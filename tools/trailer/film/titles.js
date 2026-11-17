// 字幕、片名卡：画在输出画布上（宽银幕画面里或黑边上）
import { clamp, smooth, ease } from './lib.js';

export class Titles {
  constructor(W, H, ah) { this.W = W; this.H = H; this.ah = ah; this.bar = (H - ah) / 2; }
  // items：[{ text, x, y（0–1，相对整个画面）, size（相对画面高）, font, a 透明度, color, spacing, align, glow }]
  draw(g, items) {
    if (!items) return;
    for (const it of items) {
      if (!it || (it.a ?? 1) <= 0.002) continue;
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
// 淡入淡出（秒）
export const fadeIO = (t, a, b, fin = 0.5, fout = 0.5) => smooth(a, a + fin, t) * (1 - smooth(b - fout, b, t));
