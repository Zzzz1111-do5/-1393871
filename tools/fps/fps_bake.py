# 第一人称持枪数据：从「M4 - FPS Weapon Animations Pack (v.1)」（BarcodeGames，CC-BY-4.0，
#   https://sketchfab.com/3d-models/m4-fps-weapon-animations-pack-v1-662fc74dda2646cfb48fc610705768ef）抽：
#   1) src/ReplicatedStorage/FPSAnim.lua：拔枪、开火、换弹、空仓换弹、收枪、待机每帧枪各零件（枪身、两个弹匣、枪机、空仓挂机、扳机）的骨骼、
#      方块手臂各段（上臂、小臂、手掌）相对相机的 CFrame（格；相机看 −Z、Y 朝上，和 Roblox 相机一样）；长的动作隔帧存（15 帧 / 秒）
#   2) models/fps_m4.glb：枪的网格按零件分开，每个零件的坐标就是它骨骼的局部坐标（单位格），贴图缩到 1024——在 Studio 里「导入 3D」后
#      放进 ReplicatedStorage/Imported/FPS_M4，游戏自动换成原模型（没导入时用 FPSView 里零件拼的 M4）
#   3) src/ReplicatedStorage/FPSMesh.lua：同样的网格（顶点、法线、UV、三角形）和贴图（M4 512 像素、子弹 128 像素），base64 编码嵌在游戏里——
#      客户端开局用 EditableMesh / EditableImage 生成 MeshPart，不用在 Studio 里手动导入也能看到真 M4
#   手不用原模型的手：游戏里画成 Roblox 方块形
# 用法：用 pip 装的 bpy（Blender 的 Python 模块）跑，不执行文件里的任何脚本：
#   python -I tools/fps/fps_bake.py <M4.fbx> <贴图目录> <输出 FPSAnim.lua> <输出 fps_m4.glb> <输出 FPSMesh.lua>
import bpy, sys, os, json, struct, io
from mathutils import Matrix, Vector

src, texdir, out_lua, out_glb, out_mesh = sys.argv[-5:]
S = 2.8            # 1 米 = 2.8 格（和游戏里一样）
MAG_SCALE = Vector((4.246, 4.145, 4.145))   # FBX 里两个弹匣骨骼带的缩放（Blender 导入时丢了：模型做得小、靠骨骼放大）
HAND_LEN = 0.36 / S                          # 方块手掌长（米）

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False)
sc = bpy.context.scene
arm = bpy.data.objects['Armature']
cam = bpy.data.objects['FPS_Camera']

def norm(M):
    loc, rot, _ = M.decompose()
    return Matrix.Translation(loc) @ rot.to_matrix().to_4x4()

def assign(obj, act):
    if not obj.animation_data: obj.animation_data_create()
    obj.animation_data.action = act
    if hasattr(obj.animation_data, 'action_slot') and act.slots:
        obj.animation_data.action_slot = act.slots[0]

def setact(name):
    a = bpy.data.actions['Armature|%s|BaseLayer' % name]
    assign(arm, a)
    ab = bpy.data.actions.get('Bullet5_56x45mm|%s|BaseLayer' % name)
    if ab: assign(bpy.data.objects['Bullet5_56x45mm'], ab)
    return a

def bone_world(bn): return norm(arm.matrix_world @ arm.pose.bones[bn].matrix)
def bone_head(bn): return (arm.matrix_world @ arm.pose.bones[bn].matrix).to_translation()

PIECES = { 'gun': 'Main_j', 'mag1': 'Mag1_j', 'mag2': 'Mag2_j', 'bolt': 'Bolt_j', 'catch': 'BoltCatch_j', 'trig': 'Trigger_j' }

def frame_of(a, b, side_hint, center=None):   # Y 轴从 a 指向 b，X 轴尽量贴近 side_hint
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
    for s, p in (('r', 'Right'), ('l', 'Left')):
        sh, el, wr = bone_head(p + 'Arm'), bone_head(p + 'ForeArm'), bone_head(p + 'Hand')
        hint = bone_world(p + 'ForeArm').to_3x3() @ Vector((1, 0, 0))
        out[s + 'ua'] = (frame_of(sh, el, hint), (el - sh).length)
        out[s + 'fa'] = (frame_of(el, wr, hint), (wr - el).length)
        # 手掌：腕 → 中指第三节；宽度方向 小指根 → 食指根；中心离腕半个手掌长
        tip, i1, k1 = bone_head(p + 'HandMiddle3'), bone_head(p + 'HandIndex1'), bone_head(p + 'HandPinky1')
        y = (tip - wr).normalized()
        out[s + 'h'] = (frame_of(wr, tip, i1 - k1, wr + y * HAND_LEN / 2), HAND_LEN)
    return out

def cf_list(M):   # → 位置 xyz（格）、四元数 xyzw
    loc, rot, _ = M.decompose()
    q = rot.normalized()
    return [round(loc.x * S, 3), round(loc.y * S, 3), round(loc.z * S, 3), round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)]

CLIPS = [('Idle', 1), ('Draw', 1), ('Fire', 1), ('Reload', 2), ('Reload_Empty', 2), ('Holster', 1)]   # （动作，隔几帧存一帧）
clips, lens = {}, {}
for name, every in CLIPS:
    a = setact(name)
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    frames = list(range(f0, f1 + 1, every))
    if frames[-1] != f1: frames.append(f1)
    tracks = {}
    for f in frames:
        sc.frame_set(f)
        C = norm(cam.matrix_world).inverted()
        for k, bn in PIECES.items(): tracks.setdefault(k, []).append(cf_list(C @ bone_world(bn)))
        for k, (M, L) in arm_boxes().items():
            tracks.setdefault(k, []).append(cf_list(C @ M))
            lens.setdefault(k, []).append(L * S)
    for k, arr in tracks.items():   # 整段没动的只存一帧
        if all(max(abs(v - w) for v, w in zip(fr, arr[0])) < 2e-3 for fr in arr): tracks[k] = [arr[0]]
    clips[name] = { 'fps': 30 / every, 'n': len(frames), 'dur': (f1 - f0) / 30, 'tracks': tracks }
    print(name, f0, f1, len(frames), 'static', [k for k, v in tracks.items() if len(v) == 1])
lens = { k: round(sum(v) / len(v), 3) for k, v in lens.items() }

# 待机姿势下各零件网格在自己骨骼里的坐标（格）
setact('Idle')
sc.frame_set(int(round(bpy.data.actions['Armature|Idle|BaseLayer'].frame_range[0])))
dg = bpy.context.evaluated_depsgraph_get()
MESH = [('Main', 'gun', 'M4'), ('Safety', 'gun', 'M4'), ('Mag1', 'mag1', 'M4'), ('Mag2', 'mag2', 'M4'), ('Bolt', 'bolt', 'M4'), ('BoltCatch', 'catch', 'M4'),
  ('Trigger', 'trig', 'M4'), ('Bullet5_56x45mm', 'mag1', 'Bullet'), ('Bullet5_56x45mm.001', 'mag2', 'Bullet')]
NODE = { 'Main': 'FPS_M4_Main', 'Safety': 'FPS_M4_Main', 'Mag1': 'FPS_M4_Mag1', 'Mag2': 'FPS_M4_Mag2', 'Bolt': 'FPS_M4_Bolt', 'BoltCatch': 'FPS_M4_BoltCatch',
  'Trigger': 'FPS_M4_Trigger', 'Bullet5_56x45mm': 'FPS_M4_Round1', 'Bullet5_56x45mm.001': 'FPS_M4_Round2' }
nodes = {}   # 节点名 → { piece, mat, pos[], nrm[], uv[], idx[] }
for on, piece, mat in MESH:
    o = bpy.data.objects[on]
    B = bone_world(PIECES[piece]).inverted()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    W = o.matrix_world
    R3 = (B @ W).to_3x3()
    sc3 = MAG_SCALE if piece in ('mag1', 'mag2') else Vector((1, 1, 1))
    def P(co):
        v = B @ (W @ co)
        return (v.x * sc3.x * S, v.y * sc3.y * S, v.z * sc3.z * S)
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    nd = nodes.setdefault(NODE[on], { 'piece': piece, 'mat': mat, 'pos': [], 'nrm': [], 'uv': [], 'idx': [], 'key': {} })
    for t in me.loop_triangles:
        for li in t.loops:
            vi = me.loops[li].vertex_index
            n = (R3 @ me.loops[li].normal)
            n = Vector((n.x / sc3.x, n.y / sc3.y, n.z / sc3.z)).normalized()
            uv = tuple(uvl[li].uv) if uvl else (0.0, 0.0)
            key = (on, vi, round(uv[0], 5), round(uv[1], 5), round(n.x, 3), round(n.y, 3), round(n.z, 3))
            j = nd['key'].get(key)
            if j is None:
                j = len(nd['pos'])
                nd['key'][key] = j
                nd['pos'].append(P(me.vertices[vi].co))
                nd['nrm'].append((n.x, n.y, n.z))
                nd['uv'].append((uv[0], 1 - uv[1]))   # glTF 的 V 朝下
            nd['idx'].append(j)
    ev.to_mesh_clear()
mesh = {}
for name, nd in nodes.items():
    ps = nd['pos']
    lo = [min(p[i] for p in ps) for i in range(3)]
    hi = [max(p[i] for p in ps) for i in range(3)]
    mesh[name] = { 'piece': nd['piece'], 'c': [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], 's': [round(hi[i] - lo[i], 4) for i in range(3)] }
    print(name, nd['piece'], len(ps), 'verts', len(nd['idx']) // 3, 'tris', 'center', mesh[name]['c'], 'size', mesh[name]['s'])

# ---------------------------------------------------------------- FPSAnim.lua
def num(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s
L = []
L.append('-- 自动生成（tools/fps/fps_bake.py），别手改：第一人称持枪动作，从「M4 - FPS Weapon Animations Pack (v.1)」（BarcodeGames，CC-BY-4.0）抽出来')
L.append('--   clips[动作] = { fps, n 帧数, dur 时长（秒）, t = { 轨道 = { 第 1 帧 px, py, pz, qx, qy, qz, qw, 第 2 帧 …… } } }，都是相对相机的 CFrame（格）；只有一帧的轨道整段不动')
L.append('--   轨道：gun 枪身、mag1 枪上的弹匣、mag2 换弹时拿的新弹匣、bolt 枪机、catch 空仓挂机、trig 扳机（都是骨骼的坐标系）；')
L.append('--     rua / rfa / rh 右上臂、右小臂、右手掌，lua / lfa / lh 左边的（方块的中心，Y 轴顺着手臂）')
L.append('--   len：手臂各段平均长度（格）；mesh：导入的网格（models/fps_m4.glb 的各节点）在自己骨骼里的包围盒中心、尺寸')
L.append('return {')
L.append('  clips = {')
for name, _ in CLIPS:
    c = clips[name]
    L.append('    %s = { fps = %s, n = %d, dur = %s, t = {' % (name, num(c['fps']), c['n'], num(c['dur'])))
    for k, arr in c['tracks'].items():
        flat = [num(v) for fr in arr for v in fr]
        L.append('      %s = { %s },' % (k, ', '.join(flat)))
    L.append('    } },')
L.append('  },')
L.append('  len = { %s },' % ', '.join('%s = %s' % (k, num(v)) for k, v in sorted(lens.items())))
L.append('  mesh = {')
for name in sorted(mesh):
    m = mesh[name]
    L.append('    %s = { piece = "%s", c = { %s }, s = { %s } },' % (name, m['piece'], ', '.join(num(v) for v in m['c']), ', '.join(num(v) for v in m['s'])))
L.append('  },')
L.append('}')
open(out_lua, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('lua', os.path.getsize(out_lua), 'bytes')

# ---------------------------------------------------------------- fps_m4.glb（自己写，坐标原样：Y 朝上、右手系，和 Roblox 一样）
def png_scaled(path, size=1024):
    img = bpy.data.images.load(path)
    w, h = img.size
    if max(w, h) > size:
        k = size / max(w, h)
        img.scale(max(1, int(w * k)), max(1, int(h * k)))
    tmp = os.path.join(os.path.dirname(out_glb), '_tmp_tex.png')
    img.filepath_raw = tmp
    img.file_format = 'PNG'
    img.save()
    data = open(tmp, 'rb').read()
    os.remove(tmp)
    return data
TEX = { 'M4': ('M4_D.png', 'M4_N.png'), 'Bullet': ('Bullet5.56x45mm_D.png', 'Bullet5.56x45mm_N.png') }
bin_ = io.BytesIO()
views, accessors, meshes_j, nodes_j, images, textures, materials = [], [], [], [], [], [], []
def add_view(data, target=None):
    while bin_.tell() % 4: bin_.write(b'\0')
    off = bin_.tell()
    bin_.write(data)
    v = { 'buffer': 0, 'byteOffset': off, 'byteLength': len(data) }
    if target: v['target'] = target
    views.append(v)
    return len(views) - 1
def add_acc(fmt, comps, rows, ctype, typ, target, minmax=False):
    data = b''.join(struct.pack('<' + fmt * comps, *r) if comps > 1 else struct.pack('<' + fmt, r) for r in rows)
    a = { 'bufferView': add_view(data, target), 'componentType': ctype, 'count': len(rows), 'type': typ }
    if minmax:
        a['min'] = [min(r[i] for r in rows) for i in range(comps)]
        a['max'] = [max(r[i] for r in rows) for i in range(comps)]
    accessors.append(a)
    return len(accessors) - 1
mat_index = {}
for mname, (d, n) in TEX.items():
    ii = []
    for fn in (d, n):
        images.append({ 'bufferView': add_view(png_scaled(os.path.join(texdir, fn))), 'mimeType': 'image/png', 'name': os.path.splitext(fn)[0] })
        textures.append({ 'source': len(images) - 1 })
        ii.append(len(textures) - 1)
    materials.append({ 'name': mname, 'pbrMetallicRoughness': { 'baseColorTexture': { 'index': ii[0] }, 'metallicFactor': 0.6, 'roughnessFactor': 0.55 },
      'normalTexture': { 'index': ii[1] } })
    mat_index[mname] = len(materials) - 1
for name in sorted(nodes):
    nd = nodes[name]
    pa = add_acc('f', 3, nd['pos'], 5126, 'VEC3', 34962, True)
    na = add_acc('f', 3, nd['nrm'], 5126, 'VEC3', 34962)
    ua = add_acc('f', 2, nd['uv'], 5126, 'VEC2', 34962)
    ia = add_acc('I', 1, nd['idx'], 5125, 'SCALAR', 34963)
    meshes_j.append({ 'name': name, 'primitives': [{ 'attributes': { 'POSITION': pa, 'NORMAL': na, 'TEXCOORD_0': ua }, 'indices': ia, 'material': mat_index[nd['mat']] }] })
    nodes_j.append({ 'name': name, 'mesh': len(meshes_j) - 1 })
gltf = { 'asset': { 'version': '2.0', 'generator': 'darksword fps_bake.py', 'copyright': 'M4 - FPS Weapon Animations Pack (v.1) by BarcodeGames, CC-BY-4.0' },
  'scene': 0, 'scenes': [{ 'name': 'FPS_M4', 'nodes': list(range(len(nodes_j))) }], 'nodes': nodes_j, 'meshes': meshes_j, 'materials': materials,
  'textures': textures, 'images': images, 'accessors': accessors, 'bufferViews': views, 'buffers': [{ 'byteLength': 0 }] }
while bin_.tell() % 4: bin_.write(b'\0')
B = bin_.getvalue()
gltf['buffers'][0]['byteLength'] = len(B)
J = json.dumps(gltf, separators=(',', ':')).encode()
while len(J) % 4: J += b' '
with open(out_glb, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(J) + 8 + len(B)))
    f.write(struct.pack('<II', len(J), 0x4E4F534A)); f.write(J)
    f.write(struct.pack('<II', len(B), 0x004E4942)); f.write(B)
print('glb', os.path.getsize(out_glb), 'bytes')

# ---------------------------------------------------------------- FPSMesh.lua（嵌在游戏里的网格和贴图）
import base64
import numpy as np
def b64(b): return base64.b64encode(b).decode('ascii')
def tex_rgb(path, size):
    img = bpy.data.images.load(path)
    img.scale(size, size)
    W, H = img.size
    arr = np.empty(W * H * 4, np.float32)
    img.pixels.foreach_get(arr)
    arr = arr.reshape(H, W, 4)[::-1, :, :3]   # Blender 的像素从下往上，EditableImage 从上往下
    return b64(np.clip(np.round(arr * 255), 0, 255).astype(np.uint8).tobytes()), W, H
M = []
M.append('-- 自动生成（tools/fps/fps_bake.py），别手改：第一人称 M4 的网格和贴图，从「M4 - FPS Weapon Animations Pack (v.1)」（BarcodeGames，CC-BY-4.0）转来')
M.append('--   客户端用 EditableMesh / EditableImage 生成 MeshPart（FPSView）：nodes[名字] = { piece 跟哪条动画轨道, c 包围盒中心（在骨骼坐标里，格）, n 顶点数, t 三角形数,')
M.append('--     mat 用哪张贴图, pos 顶点（float32 xyz，已减去中心）, nrm 法线（int8 xyz ÷127）, uv（uint16 ÷65535，V 朝下）, idx 三角形（uint16，逆时针是正面）}，都是小端 base64')
M.append('--   tex[名字] = { w, h, rgb（每像素 3 字节，从上往下一行行）}')
M.append('return {')
M.append('  nodes = {')
for name in sorted(nodes):
    nd = nodes[name]
    c = mesh[name]['c']
    pos = b''.join(struct.pack('<fff', p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in nd['pos'])
    nrm = b''.join(struct.pack('<bbb', *[max(-127, min(127, int(round(v * 127)))) for v in n]) for n in nd['nrm'])
    uv = b''.join(struct.pack('<HH', max(0, min(65535, int(round((u % 1.0000001) * 65535)))), max(0, min(65535, int(round((v % 1.0000001) * 65535))))) for u, v in nd['uv'])
    assert len(nd['pos']) < 65536
    idx = b''.join(struct.pack('<H', i) for i in nd['idx'])
    M.append('    %s = { piece = "%s", c = { %s }, n = %d, t = %d, mat = "%s",' % (name, nd['piece'], ', '.join(num(v) for v in c), len(nd['pos']), len(nd['idx']) // 3, nd['mat']))
    M.append('      pos = "%s",' % b64(pos))
    M.append('      nrm = "%s",' % b64(nrm))
    M.append('      uv = "%s",' % b64(uv))
    M.append('      idx = "%s" },' % b64(idx))
M.append('  },')
M.append('  tex = {')
for mname, (d, _n) in TEX.items():
    data, W, H = tex_rgb(os.path.join(texdir, d), 512 if mname == 'M4' else 128)
    M.append('    %s = { w = %d, h = %d, rgb = "%s" },' % (mname, W, H, data))
M.append('  },')
M.append('}')
open(out_mesh, 'w', encoding='utf-8').write('\n'.join(M) + '\n')
print('mesh lua', os.path.getsize(out_mesh), 'bytes')
