# 全面大战场 / Island Assault

百人同服的攻防登岛战。原来的「军事大亨」已经整个换掉。名字里不带 Roblox（平台规则）和 Battlefield（EA 的商标），2026-11-18 从「Roblox全面大战场」改过来。

- 两个虚构的阵营：**登陆联军**（COALITION LANDING FORCE，进攻方）和**岛屿守备军**（ISLAND GARRISON COMMAND，防守方）。不用真实国家的名字、国旗、军徽（降低被审核下架的风险）；坦克、飞机、军舰还是真实型号。
- 进服先选阵营（人数相当，人多的一边进不去）。
- 不选兵种：部署界面里配装备（主武器 M4 / 狙击枪、发射器、装备、投掷物）、选出生点；阵亡几秒后能复活。
- 第一人称：镜头前是真 M4（拔枪、换弹、开镜、后坐都有动作）和 Roblox 方块手臂；V 切第三人称。
- 地图是一片大海和几个岛：主岛「棕榈岛」、前哨岛、灯塔岛、西礁岛，南边海上是攻方舰队和攻方机场岛。
- 5 个据点（A 前哨岛、B 灯塔岛、C 港口镇、D 机场、E 指挥所）开局都归守方，分阶段突破：先打 A，再打 C、D（B 是侧翼），最后打 E；每个阶段限时。
  攻方有兵力（阵亡一个扣 1），E 也拿下攻方赢；兵力扣光或时间到守方赢（`Config.Stages`、`Config.Tickets`）。
- 守方的机枪碉堡、岸防炮、高炮、榴弹炮和滩头的钢刺猬、铁丝网、雷区都是地图自带的；炮没人管时 AI 打，自己队的人走过去按 E 就能接手。
- 攻方从舰队甲板出生，或者坐登陆艇抢滩、伞降、在拿下的据点出生；守方在北岸营地或还没被压住的据点出生。
- 中英双语，按系统语言自动选，部署界面右上角能切。

方案、规则细节和进度：[docs/island_assault_plan.md](docs/island_assault_plan.md)。现在是 1.0-alpha：回合、分队、部署、步兵武器（第一人称）、登陆艇、据点、胜负、界面、机器人（人不够时每队补到 18 人）、地面载具（坦克、装甲车、防空、火炮）、守方工事、直升机、飞机、舰艇都能玩了。

## 直接玩

1. 用 Roblox Studio 打开 `RobloxTotalBattlefield.rbxlx`。
2. 「测试 → 开始游戏」。开服先生成地形，要几秒（屏幕上有进度）。
3. 多人：「测试」页选「服务器 + 几个玩家」一起开，人会被随机分到两边。

操作：WASD 移动，鼠标左键开火，右键开镜（狙击镜），R 换弹，1～4 切武器，V 第一 / 第三人称，E 上车 / 操作工事（F 离开），F 观察员呼叫炮击，Tab 战况表。手机上有开火、瞄准、换弹按钮。

开载具：部署界面左上角切到「载具」页签，选型号和出生点（攻方：海滩、拿下的据点；守方：营地、还在手里的据点）。
WASD 驾驶，鼠标瞄准（炮塔跟着转，有回转速度），左键开火，1 / 2 换武器，X 烟幕弹，右键 / V 炮长瞄准镜（滚轮 / Z 换倍率），N 切换昼光 / 夜视 / 热成像白热 / 黑热，F 下车，E 上车。

## 发布到 Roblox

1. 「文件 → 发布到 Roblox」（Alt + P），选「创建新体验」，类型选「战斗」；设备勾电脑、手机、平板。
   **名字填「全面大战场」（英文 Island Assault）**——Studio 会按文件名预填 `RobloxTotalBattlefield`，要改掉（文件名没改，免得别的会话的命令对不上）。
2. 「主页 → 游戏设置」：
   - 「地点」：最多玩家数设成 **100**（上限 200）。Studio 里找不到的话，到 create.roblox.com → 你的体验 → 地点 → 配置。
   - 「安全」：打开「允许 Studio 访问 API 服务」，Studio 里测试也能存档（军衔、经验、战绩）；打开 Mesh / Image API（第一人称的真 M4 是开局用 EditableMesh 生成的，不开就退回零件拼的）。
   - 或者在 Studio 里「导入 3D」`models/fps_m4.glb`，放进 `ReplicatedStorage/Imported/FPS_M4`，第一人称就用导入的原模型。
   - 「权限」：改成公开。第一次公开前要在 create.roblox.com 上填「内容成熟度问卷」。
3. 以后更新：再「发布到 Roblox」覆盖线上版本；开着的服务器要到 create.roblox.com → 地点 →「⋯」→ 重启服务器。
4. `promo/` 里的图标和宣传图还是大亨版的，新玩法做完后重做。

## 手机上实测性能（上线前一定要做）

Studio 里的「设备模拟」只换屏幕大小，量不出手机的内存和帧率；测试台（`tools/test/`）也只能量服务器。所以要拿真手机进一次：

1. 先照下面「换上装备的原模型」导入模型（不导入的话量的是零件拼的版本，不准）。
2. 发布成**私有**（权限先别改公开），用一台中低端手机（两三年前的千元机）登你的号进游戏，打一局有机器人的。
3. 在聊天框输入 `/console` 打开开发者控制台：「Memory」页看总内存（Total）和 `PlaceMemory`、`Graphics…`、`TerrainVoxels`；屏幕左上看帧率。
   电脑上按 F9 开控制台、Shift + F5 看帧率、Shift + F3 看网络（Received KB/s）。
4. 把这几个数和卡不卡发给我。参考线：手机总内存一直往 2 GB 以上涨、帧率掉到 20 以下，就要打开流式加载（Workspace → StreamingEnabled）
   并给原模型做减面 / 远处换简化模型——这两步要改不少客户端代码（远处的东西不在本地了），等量出来再做，不要直接在 Studio 里勾上就发布。

已经做了的（2026-11-18）：枪声特效不再广播给所有人，只发给附近的人（服务器 `init.server.lua` 的 `G.flushFx`）。

## 换上装备的原模型（`models/veh/`）

不导入的话车、飞机、船是零件拼的。`models/veh/<模型键>.glb`（地面载具，21 个）、`models/air/<模型键>.glb`（飞机直升机，16 个）、`models/ship/<型号>.glb`（舰艇，7 艘）
是网页版的装备模型原样转的（ZTQ-15 网页版没有，是 Sketchfab 上的扫描模型）：最精细的网格（不减面）、原贴图和法线 / 金属粗糙度贴图；车、飞机是真实尺寸（1 米 = 2.8 格），舰艇照游戏里舰艇的比例（真船的 0.6 倍），每个模型一个文件。

1. Studio「主页 → 导入 3D」，选 `models/veh/`、`models/air/`、`models/ship/`（还有 `models/optics/` 手持装备和瞄准镜、`models/scenery/scenery.glb` 石头、`models/fps_m4.glb` 第一人称 M4）里的 GLB
   （一次选一个或几个都行），导入设置用默认的（别勾「合并网格」），导进 Workspace 就行。一步步的说明（含下面命令栏那一段）见 `docs/import_guide.txt`。
2. 开服时自动收进 `ReplicatedStorage/Imported/Veh`、`Imported/Air`、`Imported/Ship`（M4 收进 `Imported/FPS_M4`）下面（输出里有一行「用上了导入的装备模型：…」）；
   名字别改（`V_<模型键>__<块>`、`A_<模型键>__<块>`、`S_<型号>__<块>`、`FPS_M4_<件>`）。
   **以后的版本不用再导一遍**：命令栏跑一下 `docs/import_guide.txt` 里那一段（把导入的零件收进 `ServerStorage/ImportedModels`、碰撞改方盒），
   右键 `ImportedModels` →「保存到文件」存成 `.rbxm`，放进仓库的 `models/imported/`；`lune run tools/build.luau` 生成地图文件时会把它放进 `ServerStorage/ImportedModels`，打开就是原模型。
3. 导入了的型号游戏里自动换上：车的炮塔、炮管按原模型的转轴转，车轮各自有悬架、跟着转；飞机挂的弹、航行灯、加力火焰挪到原模型上，起落架收放、旋翼转、歼-15 折翼；
   船的主炮用原模型上的、跟着炮塔转，航行灯挪到原模型的桅顶、舰桥翼、船尾；打爆后烧黑。哪个型号用哪个模型见 `src/ReplicatedStorage/ImportedMeta.lua`、`ImportedAir.lua` 的 `alias`
   （舰艇按型号，`ImportedShip.lua`）。

重新转换（要网页版仓库）：`python3 -I tools/models/mdl2glb.py <网页版仓库目录> [--sf <Sketchfab 下载目录>]`（ZTQ-15 要 `--sf`，见 `tools/models/sfveh.py`；不给就照旧）；飞机先 `lune run tools/models/airdefs.luau > airdefs.json`，
再 `python3 -I tools/models/air2glb.py <网页版仓库目录> airdefs.json`；舰艇先 `lune run tools/models/shipdefs.luau > shipdefs.json`，再 `python3 -I tools/models/ship2glb.py <网页版仓库目录> shipdefs.json`。
模型都是 CC-BY，署名在 `models/veh/credits.txt`、`models/air/credits.txt`、`models/ship/credits.txt`（发布时放进游戏简介或游戏里的致谢）。

## 改枪（对标三角洲行动）

部署界面选主武器（M4 / 狙击枪）那格，下面有「改枪」按钮：3D 的枪上点改装位（枪口、瞄具、前握把、弹匣、战术），底下的卡片换配件，
右边看性能变化；左边推荐改装和三个「我的方案」；顶上的改枪码能复制给别人、粘贴别人的。点「完成」存档，下次出击生效。

- 配件是 Sketchfab 上 CC-BY 的原模型（署名在 `models/credits.txt`）。不导入也行：客户端开局用 EditableMesh 现生成（要在「游戏设置 → 安全」里打开 Mesh / Image API）；
  想要原贴图就把 `models/optics/` 里新的 17 个 GLB（`sup_*`、`muz_*`、`opt_*`、`grip_*`、`mag_*`、`tac_*`）也导入（同上面的步骤）。
- 瞄准镜照使命召唤做（11-21）：开镜时镜身、正圆的目镜圈一直看得见，从目镜的洞里看放大的画面。`models/optics/` 里的 `acog.glb`、`opt_acog6.glb`、`atacr.glb`、`qbu88.glb` 改过（补了正圆目镜圈、拆出镜筒里面的块），导入过的话**删掉旧的重新导入**这 4 个；没重导会自动退回现生成的（不贴原贴图）。
- 枪械等级：用这把枪打死人加经验，升级解锁配件。`Config.GunMods`：`killXp` / `botXp` 每次加多少，`unlockAll = true` 全部解锁，
  `studioAll`（默认开）在 Studio 里测试时全部解锁，发布到线上按等级。
- 配件的数值、能装哪些、几级解锁、推荐改装都在 `src/ReplicatedStorage/GunMods.lua`。

## 地图上的草和石头（`models/scenery/scenery.glb`）

地图有路网（营地、指挥所、港口镇、机场、各海滩之间的土路）、Roblox 地形自带的会动的草、坡上的石头。**不种树，也不放草丛、花丛**
（用户 11-17：「花草树木删掉，用 Roblox 自带的草」；11-18 又确认了一次：不要树、草用 Roblox 自带的）。石头长在哪是按地形算的（`Flora.lua`），每个人看到的一样；只在本机画，不挡人、不挡车、不挡子弹。

- 不导入也有：石头用零件拼的，地面是地形草。
- 想要真的石头：Studio「主页 → 导入 3D」选 `models/scenery/scenery.glb`（现在只有 3 块石头：`N_rock1`、`N_rock2`、`N_rock3`），开服时自动收进 `ReplicatedStorage/Imported/Scenery`。块名别改（`N_<键>__<块>`）。
- 2026-11-18 起 `scenery.glb` 只留石头（`python3 -I tools/scenery/keep_only.py <原来的 scenery.glb> models/scenery/scenery.glb N_rock`）：原来的包里还有 30 件树、灌木、草丛、花丛，
  游戏不用，导入后却会在 Workspace 里摆一堆（树叶贴图还有黑边）。树的代码还在 `Scenery.lua`（`LAYERS` 加回 `"tree"` 等就恢复），要恢复得用 `tools/scenery/scenery.mjs` 重新转一个带树的包。
- 模型都是 Sketchfab 上的 CC-BY，署名在 `models/scenery/credits.txt`。重新转换：`cd tools/weapons && npm ci`，再在仓库根目录 `node tools/scenery/scenery.mjs`
  （要从 Sketchfab 下载原模型时设好环境变量 `SKETCHFAB_TOKEN`）；挑哪几件、放大多少在 `tools/scenery/scenery.json`。
- 路网是离线算好的（`tools/map/roads.lua` → `src/ReplicatedStorage/MapRoads.lua`），改了地形重跑：`python3 tools/mock/run.py tools/map/roads.lua`。

## 改代码

- 脚本都在 `src/`，目录和 Rojo 的约定一样：
  - `src/ReplicatedStorage/`：`Config.lua`（数值：回合、占领、兵种、武器、载具名额、机器人、得分、军衔）、`Lang.lua`（中英文字）、`Map.lua`（地形高度、岛、据点、海滩、舰队位置，服务器和客户端算出来一样）。
  - `src/ReplicatedStorage/VehDefs.lua`：地面载具的型号数据（尺寸、速度、炮塔、武器、负重轮 / 车轮、烟幕弹发射筒、瞄准镜位置）；`ImportedMeta.lua` / `ImportedAir.lua` / `ImportedShip.lua`：原模型各块的位置、转轴（转换脚本生成，别手改）。
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
lune run tools/test/ia_import.luau RobloxTotalBattlefield.rbxlx  # 原模型：假装导入了 M1A2、JLTV、ZTQ-15，看收模型、拼车、炮塔炮管转轴、车轮悬架、炮口、烧黑、没导入的零件拼的炮塔位置
lune run tools/test/ia_import_air.luau RobloxTotalBattlefield.rbxlx  # 飞机原模型：假装导入歼-15、阿帕奇、歼-20，看蒙皮换掉、挂弹贴机翼、起落架收放、折翼、旋翼
lune run tools/test/ia_import_ship.luau RobloxTotalBattlefield.rbxlx  # 舰艇原模型：假装导入 7 艘，看蒙皮换掉、炮位照原模型、主炮跟着转、桅顶灯、烧黑
lune run tools/test/ia_radar.luau RobloxTotalBattlefield.rbxlx  # 雷达：看得见的敌人上雷达、太远和墙后的不上、开枪闪红圈、敌我车辆
lune run tools/test/ia_hitreg.luau RobloxTotalBattlefield.rbxlx  # 命中延迟补偿：跑动的小兵 / 玩家打得中，太久以前的位置、墙后的打不中；枪声只发给附近的人
lune run tools/test/ia_boot.luau RobloxTotalBattlefield.rbxlx  # 开服计时（地形生成）
lune run tools/test/ia_balance.luau RobloxTotalBattlefield.rbxlx 6  # 平衡统计：机器人对打几分钟，攻方的兵、登陆艇死在什么上面
lune run tools/test/map_export.luau map.bin 8 && python3 tools/test/map_png.py map.bin map.png   # 画地图俯视图
```

没有 Lune 也能跑一套 Lua 5.4 的模拟测试：`python3 tools/mock/run.py tools/mock/<flow|veh|forts|air|navy|bots|fps|scenery|hitreg>.lua`（`scenery`：路网、花草树木的摆放和按距离换版本）。两套都要过。

几个会话同时在改这个仓库：**以后都从 `main` 分支开始做，做完合回 `main`**（2026-11-18 起；GitHub 仓库设置里把默认分支改成 main）。分工、规矩和协调记录见方案文档的「协作」一节。

渲染、物理、Roblox 自带的镜头和角色控制模拟不了。上线前还是要在 Studio 里实际玩一遍。
