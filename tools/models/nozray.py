#!/usr/bin/env python3
# 尾喷口按转好的模型量（用户 11-26「发动机的 bug 是螺旋桨建模位置歪了 且发动机不会动」）：
#   原来 ImportedAir 的 noz 照网页版 / sf_air.py 手写的数，有几型对不上原模型的喷口——
#   歼-10 低了 1.8 格、歼-11 偏上偏里还在喷口后面 2.6 格、歼-6 原模型只有一个圆喷管却标成两个小的、歼-15T / 歼-8 标在喷管里面 1～2 格、
#   F-15 / F-14 没写（用 AirDefs 的发动机位置：在喷口后面 1～4 格的空中）、F-35 / 轰-6K 偏了半格多；
#   涡轮叶片、火焰稳定器、喷口里的热光、加力尾焰、推力矢量喷口外罩都照它摆，所以「歪着」「浮在机尾后面」。
#   这里从机尾往前（−Z）打射线量：出口唇口在哪（给的半径附近各方位最靠后的面）、内径（从里往外第一次打到唇口的半径，按各方位拟合圆心）、
#   喷口里第一层挡着的（模型自带的涡轮面 / 尾锥 / 堵头）离出口多深——游戏里程序画的涡轮摆在它前面，不然被挡住或者和它叠在一起
#   用法：
#     python3 -I tools/models/nozray.py measure <glb> x y z r [x y z r …]   量（给的是大概位置：圈心、出口、半径，模型坐标，格）
#     python3 -I tools/models/nozray.py write                              把下面 NOZM 写进 ImportedAir.lua（这个模型文件的各版本键都改）
#   air2glb.py / sf_air.py 重新生成时也用 NOZM 盖掉手写的数
import os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 模型文件（models/air/<键>.glb）→ 量好的喷口：[x, y, 出口 z, 内径, 喷口里第一层挡着的离出口多深（中位）, 正中心挡着的多深（只有比四周浅得多才写：尾锥）]
#   （模型坐标，格，+Z 朝机尾）
NOZM = {
    'j6': [[0.028, 4.592, 12.098, 0.692, 1.08]],   # 原模型尾部只有一个圆喷管（两台涡喷-6 共用；游戏里两台发动机配到同一个喷口只画一份）
    'j8': [[1.371, 6.316, 22.661, 1.285, 1.89], [-1.371, 6.316, 22.661, 1.285, 1.89]],
    'j10': [[0.0, 5.744, 22.15, 1.341, 2.15]],
    'j11': [[3.15, 8.69, 25.081, 0.982, 3.69], [-3.15, 8.69, 25.081, 0.982, 3.69]],
    'j15t': [[3.497, 6.222, 27.054, 1.622, 5.42], [-3.497, 6.222, 27.054, 1.622, 5.42]],
    'j16': [[3.375, 6.368, 25.092, 1.369, 0.82], [-3.131, 6.366, 25.092, 1.369, 0.85]],   # 原模型左右不对称（网页版也是左右分别量的）；喷口里装着 Su-30 的发动机内腔
    'j20': [[2.198, 5.754, 26.992, 1.4, 1.9], [-2.198, 5.754, 26.992, 1.4, 1.9]],
    'j31': [[2.156, 4.48, 20.72, 1.26, 2.28], [-2.156, 4.48, 20.72, 1.26, 2.28]],
    'f35': [[0.0, 5.416, 17.447, 0.935, 3.12]],
    'h6k': [[5.394, 7.698, 9.669, 1.261, 1.21, 0.34], [-5.394, 7.698, 9.669, 1.261, 1.21, 0.34]],   # 喷口正中有尾锥（第 6 个数：锥尖离出口 0.34；游戏里程序画的盘心、尾锥就不画）
    'f15': [[1.88, 6.39, 23.383, 1.205, 1.34], [-1.88, 6.39, 23.383, 1.205, 1.34]],
    'f14': [[4.037, 6.114, 24.683, 0.968, 1.89], [-4.037, 6.121, 24.683, 0.968, 1.89]],
}


def tris_of(path):
    import glbio
    J, BIN = glbio.read_glb(path)
    return np.concatenate([m.P[m.idx] for m in glbio.meshes(J, BIN) if not glbio.part_name(m.node).startswith(('Gear', 'Rotor', 'TRotor', 'Prop'))])


def cast(ox, oy, oz, tris):
    """射线 (ox, oy, oz) 朝 −Z：第一次打到的 z（没打到 NaN）"""
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    D = np.array([0, 0, -1.0])
    p = np.cross(D, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = np.array([ox, oy, oz]) - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q @ D) * inv
    t = (e2 * q).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return oz - t[hit].min() if hit.any() else np.nan


def measure(T, x, y, zg, r):
    box = (T[:, :, 0].max(1) > x - 2.5 * r) & (T[:, :, 0].min(1) < x + 2.5 * r) & (T[:, :, 1].max(1) > y - 2.5 * r) & (T[:, :, 1].min(1) < y + 2.5 * r) & (T[:, :, 2].max(1) > zg - 8 * r)
    tris = T[box]
    oz = tris[:, :, 2].max() + 1
    cx, cy = x, y
    ang = np.linspace(0, 2 * np.pi, 16, endpoint=False)
    for _ in range(3):
        rs = np.linspace(0.05, 1.3 * r, 60)
        prof = np.array([[cast(cx + rr * np.cos(a), cy + rr * np.sin(a), oz, tris) for a in ang] for rr in rs])
        band = (rs > 0.8 * r) & (rs < 1.25 * r)
        zl = np.nanmedian(np.nanmax(prof[band], axis=0))   # 出口唇口
        rin = []
        for k in range(len(ang)):
            idx = np.where(prof[:, k] > zl - 0.15 * r)[0]
            rin.append(rs[idx[0]] if len(idx) else np.nan)
        rin = np.array(rin)
        g = ~np.isnan(rin)
        px, py = cx + rin[g] * np.cos(ang[g]), cy + rin[g] * np.sin(ang[g])
        cx, cy, c0 = np.linalg.lstsq(np.c_[2 * px, 2 * py, np.ones(len(px))], px ** 2 + py ** 2, rcond=None)[0]
        R = np.sqrt(c0 + cx ** 2 + cy ** 2)
    inner = np.array([cast(cx + rr * np.cos(a), cy + rr * np.sin(a), oz, tris) for rr in np.linspace(0, 0.6 * R, 5) for a in ang[::2]])
    deep = float(np.nanmedian(zl - inner)) if not np.isnan(inner).all() else 99.0
    return [round(float(cx), 3), round(float(cy), 3), round(float(zl), 3), round(float(R), 3), round(deep, 2)]


def write():
    import mdl2glb as B
    import wingcut as W
    lines = B.old_lines(W.META)
    src = open(W.META, encoding='utf-8').read()
    n = 0
    for k in sorted(lines):
        base = re.sub(r'_v\d+$', '', k)
        if base not in NOZM:
            continue
        info = W.lua_parse(lines[k].split('=', 1)[1].strip().rstrip(','))
        if info.get('noz') == NOZM[base]:
            continue
        info['noz'] = NOZM[base]
        new = '    %s = %s,\n' % (k, B.lua(info))
        old = lines[k] if lines[k].endswith('\n') else lines[k] + '\n'
        assert src.count(old) == 1, k
        src = src.replace(old, new)
        n += 1
        print('  %s：noz → %s' % (k, NOZM[base]))
    open(W.META, 'w', encoding='utf-8').write(src)
    print('改了 %d 个模型键' % n)


if __name__ == '__main__':
    if sys.argv[1:2] == ['measure']:
        T = tris_of(sys.argv[2])
        v = list(map(float, sys.argv[3:]))
        for i in range(0, len(v), 4):
            print(measure(T, *v[i:i + 4]))
    elif sys.argv[1:2] == ['write']:
        write()
    else:
        print('用法见文件开头')
