-- 全面大战场（客户端）——机库（出击阵容、出击）和科技树界面（用户 11-25：「从1960到现代的战机和坦克 科技树」「再去做一个中 德 美 日 俄系」
--   「不要让玩家拿枪之类的了 就跟战雷完全一样」）
--   机库：没出击的时候（Config.Wt.noInfantry 开着）盖住原来的步兵部署页——上面选系（中 德 美 日 俄）、开科技树，底下一排出击阵容（最多 5 辆），
--     每张卡点「出击」直接坐在车里 / 飞机里出现在自己基地（服务器 Tech.lua deployVeh）
--   科技树：一棵树一张格子——每级一行（I～VII，左边写年代），每类一列，同一列上下连线；格子的颜色：买下的绿、研究完没买的蓝、正在研究的黄（带进度条）、
--     能研究的灰、还没开的暗；点一格右边出详情：年份、战斗等级、研究点、价钱，「研究」「购买」「放进出击阵容」；暂借别的型号的写「暂用 某某」
--   存档在服务器（玩家属性 Tree，JSON）；动作发 Act：treeNat / treeResearch / treeBuy / treeLineup / deployVeh
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local TechUI = {}

function TechUI.init(G)
  local me = Players.LocalPlayer
  local TT = require(RS:WaitForChild("TechTree"))
  local Config = G.Config
  local VD = require(RS:WaitForChild("VehDefs"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local zh = G.lang == "zh"
  local function L(a, b) return zh and a or b end
  local function nm(it) return zh and it.name or it.en end
  local RGB = Color3.fromRGB
  local WHITE, DIM, FAINT = Color3.new(1, 1, 1), RGB(150, 156, 160), RGB(96, 102, 106)
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local tree = { res = {}, own = {}, rp = {}, cur = {}, lineup = {}, nat = "cn", free = {} }
  local function readTree()
    local s = me:GetAttribute("Tree")
    if type(s) ~= "string" then return end
    local ok, t = pcall(function() return Http:JSONDecode(s) end)
    if ok and type(t) == "table" then
      for _, f in ipairs({ "res", "own", "rp", "cur", "lineup", "free" }) do t[f] = (type(t[f]) == "table") and t[f] or {} end
      if not TT.NAT[t.nat] then t.nat = "cn" end
      tree = t
    end
  end
  readTree()
  G.treeState = function() return tree end   -- 测试用
  local function act(...)
    local args = table.pack(...)
    pcall(function() G.R.Act:FireServer(table.unpack(args, 1, args.n)) end)
  end
  local noInf = (Config.Wt or {}).noInfantry == true
  G.hangarActive = function() return noInf and not G.forceInfantry end

  -- 这一系现在的出击阵容（服务器没给就按白送的那几辆）
  local function lineupOf(nat)
    local L0 = tree.lineup[nat]
    if type(L0) == "table" and #L0 > 0 then return L0 end
    local out = {}
    for _, br in ipairs(TT.BRANCHES) do
      for _, it in ipairs(TT.list[nat][br]) do if it.free and #out < 5 then table.insert(out, it.key) end end
    end
    return out
  end
  local function defOf(it) return VD.get(it.play) or AD.get(it.play) end

  ---------------------------------------------------------------- 小零件
  local gui = Instance.new("ScreenGui")
  gui.Name = "TechHangar"   -- 别叫 Hangar：改挂载的编辑器（Hangar.lua）已经用了这个名字
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 12
  gui.Parent = me:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, col, tr)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or RGB(10, 12, 14), tr or 0, 0
    f.Parent = parent
    return f
  end
  local function text(parent, str, size, pos, ts, col, align)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size, t.Position = size, pos or UDim2.new()
    t.Font = Enum.Font.GothamMedium
    t.TextSize = ts or 14
    t.TextColor3 = col or WHITE
    t.TextXAlignment = align or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Text = str
    t.Parent = parent
    return t
  end
  local function button(parent, str, size, pos, primary)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UDim2.new()
    b.BackgroundColor3 = primary and WHITE or RGB(30, 34, 38)
    b.BackgroundTransparency = primary and 0 or 0.15
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = primary and RGB(10, 10, 10) or WHITE
    b.Text = str
    b.Parent = parent
    local s = Instance.new("UIStroke")
    s.Color, s.Transparency, s.Thickness = RGB(120, 126, 130), primary and 1 or 0.5, 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = b
    return b
  end
  local function clear(f) for _, c in ipairs(f:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end

  ---------------------------------------------------------------- 机库
  local hangar = frame(gui, UDim2.fromScale(1, 1), nil, RGB(4, 6, 8), 0.12)
  hangar.Name = "Hangar"
  hangar.Visible = false
  local M0 = mobile and 16 or 40
  local title = text(hangar, L("机库", "HANGAR"), UDim2.new(0, 300, 0, 34), UDim2.new(0, M0, 0, 20), 26)
  title.Font = Enum.Font.GothamBold
  local phaseT = text(hangar, "", UDim2.new(0, 360, 0, 20), UDim2.new(0, M0, 0, 56), 14, DIM)
  local natBar = frame(hangar, UDim2.new(1, -2 * M0, 0, 34), UDim2.new(0, M0, 0, 86), nil, 1)
  local natLayout = Instance.new("UIListLayout")
  natLayout.FillDirection = Enum.FillDirection.Horizontal
  natLayout.Padding = UDim.new(0, 6)
  natLayout.Parent = natBar
  local treeBtn = button(hangar, L("科技树", "Tech tree"), UDim2.new(0, 140, 0, 34), UDim2.new(1, -M0 - 140, 0, 86))
  local brT = text(hangar, "", UDim2.new(0, 500, 0, 24), UDim2.new(0, M0, 1, -230), 16, WHITE)
  local row = frame(hangar, UDim2.new(1, -2 * M0, 0, 150), UDim2.new(0, M0, 1, -196), nil, 1)
  local rowLayout = Instance.new("UIListLayout")
  rowLayout.FillDirection = Enum.FillDirection.Horizontal
  rowLayout.Padding = UDim.new(0, 10)
  rowLayout.Parent = row
  local hint = text(hangar, L("选一辆出击：直接坐在车里 / 飞机里出现在自己基地。车没了回到这里。", "Pick a vehicle: you spawn inside it at your base. Lose it and you come back here."),
    UDim2.new(1, -2 * M0, 0, 20), UDim2.new(0, M0, 1, -40), 13, FAINT)
  G.hangarGui = hangar   -- 测试用

  local openTree   -- 下面定义
  local function natTabs(bar, onPick)
    clear(bar)
    for _, nat in ipairs(TT.NATIONS) do
      local N = TT.NAT[nat]
      local b = button(bar, zh and N.name or N.en, UDim2.new(0, mobile and 64 or 92, 1, 0), nil, nat == tree.nat)
      b.Name = "Nat_" .. nat
      local stripe = frame(b, UDim2.new(1, 0, 0, 3), UDim2.new(0, 0, 1, -3), N.col, 0)
      stripe.Name = "Stripe"
      b.MouseButton1Click:Connect(function() onPick(nat) end)
    end
  end
  local function spCost(it)
    local d = defOf(it)
    if not d or not Config.WtCost then return nil end
    local ok, c = pcall(Config.WtCost, it.play, d.cat or (it.branch == "air" and "jet" or "tank"), 0)
    return ok and c or nil
  end
  local function refreshHangar()
    natTabs(natBar, function(nat) tree.nat = nat act("treeNat", nat) refreshHangar() end)
    clear(row)
    local keys = lineupOf(tree.nat)
    for i = 1, 5 do
      local key = keys[i]
      local it = key and TT.get(key)
      local card = frame(row, UDim2.new(0, mobile and 150 or 190, 1, 0), nil, RGB(14, 16, 19), 0.1)
      card.Name = it and ("Line_" .. key) or ("Empty_" .. i)
      local st = Instance.new("UIStroke")
      st.Color, st.Transparency = RGB(90, 96, 100), 0.4
      st.Parent = card
      if it then
        text(card, nm(it), UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 8), 15)
        text(card, (it.branch == "air" and L("战机", "Aircraft") or L("地面", "Ground")) .. " · " .. TT.RANKS[it.rank].roman .. " · BR " .. TT.brText(it.br),
          UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 32), 12, DIM)
        local sp = spCost(it)
        if sp then text(card, "SP " .. sp, UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 52), 12, FAINT) end
        if it.stand then   -- 还没有自己的模型：借的是哪一型写在科技树详情里
          text(card, L("暂用模型", "stand-in model"), UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 70), 11, RGB(200, 170, 90))
        end
        local go = button(card, L("出击", "Deploy"), UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -44), true)
        go.Name = "Go"
        go.MouseButton1Click:Connect(function() act("deployVeh", key) end)
      else
        text(card, L("空位", "Empty"), UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 8), 15, FAINT)
        local add = button(card, L("从科技树里放进来", "Add from tech tree"), UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -44))
        add.MouseButton1Click:Connect(function() if openTree then openTree() end end)
      end
    end
    brT.Text = L("阵容战斗等级 ", "Lineup BR ") .. TT.brText(TT.lineupBr(keys))
  end
  G.refreshLineup = refreshHangar   -- 不叫 G.refreshHangar：Hangar.lua（改挂载）的刷新函数叫这个名字，顶掉了它就坏了
  treeBtn.MouseButton1Click:Connect(function() if openTree then openTree() end end)

  -- 原来的部署界面（UI.lua）每次刷新都问一下：该显示部署页的时候机库盖上去
  function G.hangarSet(show)
    local want = show and G.hangarActive()
    if hangar.Visible ~= want then
      hangar.Visible = want
      if want then refreshHangar() end
    end
    if want then
      local S = G.S
      if S then
        local fmt = function(s) s = math.max(0, math.floor(s or 0)) return string.format("%d:%02d", s // 60, s % 60) end
        phaseT.Text = (S.phase == "prep") and (L("准备阶段 ", "Preparing ") .. fmt(S.left)) or (L("剩余时间 ", "Time left ") .. fmt(S.left))
      end
    end
  end

  ---------------------------------------------------------------- 科技树
  local panel = frame(gui, UDim2.fromScale(1, 1), nil, RGB(6, 8, 10), 0.04)
  panel.Name = "TechTree"
  panel.Visible = false
  panel.ZIndex = 5
  G.treeGui = panel   -- 测试用
  local view = { nat = tree.nat, branch = "ground", sel = nil }
  local top = frame(panel, UDim2.new(1, 0, 0, 92), nil, RGB(10, 12, 14), 0.1)
  text(top, L("科技树", "TECH TREE"), UDim2.new(0, 200, 0, 30), UDim2.new(0, M0, 0, 8), 22).Font = Enum.Font.GothamBold
  local closeB = button(top, "×", UDim2.new(0, 40, 0, 34), UDim2.new(1, -M0 - 40, 0, 8))
  closeB.Name = "Close"
  closeB.MouseButton1Click:Connect(function() panel.Visible = false end)
  local tNat = frame(top, UDim2.new(0, 520, 0, 32), UDim2.new(0, M0, 0, 50), nil, 1)
  local tl = Instance.new("UIListLayout")
  tl.FillDirection = Enum.FillDirection.Horizontal
  tl.Padding = UDim.new(0, 6)
  tl.Parent = tNat
  local tBr = frame(top, UDim2.new(0, 220, 0, 32), UDim2.new(0, M0 + 540, 0, 50), nil, 1)
  local bl = Instance.new("UIListLayout")
  bl.FillDirection = Enum.FillDirection.Horizontal
  bl.Padding = UDim.new(0, 6)
  bl.Parent = tBr
  local freeT = text(top, "", UDim2.new(0, 300, 0, 20), UDim2.new(1, -M0 - 360, 0, 58), 13, DIM, Enum.TextXAlignment.Right)
  local scroll = Instance.new("ScrollingFrame")
  scroll.Size, scroll.Position = UDim2.new(1, -330, 1, -100), UDim2.new(0, 0, 0, 96)
  scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
  scroll.ScrollBarThickness = 6
  scroll.CanvasSize = UDim2.new()
  scroll.Parent = panel
  local detail = frame(panel, UDim2.new(0, 316, 1, -100), UDim2.new(1, -320, 0, 96), RGB(12, 14, 17), 0.05)
  detail.Name = "Detail"

  local CW, CH, GAP, LW, HH = 176, 58, 10, 92, 30   -- 格宽、格高、间距、左边等级栏宽、表头高
  local refreshTree
  local function status(it)
    if TT.owned(tree, it.key) then return "own" end
    if TT.researched(tree, it.key) then return "res" end
    if tree.cur[it.nat .. ":" .. it.branch] == it.key then return "cur" end
    if TT.canResearch(tree, it.key) then return "can" end
    return "lock"
  end
  local COL = { own = RGB(46, 86, 58), res = RGB(46, 72, 110), cur = RGB(120, 98, 34), can = RGB(44, 48, 54), lock = RGB(22, 24, 27) }
  local function showDetail(it)
    clear(detail)
    if not it then return end
    local y = 12
    local function line(str, ts, col, h)
      text(detail, str, UDim2.new(1, -24, 0, h or 20), UDim2.new(0, 12, 0, y), ts or 13, col or DIM).TextWrapped = true
      y += (h or 20) + 4
    end
    line(nm(it), 20, WHITE, 26)
    line((zh and it.en or it.name) .. " · " .. it.year, 13, DIM)
    line(L("等级 ", "Rank ") .. TT.RANKS[it.rank].roman .. "（" .. TT.RANKS[it.rank].years .. "）· " .. L("战斗等级 ", "BR ") .. TT.brText(it.br), 13, DIM)
    local stt = status(it)
    local stName = ({ own = L("已买下", "Owned"), res = L("已研究，可以买", "Researched"), cur = L("正在研究", "Researching"),
      can = L("可以研究", "Can research"), lock = L("还没开（先研究前一辆 / 上一级）", "Locked") })[stt]
    line(stName, 14, WHITE)
    if stt ~= "own" and stt ~= "res" then
      line(L("研究点 ", "RP ") .. tostring(tree.rp[it.key] or 0) .. " / " .. it.rp, 13, DIM)
    end
    if stt ~= "own" then line(L("价钱 ", "Cost ") .. it.cost .. L(" 金币", " coins"), 13, DIM) end
    if it.stand then
      local base = it.base and (VD.get(it.base) or AD.get(it.base)) and it.base or "?"
      line(L("还没有自己的模型：暂用 ", "No model yet: uses ") .. string.upper(base) .. L(" 的模型和性能", "'s model & stats"), 12, RGB(200, 170, 90), 34)
    end
    y += 8
    local function btn(str, primary, f)
      local b = button(detail, str, UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 0, y), primary)
      b.MouseButton1Click:Connect(f)
      y += 46
      return b
    end
    if stt == "can" then
      btn(L("研究这一辆", "Research"), true, function() act("treeResearch", it.key) end).Name = "Research"
    elseif stt == "res" then
      btn(L("购买（", "Buy (") .. it.cost .. ")", true, function() act("treeBuy", it.key) end).Name = "Buy"
    elseif stt == "own" then
      local L0 = table.clone(lineupOf(it.nat))
      local idx = table.find(L0, it.key)
      if idx then
        btn(L("移出出击阵容", "Remove from lineup"), false, function()
          table.remove(L0, idx)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupOut"
      elseif #L0 < 5 then
        btn(L("放进出击阵容", "Add to lineup"), true, function()
          table.insert(L0, it.key)
          act("treeLineup", it.nat, L0)
        end).Name = "LineupIn"
      else
        line(L("出击阵容满了（5 辆）：先移出一辆", "Lineup full (5)"), 12, DIM)
      end
    end
  end
  refreshTree = function()
    natTabs(tNat, function(nat) view.nat = nat view.sel = nil refreshTree() end)
    for _, c in ipairs(tNat:GetChildren()) do
      if c:IsA("TextButton") then
        local on = c.Name == "Nat_" .. view.nat
        c.BackgroundColor3 = on and WHITE or RGB(30, 34, 38)
        c.TextColor3 = on and RGB(10, 10, 10) or WHITE
      end
    end
    clear(tBr)
    for _, br in ipairs(TT.BRANCHES) do
      local B = TT.BRANCH[br]
      local b = button(tBr, zh and B.name or B.en, UDim2.new(0, 100, 1, 0), nil, br == view.branch)
      b.Name = "Br_" .. br
      b.MouseButton1Click:Connect(function() view.branch = br view.sel = nil refreshTree() end)
    end
    freeT.Text = L("自由研究点 ", "Free RP ") .. tostring(tree.free[view.nat] or 0)
    clear(scroll)
    local B = TT.BRANCH[view.branch]
    local list = TT.list[view.nat][view.branch]
    -- 每级一行：这一行的高度 = 这一级里同一列最多几辆
    local per = {}
    for _, it in ipairs(list) do
      per[it.rank] = per[it.rank] or {}
      per[it.rank][it.col] = (per[it.rank][it.col] or 0) + 1
    end
    local rowY, y = {}, HH
    for r = 1, #TT.RANKS do
      local m = 1
      for _, n in pairs(per[r] or {}) do if n > m then m = n end end
      rowY[r] = y
      local band = frame(scroll, UDim2.new(0, LW + #B.cols * (CW + GAP), 0, m * (CH + GAP)), UDim2.new(0, 0, 0, y), (r % 2 == 0) and RGB(14, 16, 18) or RGB(10, 12, 14), 0.3)
      band.ZIndex = 1
      local lab = text(band, TT.RANKS[r].roman, UDim2.new(0, LW - 8, 0, 22), UDim2.new(0, 10, 0, 6), 18, WHITE)
      lab.Font = Enum.Font.GothamBold
      text(band, TT.RANKS[r].years, UDim2.new(0, LW - 8, 0, 16), UDim2.new(0, 10, 0, 28), 11, FAINT)
      if not TT.rankOpen(tree, view.nat, view.branch, r) then
        text(band, L("未开", "locked"), UDim2.new(0, LW - 8, 0, 16), UDim2.new(0, 10, 0, 42), 11, RGB(170, 90, 80))
      end
      y += m * (CH + GAP)
    end
    for ci, c in ipairs(B.cols) do
      text(scroll, zh and c[1] or c[2], UDim2.new(0, CW, 0, HH - 6), UDim2.new(0, LW + (ci - 1) * (CW + GAP), 0, 4), 12, DIM, Enum.TextXAlignment.Center)
    end
    -- 格子
    local used, pos = {}, {}
    for _, it in ipairs(list) do
      used[it.rank] = used[it.rank] or {}
      local k = used[it.rank][it.col] or 0
      used[it.rank][it.col] = k + 1
      local x = LW + (it.col - 1) * (CW + GAP)
      local cy = rowY[it.rank] + k * (CH + GAP) + GAP / 2
      pos[it.key] = { x = x, y = cy }
      local stt = status(it)
      local card = Instance.new("TextButton")
      card.Name = "Card_" .. it.key
      card.AutoButtonColor = true
      card.Text = ""
      card.Size, card.Position = UDim2.new(0, CW, 0, CH), UDim2.new(0, x, 0, cy)
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = COL[stt], 0.05, 0
      card.ZIndex = 3
      card.Parent = scroll
      local s = Instance.new("UIStroke")
      s.Color = (view.sel == it.key) and WHITE or RGB(70, 76, 80)
      s.Thickness = (view.sel == it.key) and 2 or 1
      s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      s.Parent = card
      local n1 = text(card, nm(it), UDim2.new(1, -12, 0, 20), UDim2.new(0, 6, 0, 4), 13, (stt == "lock") and FAINT or WHITE)
      n1.ZIndex = 4
      local n2 = text(card, "BR " .. TT.brText(it.br) .. "  " .. it.year .. (it.stand and L("  暂用", "  stand-in") or ""), UDim2.new(1, -12, 0, 16), UDim2.new(0, 6, 0, 24), 11, DIM)
      n2.ZIndex = 4
      if stt == "cur" or (tree.rp[it.key] or 0) > 0 then
        local bg = frame(card, UDim2.new(1, -12, 0, 5), UDim2.new(0, 6, 1, -10), RGB(30, 30, 30), 0)
        bg.ZIndex = 4
        local fill = frame(bg, UDim2.new(math.clamp((tree.rp[it.key] or 0) / it.rp, 0, 1), 0, 1, 0), nil, RGB(230, 196, 80), 0)
        fill.ZIndex = 5
      end
      card.MouseButton1Click:Connect(function()
        view.sel = it.key
        refreshTree()
      end)
    end
    -- 同一列的连线：前置那一格的底边 → 这一格的顶边
    for _, it in ipairs(list) do
      local a, b = it.prev and pos[it.prev], pos[it.key]
      if a and b then
        local x = b.x + CW / 2 - 1
        local y0, y1 = a.y + CH, b.y
        if y1 > y0 then
          local ln = frame(scroll, UDim2.new(0, 2, 0, y1 - y0), UDim2.new(0, x, 0, y0), TT.researched(tree, it.prev) and RGB(150, 156, 160) or RGB(60, 64, 68), 0)
          ln.ZIndex = 2
        end
      end
    end
    scroll.CanvasSize = UDim2.new(0, LW + #B.cols * (CW + GAP) + 20, 0, y + 20)
    showDetail(view.sel and TT.get(view.sel))
  end
  openTree = function()
    view.nat = tree.nat
    panel.Visible = true
    refreshTree()
  end
  G.openTechTree = openTree
  G.refreshTechTree = function() if panel.Visible then refreshTree() end end

  me:GetAttributeChangedSignal("Tree"):Connect(function()
    readTree()
    if panel.Visible then refreshTree() end
    if hangar.Visible then refreshHangar() end
  end)
end

return TechUI
