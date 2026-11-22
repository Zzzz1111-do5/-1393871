-- Roblox全面大战场（客户端）——高超音速战术核导弹：警报、红圈、核爆（服务器 Nuke.lua；用户 11-22：「给 h6k 加一个高超音速战术核弹的挂载吧」）
--   发射（nukeWarn）：对面全队——顶上红色警报条「核打击来袭」、倒计时、警报声（滴答声截一小段循环、变速叠出来的汽笛）、
--     地上两圈红色的圈（致死半径、重伤半径）、爆心上方一个「☢ 爆心」标记、小地图上爆心一闪一闪；自己队——琥珀色的「核导弹已发射」、同样的圈（我方不受伤害）
--   开飞机按住发射键：屏幕中间一条解锁进度（Fly.lua 调 G.nukeArmUI）
--   核爆（nuke）：按镜头离多远、朝不朝着它——
--     ① 闪光：整个屏幕一下白（看着它的更白）、调色（先亮白、再橙、慢慢回来）、离得近还模糊几秒
--     ② 火球：白热的球一下胀到三百格，变黄、变橙、变暗红，往上升成蘑菇云的头
--     ③ 冲击波：一圈会折射的球壳（ForceField）冲出去，地面一圈扬起的尘土往外推几公里；冷凝云（威尔逊云）一闪
--     ④ 蘑菇云：烟柱 + 翻卷的云头（椭球 + 一圈粒子），一分多钟里升到一千七百格高；地上一圈底浪尘云、四处起火
--     ⑤ 声音按声速晚到（几公里外要等好几秒）、冲击波到的时候镜头猛震；近的屏幕闪几下雪花（电磁脉冲）
--   辐射区：对面的人在圈里有提示（服务器那边每秒掉血）
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Nuke = {}

function Nuke.init(G)
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local Map = G.Map
  local NC = (G.Config and G.Config.Nuke) or {}
  local function T(k, ...) return G.T(k, ...) end
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local exp, sin, cos, pi = math.exp, math.sin, math.cos, math.pi
  local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
  local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
  local function lerp(a, b, t) return a + (b - a) * t end
  local function nseq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = NSK(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  local function cseq(a, b) return ColorSequence.new({ CSK(0, a), CSK(1, b) }) end
  local TX = {
    smoke = "rbxasset://textures/particles/smoke_main.dds",
    fire = "rbxasset://textures/particles/fire_main.dds",
    core = "rbxasset://textures/particles/explosion01_core_main.dds",
  }
  local function myTeam() return (G.S and G.S.team) or me:GetAttribute("Side") or "atk" end
  local function groundAt(x, z) return math.max((Map.ground and Map.ground(x, z)) or Map.height(x, z), 0) end
  local function tween(o, t, props, style)
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
  end

  local folder = Instance.new("Folder")
  folder.Name = "NukeFx"
  folder.Parent = workspace

  local function part(shape, size, cf, col, mat, tr)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Size = size
    p.CFrame = cf
    p.Color = col
    p.Material = mat or Enum.Material.SmoothPlastic
    p.Transparency = tr or 0
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = folder
    return p
  end
  local function holder(cf) return part(nil, V(1, 1, 1), cf, RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1) end
  local function emitter(parent, o)
    local e = Instance.new("ParticleEmitter")
    e.Texture = o.tex or TX.smoke
    e.Rate = o.rate or 0
    e.Lifetime = NumberRange.new(o.life[1], o.life[2])
    e.Speed = NumberRange.new(o.spd[1], o.spd[2])
    e.SpreadAngle = Vector2.new(o.spread or 180, o.spread or 180)
    e.Size = o.size
    e.Transparency = o.tr
    e.Color = o.col
    e.LightEmission = o.le or 0
    e.LightInfluence = o.li or 0.5
    e.Acceleration = o.acc or V()
    e.Drag = o.drag or 0
    e.Rotation = NumberRange.new(0, 360)
    e.RotSpeed = NumberRange.new(-(o.rot or 12), o.rot or 12)
    e.EmissionDirection = o.dir or Enum.NormalId.Top
    e.ZOffset = o.z or 0
    e.Parent = parent
    return e
  end
  -- 画多少：自动画质低、手机少一半
  local function q(n) return math.max(1, math.floor(n * clamp(G.perfK or 1, 0.5, 1.1) * (G.mobile and 0.6 or 1) + 0.5)) end

  ---------------------------------------------------------------- 界面：警报条、闪光、雪花、解锁进度、辐射区提示

  local gui = Instance.new("ScreenGui")
  gui.Name = "NukeUI"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 40
  gui.Parent = me:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or RGB(0, 0, 0), tr or 0, 0
    if anchor then f.AnchorPoint = anchor end
    f.Parent = parent
    return f
  end
  local function label(parent, size, pos, ts, col, font, anchor)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UDim2.new()
    if anchor then l.AnchorPoint = anchor end
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3 = "", ts or 14, col or Color3.new(1, 1, 1)
    l.Font = font or Enum.Font.GothamMedium
    l.TextStrokeTransparency = 0.5
    l.Parent = parent
    return l
  end
  local RED, AMBER, WHITE = RGB(255, 70, 56), RGB(255, 186, 72), Color3.new(1, 1, 1)
  local banner = frame(gui, UDim2.fromOffset(560, 78), UDim2.new(0.5, 0, 0, 120), RGB(12, 4, 4), 0.25, Vector2.new(0.5, 0))
  banner.Visible = false
  local bLine = frame(banner, UDim2.new(1, 0, 0, 3), nil, RED, 0)
  local bLine2 = frame(banner, UDim2.new(1, 0, 0, 3), UDim2.new(0, 0, 1, -3), RED, 0)
  local bTitle = label(banner, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 8), 28, RED, Enum.Font.GothamBlack)
  local bSub = label(banner, UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 46), 15, WHITE, Enum.Font.GothamMedium)
  local flashF = frame(gui, UDim2.fromScale(1, 1), nil, WHITE, 1)
  flashF.ZIndex = 10
  local bars = {}
  for i = 1, 14 do
    local b = frame(gui, UDim2.new(1, 0, 0, 6), UDim2.fromScale(0, i / 15), RGB(220, 220, 220), 1)
    b.ZIndex = 9
    bars[i] = b
  end
  local armF = frame(gui, UDim2.fromOffset(300, 44), UDim2.new(0.5, 0, 0.7, 0), RGB(8, 6, 6), 0.35, Vector2.new(0.5, 0))
  armF.Visible = false
  local armL = label(armF, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 4), 15, AMBER, Enum.Font.GothamBold)
  local armBg = frame(armF, UDim2.new(1, -24, 0, 6), UDim2.new(0, 12, 1, -12), RGB(60, 40, 30), 0.2)
  local armBar = frame(armBg, UDim2.fromScale(0, 1), nil, RED, 0)
  local zoneL = label(gui, UDim2.fromOffset(420, 26), UDim2.new(0.5, 0, 0, 206), 18, RGB(200, 255, 120), Enum.Font.GothamBold, Vector2.new(0.5, 0))
  zoneL.Visible = false

  -- 按住发射键解锁（Fly.lua 每帧调：has 选的是核导弹、还有弹；k 按住了几成）
  local armSeen = 0
  function G.nukeArmUI(has, k)
    if not has then armF.Visible = false return end
    armSeen = os.clock()
    armF.Visible = true
    if k and k > 0.001 then
      armL.Text = T("nuke.arming", math.floor(clamp(k, 0, 1) * 100))
      armL.TextColor3 = RED
      armBar.Size = UDim2.fromScale(clamp(k, 0, 1), 1)
    else
      armL.Text = T("nuke.hold", G.mobile and T("nuke.btn") or "F")
      armL.TextColor3 = AMBER
      armBar.Size = UDim2.fromScale(0, 1)
    end
  end

  ---------------------------------------------------------------- 地上的圈（一段段亮条拼成：一个零件最长 2048 格，大圈画不下）

  local function ring(center, r, col, w, h, n, tr)
    local list = {}
    for i = 1, n do
      local am = (i - 0.5) / n * 2 * pi
      local x, z = center.X + cos(am) * r, center.Z + sin(am) * r
      local y = groundAt(x, z) + h / 2 + 0.5
      local len = 2 * r * sin(pi / n) + 1.5
      local pos = V(x, y, z)
      local p = part(nil, V(w, h, len), CFrame.lookAt(pos, pos + V(-sin(am), 0, cos(am))), col, Enum.Material.Neon, tr or 0.3)
      list[i] = p
    end
    return list
  end
  local function dropAll(list)
    for _, p in ipairs(list or {}) do p:Destroy() end
  end

  ---------------------------------------------------------------- 警报声：滴答声截一小段循环（一圈约 12 毫秒，嗡的一声），速度一高一低来回变——汽笛

  local siren = nil
  local function sirenOn(on)
    if on and not siren and G.makeSound and G.sndIds then
      local ok, snd = pcall(function()
        return (G.makeSound({ id = G.sndIds.TICK, vol = 0.55, s = { 3, 3 }, loop = { 0.008, 0.02 }, dist = 0.35, eq = { 0, 4, -6 } }, SoundService, {}))
      end)
      if ok then siren = snd end
    elseif not on and siren then
      local s0 = siren
      siren = nil
      tween(s0, 0.6, { Volume = 0 })
      Debris:AddItem(s0, 0.7)
    end
  end

  ---------------------------------------------------------------- 警报

  local warns = {}   -- { p, t0, eta, team, mine, rings, bb, pingT }
  local function clearWarn(W)
    dropAll(W.rings)
    if W.bb then W.bb:Destroy() end
    for i, x in ipairs(warns) do if x == W then table.remove(warns, i) break end end
    if #warns == 0 then sirenOn(false) end
  end
  local function nearestWarn(p)
    local best, bd = nil, math.huge
    for _, W in ipairs(warns) do
      local d = (W.p - p).Magnitude
      if d < bd then best, bd = W, d end
    end
    return best, bd
  end

  local function warn(e)
    if typeof(e.p) ~= "Vector3" then return end
    local mine = e.team == myTeam()
    local W = { p = e.p, t0 = os.clock(), eta = e.eta or 15, team = e.team, mine = mine, pingT = 0 }
    local col = mine and AMBER or RED
    W.rings = ring(e.p, e.r or NC.kill or 950, col, 9, 4, q(72), 0.25)
    for _, p in ipairs(ring(e.p, e.r2 or NC.hurt or 2000, col, 6, 3, q(96), 0.55)) do table.insert(W.rings, p) end
    -- 爆心标记
    local a = holder(CF(e.p + V(0, 30, 0)))
    table.insert(W.rings, a)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(220, 74)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.StudsOffset = V(0, 60, 0)
    bb.Adornee = a
    bb.Parent = me:WaitForChild("PlayerGui")
    local icon = label(bb, UDim2.new(1, 0, 0, 40), nil, 38, col, Enum.Font.GothamBlack)
    icon.Text = "☢"
    local tl = label(bb, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 44), 15, col, Enum.Font.GothamBold)
    W.bb, W.tl = bb, tl
    table.insert(warns, W)
    banner.Visible = true
    bTitle.Text = mine and T("nuke.launched") or T("nuke.incoming")
    bTitle.TextColor3 = col
    bLine.BackgroundColor3, bLine2.BackgroundColor3 = col, col
    if not mine then sirenOn(true) end
    if G.toast then G.toast(mine and T("nuke.launched") or T("nuke.incoming"), mine and "good" or "bad") end
  end

  local function dive(e)
    local W = typeof(e.p) == "Vector3" and nearestWarn(e.p) or warns[1]
    if not W then return end
    W.t0, W.eta = os.clock(), e.eta or 2
    if G.sfx and G.sndIds then   -- 俯冲：一声越来越尖的呼啸（按声速，远的听不见）
      local d = (W.p - cam.CFrame.Position).Magnitude
      if d < 9000 then
        G.sfx({ { id = G.sndIds.WIND, vol = 10, s = { 0.8, 0.9 }, reg = { 2, 6 }, eq = { 6, 8, 2 }, dist = 0.3, fade = 1 } }, nil, { vol = clamp(1.4 - d / 9000, 0.2, 1.2), must = true })
      end
    end
  end

  ---------------------------------------------------------------- 核爆

  local active = {}

  local function sound(d)
    if not (G.sfx and G.sndIds) then return end
    local S = G.sndIds
    local L = {}
    local real = G.realLayer and G.realLayer("boomL", 0.45, 2.4)
    if real then table.insert(L, real) end
    table.insert(L, { id = S.EXP, vol = 3, s = { 0.3, 0.34 }, eq = { 10, 0, -12 }, echo = { 0.5, 0.42, -6 } })
    table.insert(L, { id = S.EXP, vol = 2.6, s = { 0.2, 0.23 }, eq = { 10, -4, -20 }, delay = 0.3 })
    table.insert(L, { id = S.WIND, vol = 10, s = { 0.3, 0.34 }, reg = { 1, 9 }, eq = { 10, 0, -16 }, delay = 0.45, fade = 3 })
    local far = clamp(d / 20000, 0, 1)
    G.sfx(L, nil, { vol = clamp(1.6 - d / 22000, 0.45, 1.6), hiCut = -26 * far, delay = math.min(d / 960, 32), must = true })
  end

  local function glitch()
    local t0 = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
      local t = os.clock() - t0
      if t > 1.3 then
        for _, b in ipairs(bars) do b.BackgroundTransparency = 1 end
        conn:Disconnect()
        return
      end
      for _, b in ipairs(bars) do
        b.Position = UDim2.fromScale(0, math.random())
        b.Size = UDim2.new(1, 0, 0, math.random(2, 14))
        b.BackgroundTransparency = (math.random() < 0.55) and 1 or (0.35 + 0.5 * t)
      end
    end)
  end

  local function detonate(e)
    if typeof(e.p) ~= "Vector3" then return end
    local p = e.p
    local gy = e.gy or groundAt(p.X, p.Z)
    local W = nearestWarn(p)
    if W then
      W.det = os.clock()
      if W.tl then W.tl.Text = T("nuke.det") end
      task.delay(5, function() clearWarn(W) end)
    end
    sirenOn(false)
    task.delay(4, function() if #warns == 0 then banner.Visible = false end end)
    local cp = cam.CFrame.Position
    local d = (p - cp).Magnitude
    local look = cam.CFrame.LookVector:Dot((p - cp).Unit)
    local mine = e.team == myTeam()
    local desert = Map.desert
    local N = { p = p, gy = gy, t0 = os.clock(), parts = {}, d = d }

    -- ① 闪光、调色、模糊
    local kf = clamp(1.15 - d / 45000, 0.3, 1) * (0.45 + 0.55 * clamp(look, 0, 1))
    flashF.BackgroundTransparency = 1 - kf
    tween(flashF, 2.4, { BackgroundTransparency = 1 })
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "NukeCC"
    cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = 0.55 * kf, 0.25, -0.3, RGB(255, 246, 232)
    cc.Parent = Lighting
    N.cc, N.kf = cc, kf
    if d < 9000 and look > 0.3 then
      local bl = Instance.new("BlurEffect")
      bl.Size = 18 * kf
      bl.Parent = Lighting
      tween(bl, 3.5, { Size = 0 })
      Debris:AddItem(bl, 3.6)
    end
    if d < 6000 then glitch() end

    -- ② 火球、③ 冲击波球壳、冷凝云
    local function keep(x) table.insert(N.parts, x) return x end
    N.fb = keep(part(Enum.PartType.Ball, V(40, 40, 40), CF(p), RGB(255, 255, 245), Enum.Material.Neon, 0))
    N.shock = keep(part(Enum.PartType.Ball, V(10, 10, 10), CF(p), RGB(255, 255, 255), Enum.Material.ForceField, 0.15))
    N.wilson = keep(part(Enum.PartType.Ball, V(10, 10, 10), CF(p), RGB(236, 236, 240), Enum.Material.SmoothPlastic, 1))
    -- ④ 烟柱、云头（椭球：方块 + 球形网格）、云头里面的红光
    local dust = desert and RGB(168, 140, 104) or RGB(122, 106, 92)
    N.dust = dust
    N.stem = keep(part(Enum.PartType.Cylinder, V(10, 60, 60), CF(p) * CFrame.Angles(0, 0, pi / 2), dust, Enum.Material.SmoothPlastic, 1))
    local function ellipsoid(col, mat)
      local x = keep(part(nil, V(10, 10, 10), CF(p), col, mat, 1))
      local m = Instance.new("SpecialMesh")
      m.MeshType = Enum.MeshType.Sphere
      m.Parent = x
      return x
    end
    N.cap = ellipsoid(RGB(235, 120, 55), Enum.Material.SmoothPlastic)
    N.capGlow = ellipsoid(RGB(255, 110, 45), Enum.Material.Neon)
    -- 火球里翻卷的火（粒子：发光）
    emitter(N.fb, { tex = TX.core, rate = q(10), life = { 1.2, 2.2 }, spd = { 30, 90 }, size = nseq(0, 60, 0.5, 100, 1, 90), tr = nseq(0, 0.1, 0.7, 0.4, 1, 1),
      col = cseq(RGB(255, 236, 190), RGB(220, 80, 30)), le = 1, li = 0, rot = 40, z = 2 })
    -- 云头一圈：翻卷的烟（早期被火光照成橙色）
    N.capEm = {}
    local nCap = q(16)
    for i = 1, nCap do
      local h = keep(holder(CF(p)))
      local em = emitter(h, { rate = 3, life = { 8, 12 }, spd = { 6, 18 }, size = nseq(0, 70, 0.4, 100, 1, 100), tr = nseq(0, 0.6, 0.15, 0.25, 0.75, 0.35, 1, 1),
        col = cseq(RGB(190, 110, 70), RGB(96, 84, 76)), le = 0.35, li = 0.4, drag = 0.5, rot = 6, acc = V(0, 3, 0) })
      N.capEm[i] = { h = h, em = em, a = (i - 1) / nCap * 2 * pi }
    end
    N.topEm = {}
    for i = 1, q(5) do
      local h = keep(holder(CF(p)))
      local em = emitter(h, { rate = 2.5, life = { 9, 13 }, spd = { 4, 12 }, size = nseq(0, 80, 0.5, 100, 1, 100), tr = nseq(0, 0.6, 0.2, 0.3, 0.8, 0.4, 1, 1),
        col = cseq(RGB(176, 120, 90), RGB(104, 92, 84)), le = 0.25, li = 0.4, drag = 0.5, rot = 5 })
      N.topEm[i] = { h = h, em = em, a = i * 1.7, k = (i == 1) and 0 or 0.45 }
    end
    -- 烟柱上的尘烟
    N.stemEm = {}
    for i = 1, q(6) do
      local h = keep(holder(CF(p)))
      local em = emitter(h, { rate = 4, life = { 5, 8 }, spd = { 20, 45 }, spread = 25, size = nseq(0, 60, 1, 100), tr = nseq(0, 0.6, 0.3, 0.35, 1, 1),
        col = cseq(dust, dust:Lerp(RGB(80, 74, 70), 0.4)), li = 0.5, acc = V(0, 18, 0), rot = 10 })
      em.Enabled = false
      N.stemEm[i] = { h = h, em = em, k = (i - 0.5) / 6 }
    end
    -- 冲击波推起的一圈尘土（往外几公里）
    N.surge = {}
    for i = 1, q(24) do
      local h = keep(holder(CF(p)))
      local a = (i - 1) / q(24) * 2 * pi
      local em = emitter(h, { rate = 10, life = { 2, 3 }, spd = { 10, 40 }, spread = 60, size = nseq(0, 40, 1, 100), tr = nseq(0, 0.3, 0.4, 0.4, 1, 1),
        col = cseq(dust:Lerp(WHITE, 0.15), dust), li = 0.6, acc = V(0, 10, 0), rot = 15 })
      N.surge[i] = { h = h, em = em, a = a }
    end
    -- 底浪：贴地的一大圈尘云，慢慢往外扩、留很久
    N.base = {}
    for i = 1, q(18) do
      local h = keep(holder(CF(p)))
      local a = (i - 1) / q(18) * 2 * pi
      local em = emitter(h, { rate = 2.2, life = { 10, 15 }, spd = { 5, 15 }, spread = 70, size = nseq(0, 80, 0.5, 100, 1, 100), tr = nseq(0, 0.7, 0.2, 0.35, 0.8, 0.45, 1, 1),
        col = cseq(dust, dust:Lerp(RGB(70, 64, 60), 0.3)), li = 0.6, drag = 0.3, rot = 5, acc = V(0, 1.5, 0) })
      em.Enabled = false
      N.base[i] = { h = h, em = em, a = a + (math.random() - 0.5) * 0.2, k = 0.7 + math.random() * 0.6 }
    end
    -- 四处起火
    for _ = 1, q(12) do
      local a, r = math.random() * 2 * pi, 120 + math.random() * 580
      local x, z = p.X + cos(a) * r, p.Z + sin(a) * r
      local h = keep(holder(CF(x, groundAt(x, z) + 2, z)))
      emitter(h, { tex = TX.fire, rate = 8, life = { 1, 2 }, spd = { 6, 16 }, spread = 25, size = nseq(0, 20, 0.4, 40, 1, 10), tr = nseq(0, 0.2, 1, 1),
        col = cseq(RGB(255, 200, 110), RGB(255, 80, 30)), le = 1, li = 0, acc = V(0, 12, 0) })
      emitter(h, { rate = 1.5, life = { 6, 9 }, spd = { 6, 12 }, spread = 20, size = nseq(0, 30, 1, 100), tr = nseq(0, 0.5, 1, 1),
        col = cseq(RGB(40, 36, 34), RGB(90, 86, 82)), li = 0.5, acc = V(1, 8, 0.5) })
    end

    -- ⑤ 声音、冲击波到了镜头一震
    sound(d)
    local tShock = d / 1000
    if d < 26000 then
      task.delay(tShock, function()
        local k = clamp(1.25 - d / 8000, 0.1, 1)
        if G.shake then G.shake(k) end
        task.delay(0.45, function() if G.shake then G.shake(k * 0.35) end end)
      end)
    end
    -- 辐射区（服务器那边在掉血）：画一圈淡黄绿
    local FO = NC.fallout or {}
    if (FO.dur or 0) > 0 then
      local zr = ring(V(p.X, gy, p.Z), FO.r or 420, RGB(190, 255, 90), 5, 2.5, q(48), 0.55)
      N.zone = { list = zr, t1 = os.clock() + FO.dur, r = FO.r or 420, c = V(p.X, gy, p.Z), hurt = not mine }
    end
    table.insert(active, N)
  end

  -- 每帧摆核爆的各部分（t：爆了几秒）
  local function stepNuke(N, t)
    local p, gy = N.p, N.gy
    -- 云头的高度、半径（一分钟里升到 gy + 1790）
    local hc = gy + 140 + 1650 * (1 - exp(-t / 20))
    local Rc = 240 + 460 * (1 - exp(-t / 14))
    local Hc = Rc * 0.62
    -- 火球
    if N.fb then
      if t > 10 then
        N.fb:Destroy()
        N.fb = nil
      else
        local r = 300 * (1 - exp(-t / 0.25)) + 10 * math.max(0, t - 3)
        local y = lerp(p.Y, hc, smooth(0.6, 7, t))
        N.fb.Size = V(2 * r, 2 * r, 2 * r)
        N.fb.CFrame = CF(p.X, y, p.Z)
        local c
        if t < 0.25 then c = RGB(255, 255, 245)
        elseif t < 1 then c = RGB(255, 255, 245):Lerp(RGB(255, 232, 160), (t - 0.25) / 0.75)
        elseif t < 3 then c = RGB(255, 232, 160):Lerp(RGB(255, 160, 64), (t - 1) / 2)
        elseif t < 6 then c = RGB(255, 160, 64):Lerp(RGB(214, 84, 34), (t - 3) / 3)
        else c = RGB(214, 84, 34):Lerp(RGB(110, 42, 24), (t - 6) / 4) end
        N.fb.Color = c
        N.fb.Transparency = (t < 2) and 0 or clamp((t - 2) / 8, 0, 1) ^ 1.4
      end
    end
    -- 冲击波球壳（零件最大 2048：半径到 1020 就收掉，后面靠地上那圈尘土）
    if N.shock then
      if t > 1.15 then
        N.shock:Destroy()
        N.shock = nil
      else
        local r = math.min(1020, 1150 * t ^ 0.85 + 20)
        N.shock.Size = V(2 * r, 2 * r, 2 * r)
        N.shock.Transparency = 0.15 + 0.85 * (t / 1.15)
      end
    end
    -- 冷凝云：冲击波过后空气里一下凝出的白雾
    if N.wilson then
      if t > 2.8 then
        N.wilson:Destroy()
        N.wilson = nil
      elseif t > 0.35 then
        local r = math.min(1000, 320 + 680 * (t - 0.35) / 1.3)
        N.wilson.Size = V(2 * r, 1.3 * r, 2 * r)
        N.wilson.CFrame = CF(p.X, p.Y + 40, p.Z)
        N.wilson.Transparency = (t < 0.7) and lerp(1, 0.6, (t - 0.35) / 0.35) or lerp(0.6, 1, (t - 0.7) / 2.1)
      end
    end
    -- 云头、红光
    local capA = smooth(2.2, 6, t)
    N.cap.Size = V(2 * Rc, Hc, 2 * Rc)
    N.cap.CFrame = CF(p.X, hc, p.Z)
    N.cap.Transparency = 1 - capA * 0.86
    local cc0 = (t < 14) and RGB(235, 120, 55):Lerp(RGB(92, 76, 66), smooth(3, 14, t)) or RGB(92, 76, 66):Lerp(RGB(112, 100, 92), smooth(14, 60, t))
    N.cap.Color = cc0
    local gA = smooth(2.2, 4, t) * (1 - smooth(6, 26, t))
    N.capGlow.Size = V(1.56 * Rc, Hc * 0.72, 1.56 * Rc)
    N.capGlow.CFrame = CF(p.X, hc - Hc * 0.08, p.Z)
    N.capGlow.Transparency = 1 - gA * 0.65
    for _, c in ipairs(N.capEm) do
      local a = c.a + t * 0.05
      c.h.CFrame = CF(p.X + cos(a) * Rc * 0.86, hc - Hc * 0.1, p.Z + sin(a) * Rc * 0.86)
      c.em.Enabled = t > 2 and t < 75
      c.em.LightEmission = 0.35 * (1 - smooth(5, 20, t))
    end
    for _, c in ipairs(N.topEm) do
      c.h.CFrame = CF(p.X + cos(c.a) * Rc * c.k, hc + Hc * 0.3, p.Z + sin(c.a) * Rc * c.k)
      c.em.Enabled = t > 2.5 and t < 75
      c.em.LightEmission = 0.25 * (1 - smooth(5, 20, t))
    end
    -- 烟柱
    local top = hc - Hc * 0.3
    local sr = 50 + 70 * smooth(1.5, 25, t)
    local sh = math.max(10, top - gy)
    N.stem.Size = V(math.min(sh, 2048), 2 * sr, 2 * sr)
    N.stem.CFrame = CF(p.X, gy + math.min(sh, 2048) / 2, p.Z) * CFrame.Angles(0, 0, pi / 2)
    N.stem.Transparency = 1 - smooth(1.5, 5, t) * 0.72 * (1 - smooth(60, 90, t))
    for _, c in ipairs(N.stemEm) do
      c.h.CFrame = CF(p.X, gy + sh * c.k, p.Z)
      c.em.Enabled = t > 1.5 and t < 70
    end
    -- 冲击波推起的尘土圈
    local rr = 1150 * t ^ 0.8
    for _, c in ipairs(N.surge) do
      local x, z = p.X + cos(c.a) * rr, p.Z + sin(c.a) * rr
      c.h.CFrame = CF(x, groundAt(x, z) + 18, z)
      c.em.Enabled = t > 0.15 and t < 4.5
    end
    -- 底浪
    local br = 500 + 700 * smooth(1, 20, t)
    for _, c in ipairs(N.base) do
      local x, z = p.X + cos(c.a) * br * c.k, p.Z + sin(c.a) * br * c.k
      c.h.CFrame = CF(x, groundAt(x, z) + 30, z)
      c.em.Enabled = t > 1.2 and t < 40
    end
    -- 调色：先亮白、再偏橙，二十多秒慢慢回来
    if N.cc then
      if t > 24 then
        N.cc:Destroy()
        N.cc = nil
      else
        local kf = N.kf
        N.cc.Brightness = 0.55 * kf * exp(-t / 0.6) + 0.1 * kf * exp(-t / 6)
        N.cc.Contrast = 0.25 * exp(-t / 2)
        N.cc.Saturation = -0.3 * exp(-t / 3)
        local tc = (t < 1) and RGB(255, 246, 232):Lerp(RGB(255, 200, 156), t) or RGB(255, 200, 156):Lerp(WHITE, smooth(1, 20, t))
        N.cc.TintColor = tc
      end
    end
    return t < 95
  end

  local function cleanup(N)
    for _, x in ipairs(N.parts) do if x.Parent then x:Destroy() end end
    if N.cc then N.cc:Destroy() end
    if N.zone then dropAll(N.zone.list) end
  end

  -- 服务器来的事件（Fx.lua 转过来）
  function G.nukeEvent(e)
    if e.k == "nukeWarn" then warn(e)
    elseif e.k == "nukeDive" then dive(e)
    elseif e.k == "nuke" then detonate(e)
    elseif e.k == "nukeIgn" then
      -- 助推器点火：近处听得到一声沉闷的点火（远处的只看见尾焰）
      local d = typeof(e.p) == "Vector3" and (e.p - cam.CFrame.Position).Magnitude or 1e9
      if d < 4000 and G.sfx then G.sfx("msl", e.p, { vol = 1.6, must = true }) end
    end
  end
  G.nukeActive = function() return #active, #warns end   -- 测试用

  ---------------------------------------------------------------- 每帧

  local pulse = 0
  RunService.RenderStepped:Connect(function(dt)
    local t = os.clock()
    if armF.Visible and t - armSeen > 0.3 then armF.Visible = false end
    -- 警报：倒计时、圈一闪一闪、汽笛一高一低、小地图上爆心一闪
    pulse += dt
    local blink = 0.5 + 0.5 * sin(pulse * 6)
    local anyLive = false
    for _, W in ipairs(warns) do
      if not W.det then
        anyLive = true
        local left = math.max(0, W.eta - (t - W.t0))
        if W.tl then W.tl.Text = T("nuke.tag") .. " · " .. string.format("%.0f", left) end
        for i, pr in ipairs(W.rings) do
          if pr:IsA("BasePart") and pr.Material == Enum.Material.Neon then pr.Transparency = ((i % 2 == 0) and 0.2 or 0.35) + 0.4 * blink end
        end
        if not W.mine and G.radarShot and t - W.pingT > 0.8 then
          W.pingT = t
          G.radarShot(W.p, W.team)
        end
        bSub.Text = W.mine and T("nuke.launchedSub", string.format("%.0f", left)) or T("nuke.incomingSub", string.format("%.0f", left))
      end
    end
    if banner.Visible and anyLive then banner.BackgroundTransparency = 0.15 + 0.2 * blink end
    if siren then siren.PlaybackSpeed = 2.7 + 1.3 * (0.5 + 0.5 * sin(t * 2.2)) end
    -- 核爆
    for i = #active, 1, -1 do
      local N = active[i]
      local ok, more = pcall(stepNuke, N, t - N.t0)
      if not ok or not more then
        cleanup(N)
        table.remove(active, i)
      end
    end
    -- 辐射区提示（只有对面的人在里面挨烧）
    local inZone = false
    local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    for _, N in ipairs(active) do
      local Z = N.zone
      if Z then
        if t > Z.t1 then
          dropAll(Z.list)
          N.zone = nil
        elseif Z.hurt and hrp then
          local dd = hrp.Position - Z.c
          if dd.X * dd.X + dd.Z * dd.Z < Z.r * Z.r then inZone = true end
        end
      end
    end
    zoneL.Visible = inZone
    if inZone then zoneL.Text = "☢ " .. T("nuke.fallout") end
  end)
end

return Nuke
