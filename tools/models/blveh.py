# Sketchfab 下载的地面载具原模型 → 游戏用的 GLB（Blender 无头跑；用户 11-23：「我记得 m2a3 现实中是有动画的你重新从 sketchfeb 下载这个吧而且有导弹」
#   「你直接把这个改成 m3 好了」——布雷德利换成 mansoorsajidp 的 M3，炮塔左边的陶式发射箱是单独一块，能竖起来）
#   用法：/opt/blender/blender -b --factory-startup -P tools/models/blveh.py -- <模型键> <原模型 .glb> <输出 .glb> <分组结果 .json>
#   配置 tools/models/blveh.json[<模型键>]：
#     rotZ 绕竖轴转几度（车头朝 −Z）、length 真车全长（米，含炮管不算；按车体长缩放）、groups { 组名: [原节点名…] }（Turret / Gun / Tow / Body；
#     没点名的归 Body）、wheels [原节点名…]（每个一组 Wnn，自己转）、decimate { 原节点名: 保留比例 }、texMax 贴图最大边长、drop [不要的节点]
#     scale 原模型单位 → 米直接乘（给了就不按 length 缩）；lengthRef [节点…]：按这几块的前后长度缩到 length（不给按车体 + 车轮）
#     dedupe true：重合的三角形只留一份（游戏里扒的模型常有两三层一模一样的面，Roblox 里会闪）；dedupeFirst [节点…] 先留谁的
#     split [{ from: [节点…], to: 组名, box: [x0, x1, y0, y1, z0, z1] }]：整个连通块（按位置焊接 1 毫米）落在框里的面拆出来归 to 组
#       （炮管和车体烘焙成一块的）；框是原模型 glTF 坐标（Y 上，原模型的车头朝哪就是哪）
#     labels { 节点名: 块名前缀 }：这些节点单独成块、块名用这个前缀（组照旧），kinds { 前缀: k }：元数据里这些块带 k（int = 原模型自带的车内）
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


def pkey(co):   # 顶点位置焊接键（1 毫米）
    return (round(co.x * 1000), round(co.y * 1000), round(co.z * 1000))


# 重合的三角形只留一份
if CFG.get('dedupe'):
    first = CFG.get('dedupeFirst', [])
    seen = set()
    for o in sorted(objs, key=lambda o: (first.index(o.name) if o.name in first else len(first), o.name)):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        dead = []
        for f in bm.faces:
            k = tuple(sorted(pkey(v.co) for v in f.verts))
            if k in seen:
                dead.append(f)
            else:
                seen.add(k)
        if dead:
            bmesh.ops.delete(bm, geom=dead, context='FACES')
            bm.to_mesh(o.data)
            print('  去重 %s：去掉 %d 个重合的面，剩 %d' % (o.name, len(dead), len(bm.faces)))
        bm.free()
    for o in list(objs):
        if len(o.data.polygons) == 0:
            bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.data.objects if o.type == 'MESH']

# 按框拆：整个连通块落在框里的面挪到新物体（名字 <原名>.<组>），归 to 组
split_group = {}
for rule in CFG.get('split', []):
    bx = rule['box']
    lo = Vector((bx[0], -bx[5], bx[2]))   # glTF (x, y, z) → Blender (x, −z, y)
    hi = Vector((bx[1], -bx[4], bx[3]))
    for name in rule['from']:
        o = bpy.data.objects.get(name)
        if not o:
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        parent = {}

        def find(a):
            while parent.get(a, a) != a:
                parent[a] = parent.get(parent[a], parent[a])
                a = parent[a]
            return a
        fk = []
        for f in bm.faces:
            ks = [pkey(v.co) for v in f.verts]
            fk.append(ks)
            r0 = find(ks[0])
            for k in ks[1:]:
                r = find(k)
                if r != r0:
                    parent[r] = r0
        blo, bhi = {}, {}
        for f, ks in zip(bm.faces, fk):
            r = find(ks[0])
            for v in f.verts:
                c = v.co
                a, b = blo.get(r), bhi.get(r)
                blo[r] = Vector((min(a.x, c.x), min(a.y, c.y), min(a.z, c.z))) if a else c.copy()
                bhi[r] = Vector((max(b.x, c.x), max(b.y, c.y), max(b.z, c.z))) if b else c.copy()
        inside = {r for r in blo if all(lo[i] <= blo[r][i] and bhi[r][i] <= hi[i] for i in range(3))}
        chosen = {f.index for f, ks in zip(bm.faces, fk) if find(ks[0]) in inside}
        bm.free()
        if not chosen:
            print('  拆 %s → %s：框里没有整块的零件' % (name, rule['to']))
            continue
        new = o.copy()
        new.data = o.data.copy()
        new.name = '%s.%s' % (name, rule['to'])
        for col in o.users_collection:
            col.objects.link(new)
        for ob, keep in ((o, False), (new, True)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.faces.ensure_lookup_table()
            dead = [f for f in bm.faces if (f.index in chosen) != keep]
            bmesh.ops.delete(bm, geom=dead, context='FACES')
            bm.to_mesh(ob.data)
            bm.free()
        split_group[new.name] = rule['to']
        if name in CFG.get('decimate', {}):   # 拆出来的块照原来那块的比例减面
            CFG['decimate'][new.name] = CFG['decimate'][name]
        print('  拆 %s → %s：%d 个面（%d 个零件）' % (name, rule['to'], len(chosen), len(inside)))
objs = [o for o in bpy.data.objects if o.type == 'MESH']

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
# 分组：每块原网格 → 组（按框拆出来的归拆到的组）
group_of = {}
for g, names in CFG.get('groups', {}).items():
    for n in names:
        group_of[n] = g
group_of.update(split_group)
body_names = set(n for n in [o.name for o in objs] if n not in group_of and n not in wheel_of)


def bbox(objs_):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs_:
        for v in o.data.vertices:
            lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
            hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    return lo, hi


blo, bhi = bbox([o for o in objs if o.name in body_names or o.name in wheel_of])
if 'scale' in CFG:   # 原模型单位直接换算
    k = float(CFG['scale']) * S
elif CFG.get('lengthRef'):   # 按参考件（比如上车体）的前后长度
    rlo, rhi = bbox([o for o in objs if o.name in CFG['lengthRef']])
    k = CFG['length'] / (rhi.y - rlo.y) * S
else:
    k = CFG['length'] / (bhi.y - blo.y) * S   # Blender 里 +Y 是车头（导出 glTF 后是 −Z）
lo_all, hi_all = bbox(objs)
off = Vector(((blo.x + bhi.x) / 2, (blo.y + bhi.y) / 2, lo_all.z))
M = Matrix.Scale(k, 4) @ Matrix.Translation(-off)
for o in objs:
    o.data.transform(M)
print('缩放 %.4f（原模型车体长 %.3f → %.2f 米）；原点（Blender 坐标、转向后）%s' % (k, bhi.y - blo.y, (bhi.y - blo.y) * k / S, tuple(round(x, 4) for x in off)))

# 没贴图的材质改色（matColor { 材质名: [r, g, b]（sRGB 0–255）}：原模型白的玻璃之类）
for mn, rgb in CFG.get('matColor', {}).items():
    m = bpy.data.materials.get(mn)
    bsdf = m and m.use_nodes and next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf:
        lin = [((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92 for c in rgb]
        bsdf.inputs['Base Color'].default_value = (lin[0], lin[1], lin[2], 1)

# 贴图缩小
tmax = int(CFG.get('texMax', 1024))
for im in bpy.data.images:
    if im.size[0] > tmax or im.size[1] > tmax:
        s = tmax / max(im.size[0], im.size[1])
        im.scale(max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s)))
        im.pack()

LABELS = CFG.get('labels', {})   # 单独成块的节点 → 块名前缀
KINDS = CFG.get('kinds', {})     # 块名前缀 → 元数据里的 k


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
    lab = LABELS.get(o.name.split('.')[0], g)
    # 按材质拆开
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    if len(o.data.materials) > 1:
        bpy.ops.mesh.separate(type='MATERIAL')
    for p in [x for x in bpy.context.selected_objects]:
        mat = p.data.materials[0].name if p.data.materials else ''
        buckets.setdefault((g, mat, lab), []).append(p)
    if o.name in wheel_of:
        lo, hi = bbox([o])
        if g in wheel_info:   # 一个轮子几块（轮毂、胶圈）：包围盒合起来
            lo0, hi0 = wheel_info[g]['_lo'], wheel_info[g]['_hi']
            lo = Vector((min(lo.x, lo0.x), min(lo.y, lo0.y), min(lo.z, lo0.z)))
            hi = Vector((max(hi.x, hi0.x), max(hi.y, hi0.y), max(hi.z, hi0.z)))
        wheel_info[g] = {'_lo': lo, '_hi': hi, 'c': [round(x, 3) for x in to_glb((lo + hi) / 2)], 'r': round(max(hi.y - lo.y, hi.z - lo.z) / 2, 3)}

out_objs = []
counter = {}
for (g, mat, lab), lst in sorted(buckets.items()):
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
        counter[lab] = counter.get(lab, 0) + 1
        p.name = 'V_%s__%s_%d' % (KEY, lab, counter[lab])
        p.data.name = p.name
        # 原点放到包围盒中心
        lo, hi = bbox([p])
        c = (lo + hi) / 2
        p.data.transform(Matrix.Translation(-c))
        p.location = c
        out_objs.append((p, g, mat, lo, hi, lab))

# 物体挪了原点（location）以后 matrix_world 要等视图层刷新才变：不刷新的话下面按世界坐标算转轴时用的是旧矩阵（顶点都在原点附近）
bpy.context.view_layer.update()

# 分组结果
rep = {'parts': {}, 'wheels': {g: {'c': w['c'], 'r': w['r']} for g, w in wheel_info.items()}}
for p, g, mat, lo, hi, lab in out_objs:
    pn = p.name.split('__', 1)[1]
    e = {'g': g, 'c': [round(x, 3) for x in to_glb((lo + hi) / 2)], 's': [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)]}
    if lab in KINDS:
        e['k'] = KINDS[lab]
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
    for p, g, mat, lo, hi, lab in out_objs:
        if g == names_group and lab == g:   # 单独成块的（车内）不算转轴
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
def src_pt(p):   # 原模型 glTF 坐标 → 成品坐标（Blender，格）
    return M @ (rot @ Vector((p[0], -p[2], p[1])))


# 配置里直接给的转轴（原模型 glTF 坐标）：炮塔座圈中心 tur、炮耳轴 gun（炮口距离照算）
if 'tur' in CFG:
    rep['tur'] = [round(x, 3) for x in to_glb(src_pt(CFG['tur']))]
if 'gun' in CFG and gp:
    piv = src_pt(CFG['gun'])
    rep['gun'] = [round(x, 3) for x in to_glb(piv)]
    rep['muz'] = round(max(v.y for v in gp) - piv.y, 3)
# 别的点（瞄准镜、乘员眼位……）：原模型 glTF 坐标 → 元数据坐标（格）
for name, p in CFG.get('points', {}).items():
    rep.setdefault('pts', {})[name] = [round(x, 3) for x in to_glb(src_pt(p))]
# 原模型 glTF 坐标 → 元数据坐标（格）的仿射矩阵（三行，每行 x y z 常数）：内饰代码按原模型里量的器材位置（米）摆东西用
o0 = to_glb(src_pt((0, 0, 0)))
ax = [to_glb(src_pt(e)) for e in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
rep['src'] = [[round(ax[j][i] - o0[i], 5) for j in range(3)] + [round(o0[i], 5)] for i in range(3)]
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
