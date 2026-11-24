-- Roblox全面大战场（客户端）——选地图（用户 11-22：「界面就不要写 switch side 了，直接写 play，然后进入界面点地图」）
--   主菜单「开始游戏」打开：Map.ids 有几张就并排几张大卡片（岛屿突击 · 沙漠风暴 · 沙海；原来按两张排，第三张整个排到了屏幕外）——
--   上面一块缩略图（按那张图自己的高度、材质现画：EditableImage；用不了就一行一条渐变拼出低分辨率的缩略图），
--   下面名字、模式、尺寸、一行说明；服务器正在打的那张标「这个服务器正在打」和人数。开着时主菜单的字先藏起来（原来从卡片后面透出来）。
--   投票（用户 11-23）：还没定图时点一张就是投一票（能改票，ACT.pickMap → init.server.lua 的 G.voteMap），每张卡显示票数，底下倒计时；
--   第一票投出后 Config.MapVote.time 秒（在场的人都投了就提前）按票数最多的开 → 地图生成好（S.mapReady）投过票的人自动快速加入、关掉菜单；
--   服务器已经在打另一张：那张卡写「这个服务器在打 X」，按钮变「加入 X」
--   右上角「对战 / 关卡」两个页签：关卡页是 PvE 关卡（Pve.lua，用户 11-23：「你搞一些关卡吧」），一关一张卡，打过上一关才解锁，点了服务器换成这一关
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local MapPick = {}

function MapPick.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local V2 = Vector2.new
  local function T(k, ...) return G.T(k, ...) end
  local Map = G.Map
  local WHITE, MUTE, FAINT = Color3.new(1, 1, 1), RGB(156, 162, 168), RGB(104, 110, 116)
  local ACCENT = { island = RGB(70, 160, 200), sands = RGB(222, 116, 70) }
  local touch = UIS.TouchEnabled and not UIS.KeyboardEnabled   -- 手机：整体缩到一半多，字放大一点

  local gui = Instance.new("ScreenGui")
  gui.Name = "MapPick"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 16   -- 盖在主菜单（14）上面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or RGB(0, 0, 0), tr or 0, 0
    if anchor then f.AnchorPoint = anchor end
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UDim2.new()
    if anchor then l.AnchorPoint = anchor end
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3 = s, ts or 14, color or WHITE
    l.Font = font or Enum.Font.GothamMedium
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Parent = parent
    return l
  end
  local function stroke(f, tr, col)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = col or WHITE, 1, tr or 0.85
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end

  local shade = frame(gui, UDim2.fromScale(1, 1), nil, RGB(4, 5, 6), 0.25)
  shade.Active = true
  local content = frame(gui, UDim2.fromOffset(1232, 692), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, V2(0.5, 0.5))
  local scale = Instance.new("UIScale")
  scale.Parent = content
  local function fit()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
    scale.Scale = math.min(vp.X / 1280, vp.Y / 720, 1.6)
  end
  fit()
  if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

  local cat = text(content, "", UDim2.fromOffset(400, 14), UDim2.fromOffset(0, 34), 11, MUTE)
  local head = text(content, "", UDim2.fromOffset(700, 40), UDim2.fromOffset(0, 50), 34, WHITE, Enum.Font.GothamBold)
  local sub = text(content, "", UDim2.fromOffset(900, 16), UDim2.fromOffset(0, 96), 12, MUTE)
  local back = Instance.new("TextButton")
  back.Size, back.Position, back.AnchorPoint = UDim2.fromOffset(120, 28), UDim2.new(1, 0, 0, 50), V2(1, 0)
  back.BackgroundTransparency, back.BorderSizePixel = 1, 0
  back.TextColor3, back.TextSize, back.Font = MUTE, 13, Enum.Font.GothamMedium
  back.TextXAlignment = Enum.TextXAlignment.Right
  back.Parent = content
  frame(content, UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, 124), WHITE, 0.88)

  ---------------------------------------------------------------- 卡片的尺寸：Map.ids 有几张排几张（原来写死两张 600 宽，第三张「沙海」排在 1264 格开外、整个出了屏幕）

  local N = #Map.ids
  local GAP = 24
  local CW, CH = math.floor((1232 - (N - 1) * GAP) / N), 520
  local PH = N >= 3 and 248 or 300   -- 缩略图多高（三张并排时窄一些，矮一点给字留地方）

  ---------------------------------------------------------------- 缩略图：按那张图自己的高度、材质画（海蓝、沙黄、草绿、岩灰、跑道）

  -- 材质的颜色：那张图自己有配色表（沙海的 Map.COLORS：石灰岩台地、板岩……）就照它的，没有的按这张表（原来石灰岩、板岩都落到草绿上）
  local MATC = {
    Sand = { 206, 182, 132 }, Sandstone = { 190, 140, 96 }, Salt = { 226, 222, 206 }, Limestone = { 198, 182, 150 },
    Rock = { 128, 122, 114 }, Basalt = { 128, 122, 114 }, Slate = { 104, 96, 88 }, Ground = { 150, 124, 88 }, Mud = { 150, 124, 88 },
    Asphalt = { 70, 72, 74 }, Concrete = { 120, 118, 112 }, CrackedLava = { 170, 120, 80 },
    Grass = { 96, 136, 72 }, LeafyGrass = { 84, 124, 64 },
  }
  -- 取 cols × rows 个点：横向整张图，竖向 v0～v1 那一段（缩略图按 Crop 摆，只看得到中间一段）；每算几行让一帧（别一下卡住）
  local function previewColors(id, cols, rows, v0, v1)
    local P = Map.profile(id)
    if not P or not P.height then return nil end
    local info = Map.info[id] or {}
    local half = (info.km or 8) * 1000 * 2.8 / 2
    local own = type(P.COLORS) == "table" and P.COLORS or nil
    local px = {}
    for j = 0, rows - 1 do
      local z = -half + (v0 + (j + 0.5) / rows * (v1 - v0)) * 2 * half
      for i = 0, cols - 1 do
        local x = -half + (i + 0.5) / cols * 2 * half
        local h = P.height(x, z)
        local c
        if h <= 0.3 and info.sea ~= false then
          local d = math.clamp(-h / 60, 0, 1)
          c = { 34 - 18 * d, 110 - 50 * d, 140 - 40 * d }
        else
          local m = P.material and P.material(x, z, h, 0)
          local name = m and m.Name or ""
          local oc = own and own[name]
          if oc then c = { oc.R * 255, oc.G * 255, oc.B * 255 } else c = MATC[name] or MATC.Grass end
          local k = 0.82 + math.clamp(h / 600, 0, 0.3)   -- 高的地方亮一点（看得出山）
          c = { c[1] * k, c[2] * k, c[3] * k }
        end
        px[#px + 1] = c
      end
      if j % 8 == 7 then task.wait() end
    end
    return px
  end
  local PREV = 112
  local function paintImage(label, id)
    local okI, img = pcall(function() return game:GetService("AssetService"):CreateEditableImage({ Size = V2(PREV, PREV) }) end)
    if not okI or not img then return false end   -- 没开 Mesh / Image API：画色带
    local px = previewColors(id, PREV, PREV, 0, 1)
    if not px then return false end
    return (pcall(function()
      local buf = buffer.create(PREV * PREV * 4)
      for i, c in ipairs(px) do
        local o = (i - 1) * 4
        buffer.writeu8(buf, o, math.clamp(math.floor(c[1]), 0, 255))
        buffer.writeu8(buf, o + 1, math.clamp(math.floor(c[2]), 0, 255))
        buffer.writeu8(buf, o + 2, math.clamp(math.floor(c[3]), 0, 255))
        buffer.writeu8(buf, o + 3, 255)
      end
      img:WritePixelsBuffer(Vector2.zero, V2(PREV, PREV), buf)
      label.ImageContent = Content.fromObject(img)
    end))
  end
  -- 色带：一行一条 Frame，横向用 UIGradient 的色点（最多 20 个）渐变过去——低分辨率，但看得出海岸、沙丘、台地
  local BCOLS, BROWS = 20, 44
  local function paintBands(label, id)
    local cut = math.clamp(PH / CW, 0, 1)   -- Crop：方图横向撑满，竖向只露中间这一段
    local px = previewColors(id, BCOLS, BROWS, (1 - cut) / 2, (1 + cut) / 2)
    if not px then return false end
    local holder = Instance.new("Frame")
    holder.Name = "Bands"
    holder.Size = UDim2.fromScale(1, 1)
    holder.BackgroundTransparency = 1
    holder.ZIndex = 1
    for r = 0, BROWS - 1 do
      local kp = {}
      for c = 0, BCOLS - 1 do
        local v = px[r * BCOLS + c + 1]
        kp[#kp + 1] = ColorSequenceKeypoint.new(c / (BCOLS - 1), RGB(math.clamp(math.floor(v[1]), 0, 255), math.clamp(math.floor(v[2]), 0, 255), math.clamp(math.floor(v[3]), 0, 255)))
      end
      local f = frame(holder, UDim2.new(1, 0, 1 / BROWS, 1), UDim2.fromScale(0, r / BROWS), WHITE, 0)
      f.ZIndex = 1
      local g = Instance.new("UIGradient")
      g.Color = ColorSequence.new(kp)
      g.Parent = f
    end
    holder.Parent = label
    return true
  end

  ---------------------------------------------------------------- 卡片

  local cards = {}
  local TS = touch and 3 or 0   -- 手机上小字各大一点
  for i, id in ipairs(Map.ids) do
    local b = Instance.new("TextButton")
    b.Name = "Map_" .. id
    b.Size = UDim2.fromOffset(CW, CH)
    b.Position = UDim2.fromOffset((i - 1) * (CW + GAP), 148)
    b.BackgroundColor3 = RGB(10, 12, 14)
    b.BackgroundTransparency = 0.2
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = ""
    b.ClipsDescendants = true
    b.Parent = content
    local st = stroke(b, 0.86)
    local K = { id = id, b = b, st = st }
    -- 缩略图（地图正上方俯视）+ 一层压暗的渐变（字压在上面看得清）
    local pv = Instance.new("ImageLabel")
    pv.Name = "Preview"
    pv.Size = UDim2.new(1, 0, 0, PH)
    pv.BackgroundColor3 = ACCENT[id] or RGB(60, 70, 80)
    pv.BackgroundTransparency = 0.55
    pv.BorderSizePixel = 0
    pv.ScaleType = Enum.ScaleType.Crop
    pv.ZIndex = 1
    pv.Parent = b
    K.pv = pv
    local fade = frame(pv, UDim2.new(1, 0, 0, 120), UDim2.new(0, 0, 1, -120), RGB(10, 12, 14), 0)
    fade.ZIndex = 2   -- 压在色带上面
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
    g.Parent = fade
    K.bar = frame(b, UDim2.new(1, 0, 0, 3), nil, ACCENT[id] or WHITE, 0)
    K.mode = text(b, "", UDim2.fromOffset(CW - 48, 16), UDim2.fromOffset(24, PH - 30), 11 + TS, ACCENT[id] or MUTE, Enum.Font.GothamBold)
    K.name = text(b, "", UDim2.fromOffset(CW - 46, 34), UDim2.fromOffset(22, PH + 12), 30, WHITE, Enum.Font.GothamBold)
    K.size = text(b, "", UDim2.fromOffset(CW - 48, 16), UDim2.fromOffset(24, PH + 52), 13 + TS, MUTE, Enum.Font.GothamMedium)
    -- 说明到「正在打」那一行之间都给它（三张并排时一行 26 个字左右，沙海的说明要三行）
    local nowY = CH - 24 - 40 - 12 - 16
    K.desc = text(b, "", UDim2.fromOffset(CW - 48, nowY - 8 - (PH + 78)), UDim2.fromOffset(24, PH + 78), 13 + TS, RGB(214, 218, 222), Enum.Font.GothamMedium)
    K.desc.TextYAlignment = Enum.TextYAlignment.Top
    K.now = text(b, "", UDim2.fromOffset(CW - 48, 16), UDim2.fromOffset(24, nowY), 11 + TS, MUTE, Enum.Font.GothamMedium)
    -- 按钮横跨整张卡的底边（原来 180 宽靠右，窄卡上和「正在打 · 几名玩家」那行挤在一起）
    K.go = Instance.new("TextLabel")
    K.go.Size, K.go.Position = UDim2.new(1, -48, 0, 40), UDim2.new(0, 24, 1, -64)
    K.go.BackgroundColor3, K.go.BorderSizePixel = WHITE, 0
    K.go.TextColor3, K.go.TextSize, K.go.Font = RGB(10, 10, 12), 15 + TS, Enum.Font.GothamBold
    K.go.TextTruncate = Enum.TextTruncate.AtEnd
    K.go.Parent = b
    -- 票数（投票中才有）：缩略图右上角一块深色小牌
    K.votes = text(b, "", UDim2.fromOffset(96, 26), UDim2.new(1, -14, 0, 16), 13 + TS, WHITE, Enum.Font.GothamBold, V2(1, 0), Enum.TextXAlignment.Center)
    K.votes.BackgroundColor3, K.votes.BackgroundTransparency = RGB(8, 10, 12), 0.25
    K.votes.Visible = false
    for _, l in ipairs({ K.bar, K.mode, K.name, K.size, K.desc, K.now, K.go, K.votes }) do l.ZIndex = 3 end   -- 字在缩略图上面
    b.MouseEnter:Connect(function() st.Transparency, b.BackgroundTransparency = 0.5, 0.1 end)
    b.MouseLeave:Connect(function() st.Transparency, b.BackgroundTransparency = 0.86, 0.2 end)
    cards[id] = K
  end
  ---------------------------------------------------------------- PvE 关卡页（Pve.lua，用户 11-23：「你搞一些关卡吧」）

  local tab = "pvp"
  local tabs = {}
  for i, k in ipairs({ "pvp", "pve" }) do
    local b = Instance.new("TextButton")
    b.Name = "Tab_" .. k
    b.Size, b.Position, b.AnchorPoint = UDim2.fromOffset(150, 30), UDim2.new(1, -150 - (2 - i) * 160 - 140, 0, 50), V2(0, 0)
    b.BackgroundColor3, b.BorderSizePixel = RGB(16, 18, 20), 0
    b.TextSize, b.Font = 13, Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Parent = content
    tabs[k] = { b = b, st = stroke(b, 0.8) }
  end
  local pveGrid = frame(content, UDim2.fromOffset(1232, 520), UDim2.fromOffset(0, 148), RGB(0, 0, 0), 1)
  pveGrid.Name = "PveGrid"
  pveGrid.Visible = false
  local PC = G.Config.Pve or { levels = {} }
  local lcards = {}
  local LW, LH = 296, 250
  for n, L in ipairs(PC.levels) do
    local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
    local b = Instance.new("TextButton")
    b.Name = "Pve_" .. n
    b.Size = UDim2.fromOffset(LW, LH)
    b.Position = UDim2.fromOffset(col * (LW + 16), row * (LH + 16))
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = RGB(10, 12, 14), 0.2, 0
    b.AutoButtonColor = false
    b.Text = ""
    b.Parent = pveGrid
    local st = stroke(b, 0.86)
    frame(b, UDim2.new(1, 0, 0, 3), nil, ACCENT[L.map] or WHITE, 0)
    local K = { b = b, st = st, L = L, n = n }
    K.num = text(b, "", UDim2.fromOffset(LW - 32, 14), UDim2.fromOffset(16, 16), 11, ACCENT[L.map] or MUTE, Enum.Font.GothamBold)
    K.name = text(b, "", UDim2.fromOffset(LW - 32, 30), UDim2.fromOffset(16, 34), 24, WHITE, Enum.Font.GothamBold)
    K.map = text(b, "", UDim2.fromOffset(LW - 32, 16), UDim2.fromOffset(16, 74), 12, MUTE)
    K.goal = text(b, "", UDim2.fromOffset(LW - 32, 16), UDim2.fromOffset(16, 100), 13, RGB(214, 218, 222))
    K.forces = text(b, "", UDim2.fromOffset(LW - 32, 16), UDim2.fromOffset(16, 122), 13, RGB(214, 218, 222))
    K.reward = text(b, "", UDim2.fromOffset(LW - 32, 32), UDim2.fromOffset(16, 146), 13, RGB(255, 206, 96), Enum.Font.GothamBold)
    K.reward.TextYAlignment = Enum.TextYAlignment.Top
    K.state = Instance.new("TextLabel")
    K.state.Size, K.state.Position, K.state.AnchorPoint = UDim2.fromOffset(150, 34), UDim2.new(1, -16, 1, -16), V2(1, 1)
    K.state.BackgroundColor3, K.state.BorderSizePixel = WHITE, 0
    K.state.TextSize, K.state.Font = 14, Enum.Font.GothamBold
    K.state.Parent = b
    b.MouseEnter:Connect(function() st.Transparency, b.BackgroundTransparency = 0.5, 0.1 end)
    b.MouseLeave:Connect(function() st.Transparency, b.BackgroundTransparency = 0.86, 0.2 end)
    lcards[n] = K
  end
  local function setTab(k)
    tab = k
    for id, K in pairs(cards) do K.b.Visible = (k == "pvp") end
    pveGrid.Visible = (k == "pve")
    if G.S then G.refreshMapPick(G.S) end
  end
  tabs.pvp.b.Activated:Connect(function() setTab("pvp") end)
  tabs.pve.b.Activated:Connect(function() setTab("pve") end)
  G.mapPickTab = function(k) if k then setTab(k) end return tab end   -- 测试用

  -- 缩略图慢慢画（算一次就留着）：先试 EditableImage，用不了画色带
  local painted = {}
  local function paintAll()
    for id, K in pairs(cards) do
      if not painted[id] then
        painted[id] = true
        task.spawn(function()
          local ok = paintImage(K.pv, id) or paintBands(K.pv, id)
          if not ok then painted[id] = "fail" end
        end)
      end
    end
  end

  ---------------------------------------------------------------- 投票（用户 11-23：「三张地图改成投票制，进去投票选地图」）：
  --   还没定图：点一张就是投一票（再点别的是改票），每张卡上是票数，底下是倒计时；投票结束定了哪张，生成好了投过票的人自动快速加入。
  --   已经定了：卡片按钮是「加入」那张（同原来）

  local want = nil      -- 自己投的 / 要加入的哪张（投过票就有）
  local voteLeft, voteAt = nil, 0   -- 服务器说投票还剩几秒（收到时的本地时间）：本地往下数
  local status = text(content, "", UDim2.fromOffset(1232, 18), UDim2.fromOffset(0, 680), 13 + TS, WHITE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Center)
  -- 主菜单的字藏起来 / 放回来（Menu.lua 的 refreshMenu 看 G.mapPickShown）
  local function menuSync() if G.refreshMenu and G.S then G.refreshMenu(G.S) end end
  local wantPve = nil   -- 自己点的第几关（PvE）
  local function close()
    gui.Enabled = false
    want = nil
    wantPve = nil
    menuSync()
  end
  local function choose(id)
    local S = G.S
    if S and S.map and S.map ~= id then id = S.map end   -- 服务器已经在打另一张：按钮是「加入那张」
    want = id
    G.R.Act:FireServer("pickMap", id)
    if S and S.map then status.Text = T("map.loading", 0) end
    if G.refreshMapPick and S then G.refreshMapPick(S) end   -- 先高亮自己投的（服务器的票数随后到）
  end
  for id, K in pairs(cards) do K.b.Activated:Connect(function() choose(id) end) end
  local function pveCleared() return me:GetAttribute("PveCleared") or 0 end
  local function choosePve(n)
    local L = PC.levels[n]
    if not L then return end
    if n > pveCleared() + 1 then
      if G.toast then G.toast(T("pve.lockedMsg", n - 1), "bad") end
      return
    end
    want, wantPve = L.map, n
    G.R.Act:FireServer("pickPve", n)
    status.Text = T("map.loading", 0)
  end
  for n, K in pairs(lcards) do K.b.Activated:Connect(function() choosePve(n) end) end
  back.Activated:Connect(close)
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not gui.Enabled then return end
    if io.KeyCode == Enum.KeyCode.Escape then close()
    elseif io.KeyCode == Enum.KeyCode.Return then choose((G.S and G.S.map) or want or Map.ids[1]) end
  end)

  -- 底下那行：投票中写倒计时、几个人投了；定了写打哪张、生成进度
  local function statusLine(S)
    local V = S.vote
    if not S.map and V then
      local MV = G.Config and G.Config.MapVote or {}
      if voteLeft then
        local left = math.max(0, math.ceil(voteLeft - (os.clock() - voteAt)))
        return T("map.voteLeft", left, V.voters or 0, math.max(V.players or 0, V.voters or 0))
      end
      return T("map.voteIdle", MV.time or 25)
    end
    if S.map and want then
      local pre = (want ~= S.map) and (T("map.decided", T("map." .. S.map .. ".name")) .. "   ·   ") or ""
      return pre .. T("map.loading", math.floor((S.mapReady and 1 or (S.progress or 0)) * 100))
    end
    return ""
  end
  -- 倒计时每帧往下数（服务器半秒左右才推一次）
  local tick = 0
  local function stepStatus(dt)
    if not gui.Enabled or not G.S then return end
    tick += dt or 0
    if tick < 0.2 then return end
    tick = 0
    status.Text = statusLine(G.S)
  end
  if G.frameConn then G.frameConn("MapPick", stepStatus) else game:GetService("RunService").RenderStepped:Connect(stepStatus) end

  function G.showMapPick()
    gui.Enabled = true
    paintAll()
    menuSync()
    if G.S and G.S.pve and tab ~= "pve" then setTab("pve") end   -- 这个服务器在打关卡（比如传送过来的）：直接开关卡页
    if G.S then G.refreshMapPick(G.S) end
  end
  G.mapPickShown = function() return gui.Enabled end
  G.mapPickWant = function() return want end   -- 测试用

  function G.refreshMapPick(S)
    if not S then return end
    -- 投票的倒计时：每次收到都对一下（界面关着也记着，打开就是对的）
    local V = (not S.map) and S.vote or nil
    if V and V.left then voteLeft, voteAt = V.left, os.clock() else voteLeft = nil end
    if not S.map and S.myVote then want = S.myVote end   -- 自己投的哪张以服务器为准（换了设备、重进都对得上）
    if not gui.Enabled then return end
    cat.Text = T("map.cat")
    head.Text = T("map.title")
    sub.Text = T("map.sub")
    back.Text = T("map.back")
    local n = (S.rAtk or 0) + (S.rDef or 0)
    tabs.pvp.b.Text, tabs.pve.b.Text = T("pve.tabPvp"), T("pve.tabPve")
    for k, tb in pairs(tabs) do
      local on = tab == k
      tb.b.TextColor3 = on and RGB(10, 10, 12) or MUTE
      tb.b.BackgroundColor3 = on and WHITE or RGB(16, 18, 20)
      tb.st.Transparency = on and 0.2 or 0.8
    end
    if tab == "pve" then
      head.Text = T("pve.title")
      sub.Text = T("pve.sub")
      local cl = pveCleared()
      for i, K in pairs(lcards) do
        local L = K.L
        K.num.Text = string.upper(T("pve.level", i))
        K.name.Text = T("pve.n" .. i)
        K.map.Text = T("map." .. L.map .. ".name") .. "  ·  " .. T("map." .. L.map .. ".mode")
        K.goal.Text = L.caps and T("pve.goalCaps", L.caps) or T("pve.goalTickets", L.tickets or 0)
        K.forces.Text = T("pve.forces", L.enemies, L.allies)
        K.reward.Text = (i > cl) and T("pve.rewardFirst", math.floor(L.reward * (PC.firstBonus or 1))) or T("pve.rewardReplay", math.floor(L.reward * (PC.replay or 1)))
        local locked = i > cl + 1
        local done = i <= cl
        local cur = S.pve == i and S.map == L.map
        K.state.Text = locked and T("pve.locked", i - 1) or (cur and T("map.join") or (done and (T("pve.cleared") .. "  ·  " .. T("pve.start")) or T("pve.start")))
        K.state.BackgroundColor3 = locked and RGB(40, 42, 46) or (done and RGB(120, 214, 130) or WHITE)
        K.state.TextColor3 = locked and MUTE or RGB(10, 10, 12)
        K.b.BackgroundTransparency = locked and 0.55 or 0.2
        K.st.Color = (wantPve == i) and (ACCENT[L.map] or WHITE) or WHITE
        K.st.Transparency = (wantPve == i) and 0.2 or 0.86
      end
    end
    local voting = S.map == nil and not S.pve
    for id, K in pairs(cards) do
      local info = Map.info[id] or {}
      local acc = ACCENT[id] or WHITE
      K.mode.Text = string.upper(T("map." .. id .. ".mode"))
      K.name.Text = T("map." .. id .. ".name")
      K.size.Text = T("map.size", string.format("%.0f", info.km or 0))
      K.desc.Text = T("map." .. id .. ".desc")
      local cur = S.map == id
      local other = S.map ~= nil and not cur
      local mine = voting and want == id
      K.now.Text = cur and (T("map.now") .. "   ·   " .. T("map.players", n)) or (other and T("map.other", T("map." .. S.map .. ".name")) or "")
      if cur and S.pve then K.now.Text = T("pve.nowPve", S.pve, T("pve.n" .. S.pve)) .. "   ·   " .. T("map.players", n) end   -- 在打关卡：一个人点就退出关卡改打对战（Round.lua 的 ACT.pickMap）
      K.now.TextColor3 = cur and acc or MUTE
      if voting then
        K.go.Text = mine and T("map.voted") or T("map.vote")
        K.go.BackgroundColor3, K.go.TextColor3 = mine and acc or WHITE, RGB(10, 10, 12)
        local nv = (V and V.n and V.n[id]) or 0
        K.votes.Visible = true
        K.votes.Text = T("map.votes", nv)
        K.votes.TextColor3 = (nv > 0) and acc or MUTE
      else
        K.go.Text = other and (T("map.join") .. "  " .. T("map." .. S.map .. ".name")) or T("map.join")
        K.go.BackgroundColor3, K.go.TextColor3 = WHITE, RGB(10, 10, 12)
        K.votes.Visible = false
      end
      K.b.BackgroundTransparency = other and 0.45 or 0.2
      local hi = mine or (cur and want ~= nil)
      K.st.Color = hi and acc or WHITE
      K.st.Transparency = hi and 0.2 or 0.86
    end
    status.Text = statusLine(S)
    if wantPve and S.pve ~= wantPve then   -- 点了关卡：等服务器换成这一关
      status.Text = T("map.loading", math.floor((S.progress or 0) * 100))
    elseif want and S.map and S.mapReady then
      -- 投过票 / 点过加入 / 点过关卡的：地图定了、生成好了就快速加入（主菜单关掉、自动分队、推荐出生点）——不管最后定的是不是自己投的那张
      close()
      if G.quickJoin then G.quickJoin() end
    end
  end
end

return MapPick
