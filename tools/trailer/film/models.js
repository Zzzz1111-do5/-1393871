// 模型：游戏原模型（GLB）的载入和拆部件（炮塔、炮管、车轮、旋翼、尾喷口），程序拼的士兵（R15 方块人 + 头盔夜视仪）、登陆艇、气垫艇
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { clamp, lerp, DEG } from './lib.js';

const loader = new GLTFLoader();
const cache = {};
export let META = null;
export function setMeta(m) { META = m; }
export async function loadGLB(url) {
  if (!cache[url]) cache[url] = new Promise((res, rej) => loader.load(url, g => res(g.scene), undefined, rej));
  return cache[url];
}
// opaque：整架模型的材质按不透明画（原来给整架设成半透明的直-10 用，直-10 11-27 删了）
function prepMats(root, env = 0.6, opaque = false) {
  root.traverse(o => {
    if (o.isMesh) {
      o.castShadow = o.receiveShadow = true;
      const ms = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of ms) {
        if (!m) continue;
        if ('envMapIntensity' in m) m.envMapIntensity = env;
        if ('metalness' in m) m.metalness = Math.min(m.metalness, 0.55);   // 夜里全金属的车只反射黑天空、整辆发黑
        if (m.map) m.map.anisotropy = 4;
        if (opaque && m.transparent) { m.transparent = false; m.opacity = 1; m.depthWrite = true; }
      }
    }
  });
}
// 部件名 V_<键>__<块> → 块
const blockOf = (name, pre) => { const i = name.indexOf('__'); return (i > 0 && name.startsWith(pre)) ? name.slice(i + 2) : null; };
function collect(model, pre) {
  const out = [];
  model.traverse(o => { if (o !== model && o.name && blockOf(o.name, pre)) out.push(o); });
  // 只要最上层的（GLTFLoader 有时把一个节点拆成组 + 几个网格）
  return out.filter(o => { let p = o.parent; while (p && p !== model) { if (out.includes(p)) return false; p = p.parent; } return true; });
}


// —— 国家标志（时代广场宣传片：两边是虚构的红方 / 蓝方，不出现真实的国旗、军徽）——
//   舰艇：整张差不多都是红色的贴图就是国旗（055 的舰旗），那块网格藏起来
function redShare(img, n = 32) {
  const cv = document.createElement('canvas'); cv.width = cv.height = n;
  const g = cv.getContext('2d', { willReadFrequently: true });
  g.drawImage(img, 0, 0, n, n);
  const d = g.getImageData(0, 0, n, n).data;
  let k = 0;
  for (let i = 0; i < d.length; i += 4) if (d[i] > 120 && d[i] > d[i + 1] * 1.8 && d[i] > d[i + 2] * 1.8) k++;
  return k / (n * n);
}
export function hideFlags(model) {
  model.traverse(o => {
    if (!o.isMesh || !o.material) return;
    for (const m of (Array.isArray(o.material) ? o.material : [o.material])) {
      const img = m.map && m.map.image;
      if (img && img.width && redShare(img) > 0.6) o.visible = false;
    }
  });
}
//   飞机、车：贴图上鲜红的一块块（红星机徽、红色舷号）连同里面的黄字（闭运算把红星里的「八一」一起圈进来）用周围的漆面补上
const scrubbed = new Map();
function morph(m, w, h, r, grow) {   // 方形结构元素的膨胀（grow）/ 腐蚀：先横后竖
  const a = new Uint8Array(w * h), b = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    const row = y * w;
    for (let x = 0; x < w; x++) {
      let v = grow ? 0 : 1;
      for (let k = Math.max(0, x - r), e = Math.min(w - 1, x + r); k <= e; k++) {
        if (grow ? m[row + k] : !m[row + k]) { v = grow ? 1 : 0; break; }
      }
      a[row + x] = v;
    }
  }
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) {
      let v = grow ? 0 : 1;
      for (let k = Math.max(0, y - r), e = Math.min(h - 1, y + r); k <= e; k++) {
        if (grow ? a[k * w + x] : !a[k * w + x]) { v = grow ? 1 : 0; break; }
      }
      b[y * w + x] = v;
    }
  }
  return b;
}
function scrubTexture(tex) {
  if (!tex || scrubbed.has(tex)) return scrubbed.get(tex) || tex;
  const img = tex.image;
  scrubbed.set(tex, tex);
  if (!img || !img.width) return tex;
  const w = img.width, h = img.height, N = w * h;
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  const g = cv.getContext('2d', { willReadFrequently: true });
  g.drawImage(img, 0, 0);
  const im = g.getImageData(0, 0, w, h), d = im.data;
  let m = new Uint8Array(N), n = 0;
  for (let p = 0, i = 0; p < N; p++, i += 4) if (d[i] > 110 && d[i] > d[i + 1] * 1.8 && d[i] > d[i + 2] * 1.8) { m[p] = 1; n++; }
  if (n < 4 || n > N * 0.2) return tex;   // 没有，或者一大片都是红的（整块涂装）：不动
  const s = w / 1024;
  m = morph(morph(m, w, h, Math.round(9 * s), true), w, h, Math.round(6 * s), false);   // 闭运算 + 往外多 3 格（边上的抗锯齿、黄边）
  // 积分图：没盖住的像素的颜色和、个数，盖住的像素取周围（由近到远）没盖住的平均色
  const S = [new Uint32Array((w + 1) * (h + 1)), new Uint32Array((w + 1) * (h + 1)), new Uint32Array((w + 1) * (h + 1)), new Uint32Array((w + 1) * (h + 1))];
  for (let y = 0; y < h; y++) {
    let rr = 0, rg = 0, rb = 0, rc = 0;
    for (let x = 0; x < w; x++) {
      const p = y * w + x, i = p * 4;
      if (!m[p]) { rr += d[i]; rg += d[i + 1]; rb += d[i + 2]; rc++; }
      const q = (y + 1) * (w + 1) + x + 1, up = y * (w + 1) + x + 1;
      S[0][q] = S[0][up] + rr; S[1][q] = S[1][up] + rg; S[2][q] = S[2][up] + rb; S[3][q] = S[3][up] + rc;
    }
  }
  const box = (c, x0, y0, x1, y1) => S[c][y1 * (w + 1) + x1] - S[c][y0 * (w + 1) + x1] - S[c][y1 * (w + 1) + x0] + S[c][y0 * (w + 1) + x0];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const p = y * w + x;
    if (!m[p]) continue;
    for (const R of [8, 16, 32, 64, 128].map(v => Math.round(v * s))) {
      const x0 = Math.max(0, x - R), y0 = Math.max(0, y - R), x1 = Math.min(w, x + R + 1), y1 = Math.min(h, y + R + 1);
      const c = box(3, x0, y0, x1, y1);
      if (c > 8) { const i = p * 4; d[i] = box(0, x0, y0, x1, y1) / c; d[i + 1] = box(1, x0, y0, x1, y1) / c; d[i + 2] = box(2, x0, y0, x1, y1) / c; break; }
    }
  }
  g.putImageData(im, 0, 0);
  const t2 = new THREE.CanvasTexture(cv);
  for (const k of ['colorSpace', 'flipY', 'wrapS', 'wrapT', 'magFilter', 'minFilter', 'anisotropy', 'channel']) if (k in tex) t2[k] = tex[k];
  t2.generateMipmaps = true;
  t2.needsUpdate = true;
  scrubbed.set(tex, t2);
  return t2;
}
export function scrubInsignia(model) {
  model.traverse(o => {
    if (!o.isMesh || !o.material) return;
    const list = Array.isArray(o.material) ? o.material : [o.material];
    for (const mt of list) if (mt.map) { mt.map = scrubTexture(mt.map); mt.needsUpdate = true; }
  });
}

let BLOB = null;
function blobMat() {
  if (!BLOB) {
    const cv = document.createElement('canvas'); cv.width = cv.height = 128;
    const g = cv.getContext('2d'), gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, 'rgba(0,0,0,0.85)'); gr.addColorStop(0.55, 'rgba(0,0,0,0.6)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    const t = new THREE.CanvasTexture(cv);
    BLOB = new THREE.MeshBasicMaterial({ map: t, color: 0x000000, transparent: true, opacity: 0.55, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  }
  return BLOB;
}
// 拍片以后游戏里换过的模型（11-18 起）：99A 换成 99A2、M1A2 换成沙漠涂装 SEPv2——分镜里还按老键写，这里换成现在的文件
const VEH_KEY = { ztz99: 'ztz99a2', m1a2v3: 'm1a2dc' };
// 原模型里分错块的：PGL-625 炮塔两侧的四联导弹管、发射架烘焙在车体那块网格（Body_1）里，炮塔转、导弹不转（用户 11-22）——
//   按三角形位置（车体坐标）拆出来挂到炮塔的俯仰架上（跟着炮转、跟着炮抬头）
const VEH_MOVE = {
  t625: [{ mesh: '__Body_1', to: 'gun', test: (x, y, z) => y > 7.75 && Math.abs(x - 0.14) > 3.2 && Math.abs(x - 0.14) < 5.8 && z > -4.6 && z < 5.6 }],
};
function moveTris(root, model, key, groups) {
  for (const R of VEH_MOVE[key] || []) {
    let src = null;
    model.traverse(o => { if (!src && o.isMesh && (o.name.endsWith(R.mesh) || (o.parent && o.parent.name.endsWith(R.mesh)))) src = o; });
    if (!src || !src.geometry.index) continue;
    root.updateMatrixWorld(true);
    const toRoot = new THREE.Matrix4().copy(root.matrixWorld).invert().multiply(src.matrixWorld);
    const pos = src.geometry.attributes.position, idx = src.geometry.index.array;
    const v = new THREE.Vector3(), keep = [], take = [];
    const inside = i => { v.fromBufferAttribute(pos, i).applyMatrix4(toRoot); return R.test(v.x, v.y, v.z); };
    for (let t = 0; t < idx.length; t += 3) (inside(idx[t]) && inside(idx[t + 1]) && inside(idx[t + 2]) ? take : keep).push(idx[t], idx[t + 1], idx[t + 2]);
    if (!take.length) continue;
    const g2 = src.geometry.clone();
    g2.setIndex(take); g2.clearGroups();
    src.geometry = src.geometry.clone(); src.geometry.setIndex(keep); src.geometry.clearGroups();
    const m2 = new THREE.Mesh(g2, src.material);
    m2.castShadow = m2.receiveShadow = true;
    src.parent.add(m2); m2.position.copy(src.position); m2.quaternion.copy(src.quaternion); m2.scale.copy(src.scale);
    groups[R.to].attach(m2);
  }
}
// —— 地面载具：炮塔、炮管、车轮各挂一个转轴 ——
// 车上的星徽是单独的几块小网格（纯色贴图：红星、黄字），贴图里擦不掉（整张都是红的），整块藏起来
const EMB_MESH = { ztz99a2: ['__Body_13', '__Body_15', '__Turret_5', '__Turret_6'] };
export async function vehicle(key, base) {
  key = VEH_KEY[key] || key;
  const M = META.ImportedMeta.m[key];
  const src = await loadGLB(`${base}/models/veh/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.25);
  eraseEmblems(key, model);
  scrubInsignia(model);
  if (EMB_MESH[key]) model.traverse(o => { if (o.isMesh && EMB_MESH[key].some(k => o.name.endsWith(k) || (o.parent && o.parent.name.endsWith(k)))) o.visible = false; });
  const root = new THREE.Group(); root.name = 'veh:' + key;
  root.add(model);
  root.updateMatrixWorld(true);
  const tur = new THREE.Group(), gun = new THREE.Group(), recoil = new THREE.Group();
  if (M.tur) tur.position.fromArray(M.tur);
  root.add(tur);
  if (M.gun) { gun.position.fromArray(M.gun); gun.position.sub(tur.position); }
  tur.add(gun); gun.add(recoil);
  const wheels = [];
  for (const o of collect(model, 'V_' + key)) {
    const b = blockOf(o.name, 'V_' + key), part = M.parts[b];
    const g = part ? part.g : 'Body';
    if (g === 'Turret') tur.attach(o);
    else if (g === 'Gun') recoil.attach(o);
    else if (/^W\d+/.test(g) && M.wheels && M.wheels[g]) {
      let w = wheels.find(x => x.g === g);
      if (!w) { const piv = new THREE.Group(); piv.position.fromArray(M.wheels[g].c); root.add(piv); w = { g, piv, r: M.wheels[g].r }; wheels.push(w); }
      w.piv.attach(o);
    }
  }
  moveTris(root, model, key, { tur, gun, recoil });
  // 车底的接触阴影（环境光遮蔽）：车和地面贴着的地方一圈暗（只有太阳的影子时车像飘在沙上）
  if (M.hull) {
    const blob = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), blobMat());
    blob.rotation.x = -Math.PI / 2;
    blob.scale.set(M.hull[0] * 1.3, M.hull[2] * 1.12, 1);
    blob.position.set(0, 0.06, 0);
    blob.renderOrder = -1; blob.name = 'contactShadow';
    root.add(blob);
  }
  const V = {
    root, M, tur, gun, recoil, wheels, len: M.len,
    // 车体坐标里的一点（炮塔、炮都在零位时）→ 跟着炮塔转、炮抬头以后的世界坐标（导弹管口之类）
    gunPt: p => gun.localToWorld(new THREE.Vector3(p[0] - (M.gun ? M.gun[0] : 0), p[1] - (M.gun ? M.gun[1] : 0), p[2] - (M.gun ? M.gun[2] : 0))),
    muzzle: () => recoil.localToWorld(new THREE.Vector3(0, 0, -(M.muz || 8))),
    muzzleDir: () => new THREE.Vector3(0, 0, -1).transformDirection(recoil.matrixWorld),
    aim(yaw, pitch) { tur.rotation.y = yaw; gun.rotation.x = pitch; },
    kick(k) { recoil.position.z = k * 1.6; },   // 后坐（0–1）
    roll(dist) { for (const w of wheels) w.piv.rotation.x = -dist / Math.max(0.3, w.r); },
  };
  return V;
}

// —— 飞机、直升机：旋翼转起来、尾喷口位置 ——
export async function aircraft(key, base) {
  // 飞机的 GLB 后来换成了新版（零件叫 A_<键>_v<N>__…，元数据在 ImportedAir.m[<键>_v<N>]）：文件名照旧，零件前缀、元数据按别名找最新那版
  const ver = (META.ImportedAir.alias && Object.values(META.ImportedAir.alias).find(v => typeof v === 'string' && v.replace(/~$/, '').replace(/_v\d+$/, '') === key)) || key;
  const vk = ver.replace(/~$/, '');
  const M = META.ImportedAir.m[vk] || META.ImportedAir.m[key];
  const src = await loadGLB(`${base}/models/air/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.35, false);
  scrubInsignia(model);
  // 歼-20：原模型的漆面偏亮、偏光滑，月光在机背两条发动机舱的弧面上反出两道白光（用户看着像光柱）；按真机的暗灰隐身涂层压暗、调成哑光
  if (key === 'j20') model.traverse(o => {
    if (!o.isMesh || !o.material || o.material.transparent) return;
    o.material = o.material.clone();
    o.material.roughness = Math.max(o.material.roughness ?? 0.5, 0.66); o.material.metalness = Math.min(o.material.metalness ?? 0, 0.3);
    o.material.color.multiplyScalar(0.62); o.material.envMapIntensity = 0.25;
  });
  const root = new THREE.Group(); root.name = 'air:' + key;
  root.add(model);
  root.updateMatrixWorld(true);
  const rot = {};
  for (const k of ['rotor', 'rotor2', 'trotor']) if (M[k]) { const g = new THREE.Group(); g.position.fromArray(M[k].p); g.userData.axis = new THREE.Vector3().fromArray(M[k].a).normalize(); root.add(g); rot[k] = g; }
  const gear = [];
  for (const o of collect(model, 'A_' + vk)) {
    const b = blockOf(o.name, 'A_' + vk), part = M.parts[b];
    const g = part ? part.g : 'Body';
    if (g === 'Rotor' && rot.rotor) rot.rotor.attach(o);
    else if (g === 'Rotor2' && rot.rotor2) rot.rotor2.attach(o);
    else if (g === 'TRotor' && rot.trotor) rot.trotor.attach(o);
    else if (/^(Gear|GDoor)/.test(g)) gear.push(o);   // 起落架、舱门（歼-20、F-22 是后补的零件，机腹蒙皮是完整的）：飞着的时候藏起来
  }
  return {
    root, M, rot, gear, noz: (M.noz || []).map(a => ({ p: new THREE.Vector3(a[0], a[1], a[2]), r: a[3] })),
    spin(t, rpm = 1) {
      for (const [k, g] of Object.entries(rot)) g.quaternion.setFromAxisAngle(g.userData.axis, t * (k === 'trotor' ? 31 : 13) * rpm);
    },
    gearDown(on) { for (const o of gear) o.visible = on; },
  };
}

// 舰艇桅杆、舰艉上的旗子：贴图集里的一小块，和别的零件共用一张贴图（hideFlags 按整块网格找不到）。
//   按连通块找：水线以上、小块（几十个三角形以内）、贴图上这块大半是红的 → 整块去掉（三角形压成一个点）
const pxCache = new Map(), flagDone = new WeakSet();
function texPixels(img) {
  if (pxCache.has(img)) return pxCache.get(img);
  const cv = document.createElement('canvas'); cv.width = img.width; cv.height = img.height;
  const g = cv.getContext('2d', { willReadFrequently: true }); g.drawImage(img, 0, 0);
  const r = { w: img.width, h: img.height, d: g.getImageData(0, 0, img.width, img.height).data };
  pxCache.set(img, r);
  return r;
}
export function dropFlagBits(model, maxTris = 80) {
  model.traverse(o => {
    if (!o.isMesh || !o.geometry || flagDone.has(o.geometry)) return;
    flagDone.add(o.geometry);
    const mt = Array.isArray(o.material) ? o.material[0] : o.material;
    const g = o.geometry, uv = g.attributes.uv, pos = g.attributes.position;
    if (!mt || !mt.map || !mt.map.image || !mt.map.image.width || !uv || !g.index) return;
    const P = texPixels(mt.map.image), idx = g.index.array, n = pos.count;
    const par = new Int32Array(n); for (let i = 0; i < n; i++) par[i] = i;
    const f = i => { while (par[i] !== i) { par[i] = par[par[i]]; i = par[i]; } return i; };
    const un = (a, b) => { a = f(a); b = f(b); if (a !== b) par[b] = a; };
    for (let t = 0; t < idx.length; t += 3) { un(idx[t], idx[t + 1]); un(idx[t], idx[t + 2]); }
    const comp = new Map();
    for (let t = 0; t < idx.length; t += 3) { const r = f(idx[t]); let c = comp.get(r); if (!c) comp.set(r, c = []); c.push(t); }
    let dropped = 0;
    for (const tris of comp.values()) {
      if (tris.length > maxTris) continue;
      let y = 0, u0 = 1e9, u1 = -1e9, v0 = 1e9, v1 = -1e9;
      for (const t of tris) for (let k = 0; k < 3; k++) { const i = idx[t + k]; y += pos.getY(i); const u = uv.getX(i), v = uv.getY(i); u0 = Math.min(u0, u); u1 = Math.max(u1, u); v0 = Math.min(v0, v); v1 = Math.max(v1, v); }
      if (y / (tris.length * 3) <= 0.5) continue;   // 水线以下（船底的防污漆是红的）不管
      let red = 0;
      for (let a = 0; a < 16; a++) for (let b = 0; b < 16; b++) {
        let u = u0 + (u1 - u0) * (a + 0.5) / 16, v = v0 + (v1 - v0) * (b + 0.5) / 16;
        u -= Math.floor(u); v -= Math.floor(v);
        const i = (Math.min(P.h - 1, Math.floor(v * P.h)) * P.w + Math.min(P.w - 1, Math.floor(u * P.w))) * 4;
        if (P.d[i] > 120 && P.d[i] > P.d[i + 1] * 1.8 && P.d[i] > P.d[i + 2] * 1.8) red++;
      }
      if (red < 64) continue;   // 这块贴图四分之一以上是红的
      for (const t of tris) { idx[t + 1] = idx[t]; idx[t + 2] = idx[t]; }
      dropped += tris.length;
    }
    if (dropped) { g.index.needsUpdate = true; console.log('[film] 去掉旗子', o.name, dropped); }
  });
}

// —— 舰艇：游戏里按 1 米 = 1.68 格，片子里按真实比例（和车一样 2.8 格）放大 ——
export const SHIP_K = 2.8 / 1.68;
export async function ship(key, base) {
  const M = META.ImportedShip.m[key];
  const src = await loadGLB(`${base}/models/ship/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.2);
  hideFlags(model);
  dropFlagBits(model);
  const root = new THREE.Group(); root.name = 'ship:' + key;
  model.scale.setScalar(SHIP_K);
  root.add(model);
  return { root, M, k: SHIP_K, len: M.len * SHIP_K };
}

// —— 士兵：R15 方块人（圆角），两队迷彩、头盔、夜视仪、臂章、防弹背心，手里一支 M4 ——
const UNIFORM = { atk: [0x96805c, 0x6e6046], def: [0x546846, 0x404e36] };
const HELMET = { atk: 0x60684a, def: 0x928060 };
const BAND = { atk: 0xdc4637, def: 0x3c78e6 };
const SKIN = [0xe0b48c, 0xc89670, 0x9c6c4c, 0xf0c8a0, 0x7a5236];
let faceTex = null;
function makeFace() {
  if (faceTex) return faceTex;
  const cv = document.createElement('canvas'); cv.width = cv.height = 128;
  const g = cv.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, 128, 128);
  g.fillStyle = '#1a1410';
  g.beginPath(); g.ellipse(44, 58, 7, 10, 0, 0, Math.PI * 2); g.fill();
  g.beginPath(); g.ellipse(84, 58, 7, 10, 0, 0, Math.PI * 2); g.fill();
  g.lineWidth = 5; g.lineCap = 'round';
  g.beginPath(); g.moveTo(32, 40); g.lineTo(54, 45); g.stroke();
  g.beginPath(); g.moveTo(96, 40); g.lineTo(74, 45); g.stroke();
  g.lineWidth = 4; g.beginPath(); g.moveTo(52, 92); g.quadraticCurveTo(64, 89, 76, 92); g.stroke();
  faceTex = new THREE.CanvasTexture(cv); faceTex.colorSpace = THREE.SRGBColorSpace;
  return faceTex;
}
const RB = (w, h, d, r = 0.12) => new RoundedBoxGeometry(w, h, d, 3, Math.min(r, w / 2 - 0.01, h / 2 - 0.01, d / 2 - 0.01));
const geoCache = {};
const geo = (k, f) => geoCache[k] || (geoCache[k] = f());
export function soldier(team, opt = {}) {
  const U = UNIFORM[team], tex = opt.fabric;
  const mat = (c, r = 0.9, extra = {}) => new THREE.MeshStandardMaterial({ color: c, roughness: r, metalness: 0, map: tex || null, envMapIntensity: 0.12, ...extra });
  const mTop = mat(U[0]), mLeg = mat(U[1]), mHelm = mat(HELMET[team], 0.75), mVest = mat(team === 'atk' ? 0x5c6044 : 0x7a6c50, 0.95);
  const skin = SKIN[(opt.skin ?? 0) % SKIN.length];
  const mSkin = new THREE.MeshStandardMaterial({ color: skin, roughness: 0.65 , envMapIntensity: 0.12 });
  const mFace = new THREE.MeshStandardMaterial({ color: skin, roughness: 0.65, map: makeFace() , envMapIntensity: 0.12 });
  const mDark = new THREE.MeshStandardMaterial({ color: 0x1c1d1f, roughness: 0.5, metalness: 0.4 });
  const mBoot = new THREE.MeshStandardMaterial({ color: 0x2a221c, roughness: 0.8 });
  const mBand = new THREE.MeshStandardMaterial({ color: BAND[team], emissive: BAND[team], emissiveIntensity: 0.5, roughness: 0.5 });
  const mLens = new THREE.MeshStandardMaterial({ color: 0x103018, emissive: 0x30ff60, emissiveIntensity: opt.nvgGlow ?? 0.0, roughness: 0.2 });
  const M = (g, m) => { const x = new THREE.Mesh(g, m); x.castShadow = true; x.receiveShadow = true; return x; };
  const J = (parent, x, y, z) => { const g = new THREE.Group(); g.position.set(x, y, z); parent.add(g); return g; };
  const root = new THREE.Group();
  const hip = J(root, 0, 2.35, 0);          // 腰（下身的根）
  const lowT = M(geo('lt', () => RB(1.8, 0.42, 0.92, 0.1)), mLeg); lowT.position.y = 0.05; hip.add(lowT);
  const chest = J(hip, 0, 0.25, 0);          // 腰关节 → 上身
  const upT = M(geo('ut', () => RB(1.8, 1.42, 0.95, 0.14)), mTop); upT.position.y = 0.72; chest.add(upT);
  const vest = M(geo('vest', () => RB(1.92, 1.05, 1.12, 0.12)), mVest); vest.position.set(0, 0.68, 0); chest.add(vest);
  for (let i = -1; i <= 1; i++) { const p = M(geo('pouch', () => RB(0.42, 0.5, 0.26, 0.06)), mVest); p.position.set(i * 0.5, 0.55, -0.66); chest.add(p); }
  const radio = M(geo('radio', () => RB(0.45, 0.75, 0.3, 0.05)), mDark); radio.position.set(-0.5, 0.75, 0.66); chest.add(radio);
  const neck = J(chest, 0, 1.45, 0);
  const head = M(geo('head', () => RB(1.05, 1.05, 1.05, 0.28)), [mSkin, mSkin, mSkin, mSkin, mSkin, mFace]); head.position.y = 0.55; neck.add(head);
  // 头盔（球冠）、帽檐、夜视仪支架和双筒、耳机
  const helm = M(geo('helm', () => new THREE.SphereGeometry(0.5, 20, 12, 0, Math.PI * 2, 0, Math.PI * 0.55)), mHelm);
  helm.scale.set(1.36, 1.05, 1.42); helm.position.set(0, 0.62, 0.03); neck.add(helm);
  const rim = M(geo('rim', () => new THREE.CylinderGeometry(0.72, 0.74, 0.12, 24)), mHelm); rim.scale.set(1, 1, 1.05); rim.position.set(0, 0.74, 0.03); neck.add(rim);
  for (const s of [-1, 1]) { const e = M(geo('ear', () => RB(0.2, 0.46, 0.42, 0.08)), mDark); e.position.set(s * 0.58, 0.52, 0.02); neck.add(e); }
  const nvgPiv = J(neck, 0, 0.98, -0.68);
  const mount = M(geo('mount', () => RB(0.3, 0.22, 0.16, 0.04)), mDark); nvgPiv.add(mount);
  const nvg = J(nvgPiv, 0, -0.12, -0.12);
  const body = M(geo('nvgb', () => RB(0.58, 0.18, 0.22, 0.05)), mDark); nvg.add(body);
  for (const s of [-1, 1]) {
    const tube = M(geo('tube', () => new THREE.CylinderGeometry(0.11, 0.12, 0.34, 12).rotateX(Math.PI / 2)), mDark); tube.position.set(s * 0.17, -0.08, -0.18); nvg.add(tube);
    const lens = M(geo('lens', () => new THREE.CircleGeometry(0.09, 12)), mLens); lens.position.set(s * 0.17, -0.08, -0.36); lens.rotation.y = Math.PI; nvg.add(lens);
  }
  // 腿、手臂（关节组 + 一截一截）
  const leg = (s) => {
    const hj = J(hip, s * 0.45, -0.05, 0);
    const th = M(geo('th', () => RB(0.85, 1.05, 0.88, 0.12)), mLeg); th.position.y = -0.52; hj.add(th);
    const kj = J(hj, 0, -1.05, 0);
    const sh = M(geo('sh', () => RB(0.8, 1.05, 0.82, 0.12)), mLeg); sh.position.y = -0.52; kj.add(sh);
    const pad = M(geo('kpad', () => RB(0.6, 0.45, 0.2, 0.06)), mDark); pad.position.set(0, -0.08, -0.44); kj.add(pad);
    const aj = J(kj, 0, -1.05, 0);
    const ft = M(geo('ft', () => RB(0.84, 0.3, 1.12, 0.1)), mBoot); ft.position.set(0, -0.13, -0.12); aj.add(ft);
    return { hj, kj, aj };
  };
  const arm = (s) => {
    const sj = J(chest, s * 1.27, 1.3, 0);
    const ua = M(geo('ua', () => RB(0.78, 1.05, 0.8, 0.12)), mTop); ua.position.y = -0.48; sj.add(ua);
    const ej = J(sj, 0, -1.0, 0);
    const la = M(geo('la', () => RB(0.74, 0.95, 0.76, 0.12)), mTop); la.position.y = -0.45; ej.add(la);
    const hand = M(geo('hand', () => RB(0.66, 0.36, 0.7, 0.12)), new THREE.MeshStandardMaterial({ color: 0x252322, roughness: 0.8 })); hand.position.y = -1.0; ej.add(hand);
    if (s > 0) { const band = M(geo('band', () => new THREE.CylinderGeometry(0.43, 0.43, 0.24, 16)), mBand); band.position.y = -0.3; sj.add(band); }
    return { sj, ej, len1: 1.0, len2: 1.05 };
  };
  const L = { l: leg(-1), r: leg(1) }, A = { l: arm(-1), r: arm(1) };
  // 枪：游戏的第一人称 M4（GLB），握把在右手
  const gunPiv = new THREE.Group(); chest.add(gunPiv);
  if (opt.rifle) {
    const g = opt.rifle.clone(true);
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.material = o.material.clone(); o.material.envMapIntensity = 0.5; } });
    g.position.set(0, 0, 0.35);   // 握把（≈ z +0.35）放在转轴
    gunPiv.add(g);
  }
  root.traverse(o => { if (o.isMesh) o.layers.enable(0); });
  const S = { root, hip, chest, neck, nvg, L, A, gunPiv, team, mLens,
    nvgDown(k) { nvg.rotation.x = lerp(-80 * DEG, 0, k); nvg.position.y = lerp(0.1, -0.12, k); },
  };
  S.nvgDown(opt.nvg ?? 1);
  return S;
}
// 两节手臂的 IK：让手到 target（士兵本地坐标），肘往 pole 方向弯
const _v = new THREE.Vector3(), _w = new THREE.Vector3(), _q = new THREE.Quaternion();
export function armIK(S, side, targetLocal, pole) {
  const a = S.A[side];
  S.root.updateMatrixWorld(true);
  const shW = a.sj.getWorldPosition(new THREE.Vector3());
  const tgW = S.root.localToWorld(targetLocal.clone());
  const poleW = S.root.localToWorld(pole.clone());
  const d = tgW.clone().sub(shW), dist = clamp(d.length(), 0.1, a.len1 + a.len2 - 0.02);
  // 余弦定理：肩角
  const cosA = (a.len1 * a.len1 + dist * dist - a.len2 * a.len2) / (2 * a.len1 * dist);
  const angA = Math.acos(clamp(cosA, -1, 1));
  const dirN = d.clone().normalize();
  const pl = poleW.clone().sub(shW); pl.sub(dirN.clone().multiplyScalar(pl.dot(dirN))).normalize();
  const elbowDir = dirN.clone().multiplyScalar(Math.cos(angA)).add(pl.multiplyScalar(Math.sin(angA)));
  const elbowW = shW.clone().add(elbowDir.multiplyScalar(a.len1));
  // 上臂：本地 −Y 指向肘
  const parentQ = a.sj.parent.getWorldQuaternion(new THREE.Quaternion());
  const wantUp = elbowW.clone().sub(shW).normalize();
  const qUp = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, -1, 0), wantUp.clone().applyQuaternion(parentQ.clone().invert()));
  a.sj.quaternion.copy(qUp);
  a.sj.updateMatrixWorld(true);
  const sjQ = a.sj.getWorldQuaternion(new THREE.Quaternion());
  const wantLo = tgW.clone().sub(elbowW).normalize();
  a.ej.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), wantLo.applyQuaternion(sjQ.invert()));
}
// 姿势：腿、身子（弧度）；手臂由枪的位置 IK 出来
export function pose(S, P) {
  const { L, hip, chest, neck } = S;
  hip.position.y = 2.35 + (P.hipY || 0);
  hip.rotation.set(P.hipX || 0, P.hipYaw || 0, P.hipZ || 0);
  chest.rotation.set(P.lean || 0, P.twist || 0, P.side || 0);
  neck.rotation.set(P.headX || 0, P.headY || 0, 0);
  for (const s of ['l', 'r']) {
    const p = P[s] || [0, 0, 0];
    L[s].hj.rotation.set(p[0], 0, p[3] || 0); L[s].kj.rotation.set(p[1], 0, 0); L[s].aj.rotation.set(p[2], 0, 0);
  }
  // 枪：在上身坐标里摆
  const g = P.gun || { p: [0.55, 0.85, -0.9], r: [0, 0, 0] };
  S.gunPiv.position.fromArray(g.p);
  S.gunPiv.rotation.set(g.r[0], g.r[1], g.r[2], 'YXZ');
  S.root.updateMatrixWorld(true);
  // 手：右手握把、左手护木
  const grip = S.gunPiv.localToWorld(new THREE.Vector3(0, -0.12, 0.38)), fore = S.gunPiv.localToWorld(new THREE.Vector3(0, -0.06, -0.55));
  const toL = v => S.root.worldToLocal(v);
  armIK(S, 'r', toL(grip.clone()), new THREE.Vector3(2.5, 1.5, 1.5));
  armIK(S, 'l', toL(fore.clone()), new THREE.Vector3(-2.5, 0.5, 0.5));
}
// 跑：一个周期（u 0–1）
export function runPose(u, k = 1) {
  const s = Math.sin(u * Math.PI * 2), c = Math.cos(u * Math.PI * 2);
  return { hipY: -0.12 + Math.abs(c) * 0.18 * k, lean: 0.18 * k, l: [s * 0.75 * k, Math.max(0, -c) * 1.1 * k + 0.15, -0.2 * s * k], r: [-s * 0.75 * k, Math.max(0, c) * 1.1 * k + 0.15, 0.2 * s * k],
    side: s * 0.04 * k, twist: s * 0.08 * k, headX: -0.1 * k, gun: { p: [0.45, 0.7, -1.0], r: [-0.25, 0.25 + s * 0.05, 0.2] } };
}
export const AIM = { hipY: -0.05, lean: 0.06, l: [0.25, 0.2, -0.1, -0.08], r: [-0.25, 0.3, 0.0, 0.08], twist: 0.35, headX: 0.12, headY: -0.3, gun: { p: [0.45, 1.12, -0.85], r: [0, 0.35, 0] } };
export const KNEEL = { hipY: -0.95, lean: 0.1, l: [1.15, -0.2, 0.2], r: [-0.15, 2.0, -0.2], twist: 0.3, headX: 0.12, headY: -0.25, gun: { p: [0.45, 1.1, -0.85], r: [0, 0.3, 0] } };
export const CROUCH = { hipY: -1.05, lean: 0.35, l: [1.35, -1.7, 0.4], r: [1.25, -1.7, 0.4], headX: 0.25, gun: { p: [0.2, 0.55, -0.7], r: [-1.25, 0, 0] } };
// 站着端枪（低姿待命）：上身像 AIM 那样朝枪的方向拧一点，左肩才够得着护木——原来没拧身子，左臂要横过整个胸口去抓枪，
//   手臂拉直、枪飘在胸前（用户：士兵那个枪拿的姿势那么怪）
export const STAND = { hipY: -0.02, lean: 0.03, twist: 0.3, l: [0.14, 0.12, -0.06, -0.06], r: [-0.14, 0.16, 0, 0.06],
  headX: 0.05, gun: { p: [0.45, 1.0, -0.86], r: [-0.3, 0.34, 0.02] } };

// —— 登陆艇（LCM）、气垫艇（726）：照游戏里的样子拼、细一点 ——
export function landingCraft(tex) {
  const g = new THREE.Group();
  const hull = new THREE.MeshStandardMaterial({ color: 0x5c6460, roughness: 0.7, metalness: 0.35, map: tex.grime, envMapIntensity: 0.15 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x2a2e2c, roughness: 0.8, metalness: 0.3, map: tex.grime, envMapIntensity: 0.15 });
  const red = new THREE.MeshStandardMaterial({ color: 0x5a1e18, roughness: 0.8 });
  const B = (w, h, d, m, x, y, z) => { const b = new THREE.Mesh(RB(w, h, d, 0.15), m); b.position.set(x, y, z); b.castShadow = b.receiveShadow = true; g.add(b); return b; };
  B(16, 1.6, 34, hull, 0, -1.6, 0); B(15.6, 1.0, 33.6, red, 0, -2.6, 0);   // 船底（水线下红漆）
  B(1, 6, 34, hull, -7.5, 1, 0); B(1, 6, 34, hull, 7.5, 1, 0); B(16, 7, 1, hull, 0, 1.5, 16.5);
  B(14, 0.3, 32, dark, 0, -0.75, 0);   // 甲板
  B(6, 4, 4, hull, 0, 6, 14); B(6.4, 0.4, 4.4, dark, 0, 8.2, 14);   // 驾驶室
  for (const s of [-1, 1]) { B(0.3, 0.3, 30, dark, s * 7.5, 4.15, 0); }
  const ramp = new THREE.Group(); ramp.position.set(0, -1.6, -17); g.add(ramp);
  const rp = new THREE.Mesh(RB(15, 6.4, 0.8, 0.15), hull); rp.position.set(0, 3.2, 0); rp.castShadow = true; ramp.add(rp);
  return { root: g, ramp, setRamp(k) { ramp.rotation.x = -k * 1.35; } };
}
export function hovercraft(tex) {
  const g = new THREE.Group();
  const grey = new THREE.MeshStandardMaterial({ color: 0x6c7470, roughness: 0.65, metalness: 0.35, map: tex.grime, envMapIntensity: 0.15 });
  const deck = new THREE.MeshStandardMaterial({ color: 0x4a504c, roughness: 0.55, metalness: 0.5, map: tex.grime, envMapIntensity: 0.15 });
  const skirt = new THREE.MeshStandardMaterial({ color: 0x141416, roughness: 0.95 });
  const B = (w, h, d, m, x, y, z, r = 0.2) => { const b = new THREE.Mesh(RB(w, h, d, r), m); b.position.set(x, y, z); b.castShadow = b.receiveShadow = true; g.add(b); return b; };
  B(28, 3.2, 48, skirt, 0, -1.6, 0, 1.2);
  B(24, 1, 44, deck, 0, 0.3, 0);
  const fans = [];
  for (const s of [-1, 1]) {
    B(3, 4.2, 40, grey, s * 12.5, 2.4, 0);
    const duct = new THREE.Mesh(new THREE.TorusGeometry(4.2, 0.7, 12, 32), grey); duct.position.set(s * 6, 6.5, 20); duct.castShadow = true; g.add(duct);
    const fan = new THREE.Group(); fan.position.set(s * 6, 6.5, 20); g.add(fan);
    for (let i = 0; i < 4; i++) { const bl = new THREE.Mesh(new THREE.BoxGeometry(0.5, 7.6, 0.25), deck); bl.rotation.z = i * Math.PI / 4; fan.add(bl); }
    fans.push(fan);
    B(0.4, 7, 3, grey, s * 6, 6.2, 24);
  }
  B(4, 4.6, 6.5, grey, 10.5, 6.6, -14); B(4.2, 1.2, 6.7, deck, 10.5, 9.0, -14);
  return { root: g, fans, spin(t) { for (const f of fans) f.rotation.z = t * 25; } };
}

// —— 导弹精模：车削的弹体（导引头罩 / 雷达罩、弹体、收口的尾段）、喷管，有厚度带后掠的弹翼和舵面，色带、吊挂；弹头朝 −Z、中心在原点 ——
//   o：len 全长、r 半径、nose 'ir'（玻璃半球罩，红外弹）/ 'radar'（尖拱雷达罩）、strake 长条弹翼 [前缘起点 0–1, 弦长 0–1, 翼展]、
//      fins 尾舵 [根弦, 梢弦, 翼展, 后掠]、canard 前翼 [位置 0–1, 根弦, 梢弦, 翼展, 后掠]、bands 色带 [[位置 0–1, 宽 0–1, 颜色]…]、lugs 吊挂、roll 弹翼滚转角
export function missileModel(o) {
  const { len, r, nose = 'radar', strake = null, fins = null, canard = null, bands = [], col = 0xd8dadc, lugs = false, roll = Math.PI / 4 } = o;
  const g = new THREE.Group();
  const mBody = new THREE.MeshStandardMaterial({ color: col, roughness: 0.36, metalness: 0.25, envMapIntensity: 0.7 });
  const mFin = new THREE.MeshStandardMaterial({ color: new THREE.Color(col).multiplyScalar(0.84), roughness: 0.4, metalness: 0.25, envMapIntensity: 0.6 });
  const mDark = new THREE.MeshStandardMaterial({ color: 0x26292c, roughness: 0.5, metalness: 0.6, envMapIntensity: 0.5 });
  const mGlass = new THREE.MeshStandardMaterial({ color: 0x0a0f14, roughness: 0.03, metalness: 0.95, envMapIntensity: 2.2 });
  const add = (geo, m) => { const x = new THREE.Mesh(geo, m); x.castShadow = true; x.receiveShadow = true; g.add(x); return x; };
  // 外形（半径, 离尾部的距离），从尾到头
  const P = [], V = (a, b) => P.push(new THREE.Vector2(Math.max(0.0005, a), b));
  V(r * 0.6, 0); V(r * 0.86, r * 0.35); V(r, r * 1.3);
  if (nose === 'ir') {
    const s0 = len - r * 1.5;
    V(r, s0); V(r * 0.93, s0 + r * 0.25); V(r * 0.93, len - r * 0.55); V(r * 0.88, len - r * 0.5);
  } else {
    const nL = r * 5.2, s0 = len - nL;
    V(r, s0);
    for (let i = 1; i <= 16; i++) { const k = i / 16; V(r * Math.pow(1 - Math.pow(k, 1.7), 0.62), s0 + nL * k); }
  }
  const body = new THREE.LatheGeometry(P, 40).rotateX(-Math.PI / 2).translate(0, 0, len / 2);   // 车削轴 +Y → −Z（弹头朝前）
  add(body, mBody);
  if (nose === 'ir') { const d = add(new THREE.SphereGeometry(r * 0.88, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2).rotateX(-Math.PI / 2), mGlass); d.position.z = -len / 2 + r * 0.5; }
  // 喷管：尾部一圈深色的管口 + 里面更暗
  const noz = add(new THREE.CylinderGeometry(r * 0.5, r * 0.56, r * 0.5, 28, 1, true).rotateX(Math.PI / 2), mDark); noz.position.z = len / 2 + r * 0.1;
  const nozIn = add(new THREE.CircleGeometry(r * 0.48, 24), new THREE.MeshBasicMaterial({ color: 0x060606 })); nozIn.position.z = len / 2 - r * 0.05;
  // 色带：比弹体略粗一点点的薄圈
  for (const [at, w, c] of bands) {
    const b = add(new THREE.CylinderGeometry(r * 1.004, r * 1.004, len * w, 40, 1, true).rotateX(Math.PI / 2), new THREE.MeshStandardMaterial({ color: c, roughness: 0.45, metalness: 0.1 }));
    b.position.z = -len / 2 + len * at;
  }
  // 板（翼、舵）：形状在（翼展 x, 弦向 y）平面，拉出厚度后转成弦向朝 +Z（往后）、从弹体表面往外长
  const plate = (root, tip, span, sweep, th) => {
    const s = new THREE.Shape();
    s.moveTo(0, 0); s.lineTo(span, sweep); s.lineTo(span, sweep + tip); s.lineTo(0, root); s.lineTo(0, 0);
    const geo = new THREE.ExtrudeGeometry(s, { depth: th, bevelEnabled: false });
    geo.translate(r * 0.92, 0, -th / 2).rotateX(Math.PI / 2);
    return geo;
  };
  const ring = (geo, zLead, m, a0 = roll) => { for (let i = 0; i < 4; i++) { const f = add(geo, m); f.rotation.z = a0 + i * Math.PI / 2; f.position.z = -len / 2 + zLead; } };
  if (strake) { const [a, c, sp] = strake; ring(plate(len * c, len * c - sp * 2.4, sp, sp * 1.2, r * 0.08), len * a, mFin); }
  if (canard) { const [a, rc, tc, sp, sw] = canard; ring(plate(rc, tc, sp, sw, r * 0.1), len * a, mFin); }
  if (fins) { const [rc, tc, sp, sw] = fins; ring(plate(rc, tc, sp, sw, r * 0.12), len - rc - r * 0.35, mFin); }
  // 吊挂：弹体上方两个小块（挂在导轨上的那一面朝 +Y）
  if (lugs) for (const at of [0.36, 0.62]) { const l = add(new THREE.BoxGeometry(r * 0.35, r * 0.28, r * 0.9), mDark); l.position.set(0, r * 1.08, -len / 2 + len * at); }
  g.userData = { len, r };
  return g;
}
// 霹雳-10（侧弹舱的近距格斗弹）：3 米长 = 8.4 格、弹径 0.16 米；白弹体、玻璃导引头罩、贯通大半个弹身的长条弹翼、尾部切梢三角舵，战斗部黄色色带、发动机棕色色带
export const pl10 = () => missileModel({ len: 8.4, r: 0.224, nose: 'ir', strake: [0.22, 0.52, 0.3], fins: [1.05, 0.42, 0.62, 0.52], bands: [[0.2, 0.025, 0xc9a227], [0.42, 0.02, 0x7a5a32]], lugs: true });
// 红旗-9 一类的舰空导弹（055 垂发）：6.8 米 = 19 格；尖拱雷达罩、前翼、尾舵
export const hhq9 = () => missileModel({ len: 19, r: 0.95, nose: 'radar', canard: [0.2, 1.3, 0.55, 0.75, 0.6], fins: [3.0, 1.3, 1.7, 1.5], bands: [[0.32, 0.012, 0xb03a2e]], col: 0xe6e6e2, roll: 0 });
// 爱国者 PAC-2：5.3 米 = 14.8 格、弹径 0.41 米；白色雷达罩、四片大尾舵
export const pac2 = () => missileModel({ len: 14.8, r: 0.57, nose: 'radar', fins: [2.8, 1.1, 1.55, 1.6], col: 0xe2e2dc, roll: 0 });
// —— 霹雳-15：弹体、头锥、尾翼、弹体中段一圈深色（4 米长 = 11.2 格，弹径 0.2 米）；弹头朝 −Z ——
export function pl15() {
  const g = new THREE.Group();
  const body = new THREE.MeshStandardMaterial({ color: 0xc4c8cc, roughness: 0.45, metalness: 0.3, envMapIntensity: 0.4 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x3a3e42, roughness: 0.6, metalness: 0.2, envMapIntensity: 0.3 });
  const M = (geo, m) => { const x = new THREE.Mesh(geo, m); x.castShadow = true; g.add(x); return x; };
  M(new THREE.CylinderGeometry(0.29, 0.29, 9.6, 16).rotateX(Math.PI / 2), body).position.z = 0.4;
  M(new THREE.ConeGeometry(0.29, 1.6, 16).rotateX(-Math.PI / 2), body).position.z = -5.2;
  M(new THREE.CylinderGeometry(0.3, 0.3, 0.5, 16).rotateX(Math.PI / 2), dark).position.z = -1.5;
  for (let i = 0; i < 4; i++) {
    const f = M(new THREE.BoxGeometry(0.05, 0.95, 1.3), dark); f.position.set(0, 0, 4.6); f.rotation.z = i * Math.PI / 2 + Math.PI / 4; f.translateY(0.55);
  }
  return g;
}
// —— 歼-20 主弹舱：两扇门（铰链在外侧、往下翻）、门后的暗色舱井、吊架；照网页版的弹舱位置（门 4.3 米长、1.56 米宽）、机腹高 3.55 格 ——
export function j20Bay(A) {
  const Y = 3.5, X = 2.18, Z0 = -0.15, LEN = 12.1;
  const mDoor = new THREE.MeshStandardMaterial({ color: 0x5e6266, roughness: 0.55, metalness: 0.35, envMapIntensity: 0.35, side: THREE.DoubleSide });
  const mWell = new THREE.MeshStandardMaterial({ color: 0x08090a, roughness: 0.9, envMapIntensity: 0.05 });
  const doors = [];
  for (const s of [1, -1]) {
    const piv = new THREE.Group(); piv.position.set(s * X, Y, Z0); A.root.add(piv);
    const d = new THREE.Mesh(new THREE.BoxGeometry(X, 0.08, LEN), mDoor); d.position.set(-s * X / 2, -0.04, 0); d.castShadow = true; piv.add(d);
    doors.push({ piv, s });
  }
  const well = new THREE.Mesh(new THREE.BoxGeometry(2 * X - 0.05, 0.22, LEN - 0.1), mWell); well.position.set(0, Y + 0.02, Z0); A.root.add(well);
  const m = pl15(); A.root.add(m); m.position.set(0, Y - 0.38, Z0 - 0.3);
  const arms = [];
  for (const z of [-2.2, 1.8]) { const a = new THREE.Mesh(new THREE.BoxGeometry(0.16, 1, 0.16), mDoor); A.root.add(a); arms.push({ a, z }); }
  return {
    missile: m,
    // k 门开度 0–1，drop 吊架放下多少（格），attached 弹还挂在吊架上没有
    set(k, drop = 0, attached = true) {
      for (const d of doors) d.piv.rotation.z = d.s * 1.75 * k;
      well.visible = k > 0.02;
      for (const { a, z } of arms) { a.visible = attached && drop > 0.02; a.scale.y = Math.max(0.01, drop); a.position.set(0, Y - drop / 2, Z0 + z); }
      if (attached) { m.visible = k > 0.15; m.position.set(0, Y - 0.38 - drop, Z0 - 0.3); }
    },
  };
}
// —— 歼-20 侧弹舱（进气道下面、机身两侧）：一扇窄门（铰链在外沿、往下翻到竖直）、暗色舱井、把霹雳-10 放出舱外的导轨（导轨梁 + 两根连杆）——
//   位置照网页版 V3G_BAY 的侧弹舱：舱长 3.44 米、宽 0.35 米、比主弹舱高 0.83 米；换成格（× 2.8，机头朝 −Z）。s：哪一侧（+1 右、−1 左）
export function j20SideBay(A, s = 1, o = {}) {
  const Y = o.y ?? 5.82, XI = 3.42, XO = 4.40, Z0 = -0.48, LEN = 9.63, W = XO - XI;
  const mDoor = new THREE.MeshStandardMaterial({ color: 0x55595d, roughness: 0.5, metalness: 0.4, envMapIntensity: 0.4, side: THREE.DoubleSide });
  const mWell = new THREE.MeshStandardMaterial({ color: 0x0a0b0c, roughness: 0.9, envMapIntensity: 0.05 });
  const mRail = new THREE.MeshStandardMaterial({ color: 0x2c2f32, roughness: 0.45, metalness: 0.7, envMapIntensity: 0.4 });
  const piv = new THREE.Group(); piv.position.set(s * XO, Y, Z0); A.root.add(piv);
  const door = new THREE.Mesh(new THREE.BoxGeometry(W, 0.07, LEN), mDoor); door.position.set(-s * W / 2, -0.035, 0); door.castShadow = true; piv.add(door);
  // 门内侧的加强筋（门翻下来以后看得见）
  for (const dz of [-3.2, 0, 3.2]) { const r = new THREE.Mesh(new THREE.BoxGeometry(W * 0.9, 0.12, 0.1), mRail); r.position.set(-s * W / 2, 0.05, dz); piv.add(r); }
  const well = new THREE.Mesh(new THREE.BoxGeometry(W - 0.04, 0.8, LEN - 0.1), mWell); well.position.set(s * (XI + XO) / 2, Y + 0.41, Z0); A.root.add(well);
  const m = pl10(); A.root.add(m);
  const rail = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.15, 6.4), mRail); rail.castShadow = true; A.root.add(rail);
  const links = [-1.7, 1.5].map(dz => { const l = new THREE.Mesh(new THREE.BoxGeometry(0.13, 1, 0.2), mRail); l.castShadow = true; A.root.add(l); return { l, dz }; });
  // 弹的中心：收在舱里 → 放到舱外（门翻下来挡在外侧，导轨直着往下放，弹顶在门的下沿以下）
  const stow = new THREE.Vector3(s * 3.91, Y + 0.36, Z0 - 0.1), out = new THREE.Vector3(s * 3.98, Y - 1.3, Z0 - 0.1);
  const topY = Y + 0.72;
  const UP = new THREE.Vector3(0, 1, 0);
  return {
    missile: m, stow, out,
    // k 门开度 0–1、e 导轨放出去多少 0–1、attached 弹还在导轨上没有
    set(k, e, attached = true) {
      piv.rotation.z = s * 1.62 * k;
      well.visible = k > 0.02;
      const rp = stow.clone().lerp(out, e);
      const rTop = rp.clone().add(new THREE.Vector3(0, 0.224 + 0.11, 0));
      rail.position.copy(rTop); rail.visible = k > 0.25;
      for (const { l, dz } of links) {
        const a = new THREE.Vector3(stow.x, topY, Z0 + dz), b = new THREE.Vector3(rTop.x, rTop.y, Z0 + dz);
        const d = b.clone().sub(a), L = d.length();
        l.position.copy(a).add(b).multiplyScalar(0.5); l.scale.y = Math.max(0.02, L);
        l.quaternion.setFromUnitVectors(UP, L > 1e-4 ? d.multiplyScalar(1 / L) : UP);
        l.visible = k > 0.25;
      }
      if (attached) { m.visible = k > 0.08; m.position.copy(rp); m.quaternion.identity(); }
    },
  };
}
// —— 歼-20 的绿色电致发光编队灯带、精细的尾喷口 ——
//   灯带：网页版 V3G_PAINT.j20 的 glow 材质（Material.009 / .014 / .020 / .022 / .024），导出的 GLB 里自发光丢了，模型里只有几厘米宽，
//   所以除了材质自发光，还收集三角形中心（机体坐标）给镜头远的时候画发光点
//   尾喷口：原模型的喷口很粗糙；照涡扇-10 的收敛扩散喷口做一圈 16 片锯齿调节片、内壁、火焰稳定器（加力时发光）、涡轮锥
export function j20Extras(A) {
  const GLOW = ['Material.009', 'Material.014', 'Material.020', 'Material.022', 'Material.024'];
  A.root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(A.root.matrixWorld).invert();
  const raw = [];
  const mGlow = new THREE.MeshStandardMaterial({ color: 0x163a20, emissive: 0x3dff7a, emissiveIntensity: 2.4, roughness: 0.4 });
  A.root.traverse(o => {
    if (!o.isMesh || !o.material || !o.material.name || !GLOW.some(n => o.material.name.endsWith(n))) return;
    o.material = mGlow;
    const pos = o.geometry.attributes.position, idx = o.geometry.index;
    const M = new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld);
    const n = idx ? idx.count : pos.count, v = new THREE.Vector3();
    for (let i = 0; i < n; i += 3) {
      const c = new THREE.Vector3();
      for (let j = 0; j < 3; j++) c.add(v.fromBufferAttribute(pos, idx ? idx.getX(i + j) : i + j));
      raw.push(c.multiplyScalar(1 / 3).applyMatrix4(M));
    }
  });
  // 合并相近的点（1.2 格以内算一个）
  const glowPts = [];
  for (const p of raw) if (!glowPts.some(q => q.distanceToSquared(p) < 1.44)) glowPts.push(p);
  // 尾喷口
  const mOut = new THREE.MeshStandardMaterial({ color: 0x5f574e, roughness: 0.38, metalness: 0.85, envMapIntensity: 0.7, side: THREE.DoubleSide });
  const mIn = new THREE.MeshStandardMaterial({ color: 0x3b342d, roughness: 0.5, metalness: 0.7, envMapIntensity: 0.4, side: THREE.BackSide });
  const mHot = new THREE.MeshStandardMaterial({ color: 0x16120f, roughness: 0.7, metalness: 0.4, emissive: 0xff6a22, emissiveIntensity: 0 });
  const nozzles = [];
  for (const n of A.noz) {
    const r = n.r * 1.04, g = new THREE.Group(); g.position.copy(n.p); A.root.add(g);
    const N = 16, P = [];
    for (let i = 0; i < N; i++) {
      const a0 = (i + 0.04) / N * Math.PI * 2, a1 = (i + 0.96) / N * Math.PI * 2, am = (a0 + a1) / 2;
      const ring = (a, rr, z) => [Math.cos(a) * rr, Math.sin(a) * rr, z];
      const r0a = ring(a0, r * 1.13, -2.3 * r), r0b = ring(a1, r * 1.13, -2.3 * r), e0 = ring(a0, r, 0), e1 = ring(a1, r, 0), tip = ring(am, r * 0.97, 0.36 * r);
      P.push(...r0a, ...e0, ...r0b, ...r0b, ...e0, ...e1, ...e0, ...tip, ...e1);
    }
    const pg = new THREE.BufferGeometry(); pg.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); pg.computeVertexNormals();
    const pet = new THREE.Mesh(pg, mOut); pet.castShadow = true; g.add(pet);
    const inner = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.94, r * 0.86, 2.2 * r, 32, 1, true).rotateX(Math.PI / 2), mIn); inner.position.z = -1.1 * r; g.add(inner);
    const face = new THREE.Mesh(new THREE.CircleGeometry(r * 0.88, 32), new THREE.MeshStandardMaterial({ color: 0x0b0a09, roughness: 0.9 })); face.position.z = -2.15 * r; g.add(face);
    for (const [rr, w] of [[0.62, 0.05], [0.36, 0.045]]) { const t = new THREE.Mesh(new THREE.TorusGeometry(r * rr, r * w, 8, 40), mHot); t.position.z = -1.95 * r; g.add(t); }
    for (let i = 0; i < 8; i++) { const b = new THREE.Mesh(new THREE.BoxGeometry(r * 0.05, r * 0.66, r * 0.05), mHot); b.position.set(Math.cos(i / 8 * Math.PI * 2) * r * 0.5, Math.sin(i / 8 * Math.PI * 2) * r * 0.5, -1.96 * r); b.rotation.z = i / 8 * Math.PI * 2 + Math.PI / 2; g.add(b); }
    const cone = new THREE.Mesh(new THREE.ConeGeometry(r * 0.22, r * 0.5, 20).rotateX(Math.PI / 2), mHot); cone.position.z = -1.85 * r; g.add(cone);
    nozzles.push(g);
  }
  return { glowPts, nozzles, heat(k) { mHot.emissiveIntensity = 2.5 * k; } };
}
// —— 飞机解体：按三角形中心的位置把模型切成几块（机头、左翼、右翼、尾段、中段），每块单独一组、原点在自己的中心（机体坐标）——
export function breakApart(A, cuts = { nose: -10, tail: 12, wing: 7 }) {
  A.root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(A.root.matrixWorld).invert();
  const names = ['nose', 'wingL', 'wingR', 'tail', 'mid'];
  const pick = c => c.z < cuts.nose ? 0 : (c.x < -cuts.wing ? 1 : (c.x > cuts.wing ? 2 : (c.z > cuts.tail ? 3 : 4)));
  const parts = names.map(() => []), sum = names.map(() => new THREE.Vector3()), cnt = names.map(() => 0);
  const meshes = [];
  A.root.traverse(o => { if (o.isMesh && o.geometry && o.geometry.attributes.position && !o.material.isShaderMaterial) meshes.push(o); });
  const v = new THREE.Vector3();
  for (const mesh of meshes) {
    const geo = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry;
    const M = new THREE.Matrix4().multiplyMatrices(inv, mesh.matrixWorld);
    const pos = geo.attributes.position, per = names.map(() => []);
    for (let i = 0; i + 2 < pos.count; i += 3) {
      const c = new THREE.Vector3();
      for (let j = 0; j < 3; j++) c.add(v.fromBufferAttribute(pos, i + j));
      c.multiplyScalar(1 / 3).applyMatrix4(M);
      const k = pick(c); per[k].push(i); sum[k].add(c); cnt[k]++;
    }
    per.forEach((tris, k) => {
      if (!tris.length) return;
      const g2 = new THREE.BufferGeometry();
      for (const name of Object.keys(geo.attributes)) {
        const src = geo.attributes[name], isz = src.itemSize, arr = new Float32Array(tris.length * 3 * isz);
        let o = 0;
        for (const i of tris) for (let j = 0; j < 3; j++) { const q = i + j; arr[o++] = src.getX(q); if (isz > 1) arr[o++] = src.getY(q); if (isz > 2) arr[o++] = src.getZ(q); if (isz > 3) arr[o++] = src.getW(q); }
        g2.setAttribute(name, new THREE.BufferAttribute(arr, isz));
      }
      g2.applyMatrix4(M);
      parts[k].push({ geo: g2, mat: mesh.material });
    });
  }
  return names.map((nm, k) => {
    const c = cnt[k] ? sum[k].multiplyScalar(1 / cnt[k]) : new THREE.Vector3();
    const grp = new THREE.Group();
    for (const { geo, mat } of parts[k]) { geo.translate(-c.x, -c.y, -c.z); const m = new THREE.Mesh(geo, mat); m.castShadow = true; grp.add(m); }
    return { name: nm, group: grp, c, n: cnt[k] };
  }).filter(p => p.n > 0);
}
// —— 99A 去掉车上的国徽：徽章画在车体贴图里（炮塔顶两个、首上一个），用旁边的迷彩盖掉（只改片子里的，游戏模型不动）——
const EMB = { ztz99: [[812, 117, 24, 0, 52], [945, 117, 24, 0, 54], [851, 370, 20, -46, 0]] };   // 圆心 x, y、半径、取样偏移 dx, dy（贴图 1024²）
function eraseEmblems(key, model) {
  const L = EMB[key];
  if (!L) return;
  model.traverse(o => {
    if (!o.isMesh || !o.material || !o.material.map || o.material.userData.noEmblem) return;
    const tex = o.material.map, img = tex.image;
    if (!img || !img.width || img.width < 1000) return;
    const cv = document.createElement('canvas'); cv.width = img.width; cv.height = img.height;
    const g = cv.getContext('2d'); g.drawImage(img, 0, 0);
    const k = img.width / 1024;
    for (const [x, y, r, dx, dy] of L) {
      const R = r * k, X = x * k, Y = y * k;
      const p = document.createElement('canvas'); p.width = p.height = Math.ceil(R * 2);
      const pg = p.getContext('2d');
      pg.drawImage(cv, X + dx * k - R, Y + dy * k - R, R * 2, R * 2, 0, 0, R * 2, R * 2);
      pg.globalCompositeOperation = 'destination-in';
      const grd = pg.createRadialGradient(R, R, R * 0.55, R, R, R);
      grd.addColorStop(0, 'rgba(0,0,0,1)'); grd.addColorStop(1, 'rgba(0,0,0,0)');
      pg.fillStyle = grd; pg.fillRect(0, 0, R * 2, R * 2);
      g.drawImage(p, X - R, Y - R);
    }
    const t2 = new THREE.CanvasTexture(cv);
    t2.flipY = tex.flipY; t2.colorSpace = tex.colorSpace; t2.wrapS = tex.wrapS; t2.wrapT = tex.wrapT; t2.anisotropy = 4;
    o.material.map = t2; o.material.userData.noEmblem = true; o.material.needsUpdate = true;
  });
}
// —— 爱国者：发射箱口外露着的四个弹头和发射箱是同一块网格，切成四块单独的网格（发射了哪一枚就藏哪一枚）——
//   发射箱轴线、口的位置是离线量的（tools 里按顶点主成分：中心 C、轴 AX，沿轴 6.9 格以外是弹头）；四块按两个侧向坐标的正负分
export function patriotNoses(V) {
  const C = new THREE.Vector3(0.09, 13.58, 5.04), AX = new THREE.Vector3(0.005, 0.561, -0.828).normalize();
  const e1 = new THREE.Vector3().crossVectors(AX, new THREE.Vector3(0, 1, 0)).normalize(), e2 = new THREE.Vector3().crossVectors(e1, AX);
  V.root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(V.root.matrixWorld).invert();
  const out = [[], [], [], []], centers = [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()], cnt = [0, 0, 0, 0];
  const meshes = [];
  V.recoil.traverse(o => { if (o.isMesh) meshes.push(o); });
  for (const mesh of meshes) {
    mesh.geometry = mesh.geometry.clone();   // 克隆出来的模型和缓存共用网格，先复制一份再切
    const geo = mesh.geometry, pos = geo.attributes.position;
    const M = new THREE.Matrix4().multiplyMatrices(inv, mesh.matrixWorld);
    const idx = geo.index ? geo.index.array : [...Array(pos.count).keys()];
    const rest = [], parts = [[], [], [], []];
    const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3();
    for (let i = 0; i < idx.length; i += 3) {
      a.fromBufferAttribute(pos, idx[i]).applyMatrix4(M); b.fromBufferAttribute(pos, idx[i + 1]).applyMatrix4(M); c.fromBufferAttribute(pos, idx[i + 2]).applyMatrix4(M);
      const g = a.clone().add(b).add(c).multiplyScalar(1 / 3).sub(C);
      if (g.dot(AX) > 6.9) {
        const k = (g.dot(e1) > 0 ? 2 : 0) + (g.dot(e2) > 0.47 ? 1 : 0);
        parts[k].push(idx[i], idx[i + 1], idx[i + 2]);
        centers[k].add(g.add(C)); cnt[k]++;
      } else rest.push(idx[i], idx[i + 1], idx[i + 2]);
    }
    if (rest.length === idx.length) continue;
    geo.setIndex(rest);
    parts.forEach((p, k) => {
      if (!p.length) return;
      const g2 = geo.clone(); g2.setIndex(p);
      const n = new THREE.Mesh(g2, mesh.material); n.castShadow = true;
      mesh.parent.add(n); n.position.copy(mesh.position); n.quaternion.copy(mesh.quaternion); n.scale.copy(mesh.scale);
      out[k].push(n);
    });
  }
  return { axis: AX, center: C, noses: out.map((ms, k) => ({ meshes: ms, p: cnt[k] ? centers[k].multiplyScalar(1 / cnt[k]) : C.clone(), hide() { for (const m of ms) m.visible = false; } })) };
}
