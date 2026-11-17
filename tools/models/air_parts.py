# 检查 tools/models/air_anim.py 切出来的活动部件：按部件上色画俯视 / 仰视 / 侧视，铰链画成红线；舵面按 ±25° 偏过去再画一张（看转得对不对）
#   用法：python3 -I tools/models/air_parts.py <网页版仓库目录> <输出目录> [模型键…]
import os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
import air2glb as G   # noqa: E402
import air_anim as A   # noqa: E402

B.WEB = sys.argv[1]
OUT = sys.argv[2]
KEYS = sys.argv[3:] or sorted(A.SURF)
os.makedirs(OUT, exist_ok=True)
COL = [(230, 80, 60), (60, 160, 230), (240, 200, 40), (120, 200, 90), (200, 90, 220), (250, 140, 40), (40, 200, 190), (160, 120, 80),
       (255, 120, 170), (120, 120, 255), (190, 230, 70), (90, 90, 90)]


def deflect(PT, g, surf, k=1.0):
    """每个三角形各用各的顶点（同导出：每块各有一份顶点），活动部件按铰链转过去（舵面 25°、舱门 / 座舱盖 / 起落架开到 A）"""
    PT = PT.copy()
    for nm, e in surf.items():
        sel = np.where(g == nm)[0]
        if e['k'] == 'gdoor':
            continue
        th = e['sg'] * (e.get('A', 0.44) if e['k'] in ('bay', 'bayS', 'canopy', 'gear') else 0.44) * k
        for t in sel:
            for j in range(3):
                PT[t, j] = A.rot(PT[t, j], e['a'], e['b'] - e['a'], th)
    return PT


def render(key, PT, g, surf, view, tag, scale=50):
    """PT：每个三角形的三个顶点 (n, 3, 3)"""
    P = PT.reshape(-1, 3)
    T = np.arange(len(P)).reshape(-1, 3)
    if view == 'top':
        U, W, D = -P[:, 1], P[:, 0], P[:, 2]
    elif view == 'bottom':
        U, W, D = -P[:, 1], P[:, 0], -P[:, 2]
    else:
        U, W, D = P[:, 0], P[:, 2], -P[:, 1]
    u0, u1, w0, w1 = U.min(), U.max(), W.min(), W.max()
    pad = 0.6
    Wd, Hd = int((u1 - u0 + 2 * pad) * scale), int((w1 - w0 + 2 * pad) * scale)
    img = Image.new('RGB', (Wd, Hd), (250, 250, 250))
    dr = ImageDraw.Draw(img)

    def px(u, w): return ((u - u0 + pad) * scale, (w1 + pad - w) * scale)
    for gg in range(int(np.floor(u0)) - 1, int(np.ceil(u1)) + 2):
        a, _ = px(gg, 0)
        dr.line([(a, 0), (a, Hd)], fill=(228, 228, 236))
        dr.text((a + 2, 2), str(gg), fill=(130, 130, 160))
    for gg in range(int(np.floor(w0)) - 1, int(np.ceil(w1)) + 2):
        _, b = px(0, gg)
        dr.line([(0, b), (Wd, b)], fill=(228, 228, 236))
        dr.text((2, b + 2), str(gg), fill=(130, 130, 160))
    names = sorted(set(g.tolist()) - {'Body'})
    cmap = {n: COL[i % len(COL)] for i, n in enumerate(names)}
    order = np.argsort(D[T].mean(axis=1))
    dmin, dmax = D.min(), D.max()
    for t in order:
        tri = T[t]
        d = (D[tri].mean() - dmin) / max(1e-6, dmax - dmin)
        base = np.array(cmap.get(g[t], (150, 150, 150)), dtype=float)
        c = tuple(int(x) for x in (base * (0.55 + 0.45 * d)).clip(0, 255))
        dr.polygon([px(U[i], W[i]) for i in tri], fill=c, outline=tuple(int(x * 0.6) for x in c))
    for nm, e in surf.items():
        a, b = e['a'], e['b']
        ua, wa = (-a[1], a[0]) if view in ('top', 'bottom') else (a[0], a[2])
        ub, wb = (-b[1], b[0]) if view in ('top', 'bottom') else (b[0], b[2])
        dr.line([px(ua, wa), px(ub, wb)], fill=(220, 0, 0), width=2)
    y = Hd - 14 * (len(names) + 1)
    for n in names:
        dr.rectangle([6, y, 16, y + 10], fill=cmap[n])
        dr.text((20, y), '%s %s' % (n, surf.get(n, {}).get('k', '')), fill=(0, 0, 0))
        y += 14
    img.save(os.path.join(OUT, '%s_%s%s.png' % (key, view, tag)))


for key in KEYS:
    meta, binb, credit, VB, T, g, m, rot_piv, surf = G.segment(key)
    keep = ~np.isin(g, ['Rotor', 'Rotor2', 'TRotor', 'Drop'])
    T, g = T[keep], g[keep]
    PT = VB[T, 0:3]
    sc = 30 if key in ('b2', 'h6k') else 50
    for v in ('top', 'bottom', 'side'):
        render(key, PT, g, surf, v, '', sc)
    PD = deflect(PT, g, surf)
    for v in ('top', 'side', 'bottom'):
        render(key, PD, g, surf, v, '_d', sc)
    print(key, ' '.join('%s:%s%+d' % (n, e['k'], e['sg']) for n, e in sorted(surf.items())))
