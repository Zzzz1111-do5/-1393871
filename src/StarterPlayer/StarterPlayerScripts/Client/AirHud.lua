-- 全面大战场（客户端）——开飞机的界面（用户 11-19：「飞机操作界面也改成参考这个」，给了几张手机空战游戏的截图；
--   之后要求形状、光晕都照截图）。布局、形状、比例、光晕照截图做，图都是自己画的（HudIcons：每架飞机原模型拍的平涂侧影、六边形、弹的图标、
--   机头的全息标记……），配色跟开坦克的界面一套（绿色全息）：
--   · 右上：机型名（白）、这架飞机平涂的绿色侧影（挨打到一半变黄、三成以下变红）、血量「当前（绿）/ 满（白）」
--   · 准星两边：左「高度」右「速度」，字下面一道带一个台阶的细折线、数在折线下面，都带一圈淡淡的光晕；
--     再下面一行小字：油量和还能飞多久 / 油门（加力、自动油门）、爬升率 / 起落架
--   · 准星上方：选中的弹的名字（实心的绿色小牌子）、下面写是什么弹；准星右边剩几发，左边锁定的目标多远（千米）
--   · 机头的全息标记（用户：像全息投屏一样、机头指哪它在哪）：只描边的小飞机（直升机是小直升机），机头往前一根线、线头一个亮点；
--     不是贴在屏幕上的图——是机头前方 300 格一块斜放的面（跟着机身俯仰、滚转），从后面看过去有透视；打中东西时放大一下、变红
--   · 锁定（用户：锁定过程是一个菱形，线条顺时针画出菱形就代表锁定完成；锁定后出现四个直角的边框，菱形开始逆时针转；
--     脱离导弹发射角度菱形变黄）：目标身上一个菱形，锁定进度多少就顺时针画多少；锁上后四个直角框住目标（往里一收）、菱形一直逆时针转；
--     目标出了导弹的离轴角（Fly 里锁还留着、这时不能发射）菱形变黄
--   · 右下：六边形武器键（按键号、弹的图标、剩几发）：没选中的是灰色的金属片，选中的发绿光；最后一个是热诱弹（X）
--   · 热成像（用户：不用光电吊舱也可以开红外视角）：开飞机时 N 在 夜视 → 热成像 → 关 之间切；白热（车、船、飞机、小兵发白），
--     整个画面灰、对比高，一层横向扫描线、雪花噪点、四边压暗；进光电吊舱时先让开（吊舱有自己的画面），下飞机关掉
--   · 左上的圆形雷达（白色细圈、灰色视野扇形和中线、正中间白色小飞机）、雷达下面的「被发现!」、敌人头顶带血条的名牌：
--     TankHud.lua 的飞机模式（G.tankHudExtra(st, k, "air")）
--   Fly.lua 每帧调 G.airHudStep(st, 数据)；无人机（战术平板）、光电吊舱画面不用这一套（Fly.lua 原来的）
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local AirHud = {}

function AirHud.init(G)
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local HOLO, TXT, MUTE, INK = RGB(118, 240, 140), RGB(238, 243, 245), RGB(156, 176, 160), RGB(6, 9, 12)   -- 全息绿（用户 11-21：蓝色全部改成绿色，原来青色 110, 226, 240）
  local YEL, BAD = RGB(255, 204, 58), RGB(255, 64, 52)
  local METAL, METAL_EDGE, METAL_ICON = RGB(138, 146, 152), RGB(200, 206, 210), RGB(226, 230, 232)
  local BOLD, MONO = Enum.Font.GothamBold, Enum.Font.RobotoMono
  local WHITE = Color3.new(1, 1, 1)
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local gui = Instance.new("ScreenGui")
  gui.Name = "AirHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5   -- 跟 Fly 的平显一层（灰视、红视那层盖在上面）
  gui.Enabled = false
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
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 13, color or HOLO, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.6, RGB(0, 22, 8)
    l.Parent = parent
    return l
  end
  local function img(parent, name, size, pos, anchor, color, tr)
    local l = Instance.new("ImageLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.ImageColor3, l.ImageTransparency = color or WHITE, tr or 0
    l.Parent = parent
    return l
  end
  local function art(lbl, name) return G.hudIconOn ~= nil and G.hudIconOn(lbl, name) == true end
  local function setIcon(lbl, key)   -- 换图（同一张不重复解）
    if lbl:GetAttribute("Art") == key then return lbl:GetAttribute("ArtOk") == true end
    local ok = art(lbl, key)
    lbl:SetAttribute("Art", key)
    lbl:SetAttribute("ArtOk", ok)
    return ok
  end
  local function stroke(f, color, th, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = color, th or 1, tr or 0
    s.Parent = f
    return s
  end
  local function round(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0.5, 0)
    c.Parent = f
    return f
  end
  -- 光晕：字 / 线外面一圈比本身粗、很淡的同色描边（截图上绿色的字和线都微微发光）
  local function glow(o, color, th, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = color or HOLO, th or 2.2, tr or 0.74
    s.LineJoinMode = Enum.LineJoinMode.Round
    s.Parent = o
    return s
  end
  local function hex(c) return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local function hpColor(k) return (k > 0.6) and HOLO or ((k > 0.3) and YEL or BAD) end

  local A = {}
  G.airHud = A   -- 测试用

  ---------------------------------------------------------------- 右上：机型名、平涂的侧影、血量
  A.card = frame(gui, UDim2.fromOffset(230, 104), mobile and UD2(1, -14, 0, 56) or UD2(1, -26, 0, 20), INK, 1, V2(1, 0))
  A.card.Name = "AirCard"
  A.name = label(A.card, "", UD2(1, 0, 0, 16), UD2(0, 0, 0, 0), 13, TXT, BOLD)
  A.name.Name = "AirName"
  A.icon = img(A.card, "AirIcon", UDim2.fromOffset(156, 44), UD2(0.5, 0, 0, 21), V2(0.5, 0), HOLO)
  A.icon.Visible = false
  A.iconFall = frame(A.card, UDim2.fromOffset(120, 3), UD2(0.5, 0, 0, 42), HOLO, 0.2, V2(0.5, 0.5))   -- 用不了 EditableImage：一道横线
  A.hp = label(A.card, "", UD2(1, 0, 0, 16), UD2(0, 0, 0, 74), 13, TXT, BOLD)
  A.hp.Name = "AirHp"
  A.hp.RichText = true
  glow(A.hp, HOLO, 2, 0.82)
  A.pass = label(A.card, "", UD2(1, 0, 0, 12), UD2(0, 0, 0, 90), 10, MUTE, BOLD)
  A.iconId = nil

  ---------------------------------------------------------------- 准星两边：高度、速度
  local root = frame(gui, UD2(1, 0, 1, 0), nil, INK, 1)
  root.Name = "AirCenter"
  local function seg(parent, x0, y0, x1, y1, th)   -- 一段细线：按中点摆、转到两点的方向（GUI 绕自己的中心转）
    local dx, dy = x1 - x0, y1 - y0
    local f = frame(parent, UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, th or 1.5), UD2(0, (x0 + x1) / 2, 0, (y0 + y1) / 2), HOLO, 0.05, V2(0.5, 0.5))
    f.Rotation = math.deg(math.atan2(dy, dx))
    glow(f, HOLO, 2, 0.76)
    return f
  end
  -- 折线：高的一段在字下面、数在它下面，往外一个斜台阶接低的一段（左边那个台阶在左、右边那个在右）
  local function bracket(xOff, cap, name, stepLeft)
    local b = frame(root, UDim2.fromOffset(96, 66), UD2(0.5, xOff, 0.5, -64), INK, 1, V2(0.5, 0))
    b.Name = name
    local HY, LY = 17, 24
    local hx0, hx1 = (stepLeft and 35 or 3), (stepLeft and 93 or 61)
    -- 一整张发光的折线（HudIcons 的 brkAlt / brkSpd：细芯 + 柔光，一笔画的）；用不了 EditableImage 时三段细线拼
    local ln = img(b, "Line", UDim2.fromOffset(96, 31), UD2(0, 0, 0, 6), nil, HOLO, 0)
    if not setIcon(ln, stepLeft and "brkAlt" or "brkSpd") then
      ln:Destroy()
      if stepLeft then   -- 高度（准星左边）：低 → 台阶往上 → 高
        seg(b, 3, LY, 28, LY)
        seg(b, 28, LY, 35, HY)
        seg(b, 35, HY, 93, HY)
      else               -- 速度（准星右边）：高 → 台阶往下 → 低
        seg(b, 3, HY, 61, HY)
        seg(b, 61, HY, 68, LY)
        seg(b, 68, LY, 93, LY)
      end
    end
    local cx = (hx0 + hx1) / 2
    local c = label(b, cap, UDim2.fromOffset(62, 13), UD2(0, cx, 0, 2), 11, HOLO, BOLD, V2(0.5, 0))
    c.Name = "Cap"
    glow(c)
    local v = label(b, "", UDim2.fromOffset(70, 18), UD2(0, cx, 0, 20), 16, HOLO, BOLD, V2(0.5, 0))
    v.Name = "Value"
    glow(v)
    local sub = label(b, "", UDim2.fromOffset(136, 12), UD2(0.5, 0, 0, 42), 10, MUTE, MONO, V2(0.5, 0))
    sub.Name = "Sub"
    local sub2 = label(b, "", UDim2.fromOffset(136, 12), UD2(0.5, 0, 0, 54), 10, MUTE, MONO, V2(0.5, 0))
    sub2.Name = "Sub2"
    return { f = b, cap = c, v = v, sub = sub, sub2 = sub2 }
  end
  A.alt = bracket(-180, T("air.cap.alt"), "AltBracket", true)
  A.spd = bracket(180, T("air.cap.spd"), "SpdBracket", false)

  -- 准星上方：选中的弹（实心的绿色小牌子、白字，下面一行写是什么弹）；准星右边剩几发，左边锁定目标多远
  A.wTag = frame(root, UDim2.fromOffset(84, 18), UD2(0.5, 0, 0.5, -134), HOLO, 0.5, V2(0.5, 0.5))   -- 平飞时机头标记在准星上方：再往上让开
  A.wTag.Name = "WeaponTag"
  round(A.wTag, UDim.new(0, 2))
  glow(A.wTag, HOLO, 2.4, 0.72)
  A.wName = label(A.wTag, "", UD2(1, -6, 1, 0), UD2(0.5, 0, 0.5, 0), 12, WHITE, BOLD, V2(0.5, 0.5))
  A.wName.Name = "WeaponName"
  A.wKind = label(root, "", UDim2.fromOffset(120, 12), UD2(0.5, 0, 0.5, -122), 10, HOLO, BOLD, V2(0.5, 0))
  A.wKind.Name = "WeaponKind"
  glow(A.wKind)
  A.cnt = label(root, "", UDim2.fromOffset(60, 16), UD2(0.5, 150, 0.5, 34), 14, TXT, BOLD, V2(0, 0.5), Enum.TextXAlignment.Left)
  A.cnt.Name = "StoreCount"
  A.cntIcon = img(root, "StoreIcon", UDim2.fromOffset(18, 18), UD2(0.5, 138, 0.5, 34), V2(0.5, 0.5), TXT)
  A.cntIcon.Visible = false
  A.rng = label(root, "", UDim2.fromOffset(110, 16), UD2(0.5, -150, 0.5, 34), 13, HOLO, BOLD, V2(1, 0.5), Enum.TextXAlignment.Right)
  A.rng.Name = "LockRange"
  glow(A.rng)

  ---------------------------------------------------------------- 机头的全息标记：机头前方一块斜放的面（跟着机身转），上面是只描边的小飞机
  -- 用户 11-19：要像全息瞄准镜的准心——细、亮、带柔光，跟着机头走（之前那版太大太粗）：两张图叠着（近白的细芯 + 绿色光晕），光晕微微闪
  -- 用户 11-21：全息的那块改小一点——整张图 90 → 58 像素高（锁定的菱形 / 直角框也一起缩了三成）
  local HOLO_D, HOLO_TILT, HOLO_PX = 300, math.rad(-55), 58   -- 离机头多远（格）、往后仰多少（面朝后上方，从后面看有透视）、整张图在屏幕上多高（像素）
  local CORE = RGB(232, 255, 236)
  local holoPart = Instance.new("Part")
  holoPart.Name = "NoseHolo"
  holoPart.Anchored, holoPart.CanCollide, holoPart.CanQuery, holoPart.CanTouch, holoPart.CastShadow = true, false, false, false, false
  holoPart.Transparency = 1
  holoPart.Size = V3(4, 6, 0.05)
  holoPart.Parent = cam
  local hsg = Instance.new("SurfaceGui")
  hsg.Name = "NoseHoloGui"
  hsg.Face = Enum.NormalId.Back   -- 面朝后（镜头在飞机后面）：从后面看图不反
  pcall(function()
    hsg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    hsg.CanvasSize = Vector2.new(128, 192)
  end)
  hsg.LightInfluence = 0
  hsg.AlwaysOnTop = true
  pcall(function() hsg.Brightness = 2 end)   -- 测试用的模拟器里没有这个属性
  hsg.Enabled = false
  hsg.Parent = holoPart
  A.holoGlow = img(hsg, "NoseHoloGlow", UD2(1, 0, 1, 0), nil, nil, HOLO, 0.1)
  A.holo = img(hsg, "NoseHoloArt", UD2(1, 0, 1, 0), nil, nil, CORE, 0)
  A.holoPart, A.holoGui = holoPart, hsg
  A.boreFall = label(gui, "+", UDim2.fromOffset(40, 40), UD2(0.5, 0, 0.5, 0), 34, HOLO, Enum.Font.Code, V2(0.5, 0.5))   -- 用不了 EditableImage
  A.boreFall.Name = "BoreMark"
  A.boreFall.Visible = false

  -- 准星（鼠标想去的方向）：一个发光的细圈（HudIcons 的 aimRing），Fly 原来那个「◯」字收起来
  A.aim = img(gui, "AimRing", UDim2.fromOffset(28, 28), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5), WHITE, 0.05)
  A.aimArt = setIcon(A.aim, "aimRing")
  A.aim.Visible = false

  ---------------------------------------------------------------- 锁定：菱形（顺时针画出来）、锁上后四个直角、菱形逆时针转
  local LK, DS, CS = 40, 24, 18   -- 锁定框边长、菱形对角线、直角的图（用户 11-21 嫌大：原来 56 / 34 / 24）
  A.lock = frame(gui, UDim2.fromOffset(LK, LK), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  A.lock.Name = "LockMark"
  A.lock.Visible = false
  A.dia = frame(A.lock, UDim2.fromOffset(DS, DS), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  A.dia.Name = "Diamond"
  local DV = { { DS / 2, 0 }, { DS, DS / 2 }, { DS / 2, DS }, { 0, DS / 2 } }   -- 上 → 右 → 下 → 左：顺时针
  -- 四条边各一张发光的线（HudIcons 的 glowLine：细芯 + 柔光、两头圆）：锁定进度多少，这条边就「长」多长（像笔在画）；
  --   用不了 EditableImage 时是细的方块线
  A.diaSeg = {}
  A.lineArt = nil
  for i = 1, 4 do
    local f = img(A.dia, "Edge" .. i, UDim2.fromOffset(1, 8), UD2(), V2(0.5, 0.5), HOLO, 0)
    A.lineArt = (A.lineArt ~= false) and setIcon(f, "glowLine")
    A.diaSeg[i] = f
  end
  if not A.lineArt then
    for i, f in ipairs(A.diaSeg) do
      f:Destroy()
      local g = frame(A.dia, UDim2.fromOffset(1, 2), UD2(), HOLO, 0, V2(0.5, 0.5))
      g.Name = "Edge" .. i
      A.diaSeg[i] = g
    end
  end
  -- 四个直角：一张左上的 L（glowCorner），另外三个转 90° / 180° / 270°（方的图绕中心转，正好落到对角上）
  A.corners = {}
  for _, c in ipairs({ { 0, 0, 0 }, { 1, 0, 90 }, { 1, 1, 180 }, { 0, 1, 270 } }) do
    local f = img(A.lock, "Corner", UDim2.fromOffset(CS, CS), UD2(c[1], 0, c[2], 0), V2(c[1], c[2]), HOLO, 0)
    f.Rotation = c[3]
    if not setIcon(f, "glowCorner") then
      f:Destroy()
      for _, sz in ipairs({ { 9, 2 }, { 2, 9 } }) do
        local g = frame(A.lock, UDim2.fromOffset(sz[1], sz[2]), UD2(c[1], 0, c[2], 0), HOLO, 0, V2(c[1], c[2]))
        g.Name = "Corner"
        table.insert(A.corners, g)
      end
    else
      table.insert(A.corners, f)
    end
  end
  A.lockT0 = nil

  ---------------------------------------------------------------- 右下：六边形武器键
  local HEX_R = 28
  A.hexBar = frame(gui, UDim2.fromOffset(10, 90), UD2(1, -24, 1, -64), INK, 1, V2(1, 1))
  A.hexBar.Name = "AirWeapons"
  A.hexBar.Visible = not mobile   -- 手机：右下是开火、换弹那一排触屏键
  A.hex = {}
  local function hexBtn(i)
    local R = HEX_R
    local h = { box = frame(A.hexBar, UDim2.fromOffset(R * 2, R * 2 * 80 / 72), UD2(), INK, 1, V2(0.5, 0.5)) }
    h.box.Name = "Hex" .. i
    h.iFill = img(h.box, "HexFill", UD2(1, 0, 1, 0), nil, nil, METAL, 0.3)
    do   -- 金属片：左上亮、右下暗
      local g = Instance.new("UIGradient")
      g.Rotation = 60
      g.Color = ColorSequence.new(RGB(255, 255, 255), RGB(150, 150, 150))
      g.Parent = h.iFill
    end
    h.iGlow = img(h.box, "HexGlow", UD2(1, 0, 1, 0), nil, nil, HOLO, 0.1)
    h.iEdge = img(h.box, "HexEdge", UD2(1, 0, 1, 0), nil, nil, METAL_EDGE, 0)
    h.iIcon = img(h.box, "Icon", UDim2.fromOffset(32, 32), UD2(0.5, 0, 0.5, -3), V2(0.5, 0.5), METAL_ICON, 0)
    h.art = art(h.iFill, "hexFill") and art(h.iGlow, "hexGlow") and art(h.iEdge, "hexEdge")
    if not h.art then   -- 用不了 EditableImage：圆角方块 + 描边
      h.iFill.Visible, h.iGlow.Visible, h.iEdge.Visible, h.iIcon.Visible = false, false, false, false
      h.plate = round(frame(h.box, UDim2.fromOffset(R * 1.7, R * 1.7), UD2(0.5, 0, 0.5, 0), METAL, 0.4, V2(0.5, 0.5)), UDim.new(0, 8))
      h.plateStroke = stroke(h.plate, METAL_EDGE, 1.5, 0)
      h.short = label(h.box, "", UD2(1, -6, 0, 14), UD2(0.5, 0, 0.5, -4), 10, METAL_ICON, BOLD, V2(0.5, 0.5))
    end
    h.iFill.ZIndex, h.iGlow.ZIndex, h.iEdge.ZIndex, h.iIcon.ZIndex = 1, 2, 3, 4
    h.key = label(h.box, "", UDim2.fromOffset(14, 12), UD2(0.5, -R * 0.5, 0.5, -R * 0.62), 10, TXT, BOLD, V2(0.5, 0.5))
    h.key.Name = "Key"
    h.cnt = label(h.box, "", UDim2.fromOffset(R * 2, 12), UD2(0.5, 0, 0.5, R * 0.52), 10, TXT, BOLD, V2(0.5, 0.5))
    h.cnt.Name = "Count"
    h.key.ZIndex, h.cnt.ZIndex = 5, 5
    return h
  end
  local KIND_ICON = { gun = "mg", aam = "wAam", agm = "wAgm", rkt = "wRkt", bomb = "wBomb", flare = "wFlare" }
  local function layoutHex(n)   -- 一排，从右往左：热诱弹在最右边
    local step = HEX_R * 1.732 + 6
    A.hexBar.Size = UDim2.fromOffset(n * step + 8, HEX_R * 2.4)
    for i = 1, #A.hex do
      local h = A.hex[i]
      h.box.Visible = i <= n
      h.box.Position = UD2(0, (i - 0.5) * step + 4, 0.5, 0)
    end
  end

  ---------------------------------------------------------------- 热成像（白热）
  local irGui = Instance.new("ScreenGui")
  irGui.Name = "AirIr"
  irGui.ResetOnSpawn = false
  irGui.IgnoreGuiInset = true
  irGui.DisplayOrder = 2   -- 压在画面上、界面下面
  irGui.Enabled = false
  irGui.Parent = me:WaitForChild("PlayerGui")
  local irScan = img(irGui, "Scanlines", UD2(1, 0, 1, 0), nil, nil, Color3.new(0, 0, 0), 0.25)
  irScan.ScaleType = Enum.ScaleType.Tile
  irScan.TileSize = UDim2.fromOffset(4, 4)
  local irNoise = img(irGui, "Noise", UD2(1, 256, 1, 256), nil, nil, WHITE, 0.35)
  irNoise.ScaleType = Enum.ScaleType.Tile
  irNoise.TileSize = UDim2.fromOffset(128, 128)
  for _, e in ipairs({ { V2(0, 0), UD2(1, 0, 0.3, 0), 90 }, { V2(0, 1), UD2(1, 0, 0.3, 0), -90 },
    { V2(0, 0), UD2(0.22, 0, 1, 0), 0 }, { V2(1, 0), UD2(0.22, 0, 1, 0), 180 } }) do   -- 四边压暗
    local f = frame(irGui, e[2], UD2(e[1].X, 0, e[1].Y, 0), Color3.new(0, 0, 0), 0.35, e[1])
    local g = Instance.new("UIGradient")
    g.Rotation = e[3]
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = f
  end
  local irCC = Instance.new("ColorCorrectionEffect")
  irCC.Name = "AirIrCC"
  irCC.Enabled = false
  irCC.Saturation, irCC.Contrast, irCC.Brightness, irCC.TintColor = -1, 0.42, -0.12, RGB(236, 238, 238)
  irCC.Parent = Lighting
  local irHl = Instance.new("Highlight")   -- 车、船、飞机、小兵（View.lua 画的）发白
  irHl.Name = "AirIrHeat"
  irHl.Enabled = false
  irHl.FillColor, irHl.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
  irHl.FillTransparency, irHl.OutlineTransparency = 0.12, 0.65
  irHl.DepthMode = Enum.HighlightDepthMode.Occluded
  irHl.Parent = cam
  local irWant, irShown, irArt, irNoiseT = false, false, nil, 0
  local function irApply(on)
    if on == irShown then return end
    irShown = on
    if on and irArt == nil then irArt = setIcon(irScan, "scanTex") and setIcon(irNoise, "noiseTex") end
    irGui.Enabled = on
    irScan.Visible, irNoise.Visible = irArt == true, irArt == true
    irCC.Enabled = on
    irHl.Adornee = G.viewFolder
    irHl.Enabled = on and G.viewFolder ~= nil
    if on then
      G.nvLight = true   -- 夜里也要看得见地面：跟夜视一样让昼夜（DayNight.lua）增亮
    elseif not (G.nvgOn and G.nvgOn()) then
      G.nvLight = false
    end
  end
  -- 开 / 关（Night.lua：开飞机时 N 在 夜视 → 热成像 → 关 之间切）；不带参数：现在开着没有
  function G.airThermal(v)
    if v == nil then return irWant end
    irWant = v == true
    if not irWant then irApply(false) end
    if G.toast and irWant then G.toast(T("air.irOn"), "info") end
    return irWant
  end
  G.airThermalShown = function() return irShown end   -- 测试用

  ---------------------------------------------------------------- 每帧
  local lastT = -9
  -- info：{ d, pilot, hp, mx, kmh, agl, vs, thr（文字）, fuel（文字）, fuelCol, gear（文字或 nil）, wid, w, cnt, wl（{ { key, wid, w, n, sel } … }）,
  --   cf（机身 CFrame）, hk（命中放大 0～1）, aim（准星在屏幕上的位置或 nil）, lockDist（格或 nil）, lock（{ p = 屏幕位置, on, k = 进度, locked, inCone }） }
  function G.airHudStep(st, info)
    gui.Enabled = true
    lastT = os.clock()
    local d = info.d
    -- 热成像（光电吊舱、无人机的画面里 Fly 不调这里：先让开）
    irApply(irWant)
    if irShown and lastT - irNoiseT > 0.05 then   -- 雪花一闪一闪
      irNoiseT = lastT
      irNoise.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
    end
    -- 右上
    A.name.Text = T("veh." .. d.id)
    local k = math.clamp(info.hp / math.max(info.mx, 1), 0, 1)
    local col = hpColor(k)
    A.hp.Text = string.format('<font color="#%s">%d</font>/%d', hex(col), math.max(0, math.floor(info.hp + 0.5)), math.floor(info.mx + 0.5))
    if A.iconId ~= d.id then
      A.iconId = d.id
      local ok = art(A.icon, "air_" .. d.id)
      local ic = ok and G.hudIcon and G.hudIcon("air_" .. d.id)
      if ic then   -- 按图的长宽比缩进 156 × 52 的框（扁的飞机满宽、高的直升机满高）
        local kk = math.min(156 / ic.w, 52 / ic.h)
        A.icon.Size = UDim2.fromOffset(ic.w * kk, ic.h * kk)
      end
      A.icon.Visible = ok
      A.iconFall.Visible = not ok
    end
    A.icon.ImageColor3 = col
    A.iconFall.BackgroundColor3 = col
    A.pass.Text = info.pilot and "" or T("air.passenger")
    -- 下面这些只有开飞机的人看（坐后面的乘客只有右上那块、雷达、名牌）
    local pilot = info.pilot
    root.Visible = pilot
    A.hexBar.Visible = pilot and not mobile
    -- 高度、速度
    A.alt.v.Text = tostring(math.max(0, info.agl))
    A.spd.v.Text = tostring(info.kmh)
    A.alt.sub.Text = info.fuel or ""
    A.alt.sub.TextColor3 = info.fuelCol or MUTE
    A.alt.sub2.Text = info.vs or ""
    A.spd.sub.Text = info.thr or ""
    A.spd.sub2.Text = info.gear or ""
    A.spd.sub2.TextColor3 = YEL
    -- 选中的弹
    if info.wid then
      A.wTag.Visible, A.wKind.Visible = true, true
      A.wName.Text = T("aw." .. info.wid)
      A.wTag.Size = UDim2.fromOffset(math.max(64, #A.wName.Text * 6 + 18), 18)
      A.wKind.Text = T("air.k." .. ((info.w and info.w.kind) or "agm"))
      A.cnt.Text = tostring(info.cnt or 0)
      A.cnt.TextColor3 = ((info.cnt or 0) > 0) and TXT or BAD
      local ic = KIND_ICON[(info.w and info.w.kind) or "agm"] or "wAgm"
      A.cntIcon.Visible = setIcon(A.cntIcon, ic)
      A.cnt.Position = UD2(0.5, A.cntIcon.Visible and 150 or 138, 0.5, 34)
    else
      A.wTag.Visible, A.wKind.Visible = false, false
      A.cnt.Text, A.cntIcon.Visible = "", false
    end
    if info.lockDist then
      local m = info.lockDist / 2.8
      A.rng.Text = (m >= 1000) and T("vh.km", string.format("%.1f", m / 1000)) or T("vh.m", math.floor(m + 0.5))
      A.rng.Visible = true
    else
      A.rng.Visible = false
    end
    -- 机头的全息标记
    local hk = math.min(1, info.hk or 0)
    local hcol = HOLO:Lerp(RGB(255, 90, 70), hk * 0.8)
    local cf = info.cf
    local showHolo = false
    if pilot and cf then
      local pre = (d.kind == "heli") and "holoHeli" or "holoJet"
      local okArt = setIcon(A.holo, pre .. "Core") and setIcon(A.holoGlow, pre .. "Glow")
      local pos = cf.Position + cf.LookVector * HOLO_D
      local cp = cam.CFrame
      local rel = pos - cp.Position
      if okArt then
        local vh = math.max(cam.ViewportSize.Y, 1)
        local f = (vh / 2) / math.tan(math.rad(cam.FieldOfView / 2))
        local hgt = rel.Magnitude * HOLO_PX * (1 + 0.3 * hk) / f   -- 离镜头越远做得越大：屏幕上看着一样大
        holoPart.Size = V3(hgt * 128 / 192, hgt, 0.05)
        holoPart.CFrame = CFrame.new(pos) * (cf - cf.Position) * CFrame.Angles(HOLO_TILT, 0, 0)
        A.holoGlow.ImageColor3 = hcol
        A.holo.ImageColor3 = CORE:Lerp(RGB(255, 150, 130), hk * 0.7)
        A.holoGlow.ImageTransparency = 0.12 + 0.12 * math.noise(lastT * 6, 3.3)   -- 全息的光晕微微闪
        showHolo = rel:Dot(cp.LookVector) > 1
        A.boreFall.Visible = false
      else   -- 用不了 EditableImage：屏幕上一个十字
        local sp, on = cam:WorldToViewportPoint(pos)
        A.boreFall.Position = UDim2.fromOffset(sp.X, sp.Y)
        A.boreFall.Visible = on
        A.boreFall.TextColor3 = hcol
      end
    else
      A.boreFall.Visible = false
    end
    hsg.Enabled = showHolo
    A.aim.Visible = pilot and A.aimArt and info.aim ~= nil
    if info.aim then A.aim.Position = info.aim end
    -- 锁定：菱形顺时针画出来；锁上后四个直角往里一收、菱形逆时针转；出了导弹的离轴角菱形变黄
    local lk = info.lock
    if pilot and lk and lk.on then
      A.lock.Visible = true
      A.lock.Position = lk.p
      local dcol = lk.inCone and HOLO or YEL
      local total = (lk.locked and 1 or math.clamp(lk.k or 0, 0, 1)) * 4
      for i = 1, 4 do
        local a, b = DV[i], DV[i % 4 + 1]
        local fr = math.clamp(total - (i - 1), 0, 1)
        local sgm = A.diaSeg[i]
        sgm.Visible = fr > 0.001
        local ex, ey = a[1] + (b[1] - a[1]) * fr, a[2] + (b[2] - a[2]) * fr
        local len = math.sqrt((ex - a[1]) ^ 2 + (ey - a[2]) ^ 2)
        if A.lineArt then   -- 图里线占中间 56 / 64，两头留了光晕的空：按这个放大
          sgm.Size = UDim2.fromOffset(len / 0.875 + 0.5, 8)
          sgm.ImageColor3 = dcol
        else
          sgm.Size = UDim2.fromOffset(len + 1.5, 2)
          sgm.BackgroundColor3 = dcol
        end
        sgm.Position = UDim2.fromOffset((a[1] + ex) / 2, (a[2] + ey) / 2)
        sgm.Rotation = math.deg(math.atan2(b[2] - a[2], b[1] - a[1]))
      end
      local now = os.clock()
      if lk.locked then
        A.lockT0 = A.lockT0 or now
        local e = math.clamp((now - A.lockT0) / 0.18, 0, 1)
        local sz = LK + 18 * (1 - e) * (1 - e)   -- 四个直角从外面往里一收
        A.lock.Size = UDim2.fromOffset(sz, sz)
        A.dia.Rotation = -((now - A.lockT0) * 150 % 360)   -- 逆时针
      else
        A.lockT0 = nil
        A.lock.Size = UDim2.fromOffset(LK, LK)
        A.dia.Rotation = 0
      end
      for _, c in ipairs(A.corners) do c.Visible = lk.locked == true end
      A.lock:SetAttribute("Progress", lk.locked and 1 or (lk.k or 0))
      A.lock:SetAttribute("Locked", lk.locked == true)
      A.lock:SetAttribute("InCone", lk.inCone == true)
    else
      A.lock.Visible = false
      A.lockT0 = nil
    end
    -- 六边形武器键：没选中的灰色金属片，选中的发绿光
    local items = info.wl or {}
    local n = #items
    while #A.hex < n do A.hex[#A.hex + 1] = hexBtn(#A.hex + 1) end
    if A.hexN ~= n then
      A.hexN = n
      layoutHex(n)
    end
    for i = 1, n do
      local it, h = items[i], A.hex[i]
      local sel = it.sel == true
      local empty = (it.n or 0) <= 0
      h.key.Text = it.key
      h.cnt.Text = tostring(it.n or 0)
      h.cnt.TextColor3 = empty and BAD or (sel and HOLO or TXT)
      h.box:SetAttribute("Wid", it.wid or "flare")
      h.box:SetAttribute("Sel", sel)
      if h.art then
        h.iFill.ImageColor3, h.iFill.ImageTransparency = sel and RGB(40, 150, 72) or METAL, sel and 0.35 or 0.3
        h.iGlow.Visible = sel and not empty
        h.iEdge.ImageColor3 = empty and RGB(150, 70, 64) or (sel and HOLO or METAL_EDGE)
        h.iEdge.ImageTransparency = sel and 0 or 0.15
        local kind = it.flare and "flare" or ((it.w and it.w.kind) or "agm")
        setIcon(h.iIcon, KIND_ICON[kind] or "wAgm")
        h.iIcon.ImageColor3 = empty and RGB(120, 100, 98) or (sel and WHITE or METAL_ICON)
      else
        h.plateStroke.Color = empty and RGB(150, 70, 64) or (sel and HOLO or METAL_EDGE)
        h.plate.BackgroundColor3 = sel and RGB(40, 150, 72) or METAL
        h.short.Text = it.flare and "X" or T("aw." .. it.wid)
        h.short.TextColor3 = sel and WHITE or METAL_ICON
      end
    end
  end

  -- 光电吊舱、无人机画面：这一套收起来（热成像也先让开，出来再开）
  function G.airHudOff()
    if gui.Enabled then gui.Enabled = false end
    hsg.Enabled = false
    irApply(false)
  end

  -- 下了飞机、被打下来（Fly 不调了）：收起来、热成像关掉
  G.frameConn("AirHud", function()
    if (gui.Enabled or hsg.Enabled or irShown) and os.clock() - lastT > 0.25 then
      gui.Enabled = false
      hsg.Enabled = false
      irApply(false)
    end
    if irWant and not G.fly then irWant = false end
  end)
end

return AirHud
