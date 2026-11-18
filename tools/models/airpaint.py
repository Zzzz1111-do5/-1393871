# 飞机重新涂装（直接改成品 GLB + 元数据 ImportedAir.lua 里这个模型的那一行）
#   用户 11-18：歼-20 改得跟现实的一样，包括绿色光条——andertan 的歼-20 原模型没有贴图，转出来一整架浅灰，绿色编队灯带也是浅灰的；
#   照网页版《暗剑》v3g.js 的 V3G_PAINT.j20 / V3G_RECOL.j20：机身深灰微带青（吸波涂层，带一点金属光泽）、雷达罩更深、
#   喷管是不涂漆的耐热合金（调节片外面烧成橄榄青铜色、里面钢灰）、座舱盖镀金膜的茶金色、绿色电致发光编队灯带（机头两侧座舱下方、两片垂尾）自己发光
# 做法：要涂的材质共用一张调色板贴图（底色一张、金属度 / 粗糙度一张：Roblox 导入只认贴图，不认材质系数），
#   每个三角形的贴图坐标指到调色板里那一格——按位置分区（雷达罩、喷口外 / 里）不用另拆零件；格之间的顶点各复制一份
#   灯带：游戏里（AirModels.lua）按元数据 glow 做成 Neon 发光；玻璃：元数据 col / a（玻璃是半透明材质，游戏里按元数据上色）
#   geo：模型上的小修——原模型右边的灯带比左边长一截（右边那段后半截在 Material.009 里），照着镜像补到左边；左翼上落单的一个灯带三角形去掉
# 用法：python3 -I tools/models/airpaint.py <模型键，如 j20> [GLB，默认 models/air/<键>.glb] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
#   要在 glbvote.py（面朝向）之后跑；同一个文件只跑一次（再跑会把已经涂好的再涂一遍，结果一样，但几何小修会重复）
import io, json, os, re, struct, sys, zlib
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import mdl2glb as B   # noqa: E402

# 颜色是 sRGB（0–255），m 金属度、r 粗糙度
PAINT = {
    'j20': {
        'key': 'j20_v3',
        'pal': {'body': ((92, 97, 100), 0.4, 0.48), 'radome': ((62, 66, 68), 0.1, 0.6), 'nozzle': ((112, 103, 72), 0.82, 0.42),
                'nozzle_in': ((150, 148, 142), 0.9, 0.35), 'dark': ((30, 31, 33), 0.2, 0.7), 'lens': ((196, 202, 208), 0.1, 0.2),
                'glow': ((96, 255, 150), 0.0, 0.5)},
        # 材质 → 调色板（没列的、带贴图的都按 body）
        'mats': {'Material.026': 'dark', 'Material.002': 'dark', 'Material.005': 'lens', 'Material.099': 'lens',
                 'Material.014': 'glow', 'Material.020': 'glow', 'Material.022': 'glow', 'Material.024': 'glow', 'Material.009': 'glow'},
        # 按位置换颜色（模型坐标，格：X 右、Y 上、−Z 朝前）：雷达罩 = Material.001 里机头最前面 2.6 米（网页版 V3G_RECOL 的框）；
        #   喷口 = 两个尾喷口轴线（元数据 noz）周围、出口往前 2.5 格以内的三角形，法线朝外的是外面、朝轴线的是里面
        'regions': [{'as': 'radome', 'mats': ['Material.001'], 'zlt': -21.3, 'xabs': 3.4},
                    {'as': 'nozzle', 'noz': True, 'len': 2.5, 'r': 2.0, 'inner': 'nozzle_in'}],
        'glow': ['Material.014', 'Material.020', 'Material.022', 'Material.024', 'Material.009'],
        # 玻璃（半透明材质）：座舱盖、风挡、光电瞄准窗——镀金膜的茶金色
        'glass': {'Basic_Glass.001': ((178, 142, 72), 0.5), 'Facade_Glass': ((178, 142, 72), 0.55)},
        'geo': [{'op': 'drop', 'mat': 'Material.009', 'xlt': -10},
                {'op': 'mirror', 'from': 'Material.009', 'to': 'Material.020', 'xgt': 1.5}],
    },
    # 歼-16（用户 11-18：我记得歼-20 和歼-16 有绿色灯条）：贴图是真机照片投影（照原样，不重涂），模型里没有灯带——
    #   照解放军侧卫系列的编队灯：机头两侧座舱下方各一条（顺着机身）、两片垂尾外侧各一条（顺着前缘）；
    #   在模型表面上打射线量出位置，记进元数据 strips，游戏里贴一条薄薄的 Neon（只改元数据，不动 GLB）
    #   side：飞行员头（元数据 pit）往下 down 格、前后 z 范围；fin：垂尾外侧，高 y 范围内、弦长 chord 处（0 前缘、1 后缘）
    'j16': {
        'key': 'j16_v3', 'only': 'strips', 'glowcol': (96, 255, 150),
        'strips': [{'kind': 'side', 'z': [-20.6, -17.4], 'down': 2.3, 'w': 0.26},
                   {'kind': 'fin', 'y': [12.3, 16.2], 'chord': 0.3, 'w': 0.26}],
    },
    # 发动机堵头（用户 11-18：H-6 的发动机和 A-10 的从后往前看里面是镂空的）：喷口往里一点垫一块深色圆盘（涡轮 / 风扇那一面），
    #   从后面怎么看都透不过去——A-10 的模型没做风扇，外涵道那一圈从后面直接看到前面的天；离远了 Roblox 自动减面，喷管里的尾锥、支板也会没了
    'h6k': {'key': 'h6k_v3', 'only': 'plugs'},
    'a10': {'key': 'a10_v3', 'only': 'plugs'},
}
PW = 8   # 调色板每格 8 像素宽


def plugs(J, BIN, info, log=print):
    """每个尾喷口（元数据 noz：出口中心、内半径，朝 +Z）往里找一处四周都被管壁围住的截面，量出管壁有多粗：
    一层管子（单涵道）圆盘就是管子那么粗；中间有核心机的（双涵道：从轴线往外先打到核心机）圆盘盖到外涵道的外壁"""
    T = tris_world(J, BIN)
    out = []
    for nz in info.get('noz') or []:
        x, y, z, r = nz
        done = False
        for m in (0.8, 1.2, 1.6, 2.0, 2.6, 3.2, 4.0, 5.0):
            zs = z - m * r
            o = np.array([x, y, zs])
            r1, r2, ok = [], [], True
            for k in range(16):
                a = 2 * np.pi * k / 16
                d = np.array([np.cos(a), np.sin(a), 0.0])
                h = ray(T, o, d)
                if not h or h[0] > 4 * r:
                    ok = False
                    break
                r1.append(h[0])
            if not ok:
                continue
            if min(r1) >= 0.8 * r:   # 一层管子
                rad = min(r1) * 0.97
            else:   # 中间是核心机（双涵道）：从外面往里打，打到整流罩外皮；要四周都是罩子（比核心机粗得多）的那一截，
                #   圆盘比外皮小一点（盘边藏在罩子壁里），把外涵道和核心机一起盖住
                for k in range(16):
                    a = 2 * np.pi * k / 16
                    d = np.array([np.cos(a), np.sin(a), 0.0])
                    h = ray(T, o + d * 4 * r, -d)
                    if not h:
                        ok = False
                        break
                    r2.append(4 * r - h[0])
                if not ok or min(r2) < 1.5 * r:
                    continue
                rad = min(r2) - 0.15
            out.append({'c': [round(float(x), 3), round(float(y), 3), round(float(zs), 3)], 'a': [0, 0, 1], 'r': round(float(rad), 3)})
            log('  堵头：喷口 (%.2f, %.2f, %.2f) 往里 %.1f 格，半径 %.2f 格（%s）' % (x, y, z, m * r, rad, '一层管子' if not r2 else '双涵道'))
            done = True
            break
        if not done:
            log('  堵头：喷口 (%.2f, %.2f, %.2f) 没找到四周围住的截面' % (x, y, z))
    return out


def tris_world(J, BIN):
    """整个模型的三角形（世界坐标）：三个角 A、B、C"""
    W = glbfix.world_mats(J)
    As, Bs, Cs = [], [], []
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W:
            continue
        M = W[ni]
        for pr in J['meshes'][nd['mesh']]['primitives']:
            if pr.get('mode', 4) != 4 or 'indices' not in pr:
                continue
            P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
            I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            As.append(P[I[:, 0]]); Bs.append(P[I[:, 1]]); Cs.append(P[I[:, 2]])
    return np.concatenate(As), np.concatenate(Bs), np.concatenate(Cs)


def ray(T, o, d):
    """射线 o + t·d 最近打到的三角形：(t, 点, 面法线朝着射线来的方向)；打不到返回 None"""
    A, Bv, C = T
    e1, e2 = Bv - A, C - A
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = o - A
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q * d).sum(1) * inv
    t = (q * e2).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
    if not hit.any():
        return None
    k = np.nonzero(hit)[0][np.argmin(t[hit])]
    n = np.cross(e1[k], e2[k])
    n /= np.linalg.norm(n)
    if n @ d > 0:
        n = -n
    return t[k], o + d * t[k], n


def strips(spec, J, BIN, info, log=print):
    """在模型表面上量出灯带（右边量、左边镜像）：[{ c 中心, n 朝外的法线, d 顺着灯带的方向, l 长, w 宽, col 颜色 }]"""
    T = tris_world(J, BIN)
    left = np.array([-1.0, 0, 0])
    out = []
    for S in spec.get('strips', []):
        pts = []
        if S['kind'] == 'side':   # 从右边水平打进去，量机身侧面
            pit = info['pit'][0]
            y = pit[1] - S['down']
            for z in S['z']:
                h = ray(T, np.array([30.0, y, z]), left)
                if h:
                    pts.append(h)
        elif S['kind'] == 'fin':   # 右垂尾：每个高度从右边打一排射线量出前缘、后缘，在弦长 chord 处取点
            tip = info['tails']['p']
            for y in S['y']:
                zs = []
                for z in np.arange(tip[2] - 18, tip[2] + 12, 0.05):
                    h = ray(T, np.array([30.0, y, z]), left)
                    if h and abs(h[1][0] - tip[0]) < 2.5:
                        zs.append(z)
                if not zs:
                    continue
                zc = min(zs) + S['chord'] * (max(zs) - min(zs))
                h = ray(T, np.array([30.0, y, zc]), left)
                if h:
                    pts.append(h)
        if len(pts) != 2:
            log('  灯带 %s 没量出来（打中 %d 点）' % (S['kind'], len(pts)))
            continue
        a, b = pts[0][1], pts[1][1]
        n = pts[0][2] + pts[1][2]
        n /= np.linalg.norm(n)
        d = (b - a) / np.linalg.norm(b - a)
        for sx in (1, -1):
            m = np.array([sx, 1.0, 1.0])
            out.append({'c': [round(float(x), 3) for x in (a + b) / 2 * m], 'n': [round(float(x), 3) for x in n * m],
                        'd': [round(float(x), 3) for x in d * m], 'l': round(float(np.linalg.norm(b - a)), 3), 'w': S['w'],
                        'col': list(spec['glowcol'])})
        log('  灯带 %s：中心 %s，长 %.2f 格，法线 %s' % (S['kind'], out[-2]['c'], out[-2]['l'], out[-2]['n']))
    return out


# —— 元数据那一行（mdl2glb.lua 写的 Lua 表）读回 Python ——
def lua_parse(s):
    i = 0
    n = len(s)

    def ws():
        nonlocal i
        while i < n and s[i] in ' \t\r\n':
            i += 1

    def val():
        nonlocal i
        ws()
        c = s[i]
        if c == '{':
            i += 1
            d, arr, keyed = {}, [], False
            while True:
                ws()
                if s[i] == '}':
                    i += 1
                    break
                m = re.match(r'([A-Za-z_][\w]*)\s*=', s[i:])
                if m:
                    k = m.group(1)
                    i += m.end()
                    d[k] = val()
                    keyed = True
                elif s[i] == '[':
                    j = s.index(']', i)
                    kk = s[i + 1:j]
                    i = s.index('=', j) + 1
                    d[json.loads(kk) if kk.startswith('"') else int(kk)] = val()
                    keyed = True
                else:
                    arr.append(val())
                ws()
                if s[i] == ',':
                    i += 1
            return d if keyed else arr
        if c == '"':
            j = i + 1
            while s[j] != '"':
                j += 2 if s[j] == '\\' else 1
            v = json.loads(s[i:j + 1])
            i = j + 1
            return v
        m = re.match(r'-?\d+(\.\d+)?([eE][-+]?\d+)?', s[i:])
        if m:
            i += m.end()
            t = m.group(0)
            return float(t) if ('.' in t or 'e' in t or 'E' in t) else int(t)
        if s.startswith('true', i):
            i += 4
            return True
        if s.startswith('false', i):
            i += 5
            return False
        raise ValueError('读不了：' + s[i:i + 40])
    return val()


def png(rows):
    """rows：每行一串 (r, g, b, a)；写成 PNG 字节"""
    h, w = len(rows), len(rows[0])
    raw = b''.join(b'\x00' + b''.join(bytes(px) for px in row) for row in rows)

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')


def paint(name, glb, meta_path, log=print):
    spec = PAINT[name]
    key = spec['key']
    J, BIN = glbfix.read(glb)
    BIN = bytearray(BIN)
    # 元数据
    lines = open(meta_path, encoding='utf-8').read().split('\n')
    li = next(k for k, l in enumerate(lines) if l.startswith('    %s = {' % key))
    info = lua_parse(lines[li].strip()[len(key) + 3:].rstrip(','))
    if spec.get('only') in ('strips', 'plugs'):   # 只量灯带 / 堵头、写元数据，不动 GLB
        if spec['only'] == 'strips':
            info['strips'] = strips(spec, J, BIN, info, log)
        else:
            info['plugs'] = plugs(J, BIN, info, log)
        lines[li] = '    %s = %s,' % (key, B.lua(info))
        open(meta_path, 'w', encoding='utf-8').write('\n'.join(lines))
        log('  %s：%s %d 个写进元数据' % (key, spec['only'], len(info[spec['only']])))
        return
    pal = list(spec['pal'])
    pidx = {k: i for i, k in enumerate(pal)}
    mname = lambda mi: J['materials'][mi]['name'].replace('A_%s_' % key, '', 1) if mi is not None and mi >= 0 else ''
    # 图元表：(节点, 图元, 材质名)
    prims = []
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd:
            continue
        for pr in J['meshes'][nd['mesh']]['primitives']:
            prims.append((ni, pr, mname(pr.get('material', -1))))
    T0 = lambda ni: np.array(J['nodes'][ni].get('translation', [0, 0, 0]), dtype=np.float64)
    data = {}   # 访问器 → 新数组（最后一起 rebuild）

    def get(pr, k):
        ai = pr['attributes'][k] if k != 'indices' else pr['indices']
        return data[ai] if ai in data else glbfix.acc_read(J, BIN, ai)

    def put(pr, k, arr):
        data[pr['attributes'][k] if k != 'indices' else pr['indices']] = arr
    moved = set()   # 几何改过、要重新算中心的图元（节点）
    # —— 几何小修 ——
    for g in spec.get('geo', []):
        if g['op'] == 'drop':
            for ni, pr, mn in prims:
                if mn != g['mat']:
                    continue
                P = get(pr, 'POSITION').astype(np.float64) + T0(ni)
                I = get(pr, 'indices').astype(np.int64).reshape(-1, 3)
                cx = P[I].mean(1)[:, 0]
                keep = ~(cx < g['xlt'])
                if (~keep).any():
                    put(pr, 'indices', I[keep].reshape(-1).astype(np.uint32))
                    moved.add(ni)
                    log('  去掉 %s 的 %d 个三角形' % (mn, int((~keep).sum())))
        elif g['op'] == 'mirror':
            src = [(ni, pr) for ni, pr, mn in prims if mn == g['from']]
            dst = [(ni, pr) for ni, pr, mn in prims if mn == g['to']]
            if not src or not dst:
                continue
            dn, dp = dst[0]
            DP = get(dp, 'POSITION').astype(np.float64)
            DN = get(dp, 'NORMAL').astype(np.float64)
            DU = get(dp, 'TEXCOORD_0').astype(np.float64)
            DI = get(dp, 'indices').astype(np.int64).reshape(-1, 3)
            add = 0
            for sn, sp in src:
                P = get(sp, 'POSITION').astype(np.float64) + T0(sn)
                N = get(sp, 'NORMAL').astype(np.float64)
                U = get(sp, 'TEXCOORD_0').astype(np.float64)
                I = get(sp, 'indices').astype(np.int64).reshape(-1, 3)
                sel = P[I].mean(1)[:, 0] > g['xgt']
                if not sel.any():
                    continue
                vs = np.unique(I[sel].reshape(-1))
                remap = np.full(len(P), -1, dtype=np.int64)
                remap[vs] = len(DP) + np.arange(len(vs))
                MP = P[vs] * np.array([-1, 1, 1]) - T0(dn)
                MN = N[vs] * np.array([-1, 1, 1])
                DP = np.concatenate([DP, MP])
                DN = np.concatenate([DN, MN])
                DU = np.concatenate([DU, U[vs]])
                DI = np.concatenate([DI, remap[I[sel]][:, [0, 2, 1]]])   # 镜像以后绕向反过来
                add += int(sel.sum())
            put(dp, 'POSITION', DP.astype(np.float32))
            put(dp, 'NORMAL', DN.astype(np.float32))
            put(dp, 'TEXCOORD_0', DU.astype(np.float32))
            put(dp, 'indices', DI.reshape(-1).astype(np.uint32))
            moved.add(dn)
            log('  %s 镜像 %d 个三角形补到 %s' % (g['from'], add, g['to']))
    # —— 调色板贴图 ——
    base = [(c[0], c[1], c[2], 255) for c, m, r in (spec['pal'][k] for k in pal)]
    mr = [(255, int(round(r * 255)), int(round(m * 255)), 255) for c, m, r in (spec['pal'][k] for k in pal)]   # glTF：G 粗糙度、B 金属度
    rowsB = [[px for px in base for _ in range(PW)] for _ in range(PW)]
    rowsM = [[px for px in mr for _ in range(PW)] for _ in range(PW)]

    def add_image(b, nm):
        while len(BIN) % 4:
            BIN.append(0)
        J['bufferViews'].append({'buffer': 0, 'byteOffset': len(BIN), 'byteLength': len(b)})
        BIN.extend(b)
        J.setdefault('images', []).append({'bufferView': len(J['bufferViews']) - 1, 'mimeType': 'image/png', 'name': nm})
        J.setdefault('samplers', []).append({'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071})   # 最近点、夹边：格子之间不混色
        J.setdefault('textures', []).append({'source': len(J['images']) - 1, 'sampler': len(J['samplers']) - 1})
        return len(J['textures']) - 1
    tB = add_image(png(rowsB), 'A_%s_paint' % key)
    tM = add_image(png(rowsM), 'A_%s_paint_mr' % key)
    # —— 每个三角形涂哪一格 ——
    noz = info.get('noz') or []
    painted = set()
    nreg = {}
    for ni, pr, mn in prims:
        mi = pr.get('material', -1)
        M = J['materials'][mi] if mi >= 0 else {}
        if M.get('alphaMode') == 'BLEND':
            continue   # 玻璃：按元数据上色
        dflt = spec['mats'].get(mn, 'body')
        P = get(pr, 'POSITION').astype(np.float64)
        N = get(pr, 'NORMAL').astype(np.float64)
        I = get(pr, 'indices').astype(np.int64).reshape(-1, 3)
        if not len(I):
            continue
        Pw = P + T0(ni)
        cen = Pw[I].mean(1)
        fn = np.cross(Pw[I[:, 1]] - Pw[I[:, 0]], Pw[I[:, 2]] - Pw[I[:, 0]])
        pi = np.full(len(I), pidx[dflt], dtype=np.int64)
        if dflt == 'body':
            for R in spec.get('regions', []):
                if 'mats' in R and mn not in R['mats']:
                    continue
                if 'zlt' in R:
                    sel = (cen[:, 2] < R['zlt']) & (np.abs(cen[:, 0]) < R.get('xabs', 1e9))
                    pi[sel] = pidx[R['as']]
                    nreg[R['as']] = nreg.get(R['as'], 0) + int(sel.sum())
                if R.get('noz'):
                    for nz in noz:
                        ax = np.array([nz[0], nz[1]])
                        d = cen[:, 0:2] - ax
                        rr = np.linalg.norm(d, axis=1)
                        sel = (rr < R['r']) & (cen[:, 2] > nz[2] - R['len']) & (cen[:, 2] < nz[2] + 0.6)
                        out = (np.einsum('ij,ij->i', fn[:, 0:2], d) > 0)
                        pi[sel & out] = pidx[R['as']]
                        pi[sel & ~out] = pidx[R['inner']]
                        nreg[R['as']] = nreg.get(R['as'], 0) + int((sel & out).sum())
                        nreg[R['inner']] = nreg.get(R['inner'], 0) + int((sel & ~out).sum())
        # 顶点按（原顶点, 格）拆开
        kk = I * len(pal) + pi[:, None]
        u, inv = np.unique(kk.reshape(-1), return_inverse=True)
        ov, og = u // len(pal), u % len(pal)
        uv = np.stack([(og + 0.5) / len(pal), np.full(len(og), 0.5)], axis=1).astype(np.float32)
        for k in list(pr['attributes']):
            if k == 'TEXCOORD_0':
                continue
            arr = get(pr, k)
            put(pr, k, arr[ov])
        if 'TEXCOORD_0' not in pr['attributes']:
            continue
        put(pr, 'TEXCOORD_0', uv)
        put(pr, 'indices', inv.reshape(-1).astype(np.uint32))
        painted.add(mi)
    for mi in painted:
        M = J['materials'][mi]
        pb = M.setdefault('pbrMetallicRoughness', {})
        pb['baseColorTexture'] = {'index': tB}
        pb['metallicRoughnessTexture'] = {'index': tM}
        pb['baseColorFactor'] = [1, 1, 1, 1]
        pb['metallicFactor'], pb['roughnessFactor'] = 1, 1
    # —— 改过几何的块：重新算中心、大小（元数据跟着改） ——
    for ni in moved:
        nd = J['nodes'][ni]
        pr = J['meshes'][nd['mesh']]['primitives'][0]
        P = get(pr, 'POSITION').astype(np.float64) + T0(ni)
        I = get(pr, 'indices').astype(np.int64)
        U = P[np.unique(I)]
        lo, hi = U.min(0), U.max(0)
        c = (lo + hi) / 2
        put(pr, 'POSITION', (P - c).astype(np.float32))
        nd['translation'] = [float(x) for x in c]
        part = nd['name'].split('__', 1)[1]
        info['parts'][part]['c'] = [round(float(x), 3) for x in c]
        info['parts'][part]['s'] = [round(float(x), 3) for x in np.maximum(hi - lo, 0.02)]
    BIN = glbfix.rebuild(J, BIN, data)
    glbfix.write(glb, J, BIN)
    # —— 元数据：灯带、玻璃 ——
    glow = {}
    gc = list(spec['pal']['glow'][0])
    glass = spec.get('glass', {})
    for ni, pr, mn in prims:
        part = J['nodes'][ni]['name'].split('__', 1)[1]
        if mn in spec.get('glow', []):
            glow[part] = gc
        if mn in glass and part in info['parts']:
            info['parts'][part]['col'] = list(glass[mn][0])
            info['parts'][part]['a'] = glass[mn][1]
    if glow:
        info['glow'] = glow
    info['paint'] = name   # 重新涂过（看元数据就知道导入的是不是新的那一版）
    lines[li] = '    %s = %s,' % (key, B.lua(info))
    open(meta_path, 'w', encoding='utf-8').write('\n'.join(lines))
    log('  涂了 %d 种材质（调色板 %d 格）；按位置分区 %s；灯带 %d 块：%s' % (len(painted), len(pal), nreg, len(glow), ','.join(sorted(glow))))


if __name__ == '__main__':
    nm = sys.argv[1]
    paint(nm, sys.argv[2] if len(sys.argv) > 2 else 'models/air/%s.glb' % nm,
          sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/ImportedAir.lua')
