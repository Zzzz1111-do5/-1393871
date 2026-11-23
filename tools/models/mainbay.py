# 歼-20 弹舱照真机（用户 11-23：「检查一下 j20 弹仓打开是不是跟现实一样」「主弹仓上类似卷帘门的那种」）——成品 GLB 的最后一道加工（skinbake.py 之后）
#   对照 2018 年珠海航展歼-20 开舱的照片（主弹舱四枚霹雳-15、侧弹舱霹雳-10 转出舱外后舱门关上）：
#   · 主弹舱：两扇门在外侧铰链往下开到竖直（原来就对）。门里面是白的，一道道横肋、两条纵肋、两边的边梁——照片上像卷帘门；
#     舱里也是白的：舱顶一道道横的隔框，中间一道纵向龙骨把舱分成左右两半，每半两枚霹雳-15，各挂在一个弹射发射架下面
#   · 原模型主弹舱那里只有一层蒙皮，门上面紧贴着进气道下壁和几块内部的面，舱只有十几厘米深，弹放不进去：
#     把舱的范围里原模型的面沿盒子的面切开、里面的扔掉，挤出 0.45 米深的舱（舱壁、舱顶，正面都朝舱里）
#   · 主弹舱门前后两端是锯齿边（用户 11-23：「弹仓的开合边缘是建模的锯齿线」；照片上前端一排黄的、后端一排白的锯齿；原模型门上也画着锯齿线）：
#     原来按长方形切的门，前后端是直边——沿锯齿线把门的前后端再切一刀：齿留在门上，齿缝里那一小块归机身（关着时严丝合缝，开了门边缘是锯齿）
#   · 侧弹舱：原来的舱只有 0.3 米深，霹雳-10 的尾翼收不进去——加深到 0.42 米，舱里也改成白的
#   换新键 j20_v5（节点名 A_j20_v5__…）：元数据复制 j20_v4 那一行改键，加新零件、去掉 wells（原来那块盖在门上面的深色板会挡住新舱），
#   侧弹舱门的动法改成 bayC（先开门、挂架转出、再关门）；j20_v4 那一行的侧弹舱门也改成 bayC；alias 指到 v5、old 里加 v4；
#   ImportedTint 抄一份 v5 的（新零件按这里的颜色）
# 用法：python3 -I tools/models/mainbay.py [GLB，默认 models/air/j20.glb] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
#   要在 skinbake.py 之后跑，只跑一次（元数据里已经有 j20_v5 就不做）
import os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import airpaint   # noqa: E402  元数据那一行读回 Python（lua_parse）
import doorbay   # noqa: E402  put / material / cavity
import mdl2glb as B   # noqa: E402  B.lua 写回元数据

OLD, NEW = 'j20_v4', 'j20_v5'
WHITE = (224, 226, 218)   # 舱里、舱门里面的白漆（照片上偏一点暖）
RIB = (176, 180, 175)     # 隔框、肋条、龙骨、发射架：也是白漆，Roblox 没有环境光遮蔽，调暗一点才看得出一道道
# 主弹舱（模型坐标，格）：开口就是两扇门的范围（x ±2.184、z −6.16～5.88，门关着时上表面 3.855）
BX, BZ0, BZ1 = 2.184, -6.16, 5.88
Y_SKIN = 3.57    # 舱壁从这里起（机腹外表面 3.54 往里一点：不从外面穿出来）
Y_TOP = 5.15     # 舱顶（门上表面往里 1.3 格 ≈ 0.46 米）
CUT = (np.array([-BX + 0.012, 3.875, BZ0 + 0.012]), np.array([BX - 0.012, Y_TOP + 0.02, BZ1 - 0.012]))   # 原模型的面在这里面的切掉
# 四枚霹雳-15（弹体中心 x、z；舱外侧那两枚往后错 0.54 格，照照片错开前后）——和 AirDefs.j20 的 st 一致
PL15 = [(0.55, -0.42), (1.55, 0.12)]
PL15_D, PL15_L = 0.58, 11.2
EJ_H = 0.12      # 弹射发射架本体高（挂梁下面）：弹体顶 4.89、弹体中心 4.60（尾翼 X 形，斜着伸到 5.01，碰不到舱顶的隔框）
BEAM_H = 0.14    # 舱顶纵向挂梁高
SIDE_DEPTH = 0.42   # 侧弹舱深（米）
SAW_N, SAW_A = 3, 0.42   # 主弹舱门前后端的锯齿：每扇门几个齿、齿深（格，0.15 米）；齿尖朝外（前端朝前、后端朝后），门缝和铰链两边各是一个齿尖


def box(lo, hi, skip=()):
    """轴对齐盒子的三角形（m×3×3），正面朝外；skip 里的面不要（'-y' 贴着别的面的那一面）"""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    c = [np.array([lo[0] if i & 1 == 0 else hi[0], lo[1] if i & 2 == 0 else hi[1], lo[2] if i & 4 == 0 else hi[2]]) for i in range(8)]
    faces = {'-x': (0, 4, 6, 2), '+x': (1, 3, 7, 5), '-y': (0, 1, 5, 4), '+y': (2, 6, 7, 3), '-z': (0, 2, 3, 1), '+z': (4, 5, 7, 6)}
    out = []
    for k, (a, b, cc, d) in faces.items():
        if k in skip:
            continue
        out += [(c[a], c[b], c[cc]), (c[a], c[cc], c[d])]
    T = np.array(out)
    ctr = (lo + hi) / 2
    fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    flip = (fn * (T.mean(1) - ctr)).sum(1) < 0   # 正面朝外
    T[flip] = T[flip][:, [0, 2, 1]]
    return T


def quad(a, b, c, d, toward):
    """四边形 abcd 两个三角形，正面朝 toward 方向"""
    T = np.array([(a, b, c), (a, c, d)], float)
    fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    flip = fn @ np.asarray(toward, float) < 0
    T[flip] = T[flip][:, [0, 2, 1]]
    return T


def main_cavity():
    """主弹舱：四面舱壁 + 舱顶（正面朝舱里），白"""
    x0, x1, y0, y1, z0, z1 = -BX, BX, Y_SKIN, Y_TOP, BZ0, BZ1
    P = lambda x, y, z: np.array([x, y, z], float)   # noqa: E731
    T = [quad(P(x0, y0, z0), P(x0, y1, z0), P(x0, y1, z1), P(x0, y0, z1), (1, 0, 0)),
         quad(P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1), (-1, 0, 0)),
         quad(P(x0, y0, z0), P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0), (0, 0, 1)),
         quad(P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1), (0, 0, -1)),
         quad(P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1), (0, -1, 0))]
    return np.concatenate(T)


def main_structure():
    """舱里的结构：舱顶横隔框、舱壁竖框、中间纵向龙骨、四根挂梁、四个弹射发射架（每个两只挂钩），按 RIB 色"""
    T = []
    zs = np.arange(BZ0 + 0.55, BZ1 - 0.25, 0.95)
    for z in zs:
        T.append(box((-BX + 0.02, Y_TOP - 0.12, z - 0.05), (BX - 0.02, Y_TOP - 0.005, z + 0.05), skip=('+y',)))
        for s in (-1, 1):   # 舱壁上的竖框
            xa, xb = sorted((s * (BX - 0.005), s * (BX - 0.12)))
            T.append(box((xa, 3.93, z - 0.05), (xb, Y_TOP - 0.12, z + 0.05)))
    # 龙骨：舱顶一直下到门缝（门关着时两扇门在这里对上）
    T.append(box((-0.05, 3.90, BZ0 + 0.06), (0.05, Y_TOP - 0.005, BZ1 - 0.06), skip=('+y',)))
    T.append(box((-0.11, 3.88, BZ0 + 0.06), (0.11, 3.96, BZ1 - 0.06)))   # 龙骨下沿的缘条
    top = Y_TOP - BEAM_H - EJ_H   # 弹体顶
    for xm, zm in PL15:
        for s in (-1, 1):
            x = s * xm
            T.append(box((x - 0.09, Y_TOP - BEAM_H, zm - 4.6), (x + 0.09, Y_TOP - 0.005, zm + 4.6), skip=('+y',)))   # 挂梁
            T.append(box((x - 0.12, top, zm - 1.7), (x + 0.12, Y_TOP - BEAM_H, zm + 1.7)))                            # 发射架本体
            for dz in (-1.15, 1.15):   # 挂钩（压在弹背上）
                T.append(box((x - 0.05, top - 0.03, zm + dz - 0.12), (x + 0.05, top + 0.01, zm + dz + 0.12)))
    return np.concatenate(T)


def door_inner(side):
    """主弹舱门里面（门关着时朝上的那面）：白板 + 卷帘门那样一道道横肋、两条纵肋、两边的边梁。side 1 右门（x 0～2.184）、−1 左门。
    返回（白板, 肋条）两组三角形"""
    xa, xb = sorted((side * 0.0, side * BX))
    y = 3.862
    P = lambda x, z: np.array([x, y, z], float)   # noqa: E731
    z0, z1 = BZ0 + SAW_A + 0.06, BZ1 - SAW_A - 0.06   # 让开前后端的锯齿（齿缝那一块归机身）
    panel = quad(P(xa + 0.03, z0), P(xb - 0.03, z0), P(xb - 0.03, z1), P(xa + 0.03, z1), (0, 1, 0))
    R = []
    for z in np.arange(z0 + 0.34, z1 - 0.2, 0.62):   # 横肋：0.22 米一道
        R.append(box((xa + 0.12, y - 0.01, z - 0.03), (xb - 0.12, y + 0.12, z + 0.03), skip=('-y',)))
    for u in (1 / 3, 2 / 3):   # 纵肋
        x = xa + (xb - xa) * u
        R.append(box((x - 0.03, y - 0.01, z0 + 0.14), (x + 0.03, y + 0.085, z1 - 0.14), skip=('-y',)))
    for xe in ((xa + 0.03, xa + 0.12), (xb - 0.12, xb - 0.03)):   # 边梁（铰链那边、门缝那边）
        R.append(box((xe[0], y - 0.01, z0), (xe[1], y + 0.16, z1), skip=('-y',)))
    for ze in ((z0, z0 + 0.08), (z1 - 0.08, z1)):   # 两头的端框
        R.append(box((xa + 0.03, y - 0.01, ze[0]), (xb - 0.03, y + 0.16, ze[1]), skip=('-y',)))
    return panel, np.concatenate(R)


# ---------------------------------------------------------------- 主弹舱门前后端切成锯齿

def _clip_n(poly, n, d, keep_ge):
    """多边形留下 n·p >= d（keep_ge）或 n·p <= d 的部分（n 只看 x、z）"""
    sgn = 1.0 if keep_ge else -1.0
    out = []
    m = len(poly)
    for i in range(m):
        p, q = poly[i], poly[(i + 1) % m]
        dp, dq = sgn * (n[0] * p[0] + n[1] * p[2] - d), sgn * (n[0] * q[0] + n[1] * q[2] - d)
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            t = dp / (dp - dq)
            out.append(p + (q - p) * t)
    return out


def saw_lines():
    """锯齿线的顶点：x 从 −BX 到 BX 每半个齿一个点；前端 z = BZ0（齿尖）/ BZ0 + 齿深（齿缝），后端反过来"""
    xs = np.linspace(-BX, BX, 4 * SAW_N + 1)
    k = np.arange(len(xs)) % 2
    return xs, BZ0 + SAW_A * k, BZ1 - SAW_A * k


def saw_split(V, I, off):
    """一个舱门图元的三角形（V：顶点 [x y z nx ny nz u v]，位置是世界坐标；I：m×3）按锯齿线分成门上的、归机身的两份多边形三角形"""
    xs, zf, zr = saw_lines()
    door, edge = [], []
    for t in range(len(I)):
        tri = [V[k].copy() for k in I[t]]
        zz = [p[2] for p in tri]
        if min(zz) > BZ0 + SAW_A + 1e-6 and max(zz) < BZ1 - SAW_A - 1e-6:
            door.append(tri)
            continue
        # 按齿的折点竖着切成一条条，每条里锯齿线是一段直线
        strips = []
        rem = tri
        for j in range(1, len(xs) - 1):
            if len(rem) < 3:
                break
            left = _clip_n(rem, (1, 0), xs[j], False)
            if len(left) >= 3:
                strips.append((j - 1, left))
            rem = _clip_n(rem, (1, 0), xs[j], True)
        if len(rem) >= 3:
            strips.append((len(xs) - 2, rem))
        for j, pc in strips:
            # 前端：门那边是 z 大于这段线的；后端：z 小于这段线的
            for zl, keep_door_ge in ((zf, True), (zr, False)):
                if len(pc) < 3:
                    break
                ax, az, bx, bz = xs[j], zl[j], xs[j + 1], zl[j + 1]
                n = (-(bz - az), bx - ax)   # 线的法线，指向 z 大的那边
                d = n[0] * ax + n[1] * az
                out = _clip_n(pc, n, d, not keep_door_ge)
                if len(out) >= 3:
                    edge.append(out)
                pc = _clip_n(pc, n, d, keep_door_ge)
            if len(pc) >= 3:
                door.append(pc)
    return door, edge


def polys_to_arrays(polys):
    """多边形（扇形三角化）→ 顶点数组、索引"""
    verts, idx = [], []
    for pc in polys:
        k0 = len(verts)
        verts += pc
        for k in range(1, len(pc) - 1):
            idx.append((k0, k0 + k, k0 + k + 1))
    V = np.array(verts) if verts else np.zeros((0, 8))
    if len(V):
        V[:, 3:6] /= np.linalg.norm(V[:, 3:6], axis=1, keepdims=True) + 1e-12
    return V, np.array(idx, np.int64).reshape(-1, 3)


def write_prim(J, BIN, pr, V, I, off):
    pr['attributes'] = {'POSITION': doorbay.put(J, BIN, np.ascontiguousarray(V[:, 0:3] - off, '<f4'), 'VEC3', 5126, True),
                        'NORMAL': doorbay.put(J, BIN, np.ascontiguousarray(V[:, 3:6], '<f4'), 'VEC3', 5126),
                        'TEXCOORD_0': doorbay.put(J, BIN, np.ascontiguousarray(V[:, 6:8], '<f4'), 'VEC2', 5126)}
    pr['indices'] = doorbay.put(J, BIN, np.ascontiguousarray(I.reshape(-1), '<u4'), 'SCALAR', 5125)


def saw_doors(J, BIN, info, root, byname, W, log):
    """主弹舱四块门（BayM1_1 / _2、BayM2_1 / _2）前后端切成锯齿：齿缝里的那一块做成机身上不动的新块 BayEdge_*（同材质、同贴图坐标）"""
    made = 0
    for name in ('BayM1_1', 'BayM1_2', 'BayM2_1', 'BayM2_2'):
        ni = byname.get(name)
        if ni is None:
            continue
        off = W[ni][:3, 3]
        door_all, edge_all = [], []
        for pr in J['meshes'][J['nodes'][ni]['mesh']]['primitives']:
            att = pr['attributes']
            P = glbfix.acc_read(J, BIN, att['POSITION']).astype(np.float64) + off
            N = glbfix.acc_read(J, BIN, att['NORMAL']).astype(np.float64)
            U = glbfix.acc_read(J, BIN, att['TEXCOORD_0']).astype(np.float64)
            I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            door, edge = saw_split(np.concatenate([P, N, U], 1), I, off)
            if not edge:
                continue
            Vd, Id = polys_to_arrays(door)
            write_prim(J, BIN, pr, Vd, Id, off)
            Ve, Ie = polys_to_arrays(edge)
            edge_all.append((pr.get('material'), Ve, Ie))
        for mat, Ve, Ie in edge_all:
            made += 1
            nm = 'BayEdge_%d' % made
            lo, hi = Ve[:, 0:3].min(0), Ve[:, 0:3].max(0)
            ctr = (lo + hi) / 2
            prim = {'material': mat} if mat is not None else {}
            write_prim(J, BIN, prim, Ve, Ie, ctr)
            J['meshes'].append({'name': 'A_%s__%s' % (NEW, nm), 'primitives': [prim]})
            J['nodes'].append({'name': 'A_%s__%s' % (NEW, nm), 'mesh': len(J['meshes']) - 1, 'translation': [float(v) for v in ctr]})
            J['nodes'][root].setdefault('children', []).append(len(J['nodes']) - 1)
            src = info['parts'][name]
            info['parts'][nm] = {'c': [round(float(v), 3) for v in ctr], 's': [round(float(v), 3) for v in np.maximum(hi - lo, 0.02)], 'g': 'Body'}
            for k in ('col', 'met', 'a'):
                if k in src:
                    info['parts'][nm][k] = src[k]
            log('  %s 锯齿缝里归机身的一块 %s：%d 个三角形（%.2f～%.2f 格）' % (name, nm, len(Ie), lo[2], hi[2]))
    return made


# ---------------------------------------------------------------- 切掉盒子里的面

def _clip(poly, a, c, keep_gt):
    """Sutherland–Hodgman：多边形（顶点 = [x y z nx ny nz u v]）留下 p[a] >= c（keep_gt）或 p[a] <= c 的部分"""
    s = 1.0 if keep_gt else -1.0
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        dp, dq = s * (p[a] - c), s * (q[a] - c)
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            t = dp / (dp - dq)
            out.append(p + (q - p) * t)
    return out


def clip_out(J, BIN, pr, M, lo, hi, frame=None):
    """图元 pr（世界矩阵 M，只有平移）在盒子 lo～hi 里的部分切掉：跨盒子面的三角形沿面切开，里面的扔掉。返回（扔掉的、切开的）三角形数
    frame = (原点, 3×3 行是三根轴)：盒子在这个斜的坐标系里（侧弹舱顺着机身侧面斜着）；位置换过去切、切完换回来（插值是线性的，换不换系都一样）"""
    att = pr['attributes']
    P = glbfix.acc_read(J, BIN, att['POSITION']).astype(np.float64)
    N = glbfix.acc_read(J, BIN, att['NORMAL']).astype(np.float64)
    U = glbfix.acc_read(J, BIN, att['TEXCOORD_0']).astype(np.float64)
    I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
    off = M[:3, 3]
    W = P + off
    if frame is not None:
        O, R = frame
        W = (W - O) @ R.T
    tp = W[I]
    tmin, tmax = tp.min(1), tp.max(1)
    outside = ((tmax <= lo) | (tmin >= hi)).any(1)
    inside = ((tmin > lo) & (tmax < hi)).all(1)
    cross = ~outside & ~inside
    if not (inside.any() or cross.any()):
        return 0, 0
    V = np.concatenate([W, N, U], 1)
    newV, newI = [], []
    base = len(V)
    for t in np.nonzero(cross)[0]:
        rem = [V[k].copy() for k in I[t]]
        for a in range(3):
            for c, gt in ((lo[a], False), (hi[a], True)):   # 盒子外的那一侧：x < lo 或 x > hi
                if len(rem) < 3:
                    break
                part = _clip(rem, a, c, gt)
                if len(part) >= 3:
                    k0 = base + len(newV)
                    for p in part:
                        newV.append(p)
                    for k in range(1, len(part) - 1):
                        newI.append((k0, k0 + k, k0 + k + 1))
                rem = _clip(rem, a, c, not gt)
        # rem 剩下的在盒子里：扔掉
    keepI = I[outside]
    if newV:
        NV = np.array(newV)
        NV[:, 3:6] /= np.linalg.norm(NV[:, 3:6], axis=1, keepdims=True) + 1e-12
        V2 = np.concatenate([V, NV])
        I2 = np.concatenate([keepI, np.array(newI, np.int64)])
    else:
        V2, I2 = V, keepI
    # 没人用的顶点去掉
    used = np.unique(I2)
    remap = np.full(len(V2), -1, np.int64)
    remap[used] = np.arange(len(used))
    V2, I2 = V2[used], remap[I2]
    Pw = V2[:, 0:3]
    if frame is not None:
        Pw = Pw @ R + O
    att['POSITION'] = doorbay.put(J, BIN, np.ascontiguousarray(Pw - off, '<f4'), 'VEC3', 5126, True)
    att['NORMAL'] = doorbay.put(J, BIN, np.ascontiguousarray(V2[:, 3:6], '<f4'), 'VEC3', 5126)
    att['TEXCOORD_0'] = doorbay.put(J, BIN, np.ascontiguousarray(V2[:, 6:8], '<f4'), 'VEC2', 5126)
    pr['indices'] = doorbay.put(J, BIN, np.ascontiguousarray(I2.reshape(-1), '<u4'), 'SCALAR', 5125)
    return int(inside.sum()), int(cross.sum())


def add_node(J, BIN, info, root, key, name, C, mat, col, g='Body'):
    """同 doorbay.add_part，部件组 g 可以指定（舱门里面的白板、肋条跟着舱门转）"""
    doorbay.add_part(J, BIN, info, root, key, name, C, mat, col)
    info['parts'][name]['g'] = g


def set_mesh(J, BIN, ni, C, mat):
    """把节点 ni 的网格换成三角形 C（模型坐标）：节点挪到新包围盒中心，材质换成 mat。返回（中心, 大小）"""
    P = C.reshape(-1, 3)
    lo, hi = P.min(0), P.max(0)
    ctr = (lo + hi) / 2
    fn = np.cross(C[:, 1] - C[:, 0], C[:, 2] - C[:, 0])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    prim = {'attributes': {'POSITION': doorbay.put(J, BIN, np.ascontiguousarray(P - ctr, '<f4'), 'VEC3', 5126, True),
                           'NORMAL': doorbay.put(J, BIN, np.ascontiguousarray(np.repeat(fn, 3, axis=0), '<f4'), 'VEC3', 5126),
                           'TEXCOORD_0': doorbay.put(J, BIN, np.full((len(P), 2), 0.5, '<f4'), 'VEC2', 5126)},
            'indices': doorbay.put(J, BIN, np.arange(len(P), dtype=np.uint32), 'SCALAR', 5125), 'material': mat}
    J['meshes'][J['nodes'][ni]['mesh']]['primitives'] = [prim]
    J['nodes'][ni]['translation'] = [float(v) for v in ctr]
    return ctr, np.maximum(hi - lo, 0.02)


def compact(J, BIN):
    """换下来的旧访问器、bufferView 去掉，重新紧凑地排一遍（同 doorbay.run）"""
    usedA = sorted({i for m in J['meshes'] for p in m['primitives'] for i in list(p['attributes'].values()) + [p['indices']]})
    amap = {old: k for k, old in enumerate(usedA)}
    J['accessors'] = [J['accessors'][i] for i in usedA]
    for m in J['meshes']:
        for p in m['primitives']:
            p['attributes'] = {k: amap[v] for k, v in p['attributes'].items()}
            p['indices'] = amap[p['indices']]
    usedV = sorted({a['bufferView'] for a in J['accessors']} | {im['bufferView'] for im in J.get('images', []) if 'bufferView' in im})
    vmap, NB, views = {}, bytearray(), []
    for old in usedV:
        v = dict(J['bufferViews'][old])
        while len(NB) % 4:
            NB.append(0)
        o = v.get('byteOffset', 0)
        NB.extend(BIN[o:o + v['byteLength']])
        v['byteOffset'] = len(NB) - v['byteLength']
        vmap[old] = len(views)
        views.append(v)
    for a in J['accessors']:
        a['bufferView'] = vmap[a['bufferView']]
    for im in J.get('images', []):
        if 'bufferView' in im:
            im['bufferView'] = vmap[im['bufferView']]
    J['bufferViews'] = views
    J['buffers'][0]['byteLength'] = len(NB)
    return NB


def run(glb, meta_path, log=print):
    lines = open(meta_path, encoding='utf-8').read().split('\n')
    if any(l.startswith('    %s = {' % NEW) for l in lines):
        log('元数据里已经有 %s：做过了，不再做' % NEW)
        return
    li = next(k for k, l in enumerate(lines) if l.startswith('    %s = {' % OLD))
    info = airpaint.lua_parse(lines[li].strip()[len(OLD) + 3:].rstrip(','))
    old_info = airpaint.lua_parse(lines[li].strip()[len(OLD) + 3:].rstrip(','))
    J, BIN = glbfix.read(glb)
    BIN = bytearray(BIN)
    # —— 改键名 ——
    for nd in J['nodes']:
        nm = nd.get('name', '')
        if nm == 'A_' + OLD or nm.startswith('A_%s__' % OLD):
            nd['name'] = 'A_' + NEW + nm[len('A_' + OLD):]
    for m in J['meshes']:
        if m.get('name', '').startswith('A_%s__' % OLD):
            m['name'] = 'A_' + NEW + m['name'][len('A_' + OLD):]
    for m in J['materials']:
        if m.get('name', '').startswith('A_%s_' % OLD):
            m['name'] = 'A_' + NEW + m['name'][len('A_' + OLD):]
    W = glbfix.world_mats(J)
    root = next(i for i, nd in enumerate(J['nodes']) if 'mesh' not in nd)
    byname = {nd['name'].split('__', 1)[1]: i for i, nd in enumerate(J['nodes']) if '__' in nd.get('name', '')}

    def group_tris(g):
        out = []
        for name, ni in byname.items():
            if info['parts'].get(name, {}).get('g') != g:
                continue
            M = W[ni]
            for pr in J['meshes'][J['nodes'][ni]['mesh']]['primitives']:
                P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
                I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
                out.append(P[I])
        return np.concatenate(out) if out else np.zeros((0, 3, 3))

    # —— 0. 主弹舱门前后端切成锯齿（齿缝里的归机身） ——
    saw_doors(J, BIN, info, root, byname, W, log)
    byname = {nd['name'].split('__', 1)[1]: i for i, nd in enumerate(J['nodes']) if '__' in nd.get('name', '')}
    W = glbfix.world_mats(J)
    # —— 1. 主弹舱范围里原模型的面切掉（舱门、侧弹舱、进气道、起落架那些不动；主起落架舱前端伸进了主弹舱后角，也切） ——
    lo, hi = CUT
    nin = ncr = 0
    for name, ni in byname.items():
        g = info['parts'].get(name, {}).get('g', '')
        if g.startswith('Bay') or g.startswith('Gear') or g.startswith('GDoor') or name.startswith('Duct') or name.startswith('BayEdge') or name in ('Well_1', 'Well_2'):
            continue
        M = W[ni]
        assert np.allclose(M[:3, :3], np.eye(3)), name
        for pr in J['meshes'][J['nodes'][ni]['mesh']]['primitives']:
            a, b = clip_out(J, BIN, pr, M, lo, hi)
            nin += a
            ncr += b
    log('  主弹舱范围里原模型的面：扔掉 %d 个三角形、沿舱的面切开 %d 个' % (nin, ncr))
    # —— 2. 主弹舱：舱壁 + 舱顶（白）、结构（隔框、龙骨、挂梁、发射架） ——
    mw = doorbay.material(J, NEW, 'bay_white', WHITE)
    mr = doorbay.material(J, NEW, 'bay_rib', RIB)
    cav = main_cavity()
    stc = main_structure()
    add_node(J, BIN, info, root, NEW, 'BayCav_1', cav, mw, WHITE)
    add_node(J, BIN, info, root, NEW, 'BayCav_2', stc, mr, RIB)
    log('  主弹舱：舱壁舱顶 %d 个三角形，隔框 / 龙骨 / 挂梁 / 发射架 %d 个三角形；舱深 %.2f 米' % (len(cav), len(stc), (Y_TOP - 3.855) / 2.8))
    # —— 3. 主弹舱门里面：白板 + 卷帘门式横肋（跟着门转） ——
    for side, g in ((-1, 'BayM1'), (1, 'BayM2')):
        panel, ribs = door_inner(side)
        add_node(J, BIN, info, root, NEW, g + '_3', panel, mw, WHITE, g)
        add_node(J, BIN, info, root, NEW, g + '_4', ribs, mr, RIB, g)
        log('  %s 门里面：白板 %d、肋条 %d 个三角形' % (g, len(panel), len(ribs)))
    # —— 4. 侧弹舱加深、改白（Well_1 = 左 BaySL，Well_2 = 右 BaySR，同 doorbay 的顺序）；加深的那一截里原模型的面也切掉 ——
    for well, g in (('Well_1', 'BaySL'), ('Well_2', 'BaySR')):
        T = group_tris(g)
        Pd = T.reshape(-1, 3)
        c0 = Pd.mean(0)
        n = np.linalg.svd(Pd - c0)[2][2]
        if n @ (np.array([0.0, 7.0, c0[2]]) - c0) < 0:   # 朝机身里（同 doorbay.cavity）
            n = -n
        e3 = np.array([0.0, 0.0, 1.0])
        e1 = np.cross(n, e3)
        e1 /= np.linalg.norm(e1)
        R = np.array([e1, n, e3])
        L = (Pd - c0) @ R.T
        flo = np.array([L[:, 0].min() + 0.02, 0.10, L[:, 2].min() + 0.02])
        fhi = np.array([L[:, 0].max() - 0.02, SIDE_DEPTH * 2.8 - 0.02, L[:, 2].max() - 0.02])
        nin = ncr = 0
        for name, ni in byname.items():
            gg = info['parts'].get(name, {}).get('g', '')
            if gg.startswith('Bay') or gg.startswith('Gear') or gg.startswith('GDoor') or name.startswith('Duct') or name.startswith('Well') or name.startswith('BayCav'):
                continue
            for pr in J['meshes'][J['nodes'][ni]['mesh']]['primitives']:
                a, b = clip_out(J, BIN, pr, W[ni], flo, fhi, (c0, R))
                nin += a
                ncr += b
        log('  %s 加深的那一截里原模型的面：扔掉 %d 个三角形、切开 %d 个' % (g, nin, ncr))
        C = doorbay.cavity(T, SIDE_DEPTH, log, g)
        ctr, size = set_mesh(J, BIN, byname[well], C, mw)
        info['parts'][well].update({'c': [round(float(v), 3) for v in ctr], 's': [round(float(v), 3) for v in size], 'col': list(WHITE)})
    # —— 5. 元数据 ——
    info.pop('wells', None)   # 原来盖在主弹舱门上面的深色板：新舱比它深，留着会挡住
    for k in ('BaySL', 'BaySR'):
        info['surf'][k]['k'] = 'bayC'      # 侧弹舱门：先开门、挂架转出、再关门（AirModels.lua SURF_F.bayC）
        old_info['surf'][k]['k'] = 'bayC'
    info['bayfix'] = 'j20+main'
    BIN = glbfix.solid_textures(J, BIN, log)
    NB = compact(J, BIN)
    glbfix.write(glb, J, NB)
    lines[li] = '    %s = %s,' % (OLD, B.lua(old_info))
    lines.insert(li + 1, '    %s = %s,' % (NEW, B.lua(info)))
    txt = '\n'.join(lines)
    txt = re.sub(r'j20 = "%s"' % OLD, 'j20 = "%s"' % NEW, txt, count=1)                       # alias
    txt = re.sub(r'j20 = \{ "j20_v3"', 'j20 = { "%s", "j20_v3"' % OLD, txt, count=1)          # old
    open(meta_path, 'w', encoding='utf-8').write(txt)
    # —— 6. ImportedTint：v4 的抄一份成 v5，新零件按这里的颜色 ——
    tint_path = os.path.join(os.path.dirname(meta_path), 'ImportedTint.lua')
    tl = open(tint_path, encoding='utf-8').read().split('\n')
    add = []
    for l in tl:
        m = re.match(r'  \["A_%s__(\w+)"\] = (\{[^}]*\}),' % OLD, l)
        if m and m.group(1) not in ('Well_1', 'Well_2'):
            add.append('  ["A_%s__%s"] = %s,' % (NEW, m.group(1), m.group(2)))
    for nm, col in (('BayCav_1', WHITE), ('BayCav_2', RIB), ('BayM1_3', WHITE), ('BayM1_4', RIB), ('BayM2_3', WHITE), ('BayM2_4', RIB), ('Well_1', WHITE), ('Well_2', WHITE)):
        add.append('  ["A_%s__%s"] = { %d, %d, %d },' % (NEW, nm, *col))
    door_tint = next((re.match(r'.*= (\{[^}]*\}),', l).group(1) for l in tl if l.startswith('  ["A_%s__BayM1_1"]' % OLD)), None)
    for nm in info['parts']:
        if nm.startswith('BayEdge_') and door_tint:
            add.append('  ["A_%s__%s"] = %s,' % (NEW, nm, door_tint))
    last = max(k for k, l in enumerate(tl) if l.startswith('  ["A_%s__' % OLD))
    tl[last + 1:last + 1] = sorted(add)
    open(tint_path, 'w', encoding='utf-8').write('\n'.join(tl))
    log('  %s：写好 %s（%.1f MB）、元数据 %s 一行、ImportedTint %d 行' % (NEW, glb, os.path.getsize(glb) / 1e6, NEW, len(add)))


if __name__ == '__main__':
    run(sys.argv[1] if len(sys.argv) > 1 else 'models/air/j20.glb',
        sys.argv[2] if len(sys.argv) > 2 else 'src/ReplicatedStorage/ImportedAir.lua')
