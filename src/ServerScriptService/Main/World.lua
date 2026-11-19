-- 全面大战场：地图——光影、地形（Map.lua 的高度按块写体素）、整片海水和海底、远海平面、
--   5 个据点（旗杆、旗、地上的圈、沙袋）、守方机场、港口镇、指挥所、北岸营地、灯塔、西礁岛岸防炮台、攻方机场岛、攻方舰队（固定平台，打不掉）
--   都是锚定的静态零件；小装饰不挡人、不挡射线、不投影，省性能
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Map = require(RS:WaitForChild("Map"))

local World = {}

local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
local CYL, BALL, WEDGE = Enum.PartType.Cylinder, Enum.PartType.Ball, nil
local UP = CFrame.Angles(0, 0, math.pi / 2)   -- Roblox 圆柱的轴在 X：转 90° 立起来

local C = {
  concrete = RGB(168, 168, 162), asphalt = RGB(52, 54, 58), dark = RGB(38, 40, 44), glass = RGB(66, 104, 134),
  white = RGB(236, 236, 230), red = RGB(200, 50, 45), yellow = RGB(236, 190, 40), sandbag = RGB(176, 160, 116),
  wood = RGB(120, 88, 58), metal = RGB(122, 126, 130), roof = RGB(150, 70, 52), wall = RGB(214, 204, 178),
  hull = RGB(118, 124, 128), deck = RGB(70, 74, 78), olive = RGB(92, 104, 70), tent = RGB(110, 118, 84),
}
World.C = C

-- 零件：solid 挡人（墙、楼、船体），否则是装饰（不挡人、不挡射线、小的不投影）
local function part(parent, size, cf, color, mat, shape, solid)
  local p = Instance.new("Part")
  if shape then p.Shape = shape end
  p.Anchored = true
  p.Size = size
  p.CFrame = cf
  p.Color = color
  p.Material = mat or MAT.SmoothPlastic
  p.TopSurface = Enum.SurfaceType.Smooth
  p.BottomSurface = Enum.SurfaceType.Smooth
  if not solid then
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    if size.Magnitude < 8 then p.CastShadow = false end
  end
  p.Parent = parent
  return p
end
World.part = part
local function cyl(parent, h, dia, cf, color, mat, solid) return part(parent, V(h, dia, dia), cf * UP, color, mat, CYL, solid) end
World.cyl = cyl
local function wedge(parent, size, cf, color, mat, solid)
  local w = Instance.new("WedgePart")
  w.Anchored, w.Size, w.CFrame, w.Color, w.Material = true, size, cf, color, mat or MAT.SmoothPlastic
  if not solid then w.CanCollide, w.CanQuery, w.CanTouch = false, false, false end
  w.Parent = parent
  return w
end
local function folder(name, parent)
  local f = Instance.new("Folder")
  f.Name = name
  f.Parent = parent or workspace
  return f
end
-- 地面高度上的一点（海上是海面）
local function at(x, z, dy) return V(x, Map.ground(x, z) + (dy or 0), z) end

-- 头顶的字（离远了跟着变小）
local function sign(p, text, height, w, h, color, maxDist)
  local bb = Instance.new("BillboardGui")
  bb.Size = UDim2.new(w or 16, 0, h or 3, 0)
  bb.StudsOffsetWorldSpace = V(0, height, 0)
  bb.LightInfluence = 0
  bb.MaxDistance = maxDist or 400
  bb.AlwaysOnTop = false
  bb.Parent = p
  local t = Instance.new("TextLabel")
  t.Size = UDim2.fromScale(1, 1)
  t.BackgroundTransparency = 1
  t.Font = Enum.Font.GothamBlack
  t.TextScaled = true
  t.TextColor3 = color or Color3.new(1, 1, 1)
  t.TextStrokeTransparency = 0.3
  t.Text = text
  t.Parent = bb
  return bb, t
end
World.sign = sign

-- 夜里的灯：霓虹小块 + 光晕（BillboardGui：远处也看得见一个亮点）+ 可选的点光源 / 射灯（spot = { face, angle }，照向那一面）
--   光源都不投影（几十盏投影的灯太费）；小装饰不挡人、不挡射线
local function light(parent, pos, color, size, range, bright, spot, px)
  local p = part(parent, V(size, size * 0.6, size), CF(pos), color, MAT.Neon)
  p.CastShadow = false
  local bb = Instance.new("BillboardGui")
  bb.Name = "Glow"
  bb.Size = UDim2.new(size * 4, px or 4, size * 4, px or 4)
  bb.LightInfluence = 0
  bb.MaxDistance = 6000
  bb.Parent = p
  local halo = Instance.new("Frame")
  halo.AnchorPoint, halo.Position, halo.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
  halo.BackgroundColor3, halo.BackgroundTransparency, halo.BorderSizePixel = color, 0.76, 0
  halo.Parent = bb
  local core = Instance.new("Frame")
  core.AnchorPoint, core.Position, core.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.36, 0.36)
  core.BackgroundColor3, core.BackgroundTransparency, core.BorderSizePixel = color:Lerp(Color3.new(1, 1, 1), 0.5), 0.02, 0
  core.Parent = bb
  for _, fr in ipairs({ halo, core }) do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = fr
  end
  if range then
    local L = spot and Instance.new("SpotLight") or Instance.new("PointLight")
    L.Color, L.Range, L.Brightness, L.Shadows = color, range, bright or 1.5, false
    if spot then L.Face, L.Angle = spot.face or Enum.NormalId.Bottom, spot.angle or 70 end
    L.Parent = p
  end
  return p
end
World.light = light
-- 探照灯杆：一根杆子、顶上一盏往下照的大灯（营地、停机坪、登陆平台）
local function floodPole(parent, x, y, z, h, color, range)
  part(parent, V(0.7, h, 0.7), CF(x, y + h / 2, z), RGB(60, 62, 66), MAT.Metal, nil, true)
  part(parent, V(3.2, 0.5, 1.6), CF(x, y + h, z), RGB(40, 42, 46), MAT.Metal)
  light(parent, V(x, y + h - 0.4, z), color or RGB(255, 226, 178), 1.4, range or 110, 2.4, { face = Enum.NormalId.Bottom, angle = 95 }, 3)
end
World.floodPole = floodPole

---------------------------------------------------------------- 光影

-- 夜战（用户：交战全部设成夜晚——夜晚弥补画质，做出 3A 的质感）：凌晨两点多，月亮偏西、冷蓝的月光，环境光压得很低，远处深蓝灰的雾；
--   主要的光是枪口焰、爆炸、热诱弹、航行灯、跑道灯、甲板灯、营地探照灯（Future 光照：地图文件里设好了，脚本改不了）；夜视仪在客户端 Night.lua
function World.lighting()
  pcall(function()
    Lighting.ClockTime = 2.3
    Lighting.GeographicLatitude = 23
    Lighting.Brightness = 2.2
    Lighting.GlobalShadows = true
    Lighting.Ambient = RGB(14, 17, 24)
    Lighting.OutdoorAmbient = RGB(38, 45, 62)
    Lighting.ColorShift_Top = RGB(140, 160, 210)
    Lighting.ColorShift_Bottom = RGB(8, 10, 16)
    Lighting.EnvironmentDiffuseScale = 0.35
    Lighting.EnvironmentSpecularScale = 0.9
    Lighting.ShadowSoftness = 0.3
    Lighting.ExposureCompensation = 0.55
    Lighting.FogColor = RGB(16, 20, 30)
    Lighting.FogStart = 900
    Lighting.FogEnd = 12000   -- 地图放大了：看得远一点（远海客户端铺到镜头外一万格）
  end)
  pcall(function()
    local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
    atm.Density = 0.21   -- 原来 0.3（用户：视野很短）：远处的岛、舰、飞机看得更远
    atm.Offset = 0.06
    atm.Color = RGB(44, 54, 76)
    atm.Decay = RGB(12, 15, 24)
    atm.Glare = 0.15
    atm.Haze = 1.1
    atm.Parent = Lighting
  end)
  pcall(function()   -- 星空、大一点的月亮
    local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
    sky.StarCount = 6000
    sky.MoonAngularSize = 13
    sky.CelestialBodiesShown = true
    sky.Parent = Lighting
  end)
  pcall(function()   -- 后期：亮的东西（灯、火、曳光）泛光；整体冷一点、对比高一点
    local bloom = Lighting:FindFirstChild("NightBloom") or Instance.new("BloomEffect")
    bloom.Name = "NightBloom"
    bloom.Intensity, bloom.Size, bloom.Threshold = 1.1, 36, 1.05
    bloom.Parent = Lighting
    local cc = Lighting:FindFirstChild("NightGrade") or Instance.new("ColorCorrectionEffect")
    cc.Name = "NightGrade"
    cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = 0.02, 0.14, -0.12, RGB(222, 232, 255)
    cc.Parent = Lighting
  end)
end

---------------------------------------------------------------- 地形

-- Mud：弹坑烧焦的地面（Battle.lua 把坑里坑边的草、土、沙换成它；地图别处不用泥）——焦黑偏褐
local TERRAIN_COLORS = { Grass = RGB(96, 146, 64), LeafyGrass = RGB(70, 124, 52), Sand = RGB(226, 208, 160), Rock = RGB(124, 118, 110), Slate = RGB(98, 98, 104), Ground = RGB(122, 98, 70),
  Mud = RGB(54, 47, 40) }

-- 一块 64 × 64 列（256 × 256 格）：按高度写体素，海平面以下没土的格子是水。
--   n、yFloor（Battle.lua 填弹坑用）：只写 n × n 列的一小块，至少从 yFloor 往上写（坑底比这一小块里最低的地面还深）
local function writeChunk(T, x0, z0, n, yFloor)
  local RES, N, D = Map.RES, n or 64, Map.SEA_DEPTH
  local hs = table.create(N * N)
  local ymin, ymax = 1e9, -1e9
  for i = 0, N - 1 do
    local x = x0 + (i + 0.5) * RES
    for k = 0, N - 1 do
      local h = Map.height(x, z0 + (k + 0.5) * RES)
      hs[i * N + k + 1] = h
      if h < ymin then ymin = h end
      if h > ymax then ymax = h end
    end
  end
  -- 海底只写上面 30 格（大陆坡再往下是开头铺好的海水和远海海底：深水里看不见，写全了近岸的块要多两三倍体素）
  local DW = math.min(D, 30)
  if ymax <= -DW + 0.5 then return 0 end   -- 整块都比 30 格深（海水、海底已经铺了）
  local yb0 = math.floor((math.max(ymin, -DW) - RES) / RES)
  if yFloor then yb0 = math.min(yb0, math.floor(yFloor / RES)) end
  local yb1 = math.ceil((math.max(ymax, 0) + RES) / RES)
  local NY = yb1 - yb0
  local M, O = table.create(N), table.create(N)
  for i = 1, N do
    local Mi, Oi = table.create(NY), table.create(NY)
    for j = 1, NY do Mi[j], Oi[j] = table.create(N), table.create(N) end
    M[i], O[i] = Mi, Oi
  end
  local Water, Air, Sand, Ground, Rock = MAT.Water, MAT.Air, MAT.Sand, MAT.Ground, MAT.Rock
  for i = 0, N - 1 do
    local x = x0 + (i + 0.5) * RES
    for k = 0, N - 1 do
      local z = z0 + (k + 0.5) * RES
      local h = hs[i * N + k + 1]
      local top = Sand
      if h > 0.3 then
        local hx1 = hs[math.min(N - 1, i + 1) * N + k + 1] - hs[math.max(0, i - 1) * N + k + 1]
        local hz1 = hs[i * N + math.min(N - 1, k + 1) + 1] - hs[i * N + math.max(0, k - 1) + 1]
        top = Map.material(x, z, h, math.sqrt(hx1 * hx1 + hz1 * hz1) / (2 * RES))
      end
      local under = (h > 20) and Rock or (h > 0.3 and Ground or Sand)
      for j = 0, NY - 1 do
        local yb = (yb0 + j) * RES
        local m, o
        if yb + RES <= h then
          m, o = (yb + RES > h - 5) and top or under, 1
        elseif yb < h then
          m, o = top, math.clamp((h - yb) / RES, 0.05, 1)
        elseif yb + RES <= 0 then
          m, o = Water, 1
        else
          m, o = Air, 0
        end
        M[i + 1][j + 1][k + 1] = m
        O[i + 1][j + 1][k + 1] = o
      end
    end
  end
  local region = Region3.new(V(x0, yb0 * RES, z0), V(x0 + N * RES, yb1 * RES, z0 + N * RES))
  T:WriteVoxels(region, RES, M, O)
  return N * N * NY
end

-- 整个地形：海底沙、海水（分块 FillBlock），再按块写岛（每块之间让出一帧）；返回写了多少体素
function World.terrain(onProgress)
  local T = workspace.Terrain
  local R, D = Map.R, Map.SEA_DEPTH
  pcall(function()
    T.WaterColor = RGB(30, 112, 136)
    T.WaterTransparency = 0.5
    T.WaterReflectance = 0.5
    T.WaterWaveSize = 0.15
    T.WaterWaveSpeed = 8
    T.Decoration = true   -- 地形草（Grass 材质上会动的草叶；Map.material 让大片草地用 Grass）
    -- 草叶长度（默认 0.7 约两格高）：0.45——用户 11-19：地上草高一点、多一点（Roblox 自带的那种）；
    --   不回到 0.55（11-18 那样小兵、车轮下半截埋在草里，看着像半截身子在地下）。「多」靠 Map.material 让更多地方是 Grass
    T.GrassLength = 0.45
  end)
  for m, c in pairs(TERRAIN_COLORS) do pcall(function() T:SetMaterialColor(MAT[m], c) end) end
  local TILE = 2048
  for x = -R, R - TILE, TILE do
    for z = -R, R - TILE, TILE do
      T:FillBlock(CF(x + TILE / 2, -D - 2, z + TILE / 2), V(TILE, 4, TILE), MAT.Sand)
      -- 海水按 60 格一层灌（海加深到 110 格后一块 2048 见方要七百多万体素：分层每次不到四百万，免得一次填太大）
      local y1 = 0
      while y1 > -D do
        local h = math.min(60, y1 + D)
        T:FillBlock(CF(x + TILE / 2, y1 - h / 2, z + TILE / 2), V(TILE, h, TILE), MAT.Water)
        y1 -= h
      end
    end
    task.wait()
  end
  -- 远海（用户 11-18：要一望无际的海，不要这种割裂感——原来 ±R 以外是客户端跟着镜头铺的一圈不透明平面，颜色、反光和地形水面不一样，
  --   从天上看海面中间一道分界线）：±R 到 ±SEA_R 也灌成地形海水，水面和近海一模一样；只灌 24 格深，底下铺一层玄武岩，
  --   玄武岩染成深海的颜色（地图别处不用玄武岩），透过水看着和 110 格深的海一样暗。再往外才是客户端的平面（Scenery.lua），已经在雾里了
  local SR = Map.SEA_R or R
  if SR > R then
    pcall(function() T:SetMaterialColor(MAT.Basalt, RGB(18, 58, 70)) end)
    local FD = 24
    for x = -SR, SR - TILE, TILE do
      for z = -SR, SR - TILE, TILE do
        if not (x >= -R and x < R and z >= -R and z < R) then
          T:FillBlock(CF(x + TILE / 2, -FD - 2, z + TILE / 2), V(TILE, 4, TILE), MAT.Basalt)
          T:FillBlock(CF(x + TILE / 2, -FD / 2, z + TILE / 2), V(TILE, FD, TILE), MAT.Water)
        end
      end
      task.wait()
    end
  end
  local CH = 64 * Map.RES
  local seen, list = {}, {}
  for _, b in ipairs(Map.landBoxes()) do
    for cz = math.floor(b[2] / CH), math.floor(b[4] / CH) do
      for cx = math.floor(b[1] / CH), math.floor(b[3] / CH) do
        local key = cx .. "," .. cz
        if not seen[key] then
          seen[key] = true
          table.insert(list, { cx * CH, cz * CH })
        end
      end
    end
  end
  local total = 0
  local t0 = os.clock()
  for n, c in ipairs(list) do
    total += writeChunk(T, c[1], c[2])
    if onProgress then onProgress(n / #list) end
    if os.clock() - t0 > 0.03 then   -- 按时间片让帧（地图大了块多：每块都等一帧，光等帧就要半分钟）
      task.wait()
      t0 = os.clock()
    end
  end
  return total, #list
end

World.writeChunk = writeChunk

---------------------------------------------------------------- 小建筑

local function sandbags(f, c, r, a0, a1, h)   -- 一圈 / 一段沙袋墙（圆心 c、半径 r、从角 a0 到 a1）
  local n = math.max(2, math.floor((a1 - a0) * r / 5))
  for i = 0, n - 1 do
    local a = a0 + (a1 - a0) * (i + 0.5) / n
    local p = c + V(math.cos(a) * r, 0, math.sin(a) * r)
    local y = Map.ground(p.X, p.Z)
    part(f, V(5.2, h or 3, 2.2), CF(p.X, y + (h or 3) / 2 - 0.2, p.Z) * CFrame.Angles(0, -a + math.pi / 2, 0), C.sandbag, MAT.Fabric, nil, true)
  end
end
World.sandbags = sandbags

local function house(f, x, z, w, d, h, rot, wall, roof)
  local y = Map.ground(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot or 0, 0)
  part(f, V(w, h, d), base * CF(0, h / 2, 0), wall or C.wall, MAT.Concrete, nil, true)
  part(f, V(w + 1.5, 1, d + 1.5), base * CF(0, h + 0.5, 0), roof or C.roof, MAT.Slate, nil, true)
  for s = -1, 1, 2 do   -- 窗
    for i = 1, math.max(1, math.floor(w / 9)) do
      local wx = -w / 2 + (i - 0.5) * w / math.max(1, math.floor(w / 9))
      part(f, V(3, 3, 0.4), base * CF(wx, h * 0.6, s * (d / 2 + 0.15)), C.glass, MAT.Glass)
    end
  end
  part(f, V(4, 7, 0.4), base * CF(0, 3.5, d / 2 + 0.2), C.wood, MAT.Wood)   -- 门
  return base
end
World.house = house

local function tent(f, x, z, rot, color)
  local y = Map.ground(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot or 0, 0)
  wedge(f, V(14, 7, 6), base * CF(0, 3.5, -3), color or C.tent, MAT.Fabric, true)
  wedge(f, V(14, 7, 6), base * CF(0, 3.5, 3) * CFrame.Angles(0, math.pi, 0), color or C.tent, MAT.Fabric, true)
end

---------------------------------------------------------------- 建筑（用户：继续把游戏内地图的建筑的建模优化）
-- 导入了 models/bld/buildings.glb（网页版地图用的写实模型，带贴图）：摆原模型，外加看不见的碰撞盒挡人、挡子弹、挡车（G.spotClear 也靠它判断）；
--   没导入：零件拼一座（坡屋顶带檐口和山墙、窗框窗台、门廊、烟囱；平顶楼的楼层线、女儿墙、屋顶设备；铁皮营房、拱顶机库、八角玻璃塔台……）
--   尺寸都照 BuildingMeta（导没导入占地一样，出生点、停车位、掩体的判断都一样）
local BM, TURN = nil, CFrame.new()
pcall(function() BM = require(RS:WaitForChild("BuildingMeta", 5)) end)
pcall(function() TURN = require(RS:WaitForChild("ImportTurn", 5)).TURN end)
World.BM = BM

local function importedBld(key)
  local imp = RS:FindFirstChild("Imported")
  local b = imp and imp:FindFirstChild("Bld")
  return b and b:FindFirstChild(key)
end
World.importedBld = importedBld

-- 占地四角、中心里最低的地面（坡上的房子不悬空：上坡那边埋进去一点）
local function footY(x, z, w, d, rot)
  local c, s = math.cos(rot or 0), math.sin(rot or 0)
  local y = Map.ground(x, z)
  for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local lx, lz = o[1] * w / 2, o[2] * d / 2
    y = math.min(y, Map.ground(x + lx * c + lz * s, z - lx * s + lz * c))
  end
  return y
end
World.footY = footY

-- 占地全在陆上（四角、四边中点都不是海）：港口镇、机场摆房子前先看一眼
local function footOnLand(x, z, w, d, rot)
  local c, s = math.cos(rot or 0), math.sin(rot or 0)
  for _, o in ipairs({ { 0, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local lx, lz = o[1] * w / 2, o[2] * d / 2
    if not Map.isLand(x + lx * c + lz * s, z - lx * s + lz * c) then return false end
  end
  return true
end
World.footOnLand = footOnLand

-- 零件拼的建筑用的小工具：deco 装饰（不挡人、不挡射线）、slab 实心
local function deco(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape) end
local function slab(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape, true) end
-- 窗：白窗框 + 深色玻璃 + 窗台（贴在墙面上：face 是墙面的 CFrame，Z 朝外）
local GLASS_D, FRAME_W = RGB(44, 58, 70), RGB(222, 222, 214)
local function window(m, face, x, y, ww, wh, frameCol)
  deco(m, V(ww + 0.5, wh + 0.5, 0.2), face * CF(x, y, 0.1), frameCol or FRAME_W, MAT.SmoothPlastic)
  local g = deco(m, V(ww, wh, 0.3), face * CF(x, y, 0.18), GLASS_D, MAT.Glass)
  g.Reflectance = 0.15
  deco(m, V(ww + 1.0, 0.3, 0.7), face * CF(x, y - wh / 2 - 0.35, 0.35), FRAME_W, MAT.Concrete)
  if ww > 2.4 then deco(m, V(0.18, wh, 0.34), face * CF(x, y, 0.2), frameCol or FRAME_W, MAT.SmoothPlastic) end   -- 竖窗棂
end
-- 门：门框 + 门板 + 台阶 + 小雨棚
local function door(m, face, x, dw, dh, col)
  deco(m, V(dw + 0.8, dh + 0.5, 0.2), face * CF(x, dh / 2 + 0.6, 0.1), FRAME_W, MAT.SmoothPlastic)
  deco(m, V(dw, dh, 0.3), face * CF(x, dh / 2 + 0.6, 0.18), col or C.wood, MAT.Wood)
  slab(m, V(dw + 2.2, 0.6, 2.2), face * CF(x, 0.3, 1.1), RGB(150, 150, 146), MAT.Concrete)
  deco(m, V(dw + 3, 0.35, 2.6), face * CF(x, dh + 1.5, 1.3), RGB(80, 84, 88), MAT.Metal)
end
-- 四面墙的 CFrame（相对建筑底面中心，Z 朝外）：前（−Z）、后、左、右
local function faces(base, w, d)
  return {
    { cf = base * CF(0, 0, -d / 2) * CFrame.Angles(0, math.pi, 0), len = w },
    { cf = base * CF(0, 0, d / 2), len = w },
    { cf = base * CF(-w / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), len = d },
    { cf = base * CF(w / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), len = d },
  }
end

-- 坡屋顶民房：墙到檐口（六成高），山墙、两片屋面带出檐、屋脊、烟囱；一层或两层窗；正面中间门
local function fbHouse(m, base, w, h, d, o)
  local eave = h * 0.58
  local rh = h - eave
  slab(m, V(w + 0.8, 1.2, d + 0.8), base * CF(0, 0.3, 0), RGB(120, 118, 112), MAT.Concrete)   -- 墙基
  slab(m, V(w, eave, d), base * CF(0, eave / 2, 0), o.wall, o.wallMat or MAT.Concrete)
  -- 山墙（墙色的实心三角）+ 屋面（薄板，四边出檐）
  wedge(m, V(w, rh, d / 2), base * CF(0, eave + rh / 2, -d / 4), o.wall, o.wallMat or MAT.Concrete, true)
  wedge(m, V(w, rh, d / 2), base * CF(0, eave + rh / 2, d / 4) * CFrame.Angles(0, math.pi, 0), o.wall, o.wallMat or MAT.Concrete, true)
  for _, s in ipairs({ -1, 1 }) do   -- −1 前坡、1 后坡
    local th = math.atan2(rh, d / 2)
    local n = V(0, math.cos(th), s * math.sin(th))
    local L = math.sqrt((d / 2) ^ 2 + rh ^ 2) + 1.6
    local mid = (base * CF(0, eave + rh / 2, s * d / 4)).Position
    local rot = base - base.Position
    local pos = mid + rot:VectorToWorldSpace(n * 0.3 + V(0, -math.sin(th), s * math.cos(th)) * 0.8)
    local cf = CFrame.fromMatrix(pos, rot:VectorToWorldSpace(V(1, 0, 0)), rot:VectorToWorldSpace(n))
    slab(m, V(w + 2.4, 0.6, L), cf, o.roof, o.roofMat or MAT.Slate)
  end
  deco(m, V(w + 2.6, 0.7, 1.0), base * CF(0, h + 0.15, 0), o.roof:Lerp(Color3.new(0, 0, 0), 0.25), o.roofMat or MAT.Slate)   -- 屋脊
  deco(m, V(2.4, rh * 0.9 + 1.5, 2.4), base * CF(w * 0.26, eave + rh * 0.62, d * 0.12), RGB(120, 70, 56), MAT.Brick)   -- 烟囱
  deco(m, V(2.8, 0.4, 2.8), base * CF(w * 0.26, eave + rh * 1.07 + 0.75, d * 0.12), RGB(70, 70, 70), MAT.Concrete)
  -- 窗、门
  local floors = (eave > 11) and 2 or 1   -- 檐口高过 4 米：两层
  local F = faces(base, w, d)
  for fi, fc in ipairs(F) do
    local n = math.max(1, math.floor(fc.len / 8.5))
    for fl = 1, floors do
      local y = (floors == 1) and eave * 0.55 or eave * (fl == 1 and 0.3 or 0.74)
      for i = 1, n do
        local x = -fc.len / 2 + (i - 0.5) * fc.len / n
        if not (fi == 1 and fl == 1 and math.abs(x) < 3.5) then window(m, fc.cf, x, y, 3.0, 3.8, o.frame) end
      end
    end
  end
  door(m, F[1].cf, 0, 3.4, 6.6, o.door)
  return eave
end

-- 平顶楼（水泥楼、办公楼、公寓楼、消防站）：楼层线、每层一条窗带（窗间墙隔开）、女儿墙、屋顶空调外机 / 水箱；消防站正面几扇红色车库门
local function fbBlock(m, base, w, h, d, o)
  slab(m, V(w + 0.6, 1.0, d + 0.6), base * CF(0, 0.3, 0), RGB(110, 110, 106), MAT.Concrete)
  slab(m, V(w, h - 1.6, d), base * CF(0, (h - 1.6) / 2, 0), o.wall, o.wallMat or MAT.Concrete)
  for _, p in ipairs({ { 0, -d / 2, w + 0.6, 0.8 }, { 0, d / 2, w + 0.6, 0.8 }, { -w / 2, 0, 0.8, d }, { w / 2, 0, 0.8, d } }) do   -- 女儿墙
    slab(m, V(p[3], 1.8, p[4]), base * CF(p[1], h - 0.9, p[2]), o.trim or o.wall, o.wallMat or MAT.Concrete)
  end
  local floors = math.max(1, math.floor((h - 1.6) / 7.6))   -- 一层 2.7 米上下
  local fh = (h - 1.6) / floors
  local F = faces(base, w, d)
  for fi, fc in ipairs(F) do
    for fl = 1, floors do
      local y0 = (fl - 1) * fh
      if fl > 1 then deco(m, V(fc.len + 0.4, 0.6, 0.6), fc.cf * CF(0, y0, 0.2), o.trim or RGB(196, 196, 190), MAT.Concrete) end   -- 楼层线
      local garage = o.garage and fi == 1 and fl == 1
      if garage then
        for g = 1, o.garage do
          local x = -fc.len / 2 + (g - 0.5) * fc.len / (o.garage + 1)
          deco(m, V(fc.len / (o.garage + 1) * 0.78, fh * 0.78, 0.35), fc.cf * CF(x, fh * 0.39 + 0.5, 0.18), RGB(170, 36, 30), MAT.Metal)   -- 车库门
        end
        door(m, fc.cf, fc.len / 2 - fc.len / (o.garage + 1) * 0.5, 3.2, 6.4, RGB(80, 84, 90))
      else
        local n = math.max(1, math.floor(fc.len / 8))
        for i = 1, n do
          local x = -fc.len / 2 + (i - 0.5) * fc.len / n
          if not (fi == 1 and fl == 1 and i == math.ceil(n / 2)) then   -- 窗（平顶楼窗多：只要玻璃和窗台两块）
            local ww, wh = math.min(4.2, fc.len / n * 0.62), fh * 0.46
            local g = deco(m, V(ww, wh, 0.3), fc.cf * CF(x, y0 + fh * 0.55, 0.15), GLASS_D, MAT.Glass)
            g.Reflectance = 0.15
            deco(m, V(ww + 0.8, 0.3, 0.6), fc.cf * CF(x, y0 + fh * 0.55 - wh / 2 - 0.3, 0.3), o.trim or FRAME_W, MAT.Concrete)
          end
        end
        if fi == 1 and fl == 1 then door(m, fc.cf, -fc.len / 2 + (math.ceil(n / 2) - 0.5) * fc.len / n, 3.6, 6.6, RGB(70, 76, 82)) end
      end
    end
  end
  -- 屋顶：空调外机、水箱、检修口
  deco(m, V(4, 2.4, 3), base * CF(-w * 0.22, h - 0.4, d * 0.18), RGB(196, 198, 196), MAT.Metal)
  deco(m, V(3, 2.0, 3), base * CF(w * 0.2, h - 0.6, -d * 0.2), RGB(186, 188, 186), MAT.Metal)
  deco(m, V(3.4, 4.5, 3.4), base * CF(w * 0.3, h + 0.6, d * 0.25), RGB(150, 152, 150), MAT.Metal, CYL)
end

-- 半圆铁皮营房（匡西特）：瓦楞铁拱顶（顺着长边）、两头的端墙带门和窗
local function fbQuonset(m, base, w, h, d, o)
  slab(m, V(w + 1.2, 0.8, d + 1.2), base * CF(0, 0.2, 0), RGB(120, 120, 116), MAT.Concrete)
  local r = math.min(w / 2, h)
  slab(m, V(d, r * 2, r * 2), base * CF(0, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), o.wall or RGB(110, 116, 100), MAT.CorrodedMetal, CYL)
  for k = 1, math.floor(d / 6) do   -- 拱上一道道接缝
    deco(m, V(0.4, r * 2 + 0.25, r * 2 + 0.25), base * CF(0, 0, -d / 2 + k * 6) * CFrame.Angles(0, math.pi / 2, 0), RGB(84, 88, 78), MAT.Metal, CYL)
  end
  for _, s in ipairs({ -1, 1 }) do
    local face = base * CF(0, 0, s * d / 2) * (s < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.new())
    door(m, face, 0, 4.0, 6.8, RGB(70, 78, 66))
    window(m, face, -r * 0.55, r * 0.45, 2.6, 2.6)
    window(m, face, r * 0.55, r * 0.45, 2.6, 2.6)
  end
end

-- 拱顶机库：矮侧墙 + 椭圆拱（十几块板拼）、正面大推拉门（门缝、门上的窗带）、背面墙
local function fbHangar(m, base, w, h, d, o)
  local wall = h * 0.3
  slab(m, V(w + 2, 1, d + 2), base * CF(0, 0.3, 0), RGB(130, 130, 126), MAT.Concrete)
  for _, s in ipairs({ -1, 1 }) do slab(m, V(1.2, wall, d), base * CF(s * w / 2, wall / 2, 0), RGB(150, 152, 146), MAT.Concrete) end
  local N = 12
  local pts = {}
  for i = 0, N do
    local t = math.pi * i / N
    table.insert(pts, V(math.cos(t) * w / 2, wall + math.sin(t) * (h - wall), 0))
  end
  for i = 1, N do
    local a, b = pts[i], pts[i + 1]
    local mid, L = (a + b) / 2, (b - a).Magnitude
    local dir = (b - a).Unit
    local up = V(-dir.Y, dir.X, 0)
    if up.Y < 0 then up = -up end
    local rot = base - base.Position
    slab(m, V(L + 0.4, 0.8, d + 1.6), CFrame.fromMatrix((base * CF(mid)).Position, rot:VectorToWorldSpace(dir), rot:VectorToWorldSpace(up)), o.wall or RGB(126, 132, 128), MAT.CorrodedMetal)
  end
  -- 两头：拱形端墙用几层横条拼（宽度照椭圆）；正面下面是大门
  for _, s in ipairs({ -1, 1 }) do
    local face = base * CF(0, 0, s * d / 2) * (s < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.new())
    local layers = 6
    for k = 0, layers - 1 do
      local y0 = wall + (h - wall) * k / layers
      local y1 = wall + (h - wall) * (k + 1) / layers
      local hw = w / 2 * math.sqrt(math.max(0, 1 - (((y1 - wall) / (h - wall)) ^ 2)))
      slab(m, V(hw * 2, y1 - y0, 0.8), face * CF(0, (y0 + y1) / 2, -0.2), RGB(140, 144, 140), MAT.Metal)
    end
    if s < 0 then   -- 正面：四扇推拉门（门缝）+ 门上一条窗带
      for k = 1, 4 do
        deco(m, V(w / 4 - 0.4, wall - 0.4, 0.5), face * CF(-w / 2 + (k - 0.5) * w / 4, wall / 2, 0.1), RGB(96, 102, 98), MAT.DiamondPlate)
      end
      slab(m, V(w, wall, 0.5), face * CF(0, wall / 2, -0.3), RGB(96, 102, 98), MAT.Metal)
      deco(m, V(w * 0.8, 1.6, 0.4), face * CF(0, wall + 2, 0.1), GLASS_D, MAT.Glass)
    else
      slab(m, V(w, wall, 0.8), face * CF(0, wall / 2, -0.2), RGB(140, 144, 140), MAT.Metal)
    end
  end
end

-- 塔台：两段收分的混凝土塔身、两圈检修平台、八角形外倾的玻璃塔顶（窗棂）、顶上的天线杆
local function fbTower(m, base, w, h, d, o)
  local cab = h * 0.14
  local shaftH = h - cab - 3
  slab(m, V(w * 0.62, 2, w * 0.62), base * CF(0, 1, 0), RGB(140, 140, 136), MAT.Concrete)
  slab(m, V(w * 0.36, shaftH * 0.6, w * 0.36), base * CF(0, shaftH * 0.3, 0), C.concrete, MAT.Concrete)
  slab(m, V(w * 0.3, shaftH * 0.4, w * 0.3), base * CF(0, shaftH * 0.8, 0), C.concrete, MAT.Concrete)
  for _, y in ipairs({ shaftH * 0.42, shaftH * 0.7 }) do deco(m, V(w * 0.5, 0.6, w * 0.5), base * CF(0, y, 0), RGB(110, 112, 110), MAT.Metal) end
  slab(m, V(1.5, w * 0.86, w * 0.86), base * CF(0, shaftH + 0.75, 0) * UP, RGB(96, 98, 100), MAT.Concrete, CYL)   -- 塔顶楼板
  local R = w * 0.4
  for k = 0, 7 do   -- 八块外倾的玻璃 + 窗棂
    local a = k * math.pi / 4
    local cf = base * CF(0, shaftH + 1.5 + cab / 2, 0) * CFrame.Angles(0, a, 0) * CF(0, 0, -R) * CFrame.Angles(math.rad(-12), 0, 0)
    local g = slab(m, V(R * 0.83, cab, 0.4), cf, GLASS_D, MAT.Glass)
    g.Reflectance = 0.2
    deco(m, V(0.5, cab + 0.2, 0.6), base * CF(0, shaftH + 1.5 + cab / 2, 0) * CFrame.Angles(0, a + math.pi / 8, 0) * CF(0, 0, -R * 0.98), RGB(60, 62, 66), MAT.Metal)
  end
  slab(m, V(1.2, w * 0.92, w * 0.92), base * CF(0, shaftH + 1.5 + cab + 0.6, 0) * UP, C.dark, MAT.Metal, CYL)   -- 塔顶
  deco(m, V(0.4, 7, 0.4), base * CF(R * 0.3, shaftH + cab + 5.5, 0), C.metal, MAT.Metal)   -- 天线
  deco(m, V(2.4, 0.3, 2.4), base * CF(-R * 0.3, shaftH + cab + 3.2, 0), C.metal, MAT.Metal)   -- 雷达盘座
end

-- 库房、厂房：瓦楞铁墙、坡顶或锯齿顶（采光窗）、正面卷帘门；砖砌库房墙用砖
local function fbShed(m, base, w, h, d, o)
  local eave = h * (o.saw and 0.62 or 0.7)
  slab(m, V(w + 0.6, 0.8, d + 0.6), base * CF(0, 0.2, 0), RGB(118, 118, 114), MAT.Concrete)
  slab(m, V(w, eave, d), base * CF(0, eave / 2, 0), o.wall, o.wallMat or MAT.CorrodedMetal)
  local rh = h - eave
  if o.saw then   -- 锯齿顶：一排朝北的采光窗
    local n = math.max(2, math.floor(d / 14))
    for k = 1, n do
      local z = -d / 2 + (k - 0.5) * d / n
      wedge(m, V(w, rh, d / n), base * CF(0, eave + rh / 2, z) * CFrame.Angles(0, math.pi, 0), o.roof, MAT.CorrodedMetal, true)   -- 竖着的一面朝前
      deco(m, V(w - 1, rh * 0.8, 0.3), base * CF(0, eave + rh * 0.45, z - d / n / 2 - 0.2), GLASS_D, MAT.Glass)
    end
  else
    wedge(m, V(w, rh, d / 2), base * CF(0, eave + rh / 2, -d / 4), o.roof, MAT.CorrodedMetal, true)
    wedge(m, V(w, rh, d / 2), base * CF(0, eave + rh / 2, d / 4) * CFrame.Angles(0, math.pi, 0), o.roof, MAT.CorrodedMetal, true)
    deco(m, V(w + 1, 0.6, 1.2), base * CF(0, h + 0.1, 0), o.roof:Lerp(Color3.new(0, 0, 0), 0.3), MAT.Metal)
  end
  local F = faces(base, w, d)
  local n = math.max(1, math.floor(F[1].len / 22))
  for i = 1, n do   -- 正面卷帘门（带一道道横纹）
    local x = -F[1].len / 2 + (i - 0.5) * F[1].len / n
    local dw, dh = math.min(14, F[1].len / n * 0.6), math.min(eave * 0.8, 11)
    deco(m, V(dw + 1, dh + 0.8, 0.25), F[1].cf * CF(x, dh / 2 + 0.4, 0.12), RGB(70, 72, 74), MAT.Metal)
    deco(m, V(dw, dh, 0.35), F[1].cf * CF(x, dh / 2 + 0.4, 0.2), RGB(150, 154, 150), MAT.DiamondPlate)
  end
  for _, fc in ipairs({ F[3], F[4] }) do   -- 侧面高窗
    local k = math.max(1, math.floor(fc.len / 12))
    for i = 1, k do window(m, fc.cf, -fc.len / 2 + (i - 0.5) * fc.len / k, eave * 0.75, 4, 2) end
  end
end

-- 每种建筑：零件拼的样子、颜色，碰撞盒（相对宽 / 高 / 深的比例：{ 中心 x, y, z, 大小 x, y, z }）
local BLD = {
  jph1 = { fb = fbHouse, wall = RGB(214, 210, 198), roof = RGB(58, 62, 68), roofMat = MAT.Slate, frame = RGB(230, 230, 226) },
  jph2 = { fb = fbHouse, wall = RGB(160, 120, 92), wallMat = MAT.WoodPlanks, roof = RGB(60, 58, 56), roofMat = MAT.Slate },
  jph3 = { fb = fbHouse, wall = RGB(200, 200, 194), roof = RGB(70, 74, 80), roofMat = MAT.Slate },
  house = { fb = fbHouse, wall = RGB(196, 186, 160), roof = RGB(150, 78, 58), roofMat = MAT.Slate, door = RGB(90, 60, 40) },
  conc1 = { fb = fbBlock, wall = RGB(176, 174, 166), trim = RGB(150, 148, 140) },
  conc2 = { fb = fbBlock, wall = RGB(168, 166, 160), trim = RGB(144, 142, 136) },
  conc3 = { fb = fbBlock, wall = RGB(182, 178, 168), trim = RGB(150, 146, 136) },
  industrial = { fb = fbBlock, wall = RGB(150, 92, 72), wallMat = MAT.Brick, trim = RGB(190, 186, 176) },
  flats1 = { fb = fbBlock, wall = RGB(140, 76, 58), wallMat = MAT.Brick, trim = RGB(200, 196, 186) },
  firestation = { fb = fbBlock, wall = RGB(156, 70, 56), wallMat = MAT.Brick, trim = RGB(210, 206, 196), garage = 3 },
  quonset = { fb = fbQuonset, wall = RGB(104, 112, 96), coll = { { 0, 0.4, 0, 0.86, 0.8, 0.98 } } },
  hangar = { fb = fbHangar, wall = RGB(126, 132, 128), coll = { { 0, 0.42, 0, 0.96, 0.84, 0.98 } } },
  atc = { fb = fbTower, coll = { { 0, 0.4, 0, 0.36, 0.8, 0.36 }, { 0, 0.9, 0, 0.86, 0.2, 0.86 } } },
  wh3 = { fb = fbShed, wall = RGB(150, 156, 150), roof = RGB(110, 116, 112) },
  sawtooth = { fb = fbShed, wall = RGB(120, 96, 84), roof = RGB(96, 90, 86), saw = true },
  smallwh = { fb = fbShed, wall = RGB(118, 124, 104), roof = RGB(90, 96, 84) },
  wh99 = { fb = fbShed, wall = RGB(136, 70, 54), wallMat = MAT.Brick, roof = RGB(80, 84, 88) },
}
World.BLD = BLD
-- 默认碰撞盒：墙身整块 + 屋顶收窄一点（坡屋顶上面空着的地方不挡子弹太多）
local COLL_DEF = { { 0, 0.33, 0, 0.96, 0.66, 0.96 }, { 0, 0.8, 0, 0.8, 0.3, 0.7 } }

-- 摆一座建筑：key 是 BuildingMeta 的键；front 朝向 = 正面（−Z）转 rot；返回 (底面 CFrame, Model)
local function building(f, key, x, z, rot, opt)
  opt = opt or {}
  local info = BM and BM[key]
  local spec = BLD[key] or BLD.conc1
  local w, h, d = (info and info.w) or opt.w or 24, (info and info.h) or opt.h or 16, (info and info.d) or opt.d or 24
  local y = footY(x, z, w * 0.9, d * 0.9, rot) - 0.25
  local base = CF(x, y, z) * CFrame.Angles(0, rot or 0, 0)
  local m = Instance.new("Model")
  m.Name = "Bld_" .. key
  m:SetAttribute("Bld", key)
  local src = info and importedBld(key)
  local n = 0
  if src then   -- 原模型：每块照元数据的中心摆，补回导入时转掉的半圈（同载具）
    for name, p in pairs(info.parts) do
      local s0 = src:FindFirstChild("B_" .. key .. "__" .. name)
      if s0 and s0:IsA("BasePart") then
        local mp = s0:Clone()
        mp.Anchored = true
        mp.CanCollide, mp.CanQuery, mp.CanTouch = false, false, false
        mp.Size = V(p.s[1], p.s[2], p.s[3])
        mp.CFrame = base * CF(p.c[1], p.c[2], p.c[3]) * TURN
        if p.col then
          local okT, tid = pcall(function() return mp.TextureID end)
          if not mp:FindFirstChildOfClass("SurfaceAppearance") and (not okT or (tid or "") == "") then mp.Color = RGB(p.col[1], p.col[2], p.col[3]) end
        end
        mp.Parent = m
        n += 1
      end
    end
    if n > 0 then
      for _, c in ipairs(spec.coll or COLL_DEF) do   -- 看不见的碰撞盒：挡人、挡车、挡子弹（原模型的网格不参与碰撞：窗洞、门洞会卡人）
        local bx = part(m, V(w * c[4], h * c[5], d * c[6]), base * CF(w * c[1], h * c[2], d * c[3]), C.concrete, MAT.SmoothPlastic, nil, true)
        bx.Name = "Collision"
        bx.Transparency = 1
        bx.CastShadow = false
      end
    end
  end
  if n == 0 then spec.fb(m, base, w, h, d, spec) end
  -- 夜里：正门边一盏暖黄的壁灯（机库、塔台不要：机库有停机坪的探照灯，塔台顶上有红灯）
  if key ~= "hangar" and key ~= "atc" then
    light(m, (base * CF(math.min(4.2, w * 0.18), math.min(8.6, h * 0.45), -d / 2 - 0.7)).Position, RGB(255, 196, 132), 0.5, 16, 0.9, nil, 2)
  end
  m:SetAttribute("Imported", n > 0)
  -- 占地（Battle.lua 炸塌房子用：废墟按这个摆）
  m:SetAttribute("BldBase", base)
  m:SetAttribute("BldSize", V(w, h, d))
  m.Parent = f
  return base, m, w, h, d
end
World.building = building

local function mast(f, x, z, h)   -- 天线杆：顶上红灯一闪一闪
  local y = Map.ground(x, z)
  cyl(f, h, 0.8, CF(x, y + h / 2, z), C.metal, MAT.Metal, true)
  local l = light(f, V(x, y + h + 0.7, z), RGB(255, 40, 40), 1.2, 16, 1.6)
  l:SetAttribute("Anim", "blink")   -- 客户端 Night.lua 让它一闪一闪
  l:SetAttribute("Spd", 0.8)
end

---------------------------------------------------------------- 据点

-- 据点：地上一圈（颜色跟着归属变）、旗杆和旗、一圈断续的沙袋、远处也看得到的字母牌；Round 按属性 Owner 改颜色
function World.points(f)
  local list = {}
  for _, p in ipairs(Map.POINTS) do
    local m = Instance.new("Model")
    m.Name = "Point_" .. p.id
    local y = Map.ground(p.x, p.z)
    local ring = part(m, V(0.3, Map.POINT_R * 2, Map.POINT_R * 2), CF(p.x, y + 0.2, p.z) * UP, RGB(60, 120, 230), MAT.Neon, CYL)
    ring.Name = "Ring"
    ring.Transparency = 0.82
    local pole = cyl(m, 34, 0.9, CF(p.x, y + 17, p.z), C.white, MAT.Metal, true)
    pole.Name = "Pole"
    local flag = part(m, V(10, 6, 0.3), CF(p.x + 5.4, y + 30, p.z), RGB(60, 120, 230), MAT.Fabric)
    flag.Name = "Flag"
    local _, lbl = sign(pole, p.id, 24, 9, 9, Color3.new(1, 1, 1), 9000)
    lbl.Name = "Letter"
    sandbags(m, V(p.x, 0, p.z), 16, 0.3, 2.4, 3)
    sandbags(m, V(p.x, 0, p.z), 16, 3.5, 5.6, 3)
    m:SetAttribute("Id", p.id)
    m:SetAttribute("Owner", "def")
    m.Parent = f
    list[p.id] = m
  end
  return list
end

---------------------------------------------------------------- 场景

local function airfield(f, A, team)   -- 跑道东西向、北面停机坪、机库、塔台
  local y = A.y or Map.ground(A.x, A.z)
  local base = CF(A.x, y, A.z)
  -- 跑道长过 2048 格（零件最长 2048）：分几段铺
  local nseg = math.ceil(A.len / 2000)
  for i = 1, nseg do
    local L = A.len / nseg
    part(f, V(L, 1, A.wid), base * CF(-A.len / 2 + (i - 0.5) * L, 0.45, 0), C.asphalt, MAT.Asphalt, nil, true)
  end
  for i = -A.len / 2 + 20, A.len / 2 - 20, 45 do part(f, V(22, 0.1, 1.6), base * CF(i, 1, 0), C.white, MAT.SmoothPlastic) end   -- 中线
  for s = -1, 1, 2 do
    part(f, V(6, 0.1, A.wid - 8), base * CF(s * (A.len / 2 - 8), 1, 0), C.white, MAT.SmoothPlastic)   -- 两头的入口线
    for k = -3, 3 do if k ~= 0 then part(f, V(40, 0.1, 4), base * CF(s * (A.len / 2 - 50), 1, k * A.wid / 8), C.white, MAT.SmoothPlastic) end end   -- 入口的斑马线
    for e2 = -1, 1, 2 do   -- 两边的边线（分段，零件最长 2048）
      for i = 1, nseg do
        local L = A.len / nseg
        part(f, V(L, 0.1, 1.2), base * CF(-A.len / 2 + (i - 0.5) * L, 1, e2 * (A.wid / 2 - 3)), C.white, MAT.SmoothPlastic)
      end
    end
  end
  part(f, V(math.min(2000, A.len * 0.6), 1, 70), base * CF(0, 0.45, -A.wid / 2 - 45), C.concrete, MAT.Concrete, nil, true)   -- 停机坪
  -- 机库、塔台、营房（用户：继续把地图建筑的建模优化）：网页版地图的写实模型（导入了 buildings.glb）或零件拼的；
  --   两座拱顶机库在停机坪北边、大门朝南对着停机坪（中间空着：攻方机场岛的出生点在 x 0 一带，守方据点 D 的圈也在那里）
  local bf = folder("Buildings", f)
  local hz = -A.wid / 2 - 80 - ((BM and BM.hangar and BM.hangar.d) or 126) / 2 - 6
  for _, sx in ipairs({ -1, 1 }) do building(bf, "hangar", A.x + sx * 130, A.z + hz, math.pi) end
  -- 塔台在跑道东头北边（原来的位置）；旁边一座消防站（机场救援）、北边一排铁皮营房、一座小库房
  local tx, tz = A.x + A.len / 2 - 40, A.z - A.wid / 2 - 110
  local _, _, _, th = building(bf, "atc", tx, tz, math.pi)
  local ty = footY(tx, tz, 20, 20, 0) - 0.25
  light(f, V(tx, ty + th + 1.2, tz), RGB(255, 40, 40), 1, 14, 1.2).Name = "TowerBeacon"
  building(bf, "firestation", tx - 130, A.z - A.wid / 2 - 130, math.pi)
  for k = 0, 2 do building(bf, "quonset", A.x - 330 - k * 50, A.z - A.wid / 2 - 170, math.pi) end
  building(bf, "smallwh", A.x + 300, A.z - A.wid / 2 - 120, math.pi)
  -- 夜里的跑道灯：两边白色边灯每 40 格一盏，两头入口绿灯、末端红灯（两头都能起降：一头绿一头红）；停机坪南边一排蓝色滑行道灯
  local lights = Instance.new("Folder")
  lights.Name = "RunwayLights"
  lights.Parent = f
  for xx = -A.len / 2 + 10, A.len / 2 - 10, 60 do   -- 跑道长了：60 格一盏（灯太多费）
    for sd = -1, 1, 2 do light(lights, (base * CF(xx, 1.2, sd * (A.wid / 2 + 1.5))).Position, RGB(255, 246, 220), 0.6, nil, nil, nil, 3) end
  end
  for zz = -A.wid / 2 + 3, A.wid / 2 - 3, 8 do
    light(lights, (base * CF(-A.len / 2 - 2, 1.2, zz)).Position, RGB(60, 255, 120), 0.6, nil, nil, nil, 3)
    light(lights, (base * CF(A.len / 2 + 2, 1.2, zz)).Position, RGB(255, 50, 40), 0.6, nil, nil, nil, 3)
  end
  for xx = -math.min(1000, A.len * 0.3), math.min(1000, A.len * 0.3), 50 do light(lights, (base * CF(xx, 1.2, -A.wid / 2 - 9)).Position, RGB(70, 120, 255), 0.5, nil, nil, nil, 3) end
  for i = -1, 1 do floodPole(lights, A.x + i * A.len * 0.24, y, A.z - A.wid / 2 - 84, 22, RGB(255, 222, 170), 120) end
  local _ = team
end

local function portTown(f)
  local P = Map.PORT
  -- 码头：从湾底伸进湾里
  local zs = Map.coastS(P.x) or P.z
  for i = -1, 1 do
    local px = P.x + i * 70
    part(f, V(14, 2, 90), CF(px, 1, zs + 40), C.wood, MAT.WoodPlanks, nil, true)
    for k = 0, 3 do   -- 木桩：打到海底（原来木板直接摆在水面上，像漂着；用户 11-18：这些建筑漂在水里）
      for _, sx in ipairs({ -1, 1 }) do
        local x, z = px + sx * 6, zs + 40 - 45 + 8 + k * 25
        local bed = math.min(-1, math.max(Map.height(x, z), -40))
        cyl(f, -bed + 0.2, 1.1, CF(x, bed / 2 + 0.1, z), RGB(70, 58, 44), MAT.Wood, true)
      end
    end
  end
  -- 镇上的房子（用户：继续把地图建筑的建模优化）：民房、瓦房、水泥楼混着摆，街北的正门朝南、街南的朝北（都朝着镇中心那条街），
  --   每座稍微歪一点；湾边一排库房、码头根上一座小库房（大门朝海）
  local bf = folder("Buildings", f)
  local spots = { { -60, -40, "jph1" }, { -20, -55, "conc2" }, { 25, -45, "house" }, { 65, -30, "jph3" }, { -70, 10, "conc1" },
    { 70, 15, "jph2" }, { -30, 40, "jph1" }, { 35, 45, "conc3" }, { -95, -75, "house" }, { 100, -70, "conc1" } }
  for k, s in ipairs(spots) do
    local x, z = P.x + s[1], P.z + s[2]
    local info = BM and BM[s[3]]
    local rot = ((s[2] < 0) and math.pi or 0) + ((k % 3) - 1) * 0.06
    if footOnLand(x, z, info and info.w or 20, info and info.d or 20, rot) then building(bf, s[3], x, z, rot) end
  end
  local wz = zs - 48
  if footOnLand(P.x, wz, 132, 30, math.pi) then building(bf, "wh3", P.x, wz, math.pi) end
  if footOnLand(P.x - 150, zs - 40, 30, 34, math.pi) then building(bf, "smallwh", P.x - 150, zs - 40, math.pi) end
  if footOnLand(P.x + 150, zs - 60, 46, 64, math.pi) then building(bf, "sawtooth", P.x + 150, zs - 60, math.pi) end
  -- 吊车
  local cx, cz = P.x + 70, zs + 20
  local y = Map.ground(cx, cz)
  part(f, V(3, 40, 3), CF(cx, y + 20, cz), C.yellow, MAT.Metal, nil, true)
  part(f, V(3, 3, 40), CF(cx, y + 40, cz + 14), C.yellow, MAT.Metal, nil, true)
end

local function commandPost(f)
  local P = Map.COMMAND
  local y = Map.ground(P.x, P.z)
  part(f, V(36, 10, 26), CF(P.x - 30, y + 4, P.z - 25), C.concrete, MAT.Concrete, nil, true)   -- 半埋的掩体
  part(f, V(40, 2, 30), CF(P.x - 30, y + 9.5, P.z - 25), RGB(110, 112, 100), MAT.Concrete, nil, true)
  mast(f, P.x + 30, P.z - 30, 46)
  tent(f, P.x + 32, P.z + 22, 0.3)
  sandbags(f, V(P.x - 30, 0, P.z - 25), 30, 0, math.pi * 2, 3)
end

local function camp(f)
  local P = Map.CAMP
  for i = -2, 2 do tent(f, P.x + i * 24, P.z - 20, 0, C.tent) end
  local bf = folder("Buildings", f)
  for _, sx in ipairs({ -1, 1 }) do building(bf, "quonset", P.x + sx * 50, P.z + 20, math.pi / 2) end   -- 铁皮营房：长边东西向，门朝东西两头
  local y = Map.ground(P.x, P.z)
  cyl(f, 30, 0.8, CF(P.x, y + 15, P.z + 40), C.white, MAT.Metal, true)
  -- 夜里：车场一排探照灯（车场在南面 z + 70）、北面直升机停机坪两盏、帐篷门口小灯
  for i = -2, 2 do floodPole(f, P.x + i * 72, Map.ground(P.x + i * 72, P.z + 44), P.z + 44, 18, RGB(255, 220, 168), 90) end
  for _, dx in ipairs({ -140, 146 }) do floodPole(f, P.x + dx, Map.ground(P.x + dx, P.z - 62), P.z - 62, 18, RGB(255, 226, 180), 90) end
  for i = -2, 2 do light(f, V(P.x + i * 24, y + 6.5, P.z - 16.5), RGB(255, 200, 140), 0.4, 12, 0.9) end
end

local function lighthouse(f)
  local I = Map.LIGHTHOUSE
  local x, z = I.x + I.a * 0.55, I.z + 30   -- 东岸崖顶
  local y = Map.ground(x, z)
  f = folder("Lighthouse", f)
  for i = 0, 5 do cyl(f, 8, 12 - i * 0.6, CF(x, y + 4 + i * 8, z), (i % 2 == 0) and C.white or C.red, MAT.Concrete, true) end
  local lantern = CF(x, y + 51, z)
  local warm = RGB(255, 226, 170)
  cyl(f, 1.2, 14, lantern * CF(0, -3, 0), C.dark, MAT.Metal)
  cyl(f, 1, 11, lantern * CF(0, 3, 0), C.red, MAT.Metal)
  cyl(f, 1.3, 7, lantern * CF(0, 4.1, 0), C.dark, MAT.Metal)
  for i = 0, 7 do
    local corner = lantern * CFrame.Angles(0, i * math.pi / 4, 0)
    part(f, V(0.26, 6, 0.26), corner * CF(0, 0, -4.3), C.dark, MAT.Metal)
    part(f, V(5.3, 0.23, 0.23), corner * CF(0, -1.2, -6.45), C.metal, MAT.Metal)
  end
  local lamp = part(f, V(3.2, 3.2, 3.2), lantern, warm, MAT.Neon, BALL)
  local pl = Instance.new("PointLight")
  pl.Range, pl.Brightness, pl.Color = 28, 1.4, warm
  pl.Parent = lamp

  -- 两层渐隐光束共用一个转轴，客户端按服务器时钟同步扫过海面。
  local sweep = part(f, V(1, 1, 1), lantern, warm)
  sweep.Name = "LighthouseSweep"
  sweep.Transparency = 1
  sweep:SetAttribute("Anim", "spin")
  sweep:SetAttribute("Spd", 0.08)
  sweep:SetAttribute("Pivot", lantern.Position)
  local lens = Instance.new("Attachment")
  lens.Position = V(0, 0, -4.7)
  lens.Parent = sweep
  for _, spec in ipairs({
    { name = "LanternCore", distance = 220, width0 = 1.8, width1 = 10, alpha = 0.88 },
    { name = "SeaHaze", distance = 650, width0 = 4, width1 = 48, alpha = 0.94 },
  }) do
    local reach = Instance.new("Attachment")
    reach.Position = V(0, -0.025 * spec.distance, -spec.distance)
    reach.Parent = sweep
    local beam = Instance.new("Beam")
    beam.Name = spec.name
    beam.Attachment0, beam.Attachment1 = lens, reach
    beam.Width0, beam.Width1 = spec.width0, spec.width1
    beam.FaceCamera, beam.LightEmission, beam.LightInfluence = true, 0.7, 0
    beam.Color = ColorSequence.new(warm, RGB(172, 199, 215))
    beam.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.10, spec.alpha),
      NumberSequenceKeypoint.new(0.37, spec.alpha), NumberSequenceKeypoint.new(1, 1),
    })
    beam.Parent = sweep
  end
  local sl = Instance.new("SpotLight")
  sl.Face, sl.Angle, sl.Range, sl.Brightness, sl.Color = Enum.NormalId.Front, 20, 60, 2.5, warm
  sl.Shadows = false
  sl.Parent = sweep
  building(f, "jph2", x - 30, z + 12, 0.2 + math.pi / 2)   -- 看守的小屋
end

local function battery(f)   -- 西礁岛岸防炮台：营房（炮本身是 Forts 管的工事实体，能开火、能被打掉、玩家能操作）
  local I = Map.WESTREEF
  building(f, "conc3", I.x - 50, I.z - 20, 0.5)   -- 炮台营房：水泥楼
end

-- 攻方舰队：固定的大平台（航母、两栖攻击舰、登陆舰），甲板离水面约 30 格；出生点在甲板上
local SHIPS = {
  carrier = { L = 620, W = 116, H = 34, deck = 30, island = { 0.18, 0.42 }, color = C.hull },
  lhd = { L = 480, W = 90, H = 30, deck = 26, island = { 0.2, 0.4 }, color = C.hull },
  lst = { L = 300, W = 56, H = 22, deck = 18, island = { -0.3, 0.3 }, color = C.hull },
}
-- 航母甲板：弹射轨道（深色槽 + 黄色中线 + 起点的滑块）、偏流板（起点后面放平的一块）、斜角甲板的白线、拦阻索
--   位置照 AirDefs.CATS / WIRES（飞机端按同一套数判断卡没卡上弹射器、落没落在拦阻索区）
function World.carrierDeck(m, top)
  local AD = require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs"))
  for i, c in ipairs(AD.CATS) do
    local start = top * CF(c.x, 0, c.z) * CFrame.Angles(0, c.a, 0)
    part(m, V(2.6, 0.12, c.len), start * CF(0, 0.06, -c.len / 2), RGB(40, 42, 46), MAT.Metal)
    for k = 0, c.len - 10, 20 do part(m, V(0.5, 0.14, 10), start * CF(0, 0.08, -k - 5), C.yellow) end
    local shuttle = part(m, V(1.6, 0.6, 3), start * CF(0, 0.3, 0), RGB(70, 72, 76), MAT.Metal)
    shuttle.Name = "Shuttle" .. i
    local jbd = part(m, V(16, 0.4, 9), start * CF(0, 0.2, 22), RGB(96, 100, 104), MAT.DiamondPlate)   -- 偏流板（放平）
    jbd.Name = "JBD" .. i
    part(m, V(0.4, 0.15, 30), start * CF(-6, 0.08, 8), C.white)
    part(m, V(0.4, 0.15, 30), start * CF(6, 0.08, 8), C.white)
  end
  local Wd = AD.WIRES
  local deckA = top * CF(Wd.x, 0, (Wd.z0 + Wd.z1) / 2) * CFrame.Angles(0, Wd.a, 0)
  for k = 0, Wd.n - 1 do   -- 拦阻索：横跨斜角甲板的四根钢索
    local z = -((Wd.z1 - Wd.z0) / 2) + (k + 0.5) * (Wd.z1 - Wd.z0) / Wd.n
    part(m, V(70, 0.35, 0.35), deckA * CF(0, 0.25, z), RGB(30, 30, 32), MAT.Metal)
  end
  for s = -1, 1, 2 do   -- 斜角甲板两边的白色虚线
    local edge = top * CF(Wd.x + s * 34, 0, 60) * CFrame.Angles(0, Wd.a, 0)
    for k = -240, 240, 24 do part(m, V(0.6, 0.12, 12), edge * CF(0, 0.07, k), C.white) end
  end
  part(m, V(1.2, 0.12, 470), top * CF(Wd.x, 0.07, 60) * CFrame.Angles(0, Wd.a, 0), C.yellow)   -- 着舰中线
  -- 夜间着舰的灯（位置照真航母）：中线嵌入式白灯、斜角甲板两边的边灯、舰尾往下一列琥珀色下降灯（对准中线）、
  --   左舷着舰区旁边的光学着舰指示器（中间琥珀色「肉球」、两边一排绿色基准灯）、弹射器轨道两侧蓝灯
  local landLine = top * CF(Wd.x, 0, 60) * CFrame.Angles(0, Wd.a, 0)
  for k = -230, 230, 26 do light(m, (landLine * CF(0, 0.2, k)).Position, RGB(255, 250, 236), 0.5, nil, nil, nil, 3) end
  for sd = -1, 1, 2 do
    for k = -230, 230, 40 do light(m, (landLine * CF(sd * 33, 0.2, k)).Position, RGB(90, 150, 255), 0.5, nil, nil, nil, 3) end
  end
  local stern = (landLine * CF(0, 0, 240)).Position
  for k = 1, 5 do light(m, stern + V(0, -k * 2.4, 3), RGB(255, 170, 60), 0.6, (k == 1) and 12 or nil, 1, nil, 3) end
  local fl = top * CF(-58, 0, 150)   -- 光学着舰指示器：左舷边上
  part(m, V(2, 6, 3), fl * CF(0, 3, 0), RGB(40, 42, 46), MAT.Metal)
  light(m, (fl * CF(0, 6.4, -1.6)).Position, RGB(255, 170, 40), 0.9, 10, 2, nil, 5)
  for k = -3, 3 do
    if k ~= 0 then light(m, (fl * CF(0, 6.4, -1.6 + k * 1.4)).Position, RGB(60, 255, 110), 0.55, nil, nil, nil, 3) end
  end
  for _, c in ipairs(AD.CATS) do
    local start = top * CF(c.x, 0, c.z) * CFrame.Angles(0, c.a, 0)
    for k = 0, c.len, 40 do
      for sd = -1, 1, 2 do light(m, (start * CF(sd * 2.2, 0.15, -k)).Position, RGB(80, 140, 255), 0.35, nil, nil, nil, 2) end
    end
  end
end

function World.fleet(f)
  local decks = {}
  for i, s in ipairs(Map.FLEET) do
    local D = SHIPS[s.kind]
    local m = Instance.new("Model")
    m.Name = "Ship_" .. s.kind .. i
    local base = CF(s.x, 0, s.z) * CFrame.Angles(0, s.rot or 0, 0)
    part(m, V(D.W, D.H, D.L), base * CF(0, D.deck - D.H / 2 - 1, 0), D.color, MAT.Metal, nil, true)   -- 船体（往下伸进水里）
    wedge(m, V(D.W, D.H, 40), base * CF(0, D.deck - D.H / 2 - 1, -D.L / 2 - 20) * CFrame.Angles(0, math.pi, 0), D.color, MAT.Metal, true)   -- 船头
    local deck = part(m, V(D.W + 4, 1.5, D.L), base * CF(0, D.deck - 0.25, 0), C.deck, MAT.Asphalt, nil, true)
    deck.Name = "Deck"
    for k = -D.L / 2 + 30, D.L / 2 - 30, 40 do part(m, V(1, 0.1, 16), base * CF(0, D.deck + 0.6, k), C.yellow) end
    local ix = D.W / 2 - 16
    local iz = D.L * (D.island[1] - 0.5) + D.L * 0.3
    part(m, V(18, 36, D.L * 0.16), base * CF(ix, D.deck + 18, iz), RGB(108, 114, 118), MAT.Metal, nil, true)   -- 舰岛
    -- 航行灯（照船舶避碰规则的位置）：桅杆顶白灯、舰岛左右两侧红 / 绿舷灯、舰尾白灯；舰岛上往甲板照的探照灯
    part(m, V(1, 14, 1), base * CF(ix, D.deck + 43, iz), RGB(90, 94, 98), MAT.Metal)
    light(m, (base * CF(ix, D.deck + 50.5, iz)).Position, RGB(255, 250, 236), 0.9, 18, 1.4, nil, 4)
    light(m, (base * CF(ix - 9.4, D.deck + 30, iz - 6)).Position, RGB(255, 50, 40), 0.8, 14, 1.4, nil, 4)
    light(m, (base * CF(ix + 9.4, D.deck + 30, iz - 6)).Position, RGB(60, 255, 120), 0.8, 14, 1.4, nil, 4)
    light(m, (base * CF(0, D.deck - 2, D.L / 2 + 0.6)).Position, RGB(255, 250, 236), 0.8, 14, 1.2, nil, 4)
    for _, dz in ipairs({ -D.L * 0.12, D.L * 0.12 }) do
      light(m, (base * CF(ix - 9.6, D.deck + 22, iz + dz)).Position, RGB(255, 214, 160), 1.1, 140, 1.8, { face = Enum.NormalId.Left, angle = 70 }, 3)
    end
    if s.kind == "carrier" then
      local ok, err = pcall(World.carrierDeck, m, base * CF(0, D.deck + 0.5, 0))
      if not ok then warn("[全面大战场] 航母甲板出错：" .. tostring(err)) end
    end
    m:SetAttribute("Kind", s.kind)
    m.Parent = f
    table.insert(decks, { kind = s.kind, cf = base * CF(0, D.deck + 1, 0), L = D.L, W = D.W, model = m })
  end
  return decks
end

local function attackerAirfield(f)
  local A = Map.AFIELD2
  airfield(f, { x = A.x, z = A.z, y = A.y, len = A.len, wid = A.wid }, "atk")
end

-- 海滩：每处海滩中间一根带颜色的标杆（从海上看得到往哪儿冲）；钢刺猬、铁丝网、雷区在 Forts 里摆
function World.beaches(f)
  for _, b in ipairs(Map.BEACHES) do
    local z = b.z - b.dir * 30
    local y = Map.ground(b.cx, z)
    cyl(f, 20, 0.8, CF(b.cx, y + 10, z), C.white, MAT.Metal)
    part(f, V(8, 5, 0.3), CF(b.cx + 4.3, y + 17, z), b.color, MAT.Fabric)
  end
end

-- 开服时建整张地图；地形分块写（要好几秒），写完才让人出生
function World.build(G)
  World.lighting()
  local root = folder("Map")
  local deco = folder("Scenery", root)
  local n, chunks = World.terrain(function(p) G.worldProgress = p end)
  G.terrainVoxels, G.terrainChunks = n, chunks
  -- 远海改在客户端跟着镜头铺（Scenery.lua）：地图放大以后服务器这一圈不够远，飞机飞出去看得到海的尽头
  G.try("机场", airfield, deco, Map.AIRFIELD, "def")
  G.try("港口镇", portTown, deco)
  G.try("指挥所", commandPost, deco)
  G.try("营地", camp, deco)
  G.try("灯塔", lighthouse, deco)
  G.try("岸防炮台", battery, deco)
  G.try("攻方机场岛", attackerAirfield, deco)
  G.try("海滩标杆", World.beaches, deco)
  G.pointModels = World.points(folder("Points", root))
  G.decks = World.fleet(folder("Fleet", root))
  G.worldReady = true
end

return World
