# 雪山地图用的 glTF 读取（tools/snow/*.py 共用）：读 scene.gltf（+ .bin、贴图），把每个图元的顶点按节点矩阵变到世界坐标（Y 朝上），
#   返回 [{ name, mat, pos (N×3), nrm, uv (N×2), idx (M×3) }] 和材质表（贴图路径）。只认外部 .bin / 贴图文件（Sketchfab 下载的 glTF 压缩包就是这样）
import json, os
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def _mat(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    M = np.eye(4)
    if 'scale' in n:
        M = np.diag(list(n['scale']) + [1.0]) @ M
    if 'rotation' in n:
        x, y, z, w = n['rotation']
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        R4 = np.eye(4)
        R4[:3, :3] = R
        M = R4 @ M
    if 'translation' in n:
        T = np.eye(4)
        T[:3, 3] = n['translation']
        M = T @ M
    return M


def load(path):
    D = os.path.dirname(os.path.abspath(path))
    if path.lower().endswith('.glb'):   # GLB：JSON 块 + 一个二进制块（tools/snow/peaks.py 写的那种）
        import struct
        raw = open(path, 'rb').read()
        jl = struct.unpack_from('<I', raw, 12)[0]
        J = json.loads(raw[20:20 + jl])
        bl = struct.unpack_from('<I', raw, 20 + jl)[0]
        bufs = [raw[28 + jl:28 + jl + bl]]
    else:
        J = json.load(open(path))
        bufs = [open(os.path.join(D, b['uri']), 'rb').read() for b in J['buffers']]

    def acc(i):
        a = J['accessors'][i]
        bv = J['bufferViews'][a['bufferView']]
        dt = np.dtype(CT[a['componentType']])
        n = NC[a['type']]
        o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0) or n * dt.itemsize
        raw = bufs[bv['buffer']]
        if stride == n * dt.itemsize:
            arr = np.frombuffer(raw, dtype=dt, count=a['count'] * n, offset=o).reshape(a['count'], n)
        else:
            arr = np.lib.stride_tricks.as_strided(np.frombuffer(raw, dtype=np.uint8, offset=o),
                                                  shape=(a['count'], n * dt.itemsize), strides=(stride, 1)).copy().view(dt).reshape(a['count'], n)
        arr = arr.astype(np.float64) if dt.kind == 'f' else arr.astype(np.int64)
        if a.get('normalized') and dt.kind != 'f':
            arr = arr / float(np.iinfo(dt).max)
        return arr

    prims = []

    def walk(ni, M):
        n = J['nodes'][ni]
        W = M @ _mat(n)
        if 'mesh' in n:
            for pi, p in enumerate(J['meshes'][n['mesh']]['primitives']):
                if p.get('mode', 4) != 4:
                    continue
                pos = acc(p['attributes']['POSITION'])
                pw = (np.c_[pos, np.ones(len(pos))] @ W.T)[:, :3]
                nr = None
                if 'NORMAL' in p['attributes']:
                    N3 = np.linalg.inv(W[:3, :3]).T
                    nr = acc(p['attributes']['NORMAL']) @ N3.T
                    nr /= np.maximum(np.linalg.norm(nr, axis=1, keepdims=True), 1e-12)
                uv = acc(p['attributes']['TEXCOORD_0']) if 'TEXCOORD_0' in p['attributes'] else None
                idx = acc(p['indices']).reshape(-1, 3) if 'indices' in p else np.arange(len(pos)).reshape(-1, 3)
                if np.linalg.det(W[:3, :3]) < 0:   # 镜像矩阵：三角形绕向反过来
                    idx = idx[:, [0, 2, 1]]
                prims.append(dict(name=f"{n.get('name', ni)}#{pi}", mat=p.get('material'), pos=pw, nrm=nr, uv=uv, idx=idx))
        for c in n.get('children', []):
            walk(c, W)

    sc = J['scenes'][J.get('scene', 0)]
    for r in sc['nodes']:
        walk(r, np.eye(4))
    mats = []
    for m in J.get('materials', []):
        pbr = m.get('pbrMetallicRoughness', {})

        def tex(t):
            if not t:
                return None
            im = J['images'][J['textures'][t['index']]['source']]
            return os.path.join(D, im['uri']) if 'uri' in im else ('bufferView', im.get('bufferView'))
        mats.append(dict(name=m.get('name'), base=tex(pbr.get('baseColorTexture')), mr=tex(pbr.get('metallicRoughnessTexture')),
                         nrm=tex(m.get('normalTexture')), nscale=(m.get('normalTexture') or {}).get('scale', 1.0),
                         factor=pbr.get('baseColorFactor'), alpha=m.get('alphaMode', 'OPAQUE'), double=m.get('doubleSided', False),
                         rough=pbr.get('roughnessFactor'), metal=pbr.get('metallicFactor')))
    return prims, mats
