-- Roblox全面大战场（客户端）——开地面载具：位置在本地算（按地形贴地、坡太陡上不去、不会游的不下水、撞房子停），每秒 15 次报给服务器；
--   镜头：追尾（鼠标绕着车转），右键 / V 进炮长瞄准镜（镜头在瞄准镜的位置、顺着炮管看，滚轮 / Z 换倍率）；
--   瞄准镜四种模式（N 切换）：昼光、夜视（绿色、颗粒、圆形目镜）、热成像白热（背景压暗、人和车发白光）、热成像黑热（反过来）——
--     热的东西用 Highlight 标出来：所有实体的样子在一个 Model 里（一个高亮），玩家角色各一个（最多 24 个，挑近的）
--   炮塔跟着准星转（有回转速度上限，炮有俯仰范围），炮弹有下坠（自动按距离抬一点）；左键开火、1 / 2 换武器、X 烟幕弹、F 下车
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Drive = {}

function Drive.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end

  local st = nil   -- 正在开的车
  G.drive, G.myVeh = nil, nil

  ---------------------------------------------------------------- 界面：车的仪表、瞄准镜

  local gui = Instance.new("ScreenGui")
  gui.Name = "Drive"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")

  local panel = ui.frame(gui, UDim2.fromOffset(420, 76), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.3, Vector2.new(0.5, 1))   -- 下面让出操作说明那一行（UI.lua）
  ui.round(panel, 10)
  panel.Visible = false
  local vName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local vInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 42), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local relBg = ui.frame(panel, UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 63), RGB(0, 0, 0), 0.5)
  local relBar = ui.frame(relBg, UDim2.fromScale(0, 1), nil, RGB(240, 200, 80), 0)

  local cross = ui.label(gui, "◯", UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), 22, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  cross.TextStrokeTransparency = 0.4
  cross.Visible = false
  local gunMark = ui.label(gui, "+", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), 26, RGB(255, 210, 80), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  gunMark.TextStrokeTransparency = 0.3
  gunMark.Visible = false

  -- 瞄准镜：圆形目镜（昼光、夜视）或者长方形屏幕（热成像）；分划、测距、模式、倍率；夜视 / 热成像的颗粒
  local sight = Instance.new("Frame")
  sight.Size = UDim2.fromScale(1, 1)
  sight.BackgroundTransparency = 1
  sight.Visible = false
  sight.Parent = gui
  local eyepiece = Instance.new("Frame")   -- 圆：里面透明，外面一圈很粗的黑描边把四角盖住
  eyepiece.AnchorPoint = Vector2.new(0.5, 0.5)
  eyepiece.Position = UDim2.fromScale(0.5, 0.5)
  eyepiece.Size = UDim2.fromScale(0.9, 0.9)
  eyepiece.BackgroundTransparency = 1
  eyepiece.Parent = sight
  local asp = Instance.new("UIAspectRatioConstraint")
  asp.AspectRatio = 1
  asp.Parent = eyepiece
  local ec = Instance.new("UICorner")
  ec.CornerRadius = UDim.new(0.5, 0)
  ec.Parent = eyepiece
  local es = Instance.new("UIStroke")
  es.Thickness = 900
  es.Color = Color3.new(0, 0, 0)
  es.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  es.Parent = eyepiece
  local screenBox = Instance.new("Frame")   -- 热成像：屏幕的黑边框
  screenBox.AnchorPoint = Vector2.new(0.5, 0.5)
  screenBox.Position = UDim2.fromScale(0.5, 0.5)
  screenBox.Size = UDim2.fromScale(0.86, 0.8)
  screenBox.BackgroundTransparency = 1
  screenBox.Parent = sight
  local ss = Instance.new("UIStroke")
  ss.Thickness = 600
  ss.Color = RGB(8, 8, 8)
  ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  ss.Parent = screenBox
  -- 分划：中心十字、两边的横线、测距刻度（照截图的样子）
  local RET = RGB(235, 235, 235)
  local reticle = Instance.new("Frame")
  reticle.Size = UDim2.fromOffset(300, 120)
  reticle.AnchorPoint = Vector2.new(0.5, 0.5)
  reticle.Position = UDim2.fromScale(0.5, 0.5)
  reticle.BackgroundTransparency = 1
  reticle.Parent = sight
  local retParts = {}
  local function rl(size, pos) local f = ui.frame(reticle, size, pos, RET, 0, Vector2.new(0.5, 0.5)) table.insert(retParts, f) return f end
  rl(UDim2.fromOffset(40, 2), UDim2.new(0.5, -110, 0.5, 0))
  rl(UDim2.fromOffset(40, 2), UDim2.new(0.5, 110, 0.5, 0))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, -56, 0.5, -10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, 56, 0.5, -10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, -56, 0.5, 10))
  rl(UDim2.fromOffset(26, 2), UDim2.new(0.5, 56, 0.5, 10))
  rl(UDim2.fromOffset(2, 26), UDim2.new(0.5, 0, 0.5, -26))
  rl(UDim2.fromOffset(2, 26), UDim2.new(0.5, 0, 0.5, 26))
  local dot = rl(UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5))
  dot.BackgroundTransparency = 1
  local dotStroke = Instance.new("UIStroke")
  dotStroke.Color = RET
  dotStroke.Thickness = 1.5
  dotStroke.Parent = dot
  local dc = Instance.new("UICorner")
  dc.CornerRadius = UDim.new(0.5, 0)
  dc.Parent = dot
  local rangeText = ui.label(sight, "", UDim2.fromOffset(200, 30), UDim2.new(0.5, 0, 0.5, 150), 26, RET, Enum.Font.Code, Vector2.new(0.5, 0.5))
  local modeText = ui.label(sight, "", UDim2.fromOffset(260, 22), UDim2.new(0.5, 0, 0.5, -180), 16, RET, Enum.Font.Code, Vector2.new(0.5, 0.5))
  local zoomText = ui.label(sight, "", UDim2.fromOffset(120, 22), UDim2.new(0.5, 200, 0.5, 150), 16, RET, Enum.Font.Code, Vector2.new(0.5, 0.5))
  local grain = Instance.new("Frame")
  grain.Size = UDim2.fromScale(1, 1)
  grain.BackgroundTransparency = 1
  grain.Parent = sight
  local dots = {}
  for i = 1, 90 do
    local g = ui.frame(grain, UDim2.fromOffset(2, 2), UDim2.new(), RGB(255, 255, 255), 0.7)
    dots[i] = g
  end

  -- 画面效果
  local cc = Instance.new("ColorCorrectionEffect")
  cc.Name = "SightCC"
  cc.Enabled = false
  cc.Parent = Lighting
  G.sightCC = cc
  local MODES = { "day", "nv", "whot", "bhot" }
  local hl = {}   -- 热成像的高亮
  local function clearHl()
    for _, h in ipairs(hl) do h:Destroy() end
    hl = {}
  end
  local function newHl(adornee, color)
    local h = Instance.new("Highlight")
    h.Adornee = adornee
    h.FillColor = color
    h.FillTransparency = 0.08
    h.OutlineColor = color
    h.OutlineTransparency = 0.5
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Parent = cam   -- 镜头下面的东西只在本机
    table.insert(hl, h)
    return h
  end
  -- 热的东西：所有实体（一个 Model）+ 最近的 24 个别的玩家
  local function refreshHl(color)
    clearHl()
    if G.viewFolder then newHl(G.viewFolder, color) end
    local list = {}
    local cp = cam.CFrame.Position
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      if pl ~= me and hrp then table.insert(list, { ch, (hrp.Position - cp).Magnitude }) end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, math.min(24, #list) do newHl(list[i][1], color) end
  end

  local function applyMode()
    if not st or not st.sight then
      cc.Enabled = false
      clearHl()
      sight.Visible = false
      return
    end
    sight.Visible = true
    local m = MODES[st.mode]
    local thermal = m == "whot" or m == "bhot"
    eyepiece.Visible = not thermal
    screenBox.Visible = thermal
    grain.Visible = m ~= "day"
    cc.Enabled = true
    local retCol = RET
    if m == "day" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -0.1, 0.08, 0, Color3.new(1, 1, 1)
      clearHl()
    elseif m == "nv" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.35, 0.06, RGB(120, 255, 140)
      retCol = RGB(190, 255, 190)
      clearHl()
    elseif m == "whot" then
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.45, -0.32, RGB(225, 225, 225)
      refreshHl(Color3.new(1, 1, 1))
    else
      cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = -1, 0.25, 0.22, RGB(235, 235, 235)
      retCol = RGB(20, 20, 20)
      refreshHl(Color3.new(0, 0, 0))
    end
    for _, f in ipairs(retParts) do f.BackgroundColor3 = retCol end
    dotStroke.Color = retCol
    rangeText.TextColor3, modeText.TextColor3, zoomText.TextColor3 = retCol, retCol, retCol
    modeText.Text = T("sight." .. m)
    for _, g in ipairs(dots) do g.BackgroundColor3 = (m == "nv") and RGB(200, 255, 200) or Color3.new(1, 1, 1) end
  end

  -- 自己的车的样子不放在实体的大 Model 里（热成像整个高亮时会把镜头所在的车也涂白）
  local ownBox = Instance.new("Model")
  ownBox.Name = "OwnVeh"
  ownBox.Parent = workspace
  local function ownModel()
    local v = st and G.views and G.views[st.em]
    return v and v.model
  end
  -- 自己的车：坐进瞄准镜时藏起来（镜头在车里）
  local function ownVisible(on)
    local v = st and G.views and G.views[st.em]
    if not v or not v.M then return end
    for _, it in ipairs(v.M.parts) do
      local p = it[1]
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 0 or 1 end
    end
  end

  ---------------------------------------------------------------- 开车

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end

  -- 车底 CFrame：按四个角的地面高度定俯仰、侧倾；在水里（两栖）浮着
  local function baseAt(d, pos, yaw, carried)
    local face = V(-math.sin(yaw), 0, -math.cos(yaw))
    local right = V(-face.Z, 0, face.X)
    if carried and Map.height(pos.X, pos.Z) < 0.6 then   -- 站在气垫艇上、还在水上：车底就是艇的甲板，跟着艇轻轻晃
      local t = os.clock()
      local p = V(pos.X, VD.LCAC.deck + math.sin(t * 1.4) * 0.12, pos.Z)
      return CFrame.lookAt(p, p + face) * CFrame.Angles(math.sin(t * 0.8) * 0.01, 0, math.sin(t * 1.0) * 0.015)
    end
    -- 两栖车：浮着时车底在吃水线（海面下大半个车体）；水浅到履带碰着海底，就踩着海底往上爬（车底取海底和吃水线高的那个），
    --   不会在水深 1.5 格那一下从吃水线弹到海面上
    local draft = d.amphib and d.hullH * 0.55 or nil
    local function gh(p)
      if draft then return math.max(Map.height(p.X, p.Z), -draft) end
      return Map.ground(p.X, p.Z)
    end
    local c = V(pos.X, 0, pos.Z)
    local f, b = c + face * d.L * 0.4, c - face * d.L * 0.4
    local l, r = c - right * d.W * 0.4, c + right * d.W * 0.4
    local yf, yb, yl, yr = gh(f), gh(b), gh(l), gh(r)
    if draft and math.max(yf, yb, yl, yr) <= -draft + 1e-3 then   -- 四个角都够不着海底：浮着，随浪轻轻晃
      local t = os.clock()
      local cf = CFrame.lookAt(V(c.X, -draft + math.sin(t * 1.3) * 0.15, c.Z), V(c.X, -draft, c.Z) + face)
      return cf * CFrame.Angles(math.sin(t * 0.9) * 0.012, 0, math.sin(t * 1.1) * 0.02)
    end
    local y = (yf + yb + yl + yr) / 4
    local fwd = (V(f.X, yf, f.Z) - V(b.X, yb, b.Z)).Unit
    local side = (V(r.X, yr, r.Z) - V(l.X, yl, l.Z)).Unit
    local up = side:Cross(fwd).Unit
    return CFrame.fromMatrix(V(c.X, y, c.Z), side, up, -fwd)
  end

  local mapParams = RaycastParams.new()
  mapParams.FilterType = Enum.RaycastFilterType.Include
  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = VD.get(vs.m)
    if not d then return end
    local root = em.Root.CFrame
    local base = root * CF(0, -d.H / 2, 0)
    local look = base.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    st = { id = vs.id, em = em, d = d, pos = base.Position, yaw = yaw, speed = 0, steer = 0, accel = 0, root = root,
      ty = em:GetAttribute("Ty") or 0, gp = em:GetAttribute("Gp") or 0, camYaw = yaw, camPitch = -0.12, sight = false, mode = 1, zoom = 1,
      wi = 1, sendT = 0, next = {}, firing = false, hlT = 0 }
    G.drive, G.myVeh = st, st
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible = true
    cross.Visible = true
    gunMark.Visible = true
    if G.touchDriveUI then for _, f in ipairs(G.touchDriveUI) do f.Visible = true end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    if st then
      ownVisible(true)
      st.sight = false
      applyMode()
      local m = ownModel()
      if m and m.Parent == ownBox and G.viewFolder then m.Parent = G.viewFolder end
    end
    st = nil
    G.drive, G.myVeh = nil, nil
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible, cross.Visible, gunMark.Visible = false, false, false
    if G.touchDriveUI then for _, f in ipairs(G.touchDriveUI) do f.Visible = false end end
  end

  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  local function physics(dt)
    local d = st.d
    local key = function(k) return UIS:IsKeyDown(k) end
    local thr = (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0)
    local str = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    if G.touchDrive then
      if G.touchDrive.thr ~= 0 then thr = G.touchDrive.thr end
      if G.touchDrive.str ~= 0 then str = G.touchDrive.str end
    end
    local inWater = Map.height(st.pos.X, st.pos.Z) < -1.5
    local carried = st.em ~= nil and st.em:GetAttribute("Lcac") == true   -- 站在气垫艇上（登陆平台出发、不会游的车）：连艇一起开
    local maxF, maxR = d.speed, d.rev
    if inWater then
      if carried then maxF, maxR = VD.LCAC.speed, 12 else maxF, maxR = d.speed * 0.32, d.rev * 0.3 end
    end
    local target = (thr > 0) and maxF or ((thr < 0) and -maxR or 0)
    local a = (carried and inWater) and math.max(d.accel, 18) or d.accel   -- 气垫艇起步比坦克快
    if target == 0 then a = d.accel * 0.8
    elseif (target > 0) ~= (st.speed > 0) and math.abs(st.speed) > 1 then a = d.accel * 2.4 end   -- 反向：先刹车
    local old = st.speed
    st.speed = approach(st.speed, target, a * dt)
    st.accel = (st.speed - old) / math.max(dt, 1e-3)
    -- 转向：履带车能原地转；轮式车要走起来才转得动，倒车反着打
    local k = (d.arch == "wheeled") and math.clamp(math.abs(st.speed) / 10, 0, 1) or 1
    local dir = (d.arch == "wheeled" and st.speed < -0.5) and -1 or 1
    st.yaw -= str * math.rad(d.turn) * k * dir * dt
    st.steer = approach(st.steer, str, dt * 4)
    -- 往前挪：坡太陡、不会游的下水、撞到房子都走不动
    local fwd = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
    local step = st.speed * dt
    if math.abs(step) > 1e-4 then
      local np = st.pos + fwd * step
      local h0 = Map.height(st.pos.X, st.pos.Z)
      local h1 = Map.height(np.X, np.Z)
      local blocked = false
      if h1 < -2.5 and not d.amphib and not carried then blocked = true end
      -- 坡度按地面（海里按水面）算：比约 40° 陡上不去。按前方 4 格取样——原来按这一帧走的距离算（每帧零点几格），
      --   岸边零点几格的小坎就算成陡坡，两栖车卡在水线上不去；帧率越高越容易卡
      local probe = math.max(4, math.abs(step))
      local pa = st.pos + fwd * math.sign(step) * probe
      local ha = Map.height(pa.X, pa.Z)
      if not blocked and ha > 0.5 and (ha - math.max(h0, -0.5)) / probe > 0.85 then blocked = true end
      if not blocked then
        local o = st.pos + V(0, Map.ground(st.pos.X, st.pos.Z) - st.pos.Y + d.hullH * 0.55, 0)
        local res = workspace:Raycast(o, fwd * math.sign(step) * (d.L * 0.5 + math.abs(step) + 0.5), mapParams)
        if res then blocked = true end
      end
      -- 工事、钢刺猬（FortView 给的）：往里开就停（已经卡在里面的让它开出来）
      if not blocked and G.solidAt then
        local ahead = st.pos + fwd * math.sign(step) * (d.L * 0.45 + math.abs(step))
        if G.solidAt(ahead, d.W * 0.4) and not G.solidAt(st.pos, d.W * 0.4) then blocked = true end
      end
      if blocked then
        if math.abs(st.speed) > 12 and G.shake then G.shake(0.25) end
        st.speed = 0
      else
        st.pos = np
      end
    end
    local base = baseAt(d, st.pos, st.yaw, carried)
    st.pos = base.Position
    st.root = base * CF(0, d.H / 2, 0)
  end

  -- 准星打到哪：从镜头往前打一条射线（不算自己的车、实体的样子）
  local function aimPoint()
    local o, dir = cam.CFrame.Position, cam.CFrame.LookVector
    local ex = { G.viewFolder, ownBox }
    if me.Character then table.insert(ex, me.Character) end
    if st.em then table.insert(ex, st.em) end
    aimParams.FilterDescendantsInstances = ex
    local res = workspace:Raycast(o, dir * 4000, aimParams)
    return res and res.Position or (o + dir * 4000), res ~= nil
  end

  local function aimTurret(dt)
    local d = st.d
    local w = VD.W[d.weapons[st.wi] or ""]
    local base = st.root * CF(0, -d.H / 2, 0)
    local piv = (base * CF(d.turret.pivot) * CF(d.gun.pivot)).Position
    local ap = st.aimPt or (piv + base.LookVector * 100)
    local rel = base:VectorToObjectSpace(ap - piv)
    local horiz = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
    local wantYaw = math.deg(math.atan2(rel.X, -rel.Z))
    local wantPitch = math.deg(math.atan2(rel.Y, math.max(horiz, 1)))
    if w and w.kind == "shell" then   -- 炮弹下坠：按飞行时间抬一点
      local tFly = horiz / w.speed
      local drop = 0.5 * workspace.Gravity * 0.55 * (w.drop / 0.55) * tFly * tFly
      wantPitch += math.deg(math.atan2(drop, math.max(horiz, 1)))
    elseif w and w.kind == "arty" then   -- 曲射：炮管抬到大约 45°（只是好看，落点按准星算）
      wantPitch = math.clamp(25 + horiz / 120, 25, 60)
    end
    st.ty = (st.ty + math.clamp(angDiff(st.ty, wantYaw), -d.turret.trav * dt, d.turret.trav * dt)) % 360
    st.gp = approach(st.gp, math.clamp(wantPitch, d.turret.elev[1], d.turret.elev[2]), 35 * dt)
  end

  local function weaponId() return st.d.weapons[st.wi] end

  local function tryFire()
    local wid = weaponId()
    local w = wid and VD.W[wid]
    if not w or st.locked then return end
    local t = os.clock()
    if t < (st.next[wid] or 0) then return end
    local ammo = G.S and G.S.veh and G.S.veh.ammo and G.S.veh.ammo[wid]
    if ammo and ammo[1] <= 0 and ammo[2] <= 0 then return end
    st.next[wid] = t + w.rate
    local base = st.root * CF(0, -st.d.H / 2, 0)
    local mz = VD.muzzle(st.d, base, st.ty, st.gp, (w.kind == "gun" and st.d.coax) and "coax" or nil)
    G.R.Drive:FireServer({ op = "fire", w = wid, dir = mz.LookVector, aim = st.aimPt })
    if w.kind == "shell" or w.kind == "arty" then
      if G.vehRecoil then G.vehRecoil(st.id) end
      if G.shake then G.shake((w.dmg > 300) and 0.35 or 0.06) end
    end
    if ammo then   -- 本地先扣（服务器的数半秒后来校正）
      ammo[1] -= 1
      if ammo[1] <= 0 and ammo[2] > 0 then
        local n = math.min(w.mag, ammo[2])
        ammo[1], ammo[2] = n, ammo[2] - n
        st.next[wid] = t + math.max(w.rate, w.reload or 0)
      end
    end
  end

  ---------------------------------------------------------------- 手机：方向键、开火、烟幕、瞄准镜、模式、下车

  if UIS.TouchEnabled then
    local touch = { thr = 0, str = 0 }
    local tb = ui.frame(gui, UDim2.fromOffset(250, 170), UDim2.new(0, 20, 1, -190), RGB(0, 0, 0), 1)
    tb.Visible = false
    local function hold(text, pos, onDown, onUp)
      local b = ui.button(tb, text, UDim2.fromOffset(64, 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then onDown() end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then onUp() end end)
      return b
    end
    hold("▲", UDim2.fromOffset(93, 0), function() touch.thr = 1 end, function() touch.thr = 0 end)
    hold("▼", UDim2.fromOffset(93, 104), function() touch.thr = -1 end, function() touch.thr = 0 end)
    hold("◀", UDim2.fromOffset(20, 52), function() touch.str = -1 end, function() touch.str = 0 end)
    hold("▶", UDim2.fromOffset(166, 52), function() touch.str = 1 end, function() touch.str = 0 end)
    local rb = ui.frame(gui, UDim2.fromOffset(240, 220), UDim2.new(1, -250, 1, -330), RGB(0, 0, 0), 1)
    rb.Visible = false
    local function tap(text, pos, f)
      local b = ui.button(rb, text, UDim2.fromOffset(64, 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(f)
      return b
    end
    local fb = hold("●", UDim2.fromOffset(0, 0), function() end, function() end)
    fb.Parent = rb
    fb.Size = UDim2.fromOffset(90, 90)
    fb.Position = UDim2.fromOffset(140, 120)
    fb.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = true tryFire() end end)
    fb.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = false end end)
    tap("◎", UDim2.fromOffset(60, 140), function() if st then st.sight = not st.sight ownVisible(not st.sight) applyMode() end end)
    tap("N", UDim2.fromOffset(60, 66), function() if st then st.mode = st.mode % #MODES + 1 applyMode() end end)
    tap("X", UDim2.fromOffset(140, 40), function() G.R.Drive:FireServer({ op = "smoke" }) end)
    tap("F", UDim2.fromOffset(0, 0), function() G.R.Drive:FireServer({ op = "exit" }) end)
    tap("1/2", UDim2.fromOffset(170, -30), function() if st then st.wi = (st.wi % #st.d.weapons) + 1 end end)
    G.touchDrive = touch
    G.touchDriveUI = { tb, rb }
  end

  ---------------------------------------------------------------- 输入

  local ZOOMS = { 20, 7 }   -- 瞄准镜视场（度）：约 3.5×、10×
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      st.firing = true
      tryFire()
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.V then
      st.sight = not st.sight
      ownVisible(not st.sight)
      applyMode()
    elseif k == Enum.KeyCode.N then
      st.mode = st.mode % #MODES + 1
      applyMode()
    elseif k == Enum.KeyCode.Z then
      st.zoom = st.zoom % #ZOOMS + 1
    elseif k == Enum.KeyCode.One or k == Enum.KeyCode.Two then
      local i = (k == Enum.KeyCode.One) and 1 or 2
      if st.d.weapons[i] then st.wi = i end
    elseif k == Enum.KeyCode.X then
      G.R.Drive:FireServer({ op = "smoke" })
    elseif k == Enum.KeyCode.F or k == Enum.KeyCode.E then
      G.R.Drive:FireServer({ op = "exit" })
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then st.firing = false end
  end)
  UIS.InputChanged:Connect(function(io)
    if st and st.sight and io.UserInputType == Enum.UserInputType.MouseWheel then
      st.zoom = math.clamp(st.zoom + ((io.Position.Z > 0) and 1 or -1), 1, #ZOOMS)
    end
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and typeof(m.cf) == "CFrame" then   -- 服务器不认：拉回去
      local base = m.cf * CF(0, -st.d.H / 2, 0)
      local look = base.LookVector
      st.pos, st.yaw, st.speed = base.Position, math.atan2(-look.X, -look.Z), 0
      st.root = m.cf
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  function G.stepDrive(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and (vs.fort or vs.air or vs.ship) then vs = nil end   -- 操作工事归 Gunner 管，飞机归 Fly 管，舰艇归 Sail 管
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    local om = ownModel()
    if om and om.Parent ~= ownBox then om.Parent = ownBox end
    st.locked = vs.locked
    -- 镜头转动
    UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
    local md = UIS:GetMouseDelta()
    local sens = SENS * (st.sight and (ZOOMS[st.zoom] / 70) or 1)
    st.camYaw -= md.X * sens
    st.camPitch = math.clamp(st.camPitch - md.Y * sens, -0.75, 0.6)
    -- 车
    if st.locked then   -- 在气垫艇上：跟着服务器
      st.root = st.em.Root.CFrame
      local base = st.root * CF(0, -d.H / 2, 0)
      st.pos = base.Position
      local look = base.LookVector
      st.yaw = math.atan2(-look.X, -look.Z)
      st.speed = 0
    else
      physics(dt)
    end
    -- 镜头
    local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
    if st.sight then
      local base = st.root * CF(0, -d.H / 2, 0)
      local gcf = VD.gunCF(d, base, st.ty, st.gp)
      local tcf = VD.turretCF(d, base, st.ty)
      local eye = (tcf * CF(d.sight)).Position
      cam.CFrame = CFrame.lookAt(eye, eye + gcf.LookVector)
      cam.FieldOfView = cam.FieldOfView + (ZOOMS[st.zoom] - cam.FieldOfView) * math.min(1, dt * 10)
      -- 瞄准镜里的准星就是炮的指向；鼠标给的是想去的方向
      local o = eye
      local want = dirCam.LookVector
      aimParams.FilterDescendantsInstances = { G.viewFolder, ownBox, st.em, me.Character }
      local res = workspace:Raycast(o, want * 4000, aimParams)
      st.aimPt = res and res.Position or (o + want * 4000)
    else
      local center = st.root.Position + V(0, d.H * 0.4, 0)
      local dist = d.L * 1.25 + 14
      local camPos = center + dirCam:VectorToWorldSpace(V(0, 0, dist)) + V(0, d.H * 0.6, 0)
      cam.CFrame = CFrame.lookAt(camPos, camPos + dirCam.LookVector)
      cam.FieldOfView = cam.FieldOfView + (70 - cam.FieldOfView) * math.min(1, dt * 10)
      st.aimPt = aimPoint()
    end
    aimTurret(dt)
    -- 连发
    local w = VD.W[weaponId() or ""]
    if st.firing and w and w.rate < 0.5 then tryFire() end
    -- 报给服务器（每秒 15 次）
    st.sendT -= dt
    if st.sendT <= 0 and not st.locked then
      st.sendT = 1 / 15
      G.R.Drive:FireServer({ op = "state", cf = st.root, ty = st.ty, gp = st.gp, sp = st.speed })
    end
    -- 炮现在指着哪（追尾镜头里画一个黄十字）
    local base = st.root * CF(0, -d.H / 2, 0)
    local gcf = VD.gunCF(d, base, st.ty, st.gp)
    local gp = gcf.Position + gcf.LookVector * math.max(30, (st.aimPt - gcf.Position).Magnitude)
    local sp, on = cam:WorldToViewportPoint(gp)
    gunMark.Visible = on and not st.sight
    gunMark.Position = UDim2.fromOffset(sp.X, sp.Y)
    cross.Visible = not st.sight
    -- 仪表
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = RGB(230, 70, 60):Lerp(RGB(90, 210, 110), math.clamp(hp / mx, 0, 1))
    vName.Text = T("veh." .. d.id) .. (st.locked and ("   " .. T("ui.lcac")) or "")
    local wid = weaponId()
    local ammo = vs.ammo and wid and vs.ammo[wid]
    local kmh = math.floor(math.abs(st.speed) / 2.8 * 3.6 + 0.5)
    local rel = 1
    if wid and w then
      local left = (st.next[wid] or 0) - os.clock()
      local full = (ammo and ammo[1] == w.mag and left > w.rate) and (w.reload or w.rate) or w.rate
      rel = 1 - math.clamp(left / math.max(full, 0.01), 0, 1)
    end
    relBar.Size = UDim2.fromScale(rel, 1)
    vInfo.Text = T("ui.speed", kmh) .. "    " .. (wid and T("vw." .. wid) or "") .. (ammo and ("  " .. ammo[1] .. " / " .. ammo[2]) or "")
      .. "    " .. T("ui.smokeLeft", vs.smoke or 0) .. "    " .. T("sight." .. MODES[st.mode])
    -- 瞄准镜：测距、倍率、颗粒；热成像的高亮隔一会儿重挑一次
    if st.sight then
      local dist = (st.aimPt - cam.CFrame.Position).Magnitude
      rangeText.Text = string.format("%04d", math.floor(dist / 2.8 / 5 + 0.5) * 5)
      zoomText.Text = string.format("×%.1f", 70 / ZOOMS[st.zoom])
      if grain.Visible then
        local vs2 = cam.ViewportSize
        for _, g in ipairs(dots) do
          g.Position = UDim2.fromOffset(math.random() * vs2.X, math.random() * vs2.Y)
          g.BackgroundTransparency = 0.45 + math.random() * 0.5
        end
      end
      st.hlT -= dt
      local m = MODES[st.mode]
      if st.hlT <= 0 and (m == "whot" or m == "bhot") then
        st.hlT = 0.5
        refreshHl((m == "whot") and Color3.new(1, 1, 1) or Color3.new(0, 0, 0))
      end
    end
  end
end

return Drive
