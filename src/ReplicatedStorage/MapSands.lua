--!native
-- 全面大战场地图「沙海」（ReplicatedStorage.MapSands，地图 id "sands"）：海湾战争式的纯陆地沙漠，纯数学，服务器、客户端算出来一样
--   （Map.use("sands") 换进 Map 表；另一张沙漠「沙漠风暴」是 MapDesert，两个会话同一天各做了一张，用户 11-22 说两张都留，开局选图）
--   用户 11-22：「要一个比它大十倍的沙漠地图」「沙漠怎么可能有水」「整个重做，纯地面和空军对战的海湾战争」——
--   地形范围 ±38912 格（约 27.8 公里见方，岛图 ±12288 的 10 倍面积），没有海、没有水：红方（攻方）从南边的前进基地、前进机场北上，
--   越过边境沙墙和反坦克壕，打边境哨所 A、油田 B、镇子 C、蓝方空军基地 D、山岭上的指挥部 E；蓝方后方营地在岭北。
--   地貌照科威特—伊拉克南部：大片平的沙砾平原、一道东西向的岩岭（山口过公路）、西边一条大干河谷和西沙海、东边的干盐碱滩、
--   南边、东南的新月形沙丘、北边远处一道断崖台地；公路：南北向的 80 号公路（穿过镇子、翻过山口）、东西向的 6 号公路。
--   开服写地形（World.lua）：平原、台地、盐碱滩是正好落在体素边界上的平地，整块 FillBlock（便宜、省内存）；
--   有起伏的块（Map.chunkKind 说是 relief 的）才逐列写体素，先写核心区，外面的在后台慢慢写
local Map = {}
local exp, abs, sin, cos, sqrt, max, min, floor = math.exp, math.abs, math.sin, math.cos, math.sqrt, math.max, math.min, math.floor
local atan2 = math.atan2
local noise = math.noise

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
Map.clamp, Map.smooth, Map.lerp = clamp, smooth, lerp

Map.NAME = "sands"
Map.DESERT = true
Map.LANDONLY = true     -- 没有海：舰艇、登陆艇、海滩那一套都不用（各模块按它跳过）
local K, HK = 3, 2      -- 同岛图（别的模块按 K 定网格、范围：核心区和岛图差不多大）
Map.K, Map.HK = K, HK
Map.R = 38912           -- 地形范围 ±R：岛图 ±12288 的 √10 倍，面积 10 倍
Map.PLAY = 36864        -- 飞机的作战区（再往外自动掉头）
Map.SEA_R = 45056       -- 地形再往外铺一圈平地（只是远景）：作战区边上往外看不到地形的尽头（名字沿用岛图的）
Map.SEA_LIM = 0
Map.SEA_DEPTH = 0
Map.SHELF = 0
Map.MAXH = 290 * HK
Map.RES = 4
-- 平地的高度（都是 4 的倍数：最上面一层体素正好满，FillBlock 填出来和逐列写的一样高）
local PLAIN, PLATEAU, LOW = 12, 72, 8
Map.PLAIN, Map.PLATEAU, Map.LOW = PLAIN, PLATEAU, LOW
local MAT = Enum.Material
local LEVEL_MAT = { [PLAIN] = MAT.Sand, [PLATEAU] = MAT.Limestone, [LOW] = MAT.Salt }
-- 地形颜色（World.lua 写地形前 SetMaterialColor）：暖沙色的平原、赭红的砂岩、灰白的石灰岩台地、白的盐壳
Map.COLORS = {
  Sand = Color3.fromRGB(206, 174, 124), Ground = Color3.fromRGB(156, 128, 96), Rock = Color3.fromRGB(108, 90, 76),
  Sandstone = Color3.fromRGB(176, 118, 80), Limestone = Color3.fromRGB(198, 182, 150), Salt = Color3.fromRGB(226, 220, 204),
  Slate = Color3.fromRGB(96, 84, 74), Asphalt = Color3.fromRGB(56, 55, 56), Concrete = Color3.fromRGB(152, 148, 140),
}

---------------------------------------------------------------- 随机数（定死的种子：服务器、客户端、每局都一样）

local function rng(seed)
  local s = seed % 2147483647
  if s <= 0 then s += 2147483646 end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

---------------------------------------------------------------- 锚点

Map.REDBASE = { x = 0, z = 15500 }                                   -- 红方前进基地（攻方出生、地面载具）
Map.AFIELD2 = { x = 0, z = 17600, len = 3300, wid = 90, rot = 0 }   -- 红方前进机场（陆基飞机）
Map.AIRFIELD = { x = 3400, z = -5200, len = 3600, wid = 90, rot = 0 } -- 蓝方空军基地（据点 D）
Map.CAMP = { x = -200, z = -15000 }                                  -- 蓝方后方营地（岭北）
Map.TOWN = { x = -3800, z = -600 }                                   -- 镇子（据点 C）
Map.OILFIELD = { x = 5200, z = 2600 }                                -- 油田（据点 B）
Map.PORT = Map.TOWN   -- 岛图的「港口镇」那一套（据点 C）读这个

-- 穆特拉式岩岭：东西向，南坡陡（崖）、北坡缓；80 号公路从山口翻过去，指挥部在山口西边的岭顶上
local function ridgeZ(x) return -9300 + 500 * sin(x / 4100 + 0.6) + 160 * sin(x / 1300 + 2.0) end
Map.ridgeZ = ridgeZ
Map.COMMAND = { x = -600, z = ridgeZ(-600) - 120 }
-- 边境沙墙（东西向一道 3 米多高的沙堤，南边一条反坦克壕）：公路、几条土路的地方开口
local function bermZ(x) return 7600 + 120 * sin(x / 3100 + 1.1) + 40 * sin(x / 900 + 0.3) end
Map.bermZ = bermZ
local BREACH = { -1200, 6200, -9000, 13500, -22000, 24000 }
Map.BREACH = BREACH

Map.POINTS = {
  { id = "A", x = -1200, z = 7050 },                                -- 边境哨所：沙墙开口北边
  { id = "B", x = Map.OILFIELD.x, z = Map.OILFIELD.z },
  { id = "C", x = Map.TOWN.x, z = Map.TOWN.z },
  { id = "D", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z - 360 },       -- 机场北面的停机坪、塔台一带
  { id = "E", x = Map.COMMAND.x, z = Map.COMMAND.z },
}
Map.POINT_R = 80
for _, p in ipairs(Map.POINTS) do p.land = "main" end
-- 岛图的海上那一套：这张图没有
Map.FLEET, Map.BEACHES, Map.LANDINGS, Map.ISLES, Map.CAPES = {}, {}, {}, {}, {}
Map.BARGE = nil
function Map.landingOf() return nil end
function Map.landOf() return "main" end
function Map.beachAt() return nil end
function Map.coastS() return nil end
function Map.coastN() return nil end
function Map.inHarbor() return false end
-- 红方地面部队的出发阵地（岛图的登陆点那一层意思）：前进基地北边一排
Map.STARTS = {}
for i, x in ipairs({ -3600, -1200, 1200, 3600 }) do table.insert(Map.STARTS, { id = "s" .. i, x = x, z = 12500 }) end

---------------------------------------------------------------- 起伏（各自一个外包盒，按 1024 格的格子登记：查高度只看这一格里的）

local FEAT = {}
Map.FEAT = FEAT
local FCELL = 1024
local fgrid = {}
local function fkey(gx, gz) return (gx + 256) * 1024 + (gz + 256) end
local function addFeat(f)
  table.insert(FEAT, f)
  for gx = floor(f.x0 / FCELL), floor(f.x1 / FCELL) do
    for gz = floor(f.z0 / FCELL), floor(f.z1 / FCELL) do
      local k = fkey(gx, gz)
      local l = fgrid[k]
      if not l then l = {} fgrid[k] = l end
      table.insert(l, f)
    end
  end
  return f
end
local function featIn(x0, z0, x1, z1)
  for gx = floor(x0 / FCELL), floor(x1 / FCELL) do
    for gz = floor(z0 / FCELL), floor(z1 / FCELL) do
      local l = fgrid[fkey(gx, gz)]
      if l then
        for _, f in ipairs(l) do
          if f.x1 >= x0 and f.x0 <= x1 and f.z1 >= z0 and f.z0 <= z1 then return true end
        end
      end
    end
  end
  return false
end
local ZERO = function() return 0 end

-- 岩岭
local function ridgeH(f, x, z)
  local ends = smooth(-15500, -12500, x) * (1 - smooth(11000, 14000, x))
  if ends <= 0 then return 0 end
  local s = ridgeZ(x) - z            -- 正 = 岭线北边
  local W = (s < 0) and 210 or 800   -- 南坡陡、北坡缓
  local q = s / W
  local q2 = q * q
  if q2 > 5 then return 0 end
  local pass = 1 - 0.78 * exp(-((x - 300) / 520) ^ 2)
  local H = 150 * ends * pass * (0.85 + 0.25 * noise(x / 2600, 0.5, 4.4))
  local core = exp(-q2) * (1 - smooth(3.4, 5, q2))
  local gully = (s < 0) and (1 - abs(noise(x / 140, z / 140, 7.3))) or 0.5   -- 南坡上一道道冲沟
  return H * core * (0.86 + 0.22 * gully) + H * core * 0.06 * noise(x / 60, z / 60, 2.2)
end
addFeat({ k = "rock", fn = ridgeH, x0 = -15600, z0 = -12200, x1 = 14100, z1 = -8200 })

-- 边境沙墙 + 反坦克壕（负的高度：壕沟）；开口处没有
local function bermH(f, x, z)
  local zb = bermZ(x)
  local dz = z - zb
  if dz < -40 or dz > 80 then return 0 end
  local gap = 1
  for _, bx in ipairs(BREACH) do
    local q = (x - bx) / 70
    if q * q < 9 then gap = min(gap, 1 - exp(-q * q * q * q)) end
  end
  if gap <= 0.001 then return 0 end
  local h = 0
  if dz < 22 then h = 11 * max(0, 1 - (dz / 22) ^ 2) end                -- 沙堤：底宽 44 格
  local dd = (dz - 46) / 13
  if dd * dd < 1 then h -= 6.5 * (1 - dd * dd) end                     -- 壕沟：沙堤南边，宽 26、深 6.5（V 形）
  return h * gap
end
for x = -Map.R, Map.R - 512, 512 do
  local za, zb = bermZ(x), bermZ(x + 512)
  addFeat({ k = "berm", fn = bermH, signed = true, x0 = x, z0 = min(za, zb) - 50, x1 = x + 512, z1 = max(za, zb) + 90 })
end

-- 方山 / 残丘：平顶、陡崖、崖脚一圈碎石坡
local function mesaH(f, x, z)
  local dx, dz = x - f.x, z - f.z
  local rho = sqrt(dx * dx + dz * dz)
  if rho > f.R then return 0 end
  local th = atan2(dz, dx)
  local r = f.r * (1 + 0.16 * sin(3 * th + f.ph) + 0.08 * sin(5 * th + 2 * f.ph) + 0.05 * sin(11 * th + 3 * f.ph)) + f.r * 0.05 * noise(x / 90, z / 90, f.ph)
  local top = f.h * (1 - 0.05 * (rho / max(r, 1)) ^ 2)
  if rho <= r then return top end
  local c = rho - r
  if c < f.cliff then return top * (1 - 0.74 * smooth(0, f.cliff, c)) end
  local t = (c - f.cliff) / f.talus
  if t >= 1 then return 0 end
  return top * 0.26 * (1 - t) ^ 1.6
end
local function addMesa(x, z, r, h, ph)
  local cliff, talus = max(14, h * 0.32), h * 1.25
  local R = r * 1.35 + cliff + talus + 20
  return addFeat({ k = "mesa", fn = mesaH, x = x, z = z, r = r, h = h, ph = ph or (x * 0.001 + z * 0.0007) % 6.28, cliff = cliff, talus = talus, R = R,
    x0 = x - R, z0 = z - R, x1 = x + R, z1 = z + R })
end
-- 岩丘（平原上零星的风化岩包）
local function rockH(f, x, z)
  local dx, dz = x - f.x, z - f.z
  local q = (dx * dx + dz * dz) / (f.r * f.r)
  if q >= 1 then return 0 end
  local n = noise(x / (f.r * 0.45), z / (f.r * 0.45), f.ph)
  return f.h * (1 - q) ^ 0.7 * (0.75 + 0.35 * n)
end
local function addRock(x, z, r, h, ph)
  return addFeat({ k = "rock", fn = rockH, x = x, z = z, r = r, h = h, ph = ph or 0.9, x0 = x - r, z0 = z - r, x1 = x + r, z1 = z + r })
end
-- 沙丘带：纵向沙垄（顺着西北风「沙马尔风」，走向西北—东南），垄距 sp、高 H；迎风坡缓、落沙坡陡，弯曲、分叉，越到边上越矮
local function ergH(f, x, z)
  local dx, dz = x - f.x, z - f.z
  local ex, ez = (dx * f.ec + dz * f.es) / f.ax, (-dx * f.es + dz * f.ec) / f.az
  local q = ex * ex + ez * ez
  if q >= 1 then return 0 end
  local mask = 1 - smooth(0.5, 1, q)
  local u = dx * f.uc + dz * f.us
  local v = -dx * f.us + dz * f.uc
  local w = noise(v / 2600, u / 2600, f.ph) * 0.45 + noise(v / 900, u / 900, f.ph + 3) * 0.12 + noise(v / 420, u / 560, f.ph + 5) * 0.3   -- 沙梁顶线弯弯曲曲
  local t = u / f.sp + w
  t -= floor(t)
  local c = 0.68
  local p = (t < c) and (t / c) ^ 1.35 or (1 - (t - c) / (1 - c)) ^ 0.75
  p = p * p * (3 - 2 * p)
  -- 沿走向一段高一段低、有的地方断开，相邻两道高矮不一（原来间距、高度都匀，看着像一道道条纹）
  local seg = smooth(-0.3, 0.35, noise(v / 620, u / 880, f.ph + 7))
  local amp = (0.35 + 0.65 * seg) * clamp(0.8 + 0.5 * noise(u / 640, v / 2200, f.ph + 9), 0.45, 1.15)
  return f.H * mask * p * amp * (0.86 + 0.14 * noise(x / 160, z / 160, f.ph + 11))
end
local function addErg(x, z, ax, az, rot, H, sp, crest, ph)
  local R = max(ax, az) + 40
  local cr = crest or 0.75   -- 沙垄走向（弧度，0 = 正南北）
  return addFeat({ k = "dune", fn = ergH, x = x, z = z, ax = ax, az = az, ec = cos(rot), es = sin(rot), H = H, sp = sp,
    uc = cos(cr), us = sin(cr), ph = ph or 2.2, x0 = x - R, z0 = z - R, x1 = x + R, z1 = z + R })
end
local function starH(f, x, z)
  local dx, dz = x - f.x, z - f.z
  local rho = sqrt(dx * dx + dz * dz)
  if rho > f.r then return 0 end
  local th = atan2(dz, dx)
  local arms = 0.5 + 0.5 * cos(f.n * th + f.ph + 0.7 * sin(rho / 240 + f.ph))
  local k = rho / f.r
  return f.H * (1 - k) ^ 1.6 * (0.42 + 0.58 * arms * arms) * (0.9 + 0.1 * noise(x / 120, z / 120, f.ph))
end
local function addStar(x, z, r, H, n, ph)
  return addFeat({ k = "dune", fn = starH, x = x, z = z, r = r, H = H, n = n or 4, ph = ph or 0.4, x0 = x - r, z0 = z - r, x1 = x + r, z1 = z + r })
end
-- 新月形沙丘：两角朝下风（东南：沙马尔风从西北吹来），迎风坡缓、落沙坡陡
local WIND = math.rad(135)
local function barchanH(f, x, z)
  local dx, dz = x - f.x, z - f.z
  local a = dx * f.c + dz * f.s
  local b = -dx * f.s + dz * f.c
  local an = a / f.w
  if an > 1 or an < -1 then return 0 end
  local bn = (b - f.l * 0.55 * an * an) / f.l
  if bn < -1 or bn > 0.42 then return 0 end
  local prof = (bn < 0) and (1 + bn) ^ 1.3 or (1 - bn / 0.42) ^ 0.6
  return f.H * prof * (1 - an * an) ^ 0.8
end
local function addBarchan(x, z, w, l, H)
  local ang = WIND + math.pi / 2
  local R = max(w, l * 1.6) + 20
  return addFeat({ k = "dune", fn = barchanH, x = x, z = z, w = w, l = l, H = H, c = cos(ang), s = sin(ang), x0 = x - R, z0 = z - R, x1 = x + R, z1 = z + R })
end

---------------------------------------------------------------- 断崖台地（远处北边）、盐碱滩

local R0 = Map.R
local function escRaw(x) return -24500 + 1300 * sin(x / 6600 + 0.9) + 460 * sin(x / 2300 + 2.6) + 170 * sin(x / 770 + 4.4) - 24000 * smooth(R0 - 12000, R0 + 3000, abs(x)) end
local EX0, ESTEP = -Map.SEA_R - 64, 16
local EN = floor((2 * Map.SEA_R + 128) / ESTEP)
local e1 = table.create(EN + 1)
for i = 0, EN do e1[i + 1] = escRaw(EX0 + i * ESTEP) end
local function escAt(x)
  local f = clamp((x - EX0) / ESTEP, 0, EN - 1e-6)
  local i = floor(f)
  local a = f - i
  return e1[i + 1] * (1 - a) + e1[i + 2] * a
end
Map.escZ = escAt
local E1 = { H = PLATEAU - PLAIN, cliff = 70, talus = 260 }
local PASSES = { -12000, -700, 15000, 27000 }   -- 断崖上的坡道（崖面拉成一公里多的缓坡，车开得上去）
Map.PASSES = PASSES
local function cliffW(x)
  local w = E1.cliff
  for _, px in ipairs(PASSES) do
    local q = (x - px) / 420
    if q * q < 16 then w += 1250 * exp(-q * q) end
  end
  return w
end
local ESC_PAD = 420
local function escProf(s, cw)
  local tal = E1.talus * (1 - 0.8 * smooth(E1.cliff, E1.cliff + 600, cw))
  if s <= -tal then return 0 end
  if s < 0 then return 0.3 * (1 - (-s / tal)) ^ 1.5 end
  if s < cw then return 0.3 + 0.7 * ((cw > 200) and (s / cw) or smooth(0, cw, s)) end
  return 1
end
for x = -Map.SEA_R, Map.SEA_R, 512 do
  local za, zb = escAt(x), escAt(x + 512)
  if min(za, zb) > -Map.SEA_R - 600 then
    local cw = max(cliffW(x), cliffW(x + 512), cliffW(x + 256))
    addFeat({ k = "esc", fn = ZERO, x0 = x, z0 = min(za, zb) - ESC_PAD - cw, x1 = x + 512, z1 = max(za, zb) + ESC_PAD })
  end
end

-- 盐碱滩（干的：一层白盐壳，比平原低 4 格，边上一圈缓坡）
local SAB = { x = 16500, z = -2500, ax = 5200, az = 2800, rot = 0.2 }
SAB.c, SAB.s = cos(SAB.rot), sin(SAB.rot)
Map.SABKHA = SAB
local function sabQ(x, z)
  local dx, dz = x - SAB.x, z - SAB.z
  local u, v = (dx * SAB.c + dz * SAB.s) / SAB.ax, (-dx * SAB.s + dz * SAB.c) / SAB.az
  local th = atan2(v, u)
  local wob = 1 + 0.07 * sin(3 * th + 1.1) + 0.04 * sin(7 * th + 2.3) + 0.02 * sin(13 * th + 0.4)
  return sqrt(u * u + v * v) / wob
end
do
  local steps = 120
  for i = 0, steps - 1 do
    local a = i / steps * math.pi * 2
    local px, pz = cos(a) * SAB.ax, sin(a) * SAB.az
    local x = SAB.x + px * SAB.c - pz * SAB.s
    local z = SAB.z + px * SAB.s + pz * SAB.c
    addFeat({ k = "sab", fn = ZERO, x0 = x - 560, z0 = z - 560, x1 = x + 560, z1 = z + 560 })
  end
end

-- 平地的高度（断崖、盐碱滩），第二个返回值：在哪一级（PLAIN / PLATEAU / LOW；在崖上、滩边返回 nil）
local function baseLevel(x, z)
  local L, flat = PLAIN, PLAIN
  local s1 = escAt(x) - z
  if s1 > -E1.talus - 160 then
    local cw = cliffW(x)
    local en = (70 * noise(x / 380, z / 380, 6.6) + 30 * noise(x / 120, z / 120, 2.4)) * (1 - smooth(E1.cliff, E1.cliff + 400, cw))
    local p = escProf(s1 + en, cw)
    L += E1.H * p
    if p >= 1 then flat = PLATEAU elseif p > 0 then flat = nil end
  else
    local q = sabQ(x, z)
    if q < 1.1 then
      local k = 1 - smooth(0.88, 1.08, q)
      L -= (PLAIN - LOW) * k
      if k >= 1 then flat = LOW elseif k > 0 then flat = nil end
    end
  end
  return L, flat
end
Map.baseLevel = baseLevel

---------------------------------------------------------------- 布局

-- 核心区：坦克交战的低沙梁（车能藏在后面露个炮塔）、岩丘
addErg(200, 3700, 3000, 950, 0.05, 15, 270, 0.75, 5.1)     -- 边境哨所和镇子、油田之间的一片低沙梁
addErg(-5600, 9800, 1800, 900, -0.1, 12, 240, 0.75, 6.3)   -- 沙墙南边（红方的进攻出发阵地西边）
for _, r in ipairs({ { 1900, 5600, 130, 30 }, { -2900, 5200, 160, 36 }, { 3700, 600, 110, 26 }, { -6200, 2500, 170, 40 },
  { 7800, -1500, 150, 34 }, { -1500, -3200, 120, 28 }, { 6200, -8200, 180, 44 }, { -7000, -6800, 200, 48 },
  { 9400, 5200, 140, 30 }, { -4300, 11800, 120, 24 } }) do
  addRock(r[1], r[2], r[3], r[4], r[1] * 0.01)
end
addMesa(-8400, -4300, 420, 96, 0.8)    -- 镇子西北的方山（侦察兵、狙击手的高地）
addMesa(9800, -7200, 360, 88, 2.4)
-- 西沙海（巴廷干河西边：纵向沙垄 + 星状沙丘）
addErg(-25500, -7000, 5000, 3300, 0.6, 62, 720, 0.75, 2.2)
addStar(-26000, -7800, 900, 150, 4, 0.4)
addStar(-23600, -5900, 760, 120, 5, 1.9)
addStar(-27800, -5600, 700, 112, 3, 3.1)
addStar(-24800, -9600, 820, 132, 4, 4.6)
-- 东南的新月形沙丘、南边沙墙前零星几个
do
  local R = rng(77001)
  for _ = 1, 54 do
    local s = 0.6 + R() * 1.1
    addBarchan(11000 + R() * 22000, 7000 + R() * 19000, 150 * s, 190 * s, 11 + 15 * s)
  end
  for _ = 1, 16 do
    local s = 0.5 + R() * 0.8
    local x, z = -7000 + R() * 14000, 9200 + R() * 4500
    if abs(x - Map.REDBASE.x) > 1600 or abs(z - Map.REDBASE.z) > 1100 then addBarchan(x, z, 130 * s, 160 * s, 9 + 10 * s) end
  end
end
-- 东北、西南远处的方山群（飞机上看得见的地标）
do
  local R = rng(20261122)
  local placed = {}
  local function field(x0, z0, w, d, n)
    local cnt, tries = 0, 0
    while cnt < n and tries < 400 do
      tries += 1
      local x, z = x0 + R() * w, z0 + R() * d
      local r = 140 + R() ^ 1.8 * 760
      local h = 70 + R() * 170 * (0.6 + r / 1200)
      local ok = abs(z - escAt(x)) > r * 1.6 + 900
      for _, p in ipairs(placed) do
        if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < (r + p[3] + 900) ^ 2 then ok = false break end
      end
      if ok then table.insert(placed, { x, z, r, h }) cnt += 1 end
    end
  end
  field(14000, -21000, 15000, 11000, 12)
  field(-36000, 16000, 12000, 14000, 8)
  for _, p in ipairs(placed) do addMesa(p[1], p[2], p[3], p[4]) end
  Map.MESAFIELD = placed
end
for _, b in ipairs({ { -5200, -23400, 280, 90 }, { 4400, -23900, 300, 104 }, { 11200, -22600, 220, 80 }, { -15800, -23000, 340, 96 } }) do
  addMesa(b[1], b[2], b[3], b[4])   -- 断崖前面孤立的残丘
end

---------------------------------------------------------------- 干河谷（折线：宽、深；按 512 格的格子登记线段）

local WADIS = {
  -- 巴廷干河：西南往东北斜穿过来，再往北收进断崖
  { name = "巴廷干河", w = 520, d = 26, p = { -38500, 31000, -30000, 22000, -24000, 14200, -19200, 7200, -15600, 200, -13900, -7000,
    -13600, -14000, -14600, -21500, -15000, -25500 } },
  { name = "西干河", w = 210, d = 12, p = { -5000, -8700, -6400, -6500, -6000, -4000, -7400, -1500, -7000, 1800, -8600, 5000, -9200, 7700, -10200, 11200 } },
}
Map.WADIS = WADIS
local WCELL = 512
local wgrid = {}
for wi, W in ipairs(WADIS) do
  local p = W.p
  for i = 1, #p / 2 - 1 do
    local ax, az, bx, bz = p[2 * i - 1], p[2 * i], p[2 * i + 1], p[2 * i + 2]
    local s = { ax, az, bx, bz, W.w, W.d, wi }
    local pad = W.w + 60
    for gx = floor((min(ax, bx) - pad) / WCELL), floor((max(ax, bx) + pad) / WCELL) do
      for gz = floor((min(az, bz) - pad) / WCELL), floor((max(az, bz) + pad) / WCELL) do
        local k = (gx + 512) * 2048 + gz + 512
        local l = wgrid[k]
        if not l then l = {} wgrid[k] = l end
        table.insert(l, s)
      end
    end
    addFeat({ k = "wadi", fn = ZERO, x0 = min(ax, bx) - pad, z0 = min(az, bz) - pad, x1 = max(ax, bx) + pad, z1 = max(az, bz) + pad })
  end
end
local function wadiNear(x, z)
  local l = wgrid[(floor(x / WCELL) + 512) * 2048 + floor(z / WCELL) + 512]
  if not l then return nil end
  local best, bw, bd = 1e18, 0, 0
  for _, s in ipairs(l) do
    local ax, az, bx, bz = s[1], s[2], s[3], s[4]
    local dx, dz = bx - ax, bz - az
    local L2 = dx * dx + dz * dz
    local t = clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
    local px, pz = ax + dx * t, az + dz * t
    local L = sqrt(L2)
    local nx, nz = -dz / L, dx / L
    local m = s[5] * 0.9 * noise((px + pz) / 700, s[7] * 3.1, 0.5)   -- 河道摆动
    px += nx * m pz += nz * m
    local dd = (x - px) ^ 2 + (z - pz) ^ 2
    if dd < best then best, bw, bd = dd, s[5], s[6] end
  end
  return sqrt(best), bw, bd
end
Map.wadiNear = wadiNear

---------------------------------------------------------------- 自然高度

-- 返回高度、主要起伏的种类（材质用）
local function natural(x, z)
  local L = baseLevel(x, z)
  local kind, bump, cut, kmax = nil, 0, 0, nil
  local l = fgrid[fkey(floor(x / FCELL), floor(z / FCELL))]
  if l then
    for _, f in ipairs(l) do
      if x >= f.x0 and x <= f.x1 and z >= f.z0 and z <= f.z1 then
        local h = f.fn(f, x, z)
        if h > bump then bump, kmax = h, f.k
        elseif f.signed and h < cut then cut = h if bump <= 0 then kind = f.k end end
      end
    end
  end
  -- 地貌种类（定材质用）：起伏够高（1 格上下，边缘按噪声抖开）才算——不然岩岭、方山脚下高度几乎为零的一圈也换成土，
  --   在地图上是一道道笔直的材质边（包围盒的边）
  if kmax and bump > 1.2 + 0.8 * noise(x / 90, z / 90, 8.8) then kind = kmax end
  local y = L + bump + cut
  local wd, ww, wdep = wadiNear(x, z)
  if wd and wd < ww * 0.5 + 40 then
    local floorW = ww * 0.32
    local c = wdep * (1 - smooth(floorW, ww * 0.5 + 40, wd))
    y -= c
    if c > 1 then kind = (wd < floorW + 10) and "wadi" or "wadibank" end
  end
  return max(y, 1.5), kind
end

---------------------------------------------------------------- 压平的场地

local FLAT = {}
local function addFlat(x, z, r, r2, y) table.insert(FLAT, { x = x, z = z, r = r, r2 = r2, y = y, x0 = x - r2, z0 = z - r2, x1 = x + r2, z1 = z + r2 }) end
local function addRect(x, z, hx, hz, m, y) table.insert(FLAT, { x = x, z = z, hx = hx, hz = hz, m = m, y = y, rect = true, x0 = x - hx - m, z0 = z - hz - m, x1 = x + hx + m, z1 = z + hz + m }) end
Map.FLAT = FLAT

local function flatHeight(x, z)
  local y, kind = natural(x, z)
  local wmax = 0
  for _, F in ipairs(FLAT) do
    if x >= F.x0 and x <= F.x1 and z >= F.z0 and z <= F.z1 then
      local dx, dz = x - F.x, z - F.z
      local w = 0
      if F.rect then
        local qx, qz = max(0, abs(dx) - F.hx), max(0, abs(dz) - F.hz)
        if qx < F.m and qz < F.m then w = 1 - smooth(0, F.m, sqrt(qx * qx + qz * qz)) end
      else
        local q = dx * dx + dz * dz
        if q < F.r2 * F.r2 then w = 1 - smooth(F.r, F.r2, sqrt(q)) end
      end
      if w > 0 then
        y = lerp(y, F.y, w)
        if w > wmax then wmax = w end
      end
    end
  end
  return y, wmax, kind
end

local function avgNatural(x, z, r)
  local sum, n = natural(x, z), 1
  for k = 0, 11 do
    local a = k * math.pi / 6
    for _, rr in ipairs({ r * 0.5, r }) do
      sum += natural(x + cos(a) * rr, z + sin(a) * rr)
      n += 1
    end
  end
  return sum / n
end
for _, p in ipairs(Map.POINTS) do
  if p.id == "C" then addFlat(p.x, p.z, 420, 820, avgNatural(p.x, p.z, 420))   -- 镇子大一些
  elseif p.id ~= "D" then addFlat(p.x, p.z, 165, 330, avgNatural(p.x, p.z, 165)) end
end
do local A = Map.AIRFIELD addRect(A.x, A.z - 120, A.len / 2 + 50, 380, 240, avgNatural(A.x, A.z - 120, 600)) end   -- 跑道 + 北面停机坪、机库
do local C = Map.CAMP addRect(C.x, C.z + 45, 600, 255, 300, avgNatural(C.x, C.z, 210)) end
do local A = Map.AFIELD2 addRect(A.x, A.z, A.len / 2 + 20, 210, 180, avgNatural(A.x, A.z, 400)) end
do local B = Map.REDBASE addRect(B.x, B.z, 700, 400, 300, avgNatural(B.x, B.z, 300)) end

---------------------------------------------------------------- 路网（手画的折线）

local ROADDEF = {
  -- 80 号公路（「死亡公路」）：红方前进基地 → 沙墙开口 → 镇子 → 山口 → 蓝方营地 → 断崖坡道
  { name = "80号公路", w = 22, p = { 0, 23000, -300, 17000, -1200, 13000, -1200, 7600, -1800, 4500, -3000, 1500, -3800, -600, -2600, -4000,
    -600, -7200, 300, -9200, 100, -11500, -200, -14700, -500, -19000, -700, -23400, -700, -26400 } },
  -- 6 号公路：东西向，穿过镇子、油田
  { name = "6号公路", w = 22, p = { -40000, 900, -26000, 700, -18000, 300, -8000, -300, -3800, -600, 1500, 1200, 5200, 2600, 12000, 3200,
    24000, 2400, 40000, 3600 } },
  { name = "机场公路", w = 16, p = { -2600, -4000, 500, -4400, 1550, -4900 } },
  { name = "油田—前进基地", w = 12, p = { 5200, 2600, 5800, 4800, 6200, 7600, 5000, 11800, 2200, 15400, 700, 15500 } },
  { name = "指挥部", w = 12, p = { 300, -9200, -200, -9150, -600, -9100 } },
  { name = "前进机场", w = 16, p = { 0, 15500, 0, 16700 } },
  { name = "西干河土路", w = 10, p = { -3800, -600, -6000, -900, -9000, 7700, -10500, 12500, -3000, 15000, -700, 15400 } },
  { name = "东边土路", w = 10, p = { 5200, 2600, 9800, -1500, 13500, 7600, 17000, 12000 } },
}
local SX0, SZ0, SX1, SZ1, SY0, SY1, SW = {}, {}, {}, {}, {}, {}, {}
local RCELL = 48
local rgrid = {}
local ROADS = {}
Map.ROADS = ROADS
local RBIG = 512
local rbig = {}
for _, r in ipairs(ROADDEF) do
  local xs, zs = {}, {}
  local p = r.p
  for i = 1, #p / 2 - 1 do
    local ax, az, bx, bz = p[2 * i - 1], p[2 * i], p[2 * i + 1], p[2 * i + 2]
    local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local n = max(1, floor(L / 40))
    for k = 0, n - 1 do
      table.insert(xs, ax + (bx - ax) * k / n)
      table.insert(zs, az + (bz - az) * k / n)
    end
  end
  table.insert(xs, p[#p - 1]) table.insert(zs, p[#p])
  local n = #xs
  local ys = table.create(n)
  for i = 1, n do ys[i] = (flatHeight(xs[i], zs[i])) end
  local base = table.clone(ys)
  for _ = 1, 14 do
    local nys = table.clone(ys)
    for i = 2, n - 1 do nys[i] = ys[i - 1] * 0.25 + ys[i] * 0.5 + ys[i + 1] * 0.25 end
    ys = nys
  end
  for i = 1, n do ys[i] = clamp(ys[i], base[i] - 10, base[i] + 10) end
  table.insert(ROADS, { name = r.name, w = r.w, x = xs, z = zs, y = ys })
  for i = 1, n - 1 do
    local k = #SX0 + 1
    SX0[k], SZ0[k], SX1[k], SZ1[k], SY0[k], SY1[k], SW[k] = xs[i], zs[i], xs[i + 1], zs[i + 1], ys[i], ys[i + 1], r.w
    local pad = r.w * 0.5 + 12
    for gx = floor((min(xs[i], xs[i + 1]) - pad) / RCELL), floor((max(xs[i], xs[i + 1]) + pad) / RCELL) do
      for gz = floor((min(zs[i], zs[i + 1]) - pad) / RCELL), floor((max(zs[i], zs[i + 1]) + pad) / RCELL) do
        local key = (gx + 2048) * 4096 + gz + 2048
        local list = rgrid[key]
        if not list then list = {} rgrid[key] = list end
        table.insert(list, k)
      end
    end
    for gx = floor((min(xs[i], xs[i + 1]) - pad) / RBIG), floor((max(xs[i], xs[i + 1]) + pad) / RBIG) do
      for gz = floor((min(zs[i], zs[i + 1]) - pad) / RBIG), floor((max(zs[i], zs[i + 1]) + pad) / RBIG) do
        rbig[(gx + 512) * 2048 + gz + 512] = true
      end
    end
  end
end
local function roadNear(x, z)
  local list = rgrid[(floor(x / RCELL) + 2048) * 4096 + floor(z / RCELL) + 2048]
  if not list then return nil end
  local best, bw = 1e18, 0
  local sw, sy = 0, 0
  for _, k in ipairs(list) do
    local ax, az = SX0[k], SZ0[k]
    local dx, dz = SX1[k] - ax, SZ1[k] - az
    local L2 = dx * dx + dz * dz
    local t = (L2 > 0) and clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1) or 0
    local px, pz = ax + dx * t - x, az + dz * t - z
    local dd = px * px + pz * pz
    if dd < best then best, bw = dd, SW[k] end
    local reach = SW[k] * 0.5 + 12
    if dd < reach * reach then
      local dist = sqrt(dd)
      local w = (1 - dist / reach) ^ 2 / (1 + dist)
      sw += w
      sy += w * (SY0[k] + (SY1[k] - SY0[k]) * t)
    end
  end
  if best >= 1e18 then return nil end
  return sqrt(best), (sw > 0) and sy / sw or 0, bw
end
Map.roadNear = roadNear
function Map.roadDist(x, z)
  local d = roadNear(x, z)
  return d or 1e9
end

---------------------------------------------------------------- 高度、地面

-- 写地形时的列缓存（World.lua 的 writeChunk 先算一块里每列的高度，再一列列定材质）：height 记下压平系数、地貌种类、离路多远，
--   material 就不用把整列高度再算一遍（开服写地形省一半多时间）；只在 Map.colCache(true) 和 (false) 之间开着
local CC = nil
function Map.colCache(on) CC = on and {} or nil end
function Map.height(x, z)
  local y, wf, kind = flatHeight(x, z)
  local rd, ry, rw = roadNear(x, z)
  if CC then CC[x * 131072 + z] = { wf, kind, rd or false, rw } end
  if rd then
    local half = rw * 0.5
    local w = 1 - smooth(half, half + 10, rd)
    if w > 0 then y = lerp(y, ry, w * (1 - wf)) end
  end
  return y, 1e9
end
function Map.ground(x, z) return (Map.height(x, z)) end
function Map.isLand() return true end
function Map.slope(x, z)
  local e = 4
  local a, b = Map.height(x + e, z), Map.height(x - e, z)
  local c, d = Map.height(x, z + e), Map.height(x, z - e)
  return sqrt(((a - b) / (2 * e)) ^ 2 + ((c - d) / (2 * e)) ^ 2)
end
function Map.flatW(x, z)
  local _, w = flatHeight(x, z)
  return w or 0
end
for _, p in ipairs(Map.POINTS) do p.y = Map.ground(p.x, p.z) end
for _, k in ipairs({ "AIRFIELD", "COMMAND", "CAMP", "TOWN", "OILFIELD", "AFIELD2", "REDBASE" }) do Map[k].y = Map.ground(Map[k].x, Map[k].z) end
for _, s in ipairs(Map.STARTS) do s.y = Map.ground(s.x, s.z) end

-- 油井（油田据点 B 一带、南油田）：位置定死，工事 / 场景按它摆井口、着火的井
Map.OILWELLS = {}
do
  local R = rng(31337)
  local function wells(cx, cz, w, d, n)
    local cnt, tries = 0, 0
    while cnt < n and tries < 600 do
      tries += 1
      local x, z = cx + (R() - 0.5) * w, cz + (R() - 0.5) * d
      local ok = Map.roadDist(x, z) > 40 and Map.flatW(x, z) < 0.05
      for _, q in ipairs(Map.OILWELLS) do if (q.x - x) ^ 2 + (q.z - z) ^ 2 < 180 * 180 then ok = false break end end
      if ok and Map.slope(x, z) < 0.12 then
        cnt += 1
        table.insert(Map.OILWELLS, { x = x, z = z, y = Map.ground(x, z), field = (cz > 6000) and "south" or "B" })
      end
    end
  end
  wells(Map.OILFIELD.x + 700, Map.OILFIELD.z - 300, 2800, 2000, 14)
  wells(-9500, 12800, 5200, 3600, 22)
end

---------------------------------------------------------------- 材质

function Map.material(x, z, y, slope)
  local c = CC and CC[x * 131072 + z]
  local rd, rw, wf, kind, _
  if c then
    wf, kind, rd, rw = c[1], c[2], c[3] or nil, c[4]
  else
    rd, _, rw = roadNear(x, z)
  end
  if rd and rd < rw * 0.5 + 1.2 * noise(x / 9, z / 9, 3.3) then return (rw >= 20) and MAT.Asphalt or MAT.Ground end
  if not c then _, wf, kind = flatHeight(x, z) end
  if wf and wf > 0.6 then return MAT.Ground end   -- 据点、机场、营地、基地：压实的土
  if kind == "dune" then return MAT.Sand end
  if kind == "berm" then return (y < PLAIN - 1) and MAT.Ground or MAT.Sand end
  if kind == "wadi" then return MAT.Ground end
  if kind == "wadibank" then
    if slope > 0.75 then return ((y + 3 * noise(x / 40, z / 40, 1.1)) % 9 < 3) and MAT.Limestone or MAT.Sandstone end
    return MAT.Ground
  end
  local L, flat = baseLevel(x, z)
  if kind == "mesa" or (kind == nil and flat == nil and slope > 0.7) then
    -- 方山、断崖的崖面：一层层的砂岩、石灰岩（水平的条带）；顶上砂岩
    if slope > 0.9 then return ((y + 3 * noise(x / 40, z / 40, 1.1)) % 22 < 8) and MAT.Limestone or MAT.Sandstone end
    if slope > 0.45 then return MAT.Ground end
    if kind == "mesa" then return MAT.Sandstone end
  end
  if kind == "rock" then
    if slope > 0.85 or y > 140 then return MAT.Rock end
    if slope > 0.4 then return MAT.Slate end
    return MAT.Ground
  end
  if flat == nil then
    if L < PLAIN then return MAT.Salt end
    return MAT.Ground
  end
  return LEVEL_MAT[flat] or MAT.Sand
end

---------------------------------------------------------------- 写地形（World.lua 用）

-- 一块 256 × 256 格（x0、z0 是西北角）："flat" 整块是同一级平地（返回高度、材质：FillBlock）；"relief" 要逐列写体素
local CH = 256
local function anyRoadBig(x0, z0, x1, z1)
  for gx = floor((x0 - 40) / RBIG), floor((x1 + 40) / RBIG) do
    for gz = floor((z0 - 40) / RBIG), floor((z1 + 40) / RBIG) do
      if rbig[(gx + 512) * 2048 + gz + 512] then return true end
    end
  end
  return false
end
local function anyFlatIn(x0, z0, x1, z1)
  for _, F in ipairs(FLAT) do
    if F.x1 >= x0 and F.x0 <= x1 and F.z1 >= z0 and F.z0 <= z1 then return true end
  end
  return false
end
function Map.chunkKind(x0, z0)
  local x1, z1 = x0 + CH, z0 + CH
  local cx, cz = x0 + CH / 2, z0 + CH / 2
  local candidate = featIn(x0 - 4, z0 - 4, x1 + 4, z1 + 4) or anyRoadBig(x0, z0, x1, z1) or anyFlatIn(x0, z0, x1, z1)
  local _, f0 = baseLevel(cx, cz)
  if not f0 then return "relief" end
  if not candidate then
    for _, c in ipairs({ { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } }) do
      local _, f = baseLevel(c[1], c[2])
      if f ~= f0 then return "relief" end
    end
    return "flat", f0, LEVEL_MAT[f0]
  end
  -- 外包盒碰上了起伏、路、场地：按 9 × 9 个点（间距 32 格，比路网的格子 48 小，细的土路、小沙丘都漏不掉）看是不是真的平
  local step = CH / 8
  for i = 0, 8 do
    for k = 0, 8 do
      local x, z = x0 + i * step, z0 + k * step
      local y, wf, kind = flatHeight(x, z)
      if abs(y - f0) > 0.01 or kind ~= nil or (wf and wf > 0) then return "relief" end
      local _, f = baseLevel(x, z)
      if f ~= f0 then return "relief" end
      local rd = roadNear(x, z)
      if rd and rd < 48 then return "relief" end
    end
  end
  return "flat", f0, LEVEL_MAT[f0]
end
-- 写地形的顺序：离核心区（据点、两边的基地和机场）近的先写；核心区（各处 3500 格以内，约一千块）写完才让人出生，其余的后台写
Map.CORE = { x = 0, z = -1000, r = 12000 }
Map.CORES = {}
for _, p in ipairs(Map.POINTS) do table.insert(Map.CORES, { x = p.x, z = p.z, r = 3500 }) end
for _, a in ipairs({ Map.REDBASE, Map.AFIELD2, Map.AIRFIELD, Map.CAMP }) do table.insert(Map.CORES, { x = a.x, z = a.z, r = 3500 }) end
function Map.underMat(top)   -- 最上面一层下面填什么
  if top == MAT.Sand or top == MAT.Salt then return MAT.Sand end
  if top == MAT.Rock or top == MAT.Slate then return MAT.Rock end
  if top == MAT.Sandstone or top == MAT.Limestone then return MAT.Sandstone end
  return MAT.Ground
end
function Map.farSeaOk() return false end   -- 远海平面（Scenery.lua）一块都不铺

---------------------------------------------------------------- 有陆地的范围（画中画瞄准镜的远景网格只生成核心区）

function Map.landBoxes() return { { -12000, -16500, 12000, 18500 } } end

function Map.lineClear(a, b, step)
  step = step or 12
  local dv = b - a
  local L = dv.Magnitude
  local n = max(1, floor(L / step))
  for i = 1, n - 1 do
    local p = a + dv * (i / n)
    if Map.height(p.X, p.Z) > p.Y then return false end
  end
  return true
end

-- 小地图、部署界面画多大一块（MapUI.lua）、机器人寻路网格的范围（Nav.lua）
Map.UIBOX = { x0 = -16000, z0 = -19000, x1 = 16000, z1 = 21000 }
Map.NAVBOX = { x0 = -9600, z0 = -16800, x1 = 9600, z1 = 17600 }
Map.NAVCELL = 80   -- 寻路网格（Nav.lua）：80 格一格

return Map
