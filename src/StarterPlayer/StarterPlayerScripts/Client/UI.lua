-- Roblox全面大战场——界面：部署（兵种卡片 + 地图上点出生点 + 出击）、战斗中的顶栏（时间、5 个据点）、血条、小地图、
--   击杀信息、屏幕中间的大字、底部提示、战况表（Tab）、结算画面、出错红条；所有文字按 G.lang 中英切换
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local UI = {}

function UI.init(G)
  local Config, Lang = G.Config, G.Lang
  local Map = require(RS:WaitForChild("Map"))
  local player = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local function T(key, ...) return Lang.t(G.lang, key, ...) end
  G.T = T

  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)   -- 武器栏自己画（中英文）
  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)   -- 战况表自己画（Tab）

  local gui = Instance.new("ScreenGui")
  gui.Name = "Main"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Parent = player:WaitForChild("PlayerGui")
  G.gui = gui

  ---------------------------------------------------------------- 小工具

  local PANEL, LINE, TEXT, MUTE = RGB(16, 20, 24), RGB(255, 255, 255), RGB(236, 240, 236), RGB(160, 170, 166)
  local function frame(parent, size, pos, color, alpha, anchor)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = pos or UDim2.new()
    f.AnchorPoint = anchor or Vector2.new()
    f.BackgroundColor3 = color or PANEL
    f.BackgroundTransparency = alpha or 0.25
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
  end
  local function round(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = f
    return f
  end
  local function stroke(f, color, t, alpha)
    local s = Instance.new("UIStroke")
    s.Color = color or LINE
    s.Thickness = t or 1
    s.Transparency = alpha or 0.85
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.AnchorPoint = anchor or Vector2.new()
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = ts or 16
    l.TextColor3 = color or TEXT
    l.Font = font or Enum.Font.GothamMedium
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextWrapped = true
    l.Parent = parent
    return l
  end
  local function button(parent, text, size, pos, color, anchor)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.AnchorPoint = anchor or Vector2.new()
    b.BackgroundColor3 = color or RGB(40, 46, 52)
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel = 0
    b.Text = text or ""
    b.TextColor3 = TEXT
    b.TextSize = 16
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Parent = parent
    round(b, 8)
    return b
  end
  G.ui = { frame = frame, round = round, stroke = stroke, label = label, button = button }

  local function teamColor(t) return Config.Teams[t or "atk"].color end
  local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%d:%02d", s // 60, s % 60)
  end

  ---------------------------------------------------------------- 出错红条、开服进度

  local errBar = label(gui, "", UDim2.new(1, -40, 0, 0), UDim2.new(0.5, 0, 0, 6), 14, RGB(255, 220, 220), Enum.Font.GothamMedium, Vector2.new(0.5, 0))
  errBar.AutomaticSize = Enum.AutomaticSize.Y
  errBar.BackgroundColor3 = RGB(150, 30, 30)
  errBar.BackgroundTransparency = 0.15
  errBar.Visible = false
  errBar.ZIndex = 50
  local errs = {}
  function G.showError(msg)
    table.insert(errs, 1, tostring(msg))
    while #errs > 3 do table.remove(errs) end
    errBar.Text = table.concat(errs, "\n")
    errBar.Visible = true
  end

  local loading = frame(gui, UDim2.fromScale(1, 1), nil, RGB(10, 14, 18), 0)
  loading.ZIndex = 40
  local loadText = label(loading, "", UDim2.new(1, 0, 0, 40), UDim2.fromScale(0, 0.5), 22, TEXT, Enum.Font.GothamBold)
  loadText.ZIndex = 41

  ---------------------------------------------------------------- 部署界面

  local deploy = frame(gui, UDim2.fromScale(1, 1), nil, RGB(8, 12, 16), 0.12)
  deploy.Name = "Deploy"
  deploy.Visible = false
  deploy.ZIndex = 10
  local top = frame(deploy, UDim2.new(1, 0, 0, 64), nil, RGB(12, 16, 20), 0.2)
  local title = label(top, "", UDim2.new(0, 360, 1, 0), UDim2.fromOffset(18, 0), 22, TEXT, Enum.Font.GothamBlack, nil, Enum.TextXAlignment.Left)
  local teamTag = label(top, "", UDim2.new(0, 260, 0, 34), UDim2.new(0.5, 0, 0.5, 0), 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack, Vector2.new(0.5, 0.5))
  teamTag.BackgroundTransparency = 0.1
  round(teamTag, 6)
  local phaseText = label(top, "", UDim2.new(0, 300, 1, 0), UDim2.new(1, -150, 0, 0), 16, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Right)
  local langBtn = button(top, "", UDim2.fromOffset(110, 34), UDim2.new(1, -14, 0.5, 0), RGB(50, 58, 66), Vector2.new(1, 0.5))
  local goal = label(deploy, "", UDim2.new(1, -40, 0, 26), UDim2.fromOffset(20, 70), 16, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)

  -- 左边：步兵 / 载具 两个页签，下面是卡片
  local sel = { role = nil, spawn = nil, mode = "inf", veh = nil }
  G.deploySel = sel
  local tabInf = button(deploy, "", UDim2.new(0.18, -19, 0, 32), UDim2.fromOffset(20, 100), RGB(48, 56, 40))
  local tabVeh = button(deploy, "", UDim2.new(0.18, -19, 0, 32), UDim2.new(0.18, 9, 0, 100), RGB(28, 34, 40))
  tabInf.TextSize, tabVeh.TextSize = 15, 15
  local roles = Instance.new("ScrollingFrame")
  roles.Size = UDim2.new(0.36, -30, 1, -226)
  roles.Position = UDim2.fromOffset(20, 140)
  roles.BackgroundTransparency = 1
  roles.BorderSizePixel = 0
  roles.ScrollBarThickness = 6
  roles.CanvasSize = UDim2.new()
  roles.AutomaticCanvasSize = Enum.AutomaticSize.Y
  roles.Parent = deploy
  local grid = Instance.new("UIGridLayout")
  grid.CellSize = UDim2.new(0.5, -6, 0, 92)
  grid.CellPadding = UDim2.fromOffset(8, 8)
  grid.SortOrder = Enum.SortOrder.LayoutOrder
  grid.Parent = roles
  local roleCards = {}
  for i, r in ipairs(Config.Roles) do
    local b = Instance.new("TextButton")
    b.Text = ""
    b.LayoutOrder = i
    b.BackgroundColor3 = RGB(28, 34, 40)
    b.BackgroundTransparency = 0.1
    b.AutoButtonColor = true
    b.Parent = roles
    round(b, 8)
    local st = stroke(b, LINE, 2, 1)
    local nm = label(b, "", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(10, 6), 17, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
    local ds = label(b, "", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(10, 28), 12, MUTE, Enum.Font.Gotham, nil, Enum.TextXAlignment.Left)
    ds.TextYAlignment = Enum.TextYAlignment.Top
    local ws = label(b, "", UDim2.new(1, -16, 0, 18), UDim2.new(0, 10, 1, -24), 12, RGB(220, 200, 140), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
    roleCards[r.id] = { b = b, st = st, nm = nm, ds = ds, ws = ws, r = r }
    b.Activated:Connect(function()
      sel.role = r.id
      G.refreshDeploy()
    end)
  end

  -- 载具卡片（这一队能开的型号；分队变了重建）
  local vehs = Instance.new("ScrollingFrame")
  vehs.Size, vehs.Position = roles.Size, roles.Position
  vehs.BackgroundTransparency = 1
  vehs.BorderSizePixel = 0
  vehs.ScrollBarThickness = 6
  vehs.CanvasSize = UDim2.new()
  vehs.AutomaticCanvasSize = Enum.AutomaticSize.Y
  vehs.Visible = false
  vehs.Parent = deploy
  local vgrid = grid:Clone()
  vgrid.Parent = vehs
  local vehCards, vehKey = {}, nil
  local function buildVehCards(S)
    local key = (S.team or "") .. ":" .. table.concat(S.vehModels or {}, ",")
    if key == vehKey then return end
    vehKey = key
    for _, c in pairs(vehCards) do c.b:Destroy() end
    vehCards = {}
    local VD = require(RS:WaitForChild("VehDefs"))
    local ids = {}
    for _, id in ipairs(S.vehModels or {}) do if VD.get(id) then table.insert(ids, id) end end   -- 飞机：驾驶和部署界面还在做，先不显示
    for i, id in ipairs(ids) do
      local d = VD.get(id)
      local b = Instance.new("TextButton")
      b.Text = ""
      b.LayoutOrder = i
      b.BackgroundColor3 = RGB(28, 34, 40)
      b.BackgroundTransparency = 0.1
      b.AutoButtonColor = true
      b.Parent = vehs
      round(b, 8)
      local st = stroke(b, LINE, 2, 1)
      local nm = label(b, "", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(10, 6), 15, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
      local ds = label(b, "", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(10, 28), 12, MUTE, Enum.Font.Gotham, nil, Enum.TextXAlignment.Left)
      ds.TextYAlignment = Enum.TextYAlignment.Top
      local av = label(b, "", UDim2.new(1, -16, 0, 18), UDim2.new(0, 10, 1, -24), 12, RGB(220, 200, 140), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
      vehCards[id] = { b = b, st = st, nm = nm, ds = ds, av = av, d = d }
      b.Activated:Connect(function()
        sel.veh = id
        G.refreshDeploy()
      end)
    end
  end
  local function setMode(m)
    sel.mode = m
    G.refreshDeploy()
  end
  tabInf.Activated:Connect(function() setMode("inf") end)
  tabVeh.Activated:Connect(function() setMode("veh") end)

  -- 右边：地图 + 出生点
  local mapBox = frame(deploy, UDim2.new(0.64, -40, 1, -190), UDim2.new(0.36, 10, 0, 104), RGB(0, 0, 0), 1)
  local mapHolder = frame(mapBox, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0.5, 0))
  local aspect = Instance.new("UIAspectRatioConstraint")
  aspect.AspectRatio = 1
  aspect.Parent = mapHolder
  local spawnLayer = nil
  local spawnBtns = {}
  local extraSpawns = frame(deploy, UDim2.new(0.64, -40, 0, 40), UDim2.new(0.36, 10, 1, -80), RGB(0, 0, 0), 1)
  local extraList = Instance.new("UIListLayout")
  extraList.FillDirection = Enum.FillDirection.Horizontal
  extraList.Padding = UDim.new(0, 8)
  extraList.Parent = extraSpawns

  local deployBtn = button(deploy, "", UDim2.new(0.36, -30, 0, 52), UDim2.new(0, 20, 1, -76), RGB(60, 150, 80))
  deployBtn.TextSize = 22
  deployBtn.Activated:Connect(function()
    local S = G.S
    if not S or S.alive or (S.wait or 0) > 0 then return end
    if sel.mode == "veh" then
      if not sel.veh or not sel.spawn then G.toast(T("ui.needPick"), "bad") return end
      if not (S.vehSpawns and S.vehSpawns[sel.spawn]) then G.toast(T("ui.needSpawnVeh"), "bad") return end
      G.R.Act:FireServer("deployVeh", sel.veh, sel.spawn, sel.role)
      return
    end
    if not sel.role or not sel.spawn then G.toast(T("ui.needPick"), "bad") return end
    G.R.Act:FireServer("deploy", sel.role, sel.spawn)
  end)

  local function spawnName(s)
    if s.kind == "beach" then return T("beach." .. s.beach) end
    if s.kind == "point" then return T("point." .. s.point) end
    if s.kind == "camp" then return T("spawn.camp") end
    if s.kind == "fleet" then return T("spawn.fleet") end
    if s.kind == "para" then return T("spawn.para") end
    return s.id
  end

  local function buildSpawns(S)
    for _, b in ipairs(spawnBtns) do b:Destroy() end
    spawnBtns = {}
    if not spawnLayer then return end
    local ids = {}
    for _, s0 in ipairs(S.spawns or {}) do
      local s = s0
      if sel.mode == "veh" then   -- 载具：只有海滩、据点、营地能出
        local ok = S.vehSpawns and S.vehSpawns[s0.id]
        s = table.clone(s0)
        s.ok = ok == true
      end
      ids[s.id] = s
      local chosen = sel.spawn == s.id
      local b
      if s.x then
        local u, v = G.mapUV(s.x, s.z)
        b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.fromScale(u, v)
        b.Size = UDim2.fromOffset(chosen and 34 or 26, chosen and 34 or 26)
        b.BackgroundColor3 = s.ok and (chosen and RGB(255, 210, 60) or RGB(255, 255, 255)) or RGB(90, 90, 90)
        b.Text = (s.kind == "point") and s.point or ((s.kind == "camp") and "⌂" or "▲")
        b.TextColor3 = RGB(20, 20, 20)
        b.TextScaled = true
        b.Font = Enum.Font.GothamBlack
        b.ZIndex = 8
        b.Parent = spawnLayer
        round(b, 20)
        stroke(b, RGB(0, 0, 0), 2, 0.2)
        local tip = label(b, spawnName(s), UDim2.fromOffset(150, 18), UDim2.new(0.5, 0, 1, 2), 12, TEXT, Enum.Font.GothamBold, Vector2.new(0.5, 0))
        tip.ZIndex = 8
        tip.TextStrokeTransparency = 0.3
      else
        b = button(extraSpawns, spawnName(s), UDim2.fromOffset(210, 40), nil, s.ok and (chosen and RGB(200, 160, 40) or RGB(50, 58, 66)) or RGB(40, 40, 40))
        b.TextSize = 15
      end
      b.Active = s.ok
      b.Activated:Connect(function()
        if not s.ok then G.toast(T("ui.spawnBlocked"), "bad") return end
        sel.spawn = s.id
        G.refreshDeploy()
      end)
      table.insert(spawnBtns, b)
    end
    if sel.spawn and (not ids[sel.spawn] or not ids[sel.spawn].ok) then sel.spawn = nil end
  end

  function G.refreshDeploy()
    local S = G.S
    if not S then return end
    title.Text = T("game.title")
    teamTag.Text = T("team." .. (S.team or "atk"))
    teamTag.BackgroundColor3 = teamColor(S.team)
    goal.Text = T((S.team == "def") and "ui.goalDef" or "ui.goalAtk")
    langBtn.Text = T("ui.lang")
    for id, c in pairs(roleCards) do
      local w = {}
      for _, wid in ipairs(c.r.weapons) do table.insert(w, T("weapon." .. wid)) end
      c.nm.Text = T("role." .. id)
      c.ds.Text = T("role." .. id .. ".desc")
      c.ws.Text = table.concat(w, " · ")
      local on = sel.role == id
      c.st.Transparency = on and 0 or 1
      c.st.Color = RGB(255, 210, 60)
      c.b.BackgroundColor3 = on and RGB(48, 56, 40) or RGB(28, 34, 40)
    end
    tabInf.Text, tabVeh.Text = T("ui.tabInf"), T("ui.tabVeh")
    tabInf.BackgroundColor3 = (sel.mode == "inf") and RGB(48, 56, 40) or RGB(28, 34, 40)
    tabVeh.BackgroundColor3 = (sel.mode == "veh") and RGB(48, 56, 40) or RGB(28, 34, 40)
    roles.Visible = sel.mode == "inf"
    vehs.Visible = sel.mode == "veh"
    if sel.mode == "veh" then
      buildVehCards(S)
      local VD = require(RS:WaitForChild("VehDefs"))
      for id, c in pairs(vehCards) do
        local d = c.d
        local av = S.vehAvail and S.vehAvail[d.cat] or { u = 0, cap = 0, cd = 0 }
        local ws = {}
        for _, wid in ipairs(d.weapons) do table.insert(ws, T("vw." .. wid)) end
        c.nm.Text = T("veh." .. id)
        c.ds.Text = T("vcat." .. d.cat) .. " · " .. table.concat(ws, " / ")
        local full = av.u >= av.cap
        c.av.Text = T("ui.vehCap", av.u, av.cap) .. ((full and av.cd > 0) and ("   " .. T("ui.vehCd", av.cd)) or "")
        c.av.TextColor3 = full and RGB(230, 110, 100) or RGB(160, 220, 150)
        local on = sel.veh == id
        c.st.Transparency = on and 0 or 1
        c.st.Color = RGB(255, 210, 60)
        c.b.BackgroundColor3 = on and RGB(48, 56, 40) or RGB(28, 34, 40)
      end
      if sel.veh and not vehCards[sel.veh] then sel.veh = nil end
    end
    buildSpawns(S)
    if (S.wait or 0) > 0 then
      deployBtn.Text = T("ui.waitRespawn", S.wait)
      deployBtn.BackgroundColor3 = RGB(70, 70, 70)
    else
      deployBtn.Text = T("ui.deployBtn")
      local ready = (sel.mode == "veh") and (sel.veh and sel.spawn) or (sel.role and sel.spawn)
      deployBtn.BackgroundColor3 = ready and RGB(60, 150, 80) or RGB(70, 90, 76)
    end
  end

  langBtn.Activated:Connect(function()
    G.lang = (G.lang == "zh") and "en" or "zh"
    G.refresh()
  end)

  ---------------------------------------------------------------- 顶栏：时间、据点

  local hud = frame(gui, UDim2.fromScale(1, 1), nil, PANEL, 1)
  hud.Name = "Hud"
  local topBar = frame(hud, UDim2.fromOffset(460, 74), UDim2.new(0.5, 0, 0, 8), PANEL, 0.35, Vector2.new(0.5, 0))
  round(topBar, 10)
  local timer = label(topBar, "", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 4), 20, TEXT, Enum.Font.GothamBlack)
  local chips = {}
  for i, p in ipairs(Map.POINTS) do
    local c = frame(topBar, UDim2.fromOffset(80, 38), UDim2.fromOffset(10 + (i - 1) * 89, 30), RGB(30, 40, 60), 0.05)
    round(c, 6)
    local l = label(c, p.id, UDim2.new(0, 26, 1, 0), UDim2.fromOffset(4, 0), 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
    local n = label(c, "", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(30, 3), 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
    local barBg = frame(c, UDim2.new(1, -36, 0, 5), UDim2.new(0, 30, 1, -10), RGB(0, 0, 0), 0.5)
    local bar = frame(barBg, UDim2.fromScale(0, 1), nil, Config.Teams.atk.color, 0)
    chips[p.id] = { f = c, l = l, n = n, bar = bar }
  end
  local counts = label(hud, "", UDim2.fromOffset(240, 20), UDim2.new(0.5, 0, 0, 84), 14, TEXT, Enum.Font.GothamBold, Vector2.new(0.5, 0))
  counts.TextStrokeTransparency = 0.5

  -- 血条
  local hpBg = frame(hud, UDim2.fromOffset(260, 14), UDim2.new(0, 20, 1, -40), RGB(0, 0, 0), 0.45)
  round(hpBg, 4)
  local hpBar = frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  round(hpBar, 4)
  local hpText = label(hpBg, "", UDim2.fromScale(1, 1), nil, 12, Color3.new(1, 1, 1), Enum.Font.GothamBold)
  local roleText = label(hud, "", UDim2.fromOffset(260, 18), UDim2.new(0, 20, 1, -62), 14, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  roleText.TextStrokeTransparency = 0.5
  local help = label(hud, "", UDim2.new(0.6, 0, 0, 16), UDim2.new(0.5, 0, 1, -18), 12, MUTE, Enum.Font.Gotham, Vector2.new(0.5, 0))
  help.TextStrokeTransparency = 0.6

  -- 小地图容器（右下）
  local miniBox = frame(hud, UDim2.fromOffset(230, 230), UDim2.new(1, -16, 1, -16), PANEL, 1, Vector2.new(1, 1))

  ---------------------------------------------------------------- 消息

  local center = label(gui, "", UDim2.new(0.8, 0, 0, 40), UDim2.new(0.5, 0, 0.3, 0), 28, Color3.new(1, 1, 1), Enum.Font.GothamBlack, Vector2.new(0.5, 0.5))
  center.TextStrokeTransparency = 0.3
  center.ZIndex = 30
  local centerT = 0
  local feed = frame(gui, UDim2.fromOffset(340, 160), UDim2.new(1, -16, 0, 120), PANEL, 1, Vector2.new(1, 0))
  local feedList = Instance.new("UIListLayout")
  feedList.HorizontalAlignment = Enum.HorizontalAlignment.Right
  feedList.SortOrder = Enum.SortOrder.LayoutOrder
  feedList.Parent = feed
  local toasts = frame(gui, UDim2.fromOffset(520, 200), UDim2.new(0.5, 0, 1, -110), PANEL, 1, Vector2.new(0.5, 1))
  local toastList = Instance.new("UIListLayout")
  toastList.VerticalAlignment = Enum.VerticalAlignment.Bottom
  toastList.HorizontalAlignment = Enum.HorizontalAlignment.Center
  toastList.Padding = UDim.new(0, 4)
  toastList.SortOrder = Enum.SortOrder.LayoutOrder
  toastList.Parent = toasts
  local order = 0
  local KIND_COL = { good = RGB(60, 150, 80), bad = RGB(170, 50, 45), info = RGB(40, 50, 60), kill = RGB(150, 110, 30) }
  function G.toast(text, kind)
    order += 1
    local l = label(toasts, text, UDim2.fromOffset(500, 26), nil, 15, Color3.new(1, 1, 1), Enum.Font.GothamBold)
    l.BackgroundColor3 = KIND_COL[kind or "info"] or KIND_COL.info
    l.BackgroundTransparency = 0.2
    l.LayoutOrder = order
    round(l, 6)
    task.delay(4, function() l:Destroy() end)
  end
  function G.centerMsg(text)
    center.Text = text
    center.TextTransparency = 0
    centerT = os.clock()
  end
  local function feedAdd(text)
    order += 1
    local l = label(feed, text, UDim2.fromOffset(340, 22), nil, 14, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Right)
    l.TextStrokeTransparency = 0.4
    l.LayoutOrder = order
    local kids = {}
    for _, c in ipairs(feed:GetChildren()) do if c:IsA("TextLabel") then table.insert(kids, c) end end
    if #kids > 6 then table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end) kids[1]:Destroy() end
    task.delay(8, function() l:Destroy() end)
  end

  -- 服务器发来的文字：kind、编号、参数（参数里的 { k = 编号 } 也翻译）
  function G.onMsg(kind, key, ...)
    if kind == "hit" then
      if G.hitMarker then G.hitMarker(key) end
      return
    end
    local text = T(key, ...)
    if kind == "center" then G.centerMsg(text)
    elseif kind == "feed" then feedAdd(text)
    else G.toast(text, kind) end
  end

  ---------------------------------------------------------------- 战况表（按住 Tab）

  local board = frame(gui, UDim2.fromOffset(760, 520), UDim2.fromScale(0.5, 0.5), PANEL, 0.12, Vector2.new(0.5, 0.5))
  board.Visible = false
  board.ZIndex = 20
  round(board, 10)
  local boardTitle = label(board, "", UDim2.new(1, 0, 0, 36), nil, 20, TEXT, Enum.Font.GothamBlack)
  boardTitle.ZIndex = 21
  local cols = {}
  for i, t in ipairs({ "atk", "def" }) do
    local c = frame(board, UDim2.new(0.5, -18, 1, -50), UDim2.new((i - 1) * 0.5, 12, 0, 42), RGB(0, 0, 0), 0.6)
    c.ZIndex = 21
    round(c, 8)
    local h = label(c, "", UDim2.new(1, 0, 0, 26), nil, 16, teamColor(t), Enum.Font.GothamBlack)
    h.ZIndex = 22
    local list = Instance.new("Frame")
    list.BackgroundTransparency = 1
    list.Size = UDim2.new(1, -8, 1, -32)
    list.Position = UDim2.fromOffset(4, 30)
    list.ZIndex = 22
    list.Parent = c
    local ll = Instance.new("UIListLayout")
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Parent = list
    cols[t] = { head = h, list = list }
  end
  local boardData = {}
  function G.onBoard(d) boardData = d or {} if board.Visible then G.drawBoard() end end
  function G.drawBoard()
    boardTitle.Text = T("ui.scoreboard")
    for t, c in pairs(cols) do
      for _, k in ipairs(c.list:GetChildren()) do if k:IsA("Frame") then k:Destroy() end end
      local rows = {}
      for _, e in ipairs(boardData) do if e.t == t then table.insert(rows, e) end end
      table.sort(rows, function(a, b) return (a.s or 0) > (b.s or 0) end)
      c.head.Text = T("team." .. t) .. "  (" .. #rows .. ")"
      local hdr = frame(c.list, UDim2.new(1, 0, 0, 18), nil, PANEL, 1)
      hdr.LayoutOrder = 0
      hdr.ZIndex = 22
      for k, txt in ipairs({ "", T("ui.kills"), T("ui.deaths"), T("ui.captures"), T("ui.score") }) do
        local l = label(hdr, txt, UDim2.new(k == 1 and 0.44 or 0.14, 0, 1, 0), UDim2.new(k == 1 and 0 or (0.44 + (k - 2) * 0.14), 0, 0, 0), 11, MUTE, Enum.Font.GothamBold)
        l.ZIndex = 23
      end
      for i, e in ipairs(rows) do
        if i > 22 then break end
        local r = frame(c.list, UDim2.new(1, 0, 0, 18), nil, (e.id == player.UserId) and RGB(80, 70, 30) or PANEL, (e.id == player.UserId) and 0.3 or 1)
        r.LayoutOrder = i
        r.ZIndex = 22
        local nm = e.n .. (e.bot and (" " .. T("ui.bot")) or "")
        for k, txt in ipairs({ nm, tostring(e.k or 0), tostring(e.d or 0), tostring(e.c or 0), tostring(e.s or 0) }) do
          local l = label(r, txt, UDim2.new(k == 1 and 0.44 or 0.14, 0, 1, 0), UDim2.new(k == 1 and 0 or (0.44 + (k - 2) * 0.14), 0, 0, 0), 12, TEXT,
            Enum.Font.GothamMedium, nil, k == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center)
          l.ZIndex = 23
          l.TextTruncate = Enum.TextTruncate.AtEnd
        end
      end
    end
  end
  UIS.InputBegan:Connect(function(io, gp)
    if io.KeyCode == Enum.KeyCode.Tab then
      board.Visible = true
      G.drawBoard()
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.KeyCode == Enum.KeyCode.Tab then board.Visible = false end
  end)
  local boardBtn = button(hud, "≡", UDim2.fromOffset(40, 40), UDim2.new(0, 16, 0, 16), RGB(40, 46, 52))
  boardBtn.TextSize = 22
  boardBtn.Activated:Connect(function()
    board.Visible = not board.Visible
    if board.Visible then G.drawBoard() end
  end)

  ---------------------------------------------------------------- 结算

  local results = frame(gui, UDim2.fromOffset(620, 300), UDim2.fromScale(0.5, 0.45), PANEL, 0.1, Vector2.new(0.5, 0.5))
  results.Visible = false
  results.ZIndex = 25
  round(results, 12)
  local resTitle = label(results, "", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 16), 30, TEXT, Enum.Font.GothamBlack)
  local resSub = label(results, "", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 70), 18, MUTE, Enum.Font.GothamBold)
  local resStats = label(results, "", UDim2.new(1, -20, 0, 90), UDim2.fromOffset(10, 110), 18, TEXT, Enum.Font.GothamMedium)
  local resNext = label(results, "", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 1, -46), 16, MUTE, Enum.Font.GothamMedium)
  for _, x in ipairs({ resTitle, resSub, resStats, resNext }) do x.ZIndex = 26 end

  ---------------------------------------------------------------- 刷新（收到服务器状态时）

  local mapMountedIn = nil
  function G.refresh()
    local S = G.S
    if not S then return end
    if (S.progress or 1) < 1 then
      loading.Visible = true
      loadText.Text = T("ui.serverStarting", math.floor((S.progress or 0) * 100))
      return
    end
    loading.Visible = false
    local showDeploy = not S.alive and S.phase ~= "end"
    deploy.Visible = showDeploy
    hud.Visible = not showDeploy
    results.Visible = S.phase == "end"
    -- 地图放在部署界面或小地图里
    local want = showDeploy and mapHolder or miniBox
    if mapMountedIn ~= want then
      mapMountedIn = want
      local _, marks = G.mapMount(want, UDim2.fromScale(1, 1))
      spawnLayer = marks
    end
    if G.mapRefresh then G.mapRefresh(S) end
    if showDeploy then
      if not sel.role then sel.role = S.role or "rifle" end
      G.refreshDeploy()
      if S.phase == "prep" then phaseText.Text = T("ui.prep", S.left) else phaseText.Text = T("ui.timeLeft") .. "  " .. fmtTime(S.left) end
    else
      for _, b in ipairs(spawnBtns) do b:Destroy() end
      spawnBtns = {}
    end
    -- 顶栏
    if S.phase == "prep" then
      timer.Text = T("ui.prep", S.left)
    elseif S.ot then
      timer.Text = T("ui.overtime") .. "  " .. fmtTime(S.ot)
    else
      timer.Text = fmtTime(S.left)
    end
    for _, s in ipairs(S.points or {}) do
      local c = chips[s.id]
      if c then
        c.f.BackgroundColor3 = teamColor(s.owner):Lerp(Color3.new(0, 0, 0), 0.25)
        c.bar.Size = UDim2.fromScale(s.locked and 1 or s.prog, 1)
        c.n.Text = s.locked and "" or ((s.atk > 0 or s.def > 0) and (T("team.atk.short") .. s.atk .. " " .. T("team.def.short") .. s.def) or "")
      end
    end
    counts.Text = T("team.atk") .. " " .. (S.nAtk or 0) .. "   ·   " .. T("team.def") .. " " .. (S.nDef or 0)
    roleText.Text = (S.role and T("role." .. S.role) or "") .. "  ·  " .. T("team." .. (S.team or "atk"))
    roleText.TextColor3 = teamColor(S.team)
    help.Text = T("ui.help")
    if S.phase == "end" then
      local won = S.winner == S.team
      resTitle.Text = T(won and "ui.youWon" or "ui.youLost")
      resTitle.TextColor3 = won and RGB(120, 230, 140) or RGB(240, 110, 100)
      resSub.Text = T((S.winner == "atk") and "ui.win.atk" or "ui.win.def") .. (S.mvp and ("   MVP: " .. S.mvp) or "")
      local me = S.me or {}
      resStats.Text = T("ui.kills") .. " " .. (me.k or 0) .. "    " .. T("ui.deaths") .. " " .. (me.d or 0) .. "    " .. T("ui.captures") .. " " .. (me.c or 0) .. "    " .. T("ui.score") .. " " .. (me.s or 0)
        .. "\n" .. T("ui.xp", me.gain or 0) .. "    " .. Lang.rank(G.lang, me.rank or 1)
      resNext.Text = T("ui.nextRound", S.left)
    end
  end

  function G.stepUI(dt)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
      local k = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
      hpBar.Size = UDim2.fromScale(k, 1)
      hpBar.BackgroundColor3 = RGB(230, 70, 60):Lerp(RGB(90, 210, 110), k)
      hpText.Text = math.ceil(hum.Health) .. " / " .. math.ceil(hum.MaxHealth)
    end
    local a = os.clock() - centerT
    center.TextTransparency = math.clamp((a - 3) / 1, 0, 1)
    center.TextStrokeTransparency = 0.3 + 0.7 * math.clamp((a - 3) / 1, 0, 1)
  end
end

return UI
