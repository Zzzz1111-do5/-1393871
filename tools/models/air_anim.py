# 原模型飞机的活动部件：从机体网格里把舵面、弹舱门、座舱盖精确切出来（沿铰链线、边界线切开三角形，切口插值出新顶点），
#   起落架按连通块分成前 / 左 / 右三根，各自给一条铰链线——游戏里（AirModels.lua）绕铰链转
# tools/models/air2glb.py 调用：apply(key, VB, tris, g, m, mats) → 新的 VB、tris、g（部件名）、m（材质），以及各部件的铰链（网页版坐标：x 前、y 左、z 上，米）
# 表 SURF 是按 tools/models/air_view.py 画的俯视 / 侧视 / 仰视线框图量的（网页版坐标；左右对称的只写右边 |y|，自动镜像）
#   t 切法：
#     te   后缘舵面（副翼、襟翼、升降舵、方向舵）：sp 展向轴（y 机翼 / z 垂尾）、r 展向范围、x 前后窗口、w 厚度方向窗口（机翼是 z、垂尾是 |y|）；
#          在 r 两端各量一刀翼型的前后缘，铰链在后缘往前 c 米（或弦长的 f 倍）处，翼型中线的高度；沿铰链线和展向两端切开
#     box  全动翼面（全动平尾、鸭翼、全动垂尾）：范围内的三角形（cut 给了在翼根 r[0] 处切一刀；comp 按连通块整块挑），转轴在前后缘之间 pf 处
#     bay  弹舱门：x / y 矩形（带正负号，不镜像）、zc 只切这个高度以下的机腹蒙皮、hy 铰链（平行机身轴线）、A 开到多少度（弧度）、b 哪个弹舱（bay / bayS）
#     can  座舱盖：mats 玻璃材质 + 盖框（x 前后、zf 窗框下沿以上、|y| < yw），hx 铰链在哪（后铰链 / 前铰链）、A 掀起的角度
#   k 动法（AirModels.lua 按它算角度）：ail 副翼、flap 襟翼、flaperon 襟副翼、elevon 升降副翼、stab 全动平尾、elev 升降舵、can 鸭翼、rud 方向舵、fin 全动垂尾、
#     rv V 形尾翼（升降方向舵）、bay / bayS 弹舱门、canopy 座舱盖、gear 起落架
import numpy as np

X = np.array([1.0, 0, 0])
EPS = 1e-6


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def rot(p, a, axis, th):
    """绕过 a 点、方向 axis 的轴转 th（右手定则）"""
    k = unit(axis)
    v = np.asarray(p, dtype=np.float64) - a
    return a + v * np.cos(th) + np.cross(k, v) * np.sin(th) + k * np.dot(k, v) * (1 - np.cos(th))


class Mesh:
    def __init__(self, VB, tris, g, m):
        self.VB, self.T, self.g, self.m = VB, tris, g, m

    def P(self):
        return self.VB[:, 0:3]

    def cent(self, idx=None):
        T = self.T if idx is None else self.T[idx]
        return self.VB[T, 0:3].mean(axis=1)

    def cut(self, cand, n, d):
        """候选三角形里跨过平面 n·p = d 的切成两边（各自扇形三角化），切口新顶点按边插值（同一条边只插一次，保持相连）"""
        if len(cand) == 0:
            return
        VB = self.VB
        s = VB[:, 0:3] @ n - d
        S = s[self.T[cand]]
        X_ = cand[(S > EPS).any(1) & (S < -EPS).any(1)]
        if len(X_) == 0:
            return
        base = len(VB)
        newV, cache = [], {}

        def mid(i, j):
            key = (i, j) if i < j else (j, i)
            if key in cache:
                return cache[key]
            t = s[i] / (s[i] - s[j])
            v = VB[i] + (VB[j] - VB[i]) * t
            nn = np.linalg.norm(v[3:6])
            if nn > 0:
                v[3:6] = v[3:6] / nn
            cache[key] = base + len(newV)
            newV.append(v)
            return cache[key]
        addT, addG, addM = [], [], []
        keep = np.ones(len(self.T), dtype=bool)
        for t in X_:
            a = self.T[t]
            pp, pn = [], []
            for k in range(3):
                i, j = int(a[k]), int(a[(k + 1) % 3])
                si, sj = s[i], s[j]
                if si >= -EPS:
                    pp.append(i)
                if si <= EPS:
                    pn.append(i)
                if (si > EPS and sj < -EPS) or (si < -EPS and sj > EPS):
                    q = mid(i, j)
                    pp.append(q)
                    pn.append(q)
            for poly in (pp, pn):
                for k in range(1, len(poly) - 1):
                    addT.append([poly[0], poly[k], poly[k + 1]])
                    addG.append(self.g[t])
                    addM.append(self.m[t])
            keep[t] = False
        self.VB = np.vstack([VB, np.array(newV)]) if newV else VB
        self.T = np.concatenate([self.T[keep], np.array(addT, dtype=np.int64).reshape(-1, 3)])
        self.g = np.concatenate([self.g[keep], np.array(addG, dtype=object)])
        self.m = np.concatenate([self.m[keep], np.array(addM, dtype=self.m.dtype)])


SRC = ('Body', 'FoldR', 'FoldL', 'TipR', 'TipL')   # 从这些部件里切（歼-15 的外翼、平尾外段是折叠部件：切出来的舵面跟着折）


def cand_box(M, lo, hi, groups=SRC, margin=0.05):
    """包围盒和盒子（网页版坐标 lo / hi）重叠的三角形（大三角形的顶点可能都不在盒子里）"""
    P = M.VB[M.T, 0:3]   # (n, 3, 3)
    inside = ((P.min(axis=1) <= hi + margin) & (P.max(axis=1) >= lo - margin)).all(axis=1)
    return np.where(inside & np.isin(M.g, groups))[0]


def sel_box(M, lo, hi, groups=SRC):
    C = M.cent()
    return np.where(((C >= lo) & (C <= hi)).all(axis=1) & np.isin(M.g, groups))[0]


def side_box(sp, r, x, w, sy):
    """展向范围 r、前后窗口 x、厚度方向窗口 w → 盒子（sy 右 −1 / 左 +1：网页版 y < 0 是右边）"""
    if sp == 'y':
        ys = sorted([sy * r[0], sy * r[1]])
        return np.array([x[0], ys[0], w[0]]), np.array([x[1], ys[1], w[1]])
    ys = sorted([sy * w[0], sy * w[1]]) if sy else [w[0], w[1]]
    return np.array([x[0], ys[0], r[0]]), np.array([x[1], ys[1], r[1]])


def slice_pts(M, idx, sp, at, tol, sy):
    """这些三角形被展向平面（|y| 或 z = at）切出的截面点：跨过平面的边按插值求交点，再加上离平面 tol 以内的顶点（大三角形的机翼上也量得准）"""
    T = M.T[idx]
    P = M.VB[T, 0:3]   # (n, 3, 3)
    c = P[:, :, 1] * (sy if sy else 1) if sp == 'y' else P[:, :, 2]
    d = c - at
    out = [P[np.abs(d) < tol]]
    for i, j in ((0, 1), (1, 2), (2, 0)):
        k = (d[:, i] * d[:, j]) < 0
        if k.any():
            t = (d[k, i] / (d[k, i] - d[k, j]))[:, None]
            out.append(P[k, i] + (P[k, j] - P[k, i]) * t)
    return np.concatenate(out) if out else np.zeros((0, 3))


def airfoil(Q, sp, sy, f=None, c=None):
    """一刀翼型（顶点集）：前缘 x、后缘 x，铰链 x（后缘往前 c 米或弦长 f 倍）、铰链处的厚度中线"""
    le, te = Q[:, 0].max(), Q[:, 0].min()
    xh = te + (c if c is not None else f * (le - te))
    near = Q[np.abs(Q[:, 0] - xh) < max(0.12, 0.08 * (le - te))]
    if len(near) == 0:
        near = Q
    k = 2 if sp == 'y' else 1
    mid = (near[:, k].min() + near[:, k].max()) / 2
    return le, te, xh, mid


def hinge_pts(M, idx, sp, r, sy, f=None, c=None, tol=0.01, lo=None, hi=None):
    """在展向两端（往里收一点）各量一刀，返回铰链两端点（网页版坐标）；lo / hi 给了只要盒子里的截面点"""
    out = []
    span = abs(r[1] - r[0])

    def clip(Q):
        if lo is None:
            return Q
        return Q[((Q >= lo - 1e-6) & (Q <= hi + 1e-6)).all(axis=1)]
    for at in (r[0] + min(0.15, span * 0.1), r[1] - min(0.15, span * 0.1)):
        Q = clip(slice_pts(M, idx, sp, at, tol, sy))
        if len(Q) < 3:
            Q = clip(slice_pts(M, idx, sp, at, tol * 10, sy))
        if len(Q) < 3:
            raise ValueError('量不到翼型：展向 %s = %.2f' % (sp, at))
        le, te, xh, mid = airfoil(Q, sp, sy, f, c)
        if sp == 'y':
            out.append(np.array([xh, (sy if sy else 1) * at, mid]))
        else:
            out.append(np.array([xh, mid, at]))
    # 端点按展向量的位置往外推回 r 两端（铰链线覆盖整个舵面）
    a, b = out
    d = b - a
    k = 1 if sp == 'y' else 2
    span_ab = (b[k] - a[k])
    if abs(span_ab) > 1e-6:
        r0 = (sy if (sp == 'y' and sy) else 1) * r[0]
        r1 = (sy if (sp == 'y' and sy) else 1) * r[1]
        a2 = a + d * ((r0 - a[k]) / span_ab)
        b2 = a + d * ((r1 - a[k]) / span_ab)
        a, b = a2, b2
    return a, b


def plane_normal(a, b, sp):
    """过铰链线、垂直于翼面的切面：法线朝后（后缘那边为正）"""
    ab = unit(b - a)
    t = unit(np.cross(ab, X))           # 翼面法线（厚度方向）
    n = unit(np.cross(ab, t))
    if n[0] > 0:
        n = -n
    return n


def do_te(M, S, sy):
    sp = S.get('sp', 'y')
    lo, hi = side_box(sp, S['r'], S['x'], S['w'], sy)
    cand = cand_box(M, lo, hi, S.get('src', SRC))
    if S.get('h'):   # 铰链线直接给（右边：[[x, |y|], [x, |y|]]，高 hz；网页版 V3G_PIT 的 ctl 量好的）
        (x0, y0), (x1, y1) = S['h']
        a, b = np.array([x0, (sy or 1) * y0, S['hz']]), np.array([x1, (sy or 1) * y1, S['hz']])
    else:
        a, b = hinge_pts(M, cand, sp, S['r'], sy, S.get('f'), S.get('c'), lo=lo, hi=hi)
    n = plane_normal(a, b, sp)
    M.cut(cand, n, n @ a)
    cand = cand_box(M, lo, hi, S.get('src', SRC))
    # 展向两端
    if sp == 'y':
        for r_ in S['r']:
            M.cut(cand, np.array([0, 1.0, 0]), sy * r_)
            cand = cand_box(M, lo, hi, S.get('src', SRC))
    else:
        for r_ in S['r']:
            M.cut(cand, np.array([0, 0, 1.0]), r_)
            cand = cand_box(M, lo, hi, S.get('src', SRC))
    sel = sel_box(M, lo, hi, S.get('src', SRC))
    C = M.cent(sel)
    aft = (C - a) @ n > 0
    return sel[aft], a, b


def do_box(M, S, sy):
    sp = S.get('sp', 'y')
    lo, hi = side_box(sp, S['r'], S['x'], S['w'], sy)
    src = S.get('src', SRC)
    if S.get('cut'):
        cand = cand_box(M, lo, hi, src)
        if sp == 'y':
            M.cut(cand, np.array([0, 1.0, 0]), sy * S['r'][0])
        else:
            M.cut(cand, np.array([0, 0, 1.0]), S['r'][0])
    sel = sel_box(M, lo, hi, src)
    P = M.VB[M.T[sel], 0:3]
    sel = sel[((P >= lo - 0.02) & (P <= hi + 0.02)).all(axis=2).all(axis=1)]
    if S.get('px') is not None and sp == 'y':   # 转轴垂直于机身（真实的全动鸭翼、平尾）：在 x = px、高 pz 处平行 y 轴
        a = np.array([S['px'], (sy or 1) * S['r'][0], S['pz']])
        b = np.array([S['px'], (sy or 1) * S['r'][1], S['pz']])
    elif S.get('px') is not None:   # 全动垂尾：转轴在垂尾面里、不后掠（x = px），上下两端按那里垂尾的厚度中线（外倾的跟着倾斜）
        a, b = hinge_pts(M, sel, sp, S['r'], sy, 0.5, lo=lo, hi=hi)
        a[0] = b[0] = S['px']
    else:
        a, b = hinge_pts(M, sel, sp, S['r'], sy, S.get('pf', 0.45), lo=lo, hi=hi)
    return sel, a, b


def do_bay(M, S):
    x, y, zc = S['x'], S['y'], S['zc']
    lo, hi = np.array([x[0], y[0], -9.0]), np.array([x[1], y[1], zc])
    src = S.get('src', ('Body',))
    for ax, vals in ((0, x), (1, y)):
        cand = cand_box(M, lo, hi, src)
        nrm = np.zeros(3)
        nrm[ax] = 1
        for v in vals:
            M.cut(cand, nrm, v)
            cand = cand_box(M, lo, hi, src)
    sel = sel_box(M, lo, hi, src)
    if S.get('mats') is not None:   # 只要机腹蒙皮这几种材质（材质名）
        sel = sel[np.isin(M.m[sel], [i for i, n in enumerate(M.mnames) if n in S['mats']])]
    Q = M.VB[np.unique(M.T[sel].reshape(-1)), 0:3]
    hy = S['hy']
    near = Q[np.abs(Q[:, 1] - hy) < 0.08]
    hz = float(near[:, 2].mean()) if len(near) else float(Q[:, 2].mean())
    a, b = np.array([x[1], hy, hz]), np.array([x[0], hy, hz])
    return sel, a, b


def do_can(M, S):
    x = S['x']
    sel_parts = []
    C = M.cent()
    if S.get('mats'):   # 玻璃：前后范围里、zg 以上的
        g = np.isin(M.m, [i for i, n in enumerate(M.mnames) if n in S['mats']]) & (C[:, 0] >= x[0]) & (C[:, 0] <= x[1]) & np.isin(M.g, ('Body',))
        if S.get('zg') is not None:
            g &= C[:, 2] >= S['zg']
        if S.get('oz') is not None:   # 只要外层：面朝外（离开座舱中轴线 y = 0、z = oz 的方向）的玻璃，座舱里的仪表玻璃、平显、后隔板不算
            P = M.VB[M.T, 0:3]
            N = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
            N /= np.linalg.norm(N, axis=1)[:, None] + 1e-12
            Rr = C - np.stack([C[:, 0], 0 * C[:, 0], S['oz'] + 0 * C[:, 0]], 1)
            Rr /= np.linalg.norm(Rr, axis=1)[:, None] + 1e-12
            g &= (N * Rr).sum(1) > 0.3
        sel_parts.append(np.where(g)[0])
    if S.get('zf') is not None:   # 盖子（整块蒙皮的模型：座舱盖和机身同一种材质）：窗框下沿 zf 以上（[[x0, z0], [x1, z1]] 斜的一刀）、前后范围里、|y| < yw
        zf = S['zf']
        (x0, z0), (x1, z1) = zf if isinstance(zf, (list, tuple)) else ((0, zf), (1, zf))
        k = (z1 - z0) / (x1 - x0)
        nz = unit([-k, 0, 1.0])
        dz = nz @ np.array([x0, 0, z0])
        lo, hi = np.array([x[0], -S['yw'], min(z0, z1) - 0.5]), np.array([x[1], S['yw'], 9.0])
        for nrm, d in ((nz, dz), (X, x[0]), (X, x[1]), (np.array([0, 1.0, 0]), S['yw']), (np.array([0, 1.0, 0]), -S['yw'])):
            M.cut(cand_box(M, lo, hi, ('Body',)), nrm, d)
        sb = sel_box(M, lo, hi, ('Body',))
        sb = sb[M.cent(sb) @ nz > dz]
        sel_parts.append(sb)
    sel = np.unique(np.concatenate(sel_parts))
    hx = S['hx']
    Q = M.VB[np.unique(M.T[sel].reshape(-1)), 0:3]
    near = Q[np.abs(Q[:, 0] - hx) < 0.25]
    hz = S.get('hz', float(near[:, 2].min()) if len(near) else float(Q[:, 2].min()))
    a, b = np.array([hx, 0.5, hz]), np.array([hx, -0.5, hz])
    return sel, a, b


def components(M, idx):
    """这些三角形按顶点坐标（到毫米）相连分块"""
    q = np.round(M.VB[M.T[idx].reshape(-1), 0:3] * 1000).astype(np.int64)
    _, vid = np.unique(q, axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    par = np.arange(vid.max() + 1)

    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    for a, b, c in vid:
        ra, rb, rc = find(a), find(b), find(c)
        par[rb] = ra
        par[find(rc)] = ra
    return np.array([find(v[0]) for v in vid])


def do_gear(M, S):
    """起落架按连通块分三组：x > nx 的是前起落架，其余按左右；铰链在每组顶上"""
    idx = np.where(M.g == 'Gear')[0]
    cid = components(M, idx)
    C = M.cent(idx)
    out = {}
    P = M.VB[M.T[idx], 0:3]
    gtop = P[:, :, 2].max()
    for r in np.unique(cid):
        k = cid == r
        Q = P[k].reshape(-1, 3)
        if Q[:, 2].min() > S.get('hi', 0.55) * gtop:   # 整块在上面贴着机身的（舱门、轮舱）：不跟着转，起落架收到一半藏起来
            out.setdefault('GearD', []).append(idx[k])
            continue
        cx, cy = C[k, 0].mean(), C[k, 1].mean()
        name = 'GearN' if cx > S['nx'] else ('GearR' if cy < 0 else 'GearL')
        out.setdefault(name, []).append(idx[k])
    res = {}
    for name, parts in out.items():
        sel = np.concatenate(parts)
        if name == 'GearD':
            res[name] = (sel, None, None, 'door')
            continue
        Q = M.VB[np.unique(M.T[sel].reshape(-1)), 0:3]
        top = Q[:, 2].max()
        crown = Q[Q[:, 2] > top - 0.12]
        hp = np.array([crown[:, 0].mean(), crown[:, 1].mean(), top])
        mode = S['n'] if name == 'GearN' else S['m']
        ax = np.array([0, 1.0, 0]) if mode in ('f', 'a') else np.array([1.0, 0, 0])
        res[name] = (sel, hp - ax * 0.5, hp + ax * 0.5, mode)
    return res


def probe_sign(a, b, probe, want, th=0.3):
    """转 +th 后探测点往 want 方向走 → +1，否则 −1。网页版坐标里算：换到 Roblox 坐标（rb）是个行列式 +1 的转动加缩放，
    右手定则的转向不变，所以游戏里 CFrame.fromAxisAngle(b − a, sg × 角度) 一样转"""
    q = rot(probe, a, b - a, th)
    return 1 if (q - probe) @ want > 0 else -1


# 方向（网页版坐标）：往右 −y、往下 −z、往上 +z、往前 +x
RIGHT, DOWN, UP, FWD = np.array([0, -1.0, 0]), np.array([0, 0, -1.0]), np.array([0, 0, 1.0]), np.array([1.0, 0, 0])


def apply(key, VB, tris, g, m, SURF, GEAR, mnames=()):
    """切出活动部件；返回新网格（VB、三角形、部件名、材质）和 surf[部件名] = { k 动法, s 侧（1 右 −1 左 0 中）, a / b 铰链两端（网页版坐标）,
    sg 正角度的方向（舵面：后缘往下 / 方向舵后缘往右；舱门、起落架：打开 / 收起）, A 开到多大, fold / tip 跟着哪边折 }"""
    M = Mesh(VB, tris, g, m)
    M.mnames = list(mnames)
    jobs = []
    for S in SURF.get(key, []):
        t = S['t']
        sides = [0] if (S.get('mir') is False or t in ('bay', 'can')) else [-1, 1]
        for sy in sides:
            if t == 'te':
                sel, a, b = do_te(M, S, sy)
            elif t == 'box':
                sel, a, b = do_box(M, S, sy)
            elif t == 'bay':
                sel, a, b = do_bay(M, S)
            else:
                sel, a, b = do_can(M, S)
            if len(sel) == 0:
                raise ValueError('%s %s 一个三角形也没选到' % (key, S['g']))
            nm = S['g'] + ({-1: 'R', 1: 'L', 0: ''}[sy])
            # 按来源分开：机体上的、折叠外翼上的（跟着折）、平尾外段上的（跟着平尾外段的铰链折）——同一条铰链
            src_g = M.g[sel].copy()
            for sub, mask, extra in ((nm, src_g == 'Body', {}),
                                     (nm + 'f', np.isin(src_g, ('FoldR', 'FoldL')), {'fold': -sy if sy else 1}),
                                     (nm + 't', np.isin(src_g, ('TipR', 'TipL')), {'tip': -sy if sy else 1})):
                if mask.any():
                    M.g[sel[mask]] = sub   # 标上以后后面的切法不会再切到它（SRC 里没有这个名字）
                    jobs.append((sub, a, b, S, -sy if sy else 0, extra))
    surf = {}
    for nm, a, b, S, s, extra in jobs:
        idx = np.where(M.g == nm)[0]   # 切过以后三角形下标变了：按部件名重新找
        k = S['k']
        Q = M.VB[np.unique(M.T[idx].reshape(-1)), 0:3]
        if k in ('rud', 'fin'):
            probe, want = Q[np.argmin(Q[:, 0])], RIGHT    # 最靠后的点往右
        elif k in ('bay', 'bayS', 'gdh'):
            probe, want = Q.mean(0), DOWN                  # 舱门往下翻（gdh：起落架舱门）
        elif k == 'canopy':
            probe, want = Q.mean(0), UP                    # 座舱盖往上掀
        else:
            probe, want = Q[np.argmin(Q[:, 0])], DOWN     # 后缘往下
        e = {'k': k, 's': s, 'a': a, 'b': b, 'sg': probe_sign(a, b, probe, want)}
        if S.get('A') is not None:
            e['A'] = round(float(S['A']), 3)
        e.update(extra)
        surf[nm] = e
    # 起落架
    if GEAR.get(key) and (M.g == 'Gear').any():
        for nm, (sel, a, b, mode) in do_gear(M, GEAR[key]).items():
            M.g[sel] = nm
            if mode == 'door':   # 舱门：不转，起落架收到一半藏起来
                surf[nm] = {'k': 'gdoor', 's': 0, 'a': np.zeros(3), 'b': np.array([1.0, 0, 0]), 'sg': 1}
                continue
            Q = M.VB[np.unique(M.T[sel].reshape(-1)), 0:3]
            probe = Q[np.argmin(Q[:, 2])]   # 机轮最低点
            if mode == 'f':
                want = FWD + UP * 0.3
            elif mode == 'a':
                want = -FWD + UP * 0.3
            else:   # 往里收：朝机身中线
                want = np.array([0, -(np.sign(probe[1]) or 1.0), 0.3])
            surf[nm] = {'k': 'gear', 's': 0 if nm == 'GearN' else (1 if nm == 'GearR' else -1), 'a': a, 'b': b,
                        'sg': probe_sign(a, b, probe, want), 'A': GEAR[key].get('A', 1.57)}
    return M.VB, M.T, M.g, M.m, surf


# ---------------------------------------------------------------- 各机型的表（网页版坐标，米；量法见文件开头）

LJ50 = 1.3    # 歼-50 同上
LJ20 = 1.25   # 歼-20 网页版补起落架时整架抬高的（V3G_GEAR lift）：网页版的表按抬高后的高度量，这里减掉
SURF = {
    # 歼-20：后缘一整条襟副翼（内段升降副翼、外段副翼，弦长约 0.65 米）、全动鸭翼（转轴垂直机身）、全动垂尾（外倾）、
    #   主弹舱两扇门（铰链在外侧）+ 侧弹舱各一扇（进气道下侧的斜面上，铰链在外上沿），同网页版 V3G_BAY；座舱盖后铰链往上掀
    'j20': [
        {'g': 'Elv', 'k': 'elevon', 't': 'te', 'r': [2.45, 4.2], 'x': [-7.95, -5.5], 'w': [1.0, 1.4], 'c': 0.65},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [4.2, 6.25], 'x': [-7.95, -5.5], 'w': [1.0, 1.4], 'c': 0.65},
        {'g': 'Can', 'k': 'can', 't': 'box', 'r': [1.85, 4.1], 'x': [0.6, 4.6], 'w': [1.0, 1.4], 'cut': True, 'px': 2.0, 'pz': 1.2},
        {'g': 'Fin', 'k': 'fin', 't': 'box', 'sp': 'z', 'r': [1.72, 3.25], 'x': [-10.6, -6.8], 'w': [1.7, 3.1], 'cut': True, 'px': -8.2},
        {'g': 'BayM1', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.2], 'y': [0, .78], 'hy': .78, 'zc': 1.37 - LJ20, 'A': 1.75, 'mats': ['Material.008', 'Material.016', 'grey']},
        {'g': 'BayM2', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.2], 'y': [-.78, 0], 'hy': -.78, 'zc': 1.37 - LJ20, 'A': 1.75, 'mats': ['Material.008', 'Material.016', 'grey']},
        {'g': 'BaySL', 'k': 'bayS', 't': 'bay', 'x': [-1.55, 1.89], 'y': [1.22, 1.57], 'hy': 1.57, 'zc': 2.2 - LJ20, 'A': 1.6, 'mats': ['Material.008', 'Material.016', 'grey']},
        {'g': 'BaySR', 'k': 'bayS', 't': 'bay', 'x': [-1.55, 1.89], 'y': [-1.57, -1.22], 'hy': -1.57, 'zc': 2.2 - LJ20, 'A': 1.6, 'mats': ['Material.008', 'Material.016', 'grey']},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['Basic_Glass.001'], 'x': [4.7, 7.8], 'zg': 1.45, 'hx': 4.78, 'A': 0.75},
        # 起落架舱门（用户 11-18：找到起落架的收放位置、实现动画；起落架本身 tools/models/j20_gear.py 建）：动法 gdh——放起落架的前 1/4 开门、收起的最后 1/4 关门
        #   前起落架舱：座舱下面两扇（铰链在外侧，往下开）；主起落架舱：侧弹舱后面、进气道下侧的斜面上一扇（铰链在外上沿，同侧弹舱）
        {'g': 'GDoorN1', 'k': 'gdh', 't': 'bay', 'x': [4.6, 6.95], 'y': [0, 0.30], 'hy': 0.30, 'zc': 0.55, 'A': 1.5},
        {'g': 'GDoorN2', 'k': 'gdh', 't': 'bay', 'x': [4.6, 6.95], 'y': [-0.30, 0], 'hy': -0.30, 'zc': 0.55, 'A': 1.5},
        {'g': 'GDoorML', 'k': 'gdh', 't': 'bay', 'x': [-4.35, -1.9], 'y': [1.0, 1.48], 'hy': 1.48, 'zc': 0.95, 'A': 1.6, 'mats': ['grey']},
        {'g': 'GDoorMR', 'k': 'gdh', 't': 'bay', 'x': [-4.35, -1.9], 'y': [-1.48, -1.0], 'hy': -1.48, 'zc': 0.95, 'A': 1.6, 'mats': ['grey']},
    ],
    # F-22：外段副翼、内段襟副翼（后缘前掠）、全动平尾、外倾双垂尾的方向舵；主弹舱（机腹两扇，铰链在外侧）、侧弹舱（进气道下侧，铰链在上沿）；
    #   机腹在 z ≈ 0.06–0.13 米（|y| < 1.25），往外是进气道侧面的斜面
    'f22': [
        {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [2.95, 4.9], 'x': [-5.88, -3.0], 'w': [0.75, 1.3], 'c': 0.75},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [4.9, 6.3], 'x': [-5.88, -3.0], 'w': [0.75, 1.3], 'c': 0.6},
        {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [2.0, 4.75], 'x': [-9.6, -5.89], 'w': [0.85, 1.4], 'cut': True, 'px': -7.6, 'pz': 1.12},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [1.8, 3.75], 'x': [-7.6, -3.4], 'w': [1.5, 3.0], 'f': 0.3},
        {'g': 'BayM1', 'k': 'bay', 't': 'bay', 'x': [-2.7, 1.3], 'y': [0, 1.0], 'hy': 1.0, 'zc': 0.25, 'A': 1.75},
        {'g': 'BayM2', 'k': 'bay', 't': 'bay', 'x': [-2.7, 1.3], 'y': [-1.0, 0], 'hy': -1.0, 'zc': 0.25, 'A': 1.75},
        {'g': 'BaySL', 'k': 'bayS', 't': 'bay', 'x': [1.0, 2.9], 'y': [1.25, 1.6], 'hy': 1.6, 'zc': 0.62, 'A': 1.6},
        {'g': 'BaySR', 'k': 'bayS', 't': 'bay', 'x': [1.0, 2.9], 'y': [-1.6, -1.25], 'hy': -1.6, 'zc': 0.62, 'A': 1.6},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['glass', 'plumes'], 'x': [3.3, 7.8], 'zg': 1.0, 'oz': 0.9, 'hx': 3.5, 'A': 0.75},
    ],
    # 歼-31（代歼-35）：舵面范围、铰链照网页版 V3G_PIT.j31.ctl（模型上的舵面本来就是单独的面）；方向舵在外倾双垂尾后缘；
    #   两个并列主弹舱、每舱两扇门（同网页版 V3G_BAY.j31）；座舱盖后铰链
    'j31': [
        {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [1.7, 4.76], 'x': [-5.0, -3.0], 'w': [1.6, 2.1], 'h': [[-4.12, 1.77], [-3.77, 4.74]], 'hz': 1.85},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [4.74, 5.82], 'x': [-4.6, -3.0], 'w': [1.6, 2.1], 'h': [[-3.745, 4.74], [-3.73, 5.77]], 'hz': 1.85},
        {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [1.3, 4.25], 'x': [-8.6, -5.2], 'w': [1.5, 2.2], 'px': -6.55, 'pz': 1.86},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [2.45, 4.2], 'x': [-7.5, -3.5], 'w': [1.7, 3.0], 'f': 0.3},
        {'g': 'Bay1L', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.1], 'y': [.1, .51], 'hy': .1, 'zc': 1.3, 'A': 1.75},
        {'g': 'Bay2L', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.1], 'y': [.51, .92], 'hy': .92, 'zc': 1.3, 'A': 1.75},
        {'g': 'Bay1R', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.1], 'y': [-.51, -.1], 'hy': -.1, 'zc': 1.3, 'A': 1.75},
        {'g': 'Bay2R', 'k': 'bay', 't': 'bay', 'x': [-2.1, 2.1], 'y': [-.92, -.51], 'hy': -.92, 'zc': 1.3, 'A': 1.75},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['Material.001'], 'x': [3.35, 6.6], 'zg': 1.95, 'oz': 1.9, 'hx': 3.45, 'A': 0.75},
    ],
    # 歼-15（苏-33 外形）：襟副翼跨过折叠线（折叠外翼上那一截跟着折）、外段副翼、全动平尾（外段跟着平尾外段的铰链折）、鸭翼、双垂尾方向舵；
    #   座舱盖玻璃（材质 material）后铰链；起落架都往前收
    'j15': [
        {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [2.6, 5.0], 'x': [-7.2, -4.5], 'w': [2.4, 2.7], 'c': 0.85},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [5.0, 7.0], 'x': [-7.2, -4.5], 'w': [2.4, 2.7], 'c': 0.75},
        {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [2.3, 5.4], 'x': [-10.9, -6.9], 'w': [1.8, 2.2], 'cut': True, 'px': -8.5, 'pz': 2.0},
        {'g': 'Can', 'k': 'can', 't': 'box', 'r': [1.75, 3.4], 'x': [-1.0, 2.7], 'w': [2.3, 2.8], 'cut': True, 'px': 1.0, 'pz': 2.53},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [3.0, 5.4], 'x': [-8.6, -4.5], 'w': [1.9, 2.5], 'f': 0.3},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['material'], 'x': [3.5, 6.7], 'zg': 3.1, 'hx': 3.55, 'A': 0.7},
    ],
    # 歼-16（苏-30 外形，模型没放起落架：游戏里零件拼）：襟副翼、副翼、全动平尾（比机翼低 0.5 米）、双垂尾方向舵；双座座舱盖后铰链
    'j16': [
        {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [2.6, 4.6], 'x': [-6.0, -3.0], 'w': [1.1, 1.45], 'c': 0.8},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [4.6, 6.9], 'x': [-6.0, -3.0], 'w': [1.1, 1.45], 'c': 0.7},
        {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [2.0, 4.95], 'x': [-9.3, -5.5], 'w': [0.6, 0.85], 'cut': True, 'px': -7.8, 'pz': 0.72},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [2.4, 4.4], 'x': [-7.3, -4.0], 'w': [1.85, 2.1], 'f': 0.3},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['glass.001'], 'x': [4.3, 8.0], 'zg': 1.9, 'oz': 1.6, 'hx': 4.35, 'A': 0.7},
    ],
    # 歼-50（无尾，模型整块一种材质、没放起落架）：后缘两段升降副翼、全动翼尖；机腹两个弹舱各两扇门（同网页版 V3G_BAY.j50，高度减掉补起落架时抬的 1.3 米）；
    #   座舱盖按鼓包的轮廓斜切下来（后铰链），里面坐个飞行员
    'j50': [
        {'g': 'ElvI', 'k': 'elevon', 't': 'te', 'r': [2.6, 4.4], 'x': [-8.7, -5.5], 'w': [0.4, 1.5], 'c': 0.9},
        {'g': 'ElvO', 'k': 'elevon', 't': 'te', 'r': [4.4, 6.7], 'x': [-8.7, -5.5], 'w': [0.4, 1.5], 'c': 0.8},
        {'g': 'Tip', 'k': 'ail', 't': 'box', 'r': [6.75, 8.7], 'x': [-8.4, -4.8], 'w': [0.5, 1.1], 'cut': True, 'px': -7.0, 'pz': 0.8},
        {'g': 'Bay1L', 'k': 'bay', 't': 'bay', 'x': [-3.2, 1.6], 'y': [.45, 1.1], 'hy': .45, 'zc': 1.8 - LJ50, 'A': 1.75},
        {'g': 'Bay2L', 'k': 'bay', 't': 'bay', 'x': [-3.2, 1.6], 'y': [1.1, 1.75], 'hy': 1.75, 'zc': 1.8 - LJ50, 'A': 1.75},
        {'g': 'Bay1R', 'k': 'bay', 't': 'bay', 'x': [-3.2, 1.6], 'y': [-1.1, -.45], 'hy': -.45, 'zc': 1.8 - LJ50, 'A': 1.75},
        {'g': 'Bay2R', 'k': 'bay', 't': 'bay', 'x': [-3.2, 1.6], 'y': [-1.75, -1.1], 'hy': -1.75, 'zc': 1.8 - LJ50, 'A': 1.75},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'x': [3.0, 6.6], 'zf': [[3.0, 2.25], [6.6, 1.75]], 'yw': 0.62, 'hx': 3.05, 'A': 0.7},
    ],
    # F-35A：后缘一整段襟副翼、全动平尾、外倾双垂尾方向舵；机腹两个弹舱（中间一道龙骨）各两扇门；座舱盖是前铰链（往前上方掀开后缘），
    #   盖子是半透明的 Whitish_grey 材质
    'f35': [
        {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [2.1, 5.3], 'x': [-4.4, -2.0], 'w': [2.0, 2.45], 'c': 0.65},
        {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [2.0, 3.8], 'x': [-8.0, -4.6], 'w': [1.9, 2.45], 'cut': True, 'px': -6.3, 'pz': 2.2},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [2.75, 4.2], 'x': [-7.2, -3.5], 'w': [1.4, 2.4], 'f': 0.3},
        {'g': 'Bay1L', 'k': 'bay', 't': 'bay', 'x': [-2.1, 1.4], 'y': [.15, .55], 'hy': .15, 'zc': 1.45, 'A': 1.75},
        {'g': 'Bay2L', 'k': 'bay', 't': 'bay', 'x': [-2.1, 1.4], 'y': [.55, 1.05], 'hy': 1.05, 'zc': 1.45, 'A': 1.75},
        {'g': 'Bay1R', 'k': 'bay', 't': 'bay', 'x': [-2.1, 1.4], 'y': [-.55, -.15], 'hy': -.15, 'zc': 1.45, 'A': 1.75},
        {'g': 'Bay2R', 'k': 'bay', 't': 'bay', 'x': [-2.1, 1.4], 'y': [-1.05, -.55], 'hy': -1.05, 'zc': 1.45, 'A': 1.75},
        {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['Whitish_grey'], 'x': [2.95, 6.0], 'zg': 2.45, 'oz': 2.3, 'hx': 5.85, 'A': 0.6},
    ],
    # A-10C：内段襟翼、外段副翼（外翼上反）、平尾上的升降舵（平尾不全动）、双垂尾方向舵；座舱盖和机身贴在一起（没有单独的玻璃），不做开合
    'a10': [
        {'g': 'Flp', 'k': 'flap', 't': 'te', 'r': [2.7, 5.3], 'x': [-1.9, -0.3], 'w': [0.75, 1.5], 'c': 0.5},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [5.6, 8.6], 'x': [-1.45, -0.3], 'w': [0.75, 1.75], 'c': 0.42},
        {'g': 'Elev', 'k': 'elev', 't': 'te', 'r': [0.65, 2.85], 'x': [-7.9, -6.6], 'w': [0.85, 1.45], 'c': 0.55},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'r': [1.5, 3.4], 'x': [-7.8, -5.4], 'w': [2.85, 3.25], 'f': 0.35},
    ],
    # 轰-6K（网页版烘焙时机头朝后，转过来了）：内段襟翼、外段副翼、平尾上的升降舵、方向舵（平尾以上那段）；机腹弹舱两扇门（AirDefs 的弹舱范围）；
    #   座舱是玻璃机头、和机身一种材质，不做开合
    'h6k': [
        {'g': 'Flp', 'k': 'flap', 't': 'te', 'r': [4.6, 9.8], 'x': [-5.0, 1.0], 'w': [2.3, 3.6], 'c': 1.0},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [9.8, 15.4], 'x': [-7.7, -2.5], 'w': [2.1, 3.0], 'c': 0.85},
        {'g': 'Elev', 'k': 'elev', 't': 'te', 'r': [0.9, 5.4], 'x': [-17.4, -12.5], 'w': [4.6, 5.2], 'c': 0.75},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'mir': False, 'r': [5.3, 9.3], 'x': [-17.0, -9.0], 'w': [-0.7, 0.7], 'f': 0.3},
        {'g': 'Bay1', 'k': 'bay', 't': 'bay', 'x': [-5.0, 2.1], 'y': [0, 0.85], 'hy': 0.85, 'zc': 2.15, 'A': 1.6},
        {'g': 'Bay2', 'k': 'bay', 't': 'bay', 'x': [-5.0, 2.1], 'y': [-0.85, 0], 'hy': -0.85, 'zc': 2.15, 'A': 1.6},
    ],
    # B-2A（飞翼）：后缘锯齿形，内段、外段升降副翼和翼尖一段（真机翼尖是开裂式阻力方向舵，这里当副翼动）；两个并列的机腹弹舱，各两扇门（AirDefs 的 twin 弹舱）
    'b2': [
        {'g': 'ElvI', 'k': 'elevon', 't': 'te', 'r': [12.3, 17.5], 'x': [-8.0, -2.5], 'w': [0.9, 2.1], 'c': 0.9},
        {'g': 'ElvO', 'k': 'elevon', 't': 'te', 'r': [17.5, 21.5], 'x': [-10.5, -4.5], 'w': [0.9, 2.1], 'c': 0.9},
        {'g': 'Tip', 'k': 'ail', 't': 'te', 'r': [21.5, 24.3], 'x': [-10.6, -5.5], 'w': [0.9, 2.1], 'c': 0.8},
        {'g': 'Bay1L', 'k': 'bay', 't': 'bay', 'x': [-2.86, 2.14], 'y': [1.02, 1.64], 'hy': 1.02, 'zc': 0.6, 'A': 1.6},
        {'g': 'Bay2L', 'k': 'bay', 't': 'bay', 'x': [-2.86, 2.14], 'y': [1.64, 2.27], 'hy': 2.27, 'zc': 0.6, 'A': 1.6},
        {'g': 'Bay1R', 'k': 'bay', 't': 'bay', 'x': [-2.86, 2.14], 'y': [-1.64, -1.02], 'hy': -1.02, 'zc': 0.6, 'A': 1.6},
        {'g': 'Bay2R', 'k': 'bay', 't': 'bay', 'x': [-2.86, 2.14], 'y': [-2.27, -1.64], 'hy': -2.27, 'zc': 0.6, 'A': 1.6},
    ],
    # X-47B（代攻击-11，网页版烘焙时机头朝后，转过来了）：内段、外段升降副翼；机腹弹舱两扇门（AirDefs 的弹舱范围）
    'x47b': [
        {'g': 'ElvI', 'k': 'elevon', 't': 'te', 'r': [2.6, 4.6], 'x': [-5.0, -0.5], 'w': [1.5, 2.4], 'c': 0.6},
        {'g': 'ElvO', 'k': 'elevon', 't': 'te', 'r': [5.4, 8.8], 'x': [-6.2, -0.5], 'w': [1.7, 2.3], 'c': 0.6},
        {'g': 'Bay1', 'k': 'bay', 't': 'bay', 'x': [-1.07, 2.14], 'y': [0, 0.75], 'hy': 0.75, 'zc': 1.5, 'A': 1.6},
        {'g': 'Bay2', 'k': 'bay', 't': 'bay', 'x': [-1.07, 2.14], 'y': [-0.75, 0], 'hy': -0.75, 'zc': 1.5, 'A': 1.6},
    ],
    # MQ-9（也代攻击-2）：内段襟翼、外段副翼、V 形尾翼的升降方向舵（上反约 30°）、腹鳍上的方向舵
    'mq9': [
        {'g': 'Flp', 'k': 'flap', 't': 'te', 'r': [1.7, 5.0], 'x': [-1.6, 0.0], 'w': [1.75, 2.1], 'c': 0.3},
        {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [5.0, 8.4], 'x': [-1.2, 0.0], 'w': [1.75, 2.1], 'c': 0.28},
        {'g': 'RV', 'k': 'rv', 't': 'te', 'r': [0.75, 2.3], 'x': [-5.1, -3.4], 'w': [2.0, 3.2], 'c': 0.3},
        {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'mir': False, 'r': [0.55, 1.15], 'x': [-4.9, -3.4], 'w': [-0.12, 0.12], 'f': 0.35},
    ],
}
# 起落架怎么收：nx 前起落架在这个 x 以前；n / m 前 / 主起落架往哪收（f 往前、a 往后、in 往里）；A 收起转多少（弧度）
GEAR = {
    'j31': {'nx': 2.0, 'n': 'f', 'm': 'in'},
    'j15': {'nx': 0.5, 'n': 'f', 'm': 'f'},
    'f35': {'nx': 2.0, 'n': 'f', 'm': 'f'},
    'h6k': {'nx': 8.0, 'n': 'a', 'm': 'a'},   # 小车式主起落架往后收进翼上的短舱
    'x47b': {'nx': 2.0, 'n': 'a', 'm': 'f'},
    'mq9': {'nx': 2.0, 'n': 'a', 'm': 'in'},
    # A-10、B-2 的模型轮子半埋在机身 / 整流罩里（起落架那块只有 0.3～0.5 米高，还混着翼下挂架），不做收放转动：照旧收起时藏起来
}
# 弹舱井：x / y 范围、z0 底（舱门那么高）、top 顶
WELL = {
    'j20': [{'x': [-2.1, 2.2], 'y': [-.78, .78], 'z0': 1.37 - LJ20 + .02, 'top': 1.47 - LJ20},
            {'x': [-1.55, 1.89], 'y': [1.22, 1.57], 'z0': 2.0 - LJ20, 'top': 2.3 - LJ20}, {'x': [-1.55, 1.89], 'y': [-1.57, -1.22], 'z0': 2.0 - LJ20, 'top': 2.3 - LJ20},
            # 起落架舱（j20_gear.py）：前起落架舱一块；主起落架舱在斜面上，按斜面分三层台阶（底面都在蒙皮以上，舱门关着时露不出来）
            {'x': [4.62, 6.93], 'y': [-.28, .28], 'z0': 0.42, 'top': 1.25}]
           + [{'x': [-4.33, -1.92], 'y': [s * a if s > 0 else -b, s * b if s > 0 else -a], 'z0': z0, 'top': 1.5}
              for s in (1, -1) for a, b, z0 in ((1.02, 1.20, 0.40), (1.20, 1.36, 0.62), (1.36, 1.46, 0.88))],
    'f22': [{'x': [-2.7, 1.3], 'y': [-1.0, 1.0], 'z0': 0.16, 'top': 0.6},
            {'x': [1.0, 2.9], 'y': [1.25, 1.6], 'z0': 0.5, 'top': 0.8}, {'x': [1.0, 2.9], 'y': [-1.6, -1.25], 'z0': 0.5, 'top': 0.8}],
    'j31': [{'x': [-2.1, 2.1], 'y': [.1, .92], 'z0': 1.05, 'top': 1.52}, {'x': [-2.1, 2.1], 'y': [-.92, -.1], 'z0': 1.05, 'top': 1.52}],
    'h6k': [{'x': [-5.0, 2.1], 'y': [-0.85, 0.85], 'z0': 2.12, 'top': 3.4}],
    'b2': [{'x': [-2.86, 2.14], 'y': [1.02, 2.27], 'z0': 0.5, 'top': 1.4}, {'x': [-2.86, 2.14], 'y': [-2.27, -1.02], 'z0': 0.5, 'top': 1.4}],
    'x47b': [{'x': [-1.07, 2.14], 'y': [-0.75, 0.75], 'z0': 1.42, 'top': 2.0}],
    'f35': [{'x': [-2.1, 1.4], 'y': [.15, 1.05], 'z0': 1.3, 'top': 1.8}, {'x': [-2.1, 1.4], 'y': [-1.05, -.15], 'z0': 1.3, 'top': 1.8}],
    'f22a': [{'x': [0.3, 3.15], 'y': [-0.86, 0.86], 'z0': 0.15, 'top': 0.8}],   # NLM 的模型：主弹舱（侧弹舱模型里有舱内）
    'j50': [{'x': [-3.2, 1.6], 'y': [.45, 1.75], 'z0': 1.8 - LJ50 - .05, 'top': 2.06 - LJ50}, {'x': [-3.2, 1.6], 'y': [-1.75, -.45], 'z0': 1.8 - LJ50 - .05, 'top': 2.06 - LJ50}],
}
# 飞行员：头的位置（一个座舱一个）
PIT = {
    'j20': [[5.7, 0, 3.25 - LJ20]],   # 网页版 V3G_PIT 的眼位
    'f22': [[5.32, 0, 1.92]],   # 模型里有弹射座椅（头枕在 x 5.0、顶 2.16）
    'f22a': [[5.05, 0, 1.95]],   # NLM 的模型：座舱盖最高处（x 4.9～5.2、顶 2.27）往下 0.32
    'j31': [[4.3, 0, 2.72]],
    'j15': [[4.97, 0, 3.57]],
    'j15t': [[5.6, 0, 2.75]],   # 座舱盖顶（烘焙坐标 3.05）往下 0.3
    'j16': [[6.35, 0, 2.25], [5.0, 0, 2.52]],   # 前座、后座
    'j50': [[4.0, 0, 2.15]],
    'f35': [[5.0, 0, 2.95]],
}
