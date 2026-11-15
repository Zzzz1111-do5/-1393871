-- 暗剑：登岛战——操作：武器栏（1–4、点选）、肩后视角（拿着武器时鼠标锁在屏幕中间、人跟着镜头转，准星打哪儿就是哪儿）、
--   开火（连发 / 单发）、右键瞄准（狙击镜）、R 换弹、各种装备（火箭筒、防空导弹右键锁定、手雷、迫击炮、急救包、扳手按住修车、
--   炸药包左键放右键引爆、地雷、望远镜左键标记 F 呼叫炮击）、命中标记、弹药显示；手机上屏幕按钮
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local Play = {}

function Play.init(G)
  local Config = G.Config
  local W = Config.Weapons
  local player = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local ui = G.ui
  local T = G.T
  local now = os.clock
  local RShoot, RAct = G.R.Shoot, G.R.Act
  G.mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  ---------------------------------------------------------------- 界面：武器栏、准星、弹药、命中标记

  local hud = G.gui:WaitForChild("Hud")
  local bar = ui.frame(hud, UDim2.fromOffset(420, 52), UDim2.new(0.5, 0, 1, -70), RGB(0, 0, 0), 1, Vector2.new(0.5, 0))
  local barList = Instance.new("UIListLayout")
  barList.FillDirection = Enum.FillDirection.Horizontal
  barList.HorizontalAlignment = Enum.HorizontalAlignment.Center
  barList.Padding = UDim.new(0, 6)
  barList.Parent = bar
  local slots = {}
  local cross = ui.label(G.gui, "+", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 30, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  cross.TextStrokeTransparency = 0.4
  cross.Visible = false
  cross.ZIndex = 15
  local hitX = ui.label(G.gui, "✕", UDim2.fromOffset(34, 34), UDim2.fromScale(0.5, 0.5), 28, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  hitX.TextTransparency = 1
  hitX.ZIndex = 16
  local hitT = 0
  local ammoText = ui.label(hud, "", UDim2.fromOffset(320, 26), UDim2.new(1, -260, 1, -90), 18, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  ammoText.TextStrokeTransparency = 0.4
  local tipText = ui.label(G.gui, "", UDim2.fromOffset(300, 22), UDim2.new(0.5, 0, 0.5, 30), 14, RGB(255, 230, 140), Enum.Font.GothamBold, Vector2.new(0.5, 0))
  tipText.TextStrokeTransparency = 0.4
  tipText.ZIndex = 15
  local scope = ui.frame(G.gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  scope.ZIndex = 12
  scope.Visible = false
  do   -- 狙击镜：四周黑、中间十字
    for _, s in ipairs({ { UDim2.new(1, 0, 0.5, -170), UDim2.new() }, { UDim2.new(1, 0, 0.5, -170), UDim2.new(0, 0, 0.5, 170) }, { UDim2.new(0.5, -170, 0, 340), UDim2.new(0, 0, 0.5, -170) }, { UDim2.new(0.5, -170, 0, 340), UDim2.new(0.5, 170, 0.5, -170) } }) do
      local f = ui.frame(scope, s[1], s[2], RGB(0, 0, 0), 0)
      f.ZIndex = 12
    end
    local h = ui.frame(scope, UDim2.fromOffset(340, 1), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 0, Vector2.new(0.5, 0.5))
    local v = ui.frame(scope, UDim2.fromOffset(1, 340), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 0, Vector2.new(0.5, 0.5))
    h.ZIndex, v.ZIndex = 13, 13
  end

  function G.hitMarker(kind)
    hitX.TextColor3 = (kind == "kill") and RGB(255, 70, 60) or ((kind == "head") and RGB(255, 220, 80) or Color3.new(1, 1, 1))
    hitX.TextTransparency = 0
    hitT = now()
    if G.playSound then G.playSound((kind == "kill") and "killding" or "hit") end
  end

  ---------------------------------------------------------------- 武器栏

  local cur = { tool = nil, id = nil, nextShot = 0, firing = false, aiming = false, lockT = 0, lockId = nil }
  local ammo = {}
  local function ammoOf(id)
    local w = W[id]
    local a = ammo[id]
    if not a then
      a = { n = w.mag or 1, res = w.reserve, r = 0 }
      ammo[id] = a
    end
    if a.r > 0 and now() >= a.r then
      local need = (w.mag or 1) - a.n
      if a.res then
        local k = math.min(need, a.res)
        a.n += k
        a.res -= k
      else
        a.n += need
      end
      a.r = 0
    end
    return a
  end
  local function reload()
    local id = cur.id
    if not id then return end
    local w = W[id]
    local a = ammoOf(id)
    if a.r > 0 or a.n >= (w.mag or 1) or (a.res and a.res <= 0) or (w.reload or 0) <= 0 then return end
    a.r = now() + w.reload
    RAct:FireServer("reload", id)
  end

  local function tools()
    local list = {}
    local bp = player:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({ bp, player.Character }) do
      if holder then
        for _, t in ipairs(holder:GetChildren()) do
          if t:IsA("Tool") and t:GetAttribute("Slot") then list[t:GetAttribute("Slot")] = t end
        end
      end
    end
    return list
  end
  local function equip(i)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or G.drive then return end
    local t = tools()[i]
    if not t then return end
    if t.Parent == char then hum:UnequipTools() else hum:EquipTool(t) end
  end
  G.equipSlot = equip

  local function drawBar()
    for _, s in ipairs(slots) do s:Destroy() end
    slots = {}
    for i, t in pairs(tools()) do
      local id = t:GetAttribute("Weapon")
      local on = t.Parent == player.Character
      local b = ui.button(bar, i .. "  " .. T("weapon." .. id), UDim2.fromOffset(130, 44), nil, on and RGB(70, 90, 60) or RGB(30, 36, 42))
      b.LayoutOrder = i
      b.TextSize = 14
      b.Activated:Connect(function() equip(i) end)
      table.insert(slots, b)
    end
  end

  local function onChar(char)
    ammo = {}
    cur.tool, cur.id = nil, nil
    char.ChildAdded:Connect(function(c)
      if c:IsA("Tool") and c:GetAttribute("Weapon") then
        cur.tool, cur.id = c, c:GetAttribute("Weapon")
        cur.lockT, cur.lockId = 0, nil
        drawBar()
      end
    end)
    char.ChildRemoved:Connect(function(c)
      if c == cur.tool then
        cur.tool, cur.id, cur.firing, cur.aiming = nil, nil, false, false
        drawBar()
      end
    end)
    task.delay(0.6, drawBar)
    local bp = player:WaitForChild("Backpack", 5)
    if bp then
      bp.ChildAdded:Connect(function() task.defer(drawBar) end)
    end
    task.delay(0.8, function() if char.Parent and not cur.tool then equip(1) end end)   -- 出生拿第一把
  end
  player.CharacterAdded:Connect(onChar)
  if player.Character then onChar(player.Character) end

  ---------------------------------------------------------------- 瞄准

  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  -- 屏幕中间（准星）对着的点；ground 只要地面（迫击炮、放东西）
  local function aimPoint(range, ground)
    local vp = cam.ViewportSize
    local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
    rayP.FilterDescendantsInstances = { player.Character, G.fxFolder, G.viewFolder }
    if ground then rayP.FilterDescendantsInstances = { player.Character, G.fxFolder, G.viewFolder, workspace:FindFirstChild("Ents") } end
    local res = workspace:Raycast(ray.Origin, ray.Direction * (range or 1500), rayP)
    if res then return res.Position, res.Instance end
    return ray.Origin + ray.Direction * (range or 1500), nil
  end
  G.aimPoint = aimPoint

  -- 防空导弹锁定：准星 12° 以内、射程内最近的敌方飞机直升机
  local function lockCandidate(w)
    local look = cam.CFrame.LookVector
    local best, bd = nil, math.huge
    local ents = workspace:FindFirstChild("Ents")
    if not ents then return nil end
    for _, m in ipairs(ents:GetChildren()) do
      if m:GetAttribute("Cat") == "air" and m:GetAttribute("Team") ~= player:GetAttribute("Side") then
        local r = m:FindFirstChild("Root")
        if r then
          local to = r.Position - cam.CFrame.Position
          local d = to.Magnitude
          if d < w.range and to.Unit:Dot(look) > math.cos(math.rad(12)) and d < bd then best, bd = m, d end
        end
      end
    end
    return best
  end

  local function nearestFriendlyEnt(range)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local ents = workspace:FindFirstChild("Ents")
    if not hrp or not ents then return nil end
    local best, bd = nil, math.huge
    for _, m in ipairs(ents:GetChildren()) do
      local r = m:FindFirstChild("Root")
      if r and m:GetAttribute("Team") == player:GetAttribute("Side") and m:GetAttribute("Cat") ~= "inf" and m:GetAttribute("Cat") ~= "fort" then
        local d = (r.Position - hrp.Position).Magnitude - math.max(r.Size.X, r.Size.Z) / 2
        if d < range and d < bd then best, bd = m, d end
      end
    end
    return best
  end

  ---------------------------------------------------------------- 开火

  local function tryFire(alt)
    local id = cur.id
    local char = player.Character
    if not id or not char or G.drive then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local S = G.S
    if not S or S.phase ~= "battle" then return end
    local w = W[id]
    local t = now()
    if t < cur.nextShot then return end
    if w.kind == "heal" then
      cur.nextShot = t + w.cd
      RShoot:FireServer(id)
      return
    end
    if w.kind == "spot" then
      cur.nextShot = t + (alt and 0.5 or w.cd)
      local p = aimPoint(w.range, alt)
      RShoot:FireServer(id, p, alt and "strike" or nil)
      return
    end
    if w.kind == "repair" then
      cur.nextShot = t + 0.25
      local m = nearestFriendlyEnt(w.range)
      if m then RShoot:FireServer(id, m:GetAttribute("EntId")) end
      return
    end
    if w.kind == "place" and id == "c4" and alt then
      cur.nextShot = t + 0.4
      RShoot:FireServer(id, "det")
      return
    end
    local a = ammoOf(id)
    if a.r > 0 then return end
    if a.n <= 0 then reload() return end
    cur.nextShot = t + (w.rate or 0.2)
    a.n -= 1
    if a.n <= 0 then reload() end
    if w.kind == "gun" then
      local p = aimPoint(w.range)
      local handle = cur.tool and cur.tool:FindFirstChild("Handle")
      local mz = handle and handle:FindFirstChild("Muzzle")
      if G.gunFx and mz then G.gunFx(id, mz.WorldPosition, p, true) end
      RShoot:FireServer(id, p)
      if G.kick then G.kick(w) end
    elseif w.kind == "lock" then
      RShoot:FireServer(id, cur.lockId, aimPoint(w.range))
      cur.lockT, cur.lockId = 0, nil
    elseif w.kind == "mortar" or w.kind == "place" then
      RShoot:FireServer(id, (aimPoint(w.maxR or 60, true)))
    else
      RShoot:FireServer(id, (aimPoint(w.range or 800)))
    end
  end

  ---------------------------------------------------------------- 输入

  UIS.InputBegan:Connect(function(io, gp)
    if gp or G.drive then return end
    local k = io.KeyCode
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      cur.firing = true
      tryFire(false)
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
      cur.aiming = true
      if cur.id and (W[cur.id].kind == "place") then tryFire(true) end
    elseif k == Enum.KeyCode.R then reload()
    elseif k == Enum.KeyCode.F then
      if cur.id and W[cur.id].kind == "spot" then tryFire(true) end
    elseif k == Enum.KeyCode.One then equip(1)
    elseif k == Enum.KeyCode.Two then equip(2)
    elseif k == Enum.KeyCode.Three then equip(3)
    elseif k == Enum.KeyCode.Four then equip(4)
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 then cur.firing = false
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 then cur.aiming = false end
  end)

  -- 手机：开火（按住）、瞄准、换弹、换武器、F
  if UIS.TouchEnabled then
    local function tbtn(text, pos, size)
      local b = ui.button(hud, text, UDim2.fromOffset(size or 70, size or 70), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 15
      return b
    end
    local fire = tbtn("●", UDim2.new(1, -110, 1, -300), 90)
    fire.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then cur.firing = true tryFire(false) end end)
    fire.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then cur.firing = false end end)
    local aim = tbtn("◎", UDim2.new(1, -200, 1, -250))
    aim.Activated:Connect(function() cur.aiming = not cur.aiming end)
    local rl = tbtn("R", UDim2.new(1, -200, 1, -330), 56)
    rl.Activated:Connect(reload)
    local sw = tbtn("⇄", UDim2.new(1, -110, 1, -390), 56)
    sw.Activated:Connect(function()
      local list = tools()
      local i = cur.tool and cur.tool:GetAttribute("Slot") or 0
      for k = 1, 4 do
        local j = (i + k - 1) % 4 + 1
        if list[j] then equip(j) return end
      end
    end)
    local fbtn = tbtn("F", UDim2.new(1, -280, 1, -300), 56)
    fbtn.Activated:Connect(function() tryFire(true) end)
  end

  ---------------------------------------------------------------- 每帧

  local function weaponHud()
    local id = cur.id
    if not id then
      ammoText.Text = ""
      tipText.Text = ""
      return
    end
    local w = W[id]
    local a = ammoOf(id)
    local name = T("weapon." .. id)
    if w.kind == "heal" or w.kind == "repair" or w.kind == "spot" then
      ammoText.Text = name
    elseif a.r > 0 then
      ammoText.Text = T("ui.reloading", name)
    else
      ammoText.Text = T("ui.ammo", name, a.n, a.res and tostring(a.res) or "∞") .. (G.mobile and "" or ("   " .. T("ui.reloadKey")))
    end
    tipText.Text = ""
    if w.kind == "lock" then
      if cur.lockId then tipText.Text = T("ui.locked")
      elseif cur.lockT > 0 then tipText.Text = T("ui.locking") end
    elseif w.kind == "mortar" then
      local p = aimPoint(w.maxR + 200, true)
      local char = player.Character
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hrp then
        local d = (V(p.X, 0, p.Z) - V(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
        tipText.Text = math.floor(d) .. (G.lang == "zh" and " 格" or " studs") .. ((d < w.minR or d > w.maxR) and ("  " .. T("ui.mortarRange", w.minR, w.maxR)) or "")
      end
    end
  end

  local baseFov = 70
  function G.stepPlay(dt)
    if G.drive then   -- 开着车：镜头、开火归 Drive 管
      cross.Visible, scope.Visible = false, false
      cur.firing = false
      return
    end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local armed = cur.id ~= nil and hum and hum.Health > 0 and not G.drive and not (hrp and hrp.Anchored)
    -- 肩后视角：鼠标锁在中间、人跟着镜头转
    if armed and not G.mobile then
      UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
      hum.AutoRotate = false
      hum.CameraOffset = hum.CameraOffset:Lerp(V(1.9, 0.5, 0), math.min(1, dt * 10))
      local look = cam.CFrame.LookVector
      local yaw = math.atan2(-look.X, -look.Z)
      hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0)
    elseif hum then
      if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
      hum.AutoRotate = true
      hum.CameraOffset = hum.CameraOffset:Lerp(V(), math.min(1, dt * 10))
    end
    cross.Visible = armed == true
    -- 瞄准：拉近；狙击镜、望远镜放大得多
    local w = cur.id and W[cur.id]
    local zoom = 1
    if armed and cur.aiming and w then
      if w.scope or w.kind == "spot" then zoom = (w.scope or 5) else zoom = 1.35 end
    end
    scope.Visible = armed and cur.aiming and w and (w.scope ~= nil or w.kind == "spot") or false
    cam.FieldOfView = cam.FieldOfView + (baseFov / zoom - cam.FieldOfView) * math.min(1, dt * 12)
    -- 连发
    if cur.firing and armed and w and (w.auto or w.kind == "repair") then tryFire(false) end
    -- 防空导弹锁定：右键按住对准
    if armed and w and w.kind == "lock" then
      local m = cur.aiming and lockCandidate(w) or nil
      if m then
        cur.lockT += dt
        if cur.lockT >= w.lockTime then cur.lockId = m:GetAttribute("EntId") end
      else
        cur.lockT, cur.lockId = 0, nil
      end
    end
    weaponHud()
    local a = now() - hitT
    hitX.TextTransparency = math.clamp(a / 0.25, 0, 1)
  end
end

return Play
