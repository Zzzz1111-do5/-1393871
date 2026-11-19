# 把 tools/mock/hudshot.lua 写出的界面元素（JSON）画成 1280×720 的图，看开车时屏幕上到底有什么、叠没叠
#   python3 -I tools/mock/hud_render.py <hud.json> <输出.png> [背景图]
#   近似：方框、圆角、描边、字（文泉驿正黑）；不画图片（ImageLabel 只画个框）、不转角度
import json, sys
from PIL import Image, ImageDraw, ImageFont

FONT = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
W, H = 1280, 720


def font(sz):
    return ImageFont.truetype(FONT, max(6, int(round(sz))))


def main():
    items = json.load(open(sys.argv[1], encoding='utf-8'))
    out = sys.argv[2]
    if len(sys.argv) > 3:
        bg = Image.open(sys.argv[3]).convert('RGBA').resize((W, H))
    else:
        bg = Image.new('RGBA', (W, H), (34, 40, 46, 255))
        d0 = ImageDraw.Draw(bg)
        for y in range(H):   # 夜里的天和地：上暗下亮一点
            c = int(26 + 22 * y / H)
            d0.line([(0, y), (W, y)], fill=(c, c + 4, c + 10, 255))
    # 按 ScreenGui 的显示顺序、再按树里的顺序（深度优先，JSON 本来就是这个顺序）、ZIndex 画
    items = [dict(it, _i=i) for i, it in enumerate(items)]
    items.sort(key=lambda it: (it.get('order', 0), it['_i']))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for it in items:
        x, y, w, h = it['x'], it['y'], it['w'], it['h']
        if w <= 0 or h <= 0 or x > W or y > H or x + w < 0 or y + h < 0:
            continue
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        box = [x, y, x + w, y + h]
        r = it.get('corner') or 0
        bgT = it.get('bgT', 1)
        if it.get('bg') and bgT is not None and bgT < 0.999:
            a = int(255 * (1 - bgT))
            col = tuple(int(c) for c in it['bg']) + (a,)
            if r > 0.5:
                d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), fill=col)
            else:
                d.rectangle(box, fill=col)
        if it.get('img') and (it.get('iT') or 0) < 0.99:
            a = int(160 * (1 - (it.get('iT') or 0)))
            ic = tuple(int(c) for c in (it.get('ic') or [255, 255, 255]))
            d.rectangle(box, outline=ic + (a,), width=1)
        if it.get('st') and (it.get('stT') or 0) < 0.99:
            a = int(255 * (1 - (it.get('stT') or 0)))
            sw = max(1, int(round(it.get('stW') or 1)))
            if r > 0.5:
                d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), outline=tuple(int(c) for c in it['st']) + (a,), width=sw)
            else:
                d.rectangle(box, outline=tuple(int(c) for c in it['st']) + (a,), width=sw)
        t = it.get('text')
        if t and (it.get('tT') or 0) < 0.99:
            ts = it.get('ts') or 14
            if it.get('scaled'):
                ts = max(8, min(h * 0.8, 40))
            f = font(ts)
            a = int(255 * (1 - (it.get('tT') or 0)))
            tc = tuple(int(c) for c in (it.get('tc') or [255, 255, 255])) + (a,)
            lines = t.split('\n')
            lh = ts * 1.15
            tw = max(d.textlength(ln, font=f) for ln in lines)
            th = lh * len(lines)
            xa = it.get('xa') or ''
            if 'Left' in xa:
                tx = x
            elif 'Right' in xa:
                tx = x + w - tw
            else:
                tx = x + (w - tw) / 2
            ty = y + (h - th) / 2
            for k, ln in enumerate(lines):
                d.text((tx, ty + k * lh), ln, font=f, fill=tc)
        layer = Image.alpha_composite(layer, ov)
    img = Image.alpha_composite(bg, layer)
    img.convert('RGB').save(out)
    print('写到', out, '元素', len(items))


main()
