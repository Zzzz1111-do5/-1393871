# 弹药栏的写实弹种图（用户 11-27「我需要你完全按照战雷的风格去做设计 而不是这种卡通风格……更拟真」）：Blender 无界面渲染
#   /opt/blender/blender -b --factory-startup -P tools/models/ammopics_blender.py -- <输出目录> [only=m829a3,of26] [samples=28] [ss=8] [threads=2]
#   每一发都按真弹的结构程序化建模（不用网上的模型）：回转体（弹体、弹托、药筒、引信……按毫米写的外形轮廓车出来）+ 非回转件
#     （尾翼、弹托瓣的缝、折叠翼、弹链），涂装照实物（北约：穿甲类黑、含高爆黄字；苏 / 俄：灰弹体黑模板字、125 毫米棕色可燃筒……）。
#   摆法（同一套，整排像一张弹药识别图）：横放、弹头朝右，正交相机略俯 6°；同一口径的弹一个毫米 → 像素比例（真的长短粗细）：
#     比例 = 86 像素 ÷ 这一口径最长的「可见段」（带药筒的：露出药筒的弹丸 + 0.25 倍药筒长；125 毫米分装弹、导弹：整发），
#     弹尖压在图的 x = 90（1 倍像素），药筒往左伸出图外（打包时左边 16 像素渐隐，tools/models/ammopics.py）；
#     机枪弹链、机炮弹、导弹、工具（烟幕弹、扳手、望远镜……）各自按框塞满（太长的导弹、火箭只画前段，同药筒那样往左伸出去）。
#   光：大柔光箱左上 45° 主光、右前补光（三成）、后上方轮廓光（黑弹托、黑弹体靠它从暗底上分出来），没有地面、没有投影；
#     AgX；透明背景。输出 <输出目录>/<名字>.png（显示尺寸的 ss 倍）+ meta.json（每张多大、要不要左边渐隐）
#   尺寸、外形依据：厂家资料（诺格 M829A3 / M830A1、GD-OTS M1028 / M456A2）、FAS 剖面图、乌克兰弹药识别手册、NGIC 苏式弹药图、实物照片；
#     没找到实物的（DM12、BR-412D、3BM60、中国 125 毫米弹的颜色……）按同族、按涂装通则推（注释里写了）
import bpy, bmesh, json, math, os, sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
pos = [a for a in argv if '=' not in a]
opt = dict(a.split('=', 1) for a in argv if '=' in a)
OUT = pos[0] if pos else '/tmp/ammopics'
ONLY = set(opt['only'].split(',')) if opt.get('only') else None
SAMPLES = int(opt.get('samples', 28))
SS = int(opt.get('ss', 8))
THREADS = int(opt.get('threads', 2))
ELEV = math.radians(float(opt.get('elev', 6)))
MM = 0.001
os.makedirs(OUT, exist_ok=True)

# 图的大小（1 倍像素，同 WtTank.lua）：弹种 / 机枪格 96 × 60 里 x 0～92、y 12～46 一块；工具格 60 × 60 里 56 × 34
IMG = {'ammo': (92, 34), 'tool': (56, 34)}
NOSE_PX, LEFT_PX = 90, 4   # 弹尖压在 x = 90，可见段从 x = 4 起


def lin(c):
    """sRGB 0～255 → Blender 线性"""
    out = []
    for v in c[:3]:
        v = v / 255.0
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


################################################################ 场景
MATS = {}
FONT = None
CREATED = []


def reset():
    global FONT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()   # 换了场景，原来的材质、字体都没了
    FONT = None
    CREATED.clear()
    s = bpy.context.scene
    s.render.engine = 'CYCLES'
    s.cycles.device = 'CPU'
    s.cycles.samples = SAMPLES
    s.cycles.use_adaptive_sampling = True
    s.cycles.use_denoising = False   # 渲大图再缩：16 个像素平均一个，比降噪干净
    s.cycles.max_bounces = 6
    s.cycles.glossy_bounces = 4
    s.cycles.transparent_max_bounces = 4
    s.cycles.blur_glossy = 0.6          # 金属面上的噪点少一些
    s.cycles.caustics_reflective = False
    s.cycles.caustics_refractive = False
    s.render.threads_mode = 'FIXED'
    s.render.threads = THREADS
    s.render.film_transparent = True
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    s.render.image_settings.color_depth = '8'
    vt = [v.identifier for v in s.view_settings.bl_rna.properties['view_transform'].enum_items]
    s.view_settings.view_transform = 'AgX' if 'AgX' in vt else 'Filmic'
    try:
        s.view_settings.look = opt.get('look', 'AgX - Medium High Contrast') if 'AgX' in vt else 'Medium Contrast'
    except Exception:
        pass
    # 环境：上亮下暗的影棚（金属要有东西可反），画面上看不见（透明背景）
    w = bpy.data.worlds.new('W')
    s.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes['Background']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])
    nt.links.new(sep.outputs['Z'], ramp.inputs['Fac'])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.035, 0.035, 0.036, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.32, 0.33, 0.34, 1)
    nt.links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = float(opt.get('world', 0.3))
    return s


################################################################ 材质
def mat(name, col, metal=0.0, rough=0.5, noise=0.04, fiber=False, bump=0.0):
    """Principled：col 是 sRGB；noise 颜色 / 粗糙度的细微起伏（不要纯平的塑料感）；fiber 可燃药筒的纤维纹"""
    if metal >= 0.5 and noise == 0.04:   # 金属：起伏小一点（大了像撒了沙）
        noise = 0.012
    key = (name, tuple(col), metal, rough, noise, fiber, bump)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    base = lin(col)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if noise > 0 or fiber:
        tc = nt.nodes.new('ShaderNodeTexCoord')
        mp = nt.nodes.new('ShaderNodeMapping')
        nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
        mp.inputs['Scale'].default_value = (60, 900, 900) if fiber else (260, 260, 260)   # 纤维纹顺着弹轴拉长
        nz = nt.nodes.new('ShaderNodeTexNoise')
        nz.inputs['Scale'].default_value = 1.0
        nz.inputs['Detail'].default_value = 6.0
        nt.links.new(mp.outputs['Vector'], nz.inputs['Vector'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        k = noise if noise > 0 else 0.05
        mix.inputs[6].default_value = tuple(max(0, c * (1 - k * 2)) for c in base[:3]) + (1,)
        mix.inputs[7].default_value = tuple(min(1, c * (1 + k * 2)) for c in base[:3]) + (1,)
        nt.links.new(nz.outputs['Fac'], mix.inputs['Factor'])
        nt.links.new(mix.outputs[2], p.inputs['Base Color'])
        rr = nt.nodes.new('ShaderNodeMapRange')
        rr.inputs['To Min'].default_value = max(0.02, rough - 0.08)
        rr.inputs['To Max'].default_value = min(1.0, rough + 0.08)
        nt.links.new(nz.outputs['Fac'], rr.inputs['Value'])
        nt.links.new(rr.outputs['Result'], p.inputs['Roughness'])
        if bump > 0 or fiber:
            bp = nt.nodes.new('ShaderNodeBump')
            bp.inputs['Strength'].default_value = bump if bump > 0 else 0.08
            bp.inputs['Distance'].default_value = 0.0004
            nt.links.new(nz.outputs['Fac'], bp.inputs['Height'])
            nt.links.new(bp.outputs['Normal'], p.inputs['Normal'])
    else:
        p.inputs['Base Color'].default_value = base
    MATS[key] = m
    return m


class M:
    """常用材质（颜色照实物照片取，sRGB）"""


def init_mats():
    M.black_paint = mat('BlackPaint', (24, 24, 24), rough=0.42)
    M.black_sabot = mat('BlackSabot', (26, 26, 26), rough=0.35)          # 黑色复合 / 铝弹托（#1A1A1A，不要纯黑）
    M.us_comb = mat('UsComb', (150, 158, 142), rough=0.85, fiber=True)   # 美 120 可燃药筒：浅灰略带青绿、哑光纸感
    M.tan_comb = mat('TanComb', (160, 140, 100), rough=0.85, fiber=True) # 152 毫米可燃药筒：土黄
    M.seal = mat('Seal', (226, 226, 214), rough=0.6, noise=0.02)          # 药筒口白色密封环
    M.rubber = mat('Rubber', (16, 16, 16), rough=0.75)
    M.stub = mat('Stub', (116, 104, 74), metal=1.0, rough=0.55)          # 钢底座：暗青铜 / 橄榄灰的磷化钢
    M.du = mat('DU', (66, 68, 70), metal=0.85, rough=0.45)               # 贫铀杆：深灰近黑
    M.wha = mat('WHA', (150, 152, 156), metal=1.0, rough=0.35)           # 钨合金杆：钢灰
    M.steel = mat('Steel', (196, 198, 202), metal=1.0, rough=0.24)      # 钢尖、亮钢件
    M.steel_dk = mat('SteelDk', (120, 122, 126), metal=1.0, rough=0.38)  # 探针、开关
    M.alu = mat('Alu', (208, 208, 212), metal=1.0, rough=0.3)
    M.gold = mat('Gold', (214, 172, 80), metal=1.0, rough=0.25)
    M.copper = mat('Copper', (190, 116, 76), metal=1.0, rough=0.3)       # 铜弹带
    M.gilding = mat('Gilding', (204, 132, 90), metal=1.0, rough=0.26)    # 枪弹的铜被甲
    M.brass = mat('Brass', (214, 178, 102), metal=1.0, rough=0.3)
    M.od = mat('OD', (88, 92, 58), rough=0.55)                           # 美军橄榄绿漆
    M.yellow = mat('Yellow', (232, 190, 40), rough=0.5, noise=0.01)
    M.yellow_body = mat('YellowBody', (196, 160, 48), rough=0.45)        # 黄色弹体（机炮榴弹）
    M.white = mat('White', (232, 232, 226), rough=0.55, noise=0.01)
    M.lt_green = mat('LtGreen', (140, 190, 110), rough=0.5, noise=0.01)  # 发烟弹的浅绿环
    M.ru_grey = mat('RuGrey', (150, 160, 160), rough=0.5)                # 苏 / 俄弹丸：浅灰
    M.ru_gg = mat('RuGG', (88, 102, 90), rough=0.5)                    # 灰绿
    M.ru_dkgrey = mat('RuDkGrey', (92, 100, 100), rough=0.5)
    M.ru_brown = mat('RuBrown', (152, 78, 34), rough=0.5, fiber=True)    # 125 毫米可燃筒：橙褐
    M.ru_tan = mat('RuTan', (176, 120, 72), rough=0.6, fiber=True)       # 老一点的可燃筒：浅褐
    M.ru_sabot = mat('RuSabot', (192, 196, 196), rough=0.42)             # 浅灰漆的铝弹托
    M.ru_rod = mat('RuRod', (128, 138, 142), rough=0.45)                 # 灰漆钢套杆
    M.anod = mat('Anod', (168, 178, 156), metal=1.0, rough=0.35)         # 阳极氧化尾管：浅绿金属色
    M.redbrown = mat('RedBrown', (150, 70, 40), rough=0.5)               # 尾翼
    M.obtur = mat('Obtur', (176, 88, 42), rough=0.42)                    # 橙褐塑料闭气环
    M.ru_case = mat('RuCase', (112, 118, 96), metal=0.6, rough=0.42)     # 苏式钢药筒：灰绿漆
    M.us_case = mat('UsCase', (108, 104, 86), metal=0.85, rough=0.5)     # 美 105 钢药筒：磷化灰橄榄
    M.missile = mat('Missile', (112, 108, 72), rough=0.5)                # 导弹：橄榄 / 卡其
    M.missile_nose = mat('MissileNose', (84, 82, 52), rough=0.45)
    M.mgreen = mat('MGreen', (74, 92, 62), rough=0.5)                    # 苏式导弹的绿
    M.band_black = mat('BandBlack', (22, 22, 22), rough=0.5, noise=0.01)
    M.band_purple = mat('BandPurple', (112, 64, 140), rough=0.5, noise=0.01)
    M.band_green = mat('BandGreen', (44, 124, 64), rough=0.5, noise=0.01)
    M.band_red = mat('BandRed', (176, 42, 36), rough=0.5, noise=0.01)
    M.red_tip = mat('RedTip', (190, 46, 34), rough=0.45, noise=0.01)
    M.glass = mat('Glass', (20, 30, 34), rough=0.04, noise=0)
    M.red_paint = mat('RedPaint', (176, 30, 26), rough=0.35)
    M.chrome = mat('Chrome', (222, 224, 228), metal=1.0, rough=0.16)
    M.satin = mat('Satin', (206, 208, 212), metal=1.0, rough=0.36)       # 工具钢（缎面）
    M.plastic_blk = mat('PlasticBlk', (30, 30, 30), rough=0.45)
    M.rubber_od = mat('RubberOD', (62, 68, 50), rough=0.72)              # 望远镜、测距仪的橄榄色橡胶
    M.cn_olive = mat('CnOlive', (96, 104, 74), rough=0.5)                # 中国弹丸：橄榄灰（没查到实物彩照，△）
    M.label = mat('Label', (210, 208, 196), rough=0.6, noise=0.02)


################################################################ 几何
def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    CREATED.append(ob)
    return ob


def rot_x(v, a):
    x, y, z = v
    c, s = math.cos(a), math.sin(a)
    return (x, y * c - z * s, y * s + z * c)


def finish(bm, name, m, sharp=32, smooth=True):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    if bm.faces and all(e.is_manifold for e in bm.edges):   # 封闭的：法线一律朝外（布尔要用）
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
        try:
            me.set_sharp_from_angle(angle=math.radians(sharp))
        except Exception:
            pass
    ob = bpy.data.objects.new(name, me)
    me.materials.append(m)
    return link(ob)


def mark():
    return len(CREATED)


def xform(i0, mx):
    """从第 i0 个起新建的物体都乘上 mx（摆位置、整组转）"""
    for ob in CREATED[i0:]:
        ob.matrix_world = mx @ ob.matrix_world


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x * MM, y * MM, z * MM))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def lathe(prof, m, seg=96, a0=None, a1=None, name='L', sharp=32, dr=0.0):
    """回转体：prof = [(x 毫米, 半径 毫米), …] 从后往前（弹头在 +X）；a0 / a1（度，0 = 朝镜头那面、往上为正）只车一段弧（弹托缝、色条）"""
    bm = bmesh.new()
    part = a0 is not None
    if part:
        n = max(2, int(seg * (a1 - a0) / 360) + 1)
        angs = [math.radians(a0 + (a1 - a0) * i / (n - 1)) for i in range(n)]
    else:
        n = seg
        angs = [2 * math.pi * i / seg for i in range(seg)]
    pts = []
    for x, r in prof:
        if pts and abs(pts[-1][0] - x) < 1e-9 and abs(pts[-1][1] - r) < 1e-9:
            continue
        pts.append((x, r))
    rings = []
    for x, r in pts:
        r = r + dr
        if r <= 1e-6 and not part:
            rings.append([bm.verts.new((x * MM, 0, 0))])
        else:   # 角度 0 朝镜头（−Y），往上（+Z）为正
            rr = max(r, 1e-4) * MM
            rings.append([bm.verts.new((x * MM, -rr * math.cos(a), rr * math.sin(a))) for a in angs])
    for A, B in zip(rings, rings[1:]):
        if len(A) == 1 and len(B) == 1:
            continue
        if len(A) == 1:
            for i in range(n):
                bm.faces.new((A[0], B[i], B[(i + 1) % n]))
        elif len(B) == 1:
            for i in range(n):
                bm.faces.new((A[(i + 1) % n], A[i], B[0]))
        else:
            for i in (range(n - 1) if part else range(n)):
                j = (i + 1) % n
                try:
                    bm.faces.new((A[j], A[i], B[i], B[j]))
                except ValueError:
                    pass
    if not part:   # 两头封口
        for ring in (rings[0], rings[-1]):
            if len(ring) > 2:
                try:
                    bm.faces.new(ring)
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, name, m, sharp=sharp)


def band(x0, x1, r, m, lift=0.3):
    """色环 / 色带：贴在弹体外面一点点的一圈"""
    return lathe([(x0, r + lift), (x1, r + lift)], m, name='band')


def plate(poly, t, m, ang=0.0, name='P'):
    """平板（尾翼、弹链的板）：poly 是 (x, r) 毫米的轮廓（翼平面里：x 沿弹轴、r 径向），厚 t 毫米，绕弹轴转 ang 度（0 = 竖着朝上）"""
    bm = bmesh.new()
    a = math.radians(ang)
    f, b = [], []
    for x, r in poly:
        f.append(bm.verts.new(rot_x((x * MM, -t / 2 * MM, r * MM), a)))
        b.append(bm.verts.new(rot_x((x * MM, t / 2 * MM, r * MM), a)))
    n = len(poly)
    bm.faces.new(f)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((f[i], f[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, name, m, sharp=30)


def fins(n, poly, t, m, rot0=45.0, name='F'):
    return [plate(poly, t, m, rot0 + 360.0 * i / n, name) for i in range(n)]


def sleeve(x0, x1, r_in, r_out, a0, a1, m, name='S', seg=96):
    """一段弧形的壳（折叠翼、带缺口的环）：x0～x1、半径 r_in～r_out、角度 a0～a1（度，0 朝镜头）"""
    bm = bmesh.new()
    n = max(2, int(seg * (a1 - a0) / 360) + 1)
    angs = [math.radians(a0 + (a1 - a0) * i / (n - 1)) for i in range(n)]

    def v(x, r, a):
        return bm.verts.new((x * MM, -r * MM * math.cos(a), r * MM * math.sin(a)))
    o0 = [v(x0, r_out, a) for a in angs]
    o1 = [v(x1, r_out, a) for a in angs]
    i0 = [v(x0, r_in, a) for a in angs]
    i1 = [v(x1, r_in, a) for a in angs]
    for k in range(n - 1):
        bm.faces.new((o0[k], o0[k + 1], o1[k + 1], o1[k]))
        bm.faces.new((i0[k + 1], i0[k], i1[k], i1[k + 1]))
        bm.faces.new((o0[k + 1], o0[k], i0[k], i0[k + 1]))
        bm.faces.new((o1[k], o1[k + 1], i1[k + 1], i1[k]))
    bm.faces.new((o0[0], o1[0], i1[0], i0[0]))
    bm.faces.new((o1[-1], o0[-1], i0[-1], i1[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, name, m, sharp=30)


def box(c, size, m, rot=(0, 0, 0), name='B', bevel=0.0):
    """方块（毫米）：中心 c、尺寸 size、绕 XYZ 转（度）；bevel 倒角（毫米）"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] * MM, v.co.y * size[1] * MM, v.co.z * size[2] * MM))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=bevel * MM, segments=3, affect='EDGES', profile=0.5)
    ob = finish(bm, name, m, sharp=35)
    ob.matrix_world = T(*c) @ (R(rot[2], 'Z') @ R(rot[1], 'Y') @ R(rot[0], 'X'))
    return ob


def cyl(c, r, h, m, axis='Y', seg=64, name='C', bevel=0.0):
    """圆柱（毫米）：中心 c、半径 r、长 h，轴向 axis"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r * MM, radius2=r * MM, depth=h * MM)
    if bevel > 0:
        cap = [e for e in bm.edges if not e.is_manifold or all(abs(abs(v.co.z) - h * MM / 2) < 1e-7 for v in e.verts)]
        bmesh.ops.bevel(bm, geom=cap, offset=bevel * MM, segments=3, affect='EDGES', profile=0.5)
    ob = finish(bm, name, m, sharp=40)
    rot = {'X': R(90, 'Y'), 'Y': R(90, 'X'), 'Z': Matrix.Identity(4)}[axis]
    ob.matrix_world = T(*c) @ rot
    return ob


def curve_to_mesh(ob, m):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    CREATED.remove(ob)
    bpy.data.objects.remove(ob)
    ob2 = bpy.data.objects.new('CurveMesh', me)
    if not me.materials:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return link(ob2)


def tube(pts, r, m, name='Tube'):
    """沿折线（毫米）的圆管：软管、电线"""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    sp = cu.splines.new('NURBS')
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        p.co = (q[0] * MM, q[1] * MM, q[2] * MM, 1)
    sp.use_endpoint_u = True
    sp.order_u = min(4, len(pts))
    cu.bevel_depth = r * MM
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    ob = bpy.data.objects.new(name, cu)
    link(ob)
    return curve_to_mesh(ob, m)


def font():
    global FONT
    if FONT is None:
        FONT = False
        for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'):
            if os.path.exists(p):
                FONT = bpy.data.fonts.load(p)
                break
    return FONT or None


def stencil(txt, x, r, h, m, ang=0.0, narrow=0.82, spacing=1.15):
    """模板字：照实物「绕着弹体一圈写」（弹立起来时字是横的）——横放、弹头朝右时字竖着、从上往下读，字头朝弹头。
       x = 这几行字的中心在弹轴上的位置，r 弹体半径，h 字高（毫米，约 0.1 倍口径），ang 字中心在圆周上的角度（0 朝镜头）"""
    cu = bpy.data.curves.new('T', 'FONT')
    cu.body = txt
    f = font()
    if f:
        cu.font = f
    cu.size = h * 1.37 * MM   # 字号 → 大写字母的高（DejaVu 大写约 0.73 倍字号）
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.space_line = spacing
    ob = bpy.data.objects.new('T', cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    rr = r + 0.3
    a_c = ELEV + math.radians(ang)
    for v in me.vertices:
        tx, ty = v.co.x / MM * narrow, v.co.y / MM   # 字的横（沿圆周往下）、竖（朝弹头）
        a = a_c - tx / rr
        v.co = Vector(((x + ty) * MM, -rr * MM * math.cos(a), rr * MM * math.sin(a)))
    me.update()
    ob2 = bpy.data.objects.new('Txt', me)
    me.materials.append(m)
    return link(ob2)


################################################################ 共用的部件
def case_us120(mouth=570, seal=True):
    """北约 120 毫米：钢底座（暗青铜）+ 黑胶圈 + 浅灰可燃药筒（略带青绿）+ 口部白色密封环（M829A3 / M830A1 厂家图）"""
    lathe([(0, 0), (0, 70), (2, 76), (20, 76), (22, 73), (25, 73), (27, 75), (56, 75), (58, 73)], M.stub, name='stub')
    lathe([(58, 72.6), (60, 73.6), (70, 73.6), (72, 72.4)], M.rubber, name='rubber')
    lathe([(72, 72.2), (440, 70.6), (478, 66.5), (500, 64.2)] + ([] if seal else [(545, 63.8), (545, 40)]), M.us_comb, name='comb')
    if seal:
        lathe([(500, 64.0), (502, 64.6), (mouth - 2, 64.4), (mouth, 62), (mouth, 30)], M.seal, name='seal')


def case_rim(rim_r, body_r0, body_r1, shoulder_x, neck_r, neck_x, mouth, m, name='case'):
    """整装弹的金属药筒（带底缘）：底缘、筒身（略锥）、肩、颈、口"""
    lathe([(0, 0), (0, rim_r - 2), (1.5, rim_r), (8, rim_r), (9, body_r0 - 1.5), (11, body_r0), (shoulder_x, body_r1),
           (neck_x, neck_r), (mouth - 1.5, neck_r), (mouth, neck_r - 1.2), (mouth, neck_r - 6)], m, name=name)


def case_105(m):
    case_rim(74, 67.5, 63.5, 520, 57, 548, 617, m)


def case_100(m):
    case_rim(71, 66, 62, 626, 53.5, 652, 695, m)


def seams(prof, angs, m, w=1.4):
    """弹托的瓣缝：沿外形轮廓的细黑线（比表面高一点点）"""
    for a in angs:
        lathe(prof, m, a0=a - w / 2, a1=a + w / 2, dr=0.25, name='seam')


def lens(x, r):
    """镜片：镜筒口上一片微凸的深色镀膜玻璃"""
    lathe([(x - 2, 0), (x - 2, r), (x + 0.3, r), (x + 1.0, r * 0.7), (x + 1.4, 0)], M.glass, name='lens')


def tip(x0, x1, r, m):
    """钢尖：一小段圆柱接卵形"""
    L = x1 - x0
    lathe([(x0, r), (x0 + L * 0.3, r), (x0 + L * 0.55, r * 0.84), (x0 + L * 0.78, r * 0.52), (x1 - L * 0.04, r * 0.12), (x1, 0)], m, name='tip')


def apfsds_spool(rod_x1, tip_x, nose_x, rod_r=12.5, rod_m=None, sabot_x=570, disc_x=748, disc_r=57):
    """北约 120 尾翼稳定脱壳穿甲弹（M829A3 那种线轴形黑弹托：细腰、前端外扩成带缺口的圆盘；细长杆、钢尖）"""
    rod_m = rod_m or M.du
    prof = [(sabot_x - 6, 36), (sabot_x + 14, 34), (sabot_x + 30, 23.5), (disc_x - 50, 21.5), (disc_x - 26, 27),
            (disc_x - 12, 40), (disc_x - 4, 51), (disc_x, disc_r - 3)]
    lathe(prof, M.black_sabot, name='sabot')
    lathe([(disc_x, disc_r - 3), (disc_x + 1, disc_r - 1), (disc_x + 7, disc_r - 1), (disc_x + 7, 46), (disc_x + 13, 46),
           (disc_x + 15, 30), (disc_x + 18, 18), (disc_x + 20, rod_r + 2)], M.black_sabot, name='disc')
    for i in range(12):   # 圆盘前缘 12 个齿（缺口）
        a = i * 30.0 + 6
        sleeve(disc_x + 6.5, disc_x + 13, 45, disc_r - 1, a, a + 19, M.black_sabot, name='tooth')
    seams(prof, (24.0, 144.0, 264.0), M.band_black, w=1.2)
    lathe([(disc_x + 18, rod_r), (rod_x1, rod_r)], rod_m, name='rod')
    tip(rod_x1, nose_x, rod_r, M.steel)


def apfsds_105(rod_m, nose, ring_x=700, rod_x1=None, rod_r=11.0, mouth=617):
    """105 尾翼稳定脱壳穿甲弹（M900 / M833 / DM33）：三瓣铝弹托（黑）、口部尼龙闭气带（白）、前端钢定心环（三道剪切槽）、长杆、钢尖"""
    prof = [(mouth - 5, 52), (ring_x, 52)]
    lathe(prof, M.black_sabot, name='sabot')
    seams(prof, (26.0, 146.0, 266.0), M.band_black, w=1.2)
    band(mouth + 2, mouth + 16, 52, M.seal, lift=0.4)
    lathe([(ring_x, 51.5), (ring_x + 34, 51.5)], M.steel_dk, name='ring')
    for g in (8, 17, 26):
        lathe([(ring_x + g - 1, 51.6), (ring_x + g, 50.0), (ring_x + g + 1, 51.6)], M.band_black, name='groove')
    lathe([(ring_x + 34, 50), (ring_x + 38, 46), (ring_x + 62, 24), (ring_x + 70, rod_r + 2.5), (ring_x + 72, rod_r + 1)], M.black_sabot, name='front')
    rod_x1 = rod_x1 or (nose - 52)
    lathe([(ring_x + 70, rod_r), (rod_x1, rod_r)], rod_m, name='rod')
    tip(rod_x1, nose, rod_r, M.steel)


def apds(mouth, nose, m_sabot, txt=None, txt_m=None):
    """脱壳穿甲弹（M392A2 / DM13，英国 L52 那一族）：全口径的铝弹托（黑）包着碳化钨弹芯，前面露出弹芯的风帽"""
    prof = [(mouth - 5, 52), (mouth + 100, 52), (mouth + 108, 50.5), (mouth + 122, 43), (mouth + 133, 34), (mouth + 135, 30)]
    lathe(prof, m_sabot, name='sabot')
    seams(prof, (26.0, 146.0, 266.0), M.band_black, w=1.2)
    band(mouth + 3, mouth + 15, 52, M.seal, lift=0.4)
    L = nose - (mouth + 133)
    lathe([(mouth + 133, 26), (mouth + 133 + L * 0.3, 24), (mouth + 133 + L * 0.6, 18), (mouth + 133 + L * 0.85, 9), (nose - 2, 2.5), (nose, 0)], M.black_paint, name='cap')
    if txt:
        stencil(txt, mouth + 55, 52, 8, txt_m or M.white)


def heat_spike(mouth, r_body, body_x1, spike_x0, spike_r, spike_x1, nose, m_body, cal):
    """北约破甲弹（M456 / M830 / DM12）：全口径黑弹体、卵形头、细长钢探针、探针头的碰炸开关"""
    L = spike_x0 - body_x1
    lathe([(mouth - 10, r_body), (body_x1, r_body), (body_x1 + L * 0.25, r_body * 0.95), (body_x1 + L * 0.55, r_body * 0.82),
           (body_x1 + L * 0.8, r_body * 0.6), (spike_x0, r_body * 0.42)], m_body, name='body')
    lathe([(spike_x0 - 2, r_body * 0.42 + 1), (spike_x0 + 10, r_body * 0.42 + 1), (spike_x0 + 12, spike_r + 2)], M.steel_dk, name='sw1')
    lathe([(spike_x0 + 12, spike_r), (spike_x1, spike_r * 0.92)], M.steel_dk, name='spike')
    hr = spike_r * 1.55
    lathe([(spike_x1, spike_r * 0.92), (spike_x1, hr), (spike_x1 + 4, hr + 1), (nose - 18, hr + 1), (nose - 13, hr * 0.85),
           (nose - 6, hr * 0.5), (nose, 0)], M.steel, name='sw2')


################################################################ 每一发
ITEMS = {}


def item(name, fam=None, kind='ammo', case=None, nose=None, full=None, vis=None, dia=None):
    """登记一发：fam 口径（同一口径一个比例尺）；case 药筒长、nose 弹尖 x（毫米，带药筒的）；full 不带药筒的整发长；
       vis 不归口径的：只画前面这么长（毫米，太长的导弹 / 火箭），不给就整个塞进框；dia 最粗的地方（毫米，比例尺还要让它竖着放得下）"""
    def deco(fn):
        ITEMS[name] = dict(fn=fn, fam=fam, kind=kind, case=case, nose=nose, full=full, vis=vis, dia=dia)
        return fn
    return deco


# ======== 北约 120 毫米（M256 / Rh-120）：可燃药筒 570 毫米
@item('m829a3', fam='120', case=570, nose=982)
def _():   # 诺格资料：全长 982，弹丸 924；黑色线轴形复合弹托、贫铀杆、钢尖（尾翼在药筒里）
    case_us120()
    apfsds_spool(878, 905, 982)


@item('m830', fam='120', case=570, nose=982)
def _():   # FAS 剖面图：近全口径黑弹体、卵形头、细长钢探针 + 碰炸开关；黑底黄字
    case_us120()
    heat_spike(570, 58.5, 700, 790, 11.5, 952, 982, M.black_paint, 120)
    stencil('120MM HEAT-MP-T\nM830', 640, 58.5, 9, M.yellow)


@item('m830a1', fam='120', case=570, nose=981)
def _():   # 诺格资料：全长 981；黑色三瓣铝弹托（前端台阶），黑锥形弹头上两道银色近炸开关环、金色小尖
    case_us120()
    prof = [(560, 50), (724, 50), (726, 59), (808, 59), (811, 42)]
    lathe(prof, M.black_sabot, name='sabot')
    seams(prof, (30.0, 150.0, 270.0), M.band_black, w=1.2)
    lathe([(810, 36), (900, 21)], M.black_paint, name='cone1')
    lathe([(900, 21), (906, 20)], M.steel, name='ring1')
    lathe([(906, 20), (935, 13)], M.black_paint, name='cone2')
    lathe([(935, 13), (941, 11.8)], M.steel, name='ring2')
    lathe([(941, 11.8), (962, 6.5)], M.black_paint, name='cone3')
    lathe([(962, 6.5), (976, 2.5), (981, 0)], M.gold, name='tip')
    stencil('MPAT\nM830A1', 640, 50, 8, M.yellow)


@item('m1028', fam='120', case=570, nose=780)
def _():   # GD-OTS：全长 780；橄榄绿平头霰弹罐 + 白字，罐尾白色闭气环、暗青铜环
    case_us120(seal=False)
    lathe([(545, 63.6), (547, 64.2), (556, 64.2), (558, 63.2)], M.rubber, name='ring_dk')
    lathe([(558, 62.6), (568, 62.6)], M.white, name='obt')
    lathe([(568, 61.2), (580, 61.2)], M.stub, name='bronze')
    lathe([(580, 59.6), (774, 59.6), (777, 58.6), (780, 56), (780, 0)], M.od, name='can')
    stencil('CARTRIDGE, 120MM:\nCanister, M1028', 722, 59.6, 7.5, M.white, spacing=1.25)
    stencil('FB005840C-001', 632, 59.6, 6.0, M.white)


@item('jet120', fam='120', case=570, nose=990)
def _():   # 「金属射流弹」（游戏里的串联破甲弹）：M830 式黑弹体 + 带前级装药的粗探针，黄环 = 含高爆
    case_us120()
    lathe([(560, 58.5), (700, 58.5), (722, 56), (748, 49), (770, 39), (786, 28.5)], M.black_paint, name='body')
    band(688, 702, 58.5, M.yellow)
    lathe([(786, 27), (787, 25), (798, 25), (800, 16)], M.steel_dk, name='sw1')
    lathe([(800, 15), (900, 14.5)], M.steel_dk, name='probe')
    lathe([(900, 20), (904, 24), (944, 24), (950, 20), (952, 12)], M.black_paint, name='pre')   # 前级装药
    lathe([(950, 12), (972, 11), (972, 15), (980, 15), (985, 9), (990, 0)], M.steel, name='fz')
    stencil('120MM\nHEAT-T', 640, 58.5, 9, M.yellow)


@item('dm53', fam='120', case=570, nose=990)
def _():   # 豹 2A6：钨合金长杆（更长更细）、黑弹托（同北约动能弹「黑弹托白字」，△）
    case_us120()
    apfsds_spool(924, 945, 990, rod_r=11.5, rod_m=M.wha, disc_x=742, disc_r=58)


@item('dm33', fam='120', case=570, nose=950)
def _():   # 豹 2A4：钨合金杆比 DM53 短粗（△）
    case_us120()
    apfsds_spool(890, 908, 950, rod_r=13.5, rod_m=M.wha, disc_x=736, disc_r=58)


@item('dm12', fam='120', case=570, nose=982)
def _():   # DM12：M830 就是照它造的，外形相同；黑色系（没找到德军实物彩照，△）
    case_us120()
    heat_spike(570, 58.5, 700, 790, 11.5, 952, 982, M.black_paint, 120)
    stencil('DM12', 640, 58.5, 9, M.yellow)


# ======== 北约 105 毫米（M68 / L7）：整装弹，美军 M148 钢药筒（灰橄榄磷化），德军黄铜药筒（△）
@item('m900', fam='105', case=617, nose=1003)
def _():   # bulletpicker：「round is black with white markings」；三瓣铝弹托、钢定心环三道剪切槽、尼龙闭气带、贫铀杆钢尖
    case_105(M.us_case)
    apfsds_105(M.du, 1003)
    stencil('M900', 660, 52, 8, M.white)


@item('m833', fam='105', case=617, nose=955)
def _():   # M60A3：贫铀杆，比 M900 短（按同族，△）
    case_105(M.us_case)
    apfsds_105(M.du, 955, ring_x=690)
    stencil('M833', 655, 52, 8, M.white)


@item('m392', fam='105', case=617, nose=862)
def _():   # M392A2 脱壳穿甲弹：黑，白字
    case_105(M.us_case)
    apds(617, 862, M.black_sabot, 'M392A2')


@item('m456', fam='105', case=617, nose=1006)
def _():   # GD-OTS M456A2：全长 1005.8；近全口径黑弹体、细长探针、压电鼻帽、塑料闭气环；黑底黄字
    case_105(M.us_case)
    band(622, 636, 52.4, M.seal, lift=0.3)
    heat_spike(617, 52.4, 690, 788, 10.5, 975, 1006, M.black_paint, 105)
    stencil('105MM HEAT-T\nM456A2', 662, 52.4, 8.5, M.yellow)


@item('jet105', fam='105', case=617, nose=1010)
def _():   # 「金属射流弹」105：M456 式 + 带前级装药的粗探针、黄环
    case_105(M.us_case)
    band(622, 636, 52.4, M.seal, lift=0.3)
    lathe([(607, 52.4), (690, 52.4), (712, 50), (740, 44), (765, 33), (782, 22), (788, 18)], M.black_paint, name='body')
    band(676, 688, 52.4, M.yellow)
    lathe([(788, 14), (900, 13.5)], M.steel_dk, name='probe')
    lathe([(900, 18), (904, 21), (946, 21), (952, 16), (954, 11)], M.black_paint, name='pre')
    lathe([(952, 11), (990, 10), (990, 14), (998, 14), (1004, 8), (1010, 0)], M.steel, name='fz')
    stencil('105MM\nHEAT-T', 662, 52.4, 8.5, M.yellow)


@item('dm13', fam='105', case=617, nose=870)
def _():   # 豹 1：DM13 脱壳穿甲弹（L52 那一族），黄铜药筒（△）
    case_105(M.brass)
    apds(617, 870, M.black_sabot, 'DM13')


@item('dm33l7', fam='105', case=617, nose=995)
def _():   # 豹 1A5：DM33（105）尾翼稳定脱壳穿甲弹，钨合金杆，黄铜药筒（△）
    case_105(M.brass)
    apfsds_105(M.wha, 995, ring_x=698, rod_r=12)
    stencil('DM33', 660, 52, 8, M.white)


@item('dm12h', fam='105', case=617, nose=1006)
def _():   # 豹 1：DM12（105）破甲弹 = M456 的许可生产型，外形同 M456；黑底黄字，黄铜药筒（△）
    case_105(M.brass)
    band(622, 636, 52.4, M.seal, lift=0.3)
    heat_spike(617, 52.4, 690, 788, 10.5, 975, 1006, M.black_paint, 105)
    stencil('DM12', 662, 52.4, 8.5, M.yellow)


# ======== 苏 / 俄 / 中 125 毫米（分装：只画弹丸；穿甲弹画装在棕色可燃筒里的样子）
@item('bm42', fam='125', full=621)
def _():   # 3BM42「芒果」（BM44 装填组件，621）：棕色可燃筒（白、绿色环，黑字「БМ44 125-Д-81」），露出灰色弹托前缘和钢套长杆
    lathe([(0, 0), (0, 58), (3, 62.5), (390, 62.5), (390, 40)], M.ru_brown, name='case')
    band(52, 80, 62.5, M.band_green)
    band(96, 108, 62.5, M.white)
    stencil('БМ44\n125-Д-81', 250, 62.5, 12, M.band_black, spacing=1.2)
    lathe([(390, 62.9), (399, 62.9), (399, 45)], M.band_black, name='obt')
    lathe([(399, 63.6), (438, 63.6), (440, 61), (444, 46), (450, 27), (455, 17)], M.ru_sabot, name='sabot')
    seams([(399, 63.6), (438, 63.6), (440, 61), (444, 46)], (35.0, 155.0, 275.0), M.band_black, w=1.4)
    lathe([(454, 13.5), (588, 13.5)], M.ru_rod, name='rod')
    tip(588, 621, 13.5, M.ru_rod)
    stencil('125', 530, 13.5, 8, M.band_black)


@item('bm60', fam='125', full=735)
def _():   # 3BM60「铅-2」（3VBM23，735）：按同代展品画（△）——棕色可燃筒（紫环），露出大号多瓣浅灰弹托、细长弹头，弹头上黑字「125」
    lathe([(0, 0), (0, 58), (3, 62.5), (378, 62.5), (378, 40)], M.ru_brown, name='case')
    band(60, 90, 62.5, M.band_purple)
    stencil('125-2А46М', 225, 62.5, 11, M.band_black)
    lathe([(378, 62.9), (394, 62.9), (394, 45)], M.white, name='wb')
    lathe([(394, 62.9), (410, 62.9), (410, 45)], M.band_black, name='bb')
    prof = [(410, 63.5), (448, 63.5), (454, 52), (468, 39), (520, 36), (545, 40), (565, 48), (580, 54), (588, 54.5), (590, 48), (593, 30), (596, 17)]
    lathe(prof, M.ru_sabot, name='sabot')
    seams(prof[:-2], (45.0, 135.0, 225.0, 315.0), M.band_black, w=1.6)
    lathe([(595, 16), (603, 15), (603, 12)], M.ru_sabot, name='collar')
    lathe([(602, 11.8), (712, 11.2)], M.ru_sabot, name='rod')
    tip(712, 735, 11.2, M.ru_sabot)
    stencil('125', 655, 11.8, 8, M.band_black)


@item('bm22', fam='125', full=610)
def _():   # 3BM22「别针」（BM23 装填组件，610）：浅褐可燃筒、红环、黑字「БМ23 125-Д-81」；灰绿锥形弹托前缘 + 弹头（乌克兰识别手册照片）
    lathe([(0, 0), (0, 58), (3, 62.5), (440, 62.5), (440, 40)], M.ru_tan, name='case')
    band(18, 62, 62.5, M.band_red)
    stencil('БМ23\n125-Д-81', 270, 62.5, 12, M.band_black, spacing=1.2)
    lathe([(440, 61), (448, 59), (500, 24), (506, 20)], M.ru_gg, name='sabot')
    lathe([(505, 17), (556, 16.2)], M.ru_gg, name='body')
    lathe([(556, 16.2), (580, 12.5), (600, 5), (610, 0)], M.ru_gg, name='nose')


@item('bm15', fam='125', full=600)
def _():   # 3BM15（BM18 装填组件）：钢弹体 + 碳化钨芯；褐色可燃筒、红色标记（乌克兰识别手册照片），灰色弹头
    lathe([(0, 0), (0, 58), (3, 62.5), (430, 62.5), (430, 40)], M.ru_brown, name='case')
    band(20, 58, 62.5, M.band_red)
    stencil('БМ18\n125-Д-81', 265, 62.5, 12, M.band_black, spacing=1.2)
    lathe([(430, 61), (438, 58), (478, 30), (486, 22)], M.ru_grey, name='sabot')
    lathe([(485, 19), (552, 18)], M.ru_grey, name='body')
    lathe([(552, 18), (575, 13), (592, 5), (600, 0)], M.ru_grey, name='nose')


@item('dtc10', fam='125', full=640)
def _():   # DTC10-125（99A）：外形照苏式 125 穿甲弹的装填形态，颜色没查到（△）——浅褐可燃筒、白环，灰弹托前缘、深灰钨合金杆
    lathe([(0, 0), (0, 58), (3, 62.5), (402, 62.5), (402, 40)], M.ru_tan, name='case')
    band(70, 86, 62.5, M.white)
    lathe([(402, 62.9), (411, 62.9), (411, 45)], M.band_black, name='obt')
    lathe([(411, 63.6), (446, 63.6), (448, 61), (452, 46), (458, 27), (463, 16)], M.ru_sabot, name='sabot')
    seams([(411, 63.6), (446, 63.6), (448, 61), (452, 46)], (35.0, 155.0, 275.0), M.band_black, w=1.4)
    lathe([(462, 12.5), (606, 12.5)], M.wha, name='rod')
    tip(606, 640, 12.5, M.steel)


def heatfs125(body_m, L=660, tandem=False, txt=None, txt2=None, fin_m=None):
    """125 尾翼稳定破甲弹（3BK18M，乌克兰识别手册照片）：钢尾管 + 折叠尾翼、后环，弹体两道凸起定心带，
       前锥接 V-15 细长引信（小金属尖）；tandem：前锥接细探针、前级装药（3BK31 / 射流弹）"""
    fin_m = fin_m or M.steel_dk
    lathe([(0, 0), (0, 26), (160, 26)], M.steel_dk, name='boom')
    lathe([(0, 30), (0, 56), (1, 58), (12, 58), (13, 55), (13, 30)], M.redbrown, name='ring')
    for i in range(6):   # 折叠尾翼：顺着尾管贴着的六片（中间露出尾管）
        a = i * 60.0 + 12
        sleeve(15, 142, 40, 46, a, a + 38, fin_m, name='fin')
    lathe([(150, 26), (160, 32), (172, 48), (185, 58), (195, 60.5), (400, 61)], body_m, name='body')
    band(214, 226, 61, body_m, lift=1.4)
    band(244, 256, 61, body_m, lift=1.4)
    if not tandem:
        lathe([(400, 61), (430, 57), (470, 42), (500, 26), (505, 22)], body_m, name='front')
        lathe([(505, 21), (515, 20), (560, 15), (610, 11), (640, 9.5)], M.alu, name='fuze')
        lathe([(640, 9.5), (642, 11), (650, 11), (652, 8), (L - 2, 3.5), (L, 0)], M.steel, name='cap')
    else:
        lathe([(400, 61), (430, 56), (460, 40), (476, 26), (480, 20)], body_m, name='front')
        lathe([(479, 13), (L - 92, 12.5)], M.steel_dk, name='probe')
        lathe([(L - 92, 16), (L - 88, 23), (L - 52, 23), (L - 46, 16), (L - 44, 11)], body_m, name='pre')   # 前级装药
        lathe([(L - 45, 10), (L - 14, 9.5), (L - 14, 12), (L - 8, 12), (L - 4, 6), (L, 0)], M.steel, name='fz')
    if txt:
        stencil(txt, 320, 61, 12, M.band_black, spacing=1.2)
    if txt2:
        stencil(txt2, 375, 61, 10, M.band_black)


@item('bk18m', fam='125', full=660)
def _():   # 3BK18M：带引信 660；灰绿弹体，黑字「БК18М В-15」、炸药代号
    heatfs125(M.ru_gg, 660, txt='БК18М\nВ-15', txt2='ОКФОЛ')


@item('bk31', fam='125', full=690)
def _():   # 3BK31 串联破甲弹：长探针上一节前级装药（按同族画，△）
    heatfs125(M.ru_grey, 690, tandem=True, txt='БК31', txt2='ОКФОЛ')


@item('heat125', fam='125', full=660)
def _():   # 99A 的 125 破甲弹：外形照苏式（3BK18M），颜色没查到（△）——橄榄灰
    heatfs125(M.cn_olive, 660)


@item('jet125', fam='125', full=690)
def _():   # 「金属射流弹」125：串联破甲（同 3BK31 外形），深灰弹体
    heatfs125(M.ru_dkgrey, 690, tandem=True)


def hefrag125(body_m, txt=None):
    """125 杀爆弹（3OF26，乌克兰识别手册 + NGIC）：橙褐塑料后环、阳极氧化浅绿尾段（折叠尾翼的黑缝）、两道凸起定心带、
       长卵形头、V-429E 引信"""
    lathe([(0, 0), (0, 56), (2, 61), (28, 61), (30, 56), (30, 0)], M.obtur, name='obt')
    lathe([(30, 56.5), (232, 56.5), (236, 60), (245, 61)], M.anod, name='tail')
    for i in range(6):   # 折叠尾翼的缝
        a = i * 60.0 + 20
        lathe([(46, 56.5), (214, 56.5)], M.band_black, a0=a - 2.2, a1=a + 2.2, dr=0.2, name='slot')
    lathe([(245, 61), (440, 61), (480, 59.5), (520, 54), (560, 45), (590, 35), (612, 24), (618, 20)], body_m, name='body')
    band(252, 264, 61, body_m, lift=1.4)
    band(276, 288, 61, body_m, lift=1.4)
    lathe([(618, 20), (622, 19), (645, 15), (660, 10.5), (664, 9)], M.steel_dk, name='fuze')
    lathe([(664, 9), (668, 6.5), (671, 0)], M.black_paint, name='fz_tip')
    if txt:
        stencil(txt, 370, 61, 12, M.band_black, spacing=1.2)


@item('of26', fam='125', full=671)
def _():   # 3OF26：带引信 671；浅灰弹体，黑字「А-IX-2」「ОФ26」
    hefrag125(M.ru_grey, 'А-IX-2\nОФ26')


@item('he125', fam='125', full=671)
def _():   # 99A 的 125 杀爆弹：外形照苏式（3OF26），颜色没查到（△）
    hefrag125(M.cn_olive)


@item('refleks', fam='125', full=695)
def _():   # 9M119「反射」：橄榄卡其弹体、黑色环带，前部黑色折叠鸭翼、尾部黑色折叠尾翼（收拢）；头罩深一些（乌克兰识别手册照片）
    lathe([(0, 0), (0, 50), (4, 58), (14, 60), (120, 60)], M.plastic_blk, name='rear')
    for i in range(4):
        a = i * 90.0 + 10
        sleeve(16, 118, 60, 63.4, a, a + 68, M.plastic_blk, name='tailfin')
    lathe([(120, 60), (124, 62.4), (455, 62.5)], M.missile, name='body')
    band(250, 262, 62.5, M.band_black)
    band(330, 338, 62.5, M.band_black)
    lathe([(455, 62.5), (500, 61), (545, 56), (590, 46), (630, 32), (665, 17), (688, 6), (695, 0)], M.missile_nose, name='nose')
    for i in range(4):
        a = i * 90.0 + 35
        sleeve(462, 500, 61.2, 63.2, a, a + 20, M.plastic_blk, name='canard')
    stencil('9М119', 395, 62.5, 10, M.band_black)


# ======== 100 毫米（D-10T：59 式 / 69-II 式）：整装弹，灰绿漆钢药筒
@item('br412d', fam='100', case=695, nose=1000)
def _():   # BR-412D 被帽穿甲弹：灰绿弹体、被帽外再套尖风帽（风帽和弹体的接缝），黑字，不加色环（没找到彩照，按苏式通则，△）
    case_100(M.ru_case)
    lathe([(688, 49.6), (790, 49.6), (800, 49)], M.ru_gg, name='body')
    lathe([(800, 49), (838, 45), (840, 44.2)], M.ru_gg, name='cap')
    band(837, 842, 44.4, M.band_black, lift=0.1)
    lathe([(840, 44), (842, 43.2), (885, 35.5), (930, 24), (962, 13), (985, 5.5), (996, 2), (1000, 0)], M.ru_gg, name='ws')
    stencil('БР-412Д', 750, 49.6, 9, M.band_black)


@item('of412', fam='100', case=695, nose=1035)
def _():   # OF-412 杀爆弹（NGIC）：灰绿钢弹体、定心部涂清漆（露钢）、卵形头、RGM 引信，黑字
    case_100(M.ru_case)
    lathe([(688, 49.6), (700, 49.6)], M.ru_gg, name='b0')
    lathe([(700, 50.2), (722, 50.2)], M.steel_dk, name='bourrelet')
    lathe([(722, 49.6), (765, 49.6), (805, 47), (850, 40), (895, 29), (922, 21)], M.ru_gg, name='body')
    lathe([(922, 20.5), (926, 20), (960, 17), (1000, 12.5), (1028, 9.5), (1033, 8), (1035, 0)], M.alu, name='fuze')
    stencil('ОФ-412\n100', 770, 49.6, 9, M.band_black, spacing=1.2)


@item('bk5m', fam='100', case=695, nose=1090)
def _():   # BK-5M 破甲弹：灰绿弹体、前锥接细长的引信头，黑字（照 BK16M / BK5 的样子，△）
    case_100(M.ru_case)
    lathe([(688, 49), (830, 49), (870, 37), (903, 21)], M.ru_gg, name='body')
    lathe([(902, 18.5), (1050, 12.5)], M.ru_gg, name='nose')
    lathe([(1050, 12.5), (1068, 12.5), (1082, 8.5), (1090, 0)], M.alu, name='fz')
    stencil('БК-5М', 760, 49, 9, M.band_black)


@item('apfsds69', fam='100', case=695, nose=1140)
def _():   # 69-II 式的 100 毫米尾翼稳定脱壳穿甲弹（照 3BM24 / 3UBM10：全长 1140），弹托灰绿、钨合金杆（颜色△）
    case_100(M.ru_case)
    prof = [(688, 49.5), (790, 49.5), (800, 46.5), (826, 25), (832, 16)]
    lathe(prof, M.ru_gg, name='sabot')
    seams(prof, (30.0, 150.0, 270.0), M.band_black, w=1.3)
    lathe([(704, 50.1), (716, 50.1)], M.alu, name='ring')
    lathe([(830, 10), (1095, 9.6)], M.wha, name='rod')
    tip(1095, 1140, 9.6, M.steel)


# ======== 152 毫米（M551 的 M81）：M409 多用途破甲弹，可燃药筒
@item('m409', fam='152', case=400, nose=733, dia=166)
def _():   # M409：土黄可燃药筒 + 钢底座，黑弹体（黄字）、前面探针 + 引信（按北约破甲弹通则，△）
    lathe([(0, 0), (0, 80), (2, 83), (14, 83), (16, 80)], M.stub, name='base')
    lathe([(16, 80), (380, 78), (392, 77), (400, 76.5), (400, 40)], M.tan_comb, name='comb')
    lathe([(392, 76.6), (400, 76.6), (400, 70)], M.seal, name='seal')
    heat_spike(400, 75.5, 515, 628, 12.5, 708, 733, M.black_paint, 152)
    stencil('152MM HEAT-MP-T\nM409', 455, 75.5, 10, M.yellow)


################################################################ 机枪、机炮
def cartridge(spec, case_m, bullet_m, tip_m=None, tip_len=0, band_m=None, fuze=None, proj=None):
    """枪弹 / 炮弹（无底缘瓶形药筒）：spec = (药筒长, 底缘半径, 筒身半径, 肩 x, 肩半径, 颈 x, 颈半径, 弹头半径, 全长)"""
    cl, rim, body, sx, sr, nx, nr, br, oal = spec
    lathe([(0, 0), (0, rim - 0.3), (0.4, rim), (cl * 0.025, rim), (cl * 0.03, rim * 0.86), (cl * 0.065, rim * 0.86),
           (cl * 0.085, body), (sx, sr), (nx, nr), (cl, nr), (cl, br * 0.8)], case_m, name='case')
    L = oal - cl
    if proj:
        proj(cl, br, oal)
        return
    lathe([(cl - 2, br), (cl + L * 0.35, br), (cl + L * 0.55, br * 0.9), (cl + L * 0.75, br * 0.66), (cl + L * 0.92, br * 0.3), (oal, 0)], bullet_m, name='bullet')
    if tip_m:   # 弹尖涂色（曳光、穿甲燃烧）
        lathe([(oal - tip_len, br * 0.62), (oal - tip_len * 0.5, br * 0.36), (oal, 0)], tip_m, name='tipc', dr=0.15)


def belt(n, pitch, tilt, build, link_spec=None):
    """弹链：n 发一排（沿 −Z 排开），整排绕弹轴倒 tilt 度（像平放在桌上从斜前方看：一发压一发）"""
    i0 = mark()
    for i in range(n):
        j = mark()
        build(i)
        if link_spec:
            x0, x1, r, w = link_spec   # 链节：卡在药筒上的钢圈 + 两发之间的连接片
            for xa in (x0, x1):
                lathe([(xa, r), (xa + w, r)], M.steel_dk, name='link')
            box(((x0 + x1 + w) / 2, 0, -pitch / 2), (x1 - x0 + w, 1.2, pitch - 2 * r + 1.0), M.steel_dk, name='linkbar')
        xform(j, T(0, 0, -i * pitch))
    xform(i0, R(tilt, 'X'))


@item('coax', vis=None)
def _():   # 7.62×51 NATO：M13 链节、黄铜药筒、铜被甲弹头，每 5 发一发曳光（橙红尖）
    spec = (51.2, 6.0, 5.97, 39.5, 5.75, 43.5, 4.4, 3.91, 71.1)
    belt(5, 12.0, 58, lambda i: cartridge(spec, M.brass, M.gilding, M.red_tip if i == 2 else None, 7), (10, 31, 6.4, 6))


@item('hmg')
def _():   # 12.7×99（M2）：M9 链节；M33 普通弹、M8 穿甲燃烧（银尖）、M20 穿甲燃烧曳光（红尖）
    spec = (99.0, 10.2, 10.2, 76.0, 9.1, 82.0, 7.1, 6.5, 138.0)
    tips = [None, M.alu, M.red_tip, None]
    belt(4, 21.0, 58, lambda i: cartridge(spec, M.brass, M.gilding, tips[i], 13), (18, 58, 10.9, 9))


@item('kpvt')
def _():   # 14.5×114（KPVT）：灰绿漆钢药筒；B-32 穿甲燃烧弹（黑尖、红环）
    spec = (114.0, 13.4, 13.4, 88.0, 12.6, 98.0, 8.2, 7.45, 156.0)

    def one(i):
        cartridge(spec, M.ru_case, M.gilding, M.band_black, 16)
        lathe([(156 - 22, 7.45 * 0.86), (156 - 16, 7.45 * 0.7)], M.red_tip, dr=0.2, name='ring')
    belt(4, 26.0, 58, one, (20, 70, 13.9, 10))


def proj_he(m_body, m_fuze, band_m=None, ring_m=None):
    """机炮榴弹：弹带 + 弹体 + 头部引信"""
    def f(cl, br, oal):
        L = oal - cl
        lathe([(cl - 3, br * 0.97), (cl + L * 0.08, br * 0.97)], band_m or M.copper, name='band')
        lathe([(cl + L * 0.08, br), (cl + L * 0.5, br), (cl + L * 0.62, br * 0.92), (cl + L * 0.7, br * 0.78)], m_body, name='body')
        lathe([(cl + L * 0.7, br * 0.78), (cl + L * 0.84, br * 0.56), (cl + L * 0.95, br * 0.34), (oal - 0.5, br * 0.2), (oal, 0)], m_fuze, name='fuze')
        if ring_m:
            band(cl + L * 0.4, cl + L * 0.46, br, ring_m)
    return f


def proj_ap(m_body, m_tip):
    """机炮穿甲弹：弹带 + 弹体 + 黑 / 红弹尖"""
    def f(cl, br, oal):
        L = oal - cl
        lathe([(cl - 3, br * 0.97), (cl + L * 0.1, br * 0.97)], M.copper, name='band')
        lathe([(cl + L * 0.1, br), (cl + L * 0.45, br), (cl + L * 0.62, br * 0.88)], m_body, name='body')
        lathe([(cl + L * 0.62, br * 0.88), (cl + L * 0.82, br * 0.58), (cl + L * 0.95, br * 0.24), (oal, 0)], m_tip, name='tipc')
    return f


def proj_apds(m_sabot, m_core):
    """机炮脱壳穿甲弹：塑料 / 铝弹托 + 露出的钨芯尖"""
    def f(cl, br, oal):
        L = oal - cl
        lathe([(cl - 3, br), (cl + L * 0.42, br), (cl + L * 0.5, br * 0.7), (cl + L * 0.54, br * 0.45)], m_sabot, name='sabot')
        lathe([(cl + L * 0.53, br * 0.42), (cl + L * 0.8, br * 0.38), (cl + L * 0.95, br * 0.16), (oal, 0)], m_core, name='core')
    return f


def ac_pair(spec, case_m, projs, pitch, tilt=40):
    belt(len(projs), pitch, tilt, lambda i: cartridge(spec, case_m, None, proj=projs[i]))


@item('ac25')
def _():   # 25×137（87 式的 KBA）：钢药筒；脱壳穿甲曳光（黑弹托）+ 榴弹（黄弹体）
    spec = (137.0, 21.6, 21.6, 105.0, 18.9, 112.0, 13.4, 12.5, 223.0)
    ac_pair(spec, M.us_case, [proj_apds(M.black_sabot, M.wha), proj_he(M.yellow_body, M.steel_dk)], 30.0)


@item('ac30')
def _():   # 30×165（2A42 / 2A38）：灰绿漆钢药筒；3UOF8 杀爆燃烧（引信 + 灰绿弹体）、3UBR6 穿甲曳光（黑尖）
    spec = (165.0, 21.8, 21.8, 128.0, 19.5, 140.0, 15.3, 15.0, 285.0)
    ac_pair(spec, M.ru_case, [proj_he(M.ru_gg, M.steel_dk, ring_m=M.band_red), proj_ap(M.ru_gg, M.black_paint)], 34.0)


@item('ac35')
def _():   # 35×228（猎豹的厄利空）：黄铜药筒；榴弹（黄弹体、引信）
    spec = (228.0, 30.5, 30.5, 175.0, 28.0, 190.0, 19.0, 17.5, 387.0)
    ac_pair(spec, M.brass, [proj_he(M.yellow_body, M.steel_dk), proj_he(M.yellow_body, M.steel_dk)], 46.0)


@item('vulcan')
def _():   # 20×102（M61）：黄铜药筒；M56 杀爆燃烧（黄弹体、红尖）
    spec = (102.0, 14.8, 14.8, 76.0, 13.4, 86.0, 10.5, 10.0, 168.0)
    ac_pair(spec, M.brass, [proj_he(M.yellow_body, M.red_tip)] * 3, 24.0, tilt=50)


@item('gau8')
def _():   # 30×173（GAU-8）：铝药筒；PGU-14 贫铀穿甲燃烧（黑弹体红尖）、PGU-13 杀爆燃烧（黄弹体）
    spec = (173.0, 22.5, 22.5, 150.0, 20.5, 160.0, 15.8, 15.0, 290.0)
    ac_pair(spec, M.alu, [proj_ap(M.black_paint, M.red_tip), proj_he(M.yellow_body, M.steel_dk)], 34.0)


################################################################ 低压炮、导弹、火箭、榴弹
@item('gun100')
def _():   # BMP-3 的 2A70：3UOF17（3OF32 杀爆弹 + 短钢药筒，带药筒约 530，乌克兰识别手册照片）
    lathe([(0, 0), (0, 54), (1.5, 56), (9, 56), (10, 52), (150, 51), (158, 50.5), (158, 40)], M.ru_case, name='case')
    lathe([(150, 50), (330, 50), (360, 48), (400, 38), (430, 24), (440, 18)], M.ru_grey, name='body')
    band(160, 172, 50, M.copper, lift=0.6)
    lathe([(440, 18), (446, 17), (500, 11), (522, 8), (530, 0)], M.steel_dk, name='fuze')
    stencil('ОФ32', 270, 50, 9, M.band_black)


@item('gun73', vis=760)
def _():   # BMP-1 的 2A28：PG-15V 火箭增程破甲弹——尖头压电引信、73 毫米战斗部、细一些的火箭发动机、折叠尾翼、后面的发射药
    lathe([(0, 0), (0, 34), (2, 36), (150, 36), (158, 30)], M.missile, name='charge')
    lathe([(150, 18), (240, 18)], M.steel_dk, name='nozzle')
    for i in range(6):
        a = i * 60.0 + 15
        sleeve(160, 250, 24, 29, a, a + 40, M.steel_dk, name='fin')
    lathe([(238, 24), (250, 30), (480, 30), (500, 35)], M.mgreen, name='motor')
    lathe([(500, 36.5), (650, 36.5), (690, 32), (730, 22), (760, 11)], M.mgreen, name='war')
    lathe([(758, 11), (800, 6), (820, 0)], M.steel_dk, name='fz')
    stencil('ПГ-15В', 590, 36.5, 7, M.band_black)


@item('malyutka')
def _():   # 9M14「婴儿」：橄榄绿弹体、尖锥战斗部、尾部四片大后掠翼（BMP-1 炮上导轨装着的样子：翼张开）
    lathe([(0, 0), (0, 48), (10, 60), (40, 62), (520, 62)], M.mgreen, name='body')
    lathe([(520, 62), (560, 60), (700, 40), (820, 15), (860, 0)], M.mgreen, name='war')
    lathe([(0, 0), (0, 20), (-12, 16), (-12, 0)], M.steel_dk, name='tracer')
    fins(4, [(40, 60), (230, 60), (185, 196), (110, 196)], 3, M.mgreen, rot0=45)
    stencil('9М14', 400, 62, 10, M.band_black)


@item('konkurs', vis=1100)
def _():   # 9M113「竞技」：橄榄绿弹体（135 毫米），尾部折叠翼，前面钝圆头（发射筒里的样子）
    lathe([(0, 0), (0, 58), (12, 67.5), (900, 67.5), (960, 60), (1040, 46), (1110, 28), (1150, 12), (1165, 0)], M.mgreen, name='body')
    for i in range(4):
        a = i * 90.0 + 15
        sleeve(30, 260, 67.5, 70.5, a, a + 55, M.mgreen, name='wing')
    band(700, 712, 67.5, M.band_black)
    stencil('9М113', 980, 50, 8, M.band_black)


@item('kornet', vis=900)
def _():   # 9M133「短号」：152 毫米，前面串联战斗部的细探针，折叠翼
    lathe([(0, 0), (0, 70), (12, 76), (860, 76), (900, 70), (960, 50), (980, 30)], M.mgreen, name='body')
    lathe([(978, 16), (1120, 14)], M.steel_dk, name='probe')
    lathe([(1120, 22), (1126, 26), (1170, 26), (1190, 16), (1210, 0)], M.mgreen, name='pre')
    for i in range(4):
        a = i * 90.0 + 15
        sleeve(30, 300, 76, 79, a, a + 55, M.mgreen, name='wing')
    stencil('9М133', 700, 76, 9, M.band_black)


@item('tow2', vis=1000)
def _():   # BGM-71 陶式 2：152 毫米橄榄绿弹体、伸出的长探针，中段折叠翼，黄环（含高爆）
    lathe([(0, 0), (0, 70), (10, 76), (980, 76), (1010, 70), (1040, 56), (1060, 30)], M.od, name='body')
    band(900, 925, 76, M.yellow)
    lathe([(1058, 22), (1480, 20)], M.od, name='probe')
    lathe([(1480, 20), (1490, 24), (1515, 24), (1525, 14), (1530, 0)], M.steel_dk, name='probetip')
    for i in range(4):
        a = i * 90.0 + 15
        sleeve(520, 760, 76, 79, a, a + 50, M.od, name='wing')
    stencil('TOW 2', 800, 76, 12, M.band_black)


@item('s57e6', vis=1000)
def _():   # 57E6（铠甲）：两级——粗的助推器 + 细长的飞行级（「标枪」），飞行级前面四片小鸭翼，只画前段
    lathe([(0, 0), (0, 45), (1400, 45), (1440, 38)], M.mgreen, name='boost')
    lathe([(1430, 38), (2900, 38), (3000, 34), (3100, 20), (3160, 0)], M.mgreen, name='dart')
    fins(4, [(2560, 37), (2640, 37), (2660, 70), (2620, 70)], 2.5, M.mgreen, rot0=45)
    band(2400, 2420, 38, M.band_black)


@item('s9m31', vis=1000)
def _():   # 9M31「箭-1」：120 毫米，头部红外导引头的玻璃头罩、前面四片鸭翼，只画前段
    lathe([(0, 0), (0, 60), (1650, 60), (1720, 52), (1770, 38), (1790, 26)], M.mgreen, name='body')
    lathe([(1789, 26), (1796, 20), (1801, 10), (1803, 0)], M.glass, name='dome')
    fins(4, [(1480, 59), (1600, 59), (1620, 120), (1560, 120)], 3, M.mgreen, rot0=45)
    band(1300, 1320, 60, M.band_black)


@item('how155')
def _():   # 155 毫米 M795 榴弹：橄榄绿弹体黄字（含高爆）、铜弹带、M739 引信（铝）
    lathe([(0, 0), (0, 64), (40, 74), (80, 77.5)], M.od, name='base')
    lathe([(80, 78.3), (110, 78.3)], M.copper, name='band')
    lathe([(110, 77.5), (480, 77.5), (560, 72), (640, 58), (700, 42), (728, 33)], M.od, name='body')
    lathe([(728, 33), (732, 32), (800, 22), (850, 12), (870, 6), (872, 0)], M.alu, name='fuze')
    stencil('155MM\nM795 HE', 360, 77.5, 13, M.yellow, spacing=1.2)


@item('mlrs', vis=1000)
def _():   # M26 火箭弹（227 毫米）：橄榄绿，前面锥形头、引信，黄字；只画前段
    lathe([(0, 0), (0, 113.5), (3400, 113.5), (3600, 100), (3800, 60), (3900, 22)], M.od, name='body')
    lathe([(3898, 22), (3930, 12), (3937, 0)], M.alu, name='fz')
    band(3200, 3240, 113.5, M.yellow)
    stencil('M26', 3320, 113.5, 20, M.yellow)


################################################################ 工具格（烟幕、维修、灭火、望远镜、火炮支援、侦察）
@item('smoke', kind='tool')
def _():   # 车载发烟榴弹（照 76 毫米 M76 这一类）：橄榄绿弹体、浅绿环（发烟）、黑色塑料底座、圆顶头
    lathe([(0, 0), (0, 30), (2, 33), (18, 33), (20, 31)], M.plastic_blk, name='base')
    lathe([(20, 32.5), (150, 32.5), (160, 31), (172, 26), (182, 17), (188, 7), (190, 0)], M.od, name='body')
    band(40, 64, 32.5, M.lt_green)
    stencil('SMOKE', 110, 32.5, 7, M.white)


@item('fix', kind='tool')
def _():   # 维修：一把开口 + 梅花两用扳手（镀铬），斜着放（开口那头朝右上）
    i0 = mark()
    sleeve(-4.5, 4.5, 11, 24, 42, 318, M.satin, name='head')       # 开口头：C 形，口朝右
    xform(i0, T(92, 0, 0) @ R(90, 'Z'))
    i0 = mark()
    sleeve(-4.75, 4.75, 11.5, 21, 0, 360, M.satin, name='ring')    # 梅花头：一圈
    xform(i0, T(-92, 0, 0) @ R(90, 'Z'))
    box((0, 0, 0), (152, 8, 19), M.satin, bevel=2.6, name='handle')
    box((0, -4.2, 0), (100, 0.8, 9), M.steel_dk, bevel=0.3, name='groove')
    xform(0, R(-24, 'Y'))


@item('ext', kind='tool')
def _():   # 灭火器：红色钢瓶、黑色阀头和压把、黑软管、白标签；斜着放（阀头朝右上）
    lathe([(0, 0), (0, 40), (6, 48), (20, 50), (280, 50), (300, 46), (315, 36), (322, 24), (325, 18)], M.red_paint, name='body')
    lathe([(325, 16), (345, 16)], M.chrome, name='neck')
    box((368, 0, 4), (46, 30, 34), M.plastic_blk, bevel=4, name='valve')
    box((360, 0, 30), (90, 10, 6), M.chrome, rot=(0, 8, 0), bevel=1.5, name='lever')
    box((370, 0, -18), (60, 10, 6), M.chrome, rot=(0, -4, 0), bevel=1.5, name='grip')
    lathe([(110, 50.3), (230, 50.3)], M.label, a0=-55, a1=55, name='label')
    tube([(392, 0, 4), (420, -4, -6), (420, -30, -48), (300, -56, -46), (200, -56, -40)], 7, M.rubber, name='hose')
    xform(0, R(-20, 'Y'))


@item('bino', kind='tool')
def _():   # 车长望远镜（照军用 7×50 双筒）：橄榄色橡胶包覆、物镜深色镀膜镜片、目镜罩、中间铰链；从右前上方看（看得见两块物镜）
    for z in (-37, 37):
        i0 = mark()
        lathe([(-74, 0), (-74, 15), (-70, 18.5), (-52, 18.5), (-50, 15), (-40, 15)], M.rubber, name='eye')
        box((-6, 0, 0), (70, 44, 56), M.rubber_od, bevel=10, name='prism')
        lathe([(26, 27), (30, 29.5), (100, 29.5), (106, 31), (112, 31), (112, 26)], M.rubber_od, name='obj')
        lens(112, 26.5)
        xform(i0, T(0, 0, z))
    cyl((-4, 0, 0), 10, 64, M.plastic_blk, axis='Z', name='hinge')
    box((-46, 0, 0), (12, 14, 50), M.plastic_blk, bevel=2, name='bridge')
    xform(0, R(28, 'X'))
    xform(0, R(-32, 'Z'))


@item('arty', kind='tool')
def _():   # 火炮支援：野战电台话筒（照 H-250 这一类）——弯手柄、两头朝下的听筒 / 话筒、背上的按讲键、卷线
    tube([(-92, 0, -6), (-50, 0, 8), (0, 0, 12), (50, 0, 8), (92, 0, -6)], 15, M.plastic_blk, name='handle')
    for (x, r0, r1, ang) in ((-96, 24, 33, -18), (96, 20, 27, 18)):   # 听筒（大）、话筒（小）：口朝下
        i0 = mark()
        lathe([(0, 0), (0, r0), (24, r1), (28, r1 - 1), (28, 0)], M.plastic_blk, name='cup')
        lathe([(28.2, 0), (28.2, r1 - 6)], M.rubber, name='grille')
        xform(i0, T(x, 0, -6) @ R(ang, 'Y') @ R(90, 'Y'))
    box((0, 0, 24), (64, 16, 8), M.rubber, bevel=3, name='ptt')
    pts = []
    for i in range(80):   # 卷线：从听筒那头往下盘
        t = i / 79.0
        a = t * 2 * math.pi * 6
        pts.append((-118 - t * 36, 7 * math.cos(a), -20 - t * 54 + 7 * math.sin(a)))
    tube([(-104, 0, -12), (-116, 0, -18)] + pts, 2.2, M.rubber, name='cord')
    xform(0, R(24, 'X'))


@item('scout', kind='tool')
def _():   # 侦察：手持激光测距仪（单筒）——橄榄色机身、物镜和激光发射窗、目镜橡胶罩、按键；从右前方看（看得见镜头）
    box((0, 0, 0), (150, 58, 62), M.rubber_od, bevel=12, name='body')
    i0 = mark()
    lathe([(70, 0), (70, 24), (92, 24), (94, 22)], M.plastic_blk, name='objring')
    lens(94, 21)
    xform(i0, T(0, 0, -6))
    i0 = mark()
    lathe([(70, 0), (70, 10), (84, 10), (85, 9)], M.plastic_blk, name='laser')
    lens(85, 8.5)
    xform(i0, T(0, 0, 22))
    lathe([(-110, 0), (-110, 17), (-106, 20), (-88, 20), (-86, 16), (-74, 16)], M.rubber, name='eye')
    for x in (-30, 0):
        cyl((x, 0, 33), 6, 6, M.plastic_blk, axis='Z', bevel=1, name='btn')
    xform(0, R(-34, 'Z'))
    xform(0, R(12, 'X'))


################################################################ 摆相机、渲染
def bbox_world():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            p = mw @ v.co
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


def screen_extent():
    """竖直方向在画面上的范围（相机略俯：z·cos − y·sin）"""
    zs = []
    c, s = math.cos(ELEV), math.sin(ELEV)
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            p = mw @ v.co
            zs.append(p.z * c + p.y * s)
    return min(zs), max(zs)


def lights(cx, cz, span):
    """主光：大柔光箱左上 45°（镜头这一侧）；补光：右前三成；轮廓光：后上方（黑件靠它分出来）"""
    def area(name, loc, energy, size):
        l = bpy.data.lights.new(name, 'AREA')
        l.energy = energy
        l.shape = 'RECTANGLE'
        l.size = size
        l.size_y = size * 0.6
        ob = bpy.data.objects.new(name, l)
        ob.location = loc
        bpy.context.scene.collection.objects.link(ob)
        d = Vector((cx, 0, cz)) - Vector(loc)
        ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        return ob
    s = max(span, 0.3)
    k = s * s
    E = float(opt.get('exp', 1.0))
    area('Key', (cx - 0.9 * s, -1.1 * s, cz + 1.0 * s), 62 * k * E, 1.1 * s)
    area('Fill', (cx + 1.2 * s, -1.0 * s, cz - 0.1 * s), 17 * k * E, 1.0 * s)
    area('Rim', (cx + 0.2 * s, 0.9 * s, cz + 0.9 * s), 75 * k * E, 0.9 * s)


def render(name, it, fam_k):
    s = reset()
    init_mats()
    it['fn']()
    lo, hi = bbox_world()
    zlo, zhi = screen_extent()
    W, H = IMG[it['kind']]
    meta = dict(name=name, kind=it['kind'], w=W, h=H, ss=SS, fam=it['fam'])
    if it['fam'] and it['fam'] in fam_k:
        k = fam_k[it['fam']]   # 1 倍像素每毫米
        nose = it['nose'] if it['nose'] is not None else hi.x / MM
        x_left = nose - NOSE_PX / k
        cx = (x_left + W / 2 / k) * MM
        cz = 0.0
        meta['cut'] = (lo.x / MM) < (x_left - 0.5 / k)
    elif it['vis']:   # 太长的：只画前面 vis 毫米（同药筒那样往左伸出去、渐隐）
        k = min((NOSE_PX - LEFT_PX) / it['vis'], (H - 6) / ((zhi - zlo) / MM))
        nose = hi.x / MM
        x_left = nose - NOSE_PX / k
        cx = (x_left + W / 2 / k) * MM
        cz = (zlo + zhi) / 2
        meta['cut'] = (lo.x / MM) < (x_left - 0.5 / k)
    else:   # 按框塞满：居中
        bw = (hi.x - lo.x) / MM
        bh = (zhi - zlo) / MM
        fw, fh = (W - 10, H - 5) if it['kind'] == 'ammo' else (W - 6, H - 4)
        k = min(fw / max(bw, 1), fh / max(bh, 1))
        cx = (lo.x + hi.x) / 2
        cz = (zlo + zhi) / 2
        meta['cut'] = False
    meta['k'] = round(k, 5)
    span = (W / k) * MM
    cam = bpy.data.cameras.new('Cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = span
    cam.clip_start = 0.001
    cam.clip_end = 100
    co = bpy.data.objects.new('Cam', cam)
    bpy.context.scene.collection.objects.link(co)
    s.camera = co
    D = 5.0
    # 相机略俯 ELEV：画面中心对着 (cx, ?, cz)——cz 是画面上竖直方向的中心（z·cos − y·sin 的坐标）
    up = Vector((0, math.sin(ELEV), math.cos(ELEV)))     # 相机的上方向
    fwd = Vector((0, math.cos(ELEV), -math.sin(ELEV)))   # 相机看的方向
    center = Vector((cx, 0, 0)) + up * cz
    co.location = center - fwd * D
    co.rotation_euler = (math.pi / 2 - ELEV, 0, 0)
    lights(cx, cz, max((hi.x - lo.x), span))
    s.render.resolution_x = W * SS
    s.render.resolution_y = H * SS
    s.render.resolution_percentage = 100
    s.render.filepath = os.path.join(OUT, name + '.png')
    bpy.ops.render.render(write_still=True)
    return meta


def fam_scales():
    """每个口径：86 像素 ÷ 最长可见段（带药筒：露出的弹丸 + 0.25 倍药筒长；不带药筒：整发）"""
    best, fat = {}, {}
    for nm, it in ITEMS.items():
        if not it['fam']:
            continue
        if it['case'] is not None:
            vis = (it['nose'] - it['case']) + 0.25 * it['case']
        else:
            vis = it['full'] if it['full'] is not None else it['nose']
        best[it['fam']] = max(best.get(it['fam'], 0), vis)
        if it.get('dia'):
            fat[it['fam']] = max(fat.get(it['fam'], 0), it['dia'])
    # 竖着也要放得下：最粗的地方不超过 26 像素（1 倍）
    return {f: min((NOSE_PX - LEFT_PX) / v, 26.0 / fat[f] if f in fat else 1e9) for f, v in best.items()}


def main():
    fk = fam_scales()
    metaf = os.path.join(OUT, 'meta.json')
    meta = json.load(open(metaf)) if os.path.exists(metaf) else {}
    for nm, it in ITEMS.items():
        if ONLY and nm not in ONLY:
            continue
        meta[nm] = render(nm, it, fk)
        print('AMMOPIC', nm, json.dumps(meta[nm]))
        json.dump(meta, open(metaf, 'w'), indent=1, sort_keys=True)
    print('AMMOPIC 口径比例（1 倍像素 / 毫米）：', json.dumps({f: round(v, 4) for f, v in fk.items()}))


main()
