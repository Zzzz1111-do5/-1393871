-- Roblox全面大战场（客户端）——战雷式对局的界面（用户 11-24 夜「把整个游戏做成战雷」③：对局玩法）
--   服务器 WtMatch.lua 推的 S.wt：{ sp, free 第一辆免费还在, paid 花 SP 出过几辆, order 阵容（先后）, ln 每型出过几次, lost 每型被毁几次, max, backup, earned, vk, ak }
--   · SP：比分条下面一块「SP 350 · 出击阵容 2 / 5」（部署界面、步行时；开车开飞机时收起，那时是战雷的车辆界面），攒了 SP 下面飘「+100 SP」
--   · 选车（Depot.lua 的召唤列表）：每张卡写这辆现在要多少 SP（免费 / 够了金黄 / 不够红），阵容满了、备用用完了写出来；标题行带上 SP
--   · 结算（一局打完、不是 PvE）：战雷那样——中间一条大字「任务完成 / 任务失败」，下面我方 / 敌方两张表（名次、名字、得分、击毁、击落、击杀、
--     占点、阵亡，自己那行高亮），最下面这一局的得分、经验、攒的 SP、下一局倒计时；原来的结算卡（UI.lua）收起
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WtBattle = {}

function WtBattle.init(G)
  local Config = require(RS:WaitForChild("Config"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local V2, UD2 = Vector2.new, UDim2.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MED, BLACK = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.GothamBlack
  local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local WHITE, MUTE, INK = TH.C.TEXT, TH.C.MUTE, TH.C.INK
  local GOOD, BAD, GOLD = TH.C.GOOD, TH.C.BAD, TH.C.WARN

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtBattle"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 12   -- 盖在部署界面上面（结算页要盖住一切）
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or INK, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 13, color or WHITE, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.6, INK
    l.Parent = parent
    return l
  end
  local function hex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local function teamColor(t)
    -- 队伍的颜色按看的人算：自己这一边绿、对面红、中立灰（统一外观 docs/style.md，不再攻方一律红、守方一律绿）
    if t ~= "atk" and t ~= "def" then return TH.C.NEUTRAL end
    return TH.side(t)
  end

  ---------------------------------------------------------------- SP 那一块
  local chip = frame(gui, UD2(0, 260, 0, 26), UD2(0.5, 0, 0, 80), RGB(8, 12, 14), 0.32, V2(0.5, 0))
  chip.Name = "WtSp"
  chip.Visible = false
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = chip
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = GOLD, 1, 0.7
    s.Parent = chip
  end
  local chipT = label(chip, "", UD2(1, -16, 1, 0), UD2(0, 8, 0, 0), 13, WHITE, BOLD)
  chipT.RichText = true
  local gainT = label(gui, "", UD2(0, 160, 0, 18), UD2(0.5, 0, 0, 110), 15, GOLD, BLACK, V2(0.5, 0))
  gainT.Name = "WtSpGain"
  gainT.Visible = false
  local lastSp, gainUntil, gainSum = nil, 0, 0

  local function catOf(id)
    local d = AD.get(id)
    if d then return d.cat end
    d = VD.get(id)
    return d and d.cat or "ship"
  end
  -- 这一型现在的状态：字、颜色
  local function tagOf(id, cat, w, S)
    local n = (w.ln and w.ln[id]) or 0
    if n == 0 and #(w.order or {}) >= (w.max or 5) then return T("wtm.full"), MUTE end
    if n >= 1 + (w.backup or 1) then return T("wtm.used"), BAD end
    local c = 0
    if S.phase == "battle" and not w.free then c = Config.WtCost(id, cat or catOf(id), w.paid or 0) end
    local txt, col
    if c == 0 then txt, col = T("wtm.free"), GOOD
    else txt, col = T("wtm.cost", c), (c <= (w.sp or 0)) and GOLD or BAD end
    if n >= 1 then txt ..= " · " .. T("wtm.backup") end   -- 已经出过一次：这次是备用
    return txt, col
  end
  G.wtTagOf = function(id, cat) local S = G.S return (S and S.wt) and tagOf(id, cat, S.wt, S) or nil end   -- 测试用
  -- Depot.lua 的召唤卡片：y 是这张卡上放这行字的高度（跟左边那行「类别、名额」并排，靠右）
  function G.wtCardTag(b, id, cat, y)
    local S = G.S
    local w = S and S.wt
    if not w then return end
    local txt, col = tagOf(id, cat, w, S)
    local l = label(b, txt, UD2(0, 120, 0, 16), UD2(1, -10, 0, y or 74), 12, col, BLACK, V2(1, 0), RIGHT)
    l.Name = "WtSpTag"
  end
  function G.wtSpLine()
    local S = G.S
    local w = S and S.wt
    if not w then return nil end
    return T("wtm.sp", w.sp or 0) .. "  ·  " .. T("wtm.lineup", #(w.order or {}), w.max or 5)
  end

  ---------------------------------------------------------------- 出击栏（战雷：阵亡以后在出击界面直接选车，人在车里出生）
  --   部署界面下面一条：本队能开的地面车一排、飞机直升机一排，每张卡写名字、这辆现在要多少 SP（免费 / 够了 / 不够 / 阵容满了 / 备用用完）；
  --   点一张 → 服务器 WtMatch.lua G.ACT.wtDeployVeh（在主基地出生、出车、坐进去）；装备照部署界面左下选的
  local strip = Instance.new("ScrollingFrame")
  strip.Name = "WtLineup"
  strip.Size, strip.Position, strip.AnchorPoint = UD2(0.62, 0, 0, 76), UD2(0.5, 0, 1, -104), V2(0.5, 1)
  strip.BackgroundColor3, strip.BackgroundTransparency, strip.BorderSizePixel = RGB(8, 12, 14), 0.35, 0
  strip.ScrollingDirection = Enum.ScrollingDirection.X
  strip.ScrollBarThickness = 4
  strip.CanvasSize = UD2(0, 0, 0, 0)
  strip.AutomaticCanvasSize = Enum.AutomaticSize.X
  strip.Visible = false
  strip.Parent = gui
  do
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 6)
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = strip
    local pd = Instance.new("UIPadding")
    pd.PaddingLeft, pd.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
    pd.Parent = strip
  end
  local stripTitle = label(gui, "", UD2(0.62, 0, 0, 18), UD2(0.5, 0, 1, -182), 13, GOLD, BOLD, V2(0.5, 1), LEFT)
  stripTitle.Visible = false
  local cards, cardKey = {}, nil
  local function buildCards(S)
    local team = S.team or "atk"
    local key = team .. ":" .. tostring(#(S.wt and S.wt.order or {}))
    if key == cardKey and #cards > 0 then return end
    cardKey = key
    for _, c in ipairs(cards) do c.b:Destroy() end
    cards = {}
    local ids = {}
    for _, cat in ipairs({ "tank", "apc", "aa", "arty", "jet", "heli" }) do
      for _, id in ipairs(Config.TeamVehicles(team, cat)) do table.insert(ids, { id = id, cat = cat }) end
    end
    for i, it in ipairs(ids) do
      local b = Instance.new("TextButton")
      b.Name = "Deploy_" .. it.id
      b.Text = ""
      b.LayoutOrder = i
      b.Size = UD2(0, 132, 0, 60)
      b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = RGB(22, 26, 30), 0.1, 0
      b.AutoButtonColor = true
      b.Parent = strip
      local st = Instance.new("UIStroke")
      st.Color, st.Transparency, st.Thickness = WHITE, 0.85, 1
      st.Parent = b
      local nm = string.match(T("veh." .. it.id), "^(%S+)") or T("veh." .. it.id)
      label(b, nm, UD2(1, -10, 0, 20), UD2(0, 6, 0, 5), 14, WHITE, BLACK, nil, LEFT)
      label(b, T("vcat." .. it.cat), UD2(1, -10, 0, 14), UD2(0, 6, 0, 24), 11, MUTE, MED, nil, LEFT)
      local tag = label(b, "", UD2(1, -10, 0, 16), UD2(0, 6, 1, -20), 12, GOLD, BLACK, nil, LEFT)
      b.Activated:Connect(function()
        local sel = G.deploySel
        G.R.Act:FireServer("wtDeployVeh", it.id, sel and sel.kit or nil)
      end)
      table.insert(cards, { b = b, tag = tag, id = it.id, cat = it.cat, st = st })
    end
  end
  local function stepStrip(S)
    local dying = G.deathFxOn ~= nil and G.deathFxOn() == true
    -- 机库开着（D 的 TechUI：Config.Wt.noInfantry，玩家不当步兵）就是它管出击——这条出击栏只在还能当步兵的时候出来
    local hangar = G.hangarActive ~= nil and G.hangarActive() == true
    local show = S.wt ~= nil and S.alive == false and (S.phase == "battle" or S.phase == "prep") and not dying and not hangar
      and not (G.menuShown and G.menuShown()) and not G.factionOpen and S.picked ~= false
    strip.Visible, stripTitle.Visible = show, show
    if not show then return end
    buildCards(S)
    stripTitle.Text = T("wtm.lineupTitle") .. "   ·   " .. (G.wtSpLine() or "")
    for _, c in ipairs(cards) do
      local txt, col = tagOf(c.id, c.cat, S.wt, S)
      c.tag.Text, c.tag.TextColor3 = txt, col
      local inLine = (S.wt.ln and S.wt.ln[c.id] or 0) > 0
      c.st.Color, c.st.Transparency = inLine and GOLD or WHITE, inLine and 0.2 or 0.85
    end
  end

  ---------------------------------------------------------------- 结算页
  local res = frame(gui, UD2(1, 0, 1, 0), nil, RGB(4, 6, 8), 0.22)
  res.Name = "WtResults"
  res.Visible = false
  local resScale = Instance.new("UIScale")
  resScale.Parent = res
  local ban = frame(res, UD2(1, 0, 0, 104), UD2(0, 0, 0, 64), INK, 0.3)
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2),
      NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = ban
  end
  local banLine = frame(ban, UD2(0.5, 0, 0, 2), UD2(0.5, 0, 1, -2), GOLD, 0, V2(0.5, 0))
  local banT = label(ban, "", UD2(1, 0, 0, 56), UD2(0, 0, 0, 8), 46, WHITE, BLACK)
  banT.Name = "Title"
  local banS = label(ban, "", UD2(1, 0, 0, 20), UD2(0, 0, 0, 68), 15, MUTE, MED)
  local COLS = { { "#", 26 }, { "wtm.cName", 150 }, { "wtm.cScore", 58 }, { "wtm.cVk", 48 }, { "wtm.cAk", 48 }, { "wtm.cK", 48 }, { "wtm.cC", 48 }, { "wtm.cD", 48 } }
  local TW = 0
  for _, c in ipairs(COLS) do TW += c[2] end
  local NROW = 10
  local function makeTable(x)
    local o = { root = frame(res, UD2(0, TW + 16, 0, 34 + NROW * 24 + 8), UD2(0.5, x, 0, 196), RGB(10, 14, 16), 0.3, V2(0.5, 0)), rows = {} }
    o.title = label(o.root, "", UD2(1, -16, 0, 22), UD2(0, 8, 0, 4), 15, WHITE, BLACK, nil, LEFT)
    o.bar = frame(o.root, UD2(1, 0, 0, 2), UD2(0, 0, 0, 0), WHITE, 0)
    local hx = 8
    for _, c in ipairs(COLS) do
      label(o.root, (c[1] == "#") and "#" or T(c[1]), UD2(0, c[2], 0, 14), UD2(0, hx, 0, 28), 11, MUTE, MED, nil, (c[2] >= 100) and LEFT or Enum.TextXAlignment.Center)
      hx += c[2]
    end
    for i = 1, NROW do
      local r = { f = frame(o.root, UD2(1, -8, 0, 22), UD2(0, 4, 0, 34 + 10 + (i - 1) * 24), WHITE, 1), c = {} }
      local cx = 4
      for j, c in ipairs(COLS) do
        r.c[j] = label(r.f, "", UD2(0, c[2], 1, 0), UD2(0, cx, 0, 0), (j == 2) and 13 or 13, WHITE, (j == 2) and MED or BOLD, nil, (c[2] >= 100) and LEFT or Enum.TextXAlignment.Center)
        if j == 2 then r.c[j].TextTruncate = Enum.TextTruncate.AtEnd end
        cx += c[2]
      end
      o.rows[i] = r
    end
    return o
  end
  local GAPX = (TW + 16) / 2 + 12
  local tA, tB = makeTable(-GAPX), makeTable(GAPX)
  local rewards = label(res, "", UD2(0, 900, 0, 22), UD2(0.5, 0, 0, 196 + 34 + NROW * 24 + 28), 16, GOLD, BOLD, V2(0.5, 0))
  -- 科技树的明细（TechUI.lua G.treeResultText）：研究点、记在哪辆上、改装、乘员经验
  local treeT = label(res, "", UD2(0, 1100, 0, 36), UD2(0.5, 0, 0, 196 + 34 + NROW * 24 + 54), 13, GOLD, MED, V2(0.5, 0))
  treeT.Name = "TreeResult"
  treeT.TextWrapped = true
  local nextT = label(res, "", UD2(0, 600, 0, 18), UD2(0.5, 0, 0, 196 + 34 + NROW * 24 + 96), 13, MUTE, MED, V2(0.5, 0))

  local board = {}
  local baseBoard = G.onBoard
  G.onBoard = function(d)
    board = (type(d) == "table") and d or board
    if baseBoard then return baseBoard(d) end
  end
  local function fill(o, team, list, myName)
    local c = teamColor(team)
    o.bar.BackgroundColor3 = c
    o.title.Text = T("hud." .. team)
    o.title.TextColor3 = c:Lerp(WHITE, 0.3)
    local rows = {}
    for _, r in ipairs(list) do if r.t == team then table.insert(rows, r) end end
    table.sort(rows, function(a, b) return (a.s or 0) > (b.s or 0) end)
    for i, R in ipairs(o.rows) do
      local r = rows[i]
      R.f.Visible = r ~= nil
      if r then
        local mine = r.id == me.UserId or (r.id == nil and r.n == myName)
        R.f.BackgroundTransparency = mine and 0.82 or ((i % 2 == 0) and 0.95 or 1)
        local vals = { tostring(i), r.n or "?", tostring(r.s or 0), tostring(r.vk or 0), tostring(r.ak or 0), tostring(r.k or 0), tostring(r.c or 0), tostring(r.d or 0) }
        for j, l in ipairs(R.c) do
          l.Text = vals[j]
          l.TextColor3 = mine and GOLD or ((j == 2) and WHITE or MUTE:Lerp(WHITE, 0.4))
        end
      end
    end
  end
  G.wtResultsOn = function()   -- UI.lua 原来的结算卡看这个收起
    local S = G.S
    return S ~= nil and S.phase == "end" and not S.pve and S.wt ~= nil
  end
  local function stepResults(S)
    local on = G.wtResultsOn()
    res.Visible = on
    if not on then return end
    local vp = cam.ViewportSize
    resScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.2)
    local won = S.winner == S.team
    banT.Text = T(won and "wtm.win" or "wtm.lose")
    banT.TextColor3 = won and RGB(236, 240, 236) or RGB(240, 120, 104)
    banLine.BackgroundColor3 = won and GOLD or BAD
    banS.Text = T((S.winner == "atk") and "ui.win.atk" or "ui.win.def") .. (S.mvp and ("   ·   MVP  " .. S.mvp) or "")
    local mine = S.team or "atk"
    fill(tA, mine, board, me.DisplayName)
    fill(tB, (mine == "atk") and "def" or "atk", board, me.DisplayName)
    local m, w = S.me or {}, S.wt or {}
    rewards.Text = T("wtm.rewards", m.s or 0, m.gain or 0, w.earned or 0, w.vk or 0, w.ak or 0)
    treeT.Text = G.treeResultText and G.treeResultText() or ""
    nextT.Text = T("ui.nextRound", S.left or 0)
  end

  ---------------------------------------------------------------- 击杀信息（战雷左边那一栏）：「玩家A [豹 2A6] 击毁 玩家B [T-72B3]」
  --   服务器 WtMatch.lua 车被打掉时发 { op = "wtFeed", k 打的人, kt 他那队, kv 他开的车, v 车里的人, vt 那队, vv 那辆车, air 打下来的是飞机, why 殉爆 / 起火 }；
  --   我方蓝、敌方红；最多 7 行，8 秒后淡掉；自己相关的那行底色亮一点
  local FEED_N = 7
  local feedBox = frame(gui, UD2(0, 460, 0, FEED_N * 22), UD2(0, 16, 0.36, 0), INK, 1)
  feedBox.Name = "WtKillFeed"
  local feedRows, feedList = {}, {}
  for i = 1, FEED_N do
    local r = frame(feedBox, UD2(1, 0, 0, 20), UD2(0, 0, 0, (i - 1) * 22), INK, 0.6)
    local l = label(r, "", UD2(1, -12, 1, 0), UD2(0, 6, 0, 0), 13, WHITE, BOLD, nil, LEFT)
    l.RichText = true
    r.Visible = false
    feedRows[i] = { f = r, l = l }
  end
  local BLUE, RED = TH.C.FRIEND, TH.C.FOE   -- 自己这边绿、对面红（统一外观，不用蓝）
  local function vehName(id, tk)   -- tk：科技树的键（科技树出的车写科技树里的名字）
    if tk then
      local nm = T("tree." .. tk)
      if nm ~= "tree." .. tk then return nm end
    end
    return id and (string.match(T("veh." .. id), "^(%S+)") or T("veh." .. id)) or nil
  end
  local function feedLine(m)
    local side = me:GetAttribute("Side")
    local function who(name, team, veh, tk)
      local col = (team == side) and BLUE or RED
      local nm = name or T("wtm.ai")
      local v = vehName(veh, tk)
      return string.format('<font color="%s">%s</font>%s', hex(col), nm, v and string.format(' <font color="#C8CDD0">[%s]</font>', v) or "")
    end
    local verb = T(m.air and "wtm.shotDown" or ((m.why == "ammo") and "wtm.ammoRack" or ((m.why == "fire") and "wtm.burned" or "wtm.destroyed")))
    if not m.k then return who(m.v, m.vt, m.vv, m.vk) .. "  " .. verb end
    return who(m.k, m.kt, m.kv, m.kk) .. "  " .. verb .. "  " .. who(m.v, m.vt, m.vv, m.vk)
  end
  local function redrawFeed()
    local t = os.clock()
    for i = #feedList, 1, -1 do if t - feedList[i].t > 9 then table.remove(feedList, i) end end
    for i, R in ipairs(feedRows) do
      local e = feedList[i]
      R.f.Visible = e ~= nil
      if e then
        R.l.Text = e.txt
        local a = math.clamp((t - e.t - 7.5) / 1.5, 0, 1)
        R.l.TextTransparency = a
        R.f.BackgroundTransparency = (e.mine and 0.35 or 0.6) + a * 0.4
      end
    end
  end
  -- 火炮支援的落点：地上一圈红（本队看得见；敌人只看得见炮弹落下来）
  local artyMarks = {}
  local function artyMark(e)
    if typeof(e.p) ~= "Vector3" or e.team ~= me:GetAttribute("Side") then return end
    local p = Instance.new("Part")
    p.Name = "WtArtyMark"
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Shape = Enum.PartType.Cylinder
    p.Size = Vector3.new(0.3, (e.r or 70) * 2, (e.r or 70) * 2)
    p.CFrame = CFrame.new(e.p + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
    p.Material, p.Color, p.Transparency = Enum.Material.Neon, RGB(255, 70, 50), 0.82
    p.Parent = workspace
    table.insert(artyMarks, { p = p, till = os.clock() + (e.t or 10) })
  end
  G.R.Fx.OnClientEvent:Connect(function(list)
    if type(list) ~= "table" then return end
    for _, e in ipairs(list) do
      if type(e) == "table" and e.k == "artyMark" then G.try_(artyMark, e) end
    end
  end)
  -- 战场奖章：屏幕上方一条——左边一道琥珀细条 + 名字 + 加了多少分，几个一起来就排队
  --   （统一外观 docs/style.md：不再画金色圆章、星星、22 号金字；用户 11-25「四不像」）
  local award = frame(gui, UD2(0, 260, 0, 44), UD2(0.5, 0, 0, 150), TH.C.PANEL, TH.A.panel, V2(0.5, 0))
  award.Name = "WtAward"
  award.Visible = false
  frame(award, UD2(0, 3, 1, 0), UD2(0, 0, 0, 0), GOLD, 0)
  local awName = label(award, "", UD2(1, -18, 0, 22), UD2(0, 14, 0, 3), 16, WHITE, BOLD, nil, LEFT)
  local awPts = label(award, "", UD2(1, -18, 0, 16), UD2(0, 14, 0, 24), 13, GOLD, TH.F.mono, nil, LEFT)
  local awQueue, awUntil = {}, 0
  local function nextAward()
    local a = table.remove(awQueue, 1)
    if not a then award.Visible = false return end
    awName.Text = T("wta.aw." .. a.a)
    awPts.Text = T("wtm.awardPts", a.pts or 0)
    award.Visible = true
    awUntil = os.clock() + 2.6
    if G.sfx then pcall(G.sfx, "uiClick") end
  end
  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) == "table" and m.op == "wtAward" then
      table.insert(awQueue, m)
      if not award.Visible then nextAward() end
    end
  end)
  G.frameConn("WtAward", function()
    if award.Visible then
      local t = os.clock()
      local k = math.clamp(1 - (awUntil - t) / 0.25, 0, 1)   -- 刚出来的 0.25 秒：从大缩到正常
      local pop = 1 - math.clamp((t - (awUntil - 2.6)) / 0.25, 0, 1)
      award.Size = UD2(0, 260 * (1 + 0.06 * pop), 0, 44 * (1 + 0.06 * pop))
      if t > awUntil then nextAward() end
      local _ = k
    end
  end)
  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or m.op ~= "wtFeed" then return end
    table.insert(feedList, 1, { txt = feedLine(m), t = os.clock(), mine = m.vid == me.UserId or m.k == me.DisplayName })
    while #feedList > FEED_N do table.remove(feedList) end
    redrawFeed()
  end)
  G.wtFeedRows = function() return feedList end   -- 测试用

  ---------------------------------------------------------------- 每帧
  G.frameConn("WtBattle", function()
    if #feedList > 0 then G.try_(redrawFeed) end
    for i = #artyMarks, 1, -1 do
      local a = artyMarks[i]
      if os.clock() > a.till then a.p:Destroy() table.remove(artyMarks, i) end
    end
    local S = G.S
    local w = S and S.wt
    if S then G.try_(stepResults, S) G.try_(stepStrip, S) end
    local covered = (G.menuShown and G.menuShown()) or (G.boardShown and G.boardShown()) or G.factionOpen
    local driving = G.drive ~= nil or G.myVeh ~= nil
    local show = w ~= nil and not covered and not driving and (S.phase == "battle" or S.phase == "prep") and S.picked ~= false
    chip.Visible = show
    local t = os.clock()
    if w then
      if lastSp and (w.sp or 0) > lastSp then   -- 攒了 SP：下面飘一下
        gainSum = ((t < gainUntil) and gainSum or 0) + (w.sp - lastSp)
        gainUntil = t + 1.8
      end
      lastSp = w.sp or 0
    else
      lastSp = nil
    end
    if show then
      local y = ((G.hudLayout and G.hudLayout.scoreBottom) or 64) + 8
      chip.Position = UD2(0.5, 0, 0, y)
      local free = w.free and S.phase == "battle"
      chipT.Text = string.format('<font color="%s">%s</font>   ·   %s%s', hex(GOLD), T("wtm.sp", w.sp or 0), T("wtm.lineup", #(w.order or {}), w.max or 5),
        free and ("   ·   " .. T("wtm.firstFree")) or "")
      local okB, tw = pcall(function() return chipT.TextBounds.X end)   -- 测试用的模拟器里没有 TextBounds：按字数估
      if not okB then tw = (utf8.len((string.gsub(chipT.Text, "<[^>]+>", ""))) or 30) * 8 end
      chip.Size = UD2(0, math.clamp(tw + 24, 200, 460), 0, 26)
      gainT.Position = UD2(0.5, 0, 0, y + 30)
    end
    gainT.Visible = show and t < gainUntil
    if gainT.Visible then
      gainT.Text = T("wtm.gain", math.floor(gainSum + 0.5))
      gainT.TextTransparency = math.clamp((t - (gainUntil - 0.5)) / 0.5, 0, 1)
    end
  end)
end

return WtBattle
