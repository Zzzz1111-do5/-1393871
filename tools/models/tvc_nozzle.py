# 推力矢量喷口（用户给的 Sketchfab「F-15 SE Thrust Vector Nozzle」，ACshibu，CC-BY-4.0）→ Roblox 导入用的 models/air/tvc.glb + 元数据 ImportedAir.m.tvc
#   python3 -I tools/models/tvc_nozzle.py <下载的 .glb> [输出 GLB，默认 models/air/tvc.glb] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
#   原模型两块：外面一圈固定的外罩（Shroud）、里面的喷管（Nozzle，15 片调节片，带一个变形目标：0 收拢、1 张开，出口半径 0.42 → 0.68 米）。
#   Roblox 放不了变形动画：喷管按方位切成 15 片（每片调节片连它上面的小零件），每片绕自己喉道处的切向铰链转——张开时出口那一圈往外 0.26 米，
#   算成每片转的角度 A（同一个角）；游戏里（AirModels.lua）按油门开合、整只喷口绕喉道中心按俯仰 / 偏航 / 滚转偏转（推力矢量）。
#   坐标：转到飞机的模型坐标（X 右、Y 上、+Z 朝后＝喷口朝外），单位格（1 米 = 2.8 格）；原点在喉道铰链那一圈的中心（喷管往 +Z 伸出去）。
#   每块 MeshPart 叫 A_tvc__<块名>（Shroud_1、P01_1…P15_1），元数据 parts 里是块的中心、大小、颜色，tvc = { r 外罩半径, exit 出口离铰链多远, A 张开角, petals = { 每片的铰链点和轴 } }
import json, math, os, re, struct, sys
import numpy as np

S = 2.8
NPET = 15
src = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else 'models/air/tvc.glb'
META = sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/ImportedAir.lua'

data = open(src, 'rb').read()
jl = struct.unpack('<I', data[12:16])[0]
J = json.loads(data[20:20 + jl])
o = 20 + jl
bl = struct.unpack('<I', data[o:o + 4])[0]
BIN = data[o + 8:o + 8 + bl]
CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def acc(i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    k = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    st = bv.get('byteStride', dt.itemsize * k)
    raw = np.frombuffer(BIN, dtype=np.uint8, count=st * (a['count'] - 1) + dt.itemsize * k, offset=off)
    return np.lib.stride_tricks.as_strided(raw, shape=(a['count'], dt.itemsize * k), strides=(st, 1)).copy().view(dt).reshape(a['count'], k)


asset = J.get('asset', {}).get('extras', {})
credit = '%s（%s），作者 %s，%s' % (asset.get('title', ''), asset.get('source', ''), re.sub(r'\s*\(.*\)$', '', asset.get('author', '')), asset.get('license', ''))
meshes = {}
for mi, m in enumerate(J['meshes']):
    p = m['primitives'][0]
    P = acc(p['attributes']['POSITION']).astype(np.float64)
    N = acc(p['attributes']['NORMAL']).astype(np.float64)
    UV = acc(p['attributes']['TEXCOORD_0']).astype(np.float64)
    I = acc(p['indices']).reshape(-1, 3).astype(np.int64)
    D = acc(p['targets'][0]['POSITION']).astype(np.float64) if p.get('targets') else np.zeros_like(P)
    meshes[J['materials'][p['material']]['name']] = (P, N, UV, I, D)
# 节点上的两次绕 X 转 90° 互相抵消：模型坐标 z 是喷口轴，出口在 −z
Psh, Nsh, UVsh, Ish, _ = meshes['Shroud']
Pnz, Nnz, UVnz, Inz, Dnz = meshes['Nozzle']
ZH = 0.10   # 铰链那一圈（变形位移几乎为 0 的地方）
R_H = 0.70


def to_game(P):   # 原模型（米）→ 飞机模型坐标（格）：绕 Y 转半圈（x、z 取反，不镜像），原点挪到铰链那一圈中心
    return np.stack([-P[:, 0], P[:, 1], -(P[:, 2] - ZH)], axis=1) * S


def to_game_n(N):
    return np.stack([-N[:, 0], N[:, 1], -N[:, 2]], axis=1)


# 张开角：出口那一圈的径向位移 / 到铰链的距离
r = np.hypot(Pnz[:, 0], Pnz[:, 1])
radial = (Dnz[:, 0] * Pnz[:, 0] + Dnz[:, 1] * Pnz[:, 1]) / np.maximum(r, 1e-6)
ex = Pnz[:, 2] < Pnz[:, 2].min() + 0.05
A = float(math.atan2(radial[ex].mean(), ZH - Pnz[ex, 2].mean()))
exit_z = float((ZH - Pnz[:, 2].min()) * S)
print('张开角 %.1f°，出口离铰链 %.2f 格，出口半径 %.2f → %.2f 格' % (math.degrees(A), exit_z, r[ex].mean() * S, (r[ex] + radial[ex]).mean() * S))

# 切片：三角形重心的方位（游戏坐标里量），片中心在 −90° + 24°·k（原模型里调节片的位置，量出来的）
Pg = to_game(Pnz)
C = Pg[Inz].mean(axis=1)
ang = np.degrees(np.arctan2(C[:, 1], C[:, 0]))
# 原模型调节片中心在原坐标 −90 + 24k；转半圈后 x 取反：方位 θ → 180 − θ
centers = [((180 - (-90 + 24 * k)) + 180) % 360 - 180 for k in range(NPET)]
def nearest(a):
    d = [abs((a - c + 180) % 360 - 180) for c in centers]
    return int(np.argmin(d))
pet = np.array([nearest(a) for a in ang])

parts = []   # (名字, 部件, 顶点, 法线, uv, 三角形, 材质号)
Pgs = to_game(Psh)
parts.append(('Shroud_1', 'Shroud', Pgs, to_game_n(Nsh), UVsh, Ish, 0))
Ng = to_game_n(Nnz)
petals = []
for k in range(NPET):
    T = Inz[pet == k]
    if len(T) == 0:
        continue
    parts.append(('P%02d_1' % (k + 1), 'P%02d' % (k + 1), Pg, Ng, UVnz, T, 1))
    a = math.radians(centers[k])
    hp = [R_H * S * math.cos(a), R_H * S * math.sin(a), 0.0]
    ax = [-math.sin(a), math.cos(a), 0.0]   # 切向：绕它正转，片的后端往外张
    petals.append({'g': 'P%02d' % (k + 1), 'p': [round(v, 3) for v in hp], 'a': [round(v, 4) for v in ax]})

# 写 GLB：每块一个节点（平移到块中心），顶点相对块中心
bufs = bytearray()
views, accs, meshes_out, nodes = [], [], [], []
info_parts = {}
COL = [(150, 150, 146), (107, 104, 98)]   # 外罩、喷管（原模型喷管 0.149 线性灰）


def add_view(arr, target=None):
    global bufs
    while len(bufs) % 4:
        bufs += b'\0'
    off = len(bufs)
    b = arr.tobytes()
    bufs += b
    v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(b)}
    if target:
        v['target'] = target
    views.append(v)
    return len(views) - 1


for name, g, P, N, UV, T, mat in parts:
    u, inv = np.unique(T.reshape(-1), return_inverse=True)
    V = P[u]
    lo, hi = V.min(0), V.max(0)
    c = (lo + hi) / 2
    pos = (V - c).astype(np.float32)
    nrm = N[u].astype(np.float32)
    nl = np.linalg.norm(nrm, axis=1, keepdims=True)
    nrm = (nrm / np.maximum(nl, 1e-6)).astype(np.float32)
    uv = UV[u].astype(np.float32)
    idx = inv.reshape(-1, 3).astype(np.uint32)
    iv = add_view(idx.reshape(-1), 34963)
    accs.append({'bufferView': iv, 'componentType': 5125, 'count': int(idx.size), 'type': 'SCALAR'})
    ia = len(accs) - 1
    pv = add_view(pos, 34962)
    accs.append({'bufferView': pv, 'componentType': 5126, 'count': len(pos), 'type': 'VEC3', 'min': pos.min(0).tolist(), 'max': pos.max(0).tolist()})
    pa = len(accs) - 1
    nv = add_view(nrm, 34962)
    accs.append({'bufferView': nv, 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'})
    na = len(accs) - 1
    tv = add_view(uv, 34962)
    accs.append({'bufferView': tv, 'componentType': 5126, 'count': len(uv), 'type': 'VEC2'})
    ta = len(accs) - 1
    meshes_out.append({'name': name, 'primitives': [{'attributes': {'POSITION': pa, 'NORMAL': na, 'TEXCOORD_0': ta}, 'indices': ia, 'material': mat}]})
    nodes.append({'name': 'A_tvc__' + name, 'mesh': len(meshes_out) - 1, 'translation': c.tolist()})
    info_parts[name] = {'g': g, 'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in (hi - lo)], 'col': list(COL[mat]), 'met': 1}
root = {'name': 'A_tvc', 'children': list(range(len(nodes)))}
nodes.append(root)
gl = {'asset': {'version': '2.0', 'generator': 'tools/models/tvc_nozzle.py', 'extras': J.get('asset', {}).get('extras', {})},
      'scene': 0, 'scenes': [{'nodes': [len(nodes) - 1]}], 'nodes': nodes, 'meshes': meshes_out,
      'materials': [{'name': 'Shroud', 'pbrMetallicRoughness': {'baseColorFactor': [0.30, 0.30, 0.29, 1], 'metallicFactor': 0.9, 'roughnessFactor': 0.45}, 'doubleSided': True},
                    {'name': 'Nozzle', 'pbrMetallicRoughness': {'baseColorFactor': [0.149, 0.14, 0.12, 1], 'metallicFactor': 0.9, 'roughnessFactor': 0.5}, 'doubleSided': True}],
      'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(bufs)}]}
js = json.dumps(gl, separators=(',', ':')).encode()
js += b' ' * ((4 - len(js) % 4) % 4)
while len(bufs) % 4:
    bufs += b'\0'
glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bufs)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(bufs), 0x004E4942) + bytes(bufs)
os.makedirs(os.path.dirname(OUT) or '.', exist_ok=True)
open(OUT, 'wb').write(glb)
tris = sum(len(p[5]) for p in parts)
print('写好了 %s：%d 块、%d 个三角形、%.2f MB' % (OUT, len(parts), tris, len(glb) / 1e6))

# 元数据：m.tvc 那一行换掉 / 加上（别的模型原样）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
info = {'parts': info_parts, 'tvc': {'r': round(0.75 * S, 3), 'exit': round(exit_z, 3), 'A': round(A, 4), 'petals': petals}, 'credit': credit,
        'len': round(exit_z, 3), 'w': round(1.5 * S, 3), 'h': round(1.5 * S, 3), 'gear': False}
txt = open(META, encoding='utf-8').read()
line = '    tvc = %s,\n' % B.lua(info)
m = re.search(r'\n    tvc = \{.*?\n', txt)
if m:
    txt = txt[:m.start() + 1] + line + txt[m.end():]
else:
    k = txt.index('\n  m = {\n') + len('\n  m = {\n')
    txt = txt[:k] + line + txt[k:]
open(META, 'w', encoding='utf-8').write(txt)
print('元数据：m.tvc（%d 片调节片）写进 %s' % (len(petals), META))
cred = os.path.join(os.path.dirname(OUT), 'credits.txt')
if os.path.exists(cred):
    t = open(cred, encoding='utf-8').read()
    entry = '- 推力矢量喷口（tvc.glb）：This work is based on "%s" (%s) by %s licensed under %s（改动：转成 Roblox 坐标、喷管按 15 片调节片切开，游戏里绕铰链张合、整只偏转）' % (
        asset.get('title', ''), asset.get('source', ''), re.sub(r'\s*\(.*\)$', '', asset.get('author', '')), asset.get('license', ''))
    if '（tvc.glb）' in t:
        t = re.sub(r'- 推力矢量喷口（tvc\.glb）：[^\n]*', entry, t)
    else:
        t = t.rstrip('\n') + '\n' + entry + '\n'
    open(cred, 'w', encoding='utf-8').write(t)
