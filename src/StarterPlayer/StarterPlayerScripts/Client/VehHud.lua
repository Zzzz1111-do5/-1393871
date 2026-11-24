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
  local AMBER, OK, BAD, CYAN = RGB(255, 184, 72), RGB(110, 228, 150), RGB(240, 82, 66), RGB(132, 236, 152)
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
  -- 坦克的两块面板换成绿色全息（用户 11-19 给的截图那样）：边框、角上的亮线、选中那一行、油门条；血量写「当前 / 满」
  for _, pnl in ipairs({ TK.car, TK.arm }) do
    pnl.BackgroundTransparency = 0.32
    for _, c in ipairs(pnl:GetChildren()) do
      if c:IsA("UIStroke") then c.Color, c.Transparency = CYAN, 0.5
      elseif c:IsA("Frame") and c.BackgroundColor3 == TXT and (c.Size.Y.Offset == 2 or c.Size.X.Offset == 2) then c.BackgroundColor3 = CYAN end
    end
  end
  for _, r in ipairs(TK.rows) do r.bar.BackgroundColor3 = CYAN end
  TK.thr.BackgroundColor3 = CYAN
  TK.hp.pct.Size = UD2(0, 110, 0, 14)

  ---------------------------------------------------------------- 坦克（电脑）：MWT 那套（用户 11-19 又发了一遍截图：「确保我开坦克是这个驾驶 ui」）
  --   右下：车名、绿色的侧面剪影（挨打闪红、血少变黄 / 红）、血量「当前/满」（当前绿色）；最右下：每种武器一个六边形按钮
  --   （弹种缩写 + 炮弹图标，选中的绿色发光）；正下方偏右：烟幕弹的绿色全息图标（X、剩几发）；
  --   准星（下面 placeTank）：镜头准心一个小圈里「+」、左右两道短刻度；准心左边弹药数、下面「已就绪 / 装填」，右边测距；
  --   炮现在指的地方一个「∧」（颜色 = 打不打得穿）。电脑上开坦克时原来右下两块面板、顶上的罗盘收起（触屏照旧用紧凑读数面板）
  local MW = {}
  local HOLO = RGB(118, 240, 140)
  MW.root = frame(hud, UD2(1, 0, 1, 0), nil, INK, 1)
  MW.root.Name = "MWT"
  MW.root.Visible = false
  -- 右下一块（自己一个 UIScale，贴着右下角缩放）
  MW.br = frame(MW.root, UD2(0, 460, 0, 124), UD2(1, -18, 1, -14), INK, 1, V2(1, 1))
  MW.br.Name = "MwtVehicle"
  MW.brScale = Instance.new("UIScale")
  MW.brScale.Parent = MW.br
  -- 六边形（尖朝上）：外接圆半径 R——三块转 0 / 60 / 120° 的长方形拼成实心的底（放在 CanvasGroup 里统一调透明，叠的地方不发黑），六条边描边
  local function hexagon(parent, cx, cy, R)
    local o = {}
    o.box = frame(parent, UD2(0, R * 2, 0, R * 2), UD2(0, cx, 0, cy), INK, 1, V2(0.5, 0.5))
    local cg = Instance.new("CanvasGroup")
    cg.Size, cg.BackgroundTransparency = UD2(1, 0, 1, 0), 1
    cg.Parent = o.box
    o.fillGroup = cg
    o.fills = {}
    for i, a in ipairs({ 0, 60, 120 }) do
      local f = frame(cg, UD2(0, R * 1.732, 0, R), UD2(0.5, 0, 0.5, 0), INK, 0, V2(0.5, 0.5))
      f.Rotation = a
      o.fills[i] = f
    end
    o.edges = {}
    for k = 0, 5 do
      local a0, a1 = math.rad(90 + k * 60), math.rad(150 + k * 60)
      local x0, y0, x1, y1 = math.cos(a0) * R, -math.sin(a0) * R, math.cos(a1) * R, -math.sin(a1) * R
      local e = frame(o.box, UD2(0, R + 1, 0, 2), UD2(0.5, (x0 + x1) / 2, 0.5, (y0 + y1) / 2), TXT, 0, V2(0.5, 0.5))
      e.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
      o.edges[k + 1] = e
    end
    return o
  end
  -- 炮弹图标：斜着的弹体 + 弹头
  local function shellIcon(parent, cx, cy, len)
    local o = {}
    o.body = roundf(frame(parent, UD2(0, 6, 0, len), UD2(0, cx, 0, cy), TXT, 0, V2(0.5, 0.5)), UD(0, 2))
    o.body.Rotation = 40
    local rad = math.rad(40)
    o.tip = roundf(frame(parent, UD2(0, 6, 0, 8), UD2(0, cx + math.sin(rad) * (len / 2 + 3), 0, cy - math.cos(rad) * (len / 2 + 3)), TXT, 0, V2(0.5, 0.5)))
    o.tip.Rotation = 40
    return o
  end
  MW.hex = {}
  local HEX_R = 32
  for i = 1, 3 do
    local R = HEX_R
    local h = hexagon(MW.br, 460 - R, 124 - R - 2, R)   -- 横着摆在哪：stepTank 按这辆车有几种武器靠右排
    h.box.Name = "Ammo" .. i
    h.icon = shellIcon(h.box, R, R - 4, 22)
    h.key = label(h.box, "", UD2(0, 14, 0, 12), UD2(0.5, -R * 0.5, 0.5, -R * 0.62), 9, MUTE, BOLD)
    h.tag = label(h.box, "", UD2(0, R * 1.6, 0, 10), UD2(0.5, 4, 0.5, R * 0.5), 8, MUTE, BOLD, V2(0.5, 0.5))
    h.tag.Rotation = -20
    MW.hex[i] = h
  end
  -- 车名、剪影、血量（六边形左边）
  MW.veh = frame(MW.br, UD2(0, 190, 0, 112), UD2(0, 0, 0, 6), INK, 1)
  MW.veh.Name = "MwtHull"
  MW.name = label(MW.veh, "", UD2(1, 0, 0, 16), UD2(0, 0, 0, 2), 13, TXT, BOLD)
  MW.name.Name = "VehName"
  MW.name.TextStrokeTransparency = 0.6
  MW.sil = frame(MW.veh, UD2(0, 170, 0, 50), UD2(0.5, 0, 0, 24), INK, 1, V2(0.5, 0))
  MW.sil.Name = "Silhouette"
  MW.silParts = {}
  -- 侧面剪影（炮口朝右）：负重轮那一条、车体、首上斜面、炮塔、炮塔尾舱、车长塔、炮管、炮口
  for _, b in ipairs({ { 14, 31, 112, 14, 7, 0 }, { 6, 24, 124, 10, 2, 0 }, { 118, 21, 20, 9, 2, -24 }, { 44, 12, 52, 13, 3, 0 },
    { 34, 14, 14, 9, 2, 0 }, { 54, 6, 12, 7, 2, 0 }, { 94, 16, 70, 3, 1, 0 }, { 160, 14, 8, 6, 1, 0 } }) do
    local f = roundf(frame(MW.sil, UD2(0, b[3], 0, b[4]), UD2(0, b[1], 0, b[2]), HOLO, 0.08), UD(0, b[5]))
    f.Rotation = b[6]
    table.insert(MW.silParts, f)
  end
  for i = 0, 5 do   -- 负重轮：深色小圆点压在那一条上
    table.insert(MW.silParts, roundf(frame(MW.sil, UD2(0, 9, 0, 9), UD2(0, 26 + i * 18, 0, 33.5), INK, 0.35)))
  end
  MW.hp = label(MW.veh, "", UD2(1, 0, 0, 18), UD2(0, 0, 0, 80), 14, TXT, BOLD)
  MW.hp.Name = "HullHp"
  MW.hp.RichText = true
  MW.hp.TextStrokeTransparency = 0.6
  -- 正下方偏右：烟幕弹的全息图标
  MW.sm = frame(MW.root, UD2(0, 60, 0, 70), UD2(0.5, 104, 1, -16), INK, 1, V2(0.5, 1))   -- 正下方让给视角图，烟幕弹往右挪
  MW.sm.Visible = false   -- 用户 11-19：烟幕弹也不要显示了（X 键照样放）
  MW.sm.Name = "MwtSmoke"
  MW.smScale = Instance.new("UIScale")
  MW.smScale.Parent = MW.sm
  MW.smCan = roundf(frame(MW.sm, UD2(0, 24, 0, 34), UD2(0.5, 0, 0, 16), INK, 0.6, V2(0.5, 0)), UD(0, 5))
  MW.smCan.Rotation = -16
  MW.smStroke = stroke(MW.smCan, HOLO, 2, 0)
  MW.smCap = frame(MW.smCan, UD2(0, 10, 0, 7), UD2(0.5, 0, 0, -6), HOLO, 0, V2(0.5, 0))
  MW.smPin = frame(MW.smCan, UD2(0, 2, 0, 12), UD2(0.5, 5, 0, -14), HOLO, 0, V2(0.5, 0))
  MW.smWin = frame(MW.smCan, UD2(0, 10, 0, 12), UD2(0.5, 0, 0.5, 2), HOLO, 0.55, V2(0.5, 0.5))
  MW.smTxt = label(MW.sm, "", UD2(1, 20, 0, 12), UD2(0.5, 0, 1, -2), 10, HOLO, BOLD, V2(0.5, 1))
  MW.smTxt.Name = "SmokeLeft"
  MW.smTxt.TextStrokeTransparency = 0.6
  ---------------------------------------------------------------- 3A：抗锯齿的图（HudArt 解的 HudIcons，用户 11-19：「像素感太强，我要 3A 级别的 UI」）
  --   车：原模型正侧面拍的全息图（带柔光晕），按车型换；六边形的底 / 边 / 光晕、炮弹 / 机枪弹、烟幕弹都是 4 倍超采样画的图。
  --   用不了 EditableImage 时（游戏设置 → 安全里没打开 Mesh / Image API）退回上面方块拼的
  local function img(parent, name, size, pos, anchor, color, tr)
    local l = Instance.new("ImageLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.ImageColor3 = color or WHITE
    l.ImageTransparency = tr or 0
    l.Parent = parent
    return l
  end
  local function art(label, name) return G.hudIconOn ~= nil and G.hudIconOn(label, name) == true end
  MW.icon = img(MW.veh, "HoloIcon", UD2(0, 156, 0, 54), UD2(0.5, 0, 0, 24), V2(0.5, 0), HOLO)
  MW.icon.Visible = false
  for _, h in ipairs(MW.hex) do
    local R2 = HEX_R * 2
    h.iFill = img(h.box, "HexFill", UD2(0, R2, 0, R2 * 80 / 72), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5), INK, 0.35)
    h.iGlow = img(h.box, "HexGlow", UD2(0, R2, 0, R2 * 80 / 72), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5), HOLO, 0.15)
    h.iEdge = img(h.box, "HexEdge", UD2(0, R2, 0, R2 * 80 / 72), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5), MUTE, 0)
    h.iIcon = img(h.box, "AmmoIcon", UD2(0, 30, 0, 30), UD2(0.5, 0, 0.5, -6), V2(0.5, 0.5), MUTE, 0)
    h.art = art(h.iFill, "hexFill") and art(h.iGlow, "hexGlow") and art(h.iEdge, "hexEdge")
    h.iFill.ZIndex, h.iGlow.ZIndex, h.iEdge.ZIndex, h.iIcon.ZIndex = 1, 2, 3, 4
    h.key.ZIndex, h.tag.ZIndex = 5, 5
    h.fillGroup.Visible = not h.art
    for _, e in ipairs(h.edges) do e.Visible = not h.art end
    h.icon.body.Visible, h.icon.tip.Visible = not h.art, not h.art
    h.iFill.Visible, h.iGlow.Visible, h.iEdge.Visible, h.iIcon.Visible = h.art, h.art, h.art, h.art
  end
  -- 正下方中间：视角图（用户 11-19：屏幕下面中心放带着光晕的视角图，照 MWT）——俯视的车：车体按相对镜头的朝向转，
  --   炮塔、炮管按炮塔的朝向转，上方淡淡的两条线是镜头看的方向（视野）；绿色全息，车体外面两圈越来越淡的描边当光晕
  MW.view = frame(MW.root, UD2(0, 100, 0, 100), UD2(0.5, 0, 1, -8), INK, 1, V2(0.5, 1))
  MW.view.Name = "MwtView"
  MW.viewScale = Instance.new("UIScale")
  MW.viewScale.Parent = MW.view
  for _, a in ipairs({ -30, 30 }) do   -- 视野：从车中心往上张开 ±30°（GUI 绕自己的中心转：按中点摆）
    local L = 46
    local r = math.rad(a)
    local ln = frame(MW.view, UD2(0, 1.5, 0, L), UD2(0.5, math.sin(r) * L / 2, 0.5, 2 - math.cos(r) * L / 2), HOLO, 0.35, V2(0.5, 0.5))
    ln.Rotation = a
    grad(ln, 90, nseq(0, 1, 0.3, 0.75, 1, 0.3))   -- 越往外越淡
  end
  -- 视角图的车（用户 11-19：坦克图标有点难看 → 4 倍超采样画的全息图；坦克宽一点、不要履带、四个角直角；不要涂色，就车体边框、炮塔边框、炮管，
  --   剩下都镂空；用很薄的一个个长方形显示爆反，哪块没了就空一块）
  --   车体、炮塔各一个转的框（跟 HudIcons 的 topHull / topTurret 一样大：72 × 120 的图缩成 50 × 84），框里是全息图（用不了 EditableImage 时是
  --   方块拼的轮廓）和这辆车的爆反块（EraMeta：每块从上往下看的位置、朝向；叠在同一处的几层并成一条）；车体框绕车中心转、炮塔框绕座圈转
  local VK, VWD, VHT = 50 / 72, 50, 84
  MW.vHullBox = frame(MW.view, UD2(0, VWD, 0, VHT), UD2(0.5, 0, 0.5, 2), INK, 1, V2(0.5, 0.5))
  MW.vHullBox.Name = "ViewHull"
  MW.vTurBox = frame(MW.view, UD2(0, VWD, 0, VHT), UD2(0.5, 0, 0.5, 2), INK, 1, V2(0.5, 0.5))
  MW.vTurBox.Name = "ViewTurret"
  MW.vHullImg = img(MW.vHullBox, "ViewHullArt", UD2(1, 0, 1, 0), nil, nil, HOLO, 0)
  MW.vTurImg = img(MW.vTurBox, "ViewTurretArt", UD2(1, 0, 1, 0), nil, nil, HOLO, 0)
  MW.vArt = art(MW.vHullImg, "topHull") and art(MW.vTurImg, "topTurret")
  MW.vHullImg.Visible, MW.vTurImg.Visible = MW.vArt, MW.vArt
  MW.vFall = {}   -- 方块拼的（染色用）
  if not MW.vArt then
    local hb = frame(MW.vHullBox, UD2(0, 44 * VK, 0, 90 * VK), UD2(0.5, 0, 69 / 120, 0), HOLO, 1, V2(0.5, 0.5))   -- 直角，只有边框（镂空）
    local tc = roundf(frame(MW.vTurBox, UD2(0, 36 * VK, 0, 34 * VK), UD2(0.5, 0, 0.5, 2 * VK), HOLO, 1, V2(0.5, 0.5)), UD(0, 3))
    local gn = frame(MW.vTurBox, UD2(0, 3, 0, 44 * VK), UD2(0.5, 0, 0.5, -11 * VK), HOLO, 0.05, V2(0.5, 1))
    table.insert(MW.vFall, { f = hb, s = stroke(hb, HOLO, 1.6, 0) })
    table.insert(MW.vFall, { f = tc, s = stroke(tc, HOLO, 1.4, 0) })
    table.insert(MW.vFall, { f = gn })
  end
  -- 爆反块：这辆车 EraMeta 里的每块投到俯视图上（车体的按车体图摆：车宽、车长对上图里车体的半宽 22、半长 45；炮塔上的按座圈摆）
  local TMods = require(RS:WaitForChild("TankMods"))
  MW.era = {}
  local function buildEra(d)
    for _, e in ipairs(MW.era) do e.f:Destroy() end
    MW.era = {}
    local ok, L = pcall(function() return TMods.eraOf and TMods.eraOf(d.id) end)
    if not ok or not L or not L.b then return end
    -- 只画贴了的格（用户 11-22 晚：「坦克要能自己选位置贴爆反」；自己开的车 d 是按改装改过的那份，d.mods.ep 是一格格选的）
    local onCell = TMods.cellsOn and TMods.cellsOn(d.id, d.mods) or {}
    local sx, sz = 22 * VK / ((d.W or 10) / 2), 45 * VK / ((d.L or 20) / 2)   -- 车的格 → 框里的像素
    local tur = L.tur or { 0, 0, 0 }
    local cols, order = {}, {}
    for i, b in ipairs(L.b) do
      if not onCell[i] then b = nil end   -- 这一格没贴
      if b then
      local turret = b[1] == "t"
      local x, z = b[2], b[4]
      local nx, nz = b[5], b[7]
      local ux, uy, uz = b[8], b[9], b[10]
      local vx, vz = b[6] * uz - b[7] * uy, b[5] * uy - b[6] * ux   -- 高的方向 v = n × u（只要水平分量）
      vx, vz = -vx, -vz
      local nl = math.sqrt(nx * nx + nz * nz)
      local tx, tz
      if nl > 0.3 then tx, tz = -nz / nl, nx / nl
      else
        local ul = math.sqrt(ux * ux + uz * uz)
        tx, tz = (ul > 0.1) and ux / ul or 1, (ul > 0.1) and uz / ul or 0
      end
      local len = math.max(math.abs(ux * tx + uz * tz) * b[11], math.abs(vx * tx + vz * tz) * b[12])
      local oct = (nl > 0.3) and math.floor((math.deg(math.atan2(nz, nx)) + 382.5) / 45) % 8 or 9
      local along = math.floor((x * tx + z * tz) / 0.9 + 0.5)
      local key = (turret and "t" or "h") .. oct .. ":" .. along
      local c = cols[key]
      local depth = (nl > 0.3) and (x * nx + z * nz) / nl or 0
      if not c then
        c = { turret = turret, tx = tx, tz = tz, len = len, idx = {}, depth = -1e9 }
        cols[key] = c
        table.insert(order, c)
      end
      table.insert(c.idx, i)
      c.len = math.max(c.len, len)
      if depth > c.depth then   -- 最外面那一层的位置（贴着车体轮廓外边）
        c.depth = depth
        if turret then c.px, c.py = VWD / 2 + (x - tur[1]) * sx, 60 * VK + (z - tur[3]) * sz
        else c.px, c.py = VWD / 2 + x * sx, 69 * VK + z * sz end
        if nl > 0.3 then c.px, c.py = c.px + nx / nl * 1.4, c.py + nz / nl * 1.4 end
      end
      end
    end
    for _, c in ipairs(order) do
      local k = math.abs(c.tx) * sx + math.abs(c.tz) * sz
      local f = frame(c.turret and MW.vTurBox or MW.vHullBox, UD2(0, math.max(2, c.len * k - 1.2), 0, 1.6), UD2(0, c.px, 0, c.py), HOLO, 0, V2(0.5, 0.5))
      f.Rotation = math.deg(math.atan2(c.tz, c.tx))   -- 块和块之间留一道细缝
      f.Name = "Era"
      f.ZIndex = 3
      table.insert(MW.era, { f = f, idx = c.idx })
    end
  end
  G.viewEraBars = function() return MW.era end   -- 测试用
  MW.smImg = img(MW.sm, "SmokeIcon", UD2(0, 46, 0, 52), UD2(0.5, 0, 0, 2), V2(0.5, 0), HOLO, 0)
  MW.smArt = art(MW.smImg, "smoke")
  MW.smImg.Visible = MW.smArt
  MW.smCan.Visible = not MW.smArt
  -- 弹种缩写（六边形里）：主炮穿甲弹 APFSDS、机炮 HEI、机枪 MG、火炮 HE
  local function ammoTag(w)
    if not w then return "" end
    if w.kind == "shell" then return ((w.dmg or 0) >= 300) and "APFSDS" or "HEI" end
    if w.kind == "gun" then return "MG" end
    if w.kind == "arty" then return "HE" end
    return string.upper(string.sub(w.kind or "", 1, 3))
  end

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
  local PEN_OK, PEN_MAYBE, PEN_NO = RGB(176, 255, 84), RGB(255, 214, 72), RGB(255, 72, 60)   -- 能击穿：黄绿（界面整体改成绿以后，跟没瞄着车的绿分得开）

  -- 坦克（MWT）：四段弧（对角留缺口）围着炮指的点，装填时顺时针一段段亮起来；弧的颜色 = 打不打得穿（绿 / 黄 / 红，没瞄着车是白的）；
  --   左、右、下三道刻度，中心一个点；下面一行「可击穿 / 可能跳弹 / 跳弹 / 打不穿」，右边测距、左边装填秒数
  local mwtOn = false   -- 电脑上开坦克：MWT 那套（帧函数里按 compact 定）
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
  TR.rel.Visible = false   -- 用户 11-19（截图）：左边改成弹药数 + 状态（下面两行）
  -- 准星左边：弹药数（大）、状态（已就绪 / 装填 x.x 秒）；绿色全息（用户 11-19 给的手机坦克游戏截图那样）
  TR.ammo = label(TR.root, "", UD2(0, 90, 0, 22), UD2(0.5, -46, 0.5, -9), 20, TXT, MONO, V2(1, 0.5), RIGHT)
  TR.ammo.Name = "AmmoLeft"
  TR.ammo.TextStrokeTransparency = 0.55
  TR.state = label(TR.root, "", UD2(0, 110, 0, 16), UD2(0.5, -46, 0.5, 11), 13, CYAN, BOLD, V2(1, 0.5), RIGHT)
  TR.state.Name = "ReadyState"
  TR.state.TextStrokeTransparency = 0.6
  TR.chev = {   -- MWT：炮指的地方一个「∧」（两道斜线，顶点在这一点上方一点）
    frame(TR.root, UD2(0, 11, 0, 2), UD2(0.5, -3.6, 0.5, 2.2), TXT, 0, V2(0.5, 0.5)),
    frame(TR.root, UD2(0, 11, 0, 2), UD2(0.5, 3.6, 0.5, 2.2), TXT, 0, V2(0.5, 0.5)),
  }
  TR.chev[1].Rotation, TR.chev[2].Rotation = -52, 52
  do   -- 有抗锯齿的图就用图（转了角度的细方块边缘有锯齿）
    local l = Instance.new("ImageLabel")
    l.Name = "Chevron"
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = UD2(0, 24, 0, 16), UD2(0.5, 0, 0.5, 1), V2(0.5, 0.5)
    l.Parent = TR.root
    if G.hudIconOn and G.hudIconOn(l, "chevron") then TR.chevImg = l else l:Destroy() end
  end
  local lagArrow = label(ret, "▶", UD2(0, 16, 0, 16), UD2(0, 0, 0, 0), 13, AMBER, BOLD, V2(0.5, 0.5))
  lagArrow.Name = "TurretLag"
  -- MWT（电脑开坦克）：镜头准心小圈里一个「+」、左右两道短刻度；准心左边弹药数（前面一颗小炮弹）、下面「已就绪 / 装填」，右边测距；
  --   炮现在指的地方一个「∧」（TR.root 的位置，颜色 = 打不打得穿）。触屏照旧用上面那套
  local MR = {}
  MR.plus = {
    frame(camAim, UD2(0, 8, 0, 1.5), UD2(0.5, 0, 0.5, 0), WHITE, 0.15, V2(0.5, 0.5)),
    frame(camAim, UD2(0, 1.5, 0, 8), UD2(0.5, 0, 0.5, 0), WHITE, 0.15, V2(0.5, 0.5)),
  }
  MR.ticks = {
    frame(ret, UD2(0, 2, 0, 8), UD2(0.5, -54, 0.5, 0), WHITE, 0.3, V2(0.5, 0.5)),
    frame(ret, UD2(0, 2, 0, 8), UD2(0.5, 54, 0.5, 0), WHITE, 0.3, V2(0.5, 0.5)),
  }
  -- 字号照 MWT 截图（用户 11-19：文字精简一下、小一点）：弹药数、测距 14，已就绪 15
  MR.ammo = label(ret, "", UD2(0, 80, 0, 18), UD2(0.5, -70, 0.5, -12), 14, TXT, BOLD, V2(1, 0.5), RIGHT)
  MR.ammo.Name = "MwtAmmo"
  MR.ammo.TextStrokeTransparency = 0.55
  MR.bullet = roundf(frame(ret, UD2(0, 3, 0, 9), UD2(0.5, -110, 0.5, -12), TXT, 0.05, V2(0.5, 0.5)), UD(0, 2))   -- 弹药数前面的小炮弹（stepTank 按位数挪）
  MR.state = label(ret, "", UD2(0, 120, 0, 18), UD2(0.5, -70, 0.5, 7), 15, CYAN, BOLD, V2(1, 0.5), RIGHT)
  MR.state.Name = "MwtState"
  MR.state.TextStrokeTransparency = 0.55
  MR.rng = label(ret, "", UD2(0, 100, 0, 18), UD2(0.5, 76, 0.5, -12), 14, TXT, BOLD, V2(0, 0.5), LEFT)
  MR.rng.Name = "MwtRange"
  MR.rng.TextStrokeTransparency = 0.55
  do
    local l = Instance.new("ImageLabel")
    l.Name = "BulletIcon"
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = UD2(0, 5, 0, 12), MR.bullet.Position, V2(0.5, 0.5)
    l.ImageColor3 = TXT
    l.Parent = ret
    if G.hudIconOn and G.hudIconOn(l, "bullet") then
      MR.bullet:Destroy()
      MR.bullet = l
    else l:Destroy() end
  end
  MR.all = { MR.ticks[1], MR.ticks[2], MR.ammo, MR.bullet, MR.state, MR.rng }

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
  local function placeTank(p, o, relK, ready, left, lag, penC, penT, ammoTxt)
    SR.root.Visible, SR.lead.Visible, SR.card.Visible, SR.lock.Visible, SR.lockTxt.Visible = false, false, false, false, false
    for _, dd in ipairs(SR.leadDots) do dd.Visible = false end
    local sp, on = cam:WorldToViewportPoint(p)
    local vp = cam.ViewportSize
    TR.root.Visible = on
    local kick = reducedMotion and 0 or math.clamp(1 - (os.clock() - kickT) / 0.35, 0, 1)
    TR.scale.Scale = 1 + 0.4 * kick
    TR.root.Position = UD2(0, sp.X, 0, sp.Y)
    local col = penC or CYAN   -- 没瞄着车：绿色（全息的感觉）
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
    TR.rng.Text = T("vh.m", math.floor((p - o).Magnitude / 2.8 / 5 + 0.5) * 5)
    TR.rel.Text = ready and "" or string.format("%.1f", left)
    TR.ammo.Text = ammoTxt or ""
    TR.state.Text = ready and T("vh.rdy") or T("vh.loading", string.format("%.1f", left))
    TR.state.TextColor3 = ready and CYAN or AMBER
    -- MWT（电脑）：炮指的地方只留「∧」，数字挪到镜头准心两边
    local mw = mwtOn
    for _, sgx in ipairs(TR.segs) do sgx.Visible = not mw end
    for _, tk in ipairs(TR.ticks) do tk.Visible = not mw end
    TR.dot.Visible, TR.pen.Visible, TR.rng.Visible, TR.ammo.Visible, TR.state.Visible = not mw, not mw, not mw, not mw, not mw
    local chevCol = penC or (ready and WHITE or AMBER)
    for _, c in ipairs(TR.chev) do
      c.Visible = mw and TR.chevImg == nil
      c.BackgroundColor3 = chevCol
    end
    if TR.chevImg then
      TR.chevImg.Visible = mw
      TR.chevImg.ImageColor3 = chevCol
    end
    for _, x in ipairs(MR.all) do x.Visible = mw end
    for _, x in ipairs(MR.plus) do x.Visible = mw end
    if mw then
      MR.ammo.Text = ammoTxt or ""
      MR.bullet.Position = UD2(0.5, -70 - #(ammoTxt or "") * 8.5 - 7, 0.5, -12)
      MR.bullet.Visible = (ammoTxt or "") ~= ""
      MR.state.Text = ready and T("vh.rdy") or string.format("%.1fs", left)
      MR.state.TextColor3 = ready and CYAN or AMBER
      MR.rng.Text = TR.rng.Text
    end
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
    for _, x in ipairs(MR.all) do x.Visible = false end
    for _, x in ipairs(MR.plus) do x.Visible = false end
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
    TK.hp.pct.Text = string.format("%d / %d", math.floor(st.em:GetAttribute("Hp") or 0), math.floor(st.em:GetAttribute("MaxHp") or 0))
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
    local selAmmo = nil
    for i, r in ipairs(TK.rows) do
      local wid = d.weapons[i]
      if wid then
        local w = VD.W[wid]
        local ammo = vs and vs.ammo and vs.ammo[wid]
        setRow(r, tostring(i), T("vw." .. wid), ammo and string.format("%d / %d", ammo[1], ammo[2]) or "∞", i == st.wi, ammo and ammo[1] + ammo[2] == 0)
        if i == st.wi and w then
          selAmmo = ammo and tostring(ammo[1] + ammo[2]) or "∞"
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
    if mwtOn then
      -- MWT 右下：车名、剪影（挨打闪红、血少变色）、血量「当前/满」；六边形弹种按钮靠右排；烟幕弹图标
      MW.name.Text = string.match(TK.name.Text, "^(%S+)") or TK.name.Text   -- 只写型号（「ZTZ-96 主战坦克」→「ZTZ-96」，MWT 那样）
      -- 车的图标（全息图、视角图）、血量数字的颜色只看车况（用户 11-19：被打到状态一般改成黄色，状态很差改成红色）：
      --   六成以上绿色、三到六成黄色、三成以下红色（挨打那一下不再闪红：红色只表示车况很差）
      local silCol = (k > 0.6) and HOLO or ((k > 0.3) and RGB(255, 214, 64) or RGB(255, 64, 52))
      if MW.iconId ~= d.id then   -- 换了车：换全息图（这辆车拍过的侧面图）；没有就用方块拼的剪影
        MW.iconId = d.id
        local ok = art(MW.icon, "veh_" .. d.id)
        local ic = ok and G.hudIcon("veh_" .. d.id)
        if ic then MW.icon.Size = UD2(0, math.floor(ic.w * 0.62 + 0.5), 0, math.floor(ic.h * 0.62 + 0.5)) end
        MW.icon.Visible = ok
        MW.sil.Visible = not ok
        MW.hp.Position = UD2(0, 0, 0, ok and (24 + (ic and ic.h * 0.62 or 54) - 2) or 80)
      end
      MW.icon.ImageColor3 = silCol
      -- 视角图：车体框、炮塔框按相对镜头的朝向转（跟原来面板里的俯视轮廓一样算），颜色跟着车况；爆反哪块没了就空一块
      MW.vHullBox.Rotation, MW.vTurBox.Rotation = TK.hull.Rotation, TK.tur.Rotation
      MW.vTurBox.Visible = d.turret ~= nil
      MW.vHullImg.ImageColor3, MW.vTurImg.ImageColor3 = silCol, silCol
      for _, q in ipairs(MW.vFall) do
        if q.s then q.s.Color = silCol else q.f.BackgroundColor3 = silCol end   -- 边框染色；炮管是实心的细条
      end
      local eraKey = d.id .. ":" .. tostring(d.mods and d.mods.era or "")
      if MW.eraId ~= eraKey then
        MW.eraId = eraKey
        buildEra(d)
      end
      if #MW.era > 0 then
        local dead = {}
        for k2 in string.gmatch(st.em:GetAttribute("EraX") or "", "%d+") do dead[tonumber(k2)] = true end
        local ec = silCol:Lerp(WHITE, 0.3)
        for _, e in ipairs(MW.era) do
          local alive = 0
          for _, i2 in ipairs(e.idx) do if not dead[i2] then alive += 1 end end
          e.f.Visible = alive > 0
          e.f.BackgroundColor3 = ec
          e.f.BackgroundTransparency = (alive == #e.idx) and 0 or 0.55   -- 叠着的几层炸掉一部分：淡一点
        end
      end
      MW.viewScale.Scale = MW.brScale.Scale
      for i, f in ipairs(MW.silParts) do
        if i <= 8 then f.BackgroundColor3 = silCol end
      end
      local hp, mx = math.floor(st.em:GetAttribute("Hp") or 0), math.floor(st.em:GetAttribute("MaxHp") or 0)
      local hc = silCol
      MW.hp.Text = string.format('<font color="#%02X%02X%02X">%d</font>/%d', math.floor(hc.R * 255), math.floor(hc.G * 255), math.floor(hc.B * 255), hp, mx)
      local n = 0
      for i = 1, #MW.hex do if d.weapons[i] then n = i end end
      if MW.nHex ~= n then
        MW.nHex = n
        for i, h in ipairs(MW.hex) do
          h.box.Visible = i <= n
          h.box.Position = UD2(0, 460 - HEX_R - (n - i) * (HEX_R * 1.732 + 8), 0, 124 - HEX_R - 2)
        end
        local left0 = 460 - HEX_R - (n - 1) * (HEX_R * 1.732 + 8) - HEX_R
        MW.veh.Position = UD2(0, math.max(0, left0 - 200), 0, 6)
      end
      for i = 1, n do
        local h = MW.hex[i]
        local wid = d.weapons[i]
        local w = VD.W[wid]
        local ammo = vs and vs.ammo and vs.ammo[wid]
        local empty = ammo ~= nil and ammo[1] + ammo[2] == 0
        local sel = i == st.wi
        local edge = empty and BAD or (sel and HOLO or MUTE)
        for _, e in ipairs(h.edges) do
          e.BackgroundColor3 = edge
          e.BackgroundTransparency = sel and 0 or 0.35
        end
        for _, f in ipairs(h.fills) do f.BackgroundColor3 = sel and RGB(18, 64, 30) or INK end
        h.fillGroup.GroupTransparency = sel and 0.25 or 0.45
        h.icon.body.BackgroundColor3, h.icon.tip.BackgroundColor3 = sel and HOLO or MUTE, sel and WHITE or MUTE
        h.key.Text = tostring(i)
        h.key.TextColor3 = sel and TXT or MUTE
        h.tag.Text = ammoTag(w)
        h.tag.TextColor3 = sel and HOLO or MUTE
        if h.art then
          h.iFill.ImageColor3, h.iFill.ImageTransparency = sel and RGB(16, 58, 26) or INK, sel and 0.22 or 0.4
          h.iGlow.Visible = sel and not empty
          h.iEdge.ImageColor3, h.iEdge.ImageTransparency = edge, sel and 0 or 0.3
          local ic = (w and w.kind == "gun") and "mg" or "shell"
          if h.iconName ~= ic then h.iconName = ic art(h.iIcon, ic) end
          h.iIcon.ImageColor3 = sel and Color3.new(1, 1, 1):Lerp(HOLO, 0.35) or MUTE
        end
      end
      local sm = vs and vs.smoke or 0
      MW.smTxt.Text = string.format("X ×%d", sm)
      local dim = sm <= 0
      MW.smStroke.Transparency = dim and 0.65 or 0
      MW.smCap.BackgroundTransparency = dim and 0.65 or 0
      MW.smPin.BackgroundTransparency = dim and 0.65 or 0
      MW.smWin.BackgroundTransparency = dim and 0.85 or 0.55
      MW.smTxt.TextTransparency = dim and 0.5 or 0
      MW.smImg.ImageTransparency = dim and 0.62 or 0
    end
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
    placeTank(pt, gcf.Position, relK, ready, left, true, penC, penT, selAmmo)
    if G.tankHudExtra then G.tankHudExtra(st, k) end   -- 敌人头顶的名字和距离、「被发现」、爆反 / 主动防御的状态（TankHud.lua）
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
  -- 装填环：原来 32 颗 4 像素的小点（用户 11-19：像素感太强）——换成一道平滑的细圆环（圆角 + 描边，抗锯齿），
  --   装填中琥珀色、越装越亮，装好变绿（剩几秒写在右边的状态框里）
  SG.ringLine = roundf(frame(SG.ring, UD2(0, 172, 0, 172), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))
  SG.ringLine.Name = "ReloadRing"
  SG.ringStroke = stroke(SG.ringLine, TXT, 1.6, 0.6)
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
    MW.brScale.Scale, MW.smScale.Scale = s, s
    MW.br.Position = UD2(1, -18 * s, 1, -14 * s)
    MW.sm.Position = UD2(0.5, 70 * s, 1, -16 * s)

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
    SG.ringStroke.Color = ready and OK or AMBER
    SG.ringStroke.Transparency = ready and 0.3 or (0.8 - 0.5 * relK)
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

  G.frameConn("VehHud", function()
    local covered = (G.boardShown and G.boardShown()) or (G.menuOpen and G.menuOpen())
      or (G.menuShown and G.menuShown()) or (G.coachPanel and G.coachPanel())
    local tank, ship = G.myVeh, G.sail
    local driving = not covered and tank ~= nil and tank == G.drive and tank.d ~= nil
    local sailing = not covered and ship ~= nil and ship == G.drive and ship.d ~= nil and ship.bino ~= true
    local inSight = driving and tank.sight == true
    local showTank = driving and not inSight and not (G.interiorOn and G.interiorOn())   -- 坐在车里看（Interior.lua）：车里的屏幕就是仪表
    gui.Enabled, sg.Enabled = showTank or sailing, inSight and not G.interiorOptic
    if not gui.Enabled then
      if fireCC.Brightness ~= 0 then fireCC.Brightness = 0 end
      hp0 = nil
      mwtOn = false
      G.tankHudActive = false
    end
    if not gui.Enabled and not inSight then return end
    layoutPanels()
    if inSight then
      local ok, err = pcall(stepSight, tank)
      if not ok and G.showError then G.showError("瞄准镜：" .. tostring(err)) end
      return
    end
    mwtOn = showTank and not compact
    G.tankHudActive = mwtOn
    MW.root.Visible = mwtOn
    compGroup.Visible = not compact and not showTank and (compassSide or not (G.operationHudVisible and G.operationHudVisible()))
    TK.car.Visible, TK.arm.Visible = false, false   -- 电脑开坦克是 MWT 那套（MW），触屏是紧凑读数面板（MS）
    SH.car.Visible, SH.arm.Visible = sailing and not compact, sailing and not compact
    MS.box.Visible = compact
    local ok, err = pcall(showTank and stepTank or stepShip, showTank and tank or ship)
    if not ok and G.showError then G.showError("驾驶界面：" .. tostring(err)) end
  end)
end

return VehHud
