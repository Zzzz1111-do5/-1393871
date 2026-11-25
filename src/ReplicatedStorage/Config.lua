-- Roblox全面大战场——数值（服务器、客户端共用）
-- 文字都在 Lang.lua（中英双语），这里只放编号和数
local Config = {}

Config.Version = "1.0-alpha"
Config.Build = "dev"   -- tools/build.luau 生成地图文件 / 只换脚本的更新包时换成「构建日期 提交号」：主菜单右下、开服时的输出窗口都写着，一看就知道新脚本换没换上
Config.SaveKey = "IslandAssault_v1"   -- DataStore 名字（改了就是新存档；游戏改过名（暗剑：登岛战 → Roblox全面大战场 → 全面大战场 / Island Assault）照旧用这个，玩家的军衔、经验不丢）
Config.Tick = 0.1                     -- 推演步长（秒）：占领、AI、炮弹、导弹
-- 地图：开服以后进来的人在选地图界面投票定一张（init.server.lua；Studio 里给 Workspace 设属性 MapName 直接定）——island（棕榈岛，Map.lua）、
--   sands（海湾战争式的纯陆地沙漠「沙海」，MapSands.lua，五个阶段的突破）。原来还有 desert（「沙漠风暴」，征服）：用户 11-24 删了
--   Config.Map 是现在这张；跟着地图变的数（阶段表）由 Config.useMap(id) 换（服务器、客户端换地图时都调）
Config.Map = "sands"   -- 只剩沙海（用户 11-24：「全部默认沙海地图吧，登岛那个也删了」）
Config.MapDefault = "sands"
-- 选地图投票（用户 11-23：「三张地图改成投票制，进去投票选地图」）：进服在选地图界面投票（能改票）——第一票投出后 time 秒按票数最多的开（平票随机挑），
--   在场的人都投了就再等 grace 秒（还能改）提前开；没人投：空服几秒、有人不投 MapWaitMax 秒后按 MapDefault 开
Config.MapVote = { time = 25, grace = 3 }

---------------------------------------------------------------- 回合

-- 准备 → 战斗（攻方每拿下一个据点加时间）→ 结算 → 重新随机分队
Config.Round = {
  prep = 30,            -- 准备（选兵种、等人）
  battle = 30 * 60,     -- 战斗时长（地图放大到 3 倍后从 20 分钟加到 30 分钟：走得远）
  perCapture = 240,     -- 攻方每拿下一个据点加多少秒
  overtime = 90,        -- 时间到时有据点正在被占：最多加时多久
  results = 20,         -- 结算画面
}
Config.RespawnDelay = 6   -- 阵亡后几秒回到部署界面
Config.MinPlayersToStart = 1

-- 分阶段突破（用户：玩法不够清晰、没法快速进入战局、感受不到激烈对抗）：5 个据点不再同时开，一个阶段一个阶段打——
--   同时只能占当前阶段的据点，两边的人（机器人也是）都往那里去；打下这一阶段的全部据点，战线往前推、出生点跟着走。
--   time 这一阶段限时（秒，到点守方赢；有据点正在被占就加时）；flank 侧翼据点：从这一阶段起开放，拿下给攻方补兵力，不拿也能往前推
Config.Stages = {   -- 用户：同一时间只开一个交战区（像 Battlefield 的突破模式）——一个阶段一个据点，灯塔岛 B 不开放
  { id = "beach", points = { "A" }, time = 7 * 60 },     -- 第一阶段：抢滩前哨岛
  { id = "port", points = { "C" }, time = 6 * 60 },      -- 第二阶段：登陆主岛，拿下港口
  { id = "airfield", points = { "D" }, time = 6 * 60 },  -- 第三阶段：机场
  { id = "hq", points = { "E" }, time = 7 * 60 },        -- 第四阶段：指挥部决战
}
-- 各张图的阶段表：沙海（没有海、没有登陆艇）五个阶段一个一个打——突破边境沙墙拿下哨所 A → 油田 B → 镇子 C → 空军基地 D → 岭上指挥部 E；
--   沙漠风暴是征服模式（Round.lua conquest：据点一直都开着），阶段表不用、留岛上的
Config.StagesByMap = {
  island = Config.Stages,
  sands = {
    { id = "border", points = { "A" }, time = 6 * 60 },     -- 第一阶段：越过沙墙和反坦克壕，拿下边境哨所
    { id = "oil", points = { "B" }, time = 6 * 60 },        -- 第二阶段：油田（油井在烧）
    { id = "town", points = { "C" }, time = 6 * 60 },       -- 第三阶段：镇子（巷战）
    { id = "airfield", points = { "D" }, time = 6 * 60 },   -- 第四阶段：空军基地（加固机库）
    { id = "hq", points = { "E" }, time = 7 * 60 },         -- 第五阶段：岩岭上的指挥部
  },
}
function Config.useMap(id)
  Config.Map = id or "sands"
  Config.Stages = Config.StagesByMap[Config.Map] or Config.StagesByMap.sands
end
Config.useMap("sands")
Config.FirstWave = 45   -- 只有第一波坐登陆艇抢滩：开战后这么多秒以内还能上艇，之后攻方在攻击出发阵地出生（Round.lua）
-- 攻方兵力（门票）：攻方每阵亡一个（真人、机器人都算）扣 1，扣光了守方赢；打下一个阶段、拿下侧翼据点补兵力；人多的服多给一点
Config.Tickets = { start = 240, perReal = 10, perStage = 100, flank = 50, extraCap = 60 }   -- extraCap：阶段里拿下一个点（还没打完这一阶段）加多少秒
-- 昼夜（客户端 DayNight.lua）：用户 11-18「把白天模式去掉，就锁定晚上」锁过一阵；11-25「把抽搐bug和昼夜更替弄完」——又打开：
--   lockNight = false 按 period（一圈多少秒，每局从早上 7:30 开始）昼夜更替：白天约 13 分钟、黄昏 / 清晨各一分多钟、夜里不到 6 分钟；
--   天黑提示开夜视、天亮夜视自己收起，地图上的灯和光晕只在天黑以后亮（Night.lua）。要再锁晚上把 lockNight 改回 true（clock 是锁定时的钟点）
Config.DayNight = { lockNight = false, clock = 2.3, period = 24 * 60 }
Config.RallyBack = 200   -- 守方集结点：据点后面多远（格，150～250），守方在这里出生（用户：出生点跟着战线走）
Config.StageOff = 260    -- 攻方攻击出发阵地：据点往攻方来的方向多远（格，200～300），第一波以后攻方在这里出生（Round.lua）

-- 占领：圈里数双方的人（步兵、地面载具；飞机、舰艇不算；机器人也算）
Config.Capture = {
  r = 70,          -- 据点半径（和 Map.POINT_R 一样）
  height = 45,     -- 据点上下可占领的高度（格）
  slow = 45,       -- 攻方多 1 人：几秒占完
  fast = 15,       -- 攻方多 3 人以上：几秒占完
  decay = 90,      -- 守方人不少于攻方：进度从满退到零要几秒
  botW = 0.35,     -- PvP（用户：不要让 AI 带节奏）：机器人占点只算 0.35 个人；攻方有真人在服务器上时，圈里没有攻方真人就不涨
}

Config.Teams = {
  atk = { color = Color3.fromRGB(220, 70, 55), brick = "Bright red" },
  def = { color = Color3.fromRGB(64, 186, 92), brick = "Bright green" },   -- 用户 11-21：蓝色全部改成绿色（守方原来是蓝）
}

---------------------------------------------------------------- 步兵兵种（9 种，无限复活）：主枪统一是 M4（狙击手另有狙击枪），机枪手并进了步枪兵

-- hp 血量、speed 走路速度；weapons 带的武器（按顺序进背包：1、2、3…）
Config.Roles = {
  { id = "rifle", hp = 100, speed = 16, weapons = { "m4", "grenade" } },
  { id = "sniper", hp = 90, speed = 16, weapons = { "sniper", "m4" } },
  { id = "at", hp = 100, speed = 15, weapons = { "m4", "rpg" } },
  { id = "aa", hp = 100, speed = 15, weapons = { "m4", "manpads" } },
  { id = "medic", hp = 100, speed = 16.5, weapons = { "m4", "medkit" } },
  { id = "engineer", hp = 105, speed = 15.5, weapons = { "m4", "repair", "breach" } },
  { id = "mortar", hp = 100, speed = 15, weapons = { "m4", "mortar" } },
  { id = "spec", hp = 110, speed = 18, weapons = { "m4", "c4", "grenade" } },
  { id = "spotter", hp = 95, speed = 16, weapons = { "m4", "binoc" } },
  -- 乘员（用户 11-25「不要让玩家拿枪之类的了 就跟战雷完全一样 不要让玩家作为个体活动」）：出击直接坐进车里（Tech.lua deployVeh），身上什么都不带
  { id = "crew", hp = 100, speed = 16, weapons = {} },
}
Config.RoleById = {}
for _, r in ipairs(Config.Roles) do Config.RoleById[r.id] = r end

-- 装备栏（用户：开局不选兵种，默认就是一个士兵，部署界面底下改枪械配置）：四格各挑一样，服务器按这张表核对；
--   上面的「兵种」只剩老的名字（测试、机器人、战况表的标签）还认
Config.Loadout = {
  { id = "primary", opts = { "m4", "qbz191", "lmg", "smg", "shotgun", "sniper" } },   -- 主武器（机枪、冲锋枪、霰弹枪两边各是自己的制式：GearDefs.BY）
  { id = "secondary", opts = { "pistol", "tablet" }, none = true },   -- 副武器：手枪、战术平板（R 币解锁：Config.Passes.tablet；用户：不要按 B 召唤平板，平板做成物品）
  { id = "launcher", opts = { "rpg", "manpads", "mortar" }, none = true },   -- 发射器（可以不带：跑得快一点）
  { id = "gadget", opts = { "medkit", "repair", "breach", "binoc" } },  -- 装备
  { id = "throw", opts = { "grenade", "c4" } },                        -- 投掷
}
Config.LoadoutDefault = { primary = "m4", secondary = "pistol", gadget = "medkit", throw = "grenade" }
-- 兵种（用户 11-24：「各种角色配备各种武器」）：部署界面顶上一排，点一个就把装备栏换成这个兵种的一套（之后每格照样能改）；
--   primary 写 rifle 的按阵营给：攻方（解放军）QBZ-191、守方（美军）M4
Config.RoleKits = {
  { id = "rifle", kit = { primary = "rifle", secondary = "pistol", gadget = "medkit", throw = "grenade" } },
  { id = "mg", kit = { primary = "lmg", secondary = "pistol", gadget = "medkit", throw = "grenade" } },
  { id = "assault", kit = { primary = "smg", secondary = "pistol", gadget = "breach", throw = "grenade" } },
  { id = "breacher", kit = { primary = "shotgun", secondary = "pistol", gadget = "breach", throw = "c4" } },
  { id = "sniper", kit = { primary = "sniper", secondary = "pistol", gadget = "binoc", throw = "grenade" } },
  { id = "at", kit = { primary = "rifle", secondary = "pistol", launcher = "rpg", gadget = "medkit", throw = "c4" } },
  { id = "aa", kit = { primary = "rifle", secondary = "pistol", launcher = "manpads", gadget = "medkit", throw = "grenade" } },
  { id = "medic", kit = { primary = "smg", secondary = "pistol", gadget = "medkit", throw = "grenade" } },
  { id = "engineer", kit = { primary = "shotgun", secondary = "pistol", gadget = "repair", throw = "c4" } },
  { id = "mortar", kit = { primary = "rifle", secondary = "pistol", launcher = "mortar", gadget = "binoc", throw = "grenade" } },
}
function Config.roleKit(id, team)
  for _, r in ipairs(Config.RoleKits) do
    if r.id == id then
      local k = table.clone(r.kit)
      if k.primary == "rifle" then k.primary = (team == "atk") and "qbz191" or "m4" end
      return k
    end
  end
  return nil
end
-- 改枪（GunMods.lua，用户 11-20：对标三角洲行动）：killXp 用这把枪打死一个人（真人 / 机器人）加多少枪械经验，
--   unlockAll 配件全部解锁（不用升级），studioAll 在 Studio 里测试时全部解锁（发布到线上照常按等级）
-- 11-23 起配件要解锁（升到等级、或者拿金币买，Economy.lua）：Studio 里测试也照样上锁（studioAll 改成 false），想看全部配件改回 true
Config.GunMods = { killXp = 100, botXp = 60, unlockAll = false, studioAll = false }

-- R 币解锁（游戏通行证 Game Pass）：在 Roblox 创作者后台给这个体验建两个通行证（价格照 price），把通行证编号填进 id——
--   id 还是 0 的时候谁都能用（没上架前不挡人，Studio 里测试也方便）；填了编号就只有买了的人能用，没买的点了弹出购买框
--   item：这个通行证解锁什么（装备栏里的物品 / 召唤点的机型）
Config.Passes = {
  tablet = { id = 0, price = 99, item = "tablet" },   -- 战术平板（副武器）：召唤步战车、空投补给、呼叫火力
  b2 = { id = 0, price = 199, item = "b2" },          -- B-2 隐身轰炸机（守方）
}
Config.PassFor = {}   -- 物品 / 机型 → 通行证名
for k, v in pairs(Config.Passes) do Config.PassFor[v.item] = k end
Config.Soldier = { hp = 100, speed = 16, heavy = 15 }   -- 带着发射器（火箭筒、防空导弹、迫击炮）走慢一点

-- 左下的雷达（用户：小地图改成雷达风格的绿色、圆形，能看到范围内的友军和敌军）：
--   友军都显示；敌人里车、船、飞机在范围内就显示（雷达回波），步兵要在自己视线里、开了枪（没消音的，开枪的地方闪一下）或者被友军标记了才显示——
--   不然雷达就成了透视；allEnemies = true 时范围内的敌人全显示
Config.Radar = { range = 520, veh = 900, heli = 4000, jet = 9000, sweep = 2.4, ping = 3, allEnemies = false }   -- 半径（格：步兵约 186 米、地面载具 320 米、直升机 1.4 公里、固定翼 3.2 公里）、扫一圈几秒、开枪的红圈留几秒

---------------------------------------------------------------- 武器

-- 目标类别：inf 步兵、light 轻型车、armor 装甲、air 飞机直升机、ship 舰艇、fort 工事
-- kind：gun 直射（服务器射线判定）；proj 有弹道的弹（speed 弹速、splash 溅射、drop 是否下坠）；throw 投掷（fuse 引信秒数）；
--   lock 锁定导弹（打 air，lockTime 锁定要几秒）；mortar 曲射（点地图上 / 准星下的地面，minR maxR 射程）；
--   heal 治疗（r 范围、amt 每次、cd 冷却）；repair 修车、修工事（每秒 rate）；place 放置（炸药包）；breach 破障器材；spot 望远镜标记敌人、呼叫炮击
--   （雷区、铁丝网、炮都是地图自带的，玩家不能自己布雷、架炮）
-- dmg 每发、rate 几秒一发、mag 弹匣、reserve 备弹（不算弹匣里的；没写就是无限）、reload 换弹秒数、range 射程、spread 散布（度）；
-- vs 对各类目标的伤害倍数
-- 枪（kind gun）的散布（用户 11-18：提高手感）：spread 是腰射，adsK 开镜乘几，moveK 跑到 16 格每秒多散几倍（开镜减半），
--   跳在半空乘 2.2，bloom = { 每发多几度, 最多多几度, 每秒收回几度, 停手几秒后才收回 }（连射越打越散，停手很快收回；开镜减半）——Config.gunSpread
local G_VS = { inf = 1, light = 0.15, armor = 0, air = 0.1, ship = 0, fort = 0.04 }
Config.Weapons = {
  m4 = { kind = "gun", dmg = 25, rate = 0.08, mag = 30, reload = 2.6, range = 650, spread = 0.55, adsK = 0.35, moveK = 0.8, bloom = { 0.06, 0.55, 2.2, 0.12 },
    auto = true, vs = G_VS, head = 1.6,
    -- rc 每发的后坐（度：Fx.lua G.kick）；fall 伤害衰减（从射程的 42% 开始掉，到射程尽头剩 72%：改枪的「有效射程」）
    rc = { up = 0.3, side = 0.12, punch = 1.0, roll = 0.5 }, fall = { 0.42, 0.72 },
    scope = 3.5, optic = "acog" },   -- 两队都用这一种（第一人称动作照 M4 动作包）；上机匣导轨上一具 ACOG 3.5 倍镜（用户：武器瞄准没有镜子）
  -- 狙击枪：开镜 0.03°（原来不分开不开镜都是这么准），腰射 2.6°（不开镜别指望一枪一个）
  sniper = { kind = "gun", dmg = 96, rate = 1.35, mag = 5, reload = 3.0, range = 1500, spread = 2.6, adsK = 0.0115, moveK = 1.5,
    vs = { inf = 1, light = 0.25, armor = 0, air = 0.1, ship = 0, fort = 0.05 }, head = 2.2, scope = 5,
    rc = { up = 1.8, side = 0.35, punch = 3.4, roll = 1.2 } },
  -- 各兵种的枪（用户 11-24：「各种角色配备各种武器」）：两边各用自己的制式（GearDefs.BY：解放军 / 美军的原模型），数值一样（公平）；
  --   没有瞄准镜的开镜按机械瞄具（照门、准星对正），adsZoom 开镜放大多少；pellets 霰弹一枪几颗弹丸（dmg 是每颗的，spread 是弹丸散开的锥角）
  qbz191 = { kind = "gun", dmg = 26, rate = 0.08, mag = 30, reload = 2.7, range = 680, spread = 0.52, adsK = 0.34, moveK = 0.82, bloom = { 0.065, 0.55, 2.2, 0.12 },
    auto = true, vs = G_VS, head = 1.6, rc = { up = 0.32, side = 0.12, punch = 1.0, roll = 0.5 }, fall = { 0.44, 0.72 }, adsZoom = 1.3 },   -- 5.8 毫米，射速每分钟 750 发
  lmg = { kind = "gun", dmg = 25, rate = 0.075, mag = 100, reload = 6.2, range = 760, spread = 0.95, adsK = 0.42, moveK = 1.7, bloom = { 0.05, 0.85, 1.8, 0.12 },
    auto = true, vs = G_VS, head = 1.5, rc = { up = 0.24, side = 0.16, punch = 0.8, roll = 0.4 }, fall = { 0.5, 0.75 }, adsZoom = 1.3, adsSpd = 0.7, heavy = true },   -- 弹链 100 发、换弹慢、开镜慢、走着打散、背着走慢一点
  smg = { kind = "gun", dmg = 19, rate = 0.06, mag = 40, reload = 2.2, range = 320, spread = 0.62, adsK = 0.45, moveK = 0.45, bloom = { 0.05, 0.6, 2.6, 0.12 },
    auto = true, vs = G_VS, head = 1.5, rc = { up = 0.2, side = 0.1, punch = 0.7, roll = 0.4 }, fall = { 0.3, 0.55 }, adsZoom = 1.25 },   -- 每分钟 1000 发、近距离、跑着打也准
  shotgun = { kind = "gun", pellets = 9, dmg = 13, rate = 0.32, mag = 7, reload = 3.2, range = 90, spread = 4.5, adsK = 0.8, moveK = 0.3,
    vs = G_VS, head = 1.25, rc = { up = 1.4, side = 0.4, punch = 2.6, roll = 1.0 }, fall = { 0.2, 0.35 }, adsZoom = 1.2 },   -- 半自动、一枪 9 颗、二十几米外就不行了
  pistol = { kind = "gun", dmg = 24, rate = 0.14, mag = 15, reload = 1.7, range = 260, spread = 0.7, adsK = 0.45, moveK = 0.5,
    vs = G_VS, head = 1.6, rc = { up = 0.7, side = 0.18, punch = 1.4, roll = 0.6 }, fall = { 0.35, 0.6 }, adsZoom = 1.2 },   -- 半自动
  rpg = { kind = "proj", dmg = 110, rate = 0.5, mag = 1, reserve = 3, reload = 3.4, range = 700, spread = 0.4, speed = 230, splash = 11, drop = true,
    vs = { inf = 1, light = 5, armor = 5.5, air = 3, ship = 2.5, fort = 4 } },
  manpads = { kind = "lock", dmg = 120, rate = 0.5, mag = 1, reserve = 1, reload = 3.5, range = 1400, speed = 320, splash = 9, lockTime = 1.6,
    vs = { inf = 0.3, light = 0.5, armor = 0.3, air = 6, ship = 0.5, fort = 0.2 } },
  grenade = { kind = "throw", dmg = 115, rate = 1.0, mag = 1, reserve = 1, reload = 0.8, range = 90, fuse = 2.8, splash = 14, speed = 70,
    vs = { inf = 1, light = 0.8, armor = 0.15, air = 0, ship = 0.1, fort = 0.6 } },
  mortar = { kind = "mortar", dmg = 95, rate = 1.6, mag = 1, reserve = 11, reload = 2.6, minR = 90, maxR = 950, splash = 17, flight = 5,
    vs = { inf = 1, light = 0.8, armor = 0.3, air = 0, ship = 0.25, fort = 0.8 } },
  medkit = { kind = "heal", amt = 35, r = 14, cd = 6, mag = 1, rate = 0.5, reload = 0 },
  repair = { kind = "repair", rate = 90, range = 16, mag = 1, reload = 0 },
  breach = { kind = "breach", range = 6, detect = 34, time = 1.6, mag = 1, reload = 0 },   -- 破障器材：探雷（detect 格以内）、排雷 / 剪铁丝网（离得 range 格以内按住 time 秒）
  c4 = { kind = "place", dmg = 260, splash = 13, mag = 1, reserve = 1, reload = 0.6, rate = 0.8, trigger = "remote",
    vs = { inf = 1, light = 4, armor = 5, air = 0, ship = 2, fort = 5 } },
  tablet = { kind = "pad", mag = 1, reload = 0 },   -- 战术平板：拿在手上就打开平板（客户端 TacPad.lua），收起来就关上
  binoc = { kind = "spot", range = 1600, spotTime = 12, cd = 4, strikeCd = 75, strike = { n = 8, r = 26, dmg = 120, splash = 20, flight = 6,
    vs = { inf = 1, light = 1, armor = 0.45, air = 0, ship = 0.3, fort = 1 } }, mag = 1, reload = 0 },
}

---------------------------------------------------------------- 载具（按名额；每队每种同时在场有上限，按队伍人数算）

-- cat 类别：tank 坦克、apc 装甲车、aa 防空、arty 火炮、heli 直升机、jet 固定翼、ship 舰艇
-- 每类按队给几个型号（Lang 里有名字）；hp、speed（格 / 秒）、tgt 中弹按什么类别算伤害
Config.VehicleCats = {
  tank = { tgt = "armor", hp = 1600, speed = 34, perN = 8, min = 1, max = 4, cd = 60 },
  apc = { tgt = "light", hp = 800, speed = 46, perN = 6, min = 1, max = 5, cd = 45, seats = 5 },
  aa = { tgt = "light", hp = 700, speed = 36, perN = 12, min = 1, max = 2, cd = 60 },
  arty = { tgt = "light", hp = 650, speed = 30, perN = 14, min = 0, max = 2, cd = 70 },
  heli = { tgt = "air", hp = 900, speed = 85, perN = 12, min = 1, max = 3, cd = 75, seats = 4 },
  jet = { tgt = "air", hp = 700, speed = 260, perN = 12, min = 1, max = 3, cd = 90 },
  ship = { tgt = "ship", hp = 3000, speed = 45, perN = 16, min = 0, max = 2, cd = 120 },
}
Config.VehicleOrder = { "tank", "apc", "aa", "arty", "heli", "jet", "ship" }
-- 跳弹（用户：跳弹也做出来）：炮弹打在坦克（armor）、轻装甲车（light）上，入射方向离装甲面法线超过 a0 度开始有可能滑开、a1 度一定滑开；
--   滑开的弹只伤 dmg 倍，顺着反射方向飞走（速度剩 keep 倍，再飞 life 秒，碰到东西不炸）
Config.Ricochet = { a0 = { armor = 62, light = 70 }, a1 = { armor = 80, light = 84 }, dmg = 0.04, keep = 0.5, life = 1.2 }
-- 型号：每队每类可选的型号（编号对应 Lang 里的名字和模型名）；mod 按型号微调（hp 倍数、速度倍数、主炮伤害倍数）
Config.Vehicles = {
  atk = {
    tank = { "ztz96", "ztz99a", "t90m" },   -- ZTQ-15 轻坦 11-19 删掉了（用户：建模非常粗糙）
    apc = { "ztd05", "zbd05", "zsl92b", "ptl02", "bmp3" },
    aa = { "pgz07", "pgl625", "ld2000", "pantsir" },
    arty = { "plz07" },
    heli = { "z10", "z20" },
    jet = { "j15t", "j35", "j20", "j36", "j16", "j11", "j10", "j8", "h6k", "gj11", "gj2" },   -- 歼-50 11-22 删掉了（用户：j50 删掉）；歼-8II 11-23 加的
    ship = { "t055", "t054a", "t022" },
  },
  def = {
    tank = { "m10", "m1a1", "m1a2" },
    apc = { "m1117", "hmmwv", "jltv", "m2a3", "stryker", "m1150" },
    aa = { "m163", "mshorad", "cram", "patriot" },
    arty = { "m109a7", "m270" },   -- M777 是地图自带的炮位（Forts），走过去就能用
    heli = { "ah64e", "uh60", "ch47" },
    jet = { "a10c", "f35", "f22", "f16", "f15", "f14", "mq9", "b2" },   -- F-16C、F-15C、F-14A 11-23 加的
    ship = { "ddg125", "cg47", "lcs2", "pbr" },
  },
}
-- 两边都能用对方的载具（用户 11-23：「两边都可以用对方的载具」）：坦克、装甲车、防空、火炮、直升机、飞机的召唤点上两边的型号都有
--   （自己这一边的排前面）；舰艇还是各用各的（码头、舰队不一样）。召唤点（Depots.lua）、生成点牌子（Armor / Air 的 vehModels）按 TeamVehicles 列
Config.CrossVehicles = { tank = true, apc = true, aa = true, arty = true, heli = true, jet = true }
function Config.TeamVehicles(team, cat)
  local own = (Config.Vehicles[team] or {})[cat] or {}
  if not Config.CrossVehicles[cat] then return own end
  local other = (team == "atk") and "def" or "atk"
  local out, seen = {}, {}
  for _, list in ipairs({ own, (Config.Vehicles[other] or {})[cat] or {} }) do
    for _, id in ipairs(list) do
      if not seen[id] then seen[id] = true table.insert(out, id) end
    end
  end
  return out
end
-- 金币（Economy.lua，用户 11-23：「把很多坦克飞机直升机搞成金币解锁……金币 pvp 或者打 pve 来……改枪配件也是需要解锁」）
--   startCoins 新玩家的金币；一局打完：得分 × perScore + 赢了 win / 输了 lose；PvE 关卡打通另有奖励（Config.Pve）
--   veh：载具价钱（每类都有几型不要钱，进服就能开）；不在表里的（舰艇）不要钱；B-2 照旧是 R 币通行证（Config.Passes）
--   配件：没到这把枪的解锁等级也能拿金币买（attBase + attPerLv × 等级），到了等级照旧白给
--   unlockAll：true = 载具全部直接能开（自己测试用；配件全开是 Config.GunMods.unlockAll）
--   infinite：true = 无限金币（用户 11-24：「给我先设置成无限金币」）——买载具、配件不查余额、不扣钱，界面上写 ∞；
--     存档里的金币照旧（挣的照样记），改回 false 就恢复正常；上线前记得改回 false
Config.Economy = {
  unlockAll = false,
  infinite = true,
  startCoins = 1500,
  perScore = 0.1, win = 200, lose = 60,
  veh = {
    -- 坦克
    ztz96 = 0, m10 = 0, m1a1 = 1500, ztz99a = 3000, m1a2 = 3000, t90m = 2800,
    -- 装甲车
    ztd05 = 0, m1117 = 0, hmmwv = 0, zsl92b = 600, jltv = 600, zbd05 = 900, stryker = 1000, ptl02 = 1200, m2a3 = 1200, m1150 = 1500, bmp3 = 1300,
    -- 防空
    pgz07 = 0, m163 = 0, pgl625 = 1200, mshorad = 1500, ld2000 = 1800, cram = 1800, pantsir = 2600, patriot = 3500,
    -- 火炮
    plz07 = 0, m109a7 = 0, m270 = 2500,
    -- 直升机
    z20 = 0, uh60 = 0, ch47 = 600, z10 = 2200, ah64e = 2800,
    -- 飞机
    j10 = 0, a10c = 0, mq9 = 1200, j11 = 1500, gj2 = 1500, j15t = 1800, gj11 = 2200, j16 = 2600, f35 = 3200, j35 = 3500,
    f22 = 4500, j20 = 4500, h6k = 5000, j36 = 6500,
  },
  attBase = 100, attPerLv = 80,
}
-- PvE 关卡（Pve.lua，用户 11-23：「金币 pvp 或者打 pve 来 你搞一些关卡吧」）：真人都在攻方，跟电脑打；一关一关解锁
--   map 哪张图（岛：登陆战，拿下 caps 个据点就赢；沙漠：征服，敌方兵力 tickets 扣光就赢）；enemies 敌方电脑几个、allies 友军电脑几个
--   （多一个真人敌人多 perPlayer 个、友军少一个）；skill 电脑的枪法和反应（1 是对战里的水平）；aiVeh 敌方开不开坦克、飞机；reward 打通的金币（第一次 × firstBonus）
Config.Pve = {
  firstBonus = 2, replay = 0.5, perPlayer = 2,   -- 第一次打通奖励 ×2、再打 ×0.5；每多一个真人敌方多 2 个电脑
  -- ai（用户 11-24：「做关卡 越多越逼真越好」）：这一关电脑开的地面载具——def 敌方、atk 友军：max 同时几辆、tank 坦克占几成（其余步战车）、
  --   ids 只从这几型里挑（不给就从这一方能开的里挑：友军里有 T-90M、BMP-3 这些俄系）；简报写在 Lang 的 pve.b<关号>
  levels = {
    { map = "sands", caps = 1, enemies = 10, allies = 5, skill = 0.6, reward = 300 },
    { map = "sands", caps = 2, enemies = 14, allies = 5, skill = 0.75, reward = 450 },
    { map = "sands", caps = 3, enemies = 18, allies = 5, skill = 0.9, reward = 650, aiVeh = true,
      ai = { def = { max = 2, tank = 0, ids = { "m2a3", "stryker", "jltv" } }, atk = { max = 1, tank = 0 } } },
    -- 第 4、6、8 关原来在沙漠风暴（打光兵力）、第 1、2、3、5、7、11、14 关原来在岛上；11-24 用户把两张图都删了（「全部默认沙海地图吧，登岛那个也删了」）：
    --   十六关都在沙海、按据点算（沙海 A～E 五个阶段各一个据点，caps 最多 5）
    { map = "sands", caps = 2, enemies = 16, allies = 6, skill = 0.85, reward = 800, aiVeh = true,
      ai = { def = { max = 2, tank = 0.5 }, atk = { max = 2, tank = 0.5 } } },
    { map = "sands", caps = 4, enemies = 22, allies = 5, skill = 1.0, reward = 1000, aiVeh = true,
      ai = { def = { max = 3, tank = 0.67, ids = { "m1a1", "m2a3" } }, atk = { max = 2 } } },
    { map = "sands", caps = 3, enemies = 22, allies = 6, skill = 1.1, reward = 1300, aiVeh = true,
      ai = { def = { max = 4, tank = 1, ids = { "m1a1", "m1a2" } }, atk = { max = 3, tank = 1, ids = { "t90m", "ztz99a" } } } },
    { map = "sands", caps = 5, enemies = 26, allies = 6, skill = 1.2, reward = 1700, aiVeh = true,
      ai = { def = { max = 3 }, atk = { max = 2 } } },
    { map = "sands", caps = 5, enemies = 30, allies = 6, skill = 1.35, reward = 2500, aiVeh = true,
      ai = { def = { max = 4, tank = 0.75, ids = { "m1a2", "m1a1", "m2a3" } }, atk = { max = 3, ids = { "t90m", "ztz99a", "bmp3" } } } },
    -- 第 9～16 关（11-24 加）：沙海（突破，五个阶段）也有关卡；坦克战、机械化步兵、海岸防线、夜幕坦克战……
    { map = "sands", caps = 2, enemies = 20, allies = 6, skill = 1.0, reward = 1500, aiVeh = true,
      ai = { def = { max = 2, tank = 0.3, ids = { "m2a3", "stryker", "m1a1" } }, atk = { max = 2, tank = 0, ids = { "bmp3", "zbd05" } } } },
    { map = "sands", caps = 3, enemies = 26, allies = 6, skill = 1.2, reward = 1600 },
    { map = "sands", caps = 3, enemies = 26, allies = 6, skill = 1.25, reward = 1800, aiVeh = true,
      ai = { def = { max = 3, tank = 0.5, ids = { "m1a2", "m2a3", "m1150" } }, atk = { max = 2, ids = { "t90m", "bmp3" } } } },
    { map = "sands", caps = 4, enemies = 26, allies = 7, skill = 1.3, reward = 2200, aiVeh = true,
      ai = { def = { max = 3, tank = 0.67 }, atk = { max = 3, tank = 0.67 } } },
    { map = "sands", caps = 4, enemies = 24, allies = 6, skill = 1.35, reward = 2600, aiVeh = true,
      ai = { def = { max = 5, tank = 1, ids = { "m1a2", "m1a1" } }, atk = { max = 4, tank = 1, ids = { "t90m", "ztz99a", "ztz96" } } } },
    { map = "sands", caps = 5, enemies = 30, allies = 6, skill = 1.4, reward = 3000, aiVeh = true,
      ai = { def = { max = 4, tank = 0.5 }, atk = { max = 3 } } },
    { map = "sands", caps = 5, enemies = 32, allies = 7, skill = 1.45, reward = 3400, aiVeh = true,
      ai = { def = { max = 4, tank = 0.75, ids = { "m1a2", "m1a1", "m2a3" } }, atk = { max = 3, ids = { "t90m", "bmp3", "ztz99a" } } } },
    { map = "sands", caps = 5, enemies = 36, allies = 7, skill = 1.6, reward = 4000, aiVeh = true,
      ai = { def = { max = 5, tank = 0.7 }, atk = { max = 4, tank = 0.7 } } },
  },
}
function Config.VehPrice(id) return Config.Economy.veh[id] end   -- nil：不用金币（舰艇、R 币通行证的 B-2）
-- 战雷式对局（WtMatch.lua，用户 11-24 夜「把整个游戏做成战雷」）：重生点数 SP、出击阵容
--   每局每人 SP 从 sp0 起，第一辆车免费，以后出车按 cost 花（这一局每多出过一辆贵 rise）；得分攒 SP（每分 perScore），封顶 spMax；
--   一局最多开 lineup 种车，每种出 1 + backup 次；步兵出生不要 SP；PvE 关卡不收
-- noInfantry（用户 11-25「就跟战雷完全一样 不要让玩家作为个体活动」）：玩家不步行、不拿枪——出击界面从科技树的出击阵容里挑车，人直接坐在车里出现
--   （Tech.lua deployVeh）；下车 = 回出击界面（这辆算没了）
-- 战斗等级配对（Tech.lua，用户 11-25「都要做」）：一局的战斗等级 = 准备阶段在线真人出击阵容里最高的那辆（没人按 br0）；
--   能出的车最高到这一局 + brUp（战雷：最多碰到比自己高 1.0 的）；电脑开的车从科技树里挑 [这一局 − brUp, 这一局]；
--   真人不够一队 teamSize 个，电脑车补（每队最多 aiMax 辆，AIVeh.lua）
Config.Wt = { on = true, noInfantry = true, sp0 = 0, spMax = 3000, perScore = 0.5, lineup = 5, backup = 1, rise = 0.25,
  br0 = 4.0, brUp = 1.0, teamSize = 8, aiMax = 5,
  -- 三种模式（机库里投票，准备阶段按票数，开战定住；Tech.lua）：ab 街机（敌人都标、飞机空中出生）、rb 历史（只标近处看得见的）、
  --   sb 全真（不标、只能第一人称）；研究点、乘员经验按 modeK 乘
  mode0 = "rb", modeK = { ab = 1, rb = 1.3, sb = 1.6 }, airSpawnH = 1200,
  cost = { tank = 300, apc = 200, aa = 220, arty = 260, jet = 450, bomber = 550, drone = 280, heli = 380, transport = 240, ship = 400 } }
-- cat：地面车的 VehDefs cat（tank / apc / aa / arty）、飞机的 AirDefs cat（jet / heli）、舰艇 ship；nPaid：这一局已经花 SP 出过几辆
function Config.WtCost(id, cat, nPaid)
  local W, m = Config.Wt, Config.VehicleMod[id] or {}
  local k = cat
  if cat == "jet" then k = m.bomber and "bomber" or (m.drone and "drone" or "jet")
  elseif cat == "heli" then k = m.transport and "transport" or "heli" end
  local base = W.cost[k] or 250
  return math.floor(base * (1 + W.rise * math.max(0, nPaid or 0)) / 10 + 0.5) * 10
end
function Config.AttPrice(lv)
  if (lv or 0) <= 1 then return 0 end
  return Config.Economy.attBase + Config.Economy.attPerLv * lv
end
Config.VehicleMod = {
  m10 = { hp = 0.8, speed = 1.1, gun = 0.85 },
  ztz96 = { hp = 0.9 }, m1a1 = { hp = 0.95 }, ztz99a = { hp = 1.1, gun = 1.1 }, m1a2 = { hp = 1.1, gun = 1.1 }, t90m = { hp = 1.05, gun = 1.05 },
  zbd05 = { amphib = true }, bmp3 = { amphib = true }, ztd05 = { amphib = true, gun = 1.6 }, hmmwv = { hp = 0.5, speed = 1.25 }, jltv = { hp = 0.65, speed = 1.2 },
  m1150 = { hp = 1.4, speed = 0.8 }, m270 = { rocket = true }, patriot = { sam = true }, cram = { ciws = true },
  z20 = { transport = true }, uh60 = { transport = true }, ch47 = { transport = true, hp = 1.3 },
  h6k = { bomber = true, hp = 1.6, speed = 0.75 }, b2 = { bomber = true, hp = 1.5, speed = 0.8 }, a10c = { hp = 1.4, speed = 0.7 },
  gj11 = { drone = true, hp = 0.6 }, gj2 = { drone = true, hp = 0.6 }, mq9 = { drone = true, hp = 0.6, speed = 0.55 },
  t022 = { hp = 0.4, speed = 1.3 }, pbr = { hp = 0.25, speed = 1.4 }, lcs2 = { hp = 0.6, speed = 1.3 },
}
-- 这一队这一类最多同时在场几辆（按队伍人数，真人 + 机器人）；人数不到 VehicleCapFloor 按它算——原来机器人把每队补到 18 人，
--   去掉 AI 士兵以后（用户 11-18）人少的服务器照旧有那么多车（不然舰艇、火炮名额是 0）
Config.VehicleCapFloor = 18
function Config.VehicleCap(cat, teamN)
  local c = Config.VehicleCats[cat]
  local n = math.max(teamN or 0, Config.VehicleCapFloor or 0)
  return math.clamp(math.floor(n / c.perN) + c.min, c.min, c.max)
end

---------------------------------------------------------------- 机器人

Config.Bots = {
  minPerTeam = 0,        -- 每队保底人数：真人不够用 AI 补（用户 11-18：把 AI 士兵去掉——0 就一个都不出；代码留着，改回 18 就恢复）
  maxTotal = 40,         -- 全服最多几个机器人
  hp = 100, speed = 14,  -- 步兵机器人：血量、走路速度（格 / 秒）
  weapon = "m4",         -- 用哪种枪的伤害、射程
  sight = 520,           -- 看多远
  reaction = 0.8,        -- 发现新目标后多久开第一枪（秒，随机 ±40%）
  fireGap = 0.36,        -- 两枪之间（秒）
  spread = 0.8, spreadPer = 0.004,   -- 散布：基础几度 + 每格距离多几度（100 格约 1.2°、300 格约 2°）
}

---------------------------------------------------------------- 得分、经验、军衔

-- 单兵战术平板（每个人都有，B 键拿出来；用户：能召唤空投载具、空中打击，但必须有次数限制）：
--   在平板的地图上点目标点，呼叫一样东西；每样每局有次数（n，阵亡不补，新一局重置）、用完一次自己冷却 cd 秒；
--   同一种全队 teamCd 秒内只能叫一次（几十个人同时叫会把地图炸平）；目标离自己不超过 range 格；只在开战以后能叫
--   flight：从呼叫到落地 / 命中几秒；veh 空投的车（按阵营）；vmax 全队空投下来还活着的车最多几辆
--   打击的伤害按 Weapons 那套（dmg、splash、vs 对各类目标的倍数）；扫射、轰炸沿「自己 → 目标点」的方向排开 len 格
Config.TacPad = {
  range = 4200,
  teamCd = 20,
  order = { "vdrop", "supply", "pgm", "gunrun", "cluster" },
  items = {
    vdrop = { kind = "drop", n = 1, cd = 240, flight = 10, veh = { atk = "zsl92b", def = "m2a3" }, vmax = 3 },   -- 空投步战车（用户：平板能召唤步战车）：92B 轮式步战车 / M2A3 布雷德利
    supply = { kind = "supply", n = 2, cd = 90, flight = 8, r = 20, life = 75, heal = 8 },
    pgm = { kind = "pgm", n = 2, cd = 90, flight = 6, w = { id = "pgm", dmg = 420, splash = 26, vs = { inf = 1, light = 3, armor = 2.4, air = 0.3, ship = 1.6, fort = 3 } } },
    gunrun = { kind = "gunrun", n = 1, cd = 150, flight = 6, len = 170, hits = 24, w = { id = "gunrun", dmg = 60, splash = 7, vs = { inf = 1, light = 1.5, armor = 0.35, air = 0.5, ship = 0.4, fort = 0.6 } } },
    cluster = { kind = "cluster", n = 1, cd = 240, flight = 9, len = 230, bombs = 12, w = { id = "cluster", dmg = 200, splash = 18, vs = { inf = 1, light = 2, armor = 1.2, air = 0.2, ship = 1, fort = 1.8 } } },
  },
  -- 飞过来的飞机（客户端画）：精确打击战斗机、扫射攻击机、集束轰炸机、空投直升机
  jets = { atk = { pgm = "j20", gunrun = "j16", cluster = "h6k", drop = "z20" }, def = { pgm = "f35", gunrun = "a10c", cluster = "b2", drop = "ch47" } },
}

Config.Score = { kill = 100, botKill = 60, assist = 40, capture = 300, captureAssist = 120, heal = 10, repair = 10, spot = 15, win = 500, lose = 150, vehicleKill = 200,
  fortKill = 250, defuse = 30, wireCut = 15, revive = 60, reviveAlly = 40 }   -- 救起队友：带急救包 / 没带
-- 倒地与救援（Revive.lua，用户 11-23「按你想的来弄」）：致命的一下先倒地，队友按住 E 救起来
-- 人人都能按 Z 标记看到的敌人（Weapons.lua 的 ACT.spot）：比望远镜近、锥窄、标记时间短
Config.QuickSpot = { range = 620, cone = 3, spotTime = 7, cd = 1.5 }
-- 车里激光测距后报告敌情（M1A2 SEPv2 的 CITV、布雷德利的 CIV：Weapons.lua 的 ACT.vspot）：4 公里、锥 1.2°、标 20 秒
Config.VehSpot = { range = 11200, cone = 1.2, spotTime = 20, cd = 2 }
-- 小队（Squads.lua）：每队自动分成几个小队，能在队友身边出生
Config.Squad = { size = 4, safe = 6 }   -- 一个小队几个人；队友几秒内没挨打才能往他身边出生
Config.Revive = {
  on = true,
  bleed = 20,        -- 倒地多久没人救就阵亡（秒）
  overkill = 70,     -- 一下打掉的比剩下的血多这么多：直接阵亡（爆炸、炮弹、狙击爆头）
  range = 8,         -- 离多近能救（格）
  hold = 4.0,        -- 没带急救包：按住 E 多久
  medicHold = 1.6,   -- 带着急救包
  hp = 0.35,         -- 没带急救包救起来几成血
  medicHp = 1.0,     -- 带着急救包：满血
  giveUp = 1.0,      -- 按住空格多久放弃
  afterDown = 1,     -- 倒地以后阵亡：再等几秒能重新部署（等救援的时间已经过了）
  markR = 220,       -- 倒地的队友头顶的救援标记多远看得见（格）
}
Config.Ranks = { 0, 500, 1500, 3500, 7000, 12000, 20000, 32000, 50000, 75000, 110000, 160000, 230000, 330000, 480000 }   -- 累计经验门槛（Lang 里有军衔名）
function Config.RankOf(xp)
  local i = 1
  for k, v in ipairs(Config.Ranks) do
    if xp >= v then i = k end
  end
  return i
end

-- 枪这一发的散布（度）：服务器（Weapons.lua）开枪时按它打，客户端准星（Play.lua）照它画——两边一样
--   ads 开着镜；speed 水平速度（格 / 秒）；air 在半空；bloom 连射攒下的（度）
-- 连射攒下的散布（度）：st = { v 上一发打完攒到多少, t 上一发的时刻 }；停手 bloom[4] 秒以后才开始收回（连射时攒得起来）
function Config.bloomAt(w, st, t)
  local bl = w.bloom
  if not bl or not st then return 0 end
  return math.max(0, st.v - math.max(0, t - st.t - (bl[4] or 0.12)) * bl[3])
end

function Config.gunSpread(w, ads, speed, air, bloom)
  local s = w.spread or 0
  if ads then s *= (w.adsK or 1) end
  local mv = math.clamp(((speed or 0) - 2) / 14, 0, 1)
  s *= 1 + (w.moveK or 0) * mv * (ads and 0.5 or 1)
  if air then s *= 2.2 end
  return s + (bloom or 0) * (ads and 0.5 or 1)
end

-- 战场氛围（用户 11-18：按 3A 游戏的标准做到惊艳，参考战雷、战地；服务器 Battle.lua、客户端 Warfx.lua）
--   crater 弹坑：k 坑口半径 / 杀伤半径（按爆炸种类）、minR / maxR 坑口半径（格）上下限、depth 坑深 / 坑口半径、maxDepth 最深几格、
--     gap 离已有的坑多近不再炸（两坑半径和的倍数）、max 一局最多几个、perSec 一秒最多挖几个（多的排队）
--   illum 照明弹：every 隔几秒打一发（随机范围）、alive 同时最多几发、height 在离地多高炸开、burn 烧几秒、fall 每秒落几格、sea 攻方舰队打的比例
--   bld 房子炸塌（Battle.lua）
Config.Battle = {
  -- perSec 一秒最多挖几个、stale 排队超过几秒的不挖（用户 11-19：游戏非常卡顿——挖一个坑全服的客户端都要重算那块地面的网格）
  crater = { k = { shell = 0.36, rkt = 0.32, msl = 0.34, bomb = 0.3 }, minR = 3.2, maxR = 13, depth = 0.34, maxDepth = 5.5, gap = 0.55, max = 240, perSec = 4, stale = 2 },
  illum = { every = { 14, 24 }, alive = 3, height = { 105, 135 }, burn = 32, fall = 2.6, sea = 0.6, first = 6 },
  -- bld 房子炸塌：血量 = 占地面积 × hpPerArea（hpMin～hpMax）；k 按爆炸种类的伤害倍数；血掉到 fire 以下着火
  bld = { hpPerArea = 1.5, hpMin = 700, hpMax = 4000, fire = 0.55, k = { nade = 0.3, shell = 1, rkt = 0.8, msl = 1, bomb = 1.4 } },
  -- storm 暴风雨：开战后 at 秒（随机范围）有 chance 的机会来一场、持续 dur 秒、前后 ramp 秒变大变小
  storm = { chance = 0.85, at = { 150, 420 }, dur = { 150, 230 }, ramp = 25 },
}

-- 高超音速战术核导弹（用户 11-22：「给 h6k 加一个高超音速战术核弹的挂载吧」；Nuke.lua）：
--   cd 一队发射以后多少秒内不能再发、first 开战多少秒后才能发；kill 致死半径、hurt 重伤半径（格，1 米约 2.8 格）、air 天上的飞机挨冲击波的半径、
--   bld 房子全塌、scorch 焦土半径（中心 melt 以内烧成熔岩壳）、crater 弹坑；burst 离地多高空爆；speed 滑翔、dive 俯冲的速度（格 / 秒，6～7 马赫）；
--   fallout 辐射区（半径、每秒伤害、持续秒）
Config.Nuke = { cd = 420, first = 90, kill = 950, hurt = 2000, air = 2600, bld = 1350, scorch = 560, melt = 140, crater = 64, burst = 120,
  speed = 5800, dive = 6800, apo = 7200, drop = 0.8, life = 90,
  fallout = { r = 420, dps = 9, dur = 45 } }

return Config
