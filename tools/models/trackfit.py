# 履带轮廓（用户 11-25「坦克履带也要能动」）：原模型的履带和车身是同一块网格（贴图又不能滚动），
#   游戏里在原来的履带外面套一圈会转的履带板（客户端 Tracks.lua）。这里从原模型量出每辆履带车的履带在哪：
#   · 横向：贴地那一层（最低 0.35 格以内）的顶点 → 履带的内外边 x_in / x_out（左右对称，按右边量）
#   · 侧视轮廓：|x| 在履带宽度里的三角形按面积撒点，逐层（0.1 格）看这一层在车中段被占满多少——
#     贴地几层占满（下面一段履带），往上是负重轮（不满、或者负重轮挨得紧也满），出一次空档（< 50%），再出现的第一段占满就是上面一段履带，
#     它的上沿 = 履带最高处；挡泥板在更上面，不要
#   · 轮廓 = 履带最高处以下这些点的凸包（下段、诱导轮、主动轮、上段）；简化成二三十个点
#   python3 -I tools/models/trackfit.py tools/models models/veh <输出 lua> [核对图目录]
#   输出 src/ReplicatedStorage/TrackLoops.lua：TL[模型键] = { xi, xo, top, pts = { z1, y1, z2, y2, … } }（格，原点车底中心，−Z 朝前，同 ImportedMeta）
import json, os, sys
import numpy as np

sys.path.insert(0, sys.argv[1])
import glbio  # noqa: E402

GLB_DIR, OUT = sys.argv[2], sys.argv[3]
REVIEW = sys.argv[4] if len(sys.argv) > 4 else None
# 履带车的原模型（轮式车、牵引炮、固定阵地不要）
KEYS = ['t72b3', 't80u', 't90m', 't64', 'ztz96', 'ztz99a2', 'm1a1', 'm1a1i', 'm1a2dc', 'leo1', 'leo2a6', 'leo2a7v', 'leclerc', 'm60a3',
        'type74', 'type10', 'kitera', 'm551', 'm2a3', 'bmp1', 'bmp2', 'm109', 'pzh2000', 'm270', 'gepard', 'm163', 't625']
# 个别车自动找的上沿不对：手工给（格，离车底）
TOP_FIX = {}
# 上面一段量到了挡泥板 / 车体上（核对图里看的）：这几辆只画下面一段
NO_TOP = {'m109', 'm163', 'm60a3', 't90m', 'type74'}


def cloud(key):
    J, BIN = glbio.read_glb(os.path.join(GLB_DIR, key + '.glb'))
    ms = [m for m in glbio.meshes(J, BIN) if '__Body' in m.node or '__W' in m.node]
    if not ms:
        return None
    P = np.concatenate([m.P for m in ms])
    tris = np.concatenate([m.P[m.idx] for m in ms])
    y0 = float(P[:, 1].min())
    low = P[(P[:, 1] < y0 + 0.35) & (P[:, 0] > 0.3)]
    if len(low) < 20:
        return None
    xo, xi = float(np.percentile(low[:, 0], 99)), float(np.percentile(low[:, 0], 2))
    c = tris.mean(axis=1)
    sel = tris[(c[:, 0] > xi - 0.05) & (c[:, 0] < xo + 0.05)]
    area = 0.5 * np.linalg.norm(np.cross(sel[:, 1] - sel[:, 0], sel[:, 2] - sel[:, 0]), axis=1)
    rng = np.random.default_rng(1)
    out = []
    for t, ar in zip(sel, area):
        n = int(min(300, 2 + ar * 300))
        a = rng.random((n, 2))
        f = a.sum(1) > 1
        a[f] = 1 - a[f]
        out.append(t[0] + a[:, :1] * (t[1] - t[0]) + a[:, 1:] * (t[2] - t[0]))
    Q = np.concatenate(out)
    return Q, y0, low, xi, xo, P


def find_top(Q, y0, low):
    zc0, zc1 = float(low[:, 2].min()), float(low[:, 2].max())
    zm0, zm1 = zc0 + 0.2 * (zc1 - zc0), zc1 - 0.2 * (zc1 - zc0)
    C = Q[(Q[:, 2] > zm0) & (Q[:, 2] < zm1)]
    ncol = max(4, int((zm1 - zm0) / 0.1))
    occ = []
    for k in range(70):
        y = y0 + k * 0.1
        R = C[(C[:, 1] >= y) & (C[:, 1] < y + 0.1)]
        o = np.zeros(ncol, bool)
        if len(R):
            o[np.clip(((R[:, 2] - zm0) / 0.1).astype(int), 0, ncol - 1)] = True
        occ.append(o.mean())
    k = 0
    while k < len(occ) and occ[k] >= 0.95:   # 下面一段履带
        k += 1
    dip = False
    while k < len(occ):
        if occ[k] < 0.5:
            dip = True
        elif dip and occ[k] >= 0.95:
            break
        k += 1
    if k >= len(occ):
        return None
    while k + 1 < len(occ) and occ[k + 1] >= 0.95:
        k += 1
    return (k + 1) * 0.1


def hull(pts):
    pts = sorted(set(map(tuple, np.round(pts, 3))))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def simplify(poly, tol=0.06):
    # 去掉几乎在一条线上的点（凸包上密密的点），留二三十个
    out = list(poly)
    changed = True
    while changed and len(out) > 8:
        changed = False
        best, bi = 1e9, -1
        for i in range(len(out)):
            a, b, c = np.array(out[i - 1]), np.array(out[i]), np.array(out[(i + 1) % len(out)])
            ab, ac = b - a, c - a
            L = np.linalg.norm(ac)
            d = abs(ab[0] * ac[1] - ab[1] * ac[0]) / max(L, 1e-6)
            if d < best:
                best, bi = d, i
        if best < tol:
            out.pop(bi)
            changed = True
    return out


def simplify_open(pl, tol=0.05):
    out = list(pl)
    while len(out) > 4:
        best, bi = 1e9, -1
        for i in range(1, len(out) - 1):
            a, b, c = np.array(out[i - 1]), np.array(out[i]), np.array(out[i + 1])
            ab, ac = b - a, c - a
            L = np.linalg.norm(ac)
            d = abs(ab[0] * ac[1] - ab[1] * ac[0]) / max(L, 1e-6)
            if d < best:
                best, bi = d, i
        if best >= tol:
            break
        out.pop(bi)
    return out


res = {}
for key in KEYS:
    if not os.path.exists(os.path.join(GLB_DIR, key + '.glb')):
        continue
    cl = cloud(key)
    if not cl:
        print(key, '没有贴地的履带')
        continue
    Q, y0, low, xi, xo, P = cl
    top = TOP_FIX.get(key) or find_top(Q, y0, low)
    if not top:
        print(key, '找不到履带上沿')
        continue
    # 只量两段（用户看得到、量得准的）：
    #   下面一段：履带上沿一半高度以下的点的凸包，取它的下半条链（车头那头 → 贴地 → 车尾那头），前后弧的下半截在里面；
    #     车头车尾的斜板、挡泥板尖到不了这么低，不会被圈进来
    #   上面一段：上沿高度，前后各收到贴地那段的两头（诱导轮、主动轮上方那截常常被挡泥板挡着，量不准就不画）
    half = top * 0.45
    S = Q[Q[:, 1] <= y0 + half]
    poly = hull(np.stack([S[:, 2], S[:, 1] - y0], axis=1))
    i0 = min(range(len(poly)), key=lambda i: (poly[i][0], poly[i][1]))   # 最前（z 最小）
    i1 = max(range(len(poly)), key=lambda i: (poly[i][0], -poly[i][1]))  # 最后
    # 凸包是逆时针（z 往右、y 往上）：从最前往后走下面那半条
    chain, i = [poly[i0]], i0
    while i != i1:
        i = (i + 1) % len(poly)
        chain.append(poly[i])
    if np.mean([p[1] for p in chain]) > half * 0.6:   # 走反了（走的是上面那半条）
        chain, i = [poly[i0]], i0
        while i != i1:
            i = (i - 1) % len(poly)
            chain.append(poly[i])
    chain = simplify_open(chain)
    zc0, zc1 = float(low[:, 2].min()), float(low[:, 2].max())
    poly = chain
    res[key] = {'xi': round(xi, 3), 'xo': round(xo, 3), 'top': round(top, 2), 'z0': round(zc0, 2), 'z1': round(zc1, 2),
                'pts': [round(v, 3) for p in poly for v in p]}
    if key in NO_TOP:
        res[key]['z0'] = res[key]['z1'] = 'nil'
    print('%-8s x %.2f..%.2f  上沿 %.1f  轮廓 %d 点' % (key, xi, xo, top, len(poly)))
    if REVIEW:
        from PIL import Image, ImageDraw
        zmin, zmax = float(P[:, 2].min()), float(P[:, 2].max())
        ymax = float(P[:, 1].max())
        K = 40
        W, H = int((zmax - zmin) * K) + 8, int((ymax - y0) * K) + 8
        img = np.zeros((H, W), np.float32)
        u = ((Q[:, 2] - zmin) * K + 4).astype(int)
        v = (H - 5 - (Q[:, 1] - y0) * K).astype(int)
        ok = (u >= 0) & (u < W) & (v >= 0) & (v < H)
        np.add.at(img, (v[ok], u[ok]), 1)
        im = Image.fromarray(np.clip(img * 40, 0, 200).astype(np.uint8)).convert('RGB')
        dr = ImageDraw.Draw(im)
        pp = [((z - zmin) * K + 4, H - 5 - y * K) for z, y in poly]
        dr.line(pp, fill=(255, 80, 60), width=2)
        dr.line([((zc0 - zmin) * K + 4, H - 5 - top * K), ((zc1 - zmin) * K + 4, H - 5 - top * K)], fill=(80, 200, 255), width=2)
        os.makedirs(REVIEW, exist_ok=True)
        im.save(os.path.join(REVIEW, key + '.png'))

lines = ['-- 履带轮廓（tools/models/trackfit.py 从原模型量的，别手改）：客户端 Tracks.lua 照它套一圈会转的履带板',
         '--   TL[模型键] = { xi 履带内边, xo 外边（|x|，左右对称）, top 上面一段的高度, z0 / z1 上面一段画到哪（前、后）,',
         '--     pts = { z1, y1, z2, y2, … } 下面一段：车头那头 → 贴地 → 车尾那头的折线（格，原点车底中心，−Z 朝前） }',
         'return {']
for k in sorted(res):
    r = res[k]
    lines.append('  %s = { xi = %s, xo = %s, top = %s, z0 = %s, z1 = %s, pts = { %s } },' % (k, r['xi'], r['xo'], r['top'], r['z0'], r['z1'], ', '.join(str(v) for v in r['pts'])))
lines.append('}')
open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('写了', OUT, len(res), '辆')
