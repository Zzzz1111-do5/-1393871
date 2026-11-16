# 网页版《暗剑》的舰艇模型 → Roblox Studio「导入 3D」用的 GLB（models/ship/<型号>.glb，每艘一个）+ 游戏用的元数据
#   python3 -I tools/models/ship2glb.py <网页版仓库目录> <ShipDefs 导出的 JSON> [输出目录，默认 models/ship] [元数据，默认 src/ReplicatedStorage/ImportedShip.lua]
#   ShipDefs 的 JSON：在仓库根目录 lune run tools/models/shipdefs.luau > shipdefs.json（炮位、吃水、上层建筑：挑炮塔、摆航行灯要用）
# 来源：055、054A、DDG-125、CG-47、LCS-2 是网页版 assets/models/u_<键>.bin（DSM2 格式：tools/mdl/tbuild.mjs 转的，x 船头、y 右舷、z 上，原点在水线，米）
#   + 贴图 u_<键>_<号>.jpg / webp；022、PBR 是 js/mdl/<键>.js（和地面载具同一种格式，原点在船底）
# 和地面载具、飞机一样原样转（不减面、原贴图），但按游戏里舰艇的比例：真船的 0.6 倍（1 米 = 1.68 格，ShipDefs 的说明；地图上的航母、码头都是这个比例），
#   正好和 ShipDefs 的长度对上（055 长 302 格 = 180 米）。坐标：X 右、Y 上、−Z 船头，原点在水线、船长和船宽的中间（ShipView 的船体坐标）
# 部件：船体 Hull；主炮 T1、T2……（炮塔连炮管，从船体里按连通块挑出来：游戏里跟着炮塔转）
#   每个部件按材质分块：MeshPart 叫 S_<型号>__<部件>_<块号>（开服时 Imports.lua 收进 ReplicatedStorage.Imported.Ship.<型号>）
import io, json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402  贴图、材质、GLB 写出、署名、Lua 输出共用
import air2glb as A   # noqa: E402  连通块

S = B.S * 0.6   # 1 米 = 1.68 格
CHUNK = B.CHUNK
# 游戏里的型号 → (格式, 网页版的模型, 水线再往下压多少米（DSM2 的；网页版 V3U_SHIP 的 dz）)
SRC = {
    't055': ('dsm2', 'u_t055f', 0), 't054a': ('dsm2', 'u_t054a', -0.9), 'ddg125': ('dsm2', 'u_ddg125', 0), 'cg47': ('dsm2', 'u_cg47', 0),
    'lcs2': ('dsm2', 'u_lcs2', 0), 't022': ('mdl', 'type22', None), 'pbr': ('mdl', 'pbr', None),
}
# 原模型上主炮炮塔的中心（x、z，格）和半径：从俯视图量的（型号表 ShipDefs 的炮位是照零件拼的船定的，和原模型差了十几二十格）；
#   'comp'：按连通块挑（PBR 的双联机枪是单独的一块）；022 的 30 毫米炮从模型上分不出来，不挑（原模型上的炮不转）
GUNPIV = {'t055': [(0, -92.7, 3.6)], 't054a': [(0, -69.2, 4.2)], 'ddg125': [(None, -78.1, 3.8)], 'cg47': [(0, -90.1, 3.9), (0, 120.2, 3.9)],
          'lcs2': [(0, -47.4, 3.3)], 'pbr': 'comp', 't022': []}
# 网页版 js/v3utex.js V3U_LIST 的署名（DSM2 的模型不在 docs/credits.md 的 js/mdl 那几条里）
CREDIT = {
    'u_t055f': ('055 型驱逐舰', 'CN TYPE 055 Nanchang v3.0', 'FeriseCAT', 'https://sketchfab.com/3d-models/cn-type-055-nanchang-v30-8850f8cf1eee409abe08519fd54809cd'),
    'u_t054a': ('054A 型护卫舰', 'Type-054A Class Frigate', 'Muhamad Mirza Arrafi', 'https://sketchfab.com/3d-models/type-054a-class-frigate-948cca64a5274644a35e4600e023d61d'),
    'u_ddg125': ('阿利·伯克级驱逐舰（Flight III）', 'USS Jack H. Lucas DDG-125', 'SB-129', 'https://sketchfab.com/3d-models/uss-jack-h-lucas-ddg-125-1c9229b49915454c8ff22605f8cc7b66'),
    'u_cg47': ('提康德罗加级巡洋舰', 'Ticonderoga Missile Cruiser', 'waelXcm', 'https://sketchfab.com/3d-models/ticonderoga-missile-cruiser-397bd2b7bcd946e4b508869f4ca1e1cf'),
    'u_lcs2': ('独立级濒海战斗舰', 'USS INDEPENDENCE  LCS-2', 'Muhamad Mirza Arrafi', 'https://sketchfab.com/3d-models/uss-independence-lcs-2-7db04398d9524a36a6e08bead0050b76'),
}


def parse_dsm2(path):
    """网页版 js/v3props.js v3pParse 的 Python 版：{ tex 每张贴图是不是 webp, mats, vars: [{ name, groups: [{ mi, P 米, N, UV, I }] }] }"""
    b = open(path, 'rb').read()
    if b[:4] != b'DSM2':
        raise ValueError('不是 DSM2：' + path)
    o = 4
    nV, nM, nT = struct.unpack_from('<3I', b, o)
    o += 12

    def al(x):
        return (x + 3) & ~3
    tex = list(b[o:o + nT])
    o = al(o + nT)
    mats = []
    for _ in range(nM):
        mats.append({'ti': b[o], 'mode': b[o + 1], 'two': b[o + 2], 'bf': struct.unpack_from('<4f', b, o + 4), 'cut': struct.unpack_from('<f', b, o + 20)[0]})
        o += 24
    vars_ = []
    for _ in range(nV):
        ln = b[o]
        name = b[o + 1:o + 1 + ln].decode()
        o = al(o + 1 + ln)
        mn = np.array(struct.unpack_from('<3f', b, o))
        mx = np.array(struct.unpack_from('<3f', b, o + 12))
        o += 24
        nG = struct.unpack_from('<I', b, o)[0]
        o += 4
        groups = []
        for _ in range(nG):
            mi, nv, ni = struct.unpack_from('<3I', b, o)
            o += 12
            Q = np.frombuffer(b, dtype='<u2', count=nv * 3, offset=o).reshape(-1, 3).astype(np.float64)
            o = al(o + nv * 6)
            N = np.frombuffer(b, dtype='i1', count=nv * 3, offset=o).reshape(-1, 3).astype(np.float64) / 127.0
            o = al(o + nv * 3)
            UV = np.frombuffer(b, dtype='<f4', count=nv * 2, offset=o).reshape(-1, 2).astype(np.float64)
            o = al(o + nv * 8)
            I = np.frombuffer(b, dtype='<u2', count=ni, offset=o).astype(np.int64)
            o = al(o + ni * 2)
            o = al(o + ni // 3)   # 每个三角形一个棱线标记（网页版画发光棱线用），这里不要
            groups.append({'mi': mi, 'P': mn + Q / 65535.0 * (mx - mn), 'N': N, 'UV': UV, 'I': I})
        vars_.append({'name': name, 'groups': groups})
    return {'tex': tex, 'mats': mats, 'vars': vars_}


def load_dsm2(web, key, dz):
    """DSM2 → 和 js/mdl 一样的 meta / binb（贴图字节接在 binb 里），顶点已经是 Roblox 坐标（格，原点在水线）"""
    D = parse_dsm2(os.path.join(web, 'assets', 'models', key + '.bin'))
    blob = bytearray()
    imgs = []
    for k, webp in enumerate(D['tex']):
        p = os.path.join(web, 'assets', 'models', '%s_%d.%s' % (key, k, 'webp' if webp else 'jpg'))
        raw = open(p, 'rb').read() if os.path.exists(p) else None
        if raw is None:
            imgs.append(None)
            continue
        imgs.append({'o': len(blob), 'n': len(raw), 'm': 'image/webp' if webp else 'image/jpeg'})
        blob.extend(raw)
    mats = []
    for i, m in enumerate(D['mats']):
        M = {'n': 'm%d' % i, 'c': [float(x) for x in m['bf']], 'mr': [0, 0.75], 'ds': int(m['two']), 'am': int(m['mode']), 'ac': float(m['cut'])}
        if m['ti'] < len(imgs) and imgs[m['ti']] is not None:
            M['t'] = [m['ti'], 0, 0]
        mats.append(M)
    P, N, UV, T, TM = [], [], [], [], []
    base = 0
    for V in D['vars'][:1]:   # 舰艇只有一个变体
        for g in V['groups']:
            p = g['P']
            P.append(np.stack([p[:, 1], p[:, 2] + dz, -p[:, 0]], axis=-1) * S)   # x 船头、y 右舷、z 上 → X 右、Y 上、−Z 船头
            n = g['N']
            N.append(np.stack([n[:, 1], n[:, 2], -n[:, 0]], axis=-1))
            UV.append(g['UV'])
            T.append(g['I'].reshape(-1, 3) + base)
            TM += [g['mi']] * (len(g['I']) // 3)
            base += len(p)
    meta = {'mats': mats, 'imgs': [x or {'o': 0, 'n': 0, 'm': 'image/jpeg'} for x in imgs]}
    return meta, bytes(blob), np.concatenate(P), np.concatenate(N), np.concatenate(UV), np.concatenate(T), np.array(TM)


def load_mdl(key, draft):
    """js/mdl（x 前、y 左、z 上，原点在船底中心，米）→ Roblox 坐标（格），水线在船底往上 draft 格"""
    meta, binb, credit = B.load(key)
    st = meta.get('st', 8)
    vb0, vbn = meta['vb']
    VB = np.frombuffer(binb, dtype='<f4', count=vbn // 4, offset=vb0).reshape(-1, st).astype(np.float64)
    ib0, ibn = meta['ib']
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=ibn // meta['it'], offset=ib0).astype(np.int64)
    T, TM = [], []
    for mi, pi, s0, cnt in meta['lod'][0]:
        t = IB[s0:s0 + cnt].reshape(-1, 3)
        T.append(t)
        TM += [mi] * len(t)
    P = np.stack([-VB[:, 1], VB[:, 2], -VB[:, 0]], axis=-1) * S
    P[:, 1] -= P[:, 1].min() + draft
    N = np.stack([-VB[:, 4], VB[:, 5], -VB[:, 3]], axis=-1)
    return meta, binb, P, N, VB[:, 6:8], np.concatenate(T), np.array(TM), credit


def fix_winding(P, N, T):
    """三角形的绕向和顶点法线对不上（DSM2 是左手坐标转过来的）就整体翻过来"""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    fn = np.cross(b - a, c - a)
    vn = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
    agree = (np.einsum('ij,ij->i', fn, vn) > 0).mean()
    return (T[:, [0, 2, 1]], agree) if agree < 0.5 else (T, agree)


def convert(sid, D, web):
    fmt, key, dz = SRC[sid]
    if fmt == 'dsm2':
        meta, binb, P, N, UV, T, TM = load_dsm2(web, key, dz)
        c = CREDIT[key]
        credit = '%s：%s，作者 %s（%s），CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）' % (c[0], c[1], c[2], c[3])
    else:
        meta, binb, P, N, UV, T, TM, credit = load_mdl(key, D['draft'])
    T, agree = fix_winding(P, N, T)
    # 原点：船长、船宽的中间（高度已经是水线 = 0）
    lo, hi = P.min(0), P.max(0)
    org = np.array([(lo[0] + hi[0]) / 2, 0, (lo[2] + hi[2]) / 2])
    P = P - org
    lo, hi = P.min(0), P.max(0)
    G = np.array(['Hull'] * len(T), dtype=object)
    # 主炮（炮塔连炮管）：游戏里跟着炮塔转——
    #   按三角形挑：炮塔中心（GUNPIV 量好的）半径以内、甲板以上的，加上炮管走廊里（中线左右 0.9 格、往炮口方向一根炮管长）的；
    #   甲板高 = 炮塔外一圈往下打的最高交点里最低的；PBR 的双联机枪按连通块挑
    Pt = P[T]
    C = Pt.mean(axis=1)
    guns = []
    spec = GUNPIV.get(sid, [])
    for gi, g in enumerate(D['guns'], 1):
        name = 'T%d' % gi
        fwd = -1 if not g['aft'] else 1
        if spec == 'comp':
            cid = A.components(P, T)
            gx, gy, gz = g['pos']
            sx, sy, sz = g['size']
            za, zb = gz + fwd * (sz * 0.7 + g['len'] * 1.1), gz - fwd * sz * 0.75
            sel_all = np.zeros(len(T), dtype=bool)
            for r in np.unique(cid):
                sel = cid == r
                q = Pt[sel].reshape(-1, 3)
                ql, qh = q.min(0), q.max(0)
                if ql[0] >= gx - sx * 0.9 and qh[0] <= gx + sx * 0.9 and ql[1] >= gy - 1.2 and qh[1] <= gy + sy * 1.8 + 1 and ql[2] >= min(za, zb) and qh[2] <= max(za, zb):
                    sel_all |= sel
            deck = gy
        elif gi <= len(spec):
            cx, cz, rr = spec[gi - 1]
            if cx is None:   # 左右没量准的：照炮塔附近（高出甲板的）三角形的中线
                near = (np.hypot(C[:, 0], C[:, 2] - cz) < rr) & (C[:, 1] > g['pos'][1] - 2)
                cx = float((Pt[near][:, :, 0].min() + Pt[near][:, :, 0].max()) / 2) if near.any() else 0.0
            tops = []
            for a in np.linspace(0, 2 * np.pi, 12, endpoint=False):
                h = A.ray_ud(Pt, cx + np.cos(a) * (rr + 1.5), cz + np.sin(a) * (rr + 1.5))
                if h:
                    tops.append(h[1])
            deck = float(min(tops)) if tops else float(g['pos'][1])
            house = (np.hypot(C[:, 0] - cx, C[:, 2] - cz) <= rr) & (C[:, 1] >= deck + 0.15)
            hh = float(Pt[house][:, :, 1].max() - deck) if house.any() else 3.0
            L = g['len'] * 1.1 + rr * 0.6   # 炮管走廊：比型号表的炮管长一成（再长会带上船尾的鱼叉发射架）
            zl, zr = (cz - L, cz - rr * 0.3) if fwd < 0 else (cz + rr * 0.3, cz + L)
            barrel = (np.abs(C[:, 0] - cx) <= 0.9) & (C[:, 2] >= zl) & (C[:, 2] <= zr) & (C[:, 1] >= deck + 0.4) & (C[:, 1] <= deck + hh + 0.5)
            sel_all = house | barrel
        else:
            guns.append(None)
            continue
        if not sel_all.any():
            guns.append(None)
            continue
        G[sel_all] = name
        q = Pt[sel_all].reshape(-1, 3)
        if spec == 'comp':
            ql, qh = q.min(0), q.max(0)
            piv = [float((ql[0] + qh[0]) / 2), float(deck), float((ql[2] + qh[2]) / 2)]
        else:
            piv = [float(cx), float(deck), float(cz)]
        tip = float((piv[2] - q[:, 2].min()) if fwd < 0 else (q[:, 2].max() - piv[2]))   # 炮口离转轴多远（顺着炮管）
        guns.append({'g': name, 'piv': [round(x, 3) for x in piv], 'tip': round(tip, 3), 'n': int(sel_all.sum())})
    info = {'len': float(hi[2] - lo[2]), 'w': float(hi[0] - lo[0]), 'h': float(hi[1]), 'draft': float(-lo[1]), 'parts': {}, 'guns': guns, 'credit': credit}
    out = []
    count = {}
    for g in ['Hull'] + ['T%d' % i for i in range(1, len(D['guns']) + 1)]:
        for mi in sorted(set(TM[G == g].tolist())):
            idx_all = T[(G == g) & (TM == mi)]
            for c0 in range(0, len(idx_all), CHUNK):
                tri = idx_all[c0:c0 + CHUNK]
                u, inv = np.unique(tri.reshape(-1), return_inverse=True)
                p = P[u]
                count[g] = count.get(g, 0) + 1
                name = '%s_%d' % (g, count[g])
                plo, phi = p.min(0), p.max(0)
                cc = (plo + phi) / 2
                info['parts'][name] = {'g': g, 'c': [round(float(x), 3) for x in cc], 's': [round(float(x), 3) for x in np.maximum(phi - plo, 0.02)]}
                m = meta['mats'][mi]
                if not m.get('t'):
                    lin = m.get('c', [1, 1, 1, 1])
                    info['parts'][name]['col'] = [int(round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in (max(0.0, min(1.0, float(v))) for v in lin[:3])]
                    if m.get('am', 0) == 2 and len(lin) > 3 and lin[3] < 0.99:
                        info['parts'][name]['a'] = round(float(lin[3]), 2)
                out.append((name, g, mi, p - cc, N[u], UV[u], inv.reshape(-1, 3).astype(np.uint32)))
    # 夜航灯贴着原模型：桅顶白灯在最高点上面；艉灯在船尾甲板中线上；左红右绿在主桅前面一段、甲板以上的上层建筑最宽的地方（舰桥翼）
    V = P[np.unique(T[G == 'Hull'].reshape(-1))]
    k = int(np.argmax(V[:, 1]))
    info['top'] = [round(float(V[k, 0]), 3), round(float(V[k, 1]), 3), round(float(V[k, 2]), 3)]
    rear = V[(V[:, 2] > hi[2] - 8) & (np.abs(V[:, 0]) < 8)]
    if len(rear):
        info['stern'] = [0, round(float(rear[:, 1].max()), 3), round(float(rear[:, 2].max()), 3)]
    deck = float(D['deck'])   # 甲板高照型号表（三体船最宽的地方在水线附近、桅杆横桁也很宽，按高度圈住舰桥那一层）
    tz = info['top'][2]
    band = V[(V[:, 1] > deck + 3) & (V[:, 1] < deck + 20) & (V[:, 2] > tz - 30) & (V[:, 2] < tz + 4)]
    if len(band) and not D.get('open'):
        k2 = int(np.argmax(np.abs(band[:, 0])))
        info['side'] = [round(float(abs(band[k2, 0])), 3), round(float(band[k2, 1]), 3), round(float(band[k2, 2]), 3)]
    return meta, binb, info, out, agree


if __name__ == '__main__':
    B.WEB = sys.argv[1]
    SD = json.load(open(sys.argv[2], encoding='utf-8'))
    OUTDIR = sys.argv[3] if len(sys.argv) > 3 else 'models/ship'
    META = sys.argv[4] if len(sys.argv) > 4 else 'src/ReplicatedStorage/ImportedShip.lua'
    os.makedirs(OUTDIR, exist_ok=True)
    meta_out = {}
    for sid in sorted(SRC):
        meta, binb, info, out, agree = convert(sid, SD[sid], B.WEB)
        path = os.path.join(OUTDIR, sid + '.glb')
        B.write_glb(sid, meta, binb, info, out, path, prefix='S_')
        meta_out[sid] = info
        tris = sum(len(o[6]) for o in out)
        print('%-6s %7d 个三角形  %3d 块  长 %5.1f 宽 %4.1f 高 %4.1f 吃水 %4.1f 格（型号表长 %d）  %5.1f MB  绕向一致 %.0f%%  炮 %s' % (
            sid, tris, len(out), info['len'], info['w'], info['h'], info['draft'], SD[sid]['L'], os.path.getsize(path) / 1e6, agree * 100,
            ' '.join('%s:%s' % (g['g'], g['n']) if g else '没找到' for g in info['guns'])))
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/ship2glb.py），别手改：网页版舰艇模型原样转成的 Roblox 模型（models/ship/<型号>.glb）的元数据\n')
        f.write('--   m[型号] = { len 长 / w 宽 / h 水线以上高 / draft 吃水（格，游戏里舰艇的比例：1 米 = 1.68 格）, parts[块名] = { g 部件（Hull / T1 / T2…）, c 中心, s 大小, col 没贴图的块的颜色 },\n')
        f.write('--     guns[第几座炮] = { g 部件, piv 炮塔转轴（在甲板上）, tip 炮口离转轴多远, n 三角形数 }（没挑出来的是 false；ShipDefs 的炮位、炮管长照这个改）,\n')
        f.write('--     top 最高点（桅顶）, stern 船尾甲板, side 舰桥一侧的航行灯 { x, y, z }, credit 署名 }\n')
        f.write('--   坐标：X 右、Y 上、−Z 船头，原点在水线、船长和船宽的中间（ShipView 的船体坐标）；导入后 MeshPart 叫 S_<型号>__<块名>\n')
        f.write('return {\n  m = {\n')
        for sid in sorted(meta_out):
            info = dict(meta_out[sid])
            info['guns'] = [g if g else False for g in info['guns']]
            f.write('    %s = %s,\n' % (sid, B.lua(info)))
        f.write('  },\n}\n')
    with open(os.path.join(OUTDIR, 'credits.txt'), 'w', encoding='utf-8') as f:
        f.write('Roblox全面大战场的舰艇模型（models/ship/<型号>.glb）：从网页版《暗剑》的舰艇模型原样转换\n'
                '  这里的改动：坐标换成 Roblox 的轴向、按游戏里舰艇的比例缩放（真船的 0.6 倍：1 米 = 1.68 格）、原点挪到水线中心；主炮从船体上分出来（游戏里跟着炮塔转）；'
                '按材质切成几块，每块不超过 %d 个三角形；超过 %d 像素的贴图缩到 %d；不减面\n\n' % (CHUNK, B.TEXMAX, B.TEXMAX))
        wc = B.web_credits(['type22', 'pbr'])
        for sid in sorted(meta_out):
            fmt, key, _ = SRC[sid]
            if fmt == 'dsm2':
                c = CREDIT[key]
                f.write('- %s（%s.glb）：This work is based on "%s" (%s) by %s licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)\n' % (c[0], sid, c[1], c[3], c[2]))
            elif key in wc:
                name, line = wc[key]
                name = {'type22': '022 型导弹艇', 'pbr': 'PBR Mk II 内河巡逻艇'}.get(key, name)   # 网页版的名字带着那边的用途（代火力支援艇、代抢修艇），这里就是本型
                f.write('- %s（%s.glb）：%s\n' % (name, sid, line.replace('（改动：', '（网页版的改动：')))
            else:
                f.write('- %s.glb：%s\n' % (sid, meta_out[sid]['credit']))
    print('写好了 %s/*.glb、%s/credits.txt 和 %s' % (OUTDIR, OUTDIR, META))
