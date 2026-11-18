#!/usr/bin/env python3
# Roblox全面大战场——涂装统一（用户 11-18：96 坦和舰船的贴图修一下、风格统一；发白不是问题，统一就好）
#   原模型来自不同作者，涂装各是各的：解放军这边林地迷彩、雪地迷彩、数码迷彩、纯绿都有，美军沙色、绿色、黑色都有，舰艇的灰有深有浅。
#   这里按阵营定一套标准色（和零件拼的车 VehModels.lua 的 CAMO 一致），把每张底色贴图里的「涂装」映射过去，
#   原贴图的细节、磨损、脏污、阴影都留着（按 Lab 色彩空间保留每个像素和它所属色块的差，只是压小一点）：
#   - 迷彩（几块颜色明显不同）：按深浅对应到三种标准色（深、主、浅），软分配，色块交界不出硬边；
#   - 纯色（只有明暗不同）：整体换成主色，明暗起伏照留——不会凭空加出花纹；
#   - 不动的：红五星、黄字、舷号这些鲜艳的标志（彩度高），很白的字、很黑的缝，暗的中性灰（履带、轮胎、炮钢）；
#   舰艇：彩度压掉、色相统一成标准灰，整体明暗挪到标准灰（甲板和船体的深浅差照留）；水线下的红漆、标志不动。
#   同时把材质的底色系数乘进贴图、系数改成 1（Roblox 导入不认系数，只认贴图）。
#   用法（仓库根目录）：python3 -I tools/models/livery.py [模型…]（默认 FAMILY 里全部；改的是 models/ 下的 GLB，原地写回）
#   改完要重跑 python3 -I tools/models/tint.py（贴图没出来时的平均色），用户在 Studio 里重导这些 GLB
import io, json, os, struct, sys
import numpy as np
from PIL import Image

# 阵营 → 标准色（sRGB）。解放军：三色林地（深绿褐 / 军绿 / 土黄）；美军：单色沙黄（深浅三档都是沙色，只差明暗）
FORCE = {'veh/m2a3': 0.35}   # 原贴图几乎全黑的（布雷德利：一半像素亮度 < 7）：黑的也当漆，明暗差压到这么多
MONO = {'us'}   # 单色涂装的阵营：原来的迷彩花纹去掉（每块颜色都换成主色），只留磨损、脏污、阴影这些细节
PAL = {
    'pla': [(52, 56, 40), (86, 100, 68), (150, 140, 104)],
    'us': [(150, 132, 96), (186, 166, 124), (204, 188, 150)],   # 用户 11-18 要黄色的 M1A2（沙漠涂装）：美军一律单色沙黄
}
NAVY = {'plan': (150, 156, 160), 'usn': (128, 134, 140)}   # 中国海军浅灰、美国海军灰
FAMILY = {
    'veh/ztz96': 'pla', 'veh/ztz99a2': 'pla', 'veh/ztq15': 'pla', 'veh/zbd97': 'pla', 'veh/lav25': 'pla', 'veh/ptl02': 'pla',
    'veh/t625': 'pla', 'veh/pzh2000': 'pla',
    'veh/m1a2dc': 'us', 'veh/m1a1': 'us', 'veh/m2a3': 'us', 'veh/stryker': 'us', 'veh/matv': 'us', 'veh/hmmwv': 'us',
    'veh/jltv': 'us', 'veh/m1150': 'us', 'veh/m109': 'us', 'veh/m163': 'us', 'veh/m270': 'us', 'veh/patriot': 'us', 'veh/cram': 'us',
    'ship/t055': 'plan', 'ship/t054a': 'plan', 'ship/t022': 'plan',
    'ship/ddg125': 'usn', 'ship/cg47': 'usn', 'ship/lcs2': 'usn',
}

# ---------------------------------------------------------------- 色彩空间（sRGB ↔ Lab，D65）

def _lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _gam(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


M1 = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
M2 = np.linalg.inv(M1)
WP = np.array([0.95047, 1.0, 1.08883])


def rgb2lab(rgb):   # rgb: … × 3，0–1
    xyz = (_lin(rgb) @ M1.T) / WP
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab2rgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx, fz = fy + lab[..., 1] / 500, fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    xyz = np.where(f > 0.206893, f ** 3, (f - 16 / 116) / 7.787) * WP
    return _gam(xyz @ M2.T)


def lab_of(c):
    return rgb2lab(np.array(c, dtype=np.float64) / 255.0)

# ---------------------------------------------------------------- 贴图换色


def kmeans(X, k, it=12, seed=1):
    rng = np.random.default_rng(seed)
    C = X[rng.choice(len(X), k, replace=False)]
    for _ in range(it):
        d = ((X[:, None, :] - C[None]) ** 2).sum(-1)
        a = d.argmin(1)
        for j in range(k):
            if (a == j).any():
                C[j] = X[a == j].mean(0)
    return C


def recolor_veh(rgb, alpha, fam, log, force=None):
    lab = rgb2lab(rgb)
    L, A, B = lab[..., 0], lab[..., 1], lab[..., 2]
    C = np.hypot(A, B)
    painted = ((C >= 5) & (C <= 38) & (L >= 8)).mean() >= 0.25   # 这张图大半是有颜色的涂装（车体、炮塔）：黑色迷彩块也是漆
    if force:
        keep = (C > 38) | (L > 93)
    elif painted and fam in MONO:
        keep = (C > 38) | (L > 93) | (L < 7)   # 单色涂装：黑色迷彩块、炮管一起换；只留标志、白字、最黑的缝
    else:
        keep = (C > 38) | (L > 93) | (L < 7) | ((C < 6) & (L < 55))   # 标志、白字、黑缝、暗的中性灰（履带、轮胎、炮钢）
    if alpha is not None:
        keep |= alpha < 0.5
    paint = ~keep
    if paint.sum() < 64:
        log.append('几乎没有涂装像素，不改')
        return rgb
    X = lab[paint]
    sub = X[np.random.default_rng(2).choice(len(X), min(len(X), 20000), replace=False)]
    W = np.array([0.5, 1, 1])   # 聚类时明暗权重小一点（别把阴影当成迷彩）
    Cn = kmeans(sub * W, 3) / W
    Cn = Cn[np.argsort(Cn[:, 0])]
    ab = Cn[:, 1:]
    spread_ab = max(np.hypot(*(ab[i] - ab[j])) for i in range(3) for j in range(i + 1, 3))
    spread_L = Cn[2, 0] - Cn[0, 0]
    camo = not force and (spread_ab > 9 or (spread_L > 38 and (np.hypot(*ab[2]) < 6) != (np.hypot(*ab[0]) < 6)))
    T = np.array([lab_of(c) for c in PAL[fam]])
    if camo:
        d = ((X[:, None, :] - Cn[None]) ** 2).sum(-1)
        w = np.exp(-(d - d.min(1, keepdims=True)) / (2 * 14.0 ** 2))
        w /= w.sum(1, keepdims=True)
        out = np.zeros_like(X)
        mono = fam in MONO
        for j in range(3):
            out += w[:, j:j + 1] * ((T[1] if mono else T[j]) + (X - Cn[j]) * np.array([0.75, 0.45, 0.45]))
        log.append('迷彩：原来 %s → %s' % (' / '.join('%.0f,%.0f,%.0f' % tuple(c) for c in Cn), '单色' if mono else '标准三色'))
    else:
        m = X.mean(0)
        out = T[1] + (X - m) * np.array([force or 0.8, 0.4, 0.4])
        log.append('纯色：原来 L%.0f a%.0f b%.0f → 主色' % tuple(m))
    lab2 = lab.copy()
    lab2[paint] = out
    return lab2rgb(lab2)


def recolor_navy(rgb, alpha, fam, log):
    lab = rgb2lab(rgb)
    L, C = lab[..., 0], np.hypot(lab[..., 1], lab[..., 2])
    keep = (C > 22) | (L > 95) | (L < 6)   # 水线下红漆、舰旗、黄线、白字、黑缝
    if alpha is not None:
        keep |= alpha < 0.5
    paint = ~keep
    if paint.sum() < 64:
        return rgb
    t = lab_of(NAVY[fam])
    X = lab[paint]
    med = np.median(X[:, 0])
    out = X.copy()
    out[:, 0] = np.clip(X[:, 0] + (t[0] - med) * 0.85, 2, 97)   # 明暗整体挪到标准灰（甲板、船体的深浅差照留）
    out[:, 1:] = t[1:] + (X[:, 1:] - X[:, 1:].mean(0)) * 0.25   # 色相统一、彩度压掉
    log.append('舰艇：涂装明度中位 %.0f → %.0f' % (med, med + (t[0] - med) * 0.85))
    lab2 = lab.copy()
    lab2[paint] = out
    return lab2rgb(lab2)

# ---------------------------------------------------------------- GLB 读写


def read_glb(path):
    d = open(path, 'rb').read()
    off, J, B = 12, None, b''
    while off < len(d):
        n, t = struct.unpack_from('<II', d, off)
        if t == 0x4E4F534A:
            J = json.loads(d[off + 8:off + 8 + n])
        elif t == 0x004E4942:
            B = d[off + 8:off + 8 + n]
        off += 8 + n
    return J, B


def write_glb(path, J, B, repl):
    blob = bytearray()
    for i, bv in enumerate(J['bufferViews']):
        o = bv.get('byteOffset', 0)
        data = repl.get(i, B[o:o + bv['byteLength']])
        while len(blob) % 4:
            blob.append(0)
        bv['byteOffset'], bv['byteLength'] = len(blob), len(data)
        blob.extend(data)
    while len(blob) % 4:
        blob.append(0)
    J['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(J, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)


def process(key, fam):
    path = os.path.join('models', key + '.glb')
    J, B = read_glb(path)
    mats = J.get('materials', [])
    # 底色贴图 → 用它的材质的底色系数（同一张图被几种系数用到时取面积最大的那个；这里取第一个，几乎都一样）
    img_fac = {}
    for m in mats:
        pb = m.get('pbrMetallicRoughness', {})
        t = pb.get('baseColorTexture')
        if t is None:
            continue
        src = J['textures'][t['index']]['source']
        img_fac.setdefault(src, pb.get('baseColorFactor', [1, 1, 1, 1])[:3])
        pb['baseColorFactor'] = [1.0, 1.0, 1.0] + pb.get('baseColorFactor', [1, 1, 1, 1])[3:]
    repl, log = {}, []
    for ii, fac in img_fac.items():
        im = J['images'][ii]
        bv = J['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        pil = Image.open(io.BytesIO(B[o:o + bv['byteLength']]))
        has_a = pil.mode in ('RGBA', 'LA') or 'transparency' in pil.info
        arr = np.asarray(pil.convert('RGBA')).astype(np.float64) / 255.0
        rgb = arr[..., :3] * np.array(fac, dtype=np.float64)
        alpha = arr[..., 3] if has_a else None
        sub = []
        if fam in PAL:
            rgb = recolor_veh(rgb, alpha, fam, sub, FORCE.get(key))
        else:
            rgb = recolor_navy(rgb, alpha, fam, sub)
        log.append('  图 %d（%dx%d）：%s' % (ii, pil.size[0], pil.size[1], '；'.join(sub)))
        out = np.clip(np.round(rgb * 255), 0, 255).astype(np.uint8)
        buf = io.BytesIO()
        if has_a:
            Image.fromarray(np.dstack([out, np.round(arr[..., 3] * 255).astype(np.uint8)]), 'RGBA').save(buf, 'PNG', optimize=True)
            im['mimeType'] = 'image/png'
        else:
            Image.fromarray(out, 'RGB').save(buf, 'JPEG', quality=92)
            im['mimeType'] = 'image/jpeg'
        repl[im['bufferView']] = buf.getvalue()
    write_glb(path, J, B, repl)
    print('%s（%s）：%d 张底色贴图' % (key, fam, len(img_fac)))
    for line in log:
        print(line)


if __name__ == '__main__':
    keys = sys.argv[1:] or list(FAMILY)
    for k in keys:
        k = k if '/' in k else next((x for x in FAMILY if x.endswith('/' + k)), k)
        process(k, FAMILY[k])
