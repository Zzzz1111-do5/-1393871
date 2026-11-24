-- 全面大战场地图（ReplicatedStorage.Map）：纯数学，服务器、客户端算出来一样（地形、小地图、出生点、据点都用它）
--   坐标：X 东西（东为正），Z 南北（北是 −Z），海平面 Y = 0；地形范围 ±Map.R 格，再往外的远海是客户端跟着镜头铺的平面（Scenery.lua）
--   整张图按 K 放大（用户：地图还有海洋过于小了；放大 1.5 倍后又说不够大、海洋也太小 → 3 倍）：下面的数都是放大前的「设计尺寸」，水平方向的位置、大小、起伏的波长都乘 K，高度乘 HK；
--     房子、工事、车场这些人的尺度的东西不放大，只是摆的位置跟着锚点（据点、海滩、机场……）走
--   主岛「棕榈岛」照网页版《暗剑》js/isle.js 的虚构热带岛：南岸宽而平缓（四处海滩）、东西两个岬角、西南向南开口的 U 形港湾（湾底港口镇）、
--   中央山脊（偏东一个山口）、西北主峰、东部沿海平原上的机场；网页版只有岛的南半边，这里补出北岸，改成四面环海的完整岛，尺寸按 0.5 缩
--   另有前哨岛（据点 A）、灯塔岛（据点 B）、西礁岛（岸防炮台，没有据点）、攻方机场岛；攻方舰队在南边 Z 2000～2400
local Map = {}
local exp, abs, sin, cos, sqrt, max, min, floor = math.exp, math.abs, math.sin, math.cos, math.sqrt, math.max, math.min, math.floor
local noise = math.noise

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
Map.clamp, Map.smooth, Map.lerp = clamp, smooth, lerp

local K, HK = 3, 2      -- 水平放大、高度放大（坡度变成原来的 HK / K）：主岛东西约 9000 格（3.2 公里），主峰约 500 格
Map.K, Map.HK = K, HK
Map.R = 12288          -- 地形（含海水）范围 ±R（2048 的倍数：海水按 2048 一块灌）；攻方机场岛最南到 10300 左右
Map.PLAY = 36864       -- 飞机的作战区 ±PLAY（再往外自动掉头）：约 ±13 公里
Map.SEA_R = 24576      -- 地形海水再往外铺一圈薄的（±SEA_R，约 ±8.8 公里）：用户要「一望无际的海」，远海那圈平面和地形水面接不上、有割裂感
Map.SEA_LIM = 28672    -- 船能开到 ±SEA_LIM：约 ±10 公里（地形海水外面是客户端铺的远海平面）
Map.SEA_DEPTH = 110    -- 远海水深（格，约 40 米；用户：海太浅了不真实——原来 12 格，四米多）
Map.SHELF = 14         -- 近岸浅滩最深多少格（海滩外缓坡：登陆艇、两栖车照样冲得上滩），再往外陡降到 SEA_DEPTH
Map.MAXH = 290 * HK    -- 高度系数 1 对应多少格（主峰约 500）
Map.RES = 4            -- 地形体素边长

---------------------------------------------------------------- 主岛

local MI = { x = 0, z = -1500 * K, hs = 1500 * K, S = 800 * K, N = 760 * K }   -- 中心、东西半宽、南岸 / 北岸离中线最远多少
Map.MAIN = MI
local PH = { 0.7, 2.1, 4.0, 1.3, 5.2, 3.3, 0.4, 2.8, 4.6, 1.9, 3.7, 5.9 }   -- 起伏的相位（网页版按种子随机，这里定死：每局一样）
local BAY = { x = -495 * K, w = 120 * K, d = 320 * K }   -- 港湾：中心、半宽、伸进岛里多深
local CAPES = { { x = -1110 * K, ext = 150 * K, w = 105 * K }, { x = 1200 * K, ext = 130 * K, w = 95 * K } }   -- 南岸东西两个岬角：伸出多远、半宽
Map.BAY = BAY
Map.CAPES = CAPES

local function southRaw(x)
  local u = (x - MI.x) / MI.hs
  if abs(u) >= 1 then return nil end
  local f = (1 - abs(u) ^ 3.5) ^ 0.45   -- 南岸正面宽而平缓（能登陆的岸段长），东西两头陡收
  local c = MI.S * f + f * K * (35 * sin(x / (155 * K) + PH[1]) + 14 * sin(x / (48 * K) + PH[2]) + 6 * sin(x / (21 * K) + PH[3]))
  for _, k in ipairs(CAPES) do c += k.ext * f * exp(-((x - k.x) / k.w) ^ 2) end
  local q = (x - BAY.x) / BAY.w
  c -= BAY.d * exp(-((q * q) ^ 1.6))   -- U 形湾：湾底平、湾口不收窄
  return MI.z + c
end
local function northRaw(x)
  local u = (x - MI.x) / MI.hs
  if abs(u) >= 1 then return nil end
  local g = (1 - abs(u) ^ 3) ^ 0.5
  local c = MI.N * g + g * K * (30 * sin(x / (140 * K) + PH[4]) + 16 * sin(x / (53 * K) + PH[5]) + 7 * sin(x / (19 * K) + PH[6]))
  return MI.z - c
end

-- 岸线先算好存表（每 2 格一个），查的时候线性插值
local CX0, CSTEP = -MI.hs, 2
local CN = floor(2 * MI.hs / CSTEP)
local cS, cN = table.create(CN + 1), table.create(CN + 1)
for i = 0, CN do
  local x = CX0 + i * CSTEP
  cS[i + 1] = southRaw(x) or MI.z
  cN[i + 1] = northRaw(x) or MI.z
end
local function coastLookup(t, x)
  local f = (x - CX0) / CSTEP
  if f <= 0 or f >= CN then return nil end
  local i = floor(f)
  local a = f - i
  return t[i + 1] * (1 - a) + t[i + 2] * a
end
function Map.coastS(x) return coastLookup(cS, x) end   -- 主岛南岸线在 x 处的 z（岛外返回 nil）
function Map.coastN(x) return coastLookup(cN, x) end   -- 北岸线

---------------------------------------------------------------- 海滩、据点、营地

-- 南岸四处海滩（避开港湾、岬角）；东北岸一处侧翼海滩
Map.BEACHES = {
  { id = "red", x0 = -980 * K, x1 = -820 * K, color = Color3.fromRGB(215, 70, 60) },
  { id = "white", x0 = -200 * K, x1 = -40 * K, color = Color3.fromRGB(235, 235, 235) },
  { id = "blue", x0 = 250 * K, x1 = 410 * K, color = Color3.fromRGB(80, 196, 100) },   -- 显示名「绿滩」（用户 11-21：蓝色全部改成绿色；编号还叫 blue，代码里按它找）
  { id = "gold", x0 = 690 * K, x1 = 850 * K, color = Color3.fromRGB(235, 190, 60) },
  { id = "flank", x0 = 820 * K, x1 = 960 * K, north = true, color = Color3.fromRGB(150, 110, 220) },
}
for _, b in ipairs(Map.BEACHES) do
  b.cx = (b.x0 + b.x1) / 2
  b.z = (b.north and Map.coastN or Map.coastS)(b.cx)
  b.dir = b.north and -1 or 1   -- 朝海的方向（Z）：南岸的海在南（+Z），北岸的海在北
end
local function beachAt(x, north)
  for _, b in ipairs(Map.BEACHES) do
    if (b.north == true) == (north == true) and x >= b.x0 - 25 * K and x <= b.x1 + 25 * K then return b end
  end
  return nil
end
Map.beachAt = beachAt

local function ridgeZ(x) return MI.z + K * (-230 + 65 * sin(x / (260 * K) + PH[7]) + 30 * sin(x / (85 * K) + PH[8])) end
Map.ridgeZ = ridgeZ
local HILLS = {
  { x = -420 * K, z = MI.z - 450 * K, r = 300 * K, h = 0.95 },   -- 西北主峰
  { x = -760 * K, z = MI.z - 90 * K, r = 250 * K, h = 0.5 },
  { x = 470 * K, z = MI.z - 200 * K, r = 270 * K, h = 0.5 },
  { x = 1060 * K, z = MI.z - 330 * K, r = 190 * K, h = 0.4 },
}

-- 机场（守方，东部沿海平原，跑道东西向）、指挥所（山脊北面）、后方营地（北岸，不能占）、港口镇（湾底）
local afX = 780 * K
-- 跑道 3600 格（约 1.3 公里）、宽 90 格（用户：机场太小、跑道非常短）：不跟着 K 放大，按真飞机滑跑要的长度定（Fly.lua 地面加速度、抬头速度）
Map.AIRFIELD = { x = afX, z = (Map.coastS(afX) or 0) - 470 * K, len = 3600, wid = 90, rot = 0 }
local AFP = { x = afX, z = Map.AIRFIELD.z - 40 * K }   -- 机场一带是一片低平的沿海平原（mainNatural 里压低）
Map.COMMAND = { x = 260 * K, z = ridgeZ(260 * K) - 230 * K }
Map.CAMP = { x = 140 * K, z = (Map.coastN(140 * K) or 0) + 120 * K }
Map.PORT = { x = BAY.x, z = (Map.coastS(BAY.x) or 0) - 70 * K }

---------------------------------------------------------------- 小岛

local ISLES = {
  { id = "outpost", x = 150 * K, z = 500 * K, a = 230 * K, b = 170 * K, h = 34 * HK, ph = 1.1 },   -- 前哨岛：离攻方舰队最近
  { id = "lighthouse", x = 2500 * K, z = -300 * K, a = 300 * K, b = 230 * K, h = 62 * HK, ph = 2.7 },   -- 灯塔岛（东）
  { id = "westreef", x = -2500 * K, z = -200 * K, a = 270 * K, b = 220 * K, h = 46 * HK, ph = 4.2 },   -- 西礁岛：岸防炮台
  { id = "afield", x = 0, z = 3200 * K, a = 620 * K, b = 230 * K, h = 6, ph = 0.3, flat = true },   -- 攻方机场岛：平的
}
Map.ISLES = ISLES
for _, I in ipairs(ISLES) do Map[string.upper(I.id)] = I end

local function isleRad(I, th)   -- 椭圆半径按方位起伏
  local c, s = cos(th), sin(th)
  local r = I.a * I.b / sqrt((I.b * c) ^ 2 + (I.a * s) ^ 2)
  return r * (1 + 0.07 * sin(3 * th + I.ph) + 0.04 * sin(5 * th + 2 * I.ph) + 0.02 * sin(9 * th + 3 * I.ph))
end
Map.isleRad = isleRad
-- 离这个小岛的岸多远（正 = 岛上，负 = 海里）
local function isleD(I, x, z)
  local dx, dz = x - I.x, z - I.z
  local rho = sqrt(dx * dx + dz * dz)
  if rho > I.a * 1.3 + 400 * K then return -1e9, 1, rho end
  local R = isleRad(I, math.atan2(dz, dx))
  return R - rho, R, rho
end

-- 5 个据点：A 前哨岛、B 灯塔岛、C 港口镇、D 机场、E 指挥所（开局都归守方）
Map.POINTS = {
  { id = "A", x = 150 * K, z = 500 * K, isle = "outpost" },
  { id = "B", x = 2480 * K, z = -320 * K, isle = "lighthouse" },
  { id = "C", x = Map.PORT.x, z = Map.PORT.z },
  { id = "D", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z - 80 * K },   -- 机场北面的停机坪、塔台一带
  { id = "E", x = Map.COMMAND.x, z = Map.COMMAND.z },
}
Map.POINT_R = 80   -- 据点半径

-- 登陆点：主岛的 5 处海滩 + 前哨岛、灯塔岛的南岸（登陆艇从南边冲上去）；攻方选「抢滩」出生、机器人坐艇都按它
Map.LANDINGS = {}
for _, b in ipairs(Map.BEACHES) do table.insert(Map.LANDINGS, b) end
for _, id in ipairs({ "outpost", "lighthouse" }) do
  local I = Map[string.upper(id)]
  table.insert(Map.LANDINGS, { id = id, cx = I.x, z = I.z + isleRad(I, math.pi / 2), dir = 1, isle = id, color = Color3.fromRGB(240, 240, 200) })
end
-- 港湾里：从湾口一直冲到湾底的港口码头
table.insert(Map.LANDINGS, { id = "port", cx = BAY.x, z = Map.coastS(BAY.x), dir = 1, color = Color3.fromRGB(200, 200, 210) })
function Map.landingOf(id)
  for _, b in ipairs(Map.LANDINGS) do if b.id == id then return b end end
  return nil
end
-- 这一点在哪块陆地上：小岛编号，或者 "main"（主岛；海里也算主岛）
function Map.landOf(x, z)
  for _, I in ipairs(ISLES) do
    if (isleD(I, x, z)) > -80 * K then return I.id end
  end
  return "main"
end
for _, p in ipairs(Map.POINTS) do p.land = p.isle or "main" end

-- 攻方舰队（固定平台，打不掉）、机场岛跑道
Map.FLEET = {
  { kind = "carrier", x = -420 * K, z = 2250 * K, rot = 0 },   -- 航母（福建舰）
  { kind = "lhd", x = 330 * K, z = 2150 * K, rot = 0 },   -- 两栖攻击舰（075）
  { kind = "lst", x = -1000 * K, z = 2050 * K, rot = 0 },   -- 登陆舰（072A）
  { kind = "lst", x = 950 * K, z = 2050 * K, rot = 0 },
}
Map.AFIELD2 = { x = 0, z = 3200 * K, len = 3300, wid = 90, rot = 0 }   -- 攻方机场岛的跑道（岛东西 3700 来格，跑道 3300、宽 90）
-- 登陆平台：舰队前面一块浮在海上的大平台（攻方地面载具的生成点在两侧水面：车站在气垫艇上，自己开去哪个海滩都行，冲上岸艇自己回去）
--   摆在前哨岛南边 700 格（不跟着 K 放大到舰队那么远：气垫艇 75 格 / 秒，到海滩一分钟上下）
Map.BARGE = { x = -40 * K, z = ISLES[1].z + ISLES[1].b + 700, W = 120, L = 360, top = 3.5 }

---------------------------------------------------------------- 压平的场地

-- 据点、机场、营地、港口：在自然高度上压平一块（圆：r 以内完全压平，r2 以外不变；矩形：hx × hz 以内压平，往外 m 格过渡）；只压陆地，不把海抬起来
local FLAT = {}
local function addFlat(x, z, r, r2, y) table.insert(FLAT, { x = x, z = z, r = r, r2 = r2, y = y }) end
local function addRect(x, z, hx, hz, m, y) table.insert(FLAT, { x = x, z = z, hx = hx, hz = hz, m = m, y = y, rect = true }) end
Map.FLAT = FLAT

---------------------------------------------------------------- 高度

local function mainNatural(x, z)
  local zs, zn = Map.coastS(x), Map.coastN(x)
  if not zs then return nil, -1e9 end
  local dS, dN = zs - z, z - zn
  local d = min(dS, dN)   -- 离岸（南北方向量；岛东西两头偏小一点，没关系）
  if d <= 0 then return nil, d, dS, dN end
  local u = (x - MI.x) / MI.hs
  local e = 0.06 + min(0.18, d / (1500 * K))
  e += 0.3 * exp(-((z - ridgeZ(x)) ^ 2) / (22500 * K * K)) * smooth(0, 0.5, 1 - abs(u)) * (1 - 0.75 * exp(-((x - 180 * K) / (110 * K)) ^ 2))   -- 中央山脊，偏东一个山口
  for _, h in ipairs(HILLS) do e += h.h * exp(-((x - h.x) ^ 2 + (z - h.z) ^ 2) / (2 * h.r * h.r)) end
  local bS = beachAt(x, false)
  local headland = not bS and not (abs(x - BAY.x) < BAY.w + 60 * K) and (abs(x - CAPES[1].x) < CAPES[1].w * 1.2 or abs(x - CAPES[2].x) < CAPES[2].w * 1.2)
  if headland then e += 0.14 * exp(-((dS - 35 * K) ^ 2) / (2250 * K * K)) end   -- 岬角：岸边陡起的崖顶
  e += noise(x / (300 * K), z / (300 * K), 1.37) * 0.16 + noise(x / (110 * K), z / (110 * K), 7.1) * 0.06   -- 起伏
  e *= lerp(0.4, 1, smooth(20 * K, 325 * K, d))   -- 沿海平原
  do   -- 东部沿海平原（机场）：一大片低平地（往一个平的高度抹），往外慢慢抬起来
    local qx, qz = max(0, abs(x - AFP.x) - 330 * K), max(0, abs(z - AFP.z) - 160 * K)
    e = lerp(0.075, e, smooth(40 * K, 520 * K, sqrt(qx * qx + qz * qz)))
  end
  if bS and dS < 160 * K then e *= lerp(0.35, 1, smooth(15 * K, 120 * K, dS)) end   -- 海滩后方平缓
  local bN = beachAt(x, true)
  if bN and dN < 160 * K then e *= lerp(0.35, 1, smooth(15 * K, 120 * K, dN)) end
  e = clamp(1 - exp(-1.35 * max(0, e)), 0, 1)   -- 软压缩：高处越来越缓，不会削成平顶台地
  local y = e * Map.MAXH
  local edge = (((bS and dS < dN) or (bN and dN <= dS)) and 70 or (headland and dS < dN and 18 or 45)) * K
  return y * smooth(0, edge, d) + 0.6, d, dS, dN
end

local function isleNatural(I, x, z)
  local d, R, rho = isleD(I, x, z)
  if d <= 0 then return nil, d end
  local y
  if I.flat then
    y = I.h * smooth(0, 60 * K, d)
  else
    local k = clamp(rho / R, 0, 1)
    y = I.h * (1 - k * k) ^ 0.8 + (noise(x / (90 * K), z / (90 * K), I.ph * 3) * 0.5) * I.h * 0.25 * smooth(0, 80 * K, d)
    y *= smooth(0, 40 * K, d)
  end
  return max(y, 0) + 0.6, d
end

-- 自然高度（压平之前）；海里返回负数（海底）
local function natural(x, z)
  local y, d, dS, dN = mainNatural(x, z)
  if y then return y, d end
  local off, k = 1e9, 0.16
  if d and d > -1e8 then   -- 主岛南北两岸外：海滩外是缓坡浅滩
    off = -d
    local b = (dS and dN and dS < dN) and beachAt(x, false) or beachAt(x, true)
    if b and ((b.north and dN and dN < 0) or (not b.north and dS and dS < 0)) then k = 0.06 end
  end
  for _, I in ipairs(ISLES) do
    local yi, di = isleNatural(I, x, z)
    if yi then return yi, di end
    if -di < off then off, k = -di, 0.12 end
  end
  -- 岸线外头几格从陆地边上的 +0.6 平滑降到 −1.2（原来在岸线上直接断开 1.8 格：车开到水线就是一道坎）；海滩的缓些
  --   近岸是缓坡浅滩（最深 SHELF 格），离岸 150 格以外大陆坡往下陡降（每格降 0.28），四百多格外就是远海的深度
  local lip = 1.8 * smooth(0, (k < 0.1) and 10 or 6, off)
  local shelf = min(Map.SHELF, lip - 0.6 + off * k)
  local slope = max(0, off - 50 * K) * 0.28
  return -min(Map.SEA_DEPTH, shelf + slope), -off
end

-- 压平之后、压路之前的高度；第三个返回值是压平的权重（0～1，路在压平的场地里不再改高度）
local function flatHeight(x, z)
  local y, d = natural(x, z)
  if y <= 0.3 then return y, d, 0 end
  local wmax = 0
  for _, F in ipairs(FLAT) do
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
      y = lerp(y, max(F.y, 0.8), w * smooth(0, 25, d))   -- 岸边那一点不压（不改岸线）
      if w > wmax then wmax = w end
    end
  end
  return y, d, wmax
end

-- 地面（站人、放车）：海上是海面
function Map.ground(x, z)
  local y = Map.height(x, z)
  return max(y, 0)
end
function Map.isLand(x, z) return (Map.height(x, z)) > 0.3 end
function Map.slope(x, z)
  local e = 4
  local a, b = Map.height(x + e, z), Map.height(x - e, z)
  local c, d = Map.height(x, z + e), Map.height(x, z - e)
  return sqrt(((a - b) / (2 * e)) ^ 2 + ((c - d) / (2 * e)) ^ 2)
end

-- 压平的场地：高度取这一圈自然高度的平均（一半挖一半填，四周不会是一圈陡壁；不低于 3 格）
local function avgNatural(x, z, r)
  local sum, n = natural(x, z), 1
  for k = 0, 11 do
    local a = k * math.pi / 6
    for _, rr in ipairs({ r * 0.5, r }) do
      local y = natural(x + cos(a) * rr, z + sin(a) * rr)
      if y > 0 then sum += y; n += 1 end
    end
  end
  return sum / n
end
local function flatHere(x, z, r, r2, yMin)
  addFlat(x, z, r, r2, max(yMin or 3, avgNatural(x, z, r)))
end
for _, p in ipairs(Map.POINTS) do flatHere(p.x, p.z, 55 * K, 110 * K) end
do local A = Map.AIRFIELD addRect(A.x, A.z - 40 * K, A.len / 2 + 50, 120 * K, 170 * K, max(4, avgNatural(A.x, A.z - 40 * K, 200 * K))) end   -- 跑道 + 北面停机坪
do local C = Map.CAMP addRect(C.x, C.z + 15 * K, 200 * K, 85 * K, 120 * K, max(3, avgNatural(C.x, C.z, 70 * K))) end   -- 营地：帐篷、营房，南面一排车场、北面直升机停机坪（Depots.lua）
flatHere(Map.PORT.x, Map.PORT.z, 80 * K, 190 * K)   -- 压平的场地都跟着放大：路网是按放大前的地图（连这些场地）算的
addRect(Map.AFIELD2.x, Map.AFIELD2.z, Map.AFIELD2.len / 2 + 20, 70 * K, 60 * K, 6)
---------------------------------------------------------------- 路网（tools/map/roads.lua 离线算好的路线；这里按沿路平滑过的高度压平路面）

-- 线段：起点、终点、两头的路面高度、路宽；按 48 格的格子登记（查的时候只看这一格里的线段）
local SX0, SZ0, SX1, SZ1, SY0, SY1, SW = {}, {}, {}, {}, {}, {}, {}
local RCELL = 48
local rgrid = {}
local ROADS = {}
Map.ROADS = ROADS
do
  local ok, data = false, nil
  local mod = script and script.Parent and script.Parent:FindFirstChild("MapRoads")
  -- 客户端要等它复制过来（用户 11-22：无数个 AI 修不好坦克半截身子卡在地里）：客户端一进游戏头一件事就 require Map，
  --   这时 ReplicatedStorage 里几千块导入的网格还在往下传，MapRoads 常常还没到——原来 FindFirstChild 查一下没有就当没有路，
  --   这个客户端的地面高度就少了路的挖填（路堤、路堑最多差 6 格），可地形是服务器按有路写的：自己开的车按客户端的高度摆，
  --   路堤上整车矮下去半截、陷在看得见的路面里（位置再报给服务器，别人看着也陷着）。服务器开服时什么都在，等不着
  if not mod and script and script.Parent and script.Parent.WaitForChild then
    mod = script.Parent:WaitForChild("MapRoads", 60)
    if not mod then warn("[地图] 等了 60 秒还没有 ReplicatedStorage.MapRoads：这边的地面高度没有路，车会和地形对不上（脚本没换全？）") end
  end
  if mod then ok, data = pcall(require, mod) end
  if ok and type(data) == "table" then
    for _, r in ipairs(data) do
      local n = #r.p // 2
      if n >= 2 then
        local xs, zs, ys = table.create(n), table.create(n), table.create(n)
        for i = 1, n do
          xs[i], zs[i] = r.p[2 * i - 1] * K, r.p[2 * i] * K   -- tools/map/roads.lua 按放大前的地图算的：坐标乘 K（路宽不变）
          ys[i] = max(1.2, (flatHeight(xs[i], zs[i])))
        end
        -- 路面高度沿路平滑（坑坑洼洼的地形上路是顺的）；挖填不超过 5 格
        local base = table.clone(ys)
        for _ = 1, 6 do
          local nys = table.clone(ys)
          for i = 2, n - 1 do nys[i] = ys[i - 1] * 0.25 + ys[i] * 0.5 + ys[i + 1] * 0.25 end
          ys = nys
        end
        for i = 1, n do ys[i] = clamp(ys[i], base[i] - 5, base[i] + 5) end
        table.insert(ROADS, { name = r.name, w = r.w, x = xs, z = zs, y = ys })
        for i = 1, n - 1 do
          local k = #SX0 + 1
          SX0[k], SZ0[k], SX1[k], SZ1[k], SY0[k], SY1[k], SW[k] = xs[i], zs[i], xs[i + 1], zs[i + 1], ys[i], ys[i + 1], r.w
          local pad = r.w * 0.5 + 12
          for gx = floor((min(xs[i], xs[i + 1]) - pad) / RCELL), floor((max(xs[i], xs[i + 1]) + pad) / RCELL) do
            for gz = floor((min(zs[i], zs[i + 1]) - pad) / RCELL), floor((max(zs[i], zs[i + 1]) + pad) / RCELL) do
              local key = gx * 4096 + gz
              local list = rgrid[key]
              if not list then list = {} rgrid[key] = list end
              table.insert(list, k)
            end
          end
        end
      end
    end
  end
end
-- 离最近的路多远、这里的路面高度、路宽（附近没路返回 nil）
--   路面高度按附近各条线段加权（越近越重）：两条路交汇处各自平滑出来的高度不一样，只取最近那条会在交界处突然跳一截
local function roadNear(x, z)
  local list = rgrid[floor(x / RCELL) * 4096 + floor(z / RCELL)]
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
      local d = sqrt(dd)
      local w = (1 - d / reach) ^ 2 / (1 + d)
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

-- 港口（用户 11-20：地图有 bug——湾底的码头在 70 多格高的直崖底下，上不去；攻方从湾口冲到码头登陆也卡在崖底）：
--   湾底沿岸压出一条离水面 4 格的码头平地（码头根上的库房落在上面，靠山的三面是挡土墙，World.lua 贴水泥墙面），
--   码头北边贴着挡土墙挖一条坡道：西头跟码头一样高，往东爬 350 格、28 格宽、11° 上下，到东头接回崖顶（港口镇东南角）；
--   不往北挖：往北会把镇子东边那条路（港口镇—白滩）切出一道 30 格深的沟
local HARBOR = (function()
  local P = Map.PORT
  local zs = Map.coastS(P.x) or (P.z + 210)
  local H = { x = P.x, zs = zs, qx = 210, qd = 70, y = 4.2, rw = 14, deck = 4.6 }   -- deck：木码头面多高（比码头平地高一点）
  H.a = { x = P.x - 170, z = zs - 84 }   -- 坡道底（码头西北角，跟码头平地一样高）
  H.b = { x = P.x + 180, z = zs - 84 }   -- 坡道顶（东头，崖顶上）
  return H
end)()
Map.HARBOR = HARBOR
-- 坡道：离坡道中线多远、走到第几成（0 底～1 顶）
local function harborRamp(x, z)
  local H = HARBOR
  local ax, az, bx, bz = H.a.x, H.a.z, H.b.x, H.b.z
  local vx, vz = bx - ax, bz - az
  local L2 = vx * vx + vz * vz
  local t = ((x - ax) * vx + (z - az) * vz) / L2
  local cx, cz = ax + vx * t, az + vz * t
  return math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2), t
end
Map.harborRamp = harborRamp
-- 在不在港口码头那个坑里（码头平地、坡道；m：往外多算几格）：攻击出发阵地、AI 车的出生点别选在这里——离港口镇 70 格高的崖底，机器人的寻路绕不上来
function Map.inHarbor(x, z, m)
  local H = HARBOR
  m = m or 0
  if math.abs(x - H.x) <= H.qx + m and z >= H.zs - H.qd - 30 - m and z <= H.zs + 40 + m then return true end
  local d, t = harborRamp(x, z)
  return d <= H.rw + m and t >= -0.12 and t <= 1.05
end
local function harborCut(x, z, y)
  local H = HARBOR
  if math.abs(x - H.x) <= H.qx and z >= H.zs - H.qd and z <= H.zs + 40 then   -- 码头平地（只往下削，不把海填起来）
    return math.min(y, H.y)
  end
  local d, t = harborRamp(x, z)
  if d <= H.rw and t >= -0.1 and t <= 1 then   -- 坡道：挖到坡面的高度（坡顶接上镇子的高度）；西头往外多挖 35 格平的（车从码头拐进来的地方）
    local top = H.townY or y
    return math.min(y, H.y + (top - H.y) * math.clamp(t, 0, 1))
  end
  return y
end

function Map.height(x, z)
  local y, d, wf = flatHeight(x, z)
  if y <= 0.3 then return y, d end
  local rd, ry, rw = roadNear(x, z)
  if rd then
    local half = rw * 0.5
    local w = 1 - smooth(half, half + 10, rd)   -- 路面完全压平，两边 10 格慢慢接回地形
    if w > 0 then y = lerp(y, ry, w * (1 - wf) * smooth(0, 20, d)) end
  end
  y = harborCut(x, z, y)
  return y, d
end
-- 这一点在压平的场地（据点、机场、营地、港口）里有多深：0 外面～1 完全压平（摆树、花草时避开）
function Map.flatW(x, z)
  local _, _, w = flatHeight(x, z)
  return w or 0
end
for _, p in ipairs(Map.POINTS) do p.y = Map.ground(p.x, p.z) end
HARBOR.townY = select(1, flatHeight(HARBOR.b.x, HARBOR.b.z))   -- 坡道顶接港口镇东北角那里的地面
for _, k in ipairs({ "AIRFIELD", "COMMAND", "CAMP", "PORT", "AFIELD2" }) do Map[k].y = Map.ground(Map[k].x, Map[k].z) end

---------------------------------------------------------------- 材质

function Map.material(x, z, y, slope)
  if y <= 0.4 then
    return (y > -3.5) and Enum.Material.Sand or Enum.Material.Sand
  end
  do   -- 港口的码头平地：水泥；坡道：柏油
    local H = HARBOR
    if math.abs(x - H.x) <= H.qx and z >= H.zs - H.qd and z <= H.zs + 40 and y <= H.y + 0.5 then return Enum.Material.Concrete end
    local hd, ht = harborRamp(x, z)
    if hd <= H.rw + 1 and ht >= -0.11 and ht <= 1.02 then return Enum.Material.Asphalt end
  end
  local rd, _, rw = roadNear(x, z)
  if rd and rd < rw * 0.5 + 1.2 * noise(x / 9, z / 9, 3.3) then return Enum.Material.Ground end   -- 土路（边上毛一点）
  local zs, zn = Map.coastS(x), Map.coastN(x)
  local nearBeach = y < 8 and zs and ((beachAt(x, false) and zs - z > -10 and zs - z < 90) or (beachAt(x, true) and z - zn > -10 and z - zn < 90))
  if nearBeach or y < 2.2 then return Enum.Material.Sand end
  if slope > 1.15 * HK / K then return (y > 120 * HK) and Enum.Material.Slate or Enum.Material.Rock end
  if y > 232 * HK then return Enum.Material.Rock end
  if slope > 0.92 * HK / K then return Enum.Material.Ground end   -- 陡一点的坡才露土（原来 0.75：用户 11-19 草多一点）
  local n = noise(x / (85 * K), z / (85 * K), 11.3)
  if y < 9 and n > 0.42 then return Enum.Material.Ground end   -- 海边低处零星的土地块（少一点）
  -- 大片草地，深色 LeafyGrass 只留很少几块（小地图、瞄准镜画中画、开车的路面按这个分）；
  --   写地形时 Grass 都换成 LeafyGrass（World.lua 的 writeChunk；用户 11-21：会动的草叶把车、人的下半截盖住，脚本又关不掉草叶）
  return (n > 0.62) and Enum.Material.LeafyGrass or Enum.Material.Grass
end

---------------------------------------------------------------- 有陆地的范围（开服生成地形只写这些块）

-- 返回 { x0, z0, x1, z1 } 若干个：主岛、各小岛，外扩一圈浅滩
function Map.landBoxes()
  local pad = 120
  local boxes = { { MI.x - MI.hs - pad, MI.z - MI.N - 140 * K - pad, MI.x + MI.hs + pad, MI.z + MI.S + 200 * K + pad } }
  for _, I in ipairs(ISLES) do
    local r = max(I.a, I.b) * 1.15 + pad
    table.insert(boxes, { I.x - r, I.z - r, I.x + r, I.z + r })
  end
  return boxes
end

-- 两点之间的直线有没有被地形挡住（AI 视线用；每 step 格取一点）
function Map.lineClear(a, b, step)
  step = step or 12
  local d = b - a
  local L = d.Magnitude
  local n = max(1, floor(L / step))
  for i = 1, n - 1 do
    local p = a + d * (i / n)
    if Map.height(p.X, p.Z) > p.Y then return false end
  end
  return true
end

return Map
