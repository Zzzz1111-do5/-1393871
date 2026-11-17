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
// opaque：整架模型的材质按不透明画（直-10 的原模型整架设成了半透明，网页版 V3G_MATFIX 也是这么改的）
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

// —— 地面载具：炮塔、炮管、车轮各挂一个转轴 ——
export async function vehicle(key, base) {
  const M = META.ImportedMeta.m[key];
  const src = await loadGLB(`${base}/models/veh/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.25);
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
  const V = {
    root, M, tur, gun, recoil, wheels, len: M.len,
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
  const M = META.ImportedAir.m[key];
  const src = await loadGLB(`${base}/models/air/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.35, key === 'z10w');
  const root = new THREE.Group(); root.name = 'air:' + key;
  root.add(model);
  root.updateMatrixWorld(true);
  const rot = {};
  for (const k of ['rotor', 'rotor2', 'trotor']) if (M[k]) { const g = new THREE.Group(); g.position.fromArray(M[k].p); g.userData.axis = new THREE.Vector3().fromArray(M[k].a).normalize(); root.add(g); rot[k] = g; }
  const gear = [];
  for (const o of collect(model, 'A_' + key)) {
    const b = blockOf(o.name, 'A_' + key), part = M.parts[b];
    const g = part ? part.g : 'Body';
    if (key === 'z10w' && !/Rotor/.test(g)) o.traverse(x => { if (x.isMesh) { x.material = x.material.clone(); x.material.color.multiplyScalar(1.8); } });   // 原贴图很暗，夜里只剩一团黑
    if (/Rotor/.test(g) && key === 'z10w') o.traverse(x => { if (x.isMesh) { x.material = x.material.clone(); x.material.transparent = true; x.material.opacity = 0.4; x.material.depthWrite = false; x.castShadow = false; } });   // 原模型的桨盘是「转起来的虚影」
    if (g === 'Rotor' && rot.rotor) rot.rotor.attach(o);
    else if (g === 'Rotor2' && rot.rotor2) rot.rotor2.attach(o);
    else if (g === 'TRotor' && rot.trotor) rot.trotor.attach(o);
    else if (g === 'Gear') gear.push(o);
  }
  return {
    root, M, rot, gear, noz: (M.noz || []).map(a => ({ p: new THREE.Vector3(a[0], a[1], a[2]), r: a[3] })),
    spin(t, rpm = 1) {
      for (const [k, g] of Object.entries(rot)) g.quaternion.setFromAxisAngle(g.userData.axis, t * (k === 'trotor' ? 31 : 13) * rpm);
    },
    gearDown(on) { for (const o of gear) o.visible = on; },
  };
}

// —— 舰艇：游戏里按 1 米 = 1.68 格，片子里按真实比例（和车一样 2.8 格）放大 ——
export const SHIP_K = 2.8 / 1.68;
export async function ship(key, base) {
  const M = META.ImportedShip.m[key];
  const src = await loadGLB(`${base}/models/ship/${key}.glb`);
  const model = src.clone(true);
  prepMats(model, 0.2);
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
export const STAND = { gun: { p: [0.4, 0.75, -0.8], r: [-0.55, 0.2, 0.15] }, headX: 0.05 };

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
