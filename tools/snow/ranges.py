# 雪山冰岛两侧的山脊（用户 11-26 夜「我需要那个雪山地图有连绵不绝的山脉」，接着「你把这个设计成一个海上的冰岛吧 然后外面包裹的都是一望无际的海
#   你也不用单独建模了」）→ src/ReplicatedStorage/SnowPeaks/init.lua
#   python3 -I tools/snow/ranges.py <valley 前缀（scratchpad 里 valley.luau 的输出：.json + .vd）> [预览.png]
# 山体还是那 6 个 Sketchfab 模型（CC-BY，「坦克交战区外你就用这几个拿去拼」），按山脉排：
#   · 第一道：紧贴谷边，顺着谷边一座挨一座（间距不到半座山宽，互相叠着连成一道墙）；谷两头基地背后也是一道
#   · 岛外是海，不再摆外圈的山：贴着谷边这一道山脊的外坡直接插进海里（模型底下的裙边埋到水面下 40 格，透过海水看不见）
#   · 每个模型按自己的高度分布埋：模型里的大片台地、平地（原来露出来是平顶的高台、一圈悬崖）埋进雪原，只露山脊、山峰；
#     竖着再拉高一点（ky），露出来的山不矮
#   · 谷里（坦克交战区）不许有山伸进来：每一座摆之前查一遍，山体高过谷里地面的就往外挪，挪不开就不要；
#     两边基地跑道的起飞方向（东西两头）各留一条往外越来越高的山谷（飞机起飞不撞山）
#   · 「Rock terrain with light snow」（用户：雪山你直接用这个原封不动）：谷边山脚摆三处，当谷边露出来的雪岩坡
import json, math, os, sys, base64, re
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
META = json.load(open(os.path.join(HERE, 'peaks_meta.json')))
PEAKS = json.load(open(os.path.join(HERE, 'peaks.json'), encoding='utf-8'))
PLAIN, PLAT = 12.0, 11.5
CUT = {'icy': 35, 'wmsnow': 38, 'smv2': 56, 'glacier': 70, 'kerem': 52, 'rockscan': 25}    # 埋到这个模型高度的第几百分位（台地埋进去）
VY = {'icy': 1.55, 'wmsnow': 1.3, 'smv2': 1.25, 'glacier': 1.7, 'kerem': 1.1, 'rockscan': 1.0}  # 竖着再拉高（谷边的山要压得住：近、高、陡）
RUNWAY_Z = 7806          # 两边跑道的中线 z（±；FOB.runway.lz = 1150，基地在 ±6656）
RUNWAY_X = 1800          # 跑道两头


def load_model(key):
    t = open(os.path.join(ROOT, 'src', 'ReplicatedStorage', 'SnowPeaks', key + '.lua'), encoding='utf-8').read()
    g = lambda k: float(re.search(k + r' = (-?[\d.]+)', t).group(1))
    nx, nz = int(g('nx')), int(g('nz'))
    b64 = ''.join(re.findall(r'"([A-Za-z0-9+/=]{8,})"', t))
    q = np.frombuffer(base64.b64decode(b64), dtype='<u2').reshape(nz, nx).astype(np.float32)
    H = np.where(q > 0, (q - 1) / 16, np.nan)
    cut = float(np.nanpercentile(H, CUT[key]))
    return dict(H=H, nx=nx, nz=nz, cell=g('cell'), x0=g('x0'), z0=g('z0'), cut=cut, size=META[key]['size'], chunks=META[key]['chunks'])


MODELS = {k: load_model(k) for k in CUT}


def sample(I, X, Z):
    """一座山在世界坐标 (X, Z)（数组）处的高（没有山 nan）：同 MapSnow.peakH"""
    m = MODELS[I['m']]
    a = math.radians(I['yaw'])
    dx, dz = X - I['x'], Z - I['z']
    lx = (dx * math.cos(a) + dz * math.sin(a)) / I['k']
    lz = (-dx * math.sin(a) + dz * math.cos(a)) / I['k']
    fx = (lx - m['x0']) / m['cell'] - 0.5
    fz = (lz - m['z0']) / m['cell'] - 0.5
    ok = (fx >= 0) & (fz >= 0) & (fx <= m['nx'] - 1) & (fz <= m['nz'] - 1)
    ix = np.clip(np.floor(fx).astype(np.int64), 0, m['nx'] - 2)
    iz = np.clip(np.floor(fz).astype(np.int64), 0, m['nz'] - 2)
    ux, uz = np.clip(fx - ix, 0, 1), np.clip(fz - iz, 0, 1)
    H = m['H']
    h = (H[iz, ix] * (1 - ux) + H[iz, ix + 1] * ux) * (1 - uz) + (H[iz + 1, ix] * (1 - ux) + H[iz + 1, ix + 1] * ux) * uz
    return np.where(ok, h * I['ky'] + I['y'], np.nan)


def main():
    vpre = sys.argv[1]
    vi = json.load(open(vpre + '.json'))
    vn, vstep, vR = vi['n'], vi['step'], vi['R']
    VD = np.frombuffer(open(vpre + '.vd', 'rb').read(), dtype=np.float32).reshape(vn, vn)
    # 谷里的真地面高（scratchpad 的 floorexp.luau 导出的 MapSnow.floorH，同一张网格；谷外是 1e6）：山不许高过它
    FL = np.frombuffer(open(vpre + '.floor', 'rb').read(), dtype=np.float32).reshape(vn, vn) if os.path.exists(vpre + '.floor') else None

    def vd_at(x, z):
        i = np.clip(((np.asarray(x) + vR) / vstep).astype(np.int64), 0, vn - 1)
        j = np.clip(((np.asarray(z) + vR) / vstep).astype(np.int64), 0, vn - 1)
        return VD[j, i]

    def sm(a, b, v):
        t = np.clip((v - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)

    # 谷里的检查点（每 96 格）：山不许高过这里的地面（地面按 MapSnow natH 的谷两侧抬高估，往低里取）
    gx = np.arange(-6400, 6401, 96.0)
    gz = np.arange(-12800, 12801, 96.0)
    GX, GZ = np.meshgrid(gx, gz)
    V = vd_at(GX, GZ)
    inside = V < 1.02
    allow = PLAIN + 34 + 160 * sm(0.6, 1.02, V) ** 1.4 - 8
    if FL is not None:   # 真地面（谷边一圈按 64 格网格最近的点；往低里取：周围 3 × 3 格最低的）
        ii = np.clip(((GX + vR) / vstep).astype(np.int64), 1, vn - 2)
        jj = np.clip(((GZ + vR) / vstep).astype(np.int64), 1, vn - 2)
        fmin = np.full(GX.shape, 1e6, dtype=np.float32)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                fmin = np.minimum(fmin, FL[jj + dj, ii + di])
        allow = np.minimum(allow, fmin - 6)
    PX, PZ, PA = GX[inside], GZ[inside], allow[inside]
    # 跑道起飞的山谷：跑道两头往外，宽 ±1300，允许的高按 18% 的坡往外升
    cx, cz, ca = [], [], []
    for zr in (RUNWAY_Z, -RUNWAY_Z):
        for sx in (1, -1):
            for d in np.arange(0, 14000, 120.0):
                for w in np.arange(-1300, 1301, 130.0):
                    cx.append(sx * (RUNWAY_X + d))
                    cz.append(zr + w)
                    ca.append(PLAIN + 50 + 0.18 * d + 0.06 * abs(w))
    # 湖（水库）：湖面、湖岸一圈不许有山（湖心 (3000, -1250)、半轴 700 × 560，湖面高 52）
    for x in np.arange(2000, 4200, 60.0):
        for zz in np.arange(-2200, -300, 60.0):
            ld = math.hypot((x - 3000) / 700, (zz + 1250) / 560)
            if ld < 1.7:
                cx.append(x)
                cz.append(zz)
                ca.append(PLAIN + 34 if ld < 1.1 else PLAIN + 60)
    PX = np.concatenate([PX, np.array(cx)])
    PZ = np.concatenate([PZ, np.array(cz)])
    PA = np.concatenate([PA, np.array(ca)])

    def violates(I):
        m = MODELS[I['m']]
        r = 0.5 * math.hypot(m['size'][0], m['size'][2]) * I['k']
        sel = (np.abs(PX - I['x']) < r) & (np.abs(PZ - I['z']) < r)
        if not sel.any():
            return False
        h = sample(I, PX[sel], PZ[sel])
        bad = np.isfinite(h) & (h > PA[sel])
        return bool(bad.any())

    rng = np.random.default_rng(20261126)
    insts = []

    def make(key, x, z, yaw, k, dy=90.0, fill=True):   # 山脚埋到水面下 80 来格：比海底还低，从天上看不到海里透出来的山脚
        m = MODELS[key]
        ky = k * VY[key]
        return dict(m=key, x=float(x), z=float(z), yaw=float(yaw % 360), k=float(k), ky=float(ky), y=float(PLAT - m['cut'] * ky - dy), fill=fill)

    def place(key, x, z, yaw, k, ox, oz, fill=True, minGap=0.33):
        """从 (x, z) 起往 (ox, oz) 方向挪，直到不伸进谷里、不挡跑道；离已摆的同一座太近（minGap × 山宽）就不要"""
        m = MODELS[key]
        L = math.hypot(ox, oz) or 1
        ox, oz = ox / L, oz / L
        for step in range(40):
            I = make(key, x + ox * step * 260, z + oz * step * 260, yaw, k, fill=fill)
            if not violates(I):
                w = m['size'][0] * k
                for J in insts:
                    if math.hypot(J['x'] - I['x'], J['z'] - I['z']) < minGap * min(w, MODELS[J['m']]['size'][0] * J['k']):
                        return None
                insts.append(I)
                return I
        return None

    # ---- 第一道：谷边
    # 谷边（vd = 1）在每个 z 的东西两侧 x
    xs = np.arange(-12000, 12001, 16.0)

    def edges(z):
        v = vd_at(xs, np.full_like(xs, z))
        ins = np.nonzero(v < 1.0)[0]
        if len(ins) == 0:
            return None
        return xs[ins[0]], xs[ins[-1]]

    # 用户 11-27：「最近的山脊离谷底四五公里，而且只摆了 25 座，有缺口」「一座座模型之间的接缝……从天上看可能会花」「山体几百万三角面……手机大概率吃不消」——
    #   只用两种轻的（Icy Terrain 5.8 万面、Snow Mountain 1.4 万面，样子也接近：拼起来不花），贴着谷边、间距 2400 格一座挨一座
    WALL = ['icy', 'icy', 'wmsnow', 'icy', 'wmsnow', 'icy']
    z = -13400.0
    wi = 0
    while z <= 13400:
        e = edges(max(-9000, min(9000, z)))
        if e:
            for side, xe in ((-1, e[0]), (1, e[1])):
                key = WALL[(wi + (0 if side < 0 else 3)) % len(WALL)]
                k = float(rng.uniform(1.15, 1.35))
                w = MODELS[key]['size'][0] * k
                yaw = rng.uniform(0, 360)
                place(key, xe + side * w * 0.12, z + rng.uniform(-300, 300), yaw, k, side, 0, fill=False, minGap=0.22)
        wi += 1
        z += 2400
    # 两头（基地背后）
    for sz in (-1, 1):
        for x in np.arange(-7000, 7001, 2600.0):
            key = WALL[int(rng.integers(len(WALL)))]
            k = float(rng.uniform(1.15, 1.35))
            w = MODELS[key]['size'][0] * k
            place(key, x + rng.uniform(-300, 300), sz * (9150 + w * 0.12), rng.uniform(0, 360), k, 0, sz, fill=False, minGap=0.22)
    # ---- 「Rock terrain with light snow」：谷边山脚三处（底面接着谷边的山麓）
    for (x, z, yaw) in ((-1.0, -2600, 30),):   # Rock terrain with light snow（七十多万面）：只留一处，在雷达站台地北边的谷边
        e = edges(z)
        xe = e[0] if x < 0 else e[1]
        m = MODELS['rockscan']
        k = 1.05
        for step in range(30):   # 从谷边往外挪，直到不伸进谷里
            I = dict(m='rockscan', x=float(xe + x * (600 + step * 150)), z=float(z), yaw=float(yaw), k=k, ky=k, fill=False)
            v = float(vd_at(I['x'], I['z']))
            floor = PLAIN + 60 + 160 * float(sm(0.6, 1.02, v)) ** 1.4 + 70 * float(sm(1.0, 1.2, v))
            I['y'] = float(floor - m['cut'] * k - 6)
            if not violates(I):
                insts.append(I)
                break

    # ---- 统计、写出
    nch = sum(len(MODELS[I['m']]['chunks']) for I in insts)
    from collections import Counter
    print('山 %d 座（谷边 %d），块 %d：%s' % (len(insts), sum(1 for I in insts if not I['fill']), nch, dict(Counter(I['m'] for I in insts))))
    used = sorted({I['m'] for I in insts})
    L = ['-- 雪山地图谷外的山脉：摆法（tools/snow/ranges.py 生成，别手改）——谷边一道、外面三道，一座挨一座连成山脉',
         '--   inst 每座 { 模型键, x, z, 转角（度，从上往下看顺时针）, 横向放大 k, 上下挪 y（格）, 外圈（不投影子）, 竖向放大 ky }；',
         '--   模型的块在 ReplicatedStorage.Imported.Peaks.<键>（导入 models/snow/<键>.glb），高度图在同一个文件夹下的 <键> 模块（MapSnow 按需 require）；',
         '--   far 是山外雪原（客户端那圈远处平地）的高度',
         'return {', f'  far = {PLAT},', '  size = {']
    for key in used:
        sx, sy, sz2 = META[key]['size']
        L.append(f'    {key} = {{ {sx:.1f}, {sy:.1f}, {sz2:.1f} }},')
    L += ['  },', '  inst = {']
    for I in insts:
        L.append('    { "%s", %d, %d, %.1f, %.3f, %.1f, %s, %.3f },' % (I['m'], round(I['x']), round(I['z']), I['yaw'], I['k'], I['y'], 'true' if I['fill'] else 'false', I['ky']))
    L += ['  },', '}']
    out = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'SnowPeaks', 'init.lua')
    open(out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print('写好', out)
    if len(sys.argv) > 2:
        preview(insts, sys.argv[2], vd_at)


def preview(insts, out, vd_at, R=48000, step=96):
    from PIL import Image
    n = int(2 * R / step)
    xs = -R + (np.arange(n) + 0.5) * step
    X, Z = np.meshgrid(xs, xs)
    HW = np.full((n, n), PLAT, dtype=np.float32)
    for I in insts:
        m = MODELS[I['m']]
        r = 0.5 * math.hypot(m['size'][0], m['size'][2]) * I['k']
        i0, i1 = max(0, int((I['x'] - r + R) / step)), min(n, int((I['x'] + r + R) / step) + 1)
        j0, j1 = max(0, int((I['z'] - r + R) / step)), min(n, int((I['z'] + r + R) / step) + 1)
        if i0 >= i1 or j0 >= j1:
            continue
        h = sample(I, X[j0:j1, i0:i1], Z[j0:j1, i0:i1])
        cur = HW[j0:j1, i0:i1]
        up = np.isfinite(h) & (h > cur)
        cur[up] = h[up]
    V = vd_at(X, Z)
    gxx = np.gradient(HW, axis=1) / step
    gzz = np.gradient(HW, axis=0) / step
    nrm = np.stack([-gxx, np.ones_like(gxx), -gzz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    Ld = np.array([-0.55, 0.7, -0.45])
    Ld /= np.linalg.norm(Ld)
    sh = np.clip(nrm @ Ld, 0, 1)
    t = np.clip(HW / 2500, 0, 1)[..., None]
    base = np.array([200, 208, 220.0]) * (1 - t) + np.array([255, 255, 255.0]) * t
    img = np.clip(base * (0.35 + 0.8 * sh[..., None]), 0, 255)
    img[(V < 1.0)] = img[(V < 1.0)] * 0.6 + np.array([60, 120, 60]) * 0.4
    Image.fromarray(img.astype(np.uint8)).save(out)
    cov = HW > PLAT + 50
    for rad in (12000, 20000, 30000, 40000):
        ring = (np.abs(X) <= rad) & (np.abs(Z) <= rad) & (V >= 1.0)
        print(f'±{rad} 以内（谷外）：山盖住 {cov[ring].mean() * 100:.0f}%，高过 600 格 {(HW[ring] > 600).mean() * 100:.0f}%')
    print('写好', out)


if __name__ == '__main__':
    main()
