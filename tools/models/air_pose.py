# 转好的飞机原模型（sf_air.py / air2glb.py 的 out、info）按游戏里的动法摆一个姿势（起落架收到几成、杆舵、油门……），
#   写成 GLB 给 Blender 渲染核对（用户 11-26：「你自己弄一个blender吧」）：动法照 AirModels.lua 的 SURF_F、kf 关键帧、喷口偏转 / 调节片开合
#   python3 -I tools/models/sf_air.py <键> <下载的 .glb> <AirDefs 的 JSON> --dry --pose <输出目录> [gear=1,0.5,0 …]
import math
import numpy as np

import air_kf as KF
import sf_gear as SG

R = math.radians


def sstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


SURF_F = {   # 同 AirModels.lua 的 SURF_F（c：pit / rol / yaw −1～1，flap、brk、gear、can 0～1，thr 0～125）
    'ail': lambda c, s, A: -s * c.get('rol', 0) * R(20) - c.get('brk', 0) * R(28),
    'flap': lambda c, s, A: c.get('flap', 0) * R(30),
    'flaperon': lambda c, s, A: c.get('flap', 0) * R(20) - s * c.get('rol', 0) * R(15) + c.get('brk', 0) * R(22),
    'elevon': lambda c, s, A: max(-R(25), min(R(25), -c.get('pit', 0) * R(15) - s * c.get('rol', 0) * R(15))),
    'stab': lambda c, s, A: -c.get('pit', 0) * R(18) - s * c.get('rol', 0) * R(6),
    'elev': lambda c, s, A: -c.get('pit', 0) * R(20),
    'can': lambda c, s, A: c.get('pit', 0) * R(16),
    'rud': lambda c, s, A: c.get('yaw', 0) * R(25) + s * c.get('brk', 0) * R(28),
    'fin': lambda c, s, A: c.get('yaw', 0) * R(18) + s * c.get('brk', 0) * R(22),
    'canopy': lambda c, s, A: c.get('can', 0) * A,
    'gear': lambda c, s, A: (1 - c.get('gear', 1)) * A,
    'gdh': lambda c, s, A: min(1.0, max(0.0, c.get('gear', 1) * 4)) * A,
    'abrk': lambda c, s, A: c.get('brk', 0) * A,
    'slat': lambda c, s, A: c.get('flap', 0) * R(18) + max(0.0, c.get('pit', 0)) * R(12),
    'lev': lambda c, s, A: c.get('flap', 0) * R(8) + c.get('pit', 0) * R(14),
}


def tvc_open(t):
    if t <= 100:
        return 0.45 - 0.3 * min(1.0, max(0.0, t / 100))
    return 0.15 + 0.85 * min(1.0, (t - 100) / 25)


def slerp(q0, q1, t):
    q0, q1 = np.asarray(q0, float), np.asarray(q1, float)
    d = q0 @ q1
    if d < 0:
        q1, d = -q1, -d
    if d > 0.9995:
        q = q0 + (q1 - q0) * t
        return q / np.linalg.norm(q)
    th = math.acos(d)
    return (math.sin((1 - t) * th) * q0 + math.sin(t * th) * q1) / math.sin(th)


def kf_xf(e, u):
    """kf 部件在操纵量 u 时的变换（同 AirModels：x = u·(n−1)，两帧之间 CFrame:Lerp）：返回 (R, 平移)，点 x' = R x + t"""
    K = e['key']
    n = len(K)
    x = min(1.0, max(0.0, u)) * (n - 1)
    i = min(n - 2, int(math.floor(x)))
    f = x - i
    d = np.array(K[i][0:3]) * (1 - f) + np.array(K[i + 1][0:3]) * f
    q = slerp(K[i][3:7], K[i + 1][3:7], f)
    Rm = KF.qmat(q)
    P = np.array(e['p'])
    return Rm, P + d - Rm @ P


def noz_xf(e, c):
    """原模型喷口的推力矢量偏转（模型坐标）：抬头出口往上、右偏出口往右、右滚右边往上左边往下；斜面式（苏-35S）只在外倾 cant 的斜面里偏"""
    P, A = np.array(e['p']), SG.unit(e['a'])
    if not e.get('tv'):
        return np.eye(3), np.zeros(3)
    U = SG.unit(np.array([0, 1.0, 0]) - A * A[1])
    Rt = SG.unit(np.cross(U, A))
    side = 1 if P[0] >= 0 else -1
    up = c.get('pit', 0) * R(15) + side * c.get('rol', 0) * R(8)
    rt = c.get('yaw', 0) * R(10)
    D = up * U + rt * Rt
    if e['tv'] == 'pl':
        E = math.cos(R(e.get('cant', 32))) * U + side * math.sin(R(e.get('cant', 32))) * Rt
        D = (D @ E) * E
    m = np.linalg.norm(D)
    mx = R(e.get('A', 15))
    if m > mx:
        D, m = D * (mx / m), mx
    if m < 1e-6:
        return np.eye(3), np.zeros(3)
    Rm = SG.rot(np.cross(A, D / m), m)
    return Rm, P - Rm @ P


def visible(g, e, c):
    gear = c.get('gear', 1)
    if g == 'GearUp':
        return gear <= 0.002
    if g == 'GearX':
        return gear > 0.002
    if g == 'GearB':
        return gear >= 0.98
    if e and e.get('hu'):
        return gear > (e['hu'] if e['hu'] < 1 else 0.002)
    if e and e.get('k') == 'gear':
        return gear > 0.03
    if e and e.get('k') == 'gdoor':
        return gear > 0.5
    if g == 'Gear':
        return gear > 0.5
    return True


def xf_of(g, e, c, surf):
    """部件 g 的变换 (R, t)：x' = R x + t（模型坐标）"""
    if not e:
        return np.eye(3), np.zeros(3)
    k = e.get('k')
    if k == 'kf':
        return kf_xf(e, c.get(e.get('ch', 'gear'), 1 if e.get('ch', 'gear') == 'gear' else 0))
    if k == 'noz':
        return noz_xf(e, c)
    if k == 'pet':
        Rn, tn = noz_xf(surf[e['n']], c)
        hp, ax = np.array(e['p']), SG.unit(e['a'])
        Rp = SG.rot(ax, e.get('sg', 1) * (tvc_open(c.get('thr', 80)) - e.get('r0', 0.3)) * R(e.get('A', 10)))
        tp = hp - Rp @ hp
        return Rn @ Rp, Rn @ tp + tn
    f = SURF_F.get(k)
    if not f or 'a' not in e or 'b' not in e:
        return np.eye(3), np.zeros(3)
    a, b = np.array(e['a']), np.array(e['b'])
    ang = e.get('sg', 1) * f(c, e.get('s', 0), e.get('A', 0))
    Rm = SG.rot(b - a, ang)
    return Rm, a - Rm @ a


def pose(out, info, c):
    """按姿势 c 摆好的 out（藏起来的部件去掉）：顶点、法线都转好，仍然相对原来的块中心"""
    surf = info.get('surf') or {}
    res = []
    for name, g, mi, P, N, UV, idx in out:
        e = surf.get(g)
        if not visible(g, e, c):
            continue
        Rm, t = xf_of(g, e, c, surf)
        ctr = np.array(info['parts'][name]['c'])
        Pw = (P + ctr) @ Rm.T + t - ctr
        res.append((name, g, mi, Pw, N @ Rm.T, UV, idx))
    return res
