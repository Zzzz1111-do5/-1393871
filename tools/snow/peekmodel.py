# 看一个山体模型：俯视高度图（晕渲）+ 俯视贴图 + 边缘一圈的高度（python3 -I tools/snow/peekmodel.py <scene.gltf> <输出前缀> [格数]）
import sys, os, json
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltfio, raster  # noqa: E402
Image.MAX_IMAGE_PIXELS = None
path, out = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 512
prims, mats = gltfio.load(path)
P = np.concatenate([p['pos'] for p in prims])
mn, mx = P.min(0), P.max(0)
size = mx - mn
cell = max(size[0], size[2]) / N
nx, nz = int(np.ceil(size[0] / cell)), int(np.ceil(size[2] / cell))
Hall = np.full((nz, nx), -np.inf)
COL = np.zeros((nz, nx, 3))
texcache = {}
for p in prims:
    H, TI, BC = raster.raster(p['pos'], p['idx'], mn[0], mn[2], cell, nx, nz)
    up = H > Hall
    Hall = np.where(up, H, Hall)
    m = mats[p['mat']] if p['mat'] is not None and p['mat'] < len(mats) else None
    if m and m['base'] and p['uv'] is not None and up.any():
        if m['base'] not in texcache:
            im = Image.open(m['base']).convert('RGB')
            if max(im.size) > 4096:
                im = im.resize((4096, 4096))
            texcache[m['base']] = np.asarray(im).astype(np.float32)
        ti = TI[up]
        w = BC[up]
        tri = p['idx'][ti]
        uv = p['uv'][tri[:, 0]] * w[:, 0:1] + p['uv'][tri[:, 1]] * w[:, 1:2] + p['uv'][tri[:, 2]] * w[:, 2:3]
        COL[up] = raster.sample_tex(texcache[m['base']], uv)
    elif up.any():
        COL[up] = 150
cover = np.isfinite(Hall)
H = np.where(cover, Hall, mn[1])
# 晕渲
gx = np.gradient(H, axis=1) / cell
gz = np.gradient(H, axis=0) / cell
nrm = np.stack([-gx, np.ones_like(gx), -gz], -1)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
L = np.array([-0.5, 0.75, -0.45]); L /= np.linalg.norm(L)
sh = np.clip(nrm @ L, 0, 1)
hs = (60 + 195 * sh)
hs[~cover] = 30
Image.fromarray(hs.astype(np.uint8)).save(out + '_hs.png')
tex = np.clip(COL * (0.55 + 0.6 * sh[..., None]), 0, 255)
tex[~cover] = 40
Image.fromarray(tex.astype(np.uint8)).save(out + '_tex.png')
# 边缘一圈：每边的高度（离底面多高），看哪边低（朝外 / 埋进别的山）
def edge(a):
    v = a[np.isfinite(a)]
    return [round(float(np.percentile(v, q) - mn[1]), 3) for q in (10, 50, 90)] if len(v) else None
info = dict(size=[round(float(s), 4) for s in size], min=[round(float(v), 4) for v in mn], max=[round(float(v), 4) for v in mx],
            tris=int(sum(len(p['idx']) for p in prims)), cover=round(float(cover.mean()), 3),
            edges=dict(xmin=edge(Hall[:, :3].max(1)), xmax=edge(Hall[:, -3:].max(1)), zmin=edge(Hall[:3, :].max(0)), zmax=edge(Hall[-3:, :].max(0))),
            hpct=[round(float(np.percentile(H[cover] - mn[1], q)), 3) for q in (5, 25, 50, 75, 95, 100)])
print(json.dumps(info, ensure_ascii=False))
np.save(out + '_h.npy', np.where(cover, Hall - mn[1], np.nan).astype(np.float32))
