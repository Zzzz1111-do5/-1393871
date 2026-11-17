// 字幕、片名卡：画在输出画布上（宽银幕画面里或黑边上）
import { clamp, smooth, ease } from './lib.js';

export class Titles {
  constructor(W, H, ah) { this.W = W; this.H = H; this.ah = ah; this.bar = (H - ah) / 2; }
  // items：[{ text, x, y（0–1，相对整个画面）, size（相对画面高）, font, a 透明度, color, spacing, align, glow }]
  draw(g, items) {
    if (!items) return;
    for (const it of items) {
      if (!it || (it.a ?? 1) <= 0.002) continue;
      if (it.box) { this.lockBox(g, it); continue; }
      const px = it.size * this.H;
      g.save();
      g.globalAlpha = clamp(it.a ?? 1, 0, 1);
      g.font = `${it.weight || 400} ${px}px ${it.font || '"Noto Serif SC"'}`;
      g.textAlign = it.align || 'center';
      g.textBaseline = 'middle';
      g.fillStyle = it.color || '#e8e4dc';
      if ('letterSpacing' in g) g.letterSpacing = `${(it.spacing || 0) * px}px`;
      if (it.glow) { g.shadowColor = it.glow; g.shadowBlur = px * 0.6; }
      g.fillText(it.text, it.x * this.W, it.y * this.H);
      if (it.rule) {   // 字下面一道细线
        g.shadowBlur = 0;
        const w = it.rule * this.W;
        const y = it.y * this.H + px * 0.85;
        const grd = g.createLinearGradient(it.x * this.W - w / 2, 0, it.x * this.W + w / 2, 0);
        grd.addColorStop(0, 'rgba(232,228,220,0)'); grd.addColorStop(0.5, it.color || '#e8e4dc'); grd.addColorStop(1, 'rgba(232,228,220,0)');
        g.fillStyle = grd; g.fillRect(it.x * this.W - w / 2, y, w, Math.max(1, px * 0.04));
      }
      g.restore();
    }
  }
}
// 平显式的锁定框：四个角的折线，中间一个小菱形，上面标签、下面一行小字（x、y、w、h 都是 0–1，相对整个画面）
Titles.prototype.lockBox = function (g, it) {
  const W = this.W, H = this.H;
  const [x, y, w, h] = it.box, cx = x * W, cy = y * H, hw = w * W / 2, hh = h * H / 2, L = Math.min(hw, hh) * 0.45;
  g.save();
  g.globalAlpha = clamp(it.a ?? 1, 0, 1);
  g.strokeStyle = it.color || '#7dff9a';
  g.lineWidth = Math.max(1.5, H * 0.0022);
  g.shadowColor = it.color || '#7dff9a'; g.shadowBlur = H * 0.008;
  g.beginPath();
  for (const [sx, sy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
    const px = cx + sx * hw, py = cy + sy * hh;
    g.moveTo(px - sx * L, py); g.lineTo(px, py); g.lineTo(px, py - sy * L);
  }
  if (it.diamond) { const d = Math.min(hw, hh) * 0.18; g.moveTo(cx, cy - d); g.lineTo(cx + d, cy); g.lineTo(cx, cy + d); g.lineTo(cx - d, cy); g.closePath(); }
  g.stroke();
  g.shadowBlur = 0;
  g.fillStyle = it.color || '#7dff9a';
  g.textAlign = 'center';
  if (it.label) { g.font = `700 ${H * 0.022}px "Noto Sans SC"`; g.textBaseline = 'bottom'; g.fillText(it.label, cx, cy - hh - H * 0.008); }
  if (it.sub) { g.font = `400 ${H * 0.016}px "Noto Sans SC"`; g.textBaseline = 'top'; g.fillText(it.sub, cx, cy + hh + H * 0.008); }
  g.restore();
};
// 淡入淡出（秒）
export const fadeIO = (t, a, b, fin = 0.5, fout = 0.5) => smooth(a, a + fin, t) * (1 - smooth(b - fout, b, t));
