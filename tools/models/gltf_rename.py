# Sketchfab 下载的 glTF 节点名是乱码（U+FFFD，作者用俄文名、导出时丢了编码）：节点改名成 n<序号>_<原名里的 ASCII 部分>，另存一份 .gltf
#   （贴图、.bin 照旧在同一目录），blveh.json 里按新名字写分组（BMP-1，用户 11-25「需要模型自己找」）
#   用法：python3 -I tools/models/gltf_rename.py <原 scene.gltf> <新 .gltf>
import json, sys, re
src, dst = sys.argv[1], sys.argv[2]
J = json.load(open(src, encoding='utf-8'))
for i, n in enumerate(J.get('nodes', [])):
    nm = n.get('name', '')
    if any(ord(c) > 127 for c in nm):
        a = re.sub(r'[^\x20-\x7e]', '', nm).strip()
        n['name'] = 'n%d_%s' % (i, a)
for i, m in enumerate(J.get('meshes', [])):
    nm = m.get('name', '')
    if any(ord(c) > 127 for c in nm):
        m['name'] = 'm%d' % i
json.dump(J, open(dst, 'w', encoding='utf-8'))
print('改名完', src, '→', dst)
