-- Roblox全面大战场——机器人：真人不够时补人（每队保底 Config.Bots.minPerTeam 人，全服最多 maxTotal 个；真人多了，多出来的机器人阵亡后不再复活）
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
  -- 姿势（用户：给小兵加上动画和姿势）：命中零件跟着变——站 5.6 高、蹲 / 跪 4 高、趴 1.5 高 5.4 长；眼睛（看、开枪）的位置也跟着变；
  --   根零件（位置）还是在脚底上 2.8 格，别的模块照旧用；客户端（Soldier.lua）按属性 St 摆姿势
  local STANCE = {
    [0] = { size = SIZE, y = 0, head = 1.4, eye = V(0, HALF - 0.7, 0) },
    [1] = { size = V(2.2, 4.0, 2.0), y = -0.8, head = 1.2, eye = V(0, 0.8, -0.3) },
    [2] = { size = V(2.4, 1.8, 5.4), y = -1.9, head = 0.4, eye = V(0, -1.8, -2.0) },
  }
  local SQ = BC.squad or 5   -- 一个小队几个人（用户：登陆和防守的按照小队为单位聚在一起）
  local NADE = Config.Weapons.grenade

  -- 机器人的样子用 Roblox 正常小人（用户：士兵建模太粗糙了，就用 Roblox 正常小人的建模）：开服时生成一个默认的 R15 小人当模板
  --   放进 ReplicatedStorage.BotRig，客户端（Soldier.lua）每个机器人克隆一个、按队伍上色、播 Roblox 自带的动作；生成不了（没网）就用零件拼的经典小人
  task.spawn(function()
    local RS = game:GetService("ReplicatedStorage")
    if RS:FindFirstChild("BotRig") then return end
    local ok, rig = pcall(function()
      local desc = Instance.new("HumanoidDescription")
      return game:GetService("Players"):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not ok or not rig then
      print("[全面大战场] 机器人小人模板生成不了（客户端用零件拼的经典小人）：" .. tostring(rig))
      return
    end
    for _, d in ipairs(rig:GetDescendants()) do
      if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") then d:Destroy() end
    end
    rig.Name = "BotRig"
    -- 先在 workspace 高空放一下让关节解算（各零件摆到站姿的位置），再收进 ReplicatedStorage：直接放进去的话零件位置没解算，
    --   客户端按零件量「根零件到脚底」量出来偏小，小人被摆低、腿埋在地里（用户：士兵卡在地底下）
    pcall(function()
      local hrp = rig:FindFirstChild("HumanoidRootPart")
      if hrp then hrp.Anchored = true end
      rig:PivotTo(CFrame.new(0, 4000, 0))
      rig.Parent = workspace
      for _ = 1, 3 do game:GetService("RunService").Heartbeat:Wait() end
    end)
    rig.Parent = RS
  end)

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
    local B = { team = team, name = nm, k = 0, d = 0, s = 0, c = 0, e = nil, state = "wait", respawnAt = now() + math.random() * 2, ammo = 30,
      -- 每个人自己的脾气（用户：每个人要有自己的动作逻辑，不要一堆人一模一样）：反应快慢、枪法、胆子、步子快慢、爱不爱趴着打、带几颗手雷
      pers = { react = 0.65 + math.random() * 0.8, aim = 0.75 + math.random() * 0.55, brave = math.random(), pace = 0.92 + math.random() * 0.16,
        prone = math.random(), nades = (math.random() < 0.65) and ((math.random() < 0.3) and 2 or 1) or 0, shift = 14 + math.random() * 22 } }
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

  -- 小队：{ team, m = { 队员 }, lead = 队长, contactT / contactP（最近一次交火的时间、敌人在哪）, bound（交替掩护：1 / 2 组在冲）、
  --   boundAt（什么时候换）、adv（推进到哪了）, face（守方：阵地朝哪边） }
  local squads = {}
  local function leaveSquad(B)
    local S = B.sq
    B.sq = nil
    if not S then return end
    for i, x in ipairs(S.m) do if x == B then table.remove(S.m, i) break end end
    if S.lead == B then S.lead = S.m[1] end
    if #S.m == 0 then
      for i, x in ipairs(squads) do if x == S then table.remove(squads, i) break end end
    end
  end
  G.botSquads = function() return squads end   -- 测试用

  local function despawn(B)
    leaveSquad(B)
    if B.boat and G.botOffBoat then G.botOffBoat(B) end
    if B.e then
      local e = B.e
      B.e = nil
      e.onDeath = nil
      if e.alive then G.removeEnt(e) end
    end
  end

  -- 登陆艇满了、真人要上（Vehicles.lua）：这个机器人让座——收掉，过两秒重新出生（坐下一班）
  function G.botBump(B)
    if not B then return end
    despawn(B)
    B.state = "wait"
    B.respawnAt = now() + 2
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
  -- 能去打 / 去守的：还没被拿下、而且是当前阶段开放的（Round.lua 分阶段突破：别的阶段的据点不去）
  local function open(s) return s ~= nil and not s.locked and (not G.pointActive or G.pointActive(s.id)) end
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
      if open(s) and not (G.flankOf and G.flankOf[p.id]) then   -- 主攻不放在侧翼
        local sc = (WEIGHT[p.id] or 1) + 2.5 * (s.prog or 0) - 0.12 * defNear(p) + math.random() * 0.1
        if p.id == focus then sc += 0.4 end   -- 别来回换
        if sc > bs then best, bs = p, sc end
      end
    end
    focus = best and best.id or nil
    focusAt = now() + 20
  end
  local function pickAtkTarget(land)
    if now() >= focusAt or (focus and not open(pointState(focus))) then pickFocus() end
    if focus and math.random() < 0.7 then
      for _, p in ipairs(pointList()) do
        if p.id == focus and (not land or p.land == land) then return p end
      end
    end
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if open(s) and (not land or p.land == land) then
        local sc = (WEIGHT[p.id] or 1) / (1 + assigned("atk", "target", p.id)) + math.random() * 0.05
        if sc > bs then best, bs = p, sc end
      end
    end
    return best
  end
  -- 下一阶段的据点（守方纵深：当前阶段守满了的去那里先守着）
  local function nextStage(s)
    return s ~= nil and not s.locked and s.owner == "def" and G.stageOf ~= nil and G.round ~= nil and G.stageOf[s.id] == (G.round.stage or 1) + 1
      and not (G.flankOf and G.flankOf[s.id])
  end
  -- 守方去守的据点：攻方在附近的多派（need = 圈附近的攻方 + 1）/（已派 + 1）；
  --   守当前阶段的不超过攻方在场人数的六成（至少 4 个），多的去守下一阶段的（纵深）——不然开局全挤在前哨岛上，
  --   攻方怎么也凑不够人数占点（机器人对打：6 分钟一个点都拿不下，阵亡攻 144 守 51）
  local function frontCap()
    local n = realCount("atk")
    for _, B in ipairs(list) do if B.team == "atk" and B.e then n += 1 end end
    return math.max(4, math.ceil(n * 0.6))
  end
  local function pickDefPoint(land, self)
    local front = 0
    for _, B in ipairs(list) do
      if B ~= self and B.team == "def" and B.e and B.guard and open(pointState(B.guard)) then front += 1 end
    end
    if front >= frontCap() then
      local best, bs = nil, -1e9
      for _, p in ipairs(pointList()) do
        local s = pointState(p.id)
        if nextStage(s) and (not land or p.land == land) then
          local sc = 1 / (1 + assigned("def", "guard", p.id)) + math.random() * 0.05
          if sc > bs then best, bs = p, sc end
        end
      end
      if best then return best end
    end
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if open(s) and s.owner == "def" and (not land or p.land == land) then
        local press = (s.atk or 0) + (s.prog or 0) * 3
        local n = assigned("def", "guard", p.id)
        local sc = (1 + press) / (1 + n) + math.random() * 0.05
        if G.flankOf and G.flankOf[p.id] and press <= 0 then   -- 侧翼没人打：少派（最多 3 个），人留给主攻方向（机器人对打：灯塔岛上趴了 10 个，指挥部丢了也不动）
          sc = (n >= 3) and -1 or sc * 0.5
        end
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
  -- 挨打：被压制（多半会趴下），客户端那边身子一缩（按 Hp 变化自己画）
  local function onHit(e, amt, src)
    local B = e.bot
    if B then B.supp = math.min(4, (B.supp or 0) + 1.2) end
  end
  local function makeEnt(B, cf)
    local e = G.newEnt({ kind = "bot", team = B.team, cat = "inf", hp = BC.hp, size = SIZE, cf = cf, extra = { counts = 1, bot = B, headTop = 1.4 } })
    e.model:SetAttribute("Name", B.name)
    e.onDeath = onDeath
    e.onHit = onHit
    -- 命中零件（姿势变了跟着变）：焊在根零件上跟着走；根零件本身不挨打
    e.root.CanQuery = false
    local hit = Instance.new("Part")
    hit.Name = "Hit"
    hit.Transparency = 1
    hit.CanCollide, hit.CanTouch, hit.CanQuery = false, false, true
    hit.Massless = true
    hit.Size = SIZE
    hit.CFrame = cf
    local hw = Instance.new("Weld")
    hw.Part0, hw.Part1, hw.C0 = e.root, hit, CFrame.new()
    hw.Parent = hit
    hit.Parent = e.model
    e.hit, e.hitW, e.stance = hit, hw, 0
    B.supp, B.nades, B.actN, B.aimSent, B.boundHold, B.stanceT = 0, B.pers.nades, 0, nil, nil, 0
    local pa = math.random() * math.pi * 2
    B.pj = V(math.cos(pa), 0, math.sin(pa)) * (1 + math.random() * 2.5)   -- 在队形里自己的那一点偏差
    B.pjAt = now() + B.pers.shift
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

  -- 换姿势：命中零件变大小、往下挪；属性 St 给客户端
  local function setStance(B, s)
    local e = B.e
    if not e or (e.stance or 0) == s then return end
    local S = STANCE[s]
    e.stance, e.headTop = s, S.head
    if e.hit then
      e.hit.Size = S.size
      e.hitW.C0 = CFrame.new(0, S.y, 0)
    end
    e.model:SetAttribute("St", s)
    B.stanceT = now()
  end
  -- 一次动作给客户端（换弹 r、扔雷 g、打手势 s）：字母后面跟序号，变了才算新的一次
  local function act(B, k)
    if not B.e then return end
    B.actN = (B.actN or 0) + 1
    B.e.model:SetAttribute("Act", k .. B.actN)
  end

  local function credit(src, B)
    local kname = nil
    if src and src.P and G.P[src.P.pl] == src.P then
      local K = src.P
      if K.team ~= B.team then
        K.kills += 1
        G.addScore(K, Config.Score.botKill)
        G.msg(K.pl, "kill", "ui.youKilled", B.name)
        if src.wid and G.gunXp then G.gunXp(K, src.wid, (Config.GunMods and Config.GunMods.botXp) or 60) end   -- 枪械经验（改枪）
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
    -- 打死的那一枪从哪边来（度，0 正前、正的在右边）：客户端按它挑倒法——正面中弹往后倒、背后中弹往前扑、侧面中弹往另一边瘫
    pcall(function()
      local ap = nil
      if src and src.P and src.P.char then
        local h = src.P.char:FindFirstChild("HumanoidRootPart")
        ap = h and h.Position
      end
      if not ap and src and src.bot and src.bot.e then ap = src.bot.e.root.CFrame.Position end
      if ap then
        local rel = e.root.CFrame:PointToObjectSpace(ap)
        e.model:SetAttribute("DieD", math.floor(math.deg(math.atan2(rel.X, -rel.Z)) + 0.5))
      end
    end)
    if B then
      leaveSquad(B)
      B.d += 1
      if B.boat and G.botOffBoat then G.botOffBoat(B) end
      B.e = nil
      B.state = "wait"
      B.respawnAt = now() + Config.RespawnDelay + 2 + math.random() * 4
      B.target, B.guard = nil, nil
      G.try("机器人记功", credit, src, B)
      G.emit("botDied", B)   -- 攻方兵力扣 1（Round.lua）
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
    B.goal = nil
    e.model:SetAttribute("Ride", false)
    setStance(B, 0)
    if B.sq and B.sq.lead == B then act(B, "s") end   -- 队长：跟我上！
  end

  -- 一个小队一起出生（用户：登陆和防守的按照小队为单位聚在一起）：先按第一个人定在哪，队员在他身边排开——
  --   攻方：攻击出发阵地（第二阶段起、八成）/ 拿下的据点（四成）/ 坐同一条登陆艇；守方：据点圈里 / 集结点 / 营地，一字排开面朝来敌的方向
  -- 第 k 个队员（队长是 0）相对队长的位置：楔形，往后两侧散开
  local function wedge(k, fwd)
    if k == 0 then return V() end
    local side = (k % 2 == 1) and -1 or 1
    local row = math.ceil(k / 2)
    local rt = V(-fwd.Z, 0, fwd.X)
    return rt * (side * (4 + 2.5 * row)) - fwd * (4.5 * row)
  end
  local function flatUnit(v, def)
    local f = V(v.X, 0, v.Z)
    return (f.Magnitude > 0.01) and f.Unit or def
  end
  -- 一个据点「来敌的方向」：离它最近的登陆滩
  local function threatDir(p)
    local b = landingFor(p)
    if not b then return V(0, 0, 1) end
    return flatUnit(V(b.cx - p.x, 0, b.z - p.z), V(0, 0, 1))
  end

  local function atkPlan()
    local tg0 = pickAtkTarget(nil)
    if not tg0 then return nil end
    -- 攻击出发阵地能用（第二阶段起、守方没压过来，Round.lua）：八成在那里出生，直接上前线
    local st = G.stagingOk and G.stagingOk(tg0.id)
    if st and math.random() < 0.8 then return { mode = "land", tg = tg0, at = spotNear(st.x, st.z, 0, 35) } end
    -- 有拿下的据点、同一块陆地上还有要打的：四成在那里出生
    local caps = {}
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and s.owner == "atk" and pickAtkTarget(p.land) then table.insert(caps, p) end
    end
    if #caps > 0 and math.random() < 0.4 then
      local p = caps[math.random(#caps)]
      local tg = pickAtkTarget(p.land)
      if tg then return { mode = "land", tg = tg, at = spotNear(p.x, p.z, 10, 40) } end
    end
    if Map.LANDONLY then   -- 沙漠图没有登陆艇：出发阵地被守方压着也在那里（或拿下的据点）出生
      local sp = G.stagingOf and G.stagingOf(tg0.id)
      if sp then return { mode = "land", tg = tg0, at = spotNear(sp.x, sp.z, 0, 35) } end
      if #caps > 0 then
        local p = caps[math.random(#caps)]
        return { mode = "land", tg = tg0, at = spotNear(p.x, p.z, 10, 40) }
      end
      return nil
    end
    local b = landingFor(tg0)
    if not b or not G.boatBot then return nil end
    return { mode = "boat", tg = tg0, beach = b.id }
  end
  local function spawnAtk(B, plan, k)
    local tg = plan.tg
    if plan.mode == "land" then
      local fwd = flatUnit(V(tg.x - plan.at.X, 0, tg.z - plan.at.Z), V(0, 0, -1))
      local sp = plan.at + wedge(k, fwd)
      if not Map.isLand(sp.X, sp.Z) then sp = plan.at end
      makeEnt(B, rootCF(sp.X, sp.Z, fwd))
      B.target, B.state = tg.id, "move"
      return true
    end
    local boat, cf = G.boatBot(B, plan.beach)
    if boat == false and cf then   -- 登陆场已经建立：直接在滩上出生（第一个人定位置，后面的在他身后排开）
      if plan.beachCF then cf = plan.beachCF * CFrame.new(wedge(k, V(0, 0, -1))) else plan.beachCF = cf end
      makeEnt(B, cf)
      B.target, B.state = tg.id, "move"
      return true
    end
    if not boat then return false end
    makeEnt(B, cf)
    B.target, B.state = tg.id, "boat"
    B.e.model:SetAttribute("Ride", true)
    setStance(B, 1)   -- 艇上蹲着
    return true
  end

  local function defPlan()
    local p = pickDefPoint(nil)
    if not p then return { at = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60), face = V(0, 0, 1) } end
    local s = pointState(p.id)
    local hot = s and (s.pressed or (G.countAt and select(1, G.countAt(p.x, p.z, Map.ground(p.x, p.z), 160)) > 0))   -- 攻方到了 160 格以内：不在点里刷
    local rp = hot and G.rallyOf and G.rallyOf(p.id)
    if rp then   -- 据点被攻方压着 / 攻方快到了：在据点后方的集结点出生，冲回去
      local at = spotNear(rp.x, rp.z, 0, 30)
      return { p = p, at = at, face = flatUnit(V(p.x - at.X, 0, p.z - at.Z), V(0, 0, 1)) }
    end
    if s and s.pressed then
      -- 圈里有攻方：不能直接出生在那里——主岛上的据点从营地走过去，小岛上的换一个
      if p.land ~= "main" then
        p = pickDefPoint("main")
        if not p then return nil end
      end
      if pointState(p.id).pressed then return { p = p, at = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60), face = V(0, 0, 1) } end
    end
    return { p = p, at = spotNear(p.x, p.z, 15, Map.POINT_R * 0.8), face = threatDir(p) }
  end
  local function spawnDef(B, plan, k)
    local fwd = plan.face
    local rt = V(-fwd.Z, 0, fwd.X)
    local side = (k % 2 == 1) and -1 or 1
    local sp = plan.at + rt * (side * math.ceil(k / 2) * 6.5) + fwd * ((math.random() - 0.5) * 4)   -- 一字排开
    if not Map.isLand(sp.X, sp.Z) then sp = plan.at end
    makeEnt(B, rootCF(sp.X, sp.Z, fwd))
    B.guard = plan.p and plan.p.id or nil
    B.state = "guard"
    return true
  end

  -- 征服模式（沙漠，Round.lua 的 G.conquest）：两边都一样——挑一个据点去打（敌人的、中立的先；自己的被压着就回去守；自己的没人碰就少派人），
  --   离自己基地越远越不想去、已经有很多队友去的少派；出生在离目标最近、没被压着的自己的据点，没有就在自己基地
  local function conquestOn() return G.conquest ~= nil and G.conquest() end
  local function conqPick(team, from, self)
    local best, bs = nil, -1e9
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s then
        local n = 0
        for _, x in ipairs(list) do if x ~= self and x.team == team and x.e and x.target == p.id then n += 1 end end
        local want
        if s.owner == team then want = s.pressed and 1.5 or 0.12
        elseif s.owner == "none" then want = 1.0
        else want = 1.25 end
        local d = math.sqrt((p.x - from.X) ^ 2 + (p.z - from.Z) ^ 2)
        local sc = want / (1 + n * 0.35) - d / 9000 + math.random() * 0.15
        if sc > bs then best, bs = p, sc end
      end
    end
    return best
  end
  local function conqPlan(team)
    local B0 = Map.BASES and Map.BASES[team]
    if not B0 then return nil end
    local home = V(B0.camp.x, 0, B0.camp.z)
    local tg = conqPick(team, home, nil)
    if not tg then return nil end
    local at, bd = nil, math.huge
    for _, p in ipairs(pointList()) do
      local s = pointState(p.id)
      if s and s.owner == team and not s.pressed and p.id ~= tg.id then
        local d = (p.x - tg.x) ^ 2 + (p.z - tg.z) ^ 2
        if d < bd then at, bd = p, d end
      end
    end
    local spot = at and spotNear(at.x, at.z, 20, Map.POINT_R * 0.9) or spotNear(B0.camp.x, B0.camp.z, 10, 80)
    return { mode = "land", tg = tg, at = spot }
  end
  local function spawnSquad(team, group)
    local conq = conquestOn()
    local plan
    if conq then plan = conqPlan(team) else plan = (team == "atk") and atkPlan() or defPlan() end
    if not plan then return false end
    local S = { team = team, m = {}, bound = 1, boundAt = 0, face = plan.face }
    for k, B in ipairs(group) do
      local ok = false
      if team == "atk" or conq then ok = spawnAtk(B, plan, k - 1) else ok = spawnDef(B, plan, k - 1) end
      if ok and B.e then
        B.sq, B.readyT = S, nil
        table.insert(S.m, B)
      else
        B.respawnAt = now() + 2
      end
    end
    if #S.m == 0 then return false end
    S.lead = S.m[1]
    table.insert(squads, S)
    return true
  end

  ---------------------------------------------------------------- 看、打

  local function headOf(e) return e.root.CFrame * STANCE[e.stance or 0].eye end   -- 眼睛：站着、跪着、趴着高低不一样（趴着还在前面一截）

  -- 找目标：sight 格以内、地形不挡的最近的敌人（玩家或机器人），最多验 3 个视线
  local function findTarget(B)
    local e = B.e
    local h = headOf(e)
    local cands = {}
    local sight = BC.sight
    for _, P in pairs(G.P) do
      if P.team ~= B.team and P.alive and P.char and not G.inVeh(P) then   -- 车里的人打不着（步枪打不动车）；端着平板遥控无人机的照打
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
      local hb = ce.hit or ce.root   -- 瞄命中零件的中间偏上（趴着的人瞄地上那一截）
      return hb.CFrame.Position + V(0, hb.Size.Y * 0.1, 0)
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
    -- 散布：基础 + 距离；乘自己的枪法、被压制时抖、趴着 / 跪着稳一些
    local st = e.stance or 0
    local deg = (BC.spread + d * BC.spreadPer) * B.pers.aim * (1 + 0.45 * math.min(B.supp or 0, 2)) * ((st == 2) and 0.8 or ((st == 1) and 0.9 or 1))
    if B.tgt and B.tgt.bot then
      local C = B.tgt.bot   -- 被人朝着打：压制（打得越近越压得住）
      C.supp = math.min(4, (C.supp or 0) + ((d < 200) and 0.35 or 0.2))
    end
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
      B.reloadUntil = B.fireAt
      act(B, "r")   -- 换弹匣（客户端：左手拔弹匣、掏新的、插上、拉枪机）
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
    local st = e.stance or 0
    local speed = BC.speed * (slow or 1) * (G.wireSlow and G.wireSlow(p.X, p.Z) or 1)   -- 铁丝网里走不快
      * B.pers.pace * ((st == 1) and 0.55 or ((st == 2) and 0.22 or 1))   -- 每人步子快慢不一样；蹲着走慢、匍匐更慢
    local step = math.min(dist, speed * dt)
    local dir = d / dist
    local np, nd = nil, nil
    for _, a in ipairs(TRY) do
      local dd = (a == 0) and dir or rotY(dir, a)
      local x, z = p.X + dd.X * step, p.Z + dd.Z * step
      local h = Map.height(x, z)
      if h > 0.3 and (h - (p.Y - HALF)) < step * 1.25 + 0.6 then   -- 不下水、不爬太陡的坡（根零件一直在脚底上 HALF，趴着也是）
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

  -- 离要去的据点还很远（换了阶段：拿下港口 C 以后机场 D 在 4 公里外）、眼前没有敌人：过几秒「重新部署」（同真人按 H：不算阵亡、
  --   不扣兵力）——攻方到攻击出发阵地、守方按出生规则（据点 / 集结点）重新出生，不在路上走几分钟没仗打
  local function farHop(B, pt)
    local p = B.e.root.CFrame.Position
    local d = math.sqrt((p.X - pt.x) ^ 2 + (p.Z - pt.z) ^ 2)
    local ok = not B.tgt and d > 1300 and G.round ~= nil and G.round.phase == "battle"
    if ok and B.team == "atk" then
      local st = G.stagingOk and G.stagingOk(pt.id)
      ok = st ~= nil and d > math.sqrt((st.x - pt.x) ^ 2 + (st.z - pt.z) ^ 2) + 600
    end
    if not ok then B.hopAt = nil return false end
    B.hopAt = B.hopAt or (now() + 2 + math.random() * 6)
    if now() < B.hopAt then return false end
    B.hopAt = nil
    despawn(B)
    B.state = "wait"
    B.respawnAt = now() + 0.5
    return true
  end

  local function thinkAtk(B)
    local e = B.e
    local p = e.root.CFrame.Position
    local s = B.target and pointState(B.target)
    if not open(s) then
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
    if farHop(B, pt) then return end
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
    if not (open(s) or nextStage(s)) or s.owner ~= "def" or (B.reassignAt and now() >= B.reassignAt) then
      local land = Map.landOf(p.X, p.Z)
      -- 先在所有据点里挑；挑中的在别的岛上（侧翼守多了、小岛据点不用守了）又没在交火：撤走，到那边重新出生（走不过去）
      local q = pickDefPoint(nil, B)
      if q and q.land ~= land and not B.tgt then
        despawn(B)
        B.state = "wait"
        B.respawnAt = now() + 1
        return
      end
      if q and q.land ~= land then q = pickDefPoint(land, B) end
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
    if not pt and Map.landOf(p.X, p.Z) ~= "main" then   -- 小岛上的据点丢了（战线推到主岛）：过一会儿撤走，到新的战线上重新出生
      B.recycleAt = B.recycleAt or (now() + 8 + math.random() * 8)
      if now() >= B.recycleAt then
        B.recycleAt = nil
        despawn(B)
        B.state = "wait"
        B.respawnAt = now() + 1
      end
      return
    end
    B.recycleAt = nil
    if not pt then
      B.navKey = "camp"
      if not B.goal and Map.landOf(p.X, p.Z) == "main" then B.goal = spotNear(Map.CAMP.x, Map.CAMP.z, 10, 60) end
      return
    end
    if farHop(B, pt) then return end
    B.navKey = pt.id
    if not B.goal and not B.detour then
      local dx, dz = p.X - pt.x, p.Z - pt.z
      local inside = dx * dx + dz * dz < (Map.POINT_R * 0.9) ^ 2
      if not inside or not B.arrived or now() - B.arrived > 20 + math.random() * 25 then
        B.goal = spotNear(pt.x, pt.z, 12, Map.POINT_R * 0.85)
      end
    end
  end

  -- 小队里第几个（队长是 0）
  local function slotOf(S, B)
    local k = 0
    for _, x in ipairs(S.m) do
      if x == S.lead then
        if x == B then return 0 end
      else
        k += 1
        if x == B then return k end
      end
    end
    return k
  end
  local function pointById(id)
    if not id then return nil end
    for _, q in ipairs(Map.POINTS) do if q.id == id then return q end end
    return nil
  end

  -- 小队怎么走：攻方跟着队长排楔形，交火时交替掩护（一半人停下趴着 / 跪着打，另一半往前冲三十来格，四到七秒换一次，
  --   换到队长那一组时队长打个「跟上」的手势）；守方在队长两边一字排开、面朝来敌，每人隔一阵自己挪几步
  local function squadMove(B, S)
    local L = S.lead
    local p = B.e.root.CFrame.Position
    local t = now()
    local contact = t - (S.contactT or -1e9) < 5
    B.boundHold, B.rush, B.hurry = nil, nil, nil
    local k = slotOf(S, B)
    if B.team == "atk" then
      local pt = L and pointById(L.target)
      local lp = L and L.e and L.e.root.CFrame.Position
      local near = pt and lp and (lp.X - pt.x) ^ 2 + (lp.Z - pt.z) ^ 2 < 110 * 110   -- 离据点 110 格以内：不再交替，全队一起冲进圈
      if contact and pt and not near then
        if t >= (S.boundAt or 0) or not S.adv then
          S.bound = 3 - (S.bound or 1)
          S.boundAt = t + 3 + math.random() * 2.5
          local base = S.adv or (L.e and L.e.root.CFrame.Position) or p
          local to = V(pt.x - base.X, 0, pt.z - base.Z)
          local dir = flatUnit(to, V(0, 0, -1))
          S.adv = base + dir * math.min(30, math.max(0, to.Magnitude - 10))
          S.advDir = dir
          if S.bound == 1 and L.e then act(L, "s") end
        end
        if ((k % 2 == 0) and 1 or 2) == S.bound then
          local dir = S.advDir or V(0, 0, -1)
          local rt = V(-dir.Z, 0, dir.X)
          local side = (k % 2 == 1) and -1 or 1
          local g = S.adv + rt * (side * math.ceil(k / 2) * 6) + B.pj
          B.goal, B.detour = Map.isLand(g.X, g.Z) and V(g.X, 0, g.Z) or V(S.adv.X, 0, S.adv.Z), nil
          B.navKey, B.rush = pt.id, true
        else
          B.boundHold, B.goal = true, nil
        end
        if B ~= L then B.target = L.target end
        return
      end
      S.adv = nil
      if B == L or not L or not L.e then return end
      local lcf = L.e.root.CFrame
      local fwd = flatUnit(lcf.LookVector, V(0, 0, -1))
      local slot = lcf.Position + wedge(k, fwd) + B.pj
      local d = V(slot.X - p.X, 0, slot.Z - p.Z).Magnitude
      B.target, B.navKey = L.target, L.navKey
      B.hurry = d > 25   -- 掉队了跑快点
      if d > 3 and Map.isLand(slot.X, slot.Z) then B.goal, B.detour = V(slot.X, 0, slot.Z), nil else B.goal = nil end
    else
      if B == L or not L or not L.e then return end
      if t >= (B.pjAt or 0) then
        local pa = math.random() * math.pi * 2
        B.pj = V(math.cos(pa), 0, math.sin(pa)) * (1 + math.random() * 3)
        B.pjAt = t + B.pers.shift * (0.7 + math.random() * 0.6)
      end
      local face = S.face or V(0, 0, 1)
      local rt = V(-face.Z, 0, face.X)
      local side = (k % 2 == 1) and -1 or 1
      local base = L.goal or L.e.root.CFrame.Position
      local slot = V(base.X, 0, base.Z) + rt * (side * math.ceil(k / 2) * 7) + B.pj
      local d = V(slot.X - p.X, 0, slot.Z - p.Z).Magnitude
      B.guard, B.navKey = L.guard, L.navKey
      B.hurry = d > 30
      if d > 2.5 and Map.isLand(slot.X, slot.Z) then B.goal, B.detour = V(slot.X, 0, slot.Z), nil else B.goal = nil end
    end
  end

  -- 姿势：赶路站着跑、交火时离得近蹲着走（交替掩护冲的那组站着冲）；停下打的时候按自己的习惯跪着或趴着（远的爱趴着打）；
  --   被压制的趴下（胆子大的跪着顶住；攻方要往前冲，压得更狠才趴）；
  --   守方平时有的蹲着有的站着；刚换过姿势一秒半内不来回换
  local function decideStance(B, S)
    local e = B.e
    if B.state == "boat" then return end
    local P = B.pers
    local t = now()
    local td = B.tgtPos and (B.tgtPos - e.root.CFrame.Position).Magnitude or nil
    local holding = B.boundHold or (td and (B.team == "def" or td < 60))
    local moving = (B.goal ~= nil or B.detour ~= nil) and not holding
    local want = 0
    if (B.supp or 0) > ((B.team == "atk") and 2.2 or 1.4) and P.brave < 0.75 then
      want = moving and 1 or 2
    elseif td then
      if moving then want = (td < 120 and not B.rush) and 1 or 0
      elseif td < 22 then want = 0
      elseif td > 160 and P.prone > 0.62 then want = 2
      else want = (P.prone > 0.2) and 1 or 0 end
    elseif B.boundHold then
      want = (P.prone > 0.6) and 2 or 1
    elseif B.team == "def" and not moving then
      local hot = S and t - (S.contactT or -1e9) < 20
      if hot then want = (P.prone > 0.6) and 2 or 1 else want = (P.prone > 0.7) and 1 or 0 end
    end
    if moving and want == 2 then want = 1 end   -- 趴着不赶路
    local cur = e.stance or 0
    if want ~= cur and (t - (B.stanceT or 0) > 1.5 or moving) then
      if want == 2 or cur == 2 then B.fireAt = math.max(B.fireAt or 0, t + 0.7) end   -- 趴下 / 起身那一下打不了枪
      setStance(B, want)
    end
  end

  -- 扔手雷：带着雷、敌人在 20～85 格（扔得到又炸不到自己）、不在换弹；目标躲在东西后面（刚才连着打不中）更想扔，胆子大的多扔
  local function tryNade(B)
    local e = B.e
    if not NADE or (B.nades or 0) <= 0 or not B.tgtPos or B.state == "boat" or (e.stance or 0) == 2 then return end
    local p = e.root.CFrame.Position
    local d = V(B.tgtPos.X - p.X, 0, B.tgtPos.Z - p.Z).Magnitude
    if d < 20 or d > 85 or now() < (B.reloadUntil or 0) then return end
    if math.random() > 0.03 + 0.05 * B.pers.brave + (((B.miss or 0) >= 3) and 0.25 or 0) then return end
    B.nades -= 1
    act(B, "g")
    B.fireAt = math.max(B.fireAt, now() + 1.5)
    local tp = B.tgtPos + V((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
    task.delay(0.62, function()   -- 客户端的扔雷动作 0.62 秒出手
      if B.e ~= e or not e.alive then return end
      local m = headOf(e) + V(0, 0.6, 0)
      local fl = V(tp.X - m.X, 0, tp.Z - m.Z)
      local dd = math.min(fl.Magnitude, NADE.range)
      local dir = (fl.Magnitude > 0.1) and fl.Unit or e.root.CFrame.LookVector
      local sp = math.clamp(math.sqrt(math.max(1, dd) * workspace.Gravity * 0.55), 20, NADE.speed)   -- 45° 抛出去落在目标附近
      G.launch({ kind = "grenade", pos = m, vel = dir * sp * 0.7071 + V(0, sp * 0.7071, 0), grav = true, fuse = NADE.fuse, w = NADE,
        src = { bot = B, team = B.team, name = B.name }, ignore = { e.model }, life = NADE.fuse + 0.5 })
    end)
  end

  local function thinkConq(B)
    local e = B.e
    local p = e.root.CFrame.Position
    local s = B.target and pointState(B.target)
    -- 目标拿下了、又没人来抢：守一会儿（20～45 秒）再挑下一个
    if s and s.owner == B.team and not s.pressed then
      B.holdUntil = B.holdUntil or (now() + 20 + math.random() * 25)
      if now() >= B.holdUntil then
        B.holdUntil = nil
        local q = conqPick(B.team, p, B)
        if q and q.id ~= B.target then B.target, B.goal = q.id, nil end
      end
    elseif not s then
      local q = conqPick(B.team, p, B)
      B.target, B.goal = q and q.id or nil, nil
    else
      B.holdUntil = nil
    end
    local pt = pointById(B.target)
    if not pt then return end
    if farHop(B, pt) then return end
    local dx, dz = p.X - pt.x, p.Z - pt.z
    local inside = dx * dx + dz * dz < (Map.POINT_R * 0.8) ^ 2
    B.navKey = pt.id
    if not B.goal and not B.detour then
      if inside then
        if not B.arrived or now() - B.arrived > 8 + math.random() * 10 then B.goal = spotNear(pt.x, pt.z, 5, Map.POINT_R * 0.75) end
      else
        B.goal = spotNear(pt.x, pt.z, 5, 45)
      end
    end
  end

  local function think(B)
    local battle = G.round and G.round.phase == "battle"
    local S = B.sq
    if S and (not S.lead or not S.lead.e or S.lead.sq ~= S) then   -- 队长没了：下一个顶上
      S.lead = nil
      for _, x in ipairs(S.m) do if x.e and x.e.alive then S.lead = x break end end
    end
    if battle then
      local c = findTarget(B)
      if c and (not B.tgt or B.tgt.P ~= c.P or B.tgt.bot ~= c.bot) then
        -- 新目标：反应一下（每人快慢不一样；小队里已经有人在打了的快一些）
        local alert = S ~= nil and now() - (S.contactT or -1e9) < 6
        B.fireAt = math.max(B.fireAt, now() + BC.reaction * (0.6 + math.random() * 0.8) * B.pers.react * (alert and 0.6 or 1))
      end
      B.tgt = c
      if c and S then
        S.contactT = now()
        S.contactP = targetPos(c) or S.contactP
      end
    else
      B.tgt = nil
    end
    B.supp = (B.supp or 0) * 0.8
    if not S or S.lead == B or not S.lead then
      if conquestOn() then thinkConq(B)
      elseif B.team == "atk" then thinkAtk(B) else thinkDef(B) end
      if S and B.team == "def" and B.e and not conquestOn() then
        -- 阵地朝哪：在打的话朝敌人，不然朝来敌的方向（离据点最近的登陆滩）
        local pt = pointById(B.guard)
        if S.contactP and now() - (S.contactT or -1e9) < 20 then S.face = flatUnit(S.contactP - B.e.root.CFrame.Position, S.face or V(0, 0, 1))
        elseif pt then S.face = threatDir(pt) end
      end
    end
    if B.e and S then squadMove(B, S) end
    if B.e then
      if battle then tryNade(B) end
      decideStance(B, S)
      unstick(B)
    end
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
    local ready = { atk = {}, def = {} }
    for _, B in ipairs(table.clone(list)) do
      if B.e and not B.e.alive then
        B.e = nil
        leaveSquad(B)
      end
      if not B.e then
        if B.state ~= "boat" and not B.leaving and t >= (B.respawnAt or 0) then
          if (phase == "prep" or phase == "battle") and (B.team == "def" or ((G.round and G.round.tickets) or 1) > 0) then
            B.readyT = B.readyT or t
            table.insert(ready[B.team], B)
          end
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
          -- 枪口俯仰给客户端（端枪瞄准的角度，3° 一档，变了才发）；没目标了收掉（客户端过一会儿放低枪口）
          if B.tgtPos then
            local d = B.tgtPos - headOf(B.e)
            local a = math.floor(math.deg(math.atan2(d.Y, math.max(V(d.X, 0, d.Z).Magnitude, 1))) / 3 + 0.5) * 3
            if a ~= B.aimSent then
              B.aimSent = a
              B.e.model:SetAttribute("Aim", a)
            end
          elseif B.aimSent then
            B.aimSent = nil
            B.e.model:SetAttribute("Aim", nil)
          end
          -- 交火：守方一直站住打；攻方 300 格以内边走边打（走慢点）、贴脸（60 格以内）才站住——地图放大到 3 倍以后，
          --   原来「150 格以内站住打」让攻方停在据点外两三百格对射，一直冲不进圈；再远照常走、偶尔打几枪
          --   小队交替掩护：停下的那一组原地打（boundHold），冲的那一组快一点（rush）；掉队的跑快点（hurry）
          local td = B.tgtPos and (B.tgtPos - B.e.root.CFrame.Position).Magnitude or 1e9
          if B.tgtPos and phase == "battle" and t >= B.fireAt then
            fire(B, B.tgtPos)
            if td > 300 then B.fireAt += BC.fireGap * 2 end
          end
          local hold = (B.tgtPos and (B.team == "def" or td < 60)) or B.boundHold
          if not hold then
            local slow = B.rush and 0.9 or ((td < 300) and 0.5 or 1)
            walk(B, dt, slow * (B.hurry and 1.25 or 1))
          elseif B.tgtPos then
            local p = B.e.root.CFrame.Position
            local look = V(B.tgtPos.X - p.X, 0, B.tgtPos.Z - p.Z)
            if look.Magnitude > 0.1 then G.moveEnt(B.e, CFrame.lookAt(p, p + look)) end
          end
        end
      end
    end
    -- 等着出生的凑成小队一起出来：凑够一队、或者等最久的那个等了 5 秒（准备阶段 2.5 秒）
    for team, R in pairs(ready) do
      table.sort(R, function(x, y) return x.readyT < y.readyT end)
      while #R > 0 do
        if #R < SQ and t - R[1].readyT < ((phase == "prep") and 2.5 or 5) then break end
        local g = {}
        for _ = 1, math.min(SQ, #R) do table.insert(g, table.remove(R, 1)) end
        local ok, res = G.try("小队出生", spawnSquad, team, g)
        if not ok or not res then
          for _, B in ipairs(g) do if not B.e then B.respawnAt = t + 2 end end
          break
        end
      end
    end
  end

  -- 测试用：现有的机器人全收掉（把每队人数设成 0 之前开局刷出来的那些也收掉）
  function G.botsClear()
    for _, B in ipairs(list) do despawn(B) end
    list = {}
    squads = {}
  end

  -- 新一局：机器人全清掉，记录（战绩）清零，重新按人数补
  G.on("roundStart", function()
    for _, B in ipairs(list) do despawn(B) end
    list = {}
    squads = {}
    focus, focusAt = nil, 0
    serial = { atk = 0, def = 0 }
    balance()
  end)
  G.on("roundEnd", function()
    for _, B in ipairs(list) do B.tgt = nil end
  end)
end

return Bots
