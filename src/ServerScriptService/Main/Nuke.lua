-- Roblox全面大战场（服务器）——高超音速战术核导弹（用户 11-22：「给 h6k 加一个高超音速战术核弹的挂载吧」）
--   「惊雷-1」（AirDefs.W.hn1，虚构型号）：轰-6K 弹舱里半埋挂一枚（照轰-6N 腹部凹槽挂空射弹道导弹的挂法），一架一枚
--   飞行（guide，Air.lua 发射时挂上）：投放后自由落体 drop 秒离开轰炸机 → 助推器点火、抬头往上爬到 apo 格 → 6 马赫以上（speed）朝目标滑翔 →
--     离目标的水平距离小于高度时俯冲，末段 7 马赫（dive），离地 burst 格空爆（撞到地面、房子也炸）
--   爆炸（G.nukeAt）：kill 以内的敌人、车、船、飞机、工事当场没了；hurt 以内按距离衰减（外圈的步兵可能活下来）；天上 air 以内的飞机挨冲击波；
--     bld 以内的房子全塌；地上烧出焦土（melt 以内熔成会发光的岩浆壳）、爆心一个浅坑；之后 fallout 秒的辐射区（每秒掉血）
--   只伤敌人（跟别的武器一样不打自己人）；每队发射后冷却 cd 秒，开战 first 秒后才能发（Config.Nuke）
--   发射时：对面全队「核打击来袭」（目标点、大概几秒后到），自己队「核导弹已发射」；客户端 Nuke.lua 画警报、红圈、闪光、火球、冲击波、蘑菇云
--   每局开局把焦土、弹坑按原来的地形重写回来
local RS = game:GetService("ReplicatedStorage")

local Nuke = {}

function Nuke.init(G)
  local Config = G.Config
  local Map = G.Map
  local World = G.World
  local NC = Config.Nuke or {}
  local V = Vector3.new
  local MAT = Enum.Material
  local T = workspace.Terrain
  local now = os.clock
  local GRAV = workspace.Gravity * 0.55

  local readyAt = { atk = 0, def = 0 }   -- 这一队下次能发射的时间
  local battleT0 = nil                   -- 这一局开战的时间
  local scorched = {}                    -- 这一局烧过的地方 { x, z, r, y0 }（开局重写地形）
  local zones = {}                       -- 辐射区 { p, r, dps, t1, src }
  local count = 0
  G.nukeCount = function() return count end   -- 测试用

  local function ground(x, z) return math.max(Map.ground and Map.ground(x, z) or Map.height(x, z), 0) end

  ---------------------------------------------------------------- 能不能发

  -- 返回 true；不能发返回 false、原因（Lang 键）、还要等几秒
  function G.nukeCheck(team)
    local R = G.round
    if not R or R.phase ~= "battle" then return false, "air.notYet", 0 end
    local t = now()
    local t0 = R.battleAt or battleT0 or t   -- 开战的时间（Round.lua 的 startBattle 记的）
    if t < t0 + (NC.first or 90) then return false, "nuke.early", math.ceil(t0 + (NC.first or 90) - t) end
    if t < (readyAt[team] or 0) then return false, "nuke.cd", math.ceil(readyAt[team] - t) end
    return true
  end

  ---------------------------------------------------------------- 飞行：空射弹道导弹的弹道

  -- 点火以后走一条三次贝塞尔曲线（空射弹道导弹那样的拱形弹道：往上爬、过顶、陡陡地扎下来），离目标越远拱得越高；
  --   沿曲线的进度 u 按时间 x = 已飞时间 / 总时间 走 u = 0.55x + 0.45x²（越飞越快：末段约平均速度的 1.45 倍）。
  --   曲线的四个点、总时间发给客户端（nukePath），客户端按同一个式子算位置——高速弹不用一帧帧校正
  local function bez(P, u)
    local a = 1 - u
    return P[1] * (a * a * a) + P[2] * (3 * a * a * u) + P[3] * (3 * a * u * u) + P[4] * (u * u * u)
  end
  local function prog(x) return 0.55 * x + 0.45 * x * x end
  G.nukeBez, G.nukeProg = bez, prog   -- 客户端 Fx.lua 用同一套（测试也用）

  local function plan(s)
    local H = s.hyper
    local burst = NC.burst or 120
    local P0 = s.pos
    local P3 = H.tgt + V(0, burst, 0)
    local flat = V(P3.X - P0.X, 0, P3.Z - P0.Z)
    local fd = flat.Magnitude
    local dirH = (fd > 1) and flat.Unit or V(s.vel.X, 0, s.vel.Z).Unit
    local loft = math.clamp(fd * 0.32, 1800, 9000)
    local top = math.max(P0.Y, P3.Y) + loft
    local P1 = V(P0.X, top, P0.Z) + dirH * (fd * 0.3)
    local P2 = V(P3.X, top * 0.96, P3.Z) - dirH * (fd * 0.1)
    local pts = { P0, P1, P2, P3 }
    local len = ((P1 - P0).Magnitude + (P2 - P1).Magnitude + (P3 - P2).Magnitude + (P3 - P0).Magnitude) / 2
    local Tf = math.max(2.5, len / ((NC.speed or 5800) * 0.8))
    H.path, H.t0, H.Tf = pts, s.age, Tf
    G.fx({ k = "nukePath", id = s.id, a = P0, b = P1, c = P2, d = P3, tf = Tf })
  end

  local function eta(s)
    local H = s.hyper
    if H.path then return math.max(0, H.Tf - (s.age - H.t0)) end
    local p, tp = s.pos, H.tgt
    return (NC.drop or 0.8) - (s.age or 0) + (V(tp.X - p.X, 0, tp.Z - p.Z).Magnitude * 1.2 + 4000) / ((NC.speed or 5800) * 0.8)
  end
  G.nukeEta = eta

  -- 每步（Ents.lua stepShots 调；返回 true = 已经炸了）：这一步开头把位置摆到曲线上、速度设成到下一步位置的差（stepShots 接着按速度挪、打射线）
  local function guide(s, dt)
    s.age = (s.age or 0) + dt
    local H = s.hyper
    if H.phase == "drop" then   -- 掉下去、离开飞机（不点火）
      s.vel += V(0, -GRAV, 0) * dt
      if s.age >= (NC.drop or 0.8) then
        H.phase = "boost"
        G.fx({ k = "nukeIgn", id = s.id, p = s.pos })
        plan(s)
      end
      return false
    end
    local P, Tf = H.path, H.Tf
    local x0 = (s.age - dt - H.t0) / Tf
    local x1 = (s.age - H.t0) / Tf
    if x1 >= 1 then
      G.nukeAt(P[4], s.w, s.src)
      return true
    end
    local p0 = bez(P, prog(math.max(0, x0)))
    local p1 = bez(P, prog(x1))
    s.pos = p0
    s.vel = (p1 - p0) / math.max(dt, 1e-3)
    H.phase = (x1 < 0.25) and "boost" or ((x1 < 0.62) and "glide" or "dive")
    if H.phase == "dive" and not H.diveSent then
      H.diveSent = true
      G.fx({ k = "nukeDive", id = s.id, p = H.tgt, eta = eta(s), team = s.src and s.src.team or nil })
    end
    return false
  end
  G.nukeGuide = guide

  -- Air.lua 的 fireStore 发射时调：设好弹道、发警报、开始冷却；返回这一发的弹道表（给 G.launch 的 s.hyper）
  function G.nukeArm(team, from, aim)
    local tp = aim
    if typeof(tp) ~= "Vector3" then tp = from + V(0, 0, -9000) end
    -- 瞄到天上（看着天边按的）：顺着方向落到地面上
    local gx, gz = tp.X, tp.Z
    local lim = (Map.desert and Map.R or (Map.PLAY or 20000)) - 200
    gx, gz = math.clamp(gx, -lim, lim), math.clamp(gz, -lim, lim)
    local tgt = V(gx, ground(gx, gz), gz)
    readyAt[team] = now() + (NC.cd or 420)
    count += 1
    local H = { phase = "drop", tgt = tgt, team = team }
    local foe = (team == "atk") and "def" or "atk"
    local fd = V(tgt.X - from.X, 0, tgt.Z - from.Z).Magnitude
    local est = (NC.drop or 0.8) + (fd * 1.15 + 2 * math.clamp(fd * 0.32, 1800, 9000)) / ((NC.speed or 5800) * 0.8)
    G.fx({ k = "nukeWarn", p = tgt, eta = est, team = team, r = NC.kill or 950, r2 = NC.hurt or 2000 })
    if G.msgTeam then
      G.msgTeam(foe, "bad", "nuke.incoming")
      G.msgTeam(team, "good", "nuke.launched")
    end
    return H
  end

  ---------------------------------------------------------------- 爆炸

  local SCORCH_FROM = { MAT.Sand, MAT.Ground, MAT.Grass, MAT.LeafyGrass, MAT.Sandstone, MAT.Salt, MAT.Mud, MAT.Snow, MAT.Pavement, MAT.Limestone }
  local function scorch(x, z, gy)
    local R0 = NC.scorch or 560
    local melt = NC.melt or 140
    local mid = (melt + R0) * 0.5
    local C = 64
    local n = math.ceil(R0 / C)
    local done = 0
    for i = -n, n - 1 do
      for k = -n, n - 1 do
        local cx, cz = x + (i + 0.5) * C, z + (k + 0.5) * C
        local d = math.sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
        if d < R0 then
          local h = Map.height(cx, cz)
          -- ReplaceMaterial 的范围要对齐 4 格的体素格子（不对齐 Roblox 直接报错）
          local y0, y1 = math.floor((h - 10) / 4) * 4, math.ceil((h + 6) / 4) * 4
          local xa, xb = math.floor((cx - C / 2) / 4) * 4, math.ceil((cx + C / 2) / 4) * 4
          local za, zb = math.floor((cz - C / 2) / 4) * 4, math.ceil((cz + C / 2) / 4) * 4
          local reg = Region3.new(V(xa, y0, za), V(xb, y1, zb))
          local to = (d < melt) and MAT.CrackedLava or ((d < mid) and MAT.Basalt or MAT.Slate)
          for _, m in ipairs(SCORCH_FROM) do
            pcall(function() T:ReplaceMaterial(reg, 4, m, to) end)
          end
          if to ~= MAT.CrackedLava then pcall(function() T:ReplaceMaterial(reg, 4, MAT.Rock, MAT.Basalt) end) end
          done += 1
          if done % 24 == 0 then task.wait() end
        end
      end
    end
    -- 爆心一个浅坑（空爆的冲击波把地面压下去、炸飞一层）
    local rc = NC.crater or 64
    local hc = math.min(rc * 0.22, 14)
    local Rs = (rc * rc + hc * hc) / (2 * hc)
    pcall(function() T:FillBall(V(x, gy - hc + Rs, z), Rs, MAT.Air) end)
    table.insert(scorched, { x = x, z = z, r = R0 + 8, y0 = gy - hc - 10 })
  end

  -- 实体到爆心的距离（按命中盒边上算：大船、大飞机不是一个点）
  local function entDist(e, pos)
    local cf = e.root.CFrame
    local l = cf:PointToObjectSpace(pos)
    local hs = e.root.Size / 2
    local dx, dy, dz = math.max(0, math.abs(l.X) - hs.X), math.max(0, math.abs(l.Y) - hs.Y), math.max(0, math.abs(l.Z) - hs.Z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  function G.nukeAt(pos, w, src)
    src = src or { team = "none", name = "nuke" }
    local K, H2, AIRR = NC.kill or 950, NC.hurt or 2000, NC.air or 2600
    local gy = ground(pos.X, pos.Z)
    local wNuke = { id = "hn1", kind = "bomb", nuke = true, dmg = 1e7, splash = NC.bld or 1350 }
    src.wid = src.wid or "hn1"
    G.fx({ k = "nuke", p = pos, gy = gy, team = src.team, r = K, r2 = H2 })
    G.nukeLast = { p = pos, t = now(), team = src.team }   -- 测试用
    -- 人：在车里的由车挨（车毁了人跟着没）；外圈按距离衰减（步兵满血 100，外圈边上只掉一点）
    G.boomAt = pos
    for _, P in pairs(G.P) do
      local char = P.char
      local hrp = char and char:FindFirstChild("HumanoidRootPart")
      if hrp and P.alive and not (G.inVeh and G.inVeh(P)) then
        local d = (hrp.Position - pos).Magnitude
        if d < K then G.hurtChar(char, 1e6, src)
        elseif d < H2 then G.hurtChar(char, 260 * (1 - (d - K) / (H2 - K)) ^ 1.25, src) end
      end
    end
    G.boomAt = nil
    -- 车、船、飞机、工事、机器人
    for _, e in ipairs(table.clone(G.ents or {})) do
      if e.alive and e.root then
        local d = entDist(e, pos)
        local R2 = e.air and AIRR or H2
        if d < K then G.damageEnt(e, 1e7, src)
        elseif d < R2 then
          local f = (1 - (d - K) / (R2 - K)) ^ 1.2
          G.damageEnt(e, (e.maxHp or e.hp or 1000) * 1.15 * f, src)
        end
      end
    end
    -- 房子全塌、工事那边的爆炸处理（Battle.lua、Forts.lua 挂在 G.onExplode 上）
    if G.onExplode then G.try("核爆炸房子", G.onExplode, pos, wNuke, src) end
    -- 焦土、弹坑（放到后台慢慢写，不卡这一帧）
    task.spawn(function() G.try("核爆焦土", scorch, pos.X, pos.Z, gy) end)
    -- 辐射区
    local FO = NC.fallout or {}
    if (FO.dur or 0) > 0 then
      table.insert(zones, { p = V(pos.X, gy, pos.Z), r = FO.r or 420, dps = FO.dps or 9, t1 = now() + FO.dur, src = src })
    end
  end

  -- 辐射区：里面的敌人每秒掉血（客户端也画了范围、提示快离开）
  local acc = 0
  local function stepZones(dt)
    if #zones == 0 then return end
    acc += dt
    if acc < 0.5 then return end
    local step = acc
    acc = 0
    local t = now()
    for i = #zones, 1, -1 do
      local z = zones[i]
      if t > z.t1 then
        table.remove(zones, i)
      else
        local r2 = z.r * z.r
        for _, P in pairs(G.P) do
          local hrp = P.alive and P.char and P.char:FindFirstChild("HumanoidRootPart")
          if hrp and not (G.inVeh and G.inVeh(P)) then
            local d = hrp.Position - z.p
            if d.X * d.X + d.Z * d.Z < r2 and math.abs(d.Y) < 200 then G.hurtChar(P.char, z.dps * step, z.src) end
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 回合

  local function restore(list)
    if not World or not World.writeChunk then return end
    for _, c in ipairs(list) do
      local x0 = math.floor((c.x - c.r) / 4) * 4
      local z0 = math.floor((c.z - c.r) / 4) * 4
      local total = math.ceil(2 * c.r / 4) + 1
      -- 按 64 × 64 列一块写（一次写太大的块 WriteVoxels 会卡）；边上的块多写出去一点没关系（开局本来就要回到原样）
      local B = 64
      for i = 0, total - 1, B do
        for k = 0, total - 1, B do
          G.try("填核弹坑", World.writeChunk, T, x0 + i * 4, z0 + k * 4, B, c.y0)
          task.wait()
        end
      end
    end
  end
  G.on("roundStart", function()
    readyAt.atk, readyAt.def = 0, 0
    battleT0 = nil
    table.clear(zones)
    local list = table.clone(scorched)
    table.clear(scorched)
    if #list > 0 then task.spawn(restore, list) end
  end)

  local lastPhase = nil
  function G.nukeStep(dt)
    local R = G.round
    local ph = R and R.phase
    if ph == "battle" and lastPhase ~= "battle" then battleT0 = now() end
    lastPhase = ph
    stepZones(dt)
  end
  -- 每帧跟着服务器主循环走（Heartbeat）
  game:GetService("RunService").Heartbeat:Connect(function(dt) G.try("核弹", G.nukeStep, dt) end)
  local _ = RS
end

return Nuke
