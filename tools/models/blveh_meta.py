# tools/models/blveh.py 的分组结果 → src/ReplicatedStorage/ImportedMeta.lua：模型键那一行、alias（游戏里的型号 → 这个模型键）、
#   old（型号 → 旧模型键：没重新导入新 GLB 的照旧用旧模型，客户端 VehModels.importedFor 按 alias、old 的顺序找）
#   用法（仓库根目录）：python3 -I tools/models/blveh_meta.py <模型键> <分组结果 .json>
#   blveh.json[<模型键>] 里：credit 署名、alias [型号…]、old 旧模型键
#   mdl2glb.py 重新生成元数据时照旧保留 blveh.json 里这些模型键的行、alias、old（见 mdl2glb.py 末尾）
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mdl2glb as B   # noqa: E402  lua()、old_lines()

META = 'src/ReplicatedStorage/ImportedMeta.lua'


def parse_map(line):
    """'  alias = { a = "b", … },' → dict"""
    return dict(re.findall(r'(\w+) = "([^"]*)"', line))


def main():
    key, repf = sys.argv[1], sys.argv[2]
    CFG = json.load(open(os.path.join(HERE, 'blveh.json'), encoding='utf-8'))[key]
    rep = json.load(open(repf, encoding='utf-8'))
    info = {k: rep[k] for k in ('parts', 'wheels', 'tur', 'gun', 'muz', 'hull', 'w', 'h', 'len', 'src') if k in rep}
    for name, p in rep.get('pts', {}).items():
        if name == 'sight':
            info['sight'] = p   # 炮长主瞄准镜的镜头（VehDefs 照它摆瞄准镜视角）
        else:
            info.setdefault('pts', {})[name] = p
    info['credit'] = CFG['credit']
    if any(p.get('k') == 'int' for p in info['parts'].values()):
        info['int'] = True   # 原模型自带车内（Interior 用模型自己的内饰）
    line = '    %s = %s,\n' % (key, B.lua(info))
    src = open(META, encoding='utf-8').read().split('\n')
    out, done, have_old = [], False, False
    in_m = False
    for ln in src:
        if ln.startswith('  alias = {'):
            al = parse_map(ln)
            for a in CFG.get('alias', []):
                al[a] = key
            out.append('  alias = ' + B.lua(al) + ',')
            continue
        if ln.startswith('  old = {'):
            od = parse_map(ln)
            if CFG.get('old'):
                for a in CFG.get('alias', []):
                    od[a] = CFG['old']
            out.append('  old = ' + B.lua(od) + ',')
            have_old = True
            continue
        if ln.startswith('  m = {'):
            if not have_old and CFG.get('old'):
                out.append('  old = ' + B.lua({a: CFG['old'] for a in CFG.get('alias', [])}) + ',')
                have_old = True
            in_m = True
            out.append(ln)
            continue
        if in_m and ln.startswith('  },'):
            if not done:
                out.append(line.rstrip('\n'))
                done = True
            in_m = False
            out.append(ln)
            continue
        if in_m and ln.startswith('    %s = {' % key):
            out.append(line.rstrip('\n'))
            done = True
            continue
        out.append(ln)
    s = '\n'.join(out)
    if '--     old：' not in s:   # 文件头的说明补一行
        s = s.replace('return {\n', '--     old：游戏里的型号 → 旧模型键（alias 那个模型没导入时退回旧的，tools/models/blveh_meta.py）；int：原模型自带车内（块的 k = "int"）；'
                      'src：原模型 glTF 坐标 → 这里的坐标（tools/models/blveh.py）；pts：原模型上量的点（格）\nreturn {\n', 1)
    open(META, 'w', encoding='utf-8').write(s)
    print('写好了 %s：%s（%d 块）；alias %s → %s；old → %s' % (META, key, len(info['parts']), CFG.get('alias'), key, CFG.get('old')))


if __name__ == '__main__':
    main()
