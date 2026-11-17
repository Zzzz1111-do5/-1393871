-- Roblox全面大战场——回合：分队、部署（装备栏 + 出生点）、出生与复活、5 个据点的占领、时间与加时、胜负、得分、结算
--   一局：准备（Config.Round.prep 秒；阵营进服时自己选，真人多的一边进不去）→ 战斗（20 分钟，攻方每拿下一个据点 +3 分钟）→ 结算 → 开下一局（不打乱分队，各自留在选的阵营）
--   胜负：攻方拿下全部 5 个 → 攻方赢；时间到守方手里还有任何一个 → 守方赢（到点时有据点正在被占：加时到占领中断或成功，最多 90 秒）
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

  local R = { phase = "boot", t0 = 0, endsAt = 0, over = nil, winner = nil, n = 0 }
  G.round = R
  local points = {}   -- [id] = { id, x, z, y, owner, prog, locked, atk, def, pressed }
  G.points = points
  local now = os.clock

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

  -- 出生点：{ id, kind, x, z, ok }；每队能选哪些、现在能不能用
  local function spawnList(team, P)
    local out = {}
    if team == "atk" then
      table.insert(out, { id = "fleet", kind = "fleet", ok = true })   -- 两栖攻击舰甲板（直升机生成点）
      table.insert(out, { id = "cv", kind = "cv", ok = true })   -- 航母甲板（舰载机生成点）
      table.insert(out, { id = "barge", kind = "barge", ok = true })   -- 登陆平台（地面载具生成点）
      table.insert(out, { id = "af2", kind = "af2", x = Map.AFIELD2.x, z = Map.AFIELD2.z, ok = true })   -- 攻方机场岛（陆基飞机生成点）
      for _, b in ipairs(Map.LANDINGS) do table.insert(out, { id = "beach." .. b.id, kind = "beach", beach = b.id, x = b.cx, z = b.z, ok = R.phase == "battle" }) end
      for _, p in ipairs(Map.POINTS) do
        local s = points[p.id]
        if s and s.owner == "atk" then table.insert(out, { id = "point." .. p.id, kind = "point", point = p.id, x = p.x, z = p.z, ok = true }) end
      end
      table.insert(out, { id = "para", kind = "para", ok = R.phase == "battle" and now() >= ((P and P.paraCd) or 0) })
    else
      table.insert(out, { id = "camp", kind = "camp", x = Map.CAMP.x, z = Map.CAMP.z, ok = true })
      for _, p in ipairs(Map.POINTS) do
        local s = points[p.id]
        if s and s.owner == "def" then table.insert(out, { id = "point." .. p.id, kind = "point", point = p.id, x = p.x, z = p.z, ok = not s.pressed }) end
      end
    end
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
      return CFrame.new(0, 40, 2150)
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
    elseif sp.kind == "point" then
      local p = standAt(sp.x, sp.z, 30)
      return CFrame.lookAt(p, p + face)
    elseif sp.kind == "camp" then
      local p = standAt(sp.x, sp.z, 40)
      return CFrame.lookAt(p, p + face)
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
  local function kitFromLoadout(L)
    if type(L) ~= "table" then return nil end
    local list, pick = {}, {}
    for _, slot in ipairs(Config.Loadout) do
      local v = L[slot.id]
      if v == nil or v == "" or v == false then
        v = (not slot.none) and slot.opts[1] or nil
      elseif type(v) ~= "string" or not table.find(slot.opts, v) then
        return nil
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
    local kit = (type(choice) == "string") and kitFromRole(choice) or kitFromLoadout(choice)
    if not kit then return end
    local sp = nil
    for _, s in ipairs(spawnList(P.team, P)) do if s.id == spawnId then sp = s end end
    if not sp or not sp.ok then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
    local PREP_OK = { fleet = true, cv = true, barge = true, af2 = true, camp = true, point = true }   -- 准备阶段只能在自己的后方出生（不能先上滩、先跳伞）
    if R.phase == "prep" and not PREP_OK[sp.kind] then G.msg(P.pl, "bad", "ui.spawnBlocked") return end
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
    if src and src.P and src.P.pl then G.R.Msg:FireClient(src.P.pl, "hit", (hum.Health <= 0) and "kill" or ((part and part.Name == "Head") and "head" or "hit")) end
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
  local function countIn(s)
    local a, d = 0, 0
    local who = {}
    local r2 = CC.r * CC.r
    for _, P in pairs(G.P) do
      if P.alive and P.char then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        local hum = P.char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 and not (P.vehicle and (P.vehicle.air or P.vehicle.sea)) then
          local p = hrp.Position
          local dx, dz = p.X - s.x, p.Z - s.z
          if dx * dx + dz * dz < r2 and math.abs(p.Y - s.y) < 45 then
            if P.team == "atk" then a += 1 else d += 1 end
            table.insert(who, P)
          end
        end
      end
    end
    if G.countAt then
      local ba, bd = G.countAt(s.x, s.z, s.y, CC.r)
      a += ba
      d += bd
    end
    return a, d, who
  end

  local function capRate(diff)
    if diff <= 0 then return 0 end
    if diff >= 3 then return 1 / CC.fast end
    local mid = 2 / (CC.slow + CC.fast)   -- 多 2 人：两头之间
    return (diff == 1) and (1 / CC.slow) or mid
  end

  local function captured(s, who)
    s.owner, s.prog, s.locked = "atk", 1, true
    paint(s)
    R.endsAt += RC.perCapture
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
  end

  local function capStep(dt)
    for _, p in ipairs(Map.POINTS) do
      local s = points[p.id]
      if not s.locked then
        local a, d, who = countIn(s)
        s.atk, s.def = a, d
        s.pressed = a > 0
        local old = s.prog
        if a > d then
          s.prog = math.min(1, s.prog + capRate(a - d) * dt)
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
    R.endsAt = now() + RC.battle
    R.overtimeEnds = nil
    G.msgAll("center", "ui.goalAtk")
    G.pushAll()
  end

  local function finish(winner)
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
      local allAtk = true
      for _, s in pairs(points) do if s.owner ~= "atk" then allAtk = false end end
      if allAtk then
        finish("atk")
      elseif t >= R.endsAt then
        local active = false   -- 有据点正在被占（攻方人多、进度在涨）：加时
        for _, s in pairs(points) do if not s.locked and s.prog > 0 and s.atk > s.def then active = true end end
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
      table.insert(out, { id = s.id, owner = s.owner, prog = math.floor(s.prog * 100 + 0.5) / 100, atk = s.atk, def = s.def, locked = s.locked })
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
