-- Roblox全面大战场——地图自带的工事和障碍（服务器）：每局开局时系统照 FortDefs 摆好，玩家不用自己部署
--   工事（实体，能被打掉）：机枪碉堡、岸防炮、高炮、M777 榴弹炮阵地。没人操作时 AI 打：找目标（看得见、在射界里）、转炮塔（有回转速度）、
--     开火（机枪点射；岸防炮按弹道带提前量，头一发试射、之后一发比一发准；高炮近炸引信；榴弹炮打攻方扎堆、正在占据点、被观察员标记的地方）
--   自己队的玩家走过去按 E 接手（AI 让出来）：鼠标瞄准、左键开火、F 离开；工事被打掉时操作的人阵亡
--   据点被攻方拿下后，挨着它的工事归攻方；一方的机器人盯着对方的工事看一会儿，就呼叫炮火打它
--   障碍：钢刺猬（挡车）、铁丝网（人走进去慢；车压过去、炸一下就断；工兵能剪）、雷区（只炸攻方；爆炸能引爆附近的雷；工兵能探出来、排掉）
local RS = game:GetService("ReplicatedStorage")

local Forts = {}

function Forts.init(G)
  local Config, Map = G.Config, G.Map
  local FD = require(RS:WaitForChild("FortDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local MAT = Enum.Material
  local now = os.clock
  local SC = Config.Score
  local SHELL_G = workspace.Gravity * 0.55   -- Ents 里炮弹用的重力

  local forts = {}
  G.forts = forts
  local layout, obst = nil, nil
  local built = false
  local defFolder, wireFolder
  local wires, mines = {}, {}
  local wireBox = nil   -- 全部铁丝网的范围（先粗查）
  local fields = {}     -- 每片雷区：{ x0, z0, x1, z1, list = { 雷… } }
  local strikeAt = { atk = 0, def = 0 }

  local function foeOf(team) return (team == "atk") and "def" or "atk" end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

  ---------------------------------------------------------------- 静态零件（钢刺猬、警示牌、工事周围的沙袋）

  local function part(parent, size, cf, color, mat, solid, shape)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Anchored = true
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = mat or MAT.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CanTouch = false
    if not solid then
      p.CanCollide, p.CanQuery = false, false
      if size.Magnitude < 8 then p.CastShadow = false end
    end
    p.Parent = parent
    return p
  end

  -- 钢刺猬：三根互相垂直的工字钢，体对角线竖着（三个尖着地、三个尖朝天），高约 4 格（1.4 米）
  local HOG_R = CFrame.fromAxisAngle(V(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))
  local function hedgehog(f, x, z, rot)
    local y = math.max(Map.height(x, z), -1.4)
    local cf = CF(x, y + 2.05, z) * CFrame.Angles(0, rot, 0) * HOG_R
    local col = RGB(84, 70, 60)
    part(f, V(6.4, 0.42, 0.42), cf, col, MAT.CorrodedMetal, true)
    part(f, V(0.42, 6.4, 0.42), cf, col, MAT.CorrodedMetal, true)
    part(f, V(0.42, 0.42, 6.4), cf, col, MAT.CorrodedMetal, true)
  end

  -- 雷区警示牌：木桩 + 红底白骷髅（图案不分语言）
  local function sign(f, x, z, face)
    local y = Map.ground(x, z)
    local base = CF(x, y, z) * CFrame.Angles(0, (face > 0) and math.pi or 0, 0)
    part(f, V(0.35, 4.2, 0.35), base * CF(0, 2.1, 0), RGB(110, 84, 58), MAT.Wood, false)
    local board = part(f, V(3.2, 2.2, 0.2), base * CF(0, 3.6, 0.25), RGB(196, 40, 36), MAT.SmoothPlastic, false)
    local sg = Instance.new("SurfaceGui")
    sg.Face = Enum.NormalId.Back
    sg.Parent = board
    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromScale(1, 1)
    t.BackgroundTransparency = 1
    t.Text = "☠"
    t.TextScaled = true
    t.TextColor3 = Color3.new(1, 1, 1)
    t.Parent = sg
  end

  -- 工事周围的沙袋：一圈（后面留出入口），挡子弹、挡车
  local function bagsAround(f, L)
    local d = FD.D[L.kind]
    local c = L.cf.Position
    local back = -L.cf.LookVector
    local ab = math.atan2(back.Z, back.X)
    if L.kind == "aaa" then
      G.World.sandbags(f, c, 10.5, ab + 0.55, ab + math.pi * 2 - 0.55, 3)
    elseif L.kind == "howitzer" then
      G.World.sandbags(f, c, 14, ab + 0.8, ab + math.pi * 2 - 0.8, 3.2)
    elseif L.kind == "bunker" then   -- 碉堡两侧各一段，护住后门
      G.World.sandbags(f, c, 11.5, ab + 0.35, ab + 1.25, 3)
      G.World.sandbags(f, c, 11.5, ab - 1.25, ab - 0.35, 3)
    end
    local _ = d
  end

  local function buildStatic()
    if built or not G.worldReady then return end
    built = true
    layout = FD.layout(Map)
    obst = FD.obstacles(Map)
    local root = workspace:FindFirstChild("Map") or workspace
    defFolder = Instance.new("Folder")
    defFolder.Name = "Defenses"
    defFolder.Parent = root
    wireFolder = Instance.new("Folder")
    wireFolder.Name = "Wire"
    wireFolder.Parent = root
    for _, h in ipairs(obst.hog) do G.try("钢刺猬", hedgehog, defFolder, h.x, h.z, h.rot) end
    for _, s in ipairs(obst.signs) do G.try("警示牌", sign, defFolder, s.x, s.z, s.face) end
    for _, L in ipairs(layout) do G.try("沙袋", bagsAround, defFolder, L) end
    -- 雷区范围
    for _, m in ipairs(obst.mines) do
      local F = fields[m.field]
      if not F then
        F = { x0 = 1e9, z0 = 1e9, x1 = -1e9, z1 = -1e9, list = {} }
        fields[m.field] = F
      end
      F.x0, F.z0, F.x1, F.z1 = math.min(F.x0, m.x), math.min(F.z0, m.z), math.max(F.x1, m.x), math.max(F.z1, m.z)
    end
    for _, W in ipairs(obst.wire) do
      local x0, x1 = math.min(W.a.X, W.b.X), math.max(W.a.X, W.b.X)
      local z0, z1 = math.min(W.a.Z, W.b.Z), math.max(W.a.Z, W.b.Z)
      if not wireBox then wireBox = { x0, z0, x1, z1 } else
        wireBox = { math.min(wireBox[1], x0), math.min(wireBox[2], z0), math.max(wireBox[3], x1), math.max(wireBox[4], z1) }
      end
    end
    if wireBox then wireBox = { wireBox[1] - 8, wireBox[2] - 8, wireBox[3] + 8, wireBox[4] + 8 } end
  end

  ---------------------------------------------------------------- 铁丝网、地雷（每局重新摆）

  -- 一段铁丝网：两头的桩、三道横丝、两道斜丝（零件不挡人，走进去由脚本减速）
  local function wireModel(i, W)
    local m = Instance.new("Model")
    m.Name = "Wire" .. i
    local ya, yb = Map.ground(W.a.X, W.a.Z), Map.ground(W.b.X, W.b.Z)
    local A, B = V(W.a.X, ya, W.a.Z), V(W.b.X, yb, W.b.Z)
    local post, wireC = RGB(96, 80, 60), RGB(58, 58, 56)
    for _, p in ipairs({ A, B }) do part(m, V(0.3, 3.4, 0.3), CF(p + V(0, 1.6, 0)), post, MAT.Wood, false) end
    local function strand(p0, p1)
      local mid = (p0 + p1) / 2
      local L = (p1 - p0).Magnitude
      if L < 0.5 then return end
      part(m, V(0.12, 0.12, L), CFrame.lookAt(mid, p1), wireC, MAT.Metal, false)
    end
    for _, h in ipairs({ 0.7, 1.6, 2.6 }) do strand(A + V(0, h, 0), B + V(0, h, 0)) end
    strand(A + V(0, 0.4, 0), B + V(0, 2.9, 0))
    strand(A + V(0, 2.9, 0), B + V(0, 0.4, 0))
    m:SetAttribute("WireKey", "w" .. i)
    m.Parent = wireFolder
    return m
  end

  local function resetObstacles()
    for _, W in ipairs(wires) do if W.model then W.model:Destroy() end end
    wires, mines = {}, {}
    if not obst then return end
    for i, W0 in ipairs(obst.wire) do
      local W = { a = W0.a, b = W0.b, alive = true, i = i }
      W.model = wireModel(i, W)
      wires[i] = W
    end
    for _, F in pairs(fields) do F.list = {} end
    for i, m0 in ipairs(obst.mines) do
      local m = { x = m0.x, z = m0.z, y = Map.ground(m0.x, m0.z), at = m0.at, alive = true, i = i, known = {} }
      mines[i] = m
      local F = fields[m0.field]
      if F then table.insert(F.list, m) end
    end
  end

  -- 点到一段铁丝网的水平距离
  local function segDist(x, z, W)
    local ax, az, bx, bz = W.a.X, W.a.Z, W.b.X, W.b.Z
    local dx, dz = bx - ax, bz - az
    local L2 = dx * dx + dz * dz
    local k = (L2 > 0) and math.clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1) or 0
    local px, pz = ax + dx * k - x, az + dz * k - z
    return math.sqrt(px * px + pz * pz)
  end
  local function inWire(x, z)
    if not wireBox or x < wireBox[1] or x > wireBox[3] or z < wireBox[2] or z > wireBox[4] then return false end
    for _, W in ipairs(wires) do
      if W.alive and segDist(x, z, W) < FD.WIRE.r then return true end
    end
    return false
  end
  -- 机器人走路的速度乘数（Bots.lua 调）
  function G.wireSlow(x, z) return inWire(x, z) and FD.WIRE.slow or 1 end

  local function cutWire(W, how)
    if not W.alive then return end
    W.alive = false
    local mid = (W.a + W.b) / 2
    if W.model then W.model:Destroy() W.model = nil end
    G.fx({ k = "wireCut", p = V(mid.X, Map.ground(mid.X, mid.Z) + 1, mid.Z), how = how })
  end

  local MINE_SRC = { team = "def", name = { k = "fort.mine" } }
  local function blowMine(m)
    if not m.alive then return end
    m.alive = false
    local w = m.at and FD.MINE.at or FD.MINE.ap
    G.explode(V(m.x, m.y + 0.5, m.z), w, MINE_SRC, m.at and 1.2 or 0.8)
  end

  -- 爆炸：炸断附近的铁丝网、引爆附近的雷（隔一小会儿，一串一串地炸）
  local explode0 = G.onExplode
  G.onExplode = function(pos, w, src)
    if explode0 then explode0(pos, w, src) end
    local r = (w and w.splash or 8)
    local rw = r * 0.6 + 3
    if wireBox and pos.X > wireBox[1] - rw and pos.X < wireBox[3] + rw and pos.Z > wireBox[2] - rw and pos.Z < wireBox[4] + rw then
      for _, W in ipairs(wires) do
        if W.alive and segDist(pos.X, pos.Z, W) < rw and math.abs(pos.Y - Map.ground(pos.X, pos.Z)) < 12 then cutWire(W, "boom") end
      end
    end
    local rc = FD.MINE.chain + r * 0.25
    for _, F in pairs(fields) do
      if pos.X > F.x0 - rc and pos.X < F.x1 + rc and pos.Z > F.z0 - rc and pos.Z < F.z1 + rc then
        for _, m in ipairs(F.list) do
          if m.alive and (V(m.x, m.y, m.z) - pos).Magnitude < rc then
            m.arming = true
            task.delay(0.15 + math.random() * 0.35, function() if m.alive then blowMine(m) end end)
          end
        end
      end
    end
  end

  -- 每步：攻方踩雷（防步兵雷人踩就炸，防坦克雷只有车压上去才炸）；车压坏铁丝网；人在铁丝网里走不快
  local function stepMines()
    -- 先收集一遍攻方在地上的人和车（每步一次），再按雷区的范围粗筛
    local units = {}
    for _, P in pairs(G.P) do
      if P.team == "atk" and P.alive and P.char and not P.vehicle then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp then table.insert(units, { x = hrp.Position.X, z = hrp.Position.Z, veh = false, r = 0 }) end
      end
    end
    for _, x in ipairs(G.ents) do
      if x.alive and x.team == "atk" and not x.air and not x.sea then
        local p = x.root.CFrame.Position
        if x.kind == "bot" then
          if not (x.bot and x.bot.state == "boat") then table.insert(units, { x = p.X, z = p.Z, veh = false, r = 0 }) end
        elseif (x.cat == "light" or x.cat == "armor") and not x.locked then
          table.insert(units, { x = p.X, z = p.Z, veh = true, r = math.max(x.root.Size.X, x.root.Size.Z) * 0.45 })
        end
      end
    end
    if #units == 0 then return end
    for _, F in pairs(fields) do
      local x0, z0, x1, z1 = F.x0 - 12, F.z0 - 12, F.x1 + 12, F.z1 + 12
      for _, u in ipairs(units) do
        if u.x > x0 and u.x < x1 and u.z > z0 and u.z < z1 then
          for _, m in ipairs(F.list) do
            if m.alive and not m.arming and (u.veh or not m.at) then
              local rr = (m.at and FD.MINE.at.trig or FD.MINE.ap.trig) + u.r
              local dx, dz = u.x - m.x, u.z - m.z
              if dx * dx + dz * dz < rr * rr then blowMine(m) end
            end
          end
        end
      end
    end
  end

  local wireT = 0
  local function stepWire(dt)
    wireT += dt
    if wireT < 0.25 then return end
    wireT = 0
    -- 车压过去：压坏
    for _, e in ipairs(G.vehicles or {}) do
      if e.alive and not e.locked then
        local p = e.root.CFrame.Position
        if wireBox and p.X > wireBox[1] and p.X < wireBox[3] and p.Z > wireBox[2] and p.Z < wireBox[4] then
          for _, W in ipairs(wires) do
            if W.alive and segDist(p.X, p.Z, W) < e.root.Size.X * 0.5 + 1.5 then cutWire(W, "crush") end
          end
        end
      end
    end
    -- 人：在铁丝网里走路慢
    for _, P in pairs(G.P) do
      local char = P.char
      local hum = char and char:FindFirstChildOfClass("Humanoid")
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hum and hrp and P.alive and not P.vehicle then
        local role = Config.RoleById[P.role] or Config.Roles[1]
        local inside = inWire(hrp.Position.X, hrp.Position.Z)
        if inside ~= (P.inWire == true) then
          P.inWire = inside
          hum.WalkSpeed = role.speed * (inside and FD.WIRE.slow or 1)
          if inside then G.msg(P.pl, "info", "ui.inWire") end
        end
      else
        P.inWire = nil
      end
    end
  end

  ---------------------------------------------------------------- 工事：上下（玩家接手）

  local function hideChar(char, on)
    for _, p in ipairs(char:GetDescendants()) do
      if p:IsA("BasePart") or p:IsA("Decal") then
        if on then
          if p:GetAttribute("T0") == nil then p:SetAttribute("T0", p.Transparency) end
          p.Transparency = 1
        else
          local t0 = p:GetAttribute("T0")
          if t0 ~= nil then p.Transparency = t0 p:SetAttribute("T0", nil) end
        end
      end
    end
  end

  local function manPoint(e) return (e.base * CF(FD.MAN[e.fkind])).Position end

  local function pushAngles(e, force)
    local t = now()
    if not force and t - (e.angT or 0) < 0.15 then return end
    local ty, gp = math.floor(e.ty + 0.5), math.floor(e.gp + 0.5)
    if ty ~= e.tyQ or gp ~= e.gpQ then
      e.tyQ, e.gpQ, e.angT = ty, gp, t
      e.model:SetAttribute("Ty", ty)
      e.model:SetAttribute("Gp", gp)
    end
  end

  local function man(P, e)
    if not e.alive or e.team ~= P.team or e.gunner or P.vehicle or not P.alive or not P.char then return false end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - manPoint(e)).Magnitude > 16 then return false end
    hrp.Anchored = true
    hideChar(P.char, true)
    P.vehicle = e
    e.gunner = P
    e.trig, e.tgt, e.mission = false, nil, nil
    local MG = FD.MAG[e.w.id]
    e.mag = MG and MG.mag or nil
    e.reloadAt = nil
    e.model:SetAttribute("Gunner", P.pl.UserId)
    P.char:PivotTo(CF(manPoint(e)))
    G.pushOne(P)
    return true
  end

  local function unman(e, place)
    local P = e.gunner
    if not P then return end
    e.gunner, e.trig = nil, false
    e.model:SetAttribute("Gunner", 0)
    if P.vehicle == e then P.vehicle = nil end
    local char = P.char
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      local mp = (e.base * CF(FD.MAN[e.fkind] + V(0, 0, 3))).Position
      local y = Map.ground(mp.X, mp.Z) + 3.5
      if hrp then hrp.Anchored = false end
      char:PivotTo(CFrame.lookAt(V(mp.X, y, mp.Z), V(mp.X, y, mp.Z) + e.base.LookVector))
    end
    if G.P[P.pl] == P then G.pushOne(P) end
  end

  ---------------------------------------------------------------- 开火

  local function srcOf(e)
    local P = e.gunner
    if P then return { P = P, team = e.team, name = P.pl.DisplayName } end
    return { team = e.team, name = { k = "fort." .. e.fkind } }
  end
  local function ignoreOf(e)
    local list = { e.model }
    if e.gunner and e.gunner.char then table.insert(list, e.gunner.char) end
    return list
  end
  local function spreadDir(dir, deg)
    if not deg or deg <= 0 then return dir end
    local s = math.rad(deg)
    return (dir + V((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)).Unit
  end
  local function muzzle(e) return FD.muzzle(e.fd, e.base, e.ty, e.gp) end
  local function gunDir(e) return FD.gunCF(e.fd, e.base, e.ty, e.gp).LookVector end

  local function fireGun(e, dir, deg)
    local w = e.w
    local mz = muzzle(e).Position
    return G.botShot(mz, mz + dir * w.range, w, srcOf(e), ignoreOf(e), deg)
  end

  local function fireShell(e, dir)
    local w = e.w
    local mz = muzzle(e).Position
    G.launch({ kind = "shell", pos = mz, vel = dir * w.speed, grav = true, gscale = w.gscale, w = w, src = srcOf(e), ignore = ignoreOf(e),
      life = w.range / w.speed * 1.8 + 1, byEnt = e.id })
    G.fx({ k = "vfire", p = mz, d = dir, f = "tank", id = e.id })
  end

  -- 高炮弹：近炸引信（离敌方飞机 fuse 格以内就炸），到时间也炸（空炸）
  local function flakStep(s, dt)
    s.age = (s.age or 0) + dt
    local p = s.pos
    local list = G.aircraft or G.ents
    for _, x in ipairs(list) do
      if x.alive and x.air and x.team ~= s.team then
        local r = s.w.fuse + x.root.Size.Magnitude * 0.12
        if (x.root.CFrame.Position - p).Magnitude < r then
          G.explode(p, s.w, s.src, 0.7)
          return true
        end
      end
    end
    if s.age >= (s.tfuse or 2) then
      G.explode(p, s.w, s.src, 0.6)
      return true
    end
    return false
  end
  local function fireFlak(e, dir, tfuse)
    local w = e.w
    local mz = muzzle(e).Position
    local d2 = spreadDir(dir, w.spread)
    G.launch({ kind = "shell", pos = mz, vel = d2 * w.speed, grav = true, gscale = w.gscale, w = w, src = srcOf(e), ignore = ignoreOf(e),
      life = w.range / w.speed + 0.5, step = flakStep, team = e.team, tfuse = tfuse or (w.range / w.speed), byEnt = e.id })
    G.fx({ k = "vfire", p = mz, d = dir, f = "ac", id = e.id })
  end

  -- 榴弹炮：落点散布随距离变大；返回 false 是超出射程
  local function fireHow(e, x, z)
    local w = e.w
    local mz = muzzle(e)
    local o = mz.Position
    local dist = V(x - o.X, 0, z - o.Z).Magnitude
    if dist < w.minR or dist > w.maxR then return false end
    local sc = (w.scatter or 12) + dist * 0.012
    local a, r = math.random() * math.pi * 2, math.random() * sc
    local tx, tz = x + math.cos(a) * r, z + math.sin(a) * r
    G.shell(V(tx, Map.ground(tx, tz), tz), w, srcOf(e), w.flight + dist / 700, o)
    G.fx({ k = "vfire", p = o, d = mz.LookVector, f = "arty", id = e.id })
    return true
  end

  ---------------------------------------------------------------- AI：找目标、瞄准

  local function pivotWorld(e) return (e.base * CF(e.fd.turret.pivot)).Position end
  -- 世界方向 → 相对工事正面的方位角（度，正数往右）、俯仰角（度）
  local function anglesOf(e, dir)
    local l = e.base:VectorToObjectSpace(dir)
    return math.deg(math.atan2(l.X, -l.Z)), math.deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)))
  end
  -- 转炮塔（有回转速度、射界、俯仰范围）；返回还差多少度
  local function slew(e, wy, wp, dt)
    local T = e.fd.turret
    local full = T.arc >= 180
    if not full then wy = math.clamp(wy, -T.arc, T.arc) end
    wp = math.clamp(wp, T.elev[1], T.elev[2])
    local dy = full and angDiff(e.ty, wy) or (wy - e.ty)
    local s = T.trav * dt
    e.ty += math.clamp(dy, -s, s)
    if full then e.ty = (e.ty + 180) % 360 - 180 end
    local ps = math.max(30, T.trav) * dt
    e.gp += math.clamp(wp - e.gp, -ps, ps)
    local ry = full and math.abs(angDiff(e.ty, wy)) or math.abs(wy - e.ty)
    return ry + math.abs(wp - e.gp)
  end

  -- 舰队附近（攻方出生的地方）不打：不然一出生就挨炮
  local function nearFleet(p)
    for _, d in ipairs(G.decks or {}) do
      local c = d.cf.Position
      if (V(p.X - c.X, 0, p.Z - c.Z)).Magnitude < d.L * 0.5 + 450 then return true end
    end
    return false
  end

  local function inArc(e, pos)
    local T = e.fd.turret
    local dir = pos - pivotWorld(e)
    local dist = dir.Magnitude
    if dist < 2 then return false, dist end
    local yaw, pitch = anglesOf(e, dir)
    if T.arc < 180 and math.abs(yaw) > T.arc + 2 then return false, dist end
    if pitch < T.elev[1] - 2 or pitch > T.elev[2] + 2 then return false, dist end
    return true, dist
  end

  -- 这处工事能打的敌人，按（距离 × 优先级）排好
  local function gather(e)
    local d = e.fd
    local Tg = d.targets
    local foe = foeOf(e.team)
    local o = pivotWorld(e)
    local R2 = d.sight * d.sight
    local cur = e.tgt and (e.tgt.P or e.tgt.ent)
    local out = {}
    local function consider(x, P, pos, pri)
      local dd = pos - o
      if dd.X * dd.X + dd.Y * dd.Y + dd.Z * dd.Z > R2 then return end
      local ok, dist = inArc(e, pos)
      if not ok or dist < (e.w.minR or 0) or nearFleet(pos) then return end
      local s = dist * pri
      if (P or x) == cur then s *= 0.75 end   -- 正在打的这个：别老换
      table.insert(out, { ent = x, P = P, pos = pos, d = dist, s = s })
    end
    if Tg.inf then
      for _, P in pairs(G.P) do
        if P.team == foe and P.alive and P.char and not P.vehicle then
          local hrp = P.char:FindFirstChild("HumanoidRootPart")
          local hum = P.char:FindFirstChildOfClass("Humanoid")
          if hrp and hum and hum.Health > 0 then consider(nil, P, hrp.Position, 1) end
        end
      end
    end
    for _, x in ipairs(G.ents) do
      if x.alive and x.team == foe and x ~= e then
        local pos = x.root.CFrame.Position
        if x.kind == "bot" then
          if Tg.inf and not (x.bot and x.bot.state == "boat") then consider(x, nil, pos, 1) end
        elseif x.air then
          if Tg.air and not x.onGround then
            local agl = pos.Y - math.max(Map.ground(pos.X, pos.Z), 0)
            if agl > 12 then consider(x, nil, pos, 1) end
          end
        elseif x.sea or x.cat == "ship" then
          if Tg.boat then consider(x, nil, pos, 0.8) end
        elseif x.cat == "light" or x.cat == "armor" then
          if Tg.boat and Map.height(pos.X, pos.Z) < -1 then consider(x, nil, pos, 0.9)
          elseif Tg.veh and (x.cat == "light" or e.fkind ~= "bunker") then consider(x, nil, pos, (e.fkind == "bunker") and 1.6 or 1.1) end
        end
      end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
  end

  local function canSee(e, pos, dist)
    local o = pivotWorld(e) + V(0, 0.8, 0)
    local step = math.clamp(dist / 40, 8, 40)
    if not Map.lineClear(o, pos + V(0, 1.2, 0), step) then return false end
    if G.smokeBlocks and G.smokeBlocks(o, pos) then return false end
    return true
  end

  local function think(e)
    local t = now()
    local pick, tries = nil, 0
    for _, c in ipairs(gather(e)) do
      local key = c.P or c.ent
      if not (e.blocked and e.blocked[key] and e.blocked[key] > t) then
        tries += 1
        if canSee(e, c.pos, c.d) then pick = c break end
        if tries >= 3 then break end
      end
    end
    local old = e.tgt and (e.tgt.P or e.tgt.ent)
    if pick and (pick.P or pick.ent) ~= old then
      e.fireAt = math.max(e.fireAt or 0, t + 0.5 + math.random() * 0.7)   -- 发现新目标：反应一下
      e.rangeErr = nil   -- 岸防炮：新目标重新试射
      e.tv, e.tlast, e.burst = V(), nil, nil
    end
    e.tgt = pick
  end

  local function targetPos(c)
    if c.P then
      local P = c.P
      if not P.alive or not P.char or P.vehicle then return nil end
      local hrp = P.char:FindFirstChild("HumanoidRootPart")
      return hrp and (hrp.Position + V(0, 0.4, 0)) or nil
    end
    local x = c.ent
    if not x or not x.alive then return nil end
    if x.kind == "bot" then
      if x.bot and x.bot.state == "boat" then return nil end
      return x.root.CFrame.Position + V(0, 0.6, 0)
    end
    return x.root.CFrame.Position
  end

  -- 低伸弹道：初速 v、重力 g，打到水平距离 R、高差 h 的仰角（弧度）；够不着返回 nil
  local function lowAngle(v, g, R, h)
    local v2 = v * v
    local disc = v2 * v2 - g * (g * R * R + 2 * h * v2)
    if disc < 0 or R < 1 then return nil end
    return math.atan((v2 - math.sqrt(disc)) / (g * R))
  end
  local function ballistic(o, tp, v, g)
    local rel = tp - o
    local flat = V(rel.X, 0, rel.Z)
    local R = flat.Magnitude
    local th = lowAngle(v, g, R, rel.Y)
    if not th then return nil end
    return flat.Unit * math.cos(th) + V(0, math.sin(th), 0), R / (v * math.cos(th))
  end
  -- 打活动目标的提前量（匀速直线）：返回方向、飞行时间
  local function intercept(o, tp, tv, s, g)
    local rel = tp - o
    local a = tv:Dot(tv) - s * s
    local b = 2 * rel:Dot(tv)
    local c = rel:Dot(rel)
    local t
    if math.abs(a) < 1e-6 then
      if math.abs(b) < 1e-6 then return nil end
      t = -c / b
    else
      local disc = b * b - 4 * a * c
      if disc < 0 then return nil end
      local sq = math.sqrt(disc)
      local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
      if t1 > 0 and t2 > 0 then t = math.min(t1, t2) else t = math.max(t1, t2) end
    end
    if not t or t <= 0 then return nil end
    local aim = tp + tv * t + V(0, 0.5 * g * t * t, 0)
    return (aim - o).Unit, t
  end

  -- 榴弹炮找打击目标：攻方扎堆、正在占守方据点、被观察员标记的地方；返回 x, z
  local function artyTarget(e)
    local foe = foeOf(e.team)
    local o = e.base.Position
    local w = e.w
    local units = {}
    for _, P in pairs(G.P) do
      if P.team == foe and P.alive and P.char and not (P.vehicle and (P.vehicle.air or P.vehicle.sea)) then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp then table.insert(units, hrp.Position) end
      end
    end
    for _, x in ipairs(G.ents) do
      if x.alive and x.team == foe and not x.air and not x.sea then
        if (x.kind == "bot" and not (x.bot and x.bot.state == "boat")) or x.cat == "light" or x.cat == "armor" then table.insert(units, x.root.CFrame.Position) end
      end
    end
    if #units == 0 then return nil end
    local marked = {}
    local S = G.spotted and G.spotted[e.team]
    if S then
      for key in pairs(S) do
        local x = G.entById[key]
        if x and x.alive then table.insert(marked, x.root.CFrame.Position) end
      end
    end
    local hot = {}
    for _, s in pairs(G.points or {}) do
      if s.owner == e.team and not s.locked and (s.prog or 0) > 0.1 then table.insert(hot, V(s.x, 0, s.z)) end
    end
    local best, bs = nil, 0
    local stride = math.max(1, math.floor(#units / 30))
    for i = 1, #units, stride do
      local c = units[i]
      local flat = V(c.X - o.X, 0, c.Z - o.Z)
      local dist = flat.Magnitude
      local yaw = anglesOf(e, flat)
      if dist >= w.minR + 20 and dist <= w.maxR - 20 and math.abs(yaw) <= e.fd.turret.arc and not nearFleet(c) then
        local n = 0
        for _, u in ipairs(units) do if (V(u.X - c.X, 0, u.Z - c.Z)).Magnitude < 32 then n += 1 end end
        for _, m in ipairs(marked) do if (V(m.X - c.X, 0, m.Z - c.Z)).Magnitude < 40 then n += 1.5 end end
        for _, h in ipairs(hot) do if (V(h.X - c.X, 0, h.Z - c.Z)).Magnitude < Map.POINT_R + 10 then n += 2 end end
        if n > bs then best, bs = c, n end
      end
    end
    if bs < 2.5 then return nil end
    return best
  end

  local function stepArtyAI(e, dt)
    local t = now()
    local w = e.w
    if G.round.phase ~= "battle" then
      e.mission = nil
      slew(e, 0, 18, dt * 0.3)
      return
    end
    if not e.mission then
      if t >= (e.thinkAt or 0) then
        e.thinkAt = t + 3 + math.random()
        if t >= (e.fireAt or 0) then
          local c = artyTarget(e)
          if c then e.mission = { x = c.X, z = c.Z, left = math.random(2, 3) } end
        end
      end
      slew(e, 0, 18, dt * 0.3)
      return
    end
    local M = e.mission
    local o = e.base.Position
    local flat = V(M.x - o.X, 0, M.z - o.Z)
    local wy = anglesOf(e, flat)
    local err = slew(e, wy, math.clamp(18 + flat.Magnitude / w.maxR * 45, 15, 65), dt)
    if err < 2 and t >= (e.fireAt or 0) then
      fireHow(e, M.x, M.z)
      M.left -= 1
      e.fireAt = t + w.rate + math.random() * 2
      if M.left <= 0 then
        e.mission = nil
        e.fireAt = t + 18 + math.random() * 8
      end
    end
  end

  local function stepAI(e, dt)
    if G.fortsHold then return end   -- 测试用：工事不开火
    local t = now()
    local w = e.w
    if w.kind == "arty" then stepArtyAI(e, dt) return end
    if t >= (e.thinkAt or 0) then
      e.thinkAt = t + 0.35 + math.random() * 0.15
      think(e)
    end
    local c = e.tgt
    local tp = c and targetPos(c)
    if not tp then
      e.tgt = nil
      slew(e, 0, (e.fkind == "aaa") and 25 or 0, dt * 0.35)
      return
    end
    -- 目标速度：飞机用它自己的，别的按位置变化估（平滑一下）
    local tv
    if c.ent and c.ent.vel then tv = c.ent.vel else
      if e.tlast then
        local raw = (tp - e.tlast) / math.max(dt, 0.02)
        if raw.Magnitude < 400 then e.tv = (e.tv or V()):Lerp(raw, 0.3) end
      end
      tv = e.tv or V()
    end
    e.tlast = tp
    local mz = muzzle(e).Position
    local dir, tol, tof
    if w.kind == "gun" then
      dir, tol = (tp - mz).Unit, 3
    elseif w.kind == "shell" then
      local aim = tp
      for _ = 1, 2 do
        local d1, tf = ballistic(mz, aim, w.speed, SHELL_G * w.gscale)
        if not d1 then break end
        tof = tf
        aim = tp + V(tv.X, 0, tv.Z) * tf
      end
      -- 试射修正：头一发偏差大（射程的 5%～8%），之后一发比一发准（在目标前后来回、越来越近）
      local R = (V(aim.X - mz.X, 0, aim.Z - mz.Z)).Magnitude
      if not e.rangeErr then e.rangeErr = R * (0.05 + math.random() * 0.03) * ((math.random() < 0.5) and -1 or 1) end
      local fwd = V(aim.X - mz.X, 0, aim.Z - mz.Z).Unit
      local side = V(-fwd.Z, 0, fwd.X)
      e.latErr = e.latErr or ((math.random() - 0.5) * R * 0.012)
      local aim2 = aim + fwd * e.rangeErr + side * e.latErr
      dir = ballistic(mz, aim2, w.speed, SHELL_G * w.gscale)
      tol = 1
    elseif w.kind == "flak" then
      local lead = 0.85 + math.random() * 0.2
      dir, tof = intercept(mz, tp, tv * lead, w.speed, SHELL_G * w.gscale)
      tol = 4
    end
    if not dir then return end
    local wy, wp = anglesOf(e, dir)
    local err = slew(e, wy, wp, dt)
    if err > tol or t < (e.fireAt or 0) or G.round.phase ~= "battle" then return end
    if w.kind == "gun" then
      e.burst = e.burst or math.random(w.burst[1], w.burst[2])
      local hit = fireGun(e, dir, w.spread + c.d * w.spreadPer)
      -- 连着几枪都打在墙上、房子上（不是目标、也不是别的实体）：多半被挡着，这个目标先不打
      local key = c.P or c.ent
      if hit and not G.entOf(hit) and not (c.P and c.P.char and hit:IsDescendantOf(c.P.char)) then
        e.miss = (e.miss or 0) + 1
        if e.miss >= 8 then
          e.miss = 0
          e.blocked = e.blocked or {}
          e.blocked[key] = t + 8
          e.tgt = nil
        end
      elseif hit then
        e.miss = 0
      end
      e.burst -= 1
      if e.burst <= 0 then
        e.burst = nil
        e.fireAt = t + w.pause[1] + math.random() * (w.pause[2] - w.pause[1])
      else
        e.fireAt = t + w.rate
      end
    elseif w.kind == "shell" then
      fireShell(e, dir)
      e.fireAt = t + w.rate + math.random() * 1.5
      e.rangeErr = e.rangeErr * -0.5   -- 下一发：打到另一边、偏差减半
      e.latErr = (e.latErr or 0) * 0.5
    elseif w.kind == "flak" then
      if c.d < w.range * 0.85 then
        fireFlak(e, dir, (tof or 1) + 0.05)
        e.fireAt = t + w.rate
      end
    end
  end

  ---------------------------------------------------------------- 玩家操作

  local function stepGunner(e, dt)
    local P = e.gunner
    if not P.alive or not P.char or not P.char.Parent or G.P[P.pl] ~= P then
      unman(e, false)
      return
    end
    pushAngles(e)
    local w = e.w
    if not e.trig or G.round.phase ~= "battle" or (w.kind ~= "gun" and w.kind ~= "flak") then
      e.shotAcc = w.rate
      return
    end
    local t = now()
    local MG = FD.MAG[w.id]
    if e.reloadAt then
      if t >= e.reloadAt then
        e.reloadAt = nil
        e.mag = MG.mag
        G.pushOne(P)
      end
      return
    end
    e.shotAcc = (e.shotAcc or w.rate) + dt
    local n = math.min(2, math.floor(e.shotAcc / w.rate))
    if n <= 0 then return end
    e.shotAcc -= n * w.rate
    for _ = 1, n do
      local dir = gunDir(e)
      if w.kind == "gun" then fireGun(e, dir, 0.45) else fireFlak(e, dir, nil) end
      e.mag -= 1
      if e.mag <= 0 then
        e.reloadAt = t + MG.reload
        G.pushOne(P)
        break
      end
    end
  end

  local function gunnerFire(P, e)
    if G.round.phase ~= "battle" then return end
    local w = e.w
    local t = now()
    if t < (e.fireAt or 0) then return end
    if w.kind == "shell" then
      fireShell(e, gunDir(e))
      e.fireAt = t + w.rate
    elseif w.kind == "arty" then
      local ap = e.aimPt
      if typeof(ap) ~= "Vector3" then return end
      if not fireHow(e, ap.X, ap.Z) then
        G.msg(P.pl, "bad", "ui.outOfRange")
        return
      end
      e.fireAt = t + w.rate
    else
      return
    end
    G.pushOne(P)
  end

  local function gunnerInput(P, e, d)
    if d.op == "aim" then
      local ty, gp = d.ty, d.gp
      if type(ty) == "number" and type(gp) == "number" and ty == ty and gp == gp then
        local T = e.fd.turret
        local full = T.arc >= 180
        if full then ty = (ty + 180) % 360 - 180 else ty = math.clamp(ty, -T.arc, T.arc) end
        gp = math.clamp(gp, T.elev[1], T.elev[2])
        local t = now()
        local dtt = math.clamp(t - (e.aimT or t), 0.03, 0.5)
        e.aimT = t
        local maxStep = T.trav * dtt * 1.6 + 4   -- 比规定的回转速度快一点也认（网络抖动）
        local dy = full and angDiff(e.ty, ty) or (ty - e.ty)
        e.ty += math.clamp(dy, -maxStep, maxStep)
        if full then e.ty = (e.ty + 180) % 360 - 180 end
        local ps = math.max(30, T.trav) * dtt * 1.6 + 4
        e.gp += math.clamp(gp - e.gp, -ps, ps)
        pushAngles(e)
      end
      if typeof(d.aim) == "Vector3" and d.aim.Magnitude < 1e6 then e.aimPt = d.aim end
    elseif d.op == "trig" then
      e.trig = d.on == true
    elseif d.op == "fire" then
      if typeof(d.aim) == "Vector3" and d.aim.Magnitude < 1e6 then e.aimPt = d.aim end
      gunnerFire(P, e)
    elseif d.op == "exit" then
      unman(e, true)
    end
  end

  ---------------------------------------------------------------- 新工事、被毁

  local function newFort(L)
    local d = FD.D[L.kind]
    local e = G.newEnt({ kind = "fort", team = "def", cat = "fort", hp = d.hp, size = d.size, cf = L.cf * CF(0, d.size.Y / 2, 0), solid = true,
      extra = { fort = true, fkind = L.kind, fd = d, w = FD.W[d.weapon], base = L.cf, pt = L.pt, tag = L.tag, ty = 0, gp = 0, home = "def" } })
    e.model:SetAttribute("Model", L.kind)
    e.model:SetAttribute("Ty", 0)
    e.model:SetAttribute("Gp", 0)
    e.model:SetAttribute("Gunner", 0)
    e.thinkAt = now() + math.random() * 0.5
    e.step = function(self, dt)
      if self.gunner then stepGunner(self, dt) else stepAI(self, dt) pushAngles(self) end
    end
    e.onDeath = function(self, src)
      G.try("工事被毁", function()
        self.wreck = true
        self.step = nil
        self.model:SetAttribute("Wreck", true)
        local P = self.gunner
        if P then
          unman(self, false)
          if P.char then
            hideChar(P.char, false)
            G.hurtChar(P.char, 1e5, src)
          end
          G.msg(P.pl, "bad", "ui.fortLost")
        end
        local K = src and src.P
        if K and G.P[K.pl] == K and K.team ~= self.team then
          G.addScore(K, SC.fortKill or 250)
          G.msg(K.pl, "kill", "ui.fortKilled", { k = "fort." .. self.fkind })
        end
        local kname = src and (src.P and src.P.pl.DisplayName or src.name)
        if kname then G.msgAll("feed", "ui.fortDown", kname, { k = "fort." .. self.fkind }) end
      end)
    end
    return e
  end

  ---------------------------------------------------------------- 一方的机器人看见对方的工事：呼叫炮火

  local function callStrike(e, team)
    local S = Config.Weapons.binoc.strike
    local p = e.root.CFrame.Position
    local src = { team = team, name = { k = "fort.strike" } }
    for i = 1, 5 do
      task.delay(1 + (i - 1) * 0.5, function()
        local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * 22
        local x, z = p.X + math.cos(a) * r, p.Z + math.sin(a) * r
        G.shell(V(x, Map.ground(x, z), z), S, src, S.flight)
      end)
    end
  end

  local function stepSpotting(e)
    local foe = foeOf(e.team)
    local top = e.root.CFrame.Position + V(0, e.fd.size.Y * 0.5, 0)
    local near = {}
    for _, x in ipairs(G.ents) do
      if x.kind == "bot" and x.alive and x.team == foe and not (x.bot and x.bot.state == "boat") then
        local dd = (x.root.CFrame.Position - top).Magnitude
        if dd < 650 and dd > 30 then table.insert(near, { x = x, d = dd }) end
      end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local seen = false
    for i = 1, math.min(3, #near) do
      if Map.lineClear(near[i].x.root.CFrame.Position + V(0, 2, 0), top, 12) then seen = true break end
    end
    if seen then e.seenT = (e.seenT or 0) + 1 else e.seenT = math.max(0, (e.seenT or 0) - 0.5) end
    local t = now()
    if e.seenT >= 6 and t >= (e.strikeAt or 0) and t >= (strikeAt[foe] or 0) then
      e.seenT = 0
      e.strikeAt = t + 50
      strikeAt[foe] = t + 22
      callStrike(e, foe)
    end
  end

  ---------------------------------------------------------------- 工兵：破障器材（探雷、排雷、剪铁丝网）

  local function thingOf(key)
    if type(key) ~= "string" then return nil end
    local kind, n = string.match(key, "^(%a)(%d+)$")
    n = tonumber(n)
    if not n then return nil end
    if kind == "m" then
      local m = mines[n]
      if m and m.alive then return m, V(m.x, m.y, m.z), "mine" end
    elseif kind == "w" then
      local W = wires[n]
      if W and W.alive then return W, (W.a + W.b) / 2, "wire" end
    end
    return nil
  end
  G.toolKind = G.toolKind or {}
  G.toolKind.breach = function(P, id, w, char, head, tool, op, key)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local t = now()
    local hp = hrp.Position
    if op == "scan" then
      if t < (P.cd.scan or 0) then return end
      P.cd.scan = t + 0.4
      local list = {}
      for i, m in ipairs(mines) do
        if m.alive then
          local dx, dz = m.x - hp.X, m.z - hp.Z
          if dx * dx + dz * dz < w.detect * w.detect then
            m.known[P.team] = true
            table.insert(list, { k = "m" .. i, p = V(m.x, m.y, m.z), at = m.at })
          end
        end
      end
      G.R.Fx:FireClient(P.pl, { { k = "mines", list = list, mine = true } })
      return
    end
    if op ~= "start" and op ~= "done" then return end
    local thing, pos, kind = thingOf(key)
    if not thing then return end
    local dist = (kind == "wire") and segDist(hp.X, hp.Z, thing) or (V(pos.X, 0, pos.Z) - V(hp.X, 0, hp.Z)).Magnitude
    if dist > w.range + 2 then return end
    if op == "start" then
      P.breach = { key = key, t = t }
      return
    end
    local b = P.breach
    if not b or b.key ~= key or t - b.t < w.time * 0.8 then return end
    P.breach = nil
    if kind == "mine" then
      thing.alive = false
      G.addScore(P, SC.defuse or 30)
      G.msg(P.pl, "good", "ui.defused")
      G.fx({ k = "defuse", p = pos })
    else
      cutWire(thing, "cut")
      G.addScore(P, SC.wireCut or 15)
      G.msg(P.pl, "good", "ui.wireCut")
    end
  end

  -- 每 2 秒：本队工兵探出来的雷发给全队（离自己 300 格以内的）
  local knownT = 0
  local function pushKnown(dt)
    knownT += dt
    if knownT < 2 then return end
    knownT = 0
    for pl, P in pairs(G.P) do
      local hrp = P.alive and P.char and P.char:FindFirstChild("HumanoidRootPart")
      if hrp then
        local list = {}
        for i, m in ipairs(mines) do
          if m.alive and m.known[P.team] then
            local dx, dz = m.x - hrp.Position.X, m.z - hrp.Position.Z
            if dx * dx + dz * dz < 300 * 300 then table.insert(list, { k = "m" .. i, p = V(m.x, m.y, m.z), at = m.at }) end
          end
        end
        if #list > 0 or P.hadKnown then
          P.hadKnown = #list > 0
          G.R.Fx:FireClient(pl, { { k = "mines", list = list, known = true } })
        end
      end
    end
  end

  ---------------------------------------------------------------- 找地方（停车、直升机停机坪、出生）时避开工事、钢刺猬、房子、帐篷、沙袋

  local clearParams = RaycastParams.new()
  clearParams.FilterType = Enum.RaycastFilterType.Include
  -- (x, z) 这一块（半宽 hx、半长 hz、高 h）空不空
  function G.spotClear(x, z, hx, hz, h)
    local r = math.max(hx, hz)
    for _, L in ipairs(layout or {}) do
      local p = L.cf.Position
      local d = FD.D[L.kind]
      local rr = math.max(d.size.X, d.size.Z) * 0.5 + 6 + r
      if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < rr * rr then return false end
    end
    for _, hg in ipairs(obst and obst.hog or {}) do
      if (hg.x - x) ^ 2 + (hg.z - z) ^ 2 < (r + 3) ^ 2 then return false end
    end
    local mapF = workspace:FindFirstChild("Map")
    if not mapF then return true end
    clearParams.FilterDescendantsInstances = { mapF }
    local y = Map.ground(x, z)
    local lines = { { -hx, -hz, hx, hz }, { hx, -hz, -hx, hz }, { -hx, 0, hx, 0 }, { 0, -hz, 0, hz } }
    for _, hy in ipairs({ 1.5, math.max(2.5, (h or 5) * 0.6) }) do
      for _, l in ipairs(lines) do
        local a = V(x + l[1], y + hy, z + l[2])
        if workspace:Raycast(a, V(l[3] - l[1], 0, l[4] - l[2]), clearParams) then return false end
      end
    end
    return true
  end

  ---------------------------------------------------------------- 接到上车、开车、状态上

  local enter0 = G.ACT.enterVeh
  G.ACT.enterVeh = function(P, entId)
    local e = (type(entId) == "string") and G.entById[entId] or nil
    if e and e.fort then
      if man(P, e) then G.msg(P.pl, "info", "ui.manned", { k = "fort." .. e.fkind }) end
      return
    end
    if enter0 then return enter0(P, entId) end
  end

  local driveInput0 = G.driveInput
  function G.driveInput(P, d)
    local e = P.vehicle
    if e and e.fort then
      if e.gunner == P and e.alive then gunnerInput(P, e, d) end
      return
    end
    if driveInput0 then driveInput0(P, d) end
  end

  local vehState0 = G.vehState
  function G.vehState(P)
    local e = P.vehicle
    if e and e.fort then
      if not e.alive or e.gunner ~= P then return nil end
      local MG = FD.MAG[e.w.id]
      local t = now()
      return { id = e.id, fort = e.fkind, m = e.fkind, w = e.w.id, mag = e.mag, magMax = MG and MG.mag or nil,
        reload = e.reloadAt and math.max(0, e.reloadAt - t) or 0, next = math.max(0, (e.fireAt or 0) - t) }
    end
    if vehState0 then return vehState0(P) end
    return nil
  end

  local function dropGunner(P)
    for _, e in ipairs(forts) do
      if e.gunner == P then unman(e, false) end
    end
  end
  G.on("died", dropGunner)
  G.on("left", dropGunner)

  -- 据点被攻方拿下：挨着它的工事归攻方（还能用的）
  G.on("captured", function(s)
    for _, e in ipairs(forts) do
      if e.alive and e.pt == s.id and e.team ~= "atk" then
        if e.gunner then unman(e, true) end
        e.team = "atk"
        e.model:SetAttribute("Team", "atk")
        e.tgt, e.mission, e.blocked = nil, nil, nil
      end
    end
  end)

  G.on("roundStart", function()
    buildStatic()
    for _, e in ipairs(forts) do
      if e.gunner then unman(e, false) end
      G.removeEnt(e)
    end
    table.clear(forts)
    strikeAt = { atk = 0, def = 0 }
    if not layout then return end
    for _, L in ipairs(layout) do
      local ok, e = pcall(newFort, L)
      if ok and e then table.insert(forts, e) elseif not ok then G.reportError("工事 " .. L.kind, e) end
    end
    resetObstacles()
  end)

  ---------------------------------------------------------------- 每步（init.server.lua 的循环里调）

  local spotI = 0
  function G.fortsStep(dt)
    if not built then return end
    local battle = G.round and G.round.phase == "battle"
    if battle then stepMines() end
    stepWire(dt)
    pushKnown(dt)
    -- 机器人呼叫炮火：每步看几处工事（一秒轮一遍）
    if battle and #forts > 0 then
      local per = math.max(1, math.ceil(#forts * dt))
      for _ = 1, per do
        spotI = spotI % #forts + 1
        local e = forts[spotI]
        if e and e.alive then G.try("呼叫炮火", stepSpotting, e) end
      end
    end
  end

  -- 给测试用
  G.fortsDebug = { mines = function() return mines end, wires = function() return wires end, man = man, unman = unman, fields = fields }
end

return Forts
