# 舱盖的高度：在原模型（models/veh/<键>.glb）上，按 HatchDefs 草表给的水平位置往下打射线，量车顶 / 炮塔顶在那里多高（格，模型坐标）
#   用法（仓库根目录）：python3 -I tools/models/hatchmeasure.py <键>[:hull] x,z [x,z ...]（:hull 只量车体，不看炮塔）
#     车尾的门 / 跳板：<键> rear:x,y —— 从车后面朝前打一条水平射线，量车尾那一面在 z 多少
#   输出每个点最上面那一层的高度（只看车体 Body / 炮塔 Turret 的块，不看炮管、天线细杆：细于 0.15 格的三角形带不算）
import sys, json, struct
import numpy as np
def load(path):
    b = open(path, 'rb').read()
    off = 12; J = BIN = None
    while off < len(b):
        ln, ty = struct.unpack_from('<II', b, off); off += 8
        ch = b[off:off + ln]; off += ln
        if ty == 0x4E4F534A: J = json.loads(ch)
        elif ty == 0x004E4942: BIN = ch
    CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
    NC = {'SCALAR': 1, 'VEC3': 3}
    def acc(i):
        a = J['accessors'][i]; bv = J['bufferViews'][a['bufferView']]
        n = NC[a['type']]; dt = CT[a['componentType']]
        o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        st = bv.get('byteStride', 0); cnt = a['count']; isz = np.dtype(dt).itemsize
        if st and st != n * isz:
            raw = np.frombuffer(BIN, dtype=np.uint8, count=st * cnt, offset=o).reshape(cnt, st)
            return raw[:, :n * isz].copy().view(dt).reshape(cnt, n)
        return np.frombuffer(BIN, dtype=dt, count=cnt * n, offset=o).reshape(cnt, n)
    def mat(nd):
        M = np.eye(4)
        if 'matrix' in nd: return np.array(nd['matrix'], dtype=np.float64).reshape(4, 4).T
        t = nd.get('translation', [0, 0, 0]); x, y, z, w = nd.get('rotation', [0, 0, 0, 1]); s = nd.get('scale', [1, 1, 1])
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M[:3, :3] = R * np.array(s)[None, :]; M[:3, 3] = t
        return M
    out = []
    def walk(i, P):
        nd = J['nodes'][i]; M = P @ mat(nd)
        if 'mesh' in nd:
            for pr in J['meshes'][nd['mesh']]['primitives']:
                pos = acc(pr['attributes']['POSITION']).astype(np.float64)
                idx = acc(pr['indices']).reshape(-1).astype(np.int64) if 'indices' in pr else np.arange(len(pos))
                wp = (M[:3, :3] @ pos.T).T + M[:3, 3]
                out.append((nd.get('name', ''), wp[idx.reshape(-1, 3)]))
        for c in nd.get('children', []): walk(c, M)
    for r in J['scenes'][J.get('scene', 0)]['nodes']: walk(r, np.eye(4))
    return out
key = sys.argv[1]
hullOnly = key.endswith(':hull')   # <键>:hull —— 只量车体（驾驶员舱盖在炮塔前伸的部分底下，往下打的射线先碰到炮塔）
if hullOnly: key = key[:-5]
prims = load(f'models/veh/{key}.glb')
T = []
for name, tri in prims:
    part = name.split('__')[-1]
    if part.startswith('Gun') or part.startswith('W'): continue   # 炮管、车轮不算
    if hullOnly and (part.startswith('Turret') or part.startswith('Rws')): continue
    T.append(tri)
T = np.concatenate(T)
v0, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
def top(x, z):
    o = np.array([x, 80.0, z]); d = np.array([0, -1.0, 0])
    p = np.cross(d, e2); det = (e1 * p).sum(1); ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0); s = o - v0
    u = (s * p).sum(1) * inv; q = np.cross(s, e1); v = (q * d).sum(1) * inv; t = (e2 * q).sum(1) * inv
    h = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    if not h.any(): return None
    ys = sorted(80 - t[h], reverse=True)
    return ys
def back(x, y):
    o = np.array([x, y, 200.0]); d = np.array([0, 0, -1.0])
    p = np.cross(d, e2); det = (e1 * p).sum(1); ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0); s = o - v0
    u = (s * p).sum(1) * inv; q = np.cross(s, e1); v = (q * d).sum(1) * inv; t = (e2 * q).sum(1) * inv
    h = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return round(float(200 - t[h].min()), 3) if h.any() else None
res = {}
for a in sys.argv[2:]:
    if a.startswith('rear:'):
        x, y = [float(v) for v in a[5:].split(',')]
        res[a] = { 'z': back(x, y) }
        continue
    x, z = [float(v) for v in a.split(',')]
    ys = top(x, z)
    # 一圈 5 个点取中位数（避开拉手、螺栓这些小凸起）
    ring = []
    for dx, dz in ((0, 0), (0.35, 0), (-0.35, 0), (0, 0.35), (0, -0.35)):
        yy = top(x + dx, z + dz)
        if yy: ring.append(yy[0])
    res[a] = { 'top': round(float(np.median(ring)), 3) if ring else None, 'layers': [round(float(y), 2) for y in (ys or [])[:4]] }
print(json.dumps(res, ensure_ascii=False))
