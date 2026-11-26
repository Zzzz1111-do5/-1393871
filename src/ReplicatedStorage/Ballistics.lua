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
  m829a3 = { cls = "ap", name = "M829A3", sym = "SABOT", v0 = 1555, k = 3.6e-5, bs = 1200, tr = true,      -- 120 毫米尾翼稳定脱壳穿甲弹（贫铀长杆）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m830 = { cls = "heat", name = "M830 HEAT-MP-T", sym = "HEAT", v0 = 1140, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 120 毫米破甲多用途弹（截图里那种）
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  m830a1 = { cls = "mpat", name = "M830A1 MPAT", sym = "MPAT", v0 = 1410, k = 8.5e-5, bs = 900, tr = true, ce = true,    -- 120 毫米多用途反坦克弹（能打直升机）
    vs = { inf = 1.0, light = 1.3, armor = 0.85, fort = 1.2, air = 1.4 }, splash = 1.1 },
  m1028 = { cls = "can", name = "M1028 CAN", sym = "CAN", v0 = 1410, k = 1.5e-4, bs = 300, tr = false,       -- 120 毫米霰弹：1150 颗钨珠，近距离打步兵（500 米内）
    pellets = 24, coneDeg = 1.8, range = 600, pdmg = 0.12,   -- 游戏里按 24 道弹丸射线算（每道 = 一小把钨珠），锥角 ±1.8°、打 600 米
    vs = { inf = 1.6, light = 0.4, armor = 0.02, fort = 0.15, air = 0.6 } },
  m900 = { cls = "ap", name = "M900", sym = "SABOT", v0 = 1505, k = 4.0e-5, bs = 1200, tr = true,           -- 105 毫米尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m456 = { cls = "heat", name = "M456 HEAT", sym = "HEAT", v0 = 1173, k = 1.0e-4, bs = 900, tr = true, ce = true,         -- 105 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  dtc10 = { cls = "ap", name = "DTC10-125", sym = "穿甲", v0 = 1740, k = 3.4e-5, bs = 1200, tr = true,       -- 125 毫米尾翼稳定脱壳穿甲弹（99A）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  heat125 = { cls = "heat", name = "125 HEAT", sym = "破甲", v0 = 905, k = 1.0e-4, bs = 900, tr = true, ce = true,         -- 125 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  he125 = { cls = "he", name = "125 HE-FRAG", sym = "榴弹", v0 = 850, k = 1.0e-4, bs = 800, tr = false,        -- 125 毫米杀爆弹
    vs = { inf = 1.4, light = 1.0, armor = 0.5, fort = 1.6 }, splash = 1.6 },
  -- 俄制 125 毫米（T-90M 的 2A46M-5，用户 11-24「找俄系」）：
  bm60 = { cls = "ap", name = "3BM60 Svinets-2", sym = "穿甲", v0 = 1660, k = 3.5e-5, bs = 1200, tr = true,     -- 「铅-2」贫铀长杆尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  bk31 = { cls = "heat", name = "3BK31 HEAT", sym = "破甲", v0 = 915, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 串联装药破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.95, fort = 1.3 }, splash = 1.0 },
  of26 = { cls = "he", name = "3OF26 HE-FRAG", sym = "榴弹", v0 = 850, k = 1.0e-4, bs = 800, tr = false,      -- 杀伤爆破榴弹
    vs = { inf = 1.4, light = 1.0, armor = 0.5, fort = 1.6 }, splash = 1.6 },
  -- 金属射流弹（用户 11-24 夜「再做一个金属射流弹」）：串联聚能装药破甲弹——前级先把爆反引爆，主装药炸出一股几千米每秒的铜射流
  --   往装甲里钻（穿深跟距离无关）；打中时客户端画一道白热的射流（WtHud 的 wtJet），X 光里是一道亮青白线
  jet120 = { cls = "jet", name = "120 金属射流弹", sym = "射流", v0 = 1180, k = 1.0e-4, bs = 900, tr = true, ce = true,
    vs = { inf = 0.8, light = 1.35, armor = 1.0, fort = 1.3 }, splash = 0.9 },
  jet125 = { cls = "jet", name = "125 金属射流弹", sym = "射流", v0 = 950, k = 1.0e-4, bs = 900, tr = true, ce = true,
    vs = { inf = 0.8, light = 1.35, armor = 1.0, fort = 1.3 }, splash = 0.9 },
  jet105 = { cls = "jet", name = "105 金属射流弹", sym = "射流", v0 = 1180, k = 1.0e-4, bs = 900, tr = true, ce = true,
    vs = { inf = 0.8, light = 1.35, armor = 0.95, fort = 1.3 }, splash = 0.9 },
  -- 炮射导弹（用户 11-25「全部都做」⑥）：9M119M「反射」——从 125 炮里打出去，激光驾束（这里按炮长瞄准线导引，同 Armor.lua G.atgmStep），
  --   350 米 / 秒、5 公里、串联破甲约 850 毫米；cls atgm：Armor.lua 开火时发导弹，不按炮弹的弹道
  refleks = { cls = "atgm", name = "9M119M Refleks", sym = "导弹", v0 = 350, k = 0, bs = 900, tr = false, ce = true, range = 5000, turn = 2.2,
    vs = { inf = 0.8, light = 1.3, armor = 1.0, fort = 1.2 }, splash = 1.0 },
  -- 科技树换真模型的几型车（用户 11-25「需要模型自己找」）按真车的弹：
  bm42 = { cls = "ap", name = "3BM42 Mango", sym = "穿甲", v0 = 1715, k = 3.6e-5, bs = 1200, tr = true,      -- T-80U：「芒果」钨合金长杆尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  bm15 = { cls = "ap", name = "3BM15", sym = "穿甲", v0 = 1785, k = 4.4e-5, bs = 1200, tr = true,           -- T-64A：钢弹体 + 碳化钨弹芯的尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  bm22 = { cls = "ap", name = "3BM22 Zakolka", sym = "穿甲", v0 = 1710, k = 4.0e-5, bs = 1200, tr = true,    -- T-80B：「别针」尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  bk18m = { cls = "heat", name = "3BK18M HEAT", sym = "破甲", v0 = 905, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 125 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  dm53 = { cls = "ap", name = "DM53", sym = "KE", v0 = 1750, k = 3.4e-5, bs = 1200, tr = true,               -- 豹 2A6（L/55）：钨合金长杆，德军火控上动能弹记作 KE
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  dm33 = { cls = "ap", name = "DM33", sym = "KE", v0 = 1650, k = 3.8e-5, bs = 1200, tr = true,               -- 豹 2A4（L/44）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  dm12 = { cls = "heat", name = "DM12 HEAT-MP", sym = "MZ", v0 = 1140, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 120 毫米多用途破甲弹（MZ = 多用途）
    vs = { inf = 1.0, light = 1.3, armor = 0.85, fort = 1.2 }, splash = 1.1 },
  dm13 = { cls = "ap", name = "DM13 APDS", sym = "KE", v0 = 1426, k = 7.0e-5, bs = 1000, tr = true,          -- 豹 1：105 毫米脱壳穿甲弹（不是尾翼稳定的，掉速快）
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  dm33l7 = { cls = "ap", name = "DM33 (105)", sym = "KE", v0 = 1455, k = 4.2e-5, bs = 1200, tr = true,       -- 豹 1A5：105 毫米尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  dm12h = { cls = "heat", name = "DM12 HEAT", sym = "HL", v0 = 1173, k = 1.0e-4, bs = 900, tr = true, ce = true,   -- 105 毫米破甲弹（M456 的德国版，HL = 空心装药）
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  m833 = { cls = "ap", name = "M833", sym = "SABOT", v0 = 1494, k = 4.0e-5, bs = 1200, tr = true,            -- M60A3：105 毫米贫铀尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m392 = { cls = "ap", name = "M392A2 APDS", sym = "SABOT", v0 = 1478, k = 7.0e-5, bs = 1000, tr = true,     -- M60A1：105 毫米脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
  m409 = { cls = "heat", name = "M409 HEAT-MP", sym = "HEAT", v0 = 683, k = 1.4e-4, bs = 700, tr = true, ce = true,   -- M551：152 毫米多用途破甲弹，初速低、弹道弯
    vs = { inf = 1.1, light = 1.3, armor = 0.9, fort = 1.4 }, splash = 1.3 },
  -- 59 式 / 69-II 式的 100 毫米线膛炮（11-26）：
  br412d = { cls = "ap", name = "BR-412D APBC", sym = "穿甲", v0 = 887, k = 1.1e-4, bs = 1000, tr = true,            -- 59 式：钝头被帽穿甲弹（全口径，掉速快）
    vs = { inf = 0.6, light = 1.1, armor = 1.0, fort = 0.9 }, splash = 0.8 },
  bk5m = { cls = "heat", name = "BK-5M HEAT", sym = "破甲", v0 = 900, k = 1.0e-4, bs = 900, tr = true, ce = true,      -- 100 毫米破甲弹
    vs = { inf = 0.9, light = 1.3, armor = 0.9, fort = 1.3 }, splash = 1.0 },
  of412 = { cls = "he", name = "OF-412 HE-FRAG", sym = "榴弹", v0 = 900, k = 1.0e-4, bs = 800, tr = false,             -- 100 毫米杀爆榴弹
    vs = { inf = 1.4, light = 1.0, armor = 0.5, fort = 1.6 }, splash = 1.5 },
  apfsds69 = { cls = "ap", name = "100mm APFSDS", sym = "穿甲", v0 = 1415, k = 4.4e-5, bs = 1200, tr = true,           -- 69-II 式：尾翼稳定脱壳穿甲弹
    vs = { inf = 0.55, light = 1.0, armor = 1.1, fort = 0.8 }, splash = 0.6 },
}
-- 每门炮能打的弹（第一个是默认），以及车里炮长控制面板上的弹种键（InteriorScreens 的 gcdp 页）对到哪种弹
B.GUN = {
  gun120 = { "m829a3", "m830", "m830a1", "m1028", "jet120" },   -- M1A2 SEPv2：没有弹药数据链（ADL），打不了 AMP、M829A4（要 SEPv3）
  gun125 = { "dtc10", "heat125", "he125", "jet125" },
  gun125r = { "bm60", "bk31", "of26", "refleks", "jet125" },   -- T-90M：3BM60、3BK31、3OF26（炮射导弹 9M119M「反射」游戏里没有）
  gun105 = { "m900", "m456", "jet105" },
  gun125u = { "bm42", "bk18m", "of26", "refleks", "jet125" },    -- T-80U（9M119「反射」炮射导弹游戏里没有）
  gun125b = { "bm22", "bk18m", "of26", "jet125" },    -- T-80B、T-64B
  gun125a = { "bm15", "bk18m", "of26", "jet125" },    -- T-64A
  gun120l55 = { "dm53", "dm12", "jet120" },           -- 豹 2A6
  gun120l44 = { "dm33", "dm12", "jet120" },           -- 豹 2A4
  gun105l7 = { "dm13", "dm12h", "jet105" },           -- 豹 1
  gun105a5 = { "dm33l7", "dm12h", "jet105" },         -- 豹 1A5
  gun105m68 = { "m833", "m456", "jet105" },           -- M60A3
  gun105m60 = { "m392", "m456", "jet105" },           -- M60A1
  gun152 = { "m409" },                                 -- M551（MGM-51 导弹游戏里没有）
  gun100d = { "br412d", "bk5m", "of412" },            -- 59 式
  gun100d69 = { "apfsds69", "bk5m", "of412" },        -- 69-II 式
}
-- 面板上的键 → 弹种（这门炮没有这一种就挑它同一类 cls 的：T-90M 借 99A 的面板，「穿甲」键打 3BM60）
function B.panelAmmo(kind, wid)
  local key = B.PANEL[kind]
  local list = wid and B.GUN[wid]
  if key and list and not table.find(list, key) then
    local cls = B.AMMO[key] and B.AMMO[key].cls
    for _, k in ipairs(list) do if B.AMMO[k] and B.AMMO[k].cls == cls then return k end end
  end
  return key
end
B.PANEL = { SABOT = "m829a3", HEAT = "m830", MPAT = "m830a1", CAN = "m1028",
  ap = "dtc10", heat = "heat125", he = "he125", gl = "heat125" }
B.MAXR = 8000   -- 激光测距、弹在空中最多飞的距离（米）；11-25 用户「全部都做」③：5 → 8 公里（战雷里炮弹一直飞到落地，沙海 12.7 公里见方）

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
  if a.cls == "atgm" then return 0, xm / math.max(a.v0, 1) end   -- 炮射导弹（⑥）：顺着瞄准线飞，不抬炮
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
