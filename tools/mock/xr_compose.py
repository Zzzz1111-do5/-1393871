# X 光命中回放截图拼起来：hud_render.py 画的整屏界面 + vp_render.py 画的 3D（贴进 ViewportFrame「View」的框），再裁出回放窗口
#   python3 -I tools/mock/xr_compose.py <界面 json> <界面 png> <3D png> <输出 png> [SS]
#   SS 同 hud_render.py 的放大倍数（界面 png 是 1280×720 × SS）
import json, sys
from PIL import Image

UJ, UPNG, VPNG, OUT = sys.argv[1:5]
SS = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
items = json.load(open(UJ, encoding='utf-8'))
view = panel = None
for it in items:
    if it.get('name') == 'View' and str(it.get('gui', '')).split('#')[0] == 'WtHud':
        view = it
    if it.get('name') == 'WtXray':
        panel = it
if not view:
    raise SystemExit('界面里没有 WtHud 的 View')
base = Image.open(UPNG).convert('RGBA')
x, y, w, h = [int(round(view[k] * SS)) for k in ('x', 'y', 'w', 'h')]
bgc = tuple(int(round(c)) for c in (view.get('bg') or (14, 22, 30)))
bgt = float(view.get('bgT') or 0)
vimg = Image.open(VPNG).convert('RGBA').resize((w, h), Image.LANCZOS)
under = base.crop((x, y, x + w, y + h))
bgl = Image.new('RGBA', (w, h), bgc[:3] + (int(round(255 * (1 - bgt))),))
under = Image.alpha_composite(under, bgl)
base.paste(Image.alpha_composite(under, vimg), (x, y))
if panel:
    m = int(8 * SS)
    px, py, pw, ph = [int(round(panel[k] * SS)) for k in ('x', 'y', 'w', 'h')]
    base = base.crop((max(0, px - m), max(0, py - m), min(base.width, px + pw + m), min(base.height, py + ph + m)))
base.convert('RGB').save(OUT)
print('拼好了', OUT, base.size)
