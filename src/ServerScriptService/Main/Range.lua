-- 全面大战场——训练场（服务器）：照 MapRange 铺地形、摆靶场设施（区块 Zones.RANGE，离战场十万格，见 Zones.lua）
--   用户 11-26 晚：「把训练场单独做一张地图吧」「目前游戏里的几个地图是连起来的 不行」——试驾（Tech.lua）都在这里，不再在战场边上打靶。
--   开服时 World.build 建完战场以后调 Range.build（后台慢慢建，不耽误战场开局）：
--   ① 靶场那一片的平地（FillBlock 一块 2048 格见方、两层体素），靶道土路、跑道两边的土、几片深草盖在最上面一层
--   ② 挡弹土墙按高度逐列写体素（World.writeChunk：Map 的高度、材质函数按区块分派，训练场的点问 MapRange）
--   ③ 设施：射击线（每条靶道一块水泥坪、靶道号）、距离牌（300 ~ 2000 米）、靶道分界杆、指挥塔、旗杆、探照灯；
--      跑道（World.airfield：跑道、停机坪、机库、塔台、跑道灯，同战场的机场）、直升机坪；空中靶区的废车和集装箱
--   ④ G.rangeReady = true（试驾可以开始）；再往后：外圈平地、丘陵（远景，按块逐列写，每帧几毫秒）
local RS = game:GetService("ReplicatedStorage")
local Map = require(RS:WaitForChild("Map"))
local R = require(RS:WaitForChild("MapRange"))

local Range = {}

local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
local ANG = CFrame.Angles
local M = 2.8
local TILE, CH = 2048, 256
local BASE_D = 8   -- 平地往下铺几格（两层体素：弹坑最深 5.5 格，挖不穿）

local COL = {
  conc = RGB(170, 166, 156), concDk = RGB(132, 128, 120), white = RGB(236, 234, 226), red = RGB(196, 52, 44), yellow = RGB(226, 186, 52),
  wood = RGB(126, 96, 64), post = RGB(70, 72, 74), board = RGB(36, 40, 44), olive = RGB(84, 94, 66), rust = RGB(110, 78, 58),
  sand = RGB(176, 160, 118), glass = RGB(52, 66, 78), roof = RGB(78, 82, 84),
}

local function folder(name, parent)
  local f = Instance.new("Folder")
  f.Name = name
  f.Parent = parent
  return f
end

-- 牌子上的字（SurfaceGui，正面朝 face）
local function board(W, f, cf, w, h, text, color, face)
  local b = W.part(f, V(w, h, 0.6), cf, COL.board, MAT.SmoothPlastic, nil, true)
  local sg = Instance.new("SurfaceGui")
  sg.Face = face or Enum.NormalId.Back
  sg.CanvasSize = Vector2.new(w * 40, h * 40)
  sg.LightInfluence = 0.6
  sg.Parent = b
  local t = Instance.new("TextLabel")
  t.Size = UDim2.fromScale(1, 1)
  t.BackgroundTransparency = 1
  t.TextScaled = true
  t.Font = Enum.Font.BuilderSansBold
  t.TextColor3 = color or COL.white
  t.Text = text
  t.Parent = sg
  return b
end

---------------------------------------------------------------- 地形

local function grassMat() return Map.GRASS and MAT.Grass or MAT.LeafyGrass end

-- 一块平地（世界坐标 x0, z0 起、边长 n）
local function flatTile(T, x0, z0, n)
  local y1 = R.PLAIN
  T:FillBlock(CF(x0 + n / 2, y1 - BASE_D / 2, z0 + n / 2), V(n, BASE_D, n), grassMat())
end
-- 最上面一层换材质（土路、深草）：一条矩形
local function topRect(T, cx, cz, sx, sz, mat)
  T:FillBlock(CF(cx, R.PLAIN - 2, cz), V(sx, 4, sz), mat)
end

-- 靶场一带（核心）：开服就铺；外圈、丘陵后台慢慢铺
local CORE = R.CORE
local function tilesIn(u0, w0, u1, w1)
  local out = {}
  for u = u0, u1 - TILE, TILE do
    for w = w0, w1 - TILE, TILE do
      out[#out + 1] = { R.X + u, R.Z + w }
    end
  end
  return out
end

-- 有起伏的块（挡弹墙、丘陵）：世界坐标的块左下角
local function reliefChunks(u0, w0, u1, w1)
  local out = {}
  for u = u0, u1 - CH, CH do
    for w = w0, w1 - CH, CH do
      local x0, z0 = R.X + u, R.Z + w
      if R.reliefIn(x0, z0, x0 + CH, z0 + CH) then out[#out + 1] = { x0, z0 } end
    end
  end
  return out
end

---------------------------------------------------------------- 设施

local function firingLine(W, f)
  local lanesF = folder("Lanes", f)
  local LW = R.LANE_W
  for i = 1, R.LANES do
    local p = R.lane(i)
    local y = p.Y
    -- 射击位：一块水泥坪（车停上面），前沿一道黄线
    W.part(lanesF, V(80, 0.5, 56), CF(p.X, y + 0.05, p.Z + 6), COL.conc, MAT.Concrete, nil, true)
    W.part(lanesF, V(80, 0.06, 1.4), CF(p.X, y + 0.33, p.Z - 22), COL.yellow, MAT.SmoothPlastic)
    -- 靶道号：射击位左前方一块大牌子（对着车里的人）
    local nb = CF(p.X - 52, y + 9, p.Z - 36)
    W.part(lanesF, V(0.8, 9, 0.8), nb * CF(-5, -4.5, 0), COL.post, MAT.Metal, nil, true)
    W.part(lanesF, V(0.8, 9, 0.8), nb * CF(5, -4.5, 0), COL.post, MAT.Metal, nil, true)
    board(W, lanesF, nb * CF(0, 2, 0), 12, 8, tostring(i), COL.yellow, Enum.NormalId.Back)
    -- 距离牌：靶道左边沿，每个靶位一块（朝射击线）
    for _, d in ipairs(R.DIST) do
      local q = R.laneAt(i, d, -LW / 2 / M + 6)
      local c = CF(q.X, q.Y + 6, q.Z)
      W.part(lanesF, V(0.7, 6, 0.7), c * CF(0, -3, 0), COL.post, MAT.Metal, nil, true)
      board(W, lanesF, c * CF(0, 2.6, 0), 10, 4.4, d .. " m", COL.white, Enum.NormalId.Back)
    end
  end
  -- 靶道分界：红白相间的杆，每 250 米一根
  local poles = folder("LaneMarks", f)
  local p0 = R.lane(1)
  for i = 0, R.LANES do
    local x = p0.X - LW / 2 + i * LW
    for dist = 0, 2000, 250 do
      local z = p0.Z - dist * M
      local g = R.ground(x, z)
      W.part(poles, V(1, 5, 1), CF(x, g + 2.5, z), (dist % 500 == 0) and COL.red or COL.white, MAT.SmoothPlastic, nil, true)
    end
  end
  -- 射击线后面：指挥塔（两层，顶上玻璃观察室）、旗杆、探照灯
  local mid = R.lane(math.floor(R.LANES / 2))
  local tx, tz = mid.X + LW / 2, mid.Z + 360
  local ty = R.ground(tx, tz)
  local tw = folder("Tower", f)
  W.part(tw, V(36, 26, 30), CF(tx, ty + 13, tz), COL.conc, MAT.Concrete, nil, true)
  W.part(tw, V(42, 1.2, 36), CF(tx, ty + 26.6, tz), COL.concDk, MAT.Concrete, nil, true)
  local glass = W.part(tw, V(38, 9, 32), CF(tx, ty + 31.7, tz), COL.glass, MAT.Glass, nil, true)
  glass.Transparency = 0.35
  W.part(tw, V(44, 1.4, 38), CF(tx, ty + 36.9, tz), COL.roof, MAT.Metal, nil, true)
  for k = -1, 1 do W.part(tw, V(5, 9, 0.4), CF(tx + k * 12, ty + 12, tz - 15.2), COL.glass, MAT.Glass) end   -- 正面窗
  W.part(tw, V(8, 14, 0.4), CF(tx + 13, ty + 7, tz + 15.2), COL.wood, MAT.WoodPlanks)   -- 后门
  board(W, tw, CF(tx, ty + 22, tz - 15.5), 28, 4.4, "RANGE CONTROL · 训练场", COL.white, Enum.NormalId.Front)
  for k = -2, 2 do
    local fx = tx + k * 10
    W.part(tw, V(0.6, 26, 0.6), CF(fx, ty + 13, tz - 40), COL.white, MAT.Metal, nil, true)
    W.part(tw, V(7, 4.2, 0.2), CF(fx + 3.6, ty + 23.6, tz - 40), (k % 2 == 0) and COL.red or COL.yellow, MAT.Fabric)
  end
  for i = 1, R.LANES, 2 do
    local p = R.lane(i)
    W.floodPole(f, p.X + LW / 2, R.ground(p.X + LW / 2, p.Z + 80), p.Z + 80, 26, nil, 220)
  end
end

local function heliPad(W, f)
  local hp = folder("HeliPad", f)
  for k = 0, 2 do
    local p = R.heliPad(k)
    W.part(hp, V(56, 0.6, 56), CF(p.X, p.Y + 0.05, p.Z), COL.concDk, MAT.Concrete, nil, true)
    local ring = W.part(hp, V(0.08, 44, 44), CF(p.X, p.Y + 0.4, p.Z) * ANG(0, 0, math.pi / 2), COL.yellow, MAT.SmoothPlastic, Enum.PartType.Cylinder)
    ring.CastShadow = false
    W.part(hp, V(0.1, 38, 38), CF(p.X, p.Y + 0.42, p.Z) * ANG(0, 0, math.pi / 2), COL.concDk, MAT.Concrete, Enum.PartType.Cylinder)
    -- H
    W.part(hp, V(3, 0.08, 18), CF(p.X - 6, p.Y + 0.47, p.Z), COL.white, MAT.SmoothPlastic)
    W.part(hp, V(3, 0.08, 18), CF(p.X + 6, p.Y + 0.47, p.Z), COL.white, MAT.SmoothPlastic)
    W.part(hp, V(9, 0.08, 3), CF(p.X, p.Y + 0.47, p.Z), COL.white, MAT.SmoothPlastic)
  end
end

-- 空中靶区：烧剩的车壳、集装箱、沙袋工事（对地武器打着玩；真正的靶车由 Tech.lua 按每个人摆）
local function targetArea(W, f)
  local ta = folder("TargetArea", f)
  local c = R.airTarget()
  local rnd = Random.new(9431)
  for k = 1, 14 do
    local a, rr = rnd:NextNumber(0, math.pi * 2), rnd:NextNumber(150, 1100)
    local x, z = c.X + math.cos(a) * rr, c.Z + math.sin(a) * rr
    local g = R.ground(x, z)
    local rot = rnd:NextNumber(0, math.pi * 2)
    if k % 3 == 0 then   -- 集装箱
      W.part(ta, V(16, 7.6, 6.4), CF(x, g + 3.8, z) * ANG(0, rot, 0), (k % 2 == 0) and COL.rust or COL.olive, MAT.CorrodedMetal, nil, true)
    else   -- 车壳（烧黑的车体 + 炮塔）
      local base = CF(x, g, z) * ANG(0, rot, 0)
      W.part(ta, V(9, 2.6, 18), base * CF(0, 2.3, 0), RGB(44, 42, 40), MAT.CorrodedMetal, nil, true)
      W.part(ta, V(6.4, 2.2, 7), base * CF(0, 4.7, -1), RGB(52, 50, 47), MAT.CorrodedMetal, nil, true)
      W.part(ta, V(0.7, 0.7, 9), base * CF(0, 5, -8.5) * ANG(math.rad(-6), 0, 0), RGB(40, 40, 40), MAT.Metal)
    end
  end
  W.sandbags(ta, V(c.X, 0, c.Z), 26, 0, math.pi * 1.6, 3)
end

---------------------------------------------------------------- 入口

function Range.build(World, G, root)
  local T = workspace.Terrain
  local f = folder("Range", root or workspace)
  pcall(function() f:SetAttribute("Zone", "range") end)
  G.rangeFolder = f
  local noTerrain = G.rangeTerrainOff == true   -- 模拟器（tools/mock/common.lua）：别的测试用不着训练场的地形
  local t0 = os.clock()
  local function pace(budget)
    if os.clock() - t0 > (budget or 0.012) then
      task.wait()
      t0 = os.clock()
    end
  end
  -- ① 靶场一带的平地，靶道土路、射击线后的土路、跑道两边的土
  for _, t in ipairs(noTerrain and {} or tilesIn(CORE.u0, CORE.w0, CORE.u1, CORE.w1)) do
    flatTile(T, t[1], t[2], TILE)
    pace()
  end
  local p1 = R.lane(1)
  local trackLen = 2000 * M + 300
  local A = R.airfield()
  if not noTerrain then
    for i = 1, R.LANES do
      local p = R.lane(i)
      topRect(T, p.X, p.Z - trackLen / 2 + 120, 68, trackLen, MAT.Ground)
    end
    topRect(T, (p1.X + R.lane(R.LANES).X) / 2, p1.Z + 160, R.LANES * R.LANE_W, 80, MAT.Ground)
    topRect(T, A.x, A.z, A.len + 120, A.wid + 60, MAT.Ground)
    -- 几片深草、裸土（草地看着不是一整块）
    local rnd = Random.new(5521)
    for _ = 1, 40 do
      local u, w = rnd:NextNumber(CORE.u0 + 400, CORE.u1 - 400), rnd:NextNumber(CORE.w0 + 400, CORE.w1 - 400)
      local x, z = R.X + u, R.Z + w
      if R.material(x, z, R.PLAIN, 0) ~= MAT.Ground and not R.reliefIn(x - 200, z - 200, x + 200, z + 200) then
        local r = rnd:NextNumber(60, 220)
        pcall(function() T:FillCylinder(CF(x, R.PLAIN - 2, z), 4, r, (rnd:NextNumber() < 0.75) and MAT.LeafyGrass or MAT.Ground) end)
      end
    end
    -- ② 挡弹土墙
    for _, c in ipairs(reliefChunks(-R.BERM_HALF - 512, R.BERM_W - 1024, R.BERM_HALF + 512, R.BERM_W + 1024)) do
      World.writeChunk(T, c[1], c[2])
      pace()
    end
  end
  -- ③ 设施
  G.try("训练场 靶道", firingLine, World, f)
  G.try("训练场 跑道", function() World.airfield(folder("Airfield", f), { x = A.x, z = A.z, len = A.len, wid = A.wid, y = R.PLAIN }, "range") end)
  G.try("训练场 直升机坪", heliPad, World, f)
  G.try("训练场 靶区", targetArea, World, f)
  G.rangeReady = true
  print("[全面大战场] 训练场好了（靶场一带），外圈和丘陵后台接着铺")
  -- ④ 外圈平地、丘陵（远景）：每帧几毫秒，慢慢铺
  if noTerrain then return end
  local RR = R.R
  for _, t in ipairs(tilesIn(-RR, -RR, RR, RR)) do
    local u, w = t[1] - R.X, t[2] - R.Z
    if not (u >= CORE.u0 and u < CORE.u1 and w >= CORE.w0 and w < CORE.w1) then
      flatTile(T, t[1], t[2], TILE)
      pace(0.004)
    end
  end
  local hills = reliefChunks(-RR, -RR, RR, RR)
  local n = 0
  for _, c in ipairs(hills) do
    local u, w = c[1] - R.X, c[2] - R.Z
    if not (w > R.BERM_W - 1024 and w < R.BERM_W + 1024 and math.abs(u) < R.BERM_HALF + 512) then   -- 挡弹墙那几块铺过了
      World.writeChunk(T, c[1], c[2])
      n += 1
      pace(0.004)
    end
  end
  G.rangeHills = n
  print("[全面大战场] 训练场丘陵铺完：" .. n .. " 块")
end

return Range
