--!native
-- 全面大战场——训练场（ReplicatedStorage.MapRange）：自己的一张图，在区块 Zones.RANGE（中心 (0, 0, 100352)），纯数学，服务器、客户端算出来一样
--   用户 11-26 晚：「把训练场单独做一张地图吧」——原来试驾在战场边上打靶（钢城东边丘陵），开出去就进了战场。这张图（区块里的相对坐标：u 往东、w 往南）：
--   · 射击线（w = 3000）上一排 8 条靶道，每条 960 格宽，车停在线上朝北打；靶车在 300 / 500 / 700 / 1000 / 1300 / 1600 / 2000 米，
--     靶道是压实的土路（一路打到 2000 米的位置），尽头一道八十格高的挡弹土墙（炮弹不往远处飞）；靶道两边每 100 米一块距离牌（Range.lua 建）
--   · 西边一条 3600 格（约 1.3 公里）的跑道（东西向），北边停机坪、机库、塔台：试飞的飞机停在跑道东头，朝西起飞
--   · 挡弹墙北面是空中靶区：对地的靶车、靶机绕着它飞
--   · 射击线东头直升机坪
--   · 四周几座丘陵（远景，也挡一挡视线），再往外一圈平地铺到 ±12288，更外面是客户端跟着镜头的平地（Scenery.lua）
--   地形不比战场：大部分是平地（开服时 FillBlock 一大块一大块铺，几秒钟），只有挡弹墙、丘陵按高度逐列写体素
local Zones = require(script.Parent:WaitForChild("Zones"))

local R = {}
local abs, sqrt, exp, max, min, floor = math.abs, math.sqrt, math.exp, math.max, math.min, math.floor
local noise = math.noise
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end

local RX, RZ = Zones.RANGE.x, Zones.RANGE.z
R.X, R.Z = RX, RZ
R.R = Zones.RANGE.R
R.PLAY = Zones.RANGE.PLAY
local PLAIN = 12   -- 平地高度（同钢城：4 的倍数，FillBlock 铺出来和逐列写的一样高）
R.PLAIN = PLAIN
local M = 2.8      -- 一米多少格

---------------------------------------------------------------- 布局（区块里的相对坐标）

R.FIRE_W = 3000                 -- 射击线
R.LANES = 8
R.LANE_W = 960                 -- 一条靶道 960 格（约 340 米）宽：最远那几辆靶车横着来回开也不出自己的靶道
local LANE_U0 = -(R.LANES - 1) * R.LANE_W / 2
R.DIST = { 300, 500, 700, 1000, 1300, 1600, 2000 }   -- 靶车的距离（米）
local TRACK_HALF = 34           -- 靶道土路半宽
local TRACK_END = R.FIRE_W - 2000 * M - 260   -- 土路一直铺到 2000 米靶位再往前一点
R.BERM_W, R.BERM_H, R.BERM_HALF = -3300, 84, 4300   -- 挡弹土墙：中线、高、半长
R.RWY = { u0 = -11200, u1 = -7600, w = 700, wid = 90 }   -- 跑道（东西向，同战场的机场：World.airfield 建，北边停机坪、机库、塔台）
R.HELI = { u = 3950, w = 3150 } -- 直升机坪
R.AIRTGT = { u = 0, w = -6600 } -- 空中靶区中心
-- 开服先铺的那片平地（Range.lua；2048 的倍数，客户端那圈远处平地在这片里沉下去：Scenery.lua）
R.CORE = { u0 = -12288, u1 = 8192, w0 = -8192, w1 = 6144 }

-- 丘陵：u、w、半径、高（格）
local HILLS = {   -- 八座（逐列写体素的块只在它们和挡弹墙上：开服后台写，一两分钟写完，靶场那片开服就有）
  { -9600, -3000, 2200, 165 }, { -7800, -8600, 1800, 120 },
  { 8200, -1800, 2100, 150 }, { 7600, -7600, 1900, 140 },
  { -3200, -10400, 2000, 160 }, { 3600, -10600, 2100, 180 },
  { -2800, 9600, 1900, 100 }, { 4400, 9800, 2100, 125 },
}
R.HILLS = HILLS

function R.toLocal(x, z) return x - RX, z - RZ end
function R.toWorld(u, w) return u + RX, w + RZ end

---------------------------------------------------------------- 高度

local function bump(d2, r) -- (1 − x²)²，x = d / r：只在半径以内有，边上平滑接到平地
  local x2 = d2 / (r * r)
  if x2 >= 1 then return 0 end
  local a = 1 - x2
  return a * a
end
local function relief(u, w)
  local h = 0
  -- 挡弹土墙：横在靶道尽头，两头收进地里
  local dw = (w - R.BERM_W) / 300
  if dw * dw < 9 then
    local ends = 1 - smooth(R.BERM_HALF - 700, R.BERM_HALF, abs(u))
    h += R.BERM_H * exp(-dw * dw) * ends * (0.92 + 0.08 * noise(u / 400, w / 400, 3.7))
  end
  -- 丘陵：每座一个平滑的鼓包，上面叠两层起伏（看着像真山包，不是馒头）
  for i = 1, #HILLS do
    local hl = HILLS[i]
    local du, dv = u - hl[1], w - hl[2]
    local b = bump(du * du + dv * dv, hl[3])
    if b > 0 then
      local n1 = noise(u / 1300 + i * 7.1, w / 1300, 1.3)
      local n2 = noise(u / 420, w / 420 + i * 3.3, 2.9)
      h += hl[4] * b * (0.78 + 0.32 * n1 + 0.12 * n2)
    end
  end
  return max(h, 0)
end
-- 平地就是平的（开服时整片 FillBlock 铺在 PLAIN，按高度函数逐列写的只有挡弹墙和丘陵：高度函数要和真地形对得上，车、靶子摆得平）
function R.heightLocal(u, w)
  return PLAIN + relief(u, w)
end
function R.height(x, z) return R.heightLocal(x - RX, z - RZ), 1e9 end
function R.ground(x, z) return R.heightLocal(x - RX, z - RZ) end
function R.isLand() return true end
function R.slope(x, z)
  local e = 4
  local hx = R.ground(x + e, z) - R.ground(x - e, z)
  local hz = R.ground(x, z + e) - R.ground(x, z - e)
  return sqrt(hx * hx + hz * hz) / (2 * e)
end
function R.flatW() return 0 end

-- 有没有起伏（地形按块写：没起伏的整块 FillBlock，有的逐列写体素）：这一块（世界坐标 x0..x1, z0..z1）碰不碰得到挡弹墙、丘陵
function R.reliefIn(x0, z0, x1, z1)
  local u0, w0, u1, w1 = x0 - RX, z0 - RZ, x1 - RX, z1 - RZ
  if u1 > -R.BERM_HALF - 50 and u0 < R.BERM_HALF + 50 and w1 > R.BERM_W - 1000 and w0 < R.BERM_W + 1000 then return true end
  for i = 1, #HILLS do
    local hl = HILLS[i]
    local cu, cw = clamp(hl[1], u0, u1), clamp(hl[2], w0, w1)
    local du, dv = cu - hl[1], cw - hl[2]
    if du * du + dv * dv < hl[3] * hl[3] then return true end
  end
  return false
end

---------------------------------------------------------------- 材质

local MAT = Enum.Material
local function onTrack(u, w)
  if w > R.FIRE_W + 120 or w < TRACK_END then return false end
  local i = floor((u - LANE_U0) / R.LANE_W + 0.5)
  if i < 0 or i >= R.LANES then return false end
  return abs(u - (LANE_U0 + i * R.LANE_W)) < TRACK_HALF + noise(u / 30, w / 30) * 6
end
function R.material(x, z, y, slope)
  local u, w = x - RX, z - RZ
  slope = slope or 0
  if onTrack(u, w) then return MAT.Ground end
  -- 射击线后面压出来的一条土路（各靶道的车开上开下）、跑道两边的土
  if abs(w - (R.FIRE_W + 160)) < 40 and abs(u) < -LANE_U0 + R.LANE_W / 2 then return MAT.Ground end
  if abs(w - R.RWY.w) < R.RWY.wid / 2 + 30 and u > R.RWY.u0 - 60 and u < R.RWY.u1 + 60 then return MAT.Ground end
  if slope > 0.75 then return MAT.Rock end
  if slope > 0.42 then return MAT.Ground end
  -- 挡弹墙：被炮弹翻过的土
  local dw = abs(w - R.BERM_W)
  if dw < 520 and abs(u) < R.BERM_HALF then return (slope > 0.18 or noise(u / 60, w / 60, 1.1) > 0.2) and MAT.Ground or MAT.Grass end
  -- 草地里几片深一点的（LeafyGrass）、几块裸土
  local n = noise(u / 700, w / 700, 4.4)
  if n > 0.42 then return MAT.LeafyGrass end
  if n < -0.5 and slope < 0.2 then return MAT.Ground end
  return MAT.Grass
end
function R.underMat(top) return (top == MAT.Rock) and MAT.Rock or MAT.Ground end

-- 视线（地形挡不挡）：沿线段取样高度
function R.lineClear(a, b, step)
  local d = b - a
  local L = d.Magnitude
  if L < 1 then return true end
  local n = math.ceil(L / (step or 24))
  for i = 1, n - 1 do
    local p = a + d * (i / n)
    if R.ground(p.X, p.Z) > p.Y then return false end
  end
  return true
end
function R.navBlocked() return false end
function R.segBlocked() return false end
function R.roadDist() return 1e9 end

-- 客户端跟着镜头铺的远处平地（Scenery.lua）：草地，顶面和平地一样高
R.FAR = { color = Color3.fromRGB(80, 108, 56), mat = "Grass", y = PLAIN - 0.5 }

---------------------------------------------------------------- 试驾用的位置（世界坐标）

-- 第 i 条靶道（1 ~ LANES）射击线上的车位：位置、朝向（朝北）
function R.lane(i)
  i = ((i - 1) % R.LANES) + 1
  local u = LANE_U0 + (i - 1) * R.LANE_W
  local x, z = R.toWorld(u, R.FIRE_W)
  return Vector3.new(x, R.ground(x, z), z), Vector3.new(0, 0, -1)
end
-- 靶道正中线上离射击线 dist 米、往右偏 side 米的那一点（Tech.lua 摆靶车）
function R.laneAt(i, dist, side)
  local p = R.lane(i)
  local x, z = p.X + (side or 0) * M, p.Z - dist * M
  return Vector3.new(x, R.ground(x, z), z)
end
-- 跑道东头（起飞位，第 k 架往后排）：位置、朝向（朝西）
function R.runwayStart(k)
  k = k or 0
  local x, z = R.toWorld(R.RWY.u1 - 160 - floor(k / 2) * 110, R.RWY.w + ((k % 2 == 0) and -18 or 18))
  return Vector3.new(x, R.ground(x, z), z), Vector3.new(-1, 0, 0)
end
function R.heliPad(k)
  local x, z = R.toWorld(R.HELI.u + ((k or 0) % 3 - 1) * 70, R.HELI.w + floor((k or 0) / 3) * 70)
  return Vector3.new(x, R.ground(x, z), z), Vector3.new(0, 0, -1)
end
function R.airTarget()
  local x, z = R.toWorld(R.AIRTGT.u, R.AIRTGT.w)
  return Vector3.new(x, R.ground(x, z), z)
end
-- 跑道（World.airfield 照它建：中心、长、宽；东西向）
function R.airfield()
  local x, z = R.toWorld((R.RWY.u0 + R.RWY.u1) / 2, R.RWY.w)
  return { x = x, z = z, len = R.RWY.u1 - R.RWY.u0, wid = R.RWY.wid, rot = 0, team = "range" }
end

return R
