-- Roblox全面大战场——飞机、直升机的型号数据（服务器、客户端共用）：尺寸、飞行性能、航炮、挂点与可选挂载、预设方案、外形
--   单位：格（1 米约 2.8 格，和地面载具一样）。机体坐标：原点在机身中心（命中盒中心），X 右、Y 上、−Z 朝前（机头）
--   gearH：放下起落架停在地上时，原点离地多高；直升机是起落架 / 机轮着地时的高度
--   速度（格 / 秒）：stall 失速、vMil 不开加力的最大平飞速度、vAB 开加力；accel 军用推力的加速度；pitch / roll / yaw 每秒最多转几度；
--     g 最大过载（转弯角速度不超过 g × 重力 / 速度）
--   挂点 st：{ pos 挂点位置, bay 在哪个弹舱里（没有就是外挂）, opts 能挂什么, n 每种挂几枚（多联挂架） }；presets 预设方案（按挂点给武器，false 是空）
--   外形（客户端 AirModels 拼零件用）：机翼 / 鸭翼 / 平尾按梯形给（翼根 x、前缘 z、后缘 z，翼尖 x、前缘 z、后缘 z、高度 y），
--     垂尾按（x、根部前后缘 z、顶部前后缘 z、高、外倾角）；起落架、弹舱门、尾喷口的位置
local AirDefs = {}
local V = Vector3.new

AirDefs.M = 2.8   -- 1 米多少格
AirDefs.GRAV = 27.5   -- 飞行用的重力（格 / 秒²，9.8 米 / 秒²）
-- 抛射（用户 11-25「部分直升机我记得发射导弹是抛射」「或许不止直升机」）：发射后先不点火，t 秒以后发动机才着、开始制导
--   tube 筒射：抛射药把弹往前推出发射筒（毒刺约 28 米 / 秒，离开 8 米左右主发动机才点火，免得烧着射手 / 飞机）；
--   drop 弹射下落：弹舱、机身半埋挂点的弹射挂架（F-22 的 LAU-142、F-15 机身的 LAU-106、F-14 的 LAU-93、苏-27 进气道下的 AKU-470）
--   把弹往下推开约 7.6 米 / 秒，掉出气流再点火；cruise 涡喷巡航弹（鹰击-83K、KD-88）从挂架上投下，发动机起动要一会儿
--   f 往前推的速度、d 往下推的速度（格 / 秒，1 米 = 2.8 格）；挂点也能标 ej = true（那个挂点的弹一律弹射下落）
AirDefs.EJ = {
  tube = { t = 0.3, f = 78, d = 0 },
  drop = { t = 0.45, f = 0, d = 21 },
  cruise = { t = 0.9, f = 0, d = 10 },
}

---------------------------------------------------------------- 机载武器

-- kind：gun 航炮（服务器按射速连发，一步一发弹丸带这一步所有弹的伤害）、aam 空空导弹（seeker ir 红外 / radar 雷达）、
--   agm 空地导弹、bomb 炸弹（guided 激光 / 卫星制导：锁了目标会往目标滑）、rkt 火箭弹（一个发射巢 tubes 发）
--   lockTime 锁定要几秒、cone 导引头能看到偏离机头多少度、turn 导弹每秒最多转几度、burn 发动机烧几秒（之后慢慢减速）
--   vs：对各类目标的倍数（同 Config）
local VS_GUN = { inf = 1, light = 1, armor = 0.18, air = 1.5, ship = 0.3, fort = 0.5 }
local VS_AAM = { inf = 0.3, light = 0.4, armor = 0.1, air = 1, ship = 0.2, fort = 0.1 }
local VS_AGM = { inf = 1, light = 1.3, armor = 1, air = 0.3, ship = 0.8, fort = 1.2 }
local VS_BOMB = { inf = 1, light = 1.2, armor = 0.85, air = 0.2, ship = 1, fort = 1.4 }
local VS_RKT = { inf = 1, light = 1.1, armor = 0.45, air = 0.4, ship = 0.4, fort = 0.8 }
AirDefs.W = {
  gsh30 = { kind = "gun", rate = 0.04, dmg = 30, speed = 2100, range = 1900, splash = 3, vs = VS_GUN, cal = 0.2 },     -- GSh-30-1 30 毫米
  m61 = { kind = "gun", rate = 0.012, dmg = 11, speed = 2100, range = 1800, splash = 2, vs = VS_GUN, cal = 0.16 },     -- M61A2 20 毫米
  gau22 = { kind = "gun", rate = 0.018, dmg = 15, speed = 2100, range = 1800, splash = 2.5, vs = VS_GUN, cal = 0.17 },  -- GAU-22/A 25 毫米
  gsh23 = { kind = "gun", rate = 0.018, dmg = 15, speed = 1900, range = 1700, splash = 2.5, vs = VS_GUN, cal = 0.17 },  -- 23-3 型双管 23 毫米（歼-8II 机腹）
  gsh302 = { kind = "gun", rate = 0.02, dmg = 30, speed = 2000, range = 1900, splash = 3, vs = VS_GUN, cal = 0.2 },   -- GSh-30-2 双管 30 毫米（苏-25：250 发，每分钟约 3000 发）
  nr30 = { kind = "gun", rate = 0.024, dmg = 30, speed = 1900, range = 1700, splash = 3, vs = VS_GUN, cal = 0.2 },     -- 30-1 型（НР-30）30 毫米 ×3（歼-6：两门在翼根、一门在机头右下，合起来每分钟两千五百发）
  gau8 = { kind = "gun", rate = 0.017, dmg = 22, speed = 1900, range = 2000, splash = 3, cal = 0.22,                      -- GAU-8 30 毫米贫铀穿甲弹
    vs = { inf = 1, light = 1.2, armor = 0.55, air = 1.4, ship = 0.5, fort = 0.7 } },
  m230 = { kind = "gun", rate = 0.095, dmg = 42, speed = 1500, range = 1600, splash = 4, cal = 0.2, turret = true,       -- M230 30 毫米链式炮（机头炮塔）
    vs = { inf = 1, light = 1.1, armor = 0.25, air = 1.2, ship = 0.3, fort = 0.6 } },
  zh23 = { kind = "gun", rate = 0.1, dmg = 38, speed = 1500, range = 1500, splash = 3.5, cal = 0.18, turret = true,      -- 直-10 23 毫米炮塔
    vs = { inf = 1, light = 1.1, armor = 0.22, air = 1.2, ship = 0.3, fort = 0.6 } },
  m134 = { kind = "gun", rate = 0.025, dmg = 9, speed = 1700, range = 1100, splash = 0, cal = 0.08, door = true,          -- 舱门机枪
    vs = { inf = 1, light = 0.3, armor = 0.01, air = 0.5, ship = 0.02, fort = 0.05 } },

  -- 霹雳-2（K-13 / AIM-9B 那一代）：只能从后面咬尾、导引头视场窄、过载小，发动机烧两秒多、尾烟浓；歼-6 后期型翼下挂两枚
  pl2 = { kind = "aam", seeker = "ir", dmg = 380, splash = 11, speed = 520, range = 1100, lockTime = 1.5, cone = 20, turn = 30, burn = 2.2, life = 5, vs = VS_AAM,
    shape = { L = 7.9, d = 0.36, fin = 1.0 } },
  pl10 = { kind = "aam", seeker = "ir", dmg = 520, splash = 14, speed = 640, range = 1900, lockTime = 1.0, cone = 45, turn = 75, burn = 3.5, life = 6.5, vs = VS_AAM,
    shape = { L = 8.2, d = 0.45, fin = 1.0 } },
  pl15 = { kind = "aam", seeker = "radar", dmg = 560, splash = 16, speed = 760, range = 3800, lockTime = 2.0, cone = 22, turn = 55, burn = 5, life = 8.5, vs = VS_AAM,
    shape = { L = 11.2, d = 0.58, fin = 1.1 } },
  aim9x = { kind = "aam", seeker = "ir", dmg = 520, splash = 14, speed = 640, range = 1900, lockTime = 1.0, cone = 45, turn = 75, burn = 3.5, life = 6.5, vs = VS_AAM,
    shape = { L = 8.4, d = 0.36, fin = 0.8 } },
  aim120 = { kind = "aam", seeker = "radar", dmg = 560, splash = 16, speed = 760, range = 3800, lockTime = 2.0, cone = 22, turn = 55, burn = 5, life = 8.5, vs = VS_AAM,
    shape = { L = 10.2, d = 0.5, fin = 1.0 } },
  ty90 = { kind = "aam", eject = "tube", seeker = "ir", dmg = 340, splash = 10, speed = 480, range = 1300, lockTime = 0.9, cone = 30, turn = 60, burn = 3, life = 5.5, vs = VS_AAM,
    shape = { L = 5.3, d = 0.25, fin = 0.6 } },
  aim92 = { kind = "aam", eject = "tube", seeker = "ir", dmg = 340, splash = 10, speed = 480, range = 1300, lockTime = 0.9, cone = 30, turn = 60, burn = 3, life = 5.5, vs = VS_AAM,
    shape = { L = 4.5, d = 0.2, fin = 0.5 } },
  -- AIM-54 不死鸟（F-14 专用，用户 11-23 加 F-14）：4 米长、454 公斤的远程雷达弹——射程最远、飞得快，但又重又笨（转得慢、导引头视场窄、锁得慢）
  aim54 = { kind = "aam", eject = { t = 0.6, f = 0, d = 18 }, seeker = "radar", dmg = 620, splash = 18, speed = 820, range = 4600, lockTime = 2.6, cone = 18, turn = 38, burn = 6, life = 10, vs = VS_AAM,
    shape = { L = 11.0, d = 1.06, fin = 1.6 } },

  -- 俄制空空弹（用户 11-26：苏-57、米格-29 要参数跟现实一样；数值按公开资料、和上面各弹同一个比例尺——射程比 AIM-120C（约 105 公里）= 3800）
  --   R-73（AA-11）：红外近距弹，2.9 米、0.17 米、105 公斤，射程约 30 公里，导引头离轴 ±60°（配头盔瞄准具），鸭翼 + 燃气舵、大过载
  r73 = { kind = "aam", seeker = "ir", dmg = 500, splash = 14, speed = 620, range = 1900, lockTime = 0.9, cone = 50, turn = 80, burn = 3, life = 6.5, vs = VS_AAM,
    shape = { L = 8.1, d = 0.48, fin = 0.9 } },
  --   R-74M2：苏-57 侧弹舱用的 R-73 改型（尾翼、舵面展长缩小装得进弹舱），射程约 40 公里，离轴更大
  r74 = { kind = "aam", seeker = "ir", dmg = 500, splash = 14, speed = 640, range = 2100, lockTime = 0.8, cone = 55, turn = 85, burn = 3.2, life = 7, vs = VS_AAM,
    shape = { L = 8.1, d = 0.48, fin = 0.65 } },
  --   R-27R（AA-10A）：半主动雷达弹（靠发射机的雷达一直照着：没有 act，不自己开导引头），4.08 米、0.23 米、253 公斤，迎头射程约 70～80 公里
  r27r = { kind = "aam", seeker = "radar", dmg = 600, splash = 17, speed = 700, range = 2700, lockTime = 1.8, cone = 20, turn = 42, burn = 4.5, life = 8, vs = VS_AAM,
    shape = { L = 11.4, d = 0.64, fin = 1.5 } },
  --   K-77M（180 工程）：苏-57 主弹舱的主动雷达弹，有源相控阵导引头、双脉冲发动机，射程约 150～190 公里；栅格尾翼换成了普通尾翼（装得进弹舱）
  k77m = { kind = "aam", seeker = "radar", dmg = 560, splash = 16, speed = 800, range = 4300, lockTime = 1.8, cone = 24, turn = 56, burn = 5, life = 9.5, vs = VS_AAM,
    shape = { L = 10.4, d = 0.56, fin = 0.8 } },

  --   R-27ER：加大发动机的半主动雷达弹，4.78 米、0.26 米、350 公斤，迎头射程约 130 公里
  r27er = { kind = "aam", seeker = "radar", dmg = 640, splash = 18, speed = 760, range = 3400, lockTime = 2.0, cone = 20, turn = 40, burn = 6, life = 9.5, vs = VS_AAM,
    shape = { L = 13.4, d = 0.73, fin = 1.6 } },
  --   R-77-1（RVV-SD）：主动雷达弹，3.71 米、0.2 米、190 公斤，射程约 110 公里；尾部四片栅格翼
  r77 = { kind = "aam", seeker = "radar", dmg = 540, splash = 15, speed = 760, range = 3500, lockTime = 1.9, cone = 24, turn = 55, burn = 5, life = 9, vs = VS_AAM,
    shape = { L = 10.4, d = 0.56, fin = 1.0 } },
  --   R-60M：老式红外近距弹，2.14 米、0.12 米、44 公斤，射程约 8 公里（苏-25 最外侧挂两枚自卫）
  r60 = { kind = "aam", seeker = "ir", dmg = 380, splash = 11, speed = 560, range = 1100, lockTime = 1.0, cone = 25, turn = 70, burn = 2.5, life = 5, vs = VS_AAM,
    shape = { L = 6.0, d = 0.34, fin = 0.8 } },
  --   Kh-29L：激光半主动空地导弹，3.9 米、0.38 米、657 公斤（战斗部 320 公斤），射程约 10 公里
  kh29 = { kind = "agm", dmg = 1400, splash = 26, speed = 330, range = 2200, lockTime = 1.5, cone = 20, turn = 18, burn = 6, life = 10, vs = VS_AGM,
    shape = { L = 10.9, d = 1.06, fin = 1.6 } },

  -- 铠甲-S1 的 57E6 地空导弹（地面车发射；车上的弹药数在 VehDefs.W.s57e6，服务器 Armor.lua 按这里的速度、转弯飞；客户端照 shape 画）：
  --   弹长 3.2 米、助推器直径 0.17 米，两级、无线电指令制导（kind sam：热诱弹不骗它）
  s57e6 = { kind = "sam", dmg = 520, splash = 18, speed = 900, range = 6000, turn = 50, burn = 5, life = 13, vs = VS_AAM,
    shape = { L = 9.0, d = 0.48, fin = 0.8 } },

  akd10 = { kind = "agm", dmg = 900, splash = 10, speed = 380, range = 2400, lockTime = 1.2, cone = 25, turn = 40, burn = 6, life = 9, vs = VS_AGM,
    shape = { L = 5.0, d = 0.5, fin = 0.7 } },
  agm114 = { kind = "agm", dmg = 900, splash = 10, speed = 380, range = 2400, lockTime = 1.2, cone = 25, turn = 40, burn = 6, life = 9, vs = VS_AGM,
    shape = { L = 4.5, d = 0.5, fin = 0.7 } },
  kd88 = { kind = "agm", eject = "cruise", dmg = 1400, splash = 22, speed = 520, range = 4200, lockTime = 1.6, cone = 18, turn = 25, burn = 9, life = 12, vs = VS_AGM,
    shape = { L = 13, d = 1.0, fin = 1.6, wing = 2.6 } },
  agm65 = { kind = "agm", dmg = 1150, splash = 14, speed = 480, range = 3000, lockTime = 1.4, cone = 20, turn = 30, burn = 6, life = 10, vs = VS_AGM,
    shape = { L = 7.0, d = 0.85, fin = 1.4 } },

  -- 「惊雷-1」高超音速战术核导弹（虚构型号；用户 11-22：「给 h6k 加一个高超音速战术核弹的挂载」；服务器 Nuke.lua）：空射弹道导弹——
  --   投放后自由落体一下、助推器点火往上爬、6 马赫以上滑翔、7 马赫俯冲，离地 burst 格空爆（Config.Nuke）；只打瞄准点（不锁实体，cone = 0）
  --   弹长约 7 米、弹径约 0.9 米：轰-6K 弹舱里半埋挂一枚（照轰-6N 腹部凹槽挂空射弹道导弹的挂法）
  hn1 = { kind = "agm", nuke = true, hyper = true, dmg = 0, splash = 950, speed = 5800, range = 70000, lockTime = 0, cone = 0, turn = 22, burn = 30, life = 90,
    vs = { inf = 1, light = 1, armor = 1, air = 1, ship = 1, fort = 1 }, shape = { L = 19.5, d = 2.5, fin = 1.6 } },
  ls6 = { kind = "bomb", guided = true, dmg = 1500, splash = 32, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 10.8, d = 1.0, fin = 1.0, wing = 3.6 } },
  gbu12 = { kind = "bomb", guided = true, dmg = 1300, splash = 30, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 9.2, d = 0.9, fin = 1.2 } },
  gbu31 = { kind = "bomb", guided = true, dmg = 2600, splash = 48, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 10.6, d = 1.4, fin = 1.6 } },
  mk82 = { kind = "bomb", dmg = 1100, splash = 30, vs = VS_BOMB, shape = { L = 6.4, d = 0.75, fin = 1.0 } },
  b250 = { kind = "bomb", dmg = 1150, splash = 30, vs = VS_BOMB, shape = { L = 5.6, d = 0.95, fin = 1.0 } },

  hydra = { kind = "rkt", dmg = 230, splash = 12, speed = 760, range = 1800, rate = 0.11, tubes = 19, vs = VS_RKT, shape = { L = 4.6, d = 1.1 } },

  -- 副油箱（用户：可以选择挂载副油箱）：fuel 一个能加内油的几成，drag 挂着时最大速度、加速度少几成；油用完自动抛掉，J 键手动抛
  tk800 = { kind = "tank", fuel = 0.3, drag = 0.03, shape = { L = 12.6, d = 1.75 } },    -- 解放军 800 升（歼-10 / 歼-20 那种）
  tk370 = { kind = "tank", fuel = 0.32, drag = 0.03, shape = { L = 13.4, d = 1.9 } },    -- 美军 370 加仑（约 1400 升）
  tkh = { kind = "tank", fuel = 0.35, drag = 0.02, shape = { L = 9.5, d = 1.7 } },       -- 直升机外挂油箱（解放军）
  tk230 = { kind = "tank", fuel = 0.35, drag = 0.02, shape = { L = 10.0, d = 1.75 } },   -- 直升机 230 加仑外挂油箱（美军）

  pl12 = { kind = "aam", seeker = "radar", dmg = 540, splash = 15, speed = 720, range = 2800, lockTime = 1.6, cone = 25, turn = 50, burn = 4.5, life = 7.5, vs = VS_AAM,
    shape = { L = 10.4, d = 0.57, fin = 1.0 } },
  yj91 = { kind = "agm", eject = "drop", arm = true, dmg = 1000, splash = 14, speed = 560, range = 3800, lockTime = 1.4, cone = 25, turn = 30, burn = 8, life = 11,
    vs = { inf = 0.6, light = 1.8, armor = 0.8, air = 0.2, ship = 1.1, fort = 1.6 }, shape = { L = 13.2, d = 1.0, fin = 1.6 } },
  -- 鹰击-83K 空射反舰导弹（歼-15T 的原模型就挂着它，用户给的「J-15T with YJ-83K」）：长约 5.1 米、弹径 0.36 米、翼展约 1.2 米；
  --   涡喷发动机亚音速掠海飞行，比 KD-88 慢、射程远，打船狠（对船 3.2 倍）
  yj83k = { kind = "agm", eject = "cruise", dmg = 1600, splash = 20, speed = 440, range = 5000, lockTime = 1.6, cone = 18, turn = 22, burn = 14, life = 15,
    vs = { inf = 0.6, light = 1.2, armor = 0.8, air = 0.1, ship = 3.2, fort = 1.0 }, shape = { L = 14.3, d = 1.0, fin = 1.4, wing = 3.4 } },
  agm88 = { kind = "agm", arm = true, dmg = 950, splash = 13, speed = 580, range = 3600, lockTime = 1.4, cone = 25, turn = 30, burn = 8, life = 11,
    vs = { inf = 0.6, light = 1.8, armor = 0.8, air = 0.2, ship = 1.1, fort = 1.6 }, shape = { L = 11.6, d = 0.71, fin = 1.3 } },
  gbu32 = { kind = "bomb", guided = true, dmg = 1700, splash = 36, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 8.5, d = 1.0, fin = 1.3 } },
  gbu38 = { kind = "bomb", guided = true, dmg = 1100, splash = 28, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 6.6, d = 0.76, fin = 1.0 } },
  gbu39 = { kind = "bomb", guided = true, dmg = 700, splash = 18, lockTime = 0.8, cone = 70, vs = VS_BOMB, shape = { L = 5.0, d = 0.53, fin = 0.6, wing = 4.0 } },
  lt2 = { kind = "bomb", guided = true, dmg = 1350, splash = 30, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 11, d = 1.04, fin = 1.2 } },
  fl90 = { kind = "rkt", dmg = 260, splash = 13, speed = 720, range = 1800, rate = 0.13, tubes = 12, vs = VS_RKT, shape = { L = 5.0, d = 1.2 } },
  -- 各国直升机的武器（用户 11-25「直升机也做一下各个国家的」）：底子照相近的那种（反坦克导弹照 AGM-114、火箭照 Hydra / 飞龙-90、
  --   防空弹照毒刺、炮照 M230 / 直-10 的炮塔），速度、射程、威力按真弹之间的比例调（下面统一按真实尺度放大）
  a42 = { kind = "gun", rate = 0.11, dmg = 46, speed = 1600, range = 1800, splash = 4, cal = 0.2, turret = true,     -- 2A42 30 毫米（米-28N 机头炮塔、卡-52 右舷）
    vs = { inf = 1, light = 1.15, armor = 0.3, air = 1.2, ship = 0.3, fort = 0.6 } },
  yakb = { kind = "gun", rate = 0.03, dmg = 14, speed = 1600, range = 1300, splash = 1, cal = 0.12, turret = true,    -- 米-24V 机头 YakB-12.7 四管机枪
    vs = { inf = 1, light = 0.6, armor = 0.03, air = 0.9, ship = 0.05, fort = 0.15 } },
  m197 = { kind = "gun", rate = 0.06, dmg = 30, speed = 1500, range = 1500, splash = 2.5, cal = 0.16, turret = true,  -- AH-1 M197 20 毫米三管炮塔
    vs = { inf = 1, light = 1.05, armor = 0.18, air = 1.2, ship = 0.25, fort = 0.5 } },
  ataka = { kind = "agm", eject = "tube", dmg = 950, splash = 10, speed = 430, range = 2200, lockTime = 1.4, cone = 25, turn = 35, burn = 6, life = 9, vs = VS_AGM,   -- 9M120 攻击（米-28N）：无线电指令
    shape = { L = 6.1, d = 0.45, fin = 0.7 } },
  shturm = { kind = "agm", eject = "tube", dmg = 800, splash = 9, speed = 350, range = 2000, lockTime = 1.4, cone = 22, turn = 30, burn = 5, life = 9, vs = VS_AGM,   -- 9M114 突击（米-24V）
    shape = { L = 6.0, d = 0.45, fin = 0.7 } },
  vikhr = { kind = "agm", dmg = 950, splash = 10, speed = 520, range = 2800, lockTime = 1.4, cone = 25, turn = 35, burn = 6, life = 9, vs = VS_AGM,   -- 9K121 旋风（卡-52）：激光驾束、超音速
    shape = { L = 8.0, d = 0.4, fin = 0.7 } },
  hot3 = { kind = "agm", dmg = 850, splash = 9, speed = 280, range = 1900, lockTime = 1.3, cone = 25, turn = 35, burn = 5, life = 10, vs = VS_AGM,    -- HOT 3（虎式 UHT）：有线指令
    shape = { L = 3.6, d = 0.5, fin = 0.8 } },
  tow = { kind = "agm", eject = { t = 0.18, f = 188, d = 0 }, dmg = 800, splash = 9, speed = 290, range = 1700, lockTime = 1.3, cone = 22, turn = 30, burn = 5, life = 9, vs = VS_AGM,      -- BGM-71 陶式（AH-1S）：有线指令
    shape = { L = 3.3, d = 0.45, fin = 0.8 } },
  s8 = { kind = "rkt", dmg = 250, splash = 13, speed = 700, range = 1700, rate = 0.1, tubes = 20, vs = VS_RKT, shape = { L = 4.4, d = 1.2 } },        -- S-8 80 毫米（B-8V20 火箭巢）
  igla = { kind = "aam", eject = "tube", seeker = "ir", dmg = 320, splash = 10, speed = 470, range = 1200, lockTime = 1.0, cone = 28, turn = 55, burn = 3, life = 5.5, vs = VS_AAM,   -- 9K38 针-V
    shape = { L = 4.4, d = 0.2, fin = 0.5 } },
  type91 = { kind = "aam", eject = "tube", seeker = "ir", dmg = 320, splash = 10, speed = 470, range = 1200, lockTime = 1.0, cone = 28, turn = 55, burn = 3, life = 5.5, vs = VS_AAM, -- 91 式便携防空导弹（OH-1）
    shape = { L = 4.0, d = 0.2, fin = 0.5 } },
}
-- 导引方式：ir 红外、radar 主动雷达、laser 激光、gps 卫星 / 惯性、tv 电视 / 红外成像、arm 被动雷达（反辐射）、none 无制导
local GUIDE = { igla = "ir", type91 = "ir", ataka = "cmd", shturm = "cmd", hot3 = "cmd", tow = "cmd", vikhr = "laser",
  r73 = "ir", r74 = "ir", r27r = "radar", k77m = "radar", r27er = "radar", r77 = "radar", r60 = "ir", kh29 = "laser",
  pl10 = "ir", aim9x = "ir", ty90 = "ir", aim92 = "ir", pl15 = "radar", pl12 = "radar", aim120 = "radar", aim54 = "radar", akd10 = "laser", agm114 = "laser",
  kd88 = "tv", agm65 = "tv", yj83k = "radar", yj91 = "arm", agm88 = "arm", ls6 = "gps", gbu31 = "gps", gbu32 = "gps", gbu38 = "gps", gbu39 = "gps", gbu12 = "laser", lt2 = "laser" }
for id, w in pairs(AirDefs.W) do
  w.id = id
  w.guide = GUIDE[id] or ((w.kind == "gun") and "gun" or "none")
  -- 用户：飞机的雷达、视野都有点近——导弹射程拉远（雷达制导空空弹 2.6 倍、红外弹 1.8 倍、空地弹 1.7 倍），
  --   烧得久一点、飞得久一点才够得着（雷达弹约 3.5 公里、红外弹约 1.2 公里、KD-88 约 2.5 公里）
  if w.kind == "aam" or w.kind == "agm" then
    local k = (w.kind == "aam") and ((w.seeker == "radar") and 2.6 or 1.8) or 1.7
    w.range = math.floor(w.range * k)
    w.life = (w.life or 8) * (0.45 + 0.55 * k)
    w.burn = (w.burn or 3) * (0.6 + 0.4 * k)
  end
end
-- 各型导弹的发动机、尾烟、能量（用户 11-24 夜：「不同导弹尾烟 动能 速度都是不一样的」）——服务器 Air.lua 按它飞、客户端 Fx.lua 按它画尾烟：
--   burn 发动机烧几秒（烧完不冒烟、不发光，靠惯性滑翔）；pulse 双脉冲（{ at = 第几秒点第二次, t = 烧几秒 }：霹雳-15）；
--   cruise 涡喷一直开（巡航弹，匀速飞），boost 它起飞那一下助推几秒（浓烟）；speed 最快（格 / 秒，不写照上面）；
--   g 满速时最大过载（慢了按速度² 少：后段的弹转不动）；bleed 烧完以后掉速快慢（满速时每秒掉几成，越大的弹越小）；
--   smoke 尾烟：low 低烟发动机（细、淡）/ med / heavy（老式发动机、助推器：又粗又浓）
local MOTOR = {
  pl2 = { burn = 2.2, g = 11, bleed = 0.24, smoke = "heavy" },
  pl10 = { burn = 3.0, g = 55, bleed = 0.17, smoke = "low" },
  aim9x = { burn = 3.4, g = 55, bleed = 0.16, smoke = "low" },
  ty90 = { burn = 2.2, g = 25, bleed = 0.22, smoke = "med" },
  aim92 = { burn = 2.4, g = 25, bleed = 0.2, smoke = "low" },
  pl12 = { burn = 5.5, g = 32, bleed = 0.11, smoke = "med" },
  aim120 = { burn = 6.5, g = 32, bleed = 0.095, smoke = "low" },
  pl15 = { burn = 5.0, pulse = { at = 9, t = 4.5 }, speed = 820, g = 30, bleed = 0.08, smoke = "low" },
  aim54 = { burn = 9, g = 18, bleed = 0.07, smoke = "heavy" },
  r73 = { burn = 3.0, g = 50, bleed = 0.17, smoke = "med" },
  r74 = { burn = 3.2, g = 55, bleed = 0.16, smoke = "low" },
  r27r = { burn = 6, g = 25, bleed = 0.1, smoke = "med" },
  k77m = { burn = 5.5, pulse = { at = 10, t = 4 }, speed = 840, g = 32, bleed = 0.08, smoke = "low" },   -- 双脉冲（同霹雳-15）
  r27er = { burn = 7, g = 25, bleed = 0.09, smoke = "med" },
  r77 = { burn = 6, g = 32, bleed = 0.1, smoke = "low" },
  r60 = { burn = 2.4, g = 40, bleed = 0.2, smoke = "med" },
  kh29 = { burn = 6, g = 10, bleed = 0.05, smoke = "heavy" },
  s57e6 = { burn = 2.0, speed = 1100, g = 32, bleed = 0.045, smoke = "heavy" },   -- 两级：助推器烧完扔掉，弹体（没有发动机）高速滑翔、阻力小
  akd10 = { burn = 3.5, g = 15, bleed = 0.06, smoke = "med" },
  agm114 = { burn = 3.0, g = 15, bleed = 0.07, smoke = "med" },
  ataka = { burn = 3.5, g = 14, bleed = 0.06, smoke = "med" },
  shturm = { burn = 3.0, g = 12, bleed = 0.07, smoke = "med" },
  vikhr = { burn = 3.5, g = 16, bleed = 0.05, smoke = "med" },
  hot3 = { burn = 2.5, g = 12, bleed = 0.08, smoke = "heavy" },
  tow = { burn = 2.0, g = 12, bleed = 0.08, smoke = "heavy" },
  igla = { burn = 2.2, g = 22, bleed = 0.22, smoke = "med" },
  type91 = { burn = 2.2, g = 24, bleed = 0.21, smoke = "low" },
  agm65 = { burn = 4.5, g = 12, bleed = 0.06, smoke = "med" },
  kd88 = { cruise = true, boost = 1.5, g = 6, smoke = "low" },
  yj83k = { cruise = true, boost = 2.0, g = 6, smoke = "low" },
  yj91 = { burn = 8, g = 12, bleed = 0.05, smoke = "med" },
  agm88 = { burn = 7, g = 15, bleed = 0.05, smoke = "med" },
}
for wid, m in pairs(MOTOR) do
  local w = AirDefs.W[wid]
  if w then
    for k, v in pairs(m) do w[k] = v end
  end
end
-- 这一刻发动机开着没（尾焰、尾烟、加速都按它）：助推 / 主发动机、双脉冲的第二次、巡航弹一直开
function AirDefs.motorOn(w, t)
  if not w then return false end
  if w.cruise then return true end
  if t < (w.burn or 3) then return true end
  local p = w.pulse
  return p ~= nil and t >= p.at and t < p.at + p.t
end
-- 尾烟浓不浓（low / med / heavy）：巡航弹起飞那一下是助推器的浓烟
function AirDefs.smokeOf(w, t)
  if not w then return "med" end
  if w.cruise and t < (w.boost or 0) then return "heavy" end
  return w.smoke or "med"
end

-- 每个挂点每种武器挂几枚（多联挂架）：没写就是 1；火箭巢是一个巢（弹数在 tubes）
local function N(t) return t end

---------------------------------------------------------------- 型号

local D = {}
AirDefs.D = D
local function mirror(list)   -- 右边的挂点照着复制一份左边的（x 取反），右边在前、左边在后，挂弹时左右交替
  local out = {}
  for _, s in ipairs(list) do
    table.insert(out, s)
    if s.pos.X ~= 0 then
      local m = table.clone(s)
      m.pos = V(-s.pos.X, s.pos.Y, s.pos.Z)
      if s.bay == "sideR" then m.bay = "sideL" end
      m.mate = #out
      table.insert(out, m)
    end
  end
  return out
end

-- 预设：按挂点名字（stName）给武器；没提到的挂点空着
local function preset(key, map) return { key = key, map = map } end

---------------------------------------------------------------- 直升机

-- rotor：主旋翼（hub 桨毂位置、r 半径、blades 片数、rpm 每分钟转数、dir 1 逆时针（俯视）/ −1 顺时针），tail 尾桨（同上，axis "x" 横着装）
-- 直升机速度：vMax 最大平飞、climb 爬升 / 下降、yaw 偏航（度 / 秒）、tilt 最大俯仰 / 滚转（度）
D.z10 = { kind = "heli", cat = "heli", L = 40, W = 6.6, H = 11.2, gearH = 4.6, hp = 900, vMax = 95, climb = 34, yaw = 75, tilt = 26, accel = 30,
  seats = 2, flares = 30, gun = "zh23", gunAmmo = 300, gunPos = V(0, -3.1, -13),
  rotor = { hub = V(0, 5.6, -1), r = 18.2, blades = 5, rpm = 290, dir = 1, chord = 1.4 }, tail = { hub = V(-1.3, 3.6, 19.5), r = 3.1, blades = 4, rpm = 1400, axis = "x" },
  style = "attackheli", tandem = true, tw = 4.2, boom = 15,
  stub = { x = 3.2, span = 4.2, y = -0.8, z = 0.5 },
  st = mirror({
    { name = "outer", pos = V(5.4, -2.1, 0.6), opts = { "akd10", "fl90", "ty90" }, n = N({ akd10 = 4, ty90 = 2 }) },
    { name = "inner", pos = V(3.4, -2.1, 0.6), opts = { "akd10", "fl90" }, n = N({ akd10 = 4 }) },
  }),
  presets = { preset("at", { outer = "akd10", inner = "akd10" }), preset("mix", { outer = "akd10", inner = "fl90" }), preset("rkt", { outer = "fl90", inner = "fl90" }),
    preset("aa", { outer = "ty90", inner = "akd10" }) } }
D.ah64e = { kind = "heli", cat = "heli", L = 44, W = 7.4, H = 12.2, gearH = 4.4, hp = 1000, vMax = 92, climb = 32, yaw = 70, tilt = 26, accel = 28,
  seats = 2, flares = 30, gun = "m230", gunAmmo = 600, gunPos = V(0, -3.3, -10.5),
  rotor = { hub = V(0, 6.0, -0.5), r = 20.4, blades = 4, rpm = 289, dir = -1, chord = 1.5 }, tail = { hub = V(-1.4, 4.4, 21.6), r = 3.9, blades = 4, rpm = 1400, axis = "x", scissor = true },
  style = "attackheli", tandem = true, tw = 4.8, boom = 16, tads = true, longbow = true,
  stub = { x = 3.6, span = 4.6, y = -0.6, z = 0.2 },
  st = mirror({
    { name = "outer", pos = V(6.2, -2.0, 0.4), opts = { "agm114", "hydra" }, n = N({ agm114 = 4 }) },
    { name = "inner", pos = V(3.9, -2.0, 0.4), opts = { "agm114", "hydra" }, n = N({ agm114 = 4 }) },
    { name = "tip", pos = V(8.3, -0.5, 0.3), opts = { "aim92" }, n = N({ aim92 = 2 }) },
  }),
  presets = { preset("at", { outer = "agm114", inner = "agm114", tip = "aim92" }), preset("mix", { outer = "agm114", inner = "hydra", tip = "aim92" }),
    preset("rkt", { outer = "hydra", inner = "hydra" }) } }
D.z20 = { kind = "heli", cat = "heli", L = 44, W = 7.8, H = 14.2, gearH = 4.6, hp = 950, vMax = 88, climb = 30, yaw = 60, tilt = 22, accel = 24,
  seats = 4, transport = true, flares = 30, gun = "m134", gunAmmo = 1500, door = { x = 3.9, y = 0.8, z = -4.5 },
  rotor = { hub = V(0, 7.4, -1.2), r = 23, blades = 5, rpm = 258, dir = 1, chord = 1.6 }, tail = { hub = V(-1.6, 5.8, 23.5), r = 4.7, blades = 4, rpm = 1190, axis = "x", cant = 20 },
  style = "utility", cabin = { w = 7.4, h = 6.4, len = 18 }, sideDoor = true,
  stub = { x = 4.4, span = 4.8, y = 0.6, z = 0.4 },
  st = mirror({ { name = "stub", pos = V(7.0, -0.4, 0.5), opts = { "fl90" } } }),
  presets = { preset("none", {}), preset("rkt", { stub = "fl90" }) } }
D.uh60 = { kind = "heli", cat = "heli", L = 44, W = 7.4, H = 14.2, gearH = 4.6, hp = 900, vMax = 88, climb = 30, yaw = 60, tilt = 22, accel = 24,
  seats = 4, transport = true, flares = 30, gun = "m134", gunAmmo = 1500, door = { x = 3.7, y = 0.8, z = -4.8 },
  rotor = { hub = V(0, 7.2, -1.0), r = 23, blades = 4, rpm = 258, dir = -1, chord = 1.6 }, tail = { hub = V(-1.5, 5.6, 23.3), r = 4.6, blades = 4, rpm = 1190, axis = "x", cant = 20 },
  style = "utility", cabin = { w = 7.0, h = 6.2, len = 17 }, sideDoor = true,
  stub = { x = 4.2, span = 4.8, y = 0.6, z = 0.4 },
  st = mirror({ { name = "stub", pos = V(6.8, -0.4, 0.5), opts = { "hydra", "agm114" }, n = N({ agm114 = 4 }) } }),
  presets = { preset("none", {}), preset("rkt", { stub = "hydra" }), preset("dap", { stub = "agm114" }) } }
D.ch47 = { kind = "heli", cat = "heli", L = 44, W = 10.6, H = 16, gearH = 4.8, hp = 1300, vMax = 90, climb = 26, yaw = 45, tilt = 18, accel = 20,
  seats = 4, transport = true, flares = 40, gun = "m134", gunAmmo = 1500, door = { x = 5.2, y = 1.2, z = -10 },
  rotor = { hub = V(0, 9.2, -15.5), r = 25.6, blades = 3, rpm = 225, dir = -1, chord = 1.9 }, rotor2 = { hub = V(0, 13.4, 16.5), r = 25.6, blades = 3, rpm = 225, dir = 1, chord = 1.9 },
  style = "chinook", cabin = { w = 10.6, h = 9.6, len = 44 }, ramp = true,
  st = {}, presets = { preset("none", {}) } }

-- 各国直升机（用户 11-25「直升机也做一下各个国家的」，科技树第三棵树 heli）：机身长、旋翼直径、桨叶数、转速照真机（格 = 米 × 2.8），
--   最大平飞照真机（这里按公里 / 时 ÷ 3.1 写，下面统一 ×2.4）；dir 1 俯视逆时针（美式）、−1 顺时针（苏俄、法式）
local function hv(base, over)   -- 同族的变型：照抄一份再改几项
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(over) do t[k] = v end
  return t
end
D.mi24 = { kind = "heli", cat = "heli", L = 49, W = 18, H = 16, gearH = 5.0, hp = 1300, vMax = 108, climb = 26, yaw = 50, tilt = 22, accel = 24,   -- 米-24V：重装甲，带一个能坐 8 人的货舱
  seats = 2, flares = 40, gun = "yakb", gunAmmo = 1470, gunPos = V(0, -3.6, -19),
  rotor = { hub = V(0, 7.0, -1.5), r = 24.2, blades = 5, rpm = 240, dir = -1, chord = 1.6 }, tail = { hub = V(1.6, 5.6, 25), r = 5.4, blades = 3, rpm = 1100, axis = "x" },
  style = "attackheli", tandem = true, tw = 5.0, boom = 18,
  stub = { x = 4.0, span = 6.0, y = -0.8, z = 0.5 },
  st = mirror({
    { name = "tip", pos = V(9.6, -1.4, 0.5), opts = { "shturm", "ataka" }, n = N({ shturm = 2, ataka = 2 }) },
    { name = "outer", pos = V(7.4, -2.2, 0.5), opts = { "s8", "shturm" }, n = N({ shturm = 2 }) },
    { name = "inner", pos = V(5.2, -2.2, 0.5), opts = { "s8" } },
  }),
  presets = { preset("at", { tip = "shturm", outer = "shturm", inner = "s8" }), preset("rkt", { tip = "shturm", outer = "s8", inner = "s8" }) } }
D.mi28 = { kind = "heli", cat = "heli", L = 47, W = 13.5, H = 13.5, gearH = 4.6, hp = 1250, vMax = 97, climb = 30, yaw = 60, tilt = 24, accel = 26,   -- 米-28N 浩劫：机头 2A42 炮塔
  seats = 2, flares = 40, gun = "a42", gunAmmo = 250, gunPos = V(0, -3.4, -16),
  rotor = { hub = V(0, 6.6, -1.0), r = 24.1, blades = 5, rpm = 242, dir = -1, chord = 1.6 }, tail = { hub = V(1.4, 4.8, 23), r = 5.4, blades = 4, rpm = 1100, axis = "x", scissor = true },
  style = "attackheli", tandem = true, tw = 4.6, boom = 17,
  stub = { x = 3.6, span = 5.0, y = -0.6, z = 0.3 },
  st = mirror({
    { name = "outer", pos = V(7.6, -2.0, 0.4), opts = { "ataka", "igla", "s8" }, n = N({ ataka = 8, igla = 2 }) },
    { name = "inner", pos = V(5.0, -2.0, 0.4), opts = { "s8", "ataka" }, n = N({ ataka = 8 }) },
  }),
  presets = { preset("at", { outer = "ataka", inner = "s8" }), preset("aa", { outer = "igla", inner = "s8" }), preset("rkt", { outer = "s8", inner = "s8" }) } }
D.ka52 = { kind = "heli", cat = "heli", L = 38, W = 20.6, H = 13.8, gearH = 4.4, hp = 1150, vMax = 97, climb = 32, yaw = 85, tilt = 26, accel = 28,   -- 卡-52 短吻鳄：共轴双旋翼、没有尾桨，并列双座
  seats = 2, flares = 40, gun = "a42", gunAmmo = 460, gunPos = V(1.4, -1.6, -6),
  rotor = { hub = V(0, 6.0, -0.5), r = 20.3, blades = 3, rpm = 270, dir = 1, chord = 1.4 }, rotor2 = { hub = V(0, 8.6, -0.5), r = 20.3, blades = 3, rpm = 270, dir = -1, chord = 1.4 },
  style = "attackheli", tandem = false, tw = 5.2, boom = 14,
  stub = { x = 3.4, span = 6.0, y = -0.4, z = 0.2 },
  st = mirror({
    { name = "outer", pos = V(8.8, -1.4, 0.3), opts = { "vikhr", "igla" }, n = N({ vikhr = 6, igla = 2 }) },
    { name = "inner", pos = V(5.6, -1.8, 0.3), opts = { "s8", "vikhr" }, n = N({ vikhr = 6 }) },
  }),
  presets = { preset("at", { outer = "vikhr", inner = "s8" }), preset("aa", { outer = "igla", inner = "vikhr" }), preset("rkt", { outer = "vikhr", inner = "s8" }) } }
D.tiger = { kind = "heli", cat = "heli", L = 39, W = 12.0, H = 11.8, gearH = 4.2, hp = 950, vMax = 94, climb = 32, yaw = 75, tilt = 26, accel = 28,   -- 虎式 UHT（德国陆军）：没有机炮，桅顶瞄准具
  seats = 2, flares = 40,
  rotor = { hub = V(0, 5.6, -0.6), r = 18.2, blades = 4, rpm = 350, dir = -1, chord = 1.2 }, tail = { hub = V(1.2, 4.2, 18.6), r = 3.8, blades = 3, rpm = 1650, axis = "x" },
  style = "attackheli", tandem = true, tw = 4.0, boom = 14, longbow = true,
  stub = { x = 3.0, span = 4.4, y = -0.4, z = 0.3 },
  st = mirror({
    { name = "outer", pos = V(6.6, -1.6, 0.3), opts = { "hot3", "aim92", "hydra" }, n = N({ hot3 = 4, aim92 = 2 }) },
    { name = "inner", pos = V(4.6, -1.8, 0.3), opts = { "hot3", "hydra" }, n = N({ hot3 = 4 }) },
  }),
  presets = { preset("at", { outer = "hot3", inner = "hot3" }), preset("mix", { outer = "aim92", inner = "hot3" }), preset("rkt", { outer = "hydra", inner = "hydra" }) } }
D.ah1w = { kind = "heli", cat = "heli", L = 39, W = 13.2, H = 12.2, gearH = 4.0, hp = 1000, vMax = 91, climb = 30, yaw = 70, tilt = 26, accel = 28,   -- AH-1W 超级眼镜蛇（美国海军陆战队）：双发、两片桨，M197 三管炮
  seats = 2, flares = 40, gun = "m197", gunAmmo = 750, gunPos = V(0, -2.8, -13.5),
  rotor = { hub = V(0, 5.4, -0.5), r = 20.5, blades = 2, rpm = 324, dir = 1, chord = 2.1 }, tail = { hub = V(-1.2, 4.6, 21.5), r = 4.2, blades = 2, rpm = 1660, axis = "x" },
  style = "attackheli", tandem = true, tw = 3.4, boom = 16,
  stub = { x = 2.8, span = 5.2, y = -0.4, z = 0.2 },
  st = mirror({
    { name = "tip", pos = V(8.2, -0.6, 0.3), opts = { "aim9x", "aim92" }, n = N({ aim9x = 1, aim92 = 2 }) },
    { name = "outer", pos = V(6.4, -1.6, 0.3), opts = { "agm114", "tow", "hydra" }, n = N({ agm114 = 4, tow = 4 }) },
    { name = "inner", pos = V(4.0, -1.6, 0.3), opts = { "agm114", "hydra" }, n = N({ agm114 = 4 }) },
  }),
  presets = { preset("at", { tip = "aim9x", outer = "agm114", inner = "agm114" }), preset("mix", { tip = "aim9x", outer = "tow", inner = "hydra" }),
    preset("rkt", { outer = "hydra", inner = "hydra" }) } }
D.ah1s = hv(D.ah1w, { L = 38, W = 9.0, hp = 820, vMax = 89, yaw = 65,   -- AH-1S（陆上自卫队）：单发、两片桨、陶式
  gunAmmo = 750, rotor = { hub = V(0, 5.2, -0.5), r = 18.8, blades = 2, rpm = 324, dir = 1, chord = 1.6 },
  tail = { hub = V(-1.2, 4.4, 21), r = 3.6, blades = 2, rpm = 1660, axis = "x" },
  stub = { x = 2.6, span = 4.0, y = -0.4, z = 0.2 },
  st = mirror({
    { name = "outer", pos = V(5.8, -1.6, 0.3), opts = { "tow", "hydra" }, n = N({ tow = 4 }) },
    { name = "inner", pos = V(3.8, -1.6, 0.3), opts = { "hydra", "tow" }, n = N({ tow = 4 }) },
  }),
  presets = { preset("at", { outer = "tow", inner = "hydra" }), preset("rkt", { outer = "hydra", inner = "hydra" }) } })
D.oh1 = { kind = "heli", cat = "heli", L = 34, W = 9.0, H = 10.8, gearH = 3.8, hp = 720, vMax = 90, climb = 34, yaw = 85, tilt = 28, accel = 30,   -- OH-1 忍者（川崎）：侦察直升机，涵道尾桨
  seats = 2, flares = 30,
  rotor = { hub = V(0, 4.8, -0.4), r = 16.2, blades = 4, rpm = 380, dir = 1, chord = 1.0 }, tail = { hub = V(-0.4, 3.2, 16.4), r = 1.8, blades = 8, rpm = 3000, axis = "x" },
  style = "attackheli", tandem = true, tw = 3.2, boom = 13,
  stub = { x = 2.4, span = 3.4, y = -0.4, z = 0.2 },
  st = mirror({ { name = "stub", pos = V(5.0, -1.2, 0.2), opts = { "type91" }, n = N({ type91 = 2 }) } }),
  presets = { preset("aa", { stub = "type91" }), preset("none", {}) } }
D.ah64dj = hv(D.ah64e, { hp = 980, like = "ah64e" })   -- AH-64DJ（陆上自卫队）：长弓阿帕奇，借 AH-64E 的原模型（like：没有自己的模型就用这一型的，挂点也照它）
D.mi8 = { kind = "heli", cat = "heli", L = 51, W = 9.0, H = 15.8, gearH = 4.8, hp = 1300, vMax = 81, climb = 24, yaw = 45, tilt = 20, accel = 20,   -- 米-8MT：运输，B-8V20 火箭巢
  seats = 4, transport = true, flares = 40, gun = "m134", gunAmmo = 1500, door = { x = 4.2, y = 0.8, z = -10 },
  rotor = { hub = V(0, 8.0, -1.5), r = 29.8, blades = 5, rpm = 192, dir = -1, chord = 1.6 }, tail = { hub = V(1.6, 6.4, 29.5), r = 5.4, blades = 3, rpm = 1124, axis = "x" },
  style = "utility", cabin = { w = 7.8, h = 6.6, len = 26 }, sideDoor = true,
  stub = { x = 4.4, span = 4.0, y = 0.0, z = -2.0 },
  st = mirror({ { name = "stub", pos = V(7.2, -0.6, -2.0), opts = { "s8" } } }),
  presets = { preset("none", {}), preset("rkt", { stub = "s8" }) } }
D.nh90 = { kind = "heli", cat = "heli", L = 45, W = 9.0, H = 14.6, gearH = 4.6, hp = 1050, vMax = 97, climb = 30, yaw = 55, tilt = 22, accel = 24,   -- NH90 TTH（德国陆军）：运输，舱门机枪
  seats = 4, transport = true, flares = 40, gun = "m134", gunAmmo = 1500, door = { x = 3.9, y = 0.8, z = -5.5 },
  rotor = { hub = V(0, 7.4, -1.0), r = 22.8, blades = 4, rpm = 256, dir = -1, chord = 1.6 }, tail = { hub = V(1.6, 6.0, 23.5), r = 4.5, blades = 4, rpm = 1300, axis = "x" },
  style = "utility", cabin = { w = 7.4, h = 6.4, len = 18 }, sideDoor = true,
  stub = { x = 4.2, span = 0.1, y = 0.6, z = 0.4 },
  st = {}, presets = { preset("none", {}) } }
D.uh1n = { kind = "heli", cat = "heli", L = 36, W = 8.0, H = 12.2, gearH = 4.0, hp = 900, vMax = 71, climb = 26, yaw = 60, tilt = 22, accel = 22,   -- UH-1N 双休伊（美国海军陆战队）：双发、两片桨，运输，舱门机枪、火箭巢
  seats = 4, transport = true, flares = 30, gun = "m134", gunAmmo = 1500, door = { x = 3.4, y = 0.6, z = -4.0 },
  rotor = { hub = V(0, 6.4, -1.0), r = 20.6, blades = 2, rpm = 324, dir = 1, chord = 1.6 }, tail = { hub = V(-1.2, 5.4, 21.5), r = 3.6, blades = 2, rpm = 1660, axis = "x" },
  style = "utility", cabin = { w = 6.8, h = 5.6, len = 14 }, sideDoor = true,
  stub = { x = 3.6, span = 2.6, y = 0.2, z = 0.0 },
  st = mirror({ { name = "stub", pos = V(5.8, -0.6, 0.0), opts = { "hydra" } } }),
  presets = { preset("none", {}), preset("rkt", { stub = "hydra" }) } }
D.z8 = { kind = "heli", cat = "heli", L = 56, W = 14, H = 18.6, gearH = 5.0, hp = 1350, vMax = 85, climb = 22, yaw = 40, tilt = 18, accel = 18,   -- 直-8（昌河，超黄蜂的路子）：六片桨，大运输舱
  seats = 4, transport = true, flares = 40, gun = "m134", gunAmmo = 1500, door = { x = 4.6, y = 1.0, z = -12 },
  rotor = { hub = V(0, 9.4, -2.0), r = 26.5, blades = 6, rpm = 210, dir = -1, chord = 1.8 }, tail = { hub = V(1.8, 8.2, 31.5), r = 5.6, blades = 5, rpm = 990, axis = "x" },
  style = "utility", cabin = { w = 8.6, h = 7.6, len = 30 }, sideDoor = true,
  stub = { x = 4.8, span = 2.4, y = -1.6, z = -2.0 },
  st = mirror({ { name = "stub", pos = V(6.8, -2.2, -2.0), opts = { "fl90" } } }),
  presets = { preset("none", {}), preset("rkt", { stub = "fl90" }) } }
D.ch47j = hv(D.ch47, { like = "ch47" })   -- CH-47J（陆上自卫队）：借 CH-47 的原模型
D.uh60ja = hv(D.uh60, { like = "uh60" })   -- UH-60JA（陆上自卫队）：借 UH-60 的原模型

---------------------------------------------------------------- 固定翼

-- 外形：fus 机身（长、宽、高）、nose 机头锥长、canopy 座舱盖（z、长、宽、高）、wing / canard / htail 梯形（一半，右边）、
--   vt 垂尾 { x, zr0, zr1, zt0, zt1, h, cant }（allMove 全动）、eng 发动机尾喷口 { x, y, z, r }、intake 进气道样式、
--   gear { nose = { z, len }, main = { x, z, len }, r 机轮半径 }、bays 弹舱门 { main = { z0, z1, w }, sideR = { x, z0, z1, w } }
--   carrier 舰载（尾钩、能从航母起飞）、fold 折叠机翼（翼根 x）
D.j20 = { kind = "jet", cat = "jet", L = 57, W = 36, H = 12.5, gearH = 6.4, hp = 700, stall = 105, vMil = 360, vAB = 470, accel = 52, abAccel = 34,
  pitch = 48, roll = 210, yaw = 18, g = 9, flares = 32, gun = nil, ab = true, stealth = true,
  fus = { len = 55, w = 6.4, h = 4.6, y = 0 }, nose = 10, canopy = { z = -15.5, len = 9.5, w = 3.0, h = 2.4, y = 2.4 },
  intake = "dsi", intakeZ = -8, intakeW = 2.4,
  wing = { xr = 3.0, zr0 = -4, zr1 = 20, xt = 18, zt0 = 12.5, zt1 = 16.5, y = 0.2 }, elevon = true,
  canard = { xr = 3.0, zr0 = -15, zr1 = -8.5, xt = 10, zt0 = -9.5, zt1 = -7.5, y = 1.0 },
  vt = { x = 3.6, zr0 = 16, zr1 = 26, zt0 = 22.5, zt1 = 27, h = 8.5, cant = 27, allMove = true },
  eng = { { x = 1.9, y = 0, z = 27.5, r = 1.35 }, { x = -1.9, y = 0, z = 27.5, r = 1.35 } },
  -- 起落架位置照原模型补的那套（tools/models/j20_gear.py：前起落架在座舱下、主起落架在侧弹舱后面，都往前收）；没导入原模型时零件拼的也摆这里
  gear = { nose = { z = -13.6, len = 5.2 }, main = { x = 3.4, z = 11.6, len = 5.0 }, r = 1.1 },
  -- 弹舱照原模型（j20_v5，tools/models/mainbay.py）和真机（用户 11-23：「检查一下 j20 弹仓打开是不是跟现实一样」）：
  --   主弹舱 x ±2.18、z −6.16～5.88，四枚霹雳-15 一排挂在舱顶的弹射发射架下（中间龙骨分开左右两半，外侧两枚往后错一点）；pos 是挂点（弹背），弹体中心再往下半个弹径
  --   侧弹舱在机身下侧的斜面上：霹雳-10 收在舱里，sideArm 是挂架的转轴（右侧，机体坐标）和转多少——挂架绕转轴把弹连发射轨一起转出舱外、
  --   舱门随后关上（AirModels.lua：先开门、再转出、再关门）；侧弹舱的 pos 是收在舱里时的弹体中心
  bays = { main = { z0 = -6.16, z1 = 5.88, w = 4.37 }, sideR = { x = 3.9, z0 = -5.29, z1 = 4.34, w = 1.3 } },
  sideArm = { p = V(3.2435, -1.7543, 0), A = math.rad(86) },
  st = mirror({
    { name = "bayM1", pos = V(0.55, -1.51, -0.42), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayM2", pos = V(1.55, -1.51, 0.12), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayS", pos = V(3.493, -0.6915, -0.476), bay = "sideR", opts = { "pl10" } },
    { name = "wing", pos = V(9.5, -1.0, 7.5), opts = { "pl15", "pl10", "kd88", "ls6", "lt2" } },
  }),
  presets = { preset("aa", { bayM1 = "pl15", bayM2 = "pl15", bayS = "pl10" }), preset("ag", { bayM1 = "ls6", bayM2 = "pl15", bayS = "pl10" }),
    preset("beast", { bayM1 = "pl15", bayM2 = "pl15", bayS = "pl10", wing = "kd88" }) } }
D.j35 = { kind = "jet", cat = "jet", L = 48, W = 32, H = 13, gearH = 6.6, hp = 650, stall = 98, vMil = 350, vAB = 450, accel = 50, abAccel = 34,
  pitch = 50, roll = 220, yaw = 20, g = 9, flares = 32, ab = true, stealth = true, carrier = true, fold = 9.5,
  fus = { len = 46, w = 6.0, h = 4.6, y = 0 }, nose = 9, canopy = { z = -12, len = 8.5, w = 2.9, h = 2.4, y = 2.4 },
  intake = "dsi", intakeZ = -6, intakeW = 2.2,
  wing = { xr = 3.0, zr0 = -1, zr1 = 13, xt = 16, zt0 = 9, zt1 = 13.5, y = 0.2 },
  htail = { xr = 2.6, zr0 = 15, zr1 = 22, xt = 9.5, zt0 = 19.5, zt1 = 22.5, y = 0.2 },
  vt = { x = 3.2, zr0 = 11.5, zr1 = 20, zt0 = 17, zt1 = 21, h = 7.6, cant = 25 },
  eng = { { x = 1.7, y = 0, z = 23.5, r = 1.25 }, { x = -1.7, y = 0, z = 23.5, r = 1.25 } },
  gear = { nose = { z = -12, len = 5.4 }, main = { x = 3.2, z = 4.5, len = 5.2 }, r = 1.1, hook = 20 },
  bays = { main = { z0 = -4, z1 = 7, w = 4.6 } },
  st = mirror({
    { name = "bay1", pos = V(1.1, -2.2, 1.5), bay = "main", opts = { "pl15", "pl10", "ls6" } },
    { name = "bay2", pos = V(2.9, -1.9, 1.5), bay = "main", opts = { "pl15", "pl10", "ls6" } },
    { name = "wingI", pos = V(7.2, -1.1, 5.5), opts = { "pl15", "kd88", "ls6", "lt2" } },
    { name = "wingO", pos = V(11.5, -0.9, 8.0), opts = { "pl10", "pl15", "pl12" } },
  }),
  presets = { preset("aa", { bay1 = "pl15", bay2 = "pl15" }), preset("ag", { bay1 = "ls6", bay2 = "pl15" }),
    preset("beast", { bay1 = "pl15", bay2 = "pl15", wingI = "kd88", wingO = "pl10" }) } }
D.j15t = { kind = "jet", cat = "jet", L = 61, W = 41, H = 16.5, gearH = 7.2, hp = 760, stall = 102, vMil = 330, vAB = 440, accel = 46, abAccel = 34,
  pitch = 44, roll = 190, yaw = 18, g = 8.5, flares = 48, gun = "gsh30", gunAmmo = 150, gunPos = V(3.0, 1.2, -16), ab = true, carrier = true, fold = 9.7,
  fus = { len = 58, w = 5.2, h = 4.6, y = 0 }, nose = 11, canopy = { z = -17, len = 9, w = 2.8, h = 2.5, y = 2.6 },
  intake = "box", intakeZ = -4, intakeW = 3.0, nacelle = { x = 2.8, w = 3.4, h = 3.4 },
  wing = { xr = 4.0, zr0 = -8, zr1 = 12, xt = 20.5, zt0 = 9, zt1 = 13, y = 0.4, lerx = true },
  canard = { xr = 3.4, zr0 = -13, zr1 = -8.5, xt = 8.5, zt0 = -10, zt1 = -7.5, y = 1.0 },
  htail = { xr = 4.6, zr0 = 17, zr1 = 25, xt = 12.5, zt0 = 22.5, zt1 = 26, y = -0.2 },
  vt = { x = 3.3, zr0 = 13, zr1 = 23.5, zt0 = 21, zt1 = 25, h = 10, cant = 0 },
  eng = { { x = 2.8, y = -0.2, z = 28.5, r = 1.5 }, { x = -2.8, y = -0.2, z = 28.5, r = 1.5 } },
  gear = { nose = { z = -14, len = 6.0 }, main = { x = 3.6, z = 3.5, len = 5.6 }, r = 1.25, hook = 24 },
  st = mirror({
    { name = "tip", pos = V(20.6, -0.1, 11.5), opts = { "pl10" } },
    { name = "outer", pos = V(16, -1.1, 8.5), opts = { "pl10", "pl15", "pl12" } },
    { name = "mid", pos = V(12, -1.3, 6.0), opts = { "pl15", "pl12", "kd88", "yj83k", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "inner", pos = V(7.8, -1.5, 4.0), opts = { "pl15", "pl12", "kd88", "yj83k", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "duct", pos = V(2.8, -3.6, 3.0), opts = { "pl15", "pl12", "ls6" }, ej = true },
  }),
  presets = { preset("aa", { tip = "pl10", outer = "pl10", mid = "pl15", inner = "pl15", duct = "pl15" }),
    preset("antiship", { tip = "pl10", outer = "pl12", mid = "pl15", inner = "yj83k", duct = "pl15" }),   -- 两枚鹰击-83K（原模型的挂法）
    preset("ag", { tip = "pl10", outer = "pl15", mid = "kd88", inner = "ls6", duct = "ls6" }),
    preset("strike", { tip = "pl10", mid = "b250", inner = "b250", duct = "ls6" }),
    preset("sead", { tip = "pl10", outer = "pl12", mid = "yj91", inner = "lt2", duct = "pl15" }) } }
D.j16 = { kind = "jet", cat = "jet", L = 61, W = 41, H = 16.5, gearH = 7.2, hp = 780, stall = 100, vMil = 335, vAB = 450, accel = 46, abAccel = 36,
  pitch = 44, roll = 190, yaw = 18, g = 8.5, flares = 48, gun = "gsh30", gunAmmo = 150, gunPos = V(3.0, 1.2, -16), ab = true,
  fus = { len = 58, w = 5.2, h = 4.6, y = 0 }, nose = 11, canopy = { z = -16.5, len = 10.5, w = 2.8, h = 2.5, y = 2.6 }, twoSeat = true,
  intake = "box", intakeZ = -4, intakeW = 3.0, nacelle = { x = 2.8, w = 3.4, h = 3.4 },
  wing = { xr = 4.0, zr0 = -8, zr1 = 12, xt = 20.5, zt0 = 9, zt1 = 13, y = 0.4, lerx = true },
  htail = { xr = 4.6, zr0 = 17, zr1 = 25, xt = 12.5, zt0 = 22.5, zt1 = 26, y = -0.2 },
  vt = { x = 3.3, zr0 = 13, zr1 = 23.5, zt0 = 21, zt1 = 25, h = 10, cant = 0 },
  eng = { { x = 2.8, y = -0.2, z = 28.5, r = 1.5 }, { x = -2.8, y = -0.2, z = 28.5, r = 1.5 } },
  gear = { nose = { z = -14, len = 6.0 }, main = { x = 3.6, z = 3.5, len = 5.6 }, r = 1.25 },
  st = mirror({
    { name = "tip", pos = V(20.6, -0.1, 11.5), opts = { "pl10" } },
    { name = "outer", pos = V(16, -1.1, 8.5), opts = { "pl10", "pl15", "pl12" } },
    { name = "mid", pos = V(12, -1.3, 6.0), opts = { "pl15", "pl12", "kd88", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "inner", pos = V(7.8, -1.5, 4.0), opts = { "pl15", "pl12", "kd88", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "duct", pos = V(2.8, -3.6, 3.0), opts = { "pl15", "pl12", "ls6", "kd88" }, ej = true },
  }),
  presets = { preset("aa", { tip = "pl10", outer = "pl10", mid = "pl15", inner = "pl15", duct = "pl15" }),
    preset("ag", { tip = "pl10", outer = "pl15", mid = "kd88", inner = "kd88", duct = "ls6" }),
    preset("strike", { tip = "pl10", outer = "pl15", mid = "b250", inner = "b250", duct = "ls6" }),
    preset("sead", { tip = "pl10", outer = "pl12", mid = "yj91", inner = "yj91", duct = "pl15" }) } }
-- 歼-11B（用户 11-22：「sketchfeb 有个 j36 j10 j11……全部下载下来做进去」）：沈飞照苏-27 做的单座重型战斗机；原模型 Rhine_Lab_Muelsyse 的「Shenyang J-11」
--   （CC-BY，models/air/j11.glb，tools/models/sf_air.py）：全长 21.9 米、翼展 14.7 米、全高 5.9 米；全动平尾、襟副翼、双垂尾方向舵、背上的大减速板、
--   起落架舱门是原模型的（放起落架时打开），支柱、机轮用零件拼的（原模型是收着起落架的飞行状态）；普通喷口，没有推力矢量
D.j11 = { kind = "jet", cat = "jet", L = 61, W = 39, H = 14, gearH = 10, hp = 760, stall = 98, vMil = 330, vAB = 445, accel = 45, abAccel = 35,
  pitch = 44, roll = 200, yaw = 18, g = 9, flares = 48, gun = "gsh30", gunAmmo = 150, gunPos = V(2.6, 0.6, -9), ab = true,
  fus = { len = 58, w = 5.0, h = 4.4, y = 0 }, nose = 11, canopy = { z = -13.1, len = 6.2, w = 2.8, h = 1.9, y = 1.8 },
  intake = "box", intakeZ = -4, intakeW = 3.0, nacelle = { x = 2.6, w = 3.4, h = 3.4 },
  wing = { xr = 4.0, zr0 = -8, zr1 = 12, xt = 19.3, zt0 = 9, zt1 = 13, y = 0.0, lerx = true },
  htail = { xr = 4.6, zr0 = 17, zr1 = 25, xt = 12.5, zt0 = 22.5, zt1 = 26, y = -0.2 },
  vt = { x = 5.5, zr0 = 12, zr1 = 23, zt0 = 19, zt1 = 23.5, h = 9.5, cant = 0 },
  eng = { { x = 2.4, y = -0.1, z = 27.7, r = 1.65 }, { x = -2.4, y = -0.1, z = 27.7, r = 1.65 } },
  gear = { nose = { z = -11.5, len = 7.8 }, main = { x = 5.3, z = 6.0, len = 8.2 }, r = 1.45 },
  st = mirror({
    { name = "tip", pos = V(19.3, -0.2, 11.5), opts = { "pl10" } },
    { name = "outer", pos = V(14.5, -1.0, 8.0), opts = { "pl10", "pl12" } },
    { name = "mid", pos = V(10.5, -1.2, 5.0), opts = { "pl12", "pl15", "kd88", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "duct", pos = V(2.6, -3.0, 2.0), opts = { "pl12", "pl15" }, ej = true },
    { name = "ctr", pos = V(0, -2.6, -3.0), opts = { "pl12", "pl15", "ls6", "b250" }, n = N({ b250 = 2 }), ej = true },
  }),
  presets = { preset("aa", { tip = "pl10", outer = "pl10", mid = "pl12", duct = "pl12", ctr = "pl15" }),
    preset("ag", { tip = "pl10", outer = "pl12", mid = "kd88", duct = "pl12", ctr = "ls6" }),
    preset("strike", { tip = "pl10", outer = "pl12", mid = "b250", duct = "pl12", ctr = "b250" }) } }
-- 歼-10C：成飞的单发鸭式三角翼多用途战斗机；原模型 andertan 的「Chengdu J10 "Vigorous Dragon"」（CC-BY，models/air/j10.glb）：
--   全长 16.9 米、翼展 9.8 米、全高 5.43 米；全动鸭翼、内外两段升降副翼、方向舵、座舱盖（前风挡不动）；腹部进气道、单个喷口（不带推力矢量）；
--   原模型是飞行状态，起落架用零件拼的
D.j10 = { kind = "jet", cat = "jet", L = 47, W = 28, H = 13, gearH = 6.4, hp = 620, stall = 92, vMil = 330, vAB = 450, accel = 48, abAccel = 38,
  pitch = 48, roll = 230, yaw = 20, g = 9, flares = 32, gun = "gsh30", gunAmmo = 200, gunPos = V(-1.5, -2.6, -4), ab = true,
  fus = { len = 45, w = 4.4, h = 4.2, y = 0 }, nose = 9, canopy = { z = -10.1, len = 5.0, w = 2.2, h = 2.0, y = 2.1 },
  intake = "box", intakeZ = -2, intakeW = 2.4,
  wing = { xr = 2.4, zr0 = -2, zr1 = 14.5, xt = 13.8, zt0 = 12.3, zt1 = 14.2, y = -2.0 },
  canard = { xr = 1.6, zr0 = -8.5, zr1 = -3.5, xt = 6.6, zt0 = -5.0, zt1 = -3.6, y = 0.6 },
  vt = { x = 0, zr0 = 11, zr1 = 23.5, zt0 = 20.5, zt1 = 24, h = 9.4, cant = 0 },
  eng = { { x = 0, y = -2.5, z = 22.1, r = 1.48 } },
  gear = { nose = { z = -9, len = 5.8 }, main = { x = 4.0, z = 6.5, len = 6.0 }, r = 1.1 },
  st = mirror({
    { name = "outer", pos = V(11.0, -2.8, 9.5), opts = { "pl10", "pl12" } },
    { name = "mid", pos = V(8.0, -2.9, 7.0), opts = { "pl10", "pl12", "pl15", "ls6", "lt2", "b250", "yj91" } },
    { name = "inner", pos = V(5.0, -3.0, 5.0), opts = { "pl12", "pl15", "ls6", "lt2", "b250", "kd88" } },
    { name = "body", pos = V(2.0, -3.8, 3.0), opts = { "pl12", "pl15" } },
    { name = "ctr", pos = V(0, -4.2, 0), opts = { "pl15", "ls6", "b250" } },
  }),
  presets = { preset("aa", { outer = "pl10", mid = "pl12", inner = "pl15", body = "pl15", ctr = "pl15" }),
    preset("ag", { outer = "pl10", mid = "ls6", inner = "kd88", body = "pl12", ctr = "ls6" }),
    preset("sead", { outer = "pl10", mid = "yj91", inner = "pl15", body = "pl12", ctr = "pl15" }),
    preset("strike", { outer = "pl10", mid = "b250", inner = "b250", body = "pl12", ctr = "b250" }) } }
-- 歼-36：成飞的三发无尾「双三角 / 菱形翼」第六代战斗机（2024 年 12 月首飞）；原模型 positivevubez4eva 的「J36 v2」（CC-BY，models/air/j36.glb）：
--   全长 23 米、翼展 24 米（模型）、全高约 4.2 米；没有垂尾——后缘三段升降副翼（最外一段兼管偏航）；两侧 DSI 进气道加机背一个进气口、
--   三个喷口藏在机背的槽里；主弹舱 7.2 米长（两扇门）、两边侧弹舱各一扇门；小车式主起落架（一边前后两个轮）往前收、双轮前起落架往后收；只挂内弹舱
D.j36 = { kind = "jet", cat = "jet", L = 64, W = 68, H = 12, gearH = 7.0, hp = 820, stall = 100, vMil = 360, vAB = 480, accel = 50, abAccel = 36,
  pitch = 40, roll = 170, yaw = 14, g = 8.5, flares = 40, gun = nil, ab = true, stealth = true, flyingWing = true,
  fus = { len = 62, w = 8.4, h = 5.0, y = 0 }, nose = 12, canopy = { z = -18.8, len = 7.7, w = 4.8, h = 2.0, y = 2.8 },
  intake = "dsi", intakeZ = -10, intakeW = 2.6,
  wing = { xr = 8.4, zr0 = -14.7, zr1 = 30.8, xt = 34, zt0 = 17.1, zt1 = 22.1, y = 0 },
  eng = { { x = 4.5, y = 0.4, z = 19.8, r = 1.2 }, { x = -4.5, y = 0.4, z = 19.8, r = 1.2 }, { x = 0, y = 0.4, z = 19.8, r = 1.2 } },
  gear = { nose = { z = -17.1, len = 5.6 }, main = { x = 7.3, z = 8.1, len = 5.2, bogie = true }, r = 1.2 },
  bays = { main = { z0 = -11.4, z1 = 8.8, w = 6.6 }, sideR = { x = 4.5, z0 = -5.0, z1 = 8.8, w = 2.4 } },
  st = mirror({
    { name = "bayM1", pos = V(1.4, -1.7, -5.0), bay = "main", opts = { "pl15", "pl12", "ls6", "lt2" } },
    { name = "bayM2", pos = V(2.4, -1.9, 3.5), bay = "main", opts = { "pl15", "pl12", "ls6", "kd88" } },
    { name = "bayS", pos = V(4.5, -1.7, 1.8), bay = "sideR", opts = { "pl10" } },
  }),
  presets = { preset("aa", { bayM1 = "pl15", bayM2 = "pl15", bayS = "pl10" }), preset("ag", { bayM1 = "ls6", bayM2 = "pl15", bayS = "pl10" }),
    preset("strike", { bayM1 = "lt2", bayM2 = "kd88", bayS = "pl10" }) } }
-- 歼-6（用户 11-25 看机库截图：「这个j6很奇怪」——原来科技树的歼-6 借歼-8II 的模型和性能）：沈飞照米格-19S 造的双发超音速战斗机（1958 年首飞），
--   机头进气、55° 后掠中单翼带大翼刀、全动平尾、两台涡喷-6 并排；原模型 andertan 的「Shenyang J-6 "Farmer"」（CC-BY，models/air/j6.glb）。
--   尺寸照模型量（全长 12.54 米、翼展 8.74 米、垂尾顶离地 3.9 米）；三门 30-1 型 30 毫米炮（翼根两门各 70 发、机头一门 55 发），
--   翼下两对挂架：中段挂副油箱 / 250 公斤炸弹 / 火箭巢，内侧挂霹雳-2 / 火箭巢；没有雷达、没有热诱弹；
--   速度按真机（最大 1452 千米/时、马赫 1.35）在这张表里的比例：比歼-8II 慢三成，转得比它灵
D.j6 = { kind = "jet", cat = "jet", L = 35.1, W = 24.5, H = 10.9, gearH = 4.7, hp = 520, stall = 86, vMil = 268, vAB = 328, accel = 40, abAccel = 34,
  pitch = 40, roll = 150, yaw = 15, g = 8, flares = 0, gun = "nr30", gunAmmo = 195, gunPos = V(0, -0.5, -11.5), ab = true,
  fus = { len = 34, w = 3.8, h = 3.8, y = 0 }, nose = 1.5, canopy = { z = -9.1, len = 4.6, w = 1.9, h = 0.95, y = 2.1 },
  intake = "nose",
  wing = { xr = 1.3, zr0 = -9.5, zr1 = 2.6, xt = 12.2, zt0 = 5.4, zt1 = 9.4, y = -0.6, dihedral = -4.5 },
  htail = { xr = 0.3, zr0 = 6.4, zr1 = 13.1, xt = 6.0, zt0 = 13.4, zt1 = 16.2, y = 0.8 },
  vt = { x = 0, zr0 = 4, zr1 = 14, zt0 = 13.2, zt1 = 17.5, h = 6.2, cant = 0 },
  eng = { { x = 0.5, y = 0, z = 12.8, r = 0.5 }, { x = -0.5, y = 0, z = 12.8, r = 0.5 } },
  gear = { nose = { z = -10.8, len = 3.7 }, main = { x = 5.8, z = 1.0, len = 3.5 }, r = 0.95 },
  st = mirror({
    { name = "outer", pos = V(6.92, -2.25, 1.2), opts = { "tk800", "b250", "fl90" } },   -- 翼刀下面那对挂架：副油箱 / 炸弹 / 火箭巢
    { name = "inner", pos = V(3.67, -1.45, -3.8), opts = { "pl2", "fl90" } },            -- 内侧挂架：霹雳-2 / 火箭巢
  }),
  presets = { preset("aa", { outer = "tk800", inner = "pl2" }), preset("ag", { outer = "b250", inner = "fl90" }), preset("strike", { outer = "fl90", inner = "fl90" }) } }
-- 歼-8II（用户 11-23：「你再把 j8 和 f16 f15 f14 都做进去」）：沈飞的双发高空高速截击机（1984 年首飞），机头雷达罩 + 两侧进气道、
--   60° 三角翼、全动平尾、单垂尾加一片机腹折叠腹鳍；原模型 Rhine_Lab_Muelsyse 的「Shenyang J-8II/B」（CC-BY，models/air/j8.glb）：
--   全长 21.59 米、翼展 9.34 米、全高 5.41 米；副翼、襟翼、全动平尾、方向舵、座舱盖、起落架都是原模型单独的节点；
--   机腹 23-3 型双管 23 毫米炮（200 发）；7 个挂点：翼下 4 个（霹雳-8 / 霹雳-12 / 火箭巢 / 炸弹）、机腹中线副油箱
D.j8 = { kind = "jet", cat = "jet", L = 60, W = 26, H = 15, gearH = 6.6, hp = 640, stall = 105, vMil = 320, vAB = 455, accel = 42, abAccel = 36,
  pitch = 36, roll = 160, yaw = 14, g = 7, flares = 24, gun = "gsh23", gunAmmo = 200, gunPos = V(0, -2.4, -6), ab = true,
  fus = { len = 58, w = 4.6, h = 4.4, y = 0 }, nose = 12, canopy = { z = -16.5, len = 6.0, w = 2.4, h = 1.8, y = 2.2 },
  intake = "box", intakeZ = -10, intakeW = 2.6, nacelle = { x = 1.9, w = 2.6, h = 3.2 },
  wing = { xr = 2.6, zr0 = -3, zr1 = 18, xt = 13.1, zt0 = 15.5, zt1 = 18.5, y = -0.6 },
  htail = { xr = 2.2, zr0 = 21, zr1 = 27, xt = 9.0, zt0 = 25.5, zt1 = 28, y = 0.2 },
  vt = { x = 0, zr0 = 12, zr1 = 26, zt0 = 23, zt1 = 28, h = 9.6, cant = 0 },
  eng = { { x = 1.25, y = -0.2, z = 30, r = 1.05 }, { x = -1.25, y = -0.2, z = 30, r = 1.05 } },
  gear = { nose = { z = -16, len = 5.6 }, main = { x = 5.2, z = 6, len = 5.4 }, r = 1.15 },
  st = mirror({
    { name = "outer", pos = V(10.8, -1.4, 13), opts = { "pl10" } },
    { name = "mid", pos = V(8.0, -1.6, 10), opts = { "pl10", "pl12", "fl90", "b250" } },
    { name = "inner", pos = V(5.2, -1.8, 7.5), opts = { "pl12", "b250", "fl90", "tk800" } },
    { name = "ctr", pos = V(0, -2.9, 2), opts = { "tk800", "b250" } },
  }),
  presets = { preset("aa", { outer = "pl10", mid = "pl12", inner = "pl12", ctr = "tk800" }), preset("ag", { outer = "pl10", mid = "fl90", inner = "b250", ctr = "tk800" }),
    preset("strike", { outer = "pl10", mid = "b250", inner = "b250", ctr = "b250" }) } }
-- 歼-50 11-22 删掉了（用户：j50 删掉）
D.h6k = { kind = "jet", cat = "jet", L = 97, W = 92, H = 29, gearH = 10.5, hp = 1150, stall = 85, vMil = 240, accel = 22, pitch = 16, roll = 50, yaw = 10, g = 3,
  flares = 60, bomber = true,
  fus = { len = 92, w = 8.6, h = 8.6, y = 0 }, nose = 12, canopy = { z = -36, len = 10, w = 6.0, h = 3.2, y = 4.0 },
  wing = { xr = 4.0, zr0 = -10, zr1 = 9, xt = 46, zt0 = 9, zt1 = 17, y = -1.5, dihedral = -3 },
  htail = { xr = 3.0, zr0 = 32, zr1 = 43, xt = 17, zt0 = 39, zt1 = 45, y = 1.5 },
  vt = { x = 0, zr0 = 26, zr1 = 45, zt0 = 40, zt1 = 47, h = 21, cant = 0 },
  pods = { { x = 6.4, y = -3.2, z = 0, len = 20, r = 2.7 } }, eng = { { x = 6.4, y = -3.2, z = 10.5, r = 1.8 }, { x = -6.4, y = -3.2, z = 10.5, r = 1.8 } },
  gear = { nose = { z = -32, len = 8.5 }, main = { x = 16, z = 6, len = 8.0, bogie = true }, r = 1.6 },
  bays = { main = { z0 = -6, z1 = 14, w = 6.4 } },
  st = mirror({
    { name = "bay", pos = V(0, -3.6, 4), bay = "main", opts = { "b250", "hn1" }, n = N({ b250 = 12, hn1 = 1 }) },   -- 弹舱：12 枚 250 公斤炸弹，或者一枚「惊雷-1」核导弹
    { name = "pylI", pos = V(13, -3.4, 1.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
    { name = "pylM", pos = V(21, -3.2, 4.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
    { name = "pylO", pos = V(29, -3.0, 7.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
  }),
  presets = { preset("bomb", { bay = "b250", pylI = "b250", pylM = "b250", pylO = "b250" }), preset("kd88", { bay = "b250", pylI = "kd88", pylM = "kd88", pylO = "kd88" }),
    preset("nuke", { bay = "hn1", pylI = "kd88", pylM = "kd88", pylO = "kd88" }) } }
D.gj11 = { kind = "jet", cat = "jet", L = 28, W = 39, H = 6.0, gearH = 4.8, hp = 420, stall = 85, vMil = 280, accel = 36, pitch = 34, roll = 120, yaw = 10, g = 6,
  flares = 16, drone = true, stealth = true, flyingWing = true,
  fus = { len = 26, w = 6.0, h = 3.0, y = 0.4 }, nose = 6,
  wing = { xr = 2.0, zr0 = -13, zr1 = 9, xt = 19.5, zt0 = 6, zt1 = 9.5, y = 0, saw = true },
  eng = { { x = 0, y = 0.8, z = 12.5, r = 1.2, flat = true } },
  gear = { nose = { z = -6, len = 3.6 }, main = { x = 3.4, z = 2.0, len = 3.6 }, r = 0.8 },
  bays = { main = { z0 = -6, z1 = 3, w = 4.4 } },
  st = mirror({ { name = "bay", pos = V(1.2, -1.2, -1.5), bay = "main", opts = { "ls6", "lt2", "pl10" } } }),
  presets = { preset("ag", { bay = "ls6" }) } }
D.gj2 = { kind = "jet", cat = "jet", L = 31, W = 57, H = 11, gearH = 5.8, hp = 380, stall = 50, vMil = 130, accel = 20, pitch = 26, roll = 70, yaw = 12, g = 4,
  flares = 12, drone = true, prop = true,
  fus = { len = 30, w = 3.8, h = 3.8, y = 0 }, nose = 6, sat = true,
  wing = { xr = 2.0, zr0 = -2, zr1 = 3.8, xt = 28.5, zt0 = 0.5, zt1 = 3.0, y = 1.4 },
  vtail = { z0 = 9, z1 = 14.5, h = 6.5, span = 6, angle = 40, inverted = false },
  eng = { { x = 0, y = 0, z = 15.2, r = 0.6, prop = 3.4 } },
  gear = { nose = { z = -10, len = 3.8 }, main = { x = 3.0, z = 1.5, len = 4.4, fixed = true }, r = 0.9 },
  st = mirror({
    { name = "inner", pos = V(5.5, 0.4, 0.8), opts = { "akd10", "ls6" }, n = N({ akd10 = 1 }) },
    { name = "mid", pos = V(9.5, 0.6, 0.8), opts = { "akd10", "ls6" } },
    { name = "outer", pos = V(13.5, 0.8, 0.8), opts = { "akd10", "ty90" } },
  }),
  presets = { preset("at", { inner = "ls6", mid = "akd10", outer = "akd10" }), preset("ag", { inner = "ls6", mid = "ls6", outer = "akd10" }) } }
D.a10c = { kind = "jet", cat = "jet", L = 46, W = 49, H = 12.5, gearH = 6.0, hp = 1100, stall = 70, vMil = 210, accel = 26, pitch = 34, roll = 110, yaw = 16, g = 6.5,
  flares = 60, gun = "gau8", gunAmmo = 1150, gunPos = V(0, -0.8, -24), straight = true,
  fus = { len = 44, w = 4.4, h = 4.8, y = 0 }, nose = 6, canopy = { z = -14, len = 5.5, w = 2.8, h = 2.6, y = 2.6 },
  wing = { xr = 2.4, zr0 = -4, zr1 = 3.5, xt = 24.5, zt0 = -2.0, zt1 = 3.0, y = -1.4 },
  htail = { xr = 2.0, zr0 = 16, zr1 = 21, xt = 9.5, zt0 = 16.8, zt1 = 21, y = 1.0 },
  vt = { x = 9.6, zr0 = 15, zr1 = 21.5, zt0 = 16.5, zt1 = 21.5, h = 9, y0 = -3.4, cant = 0, endplate = true },
  -- 发动机（用户：A-10 的发动机像个摆设）：TF34 涡扇——进气口里的风扇跟着油门转（fan：喷口往前多远是风扇，按原模型发动机舱量的），
  --   喷口后面有淡淡的热浪、油门大时喷口里暗橙（mild：涵道比高、排气温度低，比战斗机淡得多）
  pods = { { x = 3.4, y = 3.2, z = 9, len = 9, r = 1.9 } }, eng = { { x = 3.4, y = 3.2, z = 14, r = 1.4, fan = 9.6, mild = true }, { x = -3.4, y = 3.2, z = 14, r = 1.4, fan = 9.6, mild = true } },
  fanEng = true,
  gear = { nose = { z = -17, len = 4.5 }, main = { x = 8.5, z = -2.5, len = 4.5, pod = true }, r = 1.25 },
  st = mirror({
    { name = "tip", pos = V(22, -2.3, -0.2), opts = { "aim9x" }, n = N({ aim9x = 2 }) },
    { name = "outer", pos = V(17.5, -2.3, -0.4), opts = { "agm65", "hydra", "mk82", "gbu38" }, n = N({ agm65 = 1, mk82 = 1 }) },
    { name = "mid", pos = V(13, -2.3, -0.6), opts = { "agm65", "gbu12", "mk82", "gbu38", "hydra" }, n = N({ agm65 = 3 }) },
    { name = "inner", pos = V(8.6, -2.6, -0.8), opts = { "gbu12", "mk82", "gbu31", "gbu32", "gbu38" } },
  }),
  presets = { preset("cas", { tip = "aim9x", outer = "hydra", mid = "agm65", inner = "gbu12" }), preset("bomb", { tip = "aim9x", outer = "mk82", mid = "mk82", inner = "gbu31" }),
    preset("jdam", { tip = "aim9x", outer = "gbu38", mid = "gbu38", inner = "gbu32" }) } }
D.f35 = { kind = "jet", cat = "jet", L = 44, W = 30, H = 12.3, gearH = 6.2, hp = 650, stall = 98, vMil = 340, vAB = 445, accel = 48, abAccel = 32,
  pitch = 48, roll = 210, yaw = 18, g = 9, flares = 30, gun = "gau22", gunAmmo = 180, gunPos = V(-2.4, 1.6, -6), ab = true, stealth = true,
  fus = { len = 42, w = 6.6, h = 5.0, y = 0 }, nose = 9, canopy = { z = -11.5, len = 8, w = 3.0, h = 2.4, y = 2.6 },
  intake = "dsi", intakeZ = -6, intakeW = 2.4,
  wing = { xr = 3.3, zr0 = -1, zr1 = 11.5, xt = 15, zt0 = 8.5, zt1 = 12, y = 0.3 },
  htail = { xr = 2.6, zr0 = 13.5, zr1 = 20.5, xt = 9.4, zt0 = 18, zt1 = 21, y = 0.2 },
  vt = { x = 3.1, zr0 = 10.5, zr1 = 18, zt0 = 15.5, zt1 = 19, h = 7.0, cant = 25 },
  eng = { { x = 0, y = 0, z = 22, r = 1.55 } },
  gear = { nose = { z = -11, len = 5.4 }, main = { x = 3.3, z = 4.0, len = 5.0 }, r = 1.1 },
  bays = { main = { z0 = -4, z1 = 6, w = 5.2, split = true } },
  st = mirror({
    { name = "bayO", pos = V(2.4, -2.3, 1.0), bay = "main", opts = { "gbu31", "gbu32", "gbu38", "gbu12", "gbu39", "aim120" }, n = N({ gbu39 = 4 }) },
    { name = "bayI", pos = V(1.0, -1.9, 1.0), bay = "main", opts = { "aim120" } },
    { name = "wingI", pos = V(7.0, -1.2, 5.0), opts = { "aim120", "gbu31", "gbu32", "gbu38", "gbu12", "agm88" } },
    { name = "wingO", pos = V(11.5, -1.0, 7.5), opts = { "aim9x", "aim120" } },
  }),
  presets = { preset("aa", { bayO = "aim120", bayI = "aim120" }), preset("ag", { bayO = "gbu31", bayI = "aim120" }),
    preset("sdb", { bayO = "gbu39", bayI = "aim120" }), preset("sead", { bayO = "aim120", bayI = "aim120", wingI = "agm88", wingO = "aim9x" }),
    preset("beast", { bayO = "gbu31", bayI = "aim120", wingI = "gbu12", wingO = "aim9x" }) } }
D.f22 = { kind = "jet", cat = "jet", L = 53, W = 38, H = 14, gearH = 6.6, hp = 700, stall = 100, vMil = 380, vAB = 480, accel = 56, abAccel = 34,
  pitch = 52, roll = 220, yaw = 20, g = 9, flares = 32, gun = "m61", gunAmmo = 480, gunPos = V(4.6, 1.6, -7), ab = true, stealth = true, tvc = true,
  fus = { len = 50, w = 7.0, h = 4.6, y = 0 }, nose = 10, canopy = { z = -14, len = 10, w = 3.1, h = 2.6, y = 2.4 },
  intake = "caret", intakeZ = -8, intakeW = 2.8,
  wing = { xr = 3.6, zr0 = -6, zr1 = 15, xt = 19, zt0 = 9.5, zt1 = 13.5, y = 0.2 },
  htail = { xr = 3.2, zr0 = 16, zr1 = 25, xt = 11, zt0 = 21.5, zt1 = 25.5, y = 0.2 },
  vt = { x = 4.4, zr0 = 11.5, zr1 = 21.5, zt0 = 19, zt1 = 23, h = 8.6, cant = 28 },
  eng = { { x = 2.3, y = 0, z = 26, r = 1.4, flat = true }, { x = -2.3, y = 0, z = 26, r = 1.4, flat = true } },
  gear = { nose = { z = -14, len = 5.4 }, main = { x = 3.6, z = 4.0, len = 5.2 }, r = 1.15 },
  bays = { main = { z0 = -4, z1 = 8, w = 5.2 }, sideR = { x = 4.5, z0 = -8, z1 = -3, w = 1.3 } },
  st = mirror({
    { name = "bayM1", pos = V(0.9, -2.2, 2.0), bay = "main", opts = { "aim120", "gbu31", "gbu32", "gbu39" }, n = N({ gbu39 = 4 }) },
    { name = "bayM2", pos = V(2.0, -2.0, 2.0), bay = "main", opts = { "aim120" } },
    { name = "bayM3", pos = V(3.1, -1.8, 2.0), bay = "main", opts = { "aim120" } },
    { name = "bayS", pos = V(4.5, -1.5, -5.5), bay = "sideR", opts = { "aim9x" } },
  }),
  presets = { preset("aa", { bayM1 = "aim120", bayM2 = "aim120", bayM3 = "aim120", bayS = "aim9x" }),
    preset("ag", { bayM1 = "gbu31", bayM2 = "aim120", bayM3 = "aim120", bayS = "aim9x" }),
    preset("sdb", { bayM1 = "gbu39", bayM2 = "aim120", bayM3 = "aim120", bayS = "aim9x" }) } }
-- F-16C Block 50/52「战隼」（用户 11-23 加的 F-16、F-15、F-14）：单发轻型多用途战斗机，机腹进气道、边条翼、单垂尾、两片腹鳍、右侧杆；
--   原模型 rave.Ar4ik 的「F-16 Fighting Falcon | NATO | GameReady」（CC-BY，models/air/f16.glb）——自带整套座舱（平显、正前方控制板、
--   两块 4 英寸多功能显示器、弹射座椅、侧杆、油门），座舱里看到的就是原模型的座舱，屏幕上贴我们的实时画面；
--   全长 15.06 米、翼展 9.45 米、全高 4.88 米；M61A1 20 毫米炮 511 发（左边条里）；9 个挂点：翼尖、翼下 6 个、机腹中线
D.f16 = { kind = "jet", cat = "jet", L = 42, W = 27, H = 13.7, gearH = 4.8, hp = 600, stall = 92, vMil = 335, vAB = 455, accel = 50, abAccel = 38,
  pitch = 50, roll = 240, yaw = 20, g = 9, flares = 30, gun = "m61", gunAmmo = 510, gunPos = V(-2.0, 1.2, -6), ab = true,
  fus = { len = 40, w = 4.2, h = 4.0, y = 0 }, nose = 8, canopy = { z = -12.5, len = 7, w = 2.4, h = 2.2, y = 2.0 },
  intake = "box", intakeZ = -4, intakeW = 2.6,
  wing = { xr = 2.2, zr0 = -4, zr1 = 9, xt = 13.2, zt0 = 6.5, zt1 = 9.5, y = 0.2, lerx = true },
  htail = { xr = 2.0, zr0 = 13, zr1 = 19, xt = 7.8, zt0 = 17, zt1 = 19.5, y = -0.3 },
  vt = { x = 0, zr0 = 9, zr1 = 19, zt0 = 16, zt1 = 19.5, h = 8.0, cant = 0 },
  eng = { { x = 0, y = 0, z = 21.2, r = 1.3 } },
  gear = { nose = { z = -8.5, len = 4.6 }, main = { x = 3.3, z = 2.0, len = 4.4 }, r = 1.0 },
  st = mirror({
    { name = "tip", pos = V(13.3, 0.0, 7.5), opts = { "aim9x", "aim120" } },
    { name = "outer", pos = V(10.6, -0.8, 6.5), opts = { "aim9x", "aim120" } },
    { name = "mid", pos = V(7.8, -1.1, 4.5), opts = { "aim120", "agm65", "agm88", "gbu12", "gbu38", "gbu31", "mk82" } },
    { name = "inner", pos = V(5.2, -1.3, 3.0), opts = { "tk370", "gbu12", "gbu31", "gbu38", "mk82", "agm65" } },
    { name = "ctr", pos = V(0, -2.7, 0), opts = { "tk370" } },
  }),
  presets = { preset("aa", { tip = "aim120", outer = "aim9x", mid = "aim120", inner = "tk370" }),
    preset("cas", { tip = "aim9x", outer = "aim120", mid = "agm65", inner = "gbu12", ctr = "tk370" }),
    preset("sead", { tip = "aim120", outer = "aim9x", mid = "agm88", inner = "tk370" }),
    preset("strike", { tip = "aim9x", outer = "aim120", mid = "gbu31", inner = "tk370", ctr = "tk370" }) } }
-- F-15C「鹰」：双发重型制空战斗机；原模型 mgg8 的「F-15A Eagle — USAF 76-0020, Duxford」（CC0，models/air/f15.glb，没有座舱内饰——
--   座舱用零件按 F-15C 的座舱拼：左上雷达垂直态势显示器 VSD、右上雷达告警 TEWS、左下武器控制面板，其余是机械表）；
--   全长 19.43 米、翼展 13.05 米、全高 5.63 米；M61A1 20 毫米炮 940 发（右翼根）；机身四角四个半埋挂点（AIM-120）、两个翼下挂架（两侧导轨各一枚）
D.f15 = { kind = "jet", cat = "jet", L = 54, W = 36.5, H = 15.8, gearH = 6.4, hp = 760, stall = 96, vMil = 340, vAB = 470, accel = 50, abAccel = 40,
  pitch = 44, roll = 200, yaw = 18, g = 9, flares = 30, gun = "m61", gunAmmo = 940, gunPos = V(4.6, 1.4, -2), ab = true,
  fus = { len = 52, w = 7.0, h = 4.6, y = 0 }, nose = 10, canopy = { z = -15.5, len = 8.5, w = 2.8, h = 2.4, y = 2.6 },
  intake = "box", intakeZ = -8, intakeW = 3.0, nacelle = { x = 2.8, w = 3.4, h = 3.6 },
  wing = { xr = 3.6, zr0 = -5, zr1 = 13, xt = 18.3, zt0 = 8.5, zt1 = 12.5, y = 0.6 },
  htail = { xr = 3.6, zr0 = 18, zr1 = 26, xt = 12.1, zt0 = 23, zt1 = 26.5, y = 0.2 },
  vt = { x = 3.3, zr0 = 15, zr1 = 25, zt0 = 22.5, zt1 = 26, h = 8.4, cant = 0 },
  eng = { { x = 1.6, y = 0, z = 27, r = 1.35 }, { x = -1.6, y = 0, z = 27, r = 1.35 } },
  gear = { nose = { z = -14, len = 5.6 }, main = { x = 3.9, z = 4, len = 5.4 }, r = 1.25 },
  st = mirror({
    { name = "railO", pos = V(10.6, -1.7, 4.5), opts = { "aim9x", "aim120" } },
    { name = "railI", pos = V(8.2, -1.7, 4.5), opts = { "aim120", "aim9x" } },
    { name = "pylon", pos = V(9.4, -2.6, 3.0), opts = { "tk370", "gbu12", "gbu31", "mk82" } },
    { name = "fusF", pos = V(3.9, -2.6, -5), opts = { "aim120" }, ej = true },   -- 机身半埋挂点：LAU-106 弹射挂架
    { name = "fusA", pos = V(3.9, -2.6, 9), opts = { "aim120" }, ej = true },
    { name = "ctr", pos = V(0, -3.2, 2), opts = { "tk370" } },
  }),
  presets = { preset("aa", { railO = "aim9x", railI = "aim120", fusF = "aim120", fusA = "aim120", ctr = "tk370" }),
    preset("beast", { railO = "aim9x", railI = "aim120", pylon = "tk370", fusF = "aim120", fusA = "aim120", ctr = "tk370" }),
    preset("strike", { railO = "aim9x", railI = "aim120", pylon = "gbu31", fusF = "aim120", fusA = "aim120" }) } }
-- F-14A「雄猫」：格鲁曼的双发双座变后掠翼舰载截击机（前座飞行员、后座雷达截击官 RIO）；原模型 Novia556 的「F-14A Tomcat」
--   （CC-BY，models/air/f14.glb，在飞行沙盒里用零件拼的，没有座舱内饰——座舱用零件按 F-14A 拼：前座平显、垂直显示器 VDI、水平态势 HSD，
--   后座一块圆的战术信息显示器 TID）；全长 19.1 米、翼展 19.55 米（展开）、全高 4.88 米；M61A1 20 毫米炮 675 发（机头左下）；
--   挂点：两个翼套挂架（AIM-9 + AIM-54 / AIM-7）、机腹隧道 4 个（AIM-54 托架或炸弹）、两个进气道下（副油箱）
D.f14 = { kind = "jet", cat = "jet", L = 53.5, W = 54.7, H = 13.7, gearH = 6.0, hp = 820, stall = 86, vMil = 320, vAB = 450, accel = 42, abAccel = 34,
  pitch = 40, roll = 170, yaw = 16, g = 7.5, flares = 30, gun = "m61", gunAmmo = 675, gunPos = V(-2.2, 1.0, -14), ab = true, carrier = true,
  fus = { len = 51, w = 7.6, h = 4.4, y = 0 }, nose = 10, canopy = { z = -15, len = 9.5, w = 2.8, h = 2.3, y = 2.4 }, twoSeat = true,
  intake = "box", intakeZ = -8, intakeW = 3.0, nacelle = { x = 3.6, w = 3.4, h = 3.6 },
  wing = { xr = 6.0, zr0 = -8, zr1 = 12, xt = 27.3, zt0 = 9, zt1 = 12.5, y = 0.6 },
  htail = { xr = 4.0, zr0 = 17, zr1 = 26, xt = 14.0, zt0 = 23, zt1 = 26.5, y = 0.0 },
  vt = { x = 3.8, zr0 = 14, zr1 = 24, zt0 = 22, zt1 = 25.5, h = 8.4, cant = 5 },
  eng = { { x = 2.8, y = 0, z = 26.5, r = 1.35 }, { x = -2.8, y = 0, z = 26.5, r = 1.35 } },
  gear = { nose = { z = -15, len = 5.4 }, main = { x = 7.0, z = 3.5, len = 5.2 }, r = 1.2, hook = 22 },
  st = mirror({
    { name = "gloveO", pos = V(6.6, -0.6, -1.0), opts = { "aim9x" } },
    { name = "gloveI", pos = V(5.6, -1.7, 0.5), opts = { "aim54", "aim120" } },
    { name = "tunF", pos = V(1.6, -2.7, -6), opts = { "aim54", "aim120", "gbu12", "mk82" }, ej = true },   -- 机腹通道托架：LAU-93 / LAU-92 弹射
    { name = "tunA", pos = V(1.6, -2.7, 6), opts = { "aim54", "aim120", "gbu12", "mk82" }, ej = true },
    { name = "duct", pos = V(4.2, -3.4, 2), opts = { "tk370" } },
  }),
  presets = { preset("phoenix", { gloveO = "aim9x", gloveI = "aim54", tunF = "aim54", tunA = "aim54" }),
    preset("aa", { gloveO = "aim9x", gloveI = "aim54", tunF = "aim120", tunA = "aim120", duct = "tk370" }),
    preset("strike", { gloveO = "aim9x", gloveI = "aim120", tunF = "gbu12", tunA = "gbu12", duct = "tk370" }) } }
D.mq9 = { kind = "jet", cat = "jet", L = 31, W = 56, H = 10.6, gearH = 5.4, hp = 360, stall = 48, vMil = 125, accel = 18, pitch = 24, roll = 65, yaw = 12, g = 3.5,
  flares = 0, drone = true, prop = true,
  fus = { len = 30, w = 3.4, h = 3.6, y = 0 }, nose = 5, sat = true,
  wing = { xr = 1.8, zr0 = -1.5, zr1 = 3.8, xt = 28, zt0 = 0.5, zt1 = 2.8, y = 0.8 },
  vtail = { z0 = 10, z1 = 14.5, h = 6, span = 6, angle = 45, inverted = true, ventral = true },
  eng = { { x = 0, y = 0, z = 15.2, r = 0.5, prop = 3.0 } },
  gear = { nose = { z = -10, len = 3.4 }, main = { x = 3.2, z = 1.0, len = 4.0 }, r = 0.8 },
  st = mirror({
    { name = "inner", pos = V(5.5, 0.0, 0.6), opts = { "gbu12", "gbu38", "agm114" }, n = N({ agm114 = 2 }) },
    { name = "outer", pos = V(10.5, 0.2, 0.6), opts = { "agm114", "gbu12", "gbu38" }, n = N({ agm114 = 2 }) },
  }),
  presets = { preset("hk", { inner = "gbu12", outer = "agm114" }), preset("at", { inner = "agm114", outer = "agm114" }) } }
D.b2 = { kind = "jet", cat = "jet", L = 59, W = 147, H = 14.5, gearH = 9.0, hp = 1400, stall = 85, vMil = 250, accel = 22, pitch = 14, roll = 40, yaw = 6, g = 2.5,
  flares = 0, bomber = true, stealth = true, flyingWing = true,
  fus = { len = 50, w = 22, h = 6.5, y = 1.0 }, nose = 10, canopy = { z = -18, len = 6, w = 6, h = 1.8, y = 3.9 },
  wing = { xr = 6.0, zr0 = -27, zr1 = 23, xt = 73.5, zt0 = 18, zt1 = 22.5, y = 0, saw = true },
  eng = { { x = 6.0, y = 2.2, z = 16, r = 1.4, flat = true }, { x = -6.0, y = 2.2, z = 16, r = 1.4, flat = true }, { x = 10.5, y = 1.8, z = 18, r = 1.4, flat = true },
    { x = -10.5, y = 1.8, z = 18, r = 1.4, flat = true } },
  gear = { nose = { z = -12, len = 6.5 }, main = { x = 13, z = 4, len = 6.4, bogie = true }, r = 1.6 },
  bays = { main = { z0 = -6, z1 = 8, w = 7.0, twin = 4.6 } },
  st = mirror({ { name = "bay", pos = V(4.6, -2.2, 1.0), bay = "main", opts = { "gbu31", "mk82" }, n = N({ gbu31 = 8, mk82 = 16 }) } }),
  presets = { preset("jdam", { bay = "gbu31" }), preset("mk82", { bay = "mk82" }) } }

---------------------------------------------------------------- 俄罗斯：米格-29、T-50、苏-57（用户 11-26：给了 bohmerang 的三个模型「原封不动导入」、「参数要跟现实中一样」）
--   原模型三个都放着起落架（另有一套收起时关着的舱门 GearUp），机身尺寸照原模型量的（tools/models/sf_air.py）；性能数值和别的飞机同一个比例尺：
--   推重比 → accel / abAccel，低空最大速度 → vMil / vAB（×2.25 是真速度），最大滚转率、过载、失速照公开资料
-- 苏-57（量产型，2020 年起交付）：长 20.1 米、翼展 14.1 米、高 4.6 米、翼面积 78.8 平方米；空重 18 吨、正常起飞 25 吨、最大 35 吨；
--   两台 AL-41F1（117 发动机）：军推 88.3 千牛、加力 142.2 千牛（正常起飞重量下推重比约 1.16），三元推力矢量（每个喷口 ±15°，左右喷口的偏转面斜着装：俯仰、偏航、滚转都管）；
--   最大速度 2 马赫（高空约 2135 公里 / 时）、不开加力超音速巡航约 1.3 马赫，升限 2 万米，过载 +9；GSh-30-1（9A1-4071K）30 毫米炮 150 发（右边前缘根部）；
--   两个前后排的主弹舱（各 2 枚 K-77M）、两个三角形侧弹舱（各 1 枚 R-74M2），翼下 6 个外挂点；雷达 N036（见 RADAR），光电 101KS-V
D.su57 = { kind = "jet", cat = "jet", L = 56, W = 39.5, H = 12.9, gearH = 6.9, hp = 760, stall = 92, vMil = 375, vAB = 475, accel = 54, abAccel = 40,
  pitch = 52, roll = 230, yaw = 26, g = 9, aoaMax = 28, flares = 64, gun = "gsh30", gunAmmo = 150, gunPos = V(2.8, 0.4, -11.2), ab = true, stealth = true, tvc = true,
  fus = { len = 53, w = 6.6, h = 4.4, y = 0 }, nose = 10, canopy = { z = -17.4, len = 6.7, w = 3.0, h = 2.4, y = 2.4 },
  intake = "box", intakeZ = -6, intakeW = 2.6,
  wing = { xr = 4.2, zr0 = -5.6, zr1 = 20.2, xt = 20.4, zt0 = 12.0, zt1 = 15.7, y = 0.2, lerx = true },
  htail = { xr = 5.9, zr0 = 15.5, zr1 = 25.4, xt = 14.5, zt0 = 22.5, zt1 = 25.4, y = 0.2 },
  vt = { x = 6.6, zr0 = 13, zr1 = 21.5, zt0 = 17.5, zt1 = 21.5, h = 6.4, cant = 26, allMove = true },
  eng = { { x = 4.1, y = 0.5, z = 24.3, r = 1.5 }, { x = -4.1, y = 0.5, z = 24.3, r = 1.5 } },
  gear = { nose = { z = -9.9, len = 5.5 }, main = { x = 7.3, z = 7.6, len = 5.5 }, r = 1.4 },
  -- 弹舱：两个主弹舱在两台发动机中间的龙骨下面前后排（各长约 4.4 米），侧弹舱在进气道外侧的翼根整流罩里
  bays = { main = { z0 = -5.0, z1 = 19.6, w = 2.8 }, sideR = { x = 5.6, z0 = -1.2, z1 = 4.6, w = 1.0 } },
  st = mirror({
    { name = "bayF", pos = V(1.0, -2.3, 1.1), bay = "main", opts = { "k77m" } },
    { name = "bayR", pos = V(1.0, -2.3, 13.4), bay = "main", opts = { "k77m" } },
    { name = "bayS", pos = V(5.6, -0.7, 1.7), bay = "sideR", opts = { "r74" } },
    { name = "wing", pos = V(11.2, -0.6, 7.0), opts = { "k77m", "r74" } },
  }),
  presets = { preset("aa", { bayF = "k77m", bayR = "k77m", bayS = "r74" }), preset("beast", { bayF = "k77m", bayR = "k77m", bayS = "r74", wing = "k77m" }) } }
-- T-50（苏-57 的原型机，2010 年首飞；用户给的「Su-57 Felon (P)」是 054 号，即 T-50-4，2012 年）：机体、发动机同量产型（AL-41F1），
--   雷达是试验阶段的 N036（见 RADAR.t50）；机头多一根长空速管
do
  local function cp(t)
    if type(t) ~= "table" or getmetatable(t) ~= nil then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = cp(v) end
    return o
  end
  D.t50 = cp(D.su57)
  D.t50.hp = 740
end
-- 米格-29（9.12，1983 年服役）：长 17.32 米（含空速管）、翼展 11.36 米、高 4.73 米、翼面积 38 平方米；空重 11 吨、正常起飞 15.3 吨、最大 18 吨；
--   两台 RD-33：军推 49.4 千牛、加力 81.4 千牛（正常起飞重量下推重比约 1.08）；最大速度 2.25 马赫（高空约 2400 公里 / 时）、海平面约 1500 公里 / 时，
--   升限 1.8 万米、爬升率约 330 米 / 秒，过载 +9（超音速 +7）；GSh-30-1 30 毫米炮 150 发（左边边条根部）；翼下 6 个挂点：内侧 R-27R、中间和外侧 R-73（或 R-60M）；
--   雷达 N019（见 RADAR）、光电 KOLS（激光测距 + 红外搜索跟踪）、头盔瞄准具「窄缝」（R-73 离轴发射）
D.mig29 = { kind = "jet", cat = "jet", L = 48.5, W = 31.8, H = 13.2, gearH = 6.3, hp = 640, stall = 95, vMil = 330, vAB = 480, accel = 46, abAccel = 40,
  pitch = 46, roll = 210, yaw = 18, g = 9, aoaMax = 26, flares = 60, gun = "gsh30", gunAmmo = 150, gunPos = V(-2.8, 0.1, -2.8), ab = true,
  fus = { len = 46, w = 5.4, h = 4.0, y = 0 }, nose = 9, canopy = { z = -9.6, len = 6.5, w = 2.3, h = 1.6, y = 2.0 },
  intake = "box", intakeZ = -1, intakeW = 2.4, nacelle = { x = 2.5, w = 2.8, h = 2.8 },
  wing = { xr = 4.8, zr0 = -3.0, zr1 = 12.9, xt = 15.6, zt0 = 11.0, zt1 = 13.5, y = -0.6, lerx = true },
  htail = { xr = 4.8, zr0 = 14.7, zr1 = 23.9, xt = 10.8, zt0 = 21.0, zt1 = 23.9, y = -1.7 },
  vt = { x = 5.0, zr0 = 13.5, zr1 = 20.7, zt0 = 18.5, zt1 = 21.2, h = 6.0, cant = 6 },
  eng = { { x = 2.4, y = -2.7, z = 19.6, r = 1.26 }, { x = -2.4, y = -2.7, z = 19.6, r = 1.26 } },
  gear = { nose = { z = -4.2, len = 5.0 }, main = { x = 4.5, z = 5.9, len = 5.0 }, r = 1.0 },
  st = mirror({
    -- own：挂在原模型自己的发射导轨 / 挂架下面（模型里有 APU-470 / APU-73 导轨、外侧挂架），不另画挂架；位置照模型量的（内侧导轨 |y| 2.37 米、
    --   中间 3.10 米、外侧挂架 3.76 米，前后在导轨中间）
    { name = "inner", pos = V(6.62, -2.0, 5.6), opts = { "r27r", "r73" }, own = true },
    { name = "mid", pos = V(8.68, -2.0, 7.48), opts = { "r73", "r27r" }, own = true },
    { name = "outer", pos = V(10.53, -1.9, 8.53), opts = { "r73" }, own = true },
  }),
  presets = { preset("aa", { inner = "r27r", mid = "r73", outer = "r73" }), preset("wvr", { inner = "r73", mid = "r73", outer = "r73" }) } }

-- 苏-35S（2014 年服役；用户 11-26 给的 bohmerang「Sukhoi Su-35 - Fighter Jet - Free」，原来借歼-11 的模型和性能）：长 21.9 米、翼展 15.3 米（带翼尖吊舱）、高 5.9 米、
--   翼面积 62 平方米；空重 19 吨、正常起飞 25.3 吨、最大 34.5 吨；两台 AL-41F1S（117S）：军推 86.3 千牛、加力 142 千牛（推重比约 1.15），推力矢量 ±15°（两个喷口的偏转面斜着装）；
--   最大速度 2.25 马赫（高空约 2400 公里 / 时）、海平面约 1400 公里 / 时，升限 1.8 万米，过载 +9；GSh-30-1 150 发；12 个挂点（翼尖是「希比内」电子战吊舱）；
--   雷达 N035（见 RADAR）、光电 OLS-35
D.su35 = { kind = "jet", cat = "jet", L = 61.3, W = 42.8, H = 16.5, gearH = 7.6, hp = 780, stall = 92, vMil = 345, vAB = 480, accel = 52, abAccel = 40,
  pitch = 50, roll = 220, yaw = 24, g = 9, aoaMax = 28, flares = 64, gun = "gsh30", gunAmmo = 150, gunPos = V(2.6, 0.6, -9), ab = true, tvc = true,
  fus = { len = 58, w = 5.0, h = 4.4, y = 0 }, nose = 11, canopy = { z = -16.6, len = 8.3, w = 2.3, h = 2.0, y = 2.0 },
  intake = "box", intakeZ = -4, intakeW = 3.0, nacelle = { x = 3.3, w = 3.4, h = 3.4 },
  wing = { xr = 4.0, zr0 = -8, zr1 = 13, xt = 20.3, zt0 = 9, zt1 = 14, y = 0.0, lerx = true },
  htail = { xr = 5.1, zr0 = 15.6, zr1 = 25.6, xt = 13.6, zt0 = 22.5, zt1 = 25.6, y = 0.1 },
  vt = { x = 6.0, zr0 = 13, zr1 = 20.7, zt0 = 17.3, zt1 = 20.7, h = 9.4, cant = 0 },
  eng = { { x = 3.3, y = 0.3, z = 23.6, r = 1.6 }, { x = -3.3, y = 0.3, z = 23.6, r = 1.6 } },
  gear = { nose = { z = -7.8, len = 7.3 }, main = { x = 6.1, z = 8.2, len = 7.3 }, r = 1.3 },
  st = mirror({
    -- 机翼下三个挂架是原模型自己的（own，|y| 3.50 / 4.63 / 6.29 米、前后在挂架中间）；翼尖是「希比内」电子战吊舱（模型自带），不挂弹
    { name = "outer", pos = V(17.6, -1.0, 12.3), opts = { "r73", "r74" }, own = true },
    { name = "mid", pos = V(12.96, -1.2, 8.7), opts = { "r77", "r27er", "r73", "kh29", "b250" }, n = N({ b250 = 2 }), own = true },
    { name = "inner", pos = V(9.8, -1.2, 7.28), opts = { "r77", "r27er", "kh29", "b250" }, n = N({ b250 = 2 }), own = true },
    { name = "duct", pos = V(2.6, -3.0, 2.0), opts = { "r77", "r27er" }, ej = true },
    { name = "ctr", pos = V(0, -2.6, -3.0), opts = { "r77", "b250" }, n = N({ b250 = 2 }), ej = true },
  }),
  presets = { preset("aa", { outer = "r74", mid = "r27er", inner = "r77", duct = "r77", ctr = "r77" }), preset("ag", { outer = "r74", mid = "kh29", inner = "kh29", duct = "r77", ctr = "b250" }) } }
-- 苏-25（1981 年服役，「白嘴鸦」）：用户 11-26 给的 Immersive3A「[PBR] Sukhoi Su-25」（CC-BY）：长 15.53 米、翼展 14.36 米、高 4.8 米、翼面积 30.1 平方米；
--   空重 9.8 吨、正常起飞 14.6 吨、最大 17.6 吨；两台 R-95Sh 涡喷（各 40.2 千牛，不带加力；推重比约 0.56）；最大速度约 950 公里 / 时（0.82 马赫），
--   升限 7000 米（空载 1 万米），过载 +6.5；座舱钛合金装甲浴盆；GSh-30-2 双管 30 毫米炮 250 发；翼下 10 个挂点（S-8 火箭、炸弹、Kh-25 / Kh-29、外侧 R-60M 自卫）；
--   没有雷达（机头是「枫叶」激光测距 / 指示器）；翼尖吊舱后面是开花式减速板；箔条 / 热焰弹 256 发（UV-26）
D.su25 = { kind = "jet", cat = "jet", L = 43.5, W = 40.2, H = 13.4, gearH = 5.5, hp = 1000, stall = 90, vMil = 320, accel = 36, pitch = 34, roll = 140, yaw = 16, g = 6.5,
  flares = 256, gun = "gsh302", gunAmmo = 250, gunPos = V(-1.1, -2.7, -12.6),
  fus = { len = 40, w = 4.6, h = 4.4, y = 0 }, nose = 8, canopy = { z = -10.7, len = 4.4, w = 2.6, h = 1.8, y = 2.4 },
  intake = "box", intakeZ = -2, intakeW = 2.2,
  wing = { xr = 2.8, zr0 = -3.0, zr1 = 6.6, xt = 20.3, zt0 = 3.6, zt1 = 6.6, y = 0 },
  htail = { xr = 0.8, zr0 = 13.4, zr1 = 18.4, xt = 6.7, zt0 = 16.0, zt1 = 18.4, y = 0.4 },
  vt = { x = 0, zr0 = 9.7, zr1 = 18.0, zt0 = 15.5, zt1 = 18.0, h = 7.4, cant = 0 },
  eng = { { x = 2.35, y = 0.4, z = 7.3, r = 0.9 }, { x = -2.35, y = 0.4, z = 7.3, r = 0.9 } },
  gear = { nose = { z = -8.4, len = 2.0 }, main = { x = 3.5, z = 1.4, len = 2.2 }, r = 1.1 },
  st = mirror({
    { name = "p1", pos = V(5.7, -0.8, -0.1), opts = { "kh29", "b250", "s8" }, own = true },
    { name = "p2", pos = V(8.0, -0.8, 0.6), opts = { "b250", "s8", "kh29" }, own = true },
    { name = "p3", pos = V(10.2, -0.8, 1.1), opts = { "s8", "b250" }, own = true },
    { name = "p4", pos = V(12.4, -0.8, 1.9), opts = { "s8", "b250" }, own = true },
    { name = "p5", pos = V(14.4, -0.8, 3.1), opts = { "r60" }, own = true },
  }),
  presets = { preset("cas", { p1 = "kh29", p2 = "b250", p3 = "s8", p4 = "s8", p5 = "r60" }), preset("bomb", { p1 = "b250", p2 = "b250", p3 = "b250", p4 = "b250", p5 = "r60" }) } }

-- 苏-27S（1985 年服役）：歼-11 就是照苏-27SK 造的，性能照抄歼-11（两台 AL-31F：军推 76.2 千牛、加力 122.6 千牛；正常起飞 23 吨；2.35 马赫；+9 g），
--   挂俄式的弹（R-73 / R-27R / R-27ER）、N001「剑」雷达；原模型借苏-35S 的（like：俄罗斯涂装和机徽；用户 11-26「为什么俄罗斯的飞机上会有中国的图标」——
--   原来借歼-11 的模型）。苏-35S 的模型喷口能偏，苏-27 没有推力矢量：AirModels 按 tvc 不偏（调节片照旧开合）
D.su27 = hv(D.j11, { like = "su35", flares = 96,
  st = mirror({
    { name = "tip", pos = V(19.3, -0.2, 11.5), opts = { "r73" } },
    { name = "outer", pos = V(17.6, -1.0, 12.3), opts = { "r73", "r27r" }, own = true },
    { name = "mid", pos = V(12.96, -1.2, 8.7), opts = { "r27r", "r27er", "r73", "b250" }, n = N({ b250 = 2 }), own = true },
    { name = "inner", pos = V(9.8, -1.2, 7.28), opts = { "r27er", "r27r", "b250" }, n = N({ b250 = 2 }), own = true },
    { name = "duct", pos = V(2.6, -3.0, 2.0), opts = { "r27r", "r27er" }, ej = true },
    { name = "ctr", pos = V(0, -2.6, -3.0), opts = { "r27er", "b250" }, n = N({ b250 = 2 }), ej = true },
  }),
  presets = { preset("aa", { tip = "r73", outer = "r73", mid = "r27r", inner = "r27er", duct = "r27r", ctr = "r27er" }),
    preset("strike", { tip = "r73", outer = "r73", mid = "b250", inner = "b250", duct = "r27r", ctr = "b250" }) } })

---------------------------------------------------------------- 补默认值

-- 对空雷达（用户 11-24 夜：「战雷……不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」）：
--   kind pd 脉冲多普勒（有源相控阵也是）：能下视，但会滤掉相对地面的径向速度太小的目标——目标把你放在 3 点 / 9 点方向侧着飞（置零、3/9 机动），
--     径向速度掉到 notch（格 / 秒）以下就从雷达屏上消失、锁不住，已经锁着的丢锁；
--   kind pulse 脉冲（老雷达）：不怕置零，但往下看（目标比自己低、背景是地面）有地杂波，低空的目标看不见；
--   range 搜索距离、lock 能锁定（单目标跟踪 STT）的距离（格）；az / el 方位、俯仰扫描 ±度。没写的飞机没有对空雷达（A-10、轰炸机、无人机、直升机）
--   客户端 Radar.lua 画雷达屏（B 显：横轴方位、竖轴距离）、Fly.lua 雷达弹只能锁雷达看得见的；服务器 Air.lua 的雷达弹按发射机的雷达跟踪（数据链）飞、
--   近了自己开导引头（act），也会被置零、箔条骗
local function radar(name, kind, range, lock, az, el, notch)
  return { name = name, kind = kind, range = range, lock = lock, az = az, el = el, notch = notch }
end
local RADAR = {
  j20 = radar("KLJ-5 有源相控阵", "pd", 16000, 13000, 60, 45, 45),
  j35 = radar("有源相控阵", "pd", 14000, 11500, 60, 45, 45),
  j15t = radar("有源相控阵", "pd", 14000, 11500, 60, 45, 45),
  j16 = radar("有源相控阵", "pd", 15000, 12000, 60, 45, 45),
  j11 = radar("1474 型脉冲多普勒", "pd", 11000, 9000, 60, 40, 60),
  j10 = radar("KLJ-10 有源相控阵", "pd", 13000, 10500, 60, 45, 45),
  j36 = radar("有源相控阵", "pd", 17000, 14000, 60, 45, 40),
  j8 = radar("SL-8A 脉冲", "pulse", 8000, 6000, 45, 30, 0),
  f35 = radar("AN/APG-81 有源相控阵", "pd", 15000, 12000, 60, 45, 45),
  f22 = radar("AN/APG-77 有源相控阵", "pd", 17000, 14000, 60, 45, 40),
  f16 = radar("AN/APG-68 脉冲多普勒", "pd", 11000, 9000, 60, 40, 60),
  f15 = radar("AN/APG-63 脉冲多普勒", "pd", 13000, 10500, 60, 40, 60),
  f14 = radar("AN/AWG-9 脉冲多普勒", "pd", 18000, 14000, 65, 40, 60),
  -- 苏-57 的 Sh121 雷达组：N036「松鼠」有源相控阵——机头 N036-1-01（X 波段，1514 个收发组件）+ 两侧的 N036B-1-01 侧视阵（方位往两边多看一截：az 75）
  --   + 前缘涡流控制板里的 L 波段阵；公开说法对大目标约 400 公里、战斗机大小的目标约 160 公里，跟踪 60 个、同时攻击 16 个（和 APG-77 一档）
  su57 = radar("N036 松鼠 有源相控阵", "pd", 16500, 13500, 75, 45, 40),
  t50 = radar("N036 有源相控阵（试验型）", "pd", 15500, 12500, 75, 45, 42),   -- 原型机（T-50-3 起才装上雷达）：软件、功率还没到量产型
  -- 米格-29（9.12）的 N019「宝石」脉冲多普勒（RLPK-29）：对战斗机迎头约 70 公里、尾追约 35 公里，跟踪 10 个、攻击 1 个；方位 ±67°；下视、抗干扰都弱
  mig29 = radar("N019 宝石 脉冲多普勒", "pd", 9500, 7500, 67, 40, 70),
  -- 苏-35S 的 N035「雪豹-E」无源相控阵：对 3 平方米的目标迎头约 350～400 公里，跟踪 30 个、攻击 8 个；电扫 ±60°，再加液压转台整个天线转到 ±120°（az 90 折中）
  su35 = radar("N035 雪豹-E 无源相控阵", "pd", 17500, 14000, 90, 60, 55),
  -- 苏-27S 的 N001「剑」脉冲多普勒（卡塞格伦天线）：对战斗机迎头约 80～100 公里、跟踪一个打一个；视场 ±60°
  su27 = radar("N001 剑 脉冲多普勒", "pd", 10000, 8000, 60, 40, 70),
}
-- 雷达弹（主动雷达）：act 离目标多近自己开导引头（之前按发射机雷达的跟踪走数据链）、notch 导引头的置零门限（格 / 秒）
local ARH = { pl15 = { act = 2800, notch = 50 }, aim120 = { act = 2600, notch = 50 }, aim54 = { act = 3200, notch = 60 }, pl12 = { act = 2200, notch = 55 },
  k77m = { act = 3000, notch = 45 }, r77 = { act = 2600, notch = 55 } }   -- K-77M 有源相控阵导引头：开机远、不怕置零；R-27R 是半主动，不在这里
for wid, a in pairs(ARH) do
  local w = AirDefs.W[wid]
  if w then w.act, w.notch = a.act, a.notch end
end

-- 照真实的速度、射程（用户 11-25「全部都做」⑩，B 挑刺 9：原来照 MWT 的尺度——歼-20 开加力最快约 600 公里 / 时、霹雳-15 约 270 米 / 秒、
--   射程一公里多）：上面的数是原来手调的（各型之间的比例照旧），这里统一放大——喷气机军推 / 加力速度 ×2.25（低空 1300 公里 / 时上下）、失速 ×1.7、
--   直升机最大平飞 ×2.4（约 290 公里 / 时）；空空、空地导弹速度 ×3.5（雷达弹约 3 马赫）、射程 ×6、能飞多久 ×1.8、发动机烧的时间 ×1.3
--   （转弯按过载 w.g 限，快了转弯半径自然变大）；火箭弹速度、射程 ×2.5；机载雷达搜索 / 锁定距离、雷达弹开导引头的距离 ×2.5。
--   作战区 ±Map.PLAY（沙海 3.7 万格，约 ±13 公里）够喷气机按真速度飞；推重比（accel）不变（A 的飞行手感）
AirDefs.REAL = { jet = 2.25, stall = 1.7, heli = 2.4, mslSpeed = 3.5, mslRange = 6, mslLife = 1.8, mslBurn = 1.3, rkt = 2.5, radar = 2.5 }
do
  local K = AirDefs.REAL
  for _, d in pairs(D) do
    if d.kind == "jet" then
      for _, f in ipairs({ "vMil", "vAB" }) do if d[f] then d[f] = d[f] * K.jet end end
      if d.stall then d.stall = d.stall * K.stall end   -- 失速只放大 1.7 倍（歼-20 约 230 公里 / 时）：再大了进近太快，1.3 公里的跑道停不下
    elseif d.kind == "heli" then
      if d.vMax then d.vMax = d.vMax * K.heli end
    end
  end
  for _, w in pairs(AirDefs.W) do
    if (w.kind == "aam" or w.kind == "agm") and not w.nuke and not w.hyper then
      w.speed = w.speed * K.mslSpeed
      w.range = w.range * K.mslRange
      if w.life then w.life = w.life * K.mslLife end
      if w.burn then w.burn = w.burn * K.mslBurn end
      if w.act then w.act = w.act * K.radar end
    elseif w.kind == "rkt" then
      w.speed = w.speed * K.rkt
      w.range = w.range * K.rkt
    end
  end
  for _, r in pairs(RADAR) do r.range, r.lock = r.range * K.radar, r.lock * K.radar end
end

for id, d in pairs(D) do
  d.id = id
  d.air = true
  d.radar = d.radar or RADAR[id]
  if d.kind == "jet" then
    d.vMax = d.vAB or d.vMil
    d.vRot = d.stall * 1.5   -- 抬头离地的速度（原来 1.08 倍失速速度，四五十米就飞起来了；用户：跑道非常短）
    d.landMax = d.stall * 1.9   -- 着陆最快多少（再快就是撞地）；比离地速度快一点，正常进近不至于判成撞地
    d.seats = d.seats or 1
  else
    d.vMax = d.vMax or 90
  end
  d.gunAmmo = d.gunAmmo or 0
  d.flares = d.flares or 0
  d.hitbox = (d.kind == "heli") and V(math.max(d.W, 8), d.H * 0.8, d.L * 0.8) or V(d.W * 0.7, d.H * 0.75, d.L * 0.9)
  for i, s in ipairs(d.st or {}) do s.i = i end
end
-- 能挂副油箱的挂点（照真飞机：侧卫系、A-10 机翼内侧，歼-20 / 歼-35 / F-35 翼下，察打无人机内侧，直升机短翼）；左右成对的挂点共用一张 opts 表，只加一次
local TANKS = { j15t = { inner = "tk800" }, j16 = { inner = "tk800" }, j20 = { wing = "tk800" }, j35 = { wingI = "tk800" }, gj2 = { inner = "tk800" },
  a10c = { inner = "tk370" }, f35 = { wingI = "tk370" }, mq9 = { inner = "tk370" }, z10 = { inner = "tkh" }, z20 = { stub = "tkh" }, ah64e = { inner = "tk230" }, uh60 = { stub = "tk230" } }
for id, map in pairs(TANKS) do
  local d = D[id]
  for _, st in ipairs((d and d.st) or {}) do
    local wid = map[st.name]
    if wid and st.opts and not table.find(st.opts, wid) then table.insert(st.opts, wid) end
  end
end

-- 攻方舰队的甲板（和 World.fleet 拼的一样大：甲板面高 top）：飞机能停在上面、从上面起飞
--   航母（福建舰，用户 11-21：航母不够真）照原模型量出来的甲板轮廓（CarrierMeta.outline：舰艏窄、斜角甲板往左舷伸出去、舰尾收窄），
--   W 只是最宽处；没有元数据时退回长方形
AirDefs.DECKS = { carrier = { L = 620, W = 160, top = 30.5 }, lhd = { L = 480, W = 94, top = 26.5 }, lst = { L = 300, W = 60, top = 18.5 } }
local CM = nil
pcall(function() CM = require(script.Parent:WaitForChild("CarrierMeta", 3)) end)
AirDefs.CM = CM
-- 航母甲板在 lz 处的左舷边、右舷边（相对甲板中心，格）；不在甲板长度里返回 nil
function AirDefs.cvEdge(lz)
  local o = CM and CM.outline
  if not o then
    if math.abs(lz) > 310 then return nil end
    return -60, 60
  end
  if lz < o[1][1] - 8 or lz > o[#o][1] + 6 then return nil end
  if lz <= o[1][1] then return o[1][2], o[1][3] end
  for i = 1, #o - 1 do
    local a, b = o[i], o[i + 1]
    if lz <= b[1] then
      local t = (lz - a[1]) / (b[1] - a[1])
      return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
    end
  end
  return o[#o][2], o[#o][3]
end
-- (x, z) 在不在这艘船的甲板上
local function onShip(s, K, x, z)
  if s.kind == "carrier" then
    local r = s.rot or 0
    local dx, dz = x - s.x, z - s.z
    local lx, lz = dx * math.cos(r) - dz * math.sin(r), dx * math.sin(r) + dz * math.cos(r)   -- 转到甲板坐标（rot 绕 Y）
    local xl, xr = AirDefs.cvEdge(lz)
    return xl ~= nil and lx >= xl and lx <= xr
  end
  return math.abs(x - s.x) < K.W / 2 and math.abs(z - s.z) < K.L / 2
end
-- (x, z) 处能落地的面多高：地形（海上是海面 0）、甲板
function AirDefs.ground(Map, x, z)
  local g = Map.ground(x, z)
  for _, s in ipairs(Map.FLEET or {}) do
    local K = AirDefs.DECKS[s.kind]
    if K and onShip(s, K, x, z) then g = math.max(g, K.top) end
  end
  return g
end
-- 航母：三条弹射器（舰艏两条、舰腰一条在斜角甲板左边）、拦阻索区；坐标相对航母甲板中心（舰艏朝 −Z），a 是往左舷偏的角度
--   照福建舰原模型（tools/models/fujian.py 量的）：舰艏两条白线就是两条弹射轨道（右边那条往外斜 5°），后端前面是偏流板；
--   舰腰那条在斜角甲板左边、偏流板后面（原模型没画轨道，World.lua 补）；斜角甲板中线往左偏 9.4°，拦阻索在着舰区后段
--   停机位在右舷舰岛后面（Depots.lua）：自己滑到弹射器起点，对正了就卡上，油门推满按空格弹射；着舰放尾钩，落在拦阻索区就被拉停
AirDefs.CATS = { { x = 34.6, z = -94.4, len = 212, a = math.rad(5.09) }, { x = -15, z = -94, len = 212, a = 0 }, { x = -59, z = 112, len = 190, a = 0 } }
AirDefs.WIRES = { z0 = 175, z1 = 255, x = 0, a = math.rad(9.4), n = 4, hw = 30 }   -- hw：拦阻索区中线两边各多宽（着舰区两条红线之间约 47 格）
AirDefs.TAXI = 28   -- 甲板上没上弹射器时最快滑多快（格 / 秒）
function AirDefs.carrierCF(Map)
  for _, s in ipairs(Map.FLEET or {}) do
    if s.kind == "carrier" then return CFrame.new(s.x, AirDefs.DECKS.carrier.top, s.z) * CFrame.Angles(0, s.rot or 0, 0) end
  end
  return nil
end
-- 第 i 条弹射器：起点（甲板面上）、方向、长度
function AirDefs.cat(Map, i)
  local base = AirDefs.carrierCF(Map)
  local c = AirDefs.CATS[i]
  if not base or not c then return nil end
  return (base * CFrame.new(c.x, 0, c.z)).Position, base:VectorToWorldSpace(Vector3.new(-math.sin(c.a), 0, -math.cos(c.a))), c.len
end
-- (x, z) 在不在拦阻索区（着舰区后段：顺着斜角甲板中线，中线两边各 hw 格）
function AirDefs.inWires(Map, x, z)
  local base = AirDefs.carrierCF(Map)
  if not base then return false end
  local Wd = AirDefs.WIRES
  local l = base:PointToObjectSpace(Vector3.new(x, base.Position.Y, z))
  local xc = Wd.x + (l.Z - (Wd.z0 + Wd.z1) / 2) * math.tan(Wd.a)   -- 中线往舰尾偏右舷（斜角甲板往左前方斜出去）
  return l.Z > Wd.z0 and l.Z < Wd.z1 and math.abs(l.X - xc) < (Wd.hw or 30)
end
-- 在不在甲板上
function AirDefs.onDeck(Map, x, z)
  for _, s in ipairs(Map.FLEET or {}) do
    local K = AirDefs.DECKS[s.kind]
    if K and onShip(s, K, x, z) then return s.kind end
  end
  return nil
end

function AirDefs.get(id) return D[id] end
function AirDefs.isAir(id) return D[id] ~= nil end

-- 一个挂点挂某种武器能挂几枚
function AirDefs.count(s, wid)
  local w = AirDefs.W[wid]
  if not w then return 0 end
  if w.kind == "rkt" then return w.tubes end
  return (s.n and s.n[wid]) or 1
end
-- 按挂点名字展开预设（左右成对的挂点同名）
function AirDefs.presetLoad(d, key)
  local p
  for _, x in ipairs(d.presets or {}) do if x.key == key then p = x end end
  p = p or (d.presets and d.presets[1])
  local out = {}
  for i, s in ipairs(d.st or {}) do
    local w = p and p.map[s.name]
    out[i] = (w and table.find(s.opts, w)) and w or false
  end
  return out
end
-- 检查客户端发来的挂载：每个挂点只能挂它能挂的；不对的换成空
function AirDefs.cleanLoad(d, load)
  local out = {}
  for i, s in ipairs(d.st or {}) do
    local w = (type(load) == "table") and load[i] or nil
    out[i] = (type(w) == "string" and table.find(s.opts, w)) and w or false
  end
  return out
end
-- 挂载里有哪几种武器（按出现顺序；1 号武器位是航炮）
function AirDefs.groups(d, load)
  local out, seen = {}, {}
  if d.gun then table.insert(out, d.gun) seen[d.gun] = true end
  for _, s in ipairs(d.st or {}) do
    local w = load[s.i]
    if w and not seen[w] and not (AirDefs.W[w] and AirDefs.W[w].kind == "tank") then table.insert(out, w) seen[w] = true end   -- 副油箱不是武器
  end
  return out
end

---------------------------------------------------------------- 燃油（用户：增加油量这个东西）

-- 内油：按「军用推力（油门 100、不开加力）一直开能飞几秒」算，直升机按满速爬升算（一局 30 分钟：战斗机满内油军推八九分钟、
--   一直开加力四分钟、巡航十七分钟上下，一局里要回去加一两次油；侧卫系、F-35 内油多一点，无人机、轰炸机能飞一整局）
local FUEL = { j20 = 520, j35 = 480, j15t = 540, j16 = 600, j11 = 640, j10 = 460, j36 = 760, j8 = 520, j6 = 380, f22 = 500, f35 = 500, f16 = 460, f15 = 620, f14 = 700,
  a10c = 600, h6k = 1300, b2 = 1600,
  gj11 = 1200, gj2 = 2400, mq9 = 2400, z10 = 600, ah64e = 600, z20 = 720, uh60 = 720, ch47 = 900 }
function AirDefs.fuelCap(d) return d.fuel or FUEL[d.id] or 360 end
-- 每秒烧掉内油的几成：油门越小越省（慢车也烧一点），加力推满是军用推力的 2.2 倍；
--   直升机：旋翼没转起来不烧，地上慢车三成，天上悬停六成，爬升（col 是升降杆 −1～1）、飞得快再多烧（spd 是速度 / 最大速度）
function AirDefs.burn(d, thr, col, rpm, spd, ground)
  local cap = AirDefs.fuelCap(d)
  if d.kind == "heli" then
    if (rpm or 0) < 30 then return 0 end
    if ground then return 0.3 / cap end
    return (0.6 + 0.25 * math.clamp(col or 0, 0, 1) + 0.15 * math.clamp(spd or 0, 0, 1)) / cap
  end
  local t = math.clamp(thr or 0, 0, 130)
  if t > 100 then return (1 + 1.2 * (t - 100) / 30) / cap end
  return (0.12 + 0.88 * (t / 100) ^ 1.6) / cap
end
-- 巡航（油门六成 / 直升机平飞七成速度）带 f 成油（内油 + 副油箱，默认满内油）能飞几分钟：选机型的卡片、挂载界面上写
function AirDefs.fuelMin(d, f)
  local r = AirDefs.burn(d, 60, 0, 100, 0.7, false)
  return math.floor((f or 1) / math.max(r, 1e-6) / 60 + 0.5)
end
-- 出发时能选的内油（几成）：少带油轻、加速快，多带飞得久
AirDefs.FUEL_OPTS = { 0.25, 0.5, 0.75, 1 }
function AirDefs.cleanFuel(f)
  f = tonumber(f)
  if not f or f ~= f then return 1 end
  return math.clamp(f, 0.25, 1)
end
-- 重量（相对一半内油、不挂副油箱）：内油大约是战斗机起飞重量的四分之一，副油箱连油带箱子再重一成；直升机油占得少
function AirDefs.heavy(d, fuel, fuelX)
  local k = (d.kind == "heli") and 0.2 or 0.35
  return (1 + k * ((fuel or 0.5) + 1.1 * (fuelX or 0))) / (1 + k * 0.5)
end
-- 一套挂载里副油箱加几成油、加几成阻力
function AirDefs.tankFuel(d, load)
  local f, drag, n = 0, 0, 0
  for i, s in ipairs(d.st or {}) do
    local w = load and load[i] and AirDefs.W[load[i]]
    if w and w.kind == "tank" then
      local c = AirDefs.count(s, load[i])
      f += w.fuel * c
      drag += w.drag * c
      n += c
    end
  end
  return f, drag, n
end

return AirDefs
