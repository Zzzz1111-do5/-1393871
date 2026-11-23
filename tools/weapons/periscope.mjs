// 坦克潜望镜（车里看得见的下半截）：Sketchfab 上 renalds_rs 的「FV105 Sultan periscop」（CC-BY-4.0，真车潜望镜的三维扫描，150 多万面）
//   截取、减面、重烘贴图，做成 optics.mjs 的原模型缓存 cache/ip_peri/model.glb（用户 11-22：「坦克第一人称驾驶舱那个潜望镜，你从 Sketchfab 自己找模型截取下来套用」）
//   用法（仓库根目录；先在 tools/weapons 里 npm ci）：node tools/weapons/periscope.mjs [目标三角形数] [截断（窗顶往上多少，窗高的倍数）] [贴图边长]
//     然后 BUILD=ip_peri node tools/weapons/optics.mjs 出 models/optics/ip_peri.glb、OpticMesh/ip_peri.lua、OpticsMeta
//   原模型缓存 cache/ip_peri_src/model.glb；没有的从 Sketchfab 下载——密钥只从环境变量 SKETCHFAB_TOKEN 读
//   步骤：
//     1) 找观察窗玻璃（贴图里青灰的那块）定坐标：x 沿窗宽、y 向上（往潜望镜头那边）、z 窗的法线（朝看的人），原点在窗中心，单位照原样（毫米）
//     2) 只留 y < 截断高度的三角形（下半截：观察窗 + 外壳，到安装法兰为止；上半截在车顶外面，车里看不见）
//     3) 按位置焊接、meshoptimizer 简化（扫描件的贴图接缝太碎，按原 UV 简化只能减到 2 万多面）
//     4) 每个三角形在新贴图里占一格，从原扫描（最近的原顶点的 UV）取颜色烘进去；观察窗玻璃压成偏冷的中性灰（不发青绿）
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { flatten, join, weld } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const [targetS, cutS, texS] = process.argv.slice(2);
const UID = '52c930bb607f4ae69aab580992e7449e';
const inp = path.join(HERE, 'cache/ip_peri_src/model.glb');
const out = path.join(HERE, 'cache/ip_peri/model.glb');
if (!fs.existsSync(inp)) {
  const tok = process.env.SKETCHFAB_TOKEN;
  if (!tok) throw new Error('缓存里没有原模型：设好环境变量 SKETCHFAB_TOKEN 再运行，或者把下载的 model.glb 放进 ' + path.dirname(inp));
  const r = await fetch(`https://api.sketchfab.com/v3/models/${UID}/download`, { headers: { Authorization: 'Token ' + tok } });
  if (!r.ok) throw new Error('下载失败：HTTP ' + r.status);
  const j = await r.json();
  fs.mkdirSync(path.dirname(inp), { recursive: true });
  fs.writeFileSync(inp, Buffer.from(await (await fetch(j.glb.url)).arrayBuffer()));
}
fs.mkdirSync(path.dirname(out), { recursive: true });
const TARGET = Number(targetS || 2000), CUT = Number(cutS || 0.35), TEX = Number(texS || 1024);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inp);
await doc.transform(flatten(), join({ keepNamed: false }));
const root = doc.getRoot();
const node = root.listNodes().find(n => n.getMesh());
const prim = node.getMesh().listPrimitives()[0];
const M = node.getWorldMatrix();
const P0 = prim.getAttribute('POSITION').getArray();
const UV0 = prim.getAttribute('TEXCOORD_0').getArray();
const I0 = prim.getIndices().getArray();
const nv = P0.length / 3;
// 世界坐标
const W = new Float64Array(nv * 3);
for (let i = 0; i < nv; i++) {
  const x = P0[i * 3], y = P0[i * 3 + 1], z = P0[i * 3 + 2];
  W[i * 3] = M[0] * x + M[4] * y + M[8] * z + M[12];
  W[i * 3 + 1] = M[1] * x + M[5] * y + M[9] * z + M[13];
  W[i * 3 + 2] = M[2] * x + M[6] * y + M[10] * z + M[14];
}
// 底色贴图
const tex = prim.getMaterial().getBaseColorTexture();
const { data: img, info } = await sharp(Buffer.from(tex.getImage())).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const TW = info.width, TH = info.height;
const sample = (u, v) => {
  const x = Math.min(TW - 1, Math.max(0, Math.floor((u - Math.floor(u)) * TW)));
  const y = Math.min(TH - 1, Math.max(0, Math.floor((v - Math.floor(v)) * TH)));
  const k = (y * TW + x) * 3;
  return [img[k], img[k + 1], img[k + 2]];
};
// 1) 玻璃：偏青灰（g、b 比 r 高，不太暗不太亮）
const glass = [];
for (let i = 0; i < nv; i++) {
  const [r, g, b] = sample(UV0[i * 2], UV0[i * 2 + 1]);
  if (g > r + 8 && b > r + 4 && g > 90 && g < 200 && Math.abs(g - b) < 40) glass.push(i);
}
console.log('原顶点', nv, '玻璃颜色的顶点', glass.length);
const mean = [0, 0, 0];
for (const i of glass) for (let a = 0; a < 3; a++) mean[a] += W[i * 3 + a] / glass.length;
const C = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
for (const i of glass) {
  const d = [W[i * 3] - mean[0], W[i * 3 + 1] - mean[1], W[i * 3 + 2] - mean[2]];
  for (let a = 0; a < 3; a++) for (let b2 = 0; b2 < 3; b2++) C[a][b2] += d[a] * d[b2] / glass.length;
}
// 对称矩阵的特征向量（Jacobi）
function eig(A) {
  const a = A.map(r => r.slice()), v = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  for (let it = 0; it < 60; it++) {
    let p = 0, q = 1;
    for (const [i, j] of [[0, 1], [0, 2], [1, 2]]) if (Math.abs(a[i][j]) > Math.abs(a[p][q])) { p = i; q = j; }
    if (Math.abs(a[p][q]) < 1e-12) break;
    const th = 0.5 * Math.atan2(2 * a[p][q], a[q][q] - a[p][p]);
    const c = Math.cos(th), s = Math.sin(th);
    for (let k = 0; k < 3; k++) { const x = a[k][p], y = a[k][q]; a[k][p] = c * x - s * y; a[k][q] = s * x + c * y; }
    for (let k = 0; k < 3; k++) { const x = a[p][k], y = a[q][k]; a[p][k] = c * x - s * y; a[q][k] = s * x + c * y; }
    for (let k = 0; k < 3; k++) { const x = v[k][p], y = v[k][q]; v[k][p] = c * x - s * y; v[k][q] = s * x + c * y; }
  }
  const vals = [a[0][0], a[1][1], a[2][2]];
  const vecs = [0, 1, 2].map(j => [v[0][j], v[1][j], v[2][j]]);
  const ord = [0, 1, 2].sort((x, y) => vals[y] - vals[x]);
  return { vals: ord.map(j => vals[j]), vecs: ord.map(j => vecs[j]) };
}
const E = eig(C);
let [wdir, udir, ndir] = E.vecs;
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
// 全模型的中心：潜望镜头在窗的「上」方，法线朝外（离模型中心远的那边是看的人那边）
const all = [0, 0, 0];
for (let i = 0; i < nv; i++) for (let a = 0; a < 3; a++) all[a] += W[i * 3 + a] / nv;
const toAll = [all[0] - mean[0], all[1] - mean[1], all[2] - mean[2]];
if (dot(toAll, udir) < 0) udir = udir.map(x => -x);
if (dot(toAll, ndir) > 0) ndir = ndir.map(x => -x);
wdir = cross(udir, ndir);   // 右手系：x × y = z
console.log('窗 特征值', E.vals.map(x => x.toFixed(1)), '宽方向', wdir.map(x => x.toFixed(3)), '上', udir.map(x => x.toFixed(3)), '法线', ndir.map(x => x.toFixed(3)));
// 2) 换到窗的坐标（单位照原样），量窗的大小
const L = new Float64Array(nv * 3);
for (let i = 0; i < nv; i++) {
  const d = [W[i * 3] - mean[0], W[i * 3 + 1] - mean[1], W[i * 3 + 2] - mean[2]];
  L[i * 3] = dot(d, wdir); L[i * 3 + 1] = dot(d, udir); L[i * 3 + 2] = dot(d, ndir);
}
const gy = glass.map(i => L[i * 3 + 1]).sort((a, b) => a - b), gx = glass.map(i => L[i * 3]).sort((a, b) => a - b);
const q = (arr, f) => arr[Math.floor(f * (arr.length - 1))];
const gTop = q(gy, 0.98), gBot = q(gy, 0.02), gH = gTop - gBot, gW = q(gx, 0.98) - q(gx, 0.02);
const yCut = gTop + CUT * gH;
console.log('窗高', gH.toFixed(1), '窗宽', gW.toFixed(1), '截断 y', yCut.toFixed(1));
// 截断后的范围
const keep = [];
for (let t = 0; t < I0.length; t += 3) {
  const a = I0[t], b = I0[t + 1], c = I0[t + 2];
  if (L[a * 3 + 1] < yCut && L[b * 3 + 1] < yCut && L[c * 3 + 1] < yCut) keep.push(a, b, c);
}
console.log('留下三角形', keep.length / 3, '/', I0.length / 3);
// 3) 按位置焊接（0.5 单位）
const key = new Map(), remap = new Int32Array(nv).fill(-1), WP = [];
for (const i of new Set(keep)) {
  const k = `${Math.round(L[i * 3] * 2)},${Math.round(L[i * 3 + 1] * 2)},${Math.round(L[i * 3 + 2] * 2)}`;
  let j = key.get(k);
  if (j === undefined) { j = WP.length / 3; key.set(k, j); WP.push(L[i * 3], L[i * 3 + 1], L[i * 3 + 2]); }
  remap[i] = j;
}
let idx = [];
for (let t = 0; t < keep.length; t += 3) {
  const a = remap[keep[t]], b = remap[keep[t + 1]], c = remap[keep[t + 2]];
  if (a !== b && b !== c && a !== c) idx.push(a, b, c);
}
await MeshoptSimplifier.ready;
const pos32 = new Float32Array(WP);
const [simp, err] = MeshoptSimplifier.simplify(new Uint32Array(idx), pos32, 3, TARGET * 3, 0.05, []);
let tris = simp;
if (tris.length / 3 > TARGET * 1.3) {   // 拓扑卡住了：退到不管拓扑的
  tris = MeshoptSimplifier.simplifySloppy(new Uint32Array(idx), pos32, 3, TARGET * 3, 0.05)[0];
}
console.log('简化后', tris.length / 3, '个三角形，误差', err);
// 4) 每个三角形一格的贴图
const nt = tris.length / 3;
const G = Math.ceil(Math.sqrt(nt));
const cell = TEX / G, pad = 1.5;
const outImg = Buffer.alloc(TEX * TEX * 3, 60);
// 最近原顶点：哈希网格
const HS = 2.0;
const grid = new Map();
const hk = (x, y, z) => ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) | 0;
for (let i = 0; i < nv; i++) {
  if (L[i * 3 + 1] > yCut + 5) continue;
  const k = hk(Math.floor(L[i * 3] / HS), Math.floor(L[i * 3 + 1] / HS), Math.floor(L[i * 3 + 2] / HS));
  let a = grid.get(k); if (!a) { a = []; grid.set(k, a); } a.push(i);
}
function nearest(x, y, z) {
  const cx = Math.floor(x / HS), cy = Math.floor(y / HS), cz = Math.floor(z / HS);
  let best = -1, bd = Infinity;
  for (let r = 1; r <= 4 && best < 0; r++) {
    for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) for (let dz = -r; dz <= r; dz++) {
      const a = grid.get(hk(cx + dx, cy + dy, cz + dz));
      if (!a) continue;
      for (const i of a) {
        const ex = L[i * 3] - x, ey = L[i * 3 + 1] - y, ez = L[i * 3 + 2] - z;
        const d = ex * ex + ey * ey + ez * ez;
        if (d < bd) { bd = d; best = i; }
      }
    }
  }
  return best;
}
const outP = [], outN = [], outUV = [], outI = [];
for (let t = 0; t < nt; t++) {
  const ia = tris[t * 3], ib = tris[t * 3 + 1], ic = tris[t * 3 + 2];
  const A = [WP[ia * 3], WP[ia * 3 + 1], WP[ia * 3 + 2]], B = [WP[ib * 3], WP[ib * 3 + 1], WP[ib * 3 + 2]], Cc = [WP[ic * 3], WP[ic * 3 + 1], WP[ic * 3 + 2]];
  const e1 = [B[0] - A[0], B[1] - A[1], B[2] - A[2]], e2 = [Cc[0] - A[0], Cc[1] - A[1], Cc[2] - A[2]];
  const n = cross(e1, e2); const nl = Math.hypot(...n) || 1;
  const len1 = Math.hypot(...e1) || 1;
  const ux = e1.map(v => v / len1);
  const nn = n.map(v => v / nl);
  const uy = cross(nn, ux);
  // 三角形在自己平面里的二维坐标
  const a2 = [0, 0], b2 = [len1, 0], c2 = [dot(e2, ux), dot(e2, uy)];
  const minX = Math.min(0, c2[0]), maxX = Math.max(len1, c2[0]), minY = 0, maxY = Math.max(0, c2[1]);
  const s = (cell - pad * 2) / Math.max(maxX - minX, maxY - minY, 1e-6);
  const cx0 = (t % G) * cell + pad, cy0 = Math.floor(t / G) * cell + pad;
  const map2 = p => [cx0 + (p[0] - minX) * s, cy0 + (p[1] - minY) * s];
  const ta = map2(a2), tb = map2(b2), tc = map2(c2);
  // 烘：格子里每个像素 → 重心坐标（夹到三角形里：边上补一圈）→ 三维点 → 最近原顶点的颜色
  const x0 = Math.floor((t % G) * cell), y0 = Math.floor(Math.floor(t / G) * cell);
  const x1 = Math.min(TEX - 1, Math.ceil(x0 + cell)), y1 = Math.min(TEX - 1, Math.ceil(y0 + cell));
  const den = (tb[1] - tc[1]) * (ta[0] - tc[0]) + (tc[0] - tb[0]) * (ta[1] - tc[1]);
  for (let py = y0; py <= y1; py++) for (let px = x0; px <= x1; px++) {
    const X = px + 0.5, Y = py + 0.5;
    let l1 = ((tb[1] - tc[1]) * (X - tc[0]) + (tc[0] - tb[0]) * (Y - tc[1])) / den;
    let l2 = ((tc[1] - ta[1]) * (X - tc[0]) + (ta[0] - tc[0]) * (Y - tc[1])) / den;
    let l3 = 1 - l1 - l2;
    if (l1 < -0.6 || l2 < -0.6 || l3 < -0.6) continue;
    l1 = Math.max(0, l1); l2 = Math.max(0, l2); l3 = Math.max(0, l3);
    const sm = l1 + l2 + l3; l1 /= sm; l2 /= sm; l3 /= sm;
    const P = [A[0] * l1 + B[0] * l2 + Cc[0] * l3, A[1] * l1 + B[1] * l2 + Cc[1] * l3, A[2] * l1 + B[2] * l2 + Cc[2] * l3];
    const i = nearest(P[0], P[1], P[2]);
    if (i < 0) continue;
    const col = sample(UV0[i * 2], UV0[i * 2 + 1]);
    const k = (py * TEX + px) * 3;
    outImg[k] = col[0]; outImg[k + 1] = col[1]; outImg[k + 2] = col[2];
  }
  for (const [p, uv] of [[A, ta], [B, tb], [Cc, tc]]) {
    outP.push(p[0], p[1], p[2]);
    outN.push(nn[0], nn[1], nn[2]);
    outUV.push(uv[0] / TEX, uv[1] / TEX);
  }
  outI.push(t * 3, t * 3 + 1, t * 3 + 2);
}
// 平滑法线：同一位置、法线夹角 < 40° 的面一起平均
{
  const byPos = new Map();
  for (let v = 0; v < outP.length / 3; v++) {
    const k = `${Math.round(outP[v * 3] * 4)},${Math.round(outP[v * 3 + 1] * 4)},${Math.round(outP[v * 3 + 2] * 4)}`;
    let a = byPos.get(k); if (!a) { a = []; byPos.set(k, a); } a.push(v);
  }
  const N0 = outN.slice();
  const cosT = Math.cos(40 * Math.PI / 180);
  for (const a of byPos.values()) for (const v of a) {
    const s2 = [0, 0, 0];
    for (const w of a) {
      const d = N0[v * 3] * N0[w * 3] + N0[v * 3 + 1] * N0[w * 3 + 1] + N0[v * 3 + 2] * N0[w * 3 + 2];
      if (d >= cosT) { s2[0] += N0[w * 3]; s2[1] += N0[w * 3 + 1]; s2[2] += N0[w * 3 + 2]; }
    }
    const l = Math.hypot(...s2) || 1;
    outN[v * 3] = s2[0] / l; outN[v * 3 + 1] = s2[1] / l; outN[v * 3 + 2] = s2[2] / l;
  }
}
// 观察窗玻璃：扫描里是青灰的（拍的时候映着天光），车里看着发绿——压成偏冷的中性灰（用户 11-22：「现实中不带绿光」）
for (let k = 0; k < outImg.length; k += 3) {
  const r = outImg[k], g = outImg[k + 1], b = outImg[k + 2];
  if (g > r + 8 && b > r + 4 && g > 90 && g < 200 && Math.abs(g - b) < 40) {
    const lum = (0.3 * r + 0.59 * g + 0.11 * b) * 0.62;
    outImg[k] = Math.round(lum * 0.94); outImg[k + 1] = Math.round(lum * 0.98); outImg[k + 2] = Math.round(lum * 1.06);
  }
}
// 写 glb
const png = await sharp(outImg, { raw: { width: TEX, height: TEX, channels: 3 } }).jpeg({ quality: 90 }).toBuffer();
const d2 = new Document();
const buf = d2.createBuffer();
const acc = (arr, type) => d2.createAccessor().setType(type).setArray(arr).setBuffer(buf);
const t2 = d2.createTexture('baked').setImage(png).setMimeType('image/jpeg');
const mat = d2.createMaterial('periscope').setBaseColorTexture(t2).setMetallicFactor(0.15).setRoughnessFactor(0.75);
const pr = d2.createPrimitive().setAttribute('POSITION', acc(new Float32Array(outP), 'VEC3')).setAttribute('NORMAL', acc(new Float32Array(outN), 'VEC3'))
  .setAttribute('TEXCOORD_0', acc(new Float32Array(outUV), 'VEC2')).setIndices(acc(new Uint32Array(outI), 'SCALAR')).setMaterial(mat);
const mesh = d2.createMesh('periscope').addPrimitive(pr);
const nd = d2.createNode('periscope').setMesh(mesh);
d2.createScene('scene').addChild(nd);
await new NodeIO().write(out, d2);
let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
for (let v = 0; v < outP.length / 3; v++) for (let a = 0; a < 3; a++) { mn[a] = Math.min(mn[a], outP[v * 3 + a]); mx[a] = Math.max(mx[a], outP[v * 3 + a]); }
console.log('输出', out, '三角形', nt, '范围', mn.map(x => x.toFixed(1)), mx.map(x => x.toFixed(1)), '窗', JSON.stringify({ w: gW, h: gH, top: gTop, bot: gBot }));
