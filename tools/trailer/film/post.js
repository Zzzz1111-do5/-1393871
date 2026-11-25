// 后期：场景（HDR）→ 泛光 → 景深 → 调色、ACES、暗角、胶片颗粒、色散、宽银幕黑边、夜视仪模式、淡入淡出
import * as THREE from 'three';

const QUAD_VS = `varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;
function pass(fs, uniforms) {
  const m = new THREE.ShaderMaterial({ vertexShader: QUAD_VS, fragmentShader: fs, uniforms, depthTest: false, depthWrite: false });
  return m;
}
export class Post {
  constructor(renderer, W, H, opt = {}) {
    this.r = renderer;
    this.W = W; this.H = H;   // 整个画面
    this.aspect = opt.aspect || 2.39;
    this.ah = Math.round(W / this.aspect / 2) * 2;   // 宽银幕的实际画面高
    const ss = opt.ss || 1;
    this.rw = Math.round(W * ss); this.rh = Math.round(this.ah * ss);
    const rtOpt = { type: THREE.HalfFloatType, depthBuffer: true };
    this.scene = new THREE.WebGLRenderTarget(this.rw, this.rh, { ...rtOpt, samples: opt.msaa ?? 4 });
    this.scene.depthTexture = new THREE.DepthTexture(this.rw, this.rh, THREE.FloatType);
    // 泛光：亮部 → 一级级缩小模糊 → 加回来
    this.levels = [];
    let w = this.rw >> 1, h = this.rh >> 1;
    for (let i = 0; i < 6; i++) {
      this.levels.push({ a: new THREE.WebGLRenderTarget(w, h, { type: THREE.HalfFloatType, depthBuffer: false }), b: new THREE.WebGLRenderTarget(w, h, { type: THREE.HalfFloatType, depthBuffer: false }), w, h });
      w = Math.max(1, w >> 1); h = Math.max(1, h >> 1);
    }
    this.dof = new THREE.WebGLRenderTarget(this.rw >> 1, this.rh >> 1, { type: THREE.HalfFloatType, depthBuffer: false });
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
    this.qs = new THREE.Scene(); this.qs.add(this.quad);
    this.qc = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.mBright = pass(`uniform sampler2D tSrc; uniform float uTh; varying vec2 vUv;
void main() { vec3 c = texture2D(tSrc, vUv).rgb; float l = max(c.r, max(c.g, c.b)); gl_FragColor = vec4(c * max(l - uTh, 0.0) / max(l, 1e-4), 1.0); }`, { tSrc: { value: null }, uTh: { value: 1.0 } });
    this.mBlur = pass(`uniform sampler2D tSrc; uniform vec2 uDir; varying vec2 vUv;
void main() { vec3 s = texture2D(tSrc, vUv).rgb * 0.227;
  s += (texture2D(tSrc, vUv + uDir * 1.385).rgb + texture2D(tSrc, vUv - uDir * 1.385).rgb) * 0.316;
  s += (texture2D(tSrc, vUv + uDir * 3.231).rgb + texture2D(tSrc, vUv - uDir * 3.231).rgb) * 0.070;
  gl_FragColor = vec4(s, 1.0); }`, { tSrc: { value: null }, uDir: { value: new THREE.Vector2() } });
    this.mDown = pass(`uniform sampler2D tSrc; uniform vec2 uPx; varying vec2 vUv;
void main() { vec3 s = texture2D(tSrc, vUv + uPx * vec2(-1., -1.)).rgb + texture2D(tSrc, vUv + uPx * vec2(1., -1.)).rgb + texture2D(tSrc, vUv + uPx * vec2(-1., 1.)).rgb + texture2D(tSrc, vUv + uPx * vec2(1., 1.)).rgb;
  gl_FragColor = vec4(s * 0.25, 1.0); }`, { tSrc: { value: null }, uPx: { value: new THREE.Vector2() } });
    // 景深：按深度算弥散圈，半分辨率黄金角采样
    this.mDof = pass(`uniform sampler2D tSrc, tDepth; uniform float uFocus, uRange, uMax, uFar, uAsp; uniform float uRadial; varying vec2 vUv;
float viewZ(vec2 uv) { float d = texture2D(tDepth, uv).r; return pow(uFar + 1.0, d) - 1.0; }
float coc(vec2 uv) { float z = viewZ(uv); float c = clamp(abs(z - uFocus) / max(uRange, 1e-3) - 0.15, 0.0, 1.0);
  c = max(c, uRadial * smoothstep(0.25, 0.8, length((uv - 0.5) * vec2(uAsp, 1.0)))); return c * uMax; }
void main() {
  float c0 = coc(vUv);
  vec3 acc = texture2D(tSrc, vUv).rgb; float wsum = 1.0;
  for (int i = 1; i < 24; i++) {
    float r = sqrt(float(i) / 24.0), a = float(i) * 2.39996;
    vec2 o = vec2(cos(a), sin(a)) * r * c0 * vec2(1.0 / uAsp, 1.0) * 0.012;
    vec2 uv = vUv + o;
    float ci = coc(uv);
    float w = smoothstep(0.0, 1.0, ci / max(c0 * r, 1e-3) + 0.2);
    acc += texture2D(tSrc, uv).rgb * w; wsum += w;
  }
  gl_FragColor = vec4(acc / wsum, c0 / max(uMax, 1e-4));
}`, { tSrc: { value: null }, tDepth: { value: null }, uFocus: { value: 100 }, uRange: { value: 100 }, uMax: { value: 0 }, uFar: { value: 1e5 }, uAsp: { value: 2.39 }, uRadial: { value: 0 } });
    this.mFinal = pass(`uniform sampler2D tSrc, tDof, tB0, tB1, tB2, tB3, tB4, tB5, tDepth;
uniform float uExp, uBloom, uTime, uGrain, uVig, uCA, uFade, uFlash, uNvg, uAsp, uBar, uSat, uContrast, uDofOn, uLift, uTint, uThermal, uHeat, uTherK, uFar;
uniform vec3 uShadowTint, uHighTint;
varying vec2 vUv;
vec3 aces(vec3 x) { const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14; return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0); }
float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void main() {
  // 宽银幕：画面只占中间一条
  float y = (vUv.y - 0.5) / uBar + 0.5;
  if (y < 0.0 || y > 1.0) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
  vec2 uv = vec2(vUv.x, y);
  vec2 cc = uv - 0.5;
  // 色散：边缘红蓝错开一点
  vec2 ca = cc * uCA * dot(cc, cc);
  // 热浪：按深度——远处的地面才抖（越远越明显），天空、近处的车不抖（原来是画面上固定一条带，地平线不在那儿时抖错地方）
  if (uHeat > 0.0) {
    float dd = texture2D(tDepth, uv).r, vz = pow(uFar + 1.0, dd) - 1.0;
    float band = smoothstep(160.0, 2400.0, vz) * step(dd, 0.99995) * (0.45 + 0.55 * exp(-pow((uv.y - 0.47) / 0.1, 2.0)));
    uv.x += uHeat * band * 0.0009 * (sin(uv.y * 210.0 + uTime * 7.0 + uv.x * 9.0) + 0.5 * sin(uv.y * 380.0 - uTime * 11.0 + uv.x * 17.0));
    uv.y += uHeat * band * 0.0004 * sin(uv.x * 140.0 + uTime * 5.0);
  }
  vec3 col = vec3(texture2D(tSrc, uv - ca).r, texture2D(tSrc, uv).g, texture2D(tSrc, uv + ca).b);
  if (uDofOn > 0.5) { vec4 d = texture2D(tDof, uv); col = mix(col, d.rgb, smoothstep(0.02, 0.25, d.a)); }
  vec3 bl = texture2D(tB0, uv).rgb * 0.30 + texture2D(tB1, uv).rgb * 0.26 + texture2D(tB2, uv).rgb * 0.2 + texture2D(tB3, uv).rgb * 0.13 + texture2D(tB4, uv).rgb * 0.07 + texture2D(tB5, uv).rgb * 0.04;
  col += bl * uBloom;
  col *= uExp;
  // 热成像（白热）：亮度 → 灰度，曲线压一下（热的东西发白、冷的地面、天空发黑），细的扫描噪声；uTherK 整体增益
  if (uThermal > 0.0) {
    float l = dot(col, vec3(0.33, 0.45, 0.22)) * uTherK;
    float g = l / (1.0 + l);
    g = smoothstep(0.02, 0.98, g);
    float nz = h12(uv * vec2(1717.0, 931.0) + fract(uTime * 7.31) * 97.0) - 0.5;
    float scan = 0.97 + 0.03 * sin(gl_FragCoord.y * 3.14159);
    vec3 th = vec3(g * scan + nz * 0.05);
    col = mix(aces(col), th, uThermal);
  } else if (uNvg > 0.0) {
    float l = dot(col, vec3(0.3, 0.55, 0.15)) * 9.0;
    vec3 nv = vec3(0.25, 1.0, 0.35) * (l / (1.0 + l)) * 1.25 + vec3(0.02, 0.06, 0.03);
    float g = h12(uv * vec2(1717.0, 931.0) + fract(uTime * 7.31) * 97.0) - 0.5;
    nv += g * 0.16 * vec3(0.4, 1.0, 0.5);
    float tube = smoothstep(0.5, 0.44, length(cc * vec2(uAsp, 1.0)) * 0.78);
    col = mix(aces(col), nv * tube, uNvg);
  } else {
    col = aces(col);
  }
  // 调色：暗部偏青、亮部偏暖，饱和度、对比、抬黑
  float L = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(L), col, uSat);
  col = mix(col, col * uShadowTint, (1.0 - smoothstep(0.0, 0.45, L)) * uTint);
  col = mix(col, col * uHighTint, smoothstep(0.35, 1.0, L) * uTint);
  col = (col - 0.5) * uContrast + 0.5;
  col = max(col, 0.0) * (1.0 - uLift) + uLift;
  // 暗角
  col *= mix(1.0, smoothstep(0.95, 0.25, length(cc * vec2(uAsp * 0.62, 1.0))), uVig);
  // 胶片颗粒（中间调最明显，24 帧跳动）
  float fr = mod(floor(uTime * 24.0), 61.0);   // 帧号取模：时间大了（片子后半段）哈希的输入太大，浮点精度不够，颗粒变成一排排规则的纹路
  float gr = h12(gl_FragCoord.xy + fr * 61.7) + h12(gl_FragCoord.xy * 0.71 + fr * 13.1) - 1.0;
  col += gr * uGrain * (0.35 + 0.65 * (1.0 - abs(L - 0.45) * 2.0));
  col = mix(col, vec3(1.0, 0.97, 0.92), uFlash);
  col *= 1.0 - uFade;
  col = pow(max(col, 0.0), vec3(1.0 / 2.2));   // 线性 → sRGB
  gl_FragColor = vec4(col, 1.0);
}`, { tSrc: { value: null }, tDof: { value: null }, tB0: { value: null }, tB1: { value: null }, tB2: { value: null }, tB3: { value: null }, tB4: { value: null }, tB5: { value: null },
      uExp: { value: 1 }, uBloom: { value: 1 }, uTime: { value: 0 }, uGrain: { value: 0.045 }, uVig: { value: 0.6 }, uCA: { value: 0.012 }, uFade: { value: 0 }, uFlash: { value: 0 }, uNvg: { value: 0 },
      uAsp: { value: this.aspect }, uBar: { value: this.ah / H }, uSat: { value: 0.92 }, uContrast: { value: 1.06 }, uDofOn: { value: 0 }, uLift: { value: 0.012 }, uTint: { value: 1 },
      uShadowTint: { value: new THREE.Vector3(0.88, 1.0, 1.1) }, uHighTint: { value: new THREE.Vector3(1.08, 1.0, 0.9) },
      uThermal: { value: 0 }, uTherK: { value: 1 }, uHeat: { value: 0 }, tDepth: { value: null }, uFar: { value: 1e5 } });
    this.set = {};
  }
  run(m) { this.quad.material = m; this.r.render(this.qs, this.qc); }
  render(scene, camera, P = {}) {
    const r = this.r;
    r.setRenderTarget(this.scene);
    r.clear();
    r.render(scene, camera);
    // 泛光
    const L = this.levels;
    this.mBright.uniforms.tSrc.value = this.scene.texture; this.mBright.uniforms.uTh.value = P.bloomTh ?? 1.1;
    r.setRenderTarget(L[0].a); this.run(this.mBright);
    for (let i = 0; i < L.length; i++) {
      const l = L[i];
      if (i > 0) { this.mDown.uniforms.tSrc.value = L[i - 1].a.texture; this.mDown.uniforms.uPx.value.set(0.5 / L[i - 1].w, 0.5 / L[i - 1].h); r.setRenderTarget(l.a); this.run(this.mDown); }
      this.mBlur.uniforms.tSrc.value = l.a.texture; this.mBlur.uniforms.uDir.value.set(1 / l.w, 0); r.setRenderTarget(l.b); this.run(this.mBlur);
      this.mBlur.uniforms.tSrc.value = l.b.texture; this.mBlur.uniforms.uDir.value.set(0, 1 / l.h); r.setRenderTarget(l.a); this.run(this.mBlur);
    }
    const F = this.mFinal.uniforms;
    // 景深
    const dofOn = (P.dof && P.dof.max > 0) ? 1 : 0;
    if (dofOn) {
      const D = this.mDof.uniforms;
      D.tSrc.value = this.scene.texture; D.tDepth.value = this.scene.depthTexture;
      D.uFocus.value = P.dof.focus; D.uRange.value = P.dof.range; D.uMax.value = P.dof.max; D.uFar.value = camera.far; D.uAsp.value = this.aspect; D.uRadial.value = P.dof.radial || 0;
      r.setRenderTarget(this.dof); this.run(this.mDof);
    }
    F.tSrc.value = this.scene.texture; F.tDof.value = this.dof.texture; F.uDofOn.value = dofOn;
    for (let i = 0; i < 6; i++) F['tB' + i].value = L[i].a.texture;
    F.uExp.value = P.exposure ?? 1; F.uBloom.value = P.bloom ?? 0.9; F.uTime.value = P.time || 0; F.uGrain.value = P.grain ?? 0.010;   // 颗粒淡一点：每帧都变的颗粒最占码率
    F.uVig.value = P.vignette ?? 0.55;
    F.uThermal.value = P.thermal || 0; F.uTherK.value = P.therK ?? 1; F.uHeat.value = P.heat || 0;
    F.tDepth.value = this.scene.depthTexture; F.uFar.value = camera.far;
    F.uCA.value = P.ca ?? 0.012; F.uFade.value = P.fade || 0; F.uFlash.value = P.flash || 0; F.uNvg.value = P.nvg || 0; F.uSat.value = P.sat ?? 0.92; F.uContrast.value = P.contrast ?? 1.06;
    F.uLift.value = P.lift ?? 0.012; F.uTint.value = P.tint ?? 1;
    r.setRenderTarget(null);
    r.setViewport(0, 0, this.W, this.H);
    this.run(this.mFinal);
  }
}
