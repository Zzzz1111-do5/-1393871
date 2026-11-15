-- 登岛战地图（ReplicatedStorage.Map）：纯数学，服务器、客户端算出来一样（地形、小地图、出生点、据点都用它）
--   坐标：X 东西（东为正），Z 南北（北是 −Z），海平面 Y = 0；地形范围 ±4096 格，再往外是一块平面当远海
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

Map.R = 4096           -- 地形范围 ±R
Map.SEA_DEPTH = 12     -- 远海水深（格）
Map.MAXH = 290         -- 高度系数 1 对应多少格（主峰约 250）
Map.RES = 4            -- 地形体素边长

---------------------------------------------------------------- 主岛

local MI = { x = 0, z = -1500, hs = 1500, S = 800, N = 760 }   -- 中心、东西半宽、南岸 / 北岸离中线最远多少
Map.MAIN = MI
local PH = { 0.7, 2.1, 4.0, 1.3, 5.2, 3.3, 0.4, 2.8, 4.6, 1.9, 3.7, 5.9 }   -- 起伏的相位（网页版按种子随机，这里定死：每局一样）
local BAY = { x = -495, w = 120, d = 320 }   -- 港湾：中心、半宽、伸进岛里多深
local CAPES = { { x = -1110, ext = 150, w = 105 }, { x = 1200, ext = 130, w = 95 } }   -- 南岸东西两个岬角：伸出多远、半宽
Map.BAY = BAY

local function southRaw(x)
  local u = (x - MI.x) / MI.hs
  if abs(u) >= 1 then return nil end
  local f = (1 - abs(u) ^ 3.5) ^ 0.45   -- 南岸正面宽而平缓（能登陆的岸段长），东西两头陡收
  local c = MI.S * f + f * (35 * sin(x / 155 + PH[1]) + 14 * sin(x / 48 + PH[2]) + 6 * sin(x / 21 + PH[3]))
  for _, k in ipairs(CAPES) do c += k.ext * f * exp(-((x - k.x) / k.w) ^ 2) end
  local q = (x - BAY.x) / BAY.w
  c -= BAY.d * exp(-((q * q) ^ 1.6))   -- U 形湾：湾底平、湾口不收窄
  return MI.z + c
end
local function northRaw(x)
  local u = (x - MI.x) / MI.hs
  if abs(u) >= 1 then return nil end
  local g = (1 - abs(u) ^ 3) ^ 0.5
  local c = MI.N * g + g * (30 * sin(x / 140 + PH[4]) + 16 * sin(x / 53 + PH[5]) + 7 * sin(x / 19 + PH[6]))
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
  { id = "red", x0 = -980, x1 = -820, color = Color3.fromRGB(215, 70, 60) },
  { id = "white", x0 = -200, x1 = -40, color = Color3.fromRGB(235, 235, 235) },
  { id = "blue", x0 = 250, x1 = 410, color = Color3.fromRGB(70, 130, 230) },
  { id = "gold", x0 = 690, x1 = 850, color = Color3.fromRGB(235, 190, 60) },
  { id = "flank", x0 = 820, x1 = 960, north = true, color = Color3.fromRGB(150, 110, 220) },
}
for _, b in ipairs(Map.BEACHES) do
  b.cx = (b.x0 + b.x1) / 2
  b.z = (b.north and Map.coastN or Map.coastS)(b.cx)
  b.dir = b.north and -1 or 1   -- 朝海的方向（Z）：南岸的海在南（+Z），北岸的海在北
end
local function beachAt(x, north)
  for _, b in ipairs(Map.BEACHES) do
    if (b.north == true) == (north == true) and x >= b.x0 - 25 and x <= b.x1 + 25 then return b end
  end
  return nil
end
Map.beachAt = beachAt

local function ridgeZ(x) return MI.z - 230 + 65 * sin(x / 260 + PH[7]) + 30 * sin(x / 85 + PH[8]) end
Map.ridgeZ = ridgeZ
local HILLS = {
  { x = -420, z = MI.z - 450, r = 300, h = 0.95 },   -- 西北主峰
  { x = -760, z = MI.z - 90, r = 250, h = 0.5 },
  { x = 470, z = MI.z - 200, r = 270, h = 0.5 },
  { x = 1060, z = MI.z - 330, r = 190, h = 0.4 },
}

-- 机场（守方，东部沿海平原，跑道东西向）、指挥所（山脊北面）、后方营地（北岸，不能占）、港口镇（湾底）
local afX = 780
Map.AIRFIELD = { x = afX, z = (Map.coastS(afX) or 0) - 470, len = 560, wid = 44, rot = 0 }
local AFP = { x = afX, z = Map.AIRFIELD.z - 40 }   -- 机场一带是一片低平的沿海平原（mainNatural 里压低）
Map.COMMAND = { x = 260, z = ridgeZ(260) - 230 }
Map.CAMP = { x = 140, z = (Map.coastN(140) or 0) + 120 }
Map.PORT = { x = BAY.x, z = (Map.coastS(BAY.x) or 0) - 70 }

---------------------------------------------------------------- 小岛

local ISLES = {
  { id = "outpost", x = 150, z = 500, a = 230, b = 170, h = 34, ph = 1.1 },   -- 前哨岛：离攻方舰队最近
  { id = "lighthouse", x = 2500, z = -300, a = 300, b = 230, h = 62, ph = 2.7 },   -- 灯塔岛（东）
  { id = "westreef", x = -2500, z = -200, a = 270, b = 220, h = 46, ph = 4.2 },   -- 西礁岛：岸防炮台
  { id = "afield", x = 0, z = 3200, a = 620, b = 230, h = 6, ph = 0.3, flat = true },   -- 攻方机场岛：平的
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
  if rho > I.a * 1.3 + 400 then return -1e9, 1, rho end
  local R = isleRad(I, math.atan2(dz, dx))
  return R - rho, R, rho
end

-- 5 个据点：A 前哨岛、B 灯塔岛、C 港口镇、D 机场、E 指挥所（开局都归守方）
Map.POINTS = {
  { id = "A", x = 150, z = 500, isle = "outpost" },
  { id = "B", x = 2480, z = -320, isle = "lighthouse" },
  { id = "C", x = Map.PORT.x, z = Map.PORT.z },
  { id = "D", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z - 80 },   -- 机场北面的停机坪、塔台一带
  { id = "E", x = Map.COMMAND.x, z = Map.COMMAND.z },
}
Map.POINT_R = 70   -- 据点半径

-- 攻方舰队（固定平台，打不掉）、机场岛跑道
Map.FLEET = {
  { kind = "carrier", x = -420, z = 2250, rot = 0 },   -- 航母（福建舰）
  { kind = "lhd", x = 330, z = 2150, rot = 0 },   -- 两栖攻击舰（075）
  { kind = "lst", x = -1000, z = 2050, rot = 0 },   -- 登陆舰（072A）
  { kind = "lst", x = 950, z = 2050, rot = 0 },
}
Map.AFIELD2 = { x = 0, z = 3200, len = 900, wid = 50, rot = 0 }

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
  local e = 0.06 + min(0.18, d / 1500)
  e += 0.3 * exp(-((z - ridgeZ(x)) ^ 2) / 22500) * smooth(0, 0.5, 1 - abs(u)) * (1 - 0.75 * exp(-((x - 180) / 110) ^ 2))   -- 中央山脊，偏东一个山口
  for _, h in ipairs(HILLS) do e += h.h * exp(-((x - h.x) ^ 2 + (z - h.z) ^ 2) / (2 * h.r * h.r)) end
  local bS = beachAt(x, false)
  local headland = not bS and not (abs(x - BAY.x) < BAY.w + 60) and (abs(x - CAPES[1].x) < CAPES[1].w * 1.2 or abs(x - CAPES[2].x) < CAPES[2].w * 1.2)
  if headland then e += 0.14 * exp(-((dS - 35) ^ 2) / 2250) end   -- 岬角：岸边陡起的崖顶
  e += noise(x / 300, z / 300, 1.37) * 0.16 + noise(x / 110, z / 110, 7.1) * 0.06   -- 起伏
  e *= lerp(0.4, 1, smooth(20, 325, d))   -- 沿海平原
  do   -- 东部沿海平原（机场）：一大片低平地（往一个平的高度抹），往外慢慢抬起来
    local qx, qz = max(0, abs(x - AFP.x) - 330), max(0, abs(z - AFP.z) - 160)
    e = lerp(0.075, e, smooth(40, 520, sqrt(qx * qx + qz * qz)))
  end
  if bS and dS < 160 then e *= lerp(0.35, 1, smooth(15, 120, dS)) end   -- 海滩后方平缓
  local bN = beachAt(x, true)
  if bN and dN < 160 then e *= lerp(0.35, 1, smooth(15, 120, dN)) end
  e = clamp(1 - exp(-1.35 * max(0, e)), 0, 1)   -- 软压缩：高处越来越缓，不会削成平顶台地
  local y = e * Map.MAXH
  local edge = ((bS and dS < dN) or (bN and dN <= dS)) and 70 or (headland and dS < dN and 18 or 45)
  return y * smooth(0, edge, d) + 0.6, d, dS, dN
end

local function isleNatural(I, x, z)
  local d, R, rho = isleD(I, x, z)
  if d <= 0 then return nil, d end
  local y
  if I.flat then
    y = I.h * smooth(0, 60, d)
  else
    local k = clamp(rho / R, 0, 1)
    y = I.h * (1 - k * k) ^ 0.8 + (noise(x / 90, z / 90, I.ph * 3) * 0.5) * I.h * 0.25 * smooth(0, 80, d)
    y *= smooth(0, 40, d)
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
  return -min(Map.SEA_DEPTH, 1.2 + off * k), -off
end

function Map.height(x, z)
  local y, d = natural(x, z)
  if y <= 0.3 then return y, d end
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
    if w > 0 then y = lerp(y, max(F.y, 0.8), w * smooth(0, 25, d)) end   -- 岸边那一点不压（不改岸线）
  end
  return y, d
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
for _, p in ipairs(Map.POINTS) do flatHere(p.x, p.z, 55, 110) end
do local A = Map.AIRFIELD addRect(A.x, A.z - 40, A.len / 2 + 50, 120, 170, max(4, avgNatural(A.x, A.z - 40, 200))) end   -- 跑道 + 北面停机坪
flatHere(Map.CAMP.x, Map.CAMP.z, 70, 170)
flatHere(Map.PORT.x, Map.PORT.z, 80, 190)
addRect(Map.AFIELD2.x, Map.AFIELD2.z, Map.AFIELD2.len / 2 + 20, 70, 60, 6)
for _, p in ipairs(Map.POINTS) do p.y = Map.ground(p.x, p.z) end
for _, k in ipairs({ "AIRFIELD", "COMMAND", "CAMP", "PORT", "AFIELD2" }) do Map[k].y = Map.ground(Map[k].x, Map[k].z) end

---------------------------------------------------------------- 材质

function Map.material(x, z, y, slope)
  if y <= 0.4 then
    return (y > -3.5) and Enum.Material.Sand or Enum.Material.Sand
  end
  local zs, zn = Map.coastS(x), Map.coastN(x)
  local nearBeach = y < 8 and zs and ((beachAt(x, false) and zs - z > -10 and zs - z < 90) or (beachAt(x, true) and z - zn > -10 and z - zn < 90))
  if nearBeach or y < 2.2 then return Enum.Material.Sand end
  if slope > 1.15 then return (y > 120) and Enum.Material.Slate or Enum.Material.Rock end
  if y > 232 then return Enum.Material.Rock end
  if slope > 0.75 then return Enum.Material.Ground end
  local n = noise(x / 85, z / 85, 11.3)
  if y < 9 and n > 0.15 then return Enum.Material.Ground end
  return (n > -0.1) and Enum.Material.LeafyGrass or Enum.Material.Grass
end

---------------------------------------------------------------- 有陆地的范围（开服生成地形只写这些块）

-- 返回 { x0, z0, x1, z1 } 若干个：主岛、各小岛，外扩一圈浅滩
function Map.landBoxes()
  local pad = 120
  local boxes = { { MI.x - MI.hs - pad, MI.z - MI.N - 140 - pad, MI.x + MI.hs + pad, MI.z + MI.S + 200 + pad } }
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
