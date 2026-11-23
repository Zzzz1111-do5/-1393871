# Sketchfab 上直接下载的飞机模型（网页版没有的型号：歼-11、歼-10、歼-36、苏-30、苏-25……；用户 11-22：「sketchfeb 有个 j36 j10 j11 还有一些俄苏的武器载具
#   你全部下载下来做进去……所有飞机飞控系统都要能动 每个位置都要能动 包括起落架」）→ 和网页版烘焙的 js/mdl/<键>.js 一样的数据，再走 air2glb.py 同一套：
#   舵面 / 座舱盖 / 减速板：原模型分好节点的按节点（SPEC 的 nodes，铰链按那一块的形状自动算），没分的按 air_anim.SURF 的切法切；
#   起落架（SPEC 的 gear 节点）按 air_anim.GEAR 分前 / 左 / 右，各自绕支柱顶上的铰链收；挂点贴机翼下表面；座舱里飞行员的头 air_anim.PIT；
#   写出 models/air/<键>.glb、ImportedAir.lua 里这个模型那一行（alias 指过来，同 air_one.py）、models/air/credits.txt 一行
#   python3 -I tools/models/sf_air.py <模型键> <下载的 .glb> <AirDefs 的 JSON> [--view <预览图.png>] [--dry]
#     AirDefs 的 JSON：lune run tools/models/airdefs.luau > airdefs.json（新型号要先写进 AirDefs.lua：挂点按它贴到机翼上）
#     --view：按游戏里的坐标画俯视 / 侧视 / 前视 / 仰视（活动部件上色、铰链画红线）看对不对；--dry 只画图不写文件
#   收模型的规矩同 sfveh.py：只要 CC-BY / CC0；简介、节点名、贴图看得出是从游戏里扒的不收（MirzaArrafi 的歼-10S 简介写着是 MFS X 的 BearStudios 做的、
#   42manako 的歼-11 写着「Not my model」、KojfDiscord 的一批写着 War Thunder——都没收）
import io, json, math, os, re, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
import air2glb as X   # noqa: E402
import air_anim as A   # noqa: E402
import air_kf as KF   # noqa: E402

LIC = 'CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）'


def credit(cn, title, author, uid, slug):
    return '%s：%s，作者 %s（https://sketchfab.com/3d-models/%s-%s），%s。署名见 docs/credits.md' % (cn, title, author, slug, uid, LIC)


# 每个模型：ids 游戏里哪些型号用它；fwd / up 原模型里机头、头顶朝哪根轴；len 真机全长（米，按它缩放）；
#   level 左右对称的节点（正则，左、右）：按它们把侧倾 / 偏航摆正（有的模型摆成转弯的样子）；drop 去掉的节点（外挂、挂架、导弹、灯光道具）；
#   gear 起落架（支柱、机轮、舱门：按连通块分前 / 左 / 右，air_anim.GEAR 的收法）；nodes 分好节点的活动部件：正则 → (部件名, 动法, 附加)；
#   动法同 air_anim（ail 副翼 / flap / flaperon / elevon / stab 全动平尾 / elev / can 鸭翼 / rud / fin / canopy / abrk 减速板）；
#   pit 飞行员头（网页版坐标：x 前、y 左、z 上，米，地面 z = 0）；noz 尾喷口 [x, |y|, z, 半径]；surf / gear_mode 见 air_anim.SURF / GEAR
SPEC = {
    # 歼-11（Rhine_Lab_Muelsyse 的 Shenyang J-11，CC-BY）：舵面、起落架、舱门、座舱盖、减速板都是单独的节点；整架摆成右翼抬起约 15° 的样子
    'j11': {
        'ids': ['j11'],
        'credit': credit('歼-11', 'Shenyang J-11', 'Rhine_Lab_Muelsyse', 'f3b0a285198a4523b96b9ac372e18865', 'shenyang-j-11'),
        'fwd': '-z', 'up': '+y', 'len': 21.9,
        'level': [(r'^Left_Fin\b', r'^Right_Fin\b'), (r'^Left_Stab\b', r'^Right_Stab\b'), (r'^Left_Rudder\b', r'^Right_Rudder\b'),
                  (r'^Left_Flap\b', r'^Right_Flap\b')],
        # 原模型是飞行状态：起落架收在舱里、舱门关着——收着的支柱、机轮去掉（游戏里用零件拼的起落架放下来），舱门做成放起落架时打开（gdh：放的前 1/4 先开门）
        'drop': [r'^BOMB\d', r'^Sop', r'^Fijo', r'^AAM_wings', r'^ECM\b', r'^light\b', r'^Front_Gear\b', r'Right_Gear', r'Left_Gear', r'Damper'],
        'pitch': -9.0, 'level_gear': False, 'lift': 2.0,   # 真机全高 5.9 米：机腹离地约 2 米
        'nodes': {
            r'^gear_hatch_r\d': ('GDoorR', 'gdh', {'A': 1.45}), r'^gear_hatch_l\d': ('GDoorL', 'gdh', {'A': 1.45}),
            r'^nose_gear_hatch\b': ('GDoorN', 'gdh', {'A': 1.4, 'split': 'y'}),
            r'^Right_Stab\b': ('StabR', 'stab'), r'^Left_Stab\b': ('StabL', 'stab'),
            r'^Right_Flap\b': ('FlpR', 'flaperon'), r'^Left_Flap\b': ('FlpL', 'flaperon'),
            r'^Right_Rudder\b': ('RudR', 'rud'), r'^Left_Rudder\b': ('RudL', 'rud'),
            r'^Canopy': ('Canopy', 'canopy', {'A': 0.75}),
            r'^Airbrake\b': ('Brake', 'abrk', {'A': 0.9}),
        },
        'noz': [[-9.9, 0.85, 1.55, 0.6]],
    },
    # 歼-10C（andertan 的 Chengdu J10 "Vigorous Dragon"，CC-BY）：飞行状态（没放起落架），鸭翼和机翼一个节点、方向舵和机身一个节点、
    #   三个副油箱跟机身一个节点（按连通块去掉）；内外两段升降副翼是单独的节点；座舱盖（前面的风挡不动）、仪表板、平显
    'j10': {
        'ids': ['j10'],
        'credit': credit('歼-10C', 'Chengdu J10 "Vigorous Dragon"', 'andertan', '3a1a1863e9ba44e88d35da0d5f23caeb', 'chengdu-j10-vigorous-dragon'),
        'fwd': '+x', 'up': '+y', 'len': 16.9, 'lift': 0.9,   # 真机全高 5.43 米：腹鳍离地约 0.9 米
        'drop': [r'^Sphere\.007_4$'],   # 翼下、进气道下的导弹和挂架（游戏按选的挂载另画）
        'comp': [
            {'node': r'^Cylinder_13$', 'sel': {'zmax': -0.26}, 'drop': True},   # 三个副油箱和尾翼（和机身一个节点）
            {'node': r'^Plane\.002_9$', 'sel': {'x': [0.5, 3.6], 'z': [0.4, 0.8]}, 'g': 'Can', 'k': 'can', 'split': 'y'},
            {'node': r'^Plane\.005_8$', 'sel': {'ay': [2.4, 5.2]}, 'g': 'ElvO', 'k': 'elevon', 'split': 'y'},
            {'node': r'^Plane\.005_8$', 'sel': {'ay': [0.5, 2.4]}, 'g': 'ElvI', 'k': 'elevon', 'split': 'y'},
            {'node': r'^Plane\.006_7$', 'sel': {'x': [2.5, 4.4]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.8}},
        ],
        # 方向舵：垂尾后缘往前 0.9 米切下来（腹鳍最低点是地面以上 0.9 米，表里的高度按这个量的）
        'surf': [{'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'mir': False, 'r': [2.45, 4.35], 'x': [-9.5, -6.0], 'w': [-0.15, 0.15], 'c': 0.9}],
        'noz': [[-7.89, 0.0, 1.16, 0.53]],
    },
    # 歼-36（positivevubez4eva 的 J36 v2，CC-BY）：在模拟飞行沙盒里用零件拼的，导出时按材质合并——节点名都是 Object_N，活动部件全靠连通块 / 切法挑。
    #   Object_2～17 是字（机徽、编号、座舱仪表上的字，十万个三角形，都是几何体、不带贴图）：用户 11-23「j36 你给我用那个 30w 个三角形的模型」——
    #   v2（键名 j36_v2）把字都放回来（原来 11-22 那版去掉了，键名 j36，留在 old 表里给已经导入过的人）；
    #   只去掉 Object_4：一层看不见的座舱盖（DoNothing 材质，不透明度 0——导进 Roblox 会变成不透明的罩子）；
    #   弹舱里装着导弹（细长的连通块）：去掉，游戏按挂载另画；起落架放着（小车式主起落架一边前后两个轮、双轮前起落架），开着的舱门收起一半时藏起来；
    #   三台发动机的喷口在机背的槽里；无尾——后缘三段升降副翼，最外一段兼管偏航
    'j36': {
        'ids': ['j36'],
        'credit': credit('歼-36', 'J36, J-36, J 36 ,v2 Chengdu Aircraft Corporation', 'positivevubez4eva', '0f7f57092bbd438fb788302e47279fc0',
                         'j36-j-36-j-36-v2-chengdu-aircraft-corporation')
                  + '（改动：转成 Roblox 坐标，升降副翼、弹舱门、座舱盖、起落架切成会动的块；去掉一层看不见的座舱盖和弹舱里自带的导弹）',
        'fwd': '+z', 'up': '+y', 'len': 22.98, 'pitch': 0.57,   # 前轮比主轮低 0.09 米：摆平让三个轮子一起着地
        'kname': 'j36_v2',   # 导入后的键名（块叫 A_j36_v2__…）；文件还是 models/air/j36.glb
        'drop': [r'^Object_4$'],
        'comp': [
            # 前起落架两个轮子中间一个 12 个三角形的方块（比轮子还低 8 厘米）
            {'node': r'^Object_', 'sel': {'x': [6.0, 6.2], 'ay': [0, 0.02], 'zlomax': 2.65}, 'drop': True},
            # 弹舱里的导弹（主弹舱一枚 6 米多长的远程弹、两排中距弹，侧弹舱两层近距弹）：横截面都不到 0.6 米
            {'node': r'^Object_', 'sel': {'x': [-3.3, 3.8], 'ay': [0, 2.1], 'z': [4.25, 5.3], 'wmax': 0.6}, 'drop': True},
            # 主起落架外侧斜挂着的舱门（连下沿那条边）、前起落架两边竖着的舱门
            {'node': r'^Object_', 'sel': {'x': [-2.4, -0.8], 'ay': [3.2, 3.9], 'z': [3.9, 4.9]}, 'g': 'GDoorM', 'k': 'gdoor', 'split': 'y'},
            {'node': r'^Object_', 'sel': {'x': [4.2, 6.6], 'ay': [0.35, 0.5], 'zmax': 4.3}, 'g': 'GDoorN', 'k': 'gdoor', 'split': 'y'},
            # 起落架：机腹以下的支柱、轮子、螺栓（主起落架在 x −4～−2、|y| 2～3；前起落架 x 5.6～6.7）
            {'node': r'^Object_', 'sel': {'x': [-4.2, -1.7], 'ay': [1.95, 2.95], 'zlomax': 4.05}, 'gear': True},
            {'node': r'^Object_', 'sel': {'x': [5.6, 6.7], 'ay': [0, 0.3], 'zlomax': 4.12}, 'gear': True},
        ],
        # 主起落架往前收进 4 米长的轮舱，前起落架往后收
        'gear_mode': {'nx': 2.0, 'n': 'a', 'm': 'f', 'hi': 0.99},
        # 下面这些是网页版坐标（地面 z = 0，轮子最低点）：机翼在 2.5～2.9 米高、后缘一级一级往外前移；comp 的 sel 是原模型坐标（z 没减地面）
        'surf': [
            {'g': 'ElvI', 'k': 'elevon', 't': 'te', 'r': [3.7, 6.3], 'x': [-11.6, -8.0], 'w': [2.35, 3.4], 'c': 1.0},
            {'g': 'ElvM', 'k': 'elevon', 't': 'te', 'r': [6.5, 9.4], 'x': [-11.0, -7.0], 'w': [2.35, 3.2], 'c': 1.0},
            {'g': 'ElvO', 'k': 'elvy', 't': 'te', 'r': [9.6, 11.8], 'x': [-10.0, -6.0], 'w': [2.35, 3.2], 'c': 0.8},
            # 主弹舱两扇门（铰链在外侧）、两边侧弹舱各一扇
            {'g': 'BayML', 'k': 'bay', 't': 'bay', 'x': [-3.15, 4.08], 'y': [0.0, 1.18], 'zc': 1.70, 'hy': 1.17, 'A': 1.7},
            {'g': 'BayMR', 'k': 'bay', 't': 'bay', 'x': [-3.15, 4.08], 'y': [-1.18, 0.0], 'zc': 1.70, 'hy': -1.17, 'A': 1.7},
            {'g': 'BaySL', 'k': 'bayS', 't': 'bay', 'x': [-3.15, 1.75], 'y': [1.18, 2.05], 'zc': 1.70, 'hy': 2.05, 'A': 1.7},
            {'g': 'BaySR', 'k': 'bayS', 't': 'bay', 'x': [-3.15, 1.75], 'y': [-2.05, -1.18], 'zc': 1.70, 'hy': -2.05, 'A': 1.7},
            # 座舱盖：玻璃（PartTransparentZWrite 材质），后铰链
            {'g': 'Canopy', 'k': 'canopy', 't': 'can', 'mats': ['PartTransparentZWriteClone'], 'x': [5.2, 8.2], 'hx': 5.35, 'A': 0.8},
        ],
        'noz': [[-7.07, 1.61, 2.64, 0.42], [-7.07, 0.0, 2.64, 0.42]],
    },
}


# ---------------------------------------------------------------- 读 GLB

CT = {5120: 'i1', 5121: 'u1', 5122: 'i2', 5123: 'u2', 5125: 'u4', 5126: 'f4'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
WRAPI = {10497: 0, 33071: 1, 33648: 2}


def load_glb(path):
    b = open(path, 'rb').read()
    if b[:4] != b'glTF':
        raise ValueError(path + ' 不是 GLB')
    off, J, BIN = 12, None, b''
    while off < len(b):
        ln, ty = struct.unpack('<II', b[off:off + 8])
        ch = b[off + 8:off + 8 + ln]
        if ty == 0x4E4F534A:
            J = json.loads(ch)
        elif ty == 0x004E4942:
            BIN = ch
        off += 8 + ln
    return J, BIN


def accessor(J, BIN, i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    n = NC[a['type']]
    dt = np.dtype('<' + CT[a['componentType']])
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    st = bv.get('byteStride', 0) or n * dt.itemsize
    raw = np.frombuffer(BIN, dtype=np.uint8, count=st * (a['count'] - 1) + n * dt.itemsize, offset=off)
    out = np.lib.stride_tricks.as_strided(raw, shape=(a['count'], n * dt.itemsize), strides=(st, 1)).copy().view(dt).reshape(a['count'], n)
    if a.get('normalized'):
        out = out.astype(np.float64) / float(np.iinfo(dt).max)
    return out


def node_mat(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    M = np.eye(4)
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M[:3, :3] = R * np.array(n.get('scale', [1, 1, 1]))
    M[:3, 3] = n.get('translation', [0, 0, 0])
    return M


def gather(J, BIN):
    """所有网格三角形（世界坐标），按图元：{ path 节点路径（祖先名字用 / 连起来）, P, N, UV, T, mat }"""
    prims = []

    def walk(i, Mp, path):
        n = J['nodes'][i]
        M = Mp @ node_mat(n)
        nm = n.get('name', '')
        p = (path + '/' + nm) if path else nm
        if 'mesh' in n:
            Nm = np.linalg.inv(M[:3, :3]).T
            for pr in J['meshes'][n['mesh']]['primitives']:
                if pr.get('mode', 4) != 4:
                    continue
                P = accessor(J, BIN, pr['attributes']['POSITION']).astype(np.float64)
                W = (M[:3, :3] @ P.T).T + M[:3, 3]
                T = accessor(J, BIN, pr['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in pr else np.arange(len(P)).reshape(-1, 3)
                if 'NORMAL' in pr['attributes']:
                    Nn = (Nm @ accessor(J, BIN, pr['attributes']['NORMAL']).astype(np.float64).T).T
                    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-12)
                else:
                    Nn = np.zeros_like(W)
                    fn = np.cross(W[T[:, 1]] - W[T[:, 0]], W[T[:, 2]] - W[T[:, 0]])
                    for k in range(3):
                        np.add.at(Nn, T[:, k], fn)
                    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-12)
                UV = accessor(J, BIN, pr['attributes']['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in pr['attributes'] else np.zeros((len(P), 2))
                if np.linalg.det(M[:3, :3]) < 0:   # 镜像的节点：三角形绕向反过来
                    T = T[:, ::-1]
                prims.append({'path': p, 'P': W, 'N': Nn, 'UV': UV, 'T': T, 'mat': pr.get('material', -1)})
        for c in n.get('children', []):
            walk(c, M, p)
    sc = J['scenes'][J.get('scene', 0)]
    for r in sc['nodes']:
        walk(r, np.eye(4), '')
    return prims


def names_of(path):
    return [x for x in path.split('/') if x]


def match(path, pats):
    for nm in names_of(path):
        for p in pats:
            if re.search(p, nm):
                return p
    return None


# ---------------------------------------------------------------- 摆正、缩放：换到网页版坐标（x 前、y 左、z 上，米）

AX = {'+x': np.array([1.0, 0, 0]), '-x': np.array([-1.0, 0, 0]), '+y': np.array([0, 1.0, 0]), '-y': np.array([0, -1.0, 0]),
      '+z': np.array([0, 0, 1.0]), '-z': np.array([0, 0, -1.0])}


def frame(prims, S):
    """原模型坐标 → 网页版坐标的转动（行：前、左、上）和平移、缩放"""
    fwd, up = AX[S['fwd']], AX[S['up']]
    left = np.cross(up, fwd)
    Rm = np.array([fwd, left, up])   # 网页版 = Rm @ 原模型
    keep = [p for p in prims if not match(p['path'], S.get('drop', []))]
    allP = np.concatenate([p['P'] for p in keep]) @ Rm.T
    # 左右对称的节点摆正：左右两块中心的连线应该正好沿 y（左）
    pairs = []
    for lp, rp in S.get('level', []):
        L = [p for p in keep if any(re.search(lp, n) for n in names_of(p['path']))]
        Rr = [p for p in keep if any(re.search(rp, n) for n in names_of(p['path']))]
        if L and Rr:
            cl = np.concatenate([p['P'] for p in L]).mean(0) @ Rm.T
            cr = np.concatenate([p['P'] for p in Rr]).mean(0) @ Rm.T
            pairs.append((cl, cr))
    if pairs:
        lat = sum((cl - cr) for cl, cr in pairs)
        lat /= np.linalg.norm(lat)
        # 机身纵轴：原来的「前」去掉横向分量（俯仰另外按机轮摆）
        lon = np.array([1.0, 0, 0]) - lat * lat[0]
        lon /= np.linalg.norm(lon)
        upv = np.cross(lon, lat)
        Rl = np.array([lon, lat, upv])
        Rm = Rl @ Rm
        ang = math.degrees(math.atan2(lat[2], lat[1]))
        print('  摆正：侧倾 %.1f°、偏航 %.1f°、俯仰 %.1f°（按 %d 对左右对称的节点）' % (ang, math.degrees(math.atan2(lat[0], lat[1])), math.degrees(math.atan2(lon[2], lon[0])), len(pairs)))
        mids = [((Rl @ (cl)) + (Rl @ (cr))) / 2 for cl, cr in pairs]
        ymid = float(np.mean([m[1] for m in mids]))
    else:
        ymid = 0.0
    # 俯仰：有起落架的按前轮、主轮的最低点摆平（两个都着地）；SPEC 里给了 pitch（度）就再转这么多
    gp = [p for p in keep if match(p['path'], S.get('gear', []))]
    if gp and S.get('level_gear', True):
        G = np.concatenate([p['P'] for p in gp]) @ Rm.T
        x0, x1 = G[:, 0].min(), G[:, 0].max()
        front = G[G[:, 0] > x1 - 0.25 * (x1 - x0)]
        back = G[G[:, 0] < x0 + 0.6 * (x1 - x0)]
        fz, bz = front[:, 2].min(), back[:, 2].min()
        fx = front[np.argmin(front[:, 2]), 0]
        bx = back[np.argmin(back[:, 2]), 0]
        th = math.atan2(fz - bz, fx - bx)   # 前轮比主轮高 → 机头抬着：往下转 th
        c, s_ = math.cos(-th), math.sin(-th)
        Rp = np.array([[c, 0, -s_], [0, 1, 0], [s_, 0, c]])
        Rm = Rp @ Rm
        print('  俯仰按机轮摆平：转了 %.1f°' % math.degrees(-th))
    if S.get('pitch'):
        th = math.radians(S['pitch'])
        Rp = np.array([[math.cos(th), 0, -math.sin(th)], [0, 1, 0], [math.sin(th), 0, math.cos(th)]])
        Rm = Rp @ Rm
    allP = np.concatenate([p['P'] for p in keep]) @ Rm.T
    lo, hi = allP.min(0), allP.max(0)
    s = S['len'] / (hi[0] - lo[0])
    if not pairs:
        ymid = float((lo[1] + hi[1]) / 2)
    else:
        L = [p for p in keep]
        ymid = float((lo[1] + hi[1]) / 2) if S.get('ymid') == 'box' else ymid
    t = np.array([-(lo[0] + hi[0]) / 2, -ymid, 0.0])
    return Rm, t, s


def components(P, T):
    """三角形的连通块（按位置焊接顶点：导出时同一个位置常有几个顶点——贴图缝）"""
    key = np.round(P / 1e-4).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    TT = inv[T]
    par = np.arange(inv.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b, c in TT:
        ra, rb, rc = find(a), find(b), find(c)
        par[rb] = ra
        par[find(rc)] = find(ra)
    roots = np.array([find(i) for i in range(len(par))])
    return roots[TT[:, 0]]


def inbox(lo, hi, sel):
    """连通块的包围盒（网页版坐标，z 没减地面）在不在 sel 的范围里：x / ay（|y|）/ z 给 [下, 上]，zmax 最高点低于它"""
    c = (lo + hi) / 2
    if 'x' in sel and not (sel['x'][0] <= c[0] <= sel['x'][1]):
        return False
    if 'ay' in sel and not (sel['ay'][0] <= abs(c[1]) <= sel['ay'][1]):
        return False
    if 'z' in sel and not (sel['z'][0] <= c[2] <= sel['z'][1]):
        return False
    if 'zmax' in sel and not (hi[2] < sel['zmax']):
        return False
    if 'zlomax' in sel and not (lo[2] < sel['zlomax']):   # 最低点低于它（伸到机腹以下的起落架）
        return False
    if 'wmax' in sel and not (max(hi[1] - lo[1], hi[2] - lo[2]) < sel['wmax']):   # 横截面（左右、上下）都小于它：细长的导弹
        return False
    return True


def build(key, path):
    """读下载的 GLB，按 SPEC 做成网页版烘焙模型那样的 (meta, binb, credit)，外加节点部件的铰链表（网页版坐标）"""
    S = SPEC[key]
    J, BIN = load_glb(path)
    prims = gather(J, BIN)
    Rm, t, s = frame(prims, S)
    nodes = S.get('nodes', {})
    # 每个图元属于哪个部件：去掉的、起落架、节点活动部件、机体
    VB, IB, lod = [], [], []
    parts = [{'n': 'gear'}]   # pi 0：起落架（air_anim.GEAR 按连通块分前 / 左 / 右）
    pidx = {}
    surfspec = {}
    nv = 0
    groups = {}
    for p in prims:
        if match(p['path'], S.get('drop', [])):
            continue
        # 按连通块挑：一个节点里合在一起的翼面（鸭翼和机翼一个节点）、挂着的副油箱（和机身一个节点）
        rules = [r for r in S.get('comp', []) if any(re.search(r['node'], n) for n in names_of(p['path']))]
        if rules:
            P = (p['P'] @ Rm.T + t) * s
            N = p['N'] @ Rm.T
            lab = components(P, p['T'])
            rest = np.ones(len(p['T']), dtype=bool)
            for l in np.unique(lab):
                m = lab == l
                Q = P[p['T'][m].reshape(-1)]
                lo_, hi_ = Q.min(0), Q.max(0)
                for r in rules:
                    if not inbox(lo_, hi_, r['sel']):
                        continue
                    rest[m] = False
                    if r.get('drop'):
                        break
                    if r.get('gear'):   # 起落架（pi 0：air_anim.GEAR 按连通块分前 / 左 / 右）
                        groups.setdefault((p['mat'], 0), []).append((P, N, p['UV'], p['T'][m]))
                        break
                    g = r['g'] + (('L' if (lo_[1] + hi_[1]) / 2 >= 0 else 'R') if r.get('split') == 'y' else '')
                    if g not in pidx:
                        pidx[g] = len(parts)
                        parts.append({'n': g})
                        surfspec[g] = (r['g'], r['k'], r.get('extra', {}))
                    groups.setdefault((p['mat'], pidx[g]), []).append((P, N, p['UV'], p['T'][m]))
                    break
            if rest.any():
                hit_ = match(p['path'], list(nodes))
                pi_ = pidx.get(nodes[hit_][0], -1) if hit_ else (0 if match(p['path'], S.get('gear', [])) else -1)
                groups.setdefault((p['mat'], pi_), []).append((P, N, p['UV'], p['T'][rest]))
            continue
        hit = match(p['path'], list(nodes))
        if hit and (nodes[hit][2] if len(nodes[hit]) > 2 else {}).get('split') == 'y':   # 一个节点里左右两扇门：按三角形在中线哪边分开
            spec = nodes[hit]
            P = (p['P'] @ Rm.T + t) * s
            N = p['N'] @ Rm.T
            cy = P[p['T']].mean(axis=1)[:, 1]
            for side_, mask in (('L', cy >= 0), ('R', cy < 0)):
                if not mask.any():
                    continue
                g = spec[0] + side_
                if g not in pidx:
                    pidx[g] = len(parts)
                    parts.append({'n': g})
                    surfspec[g] = spec
                groups.setdefault((p['mat'], pidx[g]), []).append((P, N, p['UV'], p['T'][mask]))
            continue
        if hit:
            spec = nodes[hit]
            g = spec[0]
            if g not in pidx:
                pidx[g] = len(parts)
                parts.append({'n': g})
                surfspec[g] = spec
            pi = pidx[g]
        elif match(p['path'], S.get('gear', [])):
            pi = 0
        else:
            pi = -1
        P = (p['P'] @ Rm.T + t) * s
        N = p['N'] @ Rm.T
        groups.setdefault((p['mat'], pi), []).append((P, N, p['UV'], p['T']))
    allP = np.concatenate([P for gl in groups.values() for (P, _, _, _) in gl])
    gearP = [P for (mi, pi), gl in groups.items() if pi == 0 for (P, _, _, _) in gl]
    z0 = float(np.concatenate(gearP)[:, 2].min()) if gearP else float(allP[:, 2].min())
    for (mi, pi), gl in sorted(groups.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        s0 = len(IB) * 3 if False else sum(len(x) for x in IB)
        cnt = 0
        for P, N, UV, T in gl:
            P = P.copy()
            P[:, 2] -= z0
            VB.append(np.hstack([P, N, UV]).astype(np.float32))
            IB.append((T + nv).reshape(-1).astype(np.uint32))
            nv += len(P)
            cnt += T.size
        lod.append([max(mi, 0), pi, s0, cnt])
    VBa = np.concatenate(VB)
    IBa = np.concatenate(IB)
    # 材质、贴图
    imgs, blobs = [], []
    off = len(VBa.tobytes()) + len(IBa.tobytes())

    def tex_ref(t):
        if not t:
            return None
        tx = J['textures'][t['index']]
        src = tx.get('source')
        if src is None:
            return None
        sm = J.get('samplers', [{}])[tx['sampler']] if 'sampler' in tx else {}
        return [src, WRAPI.get(sm.get('wrapS', 10497), 0), WRAPI.get(sm.get('wrapT', 10497), 0)]
    for im in J.get('images', []):
        bv = J['bufferViews'][im['bufferView']]
        data = BIN[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        imgs.append({'o': off + sum(len(b) for b in blobs), 'n': len(data), 'm': im.get('mimeType', 'image/png')})
        blobs.append(data)
    mats = []
    for m in (J.get('materials') or [{}]):
        pbr = m.get('pbrMetallicRoughness', {})
        mm = {'n': re.sub(r'[^A-Za-z0-9_.-]', '_', m.get('name', 'm%d' % len(mats)))[:40], 'c': pbr.get('baseColorFactor', [1, 1, 1, 1]),
              'mr': [pbr.get('metallicFactor', 1.0), pbr.get('roughnessFactor', 1.0)]}
        t_ = tex_ref(pbr.get('baseColorTexture'))
        if t_:
            mm['t'] = t_
        t_ = tex_ref(pbr.get('metallicRoughnessTexture'))
        if t_:
            mm['mrt'] = t_
        if m.get('normalTexture'):
            t_ = tex_ref(m['normalTexture'])
            if t_:
                mm['nt'] = t_
                mm['ns'] = m['normalTexture'].get('scale', 1)
        am = m.get('alphaMode', 'OPAQUE')
        mm['am'] = {'OPAQUE': 0, 'MASK': 1, 'BLEND': 2}.get(am, 0)
        if am == 'MASK':
            mm['ac'] = m.get('alphaCutoff', 0.5)
        if m.get('doubleSided'):
            mm['ds'] = 1
        mats.append(mm)
    vb = VBa.tobytes()
    ib = IBa.tobytes()
    binb = vb + ib + b''.join(blobs)
    meta = {'st': 8, 'vb': [0, len(vb)], 'ib': [len(vb), len(ib)], 'it': 4, 'lod': [lod], 'parts': parts, 'mats': mats, 'imgs': imgs,
            'noz': S.get('noz', [])}
    # 节点活动部件的铰链（网页版坐标）
    surf = {}
    T3 = IBa.reshape(-1, 3)
    tri_pi = np.concatenate([np.full(cnt // 3, pi) for (mi, pi, s0, cnt) in lod])
    for g, spec in surfspec.items():
        sel = np.where(tri_pi == pidx[g])[0]
        Q = VBa[np.unique(T3[sel].reshape(-1)), 0:3].astype(np.float64)
        surf[g] = hinge(g, spec, Q)
    print('  %s：%d 个三角形、%d 种材质、%d 张贴图；全长 %.2f 米、翼展 %.2f 米、高 %.2f 米；节点活动部件 %s' % (
        key, len(T3), len(mats), len(imgs), np.ptp(allP[:, 0]), np.ptp(allP[:, 1]), float(allP[:, 2].max() - z0), ', '.join(sorted(surf))))
    return meta, binb, S['credit'], surf


def hinge(g, spec, Q):
    """按那一块的形状算铰链（网页版坐标）：后缘舵面在前缘；全动翼面在翼根弦长的 35%；座舱盖在后下角；减速板在前缘"""
    k = spec[1]
    extra = spec[2] if len(spec) > 2 else {}
    side = 0 if abs(Q[:, 1].mean()) < 0.15 else (1 if Q[:, 1].mean() < 0 else -1)   # y < 0 是右边
    if k == 'gdoor':   # 原模型里开着的起落架舱门：不转，起落架收到一半藏起来
        return {'k': 'gdoor', 's': 0, 'a': [0.0, 0.0, 0.0], 'b': [1.0, 0.0, 0.0], 'sg': 1}
    if k in ('rud', 'fin'):
        lo_, hi_ = Q[:, 2].min(), Q[:, 2].max()
        e0 = Q[Q[:, 2] < lo_ + 0.15 * (hi_ - lo_)]
        e1 = Q[Q[:, 2] > hi_ - 0.15 * (hi_ - lo_)]
    else:
        ay = np.abs(Q[:, 1])
        lo_, hi_ = ay.min(), ay.max()
        e0 = Q[ay < lo_ + 0.15 * (hi_ - lo_)]
        e1 = Q[ay > hi_ - 0.15 * (hi_ - lo_)]
    if k in ('ail', 'flap', 'flaperon', 'elevon', 'elev', 'rud'):
        a, b = e0[np.argmax(e0[:, 0])], e1[np.argmax(e1[:, 0])]
    elif k in ('stab', 'can', 'fin'):
        le, te = e0[:, 0].max(), e0[:, 0].min()
        xp = le - 0.35 * (le - te)
        a = np.array([xp, e0[:, 1].mean(), e0[:, 2].mean()])
        b = np.array([xp, e1[:, 1].mean(), e1[:, 2].mean()])
    elif k == 'canopy':
        xr = Q[:, 0].min()
        rear = Q[Q[:, 0] < xr + 0.25]
        zb = rear[:, 2].min()
        a, b = np.array([xr, 0.5, zb]), np.array([xr, -0.5, zb])
    elif k == 'gdh':   # 起落架舱门：铰链在外侧那条长边上（沿机身前后），往外下方翻开
        ay = np.abs(Q[:, 1])
        edge = Q[ay > ay.max() - 0.06]
        zc = float(edge[:, 2].mean())
        yc = float(edge[:, 1].mean())
        a, b = np.array([Q[:, 0].max(), yc, zc]), np.array([Q[:, 0].min(), yc, zc])
    elif k == 'abrk':
        xf = Q[:, 0].max()
        front = Q[Q[:, 0] > xf - 0.15]
        a, b = np.array([xf, 0.5, front[:, 2].mean()]), np.array([xf, -0.5, front[:, 2].mean()])
    else:
        raise ValueError('不认识的动法 ' + k)
    if np.linalg.norm(b - a) < 1e-3:
        raise ValueError('%s 的铰链两端重合' % g)
    if k in ('rud', 'fin'):
        probe, want = Q[np.argmin(Q[:, 0])], A.RIGHT
    elif k == 'canopy':
        probe, want = Q.mean(0), A.UP
    elif k == 'gdh':   # 门的中间往下、往外翻
        probe, want = Q.mean(0), A.DOWN + np.array([0, (1.0 if Q[:, 1].mean() >= 0 else -1.0) * 0.5, 0])
    elif k == 'abrk':   # 背上的往上掀、肚皮下的往下翻
        probe, want = Q.mean(0) - np.array([0.3, 0, 0]), (A.UP if Q[:, 2].mean() > 1.8 else A.DOWN)
    else:
        probe, want = Q[np.argmin(Q[:, 0])], A.DOWN
    e = {'k': k, 's': side, 'a': [round(float(x), 4) for x in a], 'b': [round(float(x), 4) for x in b], 'sg': A.probe_sign(np.asarray(a), np.asarray(b), probe, want)}
    e.update({k_: v for k_, v in extra.items() if k_ not in ('split',)})
    return e


# ---------------------------------------------------------------- 预览图（游戏里的坐标：X 右、Y 上、−Z 前，格）

def preview(out, info, img):
    from PIL import ImageDraw
    COL = [(230, 80, 60), (60, 160, 230), (240, 200, 40), (120, 200, 90), (200, 90, 220), (250, 140, 40), (40, 200, 190), (255, 120, 170),
           (120, 120, 255), (190, 230, 70)]
    tris, cols = [], []
    gi = {}
    for name, g, mi, P, N, UV, idx in out:
        c = info['parts'][name]['c']
        Q = P + np.array(c)
        base = (150, 150, 150) if g == 'Body' else COL[gi.setdefault(g, len(gi)) % len(COL)]
        tris.append(Q[idx.astype(np.int64)])
        cols += [base] * len(idx)
    T = np.concatenate(tris)
    cols = np.array(cols)
    lo, hi = T.reshape(-1, 3).min(0), T.reshape(-1, 3).max(0)
    ctr, R = (lo + hi) / 2, (hi - lo).max() / 2

    def view(Rm, title, W=600, H=460):
        P = (T - ctr) @ Rm.T
        im = Image.new('RGB', (W, H), (26, 30, 36))
        d = ImageDraw.Draw(im)
        sc = min(W, H) * 0.46 / R
        n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        sh = np.abs(n[:, 2]) * 0.6 + 0.4
        for k in np.argsort(P[:, :, 2].mean(1)):
            q = P[k]
            d.polygon([(W / 2 + q[j, 0] * sc, H / 2 - q[j, 1] * sc) for j in range(3)], fill=tuple(int(x * sh[k]) for x in cols[k]))
        for g, e in (info.get('surf') or {}).items():
            if 'a' in e and e.get('k') not in ('kf',):
                a, b = (np.array(e['a']) - ctr) @ Rm.T, (np.array(e['b']) - ctr) @ Rm.T
                d.line([(W / 2 + a[0] * sc, H / 2 - a[1] * sc), (W / 2 + b[0] * sc, H / 2 - b[1] * sc)], fill=(255, 40, 40), width=2)
        d.text((6, 6), title, fill=(255, 255, 255))
        return im
    Rx = lambda a: np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    Ry = lambda a: np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    ims = [view(Rx(math.pi / 2), 'top'), view(Ry(-math.pi / 2), 'side (right)'), view(Ry(math.pi), 'front'), view(Rx(-math.pi / 2), 'bottom'),
           view(Rx(0.5) @ Ry(-2.5), 'oblique'), view(Rx(-0.35) @ Ry(2.3), 'oblique low')]
    W = Image.new('RGB', (1200, 1380))
    for i, im in enumerate(ims):
        W.paste(im, ((i % 2) * 600, (i // 2) * 460))
    W.save(img)
    print('  预览：' + img)


# ---------------------------------------------------------------- 主程序：同 air_one.py（只写这一个模型）

def main(argv):
    key, glb, adj = argv[0], argv[1], argv[2]
    view = argv[argv.index('--view') + 1] if '--view' in argv else None
    dry = '--dry' in argv
    S = SPEC[key]
    AD = json.load(open(adj, encoding='utf-8'))
    meta, binb, cred, surf = build(key, glb)
    # 交给 air2glb：读模型换成这份、节点部件的铰链走 kf 表那条路、起落架和座舱按 air_anim 的表
    B.load = lambda k: (json.loads(json.dumps(meta)), binb, cred)
    KF.load = lambda k: {'surf': json.loads(json.dumps(surf))} if surf else None
    if S.get('gear_mode'):
        A.GEAR[key] = S['gear_mode']
    if S.get('surf'):
        A.SURF[key] = S['surf']
    if S.get('pit'):
        A.PIT[key] = S['pit']
    for i in S['ids']:
        X.ALIAS[i] = key
    if S.get('lift'):   # 没有放下的起落架：机腹最低点离地多高（米），游戏里用零件拼的起落架
        X.LIFT[key] = S['lift']
    meta2, binb2, info, out = X.convert(key, AD, S['ids'])
    if 'pit' not in info and 'Canopy' in (info.get('surf') or {}):   # 没量座舱：头在座舱盖最高处往下 0.3 米、盖子长度的四成处
        cp = [p for n, p in info['parts'].items() if p['g'] == 'Canopy']
        lo = np.min([np.array(p['c']) - np.array(p['s']) / 2 for p in cp], 0)
        hi = np.max([np.array(p['c']) + np.array(p['s']) / 2 for p in cp], 0)
        info['pit'] = [[0.0, round(float(hi[1] - 0.3 * B.S), 3), round(float(lo[2] + 0.42 * (hi[2] - lo[2])), 3)]]
    tris = sum(len(o[6]) for o in out)
    print('  %s：%d 个三角形、%d 块，长 %.1f 翼展 %.1f 高 %.1f 格；活动部件 %s' % (key, tris, len(out), info['len'], info['w'], info['h'],
                                                            ', '.join('%s(%s)' % (g, e.get('k')) for g, e in sorted((info.get('surf') or {}).items()))))
    if view:
        preview(out, info, view)
    if dry:
        return
    path = os.path.join('models/air', key + '.glb')
    kname = S.get('kname', key)   # 换过版本的：导入后的块叫 A_<kname>__…（和用户已经导入的老版本不重名），文件名不变
    B.write_glb(kname, meta2, binb2, info, out, path, prefix='A_')
    print('  写好了 %s（%.1f MB）' % (path, os.path.getsize(path) / 1e6))
    # 元数据：同 air_one.py
    META = 'src/ReplicatedStorage/ImportedAir.lua'
    src = open(META, encoding='utf-8').read()
    old = B.old_lines(META)
    m_alias = re.search(r'\n  alias = (\{.*?\}),\n  old = ', src, re.S)
    m_old = re.search(r'\n  old = (\{.*?\}),\n  m = \{\n', src, re.S)

    def parse_tbl(t):
        o = {}
        for k_, v in re.findall(r'([a-z0-9_]+) = ("[^"]*"|\{[^}]*\})', t):
            o[k_] = v.strip('"') if v.startswith('"') else re.findall(r'"([^"]*)"', v)
        return o
    alias = parse_tbl(m_alias.group(1))
    oldt = parse_tbl(m_old.group(1))
    for i in S['ids']:
        alias[i] = kname
        if kname != key and key in old:   # 老版本（原来的键名）那一行留着，old 表里记上：没导入新版本的照旧用老的
            oldt[i] = [key] + [k for k in (oldt.get(i) or []) if k not in (key, kname)]
    old[kname] = '    %s = %s,\n' % (kname, B.lua(info))
    body = '\n  alias = ' + B.lua(alias) + ',\n  old = ' + B.lua(oldt) + ',\n  m = {\n'
    for k_ in sorted(old):
        line = old[k_]
        body += line if line.endswith('\n') else line + '\n'
    body += '  },\n}\n'
    open(META, 'w', encoding='utf-8').write(src[:m_alias.start()] + body)
    # 署名
    cred_path = os.path.join('models/air', 'credits.txt')
    lines = open(cred_path, encoding='utf-8').read().split('\n') if os.path.exists(cred_path) else []
    entry = '- %s（%s.glb）：%s' % (S['credit'].split('：', 1)[0], key, S['credit'])
    tag = '（%s.glb）' % key
    for n, ln in enumerate(lines):
        if tag in ln:
            lines[n] = entry
            break
    else:
        while lines and lines[-1] == '':
            lines.pop()
        lines.append(entry)
        lines.append('')
    open(cred_path, 'w', encoding='utf-8').write('\n'.join(lines))
    print('  元数据、署名写好了')


if __name__ == '__main__':
    main(sys.argv[1:])
