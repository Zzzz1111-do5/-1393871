-- Roblox全面大战场（客户端）——遥控无人机的战术平板（用户：无人机驾驶应该是用一个战术平板）
--   开无人机时（Fly.lua：st.uav）人站在原地端着平板（服务器 Air.lua 摆胳膊、焊平板零件，别人看得到这个人在遥控），自己的画面就是这块平板：
--     四周一圈加固外壳（黑色玻璃边、两侧橡胶握条、前置摄像头、指示灯、硬键），屏幕里是无人机的画面——前视光电（默认）/ 外部视角（右键或 V），
--     Z 变焦 1× / 3× / 8×（滚轮细调）；屏幕上叠地面站的遥测：录像计时、数据链信号（卫通满格；视距的离得越远越弱，弱了画面出雪花）、
--     平板电量、时间、航向带、高度 / 速度 / 离操作员多远 / 瞄准点距离和坐标；
--     拿出平板：整屏先黑、外壳从下往上抬进画面，屏幕「建立数据链…」再出画面；收起：外壳往下落，露出身边的样子；操作员（自己）挨打时屏幕边一圈红闪
--   没在遥控时：自己放出去的无人机断了链路在天上盘旋（服务器 Loiter，75 秒）或停在地上 → 提示「按 T 重新连接无人机」（手机上点提示）
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Tablet = {}

function Tablet.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local UDs, UDo, UD = UDim2.fromScale, UDim2.fromOffset, UDim2.new
  local V2 = Vector2.new
  local function T(k, ...) return G.T(k, ...) end
  local mob = G.mobile == true
  local AL, AC, AR = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right

  -- 屏幕在画面里的位置（比例）；手机上外壳窄，留地方给触屏按钮
  local X0, Y0, X1, Y1 = 0.062, 0.07, 0.938, 0.872
  if mob then X0, Y0, X1, Y1 = 0.026, 0.035, 0.974, 0.955 end
  G.tabletRect = { X0, Y0, X1, Y1 }

  local gui = Instance.new("ScreenGui")
  gui.Name = "UavTablet"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.DisplayOrder = -1   -- 在主界面、驾驶平显下面：比分、小地图、平显照样盖在上面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

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
    c.CornerRadius = UDim.new(0, r)
    c.Parent = f
  end
  local function stroke(f, col, th, tr)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = col, th, tr or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end
  local function shade(f, a, b, rot)   -- 外壳的明暗（UIGradient 乘在底色上）
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(Color3.new(a, a, a), Color3.new(b, b, b))
    g.Rotation = rot
    g.Parent = f
  end
  local function fade(f, t0, t1, rot)   -- 渐隐（屏幕四边压暗）
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new(t0, t1)
    g.Rotation = rot
    g.Parent = f
  end
  local function txt(parent, text, pos, size, ts, col, font, ax, anchor)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position, l.Size = pos, size
    l.AnchorPoint = anchor or V2(0, 0)
    l.Text = text
    l.TextSize = ts
    l.TextColor3 = col
    l.Font = font or Enum.Font.RobotoMono
    l.TextXAlignment = ax or AL
    l.TextStrokeTransparency = 0.6
    l.TextStrokeColor3 = RGB(0, 0, 0)
    l.Parent = parent
    return l
  end

  ---------------------------------------------------------------- 外壳

  local statics = {}   -- 外壳上印的字：{ 标签, 文字编号 }（拿出平板时按当前语言重写）
  local black = fr(gui, UDs(0, 0), UDs(1, 1), RGB(0, 0, 0), 1)   -- 拿出来那一下整屏先黑（外壳还没抬到位，不露出无人机的画面）
  local root = fr(gui, UDs(0, 1), UDs(1, 1), RGB(0, 0, 0), 1)    -- 整块平板：拿出来 / 收起时整块上下滑
  local SHELL = RGB(52, 56, 50)
  local E = 0.004
  shade(fr(root, UDs(0, 0), UDs(1, Y0 + E), SHELL), 1.0, 0.82, 90)
  shade(fr(root, UDs(0, Y1 - E), UDs(1, 1 - Y1 + E), SHELL), 0.86, 0.6, 90)
  shade(fr(root, UDs(0, 0), UDs(X0 + E, 1), SHELL), 0.7, 0.95, 0)
  shade(fr(root, UDs(X1 - E, 0), UDs(1 - X1 + E, 1), SHELL), 0.95, 0.7, 0)
  -- 屏幕外一圈黑玻璃边：屏幕大小的透明框 + 圆角 + 粗描边（描边画在框外面，顺带把方角和圆角之间的缝填上）
  local glass = fr(root, UDs(X0, Y0), UDs(X1 - X0, Y1 - Y0), RGB(0, 0, 0), 1)
  corner(glass, mob and 10 or 16)
  stroke(glass, RGB(12, 14, 14), mob and 10 or 26)
  local edge = fr(root, UDs(X0, Y0), UDs(X1 - X0, Y1 - Y0), RGB(0, 0, 0), 1)   -- 显示区边上一道很细的反光
  corner(edge, mob and 10 or 16)
  stroke(edge, RGB(120, 130, 130), 1, 0.75)
  if not mob then
    -- 两侧橡胶握条（一道道横纹）
    for _, side in ipairs({ { 0.012, X0 - 0.024 }, { X1 + 0.012, 1 - X1 - 0.024 } }) do
      local g = fr(root, UDs(side[1], 0.3), UDs(side[2], 0.4), RGB(26, 28, 26))
      corner(g, 10)
      stroke(g, RGB(14, 15, 14), 1)
      for i = 1, 11 do fr(g, UDs(0.15, i / 12), UD(0.7, 0, 0, 2), RGB(44, 47, 44)) end
    end
    -- 顶边：前置摄像头、光线传感器、两个指示灯
    local lens = fr(root, UD(0.5, -7, Y0 * 0.5, -7), UDo(14, 14), RGB(6, 7, 9))
    corner(lens, 7)
    stroke(lens, RGB(70, 74, 70), 1.5)
    local glint = fr(lens, UDo(3, 3), UDo(4, 4), RGB(90, 120, 170))
    corner(glint, 2)
    corner(fr(root, UD(0.5, 22, Y0 * 0.5, -3), UDo(6, 6), RGB(10, 11, 12)), 3)
    G.tabletLeds = {}
    for i, name in ipairs({ "LINK", "PWR" }) do
      local x = (i == 1) and (X0 + 0.01) or (X1 - 0.05)
      local led = fr(root, UD(x, 0, Y0 * 0.5, -4), UDo(8, 8), RGB(80, 230, 110))
      corner(led, 4)
      txt(root, name, UD(x, 14, Y0 * 0.5, -7), UDo(60, 14), 11, RGB(150, 156, 150), Enum.Font.GothamMedium)
      G.tabletLeds[name] = led
    end
    -- 底边：牌子、四个硬键（键帽上印着键位）
    statics[#statics + 1] = { txt(root, "", UD(X0 + 0.004, 0, Y1 + (1 - Y1) * 0.18, 0), UDo(360, 18), 12, RGB(132, 138, 130), Enum.Font.GothamBold), "uav.brand" }
    local keys = { { "V", "uav.kCam" }, { "Z", "uav.kZoom" }, { "N", "uav.kNv" }, { "F", "uav.kExit" } }
    for i, kk in ipairs(keys) do
      local x = X1 - 0.004 - (#keys - i + 1) * 0.052
      local cap = fr(root, UD(x, 0, Y1 + (1 - Y1) * 0.16, 0), UDo(46, 22), RGB(28, 30, 28))
      corner(cap, 5)
      stroke(cap, RGB(78, 82, 76), 1)
      txt(cap, kk[1], UDs(0, 0), UDs(1, 1), 13, RGB(230, 232, 226), Enum.Font.GothamBold, AC).TextStrokeTransparency = 1
      statics[#statics + 1] = { txt(root, "", UD(x, 23, Y1 + (1 - Y1) * 0.16, 24), UDo(80, 14), 10, RGB(130, 136, 128), Enum.Font.GothamMedium, AC, V2(0.5, 0)), kk[2] }
    end
  end

  ---------------------------------------------------------------- 屏幕上的遥测

  local osd = fr(root, UDs(X0, Y0), UDs(X1 - X0, Y1 - Y0), RGB(0, 0, 0), 1)
  osd.ClipsDescendants = true
  -- 四边压暗一点（像小屏幕看画面）
  fade(fr(osd, UDs(0, 0), UDs(1, 0.14), RGB(0, 0, 0), 0.35), 0, 1, 90)
  fade(fr(osd, UDs(0, 0.86), UDs(1, 0.14), RGB(0, 0, 0), 0.35), 1, 0, 90)
  fade(fr(osd, UDs(0, 0), UDs(0.07, 1), RGB(0, 0, 0), 0.45), 0, 1, 0)
  fade(fr(osd, UDs(0.93, 0), UDs(0.07, 1), RGB(0, 0, 0), 0.45), 1, 0, 0)
  local WHITE, AMBER, RED = RGB(236, 240, 236), RGB(255, 206, 110), RGB(255, 84, 72)
  -- 顶上一条状态栏
  local bar = fr(osd, UDs(0, 0), UD(1, 0, 0, 26), RGB(0, 0, 0), 0.5)
  local recDot = fr(bar, UD(0, 10, 0.5, -5), UDo(10, 10), RED)
  corner(recDot, 5)
  local recText = txt(bar, "", UDo(26, 0), UD(0, 90, 1, 0), 14, WHITE)
  local linkText = txt(bar, "", UDo(114, 0), UD(0, 60, 1, 0), 14, WHITE)
  local sig = {}   -- 信号格：五根一根比一根高的竖条
  for i = 1, 5 do sig[i] = fr(bar, UD(0, 166 + (i - 1) * 6, 1, -5 - i * 2.4), UDo(4, i * 2.4), WHITE) end
  local linkType = txt(bar, "", UDo(202, 0), UD(0, 80, 1, 0), 14, WHITE)
  local title = txt(bar, "", UDs(0.5, 0), UD(0, 420, 1, 0), 14, WHITE, Enum.Font.GothamBold, AC, V2(0.5, 0))
  local batText = txt(bar, "", UD(1, -12, 0, 0), UD(0, 230, 1, 0), 14, WHITE, Enum.Font.RobotoMono, AR, V2(1, 0))
  -- 航向带：每 10° 一格，看得见左右 30°
  local tape = fr(osd, UD(0.5, 0, 0, 32), UD(0.4, 0, 0, 22), RGB(0, 0, 0), 0.65)
  tape.AnchorPoint = V2(0.5, 0)
  tape.ClipsDescendants = true
  local marks = {}
  local NAMES = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
  for i = 0, 35 do
    local a = i * 10
    local s = NAMES[a] or ((a % 30 == 0) and tostring(a // 10) or "·")
    marks[i] = txt(tape, s, UDs(0.5, 0.5), UDo(30, 20), (NAMES[a] and 15) or 13, NAMES[a] and AMBER or WHITE, Enum.Font.GothamBold, AC, V2(0.5, 0.5))
    marks[i].Visible = false
  end
  fr(tape, UD(0.5, -1, 0, 0), UD(0, 2, 0, 5), AMBER)
  local hdgText = txt(osd, "", UD(0.5, 0, 0, 56), UDo(70, 18), 14, AMBER, Enum.Font.RobotoMono, AC, V2(0.5, 0))
  -- 左下：遥测
  local tele = fr(osd, UD(0, 14, 1, -138), UDo(220, 120), RGB(0, 0, 0), 0.6)
  corner(tele, 6)
  local tl = {}
  for i = 1, 5 do tl[i] = txt(tele, "", UDo(10, 4 + (i - 1) * 22), UD(1, -16, 0, 20), 15, WHITE) end
  -- 右下：瞄准点坐标
  local aimBox = fr(osd, UD(1, -14, 1, -82), UDo(230, 64), RGB(0, 0, 0), 0.6)
  aimBox.AnchorPoint = V2(1, 0)
  corner(aimBox, 6)
  local al1 = txt(aimBox, "", UDo(10, 6), UD(1, -16, 0, 20), 15, AMBER)
  local al2 = txt(aimBox, "", UDo(10, 32), UD(1, -16, 0, 20), 15, WHITE)
  -- 前视光电的十字线（中间留空）、倍率
  local cross = {}
  for i, v in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    local w, h = (v[1] ~= 0) and 54 or 2, (v[2] ~= 0) and 54 or 2
    local f = fr(osd, UD(0.5, v[1] * (16 + 27) - w / 2, 0.5, v[2] * (16 + 27) - h / 2), UDo(w, h), WHITE, 0.15)
    stroke(f, RGB(0, 0, 0), 1, 0.45)
    cross[i] = f
  end
  local zoomText = txt(osd, "", UD(0.5, 64, 0.5, 40), UDo(80, 18), 15, WHITE)
  -- 信号弱：一条条横着的雪花
  local noise = {}
  for i = 1, 9 do
    local f = fr(osd, UDs(0, 0), UD(1, 0, 0, 3), RGB(255, 255, 255), 1)
    noise[i] = f
  end
  local weakText = txt(osd, "", UD(0.5, 0, 0, 80), UDo(300, 20), 16, AMBER, Enum.Font.GothamBold, AC, V2(0.5, 0))
  -- 操作员挨打：屏幕边一圈红闪 + 字
  local hurt = fr(osd, UDo(8, 8), UD(1, -16, 1, -16), RGB(0, 0, 0), 1)
  local hurtS = stroke(hurt, RED, 8, 1)
  local hurtText = txt(osd, "", UD(0.5, 0, 0, 104), UDo(420, 24), 18, RED, Enum.Font.GothamBold, AC, V2(0.5, 0))
  -- 开机：黑屏 + 「建立数据链…」+ 进度条
  local boot = fr(osd, UDs(0, 0), UDs(1, 1), RGB(4, 6, 6), 0)
  local bootT = txt(boot, "", UDs(0.5, 0.46), UDo(420, 24), 18, RGB(150, 230, 170), Enum.Font.RobotoMono, AC, V2(0.5, 0.5))
  local bootBg = fr(boot, UD(0.5, -130, 0.52, 0), UDo(260, 4), RGB(40, 60, 46))
  local bootBar = fr(bootBg, UDs(0, 0), UDs(0, 1), RGB(120, 230, 150))

  ---------------------------------------------------------------- 开、关、每帧

  local S = { open = false, t = 0, closeT = nil, st = nil, hp = nil, hurtT = -9, bat = nil, tool = nil }
  local RAISE, BOOT = 0.35, 0.9

  function G.tabletOpen(st)
    S.open, S.st, S.t, S.closeT = true, st, 0, nil
    S.bat = S.bat or math.random(76, 96)
    gui.Enabled = true
    root.Position = UDs(0, 1)
    black.BackgroundTransparency = 0
    boot.Visible, boot.BackgroundTransparency = true, 0
    bootT.TextTransparency = 0
    bootT.Text = T("uav.link")
    bootBar.BackgroundTransparency, bootBg.BackgroundTransparency = 0, 0
    for _, x in ipairs(statics) do x[1].Text = T(x[2]) end
    -- 枪收起来（两只手端着平板），收平板时再拿回来
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local tool = char and char:FindFirstChildOfClass("Tool")
    S.tool = tool
    if hum and tool then hum:UnequipTools() end
    S.hp = hum and hum.Health or nil
    S.hurtT = -9
  end
  function G.tabletClose()
    if not S.open then return end
    S.open, S.st, S.closeT = false, nil, 0
    local tool = S.tool
    S.tool = nil
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if tool and hum and hum.Health > 0 and tool.Parent and tool.Parent ~= char and not tool.Parent:IsA("Model") then hum:EquipTool(tool) end
  end
  G.tabletState = S

  local function fmtClock(s)
    s = math.max(0, math.floor(s))
    return string.format("%02d:%02d", s // 60, s % 60)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  local function stepOpen(dt)
    local st = S.st
    S.t += dt
    local t = S.t
    -- 抬进画面（先快后慢）；开机画面
    local k = math.clamp(t / RAISE, 0, 1)
    root.Position = UDs(0, (1 - k) * (1 - k) * 1.0)
    black.BackgroundTransparency = (k >= 1) and 1 or 0
    if t < RAISE + BOOT then
      local b = math.clamp((t - RAISE * 0.6) / BOOT, 0, 1)
      bootBar.Size = UDs(b, 1)
      boot.Visible, boot.BackgroundTransparency = true, 0
      bootT.TextTransparency = 0
    else
      local f = math.clamp((t - RAISE - BOOT) / 0.3, 0, 1)
      boot.BackgroundTransparency = f
      bootT.TextTransparency = f
      bootBar.BackgroundTransparency, bootBg.BackgroundTransparency = f, f
      boot.Visible = f < 1
    end
    if not st or not st.d then return end
    local d = st.d
    local cf = st.cf
    local pos = cf.Position
    local M = G.AD and G.AD.M or 3.57
    -- 离操作员多远、数据链信号（卫通满格；视距的越远越弱）
    local char = me.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local dist = hrp and (pos - hrp.Position).Magnitude or 0
    local R = (G.Map and G.Map.R) or 3000
    local bars = d.sat and 5 or math.clamp(5 - math.floor(dist / (R * 0.45)), 1, 5)
    linkText.Text = T("uav.linkName")
    linkType.Text = T(d.sat and "uav.sat" or "uav.los")
    for i, f in ipairs(sig) do
      f.BackgroundColor3 = (bars <= 1) and AMBER or WHITE
      f.BackgroundTransparency = (i <= bars) and 0 or 0.75
    end
    if G.tabletLeds then
      G.tabletLeds.LINK.BackgroundColor3 = (bars <= 1 and (os.clock() * 3) % 1 < 0.5) and RGB(60, 40, 20) or RGB(80, 230, 110)
    end
    -- 录像计时、电量、时间
    recText.Text = T("uav.rec") .. " " .. fmtClock(t)
    recDot.BackgroundTransparency = ((os.clock() % 1) < 0.55) and 0 or 1
    S.bat = math.max(5, S.bat - dt / 45)
    local now = os.date and os.date("*t")
    batText.Text = T("uav.bat", math.floor(S.bat)) .. (now and string.format("   %02d:%02d", now.hour, now.min) or "")
    -- 标题：型号 · 镜头 · 倍率
    local nose = st.dcam == "nose"
    title.Text = T("veh." .. d.id) .. "  ·  " .. T(nose and "uav.nose" or "uav.chase") .. (nose and string.format("  ×%.1f", st.zoomS or 1) or "")
    -- 航向带（看的方向：前视看镜头方向、外部看机头方向）
    local look = nose and workspace.CurrentCamera.CFrame.LookVector or cf.LookVector
    local hdg = (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
    for i = 0, 35 do
      local dd = angDiff(hdg, i * 10)
      local l = marks[i]
      if math.abs(dd) < 33 then
        l.Visible = true
        l.Position = UDs(0.5 + dd / 66, 0.5)
      else
        l.Visible = false
      end
    end
    hdgText.Text = string.format("%03d°", math.floor(hdg + 0.5) % 360)
    -- 遥测
    local gy = G.AD and G.AD.ground and G.AD.ground(G.Map, pos.X, pos.Z) or 0
    local kmh = math.floor(st.vel.Magnitude / M * 3.6 + 0.5)
    tl[1].Text = T("uav.alt", math.max(0, math.floor((pos.Y - math.max(gy, 0)) / M + 0.5)))
    tl[2].Text = T("uav.spd", kmh)
    tl[3].Text = T("uav.vs", string.format("%+.0f", st.vel.Y / M))
    tl[4].Text = T("uav.dist", string.format("%.1f", dist / M / 1000))
    tl[5].Text = T("uav.flr", st.flares or 0)
    local ap = st.aimPt
    if ap then
      al1.Text = T("uav.aim", string.format("%.1f", (ap - pos).Magnitude / M / 1000))
      al2.Text = string.format("E %05d  N %05d", math.floor((ap.X + 20000) / M) % 100000, math.floor((20000 - ap.Z) / M) % 100000)
    else
      al1.Text, al2.Text = "", ""
    end
    -- 前视：十字线、倍率
    for _, f in ipairs(cross) do f.Visible = nose end
    zoomText.Visible = nose
    zoomText.Text = string.format("×%.1f", st.zoomS or 1)
    -- 信号弱：雪花
    local weak = bars <= 1
    for i, f in ipairs(noise) do
      if weak and math.random() < 0.7 then
        f.BackgroundTransparency = 0.55 + math.random() * 0.4
        f.Position = UDs(0, math.random())
        f.Size = UD(1, 0, 0, math.random(1, 5))
      else
        f.BackgroundTransparency = 1
      end
    end
    weakText.Text = weak and T("uav.weak") or ""
    -- 操作员挨打
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
      if S.hp and hum.Health < S.hp - 0.5 then S.hurtT = os.clock() end
      S.hp = hum.Health
    end
    local ht = os.clock() - S.hurtT
    if ht < 2.5 then
      local a = 0.5 + 0.5 * math.cos(ht * 12)
      hurtS.Transparency = 0.15 + 0.5 * a
      hurtText.Text = T("uav.hit")
      hurtText.TextTransparency = 0.3 * a
    else
      hurtS.Transparency = 1
      hurtText.Text = ""
    end
  end

  ---------------------------------------------------------------- 重连提示

  local hintGui = Instance.new("ScreenGui")
  hintGui.Name = "UavLink"
  hintGui.ResetOnSpawn = false
  hintGui.IgnoreGuiInset = true
  hintGui.DisplayOrder = 3
  hintGui.Parent = me:WaitForChild("PlayerGui")
  local hint = Instance.new("TextButton")
  hint.Size = UDo(440, 34)
  hint.Position = UD(0.5, 0, 1, -206)   -- 在夜视提示（-168）上面
  hint.AnchorPoint = V2(0.5, 1)
  hint.BackgroundColor3 = RGB(10, 14, 16)
  hint.BackgroundTransparency = 0.35
  hint.BorderSizePixel = 0
  hint.AutoButtonColor = false
  hint.Font = Enum.Font.GothamMedium
  hint.TextSize = 15
  hint.TextColor3 = RGB(236, 240, 236)
  hint.Text = ""
  hint.Visible = false
  hint.Parent = hintGui
  corner(hint, 8)
  stroke(hint, RGB(120, 230, 150), 1, 0.4)
  local mine = nil   -- 能重连的那架（实体模型）
  local scanT = 0
  local function relink()
    if mine and mine.Parent and not G.drive then G.R.Act:FireServer("uavLink", mine:GetAttribute("EntId")) end
  end
  hint.Activated:Connect(relink)
  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    if io.KeyCode == Enum.KeyCode.T and mine and not G.drive then relink() end
  end)
  local function stepHint(dt)
    scanT -= dt
    if scanT <= 0 then
      scanT = 0.5
      mine = nil
      local f = workspace:FindFirstChild("Ents")
      local uid = me.UserId
      if f and not G.drive then
        for _, em in ipairs(f:GetChildren()) do
          if em:GetAttribute("Op") == uid and em:GetAttribute("Driver") == 0 and not em:GetAttribute("Wreck") and em:GetAttribute("Kind") == "air" then
            mine = em
            break
          end
        end
      end
    end
    local alive = G.S and G.S.alive
    if mine and mine.Parent and alive and not G.drive then
      local name = T("veh." .. tostring(mine:GetAttribute("Model")))
      local endT = mine:GetAttribute("LoitEnd")
      if mine:GetAttribute("Loiter") and endT then
        local left = math.max(0, math.floor(endT - workspace:GetServerTimeNow()))
        hint.Text = T(mob and "uav.relinkTouchAir" or "uav.relinkAir", name, left)
      else
        hint.Text = T(mob and "uav.relinkTouch" or "uav.relink", name)
      end
      hint.Visible = true
    else
      hint.Visible = false
    end
  end

  function G.stepTablet(dt)
    stepHint(dt)
    if S.open then
      stepOpen(dt)
    elseif S.closeT then
      -- 收起：往下落
      S.closeT += dt
      local k = math.clamp(S.closeT / 0.28, 0, 1)
      root.Position = UDs(0, k * k)
      black.BackgroundTransparency = 1
      if k >= 1 then
        S.closeT = nil
        gui.Enabled = false
      end
    end
  end
end

return Tablet
