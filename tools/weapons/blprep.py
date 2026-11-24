# 车内饰零件的 Blender 预处理（用户 11-23：「很粗糙 你从 sketchfeb 找模型去替代不要自己建模 然后用 blender」）：
#   Sketchfab 上的原模型 → 只留要的那几块、截掉用不上的（卡车座椅的气囊底座……）、摆正方向、缩到真实尺寸、定原点、没贴图的上色、减面
#   → optics.mjs 的原模型缓存 cache/<键>/model.glb（之后照常 BUILD=<键> node tools/weapons/optics.mjs 出 models/optics/<键>.glb）
#   用法（仓库根目录）：blender -b -P tools/weapons/blprep.py -- <键> [<键> …]
#     配置：optics.json 的 sources[<键>].blprep；原模型缓存 cache/<键>_src/model.glb，没有的从 Sketchfab 下载——密钥只从环境变量 SKETCHFAB_TOKEN 读
#   blprep（Blender 坐标：Z 朝上；导出 glTF 时 Blender +Z → +Y、−Y → +Z）：
#     keep / drop     物体名正则（留哪些 / 去哪些）
#     box             [x0, x1, y0, y1, z0, z1]：只留包围盒中心在盒子里的物体（原模型坐标）
#     rot             [["z", 180], …]：绕世界轴转（度，先转）
#     fit             {"axis": "x" / "y" / "z" / "max", "size": 米}：按包围盒在这根轴上的长度缩到真实尺寸；或 scale 直接乘
#     cut             [{"axis": "z", "below": 米}]：缩放、定原点以后按平面切掉下面（above：上面）那一截（bisect，切口不补面）
#     origin          {"x": "center" / "min" / "max" / 米, "y": …, "z": …}：原点放到包围盒的哪儿（缩放后、切之前）；
#                     "seat"：x 取中心，z 取坐垫顶面（前一半里最高的点），y 取坐垫前后的中心
#     colors          {"材质名正则": [r, g, b, 粗糙度]}：没贴图的模型上色（断开底色贴图）
#     tris            目标三角形数（Decimate 折叠）
#     texMax          贴图最长边（默认 1024，大的缩小）
import bpy, bmesh, sys, os, re, json, math, urllib.request, mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, 'optics.json'), encoding='utf-8'))


def log(*a):
    print('[blprep]', *a, flush=True)


def source(key):
    S = CFG['sources'][key]
    f = os.path.join(HERE, 'cache', key + '_src', 'model.glb')
    if os.path.exists(f):
        return f
    tok = os.environ.get('SKETCHFAB_TOKEN')
    if not tok:
        raise SystemExit('缓存里没有 %s 的原模型：设好环境变量 SKETCHFAB_TOKEN 再运行，或者把下载的 model.glb 放进 %s' % (key, os.path.dirname(f)))
    req = urllib.request.Request('https://api.sketchfab.com/v3/models/%s/download' % S['uid'], headers={'Authorization': 'Token ' + tok})
    j = json.load(urllib.request.urlopen(req, timeout=60))
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with urllib.request.urlopen(j['glb']['url'], timeout=600) as r, open(f, 'wb') as o:
        o.write(r.read())
    return f


def bbox(objs):   # 按顶点算（改过网格以后 bound_box 要等依赖图刷新才变）
    lo = mathutils.Vector((1e18, 1e18, 1e18))
    hi = -lo
    for ob in objs:
        M = ob.matrix_world
        for v in ob.data.vertices:
            w = M @ v.co
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
    return lo, hi


def verts(objs):
    out = []
    for ob in objs:
        M = ob.matrix_world
        out.extend(M @ v.co for v in ob.data.vertices)
    return out


def run(key):
    P = CFG['sources'][key].get('blprep', {})
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source(key))
    sc = bpy.context.scene
    objs = [o for o in sc.objects if o.type == 'MESH']
    if P.get('keep'):
        objs = [o for o in objs if any(re.search(r, o.name) for r in P['keep'])]
    objs = [o for o in objs if not any(re.search(r, o.name) for r in P.get('drop', []))]
    if P.get('box'):
        x0, x1, y0, y1, z0, z1 = P['box']
        def inside(o):
            lo, hi = bbox([o])
            c = (lo + hi) / 2
            return x0 <= c.x <= x1 and y0 <= c.y <= y1 and z0 <= c.z <= z1
        objs = [o for o in objs if inside(o)]
    assert objs, '%s：一个物体都没留下' % key
    for o in list(sc.objects):
        if o.type == 'MESH' and o not in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    # 父子关系、实例都摊平成各自独立的网格，变换烘进顶点
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.make_single_user(object=True, obdata=True)
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in [o for o in sc.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o, do_unlink=True)
    # 转
    R = mathutils.Matrix.Identity(4)
    for ax, deg in P.get('rot', []):
        R = mathutils.Matrix.Rotation(math.radians(deg), 4, ax.upper()) @ R
    # 缩
    lo, hi = bbox(objs)
    s = float(P.get('scale', 1.0))
    if P.get('fit'):
        F = P['fit']
        # 先转再量：fit 的轴是转过以后的；of：只量名字合这个正则的物体（方向盘只量轮缘，不算转向柱）
        vs = [R @ v for v in verts([o for o in objs if re.search(F.get('of', '.'), o.name)])]
        a = 'xyz'.index(F['axis']) if F['axis'] != 'max' else None
        ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
        s = F['size'] / (max(ext) if a is None else ext[a])
    M = mathutils.Matrix.Scale(s, 4) @ R
    for o in objs:
        o.data.transform(M)
        o.data.update()
    # 原点
    O = P.get('origin', {})
    lo, hi = bbox(objs)
    off = mathutils.Vector((0, 0, 0))
    if O == 'seat':
        vs = verts(objs)
        ymid = (lo.y + hi.y) / 2
        front = [v for v in vs if v.y > ymid]   # 坐垫在 +Y 那一半（座椅朝 +Y：导出后乘员朝 −Z）
        top = max(v.z for v in front)
        cush = [v for v in front if v.z > top - 0.05]
        off = mathutils.Vector(((lo.x + hi.x) / 2, (min(v.y for v in cush) + max(v.y for v in cush)) / 2, top))
    else:
        if O.get('of'):   # 原点按名字合这个正则的那几块的包围盒（踏板按踏板面，不算长长的转轴）
            lo, hi = bbox([o for o in objs if re.search(O['of'], o.name)])
        for i, ax in enumerate('xyz'):
            m = O.get(ax, 'center')
            off[i] = m if isinstance(m, (int, float)) else (lo[i] if m == 'min' else hi[i] if m == 'max' else (lo[i] + hi[i]) / 2)
    T = mathutils.Matrix.Translation(-off)
    for o in objs:
        o.data.transform(T)
        o.data.update()
    # 切
    for C in P.get('cut', []):
        i = 'xyz'.index(C['axis'])
        below = 'below' in C
        val = C['below'] if below else C['above']
        no = mathutils.Vector((0, 0, 0))
        no[i] = 1.0
        co = mathutils.Vector((0, 0, 0))
        co[i] = val
        for o in objs:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_inner=below, clear_outer=not below)
            bm.to_mesh(o.data)
            bm.free()
            o.data.update()
    objs = [o for o in objs if len(o.data.polygons)]
    # 上色（没贴图的模型）
    for rx, col in P.get('colors', {}).items():
        for m in bpy.data.materials:
            if not re.search(rx, m.name) or not m.use_nodes:
                continue
            bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if not bsdf:
                continue
            for l in list(bsdf.inputs['Base Color'].links):
                m.node_tree.links.remove(l)
            bsdf.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1)
            if len(col) > 3:
                bsdf.inputs['Roughness'].default_value = col[3]
            bsdf.inputs['Metallic'].default_value = col[4] if len(col) > 4 else 0.0
    # 贴图缩小（texMax，默认 1024：Roblox 导入时也会缩到 1024，原模型 4K 的贴图白占文件大小）
    tmax = int(P.get('texMax', 1024))
    for img in bpy.data.images:
        w, h = img.size[:]
        if max(w, h) > tmax:
            k = tmax / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
    # 减面
    tri = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    want = int(P.get('tris', 0))
    if want and tri > want:
        r = want / tri
        for o in objs:
            md = o.modifiers.new('dec', 'DECIMATE')
            md.ratio = r
            md.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=md.name)
    tri2 = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    lo, hi = bbox(objs)
    out = os.path.join(HERE, 'cache', key, 'model.glb')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
    log('%s：%d → %d 个三角形，大小 %.3f × %.3f × %.3f 米（Blender x、y、z），写好 %s' % (key, tri, tri2, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, out))


for k in sys.argv[sys.argv.index('--') + 1:]:
    run(k)
