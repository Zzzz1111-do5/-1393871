-- Roblox全面大战场（客户端）——选地图（用户 11-22：「界面就不要写 switch side 了，直接写 play，然后进入界面点地图」）
--   主菜单「开始游戏」打开：两张大卡片并排（岛屿突击 · 沙漠风暴）——上面一块缩略图（按那张图自己的高度、材质现画：EditableImage；用不了画几道色带），
--   下面名字、模式、尺寸、一行说明；服务器正在打的那张标「这个服务器正在打」和人数。
--   点一张：告诉服务器（ACT.pickMap；还没定地图就按这张开）→ 地图生成好（S.mapReady）就快速加入（自动分队、默认装备、推荐出生点）、关掉菜单；
--   服务器已经在打另一张：那张卡写「这个服务器在打 X」，按钮变「加入 X」
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
  local ACCENT = { island = RGB(70, 160, 200), desert = RGB(214, 160, 84) }

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

  ---------------------------------------------------------------- 缩略图：按那张图自己的高度、材质画（海蓝、沙黄、草绿、岩灰、跑道）

  local PREV = 112
  local function previewColors(id)
    local P = Map.profile(id)
    if not P or not P.height then return nil end
    local info = Map.info[id] or {}
    local half = (info.km or 8) * 1000 * 2.8 / 2
    local px = {}
    for j = 0, PREV - 1 do
      for i = 0, PREV - 1 do
        local x = -half + (i + 0.5) / PREV * 2 * half
        local z = -half + (j + 0.5) / PREV * 2 * half
        local h = P.height(x, z)
        local c
        if h <= 0.3 and info.sea ~= false then
          local d = math.clamp(-h / 60, 0, 1)
          c = { 34 - 18 * d, 110 - 50 * d, 140 - 40 * d }
        else
          local m = P.material and P.material(x, z, h, 0)
          local name = m and m.Name or ""
          if name == "Sand" then c = { 206, 182, 132 }
          elseif name == "Sandstone" then c = { 190, 140, 96 }
          elseif name == "Salt" then c = { 226, 222, 206 }
          elseif name == "Rock" or name == "Basalt" then c = { 128, 122, 114 }
          elseif name == "Ground" or name == "Mud" then c = { 150, 124, 88 }
          elseif name == "Asphalt" or name == "Concrete" then c = { 70, 72, 74 }
          elseif name == "Cracked Lava" or name == "CrackedLava" then c = { 170, 120, 80 }
          else c = { 96, 136, 72 } end
          local k = 0.82 + math.clamp(h / 600, 0, 0.3)   -- 高的地方亮一点（看得出山）
          c = { c[1] * k, c[2] * k, c[3] * k }
        end
        px[#px + 1] = c
      end
    end
    return px
  end
  local function paint(label, id)
    local px = previewColors(id)
    if not px then return false end
    local ok = pcall(function()
      local AS = game:GetService("AssetService")
      local img = AS:CreateEditableImage({ Size = V2(PREV, PREV) })
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
    end)
    return ok
  end

  ---------------------------------------------------------------- 两张卡

  local cards = {}
  local CW, CH = 600, 520
  for i, id in ipairs(Map.ids) do
    local b = Instance.new("TextButton")
    b.Name = "Map_" .. id
    b.Size = UDim2.fromOffset(CW, CH)
    b.Position = UDim2.fromOffset((i - 1) * (CW + 32), 148)
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
    pv.Size = UDim2.new(1, 0, 0, 300)
    pv.BackgroundColor3 = ACCENT[id] or RGB(60, 70, 80)
    pv.BackgroundTransparency = 0.55
    pv.BorderSizePixel = 0
    pv.ScaleType = Enum.ScaleType.Crop
    pv.Parent = b
    K.pv = pv
    local fade = frame(pv, UDim2.new(1, 0, 0, 120), UDim2.new(0, 0, 1, -120), RGB(10, 12, 14), 0)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
    g.Parent = fade
    K.bar = frame(b, UDim2.new(1, 0, 0, 3), nil, ACCENT[id] or WHITE, 0)
    K.mode = text(b, "", UDim2.fromOffset(300, 14), UDim2.fromOffset(24, 272), 11, ACCENT[id] or MUTE, Enum.Font.GothamBold)
    K.name = text(b, "", UDim2.fromOffset(CW - 48, 34), UDim2.fromOffset(22, 316), 30, WHITE, Enum.Font.GothamBold)
    K.size = text(b, "", UDim2.fromOffset(300, 16), UDim2.fromOffset(24, 356), 13, MUTE, Enum.Font.GothamMedium)
    K.desc = text(b, "", UDim2.fromOffset(CW - 48, 64), UDim2.fromOffset(24, 382), 13, RGB(214, 218, 222), Enum.Font.GothamMedium)
    K.desc.TextYAlignment = Enum.TextYAlignment.Top
    K.now = text(b, "", UDim2.fromOffset(CW - 48, 14), UDim2.fromOffset(24, 452), 11, MUTE, Enum.Font.GothamMedium)
    K.go = Instance.new("TextLabel")
    K.go.Size, K.go.Position, K.go.AnchorPoint = UDim2.fromOffset(180, 40), UDim2.new(1, -24, 1, -24), V2(1, 1)
    K.go.BackgroundColor3, K.go.BorderSizePixel = WHITE, 0
    K.go.TextColor3, K.go.TextSize, K.go.Font = RGB(10, 10, 12), 15, Enum.Font.GothamBold
    K.go.Parent = b
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

  -- 缩略图慢慢画（一张一百多乘一百多个点，算一次就留着）
  local painted = {}
  local function paintAll()
    for id, K in pairs(cards) do
      if not painted[id] then
        painted[id] = true
        task.spawn(function() if not paint(K.pv, id) then painted[id] = "fail" end end)
      end
    end
  end

  ---------------------------------------------------------------- 点一张：告诉服务器，生成好了就快速加入

  local want = nil      -- 自己点的哪张
  local status = text(content, "", UDim2.fromOffset(1232, 18), UDim2.fromOffset(0, 680), 13, WHITE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Center)
  local wantPve = nil   -- 自己点的第几关（PvE）
  local function close()
    gui.Enabled = false
    want = nil
    wantPve = nil
  end
  local function choose(id)
    local S = G.S
    if S and S.map and S.map ~= id then id = S.map end   -- 服务器已经在打另一张：按钮是「加入那张」
    want = id
    G.R.Act:FireServer("pickMap", id)
    status.Text = T("map.loading", 0)
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
    elseif io.KeyCode == Enum.KeyCode.Return then choose((G.S and G.S.map) or Map.ids[1]) end
  end)

  function G.showMapPick()
    gui.Enabled = true
    paintAll()
    if G.S then G.refreshMapPick(G.S) end
  end
  G.mapPickShown = function() return gui.Enabled end
  G.mapPickWant = function() return want end   -- 测试用

  function G.refreshMapPick(S)
    if not S or not gui.Enabled then return end
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
        K.reward.Text = T("pve.reward", L.reward)
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
    for id, K in pairs(cards) do
      local info = Map.info[id] or {}
      K.mode.Text = string.upper(T("map." .. id .. ".mode"))
      K.name.Text = T("map." .. id .. ".name")
      K.size.Text = T("map.size", string.format("%.0f", info.km or 0))
      K.desc.Text = T("map." .. id .. ".desc")
      local cur = S.map == id
      local other = S.map ~= nil and not cur
      K.now.Text = cur and (T("map.now") .. "   ·   " .. T("map.players", n)) or (other and T("map.other", T("map." .. S.map .. ".name")) or "")
      if cur and S.pve then K.now.Text = T("pve.nowPve", S.pve, T("pve.n" .. S.pve)) .. "   ·   " .. T("map.players", n) end   -- 在打关卡：一个人点就退出关卡改打对战（Round.lua 的 ACT.pickMap）
      K.now.TextColor3 = cur and (ACCENT[id] or WHITE) or MUTE
      K.go.Text = other and (T("map.join") .. "  " .. T("map." .. S.map .. ".name")) or (cur and T("map.join") or T("map.pick"))
      K.b.BackgroundTransparency = other and 0.45 or 0.2
      K.st.Color = (want == id) and (ACCENT[id] or WHITE) or WHITE
      K.st.Transparency = (want == id) and 0.2 or 0.86
    end
    if want then
      if wantPve and S.pve ~= wantPve then   -- 点了关卡：等服务器换成这一关
        status.Text = T("map.loading", math.floor((S.progress or 0) * 100))
      elseif S.map == want and S.mapReady then
        -- 地图好了：快速加入（主菜单关掉、自动分队、推荐出生点）
        close()
        if G.quickJoin then G.quickJoin() end
      elseif S.map == want then
        status.Text = T("map.loading", math.floor((S.progress or 0) * 100))
      end
    else
      status.Text = ""
    end
  end
end

return MapPick
