# 网页版《暗剑》的地图建筑模型（assets/models/<包>.bin，DSM2 格式 + 贴图）→ Roblox Studio「导入 3D」用的一个 GLB（models/bld/buildings.glb）+ 元数据
#   python3 -I tools/models/bld2glb.py <网页版仓库目录> [输出目录，默认 models/bld] [元数据，默认 src/ReplicatedStorage/BuildingMeta.lua]
#   用户：继续把游戏内地图的建筑的建模优化——地图上原来是零件拼的方块房子（一个盒子 + 一块屋顶板），换成网页版地图用的写实模型（CC-BY，带贴图）
# 和舰艇（tools/models/ship2glb.py）一样读 DSM2（x 前、y 右、z 上，米，原点在地面中心；左手坐标转过来的），原样转（不减面、原贴图）：
#   比例同游戏里的人：1 米 = 2.8 格；机库、塔台按游戏里的场地缩（模型原来是 90 米宽的大修机库、90 米高的塔台）
#   坐标：X 右、Y 上、−Z 正面（网页版 V3P_HOUSE 的 rot 先把正面转到 +x，再换到 Roblox），原点在地面、占地的中心
#   每个建筑按材质、每块不超过 CHUNK 个三角形分块：MeshPart 叫 B_<键>__Body_<块号>（开服时 Imports.lua 收进 ReplicatedStorage.Imported.Bld.<键>）
#   GLB 里各建筑沿 X 排开（Studio 里导进来不叠在一起）；游戏里按元数据的块中心摆（World.lua 的 building）
import json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402  贴图、材质、GLB 写出、Lua 输出共用
import ship2glb as SG   # noqa: E402  DSM2 读取、绕向修正

S = B.S   # 1 米 = 2.8 格
CHUNK = B.CHUNK
# 键 → (包, 变体, 把正面转到 +x 的角（网页版 V3P_HOUSE 的 rot）, 缩放, 中文名)
LIST = {
    'jph1': ('jph1', 'jph1', 0, 1, '民房'),
    'jph2': ('jph2', 'jph2', math.pi / 2, 1, '民房'),    # 网页版写的 −π/2 是另一个转向约定：照这里的约定（正面转到 +x）是 +π/2（渲染看过：店面、大玻璃窗朝前）
    'jph3': ('jph3', 'jph3', math.pi / 2, 1, '民房'),
    'house': ('house', 'house', 0, 1, '瓦房'),
    'conc1': ('oldconc', 'conc1', 0, 1, '水泥楼'),
    'conc2': ('oldconc', 'conc2', 0, 1, '水泥楼'),
    'conc3': ('oldconc', 'conc3', 0, 1, '水泥楼'),
    'hangar': ('hangar', 'hangar', 0, 0.5, '机库'),        # 90 × 62 米的大修机库 → 45 × 31 米（放得下两架战斗机）
    'atc': ('atc', 'atc', 0, 0.42, '塔台'),                # 90 米高 → 38 米
    'quonset': ('quonset', 'quonset', 0, 1, '铁皮营房'),
    'firestation': ('firestation', 'firestation', 0, 1, '消防站'),
    'wh3': ('wh3', 'wh3', 0, 1, '库房'),
    'sawtooth': ('sawtooth', 'sawtooth', 0, 1, '厂房'),
    'smallwh': ('smallwh', 'smallwh', 0, 1, '小库房'),
    'industrial': ('industrial', 'industrial', 0, 1, '办公楼'),
    'flats1': ('flats1', 'flats1', 0, 1, '公寓楼'),
    'wh99': ('wh99', 'wh99', 0, 1, '砖砌库房'),
}
# 署名（网页版 js/v3props.js 的 V3P_PACKS）
CREDIT = {
    'jph1': ('Japanese Residential Home 01', 'Morrissey Alexander', 'https://sketchfab.com/3d-models/japanese-residential-home-01-d690f83d8e8d48e6a532bebe84901595'),
    'jph2': ('Japanese Residential Home 02', 'Morrissey Alexander', 'https://sketchfab.com/3d-models/japanese-residential-home-02-c31697f09152453cb3ed215482e7a810'),
    'jph3': ('Japanese Residential Home 03', 'Morrissey Alexander', 'https://sketchfab.com/3d-models/japanese-residential-home-03-1c53f4f37fc44c32a8874464025aea48'),
    'house': ('House', 'SpatialNeglect', 'https://sketchfab.com/3d-models/house-e70c4aebc911429ba9a894b38146892c'),
    'oldconc': ('Old Concete Building Pack | Lowpoly', 'Frid.blend', 'https://sketchfab.com/3d-models/old-concete-building-pack-lowpoly-6d070fcc86b0430dadf53da67545c6f3'),
    'hangar': ('j type hanger', 'ElectricL', 'https://sketchfab.com/3d-models/j-type-hanger-d86713d61b4941378a6ad21569e0cbac'),
    'atc': ('Air Traffic Control Tower', 'abass20', 'https://sketchfab.com/3d-models/air-traffic-control-tower-84f215391662453680e646649d42b264'),
    'quonset': ('Military Style Building (with animations)', 'TampaJoey', 'https://sketchfab.com/3d-models/military-style-building-with-animations-1671685e1dd94b6e9216ead632f08f6e'),
    'firestation': ('Fire Station No. 1', 'CommonSpence', 'https://sketchfab.com/3d-models/fire-station-no-1-87edf04deb28434993274d9f05070865'),
    'wh3': ('Pack - Realistic - 3 Warehouse', 'Islide', 'https://sketchfab.com/3d-models/pack-realistic-3-warehouse-320c272513a94c0482dbb3c4e79d61f5'),
    'sawtooth': ('Warehouse Building', 'OmegaRedZA', 'https://sketchfab.com/3d-models/warehouse-building-0c37b0f92cb54e07a1e1c6c3df9f8439'),
    'smallwh': ('Small Warehouse', 'Wardster', 'https://sketchfab.com/3d-models/small-warehouse-c7f4c017c20943cb9e9e559822a5c402'),
    'industrial': ('industrial building', 'spicybamer', 'https://sketchfab.com/3d-models/industrial-building-770acf6b0da74af397f748d95141f8be'),
    'flats1': ('Davison Street Flats 1 - Flat Roof', 'Charlie_Zane', 'https://sketchfab.com/3d-models/davison-street-flats-1-flat-roof-0f461ea81f8541db8d6a5f5e35133588'),
    'wh99': ('Warehouses', '99.Miles', 'https://sketchfab.com/3d-models/warehouses-e6e105d35b3f486292c42ffa52f363c0'),
}


def load(web, pack, var, rot, k):
    """一个建筑：DSM2 的这个变体 → (meta, binb, P 格, N, UV, T, TM)（Roblox 坐标：X 右、Y 上、−Z 正面，原点在地面中心）"""
    D = SG.parse_dsm2(os.path.join(web, 'assets', 'models', pack + '.bin'))
    blob = bytearray()
    imgs = []
    for i, webp in enumerate(D['tex']):
        p = os.path.join(web, 'assets', 'models', '%s_%d.%s' % (pack, i, 'webp' if webp else 'jpg'))
        raw = open(p, 'rb').read() if os.path.exists(p) else None
        if raw is None:
            imgs.append(None)
            continue
        imgs.append({'o': len(blob), 'n': len(raw), 'm': 'image/webp' if webp else 'image/jpeg'})
        blob.extend(raw)
    mats = []
    for i, m in enumerate(D['mats']):
        M = {'n': 'm%d' % i, 'c': [float(x) for x in m['bf']], 'mr': [0, 0.85], 'ds': int(m['two']), 'am': int(m['mode']), 'ac': float(m['cut'])}
        if m['ti'] < len(imgs) and imgs[m['ti']] is not None:
            M['t'] = [m['ti'], 0, 0]
        mats.append(M)
    V = [v for v in D['vars'] if v['name'] == var]
    if not V:
        raise SystemExit('%s 里没有变体 %s' % (pack, var))
    cr, sr = math.cos(rot), math.sin(rot)
    P, N, UV, T, TM = [], [], [], [], []
    base = 0
    for g in V[0]['groups']:
        p, n = g['P'], g['N']
        # 先绕竖轴转 rot（网页版坐标 x 前、y 右），让正面朝 +x
        px, py = p[:, 0] * cr - p[:, 1] * sr, p[:, 0] * sr + p[:, 1] * cr
        nx, ny = n[:, 0] * cr - n[:, 1] * sr, n[:, 0] * sr + n[:, 1] * cr
        P.append(np.stack([py, p[:, 2], -px], axis=-1) * S * k)   # x 前、y 右、z 上 → X 右、Y 上、−Z 前
        N.append(np.stack([ny, n[:, 2], -nx], axis=-1))
        UV.append(g['UV'])
        T.append(g['I'].reshape(-1, 3) + base)
        TM += [g['mi']] * (len(g['I']) // 3)
        base += len(p)
    meta = {'mats': mats, 'imgs': [x or {'o': 0, 'n': 0, 'm': 'image/jpeg'} for x in imgs]}
    P, N, UV, T, TM = np.concatenate(P), np.concatenate(N), np.concatenate(UV), np.concatenate(T), np.array(TM)
    T, agree = SG.fix_winding(P, N, T)
    # 原点：占地（包围盒）的中心、最低点
    lo, hi = P.min(0), P.max(0)
    P = P - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    return meta, bytes(blob), P, N, UV, T, TM


def convert_one(key, web, xoff):
    pack, var, rot, k, name = LIST[key]
    meta, binb, P, N, UV, T, TM = load(web, pack, var, rot, k)
    out, info = [], {'name': name, 'parts': {}}
    lo, hi = P.min(0), P.max(0)
    info['w'], info['h'], info['d'] = [round(float(x), 3) for x in (hi - lo)]
    info['o'] = [round(float(xoff), 3), 0, 0]
    cnt = 0
    for mi in sorted(set(TM.tolist())):
        idx = T[TM == mi]
        for c0 in range(0, len(idx), CHUNK):
            tri = idx[c0:c0 + CHUNK]
            u, inv = np.unique(tri.reshape(-1), return_inverse=True)
            p = P[u]
            plo, phi = p.min(0), p.max(0)
            c = (plo + phi) / 2
            cnt += 1
            pname = 'Body_%d' % cnt
            info['parts'][pname] = {'c': [round(float(x), 3) for x in c], 's': [round(float(x), 3) for x in np.maximum(phi - plo, 0.02)]}
            m = meta['mats'][mi]
            if not m.get('t'):   # 没贴图的块：游戏里按底色上色（Studio 导入不一定把材质颜色带过来）
                lin = m.get('c', [1, 1, 1, 1])
                info['parts'][pname]['col'] = [int(round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in (max(0.0, min(1.0, float(v))) for v in lin[:3])]
            out.append((pname, 'Body', mi, p - c, N[u], UV[u], inv.reshape(-1, 3).astype(np.uint32), c))
    tris = int(len(T))
    c = CREDIT[pack]
    info['credit'] = '%s：%s，作者 %s（%s），CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）' % (name, c[0], c[1], c[2])
    return meta, binb, info, out, tris


def write_pack(keys, web, path):
    """所有建筑写进一个 GLB：每个建筑一组节点（B_<键>），块的节点位置 = 排开的偏移 + 块中心"""
    infos, metas, all_out = {}, [], []
    xoff = 0.0
    for key in keys:
        meta, binb, info, out, tris = convert_one(key, web, xoff + 0)
        w = info['w']
        info['o'] = [round(xoff + w / 2, 3), 0, 0]
        infos[key] = info
        metas.append((key, meta, binb, out))
        xoff += w + 20
        print('%-11s %-6s %6d 个三角形 %2d 块  %6.1f × %5.1f × %6.1f 格（宽 × 高 × 深）' % (key, info['name'], tris, len(out), info['w'], info['h'], info['d']))
    # 合成一个 GLB：逐个建筑用 mdl2glb.write_glb 的写法会各写一个文件——这里把它们拼成一个（共用一个缓冲区）
    J = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield bld2glb.py'}, 'scene': 0, 'scenes': [{'name': 'Buildings', 'nodes': []}],
         'nodes': [], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [], 'materials': [], 'textures': [], 'images': [], 'samplers': []}
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

    for key, meta, binb, out in metas:
        img_ix, samp_ix, tex_ix, mat_ix = {}, {}, {}, {}

        def texture(ref, alpha=False):
            if not ref:
                return None
            ii = ref[0]
            wrap = (B.WRAP.get(ref[1] if len(ref) > 1 else 0, 10497), B.WRAP.get(ref[2] if len(ref) > 2 else 0, 10497))
            if ii not in img_ix:
                data, mime, size = B.image_bytes(meta, binb, ii, alpha)
                J['images'].append({'bufferView': view(data), 'mimeType': mime, 'name': 'B_%s_tex%d' % (key, ii)})
                img_ix[ii] = len(J['images']) - 1
            if wrap not in samp_ix:
                J['samplers'].append({'wrapS': wrap[0], 'wrapT': wrap[1], 'magFilter': 9729, 'minFilter': 9987})
                samp_ix[wrap] = len(J['samplers']) - 1
            kk = (img_ix[ii], samp_ix[wrap])
            if kk not in tex_ix:
                J['textures'].append({'source': kk[0], 'sampler': kk[1]})
                tex_ix[kk] = len(J['textures']) - 1
            return tex_ix[kk]

        def material(mi):
            if mi in mat_ix:
                return mat_ix[mi]
            m = meta['mats'][mi]
            am = m.get('am', 0)
            pbr = {'baseColorFactor': [float(x) for x in m.get('c', [1, 1, 1, 1])]}
            mr = m.get('mr') or [0, 0.85]
            pbr['metallicFactor'], pbr['roughnessFactor'] = float(mr[0]), float(mr[1])
            t = texture(m.get('t'), am != 0)
            if t is not None:
                pbr['baseColorTexture'] = {'index': t}
            M = {'name': 'B_%s_%s' % (key, m.get('n', 'm%d' % mi)), 'pbrMetallicRoughness': pbr, 'doubleSided': bool(m.get('ds', 0))}
            if am == 1:
                M['alphaMode'], M['alphaCutoff'] = 'MASK', float(m.get('ac', 0.5))
            elif am == 2:
                M['alphaMode'] = 'BLEND'
            J['materials'].append(M)
            mat_ix[mi] = len(J['materials']) - 1
            return mat_ix[mi]

        root = {'name': 'B_' + key, 'children': [], 'translation': infos[key]['o']}
        J['nodes'].append(root)
        ri = len(J['nodes']) - 1
        J['scenes'][0]['nodes'].append(ri)
        for name, g, mi, P, N, UV, idx, c in out:
            nrm = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
            prim = {'attributes': {'POSITION': acc(P.astype(np.float32), 'VEC3', minmax=True), 'NORMAL': acc(nrm.astype(np.float32), 'VEC3'),
                                   'TEXCOORD_0': acc(UV.astype(np.float32), 'VEC2')},
                    'indices': acc(idx.reshape(-1), 'SCALAR', 5125, target=34963), 'material': material(mi)}
            J['meshes'].append({'name': 'B_%s__%s' % (key, name), 'primitives': [prim]})
            J['nodes'].append({'name': 'B_%s__%s' % (key, name), 'mesh': len(J['meshes']) - 1, 'translation': [round(float(x), 4) for x in c]})
            J['nodes'][ri]['children'].append(len(J['nodes']) - 1)
    J['buffers'].append({'byteLength': len(blob)})
    js = json.dumps(J, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    import struct
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)
    import glbfix   # 朝里的面翻过来、只有底色的材质配纯色贴图（和别的模型一样）
    glbfix.fix_file(path, log=lambda m: print('  buildings' + m))
    return infos


if __name__ == '__main__':
    web = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else 'models/bld'
    meta_path = sys.argv[3] if len(sys.argv) > 3 else 'src/ReplicatedStorage/BuildingMeta.lua'
    os.makedirs(outdir, exist_ok=True)
    keys = list(LIST)
    infos = write_pack(keys, web, os.path.join(outdir, 'buildings.glb'))
    with open(meta_path, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/bld2glb.py），别手改：地图建筑的原模型（models/bld/buildings.glb，网页版地图用的写实模型）的元数据\n')
        f.write('--   [键] = { name 中文名, w / h / d 宽、高、深（格，1 米 = 2.8 格）, o 在 GLB 里的原点, parts[块名] = { c 中心, s 大小, col 没贴图的块的颜色 },\n')
        f.write('--     credit 署名 }；坐标 X 右、Y 上、−Z 正面，原点在地面、占地中心；导入后 MeshPart 叫 B_<键>__<块名>\n')
        f.write('return {\n')
        for key in keys:
            f.write('  %s = %s,\n' % (key, B.lua(infos[key])))
        f.write('}\n')
    with open(os.path.join(outdir, 'credits.txt'), 'w', encoding='utf-8') as f:
        f.write('Roblox全面大战场的地图建筑模型（models/bld/buildings.glb）：从网页版《暗剑》的地图模型（assets/models/<包>.bin）原样转换\n')
        f.write('  这里的改动：坐标换成 Roblox 的轴向、按 1 米 = 2.8 格缩放（机库缩到一半、塔台缩到 0.42 倍）、原点挪到占地中心；按材质切成几块\n\n')
        for key in keys:
            f.write('- %s（%s）：%s\n' % (LIST[key][4], key, infos[key]['credit'].split('：', 1)[1]))
    print('写好了 %s/buildings.glb、%s/credits.txt 和 %s' % (outdir, outdir, meta_path))
