#!/usr/bin/env python3
# 推进式螺旋桨拆成会转的部件（用户 11-26「发动机的 bug 是螺旋桨建模位置歪了 且发动机不会动」）：
#   原模型（MQ-9，攻击-2 也用它）的三片桨叶和机身尾部的一块灰色零件烘在一块网格里（Body_1），桨毂整流罩烘在机身（Body_2）里——
#   游戏里只能跟着机身一动不动，零件拼的那副转着的螺旋桨又在导入原模型时去掉了。
#   这里按连通块把桨叶、整流罩挑出来（整块在桨盘附近的：z ≥ z0、离桨轴 rmax 以内），另成两块：
#     Prop_<n>：桨叶（游戏里转、转快了变虚、出一圈桨盘）；PropHub_<n>：桨毂整流罩（跟着转，不变虚）
#   桨轴：整流罩根部那一圈拟合的圆心，顺着机身（+Z 朝后）；桨盘在桨叶那一层的中间。元数据加 prop = { p 桨毂, a 轴, r 桨尖半径 }
#   换一个版本号写出来（mq9_v4 → mq9_v5：导入后的块叫 A_mq9_v5__…，和用户已经导入的不重名；文件名不变 models/air/mq9.glb），
#   alias 指到新版本，老版本记进 old（没重导的照旧用老的，只是螺旋桨不转）
#   用法：python3 -I tools/models/propsplit.py [模型键 …]（不写就是 PROP 表里全部）
import os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
import wingcut as W   # noqa: E402  ImportedAir.lua 读回 Python、读写 GLB、版本号加一

META = W.META
# 模型（不带版本号的键）→ 桨盘附近的范围（模型坐标，格）：z0 桨叶前缘往前一点、c 桨轴大概在哪（x, y）、rmax 桨尖半径往外一点
PROP = {'mq9': {'z0': 13.45, 'c': [0.0, 5.57], 'rmax': 2.85}}


def comps(V, T):
    """三角形按连通块编号（位置到 0.1 毫米相同的顶点算连着）"""
    q = np.round(V * 10000).astype(np.int64)
    _, vid = np.unique(q, axis=0, return_inverse=True)
    vid = vid.reshape(-1)
    par = np.arange(vid.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b, c in vid[T]:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                par[rx] = ry
    return np.array([find(vid[t[0]]) for t in T])


def split_one(kname, info, J, BIN, newk, cf):
    parts = info['parts']
    c0 = np.array(cf['c'], dtype=np.float64)
    keep, prop = [], []   # (块名, 元数据, [(V, A, T, mat)])；prop 的按材质收
    pv = {}               # 材质 → [(V, A, T)]（桨叶 / 整流罩分开：整流罩是沿轴长的那块）
    hubs = []
    for n in J['nodes']:
        if 'mesh' not in n:
            continue
        nm = n['name'].split('__', 1)[1]
        p = parts.get(nm)
        if not p:
            continue
        t = np.array(n.get('translation', [0, 0, 0]), dtype=np.float64)
        rest = []
        for pr in J['meshes'][n['mesh']]['primitives']:
            V = W.accessor(J, BIN, pr['attributes']['POSITION']) + t
            A = {k: W.accessor(J, BIN, i) for k, i in pr['attributes'].items() if k != 'POSITION'}
            T = W.accessor(J, BIN, pr['indices']).astype(np.int64).reshape(-1, 3) if 'indices' in pr else np.arange(len(V)).reshape(-1, 3)
            mat = pr.get('material')
            if p['g'] != 'Body' or V[:, 2].max() < cf['z0']:
                rest.append((V, A, T, mat))
                continue
            lab = comps(V, T)
            take = np.zeros(len(T), dtype=bool)
            for l in np.unique(lab):
                sel = lab == l
                P = V[np.unique(T[sel].reshape(-1))]
                if P[:, 2].min() < cf['z0']:
                    continue
                if np.hypot(P[:, 0] - c0[0], P[:, 1] - c0[1]).max() > cf['rmax']:
                    continue
                take |= sel
                lo, hi = P.min(0), P.max(0)
                kind = 'hub' if (hi[2] - lo[2]) > 2 * max(hi[0] - lo[0], hi[1] - lo[1]) * 0.5 and (hi[2] - lo[2]) > 1.0 else 'blade'
                if kind == 'hub':
                    hubs.append(P)
                pv.setdefault((kind, mat, nm), []).append((V, A, T[sel]))
                print('    %s：%s 一块 %d 个三角形 x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f]' % (nm, '整流罩' if kind == 'hub' else '桨叶', sel.sum(), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
            if (~take).any():
                rest.append((V, A, T[~take], mat))
        if rest:
            keep.append((nm, p, rest))
    if not pv:
        raise SystemExit('%s：桨盘附近没找到桨叶' % kname)
    # 桨轴：整流罩根部（z 最小那头往后 0.15 格）那一圈顶点拟合圆心；没有整流罩就用桨叶内端
    if hubs:
        H = np.concatenate(hubs)
        z_lo = H[:, 2].min()
        ring = H[H[:, 2] < z_lo + 0.15]
    else:
        B_ = np.concatenate([np.concatenate([v[np.unique(t.reshape(-1))] for v, a, t in L]) for (k, m, nm), L in pv.items()])
        d = np.hypot(B_[:, 0] - c0[0], B_[:, 1] - c0[1])
        ring = B_[d < np.percentile(d, 10)]
    Am = np.c_[2 * ring[:, 0], 2 * ring[:, 1], np.ones(len(ring))]
    bm = ring[:, 0] ** 2 + ring[:, 1] ** 2
    hx, hy, cc = np.linalg.lstsq(Am, bm, rcond=None)[0]
    blades = np.concatenate([np.concatenate([v[np.unique(t.reshape(-1))] for v, a, t in L]) for (k, m, nm), L in pv.items() if k == 'blade'])
    hz = (blades[:, 2].min() + blades[:, 2].max()) / 2
    rtip = float(np.hypot(blades[:, 0] - hx, blades[:, 1] - hy).max())
    print('    桨轴 (%.3f, %.3f)，桨盘 z %.3f，桨尖半径 %.3f' % (hx, hy, hz, rtip))
    # 写块：原来的块（去掉螺旋桨）+ 螺旋桨按（桨叶 / 整流罩，材质）各一块
    new_parts, nodes_out = {}, []

    def emit(name, p, plist):
        allV = np.concatenate([q[0][np.unique(q[2].reshape(-1))] for q in plist])
        lo, hi = allV.min(0), allV.max(0)
        ctr = (lo + hi) / 2
        p2 = dict(p)
        p2['c'], p2['s'] = W.r3(ctr), W.r3(np.maximum(hi - lo, 0.02))
        new_parts[name] = p2
        prims = []
        for (V, A, T, mat) in plist:   # 只留用到的顶点
            u, inv = np.unique(T.reshape(-1), return_inverse=True)
            prims.append((V[u] - ctr, {k: a[u] for k, a in A.items()}, inv.reshape(-1, 3), mat))
        nodes_out.append(('A_%s__%s' % (newk, name), ctr, prims))
    for nm, p, rest in keep:
        emit(nm, p, rest)
    cnt = {'blade': 0, 'hub': 0}
    for (kind, mat, nm), L in sorted(pv.items(), key=lambda kv: (kv[0][0], str(kv[0][1]))):
        cnt[kind] += 1
        g = 'Prop' if kind == 'blade' else 'PropHub'
        src = parts[nm]
        p = {'g': g}
        for k_ in ('col', 'a', 'met'):
            if k_ in src:
                p[k_] = src[k_]
        emit('%s_%d' % (g, cnt[kind]), p, [(V, A, T, mat) for V, A, T in L])
    return new_parts, nodes_out, {'p': W.r3([hx, hy, hz]), 'a': [0, 0, 1], 'r': round(rtip, 3)}


def main(argv):
    src = open(META, encoding='utf-8').read()
    m_alias = re.search(r'\n  alias = (\{.*?\}),\n  old = ', src, re.S)
    m_old = re.search(r'\n  old = (\{.*?\}),\n  m = \{\n', src, re.S)
    alias = W.lua_parse(m_alias.group(1))
    oldt = W.lua_parse(m_old.group(1))
    lines = B.old_lines(META)
    want = set(argv) or set(PROP)
    done = {}
    for aid, kv in sorted(alias.items()):
        plain = kv.endswith('~')
        kname = kv[:-1] if plain else kv
        base = re.sub(r'_v\d+$', '', kname)
        if base not in want or base not in PROP:
            continue
        if kname not in done:
            info = W.lua_parse(lines[kname].split('=', 1)[1].strip().rstrip(','))
            if info.get('prop'):
                print('  %s 已经拆过' % kname)
                continue
            path = os.path.join('models/air', base + '.glb')
            J, BIN = W.load_glb(path)
            if not J['nodes'][1]['name'].startswith('A_%s__' % kname):
                print('  %s 里不是 %s 的块（%s），跳过' % (path, kname, J['nodes'][1]['name']))
                continue
            newk = W.bump(kname)
            print('  %s → %s（%s）' % (kname, newk, path))
            new_parts, nodes_out, pr = split_one(kname, info, J, BIN, newk, PROP[base])
            info2 = dict(info)
            info2['parts'] = new_parts
            info2['prop'] = pr
            W.write_glb(path, J, BIN, nodes_out, 'A_' + newk)
            print('    写好了 %s（%.1f MB）' % (path, os.path.getsize(path) / 1e6))
            lines[newk] = '    %s = %s,\n' % (newk, B.lua(info2))
            done[kname] = newk
        if kname not in done:
            continue
        newk = done[kname]
        alias[aid] = newk + ('~' if plain else '')
        prev = oldt.get(aid) or []
        if isinstance(prev, str):
            prev = [prev]
        oldt[aid] = [kv] + [k for k in prev if k not in (kv, newk, newk + '~')]
    if not done:
        print('没有要拆的')
        return
    body = '\n  alias = ' + B.lua(alias) + ',\n  old = ' + B.lua(oldt) + ',\n  m = {\n'
    for k_ in sorted(lines):
        ln = lines[k_]
        body += ln if ln.endswith('\n') else ln + '\n'
    body += '  },\n}\n'
    open(META, 'w', encoding='utf-8').write(src[:m_alias.start()] + body)
    print('元数据写好了：%s' % ', '.join('%s → %s' % kv for kv in done.items()))


if __name__ == '__main__':
    main(sys.argv[1:])
