-- Roblox全面大战场（客户端）——开船：位置在本地算（车钟定航速、舵慢慢打过去、要有航速才转得动；船头碰到浅水、码头、别的船就停），每秒 15 次报给服务器
--   W / S 车钟加一档 / 减一档（后退二 … 全速前进）、A / D 按住打舵（松开回正舵）；鼠标转镜头（追尾），右键 / V 望远镜（舰桥上看出去，Z 换倍率）
--   1 舰炮：炮塔跟着准星转（回转速度、射界、俯仰照型号），按弹道自动抬炮；画面上黄色小十字是现在炮管指向的落点；左键开火（机枪、30 毫米炮按住连发）
--   2 反舰导弹：准星附近 10° 以内最近的敌方水面 / 岸上目标自动框住，R 锁住 / 解锁；左键发射（没框住目标就打准星下那一点）
--   防空导弹、近防炮是自动的（服务器）；回到自己码头停稳补弹、修理；F 下船
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Sail = {}

function Sail.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local SD = require(RS:WaitForChild("ShipDefs"))
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end
  local SHELL_G = workspace.Gravity * 0.55

  local st = nil
  G.sail = nil

  ---------------------------------------------------------------- 界面

  local gui = Instance.new("ScreenGui")
  gui.Name = "Sail"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")

  local panel = ui.frame(gui, UDim2.fromOffset(470, 96), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.3, Vector2.new(0.5, 1))
  panel.Visible = false
  local vName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 6), UDim2.fromOffset(10, 29), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local info1 = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 39), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local info2 = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 59), 14, RGB(222, 226, 230), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local relBg = ui.frame(panel, UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 83), RGB(0, 0, 0), 0.5)
  local relBar = ui.frame(relBg, UDim2.fromScale(0, 1), nil, RGB(240, 200, 80), 0)
  ui.flatPanel(panel, { hp = hpBg, rel = relBg, name = vName })   -- 跟新界面一个样子（UI.lua）

  local cross = ui.label(gui, "◯", UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), 22, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  cross.TextStrokeTransparency = 0.4
  cross.Visible = false
  local gunMark = ui.label(gui, "+", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), 26, RGB(255, 210, 80), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  gunMark.TextStrokeTransparency = 0.3
  gunMark.Visible = false
  -- 导弹的锁定框（四角）
  local lockBox = Instance.new("Frame")
  lockBox.AnchorPoint = Vector2.new(0.5, 0.5)
  lockBox.Size = UDim2.fromOffset(46, 46)
  lockBox.BackgroundTransparency = 1
  lockBox.Visible = false
  lockBox.Parent = gui
  local lockStroke = Instance.new("UIStroke")
  lockStroke.Color = RGB(255, 80, 60)
  lockStroke.Thickness = 2
  lockStroke.Parent = lockBox
  local lockText = ui.label(gui, "", UDim2.fromOffset(360, 20), UDim2.new(0.5, 0, 0.5, 46), 14, RGB(255, 120, 100), Enum.Font.GothamBold, Vector2.new(0.5, 0))
  lockText.TextStrokeTransparency = 0.4
  lockText.Visible = false
  local warn = ui.label(gui, "", UDim2.fromOffset(400, 30), UDim2.new(0.5, 0, 0, 120), 24, RGB(255, 90, 70), Enum.Font.GothamBlack, Vector2.new(0.5, 0))
  warn.TextStrokeTransparency = 0.3
  warn.Visible = false
  -- 望远镜：四周压暗的框、倍率
  local bino = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  bino.Visible = false
  local binoIn = Instance.new("Frame")
  binoIn.AnchorPoint, binoIn.Position, binoIn.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.82, 0.7)
  binoIn.BackgroundTransparency = 1
  binoIn.Parent = bino
  local bs = Instance.new("UIStroke")
  bs.Thickness = 700
  bs.Color = Color3.new(0, 0, 0)
  bs.Transparency = 0.25
  bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  bs.Parent = binoIn
  local binoText = ui.label(bino, "", UDim2.fromOffset(260, 22), UDim2.new(0.5, 0, 0.85, 0), 16, RGB(230, 230, 230), Enum.Font.Code, Vector2.new(0.5, 0.5))

  ---------------------------------------------------------------- 开船

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end
  local mapParams = RaycastParams.new()
  mapParams.FilterType = Enum.RaycastFilterType.Include
  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  local function begin(vs)
    local em = findEnt(vs.id)
    local d = SD.get(vs.m or "")
    if not em or not d then return end
    local root = em.Root.CFrame
    local base = root * CF(0, -(d.H / 2 - d.draft), 0)
    local look = base.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local p = base.Position
    st = { id = vs.id, em = em, d = d, pos = V(p.X, 0, p.Z), yaw = yaw, speed = 0, order = 0, rudder = 0, rcmd = 0,
      camYaw = yaw, camPitch = -0.18, bino = false, zoom = 1, wi = 1, ty = {}, gp = {}, next = {}, onT = {}, sendT = 0, firing = false,
      lock = nil, sticky = false, lockT = 0, mslT = 0, warnT = 0, rwrT = 0, help = "ship.help" }
    for gi in ipairs(d.guns) do st.ty[gi], st.gp[gi], st.next[gi] = em:GetAttribute("Ty" .. gi) or 0, em:GetAttribute("Gp" .. gi) or 0, 0 end
    st.cf = CFrame.lookAt(st.pos, st.pos + V(-math.sin(yaw), 0, -math.cos(yaw)))
    G.sail, G.drive = st, st   -- G.drive：步兵的操作（Play）先停下、界面最下面一行换成开船说明
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible, cross.Visible = true, true
    if G.touchSailUI then for _, f in ipairs(G.touchSailUI) do f.Visible = true end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    if st and st.trigOn then G.R.Drive:FireServer({ op = "trig", on = false, g = st.trigG }) end
    local old = st
    st = nil
    G.sail = nil
    if G.drive == old then G.drive = nil end
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible, cross.Visible, gunMark.Visible, lockBox.Visible, lockText.Visible, warn.Visible, bino.Visible = false, false, false, false, false, false, false
    if G.touchSailUI then for _, f in ipairs(G.touchSailUI) do f.Visible = false end end
  end

  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end
  local function fwdOf(yaw) return V(-math.sin(yaw), 0, -math.cos(yaw)) end

  -- 这一点水够不够深（船吃水的三成以上）
  local function deep(p, d) return Map.height(p.X, p.Z) < -d.draft * 0.35 end
  -- 船头（倒车时船尾）前面撞上码头、平台、别的船没有
  local function blockedAt(np, yaw, dir, d)
    local f = fwdOf(yaw)
    local r = V(-f.Z, 0, f.X)
    local tip = np + f * dir * (d.L / 2)
    local pts = { tip, np + f * dir * (d.L * 0.32) + r * (d.W * 0.45), np + f * dir * (d.L * 0.32) - r * (d.W * 0.45) }
    for _, p in ipairs(pts) do
      if not deep(p, d) then return "shallow" end
      if math.abs(p.X) > Map.SEA_LIM or math.abs(p.Z) > Map.SEA_LIM then return "edge" end
    end
    -- 码头、登陆平台、舰队（地图零件）：从船头往前打一小段射线
    local res = workspace:Raycast(tip + V(0, 2.5, 0) - f * dir * 2, f * dir * 6, mapParams)
    if res then return "hit" end
    -- 别的船：船头这一点在不在它的船体方块里（宽出 3 格）
    for em, v in pairs(G.views or {}) do
      if v.kind == "ship" and em ~= st.em and v.root and v.root.Parent and not em:GetAttribute("Wreck") then
        local l = v.root.CFrame:PointToObjectSpace(V(tip.X, v.root.CFrame.Position.Y, tip.Z))
        local s = v.root.Size
        if math.abs(l.X) < s.X / 2 + 3 and math.abs(l.Z) < s.Z / 2 + 3 then return "hit" end
      end
    end
    return nil
  end

  local function physics(dt)
    local d = st.d
    local tgt = d.speed * (SD.ORDERS[st.order] or 0)
    local a = (math.abs(tgt) < math.abs(st.speed) or (tgt > 0) ~= (st.speed > 0)) and d.accel * 0.8 or d.accel
    st.speed = approach(st.speed, tgt, a * dt)
    -- 舵：按住慢慢打过去（满舵约 1.2 秒），松开回正；转得动要有航速
    local cmd = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
    if G.touchSail and G.touchSail.str ~= 0 then cmd = G.touchSail.str end
    st.rcmd = cmd
    st.rudder = approach(st.rudder, cmd, dt * 0.85)
    local eff = math.clamp(math.abs(st.speed) / (d.speed * 0.35), 0.06, 1) * ((st.speed < -0.5) and -1 or 1)
    -- 驾驶手感（用户：驾驶手感也做到最好）：舵打下去船头要一会儿才转起来、回正以后还接着转一阵（船越长越迟钝）；
    --   转弯掉速（满舵全速每秒掉 8% 上下）；船身往外侧滑——前进方向慢半拍才跟上船头
    local lag = math.clamp((d.L or 60) / 110, 0.5, 2.6)
    st.yr = (st.yr or 0) + (st.rudder * math.rad(d.turn) * eff - (st.yr or 0)) * math.min(1, dt / lag)
    local ny = st.yaw - st.yr * dt
    st.speed -= st.speed * math.clamp(math.abs(st.yr) / math.max(math.rad(d.turn), 1e-3), 0, 1) * 0.08 * dt
    st.slip = (st.slip or 0) + (st.yr * math.abs(st.speed) * 0.025 - (st.slip or 0)) * math.min(1, dt * 1.1)
    local right = V(math.cos(ny), 0, -math.sin(ny))
    local step = st.speed * dt
    local np = st.pos + fwdOf(ny) * step - right * st.slip * dt
    local why = (math.abs(step) > 1e-4) and blockedAt(np, ny, (step > 0) and 1 or -1, d) or nil
    if why then
      if math.abs(st.speed) > d.speed * 0.3 and G.shake then G.shake(0.3) end
      st.speed = -st.speed * 0.15   -- 顶住了：往回弹一点
      if why == "shallow" then st.warnT = os.clock() + 2 end
      st.yaw = ny
    else
      st.pos, st.yaw = np, ny
    end
    st.cf = CFrame.lookAt(st.pos, st.pos + fwdOf(st.yaw))
  end

  -- 准星打到哪（不算自己的船；实体的样子不挡射线，打到的是命中盒、地形、海面）
  local function aimPoint()
    local o, dir = cam.CFrame.Position, cam.CFrame.LookVector
    local ex = { st.em }
    if me.Character then table.insert(ex, me.Character) end
    if G.viewFolder then table.insert(ex, G.viewFolder) end
    aimParams.FilterDescendantsInstances = ex
    local res = workspace:Raycast(o, dir * 6000, aimParams)
    if res then return res.Position end
    if dir.Y < -0.01 then   -- 没打到东西但朝下：落在海平面上
      local t = -o.Y / dir.Y
      if t > 0 and t < 9000 then return o + dir * t end
    end
    return o + dir * 6000
  end

  local function lowAngle(v, g, R, h)
    local v2 = v * v
    local disc = v2 * v2 - g * (g * R * R + 2 * h * v2)
    if disc < 0 or R < 1 then return nil end
    return math.atan((v2 - math.sqrt(disc)) / (g * R))
  end

  -- 炮塔转向准星：直射的机枪对着打；炮弹按弹道抬（打不到就抬到 45°）
  local function aimGuns(dt)
    local d = st.d
    local cf = st.cf
    local ap = st.aimPt
    for gi, g in ipairs(d.guns) do
      local w = SD.W[g.w]
      local piv = SD.gunCF(d, cf, gi, st.ty[gi], 0).Position
      local rel = ap - piv
      local hz = V(rel.X, 0, rel.Z)
      local dir
      if w.kind == "gun" or hz.Magnitude < 1 then dir = rel.Unit else
        local th = lowAngle(w.speed, SHELL_G * w.gscale, hz.Magnitude, rel.Y) or math.rad(45)
        dir = hz.Unit * math.cos(th) + V(0, math.sin(th), 0)
      end
      local l = cf:VectorToObjectSpace(dir)
      if g.aft then l = V(-l.X, l.Y, -l.Z) end
      local wy = math.deg(math.atan2(l.X, -l.Z))
      local wp = math.deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)))
      local inArc = math.abs(wy) <= g.arc
      local goal = math.clamp(wy, -g.arc, g.arc)
      st.ty[gi] = st.ty[gi] + math.clamp(angDiff(st.ty[gi], goal), -g.trav * dt, g.trav * dt)
      st.gp[gi] = approach(st.gp[gi], math.clamp(wp, g.elev[1], g.elev[2]), 30 * dt)
      st.onT[gi] = inArc and math.abs(angDiff(st.ty[gi], wy)) < 1.5 and math.abs(st.gp[gi] - math.clamp(wp, g.elev[1], g.elev[2])) < 1.5
    end
  end

  -- 第 gi 门炮按现在的指向打出去落在哪（炮弹算弹道，落到准星那一点的高度；机枪就是一条直线）
  local function fallOfShot(gi)
    local d = st.d
    local g = d.guns[gi]
    local w = SD.W[g.w]
    local mz = SD.muzzle(d, st.cf, gi, st.ty[gi], st.gp[gi])
    local p0, dir = mz.Position, mz.LookVector
    if w.kind == "gun" then return p0 + dir * math.min(w.range, (st.aimPt - p0).Magnitude) end
    local gg = SHELL_G * w.gscale
    local vy = dir.Y * w.speed
    local yt = st.aimPt.Y
    local disc = vy * vy + 2 * gg * (p0.Y - yt)
    if disc < 0 then return nil end
    local t = (vy + math.sqrt(disc)) / gg
    return p0 + V(dir.X, 0, dir.Z) * w.speed * t + V(0, yt - p0.Y, 0)
  end

  local function tryFire()
    local d = st.d
    if st.wi == 2 then
      if not d.missiles then return end
      local t = os.clock()
      if t < st.mslT then return end
      local vs = G.S and G.S.veh
      if vs and (vs.msl or 0) <= 0 then return end
      st.mslT = t + 1.3
      G.R.Drive:FireServer({ op = "msl", tgt = st.lock and st.lock.id or nil, aim = st.aimPt })
      return
    end
    local t = os.clock()
    for gi, g in ipairs(d.guns) do
      local w = SD.W[g.w]
      if w.kind == "gun" then
        if not st.trigOn then
          st.trigOn, st.trigG = true, gi
          G.R.Drive:FireServer({ op = "trig", on = true, g = gi, ty = st.ty[gi], gp = st.gp[gi] })
        end
      elseif st.onT[gi] and t >= (st.next[gi] or 0) then
        st.next[gi] = t + w.rate
        G.R.Drive:FireServer({ op = "fire", g = gi, ty = st.ty[gi], gp = st.gp[gi] })
        if G.vehRecoil then G.vehRecoil(st.id, gi) end
        if G.shake then G.shake((w.dmg > 400) and 0.3 or 0.12) end
      end
    end
  end
  local function releaseTrig()
    if st and st.trigOn then
      st.trigOn = false
      G.R.Drive:FireServer({ op = "trig", on = false, g = st.trigG })
    end
  end

  -- 导弹框的目标：准星附近 10° 以内、射程内、看得见的敌方水面 / 岸上目标（舰艇、登陆艇、车、工事），离准星最近的
  local LOCK_KINDS = { ship = true, lcm = true, lcac = true, veh = true, fort = true }
  local function pickLock()
    local d = st.d
    local w = d.missiles and SD.W[d.missiles.w]
    if not w then return nil end
    local side = me:GetAttribute("Side")
    local o, look = cam.CFrame.Position, cam.CFrame.LookVector
    local best, ba = nil, math.rad(10)
    for em, v in pairs(G.views or {}) do
      if LOCK_KINDS[v.kind] and v.team ~= side and em.Parent and v.root and (em:GetAttribute("Hp") or 1) > 0 and not em:GetAttribute("Wreck") then
        local p = v.root.CFrame.Position
        if (p - st.pos).Magnitude < w.range then
          local a = math.acos(math.clamp(look:Dot((p - o).Unit), -1, 1))
          if a < ba then best, ba = v, a end
        end
      end
    end
    return best
  end

  ---------------------------------------------------------------- 手机：车钟、舵、开火、换武器、望远镜、下船

  if UIS.TouchEnabled then
    local touch = { str = 0 }
    local tb = ui.frame(gui, UDim2.fromOffset(250, 170), UDim2.new(0, 20, 1, -190), RGB(0, 0, 0), 1)
    tb.Visible = false
    local function btn(parent, text, pos, size)
      local b = ui.button(parent, text, size or UDim2.fromOffset(64, 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      return b
    end
    btn(tb, "▲", UDim2.fromOffset(93, 0)).Activated:Connect(function() if st then st.order = math.min(5, st.order + 1) end end)
    btn(tb, "▼", UDim2.fromOffset(93, 104)).Activated:Connect(function() if st then st.order = math.max(-2, st.order - 1) end end)
    local function holdStr(b, s)
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch.str = s end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch.str = 0 end end)
    end
    holdStr(btn(tb, "◀", UDim2.fromOffset(20, 52)), -1)
    holdStr(btn(tb, "▶", UDim2.fromOffset(166, 52)), 1)
    local rb = ui.frame(gui, UDim2.fromOffset(240, 220), UDim2.new(1, -250, 1, -330), RGB(0, 0, 0), 1)
    rb.Visible = false
    local fb = btn(rb, "●", UDim2.fromOffset(140, 120), UDim2.fromOffset(90, 90))
    fb.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = true tryFire() end end)
    fb.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch and st then st.firing = false releaseTrig() end end)
    btn(rb, "1/2", UDim2.fromOffset(170, 40)).Activated:Connect(function() if st then releaseTrig() st.wi = (st.wi == 1 and st.d.missiles) and 2 or 1 end end)
    btn(rb, "◎", UDim2.fromOffset(60, 140)).Activated:Connect(function() if st then st.bino = not st.bino end end)
    btn(rb, "R", UDim2.fromOffset(60, 66)).Activated:Connect(function() if st then st.sticky = not st.sticky if st.sticky then st.lock = pickLock() st.sticky = st.lock ~= nil end end end)
    btn(rb, "F", UDim2.fromOffset(0, 0)).Activated:Connect(function() G.R.Drive:FireServer({ op = "exit" }) end)
    G.touchSail = touch
    G.touchSailUI = { tb, rb }
  end

  ---------------------------------------------------------------- 输入

  local ZOOMS = { 24, 9 }   -- 望远镜视场（度）：约 3×、8×
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      st.firing = true
      tryFire()
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.V then
      st.bino = not st.bino
    elseif k == Enum.KeyCode.Z then
      st.zoom = st.zoom % #ZOOMS + 1
    elseif k == Enum.KeyCode.W then
      st.order = math.min(5, st.order + 1)
    elseif k == Enum.KeyCode.S then
      st.order = math.max(-2, st.order - 1)
    elseif k == Enum.KeyCode.One then
      releaseTrig()
      st.wi = 1
    elseif k == Enum.KeyCode.Two then
      if st.d.missiles then releaseTrig() st.wi = 2 end
    elseif k == Enum.KeyCode.R then
      if st.sticky then st.sticky = false else
        st.lock = pickLock()
        st.sticky = st.lock ~= nil
      end
    elseif k == Enum.KeyCode.F then
      G.R.Drive:FireServer({ op = "exit" })
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then
      st.firing = false
      releaseTrig()
    end
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and m.ship and typeof(m.cf) == "CFrame" then   -- 服务器不认（跑太快、搁浅）：拉回去
      local p = m.cf.Position
      local look = m.cf.LookVector
      st.pos, st.yaw, st.speed = V(p.X, 0, p.Z), math.atan2(-look.X, -look.Z), 0
      st.cf = CFrame.lookAt(st.pos, st.pos + fwdOf(st.yaw))
    elseif m.op == "rwr" then
      st.rwrT = os.clock() + 5
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  function G.stepSail(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and not vs.ship then vs = nil end
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    -- 镜头转动
    UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
    local md = UIS:GetMouseDelta()
    local sens = SENS * (st.bino and (ZOOMS[st.zoom] / 70) or 1)
    st.camYaw -= md.X * sens
    st.camPitch = math.clamp(st.camPitch - md.Y * sens, -0.8, 0.5)
    physics(dt)
    local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
    if st.bino then   -- 望远镜：舰桥（第二块上层建筑前面）上看出去
      local s2 = d.look and d.look.sup and d.look.sup[2]
      local eye = s2 and (st.cf * CF(0, s2[5] + s2[4] + 1.5, s2[1] + 2)).Position or (st.cf * CF(0, d.deck + 4, 0)).Position
      cam.CFrame = CFrame.lookAt(eye, eye + dirCam.LookVector)
      cam.FieldOfView = cam.FieldOfView + (ZOOMS[st.zoom] - cam.FieldOfView) * math.min(1, dt * 10)
    else
      local center = st.pos + V(0, d.H * 0.45, 0)
      local dist = d.L * 0.75 + d.H * 0.6 + 20
      local camPos = center + dirCam:VectorToWorldSpace(V(0, 0, dist)) + V(0, d.H * 0.5, 0)
      camPos = V(camPos.X, math.max(camPos.Y, 3), camPos.Z)
      cam.CFrame = CFrame.lookAt(camPos, camPos + dirCam.LookVector)
      cam.FieldOfView = cam.FieldOfView + (70 - cam.FieldOfView) * math.min(1, dt * 10)
    end
    st.aimPt = aimPoint()
    aimGuns(dt)
    if st.firing then tryFire() end
    -- 导弹框：选中导弹时每 0.2 秒重挑（锁住的就一直跟着它，没了才放）
    st.lockT -= dt
    if st.wi == 2 then
      if st.sticky and (not st.lock or not st.lock.em.Parent or st.lock.em:GetAttribute("Wreck") or (st.lock.em:GetAttribute("Hp") or 1) <= 0) then st.sticky, st.lock = false, nil end
      if not st.sticky and st.lockT <= 0 then
        st.lockT = 0.2
        st.lock = pickLock()
      end
    else
      st.lock, st.sticky = nil, false
    end
    -- 报给服务器（每秒 15 次）
    st.sendT -= dt
    if st.sendT <= 0 then
      st.sendT = 1 / 15
      G.R.Drive:FireServer({ op = "state", cf = st.cf, sp = st.speed, o = st.order, ty = st.ty, gp = st.gp })
    end
    -- 画面：弹着点、锁定框、警告
    gunMark.Visible = false
    if st.wi == 1 and d.guns[1] then
      local fp = fallOfShot(1)
      if fp then
        local sp, on = cam:WorldToViewportPoint(fp)
        gunMark.Visible = on
        gunMark.Position = UDim2.fromOffset(sp.X, sp.Y)
        gunMark.TextColor3 = st.onT[1] and RGB(255, 210, 80) or RGB(170, 170, 170)
      end
    end
    lockBox.Visible = false
    lockText.Visible = st.wi == 2
    if st.wi == 2 then
      if st.lock and st.lock.root then
        local sp, on = cam:WorldToViewportPoint(st.lock.root.CFrame.Position)
        lockBox.Visible = on
        lockBox.Position = UDim2.fromOffset(sp.X, sp.Y)
        lockStroke.Color = st.sticky and RGB(255, 60, 40) or RGB(255, 190, 80)
        local lk = st.lock
        local key = (lk.kind == "fort") and ("fort." .. tostring(lk.em:GetAttribute("Model") or "bunker"))
          or ("veh." .. ((lk.d and lk.d.id) or (lk.def and lk.def.id) or lk.kind or ""))
        lockText.Text = T("ship.lock", T(key))
      else
        lockText.Text = T("ship.noLock")
      end
    end
    local t = os.clock()
    if t < st.rwrT then
      warn.Visible = (t * 4) % 1 < 0.6
      warn.Text = T("air.missile")
    elseif t < st.warnT then
      warn.Visible = true
      warn.Text = T("ship.shallow")
    else
      warn.Visible = false
    end
    bino.Visible = st.bino
    cross.Visible = true
    if st.bino then binoText.Text = string.format("×%.0f", 70 / ZOOMS[st.zoom]) end
    -- 仪表
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    vName.Text = T("veh." .. d.id) .. ((vs.rest and vs.rest > 0) and ("   " .. T("ship.rest")) or "")
    local f = fwdOf(st.yaw)
    local hdg = math.floor((math.deg(math.atan2(f.X, -f.Z)) + 360) % 360 + 0.5) % 360
    local kn = math.floor(math.abs(st.speed) / 2.8 * 1.944 + 0.5)
    local rd = math.floor(math.abs(st.rudder) * 35 + 0.5)
    local rtxt = (rd == 0) and T("ship.mid") or T((st.rudder > 0) and "ship.right" or "ship.left", rd)
    info1.Text = T("ship.kn", kn) .. "    " .. T("ship.order." .. st.order) .. "    " .. rtxt .. "    " .. T("ship.hdg", hdg)
    local parts = {}
    local rel = 1
    if st.wi == 2 and d.missiles then
      table.insert(parts, "2  " .. T("sw." .. (d.missiles.name or "yj83")) .. "  " .. tostring(vs.msl or 0))
      rel = 1 - math.clamp((st.mslT - t) / 1.3, 0, 1)
    elseif d.guns[1] then
      local g = d.guns[1]
      local w = SD.W[g.w]
      table.insert(parts, "1  " .. T("sw." .. g.w) .. ((#d.guns > 1) and (" ×" .. #d.guns) or ""))
      rel = 1 - math.clamp(((st.next[1] or 0) - t) / math.max(w.rate, 0.01), 0, 1)
    end
    if d.sam then table.insert(parts, T("ship.sam", vs.sam or 0)) end
    if d.ciws and #d.ciws > 0 then table.insert(parts, T("ship.ciws")) end
    info2.Text = table.concat(parts, "    ")
    relBar.Size = UDim2.fromScale(rel, 1)
  end
end

return Sail
