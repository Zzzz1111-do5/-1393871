// 片子里放大的地图（用户：「视频里这个地图又小又怪」「主要地图太小了」，选了「只放大片子里的地图」——Roblox 游戏本身不动）
//   游戏的地图（Map.lua：主岛东西 3000 格 ≈ 1 公里，一艘 055 就有 500 格长）布局照旧，按离抢滩点 F 的远近放大：
//   抢滩那一片（蓝滩、两个碉堡、坦克上岸的地方，半径 R0 以内）原样不动——近景镜头都是照它摆的；往外越远放得越大，远处是 K 倍；
//   高处也是越远越高（只放大高出 BASE 的那部分：海滩、机场、港口这些平地原样，山才变高），山上加岩脊、沟壑的起伏；
//   海底换成平滑的（游戏里登陆航道两边是一道道台阶，浅滩的浪花描出一块块方格）；再补几座远处的岛、北边海平线上一道大陆的山
//   世界坐标 ↔ 游戏坐标：w2s / s2w（沿着从 F 出发的射线伸缩）；世界里一点的高度 heightAt；地形网格 bigTerrainGeo（离镜头近的地方密、远处疏）
import * as THREE from 'three';
import { clamp, lerp, smooth, rng } from './lib.js';

export const BIG = { fx: 345, fz: -770, R0: 320, K: 5, L: 520, V: 4.0, VW: 1700, BASE: 40, id: false, desert: false };
// desert：海湾战争版的沙漠地图（MapDesert.lua）——没有海、不补远处的岛和大陆；高度两级网格（近处细 D.height、整张图粗 D.height2）
// 剪辑版本可以换配置（第三版 v3 用游戏现在的地图：已经放大 3 倍，id = true 原样用，不再放大、不扭岸线、不加山脊）
export function bigConfig(o) { Object.assign(BIG, o); }

// —— 噪声（定种子的 Perlin、山脊、分形）——
const PERM = new Uint16Array(512), GX = new Float32Array(256), GY = new Float32Array(256);
{
  const r = rng(1337), p = [...Array(256).keys()];
  for (let i = 255; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [p[i], p[j]] = [p[j], p[i]]; }
  for (let i = 0; i < 512; i++) PERM[i] = p[i & 255];
  for (let i = 0; i < 256; i++) { const a = r() * Math.PI * 2; GX[i] = Math.cos(a); GY[i] = Math.sin(a); }
}
export function perlin(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, X = xi & 255, Y = yi & 255;
  const h00 = PERM[PERM[X] + Y], h10 = PERM[PERM[X + 1] + Y], h01 = PERM[PERM[X] + Y + 1], h11 = PERM[PERM[X + 1] + Y + 1];
  const u = xf * xf * xf * (xf * (xf * 6 - 15) + 10), v = yf * yf * yf * (yf * (yf * 6 - 15) + 10);
  const a = GX[h00] * xf + GY[h00] * yf, b = GX[h10] * (xf - 1) + GY[h10] * yf, c = GX[h01] * xf + GY[h01] * (yf - 1), d = GX[h11] * (xf - 1) + GY[h11] * (yf - 1);
  return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 1.41;   // 约 −1 … 1
}
export function fbm(x, y, oct = 4) {
  let s = 0, a = 0.5, f = 1, n = 0;
  for (let i = 0; i < oct; i++) { s += a * perlin(x * f + i * 31.7, y * f - i * 17.3); n += a; a *= 0.5; f *= 2.02; }
  return s / n;
}
// 山脊：1 − |噪声| 的平方叠起来（前一层高的地方后一层才显，山脊尖、山谷圆），约 0 … 1
export function ridged(x, y, oct = 5) {
  let s = 0, a = 0.5, f = 1, w = 1, n = 0;
  const wx = x + 0.35 * perlin(x * 0.6 + 5.2, y * 0.6), wy = y + 0.35 * perlin(x * 0.6, y * 0.6 - 3.1);   // 扭一扭，不要一条条直的
  for (let i = 0; i < oct; i++) {
    let v = 1 - Math.abs(perlin(wx * f + i * 13.1, wy * f - i * 7.7));
    v *= v; v *= w; w = clamp(v * 1.7, 0, 1);
    s += v * a; n += a; a *= 0.5; f *= 2.07;
  }
  return s / n;
}

// —— 世界 ↔ 游戏 ——
const sOf = D => D <= BIG.R0 ? D : BIG.R0 + (D - BIG.R0) / BIG.K + (1 - 1 / BIG.K) * BIG.L * (1 - Math.exp(-(D - BIG.R0) / BIG.L));
const sDer = D => D <= BIG.R0 ? 1 : 1 / BIG.K + (1 - 1 / BIG.K) * Math.exp(-(D - BIG.R0) / BIG.L);
function dOf(s) {   // sOf 的反函数（牛顿法）
  if (s <= BIG.R0) return s;
  let D = BIG.R0 + BIG.K * Math.max(0, s - BIG.R0 - (1 - 1 / BIG.K) * BIG.L * 0.6);
  for (let i = 0; i < 30; i++) { const e = sOf(D) - s; if (Math.abs(e) < 1e-4) break; D = Math.max(BIG.R0, D - e / sDer(D)); }
  return D;
}
export function w2s(x, z) {
  if (BIG.id) return [x, z];
  const dx = x - BIG.fx, dz = z - BIG.fz, D = Math.hypot(dx, dz);
  if (D <= BIG.R0) return [x, z];
  const k = sOf(D) / D;
  return [BIG.fx + dx * k, BIG.fz + dz * k];
}
export function s2w(x, z) {
  if (BIG.id) return [x, z];
  const dx = x - BIG.fx, dz = z - BIG.fz, s = Math.hypot(dx, dz);
  if (s <= BIG.R0) return [x, z];
  const k = dOf(s) / s;
  return [BIG.fx + dx * k, BIG.fz + dz * k];
}
export const s2wV = v => { const [x, z] = s2w(v.x, v.z); return new THREE.Vector3(x, v.y, z); };

// —— 游戏地形（数据）：原样的高度 srcH0（摆零件用）、海底抹平的 Hs（双三次插值，没有方格感）——
let G = null;
export function initBigMap(D) {
  const { n, R, step } = D, H0 = D.height;
  const A = new Float32Array(n * n);
  for (let i = 0; i < n * n; i++) A[i] = Math.min(H0[i], 0);
  // 去掉南边攻方的集结驳船（游戏里海上一块平台，片子里舰队在更远处，不要它）
  if (D.world.barge) {
    const b = D.world.barge;
    for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
      const x = -R + i * step, z = -R + j * step;
      if (Math.abs(x - b.x) < b.L / 2 + 24 && Math.abs(z - b.z) < b.W / 2 + 24) A[j * n + i] = -12;
    }
  }
  // 海底：三遍盒式模糊（半径 6 格 = 48 格）≈ 高斯
  const tmp = new Float32Array(n * n), rad = 6;
  for (let pass = 0; pass < 3; pass++) {
    for (let j = 0; j < n; j++) { let s = 0; for (let i = -rad; i <= rad; i++) s += A[j * n + clamp(i, 0, n - 1)]; for (let i = 0; i < n; i++) { tmp[j * n + i] = s / (2 * rad + 1); s += A[j * n + clamp(i + rad + 1, 0, n - 1)] - A[j * n + clamp(i - rad, 0, n - 1)]; } }
    for (let i = 0; i < n; i++) { let s = 0; for (let j = -rad; j <= rad; j++) s += tmp[clamp(j, 0, n - 1) * n + i]; for (let j = 0; j < n; j++) { A[j * n + i] = s / (2 * rad + 1); s += tmp[clamp(j + rad + 1, 0, n - 1) * n + i] - tmp[clamp(j - rad, 0, n - 1) * n + i]; } }
  }
  const Hs = new Float32Array(n * n);
  for (let i = 0; i < n * n; i++) Hs[i] = H0[i] > 0 ? H0[i] : Math.min(A[i], -0.05);
  if (D.world.barge) {   // 驳船那块（原来是高出海面的平台）
    const b = D.world.barge;
    for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
      const x = -R + i * step, z = -R + j * step;
      if (Math.abs(x - b.x) < b.L / 2 + 24 && Math.abs(z - b.z) < b.W / 2 + 24) Hs[j * n + i] = Math.min(Hs[j * n + i], -12);
    }
  }
  G = { n, R, step, H0, Hs, mat: D.mat, names: D.mats.map(s => s.split('.').pop()) };
  G2 = D.coarse ? { n: D.coarse.n, R: D.coarse.R, step: D.coarse.step, H0: D.height2, Hs: D.height2, mat: D.mat2, names: G.names } : null;
}
let G2 = null;
// 细网格里头（离边 FB 格以内慢慢换成粗网格，接缝不跳）
const FB = 600;
function fineW(x, z) {
  if (!G2) return 1;
  const e = G.R - 3 * G.step - Math.max(Math.abs(x), Math.abs(z));
  return smooth(0, FB, e);
}
function bicub(g, x, z) {
  const { n, R, step, Hs } = g;
  const fx = (x + R) / step, fz = (z + R) / step;
  const i = Math.floor(fx), j = Math.floor(fz);
  if (i < 1 || j < 1 || i > n - 3 || j > n - 3) return null;
  const u = fx - i, v = fz - j;
  const r = jj => { const o = jj * n + i; return cub(Hs[o - 1], Hs[o], Hs[o + 1], Hs[o + 2], u); };
  return cub(r(j - 1), r(j), r(j + 1), r(j + 2), v);
}
const cub = (p0, p1, p2, p3, t) => p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)));
// 沙漠图的断崖线（照 MapDesert.lua escRaw 抄的）：地图数据外接着铺北边的台地，不在图边上一刀切成直线
const ESC_R0 = 38912;
const escRaw = x => -24500 + 1300 * Math.sin(x / 6600 + 0.9) + 460 * Math.sin(x / 2300 + 2.6) + 170 * Math.sin(x / 770 + 4.4) - 24000 * smooth(ESC_R0 - 12000, ESC_R0 + 3000, Math.abs(x));
const outH = (x, z) => 12 + 60 * smooth(-200, 300, escRaw(x) - z);
function srcH(x, z) {   // 抹平海底后的游戏高度（双三次）
  if (G2) {
    const w = fineW(x, z);
    const c = w < 1 ? (bicub(G2, x, z) ?? outH(x, z)) : 0;
    if (w <= 0) return c;
    const f = bicub(G, x, z) ?? c;
    return lerp(c, f, w);
  }
  const { n, R, step, Hs } = G;
  const fx = (x + R) / step, fz = (z + R) / step;
  const i = Math.floor(fx), j = Math.floor(fz);
  if (i < 1 || j < 1 || i > n - 3 || j > n - 3) return -12;
  const u = fx - i, v = fz - j;
  const r = jj => { const o = jj * n + i; return cub(Hs[o - 1], Hs[o], Hs[o + 1], Hs[o + 2], u); };
  return cub(r(j - 1), r(j), r(j + 1), r(j + 2), v);
}
export function srcH0(x, z) {   // 游戏里原样的高度（双线性）：零件原来是照它摆的
  const { n, R, step, H0 } = G;
  const fx = clamp((x + R) / step, 0, n - 1.001), fz = clamp((z + R) / step, 0, n - 1.001);
  const i = Math.floor(fx), j = Math.floor(fz), u = fx - i, v = fz - j;
  const a = H0[j * n + i], b = H0[j * n + i + 1], c = H0[(j + 1) * n + i], d = H0[(j + 1) * n + i + 1];
  return lerp(lerp(a, b, u), lerp(c, d, u), v);
}
function srcMat(x, z) {
  const g = (G2 && fineW(x, z) < 0.5) ? G2 : G;
  const { n, R, step, mat, names } = g;
  const i = clamp(Math.round((x + R) / step), 0, n - 1), j = clamp(Math.round((z + R) / step), 0, n - 1);
  return names[mat[j * n + i] - 1] || 'Sand';
}

// —— 远处补的岛、北边的大陆（世界坐标）——
const EXTRA = [
  { x: 19500, z: -9500, a: 3400, b: 2500, h: 1050, s: 1 },
  { x: -21000, z: -6500, a: 4200, b: 2800, h: 1300, s: 2 },
  { x: 10500, z: -17500, a: 2800, b: 1900, h: 760, s: 3 },
  { x: -12500, z: -19000, a: 3000, b: 2100, h: 900, s: 4 },
  { x: 26000, z: 4000, a: 2600, b: 2000, h: 640, s: 5 },
];
function extra(x, z) {
  let h = -1e9;
  if (BIG.desert) return h;
  for (const I of EXTRA) {
    const u = (x - I.x) / I.a, v = (z - I.z) / I.b, r = Math.hypot(u, v);
    if (r > 1.5) continue;
    const ang = Math.atan2(v, u);
    const t = r / (1 + 0.16 * Math.sin(ang * 3 + I.s) + 0.09 * Math.sin(ang * 7 + I.s * 2.3) + 0.06 * perlin(x / 900, z / 900));
    const body = Math.max(0, 1 - t * t);
    const hh = I.h * Math.pow(body, 1.25) * (0.55 + 0.7 * ridged(x / 2400 + I.s * 7.3, z / 2400 - I.s * 3.1)) + 14 * body - 40 * smooth(0.95, 1.4, t);
    h = Math.max(h, hh);
  }
  // 北边海平线上的大陆：一道起伏的山
  const zc = -26000 + 2600 * Math.sin(x / 9000 + 1.3) + 1000 * Math.sin(x / 2700 + 0.4);
  const dIn = zc - z;
  if (dIn > -2500) h = Math.max(h, 2900 * smooth(-300, 9000, dIn) * (0.4 + 0.6 * ridged(x / 4600 + 3.3, z / 4600)) + 30 * smooth(-200, 600, dIn) - 40 * smooth(0, -1500, dIn));
  return h;
}

// 世界里一点 → 去游戏地图的哪儿取高度、材质：放大以后再按噪声扭一扭（游戏的岸线是几道正弦，放大了是一个光溜溜的椭圆；扭出海湾、岬角）
function srcPos(x, z) {
  const dx = x - BIG.fx, dz = z - BIG.fz, D = Math.hypot(dx, dz);
  if (BIG.id || D <= BIG.R0) return [x, z, 0, D];
  const k = sOf(D) / D, far = smooth(BIG.R0, BIG.R0 + BIG.VW, D), wq = far * 150;
  return [BIG.fx + dx * k + wq * fbm(x / 2900 + 7.1, z / 2900, 3), BIG.fz + dz * k + wq * fbm(x / 2900, z / 2900 - 3.7, 3), far, D];
}
// 沙漠的崖壁、方山（用户 11-22：那个山很奇怪）：游戏里的方山是一圈光滑的 S 形崖面 + 凹的坡脚，放大看像一块蛋糕。
//   片子里在高出平原、陡的地方加：顺坡往下的冲沟（噪声沿等高线方向密、顺坡方向拉长）、一级级的岩层台阶、坡脚的碎石堆；
//   平顶、平原、矮的沙墙沙丘、柏油路面不动（零件、车都照原来的高度摆）
function cliffDetail(x, z, h0) {
  const e = h0 - 12;
  if (e < 0.8) return 0;
  const k = 6;
  const gx = (srcH(x + k, z) - srcH(x - k, z)) / (2 * k), gz = (srcH(x, z + k) - srcH(x, z - k)) / (2 * k);
  const s = Math.hypot(gx, gz);
  if (s < 0.05) return 0;
  const ux = -gz / s, uz = gx / s;   // 沿等高线
  const u = x * ux + z * uz, v = (x * gx + z * gz) / s;   // 沿坡向
  const steep = smooth(0.1, 0.65, s) * smooth(4, 26, e) * (1 - matW(x, z)[1]);
  // 冲沟：大的十几米一道、小的几米一道，深浅不一（原来一样粗细、一样间距，像一排排草垛）
  const gully = (ridged(u / 47 + 3.1, v / 90 - 1.7, 3) - 0.5) * 10 + (ridged(u / 13 - 7.3, v / 40 + 2.2, 3) - 0.5) * 3.5 * (0.5 + 0.5 * perlin(u / 120, v / 60)) + perlin(u / 6, v / 19) * 1.6;
  // 岩层：厚薄不一（4～11 格）、高度随位置起伏一点（原来每 7.5 格一级、整整齐齐一圈圈）
  const ew = e + perlin(u / 160, 0.37) * 5;
  const L = 7.5 + 3.5 * perlin(ew / 23, 1.7), q = ew / L, f = q - Math.floor(q);
  const strata = (Math.floor(q) + smooth(0.6, 1, f) - q) * L * 0.32;
  const talus = smooth(0.04, 0.2, s) * (1 - smooth(0.45, 0.85, s)) * (1 - smooth(20, 45, e));
  return (gully + strata) * steep + (fbm(x / 8, z / 8, 3) * 1.8 + fbm(x / 31, z / 31, 2) * 2.4) * talus;
}
// —— 世界里一点的高度 ——
export function heightAt(x, z) {
  const [sx, sz, far] = srcPos(x, z);
  const h0 = srcH(sx, sz);
  if (BIG.desert) return h0 + cliffDetail(x, z, h0);
  let h;
  if (h0 <= 0) h = h0 * (1 + 2.5 * far);   // 海底：远处深一些（海水颜色、浪花按水深）
  else {
    const e = Math.max(0, h0 - BIG.BASE);
    h = h0 + e * (BIG.V - 1) * far;
    if (far > 0 && e > 0) {   // 山地的起伏：岩脊、沟壑（按高出平地多少加，平地、海滩不加）
      const m = smooth(0, 140, e) * far, he = h - BIG.BASE;
      h += m * ((ridged(x / 1700, z / 1700) - 0.42) * 0.85 * he + fbm(x / 300, z / 300, 3) * 0.08 * he + fbm(x / 70, z / 70, 2) * 5);
    }
  }
  return Math.max(h, extra(x, z));
}
// 地面的材质权重（沙、草、岩、土）和颜色
const MATC = { Sand: [0.70, 0.62, 0.45], Rock: [0.36, 0.34, 0.32], Ground: [0.36, 0.28, 0.2], Grass: [0.24, 0.3, 0.17], LeafyGrass: [0.19, 0.25, 0.14], Slate: [0.3, 0.3, 0.32], Asphalt: [0.12, 0.12, 0.13], Concrete: [0.42, 0.42, 0.4] };
// 沙漠（线性色）：暖沙、砾石、赭红砂岩、灰白石灰岩台地、白盐壳、黑柏油
const MATD = { Sand: [0.62, 0.47, 0.29], Ground: [0.42, 0.33, 0.23], Rock: [0.27, 0.21, 0.17], Slate: [0.24, 0.2, 0.17], Sandstone: [0.44, 0.33, 0.21], Limestone: [0.6, 0.53, 0.41],
  Salt: [0.7, 0.64, 0.52], Asphalt: [0.07, 0.068, 0.07], Concrete: [0.4, 0.39, 0.36], Mud: [0.3, 0.24, 0.17] };
const WCLS = nm => nm === 'Sand' ? 0 : (nm === 'Salt' || nm === 'Asphalt' || nm === 'Concrete') ? 1 : (nm === 'Rock' || nm === 'Slate' || nm === 'Sandstone' || nm === 'Limestone') ? 2 : 3;
// 台地顶上平的石灰岩是砾漠（hamada：碎石铺的平地），不是崖面那种亮的岩石——夜里高空看，整块台地亮成一片灰白
const HAMADA = [0.55, 0.41, 0.24];   // 和平原的沙一个色调（偏冷的话月光一照发蓝灰，一大块很扎眼），暗一点
function matAdd(nm, wt, A) {
  const cc = MATD[nm] || MATD.Sand;
  A.c[0] += cc[0] * wt; A.c[1] += cc[1] * wt; A.c[2] += cc[2] * wt;
  A.w[WCLS(nm)] += wt;
  if (nm === 'Limestone') A.lime += wt;
}
// 一点的材质按周围 4 个格点双线性混（边界软，不出锯齿），乘权重 wt 累加进 A
function srcMatAdd(x, z, wt, A) {
  const g = (G2 && fineW(x, z) < 0.5) ? G2 : G;
  const { n, R, step, mat, names } = g;
  if (Math.max(Math.abs(x), Math.abs(z)) > R - 2 * step) {   // 地图数据外（高空镜头往远看）：断崖线以北接着是台地，别处是平原的沙地（原来把边上那一圈拉过来，出一道道白斑）
    matAdd(z < escRaw(x) ? 'Limestone' : 'Sand', wt, A);
    return;
  }
  const fx = clamp((x + R) / step, 0, n - 1.001), fz = clamp((z + R) / step, 0, n - 1.001);
  const i = Math.floor(fx), j = Math.floor(fz), u = fx - i, v = fz - j, o = j * n + i;
  matAdd(names[mat[o] - 1] || 'Sand', wt * (1 - u) * (1 - v), A);
  matAdd(names[mat[o + 1] - 1] || 'Sand', wt * u * (1 - v), A);
  matAdd(names[mat[o + n] - 1] || 'Sand', wt * (1 - u) * v, A);
  matAdd(names[mat[o + n + 1] - 1] || 'Sand', wt * u * v, A);
}
const MACC = { c: [0, 0, 0], w: [0, 0, 0, 0], lime: 0 }, MW = { c: [0, 0, 0], w: [0, 0, 0, 0], lime: 0 };
function matW(x, z) { MW.c[0] = MW.c[1] = MW.c[2] = 0; MW.w[0] = MW.w[1] = MW.w[2] = MW.w[3] = 0; MW.lime = 0; srcMatAdd(x, z, 1, MW); return MW.w; }   // 一点的四类权重（沙、平的、岩、砾）
// 远处网格疏（最疏一格一千多），一个顶点只取一点的材质，边界就成了一级级的台阶：按这个顶点管的那一块（fx × fz）多取几点平均
function surfaceDesert(x, z, h, slope, out, o, fx = 0, fz = 0) {
  const A = MACC;
  A.c[0] = A.c[1] = A.c[2] = 0; A.w[0] = A.w[1] = A.w[2] = A.w[3] = 0; A.lime = 0;
  const nx = fx > 40 ? Math.min(4, Math.ceil(fx / 40)) : 1, nz = fz > 40 ? Math.min(4, Math.ceil(fz / 40)) : 1;
  const wt = 1 / (nx * nz);
  for (let a = 0; a < nx; a++) for (let b = 0; b < nz; b++) srcMatAdd(x + ((a + 0.5) / nx - 0.5) * fx, z + ((b + 0.5) / nz - 0.5) * fz, wt, A);
  let c = A.c.slice();
  // 权重：0 沙（沙纹）、1 盐壳 / 柏油（平的）、2 岩石、3 砾石土
  let w = A.w.slice();
  const ham = A.lime * (1 - smooth(0.2, 0.4, slope));
  if (ham > 0) {
    for (let k = 0; k < 3; k++) c[k] += ham * (HAMADA[k] - MATD.Limestone[k]);
    w[2] -= ham; w[0] += ham * 0.65; w[3] += ham * 0.35;   // 大半按沙画（沙的贴图带暖色；全按砾石画是中性灰，月光下发蓝）
  }
  // 平原上大块的深浅（砾石滩、风吹出来的沙带），沙丘背风坡暗一点
  const big = fbm(x / 2600, z / 2600, 3), mid = fbm(x / 420, z / 420, 2);
  if (w[0] > 0.5) {
    const gravel = smooth(0.05, 0.45, big) * w[0];
    c = [lerp(c[0], 0.47, gravel * 0.55), lerp(c[1], 0.37, gravel * 0.55), lerp(c[2], 0.25, gravel * 0.55)];
    w = [w[0] - gravel * 0.5, w[1], w[2], w[3] + gravel * 0.5];
  }
  if (ham > 0) { const k = 1 + ham * 0.14 * big; c = [c[0] * k, c[1] * k, c[2] * k]; }   // 砾漠也有大块的深浅（风化程度、碎石疏密）
  const lv = 0.9 + 0.2 * (mid * 0.5 + 0.5);
  out.c[o * 3] = c[0] * lv; out.c[o * 3 + 1] = c[1] * lv; out.c[o * 3 + 2] = c[2] * lv;
  out.w[o * 4] = w[0]; out.w[o * 4 + 1] = w[1]; out.w[o * 4 + 2] = w[2]; out.w[o * 4 + 3] = w[3];
}
function surface(x, z, h, slope, out, o, fx, fz) {
  if (BIG.desert) return surfaceDesert(x, z, h, slope, out, o, fx, fz);
  const [sx, sz, , D] = srcPos(x, z);
  let nm = srcMat(sx, sz);
  const inGame = Math.abs(sx) < G.R - 8 && Math.abs(sz) < G.R - 8 && srcH(sx, sz) > -1;
  if (!inGame) nm = h < 7 ? 'Sand' : 'Grass';   // 补的岛
  if (h < -0.5) nm = 'Sand';
  let w = nm === 'Sand' ? [1, 0, 0, 0] : (nm === 'Grass' || nm === 'LeafyGrass') ? [0, 1, 0, 0] : (nm === 'Rock' || nm === 'Slate') ? [0, 0, 1, 0] : [0, 0, 0, 1];
  let c = (MATC[nm] || MATC.Ground).slice();
  if (h < -0.5) c = [0.5, 0.45, 0.34];   // 海底：湿沙
  // 放大出来的山：陡的地方、高处是岩石；草地上一片片深色（树林）
  const far = BIG.id ? 1 : smooth(BIG.R0, BIG.R0 + 600, D);
  const rock = clamp(smooth(0.5, 0.95, slope) + smooth(520, 1300, h) * 0.6, 0, 1) * (inGame ? far : 1) * (h > 4 ? 1 : 0);
  const forest = (w[1] > 0.5 ? 1 : 0) * smooth(0.05, 0.35, fbm(x / 520, z / 520, 3) + 0.1) * smooth(25, 90, h) * (1 - smooth(0.55, 0.85, slope));
  c = [lerp(c[0], 0.11, forest * 0.75), lerp(c[1], 0.15, forest * 0.75), lerp(c[2], 0.09, forest * 0.75)];
  c = [lerp(c[0], 0.34, rock), lerp(c[1], 0.32, rock), lerp(c[2], 0.3, rock)];
  w = [w[0] * (1 - rock), w[1] * (1 - rock), w[2] * (1 - rock) + rock, w[3] * (1 - rock)];
  const lv = 0.86 + 0.28 * (fbm(x / 140, z / 140, 2) * 0.5 + 0.5);   // 大块的明暗
  out.c[o * 3] = c[0] * lv; out.c[o * 3 + 1] = c[1] * lv; out.c[o * 3 + 2] = c[2] * lv;
  out.w[o * 4] = w[0]; out.w[o * 4 + 1] = w[1]; out.w[o * 4 + 2] = w[2]; out.w[o * 4 + 3] = w[3];
}

// —— 地形网格：以 c 为中心的不等距网格（中心 sp0 格一个，往外线性变疏、最疏 cap，铺到 ±ext）——
function axis(c, sp0, a, cap, ext) {
  const L = [], R = [];
  for (let u = 0; u < ext;) { u += Math.min(cap, sp0 * (1 + u / a)); R.push(c + u); L.push(c - u); }
  return [...L.reverse(), c, ...R];
}
export function bigTerrainGeo(cx, cz, o = {}) {
  const xs = axis(cx, o.sp ?? 4, o.a ?? 150, o.cap ?? 600, o.ext ?? 42000);
  const zs = axis(cz, o.sp ?? 4, o.a ?? 150, o.cap ?? 600, o.ext ?? 42000);
  const nx = xs.length, nz = zs.length, N = nx * nz;
  const H = new Float32Array(N);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) H[j * nx + i] = heightAt(xs[i], zs[j]);
  const pos = new Float32Array(N * 3), nor = new Float32Array(N * 3), col = new Float32Array(N * 3), wts = new Float32Array(N * 4);
  const out = { c: col, w: wts };
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const v = j * nx + i, x = xs[i], z = zs[j], h = H[v];
    pos[v * 3] = x; pos[v * 3 + 1] = h; pos[v * 3 + 2] = z;
    const i0 = Math.max(0, i - 1), i1 = Math.min(nx - 1, i + 1), j0 = Math.max(0, j - 1), j1 = Math.min(nz - 1, j + 1);
    const gx = (H[j * nx + i1] - H[j * nx + i0]) / (xs[i1] - xs[i0]), gz = (H[j1 * nx + i] - H[j0 * nx + i]) / (zs[j1] - zs[j0]);
    const l = Math.hypot(gx, 1, gz);
    nor[v * 3] = -gx / l; nor[v * 3 + 1] = 1 / l; nor[v * 3 + 2] = -gz / l;
    surface(x, z, h, Math.hypot(gx, gz), out, v, (xs[i1] - xs[i0]) / (i1 - i0), (zs[j1] - zs[j0]) / (j1 - j0));
  }
  const idx = [];
  for (let j = 0; j < nz - 1; j++) for (let i = 0; i < nx - 1; i++) {
    const a = j * nx + i, b = a + 1, c = a + nx, d = c + 1;
    if (H[a] < -9 && H[b] < -9 && H[c] < -9 && H[d] < -9) continue;   // 深海不要（海面不透明，看不见）
    idx.push(a, c, b, b, c, d);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.setAttribute('aW', new THREE.BufferAttribute(wts, 4));
  geo.setIndex(new THREE.Uint32BufferAttribute(idx, 1));
  geo.computeBoundingSphere();
  return geo;
}
// 海面用的水深贴图（世界坐标、以 c 为中心、边长 2r、size²）：浅滩的颜色、拍岸的浪花
export function seaHeightTex(cx, cz, r, size) {
  const d = new Uint16Array(size * size);
  for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
    const x = cx - r + (i + 0.5) / size * 2 * r, z = cz - r + (j + 0.5) / size * 2 * r;
    d[j * size + i] = THREE.DataUtils.toHalfFloat(clamp(heightAt(x, z), -60, 60));
  }
  const t = new THREE.DataTexture(d, size, size, THREE.RedFormat, THREE.HalfFloatType);
  t.magFilter = t.minFilter = THREE.LinearFilter;
  t.needsUpdate = true;
  return t;
}

// —— 地图上的零件挪到放大后的位置：挨着的（40 格以内）算一组整体平移（碉堡、机场、港口照原样），
//   铁丝网、沙袋墙这些沿着海岸一长串的一件件挪；海上的（码头、舰队）只挪水平位置 ——
const PER_PART = /^Map\/(Wire|Defenses)$/;
const DROP = /^Map\/(Pads|Points)$/;   // 召唤位、据点旗（游戏里的标记：一大块蓝 / 红旗板，摆在片子里很抢眼）不进片子
// 整组平移过的东西（军舰、码头、工事、机场……）：包围盒 + 平移量。摆在它们上面的东西（甲板上的飞机、码头上的人）
//   要跟着同一个平移，不能各自按 s2w 算——放大以后两点的位移差好几百格，飞机就悬空了（用户：飞机起飞甲板为什么是透明的）
const MOVED = [];
export function shiftOf(x, z) {
  for (const g of MOVED) if (x >= g.x0 && x <= g.x1 && z >= g.z0 && z <= g.z1) return g;
  return null;
}
// 游戏坐标 → 片子里的坐标：在整组搬过的东西上就跟着它走，否则按平滑映射；返回 [x, z, 高度的平移]
export function s2wAt(x, z) {
  const g = shiftOf(x, z);
  if (g) return [x + g.dx, z + g.dz, g.dy];
  const [wx, wz] = s2w(x, z);
  return [wx, wz, 0];
}
// 海滩的标志旗（Map/Scenery 里 8 × 5 的布块，红 / 白 / 蓝 / 金 / 紫五处海滩各一面）和它的旗杆：游戏里的标记，片子里一大块纯色很抢眼
function isBeachFlag(p) { return p.g === 'Map/Scenery' && /Fabric/.test(p.m) && Math.abs(p.s[0] - 8) < 0.6 && Math.abs(p.s[1] - 5) < 0.6 && p.s[2] < 0.8; }
export function relocateParts(parts) {
  const flags = parts.filter(isBeachFlag);
  const nearFlag = p => flags.some(f => Math.hypot(p.cf[0] - f.cf[0], p.cf[2] - f.cf[2]) < 9);
  const keep = parts.filter(p => !DROP.test(p.g) && !isBeachFlag(p) && !(p.g === 'Map/Scenery' && p.s[1] > 12 && p.s[0] < 2 && p.s[2] < 2 && nearFlag(p)));
  const out = [];
  MOVED.length = 0;
  const move = (list) => {
    let sx = 0, sz = 0, x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9;
    for (const p of list) {
      sx += p.cf[0]; sz += p.cf[2];
      x0 = Math.min(x0, p.cf[0]); x1 = Math.max(x1, p.cf[0]); z0 = Math.min(z0, p.cf[2]); z1 = Math.max(z1, p.cf[2]);
    }
    sx /= list.length; sz /= list.length;
    const [nx, nz] = s2w(sx, sz);
    const g0 = srcH0(sx, sz);
    const dy = g0 < 0.5 ? 0 : heightAt(nx, nz) - g0;
    if (list.length > 20) MOVED.push({ x0: x0 - 40, x1: x1 + 40, z0: z0 - 40, z1: z1 + 40, dx: nx - sx, dz: nz - sz, dy });
    for (const p of list) { const q = { ...p, cf: p.cf.slice() }; q.cf[0] += nx - sx; q.cf[1] += dy; q.cf[2] += nz - sz; out.push(q); }
  };
  // 分组：同一类里中心相距 40 格以内的连成一组（并查集 + 网格）
  const byG = {};
  for (const p of keep) (byG[p.g] = byG[p.g] || []).push(p);
  for (const [g, L] of Object.entries(byG)) {
    if (PER_PART.test(g)) { for (const p of L) move([p]); continue; }
    const par = L.map((_, i) => i), find = i => { while (par[i] !== i) { par[i] = par[par[i]]; i = par[i]; } return i; };
    const cell = {}, C = 160, key = (a, b) => a + ',' + b;   // 连成一块的距离：40 格太小，航母的甲板块、舰岛会被拆成好多组，各组按自己的位移搬就把船抻开了
    L.forEach((p, i) => { const a = Math.floor(p.cf[0] / C), b = Math.floor(p.cf[2] / C); (cell[key(a, b)] = cell[key(a, b)] || []).push(i); });
    L.forEach((p, i) => {
      const a = Math.floor(p.cf[0] / C), b = Math.floor(p.cf[2] / C);
      for (let da = -1; da <= 1; da++) for (let db = -1; db <= 1; db++) for (const k of cell[key(a + da, b + db)] || []) {
        if (k <= i) continue;
        const q = L[k];
        if (Math.hypot(q.cf[0] - p.cf[0], q.cf[2] - p.cf[2]) < C) par[find(k)] = find(i);
      }
    });
    const groups = {};
    L.forEach((p, i) => (groups[find(i)] = groups[find(i)] || []).push(p));
    for (const list of Object.values(groups)) {
      let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9;
      for (const p of list) { x0 = Math.min(x0, p.cf[0]); x1 = Math.max(x1, p.cf[0]); z0 = Math.min(z0, p.cf[2]); z1 = Math.max(z1, p.cf[2]); }
      // 连在一起的一大块（军舰、机场）整组搬；只有拉得特别长的一串（长围栏之类）才一件件搬
      if (Math.hypot(x1 - x0, z1 - z0) > 2500) for (const p of list) move([p]); else move(list);
    }
  }
  return out;
}
// 游戏里的一点（地面上）→ 片子里的位置（贴地）
export function placeOnGround(x, z, lift = 0) { const [wx, wz] = s2wAt(x, z); return new THREE.Vector3(wx, heightAt(wx, wz) + lift, wz); }
