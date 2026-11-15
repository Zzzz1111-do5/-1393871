# 把 map_export.luau 导出的高度画成图（看岛的形状、据点、海滩、舰队位置）：python3 -I tools/test/map_png.py <map.bin> <out.png> [裁剪：x0 z0 x1 z1]
import json, struct, sys, math
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
meta = json.load(open(src + '.json'))
n, step, R = meta['n'], meta['step'], meta['R']
raw = open(src, 'rb').read()
hs = struct.unpack('<%df' % (n * n), raw)
mat = open(src + '.mat', 'rb').read()
COL = {1: (222, 205, 150), 2: (128, 120, 110), 3: (98, 98, 105), 4: (125, 98, 70), 5: (70, 120, 55), 6: (95, 145, 70), 9: (255, 0, 255)}
img = Image.new('RGB', (n, n))
px = img.load()
for j in range(n):
    for i in range(n):
        y = hs[j * n + i]
        if y <= 0.3:
            d = min(1, -y / 12)
            px[i, j] = (int(90 - 60 * d), int(185 - 95 * d), int(205 - 60 * d))
            continue
        # 简单的山体阴影：西北来光
        yl = hs[j * n + max(0, i - 1)]; yu = hs[max(0, j - 1) * n + i]
        sh = max(0.55, min(1.3, 1 + ((y - yl) + (y - yu)) / step * 0.9))
        c = COL.get(mat[j * n + i], (255, 0, 255))
        k = sh * (0.85 + 0.35 * min(1, y / 250))
        px[i, j] = tuple(max(0, min(255, int(v * k))) for v in c)
dr = ImageDraw.Draw(img)
def P(x, z): return ((x + R) / step, (z + R) / step)
for k, x, z, y in meta['flat']:
    a, b = P(x, z); dr.rectangle([a - 2, b - 2, a + 2, b + 2], outline=(255, 255, 255)); dr.text((a + 4, b - 6), k, fill=(255, 255, 255))
for pid, x, z, y in meta['points']:
    a, b = P(x, z); r = 70 / step; dr.ellipse([a - r, b - r, a + r, b + r], outline=(255, 60, 60), width=2); dr.text((a - 3, b - 6), pid, fill=(255, 255, 0))
for bid, x0, x1, z in meta['beaches']:
    a, b = P(x0, z); c, d = P(x1, z); dr.line([a, b, c, d], fill=(255, 0, 200), width=3); dr.text((a, b + 4), bid, fill=(255, 255, 255))
for kind, x, z in meta['fleet']:
    a, b = P(x, z); dr.rectangle([a - 6, b - 2, a + 6, b + 2], fill=(60, 60, 60)); dr.text((a - 10, b + 4), kind, fill=(255, 255, 255))
if len(sys.argv) > 6:
    x0, z0, x1, z1 = map(float, sys.argv[3:7]); a, b = P(x0, z0); c, d = P(x1, z1)
    img = img.crop((int(a), int(b), int(c), int(d)))
img.save(out)
print(out, img.size)
