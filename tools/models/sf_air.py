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
import sf_gear as SG   # noqa: E402  两套起落架网格、原模型喷口（推力矢量）

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
    # F-16C（rave.Ar4ik 的「F-16 Fighting Falcon | NATO | GameReady」，CC-BY；用户 11-23：「你再把 j8 和 f16 f15 f14 都做进去 你去找带内饰的然后给他们屏幕实现功能」）：
    #   机身一整块（Korpus_Low，舵面没分开，按切法切）、座舱盖单独一块（Kupol）、整套座舱（cockpit 材质：仪表板、平显、正前方控制板、两块多功能显示器、
    #   弹射座椅、侧杆、油门）；原模型机身材质整个设成了半透明混合（座舱盖的透明度在机身贴图的透明通道里）——机身改不透明，座舱盖克隆一份半透明的；
    #   飞行状态（起落架收着，零件拼）；翼下挂的 GBU-10、翼尖 AIM-120、两个副油箱去掉（游戏按选的挂载另画）
    #   座舱屏幕（原模型坐标，机头 +x、头顶 +y、+z 是右边）：两块多功能显示器在 x 7.50 的仪表板上（显示区在四根按键条里面，0.21 见方）、
    #   正前方控制板下面两个圆表（空速、高度）、中间姿态球、下面一个斜 45° 的航向仪；平显是 Cube.016 那一组（组合玻璃上画死了符号，座舱里换成会动的）
    'f16': {
        'ids': ['f16'],
        'kname': 'f16_v2',   # 11-24 雕了显示屏：导入后的块叫 A_f16_v2__…；没重导的照旧用老的 f16（屏幕贴在面上）
        'credit': credit('F-16C', 'F-16 Fighting Falcon | NATO | GameReady', 'rave.Ar4ik', '1d74c97a06384d318b1d09e0e3811055', 'f-16-fighting-falcon-nato-gameready')
                  + '（改动：转成 Roblox 坐标，去掉自带的外挂，襟副翼、全动平尾、方向舵、座舱盖切成会动的块；机身材质改不透明；座舱屏幕贴实时画面）',
        'fwd': '+x', 'up': '+y', 'len': 15.06, 'lift': 0.4, 'ymid': 'box',   # 机腹（进气道下）离地 0.85 米、全高约 5 米
        'drop': [r'^gbu-10', r'^aim-120', r'^Cylinder$', r'^Cylinder\.038$'],
        'pitmat': ['cockpit'], 'pithud': [r'^Cube\.016$'], 'pithud_box': [[7.0, 15.0, -0.62], [7.6, 15.6, -0.13]], 'glassnode': [r'^Kupol'],
        'matfix': {'Material.001': {'am': 0}, 'cockpit': {'am': 0}},
        'nodes': {r'^Kupol': ('Canopy', 'canopy', {'A': 0.6})},
        # 网页版坐标（地面 z = 0 是腹鳍最低点，没加 lift）：机翼后缘一条直线在 x −3.74、翼面高 1.33～1.47；全动平尾后缘 x −7.06、
        #   翼根前缘 −5.14、翼尖 |y| 2.8；垂尾从 z 2.5 起、后缘往上越来越靠后（−6.6 → −7.5）
        'surf': [
            {'g': 'Flp', 'k': 'flaperon', 't': 'te', 'r': [1.2, 3.9], 'x': [-3.9, -2.0], 'w': [1.25, 1.6], 'c': 0.62},
            {'g': 'Stab', 'k': 'stab', 't': 'box', 'r': [1.0, 2.9], 'x': [-7.2, -4.9], 'w': [1.2, 1.65], 'cut': True, 'px': -5.9, 'pz': 1.4},
            {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'mir': False, 'r': [2.6, 4.25], 'x': [-7.7, -5.8], 'w': [-0.15, 0.15], 'c': 0.5},
        ],
        'noz': [[-7.1, 0.0, 1.335, 0.34]],
        'eye_src': [5.70, 15.35, -0.37],
        'pitscr': {
            # 两块多功能显示器雕进机壳（用户 11-24：「我需要你在原模型上雕刻显示屏哈」）：原模型的机壳（Cube.011 / Cube.006，0.263 见方、0.028 厚；
            #   这个模型 1 单位 = 0.366 米）本来就是边框一圈、槽壁（|a|、|b| = 0.104）往里 0.0115、槽底是带雷达画面贴图的显示面——
            #   去掉槽底那块显示面，槽壁顺着往下再接 0.008（槽一共 7 毫米深）、补新槽底，屏幕放在槽底；槽口 0.207 见方（贴着原来的槽壁里面）
            'mfdL': {'c': [7.497, 14.535, -0.705], 'n': [-1, 0, 0], 'u': [0, 1, 0], 'w': 0.21, 'h': 0.21, 'page': 'f16l', 'carve': {'w': 0.207, 'h': 0.207, 'd': 0.008}},
            'mfdR': {'c': [7.497, 14.535, -0.025], 'n': [-1, 0, 0], 'u': [0, 1, 0], 'w': 0.21, 'h': 0.21, 'page': 'f16r', 'carve': {'w': 0.207, 'h': 0.207, 'd': 0.008}},
            'asi': {'c': [7.478, 14.394, -0.4534], 'n': [-1, 0, 0], 'u': [0, 1, 0], 'w': 0.13, 'h': 0.13, 'page': 'asi', 'round': 1},
            'alt': {'c': [7.478, 14.394, -0.2866], 'n': [-1, 0, 0], 'u': [0, 1, 0], 'w': 0.13, 'h': 0.13, 'page': 'alt', 'round': 1},
            'adi': {'c': [7.335, 14.175, -0.375], 'n': [-0.986, -0.168, 0], 'u': [-0.168, 0.986, 0], 'w': 0.19, 'h': 0.19, 'page': 'adi', 'round': 1},
            'hsi': {'c': [7.245, 14.02, -0.375], 'n': [-0.705, 0.709, 0], 'u': [0.709, 0.705, 0], 'w': 0.19, 'h': 0.19, 'page': 'hsi', 'round': 1},
            'hud': {'c': [7.29, 15.21, -0.3775], 'n': [-1, 0, 0], 'u': [0, 1, 0], 'w': 0.27, 'h': 0.44, 'page': 'hud'},
        },
    },
    # 歼-8II（Rhine_Lab_Muelsyse 的「Shenyang J-8II/B」，CC-BY；同一作者的歼-11 也是这么做的）：副翼、襟翼、全动平尾、方向舵、座舱盖、
    #   起落架舱门都是单独的节点；整架摆成带坡度、抬头的飞行姿态，起落架收在舱里（支柱、机轮去掉，游戏里用零件拼的放下来）；
    #   翼下的导弹和导轨（C_Ext*、3、4、1）、机腹中线挂架去掉
    'j8': {
        'ids': ['j8'],
        'credit': credit('歼-8II', 'Shenyang J-8II/B', 'Rhine_Lab_Muelsyse', '1c122a7cd4c44b1f85b916a1e059bfe4', 'shenyang-j-8iib')
                  + '（改动：转成 Roblox 坐标、摆正，去掉自带的导弹和收着的起落架，舵面、座舱盖、起落架舱门做成会动的块）',
        'fwd': '-z', 'up': '+y', 'len': 21.59, 'lift': 0.35, 'level_gear': False,   # 真机全高 5.41 米（模型 5.09 米：腹鳍放着）
        'level': [(r'^LeftAileron$', r'^RightAileron$'), (r'^LeftFlap$', r'^RightFlap$'), (r'^LeftStab$', r'^RightStab$')],
        'drop': [r'^C_Ext\d', r'^1$', r'^3$', r'^4$', r'^05$', r'^BL$', r'^Centerline_Pylon$', r'^Box18$', r'MainGearStrut$', r'MainGearTire$', r'^Nose_Gear$'],
        # 座舱盖的玻璃（和前风挡一个节点 glass）：按连通块挑后面那块大的跟着座舱盖框（hatch）一起掀
        'comp': [{'node': r'^glass$', 'sel': {'x': [4.5, 6.2], 'ay': [0, 0.3]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.8}}],
        'noz': [[-7.66, 0.46, 1.93, 0.38]],
        'nodes': {
            r'^LeftAileron$': ('AilL', 'ail'), r'^RightAileron$': ('AilR', 'ail'),
            r'^LeftFlap$': ('FlpL', 'flap'), r'^RightFlap$': ('FlpR', 'flap'),
            r'^LeftStab$': ('StabL', 'stab'), r'^RightStab$': ('StabR', 'stab'),
            r'^Rudder$': ('Rud', 'rud'),
            r'^hatch$': ('Canopy', 'canopy', {'A': 0.8}),
            r'^gear_l_hatch$': ('GDoorL', 'gdh', {'A': 1.45}), r'^gear_r_hatch$': ('GDoorR', 'gdh', {'A': 1.45}),
            r'^nose_gear_hatch_l$': ('GDoorNL', 'gdh', {'A': 1.4}), r'^nose_gear_hatch_r$': ('GDoorNR', 'gdh', {'A': 1.4}),
        },
    },
    # 歼-6（andertan 的「Shenyang J-6 "Farmer"」，CC-BY；同一作者的歼-10C 也是这么做的）——用户 11-25 看机库截图：「这个j6很奇怪」
    #   （原来科技树的歼-6 借歼-8II 的模型和性能，卡片上是通用的俯视飞机符号）。原模型按材质合成了几大块，舵面没分开、没有起落架（飞行状态）：
    #   Object_4 / 5 机翼 + 全动平尾（平尾、翼尖防颤振配重各自是单独的连通块）、翼刀、翼根炮管整流罩；Object_7 / 12 机身左右两半（12 带垂尾、背鳍）；
    #   Object_8～11 进气道和尾喷管里面；Object_13 座舱盖（中间那块能掀的、后面固定的、前风挡左右两块）；Object_15～17 座舱里面
    #   下面的切法是网页版坐标（地面 z = 0 是翼刀最低点，没加 lift）；comp 的 sel 是原模型坐标（z 没减地面：机身中线 z = 0）
    'j6': {
        'ids': ['j6'],
        'credit': credit('歼-6', 'Shenyang J-6 "Farmer"', 'andertan', '9c349a6f5df24b839508bc4045d09665', 'shenyang-j-6-farmer')
                  + '（改动：转成 Roblox 坐标，襟翼、副翼、全动平尾、方向舵、座舱盖切成会动的块）',
        'fwd': '+x', 'up': '+y', 'len': 12.54, 'lift': 0.9,   # 真机全长 12.54 米（不算空速管）、全高 3.89 米（模型 3.0 米）：机腹离地约 0.9 米
        'comp': [
            # 全动平尾：两边各一块（连同翼尖的防颤振配重），绕翼根弦长 35% 处转
            {'node': r'^Object_[45]$', 'sel': {'x': [-6.0, -2.0], 'ay': [0.3, 2.4], 'z': [0.0, 0.6]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            # 座舱盖：中间那块（前风挡、后面的固定玻璃不动）
            {'node': r'^Object_13$', 'sel': {'x': [2.6, 3.9]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.75}},
        ],
        # 后缘：翼刀（|y| 2.43～2.49）里面是襟翼、外面是副翼；垂尾后缘是方向舵
        'surf': [
            # 翼根后缘（|y| < 1.3）被全动平尾挡着（平尾在后面高一点）：襟翼从 1.3 起，窗口压在机翼的高度（z 0.25～0.75，平尾在 0.9 以上）
            {'g': 'Flp', 'k': 'flap', 't': 'te', 'r': [1.3, 2.36], 'x': [-2.1, -0.2], 'w': [0.25, 0.75], 'c': 0.62},
            {'g': 'Ail', 'k': 'ail', 't': 'te', 'r': [2.56, 4.15], 'x': [-3.6, -0.9], 'w': [0.1, 0.65], 'c': 0.48},
            {'g': 'Rud', 'k': 'rud', 't': 'te', 'sp': 'z', 'mir': False, 'r': [1.6, 2.92], 'x': [-6.45, -4.3], 'w': [-0.15, 0.15], 'c': 0.42},
        ],
        # 两台涡喷-6 并排（原模型尾部是一整圈喷管，按两个喷口算尾焰）
        'noz': [[-4.56, 0.15, 0.74, 0.15]],
    },
    # 苏-57（bohmerang 的「Sukhoi Su-57 Felon - Fighter Jet - Free」，CC BY-NC-SA：作者写明只许个人用、不许商用——用户 11-26 指定原封不动导入，
    #   已告诉用户这个授权）：机身一个网格（舵面、喷口调节片都是单独的连通块）、座舱盖（后半块能掀、前风挡不动）、座舱、平显；
    #   起落架两套：SU57-landingOn 放下的支柱、机轮、打开的主轮舱门（+ 着陆灯 landingOnLight），SU57-landingOff 收起后关好的三块门板——
    #   照真机做收放（sf_gear.py）：主起落架、前起落架都往前收进机轮前面的舱里（舱的位置按 landingOff 的门板量的）；
    #   前起落架往后斜拉的那根撑杆收的时候会从机腹戳出去（真机是折起来的）：单独成 GearB，起落架一动就藏起来
    #   推力矢量：两台 AL-41F1 的喷口全向偏转（±15°），每个喷口 16 片调节片 + 16 片密封片 + 里层，按方位分 16 组开合
    #   下面的范围都是网页版坐标、离地高度（selg：z 减了地面），量法见 tools/models/sf_gear.py
    'su57': {
        'ids': ['su57'],
        'credit': '苏-57：Sukhoi Su-57 Felon - Fighter Jet - Free，作者 bohmerang（https://sketchfab.com/3d-models/sukhoi-su-57-felon-fighter-jet-free-59995d6f34ba4bb7990195be3a745fc5），'
                  'CC BY-NC-SA 4.0（署名—非商业—相同方式共享；作者注明只许个人使用、不许用于商业作品）。'
                  '（改动：转成 Roblox 坐标、按机轮摆平，舵面、座舱盖、起落架、舱门、喷口调节片拆成会动的块）',
        'fwd': '+x', 'up': '+y', 'scale': 0.1026, 'selg': True,   # 全长 20.1 米
        'gear': [r'^SU57-landingOn_6$'],   # frame() 按放下的机轮摆平俯仰
        'gearon': [r'^SU57-landingOn_6$', r'^SU57-landingOnLight_7$'], 'gearoff': [r'^SU57-landingOff_5$'],
        'pitnode': [r'^SU57-cockpit_2$'], 'pithud': [r'^SU57-hud_3$'],
        'pit': [[5.55, 0.0, 3.12]],
        'legs': [
            # 前起落架：双轮，支柱顶的横梁在 x 3.6、离地 2.03；往前收，机轮收到舱前段（舱从 x 2.5 到 5.6）
            {'g': 'GearN', 'sel': {'x': [3.0, 4.25], 'ay': [0, 0.45], 'z': [0, 2.4]}, 'p': [3.6, 0.0, 2.03], 'to': [5.25, 0.0, 2.33], 'steer': True},
            # 主起落架（左，右边照镜像）：单轮在支柱外侧；支柱顶的耳轴 x −2.78、离地 2.42；往前收进机轮前面 2.9 米长的舱（门板 x −3.09～−0.23、|y| 1.73～2.64），
            #   舱只有 0.9 米宽：机轮竖着收（不转 90°），收的时候往里靠一点
            {'g': 'GearL', 'mir': True, 'sel': {'x': [-3.35, -1.9], 'y': [1.6, 2.85], 'z': [0, 2.6]}, 'p': [-2.78, 2.19, 2.42], 'to': [-0.9, 2.02, 2.55]},
        ],
        'brace': [{'g': 'GearB', 'sel': {'x': [2.3, 3.37], 'ay': [0, 0.2], 'z': [1.3, 2.0]}}],
        'doors': [
            # 主轮舱门：打开的门（外侧铰链、往下垂着，带内侧的加强筋）配 landingOff 里关好的门板
            {'g': 'GDoorM', 'mir': True, 'sel': {'x': [-3.2, -0.1], 'y': [2.4, 3.15], 'z': [1.1, 2.3]}, 'off': {'x': [-3.2, -0.1], 'y': [1.6, 2.8], 'z': [1.4, 2.4]}},
        ],
        # 前轮舱前段的两扇门（x 4.0～5.6）：放下起落架的那套网格里是关着的（同真机：放完前门又关上，只留支柱那一截敞着）——
        #   照真机的顺序：前门往下翻开 → 前起落架放下 / 收起 → 前门再关上（门边的铰链座留在舱边上）
        'odoors': [{'g': 'GDoorN', 'sel': {'x': [3.9, 5.7], 'ay': [0, 0.32], 'z': [1.5, 1.75]}, 'A': 88}],
        'nozzles': [{'g': 'Noz', 'node': r'^SU57-airframe', 'x': [-8.85, -7.55], 'c': [1.475, 2.64], 'r': 0.68, 'tv': '3d', 'A': 15, 'n': 16, 'pa': 10, 'r0': 0.3}],
        'nodes': {},
        'comp': [
            # 后座舱盖（前风挡不动）：后铰链往上掀
            {'node': r'^SU57-canopy_1$', 'sel': {'x': [5.3, 5.9]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.75}},
            # LEVCON（翼根前面那块可动边条）
            {'node': r'^SU57-airframe', 'sel': {'x': [2.5, 3.3], 'ay': [1.5, 2.3], 'z': [2.2, 2.5]}, 'g': 'Lev', 'k': 'lev', 'split': 'y'},
            # 前缘襟翼
            {'node': r'^SU57-airframe', 'sel': {'x': [-3.0, -1.0], 'ay': [4.0, 6.0], 'z': [2.2, 2.6]}, 'g': 'Slat', 'k': 'slat', 'split': 'y'},
            # 襟副翼（内段）连它后面那截作动筒整流罩
            {'node': r'^SU57-airframe', 'sel': {'x': [-6.1, -5.5], 'ay': [3.9, 4.5], 'z': [2.5, 2.62]}, 'g': 'Flp', 'k': 'flaperon', 'split': 'y'},
            {'node': r'^SU57-airframe', 'sel': {'x': [-6.1, -5.75], 'ay': [3.8, 4.05], 'z': [2.4, 2.52]}, 'g': 'Flp', 'k': 'flaperon', 'split': 'y'},
            # 副翼（外段）连后截整流罩、后缘上的放电刷
            {'node': r'^SU57-airframe', 'sel': {'x': [-5.9, -5.4], 'ay': [5.6, 6.1], 'z': [2.5, 2.65]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            {'node': r'^SU57-airframe', 'sel': {'x': [-5.8, -5.4], 'ay': [5.35, 5.55], 'z': [2.45, 2.57]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            {'node': r'^SU57-airframe', 'sel': {'x': [-6.2, -5.8], 'ay': [5.9, 6.6], 'z': [2.55, 2.63]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            # 全动平尾连翼尖的放电刷
            {'node': r'^SU57-airframe', 'sel': {'x': [-7.6, -7.0], 'ay': [3.4, 3.9], 'z': [2.45, 2.65]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            {'node': r'^SU57-airframe', 'sel': {'x': [-8.95, -8.6], 'ay': [4.6, 4.95], 'z': [2.5, 2.65]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            # 全动垂尾（外倾）连尖上的航行灯、天线
            {'node': r'^SU57-airframe', 'sel': {'x': [-6.2, -5.3], 'ay': [2.6, 3.2], 'z': [3.5, 4.0]}, 'g': 'Fin', 'k': 'fin', 'split': 'y'},
            {'node': r'^SU57-airframe', 'sel': {'x': [-7.45, -6.8], 'ay': [3.1, 3.3], 'z': [4.2, 4.45]}, 'g': 'Fin', 'k': 'fin', 'split': 'y'},
        ],
        'noz': [[-8.70, 1.475, 2.64, 0.47]],
    },
    # 米格-29（9.12，bohmerang 的「MiG-29 - Fighter Jet - Free」，CC BY-NC-SA：作者写明只许个人用、不许商用——用户 11-26 指定原封不动导入）：
    #   机身一个网格（全动平尾、方向舵、襟翼、副翼、机腹减速板是单独的连通块；前缘机动襟翼和喷口没分开）、座舱盖（后半块能掀）、座舱、平显、
    #   内侧 / 中间两对发射导轨（rails 节点，外侧挂架在机身网格里）——导弹直接挂在模型自己的导轨下面（AirDefs 挂点的 own），不另画挂架；
    #   起落架两套（同苏-57）：前起落架往后收（真机：米格设计局的前起落架往后收，前面那根撑杆收的时候折起来——单独成 GearB）、
    #   主起落架往前、绕斜轴收，机轮边收边转 90° 躺平（真机如此）；放下时主轮舱前段的门斜挂着、前轮舱两侧的门垂着，和 landingOff 关好的门板配对
    'mig29': {
        'ids': ['mig29'],
        'credit': '米格-29：MiG-29 - Fighter Jet - Free，作者 bohmerang（https://sketchfab.com/3d-models/mig-29-fighter-jet-free-0a21787096244220b246ec8747e7b09c），'
                  'CC BY-NC-SA 4.0（署名—非商业—相同方式共享；作者注明只许个人使用、不许用于商业作品）。'
                  '（改动：转成 Roblox 坐标、按机轮摆平，舵面、座舱盖、起落架、舱门拆成会动的块）',
        'fwd': '+x', 'up': '+y', 'len': 17.32, 'selg': True,   # 全长 17.32 米（含空速管）
        'gear': [r'^MiG-29-landingOn_6$'],
        'gearon': [r'^MiG-29-landingOn_6$', r'^MiG-29-landingOnLight_7$'], 'gearoff': [r'^MiG-29-landingOff_5$'],
        'pitnode': [r'^MiG-29-cockpit_2$'], 'pithud': [r'^MiG-29-hud_3$'],
        'pit': [[3.55, 0.0, 2.95]],
        'legs': [
            {'g': 'GearN', 'sel': {'x': [1.1, 1.86], 'ay': [0, 0.3], 'z': [0, 2.2]}, 'p': [1.72, 0.0, 1.98], 'to': [0.1, 0.0, 2.35], 'steer': True},
            {'g': 'GearL', 'mir': True, 'sel': {'x': [-2.9, -1.7], 'y': [1.0, 1.85], 'z': [0, 2.1]}, 'p': [-2.42, 1.28, 1.95], 'to': [-0.9, 1.3, 2.02], 'tw': 90},
        ],
        'brace': [{'g': 'GearB', 'sel': {'x': [1.86, 3.0], 'ay': [0, 0.25], 'z': [0.9, 2.1]}}],
        'doors': [
            {'g': 'GDoorM', 'mir': True, 'sel': {'x': [-1.45, -0.75], 'y': [0.95, 1.35], 'z': [1.0, 1.4]},
             'off': {'x': [-2.2, 0.0], 'y': [1.0, 1.8], 'z': [1.4, 2.0]}, 'crop': {'x': [-1.85, -0.4]}},
            {'g': 'GDoorN', 'mir': True, 'sel': {'x': [0.8, 1.2], 'y': [0.2, 0.4], 'z': [1.4, 1.75]},
             'off': {'x': [1.3, 1.8], 'ay': [0, 0.1], 'z': [1.5, 1.9]}, 'crop': {'x': [0.19, 1.8], 'y': [0.0, 0.3]}},
        ],
        'nodes': {},
        'comp': [
            {'node': r'^MiG-29-canopy_1$', 'sel': {'x': [2.3, 3.7]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.8}},
            {'node': r'^MiG-29-airframe', 'sel': {'x': [-7.2, -6.6], 'ay': [2.5, 3.1], 'z': [1.5, 1.8]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            {'node': r'^MiG-29-airframe', 'sel': {'x': [-7.1, -6.7], 'ay': [1.7, 1.9], 'z': [2.7, 3.05]}, 'g': 'Rud', 'k': 'rud', 'split': 'y'},
            {'node': r'^MiG-29-airframe', 'sel': {'x': [-4.3, -3.8], 'ay': [2.4, 2.9], 'z': [1.8, 1.95]}, 'g': 'Flp', 'k': 'flap', 'split': 'y'},
            {'node': r'^MiG-29-airframe', 'sel': {'x': [-4.6, -4.2], 'ay': [3.9, 4.4], 'z': [1.75, 1.85]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            {'node': r'^MiG-29-airframe', 'sel': {'x': [-6.2, -5.6], 'ay': [0, 0.1], 'z': [1.6, 1.8]}, 'g': 'Brake', 'k': 'abrk', 'extra': {'A': 0.9}},
        ],
        'noz': [[-7.05, 0.94, 1.40, 0.40]],
    },
    # 苏-35S（bohmerang 的「Sukhoi Su-35 - Fighter Jet - Free」，CC BY-NC-SA：作者写明只许个人用、不许商用——用户 11-26 给的，原封不动导入；
    #   原来科技树的苏-35S 借歼-11 的模型，机身上是中国的机徽）：机身一个网格（全动平尾、方向舵、襟副翼、两个喷口的外筒 + 各 16 片调节片是单独的连通块；
    #   前缘襟翼没分开；苏-27 一族后缘只有襟副翼、没有单独的副翼，滚转靠襟副翼 + 平尾差动）；座舱盖（风挡不动，后面两段一起往上掀）；
    #   起落架两套（同苏-57）：前起落架往前收（后面那根撑杆收的时候折起来——GearB），主起落架往前收、机轮边收边转 90° 躺平（苏-27 一族如此）；
    #   主轮舱放下时前后两扇门斜挂着，和 landingOff 那一整块关好的门板（3.8 米长）各配一半；
    #   推力矢量：两台 117S 的喷口各在外倾 32° 的斜面里偏 ±15°（一起偏管俯仰，反着偏管滚转和偏航）
    'su35': {
        'ids': ['su35'],
        'credit': '苏-35S：Sukhoi Su-35 - Fighter Jet - Free，作者 bohmerang（https://sketchfab.com/3d-models/sukhoi-su-35-fighter-jet-free-3213a404e5cb4fb68f778b9acae5109c），'
                  'CC BY-NC-SA 4.0（署名—非商业—相同方式共享；作者注明只许个人使用、不许用于商业作品）。'
                  '（改动：转成 Roblox 坐标、按机轮摆平，舵面、座舱盖、起落架、舱门、喷口调节片拆成会动的块）',
        'fwd': '+x', 'up': '+y', 'len': 21.9, 'selg': True,   # 全长 21.9 米
        'gear': [r'^SU-35-landingOn_6$'],
        'gearon': [r'^SU-35-landingOn_6$', r'^SU-35-landingOnLight_7$'], 'gearoff': [r'^SU-35-landingOff_5$'],
        'pitnode': [r'^SU-35-cockpit_2$'], 'pithud': [r'^SU-35-hud_3$'],
        'pit': [[5.75, 0.0, 3.35]],
        'legs': [
            {'g': 'GearN', 'sel': {'x': [2.4, 3.4], 'ay': [0, 0.3], 'z': [0, 2.3]}, 'p': [3.12, 0.0, 2.08], 'to': [4.95, 0.0, 2.42], 'steer': True},
            {'g': 'GearL', 'mir': True, 'sel': {'x': [-3.45, -2.4], 'y': [1.65, 2.4], 'z': [0, 2.32]}, 'p': [-3.0, 1.81, 2.5], 'to': [-1.0, 1.88, 2.55], 'tw': 90},
        ],
        'brace': [{'g': 'GearB', 'sel': {'x': [1.85, 2.62], 'ay': [0, 0.12], 'z': [1.4, 2.3]}}],
        'doors': [
            {'g': 'GDoorF', 'mir': True, 'sel': {'x': [-1.0, -0.5], 'y': [2.5, 2.9], 'z': [2.2, 2.6]},
             'off': {'x': [-2.2, -1.8], 'y': [1.7, 2.1], 'z': [2.3, 2.6]}, 'crop': {'x': [-1.6, -0.05]}},
            {'g': 'GDoorA', 'mir': True, 'sel': {'x': [-2.9, -2.5], 'y': [1.95, 2.3], 'z': [2.33, 2.6]},
             'off': {'x': [-2.2, -1.8], 'y': [1.7, 2.1], 'z': [2.3, 2.6]}, 'crop': {'x': [-3.9, -1.5]}},
        ],
        'nozzles': [{'g': 'Noz', 'node': r'^SU-35-airframe', 'x': [-9.1, -7.45], 'c': [1.19, 2.72], 'r': 0.75, 'tv': ('pl', 32), 'A': 15, 'n': 16, 'pa': 10, 'r0': 0.3}],
        'nodes': {},
        'comp': [
            {'node': r'^SU-35canopy_1$', 'sel': {'x': [4.5, 6.3]}, 'g': 'Canopy', 'k': 'canopy', 'extra': {'A': 0.75}},
            {'node': r'^SU-35-airframe', 'sel': {'x': [-7.7, -7.0], 'ay': [3.1, 3.6], 'z': [2.6, 3.0]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            {'node': r'^SU-35-airframe', 'sel': {'x': [-7.0, -6.6], 'ay': [2.0, 2.25], 'z': [4.0, 4.5]}, 'g': 'Rud', 'k': 'rud', 'split': 'y'},
            {'node': r'^SU-35-airframe', 'sel': {'x': [-4.9, -4.4], 'ay': [3.5, 4.0], 'z': [2.85, 3.05]}, 'g': 'Flp', 'k': 'flaperon', 'split': 'y'},
        ],
        'noz': [[-9.0, 1.19, 2.72, 0.5]],
    },
    # 苏-25（Immersive3A 的「[PBR] Sukhoi Su-25」，CC-BY；用户 11-26「这个也做进来 都别减面哈」）：机身一个网格（起落架放着、和机身连在一个网格里；
    #   舵面都是单独的连通块：内外两段前缘缝翼、内外两段襟翼、副翼、升降舵、上下两段方向舵、翼尖吊舱后面上下两瓣开花减速板）、座舱玻璃；
    #   翼下每边 5 个挂架是模型自己的（导弹、火箭巢、炸弹直接挂在挂架下面，AirDefs 挂点的 own）；
    #   起落架只有放下的样子：按连通块挑出每条腿（comp 的 leg），照真机收——前起落架往前收；主起落架往前收进发动机短舱下面、机轮转 90° 躺平
    'su25': {
        'ids': ['su25'],
        'credit': credit('苏-25', '[PBR] Sukhoi Su-25', 'Immersive3A', '956d0cb0bbe54fa8ad72e8c3e224fd2d', 'pbr-sukhoi-su-25')
                  + '（改动：转成 Roblox 坐标，舵面、减速板、起落架拆成会动的块）',
        'fwd': '-z', 'up': '+y', 'len': 15.53, 'ground': True, 'selg': True,   # 全长 15.53 米
        'pit': [[3.75, 0.0, 2.62]],
        'legs': [
            {'g': 'GearN', 'p': [3.1, 0.0, 1.75], 'to': [4.45, 0.0, 1.95], 'steer': True, 'keep': True},
            {'g': 'GearL', 'mir': True, 'p': [-0.2, 1.0, 1.42], 'to': [0.72, 1.0, 1.58], 'tw': 90, 'keep': True},
        ],
        'nodes': {},
        'comp': [
            # 起落架（和机身一个网格）：前起落架（连侧面挂着的门）、主起落架（连支柱内侧挂着的门）
            {'node': r'^fuselage', 'sel': {'x': [2.55, 3.6], 'ay': [0, 0.35], 'z': [0, 1.75]}, 'leg': 'GearN'},
            {'node': r'^fuselage', 'sel': {'x': [-1.0, 0.5], 'ay': [0.3, 1.45], 'z': [0, 1.0]}, 'leg': 'Gear', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-2.3, -1.8], 'ay': [5.2, 5.7], 'z': [1.85, 2.05]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-2.2, -1.8], 'ay': [3.4, 3.8], 'z': [1.95, 2.1]}, 'g': 'FlpO', 'k': 'flap', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-2.2, -1.75], 'ay': [1.9, 2.25], 'z': [2.0, 2.15]}, 'g': 'FlpI', 'k': 'flap', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-0.9, -0.5], 'ay': [5.1, 5.5], 'z': [1.95, 2.1]}, 'g': 'SlatO', 'k': 'slat', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-0.1, 0.3], 'ay': [2.4, 2.8], 'z': [2.1, 2.25]}, 'g': 'SlatI', 'k': 'slat', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-6.4, -6.1], 'ay': [1.1, 1.5], 'z': [2.0, 2.15]}, 'g': 'Elev', 'k': 'elev', 'split': 'y'},
            {'node': r'^fuselage', 'sel': {'x': [-6.1, -5.85], 'ay': [0, 0.05], 'z': [2.8, 3.1]}, 'g': 'Rud', 'k': 'rud'},
            {'node': r'^fuselage', 'sel': {'x': [-6.1, -5.85], 'ay': [0, 0.05], 'z': [3.5, 3.7]}, 'g': 'Rud', 'k': 'rud'},
            # 翼尖吊舱后面的开花减速板：上瓣往上、下瓣往下（前沿铰链）
            {'node': r'^fuselage', 'sel': {'x': [-2.6, -2.3], 'ay': [6.9, 7.15], 'z': [1.83, 1.95]}, 'g': 'BrkU', 'k': 'abrk', 'split': 'y', 'extra': {'A': 1.0}},
            {'node': r'^fuselage', 'sel': {'x': [-2.6, -2.3], 'ay': [6.9, 7.15], 'z': [1.7, 1.82]}, 'g': 'BrkD', 'k': 'abrk', 'split': 'y', 'extra': {'A': 1.0}},
        ],
        'noz': [[-3.85, 0.76, 1.30, 0.28]],
    },
    # 苏-30SM（Immersive3A 的「[PBR] Sukhoi Su-30」，CC-BY；同一作者的苏-25 也是这么做的——11-27 换掉借的歼-16 模型：用户问过「为什么俄罗斯的飞机上会有中国的图标」）：
    #   机身一个网格（起落架放着、和机身连在一起；鸭翼、前缘襟翼、襟副翼、外段副翼、全动平尾、方向舵、喷口都是单独的连通块）、座舱玻璃（前后两段 + 风挡，各两层）；
    #   贴图上没有国徽；翼下的挂架、翼尖导轨、进气道下和机腹的挂架是模型自己的（AirDefs 挂点的 own）。
    #   起落架照真机收（sf_gear.py）：前起落架往前收（前面那根斜撑杆收的时候真机是折起来的——GearB，一动就藏）；
    #   主起落架往前收进翼根下面、机轮转 90° 躺平（苏-27 一族如此）；主轮舱外侧那扇挂着的门（sdoor）收好以后关上
    #   下面的范围都是网页版坐标（x 前、y 左、z 上，米）、离地高度（selg：z 从机轮最低点量）
    'su30': {
        'ids': ['su30sm'],
        'credit': credit('苏-30SM', '[PBR] Sukhoi Su-30', 'Immersive3A', '421bd56fd97c4c7196904e778f27aef7', 'pbr-sukhoi-su-30')
                  + '（改动：转成 Roblox 坐标，鸭翼、舵面、起落架、舱门拆成会动的块）',
        'fwd': '-z', 'up': '+y', 'len': 21.935, 'ground': True, 'selg': True,   # 全长 21.935 米（含空速管）
        'pit': [[5.15, 0.0, 3.62], [3.75, 0.0, 3.70]],   # 前座、后座（座舱盖顶 3.97 / 4.03 米往下 0.35）
        'legs': [
            # 前起落架：双轮；支柱顶的横梁在 x 2.66、离地 2.29；往前收进座舱下面的舱
            {'g': 'GearN', 'p': [2.66, 0.0, 2.29], 'to': [4.55, 0.0, 2.38], 'steer': True},
            # 主起落架（左，右边照镜像）：单轮在支柱外侧；支柱顶 x −3.33、离地 2.39；往前收、机轮转 90° 躺平
            {'g': 'GearL', 'mir': True, 'p': [-3.33, 1.81, 2.39], 'to': [-1.45, 1.95, 2.3], 'tw': 90},
        ],
        'nodes': {},
        'comp': [
            # 前起落架往前斜拉的撑杆（收的时候真机折起来）：起落架一动就藏
            {'node': r'^Object_4$', 'sel': {'x': [1.5, 2.3], 'ay': [0, 0.1], 'z': [1.3, 2.0]}, 'grp': 'GearB'},
            {'node': r'^Object_4$', 'sel': {'x': [2.35, 3.4], 'ay': [0, 0.36], 'z': [0, 2.45]}, 'leg': 'GearN'},
            # 主起落架：支柱、机轮、扭力臂、作动筒（不含外侧的门、进气道下的挂架）
            {'node': r'^Object_4$', 'sel': {'x': [-4.45, -2.9], 'ay': [1.45, 2.4], 'z': [0, 2.45]}, 'leg': 'Gear', 'split': 'y'},
            # 主轮舱外侧挂着的门（外缘铰链，往下垂）：收好以后关上
            {'node': r'^Object_4$', 'sel': {'x': [-1.4, -0.9], 'ay': [2.3, 2.7], 'z': [1.7, 2.1]}, 'sdoor': 'GDoorM', 'split': 'y'},
            # 舵面
            {'node': r'^Object_4$', 'sel': {'x': [0.9, 1.6], 'ay': [2.4, 2.9], 'z': [2.3, 2.5]}, 'g': 'Can', 'k': 'can', 'split': 'y'},
            {'node': r'^Object_4$', 'sel': {'x': [-1.7, -1.1], 'ay': [3.3, 3.9], 'z': [2.4, 2.6]}, 'g': 'Slat', 'k': 'slat', 'split': 'y'},
            {'node': r'^Object_4$', 'sel': {'x': [-5.7, -4.8], 'ay': [3.6, 4.0], 'z': [2.4, 2.55]}, 'g': 'Flp', 'k': 'flaperon', 'split': 'y'},
            {'node': r'^Object_4$', 'sel': {'x': [-6.3, -5.8], 'ay': [6.0, 6.5], 'z': [2.45, 2.6]}, 'g': 'Ail', 'k': 'ail', 'split': 'y'},
            {'node': r'^Object_4$', 'sel': {'x': [-8.1, -7.6], 'ay': [3.2, 3.6], 'z': [1.85, 2.0]}, 'g': 'Stab', 'k': 'stab', 'split': 'y'},
            {'node': r'^Object_4$', 'sel': {'x': [-7.5, -7.0], 'ay': [2.1, 2.25], 'z': [3.4, 3.9]}, 'g': 'Rud', 'k': 'rud', 'split': 'y'},
        ],
        'noz': [[-9.43, 1.13, 2.0, 0.52]],
    },
    'f15': {
        'ids': ['f15'],
        'credit': 'F-15C：F-15A Eagle — USAF 76-0020, Duxford，作者 mgg8（https://sketchfab.com/3d-models/f-15a-eagle-usaf-76-0020-duxford-524f9394057e46ec8424d4a356f794b7），CC0 公共领域（不用署名，照样写上出处）',
        'fwd': '+z', 'up': '+y', 'len': 19.43,
        # 杜克斯福德博物馆的展机：起落架放着（做成收放时藏起来的 Gear）、机腹挂着副油箱（去掉）
        'comp': [{'node': '.', 'sel': {'x': [2.8, 3.9], 'ay': [0, 0.3], 'z': [0.0, 1.4]}, 'gear': True},
                 {'node': '.', 'sel': {'x': [-2.8, -1.4], 'ay': [1.3, 1.9], 'z': [0.0, 1.45]}, 'gear': True},
                 {'node': '.', 'sel': {'x': [-1.2, -0.6], 'ay': [0, 0.3], 'z': [0.5, 1.2]}, 'drop': True},
                 {'node': '.', 'sel': {'x': [-3.2, -2.2], 'ay': [2.7, 3.3], 'z': [1.2, 2.15]}, 'drop': True}],   # 翼下副油箱
    },
    'f14': {
        'ids': ['f14'],
        'credit': credit('F-14A', 'F-14A Tomcat', 'Novia556', '8df51512f1af4415bd547e5ed5936ea2', 'f-14a-tomcat'),
        'fwd': '+z', 'up': '+y', 'len': 19.1, 'drop': [r'^Object_2$'],
        'lift': 0.9,   # 飞行状态的模型（没放起落架）：腹鳍下沿离地 0.9 米，游戏里用零件拼的起落架
        'comp': [{'node': '.', 'sel': {'x': [-1.6, -0.5], 'ay': [1.2, 1.6], 'z': [1.9, 2.2]}, 'drop': True}],   # 进气道下的两个副油箱
    },
    # ———— 直升机（用户 11-25「直升机也做一下各个国家的」）：旋翼、尾桨做成会转的部件（nodes / comp 的动法 rotor / trotor，
    #   转轴按桨叶面的法线、支点按桨叶的重心自动算，见 rotor_part）；scale 按真机旋翼直径或机身长量的（桨叶伸出机身，不能按全长）；
    #   模型自带的外挂（火箭巢、导弹）去掉，游戏按选的挂载另画；机头炮塔 gunsplit 拆出来跟着瞄准转（同 air2glb.GUNSPLIT）
    #   没收的（不是作者本人做的）：42manako 的卡-52（《武装突袭》的贴图命名）、UH-1Y（贴图是扒游戏工具 Ninja Ripper 的命名）、OH-1 和直-8（SketchUp 3D 仓库的材质名），
    #   B4_Cobra 的 UH-1Y（和 42manako 那个同一份）、duckbillcore 的 UH-1Y（在 Stormworks 里用方块拼的）
    'mi24': {
        'ids': ['mi24'],
        'credit': credit('米-24V', 'Mi24', 'manilov.ap', '5d0b5d8dc985401685f217a775deadad', 'mi24'),
        'fwd': '+z', 'up': '+y', 'scale': 1.0138,   # 旋翼直径 17.3 米
        'level': [(r'^kr1$', r'^kr02$')],   # 原模型整架偏航了约 33°：按左右短翼摆正
        'dropmat': [r'^Tube01-FACES$', r'^Cylinder63-FACES$', r'^Box10-FACES$', r'^Cylinder75-FACES$'],   # UB-32 火箭巢、导弹发射筒
        'nodes': {r'^Line2[5-9]$': ('Rotor', 'rotor'), r'^Cylinder(48|49|50|52|53|54|55|56|57)$': ('TRotor', 'trotor')},
        # 机头 USPU-24 炮塔（YakB-12.7 四管机枪）：炮管、弹匣、观察窗跟着瞄准转
        'gunsplit': {'gun': {'x': [7.2, 8.5], 'y': 0.25, 'z': [0.5, 0.85]}, 'p': [7.45, 0.0, 0.66]},
    },
    'mi28': {
        'ids': ['mi28'],
        'credit': credit('米-28N', 'Mi-28N Havoc', 'Rukh3D', '3e80c95bbadf46abbafba9d9a08afc68', 'mi-28n-havoc'),
        'fwd': '+y', 'up': '-z', 'scale': 2.557, 'yoff': -0.76,   # 旋翼直径 17.2 米（机身 16.8 米，真机 17.01）
        'nodes': {r'^Object_16$': ('Rotor', 'rotor'), r'^Object_18$': ('TRotor', 'trotor')},
        'gunsplit': {'gun': {'x': [4.3, 7.7], 'y': 0.6, 'z': [0.6, 1.5]}, 'p': [4.91, 0.0, 1.13]},   # 机头 2A42 30 毫米炮塔
    },
    'ka52': {
        'ids': ['ka52'],
        'credit': credit('卡-52', '[PBR] Kamov Ka-52', 'Immersive3D', '6f29175ef23940fcb4c5364240e169f7', 'pbr-kamov-ka-52'),
        'fwd': '-z', 'up': '+y', 'scale': 0.515, 'yoff': 0.12,   # 旋翼直径 14.5 米、机身 13.5 米（原模型两样的比例差 7%，取中间）
        'drop': [r'^Object_4$', r'^Object_6$'],   # 短翼下的导弹、火箭巢
        # 共轴双旋翼都和机身在一个网格里：按连通块的高度分——下面那副 Rotor、上面那副 Rotor2（反着转，AirDefs 的 dir）；
        #   两副之间的轴（中心高 3.78 米）不转；垂尾（x −7.4）不算
        'comp': [{'node': r'^Object_10$', 'sel': {'x': [-7.1, 8.3], 'z': [3.85, 5.2]}, 'g': 'Rotor2', 'k': 'rotor'},
                 {'node': r'^Object_10$', 'sel': {'x': [-7.1, 8.3], 'z': [2.95, 3.65]}, 'g': 'Rotor', 'k': 'rotor'}],
    },
    'tiger': {
        'ids': ['tiger'],
        'credit': credit('虎式', 'Eurocopter EC665 "Tigre"', 'helijah', '71a9db4048f6488fbad922812041d0e6', 'eurocopter-ec665-tigre'),
        'fwd': '-x', 'up': '+y', 'scale': 0.975,
        'dropmat': [r'^DefaultWhite_(?!texture|interior)'],   # 座舱仪表（FlightGear 公用的仪表贴图，不是模型作者画的）
        # 主旋翼、尾桨（三片，在右边）都在白色那一个网格里：按连通块分
        # 机头的 30 毫米炮塔是法国 HAP / 西班牙 HAD 型的，德国 UHT 没有：去掉
        'comp': [{'node': r'^Object_14$', 'sel': {'x': [-7.8, -5.4]}, 'g': 'TRotor', 'k': 'trotor'},
                 {'node': r'^Object_14$', 'sel': {'z': [1.3, 2.1]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': r'^Object_38$', 'sel': {'x': [5.3, 7.3], 'z': [-1.4, -0.7]}, 'drop': True},
                 {'node': r'^Object_39$', 'sel': {'x': [5.5, 6.0], 'z': [-0.9, -0.7]}, 'drop': True}],
    },
    'ah1w': {
        'ids': ['ah1w'],
        'credit': credit('AH-1W', 'Bell AH-1 SuperCobra', 'drcrazzie', '6ee99382b2764fa6a3d761c3d4caec43', 'bell-ah-1-supercobra'),
        'fwd': '+z', 'up': '+y', 'scale': 0.01024,   # 两片桨的 AH-1W（标题写 SuperCobra）；旋翼直径 14.63 米
        'drop': [r'^CobraRocket_Low'],
        'nodes': {r'^CobraRotorMain(Blade|Parts|Rod)': ('Rotor', 'rotor'), r'^CobraRotorTail(Blade|Rod)': ('TRotor', 'trotor')},
        # 机头 M197 三管炮：炮塔座只转方位（GunY），炮管、炮身方位 + 俯仰（耳轴在两侧圆盘中间）
        'gunsplit': {'gun': {'x': [4.5, 6.9], 'y': 0.35, 'z': [0.55, 0.79]}, 'yaw': {'x': [4.5, 5.3], 'y': 0.3, 'z': [0.79, 0.95]},
                     'p': [4.88, 0.0, 0.71], 'py': [4.88, 0.0, 0.81]},
    },
    'mi8': {
        'ids': ['mi8'],
        'credit': credit('米-8MT', 'Mi-8', 'tiunov.se', '5e5e57ef66994c6196a5f5d6b9f50403', 'mi-8'),
        'fwd': '+z', 'up': '+y', 'scale': 0.903, 'yoff': 0.55,   # 旋翼直径 21.29 米
        'nodes': {r'^lopocty$': ('Rotor', 'rotor'), r'^zad\.vint$': ('TRotor', 'trotor')},
    },
    'uh1n': {
        'ids': ['uh1n'],
        'credit': credit('UH-1N', 'Bell UH-1N Twin Huey', 'helijah', '90bf99ba20f948a9838623311bd83da3', 'bell-uh-1n-twin-huey'),
        'fwd': '-x', 'up': '+y', 'scale': 1.03,   # 机身 12.9 米
        'dropmat': [r'^DefaultWhite_(Fuelflow|ai|alt|asi|bigpanel|buttons|chronograph|fuellbs|rad-alt|screen|torque|vsi|weight|panel212|vents)'],
        'drop': [r'^Object_26$'],   # 座舱里 3.5 万个三角形的仪表台细节（从外面看不见）
        'nodes': {r'^Object_13$': ('Rotor', 'rotor'), r'^Object_20$': ('TRotor', 'trotor')},
    },
    'nh90': {
        'ids': ['nh90'],
        'credit': credit('NH90', 'NH90 BundesHeer Gear out', 'davidmarton1987', '637145c56b2841a79c5ddc6a0548b794', 'nh90-bundesheer-gear-out'),
        'fwd': '-x', 'up': '+y', 'scale': 0.84,   # 旋翼直径 16.3 米、机身 16.1 米（原模型两样差 9%，取中间）
        'dropmat': [r'^HeliSim_EC225_cockpit$'],   # 座舱仪表贴图是别的模拟器的
        # SketchUp 导出的：桨叶按颜色散在好几个网格里，按连通块的位置挑——尾桨在左边（y 0.36～0.52 那一片薄的），
        #   桨毂在 (1.84, 0) 上面（机背整流罩中心高 3.28，不算），四片桨叶各一个盒子（离桨毂 1.3 米以外）
        'comp': [{'node': '.', 'sel': {'x': [-9.0, -6.6], 'y': [0.36, 0.52], 'z': [2.3, 5.3]}, 'g': 'TRotor', 'k': 'trotor'},
                 {'node': '.', 'sel': {'x': [0.4, 3.3], 'ay': [0, 1.2], 'z': [3.36, 4.2]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': '.', 'sel': {'x': [3.3, 9.6], 'ay': [0, 0.8], 'z': [3.12, 3.85]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': '.', 'sel': {'x': [-6.0, 0.4], 'y': [-0.2, 0.8], 'z': [3.3, 3.85]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': '.', 'sel': {'x': [0.8, 3.0], 'y': [1.3, 7.6], 'z': [3.1, 3.85]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': '.', 'sel': {'x': [0.8, 3.0], 'y': [-7.6, -1.3], 'z': [3.1, 3.85]}, 'g': 'Rotor', 'k': 'rotor'}],
    },
    # AH-1S（陆上自卫队）：3D 打印用的整块网格（STL，没有贴图）——按连通块分；涂成陆自的橄榄绿
    'ah1s': {
        'ids': ['ah1s'],
        'credit': credit('AH-1S', 'Ah-1s', 'Gorgytz', 'ad49c4e81546469d9d36d8e58f72fd33', 'ah-1s'),
        'fwd': '+z', 'up': '+y', 'scale': 0.03465,   # 旋翼直径 13.41 米（机身 13.5 米）
        'matfix': {'Scene_-_Root': {'c': [0.26, 0.28, 0.19, 1.0], 'mr': [0.0, 0.72]}},
        'comp': [{'node': '.', 'sel': {'x': [0.5, 2.3], 'ay': [0, 0.3], 'z': [3.0, 3.6]}, 'g': 'Rotor', 'k': 'rotor'},
                 {'node': '.', 'sel': {'x': [-7.6, -6.0], 'y': [-0.6, -0.1], 'z': [2.5, 3.4]}, 'g': 'TRotor', 'k': 'trotor'},
                 {'node': '.', 'sel': {'x': [0.6, 2.6], 'ay': [0.7, 1.3], 'z': [0.8, 1.9]}, 'drop': True},   # 短翼下的陶式发射架
                 {'node': '.', 'sel': {'x': [0.2, 2.2], 'ay': [1.3, 1.8], 'z': [0.7, 1.5]}, 'drop': True},   # 火箭巢、挂架上的小件
                 {'node': '.', 'sel': {'x': [0.3, 2.2], 'ay': [1.9, 2.5], 'z': [0.6, 1.3]}, 'drop': True},   # 外侧挂点的发射筒
        # 机头 M197 三管炮：炮塔座只转方位（GunY），炮管方位 + 俯仰（Gun）；p 是网页版坐标（减了地面）
                 {'node': '.', 'sel': {'x': [4.6, 6.2], 'ay': [0, 0.35], 'z': [0.35, 0.7]}, 'g': 'Gun', 'k': 'gun', 'extra': {'p': [4.49, 0.0, 0.52]}},
                 {'node': '.', 'sel': {'x': [4.1, 4.6], 'ay': [0, 0.35], 'z': [0.62, 0.9]}, 'g': 'GunY', 'k': 'gunyaw', 'extra': {'p': [4.49, 0.0, 0.69]}}],
    },
    'z8': {
        'ids': ['z8'],
        'credit': credit('直-8（超黄蜂）', 'Aérospatiale SA 321 Super Frelon', 'helijah', '941cbf9f814f460aa97d653f7d637378', 'aerospatiale-sa-321-super-frelon'),
        'fwd': '-x', 'up': '+y', 'scale': 0.958,   # 机身 19.4 米（直-8 就是国产的超黄蜂）
        'dropmat': [r'^DefaultWhite_(adi|alt|asi|ils|oil-temp|panel|pedestal|rpm|torque|vsi)'],
        'nodes': {r'^Object_1[0-5]$': ('Rotor', 'rotor'), r'^Object_21$': ('TRotor', 'trotor')},
    },
}



def shifted(base, dx, **kw):
    """同一套网格、整体前后挪了 dx 米的模型（T-50 原型机比量产型机头多一根试飞空速管，包围盒中心往前挪，别的都往后挪 0.74 米）：
    SPEC 里所有前后位置（sel 的 x、铰链、收好的位置、喷口、座舱、尾喷口）一起挪"""
    import copy
    S = copy.deepcopy(SPEC[base])

    def sel(d):
        if isinstance(d, dict) and 'x' in d:
            d['x'] = [d['x'][0] + dx, d['x'][1] + dx]
    for k in ('legs', 'doors', 'odoors', 'flaps', 'brace'):
        for e in S.get(k, []):
            for kk in ('sel', 'off'):
                sel(e.get(kk))
            for kk in ('p', 'to', 'w'):
                if kk in e:
                    e[kk] = [e[kk][0] + dx] + list(e[kk][1:])
    for e in S.get('nozzles', []):
        e['x'] = [e['x'][0] + dx, e['x'][1] + dx]
    for e in S.get('comp', []):
        sel(e.get('sel'))
    for k in ('pit', 'noz'):
        if k in S:
            S[k] = [[v[0] + dx] + list(v[1:]) for v in S[k]]
    S.update(kw)
    return S


# T-50（苏-57 原型机，bohmerang 的「Sukhoi Su-57 Felon (P) - Fighter Jet - Free」，同一个作者、同一套网格：机头多一根试飞空速管、原型机的涂装）
SPEC['t50'] = shifted('su57', -0.74, ids=['t50'],
    credit='T-50（苏-57 原型机）：Sukhoi Su-57 Felon (P) - Fighter Jet - Free，作者 bohmerang（https://sketchfab.com/3d-models/sukhoi-su-57-felon-p-fighter-jet-free-31127bc63bc048debb694aa88bbaafae），'
           'CC BY-NC-SA 4.0（署名—非商业—相同方式共享；作者注明只许个人使用、不许用于商业作品）。'
           '（改动：转成 Roblox 坐标、按机轮摆平，舵面、座舱盖、起落架、舱门、喷口调节片拆成会动的块）')

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
    # 直升机：桨叶伸到机身前后，按全长量不准——SPEC 直接给 scale（原模型单位 → 米，按机身长、旋翼直径量的）
    s = S['scale'] if S.get('scale') else S['len'] / (hi[0] - lo[0])
    if not pairs:
        ymid = float((lo[1] + hi[1]) / 2)
    else:
        L = [p for p in keep]
        ymid = float((lo[1] + hi[1]) / 2) if S.get('ymid') == 'box' else ymid
    t = np.array([-(lo[0] + hi[0]) / 2, -ymid, 0.0])
    # 直升机：包围盒算进了桨叶（停着的桨叶左右不对称），机身中线偏了——yoff（米）把中线挪回 y = 0（GUNSPLIT 的范围按中线左右对称量）
    t[1] -= S.get('yoff', 0.0) / s
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
    if 'y' in sel and not (sel['y'][0] <= c[1] <= sel['y'][1]):   # 分左右（y 左正）
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


def mirror_sel(sel):
    """左边的范围换成右边的：y 区间取反（ay 是 |y|，不用动）"""
    o = dict(sel)
    if 'y' in sel:
        o['y'] = [-sel['y'][1], -sel['y'][0]]
    return o


CARVED = {}  # build() 雕过的显示屏：{名字: {'z0' 显示面离 pitscr.c 平面多远, 'cut' 切了几个三角形}}
EXTRA = {}   # build() 顺便算的：飞行员眼位、座舱屏幕（网页版坐标），main() 交给 air_anim 的 PIT / PITSCR


def carve_rects(P, N, UV, T, rects):
    """在原模型上雕刻显示屏（用户 11-24：「我需要你在原模型上雕刻显示屏哈」）：多功能显示器那块机壳正面，显示区挖进去一个槽，
    屏幕（游戏里的 SurfaceGui）放在槽底——跟真的 MFD 一样，玻璃比四周的边框、按键低一截，不是贴在面上的一张画。
    rects = [{'c', 'n', 'u', 'w', 'h', 'd'}]（原模型坐标；n 朝人、u 朝上、w × h 槽口、d 槽深）：
      ① 挑出贴着显示面的三角形：朝 n（法线和 n 夹角 25° 以内）、离 c 那个平面 1 厘米以内、平面上的范围和槽口有交叠；
      ② 这些三角形按槽口的四条边一刀一刀切开（多边形对半平面裁剪，切出来的点按边插值位置、法线、贴图坐标），槽口里的扔掉；
      ③ 补四面槽壁（法线朝槽里）、槽底（法线朝 n）——给深色材质，单独返回。
    返回 (P, N, UV, T, walls, info)：walls[i] = 第 i 个槽的 (P, N, T)（这个图元里没有那块显示面就没有）；
    info[i] = {'z0' 显示面离 c 平面多远（沿 n）, 'cut' 扔掉 / 切开的三角形数}"""
    P = np.asarray(P, dtype=np.float64)
    N = np.asarray(N, dtype=np.float64)
    UV = np.asarray(UV, dtype=np.float64)
    T = np.asarray(T)
    outP, outN, outUV, outT = [P], [N], [UV], []
    nv = len(P)
    keep = np.ones(len(T), dtype=bool)
    walls = {}
    info = []
    for ri, R in enumerate(rects):
        wallP, wallN, wallT = [], [], []
        c = np.asarray(R['c'], dtype=np.float64)
        n = np.asarray(R['n'], dtype=np.float64)
        n /= np.linalg.norm(n)
        u = np.asarray(R['u'], dtype=np.float64)
        u = u - n * (u @ n)
        u /= np.linalg.norm(u)
        r = np.cross(n, u)   # 平面上的第三根轴（右手：r × u = n）
        hw, hh, d = R['w'] / 2, R['h'] / 2, R['d']
        a = (P - c) @ r
        b = (P - c) @ u
        z = (P - c) @ n
        Tk = T[keep]
        idx = np.where(keep)[0]
        fn = np.cross(P[Tk[:, 1]] - P[Tk[:, 0]], P[Tk[:, 2]] - P[Tk[:, 0]])
        fl = np.linalg.norm(fn, axis=1)
        facing = (fn @ n) > 0.9 * np.maximum(fl, 1e-12)
        A_, B_, Z_ = a[Tk], b[Tk], z[Tk]
        over = (A_.max(1) > -hw) & (A_.min(1) < hw) & (B_.max(1) > -hh) & (B_.min(1) < hh)
        # 原模型自己已经凹进去的显示器（F-16 的 MFD：边框一圈、槽壁、槽底是带画面贴图的显示面）：槽口里朝人的面比四周的边框深 2 毫米以上——
        #   就把槽底那块（带原来的画面贴图）去掉、槽壁顺着往下再接 d、补新槽底；平的面板才从面上挖
        Ac, Bc, Zc = A_.mean(1), B_.mean(1), Z_.mean(1)
        inner = facing & (np.abs(Ac) < hw * 0.8) & (np.abs(Bc) < hh * 0.8) & (Zc > -0.05) & (Zc < 0.01)
        ring = facing & (np.maximum(np.abs(Ac) / hw, np.abs(Bc) / hh) > 1.0) & (np.maximum(np.abs(Ac) / hw, np.abs(Bc) / hh) < 1.3) & (np.abs(Zc) < 0.02)
        z_in = float(np.median(Zc[inner])) if inner.any() else None
        z_rim = float(np.max(Zc[ring])) if ring.any() else None
        recessed = z_in is not None and z_rim is not None and z_in < z_rim - 0.002
        if recessed:
            near = (np.abs(Z_ - z_in) < 0.0025).all(axis=1)
        else:
            near = (np.abs(Z_) < 0.01).all(axis=1)
        sel = idx[facing & near & over]
        if not len(sel):
            info.append({'z0': 0.0, 'cut': 0, 'old': False})
            continue
        z0 = float(np.median(z[T[sel]]))
        # 一刀一刀切：每刀把多边形分成「槽口外」（留下，三角化）和「还可能在槽口里」（接着切）；四刀切完剩下的就是槽口里的，扔掉
        cuts = [(r, -hw, -1), (r, hw, 1), (u, -hh, -1), (u, hh, 1)]   # (轴, 边, 外侧方向)：s*(x·轴 − 边) > 0 是槽口外

        def split(poly, ax, e0, s):
            def f(v):
                return s * ((v[0] - c) @ ax - e0)
            out_, in_ = [], []
            m = len(poly)
            for k in range(m):
                v1, v2 = poly[k], poly[(k + 1) % m]
                f1, f2 = f(v1), f(v2)
                (out_ if f1 > 0 else in_).append(v1)
                if (f1 > 0) != (f2 > 0):
                    t_ = f1 / (f1 - f2)
                    vm = tuple(v1[j] + (v2[j] - v1[j]) * t_ for j in range(3))
                    out_.append(vm)
                    in_.append(vm)
            return out_, in_
        ncut = 0
        for ti in sel:
            keep[ti] = False
            ncut += 1
            poly = [(P[k], N[k], UV[k]) for k in T[ti]]
            for ax, e0, s in cuts:
                if len(poly) < 3:
                    break
                o_, poly = split(poly, ax, e0, s)
                if len(o_) >= 3:   # 槽口外这一片：扇形三角化，顶点顺序不变（正反面不变）
                    base = nv
                    for (pp, nn, uu) in o_:
                        outP.append(pp[None])
                        nn2 = nn / (np.linalg.norm(nn) + 1e-12)
                        outN.append(nn2[None])
                        outUV.append(uu[None])
                        nv += 1
                    for k in range(1, len(o_) - 1):
                        outT.append([base, base + k, base + k + 1])
        # 槽壁、槽底：槽口四角在显示面上（z0），往里 d
        def corner(ca, cb, cz):
            return c + r * ca + u * cb + n * cz
        quads = [((-hw, -hh), (-hw, hh), r), ((hw, hh), (hw, -hh), -r), ((-hw, hh), (hw, hh), -u), ((hw, -hh), (-hw, -hh), u)]
        for (p1, p2, nrm) in quads:
            q = [corner(p1[0], p1[1], z0), corner(p2[0], p2[1], z0), corner(p2[0], p2[1], z0 - d), corner(p1[0], p1[1], z0 - d)]
            base = sum(len(x) for x in wallP)
            wallP.append(np.array(q))
            wallN.append(np.repeat(nrm[None], 4, axis=0))
            tri = [[base, base + 1, base + 2], [base, base + 2, base + 3]]
            g = np.cross(q[1] - q[0], q[2] - q[0])
            if g @ nrm < 0:
                tri = [[t_[0], t_[2], t_[1]] for t_ in tri]
            wallT.extend(tri)
        q = [corner(-hw, -hh, z0 - d), corner(hw, -hh, z0 - d), corner(hw, hh, z0 - d), corner(-hw, hh, z0 - d)]
        base = sum(len(x) for x in wallP)
        wallP.append(np.array(q))
        wallN.append(np.repeat(n[None], 4, axis=0))
        tri = [[base, base + 1, base + 2], [base, base + 2, base + 3]]
        if np.cross(q[1] - q[0], q[2] - q[0]) @ n < 0:
            tri = [[t_[0], t_[2], t_[1]] for t_ in tri]
        wallT.extend(tri)
        walls[ri] = (np.concatenate(wallP), np.concatenate(wallN), np.array(wallT, dtype=np.int64))
        info.append({'z0': z0, 'cut': ncut, 'old': bool(recessed), 'top': float(z_rim) if recessed else z0})
    T2 = np.concatenate([T[keep]] + ([np.array(outT, dtype=T.dtype)] if outT else []), axis=0)
    return np.concatenate(outP), np.concatenate(outN), np.concatenate(outUV), T2, walls, info


def build(key, path):
    """读下载的 GLB，按 SPEC 做成网页版烘焙模型那样的 (meta, binb, credit)，外加节点部件的铰链表（网页版坐标）"""
    S = SPEC[key]
    J, BIN = load_glb(path)
    prims = gather(J, BIN)
    Rm, t, s = frame(prims, S)
    nodes = S.get('nodes', {})
    # 两套起落架网格（sf_gear.py）：地面 = 放下的机轮最低点；legs / doors / nozzles / selg 的范围都按离地高度量（z 减了地面）
    gon, goff = S.get('gearon', []), S.get('gearoff', [])
    zg = None
    if gon:
        zg = min(float(((p['P'] @ Rm.T + t) * s)[:, 2].min()) for p in prims if match(p['path'], gon))
    elif S.get('ground'):   # 起落架和机身一个网格、只有放下的样子（苏-25）：地面 = 整个模型最低点（机轮）
        zg = min(float(((p['P'] @ Rm.T + t) * s)[:, 2].min()) for p in prims if not match(p['path'], S.get('drop', [])))
    zoff = np.array([0.0, 0.0, zg if (zg is not None and S.get('selg')) else 0.0])
    G = {'legs': {}, 'doors': {}, 'closed': {}, 'flaps': {}, 'odoors': {}, 'noz': {}, 'sdoors': {}, 'sdspec': {}}   # 部件名 → 顶点（网页版坐标、地面 z = 0）
    legs, doors, flaps = [], [], []
    for L in S.get('legs', []):
        legs.append(L)
        if L.get('mir'):
            R_ = dict(L)
            R_['g'] = L['g'][:-1] + 'R'
            if 'sel' in L:   # 腿在机身网格里（苏-25）：comp 的 leg 规则挑块，这里没有 sel
                R_['sel'] = mirror_sel(L['sel'])
            for k_ in ('p', 'to', 'w'):
                if k_ in L:
                    R_[k_] = [L[k_][0], -L[k_][1], L[k_][2]]
            legs.append(R_)
    for D in S.get('doors', []):
        for sd in ((1, -1) if D.get('mir') else (0,)):
            D2 = dict(D)
            D2['g'] = D['g'] + {1: 'L', -1: 'R', 0: ''}[sd]
            if sd == -1:
                D2['sel'], D2['off'] = mirror_sel(D['sel']), mirror_sel(D['off'])
                if D.get('crop'):
                    D2['crop'] = mirror_sel(D['crop'])
            doors.append(D2)
    for F in S.get('flaps', []):
        flaps.append(F)
    nozs = []
    for Nz in S.get('nozzles', []):
        for sd in (1, -1):
            N2 = dict(Nz)
            N2['side'] = sd
            N2['c'] = [Nz['c'][0] * sd, Nz['c'][1]]
            nozs.append(N2)
    # 原模型自带座舱（用户 11-23：「你去找带内饰的然后给他们屏幕实现功能」）：座舱里的件（pitmat 材质、pitnode 节点）单独成 Pit 组——
    #   游戏里坐进座舱时不藏（看到的就是原模型的座舱），屏幕贴在它的显示器上；pithud 原模型的平显（玻璃上画死了符号）单独成 PitHud 组，
    #   座舱里藏起来、换成我们会动的平显
    pitmat, pitnode, pithud = set(S.get('pitmat', [])), S.get('pitnode', []), S.get('pithud', [])
    # 要雕刻的显示屏（pitscr 里带 carve 的）：座舱件的三角形先按槽口切开、补槽壁槽底（carve_rects）
    cnames = [nm for nm, e in (S.get('pitscr') or {}).items() if e.get('carve')]
    crects = []
    for nm in cnames:
        e = S['pitscr'][nm]
        cv = e['carve']
        crects.append({'c': e['c'], 'n': e['n'], 'u': e['u'], 'w': cv.get('w', e['w']), 'h': cv.get('h', e['h']), 'd': cv['d']})
    CARVED.clear()
    recess = []   # 槽壁、槽底（变换后的 P, N, UV, T），后面给深色材质
    mnames = [m.get('name', '') for m in (J.get('materials') or [])]
    # 座舱盖用了机身那张带透明通道的贴图（整个机身材质是半透明混合）：机身改不透明，座舱盖另外克隆一份半透明的材质
    glassnode = S.get('glassnode', [])
    clones = []

    def clone_of(mi):
        if mi not in clones:
            clones.append(mi)
        return len(mnames) + clones.index(mi)
    # 每个图元属于哪个部件：去掉的、起落架、节点活动部件、机体
    VB, IB, lod = [], [], []
    parts = [{'n': 'gear'}]   # pi 0：起落架（air_anim.GEAR 按连通块分前 / 左 / 右）
    pidx = {}
    surfspec = {}
    nv = 0
    groups = {}
    dropmat = S.get('dropmat', [])
    def grp(name, mat, P, N, UV, T):
        if name not in pidx:
            pidx[name] = len(parts)
            parts.append({'n': name})
        groups.setdefault((mat, pidx[name]), []).append((P, N, UV, T))
    for p in prims:
        if match(p['path'], S.get('drop', [])):
            continue
        if gon and (match(p['path'], gon) or match(p['path'], goff)):
            on = bool(match(p['path'], gon))
            P = (p['P'] @ Rm.T + t) * s
            N = p['N'] @ Rm.T
            Pg = P - np.array([0, 0, zg])
            lab = components(P, p['T'])
            for l in np.unique(lab):
                m = lab == l
                T_ = p['T'][m]
                Q = Pg[np.unique(T_.reshape(-1))]
                lo_, hi_ = Q.min(0), Q.max(0)
                name = None
                if on:
                    for B_ in S.get('brace', []):   # 撑杆（收的时候真机折起来）：起落架一动就藏起来
                        if inbox(lo_, hi_, B_['sel']):
                            name = B_['g']
                            break
                    for L in ([] if name else legs):
                        if inbox(lo_, hi_, L['sel']):
                            name = L['g']
                            G['legs'].setdefault(name, []).append(Q)
                            break
                    if name is None:
                        for D in doors:
                            if inbox(lo_, hi_, D['sel']):
                                name = D['g']
                                G['doors'].setdefault(name, []).append((Pg, T_))
                                break
                    if name is None:
                        for D in S.get('odoors', []):   # 两头关着、中途开着的门（前轮舱前门）：按三角形重心分左右两扇
                            if inbox(lo_, hi_, D['sel']):
                                cy = Pg[T_].mean(axis=1)[:, 1]
                                for sd_, mk in (('L', cy >= 0), ('R', cy < 0)):
                                    if mk.any():
                                        nm_ = D['g'] + sd_
                                        G['odoors'].setdefault(nm_, (D, []))[1].append(Pg[np.unique(T_[mk].reshape(-1))])
                                        grp(nm_, p['mat'], P, N, p['UV'], T_[mk])
                                name = ''
                                break
                    if name is None:
                        name = 'GearX'   # 舱里的作动筒、支架：收到底时藏起来
                        if os.environ.get('GEARX'):
                            print('    GearX 块：%d 个三角形  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f' % (len(T_), lo_[0], hi_[0], lo_[1], hi_[1], lo_[2], hi_[2]))
                else:
                    for D in doors:
                        if inbox(lo_, hi_, D['off']):
                            G['closed'].setdefault(D['g'], []).append((Pg, T_))
                    for F in flaps:
                        if inbox(lo_, hi_, F['off']):
                            if F.get('split') == 'y':   # 左右两扇：按三角形重心在中线哪边分开
                                cy = Pg[T_].mean(axis=1)[:, 1]
                                for sd_, mk in (('L', cy >= 0), ('R', cy < 0)):
                                    if mk.any():
                                        nm_ = F['g'] + sd_
                                        G['flaps'].setdefault(nm_, (F, []))[1].append(Pg[np.unique(T_[mk].reshape(-1))])
                                        grp(nm_, p['mat'], P, N, p['UV'], T_[mk])
                                name = ''
                            else:
                                name = F['g']
                                G['flaps'].setdefault(name, (F, []))[1].append(Q)
                            break
                    if name is None:
                        name = 'GearUp'   # 收起后关好的门板：收到底时才画
                if name:
                    grp(name, p['mat'], P, N, p['UV'], T_)
            continue
        if dropmat and 0 <= p['mat'] < len(mnames) and any(re.search(r_, mnames[p['mat']]) for r_ in dropmat):
            continue   # 按材质去掉（FlightGear 公用仪表的贴图：不是模型作者本人画的；起落架上挂的外挂……）
        if glassnode and match(p['path'], glassnode) and p['mat'] >= 0:
            p = dict(p)
            p['mat'] = clone_of(p['mat'])
        mname = mnames[p['mat']] if 0 <= p['mat'] < len(mnames) else ''
        inPit = mname in pitmat or (pitnode and match(p['path'], pitnode))
        if inPit or (pithud and match(p['path'], pithud)):
            P0, N0, UV0, T0 = p['P'], p['N'], p['UV'], p['T']
            if inPit and crects and not (pithud and match(p['path'], pithud)):
                P0, N0, UV0, T0, walls, cinfo = carve_rects(P0, N0, UV0, T0, crects)
                for ri, wl in walls.items():
                    nm = cnames[ri]
                    if nm in CARVED:   # 同一块显示面分在几个图元里：槽壁只补一次
                        continue
                    CARVED[nm] = {'z0': cinfo[ri]['z0'], 'cut': cinfo[ri]['cut'], 'old': cinfo[ri]['old'], 'top': cinfo[ri]['top']}
                    WP, WN, WT = wl
                    recess.append(((WP @ Rm.T + t) * s, WN @ Rm.T, np.zeros((len(WP), 2)), WT))
            P = (P0 @ Rm.T + t) * s
            N = N0 @ Rm.T
            hud = np.zeros(len(T0), dtype=bool)
            if pithud and match(p['path'], pithud):
                hud[:] = True
                if S.get('pithud_box'):   # 平显和别的东西是一块网格：只要盒子（原模型坐标）里的三角形（重心算）
                    lo_, hi_ = np.array(S['pithud_box'][0]), np.array(S['pithud_box'][1])
                    C = P0[T0].mean(axis=1)
                    hud = ((C >= lo_) & (C <= hi_)).all(axis=1)
            for pg, msk in (('PitHud', hud), ('Pit', ~hud)):
                if not msk.any() or (pg == 'Pit' and not inPit):
                    continue
                if pg not in pidx:
                    pidx[pg] = len(parts)
                    parts.append({'n': pg})
                groups.setdefault((p['mat'], pidx[pg]), []).append((P, N, UV0, T0[msk]))
            continue
        # 按连通块挑：一个节点里合在一起的翼面（鸭翼和机翼一个节点）、挂着的副油箱（和机身一个节点）
        rules = [r for r in S.get('comp', []) if any(re.search(r['node'], n) for n in names_of(p['path']))]
        nzr = [z_ for z_ in nozs if any(re.search(z_['node'], n) for n in names_of(p['path']))]
        if rules or nzr:
            P = (p['P'] @ Rm.T + t) * s
            N = p['N'] @ Rm.T
            lab = components(P, p['T'])
            rest = np.ones(len(p['T']), dtype=bool)
            for l in np.unique(lab):
                m = lab == l
                Q = P[p['T'][m].reshape(-1)]
                lo_, hi_ = Q.min(0) - zoff, Q.max(0) - zoff
                c_ = (lo_ + hi_) / 2
                hitN = None
                for z_ in nzr:   # 喷口：中心在前后范围里、离喷口轴不到 r
                    if z_['x'][0] <= c_[0] <= z_['x'][1] and math.hypot(c_[1] - z_['c'][0], c_[2] - z_['c'][1]) <= z_['r']:
                        hitN = z_
                        break
                if hitN is not None:
                    G['noz'].setdefault(id(hitN), (hitN, []))[1].append((p['mat'], P, N, p['UV'], p['T'][m]))
                    rest[m] = False
                    continue
                for r in rules:
                    if not inbox(lo_, hi_, r['sel']):
                        continue
                    rest[m] = False
                    if r.get('drop'):
                        break
                    if r.get('grp'):   # 只分组、不当活动部件（AirModels 按组名处理）：GearB 起落架一动就藏（收的时候真机折起来的撑杆）、GearX 收到底藏、Gear 收起一半藏
                        grp(r['grp'], p['mat'], P, N, p['UV'], p['T'][m])
                        break
                    if r.get('leg') or r.get('sdoor'):   # 起落架和机身一个网格的（苏-25）：这一块属于哪条腿 / 哪扇门（关键帧部件，sf_gear.py）
                        nm_ = r.get('leg') or r.get('sdoor')
                        if r.get('split') == 'y':
                            nm_ += 'L' if (lo_[1] + hi_[1]) / 2 >= 0 else 'R'
                        Qg = Q - np.array([0, 0, zg])
                        (G['legs'] if r.get('leg') else G['sdoors']).setdefault(nm_, []).append(Qg)
                        if r.get('sdoor'):
                            G['sdspec'][nm_] = r
                        grp(nm_, p['mat'], P, N, p['UV'], p['T'][m])
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
    # 原模型的喷口（sf_gear.nozzle_parts）：外筒、按方位分组的调节片各成一个部件；推力矢量、开合的参数进 surf
    xsurf = {}
    for _, (Nz, lst) in G['noz'].items():
        comps_ = [(k, (P - np.array([0, 0, zg]))[np.unique(T.reshape(-1))]) for k, (mi, P, N, UV, T) in enumerate(lst)]
        names_, sf_ = SG.nozzle_parts(comps_, Nz, Nz['side'], log=print)
        for k, (mi, P, N, UV, T) in enumerate(lst):
            grp(names_[k], mi, P, N, UV, T)
        xsurf.update(sf_)
    # 起落架（sf_gear）：每条腿、每扇门一个关键帧部件（网页版坐标、地面 z = 0，就是下面减了 z0 以后的坐标）
    for L in legs:
        if L['g'] not in G['legs']:
            raise ValueError('%s 的起落架 %s 一块也没挑到（sel 量错了？）' % (key, L['g']))
        p_, frames = SG.leg_frames(G['legs'][L['g']], L, log=print)
        # hu：gear 低于它就藏起来——腿收到位（win 的起点）以后关门那段时间腿已经在舱里，藏掉免得舱太浅的地方（米格-29 翼根）蒙皮盖不住
        ex_ = {} if L.get('keep') else {'hu': round(L.get('win', (0.2, 1.0))[0] + 0.01, 3)}   # keep：没有舱门的（苏-25），收好的腿留在舱里不藏
        if L.get('steer'):
            ex_['st'] = 1
        xsurf[L['g']] = SG.kf_entry(p_, frames, extra=ex_)
    for D in doors:
        if D['g'] not in G['doors'] or D['g'] not in G['closed']:
            raise ValueError('%s 的舱门 %s 没配上（打开的 %d 块、关好的 %d 块）' % (key, D['g'], len(G['doors'].get(D['g'], [])), len(G['closed'].get(D['g'], []))))
        So = np.concatenate([SG.sample(P, T, 3000) for P, T in G['doors'][D['g']]])
        Sc = np.concatenate([SG.sample(P, T, 3000) for P, T in G['closed'][D['g']]])
        if D.get('crop'):   # 关好的门板比打开的门大（盖住支柱那一截的门跟着支柱走）：只拿这一段拟合
            cp = D['crop']
            keep = np.ones(len(Sc), dtype=bool)
            for ax_, k_ in ((0, 'x'), (1, 'y'), (2, 'z')):
                if k_ in cp:
                    keep &= (Sc[:, ax_] >= cp[k_][0]) & (Sc[:, ax_] <= cp[k_][1])
            if 'ay' in cp:
                keep &= (np.abs(Sc[:, 1]) >= cp['ay'][0]) & (np.abs(Sc[:, 1]) <= cp['ay'][1])
            Sc = Sc[keep]
        R_, t_, err = SG.fit_door(Sc, So, log=print)
        if err > D.get('tol', 0.03):
            print('  ！%s 舱门拟合残差 %.1f 毫米，偏大' % (D['g'], err * 1000))
        Vo = np.concatenate([P[np.unique(T.reshape(-1))] for P, T in G['doors'][D['g']]])
        c_, frames = SG.door_frames(R_, t_, Vo, win=D.get('win', (0.0, 0.2)), log=print, name=D['g'])
        xsurf[D['g']] = SG.kf_entry(c_, frames, extra={'hu': 1})
    for nm_, Vs in G['sdoors'].items():   # 只有打开样子的门：绕最高那条长边转回贴着蒙皮（关上）
        c_, frames = SG.sdoor_frames(np.concatenate(Vs), G['sdspec'][nm_], log=print, name=nm_)
        xsurf[nm_] = SG.kf_entry(c_, frames)
    for nm_, (D, Vs) in G['odoors'].items():
        c_, frames = SG.oc_frames(np.concatenate(Vs), D.get('A', 88), win=D.get('win', (0.0, 0.15, 0.85, 1.0)), log=print, name=nm_)
        xsurf[nm_] = SG.kf_entry(c_, frames, extra={'hu': 1})
    for nm_, (F, Vs) in G['flaps'].items():
        c_, frames = SG.flap_frames(np.concatenate(Vs), F.get('A', 85), win=F.get('win', (0.0, 0.2)), log=print, name=nm_)
        xsurf[nm_] = SG.kf_entry(c_, frames)
    # 槽壁、槽底：一种新材质（深色哑光，排在座舱盖克隆的材质后面），放进座舱件那一组
    for nm in cnames:
        if nm not in CARVED:
            print('  ！%s 没找到要雕的显示面（pitscr 的 c / n 量错了？）' % nm)
    recess_mi = None
    if recess:
        recess_mi = len(mnames) + len(clones)
        groups[(recess_mi, pidx['Pit'])] = recess
    allP = np.concatenate([P for gl in groups.values() for (P, _, _, _) in gl])
    gearP = [P for (mi, pi), gl in groups.items() if pi == 0 for (P, _, _, _) in gl]
    z0 = float(np.concatenate(gearP)[:, 2].min()) if gearP else float(allP[:, 2].min())
    if zg is not None:
        z0 = zg
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
        fx = S.get('matfix', {}).get(m.get('name', ''))
        if fx:
            mm.update(fx)
        mats.append(mm)
    for mi in clones:   # 座舱盖：同一张贴图，半透明混合（贴图的透明通道就是玻璃）
        mm = dict(mats[mi])
        mm['n'] = (mm['n'] + '_glass')[:40]
        mm['am'] = 2
        mats.append(mm)
    if recess_mi is not None:   # 雕出来的显示屏槽：深灰哑光（真的 MFD 玻璃四周是黑色的边框内壁）
        assert recess_mi == len(mats)
        mats.append({'n': 'PitRecess', 'c': [0.028, 0.030, 0.034, 1.0], 'mr': [0.0, 0.65], 'am': 0})
    vb = VBa.tobytes()
    ib = IBa.tobytes()
    binb = vb + ib + b''.join(blobs)
    meta = {'st': 8, 'vb': [0, len(vb)], 'ib': [len(vb), len(ib)], 'it': 4, 'lod': [lod], 'parts': parts, 'mats': mats, 'imgs': imgs,
            'noz': S.get('noz', [])}
    # 飞行员眼位、座舱屏幕（原模型坐标量的）→ 网页版坐标
    def toweb(P):
        q = (np.asarray(P, dtype=np.float64) @ Rm.T + t) * s
        q[..., 2] -= z0
        return q

    def todir(D):
        v = np.asarray(D, dtype=np.float64) @ Rm.T
        return v / np.linalg.norm(v)
    EXTRA.clear()
    if S.get('eye_src'):
        EXTRA['eye'] = toweb(S['eye_src'])
    if S.get('pitscr'):
        EXTRA['scr'] = {}
        for nm, e in S['pitscr'].items():
            o = {'c': toweb(e['c']), 'n': todir(e['n']), 'u': todir(e['u']), 'w': e['w'] * s, 'h': e['h'] * s}
            o.update({k: v for k, v in e.items() if k not in ('c', 'n', 'u', 'w', 'h', 'carve')})
            if nm in CARVED:   # 雕过的：屏幕在槽底，大小 = 槽口；d = 边框面到槽底多深（游戏按它把屏边键帽摆回边框上原来的按键那儿）
                cv, K_ = e['carve'], CARVED[nm]
                n_ = np.asarray(e['n'], dtype=np.float64)
                n_ = n_ / np.linalg.norm(n_)
                floor = K_['z0'] - cv['d']
                o['c'] = toweb(np.asarray(e['c'], dtype=np.float64) + n_ * floor)
                o['w'], o['h'], o['d'] = cv.get('w', e['w']) * s, cv.get('h', e['h']) * s, (K_['top'] - floor) * s
            EXTRA['scr'][nm] = o
    # 节点活动部件的铰链（网页版坐标）
    surf = {}
    T3 = IBa.reshape(-1, 3)
    tri_pi = np.concatenate([np.full(cnt // 3, pi) for (mi, pi, s0, cnt) in lod])
    for g, spec in surfspec.items():
        sel = np.where(tri_pi == pidx[g])[0]
        if spec[1] in ('rotor', 'trotor'):   # 直升机旋翼、尾桨：不是舵面，算转轴（air2glb 做成 Rotor / Rotor2 / TRotor 部件）
            parts[pidx[g]] = rotor_part(g, spec, VBa[:, 0:3].astype(np.float64), T3[sel], toweb, todir)
            continue
        if spec[1] in ('gun', 'gunyaw'):   # 机头炮塔（同 air2glb.GUNSPLIT，但在这里按连通块先分好：整块网格的模型炮和机身挨着，air2glb 按 1 厘米焊会连成一块）
            parts[pidx[g]] = {'n': g, 'p': list((spec[2] if len(spec) > 2 else {})['p'])}
            continue
        Q = VBa[np.unique(T3[sel].reshape(-1)), 0:3].astype(np.float64)
        surf[g] = hinge(g, spec, Q)
    surf.update(xsurf)
    print('  %s：%d 个三角形、%d 种材质、%d 张贴图；全长 %.2f 米、翼展 %.2f 米、高 %.2f 米；节点活动部件 %s' % (
        key, len(T3), len(mats), len(imgs), np.ptp(allP[:, 0]), np.ptp(allP[:, 1]), float(allP[:, 2].max() - z0), ', '.join(sorted(surf))))
    return meta, binb, S['credit'], surf


def rotor_part(g, spec, P, T, toweb, todir):
    """旋翼 / 尾桨部件：转轴 a = 桨叶面的法线（按三角形面积加权的法线协方差，最大的那个方向——桨叶上下表面占了面积的大头，
    两片桨的也算得准；不能用顶点的主成分：桨毂、桨毂罩竖着比桨叶的弦还高），支点 p = 面积加权的重心（几片桨对称，重心就在桨毂上）。
    主旋翼轴朝上、尾桨轴朝左（+y）；量不准的在 SPEC 里给 p / a（原模型坐标）"""
    extra = spec[2] if len(spec) > 2 else {}
    A_ = P[T[:, 0]]
    nrm = np.cross(P[T[:, 1]] - A_, P[T[:, 2]] - A_)
    area = np.linalg.norm(nrm, axis=1)
    ok = area > 1e-12
    n = nrm[ok] / area[ok][:, None]
    w = area[ok]
    C = (n * w[:, None]).T @ n
    ev, evec = np.linalg.eigh(C)
    a = evec[:, -1]
    if spec[1] == 'rotor' and a[2] < 0:
        a = -a
    if spec[1] == 'rotor':   # 主旋翼轴只前后倾（真机桨轴前倾 3～5°），不往左右歪：桨叶静止下垂量得不准的横向分量去掉
        a = np.array([a[0], 0.0, a[2]])
        a /= np.linalg.norm(a)
    if spec[1] == 'trotor' and a[1] < 0:
        a = -a
    cen = (P[T].mean(axis=1) * area[:, None]).sum(0) / max(area.sum(), 1e-12)
    if extra.get('a') is not None:
        a = todir(extra['a'])
    if extra.get('p') is not None:
        cen = toweb(extra['p'])
    d_ = P[np.unique(T.reshape(-1))] - cen
    rad = float(np.linalg.norm(d_ - np.outer(d_ @ a, a), axis=1).max())
    print('  %s：支点 %s、转轴 %s、半径 %.2f 米（%d 个三角形）' % (g, np.round(cen, 3), np.round(a, 3), rad, len(T)))
    return {'n': spec[1], 'g': g, 'p': [round(float(x), 4) for x in cen], 'a': [round(float(x), 4) for x in a]}


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
    elif k in ('slat', 'lev'):   # 前缘襟翼、LEVCON（苏-57 翼根可动边条）：绕自己的后缘转
        a, b = e0[np.argmin(e0[:, 0])], e1[np.argmin(e1[:, 0])]
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
    elif k in ('slat', 'lev'):   # 前缘往下
        probe, want = Q[np.argmax(Q[:, 0])], A.DOWN
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
            if 'a' in e and 'b' in e and e.get('k') not in ('kf',):
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
    if EXTRA.get('eye') is not None:   # 原模型座舱：眼位按座椅量的
        A.PIT[key] = [list(EXTRA['eye'])]
    if EXTRA.get('scr'):
        A.PITSCR[key] = EXTRA['scr']
    for i in S['ids']:
        X.ALIAS[i] = key
    if S.get('lift'):   # 没有放下的起落架：机腹最低点离地多高（米），游戏里用零件拼的起落架
        X.LIFT[key] = S['lift']
    if S.get('gunsplit'):   # 直升机机头炮塔：按连通块拆出来跟着瞄准转（同 air2glb.GUNSPLIT，网页版坐标）
        X.GUNSPLIT[key] = S['gunsplit']
    if S.get('stub'):   # 直升机短翼：挂点挂在这里（同 air2glb.HELI_STUB，游戏坐标：格）
        X.HELI_STUB[key] = S['stub']
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
    if '--pose' in argv:   # 摆几个姿势写成 GLB（tools/models/air_pose.py），给 Blender 渲染核对起落架收放、舵面、喷口
        import air_pose as AP
        pdir = argv[argv.index('--pose') + 1]
        os.makedirs(pdir, exist_ok=True)
        POSES = {'down': {'gear': 1, 'thr': 80}, 'g07': {'gear': 0.7}, 'g04': {'gear': 0.4}, 'g015': {'gear': 0.15}, 'g005': {'gear': 0.05},
                 'up': {'gear': 0, 'thr': 125, 'pit': 1},
                 'ctrl': {'gear': 1, 'thr': 125, 'pit': 1, 'rol': 1, 'yaw': 1, 'flap': 1, 'can': 1}}
        for nm, c in POSES.items():
            B.write_glb(S.get('kname', key), meta2, binb2, info, AP.pose(out, info, c), os.path.join(pdir, '%s_%s.glb' % (key, nm)), prefix='A_')
        print('  姿势：' + pdir)
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
