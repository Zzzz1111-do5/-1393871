# 烘焙蒙皮贴图（用户 11-18：「为什么导入进去画质就一般」「按照 3A 游戏的标准把这款游戏做到惊艳，参考战雷」）——成品 GLB 的最后一道加工（doorbay.py 之后）
#   airpaint.py 涂的是一张 7 格的调色板：整架飞机每块是一个平平的颜色，没有缝隙阴影、面板线、深浅，Roblox 里看着像塑料玩具。
#   这里给涂过的蒙皮重新展一张独立的 UV（xatlas：每个三角形在贴图上有自己的一块），按调色板的颜色烘焙一张 1024 的底色 + 一张金属度 / 粗糙度：
#   · 缝隙阴影（环境光遮蔽）：每个像素往外半球打射线（embree），被机身挡住多的地方暗——机翼根部、进气道、鸭翼下面、舱门缝、垂尾之间
#   · 面板线：沿机身站位（前后）、翼展 / 水线方向的一格一格接缝（随机断开、错开），一部分格子里加检修口盖的方框；线上暗一点、糙一点
#   · 一块块深浅不一的蒙皮（隐身涂层补漆的样子，歼-20、F-22 的照片上很明显）+ 大尺度的轻微斑驳 + 细颗粒；上表面顺着气流的淡淡污迹
#   · 尾喷口周围的烟熏
#   只烘涂了调色板、不透明的材质；发光灯带（游戏里换成 Neon）、玻璃、起落架、舱、进气道管道不动。所有涂过的块合成一种材质（一张贴图）。
#   依赖：pip install trimesh embreex xatlas pillow（只有这一步要）
#   用法：python3 tools/models/skinbake.py <模型键，如 j20> [GLB，默认 models/air/<键>.glb] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua] [预览图目录]
import io, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import airpaint   # noqa: E402
import mdl2glb as B   # noqa: E402

S = 2.8   # 米 → 格
SPEC = {
    'j20': {
        'key': 'j20_v4', 'paint': 'j20', 'res': 1024, 'pages': 3,   # 3 页 1024：一个像素约 1.6 厘米（Roblox 贴图最大 1024）
        # 面板线：站位间距（前后，米）、翼展 / 水线间距、断开的比例、检修口盖的比例、线宽（米）、线上的明暗
        'panel': {'lz': 1.25, 'lx': 1.1, 'ly': 0.85, 'keep': 0.72, 'hatch': 0.2, 'w': 0.02, 'dark': 0.72},
        'ao': {'rays': 24, 'dist': 9.0, 'k': 0.78},
        'tone': 0.045, 'mottle': 0.025, 'grain': 0.012, 'streak': 0.03,
        'soot': {'r': 2.4, 'k': 0.5},
        'nolines': ['radome', 'nozzle', 'nozzle_in', 'dark', 'lens'],   # 调色板里这几格不画面板线
    },
}


def hash3(a, b, c):
    """整数三元组 → [0, 1) 的伪随机数（向量化）"""
    h = (np.asarray(a, np.int64) * 73856093) ^ (np.asarray(b, np.int64) * 19349663) ^ (np.asarray(c, np.int64) * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0x1000000)


def vnoise(P, scale, seed=0):
    """三维值噪声（三线性插值），P：(n,3) 米，scale：一格多少米 → [-1, 1]"""
    q = P / scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * hash3(i[:, 0] + dx + seed * 101, i[:, 1] + dy, i[:, 2] + dz)
    return out * 2 - 1


def raster(UV, H, W):
    """UV：(F,3,2) 像素坐标。返回每个像素是哪个三角形（-1 空）、重心坐标"""
    fid = np.full((H, W), -1, np.int64)
    bary = np.zeros((H, W, 3), np.float32)
    x0 = np.clip(np.floor(UV[:, :, 0].min(1) - 0.5).astype(int), 0, W - 1)
    x1 = np.clip(np.ceil(UV[:, :, 0].max(1) - 0.5).astype(int), 0, W - 1)
    y0 = np.clip(np.floor(UV[:, :, 1].min(1) - 0.5).astype(int), 0, H - 1)
    y1 = np.clip(np.ceil(UV[:, :, 1].max(1) - 0.5).astype(int), 0, H - 1)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    A, Bv, C = UV[:, 0], UV[:, 1], UV[:, 2]
    den = (Bv[:, 1] - C[:, 1]) * (A[:, 0] - C[:, 0]) + (C[:, 0] - Bv[:, 0]) * (A[:, 1] - C[:, 1])
    ok = np.abs(den) > 1e-12

    def fill(idx, gw, gh):
        gx, gy = np.meshgrid(np.arange(gw), np.arange(gh))
        gx, gy = gx.ravel(), gy.ravel()
        px = x0[idx, None] + gx[None, :]
        py = y0[idx, None] + gy[None, :]
        cx, cy = px + 0.5, py + 0.5
        a, b, c, d = A[idx], Bv[idx], C[idx], den[idx][:, None]
        l0 = ((b[:, None, 1] - c[:, None, 1]) * (cx - c[:, None, 0]) + (c[:, None, 0] - b[:, None, 0]) * (cy - c[:, None, 1])) / d
        l1 = ((c[:, None, 1] - a[:, None, 1]) * (cx - c[:, None, 0]) + (a[:, None, 0] - c[:, None, 0]) * (cy - c[:, None, 1])) / d
        l2 = 1 - l0 - l1
        inside = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4) & (px <= x1[idx, None]) & (py <= y1[idx, None])
        r, c_ = np.nonzero(inside)
        fid[py[r, c_], px[r, c_]] = idx[r]
        bary[py[r, c_], px[r, c_]] = np.stack([l0[r, c_], l1[r, c_], l2[r, c_]], 1)

    small = ok & (w <= 12) & (h <= 12)
    for gw in range(1, 13):
        for gh in range(1, 13):
            idx = np.nonzero(small & (w == gw) & (h == gh))[0]
            if len(idx):
                fill(idx, gw, gh)
    for i in np.nonzero(ok & ~small)[0]:
        fill(np.array([i]), w[i], h[i])
    return fid, bary


def dilate(img, mask, n):
    """把有内容的像素往外扩 n 圈（UV 接缝处取样不出黑边）"""
    img, mask = img.copy(), mask.copy()
    for _ in range(n):
        acc = np.zeros(img.shape, np.float64)
        cnt = np.zeros(mask.shape, np.float64)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            m = np.roll(np.roll(mask, dy, 0), dx, 1)
            v = np.roll(np.roll(img, dy, 0), dx, 1)
            acc += v * m[..., None] if img.ndim == 3 else v * m
            cnt += m
        grow = (~mask) & (cnt > 0)
        if img.ndim == 3:
            img[grow] = (acc[grow] / cnt[grow][:, None])
        else:
            img[grow] = acc[grow] / cnt[grow]
        mask = mask | grow
    return img


def png_rgb(arr):
    from PIL import Image
    b = io.BytesIO()
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').save(b, 'PNG', optimize=True)
    return b.getvalue()


def layers(spec, pspec, pal, info, pos, nrm, fc, ao, texel):
    """一页贴图上每个像素的底色（线性）、粗糙度、金属度：调色板的颜色 × 缝隙阴影 × 面板线 × 深浅 × 污迹 × 烟熏"""
    palc = np.array([pspec['pal'][k][0] for k in pal], np.float64) / 255.0
    palm = np.array([pspec['pal'][k][1] for k in pal], np.float64)
    palr = np.array([pspec['pal'][k][2] for k in pal], np.float64)
    met = palm[fc].copy()
    rou = palr[fc].copy()
    Pm = pos / S   # 米
    nolines = np.isin(np.array(pal)[fc], spec.get('nolines', []))
    PS = spec['panel']
    lz, lx, ly = PS['lz'], PS['lx'], PS['ly']
    jit = lambda k, sd: (hash3(k, sd, 7) - 0.5) * 0.35   # 每条线错开一点

    def lineDist(c, L, sd):
        k = np.floor(c / L)
        a = k * L + jit(k, sd) * L
        b2 = (k + 1) * L + jit(k + 1, sd) * L
        da, db = np.abs(c - a), np.abs(b2 - c)
        return np.minimum(da, db), np.where(da < db, k, k + 1), np.floor((c - a) / L)

    an = np.abs(nrm)
    top = an[:, 1] >= np.maximum(an[:, 0], an[:, 2])            # 上下表面：站位线 + 翼展线
    side = (an[:, 0] > an[:, 1]) & (an[:, 0] >= an[:, 2])        # 侧面：站位线 + 水线
    dz, kz, cz = lineDist(Pm[:, 2], lz, 1)
    dx, kx, cx = lineDist(np.abs(Pm[:, 0]), lx, 2)   # 左右对称（|X|）
    dy, ky, cy = lineDist(Pm[:, 1], ly, 3)
    d2 = np.where(top, dx, np.where(side, dy, dx))
    k2 = np.where(top, kx, np.where(side, ky, kx))
    c2 = np.where(top, cx, np.where(side, cy, cx))
    fam = np.where(top, 2, np.where(side, 3, 4))
    keepZ = hash3(kz, c2, fam) < PS['keep']      # 站位线这一段（在第 c2 格里）留不留
    keep2 = hash3(k2, cz, fam + 10) < PS['keep']
    dl = np.minimum(np.where(keepZ, dz, 9), np.where(keep2, d2, 9))
    hatch = hash3(cz, c2, fam + 20) < PS['hatch']   # 检修口盖：格子里一个缩进的小方框
    fz = (Pm[:, 2] / lz) - cz
    f2 = np.where(top, np.abs(Pm[:, 0]) / lx, np.where(side, Pm[:, 1] / ly, np.abs(Pm[:, 0]) / lx)) - c2
    inset = 0.18 + 0.2 * hash3(cz, c2, fam + 30)
    inZ = (fz > inset) & (fz < 1 - inset)
    in2 = (f2 > inset) & (f2 < 1 - inset)
    dh = np.minimum(np.where(in2, np.minimum(np.abs(fz - inset), np.abs(fz - (1 - inset))) * lz, 9),
                    np.where(inZ, np.minimum(np.abs(f2 - inset), np.abs(f2 - (1 - inset))) * np.where(top, lx, ly), 9))
    dl = np.where(hatch, np.minimum(dl, dh), dl)
    lineK = np.clip(1 - (dl - PS['w'] / 2) / max(1.5 * texel, 1e-4), 0, 1)   # 边缘按一个半像素过渡（线细于像素也不碎成点）
    lineK[nolines] = 0
    tone = 1 + spec['tone'] * (hash3(cz, c2, fam + 40) * 2 - 1)   # 一块块深浅
    tone[nolines] = 1
    mott = 1 + spec['mottle'] * vnoise(Pm, 2.5, 1) + spec['grain'] * vnoise(Pm, 0.08, 2)
    st = vnoise(Pm * np.array([6.0, 6.0, 0.35]), 1.0, 3)          # 顺着气流的污迹
    streak = 1 - spec['streak'] * np.clip(st, 0, 1) * (nrm[:, 1] > 0.3)
    soot = np.zeros(len(pos))
    SO = spec['soot']
    for nz in info.get('noz') or []:
        d = np.linalg.norm(pos - np.array(nz[:3]), axis=1)
        soot = np.maximum(soot, np.clip(1 - d / (SO['r'] * nz[3] + 1e-6), 0, 1) ** 1.6)
    aoK = 1 - spec['ao']['k'] * (1 - ao)
    shade = aoK * tone * mott * streak * (1 - (1 - PS['dark']) * lineK) * (1 - SO['k'] * soot)
    # 调色板的颜色是 sRGB：明暗在线性空间乘
    base = palc[fc]
    lin = np.where(base <= 0.04045, base / 12.92, ((base + 0.055) / 1.055) ** 2.4) * shade[:, None]
    rou = np.clip(rou + 0.06 * (tone - 1) / max(spec['tone'], 1e-6) * 0.5 + 0.12 * lineK + 0.2 * soot + 0.08 * (1 - ao), 0.05, 1)
    met = np.clip(met * (1 - 0.4 * soot), 0, 1)
    return lin, rou, met, lineK


def twins(P, I):
    """同一块里位置完全一样的三角形（舱门、单层板补的反面）：返回 主三角形的掩码、每个三角形对应的主三角形、角的对应"""
    T = np.round(P[I] / 1e-3).astype(np.int64)
    key = np.sort(T.view([('a', np.int64), ('b', np.int64), ('c', np.int64)]).reshape(len(I), 3), axis=1).view(np.int64).reshape(len(I), 9)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    prim = first[inv.ravel()]
    isP = prim == np.arange(len(I))
    corner = np.tile(np.arange(3), (len(I), 1))   # 这个三角形第 j 个角 = 主三角形的第 corner[j] 个角
    for t in np.nonzero(~isP)[0]:
        p = prim[t]
        for j in range(3):
            corner[t, j] = int(np.argmin(np.abs(T[p] - T[t, j]).sum(1)))
    return isP, prim, corner


def bake(nm, glb, meta_path, preview=None, log=print):
    import trimesh
    import xatlas
    from doorbay import put
    spec = SPEC[nm]
    key = spec['key']
    pspec = airpaint.PAINT[spec['paint']]
    pal = list(pspec['pal'])
    J, BIN = glbfix.read(glb)
    BIN = bytearray(BIN)
    lines = open(meta_path, encoding='utf-8').read().split('\n')
    li = next(k for k, l in enumerate(lines) if l.startswith('    %s = {' % key))
    info = airpaint.lua_parse(lines[li].strip()[len(key) + 3:].rstrip(','))
    if info.get('skin'):
        log('  %s 已经烘焙过（元数据 skin），跳过' % key)
        return
    W = glbfix.world_mats(J)
    # 调色板贴图（airpaint 加的 A_<键>_paint）用到它的材质：要烘的；发光灯带的材质除外
    pimg = next((i for i, im in enumerate(J.get('images', [])) if im.get('name') == 'A_%s_paint' % key), None)
    ptex = {t for t, tx in enumerate(J.get('textures', [])) if tx.get('source') == pimg}
    glowm = {'A_%s_%s' % (key, g) for g in pspec.get('glow', [])}
    bakeM = set()
    for mi, m in enumerate(J['materials']):
        bt = (m.get('pbrMetallicRoughness') or {}).get('baseColorTexture')
        if bt and bt.get('index') in ptex and m.get('alphaMode') != 'BLEND' and m.get('name') not in glowm:
            bakeM.add(mi)
    items = []   # 要烘的块：{ ni, pr, P 世界坐标, N, I, cell, isP, prim, corner, area }
    occ = []     # 挡光的三角形（世界坐标）：不透明的都算
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W:
            continue
        M = W[ni]
        for pr in J['meshes'][nd['mesh']]['primitives']:
            mi = pr.get('material', -1)
            att = pr['attributes']
            P = glbfix.acc_read(J, BIN, att['POSITION']).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
            I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            if mi < 0 or J['materials'][mi].get('alphaMode') != 'BLEND':
                occ.append(P[I])
            if mi in bakeM:
                N = glbfix.acc_read(J, BIN, att['NORMAL']).astype(np.float64) @ M[:3, :3].T
                N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
                UV0 = glbfix.acc_read(J, BIN, att['TEXCOORD_0']).astype(np.float64)
                cell = np.clip((UV0[I].mean(1)[:, 0] * len(pal)).astype(int), 0, len(pal) - 1)
                isP, prim, corner = twins(P, I)
                T = P[I]
                a = 0.5 * np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1)
                items.append({'ni': ni, 'pr': pr, 'P': P, 'N': N, 'I': I, 'cell': cell, 'isP': isP, 'prim': prim, 'corner': corner,
                              'area': a[isP].sum()})
    if not items:
        log('  %s：没有调色板涂的块' % key)
        return
    res, pages = spec.get('res', 1024), spec.get('pages', 3)
    # 按面积把块分进几页（大的先放、放进最空的一页）
    load = [0.0] * pages
    for it in sorted(items, key=lambda x: -x['area']):
        k = int(np.argmin(load))
        it['page'] = k
        load[k] += it['area']
    occT = np.concatenate(occ)
    mesh = trimesh.Trimesh(occT.reshape(-1, 3), np.arange(len(occT) * 3).reshape(-1, 3), process=False)
    ray = trimesh.ray.ray_pyembree.RayMeshIntersector(mesh)
    log('  %s：%d 块、%d 个三角形（同位置的反面 %d 个共用贴图），分 %d 页 %d×%d' % (key, len(items), sum(len(it['I']) for it in items),
        sum(int((~it['isP']).sum()) for it in items), pages, res, res))
    AOS = spec['ao']
    rng = np.random.default_rng(11)
    texs = []
    for pg in range(pages):
        grp = [it for it in items if it['page'] == pg]
        if not grp:
            texs.append(None)
            continue
        Ps, Ns, Fs, cells, off = [], [], [], [], 0
        for it in grp:
            Fp = it['I'][it['isP']]
            Ps.append(it['P']); Ns.append(it['N']); Fs.append(Fp + off); cells.append(it['cell'][it['isP']])
            it['off'] = off
            off += len(it['P'])
        P, N, F, cell = np.concatenate(Ps), np.concatenate(Ns), np.concatenate(Fs), np.concatenate(cells)
        A_st = 0.5 * np.linalg.norm(np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]]), axis=1).sum()
        fill = 0.72
        while True:
            atlas = xatlas.Atlas()
            atlas.add_mesh(P.astype(np.float32), F.astype(np.uint32), N.astype(np.float32))
            co, po = xatlas.ChartOptions(), xatlas.PackOptions()
            co.max_cost = 6   # 允许大一点的展开块（默认 2：二十多万个三角形碎成几千块，边距浪费一大半）
            po.resolution, po.padding, po.bilinear, po.bruteForce = res, 3, True, False
            po.texels_per_unit = float(np.sqrt(fill * res * res / A_st))
            atlas.generate(co, po)
            if atlas.atlas_count <= 1 and atlas.width <= res and atlas.height <= res:
                break
            fill *= 0.9
        vmap, F2, UV = atlas[0]
        vmap, F2 = vmap.astype(np.int64), F2.astype(np.int64)
        Ww, Hh = atlas.width, atlas.height
        UVp = UV[F2] * np.array([Ww, Hh])
        fid, bary = raster(UVp, Hh, Ww)
        mask = fid >= 0
        ys, xs = np.nonzero(mask)
        f = fid[ys, xs]
        b = bary[ys, xs].astype(np.float64)
        pos = (P[vmap][F2[f]] * b[:, :, None]).sum(1)
        nrm = (N[vmap][F2[f]] * b[:, :, None]).sum(1)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        texel = 1 / po.texels_per_unit / S   # 一个像素多少米
        # 缝隙阴影：每个像素往外的余弦半球打 rays 条射线，挡住的按距离加权
        occl = np.zeros(len(pos))
        t_ = np.cross(nrm, np.where(np.abs(nrm[:, :1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]])))
        t_ /= np.linalg.norm(t_, axis=1, keepdims=True)
        bt = np.cross(nrm, t_)
        for k in range(AOS['rays']):
            u1, u2 = rng.random(len(pos)), rng.random(len(pos))
            r_, ph = np.sqrt(u1), 2 * np.pi * u2
            d = t_ * (r_ * np.cos(ph))[:, None] + bt * (r_ * np.sin(ph))[:, None] + nrm * np.sqrt(1 - u1)[:, None]
            org = pos + nrm * 0.02
            CH = 400000
            for s0 in range(0, len(org), CH):
                o_, d_ = org[s0:s0 + CH], d[s0:s0 + CH]
                tri, ridx, loc = ray.intersects_id(o_, d_, multiple_hits=False, return_locations=True)
                if len(ridx):
                    dist = np.linalg.norm(loc - o_[ridx], axis=1)
                    occl[s0 + ridx] += np.clip(1 - dist / AOS['dist'], 0, 1) ** 1.5
        ao = 1 - occl / AOS['rays']
        lin, rou, met, lineK = layers(spec, pspec, pal, info, pos, nrm, cell[f], ao, texel)
        srgb = lambda c: np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(np.clip(c, 0, None), 1 / 2.4) - 0.055)
        colImg = np.zeros((res, res, 3))
        mrImg = np.zeros((res, res, 3))
        colImg[ys, xs] = srgb(lin) * 255
        mrImg[ys, xs, 0] = 255
        mrImg[ys, xs, 1] = rou * 255
        mrImg[ys, xs, 2] = met * 255
        m2 = np.zeros((res, res), bool)
        m2[ys, xs] = True
        colImg = dilate(colImg, m2, 8)
        mrImg = dilate(mrImg, m2, 8)
        log('    第 %d 页：%d 块、%d 个三角形，一个像素 %.1f 厘米，填了 %.0f%%，缝隙阴影平均 %.2f，面板线 %.1f%%' % (
            pg + 1, len(grp), len(F), texel * 100, 100 * mask.sum() / (res * res), ao.mean(), 100 * (lineK > 0.3).mean()))
        if preview:
            os.makedirs(preview, exist_ok=True)
            from PIL import Image
            Image.fromarray(np.clip(colImg, 0, 255).astype(np.uint8)).save(os.path.join(preview, '%s_skin%d.png' % (key, pg + 1)))
        UVn = UV * np.array([Ww / res, Hh / res])   # 贴图补成 res × res：UV 按比例缩
        texs.append({'col': colImg, 'mr': mrImg, 'vmap': vmap, 'F2': F2, 'UV': UVn, 'grp': grp})
    # —— 改 GLB：每页一种材质（两张贴图），涂过的块换成新 UV ——
    def add_image(data, name):
        while len(BIN) % 4:
            BIN.append(0)
        J['bufferViews'].append({'buffer': 0, 'byteOffset': len(BIN), 'byteLength': len(data)})
        BIN.extend(data)
        J.setdefault('images', []).append({'bufferView': len(J['bufferViews']) - 1, 'mimeType': 'image/png', 'name': name})
        J.setdefault('samplers', []).append({'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071})
        J.setdefault('textures', []).append({'source': len(J['images']) - 1, 'sampler': len(J['samplers']) - 1})
        return len(J['textures']) - 1
    for pg, tx in enumerate(texs):
        if not tx:
            continue
        tC = add_image(png_rgb(tx['col']), 'A_%s_skin%d' % (key, pg + 1))
        tM = add_image(png_rgb(tx['mr']), 'A_%s_skin%d_mr' % (key, pg + 1))
        J['materials'].append({'name': 'A_%s_skin%d' % (key, pg + 1), 'doubleSided': False,
                               'pbrMetallicRoughness': {'baseColorTexture': {'index': tC}, 'metallicRoughnessTexture': {'index': tM},
                                                        'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 1, 'roughnessFactor': 1}})
        sm = len(J['materials']) - 1
        vmap, F2, UV = tx['vmap'], tx['F2'], tx['UV']
        fp = 0
        for it in tx['grp']:
            pr, o0 = it['pr'], it['off']
            nP = int(it['isP'].sum())
            rowsP = F2[fp:fp + nP]   # 这一块的主三角形（新顶点编号）
            fp += nP
            used = np.unique(rowsP)
            loc = np.full(len(vmap), -1, np.int64)
            loc[used] = np.arange(len(used))
            src = vmap[used] - o0
            nU = len(used)
            # 主三角形在 isP 里的顺序 → 新的三角形（顶点在 used 里的编号）
            Ip = it['I']
            pidx = np.nonzero(it['isP'])[0]
            newF = np.zeros((len(Ip), 3), np.int64)
            newF[pidx] = loc[rowsP]
            # 反面：每个角新复制一个顶点（自己的位置、法线），UV 用主三角形对应那个角的
            tw = np.nonzero(~it['isP'])[0]
            tsrc = Ip[tw].reshape(-1)
            ppos = np.searchsorted(pidx, it['prim'][tw])
            tuv = UV[used][newF[pidx][ppos][np.arange(len(tw))[:, None], it['corner'][tw]]].reshape(-1, 2) if len(tw) else np.zeros((0, 2))
            newF[tw] = (nU + np.arange(len(tw) * 3)).reshape(-1, 3)
            att = pr['attributes']
            for a in list(att):
                arr = glbfix.acc_read(J, BIN, att[a])
                if a == 'TEXCOORD_0':
                    arr = np.concatenate([UV[used], tuv]).astype(np.float32)
                else:
                    arr = np.concatenate([arr[src], arr[tsrc]])
                comp, typ = J['accessors'][att[a]]['componentType'], J['accessors'][att[a]]['type']
                dt = {5126: '<f4', 5123: '<u2', 5121: 'u1', 5125: '<u4'}[comp]
                att[a] = put(J, BIN, np.ascontiguousarray(arr, dt), typ, comp, a == 'POSITION')
            pr['indices'] = put(J, BIN, np.ascontiguousarray(newF.reshape(-1), '<u4'), 'SCALAR', 5125)
            pr['material'] = sm
    # 旧的访问器、bufferView 去掉，重新紧凑地排（同 doorbay.py）；没人用的材质、贴图不删（编号会乱；调色板贴图发光灯带还在用）
    usedA = sorted({i for m in J['meshes'] for p in m['primitives'] for i in list(p['attributes'].values()) + [p['indices']]})
    amap = {old: k for k, old in enumerate(usedA)}
    J['accessors'] = [J['accessors'][i] for i in usedA]
    for m in J['meshes']:
        for p in m['primitives']:
            p['attributes'] = {k: amap[v] for k, v in p['attributes'].items()}
            p['indices'] = amap[p['indices']]
    usedV = sorted({a['bufferView'] for a in J['accessors']} | {im['bufferView'] for im in J.get('images', []) if 'bufferView' in im})
    vmap2, NB, views = {}, bytearray(), []
    for old in usedV:
        v = dict(J['bufferViews'][old])
        while len(NB) % 4:
            NB.append(0)
        o = v.get('byteOffset', 0)
        NB.extend(BIN[o:o + v['byteLength']])
        v['byteOffset'] = len(NB) - v['byteLength']
        vmap2[old] = len(views)
        views.append(v)
    for a in J['accessors']:
        a['bufferView'] = vmap2[a['bufferView']]
    for im in J.get('images', []):
        if 'bufferView' in im:
            im['bufferView'] = vmap2[im['bufferView']]
    J['bufferViews'] = views
    J['buffers'][0]['byteLength'] = len(NB)
    glbfix.write(glb, J, NB)
    info['skin'] = nm   # 烘焙过蒙皮（看元数据就知道导入的是不是这一版）
    lines[li] = '    %s = %s,' % (key, B.lua(info))
    open(meta_path, 'w', encoding='utf-8').write('\n'.join(lines))
    log('  %s：烘好了，%d 页贴图' % (key, sum(1 for t in texs if t)))


if __name__ == '__main__':
    nm = sys.argv[1]
    bake(nm, sys.argv[2] if len(sys.argv) > 2 else 'models/air/%s.glb' % nm,
         sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/ImportedAir.lua',
         sys.argv[4] if len(sys.argv) > 4 else None)
