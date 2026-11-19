-- Roblox全面大战场——瞄准镜（客户端）：狙击镜、望远镜开镜后的光学目镜（替换原来 Play 里四块黑板围出的方框）
--   用户：瞄准镜第一人称太粗糙、要有光学效果，而且居然不是圆的而是多边形
--   出瞳是正圆：Frame + UICorner 成圆，外面一圈特别粗的黑描边把四周盖住（同夜视仪的镜筒）。狙击镜两个圆叠着——
--     A 是目镜的视场光阑（边利、渐暗带窄），B 是眼睛的出瞳（大一点、渐暗带宽）：眼睛对正时 B 在 A 外面；镜子一晃、转得快、走路、开枪、
--     刚贴上目镜时两个圆错开，看得见的是两圆相交那块，边上一道月牙形的「镜内阴影」
--   边缘渐暗：一圈圈半透明黑描边叠出来（UI 没有径向渐变）；红、蓝两道细圈朝相反方向错开一点，是边上的色散彩边
--   镜片：镀膜的淡色、左上一道反光弧（描边挂渐变，只露一段）、镜头里有月亮时的眩光（光源和画面中心的连线上一串彩色鬼影、一道横向拉丝）
--   开镜：先黑一下（眼睛贴上目镜），出瞳从小变大，画面从糊到清楚（对焦）；滚轮变倍、开枪时也轻轻糊一下
--   分划在第二焦平面（大小不随倍率变）：狙击镜是密位点 + 四根粗柱，中心红点夜里发光（开着夜视仪时调暗）；
--     望远镜：两个圆并排（左右各按半边屏幕裁开，正好是两圆的并集，中间上下两个尖角）、测距框和密位刻度，底下一行琥珀色的距离 / 方位 / 倍率
--   手稳：呼吸晃，按住 Shift 屏住（稳几秒，憋过头晃得更厉害、一会儿屏不了），走动晃得多；晃动加在镜头上（子弹照样打屏幕正中），
--     镜头转得快、开枪时出瞳跟着偏；倍率高时鼠标灵敏度跟着降
--   别人开着镜对着你（他的视线在你附近 20° 以内）时他的镜片闪光：服务器只记 Scoped / ScopeDir 两个属性，闪光是看的人本地画的、墙挡得住
--   步枪（M4）上装的 ACOG（kind acog）：固定 3.5 倍、TA31 的红色箭形分划和测距线，不屏息、不闪镜片（用户：武器瞄准没有镜子）
--   Play 调：G.scopeStep(dt, 开没开, 武器表) 每帧、G.scopeZoom(武器表) 现在的倍率、G.scopeFire() 开了一枪
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")

local Scope = {}

function Scope.init(G)
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local RGB, V2 = Color3.fromRGB, Vector2.new
  local now = os.clock
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BLACK = RGB(0, 0, 0)

  ---------------------------------------------------------------- 界面零件

  local gui = Instance.new("ScreenGui")
  gui.Name = "Scope"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = -1   -- 在主界面（弹药、命中标记）下面、夜视仪镜筒上面
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function fr(parent, z, color, alpha)
    local f = Instance.new("Frame")
    f.AnchorPoint = V2(0.5, 0.5)
    f.BackgroundColor3 = color or BLACK
    f.BackgroundTransparency = (alpha == nil) and 0 or alpha
    f.BorderSizePixel = 0
    f.ZIndex = z or 1
    f.Parent = parent
    return f
  end
  local function round(f)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
    return f
  end
  local function ring(f, th, color, alpha)
    local s = Instance.new("UIStroke")
    s.Thickness, s.Color, s.Transparency = th, color, alpha
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function grad(parent, rot, keys)   -- 透明度渐变：keys = { { 位置, 透明度 }, … }
    local g = Instance.new("UIGradient")
    g.Rotation = rot
    local seq = {}
    for _, k in ipairs(keys) do table.insert(seq, NumberSequenceKeypoint.new(k[1], k[2])) end
    g.Transparency = NumberSequence.new(seq)
    g.Parent = parent
    return g
  end
  local function at(f, x, y) f.Position = UDim2.fromOffset(x, y) end
  local function sz(f, w, h) f.Size = UDim2.fromOffset(w, h or w) end

  local root = Instance.new("Frame")
  root.Size = UDim2.fromScale(1, 1)
  root.BackgroundTransparency = 1
  root.Parent = gui

  -- 一个圆形出瞳：容器（D × D）里一个圆，外面 3200 像素的黑描边盖住四周；里面 n 圈半透明黑描边叠成边缘渐暗
  --   band 渐暗带占直径的比例，k 最外一圈的不透明度，pw 往里衰减的指数
  local function aperture(parent, z, n, band, k, pw)
    local box = fr(parent, z, BLACK, 1)
    local mask = round(fr(box, z, BLACK, 1))
    mask.Position, mask.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
    ring(mask, 3200, BLACK, 0)
    local rings = {}
    for i = 1, n do
      local f = round(fr(box, z, BLACK, 1))
      f.Position = UDim2.fromScale(0.5, 0.5)
      rings[i] = { f = f, s = ring(f, 1, BLACK, 1 - k * (1 - (i - 1) / n) ^ pw) }
    end
    return { box = box, rings = rings, band = band, d = -1 }
  end
  local function sizeAp(ap, D)   -- 按像素直径摆渐暗圈（直径变了才重摆）；圈宽取整、一圈挨一圈（叠起来的地方会多出一道细纹）
    D = math.floor(D / 2 + 0.5) * 2
    if ap.d == D then return end
    ap.d = D
    sz(ap.box, D)
    local n = #ap.rings
    local w = math.max(1, math.floor(D * ap.band / n + 0.5))
    for i, r in ipairs(ap.rings) do
      sz(r.f, math.max(2, D - 2 * i * w))
      r.s.Thickness = w
    end
  end

  ---------------------------------------------------------------- 层（从下往上）：镜片 → 分划 → 眩光 → 出瞳 B → 出瞳 A → 色散彩边 → 黑场 → 读数

  -- 镜片：镀膜的淡色、反光弧（狙击镜跟着出瞳 A 走）
  local lens = fr(root, 1, BLACK, 1)
  local tint = round(fr(lens, 1, RGB(18, 34, 44), 0.93))
  tint.Position, tint.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
  grad(tint, 90, { { 0, 0.4 }, { 0.5, 0.75 }, { 1, 0.15 } })   -- 上下边色深一点
  local glare = round(fr(lens, 1, BLACK, 1))
  glare.Position, glare.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.9)
  local glareS = ring(glare, 3, RGB(235, 245, 255), 0)
  grad(glareS, 45, { { 0, 1 }, { 0.1, 0.86 }, { 0.2, 0.8 }, { 0.3, 0.93 }, { 0.4, 1 }, { 1, 1 } })   -- 只左上露一段
  local glare2 = round(fr(lens, 1, BLACK, 1))   -- 右下一道暖色的弱反光
  glare2.Position, glare2.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8)
  local glare2S = ring(glare2, 2, RGB(255, 214, 160), 0)
  grad(glare2S, 45, { { 0, 1 }, { 0.72, 1 }, { 0.84, 0.9 }, { 0.94, 1 }, { 1, 1 } })

  -- 分划：容器在屏幕正中（子弹打这儿），零件位置按直径的比例，布置在 layoutRet 里
  local ret = fr(root, 2, BLACK, 1)
  local retParts = {}   -- { f, x, y, w, h（直径的比例；w / h 小于 0 是像素数）, kind }
  local function rp(kind, x, y, w, h, color, alpha, isRound)
    local f = fr(ret, 2, color, alpha)
    if isRound then round(f) end
    table.insert(retParts, { f = f, x = x, y = y, w = w, h = h, kind = kind, a0 = alpha })
    return f
  end
  local RC = RGB(6, 6, 6)            -- 刻线
  local RED = RGB(255, 46, 30)       -- 发光的中心
  local AMB = RGB(255, 160, 52)      -- 望远镜的琥珀色读数
  local RCI = RGB(150, 26, 18)        -- 照明分划：暗红（夜里能看清，不刺眼）
  -- 狙击镜分划（第一焦平面，同这具 ATACR F1：刻线跟倍率一起放大缩小，1 密位在目标上永远是 1 米 / 千米）：
  --   细十字贯穿；每 1 密位一个刻度（5、10 长一点），倍率高时加半密位；10 密位以外是粗柱；右边、下边标 2 4 6 8；
  --   中心下面一组提前量 / 风偏点（倍率够高才画）；中心 ±2 密位那段细十字和中心点夜里发暗红光
  --   零件位置是「密位」，layoutFfp 按现在每密位多少像素摆；mw / mh 宽高（密位，0 = 只按像素下限），pw / ph 像素下限，need 每密位至少几像素才画
  local ffp = {}
  local function fe(x, y, mw, mh, pw, ph, need, color, alpha, isRound, lit)
    local f = fr(ret, 2, color or RC, alpha or 0)
    if isRound then round(f) end
    table.insert(ffp, { f = f, x = x, y = y, mw = mw, mh = mh, pw = pw, ph = ph, need = need or 0, lit = lit })
    return f
  end
  fe(0, 0, 400, 0, 0, 1)
  fe(0, 0, 0, 400, 1, 0)
  fe(0, 0, 4, 0, 0, 1, 0, RCI, 0.05, false, true)   -- 中心发光的一段
  fe(0, 0, 0, 4, 1, 0, 0, RCI, 0.05, false, true)
  for _, sgn in ipairs({ -1, 1 }) do
    fe(sgn * 60, 0, 100, 0.32, 0, 3)   -- 粗柱：10 密位以外
    fe(0, sgn * 60, 0.32, 100, 3, 0)
    for i = 1, 10 do
      local big = i % 5 == 0
      local L = big and 0.9 or 0.5
      local tx = fe(sgn * i, 0, 0, L, 1, big and 5 or 3)
      local ty = fe(0, sgn * i, L, 0, big and 5 or 3, 1)
      if sgn > 0 then tx.Name, ty.Name = "MilX" .. i, "MilY" .. i end   -- 测试按名字找（第 i 个密位的刻度）
      fe(sgn * (i - 0.5), 0, 0, 0.25, 1, 2, 9)   -- 半密位
      fe(0, sgn * (i - 0.5), 0.25, 0, 2, 1, 9)
    end
  end
  local ffpNum = {}
  for _, v in ipairs({ 2, 4, 6, 8 }) do
    for _, axis in ipairs({ "x", "y" }) do
      local l = Instance.new("TextLabel")
      l.AnchorPoint = V2(0.5, 0.5)
      l.BackgroundTransparency = 1
      l.Font = Enum.Font.RobotoMono
      l.TextColor3 = RC
      l.Text = tostring(v)
      l.ZIndex = 2
      l.Size = UDim2.fromOffset(24, 16)
      l.Parent = ret
      table.insert(ffpNum, { l = l, x = (axis == "x") and v or -0.95, y = (axis == "x") and 0.95 or v })
    end
  end
  for j = 2, 6 do   -- 中心下面的提前量 / 风偏点
    for i = 1, j - 1 do
      fe(-i, j, 0.1, 0.1, 2, 2, 11, RC, 0, true)
      fe(i, j, 0.1, 0.1, 2, 2, 11, RC, 0, true)
    end
  end
  local dot = fe(0, 0, 0.16, 0.16, 3, 3, 0, RED, 0.08, true, true)
  local glow = fe(0, 0, 0.5, 0.5, 9, 9, 0, RED, 0.82, true, true)
  local ffpK = -1
  local function layoutFfp(k)   -- k：每密位多少像素
    if math.abs(k - ffpK) < ffpK * 0.004 then return end
    ffpK = k
    for _, e in ipairs(ffp) do
      e.f.Visible = k >= e.need
      if e.f.Visible then
        sz(e.f, math.max(e.pw, math.floor(e.mw * k + 0.5)), math.max(e.ph, math.floor(e.mh * k + 0.5)))
        at(e.f, math.floor(e.x * k + 0.5), math.floor(e.y * k + 0.5))
      end
    end
    local ts = math.clamp(math.floor(k * 0.55), 10, 15)
    for _, n in ipairs(ffpNum) do
      n.l.Visible = k >= 7
      n.l.TextSize = ts
      at(n.l, math.floor(n.x * k + 0.5), math.floor(n.y * k + 0.5))
    end
  end
  -- 望远镜：测距框（四个角）、中心小十字（中间空着）、下面一条密位刻度
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    rp("ba", c[1] * 0.04 - c[1] * 0.008, c[2] * 0.04, 0.016, -1, AMB, 0.12)
    rp("ba", c[1] * 0.04, c[2] * 0.04 - c[2] * 0.008, -1, 0.016, AMB, 0.12)
  end
  for _, c in ipairs({ { -0.013, 0, 0.012, -1 }, { 0.013, 0, 0.012, -1 }, { 0, -0.013, -1, 0.012 }, { 0, 0.013, -1, 0.012 } }) do
    rp("b", c[1], c[2], c[3], c[4], AMB, 0.2)
  end
  rp("b", 0, 0.1, 0.4, -1, AMB, 0.45)
  for k = -10, 10 do
    local big = k % 5 == 0
    rp("b", k * 0.02, 0.1 - (big and 0.012 or 0.006), -1, big and 0.024 or 0.012, AMB, big and 0.3 or 0.5)
  end
  local function layoutRet(D, kind)   -- 望远镜的刻线（按直径的比例）
    local t1 = math.max(1, math.floor(D / 700 + 0.5))
    local t2 = math.max(4, math.floor(D / 95 + 0.5))
    for _, p in ipairs(retParts) do
      local mine = kind == "binoc"
      p.f.Visible = mine
      if mine then
        local px = function(v) if v >= 0 then return math.max(1, math.floor(v * D + 0.5)) end return (v == -3) and t2 or t1 end
        local w, h = px(p.w), px(p.h)
        sz(p.f, w, h)
        at(p.f, math.floor(p.x * D + 0.5), math.floor(p.y * D + 0.5))
      end
    end
  end

  -- 步枪上的 ACOG（Trijicon TA31 的箭形分划，第二焦平面：大小按出瞳直径的比例，不随倍率变）：中心一个红色发光的箭形（尖是瞄准点），
  --   下面一根细竖线挂着 400～800 米的测距横线（越远越短，正好是人肩宽），左右各一段横线（不到中心）
  local acogRet = fr(root, 2, BLACK, 1)
  local acog = {}   -- { f, x, y, w, h（直径的比例；负数是像素），lit 发光的、a0 原来的透明度 }
  local function ae(x, y, w, h, color, alpha, rot, lit)
    local f = fr(acogRet, 2, color or RC, alpha or 0)
    if rot then f.Rotation = rot end
    table.insert(acog, { f = f, x = x, y = y, w = w, h = h, lit = lit, a0 = alpha or 0 })
    return f
  end
  do
    local CH, CA = 0.042, 50   -- 箭形每边多长（直径的比例）、和竖直方向的夹角（度）
    local sa, ca = math.sin(math.rad(CA)), math.cos(math.rad(CA))
    local CR = RGB(255, 52, 36)
    for _, k in ipairs({ { -10, 1.16, 0.84 }, { -4, 1, 0.02 } }) do   -- 先画一圈晕光、再画箭形本身
      ae(CH * 0.5 * sa, CH * 0.5 * ca, k[1], CH * k[2], CR, k[3], -CA, true)
      ae(-CH * 0.5 * sa, CH * 0.5 * ca, k[1], CH * k[2], CR, k[3], CA, true)
    end
    local y0, y1 = CH * ca + 0.012, 0.19
    ae(0, (y0 + y1) / 2, -1, y1 - y0, RC, 0.1)
    for _, v in ipairs({ { 0.07, 0.05 }, { 0.1, 0.041 }, { 0.13, 0.034 }, { 0.16, 0.028 }, { 0.19, 0.023 } }) do ae(0, v[1], v[2], -2, RC, 0.08) end
    ae(-0.3, 0, 0.4, -2, RC, 0.04)
    ae(0.3, 0, 0.4, -2, RC, 0.04)
  end
  local function layoutAcog(D)
    for _, e in ipairs(acog) do
      local w = (e.w >= 0) and math.max(1, math.floor(e.w * D + 0.5)) or -e.w
      local h = (e.h >= 0) and math.max(1, math.floor(e.h * D + 0.5)) or -e.h
      sz(e.f, w, h)
      at(e.f, math.floor(e.x * D + 0.5), math.floor(e.y * D + 0.5))
    end
  end

  -- 出瞳：狙击镜 A（视场光阑）、B（眼睛的出瞳）；望远镜左右两个（各在半边屏幕的裁剪框里）
  local apB = aperture(root, 4, 12, 0.13, 0.95, 1.6)
  local apA = aperture(root, 5, 10, 0.075, 0.92, 2.2)
  local clipL = fr(root, 5, BLACK, 1)
  clipL.AnchorPoint, clipL.ClipsDescendants = V2(0, 0), true
  local clipR = fr(root, 5, BLACK, 1)
  clipR.AnchorPoint, clipR.ClipsDescendants = V2(0, 0), true
  local apL = aperture(clipL, 5, 10, 0.09, 0.93, 2.0)
  local apR = aperture(clipR, 5, 10, 0.09, 0.93, 2.0)
  local tintL = round(fr(clipL, 4, RGB(40, 34, 18), 0.94))   -- 望远镜的镀膜偏暖
  local tintR = round(fr(clipR, 4, RGB(40, 34, 18), 0.94))

  -- 色散彩边：出瞳 A 边上一红一蓝两道细圈，朝相反方向错开
  local caR = round(fr(root, 6, BLACK, 1))
  local caRs = ring(caR, 2, RGB(255, 90, 50), 0.55)
  local caB = round(fr(root, 6, BLACK, 1))
  local caBs = ring(caB, 2, RGB(70, 120, 255), 0.5)

  -- 开镜时黑一下
  local blackout = fr(root, 8, BLACK, 1)
  blackout.AnchorPoint, blackout.Size = V2(0, 0), UDim2.fromScale(1, 1)

  -- 读数：狙击镜在出瞳右边的黑处写倍率、下面一条屏息条；望远镜在视野底部写距离 · 方位 · 倍率（琥珀色）
  local function txt(z, size, color)
    local l = Instance.new("TextLabel")
    l.AnchorPoint = V2(0.5, 0.5)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextColor3 = color
    l.TextSize = size
    l.ZIndex = z
    l.Size = UDim2.fromOffset(520, size + 6)
    l.Parent = root
    return l
  end
  local zoomT = txt(9, 18, RGB(150, 156, 152))
  local breathBg = fr(root, 9, RGB(60, 64, 62), 0.35)
  local breathFill = fr(breathBg, 9, RGB(200, 206, 200), 0.1)
  breathFill.AnchorPoint = V2(0.5, 1)
  breathFill.Position = UDim2.fromScale(0.5, 1)
  local lrfT = txt(9, 18, AMB)
  lrfT.TextStrokeTransparency, lrfT.TextStrokeColor3 = 0.6, RGB(80, 30, 0)

  -- 手机：变倍按钮
  local zin, zout
  if UIS.TouchEnabled then
    local function zb(text)
      local b = Instance.new("TextButton")
      b.AnchorPoint = V2(0.5, 0.5)
      b.Size = UDim2.fromOffset(46, 46)
      b.BackgroundColor3 = RGB(18, 20, 22)
      b.BackgroundTransparency = 0.25
      b.BorderSizePixel = 0
      b.Text = text
      b.TextColor3 = RGB(220, 224, 220)
      b.TextSize = 24
      b.Font = Enum.Font.GothamMedium
      b.ZIndex = 9
      b.Parent = root
      round(b)
      ring(b, 1, RGB(255, 255, 255), 0.8)
      return b
    end
    zin, zout = zb("+"), zb("−")
  end

  ---------------------------------------------------------------- 本地画面效果：开镜对焦的模糊、镜片调色

  local blur = Instance.new("BlurEffect")
  blur.Name = "ScopeFocus"
  blur.Size = 0
  blur.Enabled = false
  blur.Parent = Lighting
  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "ScopeGrade"
  cc.Contrast, cc.Saturation, cc.Brightness, cc.TintColor = 0.07, 0.08, 0.015, RGB(247, 251, 255)
  cc.Enabled = false
  cc.Parent = Lighting

  ---------------------------------------------------------------- 状态

  local KINDS = {
    sniper = { zooms = { 7, 10, 14, 20, 27, 35 }, sway = 0.0017, def = 10 },   -- 这具 ATACR 是 7–35 倍
    acog = { zooms = { 3.5 }, sway = 0.0008, def = 3.5 },   -- 步枪上的 ACOG：固定 3.5 倍，倍率低、晃得少
    binoc = { zooms = { 4, 6, 8, 10 }, sway = 0.0011, def = 8 },
  }
  local S = {
    kind = nil, t0 = 0, zi = {}, eye = V2(), eyeV = V2(), ang = V2(), breath = 1, hold = false, tired = 0,
    swayP = 0, swayY = 0, appP = 0, appY = 0, prev = nil, vs = V2(), blurK = 0, sens = nil, sendT = 0, sentDir = nil,
    lrfT = 0, phase = 0,
  }
  G.scopeOn = false

  local function kindOf(w)
    if w and w.kind == "spot" then return "binoc" end
    if w and w.optic == "acog" then return "acog" end
    return "sniper"
  end
  local function zoomIndex(kind, want)
    local K, best, bd = KINDS[kind], 1, 1e9
    for i, z in ipairs(K.zooms) do
      if math.abs(z - want) < bd then best, bd = i, math.abs(z - want) end
    end
    return best
  end
  function G.scopeZoom(w)
    local kind = kindOf(w)
    if not S.zi[kind] then S.zi[kind] = zoomIndex(kind, KINDS[kind].def) end
    return KINDS[kind].zooms[S.zi[kind]]
  end
  local function changeZoom(d)
    local kind = S.kind
    if not kind then return end
    local K = KINDS[kind]
    local i = math.clamp((S.zi[kind] or zoomIndex(kind, K.def)) + d, 1, #K.zooms)
    if i == S.zi[kind] then return end
    S.zi[kind] = i
    S.blurK = math.max(S.blurK, 4)   -- 变倍时像糊一下再对上焦
    if G.playSound then G.playSound("quiet", nil, 1.9) end
  end

  local function onHold(_, state)
    if state == Enum.UserInputState.Begin then S.hold = true
    elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then S.hold = false end
    return Enum.ContextActionResult.Sink   -- 别让 Shift 去切 Roblox 的视角锁定
  end

  local D, Db = 0, 0   -- 狙击镜出瞳直径、望远镜每个圆的直径（像素）
  local function layout(kind)
    local vs = cam.ViewportSize
    S.vs = vs
    D = math.min(vs.X, vs.Y) * 0.96
    Db = math.min(vs.Y * 0.86, vs.X * 0.5)
    local Dr = (kind == "binoc") and Db * 1.1 or D
    layoutRet(Dr, kind)
    at(ret, vs.X / 2, vs.Y / 2)
    sz(ret, 0)
    ret.Visible = kind ~= "acog"
    acogRet.Visible = kind == "acog"
    if kind == "acog" then
      layoutAcog(D)
      at(acogRet, vs.X / 2, vs.Y / 2)
      sz(acogRet, 0)
    end
    local big = kind ~= "binoc"
    apA.box.Visible, apB.box.Visible, lens.Visible, caR.Visible, caB.Visible = big, big, big, big, big
    clipL.Visible, clipR.Visible = not big, not big
    sizeAp(apL, Db)
    sizeAp(apR, Db)
    sz(tintL, Db)
    sz(tintR, Db)
    zoomT.TextSize = math.max(14, math.floor(D / 48))
    lrfT.TextSize = math.max(14, math.floor(Db / 40))
    zoomT.Visible, breathBg.Visible = kind == "sniper", kind == "sniper"   -- ACOG 是定倍的、也不用屏息
    lrfT.Visible = not big
    if zin then   -- 手机：变倍按钮在镜子左边（右边是开火键、小地图）
      local bx = math.max(36, vs.X / 2 - Dr / 2 - 40)
      zin.Visible, zout.Visible = kind ~= "acog", kind ~= "acog"
      at(zin, bx, vs.Y / 2 - 78)
      at(zout, bx, vs.Y / 2 - 24)
    end
  end

  local function sendState(on)
    pcall(function() G.R.Act:FireServer("scope", on, on and cam.CFrame.LookVector or nil) end)
  end

  local function enter(kind)
    S.kind = kind
    S.t0 = now()
    G.scopeOn = true
    layout(kind)
    S.eye = V2(0, (kind == "binoc" and Db or D) * 0.16)   -- 刚贴上目镜：出瞳从下面进来
    S.eyeV = V2()
    S.blurK = 0
    S.prev, S.lastP = nil, nil
    gui.Enabled = true
    blur.Enabled, cc.Enabled = true, true
    if G.mapRoot then G.mapRoot.Visible = false end   -- 开着镜不画小地图（手机上它会挡住半个目镜）
    if not S.sens then pcall(function() S.sens = UIS.MouseDeltaSensitivity end) end
    if kind ~= "acog" then   -- 步枪的 ACOG：Shift 留给别的（不屏息）；也不告诉服务器（人人端枪都闪镜片就没意思了，闪光只留给狙击镜、望远镜）
      pcall(function()
        CAS:BindActionAtPriority("ScopeHoldBreath", onHold, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
      end)
      S.sendT, S.sentDir = now(), cam.CFrame.LookVector
      sendState(true)
    end
    if G.playSound then G.playSound("quiet", nil, 1.1) end
  end

  local function exit()
    local was = S.kind
    S.kind = nil
    G.scopeOn = false
    gui.Enabled = false
    blur.Enabled, cc.Enabled = false, false
    blur.Size = 0
    if G.mapRoot then G.mapRoot.Visible = true end
    S.hold = false
    if S.sens then
      local v = S.sens
      pcall(function() UIS.MouseDeltaSensitivity = v end)
      S.sens = nil
    end
    pcall(function() CAS:UnbindAction("ScopeHoldBreath") end)
    if was ~= "acog" then sendState(false) end
  end

  function G.scopeFire()
    if not S.kind then return end
    local d = (S.kind == "binoc") and Db or D
    S.eyeV += V2((math.random() - 0.5) * 0.5 * d, 2.2 * d)   -- 后坐：镜子往后往上一跳，出瞳往下甩
    S.blurK = math.max(S.blurK, 5)
  end

  ---------------------------------------------------------------- 每帧（Play 调）

  local function moonOnScreen()
    local ok, dir = pcall(function() return Lighting:GetMoonDirection() end)
    if not ok or typeof(dir) ~= "Vector3" or dir.Y < -0.05 then return nil end
    local p, vis = cam:WorldToViewportPoint(cam.CFrame.Position + dir * 5000)
    if not vis or p.Z <= 0 then return nil end
    return V2(p.X, p.Y)
  end

  local function bearing(look)
    local deg = math.deg(math.atan2(look.X, -look.Z)) % 360   -- 北是 −Z、东是 +X（同地图）
    return deg, T("dir." .. (math.floor((deg + 22.5) / 45) % 8))
  end

  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude

  function G.scopeStep(dt, on, w)
    if on and G.fpsOpticPending and G.fpsOpticPending() then on = false end   -- 第一人称还在把真瞄准镜举到眼前：举到了再换成目镜里的像
    local kind = on and kindOf(w) or nil
    if kind ~= S.kind then
      if S.kind then exit() end
      if kind then enter(kind) end
    end
    if not kind then return end
    dt = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
    local t = now()
    local vs = cam.ViewportSize
    if vs ~= S.vs then layout(kind) end
    local K = KINDS[kind]
    local zoom = G.scopeZoom(w)
    local cx, cy = vs.X / 2, vs.Y / 2
    local d = (kind == "binoc") and Db or D

    -- 呼吸、屏息、走动 → 晃动幅度
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local spd = 0   -- 走多快：按位置变化算（同 FPSView）
    if hrp then
      local p = hrp.Position
      if S.lastP then spd = V2(p.X - S.lastP.X, p.Z - S.lastP.Z).Magnitude / dt end
      S.lastP = p
      spd = math.min(spd, 40)
    end
    local move = math.clamp(spd / 16, 0, 1.5)
    local amp = K.sway * (1 + move * 2.5)
    if S.tired > 0 then
      S.tired -= dt
      amp *= 2.2
      S.breath = math.min(1, S.breath + dt / 6)
    elseif S.hold and S.breath > 0 and kind == "sniper" then
      S.breath -= dt / 5
      amp *= 0.12
      if S.breath <= 0 then S.breath, S.tired = 0, 2.5 end
    else
      S.breath = math.min(1, S.breath + dt / 4)
    end
    if UIS.TouchEnabled and not UIS.KeyboardEnabled then amp *= 0.6 end
    local tt = t * 6.2832
    S.swayP = amp * (math.sin(tt * 0.21) + 0.9 * math.noise(t * 0.7, 3.1))
    S.swayY = amp * 0.7 * (math.sin(tt * 0.13 + 1.1) + 1.0 * math.noise(t * 0.6, 7.7))

    -- 出瞳的偏移（弹簧）：镜头转得快 → 落后；走路一颠一颠；呼吸带一点
    S.phase += dt * spd * 0.55
    local target = V2(-S.ang.X, S.ang.Y) * 0.05 * d
      + V2(math.sin(S.phase) * 0.045 * d * move, math.abs(math.cos(S.phase)) * 0.03 * d * move)
      + V2(S.swayY, -S.swayP) * 6 * d
    S.eyeV += ((target - S.eye) * 150 - S.eyeV * 19) * dt
    S.eye += S.eyeV * dt
    if S.eye.Magnitude > 0.24 * d then S.eye = S.eye.Unit * 0.24 * d end
    local eye = S.eye

    -- 开镜动画：黑一下、出瞳由小变大、对焦
    local k = math.clamp((t - S.t0) / 0.24, 0, 1)
    local ease = 1 - (1 - k) ^ 3
    local scale = 0.8 + 0.2 * ease
    blackout.BackgroundTransparency = math.clamp((t - S.t0 - 0.04) / 0.13, 0, 1)
    S.blurK = math.max(0, S.blurK - dt * 22)
    local focus = (1 - math.clamp((t - S.t0) / 0.34, 0, 1)) ^ 2 * 16
    blur.Size = math.max(focus, S.blurK)
    -- 鼠标灵敏度随倍率降（高倍时拖一下不会甩出去好远）
    if S.sens then
      local v = S.sens * (1 / zoom) ^ 0.85
      if UIS.MouseDeltaSensitivity ~= v then pcall(function() UIS.MouseDeltaSensitivity = v end) end
    end

    if kind == "sniper" or kind == "acog" then
      local DA = D * scale
      local ax, ay = cx + eye.X, cy + eye.Y
      sizeAp(apA, DA)
      at(apA.box, ax, ay)
      sizeAp(apB, DA * 1.06)
      at(apB.box, cx - eye.X * 0.8, cy - eye.Y * 0.8)
      at(lens, ax, ay)
      sz(lens, DA)
      -- 色散：偏得越多彩边越宽
      local off = eye.Magnitude > 0.5 and eye.Unit * math.min(eye.Magnitude * 0.035, 3.5) or V2()
      local ca = math.min(0.35, eye.Magnitude / d * 1.6)   -- 对正时几乎看不出，偏了才明显
      local dc = DA - 5
      sz(caR, dc)
      sz(caB, dc)
      at(caR, ax + off.X + 0.35, ay + off.Y + 0.2)
      at(caB, ax - off.X - 0.35, ay - off.Y - 0.2)
      caRs.Transparency = 0.8 - ca
      caBs.Transparency = 0.78 - ca
      if kind == "acog" then
        -- 箭形照明：夜里亮（光纤 + 氚光），开着夜视仪调暗；分划跟着出瞳一起晃（第二焦平面，大小不变）
        local nv = G.nvgOn and G.nvgOn()
        for _, e in ipairs(acog) do
          if e.lit then e.f.BackgroundTransparency = nv and math.min(0.92, e.a0 + 0.45) or e.a0 end
        end
      else
        -- 倍率、屏息条（出瞳左边的黑处；右下角是小地图）
        local rx = math.max(40, cx - D / 2 - 46)
        zoomT.Text = string.format("%.1f×", zoom)
        at(zoomT, rx, cy + D * 0.3)
        sz(breathBg, 3, math.floor(D * 0.12))
        at(breathBg, rx, cy + D * 0.38)
        breathFill.Size = UDim2.new(1, 0, math.clamp(S.breath, 0, 1), 0)
        breathFill.BackgroundColor3 = (S.tired > 0) and RGB(220, 90, 70) or RGB(200, 206, 200)
        breathBg.BackgroundTransparency = (S.breath >= 1 and not S.hold) and 0.75 or 0.35
        -- 分划按现在的视角摆（第一焦平面：每密位的像素数 = 屏幕半高 ÷ tan(半视角) × 0.001）
        layoutFfp(0.001 * (vs.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2))
        -- 照明：夜里中心那段细十字和中心点发暗红光；开着夜视仪时画面本来就亮，照明调暗（不然一团光）
        local nv = G.nvgOn and G.nvgOn()
        if S.lit ~= (not nv) then
          S.lit = not nv
          for _, e in ipairs(ffp) do
            if e.lit and e.f ~= glow and e.f ~= dot then e.f.BackgroundTransparency = S.lit and 0.05 or 1 end
          end
        end
        dot.BackgroundTransparency = nv and 0.5 or 0.08
        glow.BackgroundTransparency = nv and 0.94 or 0.82
      end
    else
      local s = Db * 0.84 * scale
      local Dd = Db * scale
      local split = math.floor(cx + eye.X + 0.5)
      clipL.Position, clipL.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(split, vs.Y)
      clipR.Position, clipR.Size = UDim2.fromOffset(split, 0), UDim2.fromOffset(vs.X - split, vs.Y)
      sizeAp(apL, Dd)
      sizeAp(apR, Dd)
      sz(tintL, Dd)
      sz(tintR, Dd)
      local ly, lx, rxx = cy + eye.Y, cx - s / 2 + eye.X, cx + s / 2 + eye.X - split
      at(apL.box, lx, ly)
      at(tintL, lx, ly)
      at(apR.box, rxx, ly)
      at(tintR, rxx, ly)
      -- 激光测距、方位（每 0.1 秒量一次）
      if t - S.lrfT > 0.1 then
        S.lrfT = t
        rayP.FilterDescendantsInstances = { me.Character, cam }
        local look = cam.CFrame.LookVector
        local res = workspace:Raycast(cam.CFrame.Position, look * 3000, rayP)
        local deg, dirName = bearing(look)
        local dist = res and string.format("%04d m", math.floor((res.Position - cam.CFrame.Position).Magnitude / 2.8 + 0.5)) or "---- m"
        lrfT.Text = string.format("%s   %03d° %s   %.0f×", dist, math.floor(deg + 0.5) % 360, dirName, zoom)
      end
      at(lrfT, cx, cy + Db * 0.36)
    end

    -- 杂散光：月亮在视野里时整块镜片泛白一点
    local m = moonOnScreen()
    local center = V2(cx, cy)
    local inten = 0
    if m then
      local r = (kind == "binoc") and Db * 0.95 or D * 0.5
      inten = math.clamp(1 - (m - center).Magnitude / r, 0, 1) ^ 1.5
    end
    tint.BackgroundTransparency = 0.93 - 0.05 * inten   -- 对着亮处，整块镜片泛白一点（杂散光）

    -- 告诉服务器：开着镜、朝哪看（别人那边画镜片闪光；步枪的 ACOG 不发）
    if kind ~= "acog" and t - S.sendT > 0.25 then
      local look = cam.CFrame.LookVector
      if not S.sentDir or look:Dot(S.sentDir) < 0.9997 then
        S.sendT, S.sentDir = t, look
        sendState(true)
      end
    end
  end

  -- 晃动加在镜头上：在 Roblox 镜头更新之后（Camera + 1），只加这一帧的增量（镜头下一帧从当前朝向接着算，加总量会越转越偏）；
  --   顺便量镜头转得多快（上一帧加完晃动之后 → 这一帧镜头更新完），给出瞳偏移用
  RunService:BindToRenderStep("ScopeSway", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not S.kind then
      S.prev, S.appP, S.appY = nil, 0, 0
      return
    end
    local cf = cam.CFrame
    if S.prev and dt > 0 then
      local lv = S.prev:ToObjectSpace(cf).LookVector
      local yaw = math.atan2(-lv.X, -lv.Z)
      local pitch = math.asin(math.clamp(lv.Y, -1, 1))
      S.ang = S.ang:Lerp(V2(-yaw / dt, pitch / dt), math.min(1, dt * 18))
    end
    local dp, dy = S.swayP - S.appP, S.swayY - S.appY
    S.appP, S.appY = S.swayP, S.swayY
    cam.CFrame = cf * CFrame.Angles(dp, dy, 0)
    S.prev = cam.CFrame
  end)

  UIS.InputChanged:Connect(function(io)
    if S.kind and io.UserInputType == Enum.UserInputType.MouseWheel then changeZoom(io.Position.Z > 0 and 1 or -1) end
  end)
  if zin then
    zin.Activated:Connect(function() changeZoom(1) end)
    zout.Activated:Connect(function() changeZoom(-1) end)
  end
  cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if S.kind then layout(S.kind) end end)

  ---------------------------------------------------------------- 别人的镜片闪光

  local glints = {}   -- [Player] = { bb, core, halo, h, v }
  local function makeGlint(head)
    local bb = Instance.new("BillboardGui")
    bb.Name = "ScopeGlint"
    bb.Size = UDim2.fromOffset(110, 110)
    bb.LightInfluence = 0
    bb.Brightness = 5
    bb.AlwaysOnTop = false   -- 墙挡得住
    bb.MaxDistance = 3000
    bb.Adornee = head
    local function g(w, h, color, isRound)
      local f = Instance.new("Frame")
      f.AnchorPoint = V2(0.5, 0.5)
      f.Position = UDim2.fromScale(0.5, 0.5)
      f.Size = UDim2.fromOffset(w, h)
      f.BackgroundColor3 = color
      f.BorderSizePixel = 0
      f.BackgroundTransparency = 1
      f.Parent = bb
      if isRound then round(f) end
      return f
    end
    local G2 = { bb = bb }
    G2.halo = g(36, 36, RGB(205, 228, 255), true)
    G2.h = g(110, 2, RGB(235, 244, 255))
    grad(G2.h, 0, { { 0, 1 }, { 0.5, 0 }, { 1, 1 } })
    G2.v = g(2, 64, RGB(235, 244, 255))
    grad(G2.v, 90, { { 0, 1 }, { 0.5, 0 }, { 1, 1 } })
    G2.core = g(9, 9, RGB(255, 255, 255), true)
    bb.Parent = head
    return G2
  end
  local glintScan = 0
  G.frameConn("Scope", function(dt)
    local t = now()
    if t - glintScan > 0.25 then   -- 每 0.25 秒看一遍谁开着镜
      glintScan = t
      local side = me:GetAttribute("Side")
      for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        local head = ch and ch:FindFirstChild("Head")
        local want = pl ~= me and head ~= nil and ch:GetAttribute("Scoped") == true and pl:GetAttribute("Side") ~= side
        local gl = glints[pl]
        if want and (not gl or gl.bb.Parent ~= head) then
          if gl then gl.bb:Destroy() end
          glints[pl] = makeGlint(head)
        elseif not want and gl then
          gl.bb:Destroy()
          glints[pl] = nil
        end
      end
    end
    local eyeP = cam.CFrame.Position
    for pl, gl in pairs(glints) do
      local ch = pl.Character
      local head = gl.bb.Adornee
      if not ch or not head or not head.Parent then
        gl.bb:Destroy()
        glints[pl] = nil
      else
        local dir = ch:GetAttribute("ScopeDir")
        if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 then dir = head.CFrame.LookVector end
        dir = dir.Unit
        local to = eyeP - head.Position
        local dist = to.Magnitude
        local c = (dist > 1) and dir:Dot(to / dist) or 0
        local i = math.clamp((c - 0.94) / 0.06, 0, 1) ^ 2   -- 20° 以内开始闪，正对着最亮
        i *= 0.75 + 0.25 * math.sin(t * 19 + pl.UserId % 7)
        if dist < 25 then i = 0 end
        gl.bb.Enabled = i > 0.02
        gl.bb.StudsOffsetWorldSpace = dir * 1.15 + Vector3.new(0, 0.12, 0)
        gl.core.BackgroundTransparency = 1 - 0.95 * i
        gl.halo.BackgroundTransparency = 1 - 0.45 * i
        gl.h.BackgroundTransparency = 1 - 0.8 * i
        gl.v.BackgroundTransparency = 1 - 0.55 * i
      end
    end
  end)
  Players.PlayerRemoving:Connect(function(pl)
    if glints[pl] then glints[pl].bb:Destroy() glints[pl] = nil end
  end)
end

return Scope
