-- Roblox全面大战场（客户端）——飞机、直升机：样子和驾驶
--   样子（G.viewKind.air，View.lua 每帧调）：AirModels 按型号拼零件；位置平滑跟着服务器的 Root，舵面、起落架、弹舱、座舱盖、旋翼按实体属性
--     （Thr、Gear、Pit、Rol、Yaw、Bay、BayS、Rpm、Ty、Gp……）摆；自己开的用本地的；被击毁的往下掉、冒火冒黑烟，落地炸一下
--   驾驶（服务器推来的 S.veh.air）：位置在本地算，每秒 15 次报给服务器（Air.lua 查速度、查撞地）
--     固定翼：鼠标瞄准（像《战争雷霆》的鼠标瞄准：鼠标给想去的方向，自动压坡度、拉杆转过去），W / S 油门（推满再推进加力），
--       A / D 滚转、Q / E 方向舵、↑ / ↓ 直接推拉杆；速度不够失速（机头往下掉）、爬升掉速、俯冲加速、拉杆转弯掉能量；
--       跑道 / 甲板上：油门加速，速度够了把鼠标往上抬就离地；放着起落架、下沉不快、速度不快、姿态平就能落地（落在自己的机场 / 甲板上停 5 秒补弹修理）
--     直升机：W / S 前后、Q / E 平移、A / D 转向（不按时机头慢慢转向镜头方向）、空格 / Ctrl 升降，旋翼先转起来才飞得动
--     武器：1～6 选（航炮、各种挂的弹），左键开火；导弹、制导炸弹要锁定（目标在导引头视场里待够锁定时间），R 换目标；X 热诱弹；G 起落架；F 下飞机（在天上跳伞）
--     平显：速度、高度、油门、准星（机头指向）、鼠标瞄准圈、锁定框、炸弹落点、失速 / 拉起 / 导弹来袭 / 飞出作战区警告
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Fly = {}

function Fly.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local rad, deg = math.rad, math.deg
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local GR = AD.GRAV
  local function T(k, ...) return G.T(k, ...) end
  local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end
  local function ground(x, z) return AD.ground(Map, x, z) end

  local st = nil   -- 正在开 / 坐的飞机
  G.fly = nil
  G.AD = AD

  ---------------------------------------------------------------- 样子

  -- 挂载属性 "pl15,pl15,,kd88" → { "pl15", "pl15", false, "kd88" }
  local function parseLoad(s, d)
    local out = {}
    local i = 0
    for w in string.gmatch((s or "") .. ",", "([^,]*),") do
      i += 1
      out[i] = (w ~= "") and w or false
    end
    for k = 1, #(d.st or {}) do if out[k] == nil then out[k] = false end end
    return out
  end

  local CH = { thr = "Thr", gear = "Gear", flap = "Flap", pit = "Pit", rol = "Rol", yaw = "Yaw", bay = "Bay", bayS = "BayS", rpm = "Rpm", col = "Col", can = "Can",
    hook = "Hook", brk = "Brk", ty = "Ty", gp = "Gp", fold = "Fold" }

  G.viewKind = G.viewKind or {}
  G.viewKind.air = {
    importReady = function(v) return v.M ~= nil and not v.M.imported and v.def ~= nil and AM.importedFor(v.def) ~= nil end,   -- 原模型后来才复制齐：View 重建
    build = function(v, em, team)
      local d = AD.get(em:GetAttribute("Model") or "")
      if not d then return false end
      local M = AM.build(d, team, parseLoad(em:GetAttribute("Load"), d))
      v.M, v.def, v.model, v.anchor = M, d, M.model, M.anchor
      v.c = {}
      v.spin1, v.spin2, v.spinT, v.spinP = math.random() * 6, math.random() * 6, 0, 0
      v.prevT, v.vel = v.root.CFrame, V()
      v.frame = 0
      return true
    end,
    step = function(v, dt, camPos)
      local em, d, M = v.em, v.def, v.M
      local own = st and st.em == em and st
      local target = v.root.CFrame
      -- 别人的飞机：按服务器位置的变化估速度（被击毁时接着往下掉要用）
      if target ~= v.prevT then
        local dp = target.Position - v.prevT.Position
        if dp.Magnitude < 400 then v.vel = v.vel:Lerp(dp / math.max(dt, 1 / 60), 0.5) end
        v.prevT = target
      end
      if em:GetAttribute("Wreck") then   -- 被击毁：带着速度往下掉、翻滚、冒烟，落地炸一下
        if not v.wreck then
          v.wreck = { vel = (own and own.vel) or v.vel, spin = (math.random() - 0.5) * 3, t = 0 }
          if v.M then v.M.dark = true end   -- 被击毁：灯全灭
          for _, it in ipairs(M.items) do
            local p = it.p
            if p:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
              for _, sa in ipairs(p:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
              pcall(function() p.TextureID = "" end)
              if p.Transparency < 1 then p.Color = Color3.fromRGB(40, 38, 36) end
            elseif p:IsA("BasePart") and p.Transparency < 1 then p.Color = p.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.6) end
          end
        end
        local W = v.wreck
        W.t += dt
        if not W.down then
          W.vel += V(0, -GR, 0) * dt
          W.vel *= (1 - 0.1 * dt)
          local p = v.cf.Position + W.vel * dt
          local g = ground(p.X, p.Z)
          if p.Y < g + 1 then
            W.down = true
            p = V(p.X, g + 1, p.Z)
            if G.boom then G.boom(p, 2) end
          end
          local look = (W.vel.Magnitude > 5) and W.vel.Unit or v.cf.LookVector
          v.cf = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, W.t * W.spin)
          W.smokeT = (W.smokeT or 0) - dt
          if W.smokeT <= 0 and G.fxPart then
            W.smokeT = 0.06
            local s = G.fxPart(Enum.PartType.Ball, V(4, 4, 4), CFrame.new(p), RGB(40, 38, 36), Enum.Material.SmoothPlastic, 0.3)
            if G.tween then G.tween(s, 2.4, { Size = V(16, 16, 16), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s, 2.5)
            local f = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(p), RGB(255, 140, 40), Enum.Material.Neon, 0.1)
            if G.tween then G.tween(f, 0.4, { Size = V(6, 6, 6), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(f, 0.45)
          end
        end
      elseif own then
        v.cf = own.cf
      elseif (target.Position - v.cf.Position).Magnitude > 220 then
        v.cf = target
      else
        v.cf = v.cf:Lerp(target, math.min(1, dt * 11))
      end
      -- 通道：自己开的用本地的操纵量；别人的读属性
      local c = v.c
      if own then
        for k in pairs(CH) do c[k] = own.c[k] or 0 end
      else
        for k, a in pairs(CH) do c[k] = em:GetAttribute(a) or 0 end
        if em:GetAttribute("BayS") == nil then c.bayS = c.bay end
      end
      v.canS = approach(v.canS or c.can, c.can, dt * 0.7)   -- 座舱盖开关是 0 / 1：显示时一秒多一点慢慢掀开、合上
      c.can = v.canS
      local onGround = c.gear > 0.9 and (v.cf.Position.Y - ground(v.cf.Position.X, v.cf.Position.Z) - d.gearH) < 1.5
      c.door = (d.sideDoor and onGround) and 1 or 0
      c.ramp = (d.ramp and onGround) and 1 or 0
      -- 旋翼、螺旋桨转（看着慢一点，免得一格一格跳）
      local rpm = c.rpm or 0
      if d.rotor then v.spin1 = (v.spin1 + rpm / 100 * d.rotor.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.rotor2 then v.spin2 = (v.spin2 + rpm / 100 * d.rotor2.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.tail then v.spinT = (v.spinT + rpm / 100 * 18 * dt) % (math.pi * 2) end
      if d.prop then v.spinP = (v.spinP + (c.thr or 0) / 100 * 30 * dt) % (math.pi * 2) end
      c.spin1, c.spin2, c.spinT, c.spinP = v.spin1, v.spin2, v.spinT, v.spinP
      AM.setStores(M, em:GetAttribute("Stores"))
      -- 远的少摆几次（一架几百个零件）
      v.frame += 1
      local dist = (v.cf.Position - camPos).Magnitude
      local every = (own or dist < 1500) and 1 or ((dist < 4000) and 2 or 4)
      if v.frame % every == 0 then AM.pose(M, v.cf, c, os.clock()) end
    end,
  }

  ---------------------------------------------------------------- 平显

  local ui = G.ui
  local gui = Instance.new("ScreenGui")
  gui.Name = "Fly"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")
  local HUD = RGB(120, 255, 150)
  local function hud(text, size, pos, ts, anchor, align)
    local l = ui.label(gui, text, size, pos, ts or 16, HUD, Enum.Font.Code, anchor, align)
    l.TextStrokeTransparency = 0.5
    l.TextStrokeColor3 = RGB(0, 30, 10)
    l.Visible = false
    return l
  end
  local panel = ui.frame(gui, UDim2.fromOffset(460, 86), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.35, Vector2.new(0.5, 1))   -- 操作说明在屏幕最下面一行（UI.lua，st.help）
  panel.Visible = false
  local aName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local aInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 44), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local aWpn = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 62), 14, RGB(255, 220, 120), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  ui.flatPanel(panel, { hp = hpBg, name = aName })   -- 跟新界面一个样子（UI.lua）
  local bore = hud("+", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 34, Vector2.new(0.5, 0.5))   -- 机头指向
  local aimRing = hud("◯", UDim2.fromOffset(36, 36), UDim2.fromScale(0.5, 0.5), 30, Vector2.new(0.5, 0.5))   -- 鼠标想去的方向
  aimRing.TextColor3 = Color3.new(1, 1, 1)
  local lockBox = ui.frame(gui, UDim2.fromOffset(46, 46), UDim2.new(), HUD, 1, Vector2.new(0.5, 0.5))
  lockBox.Visible = false
  local lockStroke = ui.stroke(lockBox, HUD, 2, 0)
  local lockText = hud("", UDim2.fromOffset(160, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  local pipper = hud("◎", UDim2.fromOffset(30, 30), UDim2.new(), 26, Vector2.new(0.5, 0.5))   -- 炸弹落点
  pipper.TextColor3 = RGB(255, 200, 80)
  local spdText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, -230, 0.5, 0), 20, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local altText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, 230, 0.5, 0), 20, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local thrText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, -230, 0.5, 26), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local vsText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, 230, 0.5, 26), 14, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local fuelText = hud("", UDim2.fromOffset(200, 18), UDim2.new(0.5, -230, 0.5, 46), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)   -- 油量、按现在的油门还能飞多久
  local warnText = hud("", UDim2.fromOffset(520, 34), UDim2.new(0.5, 0, 0.5, -130), 26, Vector2.new(0.5, 0.5))
  warnText.TextColor3 = RGB(255, 80, 70)
  local landMark = hud("◇", UDim2.fromOffset(34, 34), UDim2.new(), 30, Vector2.new(0.5, 0.5))   -- 降落点
  landMark.TextColor3 = RGB(120, 200, 255)
  local landText = hud("", UDim2.fromOffset(260, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  landText.TextColor3 = RGB(120, 200, 255)
  local HUDS = { bore, aimRing, spdText, altText, thrText, vsText, warnText, fuelText }

  -- 降落引导：自己这边能落的地方（航母拦阻索区、攻方机场岛、主岛机场——据点 D 在自己手里时），返回 接地点、着陆方向
  local function landSites()
    local out = {}
    local team = me:GetAttribute("Side")
    local function pointMine(id)
      for _, p in ipairs((G.S and G.S.points) or {}) do if p.id == id then return p.owner == team end end
      return false
    end
    local function runway(A)
      for s = -1, 1, 2 do   -- 两头都能落：接地点在跑道头往里 60 格
        local td = V(A.x + s * (A.len / 2 - 60), (A.y or 0), A.z)
        table.insert(out, { p = V(td.X, AD.ground(Map, td.X, td.Z), td.Z), dir = V(-s, 0, 0) })
      end
    end
    if team == "atk" then
      local base = AD.carrierCF(Map)
      if base and st.d.carrier then
        local Wd = AD.WIRES
        local td = (base * CF(Wd.x, 0, (Wd.z0 + Wd.z1) / 2)).Position
        table.insert(out, { p = td, dir = base:VectorToWorldSpace(V(-math.sin(Wd.a), 0, -math.cos(Wd.a))), deck = true })
      end
      runway(Map.AFIELD2)
      if pointMine("D") then runway(Map.AIRFIELD) end
    elseif pointMine("D") then
      runway(Map.AIRFIELD)
    end
    return out
  end

  ---------------------------------------------------------------- 手机：杆、油门 / 升降、开火、换武器、热诱弹、起落架、下飞机

  local touch = nil
  local touchUI = nil
  if UIS.TouchEnabled then
    touch = { up = false, down = false, fire = false }
    local lb = ui.frame(gui, UDim2.fromOffset(90, 170), UDim2.new(0, 20, 1, -320), RGB(0, 0, 0), 1)
    local rb = ui.frame(gui, UDim2.fromOffset(250, 230), UDim2.new(1, -260, 1, -340), RGB(0, 0, 0), 1)
    local function hold(parent, text, size, pos, key)
      local b = ui.button(parent, text, size, pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = true end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = false end end)
      return b
    end
    local function tap(parent, text, pos, f)
      local b = ui.button(parent, text, UDim2.fromOffset(60, 60), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(function() if st then f() end end)
      return b
    end
    hold(lb, "▲", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 0), "up")
    hold(lb, "▼", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 90), "down")
    hold(rb, "●", UDim2.fromOffset(96, 96), UDim2.fromOffset(150, 130), "fire")
    tap(rb, "1/2", UDim2.fromOffset(80, 150), function() G.flyNextWeapon() end)
    tap(rb, "X", UDim2.fromOffset(150, 60), function() G.R.Drive:FireServer({ op = "flare" }) end)
    tap(rb, "G", UDim2.fromOffset(80, 80), function() if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end end)
    tap(rb, "R", UDim2.fromOffset(10, 150), function() G.flyNextTarget() end)
    tap(rb, "F", UDim2.fromOffset(10, 80), function() G.R.Drive:FireServer({ op = "exit" }) end)
    tap(rb, "J", UDim2.fromOffset(80, 10), function() G.R.Drive:FireServer({ op = "jettison" }) end)
    touchUI = { lb, rb }
    for _, f in ipairs(touchUI) do f.Visible = false end
  end

  ---------------------------------------------------------------- 开始 / 结束

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

  local controls = nil
  task.spawn(function()
    local ok, res = pcall(function()
      local pm = require(me:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
      return pm:GetControls()
    end)
    if ok then controls = res end
  end)

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = AD.get(vs.m)
    if not d then return end
    local cf = em.Root.CFrame
    local look = cf.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local onGround = vs.ground == true
    st = { id = vs.id, em = em, d = d, pilot = vs.pilot == true, cf = cf, vel = V(), spd = 0, sink = 0, pr = 0, rr = 0, yr = 0,
      thr = onGround and 0 or 85, ground = onGround, gearWant = onGround and 1 or 0, gear = onGround and 1 or 0, rpm = (d.kind == "heli" and not onGround) and 100 or 0,
      yaw = yaw, hv = V(), vy = 0, tiltP = 0, tiltR = 0, camYaw = yaw, camPitch = -0.15, aimYaw = yaw, aimPitch = 0, c = {},
      load = vs.load or {}, wl = AD.groups(d, vs.load or {}), wi = 1, firing = false, trig = false, sendT = 0, lock = nil, lockT = 0, nextFire = 0,
      ty = 0, gp = 0, lastHv = V(), crashed = false, bay = 0, bayS = 0 }
    if not onGround then   -- 空中出发：带着速度
      if d.kind == "jet" then st.spd = d.vMil * 0.8 else st.hv = look * d.vMax * 0.6 end
      st.vel = look * ((d.kind == "jet") and st.spd or d.vMax * 0.6)
    end
    -- 遥控无人机（服务器 vs.uav）：人在地上端着战术平板，画面是平板（Tablet.lua）；默认前视光电，右键 / V 换外部视角，Z 变焦
    st.uav = vs.uav == true and d.drone == true
    st.dcam, st.zoom, st.zoomS = st.uav and "nose" or nil, 1, 1
    G.fly, G.drive = st, st   -- G.drive：步兵的操作（Play）先停下
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible = true
    -- 平板模式：面板挪进平板屏幕里（底边外壳上不放东西）
    local rect = G.tabletRect
    panel.Position = (st.uav and rect) and UDim2.new(0.5, 0, rect[4], -12) or UDim2.new(0.5, 0, 1, -24)
    if st.uav and G.tabletOpen then G.tabletOpen(st) end
    for _, l in ipairs(HUDS) do l.Visible = st.pilot end
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = st.pilot end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    if st and st.trig then G.R.Drive:FireServer({ op = "trig", on = false }) end
    local old = st
    st = nil
    G.fly = nil
    if G.drive == old then G.drive = nil end
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible = false
    for _, l in ipairs(HUDS) do l.Visible = false end
    lockBox.Visible, lockText.Visible, pipper.Visible = false, false, false
    landMark.Visible, landText.Visible = false, false
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = false end end
    panel.Position = UDim2.new(0.5, 0, 1, -24)
    if old and old.uav and G.tabletClose then G.tabletClose() end
  end

  ---------------------------------------------------------------- 武器

  local function curW()
    local wid = st.wl[st.wi]
    return wid, wid and AD.W[wid]
  end
  -- 这种弹还剩几枚（S.veh.stores 是服务器的数，开火时本地先扣）
  local function left(wid)
    local w = AD.W[wid]
    if not w then return 0 end
    if w.kind == "gun" then return st.gunAmmo or 0 end
    local n = 0
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid then n += (st.stores and st.stores[i]) or 0 end
    end
    return n
  end
  function G.flyNextWeapon()
    if not st or #st.wl == 0 then return end
    st.wi = st.wi % #st.wl + 1
    st.lock, st.lockT = nil, 0
  end
  -- 弹舱：选中的弹在哪个舱里，那个舱门就开着
  local function bayOf(wid)
    local main, side = false, false
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid and s.bay then
        if s.bay == "main" then main = true else side = true end
      end
    end
    return main, side
  end

  -- 能锁的目标：敌方实体（空空弹打飞机，空地弹 / 炸弹打地面、海上的）
  local GROUND_KINDS = { veh = true, bot = true, fort = true, lcm = true, lcac = true, ship = true }
  local function candidates(w)
    local out = {}
    local f = workspace:FindFirstChild("Ents")
    if not f or not st then return out end
    local myTeam = me:GetAttribute("Side")
    local p0 = st.cf.Position
    for _, em in ipairs(f:GetChildren()) do
      local kind = em:GetAttribute("Kind")
      local root = em:FindFirstChild("Root")
      if root and em ~= st.em and em:GetAttribute("Team") ~= myTeam and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        local ok = (w.kind == "aam") and kind == "air" or ((w.kind == "agm" or w.kind == "bomb") and GROUND_KINDS[kind])
        if ok then
          local to = root.CFrame.Position - p0
          local dist = to.Magnitude
          if dist < (w.range or 3200) and dist > 30 then table.insert(out, { em = em, id = em:GetAttribute("EntId"), dir = to.Unit, dist = dist, pos = root.CFrame.Position }) end
        end
      end
    end
    return out
  end
  -- 导引头视场：导弹看机头前方 cone 度；炸弹看飞机下前方（俯冲投弹也行）
  local function inCone(w, c)
    local fwd = st.cf.LookVector
    if w.kind == "bomb" then
      local down = (fwd * 0.6 + V(0, -1, 0)).Unit
      return down:Dot(c.dir) > math.cos(rad(w.cone or 60))
    end
    local cone = w.cone or 30
    if st.d.kind == "heli" and w.kind == "agm" then cone += 20 end
    return fwd:Dot(c.dir) > math.cos(rad(cone))
  end
  local function aimDirNow()
    if st.d.kind == "jet" and not G.mobile then
      return (CFrame.Angles(0, st.aimYaw, 0) * CFrame.Angles(st.aimPitch, 0, 0)).LookVector
    end
    return cam.CFrame.LookVector
  end
  local function pickTarget(w, skip)
    local best, bs = nil, math.huge
    local want = aimDirNow()
    for _, c in ipairs(candidates(w)) do
      if inCone(w, c) and c.id ~= skip then
        local s = 1 - want:Dot(c.dir) + c.dist / 20000
        if s < bs then best, bs = c, s end
      end
    end
    return best
  end
  function G.flyNextTarget()
    if not st then return end
    local _, w = curW()
    if not w or w.kind == "gun" or w.kind == "rkt" then return end
    local c = pickTarget(w, st.lock and st.lock.id)
    st.lock, st.lockT = c, 0
  end

  local function setTrig(on)
    if st.trig == on then return end
    st.trig = on
    G.R.Drive:FireServer({ op = "trig", on = on, aim = st.aimPt })
  end

  local function fireStore(wid, w)
    local t = os.clock()
    if t < st.nextFire or left(wid) <= 0 then return end
    if G.S and G.S.phase ~= "battle" then G.toast(T("air.notYet"), "info") return end
    local locked = st.lock and st.lockT >= (w.lockTime or 1)
    if w.kind == "aam" and not locked then G.toast(T("air.needLock"), "info") return end
    st.nextFire = t + ((w.kind == "rkt") and (w.rate or 0.12) or 0.4)
    G.R.Drive:FireServer({ op = "fire", w = wid, tgt = locked and st.lock.id or nil, aim = st.aimPt })
    for i in ipairs(st.d.st or {}) do   -- 本地先扣一枚（服务器的数随后推过来）
      if st.load[i] == wid and (st.stores[i] or 0) > 0 then
        st.stores[i] -= 1
        break
      end
    end
    if G.playSound then G.playSound("rocket", st.cf.Position) end
  end

  ---------------------------------------------------------------- 物理：固定翼

  local function key(k) return UIS:IsKeyDown(k) end
  local function crash()
    if st.crashed then return end
    st.crashed = true
    G.R.Drive:FireServer({ op = "crash", hit = true })
    if G.shake then G.shake(1) end
  end

  local function jetPhysics(dt)
    local d = st.d
    local up = key(Enum.KeyCode.W) or (touch and touch.up)
    local dn = key(Enum.KeyCode.S) or (touch and touch.down)
    st.thr = clamp(st.thr + ((up and 1 or 0) - (dn and 1 or 0)) * 55 * dt, 0, d.ab and 130 or 100)
    if st.out then st.thr = 0 end   -- 油烧干了：发动机熄火，只能滑翔
    local rollIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn = (key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0)
    local pitchIn = (key(Enum.KeyCode.Down) and 1 or 0) - (key(Enum.KeyCode.Up) and 1 or 0)
    if G.mobile and controls then   -- 手机：摇杆直接当驾驶杆（往前推是低头）
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.X) > 0.1 then rollIn = mv.X end
        if math.abs(mv.Z) > 0.1 then pitchIn = mv.Z end
      end
    end
    local cf = st.cf
    local fwd, upV, right = cf.LookVector, cf.UpVector, cf.RightVector
    -- 速度：油门给目标速度（加力到 vAB），往目标加减速；爬升掉速、俯冲加速、拉杆转弯掉能量；地上没油门时滚着慢下来
    -- 重量感（用户：飞机驾驶没有重量感）：W 越大越「沉」——F-22、歼-20 约 1，A-10 约 2，轰-6K、B-2、MQ-9 是 3
    local W = math.clamp(220 / math.max(d.roll or 200, 1), 1, 3)
    -- 发动机有迟滞：推力跟着油门慢慢起来（加力点着要一下）
    st.thrE = approach(st.thrE or st.thr, st.thr, (st.thr > (st.thrE or 0) and 38 or 55) / W * dt)
    local thr = st.thrE
    local tgt = (thr <= 100) and d.vMil * thr / 100 or (d.vMil + (d.vMax - d.vMil) * (thr - 100) / 30)
    local acc = (thr > 100) and (d.accel + (d.abAccel or 0)) or d.accel
    -- 副油箱的阻力：最大速度、加速度都少几成；油多就重：加速慢（满内油 + 两个副油箱比一半内油重三成多）
    tgt *= 1 - (st.drag or 0)
    acc *= (1 - (st.drag or 0)) / (st.heavy or 1)
    -- 地上滑跑：推力要先克服整架飞机的重量和轮子的阻力，加速度只有天上的四分之一（战斗机滑跑两三百米、轰炸机五百米上下，
    --   一推油门不再四五十米就飞起来；弹射器单独算）
    if st.ground and not st.cat then acc *= 0.25 end
    if st.trap then   -- 挂着拦阻索：发动机推力不算，地上那段按拦阻索减速
    elseif tgt > st.spd then st.spd += math.min(tgt - st.spd, acc * dt) else st.spd -= math.min(st.spd - tgt, (st.ground and (key(Enum.KeyCode.B) and 60 or 22) or acc * 0.45) * dt) end
    if not st.ground then
      local vd = st.vdir or fwd
      st.spd -= GR * vd.Y * 0.9 * dt   -- 沿航迹爬升掉速、俯冲加速
      st.spd -= math.abs(st.pr) * st.spd * 0.16 * dt
      st.spd -= (1 - math.clamp(vd:Dot(fwd), -1, 1)) * st.spd * 2.6 * dt   -- 机头和航迹差得越多（大迎角、侧滑）掉速越快
    end
    st.spd = clamp(st.spd, 0, d.vMax * 1.3)
    local q = clamp((st.spd - d.stall * 0.4) / d.stall, 0.12, 1)   -- 舵效：慢了舵不灵
    -- 想怎么转：鼠标瞄准（自动驾驶）+ 键盘直接操纵
    local pc, rc, yc
    if G.mobile then
      pc, rc, yc = -pitchIn, rollIn, yawIn
      pc = pc * rad(d.pitch)
      rc = rc * rad(d.roll)
      yc = yc * rad(d.yaw)
    else
      local aim = aimDirNow()
      local l = cf:VectorToObjectSpace(aim)
      local fz = -l.Z
      local off = math.acos(clamp(fz, -1, 1))
      local w = Map.smooth(rad(2), rad(10), off)
      local toTarget = math.atan2(l.X, l.Y)   -- 让目标落到机头正上方（升力方向）要滚多少
      if fz < -0.2 and math.abs(l.X) < 0.15 then toTarget = 0 end   -- 目标在正后方偏一点点：先拉起来（筋斗），别来回滚
      local level = math.asin(clamp(right.Y, -1, 1))   -- 目标正前方时把机翼摆平
      rc = (w * clamp(toTarget * 3.2, -1, 1) + (1 - w) * clamp(level * 2.5, -1, 1)) * rad(d.roll)
      local pe = math.atan2(l.Y, math.max(fz, 0.05))
      if fz < 0 then pe = (l.Y >= 0) and math.pi / 2 or -math.pi / 2 end
      pc = clamp(pe * 3, -1, 1) * rad(d.pitch)
      if math.abs(toTarget) > rad(100) and off > rad(25) then pc = math.min(pc, rad(d.pitch) * 0.15) end   -- 还没滚过去别乱拉
      yc = clamp(math.atan2(l.X, math.max(fz, 0.05)) * 2, -1, 1) * rad(d.yaw)
      if rollIn ~= 0 then rc = rollIn * rad(d.roll) end
      if pitchIn ~= 0 then pc = -pitchIn * rad(d.pitch) end
      if yawIn ~= 0 then yc = yawIn * rad(d.yaw) end
    end
    -- 过载限制：转弯角速度不超过 g × 重力 / 速度
    local gLim = d.g * GR / math.max(st.spd, 30) / math.sqrt(st.heavy or 1)   -- 重了转不快
    pc = clamp(pc, -math.min(rad(d.pitch), gLim) * 0.6, math.min(rad(d.pitch), gLim)) * q
    rc, yc = rc * q, yc * q
    st.pr = approach(st.pr, pc, 2.6 / W ^ 0.8 * dt)   -- 角速度要一会儿才起来、停下（转动惯量）：重的更慢
    st.rr = approach(st.rr, rc, rad(d.roll) * 2.8 / W ^ 0.5 * dt)
    st.yr = approach(st.yr, yc, 1.2 / W ^ 0.6 * dt)
    st.c.pit, st.c.rol, st.c.yaw = clamp(st.pr / math.max(rad(d.pitch), 1e-3), -1, 1), clamp(st.rr / math.max(rad(d.roll), 1e-3), -1, 1), clamp(st.yr / math.max(rad(d.yaw), 1e-3), -1, 1)
    local pos = cf.Position
    if st.ground and st.cat then
      -- 航母弹射器：卡上以后原地不动，油门推满按空格（手机：推满等一秒半）沿轨道加速，冲到舰艏就离舰
      local start, dir, len = AD.cat(Map, st.cat.i)
      if st.cat.state == "hooked" then
        st.spd = 0
        st.yaw = math.atan2(-dir.X, -dir.Z)
        pos = start + V(0, d.gearH, 0)
        cf = CFrame.lookAt(pos, pos + dir)
        st.cat.full = (st.thr >= 90) and ((st.cat.full or 0) + dt) or 0
        if st.thr >= 90 and (key(Enum.KeyCode.Space) or st.cat.full > 1.2) then   -- 推满油门一会儿就弹（空格立刻弹）
          st.cat.state, st.cat.s, st.cat.v = "launch", 0, 0
          if G.shake then G.shake(0.4) end
          if G.playSound then G.playSound("boom", pos, 1.6) end
        end
      else
        local vEnd = math.max(d.vRot * 1.2, d.stall * 1.35)
        st.cat.v += vEnd * vEnd / (2 * len) * dt
        st.cat.s += st.cat.v * dt
        st.spd = st.cat.v
        if st.cat.s >= len then   -- 离舰
          st.ground, st.cat = false, nil
          st.pr = rad(5)
          pos = start + dir * len + V(0, d.gearH + 1, 0)
          cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(rad(5), 0, 0)
        else
          pos = start + dir * st.cat.s + V(0, d.gearH, 0)
          cf = CFrame.lookAt(pos, pos + dir)
          st.steamT = (st.steamT or 0) - dt
          if st.steamT <= 0 and G.fxPart then   -- 弹射轨道上一路冒白汽
            st.steamT = 0.05
            local s2 = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(pos - V(0, d.gearH - 0.5, 0)), RGB(236, 236, 232), Enum.Material.SmoothPlastic, 0.35)
            if G.tween then G.tween(s2, 1.4, { Size = V(9, 9, 9), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s2, 1.5)
          end
        end
      end
      st.vel = cf.LookVector * st.spd
      st.vdir, st.accV = cf.LookVector, nil
      st.sink = 0
    elseif st.ground then
      -- 地上：机头只能左右转（前轮转向），速度够了抬头就离地
      local aim = aimDirNow()
      local l = cf:VectorToObjectSpace(aim)
      local steer = clamp(math.atan2(l.X, math.max(-l.Z, 0.05)) * 1.5, -1, 1)
      if yawIn ~= 0 or rollIn ~= 0 then steer = yawIn ~= 0 and yawIn or rollIn end
      if G.mobile then steer = rollIn end
      st.yaw -= steer * rad(30) * clamp(st.spd / 25, 0.15, 1) * dt
      -- 航母甲板：没上弹射器滑不快（起飞要靠弹射器）；挂上拦阻索的一路被拉停
      local deck = AD.onDeck(Map, pos.X, pos.Z)
      if st.trap then
        st.spd = math.max(0, st.spd - st.trapA * dt)
        if st.spd < 1 then st.trap = nil end
      elseif deck == "carrier" then
        st.spd = math.min(st.spd, AD.TAXI)
      end
      -- 滑到弹射器起点、机头对正、速度慢：卡上
      if deck == "carrier" and d.carrier and not st.trap and st.spd < 15 then
        local look0 = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
        for i = 1, #AD.CATS do
          local start, dir = AD.cat(Map, i)
          local rel = V(pos.X - start.X, 0, pos.Z - start.Z)
          local along = rel:Dot(dir)
          local lat = (rel - dir * along).Magnitude
          if math.abs(along) < 12 and lat < 7 and look0:Dot(dir) > math.cos(rad(25)) then
            st.cat = { i = i, state = "hooked" }
            if G.playSound then G.playSound("capture", pos) end   -- 卡上：咔一声，不出字
            break
          end
        end
      end
      local look = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      pos += look * st.spd * dt
      local g = ground(pos.X, pos.Z)
      local wantUp = G.mobile and (pitchIn < -0.3) or (aim.Y > math.sin(rad(3))) or pitchIn < 0
      if st.spd >= d.vRot and wantUp then   -- 离地
        st.ground = false
        st.pr = rad(6)
        cf = CFrame.lookAt(pos + V(0, 0.5, 0), pos + V(0, 0.5, 0) + look) * CFrame.Angles(rad(4), 0, 0)
      elseif pos.Y - d.gearH > g + 2.5 then   -- 冲出甲板 / 跑道尽头：掉下去
        st.ground = false
        cf = CFrame.lookAt(pos, pos + look)
      else
        pos = V(pos.X, g + d.gearH, pos.Z)
        cf = CFrame.lookAt(pos, pos + look)
      end
      st.vel = look * st.spd
      st.vdir, st.accV = (st.ground and look) or cf.LookVector, nil
      st.sink = 0
    else
      cf = cf * CFrame.Angles(st.pr * dt, -st.yr * dt, -st.rr * dt)
      -- 失速：升力不够，往下沉、机头往速度方向掉
      local lift = clamp((st.spd / d.stall) ^ 2, 0, 1)
      st.sink = approach(st.sink, GR * (1 - lift) * 1.8, GR * dt)
      if lift < 0.85 then cf = cf * CFrame.Angles(-(1 - lift) * 0.9 * dt, 0, 0) end
      -- 航迹不是机头指哪就飞哪：升力把速度方向往机头那边拉，快、升力足拉得快，重的飞机拉得慢——拉杆时机头先抬、飞机「吃」一下才转过去
      local vd = st.vdir or cf.LookVector
      local pull = math.clamp(lift * st.spd / math.max(d.stall, 1) * 1.7, 0.35, 3.4) / W ^ 0.7
      vd = (vd + (cf.LookVector - vd) * math.min(1, pull * dt))
      st.vdir = (vd.Magnitude > 1e-3) and vd.Unit or cf.LookVector
      local v0 = st.vel
      st.vel = st.vdir * st.spd + V(0, -st.sink, 0)
      if v0 then   -- 加速度（镜头用：过载把镜头甩开）
        local a = (st.vel - v0) / math.max(dt, 1e-3)
        st.accV = (st.accV or a):Lerp(a, math.min(1, dt * 6))
      end
      pos += st.vel * dt
      cf = cf - cf.Position + pos
      -- 撞地 / 落地
      local g = ground(pos.X, pos.Z)
      if pos.Y - d.gearH <= g + 0.3 then
        local fw = cf.LookVector
        local bank = math.abs(deg(math.asin(clamp(cf.RightVector.Y, -1, 1))))
        local pitch = deg(math.asin(clamp(fw.Y, -1, 1)))
        local landable = g > 0.4 or AD.onDeck(Map, pos.X, pos.Z) ~= nil
        if st.gear > 0.9 and landable and st.vel.Y > -24 and st.spd < d.landMax and bank < 20 and pitch > -8 and pitch < 22 then
          st.ground = true
          st.yaw = math.atan2(-fw.X, -fw.Z)
          pos = V(pos.X, g + d.gearH, pos.Z)
          cf = CFrame.lookAt(pos, pos + V(fw.X, 0, fw.Z))
          st.sink, st.pr, st.rr, st.yr = 0, 0, 0, 0
          -- 航母：尾钩放着、落在拦阻索区，被拦阻索拉停（85 格内停住）
          if AD.onDeck(Map, pos.X, pos.Z) == "carrier" and (st.c.hook or 0) > 0.5 and AD.inWires(Map, pos.X, pos.Z) then
            st.trap, st.trapA = true, math.max(20, st.spd * st.spd / (2 * 85))
            if G.shake then G.shake(0.5) end
          end
        else
          crash()
        end
      end
    end
    st.cf = cf
    -- 起落架：离地后自动不收，按 G 收放；地上一直放着
    if st.ground then st.gearWant = 1 end
    st.gear = approach(st.gear, st.gearWant, dt / 2.5)
    st.c.gear = st.gear
    st.c.thr = st.thr
    st.c.flap = (st.gear > 0.5 and st.spd < d.stall * 1.6) and 1 or 0
    st.c.can = (st.ground and st.thr < 5 and st.spd < 3) and 1 or 0
    st.c.fold = (d.fold and st.ground and st.thr < 5 and st.spd < 3 and AD.onDeck(Map, pos.X, pos.Z)) and 1 or 0
    st.c.hook = (d.gear and d.gear.hook and st.gear > 0.9 and not st.ground) and 1 or 0
    st.c.brk = (key(Enum.KeyCode.B)) and 1 or 0
    st.c.rpm = st.thr
  end

  ---------------------------------------------------------------- 物理：直升机

  local function heliPhysics(dt)
    local d = st.d
    if st.out then st.rpm = approach(st.rpm, 72, 9 * dt) else st.rpm = approach(st.rpm, 100, 22 * dt) end   -- 旋翼转起来要四五秒；熄火后靠气流自转，转速掉下来
    local lift = st.rpm >= 92
    local auto = st.out and not st.ground   -- 熄火自转下滑：还能往前飘一点，快落地时拉总距（空格）下沉慢一些
    local fwdIn = (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0)
    local sideIn = (key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0)
    local yawIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local upIn = ((key(Enum.KeyCode.Space) or (touch and touch.up)) and 1 or 0) - ((key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.C) or (touch and touch.down)) and 1 or 0)
    if G.mobile and controls then
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.Z) > 0.1 then fwdIn = -mv.Z end
        if math.abs(mv.X) > 0.1 then yawIn = mv.X end
      end
    end
    -- 转向：按 A / D；没按的时候往前飞，机头慢慢转向镜头方向
    if yawIn ~= 0 then
      st.yaw -= yawIn * rad(d.yaw) * dt
    elseif not G.mobile and (fwdIn ~= 0 or st.hv.Magnitude > 10) and not st.ground then
      st.yaw += clamp(angDiff(st.yaw, st.camYaw), -rad(d.yaw) * 0.8 * dt, rad(d.yaw) * 0.8 * dt)
    end
    local f = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
    local r = V(math.cos(st.yaw), 0, -math.sin(st.yaw))
    local want = (f * fwdIn * d.vMax + r * sideIn * d.vMax * 0.45) * (1 - (st.drag or 0))
    if auto then want *= 0.5
    elseif not lift or st.ground then want = V() end
    local dv = want - st.hv
    local amax = d.accel * dt / (st.heavy or 1)
    if dv.Magnitude > amax then dv = dv.Unit * amax end
    st.lastHv = st.hv
    st.hv += dv
    local vyWant = auto and (-14 + math.max(upIn, 0) * 6) or (lift and upIn * d.climb / (st.heavy or 1) or -18)
    st.vy = approach(st.vy, vyWant, d.climb * 1.8 * dt)
    local pos = st.cf.Position + (st.hv + V(0, st.vy, 0)) * dt
    local g = ground(pos.X, pos.Z)
    if pos.Y - d.gearH <= g then
      local overSea = g <= 0.4 and not AD.onDeck(Map, pos.X, pos.Z)
      if (st.vy < -30 or overSea) and not st.ground and not st.crashed then crash() end
      pos = V(pos.X, g + d.gearH, pos.Z)
      st.vy = math.max(st.vy, 0)
      st.ground = upIn <= 0
      if st.ground then st.hv *= math.max(0, 1 - 5 * dt) end
    else
      st.ground = false
    end
    -- 姿态：往前加速低头、侧移压坡度
    local acc = (st.hv - st.lastHv) / math.max(dt, 1e-3)
    local accF, accR = acc:Dot(f), acc:Dot(r)
    local tP = clamp(-accF * 0.01 - st.hv:Dot(f) / d.vMax * 0.22, -rad(d.tilt), rad(d.tilt))
    local tR = clamp(accR * 0.01 + st.hv:Dot(r) / d.vMax * 0.2 + yawIn * 0.06, -rad(d.tilt), rad(d.tilt))
    if st.ground then tP, tR = 0, 0 end
    st.tiltP = approach(st.tiltP, tP, dt * 0.9)
    st.tiltR = approach(st.tiltR, tR, dt * 0.9)
    st.cf = CF(pos) * CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.tiltP, 0, -st.tiltR)
    st.vel = st.hv + V(0, st.vy, 0)
    st.c.pit, st.c.rol, st.c.yaw, st.c.col = fwdIn, sideIn, yawIn, upIn
    st.c.rpm, st.c.thr, st.c.gear = st.rpm, st.rpm, 1
  end

  ---------------------------------------------------------------- 输入

  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.F then G.R.Drive:FireServer({ op = "exit" }) return end
    if not st.pilot then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      st.firing = true
    elseif k == Enum.KeyCode.X then
      G.R.Drive:FireServer({ op = "flare" })
    elseif k == Enum.KeyCode.J then   -- 抛副油箱（进空战前）
      G.R.Drive:FireServer({ op = "jettison" })
    elseif k == Enum.KeyCode.G then
      if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end
    elseif k == Enum.KeyCode.R then
      G.flyNextTarget()
    elseif st.uav and (k == Enum.KeyCode.V or io.UserInputType == Enum.UserInputType.MouseButton2) then   -- 平板：前视光电 ↔ 外部视角
      st.dcam = (st.dcam == "nose") and "chase" or "nose"
    elseif st.uav and k == Enum.KeyCode.Z then   -- 变焦一档一档跳：1× → 3× → 8× → 1×
      st.zoom = (st.zoom < 2.9) and 3 or ((st.zoom < 7.9) and 8 or 1)
    else
      local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6 })[k]
      if n and st.wl[n] then
        st.wi = n
        st.lock, st.lockT = nil, 0
      end
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then st.firing = false end
  end)
  UIS.InputChanged:Connect(function(io, gp)   -- 平板前视光电：滚轮细调倍率（1× ~ 12×）
    if gp or not st or not st.uav or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    st.zoom = clamp(st.zoom * (1 + 0.18 * io.Position.Z), 1, 12)
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and typeof(m.cf) == "CFrame" then   -- 服务器不认：拉回去
      st.cf = m.cf
      if typeof(m.v) == "Vector3" then
        st.vel = m.v
        st.spd = m.v.Magnitude
        st.hv = V(m.v.X, 0, m.v.Z)
      end
      -- 航迹方向跟着拉回去（不然留着原来的航迹，机头和航迹差得远，一下子掉光速度失速）
      st.vdir = (typeof(m.v) == "Vector3" and m.v.Magnitude > 1) and m.v.Unit or m.cf.LookVector
      st.accV = nil
    elseif m.op == "rwr" then   -- 有导弹朝我来了
      st.rwrT = os.clock() + 4
      if G.playSound then G.playSound("capture", nil, 2.2) end
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  local function project(p)
    local sp, on = cam:WorldToViewportPoint(p)
    return UDim2.fromOffset(sp.X, sp.Y), on
  end

  function G.stepFly(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and not vs.air then vs = nil end
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    st.pilot = vs.pilot == true
    st.stores = st.storesLocal or {}
    -- 服务器推来的弹药数（半秒一次）：比本地扣的数少才换（本地先扣过的不回弹）
    if vs.stores then
      st.storesLocal = st.storesLocal or table.clone(vs.stores)
      for i, n in ipairs(vs.stores) do
        if st.storesSeen == nil or st.storesSeen[i] ~= n then st.storesLocal[i] = n end
      end
      st.storesSeen = table.clone(vs.stores)
      st.stores = st.storesLocal
    end
    st.gunAmmo, st.flares, st.load = vs.gun or 0, vs.flares or 0, vs.load or st.load
    -- 油量（服务器算，属性 Fuel / FuelX）：烧干了熄火；挂着的副油箱算阻力，油多算重量
    local f0, x0 = st.em:GetAttribute("Fuel"), st.em:GetAttribute("FuelX")
    st.fuel = (type(f0) == "number") and f0 or 1
    st.fuelX = (type(x0) == "number") and x0 or 0
    st.out = st.fuel <= 0 and st.fuelX <= 0
    st.heavy = AD.heavy(d, st.fuel, st.fuelX)
    st.drag, st.tanks = 0, 0
    for i, s2 in ipairs(d.st or {}) do
      local w2 = st.load and st.load[i] and AD.W[st.load[i]]
      if w2 and w2.kind == "tank" and (st.stores[i] or 0) > 0 then
        st.drag += w2.drag * st.stores[i]
        st.tanks += st.stores[i]
      end
    end
    -- 镜头转动
    if not G.mobile then UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end
    local md = UIS:GetMouseDelta()
    -- 平板前视光电变焦：倍率越大鼠标越慢（准星在画面上走得一样快）
    st.zoomS = st.zoomS + ((st.uav and st.dcam == "nose" and st.zoom or 1) - st.zoomS) * math.min(1, dt * 8)
    if st.uav then md = md / st.zoomS end
    if d.kind == "jet" and not G.mobile then
      st.aimYaw -= md.X * SENS
      st.aimPitch = clamp(st.aimPitch - md.Y * SENS, -1.45, 1.45)
    end
    st.camYaw -= md.X * SENS
    st.camPitch = clamp(st.camPitch - md.Y * SENS, -1.2, 0.9)
    -- 飞
    if st.pilot and not st.crashed then
      if d.kind == "jet" then jetPhysics(dt) else heliPhysics(dt) end
      -- 撞楼、撞舰岛：沿着速度方向打一条射线
      local stepV = st.vel * dt * 1.6
      if stepV.Magnitude > 0.5 and not st.ground then
        local res = workspace:Raycast(st.cf.Position, stepV + stepV.Unit * d.L * 0.4, mapParams)
        if res and res.Normal.Y < 0.6 then crash() end
      end
      -- 飞出作战区（±Map.PLAY，约 5 公里）：自动掉头（喷气机掉头半径七八百格）；再往外硬拦住（服务器在 Map.PLAY + 1200 以外不认）
      local p = st.cf.Position
      local lim = Map.PLAY
      st.oob = math.abs(p.X) > lim or math.abs(p.Z) > lim
      if st.oob and d.kind == "jet" then
        local back = V(-p.X, 0, -p.Z).Unit
        st.aimYaw = math.atan2(-back.X, -back.Z)
        st.aimPitch = 0.05
      end
      local hard = Map.PLAY + 1000
      if math.abs(p.X) > hard or math.abs(p.Z) > hard then
        st.cf = st.cf - p + V(math.clamp(p.X, -hard, hard), p.Y, math.clamp(p.Z, -hard, hard))
        if d.kind == "heli" then st.hv = V() end
      end
      if p.Y > 2600 then st.cf = st.cf - V(0, p.Y - 2600, 0) end
    else
      st.cf = st.em.Root.CFrame   -- 坐在后面：跟着服务器
    end
    -- 镜头
    local pos = st.cf.Position
    if st.uav and st.dcam == "nose" then
      -- 无人机前视光电（机头下面的光电球）：顺着鼠标想去的方向看（手机上就是机头方向），不画镜头抖动
      local eye = (st.cf * CF(0, -d.H * 0.22, -d.L * 0.5 - 0.8)).Position
      local look = G.mobile and st.cf.LookVector or aimDirNow()
      cam.CFrame = CFrame.lookAt(eye, eye + look * 100)
    elseif d.kind == "jet" and not G.mobile and st.pilot then
      local aim = aimDirNow()
      local back = d.L * 1.3 + 26
      -- 镜头带弹簧慢半拍跟上，加速度把镜头往反方向甩开一点（转弯时飞机在画面里往外偏、拉起时往下沉）；大过载、加力时轻轻抖
      local want = -aim * back + V(0, d.H * 0.9 + 7, 0)
      st.camOff = st.camOff and st.camOff:Lerp(want, 1 - math.exp(-dt * 7)) or want
      local acc = st.accV or V()
      local push = -acc * 0.014
      if push.Magnitude > 7 then push = push.Unit * 7 end
      st.camPush = (st.camPush or push):Lerp(push, 1 - math.exp(-dt * 4))
      local camPos = pos + st.camOff + st.camPush
      local gl = acc.Magnitude / GR   -- 大概几个 g
      local amp = math.clamp((gl - 3) * 0.0016, 0, 0.012) + ((st.thrE or 0) > 100 and 0.0012 or 0)
      local t = os.clock()
      local shake = CFrame.Angles(math.noise(t * 18, 1.3) * amp, math.noise(t * 18, 7.1) * amp, 0)
      cam.CFrame = CFrame.lookAt(camPos, pos + aim * 300) * shake
    elseif d.kind == "jet" then
      local camPos = (st.cf * CF(0, d.H * 0.9 + 7, d.L * 1.3 + 26)).Position
      cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, (st.cf * CF(0, 4, -300)).Position), math.min(1, dt * 8))
    else
      local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
      local camPos = pos + V(0, d.H * 0.5, 0) + dirCam:VectorToWorldSpace(V(0, 0, d.L * 1.1 + 18))
      cam.CFrame = CFrame.lookAt(camPos, camPos + dirCam.LookVector)
    end
    local fovT = (d.kind == "jet") and math.clamp(70 + st.spd / d.vMax * 10, 70, 82) or 70
    if st.uav and st.dcam == "nose" then fovT = 70 / st.zoomS end
    cam.FieldOfView = cam.FieldOfView + (fovT - cam.FieldOfView) * math.min(1, dt * ((st.uav and 10) or 4))
    -- 瞄准点：镜头中间（固定翼：鼠标瞄准方向）打出去碰到的地方
    local ex = { G.viewFolder }
    if me.Character then table.insert(ex, me.Character) end
    table.insert(ex, st.em)
    aimParams.FilterDescendantsInstances = ex
    local adir = aimDirNow()
    local o = (d.kind == "jet" and st.pilot and not G.mobile) and pos or cam.CFrame.Position
    local res = workspace:Raycast(o + adir * (d.L * 0.6), adir * 4000, aimParams)
    st.aimPt = res and res.Position or (o + adir * 4000)
    -- 机头炮塔：跟着瞄准点转
    local wid, w = curW()
    if d.gunPos and w and w.turret then
      local l = st.cf:PointToObjectSpace(st.aimPt) - d.gunPos
      st.ty = clamp(deg(math.atan2(l.X, -l.Z)), -110, 110)
      st.gp = clamp(deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z))), -60, 11)
    end
    st.c.ty, st.c.gp = st.ty, st.gp
    -- 弹舱门
    local bm, bs = false, false
    if wid then bm, bs = bayOf(wid) end
    st.bay = approach(st.bay, bm and 1 or 0, dt * 2.5)
    st.bayS = approach(st.bayS, bs and 1 or 0, dt * 2.5)
    st.c.bay, st.c.bayS = st.bay, st.bayS
    -- 开火：航炮按住连发（扳机发给服务器），挂的弹一下一发（火箭按住连发）
    if st.pilot and w then
      if w.kind == "gun" then
        setTrig(st.firing or (touch and touch.fire) or false)
      else
        if st.trig then setTrig(false) end
        if st.firing or (touch and touch.fire) then
          if w.kind == "rkt" or not st.fireLatch then fireStore(wid, w) end
          st.fireLatch = true
        else
          st.fireLatch = false
        end
      end
    end
    -- 锁定：选中的弹要锁的话，目标在视场里待够锁定时间
    if st.pilot and w and (w.kind == "aam" or w.kind == "agm" or (w.kind == "bomb" and w.guided)) then
      if st.lock and (not st.lock.em.Parent or st.lock.em:GetAttribute("Wreck")) then st.lock = nil end
      if st.lock then
        local root = st.lock.em:FindFirstChild("Root")
        if root then
          local to = root.CFrame.Position - pos
          st.lock.dir, st.lock.dist, st.lock.pos = to.Unit, to.Magnitude, root.CFrame.Position
          if inCone(w, st.lock) and st.lock.dist < (w.range or 3200) * 1.1 then st.lockT += dt else st.lock, st.lockT = nil, 0 end
        else
          st.lock = nil
        end
      end
      if not st.lock then
        st.lock = pickTarget(w)
        st.lockT = 0
      end
    else
      st.lock, st.lockT = nil, 0
    end
    -- 报给服务器（每秒 15 次）
    st.sendT -= dt
    if st.sendT <= 0 and st.pilot and not st.crashed then
      st.sendT = 1 / 15
      local c = st.c
      G.R.Drive:FireServer({ op = "state", cf = st.cf, v = st.vel, gd = st.ground, aim = st.aimPt, thr = c.thr, gear = c.gear, flap = c.flap, cp = c.pit, cr = c.rol,
        cy = c.yaw, bay = c.bay, bays = c.bayS, rpm = c.rpm, col = c.col, can = c.can, hook = c.hook, brk = c.brk, ty = c.ty, gp = c.gp, fold = c.fold })
    end
    -- 平显
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    aName.Text = T("veh." .. d.id) .. (st.pilot and "" or ("   " .. T("air.passenger")))
    local kmh = math.floor(st.vel.Magnitude / AD.M * 3.6 + 0.5)
    local agl = math.floor((pos.Y - ground(pos.X, pos.Z) - d.gearH) / AD.M + 0.5)
    aInfo.Text = T("ui.speed", kmh) .. "    " .. T("air.alt", math.max(0, agl)) .. "    " .. T("air.flares", st.flares) .. "    " .. T("air.fuelP", math.floor((st.fuel + st.fuelX) * 100 + 0.5))
      .. ((d.kind == "jet") and ("    " .. T("air.gearState." .. ((st.gearWant > 0.5) and "down" or "up"))) or "")
    if wid then
      aWpn.Text = "[" .. st.wi .. "/" .. #st.wl .. "] " .. T("aw." .. wid) .. "  ×" .. left(wid)
    else
      aWpn.Text = T("air.noWeapon")
    end
    st.help = st.pilot and (st.uav and "air.helpUav" or ((d.kind == "jet") and "air.helpJet" or "air.helpHeli")) or "air.helpPass"
    if st.pilot then
      spdText.Text = string.format("%d", kmh)
      altText.Text = string.format("%d", math.max(0, agl))
      thrText.Text = (d.kind == "jet") and ((st.thr > 100) and T("air.ab") or string.format("%d%%", math.floor(st.thr + 0.5))) or string.format("RPM %d%%", math.floor(st.rpm))
      vsText.Text = string.format("%+d", math.floor(st.vel.Y / AD.M + 0.5))
      -- 油量：内油 %（+ 副油箱 %）、照现在的油门还能飞几分几秒；少于两成半变黄、一成变红
      local tot = st.fuel + st.fuelX
      local rate = AD.burn(d, (d.kind == "heli") and 100 or st.thr, st.c.col or 0, (d.kind == "heli") and st.rpm or st.thr, st.vel.Magnitude / math.max(d.vMax, 1), st.ground)
      local secs = (rate > 0) and tot / rate or math.huge
      local left2 = (secs < 5999) and string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60)) or "--:--"
      fuelText.Text = T("air.fuel", math.floor(st.fuel * 100 + 0.5)) .. ((st.fuelX > 0) and string.format(" +%d", math.floor(st.fuelX * 100 + 0.5)) or "") .. "  " .. left2
      fuelText.TextColor3 = (tot < 0.1) and RGB(255, 90, 80) or ((tot < 0.25) and RGB(255, 200, 90) or HUD)
      local bp, bon = project(pos + st.cf.LookVector * 400)
      bore.Position, bore.Visible = bp, bon
      if st.uav and st.dcam == "nose" then
        aimRing.Visible = false   -- 前视光电：镜头就是瞄准方向，平板画十字线
      elseif d.kind == "jet" and not G.mobile then
        local ap, aon = project(pos + aimDirNow() * 400)
        aimRing.Position, aimRing.Visible = ap, aon
      else
        aimRing.Position, aimRing.Visible = UDim2.fromScale(0.5, 0.5), d.kind == "heli"
      end
      -- 警告
      local warn = nil
      if st.rwrT and os.clock() < st.rwrT then warn = ((os.clock() * 4) % 1 < 0.6) and T("air.missile") or ""
      elseif st.out and not st.ground then warn = T("air.flameout")
      elseif st.oob then warn = T("air.oob")
      elseif d.kind == "jet" and not st.ground and st.spd < d.stall * 1.05 then warn = T("air.stall")
      elseif not st.ground and agl < 60 and st.vel.Y < -25 then warn = T("air.pullup")
      elseif not st.ground and st.fuel + st.fuelX < 0.12 then warn = ((os.clock() * 2) % 1 < 0.6) and T("air.bingo") or "" end   -- 油不多了：该回去了
      warnText.Text = warn or ""
      warnText.Visible = warn ~= nil
      -- 降落引导：起落架放着、在天上：最近的能落的地方画个菱形，旁边写公里数；菱形按下滑道（3.5°）变色——绿正好、黄偏高、红偏低
      local site = nil
      if d.kind == "jet" and not st.ground and st.gearWant > 0.5 then
        local bd = math.huge
        for _, s2 in ipairs(landSites()) do
          local dd = (V(s2.p.X, 0, s2.p.Z) - V(pos.X, 0, pos.Z)).Magnitude
          if dd < bd then site, bd = s2, dd end
        end
        if site then
          local lp, lon = project(site.p + V(0, 1, 0))
          landMark.Position, landMark.Visible = lp, lon
          landText.Position, landText.Visible = lp + UDim2.fromOffset(0, 22), lon
          local ideal = bd * math.tan(rad(3.5))
          local dh = (pos.Y - d.gearH - site.p.Y) - ideal
          local tol = ideal * 0.35 + 18
          local col = (dh > tol) and RGB(255, 200, 90) or ((dh < -tol) and RGB(255, 90, 80) or RGB(120, 230, 140))
          landMark.TextColor3, landText.TextColor3 = col, col
          landText.Text = string.format("%.1f", bd / AD.M / 1000)
        end
      end
      if not site then landMark.Visible, landText.Visible = false, false end
      -- 锁定框
      if st.lock then
        local lp, lon = project(st.lock.pos)
        local locked = st.lockT >= (w.lockTime or 1)
        lockBox.Position, lockBox.Visible = lp, lon
        lockStroke.Color = locked and RGB(255, 80, 70) or HUD
        lockBox.Size = locked and UDim2.fromOffset(38, 38) or UDim2.fromOffset(52, 52)
        lockText.Position = lp + UDim2.fromOffset(0, 30)
        lockText.Visible = lon
        lockText.Text = locked and (T("air.locked") .. string.format("  %dm", math.floor(st.lock.dist / AD.M))) or T("air.locking", math.floor(st.lockT / (w.lockTime or 1) * 100))
        lockText.TextColor3 = locked and RGB(255, 80, 70) or HUD
      else
        lockBox.Visible, lockText.Visible = false, false
      end
      -- 炸弹落点（不制导的、或者没锁上的制导炸弹）
      if w and w.kind == "bomb" and not (st.lock and st.lockT >= (w.lockTime or 1)) then
        local h = pos.Y - math.max(ground(pos.X, pos.Z), 0)
        local vy = -st.vel.Y
        local tf = (vy + math.sqrt(math.max(0, vy * vy + 2 * GR * math.max(h, 0)))) / GR
        local hit = pos + V(st.vel.X, 0, st.vel.Z) * tf * 0.97
        local gp2, gon = project(V(hit.X, ground(hit.X, hit.Z), hit.Z))
        pipper.Position, pipper.Visible = gp2, gon
      else
        pipper.Visible = false
      end
    end
  end

  -- 被击毁 / 跳伞：服务器推来 alive = false 或 veh = nil，下一帧 stop()
end

return Fly
