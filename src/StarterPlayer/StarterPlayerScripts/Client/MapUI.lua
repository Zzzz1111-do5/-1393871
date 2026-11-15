-- Roblox全面大战场——地图界面：按 Map.lua 的高度画出群岛（每行相邻的同色格并成一块，几百个方块），标据点、海滩、舰队、出生点、自己、被标记的敌人
--   部署界面的大地图和右下角的小地图是同一张图：换父级、改大小（里面都按比例摆）
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MapUI = {}

function MapUI.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local Config = G.Config
  local player = Players.LocalPlayer
  local RGB = Color3.fromRGB

  -- 地图范围（世界坐标）：所有岛和舰队都在里面
  local X0, X1, Z0, Z1 = -3000, 3000, -2500, 3600
  local SPAN = math.max(X1 - X0, Z1 - Z0)
  local function toUV(x, z) return (x - X0) / SPAN, (z - Z0) / SPAN end
  G.mapUV = toUV

  local root = Instance.new("Frame")
  root.Name = "IslandMap"
  root.BackgroundColor3 = RGB(28, 86, 118)
  root.BorderSizePixel = 0
  root.ClipsDescendants = true
  root.SizeConstraint = Enum.SizeConstraint.RelativeYY
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = root
  local land = Instance.new("Frame")
  land.Name = "Land"
  land.BackgroundTransparency = 1
  land.Size = UDim2.fromScale(1, 1)
  land.Parent = root
  local marks = Instance.new("Frame")
  marks.Name = "Marks"
  marks.BackgroundTransparency = 1
  marks.Size = UDim2.fromScale(1, 1)
  marks.ZIndex = 3
  marks.Parent = root

  -- 陆地：按高度分几档颜色
  local function band(y)
    if y <= 0.3 then return nil end
    if y < 4 then return 1 end
    if y < 40 then return 2 end
    if y < 110 then return 3 end
    if y < 200 then return 4 end
    return 5
  end
  local BAND = { RGB(214, 198, 150), RGB(98, 140, 72), RGB(80, 120, 60), RGB(104, 112, 78), RGB(140, 136, 128) }
  local N = 110
  local cell = SPAN / N
  task.spawn(function()
    for j = 0, N - 1 do
      local z = Z0 + (j + 0.5) * cell
      local runB, runI = nil, 0
      for i = 0, N do
        local b = nil
        if i < N then b = band(Map.height(X0 + (i + 0.5) * cell, z)) end
        if b ~= runB then
          if runB then
            local f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.BackgroundColor3 = BAND[runB]
            f.Position = UDim2.fromScale(runI / N, j / N)
            f.Size = UDim2.fromScale((i - runI) / N, 1 / N + 0.0008)
            f.Parent = land
          end
          runB, runI = b, i
        end
      end
      if j % 12 == 0 then task.wait() end
    end
  end)

  local function dot(parent, u, v, size, color, text, z)
    local f = Instance.new("TextLabel")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(u, v)
    f.Size = UDim2.fromOffset(size, size)
    f.BackgroundColor3 = color
    f.BorderSizePixel = 0
    f.Text = text or ""
    f.TextColor3 = Color3.new(1, 1, 1)
    f.TextScaled = true
    f.Font = Enum.Font.GothamBlack
    f.ZIndex = z or 4
    f.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
    local s = Instance.new("UIStroke")
    s.Thickness = 1.5
    s.Color = Color3.new(0, 0, 0)
    s.Transparency = 0.3
    s.Parent = f
    return f
  end
  G.mapDot = dot

  -- 据点
  local pointDots = {}
  for _, p in ipairs(Map.POINTS) do
    local u, v = toUV(p.x, p.z)
    pointDots[p.id] = dot(marks, u, v, 22, Config.Teams.def.color, p.id, 5)
  end
  -- 舰队、机场岛（小灰块）
  for _, s in ipairs(Map.FLEET) do
    local u, v = toUV(s.x, s.z)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(u, v)
    f.Size = UDim2.fromScale((s.kind == "lst") and 0.006 or 0.009, (s.kind == "carrier") and 0.1 or 0.07)
    f.Size = UDim2.fromScale(0.012, (s.kind == "carrier") and 0.09 or ((s.kind == "lhd") and 0.07 or 0.045))
    f.BackgroundColor3 = RGB(70, 76, 82)
    f.BorderSizePixel = 0
    f.ZIndex = 2
    f.Parent = marks
  end
  -- 海滩：彩色短线
  for _, b in ipairs(Map.BEACHES) do
    local u0, v = toUV(b.x0, b.z)
    local u1 = toUV(b.x1, b.z)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0, 0.5)
    f.Position = UDim2.fromScale(u0, v)
    f.Size = UDim2.new(u1 - u0, 0, 0, 4)
    f.BackgroundColor3 = b.color
    f.BorderSizePixel = 0
    f.ZIndex = 2
    f.Parent = marks
  end

  -- 自己（箭头）、被标记的敌人（红点）
  local me = dot(marks, 0.5, 0.5, 10, RGB(255, 255, 255), "", 7)
  me.Visible = false
  local spotDots = {}

  function G.mapRefresh(S)
    if S and S.points then
      for _, s in ipairs(S.points) do
        local d = pointDots[s.id]
        if d then
          local col = Config.Teams[s.owner].color
          if s.owner == "def" and s.prog > 0 then col = col:Lerp(Config.Teams.atk.color, s.prog) end
          d.BackgroundColor3 = col
        end
      end
    end
  end

  function G.mapSpots(list)
    for _, d in ipairs(spotDots) do d:Destroy() end
    spotDots = {}
    for _, p in ipairs(list or {}) do
      local u, v = toUV(p.X, p.Z)
      table.insert(spotDots, dot(marks, u, v, 8, RGB(255, 50, 40), "", 6))
    end
  end

  function G.stepMap()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and root.Parent then
      local u, v = toUV(hrp.Position.X, hrp.Position.Z)
      me.Position = UDim2.fromScale(u, v)
      me.Visible = true
    else
      me.Visible = false
    end
  end

  -- 放到某个界面里：size 是 UDim2，pos 位置
  function G.mapMount(parent, size, pos, anchor)
    root.Parent = parent
    root.Size = size
    root.Position = pos or UDim2.new()
    root.AnchorPoint = anchor or Vector2.new()
    return root, marks
  end
  G.mapRoot = root
end

return MapUI
