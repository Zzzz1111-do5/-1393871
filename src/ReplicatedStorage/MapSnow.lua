--!native
-- 全面大战场地图「雪山」（ReplicatedStorage.MapSnow，地图 id "snow"）：一条高山河谷，纯数学，服务器、客户端算出来一样
--   用户 11-26 晚：「我要求你做一个雪山地图 一定要做到极高质量 一定要比我截图发你这个好 你直接下载这个当作地图就行 我要做一个惊艳的地图」
--   （截图是 Sketchfab 上 99.Miles 的 Low Poly Winter Tree Pack，CC-BY：树用它，tools/snow/winter.py 拆成 models/scenery/winter.glb 里的 wt1～wt15、ws1～ws15）
--   · 南北一条河谷（坦克的战场约 2 公里宽、5 公里长），两头各一座带跑道的主基地（同钢城：FOB.lua 建），出车开到据点一两分钟
--   · 东西两侧是雪峰：山脊用山脊形分形噪声（ridged multifractal）+ 坐标扭曲，山尖、山脊、冲沟像真的雪山；最高的离谷底 2200 格（约 780 米）；
--     陡坡露出岩石（Rock / Slate / Basalt），缓坡积雪，高处冰川（Glacier）；山脊外面落到一块高原（客户端那圈远处平地托着）
--   · 谷里一条冰封的河斜着穿过战场（浅河槽、冰面，坦克开得过去，但站在冰上就是活靶子），东边一个冰湖；三座桥
--   · 据点：A 南边的锯木厂、B 西边山坡上的雷达站（高处）、C 河边的山村（教堂、石桥）、D 冰湖边的水电站、E 北边的山口检查站
--   · 谷底大部分是平的（开服时 FillBlock 一块块铺雪，几秒钟），河槽、湖岸、小山包、谷边的坡逐列写体素；两侧大山是远景，开服后后台慢慢铺
--   · 树（Map.TREES）：雪松林长在谷边和山坡下半截（林线以上光秃秃），谷里零星几棵，山村里、路边几排；车撞得倒、炮弹炸得倒（同钢城）
--   同钢城一样的接口（height / ground / material / POINTS / BASES / FOB / chunkKind / ……），Map.use("snow") 换进 Map 表
local Map = {}
local exp, abs, sin, cos, sqrt, max, min, floor = math.exp, math.abs, math.sin, math.cos, math.sqrt, math.max, math.min, math.floor
local noise = math.noise

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
Map.clamp, Map.smooth, Map.lerp = clamp, smooth, lerp

Map.NAME = "snow"
Map.SNOW = true
Map.LANDONLY = true    -- 不打登陆战（没有港口、登陆艇、舰艇）；海只是岛外面的景
Map.SEA = true         -- 用户 11-26 夜：「你把这个设计成一个海上的冰岛吧 然后外面包裹的都是一望无际的海」——岛外一圈地形海水，再往外客户端的海面铺到天边
Map.GRASS = false      -- 雪地：不写 Grass（不长草叶）
Map.NOMIDAF = true     -- 两边基地各有跑道
local K, HK = 3, 2
Map.K, Map.HK = K, HK
Map.R = 12288          -- 地形铺到 ±R
Map.PLAY = 20480       -- 飞机的作战区
Map.SEA_R = 24576      -- 地形海水铺到 ±SEA_R（同海岛图：远海那圈平面和地形水面接得上），再往外是客户端跟着镜头的海面
Map.SEA_LIM = 0
Map.SEA_DEPTH = 60     -- World.writeChunk 写海底的深度上限（近岸那一圈海底按块写；离岸远的整块按平的海铺：SEA_FLOOR）
Map.SEA_FLOOR = 26     -- 外海：玄武岩海底在水面下 26 格（World.lua 铺平的海）
Map.WATER_COLOR = Color3.fromRGB(34, 78, 96)   -- 冷海：深灰蓝（World.lua 设 Terrain.WaterColor）
Map.SEA_FAR_COLOR = Color3.fromRGB(24, 58, 72)  -- 客户端远处那圈海面（不透明的平面，比透过水看海底的颜色暗一点）
Map.SHELF = 0
Map.MAXH = 4500        -- 最高的地形（Map.rayGround 只在这以下一步步找落点）：两座角峰四千三
Map.RES = 4
-- 后台还没写到的起伏块先垫的那层薄底（World.lua terrainDesert 的 underlay）：按这一块最低的地面往下 3 格、用雪铺（原来一律在平地往下 8 格铺沙——
--   这张图的「沙」是黑沙滩的深灰，没写到的一块块成了深灰的大坑，用户 11-28 晚截图「雪山图这一块一直加载不」）
Map.UNDERLAY_FOLLOW = true
Map.CEIL = 7200        -- 飞机最高飞到多高（Fly.lua、Air.lua：钢城、沙海 2600；这里角峰四千多格，上面还要留两三千格飞）
Map.HALF = 12000
local PLAIN = 12       -- 谷底平地（4 的倍数：FillBlock 铺出来和逐列写的一样高）
Map.PLAIN = PLAIN

local MAT = Enum.Material
local RGB = Color3.fromRGB
-- 地形颜色（World.lua 写地形前 SetMaterialColor）：新雪偏一点蓝、冰川青、花岗岩深灰、路上压实的脏雪
Map.COLORS = {
  Snow = RGB(236, 240, 247), Glacier = RGB(176, 208, 228), Ice = RGB(196, 220, 236), Rock = RGB(98, 98, 104), Slate = RGB(78, 80, 88),
  Basalt = RGB(18, 52, 64), Ground = RGB(122, 114, 106), LeafyGrass = RGB(104, 108, 88), Mud = RGB(92, 84, 76), Sand = RGB(66, 66, 70),
  Pavement = RGB(150, 150, 152), Concrete = RGB(162, 162, 160), Asphalt = RGB(56, 58, 62), Cobblestone = RGB(120, 118, 116), Limestone = RGB(186, 184, 178),
  Sandstone = RGB(140, 124, 108), Grass = RGB(96, 112, 78),
}
-- 岛外是海：客户端那圈远处的平面画成海（Map.FAR 不设），玄武岩染成深海底的颜色（外海的海底），沙子是冰岛那种黑沙滩

local function rng(seed)
  local s = seed % 2147483647
  if s <= 0 then s += 2147483646 end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

---------------------------------------------------------------- 两边的主基地（同钢城：FOB.lua 建营区 + 车场 + 直升机坪 + 跑道）

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
local BZ = 6656
Map.BASES = {
  atk = { x = 0, z = BZ, yaw = 0 },
  def = { x = 0, z = -BZ, yaw = math.pi },
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
Map.AIRFIELD = Map.AFIELD3
local function inBase(x, z, m)
  m = m or 0
  for _, B in pairs(Map.BASES) do
    local r = B.rect
    if x > r.x0 - m and x < r.x1 + m and z > r.z0 - m and z < r.z1 + m then return true end
  end
  return false
end
Map.inBase = inBase

---------------------------------------------------------------- 据点

local P_A = { id = "A", x = -1150, z = 3300, name = "sawmill" }     -- 南边：锯木厂（攻方先打的）
local P_B = { id = "B", x = -2000, z = 900, name = "radar" }        -- 西边台地上的雷达站（高处，看得远）；和 D 关于山村中心对称（统治模式两边一样远）
local P_C = { id = "C", x = 0, z = 0, name = "village" }            -- 河边的山村：教堂、广场
local P_D = { id = "D", x = 2300, z = -900, name = "hydro" }        -- 冰湖坝下的水电站
local P_E = { id = "E", x = 900, z = -3400, name = "pass" }         -- 北边的山口检查站（守方最后一道）
Map.POINTS = { P_A, P_B, P_C, P_D, P_E }
Map.POINT_R = 90
Map.TOWN = { x = 0, z = 0, y = PLAIN }
Map.PORT = Map.TOWN
Map.COMMAND = { x = P_E.x, z = P_E.z, y = PLAIN }
Map.FLEET, Map.BEACHES, Map.LANDINGS, Map.ISLES, Map.CAPES = {}, {}, {}, {}, {}
Map.BARGE = nil
function Map.landingOf() return nil end
function Map.landOf() return "main" end
function Map.beachAt() return nil end
function Map.coastS() return nil end
function Map.coastN() return nil end
function Map.inHarbor() return false end

---------------------------------------------------------------- 河、湖、谷

-- 冰河：从西北的山里出来，斜着穿过谷底（山村 C 的南边过），往东南的山里去——
--   用户 11-27：「河谷可能成狙击走廊」：控制点连成一条平滑的曲线，再左右摆（一个弯约 1.9 公里、摆幅 230 格）；
--   河两边是低一截的河滩，河滩外一道几米高的陡坎（凹岸那边宽、凸岸那边窄，跟着弯换边），顺着河看出去不远就被弯和坎挡住
local RIVER = {
  { -12288, -6800 }, { -7600, -5300 }, { -4300, -3600 }, { -2400, -1700 }, { -900, -420 }, { 250, 520 },
  { 1500, 1900 }, { 3000, 3300 }, { 5200, 4700 }, { 8200, 6100 }, { 12288, 7600 },
}
Map.RIVER = RIVER
local RIVER_W = 70       -- 冰面半宽
local RIVER_BANK = 70    -- 河岸坡（再往外接到河滩）
local RIVER_D = 7        -- 冰面比河滩低多少
local MEANDER_A, MEANDER_L = 430, 2300
-- 摆过的河道：先把控制点连成平滑曲线（Catmull-Rom），每 60 格一个点，再沿法向偏 A·sin(2π s / L + 0.6)
local RPTS = {}
do
  local base = {}
  local n = #RIVER
  for i = 1, n - 1 do
    local p0, p1, p2, p3 = RIVER[max(1, i - 1)], RIVER[i], RIVER[i + 1], RIVER[min(n, i + 2)]
    local L = sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
    local m = max(2, floor(L / 60))
    for q = 0, m - 1 do
      local t = q / m
      local t2, t3 = t * t, t * t * t
      local function cr(a, b2, c, d) return 0.5 * ((2 * b2) + (-a + c) * t + (2 * a - 5 * b2 + 4 * c - d) * t2 + (-a + 3 * b2 - 3 * c + d) * t3) end
      table.insert(base, { cr(p0[1], p1[1], p2[1], p3[1]), cr(p0[2], p1[2], p2[2], p3[2]) })
    end
  end
  table.insert(base, { RIVER[n][1], RIVER[n][2] })
  local acc = 0
  for i = 1, #base do
    if i > 1 then acc += sqrt((base[i][1] - base[i - 1][1]) ^ 2 + (base[i][2] - base[i - 1][2]) ^ 2) end
    local a2, b2 = base[max(1, i - 1)], base[min(#base, i + 1)]
    local tx, tz = b2[1] - a2[1], b2[2] - a2[2]
    local tl = max(sqrt(tx * tx + tz * tz), 1e-6)
    -- 山村（C）那一段不摆（河照原来的线从村南边过，不穿进村里）
    local dc = sqrt(base[i][1] ^ 2 + base[i][2] ^ 2)
    -- 弯有大有小、有长有短（摆幅、弯长沿河慢慢变，不是一条规整的正弦）
    local amp = MEANDER_A * (0.62 + 0.38 * noise(acc / 3100, 4.2, 0.7) * 2)
    local off = amp * sin(acc / MEANDER_L * 2 * math.pi + 0.6 + 1.2 * noise(acc / 2700, 8.8, 0.3)) * smooth(350, 1300, dc)
    RPTS[i] = { base[i][1] - tz / tl * off, base[i][2] + tx / tl * off, acc }
  end
end
Map.RIVER_PTS = RPTS
-- 河道按 256 格的格子登记（离河 1100 格以内的格子都记上这一段）：查离河多远只看附近几段
local RG, RGC = {}, 256
local function rgk(gx, gz) return (gx + 512) * 1024 + gz + 512 end
for i = 1, #RPTS - 1 do
  local a, b2 = RPTS[i], RPTS[i + 1]
  for gx = floor((min(a[1], b2[1]) - 1100) / RGC), floor((max(a[1], b2[1]) + 1100) / RGC) do
    for gz = floor((min(a[2], b2[2]) - 1100) / RGC), floor((max(a[2], b2[2]) + 1100) / RGC) do
      local k = rgk(gx, gz)
      local l = RG[k]
      if not l then l = {} RG[k] = l end
      table.insert(l, i)
    end
  end
end
-- 离河中线多远（1100 格以外按 1e4），第二、三个返回：最近那一点的里程、在河的左边（+1）还是右边（−1）
local function riverNear(x, z)
  local l = RG[rgk(x // RGC, z // RGC)]
  if not l then return 1e4, 0, 1 end
  local best, bs, bside = 1e18, 0, 1
  for _, i in ipairs(l) do
    local a, b2 = RPTS[i], RPTS[i + 1]
    local dx, dz = b2[1] - a[1], b2[2] - a[2]
    local L2 = dx * dx + dz * dz
    local t = clamp(((x - a[1]) * dx + (z - a[2]) * dz) / L2, 0, 1)
    local px, pz = a[1] + dx * t - x, a[2] + dz * t - z
    local d = px * px + pz * pz
    if d < best then
      best, bs = d, a[3] + (b2[3] - a[3]) * t
      bside = (dx * (z - a[2]) - dz * (x - a[1]) > 0) and 1 or -1
    end
  end
  if best >= 1e18 then return 1e4, 0, 1 end
  return sqrt(best), bs, bside
end
local function riverDist(x, z) return (riverNear(x, z)) end
Map.riverDist = riverDist
Map.riverNear = riverNear
-- 冰湖：水电站（D）东边的高台上（水库），西头一道坝挡着，坝下的豁口里就是水电站（D）——
--   湖面比谷底高 40 格（14 米）；湖四周一圈高起来的岸（坝两头插进岸里），坝下的豁口往西慢慢落回谷底
local LAKE = { x = 3000, z = -1250, rx = 700, rz = 560, y = PLAIN + 40 }
LAKE.damX = LAKE.x - LAKE.rx * 0.8       -- 坝的中线（南北向一道直墙）
LAKE.damHalf = LAKE.rz * 0.6 + 60        -- 坝半长：这里湖的弦半长 336，两头各插进岸里 60
LAKE.foot = PLAIN + 10                   -- 坝脚、厂房那块地的高
Map.LAKE = LAKE
local function lakeD(x, z)   -- 湖心是 0，湖岸是 1
  local u, v = (x - LAKE.x) / LAKE.rx, (z - LAKE.z) / LAKE.rz
  return sqrt(u * u + v * v) + 0.06 * noise(x / 180, z / 180, 6.3)
end
Map.lakeD = lakeD
-- 湖面（冰）：椭圆里、坝的东边
local function inLake(x, z) return x > LAKE.damX and lakeD(x, z) <= 1 end
Map.inLake = inLake

-- 谷底一半宽多少（z 往北为负）：两头基地那里宽（跑道 3600 格横着放），中间收窄一点；谷边以外开始往山上抬
local function valleyHalf(z)
  local a = abs(z)
  local w = 3350 + 450 * smooth(3000, 6000, a) - 250 * exp(-((z + 600) / 2600) ^ 2)
  return w + 220 * noise(z / 1900, 1.7, 0.4)
end
Map.valleyHalf = valleyHalf
-- 谷的中线（往东西弯一点；两头基地那一段是直的）
local function valleyX(z) return 900 * sin(z / 5200 + 0.4) * (1 - smooth(4300, 6800, abs(z))) end
Map.valleyX = valleyX
-- 离谷底多「远」：超椭圆（四次方）——谷里 < 1，谷边 = 1，往外越来越大；四个角是圆的，谷边带一点弯
--   第二个返回：这里 1 个单位折合多少格（两侧 ≈ 谷半宽、两头 ≈ 谷半长），(vd − 1) × 它 ≈ 离谷边多少格
local function valleyD(x, z)
  local W = valleyHalf(z)
  local L = 9150 + 420 * noise(x / 2600, 5.1, 0.3)
  local u, v = (x - valleyX(z)) / W, z / L
  local u2, v2 = u * u, v * v
  local u4, v4 = u2 * u2, v2 * v2
  local s = u4 + v4
  local wz = v4 / max(s, 1e-9)
  return sqrt(sqrt(s)), W + (L - W) * wz
end
Map.valleyD = valleyD

---------------------------------------------------------------- 谷底的自然地形（不算路、房子的挖填）
--   用户 11-26 夜「坦克交战的地方太平整了 战雷不是这样的」、11-27「战雷每座小山都是有意摆的，我们只有几个点是专门设计的，其余靠随机」——
--   谷底的丘、梁、沟、岩石一块块按用途摆（下面 FEAT），噪声只留一层缓缓的底子和小坎（车体隐蔽、雪堆）。
--   打法（南边攻方基地 → 北边守方基地，三条路）：
--   · 西路：锯木厂（A）→ 雷达站台地（B）→ 河西岸 → 山口西肩；东路：河东岸 → 坝南岗 → 水电站（D）→ 山口东肩；中路：主路 → 山村（C）过石桥 → 山口（E）
--   · 每条路上每隔六七百米一道横着的梁（两边都有车体隐蔽的射击位，背后是反斜面），梁和梁之间是洼地（死角）；路从梁上的豁口过
--   · 几处制高点两边对称摆（攻方近的一个、守方近的一个）：教堂北岗 / 磨坊坡、雷达北丘 / 坝南岗、河西丘 / 河东丘
--   · 冲沟是侧翼迂回的暗道；岩石（硬掩体，坦克上不去、打不穿）摆在梁顶、山包顶和据点外围
--   1 米 = 2.8 格，坦克车高 7～9 格；坡大多 5°～20°，梁的陡面 25°～35°（雪地上会往下滑），岩石更陡
-- 基地：基地里是平的，外面 900 格慢慢起来（1 = 基地里）
local function baseK(x, z)
  local k = 0
  for _, B in pairs(Map.BASES) do
    local r = B.rect
    local dx = max(r.x0 - x, 0, x - r.x1)
    local dz = max(r.z0 - z, 0, z - r.z1)
    if dx == 0 and dz == 0 then return 1 end
    if dx < 900 and dz < 900 then k = max(k, 1 - smooth(0, 900, sqrt(dx * dx + dz * dz))) end
  end
  return k
end
local C_LAND = {   -- 有名字的地形：{ x, z, 半径, 高 }（台地、山口的肩）
  mesa = { P_B.x - 120, P_B.z, 320, 740, 92 },             -- 雷达站台地：顶上 320 格是平的，740 格落到底；东边那面陡（距离 × 1.7）
  shW = { P_E.x - 700, P_E.z - 120, 950, 165 },            -- 山口西肩
  shE = { P_E.x + 760, P_E.z - 180, 1000, 185 },           -- 山口东肩
}
Map.C_LAND = C_LAND
-- 摆的地形：
--   { "hill", x, z, 长半轴, 短半轴, 转角°, 高, 顶上平的比例, 林 }（林 = true：这座山上树多）
--   { "ridge", { 折线点… }, 半宽, 高, 陡面（1 折线左边陡、−1 右边陡、0 两边一样）}
--   { "gully", { 折线点… }, 半宽, 深 }
--   { "rock", x, z, 长, 宽, 转角°, 高 }
local FEAT = {
  -- 南段（锯木厂 A 一带）
  { "hill", -2150, 3250, 820, 560, 105, 88, 0.15, true },          -- 锯木厂后山（林）：西路的高地，A 的西侧屏障
  { "ridge", { { -2700, 4350 }, { -1700, 4250 }, { -1020, 4330 } }, 200, 42, -1 },   -- 南梁西段：攻方压 A 的射击线（北面陡）
  { "ridge", { { -420, 4300 }, { 400, 4420 }, { 1250, 4300 } }, 180, 30, -1 },       -- 南梁东段（主路从豁口过）
  { "ridge", { { -2500, 2250 }, { -1700, 2150 }, { -1180, 2300 } }, 180, 38, 1 },    -- 磨坊北梁：守 A 的一线（南面陡）
  { "ridge", { { -640, 2360 }, { 120, 2520 } }, 160, 28, 1 },                         -- 磨坊北梁东段
  { "hill", 800, 3900, 650, 480, -20, 48, 0.25 },                  -- 南岗
  { "hill", 1900, 5000, 700, 500, 10, 36, 0.2 },                   -- 南坡
  { "hill", -500, 2750, 450, 450, 0, -24, 0.3 },                   -- 磨坊洼地（死角）
  { "gully", { { -2000, 5400 }, { -1650, 4800 }, { -1350, 4450 }, { -1200, 3900 } }, 60, 18 },   -- 南沟：绕到 A 西边的暗道
  -- 中段（雷达站 B、山村 C、水电站 D）
  { "ridge", { { -1600, 1520 }, { -1100, 1050 }, { -720, 660 } }, 170, 30, 0 },      -- 雷达东梁：挡住台地直射山村的视线
  { "hill", -650, -950, 520, 430, 35, 52, 0.3 },                   -- 教堂北岗（守方看山村的高处）
  { "hill", 650, 950, 520, 430, 35, 52, 0.3 },                     -- 磨坊坡（攻方看山村的高处，和上面对称）
  { "hill", -2300, -600, 600, 520, 20, 58, 0.25, true },           -- 雷达北丘（林）
  { "hill", 2500, 600, 520, 420, 0, 60, 0.25 },                    -- 坝南岗（和雷达北丘对称）
  { "hill", -1300, 1700, 420, 360, 45, 38, 0.3 },                  -- 河西丘
  { "hill", 1300, -1700, 420, 360, 45, 38, 0.3 },                  -- 河东丘（对称）
  { "ridge", { { 1150, 120 }, { 1750, -260 } }, 150, 26, 0 },                         -- 坝西梁：山村到水电站之间
  { "ridge", { { -1750, 260 }, { -1150, -120 } }, 150, 26, 0 },                       -- 台地东北梁（对称）
  { "gully", { { -3000, -150 }, { -2500, -900 }, { -2050, -1350 } }, 70, 22 },   -- 西沟：台地背后通河边
  { "gully", { { 3300, 2650 }, { 2600, 2250 }, { 2000, 2250 } }, 70, 20 },       -- 东沟
  -- 北段（山口 E 一带）
  { "ridge", { { -700, -2350 }, { 300, -2250 } }, 190, 40, -1 },                      -- 山口前梁西段：守方的前沿（南面陡）
  { "ridge", { { 1250, -2200 }, { 2600, -2350 } }, 190, 40, -1 },                    -- 山口前梁东段（主路从豁口过）
  { "hill", 900, -2900, 520, 420, 0, -22, 0.3 },                   -- 山口前洼地
  { "hill", -1500, -3600, 800, 700, 0, 76, 0.2, true },            -- 北林山
  { "hill", 2600, -2750, 600, 520, 30, 55, 0.25 },                 -- 东北丘
  { "gully", { { -1250, -2650 }, { -400, -3050 }, { 250, -3850 } }, 60, 18 },    -- 北沟：从西边摸到山口
  { "ridge", { { -1650, -5000 }, { -420, -4950 } }, 200, 30, 1 },                     -- 北基地前梁西段（守方最后一道）
  { "ridge", { { 520, -4900 }, { 1700, -5000 } }, 200, 30, 1 },                       -- 北基地前梁东段
  -- 补的（11-27 量了视线：山村—水电站之间、北基地门前、南边主路以东三片开阔地一眼望穿两三公里）
  { "ridge", { { 1250, 900 }, { 1150, 200 }, { 1300, -600 }, { 1150, -1300 } }, 190, 34, 0 },   -- 河东长梁：山村和水电站之间隔开
  { "hill", 1650, 1050, 480, 380, 20, 50, 0.25 },                  -- 河东南丘
  { "hill", 700, -1050, 380, 320, -30, 34, 0.3 },                  -- 村东北小丘
  { "hill", -2150, -4300, 650, 520, 10, 62, 0.2, true },           -- 北门西丘（林）
  { "hill", 2250, -4450, 620, 500, -15, 56, 0.2 },                 -- 北门东丘
  { "hill", -250, -4150, 420, 340, 70, 36, 0.3 },                  -- 北门前小丘
  { "ridge", { { -2300, -3300 }, { -1700, -2500 }, { -900, -2050 } }, 170, 30, 0 },   -- 西北斜梁
  { "ridge", { { 250, 1750 }, { 900, 2350 }, { 1500, 2950 } }, 180, 32, 0 },          -- 南东斜梁
  { "hill", 1950, 3250, 520, 420, 35, 50, 0.25 },                  -- 东南岗
  { "hill", 250, 3350, 420, 360, 0, 34, 0.3 },                     -- 主路东小丘
  { "hill", -2450, 1900, 450, 380, 50, 40, 0.3 },                  -- 西缘丘
  -- 岩石（硬掩体）：梁顶、山包顶、据点外围
  { "rock", -1900, 4270, 120, 40, 80, 22 }, { "rock", -2050, 3300, 90, 50, 20, 26 }, { "rock", 950, 4390, 80, 35, 100, 18 },
  { "rock", -2280, -650, 100, 45, 30, 24 }, { "rock", -640, -930, 70, 40, 60, 20 }, { "rock", 640, 930, 70, 40, 60, 20 },
  { "rock", 2520, 620, 90, 40, 0, 22 }, { "rock", -200, -2290, 110, 40, 85, 20 }, { "rock", 2000, -2280, 110, 40, 95, 20 },
  { "rock", -1500, -3500, 120, 60, 10, 28 }, { "rock", 200, -3560, 140, 50, 70, 30 }, { "rock", 1600, -3620, 140, 50, 110, 30 },
  { "rock", 1150, 2430, 80, 30, 30, 16 }, { "rock", -1460, 2210, 70, 30, 100, 16 }, { "rock", -1250, 1730, 60, 35, 40, 15 },
  { "rock", 1250, -1730, 60, 35, 40, 15 }, { "rock", -1050, 1050, 70, 28, 135, 14 },
}
Map.FEAT = FEAT
-- 预算：折线每段的长度、包围盒；按 512 格的格子登记
local FG, FGC = {}, 512
local function fgk(gx, gz) return (gx + 256) * 512 + gz + 256 end
for _, F in ipairs(FEAT) do
  local t = F[1]
  local x0, z0, x1, z1
  if t == "hill" or t == "rock" then
    local a = math.rad(F[6])
    F.c, F.s = cos(a), sin(a)
    local r = (t == "hill") and max(F[4], F[5]) or max(F[4], F[5]) * 0.6 + 10
    x0, z0, x1, z1 = F[2] - r, F[3] - r, F[2] + r, F[3] + r
  else
    local pts, w = F[2], F[3]
    F.L, F.acc = 0, { 0 }
    x0, z0, x1, z1 = 1e9, 1e9, -1e9, -1e9
    for i, q in ipairs(pts) do
      if i > 1 then F.L += sqrt((q[1] - pts[i - 1][1]) ^ 2 + (q[2] - pts[i - 1][2]) ^ 2) F.acc[i] = F.L end
      x0, z0, x1, z1 = min(x0, q[1]), min(z0, q[2]), max(x1, q[1]), max(z1, q[2])
    end
    local m = w * 1.4
    x0, z0, x1, z1 = x0 - m, z0 - m, x1 + m, z1 + m
  end
  for gx = floor(x0 / FGC), floor(x1 / FGC) do
    for gz = floor(z0 / FGC), floor(z1 / FGC) do
      local k = fgk(gx, gz)
      local l = FG[k]
      if not l then l = {} FG[k] = l end
      table.insert(l, F)
    end
  end
end
-- 点到折线：距离、沿线里程、在左边（+1）还是右边（−1）
local function polyNear(pts, acc, x, z)
  local best, bs, bside = 1e18, 0, 1
  for i = 1, #pts - 1 do
    local ax, az, bx, bz = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
    local dx, dz = bx - ax, bz - az
    local L2 = dx * dx + dz * dz
    local t = clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
    local px, pz = ax + dx * t - x, az + dz * t - z
    local d = px * px + pz * pz
    if d < best then
      best, bs = d, acc[i] + sqrt(L2) * t
      bside = (dx * (z - az) - dz * (x - ax) > 0) and 1 or -1
    end
  end
  return sqrt(best), bs, bside
end
-- 这一点摆的地形加多少高；第二个返回：在岩石上（定材质）；第三个：在林子里（种树）
local function featH(x, z)
  local l = FG[fgk(x // FGC, z // FGC)]
  if not l then return 0, false, false end
  local h, rock, forest = 0, false, false
  for _, F in ipairs(l) do
    local t = F[1]
    if t == "hill" then
      -- 轮廓扭一扭（不是规整的椭圆：一边鼓出一道山嘴、一边凹进去）
      local dx = x - F[2] + 0.22 * F[4] * noise(x / 380, z / 380, F[3] * 0.001)
      local dz = z - F[3] + 0.22 * F[5] * noise(x / 380 + 3.7, z / 380, F[2] * 0.001)
      local u, v = (dx * F.c + dz * F.s) / F[4], (-dx * F.s + dz * F.c) / F[5]
      local q = u * u + v * v
      if q < 1 then
        local r = sqrt(q)
        local k = clamp((1 - r) / (1 - (F[8] or 0)), 0, 1)
        h += F[7] * k * k * (3 - 2 * k)
        if F[9] and r < 0.85 then forest = true end
      end
    elseif t == "ridge" then
      local d, a, side = polyNear(F[2], F.acc, x, z)
      local w = F[3] * ((F[5] == side) and 0.6 or ((F[5] == -side) and 1.35 or 1))
      if d < w then
        local e = smooth(0, 260, a) * smooth(0, 260, F.L - a)
        local k = 1 - (d / w) ^ 2
        h += F[4] * e * k * k
      end
    elseif t == "gully" then
      local d, a = polyNear(F[2], F.acc, x, z)
      if d < F[3] then
        local e = smooth(0, 200, a) * smooth(0, 200, F.L - a)
        h -= F[4] * e * (1 - d / F[3]) ^ 1.4
      end
    else   -- rock：一块长方的岩石，四边陡（坡 1.2 以上），顶上不平
      local dx, dz = x - F[2], z - F[3]
      local u, v = (dx * F.c + dz * F.s) / (F[4] * 0.5), (-dx * F.s + dz * F.c) / (F[5] * 0.5)
      local sq = (u ^ 4 + v ^ 4) ^ 0.25
      if sq < 1.08 then
        local k = clamp((1.08 - sq) / 0.3, 0, 1)
        h += F[7] * k * (0.8 + 0.35 * noise(x / 17, z / 17, F[2] * 0.001))
        rock = true
      end
    end
  end
  return h, rock, forest
end
Map.featH = featH
local function natH(x, z)
  local bk = baseK(x, z)
  if bk >= 1 then return PLAIN end
  local vd = valleyD(x, z)
  if vd > 1.48 then   -- 岛外的海：海底（同下面海岸那段，这里已经整个落进海里）
    local cd = vd + 0.07 * noise(x / 2600, z / 2600, 51.3) + 0.03 * noise(x / 700, z / 700, 17.9)
    return max(-26, -5 - 21 * smooth(1.3, 1.62, cd))
  end
  -- 底子：缓缓的起伏（±20 格上下），扭一扭坐标
  local wx = x + 300 * noise(x / 2100, z / 2100, 31.7)
  local wz = z + 300 * noise(x / 2100 + 5.2, z / 2100, 13.3)
  local rel = 34 + 26 * noise(wx / 2600, wz / 2600, 2.2) + 22 * noise(wx / 1100, wz / 1100, 7.9) + 9 * noise(wx / 560, wz / 560, 21.4)
  if rel < 4 then rel = 4 + (rel - 4) * 0.3 end
  -- 小坎（车体隐蔽）
  rel += 6 * noise(x / 260, z / 260, 1.7) + 3 * noise(x / 118, z / 118, 3.3)
  -- 摆的地形
  rel += (featH(x, z))
  -- 山村（C）：河边一块浅盆地（起伏收到三成）
  do
    local d = sqrt(x * x + z * z)
    if d < 900 then rel *= 0.3 + 0.7 * smooth(260, 900, d) end
  end
  -- 锯木厂（A）：一级台阶
  do
    local dx, dz = x - P_A.x, z - P_A.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 560 then rel = lerp(34, rel, smooth(240, 560, d)) end
  end
  -- 河谷：河两边是低一截的河滩，河滩外一道陡坎（凹岸那边离河远、凸岸近，跟着弯换边）；再往外的起伏也收小一点
  local rd, rs, rside = riverNear(x, z)
  if rd < 900 then
    rel = 26 + (rel - 26) * (0.3 + 0.7 * smooth(260, 850, rd))
    local ph = sin(rs / MEANDER_L * 2 * math.pi + 0.6 + 1.2 * noise(rs / 2700, 8.8, 0.3))
    local bnk = 125 + 135 * max(0, -rside * ph)
    if rd < bnk + 45 then rel = lerp(2, rel, smooth(bnk, bnk + 45, rd)) end
  end
  -- 有名字的地形：雷达站台地、山口的两肩
  do
    local M = C_LAND.mesa
    local dx, dz = x - M[1], z - M[2]
    if dx > 0 then dx *= 1.7 end
    local d = sqrt(dx * dx + dz * dz)
    if d < M[4] then
      local top = M[5] + 40
      rel = max(rel, lerp(top, rel, smooth(M[3], M[4], d)))
    end
    for _, S in ipairs({ C_LAND.shW, C_LAND.shE }) do
      local ex, ez = x - S[1], z - S[2]
      local q = (ex * ex + ez * ez) / (S[3] * S[3])
      if q < 1 then
        local a = 1 - q
        rel += S[4] * a * a * (0.85 + 0.3 * noise(x / 300, z / 300, S[4]))
      end
    end
  end
  -- 谷两侧的山麓：越往谷边越高；河出入谷的地方山麓让开一道宽谷
  -- 用户 11-27「河谷可能成狙击走廊」：谷两侧原来从 vd 0.6 就开始抬（整个谷像个碗，到处都被两边高处看得见）——
  --   作战区里（vd < 0.95，边上有看不见的墙）只缓缓抬一点，真正的山麓在墙外面抬起来；河出入谷的地方山麓让开一道宽谷
  local fl = smooth(0.78, 1.0, vd)
  rel += (60 * fl + 170 * smooth(0.97, 1.18, vd)) * (0.2 + 0.8 * smooth(150, 1000, rd))
  rel *= 1 - bk
  local h = PLAIN + rel + 1.8 * noise(x / 55, z / 55, 6.1) * (1 - bk)
  -- 海岸：岛的外缘（谷边往外，vd 约 1.18～1.36）落进海里；岸线弯进弯出（海湾、岬角）
  local cd = vd + 0.07 * noise(x / 2600, z / 2600, 51.3) + 0.03 * noise(x / 700, z / 700, 17.9)
  if cd > 1.16 then
    local sea = -5 - 21 * smooth(1.3, 1.62, cd)
    h = lerp(h, sea, smooth(1.16, 1.36, cd))
    if h < -26 then h = -26 end
  end
  -- 湖：高台上的水库（四周一圈岸），坝下的豁口
  local ld = lakeD(x, z)
  if ld < 2.1 then
    local L = LAKE
    if x > L.damX and ld <= 1 then return L.y end
    local rim = L.y + 4 + 12 * smooth(1, 1.25, ld)
    h = max(h, lerp(rim, h, smooth(1.35, 2.1, ld)))
    if x < L.damX + 8 then
      local az = abs(z - L.z)
      local side = smooth(L.damHalf - 70, L.damHalf + 10, az)
      local west = smooth(200, 800, L.damX - x)
      local k = max(side, west)
      if k < 1 then h = lerp(L.foot, h, k) end
    end
  end
  return h
end
Map.natH = natH

---------------------------------------------------------------- 路（零件铺的压雪路；地形底下是 Ground）

-- 路段：{ ax, az, bx, bz, 宽, 种类, 所在的那条路, 起点在那条路上的里程 }；main 谷里的主路（河西岸南北一条）、side 支路
--   每条路（折线）顺着地形有自己的路面高（下面 roadProfiles 算，每 16 格一个）
local SEGS = {}
local POLYS = {}
local function seg(ax, az, bx, bz, w, k, P, s0) table.insert(SEGS, { ax, az, bx, bz, w, k or "side", P, s0 or 0 }) end
local function poly(pts, w, k)
  local P = { pts = pts, w = w, k = k }
  table.insert(POLYS, P)
  local acc = 0
  for i = 1, #pts - 1 do
    seg(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], w, k, P, acc)
    acc += sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2)
  end
  P.L = acc
end
do
  -- 主路：南基地正门 → 锯木厂 → 山村（过石桥）→ 山口 → 北基地正门
  poly({ { 0, BZ - 700 }, { -300, 5200 }, { -900, 3900 }, { -1150, 3300 }, { -900, 2200 }, { -420, 1100 }, { -120, 300 }, { 0, 0 },
    { 250, -700 }, { 600, -1900 }, { 900, -3400 }, { 600, -4700 }, { 0, -(BZ - 700) } }, 34, "main")
  -- 去雷达站的盘山路（B 在西边的台地上）
  poly({ { -420, 1100 }, { -1100, 1080 }, { -1650, 990 }, { -2000, 900 } }, 22, "side")
  -- 山村往东过河去水电站（坝顶也能走）
  poly({ { 0, 0 }, { 900, -300 }, { 1700, -700 }, { 2300, -900 } }, 26, "side")
  -- 锯木厂往东过河，从西南边进水电站（不翻湖岸的高处）
  poly({ { -900, 2200 }, { 600, 2300 }, { 1900, 1900 }, { 2300, 700 }, { 2120, -450 }, { 2300, -900 } }, 22, "side")
  -- 山口往西去雷达站背后
  poly({ { 900, -3400 }, { -400, -2900 }, { -1700, -1500 }, { -2250, -200 }, { -2000, 900 } }, 20, "side")
  -- 铁路（用户 11-28「剩下你自己设计参考战雷地图冰风谷」：照冰封山口——两军争一个山口，西南有一条铁路穿山）：谷的西边南北一条单线，
  --   南头在南基地西边、北头在北基地西边；坡不超过 3.5%（火车爬不了陡坡），遇到小山挖路堑、遇到洼地填路堤（坦克的掩体：堤后面藏车、堑里走车）；
  --   挖得深的几段（北基地门前那道梁、锯木厂西南的小山包、南基地西北的坡）盖混凝土防雪棚（坦克能从棚里穿过去，就是图上那条「隧道」，SnowBuild.lua 建）；
  --   山村西边一个车站（三股道的站场：Map.RAIL_YARD，停着废弃的车皮、机车）；山村西南过河一座钢桁架桥；和两条支路平交（道口）
  --   11-28 晚：北段原来从西边几座 150 格高的山包上翻（x -2400 一线），3.5% 的坡跟不上，路堤填到 46 格还不够、坡度破了上限——
  --   改走东边那条低谷（x -1700 一线，自然地面 30～75 格），只在北边那道东西向的梁（z 4400）和锯木厂西边的小山包上挖路堑
  poly({ { -2700, 7400 }, { -2650, 6300 }, { -2350, 5400 }, { -1850, 4500 }, { -1700, 3700 }, { -1580, 3000 }, { -1700, 2300 }, { -1750, 1700 }, { -1380, 920 }, { -1180, 380 } }, 18, "rail")
  poly({ { -1180, 380 }, { -1150, -260 } }, 62, "yard")
  poly({ { -1150, -260 }, { -1150, -700 }, { -1250, -1500 }, { -1300, -2450 }, { -880, -3300 }, { -900, -4300 }, { -1550, -5250 }, { -2550, -6200 }, { -2800, -7400 } }, 18, "rail")
end
Map.SEGS = SEGS
Map.RAIL_YARD = { ax = -1180, az = 380, bx = -1150, bz = -260, tracks = { -20, 0, 20 } }   -- 站场：三股道（离中线的偏移，格）
local RCELL = 64
local rgrid = {}
local function rkey(gx, gz) return (gx + 2048) * 4096 + gz + 2048 end
for k, s in ipairs(SEGS) do
  local pad = s[5] * 0.5 + 40
  for gx = floor((min(s[1], s[3]) - pad) / RCELL), floor((max(s[1], s[3]) + pad) / RCELL) do
    for gz = floor((min(s[2], s[4]) - pad) / RCELL), floor((max(s[2], s[4]) + pad) / RCELL) do
      local key = rkey(gx, gz)
      local l = rgrid[key]
      if not l then l = {} rgrid[key] = l end
      table.insert(l, k)
    end
  end
end
local PSTEP = 16   -- 路面高每 16 格一个
-- 一条路在里程 m 处的路面高（还没算好时是平地的高）
--   取样点：里程 0、16、32……，最后一个正好在路的终点（P.L）
local function profAt(P, m)
  local H = P.h
  if not H then return PLAIN end
  local n = #H
  local m2 = (n - 2) * PSTEP   -- 倒数第二个点的里程
  if m >= m2 then
    local t = clamp((m - m2) / max(P.L - m2, 1e-6), 0, 1)
    return H[n - 1] + (H[n] - H[n - 1]) * t
  end
  local f = max(m, 0) / PSTEP
  local i = floor(f)
  return H[i + 1] + (H[i + 2] - H[i + 1]) * (f - i)
end
local function roadNear(x, z)
  local l = rgrid[rkey(floor(x / RCELL), floor(z / RCELL))]
  if not l then return nil end
  local best, bw, bk, bs, bt = 1e18, 0, nil, nil, 0
  for _, k in ipairs(l) do
    local s = SEGS[k]
    local ax, az = s[1], s[2]
    local dx, dz = s[3] - ax, s[4] - az
    local L2 = dx * dx + dz * dz
    local t = (L2 > 0) and clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1) or 0
    local px, pz = ax + dx * t - x, az + dz * t - z
    local d = px * px + pz * pz
    if d < best then best, bw, bk, bs, bt = d, s[5], s[6], s, t end
  end
  if best >= 1e18 then return nil end
  local y = PLAIN
  if bs then y = profAt(bs[7], bs[8] + bt * sqrt((bs[3] - bs[1]) ^ 2 + (bs[4] - bs[2]) ^ 2)) end
  return sqrt(best), y, bw, bk
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
Map.ROADS = {}   -- 路面高（y）在下面算好路面以后填
-- 桥：路和河交叉的地方（SnowBuild.lua 建石桥 / 钢桥；地形那段河照样是冰）
Map.BRIDGES = {}
do
  for _, s in ipairs(SEGS) do
    local n = max(2, floor(sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2) / 20))
    local inside = false
    local t0 = nil
    for q = 0, n do
      local t = q / n
      local x, z = s[1] + (s[3] - s[1]) * t, s[2] + (s[4] - s[2]) * t
      local d = riverDist(x, z)
      if d < RIVER_W + RIVER_BANK * 0.6 and not inside then inside, t0 = true, t
      elseif d >= RIVER_W + RIVER_BANK * 0.6 and inside then
        inside = false
        local tm = (t0 + t) / 2
        local Ls = sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
        table.insert(Map.BRIDGES, { x = s[1] + (s[3] - s[1]) * tm, z = s[2] + (s[4] - s[2]) * tm, ax = s[1] + (s[3] - s[1]) * t0, az = s[2] + (s[4] - s[2]) * t0,
          bx = s[1] + (s[3] - s[1]) * t, bz = s[2] + (s[4] - s[2]) * t, w = s[5] + 8, k = s[6], P = s[7], m0 = s[8] + t0 * Ls, m1 = s[8] + t * Ls })
      end
    end
  end
end

-- 路面：顺着自然地形走（每 16 格取一个自然高度，前后各约 110 格平均两遍，坡不超过 15%）；过河的地方（桥头往外 40 格）落到河滩的高，
--   支路接上主路的那头跟主路一样高（按 POLYS 的先后：主路先算）
do
  local MAXG = 0.15 * PSTEP
  local function locate(P, m)   -- 里程 m 在折线上的点
    local pts = P.pts
    local acc = 0
    for i = 1, #pts - 1 do
      local L = sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2)
      if m <= acc + L or i == #pts - 1 then
        local t = (L > 0) and clamp((m - acc) / L, 0, 1) or 0
        return pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t, pts[i][2] + (pts[i + 1][2] - pts[i][2]) * t
      end
      acc += L
    end
    return pts[#pts][1], pts[#pts][2]
  end
  -- 点 (x, z) 在已经算好的路上吗（离折线 6 格以内）：返回那里的路面高
  local function onDone(x, z, self)
    for _, Q in ipairs(POLYS) do
      if Q ~= self and Q.h then
        local pts, acc = Q.pts, 0
        for i = 1, #pts - 1 do
          local ax, az, bx, bz = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
          local dx, dz = bx - ax, bz - az
          local L = sqrt(dx * dx + dz * dz)
          local t = (L > 0) and clamp(((x - ax) * dx + (z - az) * dz) / (L * L), 0, 1) or 0
          if (ax + dx * t - x) ^ 2 + (az + dz * t - z) ^ 2 < 36 then return profAt(Q, acc + t * L) end
          acc += L
        end
      end
    end
    return nil
  end
  local function mOf(P, n, q) return (q == n) and P.L or (q - 1) * PSTEP end
  -- 铁路（rail、站场 yard）：坡不超过 3.5%、平均的窗口大一倍；挖填先按 70 格收（路堑、路堤），收完再按坡度扫一遍（坡度说了算）
  --   11-28 晚：铁路先算、公路后算——道口是路迁就铁路（路面钉成轨面的高，路的坡 15% 接得上）；原来反过来钉铁路，
  --   站场南头离道口、河太近，一步落差二十格（坡 123%）。铁路过河不落到河滩：河上架高桥（Map.BRIDGES 的 y0 / y1，SnowBuild 立高墩）
  local RAILP = { maxg = 0.035 * PSTEP, win = 14, passes = 3, cut = 70 }
  local ROADP = { maxg = MAXG, win = 7, passes = 2, cut = 20 }
  local function isRail(Q) return Q.k == "rail" or Q.k == "yard" end
  local function crossAt(x, z, self)   -- 离已经算好的铁路多近：返回那里的轨面高（公路在道口钉成这个高）
    for _, Q in ipairs(POLYS) do
      if Q ~= self and Q.h and isRail(Q) then
        local pts, acc = Q.pts, 0
        for i = 1, #pts - 1 do
          local ax, az, bx, bz = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
          local dx, dz = bx - ax, bz - az
          local L = sqrt(dx * dx + dz * dz)
          local t = (L > 0) and clamp(((x - ax) * dx + (z - az) * dz) / (L * L), 0, 1) or 0
          if (ax + dx * t - x) ^ 2 + (az + dz * t - z) ^ 2 < (Q.w * 0.5 + 6) ^ 2 then return profAt(Q, acc + t * L) end
          acc += L
        end
      end
    end
    return nil
  end
  local ORDER = {}
  for _, P in ipairs(POLYS) do if isRail(P) then table.insert(ORDER, P) end end
  for _, P in ipairs(POLYS) do if not isRail(P) then table.insert(ORDER, P) end end
  for _, P in ipairs(ORDER) do
    local rail = isRail(P)
    local PP = rail and RAILP or ROADP
    local n = floor(P.L / PSTEP) + 2
    local H, pin = table.create(n), table.create(n, false)
    for q = 1, n do
      local x, z = locate(P, mOf(P, n, q))
      H[q] = natH(x, z)
      if not rail then
        if riverDist(x, z) < RIVER_W + RIVER_BANK + 40 then pin[q], H[q] = true, PLAIN end
        if not pin[q] then   -- 道口：路面和轨面一样高
          local y = crossAt(x, z, P)
          if y then pin[q], H[q] = true, y end
        end
      end
    end
    for _, e in ipairs({ 1, n }) do
      local x, z = locate(P, mOf(P, n, e))
      local y = onDone(x, z, P)
      if not y then   -- 路通到据点：路面落到据点的地面（水电站在坝下的豁口里，路不能把它垫高）
        for _, pt in ipairs(Map.POINTS) do
          if (pt.x - x) ^ 2 + (pt.z - z) ^ 2 < 100 then y = natH(x, z) end
        end
      end
      if y then pin[e], H[e] = true, y end
    end
    -- 平均两遍（钉住的不动）：前后各约 110 格——路贴着地形起伏，只抹掉小坎（原来 ±200 格、坡 11%，有的地方挖出二十多米深的路堑）
    for _ = 1, PP.passes do
      local R2, N2 = table.create(n), PP.win
      for q = 1, n do
        if pin[q] then R2[q] = H[q]
        else
          local s, c = 0, 0
          for j = max(1, q - N2), min(n, q + N2) do s += H[j] c += 1 end
          R2[q] = s / c
        end
      end
      H = R2
    end
    -- 坡不超过 15%：前后各扫一遍（钉住的不动）
    for q = 2, n do if not pin[q] then H[q] = clamp(H[q], H[q - 1] - PP.maxg, H[q - 1] + PP.maxg) end end
    for q = n - 1, 1, -1 do if not pin[q] then H[q] = clamp(H[q], H[q + 1] - PP.maxg, H[q + 1] + PP.maxg) end end
    -- 挖、填都不超过 20 格（7 米）：翻梁的地方路面跟着梁起来一点（短的一段陡一些），不挖二十多米深的沟；铁路 70 格（深堑、高堤）
    for q = 1, n do
      if not pin[q] then
        local x, z = locate(P, mOf(P, n, q))
        local nh = natH(x, z)
        H[q] = clamp(H[q], nh - PP.cut, nh + PP.cut)
      end
    end
    if rail then   -- 铁路：收完挖填再扫一遍坡（火车爬不了陡坡：坡度说了算，个别地方挖得更深）
      for q = 2, n do if not pin[q] then H[q] = clamp(H[q], H[q - 1] - PP.maxg, H[q - 1] + PP.maxg) end end
      for q = n - 1, 1, -1 do if not pin[q] then H[q] = clamp(H[q], H[q + 1] - PP.maxg, H[q + 1] + PP.maxg) end end
    end
    P.h = H
    -- 铁路：挖得深的地方（自然地面比轨面高 16 格以上、连着 140 格以上）记下来盖防雪棚（SnowBuild.lua）；P.cutDepth[q] 记每一点挖了多深
    if rail then
      P.cutD = table.create(n)
      for q = 1, n do
        local x, z = locate(P, mOf(P, n, q))
        P.cutD[q] = natH(x, z) - H[q]
      end
    end
  end
  for _, sg in ipairs(SEGS) do
    local L = sqrt((sg[3] - sg[1]) ^ 2 + (sg[4] - sg[2]) ^ 2)
    table.insert(Map.ROADS, { name = sg[6], w = sg[5], x = { sg[1], sg[3] }, z = { sg[2], sg[4] }, y = { profAt(sg[7], sg[8]), profAt(sg[7], sg[8] + L) } })
  end
  -- 桥面两头的高（公路桥就是河滩的高；铁路桥照轨面，高出河滩一截，SnowBuild 立高墩）
  for _, B in ipairs(Map.BRIDGES) do
    if B.P then B.y0, B.y1 = profAt(B.P, B.m0), profAt(B.P, B.m1) end
    B.P = nil
  end
end
Map.POLYS = POLYS
-- 折线 P 在里程 m 处的点和方向（单位向量）
local function polyPoint(P, m)
  local pts = P.pts
  local acc = 0
  for i = 1, #pts - 1 do
    local dx, dz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
    local L = sqrt(dx * dx + dz * dz)
    if m <= acc + L or i == #pts - 1 then
      local t = (L > 0) and clamp((m - acc) / L, 0, 1) or 0
      return pts[i][1] + dx * t, pts[i][2] + dz * t, dx / max(L, 1e-6), dz / max(L, 1e-6)
    end
    acc += L
  end
  return pts[#pts][1], pts[#pts][2], 0, -1
end
Map.polyPoint = polyPoint
Map.profAt = profAt
-- 防雪棚：铁路挖得深的几段（自然地面比轨面高 16 格以上、连着 140 格以上；挑最长的三段）——{ P 那条铁路, m0, m1 里程, deep 最深挖了多少 }
Map.GALLERIES = {}
for _, P in ipairs(POLYS) do
  if P.k == "rail" and P.cutD then
    local n = #P.cutD
    local run0, deep = nil, 0
    for q = 1, n + 1 do
      local d = (q <= n) and P.cutD[q] or 0
      -- 11-28 晚改线以后路堑浅了（最深二三十格、一百来格长）：挖下去 12 格以上、连着 96 格以上就盖（原来 16 格、140 格）
      if d > 12 then
        if not run0 then run0, deep = q, 0 end
        deep = max(deep, d)
      elseif run0 then
        local m0, m1 = (run0 - 1) * PSTEP, (q - 2) * PSTEP
        if m1 - m0 >= 96 and deep > 16 then table.insert(Map.GALLERIES, { P = P, m0 = max(0, m0 - 20), m1 = min(P.L, m1 + 20), deep = deep }) end
        run0 = nil
      end
    end
  end
end
table.sort(Map.GALLERIES, function(a2, b2) return (a2.m1 - a2.m0) > (b2.m1 - b2.m0) end)
while #Map.GALLERIES > 4 do table.remove(Map.GALLERIES) end

---------------------------------------------------------------- 谷外的山体（Sketchfab 的山体模型拼的：tools/snow，数据在 ReplicatedStorage.SnowPeaks）
--   用户 11-26 晚：「坦克交战区外你就用这几个拿去拼」「让这个地图望不到头」——一百七十来座山体（6 个 CC-BY 模型转着摆、外圈自动铺到四万多格），
--   客户端在本机摆模型（Client/SnowPeaks.lua：不受串流影响，远处也看得见）；这里只给高度：每个模型一张俯视高度图（u16，1/16 格），
--   查一点有多高时转到附近每一座的模型坐标里双线性取样，取最高的。飞机撞山、炮弹落点、AI、谷边写体素都照它
local PEAKS_FAR = PLAIN - 0.5
local peaksData   -- (名字) → 数据模块（名字 nil 是摆法表）；测试台（Lune）里用 SNOWPEAKS_LOAD
do
  local holder = nil
  peaksData = function(name)
    if SNOWPEAKS_LOAD then return SNOWPEAKS_LOAD(name) end
    if not holder then holder = script.Parent:WaitForChild("SnowPeaks", 10) end
    if not holder then return nil end
    if name == nil then return require(holder) end
    return require(holder:WaitForChild(name, 10))
  end
end
local B64 = {}
do
  local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B64[string.byte(abc, i)] = i - 1 end
end
-- base64 → buffer（一段 65536 个字符；4 个字符一组）
local function b64decode(parts)
  local n = 0
  for _, p in ipairs(parts) do n += #p end
  local last = parts[#parts] or ""
  local pad = (string.sub(last, -2) == "==") and 2 or ((string.sub(last, -1) == "=") and 1 or 0)
  local len = n // 4 * 3 - pad
  local out = buffer.create(len)
  local o = 0
  for _, p in ipairs(parts) do
    for i = 1, #p, 4 do
      local a, b, c, d = string.byte(p, i, i + 3)
      local v = B64[a] * 262144 + B64[b] * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
      buffer.writeu8(out, o, v // 65536)
      if o + 1 < len then buffer.writeu8(out, o + 1, (v // 256) % 256) end
      if o + 2 < len then buffer.writeu8(out, o + 2, v % 256) end
      o += 3
    end
  end
  return out
end
local pkModels = {}
local function pkModel(key)
  local m = pkModels[key]
  if m ~= nil then return m or nil end
  local ok, d = pcall(peaksData, key)
  if not ok or type(d) ~= "table" or not d.b64 then
    pkModels[key] = false
    return nil
  end
  m = { nx = d.nx, nz = d.nz, cell = d.cell, x0 = d.x0, z0 = d.z0, buf = b64decode(d.b64) }
  pkModels[key] = m
  return m
end
Map.peakModel = pkModel
local PEAKS = {}      -- 每座：{ key, x, z, c, s, k, y, r2, fill }
local PGRID, PG = {}, 4096
local function pgkey(gx, gz) return (gx + 512) * 1024 + gz + 512 end
do
  local ok, P = pcall(peaksData, nil)
  if ok and type(P) == "table" and P.inst then
    PEAKS_FAR = P.far or PEAKS_FAR
    for _, I in ipairs(P.inst) do
      local key, x, z, yaw, k, y = I[1], I[2], I[3], I[4], I[5], I[6]
      local ky = I[8] or k   -- 竖着的放大（没有就同 k）
      local sz = P.size and P.size[key] or { 12000, 2000, 12000 }
      local a = math.rad(yaw)
      local r = 0.5 * math.sqrt(sz[1] * sz[1] + sz[3] * sz[3]) * k
      local inst = { key = key, x = x, z = z, c = cos(a), s = sin(a), k = k, ky = ky, y = y, top = y + sz[2] * ky, r2 = r * r, fill = I[7] == true }
      table.insert(PEAKS, inst)
      for gx = floor((x - r) / PG), floor((x + r) / PG) do
        for gz = floor((z - r) / PG), floor((z + r) / PG) do
          local key2 = pgkey(gx, gz)
          local l = PGRID[key2]
          if not l then l = {} PGRID[key2] = l end
          table.insert(l, inst)
        end
      end
    end
  end
end
Map.PEAKS = PEAKS
Map.PEAKS_FAR = PEAKS_FAR
-- 最高的山顶（Map.rayGround 从这往下找落点；飞机的升限按它留够）
for _, I in ipairs(PEAKS) do
  if I.top + 60 > Map.MAXH then Map.MAXH = math.ceil(I.top + 60) end
end
-- 这一点的山有多高（没有山 nil）：附近每一座转到模型坐标（同 tools/snow/layout.py：lx = (dx cos + dz sin) / k、lz = (−dx sin + dz cos) / k），双线性取样取最高
local function peakH(x, z)
  local l = PGRID[pgkey(x // PG, z // PG)]
  if not l then return nil end
  local best = nil
  for _, I in ipairs(l) do
    local dx, dz = x - I.x, z - I.z
    if dx * dx + dz * dz < I.r2 and (not best or I.top > best) then
      local m = pkModel(I.key)
      if m then
        local lx = (dx * I.c + dz * I.s) / I.k
        local lz = (-dx * I.s + dz * I.c) / I.k
        local fx = (lx - m.x0) / m.cell - 0.5
        local fz = (lz - m.z0) / m.cell - 0.5
        local nx, nz = m.nx, m.nz
        if fx >= 0 and fz >= 0 and fx <= nx - 1 and fz <= nz - 1 then
          local ix, iz = floor(fx), floor(fz)
          if ix > nx - 2 then ix = nx - 2 end
          if iz > nz - 2 then iz = nz - 2 end
          local ux, uz = fx - ix, fz - iz
          local b, o = m.buf, (iz * nx + ix) * 2
          local h00, h10 = buffer.readu16(b, o), buffer.readu16(b, o + 2)
          local o2 = o + nx * 2
          local h01, h11 = buffer.readu16(b, o2), buffer.readu16(b, o2 + 2)
          if h00 > 0 and h10 > 0 and h01 > 0 and h11 > 0 then
            local h = ((h00 * (1 - ux) + h10 * ux) * (1 - uz) + (h01 * (1 - ux) + h11 * ux) * uz - 1) / 16 * I.ky + I.y
            if not best or h > best then best = h end
          end
        end
      end
    end
  end
  return best
end
Map.peakH = peakH

---------------------------------------------------------------- 楼（Map.BLD）：山村、几个小村落、农庄、锯木厂、雷达站、水电站、检查站（SnowBuild.lua 照这张表盖）
--   用户 11-26 晚：「多搞点房屋 你自己去sketchfeb找 再加点坏掉的屋子这样」——房子用 Sketchfab 上 CC-BY 的写实模型（models/bld/snow.glb，
--   元数据 SnowMeta：tools/models/sfbld.py 转的）：积雪木屋、阿尔卑斯木屋、木板房、老木楼、原木屋、谷仓、二战石屋……
--   被打坏的：炸毁的楼、会堂、教堂、塌了的木房、烧剩的空壳——山村三成多是废墟（打过仗的样子；废墟也挡车、挡子弹）。
--   每座按模型转过、缩放过的外接矩形登记（k = "model"：碰撞、寻路、视线、炸塌都照它）；没导入 snow.glb 时 SnowBuild 照同样的长宽高用零件拼，
--   所以服务器、客户端、导没导入，哪里能走、哪里挡视线都一样（同钢城）
--   { x, z 中心, w 东西宽, d 南北深, h 高, k 种类（model / mill / plant / hut……）, model 模型键, rot 转角（0 / ½π / π / 1½π）, scale, sd 种子, id }

local BLD = {}
Map.BLD = BLD
-- 各模型的宽（东西）、深（南北）、高（格；照 tools/models/sfbld_snow_meta.json 抄的，转模型时一起改）：房子怎么摆只看这张表——
--   不等 SnowMeta（客户端进服时 ReplicatedStorage 的东西是陆续到的，等不到就会摆得和服务器不一样：高度、视线都对不上）
local SDIM = {
  chalet_snow = { 26.685, 26.381, 22.4 }, chalet_alp = { 53.153, 48.944, 26.6 }, house_wood = { 32.817, 21.738, 23.8 },
  house_old = { 28.396, 20.07, 36.4 }, cabin_log = { 23.298, 23.374, 18.2 }, cabin_scan = { 25.962, 21.953, 16.8 }, barn_red = { 62.301, 37.19, 25.2 },
  barn_old = { 27.069, 16.332, 19.6 }, house_ab1 = { 34.27, 30.527, 26.6 }, house_ab2 = { 48.363, 32.422, 23.8 }, house_ww2 = { 29.656, 30.442, 28 },
  ruin_bld2 = { 42.491, 26.203, 42.028 }, ruin_bld = { 53.553, 46.539, 30.817 }, ruin_hall = { 58.817, 33.385, 42.07 },
  ruin_church = { 65.695, 41.275, 47.611 }, ruin_wood = { 25.594, 22.384, 21 }, ruin_house1 = { 51.337, 48.709, 18.2 },
  ruin_house2 = { 34.949, 28.826, 16.8 }, ruin_shell = { 27.235, 23.54, 19.6 }, ruin_house3 = { 53.554, 49.011, 18.2 }
}
-- 看不见的碰撞盒（World.building 的 coll：{ 中心 x、y、z, 大小 x、y、z }，都按模型的宽、高、深的几成）：废墟的碎渣撒得开，
--   只挡还立着的那一块（车能压到碎渣边上，炮弹从塌了的上半截飞过去）；寻路、视线按最大的那个盒子（Map.bldAt）
local SCOLL = {
  ruin_bld2 = { { 0, 0.4, 0, 0.9, 0.8, 0.85 } },
  ruin_bld = { { 0, 0.3, 0, 0.75, 0.6, 0.75 } },
  ruin_hall = { { 0, 0.4, 0, 0.85, 0.8, 0.85 } },
  ruin_church = { { 0, 0.35, 0, 0.85, 0.7, 0.85 } },
  ruin_wood = { { 0, 0.35, 0, 0.75, 0.7, 0.75 } },
  ruin_house1 = { { 0, 0.3, 0, 0.45, 0.6, 0.45 } },
  ruin_house2 = { { 0, 0.4, 0, 0.55, 0.8, 0.55 } },
  ruin_shell = { { 0, 0.4, 0, 0.9, 0.8, 0.9 } },
  ruin_house3 = { { 0, 0.4, 0, 0.45, 0.8, 0.45 } },
}
Map.SNOW_COLL = SCOLL
local function dims(key)
  local g = SDIM[key] or { 30, 30, 24 }
  return g[1], g[2], g[3]
end
-- 模型挑法：完好的民房、废墟、谷仓、小屋、大楼（村中心）
local POOL = {
  home = { "chalet_snow", "chalet_alp", "house_wood", "cabin_scan", "house_old", "house_ab1", "cabin_log", "house_ab2", "chalet_snow", "house_ww2" },
  ruin = { "ruin_wood", "ruin_house1", "ruin_house2", "ruin_shell", "ruin_house3", "ruin_bld" },
  barn = { "barn_red", "barn_old", "barn_red" },
  hut = { "cabin_log", "cabin_scan", "chalet_snow" },
  big = { "house_ww2", "house_old", "ruin_bld2", "ruin_hall" },
}
local function addB(x, z, w, d, h, k, sd)
  local b = { id = #BLD + 1, x = x, z = z, w = w, d = d, h = h, k = k, sd = sd or #BLD * 7 + 3, fl = max(1, floor(h / 11)) }
  table.insert(BLD, b)
  return b
end
-- 一座模型房子：转角 q × 90°（外接矩形不斜：碰撞、视线按轴对齐的矩形算）、缩放 s；返回登记好的那座
local function modelB(x, z, key, q, s, sd)
  local w, d, h = dims(key)
  -- 有自己的碰撞盒的（废墟）：登记的外接矩形按碰撞盒（寻路、视线、别的房子离它多远）
  local C = SCOLL[key]
  if C then
    local fx, fz, fy = 0, 0, 0
    for _, c in ipairs(C) do
      fx = max(fx, abs(c[1]) + c[4] / 2)
      fz = max(fz, abs(c[3]) + c[6] / 2)
      fy = max(fy, c[2] + c[5] / 2)
    end
    w, d, h = w * fx * 2, d * fz * 2, h * fy
  end
  q = q % 4
  if q % 2 == 1 then w, d = d, w end
  local b = addB(x, z, w * s, d * s, h * s, "model", sd)
  b.model, b.rot, b.scale = key, q * math.pi / 2, s
  b.ruin = string.sub(key, 1, 5) == "ruin_"
  return b
end
Map.modelDims = dims
-- 放得下吗：不压路、不压河、不压别的房子（留 gap 格）
local function freeAt(x, z, w, d, gap)
  if riverDist(x, z) < RIVER_W + RIVER_BANK + max(w, d) * 0.5 + 20 then return false end
  -- 山体模型脚下不摆（房子会埋进山里）：四个角、中间都还在谷底
  for _, o in ipairs({ { 0, 0 }, { -0.6, -0.6 }, { 0.6, -0.6 }, { -0.6, 0.6 }, { 0.6, 0.6 } }) do
    local p = peakH(x + o[1] * w, z + o[2] * d)
    if p and p > PLAIN + 2 then return false end
  end
  if onRoad(x, z, max(w, d) * 0.6 + 10) then return false end
  if lakeD(x, z) < 1.4 then return false end
  if inBase(x, z, 300) then return false end
  -- 坡太陡的不盖（脚下的平台挖填太多，看着像插在坡上）：四个角、中间的自然高度差不超过 10 格 + 边长的一成
  do
    local h0 = natH(x, z)
    local lo, hi = h0, h0
    for _, o in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } }) do
      local h = natH(x + o[1] * w, z + o[2] * d)
      if h < lo then lo = h end
      if h > hi then hi = h end
    end
    if hi - lo > 10 + 0.1 * max(w, d) then return false end
  end
  for _, b in ipairs(BLD) do
    if abs(b.x - x) < (b.w + w) / 2 + gap and abs(b.z - z) < (b.d + d) / 2 + gap then return false end
  end
  return true
end
do
  local R = rng(40517)
  local function pick(list) return list[1 + floor(R() * #list)] end
  -- 正面（−Z 转过的方向）朝着 (tx, tz)：挑最接近的 90° 档
  local function faceQ(x, z, tx, tz)
    local a = math.atan2(-(tx - x), -(tz - z))   -- 转 a 以后 −Z 朝向目标（Roblox：绕 Y 转 a，−Z → (−sin a, −cos a)）
    return floor((a / (math.pi / 2)) + 0.5) % 4
  end
  -- 试着在 (x, z) 附近摆一座 key：转角朝 (tx, tz)，按 s 缩放；摆不下返回 nil
  local function tryModel(x, z, key, s, tx, tz, gap)
    local q = faceQ(x, z, tx or 0, tz or 0)
    local w, d = dims(key)
    if q % 2 == 1 then w, d = d, w end
    if not freeAt(x, z, w * s, d * s, gap or 22) then return nil end
    return modelB(x, z, key, q, s)
  end
  -- 山村（C）：教堂废墟在广场北边，广场四周两三层的楼（有的炸塌了），往外沿路一圈圈散开的木屋
  modelB(30, -170, "ruin_church", 0, 1.25)                  -- 教堂（炸毁的：钟楼还立着半截）
  modelB(-170, 120, "house_ww2", 0, 1.15)                   -- 广场西南：客栈（石砌）
  modelB(175, 115, "ruin_bld2", 0, 1.0)                     -- 广场东南：被炸的四层楼（原来的旅馆）
  modelB(-185, -105, "house_old", 1, 1.1)
  modelB(190, -120, "ruin_hall", 1, 0.9)                    -- 镇公所（炸毁的会堂）
  modelB(-20, 230, "house_ab1", 2, 1.0)
  -- 用户 11-28「多搞一些房子」：山村再密一些（原来 40 户的名额）
  for i = 1, 64 do
    for _ = 1, 40 do
      local a = R() * math.pi * 2
      local r = 270 + R() * 620
      local x, z = cos(a) * r, sin(a) * r * 0.85
      local key = (R() < 0.36) and pick(POOL.ruin) or pick(POOL.home)
      if r > 700 and R() < 0.3 then key = pick(POOL.barn) end
      if tryModel(x, z, key, 0.95 + R() * 0.2, 0, 0, 24) then break end
    end
  end
  -- 几个小村落（谷里散着，每个四五户，有的炸了）：给坦克一路上的掩体、步兵的据守点
  --   11-28 多七个（南边主路旁、东边、雷达北丘下、山口前、东北、北门前、东南）
  for hi, c in ipairs({ { -2700, -2500 }, { 2500, 3700 }, { -2300, 4700 }, { 2300, -4600 }, { -3000, 1900 }, { 1500, -2200 },
    { -350, 4750 }, { 2950, 1650 }, { -1750, -950 }, { 450, -2750 }, { 2800, -3600 }, { -650, -5250 }, { 1350, 5500 } }) do
    local n = 4 + floor(R() * 4)
    for _ = 1, n do
      for _ = 1, 30 do
        local a, r = R() * math.pi * 2, 40 + R() * 260
        local x, z = c[1] + cos(a) * r, c[2] + sin(a) * r
        local key = (R() < 0.4) and pick(POOL.ruin) or ((R() < 0.25) and pick(POOL.barn) or pick(POOL.home))
        if valleyD(x, z) < 0.9 and tryModel(x, z, key, 0.95 + R() * 0.2, c[1], c[2], 20) then break end
      end
    end
  end
  -- 锯木厂（A）：大工棚（零件拼，木料堆 SnowBuild 摆）、旧木棚、办公小楼
  addB(P_A.x - 160, P_A.z - 40, 120, 60, 30, "mill")
  modelB(P_A.x + 150, P_A.z + 60, "barn_old", 1, 1.3)
  modelB(P_A.x + 150, P_A.z - 75, "barn_old", 1, 1.3)
  modelB(P_A.x - 30, P_A.z + 175, "cabin_scan", 2, 1.1)
  modelB(P_A.x + 40, P_A.z - 190, "ruin_shell", 0, 1.0)
  -- 雷达站（B）：营房、发电机房（雷达塔、天线 SnowBuild 另建）
  addB(P_B.x - 120, P_B.z + 60, 60, 26, 16, "hut")
  addB(P_B.x + 110, P_B.z + 90, 30, 24, 14, "hut")
  -- 水电站（D）：厂房在坝下游（西边）
  addB(P_D.x - 210, P_D.z + 40, 96, 52, 34, "plant")
  addB(P_D.x - 140, P_D.z - 120, 40, 30, 20, "hut")
  modelB(P_D.x - 330, P_D.z - 130, "ruin_house2", 0, 1.0)
  -- 山口检查站（E）：岗楼、营房
  addB(P_E.x - 120, P_E.z + 40, 56, 24, 16, "hut")
  addB(P_E.x + 120, P_E.z - 30, 40, 26, 18, "hut")
  modelB(P_E.x - 40, P_E.z + 210, "cabin_log", 0, 1.1)
  -- 车站（铁路站场 Map.RAIL_YARD 东边）：石砌的二层站房，正面朝着股道
  do
    local Y = Map.RAIL_YARD
    local cx, cz = (Y.ax + Y.bx) / 2 + 84, (Y.az + Y.bz) / 2 - 40
    local w, d = dims("house_ww2")
    if freeAt(cx, cz, d * 1.1, w * 1.1, 6) then Map.STATION = modelB(cx, cz, "house_ww2", 1, 1.1) end
  end
  -- 主路边一户户人家（用户 11-28「多搞一些房子」）：每四百多格一户，两边轮着，离路中线六七十格；有的炸了，有的边上一间棚子
  do
    local side = 1
    for _, sg in ipairs(SEGS) do
      if sg[6] == "main" then
        local ax, az, bx, bz = sg[1], sg[2], sg[3], sg[4]
        local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local ux, uz = (bx - ax) / L, (bz - az) / L
        for t = 150, L - 100, 430 do
          side = -side
          local off = 62 + R() * 30
          local x, z = ax + ux * t - uz * off * side, az + uz * t + ux * off * side
          local key = (R() < 0.3) and pick(POOL.ruin) or pick(POOL.home)
          local b = tryModel(x, z, key, 0.95 + R() * 0.15, ax + ux * t, az + uz * t, 18)
          if b and R() < 0.45 then tryModel(x + ux * 46, z + uz * 46, pick(POOL.hut), 0.9, ax + ux * t, az + uz * t, 10) end
        end
      end
    end
  end
  -- 路边零星的农庄：住房 + 谷仓（有的被炸了）；11-28 多八处
  for _, p in ipairs({ { -1900, 4200 }, { 1500, 4300 }, { 2100, 2700 }, { -2400, 2500 }, { -1500, -2700 }, { 1900, -2600 }, { -800, -4200 },
    { -3300, -800 }, { 3300, 900 }, { -900, 5600 }, { 800, -5600 },
    { 600, 4900 }, { -2900, 3300 }, { 1100, 1500 }, { 3200, -1900 }, { -2900, -1700 }, { 1700, -4000 }, { -1600, -4600 }, { 2400, 5300 } }) do
    local home = (R() < 0.3) and pick(POOL.ruin) or pick(POOL.home)
    if tryModel(p[1], p[2], home, 1.0, p[1] + 200, p[2], 20) then
      tryModel(p[1] + 70, p[2] + 24, pick(POOL.barn), 1.0, p[1], p[2], 16)
    end
  end
end
local BCELL = 128
local bgrid = {}
local function bkey(gx, gz) return (gx + 1024) * 4096 + (gz + 1024) end
for _, b in ipairs(BLD) do
  for gx = floor((b.x - b.w / 2 - 20) / BCELL), floor((b.x + b.w / 2 + 20) / BCELL) do
    for gz = floor((b.z - b.d / 2 - 20) / BCELL), floor((b.z + b.d / 2 + 20) / BCELL) do
      local key = bkey(gx, gz)
      local l = bgrid[key]
      if not l then l = {} bgrid[key] = l end
      table.insert(l, b)
    end
  end
end
Map.BLD_DOWN = {}
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
local civAtF = nil   -- 废弃的车（下面 Map.CIV 摆好以后才有）：寻路也绕开
function Map.navBlocked(x, z) return bldAt(x, z, 12) ~= nil or (civAtF ~= nil and civAtF(x, z, 6) ~= nil) end
function Map.segBlocked(ax, az, bx, bz, pad)
  local dx, dz = bx - ax, bz - az
  local L = sqrt(dx * dx + dz * dz)
  local n = max(1, floor(L / 10))
  for q = 0, n do
    local t = q / n
    if bldAt(ax + dx * t, az + dz * t, pad or 10) then return true end
    if civAtF and civAtF(ax + dx * t, az + dz * t, (pad or 10) * 0.5) then return true end
  end
  return false
end

---------------------------------------------------------------- 谷底（坦克交战区）的地形 = 自然地形（上面 natH）+ 路的挖填 + 房子脚下的平台 + 河槽 + 湖
--   路：路面高 = 顺着路把自然地形抹平（前后各约 110 格平均、坡不超过 15%、挖填不超过 20 格），路两边按高差挖成路堑、填成路堤（高差越大坡越宽）；
--   桥头两边路面落到河滩的高；岔路口跟主路一样高。房子：脚下一块平台（房子外 30 格以内和平台一样高，30～90 格接回坡）
---------------------------------------------------------------- 打过仗的痕迹（用户 11-27：「坦克视角近处是一大片空白雪地……没有一点打过仗的痕迹。
--   弹坑、战壕、沙袋、篱笆、电线杆、车辆残骸、木料堆都很少。你说的目的是代入感，这是现在最大的差距」）
--   · 弹坑、战壕挖进地形（坑底、壕沟露出泥土，Map.material 给 Ground：雪山图换成冬季树包的化雪泥地）：坦克开得过（壁坡 < 40°），步兵蹲在里面有掩护
--   · 沙袋、铁丝网、篱笆、电线杆、木料堆、干草垛、车辆残骸（真车模型烧黑）照 Map.PROPS 摆（SnowBuild.lua：服务器；残骸的样子 Client/SnowLook.lua）
local CRATERS, TRENCH = {}, {}
Map.CRATERS, Map.TRENCH = CRATERS, TRENCH
local CG, CGC = {}, 128
local function cgk(gx, gz) return (gx + 2048) * 4096 + gz + 2048 end
local function freeWar(x, z, r)
  if valleyD(x, z) > 0.95 or inBase(x, z, 250) then return false end
  if onRoad(x, z, r + 8) or bldAt(x, z, r + 12) then return false end
  if riverDist(x, z) < RIVER_W + RIVER_BANK + r + 10 then return false end
  if lakeD(x, z) < 1.5 then return false end
  local _, rock = featH(x, z)
  if rock then return false end
  return true
end
do
  local R = rng(55117)
  local function add(x, z, r)
    if not freeWar(x, z, r) then return end
    for gx = floor((x - r * 2) / CGC), floor((x + r * 2) / CGC) do
      for gz = floor((z - r * 2) / CGC), floor((z + r * 2) / CGC) do
        for _, c in ipairs(CG[cgk(gx, gz)] or {}) do
          if (c[1] - x) ^ 2 + (c[2] - z) ^ 2 < (c[3] + r + 3) ^ 2 then return end
        end
      end
    end
    local c = { x, z, r, r * 0.35 }
    table.insert(CRATERS, c)
    for gx = floor((x - r * 1.7) / CGC), floor((x + r * 1.7) / CGC) do
      for gz = floor((z - r * 1.7) / CGC), floor((z + r * 1.7) / CGC) do
        local k = cgk(gx, gz)
        CG[k] = CG[k] or {}
        table.insert(CG[k], c)
      end
    end
  end
  -- 用户 11-27「坦克视角近处是一大片空白雪地」：弹坑要多——坑多是小的（半径 4～15 格，小的多），据点四周、前沿梁顶、路边挨过炮的地方最密
  local function rr() return 4 + 11 * R() ^ 1.8 end
  -- 据点四周最密（反复争夺的地方）
  for _, pt in ipairs(Map.POINTS) do
    for _ = 1, 170 do
      local a, d = R() * math.pi * 2, 80 + R() * 650
      add(pt.x + cos(a) * d, pt.z + sin(a) * d, rr())
    end
  end
  -- 前沿的梁顶（炮火准备打过的地方）
  for _, F in ipairs(FEAT) do
    if F[1] == "ridge" and F[4] >= 26 then
      for _ = 1, 55 do
        local i = 1 + floor(R() * (#F[2] - 1))
        local a, b2, t = F[2][i], F[2][i + 1], R()
        add(a[1] + (b2[1] - a[1]) * t + (R() - 0.5) * 300, a[2] + (b2[2] - a[2]) * t + (R() - 0.5) * 300, rr())
      end
    end
  end
  -- 路边（车队挨过炮）
  for _ = 1, 420 do
    local sg = SEGS[1 + floor(R() * #SEGS)]
    local t = R()
    local L = sqrt((sg[3] - sg[1]) ^ 2 + (sg[4] - sg[2]) ^ 2)
    local side = (R() < 0.5) and 1 or -1
    local off = sg[5] / 2 + 14 + R() * 110
    add(sg[1] + (sg[3] - sg[1]) * t + (sg[4] - sg[2]) / L * side * off, sg[2] + (sg[4] - sg[2]) * t - (sg[3] - sg[1]) / L * side * off, rr())
  end
  -- 谷里零零散散
  for _ = 1, 1800 do add(-2900 + R() * 5800, -5600 + R() * 11200, rr()) end
end
-- 战壕：一条条之字形的壕（每 18 格拐一下，摆幅 8 格），过路的地方断开；front：胸墙（翻出来的土、沙袋）在折线左（+1）还是右（−1）
local function trench(ax, az, bx, bz, front)
  local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
  local ux, uz = (bx - ax) / L, (bz - az) / L
  local n = floor(L / 18)
  local cur = {}
  for q = 0, n do
    local t = q / n
    local off = (q % 4 == 1) and 8 or ((q % 4 == 3) and -8 or 0)
    local x, z = ax + (bx - ax) * t - uz * off, az + (bz - az) * t + ux * off
    if onRoad(x, z, 14) or bldAt(x, z, 10) or riverDist(x, z) < RIVER_W + RIVER_BANK + 10 then
      if #cur >= 3 then table.insert(TRENCH, { pts = cur, front = front }) end
      cur = {}
    else
      table.insert(cur, { x, z })
    end
  end
  if #cur >= 3 then table.insert(TRENCH, { pts = cur, front = front }) end
end
trench(-1560, 3560, -760, 3520, 1)      -- 锯木厂（A）南边：守方的壕，胸墙朝南
trench(-2400, 4300, -1760, 4240, -1)    -- 南梁上：攻方挖的，胸墙朝北
trench(-560, 420, -160, 560, 1)         -- 山村（C）西南
trench(260, -480, 700, -380, -1)        -- 山村东北
trench(-1820, 700, -1760, 1120, -1)     -- 雷达站台地东沿：胸墙朝东
trench(2080, -1180, 2120, -640, 1)      -- 坝下（D）西边：胸墙朝西
trench(-500, -2330, 200, -2260, 1)      -- 山口前梁：守方前沿，胸墙朝南
trench(480, -3080, 1340, -3140, 1)      -- 山口（E）前
for _, T2 in ipairs(TRENCH) do
  T2.acc = { 0 }
  local x0, z0, x1, z1 = 1e9, 1e9, -1e9, -1e9
  for i, q in ipairs(T2.pts) do
    if i > 1 then T2.acc[i] = T2.acc[i - 1] + sqrt((q[1] - T2.pts[i - 1][1]) ^ 2 + (q[2] - T2.pts[i - 1][2]) ^ 2) end
    x0, z0, x1, z1 = min(x0, q[1]), min(z0, q[2]), max(x1, q[1]), max(z1, q[2])
  end
  T2.box = { x0 - 20, z0 - 20, x1 + 20, z1 + 20 }
end
-- 这一点的弹坑 / 战壕：返回 地面要加多少、是不是露泥（坑底、壕里）
local function warAt(x, z)
  local dh, mud, soot = 0, false, false
  local l = CG[cgk(x // CGC, z // CGC)]
  if l then
    for _, c in ipairs(l) do
      local dx, dz = x - c[1], z - c[2]
      local d2 = dx * dx + dz * dz
      local r = c[3]
      if d2 < (r * 1.7) ^ 2 then
        local d = sqrt(d2)
        if d < r then
          dh -= c[4] * (1 - (d / r) ^ 2)
          if d < r * 0.85 then mud = true end
        end
        if d < r * 1.7 and d >= r * 0.85 and c[3] > 6 then soot = true end   -- 坑边一圈熏黑的雪
        local q = (d - r * 1.2) / (r * 0.5)
        if q > -1 and q < 1 then dh += r * 0.1 * (1 - q * q) ^ 2 end   -- 坑沿翻起来一圈
      end
    end
  end
  for _, T2 in ipairs(TRENCH) do
    local b = T2.box
    if x > b[1] and x < b[3] and z > b[2] and z < b[4] then
      local d, _, side = polyNear(T2.pts, T2.acc, x, z)
      if d < 7 then   -- 壕：底宽 3、口宽 14、深 4（坦克开得过，人蹲下去有掩护）
        dh -= 4 * (1 - smooth(1.5, 7, d))
        if d < 5 then mud = true end
      elseif side == T2.front and d < 15 then   -- 胸墙：翻出来的土
        local q = (d - 10.5) / 4.5
        dh += 2.4 * (1 - q * q)
      end
    end
  end
  return dh, mud, soot
end
Map.warAt = warAt
-- 履带辙（用户 11-27「坦克视角近处是一大片空白雪地」）：田野里七十来条坦克开过的辙——两道并排的泥雪印（各宽 3 格、相隔 9 格），
--   从基地门口、路边、据点出发，弯弯曲曲往对面去；只改地面材质（Map.material 给 Ground，雪山图上是冬季树包的化雪泥地），不占零件
local TRACKS, TG, TGC = {}, {}, 128
Map.TRACKS = TRACKS
do
  local R = rng(31337)
  local starts = {}
  for _, B in pairs(Map.BASES) do
    for k = -3, 3 do table.insert(starts, { B.x + k * 500, B.z - B.face * 1000, (B.side == "atk") and -1 or 1 }) end
  end
  for _, pt in ipairs(Map.POINTS) do
    for _ = 1, 4 do table.insert(starts, { pt.x + (R() - 0.5) * 500, pt.z + (R() - 0.5) * 500, (R() < 0.5) and 1 or -1 }) end
  end
  for _ = 1, 40 do table.insert(starts, { -2600 + R() * 5200, -5000 + R() * 10000, (R() < 0.5) and 1 or -1 }) end
  for _, st0 in ipairs(starts) do
    local x, z = st0[1], st0[2]
    local ang = (st0[3] < 0) and (-math.pi / 2) or (math.pi / 2)   -- 大致朝对面（−z 北 / +z 南）
    ang += (R() - 0.5) * 1.6
    local pts = {}
    local len = 500 + R() * 1700
    for _ = 0, len / 40 do
      if valleyD(x, z) > 0.93 or lakeD(x, z) < 1.25 or bldAt(x, z, 8) or inBase(x, z, 40) then
        if #pts >= 6 then break end
        pts = {}
      else
        table.insert(pts, { x, z })
      end
      ang += (R() - 0.5) * 0.4
      x += cos(ang) * 40
      z += sin(ang) * 40
    end
    if #pts >= 6 then
      table.insert(TRACKS, pts)
      for i = 1, #pts - 1 do
        local a, b2 = pts[i], pts[i + 1]
        for gx = floor((min(a[1], b2[1]) - 12) / TGC), floor((max(a[1], b2[1]) + 12) / TGC) do
          for gz = floor((min(a[2], b2[2]) - 12) / TGC), floor((max(a[2], b2[2]) + 12) / TGC) do
            local k = cgk(gx, gz)
            TG[k] = TG[k] or {}
            table.insert(TG[k], { a, b2 })
          end
        end
      end
    end
  end
end
local function onTrack(x, z)
  local l = TG[cgk(x // TGC, z // TGC)]
  if not l then return false end
  for _, sg in ipairs(l) do
    local a, b2 = sg[1], sg[2]
    local dx, dz = b2[1] - a[1], b2[2] - a[2]
    local t = clamp(((x - a[1]) * dx + (z - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
    local d = sqrt((a[1] + dx * t - x) ^ 2 + (a[2] + dz * t - z) ^ 2)
    -- 两道辙（体素 4 格一格：细的印子画不出来）——一条碾烂的泥雪带，边上东一块西一块
    if d < 6.5 and (d < 3.5 or noise(x / 9, z / 9, 3.3) > -0.15) then return true end
  end
  return false
end
Map.onTrack = onTrack
-- 摆的东西（SnowBuild.lua 照这张表摆）：
--   sandbag { x, z, yaw, len } 一段沙袋墙；wire { ax, az, bx, bz } 一道铁丝网；fence { ax, az, bx, bz, 断了几成 } 一段木篱笆；
--   pole { x, z, yaw, tilt } 电线杆（tilt：被打歪的）；wires { 杆 i, 杆 j } 两根杆之间的电线；logs { x, z, yaw, n } 木料堆；hay { x, z } 干草垛；
--   wreck { x, z, yaw, key 车型（ImportedMeta 的模型键）, tur 炮塔转角, tilt 歪斜, w, h, l 碰撞盒 }
local PROPS = { sandbag = {}, wire = {}, fence = {}, pole = {}, wires = {}, logs = {}, hay = {}, wreck = {} }
Map.PROPS = PROPS
do
  local R = rng(90211)
  -- 战壕：胸墙上一段段沙袋（射击位），壕前 30 格一道铁丝网
  for _, T2 in ipairs(TRENCH) do
    local pts = T2.pts
    local a, b2 = pts[1], pts[#pts]
    local L = sqrt((b2[1] - a[1]) ^ 2 + (b2[2] - a[2]) ^ 2)
    local ux, uz = (b2[1] - a[1]) / L, (b2[2] - a[2]) / L
    local nx, nz = -uz * T2.front, ux * T2.front   -- 朝胸墙那边
    local yaw = math.atan2(-ux, -uz) + math.pi / 2
    for t = 20, L - 20, 46 do
      if R() < 0.75 then
        table.insert(PROPS.sandbag, { a[1] + ux * t + nx * 9, a[2] + uz * t + nz * 9, yaw, 14 + R() * 8 })
      end
    end
    local wx0, wz0 = a[1] + nx * 34, a[2] + nz * 34
    local seg = 0
    while seg < L do
      local l2 = min(48, L - seg)
      if R() < 0.8 then
        table.insert(PROPS.wire, { wx0 + ux * seg, wz0 + uz * seg, wx0 + ux * (seg + l2), wz0 + uz * (seg + l2) })
      end
      seg += l2 + 6
    end
  end
  -- 车辆残骸：打过的仗留下的（照路线、据点前摆；挡在开阔地上就是掩体）
  local WK = {
    { -1300, 3950, 20, "t72b3" }, { -720, 4120, -30, "m60a3" }, { -1020, 3120, 70, "bmp2" }, { -280, 470, 110, "leo1" },
    { -330, 760, -60, "t64" }, { -1500, 1180, 15, "m1a1i" }, { -1700, 560, 160, "bmp2" }, { 1880, -820, 95, "leo2a6" },
    { 2230, -1330, 200, "hmmwv" }, { 690, -2700, 10, "t72b3" }, { 1170, -2640, -25, "m60a3" }, { 300, -3260, 140, "bmp1" },
    { 1500, 2620, 60, "jltv" }, { -2200, -2000, 35, "t64" }, { 2400, -2080, -70, "leo1" }, { 420, 2050, 15, "t72b3" },
    { -900, -1450, 120, "m2a3" }, { 1600, 1150, -100, "bmp1" },
  }
  for _, w in ipairs(WK) do
    local x, z = w[1], w[2]
    for _ = 1, 12 do   -- 压着路、房子、河就挪开一点
      if freeWar(x, z, 16) then break end
      x, z = x + (R() - 0.5) * 120, z + (R() - 0.5) * 120
    end
    if freeWar(x, z, 16) then
      table.insert(PROPS.wreck, { x, z, math.rad(w[3]), w[4], (R() - 0.5) * 2.4, (R() - 0.5) * 0.12 })
    end
  end
  -- 电线杆：主路一侧，每 70 格一根，杆和杆之间三根电线；据点附近的被打歪了、有的断了线
  local SEGS2 = {}
  for _, sg in ipairs(SEGS) do if sg[6] == "main" then table.insert(SEGS2, sg) end end
  local acc = 0
  for _, sg in ipairs(SEGS2) do
    local ax, az, bx, bz, w = sg[1], sg[2], sg[3], sg[4], sg[5]
    local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local ux, uz = (bx - ax) / L, (bz - az) / L
    local t = (70 - acc % 70) % 70
    while t < L do
      local x, z = ax + ux * t + uz * (w / 2 + 14), az + uz * t - ux * (w / 2 + 14)
      if not inBase(x, z, 60) and riverDist(x, z) > RIVER_W + RIVER_BANK + 6 and not bldAt(x, z, 6) then
        local nearP = false
        for _, pt in ipairs(Map.POINTS) do if (pt.x - x) ^ 2 + (pt.z - z) ^ 2 < 700 * 700 then nearP = true end end
        local tilt = (nearP and R() < 0.35) and (0.12 + R() * 0.35) or 0
        table.insert(PROPS.pole, { x, z, math.atan2(-ux, -uz), tilt })
        local i = #PROPS.pole
        if i > 1 and tilt == 0 and PROPS.pole[i - 1][4] == 0 then
          local q = PROPS.pole[i - 1]
          if (q[1] - x) ^ 2 + (q[2] - z) ^ 2 < 90 * 90 then table.insert(PROPS.wires, { i - 1, i }) end
        end
      end
      t += 70
    end
    acc += L
  end
  -- 农庄：一圈木篱笆（有的地方倒了、断了）、木料堆、干草垛
  for _, b in ipairs(BLD) do
    if b.model and string.sub(b.model, 1, 5) == "barn_" then
      local cx, cz = b.x - 35, b.z - 10
      local hw, hd = 110 + R() * 30, 80 + R() * 20
      local cs = { { cx - hw, cz - hd }, { cx + hw, cz - hd }, { cx + hw, cz + hd }, { cx - hw, cz + hd }, { cx - hw, cz - hd } }
      for i = 1, 4 do
        local a, b2 = cs[i], cs[i + 1]
        local L = sqrt((b2[1] - a[1]) ^ 2 + (b2[2] - a[2]) ^ 2)
        for t = 0, L - 20, 20 do
          local x0, z0 = a[1] + (b2[1] - a[1]) * t / L, a[2] + (b2[2] - a[2]) * t / L
          local x1, z1 = a[1] + (b2[1] - a[1]) * (t + 20) / L, a[2] + (b2[2] - a[2]) * (t + 20) / L
          if not onRoad((x0 + x1) / 2, (z0 + z1) / 2, 6) and not bldAt((x0 + x1) / 2, (z0 + z1) / 2, 4) and R() < 0.82 then
            table.insert(PROPS.fence, { x0, z0, x1, z1, (R() < 0.15) and 1 or 0 })
          end
        end
      end
      for _ = 1, 3 do
        local x, z = cx + (R() - 0.5) * hw * 1.4, cz + (R() - 0.5) * hd * 1.4
        if not bldAt(x, z, 10) and not onRoad(x, z, 8) then
          if R() < 0.5 then table.insert(PROPS.logs, { x, z, R() * math.pi, 3 + floor(R() * 3) })
          else table.insert(PROPS.hay, { x, z }) end
        end
      end
    end
  end
  -- 田边的篱笆：顺着路、离路三四十格，一段段（有的倒了）——田野有了边界，近处不是一片空白
  for _, sg in ipairs(SEGS) do
    local ax, az, bx, bz, w = sg[1], sg[2], sg[3], sg[4], sg[5]
    local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local ux, uz = (bx - ax) / L, (bz - az) / L
    for t = 0, L - 200, 200 do
      if R() < 0.45 then
        local side = (R() < 0.5) and 1 or -1
        local off = w / 2 + 28 + R() * 14
        local run = 80 + R() * 110
        for q = 0, run - 20, 20 do
          local x0, z0 = ax + ux * (t + q) - uz * side * off, az + uz * (t + q) + ux * side * off
          local x1, z1 = x0 + ux * 20, z0 + uz * 20
          local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
          if not inBase(mx, mz, 80) and not bldAt(mx, mz, 6) and not onRoad(mx, mz, 8) and riverDist(mx, mz) > RIVER_W + RIVER_BANK + 8 and R() < 0.85 then
            table.insert(PROPS.fence, { x0, z0, x1, z1, (R() < 0.12) and 1 or 0 })
          end
        end
      end
    end
  end
  -- 路边零散的木料堆（运木头的路：锯木厂一带最多）
  for _ = 1, 40 do
    local sg = SEGS[1 + floor(R() * #SEGS)]
    local t = R()
    local ax, az, bx, bz, w = sg[1], sg[2], sg[3], sg[4], sg[5]
    local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local side = (R() < 0.5) and 1 or -1
    local x = ax + (bx - ax) * t + (bz - az) / L * side * (w / 2 + 12)
    local z = az + (bz - az) * t - (bx - ax) / L * side * (w / 2 + 12)
    if not inBase(x, z, 200) and not bldAt(x, z, 10) and riverDist(x, z) > 200 then
      table.insert(PROPS.logs, { x, z, math.atan2(-(bx - ax), -(bz - az)) + math.pi / 2, 2 + floor(R() * 3) })
    end
  end
end

---------------------------------------------------------------- 废弃的车（用户 11-28「多搞一些房子 废弃的各种车等等让这个地图丰富起来」）
--   Map.CIV：民用车、卡车、客车、拖拉机、铁路车皮、机车、飞机残骸（models/bld/wrecks.glb 的 wk_*，WreckMeta；SnowBuild.lua 盖：
--   导入了摆原模型 + 看不见的碰撞盒，没导入按同样的大小用零件拼一辆）——{ x, z, a 车身长边（模型 X 轴）朝哪（弧度）, k 模型键, r 侧翻角, p 前后倾, s 缩放, y 抬高 }
--   Map.PROPS.wreck 加几簇打坏的军车（真车模型烧黑，客户端 SnowLook.lua 画）：车队挨了伏击、坦克坟场、防空阵地
local CIV = {}
Map.CIV = CIV
local CIVD = {   -- 各模型的长（X）、宽（Z）、高（格；照 WreckMeta 抄的：摆法服务器、客户端要算得一样，不等 WreckMeta）
  wk_bmw = { 12.12, 4.93, 3.63 }, wk_fiat = { 12.29, 4.71, 3.68 }, wk_hatch = { 10.92, 5.59, 3.71 }, wk_suv = { 12.88, 8.67, 4.93 },
  wk_uaz = { 11.28, 4.99, 5.88 }, wk_gaz66 = { 15.85, 6.25, 7.13 }, wk_ural = { 20.64, 8.34, 8.93 }, wk_kamaz = { 21.28, 8.81, 10.07 },
  wk_bus = { 29.4, 9.25, 9.78 }, wk_tractor = { 11.0, 4.89, 6.92 }, wk_boxcar = { 49.66, 12.15, 11.76 }, wk_hopper = { 39.8, 10.52, 10.36 },
  wk_loco = { 49.14, 9.23, 13.52 }, wk_plane = { 33.37, 9.33, 8.16 },
}
Map.CIV_DIMS = CIVD
local CG2, CG2C = {}, 64
local function civKey(gx, gz) return (gx + 4096) * 8192 + gz + 4096 end
local function civAt(x, z, pad)
  local l = CG2[civKey(x // CG2C, z // CG2C)]
  if not l then return nil end
  pad = pad or 0
  for _, c in ipairs(l) do
    local dx, dz = x - c.x, z - c.z
    local along = dx * c.ux + dz * c.uz
    local side = -dx * c.uz + dz * c.ux
    if abs(along) <= c.hl + pad and abs(side) <= c.hw + pad then return c end
  end
  return nil
end
Map.civAt = civAt
civAtF = civAt
local function addCiv(x, z, a, k, o)
  local D = CIVD[k]
  if not D then return nil end
  o = o or {}
  local sc = o.s or 1
  local c = { x = x, z = z, a = a, k = k, r = o.r or 0, p = o.p or 0, s = sc, y = o.y or 0, ux = cos(a), uz = -sin(a), hl = D[1] * sc / 2, hw = D[2] * sc / 2 }
  if abs(c.r) > 0.6 then c.hw = max(c.hw, D[3] * sc / 2) end   -- 侧翻的：车顶着地，宽按车高算
  c.id = #CIV + 1
  table.insert(CIV, c)
  local R0 = c.hl + c.hw
  for gx = floor((x - R0) / CG2C), floor((x + R0) / CG2C) do
    for gz = floor((z - R0) / CG2C), floor((z + R0) / CG2C) do
      local key = civKey(gx, gz)
      CG2[key] = CG2[key] or {}
      table.insert(CG2[key], c)
    end
  end
  return c
end
-- 放得下吗：不压房子、别的车、河、湖、基地；onRail 给 true 的是铁路车皮（本来就在轨上）
local function civFree(x, z, k, a, onRail)
  local D = CIVD[k]
  local r = max(D[1], D[2]) * 0.5
  if valleyD(x, z) > 0.95 or inBase(x, z, 120) then return false end
  if bldAt(x, z, r * 0.7 + 4) then return false end
  if civAt(x, z, r * 0.7 + 3) then return false end
  if riverDist(x, z) < RIVER_W + RIVER_BANK + r then return false end
  if lakeD(x, z) < 1.35 then return false end
  if not onRail then
    local d, _, w, rk = roadNear(x, z)
    if d and d < w * 0.5 + 2 + D[2] * 0.5 and (rk == "rail" or rk == "yard") then return false end
    -- 公路：车身中心不落在路面上（歪在路边可以，车尾压一点路肩也行；挪一挪再试的时候原来会挪到路中间去）
    if d and d < w * 0.5 + 1 and rk ~= "rail" and rk ~= "yard" then return false end
  end
  local _, rock = featH(x, z)
  if rock then return false end
  return true
end
Map.civFree = civFree
do
  local R = rng(66071)
  local function pick(list) return list[1 + floor(R() * #list)] end
  local CARS = { "wk_bmw", "wk_fiat", "wk_hatch", "wk_suv", "wk_uaz", "wk_bmw", "wk_fiat" }
  local TRUCKS = { "wk_ural", "wk_kamaz", "wk_gaz66", "wk_uaz", "wk_ural" }
  local function along(sg, t, off)   -- 路段 sg 上 t（0～1）处、往右偏 off 格的点，和路的方向角（模型 X 轴顺着路）
    local ax, az, bx, bz = sg[1], sg[2], sg[3], sg[4]
    local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local ux, uz = (bx - ax) / L, (bz - az) / L
    return ax + (bx - ax) * t - uz * off, az + (bz - az) * t + ux * off, math.atan2(-uz, ux), L
  end
  local function tryAdd(x, z, a, k, o, onRail)
    for _ = 1, 6 do
      if civFree(x, z, k, a, onRail) then return addCiv(x, z, a, k, o) end
      if onRail then return nil end
      x, z = x + (R() - 0.5) * 26, z + (R() - 0.5) * 26
    end
    return nil
  end
  -- ① 铁路站场：三股道上停着没人管的车皮（西股棚车、东股煤斗车），正线上一台 М62 机车拖着两节棚车；有一节出了轨、歪在路基边上
  do
    local Y = Map.RAIL_YARD
    local dx, dz = Y.bx - Y.ax, Y.bz - Y.az
    local L = sqrt(dx * dx + dz * dz)
    local ux, uz = dx / L, dz / L
    local a = math.atan2(-uz, ux)
    local function onTrack(off, m, k, o)
      local x, z = Y.ax + ux * m - uz * off, Y.az + uz * m + ux * off
      return tryAdd(x, z, a, k, o, true)
    end
    for i = 0, 3 do onTrack(Y.tracks[1], 90 + i * 53, "wk_boxcar") end
    for i = 0, 3 do onTrack(Y.tracks[3], 150 + i * 43, "wk_hopper") end
    onTrack(Y.tracks[2], 330, "wk_loco")
    onTrack(Y.tracks[2], 385, "wk_boxcar")
    onTrack(Y.tracks[2], 438, "wk_boxcar", { r = 0.22, p = 0.03 })   -- 一头掉下轨道，歪着
    -- 站台边：一辆客车、两辆小车（来接站的，扔下了）
    local sx, sz = (Y.ax + Y.bx) / 2 + 54, (Y.az + Y.bz) / 2 + 60
    tryAdd(sx, sz, a, "wk_bus")
    tryAdd(sx + 18, sz - 70, a + 0.4, pick(CARS))
    tryAdd(sx + 22, sz + 60, a - 0.3, pick(CARS))
  end
  -- ② 铁路正线：防雪棚口外一节翻倒的棚车、一节侧翻的煤斗车（出轨甩下路堤），路堤边几节被炸坏的车皮
  for gi, Gq in ipairs(Map.GALLERIES) do
    local m = (gi % 2 == 1) and (Gq.m0 - 70) or (Gq.m1 + 70)
    local x, z, ux, uz = polyPoint(Gq.P, clamp(m, 0, Gq.P.L))
    local nx, nz = -uz, ux
    tryAdd(x + nx * 26, z + nz * 26, math.atan2(-uz, ux) + 0.35, (gi == 1) and "wk_boxcar" or "wk_hopper", { r = 1.45, y = -1.5 })
  end
  for _, P in ipairs(POLYS) do
    if P.k == "rail" then
      for m = 600, P.L - 600, 1900 do
        local x, z, ux, uz = polyPoint(P, m)
        local side = (R() < 0.5) and 1 or -1
        tryAdd(x - uz * side * 22, z + ux * side * 22, math.atan2(-uz, ux) + (R() - 0.5) * 0.5, (R() < 0.5) and "wk_boxcar" or "wk_hopper", { r = side * (0.25 + R() * 0.3), y = -1 })
      end
    end
  end
  -- ③ 山村：街上、房前扔下的小车（有的烧了），广场边一辆客车（车站那辆之外）
  for _ = 1, 26 do
    local sg = SEGS[1 + floor(R() * #SEGS)]
    if sg[6] ~= "rail" and sg[6] ~= "yard" then
      local t = R()
      local x, z, a = along(sg, t, (R() < 0.5 and -1 or 1) * (sg[5] * 0.5 + 6 + R() * 8))
      if x * x + z * z < 950 * 950 then tryAdd(x, z, a + (R() - 0.5) * 0.4, pick(CARS)) end
    end
  end
  tryAdd(-172, 352, 1.21, "wk_bus")   -- 主路西边的路肩上（顺着路；原来 (-150, 360) 正压在主路中线边上）
  -- ④ 主路上被伏击的车队：两队卡车 / 吉普（山村—山口之间、锯木厂—山村之间），一辆接一辆歪在路边；车队前后的军车残骸在 PROPS.wreck 里
  local convoys = { { "main", 0.37, 5 }, { "main", 0.68, 6 }, { "main", 0.16, 4 } }
  for _, cv in ipairs(convoys) do
    local P = nil
    for _, Q in ipairs(POLYS) do if Q.k == cv[1] then P = Q break end end
    if P then
      local m0 = P.L * cv[2]
      for i = 0, cv[3] - 1 do
        local x, z, ux, uz = polyPoint(P, m0 + i * 34)
        local side = (i % 2 == 0) and 1 or -1
        local off = 22 + R() * 8
        tryAdd(x - uz * side * off, z + ux * side * off, math.atan2(-uz, ux) + side * (0.15 + R() * 0.35), pick(TRUCKS), { r = (R() < 0.2) and side * 0.35 or 0 })
      end
    end
  end
  -- ⑤ 农庄：谷仓边一台拖拉机（有的翻在沟里），院子里一辆旧车
  for _, b in ipairs(BLD) do
    if b.model and string.sub(b.model, 1, 5) == "barn_" and R() < 0.75 then
      tryAdd(b.x + b.w * 0.5 + 16, b.z + (R() - 0.5) * b.d, R() * math.pi * 2, "wk_tractor", { r = (R() < 0.15) and 0.4 or 0 })
      if R() < 0.5 then tryAdd(b.x - b.w * 0.5 - 18, b.z + (R() - 0.5) * b.d, R() * math.pi * 2, pick(CARS)) end
    end
  end
  -- ⑥ 小村落、路边人家门口：一两辆车
  for _, b in ipairs(BLD) do
    if b.model and not b.ruin and string.sub(b.model, 1, 5) ~= "barn_" and (b.x * b.x + b.z * b.z) > 950 * 950 and R() < 0.35 then
      local a = R() * math.pi * 2
      tryAdd(b.x + cos(a) * (b.w * 0.5 + 16), b.z + sin(a) * (b.d * 0.5 + 16), R() * math.pi * 2, pick(CARS))
    end
  end
  -- ⑦ 田野里零星的：开到半路扔下的卡车、陷在雪里的吉普（坦克的小掩体）
  for _ = 1, 30 do
    local x, z = -2700 + R() * 5400, -5400 + R() * 10800
    tryAdd(x, z, R() * math.pi * 2, (R() < 0.5) and pick(TRUCKS) or pick(CARS), { r = (R() < 0.15) and (R() - 0.5) * 1.2 or 0, y = -0.8 })
  end
  -- ⑧ 坠毁的飞机：东北丘的半坡上（机头朝下扎进雪里），雷达北丘的林子边
  tryAdd(2420, -2560, 0.6, "wk_plane", { p = -0.14, r = 0.12, y = -1.4 })
end

-- 军车残骸再加几簇（Map.PROPS.wreck，样子是客户端画的真车模型烧黑）：车队挨伏击（山村—山口的主路边）、坦克坟场（南梁前）、
--   山口前的防空阵地、水电站坝下的一排、雷达站台地下
do
  local R = rng(41593)
  local W2 = PROPS.wreck
  local function cluster(cx, cz, rad, keys)
    for _, k in ipairs(keys) do
      for _ = 1, 14 do
        local a, d = R() * math.pi * 2, R() * rad
        local x, z = cx + cos(a) * d, cz + sin(a) * d
        if freeWar(x, z, 16) and not civAt(x, z, 14) then
          local dup = false
          for _, w in ipairs(W2) do if (w[1] - x) ^ 2 + (w[2] - z) ^ 2 < 30 * 30 then dup = true break end end
          if not dup then
            table.insert(W2, { x, z, R() * math.pi * 2, k, (R() - 0.5) * 2.4, (R() - 0.5) * 0.14 })
            break
          end
        end
      end
    end
  end
  cluster(-1500, 4050, 380, { "m60a3", "leo1", "t64", "t72b3", "type59", "m60a3", "t64" })      -- 南梁前的坦克坟场
  cluster(420, -1250, 300, { "bmp1", "brdm2", "bmp2", "t72b3" })                                 -- 山村—山口的主路边（卡车车队的前后）
  cluster(-620, 2650, 280, { "m2a3", "hmmwv", "jltv", "m1a1i" })                                  -- 锯木厂—山村
  cluster(900, -2950, 320, { "pantsir", "strela1", "t90m", "bmp2", "m109" })                     -- 山口前的阵地
  cluster(1700, -800, 260, { "gepard", "m163", "leo2a6", "type74" })                             -- 水电站坝下
  cluster(-1700, 1350, 260, { "t80u", "brdm2", "bmp1" })                                         -- 雷达站台地下
  cluster(-200, -3900, 300, { "ztz96", "type59", "t64" })                                         -- 北门前
  cluster(1900, 3600, 320, { "leo1", "m60a3", "m551", "type87rcv" })                             -- 东南
end

Map.flatK = function(x, z) return baseK(x, z) end
-- 交战区的崎岖（用户 11-28「对抗的时候 地形不能是平的要多有不大不小的崎岖」，照战雷的图）：自然地形上再叠两层起伏——
--   · 冰碛丘：谷底一个个土包（高 2～4 米、直径四五十米，冰川退下去留下的那种），一簇一簇、中间夹着平一点的洼地：坦克一路上到处有车体隐蔽的位置
--   · 小坎：一米多的起伏（加上零点几米的碎坎），近处不是一块平板
--   路、铁路两边、河岸、湖岸、基地照旧平整（越靠近越收），山村中心、据点中心收一半（还看得见彼此）；房子脚下的平台、弹坑、战壕在后面照旧盖上去
local POINTS_C = Map.POINTS
local function roughH(x, z, rdist, rw, bk)
  local vd = valleyD(x, z)
  if vd > 1.0 then return 0 end
  local k = (1 - smooth(0.9, 1.0, vd)) * (1 - bk)
  if rdist then k *= smooth(rw * 0.5 + 8, rw * 0.5 + 64, rdist) end
  if k <= 0.001 then return 0 end
  local rv = riverDist(x, z)
  if rv < RIVER_W + RIVER_BANK + 90 then k *= smooth(RIVER_W + RIVER_BANK + 10, RIVER_W + RIVER_BANK + 90, rv) end
  if x > LAKE.damX - 900 then
    local ld = lakeD(x, z)
    if ld < 1.9 then k *= smooth(1.3, 1.9, ld) end
  end
  local dc = x * x + z * z
  if dc < 420 * 420 then k *= 0.45 + 0.55 * smooth(180, 420, sqrt(dc)) end
  for _, pt in ipairs(POINTS_C) do
    local dx, dz = x - pt.x, z - pt.z
    local d2 = dx * dx + dz * dz
    if d2 < 160 * 160 then k *= 0.55 + 0.45 * smooth(60, 160, sqrt(d2)) end
  end
  if k <= 0.001 then return 0 end
  local wx = x + 70 * noise(x / 330, z / 330, 71.3)
  local wz = z + 70 * noise(x / 330 + 9.1, z / 330, 33.7)
  local mound = smooth(-0.05, 0.6, noise(wx / 115, wz / 115, 41.7))
  local knoll = smooth(0.05, 0.65, noise(wx / 54, wz / 54, 19.3))
  return k * (12 * mound + 4.5 * knoll + 1.8 * noise(x / 23, z / 23, 7.7) - 5.5)
end
Map.roughH = function(x, z)
  local d, _, w = roadNear(x, z)
  return roughH(x, z, d, w or 0, baseK(x, z))
end
local function floorH(x, z)
  local h = natH(x, z)
  local bk = baseK(x, z)
  if bk >= 1 then return h end
  -- 路
  local d, ry, w = roadNear(x, z)
  h += roughH(x, z, d, w or 0, bk)
  if d then
    local hw = w * 0.5 + 3
    if d <= hw then
      h = ry
    else
      local S = 14 + 1.15 * abs(h - ry)
      if d < hw + S then h = lerp(ry, h, smooth(hw, hw + S, d)) end
    end
  end
  -- 房子脚下的平台
  local bp = bldAt(x, z, 90)
  if bp then
    if not bp.pad then
      local s, n = natH(bp.x, bp.z), 1
      for _, o in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } }) do
        s += natH(bp.x + o[1] * bp.w, bp.z + o[2] * bp.d)
        n += 1
      end
      bp.pad = s / n
    end
    local dx, dz = max(abs(x - bp.x) - bp.w / 2, 0), max(abs(z - bp.z) - bp.d / 2, 0)
    h = lerp(bp.pad, h, smooth(30, 90, sqrt(dx * dx + dz * dz)))
  end
  -- 弹坑、战壕
  local dw = warAt(x, z)
  if dw ~= 0 then h += dw end
  -- 河：冰面低 RIVER_D 格，两边缓坡（接到河滩上）；到了海边就是入海口（自然地形低过谷底的地方不再挖河槽）
  local rd = riverDist(x, z)
  if rd < RIVER_W + RIVER_BANK and h > PLAIN - 9 then
    local ice = PLAIN - RIVER_D
    if rd <= RIVER_W then return ice end
    h = lerp(ice, h, smooth(RIVER_W, RIVER_W + RIVER_BANK, rd))
  end
  return h
end
Map.floorH = floorH
local function heightAt(x, z)
  local h = floorH(x, z)
  local p = peakH(x, z)
  if p and p > h then return p end
  return h
end
function Map.height(x, z) return heightAt(x, z), 1e9 end
function Map.ground(x, z) return heightAt(x, z) end
-- 据点的高度（同沙海、钢城都有 p.y）：原来雪山没写——服务器数圈里的人（Round.countIn、Ents.countAt）、客户端判断「在不在点里」
--   （Operation.lua）都拿 p.y 比高度，nil 一减就报错（开坦克时每帧一次，屏幕上方红字常亮）。据点都在谷底，按谷底高（不查山体，开局不去载山的高度图）
for _, p in ipairs(Map.POINTS) do p.y = floorH(p.x, p.z) end
-- 写一块地形时（World.lua writeChunk 前后 Map.colCache(true / false)）：每一列的谷底高、山体高只算一次（定高度、定材质、判断壳都要）
local CCF, CCP = nil, nil
local function colInfo(x, z)
  if CCF then
    local key = (x + 65536) * 262144 + (z + 65536)
    local f = CCF[key]
    if f then return f, CCP[key] end
    local fh, ph = floorH(x, z), peakH(x, z) or false
    CCF[key], CCP[key] = fh, ph
    return fh, ph
  end
  return floorH(x, z), peakH(x, z) or false
end
function Map.colCache(on)
  if on then
    CCF, CCP = CCF or {}, CCP or {}
  else
    if CCF then table.clear(CCF) table.clear(CCP) end
    CCF, CCP = nil, nil
  end
end
-- 写体素用的高（World.lua writeChunk）：山体模型底下的体素比模型表面低 4 格（不从模型表面穿出来；坦克压在体素上，看着车轮陷进山脚一点）
function Map.voxelHeight(x, z)
  local h, p = colInfo(x, z)
  if p and p - 4 > h then return p - 4 end
  return h
end
-- 这一列写成壳（World.lua writeChunk：只写地面往下一层，底下空着）：山体模型盖着的、比谷底平地高 60 格以上的山脚
function Map.shellCol(x, z, h)
  if h < PLAIN + 60 then return false end
  local fh, p = colInfo(x, z)
  return p ~= false and p - 4 > fh + 8
end
function Map.isLand(x, z)
  if x == nil then return true end
  return heightAt(x, z) > 0.3
end
function Map.slope(x, z)
  local e = 4
  local a, b = heightAt(x + e, z), heightAt(x - e, z)
  local c, d = heightAt(x, z + e), heightAt(x, z - e)
  return sqrt(((a - b) / (2 * e)) ^ 2 + ((c - d) / (2 * e)) ^ 2)
end
function Map.flatW(x, z) return inBase(x, z, 0) and 1 or 0 end
Map.FLAT = {}
-- 冰面上（河、湖）：坦克开上去滑一点（以后可以用；现在只给材质、脚步声）
function Map.onIce(x, z) return riverDist(x, z) <= RIVER_W or inLake(x, z) end

---------------------------------------------------------------- 材质

function Map.material(x, z, y, slope)
  slope = slope or 0
  if inBase(x, z, 120) then return MAT.Snow end
  local rd = riverDist(x, z)
  if rd <= RIVER_W then return MAT.Glacier end
  if inLake(x, z) then return MAT.Glacier end
  local on, rk0 = onRoad(x, z, 0)
  if on then   -- 路（压实的土）；铁路的路基是碎石道砟（Slate）
    if rk0 == "rail" or rk0 == "yard" then return MAT.Slate end
    return MAT.Ground
  end
  -- 摆的岩石（硬掩体）、弹坑和战壕里露出来的泥
  local _, rk = featH(x, z)
  if rk then return (noise(x / 40, z / 40, 2.9) > -0.2) and MAT.Rock or MAT.Slate end
  local _, mud, soot = warAt(x, z)
  if mud then return MAT.Ground end
  if soot then return MAT.Slate end
  if onTrack(x, z) then return MAT.Ground end
  -- 山体模型底下（谷边的山脚）：体素藏在模型下面，偶尔从缝里露出来也是雪
  local fh, p = colInfo(x, z)
  if p and p - 4 > fh then return MAT.Snow end
  -- 谷底：陡的岩石包、冲沟两壁露出岩石（越陡越深）；风吹光的梁顶一点碎石
  if slope > 1.35 then return MAT.Slate end
  if slope > 0.8 then return (noise(x / 70, z / 70, 1.9) > -0.3) and MAT.Rock or MAT.Slate end
  if slope > 0.55 and noise(x / 120, z / 120, 3.7) > 0.25 then return MAT.Rock end
  -- 海边：黑沙滩（冰岛那样）、礁石；水下的海底
  if y < PLAIN - 4 then return (slope > 0.6) and MAT.Slate or MAT.Sand end
  -- 河岸、湖岸：一圈石头滩
  if rd < RIVER_W + 16 or (x > LAKE.damX and lakeD(x, z) < 1.03) then return MAT.Slate end
  return MAT.Snow
end
function Map.underMat(top)
  if top == MAT.Glacier then return MAT.Glacier end
  if top == MAT.Rock or top == MAT.Slate or top == MAT.Basalt then return MAT.Rock end
  return MAT.Snow
end
function Map.farSeaOk() return false end

---------------------------------------------------------------- 写地形（World.lua 用）
--   体素地形铺 ±12288 见方（客户端那圈远处平地在这片里沉下去）：
--   · 谷和谷边（COLL：x ±6144）按真高度写——谷底崎岖的地形、谷边山体模型脚下的一层壳（坦克、步兵的碰撞；比模型表面低 4 格，藏在模型下面）
--   · 再往外只铺一层平地（FillBlock，便宜）垫在山体模型底下：那里只有飞机，撞山按 Map.height（山体高度图）算
local CH = 256
Map.COLL = { x0 = -6144, x1 = 6144, z0 = -13312, z1 = 13312 }   -- 岛（谷、两侧山脊、海岸、近岸的海底）都在这里面
local function inColl(x0, z0)
  local C = Map.COLL
  return x0 + CH > C.x0 and x0 < C.x1 and z0 + CH > C.z0 and z0 < C.z1
end
-- 一块 256 × 256 格：9 × 9 个点高度都是平地、材质都是雪就是 "flat"（一次 FillBlock），别的逐列写
--   岛外的海：整块都是外海海底（-SEA_FLOOR）的按平的海铺（"flat"、水面 0、Water：World.lua 铺玄武岩海底 + 海水）
function Map.chunkKind(x0, z0)
  if not inColl(x0, z0) then return "flat", 0, MAT.Water end
  local step = CH / 8
  local sea, land = true, true
  for i = 0, 8 do
    for k = 0, 8 do
      local x, z = x0 + i * step, z0 + k * step
      local h = Map.voxelHeight(x, z)
      if h > -Map.SEA_FLOOR + 0.01 then sea = false end
      if abs(h - PLAIN) > 0.01 or Map.material(x, z, PLAIN, 0) ~= MAT.Snow then land = false end
      if not sea and not land then return "relief" end
    end
  end
  if sea then return "flat", 0, MAT.Water end
  return "flat", PLAIN, MAT.Snow
end
-- 这一块（256 格见方）有山体模型脚下的壳（World.lua 拆成 16 × 16 列一份写）：四个角、中间有一处山体高过平地 80 格
function Map.hollowAt(x0, z0)
  for _, o in ipairs({ { 0.5, 0.5 }, { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local p = peakH(x0 + o[1] * CH, z0 + o[2] * CH)
    if p and p > PLAIN + 80 then return true end
  end
  return false
end
-- 开服先写两边基地一带，再据点、谷底；谷边的山脚在后台
Map.CORE = { x = 0, z = 0, r = 4000 }
Map.CORES = {}
-- 开服前只写到基地外 1800 格（基地本身是平地，一次 FillBlock）：谷里的起伏块在后台按人、车在哪先写（沙海那会儿嫌开服慢）
for _, B in pairs(Map.BASES) do table.insert(Map.CORES, { x = (B.rect.x0 + B.rect.x1) / 2, z = (B.rect.z0 + B.rect.z1) / 2, r = 1800 }) end
Map.HOTS = {}
for _, c in ipairs(Map.CORES) do table.insert(Map.HOTS, c) end
for _, p in ipairs(Map.POINTS) do table.insert(Map.HOTS, { x = p.x, z = p.z, r = 900 }) end
table.insert(Map.HOTS, { x = 0, z = 0, r = 4200 })
function Map.landBoxes() return { { -12288, -12288, 12288, 12288 } } end
Map.UIBOX = { x0 = -5200, z0 = -9200, x1 = 5200, z1 = 9200 }
Map.NAVBOX = { x0 = -4608, z0 = -8448, x1 = 4608, z1 = 8448 }
Map.NAVCELL = 64

function Map.lineClear(a, b, step)
  step = step or 12
  local dv = b - a
  local L = dv.Magnitude
  local n = max(1, floor(L / step))
  for i = 1, n - 1 do
    local p = a + dv * (i / n)
    if heightAt(p.X, p.Z) > p.Y then return false end
    local bd = bldAt(p.X, p.Z, 0)
    if bd and not Map.BLD_DOWN[bd.id] and p.Y < PLAIN + bd.h then return false end
  end
  return true
end

---------------------------------------------------------------- 树（Map.TREES）：99.Miles 的冬季树包（Scenery 包里的 wt1～wt15、灌木 ws1～ws15；没导入时 Scenery 用零件拼）
--   { id, x, y, z, k 模型键, s 缩放, yaw, r 树干半径（格）, h 高 }；按 64 格的格子登记

local TREES = {}
Map.TREES = TREES
local TCELL = 64
Map.TREE_CELL = TCELL
local tgrid = {}
local function tkey(gx, gz) return (gx + 1024) * 4096 + (gz + 1024) end
-- 冬季树包（tools/snow/winter.py 拆的，models/scenery/winter.glb）：15 棵冬天的树、15 丛灌木；1 倍时的高（格，照 WinterMeta 抄的：
--   树长在哪要服务器、客户端算得一样，不等 WinterMeta 到）
local WT, WS = {}, {}
local TH = {
  wt1 = 42.8, wt2 = 42.8, wt3 = 42.8, wt4 = 42.4, wt5 = 42.4, wt6 = 42.4, wt7 = 34, wt8 = 34, wt9 = 30.5, wt10 = 30.5, wt11 = 30.3, wt12 = 25.6, wt13 = 29.1,
  wt14 = 23.6, wt15 = 21.1, ws1 = 19.6, ws2 = 21, ws3 = 21.6, ws4 = 20.1, ws5 = 18.5, ws6 = 19.8, ws7 = 17.1, ws8 = 20, ws9 = 12.3, ws10 = 12.3, ws11 = 14.2,
  ws12 = 16.5, ws13 = 14.2, ws14 = 12.3, ws15 = 13.4,
}
for i = 1, 15 do table.insert(WT, "wt" .. i) table.insert(WS, "ws" .. i) end
Map.TREE_KEYS = WT
local function treeOk(x, z)
  if inBase(x, z, 160) then return false end
  if onRoad(x, z, 10) then return false end
  if bldAt(x, z, 14) then return false end
  if civAt(x, z, 8) then return false end
  if riverDist(x, z) < RIVER_W + 24 or (x > LAKE.damX and lakeD(x, z) < 1.05) then return false end
  for _, p in ipairs(Map.POINTS) do
    local dx, dz = x - p.x, z - p.z
    if dx * dx + dz * dz < (Map.POINT_R + 30) ^ 2 then return false end
  end
  for _, B in ipairs(Map.BRIDGES) do
    if (x - B.x) ^ 2 + (z - B.z) ^ 2 < 120 * 120 then return false end
  end
  local _, mud = warAt(x, z)
  if mud then return false end
  return true
end
local function addTree(x, z, k, s, yaw)
  local id = #TREES + 1
  local y = heightAt(x, z)
  local t = { id = id, x = x, y = y - 0.3, z = z, k = k, s = s, yaw = yaw, h = (TH[k] or 40) * s, r = 1.0 * s + 0.4 }
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
  local R = rng(73311)
  -- 用户 11-26 晚：「交战区要有足够多的可以交互的植物 一定要非常精细」——树、灌木都撞得倒、炸得倒（Trees.lua），冬季树包一棵一两百个三角形，可以多种：
  --   · 谷边、山脚、山坡下半截：成片的林子（林线：谷底以上 900 格；坡太陡的不长）
  --   · 谷里：山梁上一小片一小片的树丛（坦克的遮蔽），冲沟里、河边长灌木（步兵的隐蔽），平地上零零星星
  -- 先按便宜的（谷里谷外、噪声）掷一次，中了再算高度、坡度（算高度贵：山体模型要查高度图）
  local function density0(x, z)
    local vd = valleyD(x, z)
    if vd > 1.3 then return 0, 0 end
    local edge = smooth(0.72, 1.0, vd) * (1 - smooth(1.0, 1.25, vd) * 0.6)   -- 谷边最密（墙外山麓上的少一些：名额留给作战区）
    local n = noise(x / 1300, z / 1300, 12.7) * 0.7 + noise(x / 420, z / 420, 3.1) * 0.3
    -- 谷里的小树丛：一小片一小片（约占谷底两成），中间留开阔地（坦克要有对射的空间，树丛是遮蔽和伏击点）
    local grove = smooth(0.27, 0.46, noise(x / 360, z / 360, 17.3)) * (1 - smooth(0.85, 1.0, vd))
    local d = edge * smooth(-0.15, 0.35, n) + 0.05 * smooth(0.25, 0.6, n) + 0.55 * grove
    local bush = 0.09 + 0.16 * smooth(0.0, 0.5, noise(x / 220, z / 220, 23.9))   -- 灌木：哪里都有一点，有的地方成片
    -- 用户 11-27「树稀稀拉拉」：摆的林子（锯木厂后山、雷达北丘、北林山）成片的密林；河滩、河岸一条树带（也挡住顺着河看的视线）
    local _, _, forest = featH(x, z)
    if forest then d += 0.6 end
    local rd = riverDist(x, z)
    if rd > RIVER_W + RIVER_BANK + 8 and rd < 330 then
      d += 0.22 * (1 - smooth(200, 330, rd))
      bush += 0.3 * (1 - smooth(160, 330, rd))
    end
    return d, bush * (1 - smooth(0.95, 1.15, vd))
  end
  local tries = 0
  local x0, x1, z0, z1 = -6600, 6600, -9800, 9800
  while #TREES < 12500 and tries < 300000 do
    tries += 1
    local x, z = x0 + R() * (x1 - x0), z0 + R() * (z1 - z0)
    local dT, dB = density0(x, z)
    local roll = R()
    local kind = (roll < dT) and "t" or ((roll < dT + dB) and "s" or nil)
    if kind and treeOk(x, z) then
      local h = heightAt(x, z)
      local hgt = h - PLAIN
      local e = 6
      local sl = sqrt(((heightAt(x + e, z) - heightAt(x - e, z)) / (2 * e)) ^ 2 + ((heightAt(x, z + e) - heightAt(x, z - e)) / (2 * e)) ^ 2)
      if sl < 0.68 and hgt < 900 and R() < 1 - smooth(600, 900, hgt) then
        if kind == "t" then
          local s = 0.75 + R() * 0.55
          if not nearTree(x, z, 13 * s) then addTree(x, z, WT[1 + floor(R() * #WT)], s, R() * math.pi * 2) end
        else
          local s = 0.8 + R() * 0.5
          if not nearTree(x, z, 9 * s) then addTree(x, z, WS[1 + floor(R() * #WS)], s, R() * math.pi * 2) end
        end
      end
    end
  end
  -- 山村、锯木厂边上几棵孤树
  for _ = 1, 160 do
    local a, r = R() * math.pi * 2, 200 + R() * 700
    local x, z = cos(a) * r, sin(a) * r
    if treeOk(x, z) and not nearTree(x, z, 24) then addTree(x, z, WT[1 + floor(R() * #WT)], 0.8 + R() * 0.4, R() * math.pi * 2) end
  end
end
Map.TREE_N = #TREES
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
function Map.treesInCell(cx, cz) return tgrid[tkey(cx, cz)] or {} end
Map.STARTS = {}

return Map
