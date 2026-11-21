# 只留下 GLB 里名字以给定前缀开头的节点（连同它们用到的网格、材质、贴图、采样器），其余删掉，重写成一个新的 GLB。
# 用法（仓库根目录）：python3 -I tools/scenery/keep_only.py <输入.glb> <输出.glb> <节点名前缀> [前缀 ...]
#   2026-11-18 用户：地图上不要树（草用 Roblox 地形自带的）——游戏只摆石头（Scenery.lua 的 LAYERS = { "rock" }），
#   models/scenery/scenery.glb 只留石头，导入后 Workspace 里不再冒出一堆用不上的树、草丛、花丛：
#     python3 -I tools/scenery/keep_only.py models/scenery/scenery.glb models/scenery/scenery.glb N_rock
#   元数据 SceneryMeta.lua 不用改（游戏按键名 N_<键>__<块> 认，导入了哪几种就用哪几种）。
import json
import struct
import sys


def read_glb(path):
    data = open(path, 'rb').read()
    magic, _, total = struct.unpack('<4sII', data[:12])
    if magic != b'glTF':
        raise SystemExit(f'{path} 不是 GLB')
    off, doc, binc = 12, None, b''
    while off < total:
        clen, ctype = struct.unpack('<I4s', data[off:off + 8])
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b'JSON':
            doc = json.loads(chunk)
        elif ctype == b'BIN\x00':
            binc = chunk
        off += 8 + clen
    return doc, binc


def write_glb(path, doc, binc):
    js = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    js += b' ' * ((4 - len(js) % 4) % 4)
    binc += b'\x00' * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(js) + (8 + len(binc) if binc else 0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, total))
        f.write(struct.pack('<I4s', len(js), b'JSON'))
        f.write(js)
        if binc:
            f.write(struct.pack('<I4s', len(binc), b'BIN\x00'))
            f.write(binc)


class Remap:
    def __init__(self):
        self.new = {}
        self.order = []

    def add(self, i):
        if i is None:
            return None
        if i not in self.new:
            self.new[i] = len(self.order)
            self.order.append(i)
        return self.new[i]


def tex_refs(mat):
    refs = []
    pbr = mat.get('pbrMetallicRoughness', {})
    for holder, key in ((pbr, 'baseColorTexture'), (pbr, 'metallicRoughnessTexture'), (mat, 'normalTexture'),
                        (mat, 'occlusionTexture'), (mat, 'emissiveTexture')):
        if key in holder:
            refs.append(holder[key])
    return refs


def main():
    src, dst, prefixes = sys.argv[1], sys.argv[2], sys.argv[3:]
    if not prefixes:
        raise SystemExit('要给至少一个节点名前缀')
    doc, binc = read_glb(src)
    for key in ('skins', 'animations', 'cameras'):
        if doc.get(key):
            raise SystemExit(f'不支持带 {key} 的 GLB')

    keep = []

    def take(i):
        keep.append(i)
        for c in doc['nodes'][i].get('children', []):
            take(c)

    child = {c for n in doc['nodes'] for c in n.get('children', [])}
    for i, n in enumerate(doc['nodes']):
        if i not in child and any(n.get('name', '').startswith(p) for p in prefixes):
            take(i)
    if not keep:
        raise SystemExit('没有节点名以这些前缀开头：' + ' '.join(prefixes))

    nodes, meshes, accs, mats, texs, imgs, samps, views = (Remap() for _ in range(8))
    for i in keep:
        nodes.add(i)
    new_nodes = []
    for i in nodes.order:
        n = dict(doc['nodes'][i])
        if 'children' in n:
            n['children'] = [nodes.new[c] for c in n['children']]
        if 'mesh' in n:
            n['mesh'] = meshes.add(n['mesh'])
        new_nodes.append(n)

    new_meshes = []
    for mi in meshes.order:
        m = json.loads(json.dumps(doc['meshes'][mi]))
        for p in m['primitives']:
            p['attributes'] = {k: accs.add(v) for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = accs.add(p['indices'])
            if 'material' in p:
                p['material'] = mats.add(p['material'])
            if 'targets' in p:
                p['targets'] = [{k: accs.add(v) for k, v in t.items()} for t in p['targets']]
        new_meshes.append(m)

    new_mats = []
    for mi in mats.order:
        m = json.loads(json.dumps(doc['materials'][mi]))
        for ref in tex_refs(m):
            ref['index'] = texs.add(ref['index'])
        new_mats.append(m)

    new_texs = []
    for ti in texs.order:
        t = dict(doc['textures'][ti])
        if 'source' in t:
            t['source'] = imgs.add(t['source'])
        if 'sampler' in t:
            t['sampler'] = samps.add(t['sampler'])
        new_texs.append(t)

    new_accs = []
    for ai in accs.order:
        a = json.loads(json.dumps(doc['accessors'][ai]))
        if 'bufferView' in a:
            a['bufferView'] = views.add(a['bufferView'])
        if 'sparse' in a:
            a['sparse']['indices']['bufferView'] = views.add(a['sparse']['indices']['bufferView'])
            a['sparse']['values']['bufferView'] = views.add(a['sparse']['values']['bufferView'])
        new_accs.append(a)

    new_imgs = []
    for ii in imgs.order:
        im = dict(doc['images'][ii])
        if 'bufferView' in im:
            im['bufferView'] = views.add(im['bufferView'])
        new_imgs.append(im)

    out = bytearray()
    new_views = []
    for vi in views.order:
        v = dict(doc['bufferViews'][vi])
        if v.get('buffer', 0) != 0:
            raise SystemExit('只支持一个 buffer 的 GLB')
        start = v.get('byteOffset', 0)
        out += b'\x00' * ((4 - len(out) % 4) % 4)
        v['byteOffset'] = len(out)
        out += binc[start:start + v['byteLength']]
        new_views.append(v)

    res = {k: v for k, v in doc.items() if k not in ('nodes', 'meshes', 'accessors', 'materials', 'textures', 'images',
                                                     'samplers', 'bufferViews', 'buffers', 'scenes', 'scene')}
    res['scene'] = 0
    scene = dict((doc.get('scenes') or [{}])[doc.get('scene', 0)])
    scene['nodes'] = [nodes.new[i] for i in keep if i not in child]
    res['scenes'] = [scene]
    res['nodes'] = new_nodes
    res['meshes'] = new_meshes
    res['accessors'] = new_accs
    res['bufferViews'] = new_views
    res['buffers'] = [{'byteLength': len(out)}]
    if new_mats:
        res['materials'] = new_mats
    if new_texs:
        res['textures'] = new_texs
    if new_imgs:
        res['images'] = new_imgs
    if samps.order:
        res['samplers'] = [doc['samplers'][i] for i in samps.order]
    write_glb(dst, res, bytes(out))
    print(f'{src} → {dst}：留下 {len(new_nodes)} 个节点（{", ".join(n.get("name", "") for n in new_nodes)}），'
          f'{len(new_meshes)} 个网格、{len(new_mats)} 个材质、{len(new_imgs)} 张贴图，二进制 {len(out) / 1e6:.2f} MB')


if __name__ == '__main__':
    main()
