# GLB 导入 Roblox 前的修正（tools/models/mdl2glb.py 的 write_glb 写完都过一遍：地面载具、飞机、舰艇；也能单独对现成的 GLB 跑）
#   1) 面朝向（facing.py）：Roblox 只画正面，原模型里朝里的面在 Roblox 里看不见（用户：歼-20 机头镂空）——朝里的整块翻过来
#   2) 没有厚度的单层板（两面都露在外面：垂尾、天线、桨叶……）补一份反面（用户：歼-16 很怪——左垂尾从右边看只剩一条边、像根杆子）；
#      补了以后一块网格超过 2 万个三角形（Roblox 的上限）就不补这一块
#   3) 只有底色、没贴图的材质配一张 8×8 的纯色贴图：Roblox「导入 3D」不认 glTF 材质的底色（baseColorFactor），只认贴图，
#      这种材质导入后一律灰白（用户：JLTV 没有颜色）；底色换成白（别的软件看也不会变色）。半透明（BLEND）的玻璃照原样不配
#   只能对原样转出来的 GLB 跑一次（补反面不能重复补）
# 用法：python3 -I tools/models/glbfix.py <输入.glb> [输出.glb，默认覆盖输入]
#       python3 -I tools/models/glbfix.py <目录>          目录下全部 .glb 就地改
import json, os, struct, sys, zlib
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import facing   # noqa: E402

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
TRI_MAX = 20000   # Roblox 一块网格最多多少三角形


def _q(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def read(path):
    b = open(path, 'rb').read()
    jl = struct.unpack('<I', b[12:16])[0]
    J = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack('<I', b[off:off + 4])[0]
    return J, bytearray(b[off + 8:off + 8 + bl])


def write(path, J, BIN):
    while len(BIN) % 4:
        BIN.append(0)
    J['buffers'][0]['byteLength'] = len(BIN)
    js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode()
    while len(js) % 4:
        js += b' '
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(BIN)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(BIN), 0x004E4942))
        f.write(bytes(BIN))


def acc_read(J, BIN, i):
    """访问器 → numpy 数组（支持交错的顶点缓冲）"""
    a = J['accessors'][i]
    n, dt = NC[a['type']], np.dtype(CT[a['componentType']])
    if 'bufferView' not in a:
        return np.zeros((a['count'], n), dtype=dt) if n > 1 else np.zeros(a['count'], dtype=dt)
    bv = J['bufferViews'][a['bufferView']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0) or n * dt.itemsize
    if stride == n * dt.itemsize:
        arr = np.frombuffer(bytes(BIN[o:o + a['count'] * stride]), dtype=dt).reshape(a['count'], n)
    else:
        raw = np.frombuffer(bytes(BIN[o:o + (a['count'] - 1) * stride + n * dt.itemsize]), dtype=np.uint8)
        arr = np.stack([raw[k * stride:k * stride + n * dt.itemsize].view(dt) for k in range(a['count'])])
    return arr.copy() if n > 1 else arr.reshape(-1).copy()


def world_mats(J):
    W = {}

    def rec(i, Pm):
        nd = J['nodes'][i]
        if 'matrix' in nd:
            L = np.array(nd['matrix']).reshape(4, 4).T
        else:
            Tm = np.eye(4); Tm[:3, 3] = nd.get('translation', [0, 0, 0])
            Rm = np.eye(4); Rm[:3, :3] = _q(nd.get('rotation', [0, 0, 0, 1]))
            L = Tm @ Rm @ np.diag(list(nd.get('scale', [1, 1, 1])) + [1])
        W[i] = Pm @ L
        for ch in nd.get('children', []):
            rec(ch, W[i])
    for s in J['scenes'][J.get('scene', 0)]['nodes']:
        rec(s, np.eye(4))
    return W


def fix_geometry(J, BIN, log=print):
    """面朝向 + 单层板补反面；改过的图元重新写访问器（新的 bufferView），最后把用不到的缓冲去掉重新排；返回新的 BIN"""
    W = world_mats(J)
    chunks, seen = [], set()
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W:
            continue
        M = W[ni]
        if np.linalg.det(M[:3, :3]) < 0:
            log('  %s：节点有镜像变换，跳过' % nd.get('name'))
            continue
        for p in J['meshes'][nd['mesh']]['primitives']:
            if id(p) in seen or p.get('mode', 4) != 4 or 'indices' not in p or 'NORMAL' not in p['attributes']:
                continue
            seen.add(id(p))
            attrs = {k: acc_read(J, BIN, ai) for k, ai in p['attributes'].items()}
            P = attrs['POSITION'].astype(np.float64)
            T = acc_read(J, BIN, p['indices']).astype(np.int64).reshape(-1, 3)
            chunks.append({'prim': p, 'attrs': attrs, 'P': (np.c_[P, np.ones(len(P))] @ M.T)[:, :3],
                           'N': attrs['NORMAL'].astype(np.float64), 'T': T})
    if not chunks:
        return BIN
    facing.orient(chunks, log)
    new_data = {}
    skipped = 0
    for c in chunks:
        p, attrs, T = c['prim'], c['attrs'], c['T']
        dup = c.get('dup')
        if dup is not None and dup.any():
            if len(T) + int(dup.sum()) > TRI_MAX:
                skipped += int(dup.sum())
            else:
                tris = T[dup]
                u, inv = np.unique(tris.reshape(-1), return_inverse=True)
                n0 = len(attrs['POSITION'])
                for k in attrs:
                    extra = attrs[k][u].copy()
                    if k == 'NORMAL':
                        extra = -extra
                    elif k == 'TANGENT' and extra.ndim == 2 and extra.shape[1] >= 3:
                        extra[:, :3] = -extra[:, :3]
                    attrs[k] = np.concatenate([attrs[k], extra])
                c['N'] = np.concatenate([c['N'], -c['N'][u]])
                T = np.concatenate([T, (n0 + inv.reshape(-1, 3))[:, [0, 2, 1]]])
        nrm = c['N'] / np.maximum(np.linalg.norm(c['N'], axis=1, keepdims=True), 1e-9)
        attrs['NORMAL'] = nrm.astype(attrs['NORMAL'].dtype) if attrs['NORMAL'].dtype.kind == 'f' else attrs['NORMAL']
        for k, ai in p['attributes'].items():
            new_data[ai] = attrs[k]
        idt = np.uint32 if len(attrs['POSITION']) > 65535 else np.dtype(CT[J['accessors'][p['indices']]['componentType']]).type
        new_data[p['indices']] = T.reshape(-1).astype(idt)
    if skipped:
        log('  单层板补反面：有 %d 个三角形补了会超过一块 %d 个的上限，没补' % (skipped, TRI_MAX))
    return rebuild(J, BIN, new_data)


def rebuild(J, BIN, new_data):
    views = J['bufferViews']
    vbytes = [bytes(BIN[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]) for v in views]
    for ai, arr in new_data.items():
        a = J['accessors'][ai]
        old = views[a['bufferView']] if 'bufferView' in a else {}
        arr = np.ascontiguousarray(arr)
        data = arr.tobytes()
        nv = {'buffer': 0, 'byteLength': len(data)}
        if old.get('target'):
            nv['target'] = old['target']
        views.append(nv)
        vbytes.append(data)
        a['bufferView'] = len(views) - 1
        a.pop('byteOffset', None)
        a['count'] = int(arr.shape[0])
        if arr.dtype == np.uint32:
            a['componentType'] = 5125
        elif arr.dtype == np.uint16:
            a['componentType'] = 5123
        if 'min' in a:   # 位置访问器必须带包围盒
            a['min'] = [float(x) for x in np.atleast_1d(arr.min(0))]
            a['max'] = [float(x) for x in np.atleast_1d(arr.max(0))]
    used = {a['bufferView'] for a in J['accessors'] if 'bufferView' in a} | {im['bufferView'] for im in J.get('images', []) if 'bufferView' in im}
    out, keep, remap = bytearray(), [], {}
    for i, v in enumerate(views):
        if i not in used:
            continue
        while len(out) % 4:
            out.append(0)
        nv = dict(v)
        nv['byteOffset'] = len(out)
        out.extend(vbytes[i])
        remap[i] = len(keep)
        keep.append(nv)
    J['bufferViews'] = keep
    for a in J['accessors']:
        if 'bufferView' in a:
            a['bufferView'] = remap[a['bufferView']]
    for im in J.get('images', []):
        if 'bufferView' in im:
            im['bufferView'] = remap[im['bufferView']]
    return out


def _srgb(c):
    c = min(max(float(c), 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def _png(rgba, n=8):
    raw = b''.join(b'\x00' + bytes(rgba) * n for _ in range(n))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')


def solid_textures(J, BIN, log=print):
    mats = J.get('materials', [])
    uv_ok = set()   # 只给有 UV 的图元用到的材质配（没 UV 的配了也贴不上）
    for m in J.get('meshes', []):
        for p in m['primitives']:
            if 'material' in p and 'TEXCOORD_0' in p['attributes']:
                uv_ok.add(p['material'])
    made, cache = 0, {}
    for mi, m in enumerate(mats):
        pbr = m.setdefault('pbrMetallicRoughness', {})
        if 'baseColorTexture' in pbr or m.get('alphaMode') == 'BLEND' or mi not in uv_ok:
            continue
        c = pbr.get('baseColorFactor', [1, 1, 1, 1])
        rgba = tuple(int(round(_srgb(v) * 255)) for v in c[:3]) + (255,)
        if rgba not in cache:
            data = _png(rgba)
            while len(BIN) % 4:
                BIN.append(0)
            J.setdefault('bufferViews', []).append({'buffer': 0, 'byteOffset': len(BIN), 'byteLength': len(data)})
            BIN.extend(data)
            J.setdefault('images', []).append({'bufferView': len(J['bufferViews']) - 1, 'mimeType': 'image/png', 'name': 'solid_%02x%02x%02x' % rgba[:3]})
            if not J.get('samplers'):
                J['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]
            J.setdefault('textures', []).append({'source': len(J['images']) - 1, 'sampler': 0})
            cache[rgba] = len(J['textures']) - 1
        pbr['baseColorTexture'] = {'index': cache[rgba]}
        pbr['baseColorFactor'] = [1.0, 1.0, 1.0, float(c[3]) if len(c) > 3 else 1.0]
        made += 1
    if made:
        log('  纯色贴图：%d 个材质配上（%d 种颜色）' % (made, len(cache)))
    return BIN


def single_sided(J):
    """面朝向理好、单层板补了反面以后材质改成单面：别的软件（网页版、宣传片的 three.js）认双面，正反两层叠在一起会闪；Roblox 本来就只画正面"""
    for m in J.get('materials', []):
        m['doubleSided'] = False


def fix_file(src, dst=None, log=print):
    J, BIN = read(src)
    BIN = fix_geometry(J, BIN, log)
    BIN = solid_textures(J, BIN, log)
    single_sided(J)
    write(dst or src, J, BIN)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('用法见文件开头')
        sys.exit(1)
    a = sys.argv[1]
    if os.path.isdir(a):
        for f in sorted(os.listdir(a)):
            if f.endswith('.glb'):
                print(f, flush=True)
                fix_file(os.path.join(a, f))
    else:
        print(os.path.basename(a), flush=True)
        fix_file(a, sys.argv[2] if len(sys.argv) > 2 else None)
