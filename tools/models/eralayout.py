#!/usr/bin/env python3
# Roblox全面大战场——坦克的爆反块、主动防御（雷达板、发射器）摆在原模型的哪里（用户 11-19：给坦克实现爆反和主动拦截系统）：
#   读 models/veh/<键>.glb（坐标就是车的坐标：原点车底中心，X 右、Y 上、−Z 朝前，单位格），按块名分炮塔 / 车体，
#   在每个区域（炮塔正面、炮塔侧面前半、首上、侧裙板前半）打一格一格的射线：一块砖的中心和四个角都打在同一个面上（深浅差不过 0.2 格）才放，
#   砖的朝向按四个角拟合的平面、大小按四个角实际的距离（斜面上不会拉长），颜色取砖底下贴图的颜色（迷彩接得上）；
#   主动防御：炮塔两侧中段各一个发射器、炮塔四角各一块雷达板（贴在侧面上）。
#   写 src/ReplicatedStorage/EraMeta.lua；用法（仓库根目录）：python3 -I tools/models/eralayout.py [键 …]
import io, json, os, struct, sys
import numpy as np
from PIL import Image

ROOT = os.getcwd()
OUT = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'EraMeta.lua')

# 每型：kind 爆反型号（fy4 重型、fy2 中型、arat 轻型），zones 铺哪些区域，brick 砖的宽 × 高 × 厚（格），skirt 侧裙板的砖（大一点）
SPEC = {
    # 用户 11-19：这些坦克都自带爆反（包括 99A）——四个区都用模型自带的，游戏里平时不另画砖
    'ztz99a2': {'kind': 'fy4', 'zones': ['tfront', 'troof', 'tside', 'glacis', 'skirt'], 'own': ['ts', 'gl', 'sk'], 'brick': (1.25, 0.78, 0.3), 'skirt': (1.9, 1.15, 0.34)},   # 99A 炮塔正面原模型没有：贴（用户 11-19）
    'ztz96': {'kind': 'fy2', 'zones': ['tfront', 'tside', 'glacis', 'skirt'], 'own': ['tf', 'ts', 'gl', 'sk'], 'brick': (1.2, 0.75, 0.3), 'skirt': (1.9, 1.15, 0.32)},
    # 15 式轻坦 11-19 删掉了（用户：建模非常粗糙）
    # M1A2 SEPv2、M1A1 这两个模型侧裙板本来就挂着 ARAT 爆反块（TUSK）：own = 用模型自带的，游戏里平时不另画砖，炸掉了才补焦黑的空位
    #   用户 11-22：「坦克我能选择在哪个地方贴爆反」——再算炮塔正面、炮塔侧面、首上能补贴的位置（改装界面里每个区自己选贴不贴）
    'm1a2dc': {'kind': 'arat', 'zones': ['tfront', 'tside', 'glacis', 'skirt'], 'own': ['sk'], 'brick': (1.3, 0.85, 0.3), 'skirt': (1.7, 1.25, 0.34)},
    'm1a1': {'kind': 'arat', 'zones': ['tfront', 'tside', 'glacis', 'skirt'], 'own': ['sk'], 'brick': (1.3, 0.85, 0.3), 'skirt': (1.7, 1.25, 0.34)},   # 用户 11-19：M1A1 也自带
}
GAP = 0.12        # 砖缝
FLAT = 0.2        # 四个角和中心离拟合平面最多差多少（格），超了说明跨在棱上 / 有东西挡着，不放


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
    ct = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a['componentType']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    st = bv.get('byteStride')
    isz = np.dtype(ct).itemsize
    if st and st != n * isz:
        raw = np.frombuffer(BIN, dtype=np.uint8, count=st * a['count'], offset=o).reshape(a['count'], st)
        return raw[:, :n * isz].copy().view(ct).reshape(a['count'], n)
    return np.frombuffer(BIN, dtype=ct, count=a['count'] * n, offset=o).reshape(a['count'], n)


def images(J, BIN):
    out = {}
    for i, im in enumerate(J.get('images', [])):
        bv = J['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        try:
            out[i] = np.asarray(Image.open(io.BytesIO(BIN[o:o + bv['byteLength']])).convert('RGB'), dtype=np.float32)
        except Exception:
            pass
    return out


def tris(J, BIN):
    """全部三角形：A, B, C（世界坐标）、UV（三个顶点）、材质号、组（Turret / Body / Gun / 其它）"""
    As, Bs, Cs, U, M, Gp = [], [], [], [], [], []
    for n in J['nodes']:
        if 'mesh' not in n:
            continue
        nm = n.get('name', '')
        g = 'Turret' if '__Turret_' in nm else 'Body' if '__Body_' in nm else 'Gun' if '__Gun_' in nm else 'Other'
        t = np.array(n.get('translation', [0, 0, 0]), float)
        for p in J['meshes'][n['mesh']]['primitives']:
            P = acc(J, BIN, p['attributes']['POSITION']).astype(float) + t
            I = acc(J, BIN, p['indices']).reshape(-1, 3).astype(np.int64)
            uv = acc(J, BIN, p['attributes']['TEXCOORD_0']).astype(float) if 'TEXCOORD_0' in p['attributes'] else np.zeros((len(P), 2))
            As.append(P[I[:, 0]]); Bs.append(P[I[:, 1]]); Cs.append(P[I[:, 2]])
            U.append(np.stack([uv[I[:, 0]], uv[I[:, 1]], uv[I[:, 2]]], 1))
            M += [p.get('material', -1)] * len(I)
            Gp += [g] * len(I)
    return np.concatenate(As), np.concatenate(Bs), np.concatenate(Cs), np.concatenate(U), np.array(M), np.array(Gp)


class Mesh:
    def __init__(self, fn):
        self.J, self.BIN = load(fn)
        self.A, self.B, self.C, self.U, self.M, self.G = tris(self.J, self.BIN)
        self.img = images(self.J, self.BIN)
        self.mats = self.J.get('materials', [])

    def box(self, g):
        k = self.G == g
        P = np.concatenate([self.A[k], self.B[k], self.C[k]])
        return P.min(0), P.max(0)

    def subset(self, groups, lo=None, hi=None):
        k = np.isin(self.G, groups)
        if lo is not None:
            c = (self.A + self.B + self.C) / 3
            k &= np.all(c >= lo, 1) & np.all(c <= hi, 1)
        return np.nonzero(k)[0]

    def ray(self, idx, o, d):
        """射线打 idx 里的三角形：返回 (t, 点, 法线（朝着射线来的方向）, 三角形号, 重心 u v)；打不到 None"""
        A, B, C = self.A[idx], self.B[idx], self.C[idx]
        e1, e2 = B - A, C - A
        p = np.cross(d, e2)
        det = (e1 * p).sum(1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        s = o - A
        u = (s * p).sum(1) * inv
        q = np.cross(s, e1)
        v = (q * d).sum(1) * inv
        t = (q * e2).sum(1) * inv
        hit = ok & (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7) & (t > 1e-6)
        if not hit.any():
            return None
        j = np.nonzero(hit)[0][np.argmin(t[hit])]
        n = np.cross(e1[j], e2[j])
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            return None
        n = n / ln
        if n @ d > 0:
            n = -n
        return t[j], o + d * t[j], n, idx[j], (u[j], v[j])

    def color(self, ti, uv):
        """三角形 ti 上重心坐标 uv 处的颜色（贴图 × 底色），0–255"""
        m = self.M[ti]
        base = np.array([200, 200, 200], float)
        fac = np.ones(3)
        img = None
        if 0 <= m < len(self.mats):
            pbr = self.mats[m].get('pbrMetallicRoughness', {})
            f = pbr.get('baseColorFactor')
            if f:
                fac = np.array(f[:3], float)
            bt = pbr.get('baseColorTexture')
            if bt is not None:
                src = self.J['textures'][bt['index']].get('source')
                img = self.img.get(src)
        if img is None:
            return np.clip(base * fac, 0, 255)
        u, v = uv
        tuv = self.U[ti, 0] * (1 - u - v) + self.U[ti, 1] * u + self.U[ti, 2] * v
        h, w = img.shape[:2]
        x = int((tuv[0] % 1) * w) % w
        y = int((tuv[1] % 1) * h) % h
        patch = img[max(0, y - 2):y + 3, max(0, x - 2):x + 3].reshape(-1, 3)
        return np.clip(patch.mean(0) * fac, 0, 255)


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def probe(mesh, idx, o0, ua, va, d, ul, vl, accept, step=0.2):
    """细网格探面：起点 o0 + u·ua + v·va（u 在 0~ul、v 在 0~vl），返回打到要的面的那些点的 (u, v) 范围；一个都没有返回 None"""
    us, vs = [], []
    for u in np.arange(0, ul + 1e-6, step):
        for v in np.arange(0, vl + 1e-6, step):
            r = mesh.ray(idx, o0 + ua * u + va * v, d)
            if r is not None and accept(r[1], r[2]):
                us.append(u)
                vs.append(v)
    if len(us) < 4:
        return None
    return min(us), max(us), min(vs), max(vs)


def tile(mesh, idx, o0, ua, va, d, ul, vl, size, accept, log, tag):
    """在一个面上铺砖：射线起点在 o0 + u·ua + v·va 的平面上（ua、va 单位向量，u 在 0~ul、v 在 0~vl），方向 d；
       先细网格探出真正有面的范围，再按砖的大小居中铺格子；每格打 3 × 3 九根，六根以上打在 accept 要的面上、
       深浅差不过 FLAT 才放：砖按这几个点拟合的平面摆，往外推到最凸的一点（不陷进车身；面上有缝、螺栓也不怕）"""
    out = []
    # 先按这块区域裁三角形（射线是暴力算的，三角形少一半就快一半）
    lo = np.minimum(o0, o0 + ua * ul + va * vl) - 0.5
    hi = np.maximum(o0, o0 + ua * ul + va * vl) + 0.5
    span = np.abs(d) > 0.5
    lo = np.where(span, -1e9, lo)
    hi = np.where(span, 1e9, hi)
    c3 = (mesh.A[idx] + mesh.B[idx] + mesh.C[idx]) / 3
    sub = idx[np.all(c3 >= lo - 1.5, 1) & np.all(c3 <= hi + 1.5, 1)]
    box = probe(mesh, sub, o0, ua, va, d, ul, vl, accept, 0.3)
    if box is None:
        log(f'    {tag}: 没探到面')
        return out
    u0, u1, v0, v1 = box
    bw, bh = size[0] + GAP, size[1] + GAP
    nu, nv = max(1, int((u1 - u0 + 0.3) // bw)), max(1, int((v1 - v0 + 0.3) // bh))
    cu = (u0 + u1) / 2 - nu * bw / 2
    cv = (v0 + v1) / 2 - nv * bh / 2
    du, dv = ua * bw, va * bh
    origin = o0 + ua * cu + va * cv
    for i in range(nu):
        for j in range(nv):
            c0 = origin + du * (i + 0.5) + dv * (j + 0.5)
            pts, nrm, cen = [], [], None
            for a in (-0.38, 0, 0.38):
                for b in (-0.38, 0, 0.38):
                    r = mesh.ray(sub, c0 + du * a + dv * b, d)
                    if r is not None and accept(r[1], r[2]):
                        pts.append(r[1])
                        nrm.append(r[2])
                        if a == 0 and b == 0:
                            cen = r
            if len(pts) < 6:
                continue
            P = np.array(pts)
            dep = P @ d
            keep = np.abs(dep - np.median(dep)) < FLAT * 1.5
            if keep.sum() < 6:
                continue
            P = P[keep]
            c = P.mean(0)
            w_, V = np.linalg.eigh(np.cov((P - c).T))
            n = V[:, 0]
            if n @ (-d) < 0:
                n = -n
            if np.abs((P - c) @ n).max() > FLAT:
                continue
            # 砖面贴着最凸的那一点：中心放在格子中心那根射线和这个平面的交点，再往外推
            o_c = c0
            tt = ((c - o_c) @ n) / (d @ n) if abs(d @ n) > 1e-6 else 0
            cc = o_c + d * tt
            cc = cc + n * max(0.0, ((P - cc) @ n).max())
            uax = unit(du - (du @ n) * n)
            vax = unit(np.cross(n, uax))
            if vax @ dv < 0:
                vax = -vax
            # 大小：格子在面上的投影（斜面上更长），减砖缝
            wid = np.linalg.norm(du - (du @ n) / (d @ n) * d) if abs(d @ n) > 1e-6 else bw
            hei = np.linalg.norm(dv - (dv @ n) / (d @ n) * d) if abs(d @ n) > 1e-6 else bh
            w, h = wid - GAP, hei - GAP
            if w < 0.3 or h < 0.25:
                continue
            col = mesh.color(cen[3], cen[4]) if cen is not None else np.array([90, 96, 80.0])
            out.append({'c': cc, 'n': n, 'u': uax, 'w': min(w, size[0] * 1.6), 'h': min(h, size[1] * 1.6), 't': size[2], 'col': col, 'z': tag})
    log(f'    {tag}: {len(out)} 块（探到 {u1 - u0:.1f} × {v1 - v0:.1f} 格，{nu} × {nv} 格子）')
    return out


def wall(mesh, idx, side, z, ytop, ybot, xout, accept):
    """炮塔侧面 z 处从上往下找到的第一处墙面：(点, 法线)；找不到 None"""
    for y in np.arange(ytop, ybot, -0.15):
        r = mesh.ray(idx, np.array([side * xout, y, z]), np.array([-side, 0, 0.0]))
        if r is not None and accept(r[1], r[2]):
            return r
    return None


def layout(key, sp, log=print):
    fn = os.path.join(ROOT, 'models', 'veh', key + '.glb')
    mesh = Mesh(fn)
    tlo, thi = mesh.box('Turret')
    hlo, hhi = mesh.box('Body')
    glo, ghi = mesh.box('Gun')
    log(f'  {key}: 炮塔 {np.round(tlo, 2)}~{np.round(thi, 2)}，车体 {np.round(hlo, 2)}~{np.round(hhi, 2)}')
    bw, bh, bt = sp['brick']
    blocks = []
    T = mesh.subset(['Turret'])
    Bd = mesh.subset(['Body'])
    tlen = thi[2] - tlo[2]
    hlen = hhi[2] - hlo[2]
    mant = (ghi[0] - glo[0]) / 2 + 0.9   # 炮盾两边各让开一点
    gx = (ghi[0] + glo[0]) / 2
    X, Y, Z = np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])
    for z in sp['zones']:
        if z == 'tfront':
            # 从正前方往后打（+Z），左右两片（让开炮盾）；炮塔正面那一条往往很窄，用小一号的砖
            fs = sp.get('front', (bw * 0.76, bh * 0.7, bt))
            for side in (-1, 1):
                x0, x1 = (gx + mant, thi[0]) if side > 0 else (tlo[0], gx - mant)
                if x1 - x0 < fs[0]:
                    continue
                o0 = np.array([x0, tlo[1], tlo[2] - 6])
                acc_ = (lambda p, n: n[2] < -0.45 and abs(n[1]) < 0.75)
                blocks += tile(mesh, T, o0, X, Y, Z, x1 - x0, thi[1] - tlo[1], fs, acc_, log, 'tf')
        elif z == 'troof':
            # 炮塔顶的前沿（箭形爆反模块从正面包上来）：从上往下打，只要朝前上的斜面；记成正面（tf）
            x0, x1 = tlo[0] + 0.3, thi[0] - 0.3
            z0, z1 = tlo[2], tlo[2] + tlen * 0.3
            o0 = np.array([x0, thi[1] + 4, z0])
            acc_ = (lambda p, n: n[1] > 0.55 and n[2] < -0.12 and (abs(p[0] - gx) > mant))
            blocks += tile(mesh, T, o0, X, Z, -Y, x1 - x0, z1 - z0, sp['brick'], acc_, log, 'tf')
        elif z == 'tside':
            fs = sp.get('side', (bw * 0.9, bh * 0.78, bt))
            for side in (-1, 1):
                z0, z1 = tlo[2], tlo[2] + tlen * 0.5
                xo = abs(thi[0] if side > 0 else tlo[0]) + 6
                o0 = np.array([side * xo, tlo[1], z0])
                acc_ = (lambda p, n, s=side: n[0] * s > 0.55 and abs(n[1]) < 0.7)
                blocks += tile(mesh, T, o0, Z, Y, -side * X, z1 - z0, thi[1] - tlo[1], fs, acc_, log, 'ts')
        elif z == 'glacis':
            # 从上往下打（首上是斜的、接近水平），只打车体；面要朝前上（n.y > 0.3、n.z < −0.06）
            x0, x1 = hlo[0] + 1.4, hhi[0] - 1.4
            z0, z1 = hlo[2], min(tlo[2] - 0.3, hlo[2] + hlen * 0.32)
            o0 = np.array([x0, hhi[1] + 4, z0])
            acc_ = (lambda p, n: n[1] > 0.3 and n[2] < -0.06)
            blocks += tile(mesh, Bd, o0, X, Z, -Y, x1 - x0, z1 - z0, sp['brick'], acc_, log, 'gl')
        elif z == 'skirt':
            sk = sp.get('skirt', sp['brick'])
            for side in (-1, 1):
                edge = hhi[0] if side > 0 else -hlo[0]
                z0, z1 = hlo[2] + 0.5, hlo[2] + hlen * 0.58
                o0 = np.array([side * (edge + 6), 0.6, z0])
                acc_ = (lambda p, n, s=side, e=edge: n[0] * s > 0.8 and abs(p[0]) > e - 1.3)
                blocks += tile(mesh, Bd, o0, Z, Y, -side * X, z1 - z0, min(hhi[1], tlo[1]) - 0.6, sk, acc_, log, 'sk')
    # 主动防御：炮塔主体（去掉天线、机枪站、瞄具这些突出物）的顶面高、半宽按顶点统计量；两侧中段各一个发射器（装在侧墙外的支架上）、
    #   四角各一块雷达板（斜着朝外）
    k = mesh.G == 'Turret'
    Pt = np.concatenate([mesh.A[k], mesh.B[k], mesh.C[k]])
    cx = (Pt[:, 0].max() + Pt[:, 0].min()) / 2
    hw0 = (np.percentile(Pt[:, 0], 98) - np.percentile(Pt[:, 0], 2)) / 2
    mid = (np.abs(Pt[:, 0] - cx) < hw0 * 0.6) & (Pt[:, 2] > tlo[2] + tlen * 0.2) & (Pt[:, 2] < tlo[2] + tlen * 0.8)
    roof = float(np.percentile(Pt[mid, 1], 80)) if mid.any() else float(thi[1] - 1)
    zc = tlo[2] + tlen * 0.56
    def halfw(z, y0, y1, side):
        # 这一段炮塔（z 前后 1.5 格、y0~y1 高）往 side 那边最远到哪：取九成分位，不小于主体半宽的七成五（前面收窄的楔形不至于把雷达板放到中间去）
        m = (Pt[:, 1] > y0) & (Pt[:, 1] < y1) & (np.abs(Pt[:, 2] - z) < 1.5)
        if not m.any():
            return hw0
        xs = (Pt[m, 0] - cx) * side
        xs = xs[xs > 0]
        if len(xs) == 0:
            return hw0
        return max(float(np.percentile(xs, 90)), hw0 * 0.75)
    aps = {'l': [], 'r': []}
    for side in (-1, 1):
        w = halfw(zc, roof - 1.4, roof - 0.2, side)
        aps['l'].append({'c': np.array([cx + side * (w + 0.75), roof - 0.55, zc]), 'n': np.array([side, 0, 0.0])})
        for sz in (-1, 1):
            zq = tlo[2] + tlen * (0.2 if sz < 0 else 0.84)
            w2 = halfw(zq, roof - 1.0, roof - 0.15, side)
            aps['r'].append({'c': np.array([cx + side * (w2 + 0.12), roof - 0.5, zq]), 'n': unit(np.array([side * 0.7, 0, sz * 0.7]))})
    log(f'    主动防御：炮塔顶 {roof:.2f}，半宽 {hw0:.2f}')
    log(f'    共 {len(blocks)} 块爆反；发射器 {len(aps["l"])}、雷达板 {len(aps["r"])}')
    return {'kind': sp['kind'], 'blocks': blocks, 'aps': aps, 'tlo': tlo, 'thi': thi}


def f3(v):
    return '%.3f, %.3f, %.3f' % (v[0], v[1], v[2])


def write(res, tur):
    L = ['-- 自动生成（python3 -I tools/models/eralayout.py），别手改：每型坦克原模型上的爆反块、主动防御的发射器和雷达板（车的坐标，格；炮塔上的按炮塔转角 0 摆）',
         '--   b 每块 { 组 "t" 炮塔 / "h" 车体, 中心 x y z, 朝外法线 x y z, 宽方向 x y z, 宽, 高, 厚, 颜色 r g b, 区 }；区：tf 炮塔正面、ts 炮塔侧面、gl 首上、sk 侧裙板',
         '--   tur 炮塔转轴；aps.l 发射器 { 中心, 朝外 }、aps.r 雷达板 { 中心, 朝外 }；tb 炮塔的包围盒；own 这些区的块原模型上本来就有（平时不另画，炸了补焦黑空位）',
         'return {']
    for key in sorted(res):
        r = res[key]
        own = ', '.join('"%s"' % z for z in SPEC[key].get('own', []))
        L.append('  %s = { kind = "%s", tur = { %s }, tb = { %s, %s }, own = { %s },' % (key, r['kind'], f3(tur[key]), f3(r['tlo']), f3(r['thi']), own))
        L.append('    b = {')
        for b in r['blocks']:
            g = 't' if b['z'] in ('tf', 'ts') else 'h'
            c = b['col']
            L.append('      { "%s", %s, %s, %s, %.2f, %.2f, %.2f, %d, %d, %d, "%s" },' % (g, f3(b['c']), f3(b['n']), f3(b['u']), b['w'], b['h'], b['t'], c[0], c[1], c[2], b['z']))
        L.append('    },')
        L.append('    aps = { l = { %s }, r = { %s } } },' % (
            ', '.join('{ %s, %s }' % (f3(a['c']), f3(a['n'])) for a in r['aps']['l']),
            ', '.join('{ %s, %s }' % (f3(a['c']), f3(a['n'])) for a in r['aps']['r'])))
    L.append('}')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(L) + '\n')


def turpiv():
    """ImportedMeta.lua 里每型的炮塔转轴 tur"""
    import re
    s = open(os.path.join(ROOT, 'src', 'ReplicatedStorage', 'ImportedMeta.lua'), encoding='utf-8').read()
    out = {}
    for key in SPEC:
        i = s.find('    %s = {' % key)
        line = s[i:s.find('\n', i)]
        m = re.search(r', tur = \{ ([\d.\-]+), ([\d.\-]+), ([\d.\-]+) \}', line)
        out[key] = [float(m.group(1)), float(m.group(2)), float(m.group(3))] if m else [0, 4, 0]
    return out


if __name__ == '__main__':
    dump = None
    args = sys.argv[1:]
    if '--json' in args:   # 预览用：每型的块写成 JSON（tools 外面的预览脚本拼进 GLB 渲染）
        i = args.index('--json')
        dump = args[i + 1]
        args = args[:i] + args[i + 2:]
    keys = args or list(SPEC)
    tur = turpiv()
    res = {}
    for k in keys:
        res[k] = layout(k, SPEC[k])
    if dump:
        js = {k: {'blocks': [{kk: (vv.tolist() if hasattr(vv, 'tolist') else vv) for kk, vv in b.items()} for b in r['blocks']],
                  'aps': {g: [{kk: vv.tolist() for kk, vv in a.items()} for a in r['aps'][g]] for g in r['aps']}} for k, r in res.items()}
        json.dump(js, open(dump, 'w'))
    if len(keys) == len(SPEC):
        write(res, tur)
        print('写好了', OUT)
    else:
        print('（只算了一部分，没写文件）')
