# 把 tools/mock/loadshots.lua 写出的 3D 场景（<x>.scene.json：镜头、附近零件的形状 / 大小 / CFrame / 颜色 / 材质）画成截图背后那张 3D 图，
#   界面（hud_render.py）再压在上面——整备的 3D 挂点标签、引线在截图里才指得到飞机上真的挂点。
#   python3 -I tools/mock/scene_render.py <x>.scene.json <输出.png>      SS=2（环境变量）：按 2 倍大画（同 hud_render.py 的 SS=2 BIG=1 一起用）
#   近似（不是游戏的渲染器）：方块、楔块、圆柱、球 / 椭球拼成多边形，从远往近画（画家算法），兰伯特光 + 天光、远处起雾；
#   飞机在地上投一块柔和的影子；天是上暗下亮的灰；四角压暗一点。只为看得出标签指着哪儿、整体的气氛，不追求和游戏一模一样
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SUN = np.array([-0.45, 0.82, 0.36])
SUN = SUN / np.linalg.norm(SUN)
FOG = np.array([92.0, 96.0, 96.0])


def rot(c):
    return np.array(c[3:12], dtype=float).reshape(3, 3)


def box_faces(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    v = np.array([[-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]])
    quads = [(1, 2, 6, 5), (0, 4, 7, 3), (3, 7, 6, 2), (0, 1, 5, 4), (4, 5, 6, 7), (0, 3, 2, 1)]   # 逆时针（从外面看）：法线朝外
    return [[v[i] for i in q] for q in quads]


def wedge_faces(sx, sy, sz):
    # Roblox 楔块：底面整块、后面（+Z）整块，斜面从前下（−Z, −Y）到后上（+Z, +Y）
    x, y, z = sx / 2, sy / 2, sz / 2
    a, b, c, d = [-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z]
    e, f = [-x, y, z], [x, y, z]
    return [[np.array(p) for p in q] for q in ([a, b, c, d], [d, c, f, e], [b, a, e, f], [b, f, c], [a, d, e])]


def cyl_faces(sx, sy, sz, n=18):
    r = min(sy, sz) / 2
    h = sx / 2
    ring = [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r) for k in range(n)]
    out = []
    for k in range(n):
        y0, z0 = ring[k]
        y1, z1 = ring[(k + 1) % n]
        out.append([np.array([-h, y0, z0]), np.array([-h, y1, z1]), np.array([h, y1, z1]), np.array([h, y0, z0])])
    out.append([np.array([h, y, z]) for y, z in ring])
    out.append([np.array([-h, y, z]) for y, z in ring[::-1]])
    return out


def ell_faces(rx, ry, rz, rings=8, segs=14):
    out = []
    for i in range(rings):
        t0, t1 = math.pi * i / rings - math.pi / 2, math.pi * (i + 1) / rings - math.pi / 2
        for k in range(segs):
            p0, p1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
            def pt(t, p):
                return np.array([math.cos(t) * math.cos(p) * rx, math.sin(t) * ry, math.cos(t) * math.sin(p) * rz])
            q = [pt(t0, p0), pt(t1, p0), pt(t1, p1), pt(t0, p1)]
            out.append(q)
    return out


def faces_of(p):
    sx, sy, sz = p['z']
    k = p.get('k', 'Block')
    if p.get('mesh') == 'Sphere':
        return ell_faces(sx / 2, sy / 2, sz / 2)
    if k == 'Ball':
        r = min(sx, sy, sz) / 2
        return ell_faces(r, r, r)
    if k == 'Cylinder':
        return cyl_faces(sx, sy, sz)
    if k == 'WedgePart':
        return wedge_faces(sx, sy, sz)
    return box_faces(sx, sy, sz)


def srgb2lin(c):
    return (np.asarray(c, float) / 255.0) ** 2.2


def lin2srgb(c):
    return np.clip(np.asarray(c, float), 0, 1) ** (1 / 2.2) * 255.0


def render_vp(sc, out):
    """视口里的小场景（整备资料卡里那枚弹：loadshots.lua 写的 <名>.vp.json）：透明底、照视口自己的灯（LightDirection、Ambient、LightColor），
    不投影子、不起雾、不压暗四角；hud_render.py 用 vp:<视口名>=图 贴到视口那一块"""
    ss = int(os.environ.get('SS', '1'))
    AA = 3
    W0, H0 = int(round(sc.get('vw', 276))), int(round(sc.get('vh', 72)))
    W, H = max(2, W0 * ss * AA), max(2, H0 * ss * AA)
    cam = sc['cam']
    cpos = np.array(cam[0:3], float)
    cR = rot(cam)
    f = 1.0 / math.tan(math.radians(sc.get('fov', 20)) / 2)
    L = -np.array(sc.get('light', [-1, -1, -0.5]), float)
    L = L / max(1e-9, np.linalg.norm(L))
    amb = np.array(sc.get('amb', [90, 90, 90]), float) / 255.0
    lc = np.array(sc.get('lightC', [255, 250, 240]), float) / 255.0
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, 'RGBA')
    polys = []
    for p in sc['parts']:
        tr = float(p.get('t', 0))
        if tr >= 0.97:
            continue
        pos = np.array(p['f'][0:3], float)
        R = rot(p['f'])
        base = srgb2lin(p['c'])
        for face in faces_of(p):
            wv = [pos + R @ v for v in face]
            nrm = np.cross(wv[1] - wv[0], wv[2] - wv[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-9 and len(wv) > 3:
                nrm = np.cross(wv[2] - wv[0], wv[3] - wv[0])
                ln = np.linalg.norm(nrm)
            if ln < 1e-9:
                continue
            nrm = nrm / ln
            cen = sum(wv) / len(wv)
            if np.dot(nrm, cpos - cen) <= 0 and tr < 0.05:
                continue
            pc = [(v - cpos) @ cR for v in wv]
            if any(-q[2] < 0.05 for q in pc):
                continue
            pts = [(W / 2 + q[0] / -q[2] * f * (H / 2), H / 2 - q[1] / -q[2] * f * (H / 2)) for q in pc]
            depth = float(np.mean([-q[2] for q in pc]))
            diff = max(0.0, float(np.dot(nrm, L)))
            spec = max(0.0, float(np.dot(nrm, (L + (cpos - cen) / max(1e-9, np.linalg.norm(cpos - cen))) / 2))) ** 24 * (0.5 if p.get('m') in ('Metal', 'SmoothPlastic', 'Glass') else 0.15)
            col = base * (amb * 0.9 + lc * diff * 0.95) + spec
            c = lin2srgb(col)
            a = int(255 * (1 - tr) * (0.7 if p.get('m') == 'Glass' else 1))
            polys.append((depth, pts, (int(c[0]), int(c[1]), int(c[2]), a)))
    polys.sort(key=lambda r: -r[0])
    for _, pts, col in polys:
        draw.polygon(pts, fill=col, outline=col)
    img = img.resize((W // AA, H // AA), Image.LANCZOS)
    img.save(out)
    print('写到', out, '视口零件', len(sc['parts']), '面', len(polys))


def main():
    sc = json.load(open(sys.argv[1], encoding='utf-8'))
    out = sys.argv[2]
    if sc.get('vp'):
        render_vp(sc, out)
        return
    ss = int(os.environ.get('SS', '1'))
    AA = 2
    W0, H0 = int(sc.get('vw', 1280)), int(sc.get('vh', 720))
    W, H = W0 * ss * AA, H0 * ss * AA
    cam = sc['cam']
    cpos = np.array(cam[0:3], float)
    cR = rot(cam)
    f = 1.0 / math.tan(math.radians(sc.get('fov', 40)) / 2)
    near = 0.4
    gy = float(sc.get('gy', 0))

    def to_cam(pw):
        return (pw - cpos) @ cR   # = R^T (p - pos)

    def project(pc):
        z = -pc[2]
        return (W / 2 + pc[0] / z * f * (H / 2), H / 2 - pc[1] / z * f * (H / 2))

    def clip(poly):
        out_p = []
        n = len(poly)
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            ina, inb = a[2] <= -near, b[2] <= -near
            if ina:
                out_p.append(a)
            if ina != inb:
                t = (-near - a[2]) / (b[2] - a[2])
                out_p.append(a + (b - a) * t)
        return out_p

    # 天：上暗下亮
    img = Image.new('RGB', (W, H))
    top, hor = np.array([40.0, 44.0, 46.0]), np.array([104.0, 106.0, 102.0])
    ys = np.linspace(0, 1, H)[:, None]
    grad = top[None, :] * (1 - ys) + hor[None, :] * ys
    img = Image.fromarray(np.repeat(grad[:, None, :], W, axis=1).astype('uint8'), 'RGB')
    draw = ImageDraw.Draw(img, 'RGBA')

    polys_bg, polys_plane = [], []
    shadow = Image.new('L', (W, H), 0)
    sd = ImageDraw.Draw(shadow)
    for p in sc['parts']:
        tr = float(p.get('t', 0))
        if tr >= 0.97:
            continue
        pos = np.array(p['f'][0:3], float)
        R = rot(p['f'])
        base = srgb2lin(p['c'])
        mat = p.get('m', '')
        plane = bool(p.get('pl'))
        for face in faces_of(p):
            wv = [pos + R @ v for v in face]
            if len(wv) < 3:
                continue
            nrm = np.cross(wv[1] - wv[0], wv[2] - wv[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-9:
                if len(wv) > 3:
                    nrm = np.cross(wv[2] - wv[0], wv[3] - wv[0])
                    ln = np.linalg.norm(nrm)
                if ln < 1e-9:
                    continue
            nrm = nrm / ln
            cen = sum(wv) / len(wv)
            view = cpos - cen
            if np.dot(nrm, view) <= 0 and tr < 0.05:
                continue   # 背面
            pc = [to_cam(v) for v in wv]
            cp = clip(pc)
            if len(cp) < 3:
                continue
            pts = [project(v) for v in cp]
            depth = float(np.mean([-v[2] for v in cp]))
            dist = float(np.linalg.norm(view))
            if mat == 'Neon':
                col = base * 1.15
            else:
                diff = max(0.0, float(np.dot(nrm, SUN)))
                sky = 0.5 + 0.5 * float(nrm[1])
                k = 0.22 + 0.3 * sky + 0.78 * diff
                if mat in ('Metal', 'DiamondPlate', 'Foil'):
                    k *= 0.92
                col = base * k
            c = lin2srgb(col)
            fog = 1 - math.exp(-dist / 2600.0)
            c = c * (1 - 0.8 * fog) + FOG * 0.8 * fog
            a = int(255 * (1 - tr) * (0.55 if mat == 'Glass' else 1))
            rec = (depth, pts, (int(c[0]), int(c[1]), int(c[2]), a))
            (polys_plane if plane else polys_bg).append(rec)
            if plane and tr < 0.5:   # 影子：沿太阳的方向压到地面上
                sh = []
                for v in wv:
                    t = (v[1] - gy) / max(SUN[1], 0.2)
                    g = v - SUN * t
                    g[1] = gy
                    gc = to_cam(g)
                    if gc[2] > -near:
                        sh = None
                        break
                    sh.append(project(gc))
                if sh and len(sh) >= 3:
                    sd.polygon(sh, fill=255)
    polys_bg.sort(key=lambda r: -r[0])
    for _, pts, col in polys_bg:
        draw.polygon(pts, fill=col)
    sm = shadow.filter(ImageFilter.GaussianBlur(5 * ss * AA))
    dark = Image.new('RGB', (W, H), (10, 12, 12))
    img = Image.composite(dark, img, sm.point(lambda v: int(v * 0.55)))
    draw = ImageDraw.Draw(img, 'RGBA')
    polys_plane.sort(key=lambda r: -r[0])
    for _, pts, col in polys_plane:
        draw.polygon(pts, fill=col, outline=col)
    # 四角压暗一点
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    vig = np.clip((r - 0.65) / 0.75, 0, 1) * 0.42
    arr = np.asarray(img, float) * (1 - vig[:, :, None])
    img = Image.fromarray(arr.clip(0, 255).astype('uint8'), 'RGB')
    img = img.resize((W // AA, H // AA), Image.LANCZOS)
    img.save(out)
    print('写到', out, '零件', len(sc['parts']), '面', len(polys_bg) + len(polys_plane))


main()
