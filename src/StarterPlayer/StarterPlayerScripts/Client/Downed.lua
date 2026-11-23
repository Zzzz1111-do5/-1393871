-- 全面大战场（客户端）——倒地与救援（服务器 Revive.lua；用户 11-23「这个游戏按你想的来弄」）
--   自己倒地：画面去色、发暗、发红、心跳；镜头离开身体绕着自己转（鼠标转着看有没有队友过来）；中间一条流血倒计时、最近的队友多远、
--     谁正在救你；按住空格（手机按住按钮）放弃 → 直接回部署界面；手里的枪收起来、开不了火（Play.lua 看 G.downed）
--   队友倒地：头顶一个白底红十字的救援标记（隔着墙也看得见，markR 格以内），写着多远、还剩几秒；走到旁边出现「按住 E 救起」
--     （ProximityPrompt：带着急救包 medicHold 秒、没带 hold 秒；开始按、按完都告诉服务器，服务器核对时间）
--   倒地的人（所有人、包括自己）：身子瘫在地上（服务器 PlatformStand 让它倒下去），这里再把姿势摆成受伤的样子——一条腿蜷起来、一只手捂着肚子、头歪着
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Downed = {}

function Downed.init(G)
  local Config = G.Config
  local RC = Config.Revive or {}
  if not RC.on then return end
  local T = G.T or function(k) return k end
  local player = Players.LocalPlayer
  local V, RGB, CF = Vector3.new, Color3.fromRGB, CFrame.new
  local ANG = CFrame.Angles
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
  local function serverNow()
    local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
    return (ok and type(t) == "number") and t or os.clock()
  end
  local function isDown(ch)
    if not ch or ch:GetAttribute("Downed") ~= true then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
  end
  local function act(op, ...) G.R.Act:FireServer(op, ...) end
  local function myTeam()
    local me = G.S and G.S.me
    if me and me.team then return me.team end
    local ch = player.Character
    return ch and ch:GetAttribute("Team") or nil
  end
  -- 自己带没带急救包（背包里、手上的工具）
  local function haveMedkit()
    for _, holder in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
      if holder then
        for _, t in ipairs(holder:GetChildren()) do
          if t:IsA("Tool") and t:GetAttribute("Weapon") == "medkit" then return true end
        end
      end
    end
    return false
  end

  ---------------------------------------------------------------- 自己倒地的界面

  local gui = Instance.new("ScreenGui")
  gui.Name = "Downed"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 30
  gui.Enabled = false
  gui.Parent = player:WaitForChild("PlayerGui")
  -- 四边压暗发红（四块渐变）
  local function edge(size, pos, rot)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = RGB(70, 0, 0)
    f.Size, f.Position = size, pos
    f.Parent = gui
    local g = Instance.new("UIGradient")
    g.Rotation = rot
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = f
    return f
  end
  edge(UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), 90)
  edge(UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), -90)
  edge(UDim2.fromScale(0.25, 1), UDim2.fromScale(0, 0), 0)
  edge(UDim2.fromScale(0.25, 1), UDim2.fromScale(0.75, 0), 180)
  local panel = Instance.new("Frame")
  panel.AnchorPoint = Vector2.new(0.5, 0)
  panel.Position = UDim2.new(0.5, 0, 0.62, 0)
  panel.Size = UDim2.fromOffset(460, 150)
  panel.BackgroundTransparency = 1
  panel.Parent = gui
  local function label(text, y, size, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, size + 6)
    l.Position = UDim2.fromOffset(0, y)
    l.Font = font or Enum.Font.GothamBold
    l.TextSize = size
    l.TextColor3 = color
    l.TextStrokeTransparency = 0.55
    l.Text = text
    l.Parent = panel
    return l
  end
  local title = label(T("down.title"), 0, 22, RGB(255, 236, 230))
  local bleedBar = Instance.new("Frame")
  bleedBar.Position = UDim2.fromOffset(80, 34)
  bleedBar.Size = UDim2.new(1, -160, 0, 4)
  bleedBar.BackgroundColor3 = RGB(30, 10, 10)
  bleedBar.BackgroundTransparency = 0.3
  bleedBar.BorderSizePixel = 0
  bleedBar.Parent = panel
  local bleedFill = Instance.new("Frame")
  bleedFill.Size = UDim2.fromScale(1, 1)
  bleedFill.BackgroundColor3 = RGB(226, 56, 48)
  bleedFill.BorderSizePixel = 0
  bleedFill.Parent = bleedBar
  local bleedText = label("", 42, 16, RGB(255, 200, 190), Enum.Font.Gotham)
  local nearText = label("", 66, 15, RGB(230, 230, 225), Enum.Font.Gotham)
  local hint = label(T("down.giveUp"), 96, 14, RGB(200, 200, 195), Enum.Font.Gotham)
  local giveBar = Instance.new("Frame")
  giveBar.Position = UDim2.fromOffset(150, 120)
  giveBar.Size = UDim2.new(1, -300, 0, 3)
  giveBar.BackgroundColor3 = RGB(255, 255, 255)
  giveBar.BackgroundTransparency = 0.8
  giveBar.BorderSizePixel = 0
  giveBar.Parent = panel
  local giveFill = Instance.new("Frame")
  giveFill.Size = UDim2.fromScale(0, 1)
  giveFill.BackgroundColor3 = RGB(255, 255, 255)
  giveFill.BorderSizePixel = 0
  giveFill.Parent = giveBar
  -- 手机：按住这个按钮放弃
  local giveBtn = Instance.new("TextButton")
  giveBtn.AnchorPoint = Vector2.new(0.5, 0)
  giveBtn.Position = UDim2.new(0.5, 0, 0, 132)
  giveBtn.Size = UDim2.fromOffset(200, 40)
  giveBtn.BackgroundColor3 = RGB(20, 20, 20)
  giveBtn.BackgroundTransparency = 0.35
  giveBtn.BorderSizePixel = 0
  giveBtn.Font = Enum.Font.GothamBold
  giveBtn.TextSize = 15
  giveBtn.TextColor3 = RGB(240, 240, 235)
  giveBtn.Text = T("down.giveUpTouch")
  giveBtn.Visible = false
  giveBtn.Parent = panel
  local touchHold = false
  giveBtn.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then touchHold = true end
  end)
  giveBtn.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then touchHold = false end
  end)

  ---------------------------------------------------------------- 自己倒地：进、出、每帧

  local S = { on = false }
  G.downed = false
  G.downedState = function() return S end   -- 测试用
  local function camStep()
    if not S.on then return end
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local cam = workspace.CurrentCamera
    if not hrp or not cam then return end
    local ok, d = pcall(function() return UIS:GetMouseDelta() end)
    if ok and typeof(d) == "Vector2" then
      S.yaw -= d.X * 0.004
      S.pitch = clamp(S.pitch - d.Y * 0.004, -1.25, 0.25)
    end
    pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end)
    local focus = hrp.Position + V(0, 0.6, 0)
    local rot = ANG(0, S.yaw, 0) * ANG(S.pitch, 0, 0)
    local want = focus - rot.LookVector * 9
    -- 别穿进墙里：从身体往镜头那边打一条线，挡住了就拉近
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { ch }
    local hit = workspace:Raycast(focus, want - focus, rp)
    if hit then want = focus + (want - focus).Unit * math.max(1.5, (hit.Position - focus).Magnitude - 0.6) end
    cam.CFrame = CFrame.lookAt(want, focus)
  end
  local promptsWereOn = true
  local function enter()
    S.on, S.t0, S.giveK, S.sent, S.beatT = true, os.clock(), 0, false, 0
    G.downed = true
    gui.Enabled = true
    giveBtn.Visible = UIS.TouchEnabled
    local cam = workspace.CurrentCamera
    local lv = cam and cam.CFrame.LookVector or V(0, 0, -1)
    S.yaw = math.atan2(-lv.X, -lv.Z)
    S.pitch = -0.45
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "DownedGrade"
    cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -0.8, 0.12, -0.06, RGB(255, 214, 206)
    cc.Parent = Lighting
    local blur = Instance.new("BlurEffect")
    blur.Name = "DownedBlur"
    blur.Size = 5
    blur.Parent = Lighting
    S.cc, S.blur = cc, blur
    pcall(function()
      local PPS = game:GetService("ProximityPromptService")
      promptsWereOn = PPS.Enabled
      PPS.Enabled = false   -- 倒着不能操作工事、上车、生成载具
    end)
    pcall(function() RunService:BindToRenderStep("DownedCam", Enum.RenderPriority.Camera.Value + 25, camStep) end)
  end
  local function leave()
    if not S.on then return end
    S.on = false
    G.downed = false
    gui.Enabled = false
    touchHold = false
    if S.cc then S.cc:Destroy() end
    if S.blur then S.blur:Destroy() end
    S.cc, S.blur = nil, nil
    pcall(function() game:GetService("ProximityPromptService").Enabled = promptsWereOn end)
    pcall(function() RunService:UnbindFromRenderStep("DownedCam") end)
  end
  local function stepMe(dt)
    local ch = player.Character
    local d = isDown(ch)
    if d and not S.on then enter() elseif not d and S.on then leave() end
    if not S.on then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if hum and ch:FindFirstChildOfClass("Tool") then pcall(function() hum:UnequipTools() end) end   -- 倒着拿不了枪
    -- 流血倒计时
    local til = ch:GetAttribute("DownT")
    local left = (type(til) == "number") and math.max(0, til - serverNow()) or RC.bleed
    bleedFill.Size = UDim2.fromScale(clamp(left / RC.bleed, 0, 1), 1)
    bleedText.Text = T("down.bleed", math.ceil(left))
    -- 谁在救我；不然最近的队友多远
    local rb, rt = ch:GetAttribute("RevBy"), ch:GetAttribute("RevT")
    if type(rb) == "string" and type(rt) == "number" and serverNow() - rt < RC.hold + 0.6 then
      nearText.Text = T("down.coming", rb)
      nearText.TextColor3 = RGB(150, 235, 150)
    else
      local hrp = ch:FindFirstChild("HumanoidRootPart")
      local best = nil
      local team = myTeam()
      for _, pl in ipairs(Players:GetPlayers()) do
        local c2 = pl.Character
        if pl ~= player and c2 and c2:GetAttribute("Team") == team and not isDown(c2) then
          local h2 = c2:FindFirstChild("HumanoidRootPart")
          local hm = c2:FindFirstChildOfClass("Humanoid")
          if h2 and hrp and hm and hm.Health > 0 then
            local dd = (h2.Position - hrp.Position).Magnitude
            if not best or dd < best then best = dd end
          end
        end
      end
      nearText.Text = best and T("down.near", math.floor(best / 2.8 + 0.5)) or T("down.none")
      nearText.TextColor3 = RGB(230, 230, 225)
    end
    -- 心跳（越到最后越快）
    local gap = 0.7 + 0.6 * clamp(left / RC.bleed, 0, 1)
    if os.clock() - S.beatT > gap then
      S.beatT = os.clock()
      if G.sfx then G.sfx("heart", nil, { vol = 1.1 }) end
    end
    -- 按住空格放弃
    local holding = touchHold or (UIS:GetFocusedTextBox() == nil and UIS:IsKeyDown(Enum.KeyCode.Space))
    if holding and os.clock() - S.t0 > 0.8 then S.giveK += dt / RC.giveUp else S.giveK = math.max(0, S.giveK - dt * 2) end
    giveFill.Size = UDim2.fromScale(clamp(S.giveK, 0, 1), 1)
    if S.giveK >= 1 and not S.sent then
      S.sent = true
      act("giveUp")
    end
    title.TextTransparency = 0.1 + 0.15 * math.sin(os.clock() * 3)
  end

  ---------------------------------------------------------------- 倒地的队友：救援标记、按住 E 救起

  local tracked = {}   -- [Player] = { ch, bb, dist, timer, prompt, conns }
  local function drop(pl)
    local tr = tracked[pl]
    if not tr then return end
    tracked[pl] = nil
    for _, c in ipairs(tr.conns) do c:Disconnect() end
    if tr.bb then tr.bb:Destroy() end
    if tr.prompt then tr.prompt:Destroy() end
  end
  local function cross(parent)
    local disc = Instance.new("Frame")
    disc.Size = UDim2.fromOffset(30, 30)
    disc.AnchorPoint = Vector2.new(0.5, 0)
    disc.Position = UDim2.new(0.5, 0, 0, 0)
    disc.BackgroundColor3 = RGB(245, 245, 240)
    disc.BorderSizePixel = 0
    disc.Parent = parent
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = disc
    for _, sz in ipairs({ UDim2.fromOffset(18, 6), UDim2.fromOffset(6, 18) }) do
      local b = Instance.new("Frame")
      b.AnchorPoint = Vector2.new(0.5, 0.5)
      b.Position = UDim2.fromScale(0.5, 0.5)
      b.Size = sz
      b.BackgroundColor3 = RGB(214, 40, 36)
      b.BorderSizePixel = 0
      b.Parent = disc
    end
    return disc
  end
  local function ensure(pl, ch)
    local tr = tracked[pl]
    if tr and tr.ch == ch then return tr end
    drop(pl)
    local head = ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not head or not hrp then return nil end
    tr = { ch = ch, conns = {} }
    local bb = Instance.new("BillboardGui")
    bb.Name = "ReviveMark"
    bb.Size = UDim2.fromOffset(120, 64)
    bb.StudsOffset = V(0, 2.4, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = RC.markR
    bb.Adornee = head
    tr.disc = cross(bb)
    local tag = Instance.new("TextLabel")
    tag.BackgroundTransparency = 1
    tag.Position = UDim2.fromOffset(0, 32)
    tag.Size = UDim2.new(1, 0, 0, 16)
    tag.Font = Enum.Font.GothamBold
    tag.TextSize = 13
    tag.TextColor3 = RGB(255, 240, 236)
    tag.TextStrokeTransparency = 0.4
    tag.Parent = bb
    tr.tag = tag
    local tb = Instance.new("Frame")
    tb.AnchorPoint = Vector2.new(0.5, 0)
    tb.Position = UDim2.new(0.5, 0, 0, 50)
    tb.Size = UDim2.fromOffset(44, 3)
    tb.BackgroundColor3 = RGB(40, 10, 10)
    tb.BorderSizePixel = 0
    tb.Parent = bb
    local tf = Instance.new("Frame")
    tf.Size = UDim2.fromScale(1, 1)
    tf.BackgroundColor3 = RGB(226, 56, 48)
    tf.BorderSizePixel = 0
    tf.Parent = tb
    tr.timer = tf
    bb.Parent = gui.Parent   -- 放在 PlayerGui 里（Adornee 指过去），不改别人的角色
    tr.bb = bb
    local medic = haveMedkit()
    local pr = Instance.new("ProximityPrompt")
    pr.Name = "Revive"
    pr.ActionText = medic and T("revive.medic") or T("revive.act")
    pr.ObjectText = pl.DisplayName
    pr.HoldDuration = medic and RC.medicHold or RC.hold
    pr.MaxActivationDistance = RC.range
    pr.RequiresLineOfSight = false
    pr.KeyboardKeyCode = Enum.KeyCode.E
    pcall(function() pr.GamepadKeyCode = Enum.KeyCode.ButtonX end)
    pcall(function() pr.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally end)
    pr.Parent = hrp
    tr.prompt, tr.medic = pr, medic
    table.insert(tr.conns, pr.PromptButtonHoldBegan:Connect(function() act("reviveBegin", pl.UserId) end))
    table.insert(tr.conns, pr.Triggered:Connect(function() act("revive", pl.UserId) end))
    tracked[pl] = tr
    return tr
  end
  local scanT = 0
  local function stepMates(dt)
    scanT -= dt
    local myCh = player.Character
    local myHrp = myCh and myCh:FindFirstChild("HumanoidRootPart")
    if scanT <= 0 then
      scanT = 0.25
      local team = myTeam()
      local seen = {}
      for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        if pl ~= player and ch and team and ch:GetAttribute("Team") == team and isDown(ch) then
          if ensure(pl, ch) then seen[pl] = true end
        end
      end
      for pl in pairs(tracked) do if not seen[pl] then drop(pl) end end
      -- 带没带急救包换了（换了装备重新部署）：提示和按多久跟着变
      local medic = haveMedkit()
      for _, tr in pairs(tracked) do
        if tr.medic ~= medic and tr.prompt then
          tr.medic = medic
          tr.prompt.HoldDuration = medic and RC.medicHold or RC.hold
          tr.prompt.ActionText = medic and T("revive.medic") or T("revive.act")
        end
      end
    end
    local now = serverNow()
    local pulse = 0.5 + 0.5 * math.sin(os.clock() * 5)
    for _, tr in pairs(tracked) do
      local hrp = tr.ch:FindFirstChild("HumanoidRootPart")
      if tr.prompt then tr.prompt.Enabled = not G.downed and not G.drive end
      if hrp and myHrp then
        local dd = (hrp.Position - myHrp.Position).Magnitude
        tr.tag.Text = string.format("%s  %d m", T("revive.tag"), math.floor(dd / 2.8 + 0.5))
      end
      local til = tr.ch:GetAttribute("DownT")
      if type(til) == "number" then tr.timer.Size = UDim2.fromScale(clamp((til - now) / RC.bleed, 0, 1), 1) end
      if tr.disc then tr.disc.BackgroundTransparency = 0.15 * pulse end
    end
  end
  Players.PlayerRemoving:Connect(drop)

  ---------------------------------------------------------------- 倒地的人的姿势（瘫着、一条腿蜷起来、一只手捂着肚子、头歪着）

  -- 关节角同 Soldier.lua 的 fkSet（同一套 R15 关节：膝盖往负的弯、髋往正的是大腿往前）
  local POSE = {
    LeftHip = ANG(0.85, 0, -0.1), LeftKnee = ANG(-1.45, 0, 0),
    RightHip = ANG(0.15, 0, 0.12), RightKnee = ANG(-0.35, 0, 0),
    RightShoulder = ANG(0.55, 0, 0.45), RightElbow = ANG(1.35, 0, 0),
    LeftShoulder = ANG(0.2, 0, -0.35), LeftElbow = ANG(0.4, 0, 0),
    Neck = ANG(0.3, 0.45, 0), Waist = ANG(0.12, 0.1, 0),
  }
  local posed = {}   -- [角色] = { motors = { [名字] = Motor6D }, t0 }
  local function poseStep()
    for ch, ps in pairs(posed) do
      if not ch.Parent or not isDown(ch) then
        for _, m in pairs(ps.motors) do pcall(function() m.Transform = CF() end) end
        posed[ch] = nil
      end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      if ch and isDown(ch) then
        local ps = posed[ch]
        if not ps then
          ps = { motors = {}, t0 = os.clock() }
          for name in pairs(POSE) do
            local m = ch:FindFirstChild(name, true)
            if m and m:IsA("Motor6D") then ps.motors[name] = m end
          end
          posed[ch] = ps
        end
        local k = clamp((os.clock() - ps.t0) / 0.6, 0, 1)
        k = k * k * (3 - 2 * k)
        local br = math.sin(os.clock() * 2.2) * 0.04   -- 喘气
        for name, m in pairs(ps.motors) do
          local target = POSE[name]
          if name == "Waist" then target = target * ANG(br, 0, 0) end
          pcall(function() m.Transform = CF():Lerp(target, k) end)
        end
      end
    end
  end

  G.frameConn("Downed", function(dt)
    stepMe(dt)
    stepMates(dt)
    poseStep()
  end)
end

return Downed
