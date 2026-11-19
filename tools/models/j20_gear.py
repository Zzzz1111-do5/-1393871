# 歼-20（andertan「Chengdu J-20 Fighter」）补起落架：原模型没有起落架（游戏里原来是零件拼的方块），这里按真机的位置建一套网格加进烘焙好的模型，
#   再写收放的关键帧（tools/models/kf/j20.json），air2glb.py / air_one.py 照常转。用户 11-18：「找到起落架的收放位置、实现动画；模型不要有画质缩减」。
#   用法（先用网页版 tools/v3gbake.js 不减面地烘焙出 js/mdl/j20.js——配置里去掉 tri0 / tri0Flags，或者不装 meshoptimizer）：
#     python3 -I tools/models/j20_gear.py <网页版目录（js/mdl/j20.js 在里面，原地改）>
#     python3 -I tools/models/air_one.py <网页版目录> <airdefs.json> j20
#   坐标是网页版烘焙坐标：x 前、y 左、z 上，米；机体最低点 z = 0，地面在 z = −LIFT（1.25 米，和原来零件拼的起落架一样高，游戏里机身离地不变）。
#   三根起落架都往前收（照真机）：支柱绕横轴往前转，机轮竖着收进舱里——
#     前起落架：座舱下面，支点在舱的后端（x 4.85、离机腹 0.6 米），单轮；
#     主起落架：侧弹舱后面、进气道下侧的斜面上（x −4.15、y ±1.22），单轮，收起时机轮竖着躺进进气道下面。
#   舱门是从机腹蒙皮上切出来的（air_anim.py 的 SURF：GDoorN1 / N2 / ML / MR，动法 gdh：放起落架的前 1/4 先开门、收起的最后 1/4 才关上），
#   舱里的深色舱壁在 WELL 表。支柱的关键帧照同一个节奏：放下时门开了才放支柱（操纵量 0.25 → 1 支柱从收起转到放下），收起时支柱先收到底、门再关。
import base64, json, math, os, sys
import numpy as np

KFDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kf')
LIFT = 1.25          # 机体最低点离地（米）
K = 21               # 关键帧数（操纵量 0～1 等间隔）
DOOR_T = 0.25        # 舱门开关占操纵量的这一截

# 三根起落架：支点 piv（收放的横轴过这里）、机轮半径 r、轮宽 w、支柱粗 rs、收起转多少 A（弧度，往前）
GEARS = {
    'GearN': {'piv': [4.85, 0.0, 0.80], 'r': 0.31, 'w': 0.20, 'rs': 0.068, 'A': 1.62, 'light': True},
    'GearL': {'piv': [-4.15, 1.22, 1.05], 'r': 0.44, 'w': 0.30, 'rs': 0.085, 'A': 1.57},
    'GearR': {'piv': [-4.15, -1.22, 1.05], 'r': 0.44, 'w': 0.30, 'rs': 0.085, 'A': 1.57},
}
# 新材质（网页版烘焙的材质格式；颜色是线性值）：支柱灰色金属、减震筒镀铬、轮胎黑橡胶、轮毂浅灰、着陆灯玻璃
NEWMATS = {
    'gear_metal': {'c': [0.32, 0.33, 0.35, 1], 'mr': [0.85, 0.38]},
    'gear_chrome': {'c': [0.78, 0.79, 0.82, 1], 'mr': [1.0, 0.12]},
    'gear_tire': {'c': [0.016, 0.016, 0.018, 1], 'mr': [0.0, 0.92]},
    'gear_hub': {'c': [0.42, 0.43, 0.45, 1], 'mr': [0.7, 0.35]},
    'gear_light': {'c': [0.9, 0.92, 0.95, 1], 'mr': [0.0, 0.05]},
}


def load(web):
    path = os.path.join(web, 'js', 'mdl', 'j20.js')
    t = open(path, encoding='utf-8').read()
    a = t.index('V3G.add(') + 8
    q, e = t.rindex(", '"), t.rindex("')")
    head = t[a:q]
    c = head.index(',')
    return path, t[:a], head[:c], json.loads(head[c + 1:]), base64.b64decode(t[q + 3:e]), t[e:]


# ---------------------------------------------------------------- 网格（每个函数返回 [位置, 法线]、三角形；UV 都是 0）

class Mesh:
    def __init__(self):
        self.P, self.N, self.T = [], [], []

    def add(self, P, N, T):
        o = sum(len(p) for p in self.P)
        self.P.append(np.asarray(P, float))
        self.N.append(np.asarray(N, float))
        self.T.append(np.asarray(T, np.int64) + o)

    def arrays(self):
        if not self.P:
            return np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3), np.int64)
        return np.concatenate(self.P), np.concatenate(self.N), np.concatenate(self.T)


def frame(axis):
    """单位轴 → 和它垂直的两根轴（u, v, axis 右手）"""
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    h = np.array([0, 0, 1.0]) if abs(a[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(h, a)
    u /= np.linalg.norm(u)
    return u, np.cross(a, u), a


def revolve(m, prof, c, axis, seg=40, smooth=True):
    """绕 axis（过 c）转一圈：prof 是 [(半径, 沿轴的位置)]，按顺序连成母线（法线朝外：母线从轴的负方向往正方向、外侧在左手边时朝外）"""
    u, v, a = frame(axis)
    prof = np.asarray(prof, float)
    n = len(prof)
    ang = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    P, N = [], []
    # 母线上每一点的法线（2D：(dr, dt) 转 90°）
    d = np.gradient(prof, axis=0) if smooth else np.diff(prof, axis=0, append=prof[-1:] + (prof[-1:] - prof[-2:-1]))
    n2 = np.stack([d[:, 1], -d[:, 0]], axis=1)   # (dr, dt) → (dt, −dr)：朝外
    n2 /= np.linalg.norm(n2, axis=1, keepdims=True) + 1e-12
    for t in ang:
        radial = math.cos(t) * u + math.sin(t) * v
        for (r, z), (nr, nz) in zip(prof, n2):
            P.append(np.asarray(c) + radial * r + a * z)
            N.append(radial * nr + a * nz)
    T = []
    for i in range(seg):
        i2 = (i + 1) % seg
        for j in range(n - 1):
            p0, p1, p2, p3 = i * n + j, i * n + j + 1, i2 * n + j, i2 * n + j + 1
            T += [[p0, p2, p1], [p1, p2, p3]]
    m.add(P, N, T)


def cylinder(m, p0, p1, r, seg=20, caps=True):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    L = np.linalg.norm(p1 - p0)
    ax = (p1 - p0) / L
    revolve(m, [(r, 0.0), (r, L)], p0, ax, seg, smooth=False)
    if caps:
        for pc, s in ((p0, -1), (p1, 1)):
            disc(m, pc, ax * s, r, seg)


def disc(m, c, nrm, r, seg=20):
    u, v, a = frame(nrm)
    P = [np.asarray(c, float)] + [np.asarray(c) + (math.cos(t) * u + math.sin(t) * v) * r for t in np.linspace(0, 2 * np.pi, seg, endpoint=False)]
    N = [a] * (seg + 1)
    T = [[0, 1 + i, 1 + (i + 1) % seg] for i in range(seg)]
    m.add(P, N, T)


def box(m, c, size, R=np.eye(3)):
    c, h = np.asarray(c, float), np.asarray(size, float) / 2
    P, N, T = [], [], []
    for ax in range(3):
        for s in (-1, 1):
            n = np.zeros(3)
            n[ax] = s
            o1, o2 = [(ax + 1) % 3, (ax + 2) % 3] if s > 0 else [(ax + 2) % 3, (ax + 1) % 3]
            base = len(P)
            for a1, a2 in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                q = np.zeros(3)
                q[ax] = s * h[ax]
                q[o1] = a1 * h[o1]
                q[o2] = a2 * h[o2]
                P.append(c + R @ q)
                N.append(R @ n)
            T += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
    m.add(P, N, T)


def bar(m, p0, p1, w, d, side=np.array([0, 1.0, 0])):
    """两点之间一根方截面的杆（宽 w 沿 side、厚 d）"""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    ax = p1 - p0
    L = np.linalg.norm(ax)
    ax /= L
    s = side - ax * (side @ ax)
    s /= np.linalg.norm(s)
    t = np.cross(ax, s)
    R = np.stack([ax, s, t], axis=1)
    box(m, (p0 + p1) / 2, [L, w, d], R)


# ---------------------------------------------------------------- 一根起落架（放下的样子）

def tire(m, c, r, w):
    """轮胎：圆角的胎面（外半径 r、宽 w），内圈接轮毂（半径 0.62 r）"""
    ri, hw, k = r * 0.62, w / 2, min(w * 0.3, (r - r * 0.62) * 0.45)
    prof = [(ri, -hw * 0.92), (r - k * 1.6, -hw), (r - k * 0.55, -hw * 0.93), (r - k * 0.1, -hw * 0.72), (r, -hw * 0.42), (r, hw * 0.42),
            (r - k * 0.1, hw * 0.72), (r - k * 0.55, hw * 0.93), (r - k * 1.6, hw), (ri, hw * 0.92)]
    # 母线顺着轴从 −hw 走到 +hw、外侧在 r 大的一边：revolve 的法线朝外
    revolve(m, prof, c, [0, 1.0, 0], seg=48)
    return ri


def hub(m, c, r_rim, w):
    """轮毂：两面内凹的盘 + 中间的轴头盖"""
    hw = w / 2
    for s in (-1, 1):   # 母线从轮辋往轴心走时法线朝 +y；左面（−y）那片倒过来走，法线朝 −y
        prof = [(r_rim, s * hw * 0.92), (r_rim * 0.82, s * hw * 0.62), (r_rim * 0.34, s * hw * 0.55), (r_rim * 0.3, s * hw * 0.85), (0.0, s * hw * 0.88)]
        revolve(m, prof if s > 0 else prof[::-1], c, [0, 1.0, 0], seg=32)
    cylinder(m, np.asarray(c) + [0, -hw * 0.6, 0], np.asarray(c) + [0, hw * 0.6, 0], r_rim * 0.98, seg=32, caps=False)


def gear_mesh(G):
    """一根起落架放下时的网格：按材质分开 {材质名: Mesh}"""
    px, py, pz = G['piv']
    r, w, rs = G['r'], G['w'], G['rs']
    ground = -LIFT
    axle = np.array([px, py, ground + r])
    out = {k: Mesh() for k in NEWMATS}
    M, C, Tm, H = out['gear_metal'], out['gear_chrome'], out['gear_tire'], out['gear_hub']
    top = np.array([px, py, pz])
    yoke_top = axle[2] + r + 0.07          # 叉架横梁在轮胎顶上面一点
    oleo_top = yoke_top + (pz - yoke_top) * 0.52
    # 支点的横轴（耳轴）和上面的支柱、减震筒（镀铬活塞）
    cylinder(M, top + [0, -rs * 2.2, 0], top + [0, rs * 2.2, 0], rs * 0.8, seg=16)
    cylinder(M, top, [px, py, oleo_top], rs, seg=24)
    box(M, [px, py, oleo_top + 0.03], [rs * 2.6, rs * 2.6, 0.06])              # 外筒下端的箍
    cylinder(C, [px, py, oleo_top], [px, py, yoke_top + 0.02], rs * 0.72, seg=24)
    # 扭力臂（前面两节，像个「<」）
    kx = px + rs * 1.9
    mid = (oleo_top + yoke_top) / 2
    bar(M, [px + rs * 0.9, py, oleo_top - 0.02], [kx, py, mid], rs * 0.55, rs * 0.35)
    bar(M, [kx, py, mid], [px + rs * 0.9, py, yoke_top + 0.03], rs * 0.55, rs * 0.35)
    # 叉架：横梁 + 两边的叉臂下到轮轴
    span = w / 2 + 0.05
    box(M, [px, py, yoke_top], [rs * 2.4, span * 2 + 0.06, 0.09])
    for s in (-1, 1):
        bar(M, [px, py + s * span, yoke_top], axle + [0, s * span, 0], 0.05, 0.11, side=np.array([1.0, 0, 0]))
    cylinder(M, axle + [0, -span - 0.03, 0], axle + [0, span + 0.03, 0], 0.035, seg=16)
    # 收放作动筒：从支柱上段斜着往后上连到机体（跟着支柱一起转，看着像撑杆）
    bar(M, [px, py, pz - (pz - oleo_top) * 0.35], [px - 0.42, py, pz + 0.05], rs * 0.7, rs * 0.7)
    # 机轮
    ri = tire(Tm, axle, r, w)
    hub(H, axle, ri, w * 0.86)
    if G.get('light'):   # 前起落架的着陆 / 滑行灯：支柱前面一个小灯罩
        lc = np.array([px + rs * 1.3, py, oleo_top + 0.12])
        cylinder(M, lc - [0.06, 0, 0], lc, 0.075, seg=16)
        disc(out['gear_light'], lc + [0.001, 0, 0], [1.0, 0, 0], 0.065, seg=16)
    return out


# ---------------------------------------------------------------- 关键帧：绕支点的横轴往前收

def quat_y(th):
    return [0.0, math.sin(th / 2), 0.0, math.cos(th / 2)]


def keys(G):
    """操纵量 u（0 收起～1 放下）等间隔 K 帧：u ≤ DOOR_T 支柱收着（门在开关），之后支柱从收起转到放下。
    往前收：绕 +y 轴转负角（右手定则：转正角时往下的支柱往后摆）"""
    out = []
    for j in range(K):
        u = j / (K - 1)
        f = min(1.0, max(0.0, (1 - u) / (1 - DOOR_T)))   # 1 收到底、0 放下
        out.append([0.0, 0.0, 0.0] + [round(x, 6) for x in quat_y(-G['A'] * f)])
    return out


def main():
    web = sys.argv[1]
    path, pre, keyq, meta, binb, tail = load(web)
    if any(p.get('n', '').startswith('Gear') for p in meta.get('parts', [])):
        raise SystemExit('js/mdl/j20.js 里已经有起落架了（重新烘焙一遍再跑）')
    st = meta.get('st', 8)
    VB = np.frombuffer(binb, dtype='<f4', count=meta['vb'][1] // 4, offset=meta['vb'][0]).reshape(-1, st).copy()
    IB = np.frombuffer(binb, dtype='<u4' if meta['it'] == 4 else '<u2', count=meta['ib'][1] // meta['it'], offset=meta['ib'][0]).astype(np.uint32)
    if len(meta['lod']) > 1:
        print('  远处的简化网格去掉（游戏只用最精细那档）')
        meta['lod'] = meta['lod'][:1]
    mi0 = len(meta['mats'])
    tmpl = dict(meta['mats'][0])
    for k in ('t', 'nt', 'mrt', 'sg', 'sgt', 'et', 'ot'):
        tmpl[k] = None
    for name, M in NEWMATS.items():
        m = dict(tmpl)
        m.update({'n': name, 'c': M['c'], 'mr': M['mr'], 'e': [0, 0, 0], 'am': 0, 'ds': 0})
        meta['mats'].append(m)
    mat_ix = {name: mi0 + i for i, name in enumerate(NEWMATS)}
    parts = meta.setdefault('parts', [])
    newV, newI = [VB], [IB]
    nv, ni = len(VB), len(IB)
    surf, tris = {}, 0
    for g, G in GEARS.items():
        pi = len(parts)
        parts.append({'n': g, 'k': 'kf', 'p': G['piv'], 'a': [0, 1, 0]})
        for mname, mesh in gear_mesh(G).items():
            P, N, T = mesh.arrays()
            if not len(T):
                continue
            V = np.zeros((len(P), st), np.float32)
            V[:, 0:3], V[:, 3:6] = P, N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-12)
            newV.append(V)
            idx = (T.reshape(-1) + nv).astype(np.uint32)
            meta['lod'][0].append([mat_ix[mname], pi, ni, len(idx)])
            newI.append(idx)
            nv += len(P)
            ni += len(idx)
            tris += len(T)
        surf[g] = {'k': 'kf', 's': 0 if g == 'GearN' else (1 if g == 'GearR' else -1), 'p': G['piv'], 'ch': 'gear', 'key': keys(G)}
    VB2 = np.concatenate(newV).astype('<f4')
    IB2 = np.concatenate(newI).astype('<u4')
    vb_bytes, ib_bytes = VB2.tobytes(), IB2.tobytes()
    meta['vb'] = [0, len(vb_bytes)]
    meta['ib'] = [len(vb_bytes), len(ib_bytes)]
    meta['it'] = 4
    meta['nv'] = int(len(VB2))
    if meta.get('imgs'):
        raise SystemExit('j20 带贴图的烘焙格式没处理（贴图的偏移要跟着挪）')
    data = vb_bytes + ib_bytes
    t = pre + keyq + ',' + json.dumps(meta, ensure_ascii=False, separators=(',', ':')) + ", '" + base64.b64encode(data).decode('ascii') + tail
    open(path, 'w', encoding='utf-8').write(t)
    os.makedirs(KFDIR, exist_ok=True)
    kp = os.path.join(KFDIR, 'j20.json')
    with open(kp, 'w', encoding='utf-8') as f:
        f.write('{\n  "src": "j20_gear.py（原模型没有起落架，按真机位置建的）",\n  "scale": 1.0,\n  "surf": {\n')
        f.write(',\n'.join('    %s: %s' % (json.dumps(k), json.dumps(v)) for k, v in surf.items()))
        f.write('\n  }\n}\n')
    print('补了起落架：%d 个三角形（前起落架 1 根、主起落架 2 根），%d 个新材质 → %s；关键帧 → %s' % (tris, len(NEWMATS), path, kp))


if __name__ == '__main__':
    main()
