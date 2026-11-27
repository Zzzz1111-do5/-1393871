# tools/models/sfbld.py 写的元数据（JSON）→ src/ReplicatedStorage/CityMeta.lua（格式同 BuildingMeta）+ 署名 models/bld/city_credits.txt
#   python3 -I tools/models/sfbld_meta.py <meta.json> <CityMeta.lua> <city_credits.txt> [地图名 GLB 名]
#   雪山的房子：python3 -I tools/models/sfbld_meta.py <snow_meta.json> src/ReplicatedStorage/SnowMeta.lua models/bld/snow_credits.txt 雪山 snow.glb
import json, sys

src, out_lua, out_cred = sys.argv[1], sys.argv[2], sys.argv[3]
LABEL = sys.argv[4] if len(sys.argv) > 4 else '钢城'
GLB = sys.argv[5] if len(sys.argv) > 5 else 'city.glb'
WHAT = '房子' if LABEL != '钢城' else '楼房'
M = json.load(open(src, encoding='utf-8'))


def lua(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join('%s = %s' % (k, lua(v[k])) for k in sorted(v)) + ' }'
    if isinstance(v, (list, tuple)):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, float):
        return ('%.3f' % v).rstrip('0').rstrip('.')
    return str(v)


lines = ['-- 自动生成（tools/models/sfbld.py → tools/models/sfbld_meta.py），别手改：%s的写实%s（models/bld/%s，Sketchfab 上 CC-BY-4.0 的模型）的元数据' % (LABEL, WHAT, GLB),
         '--   [键] = { name 中文名, w / h / d 宽、高、深（格，1 米 = 2.8 格）, o 在 GLB 里的原点, parts[块名] = { c 中心, s 大小 }, credit 署名, tris 三角形数 }；',
         '--   坐标 X 右、Y 上、−Z 正面，原点在地面、占地中心；导入后 MeshPart 叫 B_<键>__<块名>（Imports.lua 收进 Imported.Bld，同 BuildingMeta）',
         'return {']
for k in sorted(M):
    m = dict(M[k])
    lines.append('  %s = %s,' % (k, lua(m)))
lines.append('}')
open(out_lua, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
cred = ['%s的写实%s（models/bld/%s）——都是 Sketchfab 上 CC-BY-4.0 授权的模型（http://creativecommons.org/licenses/by/4.0/），' % (LABEL, WHAT, GLB),
        '改动：按真高缩放、换成 Roblox 的格、按材质切块（有的减了面）、贴图缩到最长边 1024；游戏里按地块的大小可能再整体缩放。', '']
for k in sorted(M):
    cred.append('· ' + M[k]['credit'])
open(out_cred, 'w', encoding='utf-8').write('\n'.join(cred) + '\n')
print('写好', out_lua, len(M), '座；', out_cred)
