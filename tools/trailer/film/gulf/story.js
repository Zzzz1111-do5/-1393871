// 海湾战争版宣传片 · 短剧版（用户 11-22：「很多动作逻辑上链接不起来，这个短片容易让人看得一头雾水，爽点啊啥的，你就根据目前 AI 短剧那种剧本逻辑做吧」）
//   结构照短剧：开头 3 秒钩子（主角被击中、定格「生死未卜」）→「6 小时前」倒叙 → 指挥所下任务（日落前拿下油田）→
//   电子沙盘讲清楚「三颗钉子」→ 每一步都是「威胁 → 应对 → 爽点」：
//     ① 利剑（歼-35）放诱饵骗过爱国者，46 公里外投弹，6 发全中
//     ② 天眼（无人机）端掉正在炮击集结地的炮兵
//     ③ 铁拳（99A 营长，主角）对毒蛇（M1A2 连长）：被击中——反应装甲挡住（钩子在这里接上）——反杀开罐
//   → 反转：死神（阿帕奇）偷袭后续纵队，嚣张「没带防空，随便打」→ 盾牌（PGL-625）打脸击落 →
//   蓝方增援赶来 → 雷霆（歼-16）38 公里外 4 发全中 → 日落拿下油田 → 片名
//   每一条剪辑（EDIT）从一个原镜头（gulf/shots.js 的 SHOTS）截一段画面（可以定格），叠：对白（下面黑边里，带说话人名牌）、
//   人物字卡（左边，阵营色）、爽点大字（正中）、时间戳（左上，打字机）、任务清单（右上）、警报横幅（上面）、说明（左下）
import { clamp, smooth, easeOut, lerp } from '../lib.js';

const FPS = 24;
const SANS = '"Noto Sans SC"', SERIF = '"Noto Serif SC"';
// 说话人：名牌颜色（红方红、蓝方蓝、指挥所金）
const RED = '#c8352a', BLUE = '#2a6cc4', GOLD = '#b8842a';
const WHO = { 长城: GOLD, 利剑: RED, 天眼: RED, 铁拳: RED, 盾牌: RED, 雷霆: RED, 爱国者阵地: BLUE, 毒蛇: BLUE, 死神: BLUE };
const SIDE = { red: { bar: '#e0402e', sub: '#ff9a84' }, blue: { bar: '#3d8fe8', sub: '#9cc8ff' } };
export const GOALS = ['爱国者防空阵地', 'M109 炮兵阵地', '沙梁 M1A2 坦克连'];

// 一条剪辑：src 原镜头（null = 黑场）、from 从原镜头第几秒开始、dur 多长、freeze 从第几秒起定格（画面停住、只有字在动）
//   subs [开始, 结束, 说话人, 台词]、card [开始, 结束, 名字, 身份, 阵营, 一句话]、big [开始, 结束, 大字, 小字, 颜色]、
//   stamp [开始, 结束, 时间, 地点]、info [开始, 结束, 说明]、alert [开始, 结束, 警报]、list [开始, 结束, 完成了几项]、sfx 剧情音效
function E(id, src, from, dur, o = {}) {
  return { id, src, from, dur: Math.round(dur * FPS) / FPS, ...o };
}
const hookLook = fr => t => {
  if (t < fr) return {};
  const u = t - fr;
  return { filter: `saturate(${lerp(0.6, 0.1, smooth(0, 0.25, u))}) contrast(1.18) brightness(0.9)`, scale: 1 + 0.05 * easeOut(u / 1.6), flash: 0.55 * Math.exp(-u * 9) };
};

export const EDIT = [
  // —————— 钩子：主角被击中，定格 ——————
  E('H1', 'G15', 0.3, 1.7, { subs: [[0.05, 0.85, '毒蛇', '锁定红方领头车。'], [0.95, 1.7, '毒蛇', '开火！']] }),
  E('H2', 'G16', 0.25, 2.4, {
    freeze: 0.85, look: hookLook(0.85),
    card: [[0.95, 2.4, '铁拳', '红方 · 99A 坦克营营长', 'red', '生死未卜']],
    sfx: [{ t: 0.85, k: 'freezeHit' }, { t: 1.25, k: 'heart' }, { t: 1.95, k: 'heart' }],
  }),
  E('H3', null, 0, 1.5, { black: '6 小时前', sfx: [{ t: 0, k: 'rewind' }] }),

  // —————— 下任务、电子沙盘 ——————
  E('S1', 'G01', 0.5, 4.6, {
    stamp: [[0.3, 4.4, '02:40', '沙海 · 红蓝两军边境']],
    subs: [[1.2, 2.4, '长城', '各单位注意。'], [2.6, 4.5, '长城', '日落之前，拿下油田！']],
  }),
  E('MAP', 'GMAP', 0, 9.8, {
    subs: [[0.8, 2.8, '长城', '想拿油田，先拔掉三颗钉子。'], [3.0, 4.5, '长城', '利剑，敲掉爱国者！'], [4.6, 6.1, '长城', '天眼，端掉炮兵！'],
      [6.2, 8.0, '长城', '铁拳，正面突破沙梁！'], [8.3, 9.6, '铁拳', '铁拳收到！']],
    sfx: [{ t: 0, k: 'mapOn' }, { t: 3.0, k: 'mark' }, { t: 4.6, k: 'mark' }, { t: 6.2, k: 'mark' }],
  }),

  // —————— 第一颗钉子：利剑 vs 爱国者 ——————
  E('A1', 'G03', 0.2, 3.6, {
    card: [[0.3, 3.4, '爱国者', '蓝方 · 防空导弹阵地', 'blue', '射程 160 公里']],
    subs: [[1.1, 3.4, '爱国者阵地', '雷达开机，来一架打一架。']],
  }),
  E('A2', 'G04', 0, 3.8, {
    card: [[0.2, 3.5, '利剑', '红方 · 歼-35 四机编队', 'red', '隐身 · 9000 米高空']],
    subs: [[0.5, 1.9, '利剑', '利剑编队，放诱饵。'], [2.1, 3.6, '利剑', '让他们打。']],
  }),
  E('A3', 'G05', 0.2, 3.0, { subs: [[0.15, 1.3, '爱国者阵地', '发现目标！发射！'], [1.45, 2.9, '爱国者阵地', '全部打出去！']] }),
  E('A4', 'G06', 0, 4.0, { subs: [[0.3, 1.8, '利剑', '他们打的是诱饵。'], [2.4, 3.9, '利剑', '锁定……投弹！']] }),
  E('A5', 'G08', 0, 3.0, { subs: [[0.3, 1.7, '利剑', '弹已离机，返航。']], info: [[0.6, 2.9, '46 公里外投弹 · 炸弹自己滑翔过去']] }),
  E('A6', 'G07', 0, 5.6, {
    stamp: [[0.05, 1.3, '3 分钟后', '']],
    big: [[3.3, 4.6, '6 / 6', '全部命中']],
    subs: [[3.9, 5.5, '长城', '第一颗钉子，拔了！']],
    list: [4.2, 5.6, 1],
  }),

  // —————— 第二颗钉子：天眼 vs 炮兵 ——————
  E('B1', 'G09', 0, 3.4, {
    card: [[0.2, 3.2, '天眼', '红方 · 攻击-2 察打一体无人机', 'red', '7600 米高空盘旋']],
    subs: [[0.4, 1.7, '天眼', '发现蓝方炮兵阵地。'], [1.8, 3.3, '天眼', '正在炮击铁拳的集结地！']],
  }),
  E('B2', 'G10', 0, 3.6, { subs: [[0.9, 1.9, '天眼', '激光照射。'], [2.05, 2.9, '天眼', '发射！']] }),
  E('B3', 'G11', 0.3, 2.4, { big: [[0.85, 2.3, '命中！']] }),
  E('B4', 'G11B', 0, 3.6, { subs: [[0.2, 1.5, '天眼', '炮兵阵地，清除。'], [1.8, 3.0, '长城', '第二颗！']], list: [1.5, 3.6, 2] }),

  // —————— 第三颗钉子：铁拳 vs 毒蛇（钩子接上）——————
  E('C1', 'G12', 0, 4.8, {
    subs: [[0.3, 2.0, '长城', '铁拳，头顶的钉子拔干净了。'], [2.2, 3.5, '铁拳', '全营——出发！']],
    card: [[2.4, 4.7, '铁拳', '红方 · 99A 坦克营营长', 'red', '全营 31 辆 99A']],
  }),
  E('C2', 'G13', 0, 3.6, { subs: [[0.3, 2.4, '铁拳', '沙梁后面有 M1A2，都盯紧了！']] }),
  E('C3', 'G14', 0, 3.8, {
    card: [[0.2, 3.6, '毒蛇', '蓝方 · M1A2 坦克连连长', 'blue', '守着沙梁 · 14 辆 M1A2']],
    subs: [[0.5, 1.8, '毒蛇', '他们看不见我们。'], [1.9, 3.7, '毒蛇', '放近了打，一辆都别放走。']],
  }),
  E('C4', 'G15', 0, 2.8, { stamp: [[0.05, 1.6, '08:40', '沙梁']], subs: [[0.3, 1.4, '毒蛇', '锁定红方领头车。'], [1.45, 2.3, '毒蛇', '开火！']] }),
  E('C5', 'G16', 0, 4.3, {
    subs: [[1.0, 1.9, '毒蛇', '打中了！'], [2.0, 3.0, '毒蛇', '它……还在动？！'], [3.15, 4.2, '铁拳', '该我们了。']],
    big: [[1.5, 2.9, '挡住了！', '爆炸反应装甲']],
  }),
  E('C6', 'G18', 0, 1.33, { subs: [[0.05, 1.33, '铁拳', '2400，穿甲弹——放！']] }),
  E('C7', 'G17', 0.65, 1.6, { subs: [[0.45, 1.55, '毒蛇', '倒车！快倒车！']] }),
  E('C8', 'G18', 1.55, 2.0, {}),
  E('C9', 'G19', 0, 3.8, { big: [[0.5, 2.6, '开罐！']] }),
  E('C10', 'G20', 0, 4.2, {
    subs: [[0.3, 2.0, '铁拳', '全营压上去，拿下沙梁！'], [2.3, 4.1, '长城', '三颗钉子，全拔了！']],
    list: [2.0, 4.2, 3],
  }),

  // —————— 反转：死神偷袭，盾牌打脸 ——————
  E('D1', 'G21', 0, 3.4, {
    card: [[0.3, 3.2, '死神', '蓝方 · AH-64E 阿帕奇', 'blue', '藏在方山背后']],
    subs: [[0.6, 2.0, '死神', '红方纵队，没带防空。'], [2.1, 3.3, '死神', '随便打。']],
  }),
  E('D2', 'G22', 0, 2.4, { subs: [[0.05, 1.0, '死神', '发射。']] }),
  E('D3', 'G22B', 0, 3.0, { alert: [[1.0, 3.0, '后续纵队遭到偷袭']], subs: [[1.1, 2.9, '长城', '直升机！后续纵队挨打了！']] }),
  E('D4', 'G23', 0, 2.8, {
    card: [[0.2, 2.7, '盾牌', '红方 · PGL-625 弹炮合一防空车', 'red', '25 毫米六管炮 + 红外导弹']],
    subs: [[0.3, 1.5, '盾牌', '谁说我们没防空？'], [1.55, 2.6, '盾牌', '锁定！']],
  }),
  E('D5', 'G24', 0, 2.6, { subs: [[0.1, 0.9, '盾牌', '开火！']] }),
  E('D6', 'G25', 0, 3.0, { subs: [[0.45, 1.6, '死神', '热诱弹！甩掉了——'], [1.65, 2.35, '盾牌', '还有一发。']] }),
  E('D7', 'G26', 0, 4.6, { big: [[0.25, 2.0, '击落！']], subs: [[2.9, 4.4, '盾牌', '打的就是你。']] }),

  // —————— 蓝方增援：雷霆 ——————
  E('E1', 'G27', 0, 3.8, {
    alert: [[0.0, 1.9, '蓝方增援装甲营 · 正扑向油田']],
    subs: [[0.2, 1.8, '长城', '蓝方增援正往油田赶！'], [2.0, 3.6, '雷霆', '雷霆收到，交给我。']],
    card: [[1.8, 3.7, '雷霆', '红方 · 歼-16 战斗机', 'red', '4 枚 KD-88 · 防区外打击']],
  }),
  E('E2', 'G28', 0, 4.2, { subs: [[0.4, 1.5, '雷霆', '发现装甲纵队。'], [2.3, 3.9, '雷霆', '四个目标，全部锁定。']] }),
  E('E3', 'G29', 0, 2.8, { subs: [[0.25, 1.0, '雷霆', '发射！']], info: [[0.9, 2.7, '38 公里外发射 · 对面连飞机都看不见']] }),
  E('E4', 'G30', 0, 4.3, { big: [[2.65, 4.2, '4 / 4', '全部命中']], subs: [[3.1, 4.2, '雷霆', '增援，清除。']] }),

  // —————— 结局、片名 ——————
  E('F1', 'G31', 0, 6.0, {
    stamp: [[0.3, 2.6, '18:07', '油田']],
    subs: [[1.0, 2.7, '铁拳', '长城，油田拿下了。'], [3.0, 4.4, '长城', '干得漂亮，铁拳。']],
    big: [[4.4, 6.0, '任务完成', '日落前拿下油田', 'gold']],
  }),
  E('T1', 'G32', 0, 6.0, { keepTitles: true }),
  E('T2', 'G33', 0, 7.5, { keepTitles: true }),
  E('T3', 'G34', 0, 5.5, { keepTitles: true }),
];
let T0 = 0;
for (const e of EDIT) { e.t0 = T0; T0 += e.dur; }
export const EDIT_TOTAL = T0;

// 第 i 帧用原镜头的第几帧（原镜头的第 k 帧在 (k + 0.5) / FPS 秒）；黑场 null
export function plateIndex(e, i) {
  if (!e.src) return null;
  const k0 = Math.round(e.from * FPS);
  return k0 + (e.freeze != null ? Math.min(i, Math.round(e.freeze * FPS)) : i);
}
// 原镜头的音效事件搬到这一条：按截的那一段平移；开头之前就开始的持续声（风、发动机、旋翼……）从 0 秒接着响；定格以后不出声
const SUSTAIN = new Set(['desertWind', 'aaaFar', 'nvgWhine', 'radarHum', 'jetLow', 'jetCabin', 'jetCruise', 'fireRoar', 'fireField', 'droneHum',
  'tankColumn', 'tankEngines', 'tankIdle', 'rotor', 'heliSpin', 'vulcan', 'gatling25']);
export function clipEvents(events, e) {
  const off = Math.round(e.from * FPS) / FPS, end = e.freeze ?? e.dur, out = [];
  for (const ev of events || []) {
    const t = ev.t - off;
    if (t >= end) continue;
    if (t < 0) { if (SUSTAIN.has(ev.k) && (ev.d == null || ev.d + t > 0.2)) out.push({ ...ev, t: 0, d: ev.d != null ? ev.d + t : undefined }); continue; }
    out.push({ ...ev, t });
  }
  return out;
}
// 字幕层自带的音效：对白开头一声电台、字卡一声呼啸、大字一记重击、清单打勾一声叮、警报、打字机
export function storyEvents(e) {
  const ev = [];
  for (const [a, b, who] of e.subs || []) ev.push({ t: a, k: 'radioIn', side: WHO[who] === BLUE ? 'blue' : 'red' }, { t: b - 0.05, k: 'radioOut' });
  for (const [a] of e.card || []) ev.push({ t: a, k: 'cardIn' });
  for (const [a, , , , col] of e.big || []) ev.push({ t: a, k: col === 'gold' ? 'hitGold' : 'hitWord' });
  if (e.list) ev.push({ t: e.list[0], k: 'listIn' }, { t: e.list[0] + 0.45, k: 'ding' });
  for (const [a, b] of e.alert || []) ev.push({ t: a, k: 'alarm', d: Math.min(1.6, b - a) });
  for (const [a, , time, place] of e.stamp || []) ev.push({ t: a, k: 'type', n: (time + place).length });
  return ev.concat(e.sfx || []);
}

// —————————————————————————— 画字 ——————————————————————————
function rr(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
const win = (t, a, b, fin = 0.12, fout = 0.18) => smooth(a, a + fin, t) * (1 - smooth(b - fout, b, t));
function spacing(g, px) { if ('letterSpacing' in g) g.letterSpacing = `${px}px`; }

// 对白：下面黑边的正中，左边一块阵营色的名牌（说话人），右边白字台词
function drawSub(g, W, H, ah, who, text, a) {
  const bar = (H - ah) / 2, y = H - bar * 0.5;
  const S = H * 0.036, LS = H * 0.021;
  g.save();
  g.globalAlpha = a;
  g.textBaseline = 'middle'; g.textAlign = 'left';
  g.font = `700 ${S}px ${SANS}`; spacing(g, S * 0.04); const tw = g.measureText(text).width;
  g.font = `900 ${LS}px ${SANS}`; spacing(g, LS * 0.12); const nw = g.measureText(who).width;
  const px = LS * 0.55, bw = nw + px * 2, bh = LS * 1.75, gap = S * 0.5;
  const x0 = W / 2 - (bw + gap + tw) / 2;
  g.fillStyle = WHO[who] || RED; rr(g, x0, y - bh / 2, bw, bh, LS * 0.28); g.fill();
  g.fillStyle = '#fff'; g.fillText(who, x0 + px, y + LS * 0.04);
  g.font = `700 ${S}px ${SANS}`; spacing(g, S * 0.04);
  g.fillStyle = '#f5f2ea'; g.fillText(text, x0 + bw + gap, y);
  g.restore();
}
// 人物字卡：画面左边，阵营色竖条 + 大名字（衬线）+ 身份 + 一句话；从左往右擦出来
function drawCard(g, W, H, ah, [t0, t1, name, sub, side, line], t) {
  if (t < t0 || t > t1) return;
  const top = (H - ah) / 2, C = SIDE[side] || SIDE.red;
  const u = t - t0, wipe = easeOut(u / 0.28), a = 1 - smooth(t1 - 0.3, t1, t);
  const x = W * 0.06, yN = top + ah * 0.40, NS = H * 0.088, SS = H * 0.025, LS = H * 0.02;
  g.save();
  g.globalAlpha = a;
  // 后面一道往右渐隐的暗带（字在亮的天上也看得清）
  const bandY = yN - NS * 0.85, bandH = NS * 0.85 + SS * 1.6 + (line ? LS * 2.2 : 0) + NS * 0.35;
  const grd = g.createLinearGradient(0, 0, W * 0.48, 0);
  grd.addColorStop(0, 'rgba(0,0,0,0.6)'); grd.addColorStop(0.6, 'rgba(0,0,0,0.32)'); grd.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grd; g.fillRect(0, bandY, W * 0.48 * wipe, bandH);
  g.beginPath(); g.rect(0, bandY - 10, (x + W * 0.42) * wipe, bandH + 20); g.clip();
  g.fillStyle = C.bar; g.fillRect(x, yN - NS * 0.72, Math.max(4, H * 0.006), NS * 0.72 + SS * 1.55 + (line ? LS * 1.9 : 0));
  const tx = x + H * 0.022;
  g.textAlign = 'left'; g.textBaseline = 'alphabetic';
  g.font = `900 ${NS}px ${SERIF}`; spacing(g, NS * 0.08);
  g.shadowColor = 'rgba(0,0,0,0.6)'; g.shadowBlur = NS * 0.12;
  g.fillStyle = '#fbf7ee'; g.fillText(name, tx, yN);
  g.shadowBlur = 0;
  g.font = `700 ${SS}px ${SANS}`; spacing(g, SS * 0.16);
  g.fillStyle = C.sub; g.fillText(sub, tx, yN + SS * 1.45);
  if (line) { g.font = `400 ${LS}px ${SANS}`; spacing(g, LS * 0.14); g.fillStyle = 'rgba(240,236,228,0.9)'; g.fillText(line, tx, yN + SS * 1.45 + LS * 1.75); }
  g.restore();
}
// 爽点大字：正中一下砸出来（1.5 倍缩回 1 倍）、描深色边、发光；下面一行小字
function drawBig(g, W, H, ah, [t0, t1, text, sub, col], t) {
  if (t < t0 || t > t1) return;
  const top = (H - ah) / 2, u = t - t0;
  const k = 1 + 0.5 * Math.exp(-u * 16), a = smooth(0, 0.05, u) * (1 - smooth(t1 - 0.25, t1, t));
  const cx = W / 2, cy = top + ah * 0.3, S = H * (text.length > 4 ? 0.1 : 0.12);   // 画面上三分之一：不挡正中的主体
  const gold = col === 'gold';
  g.save();
  g.globalAlpha = a;
  g.translate(cx, cy); g.scale(k, k);
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.font = `900 ${S}px ${SERIF}`; spacing(g, S * 0.08);
  g.lineJoin = 'round'; g.lineWidth = S * 0.1; g.strokeStyle = 'rgba(16,6,0,0.82)';
  g.strokeText(text, S * 0.04, 0);
  const grd = g.createLinearGradient(0, -S * 0.5, 0, S * 0.5);
  if (gold) { grd.addColorStop(0, '#fff6d8'); grd.addColorStop(0.55, '#ffd36a'); grd.addColorStop(1, '#d99a2b'); }
  else { grd.addColorStop(0, '#ffffff'); grd.addColorStop(0.55, '#fff1d6'); grd.addColorStop(1, '#ffc27a'); }
  g.shadowColor = gold ? 'rgba(255,190,70,0.85)' : 'rgba(255,120,40,0.8)'; g.shadowBlur = S * 0.45;
  g.fillStyle = grd; g.fillText(text, S * 0.04, 0);
  g.shadowBlur = 0;
  if (sub) {
    const s2 = H * 0.026;
    g.font = `700 ${s2}px ${SANS}`; spacing(g, s2 * 0.5);
    g.fillStyle = 'rgba(0,0,0,0.5)'; const w = g.measureText(sub).width + s2 * 1.6; g.fillRect(-w / 2, S * 0.62, w, s2 * 1.6);
    g.fillStyle = gold ? '#ffe2a0' : '#ffd9b8'; g.fillText(sub, s2 * 0.25, S * 0.62 + s2 * 0.82);
  }
  g.restore();
}
// 时间戳：左上，大的等宽时间 + 地点，打字机一个字一个字出来，后面一个闪的光标
function drawStamp(g, W, H, ah, [t0, t1, time, place], t) {
  if (t < t0 || t > t1) return;
  const top = (H - ah) / 2, a = 1 - smooth(t1 - 0.3, t1, t);
  const n = Math.floor((t - t0) / 0.055), x = W * 0.06, y = top + ah * 0.13;
  const TS = H * 0.046, PS = H * 0.022;
  g.save();
  g.globalAlpha = a;
  g.textAlign = 'left'; g.textBaseline = 'alphabetic';
  g.shadowColor = 'rgba(0,0,0,0.7)'; g.shadowBlur = TS * 0.2;
  g.font = `900 ${TS}px ${SANS}`; spacing(g, TS * 0.06);
  g.fillStyle = '#f6f1e6';
  const s1 = time.slice(0, Math.min(n, time.length)); g.fillText(s1, x, y);
  let cx = x + g.measureText(s1).width, cy = y;
  if (place && n > time.length) {
    g.font = `700 ${PS}px ${SANS}`; spacing(g, PS * 0.22);
    g.fillStyle = '#e7c48a';
    const s2 = place.slice(0, n - time.length); g.fillText(s2, x, y + PS * 1.7);
    cx = x + g.measureText(s2).width; cy = y + PS * 1.7;
  }
  if (((t - t0) * 2.2) % 1 < 0.6) { g.fillStyle = '#f6f1e6'; g.fillRect(cx + 6, cy - (cy === y ? TS : PS) * 0.8, Math.max(3, H * 0.004), (cy === y ? TS : PS) * 0.85); }
  g.restore();
}
// 说明（科普）：画面左下，一个橙色小方块 + 一行字，淡黑底
function drawInfo(g, W, H, ah, [t0, t1, text], t) {
  const a = win(t, t0, t1, 0.25, 0.3); if (a <= 0) return;
  const top = (H - ah) / 2, S = H * 0.021, x = W * 0.06, y = top + ah * 0.86;
  g.save(); g.globalAlpha = a;
  g.font = `700 ${S}px ${SANS}`; spacing(g, S * 0.12); g.textBaseline = 'middle'; g.textAlign = 'left';
  const w = g.measureText(text).width;
  g.fillStyle = 'rgba(0,0,0,0.5)'; g.fillRect(x - S * 0.5, y - S * 0.95, w + S * 2.4, S * 1.9);
  g.fillStyle = '#ff9b3d'; g.fillRect(x, y - S * 0.42, S * 0.84, S * 0.84);
  g.fillStyle = '#f2eee6'; g.fillText(text, x + S * 1.4, y + S * 0.03);
  g.restore();
}
// 警报横幅：画面上面一道红带，「警报」+ 一行字，闪
function drawAlert(g, W, H, ah, [t0, t1, text], t) {
  const a = win(t, t0, t1, 0.1, 0.25); if (a <= 0) return;
  const top = (H - ah) / 2, S = H * 0.028, y = top + ah * 0.1;
  const blink = ((t - t0) * 2.5) % 1 < 0.72 ? 1 : 0.55;
  g.save(); g.globalAlpha = a;
  g.font = `900 ${S}px ${SANS}`; spacing(g, S * 0.18); g.textBaseline = 'middle'; g.textAlign = 'left';
  const tag = '警报', tw = g.measureText(tag).width;
  g.font = `700 ${S}px ${SANS}`; const w = g.measureText(text).width;
  const pw = tw + w + S * 3.2, x0 = W / 2 - pw / 2, h = S * 2;
  const grd = g.createLinearGradient(x0 - S * 4, 0, x0 + pw + S * 4, 0);
  grd.addColorStop(0, 'rgba(150,12,8,0)'); grd.addColorStop(0.12, 'rgba(170,16,10,0.82)'); grd.addColorStop(0.88, 'rgba(170,16,10,0.82)'); grd.addColorStop(1, 'rgba(150,12,8,0)');
  g.fillStyle = grd; g.fillRect(x0 - S * 4, y - h / 2, pw + S * 8, h);
  g.globalAlpha = a * blink;
  g.fillStyle = '#fff'; rr(g, x0, y - S * 0.75, tw + S * 0.9, S * 1.5, S * 0.2); g.fill();
  g.font = `900 ${S}px ${SANS}`; g.fillStyle = '#b3120a'; g.fillText(tag, x0 + S * 0.45, y + S * 0.03);
  g.font = `700 ${S}px ${SANS}`; g.fillStyle = '#fff'; g.fillText(text, x0 + tw + S * 1.8, y + S * 0.03);
  g.restore();
}
// 任务清单：画面右上，标题「目标 · 日落前拿下油田」，三颗钉子，打完的打勾（新打的那个勾晚一点「啪」地弹出来、整行闪一下）
function check(g, x, y, s, k) {   // 一个勾（k：画出来多少，0～1）
  g.beginPath();
  const p = [[x - s * 0.5, y], [x - s * 0.12, y + s * 0.4], [x + s * 0.55, y - s * 0.45]];
  g.moveTo(...p[0]);
  if (k < 0.4) g.lineTo(lerp(p[0][0], p[1][0], k / 0.4), lerp(p[0][1], p[1][1], k / 0.4));
  else { g.lineTo(...p[1]); const v = (k - 0.4) / 0.6; g.lineTo(lerp(p[1][0], p[2][0], v), lerp(p[1][1], p[2][1], v)); }
  g.stroke();
}
function drawList(g, W, H, ah, [t0, t1, done], t) {
  const a = win(t, t0, t1, 0.25, 0.3); if (a <= 0) return;
  const top = (H - ah) / 2, S = H * 0.021, pw = W * 0.215, x0 = W * 0.94 - pw, y0 = top + ah * 0.07;
  const rowH = S * 2.05, ph = S * 2.6 + rowH * GOALS.length + S * 0.6;
  const slide = (1 - easeOut((t - t0) / 0.35)) * W * 0.05;
  g.save(); g.globalAlpha = a; g.translate(slide, 0);
  g.fillStyle = 'rgba(8,10,12,0.62)'; rr(g, x0, y0, pw, ph, S * 0.4); g.fill();
  g.fillStyle = '#e6b24e'; g.fillRect(x0, y0, pw, S * 0.18);
  g.textBaseline = 'middle'; g.textAlign = 'left';
  g.font = `900 ${S}px ${SANS}`; spacing(g, S * 0.14); g.fillStyle = '#f0c35e';
  g.fillText('目标 · 日落前拿下油田', x0 + S * 0.9, y0 + S * 1.45);
  const tNew = t0 + 0.45;
  GOALS.forEach((name, i) => {
    const y = y0 + S * 2.6 + rowH * (i + 0.5);
    const isNew = i === done - 1, ok = i < done - 1 || (isNew && t > tNew);
    if (isNew && t > tNew) { const f = Math.exp(-(t - tNew) * 3.5); g.fillStyle = `rgba(255,200,90,${0.35 * f})`; g.fillRect(x0 + S * 0.4, y - rowH * 0.45, pw - S * 0.8, rowH * 0.9); }
    g.font = `700 ${S}px ${SANS}`; spacing(g, S * 0.1);
    g.fillStyle = ok ? 'rgba(220,214,200,0.62)' : '#f4f0e8';
    g.fillText(`${i + 1}  ${name}`, x0 + S * 0.9, y);
    if (ok) { const w = g.measureText(`${i + 1}  ${name}`).width; g.fillStyle = 'rgba(220,214,200,0.55)'; g.fillRect(x0 + S * 0.9, y, w, Math.max(1.5, S * 0.08)); }
    const bx = x0 + pw - S * 1.6, bs = S * 1.05;
    g.strokeStyle = 'rgba(240,236,228,0.8)'; g.lineWidth = Math.max(1.5, S * 0.09); g.strokeRect(bx - bs / 2, y - bs / 2, bs, bs);
    if (ok) {
      const k = isNew ? clamp((t - tNew) / 0.16, 0, 1) : 1, pop = isNew ? 1 + 0.6 * Math.exp(-(t - tNew) * 10) : 1;
      g.save(); g.translate(bx, y); g.scale(pop, pop);
      g.strokeStyle = '#5ee07a'; g.lineWidth = Math.max(2.5, S * 0.2); g.lineCap = 'round'; g.lineJoin = 'round';
      g.shadowColor = 'rgba(80,255,120,0.7)'; g.shadowBlur = S * 0.5;
      check(g, 0, 0, bs * 0.95, k);
      g.restore();
    }
  });
  g.restore();
}
// 黑场大字（「6 小时前」）：开头几帧红青错位抖一下，下面一道细线展开
function drawBlack(g, W, H, text, t, dur) {
  const a = smooth(0.05, 0.25, t) * (1 - smooth(dur - 0.3, dur, t));
  const S = H * 0.072, cx = W / 2, cy = H * 0.48;
  g.save();
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.font = `900 ${S}px ${SERIF}`; spacing(g, S * 0.3);
  const gl = t < 0.45 ? (1 - t / 0.45) : 0, j = Math.sin(t * 97) * S * 0.08 * gl;
  if (gl > 0) {
    g.globalCompositeOperation = 'lighter';
    g.globalAlpha = a * 0.8; g.fillStyle = '#ff2a2a'; g.fillText(text, cx + S * 0.15 + j, cy);
    g.fillStyle = '#20e0ff'; g.fillText(text, cx - S * 0.15 - j, cy);
    g.globalCompositeOperation = 'source-over';
  }
  g.globalAlpha = a; g.fillStyle = '#f4efe4'; g.fillText(text, cx + S * 0.15, cy);
  const w = W * 0.22 * easeOut((t - 0.2) / 0.8);
  if (w > 0) { g.fillStyle = 'rgba(244,239,228,0.7)'; g.fillRect(cx - w / 2, cy + S * 0.85, w, Math.max(1.5, H * 0.002)); }
  g.restore();
}

// 一帧的字幕层（画在画面、平显上面）
export function drawStory(g, W, H, ah, e, t) {
  if (e.black) drawBlack(g, W, H, e.black, t, e.dur);
  for (const s of e.stamp || []) drawStamp(g, W, H, ah, s, t);
  for (const s of e.alert || []) drawAlert(g, W, H, ah, s, t);
  for (const s of e.info || []) drawInfo(g, W, H, ah, s, t);
  for (const s of e.card || []) drawCard(g, W, H, ah, s, t);
  if (e.list) drawList(g, W, H, ah, e.list, t);
  for (const s of e.big || []) drawBig(g, W, H, ah, s, t);
  for (const [a, b, who, text] of e.subs || []) { const k = win(t, a, b, 0.06, 0.1); if (k > 0) drawSub(g, W, H, ah, who, text, k); }
}
// 画面上的闪白（大字砸下来那一下）：合成时加到 look.flash 上
export function storyFlash(e, t) {
  let f = 0;
  for (const [a] of e.big || []) if (t >= a) f += 0.22 * Math.exp(-(t - a) * 12);
  return f;
}

// —————————————————————————— 电子沙盘（MAP，原镜头 GMAP：整张图从南边高空斜着往北看）——————————————————————————
//   P(x, z) → 画布像素坐标（镜头后面返回 null）；地图上的点都是游戏地图 MapDesert.lua 的坐标
const bermZ = x => 7600 + 120 * Math.sin(x / 3100 + 1.1) + 40 * Math.sin(x / 900 + 0.3);
const ridgeZ = x => -9300 + 500 * Math.sin(x / 4100 + 0.6) + 160 * Math.sin(x / 1300 + 2.0);
export const MAPPTS = {
  SAM: [5600, -6800], BATT: [2600, -12300], M1: [-520, 3330], OIL: [5200, 2600], BREACH: [-1200, 7700], TOWN: [-3800, -600],
  AIR: [3400, -5200], MESA: [-8400, -4300], RED: [-1200, 11200], COL6: [9800, 3150],
};
function poly(g, P, pts, k = 1) {   // 世界坐标折线 → 画出来前 k（0～1）那一段，返回终点和终点方向
  const s = pts.map(([x, z]) => P(x, z)).filter(Boolean);
  if (s.length < 2) return null;
  let L = 0; const seg = [];
  for (let i = 1; i < s.length; i++) { const d = Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]); seg.push(d); L += d; }
  let left = L * clamp(k, 0, 1), end = s[0], dir = [1, 0];
  g.beginPath(); g.moveTo(...s[0]);
  for (let i = 1; i < s.length && left > 0; i++) {
    const u = Math.min(1, left / seg[i - 1]);
    end = [lerp(s[i - 1][0], s[i][0], u), lerp(s[i - 1][1], s[i][1], u)];
    dir = [s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]];
    g.lineTo(...end); left -= seg[i - 1];
  }
  g.stroke();
  const n = Math.hypot(dir[0], dir[1]) || 1;
  return { end, dir: [dir[0] / n, dir[1] / n] };
}
function arrowHead(g, r, s) {
  if (!r) return;
  const [x, y] = r.end, [dx, dy] = r.dir;
  g.beginPath(); g.moveTo(x + dx * s, y + dy * s); g.lineTo(x - dy * s * 0.75 - dx * s * 0.4, y + dx * s * 0.75 - dy * s * 0.4); g.lineTo(x + dy * s * 0.75 - dx * s * 0.4, y - dx * s * 0.75 - dy * s * 0.4); g.closePath(); g.fill();
}
const curve = (a, b, c, n = 24) => Array.from({ length: n + 1 }, (_, i) => { const u = i / n; return [(1 - u) ** 2 * a[0] + 2 * u * (1 - u) * b[0] + u * u * c[0], (1 - u) ** 2 * a[1] + 2 * u * (1 - u) * b[1] + u * u * c[1]]; });
function label(g, x, y, text, S, col, o = {}) {
  g.font = `${o.w || 700} ${S}px ${SANS}`; spacing(g, S * (o.sp ?? 0.12));
  g.textAlign = o.align || 'left'; g.textBaseline = 'middle';
  if (o.bg) { const w = g.measureText(text).width; const bx = o.align === 'center' ? x - w / 2 : (o.align === 'right' ? x - w : x); g.fillStyle = o.bg; g.fillRect(bx - S * 0.4, y - S * 0.8, w + S * 0.8, S * 1.6); }
  g.fillStyle = col; g.fillText(text, x, y);
}
function marker(g, p, n, title, sub, t, tIn, S, side) {   // 一颗钉子：脉冲圈、蓝方方块、编号、名字、为什么要拔
  if (!p || t < tIn) return;
  const u = t - tIn, a = smooth(0, 0.2, u), [x, y] = p;
  g.save(); g.globalAlpha = a;
  for (let k = 0; k < 2; k++) { const v = ((u * 0.9 + k * 0.5) % 1); g.strokeStyle = `rgba(90,170,255,${0.8 * (1 - v)})`; g.lineWidth = 2; g.beginPath(); g.arc(x, y, S * (0.6 + v * 2.8), 0, Math.PI * 2); g.stroke(); }
  const pop = 1 + 0.8 * Math.exp(-u * 10), b = S * 0.55 * pop;
  g.fillStyle = 'rgba(30,90,190,0.9)'; g.strokeStyle = '#bfe0ff'; g.lineWidth = 2;
  g.fillRect(x - b, y - b * 0.7, b * 2, b * 1.4); g.strokeRect(x - b, y - b * 0.7, b * 2, b * 1.4);
  // 编号：红圈白字（红方要拔的钉子），顶在方块上面
  const cx = x, cy = y - b * 0.7 - S * 1.0;
  g.fillStyle = '#d8342a'; g.beginPath(); g.arc(cx, cy, S * 0.72, 0, Math.PI * 2); g.fill();
  g.font = `900 ${S}px ${SANS}`; spacing(g, 0); g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = '#fff'; g.fillText(String(n), cx, cy + S * 0.04);
  const lx = x + (side < 0 ? -b - S * 1.0 : b + S * 1.0), al = side < 0 ? 'right' : 'left';
  label(g, lx, y - S * 0.35, title, S * 1.05, '#ffffff', { w: 900, align: al, bg: 'rgba(0,0,0,0.55)' });
  label(g, lx, y + S * 1.25, sub, S * 0.8, '#ffd2a0', { w: 700, align: al, bg: 'rgba(0,0,0,0.45)' });
  g.restore();
}
export function drawMap(g, W, H, ah, t, P) {
  const top = (H - ah) / 2, S = H * 0.022;
  g.save();
  g.beginPath(); g.rect(0, top, W, ah); g.clip();
  // 扫描：开头一道亮线从上往下扫，线下面还是暗的
  const scan = top + ah * easeOut(t / 0.9);
  if (t < 1.0) {
    g.fillStyle = 'rgba(2,6,10,0.92)'; g.fillRect(0, scan, W, top + ah - scan);
    const grd = g.createLinearGradient(0, scan - 40, 0, scan + 4); grd.addColorStop(0, 'rgba(120,210,255,0)'); grd.addColorStop(1, 'rgba(150,225,255,0.55)');
    g.fillStyle = grd; g.fillRect(0, scan - 40, W, 44);
  }
  const A = smooth(0.2, 0.8, t);
  // 坐标网（每 2000 格一条）
  g.globalAlpha = A; g.strokeStyle = 'rgba(140,210,255,0.22)'; g.lineWidth = 1;
  for (let x = -14000; x <= 14000; x += 2000) poly(g, P, [[x, -16000], [x, 12000]]);
  for (let z = -16000; z <= 12000; z += 2000) poly(g, P, [[-14000, z], [14000, z]]);
  // 两军分界（边境沙墙）、岩岭
  const xs = Array.from({ length: 57 }, (_, i) => -14000 + i * 500);
  g.setLineDash([10, 8]); g.lineWidth = 2.5; g.strokeStyle = 'rgba(255,215,120,0.85)';
  poly(g, P, xs.map(x => [x, bermZ(x)]));
  g.setLineDash([3, 6]); g.lineWidth = 2; g.strokeStyle = 'rgba(200,200,200,0.5)';
  poly(g, P, xs.map(x => [x, ridgeZ(x)]));
  g.setLineDash([]);
  const pb = P(9000, bermZ(9000) - 300); if (pb) label(g, pb[0], pb[1], '边境沙墙', S * 0.85, 'rgba(255,220,140,0.95)', { w: 700, bg: 'rgba(0,0,0,0.4)' });
  const pr = P(-9000, ridgeZ(-9000) - 500); if (pr) label(g, pr[0], pr[1], '岩岭', S * 0.85, 'rgba(225,225,225,0.85)', { w: 700, bg: 'rgba(0,0,0,0.4)' });
  // 阵营
  const pR = P(6500, 9400), pB = P(-6500, -11600);
  if (pR) label(g, pR[0], pR[1], '红方', S * 1.6, '#ff6a52', { w: 900, align: 'center', sp: 0.5 });
  if (pB) label(g, pB[0], pB[1], '蓝方', S * 1.6, '#6fb6ff', { w: 900, align: 'center', sp: 0.5 });
  // 地名
  for (const [k, n, l] of [['TOWN', '镇子', 0], ['AIR', '蓝方空军基地', 1], ['MESA', '方山', 0]]) { const p = P(...MAPPTS[k]); if (p) { g.fillStyle = 'rgba(230,230,230,0.8)'; g.beginPath(); g.arc(p[0], p[1], 3, 0, Math.PI * 2); g.fill(); label(g, p[0] + (l ? -8 : 8), p[1], n, S * 0.8, 'rgba(235,235,235,0.85)', { w: 700, align: l ? 'right' : 'left', bg: 'rgba(0,0,0,0.35)' }); } }
  // 目标：油田（金色、一直在跳）
  const po = P(...MAPPTS.OIL);
  if (po && t > 0.6) {
    const u = t - 0.6, a2 = smooth(0, 0.3, u);
    g.globalAlpha = a2;
    for (let k = 0; k < 2; k++) { const v = (u * 0.7 + k * 0.5) % 1; g.strokeStyle = `rgba(255,200,80,${0.9 * (1 - v)})`; g.lineWidth = 2.5; g.beginPath(); g.arc(po[0], po[1], S * (0.8 + v * 3.2), 0, Math.PI * 2); g.stroke(); }
    g.fillStyle = '#ffc94a'; g.beginPath();
    for (let i = 0; i < 10; i++) { const r = i % 2 ? S * 0.45 : S * 1.05, an = -Math.PI / 2 + i * Math.PI / 5; g.lineTo(po[0] + Math.cos(an) * r, po[1] + Math.sin(an) * r); }
    g.closePath(); g.fill();
    label(g, po[0] + S * 1.5, po[1] - S * 0.3, '目标：油田', S * 1.15, '#ffd772', { w: 900, bg: 'rgba(0,0,0,0.55)' });
  }
  g.globalAlpha = 1;
  // 三颗钉子 + 派谁去
  g.lineCap = 'round'; g.lineJoin = 'round';
  if (t > 3.0) {   // ① 利剑：从西南天上过来（虚线）
    const k = easeOut((t - 3.0) / 1.2);
    g.setLineDash([12, 9]); g.strokeStyle = 'rgba(255,110,80,0.95)'; g.lineWidth = 3; g.fillStyle = 'rgba(255,110,80,0.95)';
    const r = poly(g, P, curve([-12000, 9000], [-2000, -1500], [4800, -6200]), k); g.setLineDash([]); arrowHead(g, r, S * 0.8);
    const p0 = P(-9500, 6500); if (p0) label(g, p0[0], p0[1], '利剑 · 歼-35', S * 0.85, '#ffb39e', { w: 900, bg: 'rgba(0,0,0,0.45)' });
  }
  marker(g, P(...MAPPTS.SAM), 1, '爱国者防空阵地', '有它在，飞机进不来', t, 3.0, S, 1);
  if (t > 4.6) {   // ② 天眼：从南边高空过来
    const k = easeOut((t - 4.6) / 1.2);
    g.setLineDash([12, 9]); g.strokeStyle = 'rgba(255,110,80,0.95)'; g.lineWidth = 3; g.fillStyle = 'rgba(255,110,80,0.95)';
    const r = poly(g, P, curve([9000, 9000], [9000, -4000], [3300, -11600]), k); g.setLineDash([]); arrowHead(g, r, S * 0.8);
    const p0 = P(10200, 5200); if (p0) label(g, p0[0], p0[1], '天眼 · 无人机', S * 0.85, '#ffb39e', { w: 900, align: 'right', bg: 'rgba(0,0,0,0.45)' });
  }
  marker(g, P(...MAPPTS.BATT), 2, 'M109 炮兵阵地', '有它在，坦克冲不过去', t, 4.6, S, -1);
  marker(g, P(...MAPPTS.M1), 3, 'M1A2 坦克连', '守着沙梁，挡在路上', t, 6.2, S, -1);
  if (t > 6.4) {   // ③ 铁拳：粗红箭头，从沙墙开口压过沙梁，拐向油田
    const k = easeOut((t - 6.4) / 1.8);
    g.strokeStyle = 'rgba(0,0,0,0.5)'; g.lineWidth = 15;
    const path = [...curve([-1200, 10800], [-1100, 7600], [-700, 4200], 12), ...curve([-700, 4200], [500, 2500], [4300, 2550], 16).slice(1)];
    poly(g, P, path, k);
    g.strokeStyle = '#ff3b2a'; g.lineWidth = 9; g.fillStyle = '#ff3b2a';
    const r = poly(g, P, path, k); arrowHead(g, r, S * 1.3);
    const p0 = P(-1200, 9300); if (p0) label(g, p0[0] + S * 1.2, p0[1], '铁拳 · 99A 坦克营', S * 1.05, '#ffffff', { w: 900, align: 'left', bg: 'rgba(170,30,20,0.85)' });
  }
  // 暗角 + 细扫描线（像屏幕）
  g.globalAlpha = 1;
  const vg = g.createRadialGradient(W / 2, top + ah / 2, ah * 0.35, W / 2, top + ah / 2, W * 0.62);
  vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,4,10,0.55)');
  g.fillStyle = vg; g.fillRect(0, top, W, ah);
  g.fillStyle = 'rgba(120,200,255,0.035)';
  for (let y = top; y < top + ah; y += 4) g.fillRect(0, y, W, 1);
  // 角上的字
  label(g, W * 0.035, top + ah * 0.07, '红方指挥所 · 作战简报', S * 0.95, 'rgba(200,232,255,0.9)', { w: 900, sp: 0.25 });
  label(g, W * 0.965, top + ah * 0.07, '沙海战区 · 北 ↑', S * 0.8, 'rgba(200,232,255,0.7)', { w: 700, align: 'right', sp: 0.2 });
  g.restore();
}
