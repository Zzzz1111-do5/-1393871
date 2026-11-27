// 时代广场宣传片（用户 11-21：「给这个游戏做一个顶级的宣传片，我要放到纽约时代广场的屏幕，3 分钟吧」）
//   用微电影《黎明之前》的镜头（shots.js）重新剪：整幅 16:9（不要宽银幕黑边）、夜戏提亮（大屏在亮处，太暗就是一片黑）、
//   英文字幕（纽约的观众）、慢镜头、换机位、同一场仗打到天亮（日出光照）；片名换成「ISLAND ASSAULT / 全面大战场」。
//   两边是虚构的红方 / 蓝方：不写真实国家，模型上的国旗、军徽在 models.js 里去掉（hideFlags、scrubInsignia）
//   三幕：一、深夜集结（0:00–0:45）二、H 时（0:45–1:40）三、天亮（1:40–2:31）片名、卖点、红蓝对峙、结尾（2:31–3:00）
//   天亮那一幕的大场面是专门拍的新镜头（promo_shots.js：机群掠海、舰队剪影、直升机编队、坦克纵队、红蓝对峙）
//   每个镜头：base 原镜头、from 从原镜头第几秒开始、speed 快慢（慢镜头 < 1）、cam 换机位、light 光照（night 提亮 / dawn 日出）、say 英文字幕
import * as THREE from 'three';
import { SHOTS as BASE } from './shots.js';
import { NEW, SUN, dawnLight, sunGlow } from './promo_shots.js';
import { V3, smooth, ease, clamp, lerp, DEG } from './lib.js';
import { fadeIO } from './titles.js';

const SANS = '"Noto Sans SC"', SERIF = '"Noto Serif SC"';
const find = id => BASE.find(s => s.id === id) || NEW.find(s => s.id === id);

// —— 光照 ——
// 夜戏提亮：曝光 +0.45 档、暗部抬一点、天光强一点（月夜的蓝还在，大屏上看得清形状）
function night(P) {
  return { ...P, exposure: (P.exposure ?? 1) * 1.37, lift: Math.max(P.lift ?? 0.012, 0.028), hemiI: (P.hemiI ?? 1.15) * 1.45, contrast: (P.contrast ?? 1.06) * 1.04, sat: (P.sat ?? 0.92) * 1.06 };
}
// 日出：太阳贴着地平线（和天亮那一镜同一个方向）、暖光镶边、雾是暖灰的；画面里摆上太阳（sunGlow）
function dawn(o = {}) { const f = P => dawnLight(P, o); f.sun = true; return f; }
const same = P => P;
// 海面的高光（月光路）：天亮以后是太阳的金色碎光
const GLINT_NIGHT = new THREE.Color(0x8fa4c8), GLINT_DAWN = new THREE.Color(2.2, 1.45, 0.8);

// —— 换机位（在原镜头摆好的镜头上再挪）：D 是镜头前方被拍的东西大概多远 ——
const fwdOf = c => new THREE.Vector3(0, 0, -1).applyQuaternion(c.quaternion);
// 长焦：往后退到 m 倍远、视场角收窄，画面里的东西一样大，背景压缩（大片感）
const tele = (m, D) => (c) => {
  const f = fwdOf(c);
  c.position.addScaledVector(f, -D * (m - 1));
  c.fov = 2 * Math.atan(Math.tan(c.fov * DEG / 2) / m) / DEG;
  c.far = Math.max(c.far, 120000);
  c.updateProjectionMatrix();
};
// 绕着被拍的东西转（deg0 → deg1 度），可以顺便抬高 / 降低
const orbit = (D, deg0, deg1, dy = 0, dur = 4) => (c, t) => {
  const f = fwdOf(c), piv = c.position.clone().addScaledVector(f, D);
  const a = lerp(deg0, deg1, ease(t / dur)) * DEG;
  const off = c.position.clone().sub(piv).applyAxisAngle(V3(0, 1, 0), a);
  off.y += dy;
  c.position.copy(piv).add(off);
  c.up.set(0, 1, 0);
  c.lookAt(piv);
};
// 往前推近
const push = (dist, dur = 4) => (c, t) => { c.position.addScaledVector(fwdOf(c), dist * ease(t / dur)); };
// 只收视场角（镜头不挪，前景不会挡上来）
const zoom = m => (c) => { c.fov = 2 * Math.atan(Math.tan(c.fov * DEG / 2) / m) / DEG; c.updateProjectionMatrix(); };
// 镜头往下压 / 往上抬一点（度）
const tilt = deg => (c) => { c.rotateX(deg * DEG); };
// 斜一点（荷兰角）
const dutch = deg => (c) => { c.rotateZ(deg * DEG); };
const both = (...fs) => (c, t) => { for (const f of fs) f(c, t); };

// —— 字幕 ——
// 大屏上要大、要粗：主字 6% 画高，副字 2.6%；白字带一圈暗的光晕（亮的画面上也看得清）
const big = (text, a, o = {}) => ({ text, x: o.x ?? 0.5, y: o.y ?? 0.5, size: o.size ?? 0.06, font: SANS, weight: 700, spacing: o.sp ?? 0.18, a, color: o.color || '#f4f1ea', glow: 'rgba(0,0,0,0.65)', align: o.align });
const small = (text, a, o = {}) => ({ text, x: o.x ?? 0.5, y: o.y ?? 0.58, size: o.size ?? 0.026, font: SANS, weight: 400, spacing: o.sp ?? 0.32, a, color: o.color || '#d9d3c6', glow: 'rgba(0,0,0,0.7)', align: o.align });
const tag = (text, a, side = 'red') => ({ text, x: 0.06, y: 0.88, size: 0.03, font: SANS, weight: 700, spacing: 0.22, a, align: 'left', color: side === 'red' ? '#ffb39a' : '#a9c6ff', glow: 'rgba(0,0,0,0.7)' });

// —— 一个宣传片镜头 ——
function cut(id, baseId, o = {}) {
  const S = find(baseId);
  if (!S) throw new Error('没有这个镜头：' + baseId);
  const from = o.from ?? 0, speed = o.speed ?? 1, dur = o.dur ?? Math.min(S.dur - from, (S.dur - from) / speed);
  // 音效：原镜头这一段里的事件，按快慢换算到宣传片的时间
  const events = (S.events || []).filter(e => e.t >= from - 0.05 && e.t <= from + dur * speed).map(e => ({ ...e, t: Math.max(0, (e.t - from) / speed), slow: speed < 0.9 }));
  return {
    id, base: baseId, dur, mark: o.mark, terrain: S.terrain, terrainOpt: S.terrainOpt, events, slow: speed < 0.9,
    async setup(env, add) {
      const sh = await S.setup(env, add);
      if (o.light && o.light.sun) sunGlow(env);
      const tmap = t => from + t * speed;
      return {
        ...sh,
        tmap,
        update(t) {
          let P = sh.update(tmap(t)) || {};
          if (o.cam) o.cam(env.camera, t, tmap(t));
          env.camera.updateMatrixWorld(true);
          P = (o.light || night)(P, t);
          env.sea.userData.mat.uniforms.uMoonC.value.copy((P.dawn || 0) > 0.5 ? GLINT_DAWN : GLINT_NIGHT);
          if (o.flash) P.flash = Math.max(P.flash || 0, o.flash(t));
          if (o.fadeIn) P.fade = Math.max(P.fade || 0, 1 - smooth(0, o.fadeIn, t));
          if (o.fadeOut) P.fade = Math.max(P.fade || 0, smooth(dur - o.fadeOut, dur, t));
          return P;
        },
        // 字幕换成英文的；原镜头的锁定框（box）留着，标签换成英文
        titles: (o.say || o.box) ? (t => [...(o.say ? o.say(t, dur) : []), ...(o.box && sh.titles ? (sh.titles(tmap(t)) || []).filter(x => x.box).map(x => ({ ...x, label: LOCK_EN[x.label] ?? x.label, sub: LOCK_EN[x.sub] ?? x.sub })) : [])]) : null,
      };
    },
  };
}

const LOCK_EN = { '锁定': 'LOCK', '搜索': 'SEARCH', '霹雳-10 · 红外锁定': 'IR LOCK', '霹雳-10': 'IR MISSILE' };

// 署名（CC BY 4.0，片子里实际出现的模型，见 models/*/credits.txt）
const CREDITS = [
  '3D models (Sketchfab, CC BY 4.0): ZTZ-99A2, J-15, Z-10 — 42manako  ·  J-20, F-22 — andertan  ·  Type 055 — FeriseCAT',
  'Type 054A, M1A2 SEPv2, Patriot — Muhamad Mirza Arrafi  ·  M4 — BarcodeGames  ·  Sand texture — Terrie Simmons-Ehrhardt  ·  VFX — ArmyVFX',
];

export const PROMO = [
  // ═══ 一、深夜集结 ═══
  cut('P01', 'S01', { mark: 'open', dur: 6.5, fadeIn: 1.2, say: (t) => [big('02:14', fadeIO(t, 1.2, 5.2, 0.8, 0.6), { y: 0.46, size: 0.07, sp: 0.3 }), small('SOMEWHERE IN THE ARCHIPELAGO', fadeIO(t, 1.8, 5.2, 0.8, 0.6), { y: 0.55 })] }),
  cut('P02', 'S02', { say: t => [tag('BLUE FORCE · HOLD THE BEACH', fadeIO(t, 0.6, 4.2, 0.5, 0.5), 'blue')] }),
  cut('P03', 'S04', { mark: 'fleet', say: t => [tag('RED FORCE · TAKE THE ISLAND', fadeIO(t, 0.6, 4.7, 0.5, 0.5), 'red')] }),
  cut('P04', 'S05'),
  cut('P05', 'S08'),
  cut('P06', 'S07B', { cam: tele(1.6, 140), dur: 3.4, from: 0.4 }),
  cut('P07', 'S06', { say: t => [small('“ALL UNITS — H-HOUR.”', fadeIO(t, 0.6, 3.7, 0.4, 0.4), { y: 0.84, size: 0.03, sp: 0.12 })] }),
  cut('P08', 'S10'),
  cut('P09', 'S07', { mark: 'hhour', say: t => [big('H-HOUR', fadeIO(t, 0.7, 3.4, 0.15, 0.35), { size: 0.085, sp: 0.4 })] }),
  cut('P10', 'S07', { from: 0.35, speed: 0.4, dur: 3.0, cam: tele(1.8, 260) }),   // 垂发出筒：慢镜头、长焦

  // ═══ 二、H 时 ═══
  cut('P11', 'S09', { mark: 'battle', say: t => [big('SEA', fadeIO(t, 0.25, 1.6, 0.1, 0.3), { size: 0.11, sp: 0.6 })] }),
  cut('P12', 'S09', { from: 1.8, speed: 0.45, dur: 3.0, cam: tele(1.7, 220) }),
  cut('P13', 'S11'),
  cut('P14', 'S12', { say: t => [big('LAND', fadeIO(t, 0.25, 1.6, 0.1, 0.3), { size: 0.11, sp: 0.6 })] }),
  cut('P15', 'S13'),
  cut('P16', 'S13', { from: 2.1, speed: 0.5, dur: 3.0, cam: zoom(1.2) }),   // 99A 开炮：慢镜头（只收视场角、不挪镜头：往后退会被铁丝网的桩子挡住）
  cut('P17', 'S14'),
  cut('P18', 'S16'),
  cut('P19', 'S16', { from: 0.4, speed: 0.4, dur: 3.0, cam: both(tilt(-6), dutch(-3)) }),   // 武装直升机火箭齐射：慢镜头（镜头往下压，直升机不贴着画面下边）
  cut('P20', 'S17'),
  cut('P21', 'S15', { box: true, say: t => [big('AIR', fadeIO(t, 0.25, 1.6, 0.1, 0.3), { size: 0.11, sp: 0.6 })] }),
  cut('P22', 'S15B'),
  cut('P23', 'S15C'),
  cut('P24', 'S15C', { from: 0.95, speed: 0.3, dur: 3.4 }),   // 击落：慢镜头
  cut('P25', 'S12', { from: 1.2, dur: 3.4, cam: both(tele(1.5, 120), dutch(-4)) }),
  cut('P26', 'S07B', { from: 0.6, dur: 3.2 }),

  // ═══ 三、天亮 ═══
  cut('P27', 'S18', { mark: 'dawn', dur: 9, light: (P) => ({ ...P, exposure: (P.exposure ?? 1.15) * 1.18, lift: 0.02 }), say: t => [big('SUNRISE.', fadeIO(t, 4.4, 7.7, 0.8, 0.6), { y: 0.45 }), small('THE ISLAND IS STILL CONTESTED', fadeIO(t, 5.0, 7.7, 0.8, 0.6), { y: 0.53 })] }),
  cut('P28', 'N2', { light: same, dur: 8.5 }),   // 舰队剪影
  cut('P29', 'S08', { light: dawn() }),
  cut('P30', 'N1', { light: same, dur: 6 }),   // 机群掠海
  cut('P31', 'S14', { light: dawn() }),
  cut('P32', 'N4', { light: same, dur: 6.5 }),   // 坦克纵队
  cut('P33', 'S16', { light: dawn(), cam: orbit(90, -20, 0, 6, 4.5) }),
  cut('P34', 'N3', { light: same, dur: 5.8 }),   // 直升机编队
  cut('P35', 'S12', { light: dawn(), cam: tele(1.4, 140) }),

  // ═══ 片名、卖点、红蓝对峙、结尾 ═══
  cut('P37', 'S19', { mark: 'title', dur: 7.5, light: same, say: t => [
    big('ISLAND ASSAULT', fadeIO(t, 0.55, 6.6, 0.25, 0.8), { y: 0.45, size: 0.1, sp: 0.16 }),
    { text: '全面大战场', x: 0.5, y: 0.555, size: 0.036, font: SERIF, weight: 700, spacing: 0.5, a: fadeIO(t, 1.2, 6.6, 0.8, 0.8), color: '#e8dccb', glow: 'rgba(255,170,90,0.35)' },
    small('LAND · SEA · AIR — ALL-OUT WAR', fadeIO(t, 1.8, 6.6, 0.8, 0.8), { y: 0.63, size: 0.024 })] }),
  cut('P38', 'S20', { mark: 'features', light: same, say: (t) => {
    const A = (a, b) => fadeIO(t, a, b, 0.35, 0.35);
    return [
      big('50+ VEHICLES', A(0.3, 3.6), { x: 0.08, y: 0.42, size: 0.06, align: 'left', sp: 0.1 }),
      small('TANKS · JETS · HELICOPTERS · WARSHIPS — DRIVE THEM ALL', A(0.6, 3.6), { x: 0.08, y: 0.5, align: 'left', size: 0.022, sp: 0.18 }),
      big('YOUR ISLAND. YOUR WAR.', A(4.0, 7.3), { x: 0.08, y: 0.42, size: 0.06, align: 'left', sp: 0.08 }),
      small('AMPHIBIOUS LANDINGS · NIGHT OPS · FULL COCKPITS & TANK INTERIORS', A(4.3, 7.3), { x: 0.08, y: 0.5, align: 'left', size: 0.022, sp: 0.14 }),
    ];
  } }),
  cut('P39', 'N5', { light: same, dur: 5.5, say: t => [big('RED  VS  BLUE', fadeIO(t, 0.3, 4.7, 0.3, 0.4), { y: 0.3, size: 0.075, sp: 0.2 }), small('CHOOSE YOUR SIDE', fadeIO(t, 0.7, 4.7, 0.3, 0.4), { y: 0.38 })] }),
  cut('P40', 'S21', { mark: 'end', dur: 10, light: same, say: (t) => {
    const a = fadeIO(t, 0.4, 9.6, 0.8, 0.8);
    return [
      big('ISLAND ASSAULT', a, { y: 0.34, size: 0.075, sp: 0.16 }),
      small('PLAY FREE ON ROBLOX', a, { y: 0.43, size: 0.034, sp: 0.3, color: '#f4f1ea' }),
      small('SEARCH  “ISLAND ASSAULT”  ·  全面大战场', a, { y: 0.49, size: 0.024, sp: 0.2 }),
      small('Cinematic rendered offline from in-game models and map. Fictional factions.', a * 0.8, { y: 0.64, size: 0.0135, sp: 0.06, color: '#9a948a' }),
      ...CREDITS.map((line, i) => small(line, a * 0.8, { y: 0.675 + i * 0.026, size: 0.0125, sp: 0.03, color: '#8f897f' })),
    ];
  } }),
];
