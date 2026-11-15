# 暗剑：登岛战（Roblox）

Darksword: Island Assault —— 百人同服的攻防登岛战。原来的「军事大亨」已经整个换掉。

- 进服后系统随机把人分成进攻方、防守方（人数相当，中途进来的补到人少的一方）。
- 每次出生前选兵种（步枪兵、机枪手、狙击手、反坦克兵、防空兵、医疗兵、工兵、迫击炮手、特种兵、观察员）和出生点；阵亡几秒后能复活。
- 地图是一片大海和几个岛：主岛「棕榈岛」、前哨岛、灯塔岛、西礁岛，南边海上是攻方舰队和攻方机场岛。
- 5 个据点（A 前哨岛、B 灯塔岛、C 港口镇、D 机场、E 指挥所）开局都归守方。攻方全部拿下就赢；时间到（20 分钟，每拿下一个 +3 分钟）守方手里还有任何一个，守方赢。
- 攻方从舰队甲板出生，或者坐登陆艇抢滩、伞降、在拿下的据点出生；守方在北岸营地或还没被压住的据点出生。
- 中英双语，按系统语言自动选，部署界面右上角能切。

方案、规则细节和进度：[docs/island_assault_plan.md](docs/island_assault_plan.md)。现在是 1.0-alpha：回合、分队、部署、步兵武器、登陆艇、据点、胜负、界面、机器人（人不够时每队补到 18 人）、地面载具（坦克、装甲车、防空、火炮）已经能玩；直升机、飞机、舰艇、实景地图、导入模型还在做。

## 直接玩

1. 用 Roblox Studio 打开 `IslandAssault.rbxlx`。
2. 「测试 → 开始游戏」。开服先生成地形，要几秒（屏幕上有进度）。
3. 多人：「测试」页选「服务器 + 几个玩家」一起开，人会被随机分到两边。

操作：WASD 移动，鼠标左键开火，右键瞄准（狙击镜），R 换弹，1～4 切武器，F 观察员呼叫炮击，Tab 战况表。手机上有开火、瞄准、换弹按钮。

开载具：部署界面左上角切到「载具」页签，选型号和出生点（攻方：海滩、拿下的据点；守方：营地、还在手里的据点）。
WASD 驾驶，鼠标瞄准（炮塔跟着转，有回转速度），左键开火，1 / 2 换武器，X 烟幕弹，右键 / V 炮长瞄准镜（滚轮 / Z 换倍率），N 切换昼光 / 夜视 / 热成像白热 / 黑热，F 下车，E 上车。

## 发布到 Roblox

1. 「文件 → 发布到 Roblox」（Alt + P），选「创建新体验」，类型选「战斗」；设备勾电脑、手机、平板。
2. 「主页 → 游戏设置」：
   - 「地点」：最多玩家数设成 **100**（上限 200）。Studio 里找不到的话，到 create.roblox.com → 你的体验 → 地点 → 配置。
   - 「安全」：打开「允许 Studio 访问 API 服务」，Studio 里测试也能存档（军衔、经验、战绩）。
   - 「权限」：改成公开。第一次公开前要在 create.roblox.com 上填「内容成熟度问卷」。
3. 以后更新：再「发布到 Roblox」覆盖线上版本；开着的服务器要到 create.roblox.com → 地点 →「⋯」→ 重启服务器。
4. `promo/` 里的图标和宣传图还是大亨版的，新玩法做完后重做。

## 改代码

- 脚本都在 `src/`，目录和 Rojo 的约定一样：
  - `src/ReplicatedStorage/`：`Config.lua`（数值：回合、占领、兵种、武器、载具名额、机器人、得分、军衔）、`Lang.lua`（中英文字）、`Map.lua`（地形高度、岛、据点、海滩、舰队位置，服务器和客户端算出来一样）。
  - `src/ReplicatedStorage/VehDefs.lua`：地面载具的型号数据（尺寸、速度、炮塔、武器、负重轮 / 车轮、烟幕弹发射筒、瞄准镜位置）。
  - `src/ServerScriptService/Main/`：服务器（`World` 生成地图、`Round` 回合与据点、`Weapons` 步兵武器、`Ents` 实体与伤害、`Vehicles` 登陆艇与伞降、`Armor` 地面载具、`Bots` 机器人、`Nav` 寻路、`Store` 存档）。
  - `src/StarterPlayer/StarterPlayerScripts/Client/`：客户端（`UI` 界面、`MapUI` 地图、`Play` 步兵操作与镜头、`Drive` 开载具与瞄准镜、`View` 实体的样子和悬架、`VehModels` 零件拼的车、`Fx` 特效与音效）。
- 生成 rbxlx：装 [Lune](https://github.com/lune-org/lune) **0.11 或更新**，在仓库根目录运行 `lune run tools/build.luau`（默认写 `IslandAssault.rbxlx`）。
- 也可以直接在 Studio 里改脚本；改完之后这里的 `src/` 就不是最新的了。

## 不开 Roblox 也能测（`tools/test/`）

用 Lune 模拟一个 Roblox 服务器加若干客户端（虚拟时钟、远程事件、角色、射线打地形、DataStore）。要 Lune 0.11 以上：老版本里同一个实例每次取出来是不同的对象，没法当表的键。

在仓库根目录运行：

```
lune run tools/build.luau
lune run tools/test/check.luau                        # 语法检查
lune run tools/test/ia_flow.luau IslandAssault.rbxlx  # 流程：开服 → 分队 → 部署 → 开枪击杀 → 复活 → 抢滩 → 占领 → 结算 → 下一局
lune run tools/test/ia_bots.luau IslandAssault.rbxlx 8  # 机器人：一个真人 + 机器人打 8 分钟（补人数、抢滩、交火、占领、耗时）
lune run tools/test/ia_veh.luau IslandAssault.rbxlx     # 载具：部署、开车、悬架、开炮、烟幕弹、瞄准镜四种模式、下车上车、被毁、气垫艇
lune run tools/test/ia_boot.luau IslandAssault.rbxlx  # 开服计时（地形生成）
lune run tools/test/map_export.luau map.bin 8 && python3 tools/test/map_png.py map.bin map.png   # 画地图俯视图
```

渲染、物理、Roblox 自带的镜头和角色控制模拟不了。上线前还是要在 Studio 里实际玩一遍。
