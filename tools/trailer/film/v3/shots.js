// 第三版微电影（用户 11-22：「给这个游戏做一个微电影宣传，之前的作废，这一版要体现游戏所有牛逼的点，用最新版做」）
//   用游戏现在的地图（Map.K = 3 放大以后的棕榈岛，按原样，不再另外放大）和现在的模型（福建舰原模型、歼-20 v4、F-22A、拆出机炮的阿帕奇……；直-10 11-27 删了）
//   分镜见 SHOTS；每个镜头 setup 搭好要用的东西，update(t) 摆好这一刻的镜头、模型、特效，返回后期参数；events 给配乐、音效（v3/audio.js）
import * as THREE from 'three';
import { V3, keys, ease, easeIn, easeOut, easeIO, smooth, lerp, shake, rng, DEG, fbm1, clamp, sat } from '../lib.js';
import { seaY, seaNormal, SEA } from '../world.js';
import { loadGLB } from '../models.js';
import { heightAt } from '../bigmap.js';

// 地图：原样（world.json 的坐标就是片子里的坐标）
export const BIGCFG = { id: true, fx: 990, fz: -2041 };

// 地图上的点（world.json 量的）
export const P = {
  blueBeach: V3(990, 0, -2041), bunkerB1: V3(820, 9, -2093), bunkerB2: V3(1183, 8, -2244),
  coastalE: V3(3593, 67, -2367), coastalW: V3(-3314, 52, -2234), lighthouse: V3(7500, 124, -900),
  airfield: V3(2340, 56, -3699), port: V3(-1485, 72, -3406), command: V3(780, 320, -5725), camp: V3(420, 170, -6514),
  carrier: V3(-1260, 0, 6750), lhd: V3(990, 0, 6450), lstW: V3(-3000, 0, 6150), lstE: V3(2850, 0, 6150),
};
// 福建舰：游戏里甲板全长 620 格（tools/models/fujian.py）；片子里飞机、车都是真实比例（1 米 = 2.8 格），航母也按真舰 316 米放大
export const CV_K = 316 * 2.8 / 620;

// 世界里的零件先过一遍：零件拼的航母（游戏里没导入原模型时的退路）不要，片子里摆福建舰原模型；
//   手雷抛物线、弹着点特效这些游戏里的临时零件不要
export function prepWorld(world) {
  const c = world.fleet && world.fleet.find(f => f.kind === 'carrier');
  world.parts = world.parts.filter(p => {
    if (/^(NadeArc|ClientFx\/Imp)/.test(p.g)) return false;
    if (c && p.g === 'Map/Fleet' && Math.abs(p.cf[0] - c.x) < 110 && Math.abs(p.cf[2] - c.z) < 360) return false;
    return true;
  });
}

const NIGHT_FOG = new THREE.Color(0x0e1420);
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

// 福建舰（原模型，不带贴图，每块一种颜色）
export async function fujian(env) {
  const src = await loadGLB(`${env.REPO}/models/ship/fujian.glb`);
  const model = src.clone(true);
  model.traverse(o => {
    if (!o.isMesh) return;
    o.castShadow = o.receiveShadow = true;
    const ms = Array.isArray(o.material) ? o.material : [o.material];
    o.material = ms.map(m => { m = m.clone(); m.envMapIntensity = 0.2; m.roughness = Math.max(0.55, m.roughness ?? 0.6); return m; });
    if (o.material.length === 1) o.material = o.material[0];
  });
  model.scale.setScalar(CV_K);
  const root = new THREE.Group(); root.name = 'ship:fujian';
  root.add(model);
  return { root, k: CV_K, deck: 30.5 * CV_K, len: 620 * CV_K };
}

// —— 调试镜头：看地图（still DBG1 0 …）——
function dbg(pos, look, fov = 40, opt = {}) {
  return async (env, add) => {
    let cv = null;
    if (opt.carrier) { cv = await fujian(env); add(cv.root); cv.root.position.set(P.carrier.x, 0, P.carrier.z); cv.root.updateMatrixWorld(true); }
    return {
      update(t) {
        cam(env, pos, look, fov);
        return { exposure: opt.exp ?? 1.2, shadowAt: look, shadowR: 400, bloom: 1.1, fogDensity: opt.fog ?? 0.00012, fogColor: NIGHT_FOG, moonI: 3.4, hemiI: 1.4 };
      },
    };
  };
}

export const SHOTS = [
  { id: 'DBG1', dur: 1, terrain: () => [990, -2041], setup: dbg(V3(1100, 60, -1350), V3(990, 10, -2150), 40) },
  { id: 'DBG2', dur: 1, terrain: () => [-1260, 6750], setup: dbg(V3(-700, 160, 6100), V3(-1260, 30, 6750), 36, { carrier: true }) },
  { id: 'DBG3', dur: 1, terrain: () => [500, -3500], setup: dbg(V3(800, 2600, 1800), V3(400, 0, -3800), 45, { fog: 0.00005 }) },
  { id: 'DBG4', dur: 1, terrain: () => [820, -2093], setup: dbg(V3(860, 22, -2040), V3(820, 10, -2100), 50) },
  { id: 'DBG5', dur: 1, terrain: () => [-1485, -3406], setup: dbg(V3(-1300, 160, -3000), V3(-1485, 70, -3406), 40) },
  { id: 'DBG6', dur: 1, terrain: () => [7500, -900], setup: dbg(V3(6200, 150, 300), V3(7500, 110, -900), 38) },
];
let T0 = 0;
for (const s of SHOTS) { s.t0 = T0; T0 += s.dur; }
export const TOTAL = T0;
