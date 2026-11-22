// 时代广场宣传片的新镜头：原片（shots.js）除了最后一镜都是夜戏，宣传片第三幕「天亮」要白天的大场面，这几镜专门拍
//   N1 机群掠海：三架歼-20 贴着海面从镜头头顶掠过，开加力朝岛上爬升（左边岛的山脊、右边海平线上的日出）
//   N2 舰队剪影：长焦逆光，054A、055 排在日出下面，近处几条登陆艇
//   N3 直升机编队：三架直-10 从海上低空掠过滩头，朝山脊后面的太阳飞
//   N4 坦克纵队：99A 迎着晨光开上滩头，步兵跟着走，路过还在烧的碉堡
//   N5 红蓝对峙：黑底里两辆坦克（红方 99A、蓝方 M1A2），一边红光、一边蓝光
// 机位是按地形量出来的（从海上往北看：岛在北偏西 40° 到北偏东 10°，太阳在北偏东 23°、仰角 9°）
import * as THREE from 'three';
import { V3, smooth, ease, lerp, clamp, DEG, shake, rng } from './lib.js';
import { SEA } from './world.js';
import { vehicle, aircraft, ship, landingCraft, hovercraft, pose, runPose } from './models.js';
import { muzzle, fire, spray } from './fx.js';
import { cam, onWaves, onGround, afterburners, squad, headingTo } from './shots.js';

// 日出：和原片天亮那一镜（S18）同一个方向
export const SUN = V3(0.38, 0.16, -0.91).normalize();
// 天亮的光照：太阳贴着地平线（场景里的「月光」平行光当太阳用，带阴影）、暖光、雾是暖灰的
export function dawnLight(P, o = {}) {
  return { ...P, dawn: 0.95, sunDir: SUN, moonDir: SUN, moonVis: 0, moonI: o.sunI ?? 6.2, moonC: 0xffb478, hemiI: o.hemiI ?? 2.1,
    fogColor: new THREE.Color().setRGB(0.21, 0.155, 0.135), fogDensity: o.fog ?? Math.min(P.fogDensity ?? 0.0009, 0.00095),
    exposure: o.exposure ?? 1.16, lift: 0.02, sat: o.sat ?? 1.0, contrast: 1.08, nvg: 0, bloom: (P.bloom ?? 0.9) * 0.9 };
}
// 太阳：天空着色器里只有地平线一抹暖光、没有日轮，摆一团光（同 S18）。沿太阳方向量地形的仰角，被山挡住就摆在山脊上面一点
export function sunGlow(env, k = 1) {
  const H = V3(SUN.x, 0, SUN.z).normalize(), el0 = SUN.y / Math.hypot(SUN.x, SUN.z);
  env.fx.add((t, f) => {
    const c = env.camera.position;
    let ang = -1;
    for (let d = 400; d < 14000; d += 200) ang = Math.max(ang, (env.groundY(c.x + H.x * d, c.z + H.z * d) - c.y) / d);
    const el = Math.max(el0, ang + 0.04);
    const p = c.clone().addScaledVector(H, 9000); p.y = c.y + el * 9000;
    f.addGlow(p, 700, new THREE.Color(1, 0.72, 0.4), 11 * k, 1, 0);
    f.addGlow(p, 3200, new THREE.Color(1, 0.5, 0.24), 0.85 * k, 0, 0);
  });
}
const fwdAz = az => V3(Math.sin(az), 0, -Math.cos(az));   // 方位角（从正北往东转）→ 水平方向
const rightAz = az => V3(Math.cos(az), 0, Math.sin(az));

// ———— N1 机群掠海 ————
async function shotJets(env, add) {
  const { fx } = env;
  const J = [];
  for (let i = 0; i < 3; i++) { const A = await aircraft('j20', env.REPO); add(A.root); A.gearDown(false); J.push(A); }
  const C0 = V3(1245, 0, 4430);                 // 镜头：海面上，离滩头约 5 公里
  const AZ = 17 * DEG, D = fwdAz(AZ), Rt = rightAz(AZ), yaw = -AZ;   // 朝着日出飞（太阳在北偏东 23°）
  const T_PASS = 1.15, V0 = 560;                // 长机从镜头头顶过去的时刻；速度（格 / 秒，约 200 米 / 秒）
  // 航迹（每 1/240 秒积一步）：开加力加速、再拉起来朝岛上爬
  const PATH = [];
  { let s = -V0 * T_PASS, h = 30, v = V0;
    for (let i = 0; i <= 7 * 240; i++) {
      const t = i / 240, gam = smooth(2.5, 4.3, t) * 14 * DEG;   // 爬得缓：一直贴着日出的高度飞，镜头跟过去太阳还在画面里
      PATH.push([s, h, gam]);
      v += smooth(1.5, 2.3, t) * 80 / 240;
      s += v * Math.cos(gam) / 240; h += v * Math.sin(gam) / 240;
    } }
  const at = t => { const k = clamp(t * 240, 0, PATH.length - 1.001), i = Math.floor(k), u = k - i, a = PATH[i], b = PATH[i + 1]; return [lerp(a[0], b[0], u), lerp(a[1], b[1], u), lerp(a[2], b[2], u)]; };
  // 编队（右、上、后）：长机偏镜头左边一点过去，僚机梯次在右后、左后
  const OFF = [[-14, 0, 0], [26, 7, 36], [-54, 12, 44]];
  const jp = (i, t) => { const [s, h] = at(t), o = OFF[i]; return C0.clone().addScaledVector(D, s - o[2]).addScaledVector(Rt, o[0]).add(V3(0, h + o[1], 0)); };
  const kf = t => 0.25 + 0.75 * smooth(1.5, 2.2, t);
  J.forEach((A, i) => afterburners(A, fx, kf, 0.4));
  sunGlow(env);
  return {
    update(t) {
      SEA.amp = 0.9;
      const cen = V3();
      J.forEach((A, i) => {
        const p = jp(i, t), gam = at(t)[2];
        A.root.position.copy(p);
        A.root.rotation.set(gam, yaw, Math.sin(t * 1.3 + i * 2) * 0.03 + (i === 2 ? -0.05 : 0.02), 'YXZ');
        A.root.updateMatrixWorld(true);
        cen.add(p);
      });
      cen.multiplyScalar(1 / 3);
      // 镜头：架在海面上不动，看着日出和岛；机群从头顶冲进画面以后，慢慢跟着它们抬、拉近
      const camP = C0.clone().add(V3(0, 9 + Math.sin(t * 0.9) * 0.3, 0));
      const base = camP.clone().add(V3(Math.sin(8 * DEG), Math.tan(3.2 * DEG), -Math.cos(8 * DEG)).multiplyScalar(1000));
      const k = smooth(1.6, 3.4, t) * 0.7;
      const look = base.clone().lerp(cen, 0).sub(camP).normalize().lerp(cen.clone().sub(camP).normalize(), k).add(camP);
      cam(env, camP, look, lerp(38, 14, smooth(1.7, 5.8, t)));
      shake(env.camera, t, 0.12 + 1.3 * Math.exp(-((t - T_PASS - 0.15) ** 2) / 0.1), 6, 71);
      return dawnLight({ shadowAt: J[0].root.position, shadowR: 160, bloom: 1.3, grain: 0.01 }, { fog: 0.00018, exposure: 1.12 });
    },
    events: [{ t: 0, k: 'wind' }, { t: 0.45, k: 'jetPass' }, { t: T_PASS + 0.1, k: 'boom', v: 0.45 }, { t: 1.9, k: 'jetSpool' }],
  };
}

// ———— N2 舰队剪影 ————
async function shotFleetDawn(env, add) {
  const { fx } = env;
  const C0 = V3(-1400, 0, 10200);
  const AZ = 12 * DEG, Hd = fwdAz(AZ), Rt = rightAz(AZ);
  const F = fwdAz(58 * DEG), hd = headingTo(V3(), F);   // 舰队往右前方开
  const S = [];
  for (const [k, d, lat] of [['t054a', 1500, -250], ['t055', 2350, 40], ['t054a', 3350, 400], ['t054a', 4500, 760]]) {
    const o = await ship(k, env.REPO); add(o.root);
    S.push({ o, base: C0.clone().addScaledVector(Hd, d).addScaledVector(Rt, lat) });
  }
  const boats = [];
  for (let i = 0; i < 3; i++) { const L = landingCraft(env.T); add(L.root); boats.push({ L, base: C0.clone().addScaledVector(Hd, 640 + i * 170).addScaledVector(Rt, -330 + i * 210) }); }
  const hc = hovercraft(env.T); add(hc.root);
  const hcB = C0.clone().addScaledVector(Hd, 980).addScaledVector(Rt, 160);
  for (const s of S) {
    const half = s.o.len / 2;
    fx.add(spray({ at: (b, q) => s.o.root.localToWorld(V3(q.x * 14, 2, -half * 0.95 + Math.abs(q.z) * 30)).setY(1.5), rate: 50, size: 12, up: 8, life: 1.8, alpha: 0.3, seed: 820 + S.indexOf(s) }));
  }
  fx.add(spray({ at: (b, q) => { const p = hc.root.position; return V3(p.x + q.x * 12, 1, p.z + q.z * 18); }, rate: 60, size: 10, up: 6, life: 1.4, alpha: 0.22, seed: 829 }));
  sunGlow(env);
  return {
    update(t) {
      SEA.amp = 0.85;
      S.forEach(s => { const p = s.base.clone().addScaledVector(F, 14 * t); onWaves(s.o.root, p.x, p.z, hd, t, 0, 0.35); });
      boats.forEach(({ L, base }, i) => { const p = base.clone().addScaledVector(F, 22 * t); onWaves(L.root, p.x, p.z, hd + 0.08 * (i - 1), t, 1.8); });
      { const p = hcB.clone().addScaledVector(F, 30 * t); onWaves(hc.root, p.x, p.z, hd, t, 2.6, 0.4); hc.spin(t); }
      // 镜头：长焦、几乎不动，慢慢往前推一点、收一点视场角
      const camP = C0.clone().addScaledVector(Hd, t * 5).add(V3(0, 6 + Math.sin(t * 0.7) * 0.25, 0));
      cam(env, camP, camP.clone().addScaledVector(Hd, 3000).add(V3(0, 3000 * Math.tan(2.6 * DEG), 0)), lerp(17, 15, ease(t / 7)));
      env.camera.rotateZ(Math.sin(t * 0.5) * 0.25 * DEG);
      return dawnLight({ shadowAt: S[1].o.root.position, shadowR: 520, bloom: 1.25, grain: 0.01 }, { fog: 0.00026, exposure: 1.1 });
    },
    events: [{ t: 0, k: 'shipRumble' }, { t: 0, k: 'wind' }],
  };
}

// ———— N3 直升机编队 ————
async function shotHelis(env, add) {
  const { fx, groundY } = env;
  const H = [];
  for (let i = 0; i < 3; i++) {
    const h = await aircraft('z10w', env.REPO); add(h.root); H.push(h);
    const d = new THREE.Mesh(new THREE.CircleGeometry(h.M.w * 0.5 * 1.25, 48), new THREE.MeshBasicMaterial({ color: 0x0d0f10, transparent: true, opacity: 0.3, depthWrite: false, side: THREE.DoubleSide }));
    d.rotation.x = -Math.PI / 2; if (h.rot.rotor) h.rot.rotor.add(d);   // 旋翼的虚影（同 S16）
  }
  const C = V3(368, 0, -700); C.y = Math.max(groundY(C.x, C.z), 0) + 2.4;
  const AZ = 5 * DEG, D = fwdAz(AZ), Rt = rightAz(AZ);
  const T_PASS = 1.35, V = 185;
  const OFF = [[-10, 0, 0], [34, 9, 46], [-46, 14, 60]];
  const hp = (i, t) => {
    const o = OFF[i], s = V * (t - T_PASS) - o[2];
    const p = C.clone().addScaledVector(D, s).addScaledVector(Rt, o[0]);
    p.y = Math.max(groundY(p.x, p.z), 0) + 44 + o[1];
    return p;
  };
  // 低空飞过沙滩：旋翼下洗卷起沙尘
  H.forEach((h, i) => fx.add(spray({ at: (b, q) => { const p = hp(i, b), g = Math.max(groundY(p.x, p.z), 0); if (p.y - g > 70) return null; return V3(p.x + q.x * 16, g + 1, p.z + q.z * 16); },
    rate: 50, size: 14, up: 3, life: 1.6, alpha: 0.16, tint: [1.0, 0.86, 0.68], seed: 840 + i })));
  // 滩头还在烧的残骸
  [[292, -806, 6], [412, -836, 5], [250, -800, 3]].forEach(([x, z, s], i) => fx.add(fire({ p: V3(x, groundY(x, z) + 0.5, z), s, seed: 850 + i })));
  sunGlow(env);
  return {
    update(t) {
      const cen = V3();
      H.forEach((h, i) => {
        const p = hp(i, t), q = hp(i, t + 0.1);
        const yw = headingTo(p, q), climb = Math.atan2(q.y - p.y, 18.5);
        h.root.position.copy(p);
        h.root.rotation.set(-0.12 + climb * 0.3, yw, Math.sin(t * 0.8 + i) * 0.04, 'YXZ');
        h.root.updateMatrixWorld(true);
        h.spin(t + i * 0.3, 0.13);
        cen.add(p);
      });
      cen.multiplyScalar(1 / 3);
      const base = C.clone().add(V3(Math.sin(4 * DEG), Math.tan(8 * DEG), -Math.cos(4 * DEG)).multiplyScalar(1000));
      const k = smooth(1.7, 3.6, t) * 0.75;
      const look = base.clone().sub(C).normalize().lerp(cen.clone().sub(C).normalize(), k).add(C);
      cam(env, C, look, lerp(42, 30, smooth(1.8, 5, t)));
      shake(env.camera, t, 0.15 + 0.9 * Math.exp(-((t - T_PASS - 0.1) ** 2) / 0.12), 5, 83);
      return dawnLight({ shadowAt: cen, shadowR: 140, bloom: 1.2, grain: 0.01, dof: { focus: Math.max(40, cen.distanceTo(C)), range: 300, max: 0.25 } }, { exposure: 1.14 });
    },
    events: [{ t: 0, k: 'rotor' }, { t: 0.9, k: 'whizz' }, { t: 0, k: 'aftermath' }],
  };
}

// ———— N4 坦克纵队 ————
// 滩头往北是一道 17° 的坡（z −740 到 −820 爬升 25 格），坡顶以北是平的台地（高约 35）。三辆 99A 从坡下冲上来、翻过坡顶迎着镜头开，
//   镜头架在台地上（太阳在镜头身后：坦克正面一层暖光；朝南的坡背着光是暗的）。车道避开碉堡、铁丝网、拒马（按 world.json 的零件位置挑的）
async function shotColumn(env, add) {
  const { fx, groundY } = env;
  const LANES = [[334, -792, 0], [304, -797, -0.02], [360, -782, 0.03]];   // 起点 x、z，航向（车尾离第二道铁丝网十来格）
  const T = [];
  for (let i = 0; i < 3; i++) { const v = await vehicle('ztz99', env.REPO); add(v.root); T.push(v); }
  const SP = 11;
  const tp = (i, t) => { const [x, z, a] = LANES[i]; return V3(x - Math.sin(a) * SP * t, 0, z - Math.cos(a) * SP * t); };
  // 海上还在往岸上开的登陆艇、气垫艇（坡顶后面露出一截海）
  const L1 = landingCraft(env.T), L2 = landingCraft(env.T), HC = hovercraft(env.T);
  add(L1.root); add(L2.root); add(HC.root);
  // 还在烧的碉堡、残骸
  [[381, -848, 7], [275, -815, 5], [404, -742, 4], [262, -760, 3]].forEach(([x, z, s], i) => fx.add(fire({ p: V3(x, groundY(x, z) + 0.5, z), s, seed: 870 + i })));
  // 履带扬起的土
  fx.add((t, f) => {
    T.forEach((v, i) => {
      const back = V3(Math.sin(LANES[i][2]), 0, Math.cos(LANES[i][2])).multiplyScalar(14);
      for (let k = 0; k < 9; k++) {
        const a = k * 0.32 + ((t * 3.1) % 0.32), p = tp(i, t - a);
        const q = p.clone().add(back).add(V3(((k % 2) ? 1 : -1) * 4.5, 0, 0));
        q.y = groundY(q.x, q.z) + 1.5 + a * 2.2;
        f.sprite('puff', q, 7 + a * 9, 6 + a * 12, 0.34 * (1 - a / 3), 0, [0.82, 0.7, 0.55], k + i * 3);
      }
    });
  });
  // 二号车边开边打：炮口焰、车四周一圈土
  const FIRE_T = 4.1, gun = T[1];
  fx.add(muzzle({ p: () => gun.muzzle(), dir: () => gun.muzzleDir(), t0: FIRE_T, kind: 'tank', seed: 881 }));
  fx.add((t, f) => {
    const u = t - FIRE_T;
    if (u < 0 || u > 2.6) return;
    const c = gun.root.position;
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * Math.PI * 2, r = 6 + 26 * (1 - Math.exp(-u * 3));
      f.sprite('puff', c.clone().add(V3(Math.cos(a) * r, 2.5, Math.sin(a) * r)), 12 + u * 6, 8 + u * 10, 0.45 * (1 - u / 2.6), 0, [0.72, 0.63, 0.5], a);
    }
  });
  sunGlow(env);
  return {
    update(t) {
      SEA.amp = 0.8;
      { const p1 = V3(322, 0, -520 - t * 20), p2 = V3(396, 0, -470 - t * 22); onWaves(L1.root, p1.x, p1.z, 0.03, t, 1.8); onWaves(L2.root, p2.x, p2.z, -0.04, t, 1.8); }
      { const p = V3(352, 0, -600 - t * 30); onWaves(HC.root, p.x, p.z, 0, t, 2.6, 0.4); HC.spin(t); }
      T.forEach((v, i) => {
        const p = tp(i, t);
        onGround(env, v.root, p.x, p.z, LANES[i][2], 0.2);
        v.root.position.y += Math.sin(t * 9 + i) * 0.05;
        v.roll(SP * t);
        if (i === 1) {
          v.aim(lerp(0, 0.42, smooth(0.8, 2.8, t)), lerp(0.02, 0.06, smooth(0.8, 2.8, t)));
          const kick = t > FIRE_T ? Math.exp(-(t - FIRE_T) * 6) * (1 - Math.exp(-(t - FIRE_T) * 60)) : 0;
          v.kick(kick); v.root.rotateX(kick * 0.015);
        } else v.aim(Math.sin(t * 0.35 + i * 2) * 0.12, 0.03);
        v.root.updateMatrixWorld(true);
      });
      // 镜头：台地上、头车正前方偏一点，往后退着拍：车从坡顶冒出来、越开越近，最后头车占满半个画面
      const lead = T[0].root.position;
      const cz = lerp(-884, -896, ease(t / 6.5)), cx = lerp(328, 325, t / 6.5);
      const cp = V3(cx, groundY(cx, cz) + 5, cz);
      cam(env, cp, lead.clone().add(V3(2, 3.5, 0)).lerp(T[1].root.position, 0.2), 28);
      shake(env.camera, t, 0.2 + (t > FIRE_T ? 1.4 * Math.exp(-(t - FIRE_T) * 4) : 0), 6, 87);
      return dawnLight({ shadowAt: lead, shadowR: 140, bloom: 1.15, grain: 0.01, dof: { focus: cp.distanceTo(lead), range: 60, max: 0.35 } }, { exposure: 1.3, hemiI: 2.4 });
    },
    events: [{ t: 0, k: 'tankEngine' }, { t: 0, k: 'aftermath' }, { t: 0.9, k: 'turret' }, { t: FIRE_T, k: 'tankFire' }],
  };
}

// ———— N5 红蓝对峙 ————
async function shotVersus(env, add) {
  env.worldVisible(false);
  const Rd = await vehicle('ztz99', env.REPO), Bl = await vehicle('m1a2v3', env.REPO);
  add(Rd.root); add(Bl.root);
  const key = new THREE.DirectionalLight(0xffe6cc, 2.0); key.position.set(0, 30, 60); add(key);
  const rr = new THREE.DirectionalLight(0xff3c1e, 7.5); rr.position.set(-80, 22, -120); add(rr);
  const rb = new THREE.DirectionalLight(0x3c7cff, 7.5); rb.position.set(80, 22, -120); add(rb);
  const fl = new THREE.HemisphereLight(0x8090a8, 0x101010, 0.35); add(fl);
  const pr = V3(-19, -5.5, -60), pb = V3(19, -5.5, -60);
  const yr = -Math.PI / 2 - 0.42, yb = Math.PI / 2 + 0.42;
  return {
    update(t) {
      Rd.root.position.copy(pr); Rd.root.rotation.set(0, yr, 0);
      Bl.root.position.copy(pb); Bl.root.rotation.set(0, yb, 0);
      const k = smooth(0.4, 2.6, t);
      Rd.aim(0.42 * k, 0.02); Bl.aim(-0.42 * k, 0.02);
      Rd.root.updateMatrixWorld(true); Bl.root.updateMatrixWorld(true);
      cam(env, V3(0, lerp(1.5, 0.5, ease(t / 5.5)), lerp(0, -6, ease(t / 5.5))), V3(0, -2.5, -60), 36);
      return { exposure: 1.35, bloom: 0.85, fade: 0, grain: 0.012, vignette: 0.85, lift: 0 };
    },
    events: [{ t: 0.4, k: 'turret' }],
  };
}

// 和原片镜头同样的格式（promo.js 的 cut() 按 id 找）；terrain 是地形网格的中心（世界坐标）
export const NEW = [
  { id: 'N1', dur: 5.5, terrain: [1000, -1600], setup: shotJets },   // 地形网格的密处放在岛上（镜头附近全是海）
  { id: 'N2', dur: 7, terrain: [-400, -900], setup: shotFleetDawn },
  { id: 'N3', dur: 5, terrain: [360, -900], setup: shotHelis },
  { id: 'N4', dur: 6, terrain: [340, -820], setup: shotColumn },
  { id: 'N5', dur: 5, setup: shotVersus },
];
