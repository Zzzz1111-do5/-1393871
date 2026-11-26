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
        'type74', 'type10', 'kitera', 'm551', 'm2a3', 'bmp1', 'bmp2', 'm109', 'pzh2000', 'm270', 'gepard', 'm163', 't625', 'type59']
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


#   —— 11-26（用户「履带 bug 是坦克同时有两副履带，一副会动」）：大多数原模型的履带是单独的块（有的还拆成履带板、销、诱导齿几块），
#   套上去的履带板只是叠在它外面，板与板之间、拐角处露出底下那副不动的——看着就是两副。认出这些块（游戏里套上履带板时把它们藏起来），
#   整圈按它们侧视的外轮廓量（不是凸包：T-72 / T-90 这种没有托带轮的，上面一段压在负重轮顶上一起一伏）
#   认履带块：贴地（最低 < 0.4 格）、和履带差不多长（≥ 75%）、九成顶点在履带宽度里、
#     侧视绝大多数顶点贴着自己的凸包边（≥ 60%：一圈），凸包里面大半是空的（覆盖 ≤ 60%：负重轮、侧裙板这种实心的不算）；
#   还要分「纯履带」和「履带里还带着别的」：自己侧视填满后往里缩 1 格的那片，纯履带是空的（量过的 20 来块全是 0%；
#     履带板本身连诱导齿侧视有 0.6 格厚，缩得少了会误伤），勒克莱尔的块带着六个负重轮的胎圈（99%）、10 式的带着侧裙板（22%）——
#     这种不能藏（藏了负重轮少一圈、侧裙板没了），只能盖住
def belt_parts(J, BIN, xi, xo, tlen):
    from scipy.spatial import ConvexHull
    out = []
    for m in glbio.meshes(J, BIN):
        P = m.P[np.unique(m.idx.reshape(-1))]
        if len(P) < 40:
            continue
        ax = np.abs(P[:, 0])
        if ((ax > xi - 0.25) & (ax < xo + 0.25)).mean() < 0.9 or np.ptp(P[:, 2]) < 0.75 * tlen or P[:, 1].min() > 0.4:
            continue
        Q = P[:, [2, 1]]
        try:
            hl = ConvexHull(Q)
        except Exception:
            continue
        H = Q[hl.vertices]
        d = np.full(len(Q), np.inf)
        for i in range(len(H)):
            a, b = H[i], H[(i + 1) % len(H)]
            t = np.clip(((Q - a) @ (b - a)) / max(((b - a) ** 2).sum(), 1e-12), 0, 1)
            d = np.minimum(d, np.linalg.norm(Q - (a + t[:, None] * (b - a)), axis=1))
        ring = (d < 0.5).mean()
        cov = raster(m.P[m.idx][:, :, [2, 1]], Q.min(0), Q.max(0), 0.15, edges=False)
        g0 = Q.min(0)
        ii, jj = np.nonzero(np.ones_like(cov))
        cells = np.c_[ii * 0.15 + g0[0] + 0.075, jj * 0.15 + g0[1] + 0.075]
        inh = (cells @ hl.equations[:, :2].T + hl.equations[:, 2] <= 1e-9).all(1)
        fill = cov.ravel()[inh].mean() if inh.any() else 1
        if ring >= 0.6 and fill <= 0.6:
            out.append((glbio.part_name(m.node), m, inner_cov(m.P[m.idx][:, :, [2, 1]]) <= 0.03))
    return out


def inner_cov(TT, g=0.05, depth=1.0):
    """侧视：块自己填满后往里缩 depth 格的那片，被它自己占了多少（纯履带一圈 ≈ 0）"""
    from scipy import ndimage
    lo = TT.reshape(-1, 2).min(0) - 4 * g
    hi = TT.reshape(-1, 2).max(0) + 4 * g
    cov = raster(TT, lo, hi, g)
    st = np.ones((3, 3), bool)
    sol = ndimage.binary_fill_holes(ndimage.binary_dilation(cov, st, iterations=3))
    k = int(round(depth / g))
    yy, xx = np.mgrid[-k:k + 1, -k:k + 1]
    core = ndimage.binary_erosion(sol, xx * xx + yy * yy <= k * k)
    return float(cov[core].mean()) if core.any() else 0.0


def raster(TT, lo, hi, g, edges=True):
    """侧视（z, y）三角形栅格化：格子 g；edges 连边一起画（侧着看是一条线的面也算上）"""
    nz, ny = int((hi[0] - lo[0]) / g) + 3, int((hi[1] - lo[1]) / g) + 3
    cov = np.zeros((nz, ny), bool)
    for tri in TT:
        a, b, c = tri
        mn, mx = np.floor((tri.min(0) - lo) / g).astype(int), np.ceil((tri.max(0) - lo) / g).astype(int)
        mn, mx = np.maximum(mn, 0), np.minimum(mx, [nz - 1, ny - 1])
        if (mx - mn).prod() > 20000:
            continue
        zz, yy = np.meshgrid(np.arange(mn[0], mx[0] + 1), np.arange(mn[1], mx[1] + 1), indexing='ij')
        pts = np.c_[zz.ravel() * g + lo[0] + g / 2, yy.ravel() * g + lo[1] + g / 2]
        v0, v1 = b - a, c - a
        den = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(den) > 1e-12:
            w = pts - a
            u = (w[:, 0] * v1[1] - w[:, 1] * v1[0]) / den
            v = (v0[0] * w[:, 1] - v0[1] * w[:, 0]) / den
            k = (u >= -0.02) & (v >= -0.02) & (u + v <= 1.02)
            cov[zz.ravel()[k], yy.ravel()[k]] = True
        if edges:
            for p, q in ((a, b), (b, c), (c, a)):
                n = int(np.linalg.norm(q - p) / (g * 0.5)) + 2
                s = p + np.linspace(0, 1, n)[:, None] * (q - p)
                ij = np.floor((s - lo) / g).astype(int)
                ok = (ij[:, 0] >= 0) & (ij[:, 0] < nz) & (ij[:, 1] >= 0) & (ij[:, 1] < ny)
                cov[ij[ok, 0], ij[ok, 1]] = True
    return cov


def envelope(TT, g=0.04):
    """履带块侧视的外轮廓：栅格化 → 膨胀两格连上块之间的缝 → 填洞 → 腐蚀回来 → 沿外边描一圈 → 化简。
    返回逆时针（z 往右、y 往上）的闭合折线，从最前面那一点开始"""
    from scipy import ndimage
    lo = TT.reshape(-1, 2).min(0) - 4 * g
    hi = TT.reshape(-1, 2).max(0) + 4 * g
    cov = raster(TT, lo, hi, g)
    st = np.ones((3, 3), bool)
    # 膨胀 5 格（0.2 格）把块和块之间、履带板之间的缝连上（M60A3 的履带板是一块块分开的），填洞，再腐蚀回来
    sol = ndimage.binary_fill_holes(ndimage.binary_dilation(cov, st, iterations=5))
    sol = ndimage.binary_erosion(sol, st, iterations=5)
    # 开运算（圆盘半径 5 格 = 0.2 格）：磨掉 0.4 格以内的尖刺、凸起（主动轮齿尖、履带板上的齿、诱导齿），不然板走过去一上一下跳、
    #   拐角处挤成一团；主动轮、诱导轮那种半径一格以上的圆弧、上面一段压在负重轮上的起伏不受影响
    r = 5
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    sol = ndimage.binary_opening(sol, xx * xx + yy * yy <= r * r)
    lab, n = ndimage.label(sol)
    if n > 1:   # 只要最大的那一片
        sz = ndimage.sum(sol, lab, range(1, n + 1))
        sol = lab == (1 + int(np.argmax(sz)))
    # 还是没连成一整片（填出来比凸包小得多）：退回凸包
    from scipy.spatial import ConvexHull
    pts = TT.reshape(-1, 2)
    hl = ConvexHull(pts)
    if sol.sum() * g * g < 0.75 * hl.volume:
        H = pts[hl.vertices]
        area = 0.5 * np.sum(H[:, 0] * np.roll(H[:, 1], -1) - np.roll(H[:, 0], -1) * H[:, 1])
        if area < 0:
            H = H[::-1]
        H = dp_closed(H, 0.06)
        k = int(np.argmin(H[:, 0] + 1e-3 * H[:, 1]))
        return np.roll(H, -k, axis=0)
    # Moore 邻域描边（格子坐标 i = z、j = y）：从最下面一行最左边的格子出发，沿外边逆时针走一圈
    nz, ny = sol.shape
    js = np.nonzero(sol.any(0))[0].min()
    i0 = np.nonzero(sol[:, js])[0].min()
    nb = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]   # 逆时针排的 8 个方向（z 往右、y 往上）

    def on(i, j):
        return 0 <= i < nz and 0 <= j < ny and sol[i, j]
    path = [(i0, js)]
    cur, back = (i0, js), 6   # 从下面（j−1，一定是空的）开始找
    for _ in range(nz * ny):
        found = False
        for k in range(1, 9):
            d = (back + k) % 8
            ni, nj = cur[0] + nb[d][0], cur[1] + nb[d][1]
            if on(ni, nj):
                back = (d + 4) % 8
                cur = (ni, nj)
                found = True
                break
        if not found or cur == path[0]:
            break
        path.append(cur)
    C = np.array([(lo[0] + (i + 0.5) * g, lo[1] + (j + 0.5) * g) for i, j in path])
    # 走的方向：有向面积 > 0 是逆时针
    area = 0.5 * np.sum(C[:, 0] * np.roll(C[:, 1], -1) - np.roll(C[:, 0], -1) * C[:, 1])
    if area < 0:
        C = C[::-1]
    C = dp_closed(C, 0.06)   # 比一格（0.04）大一点：栅格的一格台阶抹平
    k = int(np.argmin(C[:, 0] + 1e-3 * C[:, 1]))   # 从最前面（z 最小）那一点开始
    return np.roll(C, -k, axis=0)


def dp_closed(C, tol):
    """闭合折线的道格拉斯-普克化简"""
    def dp(P):
        if len(P) < 3:
            return P
        a, b = P[0], P[-1]
        ab = b - a
        L = np.linalg.norm(ab)
        d = np.abs(ab[0] * (P[:, 1] - a[1]) - ab[1] * (P[:, 0] - a[0])) / L if L > 1e-9 else np.linalg.norm(P - a, axis=1)
        i = int(np.argmax(d))
        if d[i] <= tol:
            return np.array([a, b])
        return np.vstack([dp(P[:i + 1])[:-1], dp(P[i:])])
    far = int(np.argmax(np.linalg.norm(C - C[0], axis=1)))
    A = dp(np.vstack([C[:far + 1]]))
    Bq = dp(np.vstack([C[far:], C[:1]]))
    return np.vstack([A[:-1], Bq[:-1]])


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
    # 单独的履带块：游戏里藏起来，整圈按它们的外轮廓
    J_, BIN_ = glbio.read_glb(os.path.join(GLB_DIR, key + '.glb'))
    pz = [p[0] for p in poly]
    belts = belt_parts(J_, BIN_, xi, xo, max(pz) - min(pz))
    pure = [(nm, m) for nm, m, ok in belts if ok]
    use = pure or [(nm, m) for nm, m, ok in belts]
    loopC = None
    if use:
        TT = np.concatenate([m.P[m.idx][:, :, [2, 1]] for _, m in use])
        TT = TT - np.array([0, y0])
        loopC = envelope(TT)
        if not pure and loopC[:, 1].max() > top + 0.35:   # 带着侧裙板之类、外轮廓被顶高了（10 式）：不用
            loopC = None
    if loopC is not None:
        BP = np.concatenate([m.P[np.unique(m.idx.reshape(-1))] for _, m in use])
        bx = np.abs(BP[:, 0])
        if pure:
            res[key]['trk'] = [nm for nm, _ in pure]
        res[key]['bxi'], res[key]['bxo'] = round(float(np.percentile(bx, 1)), 3), round(float(np.percentile(bx, 99)), 3)
        # 下面一半有多长：从最前面那一点逆时针走到最后面那一点（打断的履带只剩这一段）
        kz = int(np.argmax(loopC[:, 0]))
        seg = np.linalg.norm(np.diff(loopC[:kz + 1], axis=0), axis=1).sum()
        res[key]['lowL'] = round(float(seg), 2)
        res[key]['loop'] = [round(float(v), 2) for p in loopC for v in p]
    print('%-8s x %.2f..%.2f  上沿 %.1f  轮廓 %d 点%s' % (key, xi, xo, top, len(poly),
          ('；履带块 %s（藏），外轮廓 %d 点' % ('/'.join(res[key]['trk']), len(loopC))) if pure and loopC is not None else
          ('；履带块 %s 里还带着别的（不藏）%s' % ('/'.join(nm for nm, _ in use), ('，外轮廓 %d 点' % len(loopC)) if loopC is not None else '，外轮廓被顶高了不用')) if use else
          '；没有单独的履带块（和车身一块网格）'))
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
        if loopC is not None:   # 履带块的外轮廓（绿）
            lp = [((z - zmin) * K + 4, H - 5 - y * K) for z, y in loopC]
            dr.line(lp + lp[:1], fill=(60, 230, 90), width=1)
        os.makedirs(REVIEW, exist_ok=True)
        im.save(os.path.join(REVIEW, key + '.png'))

lines = ['-- 履带轮廓（tools/models/trackfit.py 从原模型量的，别手改）：客户端 Tracks.lua 照它套一圈会转的履带板',
         '--   TL[模型键] = { xi 履带内边, xo 外边（|x|，左右对称）, top 上面一段的高度, z0 / z1 上面一段画到哪（前、后）,',
         '--     pts = { z1, y1, z2, y2, … } 下面一段：车头那头 → 贴地 → 车尾那头的折线（格，原点车底中心，−Z 朝前）,',
         '--     原模型履带是单独的块的（大多数）：trk = { 块名… } 游戏里套上履带板时把它们藏起来（不然看着是两副履带）；',
         '--     loop = { z, y, … } 这些块侧视的外轮廓（逆时针一整圈，从最前面那一点开始）、lowL 下面一半多长、bxi / bxo 履带块的内外边 }',
         'return {']
for k in sorted(res):
    r = res[k]
    extra = ''
    if r.get('loop'):
        extra = '%s, bxi = %s, bxo = %s, lowL = %s, loop = { %s }' % ((', trk = { %s }' % ', '.join('"%s"' % n for n in r['trk'])) if r.get('trk') else '',
                                                                     r['bxi'], r['bxo'], r['lowL'], ', '.join(str(v) for v in r['loop']))
    lines.append('  %s = { xi = %s, xo = %s, top = %s, z0 = %s, z1 = %s, pts = { %s }%s },' % (k, r['xi'], r['xo'], r['top'], r['z0'], r['z1'], ', '.join(str(v) for v in r['pts']), extra))
lines.append('}')
open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('写了', OUT, len(res), '辆')
