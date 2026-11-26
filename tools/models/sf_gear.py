# sf_air.py 的帮手：原模型自带「放下 / 收起」两套起落架网格的飞机（bohmerang 的苏-57、苏-35、米格-29：landingOn 是放下的支柱、机轮和打开的舱门，
#   landingOff 是收起后关好的舱门），照真机做收放（用户 11-26：「有些飞机起落架是你自己做的 收放逻辑也跟现实中不一样 你也去找资源改了」）；
#   还有原模型自己的尾喷口拆成推力矢量部件（用户 11-26：「很多飞机的发动机不止可以缩放 还可以3纬运动」）。
#
#   起落架（SPEC 的 legs）：每条腿是一个关键帧部件（air_kf 的 kf，ch = gear：0 收起～1 放下），绕支柱顶的铰链转——
#     p 铰链点、to 收好以后机轮中心在哪（铰链轴、转角按「机轮从放下的位置转到 to」自动算：一根斜轴转一下，同真机的单轴收放），
#     tw 支柱自转（度：苏-27 一族主轮边收边转 90° 躺平进舱，正负号自动挑让机轮往机身里面躺的那边），win 这条腿在 gear 的哪一段里动
#     （默认 [0.2, 1]：放的时候先开门、再放腿；收的时候先收腿、最后关门）
#   舱门（SPEC 的 doors）：landingOn 里打开着的门（sel）配 landingOff 里关好的门板（off）——两种样子拟合出这扇门的铰链（门板上离打开的门最近的那一溜点就是铰链线，
#     再绕它找转角、最后迭代最近点细调），做成关键帧部件：gear 0～0.2 之间关上 / 打开；收到底（gear = 0）换成 landingOff 的门板（部件 GearUp，蒙皮贴合）
#   只有关好样子、没有打开样子的门板（flap：苏-57 前起落架舱前段）：沿外侧长边往下翻开 A 度当打开
#   landingOn 里别的（舱里的作动筒、支架）：部件 GearX，收到底时藏起来
#
#   喷口（SPEC 的 nozzles）：外筒（整圈的那一块）+ 调节片（一片一个连通块）——外筒、调节片一起绕喉道（外筒前沿的圆心）偏转；
#     调节片按方位分成 n 组（一组一片调节片 + 一片密封片 + 里层），每组绕自己前沿的切线铰链开合（慢车微张、军推收拢、加力张开）
#     tv：'3d' 全向（苏-57 AL-41F1）、('pl', 32) 每个喷口只在外倾 32° 的斜面里偏（苏-35S 117S）、None 只开合不偏（米格-29）；A 最大偏角（度）
import math
import numpy as np
from scipy.spatial import cKDTree

import air_kf as KF


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def rot(axis, ang):
    """绕单位轴转 ang 弧度的矩阵（列向量：v' = R @ v）"""
    a = unit(axis)
    x, y, z = a
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def axis_angle(R):
    """转动矩阵 → (单位轴, 角)"""
    ang = math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2)))
    if ang < 1e-9:
        return np.array([1.0, 0, 0]), 0.0
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    if np.linalg.norm(ax) < 1e-9:   # 转了 180°：取 R + I 最大的那一列
        M = R + np.eye(3)
        ax = M[:, np.argmax(np.linalg.norm(M, axis=0))]
    return unit(ax), ang


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def sample(P, T, n=4000, seed=1):
    """三角形面上按面积均匀撒点（拟合舱门用：顶点太稀、分布不均）"""
    A = P[T[:, 0]]
    B = P[T[:, 1]]
    C = P[T[:, 2]]
    ar = np.linalg.norm(np.cross(B - A, C - A), axis=1) / 2
    if ar.sum() <= 0:
        return P.copy()
    rng = np.random.default_rng(seed)
    k = rng.choice(len(T), size=n, p=ar / ar.sum())
    u, v = rng.random(n), rng.random(n)
    m = u + v > 1
    u[m], v[m] = 1 - u[m], 1 - v[m]
    return A[k] + (B[k] - A[k]) * u[:, None] + (C[k] - A[k]) * v[:, None]


def kabsch(X, Y):
    """X → Y 的刚体变换（R, t）：Y ≈ X @ R.T + t"""
    cx, cy = X.mean(0), Y.mean(0)
    H = (X - cx).T @ (Y - cy)
    U, _, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1, 1, d])
    R = Vt.T @ D @ U.T
    return R, cy - R @ cx


def fit_door(Sc, So, log=None):
    """关好的门板（撒点 Sc）→ 打开的门（撒点 So）的刚体变换：门板上离打开的门最近的那一溜点是铰链线（转的时候铰链附近几乎不动），
    绕它每 1° 找转角，再迭代最近点（去掉最差的两成）细调。返回 (R, t, 平均残差 米)"""
    tree = cTree = cKDTree(So)
    d0, _ = cTree.query(Sc)
    near = Sc[d0 <= np.quantile(d0, 0.12)]
    c = near.mean(0)
    _, _, Vt = np.linalg.svd(near - c)
    a = Vt[0]
    best = None
    for deg in range(-180, 180):
        R = rot(a, math.radians(deg))
        Q = (Sc - c) @ R.T + c
        e = tree.query(Q)[0].mean()
        if best is None or e < best[0]:
            best = (e, R, c - R @ c)
    _, R, t = best
    for _ in range(40):
        Q = Sc @ R.T + t
        d, j = tree.query(Q)
        keep = d <= np.quantile(d, 0.8)
        R2, t2 = kabsch(Sc[keep], So[j[keep]])
        if np.allclose(R2, R, atol=1e-7) and np.allclose(t2, t, atol=1e-7):
            break
        R, t = R2, t2
    e = tree.query(Sc @ R.T + t)[0]
    if log:
        log('    舱门拟合：初始铰链 %s、残差 %.1f 毫米（中位 %.1f）' % (np.round(a, 3), e.mean() * 1000, np.median(e) * 1000))
    return R, t, float(e.mean())


def screw(R, t, near):
    """刚体变换 x' = R x + t 拆成螺旋运动：轴 a、角 ang、轴上一点 c（离 near 最近）、沿轴的平移 dpar"""
    a, ang = axis_angle(R)
    dpar = (t @ a) * a
    tp = t - dpar
    c, *_ = np.linalg.lstsq(np.eye(3) - R, tp, rcond=None)
    c = c + ((near - c) @ a) * a   # 挪到轴上离门中心最近的那一点
    return a, ang, c, dpar


def kf_entry(p, frames, ch='gear', extra=None):
    """关键帧部件：支点 p、每帧 (R, d)（绕 p 转 R、p 挪 d），frames[0] 是 gear = 0 那一帧、最后一帧是 gear = 1"""
    key = []
    for R, d in frames:
        q = KF.mat_q(R)
        key.append([round(float(x), 5) for x in d] + [round(float(x), 6) for x in q])
    for j in range(1, len(key)):   # 四元数同号（插值走近路）
        if np.dot(key[j][3:], key[j - 1][3:]) < 0:
            key[j][3:] = [-v for v in key[j][3:]]
    e = {'k': 'kf', 'ch': ch, 'p': [round(float(x), 5) for x in p], 'key': key}
    if extra:
        e.update(extra)
    return e


NK = 13   # 关键帧数（gear 0～1 等分；游戏里两帧之间按 CFrame:Lerp 插值）


def us():
    return [j / (NK - 1) for j in range(NK)]


def leg_frames(Vs, spec, log=None):
    """一条腿（Vs：各连通块放下时的顶点，网页版坐标、地面 z = 0）的关键帧：放下是原样（单位变换），收起 = 绕 p 先自转 tw 再沿斜轴转到 to"""
    p = np.asarray(spec['p'], dtype=np.float64)
    V = np.concatenate(Vs)
    # 机轮中心：着地的那几块（轮胎；双轮的前起落架两个一起）的包围盒中心
    z0 = V[:, 2].min()
    tyre = [Q for Q in Vs if Q[:, 2].min() < z0 + 0.03]
    T_ = np.concatenate(tyre)
    W = (T_.min(0) + T_.max(0)) / 2
    if spec.get('w'):
        W = np.asarray(spec['w'], dtype=np.float64)
    sax = unit(spec.get('sax', [0, 0, 1]))   # 支柱轴（自转绕它）
    tw = math.radians(spec.get('tw', 0))
    T = np.asarray(spec['to'], dtype=np.float64)
    best = None
    for sg in ((1, -1) if tw else (1,)):
        Rt = rot(sax, sg * tw)
        a = Rt @ (W - p)
        b = unit(T - p) * np.linalg.norm(a)
        ax = unit(np.cross(a, b))
        ang = math.acos(max(-1.0, min(1.0, unit(a) @ unit(b))))
        Rh = rot(ax, ang)
        Rf = Rh @ Rt
        Q = (V - p) @ Rf.T + p
        score = Q[:, 2].mean()   # 自转选让整条腿收得更高（往机身里面躺）的那一边
        if best is None or score > best[0]:
            best = (score, sg, ax, ang)
    _, sg, ax, ang = best
    u0, u1 = spec.get('win', (0.2, 1.0))
    frames = []
    for u in us():
        s = 1 - smooth((u - u0) / (u1 - u0))   # 1 收起、0 放下
        R = rot(ax, ang * s) @ rot(sax, sg * tw * s)
        frames.append((R, np.zeros(3)))
    if log:
        Q = (V - p) @ frames[0][0].T + p
        lo = int(np.argmin(Q[:, 2]))
        log('    %s：铰链 %s、轴 %s、转 %.0f°、自转 %.0f°；机轮 %s → 收好 %s；收好后最低点 z %.2f（原来在 %s）' % (
            spec['g'], np.round(p, 2), np.round(ax, 3), math.degrees(ang), math.degrees(sg * tw), np.round(W, 2),
            np.round(frames[0][0] @ (W - p) + p, 2), Q[:, 2].min(), np.round(V[lo], 2)))
    return p, frames


def door_frames(R_co, t_co, Vo, win=(0.0, 0.2), log=None, name=''):
    """打开的门（原样）→ 关上：R_co / t_co 是关好的门板 → 打开的门；关上 = 它的逆；gear 在 win 里从关到开"""
    Ri = R_co.T
    ti = -Ri @ t_co
    a, ang, c, dpar = screw(Ri, ti, Vo.mean(0))
    u0, u1 = win
    frames = []
    for u in us():
        s = 1 - smooth((u - u0) / (u1 - u0))   # 1 关上、0 打开
        frames.append((rot(a, ang * s), dpar * s))
    if log:
        log('    %s：铰链轴 %s 过 %s、关上转 %.0f°（沿轴挪 %.1f 毫米）' % (name, np.round(a, 3), np.round(c, 2), math.degrees(ang), np.linalg.norm(dpar) * 1000))
    return c, frames


def flap_frames(V, A_deg, win=(0.0, 0.2), log=None, name=''):
    """只有关好样子的门板（V）：沿外侧长边（|y| 最大的那条，方向按门板的长轴）往下翻开 A 度；gear = 0 关着、win 以后开着"""
    c0 = V.mean(0)
    _, _, Vt = np.linalg.svd(V - c0)
    a = unit(Vt[0])
    ay = np.abs(V[:, 1])
    edge = V[ay > ay.max() - 0.03]
    c = edge.mean(0)
    want = np.array([0.0, 0.0, -1.0])
    ang = math.radians(A_deg)
    if (rot(a, ang) @ (c0 - c)) @ want < (rot(a, -ang) @ (c0 - c)) @ want:   # 门的中间要往下翻
        ang = -ang
    u0, u1 = win
    frames = []
    for u in us():
        s = smooth((u - u0) / (u1 - u0))   # 0 关、1 开
        frames.append((rot(a, ang * s), np.zeros(3)))
    if log:
        log('    %s：外侧铰链 %s 过 %s、翻开 %.0f°' % (name, np.round(a, 3), np.round(c, 2), math.degrees(ang)))
    return c, frames


def oc_frames(V, A_deg, win=(0.0, 0.15, 0.85, 1.0), log=None, name=''):
    """放下、收起两头都关着、中间开着的门（V：关着的样子）——苏-57 前轮舱前段：前门打开 → 前起落架放下 / 收起 → 前门再关上；
    沿外侧长边（|y| 最大的那条）往下翻开 A 度"""
    c0 = V.mean(0)
    _, _, Vt = np.linalg.svd(V - c0)
    a = unit(Vt[0])
    ay = np.abs(V[:, 1])
    edge = V[ay > ay.max() - 0.03]
    c = edge.mean(0)
    want = np.array([0.0, 0.0, -1.0])
    ang = math.radians(A_deg)
    if (rot(a, ang) @ (c0 - c)) @ want < (rot(a, -ang) @ (c0 - c)) @ want:
        ang = -ang
    w0, w1, w2, w3 = win
    frames = []
    for u in us():
        if u <= w1:
            s = smooth((u - w0) / (w1 - w0))
        elif u < w2:
            s = 1.0
        else:
            s = 1 - smooth((u - w2) / (w3 - w2))
        frames.append((rot(a, ang * s), np.zeros(3)))
    if log:
        log('    %s：外侧铰链 %s 过 %s、中途翻开 %.0f°（两头关着）' % (name, np.round(a, 3), np.round(c, 2), math.degrees(ang)))
    return c, frames


def sdoor_frames(V, spec, log=None, name=''):
    """只有打开样子的舱门（起落架和机身一个网格的模型，苏-25）：铰链是门板最高的那条长边（门挂在舱边上），
    关上 = 绕它转到门板躺平（法线朝下）、门的中间往上翻；spec 的 A 可以直接给关上转多少度。gear 在 win（默认 0～0.2）里关 → 开"""
    c0 = V.mean(0)
    _, _, Vt = np.linalg.svd(V - c0)
    a = unit(Vt[0])                      # 长边方向
    top = V[V[:, 2] > V[:, 2].max() - 0.04]
    c = top.mean(0)
    nrm = unit(Vt[2])                    # 门板法线
    if spec.get('A') is not None:
        cands = [math.radians(spec['A']), -math.radians(spec['A'])]
    else:   # 转到法线朝上 / 朝下（躺平）：两个方向各试，挑门中间往上走的那个
        cands = []
        for sg in (1, -1):
            best = min(range(0, 181), key=lambda d: abs(abs((rot(a, sg * math.radians(d)) @ nrm)[2]) - 1))
            cands.append(sg * math.radians(best))
    ang = max(cands, key=lambda an: (rot(a, an) @ (c0 - c))[2])
    u0, u1 = spec.get('win', (0.0, 0.2))
    frames = []
    for u in us():
        s = 1 - smooth((u - u0) / (u1 - u0))   # 1 关上、0 打开（原样）
        frames.append((rot(a, ang * s), np.zeros(3)))
    if log:
        log('    %s：铰链 %s 过 %s、关上转 %.0f°' % (name, np.round(a, 3), np.round(c, 2), math.degrees(ang)))
    return c, frames


def nozzle_parts(comps, spec, side, log=None):
    """一个喷口：comps 是 [(下标, 顶点 V)]（网页版坐标、地面 z = 0），挑出外筒和按方位分组的调节片。
    返回 ({下标: 部件名}, {部件名: surf 项})"""
    g = spec['g'] + ('L' if side > 0 else 'R')
    n = spec.get('n', 16)
    allV = np.concatenate([V for _, V in comps])
    # 外筒：整圈的那一块（左右、上下都跨过喷口中心）里最大的
    cy, cz = (allV[:, 1].min() + allV[:, 1].max()) / 2, (allV[:, 2].min() + allV[:, 2].max()) / 2
    ring = [(k, V) for k, V in comps if V[:, 1].min() < cy - 0.1 and V[:, 1].max() > cy + 0.1 and V[:, 2].min() < cz - 0.1 and V[:, 2].max() > cz + 0.1]
    shell = max(ring, key=lambda kv: len(kv[1]))
    S = shell[1]
    # 喷口轴：沿 x 切几片，每片的点拟合一个圆（外筒、调节片都是绕轴的回转面），圆心连成的线就是轴（外筒前沿是斜的、不是平的一圈，不能拿前后两圈的包围盒中心）
    xs0, xs1 = allV[:, 0].min(), allV[:, 0].max()
    cs = []
    for k in range(7):
        a_, b_ = xs0 + (xs1 - xs0) * k / 7, xs0 + (xs1 - xs0) * (k + 1) / 7
        Q = allV[(allV[:, 0] >= a_) & (allV[:, 0] < b_)]
        if len(Q) < 24:
            continue
        y, z = Q[:, 1], Q[:, 2]
        M = np.stack([y, z, np.ones_like(y)], axis=1)   # Kasa：y² + z² + D y + E z + F = 0
        sol, *_ = np.linalg.lstsq(M, -(y * y + z * z), rcond=None)
        yc, zc = -sol[0] / 2, -sol[1] / 2
        if math.hypot(yc - cy, zc - cz) < 0.5:
            cs.append(((a_ + b_) / 2, yc, zc))
    cs = np.array(cs)
    ky = np.polyfit(cs[:, 0], cs[:, 1], 1)
    kz = np.polyfit(cs[:, 0], cs[:, 2], 1)
    aft = unit([-1.0, -ky[0], -kz[0]])
    xf = S[:, 0].max()   # 支点：轴上外筒前沿那一处（整个喷口绕这里偏转）
    pf = np.array([xf, np.polyval(ky, xf), np.polyval(kz, xf)])
    out, surf = {}, {}
    out[shell[0]] = g
    tv = spec.get('tv')
    e = {'k': 'noz', 'p': [round(float(x), 4) for x in pf], 'a': [round(float(x), 5) for x in aft], 'A': spec.get('A', 15)}
    if tv == '3d':
        e['tv'] = '3d'
    elif isinstance(tv, (list, tuple)) and tv[0] == 'pl':
        e['tv'], e['cant'] = 'pl', tv[1]
    surf[g] = e
    # 调节片：按方位分组；每组的铰链在这一组外调节片前沿（离喷口轴最远、最靠前那一溜）
    up = unit(np.array([0, 0, 1.0]) - aft * aft[2])
    rt = unit(np.cross(up, aft))   # 网页版：y 左，这里 rt 朝哪边无所谓，只用来算方位角
    groups = {}
    for k, V in comps:
        if k == shell[0]:
            continue
        c = V.mean(0) - pf
        c = c - aft * (c @ aft)
        th = math.atan2(c @ up, c @ rt) % (2 * math.pi)
        j = int(round(th / (2 * math.pi) * n)) % n
        groups.setdefault(j, []).append((k, V))
    for j, lst in sorted(groups.items()):
        pg = '%s%02d' % ('Pet' + g[3:], j + 1)   # PetL01…
        Vall = np.concatenate([V for _, V in lst])
        for k, _ in lst:
            out[k] = pg
        rel = Vall - pf
        ax_d = rel @ aft
        rad_ = np.linalg.norm(rel - np.outer(ax_d, aft), axis=1)
        # 前沿：这一组外层的点里最靠前（离外筒近）的那一段
        outer = Vall[rad_ > np.quantile(rad_, 0.6)]
        od = (outer - pf) @ aft
        hp = outer[od < od.min() + 0.06].mean(0)
        th = (2 * math.pi) * j / n
        rdir = unit(math.cos(th) * rt + math.sin(th) * up)
        tang = unit(np.cross(aft, rdir))
        # 正角度：调节片后缘往外张
        tail = Vall[np.argmax((Vall - pf) @ aft)]
        R_ = rot(tang, 0.2)
        moved = R_ @ (tail - hp) + hp
        sg = 1 if (moved - tail) @ rdir > 0 else -1
        surf[pg] = {'k': 'pet', 'n': g, 'p': [round(float(x), 4) for x in hp], 'a': [round(float(x), 5) for x in tang], 'sg': sg,
                    'A': spec.get('pa', 10), 'r0': spec.get('r0', 0.3)}
    if log:
        log('    %s：外筒 %d 个顶点、喉道 %s、往后 %s、%d 组调节片（%d 块）%s' % (g, len(S), np.round(pf, 2), np.round(aft, 3), len(groups),
                                                                 len(comps) - 1, ('、推力矢量 %s' % (tv,)) if tv else ''))
    return out, surf
