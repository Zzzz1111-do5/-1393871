// 枪械模型管线：Sketchfab 上的枪和配件（都是 CC-BY）→ 第一人称、改装界面用的网格和校准数据
//   用法（仓库根目录；先在 tools/weapons 里 npm ci）：node tools/weapons/build.mjs [原模型缓存目录] [预览图目录]
//     缓存目录默认 tools/weapons/cache（<键>/model.glb）；没有的从 Sketchfab 下载——密钥只从环境变量 SKETCHFAB_TOKEN 读，代码、仓库里都不放
//     环境变量 ONLY=键,键 只处理这几件、只出预览图（校准时用），不写游戏文件
//   每件（weapons.json 的 items）：挑零件（keep / drop：带网格的节点按遍历顺序的序号）→ axes / scale 转到「枪身骨骼」坐标
//     （格，+Z 朝枪口、+Y 朝上、+X 朝枪的左边，同 FPSView 的 M4）→ 按 pts.grip 对齐 M4 的握把（枪）→ 按连通块分部件（pieces：弹匣单独一块好做换弹）
//     → 按颜色把三角形分成几组（每组在游戏里是一个 MeshPart：一种颜色、一种材质；贴图的颜色按三角形取样折进去）→ 减面 → 按折角算法线
//   输出：src/ReplicatedStorage/GunMesh/<键>.lua（顶点、法线、三角形，base64；客户端用 EditableMesh 生成）、src/ReplicatedStorage/GunData.lua（零件表、颜色、校准点、署名）、
//     models/weapons.glb（给 Studio 导入：放进 ReplicatedStorage/Imported/Weapons 就优先用它）、models/credits.txt 里「第一人称的枪和配件」一节、预览图
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const CFG = JSON.parse(fs.readFileSync(path.join(HERE, 'weapons.json'), 'utf8'));
const CACHE = process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache');
const PREV = process.argv[3] ? path.resolve(process.argv[3]) : path.join(HERE, 'preview');
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;
fs.mkdirSync(PREV, { recursive: true });

// M4（FPSView 里动作包的枪）的校准点：别的枪的握把对到这儿，配件按各自的点装
const M4 = CFG.m4;

const s2l = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const l2s = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
const lum = (c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
const hex = (c) => (typeof c === 'string' ? [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16) / 255) : c.map((x) => (x > 1 ? x / 255 : x)));

// ---------------------------------------------------------------- 原模型：缓存里有就用，没有就下载

async function sourceFile(key) {
  const S = CFG.sources[key];
  if (S.file) return path.join(ROOT, S.file);
  const f = path.join(CACHE, key, 'model.glb');
  if (fs.existsSync(f)) return f;
  const tok = process.env.SKETCHFAB_TOKEN;
  if (!tok) throw new Error(`缓存里没有 ${key}（${S.name}）：设好环境变量 SKETCHFAB_TOKEN（自己 Sketchfab 账号的 API 密钥）再运行，或者把下载的 model.glb 放进 ${path.dirname(f)}`);
  const r = await fetch(`https://api.sketchfab.com/v3/models/${S.uid}/download`, { headers: { Authorization: 'Token ' + tok } });
  if (!r.ok) throw new Error(`下载 ${key} 失败：HTTP ${r.status}`);
  const j = await r.json();
  if (!j.glb) throw new Error(`${key} 没有 glb 格式的下载`);
  const b = Buffer.from(await (await fetch(j.glb.url)).arrayBuffer());
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, b);
  console.log('下载', key, b.length, '字节');
  return f;
}

// ---------------------------------------------------------------- 读一件：三角形（已转到枪身坐标）+ 每个三角形的颜色

function axesMat(axes, scale) {
  const R = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  axes.split(',').forEach((a, row) => { R[row]['xyz'.indexOf(a[a.length - 1])] = a[0] === '-' ? -1 : 1; });
  const det = R[0][0] * (R[1][1] * R[2][2] - R[1][2] * R[2][1]) - R[0][1] * (R[1][0] * R[2][2] - R[1][2] * R[2][0]) + R[0][2] * (R[1][0] * R[2][1] - R[1][1] * R[2][0]);
  if (det < 0) throw new Error(`axes ${axes} 是镜像的（行列式 < 0）`);
  return R.map((r) => r.map((v) => v * scale));
}

const texCache = new Map();
async function texSampler(tex) {
  if (texCache.has(tex)) return texCache.get(tex);
  const { data, info } = await sharp(Buffer.from(tex.getImage())).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const f = (u, v) => {
    u -= Math.floor(u); v -= Math.floor(v);
    const x = Math.min(info.width - 1, Math.floor(u * info.width)), y = Math.min(info.height - 1, Math.floor(v * info.height));
    const i = (y * info.width + x) * 4;
    return [data[i] / 255, data[i + 1] / 255, data[i + 2] / 255];
  };
  texCache.set(tex, f);
  return f;
}

async function loadItem(key, I) {
  const doc = await io.read(await sourceFile(I.src));
  const scene = doc.getRoot().getDefaultScene() || doc.getRoot().listScenes()[0];
  const A = axesMat(I.axes || 'x,y,z', I.scale || 1);
  const pre = I.pre || [0, 0, 0];   // 先平移（原模型坐标，乘 scale 之前）
  const nodes = [];
  scene.traverse((n) => { if (n.getMesh()) nodes.push(n); });
  const P = [], T = [];   // P：顶点 xyz；T：{ a, b, c, col, met, glass, node }
  for (let k = 0; k < nodes.length; k++) {
    if (I.keep ? !I.keep.includes(k) : (I.drop || []).includes(k)) continue;
    const n = nodes[k];
    const M = n.getWorldMatrix();
    const nOff = (I.nodeOff && I.nodeOff[k]) || [0, 0, 0];
    for (const p of n.getMesh().listPrimitives()) {
      if (p.getMode() !== 4) continue;
      const pos = p.getAttribute('POSITION'), uv = p.getAttribute('TEXCOORD_0'), idx = p.getIndices();
      const mat = p.getMaterial();
      const fac = mat ? mat.getBaseColorFactor() : [0.6, 0.6, 0.6, 1];
      const tex = mat && mat.getBaseColorTexture();
      const samp = tex && uv ? await texSampler(tex) : null;
      const name = mat ? mat.getName() || '' : '';
      const glass = !!mat && (mat.getAlphaMode() === 'BLEND' || /glass|lens|polycarb/i.test(name));
      const met = mat ? mat.getMetallicFactor() : 0;
      const base = P.length / 3;
      const e = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) {
        pos.getElement(i, e);
        const w = [M[0] * e[0] + M[4] * e[1] + M[8] * e[2] + M[12] + pre[0], M[1] * e[0] + M[5] * e[1] + M[9] * e[2] + M[13] + pre[1], M[2] * e[0] + M[6] * e[1] + M[10] * e[2] + M[14] + pre[2]];
        for (let r = 0; r < 3; r++) P.push(A[r][0] * w[0] + A[r][1] * w[1] + A[r][2] * w[2] + nOff[r]);
      }
      const cnt = idx ? idx.getCount() : pos.getCount();
      const t2 = [0, 0];
      for (let i = 0; i + 2 < cnt; i += 3) {
        const a = idx ? idx.getScalar(i) : i, b = idx ? idx.getScalar(i + 1) : i + 1, c = idx ? idx.getScalar(i + 2) : i + 2;
        let col = [l2s(fac[0]), l2s(fac[1]), l2s(fac[2])];
        if (samp) {   // 贴图：三个角和中心取样平均（sRGB → 线性乘底色 → sRGB）
          const acc = [0, 0, 0], U = [], Vv = [];
          for (const v of [a, b, c]) { uv.getElement(v, t2); U.push(t2[0]); Vv.push(t2[1]); }
          const pts = [[U[0], Vv[0]], [U[1], Vv[1]], [U[2], Vv[2]], [(U[0] + U[1] + U[2]) / 3, (Vv[0] + Vv[1] + Vv[2]) / 3]];
          for (const [u, v] of pts) { const s = samp(u, v); for (let q = 0; q < 3; q++) acc[q] += s2l(s[q]) * fac[q]; }
          col = acc.map((x) => l2s(x / pts.length));
        }
        T.push({ a: base + a, b: base + b, c: base + c, col, met, glass, node: k });
      }
    }
  }
  return { P, T };
}

// ---------------------------------------------------------------- 焊接、连通块、部件、颜色分组

function weldAndSplit(P, T, eps = 1e-4) {
  const map = new Map(), W = [], remap = new Int32Array(P.length / 3);
  for (let i = 0; i < P.length / 3; i++) {
    const k = `${Math.round(P[i * 3] / eps)},${Math.round(P[i * 3 + 1] / eps)},${Math.round(P[i * 3 + 2] / eps)}`;
    let id = map.get(k);
    if (id === undefined) { id = W.length / 3; map.set(k, id); W.push(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]); }
    remap[i] = id;
  }
  const tris = [];
  for (const t of T) {
    const a = remap[t.a], b = remap[t.b], c = remap[t.c];
    if (a === b || b === c || a === c) continue;
    tris.push({ ...t, a, b, c });
  }
  // 连通块（共用焊接后的顶点）
  const par = new Int32Array(W.length / 3).map((_, i) => i);
  const find = (x) => { while (par[x] !== x) { par[x] = par[par[x]]; x = par[x]; } return x; };
  for (const t of tris) { const ra = find(t.a), rb = find(t.b), rc = find(t.c); par[rb] = ra; par[find(rc)] = ra; }
  const comp = new Map();
  for (const t of tris) {
    const r = find(t.a);
    let C = comp.get(r);
    if (!C) { C = { tris: [], mn: [1e9, 1e9, 1e9], mx: [-1e9, -1e9, -1e9], node: t.node }; comp.set(r, C); }
    C.tris.push(t);
    for (const v of [t.a, t.b, t.c]) for (let q = 0; q < 3; q++) { C.mn[q] = Math.min(C.mn[q], W[v * 3 + q]); C.mx[q] = Math.max(C.mx[q], W[v * 3 + q]); }
  }
  return { W, tris, comps: [...comp.values()] };
}

// 部件规则：{ name, nodes: [节点序号] } 或 { name, box: [x0, y0, z0, x1, y1, z1] }（连通块的包围盒中心在盒子里；坐标是对齐前的）
function assignPieces(comps, rules) {
  for (const C of comps) {
    C.piece = 'body';
    const c = [0, 1, 2].map((q) => (C.mn[q] + C.mx[q]) / 2);
    for (const r of rules || []) {
      const hitNode = r.nodes && C.tris.some((t) => r.nodes.includes(t.node));
      const b = r.box;
      const hitBox = b && c[0] >= b[0] && c[0] <= b[3] && c[1] >= b[1] && c[1] <= b[4] && c[2] >= b[2] && c[2] <= b[5];
      if (hitNode || hitBox) { C.piece = r.name; break; }
    }
  }
}

function triArea(W, t) {
  const a = [W[t.a * 3], W[t.a * 3 + 1], W[t.a * 3 + 2]], b = [W[t.b * 3], W[t.b * 3 + 1], W[t.b * 3 + 2]], c = [W[t.c * 3], W[t.c * 3 + 1], W[t.c * 3 + 2]];
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  return Math.hypot(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]) / 2;
}

// 颜色分组：玻璃单独一组，其余按颜色做 k 均值（面积加权），组按亮度从暗到亮叫 g1、g2……
function colorGroups(W, tris, k) {
  const solid = tris.filter((t) => !t.glass);
  for (const t of tris) t.area = triArea(W, t);
  const groups = [];
  if (solid.length) {
    const sorted = [...solid].sort((a, b) => lum(a.col) - lum(b.col));
    let cent = [];
    for (let i = 0; i < k; i++) cent.push(sorted[Math.min(sorted.length - 1, Math.floor((i + 0.5) / k * sorted.length))].col.slice());
    const d2 = (a, b) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
    for (let it = 0; it < 25; it++) {
      const acc = cent.map(() => [0, 0, 0, 0]);
      for (const t of solid) {
        let bi = 0;
        for (let j = 1; j < cent.length; j++) if (d2(t.col, cent[j]) < d2(t.col, cent[bi])) bi = j;
        t.gi = bi;
        for (let q = 0; q < 3; q++) acc[bi][q] += t.col[q] * t.area;
        acc[bi][3] += t.area;
      }
      cent = cent.map((c, j) => (acc[j][3] > 0 ? acc[j].slice(0, 3).map((x) => x / acc[j][3]) : c));
    }
    // 颜色几乎一样的两组并成一组
    const alive = cent.map(() => true);
    for (let i = 0; i < cent.length; i++) for (let j = i + 1; j < cent.length; j++) {
      if (alive[i] && alive[j] && d2(cent[i], cent[j]) < 0.0009) { alive[j] = false; for (const t of solid) if (t.gi === j) t.gi = i; }
    }
    const order = cent.map((c, i) => i).filter((i) => alive[i] && solid.some((t) => t.gi === i)).sort((a, b) => lum(cent[a]) - lum(cent[b]));
    order.forEach((ci, rank) => {
      const ts = solid.filter((t) => t.gi === ci);
      const area = ts.reduce((s, t) => s + t.area, 0);
      const met = ts.reduce((s, t) => s + t.met * t.area, 0) / (area || 1);
      groups.push({ name: 'g' + (rank + 1), col: cent[ci], met, tris: ts });
    });
  }
  const gl = tris.filter((t) => t.glass);
  if (gl.length) groups.push({ name: 'glass', col: [0.16, 0.2, 0.22], met: 0, glass: true, tris: gl });
  return groups;
}

// ---------------------------------------------------------------- 减面、法线

function subMesh(W, tris) {
  const map = new Map(), pos = [];
  const idx = new Uint32Array(tris.length * 3);
  tris.forEach((t, i) => [t.a, t.b, t.c].forEach((v, q) => {
    let id = map.get(v);
    if (id === undefined) { id = pos.length / 3; map.set(v, id); pos.push(W[v * 3], W[v * 3 + 1], W[v * 3 + 2]); }
    idx[i * 3 + q] = id;
  }));
  return { pos: new Float32Array(pos), idx };
}

function simplify(m, ratio, err) {
  if (ratio >= 0.999 || m.idx.length < 300) return m;
  const target = Math.max(36, Math.floor(m.idx.length / 3 * ratio) * 3);
  const [idx] = MeshoptSimplifier.simplify(m.idx, m.pos, 3, target, err, []);
  return { pos: m.pos, idx };
}

// 法线：相邻面夹角小于 crease 的算平滑，大于的分开（硬边）
function withNormals(m, creaseDeg = 38) {
  const cosC = Math.cos(creaseDeg * Math.PI / 180);
  const nt = m.idx.length / 3;
  const fn = new Float32Array(nt * 3);
  const vf = new Map();
  for (let f = 0; f < nt; f++) {
    const [a, b, c] = [m.idx[f * 3], m.idx[f * 3 + 1], m.idx[f * 3 + 2]];
    const A = [m.pos[a * 3], m.pos[a * 3 + 1], m.pos[a * 3 + 2]], B = [m.pos[b * 3], m.pos[b * 3 + 1], m.pos[b * 3 + 2]], C = [m.pos[c * 3], m.pos[c * 3 + 1], m.pos[c * 3 + 2]];
    const u = [B[0] - A[0], B[1] - A[1], B[2] - A[2]], v = [C[0] - A[0], C[1] - A[1], C[2] - A[2]];
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];   // 长度 = 两倍面积（面积加权）
    fn.set(n, f * 3);
    for (const x of [a, b, c]) { if (!vf.has(x)) vf.set(x, []); vf.get(x).push(f); }
  }
  const unit = (f) => { const l = Math.hypot(fn[f * 3], fn[f * 3 + 1], fn[f * 3 + 2]) || 1; return [fn[f * 3] / l, fn[f * 3 + 1] / l, fn[f * 3 + 2] / l]; };
  const outP = [], outN = [], outI = new Uint32Array(m.idx.length), key = new Map();
  for (let f = 0; f < nt; f++) {
    const uf = unit(f);
    for (let q = 0; q < 3; q++) {
      const v = m.idx[f * 3 + q];
      const s = [0, 0, 0];
      for (const g of vf.get(v)) {
        const ug = unit(g);
        if (uf[0] * ug[0] + uf[1] * ug[1] + uf[2] * ug[2] >= cosC) { s[0] += fn[g * 3]; s[1] += fn[g * 3 + 1]; s[2] += fn[g * 3 + 2]; }
      }
      const l = Math.hypot(...s) || 1;
      const n = [Math.round(s[0] / l * 127), Math.round(s[1] / l * 127), Math.round(s[2] / l * 127)];
      const k = `${v},${n}`;
      let id = key.get(k);
      if (id === undefined) { id = outP.length / 3; key.set(k, id); outP.push(m.pos[v * 3], m.pos[v * 3 + 1], m.pos[v * 3 + 2]); outN.push(...n); }
      outI[f * 3 + q] = id;
    }
  }
  return { pos: new Float32Array(outP), nrm: new Int8Array(outN), idx: outI };
}

// ---------------------------------------------------------------- 预览：正交侧视（从 +X 看：横 Z、竖 Y）、俯视、正视，带刻度

async function render(file, layers, opt = {}) {
  const view = opt.view || 'side';
  const pick = { side: [2, 1, 0], top: [2, 0, 1], front: [0, 1, 2], back: [0, 1, 2] }[view];
  const sgnU = view === 'front' ? -1 : 1;   // 正视：从枪口往回看（−Z 方向看过去，+X 在右）
  let mn = [1e9, 1e9], mx = [-1e9, -1e9];
  for (const L of layers) for (let i = 0; i < L.pos.length; i += 3) {
    const u = sgnU * L.pos[i + pick[0]], v = view === 'top' ? -L.pos[i + pick[1]] : L.pos[i + pick[1]];
    mn = [Math.min(mn[0], u), Math.min(mn[1], v)]; mx = [Math.max(mx[0], u), Math.max(mx[1], v)];
  }
  if (opt.box) { mn = [opt.box[0], opt.box[1]]; mx = [opt.box[2], opt.box[3]]; }
  const pad = 0.08 * Math.max(mx[0] - mn[0], mx[1] - mn[1]);
  mn = [mn[0] - pad, mn[1] - pad]; mx = [mx[0] + pad, mx[1] + pad];
  const Wd = opt.width || 1600, Ht = Math.max(240, Math.round(Wd * (mx[1] - mn[1]) / (mx[0] - mn[0])));
  const img = Buffer.alloc(Wd * Ht * 3);
  for (let i = 0; i < Wd * Ht; i++) { img[i * 3] = 226; img[i * 3 + 1] = 228; img[i * 3 + 2] = 230; }
  const zb = new Float32Array(Wd * Ht).fill(-1e9);
  const sx = (u) => (u - mn[0]) / (mx[0] - mn[0]) * Wd, sy = (v) => Ht - (v - mn[1]) / (mx[1] - mn[1]) * Ht;
  const depth = (p) => (view === 'side' ? p[0] : view === 'top' ? p[1] : view === 'front' ? p[2] : -p[2]);
  for (const L of layers) {
    for (let f = 0; f < L.idx.length; f += 3) {
      const V3 = [L.idx[f], L.idx[f + 1], L.idx[f + 2]].map((v) => [L.pos[v * 3], L.pos[v * 3 + 1], L.pos[v * 3 + 2]]);
      const col = L.cols ? L.cols[f / 3] : L.col;
      const u1 = V3[1].map((x, q) => x - V3[0][q]), u2 = V3[2].map((x, q) => x - V3[0][q]);
      const n = [u1[1] * u2[2] - u1[2] * u2[1], u1[2] * u2[0] - u1[0] * u2[2], u1[0] * u2[1] - u1[1] * u2[0]];
      const nl = Math.hypot(...n) || 1;
      const Ld = [0.45, 0.8, 0.4], Ll = Math.hypot(...Ld);
      const lit = 0.42 + 0.58 * Math.abs((n[0] * Ld[0] + n[1] * Ld[1] + n[2] * Ld[2]) / nl / Ll);
      const S = V3.map((p) => [sx(sgnU * p[pick[0]]), sy(view === 'top' ? -p[pick[1]] : p[pick[1]]), depth(p) + (L.zbias || 0)]);
      const x0 = Math.max(0, Math.floor(Math.min(S[0][0], S[1][0], S[2][0]))), x1 = Math.min(Wd - 1, Math.ceil(Math.max(S[0][0], S[1][0], S[2][0])));
      const y0 = Math.max(0, Math.floor(Math.min(S[0][1], S[1][1], S[2][1]))), y1 = Math.min(Ht - 1, Math.ceil(Math.max(S[0][1], S[1][1], S[2][1])));
      const den = (S[1][1] - S[2][1]) * (S[0][0] - S[2][0]) + (S[2][0] - S[1][0]) * (S[0][1] - S[2][1]);
      if (Math.abs(den) < 1e-9) continue;
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
        const w0 = ((S[1][1] - S[2][1]) * (x + 0.5 - S[2][0]) + (S[2][0] - S[1][0]) * (y + 0.5 - S[2][1])) / den;
        const w1 = ((S[2][1] - S[0][1]) * (x + 0.5 - S[2][0]) + (S[0][0] - S[2][0]) * (y + 0.5 - S[2][1])) / den;
        const w2 = 1 - w0 - w1;
        if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        const i = y * Wd + x;
        if (L.flat) {   // 底图（M4 的剪影）：只涂淡色，不挡别的
          if (zb[i] > -1e8) continue;
          img[i * 3] = Math.round(img[i * 3] * 0.55 + col[0] * 255 * 0.45); img[i * 3 + 1] = Math.round(img[i * 3 + 1] * 0.55 + col[1] * 255 * 0.45); img[i * 3 + 2] = Math.round(img[i * 3 + 2] * 0.55 + col[2] * 255 * 0.45);
          zb[i] = -1e8;
          continue;
        }
        const z = w0 * S[0][2] + w1 * S[1][2] + w2 * S[2][2];
        if (z <= zb[i]) continue;
        zb[i] = z;
        const k = lit, a = L.alpha == null ? 1 : L.alpha;
        for (let q = 0; q < 3; q++) img[i * 3 + q] = Math.round(img[i * 3 + q] * (1 - a) + Math.min(255, (col[q] * 0.85 + 0.06) * 255 * k) * a);
      }
    }
  }
  // 刻度：每 0.05 格淡线、0.1 格深一点，标数字
  const step = (mx[0] - mn[0]) > 3 ? 0.1 : 0.05;
  let svg = `<svg width="${Wd}" height="${Ht}" xmlns="http://www.w3.org/2000/svg" font-family="monospace" font-size="13">`;
  for (let u = Math.ceil(mn[0] / step) * step; u <= mx[0]; u += step) {
    const x = sx(u).toFixed(1), major = Math.abs(Math.round(u * 10) - u * 10) < 1e-6;
    svg += `<line x1="${x}" y1="0" x2="${x}" y2="${Ht}" stroke="${Math.abs(u) < 1e-6 ? '#d33' : '#000'}" stroke-opacity="${major ? 0.22 : 0.08}"/>`;
    if (major) svg += `<text x="${+x + 2}" y="${Ht - 4}" fill="#333">${(sgnU * u).toFixed(1)}</text>`;
  }
  for (let v = Math.ceil(mn[1] / step) * step; v <= mx[1]; v += step) {
    const y = sy(v).toFixed(1), major = Math.abs(Math.round(v * 10) - v * 10) < 1e-6;
    svg += `<line x1="0" y1="${y}" x2="${Wd}" y2="${y}" stroke="${Math.abs(v) < 1e-6 ? '#d33' : '#000'}" stroke-opacity="${major ? 0.22 : 0.08}"/>`;
    if (major) svg += `<text x="3" y="${+y - 3}" fill="#333">${(view === 'top' ? -v : v).toFixed(1)}</text>`;
  }
  for (const m of opt.marks || []) {   // 校准点：{ p: [x, y, z], c: 颜色, t: 字 }
    const u = sgnU * m.p[pick[0]], v = view === 'top' ? -m.p[pick[1]] : m.p[pick[1]];
    const x = sx(u), y = sy(v);
    svg += `<circle cx="${x}" cy="${y}" r="5" fill="none" stroke="${m.c}" stroke-width="2"/><line x1="${x - 9}" y1="${y}" x2="${x + 9}" y2="${y}" stroke="${m.c}"/><line x1="${x}" y1="${y - 9}" x2="${x}" y2="${y + 9}" stroke="${m.c}"/>`;
    if (m.t) svg += `<text x="${x + 7}" y="${y - 7}" fill="${m.c}" font-weight="bold">${m.t}</text>`;
  }
  for (const s of opt.segs || []) {   // 线段：{ a: [x,y,z], b: [x,y,z], c }
    const pa = [sx(sgnU * s.a[pick[0]]), sy(view === 'top' ? -s.a[pick[1]] : s.a[pick[1]])], pb = [sx(sgnU * s.b[pick[0]]), sy(view === 'top' ? -s.b[pick[1]] : s.b[pick[1]])];
    svg += `<line x1="${pa[0]}" y1="${pa[1]}" x2="${pb[0]}" y2="${pb[1]}" stroke="${s.c}" stroke-width="2"/>`;
  }
  if (opt.title) svg += `<text x="8" y="18" font-size="15" font-weight="bold" fill="#111">${opt.title}</text>`;
  svg += '</svg>';
  await sharp(img, { raw: { width: Wd, height: Ht, channels: 3 } }).composite([{ input: Buffer.from(svg) }]).png().toFile(file);
}

// ---------------------------------------------------------------- 处理全部

const OUT = {};       // [键] = { kind, parts: [{ n, p, g, col, mat, glass, pos, nrm, idx }], pts }
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const shiftPts = (pts, off) => {   // 校准点跟着平移：[x,y,z] 三元数组整体平移；rail / under 这种 { y, z0, z1 } 平移 y、z
  const o = {};
  for (const [k, v] of Object.entries(pts || {})) {
    if (Array.isArray(v) && v.length === 3) o[k] = add(v, off);
    else if (v && typeof v === 'object' && !Array.isArray(v)) {
      const w = { ...v };
      if (w.x != null) w.x += off[0];
      if (w.y != null) w.y += off[1];
      for (const z of ['z', 'z0', 'z1']) if (w[z] != null) w[z] += off[2];
      for (const r of ['r', 'f']) if (Array.isArray(w[r])) w[r] = [w[r][0] + off[1], w[r][1] + off[2]];
      o[k] = w;
    } else o[k] = v;
  }
  return o;
};

const keys = Object.keys(CFG.items).filter((k) => !ONLY || ONLY.includes(k) || k === 'm4');
let m4Layer = null;
for (const key of keys) {
  const I = CFG.items[key];
  const t0 = Date.now();
  const { P, T } = await loadItem(key, I);
  const { W, tris, comps } = weldAndSplit(P, T);
  assignPieces(comps, I.pieces);
  // 对齐：枪的握把对到 M4 的握把（offAdj 再微调）；配件的 off 直接写
  let off = I.off || [0, 0, 0];
  if (I.kind === 'gun' && I.pts && I.pts.grip && key !== 'm4') off = add([M4.grip[0] - I.pts.grip[0], M4.grip[1] - I.pts.grip[1], M4.grip[2] - I.pts.grip[2]], I.offAdj || [0, 0, 0]);
  for (let i = 0; i < W.length; i += 3) { W[i] += off[0]; W[i + 1] += off[1]; W[i + 2] += off[2]; }
  const pts = shiftPts(I.pts, off);
  // 部件 × 颜色组
  const total = tris.length;
  const ratio = Math.min(1, (I.tris || 4000) / total);
  const parts = [];
  const pieceNames = [...new Set(comps.map((c) => c.piece))];
  for (const pn of pieceNames) {
    const pt = comps.filter((c) => c.piece === pn).flatMap((c) => c.tris);
    const groups = colorGroups(W, pt, I.k || 3);
    for (const g of groups) {
      let m = subMesh(W, g.tris);
      m = simplify(m, ratio, I.err || 0.004);
      const nm = withNormals(m, I.crease || 38);
      const paint = (I.paint && (I.paint[`${pn}.${g.name}`] || I.paint[g.name])) || null;
      const col = paint ? hex(paint.c || paint) : g.col;
      const mat = (paint && paint.m) || (g.glass ? 'Glass' : g.met > 0.3 ? 'Metal' : 'SmoothPlastic');
      parts.push({ n: `${key}_${pn}_${g.name}`, p: pn, g: g.name, col, mat, glass: !!g.glass, tr: paint && paint.t, ...nm });
    }
  }
  OUT[key] = { kind: I.kind, parts, pts, off };
  // 量尺寸（校准用）：MEASURE="y=0.1,0.2;z=0.5" 打印这几个水平面（y）上几何的 z 区间、几个竖直面（z）上的 y 区间（对齐后的坐标）
  if (process.env.MEASURE) {
    for (const spec of process.env.MEASURE.split(';')) {
      const [ax, list] = spec.split('=');
      const q = ax === 'y' ? 1 : ax === 'z' ? 2 : 0, o = ax === 'y' ? 2 : 1;
      for (const cs of list.split(',')) {
        const c = +cs, iv = [];
        for (const p of parts) for (let f = 0; f < p.idx.length; f += 3) {
          const V3 = [p.idx[f], p.idx[f + 1], p.idx[f + 2]].map((v) => [p.pos[v * 3], p.pos[v * 3 + 1], p.pos[v * 3 + 2]]);
          const hits = [];
          for (let e = 0; e < 3; e++) {
            const a = V3[e], b = V3[(e + 1) % 3];
            if ((a[q] - c) * (b[q] - c) <= 0 && a[q] !== b[q]) { const t = (c - a[q]) / (b[q] - a[q]); hits.push(a[o] + (b[o] - a[o]) * t); }
          }
          if (hits.length >= 2) iv.push([Math.min(...hits), Math.max(...hits)]);
        }
        iv.sort((a, b) => a[0] - b[0]);
        const m = [];
        for (const v of iv) { if (m.length && v[0] <= m[m.length - 1][1] + 0.004) m[m.length - 1][1] = Math.max(m[m.length - 1][1], v[1]); else m.push(v.slice()); }
        console.log(`  ${key} ${ax}=${c}: ${'yz'[o - 1]} ∈ ` + m.map((v) => `${v[0].toFixed(3)}～${v[1].toFixed(3)}`).join('  '));
      }
    }
  }
  const nt = parts.reduce((s, p) => s + p.idx.length / 3, 0), nv = parts.reduce((s, p) => s + p.pos.length / 3, 0);
  console.log(key.padEnd(8), '三角形', total, '→', nt, '顶点', nv, '部件', pieceNames.join('/'), '组', parts.length, `${Date.now() - t0}ms`);
  // 预览
  const layer = (p) => ({ pos: p.pos, idx: p.idx, col: p.col, alpha: p.glass ? 0.35 : 1 });
  if (key === 'm4') { m4Layer = parts.map((p) => ({ pos: p.pos, idx: p.idx, col: [0.95, 0.35, 0.3], flat: true })); }
  const marks = [];
  const C = { grip: '#e0218a', lh: '#1f8fff', muzzle: '#ff7a00', side: '#00a86b', mag: '#8a2be2' };
  for (const [k, v] of Object.entries(pts)) if (Array.isArray(v) && v.length === 3) marks.push({ p: v, c: C[k] || '#222', t: k });
  const segs = [];
  if (pts.rail) segs.push({ a: [0, pts.rail.y, pts.rail.z0], b: [0, pts.rail.y, pts.rail.z1], c: '#00b3b3' });
  if (pts.under) segs.push({ a: [0, pts.under.y, pts.under.z0], b: [0, pts.under.y, pts.under.z1], c: '#b38f00' });
  if (pts.iron) segs.push({ a: [0, pts.iron.r[0], pts.iron.r[1]], b: [0, pts.iron.f[0], pts.iron.f[1]], c: '#d40000' });
  const base = I.kind === 'gun' && key !== 'm4' && m4Layer ? m4Layer : [];
  for (const view of I.views || ['side']) await render(path.join(PREV, `${key}_${view}.png`), [...base, ...parts.map(layer)], { view, marks, segs, title: `${key} ${view}` });
}

// ---------------------------------------------------------------- 配件装上去看看（同 FPSView 的装法）

export function mountCF(gun, slot, att) { return null; }
if (ONLY) process.exit(0);
console.log('（ONLY 没设：写游戏文件这一步还没做）');
