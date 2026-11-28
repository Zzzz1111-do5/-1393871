# Sketchfab 上下的楼房（glb）→ Roblox Studio「导入 3D」用的一个 GLB（models/bld/city.glb）+ 元数据（JSON，tools/models/sfbld_meta.py 写成 CityMeta.lua）
#   用户 11-26：「地图建模要精细 3a」——钢城的楼换成 Sketchfab 上 CC-BY 的写实楼房（带贴图），没导入时游戏里照旧用零件拼的（CityBuild.lua）
#   blender -b --python tools/models/sfbld.py -- <配置 json> <下载目录> <输出 glb> <输出元数据 json>
#   配置 tools/models/sfbld.json：[{ key, file, h 真高（米，没有就按原尺寸；车辆残骸给 len 真车全长）, rot 绕竖轴转几度（长边转到东西向以后再补的）, tris 最多几个三角形, name, author, url, uid }]
#     雪山的房子（tools/models/sfbld_snow.json → models/bld/snow.glb）多几项：drop 节点名里含这些字的去掉、plate 去掉自带的地台、
#     part 一块最多几个三角形（默认 19000：一种材质超过的按空间对半切开，不用为了凑 Roblox 一个网格两万面的上限去减面）
#     合掌村（tools/models/sfbld_vil.json → models/bld/village.glb）：mod 署名里的改动说明（drop 去掉的不是地台时照实写，比如「只取三座里的一座」），没有就照旧写「去掉自带的地台」
#   每座：所有网格合成一个、按配置转、缩到真高（米）再 × 2.8 换成格、占地中心挪到原点、底面贴地；超过 tris 的减面（collapse）；按材质切块，
#   块叫 B_<键>__Body_<号>（开服时 Imports.lua 收进 ReplicatedStorage.Imported.Bld.<键>，同 buildings.glb）；贴图最长边缩到 1024；
#   GLB 里各座沿 X 排开（Studio 里导进来不叠在一起）。坐标约定同 bld2glb.py：glTF 里 X 右、Y 上、−Z 正面（Blender 里 +Y 是正面）
import bpy, bmesh, json, math, sys, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
cfg_path, src_dir, out_glb, out_meta = argv[0], argv[1], argv[2], argv[3]
CFG = json.load(open(cfg_path))
S = 2.8   # 米 → 格

bpy.ops.wm.read_factory_settings(use_empty=True)
final = []   # 最后导出的对象
meta = {}
xoff = 0.0


def join_meshes(objs):
    """把一次导入的所有网格按世界坐标烘进一个新对象（父子关系、缩放、旋转都算进去）"""
    bm = bmesh.new()
    mats = []
    for o in objs:
        if o.type != 'MESH':
            continue
        dg = bpy.context.evaluated_depsgraph_get()
        me = o.evaluated_get(dg).to_mesh()
        me = me.copy()
        me.transform(o.matrix_world)
        # 材质号对到合并后的材质表
        remap = []
        for s in o.material_slots:
            m = s.material
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        for p in me.polygons:
            if remap:
                p.material_index = remap[min(p.material_index, len(remap) - 1)]
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new("joined")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("joined", me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(m)
    return ob


def world_bounds(o):
    bb = [o.matrix_world @ mathutils.Vector(v) for v in o.bound_box]
    lo = mathutils.Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = mathutils.Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    return lo, hi


def drop_objects(new, c):
    """配置 drop（节点名里含这些字的去掉）、plate（自带的地台：扁平、占地比别的部分大 1.3 倍以上的去掉）"""
    meshes = [o for o in new if o.type == 'MESH']
    out = []
    for o in meshes:
        if any(d in o.name for d in c.get("drop", [])):
            print("  去掉", o.name)
            continue
        out.append(o)
    if c.get("plate"):
        keep = []
        bnd = {o: world_bounds(o) for o in out}
        for o in out:
            lo, hi = bnd[o]
            e = hi - lo
            if e.z < 0.06 * max(e.x, e.y):
                rest = [bnd[q] for q in out if q is not o]
                if rest:
                    rlo = mathutils.Vector((min(b[0].x for b in rest), min(b[0].y for b in rest), 0))
                    rhi = mathutils.Vector((max(b[1].x for b in rest), max(b[1].y for b in rest), 0))
                    if (e.x * e.y) > 1.3 * (rhi.x - rlo.x) * (rhi.y - rlo.y):
                        print("  去掉地台", o.name, round(e.x, 2), round(e.y, 2))
                        continue
            keep.append(o)
        out = keep
    return out


def split_big(p, cap):
    """一块超过 cap 个三角形（Roblox 一个网格最多两万）：沿最长的方向按面中心对半切，切到每块都够小"""
    out = []
    todo = [p]
    while todo:
        o = todo.pop()
        o.data.calc_loop_triangles()
        if len(o.data.loop_triangles) <= cap:
            out.append(o)
            continue
        lo, hi = world_bounds(o)
        e = hi - lo
        ax = 0 if e.x >= e.y and e.x >= e.z else (1 if e.y >= e.z else 2)
        cs = sorted((f.center[ax], f.index) for f in o.data.polygons)
        mid = cs[len(cs) // 2][0]
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)   # 按面选（只设了面的选中标记）
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='DESELECT')
        bpy.ops.object.mode_set(mode='OBJECT')
        n = 0
        for f in o.data.polygons:
            if f.center[ax] < mid or (f.center[ax] == mid and n < len(cs) // 2):
                f.select = True
                n += 1
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        two = [q for q in bpy.context.selected_objects if q.type == 'MESH']
        if len(two) < 2:   # 切不开（全在一点上）：照原样
            out.append(o)
            continue
        todo += two
    return out


for c in CFG:
    key = c["key"]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src_dir + "/" + c["file"])
    new = [o for o in bpy.data.objects if o not in before]
    use = drop_objects(new, c)
    ob = join_meshes(use)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    me = ob.data
    # 长边转到东西向（X），再补配置的转角
    vs = [v.co for v in me.vertices]
    lo = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    rot = math.radians(c.get("rot", 0))
    if (hi.y - lo.y) > (hi.x - lo.x) * 1.05:
        rot += math.pi / 2
    me.transform(mathutils.Matrix.Rotation(rot, 4, 'Z'))
    vs = [v.co for v in me.vertices]
    lo = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    k = (c["h"] / (hi.z - lo.z)) if c.get("h") else 1.0
    if c.get("len"):   # 车辆残骸（tools/models/sfbld_wrecks.json）：按真车全长（米）缩放——长边缩到 len（车高各家模型篷布、货箱不一样，按长更准）
        k = c["len"] / max(hi.x - lo.x, hi.y - lo.y)
    k *= S
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    me.transform(mathutils.Matrix.Translation((-cx, -cy, -lo.z)))
    me.transform(mathutils.Matrix.Scale(k, 4))
    if c.get("clipBelow"):   # 实景扫描连着的一块地皮（飞机残骸）：整个面都在最低点往上 clipBelow 米以内的删掉，再把剩下的贴回地面、占地重新居中
        bm = bmesh.new()
        bm.from_mesh(me)
        lim = c["clipBelow"] * S
        dead = [f for f in bm.faces if max(v.co.z for v in f.verts) < lim]
        bmesh.ops.delete(bm, geom=dead, context='FACES')
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
        bm.to_mesh(me)
        bm.free()
        vs = [v.co for v in me.vertices]
        lo2 = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi2 = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        me.transform(mathutils.Matrix.Translation((-(lo2.x + hi2.x) / 2, -(lo2.y + hi2.y) / 2, -lo2.z)))
        print("  删掉地皮 %d 个面" % len(dead))
    # 减面
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    cap = c.get("tris", 16000)
    if tris > cap:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        md = ob.modifiers.new("dec", 'DECIMATE')
        md.ratio = cap / tris
        md.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
        ob.select_set(False)
    # 按材质切块
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = [o for o in bpy.context.selected_objects if o.type == 'MESH' and len(o.data.polygons) > 0]
    big = []
    for p in parts:
        big += split_big(p, c.get("part", 19000))
    parts = [o for o in big if len(o.data.polygons) > 0]
    W = D = H = 0
    allv = []
    pm = {}
    for i, p in enumerate(sorted(parts, key=lambda o: -len(o.data.polygons))):
        p.name = "B_%s__Body_%d" % (key, i + 1)
        p.data.name = p.name
        bpy.ops.object.select_all(action='DESELECT')
        p.select_set(True)
        bpy.context.view_layer.objects.active = p
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        bb = [p.matrix_world @ mathutils.Vector(v) for v in p.bound_box]
        plo = mathutils.Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        phi = mathutils.Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        allv += [plo, phi]
        ctr = (plo + phi) / 2
        sz = phi - plo
        # glTF 坐标：X 同、Y = Blender Z、Z = −Blender Y
        pm["Body_%d" % (i + 1)] = {"c": [round(ctr.x, 3), round(ctr.z, 3), round(-ctr.y, 3)], "s": [round(max(sz.x, 0.05), 3), round(max(sz.z, 0.05), 3), round(max(sz.y, 0.05), 3)]}
        p.location.x += xoff
        final.append(p)
    lo = mathutils.Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
    hi = mathutils.Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
    W, D, H = hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
    meta[key] = {"name": c.get("name", key), "w": round(W, 3), "h": round(H, 3), "d": round(D, 3), "o": [round(xoff, 3), 0, 0], "parts": pm,
                 "credit": "%s：%s，作者 %s（%s），CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）；改动：%s、换成 Roblox 的格、%s按材质切块、贴图缩到 1024" % (
                     c.get("name", key), c["title"], c["author"], c["url"], "按真车全长缩放" if c.get("len") else "按真高缩放",
                     (("减面到 %d 个三角形、" % cap) if tris > cap else "") + ((c["mod"] + "、") if c.get("mod") else ("去掉自带的地台、" if (c.get("plate") or c.get("drop")) else ""))),
                 "tris": min(tris, cap)}
    xoff += W + 60
    print("BLD %s %.0f x %.0f x %.0f 格  %d 块  %d 三角形" % (key, W, D, H, len(pm), min(tris, cap)))

# 贴图缩到最长边 1024
for img in bpy.data.images:
    try:
        w, h = img.size
        if max(w, h) > 1024:
            f = 1024 / max(w, h)
            img.scale(max(1, int(w * f)), max(1, int(h * f)))
    except Exception as e:
        print("img", img.name, e)

bpy.ops.object.select_all(action='DESELECT')
for o in final:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', use_selection=True, export_image_format='JPEG', export_jpeg_quality=86, export_apply=True)
json.dump(meta, open(out_meta, "w"), ensure_ascii=False, indent=1)
print("WROTE", out_glb, len(meta))
