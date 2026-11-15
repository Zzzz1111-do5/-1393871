-- 暗剑：登岛战——飞机、直升机（服务器）：部署（名额、挂载、出生点）、飞行同步（位置由开飞机的客户端算，服务器查速度、查撞地）、
--   航炮（扣着扳机按射速连发）、空空 / 空地导弹（比例导引、过载有限、近炸引信；热诱弹骗走红外弹）、炸弹（制导的往目标滑）、火箭巢、
--   跳伞（固定翼弹射、直升机高处跳伞）、没人开的飞机掉下来、撞地 / 坠海、落在自己的机场 / 甲板上补弹修理、运输直升机载人
--   出生点：攻方直升机在两栖攻击舰甲板、拿下的据点；攻方固定翼在航母（舰载机）、机场岛、或空中出发（从南边）；
--     守方直升机在营地、还在手里的据点；守方固定翼在主岛机场（据点 D 还在手里时）、或空中出发（从北边）
local RS = game:GetService("ReplicatedStorage")

local Air = {}

function Air.init(G)
  local Config, Map = G.Config, G.Map
  local AD = require(RS:WaitForChild("AirDefs"))
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock
  local CATS = Config.VehicleCats
  local AIRCATS = { heli = true, jet = true }
  local GRAV = AD.GRAV

  local aircraft = {}
  local pending = { atk = {}, def = {} }   -- 被毁的占着名额：[cat] = { 冷却到什么时候 }
  G.aircraft = aircraft

  ---------------------------------------------------------------- 地面（含甲板）

  -- (x, z) 处能落地的面多高：地形、甲板
  local function surface(x, z) return AD.ground(Map, x, z) end
  G.airSurface = surface

  ---------------------------------------------------------------- 名额

  local function used(team, cat)
    local n = 0
    for _, e in ipairs(aircraft) do if e.alive and e.team == team and e.vcat == cat then n += 1 end end
    local t = now()
    local list = pending[team][cat] or {}
    for i = #list, 1, -1 do if list[i] <= t then table.remove(list, i) else n += 1 end end
    pending[team][cat] = list
    return n
  end
  local function avail(team)
    local out = {}
    local tn = G.teamCount(team)
    for cat in pairs(AIRCATS) do
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
  -- 接到地面载具的名额、型号表上
  local vehAvail0, vehModels0 = G.vehAvail, G.vehModels
  function G.vehAvail(team)
    local out = vehAvail0 and vehAvail0(team) or {}
    for k, v in pairs(avail(team)) do out[k] = v end
    return out
  end
  function G.vehModels(team)
    local out = vehModels0 and vehModels0(team) or {}
    for _, cat in ipairs(Config.VehicleOrder) do
      if AIRCATS[cat] then
        for _, id in ipairs(Config.Vehicles[team][cat] or {}) do if AD.get(id) then table.insert(out, id) end end
      end
    end
    return out
  end

  ---------------------------------------------------------------- 出生点

  local function deckOf(kind)
    for _, d in ipairs(G.decks or {}) do if d.kind == kind then return d end end
    return nil
  end
  local function pointOk(team, id)
    local s = G.points and G.points[id]
    return s and s.owner == team and not (team == "def" and s.pressed)
  end
  -- 这一类飞机能在哪出生：{ id, kind, x, z, ok }
  local function airSpawns(P, cat)
    local out = {}
    local battle = G.round and G.round.phase == "battle"
    local prepOk = G.round and (G.round.phase == "battle" or G.round.phase == "prep")
    if P.team == "atk" then
      if cat == "heli" then
        local dk = deckOf("lhd")
        if dk then table.insert(out, { id = "air.lhd", kind = "lhd", x = dk.cf.Position.X, z = dk.cf.Position.Z, ok = prepOk }) end
        for _, p in ipairs(Map.POINTS) do
          if pointOk("atk", p.id) then table.insert(out, { id = "air.pt." .. p.id, kind = "pad", point = p.id, x = p.x, z = p.z, ok = true }) end
        end
      else
        local dk = deckOf("carrier")
        if dk then table.insert(out, { id = "air.cv", kind = "cv", x = dk.cf.Position.X, z = dk.cf.Position.Z, ok = prepOk, carrierOnly = true }) end
        table.insert(out, { id = "air.af2", kind = "runway", x = Map.AFIELD2.x, z = Map.AFIELD2.z, ok = prepOk })
        table.insert(out, { id = "air.in", kind = "airstart", x = 0, z = Map.R - 300, ok = battle })
        if pointOk("atk", "D") then table.insert(out, { id = "air.af", kind = "runway", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z, ok = true }) end
      end
    else
      if cat == "heli" then
        table.insert(out, { id = "air.camp", kind = "pad", x = Map.CAMP.x, z = Map.CAMP.z, ok = prepOk })
        for _, p in ipairs(Map.POINTS) do
          if pointOk("def", p.id) then table.insert(out, { id = "air.pt." .. p.id, kind = "pad", point = p.id, x = p.x, z = p.z, ok = true }) end
        end
      else
        table.insert(out, { id = "air.af", kind = "runway", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z, ok = pointOk("def", "D") and prepOk })
        table.insert(out, { id = "air.in", kind = "airstart", x = 0, z = -Map.R + 300, ok = battle })
      end
    end
    return out
  end
  G.airSpawns = airSpawns

  -- 空着的停机位：离别的飞机够远
  local function freeSpot(list, r)
    for _, p in ipairs(list) do
      local ok = true
      for _, e in ipairs(aircraft) do
        if e.alive and (e.root.CFrame.Position - p).Magnitude < r then ok = false break end
      end
      if ok then return p end
    end
    return list[math.random(1, #list)]
  end
  -- 出生的 CFrame（机身中心）和初速度、是否在地上
  local function spawnCF(P, d, sp)
    local yaw = (P.team == "def") and V(0, 0, 1) or V(0, 0, -1)
    if sp.kind == "airstart" then
      local x = (math.random() - 0.5) * 2400
      local z = (P.team == "def") and (-Map.R + 350) or (Map.R - 350)
      local y = math.max(surface(x, z), 0) + ((d.kind == "heli") and 260 or 700)
      local p = V(x, y, z)
      return CFrame.lookAt(p, p + yaw), yaw * ((d.kind == "heli") and d.vMax * 0.6 or d.vMil * 0.8), false
    end
    if sp.kind == "lhd" or sp.kind == "cv" then
      local dk = deckOf(sp.kind == "lhd" and "lhd" or "carrier")
      local spots = {}
      if sp.kind == "lhd" then
        for k = -2, 2 do table.insert(spots, (dk.cf * CF(-dk.W * 0.18, 0, k * 70)).Position) end
      else
        for k = 0, 3 do table.insert(spots, (dk.cf * CF(-dk.W * 0.22 + k * 9, 0, dk.L * 0.38 - k * 4)).Position) end
      end
      local p = freeSpot(spots, d.kind == "heli" and 40 or 30)
      p = V(p.X, surface(p.X, p.Z) + d.gearH, p.Z)
      return CFrame.lookAt(p, p + V(0, 0, -1)), V(), true
    end
    if sp.kind == "runway" then
      local A = (sp.id == "air.af2") and Map.AFIELD2 or Map.AIRFIELD
      local dir = (A == Map.AFIELD2) and 1 or -1   -- 机场岛往东起飞，主岛机场往西
      local spots = {}
      for k = 0, 3 do table.insert(spots, V(A.x - dir * (A.len / 2 - 30 - k * 0), 0, A.z + (k - 1.5) * 10)) end
      local p = freeSpot(spots, 18)
      p = V(p.X, surface(p.X, p.Z) + d.gearH, p.Z)
      return CFrame.lookAt(p, p + V(dir, 0, 0)), V(), true
    end
    -- 直升机停机坪：营地 / 据点附近找一块平地
    local cx, cz = sp.x, sp.z
    for _ = 1, 40 do
      local a, r = math.random() * math.pi * 2, 50 + math.random() * 80
      local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
      if Map.isLand(x, z) and Map.slope(x, z) < 0.18 and (not G.spotClear or G.spotClear(x, z, d.W * 0.5 + 3, d.L * 0.5 + 3, d.H)) then
        local clear = true
        for _, e in ipairs(aircraft) do
          if e.alive and (e.root.CFrame.Position - V(x, e.root.CFrame.Position.Y, z)).Magnitude < 45 then clear = false break end
        end
        if clear then
          local p = V(x, surface(x, z) + d.gearH, z)
          return CFrame.lookAt(p, p + yaw), V(), true
        end
      end
    end
    local p = V(cx, surface(cx, cz) + d.gearH + 1, cz + 60)
    return CFrame.lookAt(p, p + yaw), V(), true
  end

  ---------------------------------------------------------------- 挂载（每个挂点剩几枚）

  local function storesStr(e)
    local s = {}
    for i, n in ipairs(e.stores) do s[i] = string.char(48 + math.clamp(n, 0, 40)) end   -- '0' 起（40 枚以内一个字符）
    return table.concat(s)
  end
  local function loadStr(e)
    local s = {}
    for i, w in ipairs(e.load) do s[i] = w or "" end
    return table.concat(s, ",")
  end
  local function fillStores(e)
    local d = e.def
    e.stores = {}
    for i, s in ipairs(d.st or {}) do
      local w = e.load[i]
      e.stores[i] = w and AD.count(s, w) or 0
    end
    e.gunAmmo = d.gunAmmo
    e.flares = d.flares
    e.model:SetAttribute("Stores", storesStr(e))
    e.model:SetAttribute("Flares", e.flares)
  end

  ---------------------------------------------------------------- 上下飞机

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
  local function seat(P, e, asPass)
    local char = P.char
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = true end
    hideChar(char, true)
    P.vehicle = e
    if asPass then
      table.insert(e.pass, P)
    else
      e.driver = P
      e.emptyAt = nil
      e.model:SetAttribute("Driver", P.pl.UserId)
    end
    char:PivotTo(e.root.CFrame)
    G.pushOne(P)
  end
  -- 下飞机：在地上走到机身旁边；在天上跳伞（固定翼是弹射座椅：往上弹出去）
  local function unseat(P, e, place)
    if P.vehicle == e then P.vehicle = nil end
    if e.driver == P then
      e.driver = nil
      e.emptyAt = now()
      e.trig = false
      e.model:SetAttribute("Driver", 0)
      e.model:SetAttribute("Fire", false)
    end
    for i, Q in ipairs(e.pass) do if Q == P then table.remove(e.pass, i) break end end
    local char = P.char
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      local cf = e.root.CFrame
      local p = cf.Position
      local agl = p.Y - math.max(surface(p.X, p.Z), 0) - e.def.gearH
      if hrp then hrp.Anchored = false end
      if agl > 25 then   -- 天上：跳伞
        local up = (e.def.kind == "jet") and 30 or 0
        local out = (e.def.kind == "jet") and (cf * CF(0, e.def.H * 0.5 + 8 + up, 0)).Position or (cf * CF(e.def.W * 0.5 + 6, -2, 0)).Position
        char:PivotTo(CFrame.lookAt(out, out + cf.LookVector))
        if hrp then hrp.AssemblyLinearVelocity = (e.vel or V()) * 0.25 + V(0, (e.def.kind == "jet") and 20 or 0, 0) end
        P.chute = now()
        char:SetAttribute("Chute", true)
        if e.def.kind == "jet" then G.fx({ k = "eject", p = (cf * CF(0, e.def.H * 0.4, e.def.canopy and e.def.canopy.z or 0)).Position, id = e.id }) end
      else
        local side = cf * CF(-(e.def.W * 0.5 + 5), 0, 0)
        local x, z = side.Position.X, side.Position.Z
        local y = math.max(surface(x, z), 0) + 3.5
        char:PivotTo(CFrame.lookAt(V(x, y, z), V(x, y, z) + V(cf.LookVector.X, 0, cf.LookVector.Z)))
      end
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 新飞机、被毁

  local function newAircraft(team, id, cf, P, load, vel, onGround)
    local d = AD.get(id)
    local hp = math.floor(d.hp * ((Config.VehicleMod[id] and Config.VehicleMod[id].hp) or 1))
    local e = G.newEnt({ kind = "air", team = team, cat = "air", hp = hp, size = d.hitbox, cf = cf, air = true, solid = false,
      extra = { def = d, vcat = d.cat } })
    e.model:SetAttribute("Model", id)
    e.model:SetAttribute("Driver", 0)
    e.load = AD.cleanLoad(d, load)
    e.model:SetAttribute("Load", loadStr(e))
    fillStores(e)
    e.vel = vel or V()
    e.onGround = onGround
    e.pass = {}
    e.lastSync = now()
    e.gunT = 0
    e.trig = false
    e.aim = nil
    e.bay = 0
    e.model:SetAttribute("Gear", onGround and 1 or 0)
    e.model:SetAttribute("Thr", onGround and 0 or 80)
    e.model:SetAttribute("Rpm", onGround and 0 or 100)
    e.onDeath = function(self, src)
      G.try("飞机被毁", function()
        self.alive = false
        self.wreck = true
        self.model:SetAttribute("Wreck", true)
        G.fx({ k = "boom", p = self.root.CFrame.Position, s = 2.6 })
        G.fx({ k = "airWreck", id = self.id, p = self.root.CFrame.Position, v = self.vel or V() })
        local list = pending[self.team][self.vcat] or {}
        table.insert(list, now() + (CATS[self.vcat].cd or 75))
        pending[self.team][self.vcat] = list
        local function kill(Q)
          Q.vehicle = nil
          if Q.char then
            hideChar(Q.char, false)
            G.hurtChar(Q.char, 1e5, src)
          end
          G.msg(Q.pl, "bad", "ui.vehLost")
        end
        local D = self.driver
        self.driver = nil
        if D then kill(D) end
        for _, Q in ipairs(self.pass) do kill(Q) end
        self.pass = {}
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = "veh." .. self.def.id }) end
        for i, x in ipairs(aircraft) do if x == self then table.remove(aircraft, i) break end end
      end)
      task.delay(4, function() G.removeEnt(self) end)
    end
    table.insert(aircraft, e)
    return e
  end

  ---------------------------------------------------------------- 部署

  local deployVeh0 = G.ACT.deployVeh
  G.ACT.deployVeh = function(P, id, spawnId, role, load)
    local d = AD.get(type(id) == "string" and id or "")
    if not d then
      if deployVeh0 then return deployVeh0(P, id, spawnId, role) end
      return
    end
    local R = G.round
    if not R or (R.phase ~= "battle" and R.phase ~= "prep") then return end
    if P.alive or now() < (P.canDeployAt or 0) then return end
    if not table.find(Config.Vehicles[P.team][d.cat] or {}, id) then return end
    local av = avail(P.team)[d.cat]
    if av.u >= av.cap then G.msg(P.pl, "bad", "ui.vehFull") return end
    local sp
    for _, s in ipairs(airSpawns(P, d.cat)) do if s.id == spawnId then sp = s end end
    if not sp or not sp.ok then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    if sp.carrierOnly and not d.carrier then G.msg(P.pl, "bad", "ui.notCarrier") return end
    if Config.RoleById[role] then P.role = role end
    P.role = P.role or "rifle"
    local cf, vel, ground = spawnCF(P, d, sp)
    local e = newAircraft(P.team, id, cf, P, (type(load) == "table") and load or AD.presetLoad(d), vel, ground)
    e.home = sp.kind
    P.spawnCF = cf
    P.after = function(Q) seat(Q, e) end
    P.canDeployAt = now() + 2
    P.spawnId = spawnId
    P.pl:LoadCharacter()
  end

  -- 上飞机：自己队的、离机身够近；有人开的运输直升机还有空座就坐后面
  local enter0 = G.ACT.enterVeh
  G.ACT.enterVeh = function(P, entId)
    local e = type(entId) == "string" and G.entById[entId] or nil
    if not e or not e.air then
      if enter0 then return enter0(P, entId) end
      return
    end
    if not e.alive or e.team ~= P.team or P.vehicle or not P.alive or not P.char then return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - e.root.CFrame.Position).Magnitude > math.max(e.def.L, e.def.W) * 0.5 + 18 then return end
    if not e.driver then seat(P, e) return end
    if e.def.transport and #e.pass < (e.def.seats or 1) then seat(P, e, true) end
  end

  ---------------------------------------------------------------- 武器

  local function src(P) return P and { P = P, team = P.team, name = P.pl.DisplayName } or nil end
  local function ignoreOf(e)
    local list = { e.model }
    if e.driver and e.driver.char then table.insert(list, e.driver.char) end
    for _, Q in ipairs(e.pass) do if Q.char then table.insert(list, Q.char) end end
    return list
  end
  local function turnToward(dir, want, maxA)
    local c = math.clamp(dir:Dot(want), -1, 1)
    local a = math.acos(c)
    if a <= maxA or a < 1e-4 then return want end
    local axis = dir:Cross(want)
    if axis.Magnitude < 1e-6 then axis = (math.abs(dir.Y) < 0.9) and dir:Cross(V(0, 1, 0)) or dir:Cross(V(1, 0, 0)) end
    return (CFrame.fromAxisAngle(axis.Unit, maxA) * dir).Unit
  end
  local function tgtPos(t)
    if not t then return nil end
    if t.decoy then return t.pos end
    if t.alive and t.root and t.root.Parent then return t.root.CFrame.Position end
    return nil
  end
  local function tgtVel(t)
    if t and t.decoy then return t.vel end
    return (t and t.vel) or V()
  end

  -- 导弹：助推到额定速度、之后慢慢减速；比例导引（带提前量）、过载有限；导引头看不到目标就丢失；近炸
  local function guideMissile(s, dt)
    s.age += dt
    local w = s.w
    local spd = s.vel.Magnitude
    if s.age < (w.burn or 3) then spd = math.min(w.speed, spd + w.speed * 1.4 * dt)
    else spd = math.max(w.speed * 0.3, spd - w.speed * 0.12 * dt) end
    local dir = s.vel.Unit
    local t = s.tgt
    if t and t.decoy then t.pos += t.vel * dt t.vel += V(0, -GRAV * 0.4, 0) * dt end
    local tp = tgtPos(t)
    if not tp then
      s.tgt, t = nil, nil
      tp = s.aimPt
    end
    if tp then
      local rel = tp - s.pos
      local dist = rel.Magnitude
      local tgo = dist / math.max(spd, 1)
      local lead = tp + tgtVel(t) * math.min(tgo, 4) * 0.95
      local want = (lead - s.pos).Unit
      if dir:Dot(want) < math.cos(math.rad(75)) and s.age > 0.6 then   -- 导引头看不到了：丢失目标，直飞
        s.tgt, s.aimPt = nil, nil
      else
        local k = (s.age < 0.25) and 0.4 or 1   -- 刚出架先稳一下
        dir = turnToward(dir, want, math.rad(w.turn) * dt * k)
      end
      local fuse = 8 + ((t and not t.decoy and t.root) and math.min(14, t.root.Size.Magnitude * 0.18) or 0)
      if dist < fuse then
        if t and t.decoy then G.fx({ k = "boom", p = s.pos, s = 0.6 }) return true end
        G.explode(s.pos, w, s.src)
        return true
      end
    end
    s.vel = dir * spd
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.3 then   -- 客户端画的弹按服务器的位置校一下
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end
  -- 炸弹：真实重力；制导炸弹算还要多久落地，往目标方向改水平速度（带翼的滑得远）
  local function guideBomb(s, dt)
    s.age += dt
    s.vel += V(0, -GRAV, 0) * dt
    s.vel = s.vel * (1 - 0.02 * dt)
    local tp = tgtPos(s.tgt) or s.aimPt
    if s.w.guided and tp and s.age > 0.4 then
      local h = s.pos.Y - tp.Y
      local vy = -s.vel.Y
      local tFall = (vy + math.sqrt(math.max(0, vy * vy + 2 * GRAV * math.max(h, 0)))) / GRAV
      tFall = math.max(tFall, 0.3)
      local need = V(tp.X - s.pos.X, 0, tp.Z - s.pos.Z) / tFall
      local cur = V(s.vel.X, 0, s.vel.Z)
      local auth = (s.w.shape and s.w.shape.wing) and 40 or 26
      local dv = need - cur
      if dv.Magnitude > auth * dt then dv = dv.Unit * auth * dt end
      s.vel += dv
    end
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.4 then
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end
  local function guideRocket(s, dt)
    s.age += dt
    s.vel += V(0, -GRAV * 0.25, 0) * dt
    return false
  end

  -- 挂点的世界位置
  local function stationWorld(e, s) return e.root.CFrame * CF(s.pos) end
  -- 选一个还有这种弹的挂点（左右交替）
  local function pickStation(e, wid)
    local d = e.def
    local best, bestN = nil, -1
    for i, s in ipairs(d.st or {}) do
      if e.load[i] == wid and e.stores[i] > 0 then
        -- 剩得最多的先用（左右轮流）；一样多的按顺序
        if e.stores[i] > bestN then best, bestN = i, e.stores[i] end
      end
    end
    return best
  end
  local function spend(e, i)
    e.stores[i] -= 1
    e.model:SetAttribute("Stores", storesStr(e))
  end

  -- 目标：客户端锁定的实体（服务器再看一眼：射程、导引头视场放宽一点）
  local function validTarget(e, w, tid)
    local t = (type(tid) == "string") and G.entById[tid] or nil
    if not t or not t.alive or t.team == e.team then return nil end
    local p0 = e.root.CFrame.Position
    local to = t.root.CFrame.Position - p0
    if to.Magnitude > w.range * 1.25 then return nil end
    if w.kind == "aam" and not t.air then return nil end
    if (w.kind == "agm" or w.kind == "bomb") and t.air then return nil end
    local fwd = e.root.CFrame.LookVector
    local cone = (w.kind == "bomb") and 75 or (w.cone * 1.6 + 6)
    if e.def.kind == "heli" and w.kind == "agm" then cone = cone + 20 end
    if w.kind ~= "bomb" and fwd:Dot(to.Unit) < math.cos(math.rad(cone)) then return nil end
    return t
  end

  local function fireStore(P, e, wid, tid, aim)
    local w = AD.W[type(wid) == "string" and wid or ""]
    if not w or w.kind == "gun" then return end
    if G.round.phase ~= "battle" then return end
    local t = now()
    if t < (e.nextStore or 0) then return end
    local i = pickStation(e, wid)
    if not i then return end
    local s = e.def.st[i]
    local scf = stationWorld(e, s)
    local fwd = e.root.CFrame.LookVector
    local S = src(P)
    local tgt = (w.kind == "aam" or w.kind == "agm" or w.kind == "bomb") and validTarget(e, w, tid) or nil
    local aimPt = (typeof(aim) == "Vector3" and aim.Magnitude < 1e6) and aim or nil
    local base = e.vel or V()
    if w.kind == "aam" or w.kind == "agm" then
      local launch = scf.Position - scf.UpVector * 1.2
      local sh = G.launch({ kind = "missile", pos = launch, vel = base + fwd * 60 - scf.UpVector * 6, w = w, src = S, ignore = ignoreOf(e), life = w.life or 8,
        step = guideMissile, age = 0, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = (not tgt and w.kind == "agm") and aimPt or nil, byEnt = e.id })
      e.nextStore = t + 0.35
      if tgt and tgt.driver then G.R.Drive:FireClient(tgt.driver.pl, { op = "rwr", id = sh.id, w = wid }) end
    elseif w.kind == "bomb" then
      G.launch({ kind = "bomb", pos = scf.Position - scf.UpVector * 1.5, vel = base - scf.UpVector * 4, w = w, src = S, ignore = ignoreOf(e), life = 30,
        step = guideBomb, age = 0, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = aimPt, byEnt = e.id })
      e.nextStore = t + ((e.def.bomber) and 0.12 or 0.25)
    elseif w.kind == "rkt" then
      local dir = (fwd + V((math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02, (math.random() - 0.5) * 0.02)).Unit
      G.launch({ kind = "rocket", pos = scf.Position + fwd * 3, vel = base + dir * w.speed, w = w, src = S, ignore = ignoreOf(e), life = w.range / w.speed + 1,
        step = guideRocket, age = 0, byEnt = e.id })
      e.nextStore = t + w.rate
    end
    spend(e, i)
    G.fx({ k = "storeOff", id = e.id, st = i, w = wid })
  end

  -- 航炮：扣着扳机，每 0.1 秒打一发弹丸（带这 0.1 秒所有炮弹的伤害）；机头炮塔 / 舱门机枪朝准星（有转动范围）
  local function gunDir(e, w)
    local cf = e.root.CFrame
    local fwd = cf.LookVector
    if (w.turret or w.door) and typeof(e.aim) == "Vector3" then
      local o = (cf * CF(e.def.gunPos or (e.def.door and V(e.def.door.x, e.def.door.y, e.def.door.z)) or V())).Position
      local want = (e.aim - o)
      if want.Magnitude > 1 then
        want = want.Unit
        local lim = w.door and 100 or 85
        if fwd:Dot(want) > math.cos(math.rad(lim)) or w.door then return want, o end
      end
      return fwd, o
    end
    return fwd, (cf * CF(e.def.gunPos or V(0, 0, -e.def.L * 0.45))).Position
  end
  local function stepGuns(dt)
    for _, e in ipairs(aircraft) do
      if e.alive and e.trig and e.driver and e.gunAmmo > 0 and G.round.phase == "battle" then
        local w = AD.W[e.def.gun or ""]
        if w then
          e.gunT += dt
          local nShots = math.min(e.gunAmmo, math.floor(e.gunT / w.rate))
          if nShots > 0 then
            e.gunT -= nShots * w.rate
            e.gunAmmo -= nShots
            local dir, o = gunDir(e, w)
            local spread = 0.006 + (w.door and 0.01 or 0)
            dir = (dir + V((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * spread * 2).Unit
            local ww = { dmg = w.dmg * nShots, splash = w.splash, vs = w.vs, id = w.id, fx = "agun" }
            G.launch({ kind = "shell", pos = o + dir * 2, vel = (e.vel or V()) + dir * w.speed, grav = true, gscale = 0.08, w = ww, src = src(e.driver), ignore = ignoreOf(e),
              life = w.range / w.speed + 0.2, byEnt = e.id })
          end
        end
      else
        e.gunT = 0
      end
    end
  end

  -- 热诱弹：一次一组 4 发；正在追这架飞机的红外弹六成被骗走，雷达弹一成五
  local function flare(P, e)
    local t = now()
    if e.flares <= 0 or t < (e.flareNext or 0) then return end
    e.flares = math.max(0, e.flares - 4)
    e.flareNext = t + 1.2
    e.model:SetAttribute("Flares", e.flares)
    local p = e.root.CFrame.Position
    G.fx({ k = "flares", id = e.id, p = p, v = e.vel or V() })
    for _, s in ipairs(G.shots) do
      if s.tgt == e and s.w and (s.w.kind == "aam") then
        local chance = (s.w.seeker == "ir") and 0.6 or 0.15
        if (s.pos - p).Magnitude < 2200 and math.random() < chance then
          s.tgt = { decoy = true, pos = p - (e.vel or V()) * 0.15, vel = (e.vel or V()) * 0.35 + V(0, -10, 0) }
          s.tgId = nil
          G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel, lost = true })
        end
      end
    end
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 飞行同步

  local function crash(e, why)
    if not e.alive then return end
    G.fx({ k = "boom", p = e.root.CFrame.Position, s = 2.8 })
    G.damageEnt(e, 1e6, e.lastHitBy or { team = "none", name = why or "crash" })
  end

  local function sync(P, e, d)
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dt = math.max(0.02, t - (e.lastSync or t))
    local p0, p1 = e.root.CFrame.Position, cf.Position
    local dist = (p1 - p0).Magnitude
    local def = e.def
    local maxD = def.vMax * 1.5 * dt + 25
    local bad = dist > maxD or p1.Y ~= p1.Y or math.abs(p1.X) > Map.R + 600 or math.abs(p1.Z) > Map.R + 600 or p1.Y > 4000
    e.lastSync = t
    if bad then
      G.R.Drive:FireClient(P.pl, { op = "fix", cf = e.root.CFrame, v = e.vel })
      return
    end
    local g = surface(p1.X, p1.Z)
    if p1.Y < math.max(g, -2) + def.gearH * 0.25 - 2 then   -- 机身插进地里 / 海里
      G.moveEnt(e, cf)
      crash(e, "ground")
      return
    end
    G.moveEnt(e, cf)
    if typeof(d.v) == "Vector3" and d.v.Magnitude < def.vMax * 1.6 then e.vel = d.v end
    e.onGround = d.gd == true
    if typeof(d.aim) == "Vector3" then e.aim = d.aim end
    local m = e.model
    local function q(name, v, k)
      if type(v) ~= "number" or v ~= v then return end
      v = math.floor(v * k + 0.5) / k
      if m:GetAttribute(name) ~= v then m:SetAttribute(name, v) end
    end
    q("Thr", d.thr, 1)          -- 油门 0～100（加力 100～130）
    q("Gear", d.gear, 10)       -- 起落架 0 收起～1 放下
    q("Flap", d.flap, 10)
    q("Pit", d.cp, 20)          -- 操纵：俯仰、滚转、偏航 −1～1
    q("Rol", d.cr, 20)
    q("Yaw", d.cy, 20)
    q("Bay", d.bay, 10)         -- 弹舱门 0～1
    q("Rpm", d.rpm, 1)          -- 旋翼转速 %
    q("Col", d.col, 20)         -- 总距
    q("Can", d.can, 10)         -- 座舱盖
    q("Hook", d.hook, 10)
    q("Brk", d.brk, 10)         -- 减速板
    q("Ty", d.ty, 2)            -- 机头炮塔：方位、俯仰（度）
    q("Gp", d.gp, 2)
    q("Fold", d.fold, 10)
  end

  local function landedHome(e)
    -- 停在自己的机场 / 甲板 / 停机坪附近：能补弹修理
    local p = e.root.CFrame.Position
    local function near(x, z, r) return (V(p.X, 0, p.Z) - V(x, 0, z)).Magnitude < r end
    if e.team == "atk" then
      local dk = deckOf("carrier")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      dk = deckOf("lhd")
      if dk and near(dk.cf.Position.X, dk.cf.Position.Z, dk.L * 0.5) then return true end
      if near(Map.AFIELD2.x, Map.AFIELD2.z, Map.AFIELD2.len * 0.6) then return true end
      if pointOk("atk", "D") and near(Map.AIRFIELD.x, Map.AIRFIELD.z, Map.AIRFIELD.len * 0.6) then return true end
    else
      if pointOk("def", "D") and near(Map.AIRFIELD.x, Map.AIRFIELD.z, Map.AIRFIELD.len * 0.6) then return true end
      if near(Map.CAMP.x, Map.CAMP.z, 220) then return true end
    end
    return false
  end

  function G.airInput(P, d)
    local e = P.vehicle
    if not e or not e.air or not e.alive or type(d) ~= "table" then return false end
    if e.driver ~= P then
      if d.op == "exit" then unseat(P, e, true) end
      return true
    end
    if d.op == "state" then sync(P, e, d)
    elseif d.op == "trig" then
      e.trig = d.on == true
      e.model:SetAttribute("Fire", e.trig)
      if typeof(d.aim) == "Vector3" then e.aim = d.aim end
    elseif d.op == "fire" then fireStore(P, e, d.w, d.tgt, d.aim)
    elseif d.op == "flare" then flare(P, e)
    elseif d.op == "crash" then
      local p = e.root.CFrame.Position
      if p.Y - math.max(surface(p.X, p.Z), 0) < e.def.H + 40 or d.hit then crash(e, "ground") end   -- 客户端说撞了：离地面 / 障碍物不远才认
    elseif d.op == "exit" then
      unseat(P, e, true)
    end
    return true
  end
  local driveInput0 = G.driveInput
  function G.driveInput(P, d)
    if P.vehicle and P.vehicle.air then
      G.airInput(P, d)
      return
    end
    if driveInput0 then driveInput0(P, d) end
  end

  -- 给客户端的：自己开的 / 坐的飞机
  local vehState0 = G.vehState
  function G.vehState(P)
    local e = P.vehicle
    if e and e.air then
      if not e.alive then return nil end
      return { id = e.id, m = e.def.id, air = true, pilot = e.driver == P, load = e.load, stores = e.stores, gun = e.gunAmmo, flares = e.flares, home = e.home,
        ground = e.onGround == true }
    end
    if vehState0 then return vehState0(P) end
    return nil
  end
  -- 部署界面：各类飞机的出生点
  G.airSpawnState = function(P)
    local out = {}
    for cat in pairs(AIRCATS) do out[cat] = airSpawns(P, cat) end
    return out
  end

  ---------------------------------------------------------------- 每帧：机组跟着飞机走；没人开的飞机掉下来；落地补弹

  local gunAcc = 0
  G.onFrame(function(dt)
    gunAcc += dt
    if gunAcc >= 0.1 then
      stepGuns(gunAcc)
      gunAcc = 0
    end
    local t = now()
    for _, e in ipairs(table.clone(aircraft)) do
      local D = e.driver
      if D and (not D.alive or not D.char or not D.char.Parent or G.P[D.pl] ~= D) then
        e.driver = nil
        e.emptyAt = t
        e.trig = false
        e.model:SetAttribute("Driver", 0)
        D = nil
      end
      for i = #e.pass, 1, -1 do
        local Q = e.pass[i]
        if not Q.alive or not Q.char or not Q.char.Parent or G.P[Q.pl] ~= Q then table.remove(e.pass, i) end
      end
      if D and D.char then D.char:PivotTo(e.root.CFrame) end
      for i, Q in ipairs(e.pass) do if Q.char then Q.char:PivotTo(e.root.CFrame * CF(((i % 2) * 2 - 1) * 2, 0, -2 + i * 2.5)) end end
      if e.alive and not D then
        local p = e.root.CFrame.Position
        local g = surface(p.X, p.Z)
        local agl = p.Y - math.max(g, 0) - e.def.gearH
        if agl > 3 and not e.onGround then   -- 没人开、在天上：往下掉，机头慢慢栽下去
          e.vel = (e.vel or V()) + V(0, -GRAV * 0.8, 0) * dt
          e.vel = e.vel * (1 - 0.15 * dt)
          local np = p + e.vel * dt
          local look = e.vel.Magnitude > 5 and e.vel.Unit or e.root.CFrame.LookVector
          G.moveEnt(e, CFrame.lookAt(np, np + look) * CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.4))
          if np.Y < math.max(surface(np.X, np.Z), -1) + 2 then crash(e, "ground") end
        elseif e.emptyAt and t - e.emptyAt > 90 then   -- 停着没人开 90 秒：收走（不算冷却）
          for i, x in ipairs(aircraft) do if x == e then table.remove(aircraft, i) break end end
          G.removeEnt(e)
        end
      end
      -- 落在自己的地方停稳：5 秒后补满弹药、热诱弹，慢慢修
      if e.alive and e.onGround and e.vel and e.vel.Magnitude < 4 and landedHome(e) then
        e.restT = (e.restT or 0) + dt
        if e.restT > 5 then
          if not e.rearmed then
            e.rearmed = true
            fillStores(e)
            if e.driver then
              G.msg(e.driver.pl, "good", "ui.rearmed")
              G.pushOne(e.driver)
            end
          end
          if e.hp < e.maxHp then
            e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.08 * dt)
            e.model:SetAttribute("Hp", math.floor(e.hp))
          end
        end
      else
        e.restT, e.rearmed = 0, false
      end
    end
  end)

  G.on("died", function(P)
    local e = P.vehicle
    if e and e.air then unseat(P, e, false) end
  end)
  G.on("left", function(P)
    local e = P.vehicle
    if e and e.air then unseat(P, e, false) end
  end)
  G.on("roundStart", function()
    for _, e in ipairs(aircraft) do G.removeEnt(e) end
    table.clear(aircraft)
    pending = { atk = {}, def = {} }
  end)
end

return Air
