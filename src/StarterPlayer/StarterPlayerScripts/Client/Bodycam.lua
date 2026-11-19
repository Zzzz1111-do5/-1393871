-- Roblox全面大战场（客户端）——第一人称持枪的「执法记录仪」观感（用户：第一人称持枪去参考 bodycam）
--   只在步行第一人称（G.fpActive）、活着、没开狙击镜 / 望远镜时：
--   ① 镜头跟着步子走：每一步往下一沉、左右一摆、一歪（跑起来更大），落地猛地一顿，站着时随呼吸轻轻起伏；开镜瞄准时收到两成，不耽误瞄准；
--      镜头比眼睛低一点（像挂在胸前的记录仪）。只是看起来晃：每帧镜头模块算之前先把上一帧加的晃撤掉（不会越晃越偏）
--   ② 画面：四角压暗的镜头暗角、一层细碎的噪点、高光溢出（Bloom）、偏冷一点的色调；甩镜头快的时候糊一下（像记录仪的运动模糊）
--   ③ 右上角记录仪的字：● REC（一闪一闪）、机身型号和编号（虚构的）、日期时间
--   ④ 准星：第一人称不画那四根线，只留中间一个很淡的小点（记录仪画面里没有准星；第三人称照旧）——Play.lua 看 G.bodycamOn
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Bodycam = {}

function Bodycam.init(G)
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local UD2, V2 = UDim2.new, Vector2.new
  local mobile = G.mobile == true
  G.bodycamOn = true

  ---------------------------------------------------------------- 画面上的东西

  local gui = Instance.new("ScreenGui")
  gui.Name = "Bodycam"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = -2   -- 在主界面、狙击镜（-1）下面
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  -- 暗角：四边往里的渐变
  for _, e in ipairs({ { V2(0, 0), UD2(1, 0, 0.3, 0), 90 }, { V2(0, 1), UD2(1, 0, 0.3, 0), -90 }, { V2(0, 0), UD2(0.22, 0, 1, 0), 0 }, { V2(1, 0), UD2(0.22, 0, 1, 0), 180 } }) do
    local f = Instance.new("Frame")
    f.AnchorPoint = e[1]
    f.Position = UDim2.fromScale(e[1].X, e[1].Y)
    f.Size = e[2]
    f.BorderSizePixel = 0
    f.BackgroundColor3 = RGB(0, 0, 0)
    f.BackgroundTransparency = 0.35
    f.Parent = gui
    local gr = Instance.new("UIGradient")
    gr.Rotation = e[3]
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.85), NumberSequenceKeypoint.new(1, 1) })
    gr.Parent = f
  end
  -- 噪点
  local grain = {}
  for i = 1, (mobile and 24 or 70) do
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = RGB(255, 255, 255)
    f.BackgroundTransparency = 0.82
    f.Size = UDim2.fromOffset(2, 2)
    f.Parent = gui
    grain[i] = f
  end
  -- 右上角的字
  local TS = mobile and 11 or 15
  local function txt(y, col)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.AnchorPoint = V2(1, 0)
    l.Position = UD2(1, -(mobile and 14 or 24), 0, y)
    l.Size = UDim2.fromOffset(mobile and 220 or 320, TS + 4)
    l.Font = Enum.Font.Code
    l.TextSize = TS
    l.TextColor3 = col or RGB(236, 238, 236)
    l.TextTransparency = 0.12
    l.TextStrokeTransparency = 0.45
    l.TextStrokeColor3 = RGB(0, 0, 0)
    l.TextXAlignment = Enum.TextXAlignment.Right
    l.Parent = gui
    return l
  end
  -- 右上角是小地图（Hud.lua）：字放在它下面
  local L = G.hudLayout
  local y0 = (L and L.radarRight) and (L.radarY + L.radarSize + 14 + 160 + 12) or 20   -- 小地图、击杀信息下面
  local rec = txt(y0, RGB(255, 70, 60))
  rec.Name = "Rec"
  local model = txt(y0 + TS + 6)
  local clock = txt(y0 + (TS + 6) * 2)
  clock.Name = "BodycamClock"
  local serial = string.format("SN IA-%06X", (me.UserId * 2654435761) % 0xFFFFFF)
  model.Text = "ISLAND CAM X2   " .. serial
  if mobile then rec.Visible, model.Visible, clock.Visible = false, false, false end   -- 手机：右上是开火、换枪那一列按钮，字不放
  -- 准星位置上一个很淡的小点
  local dot = Instance.new("Frame")
  dot.Name = "BodycamDot"
  dot.AnchorPoint = V2(0.5, 0.5)
  dot.Position = UDim2.fromScale(0.5, 0.5)
  dot.Size = UDim2.fromOffset(3, 3)
  dot.BorderSizePixel = 0
  dot.BackgroundColor3 = RGB(255, 255, 255)
  dot.BackgroundTransparency = 0.45
  dot.Parent = gui
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = dot
  end

  -- 画面效果
  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "BodycamCC"
  cc.Enabled = false
  cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -0.16, 0.12, 0.01, RGB(232, 240, 255)
  cc.Parent = Lighting
  local bloom = Instance.new("BloomEffect")
  bloom.Name = "BodycamBloom"
  bloom.Enabled = false
  bloom.Intensity, bloom.Size, bloom.Threshold = 0.7, 30, 1.25
  bloom.Parent = Lighting
  local blur = Instance.new("BlurEffect")
  blur.Name = "BodycamBlur"
  blur.Enabled = false
  blur.Size = 0
  blur.Parent = cam

  -- 记录仪上的日期时间（本机时间；拿不到日期的环境退回按运行时间走的钟）
  local function stamp()
    local okD, str = pcall(function() return os.date("%Y-%m-%d  %H:%M:%S") end)
    if okD and type(str) == "string" then return str end
    local t = math.floor(os.clock())
    return string.format("2026-11-19  %02d:%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, t % 60)
  end

  ---------------------------------------------------------------- 镜头的晃

  local applied = nil      -- 这一帧加上去的晃（下一帧镜头模块算之前撤掉）
  local phase, speedS, airT, land, lastY, lastVy = 0, 0, 0, 0, nil, 0
  local lastLook, angS = nil, 0
  local adsK = 0
  G.bodycamState = { on = false }   -- 测试用

  local function active()
    if not G.bodycamOn or not G.fpActive or G.drive then return false end
    local ch = me.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local sv = G.scopeVisible and G.scopeVisible()
    if sv then return false end
    if G.killcamOn and G.killcamOn() then return false end   -- 阵亡镜头（Warfx）在放
    return true
  end

  -- 镜头模块（Camera 优先级）算之前：撤掉上一帧的晃
  RunService:BindToRenderStep("BodycamUndo", Enum.RenderPriority.Camera.Value - 1, function()
    if applied then
      cam.CFrame = cam.CFrame * applied:Inverse()
      applied = nil
    end
  end)

  RunService:BindToRenderStep("Bodycam", Enum.RenderPriority.Camera.Value + 5, function(dt)
    dt = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
    local on = active()
    gui.Enabled = on
    cc.Enabled, bloom.Enabled = on, on
    G.bodycamState.on = on
    if not on then
      blur.Enabled = false
      lastLook, lastY = nil, nil
      return
    end
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local t = os.clock()
    -- 速度：按位置变化（测试台、网络延迟下也稳）
    local vel = V()
    local okv, v = pcall(function() return hrp.AssemblyLinearVelocity end)
    if okv and typeof(v) == "Vector3" then vel = v end
    local hs = V(vel.X, 0, vel.Z).Magnitude
    speedS += (math.min(hs, 32) - speedS) * math.min(1, dt * 8)
    local okf, fm = pcall(function() return hum.FloorMaterial end)
    local grounded = not (okf and fm == Enum.Material.Air)
    if not grounded then airT += dt else
      if airT > 0.35 and lastVy < -18 then land = math.clamp(-lastVy / 60, 0.25, 1) end   -- 落地猛地一沉
      airT = 0
    end
    lastVy = vel.Y
    land = math.max(0, land - dt * 3.2)
    local aiming = G.fpsAiming == true
    adsK += ((aiming and 1 or 0) - adsK) * math.min(1, dt * 10)
    local amp = (1 - 0.8 * adsK)
    local run = math.clamp(speedS / 16, 0, 1.6) * (grounded and 1 or 0.2)
    phase += dt * (5.6 + speedS * 0.32) * (run > 0.05 and 1 or 0)
    local s1, s2 = math.sin(phase), math.sin(phase * 2)
    local idle = 1 - math.clamp(run * 2, 0, 1)
    -- 位置：胸前的记录仪（比眼睛低、靠前一点）+ 每步一沉一摆
    local px = s1 * 0.07 * run
    local py = -0.32 - math.abs(s1) * 0.1 * run - land * 0.45 + math.sin(t * 1.5) * 0.012 * idle
    local pz = -0.18
    -- 角度：低头点一下、左右歪（跑起来明显）、呼吸
    local rx = (-math.abs(s2) * 0.012 * run - land * 0.05 + math.sin(t * 1.5) * 0.0025 * idle) * amp
    local ry = s1 * 0.006 * run * amp
    local rz = (s1 * 0.02 * run + math.sin(t * 0.9) * 0.002 * idle) * amp
    local off = CF(px * amp, py * (0.35 + 0.65 * amp), pz) * CFrame.Angles(rx, ry, rz)
    cam.CFrame = cam.CFrame * off
    applied = off
    -- 甩镜头快：糊一下
    local look = cam.CFrame.LookVector
    if lastLook then
      local a = math.acos(math.clamp(look:Dot(lastLook), -1, 1)) / dt
      angS += (a - angS) * math.min(1, dt * 14)
    end
    lastLook = look
    local bs = math.clamp((angS - 2.2) * 1.4, 0, 6) * (1 - adsK)
    blur.Enabled = bs > 0.3
    blur.Size = bs
    -- 噪点、REC 一闪一闪、时间
    local vs = cam.ViewportSize
    for _, g in ipairs(grain) do
      g.Position = UDim2.fromOffset(math.random() * vs.X, math.random() * vs.Y)
      g.BackgroundTransparency = 0.7 + math.random() * 0.25
    end
    rec.Text = ((t % 1) < 0.6 and "● " or "   ") .. "REC"
    clock.Text = stamp()
    dot.Visible = not aiming
  end)
end

return Bodycam
