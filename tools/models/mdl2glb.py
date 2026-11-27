# 网页版《暗剑》烘焙的装备模型（js/mdl/<键>.js）→ Roblox Studio「导入 3D」用的 GLB（每个模型一个）+ 游戏用的元数据
#   python3 -I tools/models/mdl2glb.py <网页版仓库目录> [--sf <Sketchfab 下载目录>] [输出目录，默认 models/veh] [元数据，默认 src/ReplicatedStorage/ImportedMeta.lua] [模型键 …]
#   网页版没有的型号直接从 Sketchfab 下载（tools/models/sfveh.py 的 SF：来源、署名、加工方法）：--sf 给出放 <模型键>.zip 的目录才转，
#   不给就照旧用元数据里原来那一行（GLB 也不动）；只转几个模型键时，其余的元数据同样照旧
# 原样转（用户：每个载具都是要驾驶的，原 size 导入）：
#   - 网格用最精细的那档（不减面）；Roblox 一块网格最多约 2 万个三角形，超了就切成几块
#   - 每个材质照原样：底色贴图、法线贴图、金属度 / 粗糙度贴图（Studio 导入时做成 SurfaceAppearance）、底色、透明方式、双面；
#     贴图保持原分辨率（Roblox 最大 1024，更大的缩到 1024），平铺方式照原样（重复 / 镜像 / 夹边）
#   - 真实尺寸：1 米 = 2.8 格（和游戏里的人一样比例）；坐标从网页版的 x 前、y 左、z 上换成 Roblox 的 X 右、Y 上、−Z 前，
#     原点在车底、车身（不含炮塔、炮）的中心——和游戏里的碰撞盒对齐
#   - 按部件分：车体 Body、炮塔 Turret（tur / yaw / rws / tow / rdr）、炮 Gun（gun / gat / lnch）、车轮 W01……（whl）；
#     每个部件再按材质分成几块：MeshPart 叫 V_<键>__<部件>_<块号>（开服时 Imports.lua 按名字收进 ReplicatedStorage.Imported.Veh.<键>）
# 元数据：各块属于哪个部件、在模型里的中心和大小；炮塔转轴、炮耳轴、炮口离耳轴多远；每个车轮的中心和半径；署名
import base64, io, json, math, os, struct, sys
import numpy as np
from PIL import Image

WEB = None   # 网页版仓库目录（命令行第一个参数；tools/models/air2glb.py import 这个文件时自己设）
OUTDIR, META, ONLY = 'models/veh', 'src/ReplicatedStorage/ImportedMeta.lua', []
S = 2.8          # 米 → 格
CHUNK = 19500    # 一块网格最多几个三角形
TEXMAX = 1024    # Roblox 贴图最大边长

# Roblox 里的型号 → 网页版的模型（网页版自己就拿 LAV-25 代 ZSL-92B、PzH 2000 代 PLZ-07、M-ATV 代 M1117……照它）
#   M1A2 用户 11-18 指定换成 Mirza Arrafi 的「M1A2 SEPV2 Abrams Main Battle Tank DC」（沙漠涂装，Sketchfab CC-BY；原来是 dannzjs 的 SEPv3）
#   99A 用户 11-18 指定换成 42manako 的「ZTZ-99A2」（Sketchfab，CC-BY；原来是 philano 的低面数 Type 99）：网页版没有，在临时目录里用网页版的 v3gbake.js 烘焙
ALIAS = {
    'ztz99a': 'ztz99a2', 'ztz96': 'ztz96', 'zbd05': 'zbd97', 'zsl92b': 'lav25', 'ptl02': 'ptl02', 'pgl625': 't625', 'plz07': 'pzh2000',
    'm1a2': 'm1a2dc', 'm1a1': 'm1a1', 'm2a3': 'm2a3', 'stryker': 'stryker', 'mshorad': 'stryker', 'm1150': 'm1150', 'hmmwv': 'hmmwv',
    'jltv': 'jltv', 'm1117': 'matv', 'm163': 'm163', 'cram': 'cram', 'patriot': 'patriot', 'm109a7': 'm109', 'm270': 'm270',
    # 11-27 拆开重叠的版本（用户「把重叠的版本拆开（M1A2 / SEP / SEPv3 等）」）：同族的老 / 新型号借同一个模型（性能各是各的，VehDefs 的 like）
    'm1a2base': 'm1a2dc', 'm1a2sep': 'm1a2dc', 'm1a2sep3': 'm1a2dc',
}
# 网页版烘焙出来车头朝后的（网页版游戏里 JLTV 用的是 M-ATV 的模型，这个 JLTV 模型从没开过，方向反了没人发现）：掉头 180°
#   用户：「这个车操作是倒着开的」——模型的备胎（真车挂在车尾）在游戏认的车头那一端
FLIP = {'jltv', 'm270'}
#   M270 同样：驾驶室在网页版坐标的 −x 那头（网页版配置也写的 fwd +z），游戏里一直是倒着开的
# 原模型整车只有一种颜色的（JLTV：车窗、轮胎也是沙黄；用户：车窗是透明的吧，轮胎黑色吧）：按网页版的材质号 + 高度（网页版坐标 z，米）改色
#   JLTV 的 12 号材质是胎面；5 号材质是胎侧，混着左门上的一块车窗（离地 1.25 米以上）；22 号是车窗、51 号是挡风玻璃和灯罩
RECOLOR = {'jltv': [{'mats': [12], 'to': 'tire'}, {'mats': [5], 'zmax': 1.25, 'to': 'tire'}, {'mats': [5], 'zmin': 1.25, 'to': 'glass'},
                    {'mats': [22, 51], 'to': 'glass'}]}
NEWMAT = {'tire': {'n': 'tire', 'c': [0.02, 0.02, 0.022, 1], 'mr': [0, 0.92]},
          'glass': {'n': 'glass', 'c': [0.03, 0.045, 0.055, 0.42], 'am': 2, 'mr': [0.2, 0.06]}}   # 深色半透明（游戏里按元数据的 a 设透明度）
GROUP = {'tur': 'Turret', 'yaw': 'Turret', 'rws': 'Turret', 'tow': 'Turret', 'rdr': 'Turret', 'gun': 'Gun', 'gat': 'Gun', 'lnch': 'Gun'}
# 原模型里机枪塔 / 炮管和车身（或炮塔）烘焙成一整块的：按连通块拆出来，好让机枪塔转、炮管俯仰，炮弹从看得见的炮口出去
#   （用户：很多载具的机枪塔没法旋转；载具开火的位置要对）
#   坐标是网页版烘焙坐标（x 前、y 左、z 上，米；FLIP 的车照掉头前的坐标写，转的时候跟着掉头）
#   rules：from 从哪个部件拆、to 拆成哪个部件；box [x0, x1, y0, y1] + zmin / zmax：整个连通块都落在框里才拆——
#     贴着车身、伸出框外的面（车顶、炮塔壳）不会被拆走；tur 炮塔（机枪塔）转轴、gun 炮耳轴（机枪的俯仰轴）
#   悍马（M998 软篷）原模型就没有机枪：游戏里给它在车顶补一挺零件拼的 M2（客户端 VehModels）
SPLIT = {
    # JLTV：车顶 O-GPK 式机枪塔（座圈、护盾）+ M2，炮口朝车头（掉头前的 −x）
    'jltv': {'rules': [{'from': 'Body', 'to': 'Turret', 'box': [-1.35, 1.40, -0.75, 0.75], 'zmin': 2.40},
                       {'from': 'Turret', 'to': 'Body', 'box': [-1.35, -0.62, -0.75, 0.75], 'zmax': 2.56},   # 机枪塔前面车顶上的小零件留在车身
                       {'from': 'Turret', 'to': 'Gun', 'box': [-1.35, 0.30, -0.30, 0.30], 'zmin': 2.56}],
             'tur': [0.585, 0, 2.45], 'gun': [-0.10, 0, 2.82]},
    # M1150：炮塔顶上的车长指挥塔（座圈、舱盖）+ M2（炮塔本身不转：没有主炮，后面挂着扫雷火箭发射箱）
    'm1150': {'rules': [{'from': 'Body', 'to': 'Turret', 'box': [-1.60, 0.50, -0.55, 0.55], 'zmin': 1.95},
                        {'from': 'Turret', 'to': 'Body', 'box': [-0.45, 0.50, -0.55, 0.55], 'zmax': 2.25},   # 指挥塔前面炮塔顶上的箱子、观察镜留在车身
                        {'from': 'Turret', 'to': 'Body', 'box': [-1.61, -1.48, -0.55, 0.55], 'zmin': 2.3},   # 后面横杆上的零碎
                        {'from': 'Turret', 'to': 'Gun', 'box': [-0.95, 0.50, -0.40, 0.40], 'zmin': 2.28}],
              'tur': [-1.06, 0, 2.0], 'gun': [-0.60, 0, 2.42]},
    # M-ATV（游戏里的 M1117）：机枪塔本来就是单独的部件，M2 和塔是一块——拆出来；原模型的 M2 抬着 18°，转平（lvl）
    'matv': {'rules': [{'from': 'Turret', 'to': 'Gun', 'box': [-0.60, 1.10, -0.25, 0.25], 'zmin': 2.74}],
             'gun': [-0.15, 0.035, 2.98], 'lvl': 17.8},
    # 斯特赖克：网页版烘焙时 M151 遥控武器站留在了车身里（炮塔部件只有几块碎片）——整个武器站拆成炮塔，M2 拆成炮
    'stryker': {'rules': [{'from': 'Body', 'to': 'Turret', 'box': [-0.75, 1.32, -0.92, 0.06], 'zmin': 2.45},
                          {'from': 'Turret', 'to': 'Gun', 'box': [-0.70, 1.32, -0.56, -0.34], 'zmin': 2.80}],
                'gun': [-0.20, -0.45, 2.95]},
    # M1A1、96 式：炮管（连炮盾、并列机枪）烘焙在炮塔里——拆成炮，照炮耳轴俯仰；炮管本来就是平的
    'm1a1': {'rules': [{'from': 'Turret', 'to': 'Gun', 'box': [0.79, 5.10, -0.42, 0.25], 'zmin': 1.80}],
             'gun': [0.95, 0.015, 2.125]},
    # 悍马（M998 软篷）：原模型没有机枪——游戏里在车顶补一挺零件拼的 M2（客户端 VehModels 看 mg）：座圈在篷顶上，
    #   枪架高 0.46 米，耳轴到枪口 1.35 米（muz）
    'hmmwv': {'rules': [], 'tur': [-0.25, 0, 1.84], 'gun': [-0.25, 0, 2.30], 'mg': 'm2', 'muz': 1.35},
    # M1A2 SEPV2（沙漠涂装）：车长指挥塔上的 CROWS 遥控武器站拆成 Rws（跟着炮塔转、自己再转），上面的 M2 拆成 RwsGun（自己俯仰）——
    #   用户：机枪也要能转动、开火位置和枪口对上、弹道顺着枪管；rws 底座转轴、rwg M2 的俯仰轴（网页版烘焙坐标，米）；
    #   sight 炮长主瞄准镜（主炮右边、炮塔前沿那个方盒子）：瞄准镜视角从这里看出去（用户：观瞄系统位置要对）
    #   W01、W02 是车头首上两侧的车灯组（烘焙时按圆形零件当成了车轮，开车时会跟着转）：并回车身
    'm1a2dc': {'rules': [{'from': 'Turret', 'to': 'Rws', 'box': [-0.78, 0.95, -1.06, -0.36], 'zmin': 2.60},
                         {'from': 'Rws', 'to': 'RwsGun', 'box': [-0.78, 0.95, -0.80, -0.60], 'zmin': 3.12},
                         {'from': 'W01', 'to': 'Body', 'box': [-9, 9, -9, 9]}, {'from': 'W02', 'to': 'Body', 'box': [-9, 9, -9, 9]},
                         # 炮塔两侧前段的附加装甲块和挂架下沿低于烘焙时炮塔的 zmin（1.75 米），留在了车身：转炮塔时会留在原地
                         {'from': 'Body', 'to': 'Turret', 'box': [-3.15, 0.85, -1.95, 1.95], 'zmin': 1.66},
                         # 炮盾上面、两边伸出炮塔正面的零件（炮盾顶甲、并列机枪、炮上那挺 M2 的弹箱）：跟着炮俯仰
                         {'from': 'Body', 'to': 'Gun', 'box': [1.40, 2.10, -0.50, 0.50], 'zmin': 1.85}],
               'rws': [-0.30, -0.71, 2.65], 'rwg': [-0.05, -0.71, 3.235], 'sight': [0.93, -0.28, 2.24]},
    'ztz96': {'rules': [{'from': 'Turret', 'to': 'Body', 'box': [-5, 5.2, -2, 2], 'zmax': 1.585},   # 网页版炮塔框带进来的车体甲板零件（挡泥板沿、螺栓）还给车体
                        {'from': 'Turret', 'to': 'Gun', 'box': [-0.66, 5.10, -0.40, 0.27], 'zmin': 1.50}],
              'gun': [0.05, -0.01, 1.785]},
}


def _components(T):
    """三角形的连通块（T：每个三角形三个顶点的焊接编号）→ 每个三角形的块号"""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    n = int(T.max()) + 1 if len(T) else 0
    r = np.concatenate([T[:, 0], T[:, 1]])
    c = np.concatenate([T[:, 1], T[:, 2]])
    g = coo_matrix((np.ones(len(r), dtype=np.int8), (r, c)), shape=(n, n))
    _, lab = connected_components(g, directed=False)
    return lab[T[:, 0]]


def split_parts(key, VB, bins):
    """按 SPLIT 把整块落在框里的连通块挪到别的部件（bins：(部件, 材质) → [三角形顶点下标]）"""
    cfg = SPLIT[key]
    fl = key in FLIP
    P = VB[:, 0:3].astype(np.float64)
    q = np.round(P / 0.001).astype(np.int64)   # 按位置焊接（1 毫米）：同一个零件上 UV 接缝处的顶点是分开存的
    _, weld = np.unique(q, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    for rule in cfg['rules']:
        b = rule['box']
        box = [-b[1], -b[0], -b[3], -b[2]] if fl else b
        src = sorted(k for k in bins if k[0] == rule['from'])
        if not src:
            continue
        tris = [np.concatenate(bins[k]).reshape(-1, 3) for k in src]
        allT = np.concatenate(tris)
        lab = _components(weld[allT])
        pts = P[allT]
        nc = int(lab.max()) + 1
        clo, chi = np.full((nc, 3), np.inf), np.full((nc, 3), -np.inf)
        np.minimum.at(clo, lab, pts.min(axis=1))
        np.maximum.at(chi, lab, pts.max(axis=1))
        e = 0.005
        ok = (clo[:, 0] >= box[0] - e) & (chi[:, 0] <= box[1] + e) & (clo[:, 1] >= box[2] - e) & (chi[:, 1] <= box[3] + e)
        if 'zmin' in rule:
            ok &= clo[:, 2] >= rule['zmin'] - e
        if 'zmax' in rule:
            ok &= chi[:, 2] <= rule['zmax'] + e
        selT = ok[lab]
        o = 0
        for k, t in zip(src, tris):
            s = selT[o:o + len(t)]
            o += len(t)
            if not s.any():
                continue
            bins.setdefault((rule['to'], k[1]), []).append(t[s].reshape(-1))
            rest = t[~s]
            if len(rest):
                bins[k] = [rest.reshape(-1)]
            else:
                del bins[k]
        print('  %s 拆分 %s → %s：%d 个三角形（%d 块）' % (key, rule['from'], rule['to'], int(selT.sum()), len(np.unique(lab[selT]))))
    if cfg.get('lvl') and 'gun' in cfg:   # 原模型里炮（机枪）是抬着的：绕炮耳轴压平（顶点、法线一起转；拆出来的连通块不和别的块共用顶点）
        g = [np.concatenate(v) for k, v in bins.items() if k[0] == 'Gun']
        if g:
            u = np.unique(np.concatenate(g))
            p0 = np.array(cfg['gun'], dtype=np.float64)
            if fl:
                p0[0:2] *= -1
            e = math.radians(cfg['lvl'])
            ce, se = math.cos(e), math.sin(e)
            for o in (0, 3):   # 位置（绕炮耳轴）、法线
                x = VB[u, o].astype(np.float64) - (p0[0] if o == 0 else 0)
                z = VB[u, o + 2].astype(np.float64) - (p0[2] if o == 0 else 0)
                VB[u, o] = x * ce + z * se + (p0[0] if o == 0 else 0)
                VB[u, o + 2] = -x * se + z * ce + (p0[2] if o == 0 else 0)
            print('  %s 炮压平 %.1f°（%d 个顶点）' % (key, cfg['lvl'], len(u)))
    return bins
WRAP = {0: 10497, 1: 33071, 2: 33648}   # 重复、夹边、镜像


def load(key):
    t = open(os.path.join(WEB, 'js', 'mdl', key + '.js'), encoding='utf-8').read()
    a = t.index('V3G.add(') + 8
    q, e = t.rindex(", '"), t.rindex("')")
    head = t[a:q]
    c = head.index(',')
    meta = json.loads(head[c + 1:])
    credit = t.split('\n', 1)[0].lstrip('/ ').strip()
    return meta, base64.b64decode(t[q + 3:e]), credit


def rb(v):   # 网页版坐标（米）→ Roblox（格）
    v = np.asarray(v, dtype=np.float64)
    return np.stack([-v[..., 1], v[..., 2], -v[..., 0]], axis=-1) * S


def rbn(n):  # 法线：同样转，不缩放
    n = np.asarray(n, dtype=np.float64)
    return np.stack([-n[..., 1], n[..., 2], -n[..., 0]], axis=-1)


def part_group(meta, pi, wheel_ix):
    if pi < 0:
        return 'Body'
    p = meta['parts'][pi]
    n, k = p.get('n', ''), p.get('k', '')
    if n == 'whl':
        return 'W%02d' % wheel_ix[pi]
    if n in GROUP:
        return GROUP[n]
    if k == 'yaw':
        return 'Turret'
    return 'Body'


def image_bytes(meta, binb, ii, alpha):
    """贴图 → (字节, mime)：PNG / JPEG 原样留着（太大才缩），别的格式转一下"""
    I = meta['imgs'][ii]
    raw = binb[I['o']:I['o'] + I['n']]
    im = Image.open(io.BytesIO(raw))
    big = max(im.size) > TEXMAX
    if not big and I['m'] in ('image/jpeg', 'image/png'):
        return raw, I['m'], im.size
    if big:
        k = TEXMAX / max(im.size)
        im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
    buf = io.BytesIO()
    if alpha or im.mode in ('RGBA', 'LA', 'P'):
        im.convert('RGBA').save(buf, 'PNG', optimize=True)
        return buf.getvalue(), 'image/png', im.size
    im.convert('RGB').save(buf, 'JPEG', quality=90)
    return buf.getvalue(), 'image/jpeg', im.size


def convert(key, src=None):
    """src：(meta, binb, credit)，不给就读网页版的 js/mdl/<键>.js（Sketchfab 直接下载的模型由 sfveh.py 做成同样的数据）"""
    meta, binb, credit = src or load(key)
    st = meta.get('st', 8)
    vb0, vbn = meta['vb']
    VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st)
    if key in FLIP:   # 绕竖轴转 180°（网页版坐标 x 前、y 左、z 上：x、y 取反，法线一样；部件的支点、轴跟着转）
        VB = VB.copy()
        VB[:, [0, 1, 3, 4]] *= -1
        for P in meta.get('parts', []):
            for k in ('p', 'a', 'q'):
                if k in P:
                    P[k] = [-P[k][0], -P[k][1], P[k][2]]
    ib0, ibn = meta['ib']
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0)
    wheel_ix = {}
    for pi, p in enumerate(meta.get('parts', [])):
        if p.get('n') == 'whl':
            wheel_ix[pi] = len(wheel_ix) + 1
    segs = meta['lod'][0]   # 最精细的一档
    # 按（部件，材质）收三角形
    bins = {}
    for mi, pi, s0, cnt in segs:
        g = part_group(meta, pi, wheel_ix)
        bins.setdefault((g, mi), []).append(IB[s0:s0 + cnt])
    if key in RECOLOR:   # 按材质 + 高度挑出来的三角形换成新材质（轮胎、玻璃）
        newmi = {}
        for nm, m in NEWMAT.items():
            meta['mats'].append(dict(m))
            newmi[nm] = len(meta['mats']) - 1
        for rule in RECOLOR[key]:
            for (g, mi) in list(bins):
                if mi not in rule['mats']:
                    continue
                tri = np.concatenate(bins[(g, mi)]).reshape(-1, 3)
                z = VB[tri, 2].mean(axis=1)
                sel = np.ones(len(tri), dtype=bool)
                if 'zmax' in rule:
                    sel &= z <= rule['zmax']
                if 'zmin' in rule:
                    sel &= z > rule['zmin']
                if not sel.any():
                    continue
                bins.setdefault((g, newmi[rule['to']]), []).append(tri[sel].reshape(-1))
                rest = tri[~sel].reshape(-1)
                if len(rest):
                    bins[(g, mi)] = [rest]
                else:
                    del bins[(g, mi)]
    if key in SPLIT:   # 和车身烘焙在一起的机枪塔、炮管拆出来
        if not VB.flags.writeable:   # 要压平炮管时改顶点
            VB = VB.copy()
        bins = split_parts(key, VB, bins)
    pieces = []   # (部件, 材质, 顶点下标数组)
    for (g, mi), lst in sorted(bins.items()):
        idx = np.concatenate(lst).reshape(-1, 3)
        for c0 in range(0, len(idx), CHUNK):
            pieces.append((g, mi, idx[c0:c0 + CHUNK]))
    # 原点：车身（不含炮塔、炮）的中心、全车最低点——坦克的炮管往前伸好几米，按整个包围盒取中心的话，
    #   车身会比游戏里的碰撞盒往后错开 2～4 格
    used = np.unique(np.concatenate([p[2].reshape(-1) for p in pieces]))
    allP = rb(VB[used, 0:3])
    lo, hi = allP.min(0), allP.max(0)
    hull_ix = [p[2].reshape(-1) for p in pieces if p[0] not in ('Turret', 'Gun', 'Rws', 'RwsGun')]
    hP = rb(VB[np.unique(np.concatenate(hull_ix)), 0:3]) if hull_ix else allP
    hlo, hhi = hP.min(0), hP.max(0)
    org = np.array([(hlo[0] + hhi[0]) / 2, lo[1], (hlo[2] + hhi[2]) / 2])
    info = {'len': float(hi[2] - lo[2]), 'w': float(hi[0] - lo[0]), 'h': float(hi[1] - lo[1]),
            'hull': [round(float(x), 3) for x in (hhi - hlo)], 'parts': {}, 'wheels': {}, 'credit': credit}
    out = []   # (节点名, 部件, 材质, P, N, UV, idx)
    count = {}
    for g, mi, tri in pieces:
        u, inv = np.unique(tri.reshape(-1), return_inverse=True)
        v = VB[u]
        P = rb(v[:, 0:3]) - org
        N = rbn(v[:, 3:6])
        UV = v[:, 6:8].astype(np.float64)
        count[g] = count.get(g, 0) + 1
        name = '%s_%d' % (g, count[g])
        plo, phi = P.min(0), P.max(0)
        c = (plo + phi) / 2
        info['parts'][name] = {'g': g, 'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in np.maximum(phi - plo, 0.02)]}
        m = meta['mats'][mi]
        if not m.get('t'):   # 没有底色贴图的材质（JLTV、M270 整车都是）：Studio 导入不一定把材质颜色带到 MeshPart 上，游戏里照这个上色
            lin = m.get('c', [1, 1, 1, 1])
            srgb = [int(round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in (max(0.0, min(1.0, float(v))) for v in lin[:3])]
            info['parts'][name]['col'] = srgb
            if m.get('am', 0) == 2 and len(lin) > 3 and lin[3] < 0.99:
                info['parts'][name]['a'] = round(float(lin[3]), 2)
            if (m.get('mr') or [0, 0.8])[0] > 0.5:
                info['parts'][name]['met'] = 1
        out.append((name, g, mi, P - c, N, UV, inv.reshape(-1, 3).astype(np.uint32)))
    # 车轮：每个轮（几块合起来）的中心和半径
    for g in sorted(set(p[1] for p in out if p[1].startswith('W'))):
        Ps = [o[3] + np.array(info['parts'][o[0]]['c']) for o in out if o[1] == g]
        A = np.concatenate(Ps)
        wlo, whi = A.min(0), A.max(0)
        info['wheels'][g] = {'c': [round(float(x), 3) for x in (wlo + whi) / 2], 'r': round(float(max(whi[1] - wlo[1], whi[2] - wlo[2]) / 2), 3)}
    # 炮塔转轴、炮耳轴、炮口
    for p in meta.get('parts', []):
        n = p.get('n', '')
        if n in ('tur', 'rws') or p.get('k') == 'yaw':
            info['tur'] = [round(float(x), 3) for x in (rb(p['p']) - org)]
        if n in ('gun', 'lnch') and 'q' in p:
            info['gun'] = [round(float(x), 3) for x in (rb(p['q']) - org)]
    for nm in ('tur', 'gun'):   # 拆出来的机枪塔、炮：转轴照 SPLIT
        if nm in SPLIT.get(key, {}):
            p = SPLIT[key][nm]
            if key in FLIP:
                p = [-p[0], -p[1], p[2]]
            info[nm] = [round(float(x), 3) for x in (rb(p) - org)]
    if SPLIT.get(key, {}).get('mg'):   # 零件拼的机枪（原模型没有）：耳轴到枪口多远直接给
        info['mg'] = SPLIT[key]['mg']
        info['muz'] = round(SPLIT[key]['muz'] * S, 3)
    if 'gun' in info and 'mg' not in info:
        G = [o[3] + np.array(info['parts'][o[0]]['c']) for o in out if o[1] == 'Gun']
        if G:
            A = np.concatenate(G)
            info['muz'] = round(float(info['gun'][2] - A[:, 2].min()), 3)   # 炮口在耳轴前面多远（−Z 朝前）
    sp = SPLIT.get(key, {})

    def rbo(p):   # 网页版烘焙坐标（米）→ 这辆车的 Roblox 模型坐标（格）
        p = [-p[0], -p[1], p[2]] if key in FLIP else p
        return [round(float(x), 3) for x in (rb(p) - org)]
    if sp.get('rws'):   # 遥控武器站：底座转轴 p、机枪俯仰轴 g、枪口在俯仰轴前面多远 muz（量拆出来的 RwsGun）
        R = {'p': rbo(sp['rws']), 'g': rbo(sp['rwg'])}
        G = [o[3] + np.array(info['parts'][o[0]]['c']) for o in out if o[1] == 'RwsGun']
        if G:
            R['muz'] = round(float(R['g'][2] - np.concatenate(G)[:, 2].min()), 3)
        info['rws'] = R
    for nm in ('sight', 'coax'):   # 炮长主瞄准镜、并列机枪口：照原模型的位置
        if sp.get(nm):
            info[nm] = rbo(sp[nm])
    return meta, binb, info, out


def write_glb(key, meta, binb, info, out, path, prefix='V_'):
    J = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield mdl2glb.py'}, 'scene': 0, 'scenes': [{'name': prefix + key, 'nodes': [0]}],
         'nodes': [{'name': prefix + key, 'children': []}], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [], 'materials': [],
         'textures': [], 'images': [], 'samplers': []}
    blob = bytearray()

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        o = len(blob)
        blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': o, 'byteLength': len(data)}
        if target:
            bv['target'] = target
        J['bufferViews'].append(bv)
        return len(J['bufferViews']) - 1

    def acc(arr, typ, ctype=5126, minmax=False, target=34962):
        a = {'bufferView': view(np.ascontiguousarray(arr).tobytes(), target), 'componentType': ctype, 'count': len(arr), 'type': typ}
        if minmax:
            a['min'] = [float(v) for v in arr.min(0)]
            a['max'] = [float(v) for v in arr.max(0)]
        J['accessors'].append(a)
        return len(J['accessors']) - 1

    img_ix, samp_ix, tex_ix = {}, {}, {}

    def texture(ref, alpha=False):
        if not ref:
            return None
        ii = ref[0]
        wrap = (WRAP.get(ref[1] if len(ref) > 1 else 0, 10497), WRAP.get(ref[2] if len(ref) > 2 else 0, 10497))
        if ii not in img_ix:
            data, mime, size = image_bytes(meta, binb, ii, alpha)
            J['images'].append({'bufferView': view(data), 'mimeType': mime, 'name': '%s%s_tex%d' % (prefix, key, ii)})
            img_ix[ii] = len(J['images']) - 1
        if wrap not in samp_ix:
            J['samplers'].append({'wrapS': wrap[0], 'wrapT': wrap[1], 'magFilter': 9729, 'minFilter': 9987})
            samp_ix[wrap] = len(J['samplers']) - 1
        k = (img_ix[ii], samp_ix[wrap])
        if k not in tex_ix:
            J['textures'].append({'source': k[0], 'sampler': k[1]})
            tex_ix[k] = len(J['textures']) - 1
        return tex_ix[k]

    mat_ix = {}

    def material(mi):
        if mi in mat_ix:
            return mat_ix[mi]
        m = meta['mats'][mi]
        am = m.get('am', 0)
        pbr = {'baseColorFactor': [float(x) for x in m.get('c', [1, 1, 1, 1])]}
        mr = m.get('mr') or [0, 0.8]
        pbr['metallicFactor'], pbr['roughnessFactor'] = float(mr[0]), float(mr[1])
        t = texture(m.get('t'), am != 0)
        if t is not None:
            pbr['baseColorTexture'] = {'index': t}
        if m.get('mrt') and not m.get('sg'):
            t2 = texture(m.get('mrt'))
            if t2 is not None:
                pbr['metallicRoughnessTexture'] = {'index': t2}
        M = {'name': '%s%s_%s' % (prefix, key, m.get('n', 'm%d' % mi)), 'pbrMetallicRoughness': pbr, 'doubleSided': bool(m.get('ds', 0))}
        if m.get('nt'):
            tn = texture(m.get('nt'))
            if tn is not None:
                M['normalTexture'] = {'index': tn, 'scale': float(m.get('ns', 1))}
        if am == 1:
            M['alphaMode'], M['alphaCutoff'] = 'MASK', float(m.get('ac', 0.5))
        elif am == 2:
            M['alphaMode'] = 'BLEND'
        J['materials'].append(M)
        mat_ix[mi] = len(J['materials']) - 1
        return mat_ix[mi]

    for name, g, mi, P, N, UV, idx in out:
        nrm = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        prim = {'attributes': {'POSITION': acc(P.astype(np.float32), 'VEC3', minmax=True), 'NORMAL': acc(nrm.astype(np.float32), 'VEC3'),
                               'TEXCOORD_0': acc(UV.astype(np.float32), 'VEC2')},
                'indices': acc(idx.reshape(-1), 'SCALAR', 5125, target=34963), 'material': material(mi)}
        J['meshes'].append({'name': '%s%s__%s' % (prefix, key, name), 'primitives': [prim]})
        J['nodes'].append({'name': '%s%s__%s' % (prefix, key, name), 'mesh': len(J['meshes']) - 1, 'translation': info['parts'][name]['c']})
        J['nodes'][0]['children'].append(len(J['nodes']) - 1)
    if not J['samplers']:
        del J['samplers']
    for k in ('textures', 'images'):
        if not J[k]:
            del J[k]
    J['buffers'].append({'byteLength': len(blob)})
    js = json.dumps(J, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)
    # 导入 Roblox 前的修正：朝里的面翻过来（Roblox 只画正面）、只有底色的材质配纯色贴图（Roblox 导入不认底色）——tools/models/glbfix.py
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import glbfix
    glbfix.fix_file(path, log=lambda m: print('  %s%s' % (key, m)))


def web_credits(keys):
    """网页版 docs/credits.md 里各模型那一条：键 → (中文名, 英文署名 + 网页版的改动)"""
    out = {}
    try:
        for ln in open(os.path.join(WEB, 'docs', 'credits.md'), encoding='utf-8'):
            for key in keys:
                if '（js/mdl/%s.js）：' % key in ln:
                    out[key] = ln.strip().lstrip('- ').split('（js/mdl/', 1)[0], ln.strip().split('.js）：', 1)[1]
    except OSError:
        pass
    return out


def write_credits(path, keys, meta_out, head, extra=None):
    """署名（CC-BY 要写作者、出处、授权、改了什么）：照网页版 docs/credits.md 那一条（含网页版的改动），前面 head 写这里的改动；
    extra：[(名字, 模型键, 署名)]，网页版以外来的模型（Sketchfab 直接下载的）接在后面"""
    wc = web_credits(keys)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(head)
        for key in keys:
            if key in wc:
                name, line = wc[key]
                f.write('- %s（%s.glb）：%s\n' % (name, key, line.replace('（改动：', '（网页版的改动：')))
            elif key in meta_out:
                f.write('- %s.glb：%s\n' % (key, meta_out[key]['credit']))
        if extra:
            f.write('\n网页版没有、直接从 Sketchfab 下载的（tools/models/sfveh.py）：\n')
            for name, key, line in extra:
                f.write('- %s（%s.glb）：%s\n' % (name, key, line))


def lua(v):
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            kk = ('[%d]' % k) if isinstance(k, int) else (k if k.isidentifier() else '[%s]' % json.dumps(k, ensure_ascii=False))
            items.append('%s = %s' % (kk, lua(v[k])))
        return '{ ' + ', '.join(items) + ' }'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, (bool, np.bool_)):   # 要在 int 前面判断（Python 里 True 也是 int）；numpy 的布尔也算
        return 'true' if v else 'false'
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, float):
        return ('%.3f' % v).rstrip('0').rstrip('.')
    return str(v)


def old_lines(path):
    """原来元数据里每个模型那一行（'    键 = { … },'）：没转的模型照旧"""
    out = {}
    try:
        inm = False
        for ln in open(path, encoding='utf-8'):
            if ln.startswith('  m = {'):
                inm = True
            elif inm and ln.startswith('  },'):
                inm = False
            elif inm and ln.startswith('    ') and ' = { ' in ln:
                out[ln.split(' = ', 1)[0].strip()] = ln
    except OSError:
        pass
    return out


if __name__ == '__main__':
    argv = sys.argv[1:]
    SFDIR = None
    if '--sf' in argv:
        j = argv.index('--sf')
        SFDIR = argv[j + 1]
        del argv[j:j + 2]
    WEB = argv[0]
    OUTDIR = argv[1] if len(argv) > 1 else OUTDIR
    META = argv[2] if len(argv) > 2 else META
    ONLY = argv[3:]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sfveh
    alias = dict(ALIAS)
    for key, c in sfveh.SF.items():
        for a in c['alias']:
            alias[a] = key
    webkeys = sorted(set(ALIAS.values()))
    keys = sorted(set(webkeys) | set(sfveh.SF))
    os.makedirs(OUTDIR, exist_ok=True)
    meta_out = {}
    for key in keys:
        if ONLY and key not in ONLY:
            continue
        if key in sfveh.SF:
            zp = SFDIR and os.path.join(SFDIR, key + '.zip')
            if not (zp and os.path.exists(zp)):
                continue
            meta, binb, credit, rep = sfveh.load(key, zp)
            print('%-8s 扫描：放大 %.1f 倍，炮塔转回 %.1f°，三角形 车体 %d / 炮塔 %d / 炮 %d / 底板 %d' % ((key, rep['k'], -rep['yaw']) + rep['tris']))
            meta, binb, info, out = convert(key, (meta, binb, credit))
        else:
            meta, binb, info, out = convert(key)
        path = os.path.join(OUTDIR, key + '.glb')
        write_glb(key, meta, binb, info, out, path)
        meta_out[key] = info
        tris = sum(len(o[6]) for o in out)
        print('%-8s %7d 个三角形  %2d 块  %5.1f × %4.1f × %4.1f 格  %5.1f MB  炮塔 %-5s 炮 %-5s 车轮 %d' % (
            key, tris, len(out), info['len'], info['w'], info['h'], os.path.getsize(path) / 1e6, 'tur' in info, 'gun' in info, len(info['wheels'])))
    old = old_lines(META)
    rows, have = [], set()
    for key in keys:
        if key in meta_out:
            rows.append('    %s = %s,\n' % (key, lua(meta_out[key])))
        elif key in old:
            rows.append(old[key])
            print('%-8s 没转，元数据照旧' % key)
        else:
            print('%-8s 没转、原来也没有：游戏里用零件拼的' % key)
            continue
        have.add(key)
    # tools/models/blveh.py（Blender 直接转 Sketchfab 原文件）管的模型：这里不转，元数据那一行、alias、old（没重新导入时退回的旧模型键）照旧
    olds = {}
    try:
        BL = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'blveh.json'), encoding='utf-8'))
    except OSError:
        BL = {}
    for bkey, bc in sorted(BL.items()):
        if bkey in old and bkey not in have:
            rows.append(old[bkey])
            have.add(bkey)
            for a in bc.get('alias', []):
                alias[a] = bkey
                if bc.get('old') and bc['old'] in have:
                    olds[a] = bc['old']
            print('%-8s blveh.py 转的，元数据照旧' % bkey)
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/mdl2glb.py），别手改：装备原模型（models/veh/<模型键>.glb）的元数据——网页版的模型原样转的，网页版没有的从 Sketchfab 下载（tools/models/sfveh.py）\n')
        f.write('--   alias：游戏里的型号 → 模型键；m[模型键] = { len 长 / w 宽 / h 高（格，真实尺寸：1 米 = 2.8 格；含炮管、天线）, hull 车身的宽高长（不含炮塔、炮）,\n')
        f.write('--     parts[块名] = { g 部件（Body / Turret / Gun / W01…）, c 中心, s 大小,\n')
        f.write('--       col 没有底色贴图的块的颜色（sRGB 0–255）, a 不透明度（半透明的才有）, met 金属 }（原点在车底中心，−Z 朝前）,\n')
        f.write('--     tur 炮塔转轴, gun 炮耳轴, muz 炮口在耳轴前多远, wheels[部件] = { c 中心, r 半径 }, credit 署名 }；导入后 MeshPart 叫 V_<模型键>__<块名>\n')
        f.write('--     old：游戏里的型号 → 旧模型键（alias 那个模型没导入时退回旧的，tools/models/blveh_meta.py）；int：原模型自带车内（块的 k = "int"）；'
                'src：原模型 glTF 坐标 → 这里的坐标（tools/models/blveh.py）；pts：原模型上量的点（格）\n')
        f.write('return {\n  alias = ' + lua({a: k for a, k in alias.items() if k in have}) + ',\n')
        if olds:
            f.write('  old = ' + lua(olds) + ',\n')
        f.write('  m = {\n')
        f.writelines(rows)
        f.write('  },\n}\n')
    extra = [(c['name'], key, sfveh.credit(key)) for key, c in sorted(sfveh.SF.items()) if key in have]
    extra += [(bc['title'], bkey, '%s（%s）' % (bc['creditEn'], bc.get('changes', ''))) for bkey, bc in sorted(BL.items()) if bkey in have and 'creditEn' in bc]   # blveh.py 转的
    write_credits(os.path.join(OUTDIR, 'credits.txt'), [k for k in webkeys if k in have], meta_out,
                  'Roblox全面大战场的地面载具模型（models/veh/<模型键>.glb）：从网页版《暗剑》烘焙的装备模型原样转换（js/mdl/<模型键>.js）\n'
                  '  这里的改动：坐标换成 Roblox 的轴向、按 1 米 = 2.8 格缩放、原点挪到车底中心；按部件（车体 / 炮塔 / 炮 / 每个车轮）和材质切成几块，'
                  '每块不超过 %d 个三角形；超过 %d 像素的贴图缩到 %d；不减面\n\n' % (CHUNK, TEXMAX, TEXMAX), extra)
    print('写好了 %s/*.glb、%s/credits.txt 和 %s' % (OUTDIR, OUTDIR, META))
