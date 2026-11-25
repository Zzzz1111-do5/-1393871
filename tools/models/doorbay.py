# 舱门开了以后别能看穿飞机（用户 11-18：「侧弹仓打开为什么能看穿飞机」）——成品 GLB + 元数据 ImportedAir.lua 那一行的最后一道加工：
#   原模型是一层蒙皮，里面是空的；Roblox 只画正面，从开口看进去，机身另一边的蒙皮是背面、不画，就直接看到天了。
#   · 舱（cavity）：从舱门切口的轮廓往机身里挤出舱壁、再在深处盖一块舱底（舱门曲面平移进去），正面都朝舱里——开口一圈严丝合缝，
#     看进去是有深度的深灰色舱，不是贴一块黑板。原来 WELL 表的方盒子是水平的，歼-20 侧弹舱、主起落架舱在 60° 的斜面上，盒子和蒙皮之间漏一大条缝。
#   · 舱门背面：舱门只是切下来的一块蒙皮，开了以后里面那面是背面、不画，也能看穿；给舱门补一份反面（顶点复制、法线取反、绕向反过来）。
#   · 进气道（用户 11-18：从前下方能从进气道口看穿）：原模型进气道唇口后面直接通到空的机身里，没有管道、没有发动机端面。
#     在唇口还围得住的那一截（Z 固定的截面上从管道中心往四周打射线，量出开口轮廓）往后挤一段深色管道、末端封口，看进去是黑洞洞的进气道。
#   要在 glbvote.py、airpaint.py 之后跑（反面补早了，前两道会把它当成朝反的面翻回去）。舱 / 舱门反面和进气道各自只做一次
#   （元数据有 bayfix 就不再做舱，已经有 Duct_1 就不再做进气道），所以对已经加工过的文件再跑一遍只补没做的那部分。
# 用法：python3 -I tools/models/doorbay.py <模型键，如 j20> [GLB，默认 models/air/<键>.glb] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import mdl2glb as B   # noqa: E402
import airpaint   # noqa: E402  元数据那一行读回 Python（lua_parse）

S = 2.8   # 米 → 格
SPEC = {
    'j20': {
        'key': 'j20_v4',
        # 开口（几扇门合成一个开口的写在一起）→ 舱深（米，顺着舱门面的法线往里）
        'cavity': [(('BaySL',), 0.30), (('BaySR',), 0.30), (('GDoorML',), 0.45), (('GDoorMR',), 0.45), (('GDoorN1', 'GDoorN2'), 0.75)],
        'col': (52, 55, 58),   # 舱里：深灰（sRGB）
        'back': ['BayM1', 'BayM2', 'BaySL', 'BaySR', 'GDoorN1', 'GDoorN2', 'GDoorML', 'GDoorMR'],
        # 进气道（模型坐标，格）：左边那个的管道中心（X, Y）、从 Z = z0（唇口里面、轮廓还是闭合的）挤到 z1；右边照 X 镜像再量一遍
        #   z1 停在侧弹舱的舱（Z −5.3 起）前面
        #   lip：唇口那一截的范围（左边的；Z 从唇口前面到 z0），里面从中心线看是背面的面补反面
        'intakes': [{'c': [-3.45, 5.40], 'z0': -9.5, 'z1': -5.6, 'lip': {'x': [-5.3, -1.4], 'y': [3.5, 7.3], 'z': [-12.6, -9.0]}}],
        'duct_col': (30, 32, 34),
    },
}
TRI_MAX = 20000


def put(J, BIN, arr, typ, comp, minmax=False):
    while len(BIN) % 4:
        BIN.append(0)
    J['bufferViews'].append({'buffer': 0, 'byteOffset': len(BIN), 'byteLength': arr.nbytes})
    BIN.extend(arr.tobytes())
    a = {'bufferView': len(J['bufferViews']) - 1, 'componentType': comp,
         'count': int(arr.shape[0]) if typ != 'SCALAR' else int(arr.size), 'type': typ}
    if minmax:
        a['min'] = arr.min(0).tolist()
        a['max'] = arr.max(0).tolist()
    J['accessors'].append(a)
    return len(J['accessors']) - 1


def cavity(T, depth, log, name):
    """T：开口那几扇门的三角形（m×3×3，模型坐标，门关着）。返回舱的三角形（正面朝舱里 / 朝开口）"""
    P = T.reshape(-1, 3)
    c = P.mean(0)
    n = np.linalg.svd(P - c)[2][2]
    if n @ (np.array([0.0, 7.0, c[2]]) - c) < 0:   # 法线朝机身里（往机身中轴线、往上）
        n = -n
    o = n * depth * S
    # 焊顶点（切口两边的门共用切线上的顶点）；同一组顶点的三角形只留一个（glbvote 给单层板补的反面和正面共用三个顶点，
    #   不去掉的话轮廓上的边会被数成两次、那一段就不挤舱壁，留一条缝）；退化的去掉
    key = np.round(P / 1e-3).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)
    F = vid.reshape(-1, 3)
    ok = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    _, first = np.unique(np.sort(F, axis=1), axis=0, return_index=True)
    keep = np.zeros(len(F), bool)
    keep[first] = True
    keep &= ok
    F, T = F[keep], T[keep]
    # 只被一个三角形用的边 = 开口轮廓
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    lo, hi = e.min(1), e.max(1)
    k = lo * (vid.max() + 1) + hi
    u, inv, cnt = np.unique(k, return_inverse=True, return_counts=True)
    edge = cnt[inv] == 1
    pos = np.zeros((vid.max() + 1, 3))
    pos[vid] = P
    ar = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1)
    cen = (T.mean(1) * ar[:, None]).sum(0) / ar.sum()   # 开口的中心（按面积）
    walls = []
    for a, b in e[edge]:
        A, Bv = pos[a], pos[b]
        quad = [(A, Bv, Bv + o), (A, Bv + o, A + o)]
        nw = np.cross(Bv - A, o)
        d = cen - (A + Bv) / 2
        d -= n * (d @ n)
        if nw @ d < 0:   # 正面朝开口中间（舱门都是近似长方形的开口；切线上的细长三角形按它自己的重心判断会判反）
            quad = [(A, Bv + o, Bv), (A, A + o, Bv + o)]
        walls += quad
    # 舱底：门的曲面平移进去，每个三角形都让正面朝开口（−n）
    floor = T + o
    fn = np.cross(floor[:, 1] - floor[:, 0], floor[:, 2] - floor[:, 0])
    flip = fn @ n > 0
    floor[flip] = floor[flip][:, [0, 2, 1]]
    log('  舱 %s：开口轮廓 %d 条边，深 %.2f 米，法线 (%.2f, %.2f, %.2f)；舱底 %d 个三角形（翻正 %d 个）'
        % (name, int(edge.sum()), depth, *n, len(floor), int(flip.sum())))
    return np.concatenate([np.array(walls), floor])


def duct(T, c, z0, z1, log, name, K=120):
    """T：整个模型的三角形（三个角 A、B、C，模型坐标）。在 Z = z0 的截面上从 c 往四周打 K 条射线量出进气道开口的轮廓（中心挪几次），
    往后挤到 z1：管壁正面朝管道中心，末端封口正面朝前（−Z）。返回三角形（m×3×3）"""
    A, Bv, C = T
    zlo = np.minimum(np.minimum(A[:, 2], Bv[:, 2]), C[:, 2])
    zhi = np.maximum(np.maximum(A[:, 2], Bv[:, 2]), C[:, 2])
    sel = (zlo <= z0 + 0.05) & (zhi >= z0 - 0.05)   # 只要跨过这个截面的三角形
    Ts = (A[sel], Bv[sel], C[sel])
    ang = np.arange(K) * 2 * np.pi / K
    dirs = np.stack([np.cos(ang), np.sin(ang), np.zeros(K)], 1)
    c = np.array([c[0], c[1], z0], dtype=np.float64)
    for _ in range(4):
        pts = []
        for d in dirs:
            h = airpaint.ray(Ts, c, d)
            if not h or h[0] > 6:
                log('  进气道 %s：Z %.1f 的截面没围住（方向 %s）' % (name, z0, np.round(d[:2], 2)))
                return None
            pts.append(c + d * (h[0] + 0.02))   # 往外 0.02 格，和管壁之间不留缝
        pts = np.array(pts)
        c = np.array([pts[:, 0].mean(), pts[:, 1].mean(), z0])
    dz = np.array([0, 0, z1 - z0])
    tris = []
    for k in range(K):
        p, q = pts[k], pts[(k + 1) % K]
        quad = [(p, q, q + dz), (p, q + dz, p + dz)]
        nw = np.cross(q - p, dz)
        if nw @ (c - (p + q) / 2) < 0:
            quad = [(p, q + dz, q), (p, p + dz, q + dz)]
        tris += quad
        cap = (c + dz, p + dz, q + dz)
        if np.cross(cap[1] - cap[0], cap[2] - cap[0])[2] > 0:   # 封口正面朝前（−Z）
            cap = (cap[0], cap[2], cap[1])
        tris.append(cap)
    r = np.linalg.norm(pts[:, :2] - c[:2], axis=1)
    log('  进气道 %s：Z %.1f → %.1f，中心 (%.2f, %.2f)，半径 %.2f～%.2f 格' % (name, z0, z1, c[0], c[1], r.min(), r.max()))
    return np.array(tris)


def lip_backfaces(J, BIN, c, za, zb, box, log, name, K=240, dz=0.05):
    """进气道唇口那一截：从管道中心线（X, Y = c，Z 从 za 到 zb）往四周打射线，先打到的面要是背对中心线（唇口内壁朝反了：
    歼-20 进气道顶上的内壁和外面的蒙皮一样朝上，从进气道里看是背面），记下来补反面。box：只看这个范围里的三角形 [[x0, y0, z0], [x1, y1, z1]]。
    返回 {(节点, 第几个图元): 三角形下标数组}"""
    W = glbfix.world_mats(J)
    A, Bv, C, owner = [], [], [], []
    lo, hi = np.array(box[0]), np.array(box[1])
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W or '__Well_' in nd.get('name', '') or '__Duct_' in nd.get('name', ''):
            continue
        M = W[ni]
        for pi, pr in enumerate(J['meshes'][nd['mesh']]['primitives']):
            P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
            I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            cen = P[I].mean(1)
            sel = np.nonzero(((cen >= lo) & (cen <= hi)).all(1))[0]
            if not len(sel):
                continue
            A.append(P[I[sel, 0]]); Bv.append(P[I[sel, 1]]); C.append(P[I[sel, 2]])
            owner += [(ni, pi, t) for t in sel]
    if not A:
        return {}
    A, Bv, C = np.concatenate(A), np.concatenate(Bv), np.concatenate(C)
    e1, e2 = Bv - A, C - A
    fn = np.cross(e1, e2)
    ang = np.arange(K) * 2 * np.pi / K
    dirs = np.stack([np.cos(ang), np.sin(ang), np.zeros(K)], 1)
    bad = set()
    for z in np.arange(za, zb + 1e-9, dz):
        o = np.array([c[0], c[1], z])
        s_ = o - A                                   # 三角形 × 3
        q = np.cross(s_, e1)                         # 三角形 × 3
        for d in dirs:
            p = np.cross(d, e2)
            det = (e1 * p).sum(1)
            ok = np.abs(det) > 1e-12
            inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
            u = (s_ * p).sum(1) * inv
            v = (q @ d) * inv
            t = (q * e2).sum(1) * inv
            hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
            if hit.any():
                k = np.nonzero(hit)[0][np.argmin(t[hit])]
                if fn[k] @ d > 0:
                    bad.add(k)
    out = {}
    for k in sorted(bad):
        ni, pi, t = owner[k]
        out.setdefault((ni, pi), []).append(t)
    log('  进气道 %s 唇口：从中心线看是背面的 %d 个三角形补反面' % (name, len(bad)))
    return {k: np.array(v) for k, v in out.items()}


def add_back(J, BIN, pr, sel=None):
    """给图元 pr 的三角形（sel：只给这几个；None：全部）补一份反面：顶点复制、法线取反、绕向反过来。返回补了几个"""
    att = pr['attributes']
    P = glbfix.acc_read(J, BIN, att['POSITION'])
    I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
    Is = I if sel is None else I[sel]
    if len(I) + len(Is) > TRI_MAX:
        return 0
    used = np.unique(Is)
    remap = np.full(len(P), -1, np.int64)
    remap[used] = len(P) + np.arange(len(used))
    I2 = np.concatenate([I, remap[Is][:, [0, 2, 1]]])
    for a in list(att):
        arr = glbfix.acc_read(J, BIN, att[a])
        extra = arr[used]
        if a == 'NORMAL':
            extra = -extra
        comp = J['accessors'][att[a]]['componentType']
        typ = J['accessors'][att[a]]['type']
        dt = {5126: '<f4', 5123: '<u2', 5121: 'u1', 5125: '<u4'}[comp]
        att[a] = put(J, BIN, np.ascontiguousarray(np.concatenate([arr, extra]), dt), typ, comp, a == 'POSITION')
    pr['indices'] = put(J, BIN, np.ascontiguousarray(I2.reshape(-1), '<u4'), 'SCALAR', 5125)
    return len(Is)


def add_part(J, BIN, info, root, key, name, C, mat, col):
    """三角形 C（m×3×3，模型坐标）做成一块新零件：GLB 里一个节点 + 元数据 parts 一行（机体上不动的）"""
    P = C.reshape(-1, 3)
    lo, hi = P.min(0), P.max(0)
    ctr = (lo + hi) / 2
    fn = np.cross(C[:, 1] - C[:, 0], C[:, 2] - C[:, 0])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    N = np.repeat(fn, 3, axis=0)
    I = np.arange(len(P), dtype=np.uint32)
    prim = {'attributes': {'POSITION': put(J, BIN, np.ascontiguousarray(P - ctr, '<f4'), 'VEC3', 5126, True),
                           'NORMAL': put(J, BIN, np.ascontiguousarray(N, '<f4'), 'VEC3', 5126),
                           'TEXCOORD_0': put(J, BIN, np.full((len(P), 2), 0.5, '<f4'), 'VEC2', 5126)},
            'indices': put(J, BIN, I, 'SCALAR', 5125), 'material': mat}
    J['meshes'].append({'name': 'A_%s__%s' % (key, name), 'primitives': [prim]})
    J['nodes'].append({'name': 'A_%s__%s' % (key, name), 'mesh': len(J['meshes']) - 1, 'translation': [float(v) for v in ctr]})
    J['nodes'][root].setdefault('children', []).append(len(J['nodes']) - 1)
    info['parts'][name] = {'c': [round(float(v), 3) for v in ctr], 's': [round(float(v), 3) for v in np.maximum(hi - lo, 0.02)],
                           'g': 'Body', 'col': list(col)}


def material(J, key, name, col):
    J['materials'].append({'name': 'A_%s_%s' % (key, name), 'doubleSided': False,
                           'pbrMetallicRoughness': {'baseColorFactor': [(v / 255) ** 2.2 for v in col] + [1], 'metallicFactor': 0.3, 'roughnessFactor': 0.75}})
    return len(J['materials']) - 1


def run(nm, glb, meta_path, log=print):
    spec = SPEC[nm]
    key = spec['key']
    J, BIN = glbfix.read(glb)
    BIN = bytearray(BIN)
    lines = open(meta_path, encoding='utf-8').read().split('\n')
    li = next(k for k, l in enumerate(lines) if l.startswith('    %s = {' % key))
    info = airpaint.lua_parse(lines[li].strip()[len(key) + 3:].rstrip(','))
    W = glbfix.world_mats(J)
    groups = {}   # 组 → [(节点, 图元)]
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or '__' not in nd.get('name', ''):
            continue
        part = info['parts'].get(nd['name'].split('__', 1)[1])
        if part:
            for pr in J['meshes'][nd['mesh']]['primitives']:
                groups.setdefault(part['g'], []).append((ni, pr))

    def tris(g):
        out = []
        for ni, pr in groups.get(g, []):
            M = W[ni]
            P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
            I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            out.append(P[I])
        return np.concatenate(out) if out else np.zeros((0, 3, 3))
    root = next(i for i, nd in enumerate(J['nodes']) if 'mesh' not in nd)
    made = nback = nduct = nlip = 0
    if not info.get('bayfix'):
        # —— 舱 ——
        col = spec['col']
        wm = material(J, key, 'bay_well', col)
        for k, (gs, depth) in enumerate(spec['cavity']):
            T = np.concatenate([tris(g) for g in gs])
            if not len(T):
                log('  舱 %s：没找到舱门' % '+'.join(gs))
                continue
            add_part(J, BIN, info, root, key, 'Well_%d' % (k + 1), cavity(T, depth, log, '+'.join(gs)), wm, col)
            made += 1
        # —— 舱门补反面 ——
        for g in spec['back']:
            for ni, pr in groups.get(g, []):
                n_ = add_back(J, BIN, pr)
                if not n_:
                    log('  %s 补反面会超 %d 个三角形，跳过' % (J['nodes'][ni]['name'], TRI_MAX))
                nback += n_
        info['bayfix'] = nm   # 补过舱、舱门反面（看元数据就知道导入的是不是这一版）
    if spec.get('intakes') and 'Duct_1' not in info['parts']:
        # —— 进气道 ——（量轮廓用原模型的三角形：不算刚加的舱）
        keep = [i for i, nd in enumerate(J['nodes']) if '__Well_' not in nd.get('name', '') and '__Duct_' not in nd.get('name', '')]
        T = airpaint.tris_world({**J, 'nodes': [nd if i in keep else {k: v for k, v in nd.items() if k != 'mesh'} for i, nd in enumerate(J['nodes'])]}, BIN)
        dcol = spec['duct_col']
        dm = material(J, key, 'duct', dcol)
        for it in spec['intakes']:
            for sx, side in ((1, 'L'), (-1, 'R')):
                c = [it['c'][0] * sx, it['c'][1]]
                if it.get('lip'):   # 唇口内壁朝反的补反面（在挤管道之前：只看原模型的面）
                    L = it['lip']
                    box = [[min(L['x'][0] * sx, L['x'][1] * sx), L['y'][0], L['z'][0]], [max(L['x'][0] * sx, L['x'][1] * sx), L['y'][1], L['z'][1]]]
                    for (ni, pi), sel in lip_backfaces(J, BIN, c, L['z'][0], it['z0'], box, log, side).items():
                        nlip += add_back(J, BIN, J['meshes'][J['nodes'][ni]['mesh']]['primitives'][pi], sel)
                D = duct(T, c, it['z0'], it['z1'], log, side)
                if D is None:
                    continue
                nduct += 1
                add_part(J, BIN, info, root, key, 'Duct_%d' % nduct, D, dm, dcol)
    BIN = glbfix.solid_textures(J, BIN, log)
    # 换下来的旧访问器、bufferView 去掉，重新紧凑地排一遍
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
    glbfix.write(glb, J, NB)
    lines[li] = '    %s = %s,' % (key, B.lua(info))
    open(meta_path, 'w', encoding='utf-8').write('\n'.join(lines))
    log('  %s：加了 %d 个舱，舱门补反面 %d 个三角形，进气道 %d 个（唇口内壁补反面 %d 个三角形）' % (key, made, nback, nduct, nlip))


if __name__ == '__main__':
    nm = sys.argv[1]
    run(nm, sys.argv[2] if len(sys.argv) > 2 else 'models/air/%s.glb' % nm,
        sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/ImportedAir.lua')
