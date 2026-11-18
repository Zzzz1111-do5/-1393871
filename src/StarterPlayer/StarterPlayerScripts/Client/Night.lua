-- Roblox全面大战场——夜视仪（客户端）：现在有昼夜更替（DayNight.lua），天黑了出生自动打开；步兵、飞行员按 N 开关夜视（手机右边一个小按钮）
--   开着：整个画面都是夜视（本地增亮、绿色荧光调色、灯光强烈泛光、雾变淡一点看得更远、画面轻微闪烁；用户：要全屏的夜视，不要望远镜那样四周一圈黑）；
--     队友头盔后面的红外频闪一闪一闪（只有夜视里看得见）；镜筒翻下来（服务器改焊接，别人也看得到）
--   坐进载具（车、飞机、直升机、船、炮位）照样开着（用户：进载具夜视不要取消）；地面载具里 N 是切车上瞄准镜的夜视 / 热成像（Drive.lua），
--     开着车上的瞄准镜看时夜视仪先让出画面（瞄准镜有自己的调色，叠在一起热成像会发绿、过亮），退出瞄准镜自动恢复；死了关掉
--   默认开着（用户：视野不管是在什么情况默认夜视仪都是开着的）：每次出生自动打开；按 N 关掉的话这一条命里关着，下次出生又是开的；车上瞄准镜默认也是夜视档
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

  -- 夜视的画面效果加上 / 撤掉（开着夜视仪、但正在看车上的瞄准镜时撤掉，on 不变）
  local fxOn = false
  local function fxApply(want)
    if want == fxOn then return end
    fxOn = want
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
    else
      for _, e in ipairs(fx) do e:Destroy() end
      fx = {}
      G.nvLight = false
      G.irStrobes(false)
    end
  end
  -- 正在看车上的瞄准镜（它有自己的昼光 / 夜视 / 热成像调色）：夜视仪先让出画面
  local function held() return G.sightCC ~= nil and G.sightCC.Enabled end

  local function setOn(v)
    if v == on then return end
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if v and not (hum and hum.Health > 0) then return end   -- 没出生（部署界面、主菜单）不开
    on = v
    pcall(function() G.R.Act:FireServer("nvg", on) end)
    fxApply(on and not held())
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
    local air = (G.fly ~= nil) or (G.sail ~= nil)   -- 坐上飞机、船：夜视在那里也能开（地面载具里 N 是瞄准镜的，不提示）
    if air and not wasAir then showHint(8) end
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

  UIS.InputBegan:Connect(function(io, gp)
    if gp or io.KeyCode ~= Enum.KeyCode.N then return end
    if G.drive and not G.fly and not G.sail then return end   -- 地面载具里 N 是瞄准镜的夜视 / 热成像（开船、开飞机时 N 照样是夜视仪）
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    setOn(not on)
  end)
  if UIS.TouchEnabled then   -- 手机：右边一个小按钮
    local b = G.ui and G.ui.button and G.ui.button(G.gui:WaitForChild("Hud"), "NV", UDim2.fromOffset(52, 40), UDim2.new(1, -78, 0, 140), RGB(24, 28, 30))
    if b then
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(function() setOn(not on) end)
    end
  end

  RunService.RenderStepped:Connect(function(dt)
    if not on then return end
    local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then setOn(false) return end
    fxApply(not held())   -- 坐进载具照样开着；看车上的瞄准镜时让出画面，退出来再加上
    if not fxOn then return end
    local cc = fx[1]
    if cc then cc.Brightness = 0.04 + (math.random() - 0.5) * 0.018 end   -- 增像管的轻微闪烁
    irT += dt
    if irT > 0.05 then
      irT = 0
      G.irStrobes(true)
    end
  end)

  ---------------------------------------------------------------- 地图上会动的灯（服务器摆的零件带 Anim 属性）：blink 每秒闪 Spd 下、spin 绕 Pivot 转（灯塔光柱，Spd 圈 / 秒）

  local anim = {}
  task.spawn(function()
    for _ = 1, 120 do
      local root = workspace:FindFirstChild("Map")
      if root and G.S then
        task.wait(2)
        for _, p in ipairs(root:GetDescendants()) do
          if p:IsA("BasePart") then
            local a = p:GetAttribute("Anim")
            if a == "blink" or a == "spin" then
              table.insert(anim, { p = p, a = a, spd = p:GetAttribute("Spd") or 1, cf0 = p.CFrame, pivot = p:GetAttribute("Pivot"),
                glow = p:FindFirstChild("Glow"), light = p:FindFirstChildWhichIsA("Light") })
            end
          end
        end
        return
      end
      task.wait(1)
    end
  end)
  RunService.RenderStepped:Connect(function()
    if #anim == 0 then return end
    local t = os.clock()
    for _, x in ipairs(anim) do
      if x.p.Parent then
        if x.a == "blink" then
          local lit = ((t * x.spd) % 1) < 0.16
          if x.lit ~= lit then
            x.lit = lit
            x.p.Transparency = lit and 0 or 0.85
            if x.glow then x.glow.Enabled = lit end
            if x.light then x.light.Enabled = lit end
          end
        elseif x.a == "spin" and typeof(x.pivot) == "Vector3" then
          local P = CFrame.new(x.pivot)
          x.p.CFrame = P * CFrame.Angles(0, -t * x.spd * math.pi * 2, 0) * (P:Inverse() * x.cf0)
        end
      end
    end
  end)
end

return Night
