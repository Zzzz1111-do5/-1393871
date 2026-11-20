# 只转一个飞机模型（不动别的已经导入过的 GLB、元数据里别的模型那几行原样留着）：
#   python3 -I tools/models/air_one.py <网页版目录（js/mdl/<键>.js 在里面）> <AirDefs 的 JSON> <模型键> [输出目录，默认 models/air] [元数据，默认 src/ReplicatedStorage/ImportedAir.lua]
#   AirDefs 的 JSON：lune run tools/models/airdefs.luau > airdefs.json
#   和 air2glb.py 一样转（同一套表：ALIAS、LIFT、FOLD、air_anim 的 PIT / SURF / GEAR），只是只写这一个模型：
#     models/air/<键>.glb、元数据里 m[导入后的键] 换成新的，alias 里用这个模型的型号指过来；
#     这个型号原来用的模型（没导入新模型的人还在用）挪进 old，排在最前面，游戏找不到新的就用它
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl2glb as B   # noqa: E402
import air2glb as X   # noqa: E402

B.WEB = sys.argv[1]
AD = json.load(open(sys.argv[2], encoding='utf-8'))
key = sys.argv[3]
OUTDIR = sys.argv[4] if len(sys.argv) > 4 else 'models/air'
META = sys.argv[5] if len(sys.argv) > 5 else 'src/ReplicatedStorage/ImportedAir.lua'

ids = [i for i, v in X.ALIAS.items() if v.rstrip('~') == key]
if not ids:
    raise SystemExit('ALIAS 里没有型号用 ' + key)
anim = key in X.A.SURF or key in X.A.GEAR
kname = key + X.VERK.get(key, X.VER) if anim else key
meta, binb, info, out = X.convert(key, AD, ids)
path = os.path.join(OUTDIR, key + '.glb')
B.write_glb(kname, meta, binb, info, out, path, prefix='A_')
tris = sum(len(o[6]) for o in out)
print('%s：%d 个三角形、%d 块，长 %.1f 翼展 %.1f 高 %.1f 格，%.1f MB → %s' % (kname, tris, len(out), info['len'], info['w'], info['h'], os.path.getsize(path) / 1e6, path))

# 元数据：读原来的，改这个模型、这几个型号，其余原样
src = open(META, encoding='utf-8').read()
old = B.old_lines(META)   # 模型键 → 原来那一行（整块）
m_alias = re.search(r'\n  alias = (\{.*?\}),\n  old = ', src, re.S)
m_old = re.search(r'\n  old = (\{.*?\}),\n  m = \{\n', src, re.S)
if not m_alias or not m_old:
    raise SystemExit('元数据格式不认识：' + META)


def parse_tbl(t):   # { a = "x", b = { "y", "z" } } → dict（只认这两种值）
    out_ = {}
    for k, v in re.findall(r'([a-z0-9_]+) = ("[^"]*"|\{[^}]*\})', t):
        out_[k] = v.strip('"') if v.startswith('"') else re.findall(r'"([^"]*)"', v)
    return out_


alias = parse_tbl(m_alias.group(1))
oldt = parse_tbl(m_old.group(1))
for i in ids:
    prev = alias.get(i)
    keep = [x for x in ([prev] if prev else []) + list(oldt.get(i, [])) if x and x.rstrip('~') != kname]
    if keep:
        oldt[i] = list(dict.fromkeys(keep))
    alias[i] = kname
old[kname] = '    %s = %s,\n' % (kname, B.lua(info))
head = src[:m_alias.start()]
body = '\n  alias = ' + B.lua(alias) + ',\n  old = ' + B.lua(oldt) + ',\n  m = {\n'
for k in sorted(old):
    line = old[k]
    body += line if line.endswith('\n') else line + '\n'
body += '  },\n}\n'
open(META, 'w', encoding='utf-8').write(head + body)
print('元数据：%s 的 alias → %s，old → %s' % ('、'.join(ids), kname, {i: oldt.get(i) for i in ids}))

# 署名：credits.txt 里这一个模型的那一行换掉 / 加上
cred = os.path.join(OUTDIR, 'credits.txt')
if os.path.exists(cred):
    lines = open(cred, encoding='utf-8').read().split('\n')
    name = {'j15t': '歼-15T', 'f22a': 'F-22A'}.get(key, key)
    entry = '- %s（%s.glb）：%s' % (name, key, info.get('credit', ''))
    tag = '（%s.glb）' % key
    for n, ln in enumerate(lines):
        if tag in ln:
            lines[n] = entry
            break
    else:
        while lines and lines[-1] == '':
            lines.pop()
        lines.append(entry)
        lines.append('')
    open(cred, 'w', encoding='utf-8').write('\n'.join(lines))
    print('署名：' + entry[:120])
