-- Roblox全面大战场——数值（服务器、客户端共用）
-- 文字都在 Lang.lua（中英双语），这里只放编号和数
local Config = {}

Config.Version = "1.0-alpha"
Config.SaveKey = "IslandAssault_v1"   -- DataStore 名字（改了就是新存档；游戏改过名（暗剑：登岛战 → Roblox全面大战场 → 全面大战场 / Island Assault）照旧用这个，玩家的军衔、经验不丢）
Config.Tick = 0.1                     -- 推演步长（秒）：占领、AI、炮弹、导弹

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
Config.Stages = {
  { id = "beach", points = { "A" }, time = 7 * 60 },                     -- 第一阶段：抢滩前哨岛
  { id = "main", points = { "C", "D" }, time = 9 * 60, flank = { "B" } }, -- 第二阶段：登陆主岛，港口 + 机场（灯塔岛侧翼）
  { id = "hq", points = { "E" }, time = 8 * 60 },                        -- 第三阶段：指挥部决战
}
-- 攻方兵力（门票）：攻方每阵亡一个（真人、机器人都算）扣 1，扣光了守方赢；打下一个阶段、拿下侧翼据点补兵力；人多的服多给一点
Config.Tickets = { start = 240, perReal = 10, perStage = 100, flank = 50, extraCap = 60 }   -- extraCap：阶段里拿下一个点（还没打完这一阶段）加多少秒
-- 昼夜（客户端 DayNight.lua）：用户 11-18「把白天模式去掉，就锁定晚上」——lockNight 一直停在半夜 clock 点（夜里那套灯光、出生自动开夜视）；
--   lockNight = false 才按 period（一圈多少秒，每局从早上 7:30 开始）昼夜更替
Config.DayNight = { lockNight = true, clock = 2.3, period = 24 * 60 }
Config.RallyBack = 300   -- 守方前线集结点：据点往守方后方（北）多远（格），据点被压着时守方在这里出生
Config.StageOff = 420    -- 攻方攻击出发阵地：第二阶段起，据点往攻方来的方向多远（格），攻方在这里出生、不用走几公里（Round.lua）

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
  def = { color = Color3.fromRGB(60, 120, 230), brick = "Bright blue" },
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
}
Config.RoleById = {}
for _, r in ipairs(Config.Roles) do Config.RoleById[r.id] = r end

-- 装备栏（用户：开局不选兵种，默认就是一个士兵，部署界面底下改枪械配置）：四格各挑一样，服务器按这张表核对；
--   上面的「兵种」只剩老的名字（测试、机器人、战况表的标签）还认
Config.Loadout = {
  { id = "primary", opts = { "m4", "sniper" } },                       -- 主武器
  { id = "secondary", opts = { "tablet" }, none = true },             -- 副武器：战术平板（R 币解锁：Config.Passes.tablet；用户：不要按 B 召唤平板，平板做成物品）
  { id = "launcher", opts = { "rpg", "manpads", "mortar" }, none = true },   -- 发射器（可以不带：跑得快一点）
  { id = "gadget", opts = { "medkit", "repair", "breach", "binoc" } },  -- 装备
  { id = "throw", opts = { "grenade", "c4" } },                        -- 投掷
}
Config.LoadoutDefault = { primary = "m4", gadget = "medkit", throw = "grenade" }

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
    scope = 3.5, optic = "acog" },   -- 两队都用这一种（第一人称动作照 M4 动作包）；上机匣导轨上一具 ACOG 3.5 倍镜（用户：武器瞄准没有镜子）
  -- 狙击枪：开镜 0.03°（原来不分开不开镜都是这么准），腰射 2.6°（不开镜别指望一枪一个）
  sniper = { kind = "gun", dmg = 96, rate = 1.35, mag = 5, reload = 3.0, range = 1500, spread = 2.6, adsK = 0.0115, moveK = 1.5,
    vs = { inf = 1, light = 0.25, armor = 0, air = 0.1, ship = 0, fort = 0.05 }, head = 2.2, scope = 5 },
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
    tank = { "ztq15", "ztz96", "ztz99a" },
    apc = { "ztd05", "zbd05", "zsl92b", "ptl02" },
    aa = { "pgz07", "pgl625", "ld2000" },
    arty = { "plz07" },
    heli = { "z10", "z20" },
    jet = { "j15t", "j35", "j20", "j16", "j50", "h6k", "gj11", "gj2" },
    ship = { "t055", "t054a", "t022" },
  },
  def = {
    tank = { "m10", "m1a1", "m1a2" },
    apc = { "m1117", "hmmwv", "jltv", "m2a3", "stryker", "m1150" },
    aa = { "m163", "mshorad", "cram", "patriot" },
    arty = { "m109a7", "m270" },   -- M777 是地图自带的炮位（Forts），走过去就能用
    heli = { "ah64e", "uh60", "ch47" },
    jet = { "a10c", "f35", "f22", "mq9", "b2" },
    ship = { "ddg125", "cg47", "lcs2", "pbr" },
  },
}
Config.VehicleMod = {
  ztq15 = { hp = 0.75, speed = 1.15, gun = 0.8 }, m10 = { hp = 0.8, speed = 1.1, gun = 0.85 },
  ztz96 = { hp = 0.9 }, m1a1 = { hp = 0.95 }, ztz99a = { hp = 1.1, gun = 1.1 }, m1a2 = { hp = 1.1, gun = 1.1 },
  zbd05 = { amphib = true }, ztd05 = { amphib = true, gun = 1.6 }, hmmwv = { hp = 0.5, speed = 1.25 }, jltv = { hp = 0.65, speed = 1.2 },
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
  fortKill = 250, defuse = 30, wireCut = 15 }
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
  crater = { k = { shell = 0.36, rkt = 0.32, msl = 0.34, bomb = 0.3 }, minR = 3.2, maxR = 13, depth = 0.34, maxDepth = 5.5, gap = 0.55, max = 240, perSec = 8 },
  illum = { every = { 14, 24 }, alive = 3, height = { 105, 135 }, burn = 32, fall = 2.6, sea = 0.6, first = 6 },
  -- bld 房子炸塌：血量 = 占地面积 × hpPerArea（hpMin～hpMax）；k 按爆炸种类的伤害倍数；血掉到 fire 以下着火
  bld = { hpPerArea = 1.5, hpMin = 700, hpMax = 4000, fire = 0.55, k = { nade = 0.3, shell = 1, rkt = 0.8, msl = 1, bomb = 1.4 } },
  -- storm 暴风雨：开战后 at 秒（随机范围）有 chance 的机会来一场、持续 dur 秒、前后 ramp 秒变大变小
  storm = { chance = 0.85, at = { 150, 420 }, dur = { 150, 230 }, ramp = 25 },
}

return Config
