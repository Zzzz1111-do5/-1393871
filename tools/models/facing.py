# 面的朝向：Roblox 的 MeshPart 只画正面（背面剔掉），网页版、glTF 里这些模型的材质都是双面的，看不出来——
#   原模型里朝里的面在 Roblox 里整块看不见，透过去看到的是对面那层蒙皮的里面（用户：歼-20 机头镂空、歼-16 很怪）
#   1) 单个三角形的绕向和自己三个顶点的法线相反：按法线把绕向翻过来（法线是作者模型里平滑出来的，比零散的绕向可靠）
#   2) 连通块（顶点坐标到 0.01 格相同的算连着）整块朝里：从块里挑面积大的三角形，在正、反两面各打几条射线，
#      数「打出去碰不到整架模型任何三角形」的条数——朝外那面打得出去，朝里那面会碰到对面的蒙皮；反面打出去的多就整块翻（绕向、法线一起翻）
#   整个块都在机身里面（座舱里的零件）两面都打不出去、算不出来，不动
#   3) 两面都打得出去的块是一张没有厚度的单层板（歼-16 的垂尾、天线、桨叶……原作者靠双面材质两面都看得见）：记在 c['dup']，
#      glbfix.py 给它补一份反面（不补的话 Roblox 从背面看只剩一条边，歼-16 的左垂尾从右边看像根杆子）
#   面积不到整架万分之 0.2 的小碎块不打射线（太多、看不出来）
# 用在 glbfix.py（GLB 写出后的修正，地面载具、飞机、舰艇都过一遍）
import numpy as np


def components(P, T):
    """三角形按连通块编号（顶点坐标到 0.01 格相同的算连着；标号传播 + 指针跳跃）"""
    if len(T) == 0:
        return np.zeros(0, dtype=np.int64)
    q = np.round(P * 100).astype(np.int64)
    _, vid = np.unique(q, axis=0, return_inverse=True)
    F = vid.reshape(-1)[T]
    lab = np.arange(F.max() + 1)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [0, 2]]])
    while True:
        m = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        new = lab.copy()
        np.minimum.at(new, e[:, 0], m)
        np.minimum.at(new, e[:, 1], m)
        while True:
            nn = new[new]
            if (nn == new).all():
                break
            new = nn
        if (new == lab).all():
            return lab[F[:, 0]]
        lab = new


class Caster:
    """整架模型的三角形：一条射线打出去碰不碰得到（先用包围球筛，再逐个精确求交）"""
    def __init__(self, A, B, C):
        self.A, self.E1, self.E2 = A, B - A, C - A
        self.cen = (A + B + C) / 3
        self.rad = np.sqrt(np.maximum(np.maximum(((A - self.cen) ** 2).sum(1), ((B - self.cen) ** 2).sum(1)), ((C - self.cen) ** 2).sum(1))) + 1e-4

    def escapes(self, O, D, skip):
        w = self.cen - O
        along = w @ D
        perp2 = (w * w).sum(1) - along * along
        cand = (along > -self.rad) & (perp2 < self.rad * self.rad)
        cand[skip] = False
        idx = np.nonzero(cand)[0]
        if len(idx) == 0:
            return True
        A, E1, E2 = self.A[idx], self.E1[idx], self.E2[idx]
        Pv = np.cross(D, E2)
        det = (E1 * Pv).sum(1)
        ok = np.abs(det) > 1e-12
        inv = 1.0 / np.where(ok, det, 1.0)
        Tv = O - A
        u = (Tv * Pv).sum(1) * inv
        Q = np.cross(Tv, E1)
        v = (Q @ D) * inv
        t = (E2 * Q).sum(1) * inv
        return not (ok & (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7) & (t > 1e-4)).any()


def orient(chunks, log=None):
    """chunks：[{'P': (n,3) 模型坐标, 'N': (n,3) 法线, 'T': (m,3) 索引}, …]，就地改 T（绕向）和 N（法线），c['dup'] 记要补反面的三角形；
    返回 (单个翻的三角形数, 整块翻的三角形数, 要补反面的三角形数)"""
    one = 0
    for c in chunks:
        P, N, T = c['P'], c['N'], c['T']
        if len(T) == 0:
            continue
        fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
        bad = np.einsum('ij,ij->i', fn, N[T].sum(axis=1)) < 0
        T[bad] = T[bad][:, [0, 2, 1]]
        one += int(bad.sum())
    # 整架模型的三角形（射线碰撞用）
    A = np.concatenate([c['P'][c['T'][:, 0]] for c in chunks if len(c['T'])])
    B = np.concatenate([c['P'][c['T'][:, 1]] for c in chunks if len(c['T'])])
    C = np.concatenate([c['P'][c['T'][:, 2]] for c in chunks if len(c['T'])])
    cast = Caster(A, B, C)
    total_area = np.linalg.norm(np.cross(B - A, C - A), axis=1).sum() / 2
    eps = max(1e-3, float(np.ptp(np.concatenate([A, B, C]), axis=0).max()) * 2e-4)
    base = 0
    flipped = dups = 0
    for c in chunks:
        P, N, T = c['P'], c['N'], c['T']
        m = len(T)
        c['dup'] = np.zeros(m, dtype=bool)
        if m == 0:
            continue
        comp = components(P, T)
        a, b, cc = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        fn = np.cross(b - a, cc - a)
        area = np.linalg.norm(fn, axis=1) / 2
        nrm = fn / np.maximum(2 * area, 1e-12)[:, None]
        cen = (a + b + cc) / 3
        order = np.argsort(comp, kind='stable')
        cs = comp[order]
        starts = np.r_[0, np.nonzero(np.diff(cs))[0] + 1, m]
        for k in range(len(starts) - 1):
            sel = order[starts[k]:starts[k + 1]]
            ca = area[sel].sum()
            if ca <= total_area * 2e-5:
                continue
            # 抽样：面积最大的几个 + 均匀隔开的几个（大块多抽）
            ns = 2 if ca < total_area * 1e-4 else (6 if ca < total_area * 5e-3 else 12)
            by = sel[np.argsort(-area[sel])]
            pick = list(by[:max(1, ns // 2)]) + list(by[np.linspace(0, len(by) - 1, ns - ns // 2).astype(int)])
            pick = list(dict.fromkeys(pick))
            ep = em = nr = 0
            for s in pick:
                n = nrm[s]
                if not np.isfinite(n).all() or area[s] <= 0:
                    continue
                t1 = np.cross(n, [0.0, 1.0, 0.0] if abs(n[1]) < 0.9 else [1.0, 0.0, 0.0]); t1 /= np.linalg.norm(t1)
                t2 = np.cross(n, t1)
                dirs = [n, n + 0.55 * t1, n - 0.45 * t1 + 0.4 * t2]
                gi = base + s
                for d in dirs:
                    d = d / np.linalg.norm(d)
                    ep += int(cast.escapes(cen[s] + n * eps, d, gi))
                    em += int(cast.escapes(cen[s] - n * eps, -d, gi))
                    nr += 1
            if ep < em:
                T[sel] = T[sel][:, [0, 2, 1]]
                vs = np.unique(T[sel])
                N[vs] *= -1
                flipped += len(sel)
            elif nr and ep >= 0.6 * nr and em >= 0.6 * nr:   # 两面都在外面：单层板
                c['dup'][sel] = True
                dups += len(sel)
        base += m
    if log:
        log('  面朝向：单个三角形按法线翻 %d 个，整块朝里翻 %d 个三角形，单层板补反面 %d 个' % (one, flipped, dups))
    return one, flipped, dups
