# 写实车图打包（用户 11-25「主页和科技树的载具图用实拍图吧 然后角度要像战雷那样」）：
#   tools/models/vehicons.mjs 的 SET=photo 拍的 pic_veh_<模型>.png / pic_air_<模型>.png（960 × 480，透明背景）
#   → 缩到 W × H（带透明度一起缩：先预乘）、每张自己的 255 色调色板（带透明度）、透明像素连成串只记个数 → src/ReplicatedStorage/VehPics.lua
#   型号 → 图：照 vehicons.mjs 里的 GLB（地面车）、AIR（飞机、直升机）两张表
#   python3 -I tools/models/vehpics.py <图目录> [W H] [--merge]
#     --merge：只加 / 换图目录里有的图，VehPics.lua 里原来别的图原样留着（原图 PNG 不在手边时补几张用）
import sys, os, re, base64, glob
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
MERGE = '--merge' in sys.argv
argv = [a for a in sys.argv[1:] if a != '--merge']
src = argv[0]
W = int(argv[1]) if len(argv) > 1 else 240
H = int(argv[2]) if len(argv) > 2 else 120

mjs = open(os.path.join(HERE, 'vehicons.mjs'), encoding='utf-8').read()
def table(name):
    m = re.search(r'const ' + name + r' = \{(.*?)\};', mjs, re.S)
    return dict(re.findall(r"(\w+): '([\w]+)'", m.group(1))) if m else {}
GLB, AIR = table('GLB'), table('AIR')

def encode(path):
    im = Image.open(path).convert('RGBA')
    im = im.convert('RGBa').resize((W, H), Image.LANCZOS).convert('RGBA')   # 预乘以后再缩：边上不起黑边
    q = im.quantize(colors=255, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    pal = q.getpalette(rawmode='RGBA')[:255 * 4]
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
        if alpha[i] < 8:
            run += 1
            continue
        flush()
        out.append(idx[i] + 1)
    flush()
    return base64.b64encode(bytes(pal)).decode(), base64.b64encode(bytes(out)).decode()

pics = {}
if MERGE:   # 原来 VehPics.lua 里的图（已经编好码）先放进来，图目录里有同名的再换掉
    old = open(os.path.join(ROOT, 'src', 'ReplicatedStorage', 'VehPics.lua'), encoding='utf-8').read()
    for name, p_, d_ in re.findall(r'\n    (\w+) = \{ p = "([^"]*)", d = "([^"]*)" \},', old):
        pics[name] = (p_, d_)
for f in sorted(glob.glob(os.path.join(src, 'pic_*.png'))):
    name = os.path.basename(f)[4:-4]   # veh_m1a2dc / air_ah64
    pics[name] = encode(f)
alias_veh = {k: 'veh_' + v for k, v in GLB.items() if 'veh_' + v in pics}
alias_air = {k: 'air_' + v for k, v in AIR.items() if 'air_' + v in pics}
L = ['-- 自动生成（tools/models/vehpics.py），别手改：科技树、机库阵容卡上的写实车图（用户 11-25「主页和科技树的载具图用实拍图吧 然后角度要像战雷那样」）——',
     '--   原模型自己的贴图、PBR 材质，从左前方三分之四、俯视约 20° 拍（车头朝画面左下，同战雷科技树），透明背景；',
     '--   pics[图] = { p = 调色板（base64，每色 RGBA 4 字节，第 i 色是索引 i）, d = 像素（base64：0 后面一个字节 = 连续几个透明像素，否则 = 调色板第几色）}',
     '--   veh / air：VehDefs / AirDefs 的型号 → 图（同族的型号共用一个模型、一张图）；客户端 HudArt.lua G.vehPic 解成 EditableImage',
     'return {', '  w = %d, h = %d,' % (W, H), '  pics = {']
for name, (p, d) in pics.items():
    L.append('    %s = { p = "%s", d = "%s" },' % (name, p, d))
L.append('  },')
L.append('  veh = { ' + ', '.join('%s = "%s"' % kv for kv in sorted(alias_veh.items())) + ' },')
L.append('  air = { ' + ', '.join('%s = "%s"' % kv for kv in sorted(alias_air.items())) + ' },')
L.append('}')
dst = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'VehPics.lua')
open(dst, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('%d 张图，%d 个地面车型号、%d 个飞机型号 → %s（%.1f KB）' % (len(pics), len(alias_veh), len(alias_air), dst, os.path.getsize(dst) / 1024))
