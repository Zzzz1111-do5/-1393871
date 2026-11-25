// 第三版微电影的工具：会转的机炮、折叠的机翼、福建舰、车内 / 座舱、第一人称 M4（带改枪配件）、画面上叠的平显 / 瞄准镜 / 游戏界面、雨、闪电
import * as THREE from 'three';
import { V3, clamp, lerp, smooth, sat, rng, DEG, ease } from '../lib.js';
import { loadGLB, aircraft } from '../models.js';
import { buildInterior } from './interior.js';
import { heightAt } from '../bigmap.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

export const DATA = '/data';

// —— 飞机：在 models.js 的 aircraft() 上再挂几个会动的部件 ——
//   Gun（机头炮塔：方位 + 俯仰）、GunY（阿帕奇的炮塔座：只转方位）、FoldL / FoldR（歼-15T 折叠的外翼）、TipL / TipR（平尾外段）
export async function plane(key, env) {
  const A = await aircraft(key, env.REPO);
  const M = A.M, piv = {};
  const mk = (name, p) => { const g = new THREE.Group(); g.position.fromArray(p); A.root.add(g); piv[name] = g; return g; };
  if (M.gun) mk('Gun', M.gun.p);
  if (M.guny) mk('GunY', M.guny.p);
  if (M.fold && M.fold.Fold) { mk('FoldR', [M.fold.Fold.x, M.fold.Fold.y, 0]); mk('FoldL', [-M.fold.Fold.x, M.fold.Fold.y, 0]); }
  if (M.fold && M.fold.Tip) { mk('TipR', [M.fold.Tip.x, M.fold.Tip.y, 0]); mk('TipL', [-M.fold.Tip.x, M.fold.Tip.y, 0]); }
  A.root.updateMatrixWorld(true);
  const list = [];
  A.root.traverse(o => { const m = /__(Gun|GunY|FoldL|FoldR|TipL|TipR)_\d+$/.exec(o.name); if (m && piv[m[1]] && !list.some(([x]) => x === o)) list.push([o, m[1]]); });
  for (const [o, g] of list) piv[g].attach(o);
  A.piv = piv;
  // 机炮：yaw 往左为正（绕 +Y），pitch 抬头为正
  A.gunAim = (yaw, pitch) => {
    if (piv.GunY) piv.GunY.rotation.set(0, yaw, 0);
    if (piv.Gun) { piv.Gun.rotation.set(0, 0, 0); piv.Gun.rotateY(yaw); piv.Gun.rotateX(pitch); }
  };
  A.gunMuzzle = (len = 6) => piv.Gun ? piv.Gun.localToWorld(V3(0, 0, -len)) : A.root.localToWorld(V3(0, 0, -A.M.len / 2));
  A.gunDir = () => piv.Gun ? V3(0, 0, -1).transformDirection(piv.Gun.matrixWorld) : V3(0, 0, -1).transformDirection(A.root.matrixWorld);
  // 折翼：0 展开 … 1 折起（右翼绕 +Z 往上翻过竖直）
  A.fold = k => {
    const a = ((M.fold && M.fold.Fold && M.fold.Fold.A) || 2) * k, b = ((M.fold && M.fold.Tip && M.fold.Tip.A) || 1.57) * k;
    if (piv.FoldR) piv.FoldR.rotation.set(0, 0, a);
    if (piv.FoldL) piv.FoldL.rotation.set(0, 0, -a);
    if (piv.TipR) piv.TipR.rotation.set(0, 0, b);
    if (piv.TipL) piv.TipL.rotation.set(0, 0, -b);
  };
  return A;
}

// —— 福建舰：原模型（不带贴图，每块一种颜色）；游戏里甲板全长 620 格，片子里按真舰 316 米、1 米 = 2.8 格放大 ——
export const CV_K = 316 * 2.8 / 620;
export async function fujian(env) {
  const src = await loadGLB(`${env.REPO}/models/ship/fujian.glb`);
  const model = src.clone(true);
  model.traverse(o => {
    if (!o.isMesh) return;
    o.castShadow = o.receiveShadow = true;
    const one = m => { m = m.clone(); m.envMapIntensity = 0.18; m.roughness = Math.max(0.6, m.roughness ?? 0.6); m.metalness = Math.min(0.35, m.metalness ?? 0); return m; };
    o.material = Array.isArray(o.material) ? o.material.map(one) : one(o.material);
  });
  model.scale.setScalar(CV_K);
  const root = new THREE.Group(); root.name = 'ship:fujian';
  root.add(model);
  // 甲板上的位置（游戏坐标：X 右舷、−Z 船头，原点水线、甲板中间）→ 片子里
  const deck = (x, z, lift = 0) => root.localToWorld(V3(x * CV_K, 30.5 * CV_K + lift, z * CV_K));
  return { root, k: CV_K, deckY: 30.5 * CV_K, len: 620 * CV_K, deck };
}

// —— 车内、座舱：tools/mock 导出的 interior_<型号>.json ——
const intCache = {};
export async function interior(env, name, opt = {}) {
  if (!intCache[name]) intCache[name] = fetch(`${DATA}/int/interior_${name}.json`).then(r => r.json());
  return buildInterior(await intCache[name], { grime: env.T.grime, ...opt });
}

// —— 第一人称 M4（游戏里的 fps_m4.glb + 改枪配件原模型，位置照 tools/mock/gunmount.lua 导出的）——
//   枪的坐标：+Z 枪口、+Y 上，单位同游戏第一人称视角模型；手臂照游戏里的 Roblox 方块胳膊（圆角、迷彩袖子、手套）
let mountCache = null;
export async function fpsGun(env, build = 'socom_holo_rvg_p40_peq', team = 'atk') {
  if (!mountCache) mountCache = fetch(`${DATA}/gunmount.json`).then(r => r.json());
  const D = await mountCache;
  const B = D.builds.find(b => b.name === build) || D.builds[0];
  const g = new THREE.Group();
  const m4 = (c) => new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
  const put = (src, mat, only, glass, into) => src.traverse(o => {
    if (!o.isMesh || (only && !only(o.name))) return;
    let mt = o.material;
    if (glass && glass.some(p => o.name.endsWith('__' + p) || (o.parent && o.parent.name.endsWith('__' + p)))) {
      mt = o.material.clone(); mt.transparent = true; mt.opacity = 0.12; mt.depthWrite = false;
    } else if (mt) { mt = mt.clone(); if ('envMapIntensity' in mt) mt.envMapIntensity = 0.5; }
    const m = new THREE.Mesh(o.geometry, mt);
    m.matrixAutoUpdate = false;
    m.matrix.copy(mat).multiply(o.matrixWorld);
    m.castShadow = true;
    (into || g).add(m);
  });
  const gun = await loadGLB(`${env.REPO}/models/fps_m4.glb`);
  gun.updateMatrixWorld(true);
  const parts = { bolt: new THREE.Group(), mag: new THREE.Group() };
  g.add(parts.bolt, parts.mag);
  for (const p of D.m4) {
    if (B.skipMag && (p.node === 'FPS_M4_Mag1' || p.node === 'FPS_M4_Mag2')) continue;
    if (p.piece === 'mag2') continue;
    const into = p.piece === 'bolt' ? parts.bolt : (p.piece === 'mag1' ? parts.mag : g);
    put(gun, m4(p.cf), n => n === p.node || n.startsWith(p.node + '_') || n.replace(/_\d+$/, '') === p.node, null, into);
  }
  const att = {};
  for (const a of B.att) {
    const src = await loadGLB(`${env.REPO}/models/optics/${a.model}.glb`);
    src.updateMatrixWorld(true);
    const sub = new THREE.Group();
    put(src, m4(a.cf), null, a.glass, sub);
    if (a.riser) {
      const r = new THREE.Mesh(new THREE.BoxGeometry(0.058, a.riser, 0.1), new THREE.MeshStandardMaterial({ color: 0x222224, roughness: 0.5 }));
      r.matrixAutoUpdate = false; r.matrix.copy(m4(a.cf)).multiply(new THREE.Matrix4().makeTranslation(0, -a.riser / 2, 0.01));
      sub.add(r);
    }
    g.add(sub);
    att[a.slot] = { g: sub, a };
  }
  const sight = B.att.find(a => a.eye);
  const muzzle = (B.att.find(a => a.mz) || {}).mz || [0, 0.05, 1.45];
  return { root: g, build: B, att, parts, sight, muzzle: V3(...muzzle), iron: D.sightIron };
}
// 第一人称的两条胳膊（右手握把、左手护木），挂在枪上（枪的坐标）
export function fpsArms(team = 'atk') {
  const sleeve = new THREE.MeshStandardMaterial({ color: team === 'atk' ? 0x6e6a4c : 0x7d7259, roughness: 0.95, envMapIntensity: 0.1 });
  const glove = new THREE.MeshStandardMaterial({ color: 0x1d1d1c, roughness: 0.8, envMapIntensity: 0.1 });
  const g = new THREE.Group();
  const arm = (hand, elbow, gr) => {
    const L = hand.distanceTo(elbow);
    const fore = new THREE.Mesh(new RoundedBoxGeometry(0.16, 0.16, L, 3, 0.05), sleeve);
    fore.position.copy(hand).lerp(elbow, 0.5); fore.lookAt(elbow);
    const h = new THREE.Mesh(new RoundedBoxGeometry(0.14, 0.12, 0.16, 3, 0.04), glove);
    h.position.copy(hand); h.lookAt(elbow); if (gr) h.rotateX(gr);
    g.add(fore, h);
  };
  arm(V3(0.01, -0.13, 0.12), V3(0.32, -0.42, -0.65), 0.3);    // 右手：握把
  arm(V3(-0.02, -0.06, 0.72), V3(-0.42, -0.42, 0.05), -0.2);  // 左手：护木
  return g;
}

// —— 雨：镜头四周一片斜着落的雨丝（光带），按时间走、每帧可重复渲 ——
export function rain(fx, camF, opt = {}) {
  const R = rng(opt.seed || 77), N = opt.n || 900, box = opt.box || 60, sp = opt.speed || 140;
  const drops = [];
  for (let i = 0; i < N; i++) drops.push({ x: R.range(-box, box), z: R.range(-box, box), ph: R(), l: R.range(2.2, 4.5) });
  const wind = opt.wind || V3(-18, 0, 6);
  fx.add((t, f) => {
    const c = camF();
    for (const d of drops) {
      const y = ((d.ph * box * 2 - t * sp) % (box * 2) + box * 2) % (box * 2) - box;
      const p = V3(c.x + d.x + wind.x * (y / sp), c.y + y, c.z + d.z + wind.z * (y / sp));
      const dir = V3(wind.x, -sp, wind.z).normalize();
      f.addStreak(p, p.clone().addScaledVector(dir, d.l), 0.035, new THREE.Color(0.55, 0.6, 0.7), opt.bright ?? 0.55, 0.3, 0.0005);
    }
  });
}
// —— 闪电：一道分叉的电光（光带）+ 全场一亮 ——
export function lightning(fx, from, to, t0, seed = 1) {
  const R = rng(seed);
  const segs = [];
  const build = (a, b, depth) => {
    const n = 9, pts = [a.clone()];
    for (let i = 1; i < n; i++) { const p = a.clone().lerp(b, i / n); const off = a.distanceTo(b) * 0.06; p.add(V3(R.range(-off, off), R.range(-off * 0.3, off * 0.3), R.range(-off, off))); pts.push(p); }
    pts.push(b.clone());
    for (let i = 0; i < pts.length - 1; i++) segs.push([pts[i], pts[i + 1], depth]);
    if (depth < 2) for (let k = 0; k < 2; k++) { const s = pts[2 + Math.floor(R() * 5)]; build(s, s.clone().add(V3(R.range(-1, 1), -R.range(0.4, 1), R.range(-1, 1)).multiplyScalar(a.distanceTo(b) * 0.35)), depth + 1); }
  };
  build(from, to, 0);
  fx.add((t, f) => {
    const u = t - t0;
    if (u < 0 || u > 0.55) return;
    const k = (u < 0.08 ? 1 : (u < 0.16 ? 0.25 : (u < 0.24 ? 0.85 : Math.max(0, 1 - (u - 0.24) / 0.3) * 0.5)));
    for (const [a, b, d] of segs) f.addStreak(a, b, d ? 1.2 : 3.2, new THREE.Color(0.85, 0.9, 1), 14 * k / (1 + d * 1.5), 0.05, 0.0012);
    f.addLight(to.clone().lerp(from, 0.3), new THREE.Color(0.7, 0.8, 1), 160 * k, 5000);
  });
  return u => { const x = u - t0; return x < 0 || x > 0.55 ? 0 : (x < 0.08 ? 1 : (x < 0.16 ? 0.2 : (x < 0.24 ? 0.8 : Math.max(0, 1 - (x - 0.24) / 0.3) * 0.4))); };
}

// —— 画面上叠的东西（画在输出画布上，宽银幕画面里）——
// 平显：绿色的俯仰梯、航向带、速度高度、中间的飞机符号；lock 一个锁定框（画面坐标 0–1）
export function drawHud(g, W, H, ah, o = {}) {
  const top = (H - ah) / 2, cx = W / 2, cy = top + ah * 0.48, u = ah / 1080;
  const col = o.color || 'rgba(120,255,160,0.92)';
  g.save();
  g.strokeStyle = col; g.fillStyle = col; g.lineWidth = Math.max(1.5, 2.2 * u);
  g.shadowColor = 'rgba(80,255,140,0.7)'; g.shadowBlur = 8 * u;
  g.font = `600 ${Math.round(22 * u)}px "Noto Sans SC", monospace`;
  g.textAlign = 'center'; g.textBaseline = 'middle';
  const roll = o.roll || 0, pitch = o.pitch || 0;
  // 俯仰梯（随坡度转）
  g.save(); g.translate(cx, cy); g.rotate(-roll);
  for (let d = -20; d <= 20; d += 5) {
    if (d === 0) continue;
    const y = (d - pitch) * 18 * u;
    if (Math.abs(y) > ah * 0.36) continue;
    const w = 110 * u, gap = 46 * u;
    g.setLineDash(d < 0 ? [10 * u, 8 * u] : []);
    g.beginPath(); g.moveTo(-gap - w, y); g.lineTo(-gap, y); g.lineTo(-gap, y + (d > 0 ? 12 : -12) * u); g.moveTo(gap + w, y); g.lineTo(gap, y); g.lineTo(gap, y + (d > 0 ? 12 : -12) * u); g.stroke();
    g.setLineDash([]);
    g.fillText(String(Math.abs(d)), -gap - w - 26 * u, y); g.fillText(String(Math.abs(d)), gap + w + 26 * u, y);
  }
  // 地平线
  const hy = -pitch * 18 * u;
  g.beginPath(); g.moveTo(-420 * u, hy); g.lineTo(-60 * u, hy); g.moveTo(60 * u, hy); g.lineTo(420 * u, hy); g.stroke();
  g.restore();
  // 飞机符号（W）
  g.beginPath(); g.moveTo(cx - 44 * u, cy); g.lineTo(cx - 18 * u, cy); g.lineTo(cx - 9 * u, cy + 12 * u); g.lineTo(cx, cy); g.lineTo(cx + 9 * u, cy + 12 * u); g.lineTo(cx + 18 * u, cy); g.lineTo(cx + 44 * u, cy); g.stroke();
  // 航向带
  const hdg = o.hdg ?? 0, ty = top + ah * 0.12;
  for (let d = -30; d <= 30; d += 5) {
    const v = Math.round(hdg / 5) * 5 + d, x = cx + (v - hdg) * 9 * u;
    const big = ((v % 10) + 10) % 10 === 0;
    g.beginPath(); g.moveTo(x, ty); g.lineTo(x, ty + (big ? 16 : 9) * u); g.stroke();
    if (big) g.fillText(String(((v % 360) + 360) % 360 / 10 | 0).padStart(2, '0'), x, ty - 14 * u);
  }
  g.beginPath(); g.moveTo(cx, ty + 22 * u); g.lineTo(cx - 8 * u, ty + 34 * u); g.lineTo(cx + 8 * u, ty + 34 * u); g.closePath(); g.stroke();
  // 速度、高度框
  const box = (x, txt) => { g.strokeRect(x - 52 * u, cy - 20 * u, 104 * u, 40 * u); g.fillText(txt, x, cy); };
  box(cx - 330 * u, String(Math.round(o.spd ?? 1180))); box(cx + 330 * u, String(Math.round(o.alt ?? 4800)));
  g.font = `600 ${Math.round(17 * u)}px "Noto Sans SC", monospace`;
  g.fillText('M ' + (o.mach ?? 1.12).toFixed(2), cx - 330 * u, cy + 40 * u); g.fillText('G ' + (o.gload ?? 1.0).toFixed(1), cx - 330 * u, cy + 64 * u);
  if (o.weapon) g.fillText(o.weapon, cx + 330 * u, cy + 52 * u);
  // 锁定框
  if (o.lock) {
    const [lx, ly] = o.lock, s = (o.lockS || 0.07) * ah, X = lx * W, Y = ly * H;
    g.strokeStyle = o.locked ? 'rgba(255,90,70,0.95)' : col; g.shadowColor = o.locked ? 'rgba(255,60,40,0.8)' : g.shadowColor;
    g.beginPath(); g.arc(X, Y, s, 0, Math.PI * 2); g.stroke();
    if (o.locked) { g.beginPath(); g.moveTo(X, Y - s * 0.4); g.lineTo(X + s * 0.4, Y); g.lineTo(X, Y + s * 0.4); g.lineTo(X - s * 0.4, Y); g.closePath(); g.stroke(); }
    g.fillStyle = g.strokeStyle; g.font = `700 ${Math.round(20 * u)}px "Noto Sans SC"`;
    g.fillText(o.locked ? '锁定  SHOOT' : '搜索', X, Y - s - 18 * u);
  }
  g.restore();
}
// 瞄准镜（狙击镜 ATACR 7-35×56 F1）：圆出瞳、外面全黑；第一焦平面的密位分划（细十字、每密位刻度、粗柱、数字）；边上一圈暗角和一点色散
export function drawScope(g, W, H, ah, o = {}) {
  const top = (H - ah) / 2, cx = W / 2 + (o.dx || 0) * ah, cy = top + ah / 2 + (o.dy || 0) * ah, r = ah * 0.46;
  g.save();
  // 出瞳外面全黑
  g.fillStyle = '#000';
  g.beginPath(); g.rect(0, top, W, ah); g.arc(cx, cy, r, 0, Math.PI * 2, true); g.fill('evenodd');
  // 边缘渐暗、月牙
  const grd = g.createRadialGradient(cx, cy, r * 0.72, cx, cy, r);
  grd.addColorStop(0, 'rgba(0,0,0,0)'); grd.addColorStop(0.8, 'rgba(0,0,0,0.45)'); grd.addColorStop(1, 'rgba(0,0,0,0.95)');
  g.fillStyle = grd; g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2); g.fill();
  // 分划
  const mil = (o.milPx || 0.012) * ah;   // 每密位多少像素（按倍率）
  g.strokeStyle = 'rgba(8,8,8,0.95)'; g.fillStyle = 'rgba(8,8,8,0.95)';
  g.lineWidth = Math.max(1, ah * 0.0012);
  g.beginPath(); g.moveTo(cx - r, cy); g.lineTo(cx + r, cy); g.moveTo(cx, cy - r); g.lineTo(cx, cy + r); g.stroke();
  for (let i = 1; i <= 10; i++) {
    const L = (i % 5 === 0 ? 0.011 : 0.006) * ah;
    for (const s of [-1, 1]) {
      g.beginPath(); g.moveTo(cx + s * i * mil, cy - L); g.lineTo(cx + s * i * mil, cy + L); g.moveTo(cx - L, cy + s * i * mil); g.lineTo(cx + L, cy + s * i * mil); g.stroke();
    }
  }
  // 10 密位外的粗柱
  const thick = ah * 0.009;
  g.fillRect(cx + 10 * mil, cy - thick / 2, r, thick); g.fillRect(cx - 10 * mil - r, cy - thick / 2, r, thick); g.fillRect(cx - thick / 2, cy + 10 * mil, thick, r);
  g.font = `600 ${Math.round(ah * 0.016)}px "Noto Sans SC"`; g.textAlign = 'center'; g.textBaseline = 'middle';
  for (const k of [2, 4, 6, 8]) { g.fillText(String(k), cx + k * mil, cy - 0.022 * ah); g.fillText(String(k), cx - k * mil, cy - 0.022 * ah); }
  // 中心一点微红（夜间照明）
  g.fillStyle = 'rgba(255,40,30,0.9)'; g.beginPath(); g.arc(cx, cy, Math.max(1.5, ah * 0.0022), 0, Math.PI * 2); g.fill();
  // 读数（镜外的黑边上）
  g.fillStyle = 'rgba(200,205,200,0.85)'; g.font = `500 ${Math.round(ah * 0.018)}px "Noto Sans SC"`; g.textAlign = 'left';
  g.fillText(o.label || '×21  ATACR 7-35×56 F1', cx + r * 0.78, cy + r * 0.92);
  if (o.range) { g.textAlign = 'right'; g.fillText(o.range, cx - r * 0.78, cy + r * 0.92); }
  g.restore();
}
// 第一人称的游戏界面（同游戏：右下弹药、准星、击杀提示「+100 击杀」、命中的叉）
export function drawFpsHud(g, W, H, ah, o = {}) {
  const top = (H - ah) / 2, u = ah / 1080;
  g.save();
  g.textBaseline = 'middle';
  // 弹药
  g.fillStyle = 'rgba(235,240,230,0.92)'; g.textAlign = 'right';
  g.font = `700 ${Math.round(46 * u)}px "Noto Sans SC"`; g.fillText(String(o.ammo ?? 30), W * 0.93, top + ah * 0.9);
  g.font = `500 ${Math.round(24 * u)}px "Noto Sans SC"`; g.fillStyle = 'rgba(200,205,200,0.75)'; g.fillText('/ ' + (o.reserve ?? 150), W * 0.965, top + ah * 0.905);
  g.font = `500 ${Math.round(18 * u)}px "Noto Sans SC"`; g.fillText(o.weapon || 'M4A1 · 全息 · 消音', W * 0.965, top + ah * 0.86);
  // 命中叉
  if (o.hit > 0) {
    const cx = W / 2, cy = top + ah / 2, s = 16 * u, gap = 7 * u;
    g.strokeStyle = o.kill ? `rgba(255,70,50,${o.hit})` : `rgba(255,255,255,${o.hit})`; g.lineWidth = 3 * u;
    g.beginPath();
    for (const [sx, sy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) { g.moveTo(cx + sx * gap, cy + sy * gap); g.lineTo(cx + sx * (gap + s), cy + sy * (gap + s)); }
    g.stroke();
  }
  // 击杀提示
  if (o.kill > 0) {
    g.globalAlpha = o.kill; g.textAlign = 'left';
    g.fillStyle = '#ffd36a'; g.font = `800 ${Math.round(30 * u)}px "Noto Sans SC"`; g.fillText('+100', W * 0.52, top + ah * 0.46);
    g.fillStyle = 'rgba(240,240,235,0.95)'; g.font = `600 ${Math.round(20 * u)}px "Noto Sans SC"`; g.fillText('击杀  ' + (o.killName || '蓝方 · 步枪兵'), W * 0.52, top + ah * 0.5);
    g.globalAlpha = 1;
  }
  g.restore();
}
// 据点占领条（同游戏顶栏的样式）
export function drawCapture(g, W, H, ah, o = {}) {
  const top = (H - ah) / 2, u = ah / 1080, cx = W / 2, y = top + ah * 0.16;
  g.save();
  g.globalAlpha = o.a ?? 1;
  const w = 380 * u, h = 10 * u;
  g.fillStyle = 'rgba(0,0,0,0.45)'; g.fillRect(cx - w / 2, y, w, h);
  g.fillStyle = o.done ? '#e2493a' : '#e2493a'; g.fillRect(cx - w / 2, y, w * clamp(o.k ?? 0, 0, 1), h);
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillStyle = 'rgba(240,240,235,0.95)'; g.font = `700 ${Math.round(26 * u)}px "Noto Sans SC"`;
  g.fillText(o.done ? `据点 ${o.id || 'D'} 已占领` : `正在占领据点 ${o.id || 'D'}`, cx, y - 26 * u);
  g.font = `500 ${Math.round(17 * u)}px "Noto Sans SC"`; g.fillStyle = 'rgba(200,205,200,0.8)';
  g.fillText(o.done ? '交战区前移 · 时间 +3:00' : '我方 6　敌方 1', cx, y + 30 * u);
  g.restore();
}
