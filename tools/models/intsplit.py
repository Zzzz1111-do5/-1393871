# 把原模型自带车内的一整块网格（m1a1i 的 Int_2：整个炮塔内饰一块 1.2 万个三角形）按连通块拆成几块（用户 11-24：「把 m1a1 内饰部分插件搬到 a2 和 m3 布莱德利里」）：
#   炮闩 / 防危板（归炮，跟着俯仰、开炮后坐）、炮长位、车长位、车长显示器、装填手位、座椅、炮塔壳……——拆开以后 M1A2 整套借用、布雷德利只借炮长位和车长位那几件
#   python3 -I tools/models/intsplit.py m1a1i dump              列出连通块（三角形数、包围盒，格）
#   python3 -I tools/models/intsplit.py m1a1i preview=<目录>    每组一个颜色的 GLB（tools/models/intsplit_view.cjs 画）
#   python3 -I tools/models/intsplit.py m1a1i write             按 tools/models/intsplit.json 拆好写回 models/veh/<键>.glb，ImportedMeta 加新块（rep 顶替旧块）
#   配置（intsplit.json）：src 要拆的块；groups 按顺序：{ name, g 部件（Turret / Gun）, boxes [[x0,x1,y0,y1,z0,z1]...]（格，模型坐标），minTris }，
#     连通块的中心落在哪组的框里就归哪组（先匹配的先得），都不在的归 rest
import json, struct, sys, os, re
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
CFG = os.path.join(HERE, 'intsplit.json')

def load_glb(path):
    b = open(path, 'rb').read()
    magic, ver, ln = struct.unpack('<III', b[:12])
    assert magic == 0x46546C67, 'not a glb'
    off = 12
    js, bin_ = None, b''
    while off < len(b):
        cl, ct = struct.unpack('<II', b[off:off + 8])
        data = b[off + 8:off + 8 + cl]
        if ct == 0x4E4F534A: js = json.loads(data)
        elif ct == 0x004E4942: bin_ = data
        off += 8 + cl
    return js, bytearray(bin_)

def save_glb(path, js, bin_):
    jb = json.dumps(js, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    jb += b' ' * ((4 - len(jb) % 4) % 4)
    bb = bytes(bin_) + b'\x00' * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), 0x4E4F534A)); f.write(jb)
        f.write(struct.pack('<II', len(bb), 0x004E4942)); f.write(bb)

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8, 5122: np.int16, 5120: np.int8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def read_acc(js, bin_, i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    n = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0) or dt.itemsize * n
    cnt = a['count']
    if stride == dt.itemsize * n:
        arr = np.frombuffer(bytes(bin_[off:off + cnt * stride]), dtype=dt).reshape(cnt, n)
    else:
        raw = np.frombuffer(bytes(bin_[off:off + cnt * stride]), dtype=np.uint8).reshape(cnt, stride)
        arr = raw[:, :dt.itemsize * n].copy().view(dt).reshape(cnt, n)
    if a.get('normalized'):
        arr = arr.astype(np.float32) / np.iinfo(dt).max
    return arr.copy()

def node_by_name(js, name):
    for i, n in enumerate(js['nodes']):
        if n.get('name') == name: return i, n
    return None, None

def find(par, i):
    while par[i] != i:
        par[i] = par[par[i]]
        i = par[i]
    return i

def components(pos, idx):
    """连通块：位置相同的顶点焊在一起（UV 缝、法线缝上的重复顶点）再按三角形连；返回每个三角形的块号"""
    key = np.round(pos / 1e-4).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    tri = weld[idx.reshape(-1, 3)]
    nv = weld.max() + 1
    par = np.arange(nv)
    for a, b, c in tri:
        ra, rb, rc = find(par, a), find(par, b), find(par, c)
        if ra != rb: par[rb] = ra
        rc = find(par, c)
        ra = find(par, a)
        if ra != rc: par[rc] = ra
    root = np.array([find(par, v) for v in range(nv)])
    _, comp = np.unique(root[tri[:, 0]], return_inverse=True)
    return comp.reshape(-1)

def prim_arrays(js, bin_, mesh):
    assert len(mesh['primitives']) == 1, '只处理一个图元的块'
    pr = mesh['primitives'][0]
    att = {k: read_acc(js, bin_, v) for k, v in pr['attributes'].items()}
    idx = read_acc(js, bin_, pr['indices']).reshape(-1).astype(np.int64)
    return pr, att, idx

def analyze(js, bin_, cfg):
    ni, node = node_by_name(js, 'V_%s__%s' % (cfg['key'], cfg['src']))
    assert node is not None, '找不到要拆的块'
    mesh = js['meshes'][node['mesh']]
    pr, att, idx = prim_arrays(js, bin_, mesh)
    t = np.array(node.get('translation', [0, 0, 0]), dtype=np.float64)
    assert 'rotation' not in node and 'scale' not in node, '块上有旋转 / 缩放，不处理'
    pos = att['POSITION'].astype(np.float64)
    comp = components(pos, idx)
    tris = idx.reshape(-1, 3)
    out = []
    for c in range(comp.max() + 1):
        sel = np.nonzero(comp == c)[0]
        vs = pos[np.unique(tris[sel].reshape(-1))] + t
        out.append({'id': c, 'n': int(len(sel)), 'min': vs.min(0), 'max': vs.max(0), 'c': (vs.min(0) + vs.max(0)) / 2})
    return ni, node, mesh, pr, att, idx, t, comp, out

def classify(out, cfg):
    groups = cfg['groups']
    lab = {}
    force = {}
    for gdef in groups:   # ids：直接点名的连通块（框分不开的大块薄板、挨着别的组的小件），先于框
        for i in gdef.get('ids', []): force[i] = gdef['name']
    for o in out:
        if o['id'] in force:
            lab[o['id']] = force[o['id']]
            continue
        name = 'rest'
        for gdef in groups:
            for bx in gdef.get('boxes', []):
                x0, x1, y0, y1, z0, z1 = bx
                c = o['c']
                if x0 <= c[0] <= x1 and y0 <= c[1] <= y1 and z0 <= c[2] <= z1:
                    name = gdef['name']
                    break
            if name != 'rest': break
        lab[o['id']] = name
    return lab

def main():
    key = sys.argv[1] if len(sys.argv) > 1 else 'm1a1i'
    args = sys.argv[2:]
    cfgAll = json.load(open(CFG, encoding='utf-8'))
    cfg = cfgAll[key]
    cfg['key'] = key
    glb = os.path.join(ROOT, 'models', 'veh', key + '.glb')
    if cfg.get('orig'):   # 永远从拆之前的原样开始（git 里的 blob），可以反复调分组重跑
        import subprocess, tempfile
        raw = subprocess.run(['git', '-C', ROOT, 'cat-file', 'blob', cfg['orig']], capture_output=True, check=True).stdout
        tmp = os.path.join(tempfile.gettempdir(), 'intsplit_%s_orig.glb' % key)
        open(tmp, 'wb').write(raw)
        js, bin_ = load_glb(tmp)
    else:
        js, bin_ = load_glb(glb)
    ni, node, mesh, pr, att, idx, t, comp, out = analyze(js, bin_, cfg)
    lab = classify(out, cfg)
    if 'dump' in args:
        out.sort(key=lambda o: (lab[o['id']], -o['n']))
        for o in out:
            print('%-10s #%-4d n=%-5d c=(%6.2f %6.2f %6.2f) s=(%5.2f %5.2f %5.2f)' % (lab[o['id']], o['id'], o['n'], o['c'][0], o['c'][1], o['c'][2],
                  *(o['max'] - o['min'])))
        tot = {}
        for o in out: tot[lab[o['id']]] = tot.get(lab[o['id']], 0) + o['n']
        print('组：', tot)
        return
    cp = [a for a in args if a.startswith('comps=')]
    if cp:   # 每个连通块各是一块（名字 c<号>），给 intsplit_view 标号看哪块是什么
        labC = {o['id']: 'c%d' % o['id'] for o in out}
        cfgC = dict(cfg)
        cfgC['groups'] = [{'name': 'c%d' % o['id']} for o in out]
        write_split(key, js, bin_, ni, node, mesh, pr, att, idx, t, comp, labC, cfgC, os.path.join(cp[0][6:], key + '_comps.glb'), colors=True)
        return
    pv = [a for a in args if a.startswith('preview=')]
    if pv:
        write_split(key, js, bin_, ni, node, mesh, pr, att, idx, t, comp, lab, cfg, os.path.join(pv[0][8:], key + '_split.glb'), colors=True)
        return
    if 'write' in args:
        write_split(key, js, bin_, ni, node, mesh, pr, att, idx, t, comp, lab, cfg, glb, colors=False)
        return
    print('用法见文件开头')

PALETTE = [(230, 80, 60), (60, 160, 230), (90, 200, 90), (230, 200, 60), (180, 90, 220), (240, 140, 40), (60, 210, 200), (200, 200, 200), (140, 100, 60), (255, 120, 200), (120, 120, 255), (40, 90, 40), (255, 255, 140), (110, 30, 30)]

def write_split(key, js, bin_, ni, node, mesh, pr, att, idx, t, comp, lab, cfg, outPath, colors=False):
    names = [g['name'] for g in cfg['groups']] + ['rest']
    tris = idx.reshape(-1, 3)
    newNodes = []
    meta = {}
    for gi, gname in enumerate(names):
        cids = [c for c, l in lab.items() if l == gname]
        if not cids: continue
        selT = np.nonzero(np.isin(comp, cids))[0]
        used = np.unique(tris[selT].reshape(-1))
        remap = -np.ones(len(att['POSITION']), dtype=np.int64)
        remap[used] = np.arange(len(used))
        newIdx = remap[tris[selT]].reshape(-1).astype(np.uint32)
        pos = att['POSITION'][used].astype(np.float64) + t
        lo, hi = pos.min(0), pos.max(0)
        ctr = (lo + hi) / 2
        newAtt = {}
        for k, arr in att.items():
            a = arr[used].astype(np.float32)
            if k == 'POSITION': a = (pos - ctr).astype(np.float32)
            newAtt[k] = a
        # 写进 bin：每个属性一个 bufferView + accessor
        accIds = {}
        for k, a in newAtt.items():
            while len(bin_) % 4: bin_.append(0)
            off = len(bin_)
            bin_.extend(a.tobytes())
            js['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': a.nbytes, 'target': 34962})
            acc = {'bufferView': len(js['bufferViews']) - 1, 'componentType': 5126, 'count': int(a.shape[0]), 'type': {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[a.shape[1]]}
            if k == 'POSITION':
                acc['min'] = [float(x) for x in a.min(0)]
                acc['max'] = [float(x) for x in a.max(0)]
            js['accessors'].append(acc)
            accIds[k] = len(js['accessors']) - 1
        while len(bin_) % 4: bin_.append(0)
        off = len(bin_)
        bin_.extend(newIdx.tobytes())
        js['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': newIdx.nbytes, 'target': 34963})
        js['accessors'].append({'bufferView': len(js['bufferViews']) - 1, 'componentType': 5125, 'count': int(len(newIdx)), 'type': 'SCALAR'})
        prim = {'attributes': accIds, 'indices': len(js['accessors']) - 1, 'mode': 4}
        mat = pr.get('material')
        if colors:
            c = PALETTE[gi % len(PALETTE)]
            js['materials'].append({'name': 'split_' + gname, 'pbrMetallicRoughness': {'baseColorFactor': [c[0] / 255, c[1] / 255, c[2] / 255, 1], 'metallicFactor': 0, 'roughnessFactor': 0.8}})
            mat = len(js['materials']) - 1
        if mat is not None: prim['material'] = mat
        js['meshes'].append({'name': 'Int_' + gname, 'primitives': [prim]})
        nname = 'V_%s__Int_%s' % (key, gname)
        js['nodes'].append({'name': nname, 'mesh': len(js['meshes']) - 1, 'translation': [float(x) for x in ctr]})
        newNodes.append(len(js['nodes']) - 1)
        gdef = next((g for g in cfg['groups'] if g['name'] == gname), {})
        meta['Int_' + gname] = {'g': gdef.get('g', 'Turret'), 'c': [round(float(x), 3) for x in ctr], 's': [round(float(x), 3) for x in (hi - lo)], 'k': 'int', 'n': int(len(selT))}
        if not gname.startswith('c'): print('%-14s %5d 个三角形  中心 (%.2f, %.2f, %.2f)  大小 (%.2f, %.2f, %.2f)' % ('Int_' + gname, len(selT), *ctr, *(hi - lo)))
    # 场景：旧块换成新块（同一层）
    for sc in js['scenes']:
        nodes = sc['nodes']
        if ni in nodes:
            k = nodes.index(ni)
            sc['nodes'] = nodes[:k] + newNodes + nodes[k + 1:]
    for n in js['nodes']:
        ch = n.get('children')
        if ch and ni in ch:
            k = ch.index(ni)
            n['children'] = ch[:k] + newNodes + ch[k + 1:]
    js['buffers'][0]['byteLength'] = len(bin_)
    js, bin_ = compact(js, bin_)   # 旧的那块（场景里不引用了）连同它的网格、数据一起删掉
    save_glb(outPath, js, bin_)
    print('写好了', outPath, '（%.1f MB）' % (os.path.getsize(outPath) / 1e6))
    if colors:
        return
    write_meta(key, cfg, meta)

def compact(js, bin_):
    """只留场景里用到的节点、网格、访问器、缓冲视图（材质、贴图、图片全留）；重排二进制块"""
    used = []
    def walk(i):
        if i in used: return
        used.append(i)
        for c in js['nodes'][i].get('children', []): walk(c)
    for sc in js['scenes']:
        for i in sc['nodes']: walk(i)
    used.sort()
    nmap = {o: k for k, o in enumerate(used)}
    nodes = [js['nodes'][i] for i in used]
    for n in nodes:
        if 'children' in n: n['children'] = [nmap[c] for c in n['children']]
    for sc in js['scenes']: sc['nodes'] = [nmap[i] for i in sc['nodes']]
    mused = sorted({n['mesh'] for n in nodes if 'mesh' in n})
    mmap = {o: k for k, o in enumerate(mused)}
    meshes = [js['meshes'][i] for i in mused]
    for n in nodes:
        if 'mesh' in n: n['mesh'] = mmap[n['mesh']]
    aused = set()
    for m in meshes:
        for pr in m['primitives']:
            aused.update(pr['attributes'].values())
            if 'indices' in pr: aused.add(pr['indices'])
            for t in pr.get('targets', []): aused.update(t.values())
    aused = sorted(aused)
    amap = {o: k for k, o in enumerate(aused)}
    accs = [js['accessors'][i] for i in aused]
    for m in meshes:
        for pr in m['primitives']:
            pr['attributes'] = {k: amap[v] for k, v in pr['attributes'].items()}
            if 'indices' in pr: pr['indices'] = amap[pr['indices']]
            if 'targets' in pr: pr['targets'] = [{k: amap[v] for k, v in t.items()} for t in pr['targets']]
    bused = sorted({a['bufferView'] for a in accs if 'bufferView' in a} | {im['bufferView'] for im in js.get('images', []) if 'bufferView' in im})
    bmap = {o: k for k, o in enumerate(bused)}
    newBin = bytearray()
    views = []
    for i in bused:
        bv = dict(js['bufferViews'][i])
        while len(newBin) % 4: newBin.append(0)
        off = bv.get('byteOffset', 0)
        data = bin_[off:off + bv['byteLength']]
        bv['byteOffset'] = len(newBin)
        newBin.extend(data)
        views.append(bv)
    for a in accs:
        if 'bufferView' in a: a['bufferView'] = bmap[a['bufferView']]
    for im in js.get('images', []):
        if 'bufferView' in im: im['bufferView'] = bmap[im['bufferView']]
    js['nodes'], js['meshes'], js['accessors'], js['bufferViews'] = nodes, meshes, accs, views
    js['buffers'][0]['byteLength'] = len(newBin)
    return js, newBin

META = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'ImportedMeta.lua')

def lua(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k, lua(v[k])) for k in sorted(v)) + ' }'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, float):
        return ('%.3f' % v).rstrip('0').rstrip('.')
    return str(v)

def write_meta(key, cfg, meta):
    """ImportedMeta 里这个模型那一行：parts 里加新块（rep 顶替被拆的那块：没重新导入的照旧用旧块）；旧块的元数据留着"""
    lines = open(META, encoding='utf-8').read().split('\n')
    tag = '    %s = { ' % key
    k = next((i for i, ln in enumerate(lines) if ln.startswith(tag)), None)
    assert k is not None, 'ImportedMeta 里没有 %s' % key
    ln = lines[k]
    # 先去掉上次拆的（Int_ 开头、带 rep 的）
    ln = re.sub(r'Int_\w+ = \{ [^{}]*(?:\{[^{}]*\}[^{}]*)*rep = \{ "%s" \}[^{}]*(?:\{[^{}]*\}[^{}]*)*\}, ' % cfg['src'], '', ln)
    add = ''
    for name in sorted(meta):
        e = dict(meta[name])
        e.pop('n', None)
        e['rep'] = [cfg['src']]
        add += '%s = %s, ' % (name, lua(e))
    i = ln.find('parts = { ')
    assert i >= 0
    i += len('parts = { ')
    ln = ln[:i] + add + ln[i:]
    lines[k] = ln
    open(META, 'w', encoding='utf-8').write('\n'.join(lines))
    print('写好了 %s：%s 加了 %d 块（顶替 %s）' % (os.path.relpath(META, ROOT), key, len(meta), cfg['src']))

if __name__ == '__main__':
    main()
