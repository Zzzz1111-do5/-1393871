// 海湾战争版的画面叠加层（画在输出画布的宽银幕画面里）：光电吊舱、无人机转塔、99A / M1A2 炮长热像仪、告警
//   都按真东西的样子：白热灰度画面 + 细线符号、等宽数字、角上的参数块
import { clamp, lerp } from '../lib.js';
export { plane, interior, drawHud } from '../v3/kit.js';

const MONO = '"Noto Sans SC", monospace';
function frame(g, W, H, ah) { return { top: (H - ah) / 2, u: ah / 1080, cx: W / 2, cy: (H - ah) / 2 + ah / 2 }; }
function txt(g, s, x, y, size, o = {}) {
  g.font = `${o.w || 600} ${Math.round(size)}px ${o.f || MONO}`;
  g.textAlign = o.a || 'left'; g.textBaseline = o.b || 'middle';
  if (o.bg) { const m = g.measureText(s); g.save(); g.fillStyle = o.bg; g.fillRect(x - (o.a === 'center' ? m.width / 2 : (o.a === 'right' ? m.width : 0)) - 4, y - size * 0.62, m.width + 8, size * 1.24); g.restore(); }
  g.fillText(s, x, y);
}
const pad2 = n => String(Math.floor(n)).padStart(2, '0');

// 光电吊舱（歼-16 / 歼-35 的瞄准吊舱）：o = { fov, zoom, mode, az, el, rng, lat, lon, alt, boxes: [{x, y, s, label, st}], cross: [x, y], msg, t }
//   boxes 的 x、y 是画面坐标（0～1，宽银幕画面里）；st：'scan' 灰框、'trk' 白框跟踪、'lock' 菱形锁定、'hit' 打中
export function drawEO(g, W, H, ah, o = {}) {
  const { top, u, cx, cy } = frame(g, W, H, ah);
  const t = o.t || 0;
  g.save();
  g.strokeStyle = 'rgba(235,240,235,0.95)'; g.fillStyle = 'rgba(235,240,235,0.95)'; g.lineWidth = Math.max(1, 1.6 * u);
  // 中心十字（中间空一块）、四角的框
  const X = o.cross ? o.cross[0] * W : cx, Y = o.cross ? top + o.cross[1] * ah : cy;
  const gap = 26 * u, L = 120 * u;
  g.beginPath();
  g.moveTo(X - gap - L, Y); g.lineTo(X - gap, Y); g.moveTo(X + gap, Y); g.lineTo(X + gap + L, Y);
  g.moveTo(X, Y - gap - L * 0.7); g.lineTo(X, Y - gap); g.moveTo(X, Y + gap); g.lineTo(X, Y + gap + L * 0.7);
  g.stroke();
  const bx = 300 * u, by = 210 * u, bl = 40 * u;
  g.beginPath();
  for (const [sx, sy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) { g.moveTo(cx + sx * bx, cy + sy * by - sy * bl); g.lineTo(cx + sx * bx, cy + sy * by); g.lineTo(cx + sx * bx - sx * bl, cy + sy * by); }
  g.stroke();
  // 目标框
  for (const b of o.boxes || []) {
    const x = b.x * W, y = top + b.y * ah, s = (b.s || 0.03) * ah;
    const blink = b.st === 'lock' ? ((t * 6) % 1 < 0.6 ? 1 : 0.35) : 1;
    g.globalAlpha = blink * (b.a ?? 1);
    if (b.st === 'scan') { g.setLineDash([6 * u, 6 * u]); g.strokeRect(x - s, y - s, 2 * s, 2 * s); g.setLineDash([]); }
    else if (b.st === 'trk') { g.strokeRect(x - s, y - s, 2 * s, 2 * s); }
    else if (b.st === 'lock') {
      g.strokeRect(x - s, y - s, 2 * s, 2 * s);
      g.beginPath(); g.moveTo(x, y - s * 1.45); g.lineTo(x + s * 1.45, y); g.lineTo(x, y + s * 1.45); g.lineTo(x - s * 1.45, y); g.closePath(); g.stroke();
    } else if (b.st === 'hit') { g.beginPath(); g.moveTo(x - s, y - s); g.lineTo(x + s, y + s); g.moveTo(x + s, y - s); g.lineTo(x - s, y + s); g.stroke(); }
    if (b.label) txt(g, b.label, x + s + 6 * u, y - s + 9 * u, 17 * u);
    g.globalAlpha = 1;
  }
  // 角上的参数
  const s = 20 * u;
  txt(g, o.mode || 'WHOT', W * 0.07, top + 60 * u, s);
  txt(g, o.fov || 'NFOV', W * 0.07, top + 88 * u, s);
  txt(g, `ZOOM ×${(o.zoom ?? 12).toFixed(1)}`, W * 0.07, top + 116 * u, s);
  txt(g, 'TGP', W * 0.93, top + 60 * u, s, { a: 'right' });
  txt(g, o.trk || 'PT TRK', W * 0.93, top + 88 * u, s, { a: 'right' });
  txt(g, `AZ ${(o.az ?? 12).toFixed(1).padStart(5, '0')}  EL -${(o.el ?? 24).toFixed(1)}`, cx, top + 60 * u, s, { a: 'center' });
  txt(g, `RNG ${(o.rng ?? 18.4).toFixed(1)} KM`, W * 0.07, top + ah - 116 * u, s);
  txt(g, `ALT ${Math.round(o.alt ?? 21500)}`, W * 0.07, top + ah - 88 * u, s);
  txt(g, `N ${o.lat || '29°12.44'}  E ${o.lon || '047°31.08'}`, W * 0.07, top + ah - 60 * u, s);
  if (o.wpn) txt(g, o.wpn, W * 0.93, top + ah - 88 * u, s, { a: 'right' });
  if (o.msg) txt(g, o.msg, cx, top + ah - 70 * u, 26 * u, { a: 'center', w: 700 });
  if (o.laser && (t * 4) % 1 < 0.7) txt(g, 'L', X + gap + 8 * u, Y + gap + 14 * u, 22 * u, { w: 700 });
  g.restore();
}
// 无人机转塔（察打一体无人机的光电球）：比吊舱多一圈刻度、罗盘带，参数在四角
export function drawDrone(g, W, H, ah, o = {}) {
  const { top, u, cx, cy } = frame(g, W, H, ah);
  const t = o.t || 0;
  g.save();
  g.strokeStyle = 'rgba(240,240,240,0.92)'; g.fillStyle = 'rgba(240,240,240,0.92)'; g.lineWidth = Math.max(1, 1.5 * u);
  const X = o.cross ? o.cross[0] * W : cx, Y = o.cross ? top + o.cross[1] * ah : cy;
  // 十字 + 中心小方框
  g.beginPath();
  g.moveTo(X - 300 * u, Y); g.lineTo(X - 34 * u, Y); g.moveTo(X + 34 * u, Y); g.lineTo(X + 300 * u, Y);
  g.moveTo(X, Y - 220 * u); g.lineTo(X, Y - 34 * u); g.moveTo(X, Y + 34 * u); g.lineTo(X, Y + 220 * u);
  g.stroke();
  g.strokeRect(X - 12 * u, Y - 12 * u, 24 * u, 24 * u);
  for (let k = 1; k <= 5; k++) { g.beginPath(); g.moveTo(X - 34 * u - k * 50 * u, Y - 8 * u); g.lineTo(X - 34 * u - k * 50 * u, Y + 8 * u); g.moveTo(X + 34 * u + k * 50 * u, Y - 8 * u); g.lineTo(X + 34 * u + k * 50 * u, Y + 8 * u); g.stroke(); }
  // 罗盘带
  const hdg = o.hdg ?? 32, by = top + 40 * u;
  for (let d = -40; d <= 40; d += 5) {
    const v = Math.round(hdg / 5) * 5 + d, x = cx + (v - hdg) * 7 * u;
    const big = ((v % 10) + 10) % 10 === 0;
    g.beginPath(); g.moveTo(x, by); g.lineTo(x, by + (big ? 14 : 7) * u); g.stroke();
    if (big) txt(g, String(((v % 360) + 360) % 360).padStart(3, '0'), x, by + 28 * u, 15 * u, { a: 'center' });
  }
  g.beginPath(); g.moveTo(cx, by - 2 * u); g.lineTo(cx - 7 * u, by - 12 * u); g.lineTo(cx + 7 * u, by - 12 * u); g.closePath(); g.fill();
  const s = 19 * u, L = W * 0.06, Rr = W * 0.94;
  txt(g, o.mode || 'IR WHT', L, top + 90 * u, s);
  txt(g, `FOV ${(o.fov ?? 0.9).toFixed(2)}°`, L, top + 116 * u, s);
  txt(g, o.uav || 'GJ-2  AV-07', Rr, top + 90 * u, s, { a: 'right' });
  txt(g, `ALT ${Math.round(o.alt ?? 24600)} FT`, Rr, top + 116 * u, s, { a: 'right' });
  txt(g, `SLANT ${(o.rng ?? 11.8).toFixed(1)} KM`, L, top + ah - 112 * u, s);
  txt(g, `TGT  38R QU ${o.grid || '4417 2209'}`, L, top + ah - 86 * u, s);
  const tt = o.clock ?? (5 * 3600 + 12 * 60 + t);
  txt(g, `${pad2(tt / 3600)}:${pad2((tt / 60) % 60)}:${pad2(tt % 60)}Z`, L, top + ah - 60 * u, s);
  if (o.wpn) txt(g, o.wpn, Rr, top + ah - 86 * u, s, { a: 'right' });
  if (o.tof != null) txt(g, `TOF ${Math.max(0, o.tof).toFixed(0).padStart(2, '0')}`, Rr, top + ah - 60 * u, s, { a: 'right' });
  if (o.laser && (t * 3) % 1 < 0.75) { txt(g, 'LSR', X + 40 * u, Y + 40 * u, 20 * u, { w: 700 }); }
  if (o.msg) txt(g, o.msg, cx, top + ah - 70 * u, 26 * u, { a: 'center', w: 700 });
  g.restore();
}
// 99A 炮长热像仪：中间瞄准标（倒 V + 横线、测距刻度），下面一排数字：距离、弹种、待发；上面「热像 · 窄视场」
export function drawSight99(g, W, H, ah, o = {}) {
  const { top, u, cx, cy } = frame(g, W, H, ah);
  const t = o.t || 0;
  g.save();
  // 外面一圈黑框（镜子里的画面是长方形）
  g.fillStyle = '#000';
  const vw = ah * 1.5, vh = ah * 0.9, x0 = cx - vw / 2, y0 = cy - vh / 2;
  g.fillRect(0, top, W, y0 - top); g.fillRect(0, y0 + vh, W, top + ah - y0 - vh); g.fillRect(0, y0, x0, vh); g.fillRect(x0 + vw, y0, W - x0 - vw, vh);
  g.strokeStyle = 'rgba(250,250,250,0.95)'; g.fillStyle = 'rgba(250,250,250,0.95)'; g.lineWidth = Math.max(1.2, 2 * u);
  const X = cx + (o.dx || 0) * ah, Y = cy + (o.dy || 0) * ah;
  // 倒 V 瞄准标 + 两边横线（中间断开）
  g.beginPath();
  g.moveTo(X - 26 * u, Y + 22 * u); g.lineTo(X, Y); g.lineTo(X + 26 * u, Y + 22 * u);
  g.moveTo(X - 260 * u, Y); g.lineTo(X - 60 * u, Y); g.moveTo(X + 60 * u, Y); g.lineTo(X + 260 * u, Y);
  g.moveTo(X, Y + 60 * u); g.lineTo(X, Y + 200 * u);
  g.stroke();
  for (let k = 1; k <= 4; k++) { g.beginPath(); g.moveTo(X - 60 * u - k * 50 * u, Y); g.lineTo(X - 60 * u - k * 50 * u, Y + 10 * u); g.moveTo(X + 60 * u + k * 50 * u, Y); g.lineTo(X + 60 * u + k * 50 * u, Y + 10 * u); g.stroke(); }
  // 右边的距离分划（0～4 千米）
  const rx = x0 + vw - 70 * u;
  for (let k = 0; k <= 8; k++) { const yy = y0 + vh * 0.2 + k * vh * 0.07; g.beginPath(); g.moveTo(rx, yy); g.lineTo(rx + (k % 2 ? 10 : 18) * u, yy); g.stroke(); if (k % 2 === 0) txt(g, String(k / 2), rx + 26 * u, yy, 15 * u); }
  const ry = y0 + vh * 0.2 + clamp((o.range || 0) / 500, 0, 8) * vh * 0.07;
  g.beginPath(); g.moveTo(rx - 4 * u, ry); g.lineTo(rx - 16 * u, ry - 7 * u); g.lineTo(rx - 16 * u, ry + 7 * u); g.closePath(); g.fill();
  // 上、下的字
  txt(g, '热像  窄视场  ×' + (o.zoom || 12), x0 + 24 * u, y0 + 30 * u, 20 * u);
  txt(g, o.ammo || '穿甲弹', x0 + vw - 24 * u, y0 + 30 * u, 20 * u, { a: 'right' });
  const rng = o.range ? String(Math.round(o.range)).padStart(4, '0') : '----';
  txt(g, rng, cx - 140 * u, y0 + vh - 34 * u, 30 * u, { w: 700, a: 'center' });
  txt(g, '米', cx - 80 * u, y0 + vh - 32 * u, 18 * u);
  const ready = o.ready ?? true;
  if (ready) txt(g, '待发', cx + 40 * u, y0 + vh - 34 * u, 24 * u, { w: 700 });
  else if ((t * 3) % 1 < 0.6) txt(g, '装填', cx + 40 * u, y0 + vh - 34 * u, 24 * u, { w: 700 });
  if (o.lead) txt(g, `提前 ${o.lead}`, cx + 150 * u, y0 + vh - 34 * u, 18 * u);
  if (o.msg) txt(g, o.msg, cx, y0 + vh * 0.78, 30 * u, { a: 'center', w: 800, bg: 'rgba(0,0,0,0.35)' });
  g.restore();
}
// M1A2 炮长主瞄准镜（GPS 热像）：十字分划（中间空、细线），左下距离、右下弹种 / READY，上面 WHOT / 10X
export function drawSightM1(g, W, H, ah, o = {}) {
  const { top, u, cx, cy } = frame(g, W, H, ah);
  const t = o.t || 0;
  g.save();
  g.fillStyle = '#000';
  const r = ah * 0.47;
  g.beginPath(); g.rect(0, top, W, ah); g.arc(cx, cy, r, 0, Math.PI * 2, true); g.fill('evenodd');
  const grd = g.createRadialGradient(cx, cy, r * 0.8, cx, cy, r);
  grd.addColorStop(0, 'rgba(0,0,0,0)'); grd.addColorStop(1, 'rgba(0,0,0,0.85)');
  g.fillStyle = grd; g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2); g.fill();
  g.strokeStyle = 'rgba(245,245,245,0.95)'; g.fillStyle = 'rgba(245,245,245,0.95)'; g.lineWidth = Math.max(1.2, 1.8 * u);
  const X = cx + (o.dx || 0) * ah, Y = cy + (o.dy || 0) * ah;
  g.beginPath();
  g.moveTo(X - r, Y); g.lineTo(X - 40 * u, Y); g.moveTo(X + 40 * u, Y); g.lineTo(X + r, Y);
  g.moveTo(X, Y - r); g.lineTo(X, Y - 40 * u); g.moveTo(X, Y + 40 * u); g.lineTo(X, Y + r);
  g.stroke();
  g.strokeRect(X - 40 * u, Y - 22 * u, 80 * u, 44 * u);   // 中间的框
  g.beginPath(); g.arc(X, Y, 2.5 * u, 0, Math.PI * 2); g.fill();
  txt(g, 'WHOT  10X', cx - r * 0.62, cy - r * 0.78, 20 * u);
  txt(g, o.ammo || 'SABOT', cx + r * 0.62, cy - r * 0.78, 20 * u, { a: 'right' });
  txt(g, o.range ? String(Math.round(o.range)) : '----', cx - r * 0.55, cy + r * 0.8, 28 * u, { w: 700 });
  if (o.ready ?? true) txt(g, 'READY', cx + r * 0.55, cy + r * 0.8, 24 * u, { w: 700, a: 'right' });
  if (o.msg) txt(g, o.msg, cx, cy + r * 0.55, 28 * u, { a: 'center', w: 800, bg: 'rgba(0,0,0,0.35)' });
  g.restore();
}
// 直升机告警：右上角雷达告警圆屏（威胁方位）、中间闪「导弹来袭」
export function drawWarn(g, W, H, ah, o = {}) {
  const { top, u, cx, cy } = frame(g, W, H, ah);
  const t = o.t || 0;
  g.save();
  const R = 90 * u, X = W - 150 * u, Y = top + 150 * u;
  g.fillStyle = 'rgba(0,0,0,0.55)'; g.beginPath(); g.arc(X, Y, R + 10 * u, 0, Math.PI * 2); g.fill();
  g.strokeStyle = 'rgba(120,255,150,0.9)'; g.lineWidth = 1.5 * u;
  g.beginPath(); g.arc(X, Y, R, 0, Math.PI * 2); g.stroke();
  g.beginPath(); g.arc(X, Y, R * 0.5, 0, Math.PI * 2); g.stroke();
  for (let k = 0; k < 12; k++) { const a = k / 12 * Math.PI * 2; g.beginPath(); g.moveTo(X + Math.cos(a) * R * 0.92, Y + Math.sin(a) * R * 0.92); g.lineTo(X + Math.cos(a) * R, Y + Math.sin(a) * R); g.stroke(); }
  if (o.threat != null) {
    const a = o.threat - Math.PI / 2, rr = R * 0.72;
    const blink = o.launch ? ((t * 8) % 1 < 0.5) : true;
    if (blink) {
      g.fillStyle = o.launch ? 'rgba(255,70,50,1)' : 'rgba(255,220,90,1)';
      txt(g, 'SA', X + Math.cos(a) * rr, Y + Math.sin(a) * rr, 20 * u, { a: 'center', w: 800 });
      g.strokeStyle = g.fillStyle; g.beginPath(); g.arc(X + Math.cos(a) * rr, Y + Math.sin(a) * rr, 16 * u, 0, Math.PI * 2); g.stroke();
    }
  }
  if (o.msg && ((t * 4) % 1 < 0.6)) {
    g.fillStyle = 'rgba(255,60,40,0.95)';
    txt(g, o.msg, cx, top + ah * 0.2, 40 * u, { a: 'center', w: 800 });
  }
  if (o.sub) { g.fillStyle = 'rgba(240,240,240,0.9)'; txt(g, o.sub, cx, top + ah * 0.2 + 46 * u, 22 * u, { a: 'center' }); }
  g.restore();
}
// 片中的说明字（左下角一行型号 / 地点，灰白、等宽）
export function caption(text, sub, a, x = 0.06, y = 0.84) {
  const out = [{ text, x, y, size: 0.019, font: '"Noto Sans SC"', align: 'left', spacing: 0.18, a, color: '#ece6da' }];
  if (sub) out.push({ text: sub, x, y: y + 0.035, size: 0.0135, font: '"Noto Sans SC"', align: 'left', spacing: 0.22, a: a * 0.85, color: '#b9b2a4' });
  return out;
}
