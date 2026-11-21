# 把 tools/mock/hudshot.lua 写出的界面元素（JSON）画成 1280×720 的图，看开车时屏幕上到底有什么、叠没叠
#   python3 -I tools/mock/hud_render.py <hud.json> <输出.png> [背景图]
#   近似：方框（转角度）、圆角、描边、透明度渐变（UIGradient）、裁剪（ClipsDescendants、CanvasGroup 的圆角）、
#   CanvasGroup 的整体透明、字（文泉驿正黑，不转角度）；图片只画个框
import json, math, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops

FONT = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
W, H = 1280, 720
_fonts = {}


def font(sz):
    k = max(6, int(round(sz)))
    if k not in _fonts:
        _fonts[k] = ImageFont.truetype(FONT, k)
    return _fonts[k]


def rgb(c):
    return tuple(int(v) for v in (c or [255, 255, 255]))


def grad_mask(w, h, g):
    """UIGradient 的透明度：Rotation 0 从左到右、90 从上到下（按 Roblox 的方向），返回 0～255 的不透明度遮罩"""
    w, h = max(1, int(math.ceil(w))), max(1, int(math.ceil(h)))
    kp = sorted(g['kp'])
    rot = math.radians(g.get('rot', 0))
    dx, dy = math.cos(rot), math.sin(rot)
    m = Image.new('L', (w, h))
    px = m.load()
    for y in range(h):
        for x in range(w):
            u = ((x / max(1, w - 1) - 0.5) * dx + (y / max(1, h - 1) - 0.5) * dy) + 0.5
            u = min(1, max(0, u))
            t = kp[-1][1]
            for i in range(len(kp) - 1):
                if kp[i][0] <= u <= kp[i + 1][0]:
                    a = (u - kp[i][0]) / max(1e-6, kp[i + 1][0] - kp[i][0])
                    t = kp[i][1] + (kp[i + 1][1] - kp[i][1]) * a
                    break
            px[x, y] = int(255 * (1 - t))
    return m


_icons = None


def icon_img(name):
    """照游戏里的解码方式还原 src/ReplicatedStorage/HudIcons.lua 的图（灰度 + 不透明度）"""
    global _icons
    import base64, re, os
    if _icons is None:
        _icons = {}
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'ReplicatedStorage', 'HudIcons.lua')
        if os.path.exists(p):
            for k, w, h, f, d in re.findall(r'  (\w+) = \{ w = (\d+), h = (\d+), f = "(\w+)", d = "([^"]*)" \}', open(p, encoding='utf-8').read()):
                _icons[k] = (int(w), int(h), f, d)
    if name not in _icons:
        return None
    w, h, f, d = _icons[name]
    raw = base64.b64decode(d)
    px = bytearray(w * h * 2)
    o, i = 0, 0
    while i < len(raw):
        b = raw[i]
        if b == 0:
            o += raw[i + 1]; i += 2
        else:
            l, a = ((b >> 4) * 17, (b & 15) * 17) if f == 'la' else (255, b)
            px[o * 2], px[o * 2 + 1] = l, a
            o += 1; i += 1
    return Image.frombytes('LA', (w, h), bytes(px))


VPIMG = {}   # 视口名 → 图片（命令行 vp:名字=图片.png）
def quad_layer(it):
    """机头的全息标记：3D 的一块面（hudshot 导出了四个角在屏幕上的位置）——图按透视贴到这四个角上"""
    src = icon_img(it.get('icon'))
    if src is None:
        return None
    import numpy as np
    sw, sh = src.size
    L, A = src.split()
    tint = rgb(it.get('ic'))
    rgbI = Image.merge('RGB', [L.point(lambda v, c=c: v * c // 255) for c in tint])
    rgbI.putalpha(A.point(lambda v: int(v * (1 - (it.get('iT') or 0)))))
    M, B = [], []
    for (x, y), (u, v) in zip([tuple(p) for p in it['quad']], [(0, 0), (sw, 0), (sw, sh), (0, sh)]):
        M.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        B.append(u)
        M.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        B.append(v)
    coef = np.linalg.solve(np.array(M, float), np.array(B, float))
    return rgbI.transform((W, H), Image.PERSPECTIVE, tuple(coef), Image.BILINEAR)


def main():
    for a in sys.argv[4:]:
        if a.startswith('vp:') and '=' in a:
            k, v = a[3:].split('=', 1)
            VPIMG[k] = v
    items = json.load(open(sys.argv[1], encoding='utf-8'))
    # SS=2（环境变量）：按 2 倍大画再缩回来，圆、描边有抗锯齿（Roblox 画的界面本来就是抗锯齿的；不然一圈挨一圈的描边之间露出漏缝）
    global W, H
    ss = int(__import__('os').environ.get('SS', '1'))
    W0, H0 = W, H
    if ss > 1:
        W, H = W * ss, H * ss
        for it in items:
            for k in ('x', 'y', 'w', 'h', 'corner', 'stW', 'ts'):
                if isinstance(it.get(k), (int, float)):
                    it[k] = it[k] * ss
            if it.get('clip'):
                c = it['clip']
                it['clip'] = [v * ss for v in c[:4]] + ([c[4] * ss] if len(c) > 4 else [])
            if it.get('quad'):
                it['quad'] = [[q[0] * ss, q[1] * ss] for q in it['quad']]
    out = sys.argv[2]
    if len(sys.argv) > 3 and sys.argv[3] != '-':
        bg = Image.open(sys.argv[3]).convert('RGBA').resize((W, H))
    else:
        bg = Image.new('RGBA', (W, H), (34, 40, 46, 255))
        d0 = ImageDraw.Draw(bg)
        for y in range(H):   # 夜里的天和地：上暗下亮一点
            c = int(40 + 30 * y / H)
            d0.line([(0, y), (W, y)], fill=(c, c + 6, c + 12, 255))
    items = [dict(it, _i=i) for i, it in enumerate(items)]
    items.sort(key=lambda it: (it.get('order', 0), it['_i']))
    img = bg
    for it in items:
        if it.get('quad'):
            lay = quad_layer(it)
            if lay is not None:
                img = Image.alpha_composite(img, lay)
            continue
        x, y, w, h = it['x'], it['y'], it['w'], it['h']
        if w <= 0 or h <= 0 or x > W or y > H or x + w < 0 or y + h < 0:
            continue
        ga = it.get('ga', 1) or 1
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        box = [x, y, x + w, y + h]
        r = it.get('corner') or 0
        rot = it.get('rot') or 0
        bgT = it.get('bgT', 1)
        if it.get('bg') and bgT is not None and bgT < 0.999:
            a = int(255 * (1 - bgT) * ga)
            col = rgb(it['bg']) + (a,)
            if it.get('grad'):
                m = grad_mask(w, h, it['grad'])
                fill = Image.new('RGBA', m.size, rgb(it['bg']) + (0,))
                fill.putalpha(m.point(lambda v: int(v * (1 - bgT) * ga)))
                ov.alpha_composite(fill, (int(x), int(y)))
            elif abs(rot) > 0.5 and r <= 0.5:
                cx, cy = x + w / 2, y + h / 2
                ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
                pts = [(cx + px * ca - py * sa, cy + px * sa + py * ca) for px, py in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]
                d.polygon(pts, fill=col)
            elif r > 0.5:
                d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), fill=col)
            else:
                d.rectangle(box, fill=col)
        if it.get('vp') and VPIMG.get(it['vp']) and int(w) > 0 and int(h) > 0:   # 视口：贴上另外拍的 3D 画面
            src = Image.open(VPIMG[it['vp']]).convert('RGBA').resize((int(round(w)), int(round(h))), Image.LANCZOS)
            ov.alpha_composite(src, (int(round(x)), int(round(y))))
        if it.get('icon') and (it.get('iT') or 0) < 0.99:
            src = icon_img(it['icon'])
            if src is not None and int(w) > 0 and int(h) > 0:
                src = src.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)
                L, A = src.split()
                tint = rgb(it.get('ic'))
                rgbI = Image.merge('RGB', [L.point(lambda v, c=c: v * c // 255) for c in tint])
                A = A.point(lambda v: int(v * (1 - (it.get('iT') or 0)) * ga))
                rgbI.putalpha(A)
                if abs(rot) > 0.5:   # Roblox 的 Rotation 顺时针、绕自己的中心转
                    cx, cy = x + w / 2, y + h / 2
                    rgbI = rgbI.rotate(-rot, resample=Image.BICUBIC, expand=True)
                    ov.alpha_composite(rgbI, (int(round(cx - rgbI.width / 2)), int(round(cy - rgbI.height / 2))))
                else:
                    ov.alpha_composite(rgbI, (int(round(x)), int(round(y))))
        elif it.get('img') and (it.get('iT') or 0) < 0.99:
            a = int(160 * (1 - (it.get('iT') or 0)) * ga)
            d.rectangle(box, outline=rgb(it.get('ic')) + (a,), width=1)
        textGlow = None
        if it.get('st') and (it.get('stT') or 0) < 0.99 and it.get('text'):
            # 字上的 UIStroke 在游戏里是贴着字形描一圈（这里当光晕画在字后面），不是方框
            textGlow = (rgb(it['st']), int(255 * (1 - (it.get('stT') or 0)) * ga), max(1, int(round(it.get('stW') or 1))))
        elif it.get('st') and (it.get('stT') or 0) < 0.99:
            # Roblox 的 UIStroke（Border）往外描：框往外扩一个描边宽，圆角跟着加大
            a = int(255 * (1 - (it.get('stT') or 0)) * ga)
            sw = max(1, int(round(it.get('stW') or 1)))
            ob = [x - sw, y - sw, x + w + sw, y + h + sw]
            ow, oh = w + 2 * sw, h + 2 * sw
            sl = Image.new('RGBA', (W, H), (0, 0, 0, 0)) if it.get('stGrad') else None
            dd = ImageDraw.Draw(sl) if sl is not None else d
            if ob[2] - ob[0] > 0 and ob[3] - ob[1] > 0:
                if r > 0.5:
                    dd.rounded_rectangle(ob, radius=min(r + sw, ow / 2, oh / 2), outline=rgb(it['st']) + (a,), width=sw)
                else:
                    dd.rectangle(ob, outline=rgb(it['st']) + (a,), width=sw)
            if sl is not None:   # 描边上的 UIGradient：按描边外框铺透明度渐变
                m = grad_mask(ow, oh, it['stGrad'])
                full = Image.new('L', (W, H), 0)
                full.paste(m, (int(round(ob[0])), int(round(ob[1]))))
                sl.putalpha(ImageChops.multiply(sl.getchannel('A'), full))
                ov.alpha_composite(sl)
        t = it.get('text')
        if t and (it.get('tT') or 0) < 0.99:
            ts = it.get('ts') or 14
            if it.get('scaled'):
                ts = max(8, min(h * 0.8, 40))
            f = font(ts)
            a = int(255 * (1 - (it.get('tT') or 0)) * ga)
            tc = rgb(it.get('tc')) + (a,)
            import re
            t = re.sub(r'<[^>]+>', '', t)   # RichText：去掉标签只画字
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
            if textGlow:
                gl = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                gd = ImageDraw.Draw(gl)
                for k, ln in enumerate(lines):
                    gd.text((tx, ty + k * lh), ln, font=f, fill=textGlow[0] + (textGlow[1],), stroke_width=textGlow[2], stroke_fill=textGlow[0] + (textGlow[1],))
                from PIL import ImageFilter
                ov.alpha_composite(gl.filter(ImageFilter.GaussianBlur(1.2)))
            for k, ln in enumerate(lines):
                d.text((tx + 1, ty + k * lh + 1), ln, font=f, fill=(0, 0, 0, int(a * 0.5)))
                d.text((tx, ty + k * lh), ln, font=f, fill=tc)
        clip = it.get('clip')
        if clip:
            m = Image.new('L', (W, H), 0)
            md = ImageDraw.Draw(m)
            cx0, cy0, cx1, cy1, cr = clip[0], clip[1], clip[2], clip[3], (clip[4] if len(clip) > 4 else 0)
            if cx1 > cx0 and cy1 > cy0:
                if cr and cr > 0.5:
                    md.rounded_rectangle([cx0, cy0, cx1, cy1], radius=min(cr, (cx1 - cx0) / 2, (cy1 - cy0) / 2), fill=255)
                else:
                    md.rectangle([cx0, cy0, cx1, cy1], fill=255)
            al = ov.getchannel('A')
            ov.putalpha(ImageChops.multiply(al, m))
        img = Image.alpha_composite(img, ov)
    if ss > 1:
        img = img.resize((W0, H0), Image.LANCZOS)
    img.convert('RGB').save(out)
    print('写到', out, '元素', len(items))


main()
