#!/usr/bin/env python3
# 断翼（用户 11-25「飞机如果断了机翼 那机翼应该要能掉下去」「机翼应该会消失才对」）：把原模型的外翼切成单独的块
#   原模型（models/air/<文件>.glb，sf_air.py / air2glb.py 转出来的）机身、机翼是同一块网格，断了翼也藏不掉。
#   这里按翼展切：机身（Body）和长在机翼上的活动面（副翼、襟翼 / 襟副翼、升降副翼、折叠外翼、翼尖段）在 |x| = xr 处
#   按平面裁开（三角形跨过切面的按真交点切成两半，位置、法线、贴图坐标都插值，断口是直的），外面那段另成一块（元数据 w = "L" / "R"）；
#   平尾、鸭翼、垂尾、起落架、舱门、座舱不动。切面：默认半个翼展；折叠翼的（歼-15T）就在折叠线上。
#   换一个版本号写出来（j20_v5 → j20_v6，j6 → j6_v2：导入后的块叫 A_<新键>__…，和用户已经导入的不重名；文件名不变），
#   ImportedAir 的 alias 指到新版本，老版本记进 old（没重导的照旧用老的，只是断翼时那边不消失）；
#   元数据加 wcut = { x = 切面, L = { y0, y1, z0, z1 }, R = { … } }：断口截面的范围（游戏里在那儿补一块烧黑的断面）
#   用法：python3 -I tools/models/wingcut.py [机型 id …]（不写就是全部固定翼）
import json, math, os, re, struct, sys
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import mdl2glb as B   # noqa: E402

META = 'src/ReplicatedStorage/ImportedAir.lua'
# 长在机翼上的活动面（组名开头）；别的组（平尾 Stab / Elev、鸭翼 Can、垂尾 Fin / Rud、起落架、舱门、座舱……）不切
WINGISH = re.compile(r'^(Body|Ail|Flp|Elv|Fold|Tip|Slat|Lef|Spl)')
EXCLUDE = {'j15t': {'TipL', 'TipR'}}   # 歼-15T 的 Tip 是平尾外段（折叠），不是机翼
SKIP = {'tvc'}


# ---------------------------------------------------------------- ImportedAir.lua 的表（mdl2glb.lua 写的那种）读回 Python
def lua_parse(s):
    i, n = 0, len(s)

    def ws():
        nonlocal i
        while i < n and s[i] in ' \t\r\n':
            i += 1

    def value():
        nonlocal i
        ws()
        c = s[i]
        if c == '{':
            i += 1
            arr, obj = [], {}
            while True:
                ws()
                if s[i] == '}':
                    i += 1
                    break
                m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*=', s[i:])
                m2 = re.match(r'\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=', s[i:])
                m3 = re.match(r'\[\s*(-?\d+)\s*\]\s*=', s[i:])
                if m:
                    i += m.end()
                    obj[m.group(1)] = value()
                elif m2:
                    i += m2.end()
                    obj[m2.group(1)] = value()
                elif m3:
                    i += m3.end()
                    obj[int(m3.group(1))] = value()
                else:
                    arr.append(value())
                ws()
                if s[i] == ',':
                    i += 1
            if obj and arr:
                for k, v in enumerate(arr):
                    obj[k + 1] = v
                return obj
            return obj if obj else arr
        if c == '"':
            j = i + 1
            out = []
            while s[j] != '"':
                if s[j] == '\\':
                    out.append(s[j:j + 2])
                    j += 2
                else:
                    out.append(s[j])
                    j += 1
            i = j + 1
            return json.loads('"' + ''.join(out) + '"')
        m = re.match(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?', s[i:])
        if m:
            i += m.end()
            t = m.group(0)
            return float(t) if any(ch in t for ch in '.eE') else int(t)
        if s.startswith('true', i):
            i += 4
            return True
        if s.startswith('false', i):
            i += 5
            return False
        if s.startswith('nil', i):
            i += 3
            return None
        raise ValueError('读不懂：' + s[i:i + 40])

    return value()


# ---------------------------------------------------------------- GLB
def load_glb(path):
    f = open(path, 'rb').read()
    L = struct.unpack('<I', f[12:16])[0]
    J = json.loads(f[20:20 + L])
    off = 20 + L
    bl = struct.unpack('<I', f[off:off + 4])[0]
    return J, f[off + 8:off + 8 + bl]


NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
DT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}


def accessor(J, BIN, i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    n = NCOMP[a['type']]
    dt = DT[a['componentType']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride')
    isz = np.dtype(dt).itemsize
    if stride and stride != n * isz:
        raw = np.frombuffer(BIN, dtype=np.uint8, count=stride * a['count'], offset=o).reshape(a['count'], stride)[:, :n * isz]
        arr = np.frombuffer(raw.tobytes(), dtype=dt).reshape(a['count'], n)
    else:
        arr = np.frombuffer(BIN, dtype=dt, count=a['count'] * n, offset=o).reshape(a['count'], n)
    arr = arr.astype(np.float64)
    if a.get('normalized') and dt != np.float32:
        arr = arr / float(np.iinfo(dt).max)
    return arr if n > 1 else arr[:, 0]


# ---------------------------------------------------------------- 裁切：一张三角形表按 x = c 切成 外（side 那边）/ 里两份
def clip_tris(V, A, T, c, side):
    """V：顶点（世界坐标）；A：{名字: 属性数组}；T：三角形 (k, 3)。side = -1：x < c 算外面；+1：x > c 算外面。
    返回 (外, 里)，每份是 (V, A, T)；还有切面上的点（断口截面）"""
    d = (V[:, 0] - c) * side   # > 0 在外面
    outs = {'o': ([], {k: [] for k in A}, []), 'i': ([], {k: [] for k in A}, [])}
    maps = {'o': {}, 'i': {}}
    cut_pts = []

    def vid(which, key, pos, attrs):
        mp = maps[which]
        if key in mp:
            return mp[key]
        vs, aa, _ = outs[which]
        vs.append(pos)
        for k in aa:
            aa[k].append(attrs[k])
        mp[key] = len(vs) - 1
        return mp[key]

    def orig(i):
        return ('v', int(i)), V[i], {k: A[k][i] for k in A}

    def inter(i, j):
        t = d[i] / (d[i] - d[j])
        p = V[i] + (V[j] - V[i]) * t
        at = {k: A[k][i] + (A[k][j] - A[k][i]) * t for k in A}
        a, b = (int(i), int(j)) if i < j else (int(j), int(i))
        cut_pts.append(p)
        return ('e', a, b), p, at

    for tri in T:
        sd = d[tri]
        if np.all(sd >= 0) or np.all(sd <= 0):
            which = 'o' if np.sum(sd) > 0 else 'i'
            if np.all(sd == 0):
                which = 'i'
            ids = [vid(which, *orig(v)) for v in tri]
            outs[which][2].append(ids)
            continue
        # 跨过切面：Sutherland–Hodgman，两边各一个多边形（顺序不变 → 朝向不变），扇形三角化
        for which, keep in (('o', lambda x: x >= 0), ('i', lambda x: x <= 0)):
            poly = []
            for k in range(3):
                a, b = tri[k], tri[(k + 1) % 3]
                da, db = d[a], d[b]
                if keep(da):
                    poly.append(orig(a))
                if (da > 0 and db < 0) or (da < 0 and db > 0):
                    poly.append(inter(a, b))
            if len(poly) < 3:
                continue
            ids = [vid(which, *p) for p in poly]
            for k in range(1, len(ids) - 1):
                if ids[0] != ids[k] and ids[k] != ids[k + 1] and ids[0] != ids[k + 1]:
                    outs[which][2].append([ids[0], ids[k], ids[k + 1]])

    res = []
    for which in ('o', 'i'):
        vs, aa, ts = outs[which]
        if not ts:
            res.append(None)
            continue
        res.append((np.array(vs), {k: np.array(v) for k, v in aa.items()}, np.array(ts, dtype=np.int64)))
    return res[0], res[1], cut_pts


# ---------------------------------------------------------------- 写 GLB（图片、材质原样，网格重写）
def write_glb(path, J, BIN, nodes_out, root_name):
    out = {'asset': {'version': '2.0', 'generator': 'RobloxTotalBattlefield wingcut.py'}, 'scene': 0,
           'scenes': [{'name': root_name, 'nodes': [0]}], 'nodes': [{'name': root_name, 'children': []}],
           'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [],
           'materials': J.get('materials', []), 'textures': J.get('textures', []), 'images': [], 'samplers': J.get('samplers', [])}
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

    for im in J.get('images', []):   # 贴图照搬
        bv = J['bufferViews'][im['bufferView']]
        data = BIN[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        im2 = dict(im)
        im2['bufferView'] = view(data)
        out['images'].append(im2)
    TYP = {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}
    for name, center, prims in nodes_out:
        mprims = []
        for (Vl, A, T, mat) in prims:
            attrs = {'POSITION': acc(Vl.astype(np.float32), 'VEC3', minmax=True)}
            for k, arr in A.items():
                a2 = arr if arr.ndim > 1 else arr[:, None]
                if k == 'NORMAL':
                    ln = np.linalg.norm(a2, axis=1, keepdims=True)
                    a2 = a2 / np.maximum(ln, 1e-9)
                attrs[k] = acc(a2.astype(np.float32), TYP[a2.shape[1]])
            idx = T.reshape(-1)
            if len(Vl) < 65536:
                ia = acc(idx.astype(np.uint16), 'SCALAR', 5123, target=34963)
            else:
                ia = acc(idx.astype(np.uint32), 'SCALAR', 5125, target=34963)
            p = {'attributes': attrs, 'indices': ia}
            if mat is not None:
                p['material'] = mat
            mprims.append(p)
        out['meshes'].append({'name': name, 'primitives': mprims})
        out['nodes'].append({'name': name, 'mesh': len(out['meshes']) - 1, 'translation': [round(float(x), 3) for x in center]})
        out['nodes'][0]['children'].append(len(out['nodes']) - 1)
    out['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(bytes(blob))


def bump(k):
    m = re.match(r'^(.*)_v(\d+)$', k)
    return '%s_v%d' % (m.group(1), int(m.group(2)) + 1) if m else k + '_v2'


def r3(v):
    return [round(float(x), 3) for x in v]


def cut_one(kname, info, J, BIN, newk, fold_x=None):
    excl = EXCLUDE.get(re.sub(r'_v\d+$', '', kname), set())
    parts = info['parts']
    # 翼展：机身 + 机翼上的活动面最远的点
    nodes = []
    b = 0.0
    for n in J['nodes']:
        if 'mesh' not in n:
            continue
        nm = n['name'].split('__', 1)[1]
        p = parts.get(nm)
        if not p:
            print('    元数据里没有 %s，跳过' % nm)
            continue
        t = np.array(n.get('translation', [0, 0, 0]), dtype=np.float64)
        prims = []
        for pr in J['meshes'][n['mesh']]['primitives']:
            V = accessor(J, BIN, pr['attributes']['POSITION']) + t
            A = {k: accessor(J, BIN, i) for k, i in pr['attributes'].items() if k != 'POSITION'}
            if 'indices' in pr:
                T = accessor(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            else:
                T = np.arange(len(V)).reshape(-1, 3)
            prims.append((V, A, T, pr.get('material')))
        g = p['g']
        wing = bool(WINGISH.match(g)) and g not in excl
        if wing:
            for (V, _, _, _) in prims:
                b = max(b, float(np.abs(V[:, 0]).max()))
        nodes.append((nm, p, prims, wing))
    xr = fold_x if fold_x else 0.5 * b
    print('    翼展 ±%.1f 格，切面 |x| = %.2f' % (b, xr))
    new_parts, nodes_out = {}, []
    cuts = {'L': [], 'R': []}
    nL = nR = 0
    for nm, p, prims, wing in nodes:
        pieces = {'': [], 'L': [], 'R': []}
        for (V, A, T, mat) in prims:
            if not wing or float(np.abs(V[:, 0]).max()) <= xr:
                pieces[''].append((V, A, T, mat))
                continue
            oL, rest, cpL = clip_tris(V, A, T, -xr, -1)
            cuts['L'] += cpL
            if oL:
                pieces['L'].append(oL + (mat,))
            if rest:
                oR, inner, cpR = clip_tris(rest[0], rest[1], rest[2], xr, 1)
                cuts['R'] += cpR
                if oR:
                    pieces['R'].append(oR + (mat,))
                if inner:
                    pieces[''].append(inner + (mat,))
        for side, plist in pieces.items():
            if not plist:
                continue
            allV = np.concatenate([q[0] for q in plist])
            lo, hi = allV.min(0), allV.max(0)
            ctr = (lo + hi) / 2
            name = nm if side == '' else ('%s_w%s' % (nm, side))
            p2 = dict(p)
            p2['c'], p2['s'] = r3(ctr), r3(np.maximum(hi - lo, 0.02))
            if side:
                p2['w'] = side
                if side == 'L':
                    nL += 1
                else:
                    nR += 1
            new_parts[name] = p2
            nodes_out.append(('A_%s__%s' % (newk, name), ctr, [(q[0] - ctr, q[1], q[2], q[3]) for q in plist]))
    wc = {'x': round(xr, 3)}
    for side in ('L', 'R'):
        P = np.array(cuts[side]) if cuts[side] else None
        if P is not None and len(P):
            wc[side] = r3([P[:, 1].min(), P[:, 1].max(), P[:, 2].min(), P[:, 2].max()])
    print('    外翼：左 %d 块、右 %d 块；断口 %s' % (nL, nR, wc))
    return new_parts, nodes_out, wc


def main(argv):
    src = open(META, encoding='utf-8').read()
    m_alias = re.search(r'\n  alias = (\{.*?\}),\n  old = ', src, re.S)
    m_old = re.search(r'\n  old = (\{.*?\}),\n  m = \{\n', src, re.S)
    alias = lua_parse(m_alias.group(1))
    oldt = lua_parse(m_old.group(1))
    lines = B.old_lines(META)
    AD = None
    want = set(argv)
    done = {}
    for aid, kv in sorted(alias.items()):
        plain = kv.endswith('~')
        kname = kv[:-1] if plain else kv
        if want and aid not in want:
            continue
        if kname in SKIP or kname not in lines:
            continue
        line = lines[kname]
        info = lua_parse(line.split('=', 1)[1].strip().rstrip(','))
        if info.get('rotor') or any(p.get('g') in ('Rotor', 'Rotor2', 'TRotor') for p in info['parts'].values()):
            continue   # 直升机：断的是旋翼，不切
        if info.get('wcut'):
            continue   # 已经切过
        if kname not in done:
            fname = re.sub(r'_v\d+$', '', kname)
            path = os.path.join('models/air', fname + '.glb')
            if not os.path.exists(path):
                print('  没有 %s，跳过 %s' % (path, kname))
                continue
            J, BIN = load_glb(path)
            if not J['nodes'][1]['name'].startswith('A_%s__' % kname):
                print('  %s 里不是 %s 的块（%s），跳过' % (path, kname, J['nodes'][1]['name']))
                continue
            newk = bump(kname)
            print('  %s → %s（%s）' % (kname, newk, path))
            fold = info.get('fold') or {}
            fx = (fold.get('Fold') or {}).get('x')
            new_parts, nodes_out, wc = cut_one(kname, info, J, BIN, newk, fx)
            info2 = dict(info)
            info2['parts'] = new_parts
            info2['wcut'] = wc
            write_glb(path, J, BIN, nodes_out, 'A_' + newk)
            print('    写好了 %s（%.1f MB）' % (path, os.path.getsize(path) / 1e6))
            lines[newk] = '    %s = %s,\n' % (newk, B.lua(info2))
            done[kname] = newk
        newk = done[kname]
        alias[aid] = newk + ('~' if plain else '')
        prev = oldt.get(aid) or []
        if isinstance(prev, str):
            prev = [prev]
        oldt[aid] = [kv] + [k for k in prev if k not in (kv, newk, newk + '~')]
    if not done:
        print('没有要切的')
        return
    body = '\n  alias = ' + B.lua(alias) + ',\n  old = ' + B.lua(oldt) + ',\n  m = {\n'
    for k_ in sorted(lines):
        ln = lines[k_]
        body += ln if ln.endswith('\n') else ln + '\n'
    body += '  },\n}\n'
    open(META, 'w', encoding='utf-8').write(src[:m_alias.start()] + body)
    print('元数据写好了：%s' % ', '.join('%s → %s' % kv for kv in done.items()))


if __name__ == '__main__':
    main(sys.argv[1:])
