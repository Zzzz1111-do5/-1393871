// M1A2 SEPv2 车长显示单元（上 CITV 热像、下指挥地图、右边橙色字母数字键盘）的机壳网格——本项目自己按图做的：
//   用户 11-23 发来钢铁猛兽 M1A2 车长位截图：「严格按照这个图，上面是一块 CITV」「两个屏幕中间的横排按钮是对应上面的屏幕的」；
//   Sketchfab 上搜不到能下载的 CITV / 车长显示器模型（11-23 搜过 CITV、commander display unit、MFD、keypad……），所以照截图量的比例自己做
//   只做不动的壳子：机壳（正面倒角）、两块屏的银色倒角框和黑玻璃、按键底座（深色凹槽）、右边指示灯条、三根把手；
//   能按的键、屏幕画面、指示灯是游戏里现做的零件（要能点、能亮）：它们的位置和这里的壳子用同一张表 LAYOUT，
//   运行时写出 src/ReplicatedStorage/CdusLayout.lua 给 InteriorDefs 用（别手改那个文件）
//   坐标（米，真实尺寸）：X 人看过去向右、Y 向上、Z 朝人；原点在机壳正面中心（正面 z = 0）
//   用法：optics.json 的 sources.ip_cdus.gen 指到这个文件，optics.mjs 发现缓存里没有就调它生成；也可以单独跑 node tools/weapons/gen_cdus.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Document, NodeIO } from '@gltf-transform/core';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');

// ---------------------------------------------------------------- 版面（截图里量的：屏框、键、把手的相对位置和大小）
//   截图 2000 × 923：机壳从 x 1025 到 1800、y 30 到 810；横向每像素约 0.525 毫米，竖向看得斜、每像素约 0.6 毫米
export const LAYOUT = {
  unit: { w: 0.410, h: 0.470, d: 0.075, r: 0.014, ch: 0.005 },   // 机壳：宽、高、深、四角圆角、正面倒角
  zTop: 0.012, zGlass: 0.0035,                                    // 屏框顶面、玻璃面（屏框比玻璃高 8.5 毫米）
  // 两块屏：外框中心、外框宽高、外框圆角，玻璃宽高、玻璃圆角（上屏框四边厚、下屏框左右厚上下薄，照截图）
  up: { cx: -0.008, cy: 0.1305, ow: 0.300, oh: 0.205, ro: 0.024, gw: 0.256, gh: 0.176, gr: 0.010 },
  low: { cx: -0.040, cy: -0.110, ow: 0.262, oh: 0.176, ro: 0.022, gw: 0.212, gh: 0.160, gr: 0.008 },
  // 上屏（CITV）左边一列 5 个蓝键、两屏之间一排 10 个（单、单、双、双、双、双；最右一对是深色的）
  upL: [[-0.180, 0.212], [-0.180, 0.170], [-0.180, 0.128], [-0.180, 0.086], [-0.180, 0.044]], upLw: 0.030, upLh: 0.036,
  row: [[-0.151, 0.028], [-0.1175, 0.028], [-0.08175, 0.0325], [-0.04825, 0.0325], [-0.01025, 0.0325], [0.02325, 0.0325],
    [0.06125, 0.0325], [0.09475, 0.0325], [0.13275, 0.0325], [0.16625, 0.0325]], rowY: 0.0025, rowH: 0.034,
  // 上屏右边的指示灯条（三个绿灯）、竖把手
  leds: [[0.151, 0.185], [0.151, 0.130], [0.151, 0.075]], ledStrip: [0.157, 0.130, 0.024, 0.150],
  handleV: [0.190, 0.205, 0.055, 0.022],          // x、上端 y、下端 y、离面板多远
  // 下屏（地图）：左边两个键（VEH SYS、C3）、左下四个方向键、下边一排 8 个橙色横杠键、右边 4 × 4 键盘、键盘下面的横把手
  lowL: [[-0.189, -0.118], [-0.189, -0.156]], lowLw: 0.026, lowLh: 0.034,
  handleS: [-0.203, -0.177, -0.080, 0.012],       // 左边小把手：x0、x1、y、离面板多远
  arrows: { cx: -0.183, cy: -0.205, d: 0.0135, s: 0.0115 },   // 中心、离中心多远、键大小（上、下、左、右）
  bot: { x0: -0.130, dx: 0.0256, y: -0.2145, w: 0.022, h: 0.022, n: 8 },
  pad: { x0: 0.10875, y0: -0.04975, dx: 0.0215, dy: -0.0275, w: 0.0195, h: 0.0255 },
  handleH: [0.100, 0.182, -0.164, 0.016],         // 键盘下横把手：x0、x1、y、离面板多远
  ledLow: [0.100, -0.180],
};
const Lo = LAYOUT;

// ---------------------------------------------------------------- 颜色（截图：机壳深蓝灰、屏框浅银灰、按键槽更深）
const COL = {
  body: [44, 48, 66], bezel: [170, 172, 180], glass: [7, 8, 10], well: [27, 29, 38], strip: [20, 22, 28], handle: [92, 96, 106], post: [60, 62, 70],
};

// ---------------------------------------------------------------- 网格拼装：每种颜色一组顶点 / 法线 / 三角形
const G = {};
function grp(c) { return (G[c] ||= { p: [], n: [], i: [] }); }
function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
function norm(a) { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
// 一个四边形（a b c d 顺着一圈），hint：法线应该朝的大致方向——绕向不对就翻过来；nrm 每个顶点的法线（不给就用面法线）
function quad(c, a, b, cc, d, hint, nrm) {
  const g = grp(c);
  let fn = norm(cross(sub(b, a), sub(cc, a)));
  let P = [a, b, cc, d];
  let N = nrm || [fn, fn, fn, fn];
  if (dot(fn, hint) < 0) { P = [a, d, cc, b]; N = [N[0], N[3], N[2], N[1]]; fn = [-fn[0], -fn[1], -fn[2]]; }
  if (!nrm) N = [fn, fn, fn, fn];
  const o = g.p.length / 3;
  for (let k = 0; k < 4; k++) { g.p.push(...P[k]); g.n.push(...N[k]); }
  g.i.push(o, o + 1, o + 2, o, o + 2, o + 3);
}
function tri(c, a, b, cc, hint) {
  const g = grp(c);
  let fn = norm(cross(sub(b, a), sub(cc, a)));
  let P = [a, b, cc];
  if (dot(fn, hint) < 0) { P = [a, cc, b]; fn = [-fn[0], -fn[1], -fn[2]]; }
  const o = g.p.length / 3;
  for (let k = 0; k < 3; k++) { g.p.push(...P[k]); g.n.push(...fn); }
  g.i.push(o, o + 1, o + 2);
}
// 圆角矩形的一圈点（逆时针，从右上角那段圆弧开始；每个角 n 段）：同样 n 的两圈点一一对应，连成斜面
const NC = 8;
function rrect(cx, cy, hw, hh, r, n = NC) {
  r = Math.max(0.0005, Math.min(r, hw, hh));
  const pts = [];
  const C = [[cx + hw - r, cy + hh - r, 0], [cx - hw + r, cy + hh - r, 90], [cx - hw + r, cy - hh + r, 180], [cx + hw - r, cy - hh + r, 270]];
  for (const [x, y, a0] of C) for (let k = 0; k <= n; k++) {
    const a = (a0 + 90 * k / n) * Math.PI / 180;
    pts.push([x + Math.cos(a) * r, y + Math.sin(a) * r, Math.cos(a), Math.sin(a)]);   // 后两个：这一点往外的方向（斜面法线用）
  }
  return pts;
}
// 两圈之间的一条斜面 / 侧壁：A 圈在 za、B 圈在 zb；沿着一圈是平滑的（圆角处不出棱），两条之间是硬棱
function band(c, A, za, B, zb, up) {
  const n = A.length;
  for (let k = 0; k < n; k++) {
    const k2 = (k + 1) % n;
    const a = [A[k][0], A[k][1], za], b = [A[k2][0], A[k2][1], za], cc = [B[k2][0], B[k2][1], zb], d = [B[k][0], B[k][1], zb];
    // 这条带子的法线：往外（侧壁）或往外上方（倒角）——用这一点的外向和带子的坡度合成
    const nrmAt = (P, Q, out) => {
      const dr = Math.hypot(Q[0] - P[0], Q[1] - P[1]) * Math.sign((Q[0] - P[0]) * out[0] + (Q[1] - P[1]) * out[1] || 1);
      const dz = Q[2] - P[2];
      // 剖面里沿带子的方向 (dr, dz)，法线是它转 90°：(dz, -dr) 朝外、朝上
      let nr = dz, nz = -dr;
      if (up * nz < 0 || (Math.abs(nz) < 1e-9 && nr < 0 && up > 0)) { nr = -nr; nz = -nz; }
      return norm([out[0] * nr, out[1] * nr, nz]);
    };
    const oA = [A[k][2], A[k][3]], oA2 = [A[k2][2], A[k2][3]];
    const N = [nrmAt(a, d, oA), nrmAt(b, cc, oA2), nrmAt(b, cc, oA2), nrmAt(a, d, oA)];
    const mid = norm([(N[0][0] + N[1][0]) / 2, (N[0][1] + N[1][1]) / 2, (N[0][2] + N[1][2]) / 2]);
    quad(c, a, b, cc, d, mid, N);
  }
}
// 一圈点围起来的平面（扇形三角化；圆角矩形是凸的）
function cap(c, A, z, nz) {
  let cx = 0, cy = 0;
  for (const p of A) { cx += p[0]; cy += p[1]; }
  cx /= A.length; cy /= A.length;
  for (let k = 0; k < A.length; k++) {
    const k2 = (k + 1) % A.length;
    tri(c, [cx, cy, z], [A[k][0], A[k][1], z], [A[k2][0], A[k2][1], z], [0, 0, nz]);
  }
}
// 一块圆角薄板（按键槽、灯条）：正面 + 一圈侧壁
function plate(c, cx, cy, w, h, r, z0, z1) {
  const A = rrect(cx, cy, w / 2, h / 2, r, 4);
  band(c, A, z0, A, z1, 1);
  cap(c, A, z1, 1);
}
// 圆柱（把手、立柱）：从 p0 到 p1，半径 r，seg 段，两头封口
function cyl(c, p0, p1, r, seg = 14) {
  const ax = norm(sub(p1, p0));
  const t = Math.abs(ax[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  const u = norm(cross(ax, t)), v = cross(ax, u);
  const ring = (p) => Array.from({ length: seg }, (_, k) => {
    const a = 2 * Math.PI * k / seg;
    const o = [u[0] * Math.cos(a) + v[0] * Math.sin(a), u[1] * Math.cos(a) + v[1] * Math.sin(a), u[2] * Math.cos(a) + v[2] * Math.sin(a)];
    return { p: [p[0] + o[0] * r, p[1] + o[1] * r, p[2] + o[2] * r], o };
  });
  const R0 = ring(p0), R1 = ring(p1);
  for (let k = 0; k < seg; k++) {
    const k2 = (k + 1) % seg;
    const mo = norm([R0[k].o[0] + R0[k2].o[0], R0[k].o[1] + R0[k2].o[1], R0[k].o[2] + R0[k2].o[2]]);
    quad(c, R0[k].p, R0[k2].p, R1[k2].p, R1[k].p, mo, [R0[k].o, R0[k2].o, R1[k2].o, R1[k].o]);
    tri(c, p0, R0[k].p, R0[k2].p, [-ax[0], -ax[1], -ax[2]]);
    tri(c, p1, R1[k].p, R1[k2].p, ax);
  }
}
// 一根把手：两头各一根立柱（从面板伸出来）+ 中间一根杆
function handle(x0, y0, x1, y1, off, r) {
  const a = [x0, y0, off], b = [x1, y1, off];
  cyl('handle', a, b, r);
  cyl('post', [x0, y0, 0], a, r * 1.15);
  cyl('post', [x1, y1, 0], b, r * 1.15);
}

// ---------------------------------------------------------------- 拼起来
function buildMesh() {
  for (const k of Object.keys(G)) delete G[k];
  const U = Lo.unit;
  // 机壳：正面一圈倒角 + 四周侧壁 + 背面
  const F0 = rrect(0, 0, U.w / 2 - U.ch, U.h / 2 - U.ch, Math.max(0.002, U.r - U.ch));
  const F1 = rrect(0, 0, U.w / 2, U.h / 2, U.r);
  cap('body', F0, 0, 1);
  band('body', F0, 0, F1, -U.ch, 1);
  band('body', F1, -U.ch, F1, -U.d, 1);
  cap('body', F1, -U.d, -1);
  // 两块屏：外框底边（贴着机壳正面）→ 外倒角 → 平顶 → 内斜面 → 玻璃
  for (const S of [Lo.up, Lo.low]) {
    const R0 = rrect(S.cx, S.cy, S.ow / 2, S.oh / 2, S.ro);
    const R1 = rrect(S.cx, S.cy, S.ow / 2 - 0.004, S.oh / 2 - 0.004, S.ro - 0.004);
    const ins = Math.min(0.010, (S.ow - S.gw) / 2 - 0.002, (S.oh - S.gh) / 2 - 0.0015);
    const R2 = rrect(S.cx, S.cy, S.ow / 2 - ins, S.oh / 2 - ins, Math.max(S.gr, S.ro - ins));
    const R3 = rrect(S.cx, S.cy, S.gw / 2, S.gh / 2, S.gr);
    band('bezel', R0, 0, R1, Lo.zTop - 0.003, 1);
    band('bezel', R1, Lo.zTop - 0.003, R2, Lo.zTop, 1);
    band('bezel', R2, Lo.zTop, R3, Lo.zGlass, 1);
    cap('glass', R3, Lo.zGlass, 1);
  }
  // 按键槽（深色，键坐在里面）：上屏左列、两屏之间一排、下屏左边、方向键、下边一排、键盘
  const z1 = 0.0015;
  plate('well', -0.180, 0.128, 0.038, 0.204, 0.004, 0, z1);
  plate('well', 0.0088, Lo.rowY, 0.355, 0.042, 0.004, 0, z1);
  plate('well', -0.189, -0.137, 0.032, 0.082, 0.003, 0, z1);
  plate('well', Lo.arrows.cx, Lo.arrows.cy, 0.040, 0.042, 0.010, 0, z1);
  const B = Lo.bot;
  plate('well', B.x0 + B.dx * (B.n - 1) / 2, B.y, B.dx * B.n + 0.006, B.h + 0.008, 0.004, 0, z1);
  const P = Lo.pad;
  plate('well', P.x0 + P.dx * 1.5, P.y0 + P.dy * 1.5, Math.abs(P.dx) * 4 + 0.008, Math.abs(P.dy) * 4 + 0.008, 0.006, 0, z1);
  plate('well', P.x0 + P.dx * 3 + P.w / 2 + 0.003, P.y0 + P.dy, 0.008, 0.016, 0.002, 0, z1);   // LTR 键旁边那个小凸耳（截图里键盘右边缘的缺口）
  // 上屏右边的指示灯条
  const L = Lo.ledStrip;
  plate('strip', L[0], L[1], L[2], L[3], 0.004, 0, 0.003);
  // 把手：上屏右边一根竖的、下屏左边一根小的、键盘下面一根横的
  handle(Lo.handleV[0], Lo.handleV[1], Lo.handleV[0], Lo.handleV[2], Lo.handleV[3], 0.0045);
  handle(Lo.handleS[0], Lo.handleS[2], Lo.handleS[1], Lo.handleS[2], Lo.handleS[3], 0.0035);
  handle(Lo.handleH[0], Lo.handleH[2], Lo.handleH[1], Lo.handleH[2], Lo.handleH[3], 0.004);
}

// ---------------------------------------------------------------- 写 glb（每种颜色一块网格、一个材质）
export async function build(outFile) {
  buildMesh();
  const doc = new Document();
  const buf = doc.createBuffer();
  const scene = doc.createScene('cdus');
  const s2l = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  for (const [name, g] of Object.entries(G)) {
    const col = COL[name];
    const mat = doc.createMaterial(name).setBaseColorFactor([s2l(col[0]), s2l(col[1]), s2l(col[2]), 1])
      .setMetallicFactor(name === 'bezel' || name === 'handle' ? 0.35 : 0.05).setRoughnessFactor(name === 'glass' ? 0.15 : 0.6);
    const prim = doc.createPrimitive()
      .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(new Float32Array(g.p)).setBuffer(buf))
      .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(new Float32Array(g.n)).setBuffer(buf))
      .setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint16Array(g.i)).setBuffer(buf))
      .setMaterial(mat);
    const mesh = doc.createMesh(name).addPrimitive(prim);
    scene.addChild(doc.createNode(name).setMesh(mesh));
  }
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  await new NodeIO().write(outFile, doc);
  writeLua();
  const tris = Object.values(G).reduce((a, g) => a + g.i.length / 3, 0);
  console.log('gen_cdus：写好了', outFile, '三角形', tris);
  return outFile;
}

// 键、屏幕、指示灯的位置给游戏用（同一张表）
function writeLua() {
  const lv = (v) => (Array.isArray(v) ? `{ ${v.map(lv).join(', ')} }` : (typeof v === 'object' ? `{ ${Object.entries(v).map(([k, x]) => `${k} = ${lv(x)}`).join(', ')} }` : String(+(+v).toFixed(5))));
  const L = ['-- 自动生成（tools/weapons/gen_cdus.mjs），别手改：M1A2 SEPv2 车长显示单元的版面（米，X 人看过去向右、Y 上、Z 朝人，原点在机壳正面中心）',
    '--   机壳网格（OpticMesh/ip_cdus）和游戏里现做的键、屏幕、指示灯都按这张表摆',
    'return ' + lv(LAYOUT)];
  fs.writeFileSync(path.join(ROOT, 'src/ReplicatedStorage/CdusLayout.lua'), L.join('\n') + '\n');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await build(process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache/ip_cdus/model.glb'));
}
