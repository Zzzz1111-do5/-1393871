# 弹药栏写实弹种图打包（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）：
#   tools/models/ammopics_blender.py 渲的 <名字>.png（显示尺寸的 8 倍，透明背景）+ meta.json
#   → 打两套：显示尺寸的 2 倍（pics）、1 倍（pics1）——游戏里按格子实际有几个像素选（WtTank：低分屏的小格子用 1 倍，
#     免得 2 倍图缩 2.4 倍时细杆断线、字成噪点；1080p、Retina 用 2 倍），都从 8 倍原图直接缩（先预乘再缩：边上不起黑边）；
#   → 透明边外扩（11-27 美术审查）：量化之前把边缘的颜色往透明区外扩 BLEED 圈（透明度还是 0），
#     解码（HudArt.lua picDecode）时透明像素也写这个颜色、不写黑——游戏里图缩小显示时双线性插值不会把边混暗（浅色弹托在亮地面上一圈黑边）；
#   → 每张自己的调色板（带透明度；2 倍那套 254 色、1 倍那套 COLORS1 色），透明像素连成串只记个数（同 vehpics.py 的编码，HudArt.lua 共用一套解法）；
#     外扩的那几圈当普通像素记（调色板里透明度 0 的颜色，单独一小份：不跟看得见的颜色混着量化）；
#     比车图多一种码：255 + 个数 = 上一个像素再重复几个（f = "r"）——横放的弹顺着弹轴一行几乎同色，两套图加起来比只打一套 2 倍图的原来还小
#   → 不再整张降饱和（原来统一降一成，黄铜被洗成土黄）：非金属在 Blender 材质里降，金属不降
#   → 带药筒伸出图外的那几张记在 fade 表里——左边 16 像素（1 倍）「先压暗、后透明」由弹药栏的 UIGradient 做（烤进图里的话 255 色放不下
#     一整段透明度渐变，会一道一道的）
#   → 1 倍那套不写模板字（11-27 美术审查第二轮：720p / 768p 下字高约 2.5 像素，成了 1 像素的竖点）：渲染脚本给有字的另出一张
#     <名字>_nt.png（不带字），1 倍那套从它缩；meta 里 extra 的（125 穿甲弹的装填形态，留给配弹界面）不打包
#   → src/ReplicatedStorage/AmmoPics.lua
#   python3 -I tools/models/ammopics.py <渲染目录> [colors1=96] [bleed=2]
#   型号 → 图：ammo 按 Ballistics.AMMO 的键（弹种）、w 按 VehDefs.W 的键（机枪、机炮、导弹……）、tool 按弹药栏的工具格
import base64, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SRC = sys.argv[1]
OPT = dict(a.split('=', 1) for a in sys.argv[2:] if '=' in a)
COLORS2 = int(OPT.get('colors2', 254))   # 2 倍那套每张几色（≤ 254：255 留给「重复上一色」）
COLORS1 = int(OPT.get('colors1', 96))    # 1 倍那套：图小，色数少一些（调色板也是数据）
BLEED = int(OPT.get('bleed', 2))         # 透明边外扩几圈
A_MIN = 6                                # 不透明度低于这个当全透明

meta = json.load(open(os.path.join(SRC, 'meta.json'), encoding='utf-8'))
TOOLS = ('smoke', 'fix', 'ext', 'bino', 'arty', 'scout')
W_ALIAS = {'ac30aa': 'ac30'}   # 同一种弹（2A42 / 2A38 都打 30×165）


def keys_of(path, pat):
    txt = open(os.path.join(ROOT, path), encoding='utf-8').read()
    return set(re.findall(pat, txt))


AMMO_KEYS = keys_of('src/ReplicatedStorage/Ballistics.lua', r'\n  (\w+) = \{ cls = ')
W_KEYS = keys_of('src/ReplicatedStorage/VehDefs.lua', r'\n  (\w+) = \{ kind = ')


def shrink(im, W, H):
    """预乘以后再缩（边上不起黑边）→ numpy RGBA（不预乘）"""
    a = np.asarray(im.convert('RGBa').resize((W, H), Image.LANCZOS)).astype(np.float64)
    al = a[:, :, 3:4]
    rgb = np.where(al > 0, a[:, :, :3] * 255.0 / np.maximum(al, 1), 0)
    return np.dstack([rgb, al]).clip(0, 255)


def bleed(arr, n):
    """透明区外扩 n 圈：每圈把还没颜色的透明像素填成四邻里已有颜色的平均（不透明度不动，还是 0）；返回 (图, 外扩到的像素)"""
    H, W = arr.shape[:2]
    have = arr[:, :, 3] >= A_MIN
    rgb = arr[:, :, :3].copy()
    grown = np.zeros((H, W), bool)
    for _ in range(n):
        acc = np.zeros((H, W, 3))
        cnt = np.zeros((H, W))
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.zeros((H, W), bool)
            col = np.zeros((H, W, 3))
            ys0, ys1 = max(0, dy), H + min(0, dy)
            xs0, xs1 = max(0, dx), W + min(0, dx)
            src[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] = have[ys0:ys1, xs0:xs1]
            col[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] = rgb[ys0:ys1, xs0:xs1]
            acc += col * src[:, :, None]
            cnt += src
        new = (~have) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        have = have | new
        grown |= new
    out = arr.copy()
    out[:, :, :3] = np.where(grown[:, :, None], rgb, arr[:, :, :3])
    return out, grown


def quant(px, colors, mode):
    """一串像素（N × 3 / 4）量化成 ≤ colors 色：返回（调色板 [(r, g, b, a)…]，每个像素的色号）"""
    n = len(px)
    if n == 0:
        return [], np.zeros(0, int)
    im = Image.fromarray(px.reshape(1, n, -1).astype('uint8'), mode)
    q = im.quantize(colors=max(1, min(colors, n)), method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    idx = np.asarray(q).reshape(-1).astype(int)
    raw = q.getpalette(rawmode='RGBA' if mode == 'RGBA' else 'RGB')
    step = 4 if mode == 'RGBA' else 3
    used = int(idx.max()) + 1
    pal = [tuple(raw[i * step:i * step + step]) + (() if step == 4 else (0,)) for i in range(used)]
    return pal, idx


def encode(arr, colors):
    """看得见的像素（不透明度 ≥ A_MIN）一份调色板；外扩出来的透明像素另一小份（透明度 0 的颜色，两份不混：
       混在一起量化的话，一色里既有不透明的又有透明的，平均出来半透明，边上会起一圈虚影）"""
    H, W = arr.shape[:2]
    vis = arr[:, :, 3] >= A_MIN
    arr, grown = bleed(arr, BLEED) if BLEED > 0 else (arr, np.zeros((H, W), bool))
    keep = vis | grown
    flat = arr.reshape(-1, 4).round().clip(0, 255)
    visf, grownf, keepf = vis.reshape(-1), grown.reshape(-1), keep.reshape(-1)
    nb = min(32, max(4, colors // 8)) if grownf.any() else 0   # 外扩色：几十色足够（只在缩小插值时混进边上）
    pal_v, idx_v = quant(flat[visf], colors - nb, 'RGBA')
    pal_b, idx_b = quant(flat[grownf][:, :3], nb, 'RGB') if nb else ([], np.zeros(0, int))
    pal = [c for e in pal_v for c in e] + [c for e in pal_b for c in e]
    idx = np.zeros(W * H, int)
    idx[visf] = idx_v
    idx[grownf] = idx_b + len(pal_v)
    out = bytearray()
    i, N = 0, W * H
    while i < N:
        if not keepf[i]:   # 一串透明的：0, 个数
            j = i
            while j < N and not keepf[j] and j - i < 255:
                j += 1
            out.extend((0, j - i))
            i = j
            continue
        out.append(int(idx[i]) + 1)
        j = i + 1          # 后面跟着同一色的：255, 再重复几个（≥ 2 个才值得）——横放的弹顺着弹轴一行一行几乎同色
        while j < N and keepf[j] and idx[j] == idx[i] and j - i - 1 < 255:
            j += 1
        if j - i - 1 >= 2:
            out.extend((255, j - i - 1))
            i = j
        else:
            i += 1
    return W, H, base64.b64encode(bytes(pal)).decode(), base64.b64encode(bytes(out)).decode()


pics2, pics1 = {}, {}
for name in sorted(meta):
    p = os.path.join(SRC, name + '.png')
    m = meta[name]
    if not os.path.exists(p) or m.get('extra'):   # extra：125 穿甲弹的装填形态（留给配弹界面），不进弹药栏
        continue
    im = Image.open(p).convert('RGBA')
    pics2[name] = encode(shrink(im, m['w'] * 2, m['h'] * 2), COLORS2)
    # 1 倍那套用不带模板字的那张（_nt.png）：1 倍下字只有 2.5 像素高，缩成 1 像素的竖点（11-27 美术审查第二轮）
    pnt = os.path.join(SRC, name + '_nt.png')
    im1 = Image.open(pnt).convert('RGBA') if (m.get('nt') and os.path.exists(pnt)) else im
    pics1[name] = encode(shrink(im1, m['w'], m['h']), COLORS1)
ammo = {k: k for k in sorted(AMMO_KEYS) if k in pics2}
w = {k: W_ALIAS.get(k, k) for k in sorted(W_KEYS) if W_ALIAS.get(k, k) in pics2}
tool = {k: k for k in TOOLS if k in pics2}
fade = sorted(k for k in pics2 if meta[k].get('cut'))
miss = sorted(k for k in AMMO_KEYS if k not in pics2)
L = ['-- 自动生成（tools/models/ammopics.py），别手改：弹药栏的写实弹种图（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）——',
     '--   Blender 按真弹的结构建模、照实物涂装渲的（tools/models/ammopics_blender.py）：横放、弹头朝右、略俯 6° 偏 10°，同一口径的弹一个毫米 → 像素比例；',
     '--   两套：pics 显示尺寸的 2 倍、pics1 显示尺寸的 1 倍（弹药栏按格子实际几个像素选；1 倍那套不写模板字）；弹种 / 机枪格的图 92 × 40（格子 96 × 60 里 x 0～92、y 10～50）、工具格 56 × 40；',
     '--   透明像素里外扩了 %d 圈边缘色（调色板里透明度 0 的颜色）：解码时照写，图缩小显示时边上不混黑；' % BLEED,
     '--   fade：药筒（太长的导弹 / 火箭）伸出图外的那几张，弹药栏给它左边 16 像素加 UIGradient「先压暗、后透明」（不烤进图里：255 色放不下透明度渐变）',
     '--   重新生成：/opt/blender/blender -b --factory-startup -P tools/models/ammopics_blender.py -- <目录>',
     '--            python3 -I tools/models/ammopics.py <目录>',
     '--   pics[图] = { w, h, f = "r", p = 调色板（base64，每色 RGBA 4 字节，第 i 色是索引 i，≤ 254 色）, d = 像素（base64：0 后面一个字节 = 连续几个透明像素；',
     '--     255 后面一个字节 = 上一个像素再重复几个；否则 = 调色板第几色）}',
     '--   ammo：Ballistics.AMMO 的键 → 图；w：VehDefs.W 的键 → 图；tool：弹药栏工具格 → 图。客户端 HudArt.lua G.ammoPic 解成 EditableImage',
     'return {', '  scale = 2,', '  pics = {']
for name, (W, H, p, d) in pics2.items():
    L.append('    %s = { w = %d, h = %d, f = "r", p = "%s", d = "%s" },' % (name, W, H, p, d))
L.append('  },')
L.append('  pics1 = {')
for name, (W, H, p, d) in pics1.items():
    L.append('    %s = { w = %d, h = %d, f = "r", p = "%s", d = "%s" },' % (name, W, H, p, d))
L.append('  },')
for tb, dd in (('ammo', ammo), ('w', w), ('tool', tool)):
    L.append('  %s = { ' % tb + ', '.join('%s = "%s"' % kv for kv in sorted(dd.items())) + ' },')
L.append('  fade = { ' + ', '.join('%s = true' % k for k in fade) + ' },')
L.append('}')
dst = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'AmmoPics.lua')
open(dst, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
sz2 = sum(len(p) + len(d) for (_, _, p, d) in pics2.values())
sz1 = sum(len(p) + len(d) for (_, _, p, d) in pics1.values())
print('%d 张图（弹种 %d、武器 %d、工具 %d）→ %s（%.1f KB：2 倍 %.1f KB、1 倍 %.1f KB）' % (
    len(pics2), len(ammo), len(w), len(tool), dst, os.path.getsize(dst) / 1024, sz2 / 1024, sz1 / 1024))
if miss:
    print('还没有图的弹种：', ', '.join(miss))
