# 多语言（用户 11-28「多语言做一下」）：把要翻译的字全抽出来 → tools/i18n/source.json
#   python3 -I tools/i18n/extract.py（在仓库根目录跑；要 lua5.4）
#   ① Lang.lua 的 add(键, 中文, 英文)：用 lua5.4 载入 Lang.lua 拿到完整的中英表（表里拼出来的键也有），按文件里出现的顺序排（翻译时上下文连着）
#   ② 代码里的中英对照字面量：G.L("中", "英")、各文件自己的 L("中", "英")（L 是对照小函数的文件）、Interior.lua 的 T("中", "英")
#   ③ 数据表里的中英字段：zh = "中", en = "英" / name = "中", en = "英" / dz = "中", de = "英"；两个字符串的小表 { "中文", "English" }
#   不翻的：英文里没有两个以上连着的字母（数字、符号、单个字母）；InteriorScreens.lua（座舱屏幕按飞机国别写中 / 英，不跟语言走）
#   输出：{ keyed: [ { key, zh, en } … ], pairs: [ { zh, en, files } … ], strings: [ 英文原文 … ]（去重、要翻的）}
import json, os, re, subprocess, sys

ROOT = os.getcwd()
SRC = os.path.join(ROOT, 'src')
OUT = os.path.join(ROOT, 'tools', 'i18n', 'source.json')
LANG = os.path.join(SRC, 'ReplicatedStorage', 'Lang.lua')

DUMP = r'''
local L = dofile(arg[1])
local function esc(s) return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n")) end
for k, zh in pairs(L.zh) do io.write(esc(k), "\t", esc(zh), "\t", esc(L.en[k]), "\n") end
for k, en in pairs(L.en) do if L.zh[k] == nil then io.write(esc(k), "\t\t", esc(en), "\n") end end
'''


def unesc(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '\\': '\\'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def lua_str(s):   # Lua 字面量（双引号里的）→ 真的字符串
    return unesc(s)


def needs(en):
    return bool(en) and re.search(r'[A-Za-z]{2,}', en) is not None


tmp = os.path.join(ROOT, 'tools', 'i18n', '.dump.lua')
open(tmp, 'w', encoding='utf-8').write(DUMP)
r = subprocess.run(['lua5.4', tmp, LANG], capture_output=True, text=True, check=True)
os.remove(tmp)
ZH, EN = {}, {}
for line in r.stdout.split('\n'):
    if not line:
        continue
    k, zh, en = line.split('\t')
    k = unesc(k)
    ZH[k], EN[k] = unesc(zh), unesc(en)
# 文件里的顺序
order = []
seen = set()
for m in re.finditer(r'\badd\(\s*"((?:[^"\\]|\\.)*)"', open(LANG, encoding='utf-8').read()):
    k = lua_str(m.group(1))
    if k in EN and k not in seen:
        order.append(k)
        seen.add(k)
for k in sorted(EN):
    if k not in seen:
        order.append(k)
        seen.add(k)
keyed = [{'key': k, 'zh': ZH.get(k, ''), 'en': EN.get(k, '')} for k in order]

S = r'"((?:[^"\\\n]|\\.)*)"'
PATS = [
    re.compile(r'\bG\.L\(\s*' + S + r'\s*,\s*' + S + r'\s*\)'),
    re.compile(r'\bzh\s*=\s*' + S + r'\s*,\s*en\s*=\s*' + S),
    re.compile(r'\bname\s*=\s*' + S + r'\s*,\s*en\s*=\s*' + S),
    re.compile(r'\bdz\s*=\s*' + S + r'\s*,\s*de\s*=\s*' + S),
]
PAT_L = re.compile(r'\bL\(\s*' + S + r'\s*,\s*' + S + r'\s*\)')
PAT_T = re.compile(r'\bT\(\s*' + S + r'\s*,\s*' + S + r'\s*\)')
PAT_TAB = re.compile(r'\{\s*' + S + r'\s*,\s*' + S + r'\s*\}')
CJK = re.compile(r'[\u3400-\u9fff]')
pairs = {}
for dp, dn, fn in os.walk(SRC):
    for f in sorted(fn):
        if not f.endswith('.lua') or f in ('Lang.lua', 'InteriorScreens.lua') or dp.endswith('LangPacks'):
            continue
        p = os.path.join(dp, f)
        s = open(p, encoding='utf-8').read()
        rel = os.path.relpath(p, SRC)
        found = []
        for P in PATS:
            found += [(m.group(1), m.group(2)) for m in P.finditer(s)]
        if re.search(r'local (function L\(|L = function\()', s):
            found += [(m.group(1), m.group(2)) for m in PAT_L.finditer(s)]
        if f == 'Interior.lua':
            found += [(m.group(1), m.group(2)) for m in PAT_T.finditer(s)]
        for m in PAT_TAB.finditer(s):   # { "中文", "English" }：第一个有汉字、第二个没有
            a, b = m.group(1), m.group(2)
            if CJK.search(a) and not CJK.search(b):
                found.append((a, b))
        for zh, en in found:
            zh, en = lua_str(zh), lua_str(en)
            if CJK.search(en) or not CJK.search(zh + 'x') and zh == en:
                continue
            e = pairs.setdefault(en, {'zh': zh, 'en': en, 'files': []})
            if rel not in e['files']:
                e['files'].append(rel)
pairs = sorted(pairs.values(), key=lambda e: (e['files'][0], e['en']))
strings, seen = [], set()
for e in keyed + pairs:
    en = e['en']
    if needs(en) and en not in seen:
        strings.append(en)
        seen.add(en)
json.dump({'keyed': keyed, 'pairs': pairs, 'strings': strings}, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print('键 %d、对照 %d、要翻的英文（去重）%d 条 / %d 字' % (len(keyed), len(pairs), len(strings), sum(len(x) for x in strings)))
