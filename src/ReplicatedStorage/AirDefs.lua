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
  gau8 = { kind = "gun", rate = 0.017, dmg = 22, speed = 1900, range = 2000, splash = 3, cal = 0.22,                      -- GAU-8 30 毫米贫铀穿甲弹
    vs = { inf = 1, light = 1.2, armor = 0.55, air = 1.4, ship = 0.5, fort = 0.7 } },
  m230 = { kind = "gun", rate = 0.095, dmg = 42, speed = 1500, range = 1600, splash = 4, cal = 0.2, turret = true,       -- M230 30 毫米链式炮（机头炮塔）
    vs = { inf = 1, light = 1.1, armor = 0.25, air = 1.2, ship = 0.3, fort = 0.6 } },
  zh23 = { kind = "gun", rate = 0.1, dmg = 38, speed = 1500, range = 1500, splash = 3.5, cal = 0.18, turret = true,      -- 直-10 23 毫米炮塔
    vs = { inf = 1, light = 1.1, armor = 0.22, air = 1.2, ship = 0.3, fort = 0.6 } },
  m134 = { kind = "gun", rate = 0.025, dmg = 9, speed = 1700, range = 1100, splash = 0, cal = 0.08, door = true,          -- 舱门机枪
    vs = { inf = 1, light = 0.3, armor = 0.01, air = 0.5, ship = 0.02, fort = 0.05 } },

  pl10 = { kind = "aam", seeker = "ir", dmg = 520, splash = 14, speed = 640, range = 1900, lockTime = 1.0, cone = 45, turn = 75, burn = 3.5, life = 6.5, vs = VS_AAM,
    shape = { L = 8.2, d = 0.45, fin = 1.0 } },
  pl15 = { kind = "aam", seeker = "radar", dmg = 560, splash = 16, speed = 760, range = 3800, lockTime = 2.0, cone = 22, turn = 55, burn = 5, life = 8.5, vs = VS_AAM,
    shape = { L = 11.2, d = 0.58, fin = 1.1 } },
  aim9x = { kind = "aam", seeker = "ir", dmg = 520, splash = 14, speed = 640, range = 1900, lockTime = 1.0, cone = 45, turn = 75, burn = 3.5, life = 6.5, vs = VS_AAM,
    shape = { L = 8.4, d = 0.36, fin = 0.8 } },
  aim120 = { kind = "aam", seeker = "radar", dmg = 560, splash = 16, speed = 760, range = 3800, lockTime = 2.0, cone = 22, turn = 55, burn = 5, life = 8.5, vs = VS_AAM,
    shape = { L = 10.2, d = 0.5, fin = 1.0 } },
  ty90 = { kind = "aam", seeker = "ir", dmg = 340, splash = 10, speed = 480, range = 1300, lockTime = 0.9, cone = 30, turn = 60, burn = 3, life = 5.5, vs = VS_AAM,
    shape = { L = 5.3, d = 0.25, fin = 0.6 } },
  aim92 = { kind = "aam", seeker = "ir", dmg = 340, splash = 10, speed = 480, range = 1300, lockTime = 0.9, cone = 30, turn = 60, burn = 3, life = 5.5, vs = VS_AAM,
    shape = { L = 4.5, d = 0.2, fin = 0.5 } },

  akd10 = { kind = "agm", dmg = 900, splash = 10, speed = 380, range = 2400, lockTime = 1.2, cone = 25, turn = 40, burn = 6, life = 9, vs = VS_AGM,
    shape = { L = 5.0, d = 0.5, fin = 0.7 } },
  agm114 = { kind = "agm", dmg = 900, splash = 10, speed = 380, range = 2400, lockTime = 1.2, cone = 25, turn = 40, burn = 6, life = 9, vs = VS_AGM,
    shape = { L = 4.5, d = 0.5, fin = 0.7 } },
  kd88 = { kind = "agm", dmg = 1400, splash = 22, speed = 520, range = 4200, lockTime = 1.6, cone = 18, turn = 25, burn = 9, life = 12, vs = VS_AGM,
    shape = { L = 13, d = 1.0, fin = 1.6, wing = 2.6 } },
  agm65 = { kind = "agm", dmg = 1150, splash = 14, speed = 480, range = 3000, lockTime = 1.4, cone = 20, turn = 30, burn = 6, life = 10, vs = VS_AGM,
    shape = { L = 7.0, d = 0.85, fin = 1.4 } },

  ls6 = { kind = "bomb", guided = true, dmg = 1500, splash = 32, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 10.8, d = 1.0, fin = 1.0, wing = 3.6 } },
  gbu12 = { kind = "bomb", guided = true, dmg = 1300, splash = 30, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 9.2, d = 0.9, fin = 1.2 } },
  gbu31 = { kind = "bomb", guided = true, dmg = 2600, splash = 48, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 10.6, d = 1.4, fin = 1.6 } },
  mk82 = { kind = "bomb", dmg = 1100, splash = 30, vs = VS_BOMB, shape = { L = 6.4, d = 0.75, fin = 1.0 } },
  b250 = { kind = "bomb", dmg = 1150, splash = 30, vs = VS_BOMB, shape = { L = 5.6, d = 0.95, fin = 1.0 } },

  hydra = { kind = "rkt", dmg = 230, splash = 12, speed = 760, range = 1800, rate = 0.11, tubes = 19, vs = VS_RKT, shape = { L = 4.6, d = 1.1 } },

  pl12 = { kind = "aam", seeker = "radar", dmg = 540, splash = 15, speed = 720, range = 2800, lockTime = 1.6, cone = 25, turn = 50, burn = 4.5, life = 7.5, vs = VS_AAM,
    shape = { L = 10.4, d = 0.57, fin = 1.0 } },
  yj91 = { kind = "agm", arm = true, dmg = 1000, splash = 14, speed = 560, range = 3800, lockTime = 1.4, cone = 25, turn = 30, burn = 8, life = 11,
    vs = { inf = 0.6, light = 1.8, armor = 0.8, air = 0.2, ship = 1.1, fort = 1.6 }, shape = { L = 13.2, d = 1.0, fin = 1.6 } },
  agm88 = { kind = "agm", arm = true, dmg = 950, splash = 13, speed = 580, range = 3600, lockTime = 1.4, cone = 25, turn = 30, burn = 8, life = 11,
    vs = { inf = 0.6, light = 1.8, armor = 0.8, air = 0.2, ship = 1.1, fort = 1.6 }, shape = { L = 11.6, d = 0.71, fin = 1.3 } },
  gbu32 = { kind = "bomb", guided = true, dmg = 1700, splash = 36, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 8.5, d = 1.0, fin = 1.3 } },
  gbu38 = { kind = "bomb", guided = true, dmg = 1100, splash = 28, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 6.6, d = 0.76, fin = 1.0 } },
  gbu39 = { kind = "bomb", guided = true, dmg = 700, splash = 18, lockTime = 0.8, cone = 70, vs = VS_BOMB, shape = { L = 5.0, d = 0.53, fin = 0.6, wing = 4.0 } },
  lt2 = { kind = "bomb", guided = true, dmg = 1350, splash = 30, lockTime = 0.8, cone = 60, vs = VS_BOMB, shape = { L = 11, d = 1.04, fin = 1.2 } },
  fl90 = { kind = "rkt", dmg = 260, splash = 13, speed = 720, range = 1800, rate = 0.13, tubes = 12, vs = VS_RKT, shape = { L = 5.0, d = 1.2 } },
}
-- 导引方式：ir 红外、radar 主动雷达、laser 激光、gps 卫星 / 惯性、tv 电视 / 红外成像、arm 被动雷达（反辐射）、none 无制导
local GUIDE = { pl10 = "ir", aim9x = "ir", ty90 = "ir", aim92 = "ir", pl15 = "radar", pl12 = "radar", aim120 = "radar", akd10 = "laser", agm114 = "laser",
  kd88 = "tv", agm65 = "tv", yj91 = "arm", agm88 = "arm", ls6 = "gps", gbu31 = "gps", gbu32 = "gps", gbu38 = "gps", gbu39 = "gps", gbu12 = "laser", lt2 = "laser" }
for id, w in pairs(AirDefs.W) do
  w.id = id
  w.guide = GUIDE[id] or ((w.kind == "gun") and "gun" or "none")
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
  gear = { nose = { z = -16, len = 5.2 }, main = { x = 3.4, z = 5.5, len = 5.0 }, r = 1.1 },
  bays = { main = { z0 = -3, z1 = 10, w = 4.2 }, sideR = { x = 3.9, z0 = -9, z1 = -2.5, w = 1.3 } },
  st = mirror({
    { name = "bayM1", pos = V(1.0, -2.2, 3.5), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayM2", pos = V(2.8, -1.9, 3.5), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayS", pos = V(3.9, -1.6, -5.5), bay = "sideR", opts = { "pl10" } },
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
    { name = "mid", pos = V(12, -1.3, 6.0), opts = { "pl15", "pl12", "kd88", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "inner", pos = V(7.8, -1.5, 4.0), opts = { "pl15", "pl12", "kd88", "yj91", "ls6", "lt2", "b250" }, n = N({ b250 = 2 }) },
    { name = "duct", pos = V(2.8, -3.6, 3.0), opts = { "pl15", "pl12", "ls6" } },
  }),
  presets = { preset("aa", { tip = "pl10", outer = "pl10", mid = "pl15", inner = "pl15", duct = "pl15" }),
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
    { name = "duct", pos = V(2.8, -3.6, 3.0), opts = { "pl15", "pl12", "ls6", "kd88" } },
  }),
  presets = { preset("aa", { tip = "pl10", outer = "pl10", mid = "pl15", inner = "pl15", duct = "pl15" }),
    preset("ag", { tip = "pl10", outer = "pl15", mid = "kd88", inner = "kd88", duct = "ls6" }),
    preset("strike", { tip = "pl10", outer = "pl15", mid = "b250", inner = "b250", duct = "ls6" }),
    preset("sead", { tip = "pl10", outer = "pl12", mid = "yj91", inner = "yj91", duct = "pl15" }) } }
D.j50 = { kind = "jet", cat = "jet", L = 62, W = 36, H = 9.5, gearH = 6.2, hp = 720, stall = 110, vMil = 370, vAB = 480, accel = 54, abAccel = 34,
  pitch = 44, roll = 200, yaw = 14, g = 8.5, flares = 32, ab = true, stealth = true, tailless = true,
  fus = { len = 58, w = 7.6, h = 4.2, y = 0 }, nose = 12, canopy = { z = -16, len = 9.5, w = 3.0, h = 2.2, y = 2.2 },
  intake = "dorsal", intakeZ = -2, intakeW = 3.0,
  wing = { xr = 3.8, zr0 = -13, zr1 = 22, xt = 18, zt0 = 9, zt1 = 15, y = 0.1, lambda = { x = 10, z = 18 } }, elevon = true, wingtipRudder = true,
  eng = { { x = 2.6, y = 0.4, z = 27.5, r = 1.3, flat = true }, { x = -2.6, y = 0.4, z = 27.5, r = 1.3, flat = true } },
  gear = { nose = { z = -18, len = 5.0 }, main = { x = 3.8, z = 6.5, len = 4.8 }, r = 1.1 },
  bays = { main = { z0 = -6, z1 = 10, w = 5.4 }, sideR = { x = 4.6, z0 = -10, z1 = -3, w = 1.4 } },
  st = mirror({
    { name = "bayM1", pos = V(1.2, -2.0, 2.0), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayM2", pos = V(3.3, -1.8, 2.0), bay = "main", opts = { "pl15", "ls6" } },
    { name = "bayS", pos = V(4.6, -1.5, -6.5), bay = "sideR", opts = { "pl10" } },
  }),
  presets = { preset("aa", { bayM1 = "pl15", bayM2 = "pl15", bayS = "pl10" }), preset("ag", { bayM1 = "ls6", bayM2 = "ls6", bayS = "pl10" }) } }
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
    { name = "bay", pos = V(0, -3.6, 4), bay = "main", opts = { "b250" }, n = N({ b250 = 12 }) },
    { name = "pylI", pos = V(13, -3.4, 1.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
    { name = "pylM", pos = V(21, -3.2, 4.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
    { name = "pylO", pos = V(29, -3.0, 7.5), opts = { "kd88", "b250" }, n = N({ b250 = 3 }) },
  }),
  presets = { preset("bomb", { bay = "b250", pylI = "b250", pylM = "b250", pylO = "b250" }), preset("kd88", { bay = "b250", pylI = "kd88", pylM = "kd88", pylO = "kd88" }) } }
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
  pods = { { x = 3.4, y = 3.2, z = 9, len = 9, r = 1.9 } }, eng = { { x = 3.4, y = 3.2, z = 14, r = 1.4, cold = true }, { x = -3.4, y = 3.2, z = 14, r = 1.4, cold = true } },
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

---------------------------------------------------------------- 补默认值

for id, d in pairs(D) do
  d.id = id
  d.air = true
  if d.kind == "jet" then
    d.vMax = d.vAB or d.vMil
    d.vRot = d.stall * 1.08   -- 抬头离地的速度
    d.landMax = d.stall * 1.45   -- 着陆最快多少（再快就是撞地）
    d.seats = d.seats or 1
  else
    d.vMax = d.vMax or 90
  end
  d.gunAmmo = d.gunAmmo or 0
  d.flares = d.flares or 0
  d.hitbox = (d.kind == "heli") and V(math.max(d.W, 8), d.H * 0.8, d.L * 0.8) or V(d.W * 0.7, d.H * 0.75, d.L * 0.9)
  for i, s in ipairs(d.st or {}) do s.i = i end
end

-- 攻方舰队的甲板（和 World.fleet 拼的一样大：甲板面高 top）：飞机能停在上面、从上面起飞
AirDefs.DECKS = { carrier = { L = 620, W = 120, top = 30.5 }, lhd = { L = 480, W = 94, top = 26.5 }, lst = { L = 300, W = 60, top = 18.5 } }
-- (x, z) 处能落地的面多高：地形（海上是海面 0）、甲板
function AirDefs.ground(Map, x, z)
  local g = Map.ground(x, z)
  for _, s in ipairs(Map.FLEET or {}) do
    local K = AirDefs.DECKS[s.kind]
    if K and math.abs(x - s.x) < K.W / 2 and math.abs(z - s.z) < K.L / 2 then g = math.max(g, K.top) end
  end
  return g
end
-- 航母：三条弹射器（舰艏两条、斜角甲板一条）、拦阻索区；坐标相对航母甲板中心（舰艏朝 −Z），a 是往左舷偏的角度
--   停机位在右舷后部（Air.lua）：自己滑到弹射器起点，对正了就卡上，油门推满按空格弹射；着舰放尾钩，落在拦阻索区就被拉停
AirDefs.CATS = { { x = 18, z = -50, len = 240, a = 0 }, { x = -6, z = -50, len = 240, a = 0 }, { x = -30, z = 70, len = 220, a = math.rad(8) } }
AirDefs.WIRES = { z0 = 150, z1 = 245, x = -20, a = math.rad(8), n = 4 }
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
-- (x, z) 在不在拦阻索区（斜角甲板后半段）
function AirDefs.inWires(Map, x, z)
  local base = AirDefs.carrierCF(Map)
  if not base then return false end
  local l = base:PointToObjectSpace(Vector3.new(x, base.Position.Y, z))
  return l.Z > AirDefs.WIRES.z0 and l.Z < AirDefs.WIRES.z1 and l.X > -55 and l.X < 20
end
-- 在不在甲板上
function AirDefs.onDeck(Map, x, z)
  for _, s in ipairs(Map.FLEET or {}) do
    local K = AirDefs.DECKS[s.kind]
    if K and math.abs(x - s.x) < K.W / 2 and math.abs(z - s.z) < K.L / 2 then return s.kind end
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
    if w and not seen[w] then table.insert(out, w) seen[w] = true end
  end
  return out
end

return AirDefs
