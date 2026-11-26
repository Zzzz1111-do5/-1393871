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
import air_anim as A   # noqa: E402  舵面、弹舱门、座舱盖、起落架支柱
import air_kf as KF   # noqa: E402  原模型自带关键帧动画的（F-22A）：动画里会动的节点做成部件
import orient   # noqa: E402  修朝反了的面（Roblox 只画正面）
import glbvote   # noqa: E402  写完 GLB 再从 26 个方向检查一遍面朝向、法线
import airpaint   # noqa: E402  重新涂装（歼-20）、发光灯带（歼-20、歼-16）、发动机堵头（H-6、A-10）
import doorbay   # noqa: E402  舱门里补封好的舱、舱门补反面（歼-20：开了舱门别能看穿飞机）

S = B.S
CHUNK = B.CHUNK
# 单独调小的：一块里留出余量，glbfix.py 给单层板补反面时不会顶到 Roblox 一块 2 万个三角形的上限（歼-20 v4 不减面以后有一两千个三角形补不上）
CHUNKK = {'j20': 15000}

# 游戏里的型号（AirDefs）→ 网页版的模型；后面带 ~ 的去掉原机涂装（我方没有模型的用外形最接近的美军机代，原机的国籍标志、舷号都在底色贴图里），游戏里按我方涂色
ALIAS = {
    'z10': 'z10w', 'ah64e': 'ah64', 'z20': 'uh60~', 'uh60': 'uh60', 'ch47': 'ch47',
    'j20': 'j20', 'j35': 'j31', 'j15t': 'j15t', 'j16': 'j16', 'h6k': 'h6k', 'gj11': 'x47b~', 'gj2': 'mq9~',
    'a10c': 'a10', 'f35': 'f35', 'f22': 'f22a', 'mq9': 'mq9', 'b2': 'b2',
}
FLIP = {'h6k', 'x47b'}
# 模型本身没放起落架的（按飞行状态做的）：停在地上时机腹离地多高（米），同网页版 V3G_GEAR 的 lift（真实全高减模型高）
LIFT = {'j50': 1.3, 'j20': 1.25, 'f22': 1.04, 'j16': 1.6, 'j15t': 1.15}   # 歼-15T（Jeyhun1985 的）：收起起落架的样子，真机全高 5.92 米减模型高
MATFIX = {'z10w': {0: {'am': 0, 'a': 1}, 1: {'am': 0, 'a': 1}, 2: {'a': .08}}}
# 直-10：旋翼、尾桨和机身烘焙成了一体——按连通块挑出来（网页版 V3G_ROTSPLIT 的量法：c 主旋翼桨毂、z 主旋翼块的高度范围、r 离轴多远以内、tb 尾桨块范围、tc 尾桨中心）
ROTSPLIT = {'z10w': {'c': [1.21, 0, 2.95], 'z': [2.78, 3.17], 'r': 6.1, 'tb': [-7.2, -3.6, -.6, -.35, 1.3, 4.7], 'tc': [-5.41, -.46, 3.01]}}
# 歼-15 折翼（网页版 V3G_FOLD）：铰链平行机身轴线，在 |y| = y、高 z 处；x 前后范围、zr 高度范围；A 折起的角度（弧度）
# 模型自带的外挂（阿帕奇的地狱火发射架和导弹、直-10 的火箭巢和导弹）：整块去掉（按连通块，同网页版 v3gmodels.json 的 drop），
#   游戏里照选的挂载拼——打掉一枚少一枚、换挂载也对得上。范围是模型坐标（格，|x| 两边对称）：包围盒整个在里面的连通块去掉
DROP = {'ah64': [{'x': [2.4, 8.6], 'y': [1.0, 4.6], 'z': [-11.5, -4.4]}],
        'z10w': [{'x': [3.0, 6.5], 'y': [1.5, 3.6], 'z': [-3.5, 0.4]}]}
# 机头炮塔（阿帕奇的 M230 链炮、直-10 的 23 毫米炮）：原模型里和机身烘焙在一块——按连通块挑出来做成部件，游戏里跟着瞄准转（用户 11-21：直升机炮管不会转动）
#   Gun 炮（方位 + 俯仰，绕耳轴 p 转）、GunY 炮塔座（只转方位，绕 py 的竖轴）。范围是网页版坐标（米：x 前、y 左、z 上），连通块的包围盒中心在范围里的算；
#   阿帕奇：炮管 1.5 米长挂在机头下面（x 4.6～6.1）、耳轴横杆在 x 4.22 高 0.46、炮塔座顶盘在 x 4.31 高 0.99；直-10：炮管 x 5.5～6.7、炮塔球心 x 4.61 高 0.43
GUNSPLIT = {
    'ah64': {'gun': {'x': [3.7, 6.2], 'y': 0.35, 'z': [0.0, 0.6]}, 'yaw': {'x': [3.9, 4.8], 'y': 0.45, 'z': [0.6, 1.1]},
             'p': [4.27, -0.02, 0.46], 'py': [4.31, -0.02, 0.99]},
    'z10w': {'gun': {'x': [4.3, 6.8], 'y': 0.35, 'z': [0.0, 0.6]}, 'p': [4.61, 0.0, 0.43]},
}
# 直升机短翼（模型坐标）：下表面高 y、弦中间 z、翼尖 x1——挂点挂在这里（按连通块和下表面量的）
HELI_STUB = {'ah64': {'y': 4.2, 'z': -6.5, 'x1': 8.1}, 'z10w': {'y': 3.75, 'z': -1.5, 'x1': 6.6}}
# 歼-15T（Jeyhun1985 的模型，用户给的）：按这个模型量的——外翼铰链在 |y| 3.6 米、上表面高 1.8（烘焙坐标，没抬高）；平尾外段 |y| 3.7、高 1.08
FOLD_J15T = [{'g': 'Fold', 'y': 3.6, 'z': 1.8, 'x': [-6.9, .8], 'zr': [1.12, 2.4], 'A': 2.0},
             {'g': 'Tip', 'y': 3.7, 'z': 1.08, 'x': [-10.4, -6.3], 'zr': [.85, 1.11], 'A': 1.57}]
FOLD = {'j15t': FOLD_J15T, 'j15': [{'g': 'Fold', 'y': 3.47, 'z': 2.66, 'x': [-7.5, .6], 'zr': [1.6, 3.3], 'A': 2.0},
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


def segment(key):
    """读网页版模型、按部件分好三角形（网页版坐标）：机体、起落架、旋翼、折叠外翼，再切出舵面、弹舱门、座舱盖、起落架支柱（air_anim.py）"""
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
    kf = KF.load(key)   # 原模型自带动画的：烘焙时按节点分好的部件（名字就是部件名），活动方式在 tools/models/kf/<键>.json
    kfs = kf['surf'] if kf else {}
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
                # 支奴干两副旋翼都叫 rotor：前面那副是 Rotor，后面那副是 Rotor2；sf_air.py 的直升机写明了 g（卡-52 共轴：下面那副 Rotor、上面那副 Rotor2，反着转）
                others = [q for q in parts if q.get('n') == 'rotor']
                g = P.get('g') or ('Rotor2' if len(others) > 1 and P['p'][0] < max(q['p'][0] for q in others) else 'Rotor')
                rot_piv[g] = (P['p'], P.get('a', [0, 0, 1]))
            elif n == 'trotor':
                g = 'TRotor'
                rot_piv[g] = (P['p'], P.get('a', [0, 1, 0]))
            elif n in ('Gun', 'GunY'):   # sf_air.py 按连通块分好的机头炮塔（炮塔座只转方位）
                g = n
                rot_piv[g] = (P['p'], [0, 0, 1])
            elif n in kfs:
                g = n
            elif n in ('Pit', 'PitHud'):   # 原模型自带的座舱（sf_air.py 的 pitmat / pitnode）、原模型的平显（pithud）
                g = n
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
    # 有活动部件的固定翼：修朝反了的面（网页版双面渲染看不出来；Roblox 只画正面，歼-31 机翼下表面整片朝里，从下往上看机翼是透明的）
    if key in A.SURF or key in A.GEAR or kfs:
        VB, tris, src, st = orient.fix(VB, tris)
        tri_g, tri_m = tri_g[src], tri_m[src]
        print('  %s 修了朝反的面：翻过来 %d 个、补反面 %d 个（共 %d 个三角形）' % (key, st['flip'], st['dup'], st['n']))
    if key in ROTSPLIT:
        cf = ROTSPLIT[key]
        body = np.where(tri_g == 'Body')[0]
        cls = rotsplit(cf, VB, tris[body])
        tri_g[body[cls == 1]] = 'Rotor'
        tri_g[body[cls == 2]] = 'TRotor'
        rot_piv['Rotor'] = (cf['c'], [0, 0, 1])
        rot_piv['TRotor'] = (cf['tc'], [0, 1, 0])
    # 机头炮塔：机体里包围盒中心落在炮的范围里的连通块（GUNSPLIT）
    if key in GUNSPLIT:
        cf = GUNSPLIT[key]
        body = np.where(tri_g == 'Body')[0]
        lab = components(VB[:, 0:3], tris[body])
        nG = {'Gun': 0, 'GunY': 0}
        for l in np.unique(lab):
            sel = body[lab == l]
            Q = VB[tris[sel].reshape(-1), 0:3]
            c = (Q.min(axis=0) + Q.max(axis=0)) / 2
            for g, r in (('Gun', cf.get('gun')), ('GunY', cf.get('yaw'))):
                if r and r['x'][0] <= c[0] <= r['x'][1] and abs(c[1]) <= r['y'] and r['z'][0] <= c[2] <= r['z'][1]:
                    tri_g[sel] = g
                    nG[g] += len(sel)
                    break
        rot_piv['Gun'] = (cf['p'], [0, 0, 1])
        if cf.get('py'):
            rot_piv['GunY'] = (cf['py'], [0, 0, 1])
        print('  %s 拆出机头炮塔：炮 %d 个三角形、炮塔座 %d 个' % (key, nG['Gun'], nG['GunY']))
    # 折翼：重心在铰链线外侧的机体三角形（网页版坐标 y 左、x 前、z 上）
    for F in FOLD.get(key, []):
        body = np.where(tri_g == 'Body')[0]
        C = VB[tris[body], 0:3].mean(axis=1)
        sel = (np.abs(C[:, 1]) >= F['y']) & (C[:, 0] >= F['x'][0]) & (C[:, 0] <= F['x'][1]) & (C[:, 2] >= F['zr'][0]) & (C[:, 2] <= F['zr'][1])
        right = C[:, 1] < 0   # 网页版 y < 0 是右边
        tri_g[body[sel & right]] = F['g'] + 'R'
        tri_g[body[sel & ~right]] = F['g'] + 'L'
    # 活动部件：网页版按抬高后的坐标量的（V3G_BAY、V3G_PIT），这里的模型没抬高——表里的高度已经减掉了 lift
    VB, tris, tri_g, tri_m, surf = A.apply(key, VB, tris, tri_g, tri_m, A.SURF, A.GEAR, [x.get('n', '') for x in meta['mats']])
    for g, e in kfs.items():
        if not (tri_g == g).any():
            raise ValueError('%s 的部件 %s 一个三角形也没有（烘焙配置的 parts 对不上？）' % (key, g))
        if e.get('auto'):   # 弹舱门：铰链按门板的形状算
            e = KF.auto_bay(e, VB[np.unique(tris[tri_g == g].reshape(-1)), 0:3])
        surf[g] = {k: v for k, v in e.items() if k != 'deg'}
    return meta, binb, credit, VB, tris, tri_g, tri_m, rot_piv, surf


def convert(key, AD, ids):
    meta, binb, credit, VB, tris, tri_g, tri_m, rot_piv, surf = segment(key)
    # Roblox 坐标（格）
    Pw = B.rb(VB[:, 0:3])
    Nw = B.rbn(VB[:, 3:6])
    UV = VB[:, 6:8]
    # 机体：除了起落架、旋翼、去掉的外挂，其余（含切出来的舵面、舱门、座舱盖、折叠外翼）都算
    isGear = np.array([str(x).startswith('Gear') for x in tri_g], dtype=bool)
    isBody = ~isGear & ~np.isin(tri_g, ['Rotor', 'Rotor2', 'TRotor', 'Drop'])
    hb = Pw[np.unique(tris[isBody].reshape(-1))]
    blo, bhi = hb.min(0), hb.max(0)
    hasGear = bool(isGear.any())
    if hasGear:
        ground = Pw[np.unique(tris[isGear].reshape(-1))][:, 1].min()
        # 关键帧起落架（原模型的静止姿势是收起的）：按放下那一帧的机轮最低点
        kfg = [g for g, e in surf.items() if e.get('k') == 'kf' and e.get('ch') == 'gear' and str(g).startswith('Gear')]
        if kfg:
            ground = min(B.rb(KF.apply_key(surf[g], VB[np.unique(tris[tri_g == g].reshape(-1)), 0:3]))[:, 1].min() for g in kfg)
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
    order = ['Body', 'FoldR', 'FoldL', 'TipR', 'TipL'] + sorted(surf) + ['Gear', 'Rotor', 'Rotor2', 'TRotor', 'Gun', 'GunY', 'Pit', 'PitHud']
    for g in order:
        for mi in sorted(set(tri_m[tri_g == g].tolist())):
            idx_all = tris[(tri_g == g) & (tri_m == mi)]
            ck = CHUNKK.get(key, CHUNK)
            for c0 in range(0, len(idx_all), ck):
                tri = idx_all[c0:c0 + ck]
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
    # 活动部件的铰链（模型坐标）
    if surf:
        info['surf'] = {}
        for g, e in sorted(surf.items()):
            if e.get('k') == 'kf':   # 关键帧部件：支点、每帧的挪动和转动
                info['surf'][g] = KF.to_model(e, R, B.rb)
                continue
            e = dict(e)
            e['a'] = [round(float(x), 3) for x in R(e['a'])]
            e['b'] = [round(float(x), 3) for x in R(e['b'])]
            info['surf'][g] = e
    # 弹舱井（开舱时看见舱里，不是机身里面空的）：盒子的中心、大小
    wells = []
    for W in A.WELL.get(key, []):
        lo_, hi_ = R([W['x'][1], W['y'][1], W['z0']]), R([W['x'][0], W['y'][0], W['top']])
        lo, hi = np.minimum(lo_, hi_), np.maximum(lo_, hi_)
        wells.append({'c': [round(float(x), 3) for x in (lo + hi) / 2], 's': [round(float(x), 3) for x in (hi - lo)]})
    if wells:
        info['wells'] = wells
    # 飞行员（座舱里头的位置）
    if A.PIT.get(key):
        info['pit'] = [[round(float(x), 3) for x in R(p)] for p in A.PIT[key]]
    # 原模型座舱里的屏幕（sf_air.py 的 pitscr）：中心 c、朝着人的法线 n、屏幕的上方 u、宽高（格）——游戏里在这里贴我们的实时画面
    if getattr(A, 'PITSCR', {}).get(key):
        info['pitScr'] = {}
        for nm, e in A.PITSCR[key].items():
            o = {'c': [round(float(x), 3) for x in R(e['c'])], 'n': [round(float(x), 4) for x in B.rbn(e['n'])],
                 'u': [round(float(x), 4) for x in B.rbn(e['u'])], 'w': round(float(e['w']) * S, 3), 'h': round(float(e['h']) * S, 3)}
            if e.get('d'):   # 雕进原模型的显示屏：槽深（格），屏幕在槽底
                o['d'] = round(float(e['d']) * S, 4)
            o.update({k: v for k, v in e.items() if k not in ('c', 'n', 'u', 'w', 'h', 'd')})
            info['pitScr'][nm] = o
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
    # 按转好的模型量过的（tools/models/nozray.py 的 NOZM：从机尾往前打射线量出口、内径、喷口里挡着的有多深）盖掉手写的——
    #   手写的几型对不上原模型的喷口（歼-10 低 1.8 格、歼-11 在喷口后面 2.6 格、歼-6 一个圆喷管标成两个……），涡轮、尾焰、推力矢量喷口都歪着
    import nozray   # noqa: E402
    if key in nozray.NOZM:
        noz = [list(n) for n in nozray.NOZM[key]]
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


# 有活动部件（舵面、弹舱门、座舱盖、起落架支柱）的模型换个键名（<键>_v2，块叫 A_<键>_v2__<块名>）：和用户已经导入的老版本（一整块蒙皮）
#   不会重名、能同时放在 Imported.Air 里；元数据里老版本那一行原样留着（old 表），游戏先找新的、没导入新的照旧用老的（不会动）
VER = '_v3'   # v2：有活动部件；v3：再修了朝反的面（v2 导入了的照样能用，见 old 表）
# 单独换过版本的：j20 v4 是 11-18 用原模型不减面重新转的（21.9 万个三角形，原来烘焙时减到 13 万）、补了起落架和起落架舱门（tools/models/j20_gear.py）
VERK = {'j20': '_v4', 'ah64': '_v2', 'z10w': '_v2'}   # 阿帕奇、直-10 v2：拆出了机头炮塔（GUNSPLIT）


if __name__ == '__main__':
    B.WEB = sys.argv[1]
    AD = json.load(open(sys.argv[2], encoding='utf-8'))
    OUTDIR = sys.argv[3] if len(sys.argv) > 3 else 'models/air'
    META = sys.argv[4] if len(sys.argv) > 4 else 'src/ReplicatedStorage/ImportedAir.lua'
    os.makedirs(OUTDIR, exist_ok=True)
    keys = sorted(set(v.rstrip('~') for v in ALIAS.values()))
    anim = {k for k in keys if k in A.SURF or k in A.GEAR or k in GUNSPLIT}
    kname = {k: (k + VERK.get(k, VER) if k in anim else k) for k in keys}   # 导入后的键名
    old = B.old_lines(META)   # 原来元数据里各模型那一行
    # 老版本：原来元数据里这个模型的别的版本（不带后缀的一整块蒙皮版、_v2……）原样留着，用户导入的是哪一版都能用
    import re
    legacy = {}
    for k in anim:
        for ok_ in old:
            if ok_ != kname[k] and re.fullmatch(re.escape(k) + r'(_v\d+)?', ok_):
                legacy[ok_] = old[ok_]
    def vnum(x):
        m = re.search(r'_v(\d+)$', x)
        return int(m.group(1)) if m else 0
    meta_out, lua_out = {}, {}
    # 只重转这几个（环境变量 ONLY=ah64,z10w）：别的模型的 GLB 不动、元数据那一行原样留着（网页版仓库里不一定还有它们的源模型）
    only = set(x for x in os.environ.get('ONLY', '').split(',') if x)
    kept = {}
    for key in keys:
        if only and key not in only:
            if kname[key] in old:
                kept[kname[key]] = old[kname[key]]
            continue
        ids = [i for i, v in ALIAS.items() if v.rstrip('~') == key]
        meta, binb, info, out = convert(key, AD, ids)
        path = os.path.join(OUTDIR, key + '.glb')
        B.write_glb(kname[key], meta, binb, info, out, path, prefix='A_')
        glbvote.vote_file(path, log=lambda m: print('  %s%s' % (kname[key], m)))   # 最后一道面朝向检查（26 个方向看；歼-20 机头镂空就是前两道漏的）
        meta_out[key] = info
        lua_out[kname[key]] = info
        tris = sum(len(o[6]) for o in out)
        groups = sorted(set(o[1] for o in out))
        print('%-8s %7d 个三角形  %3d 块  长 %5.1f 翼展 %5.1f 高 %4.1f 格  %5.1f MB  %s  挂架 %s' % (
            kname[key], tris, len(out), info['len'], info['w'], info['h'], os.path.getsize(path) / 1e6, '/'.join(groups),
            ' '.join('%s:%d/%d' % (g, len(info['pyl'][g]), sum(1 for s in AD[g].get('st') or [] if not s.get('bay'))) for g in ids)))
    alias = {i: kname[v.rstrip('~')] + ('~' if v.endswith('~') else '') for i, v in ALIAS.items()}
    # old[型号] = 老版本的键（新的在前）：游戏先找 alias 的，没导入就挨个往下找
    alias0 = {}
    for i, v in ALIAS.items():
        base, tilde = v.rstrip('~'), ('~' if v.endswith('~') else '')
        vs = sorted([k for k in legacy if re.fullmatch(re.escape(base) + r'(_v\d+)?', k)], key=vnum, reverse=True)
        if vs:
            alias0[i] = [k + tilde for k in vs]
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/air2glb.py），别手改：网页版飞机、直升机模型原样转成的 Roblox 模型（models/air/<文件名>.glb）的元数据\n')
        f.write('--   alias：游戏里的型号 → 模型键（带 ~ 的去掉原机涂装，按我方涂色）；m[模型键] = { len 长 / w 翼展 / h 高（格，真实尺寸：1 米 = 2.8 格）,\n')
        f.write('--     parts[块名] = { g 部件（Body / Gear / Rotor / Rotor2 / TRotor / FoldR / FoldL / TipR / TipL，活动部件见 surf）, c 中心, s 大小, col 没贴图的块的颜色, a 不透明度, met 金属 },\n')
        f.write('--     gear 模型自带起落架, rotor / rotor2 / trotor = { p 支点, a 轴 }, fold[Fold / Tip] = { x 右侧铰链, y 高, A 折起的角度 }, noz 尾喷口 { x, y, z, 半径 },\n')
        f.write('--     tip 右翼尖 { x, y, 前缘 z, 后缘 z }, prof 机身中线的上 / 下表面（从 z0 起每格一个）, tails 垂尾顶 { twin 双垂尾, p }, pyl[型号][挂点] = { 机翼下表面的高, 挪到的 z, x },\n')
        f.write('--     surf[部件] = { k 动法（ail 副翼 / flap / flaperon / elevon / stab 全动平尾 / elev 升降舵 / can 鸭翼 / rud 方向舵 / fin 全动垂尾 / rv V 尾 / bay / bayS 弹舱门 /\n')
        f.write('--       canopy 座舱盖 / gear 起落架支柱 / gdoor 起落架舱门）, s 侧（1 右 −1 左）, a / b 铰链两端, sg 正角度的方向, A 开到多大（弧度）, fold / tip 跟着哪边折 },\n')
        f.write('--     wells 弹舱井 { c 中心, s 大小 }, pit 飞行员头的位置, credit 署名 }\n')
        f.write('--   old[型号] = { 老版本的键…（新的在前）}：有活动部件的模型换了键名（<键>_v3）；用户导入的是老版本时照这张表找（_v2 会动但有的面朝反了，不带后缀的一整块蒙皮不会动）\n')
        f.write('--   坐标：X 右、Y 上、−Z 朝前，高度 0 是停在地上时的地面（游戏里再往下挪 gearH 就是机体坐标）；导入后 MeshPart 叫 A_<模型键>__<块名>\n')
        f.write('return {\n  alias = ' + B.lua(alias) + ',\n  old = ' + B.lua(alias0) + ',\n  m = {\n')
        for key in sorted(lua_out):
            f.write('    %s = %s,\n' % (key, B.lua(lua_out[key])))
        for key in sorted(kept):
            f.write(kept[key] if kept[key].endswith('\n') else kept[key] + '\n')
        for key in sorted(legacy):
            f.write(legacy[key] if legacy[key].endswith('\n') else legacy[key] + '\n')
        f.write('  },\n}\n')
    # 重新涂装、灯带、发动机堵头（tools/models/airpaint.py 的 PAINT：歼-20 涂装和绿色灯带、歼-16 灯带、H-6 / A-10 堵头）——改 GLB 和刚写好的元数据那一行
    for nm, spec in airpaint.PAINT.items():
        if spec['key'] in lua_out:
            print('%-8s 涂装 / 灯带 / 堵头' % spec['key'])
            airpaint.paint(nm, os.path.join(OUTDIR, nm + '.glb'), META)
    # 舱门开口挤出舱、舱门补反面（tools/models/doorbay.py 的 SPEC）——要在涂装之后
    for nm, spec in doorbay.SPEC.items():
        if spec['key'] in lua_out:
            print('%-8s 舱、舱门反面' % spec['key'])
            doorbay.run(nm, os.path.join(OUTDIR, nm + '.glb'), META)
    if only:   # 只重转了几个：署名文件不重写（别的模型的署名信息这次没读）
        print('写好了 %s 的 GLB 和 %s' % ('、'.join(sorted(only)), META))
        sys.exit(0)
    B.write_credits(os.path.join(OUTDIR, 'credits.txt'), keys, meta_out,
                    'Roblox全面大战场的飞机、直升机模型（models/air/<模型键>.glb）：从网页版《暗剑》烘焙的模型原样转换（js/mdl/<模型键>.js）\n'
                    '  这里的改动：坐标换成 Roblox 的轴向、按 1 米 = 2.8 格缩放、原点挪到机身中心和地面；按部件（机体 / 起落架 / 旋翼 / 尾桨 / 折叠外翼）和材质切成几块，'
                    '每块不超过 %d 个三角形；超过 %d 像素的贴图缩到 %d；不减面；轰-6K、X-47B 掉头（网页版烘焙时机头朝后）；直-10 的旋翼从机身上拆开、材质改成不透明；'
                    'AH-64、直-10 去掉了模型自带的外挂（发射架、导弹、火箭巢；游戏里按选的挂载另外画）；'
                    '固定翼的舵面、弹舱门、座舱盖沿铰链线和边界线把机体三角形切开、单独成块（游戏里绕铰链转），起落架按支柱分块\n\n'
                    % (CHUNK, B.TEXMAX, B.TEXMAX))
    print('写好了 %s/*.glb、%s/credits.txt 和 %s' % (OUTDIR, OUTDIR, META))
