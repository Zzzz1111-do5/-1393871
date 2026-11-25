#!/usr/bin/env python3
# 宣传片的特效序列帧（程序生成，代替原来用户在 Fab 买的 ArmyVFX——那套贴图不在仓库里）：
#   expl 爆炸火球 → 黑烟（11 × 11 = 121 帧）、fire 火焰循环（8 × 8 = 64 帧）、mzl 枪口焰（3 × 3 = 9 帧）、
#   mzla 炮口焰（10 × 10 = 100 帧，侧面：从下边正中往上喷）、puff 烟团（8 × 8 = 64 帧，彩色）
#   通道约定照 film/fx.js 的 sheetMat：非彩色的 R = G = 烟的明暗（受光）、B = 火的热度（着色器里按热度上火色）、A = 不透明度（不预乘）；
#   puff 是彩色的 RGB + A。帧从左上角起、一行行往下排。
#   用法：python3 -I tools/trailer/vfx_gen.py <输出目录>（写 expl.webp、fire.webp、mzl.webp、mzla.webp、puff.webp；几分钟）
import sys, os, math
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/vfx'
os.makedirs(OUT, exist_ok=True)
FS = int(os.environ.get('FS', '256'))   # 每帧边长（像素）

# —— 三维梯度噪声（Perlin），向量化 ——
rs = np.random.RandomState(20261122)
PERM = np.concatenate([rs.permutation(256)] * 2).astype(np.int32)
G3 = rs.normal(size=(256, 3))
G3 /= np.linalg.norm(G3, axis=1, keepdims=True)


def fade(t):
  return t * t * t * (t * (t * 6 - 15) + 10)


def perlin3(x, y, z):
  xi, yi, zi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32), np.floor(z).astype(np.int32)
  xf, yf, zf = x - xi, y - yi, z - zi
  xi &= 255; yi &= 255; zi &= 255
  u, v, w = fade(xf), fade(yf), fade(zf)

  def g(ix, iy, iz, dx, dy, dz):
    h = PERM[PERM[PERM[ix] + iy] + iz]
    gg = G3[h]
    return gg[..., 0] * dx + gg[..., 1] * dy + gg[..., 2] * dz
  x1, y1, z1 = (xi + 1) & 255, (yi + 1) & 255, (zi + 1) & 255
  n000 = g(xi, yi, zi, xf, yf, zf); n100 = g(x1, yi, zi, xf - 1, yf, zf)
  n010 = g(xi, y1, zi, xf, yf - 1, zf); n110 = g(x1, y1, zi, xf - 1, yf - 1, zf)
  n001 = g(xi, yi, z1, xf, yf, zf - 1); n101 = g(x1, yi, z1, xf - 1, yf, zf - 1)
  n011 = g(xi, y1, z1, xf, yf - 1, zf - 1); n111 = g(x1, y1, z1, xf - 1, yf - 1, zf - 1)
  nx00 = n000 + u * (n100 - n000); nx10 = n010 + u * (n110 - n010)
  nx01 = n001 + u * (n101 - n001); nx11 = n011 + u * (n111 - n011)
  nxy0 = nx00 + v * (nx10 - nx00); nxy1 = nx01 + v * (nx11 - nx01)
  return (nxy0 + w * (nxy1 - nxy0)) * 1.15   # 约 −1 … 1


def fbm(x, y, z, oct=5, lac=2.03, gain=0.5):
  s, a, f, n = 0.0, 0.5, 1.0, 0.0
  for i in range(oct):
    s = s + a * perlin3(x * f + i * 17.1, y * f - i * 9.3, z * f + i * 5.7)
    n += a; a *= gain; f *= lac
  return s / n


def billow(x, y, z, oct=5):   # |噪声| 叠起来：一团团鼓起来的烟
  s, a, f, n = 0.0, 0.5, 1.0, 0.0
  for i in range(oct):
    s = s + a * (1 - np.abs(perlin3(x * f + i * 11.3, y * f + i * 3.1, z * f - i * 7.9)))
    n += a; a *= 0.5; f *= 2.07
  return s / n


def smooth(a, b, x):
  t = np.clip((x - a) / (b - a), 0, 1)
  return t * t * (3 - 2 * t)


def grid(fs=FS):
  y, x = np.mgrid[0:fs, 0:fs].astype(np.float64)
  return (x + 0.5) / fs, (y + 0.5) / fs   # 0 … 1，y 往下


def blur(a, sig):
  """可分离的高斯模糊（像素）"""
  r = max(1, int(sig * 3))
  k = np.exp(-0.5 * (np.arange(-r, r + 1) / sig) ** 2)
  k /= k.sum()
  pad = np.pad(a, r, mode='edge')
  b = np.apply_along_axis(lambda m: np.convolve(m, k, mode='valid'), 1, pad)
  return np.apply_along_axis(lambda m: np.convolve(m, k, mode='valid'), 0, b)


def shade(d, light=(-0.5, -0.8), soft=0.018, k=2.2):
  """烟的受光：密度模糊一下当高度场，左上来光（梯度按帧大小归一，跟分辨率无关）；密的地方里面暗一点"""
  fs = d.shape[0]
  db = blur(d, max(1.0, fs * soft))
  gy, gx = np.gradient(db)
  gx, gy = gx * fs * 0.05, gy * fs * 0.05
  l = 0.5 + 0.5 * np.tanh(-(gx * light[0] + gy * light[1]) * k)
  return np.clip(l, 0, 1)


def disc(X, Y, r0=0.47, r1=0.38):
  """圆形遮罩：离帧中心 r1 以内不动，到 r0 淡到 0（烟团不会被帧的四边切成方的）"""
  return smooth(r0, r1, np.sqrt((X - 0.5) ** 2 + (Y - 0.5) ** 2))


def sheet(frames, n, fs=FS, color=False):
  img = np.zeros((n * fs, n * fs, 4), dtype=np.float64)
  for i, f in enumerate(frames):
    r, c = divmod(i, n)
    img[r * fs:(r + 1) * fs, c * fs:(c + 1) * fs] = f
  return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def edge_fade(x, y, k=0.06):   # 帧的边上一圈淡掉（相邻帧的像素不渗进来）
  return smooth(0, k, x) * smooth(0, k, 1 - x) * smooth(0, k, y) * smooth(0, k, 1 - y)


# —— 爆炸：0 帧一个白热的火球，迅速胀大、翻滚上升，火从里往外熄，变成翻卷的黑烟、最后散掉 ——
def explosion(nf=121):
  X, Y = grid()
  out = []
  mask = disc(X, Y)
  for f in range(nf):
    u = f / (nf - 1)
    t = u * 3.0
    R = 0.10 + 0.21 * (1 - math.exp(-u * 6.5)) + 0.03 * u
    cx, cy = 0.5, 0.56 - 0.10 * u
    px, py = (X - cx) / R, (Y - cy) / R
    py2 = np.where(py > 0, py * (1.3 + 0.35 * u), py * (0.95 - 0.12 * u))   # 底下压扁（地面上炸开）、上面鼓
    r = np.sqrt(px * px + py2 * py2)
    wx = fbm(px * 1.1 + 3.1, py * 1.1, t * 0.55, 3)
    wy = fbm(px * 1.1, py * 1.1 - 4.7, t * 0.55 + 9.2, 3)
    qx, qy = px + 0.6 * wx, py + 0.6 * wy - t * 0.3
    b = billow(qx * 2.0, qy * 2.0, t * 0.45, 5)
    edge = 1.25 - r * (1.0 + 0.1 * u) + (b - 0.58) * (1.1 + 0.4 * u)
    d = smooth(0.0, 0.42, edge) * mask
    hot = math.exp(-u * 4.0)
    core = np.clip(0.95 - r * (0.85 + 2.2 * u) + (b - 0.5) * 1.1, 0, 1)
    pockets = smooth(0.66, 0.88, billow(qx * 3.6 + 7, qy * 3.6, t * 0.8 + 3, 4)) * smooth(0.2, 0.7, d) * (1 - smooth(0.25, 0.8, u))
    heat = np.clip(core * (0.2 + 1.25 * hot) + pockets * 0.6 * (1 - hot), 0, 1) * smooth(0.05, 0.5, d)
    if u < 0.04:
      heat = np.maximum(heat, d * (1 - u / 0.04))
    lum = shade(d) * 0.8 + 0.12
    lum = lum * (1.0 - 0.35 * smooth(0.0, 1.0, d) * smooth(0.2, 0.7, u))   # 后期浓烟里面暗
    a = d * (1 - smooth(0.6, 1.0, u)) ** 1.2
    out.append(np.stack([lum, lum, heat, a], -1))
    if f % 30 == 0: print('  爆炸', f, '/', nf, flush=True)
  return out


# —— 火焰：底下一团、一根根火舌往上蹿、顶上冒烟；首尾接得上（按时间循环混合）——
def fire(nf=64):
  X, Y = grid()
  out = []
  T = 2.0
  mask = disc(X, Y, 0.49, 0.42)
  for f in range(nf):
    w = f / nf
    acc = None
    for k, wt in ((0.0, 1 - w), (-T, w)):   # n(t) = (1 − w) N(t) + w N(t − T)：最后一帧接回第一帧
      t = w * T + k
      px, py = (X - 0.5) * 2.0, (0.92 - Y) / 0.9   # py：0 在底下、1 在顶上
      wx = fbm(px * 2.0, py * 2.0 - t * 2.6, t * 0.5, 3)
      n = fbm(px * 3.6 + wx * 0.9, py * 2.6 - t * 3.6, t * 0.8, 5)
      n2 = billow(px * 2.2 + wx, py * 1.8 - t * 2.4, t * 0.6 + 7, 4)
      width = 0.48 * np.clip(1 - py, 0, 1) ** 0.8 + 0.02
      body = 1 - np.abs(px + 0.18 * wx * py) / width
      flame = body * 1.25 + n * 1.35 + (n2 - 0.5) * 0.8 - py * 0.65
      dens = smooth(0.08, 0.55, flame) * smooth(0.0, 0.08, py)
      sm = (fbm(px * 1.8, py * 1.8 - t * 1.8, t * 0.4 + 4, 4) * 0.9 + 0.55 - np.abs(px) * 1.25) * smooth(0.3, 0.75, py) * (1 - smooth(0.8, 1.05, py))
      v = np.stack([dens, np.clip(sm, 0, 1), flame], -1)
      acc = v * wt if acc is None else acc + v * wt
    dens, smoke, flame = acc[..., 0], acc[..., 1], acc[..., 2]
    hgt = np.clip((0.92 - Y) / 0.9, 0, 1)
    heat = smooth(0.1, 0.9, flame) * (1 - 0.65 * smooth(0.15, 0.85, hgt))
    a = np.clip(np.maximum(dens * 0.95, smoke * 0.6), 0, 1) * mask
    lum = 0.18 + 0.4 * shade(np.maximum(dens, smoke))
    out.append(np.stack([lum, lum, np.clip(heat, 0, 1), a], -1))
  print('  火焰 好了', flush=True)
  return out


# —— 炮口焰（侧面）：从下边正中往上喷：炮口一团白热、往前喷出一道锥，前面鼓出一个大火球（二次焰），很快熄掉，留下一团往上飘的烟 ——
def muzzle_side(nf=100):
  X, Y = grid()
  out = []
  mask = disc(X, Y, 0.5, 0.44)
  for f in range(nf):
    u = f / (nf - 1)
    t = u * 1.5
    py = 1 - Y                      # 0：炮口；1：最远
    px = (X - 0.5) * 2
    L = 0.80 * (1 - math.exp(-u * 16)) + 0.06
    I = math.exp(-u * 2.6)
    n = fbm(px * 3.2, py * 3.0 - t * 1.6, t + 1.7, 4)
    b = billow(px * 2.6, py * 2.6 - t, t * 0.7 + 4, 4)
    cone = 1 - np.abs(px) / (0.06 + 0.42 * np.clip(py / L, 0, 1.2))
    cone = smooth(0.0, 0.5, cone + n * 0.5) * smooth(0.0, 0.025, py) * (1 - smooth(L * 0.75, L * 1.02, py))
    bc = L * 0.58
    bx, by = px / (0.36 + 0.3 * u), (py - bc) / (0.30 + 0.22 * u)
    ball = smooth(0.0, 0.55, 1 - np.sqrt(bx * bx + by * by) + (b - 0.55) * 0.9) * smooth(0.0, 0.12, u + 0.04)
    side = np.zeros_like(px)
    for sgn in (-1, 1):
      sx, sy = (px - sgn * 0.22 * (0.4 + L)) / (0.22 * (0.4 + L)), (py - 0.06) / 0.06
      side = np.maximum(side, smooth(0.0, 0.5, 1 - np.sqrt(sx * sx + sy * sy) + n * 0.5))
    d = np.clip(np.maximum(np.maximum(cone, ball), side * 0.8 * I), 0, 1)
    heat = d * I * (0.65 + 0.35 * smooth(0.35, 0.0, py))
    sm = smooth(0.12, 0.7, u) * np.clip(b * 1.2 - 0.35 - np.abs(px) * 1.0 - np.abs(py - 0.42 - 0.15 * u) * 1.3, 0, 1)
    a = np.clip(np.maximum(d * (0.45 + 0.55 * I), sm * 0.6 * (1 - smooth(0.7, 1.0, u))), 0, 1) * mask
    lum = 0.3 + 0.45 * shade(np.maximum(d, sm))
    out.append(np.stack([lum, lum, np.clip(heat * 1.2, 0, 1), a], -1))
  print('  炮口焰 好了', flush=True)
  return out


# —— 枪口焰（侧面，9 帧各不一样）：白热的核、往前三四根火舌、两边小叉 ——
def muzzle_rifle(nf=9):
  X, Y = grid()
  out = []
  rr = np.random.RandomState(7)
  for f in range(nf):
    py = 1 - Y
    px = (X - 0.5) * 2
    L = 0.55 + 0.4 * rr.rand()
    d = np.zeros_like(px)
    for k in range(rr.randint(3, 6)):
      ang = rr.uniform(-0.55, 0.55)
      ln = L * rr.uniform(0.45, 1.0)
      ux, uy = math.sin(ang), math.cos(ang)
      along = px * ux + py * uy
      across = px * uy - py * ux
      prong = np.clip(1 - np.abs(across) / (0.07 * (1 - along / ln) + 0.006), 0, 1) * (along > 0) * (along < ln)
      d = np.maximum(d, prong * np.clip(1 - along / ln, 0, 1) ** 0.6)
    core = np.clip(1 - np.sqrt((px / 0.22) ** 2 + ((py - 0.12) / 0.2) ** 2), 0, 1)
    d = np.clip(np.maximum(d, core) + fbm(px * 6, py * 6, f * 1.3, 3) * 0.2 * d, 0, 1)
    heat = d
    a = smooth(0.02, 0.35, d) * edge_fade(X, Y, 0.03)
    lum = 0.5 + 0.3 * d
    out.append(np.stack([lum, lum, heat, a], -1))
  print('  枪口焰 好了', flush=True)
  return out


# —— 烟团（彩色）：一开始紧实、亮，慢慢胀大、变稀、边上卷开 ——
def puff(nf=64):
  X, Y = grid()
  out = []
  mask = disc(X, Y)
  for f in range(nf):
    u = f / (nf - 1)
    t = u * 2.0
    R = 0.17 + 0.17 * (1 - math.exp(-u * 3.5))
    px, py = (X - 0.5) / R, (Y - 0.52) / R
    wx = fbm(px * 1.2 + 2, py * 1.2, t * 0.5, 3)
    wy = fbm(px * 1.2, py * 1.2 + 5, t * 0.5 + 3, 3)
    qx, qy = px + 0.5 * wx, py + 0.5 * wy
    r = np.sqrt(qx * qx + qy * qy)
    b = billow(qx * 1.9, qy * 1.9, t * 0.4 + 11, 5)
    d = np.clip(1.25 - r + (b - 0.55) * (0.9 + 0.6 * u), 0, 1)
    d = smooth(0.05, 0.75, d) * (1 - 0.55 * smooth(0.3, 1.0, u)) * mask
    l = shade(d) * 0.6 + 0.4
    col = np.stack([l * 0.93, l * 0.92, l * 0.9], -1)
    a = d
    out.append(np.concatenate([col, a[..., None]], -1))
  print('  烟团 好了', flush=True)
  return out


if __name__ == '__main__':
  jobs = [('puff', puff, 8), ('mzl', muzzle_rifle, 3), ('mzla', muzzle_side, 10), ('fire', fire, 8), ('expl', explosion, 11)]
  only = os.environ.get('ONLY')
  for name, fn, n in jobs:
    if only and name not in only.split(','): continue
    img = sheet(fn(), n)
    # 透明的地方颜色清零（线性过滤、mipmap 不会把底色渗到烟的边上），存无损 WebP：
    #   有损 WebP 按 YUV 4:2:0 压，通道里存的是烟的亮度、热度（不是颜色），压出来一块块 8 × 8 的方块，近看烟团里一排排纹路
    arr = np.asarray(img).copy()
    arr[arr[..., 3] == 0, :3] = 0
    img = Image.fromarray(arr, 'RGBA')
    p = os.path.join(OUT, name + '.webp')
    img.save(p, 'WEBP', lossless=True, quality=100, method=4)
    print('写好了', p, img.size, flush=True)
