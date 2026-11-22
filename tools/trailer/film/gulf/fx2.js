// 海湾战争版的特效配方（在 fx.js 的 FX 上画：序列帧、发光点、光带、灯、碎片）
//   脱壳穿甲弹的曳光、打在坦克上（钢甲火花 / 反应装甲殉爆）、殉爆喷火、残骸大火和黑烟、油井大火、热诱弹、转管炮的弹流、
//   车后的扬尘、旋翼下洗的沙尘、夜里的高炮曳光、地平线上的闪光
import * as THREE from 'three';
import { rng, smooth, clamp, lerp, fbm1 } from '../lib.js';

const C = (r, g, b) => new THREE.Color(r, g, b);
const UP = new THREE.Vector3(0, 1, 0);
const FIRE = C(1, 0.55, 0.22), FLASH = C(1, 0.82, 0.58), TRACER = C(1, 0.62, 0.3);
const fcall = (v, t) => (typeof v === 'function' ? v(t) : v);

// 脱壳穿甲弹：从炮口飞向 to（1700 米 / 秒 ≈ 4760 格 / 秒），尾部一点亮红的曳光；打到以后由别的配方画火花
export function sabot(o) {
  const { from, to, t0, speed = 4760, w = 0.5, col = TRACER, bright = 9 } = o;
  return (t, f) => {
    const a = fcall(from, t), b = fcall(to, t);
    const L = a.distanceTo(b), T = L / speed, u = t - t0;
    if (u < 0 || u > T) return;
    const d = b.clone().sub(a).normalize();
    const head = a.clone().addScaledVector(d, u * speed);
    const tail = a.clone().addScaledVector(d, Math.max(0, u * speed - Math.min(90, L * 0.08)));
    f.addStreak(tail, head, w, col, bright, 0.7, 0.0008);
    f.addGlow(head, 1.2, col, 4, 1, 0.0012);
  };
}
// 打在钢甲上：一团白亮的火花、往四面溅的火星、一点灰烟；era = 反应装甲殉爆（更大的闪光、一团灰黑烟、碎块）
export function armorHit(o) {
  const { p, t0, era = false, seed = 1, n = era ? 26 : 34, s = era ? 7 : 4 } = o;
  const R = rng(seed);
  const SP = [];
  for (let i = 0; i < n; i++) {
    const v = new THREE.Vector3(R.range(-1, 1), R.range(-0.2, 1), R.range(-1, 1)).normalize().multiplyScalar(R.range(30, era ? 70 : 110));
    SP.push({ v, life: R.range(0.25, 0.9) });
  }
  return (t, f) => {
    const u = t - t0;
    if (u < 0 || u > 4) return;
    const P = fcall(p, t);
    if (u < 0.12) f.addGlow(P, s * 2.4, FLASH, (era ? 16 : 10) * (1 - u / 0.12), 1, 0);
    f.addLight(P, FIRE, (era ? 5 : 2.5) * Math.exp(-u * 10), 90);
    for (const e of SP) {
      if (u > e.life) continue;
      const q = P.clone().addScaledVector(e.v, u).add(new THREE.Vector3(0, -0.5 * 27 * u * u, 0));
      const q0 = P.clone().addScaledVector(e.v, Math.max(0, u - 0.03)).add(new THREE.Vector3(0, -0.5 * 27 * (u - 0.03) ** 2, 0));
      f.addStreak(q0, q, 0.12, FIRE, 6 * (1 - u / e.life), 0.4, 0.0004);
    }
    if (era && u < 1.8) f.sprite('expl', P.clone().addScaledVector(UP, 1.5), s * 1.6, u / 1.8 * 120, 0.9, 1.2, [0.3, 0.28, 0.26], seed);
    if (u > 0.05) for (let i = 0; i < (era ? 6 : 3); i++) {
      const b = u - 0.05 - i * 0.05;
      if (b < 0) continue;
      f.sprite('puff', P.clone().add(new THREE.Vector3(Math.sin(i * 2.3) * 2, 1 + b * 3, Math.cos(i * 1.7) * 2)).addScaledVector(f.wind, b * 0.5), (era ? 6 : 3.5) + b * 5, 8 + b * 12, 0.55 * (1 - b / 3.8), 0, [0.42, 0.4, 0.38], i * 1.3 + seed);
    }
  };
}
// 殉爆：炮塔座圈里往上喷的火柱（一阵阵）、火星、黑烟
export function cookoff(o) {
  const { p, t0, dur = 6, seed = 3, s = 1 } = o;
  const R = rng(seed);
  const jets = [];
  for (let i = 0; i < 9; i++) jets.push({ t: R.range(0, dur * 0.7), d: R.range(0.4, 1.2), h: R.range(10, 26) * s });
  return (t, f) => {
    const u = t - t0;
    if (u < 0) return;
    const P = fcall(p, t);
    for (const j of jets) {
      const b = u - j.t;
      if (b < 0 || b > j.d) continue;
      const k = Math.sin(b / j.d * Math.PI);
      for (let i = 0; i < 4; i++) f.sprite('fire', P.clone().add(new THREE.Vector3(0, j.h * (0.2 + i * 0.22) * k, 0)), (3 + i * 1.4) * s * k, ((t * 30 + i * 13 + seed * 7) % 64 + 64) % 64, 0.95, 1.5, [0.2, 0.18, 0.16], i);
      f.addLight(P.clone().addScaledVector(UP, 6 * s), FIRE, 6 * k * s, 200);
      f.addGlow(P.clone().addScaledVector(UP, j.h * 0.4), 6 * s, FIRE, 2.5 * k, 0, 0);
    }
    if (u < dur) for (let i = 0; i < 18; i++) {   // 一直往上冒的黑烟
      const b = ((u - i * 0.35) % 7 + 7) % 7;
      if (u - i * 0.35 < 0) continue;
      f.sprite('puff', P.clone().add(new THREE.Vector3(Math.sin(i) * 1.5, 3 + b * 5 * s, Math.cos(i * 1.3) * 1.5)).addScaledVector(f.wind, b * 0.8), (4 + b * 3.2) * s, 12 + b * 6, 0.75 * (1 - b / 7) * smooth(0, 0.6, b), 0, [0.12, 0.11, 0.1], i * 0.7 + seed);
    }
  };
}
// 残骸、油井大火：火（序列帧叠几层）、闪烁的灯、又粗又高的黑烟柱（随风斜着往上，越高越散）
export function bigFire(o) {
  const { p, s = 8, t0 = -100, seed = 1, smokeH = 1, dark = 0.1, oil = false } = o;
  const R = rng(seed);
  const SM = [];
  const N = oil ? 40 : 26;
  for (let i = 0; i < N; i++) SM.push({ t: i * (oil ? 0.32 : 0.5) + R() * 0.3, x: R.range(-0.3, 0.3) * s, z: R.range(-0.3, 0.3) * s, rot: R() * 6.28, sz: R.range(0.8, 1.3) });
  const life = oil ? 13 : 13;
  return (t, f) => {
    const u = t - t0;
    if (u < 0) return;
    const P = fcall(p, t);
    const k = smooth(0, 0.8, u);
    const layers = oil ? 6 : 3;
    for (let i = 0; i < layers; i++) {
      const hgt = oil ? s * (0.35 + i * 0.42) : s * 0.42;
      const q = P.clone().add(new THREE.Vector3(Math.sin(i * 2.4 + t * 2) * s * 0.12, hgt, Math.cos(i * 1.7) * s * 0.12));
      f.sprite('fire', q, s * (oil ? 1.1 - i * 0.08 : 0.9 + 0.2 * Math.sin(i * 3.1)), ((t * 26 + i * 19 + seed * 7) % 64 + 64) % 64, k, 1.25, [0.2, 0.18, 0.16], i * 0.3);
    }
    const fl = 0.75 + 0.25 * fbm1(t * 7, seed);
    f.addLight(P.clone().addScaledVector(UP, s * 0.9), FIRE, 2.2 * k * fl * (s / 6), s * 14);
    f.addGlow(P.clone().addScaledVector(UP, s * 0.7), s * 2.6, FIRE, 0.4 * k * fl, 0, 0);
    for (const m of SM) {
      const b = ((u - m.t) % life + life) % life;
      if (u - m.t < 0) continue;
      const rise = (oil ? 1.9 : 0.75) * smokeH;
      const q = P.clone().add(new THREE.Vector3(m.x, s * 1.2 + b * s * rise, m.z)).addScaledVector(f.wind, b * b * (oil ? 0.45 : 0.25));
      f.sprite('puff', q, s * m.sz * (1.0 + b * (oil ? 0.55 : 0.35)), 14 + b * 3.5, 0.85 * smooth(0, 1, b) * (1 - b / life) * k, 0, [dark, dark * 0.95, dark * 0.9], m.rot + b * 0.12);
    }
  };
}
// 热诱弹：从 from(t) 处一串往下、往两侧抛出去的亮点，拖白烟，3 秒烧完
export function decoys(o) {
  const { from, vel, t0, n = 12, every = 0.07, seed = 5, spread = 60 } = o;
  const R = rng(seed);
  const F = [];
  for (let i = 0; i < n; i++) F.push({ t: t0 + i * every, side: i % 2 ? 1 : -1, v: new THREE.Vector3(R.range(0.5, 1) * spread, R.range(-30, -10), R.range(-20, 20)) });
  return (t, f) => {
    for (const d of F) {
      const u = t - d.t;
      if (u < 0 || u > 3.2) continue;
      const p0 = fcall(from, d.t), v0 = fcall(vel, d.t).clone().multiplyScalar(0.6).add(new THREE.Vector3(d.v.x * d.side, d.v.y, d.v.z));
      const at = b => p0.clone().addScaledVector(v0, (1 - Math.exp(-1.4 * b)) / 1.4).add(new THREE.Vector3(0, -0.5 * 27 * 0.55 * b * b, 0));
      const p = at(u), k = 1 - u / 3.2;
      f.addGlow(p, 3.2, C(1, 0.82, 0.55), 16 * k, 1, 0.0024);
      f.addLight(p, C(1, 0.75, 0.45), 14 * k, 160);
      for (let j = 1; j < 10; j++) { const b = j * 0.08; if (b > u) break; f.sprite('puff', at(u - b).add(new THREE.Vector3(0, b * 2, 0)), 1.6 + b * 9, 10 + b * 20, 0.42 * k * (1 - j / 10), 0, [1.1, 1.05, 1.0], j + d.t * 10); }
    }
  };
}
// 转管炮：一秒几十发，每 every 发一颗曳光；炮口一直在跳的火光
export function gatling(o) {
  const { from, dir, t0, t1, rate = 60, speed = 1100, every = 3, spread = 0.008, seed = 9, col = C(1, 0.5, 0.2), len = 30, maxD = 2600, w = 0.5, bright = 7 } = o;
  const R = rng(seed);
  const shots = [];
  for (let ti = t0; ti < t1; ti += 1 / rate) shots.push({ t: ti, j: new THREE.Vector3(R.gauss(), R.gauss(), R.gauss()).multiplyScalar(spread), tr: shots.length % every === 0 });
  return (t, f) => {
    const F = fcall(from, t), D = fcall(dir, t);
    if (t >= t0 && t <= t1) {
      const k = 0.7 + 0.3 * Math.sin(t * 91);
      f.addGlow(F.clone().addScaledVector(D, 1.2), 2.4, FLASH, 9 * k, 1, 0.0016);
      f.addLight(F.clone().addScaledVector(D, 2), FIRE, 4 * k, 160);
      f.sprite('mzl', F.clone().addScaledVector(D, 1.4), 3.2, (t * 60) % 9, 0.9, 1.6, [0.6, 0.58, 0.55], t * 33, D);
    }
    for (const s of shots) {
      if (!s.tr) continue;
      const u = t - s.t;
      if (u < 0) continue;
      const dist = u * speed;
      if (dist > maxD) continue;
      const Fs = fcall(from, s.t), Ds = fcall(dir, s.t).clone().add(s.j).normalize();
      const head = Fs.clone().addScaledVector(Ds, dist).add(new THREE.Vector3(0, -0.5 * 27 * u * u * 0.3, 0)), tail = Fs.clone().addScaledVector(Ds, Math.max(0, dist - len));
      f.addStreak(tail, head, w, col, bright, 0.6, 0.0007);
    }
  };
}
// 车后的扬尘：沿 path(t) 按走过的距离一团团放，往上、往后飘
export function dustTrail(o) {
  const { path, t0 = -3, t1 = 1e9, seed = 2, s = 1, gap = 9, life = 6, col = [0.86, 0.74, 0.56], alpha = 0.5, back = null } = o;
  return (t, f) => {
    let prev = null, acc = 0, k = 0;
    for (let tau = t0; tau <= Math.min(t, t1); tau += 0.05) {
      const q = path(tau);
      if (prev) acc += q.distanceTo(prev);
      prev = q;
      if (acc < gap) continue;
      acc = 0; k++;
      const b = t - tau;
      if (b > life) continue;
      const off = back ? back(tau) : new THREE.Vector3();
      const size = (5 + b * 4.5) * s;
      const pos = q.clone().add(off).add(new THREE.Vector3(Math.sin(k * 2.1) * 2 * s, size * 0.46 + b * 1.2 * s, Math.cos(k * 1.3) * 2 * s)).addScaledVector(f.wind, b * 0.9);   // 烟团下沿不插进地里（贴片和地面深度打架会出一格格的方块）
      f.sprite('puff', pos, size, 6 + b * 9, alpha * (1 - b / life) * smooth(0, 0.3, b), 0, col, k * 1.7 + seed);
    }
  };
}
// 旋翼下洗：直升机下面地上一圈往外滚的沙尘（离地越近越浓）
export function rotorWash(o) {
  const { at, ground, seed = 4, r = 30 } = o;
  const R = rng(seed);
  const P = [];
  for (let i = 0; i < 40; i++) P.push({ a: R() * Math.PI * 2, ph: R(), sz: R.range(0.7, 1.3) });
  return (t, f) => {
    const H = fcall(at, t), gy = ground(H.x, H.z);
    const alt = H.y - gy;
    const k = 1 - smooth(25, 110, alt);
    if (k <= 0.01) return;
    for (const p of P) {
      const b = ((t * 0.5 + p.ph) % 1);
      const d = r * (0.4 + b * 1.6);
      const size = (8 + b * 14) * p.sz;
      const q = new THREE.Vector3(H.x + Math.cos(p.a + b * 0.5) * d, gy + size * 0.46 + b * 4, H.z + Math.sin(p.a + b * 0.5) * d);
      f.sprite('puff', q, size, 8 + b * 20, 0.38 * k * (1 - b) * smooth(0, 0.15, b), 0, [0.85, 0.74, 0.56], p.a + b);
    }
  };
}
// 夜里的高炮：几门炮各自往天上泼曳光（弧线、一段段），每门有自己的节奏
export function aaa(o) {
  const { guns, t0 = 0, t1 = 10, seed = 11 } = o;
  const R = rng(seed);
  const shots = [];
  for (const g of guns) {
    let tt = t0 + R() * 0.8;
    while (tt < t1) {
      const burst = R.range(0.6, 1.6);
      const yaw = g.yaw + R.range(-0.6, 0.6), pitch = R.range(0.5, 1.2);
      for (let s = tt; s < tt + burst; s += 1 / (g.rate || 18)) shots.push({ t: s, p: g.p, d: new THREE.Vector3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)).add(new THREE.Vector3(R.gauss(), R.gauss(), R.gauss()).multiplyScalar(0.01)).normalize(), col: g.col || C(1, 0.4, 0.15) });
      tt += burst + R.range(0.4, 1.5);
    }
  }
  return (t, f) => {
    for (const s of shots) {
      const u = t - s.t;
      if (u < 0 || u > 4.5) continue;
      const v = 950;
      const at = b => s.p.clone().addScaledVector(s.d, v * b).add(new THREE.Vector3(0, -0.5 * 27 * b * b, 0));
      f.addStreak(at(Math.max(0, u - 0.035)), at(u), 0.9, s.col, 5 * (1 - u / 4.5), 0.5, 0.0009);
      if (u < 0.04) f.addGlow(s.p, 4, FLASH, 5, 1, 0.002);
    }
  };
}
// 地平线上的闪光（远处的空袭）：一闪一闪照亮天边
export function skyFlashes(o) {
  const { list } = o;   // [{ p, t, s }]
  return (t, f) => {
    for (const e of list) {
      const u = t - e.t;
      if (u < 0 || u > 1.8) continue;
      const k = u < 0.08 ? 1 : Math.exp(-(u - 0.08) * 3.5);
      f.addGlow(e.p, 220 * (e.s || 1), C(1, 0.7, 0.42), 6 * k, 1, 0);
      f.addGlow(e.p, 900 * (e.s || 1), C(1, 0.55, 0.3), 0.5 * k, 0, 0);
      f.addLight(e.p, C(1, 0.62, 0.35), 120 * k * (e.s || 1), 3000);
    }
  };
}
