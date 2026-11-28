#!/usr/bin/env python3
# Roblox全面大战场——导入的原模型每块零件的平均色：读 models/{veh,air,ship,optics,scenery}/*.glb 和 models/fps_m4.glb，
#   每个带网格的节点（导入后 MeshPart 就叫这个名字）按三角形面积在底色贴图上取样（三角形重心 + 三个顶点，按 UV 重复平铺），
#   乘材质底色，算成 sRGB 0–255，写进 src/ReplicatedStorage/ImportedTint.lua。
#   客户端（Tint.lua）在贴图没加载出来时（导入时上传失败、还在审核、被拒）用它给零件上色——不然整块是白的。
#   用法：python3 -I tools/models/tint.py（在仓库根目录跑；表里原有、这次没读到模型的条目留着，加 --fresh 从头生成）
import glob, json, os, re, struct, sys, io
import numpy as np
from PIL import Image

ROOT = os.getcwd()
OUT = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'ImportedTint.lua')

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def load(fn):
  data = open(fn, 'rb').read()
  off, js, binc = 12, None, b''
  while off < len(data):
    clen, ctype = struct.unpack_from('<II', data, off)
    if ctype == 0x4E4F534A:
      js = json.loads(data[off + 8:off + 8 + clen])
    elif ctype == 0x004E4942:
      binc = data[off + 8:off + 8 + clen]
    off += 8 + clen
  return js, binc


def accessor(js, binc, i):
  a = js['accessors'][i]
  bv = js['bufferViews'][a['bufferView']]
  dt = np.dtype(CT[a['componentType']])
  n, k = a['count'], NC[a['type']]
  base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
  stride = bv.get('byteStride', 0) or dt.itemsize * k
  if stride == dt.itemsize * k:
    arr = np.frombuffer(binc, dtype=dt, count=n * k, offset=base).reshape(n, k)
  else:
    raw = np.frombuffer(binc, dtype=np.uint8, count=stride * (n - 1) + dt.itemsize * k, offset=base)
    arr = np.lib.stride_tricks.as_strided(raw, shape=(n, dt.itemsize * k), strides=(stride, 1)).copy().view(dt).reshape(n, k)
  arr = arr.astype(np.float64)
  if a.get('normalized'):
    arr /= float(np.iinfo(dt).max)
  return arr


def srgb2lin(c):
  return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin2srgb(c):
  c = np.clip(c, 0, 1)
  return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def image_lin(js, binc, tex_index, cache):
  if tex_index in cache:
    return cache[tex_index]
  t = js['textures'][tex_index]
  src = t.get('source')
  img = None
  if src is not None:
    im = js['images'][src]
    if 'bufferView' in im:
      bv = js['bufferViews'][im['bufferView']]
      b = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
      pil = Image.open(io.BytesIO(b)).convert('RGBA')
      if max(pil.size) > 512:   # 取平均色用不着全分辨率
        pil.thumbnail((512, 512), Image.BILINEAR)
      a = np.asarray(pil).astype(np.float64) / 255.0
      img = np.concatenate([srgb2lin(a[..., :3]), a[..., 3:4]], axis=2)
  cache[tex_index] = img
  return img


def node_tint(js, binc, mesh, cache):
  acc = np.zeros(3)
  wsum = 0.0
  for p in mesh['primitives']:
    if p.get('mode', 4) != 4 or 'POSITION' not in p['attributes']:
      continue
    pos = accessor(js, binc, p['attributes']['POSITION'])
    if 'indices' in p:
      idx = accessor(js, binc, p['indices']).astype(np.int64).reshape(-1, 3)
    else:
      idx = np.arange(len(pos)).reshape(-1, 3)
    if len(idx) == 0:
      continue
    a, b, c = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    mat = js['materials'][p['material']] if p.get('material') is not None else {}
    pbr = mat.get('pbrMetallicRoughness', {})
    fac = np.array(pbr.get('baseColorFactor', [1, 1, 1, 1])[:3], dtype=np.float64)
    col = np.tile(fac, (len(idx), 1))
    wt = area.copy()
    bt = pbr.get('baseColorTexture')
    img = image_lin(js, binc, bt['index'], cache) if bt else None
    uvk = 'TEXCOORD_%d' % (bt.get('texCoord', 0) if bt else 0)
    if img is not None and uvk in p['attributes']:
      uv = accessor(js, binc, p['attributes'][uvk])
      h, w = img.shape[:2]
      ua, ub, uc = uv[idx[:, 0]], uv[idx[:, 1]], uv[idx[:, 2]]
      sc, sa = np.zeros((len(idx), 3)), np.zeros((len(idx), 1))
      for q in (ua, ub, uc, (ua + ub + uc) / 3):   # 三个顶点 + 重心
        x = np.floor(np.mod(q[:, 0], 1.0) * w).astype(np.int64) % w
        y = np.floor(np.mod(q[:, 1], 1.0) * h).astype(np.int64) % h
        px = img[y, x]
        sc += px[:, :3] * px[:, 3:4]   # 透明的地方（贴花、镂空）不算：按不透明度加权
        sa += px[:, 3:4]
      col = col * (sc / np.maximum(sa, 1e-6))
      wt = wt * (sa[:, 0] / 4)
    acc += (col * wt[:, None]).sum(axis=0)
    wsum += wt.sum()
  if wsum <= 0:
    return None
  s = lin2srgb(acc / wsum)
  return [int(round(v * 255)) for v in s]


def main():
  files = []
  for d in ('veh', 'air', 'ship', 'optics', 'scenery'):
    files += sorted(glob.glob(os.path.join(ROOT, 'models', d, '*.glb')))
  if os.path.exists(os.path.join(ROOT, 'models', 'fps_m4.glb')):
    files.append(os.path.join(ROOT, 'models', 'fps_m4.glb'))
  # 表里原有的条目先留着：有些老模型（导入过、后来不在 models/ 里了）的零件色只在表里有，整表重写会把它们丢掉；
  #   这次读到的模型照样覆盖成新算的颜色。要从头生成（丢掉没模型的老条目）加 --fresh
  out = {}
  kept = 0
  if '--fresh' not in sys.argv[1:] and os.path.exists(OUT):
    for m in re.finditer(r'^  \["(.+?)"\] = \{ (\d+), (\d+), (\d+) \},$', open(OUT, encoding='utf-8').read(), re.M):
      out[m.group(1)] = [int(m.group(2)), int(m.group(3)), int(m.group(4))]
    kept = len(out)
  for fn in files:
    js, binc = load(fn)
    cache = {}
    n = 0
    for node in js.get('nodes', []):
      if 'mesh' not in node or not node.get('name'):
        continue
      t = node_tint(js, binc, js['meshes'][node['mesh']], cache)
      if t:
        out[node['name']] = t
        n += 1
    print('%-14s %3d 块' % (os.path.relpath(fn, os.path.join(ROOT, 'models')), n))
  lines = [
    '-- 自动生成（tools/models/tint.py），别手改：导入的原模型每块零件（MeshPart 的名字）的平均色——底色贴图按三角形面积取样 × 材质底色，sRGB 0–255',
    '--   贴图没加载出来（导入时上传失败、还在审核、被拒）或者导入时没带上材质颜色的，客户端 Tint.lua 用它上色，免得整块是白的',
    'return {',
  ]
  for k in sorted(out):
    r, g, b = out[k]
    lines.append('  ["%s"] = { %d, %d, %d },' % (k, r, g, b))
  lines.append('}')
  open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
  print('写好了 %s：%d 块（原表 %d 块）' % (os.path.relpath(OUT, ROOT), len(out), kept))


if __name__ == '__main__':
  main()
