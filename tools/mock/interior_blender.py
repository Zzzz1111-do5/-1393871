# 车内饰的 Blender 渲染（Cycles，真实光照）：把 mock 测试 dump 出来的内饰零件和原车 GLB 摆在一起，按各乘员位的镜头渲染
#   用法：/opt/blender/blender -b --factory-startup -P tools/mock/interior_blender.py -- <interior_xxx.json> <输出前缀> <models/veh/xxx.glb> [carve] [day] [samples=48] [w=1280] [h=720]
#   carve：挖了内腔的原车（carve.py）——坐在车里看到的样子：Inside_ 块藏起来、Glass_ 块透明、内壁显示；外壳背面剔除（同 Roblox，从里面看不见外壳的背面）
#   坐标：dump 和 GLB 都是 Roblox 的（Y 上、−Z 朝前，格）；Blender 是 Z 上——(x, y, z) → (x, −z, y)
import bpy, json, math, sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
pos = [a for a in argv if '=' not in a and a not in ('carve', 'day')]
opt = dict(a.split('=', 1) for a in argv if '=' in a)
JSON, OUT, GLB = pos[0], pos[1], pos[2] if len(pos) > 2 else None
CARVE = 'carve' in argv
DAY = 'day' in argv
D = json.load(open(JSON, encoding='utf-8'))

C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Roblox → Blender 的坐标换算


def rb_pos(x, y, z):
    return Vector((x, -z, y))


def rb_mat(c):
    """CFrame 分量（x, y, z, r00..r22）→ Blender 的 4×4 矩阵"""
    R = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
    Rb = C @ R @ C.transposed()
    M = Rb.to_4x4()
    M.translation = rb_pos(c[0], c[1], c[2])
    return M


bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.engine = 'CYCLES'
scn.cycles.device = 'CPU'
scn.cycles.samples = int(opt.get('samples', 48))
scn.cycles.use_denoising = True
scn.render.resolution_x = int(opt.get('w', 1280))
scn.render.resolution_y = int(opt.get('h', 720))
scn.render.film_transparent = False
scn.view_settings.view_transform = 'AgX' if 'AgX' in [v.identifier for v in bpy.types.ColorManagedViewSettings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'

# 天空、太阳
world = bpy.data.worlds.new('W')
scn.world = world
world.use_nodes = True
nt = world.node_tree
bg = nt.nodes['Background']
try:
    sky = nt.nodes.new('ShaderNodeTexSky')
    sky.sky_type = 'NISHITA' if 'NISHITA' in [i.identifier for i in sky.bl_rna.properties['sky_type'].enum_items] else sky.sky_type
    sky.sun_elevation = math.radians(38 if DAY else 8)
    sky.sun_rotation = math.radians(150)
    nt.links.new(sky.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 0.35 if DAY else 0.08
except Exception:
    bg.inputs['Color'].default_value = (0.55, 0.65, 0.8, 1)
sun = bpy.data.lights.new('Sun', 'SUN')
sun.energy = 4.0 if DAY else 0.6
sun.angle = math.radians(1.0)
so = bpy.data.objects.new('Sun', sun)
so.rotation_euler = (math.radians(50), 0, math.radians(150))
scn.collection.objects.link(so)
# 地面
bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0))
gm = bpy.data.materials.new('Ground')
gm.use_nodes = True
gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.32, 0.27, 0.19, 1)
bpy.context.object.data.materials.append(gm)

# 原车
if GLB:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=GLB)
    for ob in set(bpy.data.objects) - before:
        if ob.type != 'MESH':
            continue
        nm = ob.name
        if CARVE and '__Inside_' in nm:
            ob.hide_render = True
            continue
        for slot in ob.material_slots:
            m = slot.material
            if not m:
                continue
            m.use_backface_culling = True
            if CARVE and '__Glass_' in nm:
                m = m.copy()
                slot.material = m
                p = m.node_tree.nodes.get('Principled BSDF')
                if p:
                    p.inputs['Base Color'].default_value = (0.55, 0.65, 0.70, 1)
                    for k in ('Transmission Weight', 'Transmission'):
                        if k in p.inputs:
                            p.inputs[k].default_value = 0.95
                    p.inputs['Roughness'].default_value = 0.05
                    if 'Alpha' in p.inputs:
                        p.inputs['Alpha'].default_value = 0.35
                try:
                    m.surface_render_method = 'BLENDED'
                except Exception:
                    pass
        # Roblox 的单面：背面剔除用 Cycles 的「背面不渲染」（光线照到背面当透明）
        if CARVE and '__Glass_' not in nm:
            for slot in ob.material_slots:
                m = slot.material
                if not m or not m.use_nodes or m.get('_bf'):
                    continue
                nt2 = m.node_tree
                out = next((n for n in nt2.nodes if n.type == 'OUTPUT_MATERIAL'), None)
                if not out or not out.inputs['Surface'].links:
                    continue
                src = out.inputs['Surface'].links[0].from_socket
                geo = nt2.nodes.new('ShaderNodeNewGeometry')
                tr = nt2.nodes.new('ShaderNodeBsdfTransparent')
                mix = nt2.nodes.new('ShaderNodeMixShader')
                nt2.links.new(geo.outputs['Backfacing'], mix.inputs['Fac'])
                nt2.links.new(src, mix.inputs[1])
                nt2.links.new(tr.outputs['BSDF'], mix.inputs[2])
                nt2.links.new(mix.outputs['Shader'], out.inputs['Surface'])
                m['_bf'] = True

# 内饰零件
mats = {}


def mat(col, mname, t):
    key = (tuple(col), mname, round(t, 2))
    if key in mats:
        return mats[key]
    m = bpy.data.materials.new('I_%d' % len(mats))
    m.use_nodes = True
    p = m.node_tree.nodes['Principled BSDF']
    lin = [((c / 255) / 12.92) if c / 255 <= 0.04045 else (((c / 255) + 0.055) / 1.055) ** 2.4 for c in col]
    p.inputs['Base Color'].default_value = (lin[0], lin[1], lin[2], 1)
    rough = {'Metal': 0.45, 'SmoothPlastic': 0.5, 'Plastic': 0.6, 'Glass': 0.05, 'Neon': 0.4, 'Fabric': 0.95, 'DiamondPlate': 0.5, 'Rubber': 0.9}.get(mname, 0.7)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = 0.6 if mname in ('Metal', 'DiamondPlate') else 0.0
    if mname == 'Neon':
        for k in ('Emission Color', 'Emission'):
            if k in p.inputs:
                p.inputs[k].default_value = (lin[0], lin[1], lin[2], 1)
        if 'Emission Strength' in p.inputs:
            p.inputs['Emission Strength'].default_value = 3.0
    if t > 0.01:
        p.inputs['Alpha'].default_value = max(0.05, 1 - t)
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    mats[key] = m
    return m


def add_part(pt):
    shp = pt.get('s', 'Block')
    sz = pt['z']
    M = rb_mat(pt['c'])
    if pt.get('t', 0) >= 0.99:
        return
    if shp == 'Ball':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.5)
        ob = bpy.context.object
        ob.scale = (sz[0], sz[2], sz[1])
    elif shp == 'Cylinder':   # Roblox 的圆柱轴在 X
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.5, depth=1.0)
        ob = bpy.context.object
        ob.data.transform(Matrix.Rotation(math.radians(90), 4, 'Y'))
        ob.scale = (sz[0], sz[2], sz[1])
    elif shp == 'Wedge':
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        ob = bpy.context.object
        ob.scale = (sz[0], sz[2], sz[1])
    else:
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        ob = bpy.context.object
        ob.scale = (sz[0], sz[2], sz[1])
    # 尺寸在 Roblox 的局部轴（X 宽、Y 高、Z 深）→ Blender 局部（X、−Z、Y）：先摆位置转向，再按 (x, z, y) 缩放
    ob.matrix_world = M
    ob.scale = (sz[0], sz[2], sz[1])
    ob.data.materials.append(mat(pt.get('k', [128, 128, 128]), pt.get('m', 'SmoothPlastic'), pt.get('t', 0)))


for pt in D.get('parts', []):
    try:
        add_part(pt)
    except Exception as e:
        print('零件出错', e)
# 屏幕：深色自发光的板
for s in D.get('screens', []):
    try:
        bpy.ops.mesh.primitive_plane_add(size=1.0)
        ob = bpy.context.object
        ob.data.transform(Matrix.Rotation(math.radians(-90), 4, 'X'))   # 朝 Blender 的 +Y = Roblox 零件的正面（−Z）
        ob.matrix_world = rb_mat(s['c'])
        ob.scale = (s['z'][0], 1, s['z'][1])
        m = bpy.data.materials.new('Scr')
        m.use_nodes = True
        p = m.node_tree.nodes['Principled BSDF']
        p.inputs['Base Color'].default_value = (0.02, 0.05, 0.03, 1)
        for k in ('Emission Color', 'Emission'):
            if k in p.inputs:
                p.inputs[k].default_value = (0.15, 0.6, 0.25, 1)
        if 'Emission Strength' in p.inputs:
            p.inputs['Emission Strength'].default_value = 0.8
        ob.data.materials.append(m)
    except Exception as e:
        print('屏幕出错', e)
# 车里的灯
for L in D.get('lights', []):
    try:
        ld = bpy.data.lights.new('L', 'POINT')
        k = L.get('k', [255, 240, 220])
        ld.color = (k[0] / 255, k[1] / 255, k[2] / 255)
        ld.energy = float(L.get('b', 1)) * 25
        ld.shadow_soft_size = 0.15
        lo = bpy.data.objects.new('L', ld)
        p = L['p']
        lo.location = rb_pos(p[0], p[1], p[2])
        scn.collection.objects.link(lo)
    except Exception as e:
        print('灯出错', e)

# 镜头：各乘员位
cam = bpy.data.cameras.new('Cam')
co = bpy.data.objects.new('Cam', cam)
scn.collection.objects.link(co)
scn.camera = co
cam.sensor_fit = 'VERTICAL'
cam.clip_start = 0.02
for c in D.get('cams', []):
    co.matrix_world = rb_mat(c['c'])
    cam.angle = math.radians(c.get('fov', 70))
    scn.render.filepath = '%s_%s.png' % (OUT, c['name'])
    bpy.ops.render.render(write_still=True)
    print('渲染', scn.render.filepath)
