// 海湾战争版宣传片（用户 11-22：「整个重做，纯地面和空军对战的海湾战争」）：游戏的沙漠地图（MapDesert.lua），没有海
//   主线照用户给的：战机编队定点清除防空阵地 → 无人机远程摧毁目标 → 坦克集群对轰、互相开罐（炮长瞄准镜第一人称）→
//   阿帕奇打掉几辆车、被防空车锁定，机炮扫射加导弹，规避一枚、第二枚放了热诱弹也被打中、打着转坠地爆炸 →
//   歼-16 满挂对地武器，光电吊舱发现装甲纵队，导弹挨个锁定、挨个击毁 → 黄昏的油田大火、片名
//   每个镜头 setup 搭好要用的东西，update(t) 摆好这一刻的镜头、模型、特效，返回后期参数；events 给配乐、音效（gulf/audio.js）
import * as THREE from 'three';
import { V3, keys, ease, easeIn, easeOut, easeIO, smooth, lerp, shake, rng, DEG, fbm1, clamp, sat } from '../lib.js';
import { heightAt } from '../bigmap.js';
import { vehicle, aircraft, missileModel, pl10, pl15, pac2, patriotNoses, soldier, pose, runPose, AIM, loadGLB } from '../models.js';
import { explosion, muzzle, burst, missile, fire as fireFx, flameMesh } from '../fx.js';
import { afterburners } from '../shots.js';
import { fadeIO } from '../titles.js';
import { day, dusk, night, dirAzEl } from './look.js';
import { sabot, armorHit, cookoff, bigFire, decoys, gatling, dustTrail, rotorWash, aaa, skyFlashes } from './fx2.js';
import { clutter, poles, pumpjack, wellhead, samSite, town, shelter, burnt, thermalize, dusty } from './scenery.js';
import { drawEO, drawDrone, drawSight99, drawSightM1, drawWarn, caption, plane, interior, drawHud } from './kit.js';

export const BIGCFG = { id: true, desert: true, fx: 0, fz: 0 };
export function prepWorld(world) { for (const k of ['parts', 'lights']) if (!Array.isArray(world[k])) world[k] = []; }

const SERIF = '"Noto Serif SC"', SANS = '"Noto Sans SC"';
export function cam(env, pos, look, fov) {
  const c = env.camera;
  c.position.copy(pos);
  c.up.set(0, 1, 0);
  c.lookAt(look);
  if (fov) { c.fov = fov; c.updateProjectionMatrix(); }
}
export const gy = (x, z) => heightAt(x, z);
export const gp = (x, z, lift = 0) => V3(x, heightAt(x, z) + lift, z);
const headingTo = (from, to) => Math.atan2(-(to.x - from.x), -(to.z - from.z));   // 0 = 朝北（−Z）
// 车贴地：位置、朝向、按地面坡度俯仰 / 侧倾
function ground(obj, x, z, hd, lift = 0.15) {
  const y = heightAt(x, z);
  const a = heightAt(x - Math.sin(hd) * 5, z - Math.cos(hd) * 5), b = heightAt(x + Math.sin(hd) * 5, z + Math.cos(hd) * 5);
  const l = heightAt(x - Math.cos(hd) * 4, z + Math.sin(hd) * 4), r = heightAt(x + Math.cos(hd) * 4, z - Math.sin(hd) * 4);
  obj.position.set(x, y + lift, z);
  obj.rotation.set(0, 0, 0);
  obj.rotateY(hd);
  obj.rotateX(Math.atan2(a - b, 10));
  obj.rotateZ(Math.atan2(r - l, 8));
  obj.updateMatrixWorld(true);
  return y;
}
// 飞机：位置、机头朝向（速度方向）、横滚（正数往左压坡度）。模型的机头是 −Z（kit.js plane：炮口、机头都在 −Z），
//   lookAt(0, dir) 让 −Z 对着 dir（原来写成 lookAt(0, −dir)，整架飞机倒着飞：用户 11-22「J35 为什么是倒着飞」）
function fly(A, p, dir, roll = 0) {
  A.root.position.copy(p);
  const m = new THREE.Matrix4().lookAt(new THREE.Vector3(), dir.clone(), new THREE.Vector3(0, 1, 0));
  A.root.quaternion.setFromRotationMatrix(m);
  A.root.rotateZ(roll);
  A.root.updateMatrixWorld(true);
}
// 弹药模型
const ls6 = () => missileModel({ len: 10.8, r: 0.5, nose: 'radar', fins: [1.4, 0.8, 0.9, 0.9], strake: [0.25, 0.5, 0.35], col: 0x9a9e8a, roll: 0 });
const kd88 = () => missileModel({ len: 12.9, r: 0.5, nose: 'ir', fins: [1.6, 0.9, 1.1, 1.0], canard: [0.12, 1.0, 0.45, 0.55, 0.5], col: 0xb9bcae });
const hellfire = () => missileModel({ len: 4.8, r: 0.25, nose: 'ir', fins: [0.5, 0.3, 0.4, 0.35], canard: [0.1, 0.6, 0.25, 0.3, 0.25], col: 0x5d6448 });
const fn16 = () => missileModel({ len: 4.4, r: 0.2, nose: 'ir', fins: [0.4, 0.25, 0.3, 0.3], canard: [0.08, 0.5, 0.2, 0.25, 0.2], col: 0x6c7258 });
const lj7 = () => missileModel({ len: 4.9, r: 0.25, nose: 'ir', fins: [0.5, 0.3, 0.35, 0.35], col: 0x9ea294 });
// 两次地形网格（镜头附近细）
const T = (x, z, o) => ({ terrain: () => [x, z], terrainOpt: o || {} });

// —— 地图上的点（游戏地图 MapDesert.lua）——
const SAM = V3(5600, 0, -6800);        // 蓝方爱国者阵地（空军基地东北）
const TOWNC = V3(-3800, 0, -600);      // 镇子（据点 C）
const OIL = V3(5200, 0, 2600);         // 油田（据点 B）
const DUNE = V3(200, 0, 3700);         // 低沙梁（坦克对战）
const MESA = V3(-8400, 0, -4300);      // 镇子西北的方山（阿帕奇藏在后面）
const BATT = V3(2600, 0, -12300);      // 岭北的 M109 炮兵阵地（无人机打）
const COL6 = V3(9800, 0, 3150);        // 6 号公路东段（蓝方装甲纵队，歼-16 打）

// ———————————————————————————— 序幕：夜里 ————————————————————————————
// G01 夜里的沙漠，天边一闪一闪（空袭开始了），镇子那边高炮往天上泼曳光
async function shotOpen(env, add) {
  const { fx } = env;
  const R = rng(101);
  const flashes = [];
  for (let i = 0; i < 9; i++) flashes.push({ p: V3(-9000 + R() * 18000, 30 + R() * 80, -13000 - R() * 6000), t: 0.6 + i * 0.55 + R() * 0.3, s: 0.6 + R() * 0.8 });
  fx.add(skyFlashes({ list: flashes }));
  const guns = [];
  for (let i = 0; i < 6; i++) { const x = TOWNC.x - 300 + R() * 600, z = TOWNC.z - 300 + R() * 600; guns.push({ p: gp(x, z, 6), yaw: R.range(-1, 1), rate: 14 + R() * 8, col: new THREE.Color(1, 0.36 + R() * 0.1, 0.12) }); }
  fx.add(aaa({ guns, t0: 0.4, t1: 7 }));
  add(town(TOWNC.x, TOWNC.z, { n: 60 }));
  return {
    update(t) {
      const u = t / 6.5;
      const p = V3(lerp(-1200, -1600, u), 0, lerp(2600, 2200, u));
      p.y = heightAt(p.x, p.z) + lerp(46, 58, u);
      cam(env, p, V3(TOWNC.x + 300, 140, TOWNC.z - 1600), 34);
      shake(env.camera, t, 0.08, 0.5, 3);
      return { ...night({ moonI: 2.2, exposure: 1.2 }), fade: 1 - smooth(0.1, 1.8, t), shadowAt: TOWNC, shadowR: 900 };
    },
    titles: t => [
      { text: '沙海 · 凌晨 2:40', x: 0.5, y: 0.75, size: 0.032, font: SERIF, weight: 700, spacing: 0.25, a: fadeIO(t, 1.2, 6.2, 0.8, 0.6) },
      { text: '红方空中打击开始', x: 0.5, y: 0.8, size: 0.017, font: SANS, spacing: 0.32, a: fadeIO(t, 1.8, 6.2, 0.8, 0.6), color: '#b8bcc4' },
    ],
    events: [{ t: 0, k: 'desertWind' }, { t: 0.4, k: 'aaaFar' }, ...flashes.map(e => ({ t: e.t + 1.6, k: 'distantBoom', v: 0.4 * e.s }))],
  };
}
// G02 夜视仪里：镇子边上的 M163 火神防空炮朝天上泼弹
async function shotNvgAAA(env, add) {
  const { fx } = env;
  const V = await vehicle('m163', env.REPO); add(V.root);
  const p0 = gp(TOWNC.x + 420, TOWNC.z + 260);
  ground(V.root, p0.x, p0.z, 2.6);
  add(town(TOWNC.x, TOWNC.z, { n: 60 }));
  const aim = t => { const y = Math.sin(t * 0.45) * 0.3 + 0.3; const p = 0.78 + Math.sin(t * 0.6) * 0.08; return [y, p]; };   // 跟着目标慢慢转
  const dir = t => { const [y, p] = aim(t); V.aim(y, p); V.root.updateMatrixWorld(true); return V.muzzleDir(); };
  fx.add(gatling({ from: t => { dir(t); return V.muzzle(); }, dir, t0: 0.3, t1: 3.6, rate: 50, speed: 1050, every: 5, spread: 0.007, col: new THREE.Color(1, 0.42, 0.15), len: 26, maxD: 3200, w: 0.7, bright: 5, flash: 0.35 }));   // 炮口闪光压暗：夜视里原来像频闪灯
  return {
    update(t) {
      const [y, p] = aim(t); V.aim(y, p);
      V.root.updateMatrixWorld(true);
      const c = V.root.localToWorld(V3(-13, 3.5, 21));
      cam(env, c, V.root.localToWorld(V3(0, 22, -70)), 44);
      shake(env.camera, t, (t > 0.3 && t < 3.6) ? 0.28 : 0.12, 4, 5);
      return { ...night({ exposure: 1.5 }), nvg: 1, grain: 0.03, vignette: 0.9, bloom: 0.8, shadowAt: p0, shadowR: 80 };
    },
    titles: t => caption('蓝方 · M163 火神防空炮', '镇子外围 · 夜视仪画面', fadeIO(t, 0.4, 3.7, 0.4, 0.4)),
    events: [{ t: 0, k: 'nvgWhine' }, { t: 0.3, k: 'vulcan', d: 3.3 }],
  };
}

// ———————————————————————————— 第一幕：定点清除防空阵地（夜） ————————————————————————————
// 爱国者阵地、歼-35 编队共用一条时间线：τ = 0 在 G03 开头
const STRIKE = (() => {
  const fwd = V3(0.22, 0, -1).normalize();   // 编队往北偏东飞
  const P0 = V3(SAM.x - 0.22 * 9000 / 1.02, 0, SAM.z + 9000);   // τ = 0 时长机在阵地南边 9 公里
  const v = 290;   // 约 0.85 马赫（格 / 秒 = 米 / 秒 × 2.8 ÷ 2.8……片子里按 1 米 2.8 格：290 格 / 秒 ≈ 104 米 / 秒，放慢一点好看）
  const alt = tau => lerp(62, 420, smooth(6.6, 8.4, tau));   // 先贴地飞，投弹前跃升
  const lead = tau => { const p = P0.clone().addScaledVector(fwd, v * tau); p.y = heightAt(p.x, p.z) + alt(tau); return p; };
  const OFF = [V3(0, 0, 0), V3(-60, 8, 50), V3(70, -6, 55), V3(-120, 14, 100)];   // 编队（梯队）
  const side = new THREE.Vector3().crossVectors(fwd, V3(0, 1, 0)).normalize();
  const jet = (i, tau) => lead(tau).addScaledVector(side, OFF[i].x).add(V3(0, OFF[i].y, 0)).addScaledVector(fwd, -OFF[i].z);
  const T_REL = 7.4, T_HIT = [12.2, 12.6, 13.0, 13.4, 13.8];
  return { fwd, side, lead, jet, T_REL, T_HIT, v };
})();
let SAMKIT = null;   // 阵地（几个镜头共用一份位置）
async function samKit(env, add) {
  const L = [];
  for (let i = 0; i < 4; i++) L.push(dusty(await vehicle('patriot', env.REPO), 0.55));
  const site = samSite(SAM.x, SAM.z, L, { face: Math.PI, r: 110 });   // 雷达朝南
  add(site);
  const U = site.userData;
  const targets = [U.radar.position.clone().add(V3(0, 4, 0)), ...U.launchers.map(l => V3(l.x, heightAt(l.x, l.z) + 4, l.z)), U.ecs.position.clone().add(V3(0, 3, 0))];
  return { site, U, L, targets };
}
// G03 阵地：雷达车、发射车在沙土掩体里，发射箱仰着；夜里只有一点月光
async function shotSam(env, add) {
  const K = await samKit(env, add);
  add(clutter(SAM.x, SAM.z + 200, 360, { seed: 31 }));
  return {
    update(t) {
      const u = t / 4.5;
      K.U.antPiv.rotation.y = Math.sin(t * 0.5) * 0.3;
      const c = V3(SAM.x - 260 + u * 40, 0, SAM.z + 330 - u * 30); c.y = heightAt(c.x, c.z) + 22;
      cam(env, c, V3(SAM.x, heightAt(SAM.x, SAM.z) + 8, SAM.z - 40), 32);
      return { ...night({ moonI: 2.8, exposure: 1.35, az: 200, el: 30 }), shadowAt: SAM, shadowR: 260 };
    },
    titles: t => caption('蓝方 · 爱国者防空导弹阵地', '空军基地东北 6 公里', fadeIO(t, 0.5, 4.2, 0.5, 0.4)),
    events: [{ t: 0, k: 'radarHum' }, { t: 1.2, k: 'radio' }],
  };
}
// G04 歼-35 四机编队贴着沙丘超低空飞过来（加力的火、编队灯关着）
async function shotJets(env, add) {
  const { fx } = env;
  const J = [];
  for (let i = 0; i < 4; i++) { const A = await plane('j31', env); add(A.root); A.gearDown && A.gearDown(false); afterburners(A, fx, () => 0.55, 0.3); J.push(A); }
  const T0 = 3.2;
  return {
    update(t) {
      const tau = T0 + t;
      J.forEach((A, i) => { const p = STRIKE.jet(i, tau), d = STRIKE.jet(i, tau + 0.05).sub(p).normalize(); fly(A, p, d, Math.sin(tau * 0.8 + i) * 0.04); });
      const lead = STRIKE.lead(tau);
      // 镜头：低低地架在沙丘上，编队从左前方压过来、从头顶掠过
      const c = lead.clone().addScaledVector(STRIKE.fwd, -110 + t * 6).addScaledVector(STRIKE.side, 34).add(V3(0, 16, 0));
      cam(env, c, lead.clone().addScaledVector(STRIKE.fwd, 260).add(V3(0, -14, 0)), 40);
      shake(env.camera, t, 0.35, 3, 7);
      return { ...night({ moonI: 2.6, exposure: 1.3 }), shadowAt: lead, shadowR: 200 };
    },
    titles: t => caption('红方 · 歼-35 四机编队', '超低空突防 · 离地 40 米', fadeIO(t, 0.3, 3.6, 0.4, 0.4)),
    events: [{ t: 0, k: 'jetLow' }, { t: 0, k: 'jetCabin' }],
  };
}
// G05 爱国者发射拦截弹（夜里一大团火光），编队放干扰弹、散开
async function shotPatriotFire(env, add) {
  const { fx } = env;
  const K = await samKit(env, add);
  const P = K.L[1];
  const NO = patriotNoses(P);
  const tl = [0.5, 1.4];
  const which = [3, 2];
  tl.forEach((t0, i) => {
    const exitL = NO.noses[which[i]].p.clone();
    const exit = () => P.root.localToWorld(exitL.clone());
    const dir = () => NO.axis.clone().applyQuaternion(P.root.quaternion).normalize();
    fx.add(missile({ path: tau => { const u = Math.max(0, tau - t0); return exit().addScaledVector(dir(), 3 + u * 60 + u * u * 260); }, t0, t1: t0 + 4, size: 2.0, smokeLife: 5 }));
    fx.add((t, f) => {
      const u = t - t0;
      if (u < 0 || u > 3) return;
      const b = exit(), back = dir().negate();
      if (u < 0.4) f.addGlow(b, 30, new THREE.Color(1, 0.75, 0.45), 9 * (1 - u / 0.4), 1, 0);
      f.addLight(b.clone().addScaledVector(back, 12), new THREE.Color(1, 0.6, 0.3), 16 * Math.exp(-u * 1.4), 400);
      for (let j = 0; j < 14; j++) {
        const a = j / 14 * Math.PI * 2, rr = 4 + 30 * (1 - Math.exp(-u * 2.2));
        f.sprite('puff', b.clone().addScaledVector(back, 8 + 24 * (1 - Math.exp(-u * 3))).add(V3(Math.cos(a) * rr, Math.sin(j * 1.7) * 3 + u * 3, Math.sin(a) * rr)), 12 + u * 8, 8 + u * 9, 0.6 * (1 - u / 3) * smooth(0, 0.06, u), 0, [0.7, 0.68, 0.66], j);
      }
    });
  });
  return {
    update(t) {
      tl.forEach((t0, i) => NO.noses[which[i]].meshes.forEach(m => { m.visible = t < t0; }));
      const c = P.root.localToWorld(V3(-26, 5, 34));
      cam(env, c, P.root.localToWorld(V3(0, 20 + smooth(0.5, 2.5, t) * 160, -120)), 40);
      shake(env.camera, t, 0.15 + (t > 0.5 ? 1.6 * Math.exp(-(t - 0.5) * 2) : 0) + (t > 1.4 ? 1.2 * Math.exp(-(t - 1.4) * 2) : 0), 6, 31);
      return { ...night({ moonI: 2.4, exposure: 1.25 }), shadowAt: P.root.position, shadowR: 90 };
    },
    events: [{ t: 0.5, k: 'samLaunch' }, { t: 1.4, k: 'samLaunch', v: 0.8 }],
  };
}
// G06 歼-35 的瞄准吊舱（热像）：阵地里雷达、四辆发射车、指挥车一个个框上、锁定，投弹
async function shotEO35(env, add) {
  const K = await samKit(env, add);
  K.L.forEach(V => thermalize(V, 0.9));
  K.site.traverse(o => {   // 雷达车、指挥车、电源车：热的；沙土掩体：冷的
    if (!o.isMesh || o.material.type === 'MeshBasicMaterial') return;
    const c = o.material.color || new THREE.Color(0.5, 0.5, 0.5);
    const sandy = c.r > 0.6 && c.g > 0.5;
    o.material = new THREE.MeshBasicMaterial({ color: new THREE.Color().setScalar(sandy ? 0.18 : 0.62) });
  });
  let boxes = [];
  const cv = V3();
  return {
    update(t) {
      // 吊舱从东南方 7 公里、高 2 公里往下看，慢慢推近
      const c = V3(SAM.x + 3800, heightAt(SAM.x, SAM.z) + 2600, SAM.z + 5600);
      const look = V3(SAM.x + Math.sin(t * 0.3) * 6, heightAt(SAM.x, SAM.z), SAM.z - 30);
      cam(env, c, look, lerp(2.4, 1.7, ease(t / 4)));
      env.camera.updateMatrixWorld(true);
      const band = env.post.ah / env.H;
      boxes = K.targets.map((p, i) => {
        cv.copy(p).project(env.camera);
        const st = t > 0.6 + i * 0.32 ? (t > 2.6 ? 'lock' : 'trk') : 'scan';
        return { x: 0.5 + cv.x / 2, y: 0.5 - cv.y / 2, s: 0.022, st, label: `T${i + 1}` };
      });
      return { ...night({ exposure: 1.2 }), thermal: 1, therK: 3.2, grain: 0.02, vignette: 0.3, bloom: 0.6, shadowAt: SAM, shadowR: 300, fogDensity: 0.00002 };
    },
    overlay: (g, t, W, H, ah) => drawEO(g, W, H, ah, { t, boxes, zoom: lerp(18, 26, ease(t / 4)), rng: 6.8, alt: 7400, mode: 'WHOT', wpn: '雷石-6 ×4', msg: t > 2.6 ? (t > 3.2 ? '投放' : '全部锁定') : (t > 0.6 ? '跟踪' : '搜索'), laser: t > 2.6 }),
    events: [{ t: 0.6, k: 'beepSoft' }, { t: 1.0, k: 'beepSoft' }, { t: 1.3, k: 'beepSoft' }, { t: 1.6, k: 'beepSoft' }, { t: 2.6, k: 'lockTone' }, { t: 3.2, k: 'release' }],
  };
}
// G07 一枚枚雷石-6 落下来：雷达、发射车、指挥车挨个炸开，发射箱里的导弹殉爆乱飞
async function shotSamHit(env, add) {
  const { fx } = env;
  const K = await samKit(env, add);
  const hits = [0.6, 1.15, 1.7, 2.2, 2.75, 3.2];
  K.targets.forEach((p, i) => {
    const t1 = hits[i];
    const from = p.clone().add(V3(260, 900, 700));
    fx.add((t, f) => {   // 落下来的炸弹（一个小亮点 + 细烟）
      const u = (t - (t1 - 0.9)) / 0.9;
      if (u < 0 || u > 1) return;
      const q = from.clone().lerp(p, u);
      f.addGlow(q, 1.2, new THREE.Color(1, 0.9, 0.8), 2, 1, 0.001);
    });
    fx.add(explosion({ p: p.clone(), t0: t1, s: i === 0 ? 46 : 34, seed: 300 + i, debris: 30, ember: 50 }));
    fx.add(bigFire({ p: p.clone().add(V3(0, -2, 0)), s: 9, t0: t1 + 0.3, seed: 320 + i, dark: 0.08 }));
  });
  // 殉爆：一枚导弹从发射箱里窜出去，打着转乱飞
  const lp = K.targets[2].clone();
  fx.add(missile({ path: tau => { const u = Math.max(0, tau - 1.9); return lp.clone().add(V3(u * 60 + Math.sin(u * 5) * 20, u * 80 - u * u * 10, -u * 30 + Math.cos(u * 4) * 20)); }, t0: 1.9, t1: 4.5, size: 1.6, smokeLife: 4 }));
  return {
    update(t) {
      const c = V3(SAM.x - 430, heightAt(SAM.x - 430, SAM.z + 380) + 34, SAM.z + 380);
      cam(env, c, V3(SAM.x + 10, heightAt(SAM.x, SAM.z) + 22, SAM.z - 30), 36);
      shake(env.camera, t, 0.12 + hits.reduce((a, h) => a + (t > h ? 1.1 * Math.exp(-(t - h) * 3) : 0), 0), 8, 13);
      return { ...night({ moonI: 2.2, exposure: 1.2 }), shadowAt: SAM, shadowR: 400, flash: hits.reduce((a, h) => a + (t > h ? 0.06 * Math.exp(-(t - h) * 14) : 0), 0) };
    },
    titles: t => caption('定点清除', '雷达、发射车、指挥车 —— 6 枚全中', fadeIO(t, 1.0, 4.4, 0.4, 0.4)),
    events: hits.map((h, i) => ({ t: h, k: i === 0 ? 'bigboom' : 'boom', v: 0.9 })).concat([{ t: 1.9, k: 'missileWhoosh' }]),
  };
}
// G08 四机编队从烧着的阵地上空低空冲出来，从镜头左上方掠过，接着拉起爬升、一路放红外诱饵弹；镜头跟着转过去
async function shotJetsAway(env, add) {
  const { fx } = env;
  const K = await samKit(env, add);
  K.targets.forEach((p, i) => fx.add(bigFire({ p: p.clone().add(V3(0, -2, 0)), s: 10, t0: -3 - i, seed: 340 + i, dark: 0.08 })));
  const J = [];
  for (let i = 0; i < 4; i++) { const A = await plane('j31', env); add(A.root); afterburners(A, fx, () => 1, 0.4); J.push(A); }
  const c = V3(SAM.x - 300, heightAt(SAM.x - 300, SAM.z + 500) + 3, SAM.z + 500);
  const SPD = 480, TP = 1.3, W = 0.55, AMAX = 0.9;   // 速度（格 / 秒，约 170 米 / 秒）、掠过镜头的时刻、拉起角速度（约 7 g）、最大爬升角
  const fwd = c.clone().sub(SAM).setY(0).normalize();
  const side = new THREE.Vector3().crossVectors(fwd, V3(0, 1, 0)).normalize();
  const start = c.clone().addScaledVector(fwd, -SPD * TP).addScaledVector(side, -90);   // 正好从阵地上空出来
  start.y = heightAt(start.x, start.z) + 40;
  const center = t => {   // 编队中心：先贴地平飞，掠过镜头前开始拉起（沿圆弧转成爬升）
    const tp = TP - 0.15;
    let dx = SPD * Math.min(t, tp), dy = 0;
    if (t > tp) {
      const p = t - tp, pc = AMAX / W, a = Math.min(p, pc);
      dx += SPD / W * Math.sin(W * a);
      dy += SPD / W * (1 - Math.cos(W * a));
      if (p > pc) { dx += SPD * Math.cos(AMAX) * (p - pc); dy += SPD * Math.sin(AMAX) * (p - pc); }
    }
    return start.clone().addScaledVector(fwd, dx).add(V3(0, dy, 0));
  };
  const OFF = [[0, 0], [-1, 1], [1, 1], [2, 2]];   // 指尖四机：长机、左僚、右僚、右后
  const posOf = (i, t) => center(t).addScaledVector(side, OFF[i][0] * 20).addScaledVector(fwd, -OFF[i][1] * 26).add(V3(0, OFF[i][1] * 2.5, 0));
  // 拉起以后每架放一串诱饵弹（火球往后下方散开、拖着白烟）
  for (let i = 0; i < 4; i++) fx.add(decoys({ from: t => posOf(i, t).addScaledVector(fwd, -6), vel: t => posOf(i, t + 0.05).sub(posOf(i, t)).multiplyScalar(5), t0: TP + 0.3 + (i % 2) * 0.12, n: 10, every: 0.07, spread: 40, seed: 70 + i }));
  const look = V3();
  return {
    update(t) {
      J.forEach((A, i) => {
        const p = posOf(i, t), q = posOf(i, t + 0.02);
        fly(A, p, q.sub(p).normalize(), 0.06 * (i - 1.5) * (1 - smooth(TP - 0.2, TP + 0.4, t)));
      });
      // 镜头跟着编队中心转（仰角收在 65° 以内，不翻过头顶）
      const dv = center(t).sub(c);
      const hz = Math.max(1, Math.hypot(dv.x, dv.z)), el = Math.min(Math.atan2(dv.y, hz), 1.13);
      look.set(c.x + dv.x / hz * Math.cos(el) * 100, c.y + Math.sin(el) * 100, c.z + dv.z / hz * Math.cos(el) * 100);
      cam(env, c, look, lerp(22, 56, smooth(TP - 0.75, TP + 0.15, t)));   // 远的时候长焦（飞机大），掠过时广角
      shake(env.camera, t, 0.3 + 1.6 * Math.exp(-(((t - TP) / 0.3) ** 2)), 9, 17);
      return { ...night({ moonI: 2.0, exposure: 1.15 }), shadowAt: SAM, shadowR: 300 };
    },
    titles: t => caption('任务完成', '四机编队脱离 · 放红外诱饵弹', fadeIO(t, 1.9, 3.0, 0.3, 0.2)),
    events: [{ t: 0, k: 'fireRoar' }, { t: TP - 0.6, k: 'jetPass', v: 1.2 }, { t: TP + 0.3, k: 'flares' }],
  };
}


// ———————————————————————————— 第二幕：无人机远程察打（天快亮） ————————————————————————————
const DAWN0 = () => ({ ...dusk({ el: -2, az: 95, exposure: 0.95, sunI: 2.0, hemiI: 0.6 }), day: 0.55, dawn: 1, moonVis: 0.3, stars: 0.4, cloud: 0.2, heat: 0, fogDensity: 0.00005 });
// 一门 M109 的炮口焰、后坐
function m109Fire(fx, V, times, seed) {
  for (const [i, t0] of times.entries()) fx.add(muzzle({ p: () => V.muzzle(), dir: () => V.muzzleDir(), t0, kind: 'gun', seed: seed + i }));
}
async function battery(env, add, thermal = false) {
  const G = [];
  for (let i = 0; i < 3; i++) {
    const V = await vehicle('m109', env.REPO);
    if (thermal) thermalize(V, 1); else dusty(V);
    add(V.root);
    const x = BATT.x - 70 + i * 70, z = BATT.z + (i % 2) * 18;
    ground(V.root, x, z, Math.PI * 1.0 + 0.05 * (i - 1));   // 炮口朝南（越过岩岭打红方）
    V.aim(0, 0.42);
    G.push(V);
  }
  return G;
}
// G09 攻击-2 在天快亮的高空盘旋，翼下两枚蓝箭-7
async function shotDrone(env, add) {
  const A = await aircraft('mq9', env.REPO);
  A.gearDown(false);
  A.root.traverse(o => { if (o.isMesh && o.material) { const m = o.material.clone(); m.map = null; m.color = new THREE.Color(0.55, 0.57, 0.58); m.roughness = 0.6; o.material = m; } });   // 攻击-2：浅灰涂装（不贴原机的贴图）
  add(A.root);
  const py = A.M.pyl && A.M.pyl.gj2;
  if (py) for (const k of [2, 3]) { const m = lj7(); m.position.set(py[k][2], py[k][0] - 0.9, py[k][1]); m.rotation.y = 0; A.root.add(m); }
  const c0 = V3(BATT.x - 9000, 3400, BATT.z + 8000);
  return {
    update(t) {
      const a = 0.9 + t * 0.03;
      const p = c0.clone().add(V3(Math.cos(a) * 1200, 0, Math.sin(a) * 1200));
      const d = V3(-Math.sin(a), 0, Math.cos(a));
      fly(A, p, d, -0.18);   // 顺时针盘旋（往右转）：往右压坡度
      A.spin && A.spin(t, 0.6);
      const cp = A.root.localToWorld(V3(30, 3, 26));
      cam(env, cp, A.root.localToWorld(V3(-12, -3, -50)), 34);
      shake(env.camera, t, 0.12, 0.6, 9);
      return { ...DAWN0(), shadowAt: p, shadowR: 60, fogDensity: 0.00011 };
    },
    titles: t => caption('红方 · 攻击-2 察打一体无人机', '高度 7600 米 · 离目标 11 公里', fadeIO(t, 0.4, 3.0, 0.4, 0.4)),
    events: [{ t: 0, k: 'droneHum' }],
  };
}
// G10 无人机光电球（热像）：岭北的 M109 炮兵阵地正在开火（炮口一团团发白），十字线压住中间那门，激光照射，蓝箭-7 发射
async function shotDroneEO(env, add) {
  const { fx } = env;
  const G = await battery(env, add, true);
  G.forEach((V, i) => m109Fire(fx, V, [0.3 + i * 0.45, 2.4 + i * 0.4], 400 + i * 10));
  return {
    update(t) {
      const tgt = G[1].root.position.clone().add(V3(0, 3, 0));
      const c = tgt.clone().add(V3(-6200, 7600, 7200));
      const kick = i => { const ts = [0.3 + i * 0.45, 2.4 + i * 0.4]; let k = 0; for (const s of ts) if (t > s) k = Math.max(k, Math.exp(-(t - s) * 6) * (1 - Math.exp(-(t - s) * 60))); return k; };
      G.forEach((V, i) => { V.kick(kick(i)); V.root.updateMatrixWorld(true); });
      cam(env, c, tgt.clone().add(V3(Math.sin(t * 2.1) * 0.6, 0, Math.cos(t * 1.7) * 0.6)), lerp(1.3, 0.85, ease(t / 3.5)));
      return { ...DAWN0(), thermal: 1, therK: 2.2, grain: 0.025, bloom: 0.5, vignette: 0.25, shadowAt: tgt, shadowR: 200, fogDensity: 0.00001 };
    },
    overlay: (g, t, W, H, ah) => drawDrone(g, W, H, ah, { t, alt: 24900, rng: 11.6, hdg: 318, laser: t > 1.2, wpn: t > 2.1 ? '蓝箭-7  1 / 2  发射' : '蓝箭-7  2 / 2', tof: t > 2.1 ? 14 - (t - 2.1) : null, msg: t > 2.1 ? '发射' : (t > 1.2 ? '激光照射' : '') }),
    events: [{ t: 0.3, k: 'artyFar' }, { t: 0.75, k: 'artyFar' }, { t: 1.2, k: 'beepSoft' }, { t: 2.1, k: 'release' }],
  };
}
// G11 热像里一道白光从天上扎下来，M109 炸开；接着是外面：天亮了，炮车在烧、炮弹殉爆
async function shotDroneHit(env, add) {
  const { fx } = env;
  const G = await battery(env, add, true);
  const tgt = G[1].root.position.clone().add(V3(0, 4, 0));
  const tH = 1.1;
  fx.add((t, f) => {   // 落下来的蓝箭-7：热像里一个亮点拖着尾巴
    const u = (t - (tH - 0.6)) / 0.6;
    if (u < 0 || u > 1) return;
    const a = tgt.clone().add(V3(-900, 1300, 1000)), q = a.lerp(tgt, u), q2 = tgt.clone().add(V3(-900, 1300, 1000)).lerp(tgt, Math.max(0, u - 0.08));
    f.addStreak(q2, q, 1.5, new THREE.Color(1, 1, 1), 18, 0.5, 0.002);
  });
  fx.add(explosion({ p: tgt, t0: tH, s: 30, seed: 450, debris: 30, ember: 40 }));
  fx.add(cookoff({ p: tgt.clone().add(V3(0, 1, 0)), t0: tH + 0.4, seed: 451 }));
  return {
    update(t) {
      const c = tgt.clone().add(V3(-6200, 7600, 7200));
      cam(env, c, tgt.clone(), 0.85);
      shake(env.camera, t, t > tH ? 0.04 * Math.exp(-(t - tH) * 4) : 0, 8, 3);
      return { ...DAWN0(), thermal: 1, therK: 2.2, grain: 0.025, bloom: 0.8, vignette: 0.25, shadowAt: tgt, shadowR: 200, fogDensity: 0.00001 };
    },
    overlay: (g, t, W, H, ah) => drawDrone(g, W, H, ah, { t, alt: 24900, rng: 11.6, hdg: 318, laser: t < tH, wpn: '蓝箭-7  1 / 2', tof: Math.max(0, tH - t), msg: t > tH + 0.3 ? '命中' : '' }),
    events: [{ t: tH, k: 'boomFar' }],
  };
}
async function shotBattBurn(env, add) {
  const { fx } = env;
  const G = await battery(env, add, false);
  burnt(G[1]);
  const p = G[1].root.position.clone();
  fx.add(bigFire({ p: p.clone(), s: 10, t0: -4, seed: 460, dark: 0.09 }));
  fx.add(cookoff({ p: p.clone().add(V3(0, 3, 0)), t0: 0.4, seed: 461 }));
  fx.add(explosion({ p: p.clone().add(V3(4, 2, 2)), t0: 1.6, s: 16, seed: 462, debris: 12, dust: false }));
  add(clutter(p.x, p.z, 300, { seed: 46 }));
  return {
    update(t) {
      const c = p.clone().add(V3(-150 + t * 6, 0, 120)); c.y = heightAt(c.x, c.z) + 6;
      cam(env, c, p.clone().add(V3(0, 8, 0)), 30);
      shake(env.camera, t, 0.15 + (t > 1.6 ? 0.8 * Math.exp(-(t - 1.6) * 3) : 0), 5, 4);
      return { ...dusk({ el: 1.5, az: 95, exposure: 0.95, sunI: 4.5 }), shadowAt: p, shadowR: 140 };
    },
    titles: t => caption('无人机远程摧毁', '岭北炮兵阵地 · 11.6 公里外', fadeIO(t, 0.4, 3.0, 0.4, 0.4)),
    events: [{ t: 0, k: 'fireRoar' }, { t: 0.4, k: 'cookoff' }, { t: 1.6, k: 'boom', v: 0.6 }],
  };
}

// ———————————————————————————— 第三幕：坦克集群对轰 ————————————————————————————
const DAY = (o = {}) => day({ el: 26, az: 110, ...o });
// 低沙梁的脊线：沿 x 往南北扫，找局部最高点（M1A2 停在脊线北边 18 格，车体藏住、炮塔露出来）
function crestNear(x, z0) {
  let best = z0, bh = -1e9;
  for (let z = z0 - 160; z <= z0 + 160; z += 4) { const h = heightAt(x, z); if (h > bh) { bh = h; best = z; } }
  return best;
}
const BLUE_X = [-640, -560, -480, -400];   // M1A2 排（车间距 80 格）
const RED = [[-2300, 6300], [-1700, 6150], [-1100, 6050], [-500, 6180], [100, 6320], [700, 6480]];   // 99A 楔形
const redAt = (i, t) => { const [x, z] = RED[i]; return V3(x + t * 1.5, 0, z - t * 15); };   // 往北压（每秒 15 格 ≈ 19 公里 / 时）
async function tanks(env, add, key, n, opt = {}) {
  const L = [];
  for (let i = 0; i < n; i++) { const V = await vehicle(key, env.REPO); if (opt.thermal) thermalize(V, 1); else dusty(V); add(V.root); L.push(V); }
  return L;
}
// G12 天刚亮：99A 纵队从边境沙墙的开口开过去，扬起的沙被逆光照成金色
async function shotBreach(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'ztz99a2', 5);
  const bz = 7600;
  const path = (i, t) => V3(-1200 + Math.sin((t - i * 2.4) * 0.2) * 2, 0, bz + 50 + i * 52 - t * 16);
  L.forEach((V, i) => fx.add(dustTrail({ path: tt => { const p = path(i, tt); p.y = heightAt(p.x, p.z); return p.add(V3(0, 0, 14)); }, t0: -4, s: 1.4, gap: 8, life: 7, col: [1.05, 0.86, 0.6], alpha: 0.42, seed: 500 + i })));
  add(clutter(-1200, bz, 380, { seed: 51, avoid: (x, z) => Math.abs(x + 1200) < 18 }));
  return {
    update(t) {
      L.forEach((V, i) => { const p = path(i, t); ground(V.root, p.x, p.z, 0); V.roll(-(p.z)); V.aim(0.1 * Math.sin(i), 0.02); });
      const c = V3(-1200 + 46, 0, bz - 14); c.y = heightAt(c.x, c.z) + 6;
      cam(env, c, V3(-1206, heightAt(-1200, bz + 90) + 5, bz + 110), 38);
      shake(env.camera, t, 0.18, 2, 5);
      return { ...dusk({ el: 3.5, az: 95, exposure: 0.85, dust: 0.6 }), shadowAt: V3(-1200, 12, bz + 100), shadowR: 260 };
    },
    titles: t => caption('红方 · 99A 坦克营', '越过边境沙墙', fadeIO(t, 0.6, 4.4, 0.5, 0.4)),
    events: [{ t: 0, k: 'tankColumn' }, { t: 0.5, k: 'desertWind' }],
  };
}
// G13 白天：一个坦克排（6 辆 99A）楔形队形压过开阔的平原，一路扬尘；镜头从右后上方跟着队形一起往前飞（像跟拍的无人机）
//   车间距照条令（排内 45～55 米 ≈ 140 格，往后错开 90 格）；这是镜头里的一个排，不是全营那条 600 格间距的大楔形（RED）
const WEDGE = [[0, 0], [-1, 1], [1, 1], [-2, 2], [2, 2], [3, 3]];
async function shotWedge(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'ztz99a2', 6);
  const O = V3(-1300, 0, 5400), SP = 17;   // 长机起点、速度（格 / 秒，约 22 公里 / 时）
  const at = (i, t) => V3(O.x + WEDGE[i][0] * 140 + Math.sin(t * 0.4 + i) * 3, 0, O.z + WEDGE[i][1] * 90 - t * SP);
  L.forEach((V, i) => fx.add(dustTrail({ path: tt => { const p = at(i, tt); p.y = heightAt(p.x, p.z); return p.add(V3(0, 0, 14)); }, t0: -6, s: 1.7, gap: 7, life: 9, alpha: 0.5, col: [1.15, 1.0, 0.78], seed: 520 + i })));
  add(clutter(O.x, O.z, 520, { seed: 53 }));
  return {
    update(t) {
      L.forEach((V, i) => { const p = at(i, t); ground(V.root, p.x, p.z, 0); V.roll(-p.z); V.aim(0.04 * (i - 2.5), 0.015); });
      const lead = at(0, t);
      const c = V3(lead.x + 330 - t * 8, 0, lead.z + 420 - t * 5); c.y = heightAt(c.x, c.z) + 22;   // 右翼后面、低一点：右边两辆就在跟前
      const look = V3(lead.x + 50, heightAt(lead.x, lead.z) + 3, lead.z + 40);
      cam(env, c, look, 27);
      shake(env.camera, t, 0.12, 1.2, 9);
      return { ...DAY({ heat: 0.5, dust: 0.15, fog: 0.000012 }), shadowAt: V3(lead.x, 12, lead.z + 150), shadowR: 420 };
    },
    titles: t => caption('红方 · 99A 坦克排', '楔形队形 · 车距 50 米', fadeIO(t, 0.5, 3.3, 0.4, 0.3)),
    events: [{ t: 0, k: 'tankEngines' }],
  };
}
// G14 蓝方 M1A2 排趴在沙梁后面，只露炮塔；炮塔转过来对着远处的扬尘
async function shotHullDown(env, add) {
  const L = await tanks(env, add, 'm1a2dc', 4);
  const pos = BLUE_X.map(x => { const zc = crestNear(x, 3350); return V3(x, 0, zc - 20); });
  add(clutter(-300, 3300, 420, { seed: 61 }));
  return {
    update(t) {
      L.forEach((V, i) => { ground(V.root, pos[i].x, pos[i].z, Math.PI + 0.08 * (i - 1.5)); V.aim(lerp(0.4, -0.02, smooth(0.3, 2.2, t + i * 0.2)), 0.015); });
      const mid = pos[1].clone().lerp(pos[2], 0.5);
      const c = mid.clone().add(V3(-120, 0, 620)); c.y = heightAt(c.x, c.z) + 4.5;
      cam(env, c, mid.clone().add(V3(0, 9, 0)), 7.5);
      shake(env.camera, t, 0.05, 1.5, 7);
      return { ...DAY({ heat: 0.9 }), shadowAt: pos[1], shadowR: 160 };
    },
    titles: t => caption('蓝方 · M1A2 SEPv3', '车体藏在沙梁后面，只露炮塔', fadeIO(t, 0.4, 3.6, 0.4, 0.4)),
    events: [{ t: 0.3, k: 'turretWhine' }],
  };
}
// 两边坦克的位置（炮长视角、击毁镜头共用）
const M1POS = () => BLUE_X.map(x => { const zc = crestNear(x, 3350); const p = V3(x, 0, zc - 20); p.y = heightAt(p.x, p.z); return p; });
// G15 M1A2 炮长瞄准镜（热像）：十字压住 2.3 公里外的一辆 99A，激光测距，开火
async function shotSightM1(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'ztz99a2', 3, { thermal: true });
  const fireT = 1.7;
  return {
    update(t) {
      L.forEach((V, i) => { const p = redAt(i + 2, 9 + t); ground(V.root, p.x, p.z, -0.1); V.aim(0, 0.01); });
      const me = M1POS()[1].clone().add(V3(0, 7.5, 0));
      const tgt = L[1].root.position.clone().add(V3(0, 4, 0));
      const k = t > fireT ? Math.exp(-(t - fireT) * 5) : 0;
      cam(env, me, tgt.clone().add(V3(0, k * 30 + Math.sin(t * 1.3) * 0.6, 0)), 1.6);
      return { ...DAY({ heat: 1.6 }), thermal: 1, therK: 0.7, grain: 0.02, vignette: 0.2, bloom: 0.4, flash: t > fireT ? 0.5 * Math.exp(-(t - fireT) * 12) : 0, shadowAt: tgt, shadowR: 200, fogDensity: 0.00002 };
    },
    overlay: (g, t, W, H, ah) => drawSightM1(g, W, H, ah, { t, range: t > 0.8 ? 2342 : 0, ammo: 'SABOT', ready: t < fireT, msg: t > 0.8 && t < fireT ? 'ON THE WAY' : '' }),
    events: [{ t: 0.8, k: 'laser' }, { t: fireT, k: 'tankFire', v: 1 }],
  };
}
// G16 那发脱壳穿甲弹打在 99A 炮塔正面：反应装甲殉爆、一团火光灰烟——车没事，接着往前开
async function shotEra(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'ztz99a2', 3);
  const tHit = 0.9;
  const hitP = () => L[1].root.localToWorld(V3(0.6, 6.4, -6.8));
  fx.add(sabot({ from: () => hitP().clone().add(V3(260, 6, -2400)), to: hitP, t0: tHit - 0.52 }));
  fx.add(armorHit({ p: hitP, t0: tHit, era: true, seed: 610 }));
  L.forEach((V, i) => fx.add(dustTrail({ path: tt => { const p = redAt(i + 2, 10 + tt); p.y = heightAt(p.x, p.z); return p.add(V3(0, 0, 14)); }, t0: -5, s: 1.5, gap: 8, life: 7, alpha: 0.42, seed: 620 + i })));
  return {
    update(t) {
      L.forEach((V, i) => { const p = redAt(i + 2, 10 + t); ground(V.root, p.x, p.z, -0.1); V.roll(-p.z); V.aim(-0.15, 0.02); });
      L[1].root.rotateX(t > tHit ? -0.012 * Math.exp(-(t - tHit) * 5) : 0);
      const tp = L[1].root.position;
      const c = tp.clone().add(V3(64, 0, -40)); c.y = heightAt(c.x, c.z) + 5;
      cam(env, c, tp.clone().add(V3(-4, 5, 4)), 30);
      shake(env.camera, t, 0.2 + (t > tHit ? 1.4 * Math.exp(-(t - tHit) * 4) : 0), 6, 9);
      return { ...DAY({ heat: 0.7 }), shadowAt: tp, shadowR: 120 };
    },
    titles: t => caption('爆炸反应装甲', '穿甲弹打在炮塔正面 —— 挡住了，接着打', fadeIO(t, 1.2, 3.4, 0.4, 0.4)),
    events: [{ t: tHit - 0.3, k: 'sabotWhizz' }, { t: tHit, k: 'eraBlast' }],
  };
}
// G17 99A 车内：炮长位，几块屏幕，自动装弹机把弹送进炮膛；开炮那一下整个车里一震
async function shotIn99(env, add) {
  const I = await interior(env, 'ztz99a', { lights: 0.45, screenGlow: 1.8 });
  add(I.root);
  I.root.position.set(0, 3000, 0);   // 摆在天上（只看车里）
  I.root.updateMatrixWorld(true);
  const C = I.cams.gunner || Object.values(I.cams)[0];
  const scr = I.screens.find(s => s.page === 'gunsight') || I.screens.find(s => s.page === 'fcscn') || I.screens[0];
  const fireT = 2.0;
  return {
    update(t) {
      const m = new THREE.Matrix4().makeTranslation(0, 3000, 0).multiply(C.m);
      const eye = new THREE.Vector3().setFromMatrixPosition(m);
      const fwd = new THREE.Vector3(0, 0, -1).transformDirection(m);
      const right = new THREE.Vector3(1, 0, 0).transformDirection(m);
      I.root.updateMatrixWorld(true);
      const sc = scr ? new THREE.Vector3().setFromMatrixPosition(scr.mesh.matrixWorld) : eye.clone().addScaledVector(fwd, 1.2);
      const pos = eye.clone().addScaledVector(fwd, -0.1).addScaledVector(right, 0.25).add(V3(0, 0.08, 0)).lerp(sc, 0.18 + 0.1 * smooth(0, 3.4, t));
      const k = t > fireT ? Math.exp(-(t - fireT) * 7) : 0;
      cam(env, pos, sc.clone().add(V3(0, 0.05, 0)), 58);
      shake(env.camera, t, 0.25 + k * 6, 9, 11);
      return { exposure: 0.85, bloom: 1.2, moonI: 0, hemiI: 0.12, hemiSky: 0x302820, hemiGround: 0x100c08, day: 0, fogDensity: 0, flash: t > fireT ? 0.18 * Math.exp(-(t - fireT) * 14) : 0, grain: 0.022, vignette: 0.75 };
    },
    titles: t => caption('99A · 炮长位', '自动装弹机 · 热像仪 · 激光测距', fadeIO(t, 0.4, 3.3, 0.4, 0.4)),
    events: [{ t: 0.5, k: 'autoloader' }, { t: fireT, k: 'tankFireIn' }],
  };
}
// G17 99A 开炮：炮口焰、车前地上被冲击波掀起一圈沙尘，车身往后一坐，脱壳穿甲弹的曳光飞出去
async function shotMuzzle99(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'ztz99a2', 1);
  const V = L[0];
  const p = V3(-300, 0, 5400);
  const fireT = 0.9;
  fx.add(muzzle({ p: () => V.muzzle(), dir: () => V.muzzleDir(), t0: fireT, kind: 'tank', seed: 680 }));
  fx.add(sabot({ from: () => V.muzzle(), to: () => V.muzzle().addScaledVector(V.muzzleDir(), 2600), t0: fireT, bright: 14, w: 0.7 }));
  fx.add((t, f) => {   // 炮口前方、车四周掀起的沙尘环
    const u = t - fireT;
    if (u < 0 || u > 4) return;
    const m = V.muzzle(), d = V.muzzleDir().setY(0).normalize();
    for (let i = 0; i < 18; i++) {
      const a = i / 18 * Math.PI * 2, r = 4 + 30 * (1 - Math.exp(-u * 3)) * (0.7 + 0.3 * Math.sin(i * 2.7));
      const c = m.clone().addScaledVector(d, 6 + 10 * (1 - Math.exp(-u * 2)));
      const size = 9 + u * 7;
      c.add(V3(Math.cos(a) * r, 0, Math.sin(a) * r));
      c.y = heightAt(c.x, c.z) + size * 0.46 + u * 1.5;
      f.sprite('puff', c.addScaledVector(f.wind, u), size, 8 + u * 10, 0.6 * (1 - u / 4) * smooth(0, 0.06, u), 0, [0.95, 0.82, 0.6], a);
    }
  });
  add(clutter(p.x, p.z, 260, { seed: 68 }));
  return {
    update(t) {
      ground(V.root, p.x, p.z, 0.15);
      const k = t > fireT ? Math.exp(-(t - fireT) * 6) * (1 - Math.exp(-(t - fireT) * 60)) : 0;
      V.kick(k); V.aim(-0.05, 0.03);
      V.root.rotateX(k * 0.02);
      V.root.updateMatrixWorld(true);
      const c = V.root.localToWorld(V3(40, 3, -44)); c.y = Math.max(c.y, heightAt(c.x, c.z) + 2.5);
      cam(env, c, V.root.localToWorld(V3(0, 5, -8)), 34);
      shake(env.camera, t, 0.15 + (t > fireT ? 2.4 * Math.exp(-(t - fireT) * 4) : 0), 7, 17);
      return { ...DAY({ heat: 0.6 }), shadowAt: V.root.position, shadowR: 70 };
    },
    titles: t => caption('99A · 125 毫米滑膛炮', '炮口冲击波把车前的沙掀起来一圈', fadeIO(t, 1.4, 2.9, 0.3, 0.3)),
    events: [{ t: 0, k: 'tankIdle' }, { t: fireT, k: 'tankFire', v: 1 }],
  };
}
// 炮塔被殉爆顶起来（G18、G19 共用）：初速往上 23 格 / 秒（顶起 3.5 米左右）、往旁边一点，慢慢翻（每秒 1.3 弧度），
//   落到车旁边的地上就停住、歪着（用户 11-22：掀盖有点尴尬——原来往上 34～38 格 / 秒、每秒翻 3 弧度多，在 12 倍瞄准镜里像气球一样飘上天）
function tossAt(p0, q0, u, groundY, axis, side) {
  const vy = 23, g = 27, vx = side.x, vz = side.z;
  const yf = p0.y - groundY - 1.2;   // 落到离地 1.2 格（炮塔底面着地）
  const tl = (vy + Math.sqrt(vy * vy + 2 * g * yf)) / g;   // 落地时刻
  const w = Math.min(u, tl);
  const pos = p0.clone().add(V3(vx * w, vy * w - 0.5 * g * w * w, vz * w));
  const rot = new THREE.Quaternion().setFromAxisAngle(axis, Math.min(u, tl) * 1.3);
  return { pos, quat: q0.clone().multiply(rot), landed: u >= tl };
}
// G18 99A 炮长热像仪：沙梁后面露出来的 M1A2 炮塔，测距 2410，开火——弹药殉爆，一团白热的火球，炮塔被顶起来翻落到车旁
async function shotSight99(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'm1a2dc', 4, { thermal: true });
  const P = M1POS();
  const fireT = 1.3, hitT = 1.85;
  const victim = 1;
  const turret = () => L[victim].root.localToWorld(V3(0, 5.2, -1));
  fx.add(explosion({ p: turret(), t0: hitT, s: 30, seed: 640, debris: 20, ember: 30 }));                          // 穿甲弹打进去
  fx.add(explosion({ p: turret().add(V3(0, 2, 0)), t0: hitT + 0.12, s: 52, seed: 642, debris: 28, ember: 60 }));   // 弹药殉爆：一大团火球
  fx.add(cookoff({ p: () => L[victim].root.localToWorld(V3(0, 4.6, 0)), t0: hitT + 0.2, seed: 641 }));
  fx.add(bigFire({ p: L[victim].root.localToWorld(V3(0, 4.2, 0)), s: 12, t0: hitT + 0.35, seed: 643, dark: 0.12 }));   // 炮塔座圈里往上喷的火柱
  fx.add((t, f) => {   // 热像里殉爆是一大团白：一圈白热的光，慢慢收成座圈上那根火柱
    const u = t - hitT - 0.12;
    if (u < 0 || u > 2.5) return;
    const c = L[victim].root.localToWorld(V3(0, 7 + u * 3, 0));
    f.addGlow(c, 22 + 18 * (1 - Math.exp(-u * 4)), new THREE.Color(1, 0.95, 0.85), 26 * Math.exp(-u * 2.2) + 4, 1, 0.0006);
    f.addLight(c, new THREE.Color(1, 0.7, 0.4), 30 * Math.exp(-u * 2), 260);
  });
  let toss = null;
  return {
    update(t) {
      L.forEach((V, i) => { ground(V.root, P[i].x, P[i].z, Math.PI + 0.08 * (i - 1.5)); V.aim(0, 0.015); });
      if (t > hitT + 0.1 && !toss) { toss = { g: L[victim].tur, p0: new THREE.Vector3(), q0: new THREE.Quaternion() }; L[victim].tur.updateMatrixWorld(true); env.scene.attach(L[victim].tur); toss.p0.copy(L[victim].tur.position); toss.q0.copy(L[victim].tur.quaternion); }
      if (toss) {
        const r = tossAt(toss.p0, toss.q0, t - hitT - 0.1, heightAt(toss.p0.x + 3, toss.p0.z + 2), V3(0.7, 0.15, 0.7).normalize(), V3(2.4, 0, 1.6));
        toss.g.position.copy(r.pos); toss.g.quaternion.copy(r.quat);
      }
      const me = redAt(3, 13).clone(); me.y = heightAt(me.x, me.z) + 6.5;
      const tgt = turret();
      const k = t > fireT ? Math.exp(-(t - fireT) * 5) : 0;
      cam(env, me, tgt.clone().add(V3(0, k * 25 + Math.sin(t * 1.1) * 0.5, 0)), 1.5);
      const fl = (t > fireT ? 0.5 * Math.exp(-(t - fireT) * 12) : 0) + (t > hitT + 0.12 ? 0.3 * Math.exp(-(t - hitT - 0.12) * 7) : 0);
      return { ...DAY({ heat: 1.6 }), thermal: 1, therK: 0.7, grain: 0.02, vignette: 0.2, bloom: 0.9, flash: fl, shadowAt: tgt, shadowR: 200, fogDensity: 0.00002 };
    },
    overlay: (g, t, W, H, ah) => drawSight99(g, W, H, ah, { t, range: t > 0.5 ? 2410 : 0, ready: t < fireT, ammo: '穿甲弹', msg: t > hitT + 0.3 ? '击毁' : '' }),
    events: [{ t: 0.5, k: 'laser' }, { t: fireT, k: 'tankFire', v: 1 }, { t: hitT, k: 'bigboom', v: 0.6 }],
    dispose: () => { if (toss) env.scene.remove(toss.g); },
  };
}
// G19 外面看：M1A2 的炮塔被整个掀上天，车体里往上喷火（慢动作）
async function shotToss(env, add) {
  const { fx } = env;
  const L = await tanks(env, add, 'm1a2dc', 2);
  const P = M1POS();
  const V = L[0];
  ground(V.root, P[1].x, P[1].z, Math.PI);
  ground(L[1].root, P[0].x, P[0].z, Math.PI);
  const tm = t => 0.25 + t * 0.32;   // 慢动作：片子里 1 秒 = 0.32 秒
  const hit = 0.3;
  fx.add(explosion({ p: V.root.localToWorld(V3(0, 5.5, -1)), t0: hit, s: 32, seed: 650, debris: 26, ember: 50 }));
  fx.add(explosion({ p: V.root.localToWorld(V3(0, 7.5, 0)), t0: hit + 0.1, s: 50, seed: 652, debris: 30, ember: 70 }));   // 殉爆的大火球把炮塔大半吞住
  fx.add(cookoff({ p: V.root.localToWorld(V3(0, 4.5, 0)), t0: hit + 0.1, seed: 651, s: 1.3 }));
  fx.add(bigFire({ p: V.root.localToWorld(V3(0, 4.2, 0)), s: 13, t0: hit + 0.25, seed: 653, dark: 0.1 }));   // 座圈里往上喷火
  V.tur.updateMatrixWorld(true);
  env.scene.attach(V.tur); add(V.tur);
  const p0 = V.tur.position.clone(), q0 = V.tur.quaternion.clone();
  return {
    tmap: tm,
    update(t) {
      const tt = tm(t), u = Math.max(0, tt - hit - 0.08);
      const r = tossAt(p0, q0, u, heightAt(p0.x + 3, p0.z + 2), V3(0.7, 0.2, 0.6).normalize(), V3(2.6, 0, 1.8));
      V.tur.position.copy(r.pos); V.tur.quaternion.copy(r.quat);
      const c = P[1].clone().add(V3(130, 0, -70)); c.y = heightAt(c.x, c.z) + 8;
      cam(env, c, P[1].clone().add(V3(0, 10 + u * 4, 0)), 26);
      shake(env.camera, t, 0.2 + (tt > hit ? 0.9 * Math.exp(-(tt - hit) * 3) : 0), 4, 13);
      return { ...DAY({ heat: 0.6 }), shadowAt: P[1], shadowR: 120 };
    },
    titles: t => caption('开罐', '弹药殉爆，炮塔整个掀飞', fadeIO(t, 0.8, 3.6, 0.4, 0.4)),
    events: [{ t: 0, k: 'slowBoom' }],
  };
}
// G20 大场面：沙梁上下两边互相开火，曳光交错，几处残骸在烧，一辆 99A 也被打爆
async function shotMelee(env, add) {
  const { fx } = env;
  const R0 = await tanks(env, add, 'ztz99a2', 6);
  const B0 = await tanks(env, add, 'm1a2dc', 4);
  const P = M1POS();
  const RR = rng(660);
  const fires = [];
  const LINE = i => V3(-260 - i * 62, 0, 5300 + i * 22);   // 镜头前的一排 99A（往西一字排开、车头朝北）
  R0.forEach((V, i) => { const p = i < 4 ? LINE(i) : redAt(i, 16); ground(V.root, p.x, p.z, -0.05 + 0.04 * i); });
  B0.forEach((V, i) => ground(V.root, P[i].x, P[i].z, Math.PI));
  burnt(B0[1]); burnt(R0[4]);
  fx.add(bigFire({ p: B0[1].root.position.clone().add(V3(0, 3, 0)), s: 9, t0: -6, seed: 661 }));
  fx.add(bigFire({ p: R0[4].root.position.clone().add(V3(0, 3, 0)), s: 8, t0: -2, seed: 662 }));
  const shots = [];
  // 镜头前这一排 99A 依次开火；蓝方的穿甲弹从北边飞来，一发打在第三辆上
  [0.35, 0.9, 1.5, 2.1, 3.0].forEach((t0, k) => shots.push({ t: t0, shooter: R0[[0, 1, 3, 0, 1][k]], target: B0[[0, 2, 3, 0, 3][k]] }));
  for (const s of shots) {
    fx.add(muzzle({ p: () => s.shooter.muzzle(), dir: () => s.shooter.muzzleDir(), t0: s.t, kind: 'tank', seed: Math.floor(s.t * 100) }));
    fx.add(sabot({ from: () => s.shooter.muzzle(), to: () => s.target.root.position.clone().add(V3(0, 4, 0)), t0: s.t, bright: 14, w: 0.7 }));
  }
  const hit3 = R0[2].root.position.clone().add(V3(0, 5, 0));
  fx.add(sabot({ from: hit3.clone().add(V3(80, 10, -2500)), to: hit3, t0: 2.6 - 0.53, bright: 14, w: 0.7 }));
  fx.add(explosion({ p: hit3, t0: 2.6, s: 28, seed: 663, debris: 26 }));
  fx.add(cookoff({ p: R0[2].root.position.clone().add(V3(0, 4, 0)), t0: 2.7, seed: 664 }));
  for (const [x, t0] of [[-90, 1.2], [-420, 3.3]]) fx.add(explosion({ p: gp(x, 5180, 1), t0, s: 14, seed: 670 + t0 * 10, debris: 10 }));   // 打偏的弹在地上炸起沙
  return {
    update(t) {
      for (const V of [...R0, ...B0]) {
        let k = 0;
        for (const s of shots) if (s.shooter === V && t > s.t) k = Math.max(k, Math.exp(-(t - s.t) * 6) * (1 - Math.exp(-(t - s.t) * 60)));
        V.kick(k);
        const tgt = (R0.includes(V) ? B0[0] : R0[1]).root.position;
        V.aim(headingTo(V.root.position, tgt) - V.root.rotation.y, 0.012);
        V.root.updateMatrixWorld(true);
      }
      const c = V3(-60 - t * 5, 0, 5470); c.y = heightAt(c.x, c.z) + 6;
      cam(env, c, V3(-400, 10, 5300), 36);
      shake(env.camera, t, 0.25, 2, 21);
      return { ...DAY({ heat: 1.0, dust: 0.5 }), shadowAt: V3(-700, 12, 4600), shadowR: 2000 };
    },
    titles: t => caption('坦克集群对轰', '2 公里外互相开罐', fadeIO(t, 0.5, 3.8, 0.4, 0.4)),
    events: shots.map(s => ({ t: s.t, k: 'tankFireFar', v: 0.7 })).concat([{ t: 2.6, k: 'bigboom', v: 0.8 }]),
  };
}

// ———————————————————————————— 第四幕：阿帕奇对防空车 ————————————————————————————
const COL = (i, t) => V3(-9400 + i * 70 + t * 9, 0, -300 + Math.sin(i * 1.3) * 6);   // 红方纵队（6 号公路往东开）
const HELI0 = V3(-8350, 0, -3880);   // 阿帕奇从方山南边冒出来
async function apache(env, add, n = 2) {
  const H = [];
  for (let i = 0; i < n; i++) {
    const A = await plane('ah64', env);
    add(A.root);
    const py = A.M.pyl && A.M.pyl.ah64e;
    A.hf = [];
    if (py) for (const k of [0, 1, 2, 3]) { const m = hellfire(); m.position.set(py[k][2], py[k][0] - 0.8, py[k][1]); A.root.add(m); A.hf.push(m); }
    const d = new THREE.Mesh(new THREE.CircleGeometry(24, 48), new THREE.MeshBasicMaterial({ color: 0x0d0f10, transparent: true, opacity: 0.07, depthWrite: false, side: THREE.DoubleSide }));
    d.rotation.x = -Math.PI / 2; if (A.rot.rotor) A.rot.rotor.add(d);
    H.push(A);
  }
  return H;
}
async function column(env, add) {
  const keys = ['zbd97', 'ztz99a2', 'zbd97', 'ztz99a2', 'zbd97', 't625'];
  const L = [];
  for (const k of keys) { const V = await vehicle(k, env.REPO); dusty(V); add(V.root); L.push(V); }
  return L;
}
const heliPos = (i, t) => { const rise = smooth(0.2, 2.2, t); const p = HELI0.clone().add(V3(i * 70, 0, i * 20)); p.y = 108 + 4 + rise * 22 + Math.sin(t * 1.1 + i) * 0.6; return p; };
// G21 两架阿帕奇从方山后面升起来，旋翼把山顶的沙吹得一圈圈滚开；机头炮塔转过来
async function shotApacheUp(env, add) {
  const { fx } = env;
  const H = await apache(env, add);
  H.forEach((A, i) => fx.add(rotorWash({ at: t => heliPos(i, t), ground: heightAt, seed: 700 + i, r: 30 })));
  return {
    update(t) {
      H.forEach((A, i) => { const p = heliPos(i, t); fly(A, p, V3(-0.15, -0.05, 1).normalize(), 0.02 * Math.sin(t + i)); A.spin(t + i * 0.3, 0.9); A.gunAim(lerp(0.35, 0, smooth(0.8, 2.4, t)), lerp(-0.1, -0.08, t / 3)); });
      const c = V3(-8150, 0, -3200); c.y = heightAt(c.x, c.z) + 14;
      cam(env, c, heliPos(0, t).add(V3(30, -6, 0)), 30);
      shake(env.camera, t, 0.25, 3, 23);
      return { ...DAY({ az: 140, el: 34, heat: 0.8 }), shadowAt: HELI0, shadowR: 200 };
    },
    titles: t => caption('蓝方 · AH-64E 阿帕奇', '从方山背后冒出来', fadeIO(t, 0.6, 3.3, 0.4, 0.4)),
    events: [{ t: 0, k: 'rotor' }],
  };
}
// G22 地狱火出轨（近景），接着 4 公里外的红方纵队里两辆车炸开
async function shotHellfire(env, add) {
  const { fx } = env;
  const H = await apache(env, add, 1);
  const A = H[0];
  const L0 = 0.4;
  const hfPath = tau => { const u = Math.max(0, tau - L0); A.root.updateMatrixWorld(true); const p = A.hf[0] ? A.root.localToWorld(A.hf[0].position.clone()) : heliPos(0, 3); return p.add(V3(0, u * 4, -(u * u * 240 + u * 60)).applyQuaternion(A.root.quaternion)); };
  fx.add(missile({ path: hfPath, t0: L0, t1: L0 + 3, size: 0.55, smokeLife: 2.5, tail: 2.4 }));
  fx.add((t, f) => { const u = t - L0; if (u < 0 || u > 0.4) return; const b = hfPath(L0); f.addGlow(b, 3, new THREE.Color(1, 0.7, 0.4), 6 * (1 - u / 0.4), 1, 0); f.addLight(b, new THREE.Color(1, 0.6, 0.3), 3, 60); });
  return {
    update(t) {
      const p = heliPos(0, 3 + t);
      fly(A, p, V3(-0.15, -0.05, 1).normalize(), 0.01);
      A.spin(t, 0.9); A.gunAim(0, -0.08);
      if (A.hf[0]) A.hf[0].visible = t < L0;
      A.root.updateMatrixWorld(true);
      cam(env, A.root.localToWorld(V3(9, 3, -6)), A.root.localToWorld(V3(-2, -2, -40)), 40);
      shake(env.camera, t, 0.3 + (t > L0 ? 0.8 * Math.exp(-(t - L0) * 4) : 0), 5, 27);
      return { ...DAY({ az: 140, el: 34, heat: 0.6 }), shadowAt: p, shadowR: 60 };
    },
    events: [{ t: L0, k: 'hellfire' }],
  };
}
async function shotColumnHit(env, add) {
  const { fx } = env;
  const L = await column(env, add);
  const hits = [[1, 0.9], [2, 1.9]];
  for (const [i, t1] of hits) {
    const p = () => COL(i, 8 + t1).clone().setY(heightAt(COL(i, 8 + t1).x, COL(i, 8 + t1).z) + 4);
    fx.add((t, f) => { const u = (t - (t1 - 0.5)) / 0.5; if (u < 0 || u > 1) return; const q = p().add(V3(-120 * (1 - u), 180 * (1 - u), -500 * (1 - u))); f.addGlow(q, 1.2, new THREE.Color(1, 0.75, 0.45), 4, 1, 0.001); });
    fx.add(explosion({ p: p(), t0: t1, s: 28, seed: 720 + i, debris: 24 }));
    fx.add(cookoff({ p: p(), t0: t1 + 0.2, seed: 730 + i }));
  }
  L.forEach((V, i) => fx.add(dustTrail({ path: tt => { const p = COL(i, 8 + Math.min(tt, i === 1 ? 0.9 : (i === 2 ? 1.9 : 99))); p.y = heightAt(p.x, p.z); return p.add(V3(-12, 0, 0)); }, t0: -4, s: 1.2, gap: 8, life: 6, alpha: 0.35, seed: 740 + i })));
  return {
    update(t) {
      L.forEach((V, i) => { const tt = 8 + Math.min(t, i === 1 ? 0.9 : (i === 2 ? 1.9 : 99)); const p = COL(i, tt); ground(V.root, p.x, p.z, -Math.PI / 2); V.roll(p.x); });
      const c = V3(-8900, 0, 260); c.y = heightAt(c.x, c.z) + 10;
      cam(env, c, COL(2, 9).setY(14), 22);
      shake(env.camera, t, 0.2 + (t > 0.9 ? 0.6 * Math.exp(-(t - 0.9) * 3) : 0) + (t > 1.9 ? 0.6 * Math.exp(-(t - 1.9) * 3) : 0), 5, 29);
      return { ...DAY({ az: 140, el: 34, heat: 1.0 }), shadowAt: COL(2, 9), shadowR: 300 };
    },
    events: [{ t: 0.9, k: 'boom', v: 0.9 }, { t: 1.9, k: 'boom', v: 0.9 }],
  };
}
// 防空车（PGL-625）：雷达转、炮塔转向阿帕奇
function t625Aim(V, t, tgt) {
  V.root.updateMatrixWorld(true);
  const want = headingTo(V.root.position, tgt) - V.root.rotation.y;
  const dz = tgt.y - V.root.position.y, dist = Math.hypot(tgt.x - V.root.position.x, tgt.z - V.root.position.z);
  V.aim(want, Math.atan2(dz, dist));
  V.root.updateMatrixWorld(true);
}
// G23 PGL-625 雷达截获、炮塔一下转过来，六管炮开始转——阿帕奇座舱里告警响
async function shotLock(env, add) {
  const L = await column(env, add);
  const V = L[5];
  const ah = heliPos(0, 5);
  return {
    update(t) {
      L.forEach((W, i) => { const p = COL(i, 11); ground(W.root, p.x, p.z, -Math.PI / 2); });
      const k = smooth(0.2, 1.2, t);
      V.root.updateMatrixWorld(true);
      const want = headingTo(V.root.position, ah) - V.root.rotation.y;
      V.aim(lerp(0.3, want, k), lerp(0, Math.atan2(ah.y - V.root.position.y, 3500), k));
      V.root.updateMatrixWorld(true);
      cam(env, V.root.localToWorld(V3(17, 8, 16)), V.root.localToWorld(V3(0, 9, -8)), 36);
      shake(env.camera, t, 0.2, 4, 31);
      return { ...DAY({ az: 140, el: 34, heat: 0.6 }), shadowAt: V.root.position, shadowR: 60 };
    },
    overlay: (g, t, W, H, ah2) => drawWarn(g, W, H, ah2, { t, threat: 2.6, launch: false, msg: t > 1.2 ? '雷达锁定' : '', sub: t > 1.2 ? 'PGL-625 · 6 点钟' : '' }),
    titles: t => caption('红方 · PGL-625 弹炮合一防空车', '25 毫米六管炮 + 4 枚红外导弹', fadeIO(t, 0.3, 2.6, 0.4, 0.4)),
    events: [{ t: 0.2, k: 'turretWhine' }, { t: 1.2, k: 'rwrLock' }],
  };
}
// 阿帕奇规避：一架被锁的（i = 0）往左压坡度、放热诱弹、掉高度；两枚导弹的轨迹
const EVADE = (() => {
  const tL = [0.35, 0.9], tHit = [2.05, 2.95];
  const hp = t => { const b = smooth(0.4, 1.6, t); const p = heliPos(0, 5).add(V3(-b * 60 - t * 20, -b * 18, b * 30)); return p; };
  return { tL, tHit, hp };
})();
// G24 625 开火：六管炮泼出一道曳光、两枚导弹拖着白烟出筒
async function shotAAFire(env, add) {
  const { fx } = env;
  const L = await column(env, add);
  const V = L[5];
  L.forEach((W, i) => { const p = COL(i, 11); ground(W.root, p.x, p.z, -Math.PI / 2); });
  const tgt = t => EVADE.hp(t);
  const mzl = t => { t625Aim(V, t, tgt(t)); return V.muzzle(); };
  fx.add(gatling({ from: mzl, dir: t => { t625Aim(V, t, tgt(t)); return V.muzzleDir(); }, t0: 0.1, t1: 2.4, rate: 55, speed: 1150, every: 2, spread: 0.01, col: new THREE.Color(1, 0.55, 0.2), len: 40, maxD: 4200, w: 1.3, bright: 22 }));
  EVADE.tL.forEach((t0, k) => {
    const start = () => V.root.localToWorld(V3(k ? 2.6 : -2.6, 9.4, 0.5));
    fx.add(missile({ path: tau => { const u = Math.max(0, tau - t0); const s = start(); const to = tgt(Math.min(tau, EVADE.tHit[k])); return s.lerp(to, clamp(u / (EVADE.tHit[k] - t0), 0, 1) ** 1.2).add(V3(0, Math.sin(clamp(u / (EVADE.tHit[k] - t0), 0, 1) * Math.PI) * 60, 0)); }, t0, t1: t0 + 3, size: 0.8, smokeLife: 4 }));
  });
  return {
    update(t) {
      t625Aim(V, t, tgt(t));
      const tg = tgt(t);
      const back = V.root.position.clone().sub(tg).setY(0).normalize();
      const c = V.root.position.clone().addScaledVector(back, 26).add(V3(0, 14, 0)).add(new THREE.Vector3(-back.z, 0, back.x).multiplyScalar(8));
      cam(env, c, V.root.position.clone().lerp(tg, 0.04).add(V3(0, 22, 0)), 40);
      shake(env.camera, t, 0.4 + (t > 0.1 && t < 2.4 ? 0.5 : 0), 9, 33);
      return { ...DAY({ az: 140, el: 34, heat: 0.6 }), shadowAt: V.root.position, shadowR: 70 };
    },
    events: [{ t: 0.1, k: 'gatling25', d: 2.3 }, { t: 0.35, k: 'manpads' }, { t: 0.9, k: 'manpads' }],
  };
}
// G25 阿帕奇压坡度猛拉、一串热诱弹往两边撒开：第一枚导弹被骗走、在热诱弹里炸开；第二枚穿过来——打在尾梁上
async function shotEvade(env, add) {
  const { fx } = env;
  const H = await apache(env, add, 1);
  const A = H[0];
  const T0 = 0.6;   // 这个镜头的 0 秒 = 时间线 0.6 秒
  const hp = t => EVADE.hp(T0 + t);
  fx.add(decoys({ from: hp, vel: () => V3(-20, -10, 15), t0: 0.5, n: 16, every: 0.06, spread: 55 }));
  const mis = (k, tau) => { const s = V3(-8800, 22, -220); const to = EVADE.hp(Math.min(tau, EVADE.tHit[k])); const u = clamp((tau - EVADE.tL[k]) / (EVADE.tHit[k] - EVADE.tL[k]), 0, 1); return s.lerp(to, u ** 1.2).add(V3(0, Math.sin(u * Math.PI) * 60, 0)); };
  const decoyP = V3().copy(EVADE.hp(1.6)).add(V3(-40, -26, 18));
  fx.add(missile({ path: tl => { const tau = T0 + tl; if (tau > 1.45) return mis(0, 1.45).lerp(decoyP, clamp((tau - 1.45) / 0.35, 0, 1)); return mis(0, tau); }, t0: EVADE.tL[0] - T0, t1: 1.8 - T0, size: 0.8, smokeLife: 3 }));
  fx.add(explosion({ p: decoyP, t0: 1.8 - T0, s: 14, seed: 760, debris: 0, ember: 20, dust: false, air: { v: V3(0, 0, 0) } }));
  fx.add(missile({ path: tl => mis(1, T0 + tl), t0: EVADE.tL[1] - T0, t1: EVADE.tHit[1] - T0, size: 0.8, smokeLife: 3 }));
  const tailP = () => A.root.localToWorld(V3(0, 7, 15));
  fx.add(explosion({ p: tailP, t0: EVADE.tHit[1] - T0, s: 12, seed: 761, debris: 14, ember: 30, dust: false, air: { v: V3(-20, -10, 10) } }));
  return {
    update(t) {
      const tau = T0 + t;
      const p = hp(t);
      const bank = smooth(0.2, 0.9, t) * 0.75;
      fly(A, p, V3(-0.6, -0.12, 0.8).normalize(), -bank);   // 往右急转规避：往右压坡度
      A.spin(t, 0.95); A.gunAim(0, -0.05);
      const c = p.clone().add(V3(60, 10, 40));
      cam(env, c, p.clone().add(V3(-20, -6, -10)), 40);
      shake(env.camera, t, 0.45 + (tau > EVADE.tHit[1] ? 1.2 * Math.exp(-(tau - EVADE.tHit[1]) * 3) : 0), 6, 37);
      return { ...DAY({ az: 140, el: 34, heat: 0.5 }), shadowAt: p, shadowR: 60 };
    },
    overlay: (g, t, W, H, ah) => drawWarn(g, W, H, ah, { t, threat: 2.6, launch: true, msg: T0 + t < EVADE.tHit[1] ? '导弹来袭' : '', sub: T0 + t < 1.8 ? '热诱弹' : (T0 + t < EVADE.tHit[1] ? '第二枚！' : '') }),
    events: [{ t: 0, k: 'missileWarn' }, { t: 0.5, k: 'flares' }, { t: 1.8 - T0, k: 'boom', v: 0.5 }, { t: EVADE.tHit[1] - T0, k: 'airboom' }],
  };
}
// G26 打中以后：阿帕奇冒着火、拖着黑烟打着转往下掉，砸在沙地上、翻滚、炸成一团火球
async function shotCrash(env, add) {
  const { fx } = env;
  const H = await apache(env, add, 1);
  const A = H[0];
  const p0 = EVADE.hp(EVADE.tHit[1]);
  const gyc = heightAt(p0.x - 120, p0.z + 60);
  const fall = t => { const u = clamp(t / 2.6, 0, 1); return V3(p0.x - 120 * u, lerp(p0.y, gyc + 4, u * u), p0.z + 60 * u); };
  const tImp = 2.6;
  fx.add((t, f) => {   // 尾巴上的火、拖着的黑烟
    if (t > tImp) return;
    const q = A.root.localToWorld(V3(0, 7, 14));
    f.sprite('fire', q, 7, ((t * 26) % 64 + 64) % 64, 0.95, 1.2, [0.2, 0.18, 0.16], 1);
    f.addLight(q, new THREE.Color(1, 0.55, 0.22), 6, 160);
    for (let j = 1; j < 24; j++) { const b = j * 0.09; if (b > t) break; const qq = fall(t - b).add(V3(0, 6 + b * 3, 0)); f.sprite('puff', qq, 4 + b * 9, 14 + b * 16, 0.6 * (1 - j / 24), 0, [0.15, 0.14, 0.13], j * 1.7); }
  });
  const crash = V3(p0.x - 120, gyc, p0.z + 60);
  fx.add(explosion({ p: crash.clone().add(V3(0, 3, 0)), t0: tImp, s: 40, seed: 770, debris: 36, ember: 60 }));
  fx.add(bigFire({ p: crash.clone(), s: 11, t0: tImp + 0.3, seed: 771, dark: 0.08 }));
  return {
    update(t) {
      const p = fall(Math.min(t, tImp));
      A.root.visible = t < tImp + 0.08;
      A.root.position.copy(p);
      A.root.rotation.set(0, 0, 0);
      A.root.rotateY(t * t * 1.6 + t * 2.2);   // 尾桨没了：机身越转越快
      A.root.rotateZ(Math.sin(t * 3) * 0.25);
      A.root.rotateX(0.15 + t * 0.06);
      A.root.updateMatrixWorld(true);
      A.spin(t, 0.8);
      const c = V3(crash.x + 230, 0, crash.z + 150); c.y = heightAt(c.x, c.z) + 9;
      cam(env, c, p.clone().lerp(crash, smooth(1.6, 2.6, t) * 0.7).add(V3(0, 5, 0)), lerp(30, 36, smooth(1.8, 3.2, t)));
      shake(env.camera, t, 0.25 + (t > tImp ? 1.4 * Math.exp(-(t - tImp) * 3) : 0), 4, 41);
      return { ...DAY({ az: 140, el: 34, heat: 0.8 }), shadowAt: crash, shadowR: 160 };
    },
    titles: t => caption('击落', '尾梁中弹，失去尾桨 —— 打着转坠地', fadeIO(t, 0.6, 4.4, 0.4, 0.4)),
    events: [{ t: 0, k: 'heliSpin', d: 2.6 }, { t: tImp, k: 'bigboom', v: 1 }],
  };
}

// ———————————————————————————— 第五幕：歼-16 光电吊舱，导弹挨个锁定击毁 ————————————————————————————
async function j16(env, add) {
  const A = await plane('j16', env);
  A.gearDown && A.gearDown(false);
  add(A.root);
  const py = A.M.pyl && A.M.pyl.j16;
  A.kd = [];
  if (py) {
    const mk = (k, f, dy = 1.2) => { const m = f(); m.position.set(py[k][2], py[k][0] - dy, py[k][1]); A.root.add(m); return m; };
    mk(0, pl10, 0.3); mk(1, pl10, 0.3);
    mk(2, pl15, 1.0); mk(3, pl15, 1.0);
    A.kd.push(mk(4, kd88), mk(5, kd88), mk(6, kd88), mk(7, kd88));
    mk(8, ls6, 1.4); mk(9, ls6, 1.4);
  }
  return A;
}
// G27 歼-16 挂满对地武器压坡度转弯：4 枚 KD-88、2 枚雷石-6、霹雳-15 / 10 自卫
async function shotJ16(env, add) {
  const { fx } = env;
  const A = await j16(env, add);
  afterburners(A, fx, () => 0.1, 0.1);
  const c0 = V3(COL6.x - 9000, 5200, COL6.z + 9000);
  return {
    update(t) {
      const a = -0.6 + t * 0.06;
      const p = c0.clone().add(V3(Math.cos(a) * 3000, 0, Math.sin(a) * 3000));
      fly(A, p, V3(-Math.sin(a), 0, Math.cos(a)), 0.55);
      const cp = A.root.localToWorld(V3(-58, 14, 40));
      cam(env, cp, A.root.localToWorld(V3(0, -1, -4)), 30);
      shake(env.camera, t, 0.15, 0.8, 43);
      return { ...DAY({ az: 140, el: 34, heat: 0.2, exposure: 0.6 }), shadowAt: p, shadowR: 70 };
    },
    titles: t => caption('红方 · 歼-16 · 对地满挂', '4 枚 KD-88 空地导弹 · 2 枚雷石-6 · 霹雳-15 / 10 自卫', fadeIO(t, 0.4, 3.7, 0.4, 0.4)),
    events: [{ t: 0, k: 'jetCruise' }],
  };
}
const BCOL = (i, t) => V3(COL6.x + i * 75 - t * 10, 0, COL6.z + Math.sin(i * 1.7) * 4);   // 蓝方装甲纵队往西开（6 号公路）
async function blueColumn(env, add, thermal) {
  const keys = ['m1a2dc', 'm2a3', 'm1a2dc', 'm2a3', 'hmmwv'];
  const L = [];
  for (const k of keys) { const V = await vehicle(k, env.REPO); if (thermal) thermalize(V, 1); else dusty(V); add(V.root); L.push(V); }
  return L;
}
// G28 光电吊舱（热像）：扫过公路，发现装甲纵队；目标框一个个跳出来，挨个锁定
async function shotEO16(env, add) {
  const L = await blueColumn(env, add, true);
  let boxes = [];
  const cv = V3();
  return {
    update(t) {
      L.forEach((V, i) => { const p = BCOL(i, t); ground(V.root, p.x, p.z, Math.PI / 2); });
      const look = BCOL(2, t).add(V3(lerp(-900, 0, smooth(0, 1.4, t)), 0, lerp(400, 0, smooth(0, 1.4, t))));
      look.y = heightAt(look.x, look.z);
      const c = V3(COL6.x - 7000, 6200, COL6.z + 9000);
      cam(env, c, look, lerp(2.6, 1.5, smooth(1.2, 2.6, t)));
      env.camera.updateMatrixWorld(true);
      boxes = L.slice(0, 4).map((V, i) => {
        cv.copy(V.root.position).add(V3(0, 3, 0)).project(env.camera);
        const tl = 1.6 + i * 0.45;
        const st = t > tl + 0.3 ? 'lock' : (t > tl ? 'trk' : (t > 1.4 ? 'scan' : null));
        return st ? { x: 0.5 + cv.x / 2, y: 0.5 - cv.y / 2, s: 0.02, st, label: t > tl ? `${i + 1}` : '' } : null;
      }).filter(Boolean);
      return { ...DAY({ az: 140, el: 34, heat: 0.4 }), thermal: 1, therK: 0.8, grain: 0.02, vignette: 0.25, bloom: 0.4, shadowAt: look, shadowR: 300, fogDensity: 0.00001 };
    },
    overlay: (g, t, W, H, ah) => drawEO(g, W, H, ah, { t, boxes, zoom: lerp(8, 22, smooth(1.2, 2.6, t)), rng: 11.4, alt: 18600, mode: 'WHOT', wpn: 'KD-88 ×4', trk: t > 1.6 ? 'AREA TRK' : 'SCAN', msg: t > 3.65 ? '4 / 4 锁定' : (t > 1.6 ? `锁定 ${Math.min(4, Math.floor((t - 1.6) / 0.45) + 1)} / 4` : '搜索'), laser: false, lat: '29°18.07', lon: '047°44.52' }),
    events: [{ t: 1.6, k: 'beepSoft' }, { t: 2.05, k: 'beepSoft' }, { t: 2.5, k: 'beepSoft' }, { t: 2.95, k: 'beepSoft' }, { t: 3.6, k: 'lockTone' }],
  };
}
// G29 一枚接一枚 KD-88 脱离挂架、点火、拖着白烟冲出去
async function shotRelease(env, add) {
  const { fx } = env;
  const A = await j16(env, add);
  afterburners(A, fx, () => 0.1, 0.1);
  const rel = [0.3, 0.75, 1.2, 1.65];
  const c0 = V3(COL6.x - 7000, 6200, COL6.z + 9000);
  const dir = V3(0.55, -0.04, -0.83).normalize();
  const pAt = t => c0.clone().addScaledVector(dir, t * 260);
  rel.forEach((t0, k) => {
    const m0 = () => A.kd[k] ? A.root.localToWorld(A.kd[k].position.clone()) : pAt(t0);
    fx.add(missile({ path: tau => { const u = Math.max(0, tau - t0); const s = A.kd[k] ? A.kd[k].userData.p0 || m0() : m0(); return s.clone().addScaledVector(dir, u * 260 + u * u * 160).add(V3(0, -u * 8 - 14 * Math.min(u, 0.35), 0)); }, t0: t0 + 0.3, t1: t0 + 6, size: 1.0, smokeLife: 4, tail: 6.5 }));
  });
  return {
    update(t) {
      const p = pAt(t);
      fly(A, p, dir, 0.04);
      rel.forEach((t0, k) => {
        const m = A.kd[k]; if (!m) return;
        if (t < t0) { m.visible = true; m.userData.p0 = null; return; }
        if (!m.userData.p0) m.userData.p0 = A.root.localToWorld(m.position.clone());
        m.visible = t < t0 + 0.32;
        m.position.y = (m.userData.y0 ??= m.position.y) - (t - t0) * (t - t0) * 30;
      });
      cam(env, A.root.localToWorld(V3(-30, -16, 46)), A.root.localToWorld(V3(4, -10, -60)), 44);
      shake(env.camera, t, 0.2, 1, 47);
      return { ...DAY({ az: 140, el: 34, heat: 0.2, exposure: 0.6 }), shadowAt: p, shadowR: 60 };
    },
    events: rel.map(t => ({ t: t + 0.3, k: 'missileLaunch', v: 0.7 })),
  };
}
// G30 吊舱画面：四枚导弹挨个打中，热像里一团团发白；「命中 4 / 4」
async function shotEOHit(env, add) {
  const { fx } = env;
  const L = await blueColumn(env, add, true);
  const hits = [0.6, 1.25, 1.9, 2.55];
  const T0 = 3.2;
  L.slice(0, 4).forEach((V, i) => {
    const pv = BCOL(i, T0 + hits[i]); pv.y = heightAt(pv.x, pv.z) + 4;
    const p = pv;
    fx.add((t, f) => { const u = (t - (hits[i] - 0.4)) / 0.4; if (u < 0 || u > 1) return; const q = p.clone().add(V3(-500 * (1 - u), 300 * (1 - u), 700 * (1 - u))); f.addStreak(q.clone().add(V3(-60, 36, 84)), q, 1.2, new THREE.Color(1, 1, 1), 16, 0.5, 0.0015); });
    fx.add(explosion({ p, t0: hits[i], s: 26, seed: 800 + i, debris: 18, ember: 30 }));
    fx.add(cookoff({ p, t0: hits[i] + 0.2, seed: 810 + i }));
  });
  let boxes = [];
  const cv = V3();
  return {
    update(t) {
      L.forEach((V, i) => { const stop = i < 4 ? hits[i] : 99; const p = BCOL(i, T0 + Math.min(t, stop)); ground(V.root, p.x, p.z, Math.PI / 2); });
      const look = BCOL(2, T0 + Math.min(t, hits[2])); look.y = heightAt(look.x, look.z);
      const c = V3(COL6.x - 7000, 6200, COL6.z + 9000);
      cam(env, c, look, 1.5);
      env.camera.updateMatrixWorld(true);
      boxes = L.slice(0, 4).map((V, i) => { cv.copy(V.root.position).add(V3(0, 3, 0)).project(env.camera); return { x: 0.5 + cv.x / 2, y: 0.5 - cv.y / 2, s: 0.02, st: t > hits[i] ? 'hit' : 'lock', label: `${i + 1}` }; });
      return { ...DAY({ az: 140, el: 34, heat: 0.4 }), thermal: 1, therK: 0.8, grain: 0.02, vignette: 0.25, bloom: 0.7, shadowAt: look, shadowR: 300, fogDensity: 0.00001 };
    },
    overlay: (g, t, W, H, ah) => { const n = hits.filter(h => t > h).length; drawEO(g, W, H, ah, { t, boxes, zoom: 22, rng: 10.8, alt: 18600, mode: 'WHOT', wpn: `KD-88 ×${4 - n}`, msg: n ? `命中 ${n} / 4` : '导弹飞行中', lat: '29°18.07', lon: '047°44.52' }); },
    events: hits.map(h => ({ t: h, k: 'boomFar', v: 0.8 })),
  };
}

// ———————————————————————————— 尾声：黄昏的油田大火、片名 ————————————————————————————
let WELLS = null;
function wellsNear(env, cx, cz, r) {
  const W = (env.D.world.wells || []).filter(w => Math.hypot(w.x - cx, w.z - cz) < r);
  return W;
}
// G31 黄昏：油田一口口井在烧，黑烟柱一根根顶到天上；99A 剪影从前面开过去
async function shotOilfield(env, add) {
  const { fx } = env;
  const W = wellsNear(env, OIL.x, OIL.z, 2200);
  W.forEach((w, i) => {
    const wh = wellhead(); wh.position.set(w.x, heightAt(w.x, w.z), w.z); add(wh);
    fx.add(bigFire({ p: V3(w.x, heightAt(w.x, w.z) + 3, w.z), s: 9 + (i % 3) * 3, t0: -10 - i, seed: 900 + i, oil: true, dark: 0.06, smokeH: 1.3 }));
  });
  const L = await tanks(env, add, 'ztz99a2', 3);
  const path = (i, t) => V3(OIL.x - 1500 + t * 14 + i * 80, 0, OIL.z + 1300 - i * 40);
  return {
    update(t) {
      L.forEach((V, i) => { const p = path(i, t); ground(V.root, p.x, p.z, -Math.PI / 2 + 0.1); V.roll(p.x); V.aim(0.2, 0.02); });
      const c = V3(OIL.x - 1400, 0, OIL.z + 1650); c.y = heightAt(c.x, c.z) + 5;
      cam(env, c, V3(OIL.x + 300, 60 + t * 3, OIL.z - 200), 26);
      shake(env.camera, t, 0.1, 1, 49);
      return { ...dusk({ el: 3.2, az: 300, exposure: 0.9, dust: 0.7 }), shadowAt: V3(OIL.x - 1200, 12, OIL.z + 1300), shadowR: 300, bloom: 1.0 };
    },
    titles: t => [{ text: '油田在烧', x: 0.5, y: 0.8, size: 0.03, font: SERIF, weight: 700, spacing: 0.4, a: fadeIO(t, 1.5, 5.6, 0.8, 0.6), color: '#f0e2cc' }],
    events: [{ t: 0, k: 'fireField' }, { t: 0, k: 'dawnMusic' }],
  };
}
// G32 片名
async function shotTitle(env, add) {
  env.worldVisible(false);
  const R = rng(300);
  const E = [];
  for (let i = 0; i < 160; i++) E.push({ p: V3(R.range(-60, 60), R.range(-30, 30), R.range(-80, -20)), v: V3(R.range(-1.5, 0.5), R.range(1, 3.5), 0), ph: R() * 6, s: R.range(0.08, 0.3) });
  env.fx.add((t, fx) => {
    for (const e of E) {
      const p = e.p.clone().addScaledVector(e.v, t); p.y = ((p.y + 30) % 60 + 60) % 60 - 30;
      const tw = 0.5 + 0.5 * Math.sin(t * 3 + e.ph);
      fx.addGlow(p, e.s, new THREE.Color(1, 0.5, 0.18), 3.5 * tw, 1, 0);
    }
  });
  return {
    update(t) { cam(env, V3(0, 0, 0), V3(0, 0, -1), 40); return { exposure: 1, bloom: 1.4, fade: 0, grain: 0.012, lift: 0 }; },
    titles: t => [
      { text: '全面大战场', x: 0.5, y: 0.45, size: 0.085, font: SERIF, weight: 700, spacing: 0.14, a: fadeIO(t, 0.6, 5.7, 1.2, 0.8), color: '#efe9de', glow: 'rgba(255,170,90,0.35)' },
      { text: '沙  海', x: 0.5, y: 0.565, size: 0.036, font: SERIF, weight: 700, spacing: 0.9, a: fadeIO(t, 1.4, 5.7, 1.0, 0.8), color: '#e3c79a', rule: 0.2 },
      { text: '陆 · 空　全面对决', x: 0.5, y: 0.63, size: 0.02, font: SANS, spacing: 0.6, a: fadeIO(t, 2.0, 5.7, 1.0, 0.8), color: '#b9b2a6' },
    ],
    events: [{ t: 0.55, k: 'titleHit' }],
  };
}
// G33 卖点
async function shotFeatures(env, add) {
  env.worldVisible(false);
  const tank = await vehicle('ztz99a2', env.REPO); add(tank.root);
  const J = await j16(env, add);
  const key = new THREE.DirectionalLight(0xffd6b0, 4.0); key.position.set(-25, 18, 35); add(key);
  const rim = new THREE.DirectionalLight(0x8fb0ff, 6.0); rim.position.set(30, 14, -90); add(rim);
  return {
    update(t) {
      const seg = t < 3.75 ? 0 : 1;
      tank.root.visible = seg === 0; J.root.visible = seg === 1;
      const u = seg === 0 ? t / 3.75 : (t - 3.75) / 3.75;
      if (seg === 0) { tank.root.position.set(14, -4.5, -50); tank.root.rotation.set(0, 0.55 + u * 0.35, 0); tank.aim(Math.sin(u * 2) * 0.2 - 0.3, 0.03); }
      else { J.root.position.set(36, -3, -110); J.root.rotation.set(0.1, -1.0 + u * 0.35, 0.25); }
      cam(env, V3(0, 0, 0), V3(0, 0, -1), 32);
      const k = fadeIO(t, seg === 0 ? 0 : 3.75, seg === 0 ? 3.75 : 7.5, 0.5, 0.5);
      return { exposure: 1.4 * k + 0.0001, bloom: 0.8, fade: 0, grain: 0.012, vignette: 0.8, lift: 0 };
    },
    titles: t => {
      const A = (a, b) => fadeIO(t, a, b, 0.45, 0.45);
      return [
        { text: '27.8 公里见方的沙漠战场', x: 0.08, y: 0.4, size: 0.034, font: SERIF, weight: 700, align: 'left', spacing: 0.12, a: A(0.3, 3.6) },
        { text: '地图面积 10 倍 · 边境沙墙 · 油田 · 镇子 · 空军基地 · 岩岭指挥部', x: 0.08, y: 0.47, size: 0.019, font: SANS, align: 'left', spacing: 0.18, a: A(0.7, 3.6), color: '#b9b2a6' },
        { text: '坦克 · 直升机 · 战斗机 · 无人机', x: 0.08, y: 0.4, size: 0.034, font: SERIF, weight: 700, align: 'left', spacing: 0.12, a: A(4.0, 7.3) },
        { text: '每一辆都能亲自驾驶 —— 方向装甲 · 反应装甲 · 光电吊舱 · 热诱弹', x: 0.08, y: 0.47, size: 0.019, font: SANS, align: 'left', spacing: 0.15, a: A(4.4, 7.3), color: '#b9b2a6' },
      ];
    },
    events: [{ t: 0.3, k: 'pulse2' }, { t: 4.0, k: 'pulse2' }],
  };
}
// G34 片尾
async function shotEnd(env, add) {
  env.worldVisible(false);
  const credits = ['ZTZ-99A：philano', 'M1A2：dannzjs', '歼-16、歼-35：andertan', 'AH-64：Muhamad Mirza Arrafi', 'MQ-9：IProZenoN', '爱国者：Muhamad Mirza Arrafi', 'M4：BarcodeGames'];
  return {
    update(t) { cam(env, V3(0, 0, 0), V3(0, 0, -1), 40); return { exposure: 1, fade: 0, grain: 0.010, lift: 0 }; },
    titles: t => {
      const a = fadeIO(t, 0.2, 5.5, 0.6, 0.9);
      return [
        { text: '红方　VS　蓝方', x: 0.5, y: 0.36, size: 0.03, font: SERIF, weight: 700, spacing: 0.18, a },
        { text: '两个阵营　一片沙漠　选择你的立场', x: 0.5, y: 0.42, size: 0.02, font: SANS, spacing: 0.3, a, color: '#c9c1b4' },
        { text: '全面大战场　1.0-alpha 测试中', x: 0.5, y: 0.53, size: 0.018, font: SANS, spacing: 0.3, a: a * 0.9, color: '#a8a196' },
        { text: '本片为游戏原模型与沙漠地图离线渲染　模型均为 Sketchfab 上 CC-BY 4.0 授权作品', x: 0.5, y: 0.645, size: 0.0125, font: SANS, spacing: 0.1, a: a * 0.75, color: '#8a847a' },
        { text: credits.slice(0, 4).join('　·　'), x: 0.5, y: 0.68, size: 0.0125, font: SANS, spacing: 0.05, a: a * 0.75, color: '#8a847a' },
        { text: credits.slice(4).join('　·　'), x: 0.5, y: 0.705, size: 0.0125, font: SANS, spacing: 0.05, a: a * 0.75, color: '#8a847a' },
      ];
    },
    events: [{ t: 0, k: 'endTail' }],
  };
}

export const SHOTS = [
  { id: 'G01', dur: 6.5, ...T(TOWNC.x, TOWNC.z), setup: shotOpen },
  { id: 'G02', dur: 3.8, ...T(TOWNC.x + 420, TOWNC.z + 260), setup: shotNvgAAA },
  { id: 'G03', dur: 4.5, ...T(SAM.x, SAM.z), setup: shotSam },
  { id: 'G04', dur: 3.8, ...T(SAM.x - 1500, SAM.z + 5000), setup: shotJets },
  { id: 'G05', dur: 3.2, ...T(SAM.x, SAM.z), setup: shotPatriotFire },
  { id: 'G06', dur: 4.0, ...T(SAM.x, SAM.z), setup: shotEO35 },
  { id: 'G07', dur: 4.6, ...T(SAM.x, SAM.z), setup: shotSamHit },
  { id: 'G08', dur: 3.0, ...T(SAM.x, SAM.z), setup: shotJetsAway },
  { id: 'G09', dur: 3.2, ...T(BATT.x - 9000, BATT.z + 8000), setup: shotDrone },
  { id: 'G10', dur: 3.6, ...T(BATT.x, BATT.z), setup: shotDroneEO },
  { id: 'G11', dur: 2.6, ...T(BATT.x, BATT.z), setup: shotDroneHit },
  { id: 'G11B', dur: 3.2, ...T(BATT.x, BATT.z), setup: shotBattBurn },
  { id: 'G12', dur: 4.8, ...T(-1200, 7600), setup: shotBreach },
  { id: 'G13', dur: 3.6, ...T(-1200, 5800), setup: shotWedge },
  { id: 'G14', dur: 3.8, ...T(-300, 3300), setup: shotHullDown },
  { id: 'G15', dur: 2.8, ...T(-300, 4600), setup: shotSightM1 },
  { id: 'G16', dur: 3.6, ...T(-500, 5800), setup: shotEra },
  { id: 'G17', dur: 3.0, ...T(-300, 5400), setup: shotMuzzle99 },
  { id: 'G18', dur: 3.6, ...T(-300, 4600), setup: shotSight99 },
  { id: 'G19', dur: 3.8, ...T(-500, 3300), setup: shotToss },
  { id: 'G20', dur: 4.0, ...T(0, 4600), setup: shotMelee },
  { id: 'G21', dur: 3.4, ...T(-8300, -3600), setup: shotApacheUp },
  { id: 'G22', dur: 2.4, ...T(-8300, -3600), setup: shotHellfire },
  { id: 'G22B', dur: 3.0, ...T(-8700, -200), setup: shotColumnHit },
  { id: 'G23', dur: 2.8, ...T(-8700, -200), setup: shotLock },
  { id: 'G24', dur: 2.6, ...T(-8700, -200), setup: shotAAFire },
  { id: 'G25', dur: 3.0, ...T(-8500, -3600), setup: shotEvade },
  { id: 'G26', dur: 4.6, ...T(-8500, -3500), setup: shotCrash },
  { id: 'G27', dur: 3.8, ...T(COL6.x - 9000, COL6.z + 9000), setup: shotJ16 },
  { id: 'G28', dur: 4.2, ...T(COL6.x, COL6.z), setup: shotEO16 },
  { id: 'G29', dur: 2.8, ...T(COL6.x - 7000, COL6.z + 9000), setup: shotRelease },
  { id: 'G30', dur: 3.6, ...T(COL6.x, COL6.z), setup: shotEOHit },
  { id: 'G31', dur: 6.0, ...T(OIL.x, OIL.z), setup: shotOilfield },
  { id: 'G32', dur: 6.0, setup: shotTitle },
  { id: 'G33', dur: 7.5, setup: shotFeatures },
  { id: 'G34', dur: 5.5, setup: shotEnd },
];
let T0 = 0;
for (const s of SHOTS) { s.t0 = T0; T0 += s.dur; }
export const TOTAL = T0;
