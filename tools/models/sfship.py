# 舰艇换成 Sketchfab 上的原模型（用户 11-19：船的建模有些问题、贴图方面，去 Sketchfab 找好的换掉；所有船上的武器都能有作用、能动）
#   原来的 models/ship/*.glb 是网页版《暗剑》烘焙过的（减了面、贴图压到很小：055 的贴图只剩 8×8、512），这里直接用 Sketchfab 下载的 GLB：
#   不减面、原材质（底色贴图、法线贴图、金属度 / 粗糙度贴图，超过 1024 的缩到 1024——Roblox 的上限）。
#   和 ship2glb.py 一样的约定：X 右、Y 上、−Z 船头，原点在水线、船长和船宽的中间；比例照游戏里舰艇（长度对上元数据原来的长度）；
#   MeshPart 叫 S_<型号>__<部件>_<块号>，元数据写进 ImportedShip.lua（只换这几艘那一行，别的照旧）
#   会动的部件（照原模型量好的位置，SPEC）：
#     T<n> 第 n 座主炮的炮塔（绕 piv 转向）、B<n> 它的炮管（跟着炮塔转、绕耳轴 trn 俯仰、开炮后坐）；
#     C<n> 第 n 座近防炮（整座绕自己的竖轴转向来袭的目标）；vls 垂直发射单元的格子（游戏里在上面盖可以掀开的舱盖，导弹从格子里出来）；
#     cans 斜置的导弹发射箱（导弹从箱口出来）
#   用法：python3 -I tools/models/sfship.py <Sketchfab 下载目录（<键>/scene.glb + meta.json）> <shipdefs.json> [型号 …]
#        python3 -I tools/models/sfship.py <下载目录> <shipdefs.json> --dump <型号> <输出.npz>   量位置用：只摆好方向、比例、水线，存三角形
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import mdl2glb as B   # noqa: E402
import air2glb as A   # noqa: E402

OUTDIR = os.environ.get('SFSHIP_OUT', 'models/ship')
META = os.environ.get('SFSHIP_META', 'src/ReplicatedStorage/ImportedShip.lua')
CHUNK = B.CHUNK

# 型号 → 原模型（下载目录里的键）、船头朝原模型的哪个轴、长（格，照原来元数据的 len，跟型号表、命中盒对上）、吃水（格）
SF = {
    't055': {'dir': 't055', 'fwd': 'z-', 'len': 298.8, 'draft': 12.48, 'name': '055 型驱逐舰'},
    'ddg125': {'dir': 'ddg125', 'fwd': 'x-', 'len': 260.9, 'draft': 15.62, 'name': '阿利·伯克级驱逐舰（Flight III）'},
    'cg47': {'dir': 'cg47', 'fwd': 'z+', 'len': 290.0, 'draft': 17.3, 'name': '提康德罗加级巡洋舰'},
    't054a': {'dir': 't054a', 'fwd': 'z-', 'len': 225.12, 'draft': 8.05, 'name': '054A 型护卫舰'},
    't022': {'dir': 't022', 'fwd': 'z-', 'len': 71.6, 'draft': 3.0, 'name': '022 型导弹艇'},
}
SPEC = {}   # 武器位置（照转出来的模型量的，见下面 SPEC.update）


def tref(J, ti):
    t = J['textures'][ti]
    s = J.get('samplers', [])[t['sampler']] if 'sampler' in t and J.get('samplers') else {}
    code = {10497: 0, 33648: 1, 33071: 2}
    return [t['source'], code.get(s.get('wrapS', 10497), 0), code.get(s.get('wrapT', 10497), 0)]


def load(sid, dl):
    """Sketchfab 的 GLB → ship2glb 那一套：meta（材质、贴图）、binb（贴图字节）、P N UV T TM（游戏坐标：格，水线 Y = 0），署名"""
    sp = SF[sid]
    J, BIN = glbfix.read(os.path.join(dl, sp['dir'], 'scene.glb'))
    W = glbfix.world_mats(J)
    blob, imgs = bytearray(), []
    for im in J.get('images', []):
        bv = J['bufferViews'][im['bufferView']]
        o, n = bv.get('byteOffset', 0), bv['byteLength']
        imgs.append({'o': len(blob), 'n': n, 'm': im.get('mimeType', 'image/png')})
        blob.extend(BIN[o:o + n])
    mats = []
    for i, m in enumerate(J.get('materials', [])):
        pbr = m.get('pbrMetallicRoughness', {})
        M = {'n': 'm%d' % i, 'c': [float(x) for x in pbr.get('baseColorFactor', [1, 1, 1, 1])],
             'mr': [float(pbr.get('metallicFactor', 1.0)), float(pbr.get('roughnessFactor', 1.0))], 'ds': 1 if m.get('doubleSided') else 0}
        sg = (m.get('extensions') or {}).get('KHR_materials_pbrSpecularGlossiness')
        if sg:
            M['c'] = [float(x) for x in sg.get('diffuseFactor', [1, 1, 1, 1])]
            M['mr'] = [0.0, float(1 - sg.get('glossinessFactor', 0.4))]
            M['sg'] = 1
            if 'diffuseTexture' in sg:
                M['t'] = tref(J, sg['diffuseTexture']['index'])
        if 'baseColorTexture' in pbr:
            M['t'] = tref(J, pbr['baseColorTexture']['index'])
        if 'metallicRoughnessTexture' in pbr:
            M['mrt'] = tref(J, pbr['metallicRoughnessTexture']['index'])
        if 'normalTexture' in m:
            M['nt'] = tref(J, m['normalTexture']['index'])
            M['ns'] = float(m['normalTexture'].get('scale', 1))
        M['am'] = {'OPAQUE': 0, 'MASK': 1, 'BLEND': 2}.get(m.get('alphaMode', 'OPAQUE'), 0)
        M['ac'] = float(m.get('alphaCutoff', 0.5))
        mats.append(M)
    if not mats:
        mats.append({'n': 'm0', 'c': [0.6, 0.62, 0.64, 1], 'mr': [0.3, 0.7]})
    P, N, UV, T, TM, base = [], [], [], [], [], 0
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W:
            continue
        Mx = W[ni]
        R = Mx[:3, :3]
        Rn = np.linalg.inv(R).T
        flip = np.linalg.det(R) < 0
        for p in J['meshes'][nd['mesh']]['primitives']:
            if p.get('mode', 4) != 4:
                continue
            a = p['attributes']
            pos = glbfix.acc_read(J, BIN, a['POSITION']).astype(np.float64)
            pw = (np.c_[pos, np.ones(len(pos))] @ Mx.T)[:, :3]
            idx = glbfix.acc_read(J, BIN, p['indices']).astype(np.int64).reshape(-1, 3) if 'indices' in p else np.arange(len(pos)).reshape(-1, 3)
            if flip:
                idx = idx[:, [0, 2, 1]]
            if 'NORMAL' in a:
                nrm = glbfix.acc_read(J, BIN, a['NORMAL']).astype(np.float64) @ Rn.T
            else:   # 没有法线：按面法线平均
                fn = np.cross(pw[idx[:, 1]] - pw[idx[:, 0]], pw[idx[:, 2]] - pw[idx[:, 0]])
                nrm = np.zeros_like(pw)
                for k in range(3):
                    np.add.at(nrm, idx[:, k], fn)
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            uv = glbfix.acc_read(J, BIN, a['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in a else np.zeros((len(pos), 2))
            P.append(pw)
            N.append(nrm)
            UV.append(uv)
            T.append(idx + base)
            TM += [p.get('material', 0)] * len(idx)
            base += len(pos)
    P, N, UV, T = np.concatenate(P), np.concatenate(N), np.concatenate(UV), np.concatenate(T)
    # 朝向：原模型的 fwd 轴 → 游戏的 −Z（船头），Y 照旧朝上
    rot = {'z-': np.diag([1, 1, 1]), 'z+': np.diag([-1, 1, -1]), 'x+': np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]]),
           'x-': np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]])}[sp['fwd']].astype(np.float64)
    P, N = P @ rot.T, N @ rot.T
    # 比例：船长对上；水线：船底往上 draft 格
    k = sp['len'] / (P[:, 2].max() - P[:, 2].min())
    P = P * k
    P[:, 1] -= P[:, 1].min() + sp['draft']
    lo, hi = P.min(0), P.max(0)
    P[:, 0] -= (lo[0] + hi[0]) / 2
    P[:, 2] -= (lo[2] + hi[2]) / 2
    meta_path = os.path.join(dl, sp['dir'], 'meta.json')
    mj = json.load(open(meta_path, encoding='utf-8')) if os.path.exists(meta_path) else {}
    lic = mj.get('license') or 'CC Attribution'
    lic_s = 'CC-BY-4.0 授权（http://creativecommons.org/licenses/by/4.0/）' if lic == 'CC Attribution' else lic
    credit = '%s：%s，作者 %s（%s），%s' % (sp['name'], mj.get('name', '?'), mj.get('displayName') or mj.get('user', '?'), mj.get('url', ''), lic_s)
    TM = np.array(TM)
    keep = drop_backs(P, T, TM, sid)
    return {'mats': mats, 'imgs': imgs}, bytes(blob), P, N, UV, T[keep], TM[keep], credit, mj


def drop_backs(P, T, TM, sid, log=print):
    """SketchUp 一类软件导出的模型：每块面正反两层叠在一起（位置一样、朝向相反），外层是迷彩 / 漆，里层是默认的灰蓝反面色。
    原软件只画正面所以看着对；转出来以后 glbfix 把「朝里」的那层翻成朝外，两层颜色不同叠在一起就一道道闪（022 艇满身条纹）。
    这里把成对的两层里朝里的那层去掉（剩下的单层由 glbfix 理朝向、需要的补反面）。
    哪层朝里：从面中心沿法线打一根射线，朝外的那层大多打出去不碰东西，朝里的那层打到船体的另一边；
    按「材质对」统计（同一对材质里哪种材质打出去的多），整对材质一起定，免得一块块判断出错"""
    keep = np.ones(len(T), dtype=bool)
    Q = np.round(P[T] * 1000).astype(np.int64)
    h = (Q[:, :, 0] * 73856093) ^ (Q[:, :, 1] * 19349663) ^ (Q[:, :, 2] * 83492791)
    h.sort(axis=1)
    _, inv, cnt = np.unique(h, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    order = np.argsort(inv, kind='stable')
    grp = inv[order]
    starts = np.flatnonzero(np.r_[True, grp[1:] != grp[:-1]])
    pa, pb = [], []
    for s0 in starts:
        if cnt[grp[s0]] != 2:
            continue
        a, b = order[s0], order[s0 + 1]
        if TM[a] == TM[b]:
            continue
        pa.append(a)
        pb.append(b)
    if not pa:
        return keep
    pa, pb = np.array(pa), np.array(pb)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    opp = np.einsum('ij,ij->i', fn[pa], fn[pb]) < 0
    pa, pb = pa[opp], pb[opp]
    if not len(pa):
        return keep
    import trimesh
    mesh = trimesh.Trimesh(vertices=P, faces=T, process=False)
    both = np.r_[pa, pb]
    nn = fn[both] / np.maximum(np.linalg.norm(fn[both], axis=1, keepdims=True), 1e-12)
    org = P[T[both]].mean(axis=1) + nn * 0.02
    hit = mesh.ray.intersects_first(ray_origins=org, ray_directions=nn)
    out = hit < 0   # 打出去了
    oa, ob = out[:len(pa)], out[len(pa):]
    votes = {}
    for a, b, xa, xb in zip(pa, pb, oa, ob):
        k = (int(TM[a]), int(TM[b]))
        v = votes.setdefault(k, [0, 0])
        v[0] += int(xa)
        v[1] += int(xb)
    dropped = 0
    for a, b in zip(pa, pb):
        k = (int(TM[a]), int(TM[b]))
        v = votes[k]
        if v[0] == v[1]:
            continue
        keep[b if v[0] > v[1] else a] = False
        dropped += 1
    log('  %s：正反两层叠着的面 %d 对，去掉朝里的那层 %d 块' % (sid, len(pa), dropped))
    return keep


def bow_check(P):
    """船头那一头应该比船尾窄（船尾是方的）：返回两头吃水线附近的宽度"""
    z0, z1 = P[:, 2].min(), P[:, 2].max()
    L = z1 - z0
    low = P[:, 1] < 2
    def width(sel):
        q = P[low & sel]
        return float(q[:, 0].max() - q[:, 0].min()) if len(q) else 0.0
    return width(P[:, 2] < z0 + L * 0.06), width(P[:, 2] > z1 - L * 0.06)


if __name__ == '__main__':
    dl, sdj = sys.argv[1], sys.argv[2]
    if '--dump' in sys.argv:
        sid, out = sys.argv[sys.argv.index('--dump') + 1], sys.argv[sys.argv.index('--dump') + 2]
        meta, binb, P, N, UV, T, TM, credit, mj = load(sid, dl)
        fw, bw = bow_check(P)
        print('%s：%d 个三角形，大小 %s，船头宽 %.1f 船尾宽 %.1f（船头应该更窄）' % (sid, len(T), np.round(P.max(0) - P.min(0), 1), fw, bw))
        np.savez_compressed(out, P=P, T=T, TM=TM)
        sys.exit(0)


# 武器位置（游戏坐标，格；照转出来的模型量的）：
#   guns：每座主炮 (炮塔中心 x, z, 炮塔半径)；炮管顺着走廊挑（ship2glb 的做法），单独成 B<n>
#   ciws：每座近防炮 (x, z, 半径, 最低高度)：整块连通块都在这个圆柱里的成 C<n>（整座转）
#   vls：垂发格子 (x0, x1, z0, z1, 甲板高)；cans：斜置发射箱 (x, y, z, 朝向 偏航°, 仰角°)
SPEC = {
    # 阿利·伯克 Flight III：Mk 45 主炮；前后两组 Mk 41 垂发（格子照甲板贴图量）；机库顶上一座密集阵
    'ddg125': {'guns': [(None, -78.1, 3.8)], 'ciws': [(0, 46, 2.6, None)],
               'vls': [(-6, 6, -73, -64, None), (-5, 6, 59, 72, None)], 'cans': []},
    # 提康德罗加：前后两座 Mk 45；前后两组 Mk 41；后上层建筑右边一座密集阵（左前那座和上层建筑连在一起，拆不出来）
    'cg47': {'guns': [(0, -90.1, 3.9), (0, 120.2, 3.9)], 'ciws': [(7.2, 43.3, 3.2, 27.9)],
             'vls': [(-6, 6, -80, -63, None), (-5, 5, 88, 101, None)], 'cans': []},
    # 055：130 毫米主炮；前 64、后 48 单元垂发；舰桥前面的 1130 近防炮、机库顶上的海红旗-10
    't055': {'guns': [(0, -91.5, 3.6)], 'ciws': [(0, -55, 3.4, None), (0, 73, 3.2, None)],
             'vls': [(-5, 5, -79, -66, None), (-5, 5, 40, 53, None)], 'cans': []},
    # 054A：76 毫米主炮；32 单元垂发（海红旗-16）；机库顶两座 730 近防炮；舯部两组鹰击-83 发射箱（朝两舷斜着）
    't054a': {'guns': [(0, -69.5, 4.0)], 'ciws': [(-8.25, 24.15, 4.0, 15.9), (8.35, 24.15, 4.0, 15.9)],
              'vls': [(-5, 5, -60, -50, None)], 'cans': [(-4, None, 2, -60, 15), (4, None, 2, 60, 15)]},
    # 022：艏部 30 毫米六管炮；艉部两边的导弹发射箱（朝前）
    't022': {'guns': [(0, -20.0, 1.3)], 'ciws': [], 'vls': [], 'cans': [(-5.5, None, 10, 0, 12), (5.5, None, 10, 0, 12)]},
}


def convert(sid, D, dl, log=print):
    meta, binb, P, N, UV, T, TM, credit, mj = load(sid, dl)
    sp = SPEC.get(sid, {})
    lo, hi = P.min(0), P.max(0)
    G = np.array(['Hull'] * len(T), dtype=object)
    Pt = P[T]
    C = Pt.mean(axis=1)
    guns = []
    for gi, g in enumerate(D['guns'], 1):
        spec = sp.get('guns', [])
        if gi > len(spec):
            guns.append(None)
            continue
        cx, cz, rr = spec[gi - 1]
        fwd = -1 if not g['aft'] else 1
        if cx is None:
            near = (np.hypot(C[:, 0], C[:, 2] - cz) < rr) & (C[:, 1] > 2)
            cx = float((Pt[near][:, :, 0].min() + Pt[near][:, :, 0].max()) / 2) if near.any() else 0.0
        tops = []
        for a in np.linspace(0, 2 * np.pi, 12, endpoint=False):
            h = A.ray_ud(Pt, cx + np.cos(a) * (rr + 1.5), cz + np.sin(a) * (rr + 1.5))
            if h:
                tops.append(h[1])
        deck = float(min(tops)) if tops else float(g['pos'][1])
        # 炮塔：中心在 rr 以内、几个角都在 rr×1.7 以内（甲板上从炮座伸出去的长条三角形不算——054A 炮塔连着一大片甲板）；
        #   再顺着共用的顶点往外长（055 的炮塔长，后半截的大斜面中心在 rr 外面，不长出去就钉在甲板上不转）；炮管那一条不往里长
        cen = np.hypot(C[:, 0] - cx, C[:, 2] - cz)
        far = np.hypot(Pt[:, :, 0] - cx, Pt[:, :, 2] - cz).max(axis=1)
        above = C[:, 1] >= deck + 0.15
        ahead = (C[:, 2] - cz) * fwd > rr * 0.6
        lane = (np.abs(C[:, 0] - cx) <= 0.9) & ahead
        house = (cen <= rr) & above & (far <= rr * 1.7)
        cand = above & (far <= rr * 1.7) & ~lane & ~house
        if house.any() and cand.any():
            key = np.round(Pt * 200).astype(np.int64)
            vk = (key[:, :, 0] * 73856093) ^ (key[:, :, 1] * 19349663) ^ (key[:, :, 2] * 83492791)
            for _ in range(6):
                hv = set(vk[house].reshape(-1).tolist())
                ci = np.flatnonzero(cand)
                add = ci[np.array([bool(hv.intersection(r)) for r in vk[ci].tolist()], dtype=bool)] if len(ci) else ci
                if not len(add):
                    break
                house[add] = True
                cand[add] = False
        hh = float(Pt[house][:, :, 1].max() - deck) if house.any() else 3.0
        Lb = g['len'] * 1.1 + rr * 0.6
        zl, zr = (cz - Lb, cz - rr * 0.3) if fwd < 0 else (cz + rr * 0.3, cz + Lb)
        barrel = (np.abs(C[:, 0] - cx) <= 0.9) & (C[:, 2] >= zl) & (C[:, 2] <= zr) & (C[:, 1] >= deck + 0.4) & (C[:, 1] <= deck + hh + 0.5) & ~house
        if barrel.any():   # 炮管是从炮塔前面接着往外的一整条：沿炮管方向排，中间断开（空出半格以上）后面的就不是炮管了（提康德罗加艉炮后面的鱼叉发射架）
            bi = np.flatnonzero(barrel)
            s = (Pt[bi][:, :, 2] - cz) * fwd
            s0, s1 = s.min(axis=1), s.max(axis=1)
            reach, keep = None, []
            for i in np.argsort(s0):
                if reach is None:
                    if s0[i] > rr + 0.8:
                        break
                    reach = s1[i]
                elif s0[i] > reach + 0.5:
                    break
                reach = max(reach, s1[i])
                keep.append(bi[i])
            barrel[:] = False
            barrel[np.array(keep, dtype=np.int64)] = True
        if not house.any():
            guns.append(None)
            continue
        G[house] = 'T%d' % gi
        rec = {'g': 'T%d' % gi, 'piv': [round(float(cx), 3), round(deck, 3), round(float(cz), 3)], 'n': int(house.sum())}
        q = Pt[house | barrel].reshape(-1, 3)
        rec['tip'] = round(float((cz - q[:, 2].min()) if fwd < 0 else (q[:, 2].max() - cz)), 3)
        if barrel.sum() >= 8:   # 炮管单独俯仰：耳轴在炮管最靠炮塔的那一头、炮管的高度
            G[barrel] = 'B%d' % gi
            qb = Pt[barrel].reshape(-1, 3)
            zt = float(qb[:, 2].max() if fwd < 0 else qb[:, 2].min())
            rec['b'] = 'B%d' % gi
            rec['trn'] = [round(float(cx), 3), round(float(np.median(qb[:, 1])), 3), round(zt, 3)]
        guns.append(rec)
    def deck_at(x, z, r):   # 一圈往下打，最低的那个顶面（底座所在的甲板 / 上层建筑顶）
        tops = []
        for a in np.linspace(0, 2 * np.pi, 12, endpoint=False):
            h = A.ray_ud(Pt, x + np.cos(a) * (r + 1.2), z + np.sin(a) * (r + 1.2))
            if h:
                tops.append(h[1])
        return float(min(tops)) if tops else 10.0
    def top_at(x, z):
        h = A.ray_ud(Pt, x, z)
        return float(h[1]) if h else 10.0
    # 近防炮：整块连通块在圆柱里的
    ciws = []
    if sp.get('ciws'):
        cid = A.components(P, T)
        for k, (x, z, r, ymin) in enumerate(sp['ciws'], 1):
            if ymin is None:
                ymin = deck_at(x, z, r) + 0.1
            sel = np.zeros(len(T), dtype=bool)
            inside = (np.hypot(C[:, 0] - x, C[:, 2] - z) <= r) & (C[:, 1] >= ymin)
            for c in np.unique(cid[inside]):
                m = cid == c
                q = Pt[m].reshape(-1, 3)
                if np.hypot(q[:, 0] - x, q[:, 2] - z).max() <= r * 1.05 and q[:, 1].min() >= ymin - 0.05 and q[:, 1].max() <= ymin + 7.5:   # 不要带上桅杆、天线
                    sel |= m
            sel &= (G == 'Hull')
            qq = Pt[sel].reshape(-1, 3) if sel.any() else None
            # 拆出来的得像一座近防炮（够高、够细）才算；不像的（只挑到甲板上的小零件）不拆，游戏里在这个位置拼一座零件做的（ShipView）
            if qq is not None and qq[:, 1].max() - qq[:, 1].min() >= 1.6 and sel.sum() >= 100:
                G[sel] = 'C%d' % k
                y0, y1 = float(qq[:, 1].min()), float(qq[:, 1].max())
                # 转轴：底座那一圈（最低的一成五）的中心
                base = qq[qq[:, 1] <= y0 + 0.15 * (y1 - y0)]
                bx, bz = float((base[:, 0].min() + base[:, 0].max()) / 2), float((base[:, 2].min() + base[:, 2].max()) / 2)
                # 炮口朝哪：离转轴最远的那一撮顶点（炮管伸得最远）的平均方向；ry 0 = 船头（−Z），正数往右；gy 炮管的高、mz 炮口离转轴多远
                dx, dz = qq[:, 0] - bx, qq[:, 2] - bz
                dist = np.hypot(dx, dz)
                farv = dist >= np.quantile(dist, 0.95)
                ux, uz = float(dx[farv].mean()), float(dz[farv].mean())
                ry = float(np.degrees(np.arctan2(ux, -uz))) if np.hypot(ux, uz) > 0.3 * dist.max() else 0.0
                ciws.append({'g': 'C%d' % k, 'piv': [round(bx, 3), round(y0, 3), round(bz, 3)], 'top': round(y1, 3), 'n': int(sel.sum()),
                             'ry': round(ry, 1), 'gy': round(float(np.median(qq[farv, 1])), 3), 'mz': round(float(dist.max()), 3)})
            else:
                ciws.append({'g': False, 'piv': [round(float(x), 3), round(float(ymin - 0.1), 3), round(float(z), 3)], 'ry': 0.0,
                             'gy': round(float(ymin + 1.5), 3), 'mz': 2.4})
    info = {'len': float(hi[2] - lo[2]), 'w': float(hi[0] - lo[0]), 'h': float(hi[1]), 'draft': float(-lo[1]), 'parts': {}, 'guns': guns, 'credit': credit}
    if ciws:
        info['ciws'] = ciws
    if sp.get('vls'):   # 垂发：格子的范围 + 甲板高（格子中心往下打的顶面）
        def vls_deck(x0, x1, z0, z1):   # 格子四周甲板的高（格子是挖空的，从中间往下打会打穿到船底）
            hs = [top_at(x, z) for x, z in ((x0 - 1.2, (z0 + z1) / 2), (x1 + 1.2, (z0 + z1) / 2), ((x0 + x1) / 2, z0 - 1.2), ((x0 + x1) / 2, z1 + 1.2))]
            hs = [h for h in hs if h > 0]
            return float(np.median(hs)) if hs else 10.0
        info['vls'] = [[round(float(v), 3) for v in (x0, x1, z0, z1, (y if y is not None else vls_deck(x0, x1, z0, z1)))] for (x0, x1, z0, z1, y) in sp['vls']]
    if sp.get('cans'):  # 发射箱：箱口位置（甲板往上 1.2 格）、朝向
        info['cans'] = [[round(float(v), 3) for v in (x, (y if y is not None else top_at(x, z) + 1.2), z, yaw, pitch)] for (x, y, z, yaw, pitch) in sp['cans']]
    out, count = [], {}
    groups = ['Hull'] + sorted(set(G.tolist()) - {'Hull'})
    for g in groups:
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
    # 航行灯位置（照 ship2glb）：桅顶、船尾甲板、舰桥两侧
    V = P[np.unique(T[G == 'Hull'].reshape(-1))]
    k = int(np.argmax(V[:, 1]))
    info['top'] = [round(float(V[k, 0]), 3), round(float(V[k, 1]), 3), round(float(V[k, 2]), 3)]
    rear = V[(V[:, 2] > hi[2] - 8) & (np.abs(V[:, 0]) < 8)]
    if len(rear):
        info['stern'] = [0, round(float(rear[:, 1].max()), 3), round(float(rear[:, 2].max()), 3)]
    deck = float(D['deck'])
    tz = info['top'][2]
    band = V[(V[:, 1] > deck + 3) & (V[:, 1] < deck + 20) & (V[:, 2] > tz - 30) & (V[:, 2] < tz + 4)]
    if len(band):
        k2 = int(np.argmax(np.abs(band[:, 0])))
        info['side'] = [round(float(abs(band[k2, 0])), 3), round(float(band[k2, 1]), 3), round(float(band[k2, 2]), 3)]
    return meta, binb, info, out, mj


def write_meta(infos):
    """ImportedShip.lua：只换转了的那几艘那一行"""
    lines = open(META, encoding='utf-8').read().split('\n')
    for sid, info in infos.items():
        info = dict(info)
        info['guns'] = [g if g else False for g in info['guns']]
        if info.get('ciws'):
            info['ciws'] = [c for c in info['ciws']]
        row = '    %s = %s,' % (sid, B.lua(info))
        li = next((i for i, ln in enumerate(lines) if ln.startswith('    %s = { ' % sid)), None)
        if li is None:
            li = next(i for i, ln in enumerate(lines) if ln.startswith('  },'))
            lines.insert(li, row)
        else:
            lines[li] = row
    open(META, 'w', encoding='utf-8').write('\n'.join(lines))


def write_credits(infos, mjs):
    path = os.path.join(OUTDIR, 'credits.txt')
    lines = open(path, encoding='utf-8').read().split('\n') if os.path.exists(path) else []
    head = ('Roblox全面大战场的舰艇模型（models/ship/<型号>.glb）：055、阿利·伯克、提康德罗加、054A、022 由 Sketchfab 原模型直接转换（tools/models/sfship.py），'
            '另外两艘从网页版《暗剑》的舰艇模型原样转换')
    if lines and lines[0].startswith('Roblox全面大战场的舰艇模型'):
        lines[0] = head
    for sid in infos:
        mj = mjs[sid]
        lic = mj.get('license') or 'CC Attribution'
        lic_en = 'CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)' if lic == 'CC Attribution' else lic
        row = '- %s（%s.glb）：This work is based on "%s" (%s) by %s licensed under %s（Sketchfab 原模型直接转换：不减面、原材质，贴图超过 1024 缩到 1024）' % (
            SF[sid]['name'], sid, mj.get('name', '?'), mj.get('url', ''), mj.get('displayName') or mj.get('user', '?'), lic_en)
        li = next((i for i, ln in enumerate(lines) if ('（%s.glb）' % sid) in ln), None)
        if li is None:
            lines.append(row)
        else:
            lines[li] = row
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))


if __name__ == '__main__' and '--dump' not in sys.argv:
    dl, sdj = sys.argv[1], sys.argv[2]
    SD = json.load(open(sdj, encoding='utf-8'))
    sids = sys.argv[3:] or sorted(SF)
    infos, mjs = {}, {}
    for sid in sids:
        meta, binb, info, out, mj = convert(sid, SD[sid], dl)
        path = os.path.join(OUTDIR, sid + '.glb')
        B.write_glb(sid, meta, binb, info, out, path, prefix='S_')
        infos[sid], mjs[sid] = info, mj
        tris = sum(len(o[6]) for o in out)
        print('%-6s %7d 个三角形  %3d 块  长 %5.1f 宽 %4.1f 高 %4.1f 吃水 %4.1f  %5.1f MB  炮 %s  近防 %s' % (
            sid, tris, len(out), info['len'], info['w'], info['h'], info['draft'], os.path.getsize(path) / 1e6,
            ' '.join('%s:%s%s' % (g['g'], g['n'], '+' + g['b'] if g.get('b') else '') if g else '没找到' for g in info['guns']),
            ' '.join(c['g'] or '没找到' for c in info.get('ciws', [])) or '-'))
    write_meta(infos)
    write_credits(infos, mjs)
    print('写好了 %s 和 %s/credits.txt' % (META, OUTDIR))
