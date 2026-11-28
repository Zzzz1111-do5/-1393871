# ViewportFrame 的 3D 场景（tools/mock/xrshot.lua 写的 <名>.vp.json）用 Blender 画出来，看 X 光命中回放长什么样
#   /opt/blender/blender -b --factory-startup -P tools/mock/vp_render.py -- <名>.vp.json <输出.png> <宽> <高> [models 目录]
#   近似 Roblox 的 ViewportFrame：没有影子、只有环境光 + 一盏平行光（颜色 = 底色 ×（Ambient + LightColor × max(0, N·−L)）），
#   透明度照零件的 Transparency 混合，Neon 自己发光；背景是 ViewportFrame 的底色。
#   车壳的影子（json 的 ghost：原模型键、炮塔转角、颜色 / 材质 / 透明度）：模拟器里没有导入的模型，这里直接读 models/veh/<键>.glb
#   摆上去（炮塔、炮按 ImportedMeta 的转轴转），json 里标了 XrGhost 的零件（游戏里看不见那辆车时的两个框）不画
import bpy, bmesh, json, math, os, sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT, W, H = argv[0], argv[1], int(argv[2]), int(argv[3])
MODELS = argv[4] if len(argv) > 4 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'models')
J = json.load(open(SRC, encoding='utf-8'))
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene


def lin(c):   # sRGB 0–255 → 线性
    c = c / 255.0
    return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92


def rb2bl_vec(v):   # Roblox（X 右、Y 上、−Z 前）→ Blender（X 右、Y 前、Z 上）
    return Vector((v[0], -v[2], v[1]))


def rb2bl_mat(c):   # CFrame 的 12 个分量 → Blender 的 4×4
    x, y, z = c[0], c[1], c[2]
    R = [[c[3], c[4], c[5]], [c[6], c[7], c[8]], [c[9], c[10], c[11]]]   # 行：R00 R01 R02 / R10 … （列是右、上、后）
    cols = [rb2bl_vec((R[0][i], R[1][i], R[2][i])) for i in range(3)]
    p = rb2bl_vec((x, y, z))
    M = Matrix.Identity(4)
    for i in range(3):
        M[0][i], M[1][i], M[2][i] = cols[i].x, cols[i].y, cols[i].z
    M[0][3], M[1][3], M[2][3] = p.x, p.y, p.z
    return M


# Roblox 局部轴（X 右、Y 上、Z 后）在 Blender 局部里：零件网格按 Roblox 局部建，再乘 rb2bl_mat
#   rb2bl_mat 已经把三根轴换到 Blender 世界里；网格本身在 Roblox 局部坐标里建（x, y, z 照 Roblox 的局部），所以网格顶点要先 (x, y, z) 不动
def mat_for(col, tr, matname, glow=False):
    m = bpy.data.materials.new('m')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    c = (lin(col[0]), lin(col[1]), lin(col[2]), 1)
    if glow:
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Color'].default_value = c
        em.inputs['Strength'].default_value = 2.2
        sh = em
    else:
        sh = nt.nodes.new('ShaderNodeBsdfDiffuse')
        sh.inputs['Color'].default_value = c
    if tr > 0.001:
        tp = nt.nodes.new('ShaderNodeBsdfTransparent')
        mix = nt.nodes.new('ShaderNodeMixShader')
        mix.inputs['Fac'].default_value = 1 - tr
        nt.links.new(tp.outputs[0], mix.inputs[1])
        nt.links.new(sh.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs['Surface'])
        m.blend_method = 'BLEND'
        m.show_transparent_back = True
    else:
        nt.links.new(sh.outputs[0], out.inputs['Surface'])
    return m


def prim(kind, size):
    bm = bmesh.new()
    sx, sy, sz = size
    if kind == 'Ball' or kind == 'Sphere':
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.5)
        if kind == 'Ball':
            d = min(sx, sy, sz)
            sx = sy = sz = d
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    elif kind == 'Cylinder':   # Roblox 圆柱沿局部 X
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.5, radius2=0.5, depth=1.0)   # 沿 Z
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'), verts=bm.verts)   # Z → X
        d = min(sy, sz)
        bmesh.ops.scale(bm, vec=(sx, d, d), verts=bm.verts)
    else:
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    # 顶点在 Roblox 局部坐标（X 右、Y 上、Z 后）：换成 Blender 局部（同 rb2bl_vec），整个零件再乘 rb2bl_mat 里的旋转
    for v in bm.verts:
        v.co = Vector((v.co.x, -v.co.z, v.co.y))
    me = bpy.data.meshes.new('p')
    bm.to_mesh(me)
    bm.free()
    return me


def place(ob, c):
    # 局部坐标已经换成 Blender 轴（x, −z, y）；CFrame 的旋转在 Roblox 里作用于 Roblox 局部轴 → Blender 世界：
    #   M_bl = C · M_rb · C⁻¹（C：Roblox → Blender 的换轴）；顶点已乘了 C，所以 matrix_world = C · M_rb · C⁻¹
    C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    Mr = Matrix.Identity(4)
    Mr[0][0], Mr[0][1], Mr[0][2], Mr[0][3] = c[3], c[4], c[5], c[0]
    Mr[1][0], Mr[1][1], Mr[1][2], Mr[1][3] = c[6], c[7], c[8], c[1]
    Mr[2][0], Mr[2][1], Mr[2][2], Mr[2][3] = c[9], c[10], c[11], c[2]
    ob.matrix_world = C @ Mr @ C.inverted()


ghost = J.get('ghost')
n = 0
for p in J['parts']:
    if p.get('ghost') and ghost and ghost.get('key'):
        continue   # 游戏里看不见那辆车时画的框：这里用原模型代替
    if p.get('tr', 0) >= 0.995:
        continue
    kind = p.get('shape') or 'Block'
    if p.get('mesh') == 'Sphere':
        kind = 'Sphere'
    me = prim(kind, p['size'])
    ob = bpy.data.objects.new('p%d' % n, me)
    scn.collection.objects.link(ob)
    place(ob, p['cf'])
    ob.data.materials.append(mat_for(p['col'], p.get('tr', 0), p.get('mat'), glow=(p.get('mat') == 'Neon')))
    n += 1

# 原模型当车壳的影子
if ghost and ghost.get('key'):
    path = os.path.join(MODELS, 'veh', ghost['key'] + '.glb')
    if os.path.exists(path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
        st = ghost.get('style') or {}
        gm = mat_for(st.get('col', [150, 190, 220]), st.get('tr', 0.88), st.get('mat'))
        yaw = math.radians(ghost.get('ty', 0))
        tur = ghost.get('tur')   # 炮塔转轴（ImportedMeta 的 tur，元数据坐标 = Roblox 坐标）
        for o in new:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
            nm = o.name
            if tur and ('__Turret' in nm or '__Gun' in nm):
                pv = rb2bl_vec(tur)
                R = Matrix.Translation(pv) @ Matrix.Rotation(-yaw, 4, 'Z') @ Matrix.Translation(-pv)   # 往右转为正（Roblox 绕 Y 转 −yaw）
                o.matrix_world = R @ o.matrix_world
            o.data.materials.clear()
            o.data.materials.append(gm)
        print('影子：%s %d 块' % (ghost['key'], len(new)))

# 灯：环境光（世界色）+ 平行光
amb = J.get('amb', [170, 175, 185])
lc = J.get('light', [255, 255, 255])
ld = J.get('ldir', [-0.4, -1, -0.3])
world = bpy.data.worlds.new('w')
scn.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (lin(amb[0]), lin(amb[1]), lin(amb[2]), 1)
bg.inputs['Strength'].default_value = 1.0
sun = bpy.data.lights.new('sun', 'SUN')
sun.energy = math.pi   # 漫反射白面正对着 = 1
sun.color = (lin(lc[0]), lin(lc[1]), lin(lc[2]))
so = bpy.data.objects.new('sun', sun)
scn.collection.objects.link(so)
L = rb2bl_vec(ld).normalized()
so.rotation_euler = (-L).to_track_quat('Z', 'Y').to_euler()   # 灯的 −Z 是照的方向

# 镜头
cam = bpy.data.cameras.new('cam')
cam.sensor_fit = 'VERTICAL'
cam.angle_y = math.radians(J.get('fov', 40))
cam.clip_start, cam.clip_end = 0.05, 5000
co = bpy.data.objects.new('cam', cam)
scn.collection.objects.link(co)
c = J['cam']
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
Mr = Matrix.Identity(4)
Mr[0][0], Mr[0][1], Mr[0][2], Mr[0][3] = c[3], c[4], c[5], c[0]
Mr[1][0], Mr[1][1], Mr[1][2], Mr[1][3] = c[6], c[7], c[8], c[1]
Mr[2][0], Mr[2][1], Mr[2][2], Mr[2][3] = c[9], c[10], c[11], c[2]
# Roblox 镜头局部：−Z 看、+Y 上；Blender 镜头局部同样 −Z 看、+Y 上 → 镜头的局部轴不换，只换世界：matrix_world = C · M_rb
co.matrix_world = C @ Mr
scn.camera = co

scn.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
scn.view_settings.view_transform = 'Standard'
scn.render.film_transparent = True
scn.render.resolution_x, scn.render.resolution_y = W, H
scn.render.filepath = OUT
try:
    scn.eevee.taa_render_samples = 16
except Exception:
    pass
bpy.ops.render.render(write_still=True)
print('画好了 %s（%d 个零件）' % (OUT, n))
