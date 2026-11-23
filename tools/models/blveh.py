# Sketchfab 下载的地面载具原模型 → 游戏用的 GLB（Blender 无头跑；用户 11-23：「我记得 m2a3 现实中是有动画的你重新从 sketchfeb 下载这个吧而且有导弹」
#   「你直接把这个改成 m3 好了」——布雷德利换成 mansoorsajidp 的 M3，炮塔左边的陶式发射箱是单独一块，能竖起来）
#   用法：/opt/blender/blender -b --factory-startup -P tools/models/blveh.py -- <模型键> <原模型 .glb> <输出 .glb> <分组结果 .json>
#   配置 tools/models/blveh.json[<模型键>]：
#     rotZ 绕竖轴转几度（车头朝 −Z）、length 真车全长（米，含炮管不算；按车体长缩放）、groups { 组名: [原节点名…] }（Turret / Gun / Tow / Body；
#     没点名的归 Body）、wheels [原节点名…]（每个一组 Wnn，自己转）、decimate { 原节点名: 保留比例 }、texMax 贴图最大边长、drop [不要的节点]
#   输出：节点名 V_<键>__<组>_<n>（每个节点一种材质、≤19000 个三角形、原点在包围盒中心），坐标：格，X 右、Y 上、−Z 朝前，原点车底中心；
#     分组结果 JSON（每块的组、中心、大小、材质颜色；炮塔转轴、炮耳轴、陶式铰链）给 tools/models/blveh_meta.py 写 ImportedMeta
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
KEY, SRC, OUT, REP = argv[0], argv[1], argv[2], argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, 'blveh.json'), encoding='utf-8'))[KEY]
S = 2.8   # 1 米 = 2.8 格
TRI_MAX = 19000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.data.objects if o.type == 'MESH']
print('导入 %d 块网格' % len(objs))
# 原节点名：glTF 导入后物体名就是节点名
drop = set(CFG.get('drop', []))
for o in list(objs):
    if o.name in drop:
        bpy.data.objects.remove(o, do_unlink=True)
objs = [o for o in bpy.data.objects if o.type == 'MESH']
# 先把父子关系的变换烘焙掉（每块独立）
for o in objs:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in [x for x in bpy.data.objects if x.type != 'MESH']:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 减面（保留 UV）
for o in objs:
    r = CFG.get('decimate', {}).get(o.name)
    if r:
        m = o.modifiers.new('dec', 'DECIMATE')
        m.ratio = float(r)
        bpy.context.view_layer.objects.active = o
        n0 = len(o.data.polygons)
        bpy.ops.object.modifier_apply(modifier=m.name)
        print('  减面 %s：%d → %d' % (o.name, n0, len(o.data.polygons)))

# 转向 + 缩放到真实尺寸（格）+ 车底中心为原点
rot = Matrix.Rotation(math.radians(CFG.get('rotZ', 0)), 4, 'Z')
for o in objs:
    o.data.transform(rot)
WHEEL_SETS = [w if isinstance(w, list) else [w] for w in CFG.get('wheels', [])]
wheel_of = {n: i for i, ws in enumerate(WHEEL_SETS) for n in ws}
body_names = set(n for n in [o.name for o in objs] if n not in sum(CFG.get('groups', {}).values(), []) and n not in wheel_of)


def bbox(objs_):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs_:
        for v in o.data.vertices:
            lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
            hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    return lo, hi


blo, bhi = bbox([o for o in objs if o.name in body_names or o.name in wheel_of])
k = CFG['length'] / (bhi.y - blo.y) * S   # Blender 里 +Y 是车头（导出 glTF 后是 −Z）
lo_all, hi_all = bbox(objs)
off = Vector(((blo.x + bhi.x) / 2, (blo.y + bhi.y) / 2, lo_all.z))
M = Matrix.Scale(k, 4) @ Matrix.Translation(-off)
for o in objs:
    o.data.transform(M)
print('缩放 %.4f（原模型车体长 %.3f → %.2f 米）' % (k, bhi.y - blo.y, CFG['length']))

# 贴图缩小
tmax = int(CFG.get('texMax', 1024))
for im in bpy.data.images:
    if im.size[0] > tmax or im.size[1] > tmax:
        s = tmax / max(im.size[0], im.size[1])
        im.scale(max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s)))
        im.pack()

# 分组：每块原网格 → 组
group_of = {}
for g, names in CFG.get('groups', {}).items():
    for n in names:
        group_of[n] = g


def to_glb(v):   # Blender（X 右、Y 前、Z 上）→ glTF / 游戏（X 右、Y 上、−Z 朝前）
    return [v.x, v.z, -v.y]


# 按（组, 材质）合并；车轮每个单独一组
buckets = {}
wheel_info = {}
for o in objs:
    if o.name in wheel_of:
        g = 'W%02d' % (wheel_of[o.name] + 1)
    else:
        g = group_of.get(o.name, 'Body')
    # 按材质拆开
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    if len(o.data.materials) > 1:
        bpy.ops.mesh.separate(type='MATERIAL')
    for p in [x for x in bpy.context.selected_objects]:
        mat = p.data.materials[0].name if p.data.materials else ''
        buckets.setdefault((g, mat), []).append(p)
    if o.name in wheel_of:
        lo, hi = bbox([o])
        if g in wheel_info:   # 一个轮子几块（轮毂、胶圈）：包围盒合起来
            lo0, hi0 = wheel_info[g]['_lo'], wheel_info[g]['_hi']
            lo = Vector((min(lo.x, lo0.x), min(lo.y, lo0.y), min(lo.z, lo0.z)))
            hi = Vector((max(hi.x, hi0.x), max(hi.y, hi0.y), max(hi.z, hi0.z)))
        wheel_info[g] = {'_lo': lo, '_hi': hi, 'c': [round(x, 3) for x in to_glb((lo + hi) / 2)], 'r': round(max(hi.y - lo.y, hi.z - lo.z) / 2, 3)}

out_objs = []
counter = {}
for (g, mat), lst in sorted(buckets.items()):
    bpy.ops.object.select_all(action='DESELECT')
    for p in lst:
        p.select_set(True)
    bpy.context.view_layer.objects.active = lst[0]
    if len(lst) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    # 三角化，超过上限按连通块分装
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    pieces = [o]
    if len(me.polygons) > TRI_MAX:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.mesh.separate(type='LOOSE')
        loose = sorted(bpy.context.selected_objects, key=lambda x: -len(x.data.polygons))
        packs = []
        for p in loose:
            for pk in packs:
                if pk[0] + len(p.data.polygons) <= TRI_MAX:
                    pk[0] += len(p.data.polygons)
                    pk[1].append(p)
                    break
            else:
                packs.append([len(p.data.polygons), [p]])
        pieces = []
        for _, lst2 in packs:
            bpy.ops.object.select_all(action='DESELECT')
            for p in lst2:
                p.select_set(True)
            bpy.context.view_layer.objects.active = lst2[0]
            if len(lst2) > 1:
                bpy.ops.object.join()
            pieces.append(bpy.context.view_layer.objects.active)
    for p in pieces:
        counter[g] = counter.get(g, 0) + 1
        p.name = 'V_%s__%s_%d' % (KEY, g, counter[g])
        p.data.name = p.name
        # 原点放到包围盒中心
        lo, hi = bbox([p])
        c = (lo + hi) / 2
        p.data.transform(Matrix.Translation(-c))
        p.location = c
        out_objs.append((p, g, mat, lo, hi))

# 分组结果
rep = {'parts': {}, 'wheels': {g: {'c': w['c'], 'r': w['r']} for g, w in wheel_info.items()}}
for p, g, mat, lo, hi in out_objs:
    pn = p.name.split('__', 1)[1]
    e = {'g': g, 'c': [round(x, 3) for x in to_glb((lo + hi) / 2)], 's': [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)]}
    m = bpy.data.materials.get(mat)
    if m and m.use_nodes:
        bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf and not bsdf.inputs['Base Color'].links:
            c = bsdf.inputs['Base Color'].default_value
            e['col'] = [int(round(((1.055 * x ** (1 / 2.4) - 0.055) if x > 0.0031308 else 12.92 * x) * 255)) for x in c[:3]]   # 线性 → sRGB
    rep['parts'][pn] = e
# 转轴：炮塔座圈中心（炮塔最低那一圈顶点的中心）、炮耳轴（炮管最后端往后 gunBack 米）、陶式铰链
def verts_world(names_group):
    pts = []
    for p, g, mat, lo, hi in out_objs:
        if g == names_group:
            pts += [p.matrix_world @ v.co for v in p.data.vertices]
    return pts


tp = verts_world('Turret')
if tp:
    zmin = min(v.z for v in tp)
    ring = [v for v in tp if v.z < zmin + 0.06 * S]
    cx = sum(v.x for v in ring) / len(ring)
    cy = sum(v.y for v in ring) / len(ring)
    rep['tur'] = [round(x, 3) for x in to_glb(Vector((cx, cy, zmin)))]
gp = verts_world('Gun')
if gp:
    ymax = max(v.y for v in gp)
    ymin = min(v.y for v in gp)
    rear = [v for v in gp if v.y < ymin + 0.10 * S]
    gx = sum(v.x for v in rear) / len(rear)
    gz = sum(v.z for v in rear) / len(rear)
    piv = Vector((gx, ymin - CFG.get('gunBack', 0.0) * S, gz))
    rep['gun'] = [round(x, 3) for x in to_glb(piv)]
    rep['muz'] = round(ymax - piv.y, 3)
tw = verts_world('Tow')
if tw:
    # 铰链：发射箱后下沿（竖起时绕它往上转）
    ymin = min(v.y for v in tw)
    zmin = min(v.z for v in tw)
    xs = [v.x for v in tw]
    rep['tow'] = {'hinge': [round(x, 3) for x in to_glb(Vector(((min(xs) + max(xs)) / 2, ymin, zmin)))]}
pts = [p.matrix_world @ v.co for p, *_ in out_objs for v in p.data.vertices]
bpts = [p.matrix_world @ v.co for p, g, *_ in out_objs if g == 'Body' or g.startswith('W') for v in p.data.vertices]
def ext(ps):
    return [max(v.x for v in ps) - min(v.x for v in ps), max(v.z for v in ps) - min(v.z for v in ps), max(v.y for v in ps) - min(v.y for v in ps)]
rep['hull'] = [round(x, 3) for x in ext(bpts)]
ea = ext(pts)
rep['w'], rep['h'], rep['len'] = round(ea[0], 3), round(ea[1], 3), round(ea[2], 3)
json.dump(rep, open(REP, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

bpy.ops.object.select_all(action='DESELECT')
for p, *_ in out_objs:
    p.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                          export_image_format='JPEG' if CFG.get('jpeg', True) else 'AUTO', export_jpeg_quality=88)
tot = sum(len(p.data.polygons) for p, *_ in out_objs)
print('写好了 %s：%d 块、%d 个三角形；分组 %s' % (OUT, len(out_objs), tot, REP))
