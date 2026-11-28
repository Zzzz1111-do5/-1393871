# Sketchfab 下载的地面载具原模型 → 游戏用的 GLB（Blender 无头跑；用户 11-23：「我记得 m2a3 现实中是有动画的你重新从 sketchfeb 下载这个吧而且有导弹」
#   「你直接把这个改成 m3 好了」——布雷德利换成 mansoorsajidp 的 M3，炮塔左边的陶式发射箱是单独一块，能竖起来）
#   用法：/opt/blender/blender -b --factory-startup -P tools/models/blveh.py -- <模型键> <原模型 .glb> <输出 .glb> <分组结果 .json>
#   配置 tools/models/blveh.json[<模型键>]：
#     rotZ 绕竖轴转几度（车头朝 −Z）、length 真车全长（米，含炮管不算；按车体长缩放）、groups { 组名: [原节点名…] }（Turret / Gun / Tow / Body；
#     没点名的归 Body）、wheels [原节点名…]（每个一组 Wnn，自己转；写 "@W01" 是 split 拆到 W01 组的所有块）、decimate { 原节点名: 保留比例 }、texMax 贴图最大边长、drop [不要的节点]
#     scale 原模型单位 → 米直接乘（给了就不按 length 缩）；lengthRef [节点…]：按这几块的前后长度缩到 length（不给按车体 + 车轮）
#     dedupe true：重合的三角形只留一份（游戏里扒的模型常有两三层一模一样的面，Roblox 里会闪）；dedupeFirst [节点…] 先留谁的
#     split [{ from: [节点…] | "*"（所有网格）, to: 组名, box: [x0, x1, y0, y1, z0, z1], label: 块名前缀 }]：整个连通块（按位置焊接 1 毫米）落在框里的面拆出来归 to 组
#       （给了 center: true：连通块包围盒的中心落在框里就算——车体炮塔混在一块的模型，炮塔外壳的块往下伸到甲板以下，整块框不住）
#       （给了 label：拆出来的单独成块、块名用这个前缀，比如铠甲的搜索雷达 Radar，kinds 里给它 k）
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

# 按框拆：整个连通块落在框里的面挪到新物体（名字 <原名>.<组>，给了 label 是 <原名>.<label>），归 to 组
split_group = {}
split_label = {}
for rule in CFG.get('split', []):
    bx = rule['box']
    lo = Vector((bx[0], -bx[5], bx[2]))   # glTF (x, y, z) → Blender (x, −z, y)
    hi = Vector((bx[1], -bx[4], bx[3]))
    # from 写 "*"：所有还没被前面的规则拆走的网格物体都试（11-27 87 式侦察警戒车这种上千个小物体、节点名是乱码、按名字点不过来的模型；
    #   先写的规则先挑：炮管先拆进 Gun，后面框住整个炮塔的规则就不会再把炮管拿走）
    names = [o.name for o in bpy.data.objects if o.type == 'MESH' and len(o.data.polygons) and o.name not in split_group] \
        if rule['from'] == '*' else rule['from']
    for name in names:
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
        if rule.get('center'):   # 只看连通块包围盒的中心在不在框里（炮塔外壳往下伸到甲板高度以下、整块框不住；甲板上扁平的零件中心低，框的下沿卡掉）
            inside = {r for r in blo if all(lo[i] <= (blo[r][i] + bhi[r][i]) / 2 <= hi[i] for i in range(3))}
        else:
            inside = {r for r in blo if all(lo[i] <= blo[r][i] and bhi[r][i] <= hi[i] for i in range(3))}
        chosen = {f.index for f, ks in zip(bm.faces, fk) if find(ks[0]) in inside}
        bm.free()
        if not chosen:
            if CFG.get('verbose'):
                print('  拆 %s → %s：框里没有整块的零件' % (name, rule['to']))
            continue
        new = o.copy()
        new.data = o.data.copy()
        new.name = '%s.%s' % (name, rule.get('label', rule['to']))
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
        if rule.get('label'):
            split_label[new.name] = rule['label']
        if name in CFG.get('decimate', {}):   # 拆出来的块照原来那块的比例减面
            CFG['decimate'][new.name] = CFG['decimate'][name]
        print('  拆 %s → %s：%d 个面（%d 个零件）' % (name, rule['to'], len(chosen), len(inside)))
# 整块都拆走了的原物体（比如两边的主动轮各拆成一个轮子）：删掉，不然导出一块空网格
for o in [x for x in bpy.data.objects if x.type == 'MESH' and len(x.data.polygons) == 0]:
    bpy.data.objects.remove(o, do_unlink=True)
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
# "@<组名>"：split 拆到这个组的所有块（from "*" 拆出来的一个轮子是好几十个物体，名字点不过来）
WHEEL_SETS = [[m for n in ws for m in ([k for k, g in split_group.items() if g == n[1:]] if n.startswith('@') else [n])] for ws in WHEEL_SETS]
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

# 迷彩（camo { mats: [材质名…], cols: [[r, g, b] 底色, 第二色, 第三色], share: [底色、第二色、第三色各占多少], tile: 一张图铺多大（米）, size: 贴图边长 }）：
#   原模型没有贴图（黄鼠狼 1A3：Sketchfab 的 GLB、源文件里都只有几何，材质是 Sketchfab 随手给的粉彩色）——
#   这几种材质的块合成一种材质，贴一张自己生成的三色迷彩：
#   · 图：整数波矢的余弦波叠加（四方连续，铺开没有接缝），按分位数切成底色 / 第二色两大块，另一层噪声切出第三色（黑）的小块；
#     边是硬的（抗锯齿一个像素），加一点大尺度的深浅（旧漆、泥）和细颗粒
#   · UV：按世界坐标盒式投影（每个面看法线主要朝哪：顶面用 X、前后，侧面用前后、高度，前后面用 X、高度），一格 = tile 米，
#     朝正反两面错开一点（左右两边的斑不一样）——不展 UV：细节多的模型（12 万三角形、上千个小零件）展出来几千个小岛，一张图装不下
#     （试过 Smart UV + Cycles 烘焙：小零件一块只分到几个像素，糊成一片）
#   原来的 UV 层删掉（Roblox 只认第一套 UV）——所以只用在整辆车本来就没有贴图的模型上
CAMO = CFG.get('camo')
if CAMO:
    import numpy as np
    cmats = set(CAMO['mats'])
    cobjs = [o for o in objs if any(m and m.name in cmats for m in o.data.materials)]
    SZ = int(CAMO.get('size', 1024))
    TILE = float(CAMO.get('tile', 5.0)) * S   # 一张图铺多大（格）
    rng = np.random.default_rng(int(CAMO.get('seed', 7)))
    yy, xx = np.mgrid[0:SZ, 0:SZ] / SZ

    def field(n, kmax, slope):   # 四方连续的噪声：整数波矢的余弦波，振幅按 1/|k|^slope
        f = np.zeros((SZ, SZ))
        for _ in range(n):
            kx, ky = rng.integers(-kmax, kmax + 1, 2)
            if kx == 0 and ky == 0:
                continue
            f += (kx * kx + ky * ky) ** (-slope / 2) * np.cos(2 * np.pi * (kx * xx + ky * yy) + rng.uniform(0, 2 * np.pi))
        return (f - f.mean()) / f.std()

    share = CAMO.get('share', [0.45, 0.35, 0.20])
    f1 = field(48, 7, 1.2) + 0.18 * field(40, 18, 0.6)   # 两大块（边上带点毛糙）
    f2 = field(48, 9, 1.1) + 0.2 * field(40, 20, 0.6)    # 第三色的小块
    t1 = np.quantile(f1, share[0] / (share[0] + share[1]))
    t2 = np.quantile(f2, 1 - share[2])
    px1 = 1.0 / (np.abs(np.gradient(f1)[0]) + np.abs(np.gradient(f1)[1]) + 1e-6)   # 一个像素宽的过渡（抗锯齿）
    px2 = 1.0 / (np.abs(np.gradient(f2)[0]) + np.abs(np.gradient(f2)[1]) + 1e-6)
    a1 = np.clip((f1 - t1) * px1 * 0.7 + 0.5, 0, 1)
    a2 = np.clip((f2 - t2) * px2 * 0.7 + 0.5, 0, 1)
    # 8 位的图（bpy.data.images.new 默认）pixels 里存的就是 sRGB 值，不换线性（换了整张暗一大截）
    c0, c1, c2 = (np.asarray(c, dtype=np.float64) / 255 for c in CAMO['cols'])
    col = c0[None, None, :] * (1 - a1[..., None]) + c1[None, None, :] * a1[..., None]
    col = col * (1 - a2[..., None]) + c2[None, None, :] * a2[..., None]
    shade = 1 + 0.07 * np.tanh(field(30, 3, 1.0)) + 0.025 * rng.standard_normal((SZ, SZ))   # 旧漆深浅、颗粒
    col = np.clip(col * shade[..., None], 0, 1)
    img = bpy.data.images.new('camo_' + KEY, SZ, SZ)
    rgba = np.concatenate([col, np.ones((SZ, SZ, 1))], axis=2)[::-1]   # Blender 的图从下往上存
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.pack()
    cm = bpy.data.materials.new('camo_' + KEY)
    cm.use_nodes = True
    nt = cm.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    uvn = nt.nodes.new('ShaderNodeUVMap')
    uvn.uv_map = 'CamoUV'
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.8
    bsdf.inputs['Metallic'].default_value = 0.0
    outn = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(uvn.outputs['UV'], tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(bsdf.outputs['BSDF'], outn.inputs['Surface'])
    OFF = {(0, 1): (0.0, 0.0), (0, -1): (0.37, 0.61), (1, 1): (0.13, 0.29), (1, -1): (0.71, 0.05), (2, 1): (0.53, 0.83), (2, -1): (0.19, 0.47)}
    for o in cobjs:
        for i, m in enumerate(o.data.materials):
            if m and m.name in cmats:
                o.data.materials[i] = cm
        for uv in list(o.data.uv_layers):
            o.data.uv_layers.remove(uv)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        uvl = bm.loops.layers.uv.new('CamoUV')
        for f in bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            sg = 1 if n[ax] >= 0 else -1
            du, dv = OFF[(ax, sg)]
            for lp in f.loops:
                p = lp.vert.co
                if ax == 2:
                    u, v = p.x, p.y
                elif ax == 0:
                    u, v = p.y, p.z
                else:
                    u, v = p.x, p.z
                lp[uvl].uv = (u / TILE + du, v / TILE + dv)
        bm.to_mesh(o.data)
        bm.free()
    print('迷彩：%d 块合成一种材质，贴 %d² 的四方连续迷彩（一格 %.1f 米）' % (len(cobjs), SZ, TILE / S))

# 贴图调色（texTint [{ img: 贴图名里的一段, rgb: [r, g, b] }]：原模型贴图是没上漆的灰色（豹 1），按真车涂装把中位色调到 rgb，
#   脏污、磨损、阴影这些明暗细节照留——每个通道乘同一个倍数）
for rule in CFG.get('texTint', []):
    import numpy as np
    for im in bpy.data.images:
        if rule['img'] not in im.name or im.size[0] == 0:
            continue
        px = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        med = np.median(px[px[:, 3] > 0.5][:, :3], axis=0)
        k = np.array(rule['rgb'], dtype=np.float32) / 255.0 / np.maximum(med, 1e-3)
        px[:, :3] = np.clip(px[:, :3] * k, 0, 1)
        im.pixels.foreach_set(px.ravel())
        im.pack()
        print('  调色 %s：中位色 %s → %s' % (im.name, [int(x * 255) for x in med], rule['rgb']))

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
    lab = split_label.get(o.name) or LABELS.get(o.name.split('.')[0], g)
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


def tri(p):   # 三角化（就地），返回三角形数
    bm = bmesh.new()
    bm.from_mesh(p.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(p.data)
    bm.free()
    return len(p.data.polygons)


def join(lst2):
    bpy.ops.object.select_all(action='DESELECT')
    for p in lst2:
        p.select_set(True)
    bpy.context.view_layer.objects.active = lst2[0]
    if len(lst2) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


for (g, mat, lab), lst in sorted(buckets.items()):
    # 每块先三角化，按三角形数装箱（每箱 ≤ TRI_MAX）再合并；一块自己就超了才按连通块拆
    #   （原来先全部合成一块、超了再按连通块拆：铠甲的车体上千个小零件，Blender 的按连通块拆分跑十几分钟）
    items = []
    for p in lst:
        n = tri(p)
        if n > TRI_MAX:
            bpy.ops.object.select_all(action='DESELECT')
            p.select_set(True)
            bpy.context.view_layer.objects.active = p
            bpy.ops.mesh.separate(type='LOOSE')
            items += [(len(x.data.polygons), x) for x in bpy.context.selected_objects]
        else:
            items.append((n, p))
    items.sort(key=lambda it: -it[0])
    packs = []
    for n, p in items:
        for pk in packs:
            if pk[0] + n <= TRI_MAX:
                pk[0] += n
                pk[1].append(p)
                break
        else:
            packs.append([n, [p]])
    pieces = [join(lst2) for _, lst2 in packs]
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
