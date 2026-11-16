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

---------------------------------------------------------------- 光影

function World.lighting()
  pcall(function()
    Lighting.ClockTime = 14.2
    Lighting.GeographicLatitude = 12
    Lighting.Brightness = 3
    Lighting.GlobalShadows = true
    Lighting.Ambient = RGB(70, 72, 80)
    Lighting.OutdoorAmbient = RGB(132, 136, 146)
    Lighting.ColorShift_Top = RGB(255, 244, 226)
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 1
    Lighting.ShadowSoftness = 0.2
    Lighting.ExposureCompensation = 0.1
    Lighting.FogColor = RGB(176, 196, 212)
    Lighting.FogStart = 2500
    Lighting.FogEnd = 9000
  end)
  pcall(function()
    local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
    atm.Density = 0.28
    atm.Offset = 0.12
    atm.Color = RGB(199, 214, 228)
    atm.Decay = RGB(106, 128, 150)
    atm.Glare = 0.25
    atm.Haze = 1.4
    atm.Parent = Lighting
  end)
end

---------------------------------------------------------------- 地形

local TERRAIN_COLORS = { Grass = RGB(96, 146, 64), LeafyGrass = RGB(70, 124, 52), Sand = RGB(226, 208, 160), Rock = RGB(124, 118, 110), Slate = RGB(98, 98, 104), Ground = RGB(122, 98, 70) }

-- 一块 64 × 64 列（256 × 256 格）：按高度写体素，海平面以下没土的格子是水
local function writeChunk(T, x0, z0)
  local RES, N, D = Map.RES, 64, Map.SEA_DEPTH
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
  if ymax <= -D + 0.5 then return 0 end   -- 整块都是远海（海水、海底已经铺了）
  local yb0 = math.floor((math.max(ymin, -D) - RES) / RES)
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
    T.Decoration = false
  end)
  for m, c in pairs(TERRAIN_COLORS) do pcall(function() T:SetMaterialColor(MAT[m], c) end) end
  local TILE = 2048
  for x = -R, R - TILE, TILE do
    for z = -R, R - TILE, TILE do
      T:FillBlock(CF(x + TILE / 2, -D - 2, z + TILE / 2), V(TILE, 4, TILE), MAT.Sand)
      T:FillBlock(CF(x + TILE / 2, -D / 2, z + TILE / 2), V(TILE, D, TILE), MAT.Water)
    end
    task.wait()
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
  for n, c in ipairs(list) do
    total += writeChunk(T, c[1], c[2])
    if onProgress then onProgress(n / #list) end
    task.wait()
  end
  return total, #list
end

-- 地形范围外的远海：一圈平面（从岸上、飞机上看得到海一直铺到天边）
local function farSea(f)
  local R, S = Map.R, 2048
  for x = -R - 2 * S, R + S, S do
    for z = -R - 2 * S, R + S, S do
      if not (x >= -R and x < R and z >= -R and z < R) then
        local p = part(f, V(S, 1, S), CF(x + S / 2, -0.6, z + S / 2), RGB(30, 104, 128), MAT.Glass, nil, false)
        p.Transparency = 0.05
        p.Reflectance = 0.25
        p.CastShadow = false
      end
    end
  end
end

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

local function mast(f, x, z, h)   -- 天线杆：顶上红灯一闪一闪
  local y = Map.ground(x, z)
  cyl(f, h, 0.8, CF(x, y + h / 2, z), C.metal, MAT.Metal, true)
  local l = part(f, V(1.4, 1.4, 1.4), CF(x, y + h + 0.7, z), RGB(255, 40, 40), MAT.Neon, BALL)
  l:SetAttribute("Anim", "blink")
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
  part(f, V(A.len, 1, A.wid), base * CF(0, 0.45, 0), C.asphalt, MAT.Asphalt, nil, true)
  for i = -A.len / 2 + 20, A.len / 2 - 20, 30 do part(f, V(14, 0.1, 1.2), base * CF(i, 1, 0), C.white, MAT.SmoothPlastic) end
  for s = -1, 1, 2 do part(f, V(6, 0.1, A.wid - 8), base * CF(s * (A.len / 2 - 8), 1, 0), C.white, MAT.SmoothPlastic) end
  part(f, V(A.len * 0.6, 1, 70), base * CF(0, 0.45, -A.wid / 2 - 45), C.concrete, MAT.Concrete, nil, true)   -- 停机坪
  for i = -1, 1 do   -- 机库
    local hb = base * CF(i * 110, 0, -A.wid / 2 - 120)
    part(f, V(60, 18, 44), hb * CF(0, 9, 0), RGB(120, 126, 120), MAT.Metal, nil, true)
    part(f, V(60, 30, 30), hb * CF(0, 18, 0), RGB(110, 116, 110), MAT.Metal, CYL, true)   -- 半圆拱顶（圆柱一半埋在库房里）
  end
  local tb = base * CF(A.len / 2 - 40, 0, -A.wid / 2 - 110)   -- 塔台
  part(f, V(10, 26, 10), tb * CF(0, 13, 0), C.concrete, MAT.Concrete, nil, true)
  part(f, V(15, 7, 15), tb * CF(0, 29.5, 0), C.glass, MAT.Glass, nil, true)
  part(f, V(16, 1, 16), tb * CF(0, 33.5, 0), C.dark, MAT.Metal, nil, true)
  local _ = team
end

local function portTown(f)
  local P = Map.PORT
  -- 码头：从湾底伸进湾里
  local zs = Map.coastS(P.x) or P.z
  for i = -1, 1 do part(f, V(14, 2, 90), CF(P.x + i * 70, 1, zs + 40), C.wood, MAT.WoodPlanks, nil, true) end
  local spots = { { -60, -40, 22, 18, 14 }, { -20, -55, 18, 16, 20 }, { 25, -45, 26, 18, 12 }, { 65, -30, 20, 16, 16 }, { -70, 10, 18, 22, 10 },
    { 70, 15, 22, 18, 12 }, { -30, 40, 16, 14, 9 }, { 35, 45, 18, 14, 9 }, { -95, -75, 16, 16, 12 }, { 100, -70, 18, 16, 14 } }
  for k, s in ipairs(spots) do
    local x, z = P.x + s[1], P.z + s[2]
    if Map.isLand(x, z) then house(f, x, z, s[3], s[4], s[5], (k % 3) * 0.08, nil, (k % 2 == 0) and RGB(160, 80, 60) or RGB(70, 90, 110)) end
  end
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
  house(f, P.x - 50, P.z + 20, 30, 16, 10, 0, RGB(170, 176, 150), RGB(80, 90, 70))
  house(f, P.x + 50, P.z + 20, 30, 16, 10, 0, RGB(170, 176, 150), RGB(80, 90, 70))
  local y = Map.ground(P.x, P.z)
  cyl(f, 30, 0.8, CF(P.x, y + 15, P.z + 40), C.white, MAT.Metal, true)
end

local function lighthouse(f)
  local I = Map.LIGHTHOUSE
  local x, z = I.x + I.a * 0.55, I.z + 30   -- 东岸崖顶
  local y = Map.ground(x, z)
  for i = 0, 5 do cyl(f, 8, 12 - i * 0.6, CF(x, y + 4 + i * 8, z), (i % 2 == 0) and C.white or C.red, MAT.Concrete, true) end
  local lamp = part(f, V(6, 6, 6), CF(x, y + 51, z), RGB(255, 236, 160), MAT.Neon, BALL)
  lamp:SetAttribute("Anim", "blink")
  lamp:SetAttribute("Spd", 0.25)
  part(f, V(9, 1, 9), CF(x, y + 55, z), C.red, MAT.Metal, nil, true)
  house(f, x - 26, z + 10, 16, 12, 8, 0.2)
end

local function battery(f)   -- 西礁岛岸防炮台：营房（炮本身是 Forts 管的工事实体，能开火、能被打掉、玩家能操作）
  local I = Map.WESTREEF
  house(f, I.x - 50, I.z - 20, 20, 14, 8, 0.5, RGB(150, 150, 130), RGB(90, 96, 80))
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
    part(m, V(18, 36, D.L * 0.16), base * CF(ix, D.deck + 18, D.L * (D.island[1] - 0.5) + D.L * 0.3), RGB(108, 114, 118), MAT.Metal, nil, true)   -- 舰岛
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
  G.try("远海", farSea, folder("FarSea", root))
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
