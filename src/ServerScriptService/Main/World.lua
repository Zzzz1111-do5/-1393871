-- 全面大战场：地图——光影、地形（Map.lua 的高度按块写体素）、整片海水和海底、远海平面、
--   5 个据点（旗杆、旗、地上的圈、沙袋）、守方机场、港口镇（崖下的码头：挡土墙、坡道、木码头、吊车、集装箱堆场、油罐）、指挥所、北岸营地、灯塔、
--   西礁岛岸防炮台、攻方机场岛、攻方舰队（固定平台，打不掉）；细节（World.details）：防爆掩体、油库、雷达、HESCO 墙、瞭望塔、停机坪、
--   海滩后面的沙袋战壕、烧毁的坦克 / 卡车 / 登陆艇 / 直升机、路口检查站、镇上的路灯和车
--   都是锚定的静态零件；小装饰不挡人、不挡射线、不投影，省性能
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Map = require(RS:WaitForChild("Map"))
local AirDefs = require(RS:WaitForChild("AirDefs"))   -- 航母甲板（弹射器、拦阻索、轮廓）

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
-- 开了流式加载（Workspace.StreamingEnabled）：一栋房子整栋一起流进流出（不会先来了看不见的碰撞盒、墙还没到，或者只剩半栋）
local function atomic(m)
  pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
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
    Lighting.FogEnd = 100000   -- 视野放到很远（用户 11-22：「视野给我改成无限远」；远处的看不清改成客户端的景深模糊，DayNight.lua）
  end)
  pcall(function()
    local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
    atm.Density = 0.085   -- 原来 0.3、0.21（用户：视野很短；11-22 改成无限远）：客户端昼夜（DayNight.lua）按这个量级再调
    atm.Offset = 0.06
    atm.Color = Map.DESERT and RGB(70, 60, 54) or RGB(44, 54, 76)   -- 沙漠图：暖褐的沙尘夜空
    atm.Decay = Map.DESERT and RGB(22, 17, 14) or RGB(12, 15, 24)
    atm.Glare = 0.15
    atm.Haze = 0.5
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
-- LeafyGrass：草地（用户 11-21：坦克还是半截身子在地里——Roblox 会动的草叶只长在 Grass 材质上，脚本又改不了 Decoration / GrassLength，
--   writeChunk 把 Grass 都写成 LeafyGrass，染成原来草地的颜色）
local TERRAIN_COLORS = { Grass = RGB(96, 146, 64), LeafyGrass = RGB(98, 148, 64), Sand = RGB(226, 208, 160), Rock = RGB(124, 118, 110), Slate = RGB(98, 98, 104), Ground = RGB(122, 98, 70),
  Mud = RGB(54, 47, 40), Concrete = RGB(150, 148, 140), Asphalt = RGB(70, 72, 76) }   -- 水泥、柏油：港口的码头平地、坡道

---------------------------------------------------------------- 地形网格器校准
-- 用户 11-22：「无数个 AI 修了半天修不好，坦克半截身子卡在地里」。
--   车、机器人小兵、沙袋、工事全按 Map.height（一个数）摆；地形是 4 格见方的体素，最上面那个体素填几成（占有率）是我们写的，
--   画出来的地面到底在哪是 Roblox 的网格器定的——它不是「填几成，地面就在几成高」（2017 年有人试过一块全是一成满的体素，看着是满的；
--   2024 年有人把占有率乘 10 才去掉棱）。画出来的地面比 Map.height 高一截，车就像半截陷在地里，草叶去掉了也一样。
--   办法：开服写地图之前，在地图外面很深的地方（谁也看不见）写两排试验平台，最上面一层体素分别填 0、5%、10%……100%，
--   用射线量每块的地面实际在哪，得到「占有率 → 地面在这一层体素里几成高」的对照表；写地图时倒过来查：想让地面在 Map.height，
--   就填对照表里对应的占有率。量不出来（射线打不到、数不对）就照原来的写法，Output 里说一声。
--   量出来的表写在 Terrain 的属性 SurfCal 上（客户端性能面板、测试看），Output 里也打一行
local CAL_OCC = { 0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }
local CAL_PAD, CAL_GAP = 6, 4   -- 每块试验平台 6 × 6 列，平台之间空 4 列（边上的斜坡不影响中间）
local CAL = {}                  -- [材质名] = { o = {…}, s = {…} }：s 单调不减，s[1] 是全空（下面一层满）、s[#] 是这一层也满
local function calibrate(T, mats)
  local RES = Map.RES
  local SR = Map.SEA_R or Map.R
  local x0 = math.floor((SR + 2048) / RES) * RES   -- 地图外面
  local y0 = -2048                                  -- 很深：海底下面空着
  local z0 = 0
  local n = #CAL_OCC
  local NX, NY, NZ = n * (CAL_PAD + CAL_GAP), 5, #mats * (CAL_PAD + CAL_GAP)
  local M, O = table.create(NX), table.create(NX)
  for i = 1, NX do
    local Mi, Oi = table.create(NY), table.create(NY)
    for j = 1, NY do
      local mr, orow = table.create(NZ, MAT.Air), table.create(NZ, 0)
      Mi[j], Oi[j] = mr, orow
    end
    M[i], O[i] = Mi, Oi
  end
  -- 第 0、1 层满（底座），第 2 层是试验的那层（占有率按平台），第 3、4 层空
  for a = 0, n - 1 do
    for b = 0, #mats - 1 do
      for di = 0, CAL_PAD - 1 do
        for dk = 0, CAL_PAD - 1 do
          local i, k = a * (CAL_PAD + CAL_GAP) + di + 1, b * (CAL_PAD + CAL_GAP) + dk + 1
          M[i][1][k], O[i][1][k] = MAT.Ground, 1
          M[i][2][k], O[i][2][k] = mats[b + 1], 1
          local oc = CAL_OCC[a + 1]
          if oc > 0 then M[i][3][k], O[i][3][k] = mats[b + 1], oc end
        end
      end
    end
  end
  local reg = Region3.new(V(x0, y0, z0), V(x0 + NX * RES, y0 + NY * RES, z0 + NZ * RES))
  local okW = pcall(function() T:WriteVoxels(reg, RES, M, O) end)
  if not okW then return false, "写试验平台失败" end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances = { T }
  params.IgnoreWater = true
  local ybT = y0 + 2 * RES   -- 试验那层的底
  local res, why = nil, "射线打不到试验平台"
  for _ = 1, 40 do   -- 刚写的体素物理那边可能还没好：最多等两秒左右
    local all = {}
    local ok = true
    for b = 1, #mats do
      local o, sv = {}, {}
      for a = 1, n do
        local cx = x0 + ((a - 1) * (CAL_PAD + CAL_GAP) + CAL_PAD / 2) * RES
        local cz = z0 + ((b - 1) * (CAL_PAD + CAL_GAP) + CAL_PAD / 2) * RES
        local hit = workspace:Raycast(V(cx, y0 + NY * RES + 6, cz), V(0, -(NY * RES + 12), 0), params)
        if not hit then ok = false break end
        o[a], sv[a] = CAL_OCC[a], (hit.Position.Y - ybT) / RES
      end
      if not ok then break end
      all[mats[b].Name] = { o = o, s = sv }
    end
    if ok then res = all break end
    task.wait(0.05)
  end
  pcall(function() T:FillBlock(CFrame.new(reg.CFrame.Position), reg.Size + V(8, 8, 8), MAT.Air) end)   -- 量完拆掉
  if not res then return false, why end
  -- 检查：全空那块的地面在层底附近、全满那块正好高一层（换个位置的同一种摆法）；数值整理成单调不减
  for name, t in pairs(res) do
    local s0, s1 = t.s[1], t.s[#t.s]
    if math.abs(s0) > 0.8 or math.abs(s1 - s0 - 1) > 0.2 then
      return false, string.format("%s 量出来不对：全空 %.2f、全满 %.2f", name, s0, s1)
    end
    for a = 2, #t.s do t.s[a] = math.max(t.s[a], t.s[a - 1]) end
    t.s[#t.s] = t.s[1] + 1   -- 全满就是上一层全空：按定义对齐
  end
  return true, res
end
-- 想让地面在高度 h：返回最上面那层体素的序号（y / RES 向下取整的那种）和它的占有率；这层下面全满、上面全空。
--   没校准：同原来的写法（地面在几成高就填几成，最少 5%）
local function surfAt(h, t)
  local x = h / Map.RES
  if not t then
    local j = math.floor(x)
    local f = x - j
    if f <= 1e-6 then return j, 0 end
    return j, math.max(f, 0.05)
  end
  local s, o = t.s, t.o
  local j = math.floor(x - s[1])
  local g = x - j   -- 在 [s0, s0 + 1) 里
  if g <= s[1] then return j, 0 end
  for a = 2, #s do
    if g <= s[a] then
      local s0, s1 = s[a - 1], s[a]
      if a == 2 and s1 - s0 > 0.1 then   -- 全空和最小的一档之间差得多（网格器画不出这么薄）：挑近的那个
        return j, ((g - s0) < (s1 - g)) and 0 or o[2]
      end
      if s1 - s0 < 1e-4 then return j, o[a] end
      return j, o[a - 1] + (g - s0) / (s1 - s0) * (o[a] - o[a - 1])
    end
  end
  return j, 1
end
local function calFor(mat) return CAL[mat.Name] or CAL.LeafyGrass end
World.surfAt = function(h, matName) return surfAt(h, matName and (CAL[matName] or CAL.LeafyGrass) or CAL.LeafyGrass) end   -- 测试用
World.terrainCal = function() return CAL end

-- 一块 64 × 64 列（256 × 256 格）：按高度写体素，海平面以下没土的格子是水。
--   n、yFloor（Battle.lua 填弹坑用）：只写 n × n 列的一小块，至少从 yFloor 往上写（坑底比这一小块里最低的地面还深）
local function writeChunk(T, x0, z0, n, yFloor, baseY)
  local RES, N, D = Map.RES, n or 64, Map.SEA_DEPTH
  if Map.colCache then Map.colCache(true) end   -- 沙漠图：先算的高度顺手记下地貌，定材质时不用再算一遍
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
  if ymax <= -DW + 0.5 then   -- 整块都比 30 格深（海水、海底已经铺了）
    if Map.colCache then Map.colCache(false) end
    return 0
  end
  local yb0 = math.floor((math.max(ymin, -DW) - RES) / RES)
  if yFloor then yb0 = math.min(yb0, math.floor(yFloor / RES)) end
  local yb1 = math.ceil((math.max(ymax, 0) + RES) / RES)
  local NY = yb1 - yb0
  if baseY and yb0 * RES > baseY then   -- 沙漠：下面没灌海水，补一块实心的底（弹坑挖不穿）
    T:FillBlock(CFrame.new(x0 + N * RES / 2, (baseY + yb0 * RES) / 2, z0 + N * RES / 2), V(N * RES, yb0 * RES - baseY, N * RES), MAT.Sand)
  end
  local M, O = table.create(N), table.create(N)
  for i = 1, N do
    local Mi, Oi = table.create(NY), table.create(NY)
    for j = 1, NY do Mi[j], Oi[j] = table.create(N), table.create(N) end
    M[i], O[i] = Mi, Oi
  end
  local Water, Air, Sand, Ground, Rock = MAT.Water, MAT.Air, MAT.Sand, MAT.Ground, MAT.Rock
  local Grass, Leafy = MAT.Grass, MAT.LeafyGrass
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
        -- 草地：图上开了 Map.GRASS（海岛，用户 11-24 发截图「这种草给海岛地图加上」）照写 Grass，长 Roblox 会动的草叶——
        --   开关（Terrain.Decoration）和草长（GrassLength）脚本改不了，地点文件里的 Terrain 写好了（tools/build.luau）；
        --   别的图写成 LeafyGrass（不长草叶；用户 11-21 嫌草叶盖住履带、车轮、小人的腿，看着像半截身子在地里）
        if top == Grass and not Map.GRASS then top = Leafy end
      end
      local under = Map.underMat and Map.underMat(top) or ((h > 20) and Rock or (h > 0.3 and Ground or Sand))
      -- 最上面那层：序号 jT、占有率 oT（按开服量的网格器对照表，地面画出来正好在 h；没量出来同原来的写法）
      local jT, oT = surfAt(h, calFor(top))
      for j = 0, NY - 1 do
        local ja = yb0 + j
        local yb = ja * RES
        local m, o
        if ja < jT then
          m, o = (yb + RES > h - 5) and top or under, 1
        elseif ja == jT and oT > 0 then
          m, o = top, math.min(oT, 1)
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
  if Map.colCache then Map.colCache(false) end
  local region = Region3.new(V(x0, yb0 * RES, z0), V(x0 + N * RES, yb1 * RES, z0 + N * RES))
  T:WriteVoxels(region, RES, M, O)
  return N * N * NY
end

-- 沙漠地图（沙海 MapSands：没有海）：按 2048 格一大块、里面 8 × 8 个 256 格小块看；平地小块按矩形合并成尽量大的一次 FillBlock，
--   有起伏的小块逐列写体素。
-- 开服前只写两边主基地一带（Map.CORES，出生只在自己基地），写完就让人出生；其余全在后台一小份一小份写（每帧 4 毫秒左右），顺序：
--   ① 插队：真人、机器人、车、飞机身边（±6 个小块，约 1500 格）还没写的，先写；② 据点一带（Map.HOTS）写全；
--   ③ 全图的平地（起伏块先垫一层薄底，不是窟窿）；④ 剩下的起伏块，离据点近的先。
-- 用户 11-24 晚：「目前游戏的优化没有效果 沙海地图还是加载不出来」——卡在「正在生成地图……%」：原来开服前要把全图平地都铺完
--   （3 万多次 FillBlock、16 亿个体素，进度条涨 1% 要铺一千多次），Roblox 里地形引擎铺这些远比算高度慢；现在开服前只剩基地一带几百次
-- 地底只填到这里（原来 −40：整张图平地填 13 层体素——用户 11-24「沙海加载时间太长」；弹坑最深 5.5 格（Config.Battle.crater.maxDepth），16 格厚的地壳够了）
local DESERT_BASE = -4
local function terrainDesert(T, onProgress, G)
  local SR, TILE, CH = Map.SEA_R, 2048, 256
  local NT = math.floor(2 * SR / TILE)   -- 一边几个大块
  local PH = (Map.PLAIN or 12) - 8       -- 垫底那层的顶
  local PLAY = Map.PLAY or SR
  local diag = { fills = 0, vox = 0, fillT = 0, chunks = 0, chunkT = 0, bgMax = 0, bgFills = 0, bgPieces = 0 }
  local t0 = os.clock()
  local budget = 0.03   -- 让一帧：开服前 30 毫秒一让，后台 4 毫秒一让（开打以后服务器不卡）
  local function pace(b)
    if os.clock() - t0 > (b or budget) then task.wait() t0 = os.clock() end
  end
  -- 后台（开打以后）：一次只铺一小份、每份之后看一眼——用户 11-25「把抽搐bug弄完」：11-22 那条「加载地图的时候坦克飞机抽搐」又回来了，
  --   这回是后台写地形：平地按矩形合并成一次 FillBlock，最大一次 2048 × 2048 × 16 格（一百万体素），Roblox 铺这么一块要几十上百毫秒，
  --   「每帧 8 毫秒」拦不住单次调用——服务器停一下，车、飞机、人的同步跟着一顿；插队扫描每半秒把所有人身边 ±6 块的地貌一口气算完也是。
  --   现在后台的平地切成 bgSide 见方一块块铺（量着每次的耗时自己调：超过 6 毫秒减半、不到 1.5 毫秒加倍，64～512 格），起伏块 16 × 16 列一份，
  --   扫描算地貌也分着算；每份之后超了 4 毫秒就让一帧。测试台的 os.clock 是模拟时钟（同一步里不走），再按份数让（8 份一让）
  local bg, bgSide, since = false, 256, 0
  local function step()
    since += 1
    if os.clock() - t0 > budget or since >= 8 then task.wait() t0 = os.clock() since = 0 end
  end
  -- Roblox 论坛（2025-02，Roblox 员工）：Terrain 的 SmoothVoxelsUpgraded 是没做完的功能，开着时 FillBlock 慢几千到几万倍，要关着——读得到就查一下
  do
    local okS, sv = pcall(function() return T.SmoothVoxelsUpgraded end)
    if okS and sv == true then
      warn("[地形] Workspace → Terrain 的 SmoothVoxelsUpgraded 开着：写地形会慢几千倍（地图生成卡住）。在 Studio 里选中 Terrain，属性里取消勾选再保存")
    end
  end
  local function fill(x0, z0, w, d, y, mat)
    -- 作战区里地壳 16 格厚（弹坑挖不穿）；作战区外面那一圈只是远景，8 格（PLAY 正好落在 2048 的格线上，一个大块不会跨两边）
    local inner = math.abs(x0 + w / 2) < PLAY and math.abs(z0 + d / 2) < PLAY
    local yb = math.max(math.min(DESERT_BASE, y - 8), y - (inner and 16 or 8))
    while yb < y do   -- 一次 FillBlock 别超过四百万体素：按 60 格一层（2048 × 2048 × 60 格 ≈ 390 万）
      local h = math.min(60, y - yb)
      if not bg then
        local c0 = os.clock()
        T:FillBlock(CF(x0 + w / 2, yb + h / 2, z0 + d / 2), V(w, h, d), mat)
        diag.fills += 1
        diag.vox += (w / 4) * (h / 4) * (d / 4)
        diag.fillT += os.clock() - c0
        pace()
      else   -- 后台：切成 bgSide 见方一块块铺
        local xs = 0
        while xs < w do
          local ww = math.min(bgSide, w - xs)
          local zs = 0
          while zs < d do
            local dd = math.min(bgSide, d - zs)
            local c0 = os.clock()
            T:FillBlock(CF(x0 + xs + ww / 2, yb + h / 2, z0 + zs + dd / 2), V(ww, h, dd), mat)
            local dt = os.clock() - c0
            diag.fills += 1
            diag.bgFills += 1
            diag.vox += (ww / 4) * (h / 4) * (dd / 4)
            diag.fillT += dt
            if dt > diag.bgMax then diag.bgMax = dt end
            if dt > 0.006 and bgSide > 64 then bgSide //= 2 elseif dt < 0.0015 and bgSide < 512 then bgSide *= 2 end
            diag.side = bgSide
            zs += dd
            step()
          end
          xs += ww
        end
      end
      yb += h
    end
  end
  local function relief(x0, z0, n)
    local c0 = os.clock()
    local v = writeChunk(T, x0, z0, n, nil, DESERT_BASE)
    diag.chunks += 1
    diag.chunkT += os.clock() - c0
    return v
  end
  -- 后台的一个起伏小块（256 格见方）：分 16 份写（64 格见方、16 × 16 列），每份之后看一眼
  local function reliefBg(x0, z0)
    for q = 0, 15 do
      relief(x0 + (q % 4) * 64, z0 + (q // 4) * 64, 16)
      diag.bgPieces += 1
      step()
    end
  end
  local function tileOf(x, z) return math.floor((x + SR) / TILE), math.floor((z + SR) / TILE) end
  local function ckey(x0, z0) return x0 * 1048576 + z0 end
  -- 到一组圈（核心区 / 据点）圈边多远
  local function distTo(list, x, z)
    local best = math.huge
    for _, C in ipairs(list) do best = math.min(best, math.sqrt((x - C.x) ^ 2 + (z - C.z) ^ 2) - C.r) end
    return best
  end
  local cores = Map.CORES or { Map.CORE or { x = 0, z = 0, r = 12000 } }
  local hots = Map.HOTS or cores

  -- 一个大块的平地：8 × 8 小块分类，同一级、同材质的平地小块贪心合并成矩形一次 FillBlock；起伏小块（没写过的）先垫一层薄底、交出去
  local tileDone, reliefDone, kindOf = {}, {}, {}
  local function kindAt(x0, z0)   -- Map.chunkKind 要在块里打 81 个点：算过的记下来（插队扫描每半秒要看几百块）
    local k = ckey(x0, z0)
    local v = kindOf[k]
    if v == nil then
      local kind, L, M = Map.chunkKind(x0, z0)
      v = (kind == "flat") and { L, M } or false
      kindOf[k] = v
    end
    return v
  end
  local function tileFlat(ix, iz, onRelief)
    local tk = ix * 4096 + iz
    if tileDone[tk] then return false end
    tileDone[tk] = true
    local tx, tz = -SR + ix * TILE, -SR + iz * TILE
    local K = table.create(64)
    for i = 0, 7 do
      for k = 0, 7 do
        K[i * 8 + k + 1] = kindAt(tx + i * CH, tz + k * CH)
      end
    end
    local used = {}
    local function same(i, k, e)
      local f = K[i * 8 + k + 1]
      return f and not used[i * 8 + k] and f[1] == e[1] and f[2] == e[2]
    end
    for k = 0, 7 do
      for i = 0, 7 do
        local e = K[i * 8 + k + 1]
        if e and not used[i * 8 + k] then
          local i1 = i
          while i1 < 7 and same(i1 + 1, k, e) do i1 += 1 end
          local k1, grow = k, true
          while grow and k1 < 7 do
            for ii = i, i1 do
              if not same(ii, k1 + 1, e) then grow = false break end
            end
            if grow then k1 += 1 end
          end
          for ii = i, i1 do for kk = k, k1 do used[ii * 8 + kk] = true end end
          fill(tx + i * CH, tz + k * CH, (i1 - i + 1) * CH, (k1 - k + 1) * CH, e[1], e[2])
        elseif not e then
          local x0, z0 = tx + i * CH, tz + k * CH
          -- onRelief 返回 true：这块马上就写全，不用垫；否则先垫一层薄底——后台写到它之前这里不是个窟窿（车、人不会掉下去，天上看不到洞）
          if not reliefDone[ckey(x0, z0)] and not (onRelief and onRelief(x0, z0)) then
            T:FillBlock(CF(x0 + CH / 2, PH - 2, z0 + CH / 2), V(CH, 4, CH), MAT.Sand)
            diag.fills += 1
            if bg then step() else pace() end
          end
        end
      end
    end
    return true
  end

  -- ① 开服前：两边基地一带（核心圈碰到的大块铺平地，圈里的起伏块写全）
  local coreTiles, coreSet, coreRelief = {}, {}, {}
  for _, C in ipairs(cores) do
    local a0, b0 = tileOf(C.x - C.r - CH, C.z - C.r - CH)
    local a1, b1 = tileOf(C.x + C.r + CH, C.z + C.r + CH)
    for ix = math.max(0, a0), math.min(NT - 1, a1) do
      for iz = math.max(0, b0), math.min(NT - 1, b1) do
        local tk = ix * 4096 + iz
        if not coreSet[tk] then
          coreSet[tk] = true
          table.insert(coreTiles, { ix, iz })
        end
      end
    end
  end
  local laterRelief = {}   -- 核心大块里、圈外面的起伏块：交给后台
  local nPre = #coreTiles
  local doneUnits = 0
  for _, t in ipairs(coreTiles) do
    tileFlat(t[1], t[2], function(x0, z0)
      if distTo(cores, x0 + CH / 2, z0 + CH / 2) <= CH then
        table.insert(coreRelief, { x0, z0 })
        return true
      end
      table.insert(laterRelief, { x0, z0 })
      return false
    end)
    doneUnits += 1
    if onProgress then onProgress(0.3 * doneUnits / math.max(1, nPre)) end
    pace(0.03)
  end
  table.sort(coreRelief, function(a, b) return distTo(cores, a[1], a[2]) < distTo(cores, b[1], b[2]) end)
  local total = 0
  for n, c in ipairs(coreRelief) do
    reliefDone[ckey(c[1], c[2])] = true
    total += relief(c[1], c[2])
    if onProgress then onProgress(0.3 + 0.7 * n / #coreRelief) end
    if n % 2 == 0 then task.wait() t0 = os.clock() else pace(0.03) end   -- 也按块数让：测试台里 os.clock 是模拟时钟，同一步里不走
  end
  print(string.format("[地形] 开服前写了基地一带：%d 次 FillBlock（%.2f 亿体素，共 %.1f 秒，平均每次 %.1f 毫秒）、%d 块起伏（共 %.1f 秒，平均每块 %.0f 毫秒）",
    diag.fills, diag.vox / 1e8, diag.fillT, diag.fills > 0 and diag.fillT * 1000 / diag.fills or 0, diag.chunks, diag.chunkT, diag.chunks > 0 and diag.chunkT * 1000 / diag.chunks or 0))
  if diag.fills > 20 and diag.fillT * 1000 / diag.fills > 40 then
    warn("[地形] Roblox 写地形特别慢（每次 FillBlock 平均 " .. math.floor(diag.fillT * 1000 / diag.fills) .. " 毫秒）：在 Studio 里看一下 Workspace → Terrain 的属性"
      .. "，SmoothVoxelsUpgraded 要是勾着，取消勾（Roblox 说这是没做完的功能，开着地形操作慢几千倍）")
  end
  if G then G.terrainDiag = diag end

  -- 后台：剩下的大块、起伏块
  local tilesLeft, reliefQ = {}, {}
  for ix = 0, NT - 1 do
    for iz = 0, NT - 1 do
      if not tileDone[ix * 4096 + iz] then
        local cx, cz = -SR + (ix + 0.5) * TILE, -SR + (iz + 0.5) * TILE
        table.insert(tilesLeft, { ix, iz, distTo(hots, cx, cz) })
      end
    end
  end
  table.sort(tilesLeft, function(a, b) return a[3] < b[3] end)
  local function queueRelief(x0, z0)
    if not reliefDone[ckey(x0, z0)] then table.insert(reliefQ, { x0, z0, distTo(hots, x0 + CH / 2, z0 + CH / 2) }) end
  end
  for _, c in ipairs(laterRelief) do queueRelief(c[1], c[2]) end
  if G then G.terrainRest, G.terrainTilesLeft = #tilesLeft + #reliefQ, #tilesLeft end
  task.spawn(function()
    local Players = game:GetService("Players")
    budget = 0.004
    bg = true
    local urgentTiles, urgentRelief = {}, {}
    local seen = {}
    local function want(p)   -- 这一点身边 ±6 个小块：还没铺的大块、还没写的起伏块排进插队
      local cx0, cz0 = math.floor(p.X / CH), math.floor(p.Z / CH)
      local here = ckey(cx0, cz0)
      if seen[here] then return end   -- 好几个人挤在同一块：看一次就够
      seen[here] = true
      for dx = -6, 6 do
        for dz = -6, 6 do
          local x0, z0 = (cx0 + dx) * CH, (cz0 + dz) * CH
          if math.abs(x0 + CH / 2) < SR and math.abs(z0 + CH / 2) < SR then
            local ix, iz = tileOf(x0 + 1, z0 + 1)
            if not tileDone[ix * 4096 + iz] then urgentTiles[ix * 4096 + iz] = { ix, iz } end
            local k = ckey(x0, z0)
            if kindOf[k] == nil then step() end   -- 这块的地貌还没算过（要打 81 个点）：算之前看一眼预算，扫描不再一口气算几千个点
            if not reliefDone[k] and not urgentRelief[k] and kindAt(x0, z0) == false then urgentRelief[k] = { x0, z0, (dx * dx + dz * dz) } end
          end
        end
      end
    end
    local function scan()
      table.clear(seen)
      for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp then want(hrp.CFrame.Position) end
      end
      for _, e in ipairs(G and G.ents or {}) do   -- 机器人、车、飞机（飞得高的不管：底下没铺好看着是远景，不会掉下去）
        if e.alive and e.root and e.root.Parent then
          local p = e.root.CFrame.Position
          if not e.air or p.Y < (Map.PLAIN or 12) + 600 then want(p) end
        end
      end
    end
    local function urgentStep()
      for k, t in pairs(urgentTiles) do
        urgentTiles[k] = nil
        if tileFlat(t[1], t[2], queueRelief) then return true end
      end
      local best, bk = nil, nil
      for k, c in pairs(urgentRelief) do
        if reliefDone[k] then urgentRelief[k] = nil
        elseif not best or c[3] < best[3] then best, bk = c, k end
      end
      if best then
        urgentRelief[bk] = nil
        reliefDone[bk] = true
        reliefBg(best[1], best[2])
        return true
      end
      return false
    end
    local scanAt, ti, ri, sorted = 0, 1, 1, false
    while true do
      if os.clock() >= scanAt then
        scanAt = os.clock() + 0.5
        local okS, errS = pcall(scan)   -- 扫描出错（某个实体的零件刚被删之类）不能把整个后台写地形停掉
        if not okS then warn("[地形] 插队扫描出错：" .. tostring(errS)) end
      end
      if not urgentStep() then
        if ti <= #tilesLeft then
          -- ②③ 大块：据点一带的先（tilesLeft 按离据点的距离排好了）；据点圈里的起伏块跟着写全
          local t = tilesLeft[ti]
          ti += 1
          local hot = t[3] <= TILE
          local did = tileFlat(t[1], t[2], function(x0, z0)
            if hot and distTo(hots, x0 + CH / 2, z0 + CH / 2) <= 0 then
              reliefDone[ckey(x0, z0)] = true
              reliefBg(x0, z0)
              return true
            end
            queueRelief(x0, z0)
            return false
          end)
          if did then   -- 插队时已经铺过的大块：不白等一帧
            task.wait()
            t0 = os.clock()
          end
        else
          -- ④ 剩下的起伏块：离据点近的先
          if not sorted then
            sorted = true
            table.sort(reliefQ, function(a, b) return a[3] < b[3] end)
          end
          local c = reliefQ[ri]
          if not c then break end
          ri += 1
          local k = ckey(c[1], c[2])
          if not reliefDone[k] then
            reliefDone[k] = true
            reliefBg(c[1], c[2])
          end
        end
      end
      if G then
        G.terrainRest = math.max(0, #tilesLeft - ti + 1) + math.max(0, #reliefQ - ri + 1)
        G.terrainTilesLeft = math.max(0, #tilesLeft - ti + 1)   -- 还没铺的大块（只减不增；terrainRest 里的起伏块是铺大块时才排进来的）
      end
    end
    if G then G.terrainRest = 0 end
    print(string.format("[地形] 后台写完：一共 %d 次 FillBlock（%.2f 亿体素）、%d 块起伏；后台单次 FillBlock 最长 %.1f 毫秒，小块边长最后 %d 格",
      diag.fills, diag.vox / 1e8, diag.chunks, diag.bgMax * 1000, bgSide))
  end)
  return total, #coreRelief + #reliefQ
end

-- 整个地形：海底沙、海水（分块 FillBlock），再按块写岛（每块之间让出一帧）；返回写了多少体素
function World.terrain(onProgress, G)
  local T = workspace.Terrain
  local R, D = Map.R, Map.SEA_DEPTH
  pcall(function()
    T.WaterColor = RGB(30, 112, 136)
    T.WaterTransparency = 0.5
    T.WaterReflectance = 0.5
    T.WaterWaveSize = 0.15
    T.WaterWaveSpeed = 8
    -- 地形草叶：Roblox 不许脚本改 GrassLength、Decoration（文档写着 Not Scriptable，一改就报错，被 pcall 吞了；以前调过的 0.55 / 0.45 / 0.28 / 0.22、
    --   关 Decoration 都没生效）。用户 11-21 嫌草叶盖住车：writeChunk 改写 LeafyGrass（不长草叶）；用户 11-24 又要回来（发了截图）：
    --   海岛图（Map.GRASS）照写 Grass，开关、草长写在地点文件的 Terrain 上（tools/build.luau：Decoration 开、GrassLength 1）
  end)
  for m, c in pairs(Map.COLORS or TERRAIN_COLORS) do pcall(function() T:SetMaterialColor(MAT[m], c) end) end
  -- 先量网格器（见上面 calibrate）：量出来的对照表写地图时用
  do
    local calMats = Map.GRASS and { MAT.Grass, MAT.LeafyGrass, MAT.Sand } or { MAT.LeafyGrass, MAT.Sand }   -- 长草叶的图草地写 Grass：也量它
    local okC, res = calibrate(T, calMats)
    if okC then
      CAL = res
      local parts = {}
      for _, name in ipairs({ "Grass", "LeafyGrass", "Sand" }) do
        local t = res[name]
        if t then
          local bits = {}
          for a = 1, #t.o do table.insert(bits, string.format("%g:%.2f", t.o[a], t.s[a])) end
          table.insert(parts, name .. "=" .. table.concat(bits, ","))
        end
      end
      local str = table.concat(parts, ";")
      pcall(function() T:SetAttribute("SurfCal", str) end)
      print("[地形] 网格器校准：占有率 → 地面在体素里几成高（" .. str .. "）")
    else
      CAL = {}
      pcall(function() T:SetAttribute("SurfCal", "fail:" .. tostring(res)) end)
      warn("[地形] 网格器校准没做成（" .. tostring(res) .. "）：照原来的写法")
    end
  end
  if Map.chunkKind then return terrainDesert(T, onProgress, G) end
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

World.writeChunk = function(T, x0, z0, n, yFloor)   -- 填坑（Battle.lua、Nuke.lua）：按当前地图的写法
  return writeChunk(T, x0, z0, n, yFloor)
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
  atomic(m)
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
-- 开了 streaming（地点文件的 Workspace.StreamingEnabled）也一直留在每个客户端上：据点（远处九千格就看得见旗杆上的字母）、舰队（航母甲板上站着人、远处就看得见）
local function persist(m)
  pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
end

function World.points(f)
  local list = {}
  for _, p in ipairs(Map.POINTS) do
    local m = Instance.new("Model")
    m.Name = "Point_" .. p.id
    local y = Map.ground(p.x, p.z)
    local ring = part(m, V(0.3, Map.POINT_R * 2, Map.POINT_R * 2), CF(p.x, y + 0.2, p.z) * UP, RGB(64, 186, 92), MAT.Neon, CYL)   -- 开局归守方：守方的绿（同 Config.Teams.def）
    ring.Name = "Ring"
    ring.Transparency = 0.82
    local pole = cyl(m, 34, 0.9, CF(p.x, y + 17, p.z), C.white, MAT.Metal, true)
    pole.Name = "Pole"
    local flag = part(m, V(10, 6, 0.3), CF(p.x + 5.4, y + 30, p.z), RGB(64, 186, 92), MAT.Fabric)
    flag.Name = "Flag"
    local _, lbl = sign(pole, p.id, 24, 9, 9, Color3.new(1, 1, 1), 9000)
    lbl.Name = "Letter"
    sandbags(m, V(p.x, 0, p.z), 16, 0.3, 2.4, 3)
    sandbags(m, V(p.x, 0, p.z), 16, 3.5, 5.6, 3)
    m:SetAttribute("Id", p.id)
    m:SetAttribute("Owner", "def")
    persist(m)
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
  local H = Map.HARBOR
  local zs, qy = H.zs, H.y
  local function R(x, y, z) return V(P.x + x, y, zs + z) end   -- 码头这一片的相对坐标：x 从镇中心往东、z 从湾底岸线往南
  local hf = folder("Harbor", f)
  ---------------- 挡土墙（用户 11-20：地图不够好、有 bug）：地形切出来的直壁是一面土崖，贴一层水泥墙面；墙顶比崖顶高一点当护栏
  local WALL = RGB(146, 144, 136)
  local function wallLine(x0, z0, x1, z1, ix, iz)   -- 一段直的挡土墙（相对坐标）：ix, iz 朝码头里（墙贴着崖面、往里 3 格厚）
    local dx, dz = x1 - x0, z1 - z0
    local len = math.sqrt(dx * dx + dz * dz)
    local n = math.max(1, math.ceil(len / 24))
    local look = V(dx, 0, dz).Unit
    for i = 0, n - 1 do
      local m = (i + 0.5) / n
      local cx, cz = x0 + dx * m, z0 + dz * m
      local top = Map.height(P.x + cx - ix * 5, zs + cz - iz * 5)   -- 墙外头的崖顶
      if top > qy + 3 then
        local h = top + 1.2 - (qy - 1)
        local c = R(cx + ix * 1.5, qy - 1 + h / 2, cz + iz * 1.5)
        part(hf, V(3, h, len / n + 0.05), CFrame.lookAt(c, c + look), WALL:Lerp(RGB(118, 116, 108), ((i * 37) % 5) / 10), MAT.Concrete, nil, true)
      end
    end
  end
  wallLine(-210, -70, -205, -70, 0, 1)    -- 码头北边西头一小截
  wallLine(-205, -98, -205, -70, 1, 0)    -- 坡道西头（车从码头拐进坡道的那块平地）的西墙
  wallLine(-205, -98, -170, -98, 0, 1)    -- 那块平地的北墙
  wallLine(-210, -70, -210, 40, 1, 0)     -- 西
  wallLine(210, -70, 210, 40, -1, 0)      -- 东
  wallLine(180, -70, 210, -70, 0, 1)      -- 码头北边东头（坡道顶以东）
  wallLine(-210, 40, -100, 40, 0, -1)     -- 西南：码头平地南头接回崖
  wallLine(125, 40, 210, 40, 0, -1)       -- 东南
  -- 坡道：贴着码头北边的挡土墙，西头跟码头一样高、往东爬到崖顶（Map.HARBOR）
  local top = H.townY or 73.8
  local ax, bx = H.a.x - P.x, H.b.x - P.x
  local k = (top - qy) / (bx - ax)   -- 每格升多少
  local function rampY(x) return qy + (top - qy) * math.clamp((x - ax) / (bx - ax), 0, 1) end
  do   -- 靠山那面墙：顶是平的（崖顶 + 护栏），底顺着坡面（埋进去 1 格）
    local ytop, y0 = top + 1.2, qy - 1
    local h = ytop - y0
    local L = h / k
    wedge(hf, V(3, h, L), CF(R(ax + L / 2, ytop - h / 2, -96.5)) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi), WALL, MAT.Concrete, true)
  end
  do   -- 靠码头那面挡土墙：底是平的（码头平地），顶顺着坡面
    local y0, yt = qy - 1, top + 0.3
    local h = yt - y0
    local L = h / k
    wedge(hf, V(3, h, L), CF(R(bx - L / 2, y0 + h / 2, -68.5)) * CFrame.Angles(0, math.pi / 2, 0), WALL, MAT.Concrete, true)
    local a, b = R(-150, rampY(-150) + 0.5, -71.2), R(bx, rampY(bx) + 0.5, -71.2)   -- 坡道外沿的护栏（西头低的那段不要：车从那里拐上来）
    part(hf, V(1.2, 2.2, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), RGB(172, 170, 162), MAT.Concrete, nil, true)
  end
  for x = -150, 170, 64 do light(hf, R(x, rampY(x) + 9, -94.6), RGB(255, 178, 100), 0.6, 30, 1.1, nil, 3) end   -- 坡道的壁灯
  ---------------- 木码头：两条，湾底中间那条水道留给登陆艇冲滩；码头面跟码头平地齐平（原来比水面高 2 格、码头平地又在崖底下）
  local DY = H.deck
  for _, px in ipairs({ -70, 70 }) do
    part(hf, V(14, 1.2, 90), CF(R(px, DY - 0.6, 40)), C.wood, MAT.WoodPlanks, nil, true)
    for _, sx in ipairs({ -1, 1 }) do
      part(hf, V(0.9, 1.6, 90), CF(R(px + sx * 7.3, DY - 0.9, 40)), RGB(78, 62, 46), MAT.Wood)   -- 两边的护木
      for kk = 0, 3 do   -- 木桩：打到海底（用户 11-18：这些建筑漂在水里）
        local x, z = px + sx * 6, 3 + kk * 25
        local bed = Map.height(P.x + x, zs + z)
        if bed < DY - 2.5 then
          bed = math.max(bed, -40) - 1
          local t = DY - 1.2
          cyl(hf, t - bed, 1.1, CF(R(x, (t + bed) / 2, z)), RGB(70, 58, 44), MAT.Wood, true)
        end
      end
      for z = 22, 84, 20 do cyl(hf, 1.5, 1.3, CF(R(px + sx * 5.8, DY + 0.75, z)), RGB(40, 42, 44), MAT.Metal) end   -- 系缆桩
      for z = 28, 80, 26 do part(hf, V(1, 2.6, 2.6), CF(R(px + sx * 8, DY - 1.6, z)), RGB(30, 30, 32), MAT.SmoothPlastic, CYL) end   -- 挂在码头边上的旧轮胎
    end
    cyl(hf, 9, 0.5, CF(R(px + 5, DY + 4.5, 83)), RGB(60, 62, 66), MAT.Metal, true)   -- 码头头上的灯
    light(hf, R(px + 5, DY + 9.2, 83), RGB(255, 206, 150), 0.6, 36, 1.2, nil, 3)
  end
  ---------------- 门座式吊车：四条腿的门架、转台机房、配重、司机室、斜伸出去的吊臂、人字架和拉索、钢缆吊钩；站在东边木码头根旁，吊臂伸到码头上头
  do
    local pos, tgt = R(95, qy, 18), R(70, qy, 62)
    local base = CFrame.lookAt(pos, tgt)
    local Y = RGB(222, 170, 40)
    for _, o in ipairs({ { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } }) do part(hf, V(1.3, 14, 1.3), base * CF(o[1], 7, o[2]), Y, MAT.Metal, nil, true) end
    part(hf, V(12, 1.6, 12), base * CF(0, 14.8, 0), Y, MAT.Metal, nil, true)
    for _, sz in ipairs({ -5, 5 }) do   -- 门架的斜撑
      local a, b = (base * CF(-5, 1, sz)).Position, (base * CF(5, 13, sz)).Position
      part(hf, V(0.5, 0.5, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Y, MAT.Metal)
    end
    part(hf, V(8, 6, 9), base * CF(0, 18.6, 1), Y, MAT.Metal, nil, true)                 -- 机房
    part(hf, V(7, 4, 3), base * CF(0, 18, 6.8), RGB(70, 72, 76), MAT.Metal, nil, true)    -- 配重
    local cab = part(hf, V(3.4, 3.4, 3.4), base * CF(-3.4, 17.6, -4.6), C.glass, MAT.Glass)   -- 司机室
    cab.Transparency = 0.2
    local piv = base * CF(0, 20, -3)
    local LEN, ang = 46, math.rad(30)
    local p0, p1 = piv.Position, (piv * CF(0, math.sin(ang) * LEN, -math.cos(ang) * LEN)).Position
    part(hf, V(1.8, 1.8, LEN), CFrame.lookAt((p0 + p1) / 2, p1), Y, MAT.Metal, nil, true)   -- 吊臂
    part(hf, V(1, 7, 1), base * CF(0, 25, 2), Y, MAT.Metal)                               -- 人字架
    local mt = (base * CF(0, 28.3, 2)).Position
    part(hf, V(0.25, 0.25, (p1 - mt).Magnitude), CFrame.lookAt((mt + p1) / 2, p1), RGB(30, 30, 32), MAT.Metal)   -- 拉索
    local hookY = qy + 9
    part(hf, V(0.22, p1.Y - hookY, 0.22), CF(p1.X, (p1.Y + hookY) / 2, p1.Z), RGB(30, 30, 32), MAT.Metal)   -- 钢缆
    part(hf, V(1.4, 1.8, 1.4), CF(p1.X, hookY - 0.9, p1.Z), RGB(200, 60, 40), MAT.Metal)                  -- 吊钩
    local l = light(hf, p1 + V(0, 1.2, 0), RGB(255, 40, 40), 0.7, nil, nil, nil, 3)
    l:SetAttribute("Anim", "blink")
    l:SetAttribute("Spd", 0.7)
  end
  ---------------- 集装箱堆场（码头西头、东头）：一层层摞着，门那头一块深色门板；能当掩体
  local CCOL = { RGB(150, 64, 48), RGB(48, 84, 124), RGB(60, 104, 74), RGB(186, 112, 44), RGB(128, 132, 134), RGB(196, 194, 186), RGB(112, 40, 42), RGB(40, 112, 124) }
  local ci = 0
  local function box(x, z, tier, long)
    ci += 1
    local L = long and 33 or 16.5
    local col = CCOL[(ci * 5) % #CCOL + 1]
    local base = CF(R(x, qy + 3.5 + tier * 7.05, z)) * CFrame.Angles(0, ((ci % 3) - 1) * 0.015, 0)
    part(hf, V(L, 7, 6.6), base, col, (ci % 2 == 0) and MAT.CorrodedMetal or MAT.Metal, nil, true)
    part(hf, V(0.12, 6.4, 6.0), base * CF(L / 2 + 0.06, 0, 0), col:Lerp(Color3.new(0, 0, 0), 0.3), MAT.Metal)
  end
  for _, s in ipairs({ { -188, 6, 2 }, { -188, 14, 1 }, { -152, 8, 1 }, { -152, 15, 3 }, { -190, 30, 1 }, { -150, 30, 2 }, { 186, 8, 2 }, { 186, 15.5, 1 }, { 186, 30, 2 } }) do
    for t = 0, s[3] - 1 do box(s[1], s[2], t, not (t == 2 or (t == 1 and s[1] > 0 and s[2] > 20))) end
  end
  ---------------- 油罐（东北角）：罐身、顶盖、爬梯，一圈矮的防火堤
  for _, tz in ipairs({ -52, -28 }) do
    local c = R(192, qy, tz)
    cyl(hf, 14, 16, CF(c + V(0, 7, 0)), RGB(206, 206, 198), MAT.Metal, true)
    cyl(hf, 1, 14, CF(c + V(0, 14.5, 0)), RGB(176, 176, 170), MAT.Metal)
    part(hf, V(1.2, 14, 0.3), CF(c + V(-8.1, 7, 0)), RGB(70, 72, 76), MAT.Metal)
  end
  for _, s in ipairs({ { 192, -63, 22, 1 }, { 192, -17, 22, 1 }, { 181, -40, 1, 46 }, { 203, -40, 1, 46 } }) do
    part(hf, V(s[3], 1.6, s[4]), CF(R(s[1], qy + 0.8, s[2])), RGB(156, 154, 146), MAT.Concrete, nil, true)
  end
  ---------------- 码头上的零碎：木箱、油桶（靠着库房）、探照灯杆
  local function crates(x, z, n, seed)
    local s = 3.2 + (seed % 3) * 0.5
    for i = 1, n do
      local ox, oz, y = ((i - 1) % 2) * (s + 0.3), math.floor((i - 1) / 2) * (s + 0.3), qy + s / 2
      if i == n and n >= 3 then ox, oz, y = (s + 0.3) / 2, 0, qy + s * 1.5 end   -- 最后一个摞在上面
      part(hf, V(s, s, s), CF(R(x + ox, y, z + oz)) * CFrame.Angles(0, (seed + i) * 0.37, 0), RGB(150, 116, 74), MAT.WoodPlanks, nil, true)
    end
  end
  local function drums(x, z, n, col)
    for i = 1, n do cyl(hf, 3.2, 2.2, CF(R(x + ((i - 1) % 3) * 2.4, qy + 1.6, z + math.floor((i - 1) / 3) * 2.4)), col, MAT.Metal, true) end
  end
  crates(-60, -30, 4, 1)
  crates(-30, -30, 3, 2)
  crates(48, -30, 4, 3)
  drums(-46, -30, 6, RGB(60, 90, 60))
  drums(20, -30, 5, RGB(140, 50, 40))
  drums(168, -40, 6, RGB(48, 70, 120))
  for _, s in ipairs({ { -100, 10 }, { 100, -28 }, { 178, -4 }, { -205, -45 } }) do floodPole(hf, P.x + s[1], qy, zs + s[2], 24, RGB(255, 222, 170), 110) end
  ---------------- 镇上的房子（用户：继续把地图建筑的建模优化）：民房、瓦房、水泥楼混着摆，街北的正门朝南、街南的朝北（都朝着镇中心那条街），
  --   每座稍微歪一点；码头平地上：靠山一排库房（大门朝海）、西头一座小库房、东头一座锯齿顶厂房（让开坡道和堆场）
  local bf = folder("Buildings", f)
  local spots = { { -60, -40, "jph1" }, { -20, -55, "conc2" }, { 25, -45, "house" }, { 65, -30, "jph3" }, { -70, 10, "conc1" },
    { 70, 15, "jph2" }, { -30, 40, "jph1" }, { 35, 45, "conc3" }, { -95, -75, "house" }, { 100, -70, "conc1" } }
  for kk, s in ipairs(spots) do
    local x, z = P.x + s[1], P.z + s[2]
    local info = BM and BM[s[3]]
    local rot = ((s[2] < 0) and math.pi or 0) + ((kk % 3) - 1) * 0.06
    if footOnLand(x, z, info and info.w or 20, info and info.d or 20, rot) then building(bf, s[3], x, z, rot) end
  end
  if footOnLand(P.x, zs - 48, 132, 30, math.pi) then building(bf, "wh3", P.x, zs - 48, math.pi) end
  if footOnLand(P.x - 125, zs - 22, 30, 34, math.pi) then building(bf, "smallwh", P.x - 125, zs - 22, math.pi) end
  if footOnLand(P.x + 130, zs - 34, 46, 64, math.pi) then building(bf, "sawtooth", P.x + 130, zs - 34, math.pi) end
  ---------------- 镇上：沿路的路灯（钠灯，暖橙）、路边停着的几辆车
  local lamps, cars = 0, 0
  for _, r in ipairs(Map.ROADS or {}) do
    local acc = 0
    for i = 1, #r.x - 1 do
      local x0, z0, x1, z1 = r.x[i], r.z[i], r.x[i + 1], r.z[i + 1]
      local seg = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
      acc += seg
      local dTown = math.sqrt((x0 - P.x) ^ 2 + (z0 - P.z) ^ 2)
      if dTown < 260 and seg > 0.5 then
        local ux, uz = (x1 - x0) / seg, (z1 - z0) / seg
        if acc >= 46 and lamps < 24 then
          acc = 0
          lamps += 1
          local side = (lamps % 2 == 0) and 1 or -1
          local off = r.w * 0.5 + 3
          local lx, lz = x0 - uz * off * side, z0 + ux * off * side
          local gy = Map.ground(lx, lz)
          cyl(f, 14, 0.55, CF(lx, gy + 7, lz), RGB(54, 56, 60), MAT.Metal, true)
          local hx, hz = lx + uz * 3 * side, lz - ux * 3 * side   -- 灯臂伸到路上方
          part(f, V(0.35, 0.35, 3.4), CFrame.lookAt(V(lx, gy + 13.8, lz):Lerp(V(hx, gy + 13.8, hz), 0.5), V(hx, gy + 13.8, hz)), RGB(54, 56, 60), MAT.Metal)
          light(f, V(hx, gy + 13.4, hz), RGB(255, 172, 96), 0.55, 34, 1.3, nil, 3)
        elseif acc >= 23 and acc < 23 + seg and cars < 6 and (i % 5 == 0) then
          cars += 1
          local side = (cars % 2 == 0) and 1 or -1
          local off = r.w * 0.5 + 3.4
          local cx, cz = x0 - uz * off * side, z0 + ux * off * side
          local gy = Map.ground(cx, cz)
          local base = CFrame.lookAt(V(cx, gy, cz), V(cx + ux, gy, cz + uz))
          local wreck = cars == 3
          local col = wreck and RGB(46, 40, 36) or ({ RGB(196, 196, 190), RGB(60, 74, 96), RGB(120, 40, 40), RGB(140, 144, 146), RGB(70, 84, 62) })[cars % 5 + 1]
          part(f, V(4.4, 2.0, 9.6), base * CF(0, 1.9, 0), col, wreck and MAT.CorrodedMetal or MAT.SmoothPlastic, nil, true)
          local cab = part(f, V(4.0, 1.7, 5.0), base * CF(0, 3.7, 0.6), wreck and RGB(30, 28, 26) or RGB(36, 44, 52), wreck and MAT.CorrodedMetal or MAT.Glass)
          if not wreck then cab.Reflectance = 0.1 end
          for _, w in ipairs({ { -2.1, -3.1 }, { 2.1, -3.1 }, { -2.1, 3.1 }, { 2.1, 3.1 } }) do part(f, V(0.9, 2.2, 2.2), base * CF(w[1], 1.1, w[2]), RGB(24, 24, 26), MAT.SmoothPlastic, CYL) end
        end
      end
    end
  end
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
---------------------------------------------------------------- 攻方航母：福建舰（用户 11-21：航母不够真——原来是一个长方块加一块方舰岛）
-- 原模型 models/ship/fujian.glb（tools/models/fujian.py：Sketchfab 上 businessyuen 的「Chinese Aircraft Carrier」，CC-BY；
--   去掉甲板上停着的飞机，按真舰重新分块上色），元数据 CarrierMeta（每块的中心 / 大小 / 颜色 / 材质、量出来的甲板轮廓、舰岛、甲板线）
--   导入了：每块照元数据摆、补回导入时转掉的半圈，颜色和 Roblox 材质照元数据（甲板 Concrete 的防滑面颗粒、船体 Metal）；网格不参与碰撞——
--     甲板照轮廓每 10 格铺一块看不见的碰撞板（舰艏窄、斜角甲板往左舷伸出去、舰尾收窄，走到边上会掉下去，不会踩在空气上），舰岛两个碰撞盒
--   没导入：照同一份轮廓拼——甲板（深灰防滑面）、底下收窄的船体（水线一圈黑、水线下防污红）、舰岛（下层、舰桥、四面相控阵、一体化桅杆）、
--     舰艏两条弹射轨道的白线、斜角甲板的红白边线和黄色中线
--   两种都有：弹射器（滑块；舰腰那条原模型没画，补轨道）、拦阻索（四根钢索 + 两头的滑轮座）、灯（着舰区中线 / 边线、舰尾下降灯、
--     左舷光学着舰指示器、弹射器两侧、舰岛往甲板照的探照灯、桅顶红灯）、航行灯、两舷舷号 18、舰艏甲板上的 18
local CM = nil
pcall(function() CM = require(RS:WaitForChild("CarrierMeta", 5)) end)
World.CM = CM
local CV = { hull = RGB(140, 146, 150), hullD = RGB(112, 118, 122), deck = RGB(62, 64, 66), island = RGB(168, 174, 178), island2 = RGB(148, 154, 158),
  dark = RGB(40, 44, 48), boot = RGB(34, 35, 37), bottom = RGB(112, 42, 38), white = RGB(222, 222, 214), yellow = RGB(212, 182, 66), red = RGB(178, 44, 40) }
local function importedShip(key)
  local imp = RS:FindFirstChild("Imported")
  local s = imp and imp:FindFirstChild("Ship")
  return s and s:FindFirstChild(key)
end
-- 甲板上画一道线（a → b，局部坐标 {x, z}）：w 宽，略高出甲板面
local function deckLine(m, top, a, b, w, color, h)
  local pa, pb = V(a[1], 0, a[2]), V(b[1], 0, b[2])
  local len = (pb - pa).Magnitude
  if len < 0.5 then return end
  local mid = (pa + pb) / 2
  part(m, V(w, 0.12, len), top * CFrame.lookAt(mid + V(0, h or 0.07, 0), pb + V(0, h or 0.07, 0)), color, MAT.SmoothPlastic)
end
-- 甲板上的大字（舷号）：一块薄板，上面一面贴字
local function deckText(m, cf, size, text, face)
  local p = part(m, size, cf, CV.deck, MAT.SmoothPlastic)
  p.Transparency = 1
  local sg = Instance.new("SurfaceGui")
  sg.Face = face or Enum.NormalId.Top
  sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
  sg.PixelsPerStud = 12
  sg.LightInfluence = 1
  sg.Parent = p
  local t = Instance.new("TextLabel")
  t.Size = UDim2.fromScale(1, 1)
  t.BackgroundTransparency = 1
  t.Font = Enum.Font.GothamBlack
  t.TextScaled = true
  t.Text = text
  t.TextColor3 = CV.white
  t.TextStrokeColor3 = RGB(20, 22, 24)
  t.TextStrokeTransparency = 0.35
  t.Parent = sg
  return p
end

-- 原模型 / 零件拼的船体、甲板、舰岛；返回是不是用了原模型
local function carrierHull(m, base)
  local deckY = AirDefs.DECKS.carrier.top
  local src = CM and importedShip("fujian")
  local n = 0
  if src then
    for name, p in pairs(CM.parts) do
      local s0 = src:FindFirstChild("S_fujian__" .. name)
      if s0 and s0:IsA("BasePart") then
        local mp = s0:Clone()
        mp.Anchored = true
        mp.CanCollide, mp.CanQuery, mp.CanTouch = false, false, false
        mp.Size = V(p.s[1], p.s[2], p.s[3])
        mp.CFrame = base * CF(p.c[1], p.c[2], p.c[3]) * TURN
        mp.Color = RGB(p.col[1], p.col[2], p.col[3])
        mp.Material = MAT[p.mat] or MAT.Metal
        mp.Parent = m
        n += 1
      end
    end
  end
  local real = n > 0
  local o = CM and CM.outline
  if not o then   -- 没有元数据（不该发生）：原来那块长方甲板
    local deck = part(m, V(120, 1.5, 620), base * CF(0, deckY - 0.75, 0), CV.deck, MAT.Concrete, nil, true)
    deck.Name = "Deck"
    part(m, V(110, 34, 620), base * CF(0, deckY - 18.5, 0), CV.hull, MAT.Metal, nil, true)
    return false
  end
  -- 甲板：照轮廓每 10 格一块（两行的平均宽度）；导入了原模型就是看不见的碰撞板
  for i = 1, #o - 1 do
    local a, b = o[i], o[i + 1]
    local x0, x1 = (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
    local zc, len = (a[1] + b[1]) / 2, b[1] - a[1]
    local p = part(m, V(x1 - x0, 1.5, len + 0.05), base * CF((x0 + x1) / 2, deckY - 0.75, zc), CV.deck, MAT.Concrete, nil, true)
    p.Name = "Deck"
    if real then p.Transparency, p.CastShadow = 1, false end
  end
  -- 舰岛碰撞盒：下层（到舰桥那么高）整块、上层收窄一点
  local I = CM.island.base
  local ix0, ix1, iz0, iz1, iy1 = I[1], I[2], I[3], I[4], I[5]
  local icx, icz, iw, id = (ix0 + ix1) / 2, (iz0 + iz1) / 2, ix1 - ix0, iz1 - iz0
  if real then
    for _, bx in ipairs({ { 0, iw * 0.86, id * 0.8, deckY, iy1 }, { iw * 0.08, iw * 0.55, id * 0.5, iy1, CM.island.top - 8 } }) do
      local c = part(m, V(bx[2], bx[5] - bx[4], bx[3]), base * CF(icx + bx[1], (bx[4] + bx[5]) / 2, icz), CV.island, MAT.Metal, nil, true)
      c.Name, c.Transparency, c.CastShadow = "Collision", 1, false
    end
    return true
  end
  -- 没导入：船体照轮廓收窄（甲板往外伸出去，下面是空的）：水线以上舰体灰、水线一圈黑、水线下防污红
  for i = 1, #o - 1 do
    local a, b = o[i], o[i + 1]
    local zc, len = (a[1] + b[1]) / 2, b[1] - a[1]
    local hw = math.min(37, ((a[3] - a[2]) + (b[3] - b[2])) / 4 * 0.74)
    part(m, V(hw * 2, deckY - 1.5 - 2.4, len + 0.05), base * CF(0, (deckY - 1.5 + 2.4) / 2, zc), CV.hull, MAT.Metal, nil, true)
    part(m, V(hw * 2 - 0.6, 3.2, len + 0.05), base * CF(0, 0.8, zc), CV.boot, MAT.SmoothPlastic)
    part(m, V(math.max(4, hw * 2 - 6), 12, len + 0.05), base * CF(0, -6.8, zc), CV.bottom, MAT.SmoothPlastic)
    -- 甲板下沿一圈深色的舷侧走廊
    local ex0, ex1 = (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
    part(m, V(ex1 - ex0 + 0.4, 2.2, len + 0.05), base * CF((ex0 + ex1) / 2, deckY - 2.6, zc), CV.hullD, MAT.Metal)
  end
  -- 舰岛：下层（宽、圆角的平台）、舰桥层（一圈深色窗）、上层收窄、四面相控阵雷达（深色板）、一体化桅杆、桅顶的球形天线罩
  local isl = part(m, V(iw * 0.66, iy1 - deckY - 14, id * 0.82), base * CF(icx + iw * 0.08, deckY + (iy1 - deckY - 14) / 2, icz), CV.island, MAT.Metal, nil, true)
  isl.Name = "Island"
  local by = iy1 - 14
  part(m, V(iw * 0.74, 8, id * 0.7), base * CF(icx + iw * 0.06, by + 4, icz - id * 0.04), CV.island2, MAT.Metal, nil, true)
  part(m, V(iw * 0.75, 2.4, id * 0.71), base * CF(icx + iw * 0.06, by + 5, icz - id * 0.04), CV.dark, MAT.Glass)   -- 舰桥窗
  local uy = by + 8
  local uh = CM.island.top - uy - 26
  part(m, V(iw * 0.5, uh, id * 0.5), base * CF(icx + iw * 0.12, uy + uh / 2, icz - id * 0.06), CV.island, MAT.Metal, nil, true)
  for _, f in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do   -- 四面相控阵：每面一块深色板
    local w = (f[1] == 0) and iw * 0.36 or id * 0.36
    local off = V(f[1] * (iw * 0.25 + 0.15), 0, f[2] * (id * 0.25 + 0.15))
    local face = base * CF(icx + iw * 0.12, uy + uh * 0.62, icz - id * 0.06) * CF(off) * CFrame.lookAt(V(), V(f[1], 0, f[2]))
    part(m, V(w, uh * 0.42, 0.3), face, CV.dark, MAT.SmoothPlastic)
  end
  local my = uy + uh
  part(m, V(5, 20, 5), base * CF(icx + iw * 0.12, my + 10, icz - id * 0.06), CV.island2, MAT.Metal)
  part(m, V(4.4, 4.4, 4.4), base * CF(icx + iw * 0.12, my + 22, icz - id * 0.06), CV.white, MAT.SmoothPlastic, BALL)
  return false
end

-- 甲板上的东西（两种都有）：弹射器、拦阻索、标线（没导入时）、灯、舷号
function World.carrierDeck(m, top, real)
  local AD = AirDefs
  -- 弹射器：起点的滑块；舰腰那条原模型没画轨道，补一道深色槽 + 黄色中线；没导入时舰艏两条也画槽、偏流板
  for i, c in ipairs(AD.CATS) do
    local start = top * CF(c.x, 0, c.z) * CFrame.Angles(0, c.a, 0)
    local shuttle = part(m, V(1.6, 0.6, 3), start * CF(0, 0.3, 0), RGB(70, 72, 76), MAT.Metal)
    shuttle.Name = "Shuttle" .. i
    if (not real) or i == 3 then
      part(m, V(2.6, 0.12, c.len), start * CF(0, 0.06, -c.len / 2), RGB(34, 36, 40), MAT.Metal)
      for k = 0, c.len - 10, 20 do part(m, V(0.5, 0.14, 10), start * CF(0, 0.08, -k - 5), CV.yellow) end
    end
    if not real then
      local jbd = part(m, V(18, 0.4, 9), start * CF(0, 0.2, 24), RGB(96, 100, 104), MAT.DiamondPlate)   -- 偏流板（放平）
      jbd.Name = "JBD" .. i
    end
    for k = 0, c.len, 40 do   -- 弹射器两侧的嵌入式灯（暖白）
      for sd = -1, 1, 2 do light(m, (start * CF(sd * 2.4, 0.15, -k)).Position, RGB(255, 236, 196), 0.3, nil, nil, nil, 2) end
    end
  end
  -- 拦阻索：横跨着舰区的四根钢索，两头各一个滑轮座
  local Wd = AD.WIRES
  local zc = (Wd.z0 + Wd.z1) / 2
  for k = 0, Wd.n - 1 do
    local z = Wd.z0 + (k + 0.5) * (Wd.z1 - Wd.z0) / Wd.n
    local xc = Wd.x + (z - zc) * math.tan(Wd.a)
    local cf = top * CF(xc, 0, z) * CFrame.Angles(0, Wd.a, 0)
    part(m, V(Wd.hw * 1.8, 0.35, 0.35), cf * CF(0, 0.3, 0), RGB(30, 30, 32), MAT.Metal)
    for sd = -1, 1, 2 do part(m, V(1.6, 0.9, 1.6), cf * CF(sd * (Wd.hw * 0.9 + 0.8), 0.45, 0), RGB(150, 120, 40), MAT.Metal) end
  end
  -- 斜角甲板：着舰区两条红边线、中线（量的：后端 → 前端）
  local f1, f2 = CM and CM.foul and CM.foul[1], CM and CM.foul and CM.foul[2]
  local ce = CM and CM.center
  if not real and CM then
    for _, b in ipairs(CM.bowCats or {}) do deckLine(m, top, b[1], b[2], 2.6, CV.white) end
    for _, fl in ipairs({ f1, f2 }) do
      if fl then
        deckLine(m, top, fl[1], fl[2], 1.6, CV.red, 0.08)
        local dx, dz = fl[2][1] - fl[1][1], fl[2][2] - fl[1][2]
        local L = math.sqrt(dx * dx + dz * dz)
        local nx = (fl == f1) and 1 or -1   -- 白线在红线外侧
        local ox, oz = -dz / L * 3.2 * nx, dx / L * 3.2 * nx
        deckLine(m, top, { fl[1][1] + ox, fl[1][2] + oz }, { fl[2][1] + ox, fl[2][2] + oz }, 2.4, CV.white)
      end
    end
    if ce then
      local a, b = ce[2], ce[1]   -- 后端 → 前端，每 34 格一段 17 格长的黄线
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local L = math.sqrt(dx * dx + dz * dz)
      for k = 0, L - 17, 34 do
        local t0, t1 = k / L, (k + 17) / L
        deckLine(m, top, { a[1] + dx * t0, a[2] + dz * t0 }, { a[1] + dx * t1, a[2] + dz * t1 }, 2.2, CV.yellow, 0.09)
      end
    end
    -- 舰艏甲板上的舷号（从舰尾看过来是正的）
    deckText(m, top * CF(0, 0.1, -262), V(30, 0.1, 26), "18")
  end
  -- 着舰区的灯：中线一串嵌入式白灯、两条边线一排白色边灯；舰尾往下一列琥珀色下降灯（对准中线）
  if ce then
    local a, b = ce[2], ce[1]
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local L = math.sqrt(dx * dx + dz * dz)
    for k = 0, L, 26 do light(m, (top * CF(a[1] + dx * k / L, 0.2, a[2] + dz * k / L)).Position, RGB(255, 250, 236), 0.5, nil, nil, nil, 3) end
    local st = top * CF(a[1] - dx / L * 22, 0, a[2] - dz / L * 22)
    for k = 1, 5 do light(m, (st * CF(0, -k * 2.4, 0)).Position, RGB(255, 170, 60), 0.6, (k == 1) and 12 or nil, 1, nil, 3) end
  end
  for _, fl in ipairs({ f1, f2 }) do
    if fl then
      local dx, dz = fl[2][1] - fl[1][1], fl[2][2] - fl[1][2]
      local L = math.sqrt(dx * dx + dz * dz)
      for k = 0, L, 40 do light(m, (top * CF(fl[1][1] + dx * k / L, 0.2, fl[1][2] + dz * k / L)).Position, RGB(236, 240, 255), 0.45, nil, nil, nil, 3) end
    end
  end
  -- 光学着舰指示器：左舷边上、拦阻索旁边——中间琥珀色「肉球」、两边一排绿色基准灯
  local xl = (AD.cvEdge(Wd.z0 - 20)) or -70
  local fl = top * CF(xl + 3, 0, Wd.z0 - 20)
  part(m, V(2, 6, 3), fl * CF(0, 3, 0), RGB(40, 42, 46), MAT.Metal)
  light(m, (fl * CF(0, 6.4, 1.6)).Position, RGB(255, 170, 40), 0.9, 10, 2, nil, 5)
  for k = -3, 3 do
    if k ~= 0 then light(m, (fl * CF(0, 6.4, 1.6 + k * 1.4)).Position, RGB(60, 255, 110), 0.55, nil, nil, nil, 3) end
  end
  -- 舰岛：往甲板照的两盏探照灯（左舷那面）、桅顶红色障碍灯和白色桅灯、左红右绿舷灯；舰尾白灯
  if CM then
    local I = CM.island.base
    local ix0, ix1, iz0, iz1 = I[1], I[2], I[3], I[4]
    local icx, icz = (ix0 + ix1) / 2, (iz0 + iz1) / 2
    for _, dz in ipairs({ -(iz1 - iz0) * 0.3, (iz1 - iz0) * 0.3 }) do
      light(m, (top * CF(ix0 - 0.6, I[5] - AD.DECKS.carrier.top - 6, icz + dz)).Position, RGB(255, 214, 160), 1.1, 150, 1.8, { face = Enum.NormalId.Left, angle = 70 }, 3)
    end
    local mtop = CM.island.top - AD.DECKS.carrier.top
    light(m, (top * CF(icx + (ix1 - ix0) * 0.12, mtop + 1, icz - (iz1 - iz0) * 0.06)).Position, RGB(255, 60, 50), 0.8, 20, 1.2, nil, 5)
    light(m, (top * CF(icx + (ix1 - ix0) * 0.12, mtop - 6, icz - (iz1 - iz0) * 0.06 - 2.6)).Position, RGB(255, 250, 236), 0.8, 18, 1.4, nil, 4)
    light(m, (top * CF(ix0 - 0.4, 14, icz - 10)).Position, RGB(255, 50, 40), 0.8, 14, 1.4, nil, 4)
    light(m, (top * CF(ix1 + 0.4, 14, icz - 10)).Position, RGB(60, 255, 120), 0.8, 14, 1.4, nil, 4)
    light(m, (top * CF(0, -6, 306)).Position, RGB(255, 250, 236), 0.8, 14, 1.2, nil, 4)
  end
  -- 两舷舷号 18（白字黑边，舰艏两侧，水线上 16 格那一圈船舷上）
  if CM and CM.side then
    local function sideX(z)
      local o = CM.side
      for i = 1, #o - 1 do
        if z >= o[i][1] and z <= o[i + 1][1] then
          local t = (z - o[i][1]) / (o[i + 1][1] - o[i][1])
          return o[i][2] + (o[i + 1][2] - o[i][2]) * t, o[i][3] + (o[i + 1][3] - o[i][3]) * t
        end
      end
      return nil
    end
    local z = -246
    local xa, xb = sideX(z)
    if xa then
      local dy = 16 - AD.DECKS.carrier.top
      deckText(m, top * CF(xb + 0.6, dy, z), V(0.1, 15, 24), "18", Enum.NormalId.Right)
      deckText(m, top * CF(xa - 0.6, dy, z), V(0.1, 15, 24), "18", Enum.NormalId.Left)
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
    if s.kind == "carrier" then   -- 福建舰：原模型 / 照原模型轮廓拼（上面 carrierHull、carrierDeck）
      local okH, real = pcall(carrierHull, m, base)
      if not okH then warn("[全面大战场] 航母船体出错：" .. tostring(real)) real = false end
      m:SetAttribute("Imported", real == true)
      local ok, err = pcall(World.carrierDeck, m, base * CF(0, AirDefs.DECKS.carrier.top, 0), real == true)
      if not ok then warn("[全面大战场] 航母甲板出错：" .. tostring(err)) end
      m:SetAttribute("Kind", s.kind)
      persist(m)
      m.Parent = f
      table.insert(decks, { kind = s.kind, cf = base * CF(0, D.deck + 1, 0), L = D.L, W = D.W, model = m })
    else   -- 别的舰：拼的船体（不用 continue：测试台的 Lua 5.4 没有）
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
      m:SetAttribute("Kind", s.kind)
      persist(m)
      m.Parent = f
      table.insert(decks, { kind = s.kind, cf = base * CF(0, D.deck + 1, 0), L = D.L, W = D.W, model = m })
    end
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

---------------------------------------------------------------- 细节（用户 11-20：地图不够好、有 bug，再加更多细节——不加树、花、灌木：地上的草是 Roblox 地形自带的）
--   军事据点、机场、海滩后面的阵地、打过仗的痕迹（烧毁的坦克、卡车、登陆艇、直升机）、路口检查站；都是锚定零件，能挡子弹的才挡人
local DET = {
  olive = RGB(74, 84, 58), canvas = RGB(104, 104, 78), tire = RGB(26, 26, 28), burnt = RGB(42, 38, 34), hesco = RGB(166, 148, 110),
  wood = RGB(110, 84, 58), tin = RGB(70, 76, 60),
}
local function gy(x, z) return Map.ground(x, z) end
local function onLand(x, z, r) return footOnLand(x, z, r or 10, r or 10, 0) end

-- 着火（烧着的残骸）：火、烟、一盏忽明忽暗的橙光；smoke：只冒烟
local function burning(f, pos, size, smokeOnly)
  local a = part(f, V(1, 1, 1), CF(pos), DET.burnt)
  a.Transparency = 1
  a.Name = "WreckFire"
  local s = Instance.new("Smoke")
  s.Color, s.Opacity, s.RiseVelocity, s.Size = RGB(40, 38, 36), smokeOnly and 0.18 or 0.3, 7, (size or 5) * 1.4
  s.Parent = a
  if not smokeOnly then
    local fi = Instance.new("Fire")
    fi.Size, fi.Heat, fi.Color, fi.SecondaryColor = size or 5, 9, RGB(255, 120, 40), RGB(255, 60, 20)
    fi.Parent = a
    local L = Instance.new("PointLight")
    L.Color, L.Range, L.Brightness, L.Shadows = RGB(255, 130, 60), 26, 1.6, false
    L.Parent = a
  end
  return a
end

-- 军用卡车：车头、挡风玻璃、货厢、篷布 / 油罐、三根车轴（轮子）；kind = "cargo" / "fuel" / "wreck"
local function truck(f, x, z, rot, kind)
  local y = gy(x, z)
  local wreck = kind == "wreck"
  local base = CF(x, y, z) * CFrame.Angles(0, rot or 0, 0)
  if wreck then base = base * CFrame.Angles(0.04, 0, 0.08) end
  local body, mat = wreck and DET.burnt or DET.olive, wreck and MAT.CorrodedMetal or MAT.Metal
  part(f, V(5.4, 4.4, 5), base * CF(0, 3.6, -6.2), body, mat, nil, true)
  part(f, V(4.8, 1.6, 0.2), base * CF(0, 4.6, -8.75), wreck and RGB(18, 18, 18) or C.glass, MAT.Glass)
  part(f, V(5.6, 1, 12), base * CF(0, 2.4, 2.4), body, mat, nil, true)
  if kind == "fuel" then
    part(f, V(11, 4.6, 4.6), base * CF(0, 5.2, 2.6) * CFrame.Angles(0, math.pi / 2, 0), RGB(150, 152, 146), MAT.Metal, CYL, true)   -- 油罐（轴顺着车身）
  elseif not wreck then
    part(f, V(5.6, 4.2, 11.4), base * CF(0, 5, 2.6), DET.canvas, MAT.Fabric, nil, true)
  end
  for _, wz in ipairs({ -6, 2, 5.6 }) do part(f, V(5.8, 2.8, 2.8), base * CF(0, 1.4, wz), DET.tire, MAT.SmoothPlastic, CYL) end
  if wreck then burning(f, (base * CF(0, 4, -5)).Position, 3.5, true) end
end

-- 坦克残骸：烧黑的车体、两条履带、炸飞落在旁边的炮塔和炮管
local function tankWreck(f, x, z, rot, fire)
  local y = gy(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0) * CFrame.Angles(0.05, 0, -0.06)
  part(f, V(10, 3.2, 20), base * CF(0, 2.6, 0), DET.burnt, MAT.CorrodedMetal, nil, true)
  for _, sx in ipairs({ -5.4, 5.4 }) do part(f, V(1.8, 2.8, 21), base * CF(sx, 1.4, 0), RGB(30, 28, 26), MAT.Metal, nil, true) end
  local tur = base * CF(9, 1.2, 7) * CFrame.Angles(0.3, 1.1, 0.5)
  part(f, V(7, 2.6, 8), tur, RGB(48, 44, 40), MAT.CorrodedMetal, nil, true)
  part(f, V(11, 0.8, 0.8), tur * CF(0, 0, -9) * CFrame.Angles(0, math.pi / 2, 0), RGB(36, 34, 32), MAT.Metal, CYL)   -- 炮管
  burning(f, (base * CF(0, 4.5, 2)).Position, 6, not fire)
end

-- 搁浅烧毁的登陆艇：船体、放下来的跳板、船尾驾驶室
local function craftWreck(f, x, z, rot)
  local y = math.max(Map.height(x, z), -3)
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0) * CFrame.Angles(0.06, 0, 0.12)
  part(f, V(12, 4.5, 30), base * CF(0, 1.8, 0), RGB(56, 60, 58), MAT.CorrodedMetal, nil, true)
  part(f, V(11, 0.6, 8), base * CF(0, 0.4, -18.6) * CFrame.Angles(-0.35, 0, 0), RGB(50, 52, 50), MAT.CorrodedMetal, nil, true)
  part(f, V(6, 4, 5), base * CF(0, 6, 12), RGB(46, 48, 46), MAT.CorrodedMetal, nil, true)
  burning(f, (base * CF(0, 7, 8)).Position, 4, true)
end

-- 坠毁的直升机：歪倒的机身、折断的尾梁、散落的旋翼
local function heliWreck(f, x, z, rot)
  local y = gy(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0)
  part(f, V(4.6, 4.6, 13), base * CF(0, 2.2, 0) * CFrame.Angles(0, 0, 1.2), DET.burnt, MAT.CorrodedMetal, nil, true)
  part(f, V(1.4, 1.4, 13), base * CF(1.5, 1.2, 12) * CFrame.Angles(0.15, 0.5, 0.3), RGB(50, 54, 46), MAT.Metal, nil, true)
  for k = 0, 1 do part(f, V(15, 0.25, 1), base * CF(-6 + k * 10, 0.3, -4 + k * 9) * CFrame.Angles(0.05, 0.6 + k * 1.3, 0), RGB(36, 38, 34), MAT.Metal) end
  burning(f, (base * CF(0, 4, -1)).Position, 4, false)
end

-- HESCO 防爆墙（装土的铁丝网筐）：沿一条线一节节摆，过路的地方留口子
local function hesco(f, x0, z0, x1, z1)
  local dx, dz = x1 - x0, z1 - z0
  local len = math.sqrt(dx * dx + dz * dz)
  local n = math.max(1, math.ceil(len / 12))
  local look = V(dx, 0, dz).Unit
  for i = 0, n - 1 do
    local m = (i + 0.5) / n
    local x, z = x0 + dx * m, z0 + dz * m
    if Map.roadDist(x, z) > 13 and onLand(x, z, 4) then
      local c = V(x, gy(x, z) + 1.9, z)
      part(f, V(4, 4.8, len / n - 0.3), CFrame.lookAt(c, c + look), DET.hesco:Lerp(RGB(140, 124, 92), (i % 3) * 0.2), MAT.Fabric, nil, true)
    end
  end
end

-- 沙袋墙（一段直的）：过路的地方、海里不摆；avoid（工事的位置）附近不摆——别挡碉堡的射界
local function sandbagLine(f, a, b, h, avoid)
  local d = b - a
  local len = d.Magnitude
  local n = math.max(1, math.floor(len / 5))
  local yaw = math.atan2(-d.X, -d.Z)
  for i = 0, n - 1 do
    local p = a + d * ((i + 0.5) / n)
    local y = gy(p.X, p.Z)
    local clear = true
    for _, q in ipairs(avoid or {}) do
      if (q - V(p.X, q.Y, p.Z)).Magnitude < 75 then clear = false break end
    end
    if clear and y > 1.2 and Map.roadDist(p.X, p.Z) > 10 then
      part(f, V(2.2, h or 3, len / n + 0.15), CF(p.X, y + (h or 3) / 2 - 0.2, p.Z) * CFrame.Angles(0, yaw, 0), C.sandbag, MAT.Fabric, nil, true)
    end
  end
end

-- 木头瞭望塔：四条腿、平台、一圈沙袋、铁皮顶、梯子，平台上一盏往外照的探照灯
local function watchtower(f, x, z, rot)
  local base = CF(x, gy(x, z), z) * CFrame.Angles(0, rot or 0, 0)
  for _, o in ipairs({ { -3.5, -3.5 }, { 3.5, -3.5 }, { -3.5, 3.5 }, { 3.5, 3.5 } }) do part(f, V(0.8, 16.4, 0.8), base * CF(o[1], 8.2, o[2]), DET.wood, MAT.Wood, nil, true) end
  part(f, V(9, 0.8, 9), base * CF(0, 16.4, 0), DET.wood, MAT.WoodPlanks, nil, true)
  for _, o in ipairs({ { 0, -4.2, 9, 0.7 }, { 0, 4.2, 9, 0.7 }, { -4.2, 0, 0.7, 9 }, { 4.2, 0, 0.7, 9 } }) do
    part(f, V(o[3], 2.6, o[4]), base * CF(o[1], 18.1, o[2]), C.sandbag, MAT.Fabric, nil, true)
  end
  for _, o in ipairs({ { -4.2, -4.2 }, { 4.2, 4.2 }, { -4.2, 4.2 }, { 4.2, -4.2 } }) do part(f, V(0.4, 3.6, 0.4), base * CF(o[1], 21, o[2]), DET.wood, MAT.Wood) end
  part(f, V(10.4, 0.5, 10.4), base * CF(0, 23, 0), DET.tin, MAT.CorrodedMetal)
  part(f, V(1.8, 17, 0.3), base * CF(0, 8.2, 5.4) * CFrame.Angles(-0.22, 0, 0), DET.wood, MAT.Wood)
  local pos = (base * CF(0, 20.2, -3.6)).Position
  local l = light(f, pos, RGB(255, 236, 200), 0.9, 120, 2.2, { face = Enum.NormalId.Front, angle = 38 }, 3)
  l.CFrame = CFrame.lookAt(pos, pos + base.LookVector + V(0, -0.32, 0))
end

local function crates(f, x, z, n, seed)
  local s = 3.2 + (seed % 3) * 0.5
  local y0 = gy(x, z)
  for i = 1, n do
    local ox, oz, y = ((i - 1) % 2) * (s + 0.3), math.floor((i - 1) / 2) * (s + 0.3), y0 + s / 2
    if i == n and n >= 3 then ox, oz, y = (s + 0.3) / 2, 0, y0 + s * 1.5 end
    part(f, V(s, s, s), CF(x + ox, y, z + oz) * CFrame.Angles(0, (seed + i) * 0.37, 0), RGB(118, 104, 70), MAT.WoodPlanks, nil, true)
  end
end
local function drums(f, x, z, n, col)
  for i = 1, n do
    local px, pz = x + ((i - 1) % 3) * 2.4, z + math.floor((i - 1) / 3) * 2.4
    cyl(f, 3.2, 2.2, CF(px, gy(px, pz) + 1.6, pz), col, MAT.Metal, true)
  end
end
local function fuelTank(f, x, z, dia, h)
  local y = gy(x, z)
  cyl(f, h, dia, CF(x, y + h / 2, z), RGB(200, 200, 192), MAT.Metal, true)
  cyl(f, 1, dia - 2, CF(x, y + h + 0.5, z), RGB(172, 172, 166), MAT.Metal)
  part(f, V(1.2, h, 0.3), CF(x - dia / 2 - 0.2, y + h / 2, z), RGB(70, 72, 76), MAT.Metal)
end
-- 直升机停机坪：圆水泥坪、白色 H、一圈绿灯
local function helipad(f, x, z)
  local y = gy(x, z)
  cyl(f, 0.6, 30, CF(x, y + 0.1, z), RGB(118, 118, 114), MAT.Concrete, true)
  for _, s in ipairs({ { -3, 0, 1.6, 9 }, { 3, 0, 1.6, 9 }, { 0, 0, 4.4, 1.6 } }) do part(f, V(s[3], 0.1, s[4]), CF(x + s[1], y + 0.45, z + s[2]), C.white) end
  for k = 0, 5 do
    local a = k * math.pi / 3
    light(f, V(x + math.cos(a) * 14, y + 0.6, z + math.sin(a) * 14), RGB(80, 255, 120), 0.4, nil, nil, nil, 2)
  end
end
-- 检查站：岗亭、一圈沙袋、抬起来的栏杆、一根探照灯杆（摆在路边，不挡路）
local function checkpoint(f, x, z, ux, uz)
  local side = V(-uz, 0, ux)   -- 路的左手边
  local p = V(x, 0, z) + side * 13
  local y = gy(p.X, p.Z)
  local base = CFrame.lookAt(V(p.X, y, p.Z), V(p.X, y, p.Z) - side)   -- 正面朝路
  part(f, V(5, 7.4, 5), base * CF(0, 3.7, 1.5), RGB(196, 194, 184), MAT.Concrete, nil, true)
  part(f, V(5.6, 0.5, 5.6), base * CF(0, 7.6, 1.5), RGB(60, 64, 56), MAT.Metal)
  part(f, V(3.4, 1.6, 0.2), base * CF(0, 4.8, -1.05), C.glass, MAT.Glass)
  for _, s in ipairs({ { -5, -2, 0 }, { 5, -2, 0 }, { 0, -4.6, 1 } }) do
    part(f, V(s[3] == 1 and 8 or 2.2, 3, s[3] == 1 and 2.2 or 6), base * CF(s[1], 1.3, s[2] - 2), C.sandbag, MAT.Fabric, nil, true)
  end
  part(f, V(0.8, 3.4, 0.8), base * CF(3.4, 1.7, -4.8), RGB(60, 62, 64), MAT.Metal)
  part(f, V(0.4, 0.4, 12), base * CF(3.4, 3.2, -4.8) * CFrame.Angles(1.25, 0, 0) * CF(0, 0, -6), RGB(220, 60, 50), MAT.SmoothPlastic)
  floodPole(f, (base * CF(-3.5, 0, 4.5)).Position.X, y, (base * CF(-3.5, 0, 4.5)).Position.Z, 12, RGB(255, 220, 170), 60)
end

local function revetment(f, x, z)
  local base = CF(x, gy(x, z), z)
  part(f, V(34, 7, 3), base * CF(0, 3.2, -13), C.concrete, MAT.Concrete, nil, true)
  for _, s in ipairs({ -1, 1 }) do part(f, V(3, 7, 26), base * CF(s * 17, 3.2, -1.5), C.concrete, MAT.Concrete, nil, true) end
end
local function windsock(f, x, z)
  local y = gy(x, z)
  cyl(f, 12, 0.5, CF(x, y + 6, z), C.white, MAT.Metal, true)
  local base = CF(x, y + 11.6, z) * CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(math.rad(-14), 0, 0)
  for i = 0, 2 do part(f, V(2.2 - i * 0.45, 2.2 - i * 0.45, 2.4), base * CF(0, 0, -1.4 - i * 2.4), (i % 2 == 0) and RGB(240, 110, 30) or C.white, MAT.Fabric) end
  light(f, V(x, y + 12.5, z), RGB(255, 40, 40), 0.4, nil, nil, nil, 2)
end
local function radar(f, x, z, h)
  local y = gy(x, z)
  part(f, V(3, h, 3), CF(x, y + h / 2, z), RGB(150, 152, 150), MAT.Metal, nil, true)
  part(f, V(4.6, 2.6, 4.6), CF(x, y + h + 1.3, z), RGB(200, 200, 196), MAT.Metal)
  local ant = part(f, V(11, 2.6, 0.6), CF(x, y + h + 4.4, z), RGB(214, 214, 210), MAT.Metal)
  ant.Name = "Radar"
  ant:SetAttribute("Anim", "spin")   -- 客户端 Night.lua 转它
  ant:SetAttribute("Spd", 0.22)
  ant:SetAttribute("Pivot", ant.CFrame.Position)
end

-- 机场：停机坪北边一排防爆掩体（口朝停机坪）、塔台旁的油库、跑道南边的风向袋、塔台后面转的雷达、机库门口的加油车和牵引车
local function airfieldExtras(f, A)
  local hx = A.len / 2
  for _, dx in ipairs({ -760, -620, 620, 760 }) do
    local x, z = A.x + dx, A.z - A.wid / 2 - 97
    if footOnLand(x, z, 40, 30, 0) then revetment(f, x, z) end
  end
  local fx, fz = A.x + hx - 300, A.z - A.wid / 2 - 170
  if footOnLand(fx, fz, 80, 30, 0) then
    for k = -1, 1 do fuelTank(f, fx + k * 22, fz, 16, 11) end
    local y = gy(fx, fz)
    for _, s in ipairs({ { 0, -14, 74, 1 }, { 0, 14, 74, 1 }, { -37, 0, 1, 28 }, { 37, 0, 1, 28 } }) do
      part(f, V(s[3], 1.6, s[4]), CF(fx + s[1], y + 0.8, fz + s[2]), RGB(156, 154, 146), MAT.Concrete, nil, true)
    end
    truck(f, fx - 52, fz + 4, math.pi / 2, "fuel")
  end
  if onLand(A.x + A.len * 0.33, A.z + A.wid / 2 + 40) then windsock(f, A.x + A.len * 0.33, A.z + A.wid / 2 + 40) end
  if onLand(A.x + hx - 90, A.z - A.wid / 2 - 200) then radar(f, A.x + hx - 90, A.z - A.wid / 2 - 200, 16) end
  if onLand(A.x - 192, A.z - A.wid / 2 - 76) then truck(f, A.x - 192, A.z - A.wid / 2 - 76, 0.1, "fuel") end
  if onLand(A.x + 196, A.z - A.wid / 2 - 74) then truck(f, A.x + 196, A.z - A.wid / 2 - 74, -0.15, "cargo") end
  crates(f, A.x - 210, A.z - A.wid / 2 - 70, 4, 1)
  drums(f, A.x + 212, A.z - A.wid / 2 - 66, 6, RGB(60, 90, 60))
end

-- 指挥所：后面和两侧一圈 HESCO（朝海那面不围：碉堡往南打）、直升机坪、半埋掩体上的伪装网、发电机和油桶、第二根天线、停着的卡车
--   （占领圈里只放平的停机坪和不挡人的伪装网：圈里有掩体，守方机器人会钻进去守着不走）
local function commandExtras(f)
  local P = Map.COMMAND
  local x0, x1, z0, z1 = P.x - 112, P.x + 102, P.z - 96, P.z + 60
  hesco(f, x0, z0, x1, z0)
  hesco(f, x1, z0, x1, z1)
  hesco(f, x0, z1, x0, z0)
  helipad(f, P.x - 50, P.z + 30)
  local y = gy(P.x - 30, P.z - 25)
  local net = part(f, V(48, 0.3, 38), CF(P.x - 30, y + 13.6, P.z - 25) * CFrame.Angles(0.03, 0, -0.02), DET.olive, MAT.Fabric)
  net.Transparency = 0.3
  for _, o in ipairs({ { -23, -18 }, { 23, -18 }, { -23, 18 }, { 23, 18 } }) do part(f, V(0.5, 13.4, 0.5), CF(P.x - 30 + o[1], y + 6.7, P.z - 25 + o[2]), DET.wood, MAT.Wood) end
  local gx, gz = P.x + 62, P.z - 86   -- 发电机、油桶、木箱、卡车都在占领圈（80 格）外头
  part(f, V(6, 4, 3.4), CF(gx, gy(gx, gz) + 2, gz), DET.olive, MAT.Metal, nil, true)
  cyl(f, 3, 0.5, CF(gx + 2.2, gy(gx, gz) + 5.4, gz + 0.8), RGB(40, 40, 40), MAT.Metal)
  drums(f, gx + 6, gz - 2, 6, RGB(60, 84, 52))
  mast(f, P.x - 72, P.z - 74, 30)
  truck(f, P.x - 101, P.z - 44, 0, "cargo")
  truck(f, P.x - 101, P.z - 16, 0, "cargo")
  crates(f, P.x + 80, P.z - 80, 4, 2)
  crates(f, P.x - 96, P.z + 40, 3, 1)
end

-- 后方营地：两座瞭望塔、停着的卡车、帐篷边上的木箱和油桶
local function campExtras(f)
  local P = Map.CAMP
  watchtower(f, P.x - 186, P.z + 18, math.pi * 0.75)
  watchtower(f, P.x + 190, P.z + 18, -math.pi * 0.75)
  for k = 0, 2 do truck(f, P.x + 104 + k * 9, P.z - 8, math.pi, "cargo") end
  crates(f, P.x - 78, P.z - 34, 4, 3)
  crates(f, P.x + 66, P.z - 36, 3, 2)
  drums(f, P.x - 130, P.z - 30, 6, RGB(60, 84, 52))
end

-- 前哨岛（据点 A）：两座铁皮营房、一座瞭望塔、一根天线、木箱油桶——都摆在占领圈外头（圈里有掩体，守方机器人会钻进去守着不走）
local function outpostExtras(f, bf)
  local A = Map.POINTS[1]
  for _, s in ipairs({ { -150, -120, 0.1 }, { -205, -80, -0.05 } }) do
    if footOnLand(A.x + s[1], A.z + s[2], 40, 20, s[3]) then building(bf, "quonset", A.x + s[1], A.z + s[2], s[3]) end
  end
  if onLand(A.x + 150, A.z - 40) then watchtower(f, A.x + 150, A.z - 40, math.pi * 0.85) end
  if onLand(A.x - 60, A.z - 160) then mast(f, A.x - 60, A.z - 160, 30) end
  crates(f, A.x + 120, A.z - 120, 4, 1)
  drums(f, A.x - 120, A.z - 150, 5, RGB(60, 84, 52))
end

-- 海滩后面的阵地：南岸四处海滩，离岸 75 格一条之字形的沙袋战壕线（每隔几段留口子，车开得过去）
local function beachLines(f)
  local avoid = {}
  pcall(function()
    local FD = require(RS:WaitForChild("FortDefs", 5))
    for _, e in ipairs(FD.layout(Map)) do table.insert(avoid, e.cf.Position) end
  end)
  for _, b in ipairs(Map.BEACHES) do
    if not b.north then
      local w = b.x1 - b.x0
      local pts = {}
      for i = 0, 8 do
        local x = b.x0 + w * (0.2 + 0.6 * i / 8)
        local zc = Map.coastS(x) or b.z
        table.insert(pts, V(x, 0, zc - 75 - ((i % 2 == 0) and 0 or 10)))
      end
      for i = 1, #pts - 1 do
        if i % 3 ~= 0 then sandbagLine(f, pts[i], pts[i + 1], 3, avoid) end
      end
    end
  end
end

-- 打过仗的痕迹：滩上烧毁的坦克（红滩那辆还在烧）、金滩搁浅的登陆艇、路边烧毁的卡车、指挥所下面山坡上坠毁的直升机
local function roadPoint(name, frac, off)
  for _, r in ipairs(Map.ROADS or {}) do
    if r.name == name and #r.x >= 3 then
      local i = math.clamp(math.floor(#r.x * frac), 1, #r.x - 1)
      local dx, dz = r.x[i + 1] - r.x[i], r.z[i + 1] - r.z[i]
      local l = math.max(0.01, math.sqrt(dx * dx + dz * dz))
      local ux, uz = dx / l, dz / l
      return r.x[i] - uz * off, r.z[i] + ux * off, ux, uz
    end
  end
  return nil
end
local function wrecks(f)
  local B = {}
  for _, b in ipairs(Map.BEACHES) do B[b.id] = b end
  local function onBeach(id, dx, dz, fn, ...)
    local b = B[id]
    if not b then return end
    local x = b.cx + dx
    local zc = Map.coastS(x)
    if zc then fn(f, x, zc + dz, ...) end
  end
  onBeach("red", 78, -6, tankWreck, 0.6, true)
  onBeach("blue", -84, -10, tankWreck, -0.4, false)
  onBeach("white", 92, -4, tankWreck, 2.6, false)
  onBeach("gold", 88, 14, craftWreck, 0.25)
  for _, s in ipairs({ { "指挥所—港口镇", 0.38, 1 }, { "金滩—机场", 0.55, -1 }, { "营地—指挥所", 0.62, 1 } }) do
    local x, z, ux, uz = roadPoint(s[1], s[2], s[3] * 9)
    if x and onLand(x, z) then truck(f, x, z, math.atan2(-ux, -uz) + 0.5 * s[3], "wreck") end
  end
  local hx, hz = roadPoint("指挥所—机场", 0.3, 34)
  if hx and onLand(hx, hz) then heliWreck(f, hx, hz, 1.9) end
end

-- 进港口镇、机场、指挥所的路口：检查站
local function checkpoints(f)
  local sites = { { Map.PORT.x, Map.PORT.z, 250 }, { Map.AIRFIELD.x + 600, Map.AIRFIELD.z - 300, 330 }, { Map.COMMAND.x, Map.COMMAND.z, 190 } }
  for _, s in ipairs(sites) do
    local done = 0
    for _, r in ipairs(Map.ROADS or {}) do
      for i = 1, #r.x - 1 do
        local d0 = math.sqrt((r.x[i] - s[1]) ^ 2 + (r.z[i] - s[2]) ^ 2)
        local d1 = math.sqrt((r.x[i + 1] - s[1]) ^ 2 + (r.z[i + 1] - s[2]) ^ 2)
        if done < 2 and (d0 - s[3]) * (d1 - s[3]) <= 0 then   -- 这条路在这里穿过那一圈
          local dx, dz = r.x[i + 1] - r.x[i], r.z[i + 1] - r.z[i]
          local l = math.max(0.01, math.sqrt(dx * dx + dz * dz))
          if onLand(r.x[i], r.z[i]) then
            checkpoint(f, r.x[i], r.z[i], dx / l, dz / l)
            done += 1
          end
          break
        end
      end
    end
  end
end

---------------------------------------------------------------- 沙漠图（沙海 MapSands）：镇子、清真寺、油田、边境沙墙、红方前进基地、空军基地的加固机库、死亡公路
--   用户 11-22「整个重做 纯地面和空军对战的海湾战争」：照科威特、伊拉克南部的样子——平顶土坯房（带女儿墙、院墙），镇中心一座清真寺；
--   油田里抽油机一下一下点头（客户端 Night.lua 的 rock 动画），几口井在烧；80 号公路镇子北边一路烧毁的车（「死亡公路」）。
--   都是锚定零件：房子、院墙、残骸挡子弹挡人；占领圈（80 格）里不摆能钻进去的东西
local ADOBE = { RGB(200, 176, 134), RGB(190, 162, 120), RGB(210, 188, 150), RGB(178, 152, 114), RGB(218, 202, 168), RGB(196, 168, 128) }
local function drng(seed)   -- 定死种子的随机数（每局一样）
  local s = seed
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

-- 平顶土坯房：墙身、女儿墙、深色门洞、小窗、屋顶水箱 / 卫星锅；yard 带一圈院墙（正门那面留口）
local function adobe(f, x, z, w, d, h, rot, col, R, yard)
  local y = footY(x, z, w, d, rot) - 0.3
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0)
  local m = Instance.new("Model")
  m.Name = "Adobe"
  slab(m, V(w, h, d), base * CF(0, h / 2, 0), col, MAT.Concrete)
  local par = col:Lerp(RGB(150, 128, 96), 0.25)
  for _, p in ipairs({ { 0, -d / 2, w, 0.8 }, { 0, d / 2, w, 0.8 }, { -w / 2, 0, 0.8, d }, { w / 2, 0, 0.8, d } }) do
    slab(m, V(p[3], 1.4, p[4]), base * CF(p[1], h + 0.7, p[2]), par, MAT.Concrete)
  end
  local F = faces(base, w, d)
  deco(m, V(3.4, 6.2, 0.3), F[1].cf * CF((R() - 0.5) * (w - 7), 3.1, 0.12), RGB(52, 40, 30), MAT.Wood)   -- 门
  for _, fc in ipairs(F) do
    local n = math.max(1, math.floor(fc.len / 9))
    for i = 1, n do
      if R() < 0.65 then deco(m, V(2.2, 2.4, 0.3), fc.cf * CF(-fc.len / 2 + (i - 0.5) * fc.len / n, h * 0.62, 0.12), RGB(34, 30, 26), MAT.SmoothPlastic) end
    end
  end
  local r = R()
  if r < 0.45 then
    deco(m, V(3, 2.4, 3), base * CF(w * 0.22, h + 1.2, d * 0.18), RGB(206, 206, 200), MAT.Metal, CYL)   -- 水箱（圆柱轴是 X：躺着）
  elseif r < 0.7 then
    local c = base * CF(-w * 0.25, h + 1.6, -d * 0.2) * CFrame.Angles(0, R() * 6.28, 0) * CFrame.Angles(math.rad(-50), 0, 0)
    deco(m, V(0.3, 3.2, 3.2), c * CFrame.Angles(0, math.pi / 2, 0), RGB(224, 224, 220), MAT.SmoothPlastic, CYL)   -- 卫星锅
  end
  if yard then   -- 院墙：房子前面围一个院子，正门对着的那面开口
    local yd = 10 + R() * 8
    local wc = col:Lerp(RGB(170, 146, 108), 0.35)
    local hw, wh = w / 2 + 3, 6.5
    local z0, z1 = -d / 2, -d / 2 - yd
    slab(m, V(0.9, wh, yd), base * CF(-hw, wh / 2, (z0 + z1) / 2), wc, MAT.Concrete)
    slab(m, V(0.9, wh, yd), base * CF(hw, wh / 2, (z0 + z1) / 2), wc, MAT.Concrete)
    local gap = 5
    local seg = (2 * hw - gap) / 2
    slab(m, V(seg, wh, 0.9), base * CF(-hw + seg / 2, wh / 2, z1), wc, MAT.Concrete)
    slab(m, V(seg, wh, 0.9), base * CF(hw - seg / 2, wh / 2, z1), wc, MAT.Concrete)
  end
  atomic(m)
  m.Parent = f
  return base
end

-- 清真寺：方形礼拜殿 + 大圆顶（鼓座、新月）、一座宣礼塔（阳台、小圆顶）
local function mosque(f, x, z, rot)
  local w, d, h = 46, 46, 18
  local y = footY(x, z, w + 30, d, rot) - 0.3
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0)
  local m = Instance.new("Model")
  m.Name = "Mosque"
  local wall, trim = RGB(226, 214, 186), RGB(190, 172, 136)
  slab(m, V(w, h, d), base * CF(0, h / 2, 0), wall, MAT.Concrete)
  for _, p in ipairs({ { 0, -d / 2, w, 1 }, { 0, d / 2, w, 1 }, { -w / 2, 0, 1, d }, { w / 2, 0, 1, d } }) do
    slab(m, V(p[3], 2, p[4]), base * CF(p[1], h + 1, p[2]), trim, MAT.Concrete)
  end
  slab(m, V(4, 30, 30), base * CF(0, h + 4, 0) * CFrame.Angles(0, 0, math.pi / 2), trim, MAT.Concrete, CYL)   -- 鼓座（圆柱轴竖着）
  slab(m, V(30, 30, 30), base * CF(0, h + 6, 0), RGB(64, 118, 128), MAT.SmoothPlastic, BALL)   -- 圆顶（青绿）
  deco(m, V(0.5, 4, 0.5), base * CF(0, h + 23, 0), RGB(214, 180, 70), MAT.Metal)
  deco(m, V(0.4, 2.2, 1.6), base * CF(0, h + 25.6, 0), RGB(214, 180, 70), MAT.Metal)   -- 新月（简化成一片）
  local F = faces(base, w, d)
  for _, fc in ipairs(F) do   -- 拱窗（深色竖长条）
    for i = -2, 2 do deco(m, V(2.6, 6.5, 0.3), fc.cf * CF(i * 8, h * 0.55, 0.12), RGB(40, 52, 58), MAT.SmoothPlastic) end
  end
  deco(m, V(7, 11, 0.4), F[1].cf * CF(0, 5.5, 0.15), RGB(58, 46, 34), MAT.Wood)   -- 大门
  -- 宣礼塔：礼拜殿东北角外
  local mt = base * CF(w / 2 + 9, 0, -d / 2 + 2)
  slab(m, V(6.5, 52, 6.5), mt * CF(0, 26, 0), wall, MAT.Concrete)
  slab(m, V(10, 1.4, 10), mt * CF(0, 40, 0), trim, MAT.Concrete)   -- 阳台
  slab(m, V(5, 8, 5), mt * CF(0, 56, 0), wall, MAT.Concrete)
  slab(m, V(6, 6, 6), mt * CF(0, 61, 0), RGB(64, 118, 128), MAT.SmoothPlastic, BALL)
  deco(m, V(0.4, 3.5, 0.4), mt * CF(0, 65.5, 0), RGB(214, 180, 70), MAT.Metal)
  light(m, (mt * CF(0, 41.5, -5.2)).Position, RGB(140, 255, 170), 0.6, 18, 1.1, nil, 3)   -- 宣礼塔阳台的绿灯
  atomic(m)
  m.Parent = f
end

-- 镇子（据点 C）：围着镇中心一圈一圈摆土坯房（占领圈外、躲开公路），镇中心北边清真寺，路边几排两层的水泥楼和集市棚子
local function desertTown(f)
  local T = Map.TOWN
  local R = drng(90210)
  local bf = folder("Town", f)
  local placed = {}
  local function free(x, z, r)
    if Map.roadDist(x, z) < r + 14 then return false end
    if (x - T.x) ^ 2 + (z - T.z) ^ 2 < (Map.POINT_R + 40 + r) ^ 2 then return false end
    if Map.slope(x, z) > 0.18 then return false end
    for _, q in ipairs(placed) do
      if (q[1] - x) ^ 2 + (q[2] - z) ^ 2 < (q[3] + r + 7) ^ 2 then return false end
    end
    return true
  end
  -- 清真寺：镇中心往北 190 格（路的东边）
  local mx, mz = T.x + 120, T.z - 200
  for _ = 1, 12 do
    if free(mx, mz, 40) then break end
    mx += 30
  end
  mosque(bf, mx, mz, 0)
  table.insert(placed, { mx, mz, 42 })
  -- 土坯房：按螺旋往外找空地（大约九十座），朝向大致对着最近的路
  local n, tries = 0, 0
  while n < 92 and tries < 2400 do
    tries += 1
    local a = tries * 2.39996
    local rr = 150 + 470 * math.sqrt(tries / 2400) + (R() - 0.5) * 40
    local x, z = T.x + math.cos(a) * rr * 1.15, T.z + math.sin(a) * rr * 0.9
    local w, d = 14 + math.floor(R() * 4) * 3, 12 + math.floor(R() * 4) * 3
    local h = (R() < 0.18) and 15 or (8.5 + R() * 2)
    local rad = math.sqrt(w * w + d * d) / 2 + 4
    if free(x, z, rad) then
      -- 朝向：正门对着镇中心（一条条巷子往中间走），再随机歪一点
      local rot = math.atan2(-(T.x - x), -(T.z - z)) + (R() - 0.5) * 0.5
      adobe(bf, x, z, w, d, h, rot, ADOBE[1 + math.floor(R() * #ADOBE)], R, R() < 0.45)
      table.insert(placed, { x, z, rad + ((R() < 0.45) and 10 or 0) })
      n += 1
    end
  end
  -- 公路边：两层水泥楼（商店）、集市棚子
  for _, s in ipairs({ { -260, 40 }, { -200, -60 }, { 230, 60 }, { 300, -30 }, { 40, 240 }, { -60, 300 } }) do
    local x, z = T.x + s[1], T.z + s[2]
    if free(x, z, 18) then
      building(bf, (R() < 0.5) and "conc1" or "conc2", x, z, math.atan2(-(T.x - x), -(T.z - z)))
      table.insert(placed, { x, z, 20 })
    end
  end
  for k = 0, 5 do   -- 集市：镇中心东南、圈外，一排彩色遮阳棚
    local x, z = T.x + 150 + k * 13, T.z + 120
    if free(x, z, 6) then
      local y = gy(x, z)
      local col = ({ RGB(170, 60, 50), RGB(60, 90, 140), RGB(200, 170, 70), RGB(80, 120, 70) })[1 + k % 4]
      for _, o in ipairs({ { -5, -4 }, { 5, -4 }, { -5, 4 }, { 5, 4 } }) do part(bf, V(0.4, 7, 0.4), CF(x + o[1], y + 3.5, z + o[2]), DET.wood, MAT.Wood) end
      part(bf, V(11, 0.3, 9), CF(x, y + 7.1, z) * CFrame.Angles(0.1, 0, 0), col, MAT.Fabric)
      crates(bf, x - 2, z + 1, 2, k)
      table.insert(placed, { x, z, 7 })
    end
  end
  -- 镇口两个油桶路障、烧毁的车
  truck(bf, T.x - 330, T.z + 210, 2.2, "wreck")
  drums(bf, T.x + 260, T.z + 160, 5, RGB(150, 60, 40))
end

-- 抽油机（磕头机）：底座、A 字架、游梁（前头驴头、后头连杆曲柄配重）、电机房；游梁和驴头带 rock 动画（绕支点上下点头）
local function pumpjack(f, x, z, rot, phase)
  local y = gy(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0)
  local m = Instance.new("Model")
  m.Name = "Pumpjack"
  local steel, dark = RGB(58, 62, 66), RGB(40, 40, 42)
  slab(m, V(5, 1.2, 22), base * CF(0, 0.6, 0), RGB(150, 146, 136), MAT.Concrete)
  for _, sx in ipairs({ -1.6, 1.6 }) do   -- A 字架：两根斜撑
    deco(m, V(0.5, 12.5, 0.5), base * CF(sx, 6.2, 1.5) * CFrame.Angles(0.2, 0, 0), steel, MAT.Metal)
    deco(m, V(0.5, 12.5, 0.5), base * CF(sx, 6.2, -1.2) * CFrame.Angles(-0.2, 0, 0), steel, MAT.Metal)
  end
  local pivot = (base * CF(0, 12.3, 0.2)).Position
  local beam = part(m, V(1.1, 1.4, 18), base * CF(0, 12.9, 0.2), RGB(170, 140, 40), MAT.Metal)   -- 游梁（黄）
  local head = part(m, V(1.4, 5.5, 2.2), base * CF(0, 11.8, -9.2) * CFrame.Angles(-0.25, 0, 0), RGB(170, 140, 40), MAT.Metal)   -- 驴头
  local rod = part(m, V(0.25, 9, 0.25), base * CF(0, 6, -10), dark, MAT.Metal)   -- 光杆（往井口里拉）
  rod.Name = "Rod"
  for _, p in ipairs({ beam, head }) do
    p:SetAttribute("Anim", "rock")
    p:SetAttribute("Spd", 0.16)
    p:SetAttribute("Pivot", pivot)
    p:SetAttribute("Axis", (base - base.Position) * V(1, 0, 0))
    p:SetAttribute("Amp", 0.24)
    p:SetAttribute("Ph", phase)
  end
  slab(m, V(4, 4.5, 4.5), base * CF(0, 3.4, 8.2), dark, MAT.Metal)   -- 曲柄配重
  slab(m, V(4.4, 3.6, 4), base * CF(0, 1.8, 11.6), RGB(120, 124, 116), MAT.Metal)   -- 电机房
  cyl(m, 1.6, 1.4, base * CF(0, 1.2, -10), RGB(90, 96, 92), MAT.Metal)   -- 井口
  atomic(m)
  m.Parent = f
end
-- 采油树（没装抽油机的自喷井）：一截立管、阀门、管汇
local function wellhead(f, x, z)
  local y = gy(x, z)
  local m = Instance.new("Model")
  m.Name = "Wellhead"
  cyl(m, 0.8, 7, CF(x, y + 0.4, z), RGB(150, 146, 136), MAT.Concrete, true)
  part(m, V(1.2, 7, 1.2), CF(x, y + 3.5, z), RGB(170, 60, 40), MAT.Metal, nil, true)
  for _, k in ipairs({ 2.4, 4.6 }) do part(m, V(3.2, 0.9, 0.9), CF(x, y + k, z), RGB(200, 180, 60), MAT.Metal) end
  part(m, V(0.6, 0.6, 9), CF(x, y + 1.2, z + 4.8), RGB(120, 120, 116), MAT.Metal)
  atomic(m)
  m.Parent = f
end

-- 油田：每口井一台抽油机或一棵采油树，十二分之一的井在烧（大火 + 黑烟柱）；据点 B 东边的集油站（储罐、分离器、管线、火炬）
local function oilfield(f)
  local of = folder("Oilfield", f)
  local R = drng(4242)
  for i, wl in ipairs(Map.OILWELLS or {}) do
    local x, z = wl.x, wl.z
    if i % 12 == 5 then   -- 着火的井（伊拉克撤退时点的那种）：火很大，烟柱很高
      wellhead(of, x, z)
      burning(of, V(x, gy(x, z) + 6, z), 22)
      local sm = burning(of, V(x, gy(x, z) + 30, z), 30, true)
      local s = sm:FindFirstChildOfClass("Smoke")
      if s then s.Color, s.Opacity, s.RiseVelocity = RGB(20, 18, 16), 0.45, 18 end
    elseif R() < 0.7 then
      pumpjack(of, x, z, R() * math.pi * 2, R())
    else
      wellhead(of, x, z)
    end
  end
  -- 集油站：B 东北 380 格
  local O = Map.OILFIELD
  local gx, gz = O.x + 330, O.z - 260
  if Map.roadDist(gx, gz) < 60 then gx += 120 end
  for k = 0, 2 do fuelTank(of, gx + k * 34, gz, 26, 18) end
  for k = 0, 1 do
    local y = gy(gx + k * 30, gz + 46)
    part(of, V(16, 6, 6), CF(gx + k * 30, y + 4, gz + 46), RGB(176, 178, 172), MAT.Metal, CYL, true)   -- 卧式分离器
    part(of, V(2, 3, 5), CF(gx + k * 30 - 6, y + 1.5, gz + 46), RGB(120, 120, 116), MAT.Concrete, nil, true)
    part(of, V(2, 3, 5), CF(gx + k * 30 + 6, y + 1.5, gz + 46), RGB(120, 120, 116), MAT.Concrete, nil, true)
  end
  local fy = gy(gx + 110, gz + 20)
  cyl(of, 46, 2.2, CF(gx + 110, fy + 23, gz + 20), RGB(150, 150, 146), MAT.Metal, true)   -- 火炬塔
  local fl = burning(of, V(gx + 110, fy + 48, gz + 20), 9)
  fl.Name = "Flare"
  for _, wl in ipairs(Map.OILWELLS or {}) do   -- 管线：近处几口井拉一根地面管道到集油站
    if wl.field == "B" and (wl.x - gx) ^ 2 + (wl.z - gz) ^ 2 < 1100 ^ 2 then
      local a, b = V(wl.x, gy(wl.x, wl.z) + 1, wl.z), V(gx, gy(gx, gz) + 1, gz + 30)
      local L = (b - a).Magnitude
      if L > 40 and L < 1100 then
        local nseg = math.ceil(L / 400)
        for s = 0, nseg - 1 do
          local p0, p1 = a:Lerp(b, s / nseg), a:Lerp(b, (s + 1) / nseg)
          p0 = V(p0.X, gy(p0.X, p0.Z) + 1, p0.Z)
          p1 = V(p1.X, gy(p1.X, p1.Z) + 1, p1.Z)
          part(of, V(0.9, 0.9, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), RGB(96, 92, 86), MAT.Metal)
        end
      end
    end
  end
end

-- 边境：沙墙开口两边的哨塔、开口北边的检查站和水泥岗楼；整条沙墙每隔约 1.5 公里一座哨塔（远处看得到一串）
local function border(f)
  local bf = folder("Border", f)
  local A = Map.POINTS[1]
  local bz = Map.bermZ(A.x)
  watchtower(bf, A.x - 70, bz - 34, math.pi)
  watchtower(bf, A.x + 70, bz - 34, math.pi)
  building(bf, "conc1", A.x + 150, bz - 150, math.pi)   -- 边检站
  checkpoint(bf, A.x + 16, bz - 110, 0, -1)
  for x = -Map.R + 1200, Map.R - 1200, 1500 do
    local near = math.abs(x - A.x) < 600
    for _, bx in ipairs(Map.BREACH or {}) do if math.abs(x - bx) < 160 then near = true end end
    if not near then watchtower(bf, x, Map.bermZ(x) - 36, math.pi) end
  end
end

-- 加固机库（HAS）：空军基地跑道北边一排，半圆拱的混凝土壳（埋一半），机库口朝南对着滑行道、门洞是黑的；顶上覆土长了点沙
local function shelters(f, A)
  local sf = folder("Shelters", f)
  for k = 0, 3 do
    local x, z = A.x - A.len * 0.38 + k * 140, A.z - A.wid / 2 - 240
    if Map.roadDist(x, z) > 50 then
      local y = gy(x, z)
      local L, R0 = 40, 15
      part(sf, V(L, R0 * 2, R0 * 2), CF(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), RGB(150, 140, 120), MAT.Concrete, CYL, true)   -- 拱壳（圆柱轴南北、中心在地面上：露出一半）
      part(sf, V(R0 * 1.6, R0 * 0.9, 0.6), CF(x, y + R0 * 0.45, z + L / 2 + 0.2), RGB(24, 24, 26), MAT.SmoothPlastic)   -- 门洞
      part(sf, V(R0 * 2 + 6, 3, 3), CF(x, y + 1.5, z + L / 2 + 1.5), RGB(140, 136, 126), MAT.Concrete, nil, true)   -- 门槛前的护墙
    end
  end
end

-- 死亡公路：80 号公路镇子北边到山口那一段，一路烧毁的车（卡车、坦克、民用小车），横七竖八堵在路上和路边，有的还在冒烟
local function carWreck(f, x, z, rot, col)
  local y = gy(x, z)
  local base = CF(x, y, z) * CFrame.Angles(0, rot, 0) * CFrame.Angles(0.03, 0, 0.05)
  part(f, V(6.2, 2.6, 13), base * CF(0, 1.9, 0), col, MAT.CorrodedMetal, nil, true)
  part(f, V(5.6, 1.8, 6), base * CF(0, 4, 0.8), col:Lerp(RGB(20, 18, 16), 0.4), MAT.CorrodedMetal, nil, true)
  for _, o in ipairs({ { -2.6, -4 }, { 2.6, -4 }, { -2.6, 4 }, { 2.6, 4 } }) do part(f, V(0.9, 2.2, 2.2), base * CF(o[1], 0.9, o[2]), RGB(24, 22, 20), MAT.SmoothPlastic, CYL) end
end
local function highwayOfDeath(f)
  local hf = folder("HighwayOfDeath", f)
  local R = drng(1991)
  local road
  for _, r in ipairs(Map.ROADS or {}) do if r.name == "80号公路" then road = r end end
  if not road then return end
  local smoke = 0
  local last = nil
  for i = 1, #road.x - 1 do
    local x, z = road.x[i], road.z[i]
    if z < -2600 and z > -8600 and (not last or (x - last[1]) ^ 2 + (z - last[2]) ^ 2 > 34 ^ 2) and R() < 0.55 then
      local dx, dz = road.x[i + 1] - x, road.z[i + 1] - z
      local l = math.max(0.01, math.sqrt(dx * dx + dz * dz))
      local ux, uz = dx / l, dz / l
      local off = ((R() < 0.5) and -1 or 1) * (6 + R() * 13)   -- 多数在路面两边、路肩上：路中间留一条车道（AI 的车沿路开不至于卡住）
      local px, pz = x - uz * off, z + ux * off
      local rot = math.atan2(-ux, -uz) + (R() - 0.5) * 1.2
      local r = R()
      if r < 0.16 then tankWreck(hf, px, pz, rot, false)
      elseif r < 0.5 then
        if smoke < 6 and R() < 0.5 then truck(hf, px, pz, rot, "wreck") smoke += 1 else carWreck(hf, px, pz, rot, RGB(60, 52, 44)) end
      else carWreck(hf, px, pz, rot, ({ RGB(70, 60, 50), RGB(54, 50, 46), RGB(84, 70, 54), RGB(46, 42, 40) })[1 + math.floor(R() * 4)]) end
      last = { x, z }
    end
  end
end

-- 游牧民的黑帐篷：西干河边几处（沙漠里有人住的痕迹）
local function bedouin(f)
  local R = drng(777)
  for _, c in ipairs({ { -7400, -1700 }, { -8900, 6900 }, { 9200, -2600 } }) do
    for k = 0, 2 do
      local x, z = c[1] + (R() - 0.5) * 60, c[2] + (R() - 0.5) * 60
      if Map.slope(x, z) < 0.2 then tent(f, x, z, R() * 3, RGB(40, 34, 30)) end
    end
  end
end

-- 全图的掩体和地物（用户 11-24：「细节密度加到爆，要能在任何位置都适合打坦克战、空战」「地图不够精细、细节少」）：
--   战区（两边主基地之间）按 600 格的网格，每格按定死的种子撒一样东西——坦克掩体（U 形土堤，车躲在后面只露炮塔）、岩石露头、
--   废弃的泥砖院子、烧毁的车（不冒烟：几百处一起冒烟太费）、沙袋阵地、散落的水泥墩、扔下的集装箱；避开路、据点、镇子、两边基地、陡坡、沙墙
local function sandsCover(f)
  local cf0 = folder("Cover", f)
  local R = Random.new(24113)
  local SAND, SAND2 = RGB(196, 170, 126), RGB(176, 150, 108)
  local MUD = { RGB(196, 172, 130), RGB(184, 158, 116), RGB(204, 184, 146) }
  local ROCK = { RGB(160, 128, 96), RGB(140, 116, 96), RGB(176, 146, 110), RGB(124, 108, 92) }
  local function berm2(cf, len, h, w)
    wedge(cf0, V(len, h, w / 2), cf * CF(0, h / 2, -w / 4), SAND, MAT.Sand, true)
    wedge(cf0, V(len, h, w / 2), cf * CF(0, h / 2, w / 4) * CFrame.Angles(0, math.pi, 0), SAND, MAT.Sand, true)
  end
  local function ok(x, z, r)
    if Map.roadDist(x, z) < r + 30 then return false end
    for _, p in ipairs(Map.POINTS) do
      local rr = (p.id == "C") and 1100 or 520
      if (p.x - x) ^ 2 + (p.z - z) ^ 2 < rr * rr then return false end
    end
    for _, B in pairs(Map.BASES or {}) do
      local q = B.rect
      if x > q.x0 - 500 and x < q.x1 + 500 and z > q.z0 - 500 and z < q.z1 + 500 then return false end
    end
    if Map.bermZ and math.abs(z - Map.bermZ(x)) < 120 then return false end
    if (Map.AIRFIELD.x - x) ^ 2 + (Map.AIRFIELD.z - z) ^ 2 < 2400 ^ 2 then return false end
    for _, o in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
      if Map.slope(x + o[1], z + o[2]) > 0.28 then return false end
    end
    return true
  end
  local function base(x, z, rot)
    local y = math.huge
    for _, o in ipairs({ { 0, 0 }, { 8, 8 }, { -8, 8 }, { 8, -8 }, { -8, -8 } }) do y = math.min(y, Map.ground(x + o[1], z + o[2])) end
    return CF(x, y, z) * CFrame.Angles(0, rot, 0)
  end
  -- 坦克战要的是到处都有能藏车身的东西：长条土堤、坦克掩体、大石头多放（零件少、挡得多），院子、残骸、沙袋、水泥墩、集装箱点缀
  local kinds = { "bermline", "bermline", "bermline", "berm", "berm", "rock", "rock", "rock", "ruin", "wreck", "bags", "jersey", "conex" }
  local n = 0
  for gx = -14100, 14100, 450 do
    for gz = -14700, 14700, 450 do
      local x, z = gx + R:NextNumber(-170, 170), gz + R:NextNumber(-170, 170)
      local kind = kinds[R:NextInteger(1, #kinds)]
      local rot = R:NextNumber(0, math.pi * 2)
      if R:NextNumber() < 0.86 and ok(x, z, 26) then
        n += 1
        local c = base(x, z, rot)
        if kind == "bermline" then   -- 长条土堤：两三段、拐着弯，五到八格高（坦克车身全藏住，只露炮塔）
          local len, h = R:NextNumber(50, 85), R:NextNumber(5, 8)
          local cc = c
          for _ = 1, R:NextInteger(2, 3) do
            berm2(cc, len, h, h * 2.8)
            cc = cc * CF(len / 2, 0, 0) * CFrame.Angles(0, R:NextNumber(-0.4, 0.4), 0) * CF(len / 2, 0, 0)
            local q = cc.Position
            cc = CF(q.X, Map.ground(q.X, q.Z), q.Z) * (cc - q)
          end
        elseif kind == "berm" then   -- 坦克掩体：前面一道、两边两道，口朝后；有的两三个并排
          local face = (R:NextNumber() < 0.5) and 0 or math.pi   -- 朝南或朝北（两边都用得上）
          local cc = base(x, z, face + R:NextNumber(-0.3, 0.3))
          for k = 0, R:NextInteger(0, 1) do
            local u = cc * CF(k * 34, 0, 0)
            berm2(u * CF(0, 0, -11), 26, 5.5, 10)
            for _, sx in ipairs({ -13, 13 }) do   -- 两边的矮堤：一块斜着的楔子（往后越来越低）
              wedge(cf0, V(5, 4.5, 18), u * CF(sx, 2.25, -1) * CFrame.Angles(0, math.pi, 0), SAND2, MAT.Sand, true)
            end
          end
        elseif kind == "rock" then   -- 岩石露头：几块转着的大石头挤在一起
          for k = 1, R:NextInteger(2, 4) do
            local sx, sy, sz = R:NextNumber(10, 28), R:NextNumber(6, 16), R:NextNumber(10, 24)
            local pc = c * CF(R:NextNumber(-12, 12), sy * 0.3, R:NextNumber(-12, 12)) * CFrame.Angles(R:NextNumber(-0.3, 0.3), R:NextNumber(0, 6.28), R:NextNumber(-0.3, 0.3))
            local rk = part(cf0, V(sx, sy, sz), pc, ROCK[R:NextInteger(1, #ROCK)], (k % 2 == 0) and MAT.Sandstone or MAT.Rock, nil, true)
            rk.CastShadow = sx > 8
          end
        elseif kind == "ruin" then   -- 废弃院子：一圈塌了一半的泥砖墙、院里一座塌了顶的房子、碎砖堆
          local col = MUD[R:NextInteger(1, #MUD)]
          for sd = 0, 3 do
            local w = c * CFrame.Angles(0, sd * math.pi / 2, 0)
            for seg = -1, 1 do
              if R:NextNumber() < 0.6 then
                local h = R:NextNumber(3, 8)
                part(cf0, V(12, h, 1.4), w * CF(seg * 13, h / 2, -19), col, MAT.Sandstone, nil, true)
              end
            end
          end
          local hh = R:NextNumber(6, 10)
          part(cf0, V(16, hh, 1.2), c * CF(4, hh / 2, -4), col, MAT.Sandstone, nil, true)
          part(cf0, V(1.2, hh * 0.7, 12), c * CF(-4, hh * 0.35, 2), col, MAT.Sandstone, nil, true)
          part(cf0, V(10, 3, 8), c * CF(6, 1, 4) * CFrame.Angles(0.2, 0.5, 0.1), col:Lerp(RGB(120, 100, 80), 0.3), MAT.Sandstone, nil, true)
          for k = 1, 2 do part(cf0, V(2, 1.2, 1.6), c * CF(R:NextNumber(-12, 12), 0.5, R:NextNumber(-12, 12)) * CFrame.Angles(0, R:NextNumber(0, 3), 0.3), col, MAT.Sandstone) end
        elseif kind == "wreck" then   -- 烧毁的车：坦克或卡车，旁边炸飞的炮塔 / 车门
          local burnt = RGB(42, 38, 34)
          if R:NextNumber() < 0.55 then
            part(cf0, V(10, 3.2, 20), c * CF(0, 2.4, 0) * CFrame.Angles(0.05, 0, -0.06), burnt, MAT.CorrodedMetal, nil, true)
            for _, sx in ipairs({ -5.4, 5.4 }) do part(cf0, V(1.8, 2.8, 21), c * CF(sx, 1.4, 0), RGB(30, 28, 26), MAT.Metal, nil, true) end
            local tur = c * CF(9, 1.2, 7) * CFrame.Angles(0.3, 1.1, 0.5)
            part(cf0, V(7, 2.6, 8), tur, RGB(48, 44, 40), MAT.CorrodedMetal, nil, true)
            part(cf0, V(11, 0.8, 0.8), tur * CF(0, 0, -9) * CFrame.Angles(0, math.pi / 2, 0), RGB(36, 34, 32), MAT.Metal, CYL)
          else
            part(cf0, V(5.4, 4.4, 5), c * CF(0, 3, -6) * CFrame.Angles(0, 0, 0.12), burnt, MAT.CorrodedMetal, nil, true)
            part(cf0, V(5.6, 1, 12), c * CF(0, 1.4, 2.4) * CFrame.Angles(0.06, 0, 0.12), burnt, MAT.CorrodedMetal, nil, true)
            for _, wz in ipairs({ -6, 2, 5.6 }) do part(cf0, V(5.8, 2.8, 2.8), c * CF(0, 1.2, wz), RGB(26, 26, 28), MAT.SmoothPlastic, CYL) end
          end
        elseif kind == "bags" then   -- 沙袋阵地：马蹄形，口朝后
          for k = 0, 4 do
            local a = (k - 2) * 0.55
            local bc = c * CFrame.Angles(0, a, 0) * CF(0, 0, -7)
            for r = 0, 1 do part(cf0, V(5.6 - r * 0.4, 1.4, 2.2 - r * 0.2), bc * CF(0, 0.7 + r * 1.4, 0), (r == 0) and C.sandbag or RGB(156, 140, 100), MAT.Fabric, nil, true) end
          end
        elseif kind == "jersey" then   -- 散落的水泥墩（以前的检查站）
          for k = 1, R:NextInteger(3, 6) do
            local jc = c * CF(R:NextNumber(-16, 16), 0, R:NextNumber(-10, 10)) * CFrame.Angles(0, R:NextNumber(-0.5, 0.5) + ((k % 2 == 0) and 0 or 1.57), R:NextNumber() < 0.2 and 1.4 or 0)
            part(cf0, V(8.4, 1.1, 2.3), jc * CF(0, 0.55, 0), RGB(184, 180, 168), MAT.Concrete, nil, true)
            part(cf0, V(8.4, 1.5, 0.95), jc * CF(0, 1.85, 0), RGB(184, 180, 168), MAT.Concrete, nil, true)
          end
        else   -- 扔下的集装箱：一个立着、有的翻倒
          local cols = { RGB(128, 98, 70), RGB(92, 104, 84), RGB(132, 64, 52), RGB(72, 88, 112) }
          for k = 0, R:NextInteger(0, 1) do
            local tip = (k == 1) and 1.57 or 0
            local cc = c * CF(k * 12, 0, k * 4) * CFrame.Angles(0, k * 0.4, 0) * CFrame.Angles(0, 0, tip)
            part(cf0, V(17, 7.2, 6.8), cc * CF(0, tip > 0 and 3.4 or 3.6, tip > 0 and 0 or 0) , cols[R:NextInteger(1, #cols)], MAT.CorrodedMetal, nil, true)
          end
        end
      end
    end
  end
  -- 电线杆：沿 80 号公路、6 号公路一侧（木杆、横担、三根线垂下来一点）
  local pf = folder("Poles", f)
  for _, rd in ipairs(Map.ROADS) do
    if rd.name == "80号公路" or rd.name == "6号公路" then
      local acc, prev = 0, nil
      for i = 2, #rd.x do
        local ax, az, bx, bz = rd.x[i - 1], rd.z[i - 1], rd.x[i], rd.z[i]
        local dx, dz = bx - ax, bz - az
        local L = math.sqrt(dx * dx + dz * dz)
        acc += L
        if acc >= 160 and L > 1 then
          acc = 0
          local sx, sz = -dz / L, dx / L
          local x, z = bx + sx * (rd.w * 0.5 + 12), bz + sz * (rd.w * 0.5 + 12)
          local inside = false
          for _, B in pairs(Map.BASES or {}) do
            local q = B.rect
            if x > q.x0 and x < q.x1 and z > q.z0 and z < q.z1 then inside = true end
          end
          if not inside and math.abs(x) < 30000 and math.abs(z) < 30000 then
            local y = Map.ground(x, z)
            local top = V(x, y + 22, z)
            cyl(pf, 22, 0.8, CF(x, y + 11, z), RGB(96, 76, 56), MAT.Wood, true)
            part(pf, V(7, 0.5, 0.5), CFrame.lookAt(top - V(0, 1.5, 0), top - V(0, 1.5, 0) + V(sx, 0, sz)), RGB(96, 76, 56), MAT.Wood)
            if prev and (prev - top).Magnitude < 260 then
              for _, o in ipairs({ -2.8, 2.8 }) do   -- 两根线（直的，省零件）
                local a = prev + V(sx, 0, sz) * o - V(0, 1.2, 0)
                local b = top + V(sx, 0, sz) * o - V(0, 1.2, 0)
                local w = part(pf, V(0.12, 0.12, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), RGB(30, 30, 30), MAT.Metal)
                w.CastShadow = false
              end
            end
            prev = top
          end
        end
      end
    end
  end
  return n
end

function World.desert(f)
  local df = folder("Desert", f)
  local ok, err
  for _, s in ipairs({ { "镇子", desertTown }, { "油田", oilfield }, { "边境", border }, { "死亡公路", highwayOfDeath }, { "黑帐篷", bedouin },
    { "掩体和地物", function(ff) if Map.BASES then sandsCover(ff) end end } }) do   -- 红方前进基地改成 FOB.lua 的主基地
    ok, err = pcall(s[2], df)
    if not ok then warn("[沙漠] " .. s[1] .. "出错：" .. tostring(err)) end
  end
  ok, err = pcall(shelters, df, Map.AIRFIELD)
  if not ok then warn("[沙漠] 加固机库出错：" .. tostring(err)) end
end

function World.details(f)
  local ef = folder("Details", f)
  local bf = folder("Buildings", f)
  airfieldExtras(ef, Map.AIRFIELD)
  if not Map.BASES then   -- 沙海的两边主基地自己有一整套（FOB.lua）
    local A2 = Map.AFIELD2
    airfieldExtras(ef, { x = A2.x, z = A2.z, y = A2.y, len = A2.len, wid = A2.wid })
  end
  commandExtras(ef)
  if not Map.BASES then campExtras(ef) end
  outpostExtras(ef, bf)
  beachLines(ef)
  wrecks(ef)
  checkpoints(ef)
end

-- 开服时建整张地图；地形分块写（要好几秒），写完才让人出生
function World.build(G)
  World.lighting()
  local root = folder("Map")
  local deco = folder("Scenery", root)
  local n, chunks = World.terrain(function(p) G.worldProgress = p end, G)
  G.terrainVoxels, G.terrainChunks = n, chunks
  -- 远海改在客户端跟着镜头铺（Scenery.lua）：地图放大以后服务器这一圈不够远，飞机飞出去看得到海的尽头
  G.try("机场", airfield, deco, Map.AIRFIELD, "def")
  if Map.LANDONLY then   -- 沙漠图：没有港口、灯塔、岸防炮台、海滩
    G.try("指挥所", commandPost, deco)
    -- 两边的主基地（FOB.lua：营区 + 机场 + 车场 + 直升机坪围在一起，用户 11-24「军事基地应该在一起」）；原来的守方营地、红方前进基地、前进机场不建了
    local FOB = require(script.Parent:WaitForChild("FOB"))
    G.fobParts = {}
    for _, side in ipairs({ "atk", "def" }) do
      G.try("主基地 " .. side, function() G.fobParts[side] = FOB.build(World, deco, side) end)
    end
    G.try("沙漠", World.desert, deco)
    G.try("细节", World.details, deco)
  else
    G.try("港口镇", portTown, deco)
    G.try("指挥所", commandPost, deco)
    G.try("营地", camp, deco)
    G.try("灯塔", lighthouse, deco)
    G.try("岸防炮台", battery, deco)
    G.try("攻方机场岛", attackerAirfield, deco)
    G.try("海滩标杆", World.beaches, deco)
    G.try("细节", World.details, deco)
  end
  G.pointModels = World.points(folder("Points", root))
  G.decks = World.fleet(folder("Fleet", root))
  G.worldReady = true
end

return World
