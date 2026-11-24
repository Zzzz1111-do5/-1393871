# 从原车模型挖内腔（用户 11-23：「改成在原车内部雕刻出来内饰」「这样各种载具的从外面可以看得见的窗户跟内部的内饰就能对得上了」）
#   原车 GLB（models/veh/<模型键>.glb，坐标同 ImportedMeta：格，原点车底中心，X 右、Y 上、−Z 朝前）→
#   ① 车体（或炮塔）的三角形体素化，封住小缝，从外面灌水：灌不到的就是车的实体；
#   ② 实体里离外表面超过壁厚 t 的部分 = 内腔，再按配置的盒子、切面（发动机舱隔板、炮塔前面的厚装甲……）、车轮 / 履带让开的地方截一截；
#   ③ 内腔表面（Marching Cubes，按到外表面的距离场抽，平面是平的）朝里（从车里看得见、从车外看不见），按朝向分地板 / 墙顶两块，减面；
#   ④ 窗户：配置里点名的玻璃块（或贴图上的玻璃色）后面那片内壁挖掉——车里看出去就是原车的那块玻璃，车外隔着玻璃看得见车里；
#      玻璃拆成单独的透明块（Glass_*）；原模型里自带的简易内饰（深在实体里的三角形）挪到 Inside_* 块，游戏里有内饰时藏起来；
#   ⑤ 炮塔：座圈那一圈车体内腔的顶挖开、炮塔内腔的底挖开，两块连通（炮塔篮、座圈由内饰代码补）
# 输出：GLB 里新节点 V_<键>__Cav<空间名>Floor_1 / Cav<空间名>Wall_1 / Glass_* / Inside_*（ImportedMeta 那一行跟着改），
#   src/ReplicatedStorage/CavityMesh/<键>.lua（没重新导入时客户端用 EditableMesh 现生成，格式同 OpticMesh），
#   src/ReplicatedStorage/CavityMeta.lua（内饰代码摆东西用：每个空间的地板 / 顶高度表、窗户、舱盖）
# 用法（仓库根目录）：python3 -I tools/models/carve.py <模型键 …> [preview=<目录>] [nowrite]（配置 tools/models/carve.json）
import base64, json, math, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage import measure
import fast_simplification
import glbio
import glbfix
import vehrws
import mdl2glb as B
import airpaint

ROOT = os.path.dirname(os.path.dirname(HERE))
META_LUA = os.path.join(ROOT, 'src/ReplicatedStorage/ImportedMeta.lua')
CAVMETA_LUA = os.path.join(ROOT, 'src/ReplicatedStorage/CavityMeta.lua')
CAVMESH_DIR = os.path.join(ROOT, 'src/ReplicatedStorage/CavityMesh')
CFG = json.load(open(os.path.join(HERE, 'carve.json'), encoding='utf-8'))
MAXVOX = 30e6


def log(*a):
    print(*a, flush=True)


ORIG_DIR = os.path.join(HERE, 'carve_orig')


def pristine(key):
    """原车 GLB 和元数据那一行的原样（第一次挖时记下：GLB 是 git 里的 blob 号，元数据那一行存 carve_orig/<键>.lua）——
    重跑永远从原样开始，块名不会越拆越多"""
    os.makedirs(ORIG_DIR, exist_ok=True)
    mp = os.path.join(ORIG_DIR, key + '.lua')
    cfg = CFG[key]
    path = os.path.join(ROOT, 'models/veh/%s.glb' % key)
    sha = cfg.get('orig')
    if not sha:
        sha = subprocess.run(['git', 'rev-parse', 'HEAD:models/veh/%s.glb' % key], capture_output=True, text=True, cwd=ROOT).stdout.strip()
        assert sha, '找不到 git 里的原样：models/veh/%s.glb' % key
        cfg['orig'] = sha
        import jsondump
        allc = json.load(open(os.path.join(HERE, 'carve.json'), encoding='utf-8'))
        allc[key]['orig'] = sha
        open(os.path.join(HERE, 'carve.json'), 'w', encoding='utf-8').write(jsondump.dump(allc) + '\n')
    if not os.path.exists(mp):
        lines = subprocess.run(['git', 'show', 'HEAD:src/ReplicatedStorage/ImportedMeta.lua'], capture_output=True, text=True, cwd=ROOT).stdout.split('\n')
        ln = next(x for x in lines if x.startswith('    %s = { ' % key))
        open(mp, 'w', encoding='utf-8').write(ln + '\n')
    glb = subprocess.run(['git', 'cat-file', 'blob', sha], capture_output=True, cwd=ROOT).stdout
    assert glb[:4] == b'glTF', 'git blob %s 不是 GLB' % sha
    tmp = os.path.join(ORIG_DIR, '.%s.glb' % key)
    open(tmp, 'wb').write(glb)
    meta_line = open(mp, encoding='utf-8').read().rstrip('\n')
    return tmp, meta_line


def load_meta():
    out = subprocess.run(['lune', 'run', os.path.join(HERE, 'meta2json.luau'), META_LUA], capture_output=True, text=True, cwd=ROOT)
    if out.returncode != 0:
        raise SystemExit('读不了 ImportedMeta：' + out.stderr)
    return json.loads(out.stdout)


def group_of(pn):
    return pn.rsplit('_', 1)[0]


def is_wheel(g):
    return len(g) >= 2 and g[0] == 'W' and g[1:].isdigit()


# ---------------------------------------------------------------- 体素化
def raster(T, lo, h, shape):
    grid = np.zeros(shape, dtype=bool)
    e = np.max(np.stack([np.linalg.norm(T[:, 1] - T[:, 0], axis=1), np.linalg.norm(T[:, 2] - T[:, 0], axis=1),
                         np.linalg.norm(T[:, 2] - T[:, 1], axis=1)]), axis=0)
    nseg = np.clip(np.ceil(e / (0.45 * h)).astype(int), 1, 4000)
    for nv in np.unique(nseg):
        sel = T[nseg == nv]
        ii, jj = np.meshgrid(np.arange(nv + 1), np.arange(nv + 1), indexing='ij')
        msk = ii + jj <= nv
        a = (ii[msk] / nv)[None, :, None]
        b = (jj[msk] / nv)[None, :, None]
        step = max(1, int(2e6 // max(1, a.shape[1])))
        for s in range(0, len(sel), step):
            S = sel[s:s + step]
            pts = S[:, 0, None, :] + a * (S[:, 1] - S[:, 0])[:, None, :] + b * (S[:, 2] - S[:, 0])[:, None, :]
            q = np.floor((pts.reshape(-1, 3) - lo) / h).astype(np.int64)
            ok = np.all((q >= 0) & (q < np.array(shape)), axis=1)
            q = q[ok]
            grid[q[:, 0], q[:, 1], q[:, 2]] = True
    return grid


def solidify(surf, close):
    st = ndimage.generate_binary_structure(3, 1)
    dil = ndimage.binary_dilation(surf, structure=st, iterations=close) if close > 0 else surf
    lab, nl = ndimage.label(~dil)
    faces = [lab[0], lab[-1], lab[:, 0], lab[:, -1], lab[:, :, 0], lab[:, :, -1]]
    border = np.unique(np.concatenate([f.ravel() for f in faces]))
    border = border[border > 0]
    outside = np.isin(lab, border)
    solid = ~outside
    if close > 0:
        solid = ndimage.binary_erosion(solid, structure=st, iterations=close, border_value=0) | surf
    return solid


def tri_samples(T, spacing):
    """三角形上均匀撒点（间距不超过 spacing），返回点和所属三角形号"""
    e = np.max(np.stack([np.linalg.norm(T[:, 1] - T[:, 0], axis=1), np.linalg.norm(T[:, 2] - T[:, 0], axis=1),
                         np.linalg.norm(T[:, 2] - T[:, 1], axis=1)]), axis=0)
    nseg = np.clip(np.ceil(e / spacing).astype(int), 1, 2000)
    P, I = [], []
    for nv in np.unique(nseg):
        sel = np.nonzero(nseg == nv)[0]
        ii, jj = np.meshgrid(np.arange(nv + 1), np.arange(nv + 1), indexing='ij')
        msk = ii + jj <= nv
        a = (ii[msk] / nv)[None, :, None]
        b = (jj[msk] / nv)[None, :, None]
        S = T[sel]
        pts = S[:, 0, None, :] + a * (S[:, 1] - S[:, 0])[:, None, :] + b * (S[:, 2] - S[:, 0])[:, None, :]
        P.append(pts.reshape(-1, 3))
        I.append(np.repeat(sel, a.shape[1]))
    return np.concatenate(P), np.concatenate(I)


def seal_tris(b):
    """补盖：一块轴对齐的平板（x0,x1,y0,y1,z0,z1 里有一对相等的就是那个方向的平面）"""
    x0, x1, y0, y1, z0, z1 = b
    if abs(y1 - y0) < 1e-6:
        c = np.array([[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]], dtype=np.float64)
    elif abs(x1 - x0) < 1e-6:
        c = np.array([[x0, y0, z0], [x0, y1, z0], [x0, y1, z1], [x0, y0, z1]], dtype=np.float64)
    else:
        c = np.array([[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]], dtype=np.float64)
    return np.array([[c[0], c[1], c[2]], [c[0], c[2], c[3]]])


def open_windows(gspec):
    """glass.open：每个窗口一圈角点（格，顺着转一圈），扇形三角化"""
    out = []
    for poly in gspec.get('open', []):
        P = np.array(poly, dtype=np.float64)
        for i in range(1, len(P) - 1):
            out.append([P[0], P[i], P[i + 1]])
    return np.array(out, dtype=np.float64).reshape(-1, 3, 3)


# ---------------------------------------------------------------- 约束（正 = 允许内腔在这里）
def box_sd(X, Y, Z, b):
    return np.minimum.reduce([X - b[0], b[1] - X, Y - b[2], b[3] - Y, Z - b[4], b[5] - Z])


def plane_sd(X, Y, Z, n, d):
    n = np.array(n, dtype=np.float64)
    n /= np.linalg.norm(n)
    return d - (n[0] * X + n[1] * Y + n[2] * Z)


def wheel_sd(X, Y, Z, wheels, parts, margin, tracked):
    out = None
    if not wheels:
        return None
    if tracked:
        # 履带：两边各一个让开的区域（|x| 大于负重轮内侧、y 低于负重轮顶 + 履带）——上面的翼子板空间（叶子板下）留给内腔
        road = [w for w in wheels.values() if w['r'] > 0.6]
        if not road:
            return None
        xin = min(abs(w['c'][0]) for w in road)
        wid = 0.5
        for k, w in wheels.items():
            p = parts.get(k + '_1')
            if p and w['r'] > 0.6:
                wid = max(wid, p['s'][0])
        xin -= wid / 2 + margin
        ytop = max(w['c'][1] + w['r'] for w in road) + 0.35 + margin
        out = np.maximum(xin - np.abs(X), Y - ytop)
    else:
        for k, w in wheels.items():
            c, r = w['c'], w['r']
            p = parts.get(k + '_1')
            hw = (p['s'][0] / 2) if p else 0.5
            rad = np.sqrt((Y - c[1]) ** 2 + (Z - c[2]) ** 2) - (r + margin)
            ax = np.abs(X - c[0]) - (hw + margin)
            sd = np.maximum(rad, ax)
            out = sd if out is None else np.minimum(out, sd)
    return out


# ---------------------------------------------------------------- 网格
def mc(F, lo, h):
    v, f, nrm, _ = measure.marching_cubes(F, level=0.0, spacing=(h, h, h))
    # 方向：面法线要朝内腔里面（F 增大的方向），车里看得见——直接沿面法线往前半格取 F 比一比
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    c = v[f].mean(axis=1)

    def samp(P):
        q = np.clip(np.round(P / h).astype(np.int64), 0, np.array(F.shape) - 1)
        return F[q[:, 0], q[:, 1], q[:, 2]]
    up = samp(c + fn * 0.8 * h) - samp(c - fn * 0.8 * h)
    if np.sum(up < 0) > np.sum(up > 0):
        f = f[:, ::-1].copy()
    return v + lo, f


def smooth_boundary(v, f, iters, lam=0.5, mu=-0.53):
    """开口的边（窗口、座圈口）沿着边线 Taubin 平滑：体素的锯齿拉直，口子不缩"""
    if iters <= 0 or not len(f):
        return v
    from scipy.sparse import coo_matrix, diags
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    uniq, cnt = np.unique(e, axis=0, return_counts=True)
    be = uniq[cnt == 1]
    if not len(be):
        return v
    n = len(v)
    E = np.concatenate([be, be[:, ::-1]])
    A = coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(axis=1)).ravel()
    bm = deg == 2   # 只动正常的边线点（交叉点不动）
    W = diags(1.0 / np.maximum(deg, 1)) @ A
    v = v.copy()
    for _ in range(iters):
        d = W @ v - v
        v[bm] += lam * d[bm]
        d = W @ v - v
        v[bm] += mu * d[bm]
    return v


def taubin(v, f, iters, lam=0.5, mu=-0.53):
    """Taubin 平滑（不缩水）：开口边上的锯齿磨圆、体素台阶磨平"""
    if iters <= 0 or not len(f):
        return v
    from scipy.sparse import coo_matrix, diags
    n = len(v)
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    A = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(axis=1)).ravel()
    W = diags(1.0 / np.maximum(deg, 1)) @ A
    v = v.copy()
    for _ in range(iters):
        v = v + lam * (W @ v - v)
        v = v + mu * (W @ v - v)
    return v


def face_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def compact_mesh(v, f):
    used = np.unique(f)
    remap = -np.ones(len(v), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return v[used], remap[f]


def decimate(v, f, target, border=True):
    area = np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1)
    f = f[area > 1e-10]   # 零面积三角形会卡住减面
    if len(f) <= target:
        return v, f
    v2, f2 = fast_simplification.simplify(v.astype(np.float64), f.astype(np.int32), target_count=int(target), agg=7, preserve_border=border)
    if len(f2) > target * 1.6 and border:   # 开口的边太碎、留着边减不下去：放开边再减一遍
        v2, f2 = fast_simplification.simplify(v2, f2.astype(np.int32), target_count=int(target), agg=7, preserve_border=False)
    return np.asarray(v2, dtype=np.float64), np.asarray(f2, dtype=np.int64)


def flat(v, f, uvscale=4.0):
    """每个三角形自己的三个顶点（硬边、平面着色）+ 按主方向投影的 UV（每 uvscale 格一个贴图周期）"""
    P = v[f].reshape(-1, 3)
    n = face_normals(v, f)
    N = np.repeat(n, 3, axis=0)
    ax = np.argmax(np.abs(n), axis=1)
    UV = np.zeros((len(P), 2))
    for a, (u, w) in ((0, (2, 1)), (1, (0, 2)), (2, (0, 1))):
        k = np.repeat(ax == a, 3)
        UV[k, 0] = P[k, u] / uvscale
        UV[k, 1] = P[k, w] / uvscale
    T = np.arange(len(P)).reshape(-1, 3)
    return P, N, UV, T


# ---------------------------------------------------------------- 一个空间
def in_boxes(c, boxes):
    k = np.zeros(len(c), dtype=bool)
    for b in boxes:
        k |= (c[:, 0] >= b[0]) & (c[:, 0] <= b[1]) & (c[:, 1] >= b[2]) & (c[:, 1] <= b[3]) & (c[:, 2] >= b[4]) & (c[:, 2] <= b[5])
    return k


def carve_space(key, sp, tris_by_group, glass_tris, wheels, parts, tracked, M):
    """从乘员眼位（seeds）在空气里灌水：碰到原模型的任何一面（地板、仪表台、车门内板、车顶、玻璃……）就停，
    灌到的就是车里的空气——内壁贴着原模型自己的里面；原模型没做里面的（坦克的整块外壳），就贴着外壳往里 t。
    ignore 盒子里的三角形（原模型自带的简易座椅、方向盘）不挡水，跟内腔里面的三角形一起挪到 Inside 块"""
    src = np.concatenate([tris_by_group[g] for g in sp['from'] if g in tris_by_group])
    ign = in_boxes(src.mean(axis=1), sp.get('ignore', []))
    for cy in sp.get('ignoreCyl', []):   # 竖着的圆柱里的三角形不挡水（c 圆心 x / z、r 半径、y 上下）：圆形的指挥塔里关着的舱盖、观察镜靠里那层
        cc = src.mean(axis=1)
        ign |= (np.hypot(cc[:, 0] - cy['c'][0], cc[:, 2] - cy['c'][1]) < cy['r']) & (cc[:, 1] > cy['y'][0]) & (cc[:, 1] < cy['y'][1])
    so = [tris_by_group[g] for g in sp.get('solidOnly', []) + ['__ign__'] if g in tris_by_group]   # 只封实体、不挡水的组（会动的炮：炮尾伸进炮塔，按 0° 挖会挖出一个炮形的坑；玻璃块里的简易内饰）
    if so:
        src = np.concatenate([src] + so)
        ign = np.concatenate([ign, np.ones(sum(len(x) for x in so), dtype=bool)])
    srcB = src[~ign]
    lo = src.reshape(-1, 3).min(0) - 0.6
    hi = src.reshape(-1, 3).max(0) + 0.6
    h = float(sp.get('vox', 0.06))
    vol = np.prod(hi - lo)
    if vol / h ** 3 > MAXVOX:
        h = (vol / MAXVOX) ** (1 / 3)
    shape = tuple(int(x) for x in np.ceil((hi - lo) / h))
    log('  %s：体素 %.3f 格（%d × %d × %d），三角形 %d（不挡水 %d）' % (sp['name'], h, shape[0], shape[1], shape[2], len(src), int(ign.sum())))
    allT = srcB if not len(glass_tris) else np.concatenate([srcB, glass_tris])
    sealT = [seal_tris(b) for b in sp.get('seal', [])]
    for s_ in sealT:   # 补盖：敞口的地方（敞篷、敞开的炮塔顶）先盖一块平板
        allT = np.concatenate([allT, s_])
    surf = raster(allT, lo, h, shape)
    gvox = raster(glass_tris, lo, h, shape) if len(glass_tris) else None
    close = int(sp.get('close', 3))
    # 封实体用全部三角形（不挡水的也算：原模型的座椅不会让车壳漏）；灌水只让原模型的面挡
    solid = solidify(surf | raster(src[ign], lo, h, shape), close) if ign.any() else solidify(surf, close)
    r = int(sp.get('gap', 2))   # 内壁离原模型的面几格（同时封住面上的小缝）
    st = ndimage.generate_binary_structure(3, 1)
    # 不含玻璃（补盖的平板要算上：原来只取了 srcB，配了玻璃的车补盖不挡水，车体 / 炮塔内腔从座圈那里漏成一片——11-24 挖 M1A2 指挥塔时发现）
    surfNG = raster(np.concatenate([srcB] + sealT) if sealT else srcB, lo, h, shape) if gvox is not None else surf
    wall = ndimage.binary_dilation(surfNG, structure=st, iterations=r) if r > 0 else surfNG
    if gvox is not None:   # 玻璃只挡它自己那一层：水一直灌到玻璃跟前，窗框（其余的面）往里让 r 格——挖开后窗口四周是窗框的厚度
        wall |= gvox
    xs = lo[0] + (np.arange(shape[0]) + 0.5) * h
    ys = lo[1] + (np.arange(shape[1]) + 0.5) * h
    zs = lo[2] + (np.arange(shape[2]) + 0.5) * h
    # 约束（盒子、切面、车轮）在整个网格上算成「不许去」的体素，灌水也不过去
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    b = sp['box']
    C = box_sd(X, Y, Z, b)
    for pl in sp.get('cut', []):
        C = np.minimum(C, plane_sd(X, Y, Z, pl['n'], pl['d']))
    for bx in sp.get('carveOut', []):
        C = np.minimum(C, -box_sd(X, Y, Z, bx))
    if sp.get('wheels', True):
        w = wheel_sd(X, Y, Z, wheels, parts, float(sp.get('wheelMargin', 0.25)), tracked)
        if w is not None:
            C = np.minimum(C, w)
    del X, Y, Z
    free = solid & ~wall & (C > 0)
    lab, nl = ndimage.label(free, structure=st)
    dbg = []
    for dp in sp.get('debug', []):   # 查问题用：这几个点算不算实体 / 墙 / 可灌 / 哪个连通块
        q = np.clip(np.floor((np.array(dp) - lo) / h).astype(int), 0, np.array(shape) - 1)
        dbg.append((dp, q))
        log('    debug %s：实体 %s、墙 %s、约束 %.2f、可灌 %s、块 %d' % (dp, bool(solid[q[0], q[1], q[2]]), bool(wall[q[0], q[1], q[2]]), float(C[q[0], q[1], q[2]]),
                                                       bool(free[q[0], q[1], q[2]]), int(lab[q[0], q[1], q[2]])))
    keep = set()
    for sd in sp.get('seeds', []):
        q = np.floor((np.array(sd) - lo) / h).astype(int)
        q = np.clip(q, 0, np.array(shape) - 1)
        if lab[q[0], q[1], q[2]] == 0:   # 种子落在墙上：附近找一个空的
            sl = lab[max(0, q[0] - 6):q[0] + 7, max(0, q[1] - 6):q[1] + 7, max(0, q[2] - 6):q[2] + 7]
            nz = sl[sl > 0]
            if len(nz):
                keep.add(int(np.bincount(nz).argmax()))
            else:
                log('    ！种子 %s 附近没有空气' % (sd,))
        else:
            keep.add(int(lab[q[0], q[1], q[2]]))
    if not keep:
        log('    ！没有种子 / 种子都不在空气里')
        return None
    region = np.isin(lab, list(keep))
    del lab
    ko = int(sp.get('open', 2))
    if ko > 0:   # 细缝连着的小气泡（仪表台里面、车门夹层）切断，只留乘员所在的那一大块
        reg2 = ndimage.binary_opening(region, structure=st, iterations=ko)
        lab2, _ = ndimage.label(reg2, structure=st)
        keep2 = set()
        for sd in sp.get('seeds', []):
            q = np.clip(np.floor((np.array(sd) - lo) / h).astype(int), 0, np.array(shape) - 1)
            sl = lab2[max(0, q[0] - 8):q[0] + 9, max(0, q[1] - 8):q[1] + 9, max(0, q[2] - 8):q[2] + 9]
            nz = sl[sl > 0]
            if len(nz):
                keep2.add(int(np.bincount(nz).argmax()))
        if keep2:
            before = int(region.sum())
            region = np.isin(lab2, list(keep2))
            # 开运算把墙角也磨圆了一点：胀回去（只在原来的内腔里）
            region = ndimage.binary_dilation(region, structure=st, iterations=ko) & free
            log('    切掉细缝连着的小气泡：%.1f%%' % (100.0 * (before - int(region.sum())) / max(before, 1)))
        del lab2, reg2
    if sp.get('fill', 0):   # 小东西留下的窟窿（细杆子、扶手）补上：先胀再缩
        k = int(sp['fill'])
        region = ndimage.binary_erosion(ndimage.binary_dilation(region, structure=st, iterations=k), structure=st, iterations=k) & solid & (C > 0)
    for dp, q in dbg:
        log('    debug %s：最后在内腔里 %s' % (dp, bool(region[q[0], q[1], q[2]])))
    vol_cav = float(region.sum()) * h ** 3
    t2 = float(sp.get('t', 0.0))
    D = ndimage.distance_transform_edt(region) * h - t2 - 0.5 * h   # 面在内腔体素和墙体素正中间（正好落在格点上会出一堆零面积三角形）
    D = ndimage.gaussian_filter(D, float(sp.get('smooth', 1.0)))   # 体素的台阶磨平（平的墙还是平的）
    D = np.minimum(D, C)
    # 只在内腔那一块抽面（加两格边）
    idx = np.nonzero(region)
    i0, i1 = max(0, idx[0].min() - 2), min(shape[0], idx[0].max() + 3)
    j0, j1 = max(0, idx[1].min() - 2), min(shape[1], idx[1].max() + 3)
    k0, k1 = max(0, idx[2].min() - 2), min(shape[2], idx[2].max() + 3)
    F = np.pad(D[i0:i1, j0:j1, k0:k1], 1, constant_values=-1.0)
    lo2 = np.array([xs[i0] - h, ys[j0] - h, zs[k0] - h])
    v, f = mc(F, lo2, h)
    log('    内腔 %.1f 立方格（%.2f 立方米），表面 %d 个三角形' % (vol_cav, vol_cav / 2.8 ** 3, len(f)))
    n = face_normals(v, f)
    ctr = v[f].mean(axis=1)
    keepf = np.ones(len(f), dtype=bool)
    if len(glass_tris):   # 窗户后面挖开
        gpts, gidx = tri_samples(glass_tris, 0.5 * h)
        gn = np.cross(glass_tris[:, 1] - glass_tris[:, 0], glass_tris[:, 2] - glass_tris[:, 0])
        gn /= np.maximum(np.linalg.norm(gn, axis=1, keepdims=True), 1e-12)
        kd = cKDTree(gpts)
        dd, ii = kd.query(ctr)
        gi = gidx[ii]
        par = np.abs(np.einsum('ij,ij->i', n, gn[gi])) > 0.6   # 跟玻璃平行（贴在玻璃上的那层），窗框的侧面留着
        behind = (dd < 2.6 * h + t2 + float(sp.get('winPad', 0.03))) & par
        keepf &= ~behind
        log('    窗户后面挖开 %d 个三角形' % int(behind.sum()))
        if sp.get('winDepth'):   # 窗洞：按每块玻璃的矩形往里打穿 winDepth 格，正对玻璃的内壁都删（弯的内壁只删平行的面会删得七零八落——11-24 M1A2 指挥塔）
            wd, wm = float(sp['winDepth']), float(sp.get('winMargin', 0.0))
            ncut = 0
            for wr in win_rects(glass_tris):
                c0, nrm, up = np.array(wr['c']), np.array(wr['n']), np.array(wr['up'])
                rt = np.cross(up, nrm)
                rel = ctr - c0
                cut = (np.abs(rel @ rt) < wr['w'] / 2 + wm) & (np.abs(rel @ up) < wr['h'] / 2 + wm) & (np.abs(rel @ nrm) < wd)
                ncut += int((cut & keepf).sum())
                keepf &= ~cut
            log('    窗洞（按玻璃的矩形打穿 %.2f 格）挖开 %d 个三角形' % (wd, ncut))
    ring = sp.get('ring')
    if ring:   # 座圈：车体内腔的顶 / 炮塔内腔的底挖开
        tc = M['tur']
        rr = float(ring['r'])
        inr = (ctr[:, 0] - tc[0]) ** 2 + (ctr[:, 2] - tc[2]) ** 2 < rr * rr
        if ring.get('side') == 'hull':
            cut = inr & (n[:, 1] < -0.5) & (ctr[:, 1] > tc[1] - float(ring.get('dy', 0.9)))
        else:
            cut = inr & (n[:, 1] > 0.5) & (ctr[:, 1] < tc[1] + float(ring.get('dy', 0.6)))
        keepf &= ~cut
        log('    座圈开口 %d 个三角形' % int(cut.sum()))
    for hole in sp.get('holes', []):   # 别的开口（敞开的舱口）：竖着的圆柱 c、r
        c = hole['c']
        cut = ((ctr[:, 0] - c[0]) ** 2 + (ctr[:, 2] - c[2]) ** 2 < hole['r'] ** 2) & (np.abs(ctr[:, 1] - c[1]) < hole.get('dy', 0.8))
        keepf &= ~cut
    f = f[keepf]
    v, f = compact_mesh(v, f)
    v = smooth_boundary(v, f, int(sp.get('edgeSmooth', 30)))   # 窗口边、座圈边的锯齿拉直
    v = taubin(v, f, int(sp.get('taubin', 12)))   # 整个面再磨一遍
    # 去掉碎片（很小的连通块）
    import collections
    parent = np.arange(len(v))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a_, b_, c_ in f:
        ra, rb, rc = find(a_), find(b_), find(c_)
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(x) for x in range(len(v))])
    fr = roots[f[:, 0]]
    cnt = collections.Counter(fr.tolist())
    big = {k for k, c in cnt.items() if c >= max(60, int(0.002 * len(f)))}
    f = f[np.isin(fr, list(big))]
    v, f = compact_mesh(v, f)
    target = int(sp.get('tris', 5000))
    v, f = decimate(v, f, target)
    # 减面、磨平以后个别面翻过来了（车里看是背面，游戏里就是个洞）：沿面法线两边取距离场比一比，朝外的翻回来
    n = face_normals(v, f)
    cc = v[f].mean(axis=1)

    def sampF(P):
        q = np.clip(np.round((P - lo2) / h).astype(np.int64), 0, np.array(F.shape) - 1)
        return F[q[:, 0], q[:, 1], q[:, 2]]
    dlt = sampF(cc + n * 1.5 * h) - sampF(cc - n * 1.5 * h)
    flip = dlt < -1e-6
    if flip.any():
        f[flip] = f[flip][:, ::-1]
        log('    翻回来 %d 个朝外的面' % int(flip.sum()))
    n = face_normals(v, f)
    floor = n[:, 1] > float(sp.get('floorNy', 0.72))
    out = {}
    for nm, sel in (('Floor', floor), ('Wall', ~floor)):
        if sel.sum() == 0:
            continue
        vv, ff = compact_mesh(v, f[sel])
        out[nm] = (vv, ff)
    log('    减面后：地板 %d、墙顶 %d 个三角形' % (len(out.get('Floor', (0, []))[1]), len(out.get('Wall', (0, []))[1])))
    # 给内饰代码的高度表：每 0.25 格一列，内腔在这一列的最低点（地板）和最高点（顶）
    cav = region[i0:i1, j0:j1, k0:k1]
    step = max(1, int(round(0.25 / h)))
    gx = xs[i0:i1][::step]
    gz = zs[k0:k1][::step]
    yy = ys[j0:j1]
    cols = []
    for a_ in range(0, cav.shape[0], step):
        row = []
        for c_ in range(0, cav.shape[2], step):
            col = cav[a_, :, c_]
            if col.any():
                ii = np.nonzero(col)[0]
                row.append((round(float(yy[ii[0]]) - t2, 3), round(float(yy[ii[-1]]) + t2, 3)))
            else:
                row.append(None)
        cols.append(row)
    hmap = {'x0': float(gx[0]), 'z0': float(gz[0]), 'dx': float(step * h), 'nx': len(gx), 'nz': len(gz), 'cols': cols}
    # 原模型里伸进内腔的三角形（自带的简易内饰）：中心在内腔里（或贴着内腔）的、ignore 盒子里的
    regD = ndimage.binary_dilation(region, structure=st, iterations=r + 1)
    return {'parts': out, 'hmap': hmap, 'vol': vol_cav, 'grid': (regD, lo, h), 'ignore': sp.get('ignore', [])}


def inside_tris(Tall, solid_info, depth):
    """原模型里深在实体里面的三角形（原模型自带的简易座椅、方向盘……）"""
    solid, lo, h = solid_info
    dist = ndimage.distance_transform_edt(solid) * h
    c = Tall.mean(axis=1)
    q = np.floor((c - lo) / h).astype(np.int64)
    ok = np.all((q >= 0) & (q < np.array(solid.shape)), axis=1)
    d = np.zeros(len(c))
    d[ok] = dist[q[ok, 0], q[ok, 1], q[ok, 2]]
    return d > depth


# ---------------------------------------------------------------- 预览
def preview(path, key, meshes_ext, cav_parts, clip_x=None):
    from PIL import Image, ImageDraw
    allP = np.concatenate([m.P for m in meshes_ext])
    lo, hi = allP.min(0), allP.max(0)
    PX = 46
    imgs = []
    for vname in ('side', 'top', 'front', 'iso'):
        if vname == 'side':
            proj = lambda P: np.c_[P[:, 2], -P[:, 1]]; depth = lambda P: P[:, 0]
        elif vname == 'top':
            proj = lambda P: np.c_[P[:, 0], P[:, 2]]; depth = lambda P: P[:, 1]
        elif vname == 'front':
            proj = lambda P: np.c_[-P[:, 0], -P[:, 1]]; depth = lambda P: -P[:, 2]
        else:
            a, e = math.radians(35), math.radians(28)
            R = np.array([[math.cos(a), 0, -math.sin(a)], [0, 1, 0], [math.sin(a), 0, math.cos(a)]])
            E = np.array([[1, 0, 0], [0, math.cos(e), -math.sin(e)], [0, math.sin(e), math.cos(e)]])
            RR = E @ R
            proj = lambda P: np.c_[(P @ RR.T)[:, 0], -(P @ RR.T)[:, 1]]; depth = lambda P: (P @ RR.T)[:, 2]
        # 外壳（剖开：x < 中线 那一半；俯视剖到车顶以下）画淡灰线，内腔上色
        tris = []
        for m in meshes_ext:
            T = m.P[m.idx]
            c = T.mean(axis=1)
            if vname in ('side', 'iso'):
                T = T[c[:, 0] < (clip_x if clip_x is not None else 0)]
            elif vname == 'top':
                T = T[c[:, 1] < (lo[1] + hi[1]) / 2 + 0.3]
            elif vname == 'front':
                T = T[c[:, 2] > (lo[2] + hi[2]) / 2 - 3]
            tris.append((T, None))
        for nm, (v, f) in cav_parts.items():
            T = v[f]
            c = T.mean(axis=1)
            if vname in ('side', 'iso'):
                T = T[c[:, 0] < (clip_x if clip_x is not None else 0) + 0.01]
            tris.append((T, nm))
        allT = np.concatenate([t for t, _ in tris if len(t)])
        P2 = proj(allT.reshape(-1, 3))
        mn, mx = P2.min(0), P2.max(0)
        W, H = int((mx[0] - mn[0]) * PX) + 40, int((mx[1] - mn[1]) * PX) + 40
        img = Image.new('RGB', (W, H), (246, 246, 248))
        dr = ImageDraw.Draw(img)
        L = np.array([0.3, 0.85, 0.4]); L /= np.linalg.norm(L)
        items = []
        for T, nm in tris:
            if not len(T):
                continue
            d = depth(T.reshape(-1, 3)).reshape(-1, 3).mean(axis=1)
            n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            for i in range(len(T)):
                items.append((d[i], T[i], nm, n[i]))
        items.sort(key=lambda it: -it[0] if vname != 'top' else it[0])
        for d, T, nm, n in items:
            p = proj(T)
            pts = [((x - mn[0]) * PX + 20, (y - mn[1]) * PX + 20) for x, y in p]
            if nm is None:
                dr.polygon(pts, fill=None, outline=(200, 202, 206))
            else:
                s = 0.55 + 0.45 * abs(float(n @ L))
                base = (150, 150, 140) if nm == 'Floor' else (235, 232, 222)
                dr.polygon(pts, fill=tuple(int(c * s) for c in base), outline=None)
        imgs.append(img)
    Wt = sum(i.width for i in imgs) + 10 * len(imgs)
    Ht = max(i.height for i in imgs)
    sheet = Image.new('RGB', (Wt, Ht), (255, 255, 255))
    x = 0
    for i in imgs:
        sheet.paste(i, (x, 0))
        x += i.width + 10
    sheet.save(path)
    log('  预览 ' + path)


def eyeview(path, eye, look, layers, fov=78, W=720, H=450, up=(0, 1, 0)):
    """从乘员眼位看出去（透视、背面剔除——同 Roblox：车外壳从里面看不见，内腔朝里看得见）；
    layers = [(三角形 k×3×3, 底色 (r,g,b), 种类 'cav' / 'ext' / 'glass' / 'ground')]"""
    from PIL import Image, ImageDraw
    E = np.array(eye, dtype=np.float64)
    Fw = np.array(look, dtype=np.float64)
    Fw /= np.linalg.norm(Fw)
    Rt = np.cross(Fw, np.array(up, dtype=np.float64))
    Rt /= np.linalg.norm(Rt)
    Up = np.cross(Rt, Fw)
    f = (W / 2) / math.tan(math.radians(fov) / 2)
    img = Image.new('RGB', (W, H))
    px = img.load()
    for yy in range(H):   # 天空渐变
        k = yy / H
        c = (int(150 + 70 * k), int(185 + 45 * k), int(225 + 20 * k))
        for xx in range(W):
            px[xx, yy] = c
    over = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dro = ImageDraw.Draw(over)
    L = np.array([0.3, 0.85, 0.4])
    L /= np.linalg.norm(L)
    items = []
    near = 0.04
    for T, col, kind in layers:
        if not len(T):
            continue
        C = np.einsum('kvj,ij->kvi', T - E, np.stack([Rt, Up, Fw]))   # 相机坐标：x 右、y 上、z 前
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        facing = np.einsum('ij,ij->i', n, (E - T[:, 0]))   # >0：正面朝着眼睛
        for i in range(len(T)):
            if kind in ('cav', 'ext') and facing[i] <= 0:
                continue
            tri = C[i]
            if (tri[:, 2] < near).all():
                continue
            # 近平面裁剪
            poly = []
            for a in range(3):
                p, q = tri[a], tri[(a + 1) % 3]
                if p[2] >= near:
                    poly.append(p)
                if (p[2] >= near) != (q[2] >= near):
                    t = (near - p[2]) / (q[2] - p[2])
                    poly.append(p + t * (q - p))
            if len(poly) < 3:
                continue
            d = float(np.mean([pp[2] for pp in poly]))
            s = 0.5 + 0.5 * abs(float(n[i] @ L))
            items.append((d, [(W / 2 + f * pp[0] / pp[2], H / 2 - f * pp[1] / pp[2]) for pp in poly], col, kind, s))
    items.sort(key=lambda it: -it[0])
    for d, pts, col, kind, s in items:
        if kind == 'glass':
            dro.polygon(pts, fill=(170, 210, 230, 70), outline=(60, 70, 80, 160))
        else:
            dr.polygon(pts, fill=tuple(int(c * s) for c in col))
    img = Image.alpha_composite(img.convert('RGBA'), over).convert('RGB')
    img.save(path)
    log('  眼位预览 ' + path)


# ---------------------------------------------------------------- 主程序
def run(key, preview_dir=None, write=True):
    cfg = CFG[key]
    src_glb, meta_line = pristine(key)
    M = airpaint.lua_parse(meta_line.strip()[len(key) + 3:].rstrip(','))
    parts = M['parts']
    J, BIN = glbio.read_glb(src_glb)
    ms = glbio.meshes(J, BIN)
    imgs = glbio.images(J, BIN)
    tracked = cfg.get('tracked', False)
    tris_by_group = {}
    glass_by_part = {}
    gspec = cfg.get('glass', {})
    gbox = gspec.get('box')
    for m in ms:
        pn = glbio.part_name(m.node)
        if pn.startswith('Cav'):   # 上次挖的内腔：重新挖
            continue
        g = parts.get(pn, {}).get('g') or group_of(pn)   # 拆出来的 Glass_ / Inside_ 块按元数据里的组
        if is_wheel(g):
            continue
        T = m.P[m.idx]
        isg = np.zeros(len(T), dtype=bool)
        if pn.startswith('Glass'):   # 上次拆出来的玻璃
            isg[:] = True
        elif pn.startswith('Inside'):   # 上次拆出来的原模型内饰：照样挡水（地板、车门内板都在里面）
            pass
        elif pn in gspec.get('parts', []) or (m.mat is not None and J['materials'][m.mat].get('name', '') in gspec.get('materials', [])):
            isg[:] = True
        if gspec.get('texture') and m.mat is not None:   # 贴图上的玻璃色（深、偏蓝灰、不饱和）
            col, _ = glbio.tri_colors(J, imgs, m)
            tc = gspec['texture']
            lum = col @ np.array([0.2126, 0.7152, 0.0722])
            sat = col.max(1) - col.min(1)
            isg |= (lum < tc.get('lum', 0.05)) & (sat < tc.get('sat', 0.06))
        if isg.any() and not pn.startswith('Glass'):   # 水平的（车顶、地板上的玻璃材质面）不是窗户——窗户是竖的或斜的
            nn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
            isg &= np.abs(nn[:, 1]) <= float(gspec.get('maxNy', 0.85))
        if gbox is not None and not pn.startswith('Glass'):
            c = T.mean(axis=1)
            inb = (c[:, 0] >= gbox[0]) & (c[:, 0] <= gbox[1]) & (c[:, 1] >= gbox[2]) & (c[:, 1] <= gbox[3]) & (c[:, 2] >= gbox[4]) & (c[:, 2] <= gbox[5])
            isg &= inb
        if isg.any():
            glass_by_part[pn] = isg
        tris_by_group.setdefault(g, []).append(T[~isg] if isg.any() else T)
    # 玻璃只认外壳上的（窗户）：玻璃材质的三角形离车外超过 maxDepth 的不算（JLTV 的整个驾驶室内饰都用了玻璃材质）
    if glass_by_part and gspec.get('maxDepth', 0.35) is not None:
        allT = [m.P[m.idx] for m in ms if not is_wheel(parts.get(glbio.part_name(m.node), {}).get('g') or group_of(glbio.part_name(m.node)))
                and not glbio.part_name(m.node).startswith('Cav')]
        op0 = open_windows(gspec)   # 摇下来的车窗、补盖也算上（不然驾驶室是漏的，里面全算「车外」）
        if len(op0):
            allT.append(op0)
        for sp0 in cfg.get('spaces', []):
            for b0 in sp0.get('seal', []):
                allT.append(seal_tris(b0))
        allT = np.concatenate(allT)
        h0 = 0.08
        lo0 = allT.reshape(-1, 3).min(0) - 0.6
        hi0 = allT.reshape(-1, 3).max(0) + 0.6
        if np.prod(hi0 - lo0) / h0 ** 3 > MAXVOX:
            h0 = (np.prod(hi0 - lo0) / MAXVOX) ** (1 / 3)
        shp0 = tuple(int(x) for x in np.ceil((hi0 - lo0) / h0))
        sol0 = solidify(raster(allT, lo0, h0, shp0), 3)
        dep = ndimage.distance_transform_edt(sol0) * h0
        md = float(gspec.get('maxDepth', 0.35))
        for m in ms:
            pn = glbio.part_name(m.node)
            if pn not in glass_by_part:
                continue
            c = m.P[m.idx].mean(axis=1)
            q = np.clip(np.floor((c - lo0) / h0).astype(np.int64), 0, np.array(shp0) - 1)
            deep = dep[q[:, 0], q[:, 1], q[:, 2]] > md
            g0 = glass_by_part[pn]
            if (g0 & deep).any():
                log('  %s：玻璃材质里 %d 个三角形在车里面（不是窗户）' % (pn, int((g0 & deep).sum())))
                glass_by_part[pn] = g0 & ~deep
                if not glass_by_part[pn].any():
                    del glass_by_part[pn]
                # 刚才按「全是玻璃」分组的，把车里面那部分放回普通三角形；ignoreRest：只封实体、不挡水（原模型的简易内饰，墙贴着外壳挖）
                g = parts.get(pn, {}).get('g') or group_of(pn)
                T = m.P[m.idx]
                if gspec.get('ignoreRest'):
                    tris_by_group.setdefault('__ign__', []).append(T[g0 & deep])
                else:
                    tris_by_group[g].append(T[g0 & deep])
                # 原来放进 tris_by_group 的是 T[~g0]，补上的这部分是 T[g0 & deep]
    tris_by_group = {g: np.concatenate(v) for g, v in tris_by_group.items() if len(v)}
    glass_tris = np.concatenate([m.P[m.idx][glass_by_part[glbio.part_name(m.node)]] for m in ms if glbio.part_name(m.node) in glass_by_part]) if glass_by_part else np.zeros((0, 3, 3))
    openT = open_windows(gspec)
    if len(openT):   # 原模型没装玻璃的窗口（摇下来的车窗）：封住灌水、内壁在这里开口，但不出玻璃块
        glass_tris = np.concatenate([glass_tris, openT]) if len(glass_tris) else openT
        log('  没装玻璃的窗口 %d 个' % len(gspec.get('open', [])))
    log('%s：玻璃 %d 个三角形（%s）' % (key, len(glass_tris), ', '.join('%s:%d' % (k, v.sum()) for k, v in glass_by_part.items())))
    wheels = M.get('wheels', {})
    results = {}
    for sp in cfg['spaces']:
        gt = glass_tris if sp.get('windows', True) else np.zeros((0, 3, 3))
        r = carve_space(key, sp, tris_by_group, gt, wheels, parts, tracked, M)
        if r:
            results[sp['name']] = (sp, r)
    # 原模型里伸进内腔的三角形 → Inside（游戏里有内饰时藏起来）：中心落在（胀了一圈的）内腔里，或者在 ignore 盒子里
    inside_by_part = {}
    for m in ms:
        pn = glbio.part_name(m.node)
        g = parts.get(pn, {}).get('g') or group_of(pn)
        if is_wheel(g) or pn.startswith('Cav') or pn.startswith('Glass') or pn.startswith('Inside'):
            continue
        c = m.P[m.idx].mean(axis=1)
        k = np.zeros(len(c), dtype=bool)
        for nm, (sp, r) in results.items():
            if g not in sp['from']:
                continue
            regD, lo, h = r['grid']
            q = np.floor((c - lo) / h).astype(np.int64)
            ok = np.all((q >= 0) & (q < np.array(regD.shape)), axis=1)
            kk = np.zeros(len(c), dtype=bool)
            kk[ok] = regD[q[ok, 0], q[ok, 1], q[ok, 2]]
            k |= kk | in_boxes(c, r['ignore'])
        if pn in glass_by_part:
            k &= ~glass_by_part[pn]
        if k.any():
            inside_by_part[pn] = k
    log('  原模型伸进内腔的三角形（挪到 Inside）：%s' % (', '.join('%s:%d' % (k, v.sum()) for k, v in inside_by_part.items()) or '没有'))
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        cav = {}
        for nm, (sp, r) in results.items():
            for pn, vf in r['parts'].items():
                cav[nm + pn] = vf
        allcav = {}
        for nm, vf in cav.items():
            allcav['Floor' if nm.endswith('Floor') else 'Wall' + nm] = vf
        preview(os.path.join(preview_dir, key + '_cav.png'), key, [m for m in ms if not is_wheel(group_of(glbio.part_name(m.node)))], allcav,
                clip_x=cfg.get('clipX', 0))
        # 眼位预览：原车外壳（背面剔除）+ 内腔 + 玻璃 + 地面
        ext = np.concatenate([m.P[m.idx][~inside_by_part[glbio.part_name(m.node)]] if glbio.part_name(m.node) in inside_by_part else m.P[m.idx] for m in ms])
        ground = np.array([[[-200, 0, -200], [200, 0, 200], [200, 0, -200]], [[-200, 0, -200], [-200, 0, 200], [200, 0, 200]]], dtype=np.float64)
        layers = [(ground, (120, 112, 90), 'ground'), (ext, (110, 104, 86), 'ext')]
        for nm, (sp, r) in results.items():
            for pn, (v, f) in r['parts'].items():
                layers.append((v[f], (96, 98, 94) if pn == 'Floor' else (220, 218, 208), 'cav'))
        gl = np.concatenate([m.P[m.idx][glass_by_part[glbio.part_name(m.node)]] for m in ms if glbio.part_name(m.node) in glass_by_part]) if glass_by_part else np.zeros((0, 3, 3))
        layers.append((gl, (0, 0, 0), 'glass'))
        for e in cfg.get('eyes', []):
            eyeview(os.path.join(preview_dir, '%s_eye_%s.png' % (key, e['name'])), e['pos'], e['look'], layers, fov=e.get('fov', 80))
    return results, (J, BIN, ms, glass_by_part, inside_by_part, M, src_glb, meta_line)


# ---------------------------------------------------------------- 写出
def srgb2lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def b64(data):
    return base64.b64encode(bytes(data)).decode('ascii')


def win_rects(glass_tris):
    """玻璃三角形按连通块分成一块块窗户：中心、法线（朝车外）、宽高、上方向（模型坐标，格）"""
    if not len(glass_tris):
        return []
    lab = vehrws.comps(glass_tris)
    out = []
    for k in np.unique(lab):
        T = glass_tris[lab == k]
        P = T.reshape(-1, 3)
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]).sum(axis=0)
        if np.linalg.norm(n) < 1e-9:
            continue
        n /= np.linalg.norm(n)
        c0 = P.mean(axis=0)
        if np.dot(n, c0 - np.array([0, c0[1], 0])) < 0 and abs(n[1]) < 0.9:
            n = -n   # 朝车外（从车中线往外）
        up = np.array([0.0, 1.0, 0.0]) - n * n[1]
        if np.linalg.norm(up) < 1e-3:
            up = np.array([0.0, 0.0, -1.0]) - n * n[2]
        up /= np.linalg.norm(up)
        rt = np.cross(up, n)
        u, w = (P - c0) @ rt, (P - c0) @ up
        c = c0 + rt * (u.min() + u.max()) / 2 + up * (w.min() + w.max()) / 2
        area = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1).sum() / 2
        if area < 0.01:
            continue
        out.append({'c': [round(float(x), 3) for x in c], 'n': [round(float(x), 3) for x in n], 'up': [round(float(x), 3) for x in up],
                    'w': round(float(u.max() - u.min()), 3), 'h': round(float(w.max() - w.min()), 3)})
    out.sort(key=lambda r: (r['c'][2], r['c'][0]))
    return out


def hmap_lua(hm):
    """高度表：每列地板 / 顶（格）量化成 16 位，缺的列 = 65535"""
    cols = hm['cols']
    ys = [v for row in cols for c in row if c for v in c]
    y0, y1 = min(ys), max(ys)
    lo, hi = bytearray(), bytearray()
    for row in cols:
        for c in row:
            if c is None:
                lo += (65535).to_bytes(2, 'little'); hi += (65535).to_bytes(2, 'little')
            else:
                lo += int(round((c[0] - y0) / (y1 - y0 + 1e-9) * 65534)).to_bytes(2, 'little')
                hi += int(round((c[1] - y0) / (y1 - y0 + 1e-9) * 65534)).to_bytes(2, 'little')
    return {'x0': round(hm['x0'], 4), 'z0': round(hm['z0'], 4), 'd': round(hm['dx'], 4), 'nx': hm['nx'], 'nz': hm['nz'],
            'y0': round(y0, 4), 'y1': round(y1, 4), 'lo': b64(lo), 'hi': b64(hi)}


def write(key, results, aux, glb=True):
    cfg = CFG[key]
    path = os.path.join(ROOT, 'models/veh/%s.glb' % key)
    if glb:
        write_glb(key, results, aux, cfg, path)
    write_meta(key, results, aux, cfg)


def write_glb(key, results, aux, cfg, path):
    """从原样开始写：改过的块换新名字（rep = 它顶替的旧块），元数据里旧块留着——
    没重新导入的照旧用旧块（大小、位置都对得上），重新导入以后 VehModels 看到新块就不用被它顶替的旧块"""
    J0, BIN0, ms, glass_by_part, inside_by_part, M, src_glb, meta_line = aux
    J, BIN = glbfix.read(src_glb)
    chunks = vehrws.load(J, BIN, key)
    for nd in J['nodes']:
        if 'mesh' in nd:
            assert len(J['meshes'][nd['mesh']]['primitives']) == 1, '一个节点多个 primitive：' + nd.get('name', '')
    info = airpaint.lua_parse(meta_line.strip()[len(key) + 3:].rstrip(','))
    parts = info['parts']
    out = BIN
    used = set(parts)

    def fresh(prefix):
        n = 1
        while '%s_%d' % (prefix, n) in used:
            n += 1
        nm = '%s_%d' % (prefix, n)
        used.add(nm)
        return nm
    moved = {'Glass': [], 'Inside': []}
    for c in chunks:
        nm = c['name']
        gm = glass_by_part.get(nm)
        im = inside_by_part.get(nm)
        if gm is None and im is None:
            continue
        k = np.ones(len(c['T']), dtype=bool)
        if gm is not None:
            assert len(gm) == len(c['T'])
            moved['Glass'].append((c['group'], nm, vehrws.sub(c, gm)))
            k &= ~gm
        if im is not None:
            im = im & k
            if im.any():
                moved['Inside'].append((c['group'], nm, vehrws.sub(c, im)))
            k &= ~im
        if k.any():   # 剩下的换新名字写成新节点，旧节点拿掉
            g = vehrws.sub(c, k)
            nn = fresh(c['group'])
            _, cc, ss = vehrws.write_chunk(J, out, g, 'V_%s__%s' % (key, nn))
            e = dict(parts[nm])
            e['c'] = [round(float(x), 3) for x in cc]
            e['s'] = [round(float(x), 3) for x in ss]
            e['rep'] = [nm]
            parts[nn] = e
            log('  %s ← %s 剩下的 %d 个三角形' % (nn, nm, int(k.sum())))
        J['nodes'][c['ni']] = {'name': 'V_%s__%s' % (key, nm)}   # 旧块：GLB 里不要了（元数据里留着给没重新导入的）
    galpha = float(cfg.get('glass', {}).get('alpha', 0.35))
    for kind, lst in moved.items():
        bykey = {}
        for grp, srcname, sbm in lst:
            bykey.setdefault((grp, sbm['mat']), []).append((srcname, sbm))
        for (grp, mat), subs in sorted(bykey.items(), key=lambda kv: (kv[0][0], -1 if kv[0][1] is None else kv[0][1])):
            g = vehrws.merge([x[1] for x in subs])
            reps = sorted({x[0] for x in subs})
            for t0 in range(0, len(g['T']), vehrws.TRI_MAX):
                piece = vehrws.sub({'P': g['P'], 'N': g['N'], 'UV': g['UV'], 'T': g['T'], 'mat': mat}, np.arange(len(g['T']))[t0:t0 + vehrws.TRI_MAX])
                nm = fresh(kind)
                _, cc, ss = vehrws.write_chunk(J, out, piece, 'V_%s__%s' % (key, nm))
                e = {'c': [round(float(x), 3) for x in cc], 'g': grp, 's': [round(float(x), 3) for x in ss], 'k': kind.lower(), 'rep': reps}
                src0 = parts.get(reps[0], {})
                if src0.get('col') is not None:
                    e['col'] = src0['col']
                if kind == 'Inside' and src0.get('a') is not None:
                    e['a'] = src0['a']   # 车外看还是原来的样子（JLTV 原模型的内饰是半透明的深色）
                if kind == 'Glass':
                    e['a'] = galpha
                parts[nm] = e
                log('  %s ← %s %d 个三角形（%s）' % (nm, ','.join(reps), len(piece['T']), kind))
    paint = cfg.get('paint', {})
    for spn, (sp, r) in results.items():
        grp = sp.get('group') or ('Turret' if 'Turret' in sp['from'] else sp['from'][0])
        for pn, (v, f) in r['parts'].items():
            col = list(paint.get('floor' if pn == 'Floor' else 'wall', [70, 72, 70] if pn == 'Floor' else [222, 222, 212]))
            J['materials'].append({'name': 'cav_%s_%s' % (spn, pn.lower()),
                                   'pbrMetallicRoughness': {'baseColorFactor': [srgb2lin(x) for x in col] + [1], 'metallicFactor': 0.0, 'roughnessFactor': 0.85}})
            mi = len(J['materials']) - 1
            P, N, UV, T = flat(v, f, 2.0 if pn == 'Floor' else 4.0)
            g = {'P': P, 'N': N.astype(np.float32), 'UV': UV.astype(np.float32), 'T': T, 'mat': mi}
            nm = 'Cav%s%s_1' % (spn, pn)
            used.add(nm)
            _, cc, ss = vehrws.write_chunk(J, out, g, 'V_%s__%s' % (key, nm))
            e = {'c': [round(float(x), 3) for x in cc], 'g': grp, 's': [round(float(x), 3) for x in ss], 'k': 'cav', 'col': col}
            if pn == 'Floor':
                e['m'] = 'DiamondPlate'
            parts[nm] = e
    J['nodes'][0]['children'] = [i for i in J['nodes'][0].get('children', []) if 'mesh' in J['nodes'][i] or J['nodes'][i].get('children')]
    out = vehrws.compact(J, out)
    glbfix.write(path, J, out)
    info['cav'] = True
    lines = open(META_LUA, encoding='utf-8').read().split('\n')
    li = next(i for i, ln in enumerate(lines) if ln.startswith('    %s = { ' % key))
    lines[li] = '    %s = %s,' % (key, B.lua(info))
    open(META_LUA, 'w', encoding='utf-8').write('\n'.join(lines))
    log('%s：写好了 %s（%.1f MB）、ImportedMeta' % (key, os.path.relpath(path, ROOT), os.path.getsize(path) / 1e6))


def write_meta(key, results, aux, cfg):
    J0, BIN0, ms, glass_by_part, inside_by_part, M, src_glb, meta_line = aux
    # 内腔元数据（内饰代码用）
    gl = np.concatenate([m.P[m.idx][glass_by_part[glbio.part_name(m.node)]] for m in ms if glbio.part_name(m.node) in glass_by_part]) if glass_by_part else np.zeros((0, 3, 3))
    openT = open_windows(cfg.get('glass', {}))
    if len(openT):
        gl = np.concatenate([gl, openT]) if len(gl) else openT
    entry = {'spaces': {}, 'win': win_rects(gl), 'anchors': cfg.get('anchors', {})}
    for spn, (sp, r) in results.items():
        grp = sp.get('group') or ('Turret' if 'Turret' in sp['from'] else sp['from'][0])
        entry['spaces'][spn] = {'g': grp, 'vol': round(r['vol'], 2), 'hm': hmap_lua(r['hmap'])}
        if sp.get('ring'):
            entry['spaces'][spn]['ring'] = round(float(sp['ring']['r']), 3)   # 座圈半径（格）
    try:
        old = subprocess.run(['lune', 'run', os.path.join(HERE, 'meta2json.luau'), CAVMETA_LUA], capture_output=True, text=True, cwd=ROOT)
        allm = json.loads(old.stdout) if old.returncode == 0 else {}
    except Exception:
        allm = {}
    allm[key] = entry
    with open(CAVMETA_LUA, 'w', encoding='utf-8') as fo:
        fo.write('-- 自动生成（tools/models/carve.py），别手改：从原车模型挖出来的内腔（用户 11-23「在原车内部雕刻出来内饰」），内饰代码按它摆东西\n')
        fo.write('--   [模型键] = { spaces[空间名] = { g 部件组（Body 车体 / Turret 炮塔）, vol 体积（格³）, hm 高度表 }, win 窗户（玻璃块：c 中心、n 朝外的法线、up、w 宽、h 高） }\n')
        fo.write('--   高度表：x0 / z0 第一列的位置、d 列距、nx × nz 列（x 外层、z 内层），每列内腔的地板 lo、顶 hi（16 位，y0..y1 线性，65535 = 这一列没有内腔），base64\n')
        fo.write('--   坐标同 ImportedMeta：格，原点车底中心，X 右、Y 上、−Z 朝前\n')
        fo.write('return {\n')
        for k2 in sorted(allm):
            fo.write('  %s = %s,\n' % (k2, B.lua(allm[k2])))
        fo.write('}\n')
    log('  CavityMeta：%d 个空间、%d 块窗户' % (len(entry['spaces']), len(entry['win'])))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if '=' not in a and a not in ('nowrite', 'metaonly')]
    opt = dict(a.split('=', 1) for a in sys.argv[1:] if '=' in a)
    for k in args:
        results, aux = run(k, opt.get('preview'), 'nowrite' not in sys.argv)
        if 'nowrite' not in sys.argv:
            write(k, results, aux, glb='metaonly' not in sys.argv)
