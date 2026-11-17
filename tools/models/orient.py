# 修模型里朝反了的面：网页版的材质大多是双面渲染，原作者有的整片面（歼-31 机翼下表面、歼-20 机背……）法线朝里，网页版看不出来；
#   Roblox 只画正面（MeshPart.DoubleSided 游戏脚本改不了），这些面从外面看就是透明的（用户：开飞机从下往上看没有机翼）。
# 做法：从 26 个方向各「拍」一张三角形编号图（正交投影，按深度从远到近画，近的盖住远的），每个方向第一眼看到的面：
#   正面朝着看的人 → 记一票「对」，背面朝着 → 记一票「该翻」；「该翻」的票多就把这个三角形翻过来（绕序反过来、法线取反）；
#   两边都被看到过的（单层的薄片：两面都是外面）补一个反面的三角形。从外面哪个方向都看不到的（里面、被挡住的）不动。
# 用法：from orient import fix；VB2, T2, src = fix(VB, T)（VB 每行 x y z nx ny nz u v…，T 三角形下标；src[i] = 新三角形 i 来自原来哪个三角形）
import numpy as np
from PIL import Image, ImageDraw


def directions():
    out = []
    for x in (-1, 0, 1):
        for y in (-1, 0, 1):
            for z in (-1, 0, 1):
                if x or y or z:
                    v = np.array([x, y, z], dtype=np.float64)
                    out.append(v / np.linalg.norm(v))
    return out


def basis(d):
    a = np.array([0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(a, d)
    u /= np.linalg.norm(u)
    v = np.cross(d, u)
    return u, v


def votes(P, T, res=900):
    """每个三角形：正面被看到的方向数、背面被看到的方向数"""
    n = len(T)
    G = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    good = np.zeros(n, dtype=np.int32)
    bad = np.zeros(n, dtype=np.int32)
    lo, hi = P.min(0), P.max(0)
    ext = float(np.max(hi - lo))
    px = ext / res
    for d in directions():
        u, v = basis(d)
        U, W, D = P @ u, P @ v, P @ d
        u0, w0 = U.min(), W.min()
        wpx, hpx = int((U.max() - u0) / px) + 3, int((W.max() - w0) / px) + 3
        img = Image.new('RGB', (wpx, hpx), (0, 0, 0))
        dr = ImageDraw.Draw(img)
        order = np.argsort(D[T].mean(1))   # 远的先画（看的人在 +d 那边）
        UU = (U[T] - u0) / px + 1
        WW = (W[T] - w0) / px + 1
        for t in order:
            i = int(t) + 1
            dr.polygon([(UU[t, 0], WW[t, 0]), (UU[t, 1], WW[t, 1]), (UU[t, 2], WW[t, 2])], fill=(i & 255, (i >> 8) & 255, (i >> 16) & 255))
        a = np.asarray(img, dtype=np.int64)
        ids = (a[:, :, 0] | (a[:, :, 1] << 8) | (a[:, :, 2] << 16)).reshape(-1)
        ids = ids[ids > 0] - 1
        seen = np.bincount(ids, minlength=n) >= 2   # 至少两个像素才算看到
        facing = (G @ d) > 0
        good += seen & facing
        bad += seen & ~facing
    return good, bad


def fix(VB, T, res=900):
    P = VB[:, 0:3]
    good, bad = votes(P, T, res)
    flip = bad > good
    both = (good > 0) & (bad > 0) & ~flip & (np.minimum(good, bad) >= 2)   # 两边都被看到过好几次：单层薄片，补反面
    both |= flip & (good >= 2)
    # 翻面 / 补反面的三角形用新的顶点（法线取反），不影响和它共用顶点的别的三角形
    VB2 = [VB]
    T2 = T.copy()
    src = list(range(len(T)))
    base = len(VB)

    def flipped(rows):
        nonlocal base
        idx = np.unique(T[rows].reshape(-1))
        V = VB[idx].copy()
        V[:, 3:6] *= -1
        remap = {int(o): base + k for k, o in enumerate(idx)}
        base += len(idx)
        VB2.append(V)
        tri = np.array([[remap[int(a)] for a in T[r][[0, 2, 1]]] for r in rows], dtype=T.dtype).reshape(-1, 3)
        return tri
    fr = np.where(flip)[0]
    if len(fr):
        T2[fr] = flipped(fr)
    dup = np.where(both)[0]
    extra = []
    if len(dup):
        # 补的反面：和原来那个三角形朝向相反（原来翻过的，反面就是原样）
        rows_keep = dup[~flip[dup]]
        rows_flip = dup[flip[dup]]
        if len(rows_keep):
            extra.append(flipped(rows_keep))
            src += rows_keep.tolist()
        if len(rows_flip):
            extra.append(T[rows_flip].copy())
            src += rows_flip.tolist()
    T3 = np.concatenate([T2] + extra) if extra else T2
    stats = {'flip': int(flip.sum()), 'dup': int(both.sum()), 'seen': int(((good + bad) > 0).sum()), 'n': len(T)}
    return np.vstack(VB2), T3, np.array(src, dtype=np.int64), stats
