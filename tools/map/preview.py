# 路网 / 树林预览：读 tools/map/roads.lua（或 scenery 预览）写出的高度、路线，画成俯视图（山体阴影 + 路 + 工事 + 可选的树点）
# 用法：python3 -I tools/map/preview.py <目录>（目录里有 map_h.txt、map_roads.txt，可选 map_trees.txt）→ <目录>/map.png
import sys, os, math
from PIL import Image, ImageDraw
D = sys.argv[1]
with open(os.path.join(D, 'map_h.txt')) as f:
    x0, z0, S, nx, nz = map(int, f.readline().split())
    H = [list(map(float, f.readline().split())) for _ in range(nz)]
img = Image.new('RGB', (nx, nz))
px = img.load()
for k in range(nz):
    for i in range(nx):
        h = H[k][i]
        if h <= 0.3:
            c = (40, 90, 120) if h < -2 else (200, 190, 150)
        else:
            dx = (H[k][min(nx - 1, i + 1)] - H[k][max(0, i - 1)]) / (2 * S)
            dz = (H[k][min(nz - 1, k + 1)] - H[k][max(0, k - 1)]) / (2 * S)
            shade = max(0.35, min(1.25, 1 - (dx * 0.8 + dz * 0.6)))
            t = min(1, h / 220)
            base = (int(90 + 80 * t), int(130 + 40 * t), int(70 + 70 * t))
            c = tuple(min(255, int(v * shade)) for v in base)
        px[i, k] = c
img = img.resize((nx * 2, nz * 2))
dr = ImageDraw.Draw(img)
def P(x, z): return ((x - x0) / S * 2, (z - z0) / S * 2)
tf = os.path.join(D, 'map_trees.txt')
if os.path.exists(tf):
    cols = {'c': (20, 60, 25), 'd': (60, 110, 40), 'b': (90, 120, 60), 'f': (240, 220, 40), 'r': (150, 150, 150)}
    for line in open(tf):
        t, x, z = line.split()
        a, b = P(float(x), float(z))
        dr.point((a, b), fill=cols.get(t, (0, 0, 0)))
for line in open(os.path.join(D, 'map_roads.txt')):
    v = line.split()
    if v[0] == 'F':
        a, b = P(float(v[1]), float(v[2]))
        dr.rectangle((a - 3, b - 3, a + 3, b + 3), fill=(220, 40, 40))
        continue
    pts = [P(float(v[i]), float(v[i + 1])) for i in range(0, len(v), 2)]
    dr.line(pts, fill=(140, 100, 60), width=3)
img.save(os.path.join(D, 'map.png'))
print('写好了', os.path.join(D, 'map.png'), img.size)
