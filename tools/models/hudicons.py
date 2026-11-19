# 驾驶界面的图标（用户 11-19：「你这个像素感太强，我要 3A 级别的 UI」「给每个坦克侧面都截个图，做成全息颜色的 icon，下面显示血量，
#   全息微微带着光晕」）：
#   · 载具：tools/models/vehicons.mjs 拍的侧面明暗图（白色、透明背景）→ 裁边、去掉零碎小块、拉开明暗、勾亮轮廓、淡淡的横向扫描线、
#     一圈柔光晕 → 灰度（游戏里用 ImageColor3 染成全息青色，挨打染红）
#   · 界面图形：六边形（底、边、光晕）、炮弹、机枪弹、烟幕弹、「∧」、小炮弹——4 倍大画再缩小（边缘抗锯齿，不再是方块拼的锯齿）
#   全部压进 src/ReplicatedStorage/HudIcons.lua：每张 { w, h, f, d }，f = "la"（每像素一字节：高 4 位亮度、低 4 位不透明度）或
#   "a"（白色，每像素一字节不透明度）；d 是 base64，里面字节 0 后面跟一个字节 = 连续多少个透明像素
#   用法：python3 -I tools/models/hudicons.py <侧面图目录> <输出 HudIcons.lua>
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


def vehicle(path, box_w=236, box_h=74, pad=8):
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
    solid = Image.fromarray(((a > 0.3) * 255).astype(np.uint8), 'L').filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(13))
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


icons = {}
for f in sorted(os.listdir(SRC)):
    if f.endswith('.png'):
        w, h, d = vehicle(os.path.join(SRC, f))
        icons['veh_' + f[:-4]] = (w, h, 'la', d)
        print(f"{f[:-4]}：{w}×{h}，{len(d)} 字节")
for key, (w, h, fn, glow) in {
    'hexFill': (72, 80, hex_fill, 0), 'hexEdge': (72, 80, hex_edge, 0), 'hexGlow': (72, 80, hex_glow, 4),
    'shell': (36, 36, shell, 0), 'mg': (36, 36, mg, 0), 'chevron': (24, 16, chevron, 1.2), 'bullet': (8, 18, bullet, 0),
}.items():
    W, H, d = shape(w, h, fn, glow)
    icons[key] = (W, H, 'a', d)
w, h, d = smoke_icon()
icons['smoke'] = (w, h, 'la', d)

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
