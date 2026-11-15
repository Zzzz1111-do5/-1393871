-- Roblox全面大战场——数值（服务器、客户端共用）
-- 文字都在 Lang.lua（中英双语），这里只放编号和数
local Config = {}

Config.Version = "1.0-alpha"
Config.SaveKey = "IslandAssault_v1"   -- DataStore 名字（改了就是新存档；游戏改名成「Roblox全面大战场」后照旧用这个，玩家的军衔、经验不丢）
Config.Tick = 0.1                     -- 推演步长（秒）：占领、AI、炮弹、导弹

---------------------------------------------------------------- 回合

-- 准备 → 战斗（攻方每拿下一个据点加时间）→ 结算 → 重新随机分队
Config.Round = {
  prep = 30,            -- 准备（选兵种、等人）
  battle = 20 * 60,     -- 战斗时长
  perCapture = 180,     -- 攻方每拿下一个据点加多少秒
  overtime = 90,        -- 时间到时有据点正在被占：最多加时多久
  results = 20,         -- 结算画面
}
Config.RespawnDelay = 6   -- 阵亡后几秒回到部署界面
Config.MinPlayersToStart = 1

-- 占领：圈里数双方的人（步兵、地面载具；飞机、舰艇不算；机器人也算）
Config.Capture = {
  r = 70,          -- 据点半径（和 Map.POINT_R 一样）
  slow = 45,       -- 攻方多 1 人：几秒占完
  fast = 15,       -- 攻方多 3 人以上：几秒占完
  decay = 90,      -- 守方人不少于攻方：进度从满退到零要几秒
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

---------------------------------------------------------------- 武器

-- 目标类别：inf 步兵、light 轻型车、armor 装甲、air 飞机直升机、ship 舰艇、fort 工事
-- kind：gun 直射（服务器射线判定）；proj 有弹道的弹（speed 弹速、splash 溅射、drop 是否下坠）；throw 投掷（fuse 引信秒数）；
--   lock 锁定导弹（打 air，lockTime 锁定要几秒）；mortar 曲射（点地图上 / 准星下的地面，minR maxR 射程）；
--   heal 治疗（r 范围、amt 每次、cd 冷却）；repair 修车、修工事（每秒 rate）；place 放置（炸药包）；breach 破障器材；spot 望远镜标记敌人、呼叫炮击
--   （雷区、铁丝网、炮都是地图自带的，玩家不能自己布雷、架炮）
-- dmg 每发、rate 几秒一发、mag 弹匣、reserve 备弹（不算弹匣里的；没写就是无限）、reload 换弹秒数、range 射程、spread 散布（度）；
-- vs 对各类目标的伤害倍数
local G_VS = { inf = 1, light = 0.15, armor = 0, air = 0.1, ship = 0, fort = 0.04 }
Config.Weapons = {
  m4 = { kind = "gun", dmg = 25, rate = 0.08, mag = 30, reload = 2.6, range = 650, spread = 0.55, auto = true, vs = G_VS, head = 1.6 },   -- 两队都用这一种（第一人称动作照 M4 动作包）
  sniper = { kind = "gun", dmg = 96, rate = 1.35, mag = 5, reload = 3.0, range = 1500, spread = 0.03, vs = { inf = 1, light = 0.25, armor = 0, air = 0.1, ship = 0, fort = 0.05 }, head = 2.2, scope = 5 },
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
-- 这一队这一类最多同时在场几辆（按队伍人数，真人 + 机器人）
function Config.VehicleCap(cat, teamN)
  local c = Config.VehicleCats[cat]
  return math.clamp(math.floor(teamN / c.perN) + c.min, c.min, c.max)
end

---------------------------------------------------------------- 机器人

Config.Bots = {
  minPerTeam = 18,       -- 每队保底人数：真人不够用 AI 补
  maxTotal = 40,         -- 全服最多几个机器人
  hp = 100, speed = 14,  -- 步兵机器人：血量、走路速度（格 / 秒）
  weapon = "m4",         -- 用哪种枪的伤害、射程
  sight = 520,           -- 看多远
  reaction = 0.8,        -- 发现新目标后多久开第一枪（秒，随机 ±40%）
  fireGap = 0.36,        -- 两枪之间（秒）
  spread = 0.8, spreadPer = 0.004,   -- 散布：基础几度 + 每格距离多几度（100 格约 1.2°、300 格约 2°）
}

---------------------------------------------------------------- 得分、经验、军衔

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

return Config
