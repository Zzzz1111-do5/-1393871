# 原模型自带关键帧动画的飞机（用户给的 NLM「F22 Raptor FREE」：一段 25 秒的动画——放起落架、开关侧弹舱、摆一遍舵面）→ 游戏里的活动部件
#   python3 -I tools/models/air_kf.py <模型键> <原 GLB> <输出目录>
#     → <输出目录>/<模型键>.glb：给烘焙用（网页版 tools/v3gbake.js，模型配置的 glb 指向它）。会动的部件和机体（或别的部件）共用的顶点
#         往部件里挪 1.5 毫米：烘焙按位置焊接连通块、按连通块分部件，共用一个顶点就和整架机体并成一块了
#       tools/models/kf/<模型键>.json：活动部件表（网页版烘焙后的坐标：x 前、y 左、z 上，米），air2glb.py 读
#     打印烘焙配置要写的 parts、dropNodes（照 SPEC）
#   部件两种：
#     kf  关键帧部件（起落架、起落架舱门、侧弹舱门和发射架）：支点 p（节点不动时的原点）、关键帧 key（每帧 [dx, dy, dz, qx, qy, qz, qw]：
#         绕支点转 q、支点挪 d），ch 跟哪个操纵量（gear：0 收起～1 放下；bayS：0 关～1 开），在动画的时间窗口里等间隔取 K 帧
#     铰链（舵面、座舱盖）：和 air_anim.py 切出来的一样（k 动法、s 侧、a / b 铰链两端、sg 正方向）；舵面的转轴、支点照动画，座舱盖按外形定
import json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import air_anim as A   # noqa: E402  probe_sign、方向常数

KFDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kf')

# 名字后面带 * 的按左右加 L / R（原模型 x > 0 是左边）
SPEC = {
    'f22a': {
        'fwd': '+z', 'up': '+y', 'len': 18.92,
        # 登机梯（动画里从机旁 10 米外移过来的道具）、侧弹舱发射架上自带的两枚 AIM-9（游戏按实际挂载另画）
        'drop': ['Circle_47', 'Cube.067_75', 'Cube.070_77'],
        'win': {'gear': [0.0, 7.6], 'bayS': [7.5, 11.6]},   # 0～7.6 秒放起落架（先开前面的舱门再放支柱）；7.5～11.6 秒开侧弹舱、发射架伸出
        'K': 20,
        'kf': {
            'Empty.003_12': ('GearN', 'gear'), 'Empty.004_16': ('GearN2', 'gear'), 'Empty.005_18': ('GearN3', 'gear'),
            'Cylinder.013_25': ('Gear*', 'gear'), 'Cylinder.018_31': ('Gear*', 'gear'),
            'Cube.048_91': ('GDoorN*', 'gear'), 'Cube.049_92': ('GDoorN*', 'gear'),
            'Cube.055_27': ('GDoor1*', 'gear'), 'Cube.059_32': ('GDoor1*', 'gear'),
            'Cube.056_28': ('GDoor2*', 'gear'), 'Cube.060_33': ('GDoor2*', 'gear'),
            'Cube.051_70': ('GDoor3*', 'gear'), 'Cube.016_68': ('GDoor3*', 'gear'),
            'Cube.052_71': ('GDoor4*', 'gear'), 'Cube.050_69': ('GDoor4*', 'gear'),
            'Cube.061_89': ('BayS1*', 'bayS'), 'Cube.064_83': ('BayS1*', 'bayS'),
            'Cube.062_90': ('BayS2*', 'bayS'), 'Cube.058_88': ('BayS2*', 'bayS'),
            'Cube.068_76': ('BayS3*', 'bayS'), 'Cube.069_78': ('BayS3*', 'bayS'),
        },
        'hinge': {
            'Empty.008_37': ('Rud*', 'rud'), 'Empty.007_35': ('Rud*', 'rud'),
            'Empty.009_39': ('Flp*', 'flaperon'), 'Empty.011_43': ('Flp*', 'flaperon'),
            'Empty.010_41': ('Ail*', 'ail'), 'Empty.012_45': ('Ail*', 'ail'),
            'Cube.043_66': ('Stab*', 'stab'), 'Cube.044_79': ('Stab*', 'stab'),
        },
        'hwin': [15.0, 25.0],   # 摆舵面那一段：找偏得最多的一刻量转轴
        'canopy': {'node': 'Empty.006_21', 'name': 'Canopy', 'A': 0.7},   # 一整块蚌壳式座舱盖，后端铰链往上掀
        # 主弹舱门：不在动画里，是机体网格里左右两块单独的门板（烘焙配置按位置挑：box、zmax），铰链在外侧边，往下翻开
        'bays': {'BayML': {'k': 'bay', 'A': 1.6}, 'BayMR': {'k': 'bay', 'A': 1.6}},
    },
}

AXV = {'+x': [1, 0, 0], '-x': [-1, 0, 0], '+y': [0, 1, 0], '-y': [0, -1, 0], '+z': [0, 0, 1], '-z': [0, 0, -1]}
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF', path
    off, J, BIN = 12, None, None
    while off < len(b):
        ln, ty = struct.unpack('<II', b[off:off + 8])
        ch = b[off + 8:off + 8 + ln]
        if ty == 0x4E4F534A:
            J = json.loads(ch)
        elif ty == 0x004E4942:
            BIN = bytearray(ch)
        off += 8 + ln
    return J, BIN


def write_glb(path, J, BIN):
    js = json.dumps(J, separators=(',', ':')).encode('utf-8')
    js += b' ' * ((4 - len(js) % 4) % 4)
    bn = bytes(BIN) + b'\0' * ((4 - len(BIN) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bn)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(bn), 0x004E4942) + bn)


class G:
    """glTF 场景：节点矩阵、动画采样、网格顶点"""

    def __init__(self, J, BIN):
        self.J, self.BIN = J, BIN
        self.par = {}
        for i, n in enumerate(J['nodes']):
            for c in n.get('children', []):
                self.par[c] = i
        self.byname = {n.get('name'): i for i, n in enumerate(J['nodes'])}
        self.ch = {}   # 节点 → {path: (时间, 值)}
        for Anim in J.get('animations', []):
            for c in Anim['channels']:
                sm = Anim['samplers'][c['sampler']]
                self.ch.setdefault(c['target']['node'], {})[c['target']['path']] = (self.acc(sm['input']).ravel(), self.acc(sm['output']))

    def acc(self, i):
        a = self.J['accessors'][i]
        bv = self.J['bufferViews'][a['bufferView']]
        dt, n = CT[a['componentType']], NC[a['type']]
        o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        st = bv.get('byteStride', 0)
        isz = np.dtype(dt).itemsize * n
        if st and st != isz:
            arr = np.stack([np.frombuffer(self.BIN, dt, count=n, offset=o + k * st) for k in range(a['count'])])
        else:
            arr = np.frombuffer(self.BIN, dt, count=a['count'] * n, offset=o).reshape(a['count'], n)
        arr = arr.astype(np.float64)
        if a.get('normalized'):
            arr = arr / np.iinfo(dt).max
        return arr

    def trs(self, i, t=None):
        n = self.J['nodes'][i]
        if 'matrix' in n:
            return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
        T = np.array(n.get('translation', [0, 0, 0]), dtype=np.float64)
        R = np.array(n.get('rotation', [0, 0, 0, 1]), dtype=np.float64)
        S = np.array(n.get('scale', [1, 1, 1]), dtype=np.float64)
        if t is not None and i in self.ch:
            for path, (tt, vv) in self.ch[i].items():
                v = np.array([np.interp(t, tt, vv[:, k]) for k in range(vv.shape[1])])
                if path == 'translation':
                    T = v
                elif path == 'rotation':
                    # 相邻关键帧的四元数线性插值再归一（帧很密，和球面插值差不出来）
                    k = int(np.clip(np.searchsorted(tt, t) - 1, 0, len(tt) - 2))
                    a, b = vv[k], vv[k + 1]
                    if a @ b < 0:
                        b = -b
                    f = 0.0 if tt[k + 1] <= tt[k] else float(np.clip((t - tt[k]) / (tt[k + 1] - tt[k]), 0, 1))
                    R = a * (1 - f) + b * f
                    R = R / np.linalg.norm(R)
                elif path == 'scale':
                    S = v
        M = np.eye(4)
        M[:3, :3] = qmat(R) @ np.diag(S)
        M[:3, 3] = T
        return M

    def world(self, i, t=None):
        M, k = np.eye(4), i
        while k is not None:
            M = self.trs(k, t) @ M
            k = self.par.get(k)
        return M

    def mesh_nodes(self, i):
        out, st = [], [i]
        while st:
            k = st.pop()
            if 'mesh' in self.J['nodes'][k]:
                out.append(k)
            st += self.J['nodes'][k].get('children', [])
        return out


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_q(R):
    """旋转矩阵 → 四元数 [x, y, z, w]（w ≥ 0）"""
    t = np.trace(R)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s, 0.25 * s]
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        q = [0.25 * s, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s, (R[2, 1] - R[1, 2]) / s]
    elif R[1, 1] > R[2, 2]:
        s = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        q = [(R[0, 1] + R[1, 0]) / s, 0.25 * s, (R[1, 2] + R[2, 1]) / s, (R[0, 2] - R[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        q = [(R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, 0.25 * s, (R[1, 0] - R[0, 1]) / s]
    q = np.array(q)
    q /= np.linalg.norm(q)
    return q if q[3] >= 0 else -q


def orthonorm(M):
    U, _, Vt = np.linalg.svd(M)
    R = U @ Vt
    if np.linalg.det(R) < 0:
        U[:, -1] *= -1
        R = U @ Vt
    return R


def prep(key, src, outdir):
    C = SPEC[key]
    J, BIN = read_glb(src)
    g = G(J, BIN)
    drop = set(g.byname[n] for n in C['drop'])
    fwd, up = np.array(AXV[C['fwd']], float), np.array(AXV[C['up']], float)
    Ax = np.stack([fwd, np.cross(up, fwd), up])   # 原模型世界坐标 → 网页版的轴（x 前、y 左、z 上）
    roots = J['scenes'][J.get('scene', 0)]['nodes']

    # 每个网格节点属于哪个部件：最近的、表里有的祖先（-1 机体）；去掉的节点（和子孙）不算
    groups = {}   # 部件根节点 → (名字底, 种类, 动法 / 操纵量)
    for nm, (base, ch) in C['kf'].items():
        groups[g.byname[nm]] = (base, 'kf', ch)
    for nm, (base, k) in C['hinge'].items():
        groups[g.byname[nm]] = (base, 'hinge', k)
    cn = C['canopy']
    groups[g.byname[cn['node']]] = (cn['name'], 'canopy', None)
    owner = {}

    def walk(i, gid, dead):
        dead = dead or i in drop
        if i in groups:
            gid = i
        if 'mesh' in J['nodes'][i]:
            owner[i] = None if dead else gid
        for c in J['nodes'][i].get('children', []):
            walk(c, gid, dead)
    for r in roots:
        walk(r, -1, False)

    # 世界坐标顶点（静止姿势，烘焙用的就是节点本身的 TRS）
    prims = []   # (节点, 图元, POSITION 访问器, 世界矩阵, 部件)
    for i, gid in owner.items():
        if gid is None:
            continue
        M = g.world(i)
        for pr in J['meshes'][J['nodes'][i]['mesh']]['primitives']:
            if pr.get('mode', 4) < 4:
                continue
            prims.append((i, pr, pr['attributes']['POSITION'], M, gid))
    use = {}
    for p in prims:
        use[p[2]] = use.get(p[2], 0) + 1
    shared = [a for a, n in use.items() if n > 1]
    if shared:
        print('  警告：%d 个 POSITION 访问器被几个图元共用（挪顶点会一起挪）' % len(shared))
    W = []
    for i, pr, ai, M, gid in prims:
        P = g.acc(ai)
        W.append(P @ M[:3, :3].T + M[:3, 3])
    # 烘焙的缩放、原点（同 v3gbake.js：活着的三角形的包围盒；长度方向缩到 len，前后左右居中，最低点为 0）
    allA = np.concatenate([w @ Ax.T for w in W])
    lo, hi = allA.min(0), allA.max(0)
    s = C['len'] / (hi[0] - lo[0])
    o = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])

    def web(p):   # 原模型世界坐标 → 网页版烘焙后的坐标
        return (np.asarray(p, float) @ Ax.T - o) * s

    # —— 挪开共用的顶点：1 毫米以内有别的部件（含机体）的顶点，往自己部件的中心挪 1.5 毫米 ——
    tol, mv = 1e-3 / s, 1.5e-3 / s
    cell = {}
    for pi, w in enumerate(W):
        q = np.floor(w / tol).astype(np.int64)
        for vi, k in enumerate(map(tuple, q)):
            cell.setdefault(k, []).append((pi, vi))
    cen = {}
    for pi, (i, pr, ai, M, gid) in enumerate(prims):
        cen.setdefault(gid, []).append(W[pi])
    cen = {k: np.concatenate(v).mean(0) for k, v in cen.items()}
    moved = {}
    nb = [(a, b, c) for a in (-1, 0, 1) for b in (-1, 0, 1) for c in (-1, 0, 1)]
    for pi, (i, pr, ai, M, gid) in enumerate(prims):
        if gid < 0:
            continue
        q = np.floor(W[pi] / tol).astype(np.int64)
        for vi, k in enumerate(map(tuple, q)):
            hit = False
            for d in nb:
                for pj, vj in cell.get((k[0] + d[0], k[1] + d[1], k[2] + d[2]), ()):
                    if prims[pj][4] != gid and np.linalg.norm(W[pj][vj] - W[pi][vi]) < tol:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                dv = cen[gid] - W[pi][vi]
                dv = dv / (np.linalg.norm(dv) or 1) * mv
                moved.setdefault(pi, []).append((vi, dv))
    nmov = 0
    for pi, lst in moved.items():
        i, pr, ai, M, gid = prims[pi]
        a = J['accessors'][ai]
        bv = J['bufferViews'][a['bufferView']]
        assert a['componentType'] == 5126
        o0 = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        st = bv.get('byteStride', 0) or 12
        Minv = np.linalg.inv(M[:3, :3])
        for vi, dv in lst:
            off = o0 + vi * st
            p = np.array(struct.unpack_from('<3f', BIN, off), dtype=np.float64) + Minv @ dv
            struct.pack_into('<3f', BIN, off, *p)
            nmov += 1
        P = g.acc(ai)
        a['min'], a['max'] = [float(x) for x in P.min(0)], [float(x) for x in P.max(0)]
    print('  挪开了 %d 个和别的部件共用的顶点（%.1f 毫米）' % (nmov, mv * s * 1000))

    # —— 部件名（左右）——
    names = {}
    for gid, (base, kind, x) in groups.items():
        pts = np.concatenate([W[pi] for pi, p in enumerate(prims) if p[4] == gid])
        c = web(pts.mean(0))
        names[gid] = base[:-1] + ('L' if c[1] > 0 else 'R') if base.endswith('*') else base
    assert len(set(names.values())) == len(names), names

    def gpts(gid):   # 这个部件的顶点（网页版坐标）
        return web(np.concatenate([W[pi] for pi, p in enumerate(prims) if p[4] == gid]))

    out = {}
    K = C['K']
    Axi = Ax.T
    for gid, (base, kind, x) in sorted(groups.items(), key=lambda kv: names[kv[0]]):
        nm = names[gid]
        W0 = g.world(gid)
        p0 = W0[:3, 3]
        if kind == 'kf':
            t0, t1 = C['win'][x]
            Wa = g.world(gid, t0)
            if np.abs(Wa - W0).max() > 1e-4:
                print('  注意：%s 动画起点和静止姿势差 %.5f' % (nm, np.abs(Wa - W0).max()))
            keys = []
            for t in np.linspace(t0, t1, K):
                Wt = g.world(gid, t)
                Rel = Wt @ np.linalg.inv(W0)
                Rg = orthonorm(Rel[:3, :3])
                d = (Ax @ (Wt[:3, 3] - p0)) * s
                q = mat_q(Ax @ Rg @ Axi)
                keys.append([round(float(v), 4) for v in list(d) + list(q)])
            # 四元数保持同一半球（插值不绕远路）
            for j in range(1, len(keys)):
                if np.dot(keys[j][3:], keys[j - 1][3:]) < 0:
                    keys[j][3:] = [-v for v in keys[j][3:]]
            out[nm] = {'k': 'kf', 'ch': x, 'p': [round(float(v), 4) for v in web(p0)], 'key': keys}
        elif kind == 'hinge':
            ha, hb = C['hwin']
            tt = sorted(set(np.concatenate([v[0] for v in g.ch[gid].values()]).tolist()))
            tt = [t for t in tt if ha <= t <= hb]
            best, bt = -1, None
            for t in tt:
                R = g.world(gid, t)[:3, :3] @ np.linalg.inv(W0[:3, :3])
                ang = np.arccos(np.clip((np.trace(orthonorm(R)) - 1) / 2, -1, 1))
                if ang > best:
                    best, bt = ang, t
            R = orthonorm(g.world(gid, bt)[:3, :3] @ np.linalg.inv(W0[:3, :3]))
            w_, V_ = np.linalg.eig(R)
            ax = np.real(V_[:, np.argmin(np.abs(w_ - 1))])
            ax = Ax @ ax
            ax /= np.linalg.norm(ax)
            pv = web(p0)
            P = gpts(gid)
            tproj = (P - pv) @ ax
            a, b = pv + ax * tproj.min(), pv + ax * tproj.max()
            if x in ('rud', 'fin'):
                probe, want = P[np.argmin(P[:, 0])], A.RIGHT
            else:
                probe, want = P[np.argmin(P[:, 0])], A.DOWN
            cy = P[:, 1].mean()   # 哪一侧按部件的中心（全动平尾的支点可能在中线上）
            side = -1 if cy > 0.05 else (1 if cy < -0.05 else 0)   # 1 右、−1 左
            out[nm] = {'k': x, 's': side, 'a': [round(float(v), 4) for v in a], 'b': [round(float(v), 4) for v in b],
                       'sg': A.probe_sign(a, b, probe, want), 'deg': round(float(np.degrees(best)), 1)}
        else:   # 座舱盖：后端下沿的横向铰链，往上掀
            P = gpts(gid)
            xr = P[:, 0].min()
            rear = P[P[:, 0] < xr + 0.3]
            zr = rear[:, 2].min()
            a, b = np.array([xr, P[:, 1].max(), zr]), np.array([xr, P[:, 1].min(), zr])
            out[nm] = {'k': 'canopy', 's': 0, 'a': [round(float(v), 4) for v in a], 'b': [round(float(v), 4) for v in b],
                       'sg': A.probe_sign(a, b, P.mean(0), A.UP), 'A': C['canopy']['A']}
    for nm, e in C.get('bays', {}).items():   # 铰链烘焙后按门板的形状算（air2glb.py 调 auto_bay）
        out[nm] = dict(e, auto='outer')
    os.makedirs(outdir, exist_ok=True)
    glb = os.path.join(outdir, key + '.glb')
    write_glb(glb, J, BIN)
    os.makedirs(KFDIR, exist_ok=True)
    jp = os.path.join(KFDIR, key + '.json')
    with open(jp, 'w', encoding='utf-8') as f:
        f.write('{\n  "src": %s,\n  "scale": %.6f,\n  "surf": {\n' % (json.dumps(os.path.basename(src)), s))
        f.write(',\n'.join('    %s: %s' % (json.dumps(k), json.dumps(v, ensure_ascii=False)) for k, v in out.items()))
        f.write('\n  }\n}\n')
    # 烘焙配置：每个部件按节点名挑（节点路径里有这一段）
    def esc(n):
        return n.replace('.', '\\.')
    parts = [{'name': names[gid], 'kind': 'kf', 'nodes': '/' + esc(J['nodes'][gid]['name']) + '(/|$)'} for gid in sorted(groups, key=lambda k: names[k])]
    print('  → %s、%s（%d 个部件，缩放 %.4f）' % (glb, jp, len(out), s))
    print('烘焙配置：')
    print('  "dropNodes": %s,' % json.dumps('|'.join('/' + esc(n) + '(/|$)' for n in C['drop'])))
    print('  "parts": %s' % json.dumps(parts, ensure_ascii=False))
    for nm, e in out.items():
        if e['k'] != 'kf':
            print('  %-8s %-9s s %2d sg %2d %s' % (nm, e['k'], e['s'], e['sg'], ('%.1f°' % e['deg']) if 'deg' in e else ''))


# ---------------------------------------------------------------- air2glb.py 用

def auto_bay(e, P):
    """弹舱门（网页版坐标的顶点 P）：铰链在外侧边（离中线最远）、门板的顶面高度，沿机身前后；往下翻"""
    yo = P[:, 1].max() if P[:, 1].mean() > 0 else P[:, 1].min()
    zt = P[:, 2].max()
    a, b = np.array([P[:, 0].max(), yo, zt]), np.array([P[:, 0].min(), yo, zt])
    o = {k: v for k, v in e.items() if k != 'auto'}
    o.update({'s': 1 if yo < 0 else -1, 'a': a, 'b': b, 'sg': A.probe_sign(a, b, P.mean(0), A.DOWN)})
    return o

def load(key):
    p = os.path.join(KFDIR, key + '.json')
    if not os.path.exists(p):
        return None
    return json.load(open(p, encoding='utf-8'))


def apply_key(e, P, j=-1):
    """把网页版坐标的点 P 按 kf 部件 e 的第 j 帧挪（默认最后一帧：起落架放下、舱门打开）"""
    k = e['key'][j]
    d, q = np.array(k[0:3]), k[3:7]
    pv = np.array(e['p'])
    return pv + d + (np.asarray(P, float) - pv) @ qmat(q).T


def to_model(e, R, rb):
    """kf 部件的支点、关键帧换到 Roblox 模型坐标：支点 R(p)；挪动量 rb(d)（线性）；转动 Rb·R·Rbᵀ"""
    Rb = rb(np.eye(3))   # 每一行是一个网页版的轴换过去（乘了 S）
    Rb = (Rb / np.linalg.norm(Rb[0])).T   # 列向量形式：r = Rb @ v
    o = dict(e)
    o['p'] = [round(float(x), 3) for x in R(e['p'])]
    keys = []
    for k in e['key']:
        d = rb(np.array(k[0:3]))
        Rm = Rb @ qmat(k[3:7]) @ Rb.T
        q = mat_q(Rm)
        keys.append([round(float(x), 3) for x in d] + [round(float(x), 4) for x in q])
    for j in range(1, len(keys)):
        if np.dot(keys[j][3:], keys[j - 1][3:]) < 0:
            keys[j][3:] = [-v for v in keys[j][3:]]
    o['key'] = keys
    return o


if __name__ == '__main__':
    prep(sys.argv[1], sys.argv[2], sys.argv[3])
