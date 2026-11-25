-- Roblox全面大战场——单兵战术平板（服务器）。用户：增加一个单兵战术平板，可以召唤空投载具、空中打击，但必须有次数限制
--   装备栏副武器带了战术平板的人（R 币解锁，Config.Passes.tablet），拿在手上就打开（客户端 TacPad.lua），在平板的地图上点目标，发 tacCall(种类, 位置)。这里核对：
--   活着、没在载具里、开战了、这一局还有次数、自己的冷却到了、全队同一种没刚叫过、目标离自己不超过 range 格、空投的点在陆地上、全队空投的车没超量；
--   过了就执行（Config.TacPad）：
--     空投载具：直升机飞过、挂着伞落下来，落地生成一辆空车（30 秒内只给呼叫的人，没人上 90 秒收走——同生成点的车）
--     空投补给：落地留一个补给箱，旁边的队友补满弹药、慢慢回血，75 秒后收走
--     精确打击：一枚制导炸弹；机炮扫射：攻击机沿「自己 → 目标」的方向打一串小爆炸；集束轰炸：轰炸机沿这个方向投一串炸弹
--   飞过来的飞机、落下的箱子、炸弹是客户端画的（G.fx 的 tac 特效）；次数、冷却随战况发给客户端（Round.lua 的 personal 调 G.tacState）；
--   拿出平板时人端着平板（Air.lua 的 G.uavTablet，别人看得到这个人在操作平板）
local Tactical = {}

function Tactical.init(G)
  local Config, Map = G.Config, G.Map
  local TP = Config.TacPad
  if not TP then return end
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local now = os.clock
  local teamAt = { atk = {}, def = {} }   -- [阵营][种类] = 全队下次能叫这一种的时刻
  local pending = { atk = 0, def = 0 }    -- 还在路上的空投车

  -- 这一局的次数、冷却（新一局重置；阵亡不补）
  local function slot(P, id)
    local r = (G.round and G.round.n) or 0
    if P.tacRound ~= r then P.tacRound, P.tac = r, {} end
    P.tac[id] = P.tac[id] or { used = 0, at = 0 }
    return P.tac[id]
  end
  function G.tacState(P)
    local out, t = {}, now()
    for _, id in ipairs(TP.order) do
      local it = TP.items[id]
      local s = slot(P, id)
      local ta = (teamAt[P.team] and teamAt[P.team][id]) or 0
      out[id] = { n = math.max(0, it.n - s.used), cd = math.max(0, math.ceil(math.max(s.at, ta) - t)) }
    end
    return out
  end

  local function src(P) return { P = P, team = P.team, name = P.pl.DisplayName } end
  -- 自己 → 目标的水平方向：扫射、轰炸沿它排开，飞机也顺着它飞
  local function heading(P, x, z)
    local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
    local d = hrp and V(x - hrp.Position.X, 0, z - hrp.Position.Z) or V(0, 0, -1)
    if d.Magnitude < 1 then d = V(0, 0, -1) end
    return d.Unit
  end
  local function ground(x, z) return V(x, Map.ground(x, z), z) end

  ---------------------------------------------------------------- 补给箱

  local crates = {}
  local function piece(m, size, cf, col, mat)
    local p = Instance.new("Part")
    p.Size, p.CFrame, p.Color = size, cf, col
    p.Material = mat or Enum.Material.SmoothPlastic
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, true, false, false
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = m
    return p
  end
  local function supplyCrate(team, p, it)
    local m = Instance.new("Model")
    m.Name = "SupplyCrate"
    m:SetAttribute("Team", team)
    local base = CFrame.new(p) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
    piece(m, V(6.4, 0.5, 4.6), base * CFrame.new(0, 0.25, 0), RGB(70, 58, 42), Enum.Material.WoodPlanks)   -- 托盘
    local box = piece(m, V(5.8, 3.4, 4.0), base * CFrame.new(0, 2.2, 0), RGB(78, 86, 60), Enum.Material.Fabric)   -- 帆布包着的箱子
    piece(m, V(5.9, 0.3, 4.1), base * CFrame.new(0, 2.6, 0), RGB(40, 42, 36), Enum.Material.Fabric)   -- 捆带
    piece(m, V(0.3, 3.5, 4.1), base * CFrame.new(1.4, 2.2, 0), RGB(40, 42, 36), Enum.Material.Fabric)
    piece(m, V(0.3, 3.5, 4.1), base * CFrame.new(-1.4, 2.2, 0), RGB(40, 42, 36), Enum.Material.Fabric)
    local lamp = piece(m, V(0.5, 0.5, 0.5), base * CFrame.new(0, 4.15, 0), (team == "atk") and RGB(255, 90, 70) or RGB(96, 236, 120), Enum.Material.Neon)   -- 守方的灯：绿（原来蓝，用户 11-21 蓝色全改绿）
    lamp.CanCollide = false
    lamp:SetAttribute("Anim", "blink")   -- Night.lua 让它一闪一闪（夜里好找）
    lamp:SetAttribute("Spd", 1)
    local light = Instance.new("PointLight")
    light.Range, light.Brightness, light.Color = 14, 1.2, lamp.Color
    light.Parent = lamp
    m.PrimaryPart = box
    local root = workspace:FindFirstChild("Map") or workspace
    m.Parent = root
    table.insert(crates, { m = m, team = team, p = p, r = it.r, till = now() + it.life, heal = it.heal })
  end
  -- 每秒：箱子旁边的队友回血，隔 8 秒补满一次弹药（客户端也补：G.msg 的 refill）
  local acc = 0
  G.onFrame(function(dt)
    if #crates == 0 then return end
    acc += dt
    if acc < 1 then return end
    acc = 0
    local t = now()
    for i = #crates, 1, -1 do
      local c = crates[i]
      if t > c.till or not c.m.Parent then
        c.m:Destroy()
        table.remove(crates, i)
      else
        for _, P in pairs(G.P) do
          local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
          local hum = P.char and P.char:FindFirstChildOfClass("Humanoid")
          if P.team == c.team and P.alive and hrp and hum and hum.Health > 0 and not G.inVeh(P) and (hrp.Position - c.p).Magnitude < c.r then
            if hum.Health < hum.MaxHealth then hum.Health = math.min(hum.MaxHealth, hum.Health + c.heal) end
            if t >= (P.refillAt or 0) then
              P.refillAt = t + 8
              P.ammo = {}   -- Weapons.lua 的 ammoOf 见到空的就给满弹匣、满备弹
              G.msg(P.pl, "refill")
              G.fx({ k = "heal", p = hrp.Position })
            end
          end
        end
      end
    end
  end)
  G.on("roundStart", function()
    for _, c in ipairs(crates) do c.m:Destroy() end
    crates = {}
    teamAt = { atk = {}, def = {} }
    pending = { atk = 0, def = 0 }
  end)

  ---------------------------------------------------------------- 执行

  local RUN = {}
  RUN.pgm = function(P, it, x, z)
    task.delay(it.flight, function() G.explode(ground(x, z), it.w, src(P), 2.6) end)
  end
  RUN.gunrun = function(P, it, x, z, dir)
    for i = 1, it.hits do
      local f = (i - 1) / math.max(1, it.hits - 1) - 0.5
      local px = x + dir.X * f * it.len + (math.random() - 0.5) * 7
      local pz = z + dir.Z * f * it.len + (math.random() - 0.5) * 7
      task.delay(it.flight + (i - 1) * 0.045, function() G.explode(ground(px, pz), it.w, src(P), 0.55) end)
    end
  end
  RUN.cluster = function(P, it, x, z, dir)
    for i = 1, it.bombs do
      local f = (i - 1) / math.max(1, it.bombs - 1) - 0.5
      local side = (math.random() - 0.5) * 34
      local px = x + dir.X * f * it.len - dir.Z * side
      local pz = z + dir.Z * f * it.len + dir.X * side
      task.delay(it.flight + (i - 1) * 0.12, function() G.explode(ground(px, pz), it.w, src(P), 1.7) end)
    end
  end
  RUN.drop = function(P, it, x, z, dir)
    local team = P.team
    pending[team] += 1
    task.delay(it.flight, function()
      pending[team] = math.max(0, pending[team] - 1)
      if not G.spawnGroundVeh then return end
      local p = ground(x, z)
      local owner = (G.P[P.pl] == P and P.alive) and P or nil
      local e = G.spawnGroundVeh(team, it.veh[team], CFrame.lookAt(p, p + dir), false, owner)
      if e then
        e.tacDrop = true
        G.fx({ k = "padSpawn", p = e.root.CFrame.Position })
      end
    end)
  end
  RUN.supply = function(P, it, x, z)
    local team = P.team
    task.delay(it.flight, function() supplyCrate(team, ground(x, z), it) end)
  end

  local function dropsAlive(team)
    local n = pending[team]
    for _, e in ipairs(G.ents or {}) do
      if e.tacDrop and e.alive and e.team == team then n += 1 end
    end
    return n
  end

  ---------------------------------------------------------------- 客户端发来的

  -- 拿出 / 收起平板：人端着平板（遥控无人机的时候不管，那块平板归无人机）
  G.ACT.tacPad = function(P, on)
    if P.remote then return end
    if on and (not P.alive or not P.char or P.vehicle) then on = false end
    if G.uavTablet then G.uavTablet(P, on == true) end
  end

  G.ACT.tacCall = function(P, id, pos)
    local it = type(id) == "string" and TP.items[id] or nil
    if not it or typeof(pos) ~= "Vector3" or pos.X ~= pos.X or pos.Z ~= pos.Z then return end
    if not P.alive or not P.char or G.inVeh(P) then return end
    -- 平板是副武器（用户：不要按 B 召唤平板，做成物品；99 R 币解锁）：装备栏里带了、通行证有才行
    local kit = G.kitOf and G.kitOf(P)
    if not (kit and table.find(kit.weapons, "tablet")) then G.msg(P.pl, "bad", "tac.noPad") return end
    if G.passOkFor and not G.passOkFor(P, "tablet") then G.msg(P.pl, "bad", "pass.locked", { k = "weapon.tablet" }) return end
    if not G.round or G.round.phase ~= "battle" then G.msg(P.pl, "bad", "tac.notYet") return end
    local s = slot(P, id)
    local t = now()
    if s.used >= it.n then G.msg(P.pl, "bad", "tac.none") return end
    if t < s.at then G.msg(P.pl, "bad", "tac.cd", math.ceil(s.at - t)) return end
    local ta = teamAt[P.team][id] or 0
    if t < ta then G.msg(P.pl, "bad", "tac.teamBusy", math.ceil(ta - t)) return end
    local hrp = P.char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local x, z = pos.X, pos.Z
    local R = Map.R or 12288
    if math.abs(x) > R or math.abs(z) > R then return end
    if (V(x, 0, z) - V(hrp.Position.X, 0, hrp.Position.Z)).Magnitude > TP.range then
      G.msg(P.pl, "bad", "tac.far", math.floor(TP.range / 2.8))
      return
    end
    local gy = Map.ground(x, z)
    if (it.kind == "drop" or it.kind == "supply") and gy < 0.5 then G.msg(P.pl, "bad", "tac.water") return end
    if it.kind == "drop" and dropsAlive(P.team) >= (it.vmax or 3) then G.msg(P.pl, "bad", "tac.vmax", it.vmax or 3) return end
    s.used += 1
    s.at = t + it.cd
    teamAt[P.team][id] = t + TP.teamCd
    local dir = heading(P, x, z)
    G.fx({ k = "tac", kind = it.kind, id = id, p = V(x, gy, z), d = dir, t = it.flight, team = P.team, by = P.pl.UserId,
      len = it.len, n = it.hits or it.bombs })
    RUN[it.kind](P, it, x, z, dir)
    G.msgTeam(P.team, "info", "tac.called", P.pl.DisplayName, { k = "tac." .. id }, it.flight)
    if G.pushOne then G.pushOne(P) end
  end
end

return Tactical
