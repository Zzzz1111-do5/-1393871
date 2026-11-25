-- 全面大战场（客户端）——开飞机的界面（用户 11-19：「飞机操作界面也改成参考这个」，给了几张手机空战游戏的截图；
--   之后要求形状、光晕都照截图）。布局、形状、比例、光晕照截图做，图都是自己画的（HudIcons：每架飞机原模型拍的平涂侧影、六边形、弹的图标、
--   机头的全息标记……），配色跟开坦克的界面一套（绿色全息）：
--   · 右上：机型名（白）、这架飞机平涂的绿色侧影（挨打到一半变黄、三成以下变红）、血量「当前（绿）/ 满（白）」
--   · 准星两边：左「高度」右「速度」，字下面一道带一个台阶的细折线、数在折线下面，都带一圈淡淡的光晕；
--     再下面一行小字：油量和还能飞多久 / 油门（加力、自动油门）、爬升率 / 起落架
--   · 准星上方：选中的弹的名字（实心的绿色小牌子）、下面写是什么弹；准星右边剩几发，左边锁定的目标多远（千米）
--   · 机头的全息标记（用户：像全息投屏一样、机头指哪它在哪）：只描边的小飞机（直升机是小直升机），机头往前一根线、线头一个亮点；
--     不是贴在屏幕上的图——是机头前方 300 格一块斜放的面（跟着机身俯仰、滚转），从后面看过去有透视；打中东西时放大一下、变红
--   · 锁定（用户 11-23：「飞机驾驶锁定改成战雷的 UI」，给了战雷里歼-20 锁定米格-15 的截图）：目标上一个细的绿方框，
--     框上面写目标型号、右边写距离和接近速度；雷达弹 / 空地弹锁定中方框一闪一闪、锁上常亮；红外弹的导引头圈从机头滑到目标上，锁上了方框也出来；
--     机炮黏住目标时提前量那一点一个小圈、一根细线连到目标；目标出了导弹的离轴角（锁还在、不能发射）框和字变黄
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
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local HOLO, TXT, MUTE, INK = TH.C.HUD, TH.C.TEXT, TH.C.MUTE, TH.C.BG   -- 全息绿（用户 11-21：蓝色全部改成绿色，原来青色 110, 226, 240）
  local YEL, BAD = TH.C.WARN, TH.C.BAD
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
  -- 准星（用户 11-22：「准心很奇怪，为什么是个飞机图标」——飞机图标挪到光电吊舱画面下面当航向指示了，Fly.lua）：
  --   全息的一个圈 + 中心点 + 上下左右四道短刻度，外面一圈柔光；照旧投在机头前方 300 格（全息：跟着机头走、看着在远处）
  A.holo.Visible, A.holoGlow.Visible = false, false
  do
    local R0 = 30   -- 圈的半径（画布 128 × 192 里的像素）
    local ret = Instance.new("Frame")
    ret.Name = "Reticle"
    ret.BackgroundTransparency = 1
    ret.Size = UD2(1, 0, 1, 0)
    ret.Parent = hsg
    local function piece(w, h, x, y, round)
      local f = Instance.new("Frame")
      f.AnchorPoint = V2(0.5, 0.5)
      f.Size = UDim2.fromOffset(w, h)
      f.Position = UD2(0.5, x, 0.5, y)
      f.BorderSizePixel = 0
      f.BackgroundColor3 = CORE
      f.Parent = ret
      if round then
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = f
      end
      return f
    end
    local glow = piece(R0 * 2 + 10, R0 * 2 + 10, 0, 0, true)
    glow.BackgroundTransparency = 1
    local gs = Instance.new("UIStroke")
    gs.Thickness, gs.Color, gs.Transparency = 9, HOLO, 0.7
    gs.Parent = glow
    local ring = piece(R0 * 2, R0 * 2, 0, 0, true)
    ring.BackgroundTransparency = 1
    local rs = Instance.new("UIStroke")
    rs.Thickness, rs.Color, rs.Transparency = 3, CORE, 0
    rs.Parent = ring
    local ticks = {
      piece(4, 4 + 10, 0, -(R0 + 12)), piece(4, 4 + 10, 0, R0 + 12),
      piece(14, 4, -(R0 + 12), 0), piece(14, 4, R0 + 12, 0),
    }
    local dot = piece(7, 7, 0, 0, true)
    A.ret = { frame = ret, ring = rs, glow = gs, ticks = ticks, dot = dot }
  end
  A.holoPart, A.holoGui = holoPart, hsg
  A.boreFall = label(gui, "+", UDim2.fromOffset(40, 40), UD2(0.5, 0, 0.5, 0), 34, HOLO, Enum.Font.RobotoMono, V2(0.5, 0.5))   -- 用不了 EditableImage
  A.boreFall.Name = "BoreMark"
  A.boreFall.Visible = false

  -- 准星（鼠标想去的方向）：一个发光的细圈（HudIcons 的 aimRing），Fly 原来那个「◯」字收起来
  A.aim = img(gui, "AimRing", UDim2.fromOffset(28, 28), UD2(0.5, 0, 0.5, 0), V2(0.5, 0.5), WHITE, 0.05)
  A.aimArt = setIcon(A.aim, "aimRing")
  if not A.aimArt then   -- 用不了 EditableImage（游戏设置里没开 Mesh / Image API）：圆角框 + 描边画一个圈（机炮黏住目标时要看得见）
    A.aim.BackgroundTransparency = 1
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = A.aim
    local sk = Instance.new("UIStroke")
    sk.Thickness, sk.Color, sk.Transparency = 2, WHITE, 0.1
    sk.Parent = A.aim
  end
  A.aim.Visible = false
  A.aim.Size = UDim2.fromOffset(18, 18)   -- 战雷的提前量小圈
  -- 战雷式鼠标瞄准的小圈（Fly.lua 的 info.maim：鼠标想去的方向；飞机往这里追，机头的「+」跟过来）：白色细圈、中间一个点
  A.maim = round(frame(gui, UDim2.fromOffset(22, 22), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))
  A.maim.Name = "MouseAim"
  stroke(A.maim, WHITE, 1.4, 0.15)
  round(frame(A.maim, UDim2.fromOffset(3, 3), UD2(0.5, 0, 0.5, 0), WHITE, 0.15, V2(0.5, 0.5)))
  A.maim.Visible = false
  -- 战雷式机炮提前量（Fly.lua 的 info.lead：敌机的提前量点，炮弹飞过去的时间里它飞到哪、炮弹往下掉多少都算上）：琥珀色小圈 + 中心点，
  --   旁边写距离；机头的「+」压上去开炮就打得中（战雷的固定机炮顺着机头打，不再自动黏住目标）
  A.lead = round(frame(gui, UDim2.fromOffset(18, 18), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))
  A.lead.Name = "LeadMark"
  stroke(A.lead, Color3.fromRGB(255, 200, 70), 1.6, 0.05)
  round(frame(A.lead, UDim2.fromOffset(3, 3), UD2(0.5, 0, 0.5, 0), Color3.fromRGB(255, 200, 70), 0.05, V2(0.5, 0.5)))
  A.leadT = Instance.new("TextLabel")
  A.leadT.Name = "LeadRange"
  A.leadT.BackgroundTransparency = 1
  A.leadT.Size, A.leadT.Position, A.leadT.AnchorPoint = UDim2.fromOffset(80, 14), UD2(1, 4, 0.5, 0), V2(0, 0.5)
  A.leadT.Font, A.leadT.TextSize, A.leadT.TextXAlignment = Enum.Font.RobotoMono, 12, Enum.TextXAlignment.Left
  A.leadT.TextColor3, A.leadT.TextStrokeTransparency = Color3.fromRGB(255, 214, 110), 0.4
  A.leadT.Parent = A.lead
  A.lead.Visible = false
  A.leadLine = frame(gui, UDim2.fromOffset(10, 1.5), UD2(), WHITE, 0.1, V2(0.5, 0.5))
  A.leadLine.Name = "LeadLine"
  A.leadLine.Visible = false

  ---------------------------------------------------------------- 锁定（战雷式）：细的绿方框、框上型号、右边距离和接近速度；红外弹的导引头圈
  local WT = TH.C.HUD   -- 战雷平显的绿（比全息绿更亮、更纯）
  local LK = 40
  A.lock = frame(gui, UDim2.fromOffset(LK, LK), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  A.lock.Name = "LockMark"
  A.lock.Visible = false
  A.lockBox = stroke(A.lock, WT, 1.6, 0)   -- 方框就是这个框的描边
  local function wtLabel(parent, size, pos, anchor, align)
    local l = label(parent, "", size, pos, 13, WT, BOLD, anchor, align)
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.3, RGB(0, 0, 0)
    return l
  end
  A.lkName = wtLabel(A.lock, UDim2.fromOffset(170, 16), UD2(0.5, 0, 0, -4), V2(0.5, 1))
  A.lkName.Name = "TargetName"
  A.lkDist = wtLabel(A.lock, UDim2.fromOffset(90, 15), UD2(1, 8, 0, 1), V2(0, 0), Enum.TextXAlignment.Left)
  A.lkDist.Name = "TargetRange"
  A.lkVc = wtLabel(A.lock, UDim2.fromOffset(90, 15), UD2(1, 8, 0, 18), V2(0, 0), Enum.TextXAlignment.Left)
  A.lkVc.Name = "Closure"
  A.seek = round(frame(gui, UDim2.fromOffset(36, 36), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5)))   -- 红外导引头的圈
  A.seek.Name = "Seeker"
  A.seekStroke = stroke(A.seek, WT, 1.6, 0)
  A.seek.Visible = false

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
    A.rng.Visible = false   -- 战雷式：距离写在锁定框右边
    -- 机头的全息标记
    local hk = math.min(1, info.hk or 0)
    local hcol = HOLO:Lerp(RGB(255, 90, 70), hk * 0.8)
    local cf = info.cf
    local showHolo = false
    if pilot and cf then
      local pre = (d.kind == "heli") and "holoHeli" or "holoJet"
      local okArt = true   -- 准星是框拼的（不用 EditableImage 的图）：一直能投到机头前面
      local pos = cf.Position + cf.LookVector * HOLO_D
      local cp = cam.CFrame
      local rel = pos - cp.Position
      if okArt then
        local vh = math.max(cam.ViewportSize.Y, 1)
        local f = (vh / 2) / math.tan(math.rad(cam.FieldOfView / 2))
        local hgt = rel.Magnitude * HOLO_PX * (1 + 0.3 * hk) / f   -- 离镜头越远做得越大：屏幕上看着一样大
        holoPart.Size = V3(hgt * 128 / 192, hgt, 0.05)
        holoPart.CFrame = CFrame.new(pos) * (cf - cf.Position) * CFrame.Angles(HOLO_TILT, 0, 0)
        local core = CORE:Lerp(RGB(255, 150, 130), hk * 0.7)
        A.ret.ring.Color = core
        A.ret.dot.BackgroundColor3 = core
        for _, t in ipairs(A.ret.ticks) do t.BackgroundColor3 = core end
        A.ret.glow.Color = hcol
        A.ret.glow.Transparency = 0.62 + 0.12 * math.noise(lastT * 6, 3.3)   -- 全息的光晕微微闪
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
    -- 机炮提前量：一个小圈（不转），锁着目标时一根细线连到目标（战雷）
    A.maim.Visible = pilot and info.maim ~= nil
    if info.maim then A.maim.Position = info.maim end
    A.lead.Visible = pilot and info.lead ~= nil
    if info.lead then
      A.lead.Position = info.lead
      A.leadT.Text = info.leadDist and string.format("%d", math.floor(info.leadDist / 2.8 + 0.5)) or ""
    end
    A.aim.Visible = pilot and info.aim ~= nil
    if info.aim then
      A.aim.Position = info.aim
      A.aim.Rotation = 0
      A.aim.ImageColor3 = WT
    end
    -- 锁定（战雷式）
    local lk = info.lock
    if pilot and lk and lk.on then
      local col = lk.inCone and WT or YEL
      local ir = lk.seeker == "ir"
      local k = lk.locked and 1 or math.clamp(lk.k or 0, 0, 1)
      A.lock.Visible = true
      A.lock.Position = lk.p
      local blink = (lastT * 4) % 1 < 0.6   -- 雷达弹锁定中：方框一秒闪四下
      A.lockBox.Transparency = (lk.locked or (not ir and blink)) and 0 or 1
      A.lockBox.Color = col
      A.lkName.Text = lk.name or ""
      local m = (lk.dist or info.lockDist or 0) / 2.8
      A.lkDist.Text = (m >= 1000) and string.format("%.1f km", m / 1000) or string.format("%d m", math.floor(m + 0.5))
      A.lkVc.Text = lk.vc and string.format("%d m/s", math.floor(lk.vc + 0.5)) or ""
      A.lkName.TextColor3, A.lkDist.TextColor3, A.lkVc.TextColor3 = col, col, col
      if ir then   -- 红外：导引头圈从机头滑到目标上，锁上了收小一点套住目标
        A.seek.Visible = true
        A.seek.Position = (lk.bore or UD2(0.5, 0, 0.5, 0)):Lerp(lk.p, k)
        local sz = lk.locked and 30 or 36
        A.seek.Size = UDim2.fromOffset(sz, sz)
        A.seekStroke.Color = col
      else
        A.seek.Visible = false
      end
      A.lock:SetAttribute("Progress", k)
      A.lock:SetAttribute("Locked", lk.locked == true)
      A.lock:SetAttribute("InCone", lk.inCone == true)
      A.lock:SetAttribute("Seeker", lk.seeker or "")
    else
      A.lock.Visible = false
      A.seek.Visible = false
    end
    -- 提前量小圈到目标的细线：两头各让开圈和框
    local showLine = false
    if pilot and info.aim and lk and lk.on then
      local ax, ay = info.aim.X.Offset, info.aim.Y.Offset
      local bx, by = lk.p.X.Offset, lk.p.Y.Offset
      local dx, dy = bx - ax, by - ay
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 40 then
        local ux, uy = dx / len, dy / len
        local x0, y0, x1, y1 = ax + ux * 10, ay + uy * 10, bx - ux * 24, by - uy * 24
        A.leadLine.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
        A.leadLine.Size = UDim2.fromOffset(len - 34, 1.5)
        A.leadLine.Rotation = math.deg(math.atan2(dy, dx))
        A.leadLine.BackgroundColor3 = WT
        showLine = true
      end
    end
    A.leadLine.Visible = showLine
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
    -- 战雷式界面（WtFlight.lua；用户 11-24 夜：「战雷ui压根不是这样的」，发了战雷的截图）：开着时开飞机的人这一套 MWT 式的收起来
    --   （右上机型侧影血量、准星两边高度速度、准星上方弹的牌子、六边形武器键、机头全息准星、绿方框锁定）；
    --   留着热成像、鼠标瞄准的白圈（按 M 切过去才有）、机炮提前量小圈；坐后面的乘客照旧看右上那块
    if G.wtFlightOn and G.wtFlightStep then
      A.card.Visible = not pilot
      root.Visible = false
      A.hexBar.Visible = false
      hsg.Enabled = false
      A.boreFall.Visible = false
      A.lock.Visible, A.seek.Visible, A.leadLine.Visible, A.aim.Visible = false, false, false, false
      G.wtFlightStep(st, info)
    else
      A.card.Visible = true
    end
  end

  -- 光电吊舱、无人机画面：这一套收起来（热成像也先让开，出来再开）
  function G.airHudOff()
    if gui.Enabled then gui.Enabled = false end
    hsg.Enabled = false
    irApply(false)
    if G.wtFlightOff then G.wtFlightOff() end
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
