# 雪山的天空：用户 11-26 晚给的三个 Sketchfab 模型（都是 CC-BY 4.0）→ models/snow/sky.glb（七块贴图的载体）
#   · 「Night Sky Visible Spectrum Monochromatic」（commonfactory）：一个球，内面贴一张等距柱状的星空（银河）——切成天空盒的六个面（1024²）
#   · 「Ganymede (moon)」（SebastianSosnowski）：木卫三的球面贴图——画成一张正面的月亮圆盘（侧光，黑底：Roblox 的月亮贴图黑的地方不显示）
#   · 「The Sun」（tamminen）：一个橙色的球（没有贴图）——照它的颜色画太阳圆盘：中间白热、边缘发暗（临边昏暗）、外面一圈光晕
#   python3 -I tools/snow/sky.py <夜空 scene.gltf 目录> <木卫三目录> <太阳目录> <输出 sky.glb> [预览图]
#   Roblox 的天空盒（Sky.SkyboxFt / Bk / Lf / Rt / Up / Dn）只认上传过的图片：七张图各贴在一块薄片上（N_skyft__Body …、N_moontex__Body、N_suntex__Body），
#   Studio「导入 3D」时上传，游戏里（Client/SnowLook.lua）读出贴图编号设到 Sky 上。
#   天空盒的方向（Roblox 默认镜头朝 −Z）：Ft 朝 −Z、Bk +Z、Lf −X、Rt +X（侧面图片上方是天顶）；Up 图片下边接 Ft 上边、Dn 图片上边接 Ft 下边
import sys, os, json, struct, io
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
NS, MOON, SUN, OUT = sys.argv[1:5]
PREV = sys.argv[5] if len(sys.argv) > 5 else None
F = 1024

# ---------------------------------------------------------------- 星空 → 六个面
J = json.load(open(os.path.join(NS, 'scene.gltf')))
# 星空在发光贴图里（最大的那张）
best = None
for im in J['images']:
    p = os.path.join(NS, im['uri'])
    w, h = Image.open(p).size
    if best is None or w * h > best[1]:
        best = (p, w * h)
eq = np.asarray(Image.open(best[0]).convert('RGB')).astype(np.float32)
EH, EW = eq.shape[:2]
print('星空贴图', best[0], EW, 'x', EH)

FACES = {   # 面：(朝向 f, 图片右 r, 图片上 u)
    'ft': ((0, 0, -1), (1, 0, 0), (0, 1, 0)),
    'rt': ((1, 0, 0), (0, 0, 1), (0, 1, 0)),
    'bk': ((0, 0, 1), (-1, 0, 0), (0, 1, 0)),
    'lf': ((-1, 0, 0), (0, 0, -1), (0, 1, 0)),
    'up': ((0, 1, 0), (1, 0, 0), (0, 0, 1)),
    'dn': ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
}


def sample(dirs):
    """方向（N × 3，单位向量）→ 星空的颜色（双线性）"""
    x, y, z = dirs[:, 0], dirs[:, 1], dirs[:, 2]
    lon = np.arctan2(x, -z)
    lat = np.arcsin(np.clip(y, -1, 1))
    u = (0.5 + lon / (2 * np.pi)) * EW - 0.5
    v = (0.5 - lat / np.pi) * EH - 0.5
    u0 = np.floor(u).astype(int)
    v0 = np.clip(np.floor(v).astype(int), 0, EH - 2)
    fu, fv = (u - u0)[:, None], np.clip(v - v0, 0, 1)[:, None]
    u0 %= EW
    u1 = (u0 + 1) % EW
    c = eq[v0, u0] * (1 - fu) * (1 - fv) + eq[v0, u1] * fu * (1 - fv) + eq[v0 + 1, u0] * (1 - fu) * fv + eq[v0 + 1, u1] * fu * fv
    return c


faces = {}
s = (np.arange(F) + 0.5) / F * 2 - 1
ss, tt = np.meshgrid(s, -s)   # 图片第一行是上
for name, (f, r, u) in FACES.items():
    f, r, u = np.array(f, float), np.array(r, float), np.array(u, float)
    d = f[None, None, :] + ss[..., None] * r[None, None, :] + tt[..., None] * u[None, None, :]
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    # 每个像素按 2 × 2 超采样（等距柱状图 8192 宽，一个面 1024 像素对 90°：每像素约 2 个原像素）
    acc = np.zeros((F, F, 3), np.float32)
    for ox in (-0.25, 0.25):
        for oy in (-0.25, 0.25):
            dd = f[None, None, :] + (ss + ox * 2 / F)[..., None] * r[None, None, :] + (tt + oy * 2 / F)[..., None] * u[None, None, :]
            dd /= np.linalg.norm(dd, axis=2, keepdims=True)
            acc += sample(dd.reshape(-1, 3)).reshape(F, F, 3)
    img = np.clip(acc / 4 * 1.5, 0, 255).astype(np.uint8)   # 亮一点：游戏里的夜空还要隔着大气
    faces[name] = Image.fromarray(img, 'RGB')
    print('面', name, '平均亮度', round(float(img.mean()), 1))

# ---------------------------------------------------------------- 月亮：木卫三的球面贴图画成圆盘
mt = None
for fn in os.listdir(os.path.join(MOON, 'textures')):
    if 'baseColor' in fn:
        mt = np.asarray(Image.open(os.path.join(MOON, 'textures', fn)).convert('RGB')).astype(np.float32)
MH, MW = mt.shape[:2]
M = 512
yy, xx = np.mgrid[0:M, 0:M]
px = (xx + 0.5) / M * 2 - 1
py = 1 - (yy + 0.5) / M * 2
R0 = 0.92   # 圆盘半径（留一圈黑边）
rr = np.sqrt(px * px + py * py) / R0
inside = rr < 1
nz = np.sqrt(np.clip(1 - rr * rr, 0, 1))
nx, ny = px / R0, py / R0
lon = np.arctan2(nx, nz) + 0.6   # 转一点：正面不是贴图的接缝
lat = np.arcsin(np.clip(ny, -1, 1))
mu = ((0.5 + lon / (2 * np.pi)) % 1) * (MW - 1)
mv = (0.5 - lat / np.pi) * (MH - 1)
col = mt[mv.astype(int), mu.astype(int)]
L = np.array([-0.45, 0.25, 0.86])
L /= np.linalg.norm(L)
lam = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1) ** 0.8
col = col * (0.12 + 0.95 * lam)[..., None] * 1.1
edge = np.clip((1 - rr) * M * R0 / 2, 0, 1)   # 边缘抗锯齿
moon = np.clip(col * (inside * edge)[..., None], 0, 255).astype(np.uint8)
moon_img = Image.fromarray(moon, 'RGB')

# ---------------------------------------------------------------- 太阳：照模型的颜色画
Js = json.load(open(os.path.join(SUN, 'scene.gltf')))
sc = Js['materials'][0]['pbrMetallicRoughness'].get('baseColorFactor', [1, 0.43, 0.07, 1])[:3]
S = 512
yy, xx = np.mgrid[0:S, 0:S]
px = (xx + 0.5) / S * 2 - 1
py = 1 - (yy + 0.5) / S * 2
r = np.sqrt(px * px + py * py)
R1 = 0.36   # 日面
mu_ = np.sqrt(np.clip(1 - (r / R1) ** 2, 0, 1))
limb = 0.75 + 0.25 * mu_   # 临边昏暗（边上暗一点、颜色偏橙；暗多了像描了一圈边）
core = np.array([255, 250, 236], np.float32)
rim = np.array(sc, np.float32) * 255
k = ((1 - mu_) ** 2)[..., None]
disk = core[None, None, :] * (1 - k) + rim[None, None, :] * k
disk = disk * limb[..., None]
glow = np.exp(-np.clip(r - R1, 0, None) / 0.12)[..., None] * (rim * 0.55 + core * 0.25)[None, None, :]   # 外面一圈光晕
sun = np.where((r < R1)[..., None], disk, glow * (r >= R1)[..., None])
sun *= np.clip((1 - r) / 0.08, 0, 1)[..., None]   # 图片边上收到黑
sun_img = Image.fromarray(np.clip(sun, 0, 255).astype(np.uint8), 'RGB')

# ---------------------------------------------------------------- 写 GLB：每张图一块薄片
G = dict(asset=dict(version='2.0', generator='tools/snow/sky.py'), scene=0, scenes=[dict(nodes=[])], nodes=[], meshes=[], accessors=[], bufferViews=[],
         buffers=[], materials=[], textures=[], images=[], samplers=[dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)])
blob = bytearray()


def add_view(data, target=None):
    while len(blob) % 4:
        blob.append(0)
    o = len(blob)
    blob.extend(data)
    v = dict(buffer=0, byteOffset=o, byteLength=len(data))
    if target:
        v['target'] = target
    G['bufferViews'].append(v)
    return len(G['bufferViews']) - 1


def add_acc(arr, typ, comp, target=None, minmax=False):
    a = np.ascontiguousarray(arr)
    v = add_view(a.tobytes(), target)
    d = dict(bufferView=v, componentType=comp, count=int(a.shape[0]), type=typ)
    if minmax:
        d['min'] = a.min(0).tolist()
        d['max'] = a.max(0).tolist()
    G['accessors'].append(d)
    return len(G['accessors']) - 1


items = [('sky' + k, faces[k], 'JPEG') for k in ('ft', 'bk', 'lf', 'rt', 'up', 'dn')] + [('moontex', moon_img, 'PNG'), ('suntex', sun_img, 'PNG')]
for i, (key, img, fmt) in enumerate(items):
    b = io.BytesIO()
    if fmt == 'JPEG':
        img.save(b, 'JPEG', quality=92)
        mime = 'image/jpeg'
    else:
        img.save(b, 'PNG', optimize=True)
        mime = 'image/png'
    G['images'].append(dict(bufferView=add_view(b.getvalue()), mimeType=mime))
    G['textures'].append(dict(source=len(G['images']) - 1, sampler=0))
    G['materials'].append(dict(name=key, pbrMetallicRoughness=dict(baseColorTexture=dict(index=len(G['textures']) - 1), metallicFactor=0.0, roughnessFactor=1.0),
                               emissiveTexture=dict(index=len(G['textures']) - 1), emissiveFactor=[1, 1, 1]))
    Sz = 20.0
    P = np.array([[-Sz, 0, -Sz], [Sz, 0, -Sz], [Sz, 0, Sz], [-Sz, 0, Sz]], np.float32)
    N = np.tile(np.array([0, 1, 0], np.float32), (4, 1))
    U = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], np.float32)
    T = np.array([0, 2, 1, 0, 3, 2], np.uint32)
    a_p = add_acc(P, 'VEC3', 5126, 34962, minmax=True)
    a_n = add_acc(N, 'VEC3', 5126, 34962)
    a_u = add_acc(U, 'VEC2', 5126, 34962)
    a_i = add_acc(T, 'SCALAR', 5125, 34963)
    G['meshes'].append(dict(name=f'N_{key}__Body', primitives=[dict(attributes=dict(POSITION=a_p, NORMAL=a_n, TEXCOORD_0=a_u), indices=a_i, material=len(G['materials']) - 1)]))
    G['nodes'].append(dict(name=f'N_{key}__Body', mesh=len(G['meshes']) - 1, translation=[float((i % 4) * 50), 0.0, float((i // 4) * 50)]))
    G['scenes'][0]['nodes'].append(len(G['nodes']) - 1)
while len(blob) % 4:
    blob.append(0)
G['buffers'].append(dict(byteLength=len(blob)))
js = json.dumps(G, separators=(',', ':')).encode()
js += b' ' * ((4 - len(js) % 4) % 4)
with open(OUT, 'wb') as f:
    f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(blob)))
    f.write(struct.pack('<I4s', len(js), b'JSON'))
    f.write(js)
    f.write(struct.pack('<I4s', len(blob), b'BIN\x00'))
    f.write(bytes(blob))
print('写好', OUT, '%.1f MB' % (os.path.getsize(OUT) / 1e6))
if PREV:   # 预览：立方体展开（十字）+ 月亮 + 太阳
    W = 256
    sheet = Image.new('RGB', (W * 4 + 2 * W, W * 3), (40, 0, 40))
    pos = {'up': (1, 0), 'lf': (0, 1), 'ft': (1, 1), 'rt': (2, 1), 'bk': (3, 1), 'dn': (1, 2)}
    for k, (cx, cy) in pos.items():
        sheet.paste(faces[k].resize((W, W)), (cx * W, cy * W))
    sheet.paste(moon_img.resize((W, W)), (4 * W, 0))
    sheet.paste(sun_img.resize((W, W)), (5 * W, 0))
    sheet.save(PREV)
