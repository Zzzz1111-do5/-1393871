// 分镜：《黎明之前》——夜里的一场登岛战，两边各有各的人。每个镜头 setup 搭好要用的东西，update(t) 摆好这一刻的镜头、模型、特效，返回后期参数
//   events：给配乐、音效的提示（t 镜头里的秒，k 种类，v 大小 / 声像）
import * as THREE from 'three';
import { V3, keys, ease, easeIn, easeOut, easeIO, smooth, lerp, shake, rng, DEG, fbm1, clamp, sat } from './lib.js';
import { seaY, seaNormal, SEA } from './world.js';
import { vehicle, aircraft, ship, soldier, pose, runPose, AIM, KNEEL, CROUCH, STAND, landingCraft, hovercraft, loadGLB, META } from './models.js';
import { explosion, muzzle, burst, flare, flarePos, fire, missile, spray, beamMesh, flameMesh } from './fx.js';
import { fadeIO } from './titles.js';

const NIGHT_FOG = new THREE.Color(0x0e1420);
const RED_T = new THREE.Color(1, 0.32, 0.12), GREEN_T = new THREE.Color(0.45, 1, 0.35);
const SERIF = '"Noto Serif SC"', SANS = '"Noto Sans SC"';
// 地图上的点
const BUNKER_A = V3(290, 24, -771), BUNKER_B = V3(412, 18, -812), COASTAL = V3(1185, 29, -805), LIGHTHOUSE = V3(2665, 97, -270);

export const SHOTS = [
  { id: 'S01', dur: 5.5, setup: shotSea },
  { id: 'S02', dur: 4.5, setup: shotWatch },
  { id: 'S03', dur: 3.5, setup: shotNvg },
  { id: 'S04', dur: 5, setup: shotFleet },
  { id: 'S05', dur: 4, setup: shotDeck },
  { id: 'S06', dur: 4, setup: shotBoat },
  { id: 'S07', dur: 3.5, setup: shotVls },
  { id: 'S08', dur: 3, setup: shotCat },
  { id: 'S09', dur: 4.5, setup: shotBarrage },
  { id: 'S10', dur: 4.5, setup: shotLcac },
  { id: 'S11', dur: 3.5, setup: shotMg },
  { id: 'S12', dur: 5, setup: shotAssault },
  { id: 'S13', dur: 4.5, setup: shotTank },
  { id: 'S14', dur: 3.5, setup: shotAbrams },
  { id: 'S15', dur: 4.5, setup: shotAir },
  { id: 'S16', dur: 3.5, setup: shotHeli },
  { id: 'S17', dur: 3, setup: shotPatriot },
  { id: 'S18', dur: 8, setup: shotDawn },
  { id: 'S19', dur: 6, setup: shotTitle },
  { id: 'S20', dur: 7.5, setup: shotFeatures },
  { id: 'S21', dur: 5.5, setup: shotEnd },
];
let T0 = 0;
for (const s of SHOTS) { s.t0 = T0; T0 += s.dur; }
export const TOTAL = T0;

export async function setupShot(S, env) {
  const added = [];
  const add = o => { env.scene.add(o); added.push(o); return o; };
  SEA.amp = 1;
  env.fx.wind.set(6, 0, -2);
  env.worldVisible(true);
  const sh = await S.setup(env, add);
  sh.dur = S.dur; sh.t0 = S.t0;
  const d0 = sh.dispose;
  sh.dispose = () => { for (const o of added) env.scene.remove(o); if (d0) d0(); };
  return sh;
}

// —— 小工具 ——
function cam(env, pos, look, fov) {
  const c = env.camera;
  c.position.copy(pos);
  c.up.set(0, 1, 0);
  c.lookAt(look);
  if (fov) { c.fov = fov; c.updateProjectionMatrix(); }
}
// 船跟着浪：位置、航向（0 = 朝北 −Z），返回海面高度
function onWaves(obj, x, z, heading, t, lift = 0, k = 1) {
  const y = seaY(x, z, t) * k + lift;
  const n = seaNormal(x, z, t);
  obj.position.set(x, y, z);
  const q = new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), n.clone().lerp(V3(0, 1, 0), 1 - k * 0.6).normalize());
  obj.quaternion.copy(q).multiply(new THREE.Quaternion().setFromAxisAngle(V3(0, 1, 0), heading));
  obj.updateMatrixWorld(true);
  return y;
}
function onGround(env, obj, x, z, heading, lift = 0) {
  const gy = env.groundY(x, z);
  const a = env.groundY(x, z - 4), b = env.groundY(x, z + 4), l = env.groundY(x - 4, z), r = env.groundY(x + 4, z);
  obj.position.set(x, gy + lift, z);
  obj.rotation.set(0, 0, 0);
  obj.rotateY(heading);
  obj.rotateX(Math.atan2(a - b, 8));
  obj.rotateZ(Math.atan2(l - r, 8) * -1);
  obj.updateMatrixWorld(true);
  return gy;
}
const headingTo = (from, to) => Math.atan2(-(to.x - from.x), -(to.z - from.z));   // 0 = 朝 −Z
async function rifle(env) { return loadGLB(`${env.REPO}/models/fps_m4.glb`); }
async function squad(env, team, n, seed, opt = {}) {
  const R = rng(seed), g = await rifle(env);
  const out = [];
  for (let i = 0; i < n; i++) out.push(soldier(team, { rifle: g, skin: Math.floor(R() * 5), nvg: opt.nvg ?? 1, nvgGlow: opt.glow ?? 0, fabric: env.T.grime }));
  return out;
}
// 灯塔：转动的光柱
function lighthouseBeam(add) {
  const b = beamMesh(2600, 2.0 * DEG, new THREE.Color(1, 0.92, 0.78), 1.1);
  b.position.copy(LIGHTHOUSE);
  add(b);
  return t => { b.rotation.set(0, t * 0.55 + 1.2, 0); b.rotateX(-2.5 * DEG); };
}
// 船的航行灯（055 等）：舷灯左红右绿、桅顶白——登记成特效（每帧画完模型、矩阵更新了才算位置）
function navLights(fx, S) {
  const M = S.M, k = S.k, root = S.root;
  const side = M.side ? V3(...M.side).multiplyScalar(k) : V3(10, 20, -30), top = M.top ? V3(...M.top).multiplyScalar(k) : V3(0, 60, -20);
  fx.add((t, f) => {
    if (!root.visible) return;
    const L = (v, c, i) => f.addGlow(root.localToWorld(v.clone()), 1.6, c, i, 1, 0.0016);
    L(V3(-side.x, side.y, side.z), new THREE.Color(1, 0.1, 0.05), 7);
    L(V3(side.x, side.y, side.z), new THREE.Color(0.1, 1, 0.3), 7);
    L(top, new THREE.Color(1, 1, 0.9), 8);
    if (M.stern) L(V3(...M.stern).multiplyScalar(k).add(V3(0, 3, 0)), new THREE.Color(1, 1, 0.9), 5);
  });
}
// 喷气机的加力尾焰（挂在模型上）：发光的锥 + 喷口里的亮光 + 照亮周围的灯；kf() 给这一刻的加力程度
function afterburners(A, fx, kf) {
  const fl = [];
  for (const n of A.noz) {
    const m = flameMesh(n.r * 0.9, n.r * 9);
    m.position.copy(n.p);
    A.root.add(m);
    fl.push(m);
  }
  fx.add((t, f) => {
    const k = kf(t);
    for (const m of fl) { m.material.uniforms.uK.value = k; m.material.uniforms.uT.value = t; m.scale.set(1, 1, 0.6 + 0.4 * k); m.visible = k > 0.01; }
    if (k < 0.01) return;
    for (const n of A.noz) {
      const p = A.root.localToWorld(n.p.clone().add(V3(0, 0, n.r * 0.6)));
      f.addGlow(p, n.r * 3.2, new THREE.Color(1, 0.62, 0.32), 6 * k, 1, 0.0012);
      f.addLight(A.root.localToWorld(n.p.clone().add(V3(0, 0, n.r * 6))), new THREE.Color(1, 0.55, 0.25), 1.6 * k, 120);
    }
  });
}
function spot(add, pos, target, color, intensity, angle = 50, dist = 400) {
  const s = new THREE.SpotLight(color, intensity, dist, angle * DEG, 0.6, 2);
  s.position.copy(pos); s.target.position.copy(target);
  add(s); add(s.target);
  return s;
}
function point(add, pos, color, intensity, dist = 100) {
  const l = new THREE.PointLight(color, intensity, dist, 2);
  l.position.copy(pos);
  add(l);
  return l;
}

// ———————————— 序幕 ————————————
// S01 海：贴着海面往群岛滑，月光路在左前方，右边灯塔岛的光柱扫过
async function shotSea(env, add) {
  const beam = lighthouseBeam(add);
  return {
    update(t) {
      const u = t / 5.5;
      SEA.amp = 1.15;
      cam(env, V3(lerp(-300, -272, u), 4.0 + Math.sin(t * 0.9) * 0.35, lerp(1150, 1092, u)), V3(7, 108, 204), 32);
      env.camera.rotateZ(Math.sin(t * 0.6) * 0.7 * DEG);
      beam(t + 1);
      return { fade: 1 - smooth(0.2, 2.2, t), exposure: 1.2, shadowR: 600, grain: 0.012, bloom: 1.0 };
    },
    titles: t => [
      { text: '凌晨 02:14', x: 0.5, y: 0.76, size: 0.034, font: SERIF, weight: 700, spacing: 0.25, a: fadeIO(t, 1.4, 5.3, 0.8, 0.6) },
      { text: '群岛海域 · 距离登陆还有 18 分钟', x: 0.5, y: 0.81, size: 0.018, font: SANS, spacing: 0.3, a: fadeIO(t, 2.0, 5.3, 0.8, 0.6), color: '#b8c2d0' },
    ],
    events: [{ t: 0, k: 'ambience' }, { t: 0.4, k: 'drone' }, { t: 3.2, k: 'horn' }],
  };
}
// S02 守岛的人：碉堡外的美军哨兵，逆光的轮廓，夜视仪的绿光
async function shotWatch(env, add) {
  const [s] = await squad(env, 'def', 1, 7, { glow: 2.2 });
  add(s.root);
  const p = V3(302, 0, -758);
  onGround(env, s.root, p.x, p.z, Math.PI);
  const head = () => s.root.localToWorld(V3(0, 5.0, 0));
  // 补光：身后（北边）冷色轮廓光、右前方远处火光的暖色、夜视仪照在脸上的一点绿
  spot(add, s.root.localToWorld(V3(-6, 14, 22)), s.root.localToWorld(V3(0, 4, 0)), 0xb4c8ff, 2600, 18, 120);
  point(add, s.root.localToWorld(V3(9, 3, -10)), 0xff9a50, 45, 60);
  point(add, s.root.localToWorld(V3(0, 5.2, -1.0)), 0x40ff70, 2.2, 4);
  const beam = lighthouseBeam(add);
  return {
    update(t) {
      const u = t / 4.5;
      pose(s, { ...STAND, headY: Math.sin(t * 0.35) * 0.18 - 0.05, headX: 0.04, gun: { p: [0.35, 0.75, -0.8], r: [-0.6, 0.15, 0.2] } });
      s.chest.scale.setScalar(1 + Math.sin(t * 1.6) * 0.008);
      s.root.updateMatrixWorld(true);
      const eye = head();
      cam(env, s.root.localToWorld(V3(lerp(1.8, 1.1, ease(u)), lerp(4.7, 4.9, u), lerp(-9, -6, ease(u)))), eye.clone().add(V3(0, -0.15, 0)), 26);
      beam(t + 6);
      return { exposure: 1.15, shadowAt: p, shadowR: 60, dof: { focus: env.camera.position.distanceTo(eye), range: 3, max: 1.0 }, bloom: 1.1 };
    },
    titles: t => [{ text: '美国军队 · 蓝滩守备分队', x: 0.06, y: 0.84, size: 0.017, font: SANS, align: 'left', spacing: 0.2, a: fadeIO(t, 0.8, 4.2, 0.6, 0.5), color: '#9fb4d8' }],
    events: [{ t: 0, k: 'wind' }, { t: 0.5, k: 'radioStatic' }, { t: 0, k: 'pulse' }],
  };
}
// S03 夜视仪里：海平线上有东西
async function shotNvg(env, add) {
  const fleet = await ship('t055', env.REPO);
  add(fleet.root);
  const f2 = await ship('t054a', env.REPO);
  add(f2.root);
  navLights(env.fx, fleet); navLights(env.fx, f2);
  env.fx.add((t, f) => { const fl = t > 2.4 ? Math.exp(-(t - 2.4) * 3) : 0; if (fl > 0.01) f.addGlow(V3(150, 40, 1640), 40, new THREE.Color(1, 0.8, 0.5), 20 * fl, 1, 0); });
  return {
    update(t) {
      onWaves(fleet.root, 120, 1650, 0.15, t, 0, 0.3);
      onWaves(f2.root, -520, 1500, -0.1, t, 0, 0.3);
      const yaw = lerp(-0.08, 0.06, ease(t / 3.5));
      const from = V3(300, env.groundY(300, -762) + 5.6, -762);
      cam(env, from, from.clone().add(V3(Math.sin(yaw) * 100, -1.2, 100)), 9);
      shake(env.camera, t, 0.25, 2, 3);
      return { nvg: 1, exposure: 1.4, grain: 0.035, vignette: 0.9, bloom: 1.3, shadowR: 300 };
    },
    events: [{ t: 0, k: 'nvgWhine' }, { t: 2.4, k: 'distant' }],
  };
}
// S04 舰队：贴着海面看 055 迎面压过来，船头的浪
async function shotFleet(env, add) {
  const { fx } = env;
  const S = await ship('t055', env.REPO);
  add(S.root);
  navLights(fx, S);
  const half = S.len / 2;
  const pos = t => V3(260, 0, 1500 - t * 14);
  fx.add(spray({ at: (b, q) => S.root.localToWorld(V3(q.x * 14, 2, -half * 0.95 + Math.abs(q.z) * 30)).setY(1.5), rate: 70, size: 10, up: 10, life: 1.8, alpha: 0.35 }));
  return {
    update(t) {
      const p = pos(t);
      onWaves(S.root, p.x, p.z, 0, t, 0, 0.35);
      const camP = S.root.localToWorld(V3(-95 + t * 2, 0, -half - 70 + t * 6)).setY(5 + Math.sin(t * 0.8) * 0.5);
      cam(env, camP, S.root.localToWorld(V3(0, 32, -half * 0.35)), 30);
      env.camera.rotateZ(1.5 * DEG + Math.sin(t * 0.7) * 0.5 * DEG);
      return { exposure: 1.2, shadowAt: S.root.position, shadowR: 450, bloom: 1.0 };
    },
    titles: t => [{ text: '中国人民解放军 · 登陆编队', x: 0.06, y: 0.84, size: 0.017, font: SANS, align: 'left', spacing: 0.2, a: fadeIO(t, 0.8, 4.7, 0.6, 0.5), color: '#d8b8a0' }],
    events: [{ t: 0, k: 'shipRumble' }],
  };
}
// 航母甲板的两盏探照灯
function deckLights(add) {
  spot(add, V3(-388, 52, 2163), V3(-410, 31, 2120), 0xfff0d8, 5200, 42, 260);
  spot(add, V3(-388, 52, 2312), V3(-410, 31, 2240), 0xfff0d8, 4200, 42, 260);
}
// S05 航母甲板：歼-15 挂在弹射器上，尾喷口加力
async function shotDeck(env, add) {
  const { fx } = env;
  const A = await aircraft('j15', env.REPO);
  add(A.root);
  const p0 = V3(-402, 31, 2120);
  A.root.position.copy(p0);
  const kf = t => 0.35 + 0.65 * smooth(1.2, 2.6, t);
  afterburners(A, fx, kf);
  deckLights(add);
  const crew = await squad(env, 'atk', 2, 21, { nvg: 0 });
  crew.forEach((c, i) => { add(c.root); c.root.position.set(-384 + i * 5, 31, 2104 + i * 16); c.root.rotation.y = 0.9 + i * 2; });
  fx.add(spray({ at: (b, q) => p0.clone().add(V3(q.x * 2, 0.5, -24 + q.z * 30)), rate: 30, size: 6, up: 3, life: 2.4, alpha: 0.2, tint: [1.2, 1.2, 1.25] }));
  return {
    update(t) {
      const k = kf(t);
      A.root.position.copy(p0).add(V3(0, Math.sin(t * 40) * 0.02 * k, 0));
      A.root.updateMatrixWorld(true);
      crew.forEach((c, i) => pose(c, { ...STAND, gun: { p: [0.2, -0.5, -0.4], r: [-1.4, 0, 0] }, headY: i ? -0.3 : 0.5 }));
      cam(env, V3(-422 + t * 0.5, 34.0, 2178 - t * 1.6), A.root.localToWorld(V3(2, 6, -14)), 32);
      shake(env.camera, t, 0.12 + 0.3 * k, 6, 9);
      return { exposure: 1.15, shadowAt: p0, shadowR: 120, dof: { focus: 60, range: 40, max: 0.5 }, bloom: 1.2 };
    },
    events: [{ t: 0, k: 'deckAmb' }, { t: 1.2, k: 'jetSpool' }],
  };
}
// S06 登陆艇里：一排排蹲着的兵，红色的舱灯，前面那个把夜视仪翻下来
async function shotBoat(env, add) {
  const { fx } = env;
  const L = landingCraft(env.T);
  add(L.root);
  const sq = await squad(env, 'atk', 10, 33, { nvg: 0 });
  sq.forEach(s => L.root.add(s.root));
  sq.forEach((s, i) => { const row = i % 2, col = Math.floor(i / 2); s.root.position.set(row ? 3.2 : -3.2, -0.6, -11 + col * 5.2); s.nvgDown(i === 9 ? 0 : (i % 3 === 0 ? 1 : 0)); });
  const red = new THREE.PointLight(0xff2a14, 140, 40, 2); red.position.set(0, 6.5, 10.5); L.root.add(red);
  const red2 = new THREE.PointLight(0xff2a14, 70, 30, 2); red2.position.set(0, 5.5, -8); L.root.add(red2);
  const pos = t => V3(330, 0, 260 - t * 22);
  fx.add(spray({ at: (b, q) => L.root.localToWorld(V3(q.x * 8, 5 + q.z, -18)), rate: 40, size: 6, up: 10, life: 1.4, alpha: 0.45 }));
  return {
    update(t) {
      const p = pos(t);
      SEA.amp = 1.3;
      onWaves(L.root, p.x, p.z, 0, t, 1.8, 1);
      sq.forEach((s, i) => {
        pose(s, { ...CROUCH, headX: 0.15 + Math.sin(t * 1.3 + i) * 0.05, headY: Math.sin(t * 0.7 + i * 2) * 0.12 });
        s.root.position.y = -0.6 + Math.sin(t * 7 + i) * 0.03;
      });
      sq[9].nvgDown(smooth(1.4, 2.0, t));
      L.root.updateMatrixWorld(true);
      cam(env, L.root.localToWorld(V3(4.4, 6.6, 12.8)), L.root.localToWorld(V3(-0.8, 3.4, -12)), 44);
      shake(env.camera, t, 0.8, 2.2, 5);
      return { exposure: 1.2, shadowAt: p, shadowR: 40, dof: { focus: 8, range: 6, max: 0.6 }, bloom: 1.0 };
    },
    titles: t => [{ text: '「各单位注意——H 时到。」', x: 0.5, y: 0.82, size: 0.022, font: SERIF, spacing: 0.12, a: fadeIO(t, 0.6, 3.6, 0.4, 0.4), color: '#e8e2d6' }],
    events: [{ t: 0, k: 'boatEngine' }, { t: 0.5, k: 'radio' }, { t: 1.4, k: 'nvgClick' }, { t: 3.4, k: 'riser' }],
  };
}
// S07 垂发：055 前甲板的导弹出筒
async function shotVls(env, add) {
  const { fx } = env;
  const S = await ship('t055', env.REPO);
  add(S.root);
  navLights(fx, S);
  const half = S.len / 2;
  const at = V3(260, 0, 1380);
  const cells = [V3(-3, 10.5, -72), V3(3, 10.5, -66)].map(v => v.multiplyScalar(S.k));
  const launches = [0.55, 2.0];
  launches.forEach((tl, i) => {
    const base = () => S.root.localToWorld(cells[i].clone());
    const path = tau => { const u = Math.max(0, tau - tl); const b = base(); const tilt = smooth(0.6, 2.4, u); return b.add(V3(-tilt * u * u * 25, u * 60 + u * u * 70, -tilt * u * u * 40)); };
    fx.add(missile({ path, t0: tl, t1: tl + 6, size: 2.2, smokeLife: 6 }));
    fx.add((t, f) => {   // 出筒那一下：甲板上翻起一大团烟、闪光
      const u = t - tl;
      if (u < 0 || u > 5) return;
      const b = base();
      if (u < 0.5) f.addGlow(b.clone().add(V3(0, 6, 0)), 40, new THREE.Color(1, 0.75, 0.45), 8 * (1 - u / 0.5), 1, 0);
      f.addLight(b.clone().add(V3(0, 14, 0)), new THREE.Color(1, 0.62, 0.32), 40 * Math.exp(-u * 1.2), 300);
      for (let j = 0; j < 14; j++) {
        const a = j / 14 * Math.PI * 2, r = 8 + 40 * (1 - Math.exp(-u * 1.5)) * (0.6 + 0.4 * Math.sin(j * 3.1));
        f.sprite('puff', b.clone().add(V3(Math.cos(a) * r, 4 + u * 3 + Math.sin(j) * 2, Math.sin(a) * r)).addScaledVector(f.wind, u * 0.8), 18 + u * 8, 8 + u * 8, 0.7 * (1 - u / 5) * smooth(0, 0.1, u), 0, [0.85, 0.82, 0.8], j);
      }
    });
  });
  return {
    update(t) {
      onWaves(S.root, at.x, at.z - t * 6, 0, t, 0, 0.35);
      const look = S.root.localToWorld(V3(0, 40 + smooth(0.6, 3.0, t) * 90, -half * 0.3));
      cam(env, S.root.localToWorld(V3(-175 + t * 2, 0, -half * 0.62)).setY(8), look, 34);
      shake(env.camera, t, t > 0.55 ? 0.6 * Math.exp(-(t - 0.55) * 1.5) + 0.12 : 0.12, 3, 11);
      return { exposure: 1.15, shadowAt: S.root.position, shadowR: 400, bloom: 1.3 };
    },
    events: [{ t: 0.55, k: 'launch' }, { t: 0.55, k: 'hit' }, { t: 2.0, k: 'launch' }],
  };
}
// S08 弹射起飞：歼-15 从镜头边冲过去
async function shotCat(env, add) {
  const { fx } = env;
  const A = await aircraft('j15', env.REPO);
  add(A.root);
  afterburners(A, fx, () => 1);
  deckLights(add);
  const p0 = V3(-402, 31, 2120);
  const pos = t => { const u = Math.max(0, t - 0.35); const z = p0.z - 0.5 * 130 * Math.min(u, 1.6) ** 2 - Math.max(0, u - 1.6) * 208; const lift = z < 1945 ? (1945 - z) * 0.12 : 0; return V3(p0.x, p0.y + lift, z); };
  fx.add(spray({ at: (b, q) => V3(p0.x + q.x * 3, 31.5, pos(b).z + 22 + q.z * 6), t0: 0.35, rate: 50, size: 7, up: 4, life: 1.8, alpha: 0.28, tint: [1.2, 1.2, 1.25] }));
  return {
    update(t) {
      const p = pos(t);
      A.root.position.copy(p);
      A.root.rotation.set(Math.max(0, (p.y - 31) * 0.004), 0, 0);
      A.root.updateMatrixWorld(true);
      cam(env, V3(-380, 34.5, 2010), p.clone().add(V3(0, 7, -6)), 34);
      shake(env.camera, t, smooth(0.3, 1.2, t) * 0.7 * (1 - smooth(1.8, 2.8, t)) + 0.1, 8, 4);
      return { exposure: 1.15, shadowAt: V3(-400, 31, 2060), shadowR: 140, bloom: 1.3 };
    },
    events: [{ t: 0.35, k: 'catapult' }, { t: 0.35, k: 'jetPass' }],
  };
}

// ———————————— 突击 ————————————
// S09 火力准备：高处看海岸，导弹从头顶飞过去，岸防炮、高炮一个个炸开，守军打照明弹
async function shotBarrage(env, add) {
  const { fx, groundY } = env;
  const targets = [COASTAL.clone(), V3(677, 25, -867), V3(589, 31, -1328), V3(969, 31, -1328), V3(-42, 39, -787)];
  const times = [0.9, 1.5, 2.2, 2.6, 3.2];
  targets.forEach((tg, i) => {
    tg.y = groundY(tg.x, tg.z) + 2;
    const t1 = times[i], fly = 2.2;
    const from = V3(300 + i * 60, 150, 600);
    const path = tau => { const u = clamp((tau - (t1 - fly)) / fly, 0, 1); const p = from.clone().lerp(tg, u); p.y += Math.sin(u * Math.PI) * 120; return p; };
    fx.add(missile({ path, t0: t1 - fly, t1, size: 1.3, smokeLife: 3 }));
    fx.add(explosion({ p: tg, t0: t1, s: 34 + i * 4, seed: 40 + i, debris: 24 }));
    fx.add(fire({ p: tg.clone(), s: 10, t0: t1 + 0.4, seed: 50 + i }));
  });
  [[260, 1.4], [420, 2.3], [140, 3.0]].forEach(([x, t0], i) => fx.add(flare({ p0: V3(x, 230 + i * 30, -720 + i * 40), t0, seed: 60 + i })));
  return {
    update(t) {
      cam(env, V3(lerp(420, 400, t / 4.5), lerp(170, 160, t / 4.5), lerp(-170, -200, t / 4.5)), V3(520, 30, -900), 42);
      shake(env.camera, t, 0.15, 1.5, 2);
      return { exposure: 1.15, shadowAt: V3(500, 0, -900), shadowR: 800, bloom: 1.2 };
    },
    events: [{ t: 0, k: 'incoming' }, ...times.map((t, i) => ({ t, k: 'bigboom', v: 0.7 + i * 0.05 })), { t: 1.4, k: 'flarePop' }],
  };
}
// S10 气垫艇冲滩：甲板上一辆 99A，浪花、迎面飞来的曳光
async function shotLcac(env, add) {
  const { fx } = env;
  const H = hovercraft(env.T);
  add(H.root);
  const tank = await vehicle('ztz99', env.REPO);
  H.root.add(tank.root);
  tank.root.position.set(0, 0.8, 2);
  const L2 = landingCraft(env.T); add(L2.root);
  const L3 = landingCraft(env.T); add(L3.root);
  const pos = t => V3(360, 0, -330 - t * 58);
  fx.add(spray({ at: (b, q) => { const p = pos(b); return V3(p.x + q.x * 15, 1, p.z + 6 + q.z * 22); }, rate: 90, size: 9, up: 7, life: 1.4, alpha: 0.22, tint: [1.0, 1.08, 1.2] }));
  fx.add(spray({ at: (b, q) => { const p = pos(b); return V3(p.x + q.x * 10, 2, p.z + 30 + q.z * 6); }, rate: 40, size: 13, up: 3, life: 2.0, alpha: 0.18, tint: [1.0, 1.08, 1.2] }));
  const R = rng(9);
  for (let i = 0; i < 4; i++) {
    const src = V3(290 + i * 40, 24, -780);
    fx.add(burst({ from: src, dir: () => pos(1.5).add(V3(R.range(-60, 60), 6, R.range(-60, 60))).sub(src).normalize(), t0: 0.2 + i * 0.4, t1: 4.5, rate: 7, speed: 1100, color: RED_T, spread: 0.02, seed: 70 + i, every: 1, flash: 'mg', maxD: 900 }));
  }
  [[330, 0.0, 270], [470, 1.2, 240]].forEach(([x, t0, y], i) => fx.add(flare({ p0: V3(x, y, -700), t0: t0 - 3, seed: 80 + i })));
  return {
    update(t) {
      const p = pos(t);
      SEA.amp = 1.1;
      onWaves(H.root, p.x, p.z, 0, t, 2.6, 0.4);
      H.spin(t);
      onWaves(L2.root, 250, -280 - t * 40, 0.05, t, 1.8);
      onWaves(L3.root, 470, -230 - t * 42, -0.04, t, 1.8);
      tank.aim(0, 0.02);
      cam(env, V3(p.x + 52, 6 + Math.sin(t * 2) * 0.5, p.z - 36), p.clone().add(V3(-2, 6, 4)), 34);
      shake(env.camera, t, 0.6, 4, 6);
      return { exposure: 1.2, shadowAt: p, shadowR: 120, bloom: 1.2 };
    },
    events: [{ t: 0, k: 'hover' }, { t: 0.3, k: 'whizz' }, { t: 1.6, k: 'whizz' }, { t: 2.9, k: 'whizz' }],
  };
}
// S11 碉堡机枪：守军的肩后，红色曳光扫向海面，照明弹下的登陆艇
async function shotMg(env, add) {
  const { fx, groundY } = env;
  const [s] = await squad(env, 'def', 1, 91, { nvg: 0.2 });
  add(s.root);
  onGround(env, s.root, 306, -770, Math.PI + 0.12);
  const L1 = landingCraft(env.T); add(L1.root);
  const L2 = landingCraft(env.T); add(L2.root);
  const H = hovercraft(env.T); add(H.root);
  const slit = V3(291, 25.6, -764);
  fx.add(burst({ from: slit, dir: t => V3(0.15 + Math.sin(t * 0.8) * 0.12, -0.05, 1).normalize(), t0: 0.15, t1: 3.5, rate: 13, speed: 1200, color: RED_T, spread: 0.01, seed: 101, every: 1, flash: 'mg', maxD: 700, width: 0.7 }));
  const rifleT = [0.6, 0.85, 1.2, 1.9, 2.15, 2.8];
  rifleT.forEach((tt, i) => fx.add(muzzle({ p: () => s.gunPiv.localToWorld(V3(0, 0.06, -1.05)), dir: () => V3(0, 0, -1).transformDirection(s.gunPiv.matrixWorld), t0: tt, kind: 'rifle', seed: 110 + i })));
  [[330, -2, 250], [250, 0.8, 230]].forEach(([x, t0, y], i) => fx.add(flare({ p0: V3(x, y, -600), t0, seed: 120 + i })));
  [[1.3, 300, -470], [2.6, 360, -500]].forEach(([t0, x, z], i) => fx.add(explosion({ p: V3(x, 0, z), t0, s: 16, seed: 130 + i, water: true, debris: 0, ember: 0, dust: false })));
  return {
    update(t) {
      onWaves(L1.root, 300, -420 - t * 30, 0.05, t, 1.8);
      onWaves(L2.root, 370, -380 - t * 28, -0.05, t, 1.8);
      onWaves(H.root, 230, -330 - t * 50, 0.1, t, 2.6, 0.4); H.spin(t);
      const recoil = rifleT.reduce((a, tt) => a + (t > tt && t < tt + 0.15 ? (1 - (t - tt) / 0.15) : 0), 0);
      pose(s, { ...AIM, gun: { p: [0.45, 1.12, -0.85 + recoil * 0.15], r: [-0.05 - recoil * 0.06, 0.35, 0] } });
      const cp = s.root.localToWorld(V3(-3.2, 6.6, 7.5));
      cam(env, cp, V3(286, -6, -520), 38);
      shake(env.camera, t, 0.35, 5, 8);
      return { exposure: 1.15, shadowAt: V3(300, 20, -765), shadowR: 70, dof: { focus: 160, range: 160, max: 0.4 }, bloom: 1.25 };
    },
    events: [{ t: 0.15, k: 'mgStart' }, { t: 3.5, k: 'mgStop' }, ...rifleT.map(t => ({ t, k: 'rifle', v: 0.6 })), { t: 1.3, k: 'splash' }, { t: 2.6, k: 'splash' }],
  };
}
// S12 抢滩：从登陆艇后面看，跳板放下，兵冲上沙滩，两边的曳光交织
async function shotAssault(env, add) {
  const { fx, groundY } = env;
  const L1 = landingCraft(env.T); add(L1.root);
  const L2 = landingCraft(env.T); add(L2.root);
  const b1 = V3(306, 0, -664), b2 = V3(352, 0, -672);
  const sq = await squad(env, 'atk', 12, 141);
  sq.forEach(s => add(s.root));
  const R = rng(142);
  const runners = sq.map((s, i) => {
    const boat = i < 6 ? b1 : b2;
    const start = boat.clone().add(V3(R.range(-4, 4), 0, -16 - R.range(0, 8)));
    const dir = V3(R.range(-0.25, 0.25), 0, -1).normalize();
    return { s, start, dir, t0: 1.0 + (i % 6) * 0.28 + R.range(0, 0.2), sp: R.range(15, 19), ph: R() };
  });
  fx.add(burst({ from: BUNKER_A.clone().add(V3(1, 1.5, 6)), dir: t => V3(0.25 + Math.sin(t * 1.3) * 0.12, -0.12, 1).normalize(), t0: 0, t1: 5, rate: 11, speed: 1100, color: RED_T, spread: 0.015, seed: 150, flash: 'mg', maxD: 700 }));
  fx.add(burst({ from: BUNKER_B.clone().add(V3(-2, 1.5, 6)), dir: t => V3(-0.45 + Math.sin(t) * 0.1, -0.1, 1).normalize(), t0: 0.4, t1: 5, rate: 9, speed: 1100, color: RED_T, spread: 0.02, seed: 151, flash: 'mg', maxD: 700 }));
  for (let i = 0; i < 5; i++) {
    const from = V3(300 + i * 14, 4, -684 - i * 6);
    fx.add(burst({ from, dir: V3(-0.1 + i * 0.05, 0.1, -1).normalize(), t0: 1.6 + i * 0.5, t1: 5, rate: 4, speed: 900, color: GREEN_T, spread: 0.03, seed: 160 + i, flash: 'rifle', maxD: 500, width: 0.45, bright: 4 }));
  }
  [[1.8, 330, -728], [3.1, 372, -712], [4.2, 290, -706]].forEach(([t0, x, z], i) => fx.add(explosion({ p: V3(x, groundY(x, z), z), t0, s: 18, seed: 170 + i, debris: 14 })));
  [[0.6, 395, -650], [2.5, 270, -648]].forEach(([t0, x, z], i) => fx.add(explosion({ p: V3(x, 0, z), t0, s: 14, seed: 175 + i, water: true, debris: 0, ember: 0, dust: false })));
  [[320, -6, 240], [400, -1, 260]].forEach(([x, t0, y], i) => fx.add(flare({ p0: V3(x, y, -720), t0, seed: 180 + i })));
  return {
    update(t) {
      SEA.amp = 0.7;
      onWaves(L1.root, b1.x, b1.z + Math.max(0, 0.6 - t) * 20, 0.03, t, 1.4, 0.25);
      onWaves(L2.root, b2.x, b2.z + Math.max(0, 0.4 - t) * 20, -0.04, t, 1.4, 0.25);
      L1.setRamp(smooth(0.3, 1.1, t)); L2.setRamp(smooth(0.5, 1.3, t));
      for (const r of runners) {
        const u = t - r.t0;
        if (u < 0) { r.s.root.visible = false; continue; }
        r.s.root.visible = true;
        const p = r.start.clone().addScaledVector(r.dir, Math.min(u, 3.5) * r.sp);
        const gy = Math.max(groundY(p.x, p.z), seaY(p.x, p.z, t) - 1.5);
        r.s.root.position.set(p.x, gy, p.z);
        r.s.root.rotation.set(0, headingTo(V3(), r.dir), 0);
        pose(r.s, runPose((u * 1.6 + r.ph) % 1));
      }
      cam(env, V3(lerp(334, 326, t / 5), 9.5, lerp(-612, -618, t / 5)), V3(326, 12, -740), 36);
      shake(env.camera, t, 0.55, 3, 13);
      return { exposure: 1.15, shadowAt: V3(330, 5, -700), shadowR: 120, bloom: 1.2 };
    },
    events: [{ t: 0, k: 'battleBed' }, { t: 0.3, k: 'ramp' }, { t: 0.6, k: 'splash' }, { t: 1.8, k: 'boom' }, { t: 2.5, k: 'splash' }, { t: 3.1, k: 'boom' }, { t: 4.2, k: 'boom' }],
  };
}
// S13 99A 下艇：贴着沙地看坦克开出来，转炮塔，开炮打碉堡
async function shotTank(env, add) {
  const { fx, groundY } = env;
  const H = hovercraft(env.T); add(H.root);
  const tank = await vehicle('ztz99', env.REPO);
  add(tank.root);
  const hp = V3(378, 0, -692);
  const path = t => V3(378, 0, -688 - Math.min(t, 2.4) * 15 - Math.max(0, Math.min(t, 4.5) - 2.4) * 2.0);
  const fireT = 2.75;
  const tgt = BUNKER_A.clone().add(V3(0, 2, 0));
  fx.add(muzzle({ p: () => tank.muzzle(), dir: () => tank.muzzleDir(), t0: fireT, kind: 'tank', seed: 191 }));
  fx.add((t, f) => {   // 开炮时车四周一圈扬尘
    const u = t - fireT;
    if (u < 0 || u > 3) return;
    const c = tank.root.position;
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * Math.PI * 2, r = 6 + 28 * (1 - Math.exp(-u * 3));
      f.sprite('puff', c.clone().add(V3(Math.cos(a) * r, 2.5, Math.sin(a) * r)), 12 + u * 6, 8 + u * 10, 0.5 * (1 - u / 3), 0, [0.6, 0.55, 0.45], a);
    }
  });
  fx.add(explosion({ p: tgt, t0: fireT + 0.18, s: 30, seed: 192, debris: 30 }));
  fx.add(fire({ p: tgt.clone(), s: 9, t0: fireT + 0.6, seed: 193 }));
  fx.add(burst({ from: BUNKER_B.clone().add(V3(-2, 1.5, 6)), dir: t => V3(-0.3 + Math.sin(t * 2) * 0.1, -0.12, 1).normalize(), t0: 0, t1: 4.5, rate: 9, speed: 1100, color: RED_T, spread: 0.02, seed: 194, flash: 'mg', maxD: 700 }));
  fx.add(flare({ p0: V3(360, 240, -730), t0: -5, seed: 195 }));
  fx.add(fire({ p: V3(392, groundY(392, -738) + 0.5, -738), s: 6, seed: 196 }));
  return {
    update(t) {
      H.root.position.set(hp.x, Math.max(env.groundY(hp.x, hp.z), 0) + 2.2, hp.z); H.root.rotation.set(-0.05, 0, 0); H.root.updateMatrixWorld(true);
      H.spin(t * 0.3);
      const p = path(t);
      if (p.z < -714) onGround(env, tank.root, p.x, p.z, 0, 0.2); else { tank.root.position.set(p.x, Math.max(H.root.position.y + 1.2, env.groundY(p.x, p.z) + 0.2), p.z); tank.root.rotation.set(-0.06 * smooth(-700, -714, p.z), 0, 0); }
      tank.root.position.y += Math.sin(t * 9) * 0.05;
      tank.roll(-(p.z + 688));
      const want = headingTo(tank.root.position, tgt) - tank.root.rotation.y;
      tank.aim(lerp(0, want, smooth(1.2, 2.5, t)), lerp(0.02, 0.06, smooth(1.2, 2.5, t)));
      const kick = t > fireT ? Math.exp(-(t - fireT) * 6) * (1 - Math.exp(-(t - fireT) * 60)) : 0;
      tank.kick(kick);
      tank.root.rotateX(kick * 0.015);
      tank.root.updateMatrixWorld(true);
      cam(env, V3(lerp(350, 344, t / 4.5), groundY(347, -748) + 3.0, -748), tank.root.position.clone().add(V3(-4, 5, 0)), 34);
      shake(env.camera, t, 0.25 + (t > fireT ? 2.2 * Math.exp(-(t - fireT) * 4) : 0), 7, 17);
      return { exposure: 1.15, shadowAt: tank.root.position, shadowR: 70, dof: { focus: env.camera.position.distanceTo(tank.root.position), range: 30, max: 0.45 }, bloom: 1.25 };
    },
    events: [{ t: 0, k: 'tankEngine' }, { t: 1.2, k: 'turret' }, { t: fireT, k: 'tankFire' }, { t: fireT + 0.18, k: 'bigboom', v: 0.9 }],
  };
}
// S14 守方的 M1A2 在坡上还击
async function shotAbrams(env, add) {
  const { fx, groundY } = env;
  const tank = await vehicle('m1a2v3', env.REPO);
  add(tank.root);
  const p = V3(468, 0, -905);
  const hd = headingTo(p, V3(340, 0, -660));
  onGround(env, tank.root, p.x, p.z, hd, 0.2);
  const fireT = 1.35;
  fx.add(muzzle({ p: () => tank.muzzle(), dir: () => tank.muzzleDir(), t0: fireT, kind: 'tank', seed: 201 }));
  fx.add(fire({ p: V3(330, groundY(330, -730), -730), s: 10, seed: 202 }));
  fx.add(fire({ p: V3(300, groundY(300, -700), -700), s: 7, seed: 203 }));
  fx.add(fire({ p: V3(381, 2, -690), s: 8, seed: 204 }));
  fx.add(flare({ p0: V3(380, 230, -760), t0: -4, seed: 205 }));
  fx.add(explosion({ p: V3(365, groundY(365, -690), -690), t0: fireT + 0.55, s: 24, seed: 206 }));
  return {
    update(t) {
      tank.aim(Math.sin(t * 0.4) * 0.02, -0.05);
      const kick = t > fireT ? Math.exp(-(t - fireT) * 6) * (1 - Math.exp(-(t - fireT) * 60)) : 0;
      tank.kick(kick);
      tank.root.updateMatrixWorld(true);
      cam(env, tank.root.localToWorld(V3(7.5, 11.5, 15)), tank.root.localToWorld(V3(-2, 2, -120)), 34);
      shake(env.camera, t, 0.15 + (t > fireT ? 2.5 * Math.exp(-(t - fireT) * 4) : 0), 7, 19);
      return { exposure: 1.15, shadowAt: tank.root.position, shadowR: 60, dof: { focus: 140, range: 200, max: 0.3 }, bloom: 1.25 };
    },
    titles: t => [{ text: 'M1A2 SEPv3', x: 0.94, y: 0.84, size: 0.015, font: SANS, align: 'right', spacing: 0.3, a: fadeIO(t, 0.3, 3.3, 0.4, 0.4), color: '#9fb4d8' }],
    events: [{ t: 0, k: 'battleBed' }, { t: fireT, k: 'tankFire' }, { t: fireT + 0.55, k: 'boom' }],
  };
}
// S15 空中：月光下的歼-20，F-22 横穿、放热诱弹
async function shotAir(env, add) {
  const { fx } = env;
  const J = await aircraft('j20', env.REPO); add(J.root);
  const F = await aircraft('f22', env.REPO); add(F.root);
  afterburners(J, fx, () => 0.75); afterburners(F, fx, () => 0.9);
  const jp = t => V3(300 + t * 10, 420 + Math.sin(t * 0.6) * 6, 900 - t * 300);
  const fp = t => V3(-1300 + t * 640, 470 - t * 12, -100 + t * 90);
  for (let k = 0; k < 8; k++) {
    const tr = 1.9 + k * 0.09, side = k % 2 ? 1 : -1;
    fx.add((t, f) => {
      const u = t - tr;
      if (u < 0 || u > 3.2) return;
      const p0 = fp(tr), v = V3(240 + side * 60, -40, 60 + side * 60);
      const p = p0.clone().addScaledVector(v, u * 0.55).add(V3(0, -0.5 * 27 * 0.7 * u * u, 0));
      const kk = 1 - u / 3.2;
      f.addGlow(p, 5, new THREE.Color(1, 0.75, 0.45), 14 * kk, 1, 0.0022);
      f.addLight(p, new THREE.Color(1, 0.7, 0.4), 20 * kk, 200);
      for (let j = 1; j < 10; j++) { const b = j * 0.08; if (b > u) break; const q = p0.clone().addScaledVector(v, (u - b) * 0.55).add(V3(0, -0.5 * 27 * 0.7 * (u - b) ** 2, 0)); f.sprite('puff', q, 3 + b * 10, 10 + b * 20, 0.4 * kk * (1 - j / 10), 0, [1.0, 0.95, 0.9], j); }
    });
  }
  fx.add(missile({ path: tau => { const u = tau - 2.4; return fp(2.4).add(V3(-60, 5, 0)).add(V3(u * 200 - u * u * 120, u * 15, -u * 600)); }, t0: 2.4, t1: 6, size: 1.0, smokeLife: 3 }));
  return {
    update(t) {
      const p = jp(t);
      J.root.position.copy(p);
      J.root.rotation.set(0, 0, 0);
      J.root.rotateZ(Math.sin(t * 0.7) * 0.35 + 0.3);
      J.root.rotateX(0.04);
      J.root.updateMatrixWorld(true);
      F.root.position.copy(fp(t));
      F.root.rotation.set(0, -Math.PI / 2 + 0.15, 0);
      F.root.rotateZ(-0.9);
      F.root.updateMatrixWorld(true);
      cam(env, p.clone().add(V3(30, 14, 78)), p.clone().add(V3(-8, -40, -200)), 36);
      env.camera.rotateZ(-(Math.sin(t * 0.7) * 0.35 + 0.3) * 0.25);
      shake(env.camera, t, 0.35, 5, 23);
      return { exposure: 1.2, shadowAt: p, shadowR: 80, bloom: 1.2, fogDensity: 0.00026 };
    },
    events: [{ t: 0, k: 'jetCabin' }, { t: 1.6, k: 'jetPass' }, { t: 1.9, k: 'flares' }, { t: 2.4, k: 'missileLaunch' }],
  };
}
// S16 直-10 从头顶低空掠过，机头探照灯扫过海滩，火箭往岛里打
async function shotHeli(env, add) {
  const { fx, groundY } = env;
  const hs = [await aircraft('z10w', env.REPO), await aircraft('z10w', env.REPO)];
  hs.forEach(h => add(h.root));
  const hp = (i, t) => V3(330 + i * 70, 30 + i * 14 + Math.sin(t * 1.3 + i) * 1.0, -640 - t * 62 - i * 40);
  // 探照灯：光柱 + 真的聚光灯
  const beam = beamMesh(320, 7 * DEG, new THREE.Color(1, 0.96, 0.88), 1.4);
  hs[0].root.add(beam); beam.position.set(0, 3.0, -15); beam.rotation.set(-0.55, 0, 0);
  const sl = new THREE.SpotLight(0xfff4e0, 26000, 500, 8 * DEG, 0.5, 2); hs[0].root.add(sl); sl.position.set(0, 3.0, -15);
  hs[0].root.add(sl.target); sl.target.position.set(0, -180, -280);
  // 航行灯：左红右绿、尾白闪
  hs.forEach(h => fx.add((t, f) => {
    const M = h.M, w = (M.tip ? M.tip[0] : 6) * 0.9;
    f.addGlow(h.root.localToWorld(V3(-w, 3.4, -2)), 0.8, new THREE.Color(1, 0.1, 0.05), 6, 1, 0.0015);
    f.addGlow(h.root.localToWorld(V3(w, 3.4, -2)), 0.8, new THREE.Color(0.1, 1, 0.3), 6, 1, 0.0015);
    if ((t * 1.3) % 1 < 0.12) f.addGlow(h.root.localToWorld(V3(0, 9.5, 14)), 1.2, new THREE.Color(1, 1, 1), 14, 1, 0.002);
  }));
  for (let i = 0; i < 2; i++) for (let k = 0; k < 4; k++) {
    const tl = 1.3 + k * 0.16 + i * 0.08;
    fx.add(missile({ path: tau => { const u = tau - tl; const p0 = hp(i, tl).add(V3(k % 2 ? 4 : -4, 2, -8)); return p0.add(V3(0, -u * 8, -u * 420)); }, t0: tl, t1: tl + 2.5, size: 0.7, smokeLife: 2.5, col: new THREE.Color(1, 0.6, 0.3) }));
  }
  [[2.7, 330, -1000], [2.9, 380, -1030], [3.1, 300, -1050]].forEach(([t0, x, z], i) => fx.add(explosion({ p: V3(x, groundY(x, z), z), t0, s: 30, seed: 220 + i })));
  fx.add(fire({ p: V3(300, groundY(300, -771), -771), s: 9, seed: 223 }));
  fx.add(flare({ p0: V3(340, 260, -800), t0: -6, seed: 224 }));
  fx.add(flare({ p0: V3(352, 150, -520), t0: -1.5, seed: 225 }));   // 南边低一点的照明弹：直升机的剪影
  return {
    update(t) {
      hs.forEach((h, i) => {
        h.root.position.copy(hp(i, t));
        h.root.rotation.set(-0.2, 0.05, Math.sin(t + i) * 0.05);
        h.spin(t, 0.13);
        h.root.updateMatrixWorld(true);
      });
      const cp = V3(318, groundY(318, -778) + 3.2, -778);
      const tgt = hp(0, t).add(V3(0, 4, 0));
      cam(env, cp, tgt.lerp(V3(330, 60, -900), smooth(1.8, 3.4, t) * 0.5), 46);
      shake(env.camera, t, 0.45 + smooth(1.4, 2.4, t) * 0.5, 4, 29);
      return { exposure: 1.15, shadowAt: V3(330, 20, -760), shadowR: 140, bloom: 1.25 };
    },
    events: [{ t: 0, k: 'rotor' }, { t: 1.3, k: 'rockets' }, { t: 2.7, k: 'boom' }, { t: 2.9, k: 'boom' }, { t: 3.1, k: 'boom' }],
  };
}
// S17 爱国者发射
async function shotPatriot(env, add) {
  const { fx } = env;
  const P = await vehicle('patriot', env.REPO);
  add(P.root);
  const at = V3(705, 0, -1235);
  onGround(env, P.root, at.x, at.z, Math.PI * 0.95, 0.1);
  const tl = 0.6;
  const exit = () => P.root.localToWorld(V3(0, 13, 6));
  const dir = () => V3(0, 0.62, 0.78).applyQuaternion(P.root.quaternion).normalize();
  fx.add(missile({ path: tau => { const u = Math.max(0, tau - tl); return exit().addScaledVector(dir(), u * 30 + u * u * 160); }, t0: tl, t1: tl + 4, size: 2.0, smokeLife: 5 }));
  fx.add((t, f) => {
    const u = t - tl;
    if (u < 0 || u > 3) return;
    const b = exit();
    if (u < 0.4) f.addGlow(b, 30, new THREE.Color(1, 0.75, 0.45), 6 * (1 - u / 0.4), 1, 0);
    f.addLight(b.clone().addScaledVector(dir(), 25), new THREE.Color(1, 0.6, 0.3), 30 * Math.exp(-u * 1.5), 260);
    for (let j = 0; j < 10; j++) {
      const a = j / 10 * Math.PI * 2, r = 6 + 22 * (1 - Math.exp(-u * 2));
      f.sprite('puff', P.root.localToWorld(V3(Math.cos(a) * r, 3 + Math.sin(j) * 1.5, 12 + Math.sin(a) * r)), 12 + u * 6, 8 + u * 9, 0.6 * (1 - u / 3), 0, [0.75, 0.72, 0.7], j);
    }
  });
  return {
    update(t) {
      cam(env, P.root.localToWorld(V3(-18, 3.2, -16)), P.root.localToWorld(V3(0, 12 + smooth(tl, tl + 1.5, t) * 30, 30)), 38);
      shake(env.camera, t, t > tl ? 1.8 * Math.exp(-(t - tl) * 2) + 0.15 : 0.15, 6, 31);
      return { exposure: 1.15, shadowAt: P.root.position, shadowR: 60, bloom: 1.25 };
    },
    titles: t => [{ text: 'MIM-104 爱国者', x: 0.94, y: 0.84, size: 0.015, font: SANS, align: 'right', spacing: 0.3, a: fadeIO(t, 0.3, 2.8, 0.4, 0.4), color: '#9fb4d8' }],
    events: [{ t: tl, k: 'launch' }, { t: tl, k: 'hit' }],
  };
}

// ———————————— 黎明 ————————————
// S18 天亮了：滩头的烟、烧着的残骸，人影往坡上走；镜头从人身后升起来，岛的山脊后面天发白
async function shotDawn(env, add) {
  const { fx, groundY } = env;
  const sq = await squad(env, 'atk', 7, 251, { nvg: 0 });
  sq.forEach(s => add(s.root));
  const tank = await vehicle('ztz99', env.REPO); add(tank.root);
  onGround(env, tank.root, 356, -722, 0.25, 0.2);
  tank.aim(-0.3, 0.02);
  [[290, -771, 6], [412, -812, 5], [330, -730, 3.5], [262, -742, 3]].forEach(([x, z, s], i) => fx.add(fire({ p: V3(x, groundY(x, z) + 0.5, z), s, seed: 260 + i })));
  const R = rng(270);
  const walkers = sq.map((s, i) => ({ s, start: V3(298 + i * 11 + R.range(-3, 3), 0, -712 - R.range(0, 14)), sp: R.range(3.2, 4.6), ph: R() }));
  return {
    update(t) {
      const u = t / 8;
      for (const w of walkers) {
        const z = w.start.z - t * w.sp;
        w.s.root.position.set(w.start.x, groundY(w.start.x, z), z);
        w.s.root.rotation.set(0, 0.05, 0);
        pose(w.s, { ...runPose((t * 0.7 + w.ph) % 1, 0.45), gun: { p: [0.4, 0.75, -0.8], r: [-0.5, 0.2, 0.15] } });
      }
      const e = easeIO(u);
      const cp = V3(lerp(324, 318, e), lerp(groundY(324, -698) + 2.4, 62, e), lerp(-698, -650, e));
      const look = V3(lerp(330, 340, e), lerp(28, 52, e), lerp(-800, -980, e));
      cam(env, cp, look, lerp(34, 40, e));
      const dawn = lerp(0.35, 0.85, u);
      return { exposure: lerp(1.25, 1.1, u), dawn, sunDir: V3(0.38, 0.03, -0.92).normalize(), moonVis: 1 - dawn * 0.8,
        fogColor: new THREE.Color().setRGB(lerp(0.035, 0.13, dawn), lerp(0.04, 0.105, dawn), lerp(0.06, 0.115, dawn)), fogDensity: 0.00055,
        moonDir: V3(0.38, 0.1, -0.92).normalize(), moonI: lerp(2.0, 3.6, dawn), moonC: 0xffc89a, hemiI: lerp(1.2, 1.8, dawn),
        shadowAt: V3(330, 15, -740), shadowR: 160, sat: 0.88, bloom: 1.0 };
    },
    events: [{ t: 0, k: 'dawnMusic' }, { t: 0, k: 'aftermath' }],
  };
}
// S19 片名
async function shotTitle(env, add) {
  env.worldVisible(false);
  const R = rng(300);
  const E = [];
  for (let i = 0; i < 140; i++) E.push({ p: V3(R.range(-60, 60), R.range(-30, 30), R.range(-80, -20)), v: V3(R.range(-0.5, 1.5), R.range(1, 3.5), 0), ph: R() * 6, s: R.range(0.08, 0.3) });
  env.fx.add((t, fx) => {
    for (const e of E) {
      const p = e.p.clone().addScaledVector(e.v, t); p.y = ((p.y + 30) % 60 + 60) % 60 - 30;
      const tw = 0.5 + 0.5 * Math.sin(t * 3 + e.ph);
      fx.addGlow(p, e.s, new THREE.Color(1, 0.5, 0.18), 3.5 * tw, 1, 0);
    }
  });
  return {
    update(t) {
      cam(env, V3(0, 0, 0), V3(0, 0, -1), 40);
      return { exposure: 1, bloom: 1.4, fade: 0, grain: 0.012, lift: 0 };
    },
    titles: t => [
      { text: 'Roblox全面大战场', x: 0.5, y: 0.47, size: 0.085, font: SERIF, weight: 700, spacing: 0.12, a: fadeIO(t, 0.6, 5.7, 1.2, 0.8), color: '#efe9de', glow: 'rgba(255,170,90,0.35)' },
      { text: '海 · 陆 · 空　全面开战', x: 0.5, y: 0.585, size: 0.026, font: SERIF, spacing: 0.5, a: fadeIO(t, 1.6, 5.7, 1.0, 0.8), color: '#c9c1b4', rule: 0.22 },
    ],
    events: [{ t: 0.55, k: 'titleHit' }],
  };
}
// S20 卖点：几行字，背后是缓缓转动的坦克 / 战斗机剪影
async function shotFeatures(env, add) {
  env.worldVisible(false);
  const tank = await vehicle('ztq15', env.REPO); add(tank.root);
  const J = await aircraft('j20', env.REPO); add(J.root);
  const key = new THREE.DirectionalLight(0xffd6b0, 4.0); key.position.set(-25, 18, 35); add(key);
  const rim = new THREE.DirectionalLight(0x8fb0ff, 6.0); rim.position.set(30, 14, -90); add(rim);
  return {
    update(t) {
      const seg = t < 3.75 ? 0 : 1;
      tank.root.visible = seg === 0; J.root.visible = seg === 1;
      const u = seg === 0 ? t / 3.75 : (t - 3.75) / 3.75;
      if (seg === 0) { tank.root.position.set(13, -4.5, -48); tank.root.rotation.set(0, 0.55 + u * 0.35, 0); tank.aim(Math.sin(u * 2) * 0.2 - 0.3, 0.03); }
      else { J.root.position.set(34, -3, -92); J.root.rotation.set(0.1, -1.0 + u * 0.35, 0.25); }
      cam(env, V3(0, 0, 0), V3(0, 0, -1), 32);
      const k = fadeIO(t, seg === 0 ? 0 : 3.75, seg === 0 ? 3.75 : 7.5, 0.5, 0.5);
      return { exposure: 1.4 * k + 0.0001, bloom: 0.8, fade: 0, grain: 0.012, vignette: 0.8, lift: 0 };
    },
    titles: t => {
      const A = (a, b) => fadeIO(t, a, b, 0.45, 0.45);
      return [
        { text: '两栖登陆 · 夜战 · 夜视仪', x: 0.08, y: 0.4, size: 0.034, font: SERIF, weight: 700, align: 'left', spacing: 0.12, a: A(0.3, 3.6) },
        { text: '五个据点 · 海陆空同一张战场', x: 0.08, y: 0.47, size: 0.02, font: SANS, align: 'left', spacing: 0.25, a: A(0.7, 3.6), color: '#b9b2a6' },
        { text: '陆海空 50 多种载具', x: 0.08, y: 0.4, size: 0.034, font: SERIF, weight: 700, align: 'left', spacing: 0.12, a: A(4.0, 7.3) },
        { text: '坦克 · 装甲车 · 火炮 · 战斗机 · 直升机 · 舰艇——每一辆都能亲自驾驶', x: 0.08, y: 0.47, size: 0.02, font: SANS, align: 'left', spacing: 0.15, a: A(4.4, 7.3), color: '#b9b2a6' },
      ];
    },
    events: [{ t: 0.3, k: 'pulse2' }, { t: 4.0, k: 'pulse2' }],
  };
}
// S21 片尾：选阵营、测试版、署名
async function shotEnd(env, add) {
  env.worldVisible(false);
  const credits = ['ZTZ-99A：philano', 'M1A2 SEPv3：dannzjs', '歼-20、F-22：andertan', '歼-15、直-10：42manako', '055 型驱逐舰：FeriseCAT', '爱国者：Muhamad Mirza Arrafi', 'ZTQ-15：lhc526', 'M4：BarcodeGames', '沙地贴图：Terrie Simmons-Ehrhardt'];
  return {
    update(t) { cam(env, V3(0, 0, 0), V3(0, 0, -1), 40); return { exposure: 1, fade: 0, grain: 0.010, lift: 0 }; },
    titles: t => {
      const a = fadeIO(t, 0.2, 5.5, 0.6, 0.9);
      return [
        { text: '中国人民解放军　VS　美国军队', x: 0.5, y: 0.36, size: 0.03, font: SERIF, weight: 700, spacing: 0.18, a },
        { text: '选择你的阵营', x: 0.5, y: 0.42, size: 0.02, font: SANS, spacing: 0.6, a, color: '#c9c1b4' },
        { text: 'Roblox全面大战场　1.0-alpha 测试中', x: 0.5, y: 0.53, size: 0.018, font: SANS, spacing: 0.3, a: a * 0.9, color: '#a8a196' },
        { text: '本片为游戏原模型与地图离线渲染的微电影　模型均为 Sketchfab 上 CC-BY 4.0 授权作品', x: 0.5, y: 0.645, size: 0.0125, font: SANS, spacing: 0.1, a: a * 0.75, color: '#8a847a' },
        { text: credits.slice(0, 5).join('　·　'), x: 0.5, y: 0.68, size: 0.0125, font: SANS, spacing: 0.05, a: a * 0.75, color: '#8a847a' },
        { text: credits.slice(5).join('　·　') + '　·　特效贴图：ArmyVFX', x: 0.5, y: 0.705, size: 0.0125, font: SANS, spacing: 0.05, a: a * 0.75, color: '#8a847a' },
      ];
    },
    events: [{ t: 0, k: 'endTail' }],
  };
}
// 调试：几架飞机摆在一起看
async function shotDbg(env, add) {
  env.worldVisible(false);
  const a = await aircraft('z10w', env.REPO), b = await aircraft('ah64', env.REPO), c = await aircraft('j15', env.REPO);
  [a, b, c].forEach((x, i) => { add(x.root); x.root.position.set(-40 + i * 40, -5, -80); x.root.rotation.y = 0.6; });
  const key = new THREE.DirectionalLight(0xffffff, 4.0); key.position.set(-25, 18, 35); add(key);
  let info = '';
  a.root.traverse(o => { if (o.isMesh) { const m = o.material; info += `${o.name}:${m.type},t=${m.transparent},o=${m.opacity},vis=${o.visible},a=${m.alphaTest},side=${m.side}; `; } });
  console.log('[film] z10w', info.slice(0, 600));
  return { update(t) { cam(env, V3(0, 0, 0), V3(0, -5, -80), 50); return { exposure: 1.4, lift: 0 }; } };
}
