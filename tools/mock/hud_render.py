# 把 tools/mock/hudshot.lua 写出的界面元素（JSON）画成 1280×720 的图，看开车时屏幕上到底有什么、叠没叠
#   python3 -I tools/mock/hud_render.py <hud.json> <输出.png> [背景图]
#   WH=1280x640（环境变量）：画面不是 1280 × 720 时（手机横屏的截图，uidump 按镜头的 ViewportSize 排的）
#   近似：方框（转角度）、圆角、描边、透明度渐变（UIGradient）、裁剪（ClipsDescendants、CanvasGroup 的圆角）、
#   CanvasGroup 的整体透明、字（文泉驿正黑，不转角度）；图片只画个框（写实车图 PicName、弹种图 AmmoPic、HudIcons 的图标照游戏的解法还原）
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


# 照 Roblox 的字体挑字（uidump 记了 Font）：英文、数字用相近的字体（Builder Sans → Inter，RobotoMono → JetBrains Mono，RobotoCondensed → Inter 横着压到 0.86），
#   中文一律退到文泉驿（同游戏：Roboto 系没有中文字形）；粗体的中文描一圈（stroke）模拟粗一档。没记字体的老 JSON 照原来的画法（全用文泉驿 + 阴影）
_LAT = {
    'mono': '/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf',
    'body': '/usr/share/fonts/opentype/inter/Inter-Medium.otf',
    'bold': '/usr/share/fonts/opentype/inter/Inter-Bold.otf',
    'title': '/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf',
    'cond': '/usr/share/fonts/opentype/inter/Inter-Regular.otf',
    'reg': '/usr/share/fonts/opentype/inter/Inter-Regular.otf',
}
_latf = {}


def lat_font(kind, sz):
    import os
    k = (kind, max(6, int(round(sz))))
    if k not in _latf:
        path = _LAT.get(kind, _LAT['reg'])
        _latf[k] = ImageFont.truetype(path, k[1]) if os.path.exists(path) else font(sz)
    return _latf[k]


def font_kind(name):
    if not name:
        return None
    if 'Mono' in name or name == 'Code':
        return 'mono'
    if 'Condensed' in name:
        return 'cond'
    if 'ExtraBold' in name or 'Black' in name or 'Heavy' in name:
        return 'title'
    if 'Bold' in name:
        return 'bold'
    if 'Medium' in name or name in ('Gotham', 'BuilderSans', 'SourceSans', 'Roboto', 'Arial', 'Legacy'):
        return 'body'
    return 'reg'


def is_cjk(ch):
    return ord(ch) >= 0x2E80


def parse_rich(t, col, sz, k):
    """RichText：<font color= size= weight= family=>、<b>：拆成一段段 (字, 颜色, 字号, 粗)；k = 渲染字号 / 原本字号"""
    import re, html
    runs, stack, pos = [], [(col, sz, False)], 0
    for m in re.finditer(r'<(/?)(\w+)([^>]*)>', t):
        if m.start() > pos:
            runs.append((html.unescape(t[pos:m.start()]),) + stack[-1])
        pos = m.end()
        closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
        if closing:
            if len(stack) > 1:
                stack.pop()
            continue
        c0, s0, b0 = stack[-1]
        if tag == 'font':
            mc = re.search(r'color\s*=\s*"#([0-9a-fA-F]{6})"', attrs)
            if mc:
                c0 = tuple(int(mc.group(1)[i:i + 2], 16) for i in (0, 2, 4))
            ms = re.search(r'size\s*=\s*"([\d.]+)"', attrs)
            if ms:
                s0 = float(ms.group(1)) * k
            if re.search(r'weight\s*=\s*"(bold|heavy|extrabold|semibold|[6-9]00)"', attrs, re.I):
                b0 = True
        elif tag == 'b':
            b0 = True
        stack.append((c0, s0, b0))
    if pos < len(t):
        runs.append((html.unescape(t[pos:]),) + stack[-1])
    return runs


def text_runs(it, ts, base_col):
    """一个字标签的字拆成能画的小段：[(字, PIL 字体, 横向压缩, 描边宽, 颜色)]"""
    kind = font_kind(it.get('font'))
    t = it.get('text') or ''
    if it.get('rich'):
        k = ts / max(1e-6, it.get('tsz') or ts)
        runs = parse_rich(t, base_col, ts, k)
    else:
        runs = [(t, base_col, ts, False)]
    out = []
    for txt, col, sz, bold in runs:
        cur, curC = '', None
        for ch in txt + '\0':
            c = is_cjk(ch) if ch != '\0' else None
            if ch == '\0' or (cur and c != curC):
                if cur:
                    if curC:
                        heavy = bold or kind in ('bold', 'title')
                        out.append((cur, font(sz), 1.0, max(1, int(sz / 22 + 0.5)) if heavy else 0, col))
                    else:
                        kk = 'bold' if bold and kind not in ('title',) else kind
                        out.append((cur, lat_font(kk, sz), 0.86 if kk == 'cond' else 1.0, 0, col))
                cur, curC = '', c
            if ch != '\0':
                cur += ch
                curC = c
    return out


def runs_width(d, runs):
    return sum(d.textlength(r[0], font=r[1]) * r[2] for r in runs)


def draw_runs(ov, runs, x, base, alpha, outline=None):
    """一段段画到 ov 上（同一条基线）：横向压缩的先画到小图上再压"""
    for txt, f, sx, stw, col in runs:
        wpx = ImageDraw.Draw(ov).textlength(txt, font=f)
        asc, desc = f.getmetrics()
        pad = 3 + stw
        im = Image.new('RGBA', (int(wpx + 2 * pad + 2), int(asc + desc + 2 * pad)), (0, 0, 0, 0))
        dd = ImageDraw.Draw(im)
        fill = tuple(int(v) for v in col) + (alpha,)
        if outline:
            dd.text((pad, pad + asc), txt, font=f, fill=outline, anchor='ls', stroke_width=max(1, stw) + 1, stroke_fill=outline)
        dd.text((pad, pad + asc), txt, font=f, fill=fill, anchor='ls', stroke_width=stw, stroke_fill=fill)
        if sx != 1.0:
            im = im.resize((max(1, int(im.width * sx)), im.height), Image.LANCZOS)
        ix, iy = int(round(x - pad * sx)), int(round(base - asc - pad))
        # 贴上去（超出画面的裁掉）
        x0, y0 = max(0, ix), max(0, iy)
        x1, y1 = min(ov.width, ix + im.width), min(ov.height, iy + im.height)
        if x1 > x0 and y1 > y0:
            ov.alpha_composite(im.crop((x0 - ix, y0 - iy, x1 - ix, y1 - iy)), (x0, y0))
        x += wpx * sx


def rgb(c):
    return tuple(int(v) for v in (c or [255, 255, 255]))


def grad_fill(size, base, g):
    """UIGradient 的颜色（乘在底色上，同 Roblox）；没给颜色就是纯底色"""
    w, h = size
    ck = g.get('ck')
    if not ck or all(tuple(c[1]) == (255, 255, 255) for c in ck):
        return Image.new('RGBA', size, tuple(base) + (255,))
    import numpy as np
    rot = math.radians(g.get('rot', 0))
    dx, dy = math.cos(rot), math.sin(rot)
    xs = (np.arange(w) / max(1, w - 1) - 0.5)[None, :]
    ys = (np.arange(h) / max(1, h - 1) - 0.5)[:, None]
    u = np.clip(xs * dx + ys * dy + 0.5, 0, 1)
    ts = [c[0] for c in sorted(ck)]
    out = np.zeros((h, w, 3))
    for ch in range(3):
        vs = [c[1][ch] for c in sorted(ck)]
        out[:, :, ch] = np.interp(u, ts, vs) * base[ch] / 255.0
    arr = np.dstack([out.astype('uint8'), np.full((h, w), 255, 'uint8')])
    return Image.fromarray(arr, 'RGBA')


def grad_mask(w, h, g):
    """UIGradient 的透明度：Rotation 0 从左到右、90 从上到下（按 Roblox 的方向），返回 0～255 的不透明度遮罩"""
    import numpy as np
    w, h = max(1, int(math.ceil(w))), max(1, int(math.ceil(h)))
    kp = sorted(g['kp'])
    rot = math.radians(g.get('rot', 0))
    dx, dy = math.cos(rot), math.sin(rot)
    xs = (np.arange(w) / max(1, w - 1) - 0.5)[None, :]
    ys = (np.arange(h) / max(1, h - 1) - 0.5)[:, None]
    u = np.clip(xs * dx + ys * dy + 0.5, 0, 1)
    t = np.interp(u, [k[0] for k in kp], [k[1] for k in kp]) if len(kp) > 1 else np.full((h, w), kp[0][1])
    return Image.fromarray((255 * (1 - t)).clip(0, 255).astype('uint8'), 'L')


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


_pics = None


def pic_img(name):
    """照 HudArt.lua picDecode 还原 src/ReplicatedStorage/VehPics.lua 的写实车图（调色板 RGBA + 透明游程）"""
    global _pics
    import base64, re, os
    if _pics is None:
        _pics = {}
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'ReplicatedStorage', 'VehPics.lua')
        if os.path.exists(p):
            txt = open(p, encoding='utf-8').read()
            m = re.search(r'w = (\d+), h = (\d+)', txt)
            _pics['_wh'] = (int(m.group(1)), int(m.group(2))) if m else (240, 120)
            for k, pal, d in re.findall(r'(\w+) = \{ p = "([^"]*)", d = "([^"]*)" \}', txt):
                _pics[k] = (pal, d)
    if name not in _pics:
        return None
    w, h = _pics['_wh']
    pal, d = _pics[name]
    pal, raw = base64.b64decode(pal), base64.b64decode(d)
    px = bytearray(w * h * 4)
    o, i = 0, 0
    while i < len(raw) and o < w * h:
        b = raw[i]
        if b == 0:
            o += raw[i + 1]; i += 2
        else:
            q = (b - 1) * 4
            px[o * 4:o * 4 + 4] = pal[q:q + 4]
            o += 1; i += 1
    return Image.frombytes('RGBA', (w, h), bytes(px))


_apics = None


def apic_img(name):
    """照 HudArt.lua picDecode 还原 src/ReplicatedStorage/AmmoPics.lua 的写实弹种图（每张自己的宽高；「#g」= 去色）"""
    global _apics
    import base64, re, os
    if _apics is None:
        _apics = {}
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'ReplicatedStorage', 'AmmoPics.lua')
        if os.path.exists(p):
            for k, w, h, pal, d in re.findall(r'(\w+) = \{ w = (\d+), h = (\d+), p = "([^"]*)", d = "([^"]*)" \}', open(p, encoding='utf-8').read()):
                _apics[k] = (int(w), int(h), pal, d)
    gray = name.endswith('#g')
    key = name[:-2] if gray else name
    if key not in _apics:
        return None
    w, h, pal, d = _apics[key]
    pal, raw = bytearray(base64.b64decode(pal)), base64.b64decode(d)
    if gray:
        for q in range(0, len(pal), 4):
            l = int(pal[q] * 0.299 + pal[q + 1] * 0.587 + pal[q + 2] * 0.114 + 0.5)
            pal[q], pal[q + 1], pal[q + 2] = l, l, l
    px = bytearray(w * h * 4)
    o, i = 0, 0
    while i < len(raw) and o < w * h:
        b = raw[i]
        if b == 0:
            o += raw[i + 1]; i += 2
        else:
            q = (b - 1) * 4
            px[o * 4:o * 4 + 4] = pal[q:q + 4]
            o += 1; i += 1
    return Image.frombytes('RGBA', (w, h), bytes(px))


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
    wh = __import__('os').environ.get('WH')
    if wh and 'x' in wh:
        W, H = (int(v) for v in wh.split('x', 1))
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
                fill = grad_fill(m.size, rgb(it['bg']), it['grad'])
                al = m.point(lambda v: int(v * (1 - bgT) * ga))
                if r > 0.5:   # 圆角：按圆角再裁一下
                    rm = Image.new('L', m.size, 0)
                    ImageDraw.Draw(rm).rounded_rectangle([0, 0, m.size[0] - 1, m.size[1] - 1], radius=min(r, w / 2, h / 2), fill=255)
                    al = ImageChops.multiply(al, rm)
                fill.putalpha(al)
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
        if it.get('vp') and VPIMG.get(it['vp']) and int(w) > 0 and int(h) > 0:   # 视口：贴上另外拍的 3D 画面（有圆角的按圆角裁）
            src = Image.open(VPIMG[it['vp']]).convert('RGBA').resize((int(round(w)), int(round(h))), Image.LANCZOS)
            if r > 0.5:
                mk = Image.new('L', src.size, 0)
                ImageDraw.Draw(mk).rounded_rectangle([0, 0, src.size[0] - 1, src.size[1] - 1], radius=min(r, src.size[0] / 2, src.size[1] / 2), fill=255)
                src.putalpha(ImageChops.multiply(src.getchannel('A'), mk))
            ov.alpha_composite(src, (int(round(x)), int(round(y))))
        pic_done = False
        if (it.get('pic') or it.get('apic')) and (it.get('iT') or 0) < 0.99 and int(w) > 0 and int(h) > 0:   # 写实车图（ScaleType Fit 按比例塞进框里）/ 弹种图（铺满）
            src = apic_img(it['apic']) if it.get('apic') else pic_img(it['pic'])
            if src is not None:
                sw, sh = src.size
                k = min(w / sw, h / sh) if it.get('fit') else None
                tw, th = (int(round(sw * k)), int(round(sh * k))) if k else (int(round(w)), int(round(h)))
                if tw > 0 and th > 0:
                    im2 = src.resize((tw, th), Image.LANCZOS)
                    tint = rgb(it.get('ic'))
                    if tint != (255, 255, 255):
                        r_, g_, b_, a_ = im2.split()
                        im2 = Image.merge('RGBA', [r_.point(lambda v, c=tint[0]: v * c // 255), g_.point(lambda v, c=tint[1]: v * c // 255),
                                                   b_.point(lambda v, c=tint[2]: v * c // 255), a_])
                    a_ = im2.split()[3].point(lambda v: int(v * (1 - (it.get('iT') or 0)) * ga))
                    g = it.get('grad')
                    if g and g.get('en', True):   # 图上的 UIGradient（同 Roblox：渐变的透明度也乘在图上；弹种图左边渐隐）
                        a_ = ImageChops.multiply(a_, grad_mask(tw, th, g))
                    im2.putalpha(a_)
                    ov.alpha_composite(im2, (int(round(x + (w - tw) / 2)), int(round(y + (h - th) / 2))))
                    pic_done = True
        if not pic_done and it.get('icon') and (it.get('iT') or 0) < 0.99:
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
        if it.get('st') and (it.get('stT') or 0) < 0.99 and it.get('text') and not it.get('stB'):
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
        if t and (it.get('tT') or 0) < 0.99 and it.get('font'):
            ts = it.get('ts') or 14
            if it.get('scaled'):
                ts = max(8, min(h * 0.8, 40))
            a = int(255 * (1 - (it.get('tT') or 0)) * ga)
            runs_all = text_runs(it, ts, rgb(it.get('tc')))
            # 按行拆（\n）
            lines, cur = [], []
            for r in runs_all:
                parts = r[0].split('\n')
                for k, part in enumerate(parts):
                    if k > 0:
                        lines.append(cur)
                        cur = []
                    if part:
                        cur.append((part,) + r[1:])
            lines.append(cur)
            lh = ts * 1.15
            # 放不下截掉（TextTruncate.AtEnd：末尾「…」）
            if it.get('trunc') and len(lines) == 1 and lines[0] and runs_width(d, lines[0]) > w + 0.5:
                ln = [list(r) for r in lines[0]]
                ell = '…'
                while ln and runs_width(d, [tuple(r) for r in ln]) + d.textlength(ell, font=font(ts)) > w:
                    ln[-1][0] = ln[-1][0][:-1]
                    if not ln[-1][0]:
                        ln.pop()
                lines = [[tuple(r) for r in ln] + [(ell, font(ts), 1.0, 0, rgb(it.get('tc')))]]
            widths = [runs_width(d, ln) for ln in lines]
            th = lh * len(lines)
            ya = it.get('ya') or ''
            ty = y if 'Top' in ya else (y + h - th if 'Bottom' in ya else y + (h - th) / 2)
            outline = None
            if (it.get('tsT') if it.get('tsT') is not None else 1) < 0.99:
                outline = (0, 0, 0, int(255 * (1 - it.get('tsT')) * ga))
            for k, ln in enumerate(lines):
                xa = it.get('xa') or ''
                tw = widths[k]
                if 'Left' in xa:
                    tx = x
                elif 'Right' in xa:
                    tx = x + w - tw
                else:
                    tx = x + (w - tw) / 2
                am, dm = font(ts).getmetrics()
                base = ty + k * lh + (lh - (am + dm)) / 2 + am
                draw_runs(ov, ln, tx, base, a, outline)
        elif t and (it.get('tT') or 0) < 0.99:
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
    if ss > 1 and __import__('os').environ.get('BIG') != '1':   # BIG=1：保留放大后的尺寸（给用户看的截图要清楚：字、线按倍数画，不是把小图放大）
        img = img.resize((W0, H0), Image.LANCZOS)
    img.convert('RGB').save(out)
    print('写到', out, '元素', len(items))


main()
