# 用户给的「Missile & Bomb Collection - Fighter Jets - Free」（bohmerang，CC-BY-NC-SA-4.0；用户：游戏不收费，直接用）
#   → Studio「导入 3D」用的 models/wpn/missiles.glb + 署名 models/wpn/credits.txt
#   python3 -I tools/models/wpn2glb.py <合集的 .glb> [输出目录，默认 models/wpn]
#   每枚弹一块 MeshPart：W_<型号>__Body_1（开服时 Imports.lua 收进 ReplicatedStorage.Imported.Wpn.<型号>；WeaponModels 有就用它，没有照旧零件拼）
#   坐标同 WeaponModels 的弹体坐标：包围盒中心为原点、弹头朝 −Z、+Y 朝上（挂架那边），真实尺寸 1 米 = 2.8 格（游戏里再按 AirDefs 的弹长 L 等比缩放）；
#     顶点照 tools/models/air2glb.py 的写法（导入时 Roblox 把网格转半圈，游戏里乘 TURN 补回）
#   材质照原样（底色贴图、法线贴图），只把金属度压到 0.3 以下、粗糙度至少 0.45：原模型金属度 0.7～0.96，没有环境反射的地方一片黑
#   合集里另外几枚（Kh-29、KAB-500L、R-27、PL-11、AIM-7、R-77）游戏里没有这些型号，不转
import io, json, os, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import air_kf as KF   # noqa: E402  读 GLB

S = 2.8
TEXMAX = 1024
# 游戏型号 → 合集里的节点
MAP = {
    'gbu31': 'JDAM_1',                  # GBU-31（2000 磅 JDAM），合集里大的那枚（长 3.96 米）
    'gbu32': 'JDAM (2)_0',              # GBU-32（1000 磅 JDAM，2.82 米）；GBU-38 游戏里借它按弹长缩小（WeaponModels 的 IMP_ALIAS）
    'gbu12': 'GBU-12 Paveway II_10',
    'agm65': 'AGM-65 Maverick_4',
    'aim9x': 'AIM-9 Sidewinder_12',     # 合集里是 AIM-9（L / M）
    'ty90': 'TY-90_13',
    'agm114': 'AGM-114 Hellfire_15',
    'akd10': 'HJ-10_14',                # AKD-10 是 HJ-10 的空射型
}


def convert(src, outdir):
    J, BIN = KF.read_glb(src)
    g = KF.G(J, BIN)
    out = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield wpn2glb.py'}, 'scene': 0, 'scenes': [{'name': 'W_missiles', 'nodes': [0]}],
           'nodes': [{'name': 'W_missiles', 'children': []}], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [], 'materials': [],
           'textures': [], 'images': [], 'samplers': [{'wrapS': 10497, 'wrapT': 10497, 'magFilter': 9729, 'minFilter': 9987}]}
    blob = bytearray()

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        o = len(blob)
        blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': o, 'byteLength': len(data)}
        if target:
            bv['target'] = target
        out['bufferViews'].append(bv)
        return len(out['bufferViews']) - 1

    def acc(arr, typ, ctype=5126, minmax=False, target=34962):
        a = {'bufferView': view(np.ascontiguousarray(arr).tobytes(), target), 'componentType': ctype, 'count': len(arr), 'type': typ}
        if minmax:
            a['min'] = [float(v) for v in arr.min(0)]
            a['max'] = [float(v) for v in arr.max(0)]
        out['accessors'].append(a)
        return len(out['accessors']) - 1

    img_ix = {}

    def image(ti, name):
        si = J['textures'][ti]['source']
        if si in img_ix:
            return img_ix[si]
        im = J['images'][si]
        bv = J['bufferViews'][im['bufferView']]
        raw = bytes(BIN[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
        mime = im.get('mimeType', 'image/png')
        pic = Image.open(io.BytesIO(raw))
        if max(pic.size) > TEXMAX:   # Roblox 贴图最大 1024
            k = TEXMAX / max(pic.size)
            pic = pic.resize((max(1, int(pic.size[0] * k)), max(1, int(pic.size[1] * k))), Image.LANCZOS)
            buf = io.BytesIO()
            pic.save(buf, 'PNG')
            raw, mime = buf.getvalue(), 'image/png'
        out['images'].append({'bufferView': view(raw), 'mimeType': mime, 'name': name})
        out['textures'].append({'source': len(out['images']) - 1, 'sampler': 0})
        img_ix[si] = len(out['textures']) - 1
        return img_ix[si]

    info, cred = {}, J['asset'].get('extras', {})
    for n, (key, node) in enumerate(sorted(MAP.items())):
        ni = g.byname[node]
        mn = g.mesh_nodes(ni)
        P, N, UV, T, mats = [], [], [], [], set()
        base = 0
        for i in mn:
            M = g.world(i)
            for pr in J['meshes'][J['nodes'][i]['mesh']]['primitives']:
                p = g.acc(pr['attributes']['POSITION'])
                P.append(p @ M[:3, :3].T + M[:3, 3])
                nr = g.acc(pr['attributes']['NORMAL']) if 'NORMAL' in pr['attributes'] else np.zeros_like(p)
                N.append(nr @ np.linalg.inv(M[:3, :3]))   # 法线乘逆转置
                UV.append(g.acc(pr['attributes']['TEXCOORD_0']) if 'TEXCOORD_0' in pr['attributes'] else np.zeros((len(p), 2)))
                idx = g.acc(pr['indices']).astype(np.int64).reshape(-1, 3) if 'indices' in pr else np.arange(len(p)).reshape(-1, 3)
                T.append(idx + base)
                base += len(p)
                mats.add(pr.get('material', 0))
        assert len(mats) == 1, (key, mats)
        P, N, UV, T = np.concatenate(P), np.concatenate(N), np.concatenate(UV), np.concatenate(T)
        lo, hi = P.min(0), P.max(0)
        c = (lo + hi) / 2
        ax = int(np.argmax(hi - lo))   # 弹长方向
        assert ax == 2, (key, hi - lo)
        Q = P - c
        r = np.hypot(Q[:, 0], Q[:, 1])
        L = hi[2] - lo[2]
        rN, rT = r[Q[:, 2] > L / 2 - L * 0.04].max(), r[Q[:, 2] < -L / 2 + L * 0.04].max()   # 两头 4% 里离轴线最远：尾翼那头大
        nose = 1 if rN < rT else -1   # 弹头在 +z（1）还是 −z
        # 弹头朝 −Z：弹头在 +z 的绕 Y 转半圈（x、z 都反过来，不镜像）
        R = np.diag([-1.0, 1, -1]) if nose > 0 else np.eye(3)
        Pw = (Q @ R.T) * S
        Nw = N @ R.T
        Nw /= np.maximum(np.linalg.norm(Nw, axis=1, keepdims=True), 1e-9)
        m = J['materials'][mats.pop()]
        pbr = m.get('pbrMetallicRoughness', {})
        mat = {'name': 'W_%s_%s' % (key, m.get('name', 'm')), 'doubleSided': bool(m.get('doubleSided', False)),
               'pbrMetallicRoughness': {'baseColorFactor': pbr.get('baseColorFactor', [1, 1, 1, 1]),
                                        'metallicFactor': min(0.3, float(pbr.get('metallicFactor', 1.0))),
                                        'roughnessFactor': max(0.45, float(pbr.get('roughnessFactor', 1.0)))}}
        if 'baseColorTexture' in pbr:
            mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': image(pbr['baseColorTexture']['index'], 'W_%s_base' % key)}
        if 'normalTexture' in m:
            mat['normalTexture'] = {'index': image(m['normalTexture']['index'], 'W_%s_normal' % key), 'scale': float(m['normalTexture'].get('scale', 1))}
        out['materials'].append(mat)
        prim = {'attributes': {'POSITION': acc(Pw.astype(np.float32), 'VEC3', minmax=True), 'NORMAL': acc(Nw.astype(np.float32), 'VEC3'),
                               'TEXCOORD_0': acc(UV.astype(np.float32), 'VEC2')},
                'indices': acc(T.reshape(-1).astype(np.uint32), 'SCALAR', 5125, target=34963), 'material': len(out['materials']) - 1}
        nm = 'W_%s__Body_1' % key
        out['meshes'].append({'name': nm, 'primitives': [prim]})
        out['nodes'].append({'name': nm, 'mesh': len(out['meshes']) - 1, 'translation': [n * 6.0, 0, 0]})   # 在 Studio 里一字排开
        out['nodes'][0]['children'].append(len(out['nodes']) - 1)
        sz = (hi - lo)[[0, 1, 2]] * S
        info[key] = (len(T), sz, node, nose)
        print('%-7s ← %-22s %4d 个三角形，长 %.2f 米（%.1f 格），弹头原来在 %sz（两头离轴 %.2f / %.2f 米）' % (key, node, len(T), L, L * S, '+' if nose > 0 else '−', rN, rT))
    out['buffers'].append({'byteLength': len(blob)})
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, 'missiles.glb')
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)
    print('→ %s（%.1f MB，%d 枚）' % (path, os.path.getsize(path) / 1e6, len(info)))
    names = {'gbu31': 'GBU-31 JDAM', 'gbu32': 'GBU-32 JDAM（GBU-38 借用缩小）', 'gbu12': 'GBU-12「宝石路」II', 'agm65': 'AGM-65「小牛」',
             'aim9x': 'AIM-9X「响尾蛇」（模型是 AIM-9）', 'ty90': '天燕-90', 'agm114': 'AGM-114「地狱火」', 'akd10': 'AKD-10（模型是 HJ-10）'}
    with open(os.path.join(outdir, 'credits.txt'), 'w', encoding='utf-8') as f:
        f.write('导弹、炸弹模型（missiles.glb）\n\n')
        f.write('来源：「%s」，作者 %s，%s 授权。\n' % (cred.get('title', ''), cred.get('author', ''), cred.get('license', '')))
        f.write('网址：%s\n' % cred.get('source', ''))
        f.write('改动：只取其中游戏里有的型号、各自居中摆正（弹头朝前）、换算成 Roblox 尺寸；金属度压到 0.3 以下、粗糙度至少 0.45；大于 1024 的贴图缩到 1024。\n')
        f.write('授权要求：署名、非商业使用、相同方式共享——本文件夹里转换后的模型同样按 CC BY-NC-SA 4.0 授权（https://creativecommons.org/licenses/by-nc-sa/4.0/）。\n\n')
        for key in sorted(MAP):
            f.write('- %s：合集里的「%s」\n' % (names.get(key, key), MAP[key].rsplit('_', 1)[0]))
    # 游戏里的致谢（主菜单「致谢」那一页，Menu.lua 读）
    meta = os.path.join('src', 'ReplicatedStorage', 'ImportedWpn.lua')
    lic = 'CC BY-NC-SA 4.0 授权（https://creativecommons.org/licenses/by-nc-sa/4.0/）'
    who = cred.get('author', '').split(' (')[0]
    with open(meta, 'w', encoding='utf-8') as f:
        f.write('-- 导弹合集（models/wpn/missiles.glb，tools/models/wpn2glb.py 生成）：署名（主菜单「致谢」）和导入了的型号\n')
        f.write('return {\n')
        f.write('  credit = "机载导弹、炸弹（%s）：%s，作者 %s（%s），%s。署名见 models/wpn/credits.txt",\n'
                % ('、'.join(names[k].split('（')[0] for k in sorted(MAP)), cred.get('title', ''), who, cred.get('source', ''), lic))
        f.write('  keys = { %s },\n' % ', '.join('"%s"' % k for k in sorted(MAP)))
        f.write('}\n')
    print('→ %s' % meta)


if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'models/wpn')
