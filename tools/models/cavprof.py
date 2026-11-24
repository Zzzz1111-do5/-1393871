# 看挖出来的内腔多大：解 CavityMeta 里某型的地板 / 顶高度表，按内饰用的米（相对座圈中心）打印中线剖面和几个横剖面
#   python3 -I tools/models/cavprof.py src/ReplicatedStorage/CavityMeta.lua <模型键> <ImportedMeta 的 tur：x,y,z（格）> [空间 Hull / Tur] [横剖的 z（米）,…]
import re, sys, base64
src, key, piv = sys.argv[1], sys.argv[2], [float(v) for v in sys.argv[3].split(',')]
want = sys.argv[4] if len(sys.argv) > 4 else 'Hull'
S = 2.8
s = open(src).read()
i = s.find(key + ' = {')
j = s.find(want + ' = { g', i)
seg = s[j:j + 40000]
def g(name):
    m = re.search(r'\b' + name + r' = ("([^"]*)"|[-\d.]+)', seg)
    return m.group(2) if m.group(2) is not None else float(m.group(1))
hi, lo = base64.b64decode(g('hi')), base64.b64decode(g('lo'))
nx, nz, x0, z0, d, y0, y1 = int(g('nx')), int(g('nz')), g('x0'), g('z0'), g('d'), g('y0'), g('y1')
def colv(i, k):
    j = i * nz + k
    a = lo[j * 2] + lo[j * 2 + 1] * 256
    b = hi[j * 2] + hi[j * 2 + 1] * 256
    if a == 65535: return None
    return ((y0 + (y1 - y0) * a / 65534 - piv[1]) / S, (y0 + (y1 - y0) * b / 65534 - piv[1]) / S)
print('%s %s：%d × %d 列，每列 %.3f 米' % (key, want, nx, nz, d / S))
# 中线（x = 0）前后剖面
i0 = round((piv[0] - x0) / d)
print('中线 x=0：z(米)  地板  顶')
for k in range(nz):
    c = colv(i0, k)
    if c: print('  z %+.2f  %+.2f  %+.2f' % ((z0 + k * d - piv[2]) / S, c[0], c[1]))
for zm in [float(v) for v in (sys.argv[5].split(',') if len(sys.argv) > 5 else ['-2.6', '-2.2', '-1.8', '-1.2', '-0.3', '0.6'])]:
    k = round((zm * S + piv[2] - z0) / d)
    row = []
    for i in range(nx):
        c = colv(i, k)
        if c: row.append('%+.2f:%+.2f/%+.2f' % ((x0 + i * d - piv[0]) / S, c[0], c[1]))
    print('z %+.2f 横剖（x:地板/顶）：' % zm, ' '.join(row[::2]))
