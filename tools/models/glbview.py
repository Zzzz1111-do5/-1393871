# 原车模型的正交预览（看窗户、舱盖、隔舱在哪，量坐标用）：按贴图上色，带格子坐标（1 格一条细线、每 2 格标数字）
#   用法（仓库根目录）：python3 -I tools/models/glbview.py models/veh/hmmwv.glb <输出前缀> [px=每格像素 40] [views=side,top,front,rear,left]
#     [only=Body_4,Body_6 只画这几块] [hide=W 名字以此开头的块不画] [clip=x0,x1,y0,y1,z0,z1 只画这个盒子里的三角形（剖开看）]
#   坐标同 ImportedMeta：格，原点车底中心，X 右、Y 上、−Z 朝前
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
import glbio

args = [a for a in sys.argv[1:] if '=' not in a]
opt = dict(a.split('=', 1) for a in sys.argv[1:] if '=' in a)
SRC, OUT = args[0], args[1]
PX = float(opt.get('px', 40))
VIEWS = opt.get('views', 'side,top,front,rear').split(',')
ONLY = set(opt['only'].split(',')) if 'only' in opt else None
HIDE = opt['hide'].split(',') if 'hide' in opt else []
CLIP = [float(x) for x in opt['clip'].split(',')] if 'clip' in opt else None

J, BIN = glbio.read_glb(SRC)
imgs = glbio.images(J, BIN)
tris, cols, names = [], [], []
for m in glbio.meshes(J, BIN):
    pn = glbio.part_name(m.node)
    if ONLY and pn not in ONLY:
        continue
    if any(pn.startswith(h) for h in HIDE):
        continue
    T = m.P[m.idx]
    c, a = glbio.tri_colors(J, imgs, m)
    if CLIP:
        ctr = T.mean(axis=1)
        k = (ctr[:, 0] >= CLIP[0]) & (ctr[:, 0] <= CLIP[1]) & (ctr[:, 1] >= CLIP[2]) & (ctr[:, 1] <= CLIP[3]) & (ctr[:, 2] >= CLIP[4]) & (ctr[:, 2] <= CLIP[5])
        T, c, a = T[k], c[k], a[k]
    tris.append(T)
    cols.append(np.concatenate([c, a[:, None]], axis=1))
    names += [pn] * len(T)
T = np.concatenate(tris)
C = np.concatenate(cols)
lo, hi = T.reshape(-1, 3).min(0), T.reshape(-1, 3).max(0)
print('包围盒 x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f]，%d 个三角形' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], len(T)))

# 视图：(水平轴, 竖直轴, 看的方向——深度轴和符号)；屏幕右 = 水平轴正向
VIEW = {
    'side': (2, 1, (0, -1)),    # 从右边（+X）往左看：车头（−Z）在左边
    'left': (2, 1, (0, 1)),     # 从左边看（水平轴翻过来画）
    'top': (0, 2, (1, -1)),     # 从上往下看：车头朝上
    'front': (0, 1, (2, 1)),    # 从车头前面往后看（屏幕右 = 车的左边，翻过来画成车的右边在右）
    'rear': (0, 1, (2, -1)),
}
N = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
L = np.array([0.35, 0.8, -0.45])
L /= np.linalg.norm(L)
shade = 0.45 + 0.55 * np.abs(N @ L)
for vname in VIEWS:
    hx, vy, (dax, dsg) = VIEW[vname]
    flipH = vname in ('left', 'front')
    if vname == 'top':
        flipV = True    # 车头（−Z）朝上
    else:
        flipV = False
    h0, h1 = lo[hx], hi[hx]
    v0, v1 = lo[vy], hi[vy]
    if vname == 'top':
        v0, v1 = lo[2], hi[2]
    W = int((h1 - h0) * PX) + 120
    H = int((v1 - v0) * PX) + 120
    img = Image.new('RGB', (W, H), (236, 238, 240))
    dr = ImageDraw.Draw(img)

    def sx(h):
        return 60 + ((h1 - h) if flipH else (h - h0)) * PX

    def sy(v):
        return 60 + ((v - v0) if flipV else (v1 - v)) * PX
    # 格子
    for g in range(int(np.floor(h0)), int(np.ceil(h1)) + 1):
        x = sx(g)
        dr.line([(x, 40), (x, H - 40)], fill=(205, 208, 212) if g % 2 else (170, 175, 182))
        if g % 2 == 0:
            dr.text((x - 6, 22), str(g), fill=(60, 60, 60))
            dr.text((x - 6, H - 30), str(g), fill=(60, 60, 60))
    for g in range(int(np.floor(v0)), int(np.ceil(v1)) + 1):
        y = sy(g)
        dr.line([(40, y), (W - 40, y)], fill=(205, 208, 212) if g % 2 else (170, 175, 182))
        if g % 2 == 0:
            dr.text((8, y - 6), str(g), fill=(60, 60, 60))
            dr.text((W - 34, y - 6), str(g), fill=(60, 60, 60))
    depth = T[:, :, dax].mean(axis=1) * dsg
    order = np.argsort(-depth)   # 远的先画
    vax = 2 if vname == 'top' else vy
    for i in order:
        t = T[i]
        pts = [(sx(p[hx]), sy(p[vax])) for p in t]
        c = C[i]
        rgb = np.clip((c[:3] * shade[i]) ** (1 / 2.2), 0, 1)
        if c[3] < 0.99:   # 半透明（玻璃）：画成青色描边方便认
            col = (int(rgb[0] * 120 + 20), int(rgb[1] * 120 + 120), int(rgb[2] * 120 + 135))
        else:
            col = tuple(int(x * 255) for x in rgb)
        dr.polygon(pts, fill=col)
    img.save('%s_%s.png' % (OUT, vname))
    print('写好了 %s_%s.png（%d × %d）' % (OUT, vname, W, H))
