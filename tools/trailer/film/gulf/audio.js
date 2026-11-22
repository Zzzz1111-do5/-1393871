// 海湾战争版的配乐、音效（同 ../audio.js 的离线合成，乐器、音效件一样，时间线、音效种类按 gulf/shots.js）
//   配乐 E 小调：夜里低音 + 风 + 远处的爆炸 → 空袭一段弦乐顿弓渐强、命中时铜管重击 → 无人机一段电子脉冲 → 坦克战太鼓、弦乐、铜管 →
//   阿帕奇被击落一记重击 → 歼-16 脉冲 → 油田大火静下来、大提琴独奏 → 片名重击 → 卖点脉冲 → 收尾
import { rng } from '../lib.js';

const SR = 48000;
const mtof = m => 440 * Math.pow(2, (m - 69) / 12);

export async function renderGulfScore(SHOTS) {
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

  // —— 时间线 ——
  const at = {}; let T = 0;
  for (const s of SHOTS) { at[s.id] = T; T += s.dur; }
  const end = T;
  const E = 52, G = 55, B = 59, C = 48, D = 50, A = 57, Fs = 54;   // E 小调（MIDI）
  const prog = [[E, B], [C, G], [D, A], [B - 12, Fs]];
  // 夜：低音、风、心跳
  drone(E - 12, 0.2, at.G03 + 0.6, 0.1, 360);
  pad([E + 12, G + 12, B + 12], 2.2, at.G03 + 1, 0.018, 2000, 0.2);
  for (let t = at.G02 + 0.3; t < at.G03 + 0.5; t += 0.9) heart(t, 0.28);
  // 空袭：弦乐顿弓 104 拍，一小节一小节加厚；命中时铜管
  const b104 = 60 / 104 / 2;
  for (let t = at.G03, i = 0; t < at.G09 - 0.1; t += b104, i++) {
    const bar = Math.floor(i / 8) % 4, [r] = prog[bar];
    const k = Math.min(1, (t - at.G03) / 14);
    stacc(r - 12, t, 0.15, 0.045 + 0.035 * k, (i % 2) ? 0.25 : -0.25);
    if (t > at.G04) stacc(r, t, 0.12, 0.03 + 0.01 * k, (i % 2) ? -0.3 : 0.3);
    if (i % 8 === 0) taiko(t, 0.26 + 0.24 * k, 85);
    if (t > at.G06 && i % 4 === 2) snare(t, 0.05);
  }
  drone(E - 24 + 12, at.G03, at.G09 + 0.6, 0.075, 300);
  pad([E, B, E + 12], at.G04, at.G07 + 0.5, 0.028, 1800);
  riser(at.G06 + 1.2, at.G07 + 0.6, 0.12);
  braam([E - 12, B - 12, E], at.G07 + 0.6, 3.4, 0.2); cymbal(at.G07 + 0.6, 0.06, 4);
  // 无人机：安静下来，电子脉冲（八分音符）、远处的低音
  for (let t = at.G09, i = 0; t < at.G12 - 0.2; t += 60 / 112 / 2, i++) pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.045 + 0.02 * Math.min(1, (t - at.G09) / 6));
  drone(E - 12, at.G09 - 0.4, at.G12 + 0.4, 0.07, 320);
  pad([E, G, B], at.G09, at.G12, 0.022, 1300);
  braam([E - 12, B - 12], at.G11 + 1.1, 2.6, 0.11);
  // 坦克战：120 拍，太鼓、弦乐、铜管
  const b120 = 60 / 120 / 2;
  const battle0 = at.G12, battle1 = at.G31;
  for (let t = battle0, i = 0; t < battle1 - 0.05; t += b120, i++) {
    const bar = Math.floor(i / 8) % 4, [r] = prog[bar];
    const inten = Math.min(1, (t - battle0) / 12) * (t > at.G27 ? 0.75 : 1);
    stacc(r - 12, t, 0.12, 0.045 + 0.03 * inten, (i % 2) ? 0.3 : -0.3);
    if (i % 2 === 0) stacc(r - 24 + 12, t, 0.18, 0.038);
    if (t > at.G13) stacc((i % 4 < 2 ? r + 12 : r + 7 + 12), t, 0.1, 0.022 * inten, (i % 2) ? -0.4 : 0.4);
    if (i % 4 === 0) taiko(t, 0.34 + 0.18 * inten, 85, -0.2);
    if (i % 8 === 6 && t > at.G14) taiko(t, 0.28, 110, 0.2);
    if (i % 8 === 4 && t > at.G15) snare(t, 0.07);
    if (t > at.G20 && i % 16 === 15) for (let k = 0; k < 4; k++) snare(t + k * b120 / 4, 0.05 + k * 0.015);
  }
  for (const [id, dt, notes, dur] of [['G13', 0.02, [E - 12, B - 12], 3.4], ['G16', 0.9, [C - 12, G - 12], 3.0], ['G18', 1.85, [D - 12, A - 12, D], 3.0],
    ['G20', 0.02, [B - 24, Fs - 12], 3.5], ['G21', 0.02, [E - 12, B - 12], 3.0], ['G26', 2.6, [E - 12, B - 12, E, G], 4.0], ['G27', 0.02, [C - 12, G - 12], 3.0], ['G30', 0.6, [D - 12, A - 12], 3.0]]) braam(notes, at[id] + dt, dur, 0.13);
  pad([E, G, B, E + 12], battle0, at.G16, 0.028, 1600);
  pad([C - 12, G, C, E + 12], at.G16, at.G21, 0.032, 1700);
  pad([D, A, D + 12, Fs + 12], at.G21, at.G27, 0.032, 1900);
  pad([E, B, E + 12, G + 12], at.G27, battle1 + 0.3, 0.03, 1700);
  drone(E - 24, battle0, battle1 + 0.2, 0.085, 260);
  riser(at.G25, at.G26 + 2.6, 0.11);
  riser(at.G30, battle1, 0.1);
  // 油田大火：一下静下来（耳鸣），独奏
  whine(battle1, battle1 + 2.4, 7400, 0.018);
  pad([E, G, B], battle1 + 0.8, at.G32 + 0.4, 0.042, 1300);
  drone(E - 12, battle1 + 0.5, at.G32 + 0.5, 0.07, 300);
  cello(battle1 + 1.2, 0.62, [[0, 59, 2], [2, 60, 1], [3, 59, 1], [4, 55, 2], [6, 57, 1], [7, 59, 1.6]], 0.075);   // B C B G A B
  // 片名
  const th = at.G32 + 0.55;
  braam([E - 12, B - 12, E, G], th, 5, 0.24); taiko(th, 0.7, 60); taiko(th + 0.02, 0.4, 120); cymbal(th, 0.1, 5);
  pad([E, B, E + 12, G + 12], th + 0.3, at.G33 + 1, 0.033, 1500);
  // 卖点：脉冲
  for (let t = at.G33 + 0.3, i = 0; t < at.G34 - 0.2; t += b120, i++) { pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.065); if (i % 4 === 0) taiko(t, 0.22, 95); }
  pad([E, G, B], at.G33, at.G34 + 1.5, 0.028, 1400);
  braam([E - 12, B - 12], at.G33 + 3.75, 2.5, 0.09);
  drone(E - 12, at.G34, end + 1.2, 0.08, 280);
  pad([E, B, E + 12], at.G34, end + 1.2, 0.028, 1200);

  // —— 音效 ——
  function beep(t, f = 1600, k = 0.03, d = 0.07) { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t, 0.003, k, d, 0.03); const o = osc('square', f, t, t + d + 0.1); const lp = filt('lowpass', 3200); o.connect(lp); lp.connect(g); }
  function desertWind(t0, t1, k = 0.06) { roar(t0, t1, k, 520, 0, 0.25); const g = ctx.createGain(); g.connect(out(SFX, -0.3)); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(k * 0.5, t0 + 1); g.gain.setValueAtTime(k * 0.5, t1 - 0.5); g.gain.linearRampToValueAtTime(0, t1); const n = nz(t0, t1), bp = filt('bandpass', 1700, 1.4); n.connect(bp); bp.connect(g); const l = osc('sine', 0.23, t0, t1), lg = ctx.createGain(); lg.gain.value = 700; l.connect(lg); lg.connect(bp.frequency); }
  function gatlingSnd(t0, t1, rate, k = 0.3, pan = 0, tone = 1) { roar(t0, t1 + 0.1, k * 0.9, 1400 * tone, pan, rate * 0.5); mg(t0, t1, rate * 0.35, k * 0.5, pan, tone * 1.2); }
  for (const s of SHOTS) {
    const t0 = at[s.id];
    for (const e of (s.events || [])) {
      const t = t0 + e.t, v = e.v ?? 1, d = e.d ?? 2;
      switch (e.k) {
        case 'desertWind': desertWind(t, t + s.dur + 0.3); break;
        case 'aaaFar': mg(t, t0 + s.dur, 9, 0.05, 0.3, 0.7); mg(t + 0.3, t0 + s.dur, 6, 0.04, -0.4, 0.6); break;
        case 'distantBoom': boom(t, 0.35 * v + 0.1, (R() - 0.5) * 0.8, 0.9); break;
        case 'vulcan': gatlingSnd(t, t + d, 50, 0.3, 0.2, 1.3); break;
        case 'nvgWhine': whine(t, t + s.dur, 9800, 0.01); break;
        case 'radarHum': roar(t, t + s.dur, 0.04, 260, 0, 1.6); whine(t, t + s.dur, 3200, 0.004); break;
        case 'radio': radio(t, 1.6, 0.06); break;
        case 'jetLow': roar(t, t + s.dur, 0.18, 900, 0, 0); break;
        case 'jetCabin': roar(t, t + s.dur, 0.16, 800, 0); break;
        case 'jetCruise': roar(t, t + s.dur, 0.14, 700, 0); whoosh(t, s.dur, 0.05, 600, 1800, -0.3, 0.3); break;
        case 'samLaunch': roar(t, t + 3.2, 0.38 * v, 700, 0); whoosh(t, 2.8, 0.14, 200, 2500, 0, 0.3); boom(t, 0.7 * v, 0); break;
        case 'beepSoft': beep(t, 1700, 0.028); break;
        case 'lockTone': { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t, 0.005, 0.045, 0.9, 0.1); const o = osc('square', 1240, t, t + 1.1); const lp = filt('lowpass', 3000); o.connect(lp); lp.connect(g); } break;
        case 'release': clank(t, 0.2, 0); break;
        case 'bigboom': boom(t, 1.2 * v, (R() - 0.5) * 0.6); break;
        case 'boom': boom(t, 0.85 * v, (R() - 0.5) * 0.8); break;
        case 'boomFar': boom(t, 0.55 * v, (R() - 0.5) * 0.6, 0.6); break;
        case 'missileWhoosh': whoosh(t, 2.2, 0.16, 400, 3500, 0.4, -0.4); break;
        case 'jetPass': whoosh(t, 2.4, 0.32 * v, 300, 2800, -0.8, 0.8); roar(t, t + 2.4, 0.16, 1200, 0); break;
        case 'fireRoar': roar(t, t + s.dur, 0.08, 420, 0, 3); break;
        case 'fireField': roar(t, t + s.dur, 0.1, 380, 0, 2); desertWind(t, t + s.dur, 0.04); break;
        case 'droneHum': roar(t, t + s.dur, 0.08, 520, 0, 34); desertWind(t, t + s.dur, 0.03); break;
        case 'artyFar': boom(t, 0.4, -0.3, 0.8); break;
        case 'cookoff': for (let i = 0; i < 6; i++) boom(t + i * 0.35 + R() * 0.2, 0.25, (R() - 0.5), 0.4); roar(t, t + 2.5, 0.12, 900, 0, 7); break;
        case 'tankColumn': roar(t, t + s.dur, 0.18, 300, -0.1, 11); roar(t, t + s.dur, 0.06, 1800, 0.2, 23); break;
        case 'tankEngines': roar(t, t + s.dur, 0.14, 280, 0, 9); break;
        case 'tankIdle': roar(t, t + s.dur, 0.12, 260, 0, 8); break;
        case 'turretWhine': roar(t, t + 1.6, 0.05, 1900, 0.2, 0); whine(t, t + 1.4, 2600, 0.006); break;
        case 'laser': beep(t, 2400, 0.03, 0.18); break;
        case 'tankFire': cannon(t, 1.05 * v, -0.1); break;
        case 'tankFireFar': cannon(t, 0.55 * v, (R() - 0.5) * 0.8); break;
        case 'sabotWhizz': whoosh(t, 0.32, 0.18, 2200, 7000, 0.7, -0.7); break;
        case 'eraBlast': boom(t, 0.9, 0.1); shot(t, 0.5, 0.1, 0.5); clank(t + 0.02, 0.3, 0.1); break;
        case 'slowBoom': boom(t + 0.05, 1.4, 0); roar(t, t + s.dur, 0.12, 300, 0, 1.2); break;
        case 'rotor': roar(t, t + s.dur, 0.22, 380, 0, 18); break;
        case 'hellfire': whoosh(t, 1.6, 0.2, 500, 3800, 0, 0.4); roar(t, t + 1.4, 0.14, 1500, 0.2); break;
        case 'rwrLock': for (let i = 0; i < 10; i++) beep(t + i * 0.13, 1100, 0.04, 0.07); break;
        case 'gatling25': gatlingSnd(t, t + d, 55, 0.34, 0, 1.0); break;
        case 'manpads': whoosh(t, 1.8, 0.2, 400, 3200, 0, 0.4); boom(t, 0.3, 0, 0.3); break;
        case 'missileWarn': for (let i = 0; i < 18; i++) beep(t + i * 0.15, i % 2 ? 1500 : 1100, 0.045, 0.1); break;
        case 'flares': for (let i = 0; i < 12; i++) shot(t + i * 0.06, 0.08, (i % 2 ? 0.4 : -0.4), 2.2); break;
        case 'airboom': boom(t, 1.4, 0); boom(t + 0.05, 0.8, -0.4, 0.3); break;
        case 'heliSpin': roar(t, t + d, 0.24, 420, 0, 30); whoosh(t, d, 0.1, 300, 900, -0.6, 0.6); for (let i = 0; i < 5; i++) clank(t + 0.3 + i * 0.4, 0.06, (R() - 0.5)); break;
        case 'missileLaunch': whoosh(t, 2.0, 0.18 * v, 400, 3500, -0.2, 0.6); roar(t, t + 1.6, 0.13 * v, 1400, 0.3); break;
        case 'endTail': break;
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
