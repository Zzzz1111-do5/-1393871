# Roblox全面大战场

Roblox Total Battlefield —— 百人同服的攻防登岛战。原来的「军事大亨」已经整个换掉。

- 进服后系统随机把人分成进攻方、防守方（人数相当，中途进来的补到人少的一方）。
- 每次出生前选兵种（步枪兵、狙击手、反坦克兵、防空兵、医疗兵、工兵、迫击炮手、特种兵、观察员；主枪都是 M4，狙击手另有狙击枪）和出生点；阵亡几秒后能复活。
- 第一人称：镜头前是真 M4（拔枪、换弹、开镜、后坐都有动作）和 Roblox 方块手臂；V 切第三人称。
- 地图是一片大海和几个岛：主岛「棕榈岛」、前哨岛、灯塔岛、西礁岛，南边海上是攻方舰队和攻方机场岛。
- 5 个据点（A 前哨岛、B 灯塔岛、C 港口镇、D 机场、E 指挥所）开局都归守方。攻方全部拿下就赢；时间到（20 分钟，每拿下一个 +3 分钟）守方手里还有任何一个，守方赢。
- 守方的机枪碉堡、岸防炮、高炮、榴弹炮和滩头的钢刺猬、铁丝网、雷区都是地图自带的；炮没人管时 AI 打，自己队的人走过去按 E 就能接手。
- 攻方从舰队甲板出生，或者坐登陆艇抢滩、伞降、在拿下的据点出生；守方在北岸营地或还没被压住的据点出生。
- 中英双语，按系统语言自动选，部署界面右上角能切。

方案、规则细节和进度：[docs/island_assault_plan.md](docs/island_assault_plan.md)。现在是 1.0-alpha：回合、分队、部署、步兵武器（第一人称）、登陆艇、据点、胜负、界面、机器人（人不够时每队补到 18 人）、地面载具（坦克、装甲车、防空、火炮）、守方工事已经能玩；直升机、飞机、舰艇还在做。

## 直接玩

1. 用 Roblox Studio 打开 `RobloxTotalBattlefield.rbxlx`。
2. 「测试 → 开始游戏」。开服先生成地形，要几秒（屏幕上有进度）。
3. 多人：「测试」页选「服务器 + 几个玩家」一起开，人会被随机分到两边。

操作：WASD 移动，鼠标左键开火，右键开镜（狙击镜），R 换弹，1～4 切武器，V 第一 / 第三人称，E 上车 / 操作工事（F 离开），F 观察员呼叫炮击，Tab 战况表。手机上有开火、瞄准、换弹按钮。

开载具：部署界面左上角切到「载具」页签，选型号和出生点（攻方：海滩、拿下的据点；守方：营地、还在手里的据点）。
WASD 驾驶，鼠标瞄准（炮塔跟着转，有回转速度），左键开火，1 / 2 换武器，X 烟幕弹，右键 / V 炮长瞄准镜（滚轮 / Z 换倍率），N 切换昼光 / 夜视 / 热成像白热 / 黑热，F 下车，E 上车。

## 发布到 Roblox

1. 「文件 → 发布到 Roblox」（Alt + P），选「创建新体验」，类型选「战斗」；设备勾电脑、手机、平板。
2. 「主页 → 游戏设置」：
   - 「地点」：最多玩家数设成 **100**（上限 200）。Studio 里找不到的话，到 create.roblox.com → 你的体验 → 地点 → 配置。
   - 「安全」：打开「允许 Studio 访问 API 服务」，Studio 里测试也能存档（军衔、经验、战绩）；打开 Mesh / Image API（第一人称的真 M4 是开局用 EditableMesh 生成的，不开就退回零件拼的）。
   - 或者在 Studio 里「导入 3D」`models/fps_m4.glb`，放进 `ReplicatedStorage/Imported/FPS_M4`，第一人称就用导入的原模型。
   - 「权限」：改成公开。第一次公开前要在 create.roblox.com 上填「内容成熟度问卷」。
3. 以后更新：再「发布到 Roblox」覆盖线上版本；开着的服务器要到 create.roblox.com → 地点 →「⋯」→ 重启服务器。
4. `promo/` 里的图标和宣传图还是大亨版的，新玩法做完后重做。

## 换上装备的原模型（`models/veh/`）

不导入的话车是零件拼的。`models/veh/<模型键>.glb` 是网页版的装备模型原样转的：最精细的网格（不减面）、原贴图和法线 / 金属粗糙度贴图、真实尺寸（1 米 = 2.8 格），每个模型一个文件，20 个覆盖全部地面载具。

1. Studio「主页 → 导入 3D」，选 `models/veh/` 里的 GLB（一次选一个或几个都行），导入设置用默认的（别勾「合并网格」），导进 Workspace 就行。
2. 开服时自动收进 `ReplicatedStorage/Imported/Veh/<模型键>`（输出里有一行「用上了导入的装备模型：…」）；想先整理好也可以自己拖进去，名字别改（`V_<模型键>__<块>`）。
3. 导入了的型号游戏里自动换上：炮塔、炮管按原模型的转轴转，车轮各自有悬架、跟着转，打爆后烧黑。哪个型号用哪个模型见 `src/ReplicatedStorage/ImportedMeta.lua` 的 `alias`。

重新转换（要网页版仓库）：`python3 -I tools/models/mdl2glb.py <网页版仓库目录>`。模型都是 CC-BY，署名在 `models/veh/credits.txt`（发布时放进游戏简介或游戏里的致谢）。

## 改代码

- 脚本都在 `src/`，目录和 Rojo 的约定一样：
  - `src/ReplicatedStorage/`：`Config.lua`（数值：回合、占领、兵种、武器、载具名额、机器人、得分、军衔）、`Lang.lua`（中英文字）、`Map.lua`（地形高度、岛、据点、海滩、舰队位置，服务器和客户端算出来一样）。
  - `src/ReplicatedStorage/VehDefs.lua`：地面载具的型号数据（尺寸、速度、炮塔、武器、负重轮 / 车轮、烟幕弹发射筒、瞄准镜位置）；`ImportedMeta.lua`：原模型各块的位置、转轴（转换脚本生成，别手改）。
  - `src/ServerScriptService/Main/`：服务器（`World` 生成地图、`Round` 回合与据点、`Weapons` 步兵武器、`Ents` 实体与伤害、`Vehicles` 登陆艇与伞降、`Armor` 地面载具、`Bots` 机器人、`Nav` 寻路、`Store` 存档、`Imports` 收导入的模型）。
  - `src/StarterPlayer/StarterPlayerScripts/Client/`：客户端（`UI` 界面、`MapUI` 地图、`Play` 步兵操作与镜头、`Drive` 开载具与瞄准镜、`View` 实体的样子和悬架、`VehModels` 车的样子（原模型或零件拼的）、`Fx` 特效与音效）。
- 生成 rbxlx：装 [Lune](https://github.com/lune-org/lune) **0.11 或更新**，在仓库根目录运行 `lune run tools/build.luau`（默认写 `RobloxTotalBattlefield.rbxlx`）；没有 Lune 用 `python3 tools/build_rbxlx.py`。
- 也可以直接在 Studio 里改脚本；改完之后这里的 `src/` 就不是最新的了。

## 不开 Roblox 也能测（`tools/test/`）

用 Lune 模拟一个 Roblox 服务器加若干客户端（虚拟时钟、远程事件、角色、射线打地形、DataStore）。要 Lune 0.11 以上：老版本里同一个实例每次取出来是不同的对象，没法当表的键。

在仓库根目录运行：

```
lune run tools/build.luau
lune run tools/test/check.luau                        # 语法检查
lune run tools/test/ia_flow.luau RobloxTotalBattlefield.rbxlx  # 流程：开服 → 分队 → 部署 → 开枪击杀 → 复活 → 抢滩 → 占领 → 结算 → 下一局
lune run tools/test/ia_bots.luau RobloxTotalBattlefield.rbxlx 8  # 机器人：一个真人 + 机器人打 8 分钟（补人数、抢滩、交火、占领、耗时）
lune run tools/test/ia_veh.luau RobloxTotalBattlefield.rbxlx     # 载具：部署、开车、悬架、开炮、烟幕弹、瞄准镜四种模式、下车上车、被毁、气垫艇
lune run tools/test/ia_import.luau RobloxTotalBattlefield.rbxlx  # 原模型：假装导入了 M1A2、JLTV，看收模型、拼车、炮塔炮管转轴、车轮悬架、炮口、烧黑
lune run tools/test/ia_boot.luau RobloxTotalBattlefield.rbxlx  # 开服计时（地形生成）
lune run tools/test/ia_balance.luau RobloxTotalBattlefield.rbxlx 6  # 平衡统计：机器人对打几分钟，攻方的兵、登陆艇死在什么上面
lune run tools/test/map_export.luau map.bin 8 && python3 tools/test/map_png.py map.bin map.png   # 画地图俯视图
```

没有 Lune 也能跑一套 Lua 5.4 的模拟测试：`python3 tools/mock/run.py tools/mock/<flow|veh|forts|air|bots|fps>.lua`。两套都要过。

几个会话同时在改这个仓库：分工、规矩和这一轮的协调记录见方案文档的「协作」一节。

渲染、物理、Roblox 自带的镜头和角色控制模拟不了。上线前还是要在 Studio 里实际玩一遍。
