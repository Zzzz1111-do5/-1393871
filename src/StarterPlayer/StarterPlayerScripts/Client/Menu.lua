-- Roblox全面大战场（客户端）——主菜单：照用户给的第一张截图，比截图更精致、更简洁
--   进服先到这里（还没定阵营时），盖在选阵营界面上面：左上玩家名、军衔、经验条；左边一列大卡片（只有字：用户嫌卡片里放坦克、战斗机这些模型奇怪）——
--   进入战斗（→ 选阵营 / 部署）· 选择阵营 · 操作说明 · 模型与授权（Sketchfab 作者署名，CC-BY 要求的）；右下游戏名、测试版、版本号
--   部署界面右上角「菜单」能回来
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Menu = {}

function Menu.init(G)
  local me = Players.LocalPlayer
  local Config = G.Config
  local RGB = Color3.fromRGB
  local V2 = Vector2.new
  local function T(k, ...) return G.T(k, ...) end
  local WHITE, TEXT, MUTE, FAINT = Color3.new(1, 1, 1), RGB(236, 238, 240), RGB(156, 162, 168), RGB(104, 110, 116)
  local Stage = require(script.Parent:WaitForChild("MenuStage"))   -- 背后的 3D 场景（废墟、火光、火星、全副武装的士兵）

  local gui = Instance.new("ScreenGui")
  gui.Name = "Menu"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 14   -- 盖在选阵营（12）上面
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
  local function text(parent, str, size, pos, ts, color, font, anchor, xa)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = str or "", ts or 14, color or TEXT, font or Enum.Font.GothamMedium
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    if anchor then l.AnchorPoint = anchor end
    l.Parent = parent
    return l
  end
  local function stroke(f, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Transparency, s.Thickness, s.ApplyStrokeMode = WHITE, tr or 0.88, 1, Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end

  -- 背景：近黑，左边压暗（原来右边还放一个大的原模型，和卡片里的模型一起去掉了）
  local bg = frame(gui, UDim2.fromScale(1, 1), nil, RGB(6, 8, 10), 0)   -- 后面的场景搭好了就透明（MenuStage.lua），没搭好照旧近黑
  -- 左边压暗（卡片、玩家名压在上面看得清）；后面的场景开着时浅一点，像参考图那样卡片后面还透出火光和废墟
  local shade = frame(bg, UDim2.fromScale(1, 1), nil, RGB(6, 8, 10), 0)
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.42, 0.08), NumberSequenceKeypoint.new(0.62, 0.75), NumberSequenceKeypoint.new(1, 0.9) })
    g.Parent = shade
  end
  -- 上下暗角（电影感）
  local vignette = frame(bg, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 0)
  do
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.18, 0.85), NumberSequenceKeypoint.new(0.75, 0.9), NumberSequenceKeypoint.new(1, 0.25) })
    g.Parent = vignette
  end
  -- 内容按 1280 × 720 摆，按屏幕整体缩放（手机横屏也放得下）
  local content = frame(bg, UDim2.fromOffset(1280, 720), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, V2(0.5, 0.5))
  local scale = Instance.new("UIScale")
  scale.Parent = content
  local function fit()
    local vs = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.clamp(math.min(vs.X / 1280, vs.Y / 720), 0.4, 1.3)
  end
  fit()
  workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

  -- 左上：玩家名、军衔、经验条
  local X0, CW = 48, 440
  local who = text(content, "", UDim2.fromOffset(CW, 26), UDim2.fromOffset(X0, 92), 22, WHITE, Enum.Font.GothamBold)
  local rankLine = text(content, "", UDim2.fromOffset(CW - 140, 14), UDim2.fromOffset(X0, 122), 11, MUTE, Enum.Font.GothamMedium)
  local xpLine = text(content, "", UDim2.fromOffset(160, 14), UDim2.fromOffset(X0 + CW, 122), 11, MUTE, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right)
  local xpBg = frame(content, UDim2.fromOffset(CW, 2), UDim2.fromOffset(X0, 142), WHITE, 0.85)
  local xpFill = frame(xpBg, UDim2.fromScale(0, 1), nil, WHITE, 0)

  -- 模型署名（「模型与授权」面板用）
  local META = {}
  for _, k in ipairs({ "ImportedMeta", "ImportedAir", "ImportedShip" }) do
    local ok, r = pcall(function() return require(RS:WaitForChild(k, 3)) end)
    if ok and type(r) == "table" then META[k] = r end
  end

  ---------------------------------------------------------------- 卡片

  local cards = {}
  local CH, GAP, Y0 = 104, 8, 160
  local function card(i, onClick)
    local b = Instance.new("TextButton")
    b.Name = "Card" .. i
    b.Size = UDim2.fromOffset(CW, CH)
    b.Position = UDim2.fromOffset(X0, Y0 + (i - 1) * (CH + GAP))
    b.BackgroundColor3 = RGB(10, 12, 14)
    b.BackgroundTransparency = 0.3
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = ""
    b.ClipsDescendants = true
    b.Parent = content
    local st = stroke(b, 0.88)
    local K = { b = b, st = st }
    K.cat = text(b, "", UDim2.fromOffset(260, 12), UDim2.fromOffset(20, 24), 10, MUTE, Enum.Font.GothamMedium)
    K.title = text(b, "", UDim2.fromOffset(300, 30), UDim2.fromOffset(19, 40), 24, WHITE, Enum.Font.GothamBold)
    K.sub = text(b, "", UDim2.fromOffset(300, 14), UDim2.fromOffset(20, 74), 10, MUTE, Enum.Font.GothamMedium)
    K.tag = text(b, "", UDim2.fromOffset(180, 16), UDim2.new(1, -18, 0, 36), 13, WHITE, Enum.Font.GothamBold, V2(1, 0), Enum.TextXAlignment.Right)
    K.subtag = text(b, "", UDim2.fromOffset(180, 12), UDim2.new(1, -18, 0, 56), 10, MUTE, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right)
    for _, l in ipairs({ K.tag, K.subtag, K.title }) do
      l.TextStrokeTransparency = 0.6
      l.TextStrokeColor3 = Color3.new(0, 0, 0)
    end
    b.MouseEnter:Connect(function() st.Transparency, b.BackgroundTransparency = 0.55, 0.2 end)
    b.MouseLeave:Connect(function() st.Transparency, b.BackgroundTransparency = 0.88, 0.3 end)
    b.Activated:Connect(onClick)
    cards[i] = K
    return K
  end

  -- 右边的说明面板（操作说明、模型与授权）
  local panel = frame(content, UDim2.fromOffset(560, 560), UDim2.fromOffset(1232, 92), RGB(8, 10, 12), 0.08, V2(1, 0))
  panel.Visible = false
  stroke(panel, 0.86)
  local pTitle = text(panel, "", UDim2.new(1, -120, 0, 24), UDim2.fromOffset(24, 20), 18, WHITE, Enum.Font.GothamBold)
  local pClose = Instance.new("TextButton")
  pClose.Size, pClose.Position, pClose.AnchorPoint = UDim2.fromOffset(80, 24), UDim2.new(1, -20, 0, 20), V2(1, 0)
  pClose.BackgroundTransparency = 1
  pClose.TextColor3, pClose.TextSize, pClose.Font = MUTE, 12, Enum.Font.GothamMedium
  pClose.TextXAlignment = Enum.TextXAlignment.Right
  pClose.Parent = panel
  frame(panel, UDim2.new(1, -48, 0, 1), UDim2.fromOffset(24, 56), WHITE, 0.88)
  local pScroll = Instance.new("ScrollingFrame")
  pScroll.Size = UDim2.new(1, -40, 1, -84)
  pScroll.Position = UDim2.fromOffset(24, 68)
  pScroll.BackgroundTransparency = 1
  pScroll.BorderSizePixel = 0
  pScroll.ScrollBarThickness = 2
  pScroll.ScrollBarImageColor3 = WHITE
  pScroll.CanvasSize = UDim2.new()
  pScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
  pScroll.Parent = panel
  local pBody = Instance.new("TextLabel")
  pBody.Size = UDim2.new(1, -12, 0, 0)
  pBody.AutomaticSize = Enum.AutomaticSize.Y
  pBody.BackgroundTransparency = 1
  pBody.TextWrapped = true
  pBody.RichText = true
  pBody.TextXAlignment = Enum.TextXAlignment.Left
  pBody.TextYAlignment = Enum.TextYAlignment.Top
  pBody.TextSize = 13
  pBody.LineHeight = 1.25
  pBody.TextColor3 = TEXT
  pBody.Font = Enum.Font.GothamMedium
  pBody.Parent = pScroll
  local panelKind = nil
  local function head(s) return '<font color="#FFFFFF" size="14"><b>' .. s .. "</b></font>" end
  local function showPanel(kind)
    if panelKind == kind and panel.Visible then panel.Visible = false panelKind = nil return end
    panelKind = kind
    panel.Visible = true
    pClose.Text = T("menu.close")
    if kind == "help" then
      pTitle.Text = T("menu.c3.title")
      local function plain(k) return (string.gsub(T(k), " · ", "\n")) end
      pBody.Text = head(T("menu.h.inf")) .. "\n" .. plain("ui.help") .. "\n\n" .. head(T("menu.h.veh")) .. "\n" .. plain("ui.vehHelp")
        .. "\n\n" .. head(T("menu.h.jet")) .. "\n" .. plain("air.helpJet") .. "\n\n" .. head(T("menu.h.heli")) .. "\n" .. plain("air.helpHeli")
    else
      pTitle.Text = T("menu.c4.title")
      local lines = {}
      for _, k in ipairs({ "ImportedMeta", "ImportedAir", "ImportedShip" }) do
        local m = META[k]
        if m and m.m then
          local keys = {}
          for key in pairs(m.m) do table.insert(keys, key) end
          table.sort(keys)
          for _, key in ipairs(keys) do
            local c = m.m[key].credit
            if c then table.insert(lines, (string.gsub(c, "（https?://[^）]*）", ""))) end
          end
        end
      end
      local okO, OM = pcall(function() return require(RS:WaitForChild("OpticsMeta", 3)) end)
      if okO and type(OM) == "table" then
        local keys = {}
        for key in pairs(OM) do table.insert(keys, key) end
        table.sort(keys)
        for _, key in ipairs(keys) do
          local c = OM[key].credit
          if c then table.insert(lines, (string.gsub(c, "%s*https?://%S+", ""))) end
        end
      end
      local okW, WMeta = pcall(function() return require(RS:WaitForChild("ImportedWpn", 3)) end)   -- 导弹合集（CC BY-NC-SA）
      if okW and type(WMeta) == "table" and WMeta.credit then table.insert(lines, (string.gsub(WMeta.credit, "（https?://[^）]*）", ""))) end
      pBody.Text = table.concat(lines, "\n\n")
    end
  end
  pClose.Activated:Connect(function() panel.Visible = false panelKind = nil end)

  local entered = false   -- 点过「进入战斗」：这次进服不再自动弹主菜单
  local stageOn, stageTeam = false, nil   -- 背后的场景开着没有、按哪一方搭的
  local function enter()
    entered = true
    G.menuOpenNow = false
    gui.Enabled = false
    panel.Visible = false
    if stageOn then stageOn = false Stage.show(false) end
    if G.refresh then G.refresh() end
  end
  -- 第一张卡「快速加入」（用户：没法快速进入战局）：点一下自动分队、默认装备，直接出生在离当前目标最近的出生点（Round.lua ACT.quickJoin）
  local function quick()
    enter()
    G.quickAt = os.clock()   -- 等服务器出生的这一会儿别弹选阵营界面（Faction.lua）
    G.R.Act:FireServer("quickJoin")
  end
  G.quickJoin = quick
  card(1, quick)
  card(2, function()
    enter()
    if G.showFaction then G.showFaction() end
  end)
  card(3, function() showPanel("help") end)
  card(4, function() showPanel("credits") end)
  -- 回车：快速加入
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not gui.Enabled then return end
    if io.KeyCode == Enum.KeyCode.Return then quick() end
  end)

  -- 右下：游戏名、测试版、版本号
  local gTitle = text(content, "", UDim2.fromOffset(400, 24), UDim2.fromOffset(1232, 624), 20, WHITE, Enum.Font.GothamBold, V2(1, 0), Enum.TextXAlignment.Right)
  local gSub = text(content, "", UDim2.fromOffset(400, 14), UDim2.fromOffset(1232, 652), 11, MUTE, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right)
  local gVer = text(content, "", UDim2.fromOffset(400, 12), UDim2.fromOffset(1232, 668), 10, FAINT, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right)

  ---------------------------------------------------------------- 刷新

  function G.stepMenu(dt) if stageOn then Stage.step(dt) end end
  function G.refreshMenu(S)
    if not S then return end
    local show = (G.menuOpenNow == true) or ((not entered) and (not S.alive) and (not S.picked) and (S.progress or 1) >= 1)
    gui.Enabled = show
    -- 背后的场景：开着主菜单时镜头对着它，关了收起来、镜头还给游戏
    if show ~= stageOn then
      stageOn = show
      Stage.show(show, S.team or "atk")
    elseif show and stageTeam ~= (S.team or "atk") then
      Stage.show(true, S.team or "atk")
    end
    stageTeam = S.team or "atk"
    local live = Stage.active()
    bg.BackgroundTransparency = live and 1 or 0
    shade.BackgroundTransparency = live and 0.4 or 0
    if not show then return end
    local mine = S.me or {}
    who.Text = me.DisplayName
    local R = Config.Ranks or { 0 }
    local rk = math.clamp(mine.rank or 1, 1, #R)
    local xp = mine.xp or 0
    if rk < #R then
      rankLine.Text = T("menu.rankLine", G.Lang.rank(G.lang, rk), G.Lang.rank(G.lang, rk + 1))
      xpLine.Text = T("menu.xp", xp, R[rk + 1])
      xpFill.Size = UDim2.fromScale(math.clamp((xp - R[rk]) / math.max(1, R[rk + 1] - R[rk]), 0, 1), 1)
    else
      rankLine.Text = T("menu.maxRank", G.Lang.rank(G.lang, rk))
      xpLine.Text = tostring(xp)
      xpFill.Size = UDim2.fromScale(1, 1)
    end
    local team = S.team or "atk"
    for i, K in ipairs(cards) do
      K.cat.Text = T("menu.c" .. i .. ".cat")
      K.title.Text = T("menu.c" .. i .. ".title")
      K.sub.Text = T("menu.c" .. i .. ".sub")
      K.tag.Text, K.subtag.Text = "", ""
    end
    cards[1].tag.Text = T("menu.c1.tag")
    cards[1].subtag.Text = T("menu.c1.subtag", (S.rAtk or 0) + (S.rDef or 0))
    cards[2].tag.Text = S.picked and T("faction." .. team .. ".name") or T("menu.c2.none")
    cards[2].subtag.Text = (S.rAtk or 0) .. " : " .. (S.rDef or 0)
    gTitle.Text = T("game.title")
    gSub.Text = T("menu.beta")
    gVer.Text = tostring(Config.Version or "")
  end
  -- 部署界面右上角「菜单」
  function G.showMenu()
    G.menuOpenNow = true
    if G.S then G.refreshMenu(G.S) end
  end
  G.menuEnter = enter   -- 测试、截图用
  function G.menuShown() return gui.Enabled end
end

return Menu
