// 时代广场宣传片（promo.js）的配乐、音效：乐器、音效跟微电影一样（audio.js 抄过来的），编排按宣传片的三幕重写
//   D 小调：深夜低音铺底 + 心跳 → 舰队弦乐顿弓渐强 → H 时一记重击 → 战斗 120 拍（海 / 陆 / 空三张字卡各一记铜管，慢镜头那几下压成低音 + 呼啸）
//   → 天亮一下静下来（耳鸣）、大提琴旋律，再起脉冲推到片名 → 片名重击 → 卖点脉冲 → 结尾长尾
//   宣传片多半在时代广场的大屏上无声放：画面自己讲得清楚，声音是给有声的场合（网上、发布会）
import { rng } from './lib.js';

const SR = 48000;
const mtof = m => 440 * Math.pow(2, (m - 69) / 12);

export async function renderPromoScore(SHOTS) {
  const total = SHOTS.reduce((a, s) => a + s.dur, 0) + 1.5;
  const ctx = new OfflineAudioContext(2, Math.ceil(total * SR), SR);
  const R = rng(4242);
  // —— 总线：音乐、音效（各自混响）→ 压缩 → 输出 ——
  const master = ctx.createGain(); master.gain.value = 0.9;
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -14; comp.knee.value = 8; comp.ratio.value = 4; comp.attack.value = 0.004; comp.release.value = 0.25;
  master.connect(comp); comp.connect(ctx.destination);
  const noise = (() => { const b = ctx.createBuffer(2, SR * 4, SR); for (let c = 0; c < 2; c++) { const d = b.getChannelData(c); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; } return b; })();
  const brown = (() => { const b = ctx.createBuffer(2, SR * 4, SR); for (let c = 0; c < 2; c++) { const d = b.getChannelData(c); let l = 0; for (let i = 0; i < d.length; i++) { l = (l + 0.02 * (Math.random() * 2 - 1)) / 1.02; d[i] = l * 3.5; } } return b; })();
  function ir(dur, decay, bright) {
    const n = Math.floor(SR * dur), b = ctx.createBuffer(2, n, SR);
    for (let c = 0; c < 2; c++) { const d = b.getChannelData(c); let lp = 0; for (let i = 0; i < n; i++) { const t = i / SR; lp += (Math.random() * 2 - 1 - lp) * (bright * Math.exp(-t * 1.5) + 0.03); d[i] = lp * Math.exp(-t * decay) * Math.min(1, t / 0.01); } }
    return b;
  }
  const bus = (wet, irb) => {
    const g = ctx.createGain(), dry = ctx.createGain(), cv = ctx.createConvolver(), w = ctx.createGain();
    cv.buffer = irb; w.gain.value = wet; dry.gain.value = 1;
    g.connect(dry); g.connect(cv); cv.connect(w); dry.connect(master); w.connect(master);
    return g;
  };
  const MUS = bus(0.42, ir(4.5, 1.1, 0.35)), SFX = bus(0.22, ir(2.6, 2.0, 0.6));
  MUS.gain.value = 0.55; SFX.gain.value = 0.8;
  // —— 基本件 ——
  const out = (dest, pan = 0) => { const p = ctx.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, pan)); p.connect(dest); return p; };
  function env(g, t, a, peak, hold, rel) { g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(peak, t + a); g.gain.setValueAtTime(peak, t + a + hold); g.gain.exponentialRampToValueAtTime(0.0001, t + a + hold + rel); }
  function osc(type, f, t0, t1) { const o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f, t0); o.start(t0); o.stop(t1); return o; }
  function nz(t0, t1, buf = noise, rate = 1) { const s = ctx.createBufferSource(); s.buffer = buf; s.loop = true; s.playbackRate.value = rate; s.start(t0, Math.random() * 3); s.stop(t1); return s; }
  function filt(type, f, q = 0.7) { const b = ctx.createBiquadFilter(); b.type = type; b.frequency.value = f; b.Q.value = q; return b; }
  const shaper = (() => { const w = ctx.createWaveShaper(); const n = 2048, c = new Float32Array(n); for (let i = 0; i < n; i++) { const x = i / n * 2 - 1; c[i] = Math.tanh(x * 2.5); } w.curve = c; return w; });

  // —— 乐器 ——
  // 持续低音（一组失谐锯齿 + 次低音正弦，慢慢开合的低通）
  function drone(m, t0, t1, g0 = 0.12, cut = 500, dest = MUS) {
    const g = ctx.createGain(), lp = filt('lowpass', cut, 0.9);
    g.connect(out(dest)); lp.connect(g);
    g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(g0, t0 + Math.min(3, (t1 - t0) * 0.3)); g.gain.setValueAtTime(g0, t1 - Math.min(2, (t1 - t0) * 0.25)); g.gain.linearRampToValueAtTime(0, t1);
    for (const d of [-7, 0, 6]) { const o = osc('sawtooth', mtof(m), t0, t1); o.detune.value = d; o.connect(lp); }
    const s = osc('sine', mtof(m - 12), t0, t1); const sg = ctx.createGain(); sg.gain.value = 1.4; s.connect(sg); sg.connect(g);
    const lfo = osc('sine', 0.07, t0, t1), lg = ctx.createGain(); lg.gain.value = cut * 0.35; lfo.connect(lg); lg.connect(lp.frequency);
  }
  // 弦乐铺底（和弦，慢起慢收）
  function pad(notes, t0, t1, g0 = 0.05, cut = 1600, pan = 0) {
    const g = ctx.createGain(), lp = filt('lowpass', cut, 0.5);
    g.connect(out(MUS, pan)); lp.connect(g);
    g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(g0, t0 + Math.min(2.5, (t1 - t0) * 0.4)); g.gain.setValueAtTime(g0, Math.max(t0 + 0.1, t1 - 1.5)); g.gain.linearRampToValueAtTime(0, t1);
    for (const m of notes) for (const d of [-9, 3, 11]) { const o = osc('sawtooth', mtof(m), t0, t1); o.detune.value = d + (R() - 0.5) * 4; const vib = osc('sine', 5 + R(), t0, t1), vg = ctx.createGain(); vg.gain.value = 3; vib.connect(vg); vg.connect(o.detune); o.connect(lp); }
  }
  // 弦乐顿弓（短音、滤波包络）
  function stacc(m, t, dur = 0.16, g0 = 0.07, pan = 0) {
    const g = ctx.createGain(), lp = filt('lowpass', 900, 2);
    g.connect(out(MUS, pan)); lp.connect(g);
    env(g, t, 0.006, g0, dur * 0.4, dur);
    lp.frequency.setValueAtTime(2600, t); lp.frequency.exponentialRampToValueAtTime(500, t + dur);
    for (const d of [-6, 6]) { const o = osc('sawtooth', mtof(m), t, t + dur * 2); o.detune.value = d; o.connect(lp); }
  }
  // 铜管重击（低音铜管齐奏 + 失真，「布——昂」）
  function braam(notes, t, dur = 3, g0 = 0.16) {
    const g = ctx.createGain(), lp = filt('lowpass', 300, 1.2), sh = shaper();
    g.connect(out(MUS)); sh.connect(g); lp.connect(sh);
    env(g, t, 0.03, g0, dur * 0.25, dur);
    lp.frequency.setValueAtTime(220, t); lp.frequency.linearRampToValueAtTime(1600, t + 0.25); lp.frequency.exponentialRampToValueAtTime(260, t + dur);
    for (const m of notes) for (const d of [-12, 0, 9]) { const o = osc('sawtooth', mtof(m), t, t + dur * 1.3); o.detune.value = d; o.connect(lp); }
    const s = osc('sine', mtof(notes[0] - 12), t, t + dur * 1.3), sg = ctx.createGain(); sg.gain.value = 1.2; s.connect(sg); sg.connect(g);
  }
  // 太鼓：低频正弦往下滑 + 一点噪声
  function taiko(t, g0 = 0.45, f = 90, pan = 0) {
    const g = ctx.createGain(); g.connect(out(MUS, pan));
    env(g, t, 0.002, g0, 0.02, 0.55);
    const o = osc('sine', f * 1.6, t, t + 0.8); o.frequency.exponentialRampToValueAtTime(f * 0.45, t + 0.35); o.connect(g);
    const n = nz(t, t + 0.25), ng = ctx.createGain(), lp = filt('lowpass', 900); n.connect(lp); lp.connect(ng); ng.connect(g); env(ng, t, 0.001, 0.5, 0.01, 0.12);
  }
  function snare(t, g0 = 0.12, pan = 0) {
    const g = ctx.createGain(); g.connect(out(MUS, pan)); env(g, t, 0.001, g0, 0.005, 0.16);
    const n = nz(t, t + 0.3), bp = filt('bandpass', 2400, 0.8); n.connect(bp); bp.connect(g);
    const o = osc('triangle', 210, t, t + 0.12); const og = ctx.createGain(); og.gain.value = 0.6; o.connect(og); og.connect(g);
  }
  function cymbal(t, g0 = 0.08, dur = 3.5) {
    const g = ctx.createGain(); g.connect(out(MUS)); env(g, t, 0.003, g0, 0.05, dur);
    const n = nz(t, t + dur + 0.5), hp = filt('highpass', 5200, 0.5); n.connect(hp); hp.connect(g);
  }
  // 往上冲（噪声带通往上扫 + 升调）
  function riser(t0, t1, g0 = 0.1) {
    const g = ctx.createGain(); g.connect(out(MUS));
    g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(g0, t1 - 0.02); g.gain.linearRampToValueAtTime(0, t1);
    const n = nz(t0, t1), bp = filt('bandpass', 400, 3); bp.frequency.setValueAtTime(300, t0); bp.frequency.exponentialRampToValueAtTime(7000, t1); n.connect(bp); bp.connect(g);
    const o = osc('sawtooth', 120, t0, t1); o.frequency.exponentialRampToValueAtTime(900, t1); const og = ctx.createGain(); og.gain.value = 0.25; const lp = filt('lowpass', 1800); o.connect(lp); lp.connect(og); og.connect(g);
  }
  // 心跳
  function heart(t, g0 = 0.3) {
    for (const [dt, k] of [[0, 1], [0.22, 0.7]]) { const g = ctx.createGain(); g.connect(out(MUS)); env(g, t + dt, 0.004, g0 * k, 0.02, 0.18); const o = osc('sine', 62, t + dt, t + dt + 0.3); o.frequency.exponentialRampToValueAtTime(38, t + dt + 0.2); o.connect(g); }
  }
  // 独奏旋律（像大提琴：锯齿 + 揉弦 + 低通），notes：[[拍, 音高, 拍数]]
  function cello(t0, beat, notes, g0 = 0.09) {
    for (const [b, m, len] of notes) {
      const t = t0 + b * beat, d = len * beat;
      const g = ctx.createGain(), lp = filt('lowpass', 1400, 0.8); g.connect(out(MUS, -0.1)); lp.connect(g);
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(g0, t + 0.25); g.gain.setValueAtTime(g0 * 0.9, t + d * 0.8); g.gain.linearRampToValueAtTime(0, t + d + 0.35);
      for (const dt of [-5, 5]) { const o = osc('sawtooth', mtof(m), t, t + d + 0.5); o.detune.value = dt; const v = osc('sine', 5.2, t, t + d + 0.5), vg = ctx.createGain(); vg.gain.setValueAtTime(0, t); vg.gain.linearRampToValueAtTime(9, t + 0.6); v.connect(vg); vg.connect(o.detune); o.connect(lp); }
    }
  }
  // 脉冲（卖点那段：低音合成器的八分音符）
  function pulse(m, t, g0 = 0.08) { const g = ctx.createGain(), lp = filt('lowpass', 700, 4); g.connect(out(MUS)); lp.connect(g); env(g, t, 0.004, g0, 0.04, 0.2); lp.frequency.setValueAtTime(1800, t); lp.frequency.exponentialRampToValueAtTime(300, t + 0.2); const o = osc('sawtooth', mtof(m), t, t + 0.35); o.connect(lp); }

  // —— 音效 ——
  function boom(t, k = 1, pan = 0, dist = 0) {   // 爆炸：低通噪声 + 往下滑的重击 + 碎裂的尾巴
    const g = ctx.createGain(); g.connect(out(SFX, pan)); env(g, t, 0.003, 0.55 * k, 0.05, 1.6 + k);
    const n = nz(t, t + 3 + k, brown), lp = filt('lowpass', 1800 - dist * 900); lp.frequency.setValueAtTime(2400 - dist * 1200, t); lp.frequency.exponentialRampToValueAtTime(140, t + 1.4); n.connect(lp); lp.connect(g);
    const o = osc('sine', 120, t, t + 1.2); o.frequency.exponentialRampToValueAtTime(32, t + 0.8); const og = ctx.createGain(); og.gain.value = 1.3; o.connect(og); og.connect(g);
    const c = nz(t + 0.05, t + 1.4), hp = filt('highpass', 2500), cg = ctx.createGain(); c.connect(hp); hp.connect(cg); cg.connect(out(SFX, pan)); env(cg, t + 0.05, 0.01, 0.06 * k * (1 - dist * 0.7), 0.1, 0.9);
  }
  function shot(t, k = 0.3, pan = 0, tone = 1) {   // 枪声
    const g = ctx.createGain(); g.connect(out(SFX, pan)); env(g, t, 0.0008, k, 0.004, 0.09);
    const n = nz(t, t + 0.25), bp = filt('bandpass', 1400 * tone, 0.6); n.connect(bp); bp.connect(g);
    const o = osc('square', 160 * tone, t, t + 0.05); const og = ctx.createGain(); og.gain.value = 0.25; o.connect(og); og.connect(g);
  }
  function mg(t0, t1, rate, k = 0.22, pan = 0, tone = 1) { for (let t = t0; t < t1; t += 1 / rate * (0.85 + R() * 0.3)) shot(t, k * (0.8 + R() * 0.3), pan, tone); }
  function cannon(t, k = 1, pan = 0) { boom(t, 1.1 * k, pan); shot(t, 0.6 * k, pan, 0.6); const g = ctx.createGain(); g.connect(out(SFX, pan)); env(g, t, 0.001, 0.4 * k, 0.01, 0.25); const n = nz(t, t + 0.3), hp = filt('highpass', 900); n.connect(hp); hp.connect(g); }
  function whoosh(t, dur, k = 0.2, f0 = 300, f1 = 3000, pan0 = -0.6, pan1 = 0.6) {
    const g = ctx.createGain(), p = ctx.createStereoPanner(); g.connect(p); p.connect(SFX);
    p.pan.setValueAtTime(pan0, t); p.pan.linearRampToValueAtTime(pan1, t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(k, t + dur * 0.6); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    const n = nz(t, t + dur), bp = filt('bandpass', f0, 1.2); bp.frequency.setValueAtTime(f0, t); bp.frequency.exponentialRampToValueAtTime(f1, t + dur * 0.6); bp.frequency.exponentialRampToValueAtTime(f0 * 0.6, t + dur); n.connect(bp); bp.connect(g);
  }
  function roar(t0, t1, k = 0.25, cut = 900, pan = 0, flutter = 0) {   // 发动机 / 火箭的轰鸣
    const g = ctx.createGain(); g.connect(out(SFX, pan));
    g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(k, t0 + 0.3); g.gain.setValueAtTime(k, Math.max(t0 + 0.31, t1 - 0.6)); g.gain.exponentialRampToValueAtTime(0.0001, t1);
    const n = nz(t0, t1, brown), lp = filt('lowpass', cut, 0.8); n.connect(lp); lp.connect(g);
    const n2 = nz(t0, t1), bp = filt('bandpass', cut * 2.2, 0.9), g2 = ctx.createGain(); g2.gain.value = 0.35; n2.connect(bp); bp.connect(g2); g2.connect(g);
    if (flutter) { const l = osc('sine', flutter, t0, t1), lg = ctx.createGain(); lg.gain.value = k * 0.8; l.connect(lg); lg.connect(g.gain); }
  }
  function splash(t, k = 0.35, pan = 0) { const g = ctx.createGain(); g.connect(out(SFX, pan)); env(g, t, 0.005, k, 0.15, 1.4); const n = nz(t, t + 2), lp = filt('lowpass', 2600); lp.frequency.exponentialRampToValueAtTime(500, t + 1.5); n.connect(lp); lp.connect(g); boom(t, 0.4 * k, pan, 0.5); }
  function radio(t, dur = 1.6, k = 0.08) { const g = ctx.createGain(); g.connect(out(SFX)); env(g, t, 0.01, k, dur, 0.15); const n = nz(t, t + dur + 0.3), bp = filt('bandpass', 2200, 2); n.connect(bp); bp.connect(g); const s = ctx.createGain(); s.connect(out(SFX)); env(s, t, 0.001, k * 2.5, 0.05, 0.08); const n2 = nz(t, t + 0.2), hp = filt('highpass', 3000); n2.connect(hp); hp.connect(s); const e = ctx.createGain(); e.connect(out(SFX)); env(e, t + dur, 0.001, k * 2, 0.04, 0.08); const n3 = nz(t + dur, t + dur + 0.2), hp3 = filt('highpass', 3000); n3.connect(hp3); hp3.connect(e); }
  function horn(t, dur = 3.2, k = 0.05) { const g = ctx.createGain(), lp = filt('lowpass', 420, 2); g.connect(out(SFX, 0.5)); lp.connect(g); g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(k, t + 0.5); g.gain.setValueAtTime(k, t + dur - 0.8); g.gain.linearRampToValueAtTime(0, t + dur); for (const d of [0, 7]) { const o = osc('sawtooth', 98, t, t + dur); o.detune.value = d; o.connect(lp); } }
  function clank(t, k = 0.25, pan = 0) { const g = ctx.createGain(); g.connect(out(SFX, pan)); env(g, t, 0.001, k, 0.02, 0.6); for (const f of [420, 610, 950]) { const n = nz(t, t + 0.8), bp = filt('bandpass', f, 18); n.connect(bp); bp.connect(g); } boom(t, 0.25, pan, 0.4); }
  function ambience(t0, t1, k = 0.12) {   // 海浪：低通噪声，慢慢起伏
    const g = ctx.createGain(); g.connect(out(SFX)); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(k, t0 + 1.5); g.gain.setValueAtTime(k, t1 - 1); g.gain.linearRampToValueAtTime(0, t1);
    const n = nz(t0, t1, brown), lp = filt('lowpass', 700); n.connect(lp); lp.connect(g);
    const l = osc('sine', 0.18, t0, t1), lg = ctx.createGain(); lg.gain.value = 300; l.connect(lg); lg.connect(lp.frequency);
    const n2 = nz(t0, t1), hp = filt('bandpass', 2200, 0.6), g2 = ctx.createGain(); g2.gain.value = 0.06; n2.connect(hp); hp.connect(g2); g2.connect(g);
    const l2 = osc('sine', 0.11, t0, t1), lg2 = ctx.createGain(); lg2.gain.value = 0.1; l2.connect(lg2); lg2.connect(g2.gain);
  }
  function whine(t0, t1, f = 9500, k = 0.012) { const g = ctx.createGain(); g.connect(out(SFX)); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(k, t0 + 0.4); g.gain.setValueAtTime(k, t1 - 0.2); g.gain.linearRampToValueAtTime(0, t1); const o = osc('sine', f, t0, t1); o.connect(g); }

  // —— 时间线（按宣传片的标记）——
  const at = {}, mk = {}; let T = 0;
  for (const s of SHOTS) { at[s.id] = T; if (s.mark) mk[s.mark] = T; T += s.dur; }
  const end = T;
  const D = 50, F = 53, A = 57, C = 48, Bb = 46, G = 43;
  const prog = [[D, A], [Bb, F], [C, G], [A, A]];
  // 一、深夜：低音、海浪、心跳 → 舰队弦乐顿弓 100 拍渐强 → H 时重击
  drone(D - 12, 0.2, mk.fleet + 0.5, 0.11, 380);
  pad([D + 12, F + 12, A + 12], 2.5, mk.fleet + 1, 0.022, 2200, 0.2);
  ambience(0, mk.fleet + 2, 0.13);
  for (let t = at.P02 + 0.2; t < mk.fleet; t += 0.92) heart(t, 0.32);
  const b100 = 60 / 100 / 2;
  for (let t = mk.fleet, i = 0; t < mk.hhour; t += b100, i++) {
    const bar = Math.floor(i / 8) % 4, [r] = prog[bar];
    const k = Math.min(1, (t - mk.fleet) / (mk.hhour - mk.fleet));
    stacc(r - 12, t, 0.15, 0.05 + 0.035 * k, (i % 2) ? 0.25 : -0.25);
    if (k > 0.25) stacc(r, t, 0.12, 0.035, (i % 2) ? -0.3 : 0.3);
    if (i % 8 === 0) taiko(t, 0.3 + 0.25 * k);
  }
  drone(D - 24 + 12, mk.fleet, mk.hhour + 1, 0.08, 300);
  pad([D, A, D + 12], at.P04, mk.hhour + 0.6, 0.03, 1800);
  riser(mk.hhour - 3.2, mk.hhour + 0.7, 0.13);
  const hh = mk.hhour + 0.7;
  braam([D - 12, A - 12, D], hh, 3.2, 0.22); taiko(hh, 0.65, 70); cymbal(hh, 0.08, 4);
  // 二、战斗 120 拍：慢镜头那几镜里鼓停下来，只留低音和铺底（镜头慢下来、音乐也屏住一口气）
  const b120 = 60 / 120 / 2;
  const slowAt = SHOTS.filter(s => s.slow).map(s => [at[s.id], at[s.id] + s.dur]);
  const inSlow = t => slowAt.some(([a, b]) => t >= a && t < b);
  const battle0 = at.P10, battleEnd = mk.dawn;
  for (let t = battle0, i = 0; t < battleEnd - 0.05; t += b120, i++) {
    if (inSlow(t) && t < mk.battle) continue;
    const bar = Math.floor(i / 8) % 4, [r] = prog[bar];
    const inten = Math.min(1, (t - battle0) / 14);
    if (inSlow(t)) { if (i % 8 === 0) stacc(r - 24 + 12, t, 0.5, 0.05); continue; }
    stacc(r - 12, t, 0.12, 0.05 + 0.03 * inten, (i % 2) ? 0.3 : -0.3);
    if (i % 2 === 0) stacc(r - 24 + 12, t, 0.18, 0.04);
    if (t > mk.battle) stacc((i % 4 < 2 ? r + 12 : r + 7 + 12), t, 0.1, 0.025 * inten, (i % 2) ? -0.4 : 0.4);
    if (i % 4 === 0) taiko(t, 0.38 + 0.2 * inten, 85, -0.2);
    if (i % 8 === 6) taiko(t, 0.3, 110, 0.2);
    if (i % 8 === 4 && t > mk.battle) snare(t, 0.08);
    if (t > at.P14 && i % 16 === 15) for (let k = 0; k < 4; k++) snare(t + k * b120 / 4, 0.05 + k * 0.015);
  }
  for (const s of SHOTS) if (s.slow && at[s.id] > battle0 - 1 && at[s.id] < battleEnd) {   // 慢镜头：一声往下的呼啸 + 低音
    whoosh(at[s.id], 1.6, 0.1, 2400, 200, 0, 0);
    drone(D - 24, at[s.id], at[s.id] + s.dur, 0.12, 200);
  }
  for (const [id, notes] of [['P11', [D - 12, A - 12]], ['P14', [Bb - 12, F - 12]], ['P21', [C - 12, G - 12]], ['P15', [D - 12, A - 12, D]], ['P20', [A - 12, A]]]) if (at[id] !== undefined) braam(notes, at[id] + 0.25, 3.0, 0.15);
  pad([D, F, A, D + 12], mk.battle, at.P14, 0.03, 1600);
  pad([Bb - 12, F, Bb, D + 12], at.P14, at.P21, 0.035, 1700);
  pad([C, G, C + 12, 64], at.P21, battleEnd + 0.3, 0.035, 1900);
  drone(D - 24, battle0, battleEnd + 0.2, 0.09, 260);
  riser(battleEnd - 4, battleEnd, 0.13);
  // 三、天亮：一下静下来（耳鸣），大提琴旋律，再起 100 拍的脉冲推到片名
  whine(battleEnd, battleEnd + 2.6, 7200, 0.02);
  pad([D, F, A], battleEnd + 1.2, mk.title + 0.4, 0.045, 1300);
  drone(D - 12, battleEnd + 0.8, mk.title + 0.5, 0.07, 300);
  cello(battleEnd + 1.8, 0.6, [[0, 57, 2], [2, 58, 1], [3, 57, 1], [4, 53, 2], [6, 55, 1], [7, 57, 2.5], [10, 62, 2], [12, 60, 1], [13, 58, 1], [14, 57, 3]], 0.075);
  const rise0 = battleEnd + 8.5;
  for (let t = rise0, i = 0; t < mk.title - 0.05; t += b100, i++) {
    const k = Math.min(1, (t - rise0) / (mk.title - rise0));
    const [r] = prog[Math.floor(i / 8) % 4];
    pulse((i % 8 < 6 ? r - 12 : C - 12), t, 0.05 + 0.04 * k);
    if (i % 8 === 0) taiko(t, 0.25 + 0.3 * k, 80);
    if (k > 0.5 && i % 2 === 0) stacc(r, t, 0.1, 0.03 * k, (i % 4 < 2) ? 0.3 : -0.3);
  }
  // 天亮那一幕的几下重音：机群从头顶掠过、直升机编队过顶
  if (at.P30 !== undefined) { braam([D - 12, A - 12, D], at.P30 + 1.2, 3.2, 0.16); taiko(at.P30 + 1.2, 0.6, 70); cymbal(at.P30 + 1.2, 0.06, 3); }
  if (at.P34 !== undefined) braam([F - 12, C - 12], at.P34 + 1.4, 2.6, 0.1);
  riser(mk.title - 3.5, mk.title + 0.55, 0.14);
  // 片名：重击、长尾
  const th = mk.title + 0.55;
  braam([D - 12, A - 12, D, F], th, 5, 0.26); taiko(th, 0.75, 60); taiko(th + 0.02, 0.45, 120); cymbal(th, 0.1, 5);
  pad([D, A, D + 12, F + 12], th + 0.3, mk.features + 1, 0.035, 1500);
  // 卖点、红蓝对抗：脉冲
  for (let t = mk.features + 0.3, i = 0; t < mk.end - 0.2; t += b120, i++) { pulse((i % 8 < 6 ? D - 12 : C - 12), t, 0.07); if (i % 4 === 0) taiko(t, 0.22, 95); }
  pad([D, F, A], mk.features, mk.end + 1.5, 0.03, 1400);
  braam([D - 12, A - 12], mk.features + 3.75, 2.5, 0.1);
  if (at.P39 !== undefined) { braam([D - 12, A - 12, D], at.P39 + 0.3, 3, 0.16); taiko(at.P39 + 0.3, 0.5, 70); }
  // 结尾
  braam([D - 12, A - 12, D], mk.end + 0.4, 4, 0.14);
  drone(D - 12, mk.end, end + 1.2, 0.08, 280);
  pad([D, A, D + 12], mk.end, end + 1.2, 0.03, 1200);

  // —— 每个镜头的音效 ——
  for (const s of SHOTS) {
    const t0 = at[s.id];
    for (const e of (s.events || [])) {
      const t = t0 + e.t, v = e.v ?? 1;
      switch (e.k) {
        case 'horn': horn(t); break;
        case 'wind': roar(t, t + s.dur, 0.035, 600, 0, 0.3); break;
        case 'radioStatic': radio(t, 0.9, 0.05); break;
        case 'nvgWhine': whine(t, t + s.dur, 9800, 0.01); break;
        case 'distant': boom(t, 0.3, 0.2, 0.9); break;
        case 'shipRumble': roar(t, t + s.dur, 0.12, 260, -0.2); ambience(t, t + s.dur, 0.1); break;
        case 'deckAmb': roar(t, t + s.dur, 0.08, 500, 0.2); break;
        case 'jetSpool': roar(t, t + s.dur + 0.4, 0.22, 1400, 0.1); whoosh(t, 2.4, 0.06, 800, 5000, 0, 0); break;
        case 'boatEngine': roar(t, t + s.dur, 0.11, 320, 0, 6); ambience(t, t + s.dur, 0.14); break;
        case 'radio': radio(t, 2.2, 0.07); break;
        case 'nvgClick': clank(t, 0.05, 0.3); break;
        case 'riser': break;
        case 'launch': roar(t, t + 3.2, 0.35, 700, 0); whoosh(t, 2.8, 0.12, 200, 2500, 0, 0.3); boom(t, 0.6, 0); break;
        case 'catapult': boom(t, 0.5, 0); roar(t, t + 2.4, 0.3, 1600, 0.2); whoosh(t + 0.6, 1.8, 0.2, 500, 4000, -0.5, 0.8); break;
        case 'incoming': for (let i = 0; i < 5; i++) whoosh(t + 0.3 + i * 0.55, 1.6, 0.12, 400, 2600, -0.4 + i * 0.2, 0.4 - i * 0.2); break;
        case 'bigboom': boom(t, 1.2 * v, (R() - 0.5) * 0.6); break;
        case 'boom': boom(t, 0.8 * v, (R() - 0.5) * 0.8); break;
        case 'flarePop': for (let i = 0; i < 3; i++) shot(t + i * 0.8, 0.12, (R() - 0.5), 0.5); break;
        case 'hover': roar(t, t + s.dur, 0.2, 520, 0, 0); roar(t, t + s.dur, 0.08, 2600, 0.3); break;
        case 'whizz': whoosh(t, 0.35, 0.09, 1800, 6000, 0.6, -0.6); break;
        case 'mgStart': mg(t, t0 + (s.events.find(x => x.k === 'mgStop') || { t: s.dur }).t, 13, 0.24, -0.25, 1.1); break;
        case 'rifle': shot(t, 0.32 * v, 0.35, 0.9); break;
        case 'splash': splash(t, 0.32); break;
        case 'battleBed': mg(t + 0.2, t + s.dur, 8, 0.07, -0.6, 1.2); mg(t + 0.5, t + s.dur, 6, 0.06, 0.6, 0.85); for (let i = 0; i < 6; i++) boom(t + 0.4 + R() * (s.dur - 0.5), 0.25, (R() - 0.5) * 1.6, 0.85); break;
        case 'ramp': clank(t, 0.3, -0.3); clank(t + 0.25, 0.25, 0.4); break;
        case 'tankEngine': roar(t, t + s.dur, 0.16, 300, -0.1, 11); break;
        case 'turret': roar(t, t + 1.3, 0.05, 1800, 0.2, 0); break;
        case 'tankFire': cannon(t, 1.0, -0.1); break;
        case 'jetCabin': roar(t, t + s.dur, 0.2, 900, 0); break;
        case 'jetPass': whoosh(t, 2.4, 0.3, 300, 2800, -0.8, 0.8); roar(t, t + 2.4, 0.15, 1200, 0); break;
        case 'flares': for (let i = 0; i < 8; i++) shot(t + i * 0.09, 0.08, (i % 2 ? 0.4 : -0.4), 2.2); break;
        case 'missileLaunch': whoosh(t, 2.0, 0.2, 400, 3500, -0.2, 0.6); roar(t, t + 1.8, 0.15, 1400, 0.3); break;
        case 'rotor': roar(t, t + s.dur, 0.22, 380, 0, 18); break;
        case 'rockets': for (let i = 0; i < 8; i++) whoosh(t + i * 0.09, 1.0, 0.1, 600, 4000, -0.3, 0.3); break;
        case 'aftermath': ambience(t, t + s.dur, 0.08); roar(t, t + s.dur, 0.03, 500, 0, 0.2); for (let i = 0; i < 4; i++) boom(t + 1 + i * 1.7, 0.12, (R() - 0.5), 0.95); break;
        case 'lockGrowl': for (let i = 0; i < 9; i++) { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t + i * 0.12, 0.005, 0.035, 0.05, 0.03); const o = osc('square', 820, t + i * 0.12, t + i * 0.12 + 0.12); const lp = filt('lowpass', 2400); o.connect(lp); lp.connect(g); } break;
        case 'lockTone': { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t, 0.005, 0.05, 1.0, 0.1); const o = osc('square', 1240, t, t + 1.2); const lp = filt('lowpass', 3000); o.connect(lp); lp.connect(g); } break;
        case 'bay': roar(t, t + 0.9, 0.05, 1800, -0.2, 0); clank(t + 0.75, 0.12, -0.2); break;
        case 'release': clank(t, 0.18, 0); break;
        case 'missileFly': roar(t, t + s.dur, 0.18, 1600, 0, 0); whoosh(t, s.dur * 0.6, 0.08, 900, 4200, -0.2, 0.2); break;
        case 'airboom': boom(t, 1.5, 0); boom(t + 0.05, 0.9, -0.4, 0.3); boom(t + 0.25, 0.6, 0.5, 0.5); break;
        case 'rocketRipple': for (let i = 0; i < (e.n || 10); i++) { const tt = t + i / (e.rate || 15); shot(tt, 0.16 * v, (i % 2 ? 0.35 : -0.35), 0.7); whoosh(tt, 0.7, 0.05 * v, 500, 3500, (i % 2 ? 0.3 : -0.3), 0); } break;
        case 'ambience': break;
        default: break;
      }
    }
  }
  const buf = await ctx.startRendering();
  // 归一化到 -1 dBFS，转 16 位 WAV
  const L = buf.getChannelData(0), Rr = buf.getChannelData(1);
  let pk = 0; for (let i = 0; i < L.length; i++) pk = Math.max(pk, Math.abs(L[i]), Math.abs(Rr[i]));
  const k = pk > 0 ? 0.89 / pk : 1;
  const n = L.length, data = new DataView(new ArrayBuffer(44 + n * 4));
  const W = (o, s) => { for (let i = 0; i < s.length; i++) data.setUint8(o + i, s.charCodeAt(i)); };
  W(0, 'RIFF'); data.setUint32(4, 36 + n * 4, true); W(8, 'WAVE'); W(12, 'fmt '); data.setUint32(16, 16, true); data.setUint16(20, 1, true); data.setUint16(22, 2, true);
  data.setUint32(24, SR, true); data.setUint32(28, SR * 4, true); data.setUint16(32, 4, true); data.setUint16(34, 16, true); W(36, 'data'); data.setUint32(40, n * 4, true);
  for (let i = 0; i < n; i++) { data.setInt16(44 + i * 4, Math.max(-1, Math.min(1, L[i] * k)) * 32767, true); data.setInt16(46 + i * 4, Math.max(-1, Math.min(1, Rr[i] * k)) * 32767, true); }
  const bytes = new Uint8Array(data.buffer);
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
