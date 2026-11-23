-- Roblox全面大战场——坦克炮的真实外弹道和火控计算（服务器、客户端共用）
--   用户 11-22 晚（发来钢铁猛兽 M1A2 热像截图：M830 HEAT-T、1790 米，曳光弹在画面左上方）：
--     「开镜开炮炮弹从左上方落下去，符合真实物理学和火控系统」
--   真实的：初速（米 / 秒，按弹种）、重力 9.81 米 / 秒²、空气阻力（速度平方阻力 a = −k·v·|v|：每飞一米速度掉 k 倍，
--     k 按公开资料里每公里掉多少速度折出来）。1 米 = 2.8 格
--   火控（Drive.lua）：炮长激光测距 → 弹道计算机按距离、弹种算出炮要比瞄准线高多少（超高角）；炮和瞄准镜不在一处，
--     炮对准瞄准线上那个距离的点（视差）；跟踪时按瞄准线转动的角速度 × 飞行时间加提前量；没测距按战斗瞄准距离
--   为什么曳光弹在镜里从左上方来：M1 的主瞄准镜在炮的右上方，炮管比瞄准线高出超高角——弹从左边（炮口那侧）出来、
--     先升到瞄准线上方，再落到分划中心（99A 的瞄准镜在炮左边：从右上方来）
local B = {}
local S = 2.8
B.S = S
B.G = 9.81 * S   -- 真实重力（格 / 秒²）

-- 弹种：v0 初速（米 / 秒）、k 阻力系数（每米；dv/dx = −k·v）、bs 战斗瞄准距离（米，没测距时火控按它装定）、
--   tr 曳光、ce 聚能装药（破甲 / 多用途：爆反照挡破甲弹那样挡，Era.lua）、vs 打各类目标的伤害倍数（乘在炮的 vs 上）、splash 爆炸半径倍数；
--   资料：公开的弹药手册、厂家数据
B.AMMO = {
  m829a3 = { name = "M829A3", sym = "SABOT", v0 = 1555, k = 3.6e-5, bs = 1200, tr = true,      -- 120 毫米尾翼稳定脱壳穿甲弹（贫铀长杆）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m830 = { name = "M830 HEAT-MP-T", sym = "HEAT", v0 = 1140, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 120 毫米破甲多用途弹（截图里那种）
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  m830a1 = { name = "M830A1 MPAT", sym = "MPAT", v0 = 1410, k = 8.5e-5, bs = 900, tr = true, ce = true,    -- 120 毫米多用途反坦克弹（能打直升机）
    vs = { inf = 1.0, light = 1.3, armor = 0.85, fort = 1.2, air = 1.4 }, splash = 1.1 },
  m1147 = { name = "M1147 AMP", sym = "AMP", v0 = 1410, k = 9.0e-5, bs = 900, tr = true, ce = true,        -- 120 毫米高爆多用途弹（破障、打步兵、工事）
    vs = { inf = 1.3, light = 1.1, armor = 0.6, fort = 1.6 }, splash = 1.5 },
  m900 = { name = "M900", sym = "SABOT", v0 = 1505, k = 4.0e-5, bs = 1200, tr = true,           -- 105 毫米尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m456 = { name = "M456 HEAT", sym = "HEAT", v0 = 1173, k = 1.0e-4, bs = 900, tr = true, ce = true,         -- 105 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  dtc10 = { name = "DTC10-125", sym = "穿甲", v0 = 1740, k = 3.4e-5, bs = 1200, tr = true,       -- 125 毫米尾翼稳定脱壳穿甲弹（99A）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  heat125 = { name = "125 HEAT", sym = "破甲", v0 = 905, k = 1.0e-4, bs = 900, tr = true, ce = true,         -- 125 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  he125 = { name = "125 HE-FRAG", sym = "榴弹", v0 = 850, k = 1.0e-4, bs = 800, tr = false,        -- 125 毫米杀爆弹
    vs = { inf = 1.4, light = 1.0, armor = 0.5, fort = 1.6 }, splash = 1.6 },
}
-- 每门炮能打的弹（第一个是默认），以及车里炮长控制面板上的弹种键（InteriorScreens 的 gcdp 页）对到哪种弹
B.GUN = {
  gun120 = { "m829a3", "m830", "m830a1", "m1147" },
  gun125 = { "dtc10", "heat125", "he125" },
  gun105 = { "m900", "m456" },
}
B.PANEL = { SABOT = "m829a3", HEAT = "m830", MPAT = "m830a1", AMP = "m1147", CAN = "m1147",
  ap = "dtc10", heat = "heat125", he = "he125", gl = "heat125" }
B.MAXR = 5000   -- 激光测距、弹在空中最多飞的距离（米）

-- 这门炮的这种弹（不认识的弹给默认那种）
function B.ammo(wid, key)
  local list = B.GUN[wid]
  if not list then return nil, nil end
  for _, k in ipairs(list) do if k == key then return B.AMMO[k], k end end
  return B.AMMO[list[1]], list[1]
end

-- 平射近似下的解析解（和 Ents.lua / Fx.lua 逐步积分的同一个模型：重力 + 速度平方阻力）：
--   沿弹道飞 x 米：速度 v = v0·e^(−kx)，用时 t = (e^(kx) − 1) / (k·v0)，
--   比不受重力的直线低 D = g / (2k·v0²) · ((e^(2kx) − 1) / (2k) − x)（k → 0 时就是真空里的 g·x² / (2·v0²)）
function B.flight(a, xm)
  local k, v0, g = a.k, a.v0, 9.81
  local ekx = math.exp(k * xm)
  local t = (ekx - 1) / (k * v0)
  local drop = g / (2 * k * v0 * v0) * ((ekx * ekx - 1) / (2 * k) - xm)
  return t, drop, v0 / ekx
end

-- 超高角（弧度）：打 xm 米远、瞄准线仰角 los（弧度）时炮要比瞄准线高多少（下坠只算垂直瞄准线那一份：× cos los）
function B.superElev(a, xm, los)
  if xm < 1 then return 0, 0 end
  local t, drop = B.flight(a, xm)
  return math.atan(drop * math.cos(los or 0) / xm), t
end

-- 游戏里用的：初速（格 / 秒）、阻力系数（每格）、重力倍数（Ents / Fx 的 GRAV = workspace.Gravity × 0.55 乘 gscale）
function B.launchArgs(a)
  return a.v0 * S, a.k / S, B.G / (workspace.Gravity * 0.55)
end

-- 打 xm 米远（米），默认弹种按这门炮：超高角、飞行时间（AI、第三人称自动测距都用这个）
function B.aimFor(wid, xm, los, key)
  local a = B.ammo(wid, key)
  if not a then return 0, 0 end
  return B.superElev(a, xm, los)
end

return B
