# 坦克车顶的机枪要能转（用户 11-19：坦克的机枪要能转，且开火位置要在机枪）——成品 GLB（models/veh/<键>.glb）+ 元数据 ImportedMeta.lua 那一行的后加工
#   原模型里车长 / 装填手位的机枪是烘焙在炮塔里的一块，转炮塔时跟着转，自己不会转；游戏里机枪那一栏从并列机枪口（主炮旁边）打出去。
#   这里把它拆出来，按 M1A2 的 CROWS 那一套（mdl2glb.py 的 SPLIT）：
#   · split：炮塔里整个连通块落在框里的三角形挪到别的部件——机枪（连机匣、弹箱）挪到 RwsGun（自己俯仰），座圈、枪架、舱盖挪到 Rws（跟着炮塔转、自己再转）；
#     规则按顺序做（先挑机枪，再挑座圈），框是模型坐标（格）：x、y、z 各一个范围，整块都在框里才挪
#   · cut：扫描出来的模型（ZTQ-15）车顶的武器站和炮塔顶连成一整片：框里的三角形整个去掉，切口在 cap 的高度盖一块深色的椭圆板，
#     游戏里在原处拼一个零件做的遥控武器站（mk）
#   · rws：元数据写上底座转轴 p、机枪俯仰轴 g、枪口离俯仰轴多远 muz（格）；mk 是原模型上没有（或者去掉了）机枪，游戏里拼一挺（客户端 VehModels）
#   型号表（VehDefs）看到元数据里有 rws：机枪那一栏换成这挺 12.7 毫米机枪，Drive 让它朝准星转，服务器从它的枪口打出去
# 只对原样转出来、还没拆过的 GLB 跑一次（元数据里已经有 rws 的就跳过）。用户在 Studio 里把这几个 GLB 重新导入一遍才看得到
# 用法：python3 -I tools/models/vehrws.py [模型键 …]（默认 SPEC 里全部）
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import mdl2glb as B   # noqa: E402  元数据写回（lua）
import airpaint   # noqa: E402  元数据那一行读回 Python（lua_parse）

META = 'src/ReplicatedStorage/ImportedMeta.lua'
TRI_MAX = 19500

SPEC = {
    # M1A1：车长指挥塔（座圈、观察镜、竖着的舱盖）+ 前沿枪架上的 M2
    'm1a1': {'split': [{'from': 'Turret', 'to': 'RwsGun', 'x': [1.15, 1.95], 'y': [8.10, 9.00], 'z': [-4.75, 0.35]},
                       {'from': 'Turret', 'to': 'Rws', 'x': [0.35, 3.15], 'y': [7.25, 9.60], 'z': [-2.95, 2.65]}],
             'rws': {'p': [1.60, 7.35, 0.88], 'g': [1.52, 8.35, -2.00], 'muz': 2.55}},
    # 96 式：装填手舱口座圈上的 W85 12.7 毫米机枪（连弹箱）
    'ztz96': {'split': [{'from': 'Turret', 'to': 'RwsGun', 'x': [1.25, 2.15], 'y': [7.15, 8.35], 'z': [-5.60, -1.00]},
                        {'from': 'Turret', 'to': 'Rws', 'x': [0.55, 2.95], 'y': [6.45, 8.50], 'z': [-3.00, 1.05]}],
              'rws': {'p': [1.75, 6.55, -0.38], 'g': [1.70, 7.45, -1.90], 'muz': 3.55}},
    # 99A2：原模型车顶没有机枪——装填手舱口座圈上拼一个遥控武器站
    'ztz99a2': {'rws': {'p': [1.75, 6.78, -0.30], 'g': [1.75, 7.38, -0.75], 'muz': 2.45, 'mk': 'rws'}},
    # 15 式：扫描模型，车顶左边的遥控武器站和炮塔顶连成一片——去掉，原处拼一个
}


def comps(T):
    """三角形（m×3×3，模型坐标）的连通块编号（按位置焊接 2 毫米）"""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    P = T.reshape(-1, 3)
    q = np.round(P / 0.002).astype(np.int64)
    _, w = np.unique(q, axis=0, return_inverse=True)
    w = w.reshape(-1, 3)
    n = int(w.max()) + 1
    g = coo_matrix((np.ones(len(w) * 2, dtype=np.int8), (np.r_[w[:, 0], w[:, 1]], np.r_[w[:, 1], w[:, 2]])), shape=(n, n))
    _, lab = connected_components(g, directed=False)
    return lab[w[:, 0]]


def inside(T, r):
    """每个三角形三个顶点都在框里"""
    ok = np.ones(len(T), dtype=bool)
    for ax, k in ((0, 'x'), (1, 'y'), (2, 'z')):
        lo, hi = r[k]
        ok &= (T[:, :, ax].min(1) >= lo) & (T[:, :, ax].max(1) <= hi)
    return ok


def load(J, BIN, key):
    """每个部件块：{ name, group, ni, mat, P 模型坐标, N, UV, T }"""
    out = []
    pre = 'V_%s__' % key
    for ni, nd in enumerate(J['nodes']):
        nm = nd.get('name', '')
        if 'mesh' not in nd or not nm.startswith(pre):
            continue
        prim = J['meshes'][nd['mesh']]['primitives'][0]
        a = prim['attributes']
        P = glbfix.acc_read(J, BIN, a['POSITION']).astype(np.float64) + np.array(nd.get('translation', [0, 0, 0]))
        out.append({'name': nm[len(pre):], 'group': nm[len(pre):].rsplit('_', 1)[0], 'ni': ni, 'mat': prim.get('material'), 'P': P,
                    'N': glbfix.acc_read(J, BIN, a['NORMAL']).astype(np.float32),
                    'UV': glbfix.acc_read(J, BIN, a['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in a else None,
                    'T': glbfix.acc_read(J, BIN, prim['indices']).astype(np.int64).reshape(-1, 3)})
    return out


def sub(ch, mask):
    """这一块里 mask 选中的三角形，顶点重新编号（只留用到的）"""
    T = ch['T'][mask]
    u, inv = np.unique(T.reshape(-1), return_inverse=True)
    return {'P': ch['P'][u], 'N': ch['N'][u], 'UV': ch['UV'][u] if ch['UV'] is not None else None, 'T': inv.reshape(-1, 3), 'mat': ch['mat']}


def merge(parts):
    P, N, UV, T, off = [], [], [], [], 0
    for p in parts:
        P.append(p['P']); N.append(p['N']); T.append(p['T'] + off)
        UV.append(p['UV'] if p['UV'] is not None else np.zeros((len(p['P']), 2), np.float32))
        off += len(p['P'])
    return {'P': np.concatenate(P), 'N': np.concatenate(N), 'UV': np.concatenate(UV), 'T': np.concatenate(T), 'mat': parts[0]['mat']}


def put(J, out, arr, typ, comp, target=None, minmax=False):
    while len(out) % 4:
        out.append(0)
    data = np.ascontiguousarray(arr).tobytes()
    v = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}
    if target:
        v['target'] = target
    J['bufferViews'].append(v)
    out.extend(data)
    a = {'bufferView': len(J['bufferViews']) - 1, 'componentType': comp, 'count': int(arr.shape[0]), 'type': typ}
    if minmax:
        a['min'] = [float(x) for x in arr.min(0)]
        a['max'] = [float(x) for x in arr.max(0)]
    J['accessors'].append(a)
    return len(J['accessors']) - 1


def write_chunk(J, out, g, name, node=None):
    """一块网格写成（或改写成）一个节点：平移 = 包围盒中心，顶点相对中心；返回 (节点号, 中心, 大小)"""
    lo, hi = g['P'].min(0), g['P'].max(0)
    c = (lo + hi) / 2
    Pl = (g['P'] - c).astype(np.float32)
    idt, ict = (np.uint32, 5125) if len(Pl) > 65535 else (np.uint16, 5123)
    prim = {'attributes': {'POSITION': put(J, out, Pl, 'VEC3', 5126, 34962, True), 'NORMAL': put(J, out, g['N'].astype(np.float32), 'VEC3', 5126, 34962),
                           'TEXCOORD_0': put(J, out, g['UV'].astype(np.float32), 'VEC2', 5126, 34962)},
            'indices': put(J, out, g['T'].reshape(-1).astype(idt), 'SCALAR', ict, 34963), 'mode': 4}
    if g['mat'] is not None:
        prim['material'] = g['mat']
    J['meshes'].append({'name': name, 'primitives': [prim]})
    nd = {'name': name, 'mesh': len(J['meshes']) - 1, 'translation': [float(x) for x in c]}
    if node is None:
        J['nodes'].append(nd)
        J['nodes'][0].setdefault('children', []).append(len(J['nodes']) - 1)
        node = len(J['nodes']) - 1
    else:
        J['nodes'][node] = nd
    return node, c, hi - lo


def compact(J, BIN):
    """去掉没人用的网格、访问器、缓冲视图，重新排二进制"""
    used_mesh = sorted({nd['mesh'] for nd in J['nodes'] if 'mesh' in nd})
    mm = {o: i for i, o in enumerate(used_mesh)}
    J['meshes'] = [J['meshes'][i] for i in used_mesh]
    for nd in J['nodes']:
        if 'mesh' in nd:
            nd['mesh'] = mm[nd['mesh']]
    used_acc = set()
    for m in J['meshes']:
        for p in m['primitives']:
            used_acc |= set(p['attributes'].values())
            if 'indices' in p:
                used_acc.add(p['indices'])
    ua = sorted(used_acc)
    am = {o: i for i, o in enumerate(ua)}
    J['accessors'] = [J['accessors'][i] for i in ua]
    for m in J['meshes']:
        for p in m['primitives']:
            p['attributes'] = {k: am[v] for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = am[p['indices']]
    return glbfix.rebuild(J, BIN, {})


def cap_material(J, BIN, col):
    """切口盖板：深色、不反光；Roblox 只认贴图，配一张 8×8 的纯色贴图（glbfix 的做法）"""
    lin = [((c / 255) / 12.92) if c / 255 <= 0.04045 else (((c / 255) + 0.055) / 1.055) ** 2.4 for c in col]
    J['materials'].append({'name': 'rws_cap', 'pbrMetallicRoughness': {'baseColorFactor': lin + [1], 'metallicFactor': 0.1, 'roughnessFactor': 0.9}})
    mi = len(J['materials']) - 1
    glbfix.solid_textures(J, BIN, log=lambda *a: None)
    return mi


def ellipse(c, r, n=28):
    """水平的椭圆片（朝上），三角扇"""
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    P = np.c_[c[0] + r[0] * np.cos(a), np.full(n, c[1]), c[2] + r[1] * np.sin(a)]
    P = np.r_[[c], P]
    T = np.array([[0, 1 + (i + 1) % n, 1 + i] for i in range(n)])   # 从上往下看逆时针：正面朝上
    N = np.tile([0, 1, 0], (len(P), 1)).astype(np.float32)
    UV = np.c_[(P[:, 0] - c[0]) / (2 * r[0]) + 0.5, (P[:, 2] - c[2]) / (2 * r[1]) + 0.5].astype(np.float32)
    return {'P': P, 'N': N, 'UV': UV, 'T': T}


def run(key, log=print):
    sp = SPEC[key]
    path = 'models/veh/%s.glb' % key
    lines = open(META, encoding='utf-8').read().split('\n')
    li = next(i for i, ln in enumerate(lines) if ln.startswith('    %s = { ' % key))
    info = airpaint.lua_parse(lines[li].strip()[len(key) + 3:].rstrip(','))
    if info.get('rws'):
        log('%s：元数据里已经有 rws（拆过了），跳过' % key)
        return
    J, BIN = glbfix.read(path)
    chunks = load(J, BIN, key)
    moved = {}   # 目标部件 → [子网格]
    gone = {}    # 块名 → 剩下的三角形掩码
    keep = {c['name']: np.ones(len(c['T']), dtype=bool) for c in chunks}
    for rule in sp.get('split', []):
        src = [c for c in chunks if c['group'] == rule['from']]
        allT = np.concatenate([c['P'][c['T'][keep[c['name']]]] for c in src])
        lab = comps(allT)
        ok = inside(allT, rule)
        bad = np.unique(lab[~ok])
        take = ~np.isin(lab, bad)   # 整个连通块都在框里
        o = 0
        n_take = 0
        for c in src:
            idx = np.nonzero(keep[c['name']])[0]
            sel = take[o:o + len(idx)]
            o += len(idx)
            if sel.any():
                m = np.zeros(len(c['T']), dtype=bool)
                m[idx[sel]] = True
                moved.setdefault(rule['to'], []).append(sub(c, m))
                keep[c['name']][idx[sel]] = False
                n_take += int(sel.sum())
        log('  %s → %s：%d 个三角形' % (rule['from'], rule['to'], n_take))
    for rule in sp.get('cut', []):
        n_cut = 0
        for c in chunks:
            if c['group'] != rule['from']:
                continue
            m = inside(c['P'][c['T']], rule) & keep[c['name']]
            keep[c['name']] &= ~m
            n_cut += int(m.sum())
        log('  去掉 %s 框里 %d 个三角形' % (rule['from'], n_cut))
    out = BIN
    parts = info['parts']
    # 改过的块：剩下的写回原节点（中心、大小跟着变）；剩不下的删掉
    for c in chunks:
        k = keep[c['name']]
        if k.all():
            continue
        if not k.any():
            J['nodes'][c['ni']] = {'name': 'V_%s__%s' % (key, c['name'])}   # 空节点（下面从父节点里拿掉）
            parts.pop(c['name'], None)
            gone[c['name']] = True
            continue
        g = sub(c, k)
        _, cc, ss = write_chunk(J, out, g, 'V_%s__%s' % (key, c['name']), node=c['ni'])
        parts[c['name']]['c'] = [round(float(x), 3) for x in cc]
        parts[c['name']]['s'] = [round(float(x), 3) for x in ss]
    if gone:
        J['nodes'][0]['children'] = [i for i in J['nodes'][0]['children'] if 'mesh' in J['nodes'][i]]
    # 拆出来的部件：按材质分块，一块不超过 TRI_MAX
    for grp, subs in moved.items():
        bym = {}
        for s in subs:
            bym.setdefault(s['mat'], []).append(s)
        k = 0
        for mat in sorted(bym, key=lambda x: -1 if x is None else x):
            g = merge(bym[mat])
            for t0 in range(0, len(g['T']), TRI_MAX):
                piece = sub({'P': g['P'], 'N': g['N'], 'UV': g['UV'], 'T': g['T'], 'mat': mat}, np.arange(len(g['T']))[t0:t0 + TRI_MAX])
                k += 1
                nm = '%s_%d' % (grp, k)
                _, cc, ss = write_chunk(J, out, piece, 'V_%s__%s' % (key, nm))
                parts[nm] = {'c': [round(float(x), 3) for x in cc], 'g': grp, 's': [round(float(x), 3) for x in ss]}
    # 切口盖板（炮塔的一部分）
    if sp.get('cap'):
        cp = sp['cap']
        mi = cap_material(J, out, cp['col'])
        g = ellipse(np.array(cp['c'], dtype=np.float64), cp['r'])
        g['mat'] = mi
        n_t = sum(1 for nm in parts if parts[nm].get('g') == 'Turret')
        nm = 'Turret_%d' % (n_t + 1)
        while nm in parts:
            n_t += 1
            nm = 'Turret_%d' % (n_t + 1)
        _, cc, ss = write_chunk(J, out, g, 'V_%s__%s' % (key, nm))
        parts[nm] = {'c': [round(float(x), 3) for x in cc], 'col': list(cp['col']), 'g': 'Turret', 's': [round(float(x), 3) for x in ss]}
        log('  切口盖板 %s' % nm)
    out = compact(J, out)
    glbfix.write(path, J, out)
    info['rws'] = {k: v for k, v in sp['rws'].items()}
    lines[li] = '    %s = %s,' % (key, B.lua(info))
    open(META, 'w', encoding='utf-8').write('\n'.join(lines))
    log('%s：写好了 %s、元数据（rws %s）' % (key, path, info['rws']))


if __name__ == '__main__':
    for k in (sys.argv[1:] or list(SPEC)):
        run(k)
