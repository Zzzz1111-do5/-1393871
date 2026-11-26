# 钢城（MapCity.lua）的俯视图：python3 -I tools/map/citypng.py <city.json> <out.png> [范围: full | city]
#   city.json 是 tools/mock/citylayout.lua out=... 写的（路、楼、树、据点、两边基地、铁路）；full 画到两边基地，city 只画城区
import json, sys
from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
D = json.load(open(src))
if mode == 'city':
    X0, X1, Z0, Z1, PX = -3700, 3700, -3700, 3700, 1600
else:
    X0, X1, Z0, Z1, PX = -5000, 5000, -8600, 8600, 1400
W = PX
H = int(PX * (Z1 - Z0) / (X1 - X0))
k = W / (X1 - X0)
img = Image.new('RGB', (W, H), (78, 104, 56))
d = ImageDraw.Draw(img)


def P(x, z): return ((x - X0) * k, (z - Z0) * k)


# 城区人行道、公园、郊区
d.rectangle([P(-3072, -3072), P(3072, 3072)], fill=(140, 138, 132))
d.rectangle([P(-3072, -512), P(-2048, 512)], fill=(86, 118, 60))
d.rectangle([P(2048, -3072), P(2560, 3072)], fill=(110, 96, 76))
# 基地、跑道
for b in D['bases']:
    side, x0, z0, x1, z1, ax, az, L, wid = b
    d.rectangle([P(x0, z0), P(x1, z1)], fill=(112, 98, 76), outline=(60, 60, 60))
    d.rectangle([P(ax - L / 2, az - wid / 2), P(ax + L / 2, az + wid / 2)], fill=(44, 46, 50))
# 铁路
rp = D['rail']
for i in range(len(rp) - 1):
    d.line([P(*rp[i]), P(*rp[i + 1])], fill=(70, 60, 56), width=max(2, int(150 * k)))
# 路
for s in D['segs']:
    ax, az, bx, bz, w, kind = s
    col = (112, 96, 72) if kind.startswith('lane') else (50, 52, 56)
    d.line([P(ax, az), P(bx, bz)], fill=col, width=max(1, int(w * k)))
d.rectangle([P(-300, -300), P(300, 300)], fill=(150, 142, 130))
# 树
for t in D['trees']:
    x, z, s = t
    r = max(1, 12 * s * k)
    c = P(x, z)
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(46, 82, 40))
# 楼（越高越亮）
STY = {1: (170, 170, 164), 2: (206, 190, 158), 3: (150, 88, 66), 4: (200, 192, 174), 5: (96, 120, 140), 6: (112, 80, 66), 7: (230, 228, 220), 8: (200, 164, 100)}
for b in D['blds']:
    x, z, w, dd, h, st, kind = b
    c = STY.get(st, (170, 170, 164))
    sh = min(1.0, 0.65 + h / 260)
    col = tuple(int(v * sh) for v in c)
    if kind == 'wagon':
        col = (110, 60, 44)
    if kind == 'tvtower':
        col = (230, 80, 70)
    d.rectangle([P(x - w / 2, z - dd / 2), P(x + w / 2, z + dd / 2)], fill=col, outline=(40, 40, 40))
# 据点
for p in D['points']:
    pid, x, z = p
    c = P(x, z)
    r = 90 * k
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=(255, 220, 60), width=3)
    d.text((c[0] - 4, c[1] - 6), pid, fill=(255, 255, 255))
img.save(dst)
print('写好', dst, img.size)
