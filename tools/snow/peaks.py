# 雪山地图谷外的山体：Sketchfab 的山体模型（tools/snow/peaks.json）原样转成 Studio「导入 3D」能吃下的 GLB
#   用户 11-26 晚：「坦克交战区外你就用这几个拿去拼」「雪山你直接用这个原封不动」——不减面、贴图不降分辨率，只按 Roblox 的限制切开：
#   · 一块网格最多 2 万个三角形（这里每块不超过 19500）
#   · 零件每边最多 2048 格：按 cell 格的方格切（运行时整体再放大 kmax 倍也不超）
#   · 贴图最大 1024²：底色按 UV 切成 n × n 张（4096 的切 16 张、8192 的切 64 张），每块网格只用其中一张，UV 换算到那一张上；
#     法线、粗糙度照同一个 UV 区域切（分辨率照各自原图）
#   块叫 P_<键>__c<号>（Imports.lua 收进 ReplicatedStorage.Imported.Peaks.<键>），节点的位置就是这块的中心（烘焙坐标：原模型 x、z 居中、最低点 y = 0，
#   乘 scale 换成格）；元数据写进 src/ReplicatedStorage/SnowPeaksMeta.lua（每块的中心、大小、三角形数），布局、高度场工具（tools/snow/layout.py）也读它
# 用法：python3 -I tools/snow/peaks.py <下载目录> [键…]
#   下载目录里每个源一个子目录 <键>/scene.gltf（Sketchfab「glTF」压缩包解开）；不给键就全转。输出 models/snow/<键>.glb
import io, json, math, os, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltfio  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
CFG = json.load(open(os.path.join(HERE, 'peaks.json'), encoding='utf-8'))
TRI_MAX = 19500
TEX_MAX = 1024


def tiles_of(path):
    if not path:
        return 1, (0, 0)
    w, h = Image.open(path).size
    n = 1
    while max(w, h) / n > TEX_MAX * 1.01:
        n *= 2
    return n, (w, h)


def split_group(tri_ids, cen, P, T, out):
    """三角形太多、或者块太大（乘 kmax 超过 2000 格：低模的长三角形会伸出格子）：沿包围盒长边的中位数一刀两半，直到每份都行"""
    v = P[T[tri_ids].ravel()]
    ext = np.ptp(v, axis=0)
    if len(tri_ids) <= TRI_MAX and ext.max() * KMAX[0] <= 2000:
        out.append(tri_ids)
        return
    if len(tri_ids) == 1:
        raise SystemExit(f'一个三角形就有 {ext.round(1).tolist()} 格大，切不开')
    c = cen[tri_ids]
    ax = 0 if np.ptp(c[:, 0]) >= np.ptp(c[:, 2]) else 2
    o = np.argsort(c[:, ax], kind='stable')
    h = len(o) // 2
    split_group(tri_ids[o[:h]], cen, P, T, out)
    split_group(tri_ids[o[h:]], cen, P, T, out)


def load_img(path, mode):
    im = Image.open(path)
    if mode == 'RGB':
        im = im.convert('RGB')
    elif mode == 'L':
        im = im.convert('L')
    return im


def jpeg(im, q):
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=q, subsampling=0 if q >= 93 else 2, optimize=True)
    return b.getvalue()


def png(im):
    b = io.BytesIO()
    im.save(b, 'PNG', optimize=True)
    return b.getvalue()


def clip_cells(V, T, kc):
    """把跨格线的三角形沿格线切开（Sutherland–Hodgman，每个三角形只和它盖到的那几格求交；新顶点的各项属性线性插值，画出来和原来一样）。
       V：顶点属性 (N, D)；T：三角形 (M, 3)；kc：V 里哪两列是「格坐标」（已经除过格宽，整数线就是格线）。
       返回 (新 V, 新 T, 每个三角形的格 (M', 2))"""
    K = V[:, kc]
    tk = K[T]                                   # (M, 3, 2)
    lo = np.floor(tk.min(1) + 1e-9).astype(np.int64)
    hi = np.floor(tk.max(1) - 1e-9).astype(np.int64)
    inside = (lo == hi).all(1)
    outT = [T[inside]]
    outC = [lo[inside]]
    newV = []
    base = len(V)
    for t in np.nonzero(~inside)[0]:
        poly0 = [V[T[t, 0]], V[T[t, 1]], V[T[t, 2]]]
        for ci in range(lo[t, 0], hi[t, 0] + 1):
            for cj in range(lo[t, 1], hi[t, 1] + 1):
                poly = poly0
                for ax, val, keep_ge in ((kc[0], ci, True), (kc[0], ci + 1, False), (kc[1], cj, True), (kc[1], cj + 1, False)):
                    if len(poly) < 3:
                        break
                    res = []
                    for a_i in range(len(poly)):
                        a, b = poly[a_i], poly[(a_i + 1) % len(poly)]
                        da = (a[ax] - val) if keep_ge else (val - a[ax])
                        db = (b[ax] - val) if keep_ge else (val - b[ax])
                        if da >= 0:
                            res.append(a)
                        if (da >= 0) != (db >= 0):
                            f = da / (da - db)
                            res.append(a + (b - a) * f)
                    poly = res
                if len(poly) < 3:
                    continue
                i0 = base + len(newV)
                newV.extend(poly)
                tris = [(i0, i0 + q, i0 + q + 1) for q in range(1, len(poly) - 1)]
                outT.append(np.array(tris, dtype=np.int64))
                outC.append(np.tile([ci, cj], (len(tris), 1)))
    if newV:
        V = np.vstack([V, np.array(newV)])
    T2 = np.concatenate(outT)
    C2 = np.concatenate(outC)
    # 切出来的细碎三角形（面积几乎为零）去掉
    a, b, c = V[T2[:, 0], :3], V[T2[:, 1], :3], V[T2[:, 2], :3]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
    keep = area > 1e-9 * max(1.0, float(np.ptp(V[:, :3], axis=0).max()) ** 2)
    return V, T2[keep], C2[keep]


KMAX = [1.0]   # 这个源运行时最多再放大几倍（切块时留余量：块乘它不超过 2048 格）


def taper_k(x, z, size, band):
    """离方形边界多远 → 0（边上）～1（band 以内的里面）：smoothstep"""
    d = np.minimum(np.minimum(x + size[0] / 2, size[0] / 2 - x), np.minimum(z + size[2] / 2, size[2] / 2 - z))
    t = np.clip(d / (band * max(size[0], size[2])), 0, 1)
    return t * t * (3 - 2 * t)


def taper(P, N, T, size, flat, band):
    """拼接用：外圈 band（占边长的比例）里高出 flat 的部分平滑压到 flat（边上正好 flat，往里渐渐回到原样）；压过的地方法线按新的面重算"""
    k = taper_k(P[:, 0], P[:, 2], size, band)
    y = P[:, 1]
    ny = np.where(y > flat, flat + (y - flat) * k, y)
    moved = np.abs(ny - y) > 1e-6
    P = P.copy()
    P[:, 1] = ny
    if moved.any():
        a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        fn = np.cross(b - a, c - a)                      # 面积加权
        vn = np.zeros_like(P)
        for q in range(3):
            np.add.at(vn, T[:, q], fn)
        ln = np.linalg.norm(vn, axis=1, keepdims=True)
        vn = vn / np.maximum(ln, 1e-12)
        flip = (vn[:, 1] < 0).sum() > len(vn) / 2      # 绕向反的模型：面法线朝下就整体翻过来
        if flip:
            vn = -vn
        N = N.copy()
        w = (1 - k)[:, None]                             # 边上全用新法线，往里慢慢过渡回原法线
        N[moved] = N[moved] * (1 - w[moved]) + vn[moved] * w[moved]
        N[moved] /= np.maximum(np.linalg.norm(N[moved], axis=1, keepdims=True), 1e-12)
    print(f'   边缘压平：{moved.sum()} / {len(P)} 个顶点（外圈 {band:.0%}，压到 {flat:.0f} 格）')
    return P, N


def convert(key, src_dir):
    S = CFG['sources'][key]
    KMAX[0] = float(S.get('kmax', CFG['kmax']))
    scale, cell = float(S['scale']), float(S['cell'])
    uvgrid = S.get('grid') == 'uv'
    gl = os.path.join(src_dir, key, 'scene.gltf')
    prims, mats = gltfio.load(gl)
    P_all = np.concatenate([p['pos'] for p in prims])
    mn, mx = P_all.min(0), P_all.max(0)
    ctr = np.array([(mn[0] + mx[0]) / 2, mn[1], (mn[2] + mx[2]) / 2])
    size = (mx - mn) * scale
    print(f'== {key}：{len(prims)} 个图元，原尺寸 {np.round(mx - mn, 4).tolist()}，烘焙后 {np.round(size, 1).tolist()} 格')
    # 每种材质：底色切几张（n × n）
    #   地形类（grid = uv：UV 是从上往下的平铺投影）：跨图边界的三角形沿边界切开，每张正好是原图的 1/n，n = 原图边长 / 1024，一点不缩
    #   照片扫描类（UV 是一块块拼的图集）：三角形按重心归到图上，跨界的会把一张图要盖的范围撑大，撑到超过 1024 的就再多切一份，保证每张都不用缩
    minfo = []
    for mi, m in enumerate(mats):
        n, wh = tiles_of(m['base'])
        if m['base'] and not uvgrid:
            W, H = wh
            uvs = [p['uv'][p['idx']] for p in prims if p['mat'] == mi and p['uv'] is not None]
            if uvs:
                tri_uv = np.concatenate(uvs)            # (三角形, 3, 2)
                c = tri_uv.mean(1)
                lo, hi = tri_uv.min(1), tri_uv.max(1)
                while n < 24:
                    t = np.clip(np.floor(c * n), 0, n - 1).astype(np.int64)
                    k = t[:, 0] * n + t[:, 1]
                    bmin = np.full((n * n, 2), np.inf)
                    bmax = np.full((n * n, 2), -np.inf)
                    np.minimum.at(bmin, k, lo)
                    np.maximum.at(bmax, k, hi)
                    ok = np.isfinite(bmin[:, 0])
                    span = (bmax[ok] - bmin[ok]) * np.array([W, H]) + 6
                    if span.max() <= TEX_MAX:
                        break
                    n += 1
        minfo.append(dict(n=n, wh=wh))
        if m['base']:
            print(f'   材质 {m["name"]}：底色 {wh[0]}×{wh[1]} 切成 {n}×{n} 张')
    chunks = []     # { mat, tile, P, N, UV(原 uv), I }
    tile_bb = {}    # (材质, tu, tv) → [umin, vmin, umax, vmax]（这一张图要覆盖的 UV 范围）
    # 同一种材质的图元先并成一份（原模型常把一张网格按 65535 个顶点拆成好几份、空间上交错：不并的话同一格里会切出好几块，有的只有一两个三角形）
    merged = []
    for mi in sorted({p['mat'] for p in prims}, key=lambda v: -1 if v is None else v):
        group = [p for p in prims if p['mat'] == mi]
        off, Ps, Ns, UVs, Ts = 0, [], [], [], []
        has_n = all(p['nrm'] is not None for p in group)
        has_uv = all(p['uv'] is not None for p in group)
        for p in group:
            Ps.append(p['pos'])
            Ns.append(p['nrm'] if has_n else np.zeros_like(p['pos']))
            UVs.append(p['uv'] if has_uv else np.zeros((len(p['pos']), 2)))
            Ts.append(p['idx'] + off)
            off += len(p['pos'])
        merged.append(dict(mat=mi, pos=np.concatenate(Ps), nrm=np.concatenate(Ns) if has_n else None,
                           uv=np.concatenate(UVs) if has_uv else None, idx=np.concatenate(Ts)))
    for p in merged:
        mi = p['mat'] if p['mat'] is not None else -1
        n = minfo[mi]['n'] if mi >= 0 else 1
        P = (p['pos'] - ctr) * scale
        Nn = p['nrm'] if p['nrm'] is not None else np.zeros_like(P)
        if S.get('taper'):
            P, Nn = taper(P, Nn, p['idx'], size, float(S['flat']), float(S['taper']))
        UV = p['uv'] if p['uv'] is not None else np.zeros((len(P), 2))
        if uvgrid and p['uv'] is not None:
            # 一张图再细分 sub × sub 块（零件每边 ≤ 2048 格：乘 kmax 以后也不超）；格坐标就是 UV × n × sub
            sub = max(1, int(math.ceil(max(size[0], size[2]) / n * KMAX[0] / 1990)))
            Kc = UV * (n * sub)
        elif S.get('grid') == 'tile':
            # 照片扫描（图集）、整个模型乘 kmax 也不超过 2048 格：不按空间切，只按图块（每块一张原分辨率的 1024² 图；空间上散开也没事）
            sub = 1
            Kc = np.full((len(P), 2), 0.5)   # 都在第 0 格的正中：不切
        else:
            sub = 1
            Kc = np.stack([(P[:, 0] + size[0] / 2) / cell, (P[:, 2] + size[2] / 2) / cell], 1)
        V = np.hstack([P, Nn, UV, Kc])          # 0..2 位置、3..5 法线、6..7 UV、8..9 格坐标
        V, T, C = clip_cells(V, p['idx'], (8, 9))
        nc = n * sub if uvgrid else 1 << 20
        C = np.clip(C, 0, nc - 1)
        P, Nn, UV = V[:, 0:3], V[:, 3:6], V[:, 6:8]
        Nn = Nn / np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-12)
        if uvgrid and p['uv'] is not None:
            tu, tv = C[:, 0] // sub, C[:, 1] // sub
        elif p['uv'] is not None:
            uvc = UV[T].mean(1)
            tu = np.clip(np.floor(uvc[:, 0] * n), 0, n - 1).astype(np.int64)
            tv = np.clip(np.floor(uvc[:, 1] * n), 0, n - 1).astype(np.int64)
        else:
            tu = tv = np.zeros(len(T), dtype=np.int64)
        cen = P[T].mean(1)
        gkey = ((tu * 64 + tv) * 4096 + (C[:, 0] + 2048)) * 4096 + (C[:, 1] + 2048)
        ug, inv = np.unique(gkey, return_inverse=True)
        order = np.argsort(inv, kind='stable')
        bounds = np.searchsorted(inv[order], np.arange(len(ug) + 1))
        for gi in range(len(ug)):
            ids = order[bounds[gi]:bounds[gi + 1]]
            t_u, t_v = int(tu[ids[0]]), int(tv[ids[0]])
            parts = []
            split_group(ids, cen, P, T, parts)
            for ids2 in parts:
                tri = T[ids2]
                used, remap = np.unique(tri.ravel(), return_inverse=True)
                I = remap.reshape(-1, 3)
                chunks.append(dict(mat=mi, tile=(t_u, t_v), P=P[used], N=(Nn[used] if p['nrm'] is not None else None),
                                   UV=(UV[used] if p['uv'] is not None else None), I=I))
                if p['uv'] is not None:
                    k = (mi, t_u, t_v)
                    if uvgrid:
                        tile_bb[k] = [t_u / n, t_v / n, (t_u + 1) / n, (t_v + 1) / n]
                    else:
                        uv = UV[used]
                        b = tile_bb.get(k)
                        lo, hi = uv.min(0), uv.max(0)
                        tile_bb[k] = [min(b[0], lo[0]), min(b[1], lo[1]), max(b[2], hi[0]), max(b[3], hi[1])] if b else [lo[0], lo[1], hi[0], hi[1]]
    # 每一张图：裁出覆盖的 UV 范围（外扩 2 像素），超过 1024 的等比缩到 1024
    tex_cache = {}

    def img_of(path, mode):
        kk = (path, mode)
        if kk not in tex_cache:
            tex_cache[kk] = load_img(path, mode)
        return tex_cache[kk]

    tiles = {}   # (mi, tu, tv) → { crop: (u0, v0, u1, v1) 归一化, imgs: {base, nrm, mr} 字节 }
    for k, b in sorted(tile_bb.items()):
        mi = k[0]
        m = mats[mi]
        if not m['base']:   # 没贴图的材质（底座）：下面配纯色图
            continue
        W, H = minfo[mi]['wh']
        pad = 0 if CFG['sources'][key].get('grid') == 'uv' else 2
        x0 = max(0, int(math.floor(b[0] * W + 1e-6)) - pad)
        y0 = max(0, int(math.floor(b[1] * H + 1e-6)) - pad)
        x1 = min(W, int(math.ceil(b[2] * W - 1e-6)) + pad)
        y1 = min(H, int(math.ceil(b[3] * H - 1e-6)) + pad)
        crop = (x0 / W, y0 / H, x1 / W, y1 / H)
        imgs = {}
        for nm, path, mode in (('base', m['base'], 'RGB'), ('nrm', m['nrm'], 'RGB'), ('mr', m['mr'], 'RGB')):
            if not path:
                continue
            im = img_of(path, mode)
            w2, h2 = im.size
            box = (int(round(crop[0] * w2)), int(round(crop[1] * h2)), int(round(crop[2] * w2)), int(round(crop[3] * h2)))
            c = im.crop(box)
            if max(c.size) > TEX_MAX:
                f = TEX_MAX / max(c.size)
                c = c.resize((max(1, round(c.size[0] * f)), max(1, round(c.size[1] * f))), Image.LANCZOS)
            if nm == 'base':
                gray = np.asarray(c).std(axis=2).mean() < 0.5   # 灰度底色（Snowy Mountain V2）：存成灰度图省一半
                imgs[nm] = ('image/jpeg', jpeg(c.convert('L') if gray else c, 92))
            elif nm == 'nrm':
                imgs[nm] = ('image/jpeg', jpeg(c, 95))
            else:   # 金属度粗糙度：G 粗糙度、B 金属度（地形不发亮：金属度清零）
                a = np.asarray(c).copy()
                a[..., 2] = 0
                a[..., 0] = 0
                imgs[nm] = ('image/jpeg', jpeg(Image.fromarray(a), 90))
        tiles[k] = dict(crop=crop, imgs=imgs, px=(x1 - x0, y1 - y0))
    # 没贴图的材质（岩石实拍的底座 Base）：Roblox 导入不认 glTF 的底色系数，配一张 8×8 的纯色图
    solid = {}
    for mi, m in enumerate(mats):
        if not m['base']:
            f = m['factor'] or [0.5, 0.5, 0.5, 1]
            c = tuple(int(max(0, min(1, v)) ** (1 / 2.2) * 255) for v in f[:3])
            solid[mi] = png(Image.new('RGB', (8, 8), c))
    return dict(key=key, size=size, chunks=chunks, tiles=tiles, mats=mats, solid=solid, minfo=minfo)


def write_glb(R, out_path):
    key = R['key']
    J = dict(asset=dict(version='2.0', generator='全面大战场 tools/snow/peaks.py'), scene=0, scenes=[dict(name='P_' + key, nodes=[])],
             nodes=[], meshes=[], materials=[], textures=[], images=[], samplers=[dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)],
             accessors=[], bufferViews=[], buffers=[])
    BIN = bytearray()

    def view(data, target=None):
        while len(BIN) % 4:
            BIN.append(0)
        o = len(BIN)
        BIN.extend(data)
        v = dict(buffer=0, byteOffset=o, byteLength=len(data))
        if target:
            v['target'] = target
        J['bufferViews'].append(v)
        return len(J['bufferViews']) - 1

    def accessor(arr, ctype, typ, target, minmax=False):
        a = dict(bufferView=view(arr.tobytes(), target), componentType=ctype, count=int(arr.shape[0]), type=typ)
        if minmax:
            a['min'] = arr.min(0).astype(float).tolist()
            a['max'] = arr.max(0).astype(float).tolist()
        J['accessors'].append(a)
        return len(J['accessors']) - 1

    img_index = {}

    def image(mime, data):
        h = (mime, hash(data))
        if h in img_index:
            return img_index[h]
        J['images'].append(dict(bufferView=view(data), mimeType=mime))
        J['textures'].append(dict(sampler=0, source=len(J['images']) - 1))
        img_index[h] = len(J['textures']) - 1
        return img_index[h]

    mat_index = {}

    def material(mi, tile):
        k = (mi, tile)
        if k in mat_index:
            return mat_index[k]
        m = R['mats'][mi] if mi >= 0 else None
        name = f'P_{key}_m{max(mi, 0)}_{tile[0]}_{tile[1]}'
        M = dict(name=name, pbrMetallicRoughness=dict(metallicFactor=0.0, roughnessFactor=1.0), doubleSided=False)
        T = R['tiles'].get((mi, tile[0], tile[1]))
        if T and 'base' in T['imgs']:
            M['pbrMetallicRoughness']['baseColorTexture'] = dict(index=image(*T['imgs']['base']))
            if 'mr' in T['imgs']:
                M['pbrMetallicRoughness']['metallicRoughnessTexture'] = dict(index=image(*T['imgs']['mr']))
            else:
                M['pbrMetallicRoughness']['roughnessFactor'] = 0.9 if m is None or m['rough'] is None else float(m['rough'])
            if 'nrm' in T['imgs']:
                M['normalTexture'] = dict(index=image(*T['imgs']['nrm']), scale=float(m['nscale'] or 1.0))
        elif mi in R['solid']:
            M['pbrMetallicRoughness']['baseColorTexture'] = dict(index=image('image/png', R['solid'][mi]))
            M['pbrMetallicRoughness']['roughnessFactor'] = 0.95
        J['materials'].append(M)
        mat_index[k] = len(J['materials']) - 1
        return mat_index[k]

    meta = []
    for ci, c in enumerate(R['chunks']):
        P = c['P']
        lo, hi = P.min(0), P.max(0)
        cen = (lo + hi) / 2
        rel = (P - cen).astype(np.float32)
        attrs = dict(POSITION=accessor(rel, 5126, 'VEC3', 34962, True))
        if c['N'] is not None:
            attrs['NORMAL'] = accessor(c['N'].astype(np.float32), 5126, 'VEC3', 34962)
        T = R['tiles'].get((c['mat'], c['tile'][0], c['tile'][1]))
        if c['UV'] is not None and T:
            u0, v0, u1, v1 = T['crop']
            uv = np.stack([(c['UV'][:, 0] - u0) / (u1 - u0), (c['UV'][:, 1] - v0) / (v1 - v0)], 1).astype(np.float32)
            attrs['TEXCOORD_0'] = accessor(uv, 5126, 'VEC2', 34962)
        elif c['UV'] is not None:
            attrs['TEXCOORD_0'] = accessor(c['UV'].astype(np.float32), 5126, 'VEC2', 34962)
        I = c['I'].ravel()
        idx = accessor(I.astype(np.uint16 if len(P) < 65536 else np.uint32).reshape(-1, 1), 5123 if len(P) < 65536 else 5125, 'SCALAR', 34963)
        name = f'P_{key}__c{ci:03d}'
        J['meshes'].append(dict(name=name, primitives=[dict(attributes=attrs, indices=idx, material=material(c['mat'], c['tile']), mode=4)]))
        J['nodes'].append(dict(name=name, mesh=len(J['meshes']) - 1, translation=cen.astype(float).tolist()))
        J['scenes'][0]['nodes'].append(len(J['nodes']) - 1)
        sz = hi - lo
        if max(sz[0], sz[1], sz[2]) * KMAX[0] > 2048:
            raise SystemExit(f'{name} 大小 {sz.round(1).tolist()}：乘 kmax 以后超过 2048 格，cell 再切小一点')
        if len(c['I']) > TRI_MAX:
            raise SystemExit(f'{name} 有 {len(c["I"])} 个三角形')
        meta.append(dict(name=f'c{ci:03d}', c=cen.tolist(), s=sz.tolist(), tris=int(len(c['I']))))
    J['buffers'].append(dict(byteLength=len(BIN)))
    js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode()
    while len(js) % 4:
        js += b' '
    while len(BIN) % 4:
        BIN.append(0)
    with open(out_path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(BIN)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(BIN), 0x004E4942))
        f.write(bytes(BIN))
    return meta, len(J['images'])


def main():
    src_dir = sys.argv[1]
    keys = sys.argv[2:] or list(CFG['sources'].keys())
    os.makedirs(os.path.join(ROOT, 'models', 'snow'), exist_ok=True)
    mpath = os.path.join(ROOT, 'tools', 'snow', 'peaks_meta.json')
    allmeta = json.load(open(mpath)) if os.path.exists(mpath) else {}
    for key in keys:
        R = convert(key, src_dir)
        out = os.path.join(ROOT, 'models', 'snow', key + '.glb')
        meta, nimg = write_glb(R, out)
        tris = sum(m['tris'] for m in meta)
        print(f'   {len(meta)} 块、{tris} 个三角形、{nimg} 张贴图（{", ".join(sorted({f"{t["px"][0]}×{t["px"][1]}" for t in R["tiles"].values()}))}）→ {out}（{os.path.getsize(out) / 1e6:.1f} MB）')
        allmeta[key] = dict(size=R['size'].tolist(), tris=tris, kmax=KMAX[0], chunks=meta)
        json.dump(allmeta, open(mpath, 'w'), ensure_ascii=False, indent=0)
    # Luau 元数据（运行时摆山、检查导入全没全）
    r = lambda x: round(float(x), 2)  # noqa: E731
    L = ['-- 雪山地图谷外的山体（tools/snow/peaks.py 生成，别手改）：models/snow/<键>.glb 里每一块 P_<键>__c<号>',
         '--   size 整个山体烘焙后的大小（格，x、z 居中、最低点 y = 0）；chunks 每块的中心 c、大小 s（同一坐标）、三角形数 n',
         'return {']
    for key in CFG['sources']:
        if key not in allmeta:
            continue
        A = allmeta[key]
        S = CFG['sources'][key]
        L.append(f'  {key} = {{ size = {{ {", ".join(str(r(v)) for v in A["size"])} }}, tris = {A["tris"]}, kmax = {A.get("kmax", 1)}, credit = "「{S["name"]}」{S["author"]}（Sketchfab，CC-BY 4.0）", chunks = {{')
        for m in A['chunks']:
            L.append(f'    {{ "{m["name"]}", {r(m["c"][0])}, {r(m["c"][1])}, {r(m["c"][2])}, {r(m["s"][0])}, {r(m["s"][1])}, {r(m["s"][2])}, {m["tris"]} }},')
        L.append('  } },')
    L.append('}')
    open(os.path.join(ROOT, 'src', 'ReplicatedStorage', 'SnowPeaksMeta.lua'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print('写好了 src/ReplicatedStorage/SnowPeaksMeta.lua')


if __name__ == '__main__':
    main()
