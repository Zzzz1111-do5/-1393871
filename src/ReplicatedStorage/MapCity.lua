--!native
-- 全面大战场地图「钢城」（ReplicatedStorage.MapCity，地图 id "city"）：两边各一座带机场的主基地，中间一座城——纯数学，服务器、客户端算出来一样
--   用户 11-26：「改地图，你去 sketchfab 找一个地图加进来吧，这个图不适合对抗」→「做一个两边带机场的城市地图吧」→「要有可以撞倒的树，也可以被打倒」。
--   沙海的地形照真实的海湾战争（二十多公里的平沙、一道岭）：坦克开十几分钟才碰到人，找不到掩护，不适合对着打。这张图：
--   · 南北两头各一座主基地（营区 + 车场 + 直升机坪 + 跑道，FOB.lua 建，同沙海那套），离城边两公里左右——出车一分钟开到城边，飞机就在自家跑道起飞
--   · 中间的城 12 × 12 个街区（一格 512 格 ≈ 180 米，含街道），街道是铺在地面上的零件（柏油），地形整块平地（开服铺地形快）；
--     中央广场（据点 C）、西边公园（B，树多）、东边火车站（D，铁轨、站台、货车厢）、南边工厂（A）、北边电视塔（E）；
--     老城区五到七层的周边式街坊（中间有院子）、中心四座高楼、外圈板楼和低层铺面、几处停车场、工地、被炸过的废墟（坦克的掩护）
--   · 城外一圈郊区小楼（带院子和树）、再往外是农田（一块块不同颜色的地、田埂上一排排树、林子、农舍）；两侧、基地后面是丘陵（只是远景）
--   · 树（Map.TREES）：行道树、公园、院子、田埂、林子——坦克撞上就倒、炮弹炸倒、机枪多打几下也打断（服务器 Trees.lua 记谁倒了，客户端 Scenery.lua 画）
--   · 楼（Map.BLD）：World 开服按这张表盖（CityBuild.lua），能挡车、挡子弹，炸多了会塌（Battle.lua 的房子炸塌）；电脑车寻路、看得见看不见都算楼
--   同沙海一样的接口（height / ground / material / POINTS / BASES / FOB / chunkKind / ……），Map.use("city") 换进 Map 表
local Map = {}
local exp, abs, sin, cos, sqrt, max, min, floor = math.exp, math.abs, math.sin, math.cos, math.sqrt, math.max, math.min, math.floor
local noise = math.noise

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
Map.clamp, Map.smooth, Map.lerp = clamp, smooth, lerp

Map.NAME = "city"
Map.CITY = true
Map.LANDONLY = true    -- 没有海：舰艇、登陆艇、海滩那一套都不用（各模块按它跳过）
Map.GRASS = true       -- 草地写 Grass（长 Roblox 会动的草叶，同岛图）
Map.NOMIDAF = true     -- 两边基地各有跑道，中间没有要打的那座机场（沙海的据点 D 是机场）
local K, HK = 3, 2
Map.K, Map.HK = K, HK
Map.R = 12288          -- 地形范围 ±R（城外丘陵、基地后面都写到这）
Map.PLAY = 24576       -- 飞机的作战区（再往外自动掉头）
Map.SEA_R = 16384      -- 再往外一圈平地（只是远景）
Map.SEA_LIM = 0
Map.SEA_DEPTH = 0
Map.SHELF = 0
Map.MAXH = 260
Map.RES = 4
Map.HALF = 13500       -- 试驾场（Tech.lua testSpot）：东边丘陵上一块（离城一公里多，靶车在丘陵和农田交界那一带）
local PLAIN = 12       -- 平地的高度（4 的倍数：FillBlock 填出来和逐列写的一样高）
Map.PLAIN = PLAIN
local MAT = Enum.Material
-- 地形颜色（World.lua 写地形前 SetMaterialColor）：温带的绿地、灰的人行道和水泥、深灰的柏油
Map.COLORS = {
  Grass = Color3.fromRGB(86, 116, 58), LeafyGrass = Color3.fromRGB(66, 96, 46), Ground = Color3.fromRGB(110, 94, 72),
  Pavement = Color3.fromRGB(146, 144, 138), Concrete = Color3.fromRGB(158, 156, 150), Asphalt = Color3.fromRGB(52, 54, 58),
  Rock = Color3.fromRGB(112, 110, 104), Slate = Color3.fromRGB(92, 94, 96), Mud = Color3.fromRGB(80, 68, 52), Sand = Color3.fromRGB(184, 168, 128),
  Cobblestone = Color3.fromRGB(128, 122, 114), Limestone = Color3.fromRGB(176, 170, 156), Sandstone = Color3.fromRGB(150, 120, 92),
}
-- 地图外面那一圈远景平面（Scenery.lua）：草地的颜色，顶面和平地一样高
Map.FAR = { color = Color3.fromRGB(78, 106, 54), mat = "Grass", y = PLAIN - 0.5 }

local function rng(seed)
  local s = seed % 2147483647
  if s <= 0 then s += 2147483646 end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

---------------------------------------------------------------- 两边的主基地（同沙海：FOB.lua 建营区 + 车场 + 直升机坪 + 跑道）

local FOB = {
  camp = { x0 = -560, x1 = 560, z0 = -420, z1 = 420 },
  runway = { lz = 1150, len = 3600, wid = 90 },
  motor = { lx = -300, lz = -330 },
  heli = { lx = 400, lz = -250 },
  spawn = { lx = 0, lz = -300 },
  air = { lx = -49, lz = 1010 },
  rect = { x0 = -2200, x1 = 2200, z0 = -680, z1 = 1500 },
}
Map.FOB = FOB
local BZ = 6656   -- 基地中心离城中心多远（南北）：基地前沿（围墙外的土堤）在 5976，城的郊区到 3584，中间两公里多是农田
Map.BASES = {
  atk = { x = 0, z = BZ, yaw = 0 },              -- 攻方：南边，朝北打
  def = { x = 0, z = -BZ, yaw = math.pi },       -- 守方：北边，朝南打
}
local function baseW(B, lx, lz)
  local c, s = cos(B.yaw), sin(B.yaw)
  return B.x + lx * c + lz * s, B.z - lx * s + lz * c
end
Map.baseW = baseW
for side, B in pairs(Map.BASES) do
  B.side = side
  B.face = (side == "atk") and -1 or 1
  local function at(lx, lz) local x, z = baseW(B, lx, lz) return { x = x, z = z } end
  B.camp = at(0, 0)
  B.motor = at(FOB.motor.lx, FOB.motor.lz)
  B.heli = at(FOB.heli.lx, FOB.heli.lz)
  B.spawn = at(FOB.spawn.lx, FOB.spawn.lz)
  B.spawns = {}
  for i = 0, 3 do
    for k = 0, 3 do table.insert(B.spawns, at(FOB.spawn.lx + (i - 1.5) * 12, FOB.spawn.lz + (k - 1.5) * 12)) end
  end
  B.airSpawn = at(FOB.air.lx, FOB.air.lz)
  B.airSpawns = {}
  for i = 0, 7 do table.insert(B.airSpawns, at(FOB.air.lx + i * 14, FOB.air.lz)) end
  local rx, rz = baseW(B, 0, FOB.runway.lz)
  B.airfield = { x = rx, z = rz, len = FOB.runway.len, wid = FOB.runway.wid, rot = 0, team = side }
  local xs, zs = {}, {}
  for _, c in ipairs({ { FOB.rect.x0, FOB.rect.z0 }, { FOB.rect.x1, FOB.rect.z0 }, { FOB.rect.x0, FOB.rect.z1 }, { FOB.rect.x1, FOB.rect.z1 } }) do
    local x, z = baseW(B, c[1], c[2])
    table.insert(xs, x) table.insert(zs, z)
  end
  B.rect = { x0 = min(table.unpack(xs)), x1 = max(table.unpack(xs)), z0 = min(table.unpack(zs)), z1 = max(table.unpack(zs)) }
end
Map.REDBASE = Map.BASES.atk.camp
Map.AFIELD2 = Map.BASES.atk.airfield
Map.CAMP = Map.BASES.def.camp
Map.AFIELD3 = Map.BASES.def.airfield
Map.AIRFIELD = Map.AFIELD3   -- 别的模块按沙海那套读「机场」：这张图没有中间那座（NOMIDAF），指向守方自己的跑道，不会单独再建一座

---------------------------------------------------------------- 街道网（城区 12 × 12 个街区；郊区一圈；去两边基地的公路、田间小路）

local GRID, C0, SUB = 512, 3072, 3584   -- 一格多宽、城区 ±C0、郊区外沿 ±SUB
Map.GRID, Map.C0, Map.SUB = GRID, C0, SUB
local FX, FZ = 4608, 8704                -- 平地的范围 ±FX × ±FZ（城、郊区、农田、两边基地；256 的倍数，整块地形都是平的）
Map.FLATX, Map.FLATZ = FX, FZ
local function lineAt(i) return -C0 + i * GRID end
-- 街道宽（格）：中央大道 x = 0、和平大街 z = 0 宽 64（双向四车道），±1536 的大街和环城路（±C0）宽 44，别的 36
local function lineW(v)
  local a = abs(v)
  if a < 1 then return 64 end
  if abs(a - 1536) < 1 or abs(a - C0) < 1 then return 44 end
  return 36
end
Map.lineW = lineW

-- 街坊的种类（i、j：从西往东、从北往南第几个，0～11）
local OPEN = {   -- 几处不盖楼的街坊（坦克的掩护、视野）：停车场、工地、废墟、球场、街心花园
  ["2,3"] = "parking", ["9,8"] = "parking", ["3,6"] = "ruins", ["8,5"] = "ruins", ["5,9"] = "works", ["6,2"] = "works",
  ["1,9"] = "sports", ["10,9"] = nil, ["9,3"] = "garden", ["2,8"] = "garden", ["7,10"] = "parking", ["4,1"] = "parking",
}
local function blockType(i, j)
  if (i == 0 or i == 1) and (j == 5 or j == 6) then return "park" end          -- 西边的公园（据点 B）
  if i == 10 then return (j == 5 or j == 6) and "station" or "rail" end         -- 东边一条铁路（南北穿城），中间是火车站（据点 D）
  if (i == 3 or i == 4) and (j == 9 or j == 10) then return "factory" end       -- 南边的工厂（据点 A）
  if (i == 7 or i == 8) and (j == 1 or j == 2) then return "tv" end             -- 北边的电视塔（据点 E）
  if (i == 5 or i == 6) and (j == 5 or j == 6) then return "square" end         -- 中央广场（据点 C）
  return OPEN[i .. "," .. j] or "city"
end
Map.blockType = blockType

-- 去掉的街段（院子、公园、厂区里不过车行道）：南北向 { x, z0, z1 }、东西向 { z, x0, x1 }
local CUT_NS = { { -2560, -512 + 20, 512 - 20 }, { -1024, 1536 + 20, 2560 - 20 }, { 1024, -2560 + 20, -1536 - 20 } }
local CUT_EW = { { 2048, -1536 + 24, -512 - 20 }, { -2048, 512 + 20, 1536 - 24 }, { 0, 2048 + 18, 2560 - 18 } }   -- 最后一段：和平大街到火车站就断了（站房、站台在那）
local PLAZA = 300   -- 中央广场 |x|, |z| < PLAZA：铺石头，不是柏油
Map.PLAZA = PLAZA

-- 路段（零件铺的）：{ ax, az, bx, bz, w, k, yo }；k：street 柏油街、hw 公路、hw2 斜着的公路、lane 田间土路；
--   yo：路面比平地高多少（互相压着的路段高低错开一点，免得重叠的那一块闪：斜的公路压在直的上面、土路在最底下）
local SEGS = {}
local YO = { street = 0.10, hw = 0.10, hw2 = 0.16, lane = 0.05, lane2 = 0.07 }
local function seg(ax, az, bx, bz, w, k) k = k or "street" table.insert(SEGS, { ax, az, bx, bz, w, k, YO[k] or 0.1 }) end
do
  -- 南北向的街：每条整条铺（东西向的在路口断开，不重叠）
  for i = 0, 12 do
    local x = lineAt(i)
    local w = lineW(x)
    local z0, z1 = -C0 - lineW(C0) / 2, C0 + lineW(C0) / 2
    local cuts = {}
    for _, c in ipairs(CUT_NS) do if abs(c[1] - x) < 1 then table.insert(cuts, c) end end
    if abs(x) < 1 then table.insert(cuts, { 0, -PLAZA, PLAZA, plaza = true }) end
    table.sort(cuts, function(a, b) return a[2] < b[2] end)
    local z = z0
    for _, c in ipairs(cuts) do
      if c[2] > z then seg(x, z, x, c[2], w) end
      z = c[3]
    end
    if z1 > z then seg(x, z, x, z1, w) end
  end
  -- 东西向：两条南北街之间一段
  for j = 0, 12 do
    local z = lineAt(j)
    local w = lineW(z)
    for i = 0, 11 do
      local xa, xb = lineAt(i) + lineW(lineAt(i)) / 2, lineAt(i + 1) - lineW(lineAt(i + 1)) / 2
      local cut = nil
      for _, c in ipairs(CUT_EW) do if abs(c[1] - z) < 1 and c[2] < xb and c[3] > xa then cut = c end end
      if abs(z) < 1 and xa < PLAZA and xb > -PLAZA then   -- 和平大街过广场：广场那一段不铺柏油
        if xa < -PLAZA then seg(xa, z, -PLAZA, z, w) end
        if xb > PLAZA then seg(PLAZA, z, xb, z, w) end
      elseif cut then
        if cut[2] > xa then seg(xa, z, cut[2], z, w) end
        if xb > cut[3] then seg(cut[3], z, xb, z, w) end
      else
        seg(xa, z, xb, z, w)
      end
    end
  end
  -- 郊区：城区的街往外接到郊区外沿（±SUB），外沿一圈路
  local SW = 30
  for i = 0, 12 do
    local x = lineAt(i)
    local w = (abs(x) < 1) and 64 or ((x > 2047 and x < 2561) and 0 or SW)   -- 铁路那两条街：郊区里不接（铁路从中间过）
    if w > 0 and abs(x) < C0 - 1 then   -- 环城路两条（±C0）本身就是郊区的东西两边，不往外接
      seg(x, -SUB + SW / 2, x, -C0 - lineW(C0) / 2, w)
      seg(x, C0 + lineW(C0) / 2, x, SUB - SW / 2, w)
    end
  end
  for j = 0, 12 do
    local z = lineAt(j)
    if abs(z) < C0 - 1 then
      seg(-SUB + SW / 2, z, -C0 - lineW(C0) / 2, z, (abs(z) < 1) and 64 or SW)
      seg(C0 + lineW(C0) / 2, z, SUB - SW / 2, z, (abs(z) < 1) and 64 or SW)
    end
  end
  for _, s in ipairs({ -1, 1 }) do
    seg(-SUB - SW / 2, s * SUB, SUB + SW / 2, s * SUB, SW)           -- 郊区外沿（东西向）
    seg(s * SUB, -SUB + SW / 2, s * SUB, SUB - SW / 2, SW)            -- 郊区外沿（南北向）
  end
  -- 去两边基地的公路：中央大道一直通到基地正门；两条斜着的公路从基地正门外去郊区的两个角
  for _, s in ipairs({ -1, 1 }) do
    local gz = s * (BZ - 640)   -- 基地正门外（FOB 的路从营区南门往外修到 BZ − 620，接上不重叠）
    seg(0, s * (SUB + SW / 2), 0, gz, 64, "hw")
    seg(0, s * (BZ - 700), -1536, s * (SUB + SW / 2), 34, "hw2")
    seg(0, s * (BZ - 700), 1536, s * (SUB + SW / 2), 34, "hw2")
    -- 田间土路：东西两条、南北几条
    for _, zz in ipairs({ 4352, 5120 }) do seg(-FX + 40, s * zz, FX - 40, s * zz, 18, "lane") end
    for _, xx in ipairs({ -3584, -2560, 2560, 3584 }) do seg(xx, s * (SUB + SW / 2), xx, s * 5600, 18, "lane2") end
  end
end
Map.SEGS = SEGS

-- 路段按 64 格的格子登记（查离路多远只看这一格里的）
local RCELL = 64
local rgrid = {}
local function rkey(gx, gz) return (gx + 2048) * 4096 + gz + 2048 end
for k, s in ipairs(SEGS) do
  local pad = s[5] * 0.5 + 12
  for gx = floor((min(s[1], s[3]) - pad) / RCELL), floor((max(s[1], s[3]) + pad) / RCELL) do
    for gz = floor((min(s[2], s[4]) - pad) / RCELL), floor((max(s[2], s[4]) + pad) / RCELL) do
      local key = rkey(gx, gz)
      local l = rgrid[key]
      if not l then l = {} rgrid[key] = l end
      table.insert(l, k)
    end
  end
end
-- 离最近的路多远、那条路的路面高度、路宽（附近没路返回 nil）——路都铺在平地上，路面高度就是平地
local function roadNear(x, z)
  local l = rgrid[rkey(floor(x / RCELL), floor(z / RCELL))]
  if not l then return nil end
  local best, bw, bk = 1e18, 0, nil
  for _, k in ipairs(l) do
    local s = SEGS[k]
    local ax, az = s[1], s[2]
    local dx, dz = s[3] - ax, s[4] - az
    local L2 = dx * dx + dz * dz
    local t = (L2 > 0) and clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1) or 0
    local px, pz = ax + dx * t - x, az + dz * t - z
    local d = px * px + pz * pz
    if d < best then best, bw, bk = d, s[5], s[6] end
  end
  if best >= 1e18 then return nil end
  return sqrt(best), PLAIN, bw, bk
end
Map.roadNear = roadNear
function Map.roadDist(x, z)
  local d = roadNear(x, z)
  return d or 1e9
end
local function onRoad(x, z, pad)
  local d, _, w, k = roadNear(x, z)
  if d and d < w * 0.5 + (pad or 0) then return true, k end
  return false
end
Map.onRoad = onRoad
-- 小地图（MapUI.lua）、电线杆一类按路线画：每段一条两点的折线
Map.ROADS = {}
for _, s in ipairs(SEGS) do
  if s[5] > 0 then table.insert(Map.ROADS, { name = s[6], w = s[5], x = { s[1], s[3] }, z = { s[2], s[4] }, y = { PLAIN, PLAIN } }) end
end
-- 中央广场也画一块（小地图）
table.insert(Map.ROADS, { name = "plaza", w = 60, x = { -PLAZA, PLAZA }, z = { 0, 0 }, y = { PLAIN, PLAIN } })

-- 铁路：南北一条（四股道），城里走 x 2048～2560 那一列，出了郊区往东拐，绕开攻守两边的基地，一直通到地图边上
local RAIL = { x = 2304, tracks = { -72, -40, 40, 72 } }
RAIL.path = { { 4300, -12000 }, { 4300, -6200 }, { 2304, -4200 }, { 2304, 4200 }, { 4300, 6200 }, { 4300, 12000 } }
Map.RAIL = RAIL
local function railNear(x, z)
  local best = 1e18
  local p = RAIL.path
  for i = 1, #p - 1 do
    local ax, az, bx, bz = p[i][1], p[i][2], p[i + 1][1], p[i + 1][2]
    local dx, dz = bx - ax, bz - az
    local L2 = dx * dx + dz * dz
    local t = clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
    local qx, qz = ax + dx * t - x, az + dz * t - z
    local d = qx * qx + qz * qz
    if d < best then best = d end
  end
  return sqrt(best)
end
Map.railNear = railNear

---------------------------------------------------------------- 据点

local P_A = { id = "A", x = -1024, z = 2048 }    -- 南边：钢厂（攻方先打的）
local P_B = { id = "B", x = -2560, z = 0 }       -- 西边：公园
local P_C = { id = "C", x = 0, z = 0 }           -- 中央广场
local P_D = { id = "D", x = 2304, z = 0 }        -- 东边：火车站（站台、货车厢）
local P_E = { id = "E", x = 1024, z = -2048 }    -- 北边：电视塔（守方最后一道）
Map.POINTS = { P_A, P_B, P_C, P_D, P_E }
Map.POINT_R = 90
for _, p in ipairs(Map.POINTS) do p.land = "main" p.y = PLAIN end
Map.TOWN = { x = 0, z = 0, y = PLAIN }
Map.PORT = Map.TOWN
Map.COMMAND = { x = P_E.x, z = P_E.z, y = PLAIN }
-- 岛图的海上那一套：这张图没有
Map.FLEET, Map.BEACHES, Map.LANDINGS, Map.ISLES, Map.CAPES = {}, {}, {}, {}, {}
Map.BARGE = nil
function Map.landingOf() return nil end
function Map.landOf() return "main" end
function Map.beachAt() return nil end
function Map.coastS() return nil end
function Map.coastN() return nil end
function Map.inHarbor() return false end
Map.STARTS = {}
for i, x in ipairs({ -2560, -1024, 1024, 2560 }) do table.insert(Map.STARTS, { id = "s" .. i, x = x, z = SUB + 600, y = PLAIN }) end

---------------------------------------------------------------- 楼（Map.BLD）：{ x, z 中心, w 东西宽, d 南北深, h 高, fl 层数, st 样式, k 种类, sd 种子, id }
--   都是正南正北摆的方盒子（转 0°）：碰撞、寻路、视线都按外接矩形算。World 开服照这张表盖（CityBuild.lua）
--   样式 st：1 灰板楼、2 米黄抹灰、3 红砖、4 浅色石头（老城）、5 玻璃写字楼、6 深色砖（厂房）、7 白色新楼、8 赭黄（老城）

local BLD = {}
Map.BLD = BLD
local FH = 9   -- 一层多高（格，约 3.2 米）
Map.FH = FH
local function addB(x, z, w, d, fl, st, k, sd, extra)
  if w < 12 or d < 12 then return nil end
  local b = { x = x, z = z, w = w, d = d, fl = fl, h = fl * FH + 2, st = st, k = k or "block", sd = sd or (#BLD * 7919 % 100003) }
  if extra then for kk, v in pairs(extra) do b[kk] = v end end
  b.id = #BLD + 1
  BLD[b.id] = b
  return b
end
-- 一块矩形 [x0, x1] × [z0, z1] 里放一座
local function addRect(x0, x1, z0, z1, fl, st, k, sd, extra)
  return addB((x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, fl, st, k, sd, extra)
end

local SIDE = 10   -- 人行道（楼离路边多远）
-- 街坊里能盖楼的范围（扣掉四边的半条街、人行道）
local function interior(i, j)
  local bx0, bx1, bz0, bz1 = lineAt(i), lineAt(i + 1), lineAt(j), lineAt(j + 1)
  return bx0 + lineW(bx0) / 2 + SIDE, bx1 - lineW(bx1) / 2 - SIDE, bz0 + lineW(bz0) / 2 + SIDE, bz1 - lineW(bz1) / 2 - SIDE
end
Map.blockInterior = interior

local STYLE_OLD = { 4, 8, 2, 3, 4, 8 }
local STYLE_MID = { 1, 2, 3, 7, 1, 2 }
local STYLE_OUT = { 1, 1, 7, 2, 3 }
local function pick(t, r) return t[floor(r * #t) + 1] end

-- 周边式街坊（老城、内圈）：四边沿街一圈楼，中间院子；有的一边留个门洞（坦克钻得进院子）
local function perimeter(i, j, R, flo, fhi, styles)
  local x0, x1, z0, z1 = interior(i, j)
  local D = 58 + floor(R() * 4) * 8   -- 进深
  local function run(ax0, ax1, az0, az1, alongX, gap)
    -- 沿一边分成两三座（高矮、样式不同）；gap：中间留一个门洞
    local L = alongX and (ax1 - ax0) or (az1 - az0)
    local n = (L > 360) and 2 or 1   -- 一边一两座（零件少：一座十来块）
    local cuts = { 0 }
    for q = 1, n - 1 do table.insert(cuts, L * (q / n) + (R() - 0.5) * L * 0.12) end
    table.insert(cuts, L)
    local gi = gap and (1 + floor(R() * n)) or nil
    if n == 1 then cuts = { 0, L } end
    for q = 1, n do
      local a, b2 = cuts[q], cuts[q + 1]
      if gi == q then   -- 这一段中间开个 34 格的口
        local m = (a + b2) / 2
        local function put(s0, s1)
          if s1 - s0 < 24 then return end
          if alongX then addRect(ax0 + s0, ax0 + s1, az0, az1, flo + floor(R() * (fhi - flo + 1)), pick(styles, R()), "block", floor(R() * 1e6))
          else addRect(ax0, ax1, az0 + s0, az0 + s1, flo + floor(R() * (fhi - flo + 1)), pick(styles, R()), "block", floor(R() * 1e6)) end
        end
        put(a, m - 17)
        put(m + 17, b2)
      else
        local fl = flo + floor(R() * (fhi - flo + 1))
        if alongX then addRect(ax0 + a, ax0 + b2, az0, az1, fl, pick(styles, R()), "block", floor(R() * 1e6))
        else addRect(ax0, ax1, az0 + a, az0 + b2, fl, pick(styles, R()), "block", floor(R() * 1e6)) end
      end
    end
  end
  local gapSide = floor(R() * 4)
  run(x0, x1, z0, z0 + D, true, gapSide == 0)            -- 北边
  run(x0, x1, z1 - D, z1, true, gapSide == 1)            -- 南边
  run(x0, x0 + D, z0 + D + 6, z1 - D - 6, false, gapSide == 2)   -- 西边
  run(x1 - D, x1, z0 + D + 6, z1 - D - 6, false, gapSide == 3)   -- 东边
end

-- 2 × 2 座、中间十字小巷（坦克能从街坊里穿过去）
local function grid2(i, j, R, flo, fhi, styles)
  local x0, x1, z0, z1 = interior(i, j)
  local a = 30 + floor(R() * 3) * 6   -- 巷宽
  local mx, mz = (x0 + x1) / 2 + (R() - 0.5) * 60, (z0 + z1) / 2 + (R() - 0.5) * 60
  for _, q in ipairs({ { x0, mx - a / 2, z0, mz - a / 2 }, { mx + a / 2, x1, z0, mz - a / 2 }, { x0, mx - a / 2, mz + a / 2, z1 }, { mx + a / 2, x1, mz + a / 2, z1 } }) do
    if R() < 0.9 then
      local m = 4 + R() * 14   -- 每座四周再收进去一点（楼和楼之间有空）
      addRect(q[1] + m, q[2] - m, q[3] + m, q[4] - m, flo + floor(R() * (fhi - flo + 1)), pick(styles, R()), "block", floor(R() * 1e6))
    end
  end
end

-- 两三排平行的长条板楼（外圈住宅区），排和排之间是绿地、停车的空地
local function slabs(i, j, R, flo, fhi)
  local x0, x1, z0, z1 = interior(i, j)
  local alongX = R() < 0.5
  local n = (R() < 0.55) and 2 or 3
  local D = 42 + floor(R() * 3) * 4
  local span = alongX and (z1 - z0) or (x1 - x0)
  local gapL = (span - n * D) / (n - 1)
  for q = 0, n - 1 do
    local o = q * (D + gapL)
    local cut = (R() < 0.35) and (60 + R() * 120) or nil   -- 有的一排中间断开（过车）
    local fl = flo + floor(R() * (fhi - flo + 1))
    local st = (R() < 0.6) and 1 or pick(STYLE_OUT, R())
    if alongX then
      if cut then
        addRect(x0 + 8, cut + x0, z0 + o, z0 + o + D, fl, st, "slab", floor(R() * 1e6))
        addRect(cut + x0 + 36, x1 - 8, z0 + o, z0 + o + D, fl, st, "slab", floor(R() * 1e6))
      else
        addRect(x0 + 8, x1 - 8, z0 + o, z0 + o + D, fl, st, "slab", floor(R() * 1e6))
      end
    else
      if cut then
        addRect(x0 + o, x0 + o + D, z0 + 8, cut + z0, fl, st, "slab", floor(R() * 1e6))
        addRect(x0 + o, x0 + o + D, cut + z0 + 36, z1 - 8, fl, st, "slab", floor(R() * 1e6))
      else
        addRect(x0 + o, x0 + o + D, z0 + 8, z1 - 8, fl, st, "slab", floor(R() * 1e6))
      end
    end
  end
end

-- 高楼：两层的裙楼、上面一座塔楼（中心四个街坊）
local function towers(i, j, R)
  local x0, x1, z0, z1 = interior(i, j)
  local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
  local tw = 74 + floor(R() * 3) * 10
  local fl = 16 + floor(R() * 10)
  addB(cx + (R() - 0.5) * 80, cz + (R() - 0.5) * 80, tw, tw, fl, 5, "tower", floor(R() * 1e6))
  -- 裙楼：塔楼四周四座矮的（两三层），中间留出路
  for _, q in ipairs({ { x0, cx - 70, z0, z0 + 90 }, { cx + 70, x1, z1 - 90, z1 }, { x0, x0 + 90, cz + 70, z1 }, { x1 - 90, x1, z0, cz - 70 } }) do
    if R() < 0.85 then addRect(q[1] + 6, q[2] - 6, q[3] + 6, q[4] - 6, 2 + floor(R() * 3), pick({ 7, 5, 1 }, R()), "low", floor(R() * 1e6)) end
  end
end

-- 低层铺面（外圈）：三乘三小块，两三层，空着几块
local function lowrise(i, j, R)
  local x0, x1, z0, z1 = interior(i, j)
  local nx, nz = 3, 3
  local cw, cd = (x1 - x0) / nx, (z1 - z0) / nz
  for a = 0, nx - 1 do
    for b = 0, nz - 1 do
      if not (a == 1 and b == 1) and R() < 0.8 then
        local m = 8 + R() * 10
        addRect(x0 + a * cw + m, x0 + (a + 1) * cw - m, z0 + b * cd + m, z0 + (b + 1) * cd - m, 2 + floor(R() * 2), pick({ 2, 3, 7, 8 }, R()), "low", floor(R() * 1e6))
      end
    end
  end
end

-- 被炸过的废墟：几座矮的残楼（坦克躲在后面）
local function ruins(i, j, R)
  local x0, x1, z0, z1 = interior(i, j)
  for _ = 1, 4 + floor(R() * 3) do
    local w, d = 50 + R() * 70, 40 + R() * 60
    local x, z = x0 + w / 2 + R() * (x1 - x0 - w), z0 + d / 2 + R() * (z1 - z0 - d)
    addB(x, z, w, d, 1 + floor(R() * 2), pick({ 2, 3, 4 }, R()), "ruin", floor(R() * 1e6))
  end
end

-- 城区：每个街坊按圈数定楼的样子（越靠中间越高越密）
do
  for i = 0, 11 do
    for j = 0, 11 do
      local t = blockType(i, j)
      local R = rng(7001 + i * 131 + j * 977)
      local rr = max(abs(i - 5.5), abs(j - 5.5))   -- 0.5 中心 ～ 5.5 城边
      if t == "city" then
        if rr <= 1.5 then
          if (i == 4 or i == 7) and (j == 4 or j == 7) then towers(i, j, R)
          else perimeter(i, j, R, 5, 7, STYLE_OLD) end
        elseif rr <= 3.5 then
          local r = R()
          if r < 0.4 then perimeter(i, j, R, 4, 6, STYLE_MID)
          elseif r < 0.7 then grid2(i, j, R, 4, 8, STYLE_MID)
          elseif r < 0.88 then slabs(i, j, R, 6, 9)
          else towers(i, j, R) end
        else
          local r = R()
          if r < 0.45 then slabs(i, j, R, 5, 9)
          elseif r < 0.75 then grid2(i, j, R, 3, 6, STYLE_OUT)
          else lowrise(i, j, R) end
        end
      elseif t == "ruins" then
        ruins(i, j, R)
      elseif t == "square" then
        -- 中央广场四周：每个街坊扣掉靠广场的那一角，剩下 L 形两座；西北那座是市政厅（中间一座钟楼），东南是教堂
        local x0, x1, z0, z1 = interior(i, j)
        local east, south = (i == 6), (j == 6)
        -- 竖条：离广场远的那一边（东边的街坊在东、西边的在西），南北全长
        local vx0, vx1 = (PLAZA + 10), x1
        if not east then vx0, vx1 = x0, -(PLAZA + 10) end
        addRect(vx0, vx1, z0, z1, 6, pick(STYLE_OLD, R()), "block", floor(R() * 1e6))
        -- 横条：广场那一角南边（北边）剩下的：东西从街坊靠广场的边到广场边，南北离广场远的那一边
        local hx0, hx1 = x0, PLAZA
        if not east then hx0, hx1 = -PLAZA, x1 end
        local hz0, hz1 = PLAZA + 10, z1
        if not south then hz0, hz1 = z0, -(PLAZA + 10) end
        if i == 5 and j == 5 then
          addRect(hx0, hx1, hz0, hz1, 6, 4, "hall", 5501, { tower = true })   -- 市政厅：朝着广场，顶上一座钟楼
        elseif i == 6 and j == 6 then
          addRect(hx0, hx1, hz0, hz1, 5, 4, "church", 6601, { tower = true })   -- 教堂：一座尖顶钟楼
        else
          addRect(hx0, hx1, hz0, hz1, 6, pick(STYLE_OLD, R()), "block", floor(R() * 1e6))
        end
      end
    end
  end
  -- 钢厂（据点 A，四个街坊连成一个厂区，中间的街去掉了）：四角四座锯齿顶厂房，中间空场（据点），边上办公楼、仓库
  do
    local R = rng(31013)
    local ax, az = P_A.x, P_A.z
    addRect(ax - 470, ax - 190, az - 470, az - 210, 4, 6, "shed", 101)
    addRect(ax + 190, ax + 470, az - 470, az - 210, 4, 6, "shed", 102)
    addRect(ax - 470, ax - 190, az + 210, az + 470, 4, 6, "shed", 103)
    addRect(ax + 190, ax + 470, az + 210, az + 470, 4, 6, "shed", 104)
    addRect(ax - 120, ax + 120, az - 470, az - 370, 4, 3, "block", 105)   -- 厂部办公楼（北边）
    addRect(ax - 140, ax + 140, az + 380, az + 470, 2, 6, "shed", 106)    -- 仓库（南边）
    addRect(ax - 470, ax - 360, az - 120, az + 120, 3, 6, "shed", 107)    -- 西边的车间
    local _ = R
  end
  -- 电视塔（据点 E，四个街坊连成一片）：塔在东南角、广播大楼在西北、东北一座、西南一座演播楼
  do
    local ex, ez = P_E.x, P_E.z
    addB(ex + 300, ez - 300, 44, 44, 40, 7, "tvtower", 201)     -- 塔身（40 层高 ≈ 130 米；画的时候是圆柱 + 塔楼 + 天线）
    addRect(ex - 470, ex - 160, ez - 470, ez - 280, 7, 7, "block", 202)   -- 广播大楼
    addRect(ex + 160, ex + 470, ez + 280, ez + 470, 4, 5, "block", 203)   -- 演播楼（玻璃）
    addRect(ex - 470, ex - 300, ez + 180, ez + 470, 3, 1, "low", 204)
    addRect(ex + 140, ex + 260, ez - 470, ez - 360, 2, 1, "low", 205)
  end
  -- 火车站（据点 D）：站房在铁轨东边，长长一座拱顶大厅
  addRect(2410, 2534, -300, 300, 5, 4, "station", 301)
  -- 公园（据点 B）：西北角一座玻璃温室（博物馆），别的都是树
  addRect(-3036, -2860, -480, -370, 3, 5, "low", 401)
  addRect(-2240, -2084, 380, 480, 2, 2, "low", 402)
end

-- 铁路沿线（城里那一列，除了车站）：几座小仓库；股道上停着一列列货车厢（挡车、挡子弹的掩护；不算房子、炸不塌）
do
  local R = rng(55501)
  for j = 0, 11 do
    if j ~= 5 and j ~= 6 then
      local _, _, z0, z1 = interior(10, j)
      -- 股道上的货车厢：每格两三节一串，停在随机的股道上
      for _ = 1, 2 do
        local tx = RAIL.x + RAIL.tracks[1 + floor(R() * 4)]
        local n = 2 + floor(R() * 3)
        local zz = z0 + 20 + R() * max(0, (z1 - z0) - n * 46 - 40)
        for q = 0, n - 1 do addB(tx, zz + q * 46 + 21, 11, 42, 1, 6, "wagon", floor(R() * 1e6), { h = 14 }) end
      end
      if R() < 0.5 then addRect(2460, 2530, z0 + 40, z0 + 160, 2, 6, "shed", floor(R() * 1e6)) end
    end
  end
  -- 车站两头的股道上也停几节
  for _, q in ipairs({ { RAIL.x - 72, -460 }, { RAIL.x + 40, 330 }, { RAIL.x - 40, 380 } }) do
    addB(q[1], q[2], 11, 42, 1, 6, "wagon", 900 + q[2], { h = 14 })
  end
end
for _, b in ipairs(BLD) do if b.k == "wagon" then b.h = 14 end end

-- 郊区：一圈独栋小楼（坡屋顶、院子），每个郊区街坊两排三座，空着一些当院子、菜地
local BM = nil
pcall(function()
  local RS = game:GetService("ReplicatedStorage")
  local m = RS:FindFirstChild("BuildingMeta")
  if m then BM = require(m) end
end)
local HOUSES = { "jph1", "jph2", "jph3", "house" }
local function houseDims(k)
  local m = BM and BM[k]
  if m then return m.w, m.d, m.h end
  return 26, 23, 20
end
do
  local R = rng(66607)
  local function suburbBlock(x0, x1, z0, z1)
    -- 扣掉半条街和人行道
    x0, x1, z0, z1 = x0 + 25, x1 - 25, z0 + 25, z1 - 25
    if x1 - x0 < 80 or z1 - z0 < 80 then return end
    local alongX = (x1 - x0) >= (z1 - z0)
    local n = 3
    for row = 0, 1 do
      for q = 0, n - 1 do
        if R() < 0.72 then
          local k = HOUSES[1 + floor(R() * #HOUSES)]
          local w, d, h = houseDims(k)
          local cx, cz
          if alongX then
            cx = x0 + (q + 0.5) * (x1 - x0) / n + (R() - 0.5) * 30
            cz = (row == 0) and (z0 + d / 2 + 14 + R() * 10) or (z1 - d / 2 - 14 - R() * 10)
          else
            cz = z0 + (q + 0.5) * (z1 - z0) / n + (R() - 0.5) * 30
            cx = (row == 0) and (x0 + d / 2 + 14 + R() * 10) or (x1 - d / 2 - 14 - R() * 10)
          end
          -- 朝着外面那条街（只转 0° / 90° / 180° / 270°，外接矩形照转过的算）
          local rot = alongX and ((row == 0) and math.pi or 0) or ((row == 0) and (math.pi / 2) or (-math.pi / 2))
          local fw, fd = w, d
          if not alongX then fw, fd = d, w end
          addB(cx, cz, fw, fd, 2, pick({ 2, 7, 3, 8 }, R()), "house", floor(R() * 1e6), { model = k, rot = rot, h = h })
        end
      end
    end
  end
  for _, s in ipairs({ -1, 1 }) do
    -- 北 / 南两排郊区（x 方向 14 个街坊）
    for i = -1, 12 do
      local xa = (i == -1) and -SUB or lineAt(i)
      local xb = (i == 12) and SUB or lineAt(i + 1)
      if not (xa >= 2047 and xb <= 2561) then   -- 铁路过的那一列不盖
        local za, zb = (s < 0) and -SUB or C0, (s < 0) and -C0 or SUB
        suburbBlock(xa, xb, za, zb)
      end
    end
    -- 东 / 西两列（z 方向 12 个街坊）
    for j = 0, 11 do
      local za, zb = lineAt(j), lineAt(j + 1)
      local xa, xb = (s < 0) and -SUB or C0, (s < 0) and -C0 or SUB
      suburbBlock(xa, xb, za, zb)
    end
  end
  -- 农田里的农舍：一座住房、一座谷仓
  local FARMS = { { -3000, 4700 }, { 3300, 4000 }, { -1900, 5500 }, { 1700, 4500 }, { 3300, -4000 }, { -2900, -4800 }, { 1900, -5500 }, { -1700, -4500 } }
  for fi, f in ipairs(FARMS) do
    local k = HOUSES[1 + (fi % #HOUSES)]
    local w, d, h = houseDims(k)
    addB(f[1], f[2], w, d, 2, 2, "house", 7000 + fi, { model = k, rot = 0, h = h })
    addB(f[1] + 70, f[2] + 10, 44, 64, 2, 6, "barn", 7100 + fi, { h = 26 })
  end
end

---------------------------------------------------------------- 写实楼
-- 用户 11-26「地图建模要精细 3a」：城里的楼换成 Sketchfab 上 CC-BY 的写实楼房（CityMeta / models/bld/city.glb，tools/models/sfbld.py 转的）——
--   沿街的楼（block）、板楼（slab）、塔楼（tower）、铺面（low）、废墟（ruin）这几种：在那块地的长边上一座挨一座排，
--   每座按地块的进深整体缩放（0.85～1.15 倍；塔楼、废墟 0.72～1.2），正面朝最近的那条街、贴着街那一侧（街面整齐，后面留院子）；
--   排到头剩下的一截照旧零件拼一座；塔楼地块小，原大放得下（不压别的楼、不压路）就按原大。
--   换成模型的楼按模型转过、缩放过的外接矩形登记（k = "model"：碰撞、寻路、视线、炸塌都照它）；没导入 city.glb 时 CityBuild 照同样的长宽高用零件拼，
--   所以服务器、客户端、导没导入，地图上哪里能走、哪里挡视线都一样
local CM = nil
pcall(function()
  local RS = game:GetService("ReplicatedStorage")
  local m = RS:FindFirstChild("CityMeta")
  if m then CM = require(m) end
end)
Map.CITY_META = CM
if CM then
  local POOL = {
    old = { "stalin", "office1", "shop1", "brick3", "stalin", "office1" },   -- 老城：老式住宅楼、砖面写字楼、街角铺面、砖楼
    mid = { "stalin", "panel5", "brick3", "office2", "shop1", "office1" },
    out = { "panel9", "panel5", "stalin", "brick3", "panel9" },               -- 外圈：板楼为主
    slab = { "panel9", "panel5", "panel9" },
    tower = { "tower1", "office2", "tower1" },
    low = { "shop1", "khrush", "shop1", "brick3" },
    ruin = { "ruin1" },
  }
  local KINDS = { block = true, slab = true, tower = true, low = true, ruin = true }
  local function poolOf(b)
    if b.k == "slab" then return POOL.slab, 0.85, 1.15, 10 end
    if b.k == "tower" then return POOL.tower, 0.72, 1.2, 0 end
    if b.k == "low" then return POOL.low, 0.85, 1.15, 8 end
    if b.k == "ruin" then return POOL.ruin, 0.72, 1.2, 0 end
    local r = max(abs(b.x), abs(b.z))
    if r < 1100 then return POOL.old, 0.85, 1.15, 0 end   -- 老城沿街一座挨一座（连着的街面）
    if r < 2100 then return POOL.mid, 0.85, 1.15, 3 end
    return POOL.out, 0.85, 1.15, 8
  end
  local OUT = {}   -- 新的楼表（换完以后重新编号）
  local function put(b) OUT[#OUT + 1] = b end
  -- 一块矩形 [x, z, w, d] 有没有压到别的楼（除了 skip）、压到路
  local function free(x, z, w, d, skip)
    for _, o in ipairs(BLD) do
      if o ~= skip and abs(o.x - x) < (o.w + w) / 2 + 4 and abs(o.z - z) < (o.d + d) / 2 + 4 then return false end
    end
    for _, c in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 }, { 0, -0.5 }, { 0, 0.5 }, { -0.5, 0 }, { 0.5, 0 } }) do
      if onRoad(x + c[1] * w, z + c[2] * d, 4) then return false end
    end
    return true
  end
  local function model(b, key, s, cx, cz, alongX, front)
    local m = CM[key]
    local lm, dm = m.w * s, m.d * s
    -- 正面（模型的 −Z）朝 front：沿 x 排的朝 −z（0）/ +z（π）；沿 z 排的朝 −x（π/2）/ +x（−π/2）
    local rot = alongX and ((front < 0) and 0 or math.pi) or ((front < 0) and (math.pi / 2) or (-math.pi / 2))
    local h = m.h * s
    put({ x = cx, z = cz, w = alongX and lm or dm, d = alongX and dm or lm, h = h, fl = max(1, floor((h - 2) / FH)), st = b.st, k = "model",
      model = key, rot = rot, scale = s, sd = b.sd + #OUT * 13 })
  end
  local function fill(b)
    local pool, smin, smax, gap = poolOf(b)
    local R = rng(b.sd + 911)
    local alongX = b.w >= b.d
    local L, D = alongX and b.w or b.d, alongX and b.d or b.w
    -- 正面朝长边两侧里离路近的那边
    local o = D / 2 + 30
    local d1 = alongX and Map.roadDist(b.x, b.z - o) or Map.roadDist(b.x - o, b.z)
    local d2 = alongX and Map.roadDist(b.x, b.z + o) or Map.roadDist(b.x + o, b.z)
    local front = (d1 <= d2) and -1 or 1
    -- 塔楼：原大放得下就原大
    if b.k == "tower" then
      for _ = 1, 4 do
        local key = pool[1 + floor(R() * #pool)]
        local m = CM[key]
        if m and free(b.x, b.z, m.w, m.d, b) then
          model(b, key, 1, b.x, b.z, true, front)
          return true
        end
      end
    end
    local pos = -L / 2
    local n0 = #OUT
    while true do
      local rem = L / 2 - pos
      local pick1 = nil
      for _ = 1, #pool * 2 do
        local key = pool[1 + floor(R() * #pool)]
        local m = CM[key]
        if m then
          local s = math.min(smax, D / m.d)
          if m.w * s > rem then s = rem / m.w end   -- 长度放不下：缩到正好
          if s >= smin and m.d * s <= D + 0.01 then pick1 = { key = key, s = s, m = m } break end
        end
      end
      if not pick1 then break end
      local lm, dm = pick1.m.w * pick1.s, pick1.m.d * pick1.s
      local along = pos + lm / 2
      local across = front * (D / 2 - dm / 2)
      local cx, cz
      if alongX then cx, cz = b.x + along, b.z + across else cx, cz = b.x + across, b.z + along end
      model(b, pick1.key, pick1.s, cx, cz, alongX, front)
      pos = pos + lm + gap
    end
    if #OUT == n0 then return false end
    -- 排到头剩下的一截：够宽就照旧零件拼一座（进深跟街面那排差不多）
    local rem = L / 2 - pos
    if rem >= 30 and (b.k == "block" or b.k == "low") then
      local dd = math.min(D, 60)
      local along = pos + rem / 2
      local across = front * (D / 2 - dd / 2)
      local cx, cz
      if alongX then cx, cz = b.x + along, b.z + across else cx, cz = b.x + across, b.z + along end
      put({ x = cx, z = cz, w = alongX and rem or dd, d = alongX and dd or rem, h = b.h, fl = b.fl, st = b.st, k = b.k, sd = b.sd + 17 })
    end
    return true
  end
  for _, b in ipairs(BLD) do
    if not (KINDS[b.k] and fill(b)) then put(b) end
  end
  table.clear(BLD)
  for i, b in ipairs(OUT) do
    b.id = i
    BLD[i] = b
  end
end

-- 楼按 128 格的格子登记
local BCELL = 128
local bgrid = {}
local function bkey(gx, gz) return (gx + 512) * 1024 + (gz + 512) end
for _, b in ipairs(BLD) do
  local pad = 24
  for gx = floor((b.x - b.w / 2 - pad) / BCELL), floor((b.x + b.w / 2 + pad) / BCELL) do
    for gz = floor((b.z - b.d / 2 - pad) / BCELL), floor((b.z + b.d / 2 + pad) / BCELL) do
      local key = bkey(gx, gz)
      local l = bgrid[key]
      if not l then l = {} bgrid[key] = l end
      table.insert(l, b)
    end
  end
end
-- 塌了的楼（Battle.lua 炸塌时记；新一局清空）：视线、站位不再算它（寻路网格开服时算好，不跟着变）
Map.BLD_DOWN = {}
-- (x, z) 在哪座楼里（外接矩形四边外扩 pad）；没有返回 nil
local function bldAt(x, z, pad)
  local l = bgrid[bkey(floor(x / BCELL), floor(z / BCELL))]
  if not l then return nil end
  pad = pad or 0
  for _, b in ipairs(l) do
    if abs(x - b.x) <= b.w / 2 + pad and abs(z - b.z) <= b.d / 2 + pad then return b end
  end
  return nil
end
Map.bldAt = bldAt
-- 机器人寻路（Nav.lua）：楼、车厢外扩 12 格（车身半宽 + 余量）的地方不能走
function Map.navBlocked(x, z) return bldAt(x, z, 12) ~= nil end
-- 两点之间平着走过去会不会撞楼（寻路往前看几格、找停车位用）
function Map.segBlocked(ax, az, bx, bz, pad)
  local dx, dz = bx - ax, bz - az
  local L = sqrt(dx * dx + dz * dz)
  local n = max(1, floor(L / 10))
  for q = 0, n do
    local t = q / n
    if bldAt(ax + dx * t, az + dz * t, pad or 10) then return true end
  end
  return false
end

---------------------------------------------------------------- 地形高度

-- 平地（城、郊区、农田、两边基地）以外是丘陵：东西两侧一道岭，远处起伏；离平地越近越平（接得上）
local function hills(x, z)
  local qx, qz = max(0, abs(x) - FX), max(0, abs(z) - FZ)
  if qx <= 0 and qz <= 0 then return 0 end
  local k = smooth(0, 1800, sqrt(qx * qx + qz * qz))
  local n = noise(x / 2900, z / 2900, 4.2) * 0.6 + noise(x / 1150, z / 1150, 8.1) * 0.28 + noise(x / 430, z / 430, 2.7) * 0.1
  local ridge = exp(-((abs(x) - 8200) / 1700) ^ 2) * (110 + 40 * noise(z / 2400, 3.3, 1.7))
  return (max(0, n + 0.3) * 70 + ridge) * k
end
function Map.height(x, z) return PLAIN + hills(x, z), 1e9 end
function Map.ground(x, z) return PLAIN + hills(x, z) end
function Map.isLand() return true end
function Map.slope(x, z)
  if abs(x) < FX and abs(z) < FZ then return 0 end
  local e = 4
  local a, b = Map.height(x + e, z), Map.height(x - e, z)
  local c, d = Map.height(x, z + e), Map.height(x, z - e)
  return sqrt(((a - b) / (2 * e)) ^ 2 + ((c - d) / (2 * e)) ^ 2)
end
-- 在不在两边基地的场子里（0～1）：摆树、灌木时避开
local function inBase(x, z, m)
  m = m or 0
  for _, B in pairs(Map.BASES) do
    local r = B.rect
    if x > r.x0 - m and x < r.x1 + m and z > r.z0 - m and z < r.z1 + m then return true end
  end
  return false
end
Map.inBase = inBase
function Map.flatW(x, z) return inBase(x, z, 0) and 1 or 0 end
Map.FLAT = {}

---------------------------------------------------------------- 材质

-- 平地这一块（256 格见方，按块中心）是什么地面：城里人行道（灰）、公园草地、铁路碎石、厂区水泥；郊区草地；农田一块块（草、翻过的土、深一点的草）；基地压实的土
local function flatMat(cx, cz)
  if inBase(cx, cz, 200) then return MAT.Ground end
  local ax, az = abs(cx), abs(cz)
  if ax < C0 and az < C0 then
    if cx > -C0 and cx < -2048 and az < 512 then return MAT.Grass end     -- 公园
    if cx > 2048 and cx < 2560 then return MAT.Ground end                 -- 铁路那一列
    if abs(cx - P_A.x) < 512 and abs(cz - P_A.z) < 512 then return MAT.Concrete end   -- 钢厂
    return MAT.Pavement
  end
  if ax < SUB and az < SUB then return MAT.Grass end   -- 郊区：院子里的草
  -- 农田：512 × 256 一块，按块号定种（翻过的地、草、深色的草）
  local fx, fz = floor(cx / 512), floor(cz / 256)
  local h = (fx * 73856093 + fz * 19349663) % 100   -- Luau 没有 ~（异或）：加起来取余一样散
  if h < 28 then return MAT.Ground end
  if h < 46 then return MAT.LeafyGrass end
  return MAT.Grass
end
Map.flatMat = flatMat

function Map.material(x, z, y, slope)
  if abs(x) < FX and abs(z) < FZ then
    local on, k = onRoad(x, z, 0)
    if on then return (k == "lane" or k == "lane2") and MAT.Ground or MAT.Asphalt end   -- 路（零件铺的，地形底下是人行道 / 草）
    if abs(x) < PLAZA and abs(z) < PLAZA then return MAT.Cobblestone end   -- 中央广场
    if bldAt(x, z, 0) then return MAT.Concrete end
    if railNear(x, z) < 90 then return MAT.Slate end
    return flatMat(x, z)
  end
  slope = slope or 0
  if slope > 0.9 then return MAT.Rock end
  if slope > 0.55 then return MAT.Ground end
  if (y or 0) > 170 and noise(x / 160, z / 160, 3.3) > 0.15 then return MAT.Rock end
  return (noise(x / 700, z / 700, 5.5) > 0.3) and MAT.LeafyGrass or MAT.Grass
end
function Map.colCache() end   -- 沙海的列缓存：这张图的高度、材质都便宜，不用缓存
function Map.underMat(top)
  if top == MAT.Rock or top == MAT.Slate then return MAT.Rock end
  return MAT.Ground
end
function Map.farSeaOk() return false end

---------------------------------------------------------------- 写地形（World.lua 用）

local CH = 256
-- 一块 256 × 256 格：整块在平地里就是 "flat"（一次 FillBlock：高度 PLAIN、材质按这一块），别的（丘陵）"relief" 逐列写
function Map.chunkKind(x0, z0)
  local x1, z1 = x0 + CH, z0 + CH
  if x0 >= -FX and x1 <= FX and z0 >= -FZ and z1 <= FZ then
    return "flat", PLAIN, flatMat(x0 + CH / 2, z0 + CH / 2)
  end
  -- 平地外面一圈：丘陵从平地边上慢慢抬起来——9 × 9 个点都还是平的（还没抬起来）就照平地铺
  local step = CH / 8
  for i = 0, 8 do
    for k = 0, 8 do
      if hills(x0 + i * step, z0 + k * step) > 0.01 then return "relief" end
    end
  end
  return "flat", PLAIN, MAT.Grass
end
-- 写地形的顺序：开服先写两边基地一带（出生只在自己基地），再据点一带、城区，别的在后台
Map.CORE = { x = 0, z = 0, r = 4000 }
Map.CORES = {}
for _, B in pairs(Map.BASES) do table.insert(Map.CORES, { x = (B.rect.x0 + B.rect.x1) / 2, z = (B.rect.z0 + B.rect.z1) / 2, r = 2700 }) end
Map.HOTS = {}
for _, c in ipairs(Map.CORES) do table.insert(Map.HOTS, c) end
table.insert(Map.HOTS, { x = 0, z = 0, r = 4300 })   -- 整座城（平地，铺得快）

-- 画中画瞄准镜的远景网格、小地图、寻路
function Map.landBoxes() return { { -FX, -FZ, FX, FZ } } end
Map.UIBOX = { x0 = -5200, z0 = -9200, x1 = 5200, z1 = 9200 }
-- 寻路网格（Nav.lua）：64 格一格，格子中心正好落在每条街的中线上（街都在 512 的倍数上）——顺着街走的边整条在路上
Map.NAVBOX = { x0 = -4640, z0 = -8352, x1 = 4640, z1 = 8352 }
Map.NAVCELL = 64

-- 两点之间的视线：地形（城外丘陵）、楼（塌了的不算）挡不挡（AI 车看人、工事看人）
function Map.lineClear(a, b, step)
  step = step or 12
  local dv = b - a
  local L = dv.Magnitude
  local n = max(1, floor(L / step))
  for i = 1, n - 1 do
    local p = a + dv * (i / n)
    if Map.height(p.X, p.Z) > p.Y then return false end
    local bd = bldAt(p.X, p.Z, 0)
    if bd and not Map.BLD_DOWN[bd.id] and p.Y < PLAIN + bd.h then return false end
  end
  return true
end

---------------------------------------------------------------- 树（Map.TREES）：撞得倒、炸得倒、打得断（服务器 Trees.lua 记谁倒了；客户端 Scenery.lua 按距离画）
--   { id, x, y, z, k 模型键（SceneryMeta）, s 缩放, yaw, r 树干半径（格）, h 高 }；按 64 格的格子登记（Map.treesNear / Map.treesInCell）

local TREES = {}
Map.TREES = TREES
local TCELL = 64
Map.TREE_CELL = TCELL
local tgrid = {}
local function tkey(gx, gz) return (gx + 1024) * 4096 + (gz + 1024) end
local BROAD = { "oak", "maple", "birch1", "birch2", "maple", "oak" }
local CONIFER = { "fir1", "fir2", "fir3", "fir4", "pine" }
local TH = { oak = 47.7, maple = 49.6, birch1 = 48.1, birch2 = 55.8, fir1 = 49.5, fir2 = 49.2, fir3 = 43.1, fir4 = 37.0, pine = 49.4 }
local function treeOk(x, z, clear)
  if abs(x) > FX - 20 or abs(z) > FZ - 20 then return false end
  if inBase(x, z, 120) then return false end
  if onRoad(x, z, 4) then return false end
  if bldAt(x, z, clear or 8) then return false end
  if railNear(x, z) < 96 then return false end
  if abs(x) < PLAZA + 4 and abs(z) < PLAZA + 4 then return false end
  for _, p in ipairs(Map.POINTS) do
    local dx, dz = x - p.x, z - p.z
    if dx * dx + dz * dz < (Map.POINT_R + 14) ^ 2 then return false end
  end
  return true
end
local function addTree(x, z, k, s, yaw)
  local id = #TREES + 1
  local h = (TH[k] or 45) * s
  local t = { id = id, x = x, y = PLAIN - 0.3, z = z, k = k, s = s, yaw = yaw, h = h, r = 1.1 * s + 0.4 }
  TREES[id] = t
  local key = tkey(floor(x / TCELL), floor(z / TCELL))
  local l = tgrid[key]
  if not l then l = {} tgrid[key] = l end
  table.insert(l, t)
  return t
end
local function nearTree(x, z, r)
  local g0, g1 = floor((x - r) / TCELL), floor((x + r) / TCELL)
  local h0, h1 = floor((z - r) / TCELL), floor((z + r) / TCELL)
  for gx = g0, g1 do
    for gz = h0, h1 do
      local l = tgrid[tkey(gx, gz)]
      if l then
        for _, t in ipairs(l) do
          if (t.x - x) ^ 2 + (t.z - z) ^ 2 < r * r then return true end
        end
      end
    end
  end
  return false
end
do
  local R = rng(88801)
  -- 行道树：中央大道、和平大街两边每 40 格一棵，±1536 的大街两边每 56 格；路口、广场、据点附近空着
  local function avenue(alongX, v, w, gap, s0)
    local off = w / 2 + 5
    for _, sd in ipairs({ -1, 1 }) do
      local u = -C0 + 30
      while u < C0 - 30 do
        local x, z
        if alongX then x, z = u, v + sd * off else x, z = v + sd * off, u end
        -- 离横着的街口远一点
        local cross = alongX and x or z
        local li = floor((cross + C0) / GRID + 0.5)
        local lc = lineAt(clamp(li, 0, 12))
        if abs(cross - lc) > lineW(lc) / 2 + 22 and treeOk(x, z, 6) then
          addTree(x, z, BROAD[1 + floor(R() * #BROAD)], s0 + R() * 0.12, R() * 6.283)
        end
        u += gap
      end
    end
  end
  avenue(false, 0, 64, 40, 0.5)
  avenue(true, 0, 64, 40, 0.5)
  for _, v in ipairs({ -1536, 1536 }) do
    avenue(false, v, 44, 56, 0.48)
    avenue(true, v, 44, 56, 0.48)
  end
  -- 公园（据点 B 一带）：一大片阔叶林，中间据点那一圈和几条小路空着
  do
    local x0, x1, z0, z1 = -C0 + 36, -2048 - 30, -512 + 30, 512 - 30
    for gx = x0, x1, 30 do
      for gz = z0, z1, 30 do
        local x, z = gx + (R() - 0.5) * 18, gz + (R() - 0.5) * 18
        local dB = sqrt((x - P_B.x) ^ 2 + (z - P_B.z) ^ 2)
        local path = abs(dB - 300) < 14 or abs(x - P_B.x) < 12   -- 绕着据点一圈的小路、南北一条
        if R() < 0.62 and not path and dB > Map.POINT_R + 40 and treeOk(x, z, 10) then
          addTree(x, z, BROAD[1 + floor(R() * #BROAD)], 0.62 + R() * 0.3, R() * 6.283)
        end
      end
    end
  end
  -- 广场四周的树池、街心花园、球场边、停车场边
  for i = 0, 11 do
    for j = 0, 11 do
      local t = blockType(i, j)
      if t == "garden" or t == "sports" or t == "parking" or t == "works" then
        local x0, x1, z0, z1 = interior(i, j)
        local step = (t == "garden") and 30 or 46
        for gx = x0 + 10, x1 - 10, step do
          for gz = z0 + 10, z1 - 10, step do
            local edge = (gx < x0 + 40 or gx > x1 - 40 or gz < z0 + 40 or gz > z1 - 40)
            if (t == "garden" and R() < 0.55) or (t ~= "garden" and edge and R() < 0.5) then
              local x, z = gx + (R() - 0.5) * 12, gz + (R() - 0.5) * 12
              if treeOk(x, z, 8) then addTree(x, z, BROAD[1 + floor(R() * #BROAD)], 0.55 + R() * 0.25, R() * 6.283) end
            end
          end
        end
      elseif t == "city" and R() < 0.5 then   -- 有的街坊院子里一两棵
        local x0, x1, z0, z1 = interior(i, j)
        for _ = 1, 3 do
          local x, z = lerp(x0, x1, 0.3 + R() * 0.4), lerp(z0, z1, 0.3 + R() * 0.4)
          if treeOk(x, z, 12) then addTree(x, z, BROAD[1 + floor(R() * #BROAD)], 0.5 + R() * 0.2, R() * 6.283) end
        end
      end
    end
  end
  -- 郊区：每座小楼院子里一两棵
  for _, b in ipairs(BLD) do
    if b.k == "house" then
      for _ = 1, 1 + floor(R() * 2) do
        local a = R() * 6.283
        local rr = max(b.w, b.d) * 0.5 + 14 + R() * 16
        local x, z = b.x + cos(a) * rr, b.z + sin(a) * rr
        if treeOk(x, z, 6) and not nearTree(x, z, 14) then addTree(x, z, BROAD[1 + floor(R() * #BROAD)], 0.55 + R() * 0.3, R() * 6.283) end
      end
    end
  end
  -- 农田：田埂上一排排树（东西向，每 256 格一道，断断续续），两侧和城边几片林子（针叶多）
  for _, s in ipairs({ -1, 1 }) do
    for zz = SUB + 384, 5800, 512 do
      local z = s * zz
      local x = -FX + 60
      while x < FX - 60 do
        local run = noise(x / 400, z / 400, 9.1) > -0.05
        if run and R() < 0.8 then
          local xx, zz2 = x + (R() - 0.5) * 8, z + (R() - 0.5) * 8
          if treeOk(xx, zz2, 8) and not nearTree(xx, zz2, 14) then addTree(xx, zz2, BROAD[1 + floor(R() * #BROAD)], 0.6 + R() * 0.3, R() * 6.283) end
        end
        x += 30 + R() * 12
      end
    end
  end
  local woods = {
    { -3950, 4800, 420 }, { 3900, 5300, 380 }, { -3900, -4900, 420 }, { 3950, -5200, 380 },   -- 农田四角
    { -4100, 1300, 320 }, { 4100, -1300, 320 },                                                -- 城两侧（郊区外）
    { -1300, 4300, 220 }, { 1300, -4300, 220 },
  }
  for wi, w in ipairs(woods) do
    local cx, cz, r = w[1], w[2], w[3]
    for gx = cx - r, cx + r, 28 do
      for gz = cz - r, cz + r, 28 do
        local x, z = gx + (R() - 0.5) * 18, gz + (R() - 0.5) * 18
        local q = ((x - cx) ^ 2 + (z - cz) ^ 2) / (r * r) + 0.35 * noise(x / 160, z / 160, wi * 1.7)
        if q < 1 and R() < 0.58 and treeOk(x, z, 8) then
          local k = (R() < 0.6) and CONIFER[1 + floor(R() * #CONIFER)] or BROAD[1 + floor(R() * #BROAD)]
          addTree(x, z, k, 0.7 + R() * 0.35, R() * 6.283)
        end
      end
    end
  end
end
Map.TREE_N = #TREES
-- (x, z) 方圆 r 以内的树（倒没倒由调用的人自己看）
function Map.treesNear(x, z, r, out)
  out = out or {}
  table.clear(out)
  local g0, g1 = floor((x - r) / TCELL), floor((x + r) / TCELL)
  local h0, h1 = floor((z - r) / TCELL), floor((z + r) / TCELL)
  for gx = g0, g1 do
    for gz = h0, h1 do
      local l = tgrid[tkey(gx, gz)]
      if l then
        for _, t in ipairs(l) do
          if (t.x - x) ^ 2 + (t.z - z) ^ 2 < (r + t.r) ^ 2 then table.insert(out, t) end
        end
      end
    end
  end
  return out
end
-- 这一格（Flora 的 64 格格子，同 TREE_CELL）里的树：Scenery.lua 按格子摆
function Map.treesInCell(cx, cz) return tgrid[tkey(cx, cz)] or {} end

return Map
