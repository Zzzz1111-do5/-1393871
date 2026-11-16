# Sketchfab 上直接下载的地面载具模型（网页版没有的型号）→ 和网页版烘焙模型（js/mdl/<键>.js）一样的数据，交给 mdl2glb.py 转成 GLB + 元数据
#   python3 -I tools/models/mdl2glb.py <网页版仓库目录> --sf <下载目录>
#   下载目录里每个模型放一个 <模型键>.zip：Sketchfab 模型页「下载 → glTF」的压缩包（要登录；模型号见下面 SF 的 uid）。
#   直接从压缩包里读，不解压。
# 收模型的规矩同网页版：只要 CC-BY / CC0；简介、节点名、材质名、贴图看得出是从游戏里扒的不收（Muhamad Mirza Arrafi 的 XM8、730 近防炮、
#   SX2190 卡车就是这样没收的：像是游戏资源——节点名是游戏资源那套、三档附加装甲叠在一起、贴图是游戏式的图集）。
import io, json, math, urllib.parse, zipfile
import numpy as np
from PIL import Image

# 模型键 → 来源、署名、加工方法。alias：游戏里哪些型号用它（VehDefs 的型号）
SF = {
    'ztq15': {
        'uid': 'e9863d7b5a474eb0800fc59e82f9ebd4',
        'title': 'PLA LIGHT MAIN BATTLE TANK TYPE 15 HEAVY', 'author': 'lhc526', 'user': 'https://sketchfab.com/lhc526',
        'url': 'https://sketchfab.com/3d-models/pla-light-main-battle-tank-type-15-heavy-e9863d7b5a474eb0800fc59e82f9ebd4',
        'license': 'CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)', 'name': 'ZTQ-15 轻型坦克', 'alias': ['ztq15'],
        # 作者用手机扫描（RealityScan）的一个 1:65 左右的坦克模型，连着下面一块木桌面；炮塔往右转了 30° 左右
        'scan': {
            'L': 19 / 2.8,      # 车体长（米）：照 VehDefs 的 L（1 米 = 2.8 格），按它定放大倍数
            'cut': 0.001,       # 桌面以上多高才算车（模型单位，米）
            'band': (0.004, 0.014),   # 量车体轴线、长宽用的高度段（履带、车体侧面）
            'hcut': 0.0258,     # 炮塔和车体从这个高度分开（炮塔座圈上沿）
            'gun_r': 0.0024,    # 炮管周围多粗的范围算炮（模型单位）
            'mant': 0.0265,     # 炮管从炮塔正面伸出来的位置（离炮塔转轴，往前为正）
            'trun': 0.006,      # 炮耳轴在炮管根部后面多远
            'tiles': 2,         # 贴图按贴图坐标分成 2 × 2 块，各自一张 1024 的图
        },
        'mods': '去掉扫描带的木桌面；按车体轴线摆正，炮塔转回正前方，拆成车体、炮塔、炮管；炮塔座圈补一块底板；'
                '按真车大小放大（车体长 6.8 米）；贴图按图集分成 4 块，各自裁剪、缩到 1024 像素',
    },
}


def _gltf_from_zip(path):
    """Sketchfab 的 glTF 压缩包：scene.gltf + 二进制 + 贴图，都在内存里读"""
    z = zipfile.ZipFile(path)
    names = z.namelist()
    gl = [n for n in names if n.endswith('.gltf')]
    if len(gl) != 1:
        raise ValueError('%s 里要有一个 .gltf，有 %d 个' % (path, len(gl)))
    base = gl[0].rsplit('/', 1)[0] + '/' if '/' in gl[0] else ''
    J = json.loads(z.read(gl[0]))

    def rd(uri):
        p = (base + urllib.parse.unquote(uri)).replace('\\', '/')
        if p not in names:
            raise ValueError('压缩包里没有 ' + p)
        return z.read(p)
    bufs = [rd(b['uri']) for b in J['buffers']]
    return J, bufs, rd


CT = {5120: 'i1', 5121: 'u1', 5122: 'i2', 5123: 'u2', 5125: 'u4', 5126: 'f4'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def _node_mat(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    M = np.eye(4)
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M[:3, :3] = R * np.array(n.get('scale', [1, 1, 1]))
    M[:3, 3] = n.get('translation', [0, 0, 0])
    return M


def _meshes(J, bufs):
    """所有三角形，按节点矩阵变到世界坐标：返回 P（顶点）、N（法线）、UV、T（三角形，顶点下标）、每个三角形的材质号"""
    def acc(i):
        a = J['accessors'][i]
        bv = J['bufferViews'][a['bufferView']]
        n, dt = NC[a['type']], np.dtype('<' + CT[a['componentType']])
        stride = bv.get('byteStride', 0) or dt.itemsize * n
        arr = np.ndarray((a['count'], n), dtype=dt, buffer=bufs[bv['buffer']], offset=bv.get('byteOffset', 0) + a.get('byteOffset', 0),
                         strides=(stride, dt.itemsize)).copy()
        if a.get('normalized'):
            arr = arr.astype(np.float64) / np.iinfo(dt).max
        return arr
    Ps, Ns, UVs, Ts, Ms = [], [], [], [], []
    nv = 0

    def walk(i, M):
        nonlocal nv
        n = J['nodes'][i]
        W = M @ _node_mat(n)
        if 'mesh' in n:
            for p in J['meshes'][n['mesh']]['primitives']:
                if p.get('mode', 4) != 4:
                    continue
                at = p['attributes']
                P = acc(at['POSITION']).astype(np.float64)
                N = acc(at['NORMAL']).astype(np.float64) if 'NORMAL' in at else np.zeros_like(P)
                UV = acc(at['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in at else np.zeros((len(P), 2))
                I = acc(p['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in p else np.arange(len(P)).reshape(-1, 3)
                if np.linalg.det(W[:3, :3]) < 0:   # 镜像的节点：三角形绕向反过来
                    I = I[:, ::-1]
                N = N @ np.linalg.inv(W[:3, :3])   # 法线按逆转置变换
                Ps.append(P @ W[:3, :3].T + W[:3, 3])
                Ns.append(N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12))
                UVs.append(UV)
                Ts.append(I + nv)
                Ms.append(np.full(len(I), p.get('material', 0)))
                nv += len(P)
        for c in n.get('children', []):
            walk(c, W)
    for r in J['scenes'][J.get('scene', 0)]['nodes']:
        walk(r, np.eye(4))
    return np.concatenate(Ps), np.concatenate(Ns), np.concatenate(UVs), np.concatenate(Ts), np.concatenate(Ms)


def _components(F):
    """三角形（焊接后的顶点号）按连通块编号：标号传播 + 指针跳跃"""
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


def _scan(cfg, P, N, UV, T, tex=None):
    """手机扫描的模型：去掉桌面、摆正、拆炮塔和炮管、放大到真车大小。返回 V3G 坐标（x 前、y 左、z 上，米）的顶点和分好组的三角形"""
    q = np.round(P * 1e6).astype(np.int64)
    _, wid = np.unique(q, axis=0, return_inverse=True)   # 扫描分几块网格，块之间的顶点重复：焊起来算连通
    wid = wid.reshape(-1)
    Pt = P[T]
    C = Pt.mean(1)
    FN = np.cross(Pt[:, 1] - Pt[:, 0], Pt[:, 2] - Pt[:, 0])
    A = np.linalg.norm(FN, axis=1) / 2
    FN /= np.maximum(np.linalg.norm(FN, axis=1, keepdims=True), 1e-15)
    # 桌面：朝上的面按高度统计面积，最多的那一层；再用附近的面拟合一个平面（桌面不一定绝对水平）
    up = FN[:, 1] > 0.9
    lo, hi = P[:, 1].min(), P[:, 1].max()
    hist, edges = np.histogram(C[up, 1], bins=400, range=(lo, hi), weights=A[up])
    y0 = (edges[np.argmax(hist)] + edges[np.argmax(hist) + 1]) / 2
    m = up & (np.abs(C[:, 1] - y0) < (hi - lo) * 0.02)
    X = np.c_[C[m, 0], C[m, 2], np.ones(m.sum())]
    (a, b, c), *_ = np.linalg.lstsq(X, C[m, 1], rcond=None)
    n = np.array([-a, 1.0, -b])
    n /= np.linalg.norm(n)
    o = np.array([0.0, c, 0.0])
    hgt = (P - o) @ n                       # 每个顶点离桌面多高
    keep = hgt[T].min(1) > cfg['cut']
    idx = np.nonzero(keep)[0]
    lab = _components(wid[T[keep]])
    u, cnt = np.unique(lab, return_counts=True)
    tri = idx[lab == u[np.argmax(cnt)]]      # 桌面以上最大的一块就是车
    V = np.unique(T[tri])
    # 车体轴线：履带、车体侧面那一段高度的点做主成分
    band = V[(hgt[V] > cfg['band'][0]) & (hgt[V] < cfg['band'][1])]
    c0 = P[band].mean(0)
    X = P[band] - c0
    X -= np.outer(X @ n, n)
    w, vec = np.linalg.eigh(X.T @ X)
    ax = vec[:, np.argmax(w)]
    ax -= n * (ax @ n)
    ax /= np.linalg.norm(ax)
    lf = np.cross(n, ax)
    fu, fv = (P - c0) @ ax, (P - c0) @ lf   # 车体坐标：u 沿轴线、v 往左、hgt 往上
    bu, bv = fu[band], fv[band]
    hull_u = (bu.min(), bu.max())
    hull_v = (bv.min(), bv.max())
    vc = (hull_v[0] + hull_v[1]) / 2
    # 车头：炮管伸出去的那头（两头 1 厘米内点少的那头）
    Vu = fu[V]
    front = -1 if ((Vu - Vu.min()) < 0.01).sum() < ((Vu.max() - Vu) < 0.01).sum() else 1
    # 炮管：车体前面伸出去那段，拟合一条线
    lowfront = (hull_u[0] if front < 0 else hull_u[1])
    bar = V[(front * (fu[V] - lowfront) > 0.0015) & (hgt[V] > cfg['band'][1])]
    Ab = np.c_[fu[bar], np.ones(len(bar))]
    (kv, v0), *_ = np.linalg.lstsq(Ab, fv[bar], rcond=None)
    (kh, h0), *_ = np.linalg.lstsq(Ab, hgt[bar], rcond=None)
    d = np.array([front, front * kv])
    d /= np.linalg.norm(d)                  # 炮管朝前的方向（u, v）
    # 炮塔转轴：炮管轴线和车体中线的交点
    pu = (vc - v0) / kv if abs(kv) > 1e-6 else 0.0
    piv = np.array([pu, vc])
    yaw = math.atan2(front * d[1], front * d[0])   # 炮塔在车体坐标里转了多少（弧度，往左为正）
    # 炮塔坐标：s 沿炮管往前、t 往左
    du, dv = fu - piv[0], fv - piv[1]
    s = du * d[0] + dv * d[1]
    t = -du * d[1] + dv * d[0]
    hax = h0 + kh * fu                      # 炮管轴线在这里的高度
    # 炮塔范围：比车体高的点（炮塔顶）在炮塔坐标里的外框
    top = V[hgt[V] > cfg['hcut'] + 0.005]
    smin, smax = s[top].min(), s[top].max()
    tmin, tmax = t[top].min(), t[top].max()
    sfront = max(smax, cfg['mant'])   # 炮塔正面（炮管从这里往前算炮）
    mg = 0.001
    Tt = T[tri]
    Cs, Ct, Ch = s[Tt].mean(1), t[Tt].mean(1), hgt[Tt].mean(1)
    Chax = hax[Tt].mean(1)
    gun = (Cs > cfg['mant']) & (np.hypot(Ct, Ch - Chax) < cfg['gun_r'])
    tur = ~gun & (Ch > cfg['hcut']) & (Cs > smin - mg) & (Cs < sfront + mg) & (Ct > tmin - mg) & (Ct < tmax + mg)
    body = ~gun & ~tur
    # 车体上和车体不连着的小碎片（炮塔正面伸出去、低于分界高度的边、炮管底下的几片）：归炮塔，不然炮塔转正以后它们留在原地悬空
    bi = np.nonzero(body)[0]
    lab = _components(wid[Tt[bi]])
    _, inv_, cnt_ = np.unique(lab, return_inverse=True, return_counts=True)
    big_ = cnt_.max()
    cs_ = np.bincount(inv_, Cs[bi]) / cnt_
    ct_ = np.bincount(inv_, Ct[bi]) / cnt_
    ch_ = np.bincount(inv_, Ch[bi]) / cnt_
    frag = (cnt_ < big_ * 0.02) & (cs_ > smin - 0.002) & (cs_ < sfront + 0.004) & (ct_ > tmin - 0.002) & (ct_ < tmax + 0.002) & (ch_ > cfg['hcut'] - 0.004)
    mv = bi[frag[inv_]]
    tur[mv] = True
    body[mv] = False
    # 炮塔座圈：车体上炮塔原来的位置是空的（扫描只有外表面），补一块和甲板一样颜色的底板（凸包，扇形三角化）
    ring = np.unique(Tt[tur].reshape(-1))
    ring = ring[np.abs(hgt[ring] - cfg['hcut']) < 0.0015]
    pts = np.c_[s[ring], t[ring]]
    hull2 = _convex(pts)
    capP = []
    for k in hull2:
        su, tv = pts[k]
        uu = piv[0] + su * d[0] - tv * d[1]
        vv = piv[1] + su * d[1] + tv * d[0]
        capP.append((uu, vv))
    capP = np.array(capP)
    # 底板的颜色：炮塔周围甲板的中间色——挑贴图颜色最接近中间色的那一点，整块用它的贴图坐标（一个颜色）
    deck = np.unique(Tt[body].reshape(-1))
    deck = deck[(np.abs(hgt[deck] - (cfg['hcut'] - 0.0015)) < 0.0012) & (np.hypot(du[deck], dv[deck]) < 0.05)]
    near = deck[0] if len(deck) else V[0]
    if tex is not None and len(deck):
        W_, H_ = tex.size
        px = np.asarray(tex)
        xi = np.clip((UV[deck, 0] % 1) * W_, 0, W_ - 1).astype(int)
        yi = np.clip((UV[deck, 1] % 1) * H_, 0, H_ - 1).astype(int)
        col = px[yi, xi, :3].astype(np.float64)
        near = deck[np.argmin(np.linalg.norm(col - np.median(col, axis=0), axis=1))]
    # 放大倍数：车体长（量出来的那段）→ 真车
    k = cfg['L'] / (hull_u[1] - hull_u[0])
    um = (hull_u[0] + hull_u[1]) / 2

    def v3g(uu, vv, hh):   # 车体坐标 → V3G（x 前、y 左、z 上），原点在车体中心、桌面高度
        return np.stack([(uu - um) * front, (vv - vc) * front, hh], axis=-1) * k
    # 炮塔、炮转回正前方：绕转轴转 −yaw
    cy, sy = math.cos(-yaw), math.sin(-yaw)

    def unyaw(ids):
        uu, vv = fu[ids] - piv[0], fv[ids] - piv[1]
        return piv[0] + uu * cy - vv * sy, piv[1] + uu * sy + vv * cy
    # 三组顶点各自一份（炮塔、炮要转，车体不转）
    out_P, out_N, out_UV = [], [], []
    rot_n = np.array([[cy, -sy], [sy, cy]])

    def add(sel, turn):
        ids, inv = np.unique(Tt[sel].reshape(-1), return_inverse=True)
        uu, vv = (unyaw(ids) if turn else (fu[ids], fv[ids]))
        Pv = v3g(uu, vv, hgt[ids])
        nu, nvv, nh = N[ids] @ ax, N[ids] @ lf, N[ids] @ n
        if turn:
            nu, nvv = rot_n[0, 0] * nu + rot_n[0, 1] * nvv, rot_n[1, 0] * nu + rot_n[1, 1] * nvv
        Nv = np.stack([nu * front, nvv * front, nh], axis=-1)
        base = sum(len(x) for x in out_P)
        out_P.append(Pv)
        out_N.append(Nv)
        out_UV.append(UV[ids])
        return inv.reshape(-1, 3) + base
    gb = add(body, False)
    gt = add(tur, True)
    gg = add(gun, True)
    # 底板：凸包各点 + 中心，扇形
    base = sum(len(x) for x in out_P)
    cu, cv = capP.mean(0)
    hp = cfg['hcut'] - 0.0004
    cp = v3g(np.r_[capP[:, 0], cu], np.r_[capP[:, 1], cv], np.full(len(capP) + 1, hp))
    out_P.append(cp)
    out_N.append(np.tile([0.0, 0.0, 1.0], (len(cp), 1)))
    out_UV.append(np.tile(UV[near], (len(cp), 1)))
    m_ = len(capP)
    cap = np.array([[base + m_, base + (i + 1) % m_, base + i] for i in range(m_)])
    # 让底板朝上（逆时针从上往下看）
    e1 = cp[cap[0, 1] - base] - cp[cap[0, 0] - base]
    e2 = cp[cap[0, 2] - base] - cp[cap[0, 0] - base]
    if np.cross(e1, e2)[2] < 0:
        cap = cap[:, ::-1]
    Pv = np.concatenate(out_P)
    # 炮塔转轴（座圈高度）、炮耳轴（炮管根部后面一点，炮管轴线高度）
    tp = v3g(np.array([piv[0]]), np.array([piv[1]]), np.array([cfg['hcut']]))[0]
    gs = cfg['mant'] - cfg['trun']   # 炮耳轴离转轴多远（沿炮管）；转正以后炮管沿 u 轴朝 front 那头
    gp = v3g(np.array([piv[0] + gs * front]), np.array([piv[1]]), np.array([h0 + kh * (piv[0] + gs * d[0])]))[0]
    rep = {'k': k, 'yaw': math.degrees(yaw), 'front': front, 'tris': (int(body.sum()), int(tur.sum()), int(gun.sum()), len(cap)),
           'hull': [(hull_u[1] - hull_u[0]) * k, (hull_v[1] - hull_v[0]) * k], 'top': float(hgt[V].max() * k)}
    return Pv, np.concatenate(out_N), np.concatenate(out_UV), {'body': np.concatenate([gb, cap]), 'tur': gt, 'gun': gg}, tp, gp, rep


def _convex(pts):
    """二维凸包（单调链），返回下标，逆时针"""
    o = np.lexsort((pts[:, 1], pts[:, 0]))

    def cross(a, b, c):
        return (pts[b, 0] - pts[a, 0]) * (pts[c, 1] - pts[a, 1]) - (pts[b, 1] - pts[a, 1]) * (pts[c, 0] - pts[a, 0])
    lower, upper = [], []
    for i in o:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], i) <= 0:
            lower.pop()
        lower.append(i)
    for i in o[::-1]:
        while len(upper) >= 2 and cross(upper[-2], upper[-1], i) <= 0:
            upper.pop()
        upper.append(i)
    return lower[:-1] + upper[:-1]


def credit(key):
    """CC-BY 署名：作品名、出处、作者、授权、这里的改动"""
    c = SF[key]
    return 'This work is based on "%s" (%s) by %s (%s) licensed under %s（改动：%s）' % (c['title'], c['url'], c['author'], c['user'], c['license'], c['mods'])


def load(key, zpath):
    """→ (meta, binb, credit, rep)：meta / binb 和网页版 js/mdl/<键>.js 解出来的一样（mdl2glb.convert 直接用）"""
    cfg = SF[key]
    J, bufs, rd = _gltf_from_zip(zpath)
    P, N, UV, T, MI = _meshes(J, bufs)
    if 'scan' not in cfg:
        raise ValueError(key + '：没有加工方法')
    mats = J.get('materials', [])
    if len(set(MI.tolist())) != 1:
        raise ValueError(key + '：扫描模型应该只有一种材质')
    # 贴图（扫描只有一张底色贴图）
    m0 = mats[int(MI[0])] if mats else {}
    ti = (m0.get('pbrMetallicRoughness') or {}).get('baseColorTexture', {}).get('index')
    data, tex = None, None
    if ti is not None:
        img = J['images'][J['textures'][ti]['source']]
        data = rd(img['uri'])
        tex = Image.open(io.BytesIO(data)).convert('RGB')
    Pv, Nv, UVv, G, tp, gp, rep = _scan(cfg['scan'], P, N, UV, T, tex)
    # 贴图分块：扫描的图集里车只占一小块（桌面占了不少），整张缩到 Roblox 的 1024 太糊——按贴图坐标分成 n × n 块，
    #   每块裁出它的三角形用到的那一片、各自一张图（最大 1024），三角形按所在的块分材质
    nt = cfg['scan'].get('tiles', 1) if tex is not None else 1
    order = [('body', -1), ('tur', 0), ('gun', 1)]
    allT = np.concatenate([G[g] for g, _ in order])
    tq = np.zeros(len(allT), dtype=int)
    if nt > 1:
        c = UVv[allT].mean(1)
        tq = np.clip((c[:, 0] * nt).astype(int), 0, nt - 1) + nt * np.clip((c[:, 1] * nt).astype(int), 0, nt - 1)
    blob = bytearray()
    imgs, mats, crops = [], [], {}
    for q in sorted(set(tq.tolist())):
        if tex is None:
            break
        uv = UVv[np.unique(allT[tq == q].reshape(-1))]
        W_, H_ = tex.size
        x0, y0 = max(0, int(math.floor(uv[:, 0].min() * W_)) - 2), max(0, int(math.floor(uv[:, 1].min() * H_)) - 2)
        x1, y1 = min(W_, int(math.ceil(uv[:, 0].max() * W_)) + 2), min(H_, int(math.ceil(uv[:, 1].max() * H_)) + 2)
        im = tex.crop((x0, y0, x1, y1))
        if max(im.size) > 1024:
            k_ = 1024 / max(im.size)
            im = im.resize((max(1, round(im.size[0] * k_)), max(1, round(im.size[1] * k_))), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=90)
        while len(blob) % 4:
            blob.append(0)
        imgs.append({'o': len(blob), 'n': buf.tell(), 'm': 'image/jpeg'})
        blob.extend(buf.getvalue())
        crops[q] = (len(mats), x0 / W_, y0 / H_, (x1 - x0) / W_, (y1 - y0) / H_, im.size[0] * im.size[1])
        mats.append({'n': 'scan%d' % q, 'c': [1, 1, 1, 1], 'mr': [0, 0.85], 'ds': 1, 't': [len(imgs) - 1, 1, 1]})
    if not mats:
        mats.append({'n': 'scan', 'c': [1, 1, 1, 1], 'mr': [0, 0.85], 'ds': 1})
        crops = {0: (0, 0.0, 0.0, 1.0, 1.0, 0)}
    # 每（部件，块）一段：顶点各复制一份，贴图坐标换到裁出来的那张图上
    VBs, IBs, segs, nv, s0 = [], [], [], 0, 0
    gi = np.concatenate([np.full(len(G[g]), pi) for g, pi in order])
    for g, pi in order:
        for q in sorted(crops):
            sel = (gi == pi) & (tq == q)
            if not sel.any():
                continue
            ids, inv = np.unique(allT[sel].reshape(-1), return_inverse=True)
            mi, u0, v0, du, dv, _ = crops[q]
            uv = (UVv[ids] - [u0, v0]) / [du, dv]
            VBs.append(np.concatenate([Pv[ids], Nv[ids], uv], axis=1))
            IBs.append(inv + nv)
            segs.append([mi, pi, s0, inv.size])
            nv += len(ids)
            s0 += inv.size
    while len(blob) % 4:
        blob.append(0)
    VB = np.concatenate(VBs).astype('<f4')
    vb0 = len(blob)
    blob.extend(VB.tobytes())
    IB = np.concatenate(IBs).astype('<u4')
    ib0 = len(blob)
    blob.extend(IB.tobytes())
    if tex is not None:
        area = np.linalg.norm(np.cross(Pv[allT[:, 1]] - Pv[allT[:, 0]], Pv[allT[:, 2]] - Pv[allT[:, 0]]), axis=1).sum() / 2
        px = 0.0   # 车身表面在缩好的图上占多少像素 → 每米多少像素
        for q, (mi, u0, v0, du, dv, npx) in crops.items():
            u = UVv[allT[tq == q]]
            auv = np.abs((u[:, 1, 0] - u[:, 0, 0]) * (u[:, 2, 1] - u[:, 0, 1]) - (u[:, 2, 0] - u[:, 0, 0]) * (u[:, 1, 1] - u[:, 0, 1])).sum() / 2
            px += auv / (du * dv) * npx
        rep['px_per_m'] = round(math.sqrt(px / area), 1)
        rep['tiles'] = len(crops)
    meta = {'st': 8, 'vb': [vb0, VB.nbytes], 'ib': [ib0, IB.nbytes], 'it': 4, 'lod': [segs], 'mats': mats, 'imgs': imgs,
            'parts': [{'n': 'tur', 'k': 'yaw', 'p': [float(x) for x in tp]}, {'n': 'gun', 'q': [float(x) for x in gp]}]}
    return meta, bytes(blob), credit(key), rep
