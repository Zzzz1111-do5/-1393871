# 把 tools/mock/soldier.lua dump=<目录> 写出的姿势（poses.json）画成图：每个姿势画两张——右前方斜看、右侧面看；地面一条线
#   python3 -I tools/mock/pose_render.py <目录>/poses.json <输出.png>
import json, sys, math
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
poses = json.load(open(src, encoding='utf-8'))
W = H = 300
SCALE = 42.0


def norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / l for c in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


VIEWS = [norm([-4.0, -2.2, 6.0]), [-1.0, 0.0, 0.0]]   # 看的方向：右前上方往里看、右边往左看
LIGHT = norm([0.4, 1.0, 0.6])
FACES = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)), ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]


def panel(parts, d):
    img = Image.new('RGB', (W, H), (232, 236, 240))
    dr = ImageDraw.Draw(img)
    up0 = [0, 1, 0]
    r = norm(cross(up0, [-c for c in d])) if abs(d[1]) < 0.99 else [1, 0, 0]
    u = cross([-c for c in d], r)
    cx = sum(p['c'][0] for p in parts) / max(1, len(parts))
    cz = sum(p['c'][2] for p in parts) / max(1, len(parts))
    ctr = [cx, 2.3, cz]

    def proj(pt):
        q = [pt[i] - ctr[i] for i in range(3)]
        return (W / 2 + dot(q, r) * SCALE, H / 2 - dot(q, u) * SCALE), dot(q, d)
    # 地面：一圈网格线
    for i in range(-4, 5):
        a, _ = proj([cx + i, 0, cz - 4])
        b, _ = proj([cx + i, 0, cz + 4])
        dr.line([a, b], fill=(205, 210, 214))
        a, _ = proj([cx - 4, 0, cz + i])
        b, _ = proj([cx + 4, 0, cz + i])
        dr.line([a, b], fill=(205, 210, 214))
    polys = []
    for p in parts:
        x, y, z = p['c'][0:3]
        R = p['c'][3:12]
        rx, ry, rz = [R[0], R[3], R[6]], [R[1], R[4], R[7]], [R[2], R[5], R[8]]
        s = [c / 2 for c in p['s']]
        corners = []
        for ix in (-1, 1):
            for iy in (-1, 1):
                for iz in (-1, 1):
                    corners.append([(x, y, z)[k] + rx[k] * s[0] * ix + ry[k] * s[1] * iy + rz[k] * s[2] * iz for k in range(3)])
        for idx, n in FACES:
            nw = [rx[k] * n[0] + ry[k] * n[1] + rz[k] * n[2] for k in range(3)]
            if dot(nw, d) >= 0:
                continue
            pts = [proj(corners[i]) for i in idx]
            depth = sum(q[1] for q in pts) / 4
            sh = 0.45 + 0.55 * max(0.0, dot(nw, LIGHT))
            col = tuple(min(255, int(c * sh)) for c in p['rgb'])
            polys.append((depth, [q[0] for q in pts], col))
    polys.sort(key=lambda t: -t[0])
    for _, pts, col in polys:
        dr.polygon(pts, fill=col, outline=(40, 40, 40))
    return img


cols = 4
rows = math.ceil(len(poses) / cols)
sheet = Image.new('RGB', (cols * (2 * W + 10), rows * (H + 24)), (255, 255, 255))
d2 = ImageDraw.Draw(sheet)
for i, pz in enumerate(poses):
    ox, oy = (i % cols) * (2 * W + 10), (i // cols) * (H + 24)
    for j, d in enumerate(VIEWS):
        sheet.paste(panel(pz['parts'], d), (ox + j * W, oy + 22))
    d2.text((ox + 6, oy + 4), pz['name'], fill=(0, 0, 0))
sheet.save(out)
print('saved', out, sheet.size)
