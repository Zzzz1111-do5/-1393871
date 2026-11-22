-- Roblox全面大战场——夜视仪（客户端）：现在有昼夜更替（DayNight.lua），天黑了出生自动打开；步兵、飞行员按 N 开关夜视（手机右边一个小按钮）
--   开着：整个画面都是夜视（本地增亮、绿色荧光调色、灯光强烈泛光、雾变淡一点看得更远、画面轻微闪烁；用户：要全屏的夜视，不要望远镜那样四周一圈黑）；
--     队友头盔后面的红外频闪一闪一闪（只有夜视里看得见）；镜筒翻下来（服务器改焊接，别人也看得到）
--   坐进载具（车、飞机、直升机、船、炮位）照样开着（用户：进载具夜视不要取消）；地面载具里 N 照样开关夜视仪
--     （用户 11-21：坦克里强制锁着夜视仪视角——原来地面载具里 N 整个让给瞄准镜，关不掉），开着车上的瞄准镜时 N 才是切瞄准镜的光电档（Drive.lua），
--   开飞机时 N 在 夜视 → 热成像 → 关 之间切（热成像在 AirHud.lua；用户 11-19：不用光电吊舱也可以开红外视角），
--     开着车上的瞄准镜看时夜视仪先让出画面（瞄准镜有自己的调色，叠在一起热成像会发绿、过亮），退出瞄准镜自动恢复；死了关掉
--   默认开着（用户：视野不管是在什么情况默认夜视仪都是开着的）：每次出生自动打开；按 N 关掉的话这一条命里关着，下次出生又是开的；
--   车上瞄准镜：天黑默认热成像（白热）档、白天默认昼光档，自己换过就记住（白天、夜里各记一个，Drive.lua）
--   地面载具里（用户 11-22：「坦克第三人称不光夜视，还要加一个红外，第一人称也是」）：N 在 夜视 → 热成像（白热）→ 关 之间切（同飞机），
--     第三人称、车里第一人称都是整个画面；下车自动关掉热成像、夜视仪照常开着
--   车里的观瞄设备（辅助瞄准镜、潜望镜、CROWS、车长热像仪……Interior.lua）开着时：夜视仪的绿色调色让开（用户 11-22：「坦克第一人称视角开镜有时候会是绿色的」），
--     增亮还留着（夜里昼光镜也看得见东西）；那些设备自己有昼光 / 夜视 / 热成像的样子
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Night = {}

function Night.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local on = false
  local fx = {}

  ---------------------------------------------------------------- 开关

  -- 夜视的画面效果加上 / 撤掉（开着夜视仪、但正在看车上的瞄准镜时撤掉，on 不变）；grade = false：只留增亮、绿色调色和泛光让开（车里的观瞄设备）
  local fxOn, gradeOn = false, false
  local function fxGrade(g)
    gradeOn = g
    local cc, bl = fx[1], fx[2]
    if cc then cc.Enabled = g end
    if bl then bl.Enabled = g end
    if fx[3] and not g then fx[3].Enabled = false end   -- 轻模糊：开着时按画质在每帧里开关
    if not g then G.irStrobes(false) end
  end
  local function fxApply(want, grade)
    if want ~= fxOn then fxOn = want else
      if fxOn and (grade ~= false) ~= gradeOn then fxGrade(grade ~= false) end
      return
    end
    if want then
      -- 增亮、环境光、大气变淡交给昼夜（DayNight.lua 每次更新时按 G.nvLight 加上去：白天开夜视只亮一点点）
      G.nvLight = true
      local cc = Instance.new("ColorCorrectionEffect")
      cc.Name = "NVGrade"
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.32, 0.04, RGB(120, 255, 158)
      cc.Parent = Lighting
      local bl = Instance.new("BloomEffect")
      bl.Name = "NVBloom"
      bl.Intensity, bl.Size, bl.Threshold = 1.8, 30, 0.82
      bl.Parent = Lighting
      local blur = Instance.new("BlurEffect")
      blur.Name = "NVBlur"
      blur.Size = 1.5
      blur.Parent = Lighting
      fx = { cc, bl, blur }
      fxGrade(grade ~= false)
    else
      for _, e in ipairs(fx) do e:Destroy() end
      fx = {}
      gradeOn = false
      G.nvLight = false
      G.irStrobes(false)
    end
  end
  -- 正在看车上的瞄准镜（它有自己的昼光 / 夜视 / 热成像调色）：夜视仪先让出画面
  local function held() return G.sightCC ~= nil and G.sightCC.Enabled end
  -- 车里的观瞄设备开着（Interior.lua）：绿色调色让开、增亮留着
  local function heldOptic() return G.interiorOptic ~= nil end

  local function setOn(v)
    if v == on then return end
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if v and not (hum and hum.Health > 0) then return end   -- 没出生（部署界面、主菜单）不开
    on = v
    pcall(function() G.R.Act:FireServer("nvg", on) end)
    fxApply(on and not held(), not heldOptic())
    if on and G.playSound then G.playSound("quiet", nil, 2.4) end
  end
  G.nvgOn = function() return on end
  G.setNvg = setOn

  ---------------------------------------------------------------- 提示：出生后、坐上飞机或船时夜视没开，屏幕下方淡入一行「按 N 开启夜视」，十秒后淡出（用户：提示一下按 N 开启夜视）

  local hintGui = Instance.new("ScreenGui")
  hintGui.Name = "NVHint"
  hintGui.ResetOnSpawn = false
  hintGui.IgnoreGuiInset = true
  hintGui.DisplayOrder = 3
  hintGui.Parent = me:WaitForChild("PlayerGui")
  local hint = Instance.new("TextLabel")
  hint.Name = "Hint"
  hint.AnchorPoint = Vector2.new(0.5, 1)
  hint.Position = UDim2.new(0.5, 0, 1, -168)
  hint.Size = UDim2.fromOffset(240, 30)
  hint.BackgroundColor3 = RGB(10, 12, 12)
  hint.BackgroundTransparency = 1
  hint.TextColor3 = RGB(186, 255, 196)
  hint.TextTransparency = 1
  hint.Font = Enum.Font.GothamMedium
  hint.TextSize = 15
  hint.Visible = false
  hint.Parent = hintGui
  local hc = Instance.new("UICorner")
  hc.CornerRadius = UDim.new(0, 4)
  hc.Parent = hint
  local hintUntil, hideAt = 0, nil
  local function showHint(sec)
    if on then return end
    local key = UIS.TouchEnabled and not UIS.KeyboardEnabled and "nvg.hintTouch" or "nvg.hint"
    hint.Text = (G.T and G.T(key)) or "按 N 开启夜视"
    hint.Visible = true
    hintUntil, hideAt = os.clock() + (sec or 10), nil
    TweenService:Create(hint, TweenInfo.new(0.4), { TextTransparency = 0, BackgroundTransparency = 0.45 }):Play()
  end
  local function hideHint()
    if not hint.Visible or hideAt then return end
    hintUntil, hideAt = 0, os.clock() + 0.5   -- 淡出半秒后收起
    TweenService:Create(hint, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
  end
  G.nvgHint = showHint
  local function onChar(ch)
    -- 出生自动打开夜视（等人物的 Humanoid 到了；最多等 10 秒）
    -- 服务器给人戴夜视仪（头盔上的 NVG）可能比 Humanoid 晚到：到了再把开着的状态发一遍，别人那边镜筒才翻得下来
    ch.ChildAdded:Connect(function(c)
      if c.Name == "NVG" and on and me.Character == ch then pcall(function() G.R.Act:FireServer("nvg", true) end) end
    end)
    task.spawn(function()
      local hum = ch:WaitForChild("Humanoid", 10)
      ch:WaitForChild("NVG", 3)
      for _ = 1, 40 do
        if not ch.Parent or not hum or hum.Health <= 0 then return end
        if me.Character == ch then
          -- 昼夜更替以后：天黑了才自动打开（白天出生不开）；白天开着的到天亮了不关，玩家自己按 N
          if G.isNight and not G.isNight() then break end
          setOn(true)
          if on then break end
        end
        task.wait(0.25)
      end
    end)
    task.delay(2.5, function()   -- 万一没开（自己按 N 关了）：出生、部署界面关掉以后再提示（只在天黑时）
      local hum = ch and ch.Parent and ch:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 and not on and not (G.isNight and not G.isNight()) then showHint(10) end
    end)
  end
  me.CharacterAdded:Connect(onChar)
  if me.Character then onChar(me.Character) end
  local wasAir = false
  RunService.Heartbeat:Connect(function()
    if on then hideHint()
    elseif hintUntil ~= 0 and os.clock() > hintUntil then hideHint() end
    if hideAt and os.clock() > hideAt then hint.Visible, hideAt = false, nil end
    local air = (G.fly ~= nil) or (G.sail ~= nil) or (G.drive ~= nil)   -- 坐上飞机、船、车：夜视没开就提示按 N
    if air and not wasAir and not (G.isNight and not G.isNight()) then showHint(8) end   -- 白天不提示
    wasAir = air
  end)

  -- 队友（真人）头盔后面的红外频闪：夜视里每 0.8 秒闪一下（本地改透明度，别人那边不变）
  local irT = 0
  function G.irStrobes(show)
    local side = me:GetAttribute("Side")
    local blink = show and (os.clock() % 0.8) < 0.09
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local ir = ch and ch:FindFirstChild("IRStrobe")
      if ir then
        local mine = pl:GetAttribute("Side") == side
        local tr = (show and mine and blink) and 0 or 1
        if ir.Transparency ~= tr then ir.Transparency = tr end
      end
    end
  end

  function G.nvgToggle()
    if G.drive and not G.fly and not G.sail and G.drive.sight then return end   -- 开着车上的瞄准镜：N 是切瞄准镜的光电档（Drive.lua）
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    -- 开地面载具（用户 11-22：坦克第三人称、第一人称都要有红外）：N 在 夜视 → 热成像（下面 vehThermal，白热）→ 关 之间切
    if G.drive and not G.fly and not G.sail then
      if on then
        setOn(false)
        G.vehThermal(true)
      elseif G.vehThermal() then
        G.vehThermal(false)
      else
        setOn(true)
      end
      return
    end
    -- 开飞机（用户 11-19：不用光电吊舱也可以开红外视角）：N 在 夜视 → 热成像（AirHud.lua，白热） → 关 之间切
    if G.fly and G.airThermal then
      if on then
        setOn(false)
        G.airThermal(true)
      elseif G.airThermal() then
        G.airThermal(false)
      else
        setOn(true)
      end
      return
    end
    setOn(not on)
  end
  UIS.InputBegan:Connect(function(io, gp)
    if not gp and io.KeyCode == Enum.KeyCode.N then G.nvgToggle() end
  end)
  local vehicleTouch
  if UIS.TouchEnabled then   -- 步兵按键由 Play.lua 排版；飞行和航行继续用各自的夜视入口。
    vehicleTouch = G.ui.button(G.gui:WaitForChild("Hud"), "NV", UDim2.fromOffset(52, 44), UDim2.new(1, -78, 0, 140), RGB(24, 28, 30))
    vehicleTouch.Name = "VehicleNightVision"
    vehicleTouch.Visible = false
    vehicleTouch.BackgroundTransparency = 0.35
    vehicleTouch.TextSize = 14
    vehicleTouch.Activated:Connect(G.nvgToggle)
  end

  ---------------------------------------------------------------- 地面载具的热成像（白热）：整个画面（第三人称、车里第一人称都是）
  --   背景压暗、去色，车、船、飞机、小兵（View.lua 画的，一个高亮）和最近的 24 个别的玩家发白光；扫描线、雪花、四边压暗（同飞机的，AirHud.lua）
  --   开着车上的瞄准镜、车里的观瞄设备时让出画面（它们自己有热成像档）；下车关掉，夜视仪照常开着（天黑）
  local vir, virShown, virT, virNoiseT = false, false, 0, 0
  local virGui = Instance.new("ScreenGui")
  virGui.Name = "VehIr"
  virGui.ResetOnSpawn = false
  virGui.IgnoreGuiInset = true
  virGui.DisplayOrder = 2   -- 压在画面上、界面下面
  virGui.Enabled = false
  virGui.Parent = me:WaitForChild("PlayerGui")
  local function virImg(name, size, tr)
    local l = Instance.new("ImageLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size = size
    l.ImageColor3, l.ImageTransparency = Color3.new(1, 1, 1), tr
    l.ScaleType = Enum.ScaleType.Tile
    l.Parent = virGui
    return l
  end
  local virScan = virImg("VehScanlines", UDim2.fromScale(1, 1), 0.25)
  virScan.ImageColor3 = Color3.new(0, 0, 0)
  virScan.TileSize = UDim2.fromOffset(4, 4)
  local virNoise = virImg("VehNoise", UDim2.new(1, 256, 1, 256), 0.4)
  virNoise.TileSize = UDim2.fromOffset(128, 128)
  for _, e in ipairs({ { Vector2.new(0, 0), UDim2.fromScale(1, 0.3), 90 }, { Vector2.new(0, 1), UDim2.fromScale(1, 0.3), -90 },
    { Vector2.new(0, 0), UDim2.fromScale(0.22, 1), 0 }, { Vector2.new(1, 0), UDim2.fromScale(0.22, 1), 180 } }) do   -- 四边压暗
    local f = Instance.new("Frame")
    f.AnchorPoint = e[1]
    f.Position = UDim2.fromScale(e[1].X, e[1].Y)
    f.Size = e[2]
    f.BackgroundColor3 = Color3.new(0, 0, 0)
    f.BackgroundTransparency = 0.35
    f.BorderSizePixel = 0
    local g = Instance.new("UIGradient")
    g.Rotation = e[3]
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = f
    f.Parent = virGui
  end
  local virTag = Instance.new("TextLabel")   -- 左上角一个小字：WHT（白热）
  virTag.Name = "Mode"
  virTag.BackgroundTransparency = 1
  virTag.Position = UDim2.fromOffset(18, 64)
  virTag.Size = UDim2.fromOffset(160, 18)
  virTag.Font = Enum.Font.Code
  virTag.TextSize = 14
  virTag.TextXAlignment = Enum.TextXAlignment.Left
  virTag.TextColor3 = RGB(235, 238, 238)
  virTag.Text = "IR  WHT"
  virTag.Parent = virGui
  local virCC = Instance.new("ColorCorrectionEffect")
  virCC.Name = "VehIrCC"
  virCC.Enabled = false
  virCC.Saturation, virCC.Contrast, virCC.Brightness, virCC.TintColor = -1, 0.42, -0.12, RGB(236, 238, 238)
  virCC.Parent = Lighting
  local virHl = {}
  local function virHlClear()
    for _, h in ipairs(virHl) do h:Destroy() end
    virHl = {}
  end
  local function virHlAdd(a)
    local h = Instance.new("Highlight")
    h.FillColor, h.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
    h.FillTransparency, h.OutlineTransparency = 0.12, 0.65
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Adornee = a
    h.Parent = workspace.CurrentCamera
    table.insert(virHl, h)
  end
  local function virHlRefresh()   -- 一个给所有实体的样子，再给最近的 24 个别的玩家（Highlight 同时最多画 31 个）
    virHlClear()
    if G.viewFolder then virHlAdd(G.viewFolder) end
    local cam = workspace.CurrentCamera
    local cp = cam and cam.CFrame.Position or Vector3.zero
    local list = {}
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      if pl ~= me and hrp then table.insert(list, { ch, (hrp.Position - cp).Magnitude }) end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, math.min(24, #list) do virHlAdd(list[i][1]) end
  end
  local virArt = nil
  local function virApply(want)
    if want == virShown then return end
    virShown = want
    if want and virArt == nil then
      virArt = G.hudIconOn ~= nil and G.hudIconOn(virScan, "scanTex") == true and G.hudIconOn(virNoise, "noiseTex") == true
    end
    virScan.Visible, virNoise.Visible = virArt == true, virArt == true
    virGui.Enabled = want
    virCC.Enabled = want
    if want then
      virHlRefresh()
      virT = 0
      G.nvLight = true   -- 夜里也要看得见地面：跟夜视一样让昼夜（DayNight.lua）增亮
    else
      virHlClear()
      if not fxOn and not (G.airThermalShown and G.airThermalShown()) then G.nvLight = false end
    end
  end
  -- 开 / 关（不带参数：现在开着没有）
  function G.vehThermal(v)
    if v == nil then return vir end
    vir = v == true
    if not vir then virApply(false) end
    if vir and G.toast then G.toast(G.T and G.T("air.irOn") or "热成像", "info") end
    return vir
  end
  G.vehThermalShown = function() return virShown end   -- 测试用
  G.frameConn("VehIr", function(dt)
    if vir then
      local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
      if not G.drive or G.fly or G.sail or not hum or hum.Health <= 0 then   -- 下车、死了：关掉，夜视仪照常（天黑）
        vir = false
        virApply(false)
        if hum and hum.Health > 0 and not (G.isNight and not G.isNight()) then setOn(true) end
        return
      end
    end
    virApply(vir and not held() and not heldOptic())
    if not virShown then return end
    virT += dt
    if virT > 0.5 then virT = 0 virHlRefresh() end   -- 别的玩家走近走远：半秒重挑一次
    local t = os.clock()
    if t - virNoiseT > 0.05 then   -- 雪花一闪一闪
      virNoiseT = t
      virNoise.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
    end
  end)

  G.frameConn("Night", function(dt)
    if vehicleTouch then vehicleTouch.Visible = (G.fly ~= nil or G.sail ~= nil or (G.drive ~= nil and not G.drive.sight)) and not (G.menuOpen and G.menuOpen()) end
    if not on then return end
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then setOn(false) return end
    fxApply(not held(), not heldOptic())   -- 坐进载具照样开着；看车上的瞄准镜时让出画面，退出来再加上；车里的观瞄设备开着只让开调色
    if not fxOn or not gradeOn then return end
    local cc = fx[1]
    if cc then cc.Brightness = 0.04 + (math.random() - 0.5) * 0.018 end   -- 增像管的轻微闪烁
    -- 夜视一直开着（夜战）：画面卡（自动画质 G.perfK 降下来）先关那层全屏的轻模糊，泛光收小一点
    local blur, bl = fx[3], fx[2]
    local hi = (G.perfK or 1) >= 0.8
    if blur and blur.Enabled ~= hi then blur.Enabled = hi end
    if bl then
      local sz = hi and 30 or 18
      if bl.Size ~= sz then bl.Size = sz end
    end
    irT += dt
    if irT > 0.05 then
      irT = 0
      G.irStrobes(true)
    end
  end)

  ---------------------------------------------------------------- 地图上会动的灯（服务器摆的零件带 Anim 属性）：blink 每秒闪 Spd 下、spin 绕 Pivot 转（灯塔光柱，Spd 圈 / 秒）

  ---------------------------------------------------------------- 光晕分级（用户：游戏非常卡顿）
  -- 地图上每盏灯（跑道灯、舰灯、营地灯，World.light）带一个 BillboardGui 光晕，全图 600 多个、6000 格内都在画——
  --   一个光晕就是一组界面（两块圆角方块），几百个一起画很费。按离镜头的距离分级：450 格内全亮，1100 格内亮一半，
  --   2400 格内亮四分之一（按黄金分割挑，跑道灯照样连成线，只是稀一点），再远的关掉（霓虹灯块本身和泛光还在）；
  --   画面卡（G.perfK 低）距离一起缩；同时亮着的超过 GLOW_CAP 就再缩一点。闪烁的灯灭的那一下也关着（下面 anim 用 glowDark）
  local GLOW_CAP = 150
  local glows, glowSeen, glowDark, glowAllow = {}, {}, {}, {}   -- glowSeen[光晕] = 它的记录
  local glowScale, glowAcc = 1, 0
  local function addGlow(g)
    if glowSeen[g] or not g:IsA("BillboardGui") or g.Name ~= "Glow" then return end
    local p = g.Parent
    if not (p and p:IsA("BasePart")) then return end
    local i = #glows + 1
    glows[i] = { g = g, p = p, r = (i * 0.6180339887) % 1, on = g.Enabled }
    glowSeen[g] = glows[i]
  end
  local function stepGlows()
    local cam = workspace.CurrentCamera
    if not cam or #glows == 0 then return end
    local cp = cam.CFrame.Position
    local k = math.clamp(G.perfK or 1, 0.55, 1.2) / glowScale
    local d1, d2, d3 = 450 * k, 1100 * k, 2400 * k
    local n, j = 0, 0
    for idx = 1, #glows do
      local x = glows[idx]
      if x.g.Parent == x.p and x.p.Parent then
        j += 1
        glows[j] = x
        local dv = x.p.CFrame.Position - cp   -- CFrame.Position：跟 Position 一样，测试台也认
        local dd = dv:Dot(dv)
        local allow = dd < d1 * d1 or (dd < d2 * d2 and x.r < 0.5) or (dd < d3 * d3 and x.r < 0.25)
        glowAllow[x.g] = allow
        if allow then n += 1 end
        local want = allow and not glowDark[x.g]
        if x.on ~= want then
          x.on = want
          x.g.Enabled = want
        end
      else
        glowSeen[x.g], glowDark[x.g], glowAllow[x.g] = nil, nil, nil
      end
    end
    for idx = #glows, j + 1, -1 do glows[idx] = nil end
    if n > GLOW_CAP then glowScale = math.min(4, glowScale * 1.15)
    elseif n < GLOW_CAP * 0.6 and glowScale > 1 then glowScale = math.max(1, glowScale / 1.08) end
    G.glowLit = n   -- 性能面板、测试用
  end
  G.glowCount = function() return #glows end

  local anim = {}
  task.spawn(function()
    for _ = 1, 120 do
      local root = workspace:FindFirstChild("Map")
      if root and G.S and (G.S.progress or 0) >= 1 then
        task.wait(2)
        for _, p in ipairs(root:GetDescendants()) do
          if p:IsA("BasePart") then
            local a = p:GetAttribute("Anim")
            if a == "blink" or a == "spin" then
              table.insert(anim, { p = p, a = a, spd = p:GetAttribute("Spd") or 1, cf0 = p.CFrame, pivot = p:GetAttribute("Pivot"),
                glow = p:FindFirstChild("Glow"), light = p:FindFirstChildWhichIsA("Light") })
            end
          elseif p:IsA("BillboardGui") then
            addGlow(p)
          end
        end
        root.DescendantAdded:Connect(function(d)   -- 后来摆的（舰艇重建等）
          if d.Name == "Glow" then task.defer(addGlow, d) end
        end)
        stepGlows()
        return
      end
      task.wait(1)
    end
  end)
  G.frameConn("Glow", function(dt)
    glowAcc += dt or 1 / 60
    if glowAcc >= 0.25 then
      glowAcc = 0
      local ok, err = pcall(stepGlows)
      if not ok and G.showError then G.showError("光晕：" .. tostring(err)) end
    end
    if #anim == 0 then return end
    local t = os.clock()
    for _, x in ipairs(anim) do
      if x.p.Parent then
        if x.a == "blink" then
          local lit = ((t * x.spd) % 1) < 0.16
          if x.lit ~= lit then
            x.lit = lit
            x.p.Transparency = lit and 0 or 0.85
            if x.glow then
              glowDark[x.glow] = (not lit) or nil
              local want = lit and glowAllow[x.glow] ~= false
              x.glow.Enabled = want
              local gx = glowSeen[x.glow]
              if gx then gx.on = want end
            end
            if x.light then x.light.Enabled = lit end
          end
        elseif x.a == "spin" and typeof(x.pivot) == "Vector3" then
          local P = CFrame.new(x.pivot)
          local angle = (workspace:GetServerTimeNow() * x.spd) % 1
          x.p.CFrame = P * CFrame.Angles(0, -angle * math.pi * 2, 0) * (P:Inverse() * x.cf0)
        end
      end
    end
  end)
end

return Night
