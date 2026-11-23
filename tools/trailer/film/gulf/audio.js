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

  // —— 时间线（短剧版剪辑表 gulf/story.js：H 钩子、S/MAP 下任务、A 爱国者、B 炮兵、C 坦克战、D 阿帕奇、E 歼-16、F 结局、T 片名）——
  const at = {}; let T = 0;
  for (const s of SHOTS) { at[s.id] = T; T += s.dur; }
  const end = T;
  const E = 52, G = 55, B = 59, C = 48, D = 50, A = 57, Fs = 54, Gs = 56;   // E 小调（MIDI）
  const prog = [[E, B], [C, G], [D, A], [B - 12, Fs]];
  const sec = (a, b) => [at[a], at[b]];
  // 钩子：低音、越跳越快的心跳、一路往上冲，冲到击中那一下（定格的重击、耳鸣在音效 freezeHit 里）；黑场倒带
  drone(E - 12, 0, at.H3 + 0.2, 0.09, 340);
  for (let t = 0.05, k = 0; t < at.H2 + 0.55; k++) { heart(t, 0.2 + 0.015 * k); t += Math.max(0.36, 0.78 - k * 0.08); }
  riser(0.1, at.H2 + 0.63, 0.12);
  // 下任务：夜里的低音、高处一层弦；沙盘：电子脉冲（八分音符）、慢慢加厚
  drone(E - 12, at.S1, at.A1 + 0.5, 0.085, 320);
  pad([E + 12, G + 12, B + 12], at.S1 + 0.3, at.MAP + 1, 0.018, 2000, 0.2);
  for (let t = at.MAP + 0.4, i = 0; t < at.A1 - 0.15; t += 60 / 112 / 2, i++) pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.04 + 0.03 * Math.min(1, (t - at.MAP) / 8));
  pad([E, G, B], at.MAP + 2.5, at.A1 + 0.4, 0.024, 1300);
  // 第一颗钉子：弦乐顿弓 104 拍，一小节一小节加厚，6 发命中时铜管（大字 hitWord）
  {
    const [a0, a1] = sec('A1', 'B1'), b = 60 / 104 / 2;
    for (let t = a0, i = 0; t < a1 - 0.1; t += b, i++) {
      const [r] = prog[Math.floor(i / 8) % 4], k = Math.min(1, (t - a0) / 14);
      stacc(r - 12, t, 0.15, 0.045 + 0.035 * k, (i % 2) ? 0.25 : -0.25);
      if (t > at.A2) stacc(r, t, 0.12, 0.03 + 0.01 * k, (i % 2) ? -0.3 : 0.3);
      if (i % 8 === 0) taiko(t, 0.26 + 0.24 * k, 85);
      if (t > at.A4 && i % 4 === 2) snare(t, 0.05);
    }
    drone(E - 12, a0, a1 + 0.4, 0.075, 300);
    pad([E, B, E + 12], at.A2, at.A6 + 0.5, 0.028, 1800);
    riser(at.A5 + 0.8, at.A6 + 0.6, 0.11);
  }
  // 第二颗钉子：静下来，电子脉冲、远处的低音
  {
    const [b0, b1] = sec('B1', 'C1');
    for (let t = b0, i = 0; t < b1 - 0.2; t += 60 / 112 / 2, i++) pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.045 + 0.02 * Math.min(1, (t - b0) / 6));
    drone(E - 12, b0 - 0.3, b1 + 0.3, 0.07, 320);
    pad([E, G, B], b0, b1, 0.022, 1300);
  }
  // 坦克战：120 拍，太鼓、弦乐、铜管；毒蛇出场到挨打那一段压下去（只剩低音、太鼓，心跳），挡住了以后全开
  {
    const [c0, c1] = sec('C1', 'D1'), b = 60 / 120 / 2;
    const dip0 = at.C3, dip1 = at.C5 + 1.45;
    for (let t = c0, i = 0; t < c1 - 0.05; t += b, i++) {
      const [r] = prog[Math.floor(i / 8) % 4];
      const dip = t > dip0 && t < dip1;
      const inten = Math.min(1, (t - c0) / 10) * (dip ? 0.4 : 1);
      if (!dip || i % 2 === 0) stacc(r - 12, t, 0.12, 0.045 + 0.03 * inten, (i % 2) ? 0.3 : -0.3);
      if (i % 2 === 0) stacc(r - 24 + 12, t, 0.18, 0.038 * (dip ? 0.7 : 1));
      if (!dip && t > at.C2) stacc((i % 4 < 2 ? r + 12 : r + 7 + 12), t, 0.1, 0.022 * inten, (i % 2) ? -0.4 : 0.4);
      if (i % 4 === 0) taiko(t, 0.34 + 0.18 * inten, 85, -0.2);
      if (!dip && i % 8 === 6 && t > at.C2) taiko(t, 0.28, 110, 0.2);
      if (!dip && i % 8 === 4 && t > at.C6) snare(t, 0.07);
      if (t > at.C10 && i % 16 === 15) for (let k = 0; k < 4; k++) snare(t + k * b / 4, 0.05 + k * 0.015);
    }
    for (let t = dip0 + 0.2; t < at.C5 + 0.85; t += 0.62) heart(t, 0.22);
    braam([E - 12, B - 12], at.C1 + 2.2, 3.0, 0.12);   // 全营——出发！
    pad([E, G, B, E + 12], c0, at.C3, 0.028, 1600);
    pad([C - 12, G, C], at.C3, at.C5 + 1.5, 0.022, 900);
    pad([D, A, D + 12, Fs + 12], at.C5 + 1.5, c1 + 0.3, 0.032, 1900);
    drone(E - 24, c0, c1 + 0.2, 0.085, 260);
    riser(at.C6, at.C8 + 0.3, 0.1);
  }
  // 阿帕奇：先是低音、旋翼（嚣张），偷袭一响警报；盾牌出场以后 128 拍
  {
    const [d0, d1] = sec('D1', 'E1');
    drone(E - 12, d0, d1 + 0.3, 0.08, 300);
    pad([E, G, Fs + 12], d0, at.D4, 0.02, 1100);
    for (let t = d0 + 0.3; t < at.D4; t += 60 / 128 * 2) taiko(t, 0.3, 75);
    const b = 60 / 128 / 2;
    for (let t = at.D4, i = 0; t < d1 - 0.05; t += b, i++) {
      const [r] = prog[Math.floor(i / 8) % 4], k = Math.min(1, (t - at.D4) / 5);
      stacc(r - 12, t, 0.12, 0.05 + 0.025 * k, (i % 2) ? 0.3 : -0.3);
      if (i % 2 === 0) stacc(r, t, 0.1, 0.025 * k, (i % 2) ? -0.35 : 0.35);
      if (i % 4 === 0) taiko(t, 0.38 + 0.12 * k, 88);
      if (i % 8 === 4) snare(t, 0.07);
    }
    pad([D, A, D + 12], at.D4, d1, 0.03, 1800);
    riser(at.D5, at.D6 + 2.35, 0.1);
  }
  // 歼-16：脉冲加厚，往上冲到 4 发命中
  {
    const [e0, e1] = sec('E1', 'F1'), b = 60 / 120 / 2;
    for (let t = e0, i = 0; t < e1 - 0.1; t += b, i++) {
      const [r] = prog[Math.floor(i / 8) % 4], k = Math.min(1, (t - e0) / 8);
      pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.05 + 0.02 * k);
      if (t > at.E2) stacc(r, t, 0.1, 0.02 + 0.02 * k, (i % 2) ? -0.3 : 0.3);
      if (i % 4 === 0) taiko(t, 0.25 + 0.2 * k, 90);
    }
    drone(E - 24, e0, e1 + 0.2, 0.08, 260);
    pad([E, B, E + 12, G + 12], e0, e1 + 0.3, 0.03, 1700);
    riser(at.E3, at.E4 + 2.6, 0.1);
  }
  // 结局：一下静下来，大提琴独奏；「任务完成」金色大字（hitGold）
  {
    const f0 = at.F1;
    whine(f0, f0 + 2.0, 7400, 0.014);
    pad([E, G, B], f0 + 0.6, at.T1 + 0.4, 0.042, 1300);
    drone(E - 12, f0 + 0.3, at.T1 + 0.5, 0.07, 300);
    cello(f0 + 1.0, 0.6, [[0, 59, 2], [2, 60, 1], [3, 59, 1], [4, 55, 2], [6, 57, 1]], 0.07);   // B C B G A
  }
  // 片名、卖点、片尾
  const th = at.T1 + 0.55;
  braam([E - 12, B - 12, E, G], th, 5, 0.24); taiko(th, 0.7, 60); taiko(th + 0.02, 0.4, 120); cymbal(th, 0.1, 5);
  pad([E, B, E + 12, G + 12], th + 0.3, at.T2 + 1, 0.033, 1500);
  { const b = 60 / 120 / 2; for (let t = at.T2 + 0.3, i = 0; t < at.T3 - 0.2; t += b, i++) { pulse((i % 8 < 6 ? E - 12 : D - 12), t, 0.065); if (i % 4 === 0) taiko(t, 0.22, 95); } }
  pad([E, G, B], at.T2, at.T3 + 1.5, 0.028, 1400);
  braam([E - 12, B - 12], at.T2 + 3.75, 2.5, 0.09);
  drone(E - 12, at.T3, end + 1.2, 0.08, 280);
  pad([E, B, E + 12], at.T3, end + 1.2, 0.028, 1200);

  // —— 音效 ——
  function beep(t, f = 1600, k = 0.03, d = 0.07) { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t, 0.003, k, d, 0.03); const o = osc('square', f, t, t + d + 0.1); const lp = filt('lowpass', 3200); o.connect(lp); lp.connect(g); }
  function desertWind(t0, t1, k = 0.06) { roar(t0, t1, k, 520, 0, 0.25); const g = ctx.createGain(); g.connect(out(SFX, -0.3)); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(k * 0.5, t0 + 1); g.gain.setValueAtTime(k * 0.5, t1 - 0.5); g.gain.linearRampToValueAtTime(0, t1); const n = nz(t0, t1), bp = filt('bandpass', 1700, 1.4); n.connect(bp); bp.connect(g); const l = osc('sine', 0.23, t0, t1), lg = ctx.createGain(); lg.gain.value = 700; l.connect(lg); lg.connect(bp.frequency); }
  function gatlingSnd(t0, t1, rate, k = 0.3, pan = 0, tone = 1) { roar(t0, t1 + 0.1, k * 0.9, 1400 * tone, pan, rate * 0.5); mg(t0, t1, rate * 0.35, k * 0.5, pan, tone * 1.2); }
  for (const s of SHOTS) {
    const t0 = at[s.id];
    for (const e of (s.events || [])) {
      const t = t0 + e.t, v = e.v ?? 1, d = e.d ?? 2, sd = s.adur ?? s.dur;
      switch (e.k) {
        case 'desertWind': desertWind(t, t + sd + 0.3); break;
        case 'aaaFar': mg(t, t0 + sd, 9, 0.05, 0.3, 0.7); mg(t + 0.3, t0 + sd, 6, 0.04, -0.4, 0.6); break;
        case 'distantBoom': boom(t, 0.35 * v + 0.1, (R() - 0.5) * 0.8, 0.9); break;
        case 'vulcan': gatlingSnd(t, t + d, 50, 0.3, 0.2, 1.3); break;
        case 'nvgWhine': whine(t, t + sd, 9800, 0.01); break;
        case 'radarHum': roar(t, t + sd, 0.04, 260, 0, 1.6); whine(t, t + sd, 3200, 0.004); break;
        case 'radio': radio(t, 1.6, 0.06); break;
        case 'jetLow': roar(t, t + sd, 0.18, 900, 0, 0); break;
        case 'jetCabin': roar(t, t + sd, 0.16, 800, 0); break;
        case 'jetCruise': roar(t, t + sd, 0.14, 700, 0); whoosh(t, sd, 0.05, 600, 1800, -0.3, 0.3); break;
        case 'samLaunch': roar(t, t + 3.2, 0.38 * v, 700, 0); whoosh(t, 2.8, 0.14, 200, 2500, 0, 0.3); boom(t, 0.7 * v, 0); break;
        case 'beepSoft': beep(t, 1700, 0.028); break;
        case 'lockTone': { const g = ctx.createGain(); g.connect(out(SFX, 0.1)); env(g, t, 0.005, 0.045, 0.9, 0.1); const o = osc('square', 1240, t, t + 1.1); const lp = filt('lowpass', 3000); o.connect(lp); lp.connect(g); } break;
        case 'release': clank(t, 0.2, 0); break;
        case 'bigboom': boom(t, 1.2 * v, (R() - 0.5) * 0.6); break;
        case 'boom': boom(t, 0.85 * v, (R() - 0.5) * 0.8); break;
        case 'boomFar': boom(t, 0.55 * v, (R() - 0.5) * 0.6, 0.6); break;
        case 'missileWhoosh': whoosh(t, 2.2, 0.16, 400, 3500, 0.4, -0.4); break;
        case 'jetPass': whoosh(t, 2.4, 0.32 * v, 300, 2800, -0.8, 0.8); roar(t, t + 2.4, 0.16, 1200, 0); break;
        case 'fireRoar': roar(t, t + sd, 0.08, 420, 0, 3); break;
        case 'fireField': roar(t, t + sd, 0.1, 380, 0, 2); desertWind(t, t + sd, 0.04); break;
        case 'droneHum': roar(t, t + sd, 0.08, 520, 0, 34); desertWind(t, t + sd, 0.03); break;
        case 'artyFar': boom(t, 0.4, -0.3, 0.8); break;
        case 'cookoff': for (let i = 0; i < 6; i++) boom(t + i * 0.35 + R() * 0.2, 0.25, (R() - 0.5), 0.4); roar(t, t + 2.5, 0.12, 900, 0, 7); break;
        case 'tankColumn': roar(t, t + sd, 0.18, 300, -0.1, 11); roar(t, t + sd, 0.06, 1800, 0.2, 23); break;
        case 'tankEngines': roar(t, t + sd, 0.14, 280, 0, 9); break;
        case 'tankIdle': roar(t, t + sd, 0.12, 260, 0, 8); break;
        case 'turretWhine': roar(t, t + 1.6, 0.05, 1900, 0.2, 0); whine(t, t + 1.4, 2600, 0.006); break;
        case 'laser': beep(t, 2400, 0.03, 0.18); break;
        case 'tankFire': cannon(t, 1.05 * v, -0.1); break;
        case 'tankFireFar': cannon(t, 0.55 * v, (R() - 0.5) * 0.8); break;
        case 'sabotWhizz': whoosh(t, 0.32, 0.18, 2200, 7000, 0.7, -0.7); break;
        case 'eraBlast': boom(t, 0.9, 0.1); shot(t, 0.5, 0.1, 0.5); clank(t + 0.02, 0.3, 0.1); break;
        case 'slowBoom': boom(t + 0.05, 1.4, 0); roar(t, t + sd, 0.12, 300, 0, 1.2); break;
        case 'rotor': roar(t, t + sd, 0.22, 380, 0, 18); break;
        case 'hellfire': whoosh(t, 1.6, 0.2, 500, 3800, 0, 0.4); roar(t, t + 1.4, 0.14, 1500, 0.2); break;
        case 'rwrLock': for (let i = 0; i < 10; i++) beep(t + i * 0.13, 1100, 0.04, 0.07); break;
        case 'gatling25': gatlingSnd(t, t + d, 55, 0.34, 0, 1.0); break;
        case 'manpads': whoosh(t, 1.8, 0.2, 400, 3200, 0, 0.4); boom(t, 0.3, 0, 0.3); break;
        case 'missileWarn': for (let i = 0; i < 18; i++) beep(t + i * 0.15, i % 2 ? 1500 : 1100, 0.045, 0.1); break;
        case 'flares': for (let i = 0; i < 12; i++) shot(t + i * 0.06, 0.08, (i % 2 ? 0.4 : -0.4), 2.2); break;
        case 'airboom': boom(t, 1.4, 0); boom(t + 0.05, 0.8, -0.4, 0.3); break;
        case 'heliSpin': roar(t, t + d, 0.24, 420, 0, 30); whoosh(t, d, 0.1, 300, 900, -0.6, 0.6); for (let i = 0; i < 5; i++) clank(t + 0.3 + i * 0.4, 0.06, (R() - 0.5)); break;
        case 'missileLaunch': whoosh(t, 2.0, 0.18 * v, 400, 3500, -0.2, 0.6); roar(t, t + 1.6, 0.13 * v, 1400, 0.3); break;
        // —— 字幕层（gulf/story.js storyEvents）——
        case 'radioIn': { const g = ctx.createGain(); g.connect(out(SFX, 0)); env(g, t, 0.001, 0.05, 0.02, 0.06); const n = nz(t, t + 0.15), hp = filt('highpass', 2500); n.connect(hp); hp.connect(g);
          const g2 = ctx.createGain(); g2.connect(out(SFX, 0)); env(g2, t + 0.01, 0.005, 0.03, 0.06, 0.08); const n2 = nz(t, t + 0.25), bp = filt('bandpass', e.side === 'blue' ? 1500 : 1900, 3); n2.connect(bp); bp.connect(g2);
          const o = osc('sine', e.side === 'blue' ? 1250 : 1480, t, t + 0.07), og = ctx.createGain(); og.connect(out(SFX, 0)); env(og, t, 0.002, 0.012, 0.03, 0.02); o.connect(og); } break;
        case 'radioOut': { const g = ctx.createGain(); g.connect(out(SFX, 0)); env(g, t, 0.001, 0.03, 0.01, 0.04); const n = nz(t, t + 0.1), hp = filt('highpass', 3000); n.connect(hp); hp.connect(g); } break;
        case 'cardIn': whoosh(t - 0.05, 0.45, 0.12, 500, 4200, -0.6, 0.2); clank(t + 0.22, 0.05, -0.3); break;
        case 'hitWord': braam([E - 12, B - 12], t, 2.4, 0.15); taiko(t, 0.6, 68); taiko(t + 0.01, 0.3, 130); cymbal(t, 0.045, 2.4); break;
        case 'hitGold': braam([E - 12, B - 12, E, Gs], t, 4, 0.17); taiko(t, 0.55, 64); cymbal(t, 0.06, 4); break;
        case 'listIn': whoosh(t, 0.4, 0.07, 800, 5000, 0.6, 0.2); break;
        case 'ding': for (const [f, k] of [[1568, 0.05], [2349, 0.03], [3136, 0.015]]) { const g = ctx.createGain(); g.connect(out(SFX, 0.5)); env(g, t, 0.002, k, 0.02, 1.3); const o = osc('sine', f, t, t + 1.6); o.connect(g); } break;
        case 'alarm': for (let x = 0; x < d; x += 0.36) { beep(t + x, 880, 0.035, 0.16); beep(t + x + 0.18, 660, 0.035, 0.16); } break;
        case 'type': for (let i = 0; i < (e.n || 6); i++) { const tt = t + i * 0.055; const g = ctx.createGain(); g.connect(out(SFX, -0.4)); env(g, tt, 0.0005, 0.03, 0.004, 0.025); const n = nz(tt, tt + 0.05), bp = filt('bandpass', 3800, 2); n.connect(bp); bp.connect(g); } break;
        case 'rewind': { whoosh(t, 0.9, 0.16, 5000, 300, 0.6, -0.6); const g = ctx.createGain(), lp = filt('lowpass', 1600); g.connect(out(SFX)); lp.connect(g); env(g, t, 0.01, 0.07, 0.4, 0.3); const o = osc('sawtooth', 420, t, t + 0.8); o.frequency.exponentialRampToValueAtTime(40, t + 0.7); o.connect(lp); boom(t + 1.2, 0.5, 0, 0.3); } break;
        case 'freezeHit': boom(t, 1.1, 0); braam([E - 12, B - 12, E], t, 3.2, 0.2); whine(t, t + 1.8, 6800, 0.02); break;
        case 'heart': heart(t, 0.32); break;
        case 'mapOn': { const g = ctx.createGain(); g.connect(out(SFX)); env(g, t, 0.01, 0.03, 0.3, 0.3); const o = osc('sine', 300, t, t + 0.8); o.frequency.exponentialRampToValueAtTime(2400, t + 0.55); o.connect(g); whoosh(t, 0.8, 0.06, 2000, 6000, -0.5, 0.5); } break;
        case 'mark': taiko(t, 0.4, 78); beep(t, 1400, 0.03, 0.08); beep(t + 0.12, 1900, 0.025, 0.06); break;
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
