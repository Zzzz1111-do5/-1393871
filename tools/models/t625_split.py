# PGL-625 的导弹发射架原来和车体是同一块网格（V_t625__Body_1），炮塔转、炮抬头时发射架不动（用户 11-22 看宣传片：「防空车为什么炮塔转导弹发射器不转」）。
#   宣传片（tools/trailer/film/models.js 的 VEH_MOVE）是加载时按三角形位置挪到炮那一组；游戏里的网格是 Studio 导入的、运行时拆不开——
#   这里直接改 GLB：Body_1 按同一个条件拆成两块，新名字 Body_5（车体剩下的）、Gun_2（两侧的发射架，跟炮一起转、一起抬），Body_1 去掉。
#   名字换新的是为了新旧两份都能用：没重新导入的，游戏照旧找得到 Body_1（ImportedMeta 里留着它）；重新导入以后找到 Body_5、Gun_2。
#   用法（仓库根目录）：python3 -I tools/models/t625_split.py models/veh/t625.glb models/veh/t625.glb
#   打印 ImportedMeta.lua 要加的两条（c = 块的中心 = 节点平移，s = 网格包围盒）
import json, struct, sys
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
NODE = 'V_t625__Body_1'
KEEP, TAKE = 'V_t625__Body_5', 'V_t625__Gun_2'


def take_tri(c):   # 宣传片里用的同一个条件（车身坐标，格）：炮塔两侧、高过车顶的那一圈
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x - 0.14)
    return (y > 7.75) & (ax > 3.2) & (ax < 5.8) & (z > -4.6) & (z < 5.6)


b = open(SRC, 'rb').read()
assert b[:4] == b'glTF', '不是 GLB'
off, J, BIN = 12, None, None
while off < len(b):
    ln, ty = struct.unpack('<I4s', b[off:off + 8])
    data = b[off + 8:off + 8 + ln]
    off += 8 + ln
    if ty == b'JSON':
        J = json.loads(data)
    elif ty == b'BIN\x00':
        BIN = data
CT = {5120: 'i1', 5121: 'u1', 5122: 'i2', 5123: 'u2', 5125: 'u4', 5126: 'f4'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_acc(i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    n, dt = NC[a['type']], np.dtype(CT[a['componentType']])
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0) or dt.itemsize * n
    return np.array(np.ndarray((a['count'], n), dtype=dt, buffer=BIN, offset=start, strides=(stride, dt.itemsize)))


ni = next(i for i, n in enumerate(J['nodes']) if n.get('name') == NODE)
node = J['nodes'][ni]
mi = node['mesh']
T = np.array(node.get('translation', [0, 0, 0]), dtype=np.float64)
prims = J['meshes'][mi]['primitives']
assert len(prims) == 1, 'Body_1 应该只有一个 primitive'
pr = prims[0]
attrs = {k: read_acc(v) for k, v in pr['attributes'].items()}
idx = read_acc(pr['indices']).reshape(-1, 3).astype(np.int64)
P = attrs['POSITION'].astype(np.float64) + T
cent = P[idx].mean(axis=1)
mask = take_tri(cent)
print('Body_1：%d 个三角形，拆出发射架 %d 个' % (len(idx), int(mask.sum())))
assert 200 < mask.sum() < len(idx) - 200, '拆出来的三角形数不对劲'

# —— 新的 BIN：照原来的 bufferView 顺序拷贝（去掉 Body_1 用的那几段），后面接上两块新网格的数据 ——
used_acc = set()
for k, m in enumerate(J['meshes']):
    if k == mi:
        continue
    for p in m['primitives']:
        used_acc.update(p['attributes'].values())
        if 'indices' in p:
            used_acc.add(p['indices'])
used_bv = {J['accessors'][a]['bufferView'] for a in used_acc}
for im in J.get('images', []):
    if 'bufferView' in im:
        used_bv.add(im['bufferView'])
out = bytearray()
bv_new, bv_map = [], {}


def pad4():
    while len(out) % 4:
        out.append(0)


for i, bv in enumerate(J['bufferViews']):
    if i not in used_bv:
        continue
    pad4()
    s = bv.get('byteOffset', 0)
    chunk = BIN[s:s + bv['byteLength']]
    nb = dict(bv)
    nb['byteOffset'] = len(out)
    out += chunk
    bv_map[i] = len(bv_new)
    bv_new.append(nb)
acc_new, acc_map = [], {}
for i, a in enumerate(J['accessors']):
    if i not in used_acc:
        continue
    na = dict(a)
    na['bufferView'] = bv_map[a['bufferView']]
    acc_map[i] = len(acc_new)
    acc_new.append(na)


def add_acc(arr, ctype, typ, target, minmax=False):
    pad4()
    raw = np.ascontiguousarray(arr).tobytes()
    bv = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(raw)}
    if target:
        bv['target'] = target
    out.extend(raw)
    bv_new.append(bv)
    a = {'bufferView': len(bv_new) - 1, 'componentType': ctype, 'count': int(arr.shape[0]), 'type': typ}
    if minmax:
        a['min'] = [float(v) for v in arr.min(0)]
        a['max'] = [float(v) for v in arr.max(0)]
    acc_new.append(a)
    return len(acc_new) - 1


CTYPE = {np.dtype('float32'): 5126, np.dtype('uint16'): 5123, np.dtype('uint32'): 5125}
TYP = {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}
mesh_new = []
for k, m in enumerate(J['meshes']):
    if k == mi:
        continue
    nm = json.loads(json.dumps(m))
    for p in nm['primitives']:
        p['attributes'] = {kk: acc_map[v] for kk, v in p['attributes'].items()}
        if 'indices' in p:
            p['indices'] = acc_map[p['indices']]
    mesh_new.append(nm)
mesh_map = {}
j = 0
for k in range(len(J['meshes'])):
    if k != mi:
        mesh_map[k] = j
        j += 1
meta = {}
new_nodes = []
for name, sel in ((KEEP, ~mask), (TAKE, mask)):
    tris = idx[sel]
    uv = np.unique(tris)
    remap = -np.ones(len(P), dtype=np.int64)
    remap[uv] = np.arange(len(uv))
    Pw = P[uv]
    mn, mx = Pw.min(0), Pw.max(0)
    c = (mn + mx) / 2
    prim = {'attributes': {}, 'mode': pr.get('mode', 4)}
    if 'material' in pr:
        prim['material'] = pr['material']
    for kk, arr in attrs.items():
        sub = arr[uv]
        if kk == 'POSITION':
            sub = (Pw - c).astype(np.float32)
        prim['attributes'][kk] = add_acc(sub, CTYPE.get(sub.dtype, 5126), TYP[sub.shape[1]], 34962, minmax=(kk == 'POSITION'))
    ii = remap[tris].reshape(-1)
    ii = ii.astype(np.uint16 if len(uv) < 65535 else np.uint32).reshape(-1, 1)
    prim['indices'] = add_acc(ii, CTYPE[ii.dtype], 'SCALAR', 34963)
    mesh_new.append({'name': name, 'primitives': [prim]})
    new_nodes.append({'name': name, 'mesh': len(mesh_new) - 1, 'translation': [float(v) for v in c]})
    meta[name.split('__')[1]] = (c, mx - mn, len(tris))
# 节点：去掉 Body_1，接上两块新的（挂在根节点下）
nodes = []
node_map = {}
for k, n in enumerate(J['nodes']):
    if k == ni:
        continue
    nn = dict(n)
    if 'mesh' in nn:
        nn['mesh'] = mesh_map[nn['mesh']]
    node_map[k] = len(nodes)
    nodes.append(nn)
for nn in nodes:
    if 'children' in nn:
        nn['children'] = [node_map[c] for c in nn['children'] if c != ni]
root = next(k for k, n in enumerate(J['nodes']) if ni in n.get('children', []))
for nn in new_nodes:
    nodes.append(nn)
    nodes[node_map[root]]['children'].append(len(nodes) - 1)
J['nodes'], J['meshes'], J['accessors'], J['bufferViews'] = nodes, mesh_new, acc_new, bv_new
for sc in J.get('scenes', []):
    sc['nodes'] = [node_map[n] for n in sc['nodes']]
pad4()
J['buffers'] = [{'byteLength': len(out)}]
js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
while len(js) % 4:
    js += b' '
glb = bytearray(b'glTF' + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(out)))
glb += struct.pack('<I4s', len(js), b'JSON') + js
glb += struct.pack('<I4s', len(out), b'BIN\x00') + out
open(DST, 'wb').write(glb)
print('写好了 %s（%d 字节，原来 %d）' % (DST, len(glb), len(b)))
for k, (c, s, n) in meta.items():
    print('    %s = { c = { %.3f, %.3f, %.3f }, g = "%s", s = { %.3f, %.3f, %.3f } },   -- %d 个三角形' % (k, c[0], c[1], c[2], 'Gun' if k.startswith('Gun') else 'Body', s[0], s[1], s[2], n))
