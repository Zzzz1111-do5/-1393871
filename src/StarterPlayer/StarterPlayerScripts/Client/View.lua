-- Roblox全面大战场（客户端）——实体的样子：服务器上只有一个隐形的 Root（位置）和属性（Kind 种类、Team 队伍、Hp 血量……），
--   这里按种类拼一个本地模型，每帧平滑地跟着 Root 走（服务器 10～15 次 / 秒地挪，直接跟会一顿一顿的）；头顶血条
--   机器人步兵（摆腿走路、倒地）、登陆艇（放跳板、被打沉往下沉）、气垫艇、炸药包、地雷
--   地面载具（VehModels 拼的）：每个车轮 / 负重轮各自一个弹簧阻尼（按脚下的地面高度 + 细碎的颠簸，过坡上下抖），
--     车体跟着轮子上下、前后俯仰、左右侧倾（也带弹簧，刹车点头、起步抬头）；炮塔、炮按属性 Ty / Gp 转（自己开的车用本地的），
--     开炮后坐、车轮按走的路转、前轮转向、雷达转、扬尘、被毁冒火冒黑烟；零件一次 BulkMoveTo
--   别的模块能登记自己的样子：G.viewKind[种类] = { build(v, em, team), step(v, dt, camPos), recoil(v), remove(v) }（工事在 FortView）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local View = {}

function View.init(G)
  local Config = G.Config
  local Map = require(RS:WaitForChild("Map"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local VM = require(script.Parent:WaitForChild("VehModels"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer

  -- 一个 Model 装所有实体的样子：热成像时整个打一个高亮（Highlight 有数量上限）
  local VF = Instance.new("Model")
  VF.Name = "EntView"
  VF.Parent = workspace
  G.viewFolder = VF

  local function p(m, size, cf, color, mat, shape)
    local x = Instance.new("Part")
    if shape then x.Shape = shape end
    x.Size, x.CFrame, x.Color = size, cf, color
    x.Material = mat or Enum.Material.SmoothPlastic
    x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
    x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    x.Parent = m
    return x
  end

  -- 每种实体：拼零件（相对 Root 的偏移记在 parts 里），每帧额外动（腿、跳板）
  local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }
  local KINDS = {}
  -- 机器人：服务器的命中盒高 5.6 格、中心在脚底上 2.8 格
  KINDS.bot = function(m, team)
    local U = UNIFORM[team] or UNIFORM.atk
    local L = {}
    L.torso = { p(m, V(2, 2, 1), CF(), U[1]), CF(0, 0.4, 0) }
    L.vest = { p(m, V(2.15, 1.3, 1.25), CF(), U[2]), CF(0, 0.55, 0) }
    L.head = { p(m, V(1.2, 1.2, 1.2), CF(), RGB(230, 190, 150)), CF(0, 2.0, 0) }
    L.helmet = { p(m, V(1.45, 0.65, 1.45), CF(), U[2], Enum.Material.SmoothPlastic), CF(0, 2.55, 0) }
    -- 夜视仪：头盔前面的支架和双筒（机器人夜里一直戴着、翻下来）
    L.nvg = { p(m, V(0.62, 0.24, 0.3), CF(), RGB(28, 30, 32), Enum.Material.Metal), CF(0, 2.22, -0.78) }
    for sx = -1, 1, 2 do
      L["nvgTube" .. sx] = { p(m, V(0.42, 0.24, 0.24), CF(), RGB(22, 24, 26), Enum.Material.Metal, Enum.PartType.Cylinder),
        CF(sx * 0.17, 2.12, -1.0) * CFrame.Angles(0, math.pi / 2, 0) }
    end
    L.lleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(-0.5, -1.6, 0), "leg", 1 }
    L.rleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(0.5, -1.6, 0), "leg", -1 }
    L.larm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(-1.2, 0.5, -0.5) * CFrame.Angles(-1.2, 0.35, 0) }
    L.rarm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(1.3, 0.5, -0.4) * CFrame.Angles(-1.2, 0, 0) }
    L.gun = { p(m, V(0.35, 0.45, 3.2), CF(), RGB(45, 47, 50), Enum.Material.Metal), CF(0.35, 0.75, -1.7) }
    L.band = { p(m, V(0.85, 0.35, 0.85), CF(), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(1.3, 1.0, -0.3) }
    return L
  end
  KINDS.lcm = function(m, team)
    local L = {}
    local hull = RGB(96, 104, 98)
    L.bottom = { p(m, V(16, 2, 34), CF(), hull, Enum.Material.Metal), CF(0, -2, 0) }
    L.lwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(-7.5, 1, 0) }
    L.rwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(7.5, 1, 0) }
    L.back = { p(m, V(16, 7, 1), CF(), hull, Enum.Material.Metal), CF(0, 1.5, 16.5) }
    L.cab = { p(m, V(6, 4, 4), CF(), RGB(120, 128, 120), Enum.Material.Metal), CF(0, 5, 14) }
    L.ramp = { p(m, V(15, 6, 0.8), CF(), hull, Enum.Material.Metal), CF(0, 1, -17), "ramp" }
    return L
  end
  -- 726 型气垫艇：黑色气垫围裙、甲板、两侧上层建筑、尾部两个大风扇
  KINDS.lcac = function(m)
    local L = {}
    local grey = RGB(112, 120, 116)
    L.skirt = { p(m, V(28, 3, 48), CF(), RGB(30, 30, 32), Enum.Material.Fabric), CF(0, -1.6, 0) }
    L.deck = { p(m, V(24, 1, 44), CF(), grey, Enum.Material.DiamondPlate), CF(0, 0.2, 0) }
    for s = -1, 1, 2 do
      L["side" .. s] = { p(m, V(3, 4, 40), CF(), grey, Enum.Material.Metal), CF(s * 12.5, 2.3, 0) }
      L["fan" .. s] = { p(m, V(2, 9, 9), CF(), RGB(70, 74, 72), Enum.Material.Metal, Enum.PartType.Cylinder), CF(s * 6, 6, 20) * CFrame.Angles(0, math.pi / 2, 0) }
      L["fin" .. s] = { p(m, V(0.4, 6, 3), CF(), grey, Enum.Material.Metal), CF(s * 6, 6, 23.5) }
    end
    L.bridge = { p(m, V(4, 4, 6), CF(), grey, Enum.Material.Metal), CF(10.5, 6.2, -14) }
    return L
  end
  KINDS.c4 = function(m) return { b = { p(m, V(1.1, 0.5, 0.7), CF(), RGB(176, 156, 112)), CF() }, l = { p(m, V(0.2, 0.2, 0.2), CF(), RGB(255, 40, 40), Enum.Material.Neon), CF(0, 0.3, 0) } } end
  KINDS.mine = function(m) return { b = { p(m, V(0.4, 1.4, 1.4), CF(), RGB(86, 96, 64), Enum.Material.Metal, Enum.PartType.Cylinder), CFrame.Angles(0, 0, math.pi / 2) } } end

  local views = {}   -- [entModel] = { model, parts, cf, kind, t, … }
  G.views = views
  local byId = {}    -- [实体编号] = view（开炮后坐要按编号找）
  local function bar(m, adornee, h)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(46, 6)
    bb.StudsOffsetWorldSpace = V(0, h or 5, 0)
    bb.MaxDistance = 260
    bb.Adornee = adornee
    bb.Parent = m
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = RGB(0, 0, 0)
    bg.BackgroundTransparency = 0.4
    bg.BorderSizePixel = 0
    bg.Parent = bb
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BorderSizePixel = 0
    f.Parent = bg
    return bb, f
  end

  local function add(em)
    if views[em] then return end
    local kind = em:GetAttribute("Kind")
    local root = em:FindFirstChild("Root")
    if not root then return end
    local team = em:GetAttribute("Team")
    local v = { cf = root.CFrame, root = root, kind = kind, t = 0, team = team, id = em:GetAttribute("EntId"), em = em }
    local ext = G.viewKind and G.viewKind[kind]   -- 别的模块登记的样子（工事 FortView……）：build 设好 v.model、v.anchor（血条挂点）
    if kind == "veh" then
      local d = VD.get(em:GetAttribute("Model") or "")
      if not d then return end
      local M = VM.build(d, team)
      M.model.Parent = VF
      v.M, v.def, v.model = M, d, M.model
      v.ty, v.gp, v.recoil = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0, 0
      v.bob, v.bobV, v.pitch, v.pitchV, v.roll, v.rollV = 0, 0, 0, 0, 0, 0
      v.speed, v.steer, v.lastPos, v.lastYaw = 0, 0, root.CFrame.Position, 0
      v.plist, v.clist = {}, {}
      for i, it in ipairs(M.parts) do v.plist[i] = it[1] end
      local anchor = Instance.new("Part")   -- 血条挂的点（在车顶上）
      anchor.Size, anchor.Transparency, anchor.Anchored = V(0.2, 0.2, 0.2), 1, true
      anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
      anchor.Parent = M.model
      v.anchor = anchor
      v.bb, v.fill = bar(M.model, anchor, 2)
      v.bb.MaxDistance = 600
    elseif ext then
      if not ext.build(v, em, team) or not v.model then return end
      v.ext = ext
      v.model.Parent = VF
      v.bb, v.fill = bar(v.model, v.anchor, 2)
      v.bb.MaxDistance = 600
    else
      local mk = KINDS[kind]
      if not mk then return end
      local m = Instance.new("Model")
      m.Name = kind
      v.parts = mk(m, team)
      v.model = m
      m.Parent = VF
      v.bb, v.fill = bar(m, v.parts[next(v.parts)][1])
    end
    v.fill.BackgroundColor3 = Config.Teams[team or "atk"].color
    views[em] = v
    if v.id then byId[v.id] = v end
  end

  -- 实体没了：被打死的步兵倒地几秒、被打沉的艇往下沉，其余直接删
  local dying = {}
  local function remove(em)
    local v = views[em]
    if not v then return end
    views[em] = nil
    if v.id then byId[v.id] = nil end
    local hp = em:GetAttribute("Hp") or 1
    if v.ext and v.ext.remove then
      local ok, keep = pcall(v.ext.remove, v)
      if not ok and G.showError then G.showError("local view: " .. tostring(keep)) end
      if ok and keep == true then return end   -- 自己收尾（机器人倒地，Soldier.lua）
    end
    if hp <= 0 and v.kind ~= "veh" and not v.ext then
      v.t0 = os.clock()
      if v.bb then v.bb:Destroy() end
      table.insert(dying, v)
    else
      v.model:Destroy()
    end
  end
  local function stepDying()
    local t = os.clock()
    for i = #dying, 1, -1 do
      local v = dying[i]
      local a = t - v.t0
      if a > ((v.kind == "bot") and 6 or 5) then
        v.model:Destroy()
        table.remove(dying, i)
      else
        local cf
        if v.kind == "bot" then   -- 绕脚底往后倒
          local k = math.clamp(a / 0.45, 0, 1)
          cf = v.cf * CF(0, -2.8, 0) * CFrame.Angles(k * k * 1.45, 0, 0) * CF(0, 2.8 - 0.4 * k, 0)
        else
          cf = v.cf * CF(0, -a * 2.2, 0) * CFrame.Angles(0, 0, a * 0.12)
        end
        for _, L in pairs(v.parts) do L[1].CFrame = cf * L[2] end
      end
    end
  end

  -- 开炮：这辆车的炮往后坐一下
  function G.vehRecoil(id, g)   -- g：第几门炮（舰艇有前后两门的）
    local v = byId[id]
    if v and v.kind == "veh" then v.recoil = (v.def.cat == "tank" or v.def.cat == "arty") and 1.2 or 0.35
    elseif v and v.ext and v.ext.recoil then v.ext.recoil(v, g) end
  end

  ---------------------------------------------------------------- 载具：悬架

  -- 细碎的颠簸（土路、草地上轮子一跳一跳）：两层噪声，约 ±0.35 格
  local function bump(x, z)
    return 0.22 * math.noise(x / 5.3, z / 5.3, 0.37) + 0.12 * math.noise(x / 2.1, z / 2.1, 4.1)
  end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  local function stepVeh(v, dt, camPos)
    local em, d, M = v.em, v.def, v.M
    -- 车灯：有人开、没被打爆才亮
    local lit = (em:GetAttribute("Driver") or 0) ~= 0 and not v.wrecked
    if v.lit ~= lit and M.lamps then
      v.lit = lit
      for _, p in ipairs(M.lamps) do
        p.Transparency = lit and 0 or 0.75
        for _, L in ipairs(p:GetChildren()) do if L:IsA("Light") then L.Enabled = lit end end
      end
    end
    local own = G.myVeh and G.myVeh.em == em and G.myVeh
    local target = own and own.root or v.root.CFrame
    -- 位置：自己开的直接用本地算的；别人的平滑跟
    if own then v.cf = target else v.cf = v.cf:Lerp(target, math.min(1, dt * 12)) end
    local base = v.cf * CF(0, -d.H / 2, 0)
    -- 速度、转弯（别人的车按位置变化估）
    local pos = base.Position
    if own then
      v.speed, v.steer, v.accel = own.speed, own.steer, own.accel or 0
    else
      local delta = pos - v.lastPos
      local sp = delta:Dot(base.LookVector) / math.max(dt, 1e-3)
      v.accel = (sp - v.speed) / math.max(dt, 1e-3)
      v.speed = v.speed + (sp - v.speed) * math.min(1, dt * 6)
      local _, yaw = base:ToEulerAnglesYXZ()
      local yr = angDiff(math.deg(v.lastYaw), math.deg(yaw)) / math.max(dt, 1e-3)
      v.steer = v.steer + (math.clamp(-yr / math.max(d.turn, 1), -1, 1) - v.steer) * math.min(1, dt * 6)
      v.lastYaw = yaw
    end
    v.lastPos = pos
    -- 炮塔、炮
    local ty, gp = em:GetAttribute("Ty") or 0, em:GetAttribute("Gp") or 0
    if own then ty, gp = own.ty, own.gp end
    if own then v.ty, v.gp = ty, gp else
      v.ty = v.ty + angDiff(v.ty, ty) * math.min(1, dt * 10)
      v.gp = v.gp + (gp - v.gp) * math.min(1, dt * 10)
    end
    v.recoil = math.max(0, v.recoil - dt * 2.6)
    local far = (pos - camPos).Magnitude > 420
    -- 轮子：每个一个弹簧阻尼；远了不算（省事）
    local W = M.wheels
    local rough = 1
    local onWater = Map.height(pos.X, pos.Z) < -1.5
    local sF, nF, sB, nB, sL, nL, sR, nR, sum = 0, 0, 0, 0, 0, 0, 0, 0, 0
    if not far then
      for _, w in ipairs(W) do
        local wp = (base * CF(w.x, 0, w.z)).Position
        local gy = Map.height(wp.X, wp.Z)
        local tgt
        local trv = M.travel or d.travel   -- 原模型的履带车：履带是死的，负重轮只能动一点
        if gy < -0.5 and onWater then tgt = -trv   -- 在水里：轮子垂下去
        else tgt = math.clamp(math.max(gy, -0.5) + bump(wp.X, wp.Z) * rough - wp.Y, -trv, trv) end
        local a = (tgt - w.dy) * 420 - w.vy * 26
        w.vy += a * dt
        w.dy = math.clamp(w.dy + w.vy * dt, -trv * 1.2, trv * 1.2)
        w.spin -= v.speed * dt / (w.rad or w.r)
        sum += w.dy
        if w.z < 0 then sF += w.dy nF += 1 else sB += w.dy nB += 1 end
        if w.x < 0 then sL += w.dy nL += 1 else sR += w.dy nR += 1 end
      end
    end
    local n = math.max(1, #W)
    local wb = math.max(4, (W[#W] and math.abs(W[#W].z - W[1].z)) or d.L * 0.7)
    local trk = math.max(3, d.W * 0.8)
    -- 车体：跟着轮子上下、俯仰、侧倾（弹簧）；起步抬头、刹车点头
    local tBob = sum / n * 0.55
    local tPitch = ((nF > 0 and sF / nF or 0) - (nB > 0 and sB / nB or 0)) / wb * 0.7 + math.clamp((v.accel or 0) * 0.0016, -0.035, 0.035)
    local tRoll = ((nR > 0 and sR / nR or 0) - (nL > 0 and sL / nL or 0)) / trk * 0.7 + math.clamp(v.steer * v.speed * 0.0006, -0.04, 0.04)
    v.bobV += ((tBob - v.bob) * 160 - v.bobV * 14) * dt
    v.bob += v.bobV * dt
    v.pitchV += ((tPitch - v.pitch) * 120 - v.pitchV * 12) * dt
    v.pitch += v.pitchV * dt
    v.rollV += ((tRoll - v.roll) * 120 - v.rollV * 12) * dt
    v.roll += v.rollV * dt
    local hh = d.hullH
    local hullF = base * CF(0, v.bob, 0) * CF(0, hh / 2, 0) * CFrame.Angles(v.pitch, 0, v.roll) * CF(0, -hh / 2, 0)
    local tF = hullF * CF(M.tpiv or d.turret.pivot) * CFrame.Angles(0, -math.rad(v.ty), 0)
    local gF = tF * CF(M.gpiv or d.gun.pivot) * CFrame.Angles(math.rad(v.gp), 0, 0) * CF(0, 0, v.recoil)
    v.hullF, v.tF, v.gF = hullF, tF, gF
    local steerA = math.rad(28) * math.clamp(v.steer, -1, 1)
    local now = os.clock()
    local plist, clist = v.plist, v.clist
    for i, it in ipairs(M.parts) do
      local grp, off = it[2], it[3]
      local cf
      if grp == "hull" then cf = hullF * off
      elseif grp == "turret" then
        cf = tF * off
        if it[1]:GetAttribute("Radar") then cf = cf * CFrame.Angles(0, now * 3, 0) end
      elseif grp == "gun" then cf = gF * off
      elseif grp == "wheel" then
        local w = W[it[4]]
        local wcf = base * CF(w.x, w.r + w.dy, w.z)
        if w.steer then wcf = wcf * CFrame.Angles(0, -steerA, 0) end
        cf = wcf * CFrame.Angles(w.spin, 0, 0) * off
      elseif grp == "seg" then
        local w = W[it[4]]
        cf = base * CF(0, w.dy, 0) * off
      else cf = hullF * off end
      clist[i] = cf
    end
    workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged)
    v.anchor.CFrame = hullF * CF(0, d.H + 1, 0)
    -- 扬尘：在陆地上开得快才有
    local land = not onWater
    if v.fireLight then v.fireLight.Brightness = 2.2 + math.random() * 1.8 end
    -- 扬尘按脚下的地面：土路、沙地最浓，草地淡一半，石头上更淡（每 0.3 秒看一次地面）
    v.dustT = (v.dustT or 0) - dt
    if v.dustT <= 0 then
      v.dustT = 0.3
      local mat = land and Map.material(pos.X, pos.Z, Map.height(pos.X, pos.Z), Map.slope(pos.X, pos.Z)) or nil
      local k, col = 0.5, nil
      if mat == Enum.Material.Ground then k, col = 1, Color3.fromRGB(168, 142, 104)
      elseif mat == Enum.Material.Sand then k, col = 1, Color3.fromRGB(206, 190, 150)
      elseif mat == Enum.Material.Rock or mat == Enum.Material.Slate then k, col = 0.3, Color3.fromRGB(150, 146, 138)
      else k, col = 0.45, Color3.fromRGB(150, 140, 112) end
      v.dustK = k
      if col and v.dustCol ~= col then
        v.dustCol = col
        for _, pe in ipairs(M.dust) do pe.Color = ColorSequence.new(col) end
      end
    end
    local rate = land and math.clamp((math.abs(v.speed) - 5) * 1.6, 0, 60) * (v.dustK or 0.5) or 0
    for _, pe in ipairs(M.dust) do if math.abs(pe.Rate - rate) > 0.5 then pe.Rate = rate end end
    -- 被毁：烧
    if em:GetAttribute("Wreck") and not v.wrecked then
      v.wrecked = true
      M.fire.Rate, M.black.Rate = 30, 12
      if M.fire.Parent then   -- 夜里残骸的火光照亮周围（每帧闪一闪）
        local pl = Instance.new("PointLight")
        pl.Color, pl.Range, pl.Brightness, pl.Shadows = Color3.fromRGB(255, 140, 60), 28, 3, true
        pl.Parent = M.fire.Parent
        v.fireLight = pl
      end
      for _, it in ipairs(M.parts) do
        local part = it[1]
        if part:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
          for _, sa in ipairs(part:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
          pcall(function() part.TextureID = "" end)
          part.Color = Color3.fromRGB(40, 38, 36)
        elseif part:IsA("BasePart") then part.Color = part.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.65) end
      end
      for _, pe in ipairs(M.dust) do pe.Enabled = false end
    end
  end

  ---------------------------------------------------------------- 跟着实体文件夹

  local function watch(folder)
    for _, em in ipairs(folder:GetChildren()) do task.defer(add, em) end
    folder.ChildAdded:Connect(function(em) task.defer(add, em) end)
    folder.ChildRemoved:Connect(remove)
  end
  task.spawn(function()
    local f = workspace:WaitForChild("Ents", 60)
    if f then watch(f) end
  end)

  local cam = workspace.CurrentCamera
  -- 原模型是进服后陆续复制过来的：先用零件拼的样子建起来的，两秒看一次原模型齐了没有，齐了就重建（用户：很多飞机找不到建模）
  local function rebuild(em)
    local v = views[em]
    if not v then return end
    views[em] = nil
    if v.id then byId[v.id] = nil end
    if v.ext and v.ext.remove then G.try_(v.ext.remove, v) end
    if v.model then v.model:Destroy() end
    add(em)
  end
  local impT = 0
  local function checkImports(dt)
    impT += dt
    if impT < 2 then return end
    impT = 0
    local list = {}
    for em, v in pairs(views) do
      local ok = false
      if v.kind == "veh" then ok = v.M ~= nil and not v.M.imported and v.def ~= nil and VM.importedFor(v.def) ~= nil
      elseif v.ext and v.ext.importReady then ok = v.ext.importReady(v) == true end
      if ok and em.Parent then table.insert(list, em) end
    end
    for _, em in ipairs(list) do G.try_(rebuild, em) end
  end
  function G.stepView(dt)
    stepDying()
    G.try_(checkImports, dt)
    local myTeam = me:GetAttribute("Side")
    local camPos = cam.CFrame.Position
    for em, v in pairs(views) do
      if not em.Parent then
        remove(em)
      else
        local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
        if hp ~= v.hpSeen or mx ~= v.mxSeen then
          v.hpSeen, v.mxSeen = hp, mx
          v.fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, mx), 0, 1), 1)
          v.bb.Enabled = hp < mx and hp > 0
        end
        if v.kind == "veh" then
          G.try_(stepVeh, v, dt, camPos)
        elseif v.ext then
          G.try_(v.ext.step, v, dt, camPos)
        else
          local target = v.root.CFrame
          local moved = (target.Position - v.cf.Position).Magnitude
          v.cf = v.cf:Lerp(target, math.min(1, dt * 10))
          if v.kind == "lcac" and G.lcacUnderMine then   -- 自己正开着的这条气垫艇：按本地算的车底摆（不等服务器，和甲板上的车贴死）
            local mine = G.lcacUnderMine(em:GetAttribute("Carry"))
            if mine then v.cf = mine end
          end
          v.t += dt * math.clamp(moved * 2, 0, 12)
          for _, L in pairs(v.parts) do
            local off = L[2]
            if L[3] == "leg" then off = off * CFrame.Angles(math.sin(v.t * 1.2) * 0.7 * L[4], 0, 0)
            elseif L[3] == "ramp" and em:GetAttribute("Ramp") then off = off * CFrame.Angles(-1.3, 0, 0) end
            L[1].CFrame = v.cf * off
          end
        end
      end
    end
  end
  -- 一辆车出错不影响别的
  function G.try_(f, ...)
    local ok, err = pcall(f, ...)
    if not ok and G.showError then G.showError("local view: " .. tostring(err)) end
  end
end

return View
