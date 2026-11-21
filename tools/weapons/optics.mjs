// 瞄准镜、望远镜的模型（Sketchfab 上的 CC-BY 模型）原样搬进 Roblox：几何、材质、贴图都不改，只换单位（米 → 格）、摆正方向、挪原点
//   用户：从 Sketchfab 找瞄准镜的模型，原封不动拷贝下来，再给狙击镜做分划和倍率
//   用法（仓库根目录；先在 tools/weapons 里 npm ci）：node tools/weapons/optics.mjs [原模型缓存目录] [预览图目录]
//     缓存目录默认 tools/weapons/cache（<键>/model.glb）；没有的从 Sketchfab 下载——密钥只从环境变量 SKETCHFAB_TOKEN 读，代码、仓库里都不放
//   每件（optics.json 的 items）：带网格的节点（keep / drop 按遍历序号挑）按世界矩阵烘进顶点 → rot（度，先转，模型斜着摆的）→ axes / scale 转到
//     「器材坐标」（格，+Z 朝前（物镜、枪口）、+Y 朝上）→ 按 anchor 挪原点 → 同一种材质的图元并成一块（块名照 parts 表；没写的：有贴图的叫 Body / Body2…，
//     没贴图的按颜色并成 C<颜色>）；pts 里写的点（握把 grip、导轨 rail、目镜 eyePt…，器材坐标）原样写进元数据
//   输出：
//     models/optics/<键>.glb：给 Studio「导入 3D」（块叫 O_<键>__<块名>，原来的贴图原样带着；开服时 Imports.lua 收进 ReplicatedStorage.Imported.Optics.<键>）
//     src/ReplicatedStorage/OpticsMeta.lua：每块在器材坐标里的中心、大小，目镜 / 物镜的中心和半径，署名
//     src/ReplicatedStorage/OpticMesh/<键>.lua：没导入时客户端用 EditableMesh / EditableImage 现生成的同一套网格（底色贴图缩小、调色板压缩，别的贴图不带）
//     models/credits.txt 里「瞄准镜、望远镜」一节；预览图（侧视、从目镜往前看）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { join, prune, compactPrimitive } from '@gltf-transform/functions';
import sharp from 'sharp';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const CFG = JSON.parse(fs.readFileSync(path.join(HERE, 'optics.json'), 'utf8'));
const CACHE = process.argv[2] ? path.resolve(process.argv[2]) : path.join(HERE, 'cache');
const PREV = process.argv[3] ? path.resolve(process.argv[3]) : path.join(HERE, 'preview');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
fs.mkdirSync(PREV, { recursive: true });
fs.mkdirSync(path.join(ROOT, 'models/optics'), { recursive: true });
fs.mkdirSync(path.join(ROOT, 'src/ReplicatedStorage/OpticMesh'), { recursive: true });

const l2s = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
const r3 = (x) => Math.round(x * 1000) / 1000;

async function sourceFile(key) {
  const S = CFG.sources[key];
  const f = path.join(CACHE, key, 'model.glb');
  if (fs.existsSync(f)) return f;
  const tok = process.env.SKETCHFAB_TOKEN;
  if (!tok) throw new Error(`缓存里没有 ${key}（${S.name}）：设好环境变量 SKETCHFAB_TOKEN 再运行，或者把下载的 model.glb 放进 ${path.dirname(f)}`);
  const r = await fetch(`https://api.sketchfab.com/v3/models/${S.uid}/download`, { headers: { Authorization: 'Token ' + tok } });
  if (!r.ok) throw new Error(`下载 ${key} 失败：HTTP ${r.status}`);
  const j = await r.json();
  const b = Buffer.from(await (await fetch(j.glb.url)).arrayBuffer());
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, b);
  return f;
}

function axesMat(axes, scale, rot) {
  const P = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  axes.split(',').forEach((a, row) => { P[row]['xyz'.indexOf(a[a.length - 1])] = a[0] === '-' ? -1 : 1; });
  const det = P[0][0] * (P[1][1] * P[2][2] - P[1][2] * P[2][1]) - P[0][1] * (P[1][0] * P[2][2] - P[1][2] * P[2][0]) + P[0][2] * (P[1][0] * P[2][1] - P[1][1] * P[2][0]);
  if (det < 0) throw new Error(`axes ${axes} 是镜像的`);
  // rot：按顺序绕轴转（度），[["y", -32.9], ["x", 15.6]] 是先绕 y 再绕 x；然后换轴
  const mm = (A, B) => A.map((r) => [0, 1, 2].map((c) => r[0] * B[0][c] + r[1] * B[1][c] + r[2] * B[2][c]));
  let M = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  for (const [axis, deg] of rot || []) {
    const t = deg * Math.PI / 180, c = Math.cos(t), sn = Math.sin(t);
    const Rk = axis === 'x' ? [[1, 0, 0], [0, c, -sn], [0, sn, c]] : axis === 'y' ? [[c, 0, sn], [0, 1, 0], [-sn, 0, c]] : [[c, -sn, 0], [sn, c, 0], [0, 0, 1]];
    M = mm(Rk, M);
  }
  return { R: mm(P, M), s: scale };
}

// ---------------------------------------------------------------- 一件：烘变换、按材质并块、挪原点

async function buildItem(key, I) {
  const doc = await io.read(await sourceFile(I.src));
  const root = doc.getRoot();
  const scene = root.getDefaultScene() || root.listScenes()[0];
  const { R, s } = axesMat(I.axes || 'x,y,z', I.scale || 1, I.rot);
  const nodeBox = {};   // 节点名 → 包围盒（换到器材坐标、还没挪原点）
  const byMat = new Map();
  const meshNodes = [];
  scene.traverse((n) => { if (n.getMesh()) meshNodes.push(n); });
  const texIdx = new Map();
  for (const [k, n] of meshNodes.entries()) {
    if (I.keep ? !I.keep.includes(k) : (I.drop || []).includes(k)) continue;
    const M = n.getWorldMatrix();
    const tp = (v) => {   // 原模型坐标 → 世界 → 器材坐标（没挪原点）
      const w = [M[0] * v[0] + M[4] * v[1] + M[8] * v[2] + M[12], M[1] * v[0] + M[5] * v[1] + M[9] * v[2] + M[13], M[2] * v[0] + M[6] * v[1] + M[10] * v[2] + M[14]];
      return [0, 1, 2].map((r) => (R[r][0] * w[0] + R[r][1] * w[1] + R[r][2] * w[2]) * s);
    };
    // 法线：世界矩阵 3×3 的逆转置（这些模型只有旋转、均匀缩放，直接用旋转部分再归一）
    const tn = (v) => {
      const w = [M[0] * v[0] + M[4] * v[1] + M[8] * v[2], M[1] * v[0] + M[5] * v[1] + M[9] * v[2], M[2] * v[0] + M[6] * v[1] + M[10] * v[2]];
      const o = [0, 1, 2].map((r) => R[r][0] * w[0] + R[r][1] * w[1] + R[r][2] * w[2]);
      const l = Math.hypot(...o) || 1;
      return o.map((x) => x / l);
    };
    const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    for (const p of n.getMesh().listPrimitives()) {
      const q = p.clone();   // 原图元可能被别的节点共用：复制一份再改
      const pos = q.getAttribute('POSITION');
      const np = doc.createAccessor().setType('VEC3').setArray(new Float32Array(pos.getCount() * 3)).setBuffer(pos.getBuffer());
      const e = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) {
        const v = tp(pos.getElement(i, e));
        np.setElement(i, v);
        for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], v[k]); mx[k] = Math.max(mx[k], v[k]); }
      }
      q.setAttribute('POSITION', np);
      const nor = q.getAttribute('NORMAL');
      if (nor) {
        const nn = doc.createAccessor().setType('VEC3').setArray(new Float32Array(nor.getCount() * 3)).setBuffer(nor.getBuffer());
        for (let i = 0; i < nor.getCount(); i++) nn.setElement(i, tn(nor.getElement(i, e)));
        q.setAttribute('NORMAL', nn);
      }
      const tan = q.getAttribute('TANGENT');
      if (tan) {
        const nt = doc.createAccessor().setType('VEC4').setArray(new Float32Array(tan.getCount() * 4)).setBuffer(tan.getBuffer());
        const e4 = [0, 0, 0, 0];
        for (let i = 0; i < tan.getCount(); i++) { const t = tan.getElement(i, e4); const v = tn([t[0], t[1], t[2]]); nt.setElement(i, [v[0], v[1], v[2], t[3]]); }
        q.setAttribute('TANGENT', nt);
      }
      const mat = q.getMaterial();
      let part = I.parts && mat && I.parts[mat.getName()];
      if (!part) {
        if (mat && mat.getBaseColorTexture()) {   // 有贴图：一种材质一块
          if (!texIdx.has(mat)) texIdx.set(mat, texIdx.size + 1);
          part = texIdx.get(mat) === 1 ? 'Body' : 'Body' + texIdx.get(mat);
        } else {   // 没贴图：颜色差不多的并成一块
          const f = mat ? mat.getBaseColorFactor() : [0.6, 0.6, 0.6, 1];
          part = 'C' + [0, 1, 2].map((q2) => Math.min(15, Math.round(l2s(f[q2]) * 15)).toString(16)).join('');
        }
      }
      if (!byMat.has(part)) byMat.set(part, []);
      byMat.get(part).push(q);
    }
    nodeBox[n.getName()] = { mn, mx };
  }
  // 原点：anchor 指的那些节点（名字里带这几个字）的包围盒——x、z 取中心，y 取最低（镜座底面贴在导轨上）；或者两个目镜的中点
  const pick = (re) => Object.entries(nodeBox).filter(([nm]) => new RegExp(re).test(nm)).map(([, b]) => b);
  const unite = (list) => list.reduce((a, b) => ({ mn: a.mn.map((v, k) => Math.min(v, b.mn[k])), mx: a.mx.map((v, k) => Math.max(v, b.mx[k])) }));
  let off = [0, 0, 0];
  if (I.anchor) {
    const b = unite(pick(I.anchor.nodes));
    // y：默认取最低（镜座底面贴导轨）；center 取中心（枪口装置的轴线）；max 取最高（握把、弹匣：顶面贴着导轨 / 弹匣井）
    off = [-(b.mn[0] + b.mx[0]) / 2, -(I.anchor.y === 'center' ? (b.mn[1] + b.mx[1]) / 2 : I.anchor.y === 'max' ? b.mx[1] : b.mn[1]), -(I.anchor.z === 'min' ? b.mn[2] : I.anchor.z === 'max' ? b.mx[2] : (b.mn[2] + b.mx[2]) / 2)];
  }
  if (I.offAdj) off = off.map((v, k) => v + I.offAdj[k]);
  // 新文档：每块一个节点（同材质的图元并成一个）
  for (const sc of root.listScenes()) for (const c of sc.listChildren()) sc.removeChild(c);
  const parts = [];
  for (const [part, prims] of byMat) {
    const mesh = doc.createMesh(`O_${key}__${part}`);
    for (const p of prims) {
      const pos = p.getAttribute('POSITION');
      const e = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) { pos.getElement(i, e); pos.setElement(i, [e[0] + off[0], e[1] + off[1], e[2] + off[2]]); }
      mesh.addPrimitive(p);
    }
    const node = doc.createNode(`O_${key}__${part}`).setMesh(mesh);
    scene.addChild(node);
    parts.push({ part, mesh, node });
  }
  await doc.transform(join({ keepNamed: false }), prune());
  // dropBox：去掉中心落在这个盒子里的连通块（器材坐标 [x0, y0, z0, x1, y1, z1]；比如 M40A5 自带的瞄准镜，换装别的镜子）
  if (I.dropBox) {
    const B = I.dropBox;
    let dropped = 0;
    for (const P of parts) for (const prim of P.mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION'), idx = prim.getIndices();
      if (!idx) continue;
      const n = pos.getCount();
      const key3 = new Map(), wid = new Int32Array(n), e = [0, 0, 0], V = [];
      for (let i = 0; i < n; i++) {
        pos.getElement(i, e);
        const k = `${Math.round(e[0] * 1e4)},${Math.round(e[1] * 1e4)},${Math.round(e[2] * 1e4)}`;
        let id = key3.get(k);
        if (id === undefined) { id = key3.size; key3.set(k, id); }
        wid[i] = id; V[i] = e.slice();
      }
      const par = new Int32Array(key3.size).map((_, i) => i);
      const find = (x) => { while (par[x] !== x) { par[x] = par[par[x]]; x = par[x]; } return x; };
      const ia = idx.getArray();
      for (let t = 0; t < ia.length; t += 3) { const a0 = find(wid[ia[t]]); par[find(wid[ia[t + 1]])] = a0; par[find(wid[ia[t + 2]])] = a0; }
      const acc = new Map();
      for (let t = 0; t < ia.length; t += 3) {
        const r = find(wid[ia[t]]);
        let A = acc.get(r);
        if (!A) { A = [0, 0, 0, 0]; acc.set(r, A); }
        for (let q = 0; q < 3; q++) { const v = V[ia[t + q]]; A[0] += v[0]; A[1] += v[1]; A[2] += v[2]; A[3]++; }
      }
      const inBox = (c) => c[0] >= B[0] && c[0] <= B[3] && c[1] >= B[1] && c[1] <= B[4] && c[2] >= B[2] && c[2] <= B[5];
      const keep = [];
      for (let t = 0; t < ia.length; t += 3) {
        const A = acc.get(find(wid[ia[t]]));
        if (inBox([A[0] / A[3], A[1] / A[3], A[2] / A[3]])) { dropped++; continue; }
        keep.push(ia[t], ia[t + 1], ia[t + 2]);
      }
      prim.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(keep)).setBuffer(idx.getBuffer()));
    }
    console.log('   dropBox 去掉三角形', dropped);
  }
  // 一块超过 19500 个三角形：按顺序切成几块（Roblox 导入、EditableMesh 一个网格最多 2 万个三角形），块名 Body、Body_2……
  for (const P of [...parts]) {
    const prim = P.mesh.listPrimitives()[0];
    const idx = prim && prim.getIndices();
    if (!idx || idx.getCount() / 3 <= 19500) continue;
    const all = idx.getArray();
    const nChunk = Math.ceil(all.length / 3 / 19500);
    for (let c = 1; c < nChunk; c++) {
      const q = prim.clone();
      const sub = all.slice(c * 19500 * 3, Math.min(all.length, (c + 1) * 19500 * 3));
      q.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(sub)).setBuffer(idx.getBuffer()));
      const name = `${P.part}_${c + 1}`;
      const mesh = doc.createMesh(`O_${key}__${name}`).addPrimitive(q);
      scene.addChild(doc.createNode(`O_${key}__${name}`).setMesh(mesh));
      parts.push({ part: name, mesh });
    }
    prim.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(all.slice(0, 19500 * 3))).setBuffer(idx.getBuffer()));
  }
  for (const P of parts) for (const prim of P.mesh.listPrimitives()) compactPrimitive(prim);   // 去掉没用到的顶点（切块、dropBox 以后）
  await doc.transform(prune());
  // 每块的包围盒、三角形数
  const meta = { parts: {}, tris: 0 };
  for (const P of parts) {
    const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    let tri = 0;
    for (const p of P.mesh.listPrimitives()) {
      const pos = p.getAttribute('POSITION');
      const e = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) { pos.getElement(i, e); for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], e[k]); mx[k] = Math.max(mx[k], e[k]); } }
      tri += (p.getIndices() ? p.getIndices().getCount() : pos.getCount()) / 3;
    }
    meta.parts[P.part] = { c: [0, 1, 2].map((k) => r3((mn[k] + mx[k]) / 2)), s: [0, 1, 2].map((k) => r3(mx[k] - mn[k])), tri };
    const pm = P.mesh.listPrimitives()[0] && P.mesh.listPrimitives()[0].getMaterial();
    if (pm && !pm.getBaseColorTexture()) {   // 没贴图的块：颜色写进元数据（导入后 Studio 不一定给 MeshPart 上色，游戏里照这个涂）
      const f = pm.getBaseColorFactor();
      meta.parts[P.part].col = [0, 1, 2].map((q) => Math.round(l2s(f[q]) * 255));
      meta.parts[P.part].met = r3(pm.getMetallicFactor());
    }
    meta.tris += tri;
  }
  // 光学：目镜、物镜（节点名带这几个字）的中心和半径（器材坐标）
  const lens = (re) => {
    const list = pick(re);
    if (!list.length) return null;
    const b = unite(list);
    const c = [0, 1, 2].map((k) => r3((b.mn[k] + b.mx[k]) / 2 + off[k]));
    return { c, r: r3(Math.max(b.mx[0] - b.mn[0], b.mx[1] - b.mn[1]) / 2) };
  };
  if (I.eye) meta.eye = lens(I.eye);
  if (I.obj) meta.obj = lens(I.obj);
  if (I.eyes) meta.eyes = I.eyes.map((re) => lens(re));
  if (I.eyePt) meta.eye = { c: I.eyePt, r: I.eyeR || 0.05 };   // 节点分不出镜片的：直接写（器材坐标）
  if (I.objPt) meta.obj = { c: I.objPt, r: I.objR || 0.07 };
  meta.pts = I.pts || null;
  const all = Object.values(meta.parts);
  meta.size = [0, 1, 2].map((k) => r3(Math.max(...all.map((p) => p.c[k] + p.s[k] / 2)) - Math.min(...all.map((p) => p.c[k] - p.s[k] / 2))));
  // 写 glb（贴图原样；超过 1024 的缩到 1024——Roblox 导入时本来就会缩到这么大，原图 4K 只是让文件大几倍）
  for (const tex of root.listTextures()) {
    const img = tex.getImage();
    if (!img) continue;
    const meta2 = await sharp(Buffer.from(img)).metadata();
    const big = Math.max(meta2.width || 0, meta2.height || 0);
    if (big <= (I.texMax || 1024)) continue;
    const k2 = (I.texMax || 1024) / big;
    const w2 = Math.max(1, Math.round(meta2.width * k2)), h2 = Math.max(1, Math.round(meta2.height * k2));
    const png = tex.getMimeType() === 'image/png';
    const out2 = await sharp(Buffer.from(img)).resize(w2, h2)[png ? 'png' : 'jpeg'](png ? {} : { quality: 90 }).toBuffer();
    tex.setImage(new Uint8Array(out2));
  }
  const out = path.join(ROOT, 'models/optics', key + '.glb');
  await io.write(out, doc);
  console.log(key.padEnd(6), '三角形', meta.tris, '块', parts.map((p) => p.part).join('/'), 'glb', fs.statSync(out).size, '字节');
  return { doc, parts, meta };
}

// ---------------------------------------------------------------- 内嵌版：网格量化 + 底色贴图缩小、调色板

const b64 = (buf) => Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength).toString('base64');

async function paletteTex(tex, factor, size) {
  const { data, info } = await sharp(Buffer.from(tex.getImage())).resize(size, size, { fit: 'fill' }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const n = info.width * info.height;
  // 底色乘上去（线性空间）
  const px = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) for (let q = 0; q < 3; q++) {
    const c = data[i * 3 + q] / 255;
    const lin = (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)) * factor[q];
    px[i * 3 + q] = l2s(lin) * 255;
  }
  // k 均值 256 色（亮度排序初始化）
  const K = 256;
  const order = [...Array(n).keys()].sort((a, b) => (px[a * 3] + px[a * 3 + 1] + px[a * 3 + 2]) - (px[b * 3] + px[b * 3 + 1] + px[b * 3 + 2]));
  let cent = [];
  for (let k = 0; k < K; k++) { const i = order[Math.floor((k + 0.5) / K * n)]; cent.push([px[i * 3], px[i * 3 + 1], px[i * 3 + 2]]); }
  const lab = new Uint8Array(n);
  for (let it = 0; it < 8; it++) {
    const acc = cent.map(() => [0, 0, 0, 0]);
    for (let i = 0; i < n; i++) {
      let best = 0, bd = 1e18;
      const r = px[i * 3], g = px[i * 3 + 1], b = px[i * 3 + 2];
      for (let k = 0; k < K; k++) { const c = cent[k]; const d = (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2; if (d < bd) { bd = d; best = k; } }
      lab[i] = best;
      const a = acc[best]; a[0] += r; a[1] += g; a[2] += b; a[3]++;
    }
    cent = cent.map((c, k) => (acc[k][3] ? [acc[k][0] / acc[k][3], acc[k][1] / acc[k][3], acc[k][2] / acc[k][3]] : c));
  }
  const pal = new Uint8Array(K * 3);
  cent.forEach((c, k) => { pal[k * 3] = Math.round(c[0]); pal[k * 3 + 1] = Math.round(c[1]); pal[k * 3 + 2] = Math.round(c[2]); });
  return { w: info.width, h: info.height, pal: b64(pal), px: b64(lab) };
}

async function embed(key, B, I) {
  const lines = [];
  lines.push(`-- 自动生成（tools/weapons/optics.mjs），别手改：${CFG.sources[I.src].name}（${CFG.sources[I.src].author}，${CFG.sources[I.src].license}）的网格和底色贴图`);
  lines.push('--   没在 Studio 导入 models/optics/' + key + '.glb 时，客户端用 EditableMesh / EditableImage 现生成（贴图缩小、调色板压缩；法线、粗糙度贴图不带）');
  lines.push('--   parts[块名] = { n 顶点数, t 三角形数, b 包围盒（顶点按它量化成 16 位）, pos / nrm（每个 8 位）/ uv（16 位，范围 ub）/ idx（16 位）, col 底色, tex = { w, h, pal 调色板, px 每像素的色号 } }');
  lines.push('return {');
  lines.push('  parts = {');
  for (const P of B.parts) {
    const prims = P.mesh.listPrimitives();
    if (!prims.length) continue;
    const p = prims[0];
    const pos = p.getAttribute('POSITION'), nor = p.getAttribute('NORMAL'), uv = p.getAttribute('TEXCOORD_0'), idx = p.getIndices();
    const n = pos.getCount();
    const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    const e = [0, 0, 0];
    for (let i = 0; i < n; i++) { pos.getElement(i, e); for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], e[k]); mx[k] = Math.max(mx[k], e[k]); } }
    const qp = new Uint16Array(n * 3), qn = new Int8Array(n * 3), qu = new Uint16Array(n * 2);
    let umn = [1e9, 1e9], umx = [-1e9, -1e9];
    const t2 = [0, 0];
    if (uv) for (let i = 0; i < n; i++) { uv.getElement(i, t2); for (let k = 0; k < 2; k++) { umn[k] = Math.min(umn[k], t2[k]); umx[k] = Math.max(umx[k], t2[k]); } }
    else { umn = [0, 0]; umx = [1, 1]; }
    for (let i = 0; i < n; i++) {
      pos.getElement(i, e);
      for (let k = 0; k < 3; k++) qp[i * 3 + k] = Math.round((e[k] - mn[k]) / Math.max(1e-9, mx[k] - mn[k]) * 65535);
      if (nor) { nor.getElement(i, e); for (let k = 0; k < 3; k++) qn[i * 3 + k] = Math.round(e[k] * 127); }
      if (uv) { uv.getElement(i, t2); for (let k = 0; k < 2; k++) qu[i * 2 + k] = Math.round((t2[k] - umn[k]) / Math.max(1e-9, umx[k] - umn[k]) * 65535); }
    }
    const cnt = idx ? idx.getCount() : n;
    if (n > 65535) throw new Error(`${key}.${P.part} 顶点超过 65535`);
    const qi = new Uint16Array(cnt);
    for (let i = 0; i < cnt; i++) qi[i] = idx ? idx.getScalar(i) : i;
    const mat = p.getMaterial();
    const fac = mat ? mat.getBaseColorFactor() : [0.6, 0.6, 0.6, 1];
    const tex = mat && mat.getBaseColorTexture();
    const size = (I.embedTex && I.embedTex[P.part]) || 128;
    let texL = 'nil';
    if (tex && uv) {
      const T = await paletteTex(tex, fac, size);
      texL = `{ w = ${T.w}, h = ${T.h}, pal = "${T.pal}", px = "${T.px}" }`;
    }
    const col = [l2s(fac[0]), l2s(fac[1]), l2s(fac[2])].map((x) => Math.round(x * 255));
    lines.push(`    ${P.part} = { n = ${n}, t = ${cnt / 3}, b = { ${mn.map(r3).join(', ')}, ${mx.map(r3).join(', ')} }, ub = { ${umn.map((x) => x.toFixed(5)).join(', ')}, ${umx.map((x) => x.toFixed(5)).join(', ')} },`);
    lines.push(`      col = { ${col.join(', ')} }, met = ${mat ? r3(mat.getMetallicFactor()) : 0},`);
    lines.push(`      pos = "${b64(qp)}",`);
    lines.push(`      nrm = "${b64(qn)}",`);
    lines.push(`      uv = "${b64(qu)}",`);
    lines.push(`      idx = "${b64(qi)}",`);
    lines.push(`      tex = ${texL} },`);
  }
  lines.push('  },');
  lines.push('}');
  const f = path.join(ROOT, 'src/ReplicatedStorage/OpticMesh', key + '.lua');
  fs.writeFileSync(f, lines.join('\n') + '\n');
  console.log('   内嵌', path.relative(ROOT, f), fs.statSync(f).size, '字节');
}

// ---------------------------------------------------------------- 预览（平均色、正交）

async function preview(key, B) {
  const tris = [];
  for (const P of B.parts) for (const p of P.mesh.listPrimitives()) {
    const pos = p.getAttribute('POSITION'), idx = p.getIndices();
    const mat = p.getMaterial();
    const f = mat ? mat.getBaseColorFactor() : [0.6, 0.6, 0.6];
    const c = [l2s(f[0]) * 0.6, l2s(f[1]) * 0.6, l2s(f[2]) * 0.6].map((x) => Math.min(1, x + 0.12));
    const cnt = idx ? idx.getCount() : pos.getCount();
    const e = [0, 0, 0];
    for (let i = 0; i < cnt; i += 3) tris.push([0, 1, 2].map((q) => pos.getElement(idx ? idx.getScalar(i + q) : i + q, e).slice()).concat([c]));
  }
  // 局部放大（校准握把等）：环境变量 ZOOM="键:z0,y0,z1,y1"（侧视，器材坐标），出 <键>_zoom.png，格子 0.02
  const zoom = (process.env.ZOOM || '').split(';').map((z) => z.split(':')).find((z) => z[0] === key);
  for (const view of zoom ? ['side', 'eye', 'zoom'] : ['side', 'eye']) {
    // side / zoom：从 +X 看（横 Z、竖 Y）；eye：从目镜往前看（横 −X、竖 Y，深度 Z）
    const U = (v) => (view === 'eye' ? -v[0] : v[2]), Vv = (v) => v[1], Dd = (v) => (view === 'eye' ? -v[2] : v[0]);
    let mn = [1e9, 1e9], mx = [-1e9, -1e9];
    for (const t of tris) for (let k = 0; k < 3; k++) { mn = [Math.min(mn[0], U(t[k])), Math.min(mn[1], Vv(t[k]))]; mx = [Math.max(mx[0], U(t[k])), Math.max(mx[1], Vv(t[k]))]; }
    const pad = 0.1 * Math.max(mx[0] - mn[0], mx[1] - mn[1]);
    mn = [mn[0] - pad, mn[1] - pad]; mx = [mx[0] + pad, mx[1] + pad];
    if (view === 'zoom') { const b = zoom[1].split(',').map(Number); mn = [b[0], b[1]]; mx = [b[2], b[3]]; }
    const W = 1200, H = Math.max(200, Math.round(W * (mx[1] - mn[1]) / (mx[0] - mn[0])));
    const img = Buffer.alloc(W * H * 3, 222), zb = new Float32Array(W * H).fill(-1e9);
    const sx = (u) => (u - mn[0]) / (mx[0] - mn[0]) * W, sy = (v) => H - (v - mn[1]) / (mx[1] - mn[1]) * H;
    for (const t of tris) {
      const P3 = [t[0], t[1], t[2]];
      const a = P3[1].map((x, k) => x - P3[0][k]), b = P3[2].map((x, k) => x - P3[0][k]);
      const n = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
      const lit = 0.4 + 0.6 * Math.abs((n[0] * 0.4 + n[1] * 0.8 + n[2] * 0.45) / (Math.hypot(...n) || 1) / 1.0);
      const S = P3.map((p) => [sx(U(p)), sy(Vv(p)), Dd(p)]);
      const x0 = Math.max(0, Math.floor(Math.min(S[0][0], S[1][0], S[2][0]))), x1 = Math.min(W - 1, Math.ceil(Math.max(S[0][0], S[1][0], S[2][0])));
      const y0 = Math.max(0, Math.floor(Math.min(S[0][1], S[1][1], S[2][1]))), y1 = Math.min(H - 1, Math.ceil(Math.max(S[0][1], S[1][1], S[2][1])));
      const den = (S[1][1] - S[2][1]) * (S[0][0] - S[2][0]) + (S[2][0] - S[1][0]) * (S[0][1] - S[2][1]);
      if (Math.abs(den) < 1e-9) continue;
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
        const w0 = ((S[1][1] - S[2][1]) * (x + 0.5 - S[2][0]) + (S[2][0] - S[1][0]) * (y + 0.5 - S[2][1])) / den;
        const w1 = ((S[2][1] - S[0][1]) * (x + 0.5 - S[2][0]) + (S[0][0] - S[2][0]) * (y + 0.5 - S[2][1])) / den;
        const w2 = 1 - w0 - w1;
        if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        const z = w0 * S[0][2] + w1 * S[1][2] + w2 * S[2][2], i = y * W + x;
        if (z <= zb[i]) continue;
        zb[i] = z;
        for (let q = 0; q < 3; q++) img[i * 3 + q] = Math.min(255, t[3][q] * 255 * lit + 20);
      }
    }
    let svg = `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg" font-family="monospace" font-size="13">`;
    const step = view === 'zoom' ? 0.02 : (mx[0] - mn[0]) > 2 ? 0.1 : 0.05;
    for (let u = Math.ceil(mn[0] / step) * step; u <= mx[0]; u += step) { const x = sx(u); svg += `<line x1="${x}" y1="0" x2="${x}" y2="${H}" stroke="${Math.abs(u) < 1e-6 ? '#d33' : '#000'}" stroke-opacity="0.15"/><text x="${x + 2}" y="${H - 4}">${u.toFixed(2)}</text>`; }
    for (let v = Math.ceil(mn[1] / step) * step; v <= mx[1]; v += step) { const y = sy(v); svg += `<line x1="0" y1="${y}" x2="${W}" y2="${y}" stroke="${Math.abs(v) < 1e-6 ? '#d33' : '#000'}" stroke-opacity="0.15"/><text x="3" y="${y - 3}">${v.toFixed(2)}</text>`; }
    for (const L of [B.meta.eye, B.meta.obj, ...(B.meta.eyes || [])].filter(Boolean)) {
      const x = sx(U(L.c)), y = sy(Vv(L.c)), r = L.r / (mx[0] - mn[0]) * W;
      svg += `<circle cx="${x}" cy="${y}" r="${view === 'eye' ? r : 4}" fill="none" stroke="#e0218a" stroke-width="2"/>`;
    }
    svg += `<text x="8" y="18" font-size="15" font-weight="bold">${key} ${view}</text></svg>`;
    await sharp(img, { raw: { width: W, height: H, channels: 3 } }).composite([{ input: Buffer.from(svg) }]).png().toFile(path.join(PREV, `${key}_${view}.png`));
  }
}

// ---------------------------------------------------------------- 全部

const META = {};
for (const [key, I] of Object.entries(CFG.items)) {
  const B = await buildItem(key, I);
  await embed(key, B, I);
  await preview(key, B);
  const S = CFG.sources[I.src];
  META[key] = { ...B.meta, credit: `${I.title}：${S.name}，作者 ${S.author}，${S.license} ${S.url}` };
}
// OpticsMeta.lua
const L = [];
L.push('-- 自动生成（tools/weapons/optics.mjs），别手改：瞄准镜、望远镜（Sketchfab 模型原样）的元数据');
L.push('--   坐标是「器材坐标」：格（1 米 = 2.8 格），+Z 朝前（物镜）、+Y 朝上；瞄准镜原点在镜座底面中心（贴在枪的导轨上），望远镜原点在两个目镜中间');
L.push('--   parts[块名] = { c 包围盒中心, s 大小, tri 三角形数, col / met 没贴图的块的颜色、金属度 }；eye / obj 目镜、物镜的中心 c 和半径 r；pts 握把 grip、导轨 rail 等点；size 总尺寸');
L.push('--   导入后 MeshPart 叫 O_<键>__<块名>');
L.push('return {');
const lv = (v) => `{ ${v.join(', ')} }`;
for (const [key, M] of Object.entries(META)) {
  L.push(`  ${key} = {`);
  L.push('    parts = {');
  for (const [p, d] of Object.entries(M.parts)) L.push(`      ${p} = { c = ${lv(d.c)}, s = ${lv(d.s)}, tri = ${d.tri}${d.col ? `, col = ${lv(d.col)}, met = ${d.met}` : ''} },`);
  L.push('    },');
  if (M.eye) L.push(`    eye = { c = ${lv(M.eye.c)}, r = ${M.eye.r} },`);
  if (M.obj) L.push(`    obj = { c = ${lv(M.obj.c)}, r = ${M.obj.r} },`);
  if (M.eyes) L.push(`    eyes = { ${M.eyes.map((e) => `{ c = ${lv(e.c)}, r = ${e.r} }`).join(', ')} },`);
  if (M.pts) L.push(`    pts = { ${Object.entries(M.pts).map(([k, v]) => `${k} = ${lv(v)}`).join(', ')} },`);
  L.push(`    size = ${lv(M.size)},`);
  L.push(`    credit = "${M.credit}",`);
  L.push('  },');
}
L.push('}');
fs.writeFileSync(path.join(ROOT, 'src/ReplicatedStorage/OpticsMeta.lua'), L.join('\n') + '\n');
// 署名：models/credits.txt 里「瞄准镜、望远镜」一节（整节重写）
const cf = path.join(ROOT, 'models/credits.txt');
let txt = fs.existsSync(cf) ? fs.readFileSync(cf, 'utf8') : '';
const HEAD = '第一人称的瞄准镜、望远镜（models/optics/*.glb；游戏里 src/ReplicatedStorage/OpticMesh、OpticsMeta）：';
const i0 = txt.indexOf(HEAD);
if (i0 >= 0) { const i1 = txt.indexOf('\n\n', i0); txt = txt.slice(0, i0) + (i1 >= 0 ? txt.slice(i1 + 2) : ''); }
const sec = [HEAD];
for (const [key, I] of Object.entries(CFG.items)) {
  const S = CFG.sources[I.src];
  sec.push(`  ${I.title}（${key}.glb）：「${S.name}」，作者 ${S.author}，${S.license} ${S.url}`);
}
sec.push('  改动：换了单位（米 → 格）、方向和原点，同一种材质的零件并成一块；合集里只取用到的那一件（消音器、枪口件、弹匣），红点瞄具去掉了前镜片（游戏里看得穿镜筒）；GLB 贴图最长边缩到 1024，游戏内嵌的版本贴图再缩小并压成 256 色；别的几何、材质都没改');
txt = txt.replace(/\s*$/, '\n\n') + sec.join('\n') + '\n';
fs.writeFileSync(cf, txt);
console.log('写好了 OpticsMeta.lua、credits.txt');
