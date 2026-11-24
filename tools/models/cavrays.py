# 挖好的内壁上量东西（用户 11-24 的 M1A2 指挥塔：井不是正八边形，每个方向离中心的距离不一样）：
#   从 (cx, y, cz) 往 8 个方向（正前 −Z 起、顺时针每 45°）对内壁打射线，打印每个高度 8 个方向的距离（格，模型坐标）
#   用法（仓库根目录）：python3 -I tools/models/cavrays.py <模型键> <块名> <cx> <cz> <y1,y2,…>
#   例：python3 -I tools/models/cavrays.py m1a2dc CavTurWall_1 1.43 1.06 6.6,6.7,6.8
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np, glbio, math
KEY, BLOCK = sys.argv[1], sys.argv[2]
J, BIN = glbio.read_glb(os.path.join(os.path.dirname(os.path.dirname(HERE)), 'models/veh/%s.glb' % KEY))
W = glbio.world_mats(J)
tris = []
for ni, n in enumerate(J['nodes']):
    if n.get('name') == 'V_%s__%s' % (KEY, BLOCK):
        for pr in J['meshes'][n['mesh']]['primitives']:
            P = glbio.accessor(J, BIN, pr['attributes']['POSITION'])
            Q = (np.c_[P, np.ones(len(P))] @ W[ni].T)[:, :3]
            I = glbio.accessor(J, BIN, pr['indices']).reshape(-1, 3)
            tris.append(Q[I])
T = np.concatenate(tris)
def ray(o, d):
    v0, v1, v2 = T[:, 0], T[:, 1], T[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-9
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    tv = o - v0
    u = (tv * p).sum(1) * inv
    q = np.cross(tv, e1)
    v = (q * d).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4)
    return t[hit].min() if hit.any() else None
cx, cz = float(sys.argv[3]), float(sys.argv[4])
for y in [float(a) for a in sys.argv[5].split(',')]:
    out = []
    for i in range(8):
        a = math.radians(i * 45)
        d = np.array([math.sin(a), 0, -math.cos(a)])
        r = ray(np.array([cx, y, cz]), d)
        out.append(None if r is None else round(float(r), 3))
    print('y', y, out)
