-- 全面大战场——训练场服务器（Places.lua 的 range 地点）在雪山图上试驾：出车点、靶车摆哪儿
--   用户 11-28「试驾你就让我在雪山地图试驾吧搞点靶车」「训练场 还有各种地图单独做成一个服务器」：训练场服务器开的就是雪山图（MapSnow），
--   试驾照 Tech.lua 那一套（每人一条靶道、靶车、靶机），这里给同 MapRange 一样的几个函数（lane / heliPad / runwayStart / runwayLeft /
--   runwaySide / airTarget），外加按地形挑好的靶车位置：
--   · 坦克：攻方主基地北边一排射击位（朝北、顺着河谷看出去），每人一个；靶车在 300～2000 米，每个位置先查从射击位看不看得见
--     （地形、房子挡不挡：Map.lineClear），坡太陡、压着房子、看不见的在附近挪一挪，实在没有就少摆一辆
--   · 靶机：绕圈的那一圈上找最高的地形，飞得比它高（河谷两边是七八百米的雪山，按原来训练场的高度会撞山）
--   · 飞机：攻方基地的跑道（东头朝西起飞，同训练场）；直升机：攻方基地的直升机坪一带；空中靶区在河谷正中（锯木厂和山村之间）
local SR = {}

local V3 = Vector3.new
local M = 2.8   -- 一米多少格
local floor, abs, max, sqrt = math.floor, math.abs, math.max, math.sqrt

function SR.new(Map)
  local R = {}
  local B = Map.BASES and Map.BASES.atk
  if not (B and Map.FOB) then return nil end
  local FOB = Map.FOB
  local function bw(lx, lz) return Map.baseW(B, lx, lz) end
  local ground = Map.ground or Map.height
  local function bldNear(x, z, pad) return Map.bldAt and Map.bldAt(x, z, pad or 10) ~= nil end
  local function flatEnough(x, z, s) return (not Map.slope) or Map.slope(x, z) < (s or 0.22) end

  ---------------------------------------------------------------- 射击线：两头基地各一排（攻方基地北边朝北、守方基地南边朝南），每排 8 条
  --   用户 11-28「如果这个游戏里有两个人同时选择开始试驾怎么办」：每人一条靶道；一个服务器里开坦克试驾的超过 8 个，第 9 个起去另一头那排——
  --   两排都朝着河谷中间打，靶车最远 2000 米：两边的靶车区隔着几百格，不重叠
  R.LANE_W = 330   -- 一条靶道约 118 米宽（河谷里一排八条）
  local PER = 8
  R.LANES = PER * 2
  local lanes, dirs = {}, {}
  -- 射击位：标称位置附近（左右 ±150 格、往河谷里 0～450 格）挑一处平的、不压着房子、往前看得最远的——雪山河谷是故意做得起伏的（交战区崎岖），
  --   车顶那么高往前看，一两公里外多半被小坡挡住；站的地方高一点、前面开阔一点，靶车就能摆远一点。第一次用到那一条才算（雪山的高度函数贵）
  local nominal = {}
  local function row(Bx, first, dir)
    local fx, fz = Map.baseW(Bx, 0, FOB.rect.z0 - 120)   -- 基地那块平地朝河谷那一边再往外 120 格
    local x0 = (Map.valleyX and Map.valleyX(fz) or 0) - (PER - 1) * R.LANE_W / 2
    for j = 1, PER do
      nominal[first + j - 1] = { x0 + (j - 1) * R.LANE_W, fz }
      dirs[first + j - 1] = dir
    end
    return fz
  end
  -- 看不看得见：炮手的瞄准镜在炮塔上（离地约 2.1 米 = 6 格），看得到靶车的炮塔顶（离地 5 格）就算——车体藏在小坡后面、露出炮塔
  --   （战雷里叫车体隐蔽）照样打得着；按车身正中看，雪山河谷里一两公里外几乎都被挡住
  R.EYE, R.AIM = 6.0, 5.0
  local function eyeOf(p) return p + V3(0, R.EYE, 0) end
  local function sees(eye, x, z) return Map.lineClear(eye, V3(x, ground(x, z) + R.AIM, z), 16) end
  local function laneAt(i)
    if lanes[i] then return lanes[i] end
    local nx, nz = nominal[i][1], nominal[i][2]
    local dir = dirs[i]
    local best, bestS = nil, -1
    local nT = 0
    for _, fwd in ipairs({ 0, 150, 300, 450, 600, 800 }) do
      for _, side in ipairs({ 0, 75, -75, 150, -150, 225, -225 }) do
        local x, z = nx + side, nz + dir.Z * fwd
        if flatEnough(x, z, 0.12) and not bldNear(x, z, 18) then
          local eye = eyeOf(V3(x, ground(x, z), z))
          local sc = 0
          for _, d in ipairs({ 300, 700, 1300 }) do
            if sees(eye, x, z + dir.Z * d * M) then sc += 1 end
          end
          sc -= (math.abs(side) + fwd) / 2000   -- 一样远的挑离标称位置近的
          if sc > bestS then best, bestS = { x, z }, sc end
          nT += 1
          if nT % 4 == 0 then task.wait() end
        end
      end
    end
    best = best or { nx, nz }
    lanes[i] = V3(best[1], ground(best[1], best[2]), best[2])
    return lanes[i]
  end
  local DIR = V3(0, 0, -1)
  local fz = row(B, 1, DIR)                                    -- 1～8：攻方基地北边，朝北
  R.FIRE_Z = fz
  local Bd = Map.BASES.def
  if Bd then row(Bd, PER + 1, V3(0, 0, 1)) else R.LANES = PER end   -- 9～16：守方基地南边，朝南
  function R.lane(i)
    i = ((i - 1) % R.LANES) + 1
    return laneAt(i), dirs[i]
  end

  ---------------------------------------------------------------- 靶车：射击方向多少米、往右多少米、来回开的半程（米），按地形挑位置
  -- RANGE 同 Tech.lua（训练场的那一套）；靶道窄一点，往两边偏的收一半。标称位置看不见的：顺着这个方向往近处找（每次近一成，最近到四分之一）、
  --   左右挪（最多 280 米），挑第一个看得见、平、不压房子、跟别的靶车隔开 35 米的——实在没有就少摆一辆
  local cache = {}
  function R.targets(i, RANGE)
    i = ((i - 1) % R.LANES) + 1
    if cache[i] then return cache[i] end
    local p0, dir = laneAt(i), dirs[i]
    local eye = eyeOf(p0)
    local right = V3(-dir.Z, 0, dir.X)
    local out = {}
    local function apart(x, z)
      for _, t in ipairs(out) do
        local dx, dz = t.pos.X - x, t.pos.Z - z
        if dx * dx + dz * dz < (35 * M) ^ 2 then return false end
      end
      return true
    end
    local nT = 0
    for k, r in ipairs(RANGE) do
      local fwd, side, swing = r[1], r[2] * 0.5, r[3] and (r[3] * 0.6) or nil
      local found
      local f = fwd
      while not found and f >= math.max(120, fwd * 0.25) do
        for _, ds in ipairs({ 0, 40, -40, 80, -80, 120, -120, 160, -160, 220, -220, 280, -280 }) do
          local c = p0 + dir * (f * M) + right * ((side + ds) * M)
          local x, z = c.X, c.Z
          if apart(x, z) and flatEnough(x, z, 0.3) and not bldNear(x, z, 14) and not (Map.inBase and Map.inBase(x, z, 40)) then
            nT += 1
            if nT % 6 == 0 then task.wait() end   -- 算地形挺贵（雪山的高度函数）：隔几次让一帧
            if sees(eye, x, z) then found = V3(x, ground(x, z), z) break end
          end
        end
        f = f - fwd * 0.1
      end
      if found then
        -- 来回开的：两头也得看得见、不压房子，不然就停着不动
        if swing then
          for _, sg in ipairs({ 1, -1 }) do
            local q = found + right * (swing * M * sg)
            if not (flatEnough(q.X, q.Z, 0.3) and not bldNear(q.X, q.Z, 14) and sees(eye, q.X, q.Z)) then swing = nil break end
          end
        end
        out[#out + 1] = { k = k, pos = found, swing = swing, dist = (found - p0).Magnitude / M }
      end
    end
    -- 原定的几个位置摆不满（看不见的太多）：再按几档距离补，补到跟原来一样多（停着不动的）
    local want = #RANGE
    for _, f in ipairs({ 250, 400, 550, 850, 1150 }) do
      if #out >= want then break end
      for _, ds in ipairs({ 0, 60, -60, 120, -120, 180, -180, 240, -240 }) do
        local c = p0 + dir * (f * M) + right * (ds * M)
        local x, z = c.X, c.Z
        if apart(x, z) and flatEnough(x, z, 0.3) and not bldNear(x, z, 14) and not (Map.inBase and Map.inBase(x, z, 40)) then
          nT += 1
          if nT % 6 == 0 then task.wait() end
          if sees(eye, x, z) then
            out[#out + 1] = { k = #RANGE + #out + 1, pos = V3(x, ground(x, z), z), dist = f }
            break
          end
        end
      end
    end
    cache[i] = out
    return out
  end

  ---------------------------------------------------------------- 靶机绕的圈
  -- 圈的半径最多 SKY_R 米（河谷一边一公里多宽，再大就绕到山上去了）；圈心挪到河谷中线上
  R.SKY_R = 800
  function R.skyCenter(c)
    local x = Map.valleyX and Map.valleyX(c.Z) or c.X
    return V3(x, c.Y, c.Z)
  end
  -- c 圈心、r 半径（格）、h 原来离地多高（格）：圈上最高的地形再往上 160 米，返回离圈心地面多高（格）
  function R.skyAlt(c, r, h)
    local g0 = ground(c.X, c.Z)
    local top = g0
    for j = 0, 23 do
      local a = j / 24 * math.pi * 2
      top = max(top, ground(c.X + math.cos(a) * r, c.Z + math.sin(a) * r))
    end
    return max(h, top - g0 + 160 * M)
  end

  ---------------------------------------------------------------- 跑道（攻方基地：东西向，东头朝西起飞）、直升机坪、空中靶区
  local A = B.airfield
  local RW = { x0 = A.x - A.len / 2, x1 = A.x + A.len / 2, z = A.z, wid = A.wid }
  local function startX(k) return RW.x1 - 160 - floor(k / 2) * 110 end
  function R.runwayStart(k)
    k = k or 0
    local x, z = startX(k), RW.z + ((k % 2 == 0) and -18 or 18)
    return V3(x, ground(x, z), z), V3(-1, 0, 0)
  end
  function R.runwayLeft(k) return startX(k or 0) - RW.x0 end
  function R.runwaySide(k)
    k = k or 0
    local x, z = startX(k) + ((k % 2 == 0) and -8 or 8), RW.z + RW.wid / 2 + 60
    return V3(x, ground(x, z), z)
  end
  local hx, hz = B.heli.x, B.heli.z
  function R.heliPad(k)
    k = k or 0
    local x, z = hx + (k % 3 - 1) * 70, hz - floor(k / 3) * 70
    return V3(x, ground(x, z), z), DIR
  end
  -- 空中靶区：河谷正中，锯木厂和山村之间（地上的靶车、靶机绕着它）
  local tz = fz - 3300
  local tx = Map.valleyX and Map.valleyX(tz) or 0
  function R.airTarget() return V3(tx, ground(tx, tz), tz) end
  R.dir = DIR
  return R
end

return SR
