// 特效：序列帧（ArmyVFX 的爆炸、火、炮口焰、烟团）、发光点、曳光 / 尾焰的光带、碎片、光柱、灯光池
//   每个特效都是「时间 → 这一刻长什么样」的纯函数（同一镜头的任意一帧都能单独渲，几个进程分头渲也一样）
import * as THREE from 'three';
import { rng, clamp, lerp, smooth, sat, noise1, fbm1 } from './lib.js';
import { FOG_GLSL } from './world.js';

export const SHEETS = { expl: { n: 11, f: 121 }, fire: { n: 8, f: 64 }, mzl: { n: 3, f: 9 }, mzla: { n: 10, f: 100 }, puff: { n: 8, f: 64, col: 1 } };
const MAX = 6000;
const LOG_V = `#include <logdepthbuf_pars_vertex>`, LOG_F = `#include <logdepthbuf_pars_fragment>`;

function instGeo(attrs, quadSegs = 1) {
  const g = new THREE.InstancedBufferGeometry();
  const base = new THREE.PlaneGeometry(1, 1, 1, quadSegs);
  g.index = base.index;
  g.setAttribute('position', base.attributes.position);
  g.setAttribute('uv', base.attributes.uv);
  for (const [k, n] of Object.entries(attrs)) {
    const a = new THREE.InstancedBufferAttribute(new Float32Array(MAX * n), n);
    a.setUsage(THREE.DynamicDrawUsage);
    g.setAttribute(k, a);
  }
  g.instanceCount = 0;
  return g;
}
// 序列帧精灵（预乘透明度）：iP 位置、iS 大小 / 长宽比、iF 帧 / 透明度 / 火光 / 无、iT 受光颜色、iR 转角 + 朝向轴
function sheetMat(tex, n, f, col) {
  return new THREE.ShaderMaterial({
    uniforms: { uT: { value: tex }, uN: { value: n }, uFr: { value: f }, uCol: { value: col ? 1 : 0 }, fogColor: { value: new THREE.Color() }, fogDensity: { value: 0 } },
    vertexShader: `attribute vec3 iP; attribute vec2 iS; attribute vec4 iF; attribute vec3 iT; attribute vec4 iR;
varying vec2 vUv; varying vec4 vF; varying vec3 vT; varying vec3 vW;
#include <common>
${LOG_V}
void main() {
  vUv = uv; vF = iF; vT = iT; vW = iP;
  vec3 R = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]), U = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
  if (dot(iR.yzw, iR.yzw) > 0.01) {   // 顺着某个轴立着（炮口焰）
    vec3 V = normalize(cameraPosition - iP);
    vec3 ax = iR.yzw - V * dot(iR.yzw, V);
    if (dot(ax, ax) > 1e-5) { U = normalize(ax); R = normalize(cross(U, V)); }
  }
  float c = cos(iR.x), s = sin(iR.x);
  vec2 q = vec2(position.x * c - position.y * s, position.x * s + position.y * c) * vec2(iS.x, iS.x * iS.y);
  vec3 wp = iP + R * q.x + U * q.y;
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  #include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform sampler2D uT; uniform float uN, uFr, uCol; uniform vec3 fogColor; uniform float fogDensity;
varying vec2 vUv; varying vec4 vF; varying vec3 vT; varying vec3 vW;
#include <common>
${LOG_F}
${FOG_GLSL()}
vec4 at(float f) { float c = mod(f, uN), r = floor(f / uN + 0.001); return texture2D(uT, (vec2(c, uN - 1.0 - r) + clamp(vUv, 0.004, 0.996)) / uN); }
void main() {
  #include <logdepthbuf_fragment>
  float f0 = floor(vF.x), w = vF.x - f0;
  vec4 t = mix(at(f0), at(min(f0 + 1.0, uFr - 1.0)), w);
  float a = t.a * vF.y;
  if (a < 0.003) discard;
  float fog = filmFog2(vW, fogDensity);
  vec3 c;
  if (uCol > 0.5) c = t.rgb * vT * a;
  else {
    float l = t.r * 0.4 + t.g * 0.6;
    vec3 sm = vT * (0.35 + 0.65 * l);
    float e = t.b * vF.z;
    vec3 fire = mix(vec3(0.95, 0.22, 0.04), vec3(1.0, 0.66, 0.26), smoothstep(0.15, 0.6, t.b)) + vec3(0.55, 0.5, 0.4) * smoothstep(0.72, 1.0, t.b);
    c = sm * a + fire * e * e * 1.5;
  }
  c = mix(c, fogColor * a, fog);
  gl_FragColor = vec4(c, a);
}`,
    transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor,
  });
}
// 发光点（相加）：iP、iS（大小、最小角大小）、iC（颜色 × 亮度）
function glowMat() {
  return new THREE.ShaderMaterial({
    uniforms: { fogColor: { value: new THREE.Color() }, fogDensity: { value: 0 } },
    vertexShader: `attribute vec3 iP; attribute vec2 iS; attribute vec4 iC; varying vec2 vUv; varying vec4 vC; varying vec3 vW;
#include <common>
${LOG_V}
void main() {
  vUv = uv; vC = iC; vW = iP;
  vec3 R = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]), U = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
  float d = length(cameraPosition - iP);
  float s = max(iS.x, d * iS.y);
  vC.rgb *= iS.x * iS.x / (s * s) * 0.85 + 0.15;   // 远处被撑大了就按面积变暗（总亮度差不多）
  vec3 wp = iP + (R * position.x + U * position.y) * s;
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  #include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform vec3 fogColor; uniform float fogDensity; varying vec2 vUv; varying vec4 vC; varying vec3 vW;
#include <common>
${LOG_F}
${FOG_GLSL()}
void main() {
  #include <logdepthbuf_fragment>
  float r = length(vUv - 0.5) * 2.0;
  float g = exp(-r * r * 9.0) * 0.75 + exp(-r * 18.0) * 0.6 * vC.a + smoothstep(0.18, 0.0, r) * 0.8 * vC.a;
  g *= smoothstep(1.0, 0.7, r);
  float fog = filmFog2(vW, fogDensity);
  gl_FragColor = vec4(vC.rgb * g * (1.0 - fog * 0.85), 1.0);
}`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
}
// 光带（相加）：从 A 到 B、宽 W、两头渐细
function streakMat() {
  return new THREE.ShaderMaterial({
    uniforms: { fogColor: { value: new THREE.Color() }, fogDensity: { value: 0 } },
    vertexShader: `attribute vec3 iA; attribute vec3 iB; attribute vec2 iW; attribute vec4 iC; varying vec2 vUv; varying vec4 vC; varying vec3 vW;
#include <common>
${LOG_V}
void main() {
  vUv = uv; vC = iC;
  vec3 P = mix(iA, iB, uv.x);
  vec3 dir = iB - iA; vec3 V = cameraPosition - P;
  vec3 side = cross(dir, V); float sl = length(side);
  side = sl > 1e-5 ? side / sl : vec3(0.0, 1.0, 0.0);
  float d = length(V);
  float w = max(iW.x, d * iW.y);
  vC.rgb *= min(1.0, iW.x / w) * 0.8 + 0.2;
  vec3 wp = P + side * (uv.y - 0.5) * w + normalize(dir) * (uv.x - 0.5) * w * 0.0;
  vW = P;
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  #include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform vec3 fogColor; uniform float fogDensity; varying vec2 vUv; varying vec4 vC; varying vec3 vW;
#include <common>
${LOG_F}
${FOG_GLSL()}
void main() {
  #include <logdepthbuf_fragment>
  float y = abs(vUv.y - 0.5) * 2.0;
  float core = exp(-y * y * 6.0) + exp(-y * 14.0) * 0.8;
  float taper = smoothstep(0.0, vC.a, vUv.x) * smoothstep(1.0, 0.92, vUv.x);
  float fog = filmFog2(vW, fogDensity);
  gl_FragColor = vec4(vC.rgb * core * taper * (1.0 - fog * 0.85), 1.0);
}`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  });
}

export class FX {
  constructor(scene, tex) {
    this.scene = scene;
    this.sheets = {};
    for (const [k, S] of Object.entries(SHEETS)) {
      const t = tex[k];
      if (!t) continue;
      t.colorSpace = S.col ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      const g = instGeo({ iP: 3, iS: 2, iF: 4, iT: 3, iR: 4 });
      const m = new THREE.Mesh(g, sheetMat(t, S.n, S.f, S.col));
      m.frustumCulled = false; m.renderOrder = 10;
      scene.add(m);
      this.sheets[k] = { mesh: m, g, list: [] };
    }
    const gg = instGeo({ iP: 3, iS: 2, iC: 4 });
    this.glow = { mesh: new THREE.Mesh(gg, glowMat()), g: gg, list: [] };
    this.glow.mesh.frustumCulled = false; this.glow.mesh.renderOrder = 12;
    scene.add(this.glow.mesh);
    const sg = instGeo({ iA: 3, iB: 3, iW: 2, iC: 4 });
    this.streak = { mesh: new THREE.Mesh(sg, streakMat()), g: sg, list: [] };
    this.streak.mesh.frustumCulled = false; this.streak.mesh.renderOrder = 11;
    scene.add(this.streak.mesh);
    // 碎片：小方块
    this.debris = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshStandardMaterial({ color: 0x1c1a18, roughness: 0.9 }), 800);
    this.debris.frustumCulled = false; this.debris.castShadow = true; this.debris.count = 0;
    scene.add(this.debris);
    this.dlist = [];
    // 灯光池（离镜头近、亮的特效才分到真的点光源）
    this.pool = [];
    for (let i = 0; i < 8; i++) { const l = new THREE.PointLight(0xffffff, 0, 100, 2); l.castShadow = false; scene.add(l); this.pool.push(l); }
    this.lights = [];
    this.effects = [];
    this.amb = new THREE.Color(0.05, 0.06, 0.085);   // 烟的底光（月光、天光）
    this.wind = new THREE.Vector3(6, 0, -2);
  }
  clear() { this.effects = []; }
  add(e) { this.effects.push(e); return e; }
  // 某点受特效灯光照多少（烟的颜色用）
  lightAt(p, base) {
    const c = base.clone();
    for (const L of this.lights) {
      const d2 = p.distanceToSquared(L.p), r = L.r;
      if (d2 > r * r * 4) continue;
      const k = L.i / (1 + d2 / (r * r * 0.06)) * 0.008;
      c.r += L.c.r * k; c.g += L.c.g * k; c.b += L.c.b * k;
    }
    return c;
  }
  sprite(sheet, p, size, frame, alpha, fire = 0, tint = null, rot = 0, axis = null, asp = 1) {
    const S = this.sheets[sheet]; if (!S || alpha <= 0.003 || size <= 0) return;
    S.list.push({ p, size, frame: clamp(frame, 0, SHEETS[sheet].f - 1.001), alpha: Math.min(1, alpha), fire, tint, rot, axis, asp });
  }
  addGlow(p, size, color, intensity = 1, core = 1, minAng = 0.0012) { this.glow.list.push({ p, size, c: color, i: intensity, core, minAng }); }
  addStreak(a, b, w, color, intensity = 1, taper = 0.15, minAng = 0.0006) { this.streak.list.push({ a, b, w, c: color, i: intensity, taper, minAng }); }
  addLight(p, color, intensity, range) { this.lights.push({ p, c: color, i: intensity, r: range }); }
  addDebris(p, s, q) { this.dlist.push({ p, s, q }); }
  update(t, camera) {
    for (const k in this.sheets) this.sheets[k].list.length = 0;
    this.glow.list.length = 0; this.streak.list.length = 0; this.lights.length = 0; this.dlist.length = 0;
    for (const e of this.effects) e(t, this);
    const cam = camera.position;
    // 烟的颜色：底光 + 附近特效的火光
    for (const k in this.sheets) {
      const S = this.sheets[k];
      S.list.sort((a, b) => b.p.distanceToSquared(cam) - a.p.distanceToSquared(cam));
      const g = S.g, n = Math.min(MAX, S.list.length);
      const P = g.attributes.iP.array, SZ = g.attributes.iS.array, F = g.attributes.iF.array, T = g.attributes.iT.array, R = g.attributes.iR.array;
      for (let i = 0; i < n; i++) {
        const o = S.list[i];
        P[i * 3] = o.p.x; P[i * 3 + 1] = o.p.y; P[i * 3 + 2] = o.p.z;
        SZ[i * 2] = o.size; SZ[i * 2 + 1] = o.asp;
        F[i * 4] = o.frame; F[i * 4 + 1] = o.alpha; F[i * 4 + 2] = o.fire; F[i * 4 + 3] = 0;
        const lc = this.lightAt(o.p, this.amb);
        const tn = o.tint || [0.9, 0.88, 0.86];
        T[i * 3] = tn[0] * lc.r * 4.5; T[i * 3 + 1] = tn[1] * lc.g * 4.5; T[i * 3 + 2] = tn[2] * lc.b * 4.5;
        R[i * 4] = o.rot; R[i * 4 + 1] = o.axis ? o.axis.x : 0; R[i * 4 + 2] = o.axis ? o.axis.y : 0; R[i * 4 + 3] = o.axis ? o.axis.z : 0;
      }
      g.instanceCount = n;
      for (const a of ['iP', 'iS', 'iF', 'iT', 'iR']) g.attributes[a].needsUpdate = true;
    }
    {
      const g = this.glow.g, L = this.glow.list, n = Math.min(MAX, L.length);
      const P = g.attributes.iP.array, SZ = g.attributes.iS.array, C = g.attributes.iC.array;
      for (let i = 0; i < n; i++) {
        const o = L[i];
        P.set([o.p.x, o.p.y, o.p.z], i * 3); SZ.set([o.size, o.minAng], i * 2); C.set([o.c.r * o.i, o.c.g * o.i, o.c.b * o.i, o.core], i * 4);
      }
      g.instanceCount = n;
      for (const a of ['iP', 'iS', 'iC']) g.attributes[a].needsUpdate = true;
    }
    {
      const g = this.streak.g, L = this.streak.list, n = Math.min(MAX, L.length);
      const A = g.attributes.iA.array, B = g.attributes.iB.array, W = g.attributes.iW.array, C = g.attributes.iC.array;
      for (let i = 0; i < n; i++) {
        const o = L[i];
        A.set([o.a.x, o.a.y, o.a.z], i * 3); B.set([o.b.x, o.b.y, o.b.z], i * 3); W.set([o.w, o.minAng], i * 2); C.set([o.c.r * o.i, o.c.g * o.i, o.c.b * o.i, o.taper], i * 4);
      }
      g.instanceCount = n;
      for (const a of ['iA', 'iB', 'iW', 'iC']) g.attributes[a].needsUpdate = true;
    }
    {
      const m = new THREE.Matrix4(), n = Math.min(800, this.dlist.length);
      for (let i = 0; i < n; i++) { const d = this.dlist[i]; m.compose(d.p, d.q, new THREE.Vector3(d.s, d.s * 0.7, d.s * 0.9)); this.debris.setMatrixAt(i, m); }
      this.debris.count = n; this.debris.instanceMatrix.needsUpdate = true;
    }
    // 灯光池
    const sc = this.lights.map(L => ({ L, s: L.i * L.r / (1 + L.p.distanceTo(cam) / 600) })).sort((a, b) => b.s - a.s);
    this.pool.forEach((l, i) => {
      const o = sc[i];
      if (!o) { l.intensity = 0; l.visible = false; return; }
      l.visible = true; l.position.copy(o.L.p); l.color.copy(o.L.c); l.intensity = o.L.i * 1000; l.distance = o.L.r * 2.5;
    });
  }
  setFog(fog) {
    const all = [...Object.values(this.sheets).map(s => s.mesh.material), this.glow.mesh.material, this.streak.mesh.material];
    for (const m of all) { m.uniforms.fogColor.value.copy(fog.color); m.uniforms.fogDensity.value = fog.density; }
  }
}

// —————— 特效配方 ——————
const UP = new THREE.Vector3(0, 1, 0);
const C = (r, g, b) => new THREE.Color(r, g, b);
const FIRE_C = C(1, 0.55, 0.22), FLASH_C = C(1, 0.8, 0.55);

// 爆炸：火球（序列帧）、闪光、灯、碎片、火星、之后的烟；water 落在水里是水柱
export function explosion(o) {
  const { p, t0, s = 20, seed = 1, water = false, debris = 18, smoke = true, dust = true, ember = 30 } = o;
  const R = rng(seed);
  const D = [];
  for (let i = 0; i < debris; i++) {
    const a = R() * Math.PI * 2, up = R.range(0.5, 1.2);
    D.push({ v: new THREE.Vector3(Math.cos(a) * R.range(0.3, 1), up, Math.sin(a) * R.range(0.3, 1)).multiplyScalar(s * R.range(1.4, 3.2)), sz: s * R.range(0.03, 0.09), w: new THREE.Vector3(R(), R(), R()).normalize(), sp: R.range(4, 14) });
  }
  const E = [];
  for (let i = 0; i < ember; i++) { const a = R() * Math.PI * 2; E.push({ v: new THREE.Vector3(Math.cos(a) * R.range(0.2, 1), R.range(0.4, 1.5), Math.sin(a) * R.range(0.2, 1)).multiplyScalar(s * R.range(1.5, 4)), life: R.range(0.8, 2.6) }); }
  const SM = [];
  for (let i = 0; i < 9; i++) SM.push({ a: R() * Math.PI * 2, d: R.range(0, s * 0.4), rise: R.range(0.15, 0.35) * s, sz: s * R.range(0.8, 1.4), t: R.range(0.15, 0.9), rot: R() * 6.28 });
  const g = 9.8 * 2.8;
  return (t, fx) => {
    const u = t - t0;
    if (u < 0) return;
    const dur = 1.8 + s * 0.012;
    // 闪光、灯
    if (u < 0.35) fx.addGlow(p.clone().addScaledVector(UP, s * 0.3), s * 3.2, FLASH_C, 9 * Math.pow(1 - u / 0.35, 2), 1, 0);
    const li = (u < 0.12 ? 1 : Math.exp(-(u - 0.12) * 2.2)) * (s / 20);
    if (li > 0.01) fx.addLight(p.clone().addScaledVector(UP, s * 0.5), FIRE_C, li * 3.5, s * 9);
    if (!water) {
      const fu = u / dur;
      if (fu < 1) fx.sprite('expl', p.clone().addScaledVector(UP, s * (0.12 + 0.45 * fu)), s * 1.7, fu * 120, 1, 1.7 * (1 - smooth(0.12, 0.55, fu)) + 0.15, [0.26, 0.24, 0.22], seed);
    } else {
      // 水柱：白色烟团往上冲再落下
      for (let i = 0; i < 7; i++) {
        const k = i / 6, h = s * (1.6 + k * 1.8) * Math.sin(Math.min(1, u / 1.6) * Math.PI * 0.9) ;
        const a = 1 - smooth(1.0, 2.8, u);
        fx.sprite('puff', p.clone().add(new THREE.Vector3(Math.sin(i * 2.1) * s * 0.18, h * (0.35 + k * 0.65), Math.cos(i * 1.7) * s * 0.18)), s * (0.8 + k * 0.5) * (0.6 + u * 0.4), 5 + u * 18, a * 0.85, 0, [1.9, 2.0, 2.2], i * 1.3);
      }
    }
    // 碎片（弹道）
    for (const d of D) {
      const ut = Math.min(u, 4);
      const q = p.clone().addScaledVector(d.v, ut); q.y -= 0.5 * g * ut * ut;
      if (q.y < p.y - 2 && ut > 0.3) continue;
      fx.addDebris(q, d.sz, new THREE.Quaternion().setFromAxisAngle(d.w, ut * d.sp));
    }
    // 火星
    for (const e of E) {
      if (u > e.life) continue;
      const q = p.clone().addScaledVector(e.v, u); q.y -= 0.5 * g * 0.35 * u * u;
      const prev = p.clone().addScaledVector(e.v, Math.max(0, u - 0.04)); prev.y -= 0.5 * g * 0.35 * Math.max(0, u - 0.04) ** 2;
      const k = 1 - u / e.life;
      fx.addStreak(prev, q, 0.25, FIRE_C, 3 * k * k, 0.3, 0.0005);
    }
    // 之后的烟（升起、变大、随风）
    if (smoke) for (const m of SM) {
      const b = u - m.t;
      if (b < 0 || b > 12) continue;
      const q = p.clone().add(new THREE.Vector3(Math.cos(m.a) * m.d, s * 0.55 + m.rise * b * 0.8, Math.sin(m.a) * m.d)).addScaledVector(fx.wind, b * 0.5);
      fx.sprite('puff', q, m.sz * (1 + b * 0.35), 12 + Math.min(51, b * 5), 0.85 * (1 - b / 12) * smooth(0, 0.6, b), 0, water ? [1.2, 1.25, 1.3] : [0.34, 0.32, 0.3], m.rot + b * 0.1);
    }
    // 地上一圈尘土
    if (dust && !water && u < 3) for (let i = 0; i < 8; i++) {
      const a = i / 8 * Math.PI * 2 + seed, r = s * (0.4 + 1.6 * (1 - Math.exp(-u * 2.5)));
      fx.sprite('puff', p.clone().add(new THREE.Vector3(Math.cos(a) * r, s * 0.15, Math.sin(a) * r)), s * 0.9, 10 + u * 8, 0.55 * (1 - u / 3), 0, [0.55, 0.5, 0.42], a);
    }
  };
}
// 炮口焰：kind 'tank' 大（mzla + 扬尘冲击波）、'gun' 舰炮 / 榴弹炮、'mg' 机枪、'rifle' 步枪
export function muzzle(o) {
  const { p, dir, t0, kind = 'tank', seed = 1 } = o;
  const big = kind === 'tank' || kind === 'gun';
  const sz = { tank: 9, gun: 14, mg: 1.6, rifle: 1.1 }[kind];
  const R = rng(seed);
  const rings = [];
  for (let i = 0; i < 10; i++) rings.push({ a: R() * Math.PI * 2, sp: R.range(0.6, 1.4) });
  return (t, fx) => {
    const u = t - (typeof t0 === 'function' ? t0() : t0);
    if (u < 0) return;
    const P = typeof p === 'function' ? p() : p, Dd = typeof dir === 'function' ? dir() : dir;
    if (big) {
      if (u < 0.32) fx.sprite('mzla', P.clone().addScaledVector(Dd, sz * 0.8), sz * 1.6, u / 0.32 * 99, 1 - smooth(0.2, 0.32, u), 1.6, [0.58, 0.56, 0.53], 0, Dd);
      if (u < 0.12) fx.addGlow(P.clone().addScaledVector(Dd, sz * 0.6), sz * 4, FLASH_C, 12 * (1 - u / 0.12), 1, 0);
      if (u < 0.5) fx.addLight(P.clone().addScaledVector(Dd, sz * 0.5), FIRE_C, 5 * Math.exp(-u * 9), sz * 22);
      // 炮口前、四周的烟环
      if (u < 5) for (const r of rings) {
        const side = new THREE.Vector3(Math.cos(r.a), Math.sin(r.a) * 0.6, Math.sin(r.a)).projectOnPlane(Dd).normalize();
        const q = P.clone().addScaledVector(Dd, sz * (0.5 + 1.8 * (1 - Math.exp(-u * 3)) * r.sp)).addScaledVector(side, sz * 0.9 * (1 - Math.exp(-u * 2.5))).addScaledVector(fx.wind, u * 0.6);
        fx.sprite('puff', q, sz * (1.0 + u * 0.45), 8 + u * 9, 0.38 * (1 - u / 5) * smooth(0, 0.08, u), 0, [0.46, 0.43, 0.39], r.a + u * 0.2);
      }
    } else {
      if (u < 0.06) {
        fx.sprite('mzl', P.clone().addScaledVector(Dd, sz * 0.6), sz * 1.4, u / 0.06 * 8, 1, 1.6, [0.6, 0.58, 0.55], seed, Dd);
        fx.addGlow(P.clone().addScaledVector(Dd, sz * 0.4), sz * 3.5, FLASH_C, 6, 1, 0.002);
        fx.addLight(P, FIRE_C, kind === 'mg' ? 0.9 : 0.5, 40);
      }
    }
  };
}
// 连发：每发曳光弹从 from 沿 dir（加散布）飞，rate 发 / 秒，每 tracerEvery 发一颗曳光
export function burst(o) {
  const { from, dir, t0, t1, rate = 10, speed = 900, color = C(1, 0.35, 0.12), spread = 0.012, seed = 1, len = 22, maxD = 2500, width = 0.55, every = 1, flash = 'mg', bright = 6 } = o;
  const R = rng(seed);
  const shots = [];
  for (let ti = t0; ti < t1; ti += 1 / rate) {
    const jit = new THREE.Vector3(R.gauss(), R.gauss(), R.gauss()).multiplyScalar(spread);
    shots.push({ t: ti + R.range(-0.2, 0.2) / rate, j: jit, tr: shots.length % every === 0 });
  }
  const mz = shots.map((s, i) => muzzle({ p: from, dir, t0: s.t, kind: flash, seed: seed * 100 + i }));
  return (t, fx) => {
    const F = typeof from === 'function' ? from(t) : from, Dd0 = typeof dir === 'function' ? dir(t) : dir;
    for (let i = 0; i < shots.length; i++) {
      const s = shots[i], u = t - s.t;
      if (u < 0) continue;
      if (u < 0.08) mz[i](t, fx);
      if (!s.tr) continue;
      const d = Dd0.clone().add(s.j).normalize();
      const dist = u * speed;
      if (dist > maxD) continue;
      const head = F.clone().addScaledVector(d, dist), tail = F.clone().addScaledVector(d, Math.max(0, dist - len));
      fx.addStreak(tail, head, width, color, bright, 0.6);
    }
  };
}
// 照明弹：从空中慢慢落（飘），一闪一闪的强光、拖一道烟
export function flare(o) {
  const { p0, t0, life = 14, seed = 1, drift = new THREE.Vector3(3, 0, -1) } = o;
  const col = C(1, 0.78, 0.52);
  return (t, fx) => {
    const u = t - t0;
    if (u < 0 || u > life) return;
    const p = flarePos(o, t);
    const k = smooth(0, 0.6, u) * (1 - smooth(life - 1.5, life, u));
    const fl = 0.82 + 0.18 * fbm1(t * 9, seed);
    fx.addGlow(p, 9, col, 18 * k * fl, 1, 0.0025);
    fx.addGlow(p, 45, col, 0.35 * k * fl, 0, 0);
    fx.addLight(p, col, 90 * k * fl, 1100);
    // 烟：往上一串
    for (let i = 1; i < 14; i++) {
      const b = i * 0.45;
      if (b > u) break;
      const q = flarePos(o, t - b).add(new THREE.Vector3(0, 1.5 * b, 0)).addScaledVector(fx.wind, b * 0.4);
      fx.sprite('puff', q, 6 + b * 2.2, 14 + b * 4, 0.42 * (1 - b / 6.3) * k, 0, [0.85, 0.8, 0.75], i);
    }
  };
}
export function flarePos(o, t) {
  const { p0, t0, seed = 1, drift = new THREE.Vector3(3, 0, -1) } = o;
  const u = Math.max(0, t - t0);
  return p0.clone().add(new THREE.Vector3(Math.sin(u * 0.7 + seed) * 2.5, -u * 4.2, Math.cos(u * 0.5 + seed) * 2)).addScaledVector(drift, u);
}
// 着火（残骸、建筑）：循环的火焰序列帧 + 闪烁的灯 + 烟柱
export function fire(o) {
  const { p, s = 6, t0 = -100, seed = 1, smoke = true } = o;
  const R = rng(seed);
  const SM = [];
  for (let i = 0; i < 26; i++) SM.push({ t: i * 0.5 + R() * 0.4, x: R.range(-0.4, 0.4) * s, z: R.range(-0.4, 0.4) * s, rot: R() * 6.28, sz: R.range(0.8, 1.3) });
  return (t, fx) => {
    const u = t - t0;
    if (u < 0) return;
    const k = smooth(0, 0.8, u);
    for (let i = 0; i < 3; i++) {
      const q = p.clone().add(new THREE.Vector3((i - 1) * s * 0.3, s * 0.42, Math.sin(i * 2.4) * s * 0.2));
      fx.sprite('fire', q, s * (0.9 + 0.2 * Math.sin(i * 3.1)), ((t * 24 + i * 23 + seed * 7) % 64 + 64) % 64, k, 1.05, [0.2, 0.18, 0.16], i * 0.3);
    }
    const fl = 0.75 + 0.25 * fbm1(t * 7, seed);
    fx.addLight(p.clone().addScaledVector(UP, s * 0.6), FIRE_C, 1.6 * k * fl * (s / 6), s * 12);
    fx.addGlow(p.clone().addScaledVector(UP, s * 0.4), s * 2.2, FIRE_C, 0.35 * k * fl, 0, 0);
    if (smoke) for (const m of SM) {
      const b = ((u - m.t) % 13 + 13) % 13;
      if (u - m.t < 0) continue;
      const q = p.clone().add(new THREE.Vector3(m.x, s * 0.9 + b * s * 0.55, m.z)).addScaledVector(fx.wind, b * 0.7);
      fx.sprite('puff', q, s * m.sz * (0.9 + b * 0.35), 14 + b * 3.5, 0.7 * smooth(0, 1, b) * (1 - b / 13) * k, 0, [0.28, 0.26, 0.25], m.rot + b * 0.12);
    }
  };
}
// 导弹 / 火箭：沿 path(τ) 飞，尾焰发光 + 灯 + 一路的烟
export function missile(o) {
  const { path, t0, t1, seed = 1, smoke = true, col = C(1, 0.7, 0.4), size = 1, smokeLife = 7, burn = 99 } = o;
  return (t, fx) => {
    const u = t - t0;
    if (u < 0) return;
    const tt = Math.min(t, t1);
    const p = path(tt), p2 = path(tt - 0.03);
    const d = p.clone().sub(p2).normalize();
    const on = t < t1 && u < burn;
    if (on) {
      fx.addGlow(p, 4 * size, col, 8, 1, 0.0018);
      fx.addStreak(p, p.clone().addScaledVector(d, -9 * size), 2.2 * size, col, 5, 0.05, 0.0008);
      fx.addLight(p, col, 2.2 * size, 260 * size);
    }
    if (smoke) {
      const step = 0.03;
      for (let tau = Math.max(t0, t - smokeLife); tau < Math.min(t, t1, t0 + burn); tau += step) {
        const b = t - tau;
        const q = path(tau).addScaledVector(fx.wind, b * 0.6).add(new THREE.Vector3(0, b * 0.8, 0));
        const a = 0.5 * (1 - b / smokeLife) * smooth(0, 0.15, b);
        fx.sprite('puff', q, (2.2 + b * 2.8) * size, 10 + b * 6, a, 0, [0.9, 0.88, 0.85], tau * 37);
      }
    }
  };
}
// 浪花：船头、船尾、气垫艇四周的水雾
export function spray(o) {
  const { at, t0 = -1e9, t1 = 1e9, rate = 20, size = 4, seed = 1, up = 6, life = 1.6, tint = [1.5, 1.6, 1.8], alpha = 0.5 } = o;
  const R = rng(seed);
  const N = 400, P = [];
  for (let i = 0; i < N; i++) P.push({ o: R(), x: R.range(-1, 1), z: R.range(-1, 1), v: R.range(0.6, 1.4), rot: R() * 6.28 });
  return (t, fx) => {
    if (t < t0 || t > t1 + life) return;
    for (let i = 0; i < Math.min(N, rate * life); i++) {
      const q = P[i];
      const birth = Math.floor((t - q.o * life) / life) * life + q.o * life;
      const b = t - birth;
      if (birth < t0 || birth > t1) continue;
      const base = at(birth, q);
      if (!base) continue;
      const pos = base.clone().add(new THREE.Vector3(0, up * q.v * b - 0.5 * 27 * b * b * 0.5, 0)).addScaledVector(fx.wind, b * 0.4);
      fx.sprite('puff', pos, size * (0.6 + b * 0.8) * q.v, 4 + b / life * 30, alpha * (1 - b / life) * smooth(0, 0.08, b), 0, tint, q.rot);
    }
  };
}
// 光柱（探照灯、灯塔）：圆锥，沿轴越远越淡，迎着看更亮
export function beamMesh(len, angle, color, k = 1) {
  const r = Math.tan(angle) * len;
  const g = new THREE.CylinderGeometry(0.6, r, len, 32, 12, true).translate(0, -len / 2, 0).rotateX(-Math.PI / 2);   // 从原点朝 −Z 射出去
  const m = new THREE.ShaderMaterial({
    uniforms: { uC: { value: color }, uK: { value: k }, uLen: { value: len }, fogDensity: { value: 0 }, fogColor: { value: new THREE.Color() } },
    vertexShader: `varying vec3 vW; varying vec3 vN; varying float vZ;
#include <common>
${LOG_V}
void main() { vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal); vZ = -position.z; gl_Position = projectionMatrix * viewMatrix * w;
#include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform vec3 uC; uniform float uK, uLen, fogDensity; uniform vec3 fogColor; varying vec3 vW; varying vec3 vN; varying float vZ;
#include <common>
${LOG_F}
${FOG_GLSL()}
void main() {
  #include <logdepthbuf_fragment>
  vec3 V = normalize(cameraPosition - vW);
  float edge = pow(abs(dot(V, vN)), 1.6);
  float along = exp(-vZ / uLen * 3.2) * smoothstep(0.0, uLen * 0.02, vZ);
  float fog = filmFog2(vW, fogDensity);
  gl_FragColor = vec4(uC * uK * edge * along * (1.0 - fog * 0.7) * 0.18, 1.0);
}`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(g, m);
  mesh.frustumCulled = false;
  mesh.renderOrder = 9;
  return mesh;
}
// 加力尾焰：喷口后面一截发光的锥（菱形马赫环）
export function flameMesh(r, len) {
  const g = new THREE.CylinderGeometry(r * 0.55, r * 0.95, len, 20, 16, true).translate(0, -len / 2, 0).rotateX(Math.PI / 2);   // 从原点朝 +Z（机尾方向）
  const m = new THREE.ShaderMaterial({
    uniforms: { uK: { value: 1 }, uLen: { value: len }, uT: { value: 0 } },
    vertexShader: `varying float vZ; varying vec3 vN; varying vec3 vW;
#include <common>
${LOG_V}
void main() { vZ = position.z; vN = normalize(mat3(modelMatrix) * normal); vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w;
#include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform float uK, uLen, uT; varying float vZ; varying vec3 vN; varying vec3 vW;
#include <common>
${LOG_F}
void main() {
  #include <logdepthbuf_fragment>
  float z = clamp(vZ / uLen, 0.0, 1.0);
  vec3 V = normalize(cameraPosition - vW);
  float edge = pow(abs(dot(V, vN)), 0.8);
  float diamonds = 0.6 + 0.4 * pow(abs(sin(z * 18.0 - uT * 3.0)), 3.0) * (1.0 - z);
  vec3 c = mix(vec3(1.0, 0.85, 0.65), vec3(1.0, 0.42, 0.12), smoothstep(0.0, 0.5, z));
  c = mix(c, vec3(0.5, 0.35, 0.9), smoothstep(0.55, 1.0, z) * 0.5);
  gl_FragColor = vec4(c * edge * diamonds * (1.0 - z) * (1.0 - z) * uK * 3.0, 1.0);
}`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(g, m);
  mesh.frustumCulled = false;
  return mesh;
}
