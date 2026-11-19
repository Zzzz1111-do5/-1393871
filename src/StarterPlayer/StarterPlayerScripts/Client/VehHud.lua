-- 全面大战场（客户端）——载具驾驶界面。用户 11-18：「坦克驾驶界面、操作系统观感不够惊艳，舰船也是……放开了做，作出一款震撼的作品」
--   照战雷、战地的样子重做坦克（Drive.lua 的 G.myVeh）和舰艇（Sail.lua 的 G.sail）的驾驶界面；
--   有了这个模块（G.vehHudOn），Drive.lua、Sail.lua 原来那块小面板、圆圈、黄十字不画了（瞄准镜、望远镜、导弹锁定框照旧归它们）。
--   · 电脑右下两块，触屏用紧凑读数面板给方向键留位置：
--     「车况 / 舰况」：名字；俯视轮廓（车体 / 舰体按相对镜头的朝向转，炮塔、炮管按各自的朝向转；外圈上方两道短线是镜头看的方向），
--       描边按血量变色、挨打闪红；十格血条和百分比；坦克：速度（大数字）、挡位 D / R / N、航向、油门条；
--       舰艇：航速（节）、车钟（后退二 … 全速前进 一格格的梯子，亮的是现在这一档）、舵角条（左右 35°）、航向
--     「武器」：每一种武器一行（按键、名字、弹药），选中的那行亮、左边一道琥珀色；右边装填环（24 颗点：装填时一颗颗亮起琥珀色，装好全绿、写「就绪」）；
--       坦克的烟幕弹、舰艇的防空导弹、近防炮
--   · 电脑罗盘放在计分栏左侧或下方，触屏只在面板显示航向；琥珀色小三角是炮管（坦克）/ 舰首（舰艇）的朝向
--   · 中间：镜头看的地方一个小圈；炮现在指的地方一个准星——坦克、舰艇两套不一样（用户 11-19：参考 MWT 和《现代战舰》）：
--     坦克（MWT）：四段弧 + 三道刻度 + 中心点，装填时弧顺时针一段段亮；颜色 = 打不打得穿（照服务器的跳弹算法：绿可击穿、黄可能跳弹、
--       红会跳弹 / 打不穿），下面写出来；右边测距、左边装填秒数；炮塔还没转过来时一个小箭头指着镜头准心
--     舰艇（《现代战舰》）：主炮落点一个细的大圈、四根长线（横线有刻度）、中间菱形，外圈 40 段装填；距离、炮弹飞多久、炮名；
--       瞄着的敌人上方目标卡（名字、距离、血条）和提前量（它照现在的航速、炮弹落下时开到哪）；导弹：四个角框住，锁定中琥珀、已锁定红
--   · 四周一圈很淡的暗角；开炮：瞄准圈一涨一缩、画面一亮
local VehHud = {}

function VehHud.init(G)
  local Players = game:GetService("Players")
  local GuiService = game:GetService("GuiService")
  local RunService = game:GetService("RunService")
  local Lighting = game:GetService("Lighting")
  local RS = game:GetService("ReplicatedStorage")
  local UIS = game:GetService("UserInputService")
  local V2, V3, UD2, UD = Vector2.new, Vector3.new, UDim2.new, UDim.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local VD = require(RS:WaitForChild("VehDefs"))
  local SD = require(RS:WaitForChild("ShipDefs"))
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local reducedMotion = false
  pcall(function()
    local function updateMotion() reducedMotion = GuiService.ReducedMotionEnabled end
    updateMotion()
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(updateMotion)
  end)

  local INK, TXT, MUTE = RGB(6, 9, 12), RGB(232, 238, 236), RGB(174, 187, 186)
  local AMBER, OK, BAD, CYAN = RGB(255, 184, 72), RGB(110, 228, 150), RGB(240, 82, 66), RGB(128, 214, 255)
  local MONO, BOLD, MED = Enum.Font.RobotoMono, Enum.Font.GothamBold, Enum.Font.GothamMedium
  local WHITE = Color3.new(1, 1, 1)

  local function frame(parent, size, pos, color, alpha, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or INK, alpha or 0, 0
    f.Parent = parent
    return f
  end
  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 14, color or TXT, font or MED
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.Parent = parent
    return l
  end
  local function stroke(f, color, th, alpha)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = color or WHITE, th or 1, alpha or 0.82
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function roundf(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UD(0.5, 0)
    c.Parent = f
    return f
  end
  local function grad(f, rot, seq)
    local g = Instance.new("UIGradient")
    g.Rotation = rot
    g.Transparency = seq
    g.Parent = f
    return g
  end
  local function nseq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = NumberSequenceKeypoint.new(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
  -- 面板：深色半透明、细白边、左上角刻一道短的亮线
  local function panel(parent, size, pos, anchor)
    local p = frame(parent, size, pos, INK, 0.16, anchor)
    stroke(p, WHITE, 1, 0.86)
    frame(p, UD2(0, 26, 0, 2), UD2(0, -1, 0, -1), TXT, 0.1)
    frame(p, UD2(0, 2, 0, 14), UD2(0, -1, 0, -1), TXT, 0.1)
    return p
  end
  -- 十格血条 + 百分比（左上角 x, y）
  local function hpBlock(p, x, y)
    local o = {}
    o.lab = label(p, "", UD2(0, 70, 0, 14), UD2(0, x, 0, y), 11, MUTE, MED, nil, LEFT)
    o.pct = label(p, "100%", UD2(0, 60, 0, 14), UD2(0, x + 132, 0, y), 12, TXT, MONO, V2(1, 0), RIGHT)
    o.seg = {}
    for i = 1, 10 do o.seg[i] = frame(p, UD2(0, 11, 0, 6), UD2(0, x + (i - 1) * 13.2, 0, y + 18), OK, 0.05) end
    return o
  end
  local function setHp(o, k, col)
    o.pct.Text = string.format("%d%%", math.floor(k * 100 + 0.5))
    o.pct.TextColor3 = col
    for i, s in ipairs(o.seg) do
      local on = k * 10 >= i - 0.5
      s.BackgroundColor3 = on and col or TXT
      s.BackgroundTransparency = on and 0.05 or 0.86
    end
  end
  -- 武器行：n 行（按键、名字、弹药、选中的左边一道琥珀色）
  local function weaponRows(p, n)
    local rows = {}
    for i = 1, n do
      local y = 12 + (i - 1) * 28
      local r = {}
      r.bar = frame(p, UD2(0, 3, 0, 22), UD2(0, 10, 0, y), AMBER, 0)
      r.key = label(p, "", UD2(0, 22, 0, 22), UD2(0, 18, 0, y), 12, TXT, BOLD)
      r.keyStroke = stroke(r.key, WHITE, 1, 0.7)
      r.name = label(p, "", UD2(0, 112, 0, 22), UD2(0, 48, 0, y), 13, TXT, MED, nil, LEFT)
      r.name.TextTruncate = Enum.TextTruncate.AtEnd
      r.ammo = label(p, "", UD2(0, 60, 0, 22), UD2(0, 226, 0, y), 13, TXT, MONO, V2(1, 0), RIGHT)
      r.name.Name, r.ammo.Name = "WName" .. i, "WAmmo" .. i
      rows[i] = r
    end
    return rows
  end
  local function setRow(r, key, name, ammo, sel, empty)
    local vis = name ~= nil
    r.bar.Visible, r.key.Visible, r.name.Visible, r.ammo.Visible = vis and sel, vis and key ~= nil, vis, vis
    if not vis then return end
    r.key.Text = key or ""
    r.name.Text = name
    r.ammo.Text = ammo or ""
    r.name.TextColor3 = sel and TXT or MUTE
    r.ammo.TextColor3 = empty and BAD or (sel and TXT or MUTE)
  end
  -- 装填环：24 颗点 + 中间的字
  local function reloadRing(p, cx, cy)
    local o = { dots = {} }
    o.box = frame(p, UD2(0, 64, 0, 64), UD2(0, cx, 0, cy), INK, 1, V2(0.5, 0.5))
    o.box.Name = "Reload"
    for i = 1, 24 do
      local a = (i - 0.5) / 24 * 2 * math.pi
      o.dots[i] = roundf(frame(o.box, UD2(0, 4, 0, 4), UD2(0.5, math.sin(a) * 27, 0.5, -math.cos(a) * 27), TXT, 0.75, V2(0.5, 0.5)))
    end
    o.txt = label(o.box, "", UD2(0, 60, 0, 20), UD2(0.5, 0, 0.5, -2), 14, OK, BOLD, V2(0.5, 0.5))
    o.txt.Name = "ReloadText"
    o.sub = label(o.box, "", UD2(0, 60, 0, 12), UD2(0.5, 0, 0.5, 13), 9, MUTE, MED, V2(0.5, 0.5))
    return o
  end
  local function setRing(o, relK, ready, left)
    local lit = math.floor(relK * 24 + 0.001)
    for i, d in ipairs(o.dots) do
      d.BackgroundColor3 = ready and OK or (i <= lit and AMBER or TXT)
      d.BackgroundTransparency = ready and 0.1 or (i <= lit and 0.05 or 0.8)
    end
    o.txt.Text = ready and T("vh.ready") or string.format("%.1f", left)
    o.txt.TextColor3 = ready and OK or AMBER
    o.sub.Text = ready and "" or T("vh.reload")
  end
  -- 俯视轮廓的底：一个圈 + 上方两道短线（镜头看的方向）
  local function silBase(p, cx, cy)
    local sil = frame(p, UD2(0, 104, 0, 104), UD2(0, cx, 0, cy), INK, 1, V2(0.5, 0.5))
    sil.Name = "Silhouette"
    stroke(roundf(frame(sil, UD2(1, 0, 1, 0), nil, INK, 1)), WHITE, 1, 0.85)
    for _, a in ipairs({ -32, 32 }) do
      local l = frame(sil, UD2(0, 1, 0, 30), UD2(0.5, math.sin(math.rad(a)) * 22, 0.5, -math.cos(math.rad(a)) * 22), TXT, 0.55, V2(0.5, 1))
      l.Rotation = a
    end
    for i = 0, 11 do   -- 外圈每 30° 一个刻度
      local a = i * 30
      local t = frame(sil, UD2(0, 1, 0, (i % 3 == 0) and 6 or 3), UD2(0.5, math.sin(math.rad(a)) * 50, 0.5, -math.cos(math.rad(a)) * 50), TXT, 0.5, V2(0.5, 0.5))
      t.Rotation = a
    end
    return sil
  end

  local gui = Instance.new("ScreenGui")
  gui.Name = "VehHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  G.vehHudOn = true

  for _, e in ipairs({ { UD2(1, 0, 0.16, 0), UD2(0, 0, 0, 0), 90 }, { UD2(1, 0, 0.16, 0), UD2(0, 0, 0.84, 0), 270 },
    { UD2(0.1, 0, 1, 0), UD2(0, 0, 0, 0), 0 }, { UD2(0.1, 0, 1, 0), UD2(0.9, 0, 0, 0), 180 } }) do
    local f = frame(gui, e[1], e[2], RGB(0, 0, 0), 0)
    grad(f, e[3], nseq(0, 0.45, 1, 1))
    f.Name = "Vignette"
  end
  local hud = frame(gui, UD2(1, 0, 1, 0), nil, INK, 1)
  hud.Name = "Panels"
  -- 面板缩放：每块面板自己一个 UIScale（绕自己的锚点缩，贴着角落不动）——原来整层一起缩，小屏幕上面板往左上角跑到屏幕中间
  local ret = frame(gui, UD2(1, 0, 1, 0), nil, INK, 1)
  ret.Name = "Reticles"

  ---------------------------------------------------------------- 坦克：车况、武器
  local TK = {}
  TK.car = panel(hud, UD2(0, 270, 0, 156), UD2(1, -334, 1, -40), V2(1, 1))
  TK.car.Name = "Vehicle"
  TK.name = label(TK.car, "", UD2(1, -20, 0, 18), UD2(0, 12, 0, 8), 14, TXT, MED, nil, LEFT)
  TK.name.Name = "VehName"
  local sil = silBase(TK.car, 60, 94)
  TK.hull = frame(sil, UD2(0, 70, 0, 70), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  TK.hull.Name = "Hull"
  TK.hullStroke = stroke(frame(TK.hull, UD2(0, 26, 0, 50), UD2(0.5, 0, 0.5, 0), RGB(30, 36, 40), 0.15, V2(0.5, 0.5)), OK, 1.5, 0)
  frame(TK.hull, UD2(0, 6, 0, 56), UD2(0.5, -17, 0.5, 0), RGB(200, 206, 204), 0.55, V2(0.5, 0.5))   -- 两条履带
  frame(TK.hull, UD2(0, 6, 0, 56), UD2(0.5, 17, 0.5, 0), RGB(200, 206, 204), 0.55, V2(0.5, 0.5))
  frame(TK.hull, UD2(0, 10, 0, 2), UD2(0.5, 0, 0.5, -27), TXT, 0.2, V2(0.5, 0.5))   -- 车头
  TK.tur = frame(sil, UD2(0, 70, 0, 70), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  TK.tur.Name = "Turret"
  stroke(roundf(frame(TK.tur, UD2(0, 20, 0, 20), UD2(0.5, 0, 0.5, 2), RGB(46, 54, 58), 0.05, V2(0.5, 0.5))), CYAN, 1.5, 0)
  frame(TK.tur, UD2(0, 3, 0, 34), UD2(0.5, 0, 0.5, 0), CYAN, 0, V2(0.5, 1)).Name = "Barrel"
  TK.hp = hpBlock(TK.car, 124, 34)
  TK.spd = label(TK.car, "0", UD2(0, 80, 0, 40), UD2(0, 124, 0, 66), 36, TXT, BOLD, nil, LEFT)
  TK.spd.Name = "Speed"
  label(TK.car, "km/h", UD2(0, 40, 0, 14), UD2(0, 124, 0, 104), 11, MUTE, MED, nil, LEFT)
  local gearBox = frame(TK.car, UD2(0, 30, 0, 30), UD2(1, -46, 0, 72), INK, 0.2)
  stroke(gearBox, WHITE, 1, 0.6)
  TK.gear = label(gearBox, "N", UD2(1, 0, 1, 0), nil, 18, TXT, BOLD)
  TK.gear.Name = "Gear"
  TK.hdg = label(TK.car, "000°", UD2(0, 90, 0, 14), UD2(1, -14, 0, 112), 12, MUTE, MONO, V2(1, 0), RIGHT)
  local thrBg = frame(TK.car, UD2(0, 132, 0, 3), UD2(0, 124, 0, 136), TXT, 0.86)
  TK.thr = frame(thrBg, UD2(0, 0, 1, 0), nil, AMBER, 0)
  TK.arm = panel(hud, UD2(0, 300, 0, 156), UD2(1, -24, 1, -40), V2(1, 1))
  TK.arm.Name = "Weapons"
  TK.rows = weaponRows(TK.arm, 3)
  TK.smoke = label(TK.arm, "", UD2(0, 200, 0, 18), UD2(0, 18, 1, -30), 12, MUTE, MED, nil, LEFT)
  TK.smoke.Name = "Smoke"
  TK.ring = reloadRing(TK.arm, 258, 66)

  ---------------------------------------------------------------- 舰艇：舰况、武器
  local SH = {}
  SH.car = panel(hud, UD2(0, 296, 0, 156), UD2(1, -334, 1, -40), V2(1, 1))   -- 比坦克的宽一点：右边放车钟梯子
  SH.car.Name = "Ship"
  SH.name = label(SH.car, "", UD2(1, -20, 0, 18), UD2(0, 12, 0, 8), 14, TXT, MED, nil, LEFT)
  SH.name.Name = "ShipName"
  local ssil = silBase(SH.car, 60, 94)
  SH.hull = frame(ssil, UD2(0, 90, 0, 90), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  SH.hull.Name = "Hull"
  SH.body = frame(SH.hull, UD2(0, 12, 0, 70), UD2(0.5, 0, 0.5, 4), RGB(30, 36, 40), 0.15, V2(0.5, 0.5))
  SH.bodyStroke = stroke(SH.body, OK, 1.5, 0)
  SH.bow = frame(SH.hull, UD2(0, 9, 0, 9), UD2(0.5, 0, 0.5, -31), RGB(30, 36, 40), 0.15, V2(0.5, 0.5))   -- 舰首：转 45° 的小方块
  SH.bow.Rotation = 45
  SH.bowStroke = stroke(SH.bow, OK, 1.5, 0)
  SH.turrets = {}
  SH.hp = hpBlock(SH.car, 124, 34)
  SH.kn = label(SH.car, "0", UD2(0, 70, 0, 40), UD2(0, 124, 0, 62), 36, TXT, BOLD, nil, LEFT)
  SH.kn.Name = "Knots"
  label(SH.car, "kn", UD2(0, 20, 0, 14), UD2(0, 124, 0, 100), 11, MUTE, MED, nil, LEFT)
  SH.order = label(SH.car, "", UD2(0, 90, 0, 14), UD2(0, 150, 0, 100), 11, AMBER, MED, nil, LEFT)
  SH.order.Name = "Order"
  -- 车钟梯子：−2 … 5 八格（上面是前进），亮的是现在这一档；「停」那一格白框
  SH.ladder = {}
  for o = -2, 5 do
    local y = 34 + (5 - o) * 11
    local c = frame(SH.car, UD2(0, 18, 0, 8), UD2(1, -30, 0, y), TXT, 0.85)
    if o == 0 then stroke(c, WHITE, 1, 0.3) end
    SH.ladder[o] = c
  end
  -- 舵角条：左右 35°
  local rBg = frame(SH.car, UD2(0, 132, 0, 3), UD2(0, 124, 0, 136), TXT, 0.86)
  frame(rBg, UD2(0, 1, 0, 9), UD2(0.5, 0, 0.5, 0), TXT, 0.3, V2(0.5, 0.5))
  SH.rud = frame(rBg, UD2(0, 4, 0, 11), UD2(0.5, 0, 0.5, 0), AMBER, 0, V2(0.5, 0.5))
  SH.rud.Name = "Rudder"
  SH.rudTxt = label(SH.car, "", UD2(0, 90, 0, 14), UD2(0, 124, 0, 118), 11, MUTE, MED, nil, LEFT)
  SH.hdg = label(SH.car, "", UD2(0, 70, 0, 14), UD2(1, -38, 0, 118), 11, MUTE, MONO, V2(1, 0), RIGHT)
  SH.arm = panel(hud, UD2(0, 300, 0, 156), UD2(1, -24, 1, -40), V2(1, 1))
  SH.arm.Name = "ShipWeapons"
  SH.rows = weaponRows(SH.arm, 4)
  SH.ring = reloadRing(SH.arm, 258, 66)
  SH.def = nil

  -- 小屏读数单独排版，避免把固定面板的字一起缩小。
  local MS = {}
  MS.box = panel(hud, UD2(0, 330, 0, 72), nil)
  MS.box.Name = "CompactInstruments"
  MS.box.Visible = false
  MS.speed = label(MS.box, "", UD2(0, 90, 0, 28), UD2(0, 10, 0, 3), 20, TXT, BOLD, nil, LEFT)
  MS.motion = label(MS.box, "", UD2(0, 90, 0, 16), UD2(0, 10, 0, 32), 12, TXT, MED, nil, LEFT)
  MS.heading = label(MS.box, "", UD2(0, 90, 0, 14), UD2(0, 10, 0, 50), 11, MUTE, MONO, nil, LEFT)
  MS.split = frame(MS.box, UD2(0, 1, 1, -16), nil, TXT, 0.82)
  MS.selection = label(MS.box, "", UD2(), nil, 13, TXT, BOLD, nil, LEFT)
  MS.count = label(MS.box, "", UD2(), nil, 12, TXT, MONO, nil, LEFT)
  MS.status = label(MS.box, "", UD2(0, 54, 0, 16), UD2(1, -8, 0, 24), 12, OK, BOLD, V2(1, 0), RIGHT)
  MS.health = label(MS.box, "", UD2(), nil, 11, MUTE, MED, nil, LEFT)
  MS.track = frame(MS.box, UD2(), nil, TXT, 0.82)
  MS.fill = frame(MS.track, UD2(0, 0, 1, 0), nil, OK, 0)
  MS.speed.Name, MS.motion.Name, MS.heading.Name = "Speed", "DriveState", "Heading"
  MS.selection.Name, MS.status.Name, MS.health.Name = "Selection", "Readiness", "Hull"
  MS.count.Name = "Ammo"
  for _, l in ipairs({ MS.speed, MS.motion, MS.selection, MS.count, MS.health }) do
    l.TextTruncate = Enum.TextTruncate.AtEnd
  end

  local function updateCompact(name, speed, motion, heading, hp, k, col, row, relK, ready, left)
    if not MS.box.Visible then return end
    local selected = row and row.name.Visible
    MS.speed.Text, MS.motion.Text, MS.heading.Text = speed, motion, heading
    MS.selection.Text = selected and row.name.Text or name
    MS.count.Text = selected and (string.gsub(row.ammo.Text, " / ", "/")) or ""
    MS.count.TextColor3 = selected and row.ammo.TextColor3 or TXT
    MS.status.Text = selected and (ready and T("vh.ready") or string.format("%.1fs", left)) or ""
    MS.status.TextColor3 = ready and OK or AMBER
    MS.health.Text, MS.health.TextColor3 = hp .. "  " .. string.format("%d%%", math.floor(k * 100 + 0.5)), col
    MS.track.Visible = selected == true
    MS.fill.BackgroundColor3 = ready and OK or AMBER
    MS.fill.Size = UD2(relK, 0, 1, 0)
  end

  local function buildShip(d)   -- 换船了：舰体长宽、炮塔的位置
    SH.def = d
    for _, t in ipairs(SH.turrets) do t.box:Destroy() end
    SH.turrets = {}
    local L, Wd = d.L or 200, d.W or 30
    local len = 70
    local wid = math.clamp(len * Wd / L * 1.6, 8, 22)   -- 窄长的舰体看着太细：宽度放大一点
    SH.body.Size = UD2(0, wid, 0, len)
    SH.bow.Size = UD2(0, wid * 0.72, 0, wid * 0.72)
    SH.bow.Position = UD2(0.5, 0, 0.5, 4 - len / 2)
    for gi, g in ipairs(d.guns or {}) do
      local z = g.pos and g.pos.Z or 0
      local x = g.pos and g.pos.X or 0
      local box = frame(SH.hull, UD2(0, 30, 0, 30), UD2(0.5, x / Wd * wid, 0.5, 4 + z / L * len), INK, 1, V2(0.5, 0.5))
      stroke(roundf(frame(box, UD2(0, 7, 0, 7), UD2(0.5, 0, 0.5, 0), RGB(46, 54, 58), 0, V2(0.5, 0.5))), CYAN, 1.2, 0)
      frame(box, UD2(0, 2, 0, 12), UD2(0.5, 0, 0.5, 0), CYAN, 0, V2(0.5, 1))
      SH.turrets[gi] = { box = box }
    end
  end

  ---------------------------------------------------------------- 顶上：罗盘（坦克、舰艇共用）
  local compGroup = frame(hud, UD2(0, 560, 0, 51), nil, INK, 1)
  compGroup.Name = "Compass"
  local comp = frame(compGroup, UD2(1, 0, 0, 38), nil, INK, 1)
  comp.ClipsDescendants = true
  local compBg = frame(comp, UD2(1, 0, 0, 22), UD2(0, 0, 0, 0), INK, 0.55)
  grad(compBg, 0, nseq(0, 1, 0.18, 0.45, 0.82, 0.45, 1, 1))
  local PX, CW = 4, 560   -- 每度几个像素、罗盘宽
  local ticks = {}
  for i = 1, 40 do
    ticks[i] = { t = frame(comp, UD2(0, 1, 0, 6), UD2(0, 0, 0, 0), TXT, 0.35), l = label(comp, "", UD2(0, 30, 0, 14), UD2(0, 0, 0, 7), 11, TXT, MONO, V2(0.5, 0)) }
  end
  label(compGroup, "▼", UD2(0, 16, 0, 12), UD2(0.5, 0, 0, 18), 11, TXT, BOLD, V2(0.5, 0))
  local compHdg = label(compGroup, "000", UD2(0, 60, 0, 18), UD2(0.5, 0, 0, 32), 15, TXT, MONO, V2(0.5, 0))
  compHdg.Name = "Heading"
  local compMark = label(comp, "▲", UD2(0, 14, 0, 10), UD2(0.5, 0, 0, 24), 10, AMBER, BOLD, V2(0.5, 0))
  compMark.Name = "MarkHeading"
  local DIR = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
  local function deg360(r) return (math.deg(r) % 360 + 360) % 360 end
  local function hdgOf(yaw) return (360 - deg360(yaw or 0)) % 360 end   -- 偏航（逆时针、从 −Z 起）→ 航向（顺时针从北）
  local function stepCompass(camHdg, markHdg)
    if not compGroup.Visible then return end
    local first = math.floor((camHdg - CW / 2 / PX) / 5) * 5
    for i, tk in ipairs(ticks) do
      local a = first + (i - 1) * 5
      local x = CW / 2 + (a - camHdg) * PX
      local aa = a % 360
      local major = aa % 15 == 0
      tk.t.Position = UD2(0, x, 0, 0)
      tk.t.Size = UD2(0, 1, 0, major and 8 or 4)
      tk.l.Position = UD2(0, x, 0, 8)
      tk.l.Text = major and (DIR[aa] or string.format("%03d", aa)) or ""
      tk.l.TextColor3 = DIR[aa] and TXT or MUTE
    end
    compHdg.Text = string.format("%03d", math.floor(camHdg + 0.5) % 360)
    local dg = (markHdg - camHdg + 540) % 360 - 180
    compMark.Position = UD2(0, CW / 2 + math.clamp(dg, -CW / 2 / PX, CW / 2 / PX) * PX, 0, 24)
  end

  ---------------------------------------------------------------- 中间：准星——坦克照 MWT（现代战争坦克）、舰艇照《现代战舰》，两套样子
  --   用户 11-19：「船、坦克的准心可以不一样，参考 MWT 和现代战舰」
  local camAim = roundf(frame(ret, UD2(0, 14, 0, 14), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))
  stroke(camAim, WHITE, 1.5, 0.35)
  camAim.Name = "CamAim"
  local Config = require(RS:WaitForChild("Config"))
  -- 圆上一圈小短条（Roblox 没有弧线）：from / to 度数（0 正上、顺时针），每条切着圆
  local function arcSegs(parent, n, r, w, h, from, to, col)
    local segs = {}
    for i = 1, n do
      local a = from + (to - from) * (i - 0.5) / n
      local rad = math.rad(a)
      local sg0 = frame(parent, UD2(0, w, 0, h), UD2(0.5, math.sin(rad) * r, 0.5, -math.cos(rad) * r), col or TXT, 0, V2(0.5, 0.5))
      sg0.Rotation = a
      segs[i] = sg0
    end
    return segs
  end
  local PEN_OK, PEN_MAYBE, PEN_NO = RGB(96, 236, 128), RGB(255, 214, 72), RGB(255, 72, 60)

  -- 坦克（MWT）：四段弧（对角留缺口）围着炮指的点，装填时顺时针一段段亮起来；弧的颜色 = 打不打得穿（绿 / 黄 / 红，没瞄着车是白的）；
  --   左、右、下三道刻度，中心一个点；下面一行「可击穿 / 可能跳弹 / 跳弹 / 打不穿」，右边测距、左边装填秒数
  local TR = {}
  TR.root = frame(ret, UD2(0, 120, 0, 120), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  TR.root.Name = "TankReticle"
  TR.scale = Instance.new("UIScale")
  TR.scale.Parent = TR.root
  TR.segs = {}
  for q = 0, 3 do
    for _, sgx in ipairs(arcSegs(TR.root, 9, 22, 3.4, 2, q * 90 - 33, q * 90 + 33)) do table.insert(TR.segs, sgx) end
  end
  TR.ticks = {}
  for _, a in ipairs({ 90, 180, 270 }) do
    local rad = math.rad(a)
    local tk = frame(TR.root, UD2(0, 2, 0, 9), UD2(0.5, math.sin(rad) * 32, 0.5, -math.cos(rad) * 32), TXT, 0, V2(0.5, 0.5))
    tk.Rotation = a
    table.insert(TR.ticks, tk)
  end
  TR.dot = roundf(frame(TR.root, UD2(0, 3, 0, 3), UD2(0.5, 0, 0.5, 0), TXT, 0, V2(0.5, 0.5)))
  TR.pen = label(TR.root, "", UD2(0, 160, 0, 14), UD2(0.5, 0, 0.5, 46), 12, TXT, BOLD, V2(0.5, 0.5))
  TR.pen.Name = "PenState"
  TR.pen.TextStrokeTransparency = 0.55
  TR.rng = label(TR.root, "", UD2(0, 80, 0, 14), UD2(0.5, 42, 0.5, 0), 12, TXT, MONO, V2(0, 0.5), LEFT)
  TR.rng.Name = "Range"
  TR.rng.TextStrokeTransparency = 0.6
  TR.rel = label(TR.root, "", UD2(0, 60, 0, 14), UD2(0.5, -42, 0.5, 0), 12, AMBER, MONO, V2(1, 0.5), RIGHT)
  TR.rel.Name = "ReloadLeft"
  TR.rel.TextStrokeTransparency = 0.6
  local lagArrow = label(ret, "▶", UD2(0, 16, 0, 16), UD2(0, 0, 0, 0), 13, AMBER, BOLD, V2(0.5, 0.5))
  lagArrow.Name = "TurretLag"

  -- 舰艇（《现代战舰》）：主炮落点一个细的大圈、四根长线（横线上有刻度）、中间菱形；外圈 40 段装填；右下距离、炮弹飞多久，左下炮名；
  --   瞄着的敌人：上方一张卡（名字、距离、血条），照它的航速和炮弹飞的时间算提前量（琥珀色小圈 + 一串点连过去）；
  --   导弹：四个角框住目标，刚框上从大往小收，框住琥珀、锁定红，下面写距离和导弹飞过去要多久
  local SR = {}
  SR.root = frame(ret, UD2(0, 240, 0, 240), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  SR.root.Name = "ShipReticle"
  SR.scale = Instance.new("UIScale")
  SR.scale.Parent = SR.root
  SR.ring = roundf(frame(SR.root, UD2(0, 76, 0, 76), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))
  SR.ringStroke = stroke(SR.ring, CYAN, 1.2, 0.1)
  SR.lines = {}
  for _, e in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local hz = e[1] ~= 0
    local L0, L = 46, 40
    table.insert(SR.lines, frame(SR.root, hz and UD2(0, L, 0, 1) or UD2(0, 1, 0, L), UD2(0.5, e[1] * (L0 + L / 2), 0.5, e[2] * (L0 + L / 2)), CYAN, 0.15, V2(0.5, 0.5)))
    if hz then
      for k = 1, 4 do table.insert(SR.lines, frame(SR.root, UD2(0, 1, 0, (k % 2 == 0) and 7 or 4), UD2(0.5, e[1] * (L0 + k * 9), 0.5, 0), CYAN, 0.2, V2(0.5, 0.5))) end
    end
  end
  SR.dia = frame(SR.root, UD2(0, 9, 0, 9), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  SR.dia.Rotation = 45
  SR.diaStroke = stroke(SR.dia, WHITE, 1.5, 0)
  frame(SR.root, UD2(0, 2, 0, 2), UD2(0.5, 0, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
  SR.segs = arcSegs(SR.root, 40, 47, 5.4, 2, 0, 360, CYAN)
  SR.rng = label(SR.root, "", UD2(0, 90, 0, 14), UD2(0.5, 50, 0.5, 30), 12, TXT, MONO, V2(0, 0.5), LEFT)
  SR.rng.Name = "Range"
  SR.tof = label(SR.root, "", UD2(0, 90, 0, 14), UD2(0.5, 50, 0.5, 44), 11, CYAN, MONO, V2(0, 0.5), LEFT)
  SR.tof.Name = "FlightTime"
  SR.wpn = label(SR.root, "", UD2(0, 120, 0, 14), UD2(0.5, -50, 0.5, 30), 11, MUTE, MED, V2(1, 0.5), RIGHT)
  for _, l in ipairs({ SR.rng, SR.tof, SR.wpn }) do l.TextStrokeTransparency = 0.6 end
  SR.lead = roundf(frame(ret, UD2(0, 14, 0, 14), nil, INK, 1, V2(0.5, 0.5)))
  SR.lead.Name = "LeadMark"
  stroke(SR.lead, AMBER, 1.6, 0)
  SR.leadDots = {}
  for i = 1, 6 do SR.leadDots[i] = roundf(frame(ret, UD2(0, 3, 0, 3), nil, AMBER, 0.25, V2(0.5, 0.5))) end
  SR.card = frame(ret, UD2(0, 160, 0, 30), nil, INK, 1, V2(0.5, 1))
  SR.card.Name = "TargetCard"
  SR.cardName = label(SR.card, "", UD2(1, 0, 0, 14), UD2(0, 0, 0, 0), 12, TXT, BOLD)
  SR.cardName.TextStrokeTransparency = 0.55
  SR.cardBg = frame(SR.card, UD2(0, 110, 0, 4), UD2(0.5, 0, 0, 18), INK, 0.35, V2(0.5, 0))
  SR.cardHp = frame(SR.cardBg, UD2(1, 0, 1, 0), nil, BAD, 0)
  SR.lock = frame(ret, UD2(0, 60, 0, 60), nil, INK, 1, V2(0.5, 0.5))
  SR.lock.Name = "MissileLock"
  SR.corners = {}
  for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local h = frame(SR.lock, UD2(0, 14, 0, 2), UD2(c[1], 0, c[2], 0), PEN_MAYBE, 0, V2(c[1], c[2]))
    local v = frame(SR.lock, UD2(0, 2, 0, 14), UD2(c[1], 0, c[2], 0), PEN_MAYBE, 0, V2(c[1], c[2]))
    table.insert(SR.corners, h)
    table.insert(SR.corners, v)
  end
  SR.lockTxt = label(ret, "", UD2(0, 260, 0, 16), nil, 12, PEN_MAYBE, BOLD, V2(0.5, 0))
  SR.lockTxt.Name = "LockText"
  SR.lockTxt.TextStrokeTransparency = 0.5

  local fireCC = Instance.new("ColorCorrectionEffect")
  fireCC.Name = "VehFireFlash"
  fireCC.Brightness = 0
  fireCC.Parent = Lighting
  local kickT = -9

  ---------------------------------------------------------------- 瞄着谁：实体（workspace.Ents 下的模型）、它的航速
  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  local function entOf(inst)
    local ents = workspace:FindFirstChild("Ents")
    while inst and inst.Parent and inst.Parent ~= ents do inst = inst.Parent end
    return (inst and inst.Parent == ents) and inst or nil
  end
  local vel = setmetatable({}, { __mode = "k" })   -- [实体模型] = { p 上次位置, t 时间, v 平滑后的速度 }
  local function velOf(em)
    local r = em:FindFirstChild("Root")
    if not r then return V3(0, 0, 0) end
    local p, t = r.CFrame.Position, os.clock()
    local s = vel[em]
    if not s then
      vel[em] = { p = p, t = t, v = V3(0, 0, 0) }
      return V3(0, 0, 0)
    end
    local dt = t - s.t
    if dt > 0.05 then
      local raw = (p - s.p) / dt
      if raw.Magnitude > 600 then raw = s.v end   -- 瞬移（重生、拉回）不算
      s.v = s.v:Lerp(raw, math.min(1, dt * 4))
      s.p, s.t = p, t
    end
    return s.v
  end
  local function enemyEnt(em)
    if not em or em:GetAttribute("Wreck") or (em:GetAttribute("Hp") or 1) <= 0 then return false end
    local tm = em:GetAttribute("Team")
    return tm ~= nil and tm ~= me:GetAttribute("Side")
  end
  -- 屏幕上离 (x, y) 最近的敌方水面目标 / 地面车辆（R 像素以内）
  local nearT, nearEm = 0, nil
  local function enemyNear(x, y, R)
    if os.clock() - nearT < 0.12 then return nearEm end
    nearT, nearEm = os.clock(), nil
    local ents = workspace:FindFirstChild("Ents")
    local best = R
    for _, em in ipairs(ents and ents:GetChildren() or {}) do
      local cat = em:GetAttribute("Cat")
      if (cat == "ship" or cat == "armor" or cat == "light") and enemyEnt(em) then
        local r = em:FindFirstChild("Root")
        if r then
          local sp, on = cam:WorldToViewportPoint(r.CFrame.Position)
          if on then
            local dd = (V2(sp.X, sp.Y) - V2(x, y)).Magnitude
            if dd < best then best, nearEm = dd, em end
          end
        end
      end
    end
    return nearEm
  end

  -- 坦克炮打过去打不打得穿：照服务器（Ents.lua）的跳弹算法——入射方向和装甲面法线的夹角、目标是重甲（armor）还是轻甲（light）
  --   返回 颜色、字（没瞄着敌方车辆返回 nil）
  local function penState(w, o, p, own)
    local dir = p - o
    if dir.Magnitude < 1 then return nil end
    local ex = { own }
    if me.Character then table.insert(ex, me.Character) end
    if G.viewFolder then table.insert(ex, G.viewFolder) end
    rayP.FilterDescendantsInstances = ex
    local res = workspace:Raycast(o, dir.Unit * (dir.Magnitude + 6), rayP)
    local em = res and entOf(res.Instance)
    if not em or not enemyEnt(em) then return nil end
    local cat = em:GetAttribute("Cat")
    local RIC = Config.Ricochet
    local k = (w.vs and w.vs[cat]) or 1
    if k < 0.35 then return PEN_NO, T("vh.penNo") end   -- 机枪、小口径打重甲
    if w.kind ~= "shell" or not (RIC and RIC.a0[cat]) then return PEN_OK, T("vh.penOk") end
    local ang = math.deg(math.acos(math.clamp(math.abs(dir.Unit:Dot(res.Normal)), 0, 1)))
    local pr = math.clamp((ang - RIC.a0[cat]) / math.max(1, RIC.a1[cat] - RIC.a0[cat]), 0, 1)
    if pr >= 0.75 then return PEN_NO, T("vh.penRic") end
    if pr > 0.04 or ang > RIC.a0[cat] - 6 then return PEN_MAYBE, T("vh.penMaybe", math.floor(pr * 100 + 0.5)) end
    return (k < 0.7) and PEN_MAYBE or PEN_OK, T((k < 0.7) and "vh.penWeak" or "vh.penOk")
  end

  -- 坦克的准星摆到屏幕上：p 炮指着的点、o 炮口、relK / ready / left 装填、pen 颜色和字
  local function placeTank(p, o, relK, ready, left, lag, penC, penT)
    SR.root.Visible, SR.lead.Visible, SR.card.Visible, SR.lock.Visible, SR.lockTxt.Visible = false, false, false, false, false
    for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
    local sp, on = cam:WorldToViewportPoint(p)
    local vp = cam.ViewportSize
    TR.root.Visible = on
    local kick = reducedMotion and 0 or math.clamp(1 - (os.clock() - kickT) / 0.35, 0, 1)
    TR.scale.Scale = 1 + 0.4 * kick
    TR.root.Position = UD2(0, sp.X, 0, sp.Y)
    local col = penC or TXT
    local lit = ready and #TR.segs or math.floor(relK * #TR.segs + 0.001)
    for i, sgx in ipairs(TR.segs) do
      local onSeg = i <= lit
      sgx.BackgroundColor3 = onSeg and (ready and col or AMBER) or TXT
      sgx.BackgroundTransparency = onSeg and 0.02 or 0.72
    end
    for _, tk in ipairs(TR.ticks) do tk.BackgroundColor3 = col end
    TR.dot.BackgroundColor3 = col
    TR.pen.Text = penT or ""
    TR.pen.TextColor3 = col
    TR.rng.Text = string.format("%d m", math.floor((p - o).Magnitude / 2.8 / 5 + 0.5) * 5)
    TR.rel.Text = ready and "" or string.format("%.1f", left)
    local off = V2(vp.X / 2, vp.Y / 2) - V2(sp.X, sp.Y)
    lagArrow.Visible = lag and on and off.Magnitude > 30
    if lagArrow.Visible then
      local u = off.Unit
      lagArrow.Position = UD2(0, sp.X + u.X * 40, 0, sp.Y + u.Y * 40)
      lagArrow.Rotation = math.deg(math.atan2(u.Y, u.X))
    end
    fireCC.Brightness = 0.12 * kick * kick
  end
  G.tankPen = penState   -- 测试用

  local function hideReticles()
    TR.root.Visible, SR.root.Visible, lagArrow.Visible = false, false, false
    SR.lead.Visible, SR.card.Visible, SR.lock.Visible, SR.lockTxt.Visible = false, false, false, false
    for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
    fireCC.Brightness = 0
  end

  ---------------------------------------------------------------- 每帧：坦克
  local lastNext, hp0, hurtT = {}, nil, -9
  local function hpColor(em)
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    local k = math.clamp(hp / math.max(mx, 1), 0, 1)
    if hp0 and hp < hp0 - 0.5 then hurtT = os.clock() end
    hp0 = hp
    local col = (k > 0.6) and OK or ((k > 0.3) and AMBER or BAD)
    if os.clock() - hurtT < 0.6 and (reducedMotion or (os.clock() * 10) % 2 < 1) then col = BAD end
    return k, col
  end

  local function stepTank(st)
    local d = st.d
    local vs = G.S and G.S.veh
    TK.name.Text = T("veh." .. d.id)
    TK.hp.lab.Text = T("vh.hull")
    local k, col = hpColor(st.em)
    TK.hullStroke.Color = col
    setHp(TK.hp, k, col)
    local camY = math.deg(st.camYaw or 0)
    local hullY = math.deg(st.yaw or 0)
    TK.hull.Rotation = -(hullY - camY)
    TK.tur.Rotation = -(hullY - (st.ty or 0) - camY)
    TK.tur.Visible = d.turret ~= nil
    TK.spd.Text = string.format("%d", math.floor(math.abs(st.speed or 0) / 2.8 * 3.6 + 0.5))
    local back = (st.speed or 0) < -0.4
    local gn = st.gearN or 0   -- Drive 的变速箱：1～5 档、R、N（战雷那样显示档位数字）
    TK.gear.Text = st.locked and "-" or ((gn >= 1) and tostring(gn) or (back and "R" or "N"))
    TK.gear.TextColor3 = back and AMBER or TXT
    TK.hdg.Text = string.format("%03d°  HDG", math.floor(hdgOf(st.yaw) + 0.5) % 360)
    TK.thr.Size = UD2(math.clamp(math.abs(st.speed or 0) / math.max(d.speed or 1, 1), 0, 1), 0, 1, 0)
    local relK, ready, left = 1, true, 0
    for i, r in ipairs(TK.rows) do
      local wid = d.weapons[i]
      if wid then
        local w = VD.W[wid]
        local ammo = vs and vs.ammo and vs.ammo[wid]
        setRow(r, tostring(i), T("vw." .. wid), ammo and string.format("%d / %d", ammo[1], ammo[2]) or "∞", i == st.wi, ammo and ammo[1] + ammo[2] == 0)
        if i == st.wi and w then
          local l = (st.next[wid] or 0) - os.clock()
          local full = (ammo and ammo[1] == w.mag and l > w.rate) and (w.reload or w.rate) or w.rate
          relK = 1 - math.clamp(l / math.max(full, 0.01), 0, 1)
          ready, left = l <= 0, math.max(0, l)
          if lastNext[wid] and (st.next[wid] or 0) > lastNext[wid] + 0.05 and (w.dmg or 0) > 150 then kickT = os.clock() end
        end
        lastNext[wid] = st.next[wid] or 0
      else
        setRow(r, nil, nil)
      end
    end
    TK.smoke.Text = string.format("X   %s ×%d", T("vh.smoke"), vs and vs.smoke or 0)
    setRing(TK.ring, relK, ready, left)
    local gear = TK.gear.Text
    updateCompact(TK.name.Text, TK.spd.Text .. " km/h", tonumber(gear) and ("D" .. gear) or gear, TK.hdg.Text,
      TK.hp.lab.Text, k, col, TK.rows[st.wi], relK, ready, left)
    stepCompass(hdgOf(st.camYaw), hdgOf((st.yaw or 0) - math.rad(st.ty or 0)))
    local hasGun = d.turret ~= nil and d.gun ~= nil and d.weapons[1] ~= nil
    if not hasGun then
      hideReticles()
      return
    end
    local base = st.root * CFrame.new(0, -d.H / 2, 0)
    local gcf = VD.gunCF(d, base, st.ty or 0, st.gp or 0)
    local aim = st.aimPt or (gcf.Position + gcf.LookVector * 200)
    local pt = gcf.Position + gcf.LookVector * math.max(30, (aim - gcf.Position).Magnitude)
    local wid = d.weapons[st.wi]
    local w = wid and VD.W[wid]
    local penC, penT = nil, nil
    if w then penC, penT = penState(w, gcf.Position, pt, st.em) end
    placeTank(pt, gcf.Position, relK, ready, left, true, penC, penT)
  end

  -- 舰艇主炮的准星：p 落点、o 炮口、tof 炮弹飞多久；瞄着的敌人：目标卡 + 提前量
  local function placeShip(p, o, relK, ready, left, tof, wname)
    local sp, on = cam:WorldToViewportPoint(p)
    SR.root.Visible = on
    local kick = reducedMotion and 0 or math.clamp(1 - (os.clock() - kickT) / 0.35, 0, 1)
    SR.scale.Scale = 1 + 0.25 * kick
    SR.root.Position = UD2(0, sp.X, 0, sp.Y)
    local col = ready and CYAN or AMBER
    SR.ringStroke.Color = col
    for _, l in ipairs(SR.lines) do l.BackgroundColor3 = col end
    local lit = ready and #SR.segs or math.floor(relK * #SR.segs + 0.001)
    for i, sgx in ipairs(SR.segs) do
      sgx.BackgroundColor3 = ready and CYAN or AMBER
      sgx.BackgroundTransparency = (i <= lit) and (ready and 0.35 or 0.02) or 0.8
    end
    local km = (p - o).Magnitude / 2.8 / 1000
    SR.rng.Text = (km >= 1) and string.format("%.1f km", km) or string.format("%d m", math.floor(km * 1000 / 5 + 0.5) * 5)
    SR.tof.Text = ready and string.format("T %.1f s", tof or 0) or string.format("%s %.1f", T("vh.reload"), left)
    SR.tof.TextColor3 = ready and CYAN or AMBER
    SR.wpn.Text = wname or ""
    fireCC.Brightness = 0.1 * kick * kick
    -- 瞄着的敌人（落点附近 90 像素内最近的）
    local em = on and enemyNear(sp.X, sp.Y, 90) or nil
    local r = em and em:FindFirstChild("Root")
    if not r then
      SR.card.Visible, SR.lead.Visible = false, false
      for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
      return
    end
    local tp = r.CFrame.Position
    local tsp, ton = cam:WorldToViewportPoint(tp)
    local size = r.Size.Magnitude
    local top = cam:WorldToViewportPoint(tp + V3(0, r.Size.Y * 0.5 + size * 0.06, 0))
    SR.card.Visible = ton
    SR.card.Position = UD2(0, tsp.X, 0, top.Y - 8)
    local key = "veh." .. tostring(em:GetAttribute("Model") or em:GetAttribute("Kind") or "")
    SR.cardName.Text = string.format("%s   %.1f km", T(key), (tp - o).Magnitude / 2800)
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    SR.cardHp.Size = UD2(math.clamp(hp / math.max(1, mx), 0, 1), 0, 1, 0)
    -- 提前量：炮弹落下去的时候它开到哪
    local v = velOf(em)
    local fut = tp + V3(v.X, 0, v.Z) * (tof or 0)
    local lsp, lon = cam:WorldToViewportPoint(fut)
    local show = ton and lon and V3(v.X, 0, v.Z).Magnitude > 2
    SR.lead.Visible = show
    if show then
      SR.lead.Position = UD2(0, lsp.X, 0, lsp.Y)
      for i, dd in ipairs(SR.leadDots) do
        local k = i / (#SR.leadDots + 1)
        dd.Visible = true
        dd.Position = UD2(0, tsp.X + (lsp.X - tsp.X) * k, 0, tsp.Y + (lsp.Y - tsp.Y) * k)
      end
    else
      for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
    end
  end
  G.shipLead = function() return SR.lead.Visible and SR.lead.Position or nil end   -- 测试用

  -- 导弹锁定（《现代战舰》）：四个角框住目标；刚框上 0.5 秒从两倍大收到贴着目标（琥珀「锁定中」），收好了 / 按了锁定键变红
  local lockEm, lockT0 = nil, 0
  local function placeLock(st)
    local lk = (st.wi == 2) and st.lock or nil
    local r = lk and lk.root
    if not r or not r.Parent then
      SR.lock.Visible = false
      SR.lockTxt.Visible = st.wi == 2
      SR.lockTxt.Text = T("ship.noLock")
      SR.lockTxt.TextColor3 = MUTE
      SR.lockTxt.Position = UD2(0.5, 0, 0.5, 46)
      lockEm = nil
      return
    end
    if lk.em ~= lockEm then lockEm, lockT0 = lk.em, os.clock() end
    local tp = r.CFrame.Position
    local sp, on = cam:WorldToViewportPoint(tp)
    local dist = (tp - cam.CFrame.Position).Magnitude
    local px = math.clamp(r.Size.Magnitude / math.max(dist, 1) * cam.ViewportSize.Y * 0.9, 34, 170)
    local a = math.clamp((os.clock() - lockT0) / 0.5, 0, 1)
    local locked = a >= 1 or st.sticky
    local sz = px * (1 + (1 - a) * (1 - a) * 1.2)
    SR.lock.Visible = on
    SR.lock.Position = UD2(0, sp.X, 0, sp.Y)
    SR.lock.Size = UD2(0, sz, 0, sz)
    local col = locked and PEN_NO or PEN_MAYBE
    for _, c in ipairs(SR.corners) do c.BackgroundColor3 = col end
    local key = (lk.kind == "fort") and ("fort." .. tostring(lk.em:GetAttribute("Model") or "bunker"))
      or ("veh." .. ((lk.d and lk.d.id) or (lk.def and lk.def.id) or lk.kind or ""))
    local own = st.em and st.em:FindFirstChild("Root")
    local km = own and (tp - own.CFrame.Position).Magnitude or dist
    local msp = (SD.W.asm and SD.W.asm.speed) or 320
    SR.lockTxt.Visible = on
    SR.lockTxt.Position = UD2(0, sp.X, 0, sp.Y + sz / 2 + 8)
    SR.lockTxt.TextColor3 = col
    SR.lockTxt.Text = string.format("%s  %s   %.1f km   ETA %.0f s", locked and T("ship.locked") or T("ship.locking"), T(key), km / 2800, km / (msp * 0.85) + 1)
  end
  G.shipLockState = function() return SR.lock.Visible, SR.corners[1].BackgroundColor3 end   -- 测试用

  ---------------------------------------------------------------- 每帧：舰艇
  local function stepShip(st)
    local d = st.d
    local vs = G.S and G.S.veh
    if SH.def ~= d then buildShip(d) end
    SH.name.Text = T("veh." .. d.id) .. ((vs and vs.rest and vs.rest > 0) and ("   " .. T("ship.rest")) or "")
    SH.hp.lab.Text = T("vh.hullShip")
    local k, col = hpColor(st.em)
    SH.bodyStroke.Color, SH.bowStroke.Color = col, col
    setHp(SH.hp, k, col)
    local camY = math.deg(st.camYaw or 0)
    local hullY = math.deg(st.yaw or 0)
    SH.hull.Rotation = -(hullY - camY)
    for gi, t in ipairs(SH.turrets) do t.box.Rotation = st.ty[gi] or 0 end
    SH.kn.Text = string.format("%d", math.floor(math.abs(st.speed or 0) / 2.8 * 1.944 + 0.5))
    SH.order.Text = T("ship.order." .. (st.order or 0))
    for o, c in pairs(SH.ladder) do
      local on = o == st.order
      c.BackgroundColor3 = on and ((o < 0) and AMBER or ((o == 0) and TXT or OK)) or TXT
      c.BackgroundTransparency = on and 0.02 or 0.85
    end
    local rd = math.floor(math.abs(st.rudder or 0) * 35 + 0.5)
    SH.rud.Position = UD2(0.5, (st.rudder or 0) * 64, 0.5, 0)
    SH.rudTxt.Text = (rd == 0) and T("ship.mid") or T(((st.rudder or 0) > 0) and "ship.right" or "ship.left", rd)
    SH.hdg.Text = string.format("%03d°", math.floor(hdgOf(st.yaw) + 0.5) % 360)
    -- 武器：主炮、反舰导弹、防空导弹、近防炮
    local t = os.clock()
    local relK, ready, left = 1, true, 0
    local g1 = d.guns and d.guns[1]
    if g1 then
      setRow(SH.rows[1], "1", T("sw." .. g1.w) .. ((#d.guns > 1) and (" ×" .. #d.guns) or ""), "∞", st.wi == 1)
      if st.wi == 1 then
        local w = SD.W[g1.w]
        local l = (st.next[1] or 0) - t
        relK, ready, left = 1 - math.clamp(l / math.max(w and w.rate or 1, 0.01), 0, 1), l <= 0, math.max(0, l)
        if lastNext.s1 and (st.next[1] or 0) > lastNext.s1 + 0.05 then kickT = t end
        lastNext.s1 = st.next[1] or 0
      end
    else
      setRow(SH.rows[1], nil, nil)
    end
    if d.missiles then
      local n = vs and vs.msl or 0
      setRow(SH.rows[2], "2", T("sw." .. (d.missiles.name or "yj83")), tostring(n), st.wi == 2, n == 0)
      if st.wi == 2 then
        local l = (st.mslT or 0) - t
        relK, ready, left = 1 - math.clamp(l / 1.3, 0, 1), l <= 0, math.max(0, l)
      end
    else
      setRow(SH.rows[2], nil, nil)
    end
    if d.sam then setRow(SH.rows[3], nil, T("vh.sam"), tostring(vs and vs.sam or 0), false) else setRow(SH.rows[3], nil, nil) end
    if d.ciws and #d.ciws > 0 then setRow(SH.rows[4], nil, T("vh.ciws"), T("vh.auto"), false) else setRow(SH.rows[4], nil, nil) end
    setRing(SH.ring, relK, ready, left)
    updateCompact(SH.name.Text, T("ship.kn", SH.kn.Text), SH.order.Text, SH.hdg.Text,
      SH.hp.lab.Text, k, col, SH.rows[st.wi], relK, ready, left)
    stepCompass(hdgOf(st.camYaw), hdgOf(st.yaw))
    -- 准星：主炮的落点（《现代战舰》的大圈）、导弹的锁定框
    TR.root.Visible, lagArrow.Visible = false, false
    local fp = (st.wi == 1 and G.sailFall and g1) and G.sailFall(1) or nil
    if fp then
      local w = SD.W[g1.w]
      local mz = SD.muzzle(d, st.cf, 1, st.ty[1] or 0, st.gp[1] or 0)
      local h = V3(fp.X - mz.Position.X, 0, fp.Z - mz.Position.Z).Magnitude
      local lv = mz.LookVector
      local tof = (w.kind == "gun") and ((fp - mz.Position).Magnitude / 1500) or (h / math.max(1, w.speed * math.sqrt(lv.X * lv.X + lv.Z * lv.Z)))
      placeShip(fp, mz.Position, relK, ready and (st.onT and st.onT[1]) ~= false, left, tof, T("sw." .. g1.w))
    else
      SR.root.Visible, SR.lead.Visible, SR.card.Visible = false, false, false
      for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
      fireCC.Brightness = 0
    end
    placeLock(st)
  end

  ---------------------------------------------------------------- 坦克瞄准镜里（Drive.lua 画目镜、分划、测距数字；这里在镜里补战雷那一套仪表）
  -- 分划外一圈 32 颗点的装填环（装好变绿）；左边竖着的测距尺（0～2000 米，每 200 米一格、每 400 米一个数，小三角指着现在测到的距离）；
  --   下面一行：选中的弹、弹药、装填状态；上面一条小罗盘（炮管朝向）
  local sg = Instance.new("ScreenGui")
  sg.Name = "VehSight"
  sg.ResetOnSpawn = false
  sg.IgnoreGuiInset = true
  sg.DisplayOrder = 7
  sg.Enabled = false
  sg.Parent = me:WaitForChild("PlayerGui")
  local SG = { dots = {}, ticks = {} }
  -- 开炮后镜里一阵炮口烟、土（战雷那样前面一下子看不清，一秒多散掉）：颜色跟着光电模式（夜视绿、热成像灰）
  SG.haze = Instance.new("Frame")
  SG.haze.Name = "MuzzleHaze"
  SG.haze.Size = UDim2.fromScale(0.9, 0.9)   -- 跟 Drive 的目镜一样大的圆：烟只在镜片里，外面的黑边不染色
  SG.haze.AnchorPoint = V2(0.5, 0.5)
  SG.haze.Position = UDim2.fromScale(0.5, 0.5)
  SG.haze.BorderSizePixel = 0
  do
    local a = Instance.new("UIAspectRatioConstraint")
    a.AspectRatio = 1
    a.Parent = SG.haze
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = SG.haze
  end
  SG.haze.BackgroundTransparency = 1
  SG.haze.ZIndex = 0
  SG.haze.Parent = sg
  do
    local gr = Instance.new("UIGradient")
    gr.Rotation = 90
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.55, 0), NumberSequenceKeypoint.new(1, 0.15) })
    gr.Parent = SG.haze
  end
  SG.ring = frame(sg, UD2(0, 180, 0, 180), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  SG.ring.Name = "SightReload"
  for i = 1, 32 do
    local a = (i - 0.5) / 32 * 2 * math.pi
    SG.dots[i] = roundf(frame(SG.ring, UD2(0, 4, 0, 4), UD2(0.5, math.sin(a) * 86, 0.5, -math.cos(a) * 86), TXT, 0.7, V2(0.5, 0.5)))
  end
  SG.scale = frame(sg, UD2(0, 60, 0, 220), UD2(0.5, -250, 0.5, 0), INK, 1, V2(0.5, 0.5))
  SG.scale.Name = "RangeScale"
  frame(SG.scale, UD2(0, 2, 1, 0), UD2(0, 30, 0, 0), TXT, 0.35)
  for i = 0, 10 do
    local y = 220 - i * 22
    local major = i % 2 == 0
    frame(SG.scale, UD2(0, major and 12 or 7, 0, 2), UD2(0, 32, 0, y - 1), TXT, 0.3)
    if major then label(SG.scale, tostring(i * 2), UD2(0, 26, 0, 14), UD2(0, 0, 0, y - 7), 12, TXT, MONO, nil, RIGHT) end
  end
  SG.ptr = label(SG.scale, "◀", UD2(0, 14, 0, 14), UD2(0, 46, 0, 0), 12, AMBER, BOLD, V2(0, 0.5))
  SG.ptr.Name = "RangePointer"
  label(SG.scale, "×100m", UD2(0, 60, 0, 12), UD2(0, 0, 1, 6), 10, MUTE, MONO)
  -- 右边跟左边测距尺对称：选中的弹 / 弹药 / 装填（下面 Drive 的测距数字和倍率不挡）
  SG.info = frame(sg, UD2(0, 184, 0, 43), nil, INK, 0.19)
  SG.info.Name = "SightStatus"
  stroke(SG.info, WHITE, 1, 0.79)
  SG.ammo = label(SG.info, "", UD2(1, -74, 0, 18), UD2(0, 10, 0, 4), 13, TXT, MED, nil, LEFT)
  SG.ammo.Name = "SightAmmo"
  SG.ammo.TextTruncate = Enum.TextTruncate.AtEnd
  SG.count = label(SG.info, "", UD2(0, 50, 0, 18), UD2(1, -8, 0, 4), 12, TXT, MONO, V2(1, 0), RIGHT)
  SG.state = label(SG.info, "", UD2(1, -20, 0, 16), UD2(0, 10, 0, 23), 12, OK, BOLD, nil, LEFT)
  SG.comp = frame(sg, UD2(0, 300, 0, 22), UD2(0.5, 0, 0.5, -215), INK, 1, V2(0.5, 0))
  SG.comp.ClipsDescendants = true
  for i = 1, 24 do
    SG.ticks[i] = { t = frame(SG.comp, UD2(0, 1, 0, 5), UD2(0, 0, 0, 0), TXT, 0.4), l = label(SG.comp, "", UD2(0, 28, 0, 12), UD2(0, 0, 0, 6), 10, TXT, MONO, V2(0.5, 0)) }
  end
  SG.marker = label(sg, "▼", UD2(0, 14, 0, 10), UD2(0.5, 0, 0.5, -226), 9, AMBER, BOLD, V2(0.5, 0))
  local sightRingScale = Instance.new("UIScale")
  sightRingScale.Parent = SG.ring

  -- 触屏左下的方向键最右到 x=250，右侧操作键最下到离底部 120 px。
  local function compactDock(vp, mobile, width, height)
    local margin = 14
    local left = mobile and 262 or margin
    local room = vp.X - left - margin
    local top = vp.Y - height - margin
    if mobile and room < 185 then
      -- 竖屏保留左上小地图的 122 px 宽度。
      left, room = 150, vp.X - 150 - margin
      top = math.min(100, top)
    end
    width = math.max(1, math.min(width, room))
    return math.max(left, (vp.X - width) / 2), math.max(0, top), width
  end

  local PAIRS = { { TK.car, TK.arm }, { SH.car, SH.arm } }
  for _, pr in ipairs(PAIRS) do
    pr[3], pr[4] = Instance.new("UIScale"), Instance.new("UIScale")
    pr[3].Parent, pr[4].Parent = pr[1], pr[2]
  end
  local lastVp, lastMob = nil, nil
  local compact, compassSide = false, false
  local function layoutPanels()
    local vp = cam.ViewportSize
    local mob = G.mobile == true or UIS.TouchEnabled
    if lastVp == vp and lastMob == mob then return end
    lastVp, lastMob = vp, mob
    compact = mob or vp.X < 760 or vp.Y < 480
    -- 计分栏左边：左上角是 Roblox 自己的菜单、聊天按钮（约 125 px 宽），罗盘从它们右边起，到计分栏左边留 12 px（1280 宽也放得下：约 160 px）
    local SIDE_X = 132
    local sideWidth = vp.X / 2 - 330 - SIDE_X - 12
    compassSide = sideWidth >= 150
    CW = compassSide and math.min(420, math.floor(sideWidth)) or math.clamp(math.floor(vp.X - 32), 1, 420)
    compGroup.Size = UD2(0, CW, 0, 51)
    compGroup.Position = compassSide and UD2(0, SIDE_X, 0, 16) or UD2(0.5, -CW / 2, 0, 118)

    local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.74, 1.25)
    for _, pr in ipairs(PAIRS) do
      pr[3].Scale, pr[4].Scale = s, s
      pr[1].Position, pr[2].Position = UD2(1, -334 * s, 1, -40 * s), UD2(1, -24 * s, 1, -40 * s)
    end

    local x, y, width = compactDock(vp, mob, 342, 72)
    local split = width >= 232 and 108 or 88
    MS.box.Position, MS.box.Size = UD2(0, x, 0, y), UD2(0, width, 0, 72)
    MS.speed.Size, MS.motion.Size = UD2(0, split - 15, 0, 28), UD2(0, split - 15, 0, 16)
    MS.speed.TextSize = width >= 232 and 20 or 16
    MS.split.Position = UD2(0, split, 0, 8)
    MS.selection.Position, MS.selection.Size = UD2(0, split + 10, 0, 6), UD2(1, -split - 18, 0, 16)
    MS.count.Position, MS.count.Size = UD2(0, split + 10, 0, 24), UD2(1, -split - 74, 0, 16)
    MS.health.Position, MS.health.Size = UD2(0, split + 10, 0, 42), UD2(1, -split - 18, 0, 16)
    MS.track.Position, MS.track.Size = UD2(0, split + 10, 1, -10), UD2(1, -split - 18, 0, 2)

    local simpleSight = compact or vp.X < 900 or vp.Y < 520
    SG.scale.Visible, SG.comp.Visible, SG.marker.Visible = not simpleSight, not simpleSight, not simpleSight
    sightRingScale.Scale = simpleSight and 0.78 or 1
    if simpleSight then
      local sx, sy, sw = compactDock(vp, mob, 184, 43)
      if mob and vp.X >= 600 then sx = vp.X - sw - 14 end
      SG.info.Position, SG.info.Size = UD2(0, sx, 0, sy), UD2(0, sw, 0, 43)
    else
      SG.info.Position, SG.info.Size = UD2(0.5, 206, 0.5, -26), UD2(0, 184, 0, 43)
    end
  end

  local function stepSight(st)
    local d = st.d
    local vs = G.S and G.S.veh
    local wid = d.weapons[st.wi]
    local w = wid and VD.W[wid]
    local ammo = vs and vs.ammo and wid and vs.ammo[wid]
    local relK, ready, left = 1, true, 0
    if w then
      local l = (st.next[wid] or 0) - os.clock()
      local full = (ammo and ammo[1] == w.mag and l > w.rate) and (w.reload or w.rate) or w.rate
      relK, ready, left = 1 - math.clamp(l / math.max(full, 0.01), 0, 1), l <= 0, math.max(0, l)
    end
    -- 炮口烟：开炮后 0.06 秒涌上来，一秒多散掉
    local age = os.clock() - (st.fireT or -99)
    local hz = (not reducedMotion and age < 2.2) and math.clamp(age / 0.06, 0, 1) * 0.62 * math.exp(-math.max(0, age - 0.06) * 2.1) or 0
    SG.haze.BackgroundTransparency = 1 - hz
    if hz > 0 then
      local cc = G.sightCC
      local tint = (cc and cc.Enabled) and cc.TintColor or Color3.fromRGB(255, 255, 255)
      SG.haze.BackgroundColor3 = Color3.fromRGB(168, 156, 136):Lerp(tint, 0.55)
    end
    local lit = math.floor(relK * 32 + 0.001)
    for i, dd in ipairs(SG.dots) do
      dd.BackgroundColor3 = ready and OK or (i <= lit and AMBER or TXT)
      dd.BackgroundTransparency = ready and 0.25 or (i <= lit and 0.05 or 0.75)
    end
    SG.ammo.Text = wid and T("vw." .. wid) or ""
    SG.count.Text = wid and (ammo and string.format("%d/%d", ammo[1], ammo[2]) or "∞") or ""
    SG.state.Text = ready and T("vh.loaded") or string.format("%s  %.1f", T("vh.reload"), left)
    SG.state.TextColor3 = ready and OK or AMBER
    if not SG.scale.Visible then return end
    local dist = st.aimPt and (st.aimPt - cam.CFrame.Position).Magnitude / 2.8 or 0
    SG.ptr.Position = UD2(0, 46, 0, 220 - math.clamp(dist / 2000, 0, 1) * 220)
    -- 小罗盘：炮管朝向
    local h = hdgOf((st.yaw or 0) - math.rad(st.ty or 0))
    local first = math.floor((h - 150 / 3) / 5) * 5
    for i, tk in ipairs(SG.ticks) do
      local a = first + (i - 1) * 5
      local x = 150 + (a - h) * 3
      local aa = a % 360
      tk.t.Position = UD2(0, x, 0, 0)
      tk.t.Size = UD2(0, 1, 0, (aa % 15 == 0) and 7 or 4)
      tk.l.Position = UD2(0, x, 0, 8)
      tk.l.Text = (aa % 30 == 0) and (DIR[aa] or string.format("%03d", aa)) or ""
    end
  end

  RunService.RenderStepped:Connect(function()
    local covered = (G.boardShown and G.boardShown()) or (G.menuOpen and G.menuOpen())
      or (G.menuShown and G.menuShown()) or (G.coachPanel and G.coachPanel())
    local tank, ship = G.myVeh, G.sail
    local driving = not covered and tank ~= nil and tank == G.drive and tank.d ~= nil
    local sailing = not covered and ship ~= nil and ship == G.drive and ship.d ~= nil and ship.bino ~= true
    local inSight = driving and tank.sight == true
    local showTank = driving and not inSight
    gui.Enabled, sg.Enabled = showTank or sailing, inSight
    if not gui.Enabled then
      if fireCC.Brightness ~= 0 then fireCC.Brightness = 0 end
      hp0 = nil
    end
    if not gui.Enabled and not inSight then return end
    layoutPanels()
    if inSight then
      local ok, err = pcall(stepSight, tank)
      if not ok and G.showError then G.showError("瞄准镜：" .. tostring(err)) end
      return
    end
    compGroup.Visible = not compact and (compassSide or not (G.operationHudVisible and G.operationHudVisible()))
    TK.car.Visible, TK.arm.Visible = showTank and not compact, showTank and not compact
    SH.car.Visible, SH.arm.Visible = sailing and not compact, sailing and not compact
    MS.box.Visible = compact
    local ok, err = pcall(showTank and stepTank or stepShip, showTank and tank or ship)
    if not ok and G.showError then G.showError("驾驶界面：" .. tostring(err)) end
  end)
end

return VehHud
