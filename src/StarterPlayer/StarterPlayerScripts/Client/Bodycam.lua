-- 步兵第一人称记录仪。瞄准时交还镜头，夜视时保留原画面，跟随 Roblox 的减少动态效果设置。
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Bodycam = {}
local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value
local GRAIN_INTERVAL = 1 / 12
local GREEN = Color3.fromRGB(186, 218, 207)
local LIGHT = Color3.fromRGB(237, 241, 240)
local ZERO = Vector3.new()

function Bodycam.init(G)
  local me = Players.LocalPlayer
  local mobile = G.mobile == true
  G.bodycamOn = true
  G.bodycamState = { on = false }

  local gui = Instance.new("ScreenGui")
  gui.Name = "Bodycam"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = -2
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local lens = Instance.new("Frame")
  lens.Name = "Lens"
  lens.Size = UDim2.fromScale(1, 1)
  lens.BackgroundTransparency = 1
  lens.Visible = false
  lens.Parent = gui
  for _, edge in ipairs({
    { 0, 0, 1, 0.16, 90 },
    { 0, 1, 1, 0.20, -90 },
    { 0, 0, 0.14, 1, 0 },
    { 1, 0, 0.14, 1, 180 },
  }) do
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(edge[1], edge[2])
    frame.Position = UDim2.fromScale(edge[1], edge[2])
    frame.Size = UDim2.fromScale(edge[3], edge[4])
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = Color3.fromRGB(3, 8, 9)
    frame.BackgroundTransparency = 0.65
    frame.Parent = lens

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = edge[5]
    gradient.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0),
      NumberSequenceKeypoint.new(0.48, 0.7),
      NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = frame
  end

  local grain = Instance.new("Frame")
  grain.Name = "Grain"
  grain.Size = UDim2.fromScale(1, 1)
  grain.BackgroundTransparency = 1
  grain.Visible = false
  grain.Parent = lens
  local specks = {}
  if not mobile then
    for i = 1, 18 do
      local speck = Instance.new("Frame")
      speck.BorderSizePixel = 0
      speck.BackgroundColor3 = LIGHT
      speck.BackgroundTransparency = 0.86
      speck.Size = UDim2.fromOffset(1, 1)
      speck.Parent = grain
      specks[i] = speck
    end
  end

  local readout = Instance.new("Frame")
  readout.Name = "Readout"
  readout.AnchorPoint = Vector2.new(1, 0)
  local layout = G.hudLayout
  local y = layout and layout.radarRight and (layout.radarY + layout.radarSize + 186) or 56
  readout.Position = UDim2.new(1, -22, 0, y)
  readout.Size = UDim2.fromOffset(210, 44)
  readout.BackgroundTransparency = 1
  readout.Visible = false
  readout.Parent = gui

  local function label(name, offset, size, color)
    local text = Instance.new("TextLabel")
    text.Name = name
    text.BackgroundTransparency = 1
    text.Position = UDim2.fromOffset(0, offset)
    text.Size = UDim2.new(1, 0, 0, 18)
    text.Font = Enum.Font.Code
    text.TextSize = size
    text.TextColor3 = color
    text.TextStrokeTransparency = 0.36
    text.TextStrokeColor3 = Color3.new(0, 0, 0)
    text.TextXAlignment = Enum.TextXAlignment.Right
    text.Parent = readout
    return text
  end

  label("CameraModel", 0, 14, GREEN).Text = "CAM 02  /  ISLAND ASSAULT"
  local clock = label("BodycamClock", 19, 12, LIGHT)

  local dot = Instance.new("Frame")
  dot.Name = "BodycamDot"
  dot.AnchorPoint = Vector2.new(0.5, 0.5)
  dot.Position = UDim2.fromScale(0.5, 0.5)
  dot.Size = UDim2.fromOffset(3, 3)
  dot.BorderSizePixel = 0
  dot.BackgroundColor3 = LIGHT
  dot.BackgroundTransparency = 0.32
  dot.Parent = gui

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0.5, 0)
  corner.Parent = dot
  local outline = Instance.new("UIStroke")
  outline.Color = Color3.fromRGB(5, 10, 13)
  outline.Transparency = 0.56
  outline.Thickness = 1
  outline.Parent = dot

  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "BodycamCC"
  cc.Enabled = false
  cc.Saturation, cc.Contrast, cc.Brightness = -0.08, 0.04, 0.015
  cc.TintColor = Color3.fromRGB(244, 249, 255)
  cc.Parent = Lighting

  local bloom = Instance.new("BloomEffect")
  bloom.Name = "BodycamBloom"
  bloom.Enabled = false
  bloom.Intensity, bloom.Size, bloom.Threshold = 0.24, 22, 1.8
  bloom.Parent = Lighting

  local blur = Instance.new("BlurEffect")
  blur.Name = "BodycamBlur"
  blur.Enabled = false
  blur.Size = 0
  blur.Parent = Lighting

  local reducedMotion, coreMenuOpen = false, false
  pcall(function()
    local function update() reducedMotion = GuiService.ReducedMotionEnabled end
    update()
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(update)
  end)
  pcall(function()
    local function update() coreMenuOpen = GuiService.MenuIsOpen end
    update()
    GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(update)
  end)

  local modifiedCamera, baseFrame, bodyFrame
  local trackedCamera, trackedRoot
  local phase, speed, airTime, landing, verticalSpeed = 0, 0, 0, 0, 0
  local lastLook, turnRate = nil, 0
  local nextGrain, lastSecond = 0, nil
  local random = Random.new()

  local function resetMotion()
    phase, speed, airTime, landing, verticalSpeed = 0, 0, 0, 0, 0
    lastLook, turnRate = nil, 0
  end

  local function acceptsCamera(cam)
    return G.bodycamOn and G.fpActive and not G.drive and cam.CameraType ~= Enum.CameraType.Scriptable
      and not coreMenuOpen and not G.factionOpen and not G.scopeOn
      and not (G.scopeVisible and G.scopeVisible()) and not (G.killcamOn and G.killcamOn())
      and not (G.menuOpen and G.menuOpen()) and not (G.menuShown and G.menuShown())
      and not (G.boardShown and G.boardShown()) and not (G.coachPanel and G.coachPanel())
  end

  -- 恢复原始位姿。别的镜头接手后没必要回滚它写进去的值。
  RunService:BindToRenderStep("BodycamUndo", CAMERA_PRIORITY - 1, function()
    if modifiedCamera then
      if modifiedCamera.Parent and modifiedCamera.CFrame == bodyFrame then
        modifiedCamera.CFrame = baseFrame
      end
      modifiedCamera, baseFrame, bodyFrame = nil, nil, nil
    end
  end)

  RunService:BindToRenderStep("Bodycam", CAMERA_PRIORITY + 5, function(dt)
    local cam = workspace.CurrentCamera
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local on = cam ~= nil and hum ~= nil and root ~= nil and hum.Health > 0 and acceptsCamera(cam) == true
    local aiming = G.fpsAiming == true
    local optical = on and not aiming and not G.nvLight
    local moving = on and not aiming and not reducedMotion
    local noise = optical and moving and not mobile
    if on ~= G.bodycamState.on then
      G.bodycamState.on, gui.Enabled = on, on
    end
    if optical ~= lens.Visible then
      lens.Visible, cc.Enabled, bloom.Enabled = optical, optical, optical and not mobile
    end
    if noise ~= grain.Visible then
      grain.Visible, nextGrain = noise, 0
    end

    local blurSize = 0
    if moving then
      if trackedCamera ~= cam or trackedRoot ~= root then
        trackedCamera, trackedRoot = cam, root
        resetMotion()
      end
      dt = math.clamp(dt, 1 / 240, 0.05)
      local okVelocity, velocity = pcall(function() return root.AssemblyLinearVelocity end)
      local vel = okVelocity and typeof(velocity) == "Vector3" and velocity or ZERO
      local horizontal = math.sqrt(vel.X ^ 2 + vel.Z ^ 2)
      speed += (math.min(horizontal, 26) - speed) * (1 - math.exp(-8 * dt))
      local okFloor, floor = pcall(function() return hum.FloorMaterial end)
      local grounded = not (okFloor and floor == Enum.Material.Air)
      if grounded then
        if airTime > 0.35 and verticalSpeed < -18 then landing = math.clamp(-verticalSpeed / 70, 0, 1) end
        airTime = 0
      else
        airTime += dt
      end
      verticalSpeed = vel.Y
      landing *= math.exp(-8 * dt)

      local stride = math.min(speed / 16, 1.4) * (grounded and 1 or 0.16)
      phase = (phase + dt * (4 + speed * 0.29)) % (2 * math.pi)
      local step = math.sin(phase)
      local amount = mobile and 0.63 or 1
      local slide = step * 0.051 * stride
      local dip = -0.10 - (math.abs(step) * 0.075 * stride + landing * 0.24) * amount
      local tilt = -landing * 0.032 - math.abs(math.sin(2 * phase)) * 0.008 * stride
      local roll = step * 0.014 * stride

      local view = cam.CFrame
      if optical and not mobile then
        local look = view.LookVector
        if lastLook then
          local rate = math.acos(math.clamp(look:Dot(lastLook), -1, 1)) / dt
          turnRate += (rate - turnRate) * (1 - math.exp(-13 * dt))
        end
        lastLook = look
        blurSize = math.clamp((turnRate - 3.2) * 0.72, 0, 3)
      else
        lastLook, turnRate = nil, 0
      end

      modifiedCamera, baseFrame = cam, view
      cam.CFrame = view * CFrame.new(slide * amount, dip, 0) * CFrame.Angles(tilt * amount, 0, roll * amount)
      bodyFrame = cam.CFrame
    elseif trackedCamera then
      trackedCamera, trackedRoot = nil, nil
      resetMotion()
    end

    local blurOn = blurSize > 0.3
    if blur.Enabled ~= blurOn then blur.Enabled = blurOn end
    if blurOn then blur.Size = blurSize end
    if not on then return end

    if dot.Visible == aiming then dot.Visible = not aiming end
    local viewport = cam.ViewportSize
    local showReadout = not mobile and not aiming and viewport.X >= 780 and viewport.Y >= y + 104
    if readout.Visible ~= showReadout then readout.Visible = showReadout end
    local t = os.clock()
    if noise and t >= nextGrain then
      nextGrain = t + GRAIN_INTERVAL
      for _, speck in ipairs(specks) do
        speck.Position = UDim2.fromScale(random:NextNumber(), random:NextNumber())
      end
    end
    local second = math.floor(t)
    if showReadout and lastSecond ~= second then
      clock.Text = os.date("!%Y-%m-%d  %H:%M:%S")
      lastSecond = second
    end
  end)
end

return Bodycam
