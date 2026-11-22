-- Roblox全面大战场——AI 开的地面载具（用户：AI 会自己找载具开）
--   开战后每队最多 2 辆（Config.AIVeh 能改）：坦克三成二、步战车三成一，型号从本队能开的里挑；被毁 45 秒后再派
--   守方：营地车场的空车位出发 → 寻路（Nav 流场）去当前要守的据点（被攻的优先），在据点外 50～110 格找块平地停下当火力点
--   攻方：第二阶段起在攻击出发阵地出发；同一块陆地上有拿下的据点就从那里出发；都没有（第一阶段打前哨岛）就在登陆平台旁坐气垫艇，
--     直线冲到登陆场的海滩、上岸放下车（同玩家开的气垫艇），再寻路去据点
--   打：每 0.3 秒找射程内、看得见（地形、烟幕不挡）的敌人——车、工事用主炮，步兵、机器人用并列机枪（没有机枪就主炮）；
--     炮塔按真实回转速度转过去、按距离抬高炮口（炮弹有落差），对准了才打；新目标先瞄 1～2 秒；有目标时放慢开
--   撤：血掉到三成五以下、或者主炮打光了，往出发的地方撤，撤到了就收走（不算被毁）；卡住了往旁边倒一下
--   车是 Armor 的实体（客户端照样画、炮塔按 Ty / Gp 转、车轮按 Sp 转），Driver 属性 −1：没有「E 上车」、不算「可驾驶」，也不占玩家的名额
local RS = game:GetService("ReplicatedStorage")

local AIVeh = {}

function AIVeh.init(G)
  local Config, Map = G.Config, G.Map
  local VD = require(RS:WaitForChild("VehDefs"))
  local V, CF = Vector3.new, CFrame.new
  local now = os.clock
  local A = Config.AIVeh or {}
  local MAX = A.max or 2           -- 每队同时几辆
  local REDO = A.redo or 45        -- 被毁 / 收走以后多久再派（秒）
  local RETREAT = A.retreat or 0.35
  local GUN_R, MG_R = A.gunRange or 1500, A.mgRange or 700   -- 交战距离（格）：主炮约 540 米、机枪约 250 米
  local list = {}
  G.aiVehicles = list
  local nextAt = { atk = 0, def = 0 }
  local serial = 0

  local function flat(v) return V(v.X, 0, v.Z) end
  local function angDiff(a, b) return (a - b + 180) % 360 - 180 end
  local function approach(x, to, d)
    if math.abs(to - x) <= d then return to end
    return x + ((to > x) and d or -d)
  end

  ---------------------------------------------------------------- 去哪

  -- 能去的据点：攻方打当前阶段还没拿下的（主攻，不去侧翼）；守方守自己手里的——当前阶段的，或者（当前阶段的不在这块陆地上，
  --   比如第一阶段的前哨岛）下一阶段的（纵深，先在那里等着）。land：车在哪块陆地上（车过不了海，只挑这块陆地上的）
  local function eligible(team, p, land)
    local s = G.points and G.points[p.id]
    if not s or s.locked or (land and p.land ~= land) or (G.flankOf and G.flankOf[p.id]) then return 0 end
    local active = not G.pointActive or G.pointActive(p.id)
    if team == "atk" then return (active and s.owner ~= "atk") and 2 or 0 end
    if s.owner ~= "def" then return 0 end
    if active then return 2 + (s.atk or 0) + (s.prog or 0) * 3 end
    return 0   -- 用户（交战区）：只去当前交战区
  end
  local function pickGoal(team, land)
    local best, bs = nil, 0
    for _, p in ipairs(Map.POINTS) do
      local sc = eligible(team, p, land)
      if sc > 0 then
        sc += math.random() * 0.2
        if sc > bs then best, bs = p, sc end
      end
    end
    return best
  end
  -- 据点外一圈找块能停车的平地（攻方停在自己来的那一侧）
  local function holdSpot(p, from)
    for _ = 1, 16 do
      local a = math.random() * math.pi * 2
      if from then   -- 朝着来的方向 ±60°
        local d = flat(from - V(p.x, 0, p.z))
        if d.Magnitude > 1 then a = math.atan2(d.Z, d.X) + (math.random() - 0.5) * math.rad(120) end
      end
      local r = 50 + math.random() * 60
      local x, z = p.x + math.cos(a) * r, p.z + math.sin(a) * r
      if Map.isLand(x, z) and Map.slope(x, z) < 0.35 and (not G.spotClear or G.spotClear(x, z, 7, 13, 8)) then return V(x, 0, z) end
    end
    return V(p.x, 0, p.z)
  end
  -- 离据点最近的登陆场（同一块陆地）
  local function landingFor(p)
    local best, bd = nil, 1e18
    for _, b in ipairs(Map.LANDINGS) do
      if (b.isle or "main") == p.land then
        local d = (b.cx - p.x) ^ 2 + (b.z - p.z) ^ 2
        if d < bd then best, bd = b, d end
      end
    end
    return best
  end

  ---------------------------------------------------------------- 派车

  local function pickModel(team)
    local V0 = Config.Vehicles[team] or {}
    local cat = (math.random() < 0.67) and "tank" or "apc"
    local ids = {}
    for _, id in ipairs(V0[cat] or {}) do
      local d = VD.get(id)
      if d and not d.needsAir and d.weapons and #d.weapons > 0 then table.insert(ids, id) end
    end
    if #ids == 0 then return nil end
    return ids[math.random(#ids)]
  end
  -- 车位上有没有车（玩家的、AI 的）
  local function clearAt(pos, r)
    for _, x in ipairs(G.vehicles or {}) do
      if x.alive and (flat(x.root.CFrame.Position) - flat(pos)).Magnitude < r then return false end
    end
    return true
  end
  local function landSpot(x, z, r)
    for _ = 1, 12 do
      local a, rr = math.random() * math.pi * 2, math.random() * r
      local px, pz = x + math.cos(a) * rr, z + math.sin(a) * rr
      if Map.isLand(px, pz) and Map.slope(px, pz) < 0.35 and not (Map.inHarbor and Map.inHarbor(px, pz, 10)) and clearAt(V(px, 0, pz), 16) then return px, pz end
    end
    return nil
  end

  local function setup(e, team, goal, home, state)
    serial += 1
    e.ai = { state = state, goal = goal.id, land = goal.land, home = home, hold = nil, tgt = nil, seekT = 0, aimT = 0, stuckT = 0, lastP = e.root.CFrame.Position,
      sideT = 0, holdT = 0, crew = { team = team, name = string.upper(e.def.id) .. "-" .. serial, k = 0, d = 0, s = 0, c = 0 } }
    e.emptyAt, e.resP = nil, nil
    e.model:SetAttribute("Driver", -1)   -- 有人开着：客户端不出「E 上车」、不标「可驾驶」
    e.model:SetAttribute("AI", true)
    table.insert(list, e)
    return e
  end

  local function spawn(team)
    local goal = pickGoal(team, nil)   -- 守方也不限陆地了：在目标后面的集结点出车（前哨岛 A 也守得到）
    if not goal then return nil end
    local id = pickModel(team)
    if not id then return nil end
    local d = VD.get(id)
    if team == "def" then
      -- 用户（出生点跟着战线走）：目标后面的集结点出车；那里有敌人（或找不到平地）才从营地车场出
      local rp = G.rallyOf and G.rallyOf(goal.id)
      if rp then
        local x, z = landSpot(rp.x, rp.z, 60)
        if x and Map.landOf(x, z) == goal.land then
          local e = G.newVehicle(team, id, G.vehBaseAt(d, x, z, V(goal.x - x, 0, goal.z - z)))
          return setup(e, team, goal, V(x, 0, z), "go")
        end
      end
      if goal.land ~= Map.landOf(Map.CAMP.x, Map.CAMP.z) then return nil end   -- 营地开不过去（在别的岛上）
      for _, p in ipairs(G.pads or {}) do
        if p.team == "def" and p.kind == "veh" and not p.sea and clearAt(p.base.Position, 16) then
          local face = p.base.LookVector
          local e = G.newVehicle(team, id, G.vehBaseAt(d, p.base.Position.X, p.base.Position.Z, face))
          return setup(e, team, goal, p.base.Position, "go")
        end
      end
      return nil
    end
    -- 攻方：攻击出发阵地（第二阶段起）
    local st = G.stagingOk and G.stagingOk(goal.id)
    if st then
      local x, z = landSpot(st.x, st.z, 60)
      if x then
        local e = G.newVehicle(team, id, G.vehBaseAt(d, x, z, V(goal.x - x, 0, goal.z - z)))
        return setup(e, team, goal, V(x, 0, z), "go")
      end
    end
    -- 同一块陆地上拿下的据点
    for _, p in ipairs(Map.POINTS) do
      local s = G.points and G.points[p.id]
      if s and s.owner == "atk" and p.land == goal.land and p.id ~= goal.id then
        local x, z = landSpot(p.x, p.z, 70)
        if x then
          local e = G.newVehicle(team, id, G.vehBaseAt(d, x, z, V(goal.x - x, 0, goal.z - z)))
          return setup(e, team, goal, V(x, 0, z), "go")
        end
      end
    end
    -- 沙漠图：南边前进基地的车场出车，自己开上去（没有气垫艇）
    if Map.LANDONLY then
      for _, p in ipairs(G.pads or {}) do
        if p.team == "atk" and p.kind == "veh" and not p.sea and clearAt(p.base.Position, 16) then
          local face = p.base.LookVector
          local e = G.newVehicle(team, id, G.vehBaseAt(d, p.base.Position.X, p.base.Position.Z, face))
          return setup(e, team, goal, p.base.Position, "go")
        end
      end
      return nil
    end
    -- 坐气垫艇冲滩：登陆平台旁的水面车位
    local LC = G.LCAC
    if not (LC and G.lcacCarry) then return nil end
    for _, p in ipairs(G.pads or {}) do
      if p.team == "atk" and p.kind == "veh" and p.sea and clearAt(p.base.Position, 20) then
        local c = p.base.Position
        local face = V(p.base.LookVector.X, 0, p.base.LookVector.Z).Unit
        local b = CFrame.lookAt(V(c.X, LC.deck, c.Z), V(c.X, LC.deck, c.Z) + face)
        local e = G.newVehicle(team, id, b)
        G.lcacCarry(e, b)
        local e2 = setup(e, team, goal, c, "boat")
        local lb = landingFor(goal)
        e2.ai.beach = lb and V(lb.cx + (math.random() - 0.5) * 120, 0, lb.z - (lb.dir or 1) * 60) or V(goal.x, 0, goal.z)
        return e2
      end
    end
    return nil
  end

  -- 收走（撤回去了、回合结束）：不算被毁
  local function remove(e)
    e.ai = nil
    if e.lcac then G.removeEnt(e.lcac) end
    for i, x in ipairs(G.vehicles or {}) do
      if x == e then table.remove(G.vehicles, i) break end
    end
    G.removeEnt(e)
  end

  ---------------------------------------------------------------- 开

  -- 车底朝 face 往前挪一步（转向有上限、急转弯慢下来）；返回挪了多远
  local function drive(e, goalPos, dt, speedK)
    local d = e.def
    local base = G.vehBaseOf(e)
    local p = base.Position
    local look = flat(base.LookVector)
    look = (look.Magnitude > 0.01) and look.Unit or V(0, 0, -1)
    local to = flat(goalPos - p)
    local dist = to.Magnitude
    if dist < 4 then e.model:SetAttribute("Sp", 0) return 0 end
    local want = to.Unit
    local ang = math.atan2(look:Cross(want).Y, look:Dot(want))
    local maxT = math.rad(d.turn or 36) * dt
    local nl = CFrame.Angles(0, math.clamp(ang, -maxT, maxT), 0) * look
    local sp = (d.speed or 30) * speedK * math.clamp(1 - math.abs(ang) / math.rad(100), 0.25, 1)
    local step = math.min(sp * dt, dist)
    local np = p + nl * step
    local nb
    if e.lcac then   -- 气垫艇上：车底在艇的甲板高度；冲上沙滩放下车
      local LC = G.LCAC
      local h = Map.height(np.X, np.Z)
      if h > 0.8 then
        G.lcacDropOff(e)
        nb = G.vehBaseAt(d, np.X, np.Z, nl)
      else
        local y = math.max(Map.ground(np.X, np.Z), 0) + LC.deck
        nb = CFrame.lookAt(V(np.X, y, np.Z), V(np.X, y, np.Z) + nl)
        if e.lcac and e.lcac.alive then G.moveEnt(e.lcac, G.lcacUnder(nb)) end
      end
    else
      if Map.height(np.X, np.Z) < -2 and not d.amphib then e.model:SetAttribute("Sp", 0) return 0 end   -- 前面是海：不往下开
      nb = G.vehBaseAt(d, np.X, np.Z, nl)
    end
    G.moveEnt(e, nb * CF(0, d.H / 2, 0))
    e.model:SetAttribute("Sp", math.floor(sp * 3.6 / 2.8 + 0.5))
    return step
  end

  -- 朝 key（据点）的下一个路点：流场（Nav）有就跟着走，没有（不在一块陆地上、还没算好）直接朝目标
  local function waypoint(e, dest)
    local p = e.root.CFrame.Position
    if (flat(dest - p)).Magnitude > 140 and G.navNext then
      local wp = G.navNext(p, e.ai.goal)
      if wp then return wp end
    end
    return dest
  end

  ---------------------------------------------------------------- 看、打

  local function weaponsOf(d)
    local main, mg = nil, nil
    for _, wid in ipairs(d.weapons or {}) do
      local w = VD.W[wid]
      if w and w.kind == "shell" and not main then main = wid end
      if w and w.kind == "gun" and not mg then mg = wid end
    end
    return main, mg
  end
  local function eyeOf(e) return G.vehBaseOf(e) * CF(0, e.def.H + 1, 0) end
  local function canSee(from, to)
    if not Map.lineClear(from, to, math.clamp((to - from).Magnitude / 40, 10, 40)) then return false end
    if G.smokeBlocks and G.smokeBlocks(from, to) then return false end
    return true
  end
  -- 敌人：{ pos, kind = "veh" / "fort" / "inf", ref }
  local function findTarget(e)
    local main, mg = weaponsOf(e.def)
    local eye = eyeOf(e).Position
    local best, bs = nil, math.huge
    local function consider(pos, kind, ref)
      local dd = (pos - eye).Magnitude
      local range = (kind == "inf") and ((mg and MG_R) or GUN_R * 0.6) or (main and GUN_R or MG_R)
      if dd > range then return end
      local sc = dd * ((kind == "veh") and 0.5 or ((kind == "fort") and 0.8 or 1))
      if sc >= bs then return end
      if not canSee(eye, pos + V(0, 1.5, 0)) then return end
      best, bs = { pos = pos, kind = kind, ref = ref }, sc
    end
    for _, P in pairs(G.P) do
      if P.alive and P.team ~= e.team and P.char and not G.inVeh(P) then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp then consider(hrp.Position, "inf", P.char) end
      end
    end
    for _, x in ipairs(G.ents) do
      if x.alive and x.team ~= e.team and x ~= e and not x.air and not x.ship and not x.sea then
        local kind = (x.kind == "bot") and "inf" or ((x.kind == "veh") and "veh") or (x.fort and "fort") or nil
        if kind then consider(x.root.CFrame.Position, kind, x) end
      end
    end
    return best
  end
  local function targetPos(t)
    local r = t.ref
    if typeof(r) == "Instance" then
      local hrp = r.Parent and r:FindFirstChild("HumanoidRootPart")
      return hrp and hrp.Position or nil
    end
    if r and r.alive then return r.root.CFrame.Position end
    return nil
  end
  local function spread(dir, deg)
    local s = math.rad(deg)
    return (dir + V((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)).Unit
  end

  local function fire(e, wid)
    local d, w, st = e.def, VD.W[wid], e.wst[wid]
    local t = now()
    if not st or t < st.next then return end
    if st.mag <= 0 then
      if st.reserve <= 0 then return end
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
    end
    local base = G.vehBaseOf(e)
    local mz = VD.muzzle(d, base, e.ty, e.gp, VD.mgWhich(d, wid), e.my, e.mp)
    local S = { team = e.team, name = e.ai.crew.name, bot = e.ai.crew }
    if w.kind == "shell" then
      local dir = spread(mz.LookVector, 0.25)
      G.launch({ kind = "shell", pos = mz.Position, vel = dir * w.speed, grav = true, gscale = w.drop / 0.55, w = w, src = S, ignore = { e.model },
        life = w.range / w.speed + 0.5 })
      G.fx({ k = "vfire", p = mz.Position, d = dir, f = w.fx, id = e.id })
    else
      G.botShot(mz.Position, mz.Position + spread(mz.LookVector, (w.spread or 0.5) * 1.6) * (w.range or 600), w, S, { e.model }, 0)
    end
    st.mag -= 1
    st.next = t + w.rate
    if st.mag <= 0 and st.reserve > 0 then
      local n = math.min(w.mag, st.reserve)
      st.mag, st.reserve = n, st.reserve - n
      st.next = t + math.max(w.rate, w.reload or 0)
    end
  end

  -- 炮塔转向目标、炮口按距离抬高；对准了开火。返回这次用的武器
  local function aimAndFire(e, tgt, dt)
    local d = e.def
    local main, mg = weaponsOf(d)
    local wid = (tgt.kind == "inf") and (mg or main) or (main or mg)
    if not wid then return end
    local w = VD.W[wid]
    local base = G.vehBaseOf(e)
    local pos = targetPos(tgt) or tgt.pos
    if d.rws and VD.mgWhich(d, wid) == "rws" then   -- 遥控武器站：机枪塔自己转向目标、M2 自己俯仰，对准了开火（主炮不跟着转）
      local myW, mpW = VD.rwsAim(d, base, e.ty, pos + V(0, (tgt.kind == "inf") and 1.5 or 1, 0))
      e.my = (e.my or 0) + approach(0, angDiff(myW, e.my or 0), d.rws.trav * dt)
      e.mp = approach(e.mp or 0, mpW, d.rws.rate * dt)
      e.model:SetAttribute("My", math.floor(e.my * 2 + 0.5) / 2)
      e.model:SetAttribute("Mp", math.floor(e.mp * 2 + 0.5) / 2)
      if now() >= e.ai.aimT and math.abs(angDiff(myW, e.my)) < 3 and math.abs(mpW - e.mp) < 3 then fire(e, wid) end
      return wid
    end
    local l = base:PointToObjectSpace(pos + V(0, (tgt.kind == "inf") and 1.5 or 1, 0)) - d.turret.pivot
    local horiz = math.sqrt(l.X * l.X + l.Z * l.Z)
    local wantYaw = math.deg(math.atan2(l.X, -l.Z))
    local drop = 0
    if w.kind == "shell" then
      local tf = horiz / w.speed
      drop = 0.5 * workspace.Gravity * (w.drop or 0.55) * tf * tf
    end
    local el = d.turret.elev or { -6, 18 }
    local wantPitch = math.clamp(math.deg(math.atan2(l.Y + drop, math.max(horiz, 1))), el[1], el[2])
    e.ty = (approach(0, angDiff(wantYaw, e.ty), (d.turret.trav or 40) * dt) + e.ty) % 360
    e.gp = approach(e.gp, wantPitch, 22 * dt)
    e.model:SetAttribute("Ty", math.floor(e.ty * 2 + 0.5) / 2)
    e.model:SetAttribute("Gp", math.floor(e.gp * 2 + 0.5) / 2)
    local tol = (w.kind == "shell") and 1.2 or 4
    if now() >= e.ai.aimT and math.abs(angDiff(wantYaw, e.ty)) < tol and math.abs(wantPitch - e.gp) < tol then fire(e, wid) end
    return wid
  end

  ---------------------------------------------------------------- 每辆车一步

  local function think(e, dt)
    local A0 = e.ai
    local t = now()
    local main = weaponsOf(e.def)
    -- 撤：血少了、主炮打光了
    if A0.state ~= "retreat" and A0.state ~= "boat" then
      local st = main and e.wst[main]
      if e.hp < e.maxHp * RETREAT or (st and st.mag <= 0 and st.reserve <= 0) then A0.state = "retreat" end
    end
    -- 目标（0.3 秒一次）
    if t >= A0.seekT then
      A0.seekT = t + 0.3
      local nt = (A0.state ~= "boat") and findTarget(e) or nil
      if nt and (not A0.tgt or A0.tgt.ref ~= nt.ref) then A0.aimT = t + 1 + math.random() end   -- 新目标：先瞄一会儿
      A0.tgt = nt
    end
    if A0.tgt then
      local tp = targetPos(A0.tgt)
      if not tp then A0.tgt = nil else A0.tgt.pos = tp aimAndFire(e, A0.tgt, dt) end
    end
    -- 开
    local moved = 0
    local slow = A0.tgt and 0.45 or 0.85
    if A0.state == "boat" then
      moved = drive(e, A0.beach, dt, 1)
      if not e.lcac then   -- 上岸了：撤的时候撤回这里（登陆平台在海上，车开不回去）
        A0.state, A0.home = "go", e.root.CFrame.Position
      end
    elseif A0.state == "retreat" then
      local home = A0.home
      if (flat(home - e.root.CFrame.Position)).Magnitude < 40 then remove(e) return end
      moved = drive(e, home, dt, 0.8)
    else
      -- 目标据点换了（拿下了、换阶段了）：这块陆地上重新挑；这块陆地上没有能去的了（攻方打下了前哨岛）就收走，换地方再派
      local gp = nil
      for _, p in ipairs(Map.POINTS) do if p.id == A0.goal then gp = p end end
      local cur = gp and eligible(e.team, gp, A0.land) or 0
      if cur <= 0 or t >= A0.holdT + 30 then
        A0.holdT = t
        local g = pickGoal(e.team, A0.land)
        if not g then remove(e) return end
        if g.id ~= A0.goal and (cur <= 0 or eligible(e.team, g, A0.land) > cur + 0.5) then   -- 有更要紧的（被攻了）才换
          A0.goal, A0.hold, A0.state, gp = g.id, nil, "go", g
        end
      end
      if gp then
        A0.hold = A0.hold or holdSpot(gp, e.root.CFrame.Position)
        if (flat(A0.hold - e.root.CFrame.Position)).Magnitude < 25 then
          A0.state = "hold"
          e.model:SetAttribute("Sp", 0)
        else
          A0.state = "go"
          local wp = (t < A0.sideT and A0.side) or waypoint(e, A0.hold)
          moved = drive(e, wp, dt, slow)
        end
      end
    end
    -- 卡住了（想走、走不动）：往旁边倒一下
    if A0.state == "go" or A0.state == "retreat" then
      if t - (A0.stuckAt or t) > 6 then
        local p = e.root.CFrame.Position
        if (flat(p - A0.lastP)).Magnitude < 6 then
          local a = math.random() * math.pi * 2
          A0.side, A0.sideT = p + V(math.cos(a), 0, math.sin(a)) * 60, t + 4
        end
        A0.lastP, A0.stuckAt = p, t
      end
      A0.stuckAt = A0.stuckAt or t
    end
    local _ = moved
  end

  ---------------------------------------------------------------- 每帧（10 次 / 秒）

  local acc, spawnT = 0, 0
  G.onFrame(function(dt)
    acc += dt
    if acc < 0.1 then return end
    local step = acc
    acc = 0
    local R = G.round
    if not R or R.phase ~= "battle" or G.aiVehOff then
      for i = #list, 1, -1 do
        if list[i].alive then remove(list[i]) end
        table.remove(list, i)
      end
      return
    end
    for i = #list, 1, -1 do
      local e = list[i]
      if not e.alive or not e.ai then
        table.remove(list, i)
        nextAt[e.team] = math.max(nextAt[e.team], now() + REDO)
      else
        G.try("AI 车", think, e, step)
      end
    end
    spawnT -= step
    if spawnT <= 0 then
      spawnT = 3
      for _, team in ipairs({ "atk", "def" }) do
        local n = 0
        for _, e in ipairs(list) do if e.team == team then n += 1 end end
        if n < MAX and now() >= nextAt[team] then
          local ok, e = G.try("派 AI 车", spawn, team)
          nextAt[team] = now() + ((ok and e) and 8 or 15)   -- 一辆一辆来；没派成（车位满、没地方）过一会儿再试
        end
      end
    end
  end)
end

return AIVeh
