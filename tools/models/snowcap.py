# 屋顶积雪：从转好的建筑 GLB（B_<键>__<块名>）给每座楼生成一块贴合屋面的厚积雪网格 → models/bld/snowcaps.glb（只有几何、白色材质）
#   + src/ReplicatedStorage/SnowCapMeta.lua（[键] = { c 中心, s 大小, tris }，约定同 parts：格，相对楼的占地中心、地面，X 右、Y 上、−Z 正面）
#   用户 11-27：雪山地图要冬天、大雪，照白川乡合掌村冬景——屋顶整个被半米到一米厚的雪盖住，雪的边缘圆润、檐口处略探出
#   python3 -I tools/models/snowcap.py [--out models/bld/snowcaps.glb] [--meta src/ReplicatedStorage/SnowCapMeta.lua] [--only 键,键] [--jobs 4] [<glb> <元数据.lua> ...]
#     不给成对的「glb 元数据」就用默认的几包：snow.glb + SnowMeta、buildings.glb + BuildingMeta、village.glb + VillageMeta（有才用）；
#     键重名时前面的包优先（同 World.lua 并表的顺序）。只要 numpy、scipy
#   做法（每座楼）：
#     1. 照游戏里的摆法取三角形：每块网格按自己的包围盒缩放到元数据的 s、中心放到 c（Roblox 的 MeshPart 就是这样按 Size 撑满的；
#        有几块元数据和网格对不上——Blender 的 bound_box 把游离点也算进去了——游戏里是被撑大的，雪也照撑大以后的样子盖）
#     2. 从上往下把三角形栅格化成高度网格（真实约 0.1 米一格，大楼放粗），只留最上面那层；坡度 60° 以内（合掌造约 60° 照样厚厚一层）、
#        离地 0.8 米以上的格子挂得住雪；按高度连续（相邻格高差小于约 70° 坡）分成一块块「承雪面」（屋面、平台、墙头、烟囱顶、窗台……）
#     3. 每块承雪面：边上的格子看外侧——外侧低（檐口、山墙边、墙头边）是「垂边」：雪在里面圆润地收薄、檐口外探出 0.15 米、往下包一点；
#        外侧高（贴着更高的墙、烟囱、老虎窗）是「靠墙」：雪不收薄，满厚伸进墙里一点（藏在墙里，不留缝）；
#        厚度（法向）：缓坡 0.7 米、60° 时约 0.45 米，换成竖直方向的厚度；屋脊、天沟处按雪面平滑（脊上圆、沟里填满）
#     4. 网格：顶面按等值线（marching squares）裁在雪的边缘，底面贴着屋面（低 3 厘米，藏在屋面里；探出的部分往下包），
#        边上一圈裙边连起顶面、底面——每块都是封闭的实心雪壳，不是飘着的一张纸；雪只在最上层屋面之上（加上伸进墙里那一点），不长进楼里面
#     5. 二次误差（QEM）边折叠简化到每座 ≲ 6000 个三角形（按承雪面积、周长分配），法线按 55° 分棱，UV 按法线方向投影（Roblox 的 MeshPart 材质按 UV 贴）
#   游戏里：World.building 摆完楼本身的块以后，雪山地图（Map.SNOW）或 opt.snowcap 时把 Imported.Bld.<键>.B_<键>__snow 照 SnowCapMeta 摆上，
#     材质 Snow、颜色 RGB(240, 244, 248)；没导入 snowcaps.glb 时什么都不做
import argparse, heapq, json, math, os, re, struct, sys, time
import numpy as np
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

S = 2.8   # 1 米 = 2.8 格
# 参数（米；用的时候 × S 换成格）
P = dict(
    g=0.10,        # 高度网格一格（真实 0.1 米）；一座楼承雪面超过 MAXCELL 格就放粗
    hmin=0.8,      # 离地这么高以下的面不盖（地上本来就是雪地形）
    slope=60.0,    # 坡度上限（度）
    t0=0.70,       # 缓坡（≤ 25°）上雪的法向厚度
    t60=0.45,      # 60° 坡上雪的法向厚度
    tzmax=1.05,    # 竖直方向的厚度上限
    edge=0.62,     # 垂边处顶面高出屋面 = 厚度 × edge（再往外是探出的圆头）
    rr=0.38,       # 垂边往里多远收圆（圆角半径）
    ov=0.15,       # 檐口外探出多少
    drop=0.14,     # 探出的雪往下包多少（盖住封檐板上沿）
    ovw=0.12,      # 靠墙：伸进墙里多少
    sink=0.03,     # 底面比屋面低多少（藏进屋面）
    wall=0.12,     # 外侧比承雪面高出这么多算墙
    smooth=0.22,   # 雪面平滑（高斯 σ）
    amin=0.12,     # 承雪面小于这么大（平方米）不盖
)
MAXCELL = 26000   # 一座楼承雪面最多这么多格（再多 g 放粗：QEM 是纯 Python 的，太细太慢）
TRI_MAX = 6000    # 一座楼最多几个三角形
UVS = 8.0         # UV：1 = 8 格（材质贴图按 UV 铺）


# ---------------------------------------------------------------- 读 GLB、Lua 元数据
CT = {5120: 'i1', 5121: 'u1', 5122: 'i2', 5123: 'u2', 5125: 'u4', 5126: 'f4'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF', '不是 GLB：' + path
    off, J, BIN = 12, None, b''
    while off < len(b):
        ln, ty = struct.unpack('<I4s', b[off:off + 8])
        if ty == b'JSON':
            J = json.loads(b[off + 8:off + 8 + ln])
        elif ty == b'BIN\x00':
            BIN = b[off + 8:off + 8 + ln]
        off += 8 + ln
    return J, BIN


def accessor(J, BIN, i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    n, dt = NC[a['type']], np.dtype(CT[a['componentType']])
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0) or dt.itemsize * n
    arr = np.array(np.ndarray((a['count'], n), dtype=dt, buffer=BIN, offset=start, strides=(stride, dt.itemsize)))
    if a.get('normalized') and dt.kind in 'iu':
        arr = arr.astype(np.float32) / float(np.iinfo(dt).max)
    return arr


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def world_mats(J):
    W, parent = {}, {}
    for i, n in enumerate(J['nodes']):
        for c in n.get('children', []):
            parent[c] = i

    def local(n):
        if 'matrix' in n:
            return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
        M = np.eye(4)
        if 'scale' in n:
            M = np.diag(list(n['scale']) + [1.0]) @ M
        if 'rotation' in n:
            R = np.eye(4)
            R[:3, :3] = quat_mat(n['rotation'])
            M = R @ M
        if 'translation' in n:
            T = np.eye(4)
            T[:3, 3] = n['translation']
            M = T @ M
        return M

    def get(i):
        if i not in W:
            L = local(J['nodes'][i])
            W[i] = (get(parent[i]) @ L) if i in parent else L
        return W[i]
    for i in range(len(J['nodes'])):
        get(i)
    return W


_TOK = re.compile(r'\s*(?:(--\[\[.*?\]\])|(--[^\n]*)|("(?:[^"\\]|\\.)*")|([A-Za-z_][A-Za-z0-9_]*)|(-?\d+\.?\d*(?:[eE][-+]?\d+)?)|(.))', re.S)


def parse_lua(src):
    """自动生成的元数据 Lua（return { 键 = { … }, … }）→ dict / list（只认这类纯数据表）"""
    T = []
    for m in _TOK.finditer(src):
        if m.group(1) or m.group(2):
            continue
        if m.group(3) is not None:
            T.append(('s', m.group(3)[1:-1].replace('\\"', '"').replace('\\\\', '\\')))
        elif m.group(4) is not None:
            T.append(('n', m.group(4)))
        elif m.group(5) is not None:
            T.append(('v', float(m.group(5))))
        elif m.group(6) and m.group(6).strip():
            T.append(('p', m.group(6)))
    i = 0

    def val():
        nonlocal i
        t = T[i]
        if t == ('p', '{'):
            i += 1
            arr, d = [], {}
            while T[i] != ('p', '}'):
                if T[i][0] == 'n' and T[i + 1] == ('p', '='):
                    k = T[i][1]
                    i += 2
                    d[k] = val()
                elif T[i] == ('p', '['):
                    i += 1
                    k = val()
                    i += 2   # ] =
                    d[k] = val()
                else:
                    arr.append(val())
                if T[i] in (('p', ','), ('p', ';')):
                    i += 1
            i += 1
            return d if d else arr
        i += 1
        if t[0] == 'n':
            return {'true': True, 'false': False, 'nil': None}.get(t[1], t[1])
        return t[1]
    while T[i] != ('n', 'return'):
        i += 1
    i += 1
    return val()


def load_pack(glb, meta_path, log):
    """一包楼 → { 键: (三角形 (n, 3, 3)，格，游戏里的摆法；元数据) }"""
    M = parse_lua(open(meta_path, encoding='utf-8').read())
    J, BIN = read_glb(glb)
    W = world_mats(J)
    tris = {}
    for ni, n in enumerate(J['nodes']):
        mm = re.match(r'^B_([A-Za-z0-9_]+?)__([A-Za-z0-9_]+)$', n.get('name', ''))   # 同 Imports.lua 的 ^B_([%w_]-)__[%w_]+$
        if not mm or 'mesh' not in n:
            continue
        key, part = mm.group(1), mm.group(2)
        info = M.get(key)
        p = info and info.get('parts', {}).get(part)
        if not p:
            continue
        Ps, Ts, base = [], [], 0
        for pr in J['meshes'][n['mesh']]['primitives']:
            if pr.get('mode', 4) != 4:
                continue
            v = accessor(J, BIN, pr['attributes']['POSITION']).astype(np.float64)
            idx = accessor(J, BIN, pr['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in pr else np.arange(len(v)).reshape(-1, 3)
            Ps.append(v)
            Ts.append(idx + base)
            base += len(v)
        if not Ps:
            continue
        V = np.concatenate(Ps) @ W[ni][:3, :3].T + W[ni][:3, 3]
        # Roblox：MeshPart 的网格按自己的包围盒居中，Size 撑满 → 游戏里的样子 = c + (v − 包围盒中心) × s / 包围盒大小
        lo, hi = V.min(0), V.max(0)
        size, ctr = hi - lo, (lo + hi) / 2
        c, s = np.array(p['c'], dtype=np.float64), np.array(p['s'], dtype=np.float64)
        k = np.where(size > 1e-3, s / np.maximum(size, 1e-9), 1.0)
        if np.abs(k - 1).max() > 0.01 or np.abs(ctr - np.array(info['o']) - c).max() > 0.05:
            log('  注意 %s.%s：元数据的 c/s 和网格的包围盒对不上（网格 %s → 元数据 %s，游戏里按元数据撑开），雪照游戏里的样子盖' % (
                key, part, np.round(size, 2).tolist(), np.round(s, 2).tolist()))
        G = c + (V - ctr) * k
        tris.setdefault(key, []).append(G[np.concatenate(Ts)])
    return {k: (np.concatenate(v), M[k]) for k, v in tris.items()}


# ---------------------------------------------------------------- 高度网格（从上往下看最上面一层）
def raster_top(T, g, x0, z0, nx, nz, ycut):
    """三角形 → 每格中心最上面那层的高度 H（没盖到 −inf）、那个三角形的 |ny|（坡度）；几乎竖直的、整个在 ycut 以下的不算"""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    nrm = np.cross(b - a, c - a)
    ln = np.linalg.norm(nrm, axis=1)
    ny = np.abs(nrm[:, 1]) / np.maximum(ln, 1e-12)
    keep = (ln > 1e-10) & (ny > 0.05) & (T[:, :, 1].max(1) >= ycut)
    a, b, c, ny = a[keep], b[keep], c[keep], ny[keep]
    xs, zs = np.stack([a[:, 0], b[:, 0], c[:, 0]], 1), np.stack([a[:, 2], b[:, 2], c[:, 2]], 1)
    i0 = np.ceil((xs.min(1) - x0) / g - 0.5).astype(np.int64)
    i1 = np.floor((xs.max(1) - x0) / g - 0.5).astype(np.int64)
    j0 = np.ceil((zs.min(1) - z0) / g - 0.5).astype(np.int64)
    j1 = np.floor((zs.max(1) - z0) / g - 0.5).astype(np.int64)
    i0, j0 = np.maximum(i0, 0), np.maximum(j0, 0)
    i1, j1 = np.minimum(i1, nx - 1), np.minimum(j1, nz - 1)
    ext = np.maximum(i1 - i0 + 1, j1 - j0 + 1)
    hit_c, hit_y, hit_n = [], [], []
    v0x, v0z = b[:, 0] - a[:, 0], b[:, 2] - a[:, 2]
    v1x, v1z = c[:, 0] - a[:, 0], c[:, 2] - a[:, 2]
    d00, d01, d11 = v0x * v0x + v0z * v0z, v0x * v1x + v0z * v1z, v1x * v1x + v1z * v1z
    den = d00 * d11 - d01 * d01
    ok = (ext >= 1) & (np.abs(den) > 1e-14)
    prev = 0
    for K in (1, 2, 4, 8, 16, 32, 64, 128, 256, 1 << 20):
        sel = np.nonzero(ok & (ext > prev) & (ext <= K))[0]
        prev = K
        if len(sel) == 0:
            continue
        if K > 256:   # 特大的三角形一个个来
            groups = [[t] for t in sel]
        else:
            per = max(1, 1500000 // (K * K))
            groups = [sel[s:s + per] for s in range(0, len(sel), per)]
        for grp in groups:
            grp = np.asarray(grp)
            if K > 256:
                t = grp[0]
                ii, jj = np.meshgrid(np.arange(i0[t], i1[t] + 1), np.arange(j0[t], j1[t] + 1), indexing='ij')
                I, Jz = ii.reshape(1, -1), jj.reshape(1, -1)
                valid = np.ones_like(I, dtype=bool)
            else:
                oi, oj = np.meshgrid(np.arange(K), np.arange(K), indexing='ij')
                I = i0[grp][:, None] + oi.reshape(1, -1)
                Jz = j0[grp][:, None] + oj.reshape(1, -1)
                valid = (I <= i1[grp][:, None]) & (Jz <= j1[grp][:, None])
            px = x0 + (I + 0.5) * g - a[grp, 0][:, None]
            pz = z0 + (Jz + 0.5) * g - a[grp, 2][:, None]
            d20 = px * v0x[grp][:, None] + pz * v0z[grp][:, None]
            d21 = px * v1x[grp][:, None] + pz * v1z[grp][:, None]
            dn = den[grp][:, None]
            v = (d11[grp][:, None] * d20 - d01[grp][:, None] * d21) / dn
            w = (d00[grp][:, None] * d21 - d01[grp][:, None] * d20) / dn
            u = 1 - v - w
            e = -1e-6
            ins = valid & (u >= e) & (v >= e) & (w >= e)
            if not ins.any():
                continue
            y = u * a[grp, 1][:, None] + v * b[grp, 1][:, None] + w * c[grp, 1][:, None]
            rr, cc = np.nonzero(ins)
            hit_c.append(I[rr, cc] * nz + Jz[rr, cc])
            hit_y.append(y[rr, cc])
            hit_n.append(np.broadcast_to(ny[grp][:, None], y.shape)[rr, cc])
    H = np.full(nx * nz, -np.inf)
    NY = np.zeros(nx * nz)
    if hit_c:
        hc, hy, hn = np.concatenate(hit_c), np.concatenate(hit_y), np.concatenate(hit_n)
        np.maximum.at(H, hc, hy)
        win = hy >= H[hc] - 1e-6
        NY[hc[win]] = hn[win]
    return H.reshape(nx, nz), NY.reshape(nx, nz)


# ---------------------------------------------------------------- 一块承雪面 → 封闭的雪壳
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def plate_fields(Hw, inP, g, Q):
    """承雪面（窗口里的布尔 inP、最上层高度 Hw）→ 等值面函数 phi（≥0 在雪里）、顶面 St、底面 Hb（都铺满整个窗口，好插值）"""
    nx, nz = inP.shape
    big = 1e9
    # 承雪面上的高度梯度（单侧差分只用承雪面里的格子），往外按最近的格子线性外推
    Hp = np.where(inP, Hw, np.nan)
    gx = np.zeros_like(Hw)
    gz = np.zeros_like(Hw)
    for ax, gg in ((0, gx), (1, gz)):
        fw = np.roll(Hp, -1, ax) - Hp
        bw = Hp - np.roll(Hp, 1, ax)
        if ax == 0:
            fw[-1, :] = np.nan
            bw[0, :] = np.nan
        else:
            fw[:, -1] = np.nan
            bw[:, 0] = np.nan
        both = ~np.isnan(fw) & ~np.isnan(bw)
        gg[both] = (fw[both] + bw[both]) / (2 * g)
        only = np.isnan(fw) & ~np.isnan(bw)
        gg[only] = bw[only] / g
        only = ~np.isnan(fw) & np.isnan(bw)
        gg[only] = fw[only] / g
        gg[~inP] = 0
    dout, (qi, qj) = ndimage.distance_transform_edt(~inP, return_indices=True)
    ii, jj = np.meshgrid(np.arange(nx), np.arange(nz), indexing='ij')
    Hnear = Hw[qi, qj]
    Hext = np.where(inP, Hw, Hnear + gx[qi, qj] * (ii - qi) * g + gz[qi, qj] * (jj - qj) * g)
    # 承雪面外侧：比它高的是墙（雪满厚伸进去一点），低的 / 空的是垂边（收圆、探出）
    wallC = ~inP & (Hw > Hnear + Q['wall'])
    dropC = ~inP & ~wallC
    A = inP | (wallC & ((dout - 0.5) * g <= Q['ovw']))
    eout = (dout - 0.5) * g                                   # 在承雪面外多远（到边）
    R = A | (dropC & (eout <= Q['ov']))
    # 坡度（两侧差分取大的：屋脊上不因为左右抵消变成平的）→ 法向厚度 → 竖直厚度
    Hf = Hext
    sx = np.maximum(np.abs(np.roll(Hf, -1, 0) - Hf), np.abs(Hf - np.roll(Hf, 1, 0))) / g
    sz = np.maximum(np.abs(np.roll(Hf, -1, 1) - Hf), np.abs(Hf - np.roll(Hf, 1, 1))) / g
    # 只看承雪面里的坡度：垂边外侧那一格的差分会把落差算进去
    gsl = np.where(inP, np.hypot(np.minimum(sx, 4), np.minimum(sz, 4)), np.nan)
    gsl = np.where(np.isnan(gsl), np.hypot(gx, gz)[qi, qj], gsl)
    ang = np.degrees(np.arctan(gsl))
    tn = Q['t0'] + (Q['t60'] - Q['t0']) * smoothstep(25, 60, ang)
    tz = np.minimum(tn / np.cos(np.radians(np.minimum(ang, 70))), Q['tzmax'])
    tz = ndimage.gaussian_filter(tz, 1.5)
    # 雪面：屋面 + 厚度，高斯平滑（脊上圆、沟里填），不低于屋面 + 0.35 倍厚度
    sig = max(0.6, Q['smooth'] / g)
    U = ndimage.gaussian_filter(Hext + tz, sig, mode='nearest')
    th = np.maximum(U - Hext, 0.35 * tz)
    # 收圆：到最近的垂边多远（靠墙的边不算边）
    dD = (ndimage.distance_transform_edt(~dropC) - 0.5) * g if dropC.any() else np.full(inP.shape, big)
    rr = Q['rr']
    din = np.clip(dD, 0, rr)
    rho_in = Q['edge'] + (1 - Q['edge']) * np.sqrt(np.clip(1 - (1 - din / rr) ** 2, 0, 1))
    rho_out = Q['edge'] * np.sqrt(np.clip(1 - (np.maximum(eout, 0) / Q['ov']) ** 2, 0, 1))
    rho = np.where(dropC, rho_out, rho_in)
    # 窄的（墙头、栏杆扶手）：雪堆的高不超过宽（半宽 = 附近离边最远的那格，宽的面靠边处不受影响）
    rc = int(math.ceil(0.6 * S / g))
    halfw = ndimage.maximum_filter(np.maximum(ndimage.distance_transform_edt(A) - 0.5, 0) * g, size=2 * rc + 1)
    th = np.minimum(th, 0.1 * S + 1.4 * halfw + Q['ov'])
    St = Hext + th * rho
    Hb = np.where(inP, Hw - Q['sink'], Hext - Q['sink'])
    Hb = np.where(dropC, Hext - Q['sink'] - (Q['drop'] - Q['sink']) * smoothstep(0, Q['ov'], eout), Hb)
    St = np.maximum(St, Hb + 0.4 * Q['drop'])
    # 等值面：雪区 R 的有符号距离（稍微平滑，边缘不起锯齿）
    phi = np.where(R, ndimage.distance_transform_edt(R) - 0.5, -(ndimage.distance_transform_edt(~R) - 0.5))
    phi = ndimage.gaussian_filter(phi, 0.7)
    return phi, St, Hb


def mesh_plate(phi, St, Hb, x0, z0, g):
    """phi ≥ 0 的区域（marching squares 裁边）→ 封闭网格：顶面（St）+ 底面（Hb）+ 一圈裙边；返回 (V, F)"""
    nx, nz = phi.shape
    ins = phi >= 0
    pts = []          # 二维点：(x, z, 顶高, 底高)
    gid = -np.ones((nx, nz), dtype=np.int64)
    I, Jz = np.nonzero(ins)
    gid[I, Jz] = np.arange(len(I))
    for i, j in zip(I.tolist(), Jz.tolist()):
        pts.append((x0 + (i + 0.5) * g, z0 + (j + 0.5) * g, St[i, j], Hb[i, j]))
    cross = {}

    def xpt(i, j, i2, j2):
        k = (i, j, i2, j2) if (i, j) < (i2, j2) else (i2, j2, i, j)
        if k in cross:
            return cross[k]
        a, b = phi[i, j], phi[i2, j2]
        t = a / (a - b)
        t = min(max(t, 0.02), 0.98)
        x = x0 + (i + 0.5 + t * (i2 - i)) * g
        z = z0 + (j + 0.5 + t * (j2 - j)) * g
        st = St[i, j] + t * (St[i2, j2] - St[i, j])
        hb = Hb[i, j] + t * (Hb[i2, j2] - Hb[i, j])
        pts.append((x, z, st, hb))
        cross[k] = len(pts) - 1
        return cross[k]
    tri = []
    # 四角都在里面的格：两个三角形（向量化）
    full = ins[:-1, :-1] & ins[1:, :-1] & ins[1:, 1:] & ins[:-1, 1:]
    fi, fj = np.nonzero(full)
    c0, c1, c2, c3 = gid[fi, fj], gid[fi + 1, fj], gid[fi + 1, fj + 1], gid[fi, fj + 1]
    # 对角线：取顶面高差小的那条（屋脊斜着走时不出锯齿）
    dA = np.abs(St[fi, fj] - St[fi + 1, fj + 1])
    dB = np.abs(St[fi + 1, fj] - St[fi, fj + 1])
    useA = dA <= dB
    tA = np.concatenate([np.stack([c0, c1, c2], 1)[useA], np.stack([c0, c2, c3], 1)[useA],
                         np.stack([c0, c1, c3], 1)[~useA], np.stack([c1, c2, c3], 1)[~useA]])
    # 边上的格：按角走一圈，里面的角 + 边上的交点 = 凸多边形（对角两个在里面的鞍点按中心值连 / 断）
    any_in = ins[:-1, :-1] | ins[1:, :-1] | ins[1:, 1:] | ins[:-1, 1:]
    mi, mj = np.nonzero(any_in & ~full)
    polys = []
    for i, j in zip(mi.tolist(), mj.tolist()):
        cs = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
        inn = [ins[c] for c in cs]
        if inn[0] and inn[2] and not inn[1] and not inn[3] or inn[1] and inn[3] and not inn[0] and not inn[2]:
            m = sum(phi[c] for c in cs) / 4
            if m < 0:   # 鞍点：断开，两个角各一个小三角
                for k in range(4):
                    if inn[k]:
                        a, b = cs[(k - 1) % 4], cs[(k + 1) % 4]
                        polys.append([gid[cs[k]], xpt(*cs[k], *b), xpt(*a, *cs[k])])
                continue
        poly = []
        for k in range(4):
            a, b = cs[k], cs[(k + 1) % 4]
            if inn[k]:
                poly.append(gid[a])
            if inn[k] != inn[(k + 1) % 4]:
                poly.append(xpt(*a, *b))
        if len(poly) >= 3:
            polys.append(poly)
    for poly in polys:
        for k in range(1, len(poly) - 1):
            tri.append((poly[0], poly[k], poly[k + 1]))
    T2 = np.concatenate([tA.reshape(-1, 3), np.array(tri, dtype=np.int64).reshape(-1, 3)]) if len(tri) else tA.reshape(-1, 3)
    pts = np.array(pts, dtype=np.float64)
    n2 = len(pts)
    # 上面的绕向：(x, z) 平面里顺时针 = 法线朝 +Y；按每个三角形的有向面积翻
    ax, az = pts[T2[:, 0], 0], pts[T2[:, 0], 1]
    cr = (pts[T2[:, 1], 0] - ax) * (pts[T2[:, 2], 1] - az) - (pts[T2[:, 1], 1] - az) * (pts[T2[:, 2], 0] - ax)
    T2 = np.where((cr > 0)[:, None], T2[:, [0, 2, 1]], T2)
    T2 = T2[np.abs(cr) > 1e-12]
    V = np.concatenate([np.stack([pts[:, 0], pts[:, 2], pts[:, 1]], 1), np.stack([pts[:, 0], pts[:, 3], pts[:, 1]], 1)])
    Ftop = T2
    Fbot = T2[:, [0, 2, 1]] + n2
    # 裙边：顶面的边界边（只属于一个三角形）a→b，接到底面的 a'、b'
    e = np.concatenate([T2[:, [0, 1]], T2[:, [1, 2]], T2[:, [2, 0]]])
    key = np.minimum(e[:, 0], e[:, 1]) * n2 + np.maximum(e[:, 0], e[:, 1])
    u, inv, cnt = np.unique(key, return_inverse=True, return_counts=True)
    bd = e[cnt[inv] == 1]
    Fsk = np.concatenate([np.stack([bd[:, 1], bd[:, 0], bd[:, 0] + n2], 1), np.stack([bd[:, 1], bd[:, 0] + n2, bd[:, 1] + n2], 1)])
    F = np.concatenate([Ftop, Fbot, Fsk])
    return V, F


# ---------------------------------------------------------------- 二次误差边折叠简化（Garland–Heckbert；封闭网格，保流形）
def qem(V, F, target, log=None):
    V = np.asarray(V, dtype=np.float64)
    F = np.asarray(F, dtype=np.int64)
    nv, nf = len(V), len(F)
    if nf <= target:
        return V, F
    p0, p1, p2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    n = np.cross(p1 - p0, p2 - p0)
    ar = np.linalg.norm(n, axis=1)
    n = n / np.maximum(ar, 1e-12)[:, None]
    d = -(n * p0).sum(1)
    w = ar / 2
    a, b, c = n[:, 0], n[:, 1], n[:, 2]
    qf = w[:, None] * np.stack([a * a, a * b, a * c, a * d, b * b, b * c, b * d, c * c, c * d, d * d], 1)
    Qa = np.zeros((nv, 10))
    for k in range(3):
        np.add.at(Qa, F[:, k], qf)
    Q = Qa.tolist()
    P = V.tolist()
    Fl = F.tolist()
    alive = [True] * nf
    vf = [set() for _ in range(nv)]
    for i, (x, y, z) in enumerate(Fl):
        vf[x].add(i)
        vf[y].add(i)
        vf[z].add(i)
    vdead = [False] * nv
    ver = [0] * nv
    # 边界边（不该有：网格是封闭的）两头的点不动
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    ek = np.minimum(e[:, 0], e[:, 1]) * nv + np.maximum(e[:, 0], e[:, 1])
    uk, cnt = np.unique(ek, return_counts=True)
    lock = [False] * nv
    for k in uk[cnt == 1].tolist():
        lock[k // nv] = lock[k % nv] = True
    tr = float(np.mean(Qa[:, 0] + Qa[:, 4] + Qa[:, 7])) + 1e-12

    def cost(u, v):
        qu, qv = Q[u], Q[v]
        q0, q1, q2, q3, q4, q5, q6, q7, q8, q9 = [qu[k] + qv[k] for k in range(10)]
        pu, pv = P[u], P[v]
        det = q0 * (q4 * q7 - q5 * q5) - q1 * (q1 * q7 - q5 * q2) + q2 * (q1 * q5 - q4 * q2)
        best = None
        if abs(det) > 1e-9 * ((q0 + q4 + q7) / 3) ** 3 + 1e-300:
            # 解 A x = −b（A 对称）
            i00 = (q4 * q7 - q5 * q5) / det
            i01 = -(q1 * q7 - q2 * q5) / det
            i02 = (q1 * q5 - q2 * q4) / det
            i11 = (q0 * q7 - q2 * q2) / det
            i12 = -(q0 * q5 - q1 * q2) / det
            i22 = (q0 * q4 - q1 * q1) / det
            x = -(i00 * q3 + i01 * q6 + i02 * q8)
            y = -(i01 * q3 + i11 * q6 + i12 * q8)
            z = -(i02 * q3 + i12 * q6 + i22 * q8)
            mx, my, mz = (pu[0] + pv[0]) * 0.5, (pu[1] + pv[1]) * 0.5, (pu[2] + pv[2]) * 0.5
            L2 = (pu[0] - pv[0]) ** 2 + (pu[1] - pv[1]) ** 2 + (pu[2] - pv[2]) ** 2
            if (x - mx) ** 2 + (y - my) ** 2 + (z - mz) ** 2 <= 0.36 * L2:
                best = (x, y, z)
        cands = [best] if best else [tuple(pu), tuple(pv), ((pu[0] + pv[0]) * 0.5, (pu[1] + pv[1]) * 0.5, (pu[2] + pv[2]) * 0.5)]
        be, bp = None, None
        for (x, y, z) in cands:
            er = (q0 * x * x + 2 * q1 * x * y + 2 * q2 * x * z + 2 * q3 * x + q4 * y * y + 2 * q5 * y * z + 2 * q6 * y
                  + q7 * z * z + 2 * q8 * z + q9)
            if be is None or er < be:
                be, bp = er, (x, y, z)
        return max(be, 0.0), bp

    heap = []
    seen = set()
    for (x, y, z) in Fl:
        for u, v in ((x, y), (y, z), (z, x)):
            k = (u, v) if u < v else (v, u)
            if k in seen:
                continue
            seen.add(k)
            if lock[u] or lock[v]:
                continue
            er, p = cost(*k)
            heap.append((er, k[0], k[1], 0, 0, p))
    del seen
    heapq.heapify(heap)
    live = nf

    def fnormal(a, b, c):
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        return (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)

    while live > target and heap:
        er, u, v, vu, vv, p = heapq.heappop(heap)
        if vdead[u] or vdead[v] or ver[u] != vu or ver[v] != vv:
            continue
        fu, fv = vf[u], vf[v]
        shared = fu & fv
        if len(shared) != 2:
            continue
        # 连接条件：u、v 共同的邻点只能是两个公共三角形的第三个点
        nu = set()
        for f in fu:
            nu.update(Fl[f])
        nvv = set()
        for f in fv:
            nvv.update(Fl[f])
        common = (nu & nvv) - {u, v}
        if len(common) != 2:
            continue
        # 翻面检查
        bad = False
        for f in (fu | fv) - shared:
            tri = Fl[f]
            old = [P[k] for k in tri]
            new = [p if (k == u or k == v) else P[k] for k in tri]
            n0 = fnormal(*old)
            n1 = fnormal(*new)
            l0 = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2]
            l1 = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2]
            if l1 < 1e-14 * (l0 + 1e-30) or l1 < 1e-16:
                bad = True
                break
            dt = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
            if dt < 0.25 * math.sqrt(l0 * l1):
                bad = True
                break
        if bad:
            continue
        # 折叠 v → u
        for f in shared:
            alive[f] = False
            live -= 1
            for k in Fl[f]:
                if k != u and k != v:
                    vf[k].discard(f)
        for f in fv - shared:
            t = Fl[f]
            Fl[f] = [u if k == v else k for k in t]
        fu |= fv
        fu -= shared
        vf[v] = set()
        vdead[v] = True
        P[u] = list(p)
        qu, qv = Q[u], Q[v]
        Q[u] = [qu[k] + qv[k] for k in range(10)]
        ver[u] += 1   # u 的旧边作废（v 的边 v 死了也作废），只重算 u 周围的边
        nb = set()
        for f in fu:
            nb.update(Fl[f])
        nb.discard(u)
        for w2 in nb:
            if lock[w2]:
                continue
            a2, b2 = (u, w2) if u < w2 else (w2, u)
            er2, p2 = cost(a2, b2)
            heapq.heappush(heap, (er2, a2, b2, ver[a2], ver[b2], p2))
    keepF = [Fl[i] for i in range(nf) if alive[i]]
    Fo = np.array(keepF, dtype=np.int64).reshape(-1, 3)
    used = np.unique(Fo)
    remap = -np.ones(nv, dtype=np.int64)
    remap[used] = np.arange(len(used))
    Vo = np.array(P, dtype=np.float64)[used]
    return Vo, remap[Fo]


# ---------------------------------------------------------------- 一座楼
def building_cap(key, T, Q, log):
    """一座楼的三角形（格）→ (V, F) 雪壳网格（格）与统计"""
    t0 = time.time()
    q = {k: (v * S if k not in ('slope', 'edge') else v) for k, v in Q.items()}
    q['amin'] = Q['amin'] * S * S
    lo, hi = T.reshape(-1, 3).min(0), T.reshape(-1, 3).max(0)
    pad = q['ov'] + q['ovw'] + 6 * q['g'] + q['smooth'] * 3
    g = q['g']
    # 先粗算承雪面积定格子大小
    for attempt in range(6):
        x0, z0 = lo[0] - pad, lo[2] - pad
        nx, nz = int(math.ceil((hi[0] - lo[0] + 2 * pad) / g)), int(math.ceil((hi[2] - lo[2] + 2 * pad) / g))
        H, NY = raster_top(T, g, x0, z0, nx, nz, q['hmin'])
        cos_lim = math.cos(math.radians(Q['slope']))
        patch = (H >= q['hmin']) & (NY >= cos_lim)
        ncell = int(patch.sum())
        if ncell <= MAXCELL or attempt == 5:
            break
        g *= math.sqrt(ncell / MAXCELL) * 1.02
    q['g'] = g
    # 去掉单格的噪点（坡面上偶尔一格是陡的小三角形）：先补 1 格的洞
    cover = H > -np.inf
    near = ndimage.binary_closing(patch, structure=np.ones((3, 3)), iterations=1) & cover & (H >= q['hmin'])
    patch = patch | (near & (NY >= cos_lim * 0.6))
    # 按高度连续分块
    tau = g * math.tan(math.radians(70))
    N = nx * nz
    idx = np.arange(N).reshape(nx, nz)
    m1 = patch[:-1, :] & patch[1:, :] & (np.abs(H[:-1, :] - H[1:, :]) <= tau)
    m2 = patch[:, :-1] & patch[:, 1:] & (np.abs(H[:, :-1] - H[:, 1:]) <= tau)
    rows = np.concatenate([idx[:-1, :][m1], idx[:, :-1][m2]])
    cols = np.concatenate([idx[1:, :][m1], idx[:, 1:][m2]])
    G = coo_matrix((np.ones(len(rows), dtype=np.int8), (rows, cols)), shape=(N, N))
    ncomp, lab = connected_components(G, directed=False)
    lab = lab.reshape(nx, nz)
    lab[~patch] = -1
    sizes = np.bincount(lab[patch], minlength=ncomp)
    amin_cells = q['amin'] / (g * g)
    plates = [k for k in np.argsort(-sizes) if sizes[k] >= max(amin_cells, 3)]
    Vs, Fs, area, perim = [], [], 0.0, 0.0
    base = 0
    wpad = int(math.ceil(pad / g)) + 2
    objs = ndimage.find_objects(lab + 1)
    for k in plates:
        sl = objs[k]
        i0, i1 = max(sl[0].start - wpad, 0), min(sl[0].stop + wpad, nx)
        j0, j1 = max(sl[1].start - wpad, 0), min(sl[1].stop + wpad, nz)
        inP = lab[i0:i1, j0:j1] == k
        Hw = H[i0:i1, j0:j1]
        phi, St, Hb = plate_fields(Hw, inP, g, q)
        V, F = mesh_plate(phi, St, Hb, x0 + i0 * g, z0 + j0 * g, g)
        if len(F) == 0:
            continue
        a_m2 = inP.sum() * g * g / (S * S)
        area += a_m2
        perim += (inP ^ ndimage.binary_erosion(inP)).sum() * g / S
        Vs.append(V)
        Fs.append(F + base)
        base += len(V)
    if not Fs:
        return None
    V = np.concatenate(Vs)
    F = np.concatenate(Fs)
    n0 = len(F)
    target = int(min(TRI_MAX, max(400, 14 * area + 34 * perim + 24 * len(Fs))))
    V, F = qem(V, F, target)
    st = dict(key=key, g=g / S, plates=len(Fs), area=area, perim=perim, tri0=n0, tri=len(F), sec=time.time() - t0)
    return V, F, st


# ---------------------------------------------------------------- 法线、UV、写 GLB
def finish(V, F, crease=55.0):
    """按角分棱的法线（每个角的法线 = 这个点周围和这个面夹角小于 crease 的面的面积加权平均）、按法线方向投影的 UV；拆点"""
    p0, p1, p2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    fa = np.linalg.norm(fn, axis=1)
    fu = fn / np.maximum(fa, 1e-12)[:, None]
    nv = len(V)
    corners = F.reshape(-1)
    cf = np.repeat(np.arange(len(F)), 3)
    order = np.argsort(corners, kind='stable')
    cs = corners[order]
    starts = np.searchsorted(cs, np.arange(nv + 1))
    cosl = math.cos(math.radians(crease))
    cn = np.zeros((len(corners), 3))
    for v in range(nv):
        s0, s1 = starts[v], starts[v + 1]
        if s0 == s1:
            continue
        ids = order[s0:s1]
        fs = cf[ids]
        U = fu[fs]
        Wt = fn[fs]
        sim = U @ U.T >= cosl
        acc = sim.astype(np.float64) @ Wt
        acc /= np.maximum(np.linalg.norm(acc, axis=1), 1e-12)[:, None]
        cn[ids] = acc
    # 角 → 拆点：同一个点、法线差不多的角共用
    qn = np.round(cn * 64).astype(np.int64)
    keyv = np.concatenate([corners[:, None], qn], 1)
    uk, inv = np.unique(keyv, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    nn = np.zeros((len(uk), 3))
    np.add.at(nn, inv, cn)
    nn /= np.maximum(np.linalg.norm(nn, axis=1), 1e-12)[:, None]
    pos = V[uk[:, 0]]
    # UV：朝上的按 (x, z)，朝侧面的按 (x 或 z, y)
    ay, ax, az = np.abs(nn[:, 1]), np.abs(nn[:, 0]), np.abs(nn[:, 2])
    uv = np.where((ay >= 0.55)[:, None], pos[:, [0, 2]], np.where((ax >= az)[:, None], pos[:, [2, 1]], pos[:, [0, 1]])) / UVS
    return pos, nn, uv, inv.reshape(-1, 3)


def write_glb(path, items):
    """items: [(节点名, 平移, pos, nrm, uv, idx)] → 一个 GLB（一种白色材质，不带贴图：游戏里换成 Roblox 的 Snow 材质）"""
    J = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield snowcap.py'}, 'scene': 0, 'scenes': [{'name': 'SnowCaps', 'nodes': []}],
         'nodes': [], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [],
         'materials': [{'name': 'B_snowcap', 'pbrMetallicRoughness': {'baseColorFactor': [0.871, 0.906, 0.939, 1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.92}}]}
    blob = bytearray()

    def view(data, target):
        while len(blob) % 4:
            blob.append(0)
        o = len(blob)
        blob.extend(data)
        J['bufferViews'].append({'buffer': 0, 'byteOffset': o, 'byteLength': len(data), 'target': target})
        return len(J['bufferViews']) - 1

    def acc(arr, typ, ctype, target, minmax=False):
        a = {'bufferView': view(np.ascontiguousarray(arr).tobytes(), target), 'componentType': ctype, 'count': len(arr), 'type': typ}
        if minmax:
            a['min'] = [float(v) for v in arr.min(0)]
            a['max'] = [float(v) for v in arr.max(0)]
        J['accessors'].append(a)
        return len(J['accessors']) - 1
    for name, tr, pos, nrm, uv, idx in items:
        it = idx.reshape(-1)
        ii = acc(it.astype(np.uint16), 'SCALAR', 5123, 34963) if len(pos) < 65536 else acc(it.astype(np.uint32), 'SCALAR', 5125, 34963)
        prim = {'attributes': {'POSITION': acc(pos.astype(np.float32), 'VEC3', 5126, 34962, True), 'NORMAL': acc(nrm.astype(np.float32), 'VEC3', 5126, 34962),
                               'TEXCOORD_0': acc(uv.astype(np.float32), 'VEC2', 5126, 34962)}, 'indices': ii, 'material': 0}
        J['meshes'].append({'name': name, 'primitives': [prim]})
        J['nodes'].append({'name': name, 'mesh': len(J['meshes']) - 1, 'translation': [round(float(x), 4) for x in tr]})
        J['scenes'][0]['nodes'].append(len(J['nodes']) - 1)
    while len(blob) % 4:
        blob.append(0)
    J['buffers'].append({'byteLength': len(blob)})
    js = json.dumps(J, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)


def fmt(v):
    s = ('%.3f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def _work(args):
    key, T, Q = args
    logs = []
    r = building_cap(key, T, Q, logs.append)
    if r is None:
        return key, None, logs
    V, F, st = r
    return key, (V, F, st), logs


def main():
    ap = argparse.ArgumentParser(description='给建筑 GLB 生成屋顶积雪（models/bld/snowcaps.glb + SnowCapMeta.lua）')
    ap.add_argument('pairs', nargs='*', help='成对的 <glb> <元数据.lua>')
    ap.add_argument('--out', default='models/bld/snowcaps.glb')
    ap.add_argument('--meta', default='src/ReplicatedStorage/SnowCapMeta.lua')
    ap.add_argument('--only', default='', help='只做这些键（逗号分开；调试用，输出照样只有这几座）')
    ap.add_argument('--jobs', type=int, default=max(1, min(4, os.cpu_count() or 1)))
    ap.add_argument('--dump', default='', help='另存一份 JSON（每座的统计），调试用')
    a = ap.parse_args()
    pairs = a.pairs
    if not pairs:
        pairs = ['models/bld/snow.glb', 'src/ReplicatedStorage/SnowMeta.lua', 'models/bld/buildings.glb', 'src/ReplicatedStorage/BuildingMeta.lua']
        if os.path.exists('models/bld/village.glb') and os.path.exists('src/ReplicatedStorage/VillageMeta.lua'):
            pairs += ['models/bld/village.glb', 'src/ReplicatedStorage/VillageMeta.lua']
    if len(pairs) % 2:
        raise SystemExit('要成对给 <glb> <元数据.lua>')
    only = set(x for x in a.only.split(',') if x)
    jobs, src = [], {}
    for k in range(0, len(pairs), 2):
        glb, meta = pairs[k], pairs[k + 1]
        pk = load_pack(glb, meta, print)
        n = 0
        for key in sorted(pk):
            if key in src or (only and key not in only):
                continue
            src[key] = os.path.basename(glb)
            jobs.append((key, pk[key][0], P))
            n += 1
        print('%s：%d 座' % (glb, n))
    t0 = time.time()
    res = {}
    if a.jobs > 1 and len(jobs) > 1:
        from concurrent.futures import ProcessPoolExecutor
        jobs.sort(key=lambda j: -len(j[1]))
        with ProcessPoolExecutor(a.jobs) as ex:
            for key, r, logs in ex.map(_work, jobs):
                res[key] = r
                for m in logs:
                    print(m)
    else:
        for j in jobs:
            key, r, logs = _work(j)
            res[key] = r
            for m in logs:
                print(m)
    items, meta, stats = [], {}, {}
    xoff, total = 0.0, 0
    for key in sorted(res):
        r = res[key]
        if r is None:
            print('%-12s 没有挂得住雪的面' % key)
            continue
        V, F, st = r
        pos, nrm, uv, idx = finish(V, F)
        lo, hi = pos.min(0), pos.max(0)
        c = (lo + hi) / 2
        s = hi - lo
        items.append(('B_%s__snow' % key, [xoff + c[0], c[1], c[2]], pos - c, nrm, uv, idx))
        meta[key] = {'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in s], 'tris': int(len(idx)), 'src': src[key]}
        stats[key] = st
        total += len(idx)
        xoff += s[0] + 40
        print('%-12s %-14s 格 %.3f 米  承雪面 %3d 块 %6.1f 平方米  周长 %6.1f 米  三角形 %6d → %5d  %.1f 秒' % (
            key, src[key], st['g'], st['plates'], st['area'], st['perim'], st['tri0'], st['tri'], st['sec']))
    os.makedirs(os.path.dirname(a.out) or '.', exist_ok=True)
    write_glb(a.out, items)
    L = ['-- 自动生成（tools/models/snowcap.py），别手改：建筑屋顶的积雪（models/bld/snowcaps.glb，按 %s 的屋面生成）' % '、'.join(sorted(set(src.values()))),
         '--   [键] = { c 中心, s 大小（格，同 parts：相对楼的占地中心、地面，X 右、Y 上、−Z 正面）, tris 三角形数, src 楼在哪个 GLB }；',
         '--   导入后 MeshPart 叫 B_<键>__snow（Imports.lua 收进 Imported.Bld.<键>，和楼本身一个文件夹），World.building 在雪山地图上照这里摆',
         'return {']
    for key in sorted(meta):
        m = meta[key]
        L.append('  %s = { c = { %s }, s = { %s }, src = "%s", tris = %d },' % (key, ', '.join(fmt(x) for x in m['c']), ', '.join(fmt(x) for x in m['s']), m['src'], m['tris']))
    L.append('}')
    open(a.meta, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    if a.dump:
        json.dump({'meta': meta, 'stats': stats}, open(a.dump, 'w'), ensure_ascii=False, indent=1)
    print('写好 %s（%d 座，%d 个三角形，%.1f MB）和 %s；用时 %.0f 秒' % (a.out, len(meta), total, os.path.getsize(a.out) / 1e6, a.meta, time.time() - t0))


if __name__ == '__main__':
    main()
