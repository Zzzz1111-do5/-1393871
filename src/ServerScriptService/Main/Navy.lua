-- Roblox全面大战场——舰艇（服务器）：码头和生成点、开船（位置由开船的客户端算，服务器查航速、水深、地图边）、主炮（炮弹有弹道）、
--   机枪 / 30 毫米炮（按住连发）、反舰导弹（垂发：先窜起来再掠海飞，末段扑向目标；锁定的目标或准星下的点）、
--   自动防空导弹（打敌机，热诱弹能骗走一部分）、自动近防炮（拦截飞过来的导弹、炸弹，也打近处的飞机）、
--   回自己码头停稳补弹、修理；被击沉（开船的人阵亡、名额冷却）；没人开 90 秒收走
--   生成点（走过去按住 E，生成后直接坐上舰桥）：攻方——登陆平台东南角接出的浮码头，船尾靠码头、船头朝岛；
--     守方——后方营地北边崖顶一排终端柱，船停在崖下的军港码头；港口镇木码头旁一艘巡逻艇（据点 C 在守方手里才能用）
--   AI 舰艇：攻方一艘 054A 在南面近海来回巡逻、炮击守方的岸防炮和碉堡、对敌舰发反舰导弹；守方一艘 PBR 在港湾里巡逻（据点 C 在守方手里时），打登陆艇
local RS = game:GetService("ReplicatedStorage")

local Navy = {}

function Navy.init(G)
  local Config, Map = G.Config, G.Map
  local SD = require(RS:WaitForChild("ShipDefs"))
  local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
  local now = os.clock
  local SHELL_G = workspace.Gravity * 0.55
  local CAT = Config.VehicleCats.ship
  local NORTH, SOUTH = V(0, 0, -1), V(0, 0, 1)

  local ships = {}
  G.ships = ships
  G.ShipDefs = SD   -- 测试、别的模块查型号用
  local pending = { atk = {}, def = {} }   -- 被击沉的占着名额：冷却到什么时候
  local homes = {}                         -- 补给点（码头）：{ team, p, r }
  local aiNext = { atk = 0, def = 0 }      -- AI 舰艇下次能出来的时间

  local function flat(v) return V(v.X, 0, v.Z) end
  local function angDiff(a, b) return (b - a + 180) % 360 - 180 end
  local function dropShip(e)
    for i, x in ipairs(ships) do if x == e then table.remove(ships, i) return end end
  end

  ---------------------------------------------------------------- 名额（接到载具的名额、型号表上）

  local function used(team)
    local n = 0
    for _, e in ipairs(ships) do if e.alive and e.team == team and not e.ai then n += 1 end end
    local t = now()
    local list = pending[team]
    for i = #list, 1, -1 do if list[i] <= t then table.remove(list, i) else n += 1 end end
    return n
  end
  local vehAvail0, vehModels0 = G.vehAvail, G.vehModels
  function G.vehAvail(team)
    local out = vehAvail0 and vehAvail0(team) or {}
    local cap = Config.VehicleCap("ship", G.teamCount(team))
    local u = used(team)
    local cd = 0
    if u >= cap then
      local soon = math.huge
      for _, x in ipairs(pending[team]) do soon = math.min(soon, x) end
      if soon < math.huge then cd = math.ceil(soon - now()) end
    end
    out.ship = { u = u, cap = cap, cd = cd }
    return out
  end
  function G.vehModels(team)
    local out = vehModels0 and vehModels0(team) or {}
    for _, id in ipairs(Config.Vehicles[team].ship or {}) do if SD.get(id) then table.insert(out, id) end end
    return out
  end

  ---------------------------------------------------------------- 码头（静态零件）和生成点

  local function part(parent, size, cf, color, mat, solid)
    local p = Instance.new("Part")
    p.Anchored = true
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = mat or MAT.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CanCollide, p.CanQuery, p.CanTouch = solid == true, solid == true, false
    p.CastShadow = solid == true
    p.Parent = parent
    return p
  end
  -- 一段码头：从 a 到 b（水平），宽 w，面高 top；两边黄色护轮坎、一排系船桩，下面一排桩，夜里隔一段一盏灯
  local function pier(f, a, b, w, top)
    local mid = (a + b) / 2
    local L = (b - a).Magnitude
    local cf = CFrame.lookAt(V(mid.X, top - 0.75, mid.Z), V(b.X, top - 0.75, b.Z))
    local deck = part(f, V(w, 1.5, L), cf, RGB(74, 76, 78), MAT.Concrete, true)
    deck.Name = "PierDeck"
    for s = -1, 1, 2 do
      part(f, V(0.6, 0.5, L), cf * CF(s * (w / 2 - 0.3), 1, 0), RGB(176, 150, 52), MAT.Metal)
      for k = 0, math.floor((L - 16) / 30) do
        part(f, V(1, 1.4, 1), cf * CF(s * (w / 2 - 1.4), 1.45, -L / 2 + 8 + k * 30), RGB(40, 42, 44), MAT.Metal)
      end
    end
    local n = math.max(2, math.floor(L / 36))
    local along = V(b.X - a.X, 0, b.Z - a.Z).Unit
    for i = 0, n do
      local p = a + (b - a) * (i / n)
      local pc = CFrame.lookAt(V(p.X, top - 10, p.Z), V(p.X, top - 10, p.Z) + along)
      for s = -1, 1, 2 do part(f, V(1.8, 18, 1.8), pc * CF(s * (w / 2 - 1.2), 0, 0), RGB(52, 54, 56), MAT.Concrete) end
    end
    local W = G.World
    if W and W.light then
      for i = 0, n, 2 do
        local p = a + (b - a) * (i / n)
        W.light(f, V(p.X, top + 3.4, p.Z), RGB(255, 214, 160), 0.7, 22, 1.1)
      end
    end
  end
  -- 崖下码头根上的一座升降机塔（崖顶到码头）：四根立柱、横撑、轿厢——只是样子
  local function lift(f, x, z, y0, y1)
    local h = y1 - y0
    local col = RGB(150, 128, 52)
    for _, c in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do
      part(f, V(0.7, h, 0.7), CF(x + c[1], y0 + h / 2, z + c[2]), col, MAT.Metal, true)
    end
    for y = y0 + 10, y1, 12 do
      part(f, V(6.6, 0.4, 0.4), CF(x, y, z - 3), col, MAT.Metal)
      part(f, V(6.6, 0.4, 0.4), CF(x, y, z + 3), col, MAT.Metal)
      part(f, V(0.4, 0.4, 6.6), CF(x - 3, y, z), col, MAT.Metal)
      part(f, V(0.4, 0.4, 6.6), CF(x + 3, y, z), col, MAT.Metal)
    end
    part(f, V(5, 7, 5), CF(x, y0 + 4, z), RGB(70, 74, 78), MAT.Metal, true)
    part(f, V(7.4, 1, 7.4), CF(x, y1 + 0.5, z), RGB(60, 62, 64), MAT.Metal, true)
    if G.World and G.World.light then G.World.light(f, V(x, y1 + 2, z), RGB(255, 60, 50), 0.6, nil, nil, nil, 3) end
  end

  -- 船停在码头边：船头朝 face，船尾在 stern 点（水面上）；返回生成点要的 base（船中心、水线上）
  local function berth(stern, face, L)
    local c = stern + face * (L / 2)
    return CFrame.lookAt(V(c.X, 0, c.Z), V(c.X, 0, c.Z) + face)
  end

  local built = false
  local function buildPiers()
    if built then return end
    built = true
    local root = workspace:FindFirstChild("Map") or workspace
    local f = Instance.new("Folder")
    f.Name = "Piers"
    local addPad, buildPad = G.depotAddPad, G.depotBuildPad
    local padF = root:FindFirstChild("Pads") or f
    local function pad(team, id, base, term, ty, need)
      local d = SD.get(id)
      if not d or not addPad then return end
      local p = addPad({ team = team, vid = id, kind = "ship", base = base, term = term, ty = ty, need = need, r = math.max(d.W, 24) })
      if buildPad then G.try("生成点 " .. id, buildPad, padF, p) end
      table.insert(homes, { team = team, p = base.Position, r = d.L * 0.5 + 90 })
    end
    -- 攻方：登陆平台东南角往东接一条浮码头，055、054A、022 船尾靠码头并排停着、船头朝北（直接朝岛开）；终端柱在码头上、各自船尾旁边
    local B = Map.BARGE
    local zP = B.z + B.L / 2 - 13
    local x1 = B.x + B.W / 2
    G.try("攻方码头", pier, f, V(x1 - 2, 0, zP), V(x1 + 240, 0, zP), 14, B.top)
    local x = x1 + 70
    for _, id in ipairs(Config.Vehicles.atk.ship or {}) do
      local d = SD.get(id)
      if d then
        x += d.W / 2
        pad("atk", id, berth(V(x, 0, zP - 11), NORTH, d.L), V(x + d.W / 2 + 3, 0, zP + 2), B.top)
        x += d.W / 2 + 24
      end
    end
    -- 守方：后方营地在北岸的崖顶上（高约五十格），崖下伸进北面海里一条军港码头；船船尾朝岸、船头朝北，在码头两边并排停（每条船前面都是开阔海面，
    --   不会被别的船堵住）；终端柱在营地北边崖顶上一排
    local C = Map.CAMP
    local x0 = C.x
    local z0 = Map.coastN(x0) or (C.z - 120)
    G.try("守方码头", pier, f, V(x0, 0, z0 + 6), V(x0, 0, z0 - 420), 16, 4)
    G.try("码头升降机", lift, f, x0 + 12, z0 + 3, 4, (C.y or Map.ground(C.x, C.z)) + 2)
    local sides, n = { [-1] = {}, [1] = {} }, 0
    local hasPbr = false
    for _, id in ipairs(Config.Vehicles.def.ship or {}) do
      if SD.get(id) then
        if id == "pbr" then hasPbr = true else
          n += 1
          table.insert(sides[(n % 2 == 1) and -1 or 1], id)
        end
      end
    end
    if hasPbr then table.insert(sides[1], "pbr") end   -- 巡逻艇小，排在右边最外面
    local k = 0
    for _, side in ipairs({ -1, 1 }) do
      local edge = x0 + side * (8 + 5)   -- 码头边（留 5 格水面）
      for _, id in ipairs(sides[side]) do
        local d = SD.get(id)
        k += 1
        local xs = edge + side * d.W / 2
        pad("def", id, berth(V(xs, 0, z0 - 70), NORTH, d.L), V(C.x - 90 + (k - 1) * 36, 0, C.z - 60), nil)
        edge = xs + side * (d.W / 2 + 20)
      end
    end
    -- 守方：港口镇（湾底）西边那条木码头旁停一艘巡逻艇，船头朝南（湾口）；据点 C 在守方手里才能用
    local P = Map.PORT
    local zs = Map.coastS(P.x) or P.z
    local d = SD.get("pbr")
    if d and hasPbr then pad("def", "pbr", berth(V(P.x - 70 + 9 + d.W / 2, 0, zs + 80), SOUTH, d.L), V(P.x - 70 + 3, 0, zs + 78), 2, "C") end   -- 码头里头水浅：停在外头那段
    f.Parent = root
  end
  local depotsBuild0 = G.depotsBuild
  function G.depotsBuild()
    if depotsBuild0 then depotsBuild0() end
    G.try("码头", buildPiers)
  end

  ---------------------------------------------------------------- 开船的人

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
    e.resP = nil
    e.lastSync = now()
    e.model:SetAttribute("Driver", P.pl.UserId)
    char:PivotTo(e.root.CFrame)
    G.pushOne(P)
  end
  local function cfOf(e) return e.root.CFrame * CF(0, -(e.sd.H / 2 - e.sd.draft), 0) end   -- 船（水线中心）的 CFrame

  -- 下船：离自己队的舰艇生成点近（回到码头了）——站到那根终端柱旁边；不然跳到船边的水里
  local function unseat(P, e, place)
    if P.vehicle == e then P.vehicle = nil end
    if e.driver == P then
      e.driver = nil
      e.emptyAt = now()
      e.trig = false
      e.model:SetAttribute("Driver", 0)
    end
    local char = P.char
    if char and char.Parent and place then
      hideChar(char, false)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      if hrp then hrp.Anchored = false end
      local c = cfOf(e)
      local best, bd = nil, 1e9
      for _, p in ipairs(G.pads or {}) do
        if p.kind == "ship" and p.team == e.team then
          local dd = (flat(p.base.Position) - flat(c.Position)).Magnitude
          if dd < bd then best, bd = p, dd end
        end
      end
      local pos
      if best and bd < e.sd.L * 0.5 + 120 then
        local ty = best.ty or Map.ground(best.term.X, best.term.Z)
        pos = V(best.term.X + 2, ty + 3.5, best.term.Z + 2)
      else
        pos = (c * CF(e.sd.W / 2 + 6, 1, e.sd.L * 0.2)).Position
      end
      char:PivotTo(CF(pos))
    end
    if G.P[P.pl] == P then G.pushOne(P) end
  end

  ---------------------------------------------------------------- 新船、击沉

  local function newShip(team, id, base)
    local d = SD.get(id)
    if not d then return nil end
    local e = G.newEnt({ kind = "ship", team = team, cat = "ship", hp = d.hp, size = d.size, cf = base * CF(0, d.H / 2 - d.draft, 0), solid = true,   -- 实心
      extra = { ship = true, sea = true, sd = d } })
    e.model:SetAttribute("Model", id)
    e.model:SetAttribute("Driver", 0)
    e.model:SetAttribute("Order", 0)
    e.model:SetAttribute("Sp", 0)
    e.ty, e.gp, e.next = {}, {}, {}
    for i = 1, #d.guns do
      e.ty[i], e.gp[i], e.next[i] = 0, 0, 0
      e.model:SetAttribute("Ty" .. i, 0)
      e.model:SetAttribute("Gp" .. i, 0)
    end
    e.msl = d.missiles and d.missiles.n or 0
    e.samN = d.sam and d.sam.n or 0
    e.model:SetAttribute("Msl", e.msl)
    e.model:SetAttribute("Sam", e.samN)
    e.speed = 0
    e.lastSync = now()
    e.samAt, e.ciwsT = 0, 0
    e.onDeath = function(self, src)
      G.try("舰艇被击沉", function()
        self.wreck = true
        self.model:SetAttribute("Wreck", true)
        self.root.CanQuery = false   -- 沉下去的船不再挡子弹
        if not self.ai then table.insert(pending[self.team], now() + (CAT.cd or 120)) end
        local D = self.driver
        if D then
          self.driver = nil
          D.vehicle = nil
          if D.char then
            hideChar(D.char, false)
            local hrp = D.char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Anchored = false end
            G.hurtChar(D.char, 1e5, src)
          end
          G.msg(D.pl, "bad", "ui.vehLost")
        end
        if src and src.P and G.P[src.P.pl] == src.P then G.msg(src.P.pl, "kill", "ui.vehKilled", { k = "veh." .. self.sd.id }) end
        if self.ai then aiNext[self.team] = now() + 150 end
        dropShip(self)
      end)
      task.delay(30, function() G.removeEnt(self) end)
    end
    e.step = function(self, dt)
      if self.ai and G.navyAIStep then G.navyAIStep(self, dt) end
      if G.navyDefend then G.navyDefend(self, dt) end
    end
    table.insert(ships, e)
    return e
  end

  -- 生成点生成（Depots 调）：生成的人直接坐上舰桥（船停在水里，走不上去）；30 秒内别人不能抢
  function G.spawnShip(team, id, base, P)
    local e = newShip(team, id, base)
    if not e then return nil end
    e.emptyAt = now()
    e.resP, e.resUntil = P, now() + 30
    if P and P.alive and P.char and not P.vehicle and P.team == team then seat(P, e) end
    return e
  end

  ---------------------------------------------------------------- 上船（接到上车上）：自己队没人开的船，站在船边 45 格以内（码头上、游过去）

  local enter0 = G.ACT.enterVeh
  G.ACT.enterVeh = function(P, entId)
    local e = (type(entId) == "string") and G.entById[entId] or nil
    if not e or not e.ship then
      if enter0 then return enter0(P, entId) end
      return
    end
    if not e.alive or e.ai or e.driver or e.team ~= P.team or P.vehicle or not P.alive or not P.char then return end
    if G.reservedFor and G.reservedFor(e, P) then return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local l = e.root.CFrame:PointToObjectSpace(hrp.Position)
    local dx = math.max(0, math.abs(l.X) - e.sd.W / 2)
    local dz = math.max(0, math.abs(l.Z) - e.sd.L / 2)
    if math.sqrt(dx * dx + dz * dz) > 45 then return end
    seat(P, e)
  end

  ---------------------------------------------------------------- 武器

  local function srcOf(e)
    local P = e.driver
    if P then return { P = P, team = e.team, name = P.pl.DisplayName } end
    return { team = e.team, name = { k = "veh." .. e.sd.id } }
  end
  local function ignoreOf(e)
    local list = { e.model }
    if e.driver and e.driver.char then table.insert(list, e.driver.char) end
    return list
  end

  local function fireGun(e, gi, dirOverride)
    local d = e.sd
    local g = d.guns[gi]
    local w = SD.W[g.w]
    local t = now()
    if t < (e.next[gi] or 0) then return false end
    e.next[gi] = t + w.rate
    local mzCF = SD.muzzle(d, cfOf(e), gi, e.ty[gi], e.gp[gi])
    local dir = dirOverride or mzCF.LookVector
    local mz = mzCF.Position
    if w.kind == "gun" then
      if g.twin then   -- 双联：左右两根管子轮流打
        e.twinS = -(e.twinS or 1)
        mz += mzCF.RightVector * (0.35 * e.twinS)
      end
      G.botShot(mz, mz + dir * w.range, w, srcOf(e), ignoreOf(e))
    else
      G.launch({ kind = "shell", pos = mz, vel = dir * w.speed, grav = true, gscale = w.gscale, w = w, src = srcOf(e), ignore = ignoreOf(e),
        life = w.range / w.speed * 1.8 + 1, byEnt = e.id })
      G.fx({ k = "vfire", p = mz, d = dir, f = w.fx, id = e.id, g = gi })
    end
    return true
  end
  G.navyFireGun = fireGun

  -- 反舰导弹：从垂发筒竖直窜出来（头半秒慢），然后航向朝目标转（每秒最多 w.turn 度，刚出筒时快），高度按离水面 / 地面 cruise 格掠海飞
  --   （垂直速度按高度差直接定、变化有上限：原来按转弯速度慢慢压机头，一俯冲就扎进海里或者在天上兜大圈飞过头）；离目标 600 格内直扑过去；近炸
  local function rotTo(dir, want, maxA)
    local a = math.acos(math.clamp(dir:Dot(want), -1, 1))
    if a <= maxA then return want end
    local axis = dir:Cross(want)
    if axis.Magnitude < 1e-6 then return dir end
    return (CFrame.fromAxisAngle(axis.Unit, maxA) * dir).Unit
  end
  local function guideASM(s, dt)
    s.age += dt
    local w = s.w
    local t = s.tgt
    local tp
    if t and t.alive and t.root and t.root.Parent then tp = t.root.CFrame.Position else tp = s.aimPt end
    local boost = s.age < 0.5
    local spd = boost and math.min(150, s.vel.Magnitude + 300 * dt) or math.min(w.speed, s.vel.Magnitude + w.speed * 0.8 * dt)
    local dir = s.vel.Unit
    if not boost and tp then
      local rel = tp - s.pos
      local hz = V(rel.X, 0, rel.Z)
      local turn = math.rad((s.age < 2.5) and 100 or w.turn) * dt
      if hz.Magnitude > 600 then
        local hd = V(dir.X, 0, dir.Z)
        hd = (hd.Magnitude > 0.05) and rotTo(hd.Unit, hz.Unit, turn) or hz.Unit
        local ahead = s.pos + hd * 120
        local alt = math.max(Map.height(ahead.X, ahead.Z), Map.height(s.pos.X, s.pos.Z), 0) + w.cruise
        local vyT = math.clamp((alt - s.pos.Y) * 1.6, -140, 140)
        local vy = s.vel.Y + math.clamp(vyT - s.vel.Y, -350 * dt, 350 * dt)
        vy = math.clamp(vy, -spd * 0.9, spd * 0.9)
        dir = (hd * math.sqrt(spd * spd - vy * vy) + V(0, vy, 0)).Unit
      else
        dir = rotTo(dir, rel.Unit, turn)
      end
      local fuse = 9 + ((t and t.root) and math.min(20, t.root.Size.Magnitude * 0.08) or 0)
      if rel.Magnitude < fuse then
        G.explode(s.pos, w, s.src, 1.6)
        return true
      end
    end
    s.vel = dir * spd
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.3 then
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end

  -- 发一枚反舰导弹：tgtId 锁定的敌方水面 / 地面目标（不是飞机），或者 aim 一个点（准星下的海面、地面）
  local function fireMissile(e, tgtId, aim)
    local d = e.sd
    if not d.missiles or e.msl <= 0 then return false end
    local t = now()
    if t < (e.mslAt or 0) then return false end
    local w = SD.W[d.missiles.w]
    local tgt = (type(tgtId) == "string") and G.entById[tgtId] or nil
    local p0 = e.root.CFrame.Position
    if tgt and (not tgt.alive or tgt.team == e.team or tgt.air or (tgt.root.CFrame.Position - p0).Magnitude > w.range * 1.1) then tgt = nil end
    local aimPt = nil
    if typeof(aim) == "Vector3" and aim == aim and (aim - p0).Magnitude < w.range * 1.1 then aimPt = aim end
    if not tgt and not aimPt then return false end
    e.msl -= 1
    e.mslAt = t + 1.2
    e.model:SetAttribute("Msl", e.msl)
    local pos = (cfOf(e) * CF(d.missiles.pos)).Position + V(0, 2, 0)
    G.launch({ kind = "missile", pos = pos, vel = V(0, 60, 0), w = w, src = srcOf(e), ignore = ignoreOf(e), life = w.range / w.speed + 6,
      step = guideASM, age = 0, tgt = tgt, tgId = tgt and tgt.id or nil, aimPt = aimPt, byEnt = e.id })
    G.fx({ k = "vls", p = pos, id = e.id })
    if tgt and tgt.driver and tgt.driver.pl then G.R.Drive:FireClient(tgt.driver.pl, { op = "rwr", w = "asm" }) end
    return true
  end
  G.navyFireMissile = fireMissile

  -- 防空导弹：雷达制导（热诱弹骗走一成五，Air.lua 的 flare 改 s.tgt），比例导引、转弯有上限
  local function guideSAM(s, dt)
    s.age += dt
    local w = s.w
    local t = s.tgt
    local tp
    if t and t.decoy then
      t.pos += t.vel * dt
      t.vel += V(0, -SHELL_G * 0.4, 0) * dt
      tp = t.pos
    elseif t and t.alive and t.root and t.root.Parent then
      local p = t.root.CFrame.Position
      tp = p + (t.vel or V()) * math.min(3, (p - s.pos).Magnitude / w.speed) * 0.9
    end
    local dir = s.vel.Unit
    local spd = math.min(w.speed, s.vel.Magnitude + w.speed * 1.5 * dt)
    if tp and s.age > 0.4 then
      local want = (tp - s.pos).Unit
      local a = math.acos(math.clamp(dir:Dot(want), -1, 1))
      local maxA = math.rad(75) * dt
      if a > maxA then
        local axis = dir:Cross(want)
        if axis.Magnitude > 1e-6 then dir = (CFrame.fromAxisAngle(axis.Unit, maxA) * dir).Unit end
      else
        dir = want
      end
      if (tp - s.pos).Magnitude < 14 then
        if t and t.decoy then G.fx({ k = "boom", p = s.pos, s = 0.6, c = "msl" }) return true end
        G.explode(s.pos, w, s.src, 0.9)
        return true
      end
    end
    s.vel = dir * spd
    s.fixT = (s.fixT or 0) + dt
    if s.fixT > 0.3 then
      s.fixT = 0
      G.fx({ k = "shotFix", id = s.id, p = s.pos, v = s.vel })
    end
    return false
  end

  ---------------------------------------------------------------- 自动防空：防空导弹、近防炮（所有船，有没有人开都打）

  local SAM_W = { id = "sam", kind = "aam", seeker = "radar", dmg = SD.W.sam.dmg, splash = SD.W.sam.splash, speed = SD.W.sam.speed, range = SD.W.sam.range, vs = SD.W.sam.vs }
  local CW = SD.W.ciws
  -- 这发弹是不是冲着这条船来的：敌方的导弹、炸弹（步兵火箭筒、打飞机的防空弹不算），正在靠近、会擦着船身过去
  local function incoming(e, s, cpos)
    if not s.src or s.src.team == e.team then return false end
    if s.kind ~= "missile" and s.kind ~= "bomb" then return false end
    if s.w and s.w.kind == "aam" then return false end
    local v = s.vel
    if v.Magnitude < 1 then return false end
    local rel = cpos - s.pos
    local u = v.Unit
    local ahead = rel:Dot(u)
    if ahead <= 0 then return false end
    return (rel - u * ahead).Magnitude < e.sd.L * 0.5 + 40
  end
  function G.navyDefend(e, dt)
    if not e.alive or not G.round or G.round.phase ~= "battle" then return end
    local d = e.sd
    local t = now()
    local cpos = e.root.CFrame.Position
    -- 防空导弹：最近的敌机（在天上、离海面 / 地面 15 格以上）
    if d.sam and e.samN > 0 and t >= e.samAt then
      local best, bd = nil, SD.W.sam.range
      for _, x in ipairs(G.aircraft or {}) do
        -- 刚起飞 12 秒内的不打（用户：刚起飞就被导弹打下来；Air.lua 记 upAt）
        if x.alive and x.team ~= e.team and not x.onGround and not (x.upAt and t - x.upAt < 12) then
          local p = x.root.CFrame.Position
          local dd = (p - cpos).Magnitude
          if dd < bd and p.Y - Map.ground(p.X, p.Z) > 15 then best, bd = x, dd end
        end
      end
      if best then
        e.samN -= 1
        e.samAt = t + SD.W.sam.rate
        e.model:SetAttribute("Sam", e.samN)
        local pos = (cfOf(e) * CF(d.sam.pos)).Position + V(0, 2, 0)
        G.launch({ kind = "missile", pos = pos, vel = V(0, 140, 0), w = SAM_W, src = srcOf(e), ignore = ignoreOf(e), life = SAM_W.range / SAM_W.speed + 3,
          step = guideSAM, age = 0, tgt = best, tgId = best.id, byEnt = e.id })
        G.fx({ k = "vls", p = pos, id = e.id, sam = true })
        if best.driver and best.driver.pl then G.R.Drive:FireClient(best.driver.pl, { op = "rwr", w = "sam" }) end
      end
    end
    -- 近防炮：每座盯一发冲着船来的弹，开始打的时候按概率定这一座能不能打掉（kill），打 0.8 秒见分晓；没有弹就打近处的敌机
    if not d.ciws or #d.ciws == 0 then return end
    e.ciwsT += dt
    if e.ciwsT < CW.rate then return end
    e.ciwsT = 0
    local cf = cfOf(e)
    for mi, mp in ipairs(d.ciws) do
      local m = (cf * CF(mp)).Position
      local key = e.id .. ":" .. mi
      local busy = false
      for i = #G.shots, 1, -1 do
        local s = G.shots[i]
        if (s.pos - m).Magnitude < CW.range and incoming(e, s, cpos) then
          s.ciws = s.ciws or {}
          local en = s.ciws[key]
          if not en then
            en = { t0 = t, kill = math.random() < CW.kill }
            s.ciws[key] = en
          end
          if (e.ciwsFx or 0) <= t then
            e.ciwsFx = t + 0.2
            G.fx({ k = "gun", w = "ciws", a = m, b = s.pos + V(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8 })
          end
          if en.kill and t - en.t0 > 0.8 then
            table.remove(G.shots, i)
            G.fx({ k = "shotEnd", id = s.id })
            G.fx({ k = "boom", p = s.pos, s = 0.8, c = "msl" })
          end
          busy = true
          break
        end
      end
      if not busy then
        for _, x in ipairs(G.aircraft or {}) do
          if x.alive and x.team ~= e.team and not x.onGround then
            local p = x.root.CFrame.Position
            if (p - m).Magnitude < CW.range * 0.8 then
              if (e.ciwsFx or 0) <= t then
                e.ciwsFx = t + 0.2
                G.fx({ k = "gun", w = "ciws", a = m, b = p + V(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10 })
              end
              if math.random() < 0.35 then G.damageEnt(x, CW.dmg * (CW.vs.air or 1), srcOf(e)) end
              break
            end
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 开船（客户端发来的）

  local function setGun(e, gi, ty, gp)
    local g = e.sd.guns[gi]
    if not g or type(ty) ~= "number" or type(gp) ~= "number" or ty ~= ty or gp ~= gp then return end
    e.ty[gi] = math.clamp(ty, -g.arc, g.arc)
    e.gp[gi] = math.clamp(gp, g.elev[1], g.elev[2])
    local qy, qp = math.floor(e.ty[gi] + 0.5), math.floor(e.gp[gi] + 0.5)
    if e.model:GetAttribute("Ty" .. gi) ~= qy then e.model:SetAttribute("Ty" .. gi, qy) end
    if e.model:GetAttribute("Gp" .. gi) ~= qp then e.model:SetAttribute("Gp" .. gi, qp) end
  end

  local function sync(P, e, d)
    local cf = d.cf
    if typeof(cf) ~= "CFrame" then return end
    local t = now()
    local dt = math.max(0.02, t - (e.lastSync or t))
    e.lastSync = t
    local sd = e.sd
    local c0 = cfOf(e)
    local p1 = cf.Position
    local dist = (flat(p1) - flat(c0.Position)).Magnitude
    local bad = p1.X ~= p1.X or p1.Z ~= p1.Z or dist > sd.speed * 1.5 * dt + 10 or math.abs(p1.Y) > 6
      or math.abs(p1.X) > Map.SEA_LIM + 300 or math.abs(p1.Z) > Map.SEA_LIM + 300
    if not bad and Map.height(p1.X, p1.Z) > -sd.draft * 0.3 then bad = true end   -- 搁浅（客户端也拦着，这里再查一次）
    if bad then
      G.R.Drive:FireClient(P.pl, { op = "fix", cf = c0, ship = true })
      return
    end
    local look = V(cf.LookVector.X, 0, cf.LookVector.Z)
    if look.Magnitude < 0.01 then look = c0.LookVector end
    local base = CFrame.lookAt(V(p1.X, 0, p1.Z), V(p1.X, 0, p1.Z) + look.Unit)
    G.moveEnt(e, base * CF(0, sd.H / 2 - sd.draft, 0))
    if type(d.sp) == "number" and d.sp == d.sp then
      e.speed = math.clamp(d.sp, -sd.speed, sd.speed * 1.05)
      local q = math.floor(e.speed + 0.5)
      if e.model:GetAttribute("Sp") ~= q then e.model:SetAttribute("Sp", q) end
    end
    if type(d.o) == "number" and d.o == d.o then
      local o = math.clamp(math.floor(d.o), -2, 5)
      if e.model:GetAttribute("Order") ~= o then e.model:SetAttribute("Order", o) end
    end
    if type(d.ty) == "table" and type(d.gp) == "table" then
      for i in ipairs(sd.guns) do setGun(e, i, d.ty[i], d.gp[i]) end
    end
  end

  local function shipInput(P, e, d)
    if d.op == "state" then sync(P, e, d)
    elseif d.op == "fire" or d.op == "trig" then
      local gi = (type(d.g) == "number") and math.floor(d.g) or 1
      local g = e.sd.guns[gi]
      if not g then return end
      setGun(e, gi, d.ty, d.gp)
      local w = SD.W[g.w]
      if w.kind == "gun" then
        e.trig = (d.op == "fire") or d.on == true
        e.trigG = gi
      elseif d.op == "fire" and G.round.phase == "battle" then
        fireGun(e, gi)
      end
    elseif d.op == "msl" then
      if G.round.phase == "battle" then fireMissile(e, d.tgt, d.aim) end
    elseif d.op == "exit" then
      unseat(P, e, true)
    end
  end

  local driveInput0 = G.driveInput
  function G.driveInput(P, d)
    local e = P.vehicle
    if e and e.ship then
      if e.driver == P and e.alive then shipInput(P, e, d) end
      return
    end
    if driveInput0 then driveInput0(P, d) end
  end

  local vehState0 = G.vehState
  function G.vehState(P)
    local e = P.vehicle
    if e and e.ship then
      if not e.alive or e.driver ~= P then return nil end
      local t = now()
      local nx = {}
      for i in ipairs(e.sd.guns) do nx[i] = math.max(0, (e.next[i] or 0) - t) end
      return { id = e.id, ship = true, m = e.sd.id, msl = e.msl, sam = e.samN, next = nx, rest = (e.restT and e.restT > 0) and math.floor(e.restT) or nil }
    end
    if vehState0 then return vehState0(P) end
    return nil
  end

  ---------------------------------------------------------------- AI 舰艇

  -- 攻方 054A：南面近海（离岸约 1500 格）东西来回巡逻；守方 PBR：港湾里来回
  local function aiRoute(team)
    if team == "atk" then
      local out = {}
      local K = Map.K or 1
      for _, x0 in ipairs({ -1200, -400, 400, 1200, 400, -400 }) do
        local x = x0 * K
        local zc = Map.coastS(x) or -700
        -- 离岸 2250 格（不跟着 K 一起放大）：舰炮（4000 格）够得着岸边的碉堡、岸防炮；舰空导弹（3400 格）够不着内陆 1400 来格的守方机场
        table.insert(out, V(x, 0, zc + 1500 * math.min(K, 1.5)))
      end
      return out
    end
    local P = Map.PORT
    local zc = Map.coastS(P.x) or P.z
    return { V(P.x + 25, 0, zc + 150), V(P.x - 25, 0, zc + 270), V(P.x + 25, 0, zc + 300), V(P.x - 25, 0, zc + 130) }
  end
  local AIDEF = { atk = { id = "t054a" }, def = { id = "pbr", need = "C" } }

  -- 选目标：射程内、看得见的敌方工事（岸防炮优先）、舰艇和登陆艇、车、步兵（只有机枪打步兵）
  local function aiTarget(e, gi)
    local d = e.sd
    local w = SD.W[d.guns[gi].w]
    local o = e.root.CFrame.Position
    local best, bs = nil, 1e18
    local function consider(x, pos, pri)
      local dd = (pos - o).Magnitude
      if dd > w.range * 0.95 or dd < 40 then return end
      local s = dd * pri
      if s >= bs then return end
      if not Map.lineClear(o + V(0, d.deck + 4, 0), pos + V(0, 3, 0), math.clamp(dd / 40, 10, 40)) then return end
      best, bs = x, s
    end
    for _, x in ipairs(G.ents) do
      if x.alive and x.team ~= e.team and not x.air and x ~= e then
        local pos = x.root.CFrame.Position
        if x.fort then
          if w.kind ~= "gun" then consider(x, pos, (x.fkind == "coastal") and 0.35 or ((x.fkind == "aaa") and 0.9 or 0.7)) end
        elseif x.sea or x.cat == "ship" then consider(x, pos, 0.5)
        elseif x.cat == "light" or x.cat == "armor" then consider(x, pos, (w.kind == "gun" and x.cat == "armor") and 5 or 1)
        elseif x.kind == "bot" and w.kind == "gun" then consider(x, pos, 1.2) end
      end
    end
    return best
  end

  local function lowAngle(v, g, R, h)
    local v2 = v * v
    local disc = v2 * v2 - g * (g * R * R + 2 * h * v2)
    if disc < 0 or R < 1 then return nil end
    return math.atan((v2 - math.sqrt(disc)) / (g * R))
  end

  function G.navyAIStep(e, dt)
    local d = e.sd
    local A = e.ai
    local t = now()
    -- 开船：朝下一个航点，转向有上限；前面水浅就换下一个点
    --   规避：航向左右蛇行（±25°）、每二十来秒换一次航速——岸防炮按航向航速算提前量、一发比一发准，船一变就得重新试射
    --   损管：血掉到四成五以下往外海撤（离岸再远 1500 格），一边撤一边修，修到八成五回来接着巡逻
    local c = cfOf(e)
    local p = c.Position
    if not A.retreat and e.hp < e.maxHp * 0.45 then A.retreat = true end
    if A.retreat then
      e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.006 * dt)
      e.model:SetAttribute("Hp", math.floor(e.hp))
      if e.hp > e.maxHp * 0.85 then A.retreat = false end
    end
    local wp = A.route[A.i]
    if (flat(wp) - flat(p)).Magnitude < 40 then A.i = A.i % #A.route + 1 wp = A.route[A.i] end
    if A.retreat then wp = V(wp.X, 0, wp.Z + (A.out or 1500 * (Map.K or 1))) end
    local want = flat(wp) - flat(p)
    local yawNow = math.deg(math.atan2(-c.LookVector.X, -c.LookVector.Z))
    local yawWant = math.deg(math.atan2(-want.X, -want.Z)) + ((A.retreat or not A.weave) and 0 or math.sin(t / 11 + (A.ph or 0)) * 25)
    local yaw = math.rad(yawNow + math.clamp(angDiff(yawNow, yawWant), -d.turn * 1.4 * dt, d.turn * 1.4 * dt))
    if t >= (A.spdAt or 0) then
      A.spdAt = t + 16 + math.random() * 10
      A.spdK = 0.3 + math.random() * 0.4
    end
    local spd = d.speed * (A.retreat and 0.8 or (A.spdK or 0.45))
    local fwd = V(-math.sin(yaw), 0, -math.cos(yaw))
    local np = p + fwd * spd * dt
    local ahead = np + fwd * d.L * 0.5
    if Map.height(ahead.X, ahead.Z) > -d.draft * 0.5 then
      A.i = A.i % #A.route + 1
      e.speed = 0
    else
      G.moveEnt(e, CFrame.lookAt(V(np.X, 0, np.Z), V(np.X, 0, np.Z) + fwd) * CF(0, d.H / 2 - d.draft, 0))
      e.speed = spd
      local q = math.floor(spd + 0.5)
      if e.model:GetAttribute("Sp") ~= q then e.model:SetAttribute("Sp", q) end
    end
    if not G.round or G.round.phase ~= "battle" then return end
    -- 隔一会儿重挑目标；有敌舰在射程里时偶尔发一枚反舰导弹（25 秒一枚）
    if t >= (A.thinkAt or 0) then
      A.thinkAt = t + 0.8 + math.random() * 0.4
      for gi in ipairs(d.guns) do A["tgt" .. gi] = aiTarget(e, gi) end
      if d.missiles and e.msl > 0 and t >= (A.mslAt or 0) then
        local best, bd = nil, SD.W[d.missiles.w].range * 0.9
        for _, x in ipairs(ships) do
          if x.alive and x.team ~= e.team and not x.ai then
            local dd = (x.root.CFrame.Position - p).Magnitude
            if dd < bd then best, bd = x, dd end
          end
        end
        if best and fireMissile(e, best.id) then A.mslAt = t + 25 end
      end
    end
    local cf = cfOf(e)
    for gi, g in ipairs(d.guns) do
      local tg = A["tgt" .. gi]
      if tg and tg.alive then
        local w = SD.W[g.w]
        local mz = SD.muzzle(d, cf, gi, e.ty[gi], e.gp[gi]).Position
        local tp = tg.root.CFrame.Position
        local dir
        if w.kind == "gun" then
          dir = (tp + V(0, 1, 0) - mz).Unit
        else
          -- 试射修正：换目标后头一发偏射程的 4%～7%，之后一发比一发准
          local rel = tp - mz
          local hz = V(rel.X, 0, rel.Z)
          if tg ~= A.lastT then A.lastT, A.err = tg, hz.Magnitude * (0.04 + math.random() * 0.03) * ((math.random() < 0.5) and -1 or 1) end
          local aim = tp + hz.Unit * A.err
          local r2 = aim - mz
          local th = lowAngle(w.speed, SHELL_G * w.gscale, V(r2.X, 0, r2.Z).Magnitude, r2.Y)
          if th then dir = V(r2.X, 0, r2.Z).Unit * math.cos(th) + V(0, math.sin(th), 0) end
        end
        if dir then
          local l = cf:VectorToObjectSpace(dir)
          if g.aft then l = V(-l.X, l.Y, -l.Z) end
          local wy = math.deg(math.atan2(l.X, -l.Z))
          local wp2 = math.deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)))
          if math.abs(wy) <= g.arc then
            local s = g.trav * dt
            setGun(e, gi, e.ty[gi] + math.clamp(wy - e.ty[gi], -s, s), e.gp[gi] + math.clamp(math.clamp(wp2, g.elev[1], g.elev[2]) - e.gp[gi], -s, s))
            if math.abs(wy - e.ty[gi]) < 2 and math.abs(wp2 - e.gp[gi]) < 2 and t >= (e.next[gi] or 0) then
              fireGun(e, gi, dir)
              if w.kind ~= "gun" then
                -- 打岸防炮、敌舰（会还手的）照常射速压制；别的目标打得慢一点（不是所有炮弹都朝岸上砸）
                local duel = (tg.fort and tg.fkind == "coastal") or tg.ship
                e.next[gi] = now() + (duel and w.rate * 1.1 or (w.rate * 2.5 + math.random()))
                A.err = (A.err or 0) * -0.5
              end
            end
          end
        end
      end
    end
  end

  local function spawnAI(team)
    local def = AIDEF[team]
    local d = def and SD.get(def.id)
    if not d then return end
    if def.need then
      local s = G.points and G.points[def.need]
      if not s or s.owner ~= team then return end
    end
    local route = aiRoute(team)
    local p = route[1]
    local e = newShip(team, def.id, CFrame.lookAt(V(p.X, 0, p.Z), V(route[2].X, 0, route[2].Z)))
    if not e then return end
    e.ai = { route = route, i = 2, ph = math.random() * 6, out = (team == "atk") and 1500 * (Map.K or 1) or 0, weave = team == "atk" }   -- 港湾里的巡逻艇不蛇行（湾窄）
    e.model:SetAttribute("AI", true)
    e.model:SetAttribute("Order", 2)
  end

  ---------------------------------------------------------------- 每帧：开船的人跟着船；按住扳机连发；没人开的收走；回码头补给；AI 舰艇按时出来

  local acc, aiT = 0, 0
  G.onFrame(function(dt)
    acc += dt
    aiT += dt
    local t = now()
    for _, e in ipairs(table.clone(ships)) do
      local D = e.driver
      if D and (not D.alive or not D.char or not D.char.Parent or G.P[D.pl] ~= D or D.vehicle ~= e) then
        e.driver = nil
        e.emptyAt = t
        e.trig = false
        e.model:SetAttribute("Driver", 0)
        D = nil
      end
      if D and D.char then D.char:PivotTo(e.root.CFrame) end
      if e.alive and D and e.trig and G.round and G.round.phase == "battle" then fireGun(e, e.trigG or 1) end
      if e.alive and not D and not e.ai and e.emptyAt and t - e.emptyAt > 90 then
        dropShip(e)
        G.removeEnt(e)
      end
    end
    if acc < 0.1 then return end
    local step = acc
    acc = 0
    for _, e in ipairs(ships) do
      if e.alive and not e.ai then
        -- 回自己码头停稳 5 秒：补满导弹、防空导弹，慢慢修
        local near = false
        local p = e.root.CFrame.Position
        for _, h in ipairs(homes) do
          if h.team == e.team and (flat(h.p) - flat(p)).Magnitude < h.r then near = true break end
        end
        if near and math.abs(e.speed or 0) < 3 then
          e.restT = (e.restT or 0) + step
          if e.restT > 5 then
            if not e.rearmed then
              e.rearmed = true
              e.msl = e.sd.missiles and e.sd.missiles.n or 0
              e.samN = e.sd.sam and e.sd.sam.n or 0
              e.model:SetAttribute("Msl", e.msl)
              e.model:SetAttribute("Sam", e.samN)
              if e.driver then G.msg(e.driver.pl, "good", "ui.shipRearmed") G.pushOne(e.driver) end
            end
            if e.hp < e.maxHp then
              e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.03 * step)
              e.model:SetAttribute("Hp", math.floor(e.hp))
            end
          end
        else
          e.restT, e.rearmed = 0, false
        end
      end
    end
    -- AI 舰艇：开战后没有就出来一艘（被击沉 150 秒后再来）
    if aiT >= 1 then
      aiT = 0
      if G.round and G.round.phase == "battle" and not G.navyNoAI then
        for _, team in ipairs({ "atk", "def" }) do
          local have = false
          for _, e in ipairs(ships) do if e.alive and e.ai and e.team == team then have = true end end
          if not have and t >= aiNext[team] then
            aiNext[team] = t + 20
            G.try("AI 舰艇", spawnAI, team)
          end
        end
      end
    end
  end)

  local function dropDriver(P)
    for _, e in ipairs(ships) do if e.driver == P then unseat(P, e, false) end end
  end
  G.on("died", dropDriver)
  G.on("left", dropDriver)
  G.on("roundStart", function()
    for _, e in ipairs(ships) do G.removeEnt(e) end
    table.clear(ships)
    pending = { atk = {}, def = {} }
    aiNext = { atk = 0, def = 0 }
  end)
  -- 港口镇丢了：港湾里的守方 AI 巡逻艇撤走（据点夺回来之前不再来）
  G.on("captured", function(s)
    if type(s) ~= "table" or s.id ~= "C" then return end
    if s.owner == "def" then aiNext.def = now() + 30 return end
    for _, e in ipairs(table.clone(ships)) do
      if e.ai and e.team == "def" then
        dropShip(e)
        G.removeEnt(e)
      end
    end
  end)
end

return Navy
