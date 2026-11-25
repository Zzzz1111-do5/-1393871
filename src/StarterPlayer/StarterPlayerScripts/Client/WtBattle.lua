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
  local WHITE, MUTE, INK = RGB(238, 242, 244), RGB(170, 176, 182), RGB(0, 0, 0)
  local GOOD, BAD, GOLD = RGB(120, 230, 120), RGB(255, 96, 80), RGB(255, 206, 96)

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
    local T0 = Config.Teams and Config.Teams[t or "atk"]
    return T0 and T0.color or RGB(200, 200, 200)
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

  ---------------------------------------------------------------- 每帧
  G.frameConn("WtBattle", function()
    local S = G.S
    local w = S and S.wt
    if S then G.try_(stepResults, S) end
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
