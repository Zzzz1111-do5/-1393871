-- Roblox全面大战场——操作：武器栏（1–4、点选）、第一人称（默认；镜头前的枪和方块手臂在 FPSView，V 切到第三人称的肩后视角）、
--   开火（连发 / 单发）、右键瞄准（狙击镜）、R 换弹、各种装备（火箭筒、防空导弹右键锁定、手雷、迫击炮、急救包、扳手按住修车、
--   炸药包左键放右键引爆、破障器材按住排雷剪铁丝网、望远镜左键标记 F 呼叫炮击）、命中标记、弹药显示；手机上屏幕按钮
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
  local bar = ui.frame(hud, UDim2.fromOffset(560, 32), UDim2.new(0.5, 0, 1, -50), RGB(0, 0, 0), 1, Vector2.new(0.5, 0))
  local barList = Instance.new("UIListLayout")
  barList.FillDirection = Enum.FillDirection.Horizontal
  barList.HorizontalAlignment = Enum.HorizontalAlignment.Center
  barList.Padding = UDim.new(0, 4)
  barList.Parent = bar
  local slots = {}
  -- 准星：四条细线 + 中间一点，张开多少照这一发的散布（Config.gunSpread：跑起来、跳起来、连射都会张开，停下很快收回；开枪那一下弹一下）
  --   （原来是一个「+」字，看不出现在准不准）
  local cross = Instance.new("Frame")
  cross.Name = "Crosshair"
  cross.AnchorPoint = Vector2.new(0.5, 0.5)
  cross.Position = UDim2.fromScale(0.5, 0.5)
  cross.Size = UDim2.fromOffset(120, 120)
  cross.BackgroundTransparency = 1
  cross.Visible = false
  cross.ZIndex = 15
  cross.Parent = G.gui
  local crossBars = {}
  for i = 1, 5 do
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.BackgroundColor3 = Color3.new(1, 1, 1)
    f.BackgroundTransparency = (i == 5) and 0.15 or 0.12
    f.Size = (i == 5) and UDim2.fromOffset(2, 2) or ((i <= 2) and UDim2.fromOffset(2, 9) or UDim2.fromOffset(9, 2))
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.ZIndex = 15
    local st = Instance.new("UIStroke")   -- 一圈淡黑边：亮的地方也看得清
    st.Color, st.Transparency, st.Thickness = Color3.new(0, 0, 0), 0.55, 1
    st.Parent = f
    f.Parent = cross
    crossBars[i] = f
  end
  local crossGap, crossPop = 8, 0
  local hitX = ui.label(G.gui, "✕", UDim2.fromOffset(34, 34), UDim2.fromScale(0.5, 0.5), 28, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  hitX.TextTransparency = 1
  hitX.ZIndex = 16
  local hitT = 0
  local ammoText = ui.label(hud, "", UDim2.fromOffset(320, 26), UDim2.new(1, -260, 1, -90), 18, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(1, 0), Enum.TextXAlignment.Right)
  ammoText.TextStrokeTransparency = 0.4
  G.ammoLabel = ammoText   -- Hud.lua 换成右下角的武器、弹药（这一行字收起来）
  local tipText = ui.label(G.gui, "", UDim2.fromOffset(300, 22), UDim2.new(0.5, 0, 0.5, 30), 14, RGB(255, 230, 140), Enum.Font.GothamBold, Vector2.new(0.5, 0))
  tipText.TextStrokeTransparency = 0.4
  tipText.ZIndex = 15
  local scope = { Visible = false }   -- 狙击镜、望远镜开镜：圆形目镜和光学效果在 Scope.lua（这里只记开没开）

  -- 命中提示：kind 是 hit / head、打死的 kill / headkill（小兵）、pkill / headpkill（真人）、vkill（车船）、fkill（工事）
  --   打死的红叉、爆头金色（爆头打死橙红），打死的叉先放大再缩回去；加分、连杀在 Juice.lua
  function G.hitMarker(kind)
    local kill = string.find(kind, "kill") ~= nil
    local head = string.find(kind, "head") ~= nil
    hitX.Position = G.hitMarkerAt or UDim2.fromScale(0.5, 0.5)   -- 开飞机时标在炮口指的地方（Fly.lua 每帧设），不然在屏幕中间
    hitX.TextColor3 = (kill and head and RGB(255, 150, 40)) or (kill and RGB(255, 70, 60)) or (head and RGB(255, 220, 80)) or Color3.new(1, 1, 1)
    hitX.TextTransparency = 0
    hitX.TextSize = kill and 44 or (head and 34 or 28)
    hitT = now()
    if G.playSound then G.playSound(kill and "killding" or "hit") end
    if G.onHitMarker then G.onHitMarker(kill and "kill" or kind) end
    if G.juiceHit then G.juiceHit(kind) end
  end

  ---------------------------------------------------------------- 武器栏

  local cur = { tool = nil, id = nil, nextShot = 0, firing = false, aiming = false, lockT = 0, lockId = nil }
  local bloomOf = {}   -- [枪] = { v 连射攒下的散布（度）, t 上一发 }：和服务器 Weapons.lua 一样算，准星照它张开
  local ammo = {}
  function G.refillAmmo() ammo = {} end   -- 补给箱（战术平板）：下次取弹药时按满弹匣、满备弹重新算
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
  -- 现在拿着哪件、弹药（Hud.lua 画右下角）
  function G.weaponNow()
    if not cur.id or not W[cur.id] then return nil end
    return cur.id, ammoOf(cur.id)
  end
  local function reload()
    local id = cur.id
    if not id then return end
    local w = W[id]
    local a = ammoOf(id)
    if a.r > 0 or a.n >= (w.mag or 1) or (a.res and a.res <= 0) or (w.reload or 0) <= 0 then return end
    a.r = now() + w.reload
    RAct:FireServer("reload", id)
    if G.fpsReload then G.fpsReload(id, w.reload, a.n <= 0) end   -- 第一人称：播换弹（打空了是空仓换弹）
  end

  -- 身上的装备，按装备栏格子的顺序排成 1、2、3……（用户：第一人称持枪的时候无法切换枪——原来按格子号，默认不带发射器，
  --   第 2 格是空的，按 2 没反应；现在第几把就按几）
  local function tools()
    local bySlot = {}
    local bp = player:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({ bp, player.Character }) do
      if holder then
        for _, t in ipairs(holder:GetChildren()) do
          if t:IsA("Tool") and t:GetAttribute("Slot") then table.insert(bySlot, t) end
        end
      end
    end
    table.sort(bySlot, function(a, b) return a:GetAttribute("Slot") < b:GetAttribute("Slot") end)
    return bySlot
  end
  local lastTool = nil   -- 上一把（Q 切回去）
  local function equipTool(t)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or G.drive or not t then return end
    if t.Parent == char then return end   -- 已经拿着
    local cur0 = char:FindFirstChildOfClass("Tool")
    if cur0 then lastTool = cur0 end
    hum:EquipTool(t)
  end
  -- 按数字键拿第几件：已经拿着就不动（原来是收起来、变成空手——用户：切到 2 号武器就卡住，多半是连按 / 按住时收起来了）；
  --   0.15 秒内只认一次（键盘连发、和别的界面同时收到按键）
  local lastEquipT = 0
  local function equip(i)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or G.drive then return end
    local t = tools()[i]
    if not t or t.Parent == char then return end
    local now = os.clock()
    if now - lastEquipT < 0.15 then return end
    lastEquipT = now
    equipTool(t)
  end
  -- 滚轮 / 手柄：换下一把、上一把（d = 1 / −1）
  local function cycle(d)
    local list = tools()
    if #list == 0 then return end
    local char = player.Character
    local i0 = 0
    for i, t in ipairs(list) do if t.Parent == char then i0 = i end end
    local j = (i0 == 0) and ((d > 0) and 1 or #list) or ((i0 - 1 + d) % #list + 1)
    equipTool(list[j])
  end
  G.equipSlot = equip
  G.equipCycle = cycle
  G.equipTool = equipTool
  -- 换回上一把（平板界面收起时：TacPad.lua）；没有上一把就拿第一件
  G.equipLast = function()
    if lastTool and lastTool.Parent and lastTool.Parent ~= player.Character then equipTool(lastTool) else equip(1) end
  end

  local function drawBar()
    for _, s in ipairs(slots) do s:Destroy() end
    slots = {}
    for i, t in ipairs(tools()) do
      local id = t:GetAttribute("Weapon")
      local on = t.Parent == player.Character
      -- 细线、半透明、直角（用户：界面要精致简洁，不要卡通）；拿在手里的那格顶上一道白线
      local b = Instance.new("TextButton")
      b.Size = UDim2.fromOffset(124, 32)
      b.BackgroundColor3 = RGB(8, 10, 12)
      b.BackgroundTransparency = on and 0.3 or 0.6
      b.BorderSizePixel = 0
      b.AutoButtonColor = false
      b.Text = i .. "   " .. T("weapon." .. id)
      b.TextSize = 13
      b.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
      b.TextColor3 = on and RGB(255, 255, 255) or RGB(150, 156, 160)
      b.Parent = bar
      if on then ui.frame(b, UDim2.new(1, 0, 0, 2), nil, RGB(255, 255, 255), 0) end
      b.LayoutOrder = i
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
    -- 实体（小兵、车、船、工事）不打服务器的隐形命中盒，按画面上看得见的位置算（View.lua G.viewRay；服务器按你看到的那一刻判定，Rewind.lua）
    rayP.FilterDescendantsInstances = { player.Character, G.fxFolder, G.viewFolder, workspace:FindFirstChild("Ents") }
    local len = range or 1500
    local res = workspace:Raycast(ray.Origin, ray.Direction * len, rayP)
    if not ground and G.viewRay then
      local vp3, vem = G.viewRay(ray.Origin, ray.Direction, res and (res.Position - ray.Origin).Magnitude or len)
      if vp3 then return vp3, vem end
    end
    if res then return res.Position, res.Instance end
    return ray.Origin + ray.Direction * len, nil
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
      local kd = m:GetAttribute("Kind")
      if r and m:GetAttribute("Team") == player:GetAttribute("Side") and m:GetAttribute("Cat") ~= "inf" and kd ~= "c4" and kd ~= "mine" and not m:GetAttribute("Wreck") then
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
    if not w or w.kind == "pad" then return end   -- 战术平板不开火（拿在手上平板界面开着，点的是平板上的地图）
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
    if w.kind == "breach" then return end   -- 破障器材：按住左键排雷 / 剪铁丝网，在 Gunner 的 G.breachStep 里
    if w.kind == "place" and id == "c4" and alt then
      cur.nextShot = t + 0.4
      RShoot:FireServer(id, "det")
      return
    end
    local a = ammoOf(id)
    if a.r > 0 then return end
    if a.n <= 0 then
      if a.res and a.res <= 0 then   -- 没子弹了：扣扳机咔一声（不连着响）
        cur.nextShot = t + 0.35
        if G.sfx then G.sfx("dry") end
      else
        reload()
      end
      return
    end
    cur.nextShot = t + (w.rate or 0.2)
    a.n -= 1
    if a.n <= 0 then reload() end
    if G.fpsFire then G.fpsFire(id) end   -- 第一人称：后坐、枪口火光
    if G.scopeFire then G.scopeFire() end   -- 开着镜：出瞳一甩、像糊一下
    if w.kind == "gun" then
      local p = aimPoint(w.range)
      local handle = cur.tool and cur.tool:FindFirstChild("Handle")
      local mz = handle and handle:FindFirstChild("Muzzle")
      local from = (G.fpsMuzzle and G.fpsMuzzle()) or (mz and mz.WorldPosition)   -- 第一人称时曳光从镜头前那支枪的枪口出去
      if G.gunFx and from then G.gunFx(id, from, p, true) end
      -- 开着镜（镜子已经举到眼前）告诉服务器：散布按开镜算（Config.gunSpread）；镜子还在往上举的那一下按腰射算
      local ads = cur.aiming and not (G.fpsOpticPending and G.fpsOpticPending())
      RShoot:FireServer(id, p, ads and "ads" or nil)
      if w.bloom then   -- 本地也照服务器那样攒连射的散布（准星画多大）
        bloomOf[id] = { v = math.min(w.bloom[2], Config.bloomAt(w, bloomOf[id], t) + w.bloom[1]), t = t }
      end
      crossPop = 1
      if G.kick then G.kick(w, ads, id) end
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
    if G.menuOpen and G.menuOpen() then return end   -- 挂载编辑器里点 3D 的飞机（ViewportFrame 不吞点击）不能开枪
    local k = io.KeyCode
    if G.tacOpen and G.tacOpen() and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.MouseButton2
      or k == Enum.KeyCode.One or k == Enum.KeyCode.Two or k == Enum.KeyCode.Three or k == Enum.KeyCode.Four or k == Enum.KeyCode.Five) then
      return   -- 平板开着：鼠标点平板、数字键选支援（TacPad.lua），不切枪、不开火
    end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      cur.firing = true
      tryFire(false)
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
      cur.aiming = true
      if cur.id and (W[cur.id].kind == "place") then tryFire(true) end
    elseif k == Enum.KeyCode.R then reload()
    elseif k == Enum.KeyCode.V then G.firstPerson = not (G.firstPerson ~= false)   -- 第一 / 第三人称
    elseif k == Enum.KeyCode.F then
      if cur.id and W[cur.id].kind == "spot" then tryFire(true) end
    elseif k == Enum.KeyCode.One then equip(1)
    elseif k == Enum.KeyCode.Two then equip(2)
    elseif k == Enum.KeyCode.Three then equip(3)
    elseif k == Enum.KeyCode.Four then equip(4)
    elseif k == Enum.KeyCode.Five then equip(5)
    elseif k == Enum.KeyCode.Q then   -- 切回上一把
      if lastTool and lastTool.Parent and lastTool.Parent ~= player.Character then equipTool(lastTool) else cycle(1) end
    end
  end)
  -- 滚轮换枪（开着狙击镜时滚轮是变倍，Scope.lua 管）
  UIS.InputChanged:Connect(function(io, gp)
    if gp or G.drive or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if G.scopeOn or (G.menuOpen and G.menuOpen()) or not G.fpActive then return end   -- 第三人称时滚轮还是拉镜头
    if io.Position.Z ~= 0 then cycle((io.Position.Z < 0) and 1 or -1) end
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
    sw.Activated:Connect(function() cycle(1) end)
    local fbtn = tbtn("F", UDim2.new(1, -200, 1, -170), 56)
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
    if w.kind == "heal" or w.kind == "repair" or w.kind == "spot" or w.kind == "breach" then
      ammoText.Text = name
    elseif a.r > 0 then
      ammoText.Text = T("ui.reloading", name)
    else
      -- 「R 换弹」只在打空了时提示（用户：持枪第一视角不要显示键位）
      ammoText.Text = T("ui.ammo", name, a.n, a.res and tostring(a.res) or "∞") .. ((G.mobile or a.n > 0) and "" or ("   " .. T("ui.reloadKey")))
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
  local fpMode = nil
  -- 第一人称：镜头最近、最远都设 0.5（Roblox 就进第一人称，鼠标锁在中间、人跟着镜头转）；第三人称：拉开到肩后
  local function setFirstPerson(on)
    if fpMode == on then return end
    fpMode = on
    if on then
      player.CameraMinZoomDistance, player.CameraMaxZoomDistance = 0.5, 0.5
    else
      player.CameraMaxZoomDistance = 40
      player.CameraMinZoomDistance = 8
    end
  end
  function G.stepPlay(dt)
    if G.drive then   -- 开着车：镜头、开火归 Drive 管；武器栏、弹药字藏起来（载具面板在同一个位置）
      cross.Visible, scope.Visible, bar.Visible = false, false, false
      if G.scopeStep then G.scopeStep(dt, false) end
      ammoText.Text, tipText.Text = "", ""
      cur.firing = false
      G.fpActive = false
      if G.fpsOff then G.fpsOff() end
      return
    end
    bar.Visible = true
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local armed = cur.id ~= nil and hum and hum.Health > 0 and not G.drive and not (hrp and hrp.Anchored)
    local fp = G.firstPerson ~= false and hum ~= nil and hum.Health > 0 and not (hrp and hrp.Anchored)
    G.fpActive = fp   -- 步行第一人称（UI 据此藏鼠标指针、底部键位说明）
    local menu = G.menuOpen and G.menuOpen()
    if menu then cur.firing, cur.aiming = false, false end
    if hum and hum.Health > 0 then setFirstPerson(fp) end
    baseFov = fp and 62 or 70   -- 第一人称的枪照竖直视角约 60° 做的（原动作包的相机水平 90°）
    if fp then
      hum.AutoRotate = true
      hum.CameraOffset = V()
    elseif armed and not G.mobile and not menu then   -- 第三人称：肩后视角，鼠标锁在中间、人跟着镜头转（开着挂载编辑器时不锁）
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
    local wc = cur.id and W[cur.id]
    cross.Visible = armed == true and not (fp and cur.aiming) and not (cur.aiming and wc and (wc.scope ~= nil or wc.kind == "spot"))   -- 开着镜不画准星（第三人称也是）
    if cross.Visible and wc and hrp then
      -- 张开多少：这一发的散布在屏幕上有多宽（跑起来、跳起来、连射攒的都算），开枪那一下再弹开一点
      local okv, v = pcall(function() return hrp.AssemblyLinearVelocity end)   -- 读不到（测试台）就当站着不动
      if not okv or typeof(v) ~= "Vector3" then v = V() end
      local okf, fm = pcall(function() return hum.FloorMaterial end)
      local air = okf and fm == Enum.Material.Air and math.abs(v.Y) > 1.5
      local b = Config.bloomAt(wc, bloomOf[cur.id], now())
      local deg = (wc.kind == "gun") and Config.gunSpread(wc, false, V(v.X, 0, v.Z).Magnitude, air, b) or math.max(wc.spread or 0.4, 0.4)
      -- 服务器的散布是方形的（每个方向各自 ±deg），斜着最远约 1.4 倍：准星的线画在最远那一圈
      local px = cam.ViewportSize.Y / 2 * math.tan(math.rad(deg * 1.4)) / math.tan(math.rad(cam.FieldOfView / 2))
      crossGap += (math.clamp(px, 4, 90) + crossPop * 5 - crossGap) * math.min(1, dt * 18)
      crossPop = math.max(0, crossPop - dt * 9)
      local g = math.floor(crossGap + 0.5) + 4
      crossBars[1].Position = UDim2.new(0.5, 0, 0.5, -g)
      crossBars[2].Position = UDim2.new(0.5, 0, 0.5, g)
      crossBars[3].Position = UDim2.new(0.5, -g, 0.5, 0)
      crossBars[4].Position = UDim2.new(0.5, g, 0.5, 0)
    end
    -- 瞄准：拉近；狙击镜、望远镜放大得多
    local w = cur.id and W[cur.id]
    local zoom = 1
    if armed and cur.aiming and w then
      if w.scope or w.kind == "spot" then zoom = G.scopeZoom and G.scopeZoom(w) or (w.scope or 5) else zoom = 1.35 end   -- 镜子的倍率滚轮能变
    end
    scope.Visible = armed and cur.aiming and w and (w.scope ~= nil or w.kind == "spot") or false
    if G.scopeStep then G.scopeStep(dt, scope.Visible, w) end
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
    -- 第一人称：镜头前的枪和方块手臂（狙击镜、望远镜放大时藏起来）
    if G.stepFPS then
      if fp and armed then G.stepFPS(dt, true, cur.aiming, scope.Visible, cur.tool) elseif G.fpsOff then G.fpsOff() end
    end
    if G.breachStep then   -- 破障器材：探雷标记、按住排雷 / 剪铁丝网的进度
      local tip = G.breachStep(dt, armed and w and w.kind == "breach" or false, cur.firing)
      if tip then tipText.Text = tip end
    end
    local a = now() - hitT
    hitX.TextTransparency = math.clamp(a / 0.25, 0, 1)
    if hitX.TextSize > 28 then hitX.TextSize = math.max(28, hitX.TextSize - 90 * (1 / 60)) end   -- 打死的大叉缩回去
  end
end

return Play
