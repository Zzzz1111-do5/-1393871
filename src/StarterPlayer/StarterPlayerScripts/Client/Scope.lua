-- Roblox全面大战场——瞄准镜（客户端）：狙击镜、ACOG、望远镜开镜后的光学效果
--   使命召唤式（用户 11-21：瞄准镜照使命召唤做，镜子是圆形的不是多边形）：第一人称开镜时镜身（真模型）一直看得见——FPSView 把镜筒里面
--     挡着视线的块藏掉，从目镜那个正圆的洞里看到放大的画面（两具 ACOG 原模型的目镜是八边形，optics.json 的 ring 补了正圆的目镜圈罩住）；
--     镜头视角按倍率收窄，镜子跟着往远推、在屏幕上一样大。这里只画镜片上的东西，跟着 3D 目镜走
--     （FPSView 每帧 G.scopeLensAt(屏幕 x, y, 半径, 举镜进度, 狙击镜?)），全是正圆：
--     镜片（CanvasGroup + UICorner 按圆裁剪）：透光稍暗一点、分划（在屏幕正中：子弹打这儿）、边上自然变暗、眼盒阴影（11-21 去掉了反光弧、色散彩边圈：太假）；
--       眼盒阴影：眼睛不在光轴上（枪晃、镜头转得快、走路、开枪、刚贴上目镜）时镜片边上一道月牙——两个圆叠着：A 是目镜（镜片的圆），
--       B 是镜子另一头的光阑（外面一圈特别粗的黑描边）；对正时 B 比 A 大一圈、看不见，偏了 B 朝反方向错开，A 里没被 B 盖住的那块就是月牙
--     镜片外面一圈圈往外渐暗（目镜圈、镜身、外面的世界压暗，视线集中在镜片里；狙击镜压得很黑）；近处的镜身用景深糊掉（ScopeDOF，
--     同使命召唤开镜时枪身是糊的）；跟着举镜进度淡入、松开右键跟着淡出；不是第一人称（没有 3D 镜身）时镜片摆在屏幕正中、外面几乎全黑
--   边缘渐暗：一圈圈半透明黑描边（UI 没有径向渐变），圈和圈挨着不叠
--   分划：狙击镜在第一焦平面（刻线跟倍率一起放大缩小，1 密位在目标上永远是 1 米 / 千米），中心红点夜里发光（开着夜视仪时调暗）；
--     ACOG（步枪上的 3.5 倍、改枪的 6 倍）是 TA31 的红色箭形 + 测距线（第二焦平面：大小按目镜直径），定倍、不屏息、不闪镜片
--   望远镜：两个圆并排（左右各按半边屏幕裁开，正好是两圆的并集，中间上下两个尖角）、测距框和密位刻度，底下一行琥珀色的距离 / 方位 / 倍率；
--     开镜先黑一下、出瞳由小变大、对焦
--   手稳：呼吸晃，按住 Shift 屏住（稳几秒，憋过头晃得更厉害、一会儿屏不了），走动晃得多；晃动加在镜头上（子弹照样打屏幕正中），
--     倍率高时鼠标灵敏度跟着降；滚轮变倍（狙击镜、望远镜）
--   别人开着镜对着你（他的视线在你附近 20° 以内）时他的镜片闪光：服务器只记 Scoped / ScopeDir 两个属性，闪光是看的人本地画的、墙挡得住
--   镜内单独放大（用户 11-21：「改成镜内单独放大」）：第一人称、画中画准备好了（ScopePip.lua）时，镜外只是普通开镜（约 1.25 倍）、不放大，
--     镜片那个圆里是 ScopePip 另画的放大的战场（镜头朝准星看），分划画在镜片正中；每次举镜时定下用哪种（G.scopePipMode），举到一半不换。
--     画中画用不了（EditableMesh 没开、地形网格还没生成好）时照旧整屏放大
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
  --   band 渐暗带占直径的比例，k 最外一圈的不透明度，pw 往里衰减的指数；bare 不要外面那圈黑（镜片里的暗边：圆外本来就裁掉了）
  local function aperture(parent, z, n, band, k, pw, bare)
    local box = fr(parent, z, BLACK, 1)
    if not bare then
      local mask = round(fr(box, z, BLACK, 1))
      mask.Position, mask.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
      ring(mask, 3200, BLACK, 0)
    end
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

  ---------------------------------------------------------------- 镜片（狙击镜、ACOG）：CanvasGroup 按圆裁剪，里面的分划、月牙、彩边出不了这个正圆
  --   层（从下往上）：镀膜 → 分划 → 反光弧 → 眼盒阴影 B → 边上的暗边 A → 色散彩边

  if G.pipAttach then G.pipAttach(root) end   -- 画中画（ScopePip.lua）：镜片底下那个圆里画放大的战场
  local lensG = nil
  pcall(function() lensG = Instance.new("CanvasGroup") end)
  local isCG = lensG ~= nil
  if not lensG then   -- 没有 CanvasGroup：普通 Frame 按方框裁（四个角上的刻线由外面那圈压暗挡住）
    lensG = Instance.new("Frame")
    lensG.ClipsDescendants = true
  end
  lensG.Name = "ScopeLens"
  lensG.AnchorPoint = V2(0.5, 0.5)
  lensG.BackgroundTransparency = 1
  lensG.BorderSizePixel = 0
  lensG.ZIndex = 2   -- 盖在画中画上面（镀膜、分划、暗边都是半透明的）
  lensG.Visible = false
  lensG.Parent = root
  round(lensG)
  -- 透光：镜子透光九成多，像比外面稍暗一点（中性色，不偏蓝——用户 11-21：镜片效果太假）
  local tint = round(fr(lensG, 1, RGB(6, 7, 8), 0.94))
  tint.Position, tint.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)

  -- 分划：容器（大小 0）摆在屏幕正中在镜片里的位置，零件按容器中心摆
  local ret = fr(lensG, 2, BLACK, 1)       -- 狙击镜（第一焦平面）
  ret.Name = "ScopeRet"
  local acogRet = fr(lensG, 2, BLACK, 1)   -- ACOG
  acogRet.Name = "AcogRet"
  local retB = fr(root, 2, BLACK, 1)       -- 望远镜（在镜筒的黑圈下面）
  sz(ret, 0)
  sz(acogRet, 0)
  sz(retB, 0)
  local RC = RGB(6, 6, 6)            -- 刻线
  local RED = RGB(255, 46, 30)       -- 发光的中心
  local AMB = RGB(255, 160, 52)      -- 望远镜的琥珀色读数
  local RCI = RGB(150, 26, 18)       -- 照明分划：暗红（夜里能看清，不刺眼）
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
  -- 步枪上的 ACOG（Trijicon TA31 的箭形分划，第二焦平面：大小按目镜直径的比例，不随倍率变）：中心一个红色发光的箭形（尖是瞄准点），
  --   下面一根细竖线挂着 400～800 米的测距横线（越远越短，正好是人肩宽），左右各一段横线（不到中心）
  local acog = {}   -- { f, x, y, w, h（直径的比例；负数是像素），lit 发光的、a0 原来的透明度 }
  local function ae(x, y, w, h, color, alpha, rot, lit)
    local f = fr(acogRet, 2, color or RC, alpha or 0)
    if rot then f.Rotation = rot end
    table.insert(acog, { f = f, x = x, y = y, w = w, h = h, lit = lit, a0 = alpha or 0 })
    return f
  end
  do
    local CH, CA = 0.05, 50   -- 箭形每边多长（直径的比例）、和竖直方向的夹角（度）
    local sa, ca = math.sin(math.rad(CA)), math.cos(math.rad(CA))
    local CR = RGB(255, 52, 36)
    for _, k in ipairs({ { -10, 1.16, 0.84 }, { -4, 1, 0.02 } }) do   -- 先画一圈晕光、再画箭形本身
      ae(CH * 0.5 * sa, CH * 0.5 * ca, k[1], CH * k[2], CR, k[3], -CA, true)
      ae(-CH * 0.5 * sa, CH * 0.5 * ca, k[1], CH * k[2], CR, k[3], CA, true)
    end
    local y0, y1 = CH * ca + 0.012, 0.2
    ae(0, (y0 + y1) / 2, -1, y1 - y0, RC, 0.1)
    for _, v in ipairs({ { 0.08, 0.05 }, { 0.11, 0.041 }, { 0.14, 0.034 }, { 0.17, 0.028 }, { 0.2, 0.023 } }) do ae(0, v[1], v[2], -2, RC, 0.08) end
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
  -- 望远镜：测距框（四个角）、中心小十字（中间空着）、下面一条密位刻度
  local retParts = {}   -- { f, x, y, w, h（直径的比例；w / h 小于 0 是像素数） }
  local function rp(x, y, w, h, color, alpha)
    local f = fr(retB, 2, color, alpha)
    table.insert(retParts, { f = f, x = x, y = y, w = w, h = h })
    return f
  end
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    rp(c[1] * 0.04 - c[1] * 0.008, c[2] * 0.04, 0.016, -1, AMB, 0.12)
    rp(c[1] * 0.04, c[2] * 0.04 - c[2] * 0.008, -1, 0.016, AMB, 0.12)
  end
  for _, c in ipairs({ { -0.013, 0, 0.012, -1 }, { 0.013, 0, 0.012, -1 }, { 0, -0.013, -1, 0.012 }, { 0, 0.013, -1, 0.012 } }) do
    rp(c[1], c[2], c[3], c[4], AMB, 0.2)
  end
  rp(0, 0.1, 0.4, -1, AMB, 0.45)
  for k = -10, 10 do
    local big = k % 5 == 0
    rp(k * 0.02, 0.1 - (big and 0.012 or 0.006), -1, big and 0.024 or 0.012, AMB, big and 0.3 or 0.5)
  end
  local function layoutRet(D)   -- 望远镜的刻线（按直径的比例）
    local t1 = math.max(1, math.floor(D / 700 + 0.5))
    for _, p in ipairs(retParts) do
      local px = function(v) if v >= 0 then return math.max(1, math.floor(v * D + 0.5)) end return t1 end
      sz(p.f, px(p.w), px(p.h))
      at(p.f, math.floor(p.x * D + 0.5), math.floor(p.y * D + 0.5))
    end
  end

  -- 只留真瞄准镜里看得到的（用户 11-21：镜片效果太假——原来的反光弧、红蓝色散彩边圈、偏蓝的镀膜都是假的，去掉）：
  --   眼盒阴影 B（光阑：对正时比镜片大一圈、看不见，眼睛偏了往反方向错开、边上露出一道软的月牙）、镜片边上自然变暗 A（越靠边越暗，很缓）
  local apB = aperture(lensG, 4, 10, 0.09, 0.92, 1.5)
  local apA = aperture(lensG, 5, 10, 0.1, 0.55, 1.8, true)

  -- 镜片外面：贴着镜片一圈羽化（OUT_F 圈，落在黑色的目镜圈上，圈和圈之间的接缝看不出来），再往外一圈特别粗的描边整片均匀压暗
  --   （使命召唤那样；分好几级往外渐暗的话，天空上看得出一圈圈台阶）
  local OUT_F = 7
  local outer = {}
  for i = 1, OUT_F + 1 do
    local f = round(fr(root, 6, BLACK, 1))
    f.Name = "ScopeOuter"
    f.Visible = false
    outer[i] = { f = f, s = ring(f, 1, BLACK, 1) }
  end
  -- 外面压多暗：{ 不透明度, 羽化带宽（屏高的比例） }
  local OUTK = {
    sniper = { 0.8, 0.04 },    -- 狙击镜：目镜圈、镜身压得很黑
    acog = { 0.34, 0.045 },    -- ACOG：还看得清目镜圈、镜身和两边的战场
    flat = { 0.95, 0.02 },     -- 没有 3D 镜身（第三人称、视图模型还没建好）：外面几乎全黑，像老式的镜筒
    pipSniper = { 0.3, 0.05 },  -- 画中画：镜外是不放大的战场（普通开镜），只轻轻压暗（压重了像蒙了一层黑纱）
    pipAcog = { 0.1, 0.05 },
  }

  -- 望远镜：左右两个（各在半边屏幕的裁剪框里）
  local clipL = fr(root, 5, BLACK, 1)
  clipL.AnchorPoint, clipL.ClipsDescendants = V2(0, 0), true
  local clipR = fr(root, 5, BLACK, 1)
  clipR.AnchorPoint, clipR.ClipsDescendants = V2(0, 0), true
  local apL = aperture(clipL, 5, 10, 0.09, 0.93, 2.0)
  local apR = aperture(clipR, 5, 10, 0.09, 0.93, 2.0)
  local tintL = round(fr(clipL, 4, RGB(40, 34, 18), 0.94))   -- 望远镜的镀膜偏暖
  local tintR = round(fr(clipR, 4, RGB(40, 34, 18), 0.94))

  -- 望远镜开镜时黑一下
  local blackout = fr(root, 8, BLACK, 1)
  blackout.AnchorPoint, blackout.Size = V2(0, 0), UDim2.fromScale(1, 1)

  -- 读数：狙击镜在镜片左边的暗处写倍率、下面一条屏息条；望远镜在视野底部写距离 · 方位 · 倍率（琥珀色）
  local function txt(z, size, color)
    local l = Instance.new("TextLabel")
    l.AnchorPoint = V2(0.5, 0.5)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.RobotoMono
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

  ---------------------------------------------------------------- 本地画面效果：变倍 / 望远镜对焦的模糊、镜片调色、近处镜身的景深

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
  -- 景深：3 格以内（镜头前的枪、镜身、目镜圈）糊掉，远处的战场（从目镜的洞里看到的）清楚
  local dof = nil
  pcall(function()
    local d = Instance.new("DepthOfFieldEffect")
    d.Name = "ScopeDOF"
    d.FocusDistance, d.InFocusRadius, d.NearIntensity, d.FarIntensity = 40, 37, 0, 0
    d.Enabled = false
    d.Parent = Lighting
    dof = d
  end)

  ---------------------------------------------------------------- 状态

  local KINDS = {
    sniper = { zooms = { 7, 10, 14, 20, 27, 35 }, sway = 0.0017, def = 10, k = 0.9 },   -- 这具 ATACR 是 7–35 倍；k 没有 3D 镜身时镜片占屏高
    acog = { zooms = { 3.5 }, sway = 0.0008, def = 3.5, k = 0.56 },   -- 步枪上的 ACOG：定倍（3.5 / 6），倍率低、晃得少
    binoc = { zooms = { 4, 6, 8, 10 }, sway = 0.0011, def = 8 },
  }
  local S = {
    kind = nil, t0 = 0, zi = {}, eye = V2(), eyeV = V2(), ang = V2(), breath = 1, hold = false, tired = 0,
    swayP = 0, swayY = 0, appP = 0, appY = 0, prev = nil, vs = V2(), blurK = 0, sens = nil, sendT = 0, sentDir = nil,
    lrfT = 0, phase = 0,
  }
  -- 镜片那一层：x, y 圆心、r 半径（像素），f 淡入（0～1），lk 分划（"sniper" / "acog"），fp 有 3D 镜身（第一人称），fpT 上次报目镜位置的时刻
  --   pip 这一次举镜用不用画中画（开始举时定下来，放下才清掉：举到一半不换）、Z 倍率
  local L = { x = 0, y = 0, r = 0, f = 0, lk = nil, fp = false, fpT = -1, shown = false, rA = -1, pip = nil, Z = 3.5 }
  G.scopeOn = false

  local function kindOf(w)
    if w and w.kind == "spot" then return "binoc" end
    if w and (w.optic == "acog" or w.optic == "acog6") then return "acog" end   -- 改枪的 6 倍 ACOG 也是这一套（倍率按武器表）
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
    if kind == "acog" then return (w and w.scope) or 3.5 end   -- 定倍：3.5 / 6（改枪选的瞄具）
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

  -- 开着镜（或者镜片那一层还在淡出）才开着这个界面、调色
  local function refresh()
    local on = S.kind ~= nil or L.shown
    if gui.Enabled ~= on then gui.Enabled = on end
    if cc.Enabled ~= on then cc.Enabled = on end
  end

  -- 镜片外面一圈圈压暗：圆心 (x, y)、镜片半径 r、淡入 f、prof = OUTK 的一种
  local function layoutOuter(x, y, r, f, prof)
    local vs = cam.ViewportSize
    local a1 = prof[1]
    local fw = math.max(4, prof[2] * vs.Y)
    local far = 0   -- 圆心到最远的屏幕角
    for _, c in ipairs({ V2(0, 0), V2(vs.X, 0), V2(0, vs.Y), V2(vs.X, vs.Y) }) do far = math.max(far, (c - V2(x, y)).Magnitude) end
    local function put(i, r0, r1, a)   -- 第 i 圈：半径 r0～r1、不透明度 a（半径取整，圈和圈正好接上）
      local o = outer[i]
      local d0 = math.floor(r0 + 0.5)
      sz(o.f, 2 * d0)
      at(o.f, x, y)
      o.s.Thickness = math.max(1, math.floor(r1 + 0.5) - d0)
      o.s.Transparency = 1 - a * f
    end
    for k = 1, OUT_F do
      local u = (k - 0.5) / OUT_F
      put(k, r + fw * (k - 1) / OUT_F, r + fw * k / OUT_F, a1 * u * u * (3 - 2 * u))
    end
    put(OUT_F + 1, r + fw, math.max(far, r + fw) + 400, a1)   -- 一直盖到最远的屏幕角外面
  end

  local function hideLens()
    if G.pipHide then G.pipHide() end
    if not L.shown then return end
    L.shown = false
    lensG.Visible = false
    for _, o in ipairs(outer) do o.f.Visible = false end
    if dof then dof.Enabled = false end
  end

  -- 镜片那一层摆到 L 记的位置（第一人称：FPSView 报的目镜；不然屏幕正中）
  local function drawLens()
    local f = L.f
    if f <= 0.002 or L.r < 4 then
      hideLens()
      refresh()
      return
    end
    local vs = cam.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    local x, y = L.x, L.y
    local r = math.floor(L.r + 0.5)
    if not L.shown then
      L.shown = true
      lensG.Visible = true
      for _, o in ipairs(outer) do o.f.Visible = true end
    end
    sz(lensG, 2 * r)
    at(lensG, x, y)
    if isCG then lensG.GroupTransparency = 1 - f end
    local lk = L.lk
    ret.Visible, acogRet.Visible = lk == "sniper", lk == "acog"
    local pip = L.fp and L.pip == true and G.pipStep ~= nil
    local rx, ry, fpx
    if pip then
      -- 画中画（镜内单独放大）：镜里那个圆是 ScopePip 另画的放大的战场，它的镜头朝准星看——分划在镜片正中就是子弹打的地方
      rx, ry = r, r
      fpx = G.pipStep(x, y, r, L.Z, f)
    else
      -- 整屏放大：分划在屏幕正中（子弹打这儿），镜片晃的时候分划不跟着晃，偏多了就是眼盒没对正
      if G.pipHide then G.pipHide() end
      rx, ry = cx - x + r, cy - y + r
      fpx = cy / math.tan(math.rad(cam.FieldOfView) / 2)
    end
    if lk == "acog" then
      at(acogRet, rx, ry)
      if L.rA ~= r then L.rA = r layoutAcog(2 * r) end
    else
      at(ret, rx, ry)
      layoutFfp(0.001 * fpx)   -- 第一焦平面：每密位的像素数 = 焦距（像素）× 0.001
    end
    -- 眼盒：目镜偏离屏幕中心（枪晃）+ 镜子相对眼睛的晃（S.eye：转得快、走路、开枪、刚贴上）；B 朝反方向错开
    local ev = V2(x - cx, y - cy)
    if S.kind then ev += S.eye end
    local e = ev * ((lk == "sniper") and 1.8 or 1.25)
    if e.Magnitude > 0.6 * r then e = e.Unit * 0.6 * r end
    sizeAp(apB, 2 * r * 1.08)
    at(apB.box, r - e.X, r - e.Y)
    sizeAp(apA, 2 * r)
    at(apA.box, r, r)
    -- 镜片外面
    layoutOuter(x, y, r, f, OUTK[(not L.fp) and "flat" or (pip and ((lk == "sniper") and "pipSniper" or "pipAcog")) or lk])
    -- 调色、景深跟着淡入
    cc.Contrast, cc.Saturation, cc.Brightness = 0.07 * f, 0.08 * f, 0.015 * f
    if dof then
      dof.Enabled = L.fp
      -- 镜身糊一点（画中画时轻一点：镜身就在眼前、清清楚楚的金属才像真的，糊成一团反而假）
      dof.NearIntensity = (pip and ((lk == "sniper") and 0.3 or 0.2) or ((lk == "sniper") and 0.6 or 0.45)) * f
    end
    refresh()
  end

  -- FPSView 每帧报目镜在屏幕上的位置（第一人称、拿着带瞄准镜的枪时）：举到一半开始淡入，举好时满
  function G.scopeLensAt(x, y, r, ads, sniper)
    if ads < 0.02 then L.pip = nil
    elseif L.pip == nil then L.pip = (G.pipReady ~= nil and G.pipReady()) or false end
    local f = math.clamp((ads - 0.45) / 0.2, 0, 1)
    L.x, L.y, L.r, L.f = x, y, r, f * f * (3 - 2 * f)
    L.lk, L.fp, L.fpT = sniper and "sniper" or "acog", true, now()
    drawLens()
  end

  -- 这一次开镜用不用画中画（Play 的视角、FPSView 的目镜大小跟着它）：举镜时定下的；还没举就看画中画准备好了没有
  function G.scopePipMode()
    if L.pip ~= nil then return L.pip end
    return (G.pipReady ~= nil and G.pipReady()) or false
  end

  local D0, Db = 0, 0   -- 没有 3D 镜身时镜片的直径、望远镜每个圆的直径（像素）
  local function layout(kind)
    local vs = cam.ViewportSize
    S.vs = vs
    D0 = math.min(vs.X, vs.Y) * (KINDS[kind].k or 0.9)
    Db = math.min(vs.Y * 0.86, vs.X * 0.5)
    local binoc = kind == "binoc"
    retB.Visible = binoc
    if binoc then
      layoutRet(Db * 1.1)
      at(retB, vs.X / 2, vs.Y / 2)
      sz(retB, 0)
    end
    clipL.Visible, clipR.Visible = binoc, binoc
    sizeAp(apL, Db)
    sizeAp(apR, Db)
    sz(tintL, Db)
    sz(tintR, Db)
    zoomT.TextSize = math.max(14, math.floor(vs.Y / 52))
    lrfT.TextSize = math.max(14, math.floor(Db / 40))
    zoomT.Visible, breathBg.Visible = kind == "sniper", kind == "sniper"   -- ACOG 是定倍的、也不用屏息
    lrfT.Visible = binoc
    if zin then zin.Visible, zout.Visible = kind ~= "acog", kind ~= "acog" end
  end

  local function sendState(on)
    pcall(function() G.R.Act:FireServer("scope", on, on and cam.CFrame.LookVector or nil) end)
  end

  local function enter(kind)
    S.kind = kind
    S.t0 = now()
    G.scopeOn = true
    layout(kind)
    local vs = cam.ViewportSize
    S.eye = V2(0, (kind == "binoc") and Db * 0.16 or vs.Y * 0.035)   -- 刚贴上目镜：月牙从下面进来
    S.eyeV = V2()
    S.blurK = 0
    S.prev, S.lastP = nil, nil
    blackout.Visible = kind == "binoc"
    if kind == "binoc" then cc.Contrast, cc.Saturation, cc.Brightness = 0.07, 0.08, 0.015 end
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
    refresh()
  end

  local function exit()
    local was = S.kind
    S.kind = nil
    G.scopeOn = false
    blur.Enabled = false
    blur.Size = 0
    clipL.Visible, clipR.Visible, retB.Visible, blackout.Visible = false, false, false, false
    zoomT.Visible, breathBg.Visible, lrfT.Visible = false, false, false
    if zin then zin.Visible, zout.Visible = false, false end
    if not L.fp then L.f = 0 drawLens() end   -- 没有 3D 镜身的镜片一起收掉（第一人称的跟着举镜进度淡出）
    if G.mapRoot then G.mapRoot.Visible = true end
    S.hold = false
    if S.sens then
      local v = S.sens
      pcall(function() UIS.MouseDeltaSensitivity = v end)
      S.sens = nil
    end
    pcall(function() CAS:UnbindAction("ScopeHoldBreath") end)
    if was ~= "acog" then sendState(false) end
    refresh()
  end

  function G.scopeFire()
    if not S.kind then return end
    local d = (S.kind == "binoc") and Db or math.max(40, 2 * L.r)
    S.eyeV += V2((math.random() - 0.5) * 0.5 * d, 2.2 * d)   -- 后坐：镜子往后往上一跳，月牙从下面闪一下
    if S.kind == "sniper" then S.blurK = math.max(S.blurK, 2.5) end
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
    if on and G.fpsOpticPending and G.fpsOpticPending() then on = false end   -- 第一人称还在把镜子举到眼前：举到了再算开着镜
    local kind = on and kindOf(w) or nil
    if kind ~= S.kind then
      if S.kind then exit() end
      if kind then enter(kind) end
    end
    local t = now()
    -- 第一人称不再报目镜位置（收枪、换枪、上车、死了）：镜片那一层收掉
    if L.fp and t - L.fpT > 0.15 then
      L.pip = nil
      if L.shown then
        L.f, L.fp = 0, false
        drawLens()
      end
    end
    if not kind then return end
    dt = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
    local vs = cam.ViewportSize
    if vs ~= S.vs then layout(kind) end
    local K = KINDS[kind]
    local zoom = G.scopeZoom(w)
    L.Z = zoom   -- 画中画的倍率（放下镜子淡出时还用这个）
    local cx, cy = vs.X / 2, vs.Y / 2
    local lensKind = kind == "sniper" or kind == "acog"
    -- 没有 3D 镜身（第三人称、视图模型还没建好）：镜片摆在屏幕正中，开镜后 0.15 秒淡入
    if lensKind and t - L.fpT > 0.15 then
      L.x, L.y, L.r, L.lk, L.fp = cx, cy, D0 / 2, kind, false
      L.f = math.clamp((t - S.t0) / 0.15, 0, 1)
      drawLens()
    end
    local d = (kind == "binoc") and Db or math.max(40, 2 * L.r)

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
    -- 改枪：据枪稳定性（w.swayK）；倍率高的 ACOG 晃得明显一些
    local amp = K.sway * (1 + move * 2.5) * ((w and w.swayK) or 1) * ((kind == "acog") and math.sqrt(zoom / 3.5) or 1)
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

    -- 镜子相对眼睛的偏移（弹簧）：镜头转得快 → 落后；走路一颠一颠；呼吸带一点（第一人称时枪本身也在晃，这里只补一点）
    S.phase += dt * spd * 0.55
    local target = V2(-S.ang.X, S.ang.Y) * ((kind == "binoc") and 0.05 or 0.025) * d
      + V2(math.sin(S.phase) * 0.045 * d * move, math.abs(math.cos(S.phase)) * 0.03 * d * move)
      + V2(S.swayY, -S.swayP) * 6 * d
    S.eyeV += ((target - S.eye) * 150 - S.eyeV * 19) * dt
    S.eye += S.eyeV * dt
    if S.eye.Magnitude > 0.24 * d then S.eye = S.eye.Unit * 0.24 * d end
    local eye = S.eye

    -- 模糊：变倍、狙击枪开枪时糊一下；望远镜开镜时先黑一下、出瞳由小变大、对焦
    S.blurK = math.max(0, S.blurK - dt * 22)
    local focus = 0
    if kind == "binoc" then
      blackout.BackgroundTransparency = math.clamp((t - S.t0 - 0.04) / 0.13, 0, 1)
      focus = (1 - math.clamp((t - S.t0) / 0.34, 0, 1)) ^ 2 * 16
    end
    blur.Size = math.max(focus, S.blurK)
    blur.Enabled = blur.Size > 0.05
    -- 鼠标灵敏度随倍率降（高倍时拖一下不会甩出去好远）
    if S.sens then
      local v = S.sens * (1 / zoom) ^ 0.85
      if UIS.MouseDeltaSensitivity ~= v then pcall(function() UIS.MouseDeltaSensitivity = v end) end
    end

    if lensKind then
      if kind == "acog" then
        -- 箭形照明：夜里亮（光纤 + 氚光），开着夜视仪调暗
        local nv = G.nvgOn and G.nvgOn()
        for _, e in ipairs(acog) do
          if e.lit then e.f.BackgroundTransparency = nv and math.min(0.92, e.a0 + 0.45) or e.a0 end
        end
      else
        -- 倍率、屏息条（镜片左边的暗处；右下角是小地图）
        local rx = math.max(40, L.x - L.r - 46)
        zoomT.Text = string.format("%.1f×", zoom)
        at(zoomT, rx, L.y + L.r * 0.6)
        sz(breathBg, 3, math.floor(L.r * 0.24))
        at(breathBg, rx, L.y + L.r * 0.76)
        breathFill.Size = UDim2.new(1, 0, math.clamp(S.breath, 0, 1), 0)
        breathFill.BackgroundColor3 = (S.tired > 0) and RGB(220, 90, 70) or RGB(200, 206, 200)
        breathBg.BackgroundTransparency = (S.breath >= 1 and not S.hold) and 0.75 or 0.35
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
      if zin then   -- 手机：变倍按钮在镜片左边（右边是开火键、小地图）
        local bx = math.max(36, L.x - L.r - 40)
        at(zin, bx, cy - 78)
        at(zout, bx, cy - 24)
      end
      -- 杂散光：月亮在镜片里时整块镜片泛白一点
      local mo = moonOnScreen()
      local inten = 0
      if mo and L.r > 1 then inten = math.clamp(1 - (mo - V2(L.x, L.y)).Magnitude / L.r, 0, 1) ^ 1.5 end
      tint.BackgroundTransparency = 0.94 - 0.04 * inten
    else
      local k = math.clamp((t - S.t0) / 0.24, 0, 1)
      local sc = 0.8 + 0.2 * (1 - (1 - k) ^ 3)   -- 出瞳由小变大
      local s, Dd = Db * 0.84 * sc, Db * sc
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
      if zin then
        local bx = math.max(36, cx - Db * 0.55 - 40)
        at(zin, bx, cy - 78)
        at(zout, bx, cy - 24)
      end
      -- 激光测距、方位（每 0.1 秒量一次）
      if t - S.lrfT > 0.1 then
        S.lrfT = t
        rayP.FilterDescendantsInstances = { me.Character, cam }
        local look = cam.CFrame.LookVector
        local res = G.rayFar(cam.CFrame.Position, look * 3000, rayP, true)   -- 激光测距：没加载的远处地形按地形高度算（Stream.lua）
        local deg, dirName = bearing(look)
        local dist = res and string.format("%04d m", math.floor((res.Position - cam.CFrame.Position).Magnitude / 2.8 + 0.5)) or "---- m"
        lrfT.Text = string.format("%s   %03d° %s   %.0f×", dist, math.floor(deg + 0.5) % 360, dirName, zoom)
      end
      at(lrfT, cx, cy + Db * 0.36)
    end

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
  --   顺便量镜头转得多快（上一帧加完晃动之后 → 这一帧镜头更新完），给眼盒阴影用
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
