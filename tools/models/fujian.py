#!/usr/bin/env python3
# Roblox全面大战场——攻方航母换成福建舰（003 型）的原模型（用户 11-21：航母不够真；原来是一个 620 × 116 的长方块加一块方舰岛）
#   来源：Sketchfab「Chinese Aircraft Carrier」，作者 businessyuen，CC-BY-4.0（https://sketchfab.com/3d-models/chinese-aircraft-carrier-f9ddadfc6988414fa15da2cb1b1de545）
#   这里的改动：
#     · 摆成游戏里的船体坐标（X 右舷、Y 上、−Z 船头，原点在水线、甲板长宽的中间），按甲板全长 620 格等比放大，甲板面在水线上 30.5 格（AirDefs.DECKS.carrier.top）
#     · 去掉甲板上停着的飞机、直升机、预警机、牵引车（游戏里玩家自己的飞机停在停机位上，甲板上不再摆一堆假飞机挡路）
#     · 原模型是 3D 打印用的调色板配色（粉色船体、红色船底），按真舰重新分块上色：船体 / 舰岛海军灰、水线一圈黑、水线下防污红、
#       甲板深灰防滑面、白 / 黄 / 红标线、舰岛上深色的相控阵雷达和窗——每种颜色一块网格，不带贴图（游戏里按元数据设颜色和 Roblox 材质：
#       甲板 Concrete 有防滑面的颗粒、船体 Metal），UV 重新按方块投影铺（材质纹理按 16 格一块平铺，不拉伸）
#   导出：models/ship/fujian.glb，每块 MeshPart 叫 S_fujian__<部件>_<号>（Imports.lua 收进 Imported.Ship.fujian）；
#     元数据 src/ReplicatedStorage/CarrierMeta.lua：每块的中心 / 大小 / 颜色 / 材质，甲板轮廓（每 10 格一行的左右边）、舰岛碰撞盒、
#     量出来的弹射轨道、斜角甲板中线和边线、升降机——World.lua（摆模型、碰撞、甲板细节和灯）、AirDefs.lua（弹射器、拦阻索、哪里算甲板）照这些摆
#   用法：python3 -I tools/models/fujian.py <下载的 scene.glb> [--preview <目录>]
import json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402

ROOT = os.getcwd()
OUT = os.path.join(ROOT, 'models', 'ship', 'fujian.glb')
META = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'CarrierMeta.lua')
L_GAME = 620.0      # 甲板全长（格）
DECK_TOP = 30.5     # 甲板面离水线（格）
DECK_SRC = 3.1660   # 原模型里甲板面的高度（量的）
UV_TILE = 16.0      # 材质纹理多少格一块
CREDIT = ('福建舰（fujian.glb）：This work is based on "Chinese Aircraft Carrier" (https://sketchfab.com/3d-models/chinese-aircraft-carrier-f9ddadfc6988414fa15da2cb1b1de545) '
          'by businessyuen licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)（改动：去掉甲板上的飞机和车、按真舰重新分块上色、按游戏比例放大）')

# 部件：颜色（sRGB）、Roblox 材质
PARTS = {
    'Hull': ((140, 146, 150), 'Metal'),       # 船体（舷侧、舷侧走廊）
    'HullD': ((112, 118, 122), 'Metal'),      # 船体暗一点的部分（舷侧平台、凹进去的地方）
    'Boot': ((34, 35, 37), 'SmoothPlastic'),  # 水线带
    'Bottom': ((112, 42, 38), 'SmoothPlastic'),   # 水线下的防污漆
    'Deck': ((62, 64, 66), 'Concrete'),       # 飞行甲板（防滑面）
    'LineW': ((222, 222, 214), 'SmoothPlastic'),  # 白标线
    'LineY': ((212, 182, 66), 'SmoothPlastic'),   # 黄标线
    'LineR': ((178, 44, 40), 'SmoothPlastic'),    # 红标线（着舰区边线）
    'Island': ((168, 174, 178), 'Metal'),     # 舰岛
    'Island2': ((148, 154, 158), 'Metal'),    # 舰岛上暗一点的层
    'Dark': ((40, 44, 48), 'SmoothPlastic'),  # 相控阵雷达面、舰桥窗
    'Metal': ((126, 130, 132), 'Metal'),      # 杂项设备（近防炮、天线座、救生筏架……）
    'Hangar': ((66, 68, 70), 'SmoothPlastic'),    # 机库里面
    'Prop': ((136, 108, 52), 'Metal'),        # 螺旋桨、舵（水下）
}
# 原调色板颜色 → 部件（甲板上的深灰另按高度分：甲板面 / 舰岛上的雷达窗）
SRC = {
    (78, 78, 78): 'Deck', (255, 255, 255): 'LineW', (255, 245, 157): 'LineY', (194, 24, 91): 'LineR',
    (232, 237, 239): 'Island', (208, 221, 228): 'Island', (179, 196, 201): 'Island', (157, 179, 186): 'Island2', (134, 161, 170): 'Island2',
    (153, 176, 191): 'HullD', (188, 170, 164): 'Hull', (122, 149, 167): 'HullD',
    (177, 177, 177): 'Metal', (160, 160, 160): 'Metal', (109, 109, 109): 'Metal', (202, 202, 202): 'Metal',
    (255, 171, 145): 'Hull', (211, 47, 47): 'Hull', (208, 176, 6): 'Prop',
}


def tri_colors(J, BIN, uv, I):
    from PIL import Image
    import io
    tex = J['textures'][J['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']]
    im = J['images'][tex['source']]
    bv = J['bufferViews'][im['bufferView']]
    o = bv.get('byteOffset', 0)
    a = np.asarray(Image.open(io.BytesIO(bytes(BIN[o:o + bv['byteLength']]))).convert('RGB'))
    H, W = a.shape[:2]
    c = uv[I].mean(1)
    px = np.clip((c[:, 0] % 1) * W, 0, W - 1).astype(int)
    py = np.clip((c[:, 1] % 1) * H, 0, H - 1).astype(int)
    return a[py, px].astype(int)


def components(P, I):
    key = np.round(P / 1e-4).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    T = inv[I]
    par = np.arange(inv.max() + 1)

    def find(x):
        r = x
        while par[r] != r:
            r = par[r]
        while par[x] != r:
            par[x], x = r, par[x]
        return r
    for a, b, c in T:
        ra = find(a)
        for o in (b, c):
            ro = find(o)
            if ro != ra:
                par[ro] = ra
    root = np.array([find(x) for x in range(len(par))])
    _, lab = np.unique(root[T[:, 0]], return_inverse=True)
    return lab.reshape(-1)


def load(src):
    J, BIN = glbfix.read(src)
    W = glbfix.world_mats(J)
    meshes = []
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd:
            continue
        M = W[ni]
        for pr in J['meshes'][nd['mesh']]['primitives']:
            P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(float)
            P = (M[:3, :3] @ P.T).T + M[:3, 3]
            uv = glbfix.acc_read(J, BIN, pr['attributes']['TEXCOORD_0']).astype(float)
            I = glbfix.acc_read(J, BIN, pr['indices']).reshape(-1, 3).astype(np.int64)
            meshes.append({'name': J['nodes'][ni].get('name', ''), 'P': P, 'uv': uv, 'I': I, 'col': tri_colors(J, BIN, uv, I)})
    # 原模型船头朝 +Z、右舷在 −X：绕 Y 转半圈（x → −x、z → −z），等比放大到甲板全长 620，甲板面抬到 30.5，长度方向居中
    z0 = min(m['P'][:, 2].min() for m in meshes)
    z1 = max(m['P'][:, 2].max() for m in meshes)
    s = L_GAME / (z1 - z0)
    ty = DECK_TOP - DECK_SRC * s
    tz = (z0 + z1) / 2 * s   # 转半圈以后 z' = −z·s + tz，居中
    for m in meshes:
        P = m['P']
        Q = np.empty_like(P)
        Q[:, 0] = -P[:, 0] * s
        Q[:, 1] = P[:, 1] * s + ty
        Q[:, 2] = -P[:, 2] * s + tz
        m['P'] = Q
        m['lab'] = components(Q, m['I'])
    return meshes, s


def deck_outline(meshes):
    """甲板轮廓：甲板面高度上朝上的三角形（含升降机）按 2 格一行栅格化，每 10 格一行取左右边"""
    from PIL import Image, ImageDraw
    X0, Z0, K = -110, -330, 2
    img = Image.new('L', (220 * K, 660 * K), 0)
    d = ImageDraw.Draw(img)
    for m in meshes:
        v = m['P'][m['I']]
        n = np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
        ok = (n[:, 1] > 0.9) & (np.abs(v[:, :, 1].mean(1) - DECK_TOP) < 1.2) & m.get('keep', np.ones(len(v), bool))
        for t in v[ok]:
            d.polygon([((p[0] - X0) * K, (p[2] - Z0) * K) for p in t], fill=255)
    G = np.asarray(img) > 0
    rows = []
    for z in range(-310, 311, 10):
        zz = min(max(z, -309), 309)
        r = G[int((zz - Z0) * K)]
        xs = np.where(r)[0]
        if len(xs):
            rows.append((z, round(xs.min() / K + X0, 1), round((xs.max() + 1) / K + X0, 1)))
    return rows, G


def classify(meshes, outline):
    """每块网格的三角形归到哪个部件；甲板上停着的飞机、车（甲板面以上、不高、不大、在甲板轮廓里、不是舰岛）去掉"""
    zs = np.array([r[0] for r in outline], float)
    xa = np.array([r[1] for r in outline], float)
    xb = np.array([r[2] for r in outline], float)
    dropped = 0
    for m in meshes:
        P, I, col, lab = m['P'], m['I'], m['col'], m['lab']
        part = np.array(['Hull'] * len(I), dtype=object)
        keep = np.ones(len(I), bool)
        cen = P[I].mean(1)
        if m['name'].startswith('Object_8'):   # 中间那一层：机库里面
            part[:] = 'Hangar'
        else:
            for i, c in enumerate(col):
                part[i] = SRC.get(tuple(int(x) for x in c), 'Metal')
            low = m['name'].startswith('Object_6')   # 下半截船体：按高度分水线下 / 水线带
            if low:
                y = cen[:, 1]
                part[y < -0.8] = 'Bottom'
                part[(y >= -0.8) & (y < 2.4)] = 'Boot'
            dk = part == 'Deck'
            part[dk & (cen[:, 1] > DECK_TOP + 2.5)] = 'Dark'   # 舰岛、设备上的深灰：雷达面、窗
            part[dk & (cen[:, 1] < DECK_TOP - 3)] = 'HullD'    # 甲板下沿、舷侧平台的深灰
            # 甲板上停着的飞机、直升机、预警机、牵引车（升降机上的在下半截那块网格里）：甲板面以上（底不低于甲板 1.5 格）、
            #   不高、不大、在甲板轮廓里（停在甲板边上的机翼伸出去，放宽 14 格）、不是舰岛；甲板面本身（大块）、贴着甲板的标线不算。
            #   偏流板、弹射槽、甲板边的黄标线底都在甲板面以下，不会被当成飞机
            for k in range(lab.max() + 1):
                t = np.where(lab == k)[0]
                v = P[I[t]].reshape(-1, 3)
                mn, mx = v.min(0), v.max(0)
                c = (mn + mx) / 2
                island = 30 < c[0] < 86 and 56 < c[2] < 136
                hw = max(mx[0] - mn[0], mx[2] - mn[2])
                xl, xr = np.interp(c[2], zs, xa), np.interp(c[2], zs, xb)
                inside = xl - 14 < c[0] < xr + 14
                if (not island) and inside and mn[1] > DECK_TOP - 1.5 and mx[1] < DECK_TOP + 22 and hw < 64:
                    if len(t) >= 300 or mx[1] < DECK_TOP + 0.35:
                        continue
                    keep[t] = False
                    dropped += len(t)
        m['part'], m['keep'] = part, keep
    return dropped


def box_uv(v, n):
    """方块投影：按法线最大的轴投影，UV = 坐标 / 16 格"""
    a = np.abs(n).argmax(1)
    uv = np.zeros((len(v), 3, 2))
    for i, ax in enumerate(a):
        if ax == 1:
            uv[i] = v[i][:, [0, 2]]
        elif ax == 0:
            uv[i] = v[i][:, [2, 1]]
        else:
            uv[i] = v[i][:, [0, 1]]
    return uv / UV_TILE


def build(meshes):
    """按部件合网格：去掉的三角形不要；顶点按 位置 + 法线 + UV 去重；每块 ≤ 18000 个三角形"""
    groups = {}
    for m in meshes:
        v = m['P'][m['I']]
        n = np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
        ln = np.linalg.norm(n, axis=1, keepdims=True)
        good = (ln[:, 0] > 1e-9) & m['keep']
        n = n / (ln + 1e-12)
        uv = box_uv(v, n)
        for nm in PARTS:
            sel = good & (m['part'] == nm)
            if sel.any():
                g = groups.setdefault(nm, {'v': [], 'n': [], 'uv': []})
                g['v'].append(v[sel]); g['n'].append(np.repeat(n[sel][:, None, :], 3, 1)); g['uv'].append(uv[sel])
    out = []
    for nm, g in groups.items():
        V = np.concatenate(g['v']).reshape(-1, 3)
        N = np.concatenate(g['n']).reshape(-1, 3)
        U = np.concatenate(g['uv']).reshape(-1, 2)
        key = np.round(np.concatenate([V * 100, N * 1000, U * 1000], 1)).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        Vd, Nd, Ud = V[first], N[first], U[first]
        Id = inv.reshape(-1, 3)
        for ci in range(0, len(Id), 18000):
            I = Id[ci:ci + 18000]
            used, remap = np.unique(I, return_inverse=True)
            out.append((nm, (ci // 18000) + 1, Vd[used], Nd[used], Ud[used], remap.reshape(-1, 3)))
    return out


def write_glb(parts, path):
    bufs, views, accs, nodes, meshes_j, mats = [], [], [], [], [], []
    off = [0]

    def add(b, target):
        pad = (4 - off[0] % 4) % 4
        if pad:
            bufs.append(b'\0' * pad); off[0] += pad
        views.append({'buffer': 0, 'byteOffset': off[0], 'byteLength': len(b), 'target': target})
        bufs.append(b); off[0] += len(b)
        return len(views) - 1

    def acc(arr, ct, typ, target, mm=False):
        a = {'bufferView': add(arr.tobytes(), target), 'componentType': ct, 'count': int(arr.shape[0]), 'type': typ}
        if mm:
            a['min'], a['max'] = arr.min(0).tolist(), arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1
    matid = {}
    for nm, k, V, N, U, I in parts:
        if nm not in matid:
            c = PARTS[nm][0]
            lin = [((x / 255) ** 2.2) for x in c]
            mats.append({'name': 'fujian_' + nm, 'pbrMetallicRoughness': {'baseColorFactor': lin + [1], 'metallicFactor': 0.0, 'roughnessFactor': 0.8}})
            matid[nm] = len(mats) - 1
        name = 'S_fujian__%s_%d' % (nm, k)
        prim = {'attributes': {'POSITION': acc(V.astype(np.float32), 5126, 'VEC3', 34962, True), 'NORMAL': acc(N.astype(np.float32), 5126, 'VEC3', 34962),
                               'TEXCOORD_0': acc(U.astype(np.float32), 5126, 'VEC2', 34962)},
                'indices': acc(I.astype(np.uint32).reshape(-1), 5125, 'SCALAR', 34963), 'material': matid[nm]}
        meshes_j.append({'name': name, 'primitives': [prim]})
        nodes.append({'name': name, 'mesh': len(meshes_j) - 1})
    G = {'asset': {'version': '2.0', 'generator': 'fujian.py'}, 'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}],
         'nodes': nodes, 'meshes': meshes_j, 'materials': mats, 'bufferViews': views, 'accessors': accs, 'buffers': [{'byteLength': off[0]}]}
    BIN = bytearray(b''.join(bufs))
    glbfix.write(path, G, BIN)


def lines(meshes):
    """量甲板上的线：两条舰艏弹射轨道（白）、斜角甲板的红边线、黄色中线；返回游戏坐标"""
    res = {}
    for m in meshes:
        if not m['name'].startswith('Object_4'):
            continue
        P, I, lab, col = m['P'], m['I'], m['lab'], m['col']
        for rgb, key in (((255, 255, 255), 'w'), ((194, 24, 91), 'r'), ((255, 245, 157), 'y')):
            t = np.where((col == rgb).all(1))[0]
            for k in np.unique(lab[t]):
                tt = t[lab[t] == k]
                v = P[I[tt]].reshape(-1, 3)
                c = v.mean(0)
                xz = v[:, [0, 2]] - c[[0, 2]]
                _, _, vt = np.linalg.svd(xz, full_matrices=False)
                d = vt[0]
                pr = xz @ d
                a, b = c[[0, 2]] + d * pr.min(), c[[0, 2]] + d * pr.max()
                res.setdefault(key, []).append((len(tt), (round(a[0], 2), round(a[1], 2)), (round(b[0], 2), round(b[1], 2)), round(pr.max() - pr.min(), 1)))
    return res


def hull_section(meshes, y0=16.0):
    """船舷：水线上 y0 格那一圈船体的左右边（每 20 格一行），舷号、救生筏贴在这上面"""
    rows = []
    segs = []
    for m in meshes:
        hull = np.isin(m['part'], ['Hull', 'HullD', 'Boot', 'Bottom']) & m['keep']
        v = m['P'][m['I'][hull]]
        ys = v[:, :, 1]
        cross = (ys.min(1) < y0) & (ys.max(1) > y0)
        for t in v[cross]:
            pts = []
            for a, b in ((0, 1), (1, 2), (2, 0)):
                ya, yb = t[a][1], t[b][1]
                if (ya - y0) * (yb - y0) < 0:
                    k = (y0 - ya) / (yb - ya)
                    pts.append(t[a] + (t[b] - t[a]) * k)
            if len(pts) == 2:
                segs.append((pts[0], pts[1]))
    if not segs:
        return rows
    S = np.array([[p[0], p[2], q[0], q[2]] for p, q in segs])
    for z in range(-300, 301, 20):
        sel = ((S[:, 1] - z) * (S[:, 3] - z) <= 0) & (np.abs(S[:, 1] - S[:, 3]) > 1e-6)
        xs = []
        for x1, z1, x2, z2 in S[sel]:
            xs.append(x1 + (x2 - x1) * (z - z1) / (z2 - z1))
        if xs:
            rows.append((z, round(float(min(xs)), 1), round(float(max(xs)), 1)))
    return rows


def lua(v, ind=''):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k if k.isidentifier() else '["%s"]' % k, lua(x)) for k, x in v.items()) + ' }'
    if isinstance(v, (list, tuple)):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, str):
        return '"%s"' % v.replace('\\', '\\\\').replace('"', '\\"')
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float):
        return ('%.2f' % v).rstrip('0').rstrip('.')
    return str(v)


def main(src, preview=None):
    meshes, s = load(src)
    outline, _ = deck_outline(meshes)
    dropped = classify(meshes, outline)
    outline, G = deck_outline(meshes)   # 去掉飞机以后再量一遍（飞机不在甲板面高度上，结果一样，稳妥）
    parts = build(meshes)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_glb(parts, OUT)
    L = lines(meshes)
    # 舰岛碰撞盒：舰岛范围里甲板面以上的顶点，分高低两段
    isl = []
    for m in meshes:
        v = m['P'][m['I']].reshape(-1, 3)
        sel = (v[:, 0] > 34) & (v[:, 2] > 50) & (v[:, 2] < 134) & (v[:, 1] > DECK_TOP)
        isl.append(v[sel])
    iv = np.concatenate(isl)
    lowv = iv[iv[:, 1] < DECK_TOP + 40]
    island = {'base': [round(float(lowv[:, 0].min()), 1), round(float(lowv[:, 0].max()), 1), round(float(lowv[:, 2].min()), 1), round(float(lowv[:, 2].max()), 1), round(DECK_TOP + 40, 1)],
              'top': round(float(iv[:, 1].max()), 1)}
    meta_parts = {}
    tri_total = 0
    for nm, k, V, N, U, I in parts:
        mn, mx = V.min(0), V.max(0)
        meta_parts['%s_%d' % (nm, k)] = {'c': [round(float(x), 3) for x in (mn + mx) / 2], 's': [round(float(x), 3) for x in (mx - mn)],
                                         'col': list(PARTS[nm][0]), 'mat': PARTS[nm][1]}
        tri_total += len(I)
    bow = sorted([x for x in L.get('w', []) if x[3] > 150 and x[3] < 260], key=lambda x: x[1][0])
    red = sorted([x for x in L.get('r', [])], key=lambda x: -x[3])
    yel = [x for x in L.get('y', []) if 15 < x[3] < 20]
    meta = {'scale': round(s, 4), 'tris': tri_total, 'parts': meta_parts, 'outline': [list(r) for r in outline], 'island': island,
            'side': [list(r) for r in hull_section(meshes, 16.0)],
            'bowCats': [[list(b[1]), list(b[2])] for b in bow], 'foul': [[list(r[1]), list(r[2])] for r in red[:2]],
            'center': ([list(min((y[1] for y in yel), key=lambda p: p[1])), list(max((y[2] for y in yel), key=lambda p: p[1]))] if yel else None),
            'credit': CREDIT}
    with open(META, 'w', encoding='utf-8') as f:
        f.write('-- 自动生成（tools/models/fujian.py），别手改：攻方航母（福建舰）原模型 models/ship/fujian.glb 的元数据\n')
        f.write('--   坐标：X 右舷、Y 上、−Z 船头，原点在水线、甲板长宽中间（格）；甲板面 Y = 30.5（AirDefs.DECKS.carrier.top）\n')
        f.write('--   parts[块名] = { c 中心, s 大小, col 颜色, mat Roblox 材质 }（导入后 MeshPart 叫 S_fujian__<块名>）；\n')
        f.write('--   outline = { { z, 左舷边 x, 右舷边 x }, … }（每 10 格一行）；island = { base = { x0, x1, z0, z1, 顶 }, top 最高 }；\n')
        f.write('--   side = { { z, 左舷 x, 右舷 x }, … }（水线上 16 格那一圈船舷，每 20 格一行）；\n')
        f.write('--   bowCats 舰艏两条弹射轨道（前端、后端）、foul 斜角甲板两条红边线（后端、前端）、center 着舰区黄中线（前端、后端）\n')
        f.write('return ' + lua(meta) + '\n')
    print('写好了', OUT, os.path.getsize(OUT) // 1024, 'KB，块', len(parts), '三角形', tri_total, '去掉', dropped)
    print('舰岛', island)
    print('舰艏弹射轨道', meta['bowCats'])
    print('红边线', meta['foul'])
    print('黄中线', meta['center'])
    if preview:
        from PIL import Image, ImageDraw
        os.makedirs(preview, exist_ok=True)
        X0, X1, Z0, Z1, K = -100, 100, -330, 330, 2
        img = Image.new('RGB', ((X1 - X0) * K, (Z1 - Z0) * K), (24, 40, 56))
        d = ImageDraw.Draw(img)
        T, C = [], []
        for nm, k, V, N, U, I in parts:
            T.append(V[I]); C += [PARTS[nm][0]] * len(I)
        T = np.concatenate(T)
        for i in np.argsort(T[:, :, 1].mean(1)):
            d.polygon([((p[0] - X0) * K, (p[2] - Z0) * K) for p in T[i]], fill=C[i])
        for z in range(-300, 301, 50):
            d.text((4, (z - Z0) * K - 6), str(z), fill=(255, 90, 90))
        img.save(os.path.join(preview, 'fujian_top.png'))
        print('预览', os.path.join(preview, 'fujian_top.png'))


if __name__ == '__main__':
    a = sys.argv[1:]
    pv = None
    if '--preview' in a:
        i = a.index('--preview'); pv = a[i + 1]; del a[i:i + 2]
    main(a[0], pv)
