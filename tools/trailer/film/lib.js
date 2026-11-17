// 小工具：随机数（定种子，每次渲出来一样）、缓动、插值、样条
import * as THREE from 'three';

export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export const lerp = (a, b, u) => a + (b - a) * u;
export const sat = v => clamp(v, 0, 1);
export const smooth = (a, b, v) => { const t = sat((v - a) / (b - a)); return t * t * (3 - 2 * t); };
export const ease = u => { u = sat(u); return u * u * (3 - 2 * u); };
export const easeIn = u => { u = sat(u); return u * u * u; };
export const easeOut = u => { u = sat(u); return 1 - (1 - u) ** 3; };
export const easeIO = u => { u = sat(u); return u < 0.5 ? 4 * u * u * u : 1 - (-2 * u + 2) ** 3 / 2; };
export const DEG = Math.PI / 180;

// 定种子的随机数（mulberry32）
export function rng(seed) {
  let a = seed >>> 0;
  const f = () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  f.range = (a, b) => a + (b - a) * f();
  f.pick = arr => arr[Math.floor(f() * arr.length)];
  f.sign = () => (f() < 0.5 ? -1 : 1);
  f.gauss = () => { let s = 0; for (let i = 0; i < 4; i++) s += f(); return (s - 2) / 0.577; };
  return f;
}
// 一维平滑噪声（镜头手持晃动、火光闪烁）
export function noise1(x, seed = 0) {
  const h = i => { const s = Math.sin(i * 127.1 + seed * 311.7) * 43758.5453; return s - Math.floor(s); };
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(h(i), h(i + 1), u) * 2 - 1;
}
export const fbm1 = (x, seed = 0) => noise1(x, seed) * 0.6 + noise1(x * 2.13, seed + 1) * 0.28 + noise1(x * 4.7, seed + 2) * 0.12;

// 关键帧：[[t, 值], …]，值是数或 Vector3；按 ease 插（默认平滑）
export function keys(K, t, fn = ease) {
  if (t <= K[0][0]) return K[0][1];
  for (let i = 0; i < K.length - 1; i++) {
    const [t0, a] = K[i], [t1, b] = K[i + 1];
    if (t <= t1) {
      const u = fn((t - t0) / (t1 - t0));
      return typeof a === 'number' ? lerp(a, b, u) : a.clone().lerp(b, u);
    }
  }
  return K[K.length - 1][1];
}
// Catmull-Rom 样条（镜头、飞机航线）：pts 是 Vector3 数组，u 0–1
export function spline(pts, u) {
  const c = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
  return c.getPoint(sat(u));
}
export function splineTan(pts, u) {
  const c = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
  return c.getTangent(sat(u));
}
// 手持晃动：转一点视线（不挪镜头位置），amp 度
export function shake(cam, t, amp, freq = 1, seed = 0) {
  if (!amp) return;
  cam.rotateX(fbm1(t * freq * 1.3, seed) * amp * DEG);
  cam.rotateY(fbm1(t * freq * 1.1, seed + 7) * amp * DEG);
  cam.rotateZ(fbm1(t * freq * 0.7, seed + 13) * amp * 0.4 * DEG);
}
