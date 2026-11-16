# 看原模型的舵面、舱门、座舱盖在哪：把网页版飞机模型（js/mdl/<键>.js）画成俯视 / 侧视 / 仰视的线框图，网格线每 1 米一条、标着坐标（网页版坐标：x 前、y 左、z 上，米）
#   用来量 tools/models/air2glb.py 里 SURF 表（舵面铰链、弹舱门、座舱盖）的范围
#   用法：python3 -I tools/models/air_view.py <网页版仓库目录> <输出目录> [模型键…]（默认全部固定翼）
import os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402

B.WEB = sys.argv[1]
OUT = sys.argv[2]
KEYS = sys.argv[3:] or ['j20', 'j31', 'j15', 'j16', 'j50', 'h6k', 'x47b', 'a10', 'f35', 'f22', 'mq9', 'b2']
FLIP = {'h6k', 'x47b'}
os.makedirs(OUT, exist_ok=True)


def model(key):
    meta, binb, _ = B.load(key)
    st = meta.get('st', 8)
    vb0, vbn = meta['vb']
    VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st).astype(np.float64)
    ib0, ibn = meta['ib']
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0).astype(np.int64)
    if key in FLIP:
        VB = VB.copy()
        VB[:, [0, 1, 3, 4]] *= -1
    tris, mats = [], []
    for mi, pi, s0, cnt in meta['lod'][0]:
        if pi >= 0 and meta['parts'][pi].get('n') in ('gear', 'rotor', 'trotor'):
            continue
        T = IB[s0:s0 + cnt].reshape(-1, 3)
        tris.append(T)
        mats += [mi] * len(T)
    return meta, VB, np.concatenate(tris), np.array(mats)


def render(key, view, scale=60):
    meta, VB, T, M = model(key)
    P = VB[:, 0:3]
    if view == 'top':      # 俯视：右边是 −y（模型右翼），上面是 +x（机头）
        U, W, D = -P[:, 1], P[:, 0], P[:, 2]
    elif view == 'bottom':  # 仰视（看机腹）：左右照俯视，深度反过来
        U, W, D = -P[:, 1], P[:, 0], -P[:, 2]
    else:                  # 侧视（右侧）：上面是 +z，右边是 +x
        U, W, D = P[:, 0], P[:, 2], -P[:, 1]
    u0, u1, w0, w1 = U.min(), U.max(), W.min(), W.max()
    pad = 1.0
    Wd, Hd = int((u1 - u0 + 2 * pad) * scale), int((w1 - w0 + 2 * pad) * scale)
    img = Image.new('RGB', (Wd, Hd), (250, 250, 250))
    dr = ImageDraw.Draw(img)
    def px(u, w): return ((u - u0 + pad) * scale, (w1 + pad - w) * scale)
    # 网格：每米一条
    for g in range(int(np.floor(u0)) - 1, int(np.ceil(u1)) + 2):
        a, _ = px(g, 0)
        dr.line([(a, 0), (a, Hd)], fill=(225, 225, 235) if g % 5 else (190, 190, 220))
        dr.text((a + 2, 2), str(g), fill=(120, 120, 160))
    for g in range(int(np.floor(w0)) - 1, int(np.ceil(w1)) + 2):
        _, b = px(0, g)
        dr.line([(0, b), (Wd, b)], fill=(225, 225, 235) if g % 5 else (190, 190, 220))
        dr.text((2, b + 2), str(g), fill=(120, 120, 160))
    # 三角形：从远到近画（简单的画家算法），按深度上灰度、按材质轻微上色；边描深色
    order = np.argsort(D[T].mean(axis=1))
    dmin, dmax = D.min(), D.max()
    for t in order:
        tri = T[t]
        pts = [px(U[i], W[i]) for i in tri]
        d = (D[tri].mean() - dmin) / max(1e-6, dmax - dmin)
        mi = M[t]
        base = np.array([(mi * 53) % 90, (mi * 97) % 90, (mi * 31) % 90])
        c = tuple(int(x) for x in (120 + d * 110 + base * 0.4).clip(0, 255))
        dr.polygon(pts, fill=c, outline=(40, 40, 40))
    names = ', '.join('%d:%s' % (i, m.get('n', '?')) for i, m in enumerate(meta['mats']))
    dr.text((6, Hd - 14), names[:300], fill=(0, 0, 0))
    img.save(os.path.join(OUT, '%s_%s.png' % (key, view)))
    return img.size


for k in KEYS:
    for v in ('top', 'side', 'bottom'):
        sz = render(k, v, 40 if k in ('b2', 'h6k') else 60)
    print(k, sz)
