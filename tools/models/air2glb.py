# 网页版《暗剑》烘焙的飞机、直升机模型（js/mdl/<键>.js）→ Roblox Studio「导入 3D」用的 GLB（models/air/<键>.glb，每个模型一个）+ 游戏用的元数据
#   python3 -I tools/models/air2glb.py <网页版仓库目录> <AirDefs 导出的 JSON> [输出目录，默认 models/air] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
#   AirDefs 的 JSON：在仓库根目录 lune run tools/models/airdefs.luau > airdefs.json（挂点位置、起落架高度：挂架要挂在原模型的机翼下表面上）
# 和地面载具（tools/models/mdl2glb.py）一样原样转：最精细那档网格、不减面、原贴图和法线 / 金属粗糙度贴图、真实尺寸 1 米 = 2.8 格
#   部件：机体 Body；起落架 Gear（收起时藏起来）；主旋翼 Rotor、尾桨 TRotor、支奴干后旋翼 Rotor2（转）；歼-15 折叠的外翼 FoldR / FoldL、平尾外段 TipR / TipL
#   每个部件按材质分块：MeshPart 叫 A_<键>__<部件>_<块号>（开服时 Imports.lua 收进 ReplicatedStorage.Imported.Air.<键>）
#   坐标：X 右、Y 上、−Z 朝前；原点在机身（不含旋翼、起落架）包围盒的前后、左右中心，高度 0 = 停在地上时的地面
#     （有起落架的是机轮最低点；模型没放起落架的照网页版抬高 lift 米，游戏里用零件拼的起落架）——游戏里再往下挪 gearH 就是机体坐标
#   网页版的加工照搬（js/v3g.js）：机头朝 −x 的转 180°（V3G_FLIP：轰-6K、X-47B）、直-10 的旋翼和机身烘焙成一体按连通块拆开（V3G_ROTSPLIT）、
#     直-10 材质改不透明（V3G_MATFIX）、歼-15 折翼的铰链（V3G_FOLD）
# 元数据另外算：挂点正上方的机翼下表面高度（挂架挂上去）、翼尖、机身中线上下表面的高度（夜航灯贴着蒙皮）、垂尾顶、尾喷口（加力火焰从这里喷）
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402  贴图、材质、GLB 写出、署名、Lua 输出都和地面载具共用

S = B.S
CHUNK = B.CHUNK

# 游戏里的型号（AirDefs）→ 网页版的模型；后面带 ~ 的去掉原机涂装（我方没有模型的用外形最接近的美军机代，原机的国籍标志、舷号都在底色贴图里），游戏里按我方涂色
ALIAS = {
    'z10': 'z10w', 'ah64e': 'ah64', 'z20': 'uh60~', 'uh60': 'uh60', 'ch47': 'ch47',
    'j20': 'j20', 'j35': 'j31', 'j15t': 'j15', 'j16': 'j16', 'j50': 'j50', 'h6k': 'h6k', 'gj11': 'x47b~', 'gj2': 'mq9~',
    'a10c': 'a10', 'f35': 'f35', 'f22': 'f22', 'mq9': 'mq9', 'b2': 'b2',
}
FLIP = {'h6k', 'x47b'}
# 模型本身没放起落架的（按飞行状态做的）：停在地上时机腹离地多高（米），同网页版 V3G_GEAR 的 lift（真实全高减模型高）
LIFT = {'j50': 1.3, 'j20': 1.25, 'f22': 1.04, 'j16': 1.6}
MATFIX = {'z10w': {0: {'am': 0, 'a': 1}, 1: {'am': 0, 'a': 1}, 2: {'a': .08}}}
# 直-10：旋翼、尾桨和机身烘焙成了一体——按连通块挑出来（网页版 V3G_ROTSPLIT 的量法：c 主旋翼桨毂、z 主旋翼块的高度范围、r 离轴多远以内、tb 尾桨块范围、tc 尾桨中心）
ROTSPLIT = {'z10w': {'c': [1.21, 0, 2.95], 'z': [2.78, 3.17], 'r': 6.1, 'tb': [-7.2, -3.6, -.6, -.35, 1.3, 4.7], 'tc': [-5.41, -.46, 3.01]}}
# 歼-15 折翼（网页版 V3G_FOLD）：铰链平行机身轴线，在 |y| = y、高 z 处；x 前后范围、zr 高度范围；A 折起的角度（弧度）
# 模型自带的外挂（阿帕奇的地狱火发射架和导弹、直-10 的火箭巢和导弹）：整块去掉（按连通块，同网页版 v3gmodels.json 的 drop），
#   游戏里照选的挂载拼——打掉一枚少一枚、换挂载也对得上。范围是模型坐标（格，|x| 两边对称）：包围盒整个在里面的连通块去掉
DROP = {'ah64': [{'x': [2.4, 8.6], 'y': [1.0, 4.6], 'z': [-11.5, -4.4]}],
        'z10w': [{'x': [3.0, 6.5], 'y': [1.5, 3.6], 'z': [-3.5, 0.4]}]}
# 直升机短翼（模型坐标）：下表面高 y、弦中间 z、翼尖 x1——挂点挂在这里（按连通块和下表面量的）
HELI_STUB = {'ah64': {'y': 4.2, 'z': -6.5, 'x1': 8.1}, 'z10w': {'y': 3.75, 'z': -1.5, 'x1': 6.6}}
FOLD = {'j15': [{'g': 'Fold', 'y': 3.47, 'z': 2.66, 'x': [-7.5, .6], 'zr': [1.6, 3.3], 'A': 2.0},
                {'g': 'Tip', 'y': 3.47, 'z': 2.03, 'x': [-10.6, -5.9], 'zr': [1.85, 2.12], 'A': 1.57}]}


def flip(meta, VB):
    VB = VB.copy()
    VB[:, [0, 1, 3, 4]] *= -1
    for P in meta.get('parts', []):
        for k in ('p', 'a', 'q'):
            if k in P:
                P[k] = [-P[k][0], -P[k][1], P[k][2]]
    if meta.get('noz'):
        meta['noz'] = [[-n[0], -n[1]] + list(n[2:]) for n in meta['noz']]
    return VB


def rotsplit(cf, VB, tris):
    """直-10：机身三角形里按连通块（顶点坐标到毫米相同的算连着）挑出主旋翼、尾桨。返回每个三角形的类别 0 机身 / 1 主旋翼 / 2 尾桨"""
    q = np.round(VB[tris.reshape(-1), 0:3] * 1000).astype(np.int64)
    _, vid = np.unique(q, axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    par = np.arange(vid.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b, c in vid:
        ra, rb_, rc = find(a), find(b), find(c)
        if ra != rb_:
            par[ra] = rb_
        rb2 = find(b)
        if rb2 != rc:
            par[rb2] = rc
    root = np.array([find(v) for v in range(len(par))])
    comp = root[vid[:, 0]]
    P = VB[tris, 0:3]   # (n, 3, 3)
    out = np.zeros(len(tris), dtype=np.int8)
    tb = cf['tb']
    for r in np.unique(comp):
        sel = comp == r
        Q = P[sel].reshape(-1, 3)
        lo, hi = Q.min(0), Q.max(0)
        main = lo[2] >= cf['z'][0] and hi[2] <= cf['z'][1] and np.hypot((lo[0] + hi[0]) / 2 - cf['c'][0], (lo[1] + hi[1]) / 2 - cf['c'][1]) < cf['r']
        tail = lo[0] >= tb[0] and hi[0] <= tb[1] and lo[1] >= tb[2] and hi[1] <= tb[3] and lo[2] >= tb[4] and hi[2] <= tb[5]
        out[sel] = 1 if main else (2 if tail else 0)
    return out


def components(P, T):
    """三角形按连通块编号（顶点坐标到 0.01 格相同的算连着；标号传播 + 指针跳跃，numpy 向量化）"""
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


def ray_ud(Pt, x, z):
    """竖线 (x, z) 和三角形（Pt：(n, 3, 3)，Roblox 坐标）的交点里最低、最高的 y；打不到返回 None"""
    ax, az, bx, bz, cx, cz = Pt[:, 0, 0], Pt[:, 0, 2], Pt[:, 1, 0], Pt[:, 1, 2], Pt[:, 2, 0], Pt[:, 2, 2]
    m = (x >= np.minimum(np.minimum(ax, bx), cx)) & (x <= np.maximum(np.maximum(ax, bx), cx)) & \
        (z >= np.minimum(np.minimum(az, bz), cz)) & (z <= np.maximum(np.maximum(az, bz), cz))
    if not m.any():
        return None
    T = Pt[m]
    ax, az, bx, bz, cx, cz = T[:, 0, 0], T[:, 0, 2], T[:, 1, 0], T[:, 1, 2], T[:, 2, 0], T[:, 2, 2]
    d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    ok = np.abs(d) > 1e-12
    d = np.where(ok, d, 1)
    l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
    l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
    l3 = 1 - l1 - l2
    inside = ok & (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
    if not inside.any():
        return None
    y = (l1 * T[:, 0, 1] + l2 * T[:, 1, 1] + l3 * T[:, 2, 1])[inside]
    return float(y.min()), float(y.max())


THIN = 2.5   # 机翼、短翼最厚多少格（约 0.9 米）：比这厚的是机身、发动机舱，翼下挂点不挂在那上面


def fit_pylon(Pt, x, z, thin):
    """挂点 (x, z) 挪到原模型的机翼下面：正好在翼下就不动；否则沿前后方向找最近的一段翼面，挂在那一段弦的中间。
       thin：只认薄的（机翼、短翼）。返回 (z, 下表面 y) 或 None"""
    def ok(zz):
        h = ray_ud(Pt, x, zz)
        if h is None or (thin and h[1] - h[0] > THIN):
            return None
        return h
    if ok(z):
        return z, ok(z)[0], x
    x0 = x
    for dx in np.arange(0, 1.51, 0.25):   # 翼尖挂架：原模型的翼尖可能短一点，往里挪着找
        x = x0 - np.sign(x0) * dx
        for dz in sorted(np.arange(-20, 20.01, 0.25), key=abs):
            if ok(z + dz):
                z0 = z1 = z + dz
                while ok(z0 - 0.25) and z0 - z > -40:
                    z0 -= 0.25
                while ok(z1 + 0.25) and z1 - z < 40:
                    z1 += 0.25
                zc = (z0 + z1) / 2
                if not ok(zc):
                    zc = z + dz
                return zc, ok(zc)[0], x
    return None


def convert(key, AD, ids):
    meta, binb, credit = B.load(key)
    st = meta.get('st', 8)
    vb0, vbn = meta['vb']
    VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st).astype(np.float64)
    ib0, ibn = meta['ib']
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0).astype(np.int64)
    if key in FLIP:
        VB = flip(meta, VB)
    for mi, fx in MATFIX.get(key, {}).items():
        m = meta['mats'][mi]
        if 'am' in fx:
            m['am'] = fx['am']
        if 'a' in fx:
            c = list(m.get('c', [1, 1, 1, 1]))
            while len(c) < 4:
                c.append(1)
            c[3] = fx['a']
            m['c'] = c
            if fx['a'] < 0.99 and 'am' not in fx:
                m['am'] = 2
    parts = meta.get('parts', [])
    # 每个三角形属于哪个部件
    tri_g, tri_m, tris = [], [], []
    rot_piv = {}   # 部件名 → (支点, 轴)（网页版坐标）
    for mi, pi, s0, cnt in meta['lod'][0]:
        T = IB[s0:s0 + cnt].reshape(-1, 3)
        if pi >= 0:
            P = parts[pi]
            n = P.get('n', '')
            if n == 'gear':
                g = 'Gear'
            elif n == 'rotor':
                # 支奴干两副旋翼都叫 rotor：前面那副是 Rotor，后面那副是 Rotor2
                others = [q for q in parts if q.get('n') == 'rotor']
                g = 'Rotor2' if len(others) > 1 and P['p'][0] < max(q['p'][0] for q in others) else 'Rotor'
                rot_piv[g] = (P['p'], P.get('a', [0, 0, 1]))
            elif n == 'trotor':
                g = 'TRotor'
                rot_piv[g] = (P['p'], P.get('a', [0, 1, 0]))
            else:
                g = 'Body'
            tri_g += [g] * len(T)
        else:
            tri_g += ['Body'] * len(T)
        tri_m += [mi] * len(T)
        tris.append(T)
    tris = np.concatenate(tris)
    tri_g = np.array(tri_g, dtype=object)
    tri_m = np.array(tri_m)
    if key in ROTSPLIT:
        cf = ROTSPLIT[key]
        body = np.where(tri_g == 'Body')[0]
        cls = rotsplit(cf, VB, tris[body])
        tri_g[body[cls == 1]] = 'Rotor'
        tri_g[body[cls == 2]] = 'TRotor'
        rot_piv['Rotor'] = (cf['c'], [0, 0, 1])
        rot_piv['TRotor'] = (cf['tc'], [0, 1, 0])
    # 折翼：重心在铰链线外侧的机体三角形（网页版坐标 y 左、x 前、z 上）
    for F in FOLD.get(key, []):
        body = np.where(tri_g == 'Body')[0]
        C = VB[tris[body], 0:3].mean(axis=1)
        sel = (np.abs(C[:, 1]) >= F['y']) & (C[:, 0] >= F['x'][0]) & (C[:, 0] <= F['x'][1]) & (C[:, 2] >= F['zr'][0]) & (C[:, 2] <= F['zr'][1])
        right = C[:, 1] < 0   # 网页版 y < 0 是右边
        tri_g[body[sel & right]] = F['g'] + 'R'
        tri_g[body[sel & ~right]] = F['g'] + 'L'
    # Roblox 坐标（格）
    Pw = B.rb(VB[:, 0:3])
    Nw = B.rbn(VB[:, 3:6])
    UV = VB[:, 6:8]
    isBody = np.isin(tri_g, ['Body', 'FoldR', 'FoldL', 'TipR', 'TipL'])
    hb = Pw[np.unique(tris[isBody].reshape(-1))]
    blo, bhi = hb.min(0), hb.max(0)
    hasGear = bool((tri_g == 'Gear').any())
    if hasGear:
        ground = Pw[np.unique(tris[tri_g == 'Gear'].reshape(-1))][:, 1].min()
    else:
        ground = blo[1] - LIFT.get(key, 0) * S
    org = np.array([(blo[0] + bhi[0]) / 2, ground, (blo[2] + bhi[2]) / 2])
    # 模型自带的外挂：包围盒整个在范围里的连通块去掉
    for R0 in DROP.get(key, []):
        body = np.where(tri_g == 'Body')[0]
        cid = components(Pw - org, tris[body])
        Q = (Pw - org)[tris[body]]
        for r in np.unique(cid):
            sel = cid == r
            q = Q[sel].reshape(-1, 3)
            lo_, hi_ = q.min(0), q.max(0)
            ax_lo, ax_hi = (lo_[0], hi_[0]) if lo_[0] >= 0 else (-hi_[0], -lo_[0])
            if ax_lo >= R0['x'][0] and ax_hi <= R0['x'][1] and lo_[1] >= R0['y'][0] and hi_[1] <= R0['y'][1] and lo_[2] >= R0['z'][0] and hi_[2] <= R0['z'][1]:
                tri_g[body[sel]] = 'Drop'
    allP = Pw[np.unique(tris[tri_g != 'Drop'].reshape(-1))] - org
    lo, hi = allP.min(0), allP.max(0)
    info = {'len': float(bhi[2] - blo[2]), 'w': float(bhi[0] - blo[0]), 'h': float(hi[1]), 'parts': {}, 'credit': credit, 'gear': hasGear}

    def R(v):   # 网页版坐标（米）→ 模型坐标（格）
        return B.rb(np.asarray(v, dtype=np.float64)) - org
    # 按（部件，材质）分块
    out = []
    count = {}
    order = ['Body', 'FoldR', 'FoldL', 'TipR', 'TipL', 'Gear', 'Rotor', 'Rotor2', 'TRotor']
    for g in order:
        for mi in sorted(set(tri_m[tri_g == g].tolist())):
            idx_all = tris[(tri_g == g) & (tri_m == mi)]
            for c0 in range(0, len(idx_all), CHUNK):
                tri = idx_all[c0:c0 + CHUNK]
                u, inv = np.unique(tri.reshape(-1), return_inverse=True)
                P = Pw[u] - org
                count[g] = count.get(g, 0) + 1
                name = '%s_%d' % (g, count[g])
                plo, phi = P.min(0), P.max(0)
                c = (plo + phi) / 2
                info['parts'][name] = {'g': g, 'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in np.maximum(phi - plo, 0.02)]}
                m = meta['mats'][mi]
                if not m.get('t'):   # 没有底色贴图：游戏里照这个上色（Studio 导入不一定把材质颜色带过来）
                    lin = m.get('c', [1, 1, 1, 1])
                    srgb = [int(round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in (max(0.0, min(1.0, float(v))) for v in lin[:3])]
                    info['parts'][name]['col'] = srgb
                    if m.get('am', 0) == 2 and len(lin) > 3 and lin[3] < 0.99:
                        info['parts'][name]['a'] = round(float(lin[3]), 2)
                    if (m.get('mr') or [0, 0.8])[0] > 0.5:
                        info['parts'][name]['met'] = 1
                out.append((name, g, mi, P - c, Nw[u], UV[u], inv.reshape(-1, 3).astype(np.uint32)))
    # 旋翼：支点、轴
    for g, (p, a) in rot_piv.items():
        if (tri_g == g).any():
            info[g.lower()] = {'p': [round(float(x), 3) for x in R(p)], 'a': [round(float(x), 4) for x in B.rbn(np.asarray(a, dtype=np.float64))]}
    # 折翼：右边那一侧的铰链（x、y），左边对称；A 折起的角度
    for F in FOLD.get(key, []):
        hp = R([0, -F['y'], F['z']])
        info.setdefault('fold', {})[F['g']] = {'x': round(float(hp[0]), 3), 'y': round(float(hp[1]), 3), 'A': F['A']}
    # 尾喷口：出口中心、半径（不在中线上的左右各一个）
    noz = []
    for n in meta.get('noz') or []:
        for sy in ([1, -1] if abs(n[1]) > 0.05 else [1]):
            p = R([n[0], n[1] * sy, n[2]])
            noz.append([round(float(p[0]), 3), round(float(p[1]), 3), round(float(p[2]), 3), round(float(n[3]) * S, 3)])
    if noz:
        info['noz'] = noz
    # —— 灯、挂架贴着原模型的蒙皮：机体（含折叠外翼）的三角形
    Pt = (Pw - org)[tris[isBody]]   # (n, 3, 3)
    V = (Pw - org)[np.unique(tris[isBody].reshape(-1))]
    # 右翼尖（最外的点）和那一段的前后缘
    xm = V[:, 0].max()
    tipV = V[V[:, 0] > xm - 0.6]
    info['tip'] = [round(float(xm), 3), round(float(tipV[:, 1].mean()), 3), round(float(tipV[:, 2].min()), 3), round(float(tipV[:, 2].max()), 3)]
    # 机身中线（|x| < 1.2 格）的上、下表面：每格一段
    cl = V[np.abs(V[:, 0]) < 1.2]
    z0 = float(np.floor(cl[:, 2].min()))
    nb = int(np.ceil(cl[:, 2].max() - z0)) + 1
    bi = np.clip(((cl[:, 2] - z0)).astype(int), 0, nb - 1)
    top = [None] * nb
    bot = [None] * nb
    for k in range(nb):
        q = cl[bi == k]
        if len(q):
            top[k], bot[k] = round(float(q[:, 1].max()), 2), round(float(q[:, 1].min()), 2)
    for arr in (top, bot):   # 空段照前后补上
        last = next((x for x in arr if x is not None), 0)
        for k in range(nb):
            if arr[k] is None:
                arr[k] = last
            last = arr[k]
    info['prof'] = {'z0': z0, 'top': top, 'bot': bot}
    # 垂尾顶的尾灯：后半段最高的点；双垂尾（最高点离中线远）左右各一个，取那一片顶上最靠后的点
    rear = V[V[:, 2] > 0]
    if len(rear):
        k = int(np.argmax(rear[:, 1]))
        pk = rear[k]
        twin = bool(abs(pk[0]) > 1.5)
        band = rear[(rear[:, 1] > pk[1] - 0.5) & (np.abs(np.abs(rear[:, 0]) - abs(pk[0])) < 1.0)]
        z = float(band[:, 2].max())
        x = abs(float(pk[0])) if twin else 0.0
        info['tails'] = {'twin': twin, 'p': [round(x, 3), round(float(pk[1]), 3), round(z, 3)]}
    # 挂点：照型号表的展向位置（x），前后挪到原模型的机翼（短翼）弦上、高度贴下表面（同一个模型可能给几个型号用，各按各的挂点算）
    #   机身下面的挂点（进气道、机腹）不要求薄；直升机的都在短翼上
    pyl = {}
    for gid in ids:
        D = AD.get(gid)
        if not D:
            continue
        half = (D['fus'][1] / 2 + 1.5) if D.get('fus') else 0
        surf = {}
        for i, s in enumerate(D.get('st') or []):
            if s.get('bay') or D.get('style') == 'utility':   # 弹舱里的不动；通用直升机的挂架是零件拼的（原模型没有短翼）
                continue
            x, z = s['pos'][0], s['pos'][2]
            if key in HELI_STUB:   # 直升机：挂在短翼下面（量好的位置）
                st_ = HELI_STUB[key]
                surf[i + 1] = [st_['y'], st_['z'], round(float(np.sign(x) * min(abs(x), st_['x1'])), 3)]
                continue
            thin = D['kind'] == 'heli' or abs(x) > half
            r = fit_pylon(Pt, x, z, thin)
            if r:
                surf[i + 1] = [round(float(r[1]), 3), round(float(r[0]), 3), round(float(r[2]), 3)]   # [下表面 y, z, x]
        pyl[gid] = surf
    info['pyl'] = pyl
    return meta, binb, info, out


if __name__ == '__main__':
    B.WEB = sys.argv[1]
    AD = json.load(open(sys.argv[2], encoding='utf-8'))
    OUTDIR = sys.argv[3] if len(sys.argv) > 3 else 'models/air'
    META = sys.argv[4] if len(sys.argv) > 4 else 'src/ReplicatedStorage/ImportedAir.lua'
    os.makedirs(OUTDIR, exist_ok=True)
    keys = sorted(set(v.rstrip('~') for v in ALIAS.values()))
    meta_out = {}
    for key in keys:
        ids = [i for i, v in ALIAS.items() if v.rstrip('~') == key]
        meta, binb, info, out = convert(key, AD, ids)
        path = os.path.join(OUTDIR, key + '.glb')
        B.write_glb(key, meta, binb, info, out, path, prefix='A_')
        meta_out[key] = info
        tris = sum(len(o[6]) for o in out)
        groups = sorted(set(o[1] for o in out))
        print('%-5s %7d 个三角形  %3d 块  长 %5.1f 翼展 %5.1f 高 %4.1f 格  %5.1f MB  %s  挂架 %s' % (
            key, tris, len(out), info['len'], info['w'], info['h'], os.path.getsize(path) / 1e6, '/'.join(groups),
            ' '.join('%s:%d/%d' % (g, len(info['pyl'][g]), sum(1 for s in AD[g].get('st') or [] if not s.get('bay'))) for g in ids)))
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/air2glb.py），别手改：网页版飞机、直升机模型原样转成的 Roblox 模型（models/air/<模型键>.glb）的元数据\n')
        f.write('--   alias：游戏里的型号 → 模型键（带 ~ 的去掉原机涂装，按我方涂色）；m[模型键] = { len 长 / w 翼展 / h 高（格，真实尺寸：1 米 = 2.8 格）,\n')
        f.write('--     parts[块名] = { g 部件（Body / Gear / Rotor / Rotor2 / TRotor / FoldR / FoldL / TipR / TipL）, c 中心, s 大小, col 没贴图的块的颜色, a 不透明度, met 金属 },\n')
        f.write('--     gear 模型自带起落架, rotor / rotor2 / trotor = { p 支点, a 轴 }, fold[Fold / Tip] = { x 右侧铰链, y 高, A 折起的角度 }, noz 尾喷口 { x, y, z, 半径 },\n')
        f.write('--     tip 右翼尖 { x, y, 前缘 z, 后缘 z }, prof 机身中线的上 / 下表面（从 z0 起每格一个）, tails 垂尾顶 { twin 双垂尾, p }, pyl[型号][挂点] = { 机翼下表面的高, 挪到的 z, x }, credit 署名 }\n')
        f.write('--   坐标：X 右、Y 上、−Z 朝前，高度 0 是停在地上时的地面（游戏里再往下挪 gearH 就是机体坐标）；导入后 MeshPart 叫 A_<模型键>__<块名>\n')
        f.write('return {\n  alias = ' + B.lua(ALIAS) + ',\n  m = {\n')
        for key in keys:
            f.write('    %s = %s,\n' % (key, B.lua(meta_out[key])))
        f.write('  },\n}\n')
    B.write_credits(os.path.join(OUTDIR, 'credits.txt'), keys, meta_out,
                    'Roblox全面大战场的飞机、直升机模型（models/air/<模型键>.glb）：从网页版《暗剑》烘焙的模型原样转换（js/mdl/<模型键>.js）\n'
                    '  这里的改动：坐标换成 Roblox 的轴向、按 1 米 = 2.8 格缩放、原点挪到机身中心和地面；按部件（机体 / 起落架 / 旋翼 / 尾桨 / 折叠外翼）和材质切成几块，'
                    '每块不超过 %d 个三角形；超过 %d 像素的贴图缩到 %d；不减面；轰-6K、X-47B 掉头（网页版烘焙时机头朝后）；直-10 的旋翼从机身上拆开、材质改成不透明；'
                    'AH-64、直-10 去掉了模型自带的外挂（发射架、导弹、火箭巢；游戏里按选的挂载另外画）\n\n'
                    % (CHUNK, B.TEXMAX, B.TEXMAX))
    print('写好了 %s/*.glb、%s/credits.txt 和 %s' % (OUTDIR, OUTDIR, META))
