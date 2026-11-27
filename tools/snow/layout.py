# 雪山地图谷外山体的摆法（tools/snow/layout.json）→ 俯视合成图（看拼得怎么样）+ 游戏用的高度数据
#   用户 11-26 晚：「坦克交战区外你就用这几个拿去拼」「让这个地图望不到头」——每一座（inst）是 peaks.json 里的一个山体：
#   中心 x、z（格）、转角 yaw（度，从上往下看顺时针）、整体放大 k（≤ 那个模型的 kmax）、上下挪 y（格，负的往下沉：山脚埋进雪原 / 谷底）
# 用法：
#   python3 -I tools/snow/layout.py preview <看模型的目录（peekmodel.py 的输出）> <谷形状前缀（valley.luau 的输出）> <输出.png> [半边长] [格]
#   python3 -I tools/snow/layout.py data <下载目录（peaks.py 那个）>      → src/ReplicatedStorage/SnowPeaksData.lua（各模型的高度图 + 摆法）
import json, math, os, sys, base64
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
PEAKS = json.load(open(os.path.join(HERE, 'peaks.json'), encoding='utf-8'))
LAYOUT = json.load(open(os.path.join(HERE, 'layout.json'), encoding='utf-8'))
PLAIN = 12.0
PLAT = float(LAYOUT.get('plateau', PLAIN - 0.5))   # 山外那片雪原（客户端那圈远处平地）的高度
FARY = PLAT


def model_top(peek_dir, key):
    """看模型的输出（原单位、min→max 的格子）换成烘焙坐标：高（已乘 scale，最低 0）、俯视颜色、「平地」高（第 flatq 百分位：
       山体的平坦部分，摆的时候让它正好埋在雪原下面）"""
    H = np.load(os.path.join(peek_dir, key + '_h.npy'))           # (nz, nx)，原单位、相对最低点
    C = np.asarray(Image.open(os.path.join(peek_dir, key + '_tex.png')).convert('RGB')).astype(np.float32)
    S = PEAKS['sources'][key]
    sc = float(S['scale'])
    Hs = H * sc
    if S.get('taper'):   # 同 peaks.py 的边缘压平
        nz, nx = Hs.shape
        sx, sy, sz = bake_size(key)
        cell = max(sx, sz) / max(nx, nz)
        X, Z = np.meshgrid(-sx / 2 + (np.arange(nx) + 0.5) * cell, -sz / 2 + (np.arange(nz) + 0.5) * cell)
        d = np.minimum(np.minimum(X + sx / 2, sx / 2 - X), np.minimum(Z + sz / 2, sz / 2 - Z))
        t = np.clip(d / (float(S['taper']) * max(sx, sz)), 0, 1)
        kk = t * t * (3 - 2 * t)
        f = float(S['flat'])
        Hs = np.where(Hs > f, f + (Hs - f) * kk, Hs)
    flat = float(S['flat']) if 'flat' in S else float(np.nanpercentile(Hs, float(LAYOUT.get('flatq', 35))))
    return dict(H=Hs, C=C, sc=sc, flat=flat)


def inst_y(I, tops):
    """上下挪：有 y 就照 y；没有就按雪原 —— 这座的平地埋到雪原下 dy（默认 12）格"""
    if 'y' in I:
        return float(I['y'])
    return PLAT - tops[I['m']]['flat'] * float(I.get('k', 1.0)) - float(I.get('dy', 12))


def bake_size(key):
    meta = json.load(open(os.path.join(HERE, 'peaks_meta.json')))
    return meta[key]['size']


def composite(tops, insts, R, step):
    n = int(2 * R / step)
    xs = -R + (np.arange(n) + 0.5) * step
    HW = np.full((n, n), -np.inf, dtype=np.float32)
    CW = np.zeros((n, n, 3), dtype=np.float32)
    IW = np.full((n, n), -1, dtype=np.int32)
    for ii, I in enumerate(insts):
        key = I['m']
        T = tops[key]
        sx, sy, sz = bake_size(key)
        k = float(I.get('k', 1.0))
        hx, hz = sx / 2 * k, sz / 2 * k
        rr = math.hypot(hx, hz)
        i0, i1 = max(0, int((I['x'] - rr + R) / step)), min(n, int((I['x'] + rr + R) / step) + 1)
        j0, j1 = max(0, int((I['z'] - rr + R) / step)), min(n, int((I['z'] + rr + R) / step) + 1)
        if i0 >= i1 or j0 >= j1:
            continue
        X, Z = np.meshgrid(xs[i0:i1], xs[j0:j1])
        a = math.radians(I.get('yaw', 0))
        # 世界 → 模型：先平移，再转回去（yaw 顺时针看下去：x' = x cos + z sin …，和 Roblox 的 CFrame.Angles(0, -yaw, 0) 一致）
        dx, dz = X - I['x'], Z - I['z']
        lx = (dx * math.cos(a) + dz * math.sin(a)) / k
        lz = (-dx * math.sin(a) + dz * math.cos(a)) / k
        Hm = T['H']
        nzm, nxm = Hm.shape
        cell = max(sx, sz) / max(nxm, nzm)
        fx = (lx + sx / 2) / cell - 0.5
        fz = (lz + sz / 2) / cell - 0.5
        ok = (fx >= 0) & (fx <= nxm - 1) & (fz >= 0) & (fz <= nzm - 1)
        ix = np.clip(np.floor(fx).astype(np.int64), 0, nxm - 2)
        iz = np.clip(np.floor(fz).astype(np.int64), 0, nzm - 2)
        ux, uz = np.clip(fx - ix, 0, 1), np.clip(fz - iz, 0, 1)
        h00, h10, h01, h11 = Hm[iz, ix], Hm[iz, ix + 1], Hm[iz + 1, ix], Hm[iz + 1, ix + 1]
        h = (h00 * (1 - ux) + h10 * ux) * (1 - uz) + (h01 * (1 - ux) + h11 * ux) * uz
        h = np.where(ok & np.isfinite(h), h * k + inst_y(I, tops), -np.inf)
        cur = HW[j0:j1, i0:i1]
        up = h > cur
        cur[up] = h[up]
        col = T['C'][np.clip(np.round(fz).astype(np.int64), 0, nzm - 1), np.clip(np.round(fx).astype(np.int64), 0, nxm - 1)]
        CW[j0:j1, i0:i1][up] = col[up]
        IW[j0:j1, i0:i1][up] = ii
    return xs, HW, CW, IW


def all_insts():
    """手摆的（inst）+ 外圈自动铺的（fill：从 r0 到 r1 的抖动网格，每格随机挑一个模型、转角；离手摆的太近的格跳过）"""
    insts = [dict(I) for I in LAYOUT['inst']]
    F = LAYOUT.get('fill')
    if not F:
        return insts
    rng = np.random.default_rng(F.get('seed', 1))
    g = float(F['grid'])
    r0, r1 = float(F['r0']), float(F['r1'])
    hand = [(I['x'], I['z']) for I in insts]
    n = int(math.ceil(r1 / g))
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            x = i * g + rng.uniform(-0.3, 0.3) * g
            z = j * g + rng.uniform(-0.3, 0.3) * g
            rr = max(abs(x), abs(z))
            pool = F['models'] if rr < float(F.get('rmid', r1)) else F.get('far', F['models'])
            m = pool[int(rng.integers(len(pool)))]
            yaw = float(rng.uniform(0, 360))
            dy = float(rng.uniform(5, 60))
            if max(abs(x), abs(z)) < r0 or max(abs(x), abs(z)) > r1:
                continue
            if any(math.hypot(x - hx, z - hz) < g * 0.75 for hx, hz in hand):
                continue
            insts.append(dict(m=m, x=round(x), z=round(z), yaw=round(yaw, 1), dy=round(dy), fill=True))
    return insts


def preview(peek_dir, valley_pre, out, R=48000, step=64):
    insts = all_insts()
    print(f'一共 {len(insts)} 座（手摆 {len(LAYOUT["inst"])}）')
    tops = {k: model_top(peek_dir, k) for k in {I['m'] for I in insts}}
    xs, HW, CW, IW = composite(tops, insts, R, step)
    n = len(xs)
    # 谷：valley.luau 导出的 valleyD（只盖 ±16384），谷里 < 1
    vinfo = json.load(open(valley_pre + '.json'))
    vn, vstep, vR = vinfo['n'], vinfo['step'], vinfo['R']
    vd = np.frombuffer(open(valley_pre + '.vd', 'rb').read(), dtype=np.float32).reshape(vn, vn)
    VD = np.full((n, n), 9.0, dtype=np.float32)
    ii = ((xs + vR) / vstep).astype(np.int64)
    okv = (ii >= 0) & (ii < vn)
    J, I = np.meshgrid(np.nonzero(okv)[0], np.nonzero(okv)[0], indexing='ij')
    VD[np.ix_(np.nonzero(okv)[0], np.nonzero(okv)[0])] = vd[ii[okv]][:, ii[okv]]
    wall = float(LAYOUT.get('wall', 900))   # 谷边往外多远抬到雪原（地形写的谷壁）
    vsc = 3500.0                             # valleyD 一个单位约折合多少格（谷半宽）
    dE = np.clip((VD - 1.0) * vsc, 0, None)
    t = np.clip(dE / wall, 0, 1)
    ground = np.where(VD < 1.0, PLAIN, PLAIN + (FARY - PLAIN) * t * t * (3 - 2 * t))
    mtn = np.isfinite(HW) & (HW > ground)
    Hf = np.where(mtn, HW, ground)
    # 统计：谷边一圈（谷外 0～1500 格）山够不够高；谷里被山脚占了多少
    edge = (VD >= 1.0) & (VD < 1.25)
    inval = VD < 0.97
    print(f'谷里被山盖住（高出谷底 3 格以上）：{(inval & (HW > PLAIN + 3)).sum() / max(1, inval.sum()) * 100:.1f}%')
    he = np.where(np.isfinite(HW[edge]), HW[edge], 0)
    print(f'谷外一圈：山高中位数 {np.median(he):.0f} 格，低于 150 格的 {np.mean(he < 150) * 100:.0f}%（看得穿的豁口）')
    cov = np.isfinite(HW)
    for rad in (12000, 20000, 30000, 40000):
        ring = (np.abs(xs)[None, :] <= rad) & (np.abs(xs)[:, None] <= rad) & (VD >= 1.0)
        print(f'±{rad} 以内（谷外）：有山 {np.mean(cov[ring]) * 100:.0f}%，山高过 300 格 {np.mean((HW[ring] > 300)) * 100:.0f}%')
    # 晕渲
    gx = np.gradient(Hf, axis=1) / step
    gz = np.gradient(Hf, axis=0) / step
    nrm = np.stack([-gx, np.ones_like(gx), -gz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    L = np.array([-0.55, 0.7, -0.45])
    L /= np.linalg.norm(L)
    sh = np.clip(nrm @ L, 0, 1)
    base = np.where(mtn[..., None], CW, np.where((VD < 1.0)[..., None], np.array([236, 240, 247.0]), np.array([205, 212, 222.0])))
    img = np.clip(base * (0.45 + 0.7 * sh[..., None]), 0, 255)
    # 谷边线、据点、基地
    bd = (VD < 1.0) & ~(np.roll(VD < 1.0, 1, 0) & np.roll(VD < 1.0, -1, 0) & np.roll(VD < 1.0, 1, 1) & np.roll(VD < 1.0, -1, 1))
    img[bd] = [220, 40, 40]
    for b in (12288, 20480):   # 地形边、飞机作战区边
        for v in (-b, b):
            k = int((v + R) / step)
            if 0 <= k < n:
                img[:, k] = [60, 60, 200]
                img[k, :] = [60, 60, 200]
    # 给 3D 预览：每格 f32 高 + RGB（view.html 的 rgb 模式）
    rgb = np.where(mtn[..., None], CW, np.where((VD < 1.0)[..., None], np.array([236, 240, 247.0]), np.array([228, 233, 240.0])))
    rec = np.zeros((n, n), dtype=[('h', '<f4'), ('r', 'u1'), ('g', 'u1'), ('b', 'u1'), ('p', 'u1')])
    rec['h'] = Hf
    rec['r'], rec['g'], rec['b'] = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    rec.tofile(out.replace('.png', '.hrgb'))
    json.dump(dict(n=n, step=step, R=R, plat=FARY), open(out.replace('.png', '.hrgb.json'), 'w'))
    im = Image.fromarray(img.astype(np.uint8))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(im)
    for ii, I in enumerate(insts):   # 每座的编号（布局表里的顺序）
        px, pz = (I['x'] + R) / step, (I['z'] + R) / step
        if not I.get('fill'):
            dr.rectangle([px - 14, pz - 9, px + 14, pz + 9], fill=(255, 255, 255))
        if not I.get('fill'):
            dr.text((px - 11, pz - 7), f"{ii}{I['m'][0]}", fill=(200, 0, 0))
    im.save(out)
    print('写好了', out, Hf.shape)


GRID = {'smv2': 320, 'glacier': 320, 'kerem': 320, 'icy': 256, 'wmsnow': 256, 'rockscan': 160}   # 高度图一边几格


def data():
    """游戏用的高度数据：每个模型（转好的 models/snow/<键>.glb，边缘已经压平）俯视栅格化成高度图（每格取最高），u16（1/16 格），
       base64 存成一个模块一个模型（src/ReplicatedStorage/SnowPeaks/<键>.lua）；摆法（全部 170 来座，含外圈自动铺的）写进 SnowPeaks/init.lua"""
    sys.path.insert(0, HERE)
    import gltfio, raster
    meta = json.load(open(os.path.join(HERE, 'peaks_meta.json')))
    insts = all_insts()
    used = sorted({I['m'] for I in insts})
    outdir = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'SnowPeaks')
    os.makedirs(outdir, exist_ok=True)
    flats = {}
    for key in used:
        prims, _ = gltfio.load(os.path.join(ROOT, 'models', 'snow', key + '.glb'))
        Ps, Ts, off = [], [], 0
        for p in prims:
            Ps.append(p['pos'])
            Ts.append(p['idx'] + off)
            off += len(p['pos'])
        P, T = np.concatenate(Ps), np.concatenate(Ts)
        sx, sy, sz = meta[key]['size']
        n = GRID.get(key, 256)
        cell = max(sx, sz) / n
        nx, nz = int(math.ceil(sx / cell)), int(math.ceil(sz / cell))
        x0, z0 = -nx * cell / 2, -nz * cell / 2
        H, _, _ = raster.raster(P, T, x0, z0, cell, nx, nz)
        ok = np.isfinite(H)
        # 没盖到的格（照片扫描的不规则外沿）：0 = 这里没有山
        q = np.where(ok, np.clip(np.round(np.maximum(H, 0) * 16) + 1, 1, 65535), 0).astype('<u2')
        S = PEAKS['sources'][key]
        flats[key] = float(S['flat']) if 'flat' in S else float(np.percentile(H[ok], float(LAYOUT.get('flatq', 35))))
        b64 = base64.b64encode(q.tobytes()).decode()
        parts = [b64[i:i + 65536] for i in range(0, len(b64), 65536)]
        L = [f'-- 雪山地图谷外山体「{S["name"]}」（{S["author"]}，Sketchfab，CC-BY 4.0）的俯视高度图：tools/snow/layout.py data 生成，别手改',
             f'--   {nx} × {nz} 格，每格 {cell:.3f} 格见方，左上角（x0, z0）在模型坐标 ({x0:.2f}, {z0:.2f})；u16 小端，0 = 这里没有山，其余 = 高 × 16 + 1（模型坐标：最低点 y = 0）',
             'return {', f'  nx = {nx}, nz = {nz}, cell = {cell:.6f}, x0 = {x0:.4f}, z0 = {z0:.4f}, flat = {flats[key]:.2f},', '  b64 = {']
        for part in parts:
            L.append(f'    "{part}",')
        L += ['  },', '}']
        open(os.path.join(outdir, key + '.lua'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
        print(f'{key}: {nx}×{nz}，每格 {cell:.1f} 格，盖住 {ok.mean() * 100:.0f}%，最高 {np.nanmax(H):.0f}，{len(b64) / 1024:.0f} KB')
    # 摆法
    tops = {k: dict(flat=flats[k]) for k in used}
    L = ['-- 雪山地图谷外的山体：摆法（tools/snow/layout.py data 生成，别手改；手摆的在 tools/snow/layout.json 的 inst，外圈是 fill 自动铺的）',
         '--   inst 每座 { 模型键, x, z, 转角（度，从上往下看顺时针）, 放大 k, 上下挪 y（格） }；模型的块在 ReplicatedStorage.Imported.Peaks.<键>（导入 models/snow/<键>.glb），',
         '--   高度图在同一个文件夹下的 <键> 模块（MapSnow 按需 require）；far 是山外雪原（客户端那圈远处平地）的高度',
         'return {', f'  far = {FARY},', '  size = {']
    for key in used:
        sx, sy, sz = meta[key]['size']
        L.append(f'    {key} = {{ {sx:.1f}, {sy:.1f}, {sz:.1f} }},')
    L += ['  },', '  inst = {']
    for I in insts:
        y = inst_y(I, tops)
        L.append(f'    {{ "{I["m"]}", {I["x"]}, {I["z"]}, {float(I.get("yaw", 0)):.1f}, {float(I.get("k", 1)):.3f}, {y:.1f}{", true" if I.get("fill") else ""} }},')
    L += ['  },', '}']
    open(os.path.join(outdir, 'init.lua'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print(f'摆法：{len(insts)} 座 → src/ReplicatedStorage/SnowPeaks/init.lua')


if __name__ == '__main__':
    if sys.argv[1] == 'data':
        data()
        sys.exit(0)
    cmd = sys.argv[1]
    if cmd == 'preview':
        R = float(sys.argv[5]) if len(sys.argv) > 5 else 48000
        step = float(sys.argv[6]) if len(sys.argv) > 6 else 64
        preview(sys.argv[2], sys.argv[3], sys.argv[4], R, step)
