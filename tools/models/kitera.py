#!/usr/bin/env python3
# Roblox全面大战场——坦克上补贴的爆反砖（用户 11-19：99A 正面没有爆反可以贴一下，爆反要有做旧的痕迹）
#   来源：Sketchfab「Explosive reactive armour (ERA) Kontakt-1」，作者 evt22，CC-BY-4.0（https://sketchfab.com/3d-models/ec2dd35895704132a5c38a9bc938e718）
#   这里的改动：烘进节点变换，摆成 X 宽（长边）、Y 高、Z 朝外（光面朝外，法兰和螺栓贴着车身那一面），居中；
#     底色贴图做旧：整体暗一点、偏灰，低频的积灰斑、几十道浅色划痕、锈斑和往下淌的锈流（法线、金属度粗糙度贴图原样）
#   导出 models/veh/kitera.glb：一块 MeshPart 叫 V_kitera__Body_1（Imports.lua 收进 Imported.Veh.kitera；VehModels 每块砖克隆一个、按块的大小缩放）
#   用法：python3 -I tools/models/kitera.py <下载的 kontakt1.glb>
import io, json, os, struct, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.getcwd()
OUT = os.path.join(ROOT, 'models', 'veh', 'kitera.glb')


def load(fn):
    d = open(fn, 'rb').read()
    off, J, BIN = 12, None, b''
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        if ty == 0x4E4F534A:
            J = json.loads(d[off + 8:off + 8 + ln])
        elif ty == 0x004E4942:
            BIN = d[off + 8:off + 8 + ln]
        off += 8 + ln
    return J, BIN


def acc(J, BIN, i):
    a = J['accessors'][i]
    bv = J['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    ct = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a['componentType']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(BIN, dtype=ct, count=a['count'] * n, offset=o).reshape(a['count'], n).copy()


def node_mat(n):
    if 'matrix' in n:
        return np.array(n['matrix'], float).reshape(4, 4).T
    M = np.eye(4)
    if 'translation' in n:
        M[:3, 3] = n['translation']
    return M


def world_mats(J):
    out = {}
    def walk(i, P):
        M = P @ node_mat(J['nodes'][i])
        out[i] = M
        for c in J['nodes'][i].get('children', []):
            walk(c, M)
    for r in J['scenes'][J.get('scene', 0)]['nodes']:
        walk(r, np.eye(4))
    return out


def image(J, BIN, idx):
    tex = J['textures'][idx]
    im = J['images'][tex['source']]
    bv = J['bufferViews'][im['bufferView']]
    o = bv.get('byteOffset', 0)
    return Image.open(io.BytesIO(BIN[o:o + bv['byteLength']])).convert('RGB')


def weather(img, seed=7):
    """做旧：整体压暗偏灰、低频积灰、浅色划痕、锈斑和锈流"""
    rng = np.random.default_rng(seed)
    w, h = img.size
    a = np.asarray(img, dtype=np.float32) / 255
    gray = a.mean(2, keepdims=True)
    a = a * 0.86 + gray * 0.14            # 褪色：饱和度降一点
    a *= 0.92
    # 积灰：两层不同大小的模糊噪声，往土黄色上拉
    def blob(scale, k):
        n = rng.random((max(2, h // scale), max(2, w // scale))).astype(np.float32)
        n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(scale * 0.35)), np.float32) / 255
        return np.clip((n - 0.45) * k, 0, 1)[..., None]
    dust = np.clip(blob(48, 2.2) * 0.55 + blob(12, 1.6) * 0.25, 0, 0.6)
    a = a * (1 - dust) + np.array([0.46, 0.40, 0.30]) * dust
    # 锈斑：稀疏的小斑，往下淌一道（贴图里 V 往下）
    rust = np.zeros((h, w), np.float32)
    im = Image.new('L', (w, h), 0)
    dr = ImageDraw.Draw(im)
    for _ in range(26):
        x, y = rng.integers(0, w), rng.integers(0, h)
        r = int(rng.integers(3, 11))
        dr.ellipse([x - r, y - r, x + r, y + r], fill=int(rng.integers(140, 230)))
        ln = int(rng.integers(20, 90))
        dr.line([x, y, x + int(rng.integers(-4, 5)), y + ln], fill=int(rng.integers(60, 140)), width=max(1, r // 3))
    rust = np.asarray(im.filter(ImageFilter.GaussianBlur(2.2)), np.float32)[..., None] / 255
    a = a * (1 - rust * 0.75) + np.array([0.42, 0.20, 0.08]) * rust * 0.75
    # 划痕：几十道细的浅色线（掉漆露出底下的钢）
    sc = Image.new('L', (w, h), 0)
    ds = ImageDraw.Draw(sc)
    for _ in range(70):
        x, y = rng.integers(0, w), rng.integers(0, h)
        ang = rng.uniform(0, np.pi)
        ln = rng.uniform(10, 60)
        ds.line([x, y, x + np.cos(ang) * ln, y + np.sin(ang) * ln], fill=int(rng.integers(90, 200)), width=1)
    scr = np.asarray(sc.filter(ImageFilter.GaussianBlur(0.6)), np.float32)[..., None] / 255
    a = a * (1 - scr * 0.6) + np.array([0.62, 0.62, 0.58]) * scr * 0.6
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def main(src):
    J, BIN = load(src)
    W = world_mats(J)
    ni = next(i for i, n in enumerate(J['nodes']) if 'mesh' in n)
    M = W[ni]
    prim = J['meshes'][J['nodes'][ni]['mesh']]['primitives'][0]
    P = acc(J, BIN, prim['attributes']['POSITION']).astype(float)
    N = acc(J, BIN, prim['attributes']['NORMAL']).astype(float)
    T = acc(J, BIN, prim['attributes']['TANGENT']).astype(float) if 'TANGENT' in prim['attributes'] else None
    UV = acc(J, BIN, prim['attributes']['TEXCOORD_0']).astype(np.float32)
    I = acc(J, BIN, prim['indices']).reshape(-1).astype(np.uint32)
    R = M[:3, :3]
    Pw = (R @ P.T).T + M[:3, 3]
    Rn = np.linalg.inv(R).T
    Nw = (Rn @ N.T).T
    Nw /= np.linalg.norm(Nw, axis=1, keepdims=True)
    # 世界（Y 朝上）→ 砖的坐标：X 长边、Y = −世界 Z、Z = 世界 Y（光面朝上的那一面朝外）
    A = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float)
    Pb = (A @ Pw.T).T
    Nb = (A @ Nw.T).T
    Pb -= (Pb.min(0) + Pb.max(0)) / 2
    lo, hi = Pb.min(0), Pb.max(0)
    print('砖的大小（米）', np.round(hi - lo, 3))
    Tb = None
    if T is not None:
        Tw = (R @ T[:, :3].T).T
        Tw /= np.linalg.norm(Tw, axis=1, keepdims=True) + 1e-9
        Tb = np.concatenate([(A @ Tw.T).T, T[:, 3:4]], 1).astype(np.float32)
    mat = J['materials'][prim['material']]
    pbr = mat.get('pbrMetallicRoughness', {})
    base = weather(image(J, BIN, pbr['baseColorTexture']['index']))
    imgs = [('base', base, 'image/jpeg')]
    if 'normalTexture' in mat:
        imgs.append(('normal', image(J, BIN, mat['normalTexture']['index']), 'image/png'))
    if 'metallicRoughnessTexture' in pbr:
        imgs.append(('orm', image(J, BIN, pbr['metallicRoughnessTexture']['index']), 'image/png'))
    # 写 GLB
    bufs, views, accs = [], [], []
    def add_buf(b, target=None):
        off = sum(len(x) for x in bufs)
        pad = (4 - off % 4) % 4
        if pad:
            bufs.append(b'\0' * pad)
            off += pad
        bufs.append(b)
        v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(b)}
        if target:
            v['target'] = target
        views.append(v)
        return len(views) - 1
    def add_acc(arr, ctype, typ, target, minmax=False):
        bv = add_buf(arr.tobytes(), target)
        a = {'bufferView': bv, 'componentType': ctype, 'count': int(arr.shape[0]) if arr.ndim > 1 else int(arr.size), 'type': typ}
        if minmax:
            a['min'], a['max'] = arr.min(0).tolist(), arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1
    attrs = {'POSITION': add_acc(Pb.astype(np.float32), 5126, 'VEC3', 34962, True),
             'NORMAL': add_acc(Nb.astype(np.float32), 5126, 'VEC3', 34962),
             'TEXCOORD_0': add_acc(UV, 5126, 'VEC2', 34962)}
    if Tb is not None:
        attrs['TANGENT'] = add_acc(Tb, 5126, 'VEC4', 34962)
    ind = add_acc(I, 5125, 'SCALAR', 34963)
    images, textures = [], []
    for nm, im, mime in imgs:
        b = io.BytesIO()
        im.save(b, 'JPEG' if mime == 'image/jpeg' else 'PNG', quality=90)
        images.append({'name': nm, 'mimeType': mime, 'bufferView': add_buf(b.getvalue())})
        textures.append({'source': len(images) - 1})
    m2 = {'name': 'V_kitera_Body', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 1, 'roughnessFactor': 1}}
    ti = 1
    if any(n == 'normal' for n, _, _ in imgs):
        m2['normalTexture'] = {'index': ti}
        ti += 1
    if any(n == 'orm' for n, _, _ in imgs):
        m2['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': ti}
    G = {'asset': {'version': '2.0', 'generator': 'kitera.py'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
         'nodes': [{'name': 'V_kitera__Body_1', 'mesh': 0}],
         'meshes': [{'name': 'V_kitera__Body_1', 'primitives': [{'attributes': attrs, 'indices': ind, 'material': 0}]}],
         'materials': [m2], 'images': images, 'textures': textures, 'samplers': [{}],
         'bufferViews': views, 'accessors': accs, 'buffers': [{'byteLength': sum(len(x) for x in bufs)}]}
    for t in G['textures']:
        t['sampler'] = 0
    binb = b''.join(bufs)
    binb += b'\0' * ((4 - len(binb) % 4) % 4)
    js = json.dumps(G).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(binb), 0x004E4942) + binb
    open(OUT, 'wb').write(out)
    base.save(os.path.join(os.path.dirname(src), 'kitera_base_preview.jpg'))
    print('写好了', OUT, len(out) // 1024, 'KB，三角形', len(I) // 3)


if __name__ == '__main__':
    main(sys.argv[1])
