-- 全面大战场（客户端）——局内出击页（战雷的「重生界面」）
--   用户 11-28（给了战雷截图）：「被击毁重新召唤载具要有这个界面」——进局选第一辆、被打掉以后选下一辆都在这一页，不再回 3D 机库：
--   · 顶上一排出击阵容卡（车图、名字、战斗等级、乘员组号、这一局要多少 SP / 免费 / 备用 / 用完了 / 超出本局战斗等级）；
--     选中的那张上面一块琥珀色「加入战斗！」（点它直接出）
--   · 左栏：选中那一辆的出击设置——飞机 / 直升机：挂载方案、燃油量（几成 · 能飞几分钟）；地面车：按机库里配的弹出击；下面「任务目标」
--   · 右边：大地图（同小地图那张，挂过来；网格 A～J / 1～10，同 M 键大地图 WtMap.lua）
--   · 底下一条：数据统计（战况表）· 观战模式 · 退出战斗；右边大按钮「加入战斗！（重生次数：N）」，回车也是它
--   · 左上：模式 · 地图、阶段、剩余时间、我的 SP
--   什么时候出来：在局里（服务器推的 S.pick：这一局算他的、人还没出生）、阵亡镜头放完了、没开主菜单 / 设置 / 观战 / 战况表。
--   开着它的时候机库（TechUI.lua G.hangarSet）不出来；阵容、SP 规矩、能不能出全借机库那边（G.techLineup），出击发同一个 deployVeh
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local WtSpawn = {}

function WtSpawn.init(G)
  local TH = require(RS:WaitForChild("Theme"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local TT = require(RS:WaitForChild("TechTree"))
  local me = Players.LocalPlayer
  local RGB, U2, V2 = Color3.fromRGB, UDim2, Vector2.new
  local function L(zh, en) return (G.lang == "en") and en or zh end
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local AMBER, TEXT, MUTE, FAINT, GOOD, BAD, GOLD = TH.C.WARN, TH.C.TEXT, TH.C.MUTE, TH.C.FAINT, TH.C.GOOD, TH.C.BAD, TH.C.WARN
  local function act(...)
    local args = table.pack(...)
    pcall(function() G.R.Act:FireServer(table.unpack(args, 1, args.n)) end)
  end

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtSpawn"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 13   -- 机库（12）上面、观战（15）/ 设置（30）/ 阵亡效果（40）下面
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  G.wtSpawnGui = gui   -- 测试用

  local function frame(parent, size, pos, col, tr, name)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or U2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or TH.C.PANEL, tr or 0, 0
    if name then f.Name = name end
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, xa, name)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text, t.Size, t.Position = s or "", size, pos or U2.new()
    t.TextSize, t.TextColor3, t.Font = ts or TH.S.body, col or TEXT, font or TH.F.body
    t.TextXAlignment = xa or Enum.TextXAlignment.Left
    t.TextStrokeTransparency = 0.7
    if name then t.Name = name end
    t.Parent = parent
    return t
  end
  local function btn(parent, s, size, pos, name, primary)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text = s
    b.Size, b.Position = size, pos or U2.new()
    b.Font = primary and TH.F.title or TH.F.bold
    b.TextSize = primary and TH.S.sub or TH.S.small
    b.TextColor3 = primary and RGB(24, 18, 8) or TEXT
    b.BackgroundColor3 = primary and AMBER or TH.C.RAISE
    b.BackgroundTransparency = primary and 0 or 0.15
    b.BorderSizePixel = 0
    if name then b.Name = name end
    b.Parent = parent
    TH.corner(b, 2)
    if primary then TH.grad(b, RGB(255, 214, 120), RGB(200, 132, 30)) else TH.stroke(b, false, TH.C.LINE).Transparency = 0.86 end
    b.MouseEnter:Connect(function() if not primary then b.BackgroundColor3 = RGB(48, 54, 60) end end)
    b.MouseLeave:Connect(function() if not primary then b.BackgroundColor3 = TH.C.RAISE end end)
    return b
  end

  -- 整页按 1280 × 720 画，窗口大了小了整体缩放（同机库）
  local root = frame(gui, U2.fromOffset(1280, 720), U2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, "Root")
  root.AnchorPoint = V2(0.5, 0.5)
  local scale = Instance.new("UIScale")
  scale.Parent = root
  local dim = frame(gui, U2.fromScale(1, 1), nil, RGB(6, 9, 12), 0.18, "Dim")   -- 背后的战场压暗
  dim.ZIndex = 0
  root.ZIndex = 1
  local function layout()
    local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
    scale.Scale = math.max(0.5, math.min(vs.X / 1280, vs.Y / 720))
  end

  ---------------------------------------------------------------- 左上：这一局
  local info = text(root, "", U2.fromOffset(420, 18), U2.fromOffset(28, 14), TH.S.small, MUTE, TH.F.bold, nil, "Info")
  local info2 = text(root, "", U2.fromOffset(420, 18), U2.fromOffset(28, 32), TH.S.small, MUTE, TH.F.body, nil, "Info2")

  ---------------------------------------------------------------- 顶上一排出击阵容卡
  local CW, CH, CG = 168, 92, 8
  local row = frame(root, U2.fromOffset(5 * CW + 4 * CG, CH), U2.fromOffset(640 - (5 * CW + 4 * CG) / 2, 62), RGB(0, 0, 0), 1, "Lineup")
  local tab = btn(row, L("加入战斗！", "Join battle!"), U2.fromOffset(CW - 24, 22), U2.fromOffset(0, -24), "JoinTab", true)
  tab.TextSize = TH.S.small
  tab.ZIndex = 3
  local cards = {}

  ---------------------------------------------------------------- 左栏：这一辆的出击设置、任务目标
  local LX, LY, LW = 28, 172, 340
  local side = frame(root, U2.fromOffset(LW, 470), U2.fromOffset(LX, LY), TH.C.PANEL, 0.1, "Side")
  TH.corner(side, 2)
  TH.stroke(side)
  local selName = text(side, "", U2.new(1, -24, 0, 26), U2.fromOffset(12, 8), TH.S.title, TEXT, TH.F.title, nil, "SelName")
  local selSub = text(side, "", U2.new(1, -24, 0, 18), U2.fromOffset(12, 36), TH.S.small, MUTE, TH.F.body, nil, "SelSub")
  local opts = frame(side, U2.new(1, -24, 0, 250), U2.fromOffset(12, 64), RGB(0, 0, 0), 1, "Options")
  local objT = text(side, L("任务目标", "Mission objective"), U2.new(1, -24, 0, 20), U2.fromOffset(12, 322), TH.S.sub, TEXT, TH.F.bold, nil, "ObjTitle")
  local objList = frame(side, U2.new(1, -24, 0, 120), U2.fromOffset(12, 346), RGB(0, 0, 0), 1, "Objectives")

  ---------------------------------------------------------------- 右边：大地图
  local MX, MY = LX + LW + 36, LY
  local MS = 720 - MY - 64   -- 正方形
  local mapBox = frame(root, U2.fromOffset(MS, MS), U2.fromOffset(MX, MY), RGB(0, 0, 0), 0.2, "MapBox")
  TH.stroke(mapBox)
  local holder = frame(mapBox, U2.fromScale(1, 1), nil, RGB(0, 0, 0), 1, "Holder")
  holder.ClipsDescendants = true
  local grid = frame(mapBox, U2.fromScale(1, 1), nil, RGB(0, 0, 0), 1, "Grid")
  grid.ZIndex = 20
  local ROWS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }
  for i = 1, 9 do
    frame(grid, U2.new(0, 1, 1, 0), U2.fromScale(i / 10, 0), RGB(255, 255, 255), 0.82).ZIndex = 20
    frame(grid, U2.new(1, 0, 0, 1), U2.fromScale(0, i / 10), RGB(255, 255, 255), 0.82).ZIndex = 20
  end
  for i = 1, 10 do   -- 行 A～J 在左边、列 1～10 在上边（战雷）
    text(mapBox, ROWS[i], U2.new(0, 20, 0.1, 0), U2.new(0, -22, (i - 1) / 10, 0), TH.S.small, MUTE, TH.F.bold, Enum.TextXAlignment.Center)
    text(mapBox, tostring(i), U2.new(0.1, 0, 0, 16), U2.new((i - 1) / 10, 0, 0, -18), TH.S.small, MUTE, TH.F.bold, Enum.TextXAlignment.Center)
  end

  ---------------------------------------------------------------- 底下一条
  local bar = frame(root, U2.fromOffset(1280 - 56, 40), U2.fromOffset(28, 720 - 52), RGB(0, 0, 0), 1, "Bar")
  local bStats = btn(bar, L("数据统计", "Statistics"), U2.fromOffset(124, 34), U2.fromOffset(0, 3), "Stats")
  local bSpec = btn(bar, L("观战模式", "Spectate"), U2.fromOffset(124, 34), U2.fromOffset(132, 3), "Spectate")
  local bLeave = btn(bar, L("退出战斗", "Leave battle"), U2.fromOffset(124, 34), U2.fromOffset(264, 3), "SpawnLeave")   -- 别叫 LeaveMatch：机库那个按钮叫这个
  local go = btn(bar, "", U2.fromOffset(330, 40), U2.new(1, -330, 0, 0), "SpawnGo", true)
  local goSub = text(go, "", U2.new(1, -16, 0, 12), U2.new(0, 8, 1, -13), TH.S.tiny, RGB(60, 42, 14), TH.F.bold, Enum.TextXAlignment.Center, "GoSub")
  go.TextYAlignment = Enum.TextYAlignment.Top
  local goPad = Instance.new("UIPadding")
  goPad.PaddingTop = UDim.new(0, 4)
  goPad.Parent = go
  local hint = text(root, L("回车 加入战斗 · Tab 战况", "Enter join · Tab scores"), U2.fromOffset(300, 14), U2.new(1, -328, 1, -66), TH.S.tiny, FAINT, TH.F.body, Enum.TextXAlignment.Right, "Hint")
  if mobile then hint.Visible = false end

  ---------------------------------------------------------------- 状态
  local on = false
  local lastClick = { key = nil, t = -9 }   -- 双击一张卡直接出（同战雷；单击会重画卡片，所以不记在卡上）
  local sel = nil        -- 选中的那一位：{ key, it, can, sp, ... }（G.techLineup 的一项）
  local lineSig = nil    -- 上次画卡片时的阵容、战况
  G.wtSpawnOn = function() return on end

  local function lineup()
    if not G.techLineup then return {}, 1 end
    local ok, list, si = pcall(G.techLineup)
    if not ok then return {}, 1 end
    return list or {}, si or 1
  end
  local function spawnsLeft(key)
    local w = G.S and G.S.wt
    if not w then return nil end
    local n = (w.ln and w.ln[key]) or 0
    return math.max(0, 1 + (w.backup or 1) - n)
  end

  -- 一个选项行：标题 + 一排小按钮（点一个就是它；当前的那个亮）
  local function optRow(y, title, choices, cur, onPick, name)
    text(opts, title, U2.new(1, 0, 0, 16), U2.fromOffset(0, y), TH.S.tiny, MUTE, TH.F.bold)
    local n = #choices
    local w = math.floor((LW - 24 - (n - 1) * 4) / math.max(n, 1))
    for i, c in ipairs(choices) do
      local b = btn(opts, c.label, U2.fromOffset(w, 28), U2.fromOffset((i - 1) * (w + 4), y + 18), (name or "Opt") .. "_" .. tostring(c.v))
      b.TextSize = TH.S.tiny
      b.TextWrapped = true
      local isCur = c.v == cur
      if isCur then
        b.BackgroundColor3, b.BackgroundTransparency = RGB(70, 58, 30), 0
        local st = b:FindFirstChildOfClass("UIStroke")
        if st then st.Color, st.Transparency = AMBER, 0.2 end
      end
      b.MouseButton1Click:Connect(function() if not isCur then onPick(c.v) end end)
    end
    return y + 52
  end

  local function fillOptions()
    for _, c in ipairs(opts:GetChildren()) do c:Destroy() end
    local it = sel and sel.it
    if not it then
      selName.Text = L("出击阵容是空的", "Lineup is empty")
      selSub.Text = ""
      return
    end
    selName.Text = sel.name or it.key
    local kind = (it.branch == "air") and L("战机", "Aircraft") or (it.branch == "heli") and L("直升机", "Helicopter") or L("地面车", "Ground vehicle")
    selSub.Text = kind .. "  ·  BR " .. (sel.br or "?")
    local a = (it.branch ~= "ground") and AD.get(it.play) or nil
    local y = 0
    if a and G.treeAirLoad and G.treeSaveLoad then
      local l, p, f = G.treeAirLoad(it)
      -- 挂载方案（这一型的预设；整备里改过的写「自定」）
      local ch = {}
      for _, pr in ipairs(a.presets or {}) do
        local nmp = T("preset." .. pr.key)
        if nmp == "preset." .. pr.key then nmp = pr.key end
        table.insert(ch, { v = pr.key, label = nmp })
      end
      if #ch > 4 then   -- 太多放不下一排：只列前四个（其余在机库整备里换）
        local keep = {}
        for i = 1, 4 do keep[i] = ch[i] end
        local hasCur = false
        for _, c in ipairs(keep) do if c.v == p then hasCur = true end end
        if not hasCur and p then
          for _, c in ipairs(ch) do if c.v == p then keep[4] = c end end
        end
        ch = keep
      end
      if #ch > 0 then
        y = optRow(y, L("挂载", "Loadout"), ch, p, function(v)
          local _, _, f0 = G.treeAirLoad(it)
          G.treeSaveLoad(it.key, AD.presetLoad(a, v), v, f0, true)
          fillOptions()
        end, "Preset")
      end
      -- 燃油量（几成 · 能飞几分钟，同战雷「62%（25 分）」）
      local fc = {}
      for _, fv in ipairs(AD.FUEL_OPTS or { 0.25, 0.5, 0.75, 1 }) do
        local mins = AD.fuelMin and AD.fuelMin(a, fv) or nil
        table.insert(fc, { v = fv, label = string.format("%d%%", math.floor(fv * 100 + 0.5)) .. (mins and (L("（", " (") .. mins .. L(" 分）", " min)")) or "") })
      end
      local fNow = AD.cleanFuel(f)
      local best, bd = nil, math.huge
      for _, c in ipairs(fc) do if math.abs(c.v - fNow) < bd then best, bd = c.v, math.abs(c.v - fNow) end end
      y = optRow(y, L("燃油量", "Fuel"), fc, best, function(v)
        local l2, p2 = G.treeAirLoad(it)
        G.treeSaveLoad(it.key, l2, p2, v, true)
        fillOptions()
      end, "Fuel")
      text(opts, L("挂点、副油箱细调在机库「整备」里", "Fine-tune pylons in the hangar workshop"), U2.new(1, 0, 0, 16), U2.fromOffset(0, y), TH.S.tiny, FAINT)
    else
      text(opts, L("弹药：按机库里配的出击", "Ammo: as loaded in the hangar"), U2.new(1, 0, 0, 18), U2.fromOffset(0, y), TH.S.small, MUTE, TH.F.bold)
    end
  end

  local function fillObjectives()
    for _, c in ipairs(objList:GetChildren()) do c:Destroy() end
    local S = G.S or {}
    local it = sel and sel.it
    local air = it and it.branch ~= "ground"
    local mine = me:GetAttribute("Side")
    local y = 0
    local first = air and L("☆ 协助地面部队，夺取制空权", "☆ Support ground forces, win air superiority")
      or L("☆ 占领并守住据点", "☆ Capture and hold the zones")
    text(objList, first, U2.new(1, 0, 0, 20), U2.fromOffset(0, y), TH.S.small, TEXT, TH.F.bold, nil, "Obj0")
    y += 24
    for _, p in ipairs(S.points or {}) do
      if y > 96 then break end
      local who, col = L("中立", "neutral"), MUTE
      if p.owner == mine then who, col = L("我方", "ours"), TH.C.FRIEND or GOOD
      elseif p.owner ~= nil and p.owner ~= "none" and p.owner ~= "" then who, col = L("敌方", "enemy"), TH.C.FOE or BAD end
      local where = ""
      local MP = G.Map and G.Map.POINTS
      if MP and G.mapGridRef then
        for _, q in ipairs(MP) do if q.id == p.id and q.x then where = "  " .. G.mapGridRef(q.x, q.z) end end
      end
      text(objList, string.format("%s %s · %s%s", L("据点", "Zone"), tostring(p.id), who, where), U2.new(1, 0, 0, 18), U2.fromOffset(12, y), TH.S.small, col, TH.F.body)
      y += 20
    end
  end

  local function fillTop()
    local S = G.S or {}
    local w = S.wt or {}
    local left = S.left and string.format("%d:%02d", math.floor(S.left / 60), math.floor(S.left % 60)) or "--:--"
    local mid = S.map or (G.Map and G.Map.id) or ""
    local mapN = T("map." .. mid .. ".name")
    if mapN == "map." .. mid .. ".name" then mapN = mid end
    info.Text = L("历史", "Realistic") .. ((mapN ~= "") and ("  ·  " .. mapN) or "")
    info2.Text = ((S.phase == "prep") and L("准备阶段", "Preparation") or L("交战中", "In battle")) .. L("  ·  剩余时间 ", "  ·  time left ") .. left
      .. "  ·  SP " .. tostring(w.sp or 0)
  end

  local function setGo()
    local key = sel and sel.key
    local left = key and spawnsLeft(key)
    go.Text = L("加入战斗！", "Join battle!") .. ((left ~= nil) and string.format(L("（重生次数：%d）", " (respawns: %d)"), left) or "")
    local can = sel ~= nil and sel.can == true
    go.BackgroundTransparency = can and 0 or 0.45
    go.TextColor3 = can and RGB(24, 18, 8) or RGB(80, 70, 50)
    goSub.Text = sel and ((sel.name or "") .. ((sel.sp and sel.sp ~= "") and ("  ·  " .. sel.sp) or "")) or L("阵容里没有能出的车", "Nothing to spawn")
    goSub.TextColor3 = (sel and not can) and RGB(150, 30, 20) or RGB(60, 42, 14)
    tab.Visible = can
  end

  local function buildCards()
    local list, si = lineup()
    for _, c in ipairs(cards) do c:Destroy() end
    table.clear(cards)
    sel = list[si]
    if not sel or sel.lock then   -- 选中的那位禁选：挑第一位能出的
      for i = 1, 5 do
        if list[i] and not list[i].lock then sel, si = list[i], i break end
      end
    end
    for i = 1, 5 do
      local c = list[i]
      local x = (i - 1) * (CW + CG)
      local card = Instance.new("TextButton")
      card.Name = c and ("Spawn_" .. c.key) or ("SpawnEmpty_" .. i)
      card.AutoButtonColor = false
      card.Text = ""
      card.Size, card.Position = U2.fromOffset(CW, CH), U2.fromOffset(x, 0)
      card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = RGB(27, 31, 36), 0.08, 0
      card.Parent = row
      TH.corner(card, 2)
      table.insert(cards, card)
      local isSel = c ~= nil and sel ~= nil and c.key == sel.key
      if c and c.lock then card:SetAttribute("Locked", true) end   -- 禁选（还没出过地面车的飞机）
      if isSel then TH.glow(card) else TH.stroke(card, false, TH.C.LINE).Transparency = 0.84 end
      if c then
        local dead = c.can ~= true
        local bay = frame(card, U2.fromScale(1, 1), nil, RGB(255, 255, 255), dead and 0.8 or 0.35, "Bay")
        bay.ZIndex = 0
        TH.corner(bay, 2)
        if TH.rankGrad then TH.rankGrad(bay, c.it.rank) end
        local img = Instance.new("ImageLabel")
        img.Name = "Pic"
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Size, img.Position = U2.new(1, -16, 1, -38), U2.fromOffset(8, 16)
        img.ImageTransparency = dead and 0.6 or 0
        img.Parent = card
        if G.techPicOn then pcall(G.techPicOn, img, c.it) end
        text(card, c.name or c.key, U2.new(1, -36, 0, 16), U2.fromOffset(6, 2), TH.S.small, dead and FAINT or TEXT, TH.F.bold, Enum.TextXAlignment.Left, "VehName")
        local br = text(card, c.br or "", U2.fromOffset(40, 16), U2.new(1, -44, 0, 2), TH.S.small, c.over and BAD or MUTE, TH.F.mono, Enum.TextXAlignment.Right, "Br")
        br.TextStrokeTransparency = 0.5
        text(card, "#" .. i, U2.fromOffset(24, 14), U2.new(0, 6, 1, -16), TH.S.tiny, FAINT, TH.F.mono, nil, "Slot")
        text(card, c.sp or "", U2.new(1, -36, 0, 14), U2.new(0, 30, 1, -16), TH.S.tiny, c.spC or MUTE, TH.F.bold, Enum.TextXAlignment.Right, "Sp")
        local slotI = i
        card.MouseButton1Click:Connect(function()
          if c.lock then return end
          if G.techSelectSlot then pcall(G.techSelectSlot, slotI) end
          lineSig = nil   -- 下一帧重画
        end)
        card.MouseButton1Down:Connect(function()   -- 双击直接出（同战雷）
          local t = os.clock()
          if lastClick.key == c.key and t - lastClick.t < 0.35 and c.can then act("deployVeh", c.key) end
          lastClick.key, lastClick.t = c.key, t
        end)
      else
        text(card, L("空位", "Empty"), U2.fromScale(1, 1), nil, TH.S.small, FAINT, TH.F.body, Enum.TextXAlignment.Center)
      end
      if isSel then tab.Position = U2.fromOffset(x + 12, -24) end
    end
    fillOptions()
    fillObjectives()
    setGo()
  end

  local function deploy()
    if sel and sel.can then act("deployVeh", sel.key) end
  end
  go.MouseButton1Click:Connect(deploy)
  tab.MouseButton1Click:Connect(deploy)
  bStats.MouseButton1Click:Connect(function() if G.boardToggle then G.boardToggle(true) end end)
  bSpec.MouseButton1Click:Connect(function() if G.wtSpecStart then G.wtSpecStart() end end)
  bLeave.MouseButton1Click:Connect(function() act("matchLeave") end)

  ---------------------------------------------------------------- 开、关
  local function wantOn()
    local S = G.S
    if not S or S.pick ~= true or S.alive then return false end
    if not (G.hangarActive and G.hangarActive()) then return false end
    if G.deathFxOn and G.deathFxOn() then return false end
    if G.menuShown and G.menuShown() then return false end
    if G.settingsShown and G.settingsShown() then return false end
    if G.wtSpectating and G.wtSpectating() then return false end
    if G.boardShown and G.boardShown() then return false end
    if S.phase == "end" then return false end
    return true
  end
  local function setOn(v)
    if v == on then return end
    on = v
    gui.Enabled = v
    if v then
      layout()
      lineSig = nil
      if G.mapMount then G.mapMount(holder, U2.fromScale(1, 1)) end
      if G.uiPop and not (G.reducedMotion and G.reducedMotion()) then G.uiPop(root, 0.97, true) end
    else
      local P = G.hudParts
      if G.mapMount and P then G.mapMount(P.miniClip or P.miniBox, U2.fromScale(1, 1)) end
    end
    if G.refresh then pcall(G.refresh) end   -- 机库跟着收 / 出（TechUI G.hangarSet 看 G.wtSpawnOn）
  end
  G.wtSpawnSet = function(v) setOn(v == true) end   -- 测试用

  UIS.InputBegan:Connect(function(io, gp)
    if not on or gp or UIS:GetFocusedTextBox() then return end
    if io.KeyCode == Enum.KeyCode.Return or io.KeyCode == Enum.KeyCode.KeypadEnter then deploy() end
  end)
  -- 战况表从这一页点开的：Esc 关上回到这一页
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    if io.KeyCode == Enum.KeyCode.Escape and G.boardShown and G.boardShown() and G.S and G.S.pick and G.boardToggle then G.boardToggle(false) end
  end)

  local acc = 0
  local function step(dt)
    acc += dt
    if acc < 0.1 then return end
    acc = 0
    setOn(wantOn())
    if not on then return end
    -- 阵容、战况（服务器一秒推两次 G.S）、语言变了才重画卡片
    local list, si = lineup()
    local S = G.S or {}
    local w = S.wt or {}
    local bits = { tostring(si), tostring(G.lang), tostring(w.sp), tostring(w.free), tostring(w.paid), tostring(S.phase) }
    for i = 1, 5 do
      local c = list[i]
      bits[#bits + 1] = c and (c.key .. ":" .. tostring(c.sp) .. ":" .. tostring(c.can)) or "-"
    end
    local sig = table.concat(bits, "|")
    if sig ~= lineSig then
      lineSig = sig
      buildCards()
    end
    fillTop()
  end
  if G.frameConn then G.frameConn("WtSpawn", step) else game:GetService("RunService").RenderStepped:Connect(step) end
  local cam = workspace.CurrentCamera
  if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if on then layout() end end) end
end

return WtSpawn
