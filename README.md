# 军事大亨（Roblox）

踩按钮盖楼赚钱 → 造兵 → 布阵 → 开战。你本人也上战场：能开枪、开坦克开飞机、放支援技能。
之后升级科技、重生，还能和别的玩家约战、打排位。

## 直接玩

1. 用 Roblox Studio 打开 `MilitaryTycoon.rbxlx`。
2. 点「测试 → 开始游戏」。

左上角「当前目标」会告诉你下一步做什么，地上的绿色箭头指路。左边是小地图，上面是战场。

## 把 24 个兵种的 3D 模型导进去（做一次就行）

没导入也能玩，只是兵种用零件拼的方块模型。模型要上传到你自己的 Roblox 账号，所以这一步只能在你的 Studio 里做：

1. Studio 顶部「主页（Home）」→「导入 3D（Import 3D）」。
2. 选 `models/all_units.glb`。24 个兵种已经合成了这一个文件。
3. 设置不用改，点「导入（Import）」。模型会出现在场景里。
4. 保存：Ctrl + S，或「文件 → 保存到文件」。

开游戏时，脚本会自动把这些模型认出来，并收进 ServerStorage：
- 导入时 Studio 保不保留层级都没关系，按零件名前缀（`tank__…`）分回各个兵种。
- Output（输出）窗口会打印「用上了导入的原模型：aa、arty……」。
- 想一个一个导也行：`models/` 里有单个兵种的 `tank.glb`、`heli.glb`……

模型都来自 Sketchfab，CC-BY-4.0 授权。署名在 `models/credits.txt` 和游戏里的「致谢」。

## 存档

- 在 Studio 里测试时默认不存档，屏幕上会提示「存档没读到」，正常现象。
- 要存档：先发布游戏，再到「游戏设置 → 安全」打开「允许 Studio 访问 API 服务」。
- 发布后，在线玩家的进度会自动存档。

## 出了问题

- 屏幕上方出现红条，就是脚本出错了。把红条截图发给开发者。
- 一出错的那一步会被跳过，游戏不会整个卡死。

## 0.4 版新内容

- 修卡死：
  - 收入循环、部队移动、战斗推演、结算，任何一步出错都只跳过那一下。原来一出错，整个服务器的收入会停，或者人一直卡在「打仗中」。
  - 开车时如果那辆车还没加载出来，会自动下车。原来角色会一直隐身。
- 战场支援技能：打仗时屏幕下方的按钮，也可以按 Z X V B N。
  - 迫击炮急袭（兵营）、战地急救（指挥部）、炮火覆盖（炮兵阵地）、空投援军（直升机场）、空袭（空军基地）。
- 新兵种 8 个：
  - 医疗兵：给附近的步兵回血。
  - 火焰喷射组：近距离烧一片步兵。
  - 特种小队：伪装，敌人不爱打它。
  - 抢修车：给附近的车修血。
  - 重型坦克。
  - 电子战车：让敌人的导弹打偏。
  - 巡飞弹：一头撞上去，用完就没。
  - 隐身轰炸机：只有爱国者和战斗机打得到。
- 老兵：活下来的部队升星，每星血量和伤害 +15%，会存档。
- 关卡评星；每 5 关有里程碑奖励；首领关有播报。
- 打击反馈：
  - 命中标记、伤害数字、连杀播报、战报滚动条、震屏。
  - 低血量时屏幕边缘泛红。
  - 音效用 Roblox 自带的声音。想换成自己的，在 `Config.Sounds` 里填 `rbxassetid://` 加数字。
- 补给空投：不打仗时基地里会掉补给箱，碰一下就拿钱。
- 地图指引：地上的流动箭头、小地图、路牌、部署区和敌军区的大字。
- 建筑动画：
  - 新盖的楼从地下一层层升起来，带脚手架和扬尘。
  - 雷达转，指示灯闪。
  - 买得起的按钮一呼一吸。

## 改代码

- 脚本都在 `src/`，目录和 Rojo 的约定一样：
  - `src/ReplicatedStorage/Config.lua`：所有数值，包括兵种、建筑、技能、关卡。
  - `src/ServerScriptService/Main/`：服务器。
  - `src/StarterPlayer/StarterPlayerScripts/Client/`：客户端。
- 生成 rbxlx：要先装 [Lune](https://github.com/lune-org/lune)，然后在仓库根目录运行 `lune run tools/build.luau`。
- 也可以直接在 Studio 里改脚本；改完之后，这里的 `src/` 就不是最新的了。
- 重新合并模型包：`python3 tools/merge_glb.py models models/all_units.glb`。

## 不开 Roblox 也能测（`tools/test/`）

用 Lune 模拟一个 Roblox 服务器加客户端。实例和属性都按 Roblox 的 API 检查，远程事件、DataStore 也是模拟的。

在 `tools/test` 目录里运行：

```
lune run flow_old.luau ../../MilitaryTycoon.rbxlx
lune run flow_new.luau ../../MilitaryTycoon.rbxlx
lune run units.luau ../../MilitaryTycoon.rbxlx
lune run visual.luau ../../MilitaryTycoon.rbxlx
lune run import_sim.luau ../../MilitaryTycoon.rbxlx ../../models/all_units.glb
lune run import_sim.luau ../../MilitaryTycoon.rbxlx ../../models/all_units.glb flat
```

- `flow_old`：老功能走一遍（盖楼、造兵、开战、开枪、开车、突袭、约战、重生）。
- `flow_new`：新功能（技能、补给箱、评星、老兵存档、结算出错的保底）。
- `units`：新兵种的机制。
- `visual`：地图指引、建筑动画。
- `import_sim`：模拟导入模型包。

渲染、物理、Roblox 自带的镜头和角色控制模拟不了。上线前还是要在 Studio 里实际玩一遍。
