-- 暗剑：登岛战——地面载具（坦克、装甲车、防空、火炮）：部署（名额、冷却）、开车（位置由开车的客户端算，服务器查速度、查下水）、
--   开火（主炮炮弹有弹道、并列机枪直射、榴弹炮 / 火箭炮曲射）、烟幕弹（从型号规定的发射筒打出去，落地起烟团，挡住机器人的视线）、
--   下车 / 上车、被毁（车组阵亡、残骸烧一会儿、这个名额冷却）
--   攻方的车从海上来：不会游的坐 726 气垫艇冲上选定的海滩，两栖的自己从海里开上来；守方的车在还在手里的据点车场、或后方营地
local RS = game:GetService("ReplicatedStorage")

local Armor = {}

function Armor.init(G)
  local Config, Map = G.Config, G.Map
  local VD = require(RS:WaitForChild("VehDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock
  local CATS = Config.VehicleCats
  local SM = VD.SMOKE
  local GROUND = { tank = true, apc = true, aa = true, arty = true }

  local vehicles = {}   -- 活着的载具实体
  local pending = { atk = {}, def = {} }   -- [cat] = { 冷却到什么时候, … }（被毁的车占着名额）
  G.vehicles = vehicles

  ---------------------------------------------------------------- 名额

  local function used(team, cat)
    local n = 0
    for _, e in ipairs(vehicles) do
      if e.alive and e.team == team and e.vcat == cat then n += 1 end
    end
    local t = now()
    local list = pending[team][cat] or {}
    for i = #list, 1, -1 do
      if list[i] <= t then table.remove(list, i) else n += 1 end
    end
    pending[team][cat] = list
    return n
  end
  -- 每类：在用、上限、要等多久（满了而且有在冷却的）
  function G.vehAvail(team)
    local out = {}
    local tn = G.teamCount(team)
    for cat in pairs(GROUND) do
      local cap = Config.VehicleCap(cat, tn)
      local u = used(team, cat)
      local cd = 0
      if u >= cap then
        local t, soon = now(), math.huge
        for _, x in ipairs(pending[team][cat] or {}) do soon = math.min(soon, x) end
        if soon < math.huge then cd = math.ceil(soon - t) end
      end
      out[cat] = { u = u, cap = cap, cd = cd }
    end
    return out
  end

  -- 这一队能开的型号（爱国者要等有飞机）
  function G.vehModels(team)
    local out = {}
    for _, cat in ipairs(Config.VehicleOrder) do
      if GROUND[cat] then
        for _, id in ipairs(Config.Vehicles[team][cat] or {}) do
          local d = VD.get(id)
          if d and not d.needsAir then table.insert(out, id) end
        end
      end
    end
    return out
  end

  ---------------------------------------------------------------- 摆车

  -- (x, z) 附近一块够平、够大的地（四个角高度差小）
  local function parkAt(x, z, r0, r1, d)
    for _ = 1, 30 do
      local a, r = math.random() * math.pi * 2, r0 + math.random() * (r1 - r0)
      local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
      local ok = true
      local hs = {}
      for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local h = Map.height(px + o[1] * d.W * 0.5, pz + o[2] * d.L * 0.5)
        if h < 0.6 then ok = false break end
        table.insert(hs, h)
      end
      if ok then
        local lo, hi = math.min(table.unpack(hs)), math.max(table.unpack(hs))
        if hi - lo < d.L * 0.18 then return px, pz end
      end
    end
    return x, z
  end
  -- 车底在 (x, z)、朝向 face 时的车底 CFrame（按四个角的地面高度定俯仰、侧倾）
  local function baseAt(d, x, z, face)
    face = V(face.X, 0, face.Z)
    if face.Magnitude < 0.01 then face = V(0, 0, -1) end
    face = face.Unit
    local right = V(-face.Z, 0, face.X)
    local function gh(p) return Map.ground(p.X, p.Z) end
    local c = V(x, 0, z)
    local f, b = c + face * d.L * 0.4, c - face * d.L * 0.4
    local l, r = c - right * d.W * 0.4, c + right * d.W * 0.4
    local yf, yb, yl, yr = gh(f), gh(b), gh(l), gh(r)
    local y = (yf + yb + yl + yr) / 4
    local fwd = (V(f.X, yf, f.Z) - V(b.X, yb, b.Z)).Unit
    local side = (V(r.X, yr, r.Z) - V(l.X, yl, l.Z)).Unit
    local up = side:Cross(fwd).Unit
    return CFrame.fromMatrix(V(x, y, z), side, up, -fwd)
  end
  G.vehBaseAt = baseAt
  local function rootFromBase(d, base) return base * CF(0, d.H / 2, 0) end
  local function baseOf(e) return e.root.CFrame * CF(0, -e.def.H / 2, 0) end
  G.vehBaseOf = baseOf

  ---------------------------------------------------------------- 车组（开车的人）

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

  local function seat(P, e)
    local char = P.char
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = true end
    hideChar(char, true)
    P.vehicle = e
    e.driver = P
    e.emptyAt = nil
    e.model:SetAttribute("Driver", P.pl.UserId)
    char:PivotTo(e.root.CFrame)
    G.pushOne(P)
  end

  local function unseat(P, e, place)
    if P.vehicle == e then P.vehicle = nil end
    if e.driver == P then
      e.driver = nil
      e.emptyAt = now()
      e.model:SetAttribute("Driver", 0)
    end
    local char = P.char
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      local base = baseOf(e)
      local side = base * CF(-(e.def.W / 2 + 4), 0, 0)
      local x, z = side.Position.X, side.Position.Z
      if hrp then hrp.Anchored = false end
      char:PivotTo(CFrame.lookAt(V(x, Map.ground(x, z) + 3.5, z), V(x, Map.ground(x, z) + 3.5, z) + base.LookVector))
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 新车、被毁

  local function newVehicle(team, id, base, P)
    local d = VD.get(id)
    local c = CATS[d.cat]
    local mod = Config.VehicleMod[id] or {}
    local hp = math.floor(c.hp * (mod.hp or 1))
    local e = G.newEnt({ kind = "veh", team = team, cat = c.tgt, hp = hp, size = V(d.W, d.H, d.L), cf = rootFromBase(d, base), solid = false,
      extra = { def = d, vcat = d.cat } })   -- 占领时不单算车：开车的人照常算一个
    e.model:SetAttribute("Model", id)
    e.model:SetAttribute("Ty", 0)
    e.model:SetAttribute("Gp", 0)
    e.model:SetAttribute("Driver", 0)
    e.ty, e.gp = 0, 0
    e.smokeLeft = SM.salvos
    e.smokeNext = 0
    e.wst = {}
    for _, wid in ipairs(d.weapons) do
      local w = VD.W[wid]
      e.wst[wid] = { mag = w.mag, reserve = w.reserve or 0, next = 0 }
    end
    e.lastSync = now()
    e.onDeath = function(self, src)
      G.try("载具被毁", function()
        self.alive = false
        self.wreck = true
        self.model:SetAttribute("Wreck", true)
        G.fx({ k = "boom", p = self.root.CFrame.Position, s = 2.4 })
        G.fx({ k = "wreck", id = self.id, p = self.root.CFrame.Position, life = 25 })
        local list = pending[self.team][self.vcat] or {}
        table.insert(list, now() + (CATS[self.vcat].cd or 60))
        pending[self.team][self.vcat] = list
        local D = self.driver
        if D then
          self.driver = nil
          D.vehicle = nil
          if D.char then
            hideChar(D.char, false)
            G.hurtChar(D.char, 1e5, src)
          end
          G.msg(D.pl, "bad", "ui.vehLost")
        end
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = "veh." .. self.def.id }) end
        for i, x in ipairs(vehicles) do
          if x == self then table.remove(vehicles, i) break end
        end
      end)
      task.delay(25, function() G.removeEnt(self) end)
    end
    table.insert(vehicles, e)
    return e
  end

  ---------------------------------------------------------------- 气垫艇（攻方不会游的车从海上送上滩）

  local lcacs = {}
  local LCAC = { start = 520, speed = 55, size = V(28, 6, 48), hp = 900 }
  local function lcacCF(b, dist)
    local p = V(b.cx, 2.2, b.z + b.dir * dist)
    return CFrame.lookAt(p, p + V(0, 0, -b.dir))
  end
  local function sendLcac(b, veh)
    local boat = G.newEnt({ kind = "lcac", team = "atk", cat = "ship", hp = LCAC.hp, size = LCAC.size, cf = lcacCF(b, LCAC.start), extra = { sea = true } })
    boat.beach, boat.dist, boat.veh, boat.state = b, LCAC.start, veh, "run"
    veh.locked = true
    veh.model:SetAttribute("Locked", true)
    boat.onDeath = function(self, src)
      if self.veh and self.veh.alive then G.damageEnt(self.veh, 1e6, src) end
      self.state = "sunk"
      task.delay(3, function() G.removeEnt(self) end)
    end
    table.insert(lcacs, boat)
  end
  local function stepLcacs(dt)
    for i = #lcacs, 1, -1 do
      local boat = lcacs[i]
      if not boat.alive then
        table.remove(lcacs, i)
      elseif boat.state == "run" then
        boat.dist = math.max(-30, boat.dist - LCAC.speed * dt)
        local cf = lcacCF(boat.beach, boat.dist)
        local bow = cf.Position + cf.LookVector * LCAC.size.Z * 0.5
        local veh = boat.veh
        if Map.height(bow.X, bow.Z) > 2.5 or boat.dist <= -30 then   -- 冲上滩：把车放下来
          boat.state = "landed"
          boat.backAt = now() + 8
          if veh and veh.alive then
            local d = veh.def
            local p = cf.Position + cf.LookVector * (LCAC.size.Z * 0.5 + d.L * 0.5 + 2)
            G.moveEnt(veh, rootFromBase(d, baseAt(d, p.X, p.Z, cf.LookVector)))
            veh.locked = false
            veh.model:SetAttribute("Locked", false)
            if veh.driver then G.R.Drive:FireClient(veh.driver.pl, { op = "fix", cf = veh.root.CFrame }) G.pushOne(veh.driver) end
          end
        elseif veh and veh.alive then
          G.moveEnt(veh, cf * CF(0, LCAC.size.Y / 2 + veh.def.H / 2 - 2.2, 2))
        end
        G.moveEnt(boat, cf)
      elseif boat.state == "landed" and now() >= boat.backAt then
        G.removeEnt(boat)
        table.remove(lcacs, i)
      end
    end
  end

  ---------------------------------------------------------------- 部署

  -- 载具能在哪出生：攻方——抢滩（战斗阶段）、拿下的据点；守方——营地、还在手里没被压住的据点
  local function vehSpawns(P)
    local out = {}
    for _, s in ipairs(G.spawnList(P.team, P)) do
      if s.kind == "beach" or s.kind == "point" or s.kind == "camp" then table.insert(out, s) end
    end
    return out
  end
  G.vehSpawns = vehSpawns

  function G.ACT.deployVeh(P, id, spawnId, role)
    local R = G.round
    if not R or (R.phase ~= "battle" and R.phase ~= "prep") then return end
    if P.alive or now() < (P.canDeployAt or 0) then return end
    local d = VD.get(type(id) == "string" and id or "")
    if not d or d.needsAir or not table.find(Config.Vehicles[P.team][d.cat] or {}, id) then return end
    local av = G.vehAvail(P.team)[d.cat]
    if av.u >= av.cap then G.msg(P.pl, "bad", "ui.vehFull") return end
    local sp = nil
    for _, s in ipairs(vehSpawns(P)) do if s.id == spawnId then sp = s end end
    if not sp or not sp.ok then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    if Config.RoleById[role] then P.role = role end
    P.role = P.role or "rifle"
    local e
    if sp.kind == "beach" then
      local b = Map.landingOf(sp.beach)
      if not b then return end
      if d.amphib then   -- 两栖：从离岸 300 格的海里自己开上来
        local z = b.z + b.dir * 300
        local face = V(0, 0, -b.dir)
        local base = CFrame.lookAt(V(b.cx + (math.random() - 0.5) * 60, -d.H * 0.35, z), V(b.cx, -d.H * 0.35, z) + face * 10)
        e = newVehicle(P.team, id, base, P)
      else
        local z = b.z + b.dir * LCAC.start
        e = newVehicle(P.team, id, CFrame.new(b.cx, 4, z), P)
        sendLcac(b, e)
      end
    else
      local x, z = sp.x, sp.z
      local face = (P.team == "def") and V(0, 0, 1) or V(0, 0, -1)
      local px, pz = parkAt(x, z, (sp.kind == "point") and 60 or 20, (sp.kind == "point") and 120 or 80, d)
      e = newVehicle(P.team, id, baseAt(d, px, pz, face), P)
    end
    P.spawnCF = e.root.CFrame
    P.after = function(Q, char) seat(Q, e) end
    P.canDeployAt = now() + 2
    P.spawnId = spawnId
    P.pl:LoadCharacter()
  end

  -- 上自己队的空车（离车 18 格以内）
  function G.ACT.enterVeh(P, entId)
    local e = type(entId) == "string" and G.entById[entId] or nil
    if not e or not e.alive or not e.def or e.driver or e.team ~= P.team or P.vehicle or not P.alive or not P.char then return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - e.root.CFrame.Position).Magnitude > e.def.L * 0.5 + 18 then return end
    seat(P, e)
  end

  ---------------------------------------------------------------- 开车、开火、烟幕弹（客户端发来的）

  local function src(P) return { P = P, team = P.team, name = P.pl.DisplayName } end
  local function spreadDir(dir, deg)
    if not deg or deg <= 0 then return dir end
    local s = math.rad(deg)
    return (dir + V((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)).Unit
  end

  local function sync(P, e, d)
    if e.locked then return end
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dt = math.max(0.02, t - (e.lastSync or t))
    local p0, p1 = e.root.CFrame.Position, cf.Position
    local flat = V(p1.X - p0.X, 0, p1.Z - p0.Z).Magnitude
    local maxD = e.def.speed * 1.5 * dt + 6
    local h = Map.height(p1.X, p1.Z)
    local bad = flat > maxD or p1.Y ~= p1.Y or math.abs(p1.Y - math.max(h, -e.def.H) - e.def.H / 2) > e.def.H * 1.5 + 6
    if not e.def.amphib and h < -3 then bad = true end
    if math.abs(p1.X) > Map.R or math.abs(p1.Z) > Map.R then bad = true end
    e.lastSync = t
    if bad then
      e.bad = (e.bad or 0) + 1
      G.R.Drive:FireClient(P.pl, { op = "fix", cf = e.root.CFrame })
      return
    end
    G.moveEnt(e, cf)
    local d0 = e.def
    if type(d.ty) == "number" and d.ty == d.ty then e.ty = d.ty % 360 end
    if type(d.gp) == "number" and d.gp == d.gp then e.gp = math.clamp(d.gp, d0.turret.elev[1], d0.turret.elev[2]) end
    e.model:SetAttribute("Ty", math.floor(e.ty * 2 + 0.5) / 2)
    e.model:SetAttribute("Gp", math.floor(e.gp * 2 + 0.5) / 2)
    if type(d.sp) == "number" then e.model:SetAttribute("Sp", math.floor(math.clamp(d.sp, -99, 99) + 0.5)) end
  end

  local function fire(P, e, wid, dir, aim)
    if G.round.phase ~= "battle" or e.locked then return end
    local d = e.def
    if type(wid) ~= "string" or not table.find(d.weapons, wid) then return end
    local w = VD.W[wid]
    local st = e.wst[wid]
    local t = now()
    if t < st.next then return end
    if st.mag <= 0 then
      if st.reserve <= 0 then return end
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
    end
    local base = baseOf(e)
    local mz = VD.muzzle(d, base, e.ty, e.gp, (w.kind == "gun" and d.coax) and "coax" or nil)
    local gdir = mz.LookVector
    if typeof(dir) == "Vector3" and dir.Magnitude > 0.5 and dir.Unit:Dot(gdir) > math.cos(math.rad(8)) then gdir = dir.Unit end
    local S = src(P)
    if w.kind == "shell" then
      G.launch({ kind = "shell", pos = mz.Position, vel = gdir * w.speed, grav = true, gscale = w.drop / 0.55, w = w, src = S, ignore = { e.model, P.char },
        life = w.range / w.speed + 0.5 })
      G.fx({ k = "vfire", p = mz.Position, d = gdir, f = w.fx, id = e.id })
    elseif w.kind == "gun" then
      G.botShot(mz.Position, mz.Position + spreadDir(gdir, w.spread) * w.range, w, S, { e.model, P.char }, 0)
    elseif w.kind == "arty" then
      if typeof(aim) ~= "Vector3" then return end
      local flat = V(aim.X - mz.Position.X, 0, aim.Z - mz.Position.Z)
      local dist = flat.Magnitude
      if dist < w.minR or dist > w.maxR then G.msg(P.pl, "bad", "ui.outOfRange") return end
      local sc = (w.scatter or 10) + dist * 0.01
      local a, r = math.random() * math.pi * 2, math.random() * sc
      local x, z = aim.X + math.cos(a) * r, aim.Z + math.sin(a) * r
      G.shell(V(x, Map.ground(x, z), z), w, S, w.flight + dist / 700, mz.Position)
      G.fx({ k = "vfire", p = mz.Position, d = gdir, f = "arty", id = e.id })
    end
    st.mag -= 1
    st.next = t + w.rate
    if st.mag <= 0 and st.reserve > 0 then   -- 弹匣打空：换弹
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
      st.next = t + math.max(w.rate, w.reload or 0)
    end
  end

  -- 烟幕：G.smokes = { { p, r, t0, t1 } }
  local smokes = {}
  G.smokes = smokes
  local function smokeR(s, t)
    if t >= s.t1 or t < s.t0 then return 0 end
    local grow = math.clamp((t - s.t0) / 2.5, 0.25, 1)
    local fade = math.clamp((s.t1 - t) / 6, 0, 1)
    return s.r * grow * (0.4 + 0.6 * fade)
  end
  -- 线段 a→b 有没有穿过烟团
  function G.smokeBlocks(a, b)
    if #smokes == 0 then return false end
    local t = now()
    local ab = b - a
    local L2 = ab:Dot(ab)
    for i = #smokes, 1, -1 do
      local s = smokes[i]
      if t >= s.t1 then
        table.remove(smokes, i)
      else
        local r = smokeR(s, t)
        if r > 0 then
          local k = (L2 > 0) and math.clamp((s.p - a):Dot(ab) / L2, 0, 1) or 0
          if (a + ab * k - s.p).Magnitude < r * 0.85 then return true end
        end
      end
    end
    return false
  end

  local function smoke(P, e)
    local t = now()
    if e.locked or e.smokeLeft <= 0 or t < e.smokeNext then return end
    e.smokeLeft -= 1
    e.smokeNext = t + SM.reload
    local tubes = VD.smokeTubes(e.def, baseOf(e), e.ty)
    local list = {}
    for _, tb in ipairs(tubes) do
      local flat = V(tb.dir.X, 0, tb.dir.Z)
      flat = (flat.Magnitude > 0.01) and flat.Unit or V(0, 0, -1)
      local L = SM.range * (0.85 + math.random() * 0.3)
      local x, z = tb.pos.X + flat.X * L, tb.pos.Z + flat.Z * L
      local y = math.max(Map.ground(x, z), 0) + 2.5
      table.insert(list, { a = tb.pos, b = V(x, y, z) })
    end
    G.fx({ k = "smokeLaunch", id = e.id, list = list })
    task.delay(0.9, function()
      for _, it in ipairs(list) do
        table.insert(smokes, { p = it.b, r = SM.r, t0 = now(), t1 = now() + SM.life })
        G.fx({ k = "smokeCloud", p = it.b, r = SM.r, life = SM.life })
      end
    end)
    G.pushOne(P)
  end

  function G.driveInput(P, d)
    local e = P.vehicle
    if not e or not e.alive or e.driver ~= P or type(d) ~= "table" then return end
    if d.op == "state" then sync(P, e, d)
    elseif d.op == "fire" then fire(P, e, d.w, d.dir, d.aim)
    elseif d.op == "smoke" then smoke(P, e)
    elseif d.op == "exit" then unseat(P, e, true) end
  end

  ---------------------------------------------------------------- 每帧：车组跟着车走；空车放久了收走

  G.onFrame(function(dt)
    stepLcacs(dt)
    local t = now()
    for _, e in ipairs(table.clone(vehicles)) do
      local D = e.driver
      if D then
        if not D.alive or not D.char or not D.char.Parent or G.P[D.pl] ~= D then
          e.driver = nil
          e.emptyAt = t
          e.model:SetAttribute("Driver", 0)
        else
          D.char:PivotTo(e.root.CFrame)
        end
      elseif e.alive and e.emptyAt and t - e.emptyAt > 90 then   -- 没人开 90 秒：收走（不算冷却）
        for i, x in ipairs(vehicles) do
          if x == e then table.remove(vehicles, i) break end
        end
        G.removeEnt(e)
      end
    end
  end)

  -- 给客户端的：自己的车（弹药、烟幕弹）、名额
  function G.vehState(P)
    local e = P.vehicle
    if not e or not e.alive then return nil end
    local ammo = {}
    for wid, st in pairs(e.wst) do ammo[wid] = { st.mag, st.reserve } end
    return { id = e.id, m = e.def.id, locked = e.locked or false, smoke = e.smokeLeft, ammo = ammo }
  end

  G.on("died", function(P)
    local e = P.vehicle
    if e then unseat(P, e, false) end
  end)
  G.on("left", function(P)
    local e = P.vehicle
    if e then unseat(P, e, false) end
  end)
  G.on("roundStart", function()
    for _, e in ipairs(vehicles) do G.removeEnt(e) end
    for _, b in ipairs(lcacs) do G.removeEnt(b) end
    vehicles, lcacs = {}, {}
    G.vehicles = vehicles
    pending = { atk = {}, def = {} }
    table.clear(smokes)
    for _, P in pairs(G.P) do P.vehicle = nil end
  end)
end

return Armor
