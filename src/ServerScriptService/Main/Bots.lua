-- 暗剑：登岛战——机器人：真人不够时补人（每队保底 Config.Bots.minPerTeam 人，全服最多 maxTotal 个；真人多了，多出来的机器人阵亡后不再复活）
--   攻方：开战后成班坐登陆艇（按要打的据点挑海滩 / 小岛南岸），上岸朝据点推进，见敌就打；拿下一个往同一块陆地上的下一个推，
--     这块陆地上没有要打的了就「回船」（不算阵亡，重新坐艇去别处）；有拿下的据点时也可能直接在那里出生
--   守方：准备阶段就出生，分到各个还在手里的据点（哪边攻方多往哪边多分），在圈里找位置站着；据点丢了换一个
--   打人：看得见（地形不挡）、sight 格以内最近的敌人（玩家、敌方机器人），反应一下再开火，散布随距离变大
--   机器人是实体（Ents）：一个锚定的命中盒，客户端画成小兵（View.lua）；上半截打中算爆头
local Bots = {}

function Bots.init(G)
  local Config, Map = G.Config, G.Map
  local BC = Config.Bots
  local V = Vector3.new
  local now = os.clock
  local W = Config.Weapons[BC.weapon] or Config.Weapons.m4
  local SIZE = V(2.2, 5.6, 1.6)   -- 命中盒（脚底到头顶）
  local HALF = SIZE.Y / 2

  local NAMES = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima", "Mike", "November",
    "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "Xray", "Yankee", "Zulu" }
  local list = {}   -- 全部机器人记录（活着的、等复活的）
  local serial = { atk = 0, def = 0 }

  ---------------------------------------------------------------- 人数

  local function realCount(team)
    local n = 0
    for _, P in pairs(G.P) do if P.team == team then n += 1 end end
    return n
  end
  function G.botCount(team)
    local n = 0
    for _, B in ipairs(list) do if B.team == team and not B.leaving then n += 1 end end
    return n
  end
  -- 战况表里的机器人行
  function G.botBoard()
    local out = {}
    for i, B in ipairs(list) do
      if not B.leaving then table.insert(out, { n = B.name, id = -i, t = B.team, k = B.k, d = B.d, s = B.s, c = B.c, r = "rifle", bot = true }) end
    end
    return out
  end

  local function newRecord(team)
    serial[team] += 1
    local n = serial[team]
    local nm = NAMES[(n - 1) % #NAMES + 1] .. "-" .. ((team == "atk") and "1" or "2") .. string.format("%02d", n)
    local B = { team = team, name = nm, k = 0, d = 0, s = 0, c = 0, e = nil, state = "wait", respawnAt = now() + math.random() * 2, ammo = 30 }
    table.insert(list, B)
    return B
  end
  local function dropRecord(B)
    for i, x in ipairs(list) do
      if x == B then table.remove(list, i) break end
    end
  end

  -- 每队要几个机器人：保底人数减真人，两队加起来不超过 maxTotal
  local function wanted()
    local a = math.max(0, BC.minPerTeam - realCount("atk"))
    local d = math.max(0, BC.minPerTeam - realCount("def"))
    if a + d > BC.maxTotal then
      local k = BC.maxTotal / (a + d)
      a, d = math.floor(a * k + 0.5), math.floor(d * k + 0.5)
    end
    return { atk = a, def = d }
  end

  local function despawn(B)
    if B.boat and G.botOffBoat then G.botOffBoat(B) end
    if B.e then
      local e = B.e
      B.e = nil
      e.onDeath = nil
      if e.alive then G.removeEnt(e) end
    end
  end

  local function balance()
    local want = wanted()
    for _, team in ipairs({ "atk", "def" }) do
      local have = G.botCount(team)
      if have < want[team] then
        -- 先把标了要走的叫回来，不够再新建
        for _, B in ipairs(list) do
          if have >= want[team] then break end
          if B.team == team and B.leaving then B.leaving = nil have += 1 end
        end
        for _ = have + 1, want[team] do newRecord(team) end
      elseif have > want[team] then
        local extra = have - want[team]
        -- 没出生的直接删；出生了的标上「要走」，阵亡后不再复活
        for i = #list, 1, -1 do
          local B = list[i]
          if extra <= 0 then break end
          if B.team == team and not B.leaving and not B.e then
            dropRecord(B)
            extra -= 1
          end
        end
        for i = #list, 1, -1 do
          local B = list[i]
          if extra <= 0 then break end
          if B.team == team and not B.leaving then
            B.leaving = true
            extra -= 1
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 据点挑选

  local function pointList() return Map.POINTS end
  local function pointState(id) return G.points and G.points[id] end
  local function assigned(team, field, id)
    local n = 0
    for _, B in ipairs(list) do if B.team == team and B[field] == id and B.e then n += 1 end end
    return n
  end

  -- 攻方要打的据点：集中兵力——七成打「主攻」据点（每 20 秒重选：离舰队近的、进度高的、守的人少的优先），
  --   三成分到别的据点牵制（派去的人最少的）
  local WEIGHT = { A = 1.3, B = 0.7, C = 1.1, D = 1.0, E = 0.8 }
  local focus, focusAt = nil, 0
  local function defNear(p)
    local n = 0
    for _, B in ipairs(list) do
      local e = B.e
      if B.team == "def" and e and e.alive then
        local q = e.root.CFrame.Position
        if (q.X - p.x) ^ 2 + (q.Z - p.z) ^ 2 < 150 * 150 then n += 1 end
      end
    end
    return n
  end
  local function pickFocus()
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and not s.locked then
        local sc = (WEIGHT[p.id] or 1) + 2.5 * (s.prog or 0) - 0.12 * defNear(p) + math.random() * 0.1
        if p.id == focus then sc += 0.4 end   -- 别来回换
        if sc > bs then best, bs = p, sc end
      end
    end
    focus = best and best.id or nil
    focusAt = now() + 20
  end
  local function pickAtkTarget(land)
    if now() >= focusAt or (focus and pointState(focus) and pointState(focus).locked) then pickFocus() end
    if focus and math.random() < 0.7 then
      for _, p in ipairs(pointList()) do
        if p.id == focus and (not land or p.land == land) then return p end
      end
    end
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and not s.locked and (not land or p.land == land) then
        local sc = (WEIGHT[p.id] or 1) / (1 + assigned("atk", "target", p.id)) + math.random() * 0.05
        if sc > bs then best, bs = p, sc end
      end
    end
    return best
  end
  -- 守方去守的据点：攻方在附近的多派（need = 圈附近的攻方 + 1）/（已派 + 1）
  local function pickDefPoint(land)
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and not s.locked and s.owner == "def" and (not land or p.land == land) then
        local press = (s.atk or 0) + (s.prog or 0) * 3
        local sc = (1 + press) / (1 + assigned("def", "guard", p.id)) + math.random() * 0.05
        if sc > bs then best, bs = p, sc end
      end
    end
    return best
  end
  -- 据点圈里随便一处能站人的地方
  local function spotNear(x, z, r0, r1)
    for _ = 1, 10 do
      local a, r = math.random() * math.pi * 2, r0 + math.random() * (r1 - r0)
      local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
      if Map.isLand(px, pz) and Map.slope(px, pz) < 1 then return V(px, 0, pz) end
    end
    return V(x, 0, z)
  end
  -- 离 (x, z) 最近的登陆点（同一块陆地）
  local function landingFor(p)
    local best, bd = nil, 1e18
    for _, b in ipairs(Map.LANDINGS) do
      local land = b.isle or "main"
      if land == p.land then
        local d = (b.cx - p.x) ^ 2 + (b.z - p.z) ^ 2
        if d < bd then best, bd = b, d end
      end
    end
    return best
  end

  ---------------------------------------------------------------- 出生、阵亡

  local function rootCF(x, z, face)
    local y = Map.ground(x, z) + HALF
    local p = V(x, y, z)
    face = face or V(0, 0, -1)
    return CFrame.lookAt(p, p + V(face.X, 0, face.Z))
  end

  local onDeath
  local function makeEnt(B, cf)
    local e = G.newEnt({ kind = "bot", team = B.team, cat = "inf", hp = BC.hp, size = SIZE, cf = cf, extra = { counts = 1, bot = B, headTop = 1.4 } })
    e.model:SetAttribute("Name", B.name)
    e.onDeath = onDeath
    B.e = e
    B.tgt, B.tgtPos, B.goal, B.detour, B.wp, B.navKey = nil, nil, nil, nil, nil, nil
    local ja = math.random() * math.pi * 2
    B.jit = V(math.cos(ja), 0, math.sin(ja)) * (4 + math.random() * 14)
    B.blocked, B.miss = nil, 0
    B.thinkAt = now() + math.random() * 0.5
    B.fireAt = 0
    B.ammo = 30
    B.lastPos, B.lastPosT = cf.Position, now()
    return e
  end

  local function credit(src, B)
    local kname = nil
    if src and src.P and G.P[src.P.pl] == src.P then
      local K = src.P
      if K.team ~= B.team then
        K.kills += 1
        G.addScore(K, Config.Score.botKill)
        G.msg(K.pl, "kill", "ui.youKilled", B.name)
      end
      kname = K.pl.DisplayName
    elseif src and src.bot then
      src.bot.k += 1
      src.bot.s += Config.Score.kill
      kname = src.bot.name
    elseif src and src.name then
      kname = src.name
    end
    if kname then G.msgAll("feed", "ui.killed", kname, B.name) end
  end

  onDeath = function(e, src)
    local B = e.bot
    if B then
      B.d += 1
      if B.boat and G.botOffBoat then G.botOffBoat(B) end
      B.e = nil
      B.state = "wait"
      B.respawnAt = now() + Config.RespawnDelay + 2 + math.random() * 4
      B.target, B.guard = nil, nil
      G.try("机器人记功", credit, src, B)
      if B.leaving then dropRecord(B) end
    end
    task.delay(0.05, function() G.removeEnt(e) end)
  end

  -- 靠岸：从艇上下来，朝据点走
  function G.botLanded(B, x, z)
    local e = B.e
    if not e or not e.alive then return end
    G.moveEnt(e, rootCF(x, z, V(0, 0, -1)))
    B.state = "move"
    local p = B.target and Map.POINTS[B.targetI or 0]
    B.goal = nil
  end

  local function spawnAtk(B)
    -- 有拿下的据点、同一块陆地上还有要打的：四成在那里出生
    local caps = {}
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and s.owner == "atk" and pickAtkTarget(p.land) then table.insert(caps, p) end
    end
    if #caps > 0 and math.random() < 0.4 then
      local p = caps[math.random(#caps)]
      local tg = pickAtkTarget(p.land)
      local sp = spotNear(p.x, p.z, 10, 40)
      makeEnt(B, rootCF(sp.X, sp.Z, V(tg.x - sp.X, 0, tg.z - sp.Z)))
      B.target = tg.id
      B.state = "move"
      return true
    end
    local tg = pickAtkTarget(nil)
    if not tg then return false end
    local b = landingFor(tg)
    if not b or not G.boatBot then return false end
    local boat, cf = G.boatBot(B, b.id)
    if not boat then return false end
    makeEnt(B, cf)
    B.target = tg.id
    B.state = "boat"
    return true
  end

  local function spawnDef(B)
    local p = pickDefPoint(nil)
    if not p then
      local sp = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60)
      makeEnt(B, rootCF(sp.X, sp.Z, V(0, 0, 1)))
      B.guard = nil
      B.state = "guard"
      return true
    end
    local s = pointState(p.id)
    if s and s.pressed then
      -- 圈里有攻方：不能直接出生在那里——主岛上的据点从营地走过去，小岛上的换一个
      if p.land ~= "main" then
        p = pickDefPoint("main")
        if not p then return false end
      end
      if pointState(p.id).pressed then
        local sp = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60)
        makeEnt(B, rootCF(sp.X, sp.Z, V(0, 0, 1)))
        B.guard = p.id
        B.state = "guard"
        return true
      end
    end
    local sp = spotNear(p.x, p.z, 15, Map.POINT_R * 0.8)
    makeEnt(B, rootCF(sp.X, sp.Z, V(0, 0, 1)))
    B.guard = p.id
    B.state = "guard"
    return true
  end

  ---------------------------------------------------------------- 看、打

  local function headOf(e) return e.root.CFrame.Position + V(0, HALF - 0.7, 0) end

  -- 找目标：sight 格以内、地形不挡的最近的敌人（玩家或机器人），最多验 3 个视线
  local function findTarget(B)
    local e = B.e
    local h = headOf(e)
    local cands = {}
    local sight = BC.sight
    for _, P in pairs(G.P) do
      if P.team ~= B.team and P.alive and P.char and not P.vehicle then   -- 车里的人打不着（步枪打不动车）
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        local hum = P.char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
          local d = (hrp.Position - h).Magnitude
          if d < sight then table.insert(cands, { d = d, P = P, part = hrp }) end
        end
      end
    end
    for _, C in ipairs(list) do
      local ce = C.e
      if C.team ~= B.team and ce and ce.alive and C.state ~= "boat" then
        local d = (ce.root.CFrame.Position - h).Magnitude
        if d < sight then table.insert(cands, { d = d, bot = C }) end
      end
    end
    -- 刚才连着打不中（被房子、墙挡着）的目标先不打
    local bl = B.blocked
    if bl then
      local t = now()
      for i = #cands, 1, -1 do
        local who = cands[i].P or cands[i].bot
        if bl[who] and bl[who] > t then table.remove(cands, i) end
      end
    end
    if #cands == 0 then return nil end
    table.sort(cands, function(a, b) return a.d < b.d end)
    for i = 1, math.min(3, #cands) do
      local c = cands[i]
      local tp = c.part and (c.part.Position + V(0, 1, 0)) or headOf(c.bot.e)
      if Map.lineClear(h, tp, 10) and (not G.smokeBlocks or not G.smokeBlocks(h, tp)) then return c end
    end
    return nil
  end

  local function targetPos(c)
    if c.P then
      local P = c.P
      if not P.alive or not P.char or not c.part.Parent then return nil end
      local hum = P.char:FindFirstChildOfClass("Humanoid")
      if not hum or hum.Health <= 0 then return nil end
      return c.part.Position + V(0, 0.8, 0)
    elseif c.bot then
      local ce = c.bot.e
      if not ce or not ce.alive then return nil end
      return ce.root.CFrame.Position + V(0, 0.6, 0)
    end
    return nil
  end

  -- 打中的是不是目标本身（玩家角色 / 目标机器人）
  local function hitIsTarget(inst, c)
    if not inst then return false end
    if c.P then return c.P.char ~= nil and inst:IsDescendantOf(c.P.char) end
    if c.bot and c.bot.e then return inst:IsDescendantOf(c.bot.e.model) end
    return false
  end
  local function fire(B, tp)
    local e = B.e
    local from = headOf(e)
    local d = (tp - from).Magnitude
    local deg = BC.spread + d * BC.spreadPer
    local hit = G.botShot(from, tp, W, { bot = B, team = B.team, name = B.name }, { e.model }, deg)
    -- 连着 6 枪都打在别的东西上（不是打偏到天上）：多半被挡着，这个目标 10 秒内不打了
    if hit and B.tgt and not hitIsTarget(hit, B.tgt) and not G.entOf(hit) then
      B.miss = (B.miss or 0) + 1
      if B.miss >= 6 then
        B.miss = 0
        B.blocked = B.blocked or {}
        B.blocked[B.tgt.P or B.tgt.bot] = now() + 10
        B.tgt, B.tgtPos = nil, nil
      end
    elseif hit then
      B.miss = 0
    end
    B.ammo -= 1
    if B.ammo <= 0 then
      B.ammo = 30
      B.fireAt = now() + W.reload + 0.5
    else
      B.fireAt = now() + BC.fireGap * (0.8 + math.random() * 0.5)
    end
  end

  ---------------------------------------------------------------- 走

  local TRY = { 0, 35, -35, 70, -70, 110, -110 }
  local function t0wp(B) return now() - (B.wpT or 0) > 1.5 end   -- 路点每 1.5 秒重取一次
  local function rotY(v, deg)
    local a = math.rad(deg)
    local c, s = math.cos(a), math.sin(a)
    return V(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
  end

  local function walk(B, dt, slow)
    local e = B.e
    local goal = B.detour or B.goal
    if not goal then return end
    local p = e.root.CFrame.Position
    -- 离目的地还远：顺着寻路的流场走（绕开陡坡、海）
    if not B.detour and B.navKey and G.navNext and (V(goal.X - p.X, 0, goal.Z - p.Z)).Magnitude > 70 then
      if not B.wp or t0wp(B) then
        B.wp = G.navNext(p, B.navKey)
        B.wpT = now()
        if B.wp then B.wp += B.jit end   -- 每人偏一点，不排成一条线、不挤在一处
      end
      if B.wp then goal = B.wp end
    end
    local d = V(goal.X - p.X, 0, goal.Z - p.Z)
    local dist = d.Magnitude
    if dist < 2.5 then
      if goal == B.wp then B.wp = nil return end
      if B.detour then B.detour = nil else B.goal = nil B.arrived = now() end
      return
    end
    local speed = BC.speed * (slow or 1) * (G.wireSlow and G.wireSlow(p.X, p.Z) or 1)   -- 铁丝网里走不快
    local step = math.min(dist, speed * dt)
    local dir = d / dist
    local np, nd = nil, nil
    for _, a in ipairs(TRY) do
      local dd = (a == 0) and dir or rotY(dir, a)
      local x, z = p.X + dd.X * step, p.Z + dd.Z * step
      local h = Map.height(x, z)
      if h > 0.3 and (h - (p.Y - HALF)) < step * 1.25 + 0.6 then   -- 不下水、不爬太陡的坡
        np, nd = V(x, h + HALF, z), dd
        break
      end
    end
    if not np then return end
    local look = nd
    if B.tgtPos then look = V(B.tgtPos.X - np.X, 0, B.tgtPos.Z - np.Z) end
    if look.Magnitude < 0.01 then look = nd end
    G.moveEnt(e, CFrame.lookAt(np, np + look))
  end

  -- 卡住了（10 秒没走出 6 格）：往旁边绕一下
  local function unstick(B)
    local e = B.e
    local t = now()
    if B.tgtPos then B.lastPos, B.lastPosT = e.root.CFrame.Position, t return end   -- 交火时站着不算卡住
    if t - B.lastPosT < 10 then return end
    local p = e.root.CFrame.Position
    if (B.goal or B.detour) and (p - B.lastPos).Magnitude < 6 then
      local a = math.random() * math.pi * 2
      local r = 40 + math.random() * 50
      B.detour = V(p.X + math.cos(a) * r, 0, p.Z + math.sin(a) * r)
    end
    B.lastPos, B.lastPosT = p, t
  end

  ---------------------------------------------------------------- 想（每半秒一次，错开）

  local function thinkAtk(B)
    local e = B.e
    local p = e.root.CFrame.Position
    local s = B.target and pointState(B.target)
    if not s or s.locked then
      local land = Map.landOf(p.X, p.Z)
      local tg = pickAtkTarget(land)
      if tg then
        B.target = tg.id
        B.goal = nil
      else
        -- 这块陆地上没有要打的了：过一会儿回船（不算阵亡）
        B.target = nil
        B.recycleAt = B.recycleAt or (now() + 12 + math.random() * 10)
        if now() >= B.recycleAt then
          B.recycleAt = nil
          despawn(B)
          B.state = "wait"
          B.respawnAt = now() + 1
        end
        return
      end
    end
    local pt = nil
    for _, q in ipairs(Map.POINTS) do if q.id == B.target then pt = q end end
    if not pt then return end
    local dx, dz = p.X - pt.x, p.Z - pt.z
    local inside = dx * dx + dz * dz < (Map.POINT_R * 0.8) ^ 2
    B.navKey = pt.id
    if not B.goal and not B.detour then
      if inside then
        if not B.arrived or now() - B.arrived > 8 + math.random() * 10 then B.goal = spotNear(pt.x, pt.z, 5, Map.POINT_R * 0.7) end
      else
        B.goal = spotNear(pt.x, pt.z, 5, 40)
      end
    end
  end

  local function thinkDef(B)
    local e = B.e
    local p = e.root.CFrame.Position
    local s = B.guard and pointState(B.guard)
    if not s or s.locked or s.owner ~= "def" or (B.reassignAt and now() >= B.reassignAt) then
      local land = Map.landOf(p.X, p.Z)
      local q = pickDefPoint(land)
      B.reassignAt = now() + 20 + math.random() * 20
      if q and q.id ~= B.guard then
        B.guard = q.id
        B.goal = nil
      elseif not q then
        B.guard = nil
      end
    end
    local pt = nil
    for _, q in ipairs(Map.POINTS) do if q.id == B.guard then pt = q end end
    if not pt then
      B.navKey = "camp"
      if not B.goal and Map.landOf(p.X, p.Z) == "main" then B.goal = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60) end
      return
    end
    B.navKey = pt.id
    if not B.goal and not B.detour then
      local dx, dz = p.X - pt.x, p.Z - pt.z
      local inside = dx * dx + dz * dz < (Map.POINT_R * 0.9) ^ 2
      if not inside or not B.arrived or now() - B.arrived > 20 + math.random() * 25 then
        B.goal = spotNear(pt.x, pt.z, 12, Map.POINT_R * 0.85)
      end
    end
  end

  local function think(B)
    local battle = G.round and G.round.phase == "battle"
    if battle then
      local c = findTarget(B)
      if c and (not B.tgt or B.tgt.P ~= c.P or B.tgt.bot ~= c.bot) then
        B.fireAt = math.max(B.fireAt, now() + BC.reaction * (0.6 + math.random() * 0.8))   -- 新目标：反应一下
      end
      B.tgt = c
    else
      B.tgt = nil
    end
    if B.team == "atk" then thinkAtk(B) else thinkDef(B) end
    if B.e then unstick(B) end
  end

  ---------------------------------------------------------------- 每步

  local balanceT = 0
  function G.botsStep(dt)
    local t = now()
    local phase = G.round and G.round.phase
    balanceT -= dt
    if balanceT <= 0 then
      balanceT = 2
      if phase == "prep" or phase == "battle" then balance() end
    end
    for _, B in ipairs(table.clone(list)) do
      if B.e and not B.e.alive then B.e = nil end
      if not B.e then
        if B.state ~= "boat" and not B.leaving and t >= (B.respawnAt or 0) then
          local ok = false
          if B.team == "def" and (phase == "prep" or phase == "battle") then ok = spawnDef(B)
          elseif B.team == "atk" and phase == "battle" then ok = spawnAtk(B) end
          if not ok then B.respawnAt = t + 2 end
        elseif B.leaving and not B.e then
          dropRecord(B)
        end
      elseif B.state ~= "boat" then
        if t >= (B.thinkAt or 0) then
          B.thinkAt = t + 0.5
          G.try("机器人想", think, B)
        end
        if B.e then
          B.tgtPos = B.tgt and targetPos(B.tgt) or nil
          if not B.tgtPos then B.tgt = nil end
          -- 交火：150 格以内站住打（守方一直站住打），300 格以内边走边打（走慢点），再远照常走、偶尔打几枪
          local td = B.tgtPos and (B.tgtPos - B.e.root.CFrame.Position).Magnitude or 1e9
          if B.tgtPos and phase == "battle" and t >= B.fireAt then
            fire(B, B.tgtPos)
            if td > 300 then B.fireAt += BC.fireGap * 2 end
          end
          local hold = B.tgtPos and (B.team == "def" or td < 150)
          if not hold then walk(B, dt, (td < 300) and 0.5 or 1) elseif B.tgtPos then
            local p = B.e.root.CFrame.Position
            local look = V(B.tgtPos.X - p.X, 0, B.tgtPos.Z - p.Z)
            if look.Magnitude > 0.1 then G.moveEnt(B.e, CFrame.lookAt(p, p + look)) end
          end
        end
      end
    end
  end

  -- 新一局：机器人全清掉，记录（战绩）清零，重新按人数补
  G.on("roundStart", function()
    for _, B in ipairs(list) do despawn(B) end
    list = {}
    focus, focusAt = nil, 0
    serial = { atk = 0, def = 0 }
    balance()
  end)
  G.on("roundEnd", function()
    for _, B in ipairs(list) do B.tgt = nil end
  end)
end

return Bots
