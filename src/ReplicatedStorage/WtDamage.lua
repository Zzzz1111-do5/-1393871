-- Roblox全面大战场——战雷式的车辆伤害模型（服务器、客户端共用：服务器算伤害，客户端画 X 光命中回放、准星的穿深指示）
--   用户 11-24：「把整个游戏做成战雷」，问了范围以后四项全勾（坦克平显、乘员和模块伤害 + X 光回放、对局玩法、飞机）：
--   · 装甲按毫米（动能弹 ke / 化学能 ce 两个数），分车体 / 炮塔、正面 / 侧面 / 后面 / 顶上；首下、炮塔座圈、炮盾是弱点
--   · 弹按穿深（毫米，脱壳穿甲弹随距离掉一点），入射角越斜等效越厚、太斜会跳弹（破甲弹太斜引信不发火）
--   · 击穿以后弹芯 / 金属射流顺着弹道往里钻、一锥破片散开：打到哪个乘员、哪个模块就伤哪个——
--     乘员（驾驶员、炮长、车长、装填手）各自有血，模块（发动机、传动、履带、炮管、炮闩、炮塔驱动、弹药架、油箱）各自有血；
--     乘员剩不到一半、或者弹药架殉爆，车就算被击毁（照战雷：四人车组剩一个、三人车组剩一个就完了）
--   坐标：车的「底座」系（同 VehDefs：底面中心、y 朝上、−z 朝前，格）；炮塔上的零件在炮塔系（转轴处、跟炮塔转）
local W = {}
local V = Vector3.new
local M = 2.8   -- 1 米 = 2.8 格

---------------------------------------------------------------- 装甲（毫米）：{ ke 动能弹, ce 破甲弹 }

-- hull / tur：f 正面、s 侧面、r 后面、t 顶上（炮塔侧面前半截按 sf，后半截按 s）；crew 车组（角色顺序：驾驶员 drv、炮长 gnr、车长 cmd、装填手 ldr）；
--   lay 布局：w4 西方四人坦克（弹在炮塔尾舱、有泄压板）、e3 东方三人坦克（转盘式自动装弹机在车体底、没有泄压）、ifv 步战车（发动机在前）、
--   ifvr 步战车（发动机在后：BMP-3）、apc 轮式装甲车、light 轻型车、spg 自行火炮 / 防空（炮塔大、弹在炮塔里）
W.PROF = {
  m1a2 = { lay = "w4", hull = { f = { 560, 850 }, s = { 70, 90 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 800, 1300 }, sf = { 300, 350 }, s = { 100, 120 }, r = { 60, 60 }, t = { 45, 45 } }, blowout = true },
  m1a1 = { lay = "w4", hull = { f = { 520, 750 }, s = { 65, 80 }, r = { 30, 30 }, t = { 30, 30 } },
    tur = { f = { 650, 1100 }, sf = { 260, 300 }, s = { 90, 110 }, r = { 60, 60 }, t = { 40, 40 } }, blowout = true },
  t90m = { lay = "e3", hull = { f = { 600, 1000 }, s = { 80, 150 }, r = { 40, 40 }, t = { 40, 40 } },
    tur = { f = { 750, 1300 }, sf = { 300, 450 }, s = { 150, 250 }, r = { 60, 60 }, t = { 45, 60 } } },
  ztz99a = { lay = "e3", hull = { f = { 650, 1000 }, s = { 90, 150 }, r = { 40, 40 }, t = { 40, 40 } },
    tur = { f = { 800, 1350 }, sf = { 320, 450 }, s = { 120, 180 }, r = { 60, 60 }, t = { 45, 50 } } },
  ztz96 = { lay = "e3", hull = { f = { 480, 650 }, s = { 80, 100 }, r = { 40, 40 }, t = { 35, 35 } },
    tur = { f = { 520, 750 }, sf = { 250, 300 }, s = { 100, 130 }, r = { 50, 50 }, t = { 40, 40 } } },
  m2a3 = { lay = "ifv", hull = { f = { 80, 120 }, s = { 40, 60 }, r = { 20, 20 }, t = { 20, 20 } }, tur = { f = { 60, 60 }, s = { 30, 30 }, r = { 20, 20 }, t = { 20, 20 } } },
  hmmwv = { lay = "light", hull = { f = { 8, 8 }, s = { 6, 6 }, r = { 5, 5 }, t = { 4, 4 } }, crew = 2 },
  jltv = { lay = "light", hull = { f = { 15, 15 }, s = { 12, 12 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 2 },
  pgz07 = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 15, 15 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 4 },
  m163 = { lay = "spg", hull = { f = { 30, 30 }, s = { 25, 25 }, r = { 15, 15 }, t = { 15, 15 } }, tur = { f = { 12, 12 }, s = { 12, 12 }, r = { 12, 12 }, t = { 8, 8 } }, crew = 2 },
  pgl625 = { lay = "spg", hull = { f = { 12, 12 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  pantsir = { lay = "spg", hull = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  ld2000 = { lay = "spg", hull = { f = { 12, 12 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 3 },
  mshorad = { lay = "apc", hull = { f = { 35, 35 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, tur = { f = { 20, 20 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 3 },
  cram = { lay = "spg", hull = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, tur = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 2 },
  plz07 = { lay = "spg", hull = { f = { 40, 40 }, s = { 25, 25 }, r = { 20, 20 }, t = { 15, 15 } }, tur = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, crew = 4 },
  m109a7 = { lay = "spg", hull = { f = { 40, 40 }, s = { 30, 30 }, r = { 20, 20 }, t = { 15, 15 } }, tur = { f = { 30, 30 }, s = { 25, 25 }, r = { 15, 15 }, t = { 12, 12 } }, crew = 4 },
  m270 = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 10, 10 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 3 },
  patriot = { lay = "light", hull = { f = { 10, 10 }, s = { 8, 8 }, r = { 8, 8 }, t = { 6, 6 } }, crew = 2 },
}
-- 没登记的型号按类别给一套
W.CAT = {
  tank = { lay = "w4", hull = { f = { 450, 600 }, s = { 70, 80 }, r = { 35, 35 }, t = { 30, 30 } }, tur = { f = { 500, 700 }, sf = { 200, 250 }, s = { 80, 90 }, r = { 50, 50 }, t = { 35, 35 } } },
  apc = { lay = "apc", hull = { f = { 30, 30 }, s = { 18, 18 }, r = { 12, 12 }, t = { 10, 10 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } } },
  aa = { lay = "spg", hull = { f = { 20, 20 }, s = { 15, 15 }, r = { 10, 10 }, t = { 8, 8 } }, tur = { f = { 15, 15 }, s = { 10, 10 }, r = { 10, 10 }, t = { 8, 8 } }, crew = 3 },
  arty = { lay = "spg", hull = { f = { 30, 30 }, s = { 20, 20 }, r = { 15, 15 }, t = { 12, 12 } }, tur = { f = { 25, 25 }, s = { 15, 15 }, r = { 12, 12 }, t = { 10, 10 } }, crew = 4 },
}
function W.prof(d)
  return W.PROF[d.id] or W.CAT[d.cat] or W.CAT.apc
end

---------------------------------------------------------------- 弹的穿深（毫米）

-- 坦克炮弹（Ballistics.AMMO 的键）：p0 炮口处、fall 每公里掉多少（脱壳穿甲弹）、t 类型（ke 动能 / ce 聚能 / he 杀爆）、
--   spall 破片锥半角（度）、n 破片数、core 弹芯 / 射流往里钻多远（米）、tandem 串联装药（爆反挡不住）
W.AMMO = {
  m829a3 = { p0 = 800, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  m830 = { p0 = 600, t = "ce", spall = 20, n = 12, core = 2.4 },
  m830a1 = { p0 = 500, t = "ce", spall = 22, n = 12, core = 2.0 },
  m1028 = { p0 = 15, t = "he", spall = 30, n = 0, core = 0 },
  m900 = { p0 = 560, fall = 30, t = "ke", spall = 16, n = 14, core = 3.0 },
  m456 = { p0 = 430, t = "ce", spall = 20, n = 10, core = 2.0 },
  dtc10 = { p0 = 760, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  heat125 = { p0 = 550, t = "ce", spall = 20, n = 12, core = 2.2 },
  he125 = { p0 = 45, t = "he", spall = 40, n = 20, core = 0, blast = 2.4 },
  bm60 = { p0 = 720, fall = 30, t = "ke", spall = 16, n = 16, core = 3.2 },
  bk31 = { p0 = 760, t = "ce", spall = 20, n = 12, core = 2.4, tandem = true },
  of26 = { p0 = 45, t = "he", spall = 40, n = 20, core = 0, blast = 2.4 },
}
-- 别的武器（按武器 id）：机炮的脱壳穿甲弹、反坦克火箭 / 导弹、飞机的弹
W.WPN = {
  ac30 = { p0 = 70, fall = 25, t = "ke", spall = 18, n = 4, core = 1.2 },      -- 30 毫米（2A72 / Mk44）脱壳穿甲弹
  ac35 = { p0 = 60, fall = 25, t = "ke", spall = 18, n = 4, core = 1.0 },
  ac30aa = { p0 = 55, fall = 25, t = "ke", spall = 18, n = 3, core = 1.0 },
  vulcan = { p0 = 30, fall = 20, t = "ke", spall = 18, n = 2, core = 0.6 },
  gau8 = { p0 = 75, fall = 25, t = "ke", spall = 18, n = 5, core = 1.4 },      -- A-10 的 30 毫米贫铀穿甲弹
  gun100 = { p0 = 40, t = "he", spall = 40, n = 18, core = 0, blast = 2.2 },    -- BMP-3 的 100 毫米榴弹
  hmg = { p0 = 25, fall = 10, t = "ke", spall = 10, n = 1, core = 0.4 },       -- 12.7 毫米穿甲弹
  rpg = { p0 = 500, t = "ce", spall = 22, n = 10, core = 1.8 },                -- 火箭筒（RPG-7 / PF-98 一类的串联破甲）
  c4 = { p0 = 120, t = "he", spall = 40, n = 14, core = 0, blast = 2.6 },
  manpads = { p0 = 40, t = "he", spall = 30, n = 6, core = 0, blast = 1.4 },
  s57e6 = { p0 = 40, t = "he", spall = 30, n = 6, core = 0, blast = 1.6 },
}
-- 按武器的种类给（上面两张表都没有的）：导弹、火箭弹按破甲弹，炸弹、炮弹按杀爆
W.KIND = {
  agm = { p0 = 900, t = "ce", spall = 20, n = 14, core = 2.6 },     -- 空地导弹（地狱火、AKD-10 一类）
  missile = { p0 = 800, t = "ce", spall = 20, n = 12, core = 2.4 },
  rkt = { p0 = 120, t = "ce", spall = 22, n = 6, core = 1.0 },       -- 航空火箭弹
  rocket = { p0 = 120, t = "ce", spall = 22, n = 6, core = 1.0 },
  bomb = { p0 = 80, t = "he", spall = 45, n = 24, core = 0, blast = 4.0 },
  arty = { p0 = 50, t = "he", spall = 40, n = 18, core = 0, blast = 3.0 },
  mortar = { p0 = 25, t = "he", spall = 40, n = 10, core = 0, blast = 2.0 },
  shell = { p0 = 40, t = "he", spall = 40, n = 12, core = 0, blast = 2.2 },
  gun = { p0 = 8, fall = 5, t = "ke", spall = 0, n = 0, core = 0 },
}
-- 这一发的穿深：返回（毫米，表项）；distM 飞了多少米
function W.ammoOf(w)
  if not w then return W.KIND.gun end
  return (w.ammo and W.AMMO[w.ammo]) or (w.id and W.WPN[w.id]) or (w.base and w.base.id and W.WPN[w.base.id]) or W.KIND[w.kind] or W.KIND.gun
end
function W.pen(w, distM)
  local a = W.ammoOf(w)
  local p = a.p0
  if a.fall and distM then p = math.max(a.p0 * 0.4, a.p0 - a.fall * distM / 1000) end
  return p, a
end

---------------------------------------------------------------- 车里的乘员和模块（按型号的尺寸摆，缓存）

-- 每件：k 名字、kind crew / mod、role（乘员）、lo / hi 盒子（格）、tur 在炮塔系、hp 满血、ext 车外的（履带、炮管：没击穿也能打坏）
local cache = {}
local CREW = { drv = "drv", gnr = "gnr", cmd = "cmd", ldr = "ldr" }
W.ROLES = { "drv", "gnr", "cmd", "ldr" }
function W.layout(d)
  local hit = cache[d]
  if hit then return hit end
  local P = W.prof(d)
  local L, Wd, H = d.L, d.W, d.H
  local hH = d.hullH or H * 0.55
  local cl = d.clear or 1.2
  local fl = cl + 0.25              -- 车体底板（里面）
  local list = {}
  local function add(k, kind, lo, hi, extra)
    local it = { k = k, kind = kind, lo = lo, hi = hi, hp = (kind == "crew") and 100 or 100 }
    if extra then for a, b in pairs(extra) do it[a] = b end end
    table.insert(list, it)
    return it
  end
  local function crew(role, c, tur)   -- 一个人：约 0.6 × 0.95 × 0.6 米（坐着）
    return add(role, "crew", c - V(0.85, 1.35, 0.85), c + V(0.85, 1.35, 0.85), { role = role, tur = tur })
  end
  local T = d.turret
  local tp = T and T.pivot or V(0, hH, 0)
  local ts = T and T.size or V(Wd * 0.6, 2, L * 0.4)
  local bus = T and T.bustle or 0
  local lay = P.lay
  local nCrew = P.crew or ((lay == "w4") and 4 or 3)
  local front, back = -L / 2, L / 2
  -- 履带 / 车轮（车外，侧面下半截）：打坏了动不了
  for s = -1, 1, 2 do
    local x0, x1 = s * (Wd / 2 - Wd * 0.13), s * (Wd / 2)
    add(s > 0 and "trackR" or "trackL", "mod", V(math.min(x0, x1), 0, front + 0.5), V(math.max(x0, x1), cl + 1.2, back - 0.5), { ext = true })
  end
  -- 炮管（炮塔系，在外面）、炮闩
  if d.gun and T then
    local gp = d.gun.pivot
    local cal = math.max(0.25, (d.gun.cal or 0.3))
    local len = d.gun.len or 8
    add("barrel", "mod", V(gp.X - cal, gp.Y - cal, gp.Z - len), V(gp.X + cal, gp.Y + cal, gp.Z - 1.2), { tur = true, ext = true })
    add("breech", "mod", V(gp.X - 0.7, gp.Y - 0.65, gp.Z - 0.4), V(gp.X + 0.7, gp.Y + 0.55, gp.Z + 2.6), { tur = true })
    add("tdrive", "mod", V(-1.4, -0.9, -1.6), V(-0.4, 0.1, -0.6), { tur = true })   -- 炮塔驱动（座圈前左）
  end
  local engFront = (lay == "ifv" or lay == "apc" or lay == "light")   -- 发动机在前面的
  if engFront then
    local xs = (lay == "light") and -Wd * 0.3 or Wd * 0.04   -- 步战车：发动机在右前（驾驶员在左前）
    add("engine", "mod", V(xs, fl, front + L * 0.05), V(Wd * 0.36, hH - 0.3, front + L * 0.3))
    add("trans", "mod", V(-Wd * 0.3, fl, front + 0.3), V(Wd * 0.36, fl + 1.2, front + L * 0.06))
  else
    add("engine", "mod", V(-Wd * 0.32, fl, back - L * 0.3), V(Wd * 0.32, hH - 0.35, back - L * 0.08))
    add("trans", "mod", V(-Wd * 0.34, fl, back - L * 0.08), V(Wd * 0.34, fl + 1.3, back - 0.35))
  end
  -- 乘员
  local yS = fl + 1.35   -- 坐着的人中心离底板
  if lay == "w4" then
    crew("drv", V(0, yS, front + L * 0.16))
    crew("gnr", V(1.35, -0.55, -0.9), true)     -- 炮长在右前（炮塔系，y 相对座圈：往下坐进车体）
    crew("cmd", V(1.5, 0.35, 0.9), true)        -- 车长在炮长后上
    crew("ldr", V(-1.45, -0.35, 0.1), true)     -- 装填手在左
    -- 弹：炮塔尾舱（有泄压板）、车体里少量
    add("ammo", "mod", V(-ts.X * 0.4, 0.3, ts.Z / 2 - math.max(1.5, bus)), V(ts.X * 0.4, ts.Y - 0.4, ts.Z / 2 - 0.2), { tur = true, blow = P.blowout })
    add("ammoH", "mod", V(Wd * 0.12, fl, front + L * 0.2), V(Wd * 0.36, fl + 1.6, front + L * 0.32), {})
    add("fuelL", "mod", V(-Wd * 0.38, fl, front + L * 0.06), V(-Wd * 0.14, hH - 0.4, front + L * 0.24))
    add("fuelR", "mod", V(Wd * 0.14, fl, front + L * 0.06), V(Wd * 0.38, hH - 0.4, front + L * 0.2))
  elseif lay == "e3" then
    crew("drv", V(0, yS - 0.2, front + L * 0.15))
    crew("gnr", V(-1.35, -0.7, -0.4), true)     -- 炮长在左、车长在右（坐得低，炮塔里大半在座圈以下）
    crew("cmd", V(1.35, -0.55, -0.2), true)
    -- 转盘式自动装弹机：车体底板上、炮塔下面一圈（没有泄压，殉爆就是掀炮塔）
    add("ammo", "mod", V(tp.X - Wd * 0.36, fl, tp.Z - Wd * 0.34), V(tp.X + Wd * 0.36, fl + 1.0, tp.Z + Wd * 0.34))
    add("ammoH", "mod", V(Wd * 0.12, fl, front + L * 0.06), V(Wd * 0.38, hH - 0.5, front + L * 0.22))   -- 前右油箱架里的备弹
    add("fuelR", "mod", V(Wd * 0.12, fl, front + L * 0.22), V(Wd * 0.38, hH - 0.5, front + L * 0.32))
  else
    -- 步战车 / 装甲车 / 自行火炮：驾驶员在左前（发动机在前的）或正前（发动机在后的）
    local dx = engFront and -Wd * 0.25 or 0
    crew("drv", V(dx, yS, front + L * 0.16))
    if T and lay ~= "light" then
      crew("gnr", V(-1.2, -0.5, -0.2), true)
      if nCrew >= 3 then crew("cmd", V(1.2, -0.4, 0.2), true) end
      if nCrew >= 4 then crew("ldr", V(0, -0.6, 1.4), true) end
      add("ammo", "mod", V(-ts.X * 0.35, -1.2, 0.4), V(ts.X * 0.35, 0.4, ts.Z / 2 - 0.3), { tur = true })
    else
      if nCrew >= 2 then crew("cmd", V(-dx, yS, front + L * 0.16)) end
      if nCrew >= 3 then crew("gnr", V(0, hH + 0.4, front + L * 0.4)) end   -- 车顶的机枪手
      add("ammo", "mod", V(-Wd * 0.25, fl, front + L * 0.3), V(Wd * 0.25, fl + 1.2, front + L * 0.42))
    end
    add("fuelR", "mod", V(Wd * 0.14, fl, back - L * 0.2), V(Wd * 0.38, hH - 0.4, back - L * 0.05))
    if lay ~= "spg" and lay ~= "light" then   -- 载员舱（后半截）：打进去伤里面坐着的人
      add("troops", "mod", V(-Wd * 0.38, fl, front + L * 0.45), V(Wd * 0.38, hH - 0.3, back - L * 0.06), { troop = true })
    end
  end
  hit = { list = list, nCrew = nCrew, prof = P, hH = hH, tp = tp, ts = ts }
  cache[d] = hit
  return hit
end

---------------------------------------------------------------- 打在哪、多厚

-- 底座系的点、方向换到炮塔系（炮塔往右转 yaw 度为正，同 VehDefs.turretCF）
function W.toTur(d, p, yaw)
  local tp = d.turret and d.turret.pivot or V()
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  local q = p - tp
  -- turretCF = base * CF(tp) * Angles(0, −a, 0)：逆变换是绕 y 转 +a（CFrame.Angles(0, θ, 0) 把 x 转到 (cos θ, 0, −sin θ)）
  return V(q.X * c + q.Z * s, q.Y, -q.X * s + q.Z * c)
end
function W.toTurDir(dir, yaw)
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  return V(dir.X * c + dir.Z * s, dir.Y, -dir.X * s + dir.Z * c)
end
function W.fromTur(d, q, yaw)
  local tp = d.turret and d.turret.pivot or V()
  local a = math.rad(yaw or 0)
  local c, s = math.cos(a), math.sin(a)
  return tp + V(q.X * c - q.Z * s, q.Y, q.X * s + q.Z * c)
end

-- 打中的点（底座系）、来向（底座系，单位向量）、炮塔转角 → 区域 zone（hull / tur）、面 face（f / s / r / t）、弱点系数、法线
function W.where(d, p, dir, yaw)
  local lay = W.layout(d)
  local hH = lay.hH
  local T = d.turret
  if T and p.Y > hH - 0.15 then
    local q = W.toTur(d, p, yaw)
    local ts = lay.ts
    if math.abs(q.X) < ts.X / 2 + 0.6 and q.Z > -ts.Z / 2 - 1.2 and q.Z < ts.Z / 2 + 0.6 then
      local dq = W.toTurDir(dir, yaw)
      local face, n
      -- 按来向在炮塔系里哪个分量最大（盒子的哪一面迎着弹）
      if q.Y > ts.Y - 0.35 and -dq.Y > 0.5 then face, n = "t", V(0, 1, 0)
      elseif math.abs(dq.Z) >= math.abs(dq.X) then
        if dq.Z > 0 then face, n = "f", V(0, 0, -1) else face, n = "r", V(0, 0, 1) end
      else
        face, n = "s", V(dq.X > 0 and -1 or 1, 0, 0)
      end
      local weak = 1
      if face == "f" and math.abs(q.X) < 1.1 and math.abs(q.Y - (d.gun and d.gun.pivot.Y or 1)) < 0.7 then weak = 0.75 end   -- 炮盾
      if (face == "f" or face == "s") and q.Y < 0.45 then weak = math.min(weak, 0.55) end   -- 座圈一带
      if face == "s" and q.Z < 0 then face = "sf" end   -- 炮塔侧面前半截（更厚）
      return "tur", face, weak, n, q, dq
    end
  end
  local face, n
  if p.Y > hH - 0.4 and -dir.Y > 0.55 then face, n = "t", V(0, 1, 0)
  elseif math.abs(dir.Z) >= math.abs(dir.X) then
    if dir.Z > 0 then face, n = "f", V(0, 0, -1) else face, n = "r", V(0, 0, 1) end
  else
    face, n = "s", V(dir.X > 0 and -1 or 1, 0, 0)
  end
  local weak = 1
  local cl = d.clear or 1.2
  if face == "f" and p.Y < cl + (hH - cl) * 0.42 then weak = 0.55 end   -- 首下
  return "hull", face, weak, n, p, dir
end

-- 这一面的装甲（毫米）：ce 破甲弹用化学能那个数
function W.armor(d, zone, face, t)
  local P = W.prof(d)
  local z = (zone == "tur" and P.tur) or P.hull
  local a = z[face] or z.s or z.f
  if not a then return 10 end
  return (t == "ce") and (a[2] or a[1]) or a[1]
end

-- 入射角（度，和法线的夹角）下：等效厚度、会不会跳弹
function W.effective(mm, ang, t)
  local c = math.max(math.cos(math.rad(math.min(ang, 85))), 0.12)
  local eff = mm / c
  if t == "ke" then eff = mm / (c ^ 0.82) end   -- 长杆弹斜着打，转正一点
  return eff
end
function W.ricochet(t, ang)
  local a0, a1
  if t == "ke" then a0, a1 = 74, 82 elseif t == "ce" then a0, a1 = 78, 84 else a0, a1 = 66, 78 end
  return math.clamp((ang - a0) / (a1 - a0), 0, 1)
end

-- 一根射线（底座系起点、方向、长度）穿过的零件：{ { it, t 进入时离起点多远 }, … } 按远近
local function slab(o, dv, lo, hi, len)
  local t0, t1 = 0, len
  for _, ax in ipairs({ "X", "Y", "Z" }) do
    local oo, dd, l, h = o[ax], dv[ax], lo[ax], hi[ax]
    if math.abs(dd) < 1e-6 then
      if oo < l or oo > h then return nil end
    else
      local a, b = (l - oo) / dd, (h - oo) / dd
      if a > b then a, b = b, a end
      if a > t0 then t0 = a end
      if b < t1 then t1 = b end
      if t0 > t1 then return nil end
    end
  end
  return t0
end
function W.trace(d, yaw, o, dv, len, skipExt)
  local lay = W.layout(d)
  local out = {}
  local oT, dT = W.toTur(d, o, yaw), W.toTurDir(dv, yaw)
  for _, it in ipairs(lay.list) do
    if not (skipExt and it.ext) then
      local t = it.tur and slab(oT, dT, it.lo, it.hi, len) or slab(o, dv, it.lo, it.hi, len)
      if t then table.insert(out, { it = it, t = t }) end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end
-- 点在不在零件盒子里（底座系）
function W.inside(d, yaw, p, it, pad)
  pad = pad or 0
  local q = it.tur and W.toTur(d, p, yaw) or p
  return q.X >= it.lo.X - pad and q.X <= it.hi.X + pad and q.Y >= it.lo.Y - pad and q.Y <= it.hi.Y + pad and q.Z >= it.lo.Z - pad and q.Z <= it.hi.Z + pad
end
-- 零件中心（底座系；炮塔上的按现在的炮塔转角）
function W.center(d, yaw, it)
  local c = (it.lo + it.hi) / 2
  return it.tur and W.fromTur(d, c, yaw) or c
end

-- 一锥破片的方向（确定的伪随机：服务器、客户端回放画出来一样）：axis 弹道方向、half 半角（度）、n 根、seed
function W.cone(axis, half, n, seed)
  local out = {}
  local up = math.abs(axis.Y) < 0.9 and V(0, 1, 0) or V(1, 0, 0)
  local r1 = axis:Cross(up).Unit
  local r2 = axis:Cross(r1).Unit
  local s = (seed or 1) % 2147483647
  local function rnd() s = (s * 16807) % 2147483647 return s / 2147483647 end
  for i = 1, n do
    local a = rnd() * math.pi * 2
    local t = math.rad(half) * math.sqrt(rnd())
    local dv = (axis * math.cos(t) + (r1 * math.cos(a) + r2 * math.sin(a)) * math.sin(t)).Unit
    out[i] = dv
  end
  return out
end

-- 名字（客户端界面）：模块 / 乘员的中文名用 Lang 的 wt.<k>
W.MODS = { "engine", "trans", "trackL", "trackR", "barrel", "breech", "tdrive", "ammo", "ammoH", "fuelL", "fuelR", "troops" }
W.M = M
return W
