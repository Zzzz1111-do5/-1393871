-- Roblox全面大战场（客户端）——操作地图自带的工事（走到跟前按 E 接手，F 离开）
--   机枪碉堡：坐在机枪后面从射孔往外看，鼠标转枪（左右各 60°），按住左键连发；
--   高炮：炮后面的追尾镜头，按住左键连发（近炸引信），准星旁边给最近的敌机画提前量菱形；
--   岸防炮：炮塔后面的镜头，右键 / V 进瞄准镜（滚轮换倍率），准星指哪儿炮按弹道自己抬到哪儿，左键一发；
--   榴弹炮：高处往前看，准星下的地面就是落点（地上一个圈、显示距离和射程），左键开炮；炮只能左右转 25°
--   炮塔转动有速度上限（和服务器一样），每秒 12 次把方位、俯仰报给服务器
--   另：工兵的破障器材（G.breachStep，Play 每帧调）——每半秒探一次雷，地上标出来；按住左键排雷 / 剪铁丝网（有进度）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Gunner = {}

function Gunner.init(G)
  local FD = require(RS:WaitForChild("FortDefs"))
  local Map = G.Map
  local Config = G.Config
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local ui = G.ui
  local function T(k, ...) return G.T(k, ...) end
  local SHELL_G = workspace.Gravity * 0.55

  local gs = nil   -- 正在操作的工事
  G.gunner = nil

  ---------------------------------------------------------------- 界面

  local gui = Instance.new("ScreenGui")
  gui.Name = "Gunner"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")

  local panel = ui.frame(gui, UDim2.fromOffset(420, 70), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.3, Vector2.new(0.5, 1))   -- 操作说明在屏幕最下面一行（UI.lua，gs.help）
  ui.round(panel, 10)
  panel.Visible = false
  local fName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 6), UDim2.fromOffset(10, 29), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local fInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 38), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local relBg = ui.frame(panel, UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 58), RGB(0, 0, 0), 0.5)
  local relBar = ui.frame(relBg, UDim2.fromScale(1, 1), nil, RGB(240, 200, 80), 0)
  local cross = ui.label(gui, "+", UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), 26, Color3.new(1, 1, 1), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  cross.TextStrokeTransparency = 0.4
  cross.Visible = false
  local gunMark = ui.label(gui, "◯", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), 20, RGB(255, 210, 80), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  gunMark.TextStrokeTransparency = 0.3
  gunMark.Visible = false
  local leadMark = ui.label(gui, "◇", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), 24, RGB(255, 90, 70), Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  leadMark.TextStrokeTransparency = 0.3
  leadMark.Visible = false
  local rangeText = ui.label(gui, "", UDim2.fromOffset(320, 24), UDim2.new(0.5, 0, 0.5, 34), 16, RGB(255, 236, 170), Enum.Font.Code, Vector2.new(0.5, 0))
  rangeText.TextStrokeTransparency = 0.4
  rangeText.Visible = false
  local scopeBox = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  scopeBox.Visible = false
  do   -- 瞄准镜：四周压暗的圆、细十字
    local eye = Instance.new("Frame")
    eye.AnchorPoint = Vector2.new(0.5, 0.5)
    eye.Position = UDim2.fromScale(0.5, 0.5)
    eye.Size = UDim2.fromScale(0.86, 0.86)
    eye.BackgroundTransparency = 1
    eye.Parent = scopeBox
    local a = Instance.new("UIAspectRatioConstraint")
    a.AspectRatio = 1
    a.Parent = eye
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = eye
    local s = Instance.new("UIStroke")
    s.Thickness = 900
    s.Color = Color3.new(0, 0, 0)
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = eye
    ui.frame(scopeBox, UDim2.new(0.5, 0, 0, 1), UDim2.fromScale(0.5, 0.5), RGB(230, 230, 230), 0.2, Vector2.new(0.5, 0.5))
    ui.frame(scopeBox, UDim2.new(0, 1, 0.5, 0), UDim2.fromScale(0.5, 0.5), RGB(230, 230, 230), 0.2, Vector2.new(0.5, 0.5))
  end

  -- 榴弹炮的落点圈（只在本机）
  local ring = Instance.new("Part")
  ring.Shape = Enum.PartType.Cylinder
  ring.Size = V(0.3, 30, 30)
  ring.Color = RGB(255, 80, 60)
  ring.Material = Enum.Material.Neon
  ring.Transparency = 1
  ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
  ring.CastShadow = false
  ring.Parent = workspace

  ---------------------------------------------------------------- 开始、结束

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end

  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = FD.D[vs.fort]
    if not d then return end
    local root = em:FindFirstChild("Root")
    if not root then return end
    local base = root.CFrame * CF(0, -d.size.Y / 2, 0)
    local ty, gp = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0
    local look = base.LookVector
    gs = { id = vs.id, em = em, kind = vs.fort, d = d, w = FD.W[d.weapon], base = base, ty = ty, gp = gp,
      ay = ty, ap = gp, camYaw = math.atan2(-look.X, -look.Z), camPitch = (vs.fort == "howitzer") and -0.32 or -0.1,
      sight = false, zoom = 1, firing = false, sendT = 0, nextAt = 0 }
    G.gunner, G.drive = gs, gs   -- G.drive：步兵的操作（Play）先停下
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible, cross.Visible = true, true
    if G.touchGunUI then G.touchGunUI.Visible = true end
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    if gs and gs.firing then G.R.Drive:FireServer({ op = "trig", on = false }) end
    gs = nil
    if G.drive and G.drive == G.gunner then G.drive = nil end
    G.gunner = nil
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible, cross.Visible, gunMark.Visible, leadMark.Visible, rangeText.Visible, scopeBox.Visible = false, false, false, false, false, false
    ring.Transparency = 1
    if G.touchGunUI then G.touchGunUI.Visible = false end
  end

  ---------------------------------------------------------------- 开火

  local function auto() return gs.w.kind == "gun" or gs.w.kind == "flak" end
  local function setTrig(on)
    if not gs then return end
    if auto() then
      if on ~= gs.firing then G.R.Drive:FireServer({ op = "trig", on = on }) end
      gs.firing = on
    elseif on then
      local t = os.clock()
      if t < gs.nextAt then return end
      gs.nextAt = t + gs.w.rate
      G.R.Drive:FireServer({ op = "fire", aim = gs.aimPt })
      if G.shake then G.shake(0.25) end
      if G.vehRecoil then G.vehRecoil(gs.id) end
    end
  end
  G.gunnerTrig = setTrig

  ---------------------------------------------------------------- 手机：开火、瞄准镜、离开；拖屏幕转炮

  if UIS.TouchEnabled then
    local rb = ui.frame(gui, UDim2.fromOffset(240, 200), UDim2.new(1, -250, 1, -300), RGB(0, 0, 0), 1)
    rb.Visible = false
    local function btn(text, pos, size)
      local b = ui.button(rb, text, UDim2.fromOffset(size or 64, size or 64), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 15
      return b
    end
    local fb = btn("●", UDim2.fromOffset(140, 100), 90)
    fb.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then setTrig(true) end end)
    fb.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then setTrig(false) end end)
    btn("◎", UDim2.fromOffset(60, 120)).Activated:Connect(function() if gs then gs.sight = not gs.sight end end)
    btn("F", UDim2.fromOffset(0, 0)).Activated:Connect(function() G.R.Drive:FireServer({ op = "exit" }) end)
    G.touchGunUI = rb
  end

  ---------------------------------------------------------------- 输入

  local ZOOMS = { 24, 9 }
  UIS.InputBegan:Connect(function(io, gpe)
    if gpe or not gs then return end
    local k = io.KeyCode
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      setTrig(true)
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.V then
      gs.sight = not gs.sight
    elseif k == Enum.KeyCode.Z then
      gs.zoom = gs.zoom % #ZOOMS + 1
    elseif k == Enum.KeyCode.F then
      G.R.Drive:FireServer({ op = "exit" })
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if gs and io.UserInputType == Enum.UserInputType.MouseButton1 then setTrig(false) end
  end)
  UIS.InputChanged:Connect(function(io)
    if not gs then return end
    if gs.sight and io.UserInputType == Enum.UserInputType.MouseWheel then
      gs.zoom = math.clamp(gs.zoom + ((io.Position.Z > 0) and 1 or -1), 1, #ZOOMS)
    elseif io.UserInputType == Enum.UserInputType.Touch and io.Delta then   -- 手机：拖屏幕转
      gs.touchD = (gs.touchD or Vector2.new()) + Vector2.new(io.Delta.X, io.Delta.Y)
    end
  end)

  ---------------------------------------------------------------- 每帧

  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end
  local function approach(a, b, s) if a < b then return math.min(b, a + s) end return math.max(b, a - s) end
  -- 工事坐标系里的方位、俯仰 → 世界方向
  local function dirOf(base, yaw, pitch) return (base * CFrame.Angles(0, -math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector end
  local function anglesOf(base, dir)
    local l = base:VectorToObjectSpace(dir)
    return math.deg(math.atan2(l.X, -l.Z)), math.deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)))
  end
  local function lowAngle(v, g, R, h)
    local v2 = v * v
    local disc = v2 * v2 - g * (g * R * R + 2 * h * v2)
    if disc < 0 or R < 1 then return nil end
    return math.atan((v2 - math.sqrt(disc)) / (g * R))
  end

  -- 准星打到哪：从镜头往前打一条射线（不算实体的样子、自己）
  local function aimRay(o, dir, len)
    local ex = { G.viewFolder }
    if me.Character then table.insert(ex, me.Character) end
    if gs and gs.em then table.insert(ex, gs.em) end
    aimParams.FilterDescendantsInstances = ex
    local res = workspace:Raycast(o, dir * len, aimParams)
    return res and res.Position or (o + dir * len), res ~= nil
  end

  -- 高炮：准星附近（20° 以内）最近的敌机，按它的速度和炮弹速度算提前量
  local track = {}
  local function leadFor(o)
    local ents = workspace:FindFirstChild("Ents")
    if not ents then return nil end
    local best, bd = nil, math.huge
    local look = cam.CFrame.LookVector
    local side = me:GetAttribute("Side")
    local t = os.clock()
    for _, m in ipairs(ents:GetChildren()) do
      if m:GetAttribute("Cat") == "air" and m:GetAttribute("Team") ~= side then
        local r = m:FindFirstChild("Root")
        if r then
          local p = r.Position
          local tr = track[m]
          if tr and t > tr.t then
            local v = (p - tr.p) / (t - tr.t)
            tr.v = tr.v and tr.v:Lerp(v, 0.25) or v
          end
          track[m] = { p = p, t = t, v = tr and tr.v or V() }
          local to = p - o
          local d = to.Magnitude
          if d < gs.w.range * 1.1 and to.Unit:Dot(look) > math.cos(math.rad(20)) and d < bd then best, bd = m, d end
        end
      end
    end
    if not best then return nil end
    local tr = track[best]
    local s = gs.w.speed
    local rel = tr.p - o
    local tof = rel.Magnitude / s
    for _ = 1, 3 do tof = ((tr.p + tr.v * tof) - o).Magnitude / s end
    return tr.p + tr.v * tof + V(0, 0.5 * SHELL_G * (gs.w.gscale or 0) * tof * tof, 0)
  end

  local SENS = 0.0042
  function G.stepGunner(dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and not vs.fort then vs = nil end
    if vs and (not gs or gs.id ~= vs.id) then
      if gs then stop() end
      begin(vs)
    elseif not vs and gs then
      stop()
    end
    if not gs then return end
    if not gs.em.Parent then stop() return end
    local d, w = gs.d, gs.w
    local root = gs.em:FindFirstChild("Root")
    if root then gs.base = root.CFrame * CF(0, -d.size.Y / 2, 0) end
    local base = gs.base
    local Tt = d.turret
    local full = Tt.arc >= 180
    -- 鼠标（手机拖屏幕）：转想要的方向
    UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
    local md = UIS:GetMouseDelta()
    if gs.touchD then md = md + gs.touchD * 0.6 gs.touchD = nil end
    local fov = gs.sight and ZOOMS[gs.zoom] or 70
    local sens = SENS * fov / 70
    local tPivot = (base * CF(Tt.pivot)).Position
    local o, look
    if gs.kind == "bunker" or gs.kind == "aaa" then
      -- 鼠标直接给想要的方位、俯仰（碉堡里限在射孔的范围内）
      gs.ay = gs.ay - md.X * sens * 57.3
      gs.ap = math.clamp(gs.ap - md.Y * sens * 57.3, Tt.elev[1], Tt.elev[2])
      if full then gs.ay = (gs.ay + 180) % 360 - 180 else gs.ay = math.clamp(gs.ay, -Tt.arc, Tt.arc) end
      look = dirOf(base, gs.ay, gs.ap)
      if gs.kind == "bunker" then
        local tF = base * CF(Tt.pivot) * CFrame.Angles(0, -math.rad(gs.ty), 0)
        o = (tF * CF(0, 0.45, 1.7)).Position   -- 机枪后面，眼睛和射孔一样高
      else
        o = tPivot + dirOf(base, gs.ay, 0) * -16 + V(0, 5, 0)
      end
      if gs.sight then o = tPivot + V(0, 1.4, 0) end
      cam.CFrame = CFrame.lookAt(o, o + look)
      gs.aimPt = aimRay(cam.CFrame.Position, look, w.range)
    else
      -- 岸防炮、榴弹炮：镜头绕着炮转，准星指哪儿炮算到哪儿
      gs.camYaw -= md.X * sens
      gs.camPitch = math.clamp(gs.camPitch - md.Y * sens, -1.2, 0.5)
      local dirCam = CFrame.Angles(0, gs.camYaw, 0) * CFrame.Angles(gs.camPitch, 0, 0)
      look = dirCam.LookVector
      if gs.sight then
        o = tPivot + V(0, (gs.kind == "coastal") and 6 or 4, 0)
      elseif gs.kind == "coastal" then
        o = tPivot + dirCam:VectorToWorldSpace(V(0, 0, 34)) + V(0, 10, 0)
      else
        o = tPivot + dirCam:VectorToWorldSpace(V(0, 0, 30)) + V(0, 22, 0)
      end
      cam.CFrame = CFrame.lookAt(o, o + look)
      local maxL = (w.kind == "arty") and (w.maxR + 600) or w.range
      gs.aimPt = aimRay(o, look, maxL)
      local rel = gs.aimPt - tPivot
      local yaw = anglesOf(base, rel)
      local R = V(rel.X, 0, rel.Z).Magnitude
      if w.kind == "shell" then   -- 按弹道自动抬炮
        local mz = (base * CF(Tt.pivot) * CF(d.gun.pivot)).Position
        local rr = gs.aimPt - mz
        local th = lowAngle(w.speed, SHELL_G * w.gscale, V(rr.X, 0, rr.Z).Magnitude, rr.Y)
        gs.ay, gs.ap = yaw, th and math.deg(th) or Tt.elev[2]
      else   -- 榴弹炮：炮管抬到大约（只是好看，落点按准星算）
        gs.ay, gs.ap = yaw, math.clamp(18 + R / w.maxR * 45, 15, 65)
      end
      if not full then gs.ay = math.clamp(gs.ay, -Tt.arc, Tt.arc) end
      gs.ap = math.clamp(gs.ap, Tt.elev[1], Tt.elev[2])
    end
    cam.FieldOfView = cam.FieldOfView + (fov - cam.FieldOfView) * math.min(1, dt * 10)
    -- 炮塔（和服务器一样的回转速度）
    local s = Tt.trav * dt
    if full then gs.ty = (gs.ty + math.clamp(angDiff(gs.ty, gs.ay), -s, s) + 180) % 360 - 180
    else gs.ty = gs.ty + math.clamp(gs.ay - gs.ty, -s, s) end
    gs.gp = approach(gs.gp, gs.ap, math.max(30, Tt.trav) * dt)
    -- 报给服务器
    gs.sendT -= dt
    if gs.sendT <= 0 then
      gs.sendT = 1 / 12
      G.R.Drive:FireServer({ op = "aim", ty = gs.ty, gp = gs.gp, aim = gs.aimPt })
    end
    -- 炮现在指着哪（黄圈）；高炮的提前量（红菱形）
    local gF = FD.gunCF(d, base, gs.ty, gs.gp)
    local far = gF.Position + gF.LookVector * math.max(40, (gs.aimPt - gF.Position).Magnitude)
    local sp, on = cam:WorldToViewportPoint(far)
    gunMark.Visible = on and w.kind ~= "arty" and not gs.sight
    gunMark.Position = UDim2.fromOffset(sp.X, sp.Y)
    leadMark.Visible = false
    if w.kind == "flak" then
      local lp = leadFor(gF.Position)
      if lp then
        local p2, on2 = cam:WorldToViewportPoint(lp)
        leadMark.Visible = on2
        leadMark.Position = UDim2.fromOffset(p2.X, p2.Y)
      end
    end
    scopeBox.Visible = gs.sight and w.kind ~= "arty"
    -- 榴弹炮：落点圈、距离
    rangeText.Visible = w.kind == "arty" or w.kind == "shell"
    if w.kind == "arty" then
      local a = gs.aimPt
      local dist = V(a.X - tPivot.X, 0, a.Z - tPivot.Z).Magnitude
      local okR = dist >= w.minR and dist <= w.maxR
      ring.Transparency = 0.45
      ring.Color = okR and RGB(255, 200, 70) or RGB(255, 60, 50)
      ring.CFrame = CF(a.X, Map.ground(a.X, a.Z) + 0.3, a.Z) * CFrame.Angles(0, 0, math.pi / 2)
      rangeText.Text = T("ui.howRange", math.floor(dist / 2.8 + 0.5), math.floor(w.minR / 2.8), math.floor(w.maxR / 2.8))
      rangeText.TextColor3 = okR and RGB(255, 236, 170) or RGB(255, 110, 90)
    elseif w.kind == "shell" then
      ring.Transparency = 1
      local dist = (gs.aimPt - tPivot).Magnitude
      rangeText.Text = string.format("%04d m   %+.1f°", math.floor(dist / 2.8 / 5 + 0.5) * 5, gs.gp)
    else
      ring.Transparency = 1
    end
    cross.Visible = not (gs.sight and w.kind ~= "arty")
    -- 仪表
    local em = gs.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = RGB(230, 70, 60):Lerp(RGB(90, 210, 110), math.clamp(hp / mx, 0, 1))
    fName.Text = T("fort." .. gs.kind)
    local info = T("fw." .. w.id)
    local rel = 1
    if vs.reload and vs.reload > 0 then
      info = info .. "    " .. T("ui.reloadIn", math.ceil(vs.reload))
      rel = 0
    elseif vs.mag then
      info = info .. "    " .. vs.mag .. " / " .. (vs.magMax or "∞")
    end
    if not auto() then
      local left = gs.nextAt - os.clock()
      rel = 1 - math.clamp(left / w.rate, 0, 1)
    end
    relBar.Size = UDim2.fromScale(rel, 1)
    fInfo.Text = info
    gs.help = (w.kind == "arty") and "ui.howHelp" or "ui.fortHelp"
  end

  ---------------------------------------------------------------- 工兵的破障器材

  local RShoot = G.R.Shoot
  local W = Config.Weapons.breach
  local marks = {}       -- 本机探到的雷：[编号] = { part, p }
  local known = {}       -- 队友探出来的雷
  local scanT, work = 0, nil
  local wireList = {}
  do
    local ok, ob = pcall(FD.obstacles, Map)
    if ok and ob then wireList = ob.wire end
  end

  local function mark(list, key, p, at, far)
    local m = list[key]
    if m then m.p = p return end
    local a = Instance.new("Part")
    a.Size, a.Transparency, a.Anchored = V(0.2, 0.2, 0.2), 1, true
    a.CanCollide, a.CanQuery, a.CanTouch = false, false, false
    a.CFrame = CF(p + V(0, 2.2, 0))
    a.Parent = workspace
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(22, 22)
    bb.AlwaysOnTop = true
    bb.MaxDistance = far and 220 or 80
    bb.Parent = a
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundTransparency = 1
    l.Text = at and "▲" or "●"
    l.TextScaled = true
    l.TextColor3 = at and RGB(255, 140, 40) or RGB(255, 60, 50)
    l.TextStrokeTransparency = 0.3
    l.Parent = bb
    list[key] = { part = a, p = p }
  end
  local function setMarks(list, items, far)
    local seen = {}
    for _, it in ipairs(items or {}) do
      if typeof(it.p) == "Vector3" then
        seen[it.k] = true
        mark(list, it.k, it.p, it.at, far)
      end
    end
    for k, m in pairs(list) do
      if not seen[k] then m.part:Destroy() list[k] = nil end
    end
  end

  -- 服务器发来的雷：自己探到的（mine）、队友探出来的（known）
  local onFx0 = G.onFx
  G.onFx = function(list)
    for _, e in ipairs(list) do
      if e.k == "mines" then
        if e.known then setMarks(known, e.list, true) else setMarks(marks, e.list, false) end
      elseif e.k == "wireCut" and G.playSound then G.playSound("repair", e.p)
      elseif e.k == "defuse" and G.playSound then G.playSound("heal", e.p) end
    end
    if onFx0 then onFx0(list) end
  end

  local function nearestThing(hp)
    local best, bd, kind = nil, W.range, nil
    for k, m in pairs(marks) do
      local dd = V(m.p.X - hp.X, 0, m.p.Z - hp.Z).Magnitude
      if dd < bd then best, bd, kind = k, dd, "mine" end
    end
    if best then return best, kind end
    local wf = workspace:FindFirstChild("Map")
    wf = wf and wf:FindFirstChild("Wire")
    for i, Wr in ipairs(wireList) do
      if wf and wf:FindFirstChild("Wire" .. i) then
        local ax, az, bx, bz = Wr.a.X, Wr.a.Z, Wr.b.X, Wr.b.Z
        local dx, dz = bx - ax, bz - az
        local L2 = dx * dx + dz * dz
        local k = (L2 > 0) and math.clamp(((hp.X - ax) * dx + (hp.Z - az) * dz) / L2, 0, 1) or 0
        local dd = V(ax + dx * k - hp.X, 0, az + dz * k - hp.Z).Magnitude
        if dd < bd then best, bd, kind = "w" .. i, dd, "wire" end
      end
    end
    return best, kind
  end

  -- Play 每帧调：active 拿着破障器材、firing 按着左键；返回要显示的提示
  function G.breachStep(dt, active, firing)
    if not active then
      if next(marks) then setMarks(marks, {}, false) end
      work = nil
      return nil
    end
    local char = me.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    scanT -= dt
    if scanT <= 0 then
      scanT = 0.5
      RShoot:FireServer("breach", "scan")
    end
    local key, kind = nearestThing(hrp.Position)
    if firing and key then
      if not work or work.key ~= key then
        work = { key = key, kind = kind, t = 0 }
        RShoot:FireServer("breach", "start", key)
      end
      work.t += dt
      if work.t >= W.time then
        RShoot:FireServer("breach", "done", key)
        if kind == "mine" and marks[key] then marks[key].part:Destroy() marks[key] = nil end
        work = nil
        return nil
      end
      return T((kind == "mine") and "ui.defusing" or "ui.cutting", math.floor(work.t / W.time * 100))
    end
    work = nil
    local n = 0
    for _ in pairs(marks) do n += 1 end
    if key and kind == "wire" and n == 0 then return T("ui.wireNear") end
    if n > 0 then return T("ui.mineNear", n) end
    return T("ui.noMines")
  end
end

return Gunner
