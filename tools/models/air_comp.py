# 列出原模型机体的连通块（网页版坐标：x 前、y 左、z 上，米）：舵面、座舱盖、舱门多半是单独的一块——量 air2glb.py 的 SURF 表用
#   用法：python3 -I tools/models/air_comp.py <网页版仓库目录> <模型键> [最多列几块]
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
import air2glb as A   # noqa: E402
B.WEB = sys.argv[1]
key = sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 80
meta, binb, _ = B.load(key)
st = meta.get('st', 8)
vb0, vbn = meta['vb']
VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st).astype(np.float64)
ib0, ibn = meta['ib']
IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0).astype(np.int64)
if key in A.FLIP:
    VB = A.flip(meta, VB)
tris, mats = [], []
for mi, pi, s0, cnt in meta['lod'][0]:
    if pi >= 0 and meta['parts'][pi].get('n') in ('gear', 'rotor', 'trotor'):
        continue
    T = IB[s0:s0 + cnt].reshape(-1, 3)
    tris.append(T)
    mats += [mi] * len(T)
T = np.concatenate(tris)
M = np.array(mats)
P = VB[:, 0:3]
cid = A.components(P, T)
rows = []
for r in np.unique(cid):
    sel = cid == r
    q = P[T[sel]].reshape(-1, 3)
    lo, hi = q.min(0), q.max(0)
    ms = sorted(set(M[sel].tolist()))
    rows.append((lo, hi, int(sel.sum()), ms))
rows.sort(key=lambda r: -(r[1] - r[0]).prod() ** (1 / 3))
print('%s：%d 块（材质 %s）' % (key, len(rows), ', '.join('%d:%s' % (i, m.get('n')) for i, m in enumerate(meta['mats']))))
for lo, hi, n, ms in rows[:N]:
    print('  x %6.2f..%6.2f  y %6.2f..%6.2f  z %5.2f..%5.2f  △%5d  材质 %s' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], n, ms))
