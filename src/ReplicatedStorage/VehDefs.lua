-- Roblox全面大战场——地面载具的型号数据（服务器、客户端共用）：尺寸、速度、炮塔、武器、车轮 / 负重轮、烟幕弹发射筒、瞄准镜
--   单位：格（1 米约 2.8 格，和 Roblox 的人一样比例）。车的坐标系：原点在车底中心（着地），X 右、Y 上、−Z 朝前
--   服务器的命中盒是 W × H × L 的方块，中心在原点上 H/2；客户端按 arch（tracked 履带 / wheeled 轮式）和各项参数拼零件模型
--   炮塔：pivot 是转轴（相对车底），trav 每秒转几度，elev 俯仰范围（度）；炮：gun.pivot 是耳轴（相对炮塔转轴），len 长、cal 粗
--   烟幕弹：smoke.banks 每组一个发射架（相对炮塔转轴的位置、朝向角 yaw 度——0 朝前、正数往右），n 管，各管在架上扇形张开、仰 35°
local VehDefs = {}
local V = Vector3.new

-- 武器（载具用）：kind shell 有弹道的炮弹（打到就炸）、gun 机枪（直射判定）、arty 曲射（准星下的地面）、
--   rate 两发间隔（秒）、mag 一个弹匣 / 弹舱、reload 换弹、reserve 备弹（不算弹匣里的）；speed 弹速（格 / 秒）、drop 下坠（重力倍数）
--   坦克炮（gun125 / gun120 / gun105）真正打出去按 Ballistics.lua 的弹种（初速、阻力、真实重力）；这里的 speed、drop 是默认弹种的值（别处估飞行时间用）
VehDefs.W = {
  gun125 = { kind = "shell", dmg = 640, speed = 4872, drop = 0.14, splash = 6, rate = 6.5, mag = 1, reload = 0, reserve = 30, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun120 = { kind = "shell", dmg = 640, speed = 4354, drop = 0.14, splash = 6, rate = 6.0, mag = 1, reload = 0, reserve = 30, range = 3000,
    vs = { inf = 0.7, light = 1.3, armor = 1, air = 0.8, ship = 0.7, fort = 1.2 }, fx = "tank", cal = 0.42 },
  gun105 = { kind = "shell", dmg = 480, speed = 4214, drop = 0.14, splash = 6, rate = 5.0, mag = 1, reload = 0, reserve = 36, range = 2600,
    vs = { inf = 0.8, light = 1.3, armor = 0.9, air = 0.8, ship = 0.6, fort = 1.1 }, fx = "tank", cal = 0.36 },
  ac30 = { kind = "shell", dmg = 60, speed = 1150, drop = 0.2, splash = 4, rate = 0.19, mag = 50, reload = 4.5, reserve = 400, range = 2000,
    vs = { inf = 1, light = 1, armor = 0.22, air = 1.4, ship = 0.35, fort = 0.6 }, fx = "ac", cal = 0.2 },
  ac35 = { kind = "shell", dmg = 46, speed = 1300, drop = 0.15, splash = 5, rate = 0.07, mag = 120, reload = 5, reserve = 600, range = 2400,
    vs = { inf = 0.8, light = 0.8, armor = 0.1, air = 2.4, ship = 0.25, fort = 0.35 }, fx = "ac", cal = 0.2 },
  vulcan = { kind = "shell", dmg = 26, speed = 1200, drop = 0.2, splash = 2.5, rate = 0.035, mag = 300, reload = 6, reserve = 1200, range = 1600,
    vs = { inf = 1, light = 0.6, armor = 0.05, air = 2.0, ship = 0.15, fort = 0.25 }, fx = "ac", cal = 0.14 },
  -- 车顶 GAU-8 加特林附件（坦克改装，TankMods.OPT.gau8）：30 毫米，一秒二十发，2048 发
  gau8 = { kind = "shell", dmg = 52, speed = 1250, drop = 0.18, splash = 3.5, rate = 0.05, mag = 512, reload = 6, reserve = 1536, range = 2200,
    vs = { inf = 1, light = 1.1, armor = 0.32, air = 1.6, ship = 0.4, fort = 0.9 }, fx = "ac", cal = 0.22 },
  coax = { kind = "gun", dmg = 24, rate = 0.08, mag = 200, reload = 5, reserve = 2000, range = 900, spread = 0.45,
    vs = { inf = 1, light = 0.15, armor = 0, air = 0.1, ship = 0, fort = 0.04 }, fx = "lmg" },
  hmg = { kind = "gun", dmg = 40, rate = 0.11, mag = 100, reload = 5, reserve = 900, range = 1200, spread = 0.5,
    vs = { inf = 1, light = 0.5, armor = 0.04, air = 0.4, ship = 0.05, fort = 0.12 }, fx = "lmg" },
  how155 = { kind = "arty", dmg = 340, splash = 26, rate = 7, mag = 1, reload = 0, reserve = 40, minR = 300, maxR = 3600, flight = 6,
    vs = { inf = 1, light = 1, armor = 0.6, air = 0, ship = 0.5, fort = 1.2 } },
  mlrs = { kind = "arty", dmg = 180, splash = 22, rate = 0.45, mag = 12, reload = 25, reserve = 24, minR = 500, maxR = 4000, flight = 7, scatter = 40,
    vs = { inf = 1, light = 1, armor = 0.45, air = 0, ship = 0.4, fort = 1 } },
}
-- 烟幕弹：每次齐射一组，落点约 30 格外，烟团半径 ~20 格、持续 30 秒
VehDefs.SMOKE = { range = 32, r = 20, life = 30, salvos = 2, reload = 12 }
-- 726 气垫艇：攻方不会游的车在登陆平台旁站在艇上生成，开车的人连艇一起开（服务器 Armor、客户端 Drive 共用）：
--   y 艇身中心高、deck 车底的高度、speed 水上最快（格 / 秒）、size 艇身、hp
VehDefs.LCAC = { y = 2.2, deck = 3.0, speed = 75, size = Vector3.new(28, 6, 48), hp = 1800 }   -- 75 格 / 秒：从登陆平台到海滩四十来秒

local D = {}
VehDefs.D = D

-- 履带车的公共部分（负重轮、履带）；轮式车的车轴
local function tracked(t)
  t.arch = "tracked"
  t.wheels = nil
  return t
end
local function wheeled(t)
  t.arch = "wheeled"
  return t
end

---------------------------------------------------------------- 坦克

D.ztz99a = tracked({ cat = "tank", L = 22, W = 10.2, H = 7.4, hullH = 4.2, clear = 1.3, speed = 34, accel = 10, turn = 36,
  rw = { n = 6, r = 1.15, x = 4.0, z0 = -7.6, z1 = 7.2 }, era = true, skirt = true,
  turret = { pivot = V(0, 4.2, 0.6), size = V(7.4, 2.3, 8.2), style = "wedge", trav = 42, elev = { -6, 18 }, bustle = 2.2 },
  gun = { pivot = V(0, 0.9, -3.4), len = 14.5, cal = 0.46, brake = false, fume = true }, coax = V(1.1, 0.9, -3.6),
  sight = V(-1.9, 2.1, -2.6), cupola = V(1.7, 2.3, 0.6),   -- 车顶车长舱口一挺手动的 12.7 毫米重机枪（用户 11-21 晚：照真车加回，元数据 rws.mk = "manual"）
  smoke = { banks = { { at = V(3.3, 1.5, -1.6), yaw = 40 }, { at = V(-3.3, 1.5, -1.6), yaw = -40 } }, n = 4 },
  weapons = { "gun125", "coax" } })
D.ztz96 = tracked({ cat = "tank", L = 20.5, W = 9.8, H = 7.0, hullH = 4.0, clear = 1.3, speed = 33, accel = 9, turn = 36,
  rw = { n = 6, r = 1.1, x = 3.85, z0 = -7.0, z1 = 6.7 }, era = true, skirt = true,
  turret = { pivot = V(0, 4.0, 0.4), size = V(6.8, 2.2, 7.0), style = "round", trav = 38, elev = { -6, 16 }, bustle = 1.2 },
  gun = { pivot = V(0, 0.9, -3.0), len = 14, cal = 0.45, fume = true }, coax = V(1.0, 0.9, -3.2),
  sight = V(-1.7, 2.0, -2.2), cupola = V(1.6, 2.2, 0.4),
  smoke = { banks = { { at = V(3.1, 1.4, -1.2), yaw = 40 }, { at = V(-3.1, 1.4, -1.2), yaw = -40 } }, n = 4 },
  weapons = { "gun125", "coax" } })
D.m1a2 = tracked({ cat = "tank", L = 23, W = 10.2, H = 7.6, hullH = 4.2, clear = 1.4, speed = 35, accel = 10, turn = 35,
  rw = { n = 7, r = 1.05, x = 4.0, z0 = -7.8, z1 = 7.6 }, era = false, skirt = true, tusk = false,
  turret = { pivot = V(0, 4.2, 0.9), size = V(7.8, 2.4, 9.4), style = "abrams", trav = 42, elev = { -9, 20 }, bustle = 3.0 },
  gun = { pivot = V(0, 0.95, -4.0), len = 14, cal = 0.44 }, coax = V(1.2, 0.95, -4.1),
  sight = V(1.75, 2.2, -2.8), cupola = V(1.8, 2.4, 0.8), citv = V(-1.4, 2.6, -0.4),   -- 主瞄准镜在炮右边（炮长坐右边）
  -- 主瞄准镜的倍率（Drive.lua 的视场档）：SEPv2 第二代前视红外热像宽视场 3 / 6 倍、窄视场 13 / 25 / 50 倍；昼光通道 3 / 10 倍
  sightZoom = { day = { 3, 10 }, th = { 3, 6, 13, 25, 50 } },
  smoke = { banks = { { at = V(3.5, 1.6, -2.4), yaw = 35 }, { at = V(-3.5, 1.6, -2.4), yaw = -35 } }, n = 6 },
  weapons = { "gun120", "coax" } })
D.m1a1 = tracked({ cat = "tank", L = 22.5, W = 10.2, H = 7.4, hullH = 4.2, clear = 1.4, speed = 35, accel = 10, turn = 35,
  rw = { n = 7, r = 1.05, x = 4.0, z0 = -7.6, z1 = 7.4 }, era = false, skirt = true,
  turret = { pivot = V(0, 4.2, 0.9), size = V(7.6, 2.3, 9.0), style = "abrams", trav = 40, elev = { -9, 20 }, bustle = 2.6 },
  gun = { pivot = V(0, 0.95, -3.9), len = 14, cal = 0.44 }, coax = V(1.2, 0.95, -4.0),
  sight = V(1.75, 2.1, -2.7), cupola = V(1.8, 2.3, 0.8),
  smoke = { banks = { { at = V(3.4, 1.5, -2.3), yaw = 35 }, { at = V(-3.4, 1.5, -2.3), yaw = -35 } }, n = 6 },
  sightZoom = { day = { 3, 10 }, th = { 3, 10 } },   -- M1A1 主瞄准镜：昼光 3 / 10 倍，热像（第一代）宽 3 倍、窄 10 倍
  weapons = { "gun120", "coax" } })
D.m10 = tracked({ cat = "tank", L = 22, W = 9.6, H = 7.4, hullH = 4.3, clear = 1.4, speed = 37, accel = 11, turn = 40,
  rw = { n = 6, r = 1.05, x = 3.8, z0 = -7.2, z1 = 7.0 }, skirt = true,
  turret = { pivot = V(0, 4.3, 0.6), size = V(7.0, 2.3, 7.6), style = "wedge", trav = 40, elev = { -8, 20 }, bustle = 2.0 },
  gun = { pivot = V(0, 0.9, -3.4), len = 12, cal = 0.38, brake = true, fume = true }, coax = V(1.1, 0.9, -3.5),
  sight = V(1.7, 2.1, -2.4), cupola = V(1.7, 2.3, 0.6),
  smoke = { banks = { { at = V(3.2, 1.5, -1.8), yaw = 35 }, { at = V(-3.2, 1.5, -1.8), yaw = -35 } }, n = 4 },
  weapons = { "gun105", "coax" } })

---------------------------------------------------------------- 装甲车（履带）

D.zbd05 = tracked({ cat = "apc", L = 26, W = 9.6, H = 7.0, hullH = 4.6, clear = 1.2, speed = 40, accel = 11, turn = 40, amphib = true, boat = true,
  rw = { n = 7, r = 0.95, x = 3.8, z0 = -9.2, z1 = 9.4 }, skirt = false,
  turret = { pivot = V(0, 4.6, -1.6), size = V(4.6, 1.6, 4.8), style = "ifv", trav = 60, elev = { -8, 50 } },
  gun = { pivot = V(0, 0.6, -2.2), len = 7.5, cal = 0.24, brake = true }, coax = V(0.8, 0.6, -2.3),
  sight = V(-1.4, 1.5, -1.8),
  smoke = { banks = { { at = V(2.2, 0.9, -1.6), yaw = 30 }, { at = V(-2.2, 0.9, -1.6), yaw = -30 } }, n = 4 },
  weapons = { "ac30", "coax" }, seats = 6 })
D.ztd05 = tracked({ cat = "apc", L = 26, W = 9.6, H = 7.2, hullH = 4.6, clear = 1.2, speed = 38, accel = 10, turn = 38, amphib = true, boat = true,
  rw = { n = 7, r = 0.95, x = 3.8, z0 = -9.2, z1 = 9.4 },
  turret = { pivot = V(0, 4.6, -0.6), size = V(6.0, 2.0, 6.0), style = "wedge", trav = 40, elev = { -6, 18 }, bustle = 1.2 },
  gun = { pivot = V(0, 0.8, -2.8), len = 11.5, cal = 0.36, brake = true, fume = true }, coax = V(0.9, 0.8, -2.9),
  sight = V(-1.6, 1.8, -2.0),
  smoke = { banks = { { at = V(2.8, 1.2, -1.6), yaw = 35 }, { at = V(-2.8, 1.2, -1.6), yaw = -35 } }, n = 4 },
  weapons = { "gun105", "coax" } })
D.m2a3 = tracked({ cat = "apc", L = 19, W = 9.4, H = 8.4, hullH = 5.6, clear = 1.4, speed = 36, accel = 10, turn = 40,
  rw = { n = 6, r = 0.95, x = 3.7, z0 = -6.8, z1 = 6.8 }, skirt = true,
  turret = { pivot = V(0, 5.6, -0.4), size = V(5.0, 1.8, 5.2), style = "ifv", trav = 60, elev = { -9, 55 }, tow = true },
  gun = { pivot = V(0, 0.7, -2.4), len = 6.5, cal = 0.24 }, coax = V(0.9, 0.7, -2.5),
  sight = V(-1.5, 1.7, -1.8),
  sightZoom = { day = { 4, 12 }, th = { 4, 12, 24 } },   -- M2A3 炮长的综合瞄准具（IBAS）：昼光 4 / 12 倍，热像 4 / 12 倍 + 电子放大 24 倍
  smoke = { banks = { { at = V(2.4, 1.0, -2.2), yaw = 30 }, { at = V(-2.4, 1.0, -2.2), yaw = -30 } }, n = 4 },
  weapons = { "ac30", "coax" }, seats = 6 })
D.m1150 = tracked({ cat = "apc", L = 24, W = 10.2, H = 6.6, hullH = 4.4, clear = 1.4, speed = 32, accel = 9, turn = 34, plow = true,
  rw = { n = 7, r = 1.05, x = 4.0, z0 = -7.8, z1 = 7.6 }, skirt = true,
  turret = { pivot = V(0, 4.4, 1.6), size = V(2.2, 1.0, 2.2), style = "rws", trav = 70, elev = { -10, 50 } },
  gun = { pivot = V(0, 0.6, -0.6), len = 4.6, cal = 0.2 }, sight = V(0, 1.4, -0.8),
  smoke = { banks = { { at = V(1.4, 0.4, -0.6), yaw = 35 }, { at = V(-1.4, 0.4, -0.6), yaw = -35 } }, n = 4 },
  weapons = { "hmg" } })

---------------------------------------------------------------- 装甲车（轮式）

D.zsl92b = wheeled({ cat = "apc", L = 21, W = 8.4, H = 7.6, hullH = 5.2, clear = 1.7, speed = 46, accel = 12, turn = 48, amphib = true, boat = true,
  axles = { -6.0, -1.6, 5.4 }, steer = 1, wr = 1.55, ww = 1.1, wx = 3.5,
  turret = { pivot = V(0, 5.2, -0.6), size = V(4.2, 1.5, 4.2), style = "ifv", trav = 60, elev = { -8, 55 } },
  gun = { pivot = V(0, 0.6, -2.0), len = 7.0, cal = 0.22, brake = true }, coax = V(0.8, 0.6, -2.1),
  sight = V(-1.3, 1.4, -1.6),
  smoke = { banks = { { at = V(2.1, 0.9, -1.2), yaw = 35 }, { at = V(-2.1, 0.9, -1.2), yaw = -35 } }, n = 4 },
  weapons = { "ac30", "coax" }, seats = 6 })
D.ptl02 = wheeled({ cat = "apc", L = 22, W = 8.6, H = 7.4, hullH = 5.0, clear = 1.7, speed = 46, accel = 12, turn = 46,
  axles = { -6.4, -2.0, 5.4 }, steer = 1, wr = 1.55, ww = 1.1, wx = 3.6,
  turret = { pivot = V(0, 5.0, 0.4), size = V(5.6, 1.8, 5.8), style = "wedge", trav = 40, elev = { -6, 18 }, bustle = 1.0 },
  gun = { pivot = V(0, 0.7, -2.6), len = 11.5, cal = 0.36, brake = true, fume = true }, coax = V(0.9, 0.7, -2.7),
  sight = V(-1.5, 1.6, -2.0),
  smoke = { banks = { { at = V(2.7, 1.0, -1.6), yaw = 35 }, { at = V(-2.7, 1.0, -1.6), yaw = -35 } }, n = 4 },
  weapons = { "gun105", "coax" } })
D.stryker = wheeled({ cat = "apc", L = 22, W = 8.4, H = 7.8, hullH = 5.8, clear = 1.6, speed = 46, accel = 12, turn = 44,
  axles = { -6.8, -3.2, 2.6, 6.2 }, steer = 2, wr = 1.45, ww = 1.0, wx = 3.5,
  turret = { pivot = V(0, 5.8, 0.4), size = V(2.4, 1.1, 2.4), style = "rws", trav = 70, elev = { -12, 55 } },
  gun = { pivot = V(0, 0.6, -0.6), len = 5.0, cal = 0.2 }, sight = V(0, 1.4, -0.9),
  smoke = { banks = { { at = V(3.6, -0.2, -6.0), yaw = 30, hull = true }, { at = V(-3.6, -0.2, -6.0), yaw = -30, hull = true } }, n = 4 },
  weapons = { "hmg" }, seats = 8 })
D.m1117 = wheeled({ cat = "apc", L = 17, W = 7.6, H = 7.4, hullH = 5.4, clear = 1.6, speed = 50, accel = 13, turn = 52,
  axles = { -4.8, 4.6 }, steer = 1, wr = 1.6, ww = 1.0, wx = 3.1,
  turret = { pivot = V(0, 5.4, 0.6), size = V(3.2, 1.4, 3.2), style = "ifv", trav = 70, elev = { -8, 45 } },
  gun = { pivot = V(0, 0.6, -1.4), len = 4.6, cal = 0.2 }, sight = V(-1.0, 1.3, -1.2),
  smoke = { banks = { { at = V(1.6, 0.7, -1.4), yaw = 35 }, { at = V(-1.6, 0.7, -1.4), yaw = -35 } }, n = 4 },
  weapons = { "hmg" }, seats = 4 })
D.hmmwv = wheeled({ cat = "apc", L = 14, W = 6.4, H = 6.4, hullH = 4.6, clear = 1.4, speed = 58, accel = 15, turn = 60, light = true,
  axles = { -4.0, 4.2 }, steer = 1, wr = 1.3, ww = 0.9, wx = 2.6,
  turret = { pivot = V(0, 4.6, 0.6), size = V(2.4, 0.9, 2.4), style = "ring", trav = 90, elev = { -10, 40 } },
  gun = { pivot = V(0, 0.9, -0.6), len = 4.2, cal = 0.18 }, sight = V(0, 1.7, 0.4),
  smoke = { banks = { { at = V(1.9, 0.3, -2.4), yaw = 35, hull = true }, { at = V(-1.9, 0.3, -2.4), yaw = -35, hull = true } }, n = 2 },
  weapons = { "hmg" }, seats = 4 })
D.jltv = wheeled({ cat = "apc", L = 17, W = 7.0, H = 7.2, hullH = 5.2, clear = 1.6, speed = 56, accel = 14, turn = 56, light = true,
  axles = { -4.8, 4.8 }, steer = 1, wr = 1.45, ww = 1.0, wx = 2.9,
  turret = { pivot = V(0, 5.2, 0.4), size = V(2.2, 1.0, 2.2), style = "rws", trav = 80, elev = { -10, 50 } },
  gun = { pivot = V(0, 0.6, -0.6), len = 4.4, cal = 0.18 }, sight = V(0, 1.4, -0.8),
  smoke = { banks = { { at = V(1.4, 0.4, -0.6), yaw = 35 }, { at = V(-1.4, 0.4, -0.6), yaw = -35 } }, n = 2 },
  weapons = { "hmg" }, seats = 4 })

---------------------------------------------------------------- 防空

D.pgz07 = tracked({ cat = "aa", L = 22, W = 9.6, H = 9.6, hullH = 4.4, clear = 1.3, speed = 34, accel = 9, turn = 36,
  rw = { n = 6, r = 1.05, x = 3.8, z0 = -7.4, z1 = 7.2 }, skirt = true,
  turret = { pivot = V(0, 4.4, 0.8), size = V(5.6, 2.6, 6.2), style = "spaag", trav = 90, elev = { -5, 85 }, radar = true, twin = 3.4 },
  gun = { pivot = V(0, 1.3, -1.4), len = 9.5, cal = 0.24 }, sight = V(0, 2.2, -2.6),
  smoke = { banks = { { at = V(2.7, 0.8, -2.8), yaw = 35 }, { at = V(-2.7, 0.8, -2.8), yaw = -35 } }, n = 4 },
  weapons = { "ac35" } })
D.m163 = tracked({ cat = "aa", L = 15, W = 8.2, H = 8.0, hullH = 5.4, clear = 1.2, speed = 36, accel = 10, turn = 42,
  rw = { n = 5, r = 0.95, x = 3.4, z0 = -5.6, z1 = 5.6 },
  turret = { pivot = V(0, 5.4, 1.4), size = V(3.4, 1.4, 3.4), style = "vulcan", trav = 80, elev = { -5, 80 } },
  gun = { pivot = V(0, 0.9, -1.0), len = 5.4, cal = 0.3, gatling = true }, sight = V(-1.0, 1.8, -0.4),
  smoke = { banks = { { at = V(3.2, -1.4, -6.4), yaw = 30, hull = true }, { at = V(-3.2, -1.4, -6.4), yaw = -30, hull = true } }, n = 4 },
  weapons = { "vulcan" } })
D.pgl625 = wheeled({ cat = "aa", L = 24, W = 8.4, H = 9.6, hullH = 5.6, clear = 1.8, speed = 44, accel = 11, turn = 40, truck = true,
  axles = { -7.6, -3.8, 5.6 }, steer = 1, wr = 1.55, ww = 1.1, wx = 3.4,
  turret = { pivot = V(0, 5.6, 2.4), size = V(4.6, 2.2, 4.6), style = "spaag", trav = 90, elev = { -5, 85 }, radar = true, twin = 2.8 },
  gun = { pivot = V(0, 1.1, -1.2), len = 7.4, cal = 0.22 }, sight = V(0, 2.0, -2.0),
  smoke = { banks = { { at = V(2.3, 0.6, -2.4), yaw = 35 }, { at = V(-2.3, 0.6, -2.4), yaw = -35 } }, n = 4 },
  weapons = { "ac35" } })
D.ld2000 = wheeled({ cat = "aa", L = 30, W = 8.6, H = 10.4, hullH = 5.8, clear = 1.9, speed = 40, accel = 9, turn = 34, truck = true,
  axles = { -10.6, -6.6, 3.4, 7.2 }, steer = 2, wr = 1.65, ww = 1.15, wx = 3.5,
  turret = { pivot = V(0, 5.8, 4.6), size = V(4.0, 2.6, 4.0), style = "vulcan", trav = 90, elev = { -5, 85 }, radar = true },
  gun = { pivot = V(0, 1.3, -1.2), len = 6.0, cal = 0.36, gatling = true }, sight = V(-1.2, 2.2, -1.0),
  smoke = { banks = { { at = V(3.6, -1.6, -11.4), yaw = 30, hull = true }, { at = V(-3.6, -1.6, -11.4), yaw = -30, hull = true } }, n = 4 },
  weapons = { "vulcan" } })
D.mshorad = wheeled({ cat = "aa", L = 22, W = 8.4, H = 9.0, hullH = 5.8, clear = 1.6, speed = 46, accel = 12, turn = 44,
  axles = { -6.8, -3.2, 2.6, 6.2 }, steer = 2, wr = 1.45, ww = 1.0, wx = 3.5,
  turret = { pivot = V(0, 5.8, 0.6), size = V(4.0, 1.8, 4.2), style = "ifv", trav = 80, elev = { -8, 70 }, pods = true },
  gun = { pivot = V(0, 0.7, -2.0), len = 6.4, cal = 0.22 }, sight = V(-1.3, 1.6, -1.6),
  smoke = { banks = { { at = V(3.6, -0.2, -6.0), yaw = 30, hull = true }, { at = V(-3.6, -0.2, -6.0), yaw = -30, hull = true } }, n = 4 },
  weapons = { "ac30" } })
D.cram = wheeled({ cat = "aa", L = 19, W = 8.0, H = 9.6, hullH = 4.4, clear = 1.6, speed = 30, accel = 7, turn = 30, truck = true,
  axles = { -5.4, -2.0, 5.4 }, steer = 1, wr = 1.5, ww = 1.0, wx = 3.2,
  turret = { pivot = V(0, 4.4, 3.0), size = V(3.6, 2.4, 3.6), style = "vulcan", trav = 100, elev = { -5, 85 }, dome = true },
  gun = { pivot = V(0, 1.2, -1.2), len = 6.0, cal = 0.3, gatling = true }, sight = V(-1.0, 2.0, -0.6),
  smoke = { banks = { { at = V(3.4, -0.8, -7.4), yaw = 30, hull = true }, { at = V(-3.4, -0.8, -7.4), yaw = -30, hull = true } }, n = 2 },
  weapons = { "vulcan" } })

---------------------------------------------------------------- 火炮

D.plz07 = tracked({ cat = "arty", L = 22, W = 9.6, H = 9.0, hullH = 4.4, clear = 1.3, speed = 32, accel = 8, turn = 34,
  rw = { n = 6, r = 1.0, x = 3.8, z0 = -7.4, z1 = 7.2 },
  turret = { pivot = V(0, 4.4, 2.2), size = V(7.2, 3.0, 8.4), style = "sph", trav = 25, elev = { -3, 65 } },
  gun = { pivot = V(0, 1.4, -4.0), len = 15, cal = 0.42, brake = true, fume = true }, sight = V(-2.4, 2.8, -3.0),
  smoke = { banks = { { at = V(3.4, 1.4, -3.4), yaw = 35 }, { at = V(-3.4, 1.4, -3.4), yaw = -35 } }, n = 4 },
  weapons = { "how155" } })
D.m109a7 = tracked({ cat = "arty", L = 24, W = 10.2, H = 9.4, hullH = 4.2, clear = 1.4, speed = 30, accel = 8, turn = 32,
  rw = { n = 7, r = 1.0, x = 4.0, z0 = -7.8, z1 = 7.6 },
  turret = { pivot = V(0, 4.2, 2.8), size = V(8.4, 3.4, 10.4), style = "sph", trav = 22, elev = { -3, 70 } },
  gun = { pivot = V(0, 1.6, -5.0), len = 17, cal = 0.44, brake = true, fume = true }, sight = V(-2.8, 3.0, -3.6),
  smoke = { banks = { { at = V(4.0, 1.6, -4.4), yaw = 35 }, { at = V(-4.0, 1.6, -4.4), yaw = -35 } }, n = 4 },
  weapons = { "how155" } })
D.m270 = tracked({ cat = "arty", L = 20, W = 9.4, H = 8.2, hullH = 4.4, clear = 1.4, speed = 32, accel = 8, turn = 34,
  rw = { n = 6, r = 1.0, x = 3.7, z0 = -6.8, z1 = 6.8 }, cab = true,
  turret = { pivot = V(0, 4.4, 2.6), size = V(5.8, 2.6, 9.0), style = "launcher", trav = 30, elev = { 0, 60 } },
  gun = { pivot = V(0, 0.4, 0), len = 0, cal = 0 }, sight = V(0, -0.6, -8.6),
  smoke = { banks = { { at = V(3.4, -1.4, -8.6), yaw = 30, hull = true }, { at = V(-3.4, -1.4, -8.6), yaw = -30, hull = true } }, n = 4 },
  weapons = { "mlrs" } })

-- 爱国者（只打飞机；在有飞机之前不给选）
D.patriot = wheeled({ cat = "aa", L = 28, W = 8.4, H = 10, hullH = 4.4, clear = 1.8, speed = 34, accel = 8, turn = 32, truck = true, needsAir = true,
  axles = { -9.6, -5.8, 6.2, 9.6 }, steer = 1, wr = 1.6, ww = 1.1, wx = 3.4,
  turret = { pivot = V(0, 4.4, 3.0), size = V(6.0, 3.0, 11), style = "launcher", trav = 30, elev = { 0, 38 } },
  gun = { pivot = V(0, 0.4, 0), len = 0, cal = 0 }, sight = V(0, -0.4, -12),
  smoke = { banks = { { at = V(3.4, -0.4, -13), yaw = 30, hull = true }, { at = V(-3.4, -0.4, -13), yaw = -30, hull = true } }, n = 2 },
  weapons = {} })

-- 每个型号补上默认值、名字
for id, d in pairs(D) do
  d.id = id
  d.seats = d.seats or 1
  d.travel = d.travel or ((d.arch == "wheeled") and 0.75 or 0.55)   -- 悬架行程（上下各多少格）
  d.rev = d.rev or d.speed * 0.4
  if d.arch == "tracked" then d.rw.y = d.rw.y or d.rw.r end
end

-- 有原模型的型号（ImportedMeta：网页版装备模型原样转的，真实尺寸）：炮塔转轴、炮耳轴、炮口位置照原模型——
--   炮弹从看得见的炮口出去、炮长瞄准镜跟着真炮塔；不管导没导入都一样（服务器和客户端算出来一致）
do
  local ok, IM = pcall(function()
    local m = script and script.Parent and script.Parent:FindFirstChild("ImportedMeta")
    return m and require(m) or nil
  end)
  if ok and type(IM) == "table" and IM.alias and IM.m then
    for id, key in pairs(IM.alias) do
      local d, info = D[id], IM.m[key]
      if d and info and (info.tur or info.gun) then
        -- 型号表原来的转轴、炮长留着：没导入原模型时零件拼的炮塔、炮还按它摆（不然炮塔离开车体顶，C-RAM、斯特赖克高出 2 格）
        d.turret.pivot0 = d.turret.pivot
        if d.gun then d.gun.pivot0, d.gun.len0 = d.gun.pivot, d.gun.len end
        -- 原模型没有单独的炮塔（爱国者只有会俯仰的发射架）：转轴照型号表，耳轴照原模型（客户端 VehModels 也是这么摆的）
        local tur = info.tur and V(info.tur[1], info.tur[2], info.tur[3]) or d.turret.pivot
        d.turret.pivot = tur   -- 瞄准镜、烟幕弹发射架都是相对炮塔转轴的，跟着挪
        if info.gun then
          d.gun.pivot = V(info.gun[1], info.gun[2], info.gun[3]) - tur
          if info.muz and info.muz > 1 then d.gun.len = info.muz end
        end
        -- 炮长主瞄准镜、并列机枪口照原模型（用户：观瞄系统位置要对）：瞄准镜视角从模型上那个镜头看出去
        if info.sight then d.sight = V(info.sight[1], info.sight[2], info.sight[3]) - tur end
        if info.coax then d.coax = V(info.coax[1], info.coax[2], info.coax[3]) - tur end
        -- 遥控武器站（M1A2 车长位的 CROWS + M2）：底座跟着炮塔转、自己再转，M2 自己俯仰；机枪那一栏从并列机枪换成它的 12.7 毫米机枪
        --   （用户：机枪也要能转动、开火位置和枪口对上、弹道顺着枪管）
        if info.rws and info.rws.p and info.rws.g then
          local rp = V(info.rws.p[1], info.rws.p[2], info.rws.p[3])
          local rg = V(info.rws.g[1], info.rws.g[2], info.rws.g[3])
          d.rws = { pivot = rp - tur, gun = rg - rp, len = info.rws.muz or 2.5, trav = 120, rate = 90, elev = { -20, 60 }, mk = info.rws.mk }
          if info.rws.mk == "manual" then   -- 手动的车长重机枪（99A 的 12.7 毫米，真车上还有一挺 7.62 并列机枪）：并列机枪留着，第 3 栏是车顶重机枪
            table.insert(d.weapons, "hmg")
          else
            for i, wid in ipairs(d.weapons) do
              if wid == "coax" then d.weapons[i] = "hmg" end
            end
          end
        end
        d.model = key
      end
    end
  end
end

-- 零件拼的坦克（没有原模型：M10）：车长位上一个会转的遥控武器站（用户 11-19：坦克的机枪要能转，开火位置要在机枪）——
--   机枪那一栏从并列机枪（主炮旁边）换成它的 12.7 毫米机枪；有原模型的坦克在元数据里给（tools/models/vehrws.py）
for _, d in pairs(D) do
  if d.cat == "tank" and not d.rws and not d.model and d.cupola and not d.noRoofMg then
    local top = (d.turret and d.turret.size and d.turret.size.Y) or 2.3
    d.rws = { pivot = V(d.cupola.X, top, d.cupola.Z), gun = V(0, 0.62, -0.45), len = 2.45, trav = 120, rate = 90, elev = { -15, 55 }, mk = "rws" }
    for i, wid in ipairs(d.weapons) do
      if wid == "coax" then d.weapons[i] = "hmg" end
    end
  end
end

-- 用户 11-22：「坦克不要弄哪个机枪」——主战坦克（cat = "tank"）不要机枪：并列机枪、车顶的遥控武器站 / 手动重机枪都去掉，只剩主炮
--   （机器人开的坦克打步兵也用主炮）；步战车、轻型车、防空车照旧。想加回来把 VehDefs.TANK_MG 改成 true
VehDefs.TANK_MG = false
if not VehDefs.TANK_MG then
  for _, d in pairs(D) do
    if d.cat == "tank" then
      d.rws, d.noRoofMg = nil, true
      local keep = {}
      for _, wid in ipairs(d.weapons or {}) do
        if wid ~= "coax" and wid ~= "hmg" then table.insert(keep, wid) end
      end
      d.weapons = keep
    end
  end
end

function VehDefs.get(id) return D[id] end

-- 炮塔、炮的坐标系：base 是车底（着地中心）的 CFrame
function VehDefs.turretCF(d, base, yaw)
  return base * CFrame.new(d.turret.pivot) * CFrame.Angles(0, -math.rad(yaw or 0), 0)
end
function VehDefs.gunCF(d, base, yaw, pitch)
  return VehDefs.turretCF(d, base, yaw) * CFrame.new(d.gun.pivot) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
end
-- 遥控武器站：底座跟炮塔转（yaw）再自己转（my，度，往右为正，同炮塔），M2 俯仰（mp，度，抬头为正）
function VehDefs.rwsCF(d, base, yaw, my, mp)
  local R = d.rws
  return VehDefs.turretCF(d, base, yaw) * CFrame.new(R.pivot) * CFrame.Angles(0, -math.rad(my or 0), 0) * CFrame.new(R.gun)
    * CFrame.Angles(math.rad(mp or 0), 0, 0)
end
-- 遥控武器站要转到多少才对着 target（世界坐标）：返回 my、mp（夹在俯仰范围里）
function VehDefs.rwsAim(d, base, yaw, target)
  local R = d.rws
  local piv = VehDefs.turretCF(d, base, yaw) * CFrame.new(R.pivot)
  local rel = piv:PointToObjectSpace(target)
  local my = math.deg(math.atan2(rel.X, -rel.Z))
  local horiz = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
  local mp = math.deg(math.atan2(rel.Y - R.gun.Y, math.max(horiz, 1)))
  return my, math.clamp(mp, R.elev[1], R.elev[2])
end
-- 炮口（主炮）；coax 并列机枪口；rws 遥控武器站的枪口（my、mp 是它的转角）
function VehDefs.muzzle(d, base, yaw, pitch, which, my, mp)
  if which == "rws" and d.rws then
    return VehDefs.rwsCF(d, base, yaw, my, mp) * CFrame.new(0, 0, -d.rws.len)
  end
  if which == "coax" and d.coax then
    local t = VehDefs.turretCF(d, base, yaw) * CFrame.new(d.coax) * CFrame.Angles(math.rad(pitch or 0), 0, 0)
    return t * CFrame.new(0, 0, -1.2)
  end
  return VehDefs.gunCF(d, base, yaw, pitch) * CFrame.new(0, 0, -(d.gun.len > 0 and d.gun.len or 2))
end
-- 这件武器从哪个口出去：遥控站的 12.7 毫米机枪 → rws；别的机枪 → 并列机枪口；主炮 → nil
function VehDefs.mgWhich(d, wid)
  local w = VehDefs.W[wid]
  if not w or w.kind ~= "gun" then return nil end
  if wid == "hmg" and d.rws then return "rws" end
  return d.coax and "coax" or nil
end
-- 烟幕弹发射筒：返回 { { pos, dir }, … }（世界坐标）；装在炮塔上的随炮塔转，hull 的装在车体上
function VehDefs.smokeTubes(d, base, yaw)
  local out = {}
  local S = d.smoke
  if not S then return out end
  local tcf = VehDefs.turretCF(d, base, yaw)
  for _, b in ipairs(S.banks) do
    local frame = (b.hull and (base * CFrame.new(0, d.hullH, 0)) or tcf) * CFrame.new(b.at)
    for i = 1, S.n do
      local fan = (S.n > 1) and ((i - 1) / (S.n - 1) - 0.5) or 0
      local yaw2 = math.rad(b.yaw + fan * 40 * (b.yaw >= 0 and 1 or -1))
      local local_ = CFrame.Angles(0, -yaw2, 0) * CFrame.Angles(math.rad(35), 0, 0)
      local cf = frame * CFrame.new(fan * 0.9, (i % 2) * 0.35, 0) * local_
      table.insert(out, { pos = cf.Position, dir = cf.LookVector })
    end
  end
  return out
end

return VehDefs
