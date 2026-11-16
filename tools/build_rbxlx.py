#!/usr/bin/env python3
# 把 src/ 拼成 RobloxTotalBattlefield.rbxlx（和 tools/build.luau 一样的结果，不用装 Lune）：
#   目录 = Folder；X.lua = ModuleScript；X.server.lua = Script；X.client.lua = LocalScript；
#   目录里有 init.server.lua / init.client.lua / init.lua 时，这个目录本身就是那个脚本，其余文件是它的子模块
# 用法（仓库根目录）：python3 tools/build_rbxlx.py [输出文件，默认 RobloxTotalBattlefield.rbxlx]
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'RobloxTotalBattlefield.rbxlx')
SRC = os.path.join(ROOT, 'src')
count = {'Script': 0, 'LocalScript': 0, 'ModuleScript': 0, 'Folder': 0}
ref = [0]


def kind_of(name):
    if name.endswith('.server.lua'):
        return 'Script', name[:-len('.server.lua')]
    if name.endswith('.client.lua'):
        return 'LocalScript', name[:-len('.client.lua')]
    if name.endswith('.lua'):
        return 'ModuleScript', name[:-len('.lua')]
    return None, None


def cdata(s):
    # 源码里万一有 ]]>：拆成两段 CDATA
    return '<![CDATA[' + s.replace(']]>', ']]]]><![CDATA[>') + ']]>'


class Item:
    def __init__(self, cls, name, source=None, props=None):
        self.cls, self.name, self.source, self.props, self.kids = cls, name, source, props or [], []

    def find(self, name):
        for k in self.kids:
            if k.name == name:
                return k
        return None

    def xml(self, ind):
        ref[0] += 1
        p = '  ' * ind
        lines = [f'{p}<Item class="{self.cls}" referent="{ref[0]}">', f'{p}  <Properties>', f'{p}    <string name="Name">{escape(self.name)}</string>']
        if self.source is not None:
            lines.append(f'{p}    <ProtectedString name="Source">{cdata(self.source)}</ProtectedString>')
        for t, n, v in self.props:
            lines.append(f'{p}    <{t} name="{n}">{v}</{t}>')
        lines.append(f'{p}  </Properties>')
        for k in self.kids:
            lines.append(k.xml(ind + 1))
        lines.append(f'{p}</Item>')
        return '\n'.join(lines)


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def build(d, parent):
    for name in sorted(os.listdir(d)):
        path = os.path.join(d, name)
        if os.path.isdir(path):
            inst = None
            for init in ('init.server.lua', 'init.client.lua', 'init.lua'):
                if os.path.isfile(os.path.join(path, init)):
                    cls, _ = kind_of(init)
                    inst = Item(cls, name, read(os.path.join(path, init)))
                    count[cls] += 1
                    break
            if inst is None:
                # StarterPlayer 下面这两个是专门的类（普通 Folder 里的脚本不会复制给玩家）
                special = name in ('StarterPlayerScripts', 'StarterCharacterScripts') and parent.cls == 'StarterPlayer'
                inst = parent.find(name)
                if inst is None:
                    inst = Item(name if special else 'Folder', name)
                    if not special:
                        count['Folder'] += 1
                    parent.kids.append(inst)
            elif inst not in parent.kids:
                parent.kids.append(inst)
            build(path, inst)
        elif not name.startswith('init.'):
            cls, base = kind_of(name)
            if cls:
                parent.kids.append(Item(cls, base, read(path)))
                count[cls] += 1


services = []
for svc in sorted(os.listdir(SRC)):
    it = Item(svc, svc)
    build(os.path.join(SRC, svc), it)
    services.append(it)
by = {s.name: s for s in services}
# 不是脚本的东西：放导入模型的文件夹、关掉流式加载、光照（Future 只能写进地图文件）
rs = by.setdefault('ReplicatedStorage', Item('ReplicatedStorage', 'ReplicatedStorage'))
if rs not in services:
    services.append(rs)
for f in ('UnitModels',):
    if not rs.find(f):
        rs.kids.append(Item('Folder', f))
services.append(Item('Workspace', 'Workspace', props=[('bool', 'StreamingEnabled', 'false')]))
services.append(Item('Lighting', 'Lighting', props=[('float', 'Brightness', '3'), ('float', 'ClockTime', '14.6'), ('float', 'EnvironmentDiffuseScale', '1'),
                                                    ('float', 'EnvironmentSpecularScale', '1'), ('bool', 'GlobalShadows', 'true'), ('token', 'Technology', '4')]))
body = '\n'.join(s.xml(1) for s in services)
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('<roblox version="4">\n' + body + '\n</roblox>\n')
print(f"写好了 {os.path.relpath(out, ROOT)}：Script {count['Script']}、LocalScript {count['LocalScript']}、ModuleScript {count['ModuleScript']}、Folder {count['Folder']}")
