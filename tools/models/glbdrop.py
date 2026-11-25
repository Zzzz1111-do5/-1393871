# 去掉 glb 上做成几何片的标志（名字、材质、别的零件、贴图一律不动）：
#   python3 -I tools/models/glbdrop.py <进.glb> <出.glb> <规则.json>
#   规则：[{"box": [x0, x1, y0, y1, z0, z1], "drop": ["A_nh90__Body_2", ...], "patch": "A_nh90__Body_3"}, ...]
#     坐标是 glb 里的世界坐标（零件节点的平移算进去）；drop 里各零件三个顶点都在盒子里（四周放宽 0.02）的三角形删掉；
#     patch：原模型的蒙皮在标志那里是挖空的（SketchUp 导出的，标志片补在洞里），光删会露出机舱里面——
#       在被删的那些面的平面上铺一块比它们大一圈（pad，默认 0.04 格）的细分平面补丁，加进 patch 那个零件（用它的材质、贴图）：
#       UV 按盒子四周 2 格以内的蒙皮顶点拟合「位置 → UV」的仿射映射（四周是平面投影的贴图时补丁和四周严丝合缝；
#       拟合不上就整块用离中心最近的蒙皮顶点的 UV，一个颜色），法线朝外，往外抬 lift（默认 0.006 格，约 2 毫米）免得和蒙皮打架
#   用处：用户 11-25 晚「把所有带着二战希特勒德军标识的符号全部去掉」（Roblox 审核把豹 2A6 贴图上的十字判违规、账号被警告）——
#     NH90 的四个十字（两侧、机腹、机顶，每个是一块黑芯 + 四块白角）：tools/models/insignia_nh90.json
import json, struct, sys
import numpy as np

src, dst, rules = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
b = open(src, 'rb').read()
n = 12; J = None; BIN = None
while n < len(b):
    ln, ty = struct.unpack('<II', b[n:n + 8]); ch = b[n + 8:n + 8 + ln]
    if ty == 0x4E4F534A: J = json.loads(ch)
    elif ty == 0x004E4942: BIN = ch
    n += 8 + ln
CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
views = [bytes(BIN[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]) for v in J['bufferViews']]


def read(ai):
    a = J['accessors'][ai]; v = J['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']]); nc = NC[a['type']]
    stride = v.get('byteStride', dt.itemsize * nc)
    raw = np.frombuffer(views[a['bufferView']], dtype=np.uint8)
    off = a.get('byteOffset', 0)
    out = np.empty((a['count'], nc), dtype=dt)
    for i in range(nc):
        idx = off + np.arange(a['count']) * stride + i * dt.itemsize
        out[:, i] = np.frombuffer(np.stack([raw[idx + k] for k in range(dt.itemsize)], 1).tobytes(), dtype=dt)
    return out


def write(ai, arr, minmax=False):
    a = J['accessors'][ai]
    assert a.get('byteOffset', 0) == 0 and sum(1 for x in J['accessors'] if x.get('bufferView') == a['bufferView']) == 1, '访问器和别的共用缓冲区，不敢改'
    views[a['bufferView']] = np.ascontiguousarray(arr.astype(CT[a['componentType']])).tobytes()
    J['bufferViews'][a['bufferView']].pop('byteStride', None)
    a['count'] = int(arr.shape[0])
    if minmax:
        a['min'] = [float(x) for x in arr.min(0)]; a['max'] = [float(x) for x in arr.max(0)]


def node(name):
    nd = next(x for x in J['nodes'] if x.get('name') == name)
    assert 'rotation' not in nd and 'scale' not in nd and 'matrix' not in nd, '只认平移'
    return nd, np.array(nd.get('translation', [0, 0, 0]), dtype=np.float64)


total = 0
for r in rules:
    bx = r['box']; e = 0.02
    lo = np.array([bx[0], bx[2], bx[4]]) - e; hi = np.array([bx[1], bx[3], bx[5]]) + e
    gone_p, gone_n = [], []
    for nm in r['drop']:
        nd, t = node(nm)
        for p in J['meshes'][nd['mesh']]['primitives']:
            assert p.get('mode', 4) == 4
            pos = read(p['attributes']['POSITION']).astype(np.float64) + t
            nor = read(p['attributes']['NORMAL']).astype(np.float64)
            idx = read(p['indices'])[:, 0].astype(np.int64).reshape(-1, 3)
            kill = np.all((pos >= lo) & (pos <= hi), axis=1)[idx].all(axis=1)
            if not kill.any(): continue
            used = np.unique(idx[kill])
            gone_p.append(pos[used]); gone_n.append(nor[used])
            write(p['indices'], idx[~kill].reshape(-1))
            total += int(kill.sum())
            print('%s：盒子 %s 删掉 %d 个三角形' % (nm, bx, int(kill.sum())))
    if not r.get('patch') or not gone_p: continue
    P = np.vstack(gone_p); Nn = np.vstack(gone_n)
    c = P.mean(0)
    # 平面：被删的点做主成分，最小的那个方向是法线；按原来那些面的法线定朝外
    _, _, vt = np.linalg.svd(P - c)
    nrm = vt[2] * (1 if vt[2] @ Nn.mean(0) > 0 else -1)
    ua, va = vt[0], vt[1]
    pu, pv = (P - c) @ ua, (P - c) @ va
    pad = float(r.get('pad', 0.04)); lift = float(r.get('lift', 0.006)); g = int(r.get('grid', 6))
    us = np.linspace(pu.min() - pad, pu.max() + pad, g + 1); vs = np.linspace(pv.min() - pad, pv.max() + pad, g + 1)
    grid = np.array([c + a * ua + bb * va for bb in vs for a in us])   # 先在原平面上（算 UV 用）
    tn, tt = node(r['patch'])
    tp = J['meshes'][tn['mesh']]['primitives'][0]
    tpos = read(tp['attributes']['POSITION']).astype(np.float64)
    tnor = read(tp['attributes']['NORMAL']).astype(np.float64)
    tuv = read(tp['attributes']['TEXCOORD_0']).astype(np.float64)
    tidx = read(tp['indices'])[:, 0].astype(np.int64)
    w = tpos + tt
    near = (np.linalg.norm(w - c, axis=1) < 2.0) & ~np.all((w >= lo) & (w <= hi), axis=1)
    A = np.c_[w[near], np.ones(int(near.sum()))]
    M = np.linalg.lstsq(A, tuv[near], rcond=None)[0]
    err = float(np.abs(A @ M - tuv[near]).max()) if near.any() else 1e9
    if err < 0.01:
        guv = np.c_[grid, np.ones(len(grid))] @ M
    else:   # 四周的 UV 不是平面投影（平铺的、分了好几块的）：整块一个颜色
        k = int(np.argmin(np.linalg.norm(w - c, axis=1)))
        guv = np.repeat(tuv[k:k + 1], len(grid), axis=0)
    gpos = grid + nrm * lift
    gnor = np.repeat(nrm[None, :], len(grid), axis=0)
    base = tpos.shape[0]
    tri = []
    for j in range(g):
        for i in range(g):
            a0 = base + j * (g + 1) + i; a1 = a0 + 1; a2 = a0 + (g + 1); a3 = a2 + 1
            tri += [(a0, a1, a3), (a0, a3, a2)]
    tri = np.array(tri, dtype=np.int64)
    # 绕向朝外
    q = np.vstack([gpos])[tri[0] - base]
    if np.cross(q[1] - q[0], q[2] - q[0]) @ nrm < 0: tri = tri[:, [0, 2, 1]]
    write(tp['attributes']['POSITION'], np.vstack([tpos, gpos - tt]), True)
    write(tp['attributes']['NORMAL'], np.vstack([tnor, gnor]))
    write(tp['attributes']['TEXCOORD_0'], np.vstack([tuv, guv]))
    allidx = np.concatenate([tidx, tri.reshape(-1)])
    ta = J['accessors'][tp['indices']]
    if allidx.max() > 65535 and ta['componentType'] != 5125: ta['componentType'] = 5125
    write(tp['indices'], allidx)
    print('  补丁 → %s：%d×%d 格、%.2f×%.2f 格大，UV %s' % (r['patch'], g, g, us[-1] - us[0], vs[-1] - vs[0],
          ('接四周投影（%d 个蒙皮顶点，误差 %.4f）' % (int(near.sum()), err)) if err < 0.01 else '整块一个颜色'))

out = bytearray()
for i, bv in enumerate(J['bufferViews']):
    while len(out) % 4: out.append(0)
    bv['byteOffset'] = len(out); bv['byteLength'] = len(views[i])
    out += views[i]
while len(out) % 4: out.append(0)
J['buffers'][0]['byteLength'] = len(out)
js = json.dumps(J, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
while len(js) % 4: js += b' '
o = bytearray(b'glTF') + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(out))
o += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(out), 0x004E4942) + out
open(dst, 'wb').write(o)
print('写好 %s：一共删掉 %d 个三角形' % (dst, total))
