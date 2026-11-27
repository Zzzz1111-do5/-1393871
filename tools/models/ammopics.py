# 弹药栏写实弹种图打包（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）：
#   tools/models/ammopics_blender.py 渲的 <名字>.png（显示尺寸的 8 倍，透明背景）+ meta.json
#   → 缩到显示尺寸的 2 倍（先预乘再缩：边上不起黑边）、整体降饱和一成、
#     每张自己的 255 色调色板（带透明度）、透明像素连成串只记个数（同 vehpics.py 的编码，客户端 HudArt.lua 共用一套解法）；
#     带药筒伸出图外的那几张记在 fade 表里——左边 16 像素（1 倍）的渐隐由弹药栏的 UIGradient 做（烤进图里的话 255 色放不下
#     一整段透明度渐变，会一道一道的）
#   → src/ReplicatedStorage/AmmoPics.lua
#   python3 -I tools/models/ammopics.py <渲染目录>
#   型号 → 图：ammo 按 Ballistics.AMMO 的键（弹种）、w 按 VehDefs.W 的键（机枪、机炮、导弹……）、tool 按弹药栏的工具格
import base64, json, os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SRC = sys.argv[1]
K = 2            # 图是显示尺寸的几倍
DESAT = 0.10     # 降饱和

meta = json.load(open(os.path.join(SRC, 'meta.json'), encoding='utf-8'))
TOOLS = ('smoke', 'fix', 'ext', 'bino', 'arty', 'scout')
W_ALIAS = {'ac30aa': 'ac30'}   # 同一种弹（2A42 / 2A38 都打 30×165）


def keys_of(path, pat):
    txt = open(os.path.join(ROOT, path), encoding='utf-8').read()
    return set(re.findall(pat, txt))


AMMO_KEYS = keys_of('src/ReplicatedStorage/Ballistics.lua', r'\n  (\w+) = \{ cls = ')
W_KEYS = keys_of('src/ReplicatedStorage/VehDefs.lua', r'\n  (\w+) = \{ kind = ')


def encode(path, m):
    W, H = m['w'] * K, m['h'] * K
    im = Image.open(path).convert('RGBA')
    im = im.convert('RGBa').resize((W, H), Image.LANCZOS)   # 预乘以后再缩：边上不起黑边
    px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            l = 0.299 * r + 0.587 * g + 0.114 * b
            px[x, y] = (int(r + (l - r) * DESAT + 0.5), int(g + (l - g) * DESAT + 0.5), int(b + (l - b) * DESAT + 0.5), a)
    im = im.convert('RGBA')
    q = im.quantize(colors=255, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    pal = q.getpalette(rawmode='RGBA')[:255 * 4]
    pal += [0] * (255 * 4 - len(pal))
    idx = q.tobytes()
    alpha = im.getchannel('A').tobytes()
    out, run = bytearray(), 0

    def flush():
        nonlocal run
        while run > 0:
            n = min(run, 255)
            out.extend((0, n))
            run -= n
    for i in range(W * H):
        if alpha[i] < 6:
            run += 1
            continue
        flush()
        out.append(idx[i] + 1)
    flush()
    return W, H, base64.b64encode(bytes(pal)).decode(), base64.b64encode(bytes(out)).decode()


pics = {}
for name in sorted(meta):
    p = os.path.join(SRC, name + '.png')
    if os.path.exists(p):
        pics[name] = encode(p, meta[name])
ammo = {k: k for k in sorted(AMMO_KEYS) if k in pics}
w = {k: W_ALIAS.get(k, k) for k in sorted(W_KEYS) if W_ALIAS.get(k, k) in pics}
tool = {k: k for k in TOOLS if k in pics}
fade = sorted(k for k in pics if meta[k].get('cut'))
miss = sorted(k for k in AMMO_KEYS if k not in pics)
L = ['-- 自动生成（tools/models/ammopics.py），别手改：弹药栏的写实弹种图（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）——',
     '--   Blender 按真弹的结构建模、照实物涂装渲的（tools/models/ammopics_blender.py）：横放、弹头朝右、略俯 6°，同一口径的弹一个毫米 → 像素比例；',
     '--   显示尺寸的 %d 倍：弹种 / 机枪格的图 92 × 34（格子 96 × 60 里 x 0～92、y 12～46）、工具格 56 × 34；' % K,
     '--   fade：药筒（太长的导弹 / 火箭）伸出图外的那几张，弹药栏给它左边 16 像素加 UIGradient 渐隐（不烤进图里：255 色放不下透明度渐变）',
     '--   重新生成：/opt/blender/blender -b --factory-startup -P tools/models/ammopics_blender.py -- <目录>',
     '--            python3 -I tools/models/ammopics.py <目录>',
     '--   pics[图] = { w, h, p = 调色板（base64，每色 RGBA 4 字节，第 i 色是索引 i）, d = 像素（base64：0 后面一个字节 = 连续几个透明像素，否则 = 调色板第几色）}',
     '--   ammo：Ballistics.AMMO 的键 → 图；w：VehDefs.W 的键 → 图；tool：弹药栏工具格 → 图。客户端 HudArt.lua G.ammoPic 解成 EditableImage',
     'return {', '  scale = %d,' % K, '  pics = {']
for name, (W, H, p, d) in pics.items():
    L.append('    %s = { w = %d, h = %d, p = "%s", d = "%s" },' % (name, W, H, p, d))
L.append('  },')
for tb, dd in (('ammo', ammo), ('w', w), ('tool', tool)):
    L.append('  %s = { ' % tb + ', '.join('%s = "%s"' % kv for kv in sorted(dd.items())) + ' },')
L.append('  fade = { ' + ', '.join('%s = true' % k for k in fade) + ' },')
L.append('}')
dst = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'AmmoPics.lua')
open(dst, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('%d 张图（弹种 %d、武器 %d、工具 %d）→ %s（%.1f KB）' % (len(pics), len(ammo), len(w), len(tool), dst, os.path.getsize(dst) / 1024))
if miss:
    print('还没有图的弹种：', ', '.join(miss))
