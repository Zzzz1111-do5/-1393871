# 多语言译文包（用户 11-28「多语言做一下」）：tools/i18n/source.json + tools/i18n/tr/*.tsv → src/ReplicatedStorage/LangPacks/<代码>.lua
#   python3 -I tools/i18n/build.py（在仓库根目录跑；先跑 extract.py；繁中要 pip install opencc-python-reimplemented）
#   · 日、韩、俄、德、法、西、葡：tr/*.tsv 每行「英文原文⟫日⟫韩⟫俄⟫德⟫法⟫西⟫葡」（⟫ 分隔：游戏的字里不会有；按英文原文对上，不按编号——
#     extract.py 重新抽了、顺序变了也不串；换行写成两个字符 \n；前后的空格照原文留着；空的那一格游戏里用英文）
#     → k[键] = 译文（Lang.lua 的键）、p[英文] = 译文（代码里的 G.L 对照）；代码里已经没有的原文打出来（过期），还没翻的条数也打出来
#   · 繁中：OpenCC s2twp（台湾用词：设置 → 設定、鼠标 → 滑鼠……）从简体转：k[键]、p[简体原文]
#   检查：{1} {2} 这种参数、<b> 这种富文本标签要和英文一样，不一样的这一条不收（游戏里退回英文）、打出来
#   · 按键给的译文：一行开头写「@键」（「@ammo.t.ap⟫徹甲弾⟫……」）只给这一个键（英文原文和别的键撞了也不串：
#     「AP」「HE」别处是一个字的小牌子，弹种全称要写整个词）；按键的盖过按英文对上的
import glob, json, os, re, sys

ROOT = os.getcwd()
SRC = json.load(open(os.path.join(ROOT, 'tools', 'i18n', 'source.json'), encoding='utf-8'))
OUTD = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'LangPacks')
LANGS = ['ja', 'ko', 'ru', 'de', 'fr', 'es', 'pt']
strings = SRC['strings']


def unesc(s):   # \n \t \\ → 换行、制表、反斜杠
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            out.append({'n': '\n', 't': '\t', '\\': '\\'}.get(s[i + 1], '\\' + s[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def lua_q(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif o < 32:
            out.append('\\%03d' % o)
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


PH = re.compile(r'\{\d+\}')
TAG = re.compile(r'</?[a-zA-Z][^>]*>')
FMT = re.compile(r'%[-+#0-9.]*[dsfxXgq%]')   # string.format 的 %d %s %.1f：个数、顺序都要一样


def same_marks(en, tx):
    return (sorted(PH.findall(en)) == sorted(PH.findall(tx)) and len(TAG.findall(en)) == len(TAG.findall(tx))
            and FMT.findall(en) == FMT.findall(tx))


def write_pack(code, K, P, note):
    os.makedirs(OUTD, exist_ok=True)
    lines = ['-- 自动生成（tools/i18n/build.py），别手改：%s 的译文（%s）' % (code, note),
             '--   k：Lang.lua 的键 → 译文；p：代码里的中英对照（G.L）→ 译文（繁中按简体原文查，别的语言按英文原文查）；缺的游戏里退回英文 / 简体',
             'return {', '  k = {']
    for k in sorted(K):
        lines.append('    [%s] = %s,' % (lua_q(k), lua_q(K[k])))
    lines += ['  },', '  p = {']
    for k in sorted(P):
        lines.append('    [%s] = %s,' % (lua_q(k), lua_q(P[k])))
    lines += ['  },', '}']
    open(os.path.join(OUTD, code + '.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')


# 日韩俄德法西葡
TR = {l: {} for l in LANGS}
TRK = {l: {} for l in LANGS}   # 按键给的（「@键」那种行）
bad, stale = [], []
KNOWN = set(strings)
KEYED = {e['key']: e for e in SRC['keyed']}
for fn in sorted(glob.glob(os.path.join(ROOT, 'tools', 'i18n', 'tr', '*.tsv'))):
    for ln, line in enumerate(open(fn, encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line.strip() or line.startswith('#'):
            continue
        cols = line.split('⟫')
        if len(cols) != 1 + len(LANGS):
            bad.append('%s:%d 列数 %d' % (os.path.basename(fn), ln, len(cols)))
            continue
        if cols[0].startswith('@'):
            key = cols[0][1:]
            ent = KEYED.get(key)
            if not ent:
                stale.append('%s:%d 键 %r' % (os.path.basename(fn), ln, key))
                continue
            for l, tx in zip(LANGS, cols[1:]):
                tx = unesc(tx)
                if not tx:
                    continue
                if not same_marks(ent['en'], tx):
                    bad.append('%s:%d %s 参数 / 标签对不上：%r → %r' % (os.path.basename(fn), ln, l, key, tx[:60]))
                    continue
                TRK[l][key] = tx
            continue
        en = unesc(cols[0])
        if en not in KNOWN:
            stale.append('%s:%d %r' % (os.path.basename(fn), ln, en[:60]))
            continue
        for l, tx in zip(LANGS, cols[1:]):
            tx = unesc(tx)
            if not tx:
                continue
            if not same_marks(en, tx):
                bad.append('%s:%d %s 参数 / 标签对不上：%r → %r' % (os.path.basename(fn), ln, l, en[:60], tx[:60]))
                continue
            TR[l][en] = tx
for l in LANGS:
    tr = TR[l]
    K = {e['key']: tr[e['en']] for e in SRC['keyed'] if e['en'] in tr}
    K.update(TRK[l])
    P = {e['en']: tr[e['en']] for e in SRC['pairs'] if e['en'] in tr}
    write_pack(l, K, P, '%d / %d 条' % (len(tr), len(strings)))
    print('%s：%d / %d 条（键 %d、对照 %d）' % (l, len(tr), len(strings), len(K), len(P)))

# 繁中
try:
    from opencc import OpenCC
    cc = OpenCC('s2twp')
    K = {e['key']: cc.convert(e['zh']) for e in SRC['keyed'] if e['zh']}
    P = {e['zh']: cc.convert(e['zh']) for e in SRC['pairs'] if e['zh']}
    write_pack('zh-TW', K, P, 'OpenCC s2twp 从简体转')
    print('zh-TW：键 %d、对照 %d' % (len(K), len(P)))
except ImportError:
    print('没装 opencc-python-reimplemented：繁中没生成')
for b in bad[:40]:
    print('  不收：' + b)
if len(bad) > 40:
    print('  ……还有 %d 条' % (len(bad) - 40))
for b in stale[:20]:
    print('  过期（代码里已经没有这句英文）：' + b)
if len(stale) > 20:
    print('  ……还有 %d 条过期的' % (len(stale) - 20))
miss = [e for e in strings if e not in TR['ja']]
print('还没翻的 %d 条（游戏里用英文；型号、代号这种本来就不用翻）' % len(miss))
