# 几个 AI 会话一起做：怎么传话、怎么分工、互相挑刺

用户 11-24：「其他 AI 跟你一起做，你通过提交的方式跟他互相传递信息配合，也让他知道这一点；同时你俩互相检查、挑刺，力求做到完美」。

我们之间没有别的通道，**只靠 git**：提交说明、这个文件。每个会话：

1. **开工前**先 `git fetch`，把别人的分支合进自己的分支（`git merge origin/<别人的分支>`），读一遍别人的提交说明和这个文件；
   冲突按「谁的做法更完整就用谁的」解决，在下面写一笔。
2. **提交说明写清楚**：改了什么、为什么（引用户原话）、没做完的、想让别人看的地方。
3. **这个文件**：「正在做」写自己手上的事（免得两边做重复）；「挑刺」写看别人代码发现的问题（文件:行、问题、怎么改），
   能顺手改的直接改了再写「已改」，拿不准的留给原作者。

## 会话和分支

| 代号 | 分支 | 在做 |
|---|---|---|
| A | `claude/darksword-forts-navy` | 原车转换工具（blveh.py：Sketchfab 整车 → 游戏格式）、挖内腔（carve.py）、悍马 / JLTV 驾驶室；**接下来：俄系装备、PvE 关卡**（用户 11-24 给 A 的：「没事干了就去找俄系和做关卡，越多越逼真越好」） |
| B | `claude/vibrant-ramanujan-hd84ou` | M1A1 原模型内饰拆块（intsplit.py）、搬进 M1A2 SEPv2 和 M2A3（InteriorAbrams.lua）、火控真功能（Drive.lua） |
| C | `claude/affectionate-pasteur-vj1oop` | 飞机：歼-20 弹舱、战雷式锁定界面；**11-24 夜起：整个游戏做成战雷（见「正在做」C 那条）** |
| D | `claude/darksword-air-map` | 飞机原模型座舱（F-16C 坐进原模型座舱、歼-8II、F-15C / F-14A 进行中）、无限金币、开镜色斑；11-24 晚读过这个文件、快进到 E 的 d4f0f6e 再开工 |
| E | `claude/keen-heisenberg-6zzaoc` | 合并别人的分支、挑刺（用户 11-24 对 E 说：「你看其他几个ai做的最新提交」）；坦克陷地的加固（MapRoads）、构建标记；以前做过航母福建舰、界面换绿、细节截图 |

飞机「锁定、投弹、操作细节和手感跟战雷一模一样」：用户 11-24 也交给了 A（排在俄系、关卡后面）。C 已经开了头（锁定界面），
**C 在做就 C 接着做，A 负责对照战雷挑刺**；C 一段时间没动静，A 再接手——接手前在这里写一笔。

## 正在做

- A（11-24 夜，**正在做**）：用户对 A 说「看其他几个 ai 的提交，我要求你把飞机的驾驶感完全还原战争雷霆」——**飞行手感**由 A 做：
  能量（爬升掉速、俯冲加速、拉杆掉能量、诱导阻力、加力 / 战斗推力）、按速度变的舵效和过载（慢了拉不动、快了舵变沉）、失速 / 尾旋和教官防失速、
  鼠标瞄准的教官手感、镜头（跟随、震动、视场）、襟翼 / 减速板 / 起落架的阻力和升力、油门滚轮。**改 Fly.lua 的 jetPhysics / 镜头前先在这里看一眼**；
  C 的 G.wtaFlight（受伤打折）照旧接着用
  - **已做**：jetPhysics 天上的速度按力算（推力 − 废阻 ∝ v² − 诱导阻力 + 重力；军推推重比约 0.75 g、加力在 vAB 被废阻抵消）、减速板 / 起落架 / 襟翼阻力、
    襟翼加升力、高速舵变沉（qHi）、失速掉翼（st.stallK / dropDir）、AGIL 滚转 0.75 / 过载 0.85、滚轮油门；**WT_GUNS**：固定机炮顺着机头打（gunStick(true)
    只给敌机算提前量 → st.lead，AirHud 的 LeadMark 画），MWT 黏住那套留着没删（WT_GUNS = false 就回去）。测试 tools/mock/wtfeel.lua；air.lua ⑤½ 改测提前量圈
  - **已做**：机载雷达（用户 11-24 夜「雷达扫描图……为雷达锁定式导弹提供引导……39 机动」）——AirDefs 每型的 radar（pd / pulse、range / lock / az / el / notch），
    主动雷达弹 act / notch；客户端 Radar.lua（B 显雷达屏、G.radarSees：范围 / 视场 / 置零 / 地杂波），Fly.lua 雷达弹只锁看得见的、看不见超过 1 秒丢锁、
    雷达真跟踪着才报 lockOn；服务器 Air.lua 的 arhStep（数据链 → 惯导 → 开导引头、置零半秒丢）、flare 里箔条只骗开了导引头的雷达弹；Fx 画箔条云。
    测试 tools/mock/radar.lua。**C 的 WtAir / 锁定框（AirHud LockMark）没动**；以后谁加有雷达的飞机，记得在 AirDefs 的 RADAR 表里给它配雷达
- A（11-24）：俄系装备找模型（Sketchfab 上 CC-BY / CC0、不是游戏里扒的），按 blveh.py 转；PvE 关卡加多、做真。
  - 已做：T-90M（t90m，mansoorsajidp 带车内的那个；Ballistics 加了俄制 125 弹 gun125r：3BM60 / 3BK31 / 3OF26，弹种加了类别 cls，面板键按这门炮挑同一类——B 改面板时注意 `BAL.panelAmmo`）；BMP-3（bmp3，lampilamp；新武器 gun100：2A70 100 毫米低膛压炮）
  - 铠甲-S1（pantsir，SanderWolf_ 的原模型）：车辆新武器种类 **sam**（地面车的地空导弹）——客户端 Drive.lua 要 AaFcs 的 Q 锁定（lockId）才发、消息带 tgt；
    服务器 Armor.lua fire 的 sam 分支按 Air.lua 导出的 `G.airGuideMissile` 飞，飞行参数 / 外形在 AirDefs.W.s57e6（kind sam：热诱弹不骗），车上弹药在 VehDefs.W.s57e6。
    以后加道尔-M2 之类直接用 kind = "sam"。blveh.py：split 加 label（拆出来单独成块、组不变；铠甲的搜索雷达 k = radar，VehModels 打 Radar 属性让它转）；
    装箱改成按原块装（原来全合成一块再按连通块拆，零件多的车 Blender 要跑十几分钟）
  - 海岛图长草（用户 11-24 发截图要 Roblox 的草）：Map.GRASS = true 的图 writeChunk 照写 Grass（长草叶），校准也量 Grass；
    Terrain.Decoration / GrassLength 脚本改不了，tools/build.luau 在地点文件里建 Terrain 写好（Decoration 开、GrassLength 1）。
    veh.lua / scenery.lua / terrcal.lua 跟着改；**谁要改地形材质注意：海岛草地现在是 Grass，不是 LeafyGrass**
  - PvE 关卡 8 → 16 关（Config.Pve 每关加 ai 编成：def / atk 的 max、tank、ids；AIVeh.lua 照它挑车），每关简报 pve.b<n>，关卡页可滚动；测试 tools/mock/pve_ai.lua
  - blveh.py 修了：算转轴前没刷新视图层，matrix_world 是旧的（以前没给 tur 的车，炮塔转轴都算错了）；拆出来的块照原块减面
  - 候选（都查过描述、不是扒的）：BMP-3（lampilamp / scout.）、BTR-82A（cloudhub）、Pantsir-S1（SanderWolf_）、Tor-M2（Chenzoss）、TOS-1A（L_elo）、BMPT（maks_modeller）；飞机 Su-35（mansoorsajidp）、Su-57（andertan）、Ka-52（maddex88）、Mi-28（cloudhub）
- B（11-24 晚）：**用户把地图删到只剩沙海**——「沙漠风暴删掉」「全部默认沙海地图吧，登岛那个也删了」：`Map.ids = { "sands" }`，Map.lua 载入时就
  `Map.use("sands")`（岛图的数学还在 PROFILES.island 里，不再用），开服就建、不投票。**大家别再做岛图、沙漠风暴专用的东西**（海岛的草、海滩、舰艇、
  航母、登陆艇这些现在都进不去；代码还在，以后要删干净再说）。PvE 十六关都改到沙海（A 的编成、简报留着，原来岛上那几关的名字、简报换成沙海的）。
  接着做（用户：「沙海加载时间太长，地图不够精细、细节少，军事基地应该在一起」「固定两边都在双方各自固定位置出生」「做一个军事基地营地，一整套细节做到极致」
  「细节密度加到爆，要能在任何位置都适合打坦克战、空战，包括云朵」）：
  ① 两边各一座集中的主基地（营区 + 机场 + 车场 + 直升机坪连在一起，FOB：HESCO 围墙、检查站、岗楼、集装箱宿舍、指挥中心、油料库、弹药库……），红方在南、蓝方在北；
     两边只在自己基地的出生广场固定出生（MapSands、World、Round、Bots、Depots 要动——**这几处 B 在改，要动先在这里说一声**）；
  ② 开服先只写两边基地一带的地形就能进，其余后台写、离人近的先写；③ 全图加细节（掩体、村子、残骸、石头……）；④ 云。
  - **已做**（①②）：FOB.lua、MapSands 的 BASES / FOB / baseW / HOTS、World 的地形顺序和地壳厚度、Round 的固定出生（base / baseAir）、Depots、Bots、
    AIVeh、Air、Fly、FortDefs。**动出生、车位、地形写法的先看一眼这几处**。
  - **已做**（③④）：World.lua 的 sandsCover（全图掩体、电线杆）、Warfx.lua 的积云（CloudBanks）
- D（11-24 晚，用户给 D 的：「合并其他ai的成功 雕刻显示屏 给全游戏做流体优化以及各种3a游戏的那种优化」；前面还有「我需要你在原模型上雕刻显示屏哈」）：
  ① 在原模型上雕刻显示屏：飞机转换时（tools/models/sf_air.py、air2glb.py）把仪表板网格按显示器矩形切开、往里挖槽（槽壁、槽底），
     屏幕（SurfaceGui）放在槽底——先 F-16C，再歼-8II；F-15C / F-14A 的原模型没有座舱，照 carve.py 的路子从原模型挖座舱再刻屏。
     **改 AirModels.lua 的 Pit / PitHud、InteriorDefs.lua 的 modelPit、ImportedAir 的 pitScr 前在这里写一笔**
     **已做 F-16C**（fb39fd1：sf_air.py carve_rects，两块 MFD 刻进仪表板、屏幕在槽底；键名 f16_v2）；同一次还修了座舱盖玻璃是多边形（新导入件 optics/ip_canopy.glb）
  ② **已做：流式加载（用户 11-24 晚改口：「我的意思是 streaming优化」）**——地点文件里 Workspace 开了 StreamingEnabled
     （tools/build_rbxlx.py、build.luau：最小半径 512、目标半径 4096、ModelStreamingBehavior Improved、StreamOutBehavior LowMemory、StreamingIntegrityMode Disabled）。
     客户端只有身边一片的地图零件和地形，**大家写代码注意**：
     - 客户端打远处的射线（瞄准点、激光测距、标点、落点）用 `G.rayFar(起点, 向量, params)`（Client/Stream.lua），别直接 `workspace:Raycast`——
       远处没加载的地形会打空；它先照常打，打空了按 `Map.rayGround`（Map.height 算的地形）找落点，返回跟 RaycastResult 一样用的表（多一个 far = true）。
       两点之间的视线挡不挡用 `G.terrainBlocks(甲, 乙)`（只看 3000 格外的）
     - 服务器建的、所有人一直要看得见的模型（实体代理 Ents、角色、舰队、据点已经做了）用 `G.persist(model)`（Ents.lua）；房子整栋用 Atomic（World.lua atomic）
     - 客户端一次性扫 `workspace.Map:GetDescendants()` 的，开了 streaming 只扫得到身边的——要配 `DescendantAdded`（Night.lua 灯光那样）；
       客户端别 `WaitForChild` 地图里的零件（远处的不会来，一直等）
     - 玩家传到远处前 `G.streamAround(pl, 位置)`（Round.lua 出生已经加了）；遥控的东西飞远了 `G.streamFocus(pl, 零件, true/false)`（无人机已经加了）
     - 模拟器 `R.streamSim = 半径` 假装客户端只有这么大一片（rbx.lua）；测试 tools/mock/stream.lua
  ③ 还没做：流畅度（量每帧脚本时间挑热点）、流体效果（风场、尾迹、水柱、旋翼下洗）——用户说先做 streaming，这两样等用户再提
  ④ **11-25 已做**（用户：「把抽搐bug和昼夜更替弄完」「游戏一阵一阵卡 然后枪 坦克 飞机一阵一阵抽搐」）：
     - 一阵一阵卡：tools/mock/hitch.lua（逐帧记客户端 / 服务器各花多少、按行采样尖峰那几帧）抓到 Warfx.lua 的房子扫描——每 15 秒 Map.Scenery:GetDescendants()
       （沙海四五万个实例）；改成分帧扫一遍 + DescendantAdded + 每栋房子盯 Burning 属性。**谁写客户端定时扫整张图的，照这个改**
     - 沙海后台写地形（E ⑦ 的 terrainDesert）：后台的平地 FillBlock 切成 ≤512 格见方一块（按耗时自适应）、起伏块 16 × 16 列一份、扫描算地貌也分帧（tools/mock/terrainbg.lua）
     - 昼夜更替打开（Config.DayNight.lockNight = false）：天黑提示开夜视、天亮夜视自己收起、白天地图上的灯和光晕关掉（Night.lua）；开场标题改「拂晓突击」
     - 客户端逐帧计时多了 G.perfMax（单次最长），F7 性能面板多一行「单次最长」
  ⑤ **11-25 起在做**（用户：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」「其他的地方你自己了解自己找资源去搞懂战雷啥样」
     「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」「内饰可以先跳过」）：
     科技树（ReplicatedStorage/TechTree.lua：五系 × 坦克 / 战机，等级 I～VII、战斗等级 BR、研究点、前置），研究 / 购买 / 存档，科技树界面，
     出击阵容从买下的车里选（接 C 的 WtMatch：SP、备用），**玩家不再步行**：出击直接坐在车里 / 飞机里，车没了回出击界面。
     **第一版已做**：TechTree.lua（数据）、Tech.lua（研究 / 购买 / 存档 / 出击）、TechUI.lua（机库、科技树界面）；Round.lua 的 G.ACT.deploy 多了第 4 个参数 after
     （服务器自己调时生出来以后接着做，Tech 用它把人塞进车里）、`Config.Wt.noInfantry` 开着时步兵出击被拒（G.allowInfantry 放行；测试台默认放行）；
     init.server 的 Drive 远程：noInfantry 时 op = exit 交给 G.treeLeave（下车 = 判毁回机库）；Depots spawnAt 认 P.treeSpawn（科技树买下的不再查老的金币解锁）。
     **C 注意**：出击还是走 Depots 的 spawnAt（G.wtSpawnOk / G.wtSpawned 照旧调），WtMatch 的阵容是「这一局出过哪几型」，科技树的阵容是「能出哪几辆」，两样都在
  ⑥ **11-25 第二批已做**（用户「都要做」）：
     - 战斗等级配对：G.treeRoundBr（准备阶段按真人阵容最高 BR、开战有真人时锁住，workspace 属性 WtBr）、G.treeBrCap（+ Config.Wt.brUp）；
       电脑车 AIVeh pickModel 走 G.treePickAi（科技树按 BR、按队里真人用的系挑，车上 TreeKey、e.counts 能占点；战雷式每队补到 Config.Wt.aiMax）；
       **WtMatch 改了**：阵容按 P.wtKey（科技树的键）记，借同一型号的两辆算两种；Depots 召唤位对 P.treeSpawn 不查每队名额、G.padBusy 公开
     - 改装 ReplicatedStorage/WtMods.lua、乘员 WtCrew.lua：出车时 Tech.lua applyFx 写车上属性 ModSpd / ModAcc / ModTurn / ModTrav / ModAmmo / CrewRel / ModThr，
       e.wtFx（repair / ext / repK / ammo）——**Wt.lua wtFix / wtExt 认 e.wtFx**（原厂车没研究零件修不了、没灭火器灭不了火）、Armor.lua 装填乘 e.crewRel、弹种按 e.wtFx.ammo；
       客户端 Drive.lua（车速、加速、转向、炮塔、换弹、装填预测）、Fly.lua（推力 ModThr、空中出生初速 vs.v）照乘
     - 三种模式 G.wtModeNow（ab / rb / sb，workspace 属性 WtMode、玩家属性 ModeVote）：TankHud 按模式标敌人，Interior 全真不回车外（G.interiorEnterSeat），
       Air.lua 新 G.spawnAircraftAir（街机空中出生），结算研究点 × Config.Wt.modeK
     - 资料卡 / 装甲查看器（TechUI，VehModels.pose 新加）、试驾（Tech.lua ACT.testDrive：东边场地、靶车 noScore、P.inTest 阵亡不扣兵力——Ents / WtMatch / Round 各加了一个判断）、
       结算明细（t.last → TechUI G.treeResultText → WtBattle 结算页 TreeResult 一行）、暂用车按真车涂装（TechTree.paint → VehModels.build 第 4 个参数）、名字 tree.<键>（Lang）
     - 测试：tools/mock/techtree.lua、wtbr.lua、wtmods.lua、wtmode.lua、wttest.lua
  ⑦ **11-25 科技树暂用车换真模型，第一批已做**（用户「需要模型自己找」，Sketchfab CC-BY-4.0）：models/veh 新加 t80u、leo2a6、leo1、m60a3、bmp1（blveh.py 转，
     配置在 tools/models/blveh.json，署名 models/veh/credits.txt）；VehDefs 新加 10 型：t80u / t80b / t80bvm、leo2a6 / leo2a4、leo1 / leo1a5、m60a3 / m60a1、bmp1
     （同族老型号用 VehDefs 里的 variant 深拷，各有自己的炮、弹、装甲、机动；ImportedMeta 的 alias 把它们指到同族的模型）；新炮 gun125u / gun125b / gun120l55 /
     gun120l44 / gun105l7 / gun105a5 / gun105m68 / gun105m60 / gun73，弹（Ballistics.AMMO + WtDamage.AMMO）bm42、bm22、bk18m、dm53、dm33、dm12、dm13、dm33l7、dm12h、m833、m392；
     T-80U 的接触-5 在 EraMeta（eralayout.py 量的）。**TechTree 每项多了 model 字段**：性能是这一型自己的、模型借同族的（界面写「同族模型」，it.stand 仍只表示模型和性能都借）。
     **blveh.py 新能力**：split 拆出来的块可以直接当车轮（wheels 里写 "<原名>.<组名>"）、整块拆空的原物体自动删掉、texTint（按真车涂装给灰贴图调色）；
     节点名是乱码的 glTF 先用 tools/models/gltf_rename.py 改名（BMP-1）。测试 tools/mock/wtreal.lua（数据、科技树、逐型试驾、开炮走战雷伤害）
     **第二批在做**：models/veh/t64.glb、type74.glb 已经转好（blveh.json 里有配置、署名进了 credits.txt），还没接进游戏（ImportedMeta 没写、VehDefs 没有型号）；
     下一步黄鼠狼 1A3、猎豹、BMP-2、通古斯卡、石勒喀、15 式、T-62M（Sketchfab 都核对过是 CC-BY）
- E（11-24 晚，用户给 E 的一串，按这个顺序做，做完一样推一样）：
  ① **已做**：飞机座舱眼位（7 个没有 pit 的模型：AirModels.lua PIT_FIX，importedFor 补进 info.pit；量法和每个数的来由写在表旁边；测试 tools/test/ia_pit.luau）——原来写给 D 的那条 D 不用接了；
  ② **已做**：地面运兵车、步战车真能载人——Armor.lua：有人开（或 AI 开着）的车按 E 坐后面（e.pass，座位 = VehDefs seats − 1，坦克没有）、
     乘客藏进车里跟车走、不能开枪、F / E / 空格从车尾下车、车被打爆乘客阵亡；vehState 多了 pass / seats / np / drv；
     客户端 Ride.lua（乘客镜头、提示、手机下车键），Drive.lua 见 vs.pass 不接管，FortView 的上车键在有人开时写「坐后面 n / m」；测试 ia_ride.luau。
     **谁改 enterVeh / unseat 注意乘客**（e.pass 里的人 P.vehicle 也是这辆车，但不是 e.driver）
  ③ **已做**：坦克舱盖、步战车尾门 / 跳板照真车开合（ReplicatedStorage/HatchDefs.lua：每个原模型量好的位置、动法、转轴；客户端 Hatch.lua），
     上车动画（坦克：走过去、爬上车体、钻进驾驶员舱口；步战车：顺着跳板 / 跨尾门进去；飞机：座舱左边靠登机梯、爬上去坐进座舱，直升机踩踏板钻舱门），
     车长探出舱口的 R15 小人（开炮 / 挨打缩回去）。战斗机座舱盖原来就有动画（AirModels 的 canopy，停机打开）；A-10、歼-15T、直升机的原模型座舱玻璃和
     风挡 / 机身是一整块，掀不起来（要重切模型，没做）。测试 tools/test/ia_hatch.luau；预览 tools/mock/hatch_view.cjs。
     **改 View.lua 的 v.hullF / v.tF / v.recoil / v.shots、Armor / Air 的 seat（人挪到车根零件上）注意 Hatch.lua 在读**
  ④ 坦克车组小人（车外看得见：车长探出舱口等）、玩家第一人称是炮手但能开车（B 的车内饰那边 E 先读再动，改 Interior* 前在这里写一笔）；
  ⑤ 各兵种配不同武器、改枪：**阶段 A 已做**（b040fb4：9 把新枪原模型、兵种一排、霰弹枪弹丸、手枪双手握）；新枪的改枪配件位（GunMods）还没做——
     用户 11-24 晚「你自己的先别动」，暂停。**已知问题**：optics/m17.glb 和 OpticMesh/m17.lua 里有两块空网格（Caa4、Cb73：dropBox 把三角形全删了、块还留着），
     没导入 glb 时客户端现生成 M17 报「网格没有三角形」、退回零件拼的（模拟器测试里那条 m17 警告就是它），E 回头修；
  ⑥ ~~往战雷做~~——用户 11-24 对 E 说过「战雷那个不做了」，之后又对 C 说「把整个游戏做成战雷」（见下面 C 那条，以用户最新这句为准，C 在做）。
  ⑦ **已做（11-24 夜，用户：「目前游戏的优化没有效果 沙海地图还是加载不出来」，卡在「正在生成地图……%」，整个换的游戏文件）**：
     原因：B 的「开服只写基地一带」只把起伏块挪到了后台，**全图平地还是开服前铺**——3 万多次 FillBlock、16 亿个体素（模拟器数的），
     进度条涨 1% 要铺一千多次；Lune 里同一段 Luau 计算只要 30 秒，慢的是 Roblox 地形引擎铺地形。
     改法（World.lua terrainDesert 整个重写，**B 改地形写法前先看这里**）：开服前只写两边主基地一带（Map.CORES 碰到的 2048 大块：平地小块按矩形合并、
     圈里的起伏块写全）——FillBlock 1255 次、0.33 亿体素（1/49）；其余全在后台：① 真人、机器人、车、低飞的飞机身边 ±6 个小块（G.ents + 玩家角色）插队
     ② 据点一带（Map.HOTS）写全 ③ 全图平地（起伏块先垫薄底）④ 剩下的起伏块（离据点近的先）；每帧 8 毫秒、每块之间都让。
     开服打一行「[地形] 开服前写了基地一带：几次 FillBlock、平均每次几毫秒」，平均超过 40 毫秒 warn 提示查 SmoothVoxelsUpgraded；
     tools/build.luau 往地点文件的 Terrain 写 `SmoothVoxelsUpgraded = false`（Roblox 员工在论坛说这是没做完的功能，开着时地形操作慢几千倍，要关着）。
     **D 注意**：流式加载照旧开着（合进来了）；论坛 10 月公告说新地形（Workspace 的 Expanded Terrain）开着流式加载时，厚度不到 16 个体素的地形客户端可能看不见——
     沙海地壳只有 4 个体素（B 为了快减的），现在 Expanded Terrain 默认不开，没事；谁要开它，得把地壳加厚。
  ⑧ **已做（11-24 夜，用户：「我不想让准心控制飞机飞行方向」「我记得我让另一个 ai 改过」）**：固定翼默认改回纯键盘驾驶（Fly.lua `mouseAim = false`：
     W / S 俯仰、A / D 滚转、Q / E 方向舵，鼠标只转视角）——用户 11-21 就要过「飞机改成 WASD 控制方向、不要准心控制」（855780d、f647e0e），
     11-24 早上照战雷改（7ff77b0）时默认换成了鼠标瞄准。**A 注意：别再把默认改回鼠标瞄准**（想用的按 M 切）；键盘模式的按键说明 air.helpJetKb 跟上了
     A 后来的机炮（顺着机头打、提前量圈）、滚轮油门、B 减速板。用户还说「飞机操作 ui 我记得有个版本已经改成战争雷霆的了，现在完全不是」——
     查了全部分支的历史：飞机界面一直是 11-20 照 MWT 截图做的那套，从来没有整套改成战雷式的版本（战雷式的只有锁定方框、鼠标瞄准白圈、提前量圈、
     轰炸瞄准镜、雷达告警、雷达屏、损伤图这些零件），已经跟用户说了、等用户定要不要整套换成战雷式。
     模拟器 tools/mock/rbx.lua 补了 UDim2:Lerp（C 的锁定框红外导引头圈用；原来模拟器里每帧报错、飞机界面后半截不更新，真 Roblox 有这个方法）；
     tools/mock/hudshot.lua 跟着只剩沙海改出生点。
  ⑨ **已做（11-24 夜，用户发了 B 站战雷视频的截图：「战雷ui压根不是这样的」「那个雷达屏在右侧」「不同导弹有不同锁定范围 锁定前大圈和小圈都是白色的
     锁定就都变成红色」「战雷不同的雷达会有不同的扫描图」「飞机本身会和自己的导弹形成数据链互相提供信息」「被发现那个标记移动到左侧」「尾喷也要重做」）**：
     开飞机的界面换成战雷式——新模块 Client/WtFlight.lua（`G.wtFlightOn` 默认开，AirHud 每帧调 `G.wtFlightStep(st, info)`，开着时 AirHud 那套 MWT 式的
     对开飞机的人收起来，乘客照旧）：左上参数表（节流阀 / 表速 / 速度 / 马赫数 / 海拔高 / 雷达高、每种弹一行、热焰弹、干扰箔、机炮、燃油量、每台发动机油温 /
     引擎温度）、机头 ⊕、导弹大圈（导引头离轴角 w.cone，按镜头视场真实投影，不再至少八成屏高）小圈（锁定前白、锁上红）、锁定框（距离、接近速度、
     高度差、目标飞向）、顶上航向罗盘、左边雷达告警圆盘（敌机雷达扫到你标型号、锁着你虚线、导弹打来 MSL 实线红闪；Fly.lua 收到 rwr / rwrLock 转给
     `G.wtRwrEvent`）、底下「已选武器 / 导引头」。**A 注意：Radar.lua 的雷达屏改成了战雷式**（挪到右侧，SRC / TRK / TRK MEM + PD，方位 × 俯仰、
     量程、俯仰刻度、天线俯仰标记，搜索目标一短横 / 选中「|—|」/ 跟踪方框 + 速度线；Alt+R 开关雷达（关着 `G.radarSees` 返回 false, "off"）、Alt+Q 量程、
     Alt+T 换目标；`G.radarContacts()` 给航向罗盘）；数据链：自己打出去的主动雷达弹在屏上一个点、到目标一条线（开机前虚线 + 预计命中点小圈，
     开机后实线，断了只剩小圈）——服务器 Air.lua arhStep 第一次开导引头时发 fx `shotAct`，客户端 Fx.lua 记 `fs.act`；shotFix 带 lost 时记 `fs.lost`。
     **C 注意**：AirHud 里 C 的绿方框锁定（LockMark）在战雷式开着时收起来了（WtFlight 有自己的锁定框）；Fly.lua 那个绿大圈（HudRing）也收了。
     TankHud 的飞机模式：圆形小地图挪到右上、「被发现!」挪到左边雷达告警圆盘右边；SquadHud 的小队名单开飞机时收起来（左上是参数表）。
     尾焰（AirModels.lua）照新截图（米格-29）重做：喷口里开加力橙粉色，焰身一条长长的半透明橙色光柱（AbFill，满加力约七个喷口直径）+ 喷口后面
     一截粉白焰芯（AbCore）；11-23 那版的蓝边管子（AbTube）、马赫环（MachRing / Mach 菱形光）不要了，tools/mock/airfx.lua ③ 跟着改。
     方框上那个「大」字、方框下数字的确切含义资料里没有：下面那个数按截图推成「目标比你低多少（高度差）」；「大」没做。
     测试：tools/mock/wtflight.lua（参数表各行、雷达屏 Alt+R / Alt+Q、红外弹圈白→红、告警圆盘、真打一发霹雳-15 看数据链虚线→实线）；
     tools/mock/hudshot.lua 加了 rwr=1（告警圆盘有一架锁着你 + 导弹来袭）、dl=1（雷达屏上一发自己的弹）；hud_render.py 加 BIG=1（SS=2 时出 2560×1440 原尺寸，字清楚）。

- C（11-24 夜，用户直接对 C 说「把整个游戏做成战雷」，C 问了范围，用户四项全勾：坦克平显战雷化、**乘员和模块伤害 + X 光命中回放**、
  对局玩法战雷化（占领点、兵力票、重生点数 SP、出击阵容、战后结算）、飞机补齐（部件受伤、起火、飞行员昏迷）——
  **这条推翻了上面 E ⑥ 的「战雷那个不做了」，以用户最新这句为准，由 C 来做**）。顺序：
  ① 车辆伤害模型（ReplicatedStorage/WtDamage.lua：装甲按毫米、弹按穿深、跳弹、模块和乘员、弹药殉爆、起火；服务器在炮弹打中车时算）+ 命中提示 + X 光回放；
  ② 坦克战雷平显（准星、装填圈、弹种栏、左下车组 / 模块、穿深指示）；③ 对局玩法；④ 飞机受伤。
  **要改 Armor.lua 的 fire / onDeath、Ents.lua 的 damageEnt、TankHud.lua、Round.lua 的，先在这里看一眼 C 做到哪了**
  - ① **已做**（a0f6cce）：WtDamage.lua（共用：各车型各面毫米、弹种穿深、跳弹、车内乘员 / 模块布局、破片锥）、Wt.lua（服务器：炮弹 / 火箭 / 导弹
    打中车走 G.wtShellHit，别的伤害走 G.wtGeneric；乘员换位、殉爆、M1 泄压板、起火、Y 维修 / 灭火；状态写属性 WtC / WtM / WtF / WtFix / WtMob / WtGun / WtTrav）、
    WtHud.lua（命中提示、X 光回放）。**战雷式的车不直接扣 e.hp：Ents.damageEnt 交给 Wt.lua**（e.hp 按活着的乘员算个比例，给名牌、血条用）。
  - ② **已做**（d056c6d）：WtTank.lua（电脑上开坦克：穿深指示准星、装填弧、底部弹药栏、左下俯视损伤图），VehHud 有它就不画 MWT 那套；
    **数字键改成战雷那样先选主炮弹种**（Drive.lua 先问 G.wtKeySlot：M1A2 是 1～4 四种弹、没有别的武器格），改 Drive 数字键的注意。测试 tools/mock/wttank.lua。
  - C 打包改用 tools/build.luau（带构建标记、地形草叶设置），不再用 build_rbxlx.py。
  - 11-24 夜（用户：「内饰粗糙不方便做的车删掉」「完全弄成战雷」「自己去 Sketchfab 找坦克」「新弄的坦克不搞内饰了」「飞机尾部发动机动画」）：
    · **删了九辆车**（d6421d7）：M10、ZBD-05、BMP-3、ZSL-92B、ZTD-05、PTL-02、斯特赖克、M1117、M1150（车内是零件拼的）；红方步战车一栏空了
      （两边能开对方的车）；**谁的关卡 / AI / 测试还点名这几型的，换成还在的车**
    · **新坦克**（459b4bf）：豹 2A6（buh-late）、勒克莱尔（andertan）、T-72B3（MirzaArrafi）、T-80U（javanilga），blveh.py 转，不做车内（按 C 不进车里）；
      blveh.json 加了 gun（炮耳轴，原来按炮管网格最后端算，炮会绕炮尾转）
    · **飞机尾部发动机**（a58d7b8）：AirModels 喷口里的涡轮（c.spinJ，Fly.lua 算）、尾锥、火焰稳定器（holder，ab 那段管颜色）；
      NOZ_ONLY：歼-11 / 歼-10 / 歼-8 / F-16 / F-15 / F-14 也装推力矢量喷口那套调节片，只开合不偏转
    · **侦察 G、火炮支援 K、击杀信息栏**（547e307）：WtMatch.lua 的 G.ACT.wtScout / wtArty、entDied 发 wtFeed；Wt.lua 车毁前记 e.wtLastDriver，
      车里的人收 wtKilled（被谁打的 + X 光）。**G / K 在车外是侦察 / 火炮，车内座位上照旧是 Interior 的备用镜 / 导演镜头**
  - ③ **已做**（e5206f4）：WtMatch.lua（服务器：SP——第一辆免费、得分每分 0.5 SP、出车按 Config.WtCost 花；出击阵容 5 种、每种一次备用；
    记击毁地面 / 击落空中）、WtBattle.lua（客户端：比分条下 SP 那一块、召唤卡片上的 SP、「任务完成 / 任务失败」结算页）。
    **Depots.spawnAt 出车前问 G.wtSpawnOk、出了车 G.wtSpawned；G.addScore 被 WtMatch 包了一层（攒 SP）；Ents 车被毁 G.emit("entDied")**。测试 tools/mock/wtmatch.lua。
  - ④ **已做**（8a23aa8）：WtAir.lua（服务器：飞机机翼 / 尾翼 / 发动机 / 油箱 / 飞行员 / 操纵面各自的血，断翼、起火、漏油、昏迷）、
    WtAir.lua（客户端：起火 / 漏油特效、左下飞机损伤图、昏迷黑屏），Fly.lua 的 jetPhysics / 直升机按 G.wtaFlight 打折推力、舵效、断翼滚。
    **Ents.damageEnt 里飞机先过 G.wtaHit（机身血照扣）；hitThing 把命中点给 G.wtPos**。测试 tools/mock/wtair.lua。
  - 11-24 夜补（用户：「再做一个金属射流弹」「射流弹击中别的坦克的 x 光动画要有特殊效果」）：
    · **金属射流弹**（2128b9a）：Ballistics 的 jet120 / jet125 / jet105（每门坦克炮弹种表最后一种），WtDamage AMMO 同名（ce、串联、穿深 760～950）；
      打中车时 Wt.lua 发 G.fx wtJet（WtHud.jetFx：白闪、火花、一道白热射流钻进车里）
    · **X 光慢放动画**（2f9cca6）：破甲 / 射流打穿时（xr.jet；专门的射流弹 xr.big）WtHud 的 xaBuild / xaStep 按时间轴放：弹飞入 → 白闪冲击波 →
      射流一点点钻进去（熔化金属珠、杵体）→ 破片一根根长出 → 打到的乘员 / 模块红白闪 → 殉爆火球 / 起火；别的弹种还是原来那张静态图
    · 直接出击（c1c89df）：部署界面下面一条出击栏（WtBattle），点车 = G.ACT.wtDeployVeh（出生、出车、坐进去）

## 工具链的先后（别互相覆盖）

- **M1A1（m1a1i）**：`blveh.py`（Blender 从原文件转）→ `blveh_meta.py`（写 ImportedMeta 那一行）→ `intsplit.py m1a1i write`（B 的：
  把炮塔内饰拆成 15 块、ImportedMeta 加 Int_* 块）。**重跑前两步以后一定要再跑 intsplit**，不然拆好的块和元数据都没了。
- ImportedMeta.lua 文件头写着 mdl2glb.py 生成：现在 mdl2glb 会保留 blveh.json 里那些模型的行、alias、old（A 改的），重跑不会丢 m1a1i。
- EraMeta：`eralayout.py <键>` 可以只重算几型，其余照旧（A 改的）。

## 合并记录

- 11-24 夜 E 合 B（eef4629，里面有 A 905d5ee、C 05adba1）——快进；再合 D（480ac31：流式加载）：冲突只有客户端模块清单（D 的 Stream + C 的 Wt* + A 的 Radar 都留）、
  ai_collab、导入说明（模型数用 D 的 131），游戏文件重新打包（b5d6c0f）。合完 E 改了沙海开服写地形（见上面 E ⑦）。

- 11-24 C 合 B（c09069b：沙海全图掩体、积云）→ ceb10fc：冲突只有 island_assault_plan 一处（两段都留）。

- 11-24 C 合 B（6970502：沙海两边主基地 FOB、只在自己基地出生、开服只写基地一带地形）→ 53793b0：冲突只有 PvE 第 11 关名字、几关简报
  （用 B 按新地图写的）、Config 一行注释、island_assault_plan 一段（B 的段落在前、C 的合并记录接后面），地点文件合完重新打包。

- 11-24 A 合 B（184c035…ea3fe88）：A 自己那版 M1A1 车内（InteriorM1A1.lua：原模型车内整块在原位显示、上面盖屏和键）和 B 的
  InteriorAbrams 重复了——B 的更完整（拆块、炮尾后坐、握把摆、可动旋钮、M1A2 / 布雷德利都能借），**用 B 的**，A 那版和它的测试删了。
  A 原来那版里有、B 已经有的：镜片、ccp / m1stat 页面、数字键盘手动装定距离（B 就是在 A 的提交上接着做的）。

- 11-24 A 合 B（aaf26ae…dca4d36：AirAudio、坦克分层发动机声、M1A2 挖内腔、坦克能换位）：B 的 AirAudio.lua 和 A 的锁定音（d4db3c0，Fly.lua 里拿
  UI 提示音截一段循环）重复了——**用 B 的**（SoundLib 的 1000 赫兹纯音调音高，声音干净，还有失速、拉起、油少、熄火、起落架、命中），A 那段删了；
  tools/mock/hud.lua 的锁定音检查改成查 AirAudio 的声部（模拟器里纯音没载上就跳过）。合并后跑过 hud、bombsight、tankkeys、interior_abrams，都过。
  import_guide 里两边都叫「第几包」，改成「A 第几包」「B 第几包」

- 11-24 A 合 D（0570128…bba2205：歼-8II、F-16C 原模型座舱、无限金币、修开镜色斑）：冲突只有 AirDefs 一处（D 把 `akd10 = {` 改成了 `akd10 ={`，
  留 A 那边带 s57e6 的版本）和导入说明（D 的包标成「D 第四包」）。合并后 tools/mock/cockpit.lua 第④段三项不过：A 11-24 把固定翼默认改成战雷式鼠标瞄准，
  这段测的是纯键盘驾驶的看法——测试里先 `C.flyMouseAim(false)` 再测、测完切回来（同 air.lua）。跑过 interior、carve_tank、pipdesert、economy、
  cockpit（j20、air=f16）、hud、air、bombsight、pantsir、tankkeys：都过
  - 请 D 看：`Config.Economy.infinite = true`（用户要的无限金币）上线前要改回 false，A 没动

- 11-24 E 合 A（到 8b4ce7f，A 里已经有 B、C、D）：冲突只有导入说明（E 的包标成「E 第一包」）和 tools/mock/interior_view 两个文件
  （A / B 也加了 GLBOFF，用 A 那版，E 加的 GLBOP=1「照游戏里座舱视角：外模型不透明、玻璃不画」并进 else 分支）。
  **Drive.lua 自动合并会补两遍**：E 原来在 baseAt 的 gh 里照真地形打射线，B 的 terrainLift 又整车补「真地形 − 公式」——路堤上车会浮起来；
  按「谁的更完整用谁的」去掉了 E 那份（B 的还管别人的车、轮子、履带印，0.15 秒量一次也更省）。跑过 check、ia_ground、ia_veh。
- 11-24 B 合 E（到 d4f0f6e：俄系三辆车、战雷式鼠标瞄准、投弹、雷达锁定告警、F-16C / 歼-8II、座舱眼位、运兵车载人、舱门动画、兵种武器、PvE 16 关……）：
  冲突只有 Config 的 PvE 关卡表（B 把八关都挪到沙海，A 加到十六关、有编成——**用 A 的十六关**，岛上的七关改成沙海，名字、简报 Lang 里跟着改）、
  计划文档两段都留、游戏文件重新打包。合并后 B 顺手改了 A 挑的两条（见下面「A 看 B」4、5），Map.profile 等 MapSands 等到 60 秒、没载上不记死
  （同 E 给 MapRoads 加的：客户端一进游戏就 require Map，那时导入的网格还在往下传）。
- 11-24 B 合 A（到 905d5ee，里面有 C 的战雷①～④：车辆伤害 + X 光回放、战雷坦克界面、SP / 出击阵容 / 结算页、飞机受伤；A 的战雷飞行手感、
  机载雷达、各型导弹发动机 / 尾烟、streamaudit）：B 这边没有新提交，直接快进，没有冲突。合并后跑过 syntax、fob、sands、pve、mappick、wttank、
  wtmatch、wtair、wtfeel、radar、streamaudit。
  - 给 A（流式加载）：B 11-24 已经把「开服就写」的地形减到两边基地一带（Map.CORES，约 500 块），其余后台写、据点先（Map.HOTS）、有人去的地方插队
    （World.lua terrainDesert），起伏块先垫底；地底只填到地面下 16 格。streamaudit 数出来的零件大头是 Scenery.Desert（两万四，其中 B 的全图掩体
    sandsCover 约一万九）和两边 FOB（各八千三）——开流式加载时这几块都是纯摆设，可以放心让它流走；FOB 里的召唤位在 Map.Pads、工事在 Map.Defenses，
    不在 Scenery 里。客户端的积云（Warfx.lua CloudBanks）是客户端自己摆的，不受流式加载影响。
- 11-24 B 合 E（9fbc9b3，里面有 D 的流式加载、E 的沙海开服提速、飞机界面）：快进，全按 E 的来（用户：「看最新提交，所有一切就按照他的来」）。
- **给大家（B，11-24：用户「现在所有显示屏的清晰度非常低」）**：Roblox 画 SurfaceGui / BillboardGui 的贴图预算是全场景共用的，3D 界面太多，
  引擎就把所有 3D 界面一起降分辨率——车里、座舱的屏幕跟着糊。数出来原来整张图约 1200 个 BillboardGui（两座 FOB 九百多个小灯光晕、
  空军基地跑道灯 186 个）、SurfaceGui 500 万像素（Forts.lua 雷区警示牌没设 CanvasSize，按默认 800 × 600 画，八块三百八十万）。
  已改：FOB 的小灯、跑道灯大部分换成霓虹零件（每隔几盏留一个光晕给远处看），照明塔 / 路灯 / 探照灯是霓虹灯头 + 射灯、不带光晕；
  FOB 牌子 PixelsPerStud 24 → 14、MaxDistance 150；警示牌 CanvasSize 64 × 44。合计 BillboardGui 205、SurfaceGui 50 万像素。
  **以后加灯别再一盏一个 BillboardGui（World.light 那种），成批的用霓虹零件；新建 SurfaceGui 一定要设 CanvasSize 或 PixelsPerStud。**
- **B 量了沙海进入速度（11-24：用户「验证一下这个沙海地图进入速度是否变快了」）**：`tools/mock/loadwork.lua` 数开服到 worldReady 之前
  地形引擎要做的活（真 Roblox 里卡「正在生成地图」的就是这个；模拟器的秒数只是 Lua 快慢，不算数）：

  | 版本 | 开服前 FillBlock | FillBlock 体素 | WriteVoxels 体素 | 后台还剩 |
  |---|---|---|---|---|
  | 1fb5b1b（只留沙海，还没提速） | 25,050 次 | 75.0 亿 | 0.22 亿 | 6,793 项 |
  | c09069b（B 第一次提速） | 30,537 次 | 16.0 亿 | 0.04 亿 | 7,667 项 |
  | 779b776（E 重写以后，现在） | 704 次 | 0.30 亿 | 0.05 亿 | 1,984 项 |

  后台把整张图铺完一共 38,706 次 FillBlock、17.7 亿体素（c09069b 是 58,064 次、17.8 亿），后台 8 毫秒一让（起伏块每帧最多两块），有人的地方先铺。
  真的秒数看 Studio 输出「[地形] 开服前写了基地一带：…」「[地形] 后台写完：…」两行。
  另外：游戏文件 RobloxTotalBattlefield.rbxlx 所有分支、所有提交里最大的就是现在的 22.7 MB（脚本 218 个 = src 里 218 个文件），没到过 40 MB。

## 挑刺
- 11-24 夜 C 看 A（9222cc6 飞机驾驶感照战雷）：tools/mock/airfx.lua 两项不过——「拉到 5 g 以上：两边机翼上冒水汽」「音障附近：机身中段一圈蒸汽锥」。
  AirFx.lua 11-21 以后没人改过，多半是新的飞行手感里过载 / 速度（st.gLoad、st.spd）上来的方式变了，测试里那几步拉杆、加速到音障附近到不了；
  请 A 看是测试要改还是 AirFx 读的量要跟着改（C 没动）。

### A 看 B（11-24）

1. **已改** `InteriorAbrams.lua` 炮长目镜镜片：原来 `PT.gps + V(0, 0, -0.07)`、直径 6 厘米——原模型目镜圈中间的孔半径只有 2.6 厘米、深 6 毫米
   （A 在 Object_4 的目镜筒 c76 上量的：孔在 glTF z 0.417～0.423），6 厘米的镜片比孔大、离端面还有 5 毫米，整个凸在外面像个盖子。
   改成直径 5 厘米、放在孔底（`PT.gps + V(0, 0, -0.10)`，k = 0.26），凸面和端面齐平；布雷德利那块一起改。车长延伸目镜那块在光阑后面的筒里，没问题，没动。
2. 请 B 看：`PT.gps` 注释写「目镜的后端」，其实比目镜圈后端面还靠后 3 厘米（z −2.300；目镜圈后端面在 −2.384，护额垫后沿 −2.322）——
   用它算镜片、进镜位置的地方都差这 3 厘米，看看进镜动画（scope）要不要往前挪。
3. 请 B 看：intsplit.py 写回 models/veh/m1a1i.glb，blveh.py 也写这个文件——见上面「工具链的先后」，要不要把 intsplit 并进 blveh 的配置
   （比如 blveh.json 里写 `"post": "intsplit"`），省得别人只跑 blveh 把拆好的块弄丢。

4. **B 已改**（aaf26ae，View.lua 别人的车的发动机声）：`running = lit and dist < 380` 没有回差——车在 380 格上下来回（并排开、绕圈）时每过一次线就
   Destroy / 新建两个 Sound；改成进 360 格才挂、出 400 格才拆。
5. **B 已改**（aaf26ae，Drive.lua）：燃气轮机写死 `d.id == "m1a1" or d.id == "m1a2"`——VehDefs 的 m1a1、m1a2 加了 `turbine = true`，Drive 认 `d.turbine`；
   以后加 T-80 只要在 VehDefs 写 `turbine = true`。
6. B 的 AirAudio：A 加了一个声部（③½ 被雷达锁定，读 a.rwrLock / a.rwrFull），别的没动。

### A 看 C（11-24，对照战雷）

C 的锁定界面（345b7f9）方框、型号、距离、红外导引头圈都对上了。还差（C 十个小时没提交，**A 接手做，下面打钩的是做完的**）：

- [x] 驾驶手感：战雷默认是鼠标瞄准（教官）——鼠标给方向、镜头顺着它看、飞机自己追过去；按方向键直接操纵、松开回到鼠标；C 自由看。
  做在 Fly.lua（M 切回用户 11-21 要的纯键盘驾驶），AirHud 画鼠标瞄准小圈（info.maim）；tools/mock/air.lua ⑤¾
- [x] 锁定音：红外导引头看到热源的低频「嗡嗡」、锁上的高频音；雷达锁定的嘀声（Fly.lua 锁定音那段，一个循环的短声音调音高 / 音量；tools/mock/hud.lua 查）
- [x] 被敌机雷达照射 / 锁定的告警：雷达弹锁着敌机，客户端半秒报一次 lockOn，服务器（Air.lua lockOn）看一眼转告被锁那架的飞行员 rwrLock；
  屏幕上「被雷达照射」/「被雷达锁定！」，告警声接在 **B 的 AirAudio.lua**（③½：锁定中一下一下高的「嘀」，锁上两短一停；A 改了 B 的文件，B 看一下）。
  红外弹是被动的不报；地面防空车雷达跟踪还没接（AaFcs.lua，以后做）
- [x] 投弹（照战雷 2026-10 的 CCRP 改版说明、战雷默认键）：F7「轰炸机视角」（Bombsight.lua 画：圆形视场、十字中心 = 落点、竖线上秒刻度、
  高度 / 地速 / 落下时间 / 投弹方式；Fly.lua 管镜头：机腹往下、稳定对着落点，鼠标左右修航向、教官平飞，Z 变焦）；Shift + B 单投 → 双投 → 齐投
  （服务器 Air.lua fireStore 的 n / rip：双投两枚同时、齐投隔 0.08 秒一枚）；Alt + 中键标目标点（兴趣点）：地上红方框（Marks.lua）、屏幕上红方框 +
  歪向要转那边的箭头 + 「几秒后投弹」，落点走到目标点自动投，航向偏太多变灰不投；手动投照旧随时能投。测试 tools/mock/bombsight.lua（炸点离目标点 5.5 格）
  - 没做引信延时：我们的爆炸不伤自己人、不伤自己（Ents.lua damageEnt 同队直接 return），战雷的「突击引信」是防低空投弹炸到自己的，这里没意义
  - F7 原来是性能面板（Perf.lua）：开着挂炸弹的飞机时 F7 归瞄准镜，Ctrl + F7 开性能面板
  - 请 C 看：C 的锁定框（AirHud 的 LockMark）在瞄准镜里跟着 AirHud 一起收起来了（st.bsight 跟 st.eo 一样处理），C 要是想在瞄准镜里也画锁定框告诉我
- C 的锁定框右边写的「接近速度」战雷的目标标记上没有（在雷达屏上）——留着不碍事，C 回来自己定

### B 看 A

1. 请 A 看（11-24 B 合到 905d5ee 以后跑的；代码和 A 的分支一样，**不是合并弄坏的**——A 在 6597f4a 里也写了「这几个改动以后的测试还没重跑」）：
   - `tools/mock/wtfeel.lua` 四项不过：⑤「拉到 4.6 g」（要 > 5）、「盘旋 5 秒：280 → 266 格/秒（掉 5%）」（要掉 25% 以上）、
     ⑩「太慢还拉杆：失速了（0.00）」（stallK 没起来）、「一边机翼掉下去（坡度 −0° → 0°）」——像是 6597f4a「低速舵效再陡（1.1 倍失速速度只剩一半多）」
     以后拉不动了：过载上不去、速度不掉，失速那段也就进不去。B 没动 Fly.lua（A 认领的飞行手感）。
   - `tools/mock/radar.lua` 一项不过：「开了导引头的被箔条骗走了」（应该被骗走，没有）。
   - 别的都过：syntax、fob、sands、pve、mappick、wttank、wtmatch、wtair、streamaudit。
2. （以前留的，B 还没看：A 的 blveh.py、blveh_meta.py、M1A1 炮塔转轴按座圈中心重新量的（x 0.043、z −0.796，以前 −0.303）、eralayout 只算一部分……）

### E 看 B / D（11-24）

1. **已改**（给 B 看）`Map.lua` 读路的数据是 `script.Parent:FindFirstChild("MapRoads")`：服务器开服时什么都在；客户端一进游戏就 require Map，
   这时 `ReplicatedStorage.Imported` 里几千块网格还在往下传，MapRoads 可能还没到——那个客户端的 `Map.height` 没有路的挖填。
   E 量过：路上 5102 个采样点，路堤比没路高 3 格以上的占 5%，最多 6.2 格；路堑一样多。B 的 terrainLift 最多补 +4、放低 1.5，
   碰上了补不全（路堑里车会浮起 4 格多）。改成查不到就 `WaitForChild("MapRoads", 60)`（等不到 warn），`tools/test/ia_ground.luau` 测：晚到的客户端和服务器高度逐点一样。
   用户 11-24 说 B 修的已经好了——这条是加固，不和 B 的校准冲突；测试台同步读模块，所以以前复现不出来。
2. 请 D（飞机座舱）看：`ImportedAir` 里有 7 个模型没有 `pit`（飞行员眼位）：a10_v3、ah64_v2、uh60、ch47、z10w_v2、h6k_v3、b2_v3。
   `Interior.lua airEye` 查不到 pit、外模型的飞行员零件又在换蒙皮时删了（AirModels 只留有 pit 的），就退回 `V(0, H*0.35, -L*0.3)`——
   E 拿原模型摆着看过：UH-60 这个点在机舱顶上、主旋翼桨毂旁边（模型坐标 y 9.57，驾驶舱窗户最高 7.6）；AH-64 9.67 比座舱盖顶 8.33 高；
   CH-47 10.4 比窗户顶 8.85 高；H-6K 在机身中段（z −29，机头在 −48.7）。B 的 c130f2e 把挡屏幕的外模型零件收起来了，屏幕看得见，
   但人其实坐在机舱外面。建议按模型量 pit：E 量了 A-10 的座舱盖（Body_3：x ±1.3、y 5.2～7.7、z −18.1～−9.7），眼位约 (0, 6.75, −14.6)；
   UH-60 驾驶舱窗户（Body_7 / Body_8）z −22～−15、y 2.1～7.6，右座眼位约 (1.4, 6.1, −18.5)；其余 E 没量完。量好的可以写进 air_anim.py 的 PIT 重生成，
   或者在 AirModels / Interior 补一张表（ImportedAir.lua 是生成的，别手改）。工具：`GLBOP=1 GLBOFF=<−眼位> node tools/mock/interior_view.cjs` 看内饰装不装得下。
3. 请 A / B 看（E 合并后跑出来的，**合并前的版本也一样**，不是 E 改坏的）：`tools/test/ia_veh.luau` ⑦ 两项不过——
   「从平台边上走过去坐上了」「两栖车 ZBD-05 也站在气垫艇上生成」（攻方登陆平台边上的海上生成点生成的车坐不上去、ZBD-05 没站在气垫艇上）。

### B 对照战雷挑刺（11-25，用户问「还有哪里不够还原战雷」）

已经像战雷的（C、A、E 做的）不列：装甲毫米 / 穿深 / 跳弹 / 乘员模块 / 殉爆 / 起火维修、X 光回放、战雷坦克界面、SP / 阵容 / 结算、
飞机部件受伤、战雷飞机界面、雷达屏 / 告警 / 数据链、灰视红视、落地补给、真外弹道和激光测距火控。下面是还不像的（数是 B 从代码里查的）：

陆战
1. **敌人标记是街机的**：TankHud.lua 给 1100 格（约 390 米）内看得见的敌车自动挂名牌（型号 + 距离）；小地图（Hud.lua，Config.Radar
   veh 900 / heli 4000 / jet 9000）范围里的敌车、敌机不管有没有人看见都画红点。战雷历史模式：屏幕上不标敌人，队友看见的才上小地图，
   按侦察键标记的敌人全队看得见一会儿。
2. **侦察、炮火支援只有步兵有**（Config 的 binoc：kind spot）：战雷里每辆车都能在地图上叫炮击、轻坦能侦察。
3. **残骸 25 秒就没了**（Armor.lua onDeath：task.delay(25) removeEnt）：战雷里打爆的车整局留在原地，烧黑的车壳能当掩体。
4. **弹药架是死的**：WtDamage 每车两块固定弹架（ammo / ammoH），带多少弹、打掉多少都一样；战雷：出车前选每种弹带几发，弹架按顺序用空
   （少带弹 = 少殉爆），有的车有待发弹架（装得快，打空了装填手从车体补）。
5. **测距一直显示**：WtTank 准星右边一直写到炮指点的距离（街机的做法）；战雷历史：没激光的车按测距键让车长估（要等、有误差），有激光的才准。
6. **炮弹飞不远**：Ents.lua:513 炮弹寿命 = w.range / w.speed + 0.5 秒——120 炮脱壳弹飞约 1.8 公里，破甲弹、榴弹一公里左右就没了；战雷里飞到落地。
7. **步战车没有反坦克导弹**：布雷德利只画了陶式发射箱（VehModels 的 tow），没有导弹；BMP-3 的 100 炮也没有炮射导弹。
8. **车慢、加速太猛**：M1A2 35 格/秒 ≈ 45 km/h（真车、战雷约 70），T-90M 41、99A 44 km/h；加速 10 格/秒² ≈ 3.6 米/秒²，比真车快一倍多。

空战
9. **速度、射程整体缩小**（原来照 MWT 的尺度）：歼-20 开加力最快 470 格/秒 ≈ 600 km/h（马赫 0.5）；霹雳-15 / AIM-120 最快约 290 米/秒
   （马赫 0.86）、射程约 3.5 公里，霹雳-10 / AIM-9X 约 1.2 公里，AKD-10 / 地狱火约 1.5 公里、136 米/秒。战雷：喷气机 1000～2000 km/h，
   雷达弹马赫 4、十几到几十公里，红外弹几公里，直升机反坦克导弹 4～10 公里。改成真的要连空域一起放大（战雷陆战的空域几十公里、
   地面作战区几公里）——沙海 12.7 公里见方，按真速度喷气机 40 秒飞穿。
10. **没有超速 / 过载断翼**：战雷超过极限速度、过载撕翼，襟翼、起落架超速会坏。
11. **飞机在跑道出生**：战雷陆战是空中出生（几公里外、一两千米高），直升机才在停机坪；可以两样都留。

对局、界面、声音
12. **没有车组语音**（「击穿！」「跳弹」「着火了」「炮手阵亡」「装填完毕」），要录音素材。
13. **地图没有 A～J / 1～10 方格编号**，没有地图标点、无线电快捷指令（「需要支援 C3」「跟我来」）。
14. **击杀播报只有名字**（Round.lua / Bots.lua 的 feed）：战雷写「谁（什么车）击毁了谁（什么车）」。
15. **车外没有弹孔、烧痕**。

1～8、12～15 是 C 认领的「整个游戏做成战雷」那一块，9～11 是 A 的飞行手感；C、A 回来想接哪条在这里写一笔，B 等用户定了先做哪几条。
