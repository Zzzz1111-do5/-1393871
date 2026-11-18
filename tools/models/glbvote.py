# 成品 GLB 的最后一道面朝向检查（Roblox 只画正面，背面剔掉）：整个模型从 26 个方向各「拍」一张三角形编号图（orient.votes，正交投影、
#   近的盖住远的），每个三角形：
#   · 正面被看到的方向多 → 不动
#   · 背面被看到的方向多 → 翻过来（绕向反过来；给它单独复制一份顶点、法线取反，不影响和它共用顶点的别的面）
#   · 两面都被看到好几次（单层薄片：发动机里只做了朝前一面的风扇盘、机翼上的单层板……）→ 补一份反面
#   从外面哪个方向都看不到的（机身里面、被挡住的）不动
#   然后法线：顶点法线和用它的那几个三角形的朝向相反的（绕向是对的、法线朝里——光照按背光算，Roblox 里是一大片黑），法线取反
#   （歼-20 前机身两侧原来就是这样：面看得见，却黑乎乎的）
# 为什么还要这一道：前面两道（air2glb 里 orient.fix 在网页版烘焙数据上投票、glbfix 里 facing.orient 按法线 + 射线）有漏的——
#   歼-20 机头和前机身 4409 个三角形绕向和法线一起朝里（用户：歼-20 机头镂空）；H-6、A-10 从后往前看发动机里面是空的（用户）
# 一块网格最多 2 万个三角形（Roblox 的上限）：补反面会超的那块只翻、不补
# 用法：python3 -I tools/models/glbvote.py <输入.glb> [输出.glb，默认覆盖输入] [分辨率，默认 2400：太小的三角形不到两个像素算没看到]
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbfix   # noqa: E402
import orient   # noqa: E402

TRI_MAX = 20000


def fix_normals(P, N, I):
    """顶点法线和用它的三角形（按面积加权）的朝向相反的：取反（就地改 N），返回改了几个"""
    fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
    accn = np.zeros((len(P), 3))
    for k in range(3):
        np.add.at(accn, I[:, k], fn)
    bad = np.einsum('ij,ij->i', N.astype(np.float64), accn) < 0
    N[bad] = -N[bad]
    return int(bad.sum())


def vote_file(src, dst=None, res=2400, log=print):
    J, BIN = glbfix.read(src)
    W = glbfix.world_mats(J)
    prims = []   # (图元, 属性 → 访问器)
    Ps, Ts, off = [], [], 0
    used = {}
    for ni, nd in enumerate(J['nodes']):
        if 'mesh' not in nd or ni not in W:
            continue
        M = W[ni]
        for pr in J['meshes'][nd['mesh']]['primitives']:
            if pr.get('mode', 4) != 4 or 'indices' not in pr:
                continue
            P = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64)
            T = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
            Ps.append(P @ M[:3, :3].T + M[:3, 3])
            Ts.append(T + off)
            prims.append((pr, len(T), off, len(P)))
            off += len(P)
            for ai in list(pr['attributes'].values()) + [pr['indices']]:
                used[ai] = used.get(ai, 0) + 1
    P = np.concatenate(Ps)
    T = np.concatenate(Ts)
    good, bad = orient.votes(P, T, res)
    new_data = {}
    t0 = 0
    nflip = ndup = nskip = nnorm = 0
    for pr, nt, voff, nv in prims:
        g, b = good[t0:t0 + nt], bad[t0:t0 + nt]
        t0 += nt
        flip = b > g
        both = ((g > 0) & (b > 0) & ~flip & (np.minimum(g, b) >= 2)) | (flip & (g >= 2))
        acc = list(pr['attributes'].items())
        if not flip.any() and not both.any():
            if 'NORMAL' in pr['attributes'] and used[pr['attributes']['NORMAL']] == 1:   # 不用翻面的图元也查一遍法线
                I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
                Pl = glbfix.acc_read(J, BIN, pr['attributes']['POSITION']).astype(np.float64)
                Nl = glbfix.acc_read(J, BIN, pr['attributes']['NORMAL'])
                k = fix_normals(Pl, Nl, I)
                if k:
                    new_data[pr['attributes']['NORMAL']] = Nl
                    nnorm += k
            continue
        if any(used[ai] > 1 for _, ai in acc) or used[pr['indices']] > 1:   # 访问器和别的图元共用：不动（我们自己写的 GLB 不会这样）
            nskip += 1
            continue
        if nt + int(both.sum()) > TRI_MAX:
            both[:] = False
        I = glbfix.acc_read(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3)
        A = {k: glbfix.acc_read(J, BIN, ai) for k, ai in acc}
        extra = {k: [] for k, _ in acc}
        n0 = nv

        def copy(rows):   # 这些三角形的顶点复制一份（法线取反），返回新的三角形（绕向反过来）
            nonlocal n0
            vs = np.unique(I[rows].reshape(-1))
            remap = np.full(nv, -1, dtype=np.int64)
            remap[vs] = n0 + np.arange(len(vs))
            n0 += len(vs)
            for k, _ in acc:
                v = A[k][vs].copy()
                if k == 'NORMAL':
                    v = -v
                elif k == 'TANGENT':
                    v[:, 3] = -v[:, 3]
                extra[k].append(v)
            return remap[I[rows]][:, [0, 2, 1]]
        I2 = I.copy()
        fr = np.nonzero(flip)[0]
        if len(fr):
            I2[fr] = copy(fr)
        add = []
        dup = np.nonzero(both)[0]
        if len(dup):
            keep, fl = dup[~flip[dup]], dup[flip[dup]]
            if len(keep):
                add.append(copy(keep))
            if len(fl):
                add.append(I[fl].copy())   # 翻过的那个，反面就是原来的样子
        I3 = np.concatenate([I2] + add) if add else I2
        for k, ai in acc:
            if extra[k]:
                new_data[ai] = np.concatenate([A[k]] + extra[k]).astype(A[k].dtype)
        if 'NORMAL' in pr['attributes']:
            ai = pr['attributes']['NORMAL']
            Nl = new_data.get(ai, A['NORMAL']).copy()
            Pl = new_data.get(pr['attributes']['POSITION'], A['POSITION']).astype(np.float64)
            nnorm += fix_normals(Pl, Nl, I3)
            new_data[ai] = Nl
        new_data[pr['indices']] = I3.reshape(-1).astype(np.uint32)
        nflip += len(fr)
        ndup += len(dup)
    if new_data:
        BIN = glbfix.rebuild(J, BIN, new_data)
    glbfix.write(dst or src, J, BIN)
    log('  从 26 个方向看：%d 个三角形里看得到 %d 个；翻过来 %d 个，补反面 %d 个，法线取反 %d 个顶点%s' % (
        len(T), int(((good + bad) > 0).sum()), nflip, ndup, nnorm, ('（%d 个图元和别的共用访问器，没动）' % nskip) if nskip else ''))
    return nflip, ndup


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('用法见文件开头')
        sys.exit(1)
    vote_file(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].isdigit() else None,
              int(sys.argv[-1]) if sys.argv[-1].isdigit() else 2400)
