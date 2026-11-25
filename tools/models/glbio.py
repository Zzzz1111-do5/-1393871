# 读写 GLB 的共用件（carve.py、glbview.py 用）：节点按父子关系算好世界坐标（格，原点车底中心，−Z 朝前，同 ImportedMeta），
#   每块网格给出三角形、UV、材质、底色贴图（PIL 图）；写回时按 t625_split.py 那套把 BIN 重新排一遍、接上新节点
import io, json, struct
import numpy as np

CT = {5120: 'i1', 5121: 'u1', 5122: 'i2', 5123: 'u2', 5125: 'u4', 5126: 'f4'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF', '不是 GLB：' + path
    off, J, BIN = 12, None, b''
    while off < len(b):
        ln, ty = struct.unpack('<I4s', b[off:off + 8])
        data = b[off + 8:off + 8 + ln]
        off += 8 + ln
        if ty == b'JSON':
            J = json.loads(data)
        elif ty == b'BIN\x00':
            BIN = data
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


def node_local(n):
    M = np.eye(4)
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
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


def world_mats(J):
    W = {}
    parent = {}
    for i, n in enumerate(J['nodes']):
        for c in n.get('children', []):
            parent[c] = i

    def get(i):
        if i in W:
            return W[i]
        L = node_local(J['nodes'][i])
        W[i] = (get(parent[i]) @ L) if i in parent else L
        return W[i]
    for i in range(len(J['nodes'])):
        get(i)
    return W


def images(J, BIN):
    """图片序号 → PIL 图（RGB）"""
    from PIL import Image
    out = {}
    for i, im in enumerate(J.get('images', [])):
        if 'bufferView' not in im:
            continue
        bv = J['bufferViews'][im['bufferView']]
        s = bv.get('byteOffset', 0)
        try:
            out[i] = Image.open(io.BytesIO(BIN[s:s + bv['byteLength']])).convert('RGB')
        except Exception:
            pass
    return out


class Mesh:
    """一个节点的一个 primitive：P 世界坐标（格），N 法线，UV，idx 三角形（k×3），mat 材质序号，node 节点名"""
    __slots__ = ('node', 'ni', 'mi', 'pi', 'P', 'N', 'UV', 'idx', 'mat')


def meshes(J, BIN):
    W = world_mats(J)
    out = []
    for ni, n in enumerate(J['nodes']):
        if 'mesh' not in n:
            continue
        M = W[ni]
        R = M[:3, :3]
        for pi, pr in enumerate(J['meshes'][n['mesh']]['primitives']):
            if pr.get('mode', 4) != 4:
                continue
            m = Mesh()
            m.node, m.ni, m.mi, m.pi = n.get('name', ''), ni, n['mesh'], pi
            P = accessor(J, BIN, pr['attributes']['POSITION']).astype(np.float64)
            m.P = P @ R.T + M[:3, 3]
            if 'NORMAL' in pr['attributes']:
                N = accessor(J, BIN, pr['attributes']['NORMAL']).astype(np.float64) @ np.linalg.inv(R).T
                ln = np.linalg.norm(N, axis=1, keepdims=True)
                m.N = N / np.maximum(ln, 1e-9)
            else:
                m.N = None
            m.UV = accessor(J, BIN, pr['attributes']['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in pr['attributes'] else None
            if 'indices' in pr:
                m.idx = accessor(J, BIN, pr['indices']).reshape(-1, 3).astype(np.int64)
            else:
                m.idx = np.arange(len(P)).reshape(-1, 3)
            m.mat = pr.get('material')
            out.append(m)
    return out


def part_name(node):
    """V_<键>__Body_3 → Body_3"""
    return node.split('__', 1)[1] if '__' in node else node


def tri_colors(J, imgs, m):
    """每个三角形的底色（0–1，按 UV 中心取贴图 × 材质底色）"""
    k = len(m.idx)
    col = np.ones((k, 3))
    alpha = np.ones(k)
    if m.mat is None:
        return col * 0.6, alpha
    mat = J['materials'][m.mat]
    pbr = mat.get('pbrMetallicRoughness', {})
    f = pbr.get('baseColorFactor', [1, 1, 1, 1])
    col *= np.array(f[:3])
    alpha *= f[3]
    t = pbr.get('baseColorTexture')
    if t is not None and m.UV is not None:
        src = J['textures'][t['index']].get('source')
        im = imgs.get(src)
        if im is not None:
            a = np.asarray(im, dtype=np.float64) / 255.0
            h, w = a.shape[:2]
            uv = m.UV[m.idx].mean(axis=1)
            u = np.mod(uv[:, 0], 1.0)
            v = np.mod(uv[:, 1], 1.0)
            px = np.clip((u * w).astype(int), 0, w - 1)
            py = np.clip((v * h).astype(int), 0, h - 1)
            col *= a[py, px] ** 2.2   # sRGB → 线性（着色用）
    return col, alpha


def write_glb(path, J, BIN_chunks):
    """J 的 bufferViews 已经指向 BIN_chunks 拼起来的那一整块"""
    out = bytes(BIN_chunks)
    js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    while len(js) % 4:
        js += b' '
    while len(out) % 4:
        out += b'\x00'
    J['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    while len(js) % 4:
        js += b' '
    glb = bytearray(b'glTF' + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(out)))
    glb += struct.pack('<I4s', len(js), b'JSON') + js
    glb += struct.pack('<I4s', len(out), b'BIN\x00') + out
    open(path, 'wb').write(glb)
    return len(glb)
