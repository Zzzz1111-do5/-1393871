# 网格 → 俯视高度图（每格取最高的那一层，像从天上往下看）：三角形按包围盒分批向量化光栅化（小三角形一次处理一大批，大的逐个）
#   raster(pos, idx, x0, z0, cell, nx, nz, uv=None) → (高, 命中的三角形号, 重心坐标)；没盖到的格高是 −inf
import numpy as np


def _batch(P, T, x0, z0, cell, nx, nz, H, TI, BC, K, sel):
    tri = T[sel]
    a, b, c = P[tri[:, 0]], P[tri[:, 1]], P[tri[:, 2]]
    xs = np.stack([a[:, 0], b[:, 0], c[:, 0]], 1)
    zs = np.stack([a[:, 2], b[:, 2], c[:, 2]], 1)
    i0 = np.floor((xs.min(1) - x0) / cell - 0.5).astype(np.int64)
    k0 = np.floor((zs.min(1) - z0) / cell - 0.5).astype(np.int64)
    oi, ok = np.meshgrid(np.arange(K + 1), np.arange(K + 1), indexing='ij')
    oi, ok = oi.ravel(), ok.ravel()
    I = i0[:, None] + oi[None, :]
    Kk = k0[:, None] + ok[None, :]
    cx = x0 + (I + 0.5) * cell
    cz = z0 + (Kk + 0.5) * cell
    # 重心坐标（xz 平面）
    v0x, v0z = (b[:, 0] - a[:, 0])[:, None], (b[:, 2] - a[:, 2])[:, None]
    v1x, v1z = (c[:, 0] - a[:, 0])[:, None], (c[:, 2] - a[:, 2])[:, None]
    v2x, v2z = cx - a[:, 0][:, None], cz - a[:, 2][:, None]
    den = v0x * v1z - v1x * v0z
    ok_ = np.abs(den) > 1e-14
    den = np.where(ok_, den, 1.0)
    w1 = (v2x * v1z - v1x * v2z) / den
    w2 = (v0x * v2z - v2x * v0z) / den
    w0 = 1 - w1 - w2
    e = -1e-6
    m = ok_ & (w0 >= e) & (w1 >= e) & (w2 >= e) & (I >= 0) & (I < nx) & (Kk >= 0) & (Kk < nz)
    if not m.any():
        return
    y = w0 * a[:, 1][:, None] + w1 * b[:, 1][:, None] + w2 * c[:, 1][:, None]
    rows = np.nonzero(m)
    flat = (Kk[m] * nx + I[m])
    yy = y[m]
    tid = sel[rows[0]]
    # 每格取最高：先按高度排序，后写的覆盖先写的
    order = np.argsort(yy)
    flat, yy, tid = flat[order], yy[order], tid[order]
    ww = np.stack([w0[m][order], w1[m][order], w2[m][order]], 1)
    Hf = H.ravel()
    higher = yy > Hf[flat]
    flat, yy, tid, ww = flat[higher], yy[higher], tid[higher], ww[higher]
    Hf[flat] = yy   # 重复的格：排过序，最后一次（最高的）留下
    TI.ravel()[flat] = tid
    BC.reshape(-1, 3)[flat] = ww


def raster(P, T, x0, z0, cell, nx, nz):
    H = np.full((nz, nx), -np.inf)
    TI = np.full((nz, nx), -1, dtype=np.int64)
    BC = np.zeros((nz, nx, 3))
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    span = np.maximum(np.maximum(np.abs(a[:, 0] - b[:, 0]), np.abs(b[:, 0] - c[:, 0])), np.abs(a[:, 0] - c[:, 0]))
    span = np.maximum(span, np.maximum(np.maximum(np.abs(a[:, 2] - b[:, 2]), np.abs(b[:, 2] - c[:, 2])), np.abs(a[:, 2] - c[:, 2])))
    cs = np.ceil(span / cell).astype(np.int64)
    for K in (1, 2, 4, 8, 16, 32):
        sel_all = np.nonzero((cs <= K) & ((K == 1) | (cs > K // 2)))[0]
        for s in range(0, len(sel_all), max(1, 4000000 // ((K + 1) ** 2))):
            _batch(P, T, x0, z0, cell, nx, nz, H, TI, BC, K, sel_all[s:s + max(1, 4000000 // ((K + 1) ** 2))])
    big = np.nonzero(cs > 32)[0]
    for t in big:   # 极少数大三角形：单独按它的包围盒
        K = int(cs[t]) + 1
        _batch(P, T, x0, z0, cell, nx, nz, H, TI, BC, K, np.array([t]))
    return H, TI, BC


def sample_tex(img, uv):
    """uv (N×2, glTF 约定：v 向下) → 颜色（双线性）"""
    h, w = img.shape[:2]
    u = (uv[:, 0] % 1.0) * w - 0.5
    v = (uv[:, 1] % 1.0) * h - 0.5
    i0 = np.clip(np.floor(u).astype(np.int64), 0, w - 1)
    j0 = np.clip(np.floor(v).astype(np.int64), 0, h - 1)
    i1, j1 = np.clip(i0 + 1, 0, w - 1), np.clip(j0 + 1, 0, h - 1)
    fu, fv = np.clip(u - i0, 0, 1)[:, None], np.clip(v - j0, 0, 1)[:, None]
    c = img[j0, i0] * (1 - fu) * (1 - fv) + img[j0, i1] * fu * (1 - fv) + img[j1, i0] * (1 - fu) * fv + img[j1, i1] * fu * fv
    return c
