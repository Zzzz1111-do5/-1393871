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
  local function close()
    gui.Enabled = false
    want = nil
  end
  local function choose(id)
    local S = G.S
    if S and S.map and S.map ~= id then id = S.map end   -- 服务器已经在打另一张：按钮是「加入那张」
    want = id
    G.R.Act:FireServer("pickMap", id)
    status.Text = T("map.loading", 0)
  end
  for id, K in pairs(cards) do K.b.Activated:Connect(function() choose(id) end) end
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
    for id, K in pairs(cards) do
      local info = Map.info[id] or {}
      K.mode.Text = string.upper(T("map." .. id .. ".mode"))
      K.name.Text = T("map." .. id .. ".name")
      K.size.Text = T("map.size", string.format("%.0f", info.km or 0))
      K.desc.Text = T("map." .. id .. ".desc")
      local cur = S.map == id
      local other = S.map ~= nil and not cur
      K.now.Text = cur and (T("map.now") .. "   ·   " .. T("map.players", n)) or (other and T("map.other", T("map." .. S.map .. ".name")) or "")
      K.now.TextColor3 = cur and (ACCENT[id] or WHITE) or MUTE
      K.go.Text = other and (T("map.join") .. "  " .. T("map." .. S.map .. ".name")) or (cur and T("map.join") or T("map.pick"))
      K.b.BackgroundTransparency = other and 0.45 or 0.2
      K.st.Color = (want == id) and (ACCENT[id] or WHITE) or WHITE
      K.st.Transparency = (want == id) and 0.2 or 0.86
    end
    if want then
      if S.map == want and S.mapReady then
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
