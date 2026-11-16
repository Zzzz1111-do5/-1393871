-- Roblox全面大战场——夜视仪（客户端）：交战全在夜里（World.lighting），步兵、飞行员按 N 开关夜视（手机右边一个小按钮）
--   开着：本地增亮（曝光、环境光）、绿色荧光调色、灯光强烈泛光、雾变淡一点（看得更远）、镜筒形的视野（四周黑，飞行员用头盔显示不加这一圈）、
--     画面轻微闪烁；队友头盔后面的红外频闪一闪一闪（只有夜视里看得见）；镜筒翻下来（服务器改焊接，别人也看得到）
--   开地面载具时关掉（车上有自己的夜视 / 热成像瞄准镜，Drive.lua）；死了关掉
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Night = {}

function Night.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local on = false
  local saved = nil
  local fx = {}

  ---------------------------------------------------------------- 镜筒形视野：一个两头圆的框，外面一圈特别粗的黑描边把四周盖住

  local gui = Instance.new("ScreenGui")
  gui.Name = "NVG"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = -5   -- 在别的界面下面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local tube = Instance.new("Frame")
  tube.Name = "Tube"
  tube.AnchorPoint = Vector2.new(0.5, 0.5)
  tube.Position = UDim2.fromScale(0.5, 0.5)
  tube.BackgroundTransparency = 1
  tube.Parent = gui
  local tc = Instance.new("UICorner")
  tc.CornerRadius = UDim.new(0.5, 0)
  tc.Parent = tube
  local mask = Instance.new("UIStroke")
  mask.Thickness = 2400
  mask.Color = RGB(0, 0, 0)
  mask.Transparency = 0
  mask.Parent = tube
  local edge = Instance.new("Frame")   -- 视野边上一圈软的暗边
  edge.AnchorPoint = Vector2.new(0.5, 0.5)
  edge.Position = UDim2.fromScale(0.5, 0.5)
  edge.Size = UDim2.new(1, -28, 1, -28)
  edge.BackgroundTransparency = 1
  edge.Parent = tube
  local ec = Instance.new("UICorner")
  ec.CornerRadius = UDim.new(0.5, 0)
  ec.Parent = edge
  local es = Instance.new("UIStroke")
  es.Thickness = 30
  es.Color = RGB(0, 0, 0)
  es.Transparency = 0.45
  es.Parent = edge
  local function fitTube()
    local vs = workspace.CurrentCamera.ViewportSize
    local h = vs.Y * 0.97
    tube.Size = UDim2.fromOffset(math.min(vs.X * 0.98, h * 1.62), h)
  end

  ---------------------------------------------------------------- 开关

  local function setOn(v)
    if v == on then return end
    on = v
    pcall(function() G.R.Act:FireServer("nvg", on) end)
    if on then
      local atm = Lighting:FindFirstChildOfClass("Atmosphere")
      saved = { exp = Lighting.ExposureCompensation, amb = Lighting.Ambient, oamb = Lighting.OutdoorAmbient, dens = atm and atm.Density, atm = atm }
      Lighting.ExposureCompensation = saved.exp + 2.7
      Lighting.Ambient = RGB(52, 60, 56)
      Lighting.OutdoorAmbient = RGB(96, 110, 100)
      if atm then atm.Density = math.max(0.12, (saved.dens or 0.3) * 0.55) end
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
      fitTube()
      gui.Enabled = G.fly == nil   -- 飞行员是头盔显示：不加镜筒那一圈
      if G.playSound then G.playSound("quiet", nil, 2.4) end
    else
      for _, e in ipairs(fx) do e:Destroy() end
      fx = {}
      if saved then
        Lighting.ExposureCompensation = saved.exp
        Lighting.Ambient = saved.amb
        Lighting.OutdoorAmbient = saved.oamb
        if saved.atm and saved.dens then saved.atm.Density = saved.dens end
        saved = nil
      end
      gui.Enabled = false
      G.irStrobes(false)
    end
  end
  G.nvgOn = function() return on end
  G.setNvg = setOn

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
    if not hum or hum.Health <= 0 or (G.drive and not G.fly and not G.sail) then setOn(false) return end
    gui.Enabled = G.fly == nil and G.sail == nil   -- 目镜的圆框只在步兵时画（开飞机、开船是追尾镜头）
    local cc = fx[1]
    if cc then cc.Brightness = 0.04 + (math.random() - 0.5) * 0.018 end   -- 增像管的轻微闪烁
    irT += dt
    if irT > 0.05 then
      irT = 0
      G.irStrobes(true)
    end
  end)
  workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitTube)

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
