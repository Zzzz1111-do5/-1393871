# 驾驶界面的图标（用户 11-19：「你这个像素感太强，我要 3A 级别的 UI」「给每个坦克侧面都截个图，做成全息颜色的 icon，下面显示血量，
#   全息微微带着光晕」）：
#   · 载具：tools/models/vehicons.mjs 拍的侧面明暗图（白色、透明背景）→ 裁边、去掉零碎小块、拉开明暗、勾亮轮廓、淡淡的横向扫描线、
#     一圈柔光晕 → 灰度（游戏里用 ImageColor3 染成全息青色，挨打染红）
#   · 界面图形：六边形（底、边、光晕）、炮弹、机枪弹、烟幕弹、「∧」、小炮弹，视角图的俯视车体 / 炮塔（topHull / topTurret）——
#     4 倍大画再缩小（边缘抗锯齿，不再是方块拼的锯齿）
#   全部压进 src/ReplicatedStorage/HudIcons.lua：每张 { w, h, f, d }，f = "la"（每像素一字节：高 4 位亮度、低 4 位不透明度）或
#   "a"（白色，每像素一字节不透明度）；d 是 base64，里面字节 0 后面跟一个字节 = 连续多少个透明像素
#   · 开飞机的界面：每架飞机 / 直升机的侧影（vehicons.mjs SET=air 拍的 air_<型号>.png）、六边形武器键上的弹（wAam / wAgm / wRkt / wBomb / wFlare）、
#     机头指向的小飞机 / 小直升机（planeMark / heliMark）、圆形雷达里的视野扇形（viewCone）和正中间的小飞机（radarJet）、
#     机头前方的全息标记（noseJet / noseHeli：只描边、往前一根线）、热成像的扫描线和噪点（scanTex / noiseTex）、
#     全息瞄准镜式的准心（holoJetCore / holoJetGlow、holoHeliCore / holoHeliGlow：细芯 + 光晕两张叠着）、
#     发光的线（glowLine 菱形的边、glowCorner 锁定的直角、brkAlt / brkSpd 高度速度下面的折线、aimRing 准星的细圈）
#   · 舰艇：vehicons.mjs SET=ship 拍的 ship_<型号>.png（召唤界面、码位牌子上的侧影，用户 11-23）
#   用法：python3 -I tools/models/hudicons.py <侧面图目录> <输出 HudIcons.lua>（输出文件已有的图、这次目录里没有的留着）
import base64, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
SS = 4   # 界面图形超采样倍数


def rle(bytes_):
    out = bytearray()
    i, n = 0, len(bytes_)
    while i < n:
        if bytes_[i] == 0:
            j = i
            while j < n and bytes_[j] == 0 and j - i < 255:
                j += 1
            out += bytes((0, j - i))
            i = j
        else:
            out.append(bytes_[i])
            i += 1
    return bytes(out)


def pack_la(lum, alpha):
    l4 = np.clip(np.rint(lum * 15), 0, 15).astype(np.uint8)
    a4 = np.clip(np.rint(alpha * 15), 0, 15).astype(np.uint8)
    b = (l4 << 4) | a4
    b[a4 == 0] = 0
    return rle(b.reshape(-1).tobytes())


def pack_a(alpha):
    a8 = np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)
    return rle(a8.reshape(-1).tobytes())


def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im).astype(np.float64) / 255


def drop_specks(mask):
    """去掉和车身不连着的零碎小块（尾灯、烟幕弹发射器拍出来的小方点）：按 4 邻域连通，留下面积大的"""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    sizes = [0]
    cur = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not lab[y, x]:
                cur += 1
                stack = [(y, x)]
                lab[y, x] = cur
                n = 0
                while stack:
                    cy, cx = stack.pop()
                    n += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur
                            stack.append((ny, nx))
                sizes.append(n)
    big = max(sizes) if sizes else 0
    keep = np.array([s >= max(40, big * 0.004) for s in sizes])
    keep[0] = False
    return keep[lab]


def vehicle(path, box_w=236, box_h=74, pad=8, thin=(9, 13), flat=False):
    im = Image.open(path).convert('RGBA')
    arr = np.asarray(im).astype(np.float64) / 255
    a = arr[:, :, 3]
    # 先缩到一个中间大小再找连通块（原图 1800 宽，逐像素找太慢）
    small = Image.fromarray((a * 255).astype(np.uint8), 'L')
    sw = 600
    sh = max(1, round(small.height * sw / small.width))
    sm = np.asarray(small.resize((sw, sh), Image.BILINEAR)) > 20
    keep = drop_specks(sm)
    keepBig = np.asarray(Image.fromarray((keep * 255).astype(np.uint8), 'L').resize((im.width, im.height), Image.NEAREST)) > 0
    keepBig = np.asarray(Image.fromarray((keepBig * 255).astype(np.uint8), 'L').filter(ImageFilter.MaxFilter(7))) > 0
    # 细天线、拉线（几个像素宽、竖得老高）去掉：开运算（先腐蚀再膨胀）抹掉细东西，炮管这种粗的留着；不然图标按天线的高度缩，车身变小
    solid = Image.fromarray(((a > 0.3) * 255).astype(np.uint8), 'L').filter(ImageFilter.MinFilter(thin[0])).filter(ImageFilter.MaxFilter(thin[1]))
    a = a * keepBig * (np.asarray(solid) > 0)
    ys, xs = np.nonzero(a > 0.03)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgb = arr[y0:y1, x0:x1, :3]
    a = a[y0:y1, x0:x1]
    lum = (rgb[:, :, 0] * 0.3 + rgb[:, :, 1] * 0.59 + rgb[:, :, 2] * 0.11)
    # 缩到图标大小（预乘透明度再缩，边上不发黑）
    k = min(box_w / a.shape[1], box_h / a.shape[0])
    W, H = max(1, round(a.shape[1] * k)), max(1, round(a.shape[0] * k))
    pm = Image.fromarray(np.clip(lum * a * 255, 0, 255).astype(np.uint8), 'L').resize((W, H), Image.LANCZOS)
    am = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), 'L').resize((W, H), Image.LANCZOS)
    A = np.asarray(am).astype(np.float64) / 255
    L = np.where(A > 0.02, (np.asarray(pm).astype(np.float64) / 255) / np.maximum(A, 1e-3), 0)
    # 明暗拉开：车身上 5%～95% 的亮度铺满 0～1
    inside = A > 0.5
    lo, hi = np.percentile(L[inside], 5), np.percentile(L[inside], 95)
    Ln = np.clip((L - lo) / max(hi - lo, 1e-3), 0, 1)
    B = 0.58 + 0.42 * Ln
    # 勾亮：明暗的边（负重轮、炮塔棱线）和外轮廓
    gy, gx = np.gradient(Ln * A)
    edge = np.clip(np.hypot(gx, gy) * 3.2, 0, 1)
    ay, ax = np.gradient(A)
    rim = np.clip(np.hypot(ax, ay) * 2.4, 0, 1)
    B = np.clip(B + 0.28 * edge + 0.4 * rim, 0, 1)
    # 全息的横向扫描线：每三行暗一点
    rows = (np.arange(H) % 3 == 0)[:, None]
    B = np.where(rows, B * 0.9, B)
    if flat:   # 飞机（用户 11-19：照 MWT 截图——右上那张是一整块平涂的青色剪影，不带明暗、扫描线）
        B = np.ones_like(B)
    # 放进带边距的画布，加一圈柔光晕
    CW, CH = W + pad * 2, H + pad * 2
    As = np.zeros((CH, CW))
    Bs = np.zeros((CH, CW))
    As[pad:pad + H, pad:pad + W] = A * 0.96
    Bs[pad:pad + H, pad:pad + W] = B
    G = blur(As, 3.2) * 0.62 + blur(As, 7) * 0.3
    Aout = As + G * (1 - As)
    Lout = np.where(Aout > 1e-3, (Bs * As + 0.95 * G * (1 - As)) / np.maximum(Aout, 1e-3), 0)
    return CW, CH, pack_la(Lout, Aout)


# ---------------------------------------------------------------- 界面图形（白色，4 倍画再缩）
def shape(w, h, draw, glow=0):
    big = Image.new('L', (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    draw(d, SS)
    im = big.resize((w, h), Image.LANCZOS)
    a = np.asarray(im).astype(np.float64) / 255
    if glow:
        g = blur(a, glow) * 0.8
        a = a + g * (1 - a)
    return w, h, pack_a(a)


def hex_pts(cx, cy, R):
    return [(cx + R * math.cos(math.radians(90 + k * 60)), cy - R * math.sin(math.radians(90 + k * 60))) for k in range(6)]


def hex_fill(d, s):
    d.polygon(hex_pts(36 * s, 40 * s, 36 * s), fill=255)


def hex_edge(d, s):
    pts = hex_pts(36 * s, 40 * s, 34.6 * s)
    d.line(pts + [pts[0], pts[1]], fill=255, width=int(2.4 * s), joint='curve')


def hex_glow(d, s):
    pts = hex_pts(36 * s, 40 * s, 34.6 * s)
    d.line(pts + [pts[0], pts[1]], fill=255, width=int(3 * s), joint='curve')


def rot_poly(pts, cx, cy, deg):
    c, si = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [(cx + (x - cx) * c - (y - cy) * si, cy + (x - cx) * si + (y - cy) * c) for x, y in pts]


def shell(d, s):
    # 竖着画一发炮弹（弹头朝上），再转 40°：弹体、弹带、弹头（尖拱）
    cx, cy = 18 * s, 18 * s
    bw, top, bot = 5.2 * s, 10 * s, 31 * s
    body = [(cx - bw, top + 7 * s), (cx + bw, top + 7 * s), (cx + bw, bot), (cx - bw, bot)]
    tip = [(cx - bw, top + 7.5 * s)]
    for i in range(1, 12):
        t = i / 12
        tip.append((cx - bw * (1 - t * t), top + 7.5 * s - 9 * s * t))
    tip += [(cx, top - 2 * s)]
    for i in range(11, 0, -1):
        t = i / 12
        tip.append((cx + bw * (1 - t * t), top + 7.5 * s - 9 * s * t))
    tip.append((cx + bw, top + 7.5 * s))
    d.polygon(rot_poly(body, cx, cy, 40), fill=255)
    d.polygon(rot_poly(tip, cx, cy, 40), fill=255)
    band = [(cx - bw - 0.6 * s, bot - 6 * s), (cx + bw + 0.6 * s, bot - 6 * s), (cx + bw + 0.6 * s, bot - 4.2 * s), (cx - bw - 0.6 * s, bot - 4.2 * s)]
    d.polygon(rot_poly(band, cx, cy, 40), fill=0)


def mg(d, s):
    # 三颗并排的子弹
    for k in (-1, 0, 1):
        cx, cy = (18 + k * 7) * s, 18 * s
        pts = [(cx - 2.4 * s, 13 * s), (cx + 2.4 * s, 13 * s), (cx + 2.4 * s, 30 * s), (cx - 2.4 * s, 30 * s)]
        d.polygon(rot_poly(pts, 18 * s, 18 * s, 40), fill=255)
        d.ellipse([cx - 2.4 * s, 8.5 * s, cx + 2.4 * s, 17 * s], fill=255) if False else None
        tip = [(cx - 2.4 * s, 13.2 * s), (cx, 6.5 * s), (cx + 2.4 * s, 13.2 * s)]
        d.polygon(rot_poly(tip, 18 * s, 18 * s, 40), fill=255)


def chevron(d, s):
    d.line([(3 * s, 13 * s), (12 * s, 3.5 * s), (21 * s, 13 * s)], fill=255, width=int(2.6 * s), joint='curve')


def bullet(d, s):
    d.rounded_rectangle([1 * s, 5 * s, 7 * s, 17 * s], radius=1 * s, fill=255)
    d.polygon([(1 * s, 6 * s), (4 * s, 0.5 * s), (7 * s, 6 * s)], fill=255)


def smoke_icon():
    """烟幕弹：圆角罐 + 顶盖 + 拉环 + 两团烟（全息：亮的线条 + 淡的填充 + 光晕）"""
    w, h = 56, 64
    big = Image.new('L', (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    s = SS
    d.rounded_rectangle([16 * s, 22 * s, 36 * s, 56 * s], radius=4 * s, outline=255, width=int(2.4 * s), fill=70)
    d.rectangle([20 * s, 17 * s, 32 * s, 22 * s], fill=255)
    d.arc([26 * s, 9 * s, 38 * s, 21 * s], 180, 360, fill=255, width=int(2 * s))
    d.rectangle([20 * s, 32 * s, 32 * s, 44 * s], fill=170)
    for cx, cy, r in ((42, 14, 6), (48, 8, 4.5)):
        d.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], outline=255, width=int(1.8 * s))
    A = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    B = np.where(A > 0, 1.0, 0)
    G = blur(A, 3) * 0.6
    Aout = A + G * (1 - A)
    Lout = np.where(Aout > 1e-3, (B * A + 0.9 * G * (1 - A)) / np.maximum(Aout, 1e-3), 0)
    return w, h, pack_la(Lout, Aout)


TOP_W, TOP_H = 72, 120   # 视角图（用户 11-19：屏幕下面中心带光晕的视角图；坦克宽一点、履带不要显示）：车体、炮塔两张同样大，炮塔座圈都在正中间
TOP_HULL = (36, 22, 24, 114)   # 车体在图里：中线 x、半宽、前、后（界面上按这个把爆反块摆到车体轮廓上）


def holo(big, fill_big, w, h, glow=3.2):
    """全息：亮的线条（big）+ 淡淡的填充（fill_big）+ 一圈柔光晕 → (亮度, 不透明度)"""
    A = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    F = np.asarray(fill_big.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    G = blur(A, glow) * 0.75
    base = np.maximum(A, F * 0.22)
    Aout = base + G * (1 - base)
    Lout = np.where(Aout > 1e-3, (A * 1.0 + F * 0.22 * 0.75 * (1 - A) + 0.95 * G * (1 - base)) / np.maximum(Aout, 1e-3), 0)
    return np.clip(Lout, 0, 1), np.clip(Aout, 0, 1)


def top_hull():
    """俯视的车体（车头朝上）：只有一圈边框（四个直角），里面镂空、不涂色（用户 11-19：不要涂色，就边框、炮塔边框、炮管，剩下都是镂空）"""
    w, h, s = TOP_W, TOP_H, SS
    big = Image.new('L', (w * s, h * s), 0)
    fill = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(big)
    cx, hw, L0, L1 = TOP_HULL
    body = [(cx - hw, L0), (cx + hw, L0), (cx + hw, L1), (cx - hw, L1)]
    d.line([(x * s, y * s) for x, y in body + body[:2]], fill=255, width=int(1.8 * s))
    Lout, Aout = holo(big, fill, w, h)
    return w, h, pack_la(Lout, Aout)


def top_turret():
    """俯视的炮塔连炮管（炮口朝上）：炮塔一圈边框（楔形的前装甲、尾舱）、一根炮管、圆形舱盖、后面左右两个「=」，别的镂空；座圈在图正中间"""
    w, h, s = TOP_W, TOP_H, SS
    big = Image.new('L', (w * s, h * s), 0)
    fill = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(big)
    cx, cy = w / 2, h / 2
    P = [(-10, -15), (-18, -6), (-18, 11), (-13, 19), (13, 19), (18, 11), (18, -6), (10, -15)]
    tur = [(cx + x, cy + y) for x, y in P]
    d.line([(x * s, y * s) for x, y in tur + tur[:2]], fill=255, width=int(1.8 * s), joint='curve')
    d.line([cx * s, 3 * s, cx * s, (cy - 15) * s], fill=255, width=int(2.2 * s))   # 炮管
    # 用户 11-19：圆形舱盖加上，左后、右后各一个「=」（不然炮塔后半截有点空）
    d.ellipse([(cx - 4.5) * s, (cy + 1.5) * s, (cx + 4.5) * s, (cy + 10.5) * s], outline=255, width=int(1.5 * s))
    for sx in (-1, 1):
        x0 = cx + sx * 11.5
        for dy in (-1.8, 1.8):
            d.line([(x0 - 3.5) * s, (cy + 12 + dy) * s, (x0 + 3.5) * s, (cy + 12 + dy) * s], fill=255, width=int(1.4 * s))
    Lout, Aout = holo(big, fill, w, h, glow=2.6)
    return w, h, pack_la(Lout, Aout)



# ---------------------------------------------------------------- 开飞机的界面（用户 11-19：飞机操作界面也照 MWT 的截图改——照布局和感觉，图自己画）
#   六边形武器键上的弹：空空弹、空地弹、火箭弹、炸弹、热诱弹（航炮用上面的 mg）；都是竖着画（弹头朝上）再转 40°，跟炮弹一个方向
def _missile(d, s, cx, top, bot, r, nose, fins):
    """竖着的一枚弹：弹体（半径 r）、尖拱弹头（长 nose）、fins = [(上沿 y, 下沿 y, 伸出多宽, 后掠)]"""
    pts = [(cx - r, top + nose)]
    for i in range(1, 12):
        t = i / 12
        pts.append((cx - r * (1 - t * t), top + nose - nose * t))
    pts.append((cx, top))
    for i in range(11, 0, -1):
        t = i / 12
        pts.append((cx + r * (1 - t * t), top + nose - nose * t))
    pts += [(cx + r, top + nose), (cx + r, bot), (cx - r, bot)]
    out = [rot_poly([(x * s, y * s) for x, y in pts], 20 * s, 20 * s, 40)]
    for y0, y1, wd, sw in fins:
        for sx in (-1, 1):
            f = [(cx + sx * r, y0), (cx + sx * (r + wd), y0 + sw), (cx + sx * (r + wd), y1), (cx + sx * r, y1)]
            out.append(rot_poly([(x * s, y * s) for x, y in f], 20 * s, 20 * s, 40))
    for poly in out:
        d.polygon(poly, fill=255)


def w_aam(d, s):
    _missile(d, s, 20, 3, 36, 1.9, 6.5, [(11, 14.5, 2.6, 1.6), (29, 36, 4.4, 4.2)])


def w_agm(d, s):
    _missile(d, s, 20, 4, 35, 2.9, 4.2, [(15, 25, 4.6, 5.5), (30.5, 35, 3.2, 2.4)])


def w_rkt(d, s):
    for k, dy in ((-1, 4), (0, 0), (1, 4)):   # 三枚火箭弹并排，中间那枚靠前
        _missile(d, s, 20 + k * 6.4, 5 + dy, 34 + dy * 0.3, 1.9, 4.5, [(29 + dy * 0.3, 34 + dy * 0.3, 1.6, 2)])


def w_bomb(d, s):
    cx = 20
    body = []
    for i in range(0, 25):   # 弹体：前圆后收的流线形
        t = i / 24
        y = 5 + 25 * t
        r = 5.6 * math.sin(math.pi * (0.12 + 0.82 * t)) ** 0.7
        body.append((cx + r, y))
    body += [(cx + 1.6, 32.5), (cx - 1.6, 32.5)]
    body += [(2 * cx - x, y) for x, y in reversed(body[:25])]
    d.polygon(rot_poly([(x * s, y * s) for x, y in body], 20 * s, 20 * s, 40), fill=255)
    for sx in (-1, 1):   # 箱形尾翼（侧面看见两片）
        f = [(cx + sx * 1.4, 29), (cx + sx * 5.6, 31), (cx + sx * 5.6, 37), (cx + sx * 1.4, 36)]
        d.polygon(rot_poly([(x * s, y * s) for x, y in f], 20 * s, 20 * s, 40), fill=255)
    f = [(cx - 5.6, 36.2), (cx + 5.6, 36.2), (cx + 5.6, 37.6), (cx - 5.6, 37.6)]
    d.polygon(rot_poly([(x * s, y * s) for x, y in f], 20 * s, 20 * s, 40), fill=255)


def w_flare(d, s):
    def star(cx, cy, R, r, rot=0):
        pts = []
        for k in range(8):
            a = math.radians(rot + k * 45)
            rr = R if k % 2 == 0 else r
            pts.append(((cx + math.sin(a) * rr) * s, (cy - math.cos(a) * rr) * s))
        d.polygon(pts, fill=255)
    star(17, 22, 14, 2.6)
    star(31, 9, 6, 1.4)
    d.ellipse([29 * s, 30 * s, 33 * s, 34 * s], fill=255)


def _mark_fill(big, fill, w, h, glow):
    """亮边 + 光晕（holo）盖在一层浓一点的填充上（MWT 那种实心一点的小飞机）"""
    L, A = holo(big, fill, w, h, glow=glow)
    F = np.asarray(fill.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    Af, Lf = F * 0.5, 0.8
    Aout = A + Af * (1 - A)
    Lout = np.where(Aout > 1e-3, (L * A + Lf * Af * (1 - A)) / np.maximum(Aout, 1e-3), 0)
    return np.clip(Lout, 0, 1), np.clip(Aout, 0, 1)


def plane_mark():
    """机头指向（平显中间那个青色小飞机，机头朝上）：俯视的战斗机——淡淡的填充 + 亮边 + 光晕"""
    w, h, s = 52, 52, SS
    big = Image.new('L', (w * s, h * s), 0)
    fill = Image.new('L', (w * s, h * s), 0)
    d, df = ImageDraw.Draw(big), ImageDraw.Draw(fill)
    cx = w / 2
    half = [(0, 4), (1.6, 7), (2.7, 12), (3.2, 18), (19.5, 30.5), (19.5, 33.5), (4.2, 32), (4.0, 36.5), (11, 42.5), (11, 45), (3.4, 44.5), (2.2, 47)]
    pts = [(cx + x, y) for x, y in half] + [(cx - x, y) for x, y in reversed(half)]
    big_pts = [(x * s, y * s) for x, y in pts]
    df.polygon(big_pts, fill=255)
    d.line(big_pts + big_pts[:2], fill=255, width=int(1.7 * s), joint='curve')
    d.line([cx * s, 9 * s, cx * s, 14 * s], fill=255, width=int(1.4 * s))   # 座舱
    return w, h, pack_la(*_mark_fill(big, fill, w, h, 2.4))


def heli_mark():
    """直升机的机头指向：俯视的机身、尾梁、平尾，外面一圈淡淡的旋翼盘"""
    w, h, s = 52, 52, SS
    big = Image.new('L', (w * s, h * s), 0)
    fill = Image.new('L', (w * s, h * s), 0)
    d, df = ImageDraw.Draw(big), ImageDraw.Draw(fill)
    cx = w / 2
    half = [(0, 7), (3, 9), (4.6, 14), (4.6, 24), (3.2, 30), (1.3, 32), (1.3, 42), (6, 42), (6, 44.5), (1.3, 44.5), (1.1, 48)]
    pts = [(cx + x, y) for x, y in half] + [(cx - x, y) for x, y in reversed(half)]
    big_pts = [(x * s, y * s) for x, y in pts]
    df.polygon(big_pts, fill=255)
    d.line(big_pts + big_pts[:2], fill=255, width=int(1.6 * s), joint='curve')
    R = 19   # 旋翼盘：一圈淡淡的细线（不画桨叶——圆圈里打叉像禁止标志）
    d.ellipse([(cx - R) * s, (19 - R) * s, (cx + R) * s, (19 + R) * s], outline=120, width=int(1.0 * s))
    return w, h, pack_la(*_mark_fill(big, fill, w, h, 2.2))


def view_cone():
    """左上圆形雷达里的视野扇形（镜头看的方向，±35°）：顶点在图正中间、朝上，越往外越淡，两条边亮一点"""
    w = h = 160
    s = SS
    big = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(big)
    c, R, half = w / 2, w / 2, 35
    d.pieslice([(c - R) * s, (c - R) * s, (c + R) * s, (c + R) * s], -90 - half, -90 + half, fill=255)
    a = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx + 0.5 - c, yy + 0.5 - c) / R
    alpha = a * (0.5 - 0.3 * np.clip(r, 0, 1))
    edge = Image.new('L', (w * s, h * s), 0)
    de = ImageDraw.Draw(edge)
    for sg in (-1, 1):
        ang = math.radians(-90 + sg * half)
        de.line([c * s, c * s, (c + math.cos(ang) * R) * s, (c + math.sin(ang) * R) * s], fill=255, width=int(1.2 * s))
    e = np.asarray(edge.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255 * (1 - 0.6 * np.clip(r, 0, 1))
    mid = Image.new('L', (w * s, h * s), 0)   # 中间一根细线：机头朝哪
    ImageDraw.Draw(mid).line([c * s, c * s, c * s, 0], fill=255, width=int(0.9 * s))
    m = np.asarray(mid.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    return w, h, pack_a(np.clip(np.maximum(np.maximum(alpha, e * 0.8), m * 0.85), 0, 1))


# ---------------------------------------------------------------- 机头的全息标记（用户 11-19：MWT 那个像全息投屏一样、机头指哪它在哪的标记）
#   只有描边的俯视小飞机（不涂色），机头往前伸出一根细线、线头一个亮点；游戏里贴在机头前方的一块斜放的面上（跟着机身转），所以看着有透视
def _nose_line(d, s, cx, y_nose):
    d.line([cx * s, y_nose * s, cx * s, 11 * s], fill=255, width=int(1.5 * s))
    d.ellipse([(cx - 2.6) * s, (7.4 - 2.6) * s, (cx + 2.6) * s, (7.4 + 2.6) * s], fill=255)


def nose_jet():
    w, h, s = 64, 96, SS
    big = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(big)
    cx, y0, k = w / 2, 40, 1.15
    half = [(0, 4), (1.6, 7), (2.7, 12), (3.2, 18), (19.5, 30.5), (19.5, 33.5), (4.2, 32), (4.0, 36.5), (11, 42.5), (11, 45), (3.4, 44.5), (2.2, 47)]
    pts = [(cx + x * k, y0 + y * k) for x, y in half] + [(cx - x * k, y0 + y * k) for x, y in reversed(half)]
    bp = [(x * s, y * s) for x, y in pts]
    d.line(bp + bp[:2], fill=255, width=int(1.7 * s), joint='curve')
    _nose_line(d, s, cx, y0 + 4 * k)
    L, A = holo(big, Image.new('L', (w * s, h * s), 0), w, h, glow=2.8)
    return w, h, pack_la(L, A)


def nose_heli():
    w, h, s = 64, 96, SS
    big = Image.new('L', (w * s, h * s), 0)
    d = ImageDraw.Draw(big)
    cx, y0 = w / 2, 38
    half = [(0, 7), (3.4, 9), (5.2, 15), (5.2, 26), (3.6, 33), (1.5, 36), (1.5, 48), (7, 48), (7, 51), (1.5, 51), (1.3, 55)]
    pts = [(cx + x, y0 + y) for x, y in half] + [(cx - x, y0 + y) for x, y in reversed(half)]
    bp = [(x * s, y * s) for x, y in pts]
    d.line(bp + bp[:2], fill=255, width=int(1.6 * s), joint='curve')
    R = 20
    d.ellipse([(cx - R) * s, (y0 + 19 - R) * s, (cx + R) * s, (y0 + 19 + R) * s], outline=110, width=int(1.0 * s))
    _nose_line(d, s, cx, y0 + 7)
    L, A = holo(big, Image.new('L', (w * s, h * s), 0), w, h, glow=2.6)
    return w, h, pack_la(L, A)


def radar_jet(d, s):
    """圆形雷达正中间自己那架：一个白色的实心小飞机（机头朝上）"""
    cx = 11
    half = [(0, 1), (1.2, 4), (1.6, 8), (9.5, 14), (9.5, 15.5), (1.8, 14.5), (1.6, 17), (5, 19.5), (5, 20.6), (0.9, 20.4)]
    pts = [(cx + x, y) for x, y in half] + [(cx - x, y) for x, y in reversed(half)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=255)


# ---------------------------------------------------------------- 热成像（用户 11-19：不进光电吊舱也能开红外视角）：横向扫描线、雪花噪点（平铺在全屏上）
def scan_tex():
    a = np.zeros((4, 4))
    a[2, :], a[3, :] = 0.45, 0.2
    return 4, 4, pack_a(a)


def noise_tex():
    rng = np.random.default_rng(11)
    w = h = 128
    a = np.zeros((h, w))
    n = int(w * h * 0.012)
    ys, xs = rng.integers(0, h, n), rng.integers(0, w, n)
    a[ys, xs] = rng.uniform(0.45, 1.0, n)
    xs2 = np.clip(xs + 1, 0, w - 1)   # 一部分是横着两个像素的小划痕
    pick = rng.random(n) < 0.35
    a[ys[pick], xs2[pick]] = a[ys[pick], xs[pick]] * 0.7
    return w, h, pack_a(a)


# ---------------------------------------------------------------- 全息瞄准镜那种发光的线（用户 11-19：机头的标记要像全息瞄准镜的准心——细、亮、带柔光，
#   不要一段段线拼起来的、不要太大太粗）：整张图一笔画出来（4 倍大画再缩，抗锯齿），分两层——
#   芯（很细、游戏里染成近白的青）和光晕（芯往外模糊开、染成青色、淡）；界面上两张叠着放
def _line_layers(draw, w, h, core, glow_r):
    big = Image.new('L', (w * SS, h * SS), 0)
    draw(ImageDraw.Draw(big), SS, max(1, int(round(core * SS))))
    A = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float64) / 255
    G = np.clip(blur(A, glow_r * 0.4) * 0.6 + blur(A, glow_r) * 0.45, 0, 1)
    return A, np.maximum(G, A * 0.9)


def _jet_outline(d, s, lw, cx, y0, k):
    half = [(0, 4), (1.6, 7), (2.7, 12), (3.2, 18), (19.5, 30.5), (19.5, 33.5), (4.2, 32), (4.0, 36.5), (11, 42.5), (11, 45), (3.4, 44.5), (2.2, 47)]
    pts = [(cx + x * k, y0 + y * k) for x, y in half] + [(cx - x * k, y0 + y * k) for x, y in reversed(half)]
    bp = [(x * s, y * s) for x, y in pts]
    d.line(bp + bp[:2], fill=255, width=lw, joint='curve')
    nose = y0 + 4 * k
    d.line([cx * s, nose * s, cx * s, 52 * s], fill=255, width=lw)   # 机头往前一根线（机身长的四成）
    r = 3.0
    d.ellipse([(cx - r) * s, (46 - r) * s, (cx + r) * s, (46 + r) * s], fill=255)   # 线头一个亮点


def _heli_outline(d, s, lw, cx, y0, k):
    half = [(0, 7), (3.4, 9), (5.2, 15), (5.2, 26), (3.6, 33), (1.5, 36), (1.5, 48), (7, 48), (7, 51), (1.5, 51), (1.3, 55)]
    pts = [(cx + x * k, y0 + y * k) for x, y in half] + [(cx - x * k, y0 + y * k) for x, y in reversed(half)]
    bp = [(x * s, y * s) for x, y in pts]
    d.line(bp + bp[:2], fill=255, width=lw, joint='curve')
    R = 20 * k
    cy = y0 + 19 * k
    d.arc([(cx - R) * s, (cy - R) * s, (cx + R) * s, (cy + R) * s], 0, 360, fill=255, width=max(1, lw // 2))
    nose = y0 + 7 * k
    d.line([cx * s, nose * s, cx * s, 52 * s], fill=255, width=lw)
    r = 3.0
    d.ellipse([(cx - r) * s, (46 - r) * s, (cx + r) * s, (46 + r) * s], fill=255)


def holo_reticle(kind):
    """机头的全息准心（128 × 192，机头朝上）：芯 + 光晕两张"""
    w, h = 128, 192
    if kind == 'jet':
        A, G = _line_layers(lambda d, s, lw: _jet_outline(d, s, lw, w / 2, 84, 2.2), w, h, 2.2, 5)
    else:
        A, G = _line_layers(lambda d, s, lw: _heli_outline(d, s, lw, w / 2, 76, 2.0), w, h, 2.2, 5)
    return (w, h, pack_a(A)), (w, h, pack_a(G))


def glow_line():
    """一段发光的横线（64 × 16，中间两像素的芯 + 上下柔光，两头圆）：拉长了当菱形的边"""
    w, h = 64, 16
    def dr(d, s, lw):
        d.line([4 * s, 8 * s, 60 * s, 8 * s], fill=255, width=lw)
    A, G = _line_layers(dr, w, h, 1.8, 2.6)
    return w, h, pack_la(np.where(G > 1e-3, (A + 0.85 * G * (1 - A)) / np.maximum(np.maximum(A, G), 1e-3), 0), np.maximum(A, G))


def glow_corner():
    """锁定的直角（32 × 32，左上那个；别的三个转 90° / 180° / 270°）"""
    w, h = 32, 32
    def dr(d, s, lw):
        d.line([(6 * s, 27 * s), (6 * s, 6 * s), (27 * s, 6 * s)], fill=255, width=lw, joint='curve')
    A, G = _line_layers(dr, w, h, 1.8, 2.4)
    return w, h, pack_la(np.where(G > 1e-3, (A + 0.85 * G * (1 - A)) / np.maximum(np.maximum(A, G), 1e-3), 0), np.maximum(A, G))


def glow_bracket(step_left):
    """高度 / 速度下面那道带台阶的折线（112 × 36）：高度（准星左边）低 → 台阶往上 → 高；速度（右边）高 → 台阶往下 → 低"""
    w, h = 112, 36
    def dr(d, s, lw):
        if step_left:
            pts = [(4, 22), (32, 22), (41, 13), (108, 13)]
        else:
            pts = [(4, 13), (71, 13), (80, 22), (108, 22)]
        d.line([(x * s, y * s) for x, y in pts], fill=255, width=lw, joint='curve')
    A, G = _line_layers(dr, w, h, 1.6, 2.4)
    return w, h, pack_la(np.where(G > 1e-3, (A + 0.85 * G * (1 - A)) / np.maximum(np.maximum(A, G), 1e-3), 0), np.maximum(A, G))


def aim_ring():
    """准星：一个细圈（48 × 48）"""
    w, h = 48, 48
    def dr(d, s, lw):
        r = 15
        d.ellipse([(24 - r) * s, (24 - r) * s, (24 + r) * s, (24 + r) * s], outline=255, width=lw)
    A, G = _line_layers(dr, w, h, 1.6, 2.2)
    return w, h, pack_la(np.where(G > 1e-3, (A + 0.85 * G * (1 - A)) / np.maximum(np.maximum(A, G), 1e-3), 0), np.maximum(A, G))

icons = {}
# 增量：OUT 里已经有的图、这次没重新生成的原样留着（只拍了飞机就只换飞机的；载具侧面图不用每次全拍）
if os.path.exists(OUT):
    import re
    for ln in open(OUT, encoding='utf-8'):
        m = re.match(r'  (\w+) = \{ w = (\d+), h = (\d+), f = "(\w+)", d = "([^"]*)" \},$', ln.rstrip('\n'))
        if m:
            icons[m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4), base64.b64decode(m.group(5)))
for f in sorted(os.listdir(SRC)):
    if f.endswith('.png'):
        air = f.startswith('air_')   # 飞机、直升机的侧影：扁一点，细的旋翼、垂尾留着
        ship = f.startswith('ship_')   # 舰艇（用户 11-23：召唤界面名字下面带图标）：明暗同地面载具，船身细长、高度框小一点
        w, h, d = vehicle(os.path.join(SRC, f), box_h=70 if air else (60 if ship else 74), thin=(5, 7) if air else (9, 13), flat=air)
        icons[f[:-4] if (air or ship) else 'veh_' + f[:-4]] = (w, h, 'la', d)
        print(f"{f[:-4]}：{w}×{h}，{len(d)} 字节")
for key, (w, h, fn, glow) in {
    'hexFill': (72, 80, hex_fill, 0), 'hexEdge': (72, 80, hex_edge, 0), 'hexGlow': (72, 80, hex_glow, 4),
    'shell': (36, 36, shell, 0), 'mg': (36, 36, mg, 0), 'chevron': (24, 16, chevron, 1.2), 'bullet': (8, 18, bullet, 0),
    'wAam': (40, 40, w_aam, 0), 'wAgm': (40, 40, w_agm, 0), 'wRkt': (40, 40, w_rkt, 0), 'wBomb': (40, 40, w_bomb, 0), 'wFlare': (40, 40, w_flare, 0),
    'radarJet': (22, 22, radar_jet, 0.8),
}.items():
    W, H, d = shape(w, h, fn, glow)
    icons[key] = (W, H, 'a', d)
w, h, d = smoke_icon()
icons['smoke'] = (w, h, 'la', d)
for key, fn in (('topHull', top_hull), ('topTurret', top_turret), ('planeMark', plane_mark), ('heliMark', heli_mark), ('noseJet', nose_jet), ('noseHeli', nose_heli)):
    w, h, d = fn()
    icons[key] = (w, h, 'la', d)

w, h, d = view_cone()
icons['viewCone'] = (w, h, 'a', d)
for key, fn in (('scanTex', scan_tex), ('noiseTex', noise_tex)):
    w, h, d = fn()
    icons[key] = (w, h, 'a', d)
for kind in ('jet', 'heli'):   # 机头的全息准心：芯 + 光晕
    (w, h, dc), (_, _, dg) = holo_reticle(kind)
    key = 'holo' + kind.capitalize()
    icons[key + 'Core'] = (w, h, 'a', dc)
    icons[key + 'Glow'] = (w, h, 'a', dg)
for key, fn in (('glowLine', glow_line), ('glowCorner', glow_corner), ('aimRing', aim_ring),
                ('brkAlt', lambda: glow_bracket(True)), ('brkSpd', lambda: glow_bracket(False))):
    w, h, d = fn()
    icons[key] = (w, h, 'la', d)

lines = ['-- 自动生成（tools/models/hudicons.py），别手改：驾驶界面的图标——每辆地面载具的侧面全息图标（原模型正侧面拍的，灰度、带柔光晕，',
         '--   游戏里用 ImageColor3 染成全息青色）和界面图形（六边形、炮弹、机枪弹、烟幕弹、「∧」、小炮弹，4 倍超采样画的，边缘不起锯齿）',
         '--   icons[名字] = { w, h, f, d }：f = "la" 每像素一字节（高 4 位亮度、低 4 位不透明度）、"a" 白色每像素一字节不透明度；',
         '--   d 是 base64，字节 0 后面跟一个字节 = 连续多少个透明像素。载具的名字是 "veh_" .. VehDefs 的车型',
         'return {']
total = 0
for k in sorted(icons):
    w, h, fmt, d = icons[k]
    b = base64.b64encode(d).decode()
    total += len(b)
    lines.append(f'  {k} = {{ w = {w}, h = {h}, f = "{fmt}", d = "{b}" }},')
lines.append('}')
with open(OUT, 'w', encoding='utf-8', newline='\n') as fo:
    fo.write('\n'.join(lines) + '\n')
print(f'写好了 {OUT}：{len(icons)} 张，base64 一共 {total // 1024} KB')
