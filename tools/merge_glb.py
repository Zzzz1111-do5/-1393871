# 把 models/ 下各兵种的 GLB 合成一个 all_units.glb：Studio 里「导入 3D」导一次就全进去了。
# 每个零件改名成「兵种名__原名」（比如 tank__Turret_1、heli___PivotRotor），导入后不管 Studio 保不保留层级，游戏都能按名字前缀分回各个兵种；
# 每个兵种挂在一个同名的空节点下，并排摆开（Studio 里看着不重叠）。只改节点名和摆放，网格、贴图原样不动。
# 用法：python3 tools/merge_glb.py [models 目录] [输出文件]
import sys, os, json, struct

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'models')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(src, 'all_units.glb')
names = sorted(f[:-4] for f in os.listdir(src) if f.endswith('.glb') and f != os.path.basename(out))

def load(path):
    b = open(path, 'rb').read()
    magic, ver, total = struct.unpack_from('<III', b, 0)
    assert magic == 0x46546C67, path
    off, j, binc = 12, None, b''
    while off < total:
        clen, ctype = struct.unpack_from('<II', b, off)
        data = b[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A: j = json.loads(data)
        elif ctype == 0x004E4942: binc = data
        off += 8 + clen
    return j, binc

M = {'asset': {'version': '2.0', 'generator': 'military-tycoon merge_glb.py'}, 'scene': 0, 'scenes': [{'name': 'MilitaryTycoonUnits', 'nodes': []}],
     'nodes': [], 'meshes': [], 'accessors': [], 'bufferViews': [], 'materials': [], 'textures': [], 'images': [], 'samplers': []}
blob = bytearray()
used_ext = set()
cols = 6
for i, name in enumerate(names):
    j, binc = load(os.path.join(src, name + '.glb'))
    assert len(j.get('buffers', [])) <= 1, name
    while len(blob) % 8: blob.append(0)
    boff = len(blob)
    blob += binc
    o = {k: len(M[k]) for k in ('nodes', 'meshes', 'accessors', 'bufferViews', 'materials', 'textures', 'images', 'samplers')}
    for bv in j.get('bufferViews', []):
        bv = dict(bv)
        bv['buffer'] = 0
        bv['byteOffset'] = bv.get('byteOffset', 0) + boff
        M['bufferViews'].append(bv)
    for a in j.get('accessors', []):
        a = dict(a)
        if 'bufferView' in a: a['bufferView'] += o['bufferViews']
        if 'sparse' in a: raise SystemExit('不支持 sparse accessor：' + name)
        M['accessors'].append(a)
    for im in j.get('images', []):
        im = dict(im)
        if 'bufferView' in im: im['bufferView'] += o['bufferViews']
        M['images'].append(im)
    for s in j.get('samplers', []): M['samplers'].append(dict(s))
    for t in j.get('textures', []):
        t = dict(t)
        if 'source' in t: t['source'] += o['images']
        if 'sampler' in t: t['sampler'] += o['samplers']
        M['textures'].append(t)
    def fix_tex(d):
        if isinstance(d, dict):
            for k, v in d.items():
                if k.endswith('Texture') and isinstance(v, dict) and 'index' in v: v['index'] += o['textures']
                else: fix_tex(v)
    for m in j.get('materials', []):
        m = json.loads(json.dumps(m))
        fix_tex(m)
        M['materials'].append(m)
    for me in j.get('meshes', []):
        me = json.loads(json.dumps(me))
        for p in me['primitives']:
            p['attributes'] = {k: v + o['accessors'] for k, v in p['attributes'].items()}
            if 'indices' in p: p['indices'] += o['accessors']
            if 'material' in p: p['material'] += o['materials']
            if 'targets' in p: p['targets'] = [{k: v + o['accessors'] for k, v in t.items()} for t in p['targets']]
        M['meshes'].append(me)
    for n in j.get('nodes', []):
        n = json.loads(json.dumps(n))
        if 'mesh' in n: n['mesh'] += o['meshes']
        if 'children' in n: n['children'] = [c + o['nodes'] for c in n['children']]
        n['name'] = name + '__' + n.get('name', 'Part')
        for k in ('skin', 'camera'): n.pop(k, None)
        M['nodes'].append(n)
    used_ext |= set(j.get('extensionsUsed', []))
    roots = [r + o['nodes'] for r in j['scenes'][j.get('scene', 0)]['nodes']]
    group = {'name': name, 'children': roots, 'translation': [(i % cols) * 40.0, 0.0, (i // cols) * 40.0]}
    M['nodes'].append(group)
    M['scenes'][0]['nodes'].append(len(M['nodes']) - 1)
for k in ('textures', 'images', 'samplers', 'materials'):
    if not M[k]: del M[k]
if used_ext: M['extensionsUsed'] = sorted(used_ext)
while len(blob) % 4: blob.append(0)
M['buffers'] = [{'byteLength': len(blob)}]
js = json.dumps(M, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
while len(js) % 4: js += b' '
total = 12 + 8 + len(js) + 8 + len(blob)
with open(out, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II', len(blob), 0x004E4942)); f.write(blob)
print(f'合并了 {len(names)} 个兵种 → {out}（{total / 1048576:.1f} MB，节点 {len(M["nodes"])}，网格 {len(M["meshes"])}）')
