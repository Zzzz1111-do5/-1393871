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
  local WM = require(RS:WaitForChild("WtMods"))   -- 每辆车的改装
  local WC = require(RS:WaitForChild("WtCrew"))   -- 乘员
  local WD = require(RS:WaitForChild("WtDamage"))   -- 装甲、穿深（资料卡）
  local BAL = require(RS:WaitForChild("Ballistics"))
  local VM = require(script.Parent:WaitForChild("VehModels"))   -- 装甲查看器里的车模
  local RunService = game:GetService("RunService")
  local zh = G.lang == "zh"
  local function L(a, b) return zh and a or b end
  local function nm(it) return zh and it.name or it.en end
  -- 型号的名字（Lang 的 veh.<型号>；没有就写型号）：暂用 / 同族模型那一行写借的是哪一型
  local function vname(id)
    local t = id and G.T and G.T("veh." .. id)
    return (t and t ~= "veh." .. id) and t or string.upper(tostring(id))
  end
  local RGB = Color3.fromRGB
  local WHITE, DIM, FAINT = Color3.new(1, 1, 1), RGB(150, 156, 160), RGB(96, 102, 106)
  local GOOD, GOLD, BAD = RGB(140, 210, 140), RGB(230, 196, 110), RGB(232, 120, 100)
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
  local brT = text(hangar, "", UDim2.new(1, -2 * M0, 0, 24), UDim2.new(0, M0, 1, -262), 16, WHITE)
  local row = frame(hangar, UDim2.new(1, -2 * M0, 0, 182), UDim2.new(0, M0, 1, -228), nil, 1)
  local rowLayout = Instance.new("UIListLayout")
  rowLayout.FillDirection = Enum.FillDirection.Horizontal
  rowLayout.Padding = UDim.new(0, 10)
  rowLayout.Parent = row
  local hint = text(hangar, L("选一辆出击：直接坐在车里 / 飞机里出现在自己基地。车没了回到这里。", "Pick a vehicle: you spawn inside it at your base. Lose it and you come back here."),
    UDim2.new(1, -2 * M0, 0, 20), UDim2.new(0, M0, 1, -40), 13, FAINT)
  G.hangarGui = hangar   -- 测试用

  -- 三种模式（服务器 Tech.lua：准备阶段按票数，开战定住，workspace 属性 WtMode；每人投的票是玩家属性 ModeVote）
  local MODE_NAME = { ab = L("街机", "Arcade"), rb = L("历史", "Realistic"), sb = L("全真", "Simulator") }
  local MODE_DESC = {
    ab = L("看得见的敌人都标出来，飞机直接在空中出生 · 奖励 ×1", "All visible enemies marked, aircraft spawn in the air · rewards ×1"),
    rb = L("只标近处看得见的敌人，飞机从跑道起飞 · 奖励 ×1.3", "Only nearby visible enemies marked, aircraft take off from the runway · rewards ×1.3"),
    sb = L("不标敌人，只能第一人称（瞄准镜、车内、座舱）· 奖励 ×1.6", "No markers, first person only (sights, interior, cockpit) · rewards ×1.6"),
  }
  local modeBar = frame(hangar, UDim2.new(0, mobile and 300 or 420, 0, 30), UDim2.new(1, -M0 - (mobile and 300 or 420), 0, 128), nil, 1)
  local mlay = Instance.new("UIListLayout")
  mlay.FillDirection = Enum.FillDirection.Horizontal
  mlay.HorizontalAlignment = Enum.HorizontalAlignment.Right
  mlay.Padding = UDim.new(0, 6)
  mlay.Parent = modeBar
  local modeT = text(hangar, "", UDim2.new(0, mobile and 300 or 520, 0, 18), UDim2.new(1, -M0 - (mobile and 300 or 520), 0, 164), 12, DIM, Enum.TextXAlignment.Right)
  modeT.Name = "ModeT"
  local modeBtns = {}
  for _, m in ipairs({ "ab", "rb", "sb" }) do
    local b = button(modeBar, MODE_NAME[m], UDim2.new(0, mobile and 96 or 132, 1, 0))
    b.Name = "Mode_" .. m
    b.MouseButton1Click:Connect(function() act("wtModeVote", m) end)
    modeBtns[m] = b
  end
  local function refreshMode()
    local cur = workspace:GetAttribute("WtMode") or "rb"
    if not MODE_NAME[cur] then cur = "rb" end
    local cnt = { ab = 0, rb = 0, sb = 0 }
    for _, pl in ipairs(Players:GetPlayers()) do
      local v = pl:GetAttribute("ModeVote")
      if cnt[v] then cnt[v] += 1 end
    end
    local mine = me:GetAttribute("ModeVote")
    for m, b in pairs(modeBtns) do
      local on = m == cur
      b.BackgroundColor3 = on and WHITE or RGB(30, 34, 38)
      b.TextColor3 = on and RGB(10, 10, 10) or WHITE
      b.Text = MODE_NAME[m] .. ((cnt[m] > 0) and ("  " .. cnt[m]) or "") .. ((mine == m) and "  ✓" or "")
    end
    modeT.Text = L("本局模式：", "Mode: ") .. MODE_NAME[cur] .. "  ·  " .. MODE_DESC[cur]
  end

  -- 全真模式：只能第一人称——车外的时候坐进车里（这辆车没有内饰就开瞄准镜）；飞机有座舱的坐进座舱
  task.spawn(function()
    while true do
      task.wait(0.5)
      if workspace:GetAttribute("WtMode") == "sb" then
        local d = G.drive
        if d and G.myVeh and not d.sight and not (G.interiorOn and G.interiorOn()) then
          if not (G.interiorEnterSeat and G.interiorEnterSeat()) and G.driveSetSight then pcall(G.driveSetSight, true) end
        end
        if G.fly and not (G.interiorOn and G.interiorOn()) and G.interiorEnterSeat then pcall(G.interiorEnterSeat) end
      end
    end
  end)

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
  -- 这一辆这一局出车要什么（照服务器 WtMatch 推的 S.wt：准备阶段、第一辆免费；出过一次的是备用；备用用完、阵容满了不能出）
  local function spState(it)
    local d = defOf(it)
    if not d or not Config.WtCost then return nil end
    local cat = d.cat or (it.branch == "air" and "jet" or "tank")
    local S = G.S
    local w = S and S.wt
    if not w then
      local ok, c = pcall(Config.WtCost, it.play, cat, 0)
      return ok and c and ("SP " .. c) or nil, FAINT
    end
    local n = (w.ln and w.ln[it.key]) or 0
    if n >= 1 + (w.backup or 1) then return L("备用也用完了", "Used up"), BAD end
    if n == 0 and #(w.order or {}) >= (w.max or 5) then return L("这一局阵容满了", "Lineup full"), FAINT end
    local c = 0
    if S.phase == "battle" and not w.free then
      local ok, v = pcall(Config.WtCost, it.play, cat, w.paid or 0)
      c = ok and v or 0
    end
    local txt = (c == 0) and L("免费", "Free") or ("SP " .. c .. " / " .. (w.sp or 0))
    if n >= 1 then txt = txt .. L(" · 备用", " · backup") end
    return txt, (c == 0) and GOOD or ((c <= (w.sp or 0)) and GOLD or BAD)
  end
  -- 这一局的战斗等级（服务器 Tech.lua 写 workspace 属性 WtBr）：能出到 BR + brUp
  local function brCap()
    local rb = workspace:GetAttribute("WtBr")
    if type(rb) ~= "number" then return nil, nil end
    return rb, rb + ((Config.Wt or {}).brUp or 1.0)
  end
  ---------------------------------------------------------------- 乘员（WtCrew）：阵容每一位一组乘员，升级给技能点，点技能
  local crewP = frame(gui, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  crewP.Name = "Crew"
  crewP.Visible = false
  crewP.ZIndex = 10
  G.crewGui = crewP   -- 测试用
  local cCard = frame(crewP, UDim2.new(0, 520, 0, 420), UDim2.fromScale(0.5, 0.5), RGB(12, 14, 17), 0.03)
  cCard.AnchorPoint = Vector2.new(0.5, 0.5)
  local cFit = Instance.new("UISizeConstraint")
  cFit.MaxSize = Vector2.new(520, 420)
  cFit.Parent = cCard
  if mobile then cCard.Size = UDim2.fromScale(0.94, 0.9) end
  local cSt = Instance.new("UIStroke")
  cSt.Color, cSt.Transparency = RGB(90, 96, 100), 0.5
  cSt.Parent = cCard
  local cTitle = text(cCard, "", UDim2.new(1, -140, 0, 28), UDim2.new(0, 18, 0, 14), 19)
  cTitle.Font = Enum.Font.GothamBold
  local cClose = button(cCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 12))
  cClose.MouseButton1Click:Connect(function() crewP.Visible = false end)
  local cLv = text(cCard, "", UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 50), 13, DIM)
  local cBarBg = frame(cCard, UDim2.new(1, -36, 0, 4), UDim2.new(0, 18, 0, 72), RGB(40, 44, 48), 0)
  local cBar = frame(cBarBg, UDim2.new(0, 0, 1, 0), nil, GOLD, 0)
  local cRows = frame(cCard, UDim2.new(1, -36, 1, -100), UDim2.new(0, 18, 0, 88), nil, 1)
  local crewAt = nil   -- { nat, slot, key }
  local function refreshCrew()
    if not crewAt or not crewP.Visible then return end
    clear(cRows)
    local cs = tree.crew and tree.crew[crewAt.nat] and tree.crew[crewAt.nat][tostring(crewAt.slot)] or { xp = 0, sk = {} }
    local it = TT.get(crewAt.key)
    local lv = WC.level(cs.xp)
    local free = WC.free(cs)
    cTitle.Text = L("阵容第 ", "Slot ") .. crewAt.slot .. L(" 位 · 乘员", " · Crew") .. (it and ("（" .. nm(it) .. "）") or "")
    local a, b = WC.xpFor(lv), WC.xpFor(lv + 1)
    cLv.Text = L("等级 ", "Level ") .. lv .. "   ·   " .. L("经验 ", "XP ") .. math.floor(cs.xp or 0) .. " / " .. b .. "   ·   " .. L("技能点 ", "Points ") .. free
    cBar.Size = UDim2.new(math.clamp(((cs.xp or 0) - a) / math.max(b - a, 1), 0, 1), 0, 1, 0)
    for i, s in ipairs(WC.SKILLS) do
      local y = (i - 1) * 58
      local r = frame(cRows, UDim2.new(1, 0, 0, 52), UDim2.new(0, 0, 0, y), RGB(20, 23, 26), 0.1)
      r.Name = "Sk_" .. s.key
      text(r, zh and s.zh or s.en, UDim2.new(0, 120, 0, 20), UDim2.new(0, 10, 0, 6), 14, WHITE)
      text(r, zh and s.dz or s.de, UDim2.new(0, 200, 0, 16), UDim2.new(0, 10, 0, 28), 11, DIM)
      local cur = (cs.sk and cs.sk[s.key]) or 0
      for p = 1, WC.MAXLV do   -- 5 格：点了的亮
        local pip = frame(r, UDim2.new(0, 18, 0, 8), UDim2.new(1, -230 + (p - 1) * 24, 0.5, -4), (p <= cur) and GOLD or RGB(50, 54, 58), 0)
        pip.Name = "Pip"
      end
      local cost = WC.stepCost(cur + 1)
      local can = cur < WC.MAXLV and free >= cost
      local up = button(r, (cur >= WC.MAXLV) and L("满级", "Max") or ("+ " .. cost), UDim2.new(0, 84, 0, 32), UDim2.new(1, -94, 0.5, -16), can)
      up.Name = "Up"
      if not can then up.TextColor3 = FAINT end
      up.MouseButton1Click:Connect(function() if can then act("crewUp", crewAt.nat, crewAt.slot, s.key) end end)
    end
  end
  local function openCrew(nat, slot, key)
    crewAt = { nat = nat, slot = slot, key = key }
    crewP.Visible = true
    refreshCrew()
  end
  G.openCrew = openCrew

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
        local spT, spC = spState(it)
        if spT then text(card, spT, UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 52), 12, spC or FAINT).Name = "Sp" end
        local md = tree.mods and tree.mods[key]
        local nDone, nAll = WM.count(it, md and md.done)
        text(card, L("改装 ", "Mods ") .. nDone .. " / " .. nAll, UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 70), 11, (nDone == nAll) and GOOD or DIM).Name = "ModCount"
        if it.stand then   -- 还没有自己的模型：借的是哪一型写在科技树详情里
          text(card, L("暂用模型", "stand-in model"), UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 86), 11, RGB(200, 170, 90))
        elseif it.model then   -- 性能是自己的，模型借同族的
          text(card, L("同族模型", "family model"), UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 86), 11, RGB(170, 185, 150))
        end
        local cs = tree.crew and tree.crew[tree.nat] and tree.crew[tree.nat][tostring(i)] or { xp = 0 }
        local cfree = WC.free(cs)
        text(card, L("乘员 ", "Crew ") .. WC.level(cs.xp) .. L(" 级", "") .. (cfree > 0 and (L(" · ", " · ") .. cfree .. L(" 点", " pts")) or ""),
          UDim2.new(1, -86, 0, 16), UDim2.new(0, 8, 0, 108), 11, cfree > 0 and GOLD or DIM).Name = "CrewT"
        local cb = button(card, L("乘员", "Crew"), UDim2.new(0, 64, 0, 22), UDim2.new(1, -72, 0, 104))
        cb.Name = "CrewBtn"
        cb.TextSize = 12
        local slotI = i
        cb.MouseButton1Click:Connect(function() openCrew(tree.nat, slotI, key) end)
        -- 涂装、贴花（C：用户 11-25「全部都做」⑯，WtSkin.lua）
        if it.branch ~= "air" and G.openSkin then
          local sb = button(card, L("涂装", "Paint"), UDim2.new(0, 64, 0, 19), UDim2.new(1, -72, 0, 83))
          sb.Name = "SkinBtn"
          sb.TextSize = 12
          sb.MouseButton1Click:Connect(function() G.openSkin(key) end)
        end
        -- 配弹（C：用户 11-25「全部都做」④，WtAmmo.lua）：地面车的主炮每种弹带几发
        if it.branch ~= "air" and G.openAmmo then
          local ab = button(card, L("弹药", "Ammo"), UDim2.new(0, 64, 0, 19), UDim2.new(1, -72, 0, 62))   -- 「乘员」上面两格（改装数那几行右边是空的）
          ab.Name = "AmmoBtn"
          ab.TextSize = 12
          ab.MouseButton1Click:Connect(function()
            local md = tree.mods and tree.mods[key]
            local fx = WM.fx and WM.fx(it, md and md.done)
            G.openAmmo(key, fx and fx.ammo)
          end)
        end
        local _, cap = brCap()
        local over = cap ~= nil and it.br > cap + 0.05   -- 超出这一局能出的战斗等级：标灰（点了服务器也会说）
        local go = button(card, over and L("超出本局战斗等级", "Above battle BR") or L("出击", "Deploy"), UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -44), not over)
        go.Name = "Go"
        if over then
          go.TextColor3 = BAD
          card.BackgroundTransparency = 0.45
        end
        go.MouseButton1Click:Connect(function() act("deployVeh", key) end)
      else
        text(card, L("空位", "Empty"), UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 8), 15, FAINT)
        local add = button(card, L("从科技树里放进来", "Add from tech tree"), UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -44))
        add.MouseButton1Click:Connect(function() if openTree then openTree() end end)
      end
    end
    local rb, cap = brCap()
    brT.Text = L("阵容战斗等级 ", "Lineup BR ") .. TT.brText(TT.lineupBr(keys))
      .. (rb and (L("   ·   本局战斗等级 ", "   ·   Battle BR ") .. TT.brText(rb) .. L("（能出到 ", " (up to ") .. TT.brText(cap) .. L("）", ")")) or "")
  end
  G.refreshLineup = refreshHangar   -- 不叫 G.refreshHangar：Hangar.lua（改挂载）的刷新函数叫这个名字，顶掉了它就坏了
  treeBtn.MouseButton1Click:Connect(function() if openTree then openTree() end end)

  -- 原来的部署界面（UI.lua）每次刷新都问一下：该显示部署页的时候机库盖上去
  local lastSig = nil
  function G.hangarSet(show)
    local want = show and G.hangarActive() and not (G.wtSpectating and G.wtSpectating())   -- C ⑮：观战的时候机库收起（WtCam.lua）
    if hangar.Visible ~= want then
      hangar.Visible = want
      if want then refreshHangar() end
    end
    if want then
      refreshMode()
      local S = G.S
      if S then
        local fmt = function(s) s = math.max(0, math.floor(s or 0)) return string.format("%d:%02d", s // 60, s % 60) end
        phaseT.Text = (S.phase == "prep") and (L("准备阶段 ", "Preparing ") .. fmt(S.left)) or (L("剩余时间 ", "Time left ") .. fmt(S.left))
        -- 这一局的账（SP、免费那一辆、出过几次）、战斗等级变了：卡片上的「免费 / SP / 备用 / 用完」跟着刷新
        local w = S.wt or {}
        local sig = table.concat({ tostring(S.phase), tostring(w.sp), tostring(w.free), tostring(w.paid), tostring(#(w.order or {})), tostring(workspace:GetAttribute("WtBr")) }, "|")
        if sig ~= lastSig then
          lastSig = sig
          refreshHangar()
        end
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

  ---------------------------------------------------------------- 改装（WtMods）：三列（机动 / 防护 / 火力）× 四级，点一项设成研究目标
  local modsP = frame(gui, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  modsP.Name = "Mods"
  modsP.Visible = false
  modsP.ZIndex = 10
  G.modsGui = modsP   -- 测试用
  local mCard = frame(modsP, UDim2.fromScale(0.94, 0.86), UDim2.fromScale(0.03, 0.07), RGB(12, 14, 17), 0.03)
  local mLim = Instance.new("UISizeConstraint")
  mLim.MaxSize = Vector2.new(820, 560)
  mLim.Parent = mCard
  mCard.AnchorPoint, mCard.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
  local mStroke = Instance.new("UIStroke")
  mStroke.Color, mStroke.Transparency = RGB(90, 96, 100), 0.5
  mStroke.Parent = mCard
  local mTitle = text(mCard, "", UDim2.new(1, -140, 0, 30), UDim2.new(0, 18, 0, 14), 20)
  mTitle.Font = Enum.Font.GothamBold
  local mSub = text(mCard, "", UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 46), 12, DIM)
  local mClose = button(mCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 14))
  mClose.Name = "Close"
  mClose.MouseButton1Click:Connect(function() modsP.Visible = false end)
  local mGrid = frame(mCard, UDim2.new(1, -36, 1, -124), UDim2.new(0, 18, 0, 76), nil, 1)
  local mFoot = text(mCard, L("这辆车每打一局，结束时它挣的研究点先给正在研究的那项改装（没选就按顺序自动研究）；研究完自动装上。每一级研究完两项，开下一级。",
    "Research points this vehicle earns go to the selected modification (or the next one in order); researched mods install automatically. Two per tier unlock the next tier."),
    UDim2.new(1, -36, 0, 34), UDim2.new(0, 18, 1, -44), 12, FAINT)
  mFoot.TextWrapped, mFoot.TextTruncate = true, Enum.TextTruncate.None
  local modsIt = nil
  local function refreshMods()
    local it = modsIt
    if not it or not modsP.Visible then return end
    clear(mGrid)
    local md = (tree.mods and tree.mods[it.key]) or {}
    local done = md.done or {}
    local nDone, nAll = WM.count(it, done)
    mTitle.Text = nm(it) .. L("  ·  改装", "  ·  Modifications")
    mSub.Text = L("已装 ", "Installed ") .. nDone .. " / " .. nAll .. (md.cur and (L("   ·   正在研究：", "   ·   Researching: ") .. ((WM.get(it, md.cur) or {})[zh and "zh" or "en"] or "")) or "")
    local classes = {}
    for _, c in ipairs(WM.CLS) do
      for _, m in ipairs(WM.list(it)) do if m.cls == c then classes[c] = true end end
    end
    local cols = {}
    for _, c in ipairs(WM.CLS) do if classes[c] then table.insert(cols, c) end end
    local nC = #cols
    local headH, rowGap, colGap, tierW = 24, 8, 10, 34
    -- 左边 tierW 像素是等级栏，上面 headH 像素是表头；其余按比例分：横坐标比例 sx → 位置 (sx, tierW·(1 − sx))，纵坐标比例 sy → (sy, headH·(1 − sy))
    local function px(sx) return sx, tierW * (1 - sx) end
    local function py(sy) return sy, headH * (1 - sy) end
    for ci, c in ipairs(cols) do   -- 表头：机动 / 防护 / 火力
      local sx, ox = px((ci - 1) / nC)
      local h = text(mGrid, L(WM.CLS_NAME[c][1], WM.CLS_NAME[c][2]), UDim2.new(1 / nC, -colGap - tierW / nC, 0, headH),
        UDim2.new(sx, ox, 0, 0), 13, DIM, Enum.TextXAlignment.Center)
      h.Font = Enum.Font.GothamBold
    end
    for tier = 1, 4 do
      local open = WM.tierOpen(it, done, tier)
      local sy, oy = py((tier - 1) / 4)
      local rl = text(mGrid, ({ "I", "II", "III", "IV" })[tier], UDim2.new(0, tierW, 0.25, -rowGap - headH / 4), UDim2.new(0, 0, sy, oy), 15, open and WHITE or FAINT, Enum.TextXAlignment.Center)
      rl.Font = Enum.Font.GothamBold
      for ci, c in ipairs(cols) do
        local list = {}
        for _, m in ipairs(WM.list(it)) do if m.tier == tier and m.cls == c then table.insert(list, m) end end
        for mi, m in ipairs(list) do
          local isDone, isCur = done[m.key] == true, md.cur == m.key
          local can = WM.canResearch(it, done, m.key)
          local bg = isDone and RGB(38, 74, 50) or (isCur and RGB(104, 84, 30)) or (can and RGB(36, 40, 46)) or RGB(20, 22, 25)
          local w = 1 / nC / #list
          local cell = Instance.new("TextButton")
          cell.Name = "Mod_" .. m.key
          cell.AutoButtonColor = can and not isDone
          cell.Text = ""
          cell.BackgroundColor3, cell.BackgroundTransparency, cell.BorderSizePixel = bg, 0.05, 0
          local sx, ox = px((ci - 1) / nC + (mi - 1) * w)
          cell.Size = UDim2.new(w, -colGap - tierW * w, 0.25, -rowGap - headH / 4)
          cell.Position = UDim2.new(sx, ox, sy, oy)
          cell.Parent = mGrid
          local cs = Instance.new("UIStroke")
          cs.Color = isCur and GOLD or (isDone and GOOD or RGB(70, 76, 80))
          cs.Transparency = (isCur or isDone) and 0.2 or 0.6
          cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
          cs.Parent = cell
          text(cell, zh and m.zh or m.en, UDim2.new(1, -12, 0, 18), UDim2.new(0, 8, 0, 6), 13, (can or isDone) and WHITE or FAINT)
          local dsc = text(cell, zh and m.dz or m.de, UDim2.new(1, -12, 1, -48), UDim2.new(0, 8, 0, 26), 11, (can or isDone) and DIM or FAINT)
          dsc.TextWrapped, dsc.TextTruncate, dsc.TextYAlignment = true, Enum.TextTruncate.AtEnd, Enum.TextYAlignment.Top
          local cost = WM.cost(it, m)
          local st = isDone and L("已装上", "Installed") or (isCur and (L("研究中 ", "Researching ") .. (md.rp or 0) .. " / " .. cost))
            or (can and (L("点一下研究 · ", "Click to research · ") .. cost)) or (L("还没开 · ", "Locked · ") .. cost)
          text(cell, st, UDim2.new(1, -12, 0, 16), UDim2.new(0, 8, 1, -20), 11, isDone and GOOD or (isCur and GOLD or FAINT)).Name = "State"
          if isCur then   -- 进度条
            local bar = frame(cell, UDim2.new(math.clamp((md.rp or 0) / math.max(cost, 1), 0, 1), 0, 0, 3), UDim2.new(0, 0, 1, -3), GOLD, 0)
            bar.Name = "Bar"
          end
          if can and not isDone then
            cell.MouseButton1Click:Connect(function() act("treeMod", it.key, m.key) end)
          end
        end
      end
    end
  end
  local function openMods(it)
    modsIt = it
    modsP.Visible = true
    refreshMods()
  end
  G.openMods = openMods

  ---------------------------------------------------------------- 资料卡、装甲查看器（详情里「资料卡」）：左边 3D 车模按装甲厚度上色（拖动转、滚轮缩放），
  --   右边性能：极速、炮塔转速 / 俯仰、各处装甲（动能 / 破甲毫米）、主炮每种弹的初速和 0 / 500 / 1000 / 2000 米穿深；飞机写速度、挂载
  local infoP = frame(gui, UDim2.fromScale(1, 1), nil, RGB(2, 3, 4), 0.35)
  infoP.Name = "Info"
  infoP.Visible = false
  infoP.ZIndex = 10
  G.infoGui = infoP   -- 测试用
  local iCard = frame(infoP, UDim2.fromScale(0.96, 0.9), UDim2.fromScale(0.5, 0.5), RGB(12, 14, 17), 0.03)
  iCard.AnchorPoint = Vector2.new(0.5, 0.5)
  local iFit = Instance.new("UISizeConstraint")
  iFit.MaxSize = Vector2.new(1060, 640)
  iFit.Parent = iCard
  local iSt = Instance.new("UIStroke")
  iSt.Color, iSt.Transparency = RGB(90, 96, 100), 0.5
  iSt.Parent = iCard
  local iTitle = text(iCard, "", UDim2.new(1, -140, 0, 30), UDim2.new(0, 18, 0, 14), 20)
  iTitle.Font = Enum.Font.GothamBold
  local iSub = text(iCard, "", UDim2.new(1, -150, 0, 18), UDim2.new(0, 18, 0, 46), 12, DIM)
  local iClose = button(iCard, L("关闭", "Close"), UDim2.new(0, 100, 0, 32), UDim2.new(1, -118, 0, 14))
  iClose.MouseButton1Click:Connect(function() infoP.Visible = false end)
  local vp = Instance.new("ViewportFrame")
  vp.Name = "ArmorView"
  vp.Size, vp.Position = UDim2.new(0.56, -24, 1, -138), UDim2.new(0, 18, 0, 74)
  vp.BackgroundColor3, vp.BorderSizePixel = RGB(16, 18, 21), 0
  vp.Ambient, vp.LightColor, vp.LightDirection = RGB(128, 132, 138), RGB(255, 250, 240), Vector3.new(-0.45, -1, -0.55)
  vp.Parent = iCard
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 38
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local vpNote = text(vp, "", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 1, -26), 12, FAINT)
  -- 图例：装甲厚度 → 颜色
  local RAMP = { { 15, RGB(60, 120, 200) }, { 40, RGB(56, 168, 160) }, { 80, RGB(92, 190, 92) }, { 150, RGB(206, 200, 72) },
    { 300, RGB(232, 150, 52) }, { 600, RGB(222, 72, 52) }, { 1e9, RGB(168, 42, 132) } }
  local function rampCol(mm)
    for _, r in ipairs(RAMP) do if mm <= r[1] then return r[2] end end
    return RAMP[#RAMP][2]
  end
  local legend = frame(iCard, UDim2.new(0.56, -24, 0, 26), UDim2.new(0, 18, 1, -58), nil, 1)
  for i, r in ipairs(RAMP) do
    frame(legend, UDim2.new(1 / #RAMP, -4, 0, 8), UDim2.new((i - 1) / #RAMP, 0, 0, 0), r[2], 0)
    text(legend, (i < #RAMP) and ("≤ " .. r[1]) or "> 600", UDim2.new(1 / #RAMP, -4, 0, 14), UDim2.new((i - 1) / #RAMP, 0, 0, 11), 10, DIM, Enum.TextXAlignment.Center)
  end
  local keBtn = button(iCard, L("对动能弹", "vs KE"), UDim2.new(0, 96, 0, 26), UDim2.new(0, 18, 1, -30), true)
  local ceBtn = button(iCard, L("对破甲弹", "vs HEAT"), UDim2.new(0, 96, 0, 26), UDim2.new(0, 120, 1, -30))
  keBtn.Name, ceBtn.Name = "KE", "CE"
  local stats = Instance.new("ScrollingFrame")
  stats.Name = "Stats"
  stats.Size, stats.Position = UDim2.new(0.44, -18, 1, -90), UDim2.new(0.56, 0, 0, 74)
  stats.BackgroundTransparency, stats.BorderSizePixel, stats.ScrollBarThickness = 1, 0, 5
  stats.CanvasSize = UDim2.new()
  stats.Parent = iCard
  local av = { yaw = math.pi - 0.75, pitch = 0.32, dist = 40, ce = false, it = nil, drag = false }
  -- 一块零件在哪一区：炮塔 / 炮的按炮塔的长宽分正面、侧面（前半截 sf）、后面、顶上；车体按车长车宽分；底下的悬挂、轮子不算
  local function zoneOf(d, tp, grp, pos)
    if grp == "wheel" or grp == "seg" then return nil end
    if grp == "gun" then return "tur", "f" end
    if grp == "turret" or grp == "rws" or grp == "rwg" or grp == "kit" then
      local ts = (d.turret and d.turret.size) or Vector3.new(7, 2, 7)
      local tz, tx = (pos.Z - tp.Z) / math.max(ts.Z / 2, 0.5), (pos.X - tp.X) / math.max(ts.X / 2, 0.5)
      if tz < -0.4 then return "tur", "f" elseif tz > 0.55 then return "tur", "r" elseif math.abs(tx) > 0.6 then return "tur", (tz < 0) and "sf" or "s" end
      return "tur", "t"
    end
    if pos.Y < (d.clear or 1) + 0.6 then return nil end
    local nz, nx = pos.Z / math.max((d.L or 20) / 2, 0.5), pos.X / math.max((d.W or 10) / 2, 0.5)
    if nz < -0.55 then return "hull", "f" elseif nz > 0.6 then return "hull", "r" elseif math.abs(nx) > 0.72 then return "hull", "s" end
    return "hull", "t"
  end
  local function armorMM(prof, zone, face, ce)
    local z = prof[zone] or prof.hull
    local f = z and (z[face] or ((face == "sf") and z.s) or z.f)
    return f and f[ce and 2 or 1] or nil
  end
  local function clearView()
    for _, c in ipairs(vp:GetChildren()) do if c ~= vcam and c ~= vpNote then c:Destroy() end end
  end
  local function buildView(it)
    clearView()
    vpNote.Text = ""
    local d = VD.get(it.play)
    if not d then   -- 飞机：只看外形
      vpNote.Text = L("飞机没有分区装甲：这里只看外形", "Aircraft: no armor zones, shape only")
      local AD2 = AD.get(it.play)
      local okA, AM = pcall(function() return require(script.Parent:WaitForChild("AirModels", 2)) end)
      if AD2 and okA and AM then
        local okB, M = pcall(AM.build, AD2, "atk", AD.presetLoad(AD2))
        if okB and M and M.model then
          pcall(AM.pose, M, CFrame.new(), { gear = 1, thr = 0 }, os.clock())
          M.model.Parent = vp
          av.d = { L = (AD2.hitbox and AD2.hitbox.Z) or 50, W = (AD2.hitbox and AD2.hitbox.X) or 40, H = (AD2.hitbox and AD2.hitbox.Y) or 12 }
          av.dist = math.max(av.d.L, av.d.W) * 1.6
        end
      end
      return
    end
    local okB, M = pcall(VM.build, d, "atk", nil, TT.paint(it))
    if not okB or not M then return end
    local tp = VM.pose(M, d)
    local prof = WD.prof(d)
    for _, x in ipairs(M.parts) do
      local p, grp = x[1], x[2]
      if p:IsA("BasePart") then
        for _, c in ipairs(p:GetChildren()) do
          if c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("ParticleEmitter") or c:IsA("Light") then c:Destroy() end
        end
        pcall(function() p.TextureID = "" end)
        p.Material = Enum.Material.SmoothPlastic
        local zone, face = zoneOf(d, tp, grp, p.CFrame.Position)
        local mm = zone and armorMM(prof, zone, face, av.ce)
        p.Color = mm and rampCol(mm) or RGB(64, 66, 70)
      end
    end
    M.model.Parent = vp
    av.d = d
    av.dist = math.max(d.L or 20, d.W or 10) * 1.75
    vpNote.Text = L("拖动转、滚轮缩放 · 颜色是这一处的装甲厚度", "Drag to rotate, wheel to zoom · color = armor at that spot")
  end
  local function placeCam()
    local d = av.d
    if not d then return end
    local c = Vector3.new(0, (d.H or 6) * 0.45, 0)
    local cp = math.cos(av.pitch)
    local dir = Vector3.new(math.sin(av.yaw) * cp, math.sin(av.pitch), math.cos(av.yaw) * cp)
    vcam.CFrame = CFrame.lookAt(c + dir * av.dist, c)
  end
  vp.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then av.drag = true end
  end)
  vp.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then av.drag = false end
  end)
  vp.InputChanged:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseWheel then
      av.dist = math.clamp(av.dist * (1 - 0.1 * io.Position.Z), 8, 400)
    elseif av.drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
      av.yaw -= io.Delta.X * 0.01
      av.pitch = math.clamp(av.pitch + io.Delta.Y * 0.008, -0.2, 1.3)
    end
  end)
  RunService.RenderStepped:Connect(function(dt)
    if not infoP.Visible then return end
    if not av.drag then av.yaw += (dt or 0.016) * 0.22 end   -- 不拖的时候慢慢转
    placeCam()
  end)
  local function statRows(it)
    local rows = {}
    local function add(s, col, ts) table.insert(rows, { s, col or DIM, ts or 13 }) end
    local function T2(k) return G.T and G.T(k) or k end
    if it.stand then add(L("还没有自己的模型：模型和性能暂用 ", "No model yet: model & stats from ") .. vname(it.play), GOLD, 12)
    elseif it.model then add(L("模型暂用同族的 ", "Model borrowed from ") .. vname(it.model) .. L("（性能是本车的）", " (own stats)"), GOLD, 12) end
    local d = VD.get(it.play)
    if d then
      add(L("机动", "Mobility"), WHITE, 15)
      add(L("公路极速 ", "Top speed ") .. math.floor((d.speed or 0) / 2.8 * 3.6 + 0.5) .. " km/h")
      if d.turret then
        local el = d.turret.elev
        add(L("炮塔转速 ", "Turret traverse ") .. (d.turret.trav or 0) .. " °/s   ·   " .. L("俯仰 ", "Elevation ") .. (el and (el[1] .. "° / +" .. el[2] .. "°") or "—"))
      end
      local prof = WD.prof(d)
      add(L("装甲（毫米：对动能弹 / 对破甲弹）", "Armor (mm: vs KE / vs HEAT)"), WHITE, 15)
      for _, f in ipairs({ { "tur", "f", L("炮塔正面", "Turret front") }, { "tur", "s", L("炮塔侧面", "Turret side") }, { "tur", "r", L("炮塔后面", "Turret rear") },
        { "hull", "f", L("车体正面", "Hull front") }, { "hull", "s", L("车体侧面", "Hull side") }, { "hull", "r", L("车体后面", "Hull rear") }, { "hull", "t", L("顶上", "Roof") } }) do
        local z = prof[f[1]]
        local a = z and z[f[2]]
        if a then add(f[3] .. "   " .. a[1] .. " / " .. a[2]) end
      end
      add(L("武器", "Weapons"), WHITE, 15)
      for _, wid in ipairs(d.weapons or {}) do
        add(T2("vw." .. wid), WHITE, 13)
        for _, k in ipairs(BAL.GUN[wid] or {}) do
          local a, pa = BAL.AMMO[k], WD.AMMO[k]
          if a then
            local pens = {}
            for _, m in ipairs({ 0, 500, 1000, 2000 }) do
              local p0 = pa and pa.p0 or 0
              table.insert(pens, math.floor(pa and pa.fall and math.max(p0 * 0.4, p0 - pa.fall * m / 1000) or p0))
            end
            add("   " .. (a.name or k) .. " · " .. (a.v0 or 0) .. " m/s · " .. L("穿深 ", "pen ") .. table.concat(pens, " / ") .. " mm", DIM, 12)
          end
        end
      end
      add(L("（穿深：0 / 500 / 1000 / 2000 米）", "(pen at 0 / 500 / 1000 / 2000 m)"), FAINT, 11)
    else
      local a = AD.get(it.play)
      if a then
        local k = 3.6 / (AD.M or 2.8)
        add(L("性能", "Performance"), WHITE, 15)
        if a.vMax then add(L("最大速度（加力）", "Max speed (AB) ") .. math.floor(a.vMax * k + 0.5) .. " km/h") end
        if a.vMil then add(L("最大速度（军推）", "Max speed (mil) ") .. math.floor(a.vMil * k + 0.5) .. " km/h") end
        if a.stall then add(L("失速速度 ", "Stall speed ") .. math.floor(a.stall * k + 0.5) .. " km/h") end
        add(L("默认挂载", "Default loadout"), WHITE, 15)
        local okG, list = pcall(AD.groups, a, AD.presetLoad(a))
        for _, wid in ipairs(okG and list or {}) do add("   " .. T2("aw." .. wid), DIM, 12) end
      end
    end
    -- 这辆车现在的改装、乘员（买下了才有）
    local md = tree.mods and tree.mods[it.key]
    if TT.owned(tree, it.key) then
      local nDone, nAll = WM.count(it, md and md.done)
      add(L("改装 ", "Modifications ") .. nDone .. " / " .. nAll .. L("（研究完的效果出车时生效）", " (researched ones apply when you deploy)"), GOOD, 12)
    end
    return rows
  end
  local function refreshInfo()
    local it = av.it
    if not it then return end
    iTitle.Text = nm(it) .. L("  ·  资料卡", "  ·  Stats")
    iSub.Text = TT.NAT[it.nat].name .. " · " .. TT.RANKS[it.rank].roman .. " · BR " .. TT.brText(it.br) .. " · " .. it.year
    keBtn.BackgroundColor3, ceBtn.BackgroundColor3 = av.ce and RGB(30, 34, 38) or WHITE, av.ce and WHITE or RGB(30, 34, 38)
    keBtn.TextColor3, ceBtn.TextColor3 = av.ce and WHITE or RGB(10, 10, 10), av.ce and RGB(10, 10, 10) or WHITE
    buildView(it)
    clear(stats)
    local y = 0
    for _, r in ipairs(statRows(it)) do
      local h = r[3] + 8
      local t = text(stats, r[1], UDim2.new(1, -10, 0, h), UDim2.new(0, 0, 0, y), r[3], r[2])
      t.TextWrapped, t.TextTruncate = true, Enum.TextTruncate.None
      y += h + 2
    end
    stats.CanvasSize = UDim2.new(0, 0, 0, y + 10)
  end
  keBtn.MouseButton1Click:Connect(function() av.ce = false refreshInfo() end)
  ceBtn.MouseButton1Click:Connect(function() av.ce = true refreshInfo() end)
  local function openInfo(it)
    av.it = it
    av.yaw, av.pitch = math.pi - 0.75, 0.32
    infoP.Visible = true
    refreshInfo()
  end
  G.openInfo = openInfo

  -- 结算页那一行（WtBattle.lua 结算页里调；服务器 Tech.lua treeAward 写的 t.last）：研究点、倍率、记在哪辆上、改装、乘员经验
  local MODE_NM = { [1] = L("街机", "Arcade") }
  G.treeResultText = function()
    local last = tree and tree.last
    if type(last) ~= "table" or not last.rp then return "" end
    local S = G.S
    if S and S.round and last.n and last.n ~= S.round then return "" end
    local parts = {}
    local mk = last.mk or 1
    table.insert(parts, L("研究点 +", "RP +") .. last.rp .. ((mk ~= 1) and (L("（模式 ×", " (mode ×") .. mk .. L("）", ")")) or ""))
    for _, c in ipairs(last.cur or {}) do
      local it = TT.get(c.k)
      if it then table.insert(parts, nm(it) .. " " .. math.min(c.rp, c.need) .. " / " .. c.need) end
    end
    for k, m in pairs(last.mods or {}) do
      local it = TT.get(k)
      if it then
        local s = nm(it) .. L(" 改装 +", " mods +") .. (m.g or 0)
        local fin = {}
        for _, mkey in ipairs(m.fin or {}) do
          local mm = WM.get(it, mkey)
          if mm then table.insert(fin, zh and mm.zh or mm.en) end
        end
        if #fin > 0 then s ..= L("（研究完：", " (done: ") .. table.concat(fin, L("、", ", ")) .. L("）", ")") end
        table.insert(parts, s)
      end
    end
    local cx = 0
    for _, x in pairs(last.crew or {}) do cx = math.max(cx, x) end
    if cx > 0 then table.insert(parts, L("乘员经验 +", "Crew XP +") .. cx) end
    return table.concat(parts, "   ·   ")
  end

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
      line(L("还没有自己的模型：暂用 ", "No model yet: uses ") .. vname(base) .. L(" 的模型和性能", "'s model & stats"), 12, RGB(200, 170, 90), 34)
    elseif it.model then
      line(L("模型暂用同族的 ", "Model from ") .. vname(it.model) .. L("；炮、弹、装甲、机动按本车", "; gun, ammo, armour and mobility are its own"), 12, RGB(170, 185, 150), 34)
    end
    y += 8
    local function btn(str, primary, f)
      local b = button(detail, str, UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 0, y), primary)
      b.MouseButton1Click:Connect(f)
      y += 46
      return b
    end
    btn(L("资料卡 · 装甲", "Stats · armor"), false, function() openInfo(it) end).Name = "InfoBtn"
    -- 试驾：随便哪一辆都能试（服务器 Tech.lua testDrive：东边单独一块场地、三辆靶车、改装全装；下车回机库）
    btn(L("试驾", "Test drive"), false, function()
      panel.Visible = false
      act("testDrive", it.key)
    end).Name = "TestBtn"
    if stt == "can" then
      btn(L("研究这一辆", "Research"), true, function() act("treeResearch", it.key) end).Name = "Research"
    elseif stt == "res" then
      btn(L("购买（", "Buy (") .. it.cost .. ")", true, function() act("treeBuy", it.key) end).Name = "Buy"
    elseif stt == "own" then
      local md = tree.mods and tree.mods[it.key]
      local nDone, nAll = WM.count(it, md and md.done)
      btn(L("改装（", "Modifications (") .. nDone .. " / " .. nAll .. L("）", ")"), false, function() openMods(it) end).Name = "ModsBtn"
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
      local n2 = text(card, "BR " .. TT.brText(it.br) .. "  " .. it.year .. (it.stand and L("  暂用", "  stand-in") or (it.model and L("  同族模型", "  family model")) or ""), UDim2.new(1, -12, 0, 16), UDim2.new(0, 6, 0, 24), 11, DIM)
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
    if modsP.Visible then refreshMods() end
    if crewP.Visible then refreshCrew() end
    if hangar.Visible then refreshHangar() end
  end)
end

return TechUI
