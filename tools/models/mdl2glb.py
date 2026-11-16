# 网页版《暗剑》烘焙的装备模型（js/mdl/<键>.js）→ Roblox Studio「导入 3D」用的 GLB（每个模型一个）+ 游戏用的元数据
#   python3 -I tools/models/mdl2glb.py <网页版仓库目录> [输出目录，默认 models/veh] [元数据，默认 src/ReplicatedStorage/ImportedMeta.lua] [模型键 …]
# 原样转（用户：每个载具都是要驾驶的，原 size 导入）：
#   - 网格用最精细的那档（不减面）；Roblox 一块网格最多约 2 万个三角形，超了就切成几块
#   - 每个材质照原样：底色贴图、法线贴图、金属度 / 粗糙度贴图（Studio 导入时做成 SurfaceAppearance）、底色、透明方式、双面；
#     贴图保持原分辨率（Roblox 最大 1024，更大的缩到 1024），平铺方式照原样（重复 / 镜像 / 夹边）
#   - 真实尺寸：1 米 = 2.8 格（和游戏里的人一样比例）；坐标从网页版的 x 前、y 左、z 上换成 Roblox 的 X 右、Y 上、−Z 前，
#     原点在车底、车身（不含炮塔、炮）的中心——和游戏里的碰撞盒对齐
#   - 按部件分：车体 Body、炮塔 Turret（tur / yaw / rws / tow / rdr）、炮 Gun（gun / gat / lnch）、车轮 W01……（whl）；
#     每个部件再按材质分成几块：MeshPart 叫 V_<键>__<部件>_<块号>（开服时 Imports.lua 按名字收进 ReplicatedStorage.Imported.Veh.<键>）
# 元数据：各块属于哪个部件、在模型里的中心和大小；炮塔转轴、炮耳轴、炮口离耳轴多远；每个车轮的中心和半径；署名
import base64, io, json, math, os, struct, sys
import numpy as np
from PIL import Image

WEB = sys.argv[1]
OUTDIR = sys.argv[2] if len(sys.argv) > 2 else 'models/veh'
META = sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/ImportedMeta.lua'
ONLY = sys.argv[4:]
S = 2.8          # 米 → 格
CHUNK = 19500    # 一块网格最多几个三角形
TEXMAX = 1024    # Roblox 贴图最大边长

# Roblox 里的型号 → 网页版的模型（网页版自己就拿 LAV-25 代 ZSL-92B、PzH 2000 代 PLZ-07、M-ATV 代 M1117……照它）
ALIAS = {
    'ztz99a': 'ztz99', 'ztz96': 'ztz96', 'zbd05': 'zbd97', 'zsl92b': 'lav25', 'ptl02': 'ptl02', 'pgl625': 't625', 'plz07': 'pzh2000',
    'm1a2': 'm1a2v3', 'm1a1': 'm1a1', 'm2a3': 'm2a3', 'stryker': 'stryker', 'mshorad': 'stryker', 'm1150': 'm1150', 'hmmwv': 'hmmwv',
    'jltv': 'jltv', 'm1117': 'matv', 'm163': 'm163', 'cram': 'cram', 'patriot': 'patriot', 'm109a7': 'm109', 'm270': 'm270',
}
GROUP = {'tur': 'Turret', 'yaw': 'Turret', 'rws': 'Turret', 'tow': 'Turret', 'rdr': 'Turret', 'gun': 'Gun', 'gat': 'Gun', 'lnch': 'Gun'}
WRAP = {0: 10497, 1: 33071, 2: 33648}   # 重复、夹边、镜像


def load(key):
    t = open(os.path.join(WEB, 'js', 'mdl', key + '.js'), encoding='utf-8').read()
    a = t.index('V3G.add(') + 8
    q, e = t.rindex(", '"), t.rindex("')")
    head = t[a:q]
    c = head.index(',')
    meta = json.loads(head[c + 1:])
    credit = t.split('\n', 1)[0].lstrip('/ ').strip()
    return meta, base64.b64decode(t[q + 3:e]), credit


def rb(v):   # 网页版坐标（米）→ Roblox（格）
    v = np.asarray(v, dtype=np.float64)
    return np.stack([-v[..., 1], v[..., 2], -v[..., 0]], axis=-1) * S


def rbn(n):  # 法线：同样转，不缩放
    n = np.asarray(n, dtype=np.float64)
    return np.stack([-n[..., 1], n[..., 2], -n[..., 0]], axis=-1)


def part_group(meta, pi, wheel_ix):
    if pi < 0:
        return 'Body'
    p = meta['parts'][pi]
    n, k = p.get('n', ''), p.get('k', '')
    if n == 'whl':
        return 'W%02d' % wheel_ix[pi]
    if n in GROUP:
        return GROUP[n]
    if k == 'yaw':
        return 'Turret'
    return 'Body'


def image_bytes(meta, binb, ii, alpha):
    """贴图 → (字节, mime)：PNG / JPEG 原样留着（太大才缩），别的格式转一下"""
    I = meta['imgs'][ii]
    raw = binb[I['o']:I['o'] + I['n']]
    im = Image.open(io.BytesIO(raw))
    big = max(im.size) > TEXMAX
    if not big and I['m'] in ('image/jpeg', 'image/png'):
        return raw, I['m'], im.size
    if big:
        k = TEXMAX / max(im.size)
        im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
    buf = io.BytesIO()
    if alpha or im.mode in ('RGBA', 'LA', 'P'):
        im.convert('RGBA').save(buf, 'PNG', optimize=True)
        return buf.getvalue(), 'image/png', im.size
    im.convert('RGB').save(buf, 'JPEG', quality=90)
    return buf.getvalue(), 'image/jpeg', im.size


def convert(key):
    meta, binb, credit = load(key)
    st = meta.get('st', 8)
    vb0, vbn = meta['vb']
    VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st)
    ib0, ibn = meta['ib']
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0)
    wheel_ix = {}
    for pi, p in enumerate(meta.get('parts', [])):
        if p.get('n') == 'whl':
            wheel_ix[pi] = len(wheel_ix) + 1
    segs = meta['lod'][0]   # 最精细的一档
    # 按（部件，材质）收三角形
    bins = {}
    for mi, pi, s0, cnt in segs:
        g = part_group(meta, pi, wheel_ix)
        bins.setdefault((g, mi), []).append(IB[s0:s0 + cnt])
    pieces = []   # (部件, 材质, 顶点下标数组)
    for (g, mi), lst in sorted(bins.items()):
        idx = np.concatenate(lst).reshape(-1, 3)
        for c0 in range(0, len(idx), CHUNK):
            pieces.append((g, mi, idx[c0:c0 + CHUNK]))
    # 原点：车身（不含炮塔、炮）的中心、全车最低点——坦克的炮管往前伸好几米，按整个包围盒取中心的话，
    #   车身会比游戏里的碰撞盒往后错开 2～4 格
    used = np.unique(np.concatenate([p[2].reshape(-1) for p in pieces]))
    allP = rb(VB[used, 0:3])
    lo, hi = allP.min(0), allP.max(0)
    hull_ix = [p[2].reshape(-1) for p in pieces if p[0] not in ('Turret', 'Gun')]
    hP = rb(VB[np.unique(np.concatenate(hull_ix)), 0:3]) if hull_ix else allP
    hlo, hhi = hP.min(0), hP.max(0)
    org = np.array([(hlo[0] + hhi[0]) / 2, lo[1], (hlo[2] + hhi[2]) / 2])
    info = {'len': float(hi[2] - lo[2]), 'w': float(hi[0] - lo[0]), 'h': float(hi[1] - lo[1]),
            'hull': [round(float(x), 3) for x in (hhi - hlo)], 'parts': {}, 'wheels': {}, 'credit': credit}
    out = []   # (节点名, 部件, 材质, P, N, UV, idx)
    count = {}
    for g, mi, tri in pieces:
        u, inv = np.unique(tri.reshape(-1), return_inverse=True)
        v = VB[u]
        P = rb(v[:, 0:3]) - org
        N = rbn(v[:, 3:6])
        UV = v[:, 6:8].astype(np.float64)
        count[g] = count.get(g, 0) + 1
        name = '%s_%d' % (g, count[g])
        plo, phi = P.min(0), P.max(0)
        c = (plo + phi) / 2
        info['parts'][name] = {'g': g, 'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in np.maximum(phi - plo, 0.02)]}
        m = meta['mats'][mi]
        if not m.get('t'):   # 没有底色贴图的材质（JLTV、M270 整车都是）：Studio 导入不一定把材质颜色带到 MeshPart 上，游戏里照这个上色
            lin = m.get('c', [1, 1, 1, 1])
            srgb = [int(round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in (max(0.0, min(1.0, float(v))) for v in lin[:3])]
            info['parts'][name]['col'] = srgb
            if m.get('am', 0) == 2 and len(lin) > 3 and lin[3] < 0.99:
                info['parts'][name]['a'] = round(float(lin[3]), 2)
            if (m.get('mr') or [0, 0.8])[0] > 0.5:
                info['parts'][name]['met'] = 1
        out.append((name, g, mi, P - c, N, UV, inv.reshape(-1, 3).astype(np.uint32)))
    # 车轮：每个轮（几块合起来）的中心和半径
    for g in sorted(set(p[1] for p in out if p[1].startswith('W'))):
        Ps = [o[3] + np.array(info['parts'][o[0]]['c']) for o in out if o[1] == g]
        A = np.concatenate(Ps)
        wlo, whi = A.min(0), A.max(0)
        info['wheels'][g] = {'c': [round(float(x), 3) for x in (wlo + whi) / 2], 'r': round(float(max(whi[1] - wlo[1], whi[2] - wlo[2]) / 2), 3)}
    # 炮塔转轴、炮耳轴、炮口
    for p in meta.get('parts', []):
        n = p.get('n', '')
        if n in ('tur', 'rws') or p.get('k') == 'yaw':
            info['tur'] = [round(float(x), 3) for x in (rb(p['p']) - org)]
        if n in ('gun', 'lnch') and 'q' in p:
            info['gun'] = [round(float(x), 3) for x in (rb(p['q']) - org)]
    if 'gun' in info:
        G = [o[3] + np.array(info['parts'][o[0]]['c']) for o in out if o[1] == 'Gun']
        if G:
            A = np.concatenate(G)
            info['muz'] = round(float(info['gun'][2] - A[:, 2].min()), 3)   # 炮口在耳轴前面多远（−Z 朝前）
    return meta, binb, info, out


def write_glb(key, meta, binb, info, out, path):
    J = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield mdl2glb.py'}, 'scene': 0, 'scenes': [{'name': 'V_' + key, 'nodes': [0]}],
         'nodes': [{'name': 'V_' + key, 'children': []}], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [], 'materials': [],
         'textures': [], 'images': [], 'samplers': []}
    blob = bytearray()

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        o = len(blob)
        blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': o, 'byteLength': len(data)}
        if target:
            bv['target'] = target
        J['bufferViews'].append(bv)
        return len(J['bufferViews']) - 1

    def acc(arr, typ, ctype=5126, minmax=False, target=34962):
        a = {'bufferView': view(np.ascontiguousarray(arr).tobytes(), target), 'componentType': ctype, 'count': len(arr), 'type': typ}
        if minmax:
            a['min'] = [float(v) for v in arr.min(0)]
            a['max'] = [float(v) for v in arr.max(0)]
        J['accessors'].append(a)
        return len(J['accessors']) - 1

    img_ix, samp_ix, tex_ix = {}, {}, {}

    def texture(ref, alpha=False):
        if not ref:
            return None
        ii = ref[0]
        wrap = (WRAP.get(ref[1] if len(ref) > 1 else 0, 10497), WRAP.get(ref[2] if len(ref) > 2 else 0, 10497))
        if ii not in img_ix:
            data, mime, size = image_bytes(meta, binb, ii, alpha)
            J['images'].append({'bufferView': view(data), 'mimeType': mime, 'name': 'V_%s_tex%d' % (key, ii)})
            img_ix[ii] = len(J['images']) - 1
        if wrap not in samp_ix:
            J['samplers'].append({'wrapS': wrap[0], 'wrapT': wrap[1], 'magFilter': 9729, 'minFilter': 9987})
            samp_ix[wrap] = len(J['samplers']) - 1
        k = (img_ix[ii], samp_ix[wrap])
        if k not in tex_ix:
            J['textures'].append({'source': k[0], 'sampler': k[1]})
            tex_ix[k] = len(J['textures']) - 1
        return tex_ix[k]

    mat_ix = {}

    def material(mi):
        if mi in mat_ix:
            return mat_ix[mi]
        m = meta['mats'][mi]
        am = m.get('am', 0)
        pbr = {'baseColorFactor': [float(x) for x in m.get('c', [1, 1, 1, 1])]}
        mr = m.get('mr') or [0, 0.8]
        pbr['metallicFactor'], pbr['roughnessFactor'] = float(mr[0]), float(mr[1])
        t = texture(m.get('t'), am != 0)
        if t is not None:
            pbr['baseColorTexture'] = {'index': t}
        if m.get('mrt') and not m.get('sg'):
            t2 = texture(m.get('mrt'))
            if t2 is not None:
                pbr['metallicRoughnessTexture'] = {'index': t2}
        M = {'name': 'V_%s_%s' % (key, m.get('n', 'm%d' % mi)), 'pbrMetallicRoughness': pbr, 'doubleSided': bool(m.get('ds', 0))}
        if m.get('nt'):
            tn = texture(m.get('nt'))
            if tn is not None:
                M['normalTexture'] = {'index': tn, 'scale': float(m.get('ns', 1))}
        if am == 1:
            M['alphaMode'], M['alphaCutoff'] = 'MASK', float(m.get('ac', 0.5))
        elif am == 2:
            M['alphaMode'] = 'BLEND'
        J['materials'].append(M)
        mat_ix[mi] = len(J['materials']) - 1
        return mat_ix[mi]

    for name, g, mi, P, N, UV, idx in out:
        nrm = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        prim = {'attributes': {'POSITION': acc(P.astype(np.float32), 'VEC3', minmax=True), 'NORMAL': acc(nrm.astype(np.float32), 'VEC3'),
                               'TEXCOORD_0': acc(UV.astype(np.float32), 'VEC2')},
                'indices': acc(idx.reshape(-1), 'SCALAR', 5125, target=34963), 'material': material(mi)}
        J['meshes'].append({'name': 'V_%s__%s' % (key, name), 'primitives': [prim]})
        J['nodes'].append({'name': 'V_%s__%s' % (key, name), 'mesh': len(J['meshes']) - 1, 'translation': info['parts'][name]['c']})
        J['nodes'][0]['children'].append(len(J['nodes']) - 1)
    if not J['samplers']:
        del J['samplers']
    for k in ('textures', 'images'):
        if not J[k]:
            del J[k]
    J['buffers'].append({'byteLength': len(blob)})
    js = json.dumps(J, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)


def lua(v):
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            kk = k if k.isidentifier() else '[%s]' % json.dumps(k, ensure_ascii=False)
            items.append('%s = %s' % (kk, lua(v[k])))
        return '{ ' + ', '.join(items) + ' }'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, float):
        return ('%.3f' % v).rstrip('0').rstrip('.')
    return str(v)


if __name__ == '__main__':
    keys = sorted(set(ALIAS.values()))
    os.makedirs(OUTDIR, exist_ok=True)
    meta_out = {}
    for key in keys:
        if ONLY and key not in ONLY:
            continue
        meta, binb, info, out = convert(key)
        path = os.path.join(OUTDIR, key + '.glb')
        write_glb(key, meta, binb, info, out, path)
        meta_out[key] = info
        tris = sum(len(o[6]) for o in out)
        print('%-8s %7d 个三角形  %2d 块  %5.1f × %4.1f × %4.1f 格  %5.1f MB  炮塔 %-5s 炮 %-5s 车轮 %d' % (
            key, tris, len(out), info['len'], info['w'], info['h'], os.path.getsize(path) / 1e6, 'tur' in info, 'gun' in info, len(info['wheels'])))
    if ONLY and os.path.exists(META):   # 只转了几个：其余的元数据留着（读回旧文件太麻烦，只转几个时不改元数据）
        print('只转了 %s，元数据没改' % ', '.join(ONLY))
        sys.exit(0)
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/mdl2glb.py），别手改：网页版装备模型原样转成的 Roblox 模型（models/veh/<模型键>.glb）的元数据\n')
        f.write('--   alias：游戏里的型号 → 模型键；m[模型键] = { len 长 / w 宽 / h 高（格，真实尺寸：1 米 = 2.8 格；含炮管、天线）, hull 车身的宽高长（不含炮塔、炮）,\n')
        f.write('--     parts[块名] = { g 部件（Body / Turret / Gun / W01…）, c 中心, s 大小,\n')
        f.write('--       col 没有底色贴图的块的颜色（sRGB 0–255）, a 不透明度（半透明的才有）, met 金属 }（原点在车底中心，−Z 朝前）,\n')
        f.write('--     tur 炮塔转轴, gun 炮耳轴, muz 炮口在耳轴前多远, wheels[部件] = { c 中心, r 半径 }, credit 署名 }；导入后 MeshPart 叫 V_<模型键>__<块名>\n')
        f.write('return {\n  alias = ' + lua(ALIAS) + ',\n  m = {\n')
        for key in keys:
            if key in meta_out:
                f.write('    %s = %s,\n' % (key, lua(meta_out[key])))
        f.write('  },\n}\n')
    # 署名（CC-BY 要写作者、出处、授权、改了什么）：照网页版 docs/credits.md 那一条（含网页版的改动），再加这里的改动
    web_cred = {}
    try:
        for ln in open(os.path.join(WEB, 'docs', 'credits.md'), encoding='utf-8'):
            for key in keys:
                if '（js/mdl/%s.js）：' % key in ln:
                    web_cred[key] = ln.strip().lstrip('- ').split('（js/mdl/', 1)[0], ln.strip().split('.js）：', 1)[1]
    except OSError:
        pass
    with open(os.path.join(OUTDIR, 'credits.txt'), 'w', encoding='utf-8') as f:
        f.write('Roblox全面大战场的地面载具模型（models/veh/<模型键>.glb）：从网页版《暗剑》烘焙的装备模型原样转换（js/mdl/<模型键>.js）\n')
        f.write('  这里的改动：坐标换成 Roblox 的轴向、按 1 米 = 2.8 格缩放、原点挪到车底中心；按部件（车体 / 炮塔 / 炮 / 每个车轮）和材质切成几块，'
                '每块不超过 %d 个三角形；超过 %d 像素的贴图缩到 %d；不减面\n\n' % (CHUNK, TEXMAX, TEXMAX))
        for key in keys:
            if key not in meta_out:
                continue
            if key in web_cred:
                name, line = web_cred[key]
                f.write('- %s（%s.glb）：%s\n' % (name, key, line.replace('（改动：', '（网页版的改动：')))
            else:
                f.write('- %s.glb：%s\n' % (key, meta_out[key]['credit']))
    print('写好了 %s/*.glb、%s/credits.txt 和 %s' % (OUTDIR, OUTDIR, META))
