-- Roblox全面大战场（客户端）——单兵战术平板（用户：增加一个单兵战术平板，可以召唤空投载具、空中打击，但必须要有次数限制）
--   步行时按 B（手机：右边「平板」按钮）拿出来：人端着平板（服务器 Air.lua 的 G.uavTablet，别人看得到），手里的枪先收起；画面中间一块加固平板——
--     左边一列支援：空投载具、空投补给、精确打击、机炮扫射、集束轰炸（Config.TacPad），每样这一局还剩几次（圆点）、冷却还有多久
--       （次数、冷却都是服务器 Tactical.lua 管的，随状态发来 G.S.tac）；1–5 选、或者点卡片；
--     右边是群岛地图（借 MapUI 那张图，以自己为中心放大；滚轮缩放、右键拖动），一圈呼叫范围；左键点目标，
--       扫射、轰炸画出顺着「自己 → 目标」方向的覆盖带；「确认呼叫」（Enter）发给服务器核对，过了平板自动收起，抬头看飞机飞过来；没过就在平板上写原因
--   飞机、落下来的货盘和炸弹是这里画的（Fx 的 tac 特效，所有人都看得到；伤害、生成车和补给箱是服务器的事）：
--     精确打击：战斗机高空飞过、放下一枚激光制导炸弹（目标上一个闪烁的激光照射点，呼叫的人那里一道照射光束——夜视里看得清）；
--     机炮扫射：攻击机俯冲下来，一串曳光弹扫到地上；集束轰炸：轰炸机沿方向飞过，炸弹一枚枚落下；
--     空投：运输直升机低空飞来，货盘挂伞落下（载具是三顶伞的重装平台），落地那一刻换成服务器生成的车 / 补给箱
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local TacPad = {}

function TacPad.init(G)
  local TP = G.Config.TacPad
  if not TP then return end
  local AD = require(RS:WaitForChild("AirDefs"))
  local WM = require(RS:WaitForChild("WeaponModels"))
  local MapM = require(RS:WaitForChild("Map"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local UDs, UDo, UD = UDim2.fromScale, UDim2.fromOffset, UDim2.new
  local V2, V = Vector2.new, Vector3.new
  local CF = CFrame.new
  local UPV = V(0, 1, 0)
  local function T(k, ...) return G.T(k, ...) end
  local mob = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local AL, AC, AR = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
  local M_PER = 2.8   -- 1 米多少格（同 Hud.lua）
  local ORDER = TP.order

  -- 配色：深色、去饱和，选中的一样用琥珀色点一下（用户：精致、简洁，不要卡通）
  local TEXT, DIM, FAINT = RGB(226, 232, 228), RGB(140, 149, 145), RGB(82, 90, 88)
  local AMBER, RED, GOOD = RGB(255, 196, 92), RGB(255, 94, 78), RGB(128, 222, 156)
  local SHELL, RUBBER = RGB(46, 49, 44), RGB(23, 25, 23)
  local SCREEN, CARD, CARD_ON, OFF = RGB(8, 11, 12), RGB(15, 19, 20), RGB(27, 32, 33), RGB(30, 34, 34)

  -- 平板按设计尺寸（像素）摆，整块用 UIScale 缩到屏幕上（电脑 1120 × 700；手机横屏扁一些、卡片矮一些、不写说明）
  local DW, DH = 1120, 700
  local BL, BT, BR, BB = 36, 40, 36, 52   -- 外壳边：左、上、右、下
  local LW, CH, CG = 336, 74, 8           -- 左列宽、卡片高、卡片间距
  if mob then DW, DH, BL, BT, BR, BB, LW, CH, CG = 900, 428, 18, 14, 18, 14, 286, 46, 5 end
  local SW, SH = DW - BL - BR, DH - BT - BB
  local TOP = mob and 24 or 30            -- 屏幕顶上状态栏
  local VX, VY = LW, TOP + 12             -- 地图区
  local VW, VH = SW - LW - 12, SH - TOP - 24

  local function fr(parent, pos, size, col, tr)
    local f = Instance.new("Frame")
    f.Position, f.Size = pos, size
    f.BackgroundColor3 = col or RGB(0, 0, 0)
    f.BackgroundTransparency = tr or 0
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
  end
  local function corner(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = (typeof(r) == "UDim") and r or UDim.new(0, r)
    c.Parent = f
    return c
  end
  local function stroke(f, col, th, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = col, th, tr or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function shade(f, a, b, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(Color3.new(a, a, a), Color3.new(b, b, b))
    g.Rotation = rot
    g.Parent = f
    return g
  end
  local function txt(parent, text, pos, size, ts, col, font, ax, anchor)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position, l.Size = pos, size
    l.AnchorPoint = anchor or V2(0, 0)
    l.Text = text or ""
    l.TextSize = ts
    l.TextColor3 = col
    l.Font = font or Enum.Font.Gotham
    l.TextXAlignment = ax or AL
    l.Parent = parent
    return l
  end
  local function seg(parent, a, b, th, col, tr)   -- 两点之间一条线（设计像素）
    local d = b - a
    local f = fr(parent, UDo((a.X + b.X) / 2, (a.Y + b.Y) / 2), UDo(math.max(1, d.Magnitude), th), col, tr)
    f.AnchorPoint = V2(0.5, 0.5)
    f.Rotation = math.deg(math.atan2(d.Y, d.X))
    return f
  end

  ---------------------------------------------------------------- 外壳

  local gui = Instance.new("ScreenGui")
  gui.Name = "TacPad"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.DisplayOrder = 6   -- 盖在主界面、载具平显（5）上面；选阵营、主菜单（12、14）还在它上面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local dimBg = fr(gui, UDs(0, 0), UDs(1, 1), RGB(0, 0, 0), 1)   -- 四周压暗（拿出平板时淡入）
  local modal = Instance.new("TextButton")   -- 第一人称里把鼠标放出来点地图
  modal.Name = "Modal"
  modal.Modal = true
  modal.BackgroundTransparency = 1
  modal.Text = ""
  modal.Size = UDo(1, 1)
  modal.Parent = gui

  local dev = fr(gui, UD(0.5, 0, 0.5, 0), UDo(DW, DH), RGB(0, 0, 0), 1)
  dev.Name = "Device"
  dev.AnchorPoint = V2(0.5, 0.5)
  local scale = Instance.new("UIScale")
  scale.Parent = dev

  local shell = fr(dev, UDs(0, 0), UDs(1, 1), SHELL)
  corner(shell, mob and 18 or 30)
  shade(shell, 1.0, 0.72, 90)
  stroke(shell, RGB(14, 15, 14), 2)
  local sheen = fr(dev, UDo(40, 3), UD(1, -80, 0, 2), RGB(255, 255, 255), 0.9)   -- 上沿一道反光
  corner(sheen, 1)
  if not mob then
    -- 四个角的橡胶护角（屏幕玻璃压在上面，只露出外壳角上一圈 L 形）
    for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
      local b = fr(dev, UD(c[1], (c[1] == 0) and -6 or 6, c[2], (c[2] == 0) and -6 or 6), UDo(104, 104), RUBBER)
      b.AnchorPoint = V2(c[1], c[2])
      corner(b, 34)
      shade(b, 1.0, 0.7, 90)
      stroke(b, RGB(10, 11, 10), 1.5)
    end
    -- 两侧橡胶握条（一道道横纹）
    for _, x in ipairs({ 8, DW - 8 - 18 }) do
      local g = fr(dev, UDo(x, DH * 0.33), UDo(18, DH * 0.34), RUBBER)
      corner(g, 8)
      for i = 1, 13 do fr(g, UD(0.22, 0, i / 14, 0), UD(0.56, 0, 0, 2), RGB(40, 43, 40)) end
    end
  end
  -- 顶边：前置摄像头、两个指示灯
  local lens = fr(dev, UD(0.5, -6, 0, BT / 2 - 6), UDo(12, 12), RGB(5, 6, 8))
  corner(lens, 6)
  stroke(lens, RGB(72, 76, 72), 1.5)
  local leds = {}
  if not mob then
    for i, nm in ipairs({ "GPS", "LINK" }) do
      local x = BL + 70 + (i - 1) * 64
      local led = fr(dev, UDo(x, BT / 2 - 3), UDo(6, 6), GOOD)
      corner(led, 3)
      txt(dev, nm, UDo(x + 12, BT / 2 - 7), UDo(50, 14), 10, RGB(150, 156, 150), Enum.Font.GothamMedium)
      leds[nm] = led
    end
  end
  -- 底边：牌子、硬键（键帽上印键位）
  local brand = txt(dev, "", UDo(BL + 4, DH - BB / 2 - 8), UDo(360, 16), 11, RGB(128, 134, 126), Enum.Font.GothamBold)
  brand.Visible = not mob
  local capLabels = {}
  if not mob then
    local caps = { { "1–5", "tac.kSel" }, { "ENTER", "tac.kCall" }, { "B", "tac.kClose" } }
    local x = DW - BR
    for i = #caps, 1, -1 do
      local c = caps[i]
      local w = 22 + #c[1] * 6
      x -= w
      local cap = fr(dev, UDo(x, DH - BB / 2 - 11), UDo(w, 22), RGB(28, 30, 28))
      corner(cap, 5)
      stroke(cap, RGB(78, 82, 76), 1)
      local l = txt(cap, c[1], UDs(0, 0), UDs(1, 1), 11, TEXT, Enum.Font.GothamBold, AC)
      l.TextYAlignment = Enum.TextYAlignment.Center
      local lab = txt(dev, "", UDo(x - 6, DH - BB / 2 - 7), UDo(70, 14), 11, RGB(130, 136, 128), Enum.Font.GothamMedium, AR, V2(1, 0))
      capLabels[#capLabels + 1] = { lab, c[2] }
      x -= 84
    end
  end

  -- 屏幕：黑玻璃边、显示区、一道细反光
  local glassF = fr(dev, UDo(BL - 7, BT - 7), UDo(SW + 14, SH + 14), RGB(4, 5, 6))
  corner(glassF, mob and 10 or 16)
  local scr = fr(dev, UDo(BL, BT), UDo(SW, SH), SCREEN)
  scr.Name = "Screen"
  corner(scr, mob and 6 or 9)
  scr.ClipsDescendants = true
  local edge = fr(dev, UDo(BL, BT), UDo(SW, SH), RGB(0, 0, 0), 1)
  corner(edge, mob and 6 or 9)
  stroke(edge, RGB(120, 130, 130), 1, 0.8)

  -- 状态栏
  local bar = fr(scr, UDs(0, 0), UD(1, 0, 0, TOP), RGB(0, 0, 0), 0.45)
  local title = txt(bar, "", UDo(14, 0), UD(0, 320, 1, 0), mob and 12 or 13, TEXT, Enum.Font.GothamBold)
  local coord = txt(bar, "", UDs(0.5, 0), UD(0, 300, 1, 0), mob and 11 or 12, DIM, Enum.Font.Code, AC, V2(0.5, 0))
  local clock = txt(bar, "", UD(1, -14, 0, 0), UD(0, 280, 1, 0), mob and 11 or 12, TEXT, Enum.Font.Code, AR, V2(1, 0))
  fr(scr, UDo(0, TOP), UD(1, 0, 0, 1), RGB(255, 255, 255), 0.92)
  local bat = math.random(72, 96)

  ---------------------------------------------------------------- 左列：支援卡片

  -- 卡片上的小图标（几条线、几个方块拼的，同一个颜色）
  local function icon(box, kind)
    local s = box.Size.X.Offset
    local o = fr(box, UDs(0, 0), UDs(1, 1), RGB(0, 0, 0), 1)
    local parts = {}
    local function add(f) parts[#parts + 1] = f return f end
    local k = s / 44
    if kind == "drop" or kind == "supply" then   -- 伞 + 吊着的箱子
      local dome = add(fr(o, UDo(10 * k, 7 * k), UDo(24 * k, 9 * k), TEXT))
      corner(dome, UDim.new(0.5, 0))
      add(seg(o, V2(12 * k, 13 * k), V2(19 * k, 27 * k), 1.5, TEXT))
      add(seg(o, V2(32 * k, 13 * k), V2(25 * k, 27 * k), 1.5, TEXT))
      local w = (kind == "drop") and 14 or 10
      add(fr(o, UDo(22 * k - w * k / 2, 27 * k), UDo(w * k, 9 * k), TEXT))
    elseif kind == "pgm" then   -- 准星：圈 + 四个刻 + 中心点
      local ring = fr(o, UDo(11 * k, 11 * k), UDo(22 * k, 22 * k), RGB(0, 0, 0), 1)
      corner(ring, UDim.new(0.5, 0))
      parts[#parts + 1] = stroke(ring, TEXT, 1.5)
      add(fr(o, UDo(21 * k, 5 * k), UDo(2, 8 * k), TEXT))
      add(fr(o, UDo(21 * k, 31 * k), UDo(2, 8 * k), TEXT))
      add(fr(o, UDo(5 * k, 21 * k), UDo(8 * k, 2), TEXT))
      add(fr(o, UDo(31 * k, 21 * k), UDo(8 * k, 2), TEXT))
      local dot = add(fr(o, UDo(20 * k, 20 * k), UDo(4 * k, 4 * k), TEXT))
      corner(dot, UDim.new(0.5, 0))
    elseif kind == "gunrun" then   -- 一串斜着的曳光
      for i = 0, 3 do
        local a = V2((8 + i * 7) * k, (12 + i * 6) * k)
        add(seg(o, a, a + V2(6 * k, 5 * k), 2, TEXT))
      end
      add(seg(o, V2(10 * k, 36 * k), V2(36 * k, 36 * k), 1, TEXT, 0.5))
    else   -- 集束：两行炸点
      for r = 0, 1 do
        for c = 0, 2 do
          local d = add(fr(o, UDo((9 + c * 10 + r * 5) * k, (14 + r * 11) * k), UDo(6 * k, 6 * k), TEXT))
          corner(d, UDim.new(0.5, 0))
        end
      end
    end
    return function(col)
      for _, p in ipairs(parts) do
        if p:IsA("UIStroke") then p.Color = col else p.BackgroundColor3 = col end
      end
    end
  end

  local sel = ORDER[1]
  local cards = {}
  local IB = mob and 32 or 44
  local NX = (mob and 8 or 12) + IB + 12
  for i, id in ipairs(ORDER) do
    local it = TP.items[id]
    local y = TOP + 12 + (i - 1) * (CH + CG)
    local b = Instance.new("TextButton")
    b.Name = "Card_" .. id
    b.AutoButtonColor = false
    b.Text = ""
    b.BackgroundColor3 = CARD
    b.BorderSizePixel = 0
    b.Position, b.Size = UDo(12, y), UDo(LW - 24, CH)
    b.Parent = scr
    corner(b, 6)
    local st = stroke(b, RGB(255, 255, 255), 1, 0.93)
    local acc = fr(b, UDo(0, 8), UD(0, 3, 1, -16), AMBER)
    corner(acc, 1)
    local ib = fr(b, UDo(mob and 8 or 12, (CH - IB) / 2), UDo(IB, IB), RGB(23, 28, 29))
    corner(ib, 5)
    local paint = icon(ib, (it.kind == "drop") and "drop" or it.kind)
    if not mob then txt(ib, tostring(i), UD(1, -3, 1, -1), UDo(12, 12), 9, FAINT, Enum.Font.GothamBold, AR, V2(1, 1)) end
    local name = txt(b, "", UDo(NX, mob and 5 or 10), UDo(LW - 24 - NX - 96, 18), mob and 13 or 15, TEXT, Enum.Font.GothamBold)
    local state = txt(b, "", UD(1, -12, 0, mob and 5 or 10), UDo(96, 18), mob and 10 or 11, DIM, Enum.Font.GothamMedium, AR, V2(1, 0))
    if mob then state.Position, state.AnchorPoint, state.TextXAlignment = UDo(NX, 24), V2(0, 0), AL end
    local desc
    if not mob then
      desc = txt(b, "", UDo(NX, 31), UDo(LW - 24 - NX - 50, 32), 11, DIM, Enum.Font.Gotham)
      desc.TextWrapped = true
      desc.TextYAlignment = Enum.TextYAlignment.Top
    end
    local pips = {}
    for k = 1, it.n do
      local p = fr(b, UD(1, -12 - (it.n - k) * 11, 1, mob and -19 or -14), UDo(7, 7), TEXT)
      p.AnchorPoint = V2(1, 1)
      corner(p, 4)
      pips[k] = p
    end
    local cdBar = fr(b, UD(0, 0, 1, -2), UD(0, 0, 0, 2), AMBER, 0.2)   -- 冷却进度（底边一道）
    b.Activated:Connect(function() sel = id end)
    cards[id] = { b = b, st = st, acc = acc, name = name, state = state, desc = desc, pips = pips, cd = cdBar, paint = paint }
  end

  -- 选中那一样的详情 + 呼叫按钮
  local DY = TOP + 12 + #ORDER * (CH + CG) + (mob and 0 or 4)
  local det = fr(scr, UDo(12, DY), UDo(LW - 24, SH - DY - 12), RGB(0, 0, 0), 1)
  local dName = txt(det, "", UDo(2, 0), UD(1, -4, 0, 22), 18, TEXT, Enum.Font.GothamBold)
  local dInfo = txt(det, "", UDo(2, 26), UD(1, -4, 0, 16), 12, DIM, Enum.Font.Gotham)
  local dTgt = txt(det, "", UDo(2, mob and 0 or 50), UD(1, -4, 0, 16), mob and 12 or 13, TEXT, Enum.Font.Code)
  local dWarn = txt(det, "", UDo(2, mob and 17 or 70), UD(1, -4, 0, 14), 11, RED, Enum.Font.GothamMedium)
  dName.Visible, dInfo.Visible = not mob, not mob
  local BTN_H = mob and 40 or 46
  local callBtn = Instance.new("TextButton")
  callBtn.Name = "Call"
  callBtn.AutoButtonColor = true
  callBtn.BorderSizePixel = 0
  callBtn.Position, callBtn.Size = UD(0, 0, 1, -BTN_H), UD(1, 0, 0, BTN_H)
  callBtn.Font = Enum.Font.GothamBold
  callBtn.TextSize = mob and 14 or 15
  callBtn.Parent = det
  corner(callBtn, 6)

  ---------------------------------------------------------------- 右边：地图

  local view = fr(scr, UDo(VX, VY), UDo(VW, VH), RGB(14, 24, 32))
  view.Name = "MapView"
  view.ClipsDescendants = true
  local holder = fr(view, UDs(0, 0), UDs(1, 1), RGB(0, 0, 0), 1)   -- 借来的地图挂在这里
  holder.ZIndex = 1
  local catcher = Instance.new("TextButton")   -- 接点击（盖在地图上面、标记下面）
  catcher.Name = "Catch"
  catcher.BackgroundTransparency = 1
  catcher.Text = ""
  catcher.AutoButtonColor = false
  catcher.Size = UDs(1, 1)
  catcher.ZIndex = 2
  catcher.Parent = view
  local over = fr(view, UDs(0, 0), UDs(1, 1), RGB(0, 0, 0), 1)
  over.ZIndex = 3
  local vEdge = fr(scr, UDo(VX, VY), UDo(VW, VH), RGB(0, 0, 0), 1)
  stroke(vEdge, RGB(255, 255, 255), 1, 0.88)

  -- 呼叫范围：一圈细线、圈里淡淡一层
  local ring = fr(over, UDs(0.5, 0.5), UDo(10, 10), RGB(255, 255, 255), 0.96)
  ring.AnchorPoint = V2(0.5, 0.5)
  corner(ring, UDim.new(0.5, 0))
  stroke(ring, TEXT, 1.5, 0.45)
  local ringLabel = txt(over, "", UDs(0.5, 0.5), UDo(160, 14), 11, DIM, Enum.Font.GothamMedium, AC, V2(0.5, 1))
  -- 自己 → 目标的连线、覆盖带、目标标记
  local path = fr(over, UDs(0.5, 0.5), UDo(10, 1.5), TEXT, 0.55)
  path.AnchorPoint = V2(0.5, 0.5)
  local strip = fr(over, UDs(0.5, 0.5), UDo(10, 10), AMBER, 0.8)
  strip.AnchorPoint = V2(0.5, 0.5)
  stroke(strip, AMBER, 1, 0.3)
  local blast = fr(over, UDs(0.5, 0.5), UDo(10, 10), AMBER, 0.82)
  blast.AnchorPoint = V2(0.5, 0.5)
  corner(blast, UDim.new(0.5, 0))
  local mark = fr(over, UDs(0.5, 0.5), UDo(26, 26), RGB(0, 0, 0), 1)
  mark.AnchorPoint = V2(0.5, 0.5)
  corner(mark, UDim.new(0.5, 0))
  local markS = stroke(mark, AMBER, 2)
  local ticks = {}
  for i, v in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local t = fr(mark, UD(0.5, v[1] * 19 - ((v[1] ~= 0) and 4 or 1), 0.5, v[2] * 19 - ((v[2] ~= 0) and 4 or 1)), UDo((v[1] ~= 0) and 8 or 2, (v[2] ~= 0) and 8 or 2), AMBER)
    ticks[i] = t
  end
  local markL = txt(over, "", UDs(0.5, 0.5), UDo(220, 16), 12, AMBER, Enum.Font.Code, AL, V2(0, 0.5))
  markL.TextStrokeTransparency = 0.4
  -- 北、比例尺、操作提示、状态
  local north = txt(over, "N", UD(1, -14, 0, 10), UDo(20, 16), 13, TEXT, Enum.Font.GothamBold, AC, V2(1, 0))
  local nTick = fr(over, UD(1, -24, 0, 6), UDo(2, 5), TEXT)
  nTick.AnchorPoint = V2(0.5, 0)
  local _ = north
  local sbar = fr(over, UD(0, 14, 1, -18), UDo(80, 2), TEXT, 0.15)
  local sbarL = fr(sbar, UDo(0, -4), UDo(1.5, 6), TEXT)
  local sbarR = fr(sbar, UD(1, -1.5, 0, -4), UDo(1.5, 6), TEXT)
  local _ = sbarL, sbarR
  local sText = txt(over, "", UD(0, 14, 1, -36), UDo(120, 14), 11, TEXT, Enum.Font.Code)
  local hint = txt(over, "", UD(1, -14, 1, -12), UDo(360, 14), 11, DIM, Enum.Font.Gotham, AR, V2(1, 1))
  local pill = fr(over, UD(0.5, 0, 0, 12), UDo(360, 26), RGB(0, 0, 0), 0.25)
  pill.AnchorPoint = V2(0.5, 0)
  corner(pill, 4)
  local pillT = txt(pill, "", UDs(0, 0), UDs(1, 1), 13, TEXT, Enum.Font.GothamMedium, AC)
  pill.Visible = false
  -- 缩放按钮（右下）
  local zoomBtns = {}
  for i, s in ipairs({ "+", "−" }) do
    local b = Instance.new("TextButton")
    b.Name = "Zoom" .. i
    b.Text = s
    b.Font = Enum.Font.GothamBold
    b.TextSize = 18
    b.TextColor3 = TEXT
    b.BackgroundColor3 = RGB(0, 0, 0)
    b.BackgroundTransparency = 0.35
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.AnchorPoint = V2(1, 1)
    b.Position = UD(1, -12, 1, -34 - (2 - i) * 38)
    b.Size = UDo(32, 32)
    b.ZIndex = 4
    b.Parent = view
    corner(b, 4)
    stroke(b, RGB(255, 255, 255), 1, 0.85)
    zoomBtns[i] = b
  end

  ---------------------------------------------------------------- 状态（服务器给的次数、冷却）

  local seenS, cdAt, left = nil, {}, {}
  local function sync()
    local S = G.S
    if S == seenS then return end
    seenS = S
    local tac = S and S.tac
    if type(tac) ~= "table" then return end
    local t = os.clock()
    for id, v in pairs(tac) do
      if type(v) == "table" then
        left[id] = v.n
        cdAt[id] = t + (v.cd or 0)
      end
    end
  end
  local function state(id)
    sync()
    local it = TP.items[id]
    return math.max(0, left[id] or it.n), math.max(0, math.ceil((cdAt[id] or 0) - os.clock())), it
  end
  local function mmss(s) return string.format("%d:%02d", s // 60, s % 60) end

  local function myPos()
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
  end

  ---------------------------------------------------------------- 地图：放大、拖动、点目标

  local zoom, pan = 1, V2(0, 0)
  local tgt = nil        -- 选的目标（世界 x, z）
  local sending = nil    -- 发出去了、等服务器回话的时刻
  local pillUntil = 0
  local function kPx() return zoom * (VH * 0.86) / (2 * TP.range) end   -- 每格多少设计像素（放大 1 倍时呼叫范围占地图高的 86%）
  local function center()
    local p = myPos()
    return (p and V2(p.X, p.Z) or V2(0, 0)) + pan
  end
  local function at(x, z, c, k) return UD(0.5, (x - c.X) * k, 0.5, (z - c.Y) * k) end
  local function flash(text, col, sec)
    pillT.Text = text
    pillT.TextColor3 = col or TEXT
    pill.Size = UDo(math.min(VW - 40, 40 + utf8.len(text) * 13), 26)
    pill.Visible = true
    pillUntil = os.clock() + (sec or 3)
  end
  local function setTarget(w)
    local p = myPos()
    if not p then return end
    local d = w - V2(p.X, p.Z)
    if d.Magnitude > TP.range then   -- 点到圈外：收到圈边上
      w = V2(p.X, p.Z) + d.Unit * (TP.range - 1)
      flash(T("tac.far", math.floor(TP.range / M_PER)), AMBER)
    end
    tgt = w
  end
  G.tacPick = function(x, z) setTarget(V2(x, z)) end   -- 测试用：直接给目标
  local function screenToWorld(p)   -- p：InputObject.Position（同 AbsolutePosition 一个坐标系）
    local a, s = view.AbsolutePosition, view.AbsoluteSize
    if s.X < 2 then return nil end
    local k = kPx() * (s.X / VW)
    local c = center()
    return V2(c.X + (p.X - (a.X + s.X / 2)) / k, c.Y + (p.Y - (a.Y + s.Y / 2)) / k)
  end
  local dragging, dragFrom = false, nil
  catcher.InputBegan:Connect(function(io)
    local ut = io.UserInputType
    if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
      local ok, w = pcall(screenToWorld, io.Position)
      if ok and w then setTarget(w) end
    elseif ut == Enum.UserInputType.MouseButton2 then
      dragging, dragFrom = true, io.Position
    end
  end)
  catcher.InputChanged:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseWheel then
      zoom = math.clamp(zoom * ((io.Position.Z > 0) and 1.25 or 0.8), 0.6, 6)
    end
  end)
  UIS.InputChanged:Connect(function(io)
    if dragging and io.UserInputType == Enum.UserInputType.MouseMovement and dragFrom then
      local ok, s = pcall(function() return view.AbsoluteSize.X / VW end)
      local k = kPx() * ((ok and s and s > 0) and s or 1)
      local d = io.Position - dragFrom
      dragFrom = io.Position
      pan -= V2(d.X, d.Y) / k
      if pan.Magnitude > TP.range * 1.3 then pan = pan.Unit * TP.range * 1.3 end
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton2 then dragging = false end
  end)
  zoomBtns[1].Activated:Connect(function() zoom = math.clamp(zoom * 1.4, 0.6, 6) end)
  zoomBtns[2].Activated:Connect(function() zoom = math.clamp(zoom / 1.4, 0.6, 6) end)

  local function stepMap()
    local root = G.mapRoot
    local k, c = kPx(), center()
    if root and root.Parent == holder and G.mapUV and G.mapSpan then
      local Z = G.mapSpan * k
      local u, v = G.mapUV(c.X, c.Y)
      root.AnchorPoint = V2(0, 0)
      root.Size = UDo(Z, Z)
      root.Position = UD(0.5, -u * Z, 0.5, -v * Z)
      root.BackgroundTransparency = 0
    end
    local p = myPos()
    if p then
      ring.Visible = true
      ring.Position = at(p.X, p.Z, c, k)
      ring.Size = UDo(TP.range * 2 * k, TP.range * 2 * k)
      ringLabel.Position = UD(0.5, (p.X - c.X) * k, 0.5, (p.Z - c.Y) * k - TP.range * k - 4)
      ringLabel.Text = T("tac.range", math.floor(TP.range / M_PER))
    else
      ring.Visible = false
    end
    local it = TP.items[sel]
    local has = tgt ~= nil and p ~= nil
    mark.Visible, markL.Visible, path.Visible = has, has, has
    strip.Visible = has and (it.kind == "gunrun" or it.kind == "cluster")
    blast.Visible = has and it.kind == "pgm"
    if has then
      local me2 = V2(p.X, p.Z)
      local d = tgt - me2
      local dir = (d.Magnitude > 1) and d.Unit or V2(0, -1)
      local rot = math.deg(math.atan2(dir.X, -dir.Y))   -- 相对北（地图上方）顺时针
      local mp = at(tgt.X, tgt.Y, c, k)
      mark.Position = mp
      local col = (os.clock() % 0.8 < 0.62) and AMBER or TEXT
      markS.Color = col
      for _, t in ipairs(ticks) do t.BackgroundColor3 = col end
      markL.Position = UD(0.5, (tgt.X - c.X) * k + 20, 0.5, (tgt.Y - c.Y) * k)
      local brg = (math.deg(math.atan2(dir.X, -dir.Y)) + 360) % 360
      markL.Text = T("tac.target", math.floor(d.Magnitude / M_PER + 0.5), string.format("%03d", math.floor(brg + 0.5) % 360))
      local a = V2((p.X - c.X) * k, (p.Z - c.Y) * k)
      local b = V2((tgt.X - c.X) * k, (tgt.Y - c.Y) * k)
      local mid = (a + b) / 2
      path.Position = UD(0.5, mid.X, 0.5, mid.Y)
      path.Size = UDo(math.max(1, (b - a).Magnitude), 1.5)
      path.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
      if strip.Visible then
        local w = (it.kind == "cluster") and 70 or 22
        strip.Position = mp
        strip.Size = UDo(math.max(6, w * k), math.max(18, (it.len or 100) * k))
        strip.Rotation = rot
      end
      if blast.Visible then
        local r = math.max(8, 60 * k)
        blast.Position = mp
        blast.Size = UDo(r * 2, r * 2)
      end
    end
    -- 比例尺：取一个整数距离，长 60～150 像素
    local best = 100
    for _, m in ipairs({ 50, 100, 200, 250, 500, 1000, 2000, 5000 }) do
      if m * M_PER * k <= 150 then best = m end
    end
    sbar.Size = UDo(best * M_PER * k, 2)
    sText.Text = (best >= 1000) and string.format("%g km", best / 1000) or (best .. " m")
    if pill.Visible and os.clock() > pillUntil then pill.Visible = false end
  end

  ---------------------------------------------------------------- 文字、卡片、按钮

  local function canCall()
    local n, cd, it = state(sel)
    if n <= 0 then return false, T("tac.out"), FAINT end
    if cd > 0 then return false, T("tac.cdShort", mmss(cd)), AMBER end
    if not tgt then return false, T("tac.pick"), DIM end
    if sending and os.clock() - sending < 3 then return false, "· · ·", DIM end
    if (it.kind == "drop" or it.kind == "supply") and MapM.ground(tgt.X, tgt.Y) < 0.5 then return false, T("tac.water"), AMBER end
    return true, mob and T("tac.call") or T("tac.callNow"), RGB(10, 12, 12)
  end
  local function redraw()
    title.Text = T("tac.title")
    brand.Text = T("tac.brand")
    for _, c in ipairs(capLabels) do c[1].Text = T(c[2]) end
    hint.Text = mob and T("tac.zoomTouch") or T("tac.zoom")
    local p = myPos()
    if p then
      local R = MapM.R or 12288
      coord.Text = string.format("%s %05d · %05d", "GRID", math.floor((p.X + R) / M_PER), math.floor((R - p.Z) / M_PER))
    end
    local ct = Lighting.ClockTime
    clock.Text = string.format("%02d:%02d   %d%%", math.floor(ct) % 24, math.floor((ct % 1) * 60), bat)
    for _, id in ipairs(ORDER) do
      local c = cards[id]
      local n, cd, it = state(id)
      local on = id == sel
      c.b.BackgroundColor3 = on and CARD_ON or CARD
      c.st.Transparency = on and 0.75 or 0.93
      c.st.Color = on and AMBER or RGB(255, 255, 255)
      c.acc.Visible = on
      local usable = n > 0
      c.name.Text = T("tac." .. id)
      c.name.TextColor3 = usable and TEXT or FAINT
      if c.desc then c.desc.Text = T("tac." .. id .. ".desc") c.desc.TextColor3 = usable and DIM or FAINT end
      c.paint(usable and (on and AMBER or TEXT) or FAINT)
      for k, pp in ipairs(c.pips) do
        pp.BackgroundColor3 = (k <= n) and (on and AMBER or TEXT) or RGB(60, 66, 64)
        pp.BackgroundTransparency = (k <= n) and 0 or 0.2
      end
      if not usable then
        c.state.Text, c.state.TextColor3 = T("tac.out"), FAINT
        c.cd.Size = UD(0, 0, 0, 2)
      elseif cd > 0 then
        c.state.Text, c.state.TextColor3 = T("tac.cdShort", mmss(cd)), AMBER
        c.cd.Size = UD(1 - cd / math.max(1, it.cd), 0, 0, 2)
      else
        c.state.Text, c.state.TextColor3 = T("tac.ready"), GOOD
        c.cd.Size = UD(0, 0, 0, 2)
      end
    end
    local n, _, it = state(sel)
    dName.Text = T("tac." .. sel)
    dInfo.Text = T("tac.eta", it.flight) .. "   ·   " .. T("tac.limit", it.n, it.cd)
    if tgt and p then
      local d = (tgt - V2(p.X, p.Z)).Magnitude
      dTgt.Text = T("tac.target", math.floor(d / M_PER + 0.5), string.format("%03d", math.floor((math.deg(math.atan2(tgt.X - p.X, -(tgt.Y - p.Z))) + 360) % 360 + 0.5) % 360))
      dTgt.TextColor3 = AMBER
      dWarn.Text = (it.kind ~= "drop" and it.kind ~= "supply" and d < 110) and T("tac.danger") or ""
    else
      dTgt.Text = T("tac.pick")
      dTgt.TextColor3 = DIM
      dWarn.Text = ""
    end
    local ok, label, tcol = canCall()
    callBtn.Text = label
    callBtn.TextColor3 = tcol
    callBtn.BackgroundColor3 = ok and TEXT or OFF
    callBtn.AutoButtonColor = ok
    local _ = n
  end

  ---------------------------------------------------------------- 拿出来、收起、呼叫

  local open, closing, prevTool = false, nil, nil
  local function fit()
    local cam = workspace.CurrentCamera
    local ok, vp = pcall(function() return cam.ViewportSize end)
    if not ok or not vp or vp.X < 10 then vp = V2(1280, 720) end
    local s = math.min(vp.X * (mob and 0.985 or 0.92) / DW, vp.Y * (mob and 0.97 or 0.92) / DH)
    scale.Scale = math.clamp(s, 0.3, 1.6)
  end
  local function canUse()
    local ch = me.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if G.drive or G.fly or G.sail or G.gunner then return false end   -- 只有步行能用（车上、飞机上、工事上不行）
    if G.S and (G.S.alive == false or G.S.phase == "end") then return false end
    if G.menuShown and G.menuShown() then return false end
    if G.tabletState and G.tabletState.open then return false end   -- 正在遥控无人机
    if G.scopeOn then return false end
    return true
  end
  local function openPad()
    if open or not canUse() then return end
    open, closing, sending = true, nil, nil
    gui.Enabled = true
    fit()
    -- 枪收起来（两只手端着平板），收平板时再拿回来
    local ch = me.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local tool = ch and ch:FindFirstChildOfClass("Tool")
    prevTool = tool
    if tool and hum then hum:UnequipTools() end
    -- 借地图（收起时还给右下角的雷达）
    if G.mapMount and G.mapRoot then
      G.mapMount(holder, UDo(10, 10))
      if G.mapTheme then G.mapTheme("map") end
    end
    pan = V2(0, 0)
    pcall(function() G.R.Act:FireServer("tacPad", true) end)
    dev.Position = UD(0.5, 0, 1.5, 0)
    TweenService:Create(dev, TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UD(0.5, 0, 0.5, 0) }):Play()
    dimBg.BackgroundTransparency = 1
    TweenService:Create(dimBg, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()
    if G.playSound then G.playSound("quiet", nil, 1.3) end
    stepMap()
    redraw()
  end
  local function closePad(keepTool)
    if not open then return end
    open, sending, dragging = false, nil, false
    local root = G.mapRoot
    if root and root.Parent == holder and G.hudParts and G.hudParts.miniBox then G.mapMount(G.hudParts.miniBox, UDs(1, 1)) end
    pcall(function() G.R.Act:FireServer("tacPad", false) end)
    local ch = me.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local tool = prevTool
    prevTool = nil
    if not keepTool and tool and hum and hum.Health > 0 and not G.drive and tool.Parent and tool.Parent ~= ch and not tool.Parent:IsA("Model") then
      hum:EquipTool(tool)
    end
    local mine = {}
    closing = mine
    TweenService:Create(dev, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UD(0.5, 0, 1.5, 0) }):Play()
    TweenService:Create(dimBg, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
    task.delay(0.24, function() if closing == mine and not open then gui.Enabled = false end end)
  end
  G.tacOpen = function() return open end
  G.tacToggle = function() if open then closePad() else openPad() end end
  G.tacSelect = function(id) if TP.items[id] then sel = id end end

  local function callNow()
    if not open then return end
    local ok, label = canCall()
    if not ok then
      if label and label ~= "· · ·" then flash(label, AMBER) end
      return
    end
    sending = os.clock()
    pcall(function() G.R.Act:FireServer("tacCall", sel, V(tgt.X, 0, tgt.Y)) end)
    redraw()
  end
  G.tacCallNow = callNow
  callBtn.Activated:Connect(callNow)

  -- 服务器回话：不行的原因写在平板上（主界面的提示被平板挡着）
  local prevMsg = G.onMsg
  G.onMsg = function(kind, key, ...)
    if open and kind == "bad" and type(key) == "string" and string.sub(key, 1, 4) == "tac." then
      sending = nil
      flash(T(key, ...), RED, 4)
      redraw()
    end
    return prevMsg(kind, key, ...)
  end

  -- 键：B 拿出 / 收起；开着时 Enter 呼叫、1–5 选
  local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5 }
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.B then
      if open then closePad() else openPad() end
    elseif open and k == Enum.KeyCode.Return then
      callNow()
    elseif open and KEYS[k] and ORDER[KEYS[k]] then
      sel = ORDER[KEYS[k]]
      redraw()
    end
  end)
  if mob then   -- 手机：右边一个小按钮（夜视按钮下面）
    task.spawn(function()
      local hud = G.gui and G.gui:WaitForChild("Hud", 20)
      local b = hud and G.ui and G.ui.button and G.ui.button(hud, "", UDim2.fromOffset(52, 40), UDim2.new(1, -78, 0, 186), RGB(24, 28, 30))
      if b then
        b.Name = "TacPadBtn"
        b.Text = T("tac.key")
        b.BackgroundTransparency = 0.35
        b.TextSize = 13
        b.Activated:Connect(function() if open then closePad() else openPad() end end)
      end
    end)
    local closeBtn = Instance.new("TextButton")   -- 平板右上角的「收起」
    closeBtn.Name = "Close"
    closeBtn.Size = UDo(70, TOP - 4)
    closeBtn.Position = UD(1, -84, 0, 2)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.TextColor3 = AMBER
    closeBtn.Text = T("tac.closeTouch")
    closeBtn.Parent = bar
    closeBtn.Activated:Connect(function() closePad() end)
    clock.Position = UD(1, -92, 0, 0)
  end

  ---------------------------------------------------------------- 飞过来的飞机、落下的货盘和炸弹（所有人都看得到）

  local FXF = G.fxFolder or workspace
  local jobs = {}
  local function newPart(size, cf, col, mat, tr)
    local p = Instance.new("Part")
    p.Size, p.CFrame, p.Color = size, cf, col
    p.Material = mat or Enum.Material.SmoothPlastic
    p.Transparency = tr or 0
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = FXF
    return p
  end
  local function ground(x, z) return math.max(MapM.ground(x, z), 0) end
  local function lookCF(p, fwd, up)
    if fwd.Magnitude < 1e-3 then fwd = V(0, 0, -1) end
    return CFrame.lookAt(p, p + fwd, up or UPV)
  end

  -- 飞机：AirModels 拼的整架（跟部署界面、空中别人的飞机一个样子；挂架空着）
  local function plane(id, team)
    local d = AD.get(id)
    if not d then return nil end
    local load = {}
    for k = 1, #(d.st or {}) do load[k] = false end
    local ok, M = pcall(AM.build, d, team, load)
    if not ok or not M then return nil end
    M.model.Parent = FXF
    return { M = M, d = d, c = { thr = 96, gear = 0, flap = 0, pit = 0, rol = 0, yaw = 0, bay = 0, bayS = 0, can = 0, hook = 0, fold = 0, rpm = 100,
      door = 0, ramp = 0, ty = 0, gp = 0, spin1 = math.random() * 6, spin2 = math.random() * 6, spinT = 0, spinP = 0 } }
  end
  local function posePlane(P, cf, dt)
    local c, d = P.c, P.d
    if d.rotor then c.spin1 = (c.spin1 + d.rotor.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
    if d.rotor2 then c.spin2 = (c.spin2 + d.rotor2.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
    if d.tail then c.spinT = (c.spinT + 18 * dt) % (math.pi * 2) end
    if d.prop then c.spinP = (c.spinP + 30 * dt) % (math.pi * 2) end
    pcall(AM.pose, P.M, cf, c, os.clock())
  end
  local function job(f, kill)
    table.insert(jobs, { f = f, kill = kill, t = 0 })
  end
  local function stepJobs(dt)
    for i = #jobs, 1, -1 do
      local j = jobs[i]
      j.t += dt
      local ok, keep = pcall(j.f, j.t, dt)
      if not ok or not keep then
        pcall(j.kill)
        table.remove(jobs, i)
      end
    end
  end

  -- 一枚炸弹从 a 落到 b（t0 → t1），水平先快后慢、竖直越落越快，弹头顺着速度
  local function bombDrop(wid, a, b, t0, t1)
    local aw = AD.W[wid]
    if not aw then return end
    local mdl = WM.make(FXF, aw, CF(a), true)
    for _, p in ipairs(mdl.parts) do p.Parent = nil end
    local cfs = table.create(#mdl.parts)
    local shown = false
    local function posAt(s)
      local h = a:Lerp(b, 1 - (1 - s) ^ 1.6)
      return V(h.X, a.Y + (b.Y - a.Y) * s ^ 1.7, h.Z)
    end
    job(function(t)
      if t < t0 then return true end
      if t >= t1 then return false end
      if not shown then
        shown = true
        for _, p in ipairs(mdl.parts) do p.Parent = FXF end
      end
      local s = (t - t0) / (t1 - t0)
      local p = posAt(s)
      local q = posAt(math.min(1, s + 0.02))
      local cf = lookCF(p, q - p)
      for k, o in ipairs(mdl.offs) do cfs[k] = cf * o end
      workspace:BulkMoveTo(mdl.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
      return true
    end, function() for _, p in ipairs(mdl.parts) do p:Destroy() end end)
  end

  -- 降落伞（货盘用）：扁椭球伞衣 + 四根伞绳；k 张开程度 0～1
  local function chute(r)
    local canopy = newPart(V(r * 2, r * 0.8, r * 2), CF(), RGB(112, 112, 88), Enum.Material.Fabric)
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Parent = canopy
    local vent = newPart(V(r * 0.5, r * 0.22, r * 0.5), CF(), RGB(78, 78, 62), Enum.Material.Fabric)
    local vm = Instance.new("SpecialMesh")
    vm.MeshType = Enum.MeshType.Sphere
    vm.Parent = vent
    local lines = {}
    for i = 1, 4 do lines[i] = newPart(V(0.12, 0.12, 1), CF(), RGB(52, 52, 46), Enum.Material.SmoothPlastic) end
    local C = { canopy = canopy, vent = vent, lines = lines, r = r, mesh = mesh, vm = vm }
    function C.place(top, low, k, sway)   -- top：伞衣中心，low：吊点（四角按 1 格外扩）
      k = math.clamp(k, 0.05, 1)
      local rr = r * k
      local ccf = CF(top) * CFrame.Angles(sway.X, 0, sway.Y)
      mesh.Scale = V(k, 0.4 + 0.6 * k, k)
      canopy.CFrame = ccf
      vent.CFrame = ccf * CF(0, r * 0.38 * (0.4 + 0.6 * k), 0)
      for i, l in ipairs(lines) do
        local ang = (i - 0.5) * math.pi / 2
        local rim = (ccf * CF(math.cos(ang) * rr * 0.92, -r * 0.1, math.sin(ang) * rr * 0.92)).Position
        local dl = low - rim
        l.Size = V(0.12, 0.12, math.max(0.2, dl.Magnitude))
        l.CFrame = CFrame.lookAt(rim + dl / 2, low)
      end
    end
    function C.kill()
      canopy:Destroy()
      vent:Destroy()
      for _, l in ipairs(lines) do l:Destroy() end
    end
    return C
  end

  -- 空投货盘：supply 帆布箱；vdrop 重装平台（车罩着篷布、三顶伞）
  local function cargo(kind)
    local parts, offs = {}, {}
    local function add(size, off, col, mat, tr)
      local p = newPart(size, CF(), col, mat, tr)
      table.insert(parts, p)
      table.insert(offs, off)
      return p
    end
    local lamp
    if kind == "drop" then
      add(V(13, 1.2, 22), CF(0, 0.6, 0), RGB(64, 58, 46), Enum.Material.WoodPlanks)   -- 平台
      add(V(11, 5.2, 19), CF(0, 3.8, 0), RGB(70, 76, 58), Enum.Material.Fabric)      -- 罩着篷布的车
      add(V(9, 2.4, 9), CF(0, 7.6, 2), RGB(64, 70, 54), Enum.Material.Fabric)
      for _, z in ipairs({ -6, 0, 6 }) do add(V(11.2, 0.3, 0.5), CF(0, 5.3, z), RGB(34, 36, 30), Enum.Material.Fabric) end
      lamp = add(V(0.6, 0.6, 0.6), CF(5.6, 1.6, 10.4), RGB(150, 255, 170), Enum.Material.Neon)
    else
      add(V(6.4, 0.5, 4.6), CF(0, 0.25, 0), RGB(64, 58, 46), Enum.Material.WoodPlanks)
      add(V(5.8, 3.4, 4.0), CF(0, 2.2, 0), RGB(78, 86, 60), Enum.Material.Fabric)
      add(V(0.3, 3.5, 4.1), CF(1.4, 2.2, 0), RGB(40, 42, 36), Enum.Material.Fabric)
      add(V(0.3, 3.5, 4.1), CF(-1.4, 2.2, 0), RGB(40, 42, 36), Enum.Material.Fabric)
      lamp = add(V(0.45, 0.45, 0.45), CF(0, 4.1, 0), RGB(150, 255, 170), Enum.Material.Neon)
    end
    local pl = Instance.new("PointLight")   -- 化学荧光棒：夜里好找
    pl.Color, pl.Range, pl.Brightness, pl.Shadows = RGB(140, 255, 160), 12, 0.8, false
    pl.Parent = lamp
    return { parts = parts, offs = offs, cfs = table.create(#parts), top = (kind == "drop") and 9 or 4.4, lamp = lamp }
  end

  local function fxTac(e)
    if typeof(e.p) ~= "Vector3" then return end
    local team = (e.team == "def") and "def" or "atk"
    local kind = e.kind
    local P0 = e.p
    local dir = (typeof(e.d) == "Vector3" and e.d.Magnitude > 0.1) and V(e.d.X, 0, e.d.Z).Unit or V(0, 0, -1)
    local side = dir:Cross(UPV)
    local T1 = tonumber(e.t) or 6
    local jets = TP.jets[team] or TP.jets.atk
    local jid = jets[(kind == "supply") and "drop" or kind] or jets.pgm
    -- 呼叫的是自己：平板上说一声，过一会儿收起来看
    if e.by == me.UserId and open then
      sending = nil
      flash(T("tac.sent", T1), GOOD, 3)
      task.delay(1.1, function() if open then closePad() end end)
    end
    local P = plane(jid, team)
    local gy0 = P0.Y

    if kind == "pgm" then
      -- 战斗机高空水平飞过；落弹前 3.4 秒在投弹点（目标前方 520 格）放弹
      local H, VP, FALL = 820, 480, 3.4
      local tr = math.max(0.4, T1 - FALL)
      local rel = P0 - dir * 520
      local function pos(t) return rel + dir * VP * (t - tr) + UPV * (gy0 + H - rel.Y) end
      if P then
        job(function(t, dt)
          if t > tr + 5 then return false end
          posePlane(P, lookCF(pos(t), dir), dt)
          return true
        end, function() P.M.model:Destroy() end)
      end
      bombDrop((team == "def") and "gbu12" or "lt2", pos(tr) - UPV * 3, P0, tr, T1)
      -- 激光照射点（一闪一闪）+ 呼叫的人那里一道照射光束（夜视里看得见）
      local spot = newPart(V(1.6, 1.6, 1.6), CF(P0 + UPV * 0.6), RGB(255, 80, 70), Enum.Material.Neon, 0.1)
      spot.Shape = Enum.PartType.Ball
      local beam = newPart(V(0.14, 0.14, 1), CF(), RGB(190, 255, 200), Enum.Material.Neon, 0.72)
      local caller = Players:GetPlayerByUserId(tonumber(e.by) or 0)
      job(function(t)
        if t > T1 + 0.1 then return false end
        spot.Transparency = ((t * 8) % 1 < 0.5) and 0.05 or 0.6
        local ch = caller and caller.Character
        local head = ch and ch:FindFirstChild("Head")
        if head then
          local a = head.Position + V(0, 0.2, 0)
          local d = P0 + UPV * 0.6 - a
          beam.Size = V(0.14, 0.14, d.Magnitude)
          beam.CFrame = CFrame.lookAt(a + d / 2, P0)
          beam.Transparency = 0.72
        else
          beam.Transparency = 1
        end
        return true
      end, function() spot:Destroy() beam:Destroy() end)

    elseif kind == "gunrun" then
      -- 攻击机俯冲：开火时在扫射带起点后 520 格、离地 260 格，一边打一边往下压，打完拉起
      local len, n = tonumber(e.len) or 170, tonumber(e.n) or 24
      local dur = (n - 1) * 0.045
      local VP = 300
      local s0 = P0 - dir * (len / 2)
      local function alt(t)
        local u = t - T1
        if u < 0 then return 260 + 150 * math.min(1, -u / 4) end
        if u < dur then return 260 - 70 * (u / dur) end
        return 190 + 90 * (u - dur) ^ 1.4
      end
      local function pos(t) return s0 - dir * 520 + dir * VP * (t - T1) + UPV * (gy0 + alt(t) - s0.Y) end
      local nose = nil
      if P then
        job(function(t, dt)
          if t > T1 + dur + 4 then return false end
          local p = pos(t)
          local q = pos(t + 0.05)
          posePlane(P, lookCF(p, q - p), dt)
          nose = p + (q - p).Unit * 24 - UPV * 2
          return true
        end, function() P.M.model:Destroy() end)
      end
      -- 曳光：每一发从机头打到扫射带上那一点（爆点是服务器给的）
      local fired = 0
      local gunKey = "tac" .. tostring(e.id or math.random(1, 1e6))
      local flashP = newPart(V(3, 3, 3), CF(0, -500, 0), RGB(255, 214, 140), Enum.Material.Neon, 1)
      flashP.Shape = Enum.PartType.Ball
      local fl = Instance.new("PointLight")
      fl.Color, fl.Range, fl.Brightness, fl.Shadows = RGB(255, 200, 130), 40, 0, false
      fl.Parent = flashP
      local tracers = {}
      job(function(t)
        if t > T1 + dur + 0.6 then return false end
        while fired < n and t >= T1 + fired * 0.045 do
          fired += 1
          local f = (fired - 1) / math.max(1, n - 1) - 0.5
          local hit = P0 + dir * f * len
          hit = V(hit.X, ground(hit.X, hit.Z), hit.Z)
          local from = nose or pos(t)
          local d = hit - from
          local tr = newPart(V(0.4, 0.4, d.Magnitude), CFrame.lookAt(from + d / 2, hit), RGB(255, 206, 128), Enum.Material.Neon, 0.1)
          table.insert(tracers, { p = tr, t = t })
          if G.gunLoop then   -- 航炮声：机头那里一个循环声（一圈一发，Fx.lua），打完 0.25 秒自己停
            local jd = G.AD and G.AD.get and G.AD.get(jid)
            G.gunLoop(gunKey, (jd and jd.gun) or "gau8", from, true)
          elseif fired % 3 == 1 and G.playSound then G.playSound("lmg", from, 0.55 + math.random() * 0.1) end
        end
        local firing = t >= T1 and t <= T1 + dur
        if firing and nose then
          flashP.CFrame = CF(nose)
          flashP.Transparency = (math.random() < 0.5) and 0.1 or 0.5
          fl.Brightness = 3
        else
          flashP.Transparency, fl.Brightness = 1, 0
        end
        for i = #tracers, 1, -1 do
          local x = tracers[i]
          local age = t - x.t
          if age > 0.08 then x.p:Destroy() table.remove(tracers, i) else x.p.Transparency = 0.1 + age * 10 end
        end
        return true
      end, function()
        flashP:Destroy()
        for _, x in ipairs(tracers) do x.p:Destroy() end
      end)

    elseif kind == "cluster" then
      -- 轰炸机高空沿方向飞过，炸弹按服务器的落点时刻一枚枚放下（落 4.2 秒）
      local len, n = tonumber(e.len) or 230, tonumber(e.n) or 12
      local H, VB, FALL = 1250, 330, 4.2
      local tMid = T1 + (n - 1) * 0.12 / 2 - FALL
      local cpt = P0 - dir * (VB * FALL * 0.6)
      local function pos(t) return cpt + dir * VB * (t - tMid) + UPV * (gy0 + H - cpt.Y) end
      if P then
        job(function(t, dt)
          if t > tMid + 7 then return false end
          posePlane(P, lookCF(pos(t), dir), dt)
          return true
        end, function() P.M.model:Destroy() end)
      end
      local wid = (team == "def") and "mk82" or "b250"
      for i = 1, n do
        local ti = T1 + (i - 1) * 0.12
        local f = (i - 1) / math.max(1, n - 1) - 0.5
        local q = P0 + dir * f * len + side * ((math.random() - 0.5) * 30)
        q = V(q.X, ground(q.X, q.Z), q.Z)
        local t0 = math.max(0, ti - FALL)
        bombDrop(wid, pos(t0) - UPV * 4, q, t0, ti)
      end

    else   -- drop / supply：运输直升机低空飞来，落地前 FALL 秒在目标上空放货盘
      local heavy = kind == "drop"
      local H, VH = heavy and 190 or 150, 120
      local FALL = heavy and 6.5 or 5
      local tr = math.max(0.5, T1 - FALL)
      local rel = P0 - dir * 30
      local function pos(t) return rel + dir * VH * (t - tr) + UPV * (gy0 + H - rel.Y) end
      if P then
        job(function(t, dt)
          if t > tr + 6 then return false end
          local p = pos(t)
          posePlane(P, lookCF(p, dir - UPV * 0.06), dt)
          return true
        end, function() P.M.model:Destroy() end)
      end
      local cg = cargo(heavy and "drop" or "supply")
      local chutes = {}
      for i = 1, heavy and 3 or 1 do chutes[i] = chute(heavy and 15 or 9) end
      for _, p in ipairs(cg.parts) do p.Parent = nil end
      local shown = false
      local OPEN = 0.9
      local yRel = gy0 + H - 8
      job(function(t)
        if t < tr then return true end
        if not shown then
          shown = true
          for _, p in ipairs(cg.parts) do p.Parent = FXF end
        end
        local u = t - tr
        local horiz = rel + dir * VH * math.min(u, 0.6) * 0.5
        local y
        local yOpen = yRel - 0.5 * 60 * OPEN * OPEN
        if u < OPEN then y = yRel - 0.5 * 60 * u * u
        else y = yOpen + (gy0 - yOpen) * math.clamp((u - OPEN) / math.max(0.5, FALL - OPEN), 0, 1) end
        local landed = u >= FALL
        local base = V(horiz.X, math.max(gy0, y), horiz.Z)
        local sway = V2(math.sin(t * 1.3) * 0.06, math.cos(t * 1.1) * 0.05)
        local cf = CF(base) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0) * CFrame.Angles(sway.X * 0.5, 0, sway.Y * 0.5)
        for k, o in ipairs(cg.offs) do cg.cfs[k] = cf * o end
        workspace:BulkMoveTo(cg.parts, cg.cfs, Enum.BulkMoveMode.FireCFrameChanged)
        cg.lamp.Transparency = ((t * 2.2) % 1 < 0.15) and 0 or 0.7
        local k = math.clamp((u - 0.25) / OPEN, 0, 1)
        for i, c in ipairs(chutes) do
          local off = (#chutes == 1) and V() or ((cf.RightVector * ((i - 2) * 16)) + cf.LookVector * ((i == 2) and 4 or -3))
          local top = base + UPV * (cg.top + 5 + 26 * k) + off * k
          if landed then   -- 落地：伞衣塌下来、淡掉
            local f = math.clamp((u - FALL) / 0.8, 0, 1)
            top = base + UPV * (cg.top + (5 + 26) * (1 - f)) + off + dir * 10 * f
            c.canopy.Transparency, c.vent.Transparency = f, f
            for _, l in ipairs(c.lines) do l.Transparency = f end
          end
          c.place(top, base + UPV * cg.top, k, sway)
        end
        if landed then   -- 服务器那边的车 / 补给箱这时生成：货盘淡掉
          local f = math.clamp((u - FALL) / 0.35, 0, 1)
          for _, p in ipairs(cg.parts) do p.Transparency = math.max(p.Transparency, f) end
          if u > FALL + 0.9 then return false end
        end
        return true
      end, function()
        for _, p in ipairs(cg.parts) do p:Destroy() end
        for _, c in ipairs(chutes) do c.kill() end
      end)
    end
  end
  G.fxExtra = G.fxExtra or {}
  G.fxExtra.tac = fxTac

  ---------------------------------------------------------------- 每帧

  local acc = 0
  function G.stepTacPad(dt)
    stepJobs(dt)
    if not open then return end
    if not canUse() then closePad(true) return end
    -- 有人把枪拿出来了（别的模块装备）：再收起来
    local ch = me.Character
    local tool = ch and ch:FindFirstChildOfClass("Tool")
    if tool then
      prevTool = prevTool or tool
      local hum = ch:FindFirstChildOfClass("Humanoid")
      if hum then hum:UnequipTools() end
    end
    local root = G.mapRoot
    if root and root.Parent ~= holder and G.mapMount then G.mapMount(holder, UDo(10, 10)) end
    stepMap()
    acc += dt
    if acc > 0.1 then
      acc = 0
      redraw()
    end
    for _, led in pairs(leds) do led.BackgroundTransparency = (os.clock() % 1.6 < 1.3) and 0 or 0.6 end
  end
end

return TacPad
