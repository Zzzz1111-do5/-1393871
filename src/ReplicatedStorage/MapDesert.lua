-- 全面大战场——沙漠地图「沙漠风暴」（ReplicatedStorage.MapDesert）：跟 Map.lua 同一套接口（Map.use("desert") 换进 Map 表）；纯数学，服务器、客户端算出来一样
--   用户 11-22：「加一个沙漠地图，给我搞得特别特别大，然后两边有自己的军事基地带机场」
--   23.4 公里见方（地形 ±32768 格）：西边联军前进基地、东边守备军基地——各一条 3600 格的南北向跑道、机库、塔台、车场、直升机坪、营房；
--   中间 7 个据点（开局都是中立，征服模式：Round.lua）：A 绿洲镇、B 油田、C 古城（台地上）、D 十字路口镇（正中）、E 雷达站（山头上）、F 干河谷桥、G 炼油厂；
--   地形：大片平坦的戈壁（reg）、南北两条沙丘带（erg：横向沙丘，高 20～60 格）、二十来座平顶台地（mesa，陡壁、坡脚有碎石坡）、两条干河谷（wadi）、
--   中间一道石岭；基地、据点、路两边压平。没有海：最低的河谷底也在 0 以上（各模块拿「高度 > 0.3」当陆地）
--   开服写地形（World.lua 的 desertTerrain）：±32768 整片先用 FillBlock 铺平（很快），细节（沙丘、台地、河谷、石岭、据点）只写 detailBoxes 里的块
local M = {}
local abs, sin, cos, sqrt, max, min, floor = math.abs, math.sin, math.cos, math.sqrt, math.max, math.min, math.floor
local noise = math.noise
local PI = math.pi

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end

M.id = "desert"
M.K, M.HK = 3, 2          -- 跟岛一样的倍数（有的界面、寻路网格按 K 算格子大小）
M.R = 32768               -- 地形范围 ±R（全是平地，FillBlock 铺）
M.EXT = 15500             -- 有东西的范围 ±EXT（小地图、战术平板、机器人寻路按它）
M.PLAY = 36000            -- 飞机作战区 ±PLAY（再往外自动掉头）
M.SEA_R, M.SEA_LIM, M.SEA_DEPTH, M.SHELF = 0, 0, 0, 0   -- 没有海
M.MAXH = 290 * M.HK
M.RES = 4
M.BASE_Y = 8              -- 戈壁平原的高度（河谷底在 1 左右，还是陆地）
M.desert = true

---------------------------------------------------------------- 两边的基地（跑道、营地、车场）

-- 跑道东西向（同岛上的机场：World.lua 的 airfield 照用）在基地北边，北面停机坪、机库、塔台；跑道南边是营地（帐篷、营房）、
--   车场（一排地面载具召唤位）、直升机坪；四周一圈 HESCO 防爆墙
local BX = 12600   -- 基地中心离中线多远
M.BASES = {
  atk = { x = -BX, z = 0, face = 1 },    -- 西边，朝东打
  def = { x = BX, z = 0, face = -1 },    -- 东边，朝西打
}
for side, B in pairs(M.BASES) do
  B.airfield = { x = B.x, z = -1500, len = 3600, wid = 90, rot = 0, team = side, face = B.face }
  B.camp = { x = B.x + B.face * 500, z = 700 }
  B.motor = { x = B.x + B.face * 500, z = 1350 }          -- 车场（坦克、装甲车、防空、炮）
  B.heli = { x = B.x - B.face * 700, z = 1000 }           -- 直升机坪
  B.rect = { x0 = B.x - 2150, x1 = B.x + 2150, z0 = -2450, z1 = 2300 }
end
-- 跟岛一样的名字（守方机场 AIRFIELD、攻方机场 AFIELD2、守方营地 CAMP）：Air.lua、Depots.lua 照用
M.AIRFIELD = M.BASES.def.airfield
M.AFIELD2 = M.BASES.atk.airfield
M.CAMP = M.BASES.def.camp
M.CAMP_ATK = M.BASES.atk.camp

---------------------------------------------------------------- 据点（开局中立）

M.POINTS = {
  { id = "A", x = -6200, z = -3000, kind = "oasis" },       -- 绿洲镇
  { id = "B", x = -6000, z = 3600, kind = "oil" },          -- 油田
  { id = "C", x = 0, z = -4900, kind = "citadel" },         -- 古城（台地上）
  { id = "D", x = 0, z = 0, kind = "crossroads" },          -- 十字路口镇
  { id = "E", x = 0, z = 5000, kind = "radar" },            -- 雷达站（山头上）
  { id = "F", x = 6200, z = -3200, kind = "bridge" },       -- 干河谷桥
  { id = "G", x = 6200, z = 3400, kind = "refinery" },      -- 炼油厂
}
M.POINT_R = 90
for _, p in ipairs(M.POINTS) do p.land = "main" end
M.BEACHES, M.LANDINGS, M.FLEET, M.ISLES, M.CAPES = {}, {}, {}, {}, {}

---------------------------------------------------------------- 路（直线段；路面压平、两边让开沙丘和台地）

local ROADS = {
  { name = "西基地—十字路口", pts = { { -BX + 700, 0 }, { -6200, 0 }, { 0, 0 } }, w = 26 },
  { name = "十字路口—东基地", pts = { { 0, 0 }, { 6200, 0 }, { BX - 700, 0 } }, w = 26 },
  { name = "绿洲—油田", pts = { { -6200, -3000 }, { -6300, 0 }, { -6000, 3600 } }, w = 20 },
  { name = "河谷桥—炼油厂", pts = { { 6200, -3200 }, { 6300, 0 }, { 6200, 3400 } }, w = 20 },
  { name = "十字路口—古城", pts = { { 0, 0 }, { 200, -2600 }, { 0, -4600 } }, w = 18 },
  { name = "十字路口—雷达站", pts = { { 0, 0 }, { -200, 2600 }, { 0, 4700 } }, w = 18 },
  { name = "西基地—绿洲", pts = { { -BX + 700, -300 }, { -9200, -2200 }, { -6200, -3000 } }, w = 18 },
  { name = "西基地—油田", pts = { { -BX + 700, 300 }, { -9200, 2600 }, { -6000, 3600 } }, w = 18 },
  { name = "东基地—河谷桥", pts = { { BX - 700, -300 }, { 9200, -2400 }, { 6200, -3200 } }, w = 18 },
  { name = "东基地—炼油厂", pts = { { BX - 700, 300 }, { 9200, 2400 }, { 6200, 3400 } }, w = 18 },
  { name = "绿洲—古城", pts = { { -6200, -3000 }, { -3000, -4300 }, { 0, -4900 } }, w = 16 },
  { name = "古城—河谷桥", pts = { { 0, -4900 }, { 3000, -4400 }, { 6200, -3200 } }, w = 16 },
  { name = "油田—雷达站", pts = { { -6000, 3600 }, { -3000, 4600 }, { 0, 5000 } }, w = 16 },
  { name = "雷达站—炼油厂", pts = { { 0, 5000 }, { 3000, 4600 }, { 6200, 3400 } }, w = 16 },
}
-- 跟岛的 Map.ROADS 同样的格式（x、z 两列；客户端小地图、World 画路面用）
M.ROADS = {}
local SEG = {}   -- { ax, az, bx, bz, w }
for _, r in ipairs(ROADS) do
  local xs, zs = {}, {}
  for i, p in ipairs(r.pts) do
    xs[i], zs[i] = p[1], p[2]
    if i > 1 then table.insert(SEG, { r.pts[i - 1][1], r.pts[i - 1][2], p[1], p[2], r.w }) end
  end
  table.insert(M.ROADS, { name = r.name, x = xs, z = zs, w = r.w })
end
-- 线段按 512 格的格子登记（查的时候只看这一格和周围的）
local RC = 512
local rgrid = {}
for i, s in ipairs(SEG) do
  local x0, x1 = min(s[1], s[3]) - 200, max(s[1], s[3]) + 200
  local z0, z1 = min(s[2], s[4]) - 200, max(s[2], s[4]) + 200
  for cx = floor(x0 / RC), floor(x1 / RC) do
    for cz = floor(z0 / RC), floor(z1 / RC) do
      local k = cx * 100003 + cz
      rgrid[k] = rgrid[k] or {}
      table.insert(rgrid[k], i)
    end
  end
end
local function roadNear(x, z)
  local list = rgrid[floor(x / RC) * 100003 + floor(z / RC)]
  if not list then return nil end
  local best, bw = 1e18, 0
  for _, i in ipairs(list) do
    local s = SEG[i]
    local vx, vz = s[3] - s[1], s[4] - s[2]
    local L2 = vx * vx + vz * vz
    local t = clamp(((x - s[1]) * vx + (z - s[2]) * vz) / L2, 0, 1)
    local dx, dz = x - (s[1] + vx * t), z - (s[2] + vz * t)
    local d2 = dx * dx + dz * dz
    if d2 < best then best, bw = d2, s[5] end
  end
  if best >= 1e18 then return nil end
  return sqrt(best), M.BASE_Y, bw
end
M.roadNear = roadNear
function M.roadDist(x, z)
  local d = roadNear(x, z)
  return d or 1e9
end

---------------------------------------------------------------- 地貌
-- 地形只在这些地貌的「块」里写体素（detailBoxes），别处是 FillBlock 铺的平地——所以平地上一点起伏都不能有（不然 Map.ground 和写出来的地对不上，
--   车悬空 / 陷地）；每样地貌在自己的块边上都已经回到平地

-- 平顶台地：中心、顶面半径、高（定死的位置：避开据点、基地、路）；陡壁 + 坡脚 200 格的碎石坡
local MESAS = {
  { -9800, -5200, 420, 110 }, { -8400, 5800, 360, 95 }, { -4200, -1600, 240, 70 }, { -3600, 1900, 280, 85 },
  { -2600, -6600, 380, 120 }, { 2200, -1900, 260, 75 }, { 3500, 1700, 300, 90 }, { 2800, 6900, 420, 115 },
  { 4300, -6300, 340, 95 }, { 8800, 5300, 380, 105 }, { -10400, 4300, 260, 70 }, { 9700, -5600, 300, 85 },
}
local TALUS = 200
-- 圆丘：古城（据点 C）、雷达站（据点 E）站在山头上（坡缓，车开得上去），旁边两个小丘
local HILLS = { { 0, -4900, 620, 48 }, { 0, 5000, 640, 70 }, { 1300, 5600, 380, 36 }, { -1200, 5500, 340, 30 } }
local TOPS = { { 0, -4900, 48 }, { 0, 5000, 70 } }   -- 山头压平一块（据点 C、E 的场地）：中心、高
-- 中间一道石岭（东西走向，D 和 E 之间北边一点；中间豁口过路）
local RIDGE = { x0 = -3600, x1 = 3600, z = 2300, w = 140, h = 42 }
-- 沙丘区（erg）：一片片横向沙丘，长方形 hx × hz（半宽），边上 500 格慢慢回到平地
local ERGS = {
  { -6400, -9800, 1100, 850 }, { 4800, -10000, 1100, 850 }, { -4200, 9900, 1100, 850 }, { 6400, 9700, 1000, 850 },
}

-- 压平的地方：基地、据点
local FLAT = {}
for _, B in pairs(M.BASES) do
  table.insert(FLAT, { rect = true, x0 = B.rect.x0, x1 = B.rect.x1, z0 = B.rect.z0, z1 = B.rect.z1, m = 500, y = M.BASE_Y })
end
for _, p in ipairs(M.POINTS) do
  if p.id ~= "C" and p.id ~= "E" then table.insert(FLAT, { x = p.x, z = p.z, r = 260, r2 = 520, y = M.BASE_Y }) end
end
M.FLAT = FLAT

-- 干河谷：两条南北向、蜿蜒的浅沟（深 7 格，河岸缓坡，车开得过去），南北两头 600 格慢慢收平；F 据点的桥跨在东边那条上
local WADIS = { { x = -3400, a = 260, k = 2400, ph = 0.6, z0 = -3000, z1 = 3000 }, { x = 6200, a = 200, k = 2000, ph = 2.2, z0 = -4200, z1 = 1800 } }
local function wadiX(W, z) return W.x + W.a * sin(z / W.k + W.ph) + 90 * noise(z / 700, W.x / 1000, 5.5) end

-- 这一点离「要压平 / 要让开」的东西有多近：0 完全压平 ～ 1 完全自然
local function flatMask(x, z)
  local m = 1
  for _, f in ipairs(FLAT) do
    if f.rect then
      local dx = max(f.x0 - x, 0, x - f.x1)
      local dz = max(f.z0 - z, 0, z - f.z1)
      if dx < f.m and dz < f.m then
        local d = sqrt(dx * dx + dz * dz)
        if d < f.m then m = min(m, smooth(0, f.m, d)) end
      end
    else
      local dx, dz = x - f.x, z - f.z
      local d2 = dx * dx + dz * dz
      if d2 < f.r2 * f.r2 then m = min(m, smooth(f.r, f.r2, sqrt(d2))) end
    end
  end
  local rd, _, rw = roadNear(x, z)
  if rd then m = min(m, smooth(rw * 0.5 + 6, rw * 0.5 + 90, rd)) end
  return m
end

local function dunes(x, z)
  local h = 0
  for _, E in ipairs(ERGS) do
    local dx, dz = abs(x - E[1]), abs(z - E[2])
    if dx < E[3] + 500 and dz < E[4] + 500 then
      local w = (1 - smooth(E[3], E[3] + 500, dx)) * (1 - smooth(E[4], E[4] + 500, dz))
      -- 横向沙丘：脊线大致东西走向、弯弯曲曲；迎风坡缓、背风坡陡（往上偏的幂）
      local u = z + 150 * noise(x / 1700, 3.1, 0.3) + 55 * noise(x / 520, 7.7, 0.9)
      local s = 0.5 + 0.5 * sin(u / 460 * 2 * PI)
      local crest = s * s * (1.6 - 0.6 * s)
      local amp = 16 + 38 * (0.5 + 0.5 * noise(x / 2600, z / 2600, 1.7))
      local fine = 2.5 * (0.5 + 0.5 * noise(x / 95, z / 95, 4.4))
      h = max(h, w * (crest * amp + fine + 3))
    end
  end
  return h
end
local function mesas(x, z)
  local h = 0
  for _, ms in ipairs(MESAS) do
    local dx, dz = x - ms[1], z - ms[2]
    local reach = ms[3] + TALUS + 50
    if abs(dx) < reach and abs(dz) < reach then
      local d = sqrt(dx * dx + dz * dz)
      local wob = 34 * noise(dx / 150, dz / 150, ms[1] / 1000) + 14 * noise(dx / 45, dz / 45, 2.2)
      local r = ms[3] + wob
      local top = ms[4] * (1 - smooth(r - 6, r + 26, d))                -- 陡壁
      local talus = ms[4] * 0.32 * (1 - smooth(r, r + TALUS, d))       -- 坡脚的碎石坡
      local layer = (top > 2) and ms[4] * 0.04 * floor((top / ms[4]) * 5 + 0.5) / 5 or 0   -- 一层层的砂岩台阶感
      h = max(h, max(top + layer, talus))
    end
  end
  return h
end
local function hills(x, z)
  local h = 0
  for _, H in ipairs(HILLS) do
    local dx, dz = x - H[1], z - H[2]
    if abs(dx) < H[3] * 1.55 and abs(dz) < H[3] * 1.55 then
      local d = sqrt(dx * dx + dz * dz)
      local k = clamp(1 - d / (H[3] * 1.5), 0, 1)
      h = max(h, H[4] * k * k * (3 - 2 * k) * (1 + 0.12 * noise(dx / 160, dz / 160, 9.1)))
    end
  end
  return h
end
local function ridge(x, z)
  local R = RIDGE
  if x < R.x0 - 300 or x > R.x1 + 300 or abs(z - R.z) > R.w * 2.5 then return 0 end
  local along = smooth(R.x0 - 300, R.x0 + 200, x) * (1 - smooth(R.x1 - 200, R.x1 + 300, x))
  local gap = smooth(80, 260, abs(x))   -- 中间豁口（雷达站那条路过）
  local zc = R.z + 120 * noise(x / 900, 1.3, 0)
  local k = clamp(1 - abs(z - zc) / R.w, 0, 1)
  local crag = 0.7 + 0.5 * noise(x / 60, z / 60, 3.3)
  return R.h * along * gap * k * k * crag
end
local function wadi(x, z)
  local cut = 0
  for _, W in ipairs(WADIS) do
    if z > W.z0 - 600 and z < W.z1 + 600 then
      local d = abs(x - wadiX(W, z))
      if d < 140 then
        local ends = smooth(W.z0 - 600, W.z0, z) * (1 - smooth(W.z1, W.z1 + 600, z))
        cut = max(cut, 7 * ends * (1 - smooth(24, 120, d)))
      end
    end
  end
  return cut
end

-- 地面高度（格）；后面几个返回值：这一点有多少是「自然地貌」（0 压平～1）、沙丘贡献多少、台地贡献多少（材质用）
local function heightParts(x, z)
  if abs(x) > M.EXT or abs(z) > M.EXT then return M.BASE_Y, 0, 0, 0 end
  local du = dunes(x, z)
  local me = mesas(x, z)
  local hi = hills(x, z)
  local ri = ridge(x, z)
  local wa = wadi(x, z)
  if du == 0 and me == 0 and hi == 0 and ri == 0 and wa == 0 then return M.BASE_Y, 1, 0, 0 end
  local m = flatMask(x, z)
  -- 古城、雷达站的山头不被据点压平（据点在山顶上）：山丘不乘压平系数
  local feat = max(du * m, me * (m * 0.85 + 0.15), hi, ri * m)
  local y = M.BASE_Y + feat - wa * m
  for _, t in ipairs(TOPS) do   -- 山顶压平一块（据点 C、E 的场地）
    local dx, dz = x - t[1], z - t[2]
    local d2 = dx * dx + dz * dz
    if d2 < 340 * 340 then y = lerp(y, M.BASE_Y + t[3], 1 - smooth(170, 320, sqrt(d2))) end
  end
  return max(y, 1), m, du, me
end
M.parts = heightParts   -- 写地形（World.lua）：一次拿齐高度、压平系数、沙丘、台地，材质不用再算一遍

function M.height(x, z)
  local y = heightParts(x, z)
  return y, 1e9
end
function M.ground(x, z) return (heightParts(x, z)) end
function M.isLand(x, z) return abs(x) < M.R and abs(z) < M.R end
function M.slope(x, z)
  local e = 4
  local a, b = M.height(x + e, z), M.height(x - e, z)
  local c, d = M.height(x, z + e), M.height(x, z - e)
  return sqrt(((a - b) / (2 * e)) ^ 2 + ((c - d) / (2 * e)) ^ 2)
end
function M.flatW(x, z) return 1 - flatMask(x, z) end
function M.landOf() return "main" end
function M.landingOf() return nil end
function M.coastS() return nil end
function M.coastN() return nil end
function M.inHarbor() return false end
function M.beachAt() return nil end

---------------------------------------------------------------- 材质

local function materialOf(x, z, y, slope, m, du, me)
  slope = slope or 0
  if slope > 1.25 then return Enum.Material.Rock end
  if me > 10 and slope > 0.55 then return Enum.Material.Sandstone end
  if me > 30 then return (noise(x / 40, z / 40, 1.1) > 0.25) and Enum.Material.Sandstone or Enum.Material.Ground end
  if du > 2.5 then return Enum.Material.Sand end
  -- 干河谷底：碎石泥地
  for _, W in ipairs(WADIS) do
    if abs(x - wadiX(W, z)) < 40 then return Enum.Material.Ground end
  end
  if m < 0.15 then return Enum.Material.Ground end   -- 基地、据点压平的地：夯实的土
  -- 平原：沙地为主，零星的砾石滩、盐碱地
  local n = noise(x / 900, z / 900, 2.6)
  if n > 0.42 then return Enum.Material.Ground end
  if n < -0.55 then return Enum.Material.Salt end
  return Enum.Material.Sand
end
M.materialOf = materialOf
function M.material(x, z, y, slope)
  local _, m, du, me = heightParts(x, z)
  return materialOf(x, z, y, slope, m, du, me)
end

---------------------------------------------------------------- 写地形的块

-- 有起伏的地方（沙丘区、台地、山丘、石岭、河谷）：World 只给这些块写体素，别处 FillBlock 铺平（平地上没有一点起伏，见上面）
function M.detailBoxes()
  local b = {}
  for _, E in ipairs(ERGS) do table.insert(b, { E[1] - E[3] - 520, E[2] - E[4] - 520, E[1] + E[3] + 520, E[2] + E[4] + 520 }) end
  for _, ms in ipairs(MESAS) do
    local r = ms[3] + TALUS + 60
    table.insert(b, { ms[1] - r, ms[2] - r, ms[1] + r, ms[2] + r })
  end
  for _, H in ipairs(HILLS) do
    local r = H[3] * 1.55
    table.insert(b, { H[1] - r, H[2] - r, H[1] + r, H[2] + r })
  end
  table.insert(b, { RIDGE.x0 - 300, RIDGE.z - RIDGE.w * 2.5, RIDGE.x1 + 300, RIDGE.z + RIDGE.w * 2.5 })
  for _, W in ipairs(WADIS) do
    table.insert(b, { W.x - W.a - 240, W.z0 - 620, W.x + W.a + 240, W.z1 + 620 })
  end
  return b
end
M.landBoxes = M.detailBoxes

for _, p in ipairs(M.POINTS) do p.y = M.ground(p.x, p.z) end
for _, k in ipairs({ "AIRFIELD", "AFIELD2", "CAMP", "CAMP_ATK" }) do M[k].y = M.ground(M[k].x, M[k].z) end
for _, B in pairs(M.BASES) do
  for _, k in ipairs({ "motor", "heli" }) do B[k].y = M.ground(B[k].x, B[k].z) end
end

-- 两点之间的直线有没有被地形挡住（Map.lua 的那份是通用的，这里不用重写；保留接口一致）
M.clamp, M.smooth, M.lerp = clamp, smooth, lerp

return M
