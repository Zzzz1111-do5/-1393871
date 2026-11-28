-- 全面大战场（客户端）——战雷式的开飞机界面
--   用户 11-24 夜：「飞机操作ui我记得有个版本已经帮我改成战争雷霆的了 现在完全不是」「战雷ui压根不是这样的」，发了 B 站战雷视频的截图
--   （米格-29、F-15 的空战）；「不同导弹有不同锁定范围 锁定前大圈和小圈都是白色的 锁定就都变成红色」「那个雷达屏在右侧」。
--   照截图和战雷 wiki（官方英文 wiki「Airborne radars」、中文 wiki「机载雷达」「雷达告警接收器」）做，图都是框和字拼的：
--   · 左上一列小字（标签灰白、数白色等宽）：节流阀（开加力写红色「110 % 加力」）、表速、速度、马赫数、海拔高、雷达高；
--     挂的弹一种一行（「空对空 4[左] R-73」：剩几发、下一发从哪边挂架打，选中的那行前面「›」；红外导引头追踪时标签换成红色「追踪」）、
--     热焰弹、干扰箔（每组诱饵弹里两样都有：一个数）、机炮（「机 炮 自动 150 30 毫米 GSh-30-1」）、燃油量（照现在的油门还能飞几分几秒）；
--     每台发动机的油温、引擎温度（开加力油温往上走、变橙色，后面写还能撑多久）
--   · 机头一个小 ⊕（固定机炮顺着机头打）；选了导弹：大圈是这种弹导引头能锁的离轴角（每种弹不一样大，近距格斗弹的大到出屏幕），
--     小圈是导引头看着哪（追踪时滑到目标上）——锁定前都是白的，锁上都变红
--   · 雷达跟踪着的目标：方框，右边距离、接近速度（越飞越远是负的），左下高度差，下面一个圈带一根线（目标往哪飞：线朝下迎头冲你来，朝上背对你跑）
--   · 顶上一条航向罗盘（雷达看到的敌机在上面是小三角，锁着的套框）；左边雷达告警圆盘（RWR：敌机雷达扫到你标型号，锁着你一条虚线连到中间，
--     导弹打过来「MSL」红色闪、实线）；底下中间「已选武器」「导引头」两行；右边雷达屏在 Radar.lua；右上圆形小地图（TankHud 的飞机模式）；
--     左下损伤图是 C 的 WtAir.lua
--   G.wtFlightStep(st, info)：AirHud 每帧调（G.wtFlightOn 开着时 AirHud 原来那套 MWT 式的收起来）；G.wtFlightOff() 下飞机收起
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local WtFlight = {}

function WtFlight.init(G)
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local AD = require(RS:WaitForChild("AirDefs"))
  local V, V2, UD2 = Vector3.new, Vector2.new, UDim2.new
  local RGB = Color3.fromRGB
  local clamp, rad, deg = math.clamp, math.rad, math.deg
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local HUD = TH.C.HUD                     -- 战雷平显的绿（界面一律绿色：用户 11-21）
  local TXT, LAB = TH.C.TEXT, TH.C.MUTE   -- 左上：数白、标签灰白
  local RED, ORG, WHITE = TH.C.BAD, TH.C.WARN, Color3.new(1, 1, 1)
  local INK = RGB(0, 0, 0)
  local MONO, SANS = Enum.Font.RobotoMono, Enum.Font.BuilderSans
  G.wtFlightOn = true

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtFlight"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or INK, tr or 1, 0
    f.Parent = parent
    return f
  end
  local function label(parent, size, pos, ts, col, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.Text, l.TextSize, l.TextColor3, l.Font = "", ts or 13, col or TXT, font or MONO
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.55, INK
    l.Parent = parent
    return l
  end
  local function ringOf(parent, px, col, th)   -- 一个圈：圆角框 + 描边
    local f = frame(parent, UDim2.fromOffset(px, px), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = col or WHITE, th or 1.4, 0
    s.Parent = f
    return f, s
  end
  local function seg(parent, col, th)   -- 一段线（setSeg 摆两头）
    local f = frame(parent, UDim2.fromOffset(2, th or 1.4), UD2(), col or HUD, 0, V2(0.5, 0.5))
    f.Visible = false
    return f
  end
  local function setSeg(f, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), f.Size.Y.Offset)
    f.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
    f.Rotation = deg(math.atan2(dy, dx))
    f.Visible = true
  end

  local W = {}
  G.wtFlight = W   -- 测试用

  ---------------------------------------------------------------- 左上：参数表
  local LIST_X = mobile and 12 or 70   -- 让开左上角的菜单键（≡）、Roblox 自己那排按钮
  local list = frame(gui, UDim2.fromOffset(330, 470), UD2(0, LIST_X, 0, mobile and 64 or 58))
  list.Name = "WtParams"
  local ROW, COL1, COL2 = 16, 74, 178
  local rows = {}
  local function row(i)
    local r = rows[i]
    if r then return r end
    local y = (i - 1) * ROW
    r = {}
    r.mk = label(list, UDim2.fromOffset(10, ROW), UD2(0, -2, 0, y), 13, TXT, MONO)
    r.lab = label(list, UDim2.fromOffset(COL1 - 10, ROW), UD2(0, 10, 0, y), 13, LAB, SANS)
    r.val = label(list, UDim2.fromOffset(COL2 - COL1, ROW), UD2(0, COL1 + 8, 0, y), 13, TXT, MONO)
    r.ext = label(list, UDim2.fromOffset(160, ROW), UD2(0, COL2 + 8, 0, y), 13, TXT, MONO)
    r.lab.Name, r.val.Name, r.ext.Name = "Lab" .. i, "Val" .. i, "Ext" .. i
    rows[i] = r
    return r
  end
  local nRows = 0
  local function put(mk, lab, val, ext, labCol, valCol)
    nRows += 1
    local r = row(nRows)
    r.mk.Text, r.lab.Text, r.val.Text, r.ext.Text = mk or "", lab or "", val or "", ext or ""
    r.lab.TextColor3, r.val.TextColor3, r.ext.TextColor3 = labCol or LAB, valCol or TXT, valCol or TXT
    r.mk.Visible, r.lab.Visible, r.val.Visible, r.ext.Visible = true, true, true, true
  end
  local function gap()
    nRows += 1
    local r = row(nRows)
    r.mk.Text, r.lab.Text, r.val.Text, r.ext.Text = "", "", "", ""
  end
  W.rows = rows

  -- 大气（国际标准大气，对流层）：表速 = 真速 × √(ρ / ρ0)，声速按温度
  local function atmo(hM)
    local h = clamp(hM, -500, 20000)
    local Tk = math.max(216.65, 288.15 - 0.0065 * h)
    local rho = (h < 11000) and (1 - 2.25577e-5 * h) ^ 4.25588 or 0.2971 * math.exp(-(h - 11000) / 6341.6)
    return rho, 20.05 * math.sqrt(Tk)
  end
  -- 发动机温度（只是看的：油门越大越热，开加力油温慢慢往上走、过了 105 °C 变橙色，写还能撑多久——战雷那样；不影响推演）
  local eng = { oil = 88, egt = 520, abT = 0 }
  local KIND_LAB = { aam = "wt.aam", agm = "wt.agm", bomb = "wt.bomb", rkt = "wt.rkt" }

  ---------------------------------------------------------------- 机头 ⊕、导弹的大圈小圈
  local bore = frame(gui, UDim2.fromOffset(26, 26), UD2(0.5, 0, 0.5, 0), INK, 1, V2(0.5, 0.5))
  bore.Name = "WtBore"
  do
    local _, s = ringOf(bore, 16, HUD, 1.4)
    s.Parent.Name = "Ring"
    for _, a in ipairs({ { 0, -10, 1.4, 8 }, { 0, 10, 1.4, 8 }, { -10, 0, 8, 1.4 }, { 10, 0, 8, 1.4 } }) do   -- 十字从圈里伸出来一点
      local f = frame(bore, UDim2.fromOffset(a[3], a[4]), UD2(0.5, a[1], 0.5, a[2]), HUD, 0, V2(0.5, 0.5))
      f.Name = "Tick"
    end
  end
  bore.Visible = false
  local bigC, bigS = ringOf(gui, 200, WHITE, 1.5)
  bigC.Name = "SeekerCone"
  bigC.Visible = false
  local smallC, smallS = ringOf(gui, 26, WHITE, 1.6)
  smallC.Name = "SeekerHead"
  smallC.Visible = false
  -- 雷达近战模式的扫描区（Radar.lua 的 G.radarAcmZone，机体坐标）：竖扫两条竖线、平显视场 / 可挪一个框、瞄准线 / 头盔一个小圈
  local acmZ = frame(gui, UDim2.fromScale(1, 1), UD2(), INK, 1)
  acmZ.Name = "WtAcmZone"
  acmZ.Visible = false
  local acmSeg = {}
  for i = 1, 4 do
    acmSeg[i] = seg(acmZ, HUD, 1.4)
    acmSeg[i].Name = "AcmEdge"
  end
  local acmRing = ringOf(acmZ, 20, HUD, 1.4)
  acmRing.Name = "AcmRing"

  ---------------------------------------------------------------- 锁定框（雷达 / 导引头跟踪着的目标）
  local box = frame(gui, UDim2.fromOffset(30, 30), UD2(), INK, 1, V2(0.5, 0.5))
  box.Name = "WtLockBox"
  local boxS = Instance.new("UIStroke")
  boxS.Color, boxS.Thickness = HUD, 1.6
  boxS.Parent = box
  box.Visible = false
  local bDist = label(box, UDim2.fromOffset(90, 15), UD2(1, 4, 0, -2), 13, HUD, MONO)
  local bVc = label(box, UDim2.fromOffset(90, 15), UD2(1, 4, 0, 14), 13, HUD, MONO)
  local bAlt = label(box, UDim2.fromOffset(70, 15), UD2(0, 0, 1, 3), 13, HUD, MONO, V2(1, 0), Enum.TextXAlignment.Right)
  bDist.Name, bVc.Name, bAlt.Name = "Range", "Closure", "AltDiff"
  for _, l in ipairs({ bDist, bVc, bAlt }) do l.TextStrokeTransparency = 0.3 end
  -- 目标往哪飞：一个小圈、从圈心伸出一根线（线朝下迎头、朝上背对着跑；左右按它横着飞的方向）
  local asp = frame(box, UDim2.fromOffset(24, 24), UD2(0.5, 0, 1, 18), INK, 1, V2(0.5, 0.5))
  asp.Name = "Aspect"
  ringOf(asp, 10, HUD, 1.4)
  local aspLine = frame(asp, UDim2.fromOffset(1.6, 11), UD2(0.5, 0, 0.5, 0), HUD, 0, V2(0.5, 0))
  aspLine.Name = "AspectLine"
  local tracks = setmetatable({}, { __mode = "k" })
  local function velOf(em, p, t)   -- 目标的速度（服务器不发速度）：只在服务器真挪了它时按两次挪之间的时间算、按时间平滑（View.lua G.velTrack）
    local r = tracks[em]
    if not r then
      r = {}
      tracks[em] = r
    end
    if G.velTrack then return G.velTrack(r, p, t, 3000) end
    r.p, r.t, r.v = p, t, r.v or V()
    return r.v
  end

  ---------------------------------------------------------------- 顶上：航向罗盘
  local TAPE_W, TAPE_DEG = 380, 30   -- 宽多少像素、两头各多少度
  local tape = frame(gui, UDim2.fromOffset(TAPE_W, 34), UD2(0.5, 0, 0, mobile and 40 or 6), INK, 1, V2(0.5, 0))
  tape.Name = "WtHeading"
  tape.ClipsDescendants = true
  local tapeMarks = {}
  for i = 1, 16 do
    local l = label(tape, UDim2.fromOffset(40, 14), UD2(), 12, TXT, MONO, V2(0.5, 0), Enum.TextXAlignment.Center)
    local tk = frame(tape, UDim2.fromOffset(1.4, 5), UD2(), TXT, 0.2, V2(0.5, 0))
    tapeMarks[i] = { l = l, tk = tk }
  end
  local caret = label(gui, UDim2.fromOffset(20, 12), UD2(0.5, 0, 0, (mobile and 40 or 6) + 30), 11, TXT, MONO, V2(0.5, 0), Enum.TextXAlignment.Center)
  caret.Text = "^"
  caret.Name = "WtHeadingCaret"
  local tapeTri = {}   -- 雷达看到的敌机：罗盘上一个小菱形（锁着的换成方框）
  for i = 1, 10 do
    local tr = frame(tape, UDim2.fromOffset(7, 7), UD2(), RED, 0, V2(0.5, 0.5))
    tr.Name = "Contact"
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = HUD, 1.4, 1
    s.Parent = tr
    tr.Visible = false
    tapeTri[i] = { f = tr, s = s }
  end

  ---------------------------------------------------------------- 左边：雷达告警圆盘（RWR）
  local RW = 150
  local rwr = frame(gui, UDim2.fromOffset(RW, RW), UD2(0, mobile and 18 or 46, 0.5, 70), INK, 1, V2(0, 0.5))
  rwr.Name = "WtRwr"
  do
    local o = ringOf(rwr, RW, HUD, 1.4)
    o.Name = "Outer"
    local i2 = ringOf(rwr, RW * 0.62, HUD, 1)
    i2.Name = "Inner"
    local plus = label(rwr, UDim2.fromOffset(20, 20), UD2(0.5, 0, 0.5, 0), 16, HUD, MONO, V2(0.5, 0.5), Enum.TextXAlignment.Center)
    plus.Text = "+"
  end
  local rwrBg = Instance.new("UICorner")
  rwrBg.CornerRadius = UDim.new(0.5, 0)
  rwrBg.Parent = rwr
  rwr.BackgroundColor3, rwr.BackgroundTransparency = RGB(0, 30, 10), 0.75
  local rwrTags, rwrLines = {}, {}
  for i = 1, 8 do
    local l = label(rwr, UDim2.fromOffset(40, 14), UD2(), 12, HUD, MONO, V2(0.5, 0.5), Enum.TextXAlignment.Center)
    l.Visible = false
    rwrTags[i] = l
    local dashes = {}
    for k = 1, 6 do
      dashes[k] = seg(rwr, HUD, 1.4)
      dashes[k].Name = "RwrDash"
    end
    rwrLines[i] = dashes
  end
  local threats = {}   -- [实体 id] = { t 最后一次, lock 锁着我到什么时候, msl 导弹打过来到什么时候 }
  function G.wtRwrEvent(op, m)   -- Fly.lua 收到服务器的 rwr / rwrLock 时转过来
    if op == "rwrLock" and m.by then
      local r = threats[m.by] or {}
      r.lock = os.clock() + 1.1
      threats[m.by] = r
    elseif op == "rwr" then
      W.mslUntil = os.clock() + 4
      W.mslBy = W.lastLockBy
    end
    if op == "rwrLock" then W.lastLockBy = m.by end
  end

  ---------------------------------------------------------------- 底下中间：已选武器、导引头
  local selW = label(gui, UDim2.fromOffset(420, 16), UD2(0.5, -130, 1, mobile and -150 or -118), 14, TXT, SANS)
  local selS = label(gui, UDim2.fromOffset(420, 16), UD2(0.5, -130, 1, mobile and -132 or -100), 14, TXT, SANS)
  selW.Name, selS.Name = "WtSelWeapon", "WtSeeker"

  ---------------------------------------------------------------- 每帧
  local lastT = -9
  local function px(degs)   -- 离轴角 → 屏幕上离画面中心多少像素（按镜头视场）
    local vh = math.max(cam.ViewportSize.Y, 1)
    return (vh / 2) / math.tan(rad(cam.FieldOfView / 2)) * math.tan(rad(clamp(degs, 0, 85)))
  end
  local function proj(p)
    local sp, on = cam:WorldToViewportPoint(p)
    return UDim2.fromOffset(sp.X, sp.Y), on and sp.Z > 0, sp
  end

  function G.wtFlightStep(st, info)
    if not G.wtFlightOn or not info.pilot or st.uav then
      gui.Enabled = false
      return
    end
    gui.Enabled = true
    local t = os.clock()
    local dt = math.min(0.1, t - lastT)
    lastT = t
    local d = info.d
    local cf = st.cf
    local pos = cf.Position
    local jet = d.kind == "jet"

    -- ① 左上参数表
    nRows = 0
    local thr = st.thr or 0
    if jet then
      if thr > 100.5 then put(nil, T("wt.thr"), string.format("%d %% %s", math.floor(thr + 0.5), T("wt.ab")), nil, nil, RED)
      else put(nil, T("wt.thr"), string.format("%d %%", math.floor(thr + 0.5))) end
    else
      put(nil, T("wt.rotor"), string.format("%d %%", math.floor((st.rpm or 0) + 0.5)))
    end
    local hM = pos.Y / AD.M
    local rho, a = atmo(hM)
    local tas = st.vel.Magnitude / AD.M
    put(nil, T("wt.ias"), string.format("%d km/h", math.floor(tas * math.sqrt(rho) * 3.6 + 0.5)))
    put(nil, T("wt.tas"), string.format("%d km/h", math.floor(tas * 3.6 + 0.5)))
    put(nil, T("wt.mach"), string.format("%.2f", tas / a))
    put(nil, T("wt.alt"), T("wt.m", math.floor(hM + 0.5)))
    put(nil, T("wt.ralt"), T("wt.m", math.max(0, info.agl or 0)))
    gap()
    -- 挂的弹：一种一行（机炮放最后），选中的前面「›」
    local items = info.wl or {}
    local gunIt, flareIt = nil, nil
    local lk = info.lock
    for _, it in ipairs(items) do
      if it.flare then flareIt = it
      elseif it.w and it.w.kind == "gun" then gunIt = gunIt or it
      elseif it.w then
        local labK = KIND_LAB[it.w.kind] or "wt.agm"
        local labCol = nil
        if it.sel and lk and lk.on and lk.seeker == "ir" and not lk.locked then labK, labCol = "wt.track", RED end   -- 红外导引头在追踪
        local n = it.n or 0
        local side = (n % 2 == 0) and T("wt.left") or T("wt.right")   -- 左右挂架轮着打
        put(it.sel and ">" or "", T(labK), (n > 0) and string.format("%d[%s]", n, side) or "0", T("aw." .. it.wid), labCol, (n > 0) and TXT or RED)
      end
    end
    local nf = flareIt and flareIt.n or st.flares or 0
    put("", T("wt.flare"), tostring(nf), nil, nil, (nf > 0) and TXT or RED)
    put("", T("wt.chaff"), tostring(nf), nil, nil, (nf > 0) and TXT or RED)
    if gunIt then
      put(gunIt.sel and ">" or "", T("wt.gun"), tostring(gunIt.n or 0), T("aw." .. gunIt.wid), nil, ((gunIt.n or 0) > 0) and TXT or RED)
    end
    put("", T("wt.fuel"), info.fuelT or "--:--", nil, nil, info.fuelCol or TXT)
    gap()
    -- 发动机：每台一组油温、引擎温度——跟着发动机真实的状态走（用户 11-26「飞机发动机有 bug」）：
    --   原来开加力一分钟油温过 105 °C 就挂一个橙色的「还能撑多久」倒计时，可油温最高只到 116 °C，倒计时永远停在 0:33 走不完
    --   （喷气机在这里不会过热坏掉，战雷的喷气机也不过热）——倒计时去掉；
    --   发动机受伤：排气温度高、发涩（橙）；打坏 / 没油熄火：两个温度一路往下掉（红，写「熄火」）
    local k = clamp(thr / 100, 0, 1.3)
    local wae = G.wtaFlight and G.wtaFlight(st.em)
    local engK = wae and wae.eng or 1
    local dead = st.out == true or engK <= 0
    if jet then
      local ab = thr > 100.5 and not dead
      eng.abT = ab and math.min(eng.abT + dt, 120) or math.max(0, eng.abT - dt * 0.5)
      local oilT = dead and 45 or (84 + 14 * math.min(k, 1) + eng.abT / 120 * 6)
      local egtT = dead and 160 or (520 + 330 * math.min(k, 1) + (ab and 100 or 0) + (1 - engK) * 160)
      eng.oil += (oilT - eng.oil) * math.min(1, dt * (dead and 0.08 or 0.4))
      eng.egt += (egtT - eng.egt) * math.min(1, dt * (dead and 0.35 or 1.5))
    else
      local r = clamp((st.rpm or 0) / 100, 0, 1)
      eng.oil += (((dead and 45) or (80 + 20 * r)) - eng.oil) * math.min(1, dt * (dead and 0.08 or 0.4))
      eng.egt += (((dead and 160) or (480 + 260 * r + (1 - engK) * 140)) - eng.egt) * math.min(1, dt * (dead and 0.35 or 1.5))
    end
    local nEng = (d.eng and #d.eng > 0) and #d.eng or 1
    local hurt = not dead and engK < 1
    local col = (dead and RED) or (hurt and ORG) or TXT
    for _ = 1, math.min(nEng, 3) do
      put("", T("wt.oil"), string.format("%d°C", math.floor(eng.oil + 0.5)), nil, (dead or hurt) and col or nil, col)
      put("", T("wt.eng"), dead and string.format("%d°C %s", math.floor(eng.egt + 0.5), T("wt.engOff")) or string.format("%d°C", math.floor(eng.egt + 0.5)),
        nil, (dead or hurt) and col or nil, col)
    end
    for i = nRows + 1, #rows do
      local r = rows[i]
      r.mk.Visible, r.lab.Visible, r.val.Visible, r.ext.Visible = false, false, false, false
    end

    -- ② 机头 ⊕、导弹的大圈小圈
    local bp, bon = proj(pos + cf.LookVector * 600)
    bore.Position, bore.Visible = bp, bon and not st.eo and not st.bsight
    local w = info.w
    local missile = w and (w.kind == "aam" or w.kind == "agm") and (w.cone or 0) > 0
    if missile and bon and not st.eo and not st.bsight then
      local locked = lk and lk.on and lk.locked
      local col = locked and RED or WHITE
      local r0 = px(w.cone) * 2
      bigC.Size, bigC.Position, bigC.Visible = UDim2.fromOffset(r0, r0), bp, true
      bigS.Color = col
      -- 小圈：导引头看着哪——没目标在大圈中心；追踪 / 锁定时滑到目标上（红外的从机头滑过去，雷达弹锁着就在目标上）
      local sp = bp
      if lk and lk.on and lk.p then
        local kk = locked and 1 or clamp(lk.k or 0, 0, 1)
        sp = bp:Lerp(lk.p, (lk.seeker == "ir") and kk or (locked and 1 or 0))
      end
      smallC.Position, smallC.Visible = sp, true
      smallC.Size = UDim2.fromOffset(locked and 22 or 26, locked and 22 or 26)
      smallS.Color = col
    else
      bigC.Visible, smallC.Visible = false, false
    end
    -- 雷达近战模式的扫描区：按机体坐标的角度投到画面上（离机头 800 格的那个面）；竖扫的上头（+50°）多半在画面外，线照样画（屏幕边上截断）
    local zA = G.radarAcmZone and G.radarAcmZone()
    if zA and not st.eo and not st.bsight then
      local function at(a, e)
        local ca, ce = math.cos(rad(a)), math.cos(rad(e))
        local dir = cf:VectorToWorldSpace(V(math.sin(rad(a)) * ce, math.sin(rad(e)), -ca * ce))
        local _, _, sp = proj(pos + dir * 800)
        return sp.X, sp.Y, sp.Z > 1
      end
      local okAll = true
      if zA.fixed or zA.head then
        local x, y, on = at(zA.cAz, zA.cEl)
        local r0 = math.max(px(math.max(zA.A, zA.H, zA.beam or 2)) * 2, 12)
        acmRing.Position, acmRing.Size, acmRing.Visible = UDim2.fromOffset(x, y), UDim2.fromOffset(r0, r0), on
        for _, s2 in ipairs(acmSeg) do s2.Visible = false end
        okAll = on
      else
        acmRing.Visible = false
        local a0, a1, e0, e1 = zA.cAz - zA.A, zA.cAz + zA.A, zA.cEl - zA.H, zA.cEl + zA.H
        local x00, y00, o1 = at(a0, e0)
        local x10, y10, o2 = at(a1, e0)
        local x01, y01, o3 = at(a0, e1)
        local x11, y11, o4 = at(a1, e1)
        okAll = o1 and o2 and o3 and o4
        if okAll then
          setSeg(acmSeg[1], x00, y00, x01, y01)   -- 左边
          setSeg(acmSeg[2], x10, y10, x11, y11)   -- 右边
          if zA.vert then   -- 竖扫只画两条竖线
            acmSeg[3].Visible, acmSeg[4].Visible = false, false
          else
            setSeg(acmSeg[3], x01, y01, x11, y11)
            setSeg(acmSeg[4], x00, y00, x10, y10)
          end
        else
          for _, s2 in ipairs(acmSeg) do s2.Visible = false end
        end
      end
      acmZ.Visible = okAll
    else
      acmZ.Visible = false
    end

    -- ③ 锁定框：距离、接近速度、高度差、目标往哪飞（选的弹没锁、雷达 STT 锁着的也画：雷达锁定跟所选武器无关）
    local tgt, blk = st.lock, lk
    if not (blk and blk.on and blk.p and tgt) and st.rdLock and not st.rdLock.mem and st.rdLock.p then
      local rp, ron = proj(st.rdLock.p)
      if ron then blk, tgt = { on = true, p = rp, dist = st.rdLock.dist }, st.rdLock end
    end
    if blk and blk.on and blk.p and tgt and not st.eo and not st.bsight then
      box.Visible = true
      box.Position = blk.p
      local m = (blk.dist or 0) / AD.M
      bDist.Text = (m >= 1000) and string.format("%.1f km", m / 1000) or string.format("%d m", math.floor(m + 0.5))
      bVc.Text = blk.vc and string.format("%d m/s", math.floor(blk.vc + 0.5)) or ""
      local em = tgt.em
      local root = em and em.Parent and em:FindFirstChild("Root")
      if root then
        local tp = root.CFrame.Position
        local dh = (tp.Y - pos.Y) / AD.M
        bAlt.Text = (math.abs(dh) >= 1000) and string.format("%+.0f km", dh / 1000) or string.format("%+d m", math.floor(dh / 10 + 0.5) * 10)
        local vT = velOf(em, tp, t)
        local los = (pos - tp)   -- 从目标看向我
        if vT.Magnitude > 5 and los.Magnitude > 1 then
          local u = los.Unit
          local head = vT.Unit:Dot(u)   -- 1 迎头冲我来、−1 背对我
          local side = cam.CFrame.RightVector:Dot(vT.Unit)
          local ang = deg(math.acos(clamp(head, -1, 1)))   -- 0 迎头、180 背对
          aspLine.Rotation = (side >= 0) and -ang or ang   -- 0°：线朝下（迎头）
          aspLine.Visible = true
        else
          aspLine.Visible = false
        end
      else
        bAlt.Text = ""
        aspLine.Visible = false
      end
    else
      box.Visible = false
    end

    -- ④ 航向罗盘
    local lv = cf.LookVector
    local hdg = (deg(math.atan2(lv.X, -lv.Z)) + 360) % 360
    local base = math.floor((hdg - TAPE_DEG) / 5) * 5
    local CARD = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
    for i, mk in ipairs(tapeMarks) do
      local h = base + (i - 1) * 5
      local off = h - hdg
      local x = TAPE_W / 2 + off / TAPE_DEG * (TAPE_W / 2)
      local hh = (h % 360 + 360) % 360
      mk.l.Visible = x > 8 and x < TAPE_W - 8 and (hh % 10 == 0 or hh % 5 == 0)
      mk.tk.Visible = mk.l.Visible
      if mk.l.Visible then
        mk.l.Position = UDim2.fromOffset(x, 0)
        mk.tk.Position = UDim2.fromOffset(x, 15)
        mk.l.Text = CARD[hh] or tostring(hh)
        mk.l.TextColor3 = CARD[hh] and HUD or TXT
      end
    end
    local contacts = G.airRadarContacts and G.airRadarContacts() or {}   -- Radar.lua（Hud.lua 的 G.radarContacts 是小地图那份）
    local ni = 0
    for _, c in ipairs(contacts) do
      if ni < #tapeTri and math.abs(c.az) < TAPE_DEG then
        ni += 1
        local tr = tapeTri[ni]
        tr.f.Position = UDim2.fromOffset(TAPE_W / 2 + c.az / TAPE_DEG * (TAPE_W / 2), 26)
        tr.f.Rotation = c.locked and 0 or 45
        tr.f.Size = c.locked and UDim2.fromOffset(9, 9) or UDim2.fromOffset(6, 6)
        tr.f.BackgroundTransparency = c.locked and 1 or 0
        tr.s.Transparency = c.locked and 0 or 1
        tr.f.Visible = true
      end
    end
    for i = ni + 1, #tapeTri do tapeTri[i].f.Visible = false end

    -- ⑤ 雷达告警圆盘：敌机的雷达扫到我（在它的扫描范围里）标型号，锁着我虚线连到中间，导弹打过来实线、红色闪
    local ents = workspace:FindFirstChild("Ents")
    local side = me:GetAttribute("Side")
    local myYaw = math.atan2(lv.X, -lv.Z)
    local ti = 0
    local R0 = RW / 2
    local function place(i, bearing, rr, text, col, mode)   -- mode：nil 只有字、"dash" 虚线、"solid" 实线
      local x = R0 + math.sin(bearing) * rr
      local y = R0 - math.cos(bearing) * rr
      local tag = rwrTags[i]
      tag.Text, tag.TextColor3, tag.Visible = text, col, true
      tag.Position = UDim2.fromOffset(x, y)
      local dashes = rwrLines[i]
      for kq, dsh in ipairs(dashes) do
        if mode then
          local n = #dashes
          local a0, a1 = (kq - 1) / n, (kq - (mode == "dash" and 0.45 or 0)) / n
          local ex, ey = R0 + math.sin(bearing) * (rr - 9), R0 - math.cos(bearing) * (rr - 9)
          setSeg(dsh, R0 + (ex - R0) * a0, R0 + (ey - R0) * a0, R0 + (ex - R0) * a1, R0 + (ey - R0) * a1)
          dsh.BackgroundColor3 = col
        else
          dsh.Visible = false
        end
      end
    end
    local mslOn = W.mslUntil and t < W.mslUntil
    for _, em in ipairs(ents and ents:GetChildren() or {}) do
      if ti >= #rwrTags then break end
      local mdl = em:GetAttribute("Model")
      -- 敌机的雷达按它的科技树版本取（Radars.lua：F-16A 是 APG-66、苏-30SM 是 N011M），不是只看型号
      local rd = mdl and AD.radarOf and AD.radarOf(mdl, em:GetAttribute("TreeKey"))
      local root = em:FindFirstChild("Root")
      if rd and root and em ~= st.em and em:GetAttribute("Team") ~= side and em:GetAttribute("Kind") == "air" and (em:GetAttribute("Hp") or 1) > 0 then
        local rc = root.CFrame
        local to = pos - rc.Position
        local dist = to.Magnitude
        local id = em:GetAttribute("EntId")
        local th = id and threats[id]
        local locking = th and th.lock and t < th.lock
        local l = rc:VectorToObjectSpace(to / math.max(dist, 1))
        -- 扫到我：在它的量程里、它默认扫描方式的方位宽度里（第 4 步以前没有扫描中心；不然苏-35S 的 ±120° 万向架一下子全扫得到）、俯仰万向架里
        local elT = deg(math.asin(clamp(l.Y, -1, 1)))
        local inScan = dist <= rd.range and math.abs(deg(math.atan2(l.X, -l.Z))) <= (AD.Radars and AD.Radars.half(rd) or rd.az) and elT <= rd.elU and elT >= -rd.elD
        if inScan or locking then
          ti += 1
          local rel = -to
          local bearing = math.atan2(rel.X, -rel.Z) - myYaw
          local missileHere = mslOn and (W.mslBy == id)
          local rr = R0 * (missileHere and 0.42 or (locking and 0.6 or 0.8))
          local code = rd.rwr or string.upper(string.sub(mdl, 1, 4))   -- 告警器代号（Radars.lua 的 rwr：米格-29 写 29，不再是型号前四个字母 MIG2）
          if missileHere then
            place(ti, bearing, rr, ((t * 4) % 1 < 0.6) and "MSL" or "", RED, "solid")
          elseif locking then
            place(ti, bearing, rr, code, ORG, "dash")
          else
            place(ti, bearing, rr, code, HUD, nil)
          end
        end
      end
    end
    if mslOn and not (W.mslBy and threats[W.mslBy]) and ti < #rwrTags then   -- 导弹打过来、不知道是谁打的：正后方闪「MSL」
      ti += 1
      place(ti, math.pi, R0 * 0.42, ((t * 4) % 1 < 0.6) and "MSL" or "", RED, "solid")
    end
    for i = ti + 1, #rwrTags do
      rwrTags[i].Visible = false
      for _, dsh in ipairs(rwrLines[i]) do dsh.Visible = false end
    end
    for id, th in pairs(threats) do
      if not th.lock or t - th.lock > 5 then threats[id] = nil end
    end

    -- ⑥ 底下中间：已选武器、导引头
    if w and info.wid then
      selW.Text = T("wt.selW", T("aw." .. info.wid), T("air.k." .. (w.kind or "agm")))
      if w.kind == "aam" or (w.kind == "agm" and (w.cone or 0) > 0) then
        local stt = (lk and lk.on) and (lk.locked and "wt.seekLock" or "wt.seekTrack") or "wt.seekOn"
        selS.Text = T("wt.seeker", T(stt))
        selS.TextColor3 = (lk and lk.on and lk.locked) and RED or TXT
      else
        selS.Text = ""
      end
    else
      selW.Text, selS.Text = "", ""
    end
  end

  function G.wtFlightOff()
    gui.Enabled = false
  end
  G.wtFlightGui = gui   -- 测试用
  G.frameConn("WtFlight", function()
    if gui.Enabled and os.clock() - lastT > 0.25 then gui.Enabled = false end
  end)
end

return WtFlight
