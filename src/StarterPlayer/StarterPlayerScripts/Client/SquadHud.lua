-- 全面大战场（客户端）——小队（服务器 Squads.lua；用户 11-23「这个游戏按你想的来弄」）
--   左边一块小队面板：「A 小队」，下面每个队友一行——名字、血条、状态（倒地红字、阵亡灰字、在载具里）、离我多远；只有自己一个人时写「等队友加入」
--   小队队友头顶：绿色的倒三角 + 名字（隔着墙也看得见，600 格以内），倒地的由 Downed.lua 画救援标记、这里不画
--   小队号在玩家属性 Squad 上（服务器分好的），队伍在属性 Side 上
local Players = game:GetService("Players")

local SquadHud = {}

function SquadHud.init(G)
  local T = G.T or function(k) return k end
  local player = Players.LocalPlayer
  local RGB, V = Color3.fromRGB, Vector3.new
  local GREEN = RGB(116, 232, 120)
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

  local gui = Instance.new("ScreenGui")
  gui.Name = "SquadHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Parent = player:WaitForChild("PlayerGui")
  local panel = Instance.new("Frame")
  panel.Name = "Panel"
  panel.Position = UDim2.new(0, 16, 0.36, 0)
  panel.Size = UDim2.fromOffset(190, 20)
  panel.BackgroundTransparency = 1
  panel.Visible = false
  panel.Parent = gui
  local title = Instance.new("TextLabel")
  title.BackgroundTransparency = 1
  title.Size = UDim2.new(1, 0, 0, 18)
  title.Font = Enum.Font.GothamBold
  title.TextSize = 13
  title.TextColor3 = GREEN
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.TextStrokeTransparency = 0.5
  title.Parent = panel
  local rows = {}
  local function row(i)
    if rows[i] then return rows[i] end
    local f = Instance.new("Frame")
    f.BackgroundColor3 = RGB(6, 8, 10)
    f.BackgroundTransparency = 0.45
    f.BorderSizePixel = 0
    f.Size = UDim2.new(1, 0, 0, 30)
    f.Position = UDim2.fromOffset(0, 20 + (i - 1) * 33)
    f.Parent = panel
    local edge = Instance.new("Frame")
    edge.Size = UDim2.new(0, 2, 1, 0)
    edge.BackgroundColor3 = GREEN
    edge.BorderSizePixel = 0
    edge.Parent = f
    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Position = UDim2.fromOffset(8, 2)
    name.Size = UDim2.new(1, -70, 0, 16)
    name.Font = Enum.Font.GothamMedium
    name.TextSize = 13
    name.TextColor3 = RGB(236, 240, 236)
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Parent = f
    local info = Instance.new("TextLabel")
    info.BackgroundTransparency = 1
    info.AnchorPoint = Vector2.new(1, 0)
    info.Position = UDim2.new(1, -6, 0, 2)
    info.Size = UDim2.fromOffset(64, 16)
    info.Font = Enum.Font.GothamBold
    info.TextSize = 11
    info.TextColor3 = RGB(190, 196, 190)
    info.TextXAlignment = Enum.TextXAlignment.Right
    info.Parent = f
    local bar = Instance.new("Frame")
    bar.Position = UDim2.fromOffset(8, 21)
    bar.Size = UDim2.new(1, -16, 0, 3)
    bar.BackgroundColor3 = RGB(40, 44, 40)
    bar.BorderSizePixel = 0
    bar.Parent = f
    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = GREEN
    fill.BorderSizePixel = 0
    fill.Parent = bar
    rows[i] = { f = f, edge = edge, name = name, info = info, fill = fill }
    return rows[i]
  end

  -- 头顶的标记
  local marks = {}   -- [Player] = { bb, ch }
  local function dropMark(pl)
    local m = marks[pl]
    if m then m.bb:Destroy() marks[pl] = nil end
  end
  local function mark(pl, ch)
    local m = marks[pl]
    if m and m.ch == ch then return m end
    dropMark(pl)
    local head = ch:FindFirstChild("Head")
    if not head then return nil end
    local bb = Instance.new("BillboardGui")
    bb.Name = "SquadMark"
    bb.Size = UDim2.fromOffset(110, 34)
    bb.StudsOffset = V(0, 2.2, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 600
    bb.Adornee = head
    local nm = Instance.new("TextLabel")
    nm.BackgroundTransparency = 1
    nm.Size = UDim2.new(1, 0, 0, 14)
    nm.Font = Enum.Font.GothamBold
    nm.TextSize = 12
    nm.TextColor3 = GREEN
    nm.TextStrokeTransparency = 0.45
    nm.Text = pl.DisplayName
    nm.Parent = bb
    local tri = Instance.new("TextLabel")
    tri.BackgroundTransparency = 1
    tri.Position = UDim2.fromOffset(0, 13)
    tri.Size = UDim2.new(1, 0, 0, 16)
    tri.Font = Enum.Font.GothamBold
    tri.TextSize = 14
    tri.TextColor3 = GREEN
    tri.TextStrokeTransparency = 0.45
    tri.Text = "▼"
    tri.Parent = bb
    bb.Parent = gui
    m = { bb = bb, ch = ch, nm = nm, tri = tri }
    marks[pl] = m
    return m
  end
  Players.PlayerRemoving:Connect(dropMark)

  -- 小队队友（同一边、同一个小队号；按名字排好）
  local function mates()
    local sq, side = player:GetAttribute("Squad"), player:GetAttribute("Side")
    local out = {}
    if not sq then return out, nil end
    for _, pl in ipairs(Players:GetPlayers()) do
      if pl ~= player and pl:GetAttribute("Squad") == sq and pl:GetAttribute("Side") == side then table.insert(out, pl) end
    end
    table.sort(out, function(a, b) return a.DisplayName < b.DisplayName end)
    return out, sq
  end
  G.squadMatesOf = mates   -- 测试用

  local acc = 0
  G.frameConn("SquadHud", function(dt)
    acc += dt
    if acc < 0.2 then return end
    acc = 0
    local list, sq = mates()
    local menu = (G.menuShown and G.menuShown()) or false
    local myCh = player.Character
    local myHrp = myCh and myCh:FindFirstChild("HumanoidRootPart")
    -- 开飞机、战雷式界面（WtFlight.lua）开着时左上是参数表：小队名单先收起来
    local flying = G.wtFlightOn and G.fly ~= nil and G.fly.pilot == true
    panel.Visible = sq ~= nil and not menu and myHrp ~= nil and not flying
    title.Text = sq and T("squad.title", sq) or ""
    local seen = {}
    for i, pl in ipairs(list) do
      local r = row(i)
      r.f.Visible = true
      r.name.Text = pl.DisplayName
      local ch = pl.Character
      local hum = ch and ch:FindFirstChildOfClass("Humanoid")
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      local alive = hum ~= nil and hum.Health > 0
      local down = alive and ch:GetAttribute("Downed") == true
      local hp = (alive and not down) and clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1) or 0
      r.fill.Size = UDim2.fromScale(hp, 1)
      r.fill.BackgroundColor3 = (hp < 0.35) and RGB(236, 170, 60) or GREEN
      local okS, seated = pcall(function() return hum ~= nil and hum.Sit end)   -- Lune 测试台的 Humanoid 读不到 Sit
      seated = okS and seated == true
      if not alive then
        r.info.Text, r.info.TextColor3 = T("squad.dead"), RGB(140, 140, 140)
        r.name.TextColor3, r.edge.BackgroundColor3 = RGB(140, 144, 140), RGB(90, 90, 90)
      elseif down then
        r.info.Text, r.info.TextColor3 = T("squad.down"), RGB(236, 70, 60)
        r.name.TextColor3, r.edge.BackgroundColor3 = RGB(255, 210, 205), RGB(236, 70, 60)
      else
        local d = (hrp and myHrp) and math.floor((hrp.Position - myHrp.Position).Magnitude / 2.8 + 0.5) or nil
        r.info.Text = seated and T("squad.veh") or (d and (d .. " m") or "")
        r.info.TextColor3 = RGB(190, 196, 190)
        r.name.TextColor3, r.edge.BackgroundColor3 = RGB(236, 240, 236), GREEN
      end
      -- 头顶标记：活着、没倒地、不是自己
      if alive and not down and ch then
        local m = mark(pl, ch)
        if m then seen[pl] = true end
      end
    end
    for i = #list + 1, #rows do rows[i].f.Visible = false end
    if #list == 0 and sq then
      local r = row(1)
      r.f.Visible = true
      r.name.Text = T("squad.alone")
      r.name.TextColor3 = RGB(170, 176, 170)
      r.info.Text = ""
      r.fill.Size = UDim2.fromScale(0, 1)
    end
    for pl in pairs(marks) do if not seen[pl] then dropMark(pl) end end
  end)
end

return SquadHud
