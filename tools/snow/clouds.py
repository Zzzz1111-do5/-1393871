# 雪山上空的体积云：Sketchfab 上 Loïc Norgeot 的「Fluffy Cloud」（CC-BY 4.0）→ models/snow/clouds.glb
#   用户 11-26 晚：「天上要有非常多的云 让飞机在天上飞也有立体感」
#   python3 -I tools/snow/clouds.py <Fluffy Cloud 的 scene.gltf> <输出 clouds.glb>
#   原模型是一团云的「切片」：三个方向（X、Y、Z）各 225 片正方形，每片贴一张云的密度切片（三张 15 × 15 的图集），每片几乎全透明（不透明度 0.03），
#     叠在一起就是一团有体积的云——在 Roblox 里每团 675 片透明面叠着画太费（钻进去整屏叠几百层），这里：
#   · 每个方向等间隔挑 N 片（默认 19），按片数补每片的不透明度（叠起来总的浓淡和原来差不多）
#   · 明暗烘进贴图：云顶白、云底灰蓝（每个贴图格子按它在云里的高度算），太阳从上面照的样子
#   · 三个方向各一块网格（N_cloud__X / Y / Z，Imports.lua 收进 Imported.Scenery.cloud），大小 1 × 1 × 1（游戏里按需要放大、压扁、转）
import sys, os, json, struct, io
import numpy as np
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
NS = int(sys.argv[3]) if len(sys.argv) > 3 else 19
D = os.path.dirname(os.path.abspath(SRC))
J = json.load(open(SRC))
BIN = open(os.path.join(D, J['buffers'][0]['uri']), 'rb').read()
CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def acc(i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    n = NC[a['type']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(BIN, dtype=dt, count=a['count'] * n, offset=o).reshape(a['count'], n).astype(np.float64 if dt.kind == 'f' else np.int64)


G = dict(asset=dict(version='2.0', generator='tools/snow/clouds.py'), scene=0, scenes=[dict(nodes=[])], nodes=[], meshes=[], accessors=[], bufferViews=[],
         buffers=[], materials=[], textures=[], images=[], samplers=[dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)])
blob = bytearray()


def add_view(data, target=None):
    while len(blob) % 4:
        blob.append(0)
    o = len(blob)
    blob.extend(data)
    v = dict(buffer=0, byteOffset=o, byteLength=len(data))
    if target:
        v['target'] = target
    G['bufferViews'].append(v)
    return len(G['bufferViews']) - 1


def add_acc(arr, typ, comp, target=None, minmax=False):
    a = np.ascontiguousarray(arr)
    v = add_view(a.tobytes(), target)
    d = dict(bufferView=v, componentType=comp, count=int(a.shape[0]), type=typ)
    if minmax:
        d['min'] = a.min(0).tolist()
        d['max'] = a.max(0).tolist()
    G['accessors'].append(d)
    return len(G['accessors']) - 1


AX = 'XYZ'
mesh_nodes = [n for n in J['nodes'] if 'mesh' in n]
TOP, BOT = np.array([255, 255, 255], np.float32), np.array([158, 166, 182], np.float32)   # 云顶、云底的颜色
for mi, m in enumerate(J['meshes']):
    p = m['primitives'][0]
    P = acc(p['attributes']['POSITION'])
    UV = acc(p['attributes']['TEXCOORD_0'])
    I = acc(p['indices']).reshape(-1, 3)
    mat = J['materials'][p['material']]
    img = J['images'][J['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    tex = np.array(Image.open(os.path.join(D, img['uri'])).convert('LA')).astype(np.float32)
    H, W = tex.shape[:2]
    # 每 4 个顶点一片：这一片垂直于哪根轴、在那根轴上的位置
    nq = len(P) // 4
    Q = P.reshape(nq, 4, 3)
    span = Q.max(1) - Q.min(1)
    ax = int(np.argmin(span.mean(0)))   # 片在这根轴上没有厚度
    pos = Q[:, 0, ax]
    order = np.argsort(pos)
    # 挑片：只要这一片贴图格子里有云的（透明度总和够），再等间隔挑 NS 片
    keep_all = []
    for qi in order:
        uv = UV[qi * 4:(qi + 1) * 4]
        x0, x1 = int(uv[:, 0].min() * W), int(np.ceil(uv[:, 0].max() * W))
        y0, y1 = int(uv[:, 1].min() * H), int(np.ceil(uv[:, 1].max() * H))
        a = tex[y0:y1, x0:x1, 1]
        if a.size and a.mean() > 2.0:
            keep_all.append(qi)
    pick = [keep_all[int(round(k))] for k in np.linspace(0, len(keep_all) - 1, min(NS, len(keep_all)))]
    boost = 0.03 * len(keep_all) / len(pick)   # 少画了几片：每片的不透明度按片数补回来（贴图的透明度 × 原来的 0.03 × 倍数）
    out = np.zeros((H, W, 4), np.uint8)
    out[..., :3] = 255
    Pv, Uv, Nv, Iv = [], [], [], []
    for k, qi in enumerate(pick):
        q = P[qi * 4:(qi + 1) * 4]
        uv = UV[qi * 4:(qi + 1) * 4]
        x0, x1 = int(uv[:, 0].min() * W), int(np.ceil(uv[:, 0].max() * W))
        y0, y1 = int(uv[:, 1].min() * H), int(np.ceil(uv[:, 1].max() * H))
        # 格子里每个像素在云里的高度（y）：按这一片四个角的 uv → 位置插值（片是正方形、uv 是对齐的矩形）
        ys = np.zeros((y1 - y0, x1 - x0), np.float32)
        u = (np.arange(x0, x1) + 0.5) / W
        v = (np.arange(y0, y1) + 0.5) / H
        uu, vv = np.meshgrid(u, v)
        # 拟合 y = a·u + b·v + c（四个角）
        A = np.c_[uv[:, 0], uv[:, 1], np.ones(4)]
        coef, *_ = np.linalg.lstsq(A, q[:, 1], rcond=None)
        ys = coef[0] * uu + coef[1] * vv + coef[2]   # 原模型 y 在 −1 ～ 0
        t = np.clip((ys + 1.0) / 1.0, 0, 1) ** 0.8   # 0 云底 ～ 1 云顶
        col = BOT[None, None, :] * (1 - t[..., None]) + TOP[None, None, :] * t[..., None]
        out[y0:y1, x0:x1, :3] = col.astype(np.uint8)
        out[y0:y1, x0:x1, 3] = np.clip(tex[y0:y1, x0:x1, 1] * boost * 1.4, 0, 255).astype(np.uint8)
        # 顶点：原模型在 x 0～1、y −1～0、z 0～1 的方块里——挪到中心在原点
        base = len(Pv) * 0
        Pv.append(q - np.array([0.5, -0.5, 0.5]))
        Uv.append(uv)
        nrm = np.zeros(3)
        nrm[ax] = 1
        Nv.append(np.tile(nrm, (4, 1)))
    Pv = np.vstack(Pv).astype(np.float32)
    Uv = np.vstack(Uv).astype(np.float32)
    Nv = np.vstack(Nv).astype(np.float32)
    n = len(pick)
    # 每片两面（Roblox 的网格只画正面）
    tri = []
    for k in range(n):
        a = 4 * k
        tri += [[a, a + 1, a + 2], [a, a + 2, a + 3], [a, a + 2, a + 1], [a, a + 3, a + 2]]
    tri = np.array(tri, np.uint32)
    im = Image.fromarray(out, 'RGBA').resize((1024, 1024), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, 'PNG', optimize=True)
    G['images'].append(dict(bufferView=add_view(b.getvalue()), mimeType='image/png'))
    G['textures'].append(dict(source=len(G['images']) - 1, sampler=0))
    G['materials'].append(dict(name='Cloud' + AX[ax], alphaMode='BLEND', doubleSided=False,
                               pbrMetallicRoughness=dict(baseColorTexture=dict(index=len(G['textures']) - 1), metallicFactor=0.0, roughnessFactor=1.0)))
    c = (Pv.min(0) + Pv.max(0)) / 2
    a_p = add_acc(Pv - c, 'VEC3', 5126, 34962, minmax=True)
    a_n = add_acc(Nv, 'VEC3', 5126, 34962)
    a_u = add_acc(Uv, 'VEC2', 5126, 34962)
    a_i = add_acc(tri.reshape(-1), 'SCALAR', 5125, 34963)
    name = 'N_cloud__' + AX[ax]
    G['meshes'].append(dict(name=name, primitives=[dict(attributes=dict(POSITION=a_p, NORMAL=a_n, TEXCOORD_0=a_u), indices=a_i, material=len(G['materials']) - 1)]))
    G['nodes'].append(dict(name=name, mesh=len(G['meshes']) - 1, translation=[float(v) for v in c]))
    G['scenes'][0]['nodes'].append(len(G['nodes']) - 1)
    print(name, '挑了', n, '片（有云的', len(keep_all), '片），每片不透明度 ×', round(boost, 3), '，中心', np.round(c, 3), '大小', np.round(Pv.max(0) - Pv.min(0), 3))

while len(blob) % 4:
    blob.append(0)
G['buffers'].append(dict(byteLength=len(blob)))
js = json.dumps(G, separators=(',', ':')).encode()
js += b' ' * ((4 - len(js) % 4) % 4)
with open(OUT, 'wb') as f:
    f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(blob)))
    f.write(struct.pack('<I4s', len(js), b'JSON'))
    f.write(js)
    f.write(struct.pack('<I4s', len(blob), b'BIN\x00'))
    f.write(bytes(blob))
print('写好', OUT, '%.1f MB' % (os.path.getsize(OUT) / 1e6))
