-- Roblox全面大战场——选阵营（客户端）：进服先看这个（服务器的 S.picked 还没定）；部署界面顶上「换阵营」也能回来（没出生的时候）
--   两张竖着的阵营档案卡并排：顶上一条阵营色细线、徽记、英文全称、中文名、任务、三样主要装备、在线人数和两边的比例条、加入按钮；
--   人多的一边「人数已满」；整体黑底、直角、细线（用户：参考截图但要更好、变化要大——不做左右两半的大国旗）
local Players = game:GetService("Players")

local Faction = {}

function Faction.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local function T(k, ...) return G.T(k, ...) end
  local TEXT, MUTE, LINE = RGB(238, 240, 242), RGB(138, 146, 154), RGB(255, 255, 255)
  local COL = { atk = RGB(214, 58, 46), def = RGB(64, 132, 238) }
  local GOLD = RGB(232, 196, 92)

  local gui = Instance.new("ScreenGui")
  gui.Name = "Faction"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 12
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
    if anchor then l.AnchorPoint = anchor end
    l.Parent = parent
    return l
  end
  local function line(parent, pos, w, tr)
    return frame(parent, UDim2.new(0, w, 0, 1), pos, LINE, tr or 0.88)
  end

  -- 背景：近黑；左下、右下两团很淡的阵营色
  local bg = frame(gui, UDim2.fromScale(1, 1), nil, RGB(7, 9, 12), 0)
  for i, side in ipairs({ "atk", "def" }) do
    local g = frame(bg, UDim2.fromScale(0.5, 1), UDim2.fromScale((i - 1) * 0.5, 0), COL[side], 0)
    local gr = Instance.new("UIGradient")
    gr.Rotation = (i == 1) and 0 or 180
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 1) })
    gr.Parent = g
  end
  -- 内容按 1280 × 720 摆，按屏幕大小整体缩放（手机横屏 844 × 390 也放得下）
  local content = frame(bg, UDim2.fromOffset(1280, 720), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  local scale = Instance.new("UIScale")
  scale.Parent = content
  local function fit()
    local vs = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.clamp(math.min(vs.X / 1280, vs.Y / 720), 0.4, 1.3)
  end
  fit()
  workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
  -- 顶上：游戏名、副标题、语言
  local head = text(content, "", UDim2.new(0, 520, 0, 30), UDim2.new(0.5, 0, 0, 40), 26, TEXT, Enum.Font.GothamBlack, Vector2.new(0.5, 0), Enum.TextXAlignment.Center)
  local sub = text(content, "", UDim2.new(0, 520, 0, 16), UDim2.new(0.5, 0, 0, 74), 12, MUTE, Enum.Font.GothamMedium, Vector2.new(0.5, 0), Enum.TextXAlignment.Center)
  line(content, UDim2.new(0.5, -40, 0, 98), 80, 0.6)
  local langBtn = Instance.new("TextButton")
  langBtn.Size, langBtn.Position, langBtn.AnchorPoint = UDim2.fromOffset(96, 30), UDim2.new(1, -24, 0, 24), Vector2.new(1, 0)
  langBtn.BackgroundColor3, langBtn.BackgroundTransparency, langBtn.BorderSizePixel = RGB(255, 255, 255), 0.94, 0
  langBtn.TextColor3, langBtn.TextSize, langBtn.Font = TEXT, 13, Enum.Font.GothamMedium
  langBtn.AutoButtonColor = true
  langBtn.Parent = bg
  local lst = Instance.new("UIStroke")
  lst.Color, lst.Transparency, lst.Thickness, lst.ApplyStrokeMode = LINE, 0.8, 1, Enum.ApplyStrokeMode.Border
  lst.Parent = langBtn
  langBtn.Activated:Connect(function()
    G.lang = (G.lang == "zh") and "en" or "zh"
    if G.refresh then G.refresh() end
  end)

  -- 两张档案卡
  local cards = {}
  local W, H = 420, 468
  local GEAR = { atk = { { "tank", "ztz99a" }, { "jet", "j35" }, { "heli", "z10" } }, def = { { "tank", "m1a2" }, { "jet", "f22" }, { "heli", "ah64e" } } }
  for i, side in ipairs({ "atk", "def" }) do
    local c = frame(content, UDim2.fromOffset(W, H), UDim2.new(0.5, (i == 1) and -(W + 14) or 14, 0.5, 16), RGB(13, 15, 19), 0.04, Vector2.new(0, 0.5))
    c.Name = "Card_" .. side
    local cs = Instance.new("UIStroke")
    cs.Color, cs.Transparency, cs.Thickness, cs.ApplyStrokeMode = LINE, 0.9, 1, Enum.ApplyStrokeMode.Border
    cs.Parent = c
    frame(c, UDim2.new(1, 0, 0, 3), nil, COL[side], 0)   -- 顶上一条阵营色
    -- 徽记：解放军是金边红底上一颗金星；美军是蓝圆里一颗白星
    local em = frame(c, UDim2.fromOffset(58, 58), UDim2.fromOffset(28, 30), (side == "atk") and RGB(170, 32, 28) or RGB(26, 56, 112), 0)
    local es = Instance.new("UIStroke")
    es.Color, es.Thickness, es.ApplyStrokeMode = (side == "atk") and GOLD or RGB(220, 226, 236), 1.5, Enum.ApplyStrokeMode.Border
    es.Parent = em
    if side == "def" then
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(0.5, 0)
      cr.Parent = em
    end
    text(em, "★", UDim2.fromScale(1, 1), nil, 34, (side == "atk") and GOLD or RGB(255, 255, 255), Enum.Font.GothamBlack, nil, Enum.TextXAlignment.Center)
    local K = {}
    K.en = text(c, "", UDim2.new(1, -120, 0, 14), UDim2.fromOffset(102, 34), 11, MUTE, Enum.Font.GothamBold)
    K.name = text(c, "", UDim2.new(1, -120, 0, 32), UDim2.fromOffset(102, 50), 26, TEXT, Enum.Font.GothamBlack)
    K.role = text(c, "", UDim2.new(1, -56, 0, 18), UDim2.fromOffset(28, 108), 14, COL[side]:Lerp(RGB(255, 255, 255), 0.2), Enum.Font.GothamBold)
    K.desc = text(c, "", UDim2.new(1, -56, 0, 40), UDim2.fromOffset(28, 132), 13, MUTE, Enum.Font.GothamMedium)
    K.desc.TextWrapped = true
    K.desc.TextYAlignment = Enum.TextYAlignment.Top
    line(c, UDim2.fromOffset(28, 188), W - 56)
    K.gear = {}
    for k = 1, 3 do
      local y = 202 + (k - 1) * 34
      local a = text(c, "", UDim2.new(0.5, -28, 0, 20), UDim2.fromOffset(28, y), 12, MUTE, Enum.Font.GothamMedium)
      local b = text(c, "", UDim2.new(0.5, -28, 0, 20), UDim2.new(0.5, 0, 0, y), 15, TEXT, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Right)
      K.gear[k] = { a, b }
    end
    line(c, UDim2.fromOffset(28, 310), W - 56)
    K.players = text(c, "", UDim2.new(0.5, -28, 0, 20), UDim2.fromOffset(28, 326), 13, TEXT, Enum.Font.GothamBold)
    local barBg = frame(c, UDim2.new(0.5, -28, 0, 4), UDim2.new(0.5, 0, 0, 334), RGB(255, 255, 255), 0.9)
    K.bar = frame(barBg, UDim2.fromScale(0.5, 1), nil, COL[side], 0)
    local btn = Instance.new("TextButton")
    btn.Name = "Join"
    btn.Size, btn.Position = UDim2.new(1, -56, 0, 50), UDim2.new(0, 28, 1, -78)
    btn.BorderSizePixel = 0
    btn.Font, btn.TextSize = Enum.Font.GothamBlack, 17
    btn.AutoButtonColor = true
    btn.Parent = c
    K.btn = btn
    btn.Activated:Connect(function()
      local S = G.S
      if not S or S.alive then return end
      local ok = S.canDef
      if side == "atk" then ok = S.canAtk end   -- 不写成 a and b or c：b 是 false 时会拿到 c
      if not ok and S.team ~= side then
        if G.toast then G.toast(T("ui.teamFull"), "bad") end
        return
      end
      G.R.Act:FireServer("pickTeam", side)
      G.factionOpen = false   -- 服务器定下来（S.picked）就不再显示
    end)
    K.c, K.stroke = c, cs
    cards[side] = K
  end
  local foot = text(content, "", UDim2.new(0, 600, 0, 18), UDim2.new(0.5, 0, 1, -40), 13, MUTE, Enum.Font.GothamMedium, Vector2.new(0.5, 0), Enum.TextXAlignment.Center)

  local function fmt(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
  end
  -- 每次收到战况刷新；进服还没定阵营、或者点了「换阵营」时显示（出生了就藏起来）
  function G.refreshFaction(S)
    if not S then return end
    local show = (not S.alive) and ((not S.picked) or G.factionOpen == true) and (S.progress or 1) >= 1
      and not (G.menuShown and G.menuShown())   -- 主菜单开着：等点了「进入战斗」
    gui.Enabled = show
    if not show then return end
    head.Text = T("faction.title")
    sub.Text = T("faction.sub")
    langBtn.Text = T("ui.lang")
    local total = math.max(1, (S.rAtk or 0) + (S.rDef or 0))
    for side, K in pairs(cards) do
      K.en.Text = T("faction." .. side .. ".en")
      K.name.Text = T("faction." .. side .. ".name")
      K.role.Text = T("faction." .. side .. ".role")
      K.desc.Text = T("faction." .. side .. ".desc")
      for k, g in ipairs(GEAR[side]) do
        K.gear[k][1].Text = T("vcat." .. g[1])
        K.gear[k][2].Text = T("veh." .. g[2])
      end
      local n = (side == "atk") and (S.rAtk or 0) or (S.rDef or 0)
      K.players.Text = T("faction.players", n)
      K.bar.Size = UDim2.fromScale(n / total, 1)
      local ok = S.canDef
      if side == "atk" then ok = S.canAtk end
      local mine = S.picked and S.team == side
      if mine then
        K.btn.Text, K.btn.BackgroundColor3, K.btn.TextColor3 = T("faction.stay"), RGB(255, 255, 255), RGB(10, 10, 12)
      elseif ok then
        K.btn.Text, K.btn.BackgroundColor3, K.btn.TextColor3 = T("faction.join"), RGB(255, 255, 255), RGB(10, 10, 12)
      else
        K.btn.Text, K.btn.BackgroundColor3, K.btn.TextColor3 = T("faction.full"), RGB(34, 36, 40), RGB(120, 124, 130)
      end
      K.stroke.Transparency = mine and 0.5 or 0.9
      K.stroke.Color = mine and COL[side] or LINE
    end
    if S.phase == "prep" then foot.Text = T("faction.round", S.round or 1) .. "   ·   " .. T("ui.prep", S.left)
    else foot.Text = T("faction.round", S.round or 1) .. "   ·   " .. T("ui.timeLeft") .. " " .. fmt(S.left) end
  end
  -- 部署界面的「换阵营」
  function G.showFaction()
    G.factionOpen = true
    if G.refreshFaction then G.refreshFaction(G.S) end
  end
end

return Faction
