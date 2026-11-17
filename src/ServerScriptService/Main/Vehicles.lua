-- Roblox全面大战场——载具：登陆艇（攻方选海滩出生、机器人成班坐艇）、伞降；开载具的操作在后面的版本里接
--   登陆艇：每处海滩一条在装人的艇，第一个人上来后等 4 秒开船，从离岸约 600 格冲向海滩（十来秒），途中能被打沉（乘客一起阵亡）；
--     准备阶段上的艇在海上等着，开战那一刻一起冲滩（开局就是抢滩登陆）；同一处海滩同时有几条艇的左右错开排成一排；
--     到岸放下跳板、把人放到艇头前面的滩上，艇退回去消失。乘客坐艇时角色锚定、每帧跟着艇挪（镜头跟着走）
--   伞降：从高空落下，降落伞把下落速度压在每秒 18 格以内；个人冷却
local Vehicles = {}

function Vehicles.init(G)
  local Config, Map = G.Config, G.Map
  local V = Vector3.new
  local CF = CFrame.new
  local now = os.clock

  -- hp：岸防炮一发直接命中 728（520 × 打船 1.4），原来 650 一发就沉、一船人全灭（机器人对打 6 分钟被打沉 53 条，攻方一个据点都拿不下）；
  --   现在要中 3 发才沉，被盯上了还有机会冲上滩
  local BOAT = { start = 620, speed = 48, wait = 4, hp = 1600, size = V(16, 7, 34), seats = 12 }
  local boats = {}   -- [beachId] = 正在装人的那条；跑着的在 running 里
  local running = {}
  local laneN = {}   -- [beachId] = 这处海滩开过几条（左右错开排）

  local beachOf = Map.landingOf

  -- 艇的位置：从海上 start 格处沿 b.dir 方向冲向岸线；返回 CFrame（船头朝岸）
  local function boatCF(b, d, lane)
    local z = b.z + b.dir * d
    local face = V(0, 0, -b.dir)
    local p = V(b.cx + (lane or 0) * 34, 1.2, z)
    return CFrame.lookAt(p, p + face)
  end

  local function seatOffset(i)
    local row, col = math.floor((i - 1) / 3), (i - 1) % 3
    return CF((col - 1) * 4, 3.4, -8 + row * 4.5)
  end

  local function newBoat(b)
    laneN[b.id] = (laneN[b.id] or 0) + 1
    local k = (laneN[b.id] - 1) % 5
    local lane = ((k % 2 == 0) and 1 or -1) * math.ceil(k / 2)   -- 0、-1、1、-2、2：从中间往两边排
    local e = G.newEnt({ kind = "lcm", team = "atk", cat = "ship", hp = BOAT.hp, size = BOAT.size, cf = boatCF(b, BOAT.start, lane), extra = { sea = true } })
    e.beach = b
    e.lane = lane
    e.dist = BOAT.start
    e.state = "loading"
    e.leaveAt = now() + BOAT.wait
    local R = G.round
    if R and R.phase == "prep" then e.leaveAt = math.max(e.leaveAt, (R.prepEnds or 0) + 0.5) end   -- 准备阶段：等开战一起冲
    e.pass = {}   -- 坐着的玩家
    e.bots = {}   -- 坐着的机器人
    e.onDeath = function(self, src)
      for _, P in ipairs(self.pass) do
        if P.alive and P.char then
          local hum = P.char:FindFirstChildOfClass("Humanoid")
          if hum then G.hurtChar(P.char, 1000, src) end
          G.msg(P.pl, "bad", "ui.boatSunk")
        end
      end
      local bots = self.bots
      self.pass, self.bots = {}, {}
      for _, B in ipairs(bots) do
        B.boat = nil
        if B.e and B.e.alive then G.damageEnt(B.e, 1e5, src) end
      end
      if boats[b.id] == self then boats[b.id] = nil end
      self.state = "sunk"
      task.delay(3, function() G.removeEnt(self) end)
    end
    return e
  end

  -- 这处海滩正在装人、还有座位的艇（没有就新开一条）
  local function boatFor(b)
    local e = boats[b.id]
    if not e or not e.alive or e.state ~= "loading" or #e.pass + #e.bots >= BOAT.seats then
      e = newBoat(b)
      boats[b.id] = e
      table.insert(running, e)
    end
    return e
  end
  local function seatOf(e, who)
    local i = 0
    for _, x in ipairs(e.pass) do i += 1 if x == who then return i end end
    for _, x in ipairs(e.bots) do i += 1 if x == who then return i end end
    return 1
  end

  -- 登陆场：滩头已经被攻方控制住了（登陆点 150 格内有攻方、没有守方，而且开战了）——后面的增援直接在滩上出生，不用再坐 10 多秒的艇
  --   （机器人对打：守方在据点后面就近出生，攻方每一波都要坐艇再走几百格，第一波打到 63% 也被压回去）
  local function secured(b)
    local R = G.round
    if not R or R.phase ~= "battle" or not G.countAt then return false end
    local x, z = b.cx, b.z - b.dir * 40
    local a, d = G.countAt(x, z, Map.ground(x, z), 150)
    for _, P in pairs(G.P) do
      if P.alive and P.char then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp and (hrp.Position.X - x) ^ 2 + (hrp.Position.Z - z) ^ 2 < 150 * 150 then
          if P.team == "atk" then a += 1 else d += 1 end
        end
      end
    end
    return a > 0 and d == 0
  end
  G.beachSecured = function(id) local b = beachOf(id) return b ~= nil and secured(b) end
  -- 滩上的一个出生位置（艇头前面一排，左右散开）
  local function onBeach(b)
    local x = b.cx + (math.random() - 0.5) * 80
    local z = b.z - b.dir * (24 + math.random() * 20)
    local y = Map.ground(x, z) + 3.5
    return CFrame.lookAt(V(x, y, z), V(x, y, z - b.dir * 10))
  end

  -- 机器人上艇：返回艇（Bots 按艇的位置建实体；之后每帧跟着艇挪，靠岸时 G.botLanded）；登陆场已经建立了就直接在滩上出生（返回 nil 艇）
  function G.boatBot(B, beachId)
    local b = beachOf(beachId)
    if not b then return nil end
    if secured(b) then return false, onBeach(b) * CF(0, -1.6, 0) end
    local e = boatFor(b)
    table.insert(e.bots, B)
    B.boat = e
    return e, e.root.CFrame * seatOffset(#e.pass + #e.bots) * CF(0, -1.6, 0)
  end
  function G.botOffBoat(B)
    local e = B.boat
    if not e then return end
    for i, x in ipairs(e.bots) do
      if x == B then table.remove(e.bots, i) break end
    end
    B.boat = nil
  end

  -- 上艇：返回出生位置（艇上的座位）和出生后要做的事（把角色挂到艇上）；登陆场已经建立了就直接站在滩上
  function G.boardBoat(P, beachId)
    local b = beachOf(beachId)
    if not b then return CF(0, 50, 0), nil end
    if secured(b) then return onBeach(b), nil end
    local e = boatFor(b)
    table.insert(e.pass, P)
    P.boat = e
    local seat = seatOffset(#e.pass + #e.bots)
    P.seat = seat
    G.msg(P.pl, "info", "ui.landing")
    return e.root.CFrame * seat, function(Q, char)
      local hrp = char:FindFirstChild("HumanoidRootPart")
      if hrp then hrp.Anchored = true end
    end
  end

  local function release(e)
    local b = e.beach
    for i, P in ipairs(e.pass) do
      if P.alive and P.char and P.boat == e then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        local x = b.cx + (e.lane or 0) * 34 + ((i - 1) % 4 - 1.5) * 5
        local z = b.z - b.dir * (18 + math.floor((i - 1) / 4) * 5)
        if hrp then
          hrp.Anchored = false
          P.char:PivotTo(CFrame.lookAt(V(x, Map.ground(x, z) + 3.5, z), V(x, Map.ground(x, z) + 3.5, z - b.dir * 10)))
        end
      end
      P.boat, P.seat = nil, nil
    end
    local n = #e.pass
    for i, B in ipairs(e.bots) do
      B.boat = nil
      if B.e and B.e.alive then
        local k = n + i
        local x = b.cx + (e.lane or 0) * 34 + ((k - 1) % 4 - 1.5) * 5
        local z = b.z - b.dir * (18 + math.floor((k - 1) / 4) * 5)
        if G.botLanded then G.try("机器人上岸", G.botLanded, B, x, z) end
      end
    end
    e.pass, e.bots = {}, {}
  end

  -- 每帧：艇往岸边开，乘客跟着
  G.onFrame(function(dt)
    for i = #running, 1, -1 do
      local e = running[i]
      if not e.alive then
        table.remove(running, i)
      else
        local t = now()
        if e.state == "loading" and t >= e.leaveAt and not (G.round and G.round.phase == "prep") then
          e.state = "run"
          if boats[e.beach.id] == e then boats[e.beach.id] = nil end
        end
        if e.state == "run" then
          e.dist = math.max(0, e.dist - BOAT.speed * dt)
          local cf = boatCF(e.beach, e.dist, e.lane)
          local bow = cf.Position + cf.LookVector * BOAT.size.Z * 0.5
          if Map.height(bow.X, bow.Z) > -1.2 or e.dist <= 0 then   -- 冲上滩
            e.state = "landed"
            e.backAt = t + 6
            G.fx({ k = "ramp", id = e.id })
            release(e)
          end
          G.moveEnt(e, cf)
        elseif e.state == "landed" and t >= (e.backAt or 0) then
          e.state = "gone"
          G.removeEnt(e)
        end
        for _, P in ipairs(e.pass) do
          if P.alive and P.char and P.boat == e then
            local hrp = P.char:FindFirstChild("HumanoidRootPart")
            if hrp then
              hrp.Anchored = true
              P.char:PivotTo(e.root.CFrame * (P.seat or CF()))
            end
          end
        end
        if e.state ~= "landed" then
          local n = #e.pass
          for i, B in ipairs(e.bots) do
            if B.e and B.e.alive then G.moveEnt(B.e, e.root.CFrame * seatOffset(n + i) * CF(0, -1.6, 0)) end
          end
        end
      end
    end
    -- 伞降：下落速度压到每秒 18 格
    for _, P in pairs(G.P) do
      if P.chute and P.alive and P.char then
        local hrp = P.char:FindFirstChild("HumanoidRootPart")
        if hrp then
          local v = hrp.AssemblyLinearVelocity
          if v.Y < -18 then hrp.AssemblyLinearVelocity = V(v.X, -18, v.Z) end
          local gy = Map.ground(hrp.Position.X, hrp.Position.Z)
          if hrp.Position.Y - gy < 6 or now() - P.chute > 40 then
            P.chute = nil
            P.char:SetAttribute("Chute", false)
          end
        end
      end
    end
  end)

  -- 伞降：落在离最近一个还没拿下的据点 220～320 格、靠攻方一侧的地方（不能直接落进据点）
  function G.paraDrop(P)
    local t = now()
    local target = nil
    for _, p in ipairs(Map.POINTS) do
      local s = G.points[p.id]
      local act = (not G.pointActive or G.pointActive(p.id)) and not (G.flankOf and G.flankOf[p.id])   -- 当前阶段要打的（不落到侧翼、别的阶段去）
      if s and s.owner == "def" and act then
        if not target or p.z > target.z then target = p end   -- 最靠南（离攻方最近）的
      end
    end
    target = target or Map.POINTS[1]
    local a = math.rad(60 + math.random() * 60)   -- 南边的扇面
    local r = 220 + math.random() * 100
    local x, z = target.x + math.cos(a) * r, target.z + math.sin(a) * r
    if not Map.isLand(x, z) then x, z = target.x, target.z + 200 end
    local y = Map.ground(x, z) + 320
    return CFrame.lookAt(V(x, y, z), V(target.x, y, target.z)), function(Q, char)
      Q.chute = now()
      char:SetAttribute("Chute", true)
      Q.paraCd = t + 60
    end
  end

  local function offBoat(P)
    if P.boat then
      for i, Q in ipairs(P.boat.pass) do
        if Q == P then table.remove(P.boat.pass, i) break end
      end
      P.boat, P.seat = nil, nil
    end
    P.chute = nil
  end
  G.on("died", offBoat)
  G.on("left", offBoat)
  G.on("roundStart", function()
    for _, e in ipairs(running) do if e.alive then G.removeEnt(e) end end
    running = {}
    boats = {}
    laneN = {}
  end)
end

return Vehicles
