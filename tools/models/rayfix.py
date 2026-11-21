# 逐个三角形按射线修面朝向（GLB 写出、glbfix.py 修过以后再过一遍）：Roblox 的 MeshPart 只画正面，原模型的材质是双面的、绕向和法线朝哪的都有，
#   facing.py 按连通块整块翻、按顶点法线翻，对不减面的歼-20（andertan，j20_v4）不管用——机头尖那一段按面积六成多是朝里的（Roblox 里像镂空的）。
#   这里每个三角形从正面、背面各往外打几条射线（embree 加速）：正面几乎都被挡住、背面大多打得出去 = 朝反了 → 翻绕向，法线跟着反（顶点拆开复制）；
#   两面都打得出去的单层板、两面都打不出去的（机身里面）不动。
#   依赖：pip install trimesh embreex（只有这一步要；其余转换工具只用 numpy）
#   用法：python3 tools/models/rayfix.py <GLB> [输出 GLB，默认覆盖原文件]
import json, struct, sys
import numpy as np
import trimesh

K = 6            # 每面打几条射线
SPREAD = 0.35    # 射线在法线附近散开多少
EPS = 0.02       # 起点离面多远（格）


def read(path):
    data = open(path, 'rb').read()
    _, _, total = struct.unpack('<4sII', data[:12])
    off, J, BIN = 12, None, b''
    while off < total:
        n, t = struct.unpack('<I4s', data[off:off + 8])
        if t == b'JSON':
            J = json.loads(data[off + 8:off + 8 + n])
        else:
            BIN = data[off + 8:off + 8 + n]
        off += 8 + n
    return J, bytearray(BIN)


def acc(J, BIN, i):
    a = J['accessors'][i]
    v = J['bufferViews'][a['bufferView']]
    dt = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    st = v.get('byteStride')
    base = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    item = np.dtype(dt).itemsize * n
    if st and st != item:
        raw = np.frombuffer(bytes(BIN), np.uint8, a['count'] * st, base).reshape(a['count'], st)[:, :item].copy()
        return raw.view(dt).reshape(a['count'], n)
    return np.frombuffer(bytes(BIN), dt, a['count'] * n, base).reshape(a['count'], n).copy()


def node_mats(J):
    """每个带网格的节点的世界矩阵（只认 translation / rotation / scale / matrix）"""
    def local(n):
        if 'matrix' in n:
            return np.array(n['matrix'], float).reshape(4, 4).T
        t = np.array(n.get('translation', [0, 0, 0]), float)
        x, y, z, w = n.get('rotation', [0, 0, 0, 1])
        s = np.array(n.get('scale', [1, 1, 1]), float)
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4)
        M[:3, :3] = R * s
        M[:3, 3] = t
        return M
    out = {}
    def walk(i, M):
        n = J['nodes'][i]
        M = M @ local(n)
        if 'mesh' in n:
            out[i] = M
        for c in n.get('children', []):
            walk(c, M)
    for r in J['scenes'][J.get('scene', 0)]['nodes']:
        walk(r, np.eye(4))
    return out


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    J, BIN = read(src)
    mats = node_mats(J)
    # 整架模型（世界坐标）：每个图元的三角形
    prims = []
    for ni, M in mats.items():
        for pi, p in enumerate(J['meshes'][J['nodes'][ni]['mesh']]['primitives']):
            P = acc(J, BIN, p['attributes']['POSITION']).astype(float)
            I = acc(J, BIN, p['indices']).reshape(-1, 3).astype(np.int64)
            W = P @ M[:3, :3].T + M[:3, 3]
            prims.append((ni, pi, p, P, I, W))
    allW = np.concatenate([W[I] for *_, I, W in prims]).reshape(-1, 3)
    allF = np.arange(len(allW)).reshape(-1, 3)
    mesh = trimesh.Trimesh(allW, allF, process=False)
    ray = trimesh.ray.ray_pyembree.RayMeshIntersector(mesh)
    T = mesh.triangles
    fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    area = np.linalg.norm(fn, axis=1)
    n = fn / (area[:, None] + 1e-15)
    C = T.mean(1)
    rng = np.random.default_rng(7)

    def escapes(sign):
        e = np.zeros(len(T), int)
        for _ in range(K):
            d = sign * n + rng.normal(0, SPREAD, n.shape)
            d /= np.linalg.norm(d, axis=1, keepdims=True)
            bad = (d * n).sum(1) * sign < 0.2
            d[bad] = sign * n[bad]
            e += ~ray.intersects_any(C + d * EPS, d)
        return e
    ef, eb = escapes(1), escapes(-1)
    inv = (ef <= 1) & (eb >= 4) & (area > 1e-10)
    print('  逐面打射线：%d 个三角形，朝反的 %d 个（面积 %.1f%%）' % (len(T), inv.sum(), 100 * area[inv].sum() / area.sum()))
    # 改：朝反的三角形翻绕向、顶点复制一份（法线取反），写进新的访问器
    base = 0
    for ni, pi, p, P, I, W in prims:
        m = len(I)
        sel = inv[base:base + m]
        base += m
        if not sel.any():
            continue
        att = p['attributes']
        N = acc(J, BIN, att['NORMAL']).astype(np.float32) if 'NORMAL' in att else None
        UV = acc(J, BIN, att['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in att else None
        P32 = P.astype(np.float32)
        flipI = I[sel]
        nv = len(P32)
        newIdx = np.arange(nv, nv + flipI.size).reshape(-1, 3)
        Pn = np.concatenate([P32, P32[flipI.reshape(-1)]])
        Nn = np.concatenate([N, -N[flipI.reshape(-1)]]) if N is not None else None
        UVn = np.concatenate([UV, UV[flipI.reshape(-1)]]) if UV is not None else None
        I2 = I.copy()
        I2[sel] = newIdx[:, [0, 2, 1]]
        # 用到的旧顶点之外不清理（数量不大）；新数据追加到 BIN 末尾
        def put(arr, typ, comp, minmax=False):
            nonlocal BIN
            while len(BIN) % 4:
                BIN.append(0)
            bv = {'buffer': 0, 'byteOffset': len(BIN), 'byteLength': arr.nbytes}
            BIN += arr.tobytes()
            J['bufferViews'].append(bv)
            ac = {'bufferView': len(J['bufferViews']) - 1, 'componentType': comp, 'count': int(arr.shape[0]) if typ != 'SCALAR' else int(arr.size), 'type': typ}
            if minmax:
                ac['min'] = arr.min(0).tolist()
                ac['max'] = arr.max(0).tolist()
            J['accessors'].append(ac)
            return len(J['accessors']) - 1
        att['POSITION'] = put(np.ascontiguousarray(Pn, '<f4'), 'VEC3', 5126, True)
        if Nn is not None:
            att['NORMAL'] = put(np.ascontiguousarray(Nn, '<f4'), 'VEC3', 5126)
        if UVn is not None:
            att['TEXCOORD_0'] = put(np.ascontiguousarray(UVn, '<f4'), 'VEC2', 5126)
        p['indices'] = put(np.ascontiguousarray(I2.reshape(-1), '<u4'), 'SCALAR', 5125)
    # 没被图元用到的访问器也去掉
    usedA = sorted({i for m in J['meshes'] for p in m['primitives'] for i in list(p['attributes'].values()) + ([p['indices']] if 'indices' in p else [])})
    amap = {old: k for k, old in enumerate(usedA)}
    J['accessors'] = [J['accessors'][i] for i in usedA]
    for m in J['meshes']:
        for p in m['primitives']:
            p['attributes'] = {k: amap[v] for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = amap[p['indices']]
    # 换下来的旧顶点、旧索引没人用了：只留还被访问器 / 贴图引用的 bufferView，重新紧凑地排一遍
    used = sorted({a['bufferView'] for a in J['accessors'] if 'bufferView' in a} | {im['bufferView'] for im in J.get('images', []) if 'bufferView' in im})
    remap, NB = {}, bytearray()
    views = []
    for old in used:
        v = dict(J['bufferViews'][old])
        while len(NB) % 4:
            NB.append(0)
        o = v.get('byteOffset', 0)
        chunk = BIN[o:o + v['byteLength']]
        v['byteOffset'] = len(NB)
        NB += chunk
        remap[old] = len(views)
        views.append(v)
    for a in J['accessors']:
        if 'bufferView' in a:
            a['bufferView'] = remap[a['bufferView']]
    for im in J.get('images', []):
        if 'bufferView' in im:
            im['bufferView'] = remap[im['bufferView']]
    J['bufferViews'] = views
    BIN = NB
    J['buffers'][0]['byteLength'] = len(BIN)
    js = json.dumps(J, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    js += b' ' * ((4 - len(js) % 4) % 4)
    while len(BIN) % 4:
        BIN.append(0)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(BIN)))
        f.write(struct.pack('<I4s', len(js), b'JSON'))
        f.write(js)
        f.write(struct.pack('<I4s', len(BIN), b'BIN\x00'))
        f.write(bytes(BIN))
    print('  → %s' % dst)


if __name__ == '__main__':
    main()
