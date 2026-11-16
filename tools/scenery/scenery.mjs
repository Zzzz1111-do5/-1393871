// 花草树木模型包（地图上的树林、灌木、石头、草丛、花丛）：Sketchfab 上的 CC-BY 模型挑出来转成一个 GLB，Studio 里「导入 3D」一次就全有了
//   用户：地图做成 Arma 那种样子（土路、草地花丛、成片树林），缺的模型去 Sketchfab 找
//   用法（仓库根目录；先 cd tools/weapons && npm ci，这里的 node_modules 链到那边）：node tools/scenery/scenery.mjs [原模型缓存目录] [预览图目录]
//     缓存目录默认 tools/scenery/cache（<源>.glb）；没有的从 Sketchfab 下载——密钥只从环境变量 SKETCHFAB_TOKEN 读，代码、仓库里都不放
//   每件（scenery.json 的 items）：nodes 指的节点（含下面所有网格）按世界矩阵烘进顶点 → 1 米 = 2.8 格再乘 s → 原点放在树干底部中心（x、z 取树干
//     包围盒中心，没有树干取整体；y 取最低）→ 同一种材质并成一块：树干叫 Bark、树叶 / 草 / 花叫 Leaves（第二种叫 Leaves2…）、其余 Body；
//     树干三角形太多的用 meshoptimizer 减面（barkTris）；树叶、草这类贴图带透明的面片做成双面（多一份反过来的三角形，Roblox 的网格默认只画正面）
//     patch：几种草 / 花随机撒成一片（半径 r 米、n 株、随机转角、大小差一成五），一片一个模型
//   输出：
//     models/scenery/scenery.glb：Studio「导入 3D」导入这一个文件（块叫 N_<键>__<块名>；开服时 Imports.lua 收进 ReplicatedStorage.Imported.Scenery.<键>）
//     src/ReplicatedStorage/SceneryMeta.lua：每件的种类、高、树冠半径、每块在这件里的中心和大小、在 GLB 里摆在哪（导入后按它找回原点）
//     models/scenery/credits.txt：署名（CC-BY 要求写作者、原名、链接、改了什么）
//     预览图（侧视，按块上色）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const CFG = JSON.parse(fs.readFileSync(path.join(HERE, 'scenery.json'), 'utf8'));
const CACHE = process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache');
const PREV = process.argv[3] ? path.resolve(process.argv[3]) : path.join(HERE, 'preview');
const M2S = 2.8;   // 1 米多少格
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;

// 可重复的随机数（每次转出来一样）
function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

async function sourceDoc(key) {
  const f = path.join(CACHE, key + '.glb');
  if (!fs.existsSync(f)) {
    const S = CFG.sources[key];
    const tok = process.env.SKETCHFAB_TOKEN;
    if (!tok) throw new Error(`缓存里没有 ${key}（${S.name}）：设好环境变量 SKETCHFAB_TOKEN 再运行，或者把下载的 GLB 放到 ${f}`);
    const r = await fetch(`https://api.sketchfab.com/v3/models/${S.uid}/download`, { headers: { Authorization: 'Token ' + tok } });
    if (!r.ok) throw new Error(`下载 ${key} 失败：HTTP ${r.status}`);
    const j = await r.json();
    fs.mkdirSync(CACHE, { recursive: true });
    fs.writeFileSync(f, Buffer.from(await (await fetch(j.glb.url)).arrayBuffer()));
  }
  return io.read(f);
}

// ---------------------------------------------------------------- 取网格（烘进世界矩阵）

// 一个材质的「角色」：树干、树叶（含草、花、公告板）、其余
function roleOf(name) {
  if (/bark/i.test(name)) return 'Bark';
  if (/branch|brunch|leaf|grass|billboard|dandelion|lactuc|plantain|atlas|needle|foliage/i.test(name)) return 'Leaves';
  return 'Body';
}
// 节点下所有带网格的节点（包括它自己）
function meshNodesUnder(node, out = []) {
  if (node.getMesh()) out.push(node);
  for (const c of node.listChildren()) meshNodesUnder(c, out);
  return out;
}
function findNode(doc, name) {
  let hit = null;
  for (const sc of doc.getRoot().listScenes()) sc.traverse((n) => { if (!hit && n.getName() === name) hit = n; });
  if (!hit) throw new Error('找不到节点 ' + name);
  return hit;
}
// 取一个节点（及下面）的三角形：每个图元 → { mat, pos[], nor[], uv[], idx[] }（位置是世界坐标，单位米）
function grab(node) {
  const out = [];
  for (const n of meshNodesUnder(node)) {
    const M = n.getWorldMatrix();
    for (const p of n.getMesh().listPrimitives()) {
      const P = p.getAttribute('POSITION'), N = p.getAttribute('NORMAL'), T = p.getAttribute('TEXCOORD_0');
      const cnt = P.getCount();
      const pos = new Float32Array(cnt * 3), nor = new Float32Array(cnt * 3), uv = new Float32Array(cnt * 2);
      const e = [0, 0, 0], e2 = [0, 0];
      for (let i = 0; i < cnt; i++) {
        P.getElement(i, e);
        pos[i * 3] = M[0] * e[0] + M[4] * e[1] + M[8] * e[2] + M[12];
        pos[i * 3 + 1] = M[1] * e[0] + M[5] * e[1] + M[9] * e[2] + M[13];
        pos[i * 3 + 2] = M[2] * e[0] + M[6] * e[1] + M[10] * e[2] + M[14];
        if (N) {
          N.getElement(i, e);
          let x = M[0] * e[0] + M[4] * e[1] + M[8] * e[2], y = M[1] * e[0] + M[5] * e[1] + M[9] * e[2], z = M[2] * e[0] + M[6] * e[1] + M[10] * e[2];
          const l = Math.hypot(x, y, z) || 1;
          nor[i * 3] = x / l; nor[i * 3 + 1] = y / l; nor[i * 3 + 2] = z / l;
        } else { nor[i * 3 + 1] = 1; }
        if (T) { T.getElement(i, e2); uv[i * 2] = e2[0]; uv[i * 2 + 1] = e2[1]; }
      }
      const I = p.getIndices();
      const idx = I ? Uint32Array.from(I.getArray()) : Uint32Array.from({ length: cnt }, (_, i) => i);
      // 世界矩阵是镜像的（行列式 < 0）：三角形绕向反过来
      const det = M[0] * (M[5] * M[10] - M[6] * M[9]) - M[4] * (M[1] * M[10] - M[2] * M[9]) + M[8] * (M[1] * M[6] - M[2] * M[5]);
      if (det < 0) for (let t = 0; t < idx.length; t += 3) { const a = idx[t + 1]; idx[t + 1] = idx[t + 2]; idx[t + 2] = a; }
      out.push({ mat: p.getMaterial(), pos, nor, uv, idx });
    }
  }
  return out;
}
// 一组图元：包围盒（可只算某种角色的）
function bounds(prims, role) {
  const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
  for (const g of prims) {
    if (role && roleOf(g.mat ? g.mat.getName() : '') !== role) continue;
    for (let i = 0; i < g.pos.length; i += 3) for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], g.pos[i + k]); mx[k] = Math.max(mx[k], g.pos[i + k]); }
  }
  return mn[0] > mx[0] ? null : { mn, mx };
}
// 平移、缩放、绕 Y 转（米 → 格）：p' = R(yaw)·(p − o)·s + t
function place(prims, o, s, yaw, t) {
  const c = Math.cos(yaw), sn = Math.sin(yaw);
  for (const g of prims) {
    for (let i = 0; i < g.pos.length; i += 3) {
      const x = (g.pos[i] - o[0]) * s, y = (g.pos[i + 1] - o[1]) * s, z = (g.pos[i + 2] - o[2]) * s;
      g.pos[i] = c * x + sn * z + t[0]; g.pos[i + 1] = y + t[1]; g.pos[i + 2] = -sn * x + c * z + t[2];
      const nx = g.nor[i], nz = g.nor[i + 2];
      g.nor[i] = c * nx + sn * nz; g.nor[i + 2] = -sn * nx + c * nz;
    }
  }
}

// ---------------------------------------------------------------- 并块、减面、双面

function merge(list) {
  let nv = 0, ni = 0;
  for (const g of list) { nv += g.pos.length / 3; ni += g.idx.length; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2), idx = new Uint32Array(ni);
  let ov = 0, oi = 0;
  for (const g of list) {
    pos.set(g.pos, ov * 3); nor.set(g.nor, ov * 3); uv.set(g.uv, ov * 2);
    for (let i = 0; i < g.idx.length; i++) idx[oi + i] = g.idx[i] + ov;
    ov += g.pos.length / 3; oi += g.idx.length;
  }
  return { pos, nor, uv, idx };
}
function simplify(g, maxTris) {
  if (g.idx.length / 3 <= maxTris) return g;
  const target = Math.floor(maxTris) * 3;
  const [out] = MeshoptSimplifier.simplify(g.idx, g.pos, 3, target, 0.05, ['LockBorder']);
  let res = out;
  if (res.length / 3 > maxTris * 1.3) res = MeshoptSimplifier.simplify(g.idx, g.pos, 3, target, 0.3, [])[0];   // 锁着边界减不下去：放开边界、误差放宽
  return { pos: g.pos, nor: g.nor, uv: g.uv, idx: Uint32Array.from(res) };
}
function doubleSide(g) {
  const nv = g.pos.length / 3;
  const pos = new Float32Array(nv * 6), nor = new Float32Array(nv * 6), uv = new Float32Array(nv * 4);
  pos.set(g.pos); pos.set(g.pos, nv * 3); uv.set(g.uv); uv.set(g.uv, nv * 2);
  nor.set(g.nor);
  for (let i = 0; i < nv * 3; i++) nor[nv * 3 + i] = -g.nor[i];
  const idx = new Uint32Array(g.idx.length * 2);
  idx.set(g.idx);
  for (let t = 0; t < g.idx.length; t += 3) { idx[g.idx.length + t] = g.idx[t] + nv; idx[g.idx.length + t + 1] = g.idx[t + 2] + nv; idx[g.idx.length + t + 2] = g.idx[t + 1] + nv; }
  return { pos, nor, uv, idx };
}

// ---------------------------------------------------------------- 贴图

const texCache = new Map();
async function texOf(srcTex, maxDim, keepAlpha) {
  if (!srcTex) return null;
  const k = srcTex.getURI() + '|' + srcTex.getName() + '|' + maxDim + '|' + keepAlpha + '|' + srcTex.getImage().byteLength;
  if (texCache.has(k)) return texCache.get(k);
  let img = sharp(Buffer.from(srcTex.getImage())).resize(maxDim, maxDim, { fit: 'inside', withoutEnlargement: true });
  const buf = keepAlpha ? await img.png({ compressionLevel: 9, palette: false }).toBuffer() : await img.jpeg({ quality: 82 }).toBuffer();
  const r = { buf, mime: keepAlpha ? 'image/png' : 'image/jpeg' };
  texCache.set(k, r);
  return r;
}
// 原材质的底色贴图（含 KHR_materials_pbrSpecularGlossiness 的 diffuse）、法线贴图
function baseTexOf(mat) {
  if (!mat) return null;
  const t = mat.getBaseColorTexture();
  if (t) return t;
  const sg = mat.getExtension('KHR_materials_pbrSpecularGlossiness');
  return sg ? sg.getDiffuseTexture() : null;
}

// ---------------------------------------------------------------- 一件

async function buildItem(I, docs) {
  let prims = [];
  const R = rng(I.key.split('').reduce((a, c) => a * 31 + c.charCodeAt(0), 7));
  if (I.patch) {   // 一片草 / 花：几种随机撒开
    for (const sub of I.patch) {
      const doc = docs[sub.src];
      // tris：原型先减面（蒲公英的花瓣是真几何体，一株上千个三角形）
      const protos = sub.nodes.map((nm) => grab(findNode(doc, nm)).map((g) => (sub.tris ? Object.assign(simplify(g, sub.tris), { mat: g.mat }) : g)));
      for (let k = 0; k < sub.n; k++) {
        const proto = protos[Math.floor(R() * protos.length)];
        const copy = proto.map((g) => ({ mat: g.mat, pos: Float32Array.from(g.pos), nor: Float32Array.from(g.nor), uv: g.uv, idx: g.idx }));
        const b = bounds(copy);
        const a = R() * Math.PI * 2, rr = Math.sqrt(R()) * sub.r * M2S;
        const sc = M2S * sub.s * (0.85 + R() * 0.3);
        place(copy, [(b.mn[0] + b.mx[0]) / 2, b.mn[1], (b.mn[2] + b.mx[2]) / 2], sc, R() * Math.PI * 2, [Math.cos(a) * rr, 0, Math.sin(a) * rr]);
        prims.push(...copy);
      }
    }
  } else {
    const doc = docs[I.src];
    for (const nm of I.nodes) prims.push(...grab(findNode(doc, nm)));
    const bt = bounds(prims, 'Bark') || bounds(prims);
    const ball = bounds(prims);
    place(prims, [(bt.mn[0] + bt.mx[0]) / 2, ball.mn[1], (bt.mn[2] + bt.mx[2]) / 2], M2S * (I.s || 1), 0, [0, 0, 0]);
  }
  // 按材质并块
  const byMat = new Map();
  for (const g of prims) {
    if (!byMat.has(g.mat)) byMat.set(g.mat, []);
    byMat.get(g.mat).push(g);
  }
  const parts = [];
  const roleN = {};
  for (const [mat, list] of byMat) {
    const role = roleOf(mat ? mat.getName() : '');
    roleN[role] = (roleN[role] || 0) + 1;
    const name = roleN[role] === 1 ? role : role + roleN[role];
    let g = merge(list);
    if (role === 'Bark' || role === 'Body') g = simplify(g, (role === 'Bark') ? (I.barkTris || 2500) : (I.barkTris || 4000));
    if (role === 'Leaves') g = doubleSide(g);
    parts.push({ name, role, mat, g });
  }
  return parts;
}

// ---------------------------------------------------------------- 主程序

const docs = {};
for (const k of Object.keys(CFG.sources)) docs[k] = await sourceDoc(k);
const out = new Document();
const buffer = out.createBuffer();
const scene = out.createScene('Scenery');
const outMats = new Map();
async function matFor(srcMat, role) {
  const key = srcMat;
  if (outMats.has(key)) return outMats.get(key);
  const leaf = role === 'Leaves';
  const m = out.createMaterial((srcMat ? srcMat.getName() : 'Mat').replace(/[^\w]+/g, '_'));
  m.setMetallicFactor(0).setRoughnessFactor(leaf ? 0.85 : 0.95).setDoubleSided(false);
  const bt = baseTexOf(srcMat);
  if (bt) {
    const t = await texOf(bt, leaf ? 512 : 256, leaf);
    const tex = out.createTexture(m.getName() + '_c').setImage(t.buf).setMimeType(t.mime);
    m.setBaseColorTexture(tex);
  } else if (srcMat) {
    const sg = srcMat.getExtension('KHR_materials_pbrSpecularGlossiness');
    m.setBaseColorFactor(sg ? sg.getDiffuseFactor() : srcMat.getBaseColorFactor());
  }
  if (leaf) m.setAlphaMode('MASK').setAlphaCutoff(0.45);
  const nt = srcMat && srcMat.getNormalTexture();
  if (nt && !leaf) {
    const t = await texOf(nt, 256, false);
    m.setNormalTexture(out.createTexture(m.getName() + '_n').setImage(t.buf).setMimeType(t.mime));
  }
  outMats.set(key, m);
  return m;
}
const meta = [];
const preview = [];
let col = 0, rowX = 0, rowZ = 0, rowDepth = 0;
for (const I of CFG.items) {
  const parts = await buildItem(I, docs);
  // 在 GLB 里摆成一排一排（Studio 里导入后不叠在一起）；元数据记下每件的原点
  const bb = { mn: [1e9, 1e9, 1e9], mx: [-1e9, -1e9, -1e9] };
  for (const P of parts) for (let i = 0; i < P.g.pos.length; i += 3) for (let k = 0; k < 3; k++) { bb.mn[k] = Math.min(bb.mn[k], P.g.pos[i + k]); bb.mx[k] = Math.max(bb.mx[k], P.g.pos[i + k]); }
  const w = bb.mx[0] - bb.mn[0], d = bb.mx[2] - bb.mn[2];
  if (col >= 8) { col = 0; rowX = 0; rowZ += rowDepth + 20; rowDepth = 0; }
  const origin = [rowX - bb.mn[0], 0, rowZ - bb.mn[2]];
  rowX += w + 20; rowDepth = Math.max(rowDepth, d); col++;
  const partMeta = [];
  let tris = 0;
  for (const P of parts) {
    const g = P.g;
    const mat = await matFor(P.mat, P.role);
    const prim = out.createPrimitive()
      .setAttribute('POSITION', out.createAccessor().setType('VEC3').setArray(g.pos).setBuffer(buffer))
      .setAttribute('NORMAL', out.createAccessor().setType('VEC3').setArray(g.nor).setBuffer(buffer))
      .setAttribute('TEXCOORD_0', out.createAccessor().setType('VEC2').setArray(g.uv).setBuffer(buffer))
      .setIndices(out.createAccessor().setType('SCALAR').setArray(g.idx).setBuffer(buffer))
      .setMaterial(mat);
    const nm = `N_${I.key}__${P.name}`;
    const mesh = out.createMesh(nm).addPrimitive(prim);
    scene.addChild(out.createNode(nm).setMesh(mesh).setTranslation(origin));
    const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    for (let i = 0; i < g.pos.length; i += 3) for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], g.pos[i + k]); mx[k] = Math.max(mx[k], g.pos[i + k]); }
    partMeta.push({ name: P.name, c: mn.map((v, k) => (v + mx[k]) / 2), s: mn.map((v, k) => mx[k] - v), tris: g.idx.length / 3 });
    tris += g.idx.length / 3;
    if (g.idx.length / 3 > 19500) throw new Error(`${nm} 有 ${g.idx.length / 3} 个三角形，超过 Roblox 一块 2 万的上限`);
    preview.push({ key: I.key, role: P.role, g });
  }
  const r = Math.max(bb.mx[0], -bb.mn[0], bb.mx[2], -bb.mn[2]);
  meta.push({ key: I.key, kind: I.kind, h: bb.mx[1], r, origin, parts: partMeta, tris });
  console.log(`${I.key.padEnd(8)} ${I.kind.padEnd(8)} 高 ${bb.mx[1].toFixed(1).padStart(5)} 格  冠幅半径 ${r.toFixed(1).padStart(5)}  △${tris}  块 ${parts.map((p) => p.name + '·' + p.g.idx.length / 3).join(' ')}`);
}
fs.mkdirSync(path.join(ROOT, 'models/scenery'), { recursive: true });
await io.write(path.join(ROOT, 'models/scenery/scenery.glb'), out);
console.log('写好了 models/scenery/scenery.glb', Math.round(fs.statSync(path.join(ROOT, 'models/scenery/scenery.glb')).size / 1024), 'KB');

// 元数据
const r3 = (x) => Math.round(x * 100) / 100;
const lines = [
  '-- 花草树木模型包的元数据（tools/scenery/scenery.mjs 生成，别手改）：models/scenery/scenery.glb 里每一件',
  '--   kind 种类（conifer 针叶树、young 小针叶树、broad 阔叶树、bush 灌木、dead 枯树、log 倒木、rock 石头、outcrop 岩石、grass 草丛、flower 花丛、lod 远景版本）、',
  '--   h 高、r 冠幅半径（格）、o 在 GLB 里的原点（导入后各块按它找回相对位置）、parts 每块的中心 c 和大小 s（相对这件的原点：树干底部中心）、tris 三角形数',
  'return {',
];
for (const m of meta) {
  const ps = m.parts.map((p) => `{ name = "${p.name}", c = { ${p.c.map(r3).join(', ')} }, s = { ${p.s.map(r3).join(', ')} } }`).join(', ');
  lines.push(`  ${m.key} = { kind = "${m.kind}", h = ${r3(m.h)}, r = ${r3(m.r)}, o = { ${m.origin.map(r3).join(', ')} }, tris = ${m.tris}, parts = { ${ps} } },`);
}
lines.push('}');
fs.writeFileSync(path.join(ROOT, 'src/ReplicatedStorage/SceneryMeta.lua'), lines.join('\n') + '\n');
console.log('写好了 src/ReplicatedStorage/SceneryMeta.lua');

// 署名
const used = new Set(CFG.items.flatMap((I) => I.patch ? I.patch.map((p) => p.src) : [I.src]));
const cr = ['花草树木模型包（models/scenery/scenery.glb）用到的模型，都是 Sketchfab 上 CC-BY 4.0（署名）授权：', ''];
for (const k of used) {
  const S = CFG.sources[k];
  cr.push(`- 「${S.name}」，作者 ${S.author}，https://sketchfab.com/3d-models/${S.uid}，CC-BY 4.0`);
}
cr.push('', '改动：挑出其中几棵树 / 灌木 / 石头 / 草 / 花，单位换成 Roblox 的格（1 米 = 2.8 格）并按需要放大，树干减面，贴图缩小（树叶 512、树干 256），',
  '树叶、草、花的面片做成双面；草丛、花丛是把几株随机撒成一片。');
fs.writeFileSync(path.join(ROOT, 'models/scenery/credits.txt'), cr.join('\n') + '\n');

// 预览：每件侧视（x、y），树干棕、树叶绿、其余灰
fs.mkdirSync(PREV, { recursive: true });
const cells = [...new Set(preview.map((p) => p.key))];
const CW = 220, CH = 260, cols = 8;
const svg = [`<svg xmlns="http://www.w3.org/2000/svg" width="${CW * cols}" height="${CH * Math.ceil(cells.length / cols)}"><rect width="100%" height="100%" fill="#ddd"/>`];
cells.forEach((key, i) => {
  const items = preview.filter((p) => p.key === key);
  const m = meta.find((x) => x.key === key);
  const sc = Math.min((CW - 20) / (2 * m.r + 1), (CH - 40) / (m.h + 1));
  const ox = (i % cols) * CW + CW / 2, oy = Math.floor(i / cols) * CH + CH - 20;
  for (const it of items) {
    const g = it.g, fill = it.role === 'Bark' ? '#6b4a2a' : it.role === 'Leaves' ? '#2f6b2a' : '#888';
    const step = Math.max(3, Math.floor(g.idx.length / 3 / 4000) * 3);
    for (let t = 0; t < g.idx.length; t += step) {
      const pts = [0, 1, 2].map((q) => { const v = g.idx[t + q] * 3; return `${(ox + g.pos[v] * sc).toFixed(1)},${(oy - g.pos[v + 1] * sc).toFixed(1)}`; });
      svg.push(`<polygon points="${pts.join(' ')}" fill="${fill}" fill-opacity="0.35"/>`);
    }
  }
  svg.push(`<text x="${ox - CW / 2 + 6}" y="${oy - CH + 34}" font-size="14" font-family="sans-serif">${key} ${m.h.toFixed(0)}格 △${m.tris}</text>`);
});
svg.push('</svg>');
await sharp(Buffer.from(svg.join(''))).png().toFile(path.join(PREV, 'scenery.png'));
console.log('预览图', path.join(PREV, 'scenery.png'));
