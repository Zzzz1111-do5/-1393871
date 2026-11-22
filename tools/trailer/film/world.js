// 世界：高度雾、夜空（月亮、星星、云、天亮时的地平线）、海（涌浪几何波 + 反射 + 浅滩泡沫）、地形（游戏的高度和材质）、
//   游戏地图里的零件（碉堡、钢刺猬、码头、舰队……合并成几块网格）、灯（发光点 + 聚光灯的光柱）
import * as THREE from 'three';
import { clamp, smooth, lerp } from './lib.js';

export const G = 27.4;   // 重力（格 / 秒²：9.8 米 × 2.8）
// 涌浪：几道 Gerstner 波（方向、波长、振幅、陡度）；着色器和 JS 用同一套（船跟着浪起伏）
export const WAVES = [
  [0.35, -1.0, 150, 1.25, 0.55], [-0.6, -0.8, 92, 0.75, 0.6], [0.9, -0.35, 57, 0.42, 0.65], [-0.2, -1.0, 31, 0.22, 0.7], [0.7, 0.7, 19, 0.11, 0.6],
].map(([dx, dz, L, A, Q]) => { const l = Math.hypot(dx, dz); return { dx: dx / l, dz: dz / l, k: 2 * Math.PI / L, A, Q, c: Math.sqrt(G * L / (2 * Math.PI)) }; });
export const SEA = { amp: 1 };   // 浪的大小（镜头里调）
// 某点（x, z）在 t 时的海面高度（只算 y，不算水平挪动：船的起伏够用）
export function seaY(x, z, t) {
  let y = 0;
  for (const w of WAVES) y += w.A * SEA.amp * Math.sin(w.k * (w.dx * x + w.dz * z - w.c * t));
  return y;
}
export function seaNormal(x, z, t) {   // 海面法线（船的俯仰、横摇）
  let nx = 0, nz = 0;
  for (const w of WAVES) { const c = w.k * w.A * SEA.amp * Math.cos(w.k * (w.dx * x + w.dz * z - w.c * t)); nx -= w.dx * c; nz -= w.dz * c; }
  return new THREE.Vector3(nx, 1, nz).normalize();
}
const WAVE_GLSL = `
const int NW = ${WAVES.length};
uniform vec4 uWa[${WAVES.length}];   // dx, dz, k, A
uniform vec2 uWb[${WAVES.length}];   // Q, c
uniform float uSeaAmp;
vec3 gerstner(vec2 p, float t, out vec3 nrm, out float crest) {
  vec3 o = vec3(p.x, 0.0, p.y);
  vec3 n = vec3(0.0, 1.0, 0.0);
  crest = 0.0;
  for (int i = 0; i < NW; i++) {
    vec2 d = uWa[i].xy; float k = uWa[i].z, A = uWa[i].w * uSeaAmp, Q = uWb[i].x, c = uWb[i].y;
    float f = k * (dot(d, p) - c * t), s = sin(f), co = cos(f);
    o.x += Q * A * d.x * co; o.z += Q * A * d.y * co; o.y += A * s;
    n.x -= d.x * k * A * co; n.z -= d.y * k * A * co; n.y -= Q * k * A * s;
    crest += max(s, 0.0) * Q * k * A;
  }
  nrm = normalize(n);
  return o;
}`;

// 高度雾：贴着海面浓、往上淡（按镜头到这一点的路径积分）；所有用 fog 的材质都换成这个
export function patchFog(H = 220) {
  const C = THREE.ShaderChunk;
  C.fog_pars_vertex = `#ifdef USE_FOG
varying float vFogDepth; varying vec3 vFogW;
#endif`;
  C.fog_vertex = `#ifdef USE_FOG
vFogDepth = - mvPosition.z;
vFogW = (mvPosition.xyz - viewMatrix[3].xyz) * mat3(viewMatrix);
#endif`;
  C.fog_pars_fragment = `#ifdef USE_FOG
uniform vec3 fogColor; varying float vFogDepth; varying vec3 vFogW;
#ifdef FOG_EXP2
uniform float fogDensity;
#else
uniform float fogNear; uniform float fogFar;
#endif
float filmFog(vec3 wp) {
  vec3 d = wp - cameraPosition; float L = length(d);
  float hc = max(cameraPosition.y, 0.0), hp = max(wp.y, 0.0), k = ${(1 / H).toFixed(6)};
  float a = abs(hp - hc) > 0.5 ? (exp(-k * hc) - exp(-k * hp)) / (k * (hp - hc)) : exp(-k * hc);
  #ifdef FOG_EXP2
  return 1.0 - exp(-fogDensity * L * a);
  #else
  return smoothstep(fogNear, fogFar, L);
  #endif
}
#endif`;
  C.fog_fragment = `#ifdef USE_FOG
gl_FragColor.rgb = mix(gl_FragColor.rgb, fogColor, max(filmFog(vFogW), smoothstep(70000.0, 300000.0, length(vFogW))));
#endif`;
}
export const FOG_GLSL = (H = 220) => `
float filmFog2(vec3 wp, float dens) {
  vec3 d = wp - cameraPosition; float L = length(d);
  float hc = max(cameraPosition.y, 0.0), hp = max(wp.y, 0.0), k = ${(1 / H).toFixed(6)};
  float a = abs(hp - hc) > 0.5 ? (exp(-k * hc) - exp(-k * hp)) / (k * (hp - hc)) : exp(-k * hc);
  return 1.0 - exp(-dens * L * a);
}`;

// —— 夜空 ——
export function makeSky() {
  const mat = new THREE.ShaderMaterial({
    uniforms: { uMoon: { value: new THREE.Vector3(0.3, 0.28, -0.91).normalize() }, uSun: { value: new THREE.Vector3(0.9, -0.15, -0.3).normalize() },
      uDawn: { value: 0 }, uTime: { value: 0 }, uFog: { value: new THREE.Color(0x0c1018) }, uStars: { value: 1 }, uCloud: { value: 0.55 }, uMoonI: { value: 1 },
      uDay: { value: 0 }, uHaze: { value: new THREE.Color(0.7, 0.62, 0.5) },
      // 写实化：真实天空的 HDRI（gulf/real.js）——uHdrOn 开、按太阳方位转 uHdrRot、亮度 uHdrK、地平线一圈沙尘霾 uHdrHaze
      tHdr: { value: null }, uHdrOn: { value: 0 }, uHdrRot: { value: 0 }, uHdrK: { value: 1 }, uHdrHaze: { value: 0.5 } },
    vertexShader: `varying vec3 vDir;
#include <common>
#include <logdepthbuf_pars_vertex>
void main() { vDir = (modelMatrix * vec4(position, 0.0)).xyz; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv;
#include <logdepthbuf_vertex>
}`,
    fragmentShader: `uniform vec3 uMoon, uSun, uFog, uHaze; uniform float uDawn, uTime, uStars, uCloud, uMoonI, uDay; varying vec3 vDir;
uniform sampler2D tHdr; uniform float uHdrOn, uHdrRot, uHdrK, uHdrHaze;
#include <common>
#include <logdepthbuf_pars_fragment>
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) { vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z); }
float fbm(vec3 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * n3(p); p = p * 2.03 + 3.1; a *= 0.5; } return s; }
void main() {
  #include <logdepthbuf_fragment>
  vec3 d = normalize(vDir);
  float h = d.y;
  vec3 zen = mix(vec3(0.004, 0.0065, 0.014), vec3(0.05, 0.09, 0.2), uDawn);
  vec3 hor = uFog * 1.05;
  vec3 col = mix(hor, zen, pow(clamp(h, 0.0, 1.0), 0.42));
  // 月亮：光晕、盘面（明暗斑）、背后天空亮一点
  float md = dot(d, uMoon);
  col += vec3(0.16, 0.2, 0.3) * 0.05 * pow(max(md, 0.0), 8.0) * uMoonI + vec3(0.4, 0.45, 0.6) * 0.08 * pow(max(md, 0.0), 180.0) * uMoonI;
  // 星星：方向空间分格，每格最多一颗；越靠地平线越暗
  if (h > -0.02) {
    vec3 p = d * 220.0; vec3 c = floor(p); float r = h3(c);
    if (r > 0.86) {
      vec3 sp = c + vec3(h3(c + 7.1), h3(c + 3.3), h3(c + 1.9));
      float dd = length(p - sp);
      float tw = 0.65 + 0.35 * sin(uTime * (2.0 + 6.0 * h3(c + 5.0)) + r * 40.0);
      float b = pow(max(0.0, 1.0 - dd * 2.4), 6.0) * (r - 0.86) * 40.0 * tw;
      vec3 sc = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), h3(c + 11.0));
      col += sc * b * 0.9 * smoothstep(0.0, 0.25, h) * uStars * (1.0 - uDawn) * (1.0 - uDay);
    }
    // 银河：一条淡淡的带子
    float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.6, -0.72))) / 0.16, 2.0));
    col += vec3(0.05, 0.055, 0.075) * 0.25 * band * fbm(d * 18.0) * smoothstep(0.05, 0.4, h) * uStars * (1.0 - uDawn) * (1.0 - uDay);
  }
  // 云：天上一层，被月光照亮靠月亮那一侧的边
  float cloudOcc = 0.0;
  if (h > 0.0) {
    vec2 uv = d.xz / (h + 0.12) * 1.6 + vec2(uTime * 0.004, uTime * 0.0015);
    float c1 = fbm(vec3(uv * 1.3, 0.5)), cov = smoothstep(0.5 - uCloud * 0.25, 0.85, c1);
    float lit = 0.25 + 0.75 * pow(max(md, 0.0), 3.0);
    vec3 cc = mix(vec3(0.008, 0.01, 0.016), vec3(0.06, 0.07, 0.09) * lit * uMoonI, smoothstep(0.55, 0.95, c1));
    cc = mix(cc, vec3(0.55, 0.32, 0.22) * 0.5, uDawn * 0.8 * pow(max(dot(d, uSun) * 0.5 + 0.5, 0.0), 2.0));
    col = mix(col, cc, cov * smoothstep(0.0, 0.12, h) * 0.9);
    cloudOcc = cov * smoothstep(0.0, 0.12, h);
  }
  if (uHdrOn > 0.5) {   // 真实天空：照片里的天（星空、银河、日晕、云），地平线往下渐变成沙尘的霾
    float cr = cos(-uHdrRot), sr = sin(-uHdrRot);
    vec3 dh = vec3(d.x * cr - d.z * sr, d.y, d.x * sr + d.z * cr);
    vec3 hc = texture2D(tHdr, equirectUv(vec3(dh.x, max(dh.y, 0.002), dh.z))).rgb * uHdrK;
    float hz = uHdrHaze * exp(-max(h, 0.0) * 9.0);
    col = mix(hc, uFog, hz);
    cloudOcc = 0.0;
  }
  float ang = acos(clamp(md, -1.0, 1.0)), R = 0.016;
  if (ang < R * 1.05) {
    vec3 t1 = normalize(cross(uMoon, vec3(0.0, 1.0, 0.0))), t2 = cross(t1, uMoon);
    vec2 q = vec2(dot(d, t1), dot(d, t2)) / R;
    float mare = fbm(vec3(q * 2.2, 3.0)) * 0.55 + fbm(vec3(q * 6.0, 9.0)) * 0.25;
    float limb = sqrt(max(0.0, 1.0 - dot(q, q)));
    vec3 mc = vec3(1.0, 0.97, 0.9) * (0.62 + 0.55 * (1.0 - mare)) * (0.55 + 0.45 * limb);
    col = mix(col, mc * 5.0 * uMoonI, smoothstep(1.0, 0.94, length(q)) * (1.0 - 0.75 * cloudOcc) * step(0.001, uMoonI));
  }

  // 天亮：东边地平线一抹暖光
  float sd = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(uSun.x, 0.0, uSun.z))), 0.0);
  col += (1.0 - uHdrOn) * uDawn * (1.0 - uDay) * (vec3(1.0, 0.45, 0.16) * 0.55 * pow(sd, 3.0) + vec3(0.9, 0.55, 0.35) * 0.18) * exp(-max(h, 0.0) * 6.0);
  // 白天（沙漠）：天顶蓝、地平线一圈沙尘的暖灰，太阳四周一大团亮（米氏散射）、太阳盘；太阳低的时候整片天往橙红走
  if (uDay > 0.001 && uHdrOn < 0.5) {
    vec3 sD = normalize(uSun);
    float se = clamp(sD.y, 0.0, 1.0);
    float cs = max(dot(d, sD), 0.0);
    vec3 zen = mix(vec3(0.05, 0.1, 0.24), vec3(0.11, 0.24, 0.5), smoothstep(0.02, 0.5, se));
    vec3 dayc = mix(uHaze, zen, pow(clamp(h, 0.0, 1.0), 0.5));
    dayc = mix(dayc, uHaze * vec3(1.15, 0.8, 0.55), uDawn * pow(sd, 2.0) * exp(-max(h, 0.0) * 3.5));
    dayc += vec3(1.0, 0.8, 0.58) * (0.35 * pow(cs, 5.0) + 1.1 * pow(cs, 48.0) + 6.0 * pow(cs, 900.0)) * mix(1.0, 1.7, uDawn);
    float disc = smoothstep(0.99994, 0.99997, cs);
    dayc += mix(vec3(60.0, 54.0, 44.0), vec3(40.0, 22.0, 9.0), uDawn) * disc;
    if (h > 0.0) {   // 天上一层薄云（卷云）
      vec2 uv = d.xz / (h + 0.12) * 1.1 + vec2(uTime * 0.003, uTime * 0.001);
      float c1 = fbm(vec3(uv * vec2(3.0, 0.9), 2.5));
      float cov = smoothstep(0.62 - uCloud * 0.2, 0.95, c1) * smoothstep(0.0, 0.18, h);
      dayc = mix(dayc, mix(uHaze * 1.2, vec3(1.0, 0.75, 0.55), uDawn * pow(cs, 2.0)) * (0.85 + 0.6 * pow(cs, 3.0)), cov * 0.7);
    }
    if (h < 0.0) dayc = uHaze;
    col = mix(col, dayc, uDay);
  }
  if (h < 0.0) col = mix(col, uFog, smoothstep(0.0, -0.06, h));
  gl_FragColor = vec4(col, 1.0);
}`,
    side: THREE.BackSide, depthWrite: false, fog: false,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(1, 48, 24), mat);
  m.scale.setScalar(90000);   // 要在镜头远裁剪面（12 万）以内，不然整个天被裁掉
  m.frustumCulled = false;
  m.renderOrder = -10;
  m.userData.follow = true;
  return m;
}

// —— 海 ——
export function makeSea(renderer, D, normals, rw, rh) {
  const rt = new THREE.WebGLRenderTarget(rw, rh, { type: THREE.HalfFloatType });
  // 水深贴图（浅滩的颜色、浪花）：世界坐标，镜头附近一张细的、外面一张粗的（setDepth 按镜头换）
  const blank = new THREE.DataTexture(new Uint16Array([THREE.DataUtils.toHalfFloat(-60)]), 1, 1, THREE.RedFormat, THREE.HalfFloatType); blank.needsUpdate = true;
  normals.wrapS = normals.wrapT = THREE.RepeatWrapping;
  const uWa = WAVES.map(w => new THREE.Vector4(w.dx, w.dz, w.k, w.A)), uWb = WAVES.map(w => new THREE.Vector2(w.Q, w.c));
  const texMat = new THREE.Matrix4();
  const mat = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      uTime: { value: 0 }, uRefl: { value: rt.texture }, uTexM: { value: texMat }, uNorm: { value: normals }, uHn: { value: blank }, uHf: { value: blank },
      uHnC: { value: new THREE.Vector3(0, 0, 1) }, uHfC: { value: new THREE.Vector3(0, 0, 1) }, uMoon: { value: new THREE.Vector3() }, uMoonC: { value: new THREE.Color(0x8fa4c8) }, uDeep: { value: new THREE.Color(0x01040a) },
      uShallow: { value: new THREE.Color(0x0a1a1c) }, uSeaAmp: { value: 1 }, uWa: { value: uWa }, uWb: { value: uWb }, uReflK: { value: 1 }, uFoamK: { value: 1 },
    }]),
    vertexShader: `${WAVE_GLSL}
uniform float uTime; uniform mat4 uTexM;
varying vec3 vW; varying vec3 vN; varying float vCrest; varying vec4 vMir;
#include <common>
#include <logdepthbuf_pars_vertex>
#include <fog_pars_vertex>
void main() {
  vec3 wp = (modelMatrix * vec4(position, 1.0)).xyz;
  float fade = 1.0 - smoothstep(1500.0, 6000.0, length(wp.xz - cameraPosition.xz));
  vec3 nrm; float crest;
  vec3 g = gerstner(wp.xz, uTime, nrm, crest);
  wp = mix(vec3(wp.x, 0.0, wp.z), g, fade);
  vN = normalize(mix(vec3(0.0, 1.0, 0.0), nrm, fade)); vCrest = crest * fade;
  vW = wp;
  vMir = uTexM * vec4(wp.x, 0.0, wp.z, 1.0);
  vec4 mvPosition = viewMatrix * vec4(wp, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  #include <logdepthbuf_vertex>
  #include <fog_vertex>
}`,
    fragmentShader: `uniform float uTime, uReflK, uFoamK; uniform sampler2D uRefl, uNorm, uHn, uHf; uniform vec3 uMoon, uMoonC, uDeep, uShallow, uHnC, uHfC;
varying vec3 vW; varying vec3 vN; varying float vCrest; varying vec4 vMir;
#include <common>
#include <logdepthbuf_pars_fragment>
#include <fog_pars_fragment>
vec3 detailN(vec2 uv) {
  vec2 a = uv / 41.0 + vec2(uTime / 37.0, uTime / 53.0), b = uv / 43.0 - vec2(uTime / -41.0, uTime / 59.0);
  vec2 c = uv / 13.0 + vec2(uTime / 21.0, -uTime / 27.0), e = uv / 380.0 - vec2(uTime / 191.0, uTime / -173.0);
  vec4 nz = texture2D(uNorm, a) + texture2D(uNorm, b) + texture2D(uNorm, c) * 0.6 + texture2D(uNorm, e);
  return normalize((nz.xzy / 3.6 * 2.0 - 1.0) * vec3(1.0, 1.0, 1.0));
}
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y); }
void main() {
  #include <logdepthbuf_fragment>
  vec3 V = cameraPosition - vW; float dist = length(V); V /= dist;
  vec3 dn = detailN(vW.xz);
  float detailK = 0.55 * (1.0 - smoothstep(2500.0, 14000.0, dist));
  vec3 N = normalize(vN + vec3(dn.x, 0.0, dn.z) * detailK);
  // 反射（镜像渲染的画面，按法线扭一扭）
  vec2 ruv = vMir.xy / vMir.w + N.xz * (0.012 + 6.0 / max(dist, 30.0)) * 0.5;
  vec3 refl = texture2D(uRefl, ruv).rgb * uReflK;
  float cosT = max(dot(N, V), 0.0);
  float F = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
  // 水深（地形高度贴图）：浅的地方带点沙色、浪花
  vec2 hn = (vW.xz - uHnC.xy) / (2.0 * uHnC.z) + 0.5, hf = (vW.xz - uHfC.xy) / (2.0 * uHfC.z) + 0.5;
  float ground = (hn.x > 0.002 && hn.x < 0.998 && hn.y > 0.002 && hn.y < 0.998) ? texture2D(uHn, hn).r : ((hf.x > 0.0 && hf.x < 1.0 && hf.y > 0.0 && hf.y < 1.0) ? texture2D(uHf, hf).r : -60.0);
  float depth = max(0.0, -ground + vW.y * 0.5);
  vec3 body = mix(uShallow, uDeep, 1.0 - exp(-depth / 9.0));
  vec3 col = mix(body * (0.35 + 0.65 * max(N.y, 0.0)), refl, F);
  // 月光的高光（一条闪烁的月光路）
  vec3 R = reflect(-V, N);
  float glint = pow(vn(vW.xz * 0.8 + vec2(uTime * 0.9, -uTime * 0.6)), 6.0) * 5.0;   // 碎光：一片闪烁的亮点，不是一整团
  float sp = pow(max(dot(R, uMoon), 0.0), 110.0) * (0.05 + glint * 0.55) * 1.5;   // 海面原来看不见（绕反了），现在看得见了：月光路收窄、调暗，不盖住字幕
  col += uMoonC * sp;
  // 浪花：浪尖、浅滩、拍岸的一道道
  float n1 = vn(vW.xz / 3.5 + uTime * 0.3), n2 = vn(vW.xz / 11.0 - uTime * 0.12);
  float crestF = smoothstep(0.55, 1.0, vCrest * 1.4 + n1 * 0.35) * 0.25;
  float shore = 0.0;
  if (ground > -6.0) {
    float sw = sin(depth * 1.3 - uTime * 1.6 + n2 * 4.0) * 0.5 + 0.5;
    shore = (smoothstep(3.5, 0.0, depth) * (0.55 + 0.45 * sw) + smoothstep(1.2, 0.0, depth)) * smoothstep(0.25, 0.75, n1 * 0.6 + n2 * 0.6);
  }
  float foam = clamp(crestF + shore * 0.9, 0.0, 1.0) * uFoamK;
  col = mix(col, vec3(0.06, 0.07, 0.085) + uMoonC * 0.05 + refl * 0.25, foam);
  gl_FragColor = vec4(col, 1.0);
  #include <fog_fragment>
}`,
    fog: true,
  });
  // 网格：以镜头为中心的一圈一圈（近处密、远处疏），每帧挪到镜头下面
  const rings = [], seg = 220;
  let r = 0, dr = 0.6;
  while (r < 90000) { rings.push(r); r += dr; dr *= 1.045; }
  rings.push(150000);
  const pos = [], idx = [];
  for (let i = 0; i < rings.length; i++) for (let j = 0; j < seg; j++) { const a = j / seg * Math.PI * 2; pos.push(Math.cos(a) * rings[i], 0, Math.sin(a) * rings[i]); }
  for (let i = 0; i < rings.length - 1; i++) for (let j = 0; j < seg; j++) {
    const a = i * seg + j, b = i * seg + (j + 1) % seg, c = (i + 1) * seg + j, d = (i + 1) * seg + (j + 1) % seg;
    idx.push(a, b, c, b, d, c);   // 正面朝上（原来绕反了，从上往下看整片海被背面剔除，高处镜头看到的是海底和地形网格的锯齿边）
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.frustumCulled = false;
  mesh.receiveShadow = false;
  const mirrorCam = new THREE.PerspectiveCamera();
  const clip = new THREE.Vector4(), q = new THREE.Vector4(), plane = new THREE.Plane();
  mesh.userData.sea = true;
  // 每帧：挪到镜头下、画反射
  mesh.userData.prepare = (renderer, scene, camera, t) => {
    mat.uniforms.uTime.value = t;
    mesh.position.set(Math.round(camera.position.x / 4) * 4, 0, Math.round(camera.position.z / 4) * 4);
    mesh.rotation.y = 0;
    // 镜像镜头：关于 y = 0 翻转
    mirrorCam.copy(camera);
    mirrorCam.position.set(camera.position.x, -camera.position.y, camera.position.z);
    const e = new THREE.Euler().setFromQuaternion(camera.quaternion, 'YXZ');
    mirrorCam.rotation.set(-e.x, e.y, -e.z, 'YXZ');
    mirrorCam.updateMatrixWorld();
    mirrorCam.projectionMatrix.copy(camera.projectionMatrix);
    texMat.set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1);
    texMat.multiply(mirrorCam.projectionMatrix).multiply(mirrorCam.matrixWorldInverse);
    // 斜裁剪面：只画水面以上的东西
    plane.set(new THREE.Vector3(0, 1, 0), 0.3).applyMatrix4(mirrorCam.matrixWorldInverse);
    clip.set(plane.normal.x, plane.normal.y, plane.normal.z, plane.constant);
    const P = mirrorCam.projectionMatrix;
    q.x = (Math.sign(clip.x) + P.elements[8]) / P.elements[0];
    q.y = (Math.sign(clip.y) + P.elements[9]) / P.elements[5];
    q.z = -1; q.w = (1 + P.elements[10]) / P.elements[14];
    clip.multiplyScalar(2 / clip.dot(q));
    P.elements[2] = clip.x; P.elements[6] = clip.y; P.elements[10] = clip.z + 1; P.elements[14] = clip.w;
    mesh.visible = false;
    const sky = scene.userData.sky;
    if (sky) sky.position.copy(mirrorCam.position);
    const prevShadow = renderer.shadowMap.autoUpdate;
    renderer.shadowMap.autoUpdate = false;
    renderer.setRenderTarget(rt);
    renderer.clear();
    const lay = mirrorCam.layers.mask;
    mirrorCam.layers.disable(2);   // 第 2 层：不进反射的小东西（人、细小的特效）
    renderer.render(scene, mirrorCam);
    mirrorCam.layers.mask = lay;
    renderer.shadowMap.autoUpdate = prevShadow;
    mesh.visible = true;
    if (sky) sky.position.copy(camera.position);
  };
  mesh.userData.mat = mat;
  // 换水深贴图：near / far = [贴图, 中心 x, 中心 z, 半边长]
  mesh.userData.setDepth = (near, far) => {
    const U = mat.uniforms;
    U.uHn.value = near[0]; U.uHnC.value.set(near[1], near[2], near[3]);
    U.uHf.value = far[0]; U.uHfC.value.set(far[1], far[2], far[3]);
  };
  return mesh;
}

// —— 地形 ——
const MATC = { Sand: [0.70, 0.62, 0.45], Rock: [0.36, 0.34, 0.32], Ground: [0.36, 0.28, 0.2], Grass: [0.24, 0.3, 0.17], LeafyGrass: [0.19, 0.25, 0.14], Slate: [0.3, 0.3, 0.32] };
export function makeTerrain(D, tex, box = [-3300, -2700, 3300, 3600]) {
  const { n, R, step } = D;
  const hb = D.height, mb = D.mat;
  const i0 = Math.max(0, Math.floor((box[0] + R) / step)), i1 = Math.min(n - 1, Math.ceil((box[2] + R) / step));
  const j0 = Math.max(0, Math.floor((box[1] + R) / step)), j1 = Math.min(n - 1, Math.ceil((box[3] + R) / step));
  const H = (i, j) => hb[clamp(j, 0, n - 1) * n + clamp(i, 0, n - 1)];
  const names = D.mats.map(s => s.split('.').pop());
  const nx = i1 - i0 + 1, nz = j1 - j0 + 1;
  const pos = new Float32Array(nx * nz * 3), nor = new Float32Array(nx * nz * 3), col = new Float32Array(nx * nz * 3), wts = new Float32Array(nx * nz * 4);
  for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
    const v = (j - j0) * nx + (i - i0);
    const x = -R + i * step, z = -R + j * step, y = H(i, j);
    pos.set([x, y, z], v * 3);
    const gx = (H(i + 1, j) - H(i - 1, j)) / (2 * step), gz = (H(i, j + 1) - H(i, j - 1)) / (2 * step);
    const l = Math.hypot(gx, 1, gz);
    nor.set([-gx / l, 1 / l, -gz / l], v * 3);
    // 材质：周围 3 × 3 平均（边界软一点）
    let c = [0, 0, 0], w = [0, 0, 0, 0], cnt = 0;
    for (let b = -1; b <= 1; b++) for (let a = -1; a <= 1; a++) {
      const id = mb[clamp(j + b, 0, n - 1) * n + clamp(i + a, 0, n - 1)];
      const nm = names[id - 1] || 'Sand';
      const cc = MATC[nm] || MATC.Ground;
      c[0] += cc[0]; c[1] += cc[1]; c[2] += cc[2];
      if (nm === 'Sand') w[0]++; else if (nm === 'Grass' || nm === 'LeafyGrass') w[1]++; else if (nm === 'Rock' || nm === 'Slate') w[2]++; else w[3]++;
      cnt++;
    }
    if (y < -0.5) { c = [0.5 * cnt, 0.45 * cnt, 0.34 * cnt]; }   // 海底：湿沙
    col.set([c[0] / cnt, c[1] / cnt, c[2] / cnt], v * 3);
    wts.set([w[0] / cnt, w[1] / cnt, w[2] / cnt, w[3] / cnt], v * 4);
  }
  const idx = [];
  for (let j = 0; j < nz - 1; j++) for (let i = 0; i < nx - 1; i++) {
    const a = j * nx + i, b = a + 1, c = a + nx, d = c + 1;
    if (pos[a * 3 + 1] < -9 && pos[b * 3 + 1] < -9 && pos[c * 3 + 1] < -9 && pos[d * 3 + 1] < -9) continue;   // 深海不要
    idx.push(a, c, b, b, c, d);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.setAttribute('aW', new THREE.BufferAttribute(wts, 4));
  geo.setIndex(idx);
  const mesh = new THREE.Mesh(geo, terrainMaterial(tex));
  mesh.receiveShadow = true;
  mesh.castShadow = true;
  mesh.frustumCulled = false;
  return mesh;
}
// 沙漠的写实地表（用户 11-22：太假了）：Poly Haven 的扫描贴图（沙砾、砾漠、龟裂地、岩面，gulf/real.js loadGround）——
//   底色 = 顶点色（游戏材质的颜色和大块深浅）× 贴图 / 贴图平均色（细节）；两个尺度（2.5 米、11 米一块），都按区域随机错开采样（不重复），
//   远了先淡掉密的那层、再淡成平均色（不然密的贴图在远处叠出一道道纹）；法线贴图按世界 xz 铺；arm 的 AO 压进底色、粗糙度照贴图（不低于 0.86，沙地哑光）；
//   岩：平顶、台地顶按碎石地画；陡的崖面三向投影岩石、颜色按一层层的砂岩（不用游戏顶点色）、竖的「沙漠漆」暗纹、岩石法线
function terrainMaterialPBR(tex) {
  const P = tex.pbr;
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0 });
  mat.userData.wet = 0;
  mat.onBeforeCompile = sh => {
    const U = sh.uniforms;
    for (const k of ['sand', 'gravel', 'crack', 'rock']) {
      U[`t_${k}D`] = { value: P[k].d }; U[`t_${k}N`] = { value: P[k].n }; U[`t_${k}A`] = { value: P[k].a }; U[`u_${k}M`] = { value: P[k].mean };
    }
    U.tNoise = { value: tex.noise };
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute vec4 aW; varying vec4 vW; varying vec3 vWP;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvW = aW; vWP = (modelMatrix * vec4(position, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>
uniform sampler2D tNoise, t_sandD, t_sandN, t_sandA, t_gravelD, t_gravelN, t_gravelA, t_crackD, t_crackN, t_crackA, t_rockD, t_rockN, t_rockA;
uniform vec3 u_sandM, u_gravelM, u_crackM, u_rockM;
varying vec4 vW; varying vec3 vWP;
vec3 gNw, gCliffP; float gAO, gRough, gFar, gVeryFar;
// 不重复的采样（Quilez 的办法）：大块噪声选 8 种偏移里的两种，按噪声在两者之间过渡
vec4 gOff, gOff2; float gBl, gBl2;
void noTile(vec2 uv, vec2 uv2) {
  float l = texture2D(tNoise, uv * 0.0137).r * 8.0, ia = floor(l);
  gOff = vec4(sin(vec2(3.0, 7.0) * ia), sin(vec2(3.0, 7.0) * (ia + 1.0)));
  gBl = smoothstep(0.25, 0.75, fract(l));
  float l2 = texture2D(tNoise, uv2 * 0.031 + 0.37).g * 8.0, ib = floor(l2);
  gOff2 = vec4(sin(vec2(5.0, 11.0) * ib), sin(vec2(5.0, 11.0) * (ib + 1.0)));
  gBl2 = smoothstep(0.25, 0.75, fract(l2));
}
vec4 tex2(sampler2D T, vec2 uv) {
  vec2 dx = dFdx(uv), dy = dFdy(uv);
  return mix(textureGrad(T, uv + gOff.xy, dx, dy), textureGrad(T, uv + gOff.zw, dx, dy), gBl);
}
vec4 tex2b(sampler2D T, vec2 uv) {
  vec2 dx = dFdx(uv), dy = dFdy(uv);
  return mix(textureGrad(T, uv + gOff2.xy, dx, dy), textureGrad(T, uv + gOff2.zw, dx, dy), gBl2);
}
// 一层地表：两个尺度按大块噪声混；返回底色（除过平均色），法线（切线空间）、arm 累加进 nT / arm
vec3 layer2(sampler2D D, sampler2D N, sampler2D A, vec3 M, vec2 uv, float mixK, inout vec3 nT, inout vec3 arm, float w) {
  vec2 uv2 = mat2(0.7986, -0.6018, 0.6018, 0.7986) * uv * 0.29 + vec2(0.37, 0.11);
  float k = mix(mixK, 1.0, gFar);
  noTile(uv, uv2);
  vec3 d = mix(mix(tex2(D, uv).rgb, tex2b(D, uv2).rgb, k), M, gVeryFar);
  vec3 n = mix(mix(tex2(N, uv).xyz, tex2b(N, uv2).xyz, k) * 2.0 - 1.0, vec3(0.0, 0.0, 1.0), gVeryFar);
  vec3 a = mix(tex2(A, uv).rgb, tex2b(A, uv2).rgb, k);
  nT += n * w; arm += a * w;
  return d / max(M, vec3(0.02)) * w;
}`)
      .replace('#include <color_fragment>', `#include <color_fragment>
  {
    vec2 uv = vec2(vWP.x, -vWP.z) / 9.0;   // 2.5 米一块（1 米 = 2.8 格）
    float camD = distance(vWP, cameraPosition);
    gFar = smoothstep(120.0, 520.0, camD); gVeryFar = smoothstep(700.0, 2000.0, camD);
    vec4 nA = texture2D(tNoise, vWP.xz / 61.0), nC = texture2D(tNoise, vWP.xz / 330.0);
    float mixK = smoothstep(0.3, 0.7, nA.r * 0.6 + nC.g * 0.4);
    vec3 nT = vec3(0.0), arm = vec3(0.0), det = vec3(0.0);
    gCliffP = vec3(0.0);
    float wsum = 0.0;
    vec4 w = max(vW, 0.0);
    if (w.x > 0.01) { det += layer2(t_sandD, t_sandN, t_sandA, u_sandM, uv, mixK, nT, arm, w.x); wsum += w.x; }
    if (w.w > 0.01) { det += layer2(t_gravelD, t_gravelN, t_gravelA, u_gravelM, uv * 1.15 + 0.23, 1.0 - mixK, nT, arm, w.w); wsum += w.w; }
    if (w.y > 0.01) {   // 盐壳、柏油、水泥：亮的（盐碱滩）照龟裂地，暗的（柏油）细碎的斑
      float lum = dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11));
      float ck = smoothstep(0.25, 0.45, lum);
      vec3 nn = vec3(0.0), aa = vec3(0.0);
      vec3 dc = layer2(t_crackD, t_crackN, t_crackA, u_crackM, uv * 0.6, mixK, nn, aa, 1.0);
      det += mix(vec3(0.93 + 0.14 * nA.b), mix(vec3(1.0), dc, 0.85), ck) * w.y;
      nT += mix(vec3(0.0, 0.0, 1.0), nn, ck) * w.y; arm += mix(vec3(1.0, 0.75, 0.0), aa, ck) * w.y; wsum += w.y;
    }
    if (w.z > 0.01) {   // 岩：平的地方（方山顶、台地顶）是碎石地，陡的崖面是岩石
      vec3 cr = cross(dFdx(vWP), dFdy(vWP));
      vec3 Nw = dot(cr, cr) > 1e-12 ? normalize(cr) : vec3(0.0, 1.0, 0.0);   // 轮廓边上屏幕导数可能是零
      float cliff = smoothstep(0.82, 0.55, abs(Nw.y));
      vec3 nn = vec3(0.0), aa = vec3(0.0);
      vec3 flatD = layer2(t_gravelD, t_gravelN, t_gravelA, u_gravelM, uv * 1.07 + 0.61, mixK, nn, aa, 1.0) * vec3(0.645, 0.64, 0.59);
      vec3 bw = pow(abs(Nw), vec3(4.0)); bw /= (bw.x + bw.y + bw.z);
      vec2 px = vWP.zy, py = vec2(vWP.x, -vWP.z), pz = vWP.xy;
      vec3 d1 = texture2D(t_rockD, px / 46.0).rgb * bw.x + texture2D(t_rockD, py / 46.0).rgb * bw.y + texture2D(t_rockD, pz / 46.0).rgb * bw.z;
      vec3 d2 = texture2D(t_rockD, px / 137.0 + 0.31).rgb * bw.x + texture2D(t_rockD, py / 137.0 + 0.31).rgb * bw.y + texture2D(t_rockD, pz / 137.0 + 0.31).rgb * bw.z;
      vec3 dr = mix(d1, d2, 0.45) / max(u_rockM, vec3(0.02));
      dr = mix(vec3(dot(dr, vec3(0.333))), dr, 0.45);   // 岩石贴图本身橙一块黑一块，颜色收一大半
      vec3 ar = texture2D(t_rockA, px / 46.0).rgb * bw.x + texture2D(t_rockA, py / 46.0).rgb * bw.y + texture2D(t_rockA, pz / 46.0).rgb * bw.z;
      // 沙漠漆：崖面上从上往下一道道的暗褐色（雨水顺着流下来的痕迹），沿等高线方向变、竖着拉长
      float hz = dot(vWP.xz, normalize(vec2(-Nw.z, Nw.x) + 1e-4));
      float streak = smoothstep(0.42, 0.85, texture2D(tNoise, vec2(hz / 23.0, vWP.y / 260.0)).r * 0.7 + texture2D(tNoise, vec2(hz / 7.0, vWP.y / 90.0)).g * 0.3);
      dr *= mix(vec3(1.0), vec3(0.62, 0.55, 0.5), streak * cliff);
      // 崖面颜色不用游戏的顶点色（石灰岩一道道发白）：一层层深浅交替的黄褐色砂岩
      float yw = vWP.y + 6.0 * texture2D(tNoise, vWP.xz / 210.0).r;
      float lay = smoothstep(0.2, 0.8, fract(yw / (7.0 + 4.0 * texture2D(tNoise, vec2(yw / 90.0, 0.3)).g)));
      vec3 cliffC = mix(vec3(0.19, 0.135, 0.085), vec3(0.3, 0.215, 0.135), lay) * (0.85 + 0.3 * texture2D(tNoise, vec2(hz / 300.0, vWP.y / 400.0)).b);
      cliffC = mix(cliffC, cliffC * vec3(1.12, 0.95, 0.8), smoothstep(0.4, 0.8, texture2D(tNoise, vec2(hz / 180.0, vWP.y / 70.0)).r));   // 一片片偏红的铁锈色
      vec3 dl = vec3(mix(dot(dr, vec3(0.333)), 1.0, 0.35));
      det += mix(flatD, cliffC * mix(dl, dr, 0.3) / max(diffuseColor.rgb, vec3(0.03)), cliff) * w.z;
      vec3 tx = texture2D(t_rockN, px / 46.0).xyz * 2.0 - 1.0, tz = texture2D(t_rockN, pz / 46.0).xyz * 2.0 - 1.0;
      gCliffP += (vec3(0.0, tx.y, tx.x) * bw.x + vec3(tz.x, tz.y, 0.0) * bw.z) * cliff * w.z * 1.4;
      nT += mix(nn, vec3(0.0, 0.0, 1.0), cliff) * w.z; arm += mix(aa, ar, cliff) * w.z; wsum += w.z;
    }
    float sw = (w.x + w.w) / max(wsum, 1e-3);
    det /= max(wsum, 1e-3); nT /= max(wsum, 1e-3); arm /= max(wsum, 1e-3);
    if (wsum < 0.01) { det = vec3(1.0); nT = vec3(0.0, 0.0, 1.0); arm = vec3(1.0, 0.95, 0.0); }
    // 沙、砾石的反照率压到真实沙地（线性约 0.40 / 0.30 / 0.17）：顶点色是游戏材质的颜色，偏亮（原来的旧贴图本身暗，乘出来正好）
    det *= mix(vec3(1.0), vec3(0.645, 0.64, 0.59), sw);
    diffuseColor.rgb *= det * (0.86 + 0.28 * nC.r);
    gAO = mix(1.0, arm.r, 0.7); gRough = clamp(arm.g, 0.86, 1.0); gNw = nT;   // 沙地哑光（太光滑的话低角度看过去整片反天光、发白）
  }`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  roughnessFactor = gRough;`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
  {   // 世界 xz 铺的切线空间：T = +x、B = −z（uv.y 朝 −z），N = 几何法线；崖面的岩石法线另外按世界空间加上去
    vec3 Nw = normalize((vec4(normal, 0.0) * viewMatrix).xyz);
    // 竖直的面（陡坡、崖壁、掩体墙）上 x 轴和法线几乎平行，Gram-Schmidt 出来是零向量、normalize 成 NaN（泛光里扩成一片片黑条）：换 z 轴
    vec3 t0 = vec3(1.0, 0.0, 0.0) - Nw * Nw.x;
    if (dot(t0, t0) < 1e-4) t0 = vec3(0.0, 0.0, 1.0) - Nw * Nw.z;
    vec3 Tw = normalize(t0), Bw = cross(Nw, Tw);
    float dcam = distance(vWP, cameraPosition);
    float fade = 1.0 - smoothstep(250.0, 1400.0, dcam);   // 远了贴图的起伏糊成一片，不要它把整片地压暗
    vec3 gn = dot(gNw, gNw) > 1e-8 ? normalize(gNw) : vec3(0.0, 0.0, 1.0);
    vec3 tn = normalize(mix(vec3(0.0, 0.0, 1.0), gn, fade * 0.9));
    vec3 pw = normalize(Tw * tn.x + Bw * tn.y + Nw * tn.z + gCliffP * (1.0 - smoothstep(400.0, 2500.0, dcam)));
    normal = normalize((viewMatrix * vec4(pw, 0.0)).xyz);
  }`)
      .replace('#include <aomap_fragment>', `#include <aomap_fragment>
  reflectedLight.indirectDiffuse *= gAO; reflectedLight.directDiffuse *= mix(1.0, gAO, 0.45);`);
  };
  return mat;
}
// 地形材质：顶点色（游戏材质）× 细节贴图（沙、草、岩、土按权重 aW）、湿沙
export function terrainMaterial(tex) {
  if (tex.pbr) return terrainMaterialPBR(tex);
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0 });
  mat.userData.wet = 1;
  mat.onBeforeCompile = sh => {
    sh.uniforms.tSand = { value: tex.sand };
    sh.uniforms.tNoise = { value: tex.noise };
    sh.uniforms.tRock = { value: tex.rock || tex.sand };
    sh.uniforms.uDesert = { value: tex.desert ? 1 : 0 };
    sh.uniforms.uWet = { get value() { return mat.userData.wet; } };
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute vec4 aW; varying vec4 vW; varying vec3 vWP;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvW = aW; vWP = (modelMatrix * vec4(position, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform sampler2D tSand, tNoise, tRock; uniform float uDesert, uWet; varying vec4 vW; varying vec3 vWP;')
      .replace('#include <color_fragment>', `#include <color_fragment>
  {
    vec2 uv = vWP.xz;
    vec3 sa = texture2D(tSand, uv / 22.0).rgb * 0.6 + texture2D(tSand, uv.yx / 61.0 + 0.37).rgb * 0.4;
    sa /= vec3(0.62, 0.55, 0.45);
    vec4 nA = texture2D(tNoise, uv / 37.0), nB = texture2D(tNoise, uv / 9.0), nC = texture2D(tNoise, uv / 260.0);
    vec3 det = vW.x * sa + vW.y * vec3(0.62 + 0.75 * nA.r * nB.g) * mix(vec3(1.0), vec3(1.12, 1.05, 0.8), nC.b) + vW.z * vec3(0.6 + 0.8 * nB.r) + vW.w * vec3(0.7 + 0.6 * nA.g * nB.b);
    if (uDesert > 0.5) {
      // 沙漠：沙（贴图 + 近处的风成沙纹）、盐壳 / 柏油（几乎平的，细碎的斑）、岩石（岩石贴图）、砾石（碎点）
      float dist = distance(vWP, cameraPosition);
      float rip = sin(dot(vWP.xz, vec2(0.83, 0.56)) * 2.6 + 7.0 * texture2D(tNoise, vWP.xz / 70.0).r + 3.0 * nB.g);
      float nearK = 1.0 - smoothstep(25.0, 180.0, dist);
      vec3 rk = texture2D(tRock, uv / 26.0).rgb * 0.6 + texture2D(tRock, uv.yx / 83.0 + 0.21).rgb * 0.4;
      float rkL = dot(rk, vec3(0.333)) / 0.42;
      vec3 sandD = sa * (1.0 + 0.035 * rip * nearK);
      vec3 flatD = vec3(0.93 + 0.14 * nA.r * nB.g);
      vec3 rockD = vec3(0.55 + 0.55 * rkL) * mix(vec3(1.0), vec3(1.06, 0.97, 0.9), nA.b);
      vec3 gravD = vec3(0.72 + 0.5 * nB.r * nA.g) * (0.9 + 0.2 * step(0.72, texture2D(tNoise, uv / 3.0).g));
      det = vW.x * sandD + vW.y * flatD + vW.z * rockD + vW.w * gravD;
    }
    diffuseColor.rgb *= det * (0.82 + 0.36 * nC.r);
    float wet = smoothstep(2.2, 0.2, vWP.y) * uWet;
    diffuseColor.rgb *= 1.0 - 0.45 * wet;
  }`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  roughnessFactor = mix(roughnessFactor, 0.62, smoothstep(2.2, 0.2, vWP.y) * uWet);   // 湿沙有一点光泽（太光滑的话月亮低时整条水线发白）`);
  };
  return mat;
}
// 地形高度（双线性）：摆东西、算车在坡上的姿态
export function groundY(D, x, z) {
  const { n, R, step, height: hb } = D;
  const fx = (x + R) / step, fz = (z + R) / step;
  const i = clamp(Math.floor(fx), 0, n - 2), j = clamp(Math.floor(fz), 0, n - 2), u = clamp(fx - i, 0, 1), v = clamp(fz - j, 0, 1);
  const a = hb[j * n + i], b = hb[j * n + i + 1], c = hb[(j + 1) * n + i], d = hb[(j + 1) * n + i + 1];
  return lerp(lerp(a, b, u), lerp(c, d, u), v);
}

// —— 游戏地图里的零件：按材质合并成几块网格 ——
const SKIP = /^(MenuStage|Camera|Ents)|FarSea/;
export function makeParts(D, tex) {
  const groups = {};
  const tmp = new THREE.Matrix4(), sc = new THREE.Matrix4();
  const box = new THREE.BoxGeometry(1, 1, 1), cyl = new THREE.CylinderGeometry(0.5, 0.5, 1, 18).rotateZ(Math.PI / 2), sph = new THREE.SphereGeometry(0.5, 16, 10);
  const wedge = (() => {   // Roblox 楔形：高的一头在 +Z，斜面朝前（−Z）上方
    const g = new THREE.BufferGeometry();
    const P = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]];
    const F = [[0, 2, 1], [1, 2, 3], [2, 4, 3], [3, 4, 5], [0, 1, 4], [1, 5, 4], [0, 4, 2], [1, 3, 5]];
    const pos = [];
    for (const f of F) for (const k of f) pos.push(...P[k]);
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.computeVertexNormals();
    return g;
  })();
  const cls = m => {
    if (/Neon/.test(m)) return 'neon';
    if (/Glass/.test(m)) return 'glass';
    if (/Metal|DiamondPlate/.test(m)) return 'metal';
    if (/Concrete|Brick|Slate|Cobblestone|Rock|Granite|Pebble|Sand|Ground|Asphalt|Pavement|Grass|Mud/.test(m)) return 'stone';
    if (/Wood/.test(m)) return 'wood';
    if (/Fabric|Leather|Rubber/.test(m)) return 'fabric';
    return 'plastic';
  };
  const lamps = [];
  for (const p of D.world.parts) {
    if (SKIP.test(p.g) || p.t >= 0.98) continue;
    const c = cls(p.m);
    const geo = /Cylinder/.test(p.sh) ? cyl : /Ball|Sphere/.test(p.sh) ? sph : /Wedge/.test(p.sh) ? wedge : box;
    const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = p.cf;
    tmp.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
    sc.makeScale(p.s[0], p.s[1], p.s[2]);
    const g = geo.clone().applyMatrix4(sc).applyMatrix4(tmp);
    const nv = g.attributes.position.count;
    const color = new THREE.Color(p.c[0], p.c[1], p.c[2]).convertSRGBToLinear();
    const ca = new Float32Array(nv * 3);
    for (let i = 0; i < nv; i++) color.toArray(ca, i * 3);
    g.setAttribute('color', new THREE.BufferAttribute(ca, 3));
    // 按盒子大小给 UV（世界尺度的细节纹理）
    const pa = g.attributes.position, na = g.attributes.normal, uv = new Float32Array(nv * 2);
    for (let i = 0; i < nv; i++) {
      const ax = Math.abs(na.getX(i)), ay = Math.abs(na.getY(i));
      const X = pa.getX(i), Y = pa.getY(i), Z = pa.getZ(i);
      if (ay > 0.7) { uv[i * 2] = X / 9; uv[i * 2 + 1] = Z / 9; } else if (ax > 0.7) { uv[i * 2] = Z / 9; uv[i * 2 + 1] = Y / 9; } else { uv[i * 2] = X / 9; uv[i * 2 + 1] = Y / 9; }
    }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    const key = c + (p.t > 0.05 ? ':t' : '');
    (groups[key] = groups[key] || []).push(g.index ? g.toNonIndexed() : g);
    if (c === 'neon') lamps.push({ p: new THREE.Vector3(x, y, z), c: color, s: Math.max(...p.s), an: p.an });
  }
  const out = new THREE.Group();
  for (const [key, list] of Object.entries(groups)) {
    const c = key.split(':')[0], tr = key.endsWith(':t');
    const merged = mergeGeos(list);
    let mat;
    if (c === 'neon') mat = new THREE.MeshBasicMaterial({ vertexColors: true, color: new THREE.Color(3.2, 3.2, 3.2), fog: true });
    else mat = new THREE.MeshStandardMaterial({ vertexColors: true, map: tex.grime, roughness: { metal: 0.5, glass: 0.08, stone: 0.95, wood: 0.85, fabric: 1, plastic: 0.6 }[c],
      metalness: { metal: 0.55, glass: 0.2 }[c] || 0, transparent: tr || c === 'glass', opacity: c === 'glass' ? 0.55 : tr ? 0.6 : 1, envMapIntensity: 0.08 });
    const m = new THREE.Mesh(merged, mat);
    m.castShadow = c !== 'glass' && c !== 'neon';
    m.receiveShadow = true;
    out.add(m);
  }
  return { group: out, lamps };
}
export function mergeGeos(list) {
  let nv = 0;
  for (const g of list) nv += g.attributes.position.count;
  const P = new Float32Array(nv * 3), N = new Float32Array(nv * 3), C = new Float32Array(nv * 3), U = new Float32Array(nv * 2);
  let o = 0;
  for (const g of list) {
    const k = g.attributes.position.count;
    P.set(g.attributes.position.array, o * 3); N.set(g.attributes.normal.array, o * 3);
    if (g.attributes.color) C.set(g.attributes.color.array, o * 3); else C.fill(1, o * 3, (o + k) * 3);
    if (g.attributes.uv) U.set(g.attributes.uv.array, o * 2);
    o += k;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(P, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(N, 3));
  out.setAttribute('color', new THREE.BufferAttribute(C, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(U, 2));
  out.computeBoundingSphere();
  return out;
}

// 程序生成的贴图：噪声（RGBA 各一层）、污渍（零件表面的明暗）
export function makeNoiseTex(size = 256, seed = 1) {
  const cv = document.createElement('canvas'); cv.width = cv.height = size;
  const g = cv.getContext('2d'), im = g.createImageData(size, size);
  const lay = [];
  for (let c = 0; c < 4; c++) {
    const a = new Float32Array(size * size);
    for (let oct = 0, amp = 1, cell = size / 4; cell >= 2; oct++, amp *= 0.55, cell /= 2) {
      const m = size / cell, grid = new Float32Array((m + 1) * (m + 1));
      let s = seed * 9973 + c * 131 + oct * 17;
      const r = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
      for (let i = 0; i < grid.length; i++) grid[i] = r();
      for (let k = 0; k <= m; k++) { grid[k * (m + 1) + m] = grid[k * (m + 1)]; grid[m * (m + 1) + k] = grid[k]; }
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const fx = x / cell, fy = y / cell, ix = Math.floor(fx), iy = Math.floor(fy), u = fx - ix, v = fy - iy;
        const su = u * u * (3 - 2 * u), sv = v * v * (3 - 2 * v);
        const q = (i, j) => grid[j * (m + 1) + i];
        a[y * size + x] += amp * lerp(lerp(q(ix, iy), q(ix + 1, iy), su), lerp(q(ix, iy + 1), q(ix + 1, iy + 1), su), sv);
      }
    }
    let mn = 1e9, mx = -1e9;
    for (const v of a) { mn = Math.min(mn, v); mx = Math.max(mx, v); }
    lay.push(a.map(v => (v - mn) / (mx - mn)));
  }
  for (let i = 0; i < size * size; i++) for (let c = 0; c < 4; c++) im.data[i * 4 + c] = lay[c][i] * 255;
  g.putImageData(im, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.NoColorSpace;
  t.anisotropy = 4;
  return t;
}
export function makeGrimeTex(noise) {
  const size = 256, cv = document.createElement('canvas'); cv.width = cv.height = size;
  const g = cv.getContext('2d');
  g.drawImage(noise.image, 0, 0);
  const im = g.getImageData(0, 0, size, size);
  for (let i = 0; i < size * size; i++) {
    const v = 0.72 + 0.28 * (im.data[i * 4] / 255) * 0.6 + 0.28 * (im.data[i * 4 + 1] / 255) * 0.4;
    const k = Math.round(clamp(v, 0, 1) * 255);
    im.data[i * 4] = im.data[i * 4 + 1] = im.data[i * 4 + 2] = k; im.data[i * 4 + 3] = 255;
  }
  g.putImageData(im, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
