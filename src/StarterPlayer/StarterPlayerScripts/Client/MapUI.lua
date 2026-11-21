-- Roblox全面大战场——地图界面：按 Map.lua 的高度画出群岛（每行相邻的同色格并成一块，几百个方块），标据点、海滩、舰队、出生点、自己、被标记的敌人
--   部署界面的大地图和右上角的小地图是同一张图：换父级、改大小（里面都按比例摆）
--   有 EditableImage 时上面盖一张 MapPaint 画的卫星图（整张图的底图 + 小地图身边的细节块），见下面「卫星图」
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MapUI = {}

function MapUI.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local Config = G.Config
  local player = Players.LocalPlayer
  local RGB = Color3.fromRGB

  -- 地图范围（世界坐标）：所有岛和舰队都在里面
  local K = Map.K or 1   -- 地图放大的倍数（Map.lua）
  local X0, X1, Z0, Z1 = -3000 * K, 3000 * K, -2500 * K, 3600 * K
  local SPAN = math.max(X1 - X0, Z1 - Z0)
  local function toUV(x, z) return (x - X0) / SPAN, (z - Z0) / SPAN end
  G.mapUV = toUV
  G.mapXZ = function(u, v) return X0 + u * SPAN, Z0 + v * SPAN end   -- 地图上的点 → 世界坐标（战术平板点目标用）
  G.mapSpan = SPAN

  local root = Instance.new("Frame")
  root.Name = "IslandMap"
  -- 配色压暗、去饱和（用户：界面太卡通，要精致、简洁）：深色的海、灰绿的陆地、细网格、直角
  root.BackgroundColor3 = RGB(14, 24, 32)
  root.BorderSizePixel = 0
  root.ClipsDescendants = true
  root.SizeConstraint = Enum.SizeConstraint.RelativeYY
  local land = Instance.new("Frame")
  land.Name = "Land"
  land.BackgroundTransparency = 1
  land.Size = UDim2.fromScale(1, 1)
  land.Parent = root
  local bands = Instance.new("Frame")   -- 按高度分档的色块、路线（有卫星图以后藏起来：用不了 EditableImage 时才看得到）
  bands.Name = "Bands"
  bands.BackgroundTransparency = 1
  bands.Size = UDim2.fromScale(1, 1)
  bands.Parent = land
  for k = 1, 7 do   -- 细网格
    for _, vert in ipairs({ true, false }) do
      local g = Instance.new("Frame")
      g.Name = "Grid"
      g.BorderSizePixel = 0
      g.BackgroundColor3 = Color3.new(1, 1, 1)
      g.BackgroundTransparency = 0.93
      g.Size = vert and UDim2.new(0, 1, 1, 0) or UDim2.new(1, 0, 0, 1)
      g.Position = vert and UDim2.fromScale(k / 8, 0) or UDim2.fromScale(0, k / 8)
      g.ZIndex = 2
      g.Parent = root
    end
  end
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
  local BAND = { RGB(118, 112, 92), RGB(62, 74, 58), RGB(54, 66, 50), RGB(70, 74, 64), RGB(92, 92, 88), RGB(42, 54, 42) }
  -- 放进左下的雷达时整张图换成墨绿（Hud.lua 调 G.mapTheme("radar")）：海近黑、陆地按高低深浅、路和网格是亮一点的绿
  local RADAR = { RGB(22, 66, 38), RGB(16, 54, 30), RGB(14, 48, 27), RGB(20, 60, 34), RGB(28, 72, 42), RGB(10, 40, 22) }
  -- 右上的小地图（用户 11-19：不要黑绿，改成正常的；再要暗淡、拟真）：深蓝的海，暗沙色海滩，暗绿的低地、山坡，高处灰褐；路是土色
  --   （有 EditableImage 时上面盖一张 MapPaint 画的卫星图，这些色块只在用不了时看得到）
  local MINI = { RGB(146, 136, 110), RGB(76, 90, 58), RGB(68, 82, 54), RGB(92, 94, 82), RGB(100, 98, 92), RGB(60, 74, 48) }
  local SEA = { map = RGB(14, 24, 32), radar = RGB(3, 14, 8), mini = RGB(22, 36, 50) }   -- 海是地图本身的颜色，不跟着界面改绿（用户 11-19：小地图不要黑绿、要拟真）
  local theme = "map"
  local landBand = {}   -- 陆地块 → 档（换配色用）
  local roads = {}
  local fleetMarks = {}   -- 舰队、机场岛的小灰块：雷达里换成暗绿
  local function landCol(b) return ((theme == "radar" and RADAR) or (theme == "mini" and MINI) or BAND)[b] end
  local N = 110
  local cell = SPAN / N
  task.spawn(function()
    for j = 0, N - 1 do
      local z = Z0 + (j + 0.5) * cell
      local runB, runI = nil, 0
      for i = 0, N do
        local b = nil
        if i < N then
          local x = X0 + (i + 0.5) * cell
          b = band(Map.height(x, z))
          -- （树林删掉了，地图上不再画深绿的林子）
        end
        if b ~= runB then
          if runB then
            local f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.BackgroundColor3 = landCol(runB)
            landBand[f] = runB
            f.Position = UDim2.fromScale(runI / N, j / N)
            f.Size = UDim2.fromScale((i - runI) / N, 1 / N + 0.0008)
            f.Parent = bands
          end
          runB, runI = b, i
        end
      end
      if j % 12 == 0 then task.wait() end
    end
    -- 路网：沿路每隔几个点连一段细线（土黄色）
    for _, r in ipairs(Map.ROADS or {}) do
      local step = 3
      for i = 1, #r.x - 1, step do
        local k = math.min(#r.x, i + step)
        local u0, v0 = toUV(r.x[i], r.z[i])
        local u1, v1 = toUV(r.x[k], r.z[k])
        local len = math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2)
        if len > 0 then
          local f = Instance.new("Frame")
          f.Name = "Road"
          f.BorderSizePixel = 0
          f.BackgroundColor3 = (theme == "radar") and RGB(70, 150, 90) or RGB(150, 140, 116)
          table.insert(roads, f)
          f.AnchorPoint = Vector2.new(0.5, 0.5)
          f.Position = UDim2.fromScale((u0 + u1) / 2, (v0 + v1) / 2)
          f.Size = UDim2.new(len * 1.04, 0, 0, 1)
          f.Rotation = math.deg(math.atan2(v1 - v0, u1 - u0))
          f.ZIndex = 2
          f.Parent = bands
        end
      end
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
    pointDots[p.id] = dot(marks, u, v, 18, Config.Teams.def.color, p.id, 5)
  end
  -- 舰队、机场岛（小灰块）
  for _, s in ipairs(Map.FLEET) do
    local u, v = toUV(s.x, s.z)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(u, v)
    f.Size = UDim2.fromScale((s.kind == "lst") and 0.006 or 0.009, (s.kind == "carrier") and 0.1 or 0.07)
    f.Size = UDim2.fromScale(0.012, (s.kind == "carrier") and 0.09 or ((s.kind == "lhd") and 0.07 or 0.045))
    f.BackgroundColor3 = (theme == "radar") and RGB(50, 110, 70) or RGB(120, 126, 132)
    f.BorderSizePixel = 0
    f.ZIndex = 2
    f.Parent = marks
    table.insert(fleetMarks, f)
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

  ---------------------------------------------------------------- 卫星图（用户 11-19：右上角小地图显示内容更精细、颜色更暗淡、更拟真）
  --   有 EditableImage（游戏设置 → 安全里打开 Mesh / Image API）就照 MapPaint 一个像素一个像素画：
  --   · 整张图一张 512 × 512 的底图（开局在后台画，每帧最多 3 毫秒，一行一行写上去），画完把色块、路线藏起来；
  --   · 小地图跟着人的时候（Hud.lua 每帧调 G.mapFocus），身边再画细节块（电脑 128 × 128 像素一块、800 格见方，每像素 6.25 格；
  --     触屏 80 × 80，每像素 10 格）：近的先画，全是深海的不画（底图就够了），最多留 36 块（最久没用的先扔）
  --   用不了 EditableImage 就照旧是色块（暗淡的那套配色）
  local AS = game:GetService("AssetService")
  local UIS = game:GetService("UserInputService")
  local Paint = require(RS:WaitForChild("MapPaint"))
  local imgOK = nil   -- nil 还没试、true 能用、false 用不了
  local function newImage(n)
    if imgOK == false then return nil end
    local ok, img = pcall(function() return AS:CreateEditableImage({ Size = Vector2.new(n, n) }) end)
    imgOK = (ok and img ~= nil) and true or false
    return imgOK and img or nil
  end
  local function satLabel(img, u0, v0, us, z)
    local l = Instance.new("ImageLabel")
    l.Name = "Sat"
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.Position = UDim2.fromScale(u0, v0)
    l.Size = UDim2.fromScale(us, us)
    l.ZIndex = z
    local ok = pcall(function() l.ImageContent = Content.fromObject(img) end)
    if not ok then
      l:Destroy()
      return nil
    end
    l.Parent = land
    return l
  end
  local BUDGET = 0.003
  local satReady = false
  -- 一块图一行一行画（每帧画到 BUDGET 为止），每行画完写进 EditableImage（没画到的行是透明的：底下的底图、色块照样看得到）
  local function paintInto(img, P, alive)
    local row = buffer.create(P.w * 4)
    local t0 = os.clock()
    for r = 0, P.h - 1 do
      if alive and not alive() then return false end
      Paint.paint(Map, P, r, r + 1, row)
      local ok = pcall(function() img:WritePixelsBuffer(Vector2.new(0, r), Vector2.new(P.w, 1), row) end)
      if not ok then return false end
      if os.clock() - t0 > BUDGET then
        task.wait()
        t0 = os.clock()
      end
    end
    return true
  end
  task.spawn(function()
    task.wait(1)   -- 开局别的先跑
    local NB = 512
    local img = newImage(NB)
    local lab = img and satLabel(img, 0, 0, 1, 1)
    if not lab then
      imgOK = false
      return
    end
    if paintInto(img, { x0 = X0, z0 = Z0, step = SPAN / NB, w = NB, h = NB, detail = false, exag = 2.6 }) then
      satReady = true
      bands.Visible = false
    end
  end)
  -- 细节块
  local touch = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local TPX = touch and 80 or 128
  local TILE = 800
  local tiles, nTiles = {}, 0   -- [键] = { img, lab, used, sea }
  local queue = {}              -- [键] = { tx, tz }
  local focusX, focusZ = nil, nil
  local function key(tx, tz) return tx * 100000 + tz end
  function G.mapFocus(x, z, radius)
    if not satReady then return end
    focusX, focusZ = x, z
    local R = math.min((radius or 600) * 1.5, TILE * 2.5)
    local now = os.clock()
    for tz = math.floor((z - R - Z0) / TILE), math.floor((z + R - Z0) / TILE) do
      for tx = math.floor((x - R - X0) / TILE), math.floor((x + R - X0) / TILE) do
        local k = key(tx, tz)
        local t = tiles[k]
        if t then t.used = now elseif not queue[k] then queue[k] = { tx = tx, tz = tz } end
      end
    end
  end
  G.mapSatState = function() return imgOK, satReady, nTiles end   -- 测试用
  task.spawn(function()
    while true do
      local pick, pk, best = nil, nil, math.huge
      if focusX then
        for k, q in pairs(queue) do
          local cx, cz = X0 + (q.tx + 0.5) * TILE, Z0 + (q.tz + 0.5) * TILE
          local d = (cx - focusX) ^ 2 + (cz - focusZ) ^ 2
          if d > (TILE * 3.5) ^ 2 then queue[k] = nil   -- 走远了：不画了
          elseif d < best then pick, pk, best = q, k, d end
        end
      end
      if not pick then
        task.wait(0.25)
      else
        queue[pk] = nil
        local x0, z0 = X0 + pick.tx * TILE, Z0 + pick.tz * TILE
        if not Paint.hasLand(Map, x0, z0, TILE) then
          tiles[pk] = { sea = true, used = os.clock() }
        else
          -- 太多了：扔掉最久没用的那块
          if nTiles >= 36 then
            local old, ok2, ot = nil, nil, math.huge
            for k, t in pairs(tiles) do
              if not t.sea and t.used < ot then old, ok2, ot = t, k, t.used end
            end
            if old then
              old.lab:Destroy()
              pcall(function() old.img:Destroy() end)
              tiles[ok2] = nil
              nTiles -= 1
            end
          end
          local img = newImage(TPX)
          local u0, v0 = toUV(x0, z0)
          local lab = img and satLabel(img, u0, v0, TILE / SPAN, 2)
          if lab then
            local t = { img = img, lab = lab, used = os.clock() }
            tiles[pk] = t
            nTiles += 1
            paintInto(img, { x0 = x0, z0 = z0, step = TILE / TPX, w = TPX, h = TPX, detail = true, exag = 1.5 }, function() return tiles[pk] == t end)
          end
        end
        task.wait()
      end
    end
  end)

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
  -- 配色：「map」部署界面的大地图（灰绿），「mini」右上的小地图（正常的地图颜色：深蓝的海、暗沙色海滩、暗绿的地），「radar」墨绿的雷达（不再用）
  function G.mapTheme(t)
    if t == theme then return end
    theme = t
    local radar, mini = t == "radar", t == "mini"
    root.BackgroundColor3 = SEA[t] or SEA.map
    for f, b in pairs(landBand) do f.BackgroundColor3 = landCol(b) end
    for _, f in ipairs(roads) do f.BackgroundColor3 = radar and RGB(70, 150, 90) or (mini and RGB(122, 110, 90) or RGB(150, 140, 116)) end
    for _, f in ipairs(fleetMarks) do f.BackgroundColor3 = radar and RGB(50, 110, 70) or (mini and RGB(128, 132, 136) or RGB(120, 126, 132)) end
    for _, g in ipairs(root:GetChildren()) do
      if g.Name == "Grid" then
        g.BackgroundColor3 = radar and RGB(80, 255, 140) or Color3.new(1, 1, 1)
        g.BackgroundTransparency = radar and 0.9 or (mini and 0.9 or 0.93)
      end
    end
  end
  G.mapThemeNow = function() return theme end   -- 测试用
end

return MapUI
