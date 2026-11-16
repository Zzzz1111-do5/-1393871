# 第一人称持枪数据（通用版）：从 DuqueCD7 的「FPS Character Animation Pack」（Sketchfab，CC-BY-4.0）GLB 里抽——手枪、AK-47、Saps-12 霰弹枪
#   三个包用同一套角色骨架（Rigify 的 DEF-upper_arm / forearm / hand……）加各自的枪骨架；相机在 DEF-spine.006 的头上、不动，看 −Y、Z 朝上
#   （AK、Saps 的包里有 Camera 节点，位置正好在那儿；手枪包没有，照同一个位置算）；场景按骨架缩放换成米再乘 2.8（1 米 = 2.8 格）
#   输出两个 ModuleScript（格式同 FPSAnim.lua / FPSMesh.lua，FPSView 读）：
#     <id>_anim.lua：clips[Idle / Draw / Fire / Reload / AimIdle / AimFire / Holster / ……] 每帧枪的各零件、方块手臂各段相对相机的 CFrame；
#       len 手臂各段长、mesh 各网格在自己骨骼里的包围盒、muzzle 枪口（在枪身骨骼里）、sight 开镜时眼睛对准的两点（没有开镜动作的枪用）
#     <id>_mesh.lua：网格（按每个顶点权重最大的骨骼分成零件，坐标是那根骨骼的局部坐标）和贴图（调色板：256 色 + 每像素 1 字节，比原样 RGB 小三倍）
#   手不用原模型的手：游戏里画成 Roblox 方块形
# 用法：用 pip 装的 bpy（Blender 的 Python 模块）跑，不执行文件里的任何脚本：
#   python -I tools/fps/fps_bake_pack.py <包.glb> <pistol|ak47|saps> <输出 _anim.lua> <输出 _mesh.lua>
import bpy, sys, os, struct, base64
import numpy as np
from mathutils import Matrix, Vector

src, kid, out_anim, out_mesh = sys.argv[-4:]
S = 2.8
HAND_LEN = 0.36 / S

PACKS = {
  'pistol': {
    'title': 'FPS Character Animation Pack Pistol', 'url': 'https://sketchfab.com/3d-models/fps-character-animation-pack-pistol-e2815a5bea3a4e3895b3c29a2586e671',
    'pieces': { 'gun': 'DEF_Cuerpo', 'slide': 'DEF_Corredera', 'hammer': 'DEF_Martillo', 'mag1': 'DEF_Cargador', 'round': 'DEF_Bala', 'trig': 'DEF_Gatillo' },
    'clips': { 'Idle': 'Idle', 'Draw': 'Equip', 'Fire': 'Fire', 'Reload': 'Reload', 'AimIdle': 'Aim_Idle', 'AimFire': 'Aim_Fire', 'Holster': 'Change' },
    'every': { 'Reload': 2, 'Idle': 2, 'AimIdle': 2 }, 'tex': 512, 'decimate': 1.0,
  },
  'ak47': {
    'title': 'FPS Character Animation Pack Ak-47', 'url': 'https://sketchfab.com/3d-models/fps-character-animation-pack-ak-47-b95778a564094fc3a49d1d6a3b6a30ab',
    'pieces': { 'gun': 'Grip', 'bolt': 'bolt', 'trig': 'Trigger', 'mag1': 'Magazine' },
    'clips': { 'Idle': 'AK_Idle', 'Draw': 'AK_Equip', 'Fire': 'AK_Fire', 'Reload': 'AK_Reload', 'AimIdle': 'AK_Idle_Aim', 'AimFire': 'AK_Aim_Fire', 'Holster': 'AK_Hold' },
    'every': { 'Reload': 2, 'Idle': 2, 'AimIdle': 2 }, 'tex': 512, 'decimate': 0.55,
  },
  'saps': {
    'title': 'FPS Character Animation Pack Saps-12', 'url': 'https://sketchfab.com/3d-models/fps-character-animation-pack-saps-12-3e5ebbd4ace24f2e92eadb7252927b31',
    'pieces': { 'gun': 'Root', 'pump': 'DEF-Guardians', 'bolt': 'DEF-Bolt', 'gate': 'DEF-bedroom', 'trig': 'DEF-trigger', 'round': 'DEF-case' },
    'clips': { 'Idle': 'Idle', 'Draw': 'Equip', 'Fire': 'Fire', 'Pump': 'Accion_Fire', 'ReloadIn': 'IdleToReload', 'Reload': 'Reload', 'ReloadOut': 'ReloadToIdle', 'Holster': 'Hold' },
    'every': { 'Idle': 2 }, 'tex': 512, 'decimate': 0.4,
  },
}
P = PACKS[kid]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
char = max(arms, key=lambda o: len(o.data.bones))
gun = min(arms, key=lambda o: len(o.data.bones))
UNIT = 0.01 / char.matrix_world.to_scale().x      # 一个 Blender 单位是多少米（三个包的整体缩放不一样）
print('unit', UNIT, 'char', char.name, 'gun', gun.name)

def bone(arm, short):   # 骨骼名后面带了 _数字 的编号
    for b in arm.pose.bones:
        if b.name == short or b.name.rsplit('_', 1)[0] == short: return b
    raise KeyError(short)
def norm(M):
    loc, rot, _ = M.decompose()
    return Matrix.Translation(loc) @ rot.to_matrix().to_4x4()
def bw(arm, short): return norm(arm.matrix_world @ bone(arm, short).matrix)
def bh(arm, short): return arm.matrix_world @ bone(arm, short).head

def find_action(name):
    for a in bpy.data.actions:
        if a.name.endswith('_' + name) or a.name == name: return a
    raise KeyError(name)
def setact(name):
    a = find_action(name)
    for o in bpy.data.objects:
        for s in a.slots:
            if s.name_display == o.name:
                if not o.animation_data: o.animation_data_create()
                o.animation_data.action = a
                o.animation_data.action_slot = s
    return a

# 相机：待机第一帧 DEF-spine.006 的头（眼睛），看 −Y、Z 朝上 → Roblox 相机系（右 +X、上 +Y、看 −Z）
setact(P['clips']['Idle'])
sc.frame_set(0)
eye = bh(char, 'DEF-spine.006')
CW = Matrix(((-1, 0, 0, eye.x), (0, 0, 1, eye.y), (0, 1, 0, eye.z), (0, 0, 0, 1)))   # 列：右 = −X、上 = +Z、后 = +Y
C = CW.inverted()
K = UNIT * S        # Blender 单位 → 格

def frame_of(a, b, side_hint, center=None):
    y = (b - a).normalized()
    x = side_hint - y * side_hint.dot(y)
    if x.length < 1e-6: x = Vector((1, 0, 0)) - y * y.x
    x = x.normalized()
    z = x.cross(y)
    M = Matrix(((x.x, y.x, z.x, 0), (x.y, y.y, z.y, 0), (x.z, y.z, z.z, 0), (0, 0, 0, 1)))
    M.translation = center if center is not None else (a + b) / 2
    return M

def arm_boxes():
    out = {}
    for s, p in (('r', 'R'), ('l', 'L')):
        sh, el, wr = bh(char, 'DEF-upper_arm.' + p), bh(char, 'DEF-forearm.' + p), bh(char, 'DEF-hand.' + p)
        hint = bw(char, 'DEF-forearm.' + p).to_3x3() @ Vector((1, 0, 0))
        out[s + 'ua'] = (frame_of(sh, el, hint), (el - sh).length)
        out[s + 'fa'] = (frame_of(el, wr, hint), (wr - el).length)
        tip, i1, k1 = bh(char, 'DEF-f_middle.03.' + p), bh(char, 'DEF-f_index.01.' + p), bh(char, 'DEF-f_pinky.01.' + p)
        y = (tip - wr).normalized()
        out[s + 'h'] = (frame_of(wr, tip, i1 - k1, wr + y * (HAND_LEN / UNIT) / 2), HAND_LEN / UNIT)
    return out

def cf_list(M):   # Blender 单位的矩阵 → 位置（格）、四元数
    loc, rot, _ = M.decompose()
    q = rot.normalized()
    return [round(loc.x * K, 3), round(loc.y * K, 3), round(loc.z * K, 3), round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)]

clips, lens = {}, {}
for name, an in P['clips'].items():
    a = setact(an)
    every = P['every'].get(name, 1)
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    frames = list(range(f0, f1 + 1, every))
    if frames[-1] != f1: frames.append(f1)
    tracks = {}
    for f in frames:
        sc.frame_set(f)
        for k, bn in P['pieces'].items(): tracks.setdefault(k, []).append(cf_list(C @ bw(gun, bn)))
        for k, (M, L) in arm_boxes().items():
            tracks.setdefault(k, []).append(cf_list(C @ M))
            lens.setdefault(k, []).append(L * K)
    for k, arr in tracks.items():
        if all(max(abs(v - w) for v, w in zip(fr, arr[0])) < 2e-3 for fr in arr): tracks[k] = [arr[0]]
    fps = sc.render.fps / sc.render.fps_base
    clips[name] = { 'fps': fps / every, 'n': len(frames), 'dur': (f1 - f0) / fps, 'tracks': tracks }
    print(name, an, f0, f1, len(frames), 'fps', fps, 'static', [k for k, v in tracks.items() if len(v) == 1])
lens = { k: round(sum(v) / len(v), 3) for k, v in lens.items() }

# ---------------------------------------------------------------- 网格：待机第一帧变形后的顶点，按权重最大的骨骼分零件、换到那根骨骼的局部坐标（格）
setact(P['clips']['Idle'])
sc.frame_set(0)
inv_piece = { v: k for k, v in P['pieces'].items() }
dg = bpy.context.evaluated_depsgraph_get()
if P['decimate'] < 1:
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.parent == gun and len(o.data.vertices) > 3000:
            m = o.modifiers.new('dec', 'DECIMATE')
            m.ratio = P['decimate']
            bpy.context.view_layer.objects.active = o
            o.modifiers.move(o.modifiers.find('dec'), 0)   # 先减面再蒙皮（权重跟着顶点走）
    dg = bpy.context.evaluated_depsgraph_get()
def base_tex(mat):   # 材质 Base Color 接的那张图
    if not mat or not mat.use_nodes: return None
    for n in mat.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            inp = n.inputs['Base Color']
            if inp.links:
                fn = inp.links[0].from_node
                while fn and fn.type != 'TEX_IMAGE' and fn.inputs:
                    li = [i for i in fn.inputs if i.links]
                    fn = li[0].links[0].from_node if li else None
                if fn and fn.type == 'TEX_IMAGE': return fn.image
    return None
nodes, texmap = {}, {}
for o in bpy.data.objects:
    if o.type != 'MESH' or o.parent != gun: continue
    names = [g.name for g in o.vertex_groups]
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    W = o.matrix_world
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    # 每个顶点权重最大的骨骼（减面修改器排在蒙皮前面，新顶点的权重是它插值出来的，算出来的网格上还在）
    vbone = {}
    for v in me.vertices:
        if v.groups:
            g = max(v.groups, key=lambda x: x.weight)
            if g.group < len(names): vbone[v.index] = names[g.group].rsplit('_', 1)[0]
    mat = o.data.materials[0] if o.data.materials else None
    img = base_tex(mat)
    mname = (mat.name if mat else 'mat').replace('.', '_').replace('-', '_')
    if img: texmap[mname] = img
    for t in me.loop_triangles:
        bones_ = [vbone.get(me.loops[li].vertex_index, P['pieces']['gun']) for li in t.loops]
        bn = max(set(bones_), key=bones_.count)
        piece = inv_piece.get(bn, 'gun')
        B = bw(gun, P['pieces'][piece]).inverted()
        R3 = (B @ W).to_3x3()
        node = '%s_%s_%s' % (kid, piece, mname)
        nd = nodes.setdefault(node, { 'piece': piece, 'mat': mname, 'pos': [], 'nrm': [], 'uv': [], 'idx': [], 'key': {} })
        for li in t.loops:
            vi = me.loops[li].vertex_index
            n = (R3 @ me.loops[li].normal).normalized()
            uv = tuple(uvl[li].uv) if uvl else (0.0, 0.0)
            key = (o.name, vi, round(uv[0], 5), round(uv[1], 5), round(n.x, 3), round(n.y, 3), round(n.z, 3))
            j = nd['key'].get(key)
            if j is None:
                j = len(nd['pos'])
                nd['key'][key] = j
                v = B @ (W @ me.vertices[vi].co)
                nd['pos'].append((v.x * K, v.y * K, v.z * K))
                nd['nrm'].append((n.x, n.y, n.z))
                nd['uv'].append((uv[0], 1 - uv[1]))
            nd['idx'].append(j)
    ev.to_mesh_clear()
mesh = {}
for name, nd in nodes.items():
    ps = nd['pos']
    lo = [min(p[i] for p in ps) for i in range(3)]
    hi = [max(p[i] for p in ps) for i in range(3)]
    mesh[name] = { 'piece': nd['piece'], 'c': [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], 's': [round(hi[i] - lo[i], 4) for i in range(3)] }
    print(name, nd['piece'], len(ps), 'verts', len(nd['idx']) // 3, 'tris')

# 枪口：枪身零件里最靠前（相机系 −Z 最小）那一圈顶点（3 厘米以内）的中心，换回枪身骨骼的局部坐标；
#   开镜两点（没有开镜动作的枪用）：枪身后段、前段的最高点
G0 = C @ bw(gun, P['pieces']['gun'])
pts = []   # （相机系位置，格；骨骼里的位置，格）
for name, nd in nodes.items():
    if nd['piece'] == 'gun':
        for p in nd['pos']:
            c = G0 @ Vector((p[0] / K, p[1] / K, p[2] / K))
            pts.append((c * K, p))
zmin = min(c.z for c, _ in pts)
zmax = max(c.z for c, _ in pts)
print('gun camera-space bounds', [round(min(c[i] for c, _ in pts), 2) for i in range(3)], [round(max(c[i] for c, _ in pts), 2) for i in range(3)], len(pts))
front = [p for c, p in pts if c.z < zmin + 0.03 * S]
mz = [sum(p[i] for p in front) / len(front) for i in range(3)]
span = zmax - zmin
def top_at(z0, z1):
    sel = [(c, p) for c, p in pts if z0 <= c.z <= z1]
    if not sel: sel = pts
    return max(sel, key=lambda cp: cp[0].y)[1]
sight_r = top_at(zmax - span * 0.45, zmax - span * 0.3)
sight_f = top_at(zmin + span * 0.02, zmin + span * 0.12)
print('muzzle', [round(v, 3) for v in mz], 'sights', [round(v, 3) for v in sight_r], [round(v, 3) for v in sight_f], 'gun length', round(span, 2), 'studs')

def num(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s

L = []
L.append('-- 自动生成（tools/fps/fps_bake_pack.py），别手改：第一人称持枪动作，从「%s」（DuqueCD7，CC-BY-4.0，%s）抽出来' % (P['title'], P['url']))
L.append('--   格式同 FPSAnim.lua：clips[动作] = { fps, n, dur, t = { 轨道 = { 每帧 px, py, pz, qx, qy, qz, qw … } } }（相对相机，格）；只有一帧的轨道整段不动')
L.append('--   轨道：gun 枪身，%s；rua / rfa / rh、lua / lfa / lh 方块手臂' % '、'.join('%s 骨骼 %s' % (k, v) for k, v in P['pieces'].items() if k != 'gun'))
L.append('--   muzzle 枪口、sight 开镜时照门 / 准星（都在枪身骨骼里，格）；mesh 各网格（%s_mesh）在自己骨骼里的包围盒' % kid)
L.append('return {')
L.append('  clips = {')
for name in P['clips']:
    c = clips[name]
    L.append('    %s = { fps = %s, n = %d, dur = %s, t = {' % (name, num(c['fps']), c['n'], num(c['dur'])))
    for k, arr in c['tracks'].items():
        L.append('      %s = { %s },' % (k, ', '.join(num(v) for fr in arr for v in fr)))
    L.append('    } },')
L.append('  },')
L.append('  len = { %s },' % ', '.join('%s = %s' % (k, num(v)) for k, v in sorted(lens.items())))
L.append('  muzzle = { %s },' % ', '.join(num(v) for v in mz))
L.append('  sight = { { %s }, { %s } },' % (', '.join(num(v) for v in sight_r), ', '.join(num(v) for v in sight_f)))
L.append('  mesh = {')
for name in sorted(mesh):
    m = mesh[name]
    L.append('    %s = { piece = "%s", c = { %s }, s = { %s } },' % (name, m['piece'], ', '.join(num(v) for v in m['c']), ', '.join(num(v) for v in m['s'])))
L.append('  },')
L.append('}')
open(out_anim, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('anim lua', os.path.getsize(out_anim), 'bytes')

# ---------------------------------------------------------------- 贴图：缩到 tex 像素，量化成 256 色调色板（k-means，numpy）
def b64(b): return base64.b64encode(b).decode('ascii')
def tex_pal(img, size):
    img = img.copy()
    img.scale(size, size)
    Wd, Ht = img.size
    arr = np.empty(Wd * Ht * 4, np.float32)
    img.pixels.foreach_get(arr)
    px = np.clip(np.round(arr.reshape(Ht, Wd, 4)[::-1, :, :3] * 255), 0, 255).reshape(-1, 3).astype(np.float32)
    rng = np.random.default_rng(7)
    cent = px[rng.choice(len(px), 256, replace=False)].copy()
    sample = px[rng.choice(len(px), min(len(px), 60000), replace=False)]
    for _ in range(14):
        d = ((sample[:, None, :] - cent[None, :, :]) ** 2).sum(-1)
        lab = d.argmin(1)
        for k in range(256):
            m = lab == k
            if m.any(): cent[k] = sample[m].mean(0)
    idx = np.empty(len(px), np.uint8)
    for i in range(0, len(px), 20000):
        d = ((px[i:i + 20000, None, :] - cent[None, :, :]) ** 2).sum(-1)
        idx[i:i + 20000] = d.argmin(1)
    err = np.abs(cent[idx] - px).mean()
    print('tex', img.name, Wd, Ht, 'palette err', round(float(err), 2))
    return b64(np.clip(np.round(cent), 0, 255).astype(np.uint8).tobytes()), b64(idx.tobytes()), Wd, Ht

M = []
M.append('-- 自动生成（tools/fps/fps_bake_pack.py），别手改：第一人称「%s」的网格和贴图（DuqueCD7，CC-BY-4.0，%s）' % (P['title'], P['url']))
M.append('--   nodes 同 FPSMesh.lua（pos float32、nrm int8、uv uint16、idx uint16，小端 base64）；tex[名字] = { w, h, pal（256 色 × RGB）, ix（每像素调色板序号，从上往下）}')
M.append('return {')
M.append('  nodes = {')
for name in sorted(nodes):
    nd = nodes[name]
    c = mesh[name]['c']
    assert len(nd['pos']) < 65536, name
    pos = b''.join(struct.pack('<fff', p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in nd['pos'])
    nrm = b''.join(struct.pack('<bbb', *[max(-127, min(127, int(round(v * 127)))) for v in n]) for n in nd['nrm'])
    uv = b''.join(struct.pack('<HH', max(0, min(65535, int(round((u % 1.0000001) * 65535)))), max(0, min(65535, int(round((v % 1.0000001) * 65535))))) for u, v in nd['uv'])
    idx = b''.join(struct.pack('<H', i) for i in nd['idx'])
    M.append('    %s = { piece = "%s", c = { %s }, n = %d, t = %d, mat = "%s",' % (name, nd['piece'], ', '.join(num(v) for v in c), len(nd['pos']), len(nd['idx']) // 3, nd['mat']))
    M.append('      pos = "%s",' % b64(pos))
    M.append('      nrm = "%s",' % b64(nrm))
    M.append('      uv = "%s",' % b64(uv))
    M.append('      idx = "%s" },' % b64(idx))
M.append('  },')
M.append('  tex = {')
for mname, img in texmap.items():
    size = P['tex'] if mname.lower() != 'case' else 128
    pal, ix, Wd, Ht = tex_pal(img, size)
    M.append('    %s = { w = %d, h = %d, pal = "%s",' % (mname, Wd, Ht, pal))
    M.append('      ix = "%s" },' % ix)
M.append('  },')
M.append('}')
open(out_mesh, 'w', encoding='utf-8').write('\n'.join(M) + '\n')
print('mesh lua', os.path.getsize(out_mesh), 'bytes')
