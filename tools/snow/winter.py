# 冬季树包（Sketchfab 上 99.Miles 的「Low Poly Winter Tree Pack」，CC-BY 4.0）→ 雪山地图的树、灌木 + 地面雪贴图
#   用户 11-26 晚：「我发你的那个这里面的雪非常细节 你把这下载下来 把树给搞进地图里 地面用我发你的这个雪」
#   python3 -I tools/snow/winter.py <winter.glb> <输出 models/scenery/winter.glb> <输出 WinterMeta.lua> [原始贴图目录 TEXTURES/VEGETATION]
#   用户 11-26 夜：「那个树你记得用那个 我发你的那个精细建模树哈」——给了原始贴图目录（原包 source.zip 里 2048² 的 Diffuse / Opacity / Normal）
#     就每棵树单独做贴图：只裁这棵树用到的那几块（面片的剪影、挂雪的枝叶），按原分辨率拼成一张（超过 1024 才缩，Roblox 贴图上限 1024），
#     UV 跟着改——比整张图集一起缩到 1024 清楚一倍左右；法线也照样裁（512 以内），粗糙度用常数
#   原包是一个小场景：一个雪堆（Snow，细腻的积雪贴图 + 法线）、几片化雪的泥地（Snow_Melting）、十几棵冬天的树和几丛灌木——
#     树 = 树干、枝杈的竖面片（Winter_Trees_Planes，透明贴图）+ 挂着雪的枝叶面片（Winter_Trees_Branches）。这里一棵棵拆出来：
#     ① 竖面片按连通块分开，中心挨得近的（2.2 米内）算同一棵树的；② 枝叶面片分给水平距离最近的那棵（6.5 米内、高度对得上），
#     ③ 剩下低矮的枝叶面片按远近连成一丛丛灌木。每棵原点在树干底部中心；1 米 = 2.8 格。
#   面片带透明贴图：做成双面（多一份反过来的三角形；Roblox 的网格只画正面），材质 MASK（裁掉透明的地方）。
#   地面雪：雪堆、化雪泥地的贴图各放在一块 40 格见方的薄片上（N_snowtex__Body、N_slushtex__Body）——Studio 导入时贴图会上传，
#     游戏里（Client/SnowLook.lua）把它们的贴图做成 MaterialVariant 换掉地形的 Snow、Ground 材质
#   块叫 N_<键>__<块名>（Imports.lua 收进 ReplicatedStorage.Imported.Scenery.<键>，同 scenery.glb），元数据格式同 SceneryMeta
import sys, os, json, struct, io
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import gltfio
from PIL import Image

SRC, OUT, META_OUT = sys.argv[1], sys.argv[2], sys.argv[3]
TEXDIR = sys.argv[4] if len(sys.argv) > 4 else None
M2S = 2.8
MAT_BR, MAT_SNOW, MAT_MELT, MAT_PL = 0, 1, 2, 3

prims, mats = gltfio.load(SRC)
raw = open(SRC, 'rb').read()
jl = struct.unpack_from('<I', raw, 12)[0]
J = json.loads(raw[20:20 + jl])
bl = struct.unpack_from('<I', raw, 20 + jl)[0]
BIN = raw[28 + jl:28 + jl + bl]


def image_of(tex):
    """材质里的贴图（GLB 里嵌着的）→ PIL 图"""
    if not tex or tex[0] != 'bufferView':
        return None
    bv = J['bufferViews'][tex[1]]
    o = bv.get('byteOffset', 0)
    return Image.open(io.BytesIO(BIN[o:o + bv['byteLength']]))


def mat_tex(mi, kind):
    m = J['materials'][mi]
    if kind == 'base':
        t = (m.get('pbrMetallicRoughness') or {}).get('baseColorTexture')
    elif kind == 'mr':
        t = (m.get('pbrMetallicRoughness') or {}).get('metallicRoughnessTexture')
    else:
        t = m.get('normalTexture')
    if not t:
        return None
    im = J['images'][J['textures'][t['index']]['source']]
    return image_of(('bufferView', im.get('bufferView')))


# ---------------------------------------------------------------- 连通块
def components(p):
    T = p['idx']
    nv = len(p['pos'])
    par = np.arange(nv)

    def f(a):
        r = a
        while par[r] != r:
            r = par[r]
        while par[a] != r:
            par[a], a = r, par[a]
        return r
    for a, b, c in T:
        ra = f(a)
        par[f(b)] = ra
        par[f(c)] = ra
    lab = np.array([f(i) for i in range(nv)])
    groups = {}
    for ti, l in enumerate(lab[T[:, 0]]):
        groups.setdefault(int(l), []).append(ti)
    out = []
    for g in groups.values():
        tri = T[np.array(g)]
        V = p['pos'][tri.reshape(-1)]
        lo, hi = V.min(0), V.max(0)
        out.append(dict(p=p, tris=tri, lo=lo, hi=hi, c=(lo + hi) / 2))
    return out


# 原包里多数树一棵一个节点（竖面片节点 + 枝叶节点成对），北边一片树林、两道矮树篱是几棵合在一个节点里的：
#   ① 一个竖面片节点水平范围不大（< 14 米）就是一棵树，枝叶节点中心落在它范围里的（够高的）归它；
#   ② 合在一起的那片：竖面片按连通块分，中心挨得近的（3.6 米内）算一棵，枝叶按块分给水平最近的树（6.5 米内）；
#   ③ 剩下的枝叶：矮的单个节点一丛灌木；树篱、林子里剩的按远近连起来，长过 7 米的再切成几段（一丛一段）
def ext(p):
    lo, hi = p['pos'].min(0), p['pos'].max(0)
    return lo, hi


def comps_n(ps):
    out = []
    for p in ps:
        out += components(p)
    return out


pl_prims = [p for p in prims if p['mat'] == MAT_PL]
br_prims = [p for p in prims if p['mat'] == MAT_BR]
trees = []
group_pl, used_br = [], set()
for p in pl_prims:
    lo, hi = ext(p)
    if max(hi[0] - lo[0], hi[2] - lo[2]) < 14:
        trees.append(dict(pl=components(p), br=[], lo=lo, hi=hi))
    else:
        group_pl.append(p)
for i, b in enumerate(br_prims):
    lo, hi = ext(b)
    c = (lo + hi) / 2
    if max(hi[0] - lo[0], hi[2] - lo[2]) >= 14 or hi[1] < 7:
        continue
    best, bo = None, 0
    for t in trees:
        if t['lo'][0] - 1.5 < c[0] < t['hi'][0] + 1.5 and t['lo'][2] - 1.5 < c[2] < t['hi'][2] + 1.5:
            o = min(hi[0], t['hi'][0]) - max(lo[0], t['lo'][0]) + min(hi[2], t['hi'][2]) - max(lo[2], t['lo'][2])
            if best is None or o > bo:
                best, bo = t, o
    if best is not None:
        best['br'] += components(b)
        used_br.add(i)
# ② 合在一起的那片树林
gpl = comps_n(group_pl)
n = len(gpl)
par = list(range(n))


def fnd(a):
    while par[a] != a:
        par[a] = par[par[a]]
        a = par[a]
    return a


for i in range(n):
    for j in range(i + 1, n):
        if np.hypot(gpl[i]['c'][0] - gpl[j]['c'][0], gpl[i]['c'][2] - gpl[j]['c'][2]) < 3.6:
            par[fnd(j)] = fnd(i)
gg = {}
for i in range(n):
    gg.setdefault(fnd(i), []).append(gpl[i])
gtrees = []
for v in gg.values():
    lo = np.min([c['lo'] for c in v], 0)
    hi = np.max([c['hi'] for c in v], 0)
    gtrees.append(dict(pl=v, br=[], lo=lo, hi=hi))
left = []
for i, b in enumerate(br_prims):
    if i in used_br:
        continue
    lo, hi = ext(b)
    if max(hi[0] - lo[0], hi[2] - lo[2]) < 14 and hi[1] < 7:   # 矮的单个节点：一丛灌木
        left.append(('bush', components(b)))
        continue
    for c in components(b):
        best, bd = None, 6.5
        for t in gtrees:
            tx, tz = (t['lo'][0] + t['hi'][0]) / 2, (t['lo'][2] + t['hi'][2]) / 2
            d = np.hypot(c['c'][0] - tx, c['c'][2] - tz)
            if d < bd and c['lo'][1] > t['lo'][1] + 1.0 and c['hi'][1] < t['hi'][1] + 3:
                best, bd = t, d
        if best is not None:
            best['br'].append(c)
        else:
            left.append(('loose', [c]))
trees += gtrees
for t in trees:
    xs = np.array([c['c'] for c in t['pl']])
    t['x'], t['z'] = float(xs[:, 0].mean()), float(xs[:, 2].mean())
    t['y0'] = float(min(c['lo'][1] for c in t['pl']))
    t['y1'] = float(max(c['hi'][1] for c in t['pl']))
# ③ 灌木
bushes = [v for k, v in left if k == 'bush']
loose = [v[0] for k, v in left if k == 'loose']
n = len(loose)
par = list(range(n))
for i in range(n):
    for j in range(i + 1, n):
        if np.hypot(loose[i]['c'][0] - loose[j]['c'][0], loose[i]['c'][2] - loose[j]['c'][2]) < 1.6:
            par[fnd(j)] = fnd(i)
gg = {}
for i in range(n):
    gg.setdefault(fnd(i), []).append(loose[i])
for v in gg.values():
    if len(v) < 6:
        continue
    xs = np.array([c['c'] for c in v])
    span = max(np.ptp(xs[:, 0]), np.ptp(xs[:, 2]))
    k = max(1, int(np.ceil(span / 6.0)))
    if k == 1:
        bushes.append(v)
        continue
    # 长的一串（树篱）：沿长的方向等分成 k 段
    ax = 0 if np.ptp(xs[:, 0]) >= np.ptp(xs[:, 2]) else 2
    order = np.argsort(xs[:, ax])
    for q in range(k):
        seg = [v[i] for i in order[q * len(v) // k:(q + 1) * len(v) // k]]
        if len(seg) >= 6:
            bushes.append(seg)
print('树', len(trees), '棵（成对节点', len(trees) - len(gtrees), '、树林里拆出', len(gtrees), '）；灌木', len(bushes), '丛')

# ---------------------------------------------------------------- 拼 GLB
G = dict(asset=dict(version='2.0', generator='tools/snow/winter.py'), scene=0, scenes=[dict(nodes=[])], nodes=[], meshes=[],
         accessors=[], bufferViews=[], buffers=[], materials=[], textures=[], images=[], samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)])
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
    acc = dict(bufferView=v, componentType=comp, count=int(a.shape[0]), type=typ)
    if minmax:
        acc['min'] = a.min(0).tolist()
        acc['max'] = a.max(0).tolist()
    G['accessors'].append(acc)
    return len(G['accessors']) - 1


def add_image(im, fmt):
    b = io.BytesIO()
    if fmt == 'PNG':
        im.save(b, 'PNG', optimize=True)
        mime = 'image/png'
    else:
        im.convert('RGB').save(b, 'JPEG', quality=90)
        mime = 'image/jpeg'
    v = add_view(b.getvalue())
    G['images'].append(dict(bufferView=v, mimeType=mime))
    G['textures'].append(dict(source=len(G['images']) - 1, sampler=0))
    return len(G['textures']) - 1


def fit(im, mx=1024):
    w, h = im.size
    if max(w, h) > mx:
        k = mx / max(w, h)
        im = im.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
    return im


def make_mat(name, mi, alpha):
    base = mat_tex(mi, 'base')
    m = dict(name=name, pbrMetallicRoughness=dict(metallicFactor=0.0, roughnessFactor=0.9), doubleSided=False)
    if base is not None:
        m['pbrMetallicRoughness']['baseColorTexture'] = dict(index=add_image(fit(base.convert('RGBA' if alpha else 'RGB')), 'PNG' if alpha else 'JPEG'))
    nm = mat_tex(mi, 'nrm')
    if nm is not None:
        m['normalTexture'] = dict(index=add_image(fit(nm.convert('RGB')), 'JPEG'))
    mr = mat_tex(mi, 'mr')
    if mr is not None:   # 粗糙度在 G 通道（金属度 B 通道这里都是 0）
        g = mr.convert('RGB').split()[1]
        z = Image.new('L', g.size, 0)
        m['pbrMetallicRoughness']['metallicRoughnessTexture'] = dict(index=add_image(fit(Image.merge('RGB', (z, g, z))), 'JPEG'))
        m['pbrMetallicRoughness']['roughnessFactor'] = 1.0
    if alpha:
        m['alphaMode'] = 'MASK'
        m['alphaCutoff'] = 0.45
    G['materials'].append(m)
    return len(G['materials']) - 1


MI = {MAT_SNOW: make_mat('WinterSnow', MAT_SNOW, False), MAT_MELT: make_mat('WinterSlush', MAT_MELT, False)}
if not TEXDIR:   # 没给原始贴图：树、灌木共用整张图集（缩到 1024）
    MI[MAT_BR] = make_mat('WinterBranches', MAT_BR, True)
    MI[MAT_PL] = make_mat('WinterPlanes', MAT_PL, True)


def mesh_from(comps, x0, y0, z0, double=True, uvmap=None):
    """一组连通块 → (顶点、法线、UV、三角形)，坐标相对 (x0, y0, z0)、换成格；uvmap(块序号, uv) 换到这件自己的贴图上"""
    P, N, U, T = [], [], [], []
    base = 0
    for ci, c in enumerate(comps):
        p = c['p']
        vid = np.unique(c['tris'].reshape(-1))
        remap = {int(v): i for i, v in enumerate(vid)}
        pos = (p['pos'][vid] - np.array([x0, y0, z0])) * M2S
        nrm = p['nrm'][vid] if p['nrm'] is not None else np.tile([0, 1, 0], (len(vid), 1))
        uv = p['uv'][vid] if p['uv'] is not None else np.zeros((len(vid), 2))
        if uvmap is not None:
            uv = uvmap(ci, uv)
        tri = np.vectorize(lambda v: remap[int(v)])(c['tris'])
        P.append(pos), N.append(nrm), U.append(uv), T.append(tri + base)
        base += len(vid)
        if double:   # 反面：同样的顶点再来一份，法线反过来、三角形绕向反过来
            P.append(pos), N.append(-nrm), U.append(uv), T.append(tri[:, [0, 2, 1]] + base)
            base += len(vid)
    return np.vstack(P), np.vstack(N), np.vstack(U), np.vstack(T)


meta = {}

# ---------------------------------------------------------------- 每件自己的贴图（原始 2048² 贴图里裁这件用到的块，按原分辨率拼）
SRCTEX = {}
if TEXDIR:
    def _ld(sub, names):
        for nm in names:
            f = os.path.join(TEXDIR, sub, nm)
            if os.path.exists(f):
                return Image.open(f)
        raise FileNotFoundError(sub + '/' + names[0])
    for mi, sub, pre in ((MAT_BR, 'DETAILS', 'Winter_Trees_Branches'), (MAT_PL, 'PLANES', 'Winter_Trees_Planes')):
        # 原包的 PNG 是 FBX 的习惯（UV 原点在左下）：上下翻过来才和 glb 的 UV 对得上（glb 里嵌的就是翻过的；法线图的绿通道不用反）
        FL = Image.FLIP_TOP_BOTTOM
        dif = _ld(sub, [pre + '_Diffuse.png', pre + '_Difffuse.png']).convert('RGB').transpose(FL)
        opa = _ld(sub, [pre + '_Opacity.png']).convert('L').transpose(FL)
        nrm = _ld(sub, [pre + '_Normal.png']).convert('RGB').transpose(FL)
        rgba = dif.copy()
        rgba.putalpha(opa)
        SRCTEX[mi] = dict(col=rgba, nrm=nrm, W=dif.size[0], H=dif.size[1])
    print('原始贴图', {k: v['col'].size for k, v in SRCTEX.items()})
ATLAS = {}   # 同样的几块拼出来的贴图只做一份：键 = (材质, 块的矩形们) → 材质号


def part_atlas(comps, mi):
    """这一件（一组连通块，同一种材质）用到的贴图块：每块的 UV 外框合并成「图块」，按原分辨率排成一张（超过 1024 整体缩），
       返回 (材质号, uvmap)"""
    S = SRCTEX[mi]
    W, H = S['W'], S['H']
    rects = []
    for c in comps:
        vid = np.unique(c['tris'].reshape(-1))
        uv = c['p']['uv'][vid]
        u0, v0 = np.clip(uv.min(0), 0, 1)
        u1, v1 = np.clip(uv.max(0), 0, 1)
        rects.append([u0 * W, v0 * H, u1 * W, v1 * H])
    # 重叠的外框合成一个图块（同一张小图上的几片）
    n = len(rects)
    par = list(range(n))

    def f(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for i in range(n):
        for j in range(i + 1, n):
            a, b = rects[i], rects[j]
            if a[0] < b[2] + 2 and b[0] < a[2] + 2 and a[1] < b[3] + 2 and b[1] < a[3] + 2:
                par[f(j)] = f(i)
    groups = {}
    for i in range(n):
        groups.setdefault(f(i), []).append(i)
    tiles = []
    owner = [0] * n
    for gi, idx in enumerate(groups.values()):
        x0 = max(0, int(np.floor(min(rects[i][0] for i in idx))) - 4)
        y0 = max(0, int(np.floor(min(rects[i][1] for i in idx))) - 4)
        x1 = min(W, int(np.ceil(max(rects[i][2] for i in idx))) + 4)
        y1 = min(H, int(np.ceil(max(rects[i][3] for i in idx))) + 4)
        tiles.append([x0, y0, x1, y1])
        for i in idx:
            owner[i] = gi
    key = (mi, tuple(tuple(t) for t in sorted(tiles)))
    # 排：按高从高到低一行行放（行宽不超过总面积开方的 1.15 倍）
    order = sorted(range(len(tiles)), key=lambda t: -(tiles[t][3] - tiles[t][1]))
    area = sum((t[2] - t[0]) * (t[3] - t[1]) for t in tiles)
    rowW = max(max(t[2] - t[0] for t in tiles), int(np.sqrt(area) * 1.15))
    pos = [None] * len(tiles)
    x = y = rh = 0
    for t in order:
        w, h = tiles[t][2] - tiles[t][0], tiles[t][3] - tiles[t][1]
        if x > 0 and x + w > rowW:
            x, y, rh = 0, y + rh, 0
        pos[t] = (x, y)
        x += w
        rh = max(rh, h)
    AW = max(pos[t][0] + tiles[t][2] - tiles[t][0] for t in range(len(tiles)))
    AH = max(pos[t][1] + tiles[t][3] - tiles[t][1] for t in range(len(tiles)))
    if key not in ATLAS:
        col = Image.new('RGBA', (AW, AH), (0, 0, 0, 0))
        nrm = Image.new('RGB', (AW, AH), (128, 128, 255))
        for t in range(len(tiles)):
            box = tuple(tiles[t])
            col.paste(S['col'].crop(box), pos[t])
            nrm.paste(S['nrm'].crop(box), pos[t])
        k = min(1.0, 1024 / max(AW, AH))
        if k < 1:
            col = col.resize((max(1, round(AW * k)), max(1, round(AH * k))), Image.LANCZOS)
        nk = min(1.0, 512 / max(nrm.size))
        if nk < 1:
            nrm = nrm.resize((max(1, round(AW * nk)), max(1, round(AH * nk))), Image.LANCZOS)
        m = dict(name=('WinterBranches' if mi == MAT_BR else 'WinterPlanes') + str(len(ATLAS) + 1),
                 pbrMetallicRoughness=dict(metallicFactor=0.0, roughnessFactor=0.88), doubleSided=False, alphaMode='MASK', alphaCutoff=0.45)
        m['pbrMetallicRoughness']['baseColorTexture'] = dict(index=add_image(col, 'PNG'))
        m['normalTexture'] = dict(index=add_image(nrm, 'JPEG'))
        G['materials'].append(m)
        ATLAS[key] = dict(mat=len(G['materials']) - 1, size=col.size, src=(AW, AH))
        print('  贴图', m['name'], '原尺寸 %d×%d → %d×%d（%d 块）' % (AW, AH, col.size[0], col.size[1], len(tiles)))
    A = ATLAS[key]
    # 同样的几块（key 相同）排法也相同（上面的排法只看图块）：UV 换算按这次的排法
    def uvmap(ci, uv):
        t = owner[ci]
        px = uv[:, 0] * W - tiles[t][0] + pos[t][0]
        py = uv[:, 1] * H - tiles[t][1] + pos[t][1]
        return np.stack([px / AW, py / AH], -1)
    return A['mat'], uvmap


# ---------------------------------------------------------------- 共用图集（用户 11-27：「一万一千棵树、每棵单独贴图，树包文件从 4.5MB 涨到 17.9MB」）：
#   所有树、灌木用到的图块（面片剪影、挂雪枝叶）合起来排进几张 1024² 的共用图集（剪影按原图 0.72、枝叶 0.85），
#   一件的面片 / 枝叶落在哪张图集上就用哪张（落在两张上的拆成两块网格）。比原来整张图集缩到 1024 清楚，比每棵一张省得多
PENDING = []


def add_item(key, kind, parts, x0, y0, z0):
    PENDING.append((key, kind, parts, x0, y0, z0))


SCALE = {MAT_PL: 0.72, MAT_BR: 0.85}
PAGE = 1024
SHARED = {}   # (材质, 件号, 块号, 连通块号) → (图集页, uvmap 参数)


def comp_rect(c, W, H):
    vid = np.unique(c['tris'].reshape(-1))
    uv = c['p']['uv'][vid]
    u0, v0 = np.clip(uv.min(0), 0, 1)
    u1, v1 = np.clip(uv.max(0), 0, 1)
    return [u0 * W, v0 * H, u1 * W, v1 * H]


def build_quads(mi):
    """枝叶图集：小图一块挨一块（外框连成一片），按图块排会合成整张——改成从原图里挑几块 1088² 的窗口（缩到 1024，接近原分辨率），
       贪心挑：每次挑能整个装下最多连通块的窗口，直到都装下（装不下的极少数用整张缩到 1024 的那张）"""
    S = SRCTEX[mi]
    W, H = S['W'], S['H']
    R = 1088
    cands = [(x0, y0) for y0 in range(0, H - R + 1, 120) for x0 in range(0, W - R + 1, 120)]
    if (W - R, H - R) not in cands:
        cands.append((W - R, H - R))
    comps = []
    for ii, (key, kind, parts, *_r) in enumerate(PENDING):
        for pi, (name, cs, pmi) in enumerate(parts):
            if pmi != mi:
                continue
            for ci, c in enumerate(cs):
                comps.append(((ii, pi, ci), comp_rect(c, W, H)))
    left = list(range(len(comps)))
    regs = []
    assign = {}
    while left and len(regs) < 8:
        best, bset = None, []
        for (x0, y0) in cands:
            inside = [i for i in left if comps[i][1][0] >= x0 + 2 and comps[i][1][1] >= y0 + 2 and comps[i][1][2] <= x0 + R - 2 and comps[i][1][3] <= y0 + R - 2]
            if len(inside) > len(bset):
                best, bset = (x0, y0), inside
        if not bset:
            break
        regs.append((best[0], best[1], R, R))
        for i in bset:
            assign[comps[i][0]] = len(regs) - 1
        left = [i for i in left if i not in set(bset)]
    if left:
        regs.append((0, 0, W, H))
        for i in left:
            assign[comps[i][0]] = len(regs) - 1
    mats = {}
    for k, (x0, y0, rw, rh) in enumerate(regs):
        col = S['col'].crop((x0, y0, x0 + rw, y0 + rh)).resize((PAGE, PAGE), Image.LANCZOS)
        nrm = S['nrm'].crop((x0, y0, x0 + rw, y0 + rh)).resize((PAGE // 2, PAGE // 2), Image.LANCZOS)
        m = dict(name='WinterBranches' + str(k + 1), pbrMetallicRoughness=dict(metallicFactor=0.0, roughnessFactor=0.88),
                 doubleSided=False, alphaMode='MASK', alphaCutoff=0.45)
        m['pbrMetallicRoughness']['baseColorTexture'] = dict(index=add_image(col, 'PNG'))
        m['normalTexture'] = dict(index=add_image(nrm, 'JPEG'))
        G['materials'].append(m)
        mats[k] = len(G['materials']) - 1
    for ref, k in assign.items():
        x0, y0, rw, rh = regs[k]
        SHARED[(mi,) + ref] = (mats[k], (x0, y0, rw, rh, 0, 0, PAGE, PAGE, W, H))
    print('共用图集 Branches：', len(regs), '张', '（整张缩的那张上 %d 块）' % len(left) if left else '（都在近原分辨率的窗口里）')


def build_shared():
    for mi, S in SRCTEX.items():
        if mi == MAT_BR:
            build_quads(mi)
            continue
        W, H = S['W'], S['H']
        refs = []
        for ii, (key, kind, parts, *_r) in enumerate(PENDING):
            for pi, (name, comps, pmi) in enumerate(parts):
                if pmi != mi:
                    continue
                for ci, c in enumerate(comps):
                    refs.append(((ii, pi, ci), comp_rect(c, W, H)))
        n = len(refs)
        par = list(range(n))

        def f(a):
            while par[a] != a:
                par[a] = par[par[a]]
                a = par[a]
            return a
        order = sorted(range(n), key=lambda i: refs[i][1][0])
        for oi in range(n):   # 按 x 排过的扫描：只和 x 上挨得着的比
            i = order[oi]
            ri = refs[i][1]
            for oj in range(oi + 1, n):
                j = order[oj]
                rj = refs[j][1]
                if rj[0] > ri[2] + 2:
                    break
                if ri[1] < rj[3] + 2 and rj[1] < ri[3] + 2:
                    par[f(j)] = f(i)
        groups = {}
        for i in range(n):
            groups.setdefault(f(i), []).append(i)
        tiles, owner = [], {}
        for g in groups.values():
            x0 = max(0, int(np.floor(min(refs[i][1][0] for i in g))) - 4)
            y0 = max(0, int(np.floor(min(refs[i][1][1] for i in g))) - 4)
            x1 = min(W, int(np.ceil(max(refs[i][1][2] for i in g))) + 4)
            y1 = min(H, int(np.ceil(max(refs[i][1][3] for i in g))) + 4)
            ti = len(tiles)
            tiles.append([x0, y0, x1, y1])
            for i in g:
                owner[refs[i][0]] = ti
        # 排：按缩过的高从高到低，一行行放进 1024² 的页
        sc = SCALE[mi]
        sizes = []
        for t in tiles:
            w, h = (t[2] - t[0]) * sc, (t[3] - t[1]) * sc
            k = min(1.0, (PAGE - 4) / max(w, h))
            sizes.append((max(1, int(round(w * k))), max(1, int(round(h * k)))))
        order = sorted(range(len(tiles)), key=lambda t: -sizes[t][1])
        pages, place = [], {}
        cur = None
        for t in order:
            w, h = sizes[t]
            if cur is None or (cur['x'] + w > PAGE and cur['y'] + cur['rh'] + h > PAGE) or (cur['x'] + w <= PAGE and cur['y'] + h > PAGE):
                cur = dict(x=0, y=0, rh=0, items=[])
                pages.append(cur)
            if cur['x'] + w > PAGE:
                cur['x'], cur['y'], cur['rh'] = 0, cur['y'] + cur['rh'], 0
                if cur['y'] + h > PAGE:
                    cur = dict(x=0, y=0, rh=0, items=[])
                    pages.append(cur)
            place[t] = (len(pages) - 1, cur['x'], cur['y'])
            cur['items'].append(t)
            cur['x'] += w
            cur['rh'] = max(cur['rh'], h)
        mats = []
        for pg_i, pg in enumerate(pages):
            col = Image.new('RGBA', (PAGE, PAGE), (0, 0, 0, 0))
            nrm = Image.new('RGB', (PAGE, PAGE), (128, 128, 255))
            for t in pg['items']:
                box = tuple(tiles[t])
                w, h = sizes[t]
                _, px, py = place[t]
                col.paste(S['col'].crop(box).resize((w, h), Image.LANCZOS), (px, py))
                nrm.paste(S['nrm'].crop(box).resize((w, h), Image.LANCZOS), (px, py))
            nrm = nrm.resize((PAGE // 2, PAGE // 2), Image.LANCZOS)
            m = dict(name=('WinterBranches' if mi == MAT_BR else 'WinterPlanes') + str(pg_i + 1),
                     pbrMetallicRoughness=dict(metallicFactor=0.0, roughnessFactor=0.88), doubleSided=False, alphaMode='MASK', alphaCutoff=0.45)
            m['pbrMetallicRoughness']['baseColorTexture'] = dict(index=add_image(col, 'PNG'))
            m['normalTexture'] = dict(index=add_image(nrm, 'JPEG'))
            G['materials'].append(m)
            mats.append(len(G['materials']) - 1)
        print('共用图集', 'Branches' if mi == MAT_BR else 'Planes', '图块', len(tiles), '张数', len(pages))
        for ref, t in owner.items():
            pg, px, py = place[t]
            w, h = sizes[t]
            T0 = tiles[t]
            SHARED[(mi,) + ref] = (mats[pg], (T0[0], T0[1], (T0[2] - T0[0]), (T0[3] - T0[1]), px, py, w, h, W, H))


def emit_item(ii, key, kind, parts, x0, y0, z0):
    built = []
    lo = np.array([1e9] * 3)
    hi = -lo
    for pi, (name, comps, mi) in enumerate(parts):
        if not comps:
            continue
        if mi in SRCTEX:
            byMat = {}
            for ci, c in enumerate(comps):
                gm, prm = SHARED[(mi, ii, pi, ci)]
                byMat.setdefault(gm, []).append((c, prm))
            for k, (gm, lst) in enumerate(byMat.items()):
                cs = [c for c, _ in lst]
                prms = [prm for _, prm in lst]

                def uvmap(ci, uv, prms=prms):
                    tx, ty, tw, th, px, py, w, h, W, H = prms[ci]
                    return np.stack([(px + (uv[:, 0] * W - tx) / tw * w) / PAGE, (py + (uv[:, 1] * H - ty) / th * h) / PAGE], -1)
                P, N, U, T = mesh_from(cs, x0, y0, z0, uvmap=uvmap)
                lo, hi = np.minimum(lo, P.min(0)), np.maximum(hi, P.max(0))
                built.append((name if k == 0 else f'{name}{k + 1}', P, N, U, T, gm))
        else:
            P, N, U, T = mesh_from(comps, x0, y0, z0)
            lo, hi = np.minimum(lo, P.min(0)), np.maximum(hi, P.max(0))
            built.append((name, P, N, U, T, MI[mi]))
    if not built:
        return
    r = float(max(hi[0] - lo[0], hi[2] - lo[2]) / 2)
    # 在 GLB 里排成一行行（每行 8 件、间隔 60 格：Studio 导进来不叠在一起，预览也看得清）
    ox, oz = (len(meta) % 8) * 60.0, (len(meta) // 8) * 60.0
    pm = []
    tris = 0
    for name, P, N, U, T, mi in built:
        c = (P.min(0) + P.max(0)) / 2
        s2 = P.max(0) - P.min(0)
        rel = (P - c).astype(np.float32)
        a_p = add_acc(rel, 'VEC3', 5126, 34962, minmax=True)
        a_n = add_acc(N.astype(np.float32), 'VEC3', 5126, 34962)
        a_u = add_acc(U.astype(np.float32), 'VEC2', 5126, 34962)
        a_i = add_acc(T.astype(np.uint32).reshape(-1), 'SCALAR', 5125, 34963)
        G['meshes'].append(dict(name=f'N_{key}__{name}', primitives=[dict(attributes=dict(POSITION=a_p, NORMAL=a_n, TEXCOORD_0=a_u), indices=a_i, material=mi)]))
        G['nodes'].append(dict(name=f'N_{key}__{name}', mesh=len(G['meshes']) - 1, translation=[float(ox + c[0]), float(c[1]), float(oz + c[2])]))
        G['scenes'][0]['nodes'].append(len(G['nodes']) - 1)
        pm.append(dict(name=name, c=[round(float(v), 2) for v in c], s=[round(float(v), 2) for v in s2]))
        tris += len(T)
    meta[key] = dict(kind=kind, h=round(float(hi[1]), 2), r=round(r, 2), o=[round(ox, 2), 0, round(oz, 2)], tris=int(tris), parts=pm)


# 原场景里同一棵树摆了好几次（三角形数、高矮都一样）：同样的只留一棵
def sig(comps):
    n = sum(len(c['tris']) for c in comps)
    lo = np.min([c['lo'] for c in comps], 0)
    hi = np.max([c['hi'] for c in comps], 0)
    return (n, round(float(hi[1] - lo[1]), 1), round(float(max(hi[0] - lo[0], hi[2] - lo[2])), 0))


seen = set()
uniq = []
for t in trees:
    k = sig(t['pl'] + t['br'])
    if k not in seen:
        seen.add(k)
        uniq.append(t)
print('去掉重复的树', len(trees) - len(uniq), '棵')
trees = uniq
seen = set()
uniq = []
for b in bushes:
    k = sig(b)
    if k not in seen:
        seen.add(k)
        uniq.append(b)
print('去掉重复的灌木', len(bushes) - len(uniq), '丛')
bushes = uniq
# 树：高的在前（wt1 最高）
trees.sort(key=lambda t: -(t['y1'] - t['y0']))
for i, t in enumerate(trees):
    add_item(f'wt{i + 1}', 'winter', [('Planes', t['pl'], MAT_PL), ('Branches', t['br'], MAT_BR)], t['x'], t['y0'], t['z'])
for i, b in enumerate(sorted(bushes, key=lambda v: -len(v))):
    xs = np.array([c['c'] for c in b])
    y0 = float(min(c['lo'][1] for c in b))
    add_item(f'ws{i + 1}', 'bush', [('Branches', b, MAT_BR)], float(xs[:, 0].mean()), y0, float(xs[:, 2].mean()))

# 图集排好再出网格
if SRCTEX:
    build_shared()
for ii, it in enumerate(PENDING):
    emit_item(ii, *it)

# 地面雪贴图的载体：40 格见方的一块薄片（UV 0～1 铺满一张）
for key, mi in (('snowtex', MAT_SNOW), ('slushtex', MAT_MELT)):
    S = 20.0
    P = np.array([[-S, 0, -S], [S, 0, -S], [S, 0, S], [-S, 0, S]], dtype=np.float32)
    Nn = np.tile(np.array([0, 1, 0], dtype=np.float32), (4, 1))
    U = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float32)
    T = np.array([[0, 2, 1], [0, 3, 2]], dtype=np.uint32)
    ox, oz = (len(meta) % 8) * 60.0, (len(meta) // 8) * 60.0
    a_p = add_acc(P, 'VEC3', 5126, 34962, minmax=True)
    a_n = add_acc(Nn, 'VEC3', 5126, 34962)
    a_u = add_acc(U, 'VEC2', 5126, 34962)
    a_i = add_acc(T.reshape(-1), 'SCALAR', 5125, 34963)
    G['meshes'].append(dict(name=f'N_{key}__Body', primitives=[dict(attributes=dict(POSITION=a_p, NORMAL=a_n, TEXCOORD_0=a_u), indices=a_i, material=MI[mi])]))
    G['nodes'].append(dict(name=f'N_{key}__Body', mesh=len(G['meshes']) - 1, translation=[float(ox), 0.0, float(oz)]))
    G['scenes'][0]['nodes'].append(len(G['nodes']) - 1)
    meta[key] = dict(kind='tex', h=0.1, r=S, o=[round(ox, 2), 0, round(oz, 2)], tris=2, parts=[dict(name='Body', c=[0, 0, 0], s=[2 * S, 0.1, 2 * S])])

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


def lua(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k, lua(v[k])) for k in ('name', 'kind', 'h', 'r', 'o', 'tris', 'c', 's', 'parts') if k in v) + ' }'
    if isinstance(v, (list, tuple)):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, float):
        return ('%.2f' % v).rstrip('0').rstrip('.')
    return str(v)


lines = ['-- 冬季树包的元数据（tools/snow/winter.py 生成，别手改；格式同 SceneryMeta）：models/scenery/winter.glb 里每一件——',
         '--   Sketchfab 上 99.Miles 的「Low Poly Winter Tree Pack」（CC-BY 4.0）拆出来的冬天的树 wt*（kind winter）、灌木 ws*（bush），',
         '--   地面雪贴图的载体 snowtex（雪堆的雪）、slushtex（化雪的泥地）（kind tex：不摆，Client/SnowLook.lua 拿贴图换地形材质）',
         'return {']
for k in sorted(meta, key=lambda s: (s[:2], int(''.join(ch for ch in s if ch.isdigit()) or 0), s)):
    lines.append('  %s = %s,' % (k, lua(meta[k])))
lines.append('}')
open(META_OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('写好', OUT, '（%.1f MB）' % (os.path.getsize(OUT) / 1e6), len(meta), '件')
for k in sorted(meta):
    m = meta[k]
    print('  %-9s %-6s 高 %5.1f 格  冠幅半径 %4.1f  %4d 三角形' % (k, m['kind'], m['h'], m['r'], m['tris']))
