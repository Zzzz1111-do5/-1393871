#!/usr/bin/env python3
# 游戏里拼出来的发动机零件对不对得上原模型的喷口（用户 11-26「螺旋桨建模位置歪了 且发动机不会动」）：
#   先跑模拟器导出零件：python3 tools/mock/run.py tools/mock/airnoz.lua out=<dump.json>
#   再：python3 -I tools/models/nozcheck.py <dump.json> [输出目录：每型一张尾部特写，程序画的零件叠在原模型上]
#   真值是原模型的网格（models/air/<文件>.glb）：从机尾往前（−Z）在每个零件中心打一条射线，
#   第一次打到原模型的地方不能在零件后面（零件被机身、喷管壁挡住 = 摆歪了，不在喷口洞里）；涡轮还要在出口往里
import json, os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nozray as NR   # noqa: E402

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2] if len(sys.argv) > 2 else None
bad = 0
for aid, e in sorted(D.items()):
    key = e['key']
    path = os.path.join('models/air', re.sub(r'_v\d+$', '', key) + '.glb')
    if not os.path.exists(path):
        print('%s：没有 %s' % (aid, path))
        continue
    T = NR.tris_of(path)
    oz = T[:, :, 2].max() + 1
    probs, n = [], 0
    noz = e['noz']

    def near(c):   # 零件属于哪个喷口：离喷口轴最近的
        return min(range(len(noz)), key=lambda i: (c[0] - noz[i][0]) ** 2 + (c[1] - noz[i][1]) ** 2) if noz else None
    lips = []   # 每个喷口：原模型唇口在哪（喷口外面紧挨着一圈从后往前打到的）
    for q in noz:   # 同 nozray：喷口半径附近一带（0.85～1.2 倍）各方位最靠后的面，取中位
        per = []
        for a in np.linspace(0, 2 * np.pi, 12, endpoint=False):
            hs = [NR.cast(q[0] + q[3] * k * np.cos(a), q[1] + q[3] * k * np.sin(a), oz, T) for k in np.linspace(0.85, 1.2, 6)]
            if not np.all(np.isnan(hs)):
                per.append(np.nanmax(hs))
        lips.append(float(np.median(per)) if per else np.nan)
    tvc_front = {}
    for p in e['parts']:
        Rm = np.array(p['R']).reshape(3, 3)
        corners = np.array([[a, b, c] for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]) * (np.array(p['s']) / 2)
        zmin = float((corners @ Rm.T + np.array(p['c']))[:, 2].min())
        if p['what'] == 'tvc':
            i = near(p['c'])
            tvc_front[i] = min(tvc_front.get(i, 1e9), zmin)
        if p['what'] not in ('eng', 'holder', 'core'):
            continue
        x, y, z = p['c']
        hit = NR.cast(x, y, oz, T)
        n += 1
        if not np.isnan(hit) and hit > z + 0.06:
            probs.append('%s (%.2f, %.2f, %.2f) 被原模型挡住（往后 %.2f 格就是蒙皮 / 喷管壁）' % (p['what'], x, y, z, hit - z))
        if p['what'] == 'core':
            i = near(p['c'])
            if i is not None and i not in tvc_front and (np.isnan(lips[i]) or abs(z - lips[i]) > 0.5):   # 没有推力矢量外罩：热光就在原模型的出口
                probs.append('core (%.2f, %.2f, %.2f) 不在原模型的喷口出口（唇口在 %.2f）' % (x, y, z, lips[i]))
    if not noz and n:
        probs.append('元数据里没有喷口（noz），零件按 AirDefs 的发动机位置摆的')
    for i, zf in tvc_front.items():   # 推力矢量 / 调节片外罩：前沿接在原模型的唇口上（不浮在机尾后面、不缩进喷管里）
        if i is None:
            continue
        if np.isnan(lips[i]) or abs(zf - lips[i]) > 0.8:   # 0.8：歼-15T 的调节片末端是锯齿，各方位唇口前后差半格多
            probs.append('喷口外罩前沿 z %.2f 没接在原模型唇口（%.2f）上' % (zf, lips[i]))
    if n:
        ok = not probs
        bad += 0 if ok else 1
        print('%s %-6s（%s）：%d 个喷口零件%s' % ('通过' if ok else '不对', aid, key, n, '都看得见（在喷口洞里）' if ok else ('，' + '；'.join(probs[:3]) + ('…共 %d 个' % len(probs) if len(probs) > 3 else ''))))
    if OUT and e['noz']:
        from PIL import Image, ImageDraw
        os.makedirs(OUT, exist_ok=True)
        noz = e['noz']
        R = max(q[3] for q in noz)
        x0, x1 = min(q[0] for q in noz) - 2.4 * R, max(q[0] for q in noz) + 2.4 * R
        y0, y1 = min(q[1] for q in noz) - 2.4 * R, max(q[1] for q in noz) + 2.4 * R
        z0 = min(q[2] for q in noz) - 3.5 * R
        PX = 520 / max(x1 - x0, y1 - y0)
        sel = T[:, :, 2].max(1) > z0
        Tt = T[sel]
        Nn = np.cross(Tt[:, 1] - Tt[:, 0], Tt[:, 2] - Tt[:, 0])
        Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-12)
        L = np.array([0.35, 0.8, 0.45])
        shade = 0.35 + 0.55 * np.abs(Nn @ (L / np.linalg.norm(L)))
        W, H = int((x1 - x0) * PX) + 20, int((y1 - y0) * PX) + 20
        img = Image.new('RGB', (W, H), (236, 238, 240))
        dr = ImageDraw.Draw(img)
        sx = lambda v: 10 + (v - x0) * PX
        sy = lambda v: 10 + (y1 - v) * PX
        for i in np.argsort(Tt[:, :, 2].mean(1)):   # 从后往前看：前面（z 小）的先画
            g = int(150 * shade[i])
            dr.polygon([(sx(q[0]), sy(q[1])) for q in Tt[i]], fill=(g, g, g + 6))
        for p in sorted(e['parts'], key=lambda q: q['c'][2]):
            if p['what'] not in ('eng', 'holder', 'core', 'tvc'):
                continue
            x, y, z = p['c']
            # 零件的 8 个角投到后视图上：外框
            Rm = np.array(p['R']).reshape(3, 3)
            s = np.array(p['s']) / 2
            corners = np.array([[a, b, c] for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]) * s
            P = corners @ Rm.T + np.array([x, y, z])
            col = {'eng': (40, 110, 255), 'holder': (255, 140, 0), 'core': (255, 40, 40), 'tvc': (0, 170, 90)}[p['what']]
            xs, ys = [sx(q[0]) for q in P], [sy(q[1]) for q in P]
            dr.rectangle([min(xs), min(ys), max(xs), max(ys)], outline=col, width=1)
        for q in noz:
            dr.ellipse([sx(q[0] - q[3]), sy(q[1] + q[3]), sx(q[0] + q[3]), sy(q[1] - q[3])], outline=(200, 0, 200), width=2)
        img.save(os.path.join(OUT, '%s_rear.png' % aid))
print('全部通过' if bad == 0 else ('不对 %d 型' % bad))
sys.exit(1 if bad else 0)
