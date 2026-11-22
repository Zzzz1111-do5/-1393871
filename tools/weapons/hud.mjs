// 飞机座舱平显（光学瞄准屏）的原模型搬进 Roblox（用户 11-22：「去 Sketchfab 上找模型，把飞机驾驶舱的光学瞄准屏直接搬来用」，
//   「我记得 j15t 原模型在 Sketchfab 自带内饰」）
//   原模型：J-15T with YJ-83K，作者 Jeyhun1985（https://sketchfab.com/3d-models/b416034f0cde4e46b37cf3e5445bd1b7），CC-BY-4.0——
//     游戏里歼-15T 的外模型也是它（models/air/j15t.glb）；它自带整个座舱（弹射座椅、仪表板、两边操纵台、后视镜、平显）。
//     这里只把平显那一套抠出来：两根弧形立柱 + 顶梁（黑色框）、下面的投影仪壳子（Frame），组合玻璃（Glass）
//   用法（仓库根目录；先在 tools/weapons 里 npm ci）：node tools/weapons/hud.mjs [原模型缓存目录] [预览图目录]
//     缓存里没有原模型就从 Sketchfab 下载（密钥只从环境变量 SKETCHFAB_TOKEN 读）
//   做法：原模型按材质并成了几十块大网格（整架飞机的同一种材质在一块里），平显散在其中两三块里——
//     按连通块挑：一个连通块整个落在平显那一小块空间里（BOX）才要（座舱壳、风挡框这些大东西只是穿过这里，整块不要）
//   坐标换成「平显坐标」：原点在组合玻璃的包围盒中心，+X 飞行员看来的右边，+Y 上，+Z 朝飞行员（原模型机头朝 +Z：绕 Y 转半圈），单位格（1 米 = 2.8 格）
//   输出：models/optics/hud15.glb（给 Studio「导入 3D」：块叫 O_hud15__Frame / Glass，开服时 Imports.lua 收进 ReplicatedStorage.Imported.Optics.hud15）、
//     src/ReplicatedStorage/HudMeta.lua（每块在平显坐标里的中心、大小（米），组合玻璃的大小、斜度，署名）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const KEY = 'hud15';
const UID = 'b416034f0cde4e46b37cf3e5445bd1b7';
const CACHE = process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache');
const SRC = path.join(CACHE, 'j15tsrc', 'model.glb');
const OUT = path.join(ROOT, 'models', 'optics', KEY + '.glb');
const META = path.join(ROOT, 'src', 'ReplicatedStorage', 'HudMeta.lua');
const S = 2.8;   // 1 米多少格
// 平显那一小块空间（原模型坐标，米；机头 +Z）：连通块整个在里面才要
const BOX = [-0.16, 0.84, 8.36, 0.16, 1.20, 8.64];   // 上面不到 1.2（风挡框上的后视镜不要）、左右不出 0.16（两边的导轨、电缆不要）
// 材质 → 块：座舱贴图集（黑框、投影仪）→ Frame；有色透明玻璃（组合玻璃）→ Glass；别的材质（机身外皮、风挡玻璃）不要
const MATS = { 'e473a719-61a1-4661-a0ce-2098c76de6a1': 'Frame', '85aee3ae-b845-4f0d-90c2-0b6c0c8b1ae8': 'Glass' };

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
async function source() {
  if (fs.existsSync(SRC)) return SRC;
  const tok = process.env.SKETCHFAB_TOKEN;
  if (!tok) throw new Error(`缓存里没有原模型：设好环境变量 SKETCHFAB_TOKEN 再运行，或者把 Sketchfab 上下载的 glb 放到 ${SRC}`);
  const r = await fetch(`https://api.sketchfab.com/v3/models/${UID}/download`, { headers: { Authorization: 'Token ' + tok } });
  if (!r.ok) throw new Error('下载失败：HTTP ' + r.status);
  const j = await r.json();
  const b = Buffer.from(await (await fetch(j.glb.url)).arrayBuffer());
  fs.mkdirSync(path.dirname(SRC), { recursive: true });
  fs.writeFileSync(SRC, b);
  return SRC;
}

const doc = await io.read(await source());
const root = doc.getRoot();
const scene = root.listScenes()[0];
const meshNodes = [];
scene.traverse((n) => { if (n.getMesh()) meshNodes.push(n); });
const world = (M, e) => [M[0] * e[0] + M[4] * e[1] + M[8] * e[2] + M[12], M[1] * e[0] + M[5] * e[1] + M[9] * e[2] + M[13], M[2] * e[0] + M[6] * e[1] + M[10] * e[2] + M[14]];
const wdir = (M, e) => [M[0] * e[0] + M[4] * e[1] + M[8] * e[2], M[1] * e[0] + M[5] * e[1] + M[9] * e[2], M[2] * e[0] + M[6] * e[1] + M[10] * e[2]];
const inBox = (mn, mx) => mn[0] >= BOX[0] && mn[1] >= BOX[1] && mn[2] >= BOX[2] && mx[0] <= BOX[3] && mx[1] <= BOX[4] && mx[2] <= BOX[5];

// 第一遍：每个图元按连通块挑三角形（世界坐标）
const picked = [];   // { part, prim, M, W（世界坐标顶点）, tris（三角形顶点下标） }
for (const n of meshNodes) {
  const M = n.getWorldMatrix();
  for (const p of n.getMesh().listPrimitives()) {
    const mat = p.getMaterial();
    const part = mat && MATS[mat.getName()];
    const idx = p.getIndices();
    if (!part || !idx) continue;
    const pos = p.getAttribute('POSITION');
    const cnt = pos.getCount(), e = [0, 0, 0];
    const W = new Array(cnt);
    for (let i = 0; i < cnt; i++) W[i] = world(M, pos.getElement(i, e));
    // 连通：同一个位置的顶点算一个（UV 缝上的顶点是分开存的）
    const key = new Map(), vid = new Int32Array(cnt);
    for (let i = 0; i < cnt; i++) {
      const k = W[i].map((v) => Math.round(v * 1e4)).join(',');
      let id = key.get(k);
      if (id === undefined) { id = key.size; key.set(k, id); }
      vid[i] = id;
    }
    const par = new Int32Array(key.size).map((_, i) => i);
    const find = (x) => { while (par[x] !== x) { par[x] = par[par[x]]; x = par[x]; } return x; };
    const ia = idx.getArray();
    // 先粗筛：三角形中心在盒子外面老远的不管（大网格几十万个三角形）
    const near = [];
    const pad = 0.6;
    for (let t = 0; t < ia.length; t += 3) {
      const a = W[ia[t]];
      if (a[0] < BOX[0] - pad || a[0] > BOX[3] + pad || a[1] < BOX[1] - pad || a[1] > BOX[4] + pad || a[2] < BOX[2] - pad || a[2] > BOX[5] + pad) continue;
      near.push(t);
      const r0 = find(vid[ia[t]]);
      par[find(vid[ia[t + 1]])] = r0;
      par[find(vid[ia[t + 2]])] = find(r0);
    }
    // 连通块的包围盒（只算挨着盒子的那些三角形；穿出粗筛范围的大块，它在范围里的部分也会伸出盒子，照样不要）
    const box = new Map();
    for (const t of near) {
      const r = find(vid[ia[t]]);
      let b = box.get(r);
      if (!b) { b = { mn: [1e9, 1e9, 1e9], mx: [-1e9, -1e9, -1e9] }; box.set(r, b); }
      for (let q = 0; q < 3; q++) { const v = W[ia[t + q]]; for (let k = 0; k < 3; k++) { b.mn[k] = Math.min(b.mn[k], v[k]); b.mx[k] = Math.max(b.mx[k], v[k]); } }
    }
    const tris = [];
    for (const t of near) {
      const b = box.get(find(vid[ia[t]]));
      if (inBox(b.mn, b.mx)) tris.push(ia[t], ia[t + 1], ia[t + 2]);
    }
    if (tris.length) picked.push({ part, prim: p, M, W, tris });
  }
}
if (!picked.length) throw new Error('盒子里没挑到平显的连通块：BOX 不对？');

// 组合玻璃的包围盒中心：新原点
let gmn = [1e9, 1e9, 1e9], gmx = [-1e9, -1e9, -1e9];
for (const it of picked) if (it.part === 'Glass') for (const i of it.tris) { const v = it.W[i]; for (let k = 0; k < 3; k++) { gmn[k] = Math.min(gmn[k], v[k]); gmx[k] = Math.max(gmx[k], v[k]); } }
if (gmn[0] > 1e8) throw new Error('没挑到组合玻璃');
const ctr = gmn.map((v, k) => (v + gmx[k]) / 2);
const toH = (w) => [-(w[0] - ctr[0]) * S, (w[1] - ctr[1]) * S, -(w[2] - ctr[2]) * S];
const toHn = (d) => { const v = [-d[0], d[1], -d[2]]; const l = Math.hypot(...v) || 1; return v.map((x) => x / l); };
// 组合玻璃的斜度：玻璃顶点的主方向（最小方差的方向是法线）
function plane(pts) {
  const c = [0, 0, 0];
  for (const p of pts) for (let k = 0; k < 3; k++) c[k] += p[k] / pts.length;
  const C = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  for (const p of pts) for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) C[i][j] += (p[i] - c[i]) * (p[j] - c[j]);
  // 幂迭代求最大的两个方向，法线 = 叉乘
  const mul = (A, v) => [0, 1, 2].map((i) => A[i][0] * v[0] + A[i][1] * v[1] + A[i][2] * v[2]);
  const norm = (v) => { const l = Math.hypot(...v) || 1; return v.map((x) => x / l); };
  let a = [1, 0.3, 0.2];
  for (let i = 0; i < 60; i++) a = norm(mul(C, a));
  const la = a.reduce((s, x, i) => s + x * mul(C, a)[i], 0);
  const C2 = C.map((r, i) => r.map((x, j) => x - la * a[i] * a[j]));
  let b = [0.2, 1, 0.3];
  for (let i = 0; i < 60; i++) b = norm(mul(C2, b));
  const n = norm([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]);
  return n;
}

// 第二遍：每块一个网格，图元只留挑中的三角形，顶点换到平显坐标
const byPart = new Map();
const glassPts = [];
for (const it of picked) {
  const q = it.prim.clone();
  const pos = q.getAttribute('POSITION');
  const cnt = pos.getCount(), e = [0, 0, 0];
  const np = doc.createAccessor().setType('VEC3').setArray(new Float32Array(cnt * 3)).setBuffer(pos.getBuffer());
  for (let i = 0; i < cnt; i++) np.setElement(i, toH(it.W[i]));
  q.setAttribute('POSITION', np);
  const nor = q.getAttribute('NORMAL');
  if (nor) {
    const nn = doc.createAccessor().setType('VEC3').setArray(new Float32Array(cnt * 3)).setBuffer(nor.getBuffer());
    for (let i = 0; i < cnt; i++) nn.setElement(i, toHn(wdir(it.M, nor.getElement(i, e))));
    q.setAttribute('NORMAL', nn);
  }
  const tan = q.getAttribute('TANGENT');
  if (tan) {
    const nt = doc.createAccessor().setType('VEC4').setArray(new Float32Array(cnt * 4)).setBuffer(tan.getBuffer());
    const e4 = [0, 0, 0, 0];
    for (let i = 0; i < cnt; i++) { const t = tan.getElement(i, e4); const v = toHn(wdir(it.M, [t[0], t[1], t[2]])); nt.setElement(i, [v[0], v[1], v[2], t[3]]); }
    q.setAttribute('TANGENT', nt);
  }
  q.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(it.tris)).setBuffer(q.getIndices().getBuffer()));
  if (it.part === 'Glass') for (const i of it.tris) glassPts.push(toH(it.W[i]).map((v) => v / S));
  if (!byPart.has(it.part)) byPart.set(it.part, []);
  byPart.get(it.part).push(q);
}
for (const sc of root.listScenes()) for (const c of sc.listChildren()) sc.removeChild(c);
for (const a of root.listAnimations()) a.dispose();
const metaParts = {};
const r4 = (x) => Math.round(x * 10000) / 10000;
for (const [part, prims] of byPart) {
  const mesh = doc.createMesh(`O_${KEY}__${part}`);
  const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9], e = [0, 0, 0];
  let tri = 0;
  for (const p of prims) {
    mesh.addPrimitive(p);
    const pos = p.getAttribute('POSITION');
    const ia = p.getIndices().getArray();
    tri += ia.length / 3;
    for (const i of ia) { pos.getElement(i, e); for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], e[k]); mx[k] = Math.max(mx[k], e[k]); } }
  }
  scene.addChild(doc.createNode(`O_${KEY}__${part}`).setMesh(mesh));
  metaParts[part] = { c: mn.map((v, k) => r4((v + mx[k]) / 2 / S)), s: mn.map((v, k) => r4((mx[k] - v) / S)), tri };
}
await doc.transform(prune(), dedup(), textureCompress({ encoder: sharp, resize: [1024, 1024] }));
fs.mkdirSync(path.dirname(OUT), { recursive: true });
await io.write(OUT, doc);

const n = plane(glassPts);
if (n[2] < 0) for (let k = 0; k < 3; k++) n[k] = -n[k];   // 法线朝飞行员（+Z）
const tilt = Math.round(Math.atan2(-n[1], n[2]) * 180 / Math.PI * 10) / 10;   // 组合玻璃往后仰几度（法线往下偏）
const lua = (v) => '{ ' + v.join(', ') + ' }';
let out = '-- 自动生成（tools/weapons/hud.mjs），别手改：飞机座舱平显（光学瞄准屏）原模型的元数据\n';
out += '--   原模型：J-15T with YJ-83K（作者 Jeyhun1985，CC-BY-4.0）自带座舱里的平显——两根弧形立柱 + 顶梁、投影仪壳子（Frame），组合玻璃（Glass）\n';
out += '--   平显坐标（米）：原点在组合玻璃的包围盒中心，+X 飞行员看来的右边，+Y 上，+Z 朝飞行员；parts[块名] = { c 中心, s 大小, tri 三角形数 }\n';
out += '--   导入后 MeshPart 叫 O_' + KEY + '__<块名>，开服时 Imports.lua 收进 ReplicatedStorage.Imported.Optics.' + KEY + '；InteriorDefs 的平显有它就换上\n';
out += 'return {\n  ' + KEY + ' = {\n    parts = {\n';
for (const part of ['Frame', 'Glass']) {
  const m = metaParts[part];
  if (m) out += `      ${part} = { c = ${lua(m.c)}, s = ${lua(m.s)}, tri = ${m.tri} },\n`;
}
const g = metaParts.Glass;
out += `    },\n    glass = { w = ${g.s[0]}, h = ${g.s[1]}, d = ${g.s[2]}, tilt = ${tilt} },   -- 组合玻璃（米）：包围盒、往飞行员那边仰几度\n`;
out += `    credit = "平显（光学瞄准屏）：J-15T with YJ-83K 自带座舱里的平显，作者 Jeyhun1985（https://sketchfab.com/3d-models/${UID}），CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）",\n`;
out += '  },\n}\n';
fs.writeFileSync(META, out);
console.log('写好了', path.relative(ROOT, OUT), (fs.statSync(OUT).size / 1048576).toFixed(2) + ' MB，组合玻璃仰', tilt, '°');
for (const [p, m] of Object.entries(metaParts)) console.log(' ', p, '三角形', m.tri, '中心', m.c.join(', '), '大小', m.s.join(', '));
