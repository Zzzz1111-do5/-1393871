-- Roblox全面大战场——回合：分队、部署（装备栏 + 出生点）、出生与复活、据点的占领、阶段与兵力、胜负、得分、结算
--   一局：准备（Config.Round.prep 秒；阵营进服时自己选，真人多的一边进不去）→ 战斗 → 结算 → 开下一局（不打乱分队，各自留在选的阵营）
--   分阶段突破（Config.Stages）：同时只能占当前阶段的据点（抢滩 A → 港口 C + 机场 D → 指挥部 E；灯塔岛 B 是第二阶段起开放的侧翼），
--     打下这一阶段的全部据点就进下一阶段（补兵力、重新计时，出生点跟着往前）；攻方有兵力（每阵亡一个扣 1，Config.Tickets）
--   胜负：打下最后一个阶段 → 攻方赢；兵力扣光、或者这一阶段时间到 → 守方赢（有据点正在被占：加时到占领中断或成功，最多 90 秒）
--   据点被攻方拿下后锁定，守方夺不回去
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Round = {}

function Round.init(G)
  local Config, Map = G.Config, G.Map
  local V = Vector3.new
  local RC, CC = Config.Round, Config.Capture

  -- 两支队（Roblox 自带的队伍：聊天里名字带颜色、头顶名字只给队友看）
  local TEAM = {}
  for _, id in ipairs({ "atk", "def" }) do
    local t = Teams:FindFirstChild(id) or Instance.new("Team")
    t.Name = (id == "atk") and "Attackers" or "Defenders"
    t.TeamColor = BrickColor.new(Config.Teams[id].brick)
    t.AutoAssignable = false
    t:SetAttribute("Side", id)
    t.Parent = Teams
    TEAM[id] = t
  end
  G.TEAM = TEAM

  local R = { phase = "boot", t0 = 0, endsAt = 0, over = nil, winner = nil, n = 0, stage = 1, tickets = 0, ticketsMax = 0 }
  G.round = R
  local points = {}   -- [id] = { id, x, z, y, owner, prog, locked, atk, def, pressed }
  G.points = points
  local now = os.clock

  -- 阶段：每个据点属于第几阶段、是不是侧翼（没写进 Config.Stages 的据点一直开着）
  local STAGES = Config.Stages or { { id = "all", points = { "A", "B", "C", "D", "E" }, time = RC.battle } }
  local stageOf, flankOf = {}, {}
  for i, st in ipairs(STAGES) do
    for _, id in ipairs(st.points) do stageOf[id] = i end
    for _, id in ipairs(st.flank or {}) do
      if not stageOf[id] then stageOf[id], flankOf[id] = i, true end
    end
  end
  G.stageOf, G.flankOf, G.STAGES = stageOf, flankOf, STAGES
  -- 现在能不能占：当前阶段的、开放了的侧翼，还没被拿下
  --   用户（交战区）：同一时间只开一个交战区——没排进阶段的据点（灯塔岛 B）一直不开放
  local function isActive(s)
    if not s or s.locked then return false end
    local k = stageOf[s.id]
    if not k then return false end
    if flankOf[s.id] then return R.stage >= k end
    return k == R.stage
  end
  function G.pointActive(id) return isActive(points[id]) end
  -- 当前阶段要打的据点（Map.POINTS 那一项；withFlank 连侧翼）
  local function objectives(withFlank)
    local out = {}
    for _, p in ipairs(Map.POINTS) do
      local s = points[p.id]
      if isActive(s) and (withFlank or not flankOf[p.id]) then table.insert(out, p) end
    end
    return out
  end
  G.objectives = objectives
  -- 用户（交战区）：出生点跟着战线走——攻方在离目标 Config.StageOff 格（200～300）的攻击出发阵地出生，守方在目标后面
  --   Config.RallyBack 格（150～250）的集结点出生；每处算几个备选位置，对方在附近就换下一个（不出生在敌人脸上）
  local rally = {}   -- [据点] = { {x, z}, … }（在攻方来向的反方向，下面和出发阵地一起算）
  G.rallyOf = function(id) return rally[id] and rally[id][1] end
  local FD = require(game:GetService("ReplicatedStorage"):WaitForChild("FortDefs"))
  local bunkers = {}
  for _, f in ipairs(FD.layout(Map)) do
    if f.kind == "bunker" then
      local d = FD.D.bunker
      local pos, lv = f.cf.Position, f.cf.LookVector   -- −Z 朝前
      table.insert(bunkers, { x = pos.X, y = pos.Y + d.turret.pivot.Y, z = pos.Z, fx = lv.X, fz = lv.Z, r = d.sight, cosArc = math.cos(math.rad(d.turret.arc + 12)) })
    end
  end
  local function covered(x, z)
    local y = Map.ground(x, z) + 3
    for _, b in ipairs(bunkers) do
      local dx, dz = x - b.x, z - b.z
      local d = math.sqrt(dx * dx + dz * dz)
      if d < b.r + 40 and d > 1 then
        local fl = math.max(1e-3, math.sqrt(b.fx * b.fx + b.fz * b.fz))
        if (dx * b.fx + dz * b.fz) / (d * fl) > b.cosArc and Map.lineClear(V(b.x, b.y, b.z), V(x, y, z), 12) then return true end
      end
    end
    return false
  end
  local staging = {}   -- [据点] = { {x, z}, … }（好的在前；都在机枪碉堡射界里时才用射界里的）
  local OFF = Config.StageOff or 260
  local BACK = Config.RallyBack or 200
  for _, p in ipairs(Map.POINTS) do
    local k = stageOf[p.id]
    if k and not flankOf[p.id] then
      -- 攻方来的方向：同一块陆地上前面阶段的据点；没有就是最近的登陆点；再没有就是南边（攻方从南边的海上来）
      local fx, fz, fd = nil, nil, math.huge
      for _, q in ipairs(Map.POINTS) do
        if stageOf[q.id] and stageOf[q.id] < k and not flankOf[q.id] and q.land == p.land then
          local d = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
          if d < fd then fx, fz, fd = q.x, q.z, d end
        end
      end
      if not fx then
        for _, b in ipairs(Map.LANDINGS) do
          if (b.isle or "main") == p.land then
            local d = math.sqrt((b.cx - p.x) ^ 2 + (b.z - p.z) ^ 2)
            if d < fd then fx, fz, fd = b.cx, b.z, d end
          end
        end
      end
      local ux, uz = 0, 1
      if fx and fd > 1 then ux, uz = (fx - p.x) / fd, (fz - p.z) / fd end
      local good, bad = {}, {}
      for _, ang in ipairs({ 0, 25, -25, 50, -50, 75, -75, 100, -100 }) do
        local a = math.rad(ang)
        local dx, dz = ux * math.cos(a) - uz * math.sin(a), ux * math.sin(a) + uz * math.cos(a)
        for _, r in ipairs({ OFF, OFF - 40, OFF + 30, 210, 290 }) do
          local x, z = p.x + dx * r, p.z + dz * r
          if Map.isLand(x, z) and Map.landOf(x, z) == p.land and Map.slope(x, z) < 0.9 then
            table.insert(covered(x, z) and bad or good, { x = x, z = z })
            break
          end
        end
      end
      for _, c in ipairs(bad) do table.insert(good, c) end
      staging[p.id] = (#good > 0) and good or nil
      -- 守方集结点：反方向（据点后面）150～250 格
      local rs = {}
      for _, ang in ipairs({ 0, 30, -30, 60, -60, 90, -90 }) do
        local a = math.rad(ang)
        local dx, dz = -(ux * math.cos(a) - uz * math.sin(a)), -(ux * math.sin(a) + uz * math.cos(a))
        for _, r in ipairs({ BACK, BACK - 30, BACK + 40, 160, 240 }) do
          local x, z = p.x + dx * r, p.z + dz * r
          if Map.isLand(x, z) and Map.landOf(x, z) == p.land and Map.slope(x, z) < 0.9 then
            table.insert(rs, { x = x, z = z })
            break
          end
        end
      end
      rally[p.id] = (#rs > 0) and rs or { { x = p.x, z = p.z - 120 } }
    else
      rally[p.id] = { { x = p.x, z = p.z - 120 } }
    end
  end
  G.stagingCovered = covered
  G.stagingOf = function(id) return staging[id] and staging[id][1] end

  ---------------------------------------------------------------- 队伍人数、分队

  local function teamCount(team, realOnly)
    local n = 0
    for _, P in pairs(G.P) do if P.team == team then n += 1 end end
    if not realOnly and G.botCount then n += G.botCount(team) end
    return n
  end
  G.teamCount = teamCount

  local function setTeam(P, team)
    P.team = team
    P.pl.Team = TEAM[team]
    P.pl.Neutral = false
    P.pl:SetAttribute("Side", team)   -- 客户端认敌我用（锁定、血条）
  end

  -- 新来的人先放到真人少的一方（临时的），进服先看选阵营界面：自己选解放军（攻）还是美军（守）
  local function pickTeam()
    local a, d = teamCount("atk", true), teamCount("def", true)
    if a < d then return "atk" elseif d < a then return "def" end
    return (math.random() < 0.5) and "atk" or "def"
  end

  -- 能不能进这一队：不算自己，这一队的真人不比另一队多（人多的一边「人数已满」）
  local function canJoin(P, team)
    if team ~= "atk" and team ~= "def" then return false end
    local other = (team == "atk") and "def" or "atk"
    local a, b = teamCount(team, true), teamCount(other, true)
    if P.team == team then a -= 1 elseif P.team == other then b -= 1 end
    return a <= b
  end
  G.canJoin = canJoin
  -- 选阵营（解放军 = 攻、美军 = 守）：没出生的时候才能选 / 换；开新一局不再打乱，各自留在自己选的阵营
  function G.ACT.pickTeam(P, team)
    if P.alive or not canJoin(P, team) then
      if not P.alive and (team == "atk" or team == "def") and P.team ~= team then G.msg(P.pl, "bad", "ui.teamFull") end
      if P.team == team then P.picked = true G.pushOne(P) end
      return
    end
    setTeam(P, team)
    P.picked = true
    G.pushAll()
  end

  ---------------------------------------------------------------- 出生点

  -- (x, z) 附近 r 格内有没有 team 一方的人（玩家、机器人、地面载具）：集结点、出发阵地有敌人就不能出生，免得出生就被打
  local function hotFor(team, x, z, r)
    local r2 = r * r
    for _, Q in pairs(G.P) do
      if Q.team == team and Q.alive and Q.char then
        local hrp = Q.char:FindFirstChild("HumanoidRootPart")
        if hrp and (hrp.Position.X - x) ^ 2 + (hrp.Position.Z - z) ^ 2 < r2 then return true end
      end
    end
    if G.countAt then
      local a, d = G.countAt(x, z, Map.ground(x, z), r)
      if ((team == "atk") and a or d) > 0 then return true end
    end
    return false
  end
  -- 集结点现在能用的那一个（攻方 120 格以内没人）
  local function rallyFree(id)
    for _, c in ipairs(rally[id] or {}) do
      if not hotFor("atk", c.x, c.z, 120) then return c end
    end
    return nil
  end
  -- 第一波：准备阶段和开战后 Config.FirstWave 秒（第一阶段）能坐登陆艇抢滩；之后只能在攻击出发阵地出生
  local function firstWave()
    if R.phase == "prep" then return true end
    return R.phase == "battle" and R.stage == 1 and now() - (R.battleAt or 0) < (Config.FirstWave or 45)
  end
  G.firstWave = firstWave
  -- 攻击出发阵地现在能不能用（AI 车出生也看这个）：开战了、过了第一波、据点是当前阶段的目标；守方 150 格以内没人的那一个
  local function stagingOk(id)
    local list = staging[id]
    if not list or R.phase ~= "battle" or flankOf[id] or not isActive(points[id]) or firstWave() then return nil end
    for _, c in ipairs(list) do
      if not hotFor("def", c.x, c.z, 150) then return c end
    end
    return nil
  end
  G.stagingOk = stagingOk

  -- 推荐的出生点（部署界面默认选中、快速加入去的）：离当前要打 / 要守的据点最近的——攻方是登陆点、拿下的据点；守方是据点本身（没被压着）、集结点
  local function recommend(team, list)
    local objs = objectives(false)
    local best, bd = nil, math.huge
    for _, s in ipairs(list) do
      local kindOk = (team == "atk" and (s.kind == "beach" or s.kind == "staging")) or (team == "def" and (s.kind == "point" or s.kind == "rally"))
      if s.ok and s.x and kindOk then
        for _, o in ipairs(objs) do
          local d = math.sqrt((s.x - o.x) ^ 2 + (s.z - o.z) ^ 2)
          if s.kind == "point" and team == "def" then   -- 守方：当前阶段的据点没被压着就去据点（后方的据点不推荐）
            d = (G.pointActive(s.point) and (d - 200)) or math.huge
          elseif s.kind == "staging" then   -- 攻方：出发阵地直接在前线（登陆点还要坐艇）
            d -= 250
          end
          if d < bd then best, bd = s, d end
        end
      end
    end
    if not best then
      for _, s in ipairs(list) do
        if s.ok and ((team == "atk" and s.kind == "barge") or (team == "def" and s.kind == "camp")) then best = s end
      end
    end
    if best then best.rec = true end
  end

  -- 出生点：{ id, kind, x, z, ok, rec }；每队能选哪些、现在能不能用、推荐哪个（离当前目标最近的）
  --   攻方的登陆点只列当前目标所在的那块陆地上的；守方的集结点只给当前阶段的据点。自己手里的据点都能出生（守方的机场 D 是飞机基地）
  local function spawnList(team, P)
    -- 用户（交战区）：区外不能出生——步兵只能在当前交战区出生（攻方：第一波的登陆艇、攻击出发阵地、空降；守方：据点本身、后方集结点）；
    --   舰艇、航母、登陆平台、机场、营地是开载具 / 飞机的地方，照旧能去（攻方拿下的据点、守方后方别的据点不能再出生）
    local out = {}
    local objs = objectives(false)
    if team == "atk" then
      table.insert(out, { id = "fleet", kind = "fleet", ok = true })   -- 两栖攻击舰甲板（直升机生成点）
      table.insert(out, { id = "cv", kind = "cv", ok = true })   -- 航母甲板（舰载机生成点）
      table.insert(out, { id = "barge", kind = "barge", ok = true })   -- 登陆平台（地面载具生成点）
      table.insert(out, { id = "af2", kind = "af2", x = Map.AFIELD2.x, z = Map.AFIELD2.z, ok = true })   -- 攻方机场岛（陆基飞机生成点）
      if firstWave() then   -- 第一波：坐登陆艇抢滩（准备阶段上艇，开战一起冲）
        local lands = {}
        for _, p in ipairs(objs) do lands[p.land] = true end
        for _, b in ipairs(Map.LANDINGS) do
          if lands[b.isle or "main"] then table.insert(out, { id = "beach." .. b.id, kind = "beach", beach = b.id, x = b.cx, z = b.z, ok = true }) end
        end
      end
      for _, p in ipairs(objs) do   -- 攻击出发阵地：离目标 200～300 格
        local list = staging[p.id]
        if list then
          local c = stagingOk(p.id)
          local sp = c or list[1]
          table.insert(out, { id = "stage." .. p.id, kind = "staging", point = p.id, x = sp.x, z = sp.z, ok = c ~= nil })
        end
      end
      table.insert(out, { id = "para", kind = "para", ok = R.phase == "battle" and now() >= ((P and P.paraCd) or 0) })
    else
      table.insert(out, { id = "camp", kind = "camp", x = Map.CAMP.x, z = Map.CAMP.z, ok = true })   -- 后方营地（地面载具、直升机）
      local D = points.D
      if Map.AIRFIELD and D and D.owner == "def" then   -- 守方机场（战斗机）：机场 D 还在手里
        table.insert(out, { id = "afield", kind = "afield", x = Map.AIRFIELD.x, z = Map.AIRFIELD.z, ok = true })
      end
      for _, p in ipairs(objs) do
        local s = points[p.id]
        if s and s.owner == "def" then
          table.insert(out, { id = "point." .. p.id, kind = "point", point = p.id, x = p.x, z = p.z, ok = not s.pressed })
          local c = rallyFree(p.id)
          local rp = c or rally[p.id][1]
          table.insert(out, { id = "rally." .. p.id, kind = "rally", point = p.id, x = rp.x, z = rp.z, ok = c ~= nil })
        end
      end
    end
    recommend(team, out)
    return out
  end
  G.spawnList = spawnList

  -- 在 (x, z) 附近找一块能站人的地（陆地、不太陡），避开别人
  local function standAt(x, z, spread)
    for _ = 1, 12 do
      local a, r = math.random() * math.pi * 2, math.random() * (spread or 12)
      local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
      if Map.isLand(px, pz) and Map.slope(px, pz) < 0.9 and (not G.spotClear or G.spotClear(px, pz, 1.5, 1.5, 5)) then return V(px, Map.ground(px, pz) + 3.5, pz) end
    end
    return V(x, Map.ground(x, z) + 3.5, z)
  end
  G.standAt = standAt

  local function spawnCF(P, sp)
    local face = (P.team == "atk") and V(0, 0, -1) or V(0, 0, 1)   -- 攻方朝北（岛），守方朝南（海）
    if sp.kind == "fleet" then
      local d = G.decks and G.decks[2] or (G.decks and G.decks[1])
      if d then
        local off = V((math.random() - 0.5) * d.W * 0.6, 3, (math.random() - 0.5) * d.L * 0.5)
        return CFrame.lookAt(d.cf.Position + off, d.cf.Position + off + face)
      end
      local f = Map.FLEET[2] or Map.FLEET[1]
      return CFrame.new(f.x, 40, f.z)
    elseif sp.kind == "cv" then   -- 航母：舰岛后面（右舷停机位旁边），别站在弹射器、着舰区上
      for _, d in ipairs(G.decks or {}) do
        if d.kind == "carrier" then
          local p = (d.cf * CFrame.new(44 + (math.random() - 0.5) * 6, 2, 46 + (math.random() - 0.5) * 14)).Position
          return CFrame.lookAt(p, p + V(0, 0, 1))
        end
      end
    elseif sp.kind == "barge" then   -- 登陆平台中间
      local B = Map.BARGE
      local p = V(B.x + (math.random() - 0.5) * B.W * 0.5, B.top + 3, B.z + (math.random() - 0.5) * B.L * 0.6)
      return CFrame.lookAt(p, p + face)
    elseif sp.kind == "af2" then   -- 攻方机场岛：停机坪北面
      local A = Map.AFIELD2
      local p = standAt(A.x + (math.random() - 0.5) * 120, A.z - A.wid / 2 - 120, 10)
      return CFrame.lookAt(p, p + V(0, 0, 1))
    elseif sp.kind == "afield" then   -- 守方机场：跑道北边
      local A = Map.AIRFIELD
      local p = standAt(A.x + (math.random() - 0.5) * 120, A.z - A.wid / 2 - 60, 10)
      return CFrame.lookAt(p, p + V(0, 0, 1))
    elseif sp.kind == "point" then
      local p = standAt(sp.x, sp.z, 30)
      return CFrame.lookAt(p, p + face)
    elseif sp.kind == "camp" then
      local p = standAt(sp.x, sp.z, 40)
      return CFrame.lookAt(p, p + face)
    elseif sp.kind == "rally" or sp.kind == "staging" then   -- 守方前线集结点、攻方攻击出发阵地：面朝据点
      local p = standAt(sp.x, sp.z, 25)
      local pt = nil
      for _, q in ipairs(Map.POINTS) do if q.id == sp.point then pt = q end end
      local look = pt and V(pt.x - p.X, 0, pt.z - p.Z) or face
      return CFrame.lookAt(p, p + ((look.Magnitude > 1) and look.Unit or face))
    elseif sp.kind == "beach" then   -- 没有登陆艇模块时直接站在滩上
      local p = standAt(sp.x, sp.z - 40, 40)
      return CFrame.lookAt(p, p + face)
    end
    return CFrame.new(0, 60, 0)
  end

  ---------------------------------------------------------------- 角色

  -- 角色的样子：两队不同色的迷彩上衣、队伍色臂章；名字只给队友看
  local UNIFORM = { atk = { Color3.fromRGB(150, 128, 92), Color3.fromRGB(110, 96, 70) }, def = { Color3.fromRGB(84, 104, 70), Color3.fromRGB(64, 78, 54) } }
  local function dress(P, char)
    local bc = char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
    local U = UNIFORM[P.team]
    bc.TorsoColor3 = U[1]
    bc.LeftArmColor3, bc.RightArmColor3 = U[1], U[1]
    bc.LeftLegColor3, bc.RightLegColor3 = U[2], U[2]
    bc.Parent = char
    for _, c in ipairs(char:GetChildren()) do
      if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c:Destroy() end
    end
    local arm = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
    if arm then
      local band = Instance.new("Part")
      band.Name = "Armband"
      band.Size = V(1.05, 0.35, 1.05)
      band.Color = Config.Teams[P.team].color
      band.Material = Enum.Material.Neon
      band.CanCollide, band.CanQuery, band.CanTouch, band.Massless = false, false, false, true
      band.CFrame = arm.CFrame * CFrame.new(0, 0.3, 0)
      local w = Instance.new("WeldConstraint")
      w.Part0, w.Part1 = arm, band
      w.Parent = band
      band.Parent = char
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
      hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
      hum.NameOcclusion = Enum.NameOcclusion.EnemyOcclusion
      hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
    end
    G.try("头盔夜视仪", G.helmetGear, P, char)
  end

  -- 夜战装具：头盔（两队不同色）、头盔前面的夜视仪支架和双筒夜视仪（不用时翻上去，开了翻下来，别人看得到）、
  --   头盔后面的红外频闪（平时看不见，队友开着夜视才看得见，Night.lua）
  local HELMET = { atk = Color3.fromRGB(96, 104, 72), def = Color3.fromRGB(146, 128, 96) }
  local NVG_UP, NVG_DOWN = CFrame.Angles(math.rad(-80), 0, 0), CFrame.Angles(0, 0, 0)
  function G.helmetGear(P, char)
    local head = char:FindFirstChild("Head")
    if not head then return end
    for _, a in ipairs(char:GetChildren()) do   -- 帽子类饰品摘掉（头发留着），戴头盔
      if a:IsA("Accessory") and a.AccessoryType == Enum.AccessoryType.Hat then a:Destroy() end
    end
    local hs = head.Size
    local k = math.max(hs.X, hs.Z) / 1.2   -- 按头的大小缩放（R15 头大约 1.2 格）
    local function piece(name, size, off, color, mat, shape)
      local p = Instance.new("Part")
      p.Name = name
      p.Size = size * k
      if shape then p.Shape = shape end
      p.Color = color
      p.Material = mat or Enum.Material.SmoothPlastic
      p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, true
      p.CFrame = head.CFrame * off
      local w = Instance.new("WeldConstraint")
      w.Part0, w.Part1 = head, p
      w.Parent = p
      p.Parent = char
      return p
    end
    local col = HELMET[P.team] or HELMET.def
    local shell = piece("Helmet", Vector3.new(1.42, 0.86, 1.5), CFrame.new(0, 0.42 * k, 0.04 * k), col, Enum.Material.Fabric)
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Parent = shell
    piece("HelmetRim", Vector3.new(1.46, 0.14, 1.54), CFrame.new(0, 0.08 * k, 0.04 * k), col:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
    local mount = piece("NVGMount", Vector3.new(0.34, 0.26, 0.16), CFrame.new(0, 0.42 * k, -0.74 * k), Color3.fromRGB(34, 36, 38), Enum.Material.Metal)
    -- 夜视仪：支架上一个铰链，两个镜筒（翻上 / 翻下靠改焊接的 C0）
    local body = Instance.new("Part")
    body.Name = "NVG"
    body.Size = Vector3.new(0.62, 0.2, 0.22) * k
    body.Color, body.Material = Color3.fromRGB(28, 30, 32), Enum.Material.Metal
    body.CanCollide, body.CanQuery, body.CanTouch, body.Massless = false, false, false, true
    body.CFrame = mount.CFrame * CFrame.new(0, -0.16 * k, -0.14 * k)
    body.Parent = char
    local hinge = Instance.new("Weld")
    hinge.Name = "NVGHinge"
    hinge.Part0, hinge.Part1 = mount, body
    hinge.C1 = CFrame.new(0, 0.16 * k, 0.1 * k)   -- 铰链在镜筒上沿后面
    hinge.C0 = NVG_UP
    hinge.Parent = body
    for _, sx in ipairs({ -1, 1 }) do
      local tube = Instance.new("Part")
      tube.Name = "NVGTube"
      tube.Shape = Enum.PartType.Cylinder
      tube.Size = Vector3.new(0.42, 0.24, 0.24) * k
      tube.Color, tube.Material = Color3.fromRGB(22, 24, 26), Enum.Material.Metal
      tube.CanCollide, tube.CanQuery, tube.CanTouch, tube.Massless = false, false, false, true
      tube.CFrame = body.CFrame * CFrame.new(sx * 0.17 * k, -0.06 * k, -0.12 * k) * CFrame.Angles(0, math.pi / 2, 0)
      local w = Instance.new("WeldConstraint")
      w.Part0, w.Part1 = body, tube
      w.Parent = tube
      tube.Parent = char
      local lens = Instance.new("Part")   -- 物镜：一点暗绿的反光
      lens.Name = "NVGLens"
      lens.Shape = Enum.PartType.Cylinder
      lens.Size = Vector3.new(0.03, 0.2, 0.2) * k
      lens.Color, lens.Material = Color3.fromRGB(40, 70, 52), Enum.Material.Glass
      lens.CanCollide, lens.CanQuery, lens.CanTouch, lens.Massless = false, false, false, true
      lens.CFrame = tube.CFrame * CFrame.new(-0.215 * k, 0, 0)
      local w2 = Instance.new("WeldConstraint")
      w2.Part0, w2.Part1 = tube, lens
      w2.Parent = lens
      lens.Parent = char
    end
    local ir = piece("IRStrobe", Vector3.new(0.16, 0.16, 0.16), CFrame.new(0, 0.62 * k, 0.62 * k), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
    ir.Transparency = 1
    ir.CastShadow = false
    char:SetAttribute("NVG", false)
  end
  -- 开关夜视仪：别人看到镜筒翻下来 / 翻上去
  function G.ACT.nvg(P, on)
    local char = P.char
    local body = char and char:FindFirstChild("NVG")
    local hinge = body and body:FindFirstChild("NVGHinge")
    if not hinge then return end
    hinge.C0 = (on == true) and NVG_DOWN or NVG_UP
    char:SetAttribute("NVG", on == true)
  end
  -- 开着狙击镜 / 望远镜、朝哪看：别人的客户端在他镜片上画闪光（只记两个属性；同一状态 0.12 秒内不重复记）
  function G.ACT.scope(P, on, dir)
    local char = P.char
    if not char then return end
    local t = os.clock()
    if t - (P.scopeT or 0) < 0.12 and (on == true) == (char:GetAttribute("Scoped") == true) then return end
    P.scopeT = t
    char:SetAttribute("Scoped", on == true)
    if on == true and typeof(dir) == "Vector3" and dir.X == dir.X and dir.Magnitude > 0.5 and dir.Magnitude < 2 then
      char:SetAttribute("ScopeDir", dir.Unit)
    end
  end

  local function onDied(P, char)
    if P.char ~= char then return end
    P.alive = false
    P.deaths += 1
    P.deadAt = now()
    P.canDeployAt = now() + Config.RespawnDelay
    P.vehicle = nil
    G.emit("died", P)
    -- 记功：最后一个打伤的人算击杀，最近 15 秒里打掉 30 以上的算助攻
    local log, t = P.dmgLog or {}, now()
    local killer, assists = nil, {}
    for i = #log, 1, -1 do
      local e = log[i]
      if t - e.t < 15 then
        if not killer and (e.by or e.bot) then killer = e end
      end
    end
    local sum = {}
    for _, e in ipairs(log) do
      if t - e.t < 15 and e.by and e.by ~= (killer and killer.by) then sum[e.by] = (sum[e.by] or 0) + e.amt end
    end
    for by, amt in pairs(sum) do if amt >= 30 then table.insert(assists, by) end end
    P.dmgLog = {}
    local kname = killer and killer.name or nil
    if killer and killer.by and killer.by ~= P and killer.by.team ~= P.team then
      local K = killer.by
      if G.P[K.pl] == K then
        K.kills += 1
        G.addScore(K, Config.Score.kill)
        G.msg(K.pl, "kill", "ui.youKilled", P.pl.DisplayName)
      end
    end
    for _, A in ipairs(assists) do
      if G.P[A.pl] == A and A.team ~= P.team then G.addScore(A, Config.Score.assist) end
    end
    if killer and killer.bot and killer.bot.team ~= P.team then   -- 机器人打死的
      killer.bot.k += 1
      killer.bot.s += Config.Score.kill
    end
    G.msg(P.pl, "center", kname and "ui.killedBy" or "ui.died", kname)
    if kname then G.msgAll("feed", "ui.killed", kname, P.pl.DisplayName) end
    G.pushOne(P)
  end

  -- 带什么（P.kit）：部署时选的装备栏；老的兵种名（测试、机器人）换成那个兵种原来的武器
  local function kitFromRole(id)
    local r = Config.RoleById[id]
    return r and { weapons = table.clone(r.weapons), hp = r.hp, speed = r.speed, role = id } or nil
  end
  local LAUNCH_ROLE = { rpg = "at", manpads = "aa", mortar = "mortar" }
  local function kitFromLoadout(L, P)
    if type(L) ~= "table" then return nil end
    local list, pick = {}, {}
    for _, slot in ipairs(Config.Loadout) do
      local v = L[slot.id]
      if v == nil or v == "" or v == false then
        v = (not slot.none) and slot.opts[1] or nil
      elseif type(v) ~= "string" or not table.find(slot.opts, v) then
        return nil
      end
      if v and P and G.passOkFor and not G.passOkFor(P, v) then   -- R 币解锁的（战术平板）没买：这一格空着出去
        G.msg(P.pl, "bad", "pass.locked", { k = "weapon." .. v })
        v = (not slot.none) and slot.opts[1] or nil
      end
      pick[slot.id] = v
      if v then table.insert(list, v) end
    end
    local S = Config.Soldier
    -- 战况表上的标签：按主武器、发射器挑一个
    local role = (pick.primary == "sniper" and "sniper") or LAUNCH_ROLE[pick.launcher or ""] or "rifle"
    return { weapons = list, hp = S.hp, speed = pick.launcher and S.heavy or S.speed, role = role, pick = pick }
  end
  function G.kitOf(P)
    if P.kit and P.kit.role == P.role then return P.kit end   -- 别处直接改了 P.role（测试换成观察员）就按那个兵种
    return kitFromRole(P.role) or kitFromRole("rifle")
  end

  local function onCharacter(P, char)
    P.char = char
    local hum = char:WaitForChild("Humanoid", 10)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hum or not hrp or G.P[P.pl] ~= P then return end
    local kit = G.kitOf(P)
    hum.MaxHealth = kit.hp
    hum.Health = kit.hp
    hum.WalkSpeed = kit.speed
    hum.BreakJointsOnDeath = false
    G.try("换衣服", dress, P, char)
    hum.Died:Connect(function() G.try("阵亡", onDied, P, char) end)
    char:SetAttribute("Team", P.team)
    char:SetAttribute("Role", P.role)
    if G.giveLoadout then G.try("发武器", G.giveLoadout, P) end
    local cf = P.spawnCF
    if cf then
      task.wait()
      if char.Parent then char:PivotTo(cf) end
    end
    P.alive = true
    P.spawnedAt = now()
    if P.after then
      local f = P.after
      P.after = nil
      G.try("出生后", f, P, char)
    end
    G.pushOne(P)
  end

  -- 部署：装备栏（{ primary, launcher, gadget, throw }；老的兵种名也认）和出生点
  function G.ACT.deploy(P, choice, spawnId)
    if R.phase ~= "battle" and R.phase ~= "prep" then return end
    if P.alive or now() < (P.canDeployAt or 0) then return end
    local kit = (type(choice) == "string") and kitFromRole(choice) or kitFromLoadout(choice, P)
    if not kit then return end
    local sp = nil
    for _, s in ipairs(spawnList(P.team, P)) do if s.id == spawnId then sp = s end end
    if not sp or not sp.ok then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    -- 准备阶段：后方、自己的据点和集结点；登陆艇也能上（艇在海上等着，开战一起冲滩）；不能先跳伞
    local PREP_OK = { fleet = true, cv = true, barge = true, af2 = true, camp = true, point = true, rally = true, beach = true }
    if R.phase == "prep" and not PREP_OK[sp.kind] then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    if P.team == "atk" and R.phase == "battle" and (R.tickets or 1) <= 0 then G.msg(P.pl, "bad", "ui.noTickets") return end   -- 兵力打光：攻方不能再出生
    P.lastChoice = choice   -- 快速部署照上次的装备
    P.role = kit.role
    P.kit = kit
    P.spawnId = spawnId
    P.spawnCF = spawnCF(P, sp)
    P.after = nil
    if sp.kind == "beach" and G.boardBoat then
      P.spawnCF, P.after = G.boardBoat(P, sp.beach)
    elseif sp.kind == "para" and G.paraDrop then
      P.spawnCF, P.after = G.paraDrop(P)
    end
    P.canDeployAt = now() + 2
    P.pl:LoadCharacter()
  end

  -- 快速加入（主菜单的大按钮）/ 快速部署（部署界面）：没选阵营的按人数自动分；装备照上次出击的（没有就默认）；
  --   出生在推荐的出生点（离当前目标最近）——点一下就进战场（用户：没法快速进入战局）
  function G.ACT.quickJoin(P)
    if P.alive then return end
    if not P.picked then
      local team = P.team
      if not canJoin(P, team) then team = (team == "atk") and "def" or "atk" end
      if canJoin(P, team) then setTeam(P, team) end
      P.picked = true
    end
    local list = spawnList(P.team, P)
    local sp = nil
    for _, s in ipairs(list) do if s.rec then sp = s end end
    if not sp then
      for _, s in ipairs(list) do if s.ok and not sp then sp = s end end
    end
    if not sp then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    G.ACT.deploy(P, P.lastChoice or {}, sp.id)
    G.pushAll()
  end

  -- 重新部署（H 键）：换了阶段、新目标在几公里外时，回部署界面重新挑出生点（攻击出发阵地、集结点）——不算阵亡、不扣兵力、不用等。
  --   交火中（8 秒内挨过打）、在载具里不行（不能拿来躲子弹、扔车）
  function G.ACT.redeploy(P)
    if not P.alive or not P.char or R.phase ~= "battle" then return end
    if G.inVeh and G.inVeh(P) then G.msg(P.pl, "bad", "ui.redeployVeh") return end
    local last = P.dmgLog and P.dmgLog[#P.dmgLog]
    if last and now() - last.t < 8 then G.msg(P.pl, "bad", "ui.redeployHot") return end
    local char = P.char
    P.char, P.alive, P.vehicle = nil, false, nil   -- 先断开：角色的 Died 不再算阵亡（onDied 只认 P.char）
    P.canDeployAt = now()
    P.dmgLog = {}
    if char.Parent then char:Destroy() end
    pcall(function() P.pl.Character = nil end)   -- 测试台（Lune）不能把引用属性设成 nil
    G.pushOne(P)
  end

  ---------------------------------------------------------------- 得分

  function G.addScore(P, n)
    P.score += n
    P.roundXp = (P.roundXp or 0) + n
  end
  -- 打伤一个玩家的角色（武器、爆炸、机器人都走这里）：src = { P 打人的玩家 / name 名字（机器人）, team }
  function G.hurtChar(char, amt, src, part)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or amt <= 0 then return false end
    local victim = nil
    for _, P in pairs(G.P) do if P.char == char then victim = P end end
    if victim and src and src.team == victim.team then return false end   -- 不打自己人
    if victim and R.phase ~= "battle" then return false end
    if victim then
      victim.dmgLog = victim.dmgLog or {}
      table.insert(victim.dmgLog, { t = now(), amt = amt, by = src and src.P or nil, bot = src and src.bot or nil, name = src and (src.P and src.P.pl.DisplayName or src.name) or nil })
      if #victim.dmgLog > 30 then table.remove(victim.dmgLog, 1) end
    end
    hum:TakeDamage(amt)
    local head = part ~= nil and part.Name == "Head"
    -- 打死真人是 pkill / headpkill（加分和打死小兵不一样，客户端的加分滚动按它写）
    if src and src.P and src.P.pl then G.R.Msg:FireClient(src.P.pl, "hit", (hum.Health <= 0) and (head and "headpkill" or "pkill") or (head and "head" or "hit")) end
    -- 挨打的真人：伤害从哪来（客户端在准星周围画一道红弧指过去）——开枪的人 / 小兵的位置，爆炸的话是炸点
    if victim and victim.pl then
      local ap = G.boomAt
      if ap then   -- 炸的：指向炸点
      elseif src and src.P and src.P.char then
        local h = src.P.char:FindFirstChild("HumanoidRootPart")
        ap = h and h.Position or ap
      elseif src and src.bot and src.bot.e then
        ap = src.bot.e.root.CFrame.Position
      end
      if typeof(ap) == "Vector3" then pcall(function() G.R.Msg:FireClient(victim.pl, "hurt", ap) end) end
    end
    return true
  end

  ---------------------------------------------------------------- 据点

  local function resetPoints()
    for _, p in ipairs(Map.POINTS) do
      points[p.id] = { id = p.id, x = p.x, z = p.z, y = p.y, owner = "def", prog = 0, locked = false, atk = 0, def = 0, pressed = false }
      local m = G.pointModels and G.pointModels[p.id]
      if m then m:SetAttribute("Owner", "def") m:SetAttribute("Prog", 0) end
    end
  end
  resetPoints()

  local function paint(s)
    local m = G.pointModels and G.pointModels[s.id]
    if not m then return end
    m:SetAttribute("Owner", s.owner)
    m:SetAttribute("Prog", s.prog)
    local col = Config.Teams[s.owner].color
    if s.owner == "def" and s.prog > 0 then col = col:Lerp(Config.Teams.atk.color, s.prog) end
    for _, n in ipairs({ "Ring", "Flag" }) do
      local p = m:FindFirstChild(n)
      if p then p.Color = col end
    end
  end

  -- 数圈里的人：活着的玩家（不在飞机、舰艇上）、机器人、地面载具
  -- 返回：圈里攻方、守方的人数（真人 + 机器人 + 地面载具）、圈里的真人、攻方真人数、守方真人数
  local function countIn(s)
    local a, d = 0, 0
    local who = {}
    local r2 = CC.r * CC.r
    for _, P in pairs(G.P) do
      if P.alive and P.char then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        local hum = P.char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 and not (G.inVeh(P) and (P.vehicle.air or P.vehicle.sea)) then
          local p = hrp.Position
          local dx, dz = p.X - s.x, p.Z - s.z
          if dx * dx + dz * dz < r2 and math.abs(p.Y - s.y) < 45 then
            if P.team == "atk" then a += 1 else d += 1 end
            table.insert(who, P)
          end
        end
      end
    end
    local ra, rd = a, d
    if G.countAt then
      local ba, bd = G.countAt(s.x, s.z, s.y, CC.r)
      a += ba
      d += bd
    end
    return a, d, who, ra, rd
  end

  -- 占领速度：多出来的人数（可以是小数：机器人只算 CC.botW 个人）连续地插值——多 1 人 slow 秒、多 2 人两头之间、多 3 人以上 fast 秒，不到 1 人按比例慢下去
  local function capRate(diff)
    if diff <= 0 then return 0 end
    local s1, s2, s3 = 1 / CC.slow, 2 / (CC.slow + CC.fast), 1 / CC.fast
    if diff < 1 then return s1 * diff end
    if diff < 2 then return s1 + (s2 - s1) * (diff - 1) end
    if diff < 3 then return s2 + (s3 - s2) * (diff - 2) end
    return s3
  end

  local finish   -- 下面定义（拿下最后一个阶段时要调）
  -- 这一阶段打完了：进下一阶段（补兵力、重新计时、战线前移：出生点、机器人都跟着走）；最后一个阶段打完攻方赢
  local function stageCleared()
    if R.stage >= #STAGES then
      finish("atk")
      return
    end
    R.stage += 1
    local st = STAGES[R.stage]
    R.tickets += (Config.Tickets and Config.Tickets.perStage) or 0
    R.ticketsMax = math.max(R.ticketsMax, R.tickets)
    R.endsAt = now() + (st.time or 480)
    R.overtimeEnds = nil
    R.stageAt = now()
    G.msgAll("stage", "stage." .. st.id, R.stage, #STAGES)   -- 客户端：全屏横幅（第几阶段、这一阶段打哪儿）
    G.emit("stage", R.stage, st)
  end
  local function captured(s, who)
    s.owner, s.prog, s.locked = "atk", 1, true
    paint(s)
    for _, P in ipairs(who) do
      if P.team == "atk" then
        P.caps += 1
        G.addScore(P, Config.Score.capture)
        G.msg(P.pl, "good", "ui.capturedYou", { k = "point." .. s.id })
      end
    end
    G.msgAll("center", "ui.captured", { k = "point." .. s.id })
    G.fx({ k = "capture", id = s.id })
    G.emit("captured", s)
    local TK = Config.Tickets or {}
    if flankOf[s.id] then   -- 侧翼：补兵力，不影响推进
      R.tickets += TK.flank or 0
      R.ticketsMax = math.max(R.ticketsMax, R.tickets)
      G.msgAll("good", "ui.flankTaken", { k = "point." .. s.id }, TK.flank or 0)
      return
    end
    local st = STAGES[R.stage]
    for _, id in ipairs((st and st.points) or {}) do
      local q = points[id]
      if q and not q.locked then   -- 这一阶段还有没拿下的：加一点时间
        R.endsAt += TK.extraCap or 60
        return
      end
    end
    stageCleared()
  end

  local function capStep(dt)
    for _, p in ipairs(Map.POINTS) do
      local s = points[p.id]
      if isActive(s) then
        local a, d, who, ra = countIn(s)
        s.atk, s.def = a, d
        s.pressed = a > 0
        local old = s.prog
        -- PvP（用户：进攻方登陆过快，这是 PvP，不要让 AI 带领节奏）：机器人只算 CC.botW 个人；攻方有真人在服务器上时，
        --   圈里没有攻方真人就不涨——机器人自己占不下来，节奏跟着真人走（攻方全是机器人时照样能慢慢占）
        local needReal = teamCount("atk", true) > 0
        local effA = ra + (a - ra) * (CC.botW or 1)
        if a > d and (not needReal or ra > 0) then
          s.prog = math.min(1, s.prog + capRate(effA - d) * dt)
        elseif a > d then
          -- 只有机器人压着：不涨也不退（守方得来把人清掉）
        else
          s.prog = math.max(0, s.prog - dt / CC.decay)
        end
        if s.prog >= 1 then
          captured(s, who)
        elseif math.abs(s.prog - old) > 1e-6 then
          if s.prog > 0 and old == 0 then G.msgTeam("def", "bad", "ui.losing", { k = "point." .. s.id }) end
          paint(s)
        end
      else
        s.atk, s.def, s.pressed = 0, 0, false
      end
    end
  end

  ---------------------------------------------------------------- 回合

  local function clearChars()
    for _, P in pairs(G.P) do
      if P.char and P.char.Parent then P.char:Destroy() end
      P.char, P.alive, P.vehicle = nil, false, nil
      P.canDeployAt = 0
      pcall(function() P.pl.Character = nil end)   -- 测试台（Lune）不能把引用属性设成 nil
    end
  end

  function G.roundStart()
    R.n += 1
    R.phase = "prep"
    R.t0 = now()
    R.prepEnds = now() + RC.prep
    R.winner = nil
    R.stage, R.stageAt, R.overtimeEnds = 1, now(), nil
    pcall(function() workspace:SetAttribute("DayT0", workspace:GetServerTimeNow()) end)   -- 昼夜：每局从早上开始（客户端 DayNight.lua 按这个算）
    local TK = Config.Tickets or {}
    R.tickets = (TK.start or 200) + (TK.perReal or 0) * teamCount("atk", true)   -- 准备阶段先给个数（开战时按真人数重算）
    R.ticketsMax = R.tickets
    resetPoints()
    clearChars()
    for _, P in pairs(G.P) do
      P.kills, P.deaths, P.score, P.caps, P.roundXp = 0, 0, 0, 0, 0
    end
    G.emit("roundStart")
    G.pushAll()
  end

  local function startBattle()
    R.phase = "battle"
    R.stage = 1
    R.battleAt = now()   -- 第一波（登陆艇）从这时算
    R.endsAt = now() + ((STAGES[1] and STAGES[1].time) or RC.battle)
    R.overtimeEnds = nil
    R.stageAt = now()
    -- 兵力：开局的数 + 每个真人攻方多给一点（人多的服打得久）
    local TK = Config.Tickets or {}
    R.tickets = (TK.start or 200) + (TK.perReal or 0) * teamCount("atk", true)
    R.ticketsMax = R.tickets
    G.msgAll("stage", "stage." .. ((STAGES[1] and STAGES[1].id) or "all"), 1, #STAGES)
    G.pushAll()
  end
  -- 攻方阵亡一个（真人、机器人都算）：兵力扣 1；剩 50、20 的时候喊一声
  local function ticketLoss(team)
    if team ~= "atk" or R.phase ~= "battle" then return end
    R.tickets = math.max(0, (R.tickets or 0) - 1)
    if R.tickets == 50 or R.tickets == 20 then G.msgAll("center", "ui.ticketsLow", R.tickets) end
  end
  G.on("died", function(P) ticketLoss(P.team) end)
  G.on("botDied", function(B) ticketLoss(B.team) end)

  finish = function(winner)
    if R.phase == "end" then return end
    R.phase = "end"
    R.winner = winner
    R.nextAt = now() + RC.results
    local best = nil
    for _, P in pairs(G.P) do
      G.addScore(P, (P.team == winner) and Config.Score.win or Config.Score.lose)
      if not best or P.score > best.score then best = P end
      if G.awardXp then G.try("结算经验", G.awardXp, P, P.team == winner) end
    end
    R.mvp = best and best.pl.DisplayName or nil
    G.msgAll("center", (winner == "atk") and "ui.win.atk" or "ui.win.def")
    G.emit("roundEnd", winner)
    G.pushAll()
  end

  function G.roundStep(dt)
    local t = now()
    if R.phase == "prep" then
      if t >= R.prepEnds then startBattle() end
    elseif R.phase == "battle" then
      capStep(dt)
      if R.phase == "battle" and ((R.tickets or 1) <= 0 or t >= R.endsAt) then   -- 兵力扣光、这一阶段时间到：守方赢
        local active = false   -- 有据点正在被占（攻方人多、进度在涨）：加时
        for _, s in pairs(points) do if isActive(s) and s.prog > 0 and s.atk > s.def then active = true end end
        if active then
          R.overtimeEnds = R.overtimeEnds or (t + RC.overtime)
          if t >= R.overtimeEnds then finish("def") end
        else
          finish("def")
        end
      end
    elseif R.phase == "end" then
      if t >= R.nextAt then G.roundStart() end
    end
    -- 每半秒发一次战况
    R.pushT = (R.pushT or 0) + dt
    if R.pushT >= 0.5 then
      R.pushT = 0
      G.pushAll()
    end
  end

  ---------------------------------------------------------------- 发给客户端的状态

  local function pointsState()
    local out = {}
    for _, p in ipairs(Map.POINTS) do
      local s = points[p.id]
      table.insert(out, { id = s.id, owner = s.owner, prog = math.floor(s.prog * 100 + 0.5) / 100, atk = s.atk, def = s.def, locked = s.locked,
        act = isActive(s), stage = stageOf[s.id], flank = flankOf[s.id] or nil })
    end
    return out
  end
  local function boardState()
    local list = {}
    for _, P in pairs(G.P) do
      table.insert(list, { n = P.pl.DisplayName, id = P.pl.UserId, t = P.team, k = P.kills, d = P.deaths, s = P.score, c = P.caps, r = P.role, rk = P.rank or 1 })
    end
    if G.botBoard then for _, b in ipairs(G.botBoard()) do table.insert(list, b) end end
    return list
  end
  local function common()
    local t = now()
    local left = 0
    if R.phase == "prep" then left = R.prepEnds - t elseif R.phase == "battle" then left = R.endsAt - t elseif R.phase == "end" then left = R.nextAt - t end
    return {
      phase = R.phase, left = math.max(0, math.floor(left + 0.5)), ot = R.overtimeEnds and math.max(0, math.floor(R.overtimeEnds - t + 0.5)) or nil,
      points = pointsState(), nAtk = teamCount("atk"), nDef = teamCount("def"), winner = R.winner, mvp = R.mvp, round = R.n,
      stage = R.stage, stages = #STAGES, stageId = STAGES[R.stage] and STAGES[R.stage].id, tickets = R.tickets, ticketsMax = R.ticketsMax,
      progress = G.worldReady and 1 or (G.worldProgress or 0),
    }
  end
  local function personal(P, C)
    local t = now()
    C.team = P.team
    C.round = R.n
    C.picked = P.picked == true
    C.rAtk, C.rDef = teamCount("atk", true), teamCount("def", true)   -- 选阵营界面：两边各有几个真人、能不能进
    C.canAtk, C.canDef = canJoin(P, "atk"), canJoin(P, "def")
    C.role = P.role
    C.alive = P.alive
    C.wait = math.max(0, math.ceil((P.canDeployAt or 0) - t))
    C.spawns = spawnList(P.team, P)
    if G.vehState then
      C.veh = G.vehState(P)
      C.vehAvail = G.vehAvail(P.team)
      C.vehModels = G.vehModels(P.team)   -- 生成点牌子上写的名额、冷却（Depot.lua）
    end
    C.me = { k = P.kills, d = P.deaths, s = P.score, c = P.caps, xp = P.xp or 0, rank = P.rank or 1, gain = P.roundXp or 0 }
    if G.tacState then C.tac = G.tacState(P) end   -- 战术平板：每样还剩几次、冷却（Tactical.lua）
    return C
  end
  function G.pushOne(P)
    if G.P[P.pl] ~= P then return end
    G.R.State:FireClient(P.pl, personal(P, common()))
  end
  function G.pushAll()
    local C = common()
    local board = nil
    R.boardT = (R.boardT or 0) + 1
    if R.boardT >= 4 or R.phase == "end" then   -- 战况表两秒一次
      R.boardT = 0
      board = boardState()
    end
    for _, P in pairs(G.P) do
      local c = table.clone(C)
      G.R.State:FireClient(P.pl, personal(P, c))
    end
    if board then G.R.Board:FireAllClients(board) end
  end

  ---------------------------------------------------------------- 进出

  local function onPlayer(pl)
    if G.P[pl] then return end
    local P = { pl = pl, kills = 0, deaths = 0, score = 0, caps = 0, roundXp = 0, alive = false, canDeployAt = 0, dmgLog = {} }
    G.P[pl] = P
    setTeam(P, pickTeam())
    pl.CharacterAdded:Connect(function(char) G.try("出生", onCharacter, P, char) end)
    if G.loadData then task.spawn(function() G.try("读档", G.loadData, P) end) end
    G.pushOne(P)
    task.delay(1, function()
      if G.P[pl] == P then
        for _, m in ipairs(G.bootErrors) do G.msg(pl, "bad", m) end
      end
    end)
  end
  Players.PlayerAdded:Connect(onPlayer)
  for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, pl) end
  Players.PlayerRemoving:Connect(function(pl)
    local P = G.P[pl]
    if not P then return end
    G.emit("left", P)
    if G.saveData then G.try("存档", G.saveData, P) end
    G.P[pl] = nil
  end)
end

return Round
