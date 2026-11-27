-- 雪山：坦克在雪地、冰面上会滑（用户 11-26 夜「然后坦克要能滑雪」）：python3 tools/mock/run.py tools/mock/snowdrive.lua
--   ① 横着停在陡雪坡上：往坡下横着溜；缓坡上停得住  ② 车头朝下停在陡雪坡上：刹不住，往下溜
--   ③ 冰面（河上的冰）刹车距离比压实的雪路长得多；冰上打方向车尾甩得多（车头和去向差得多）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

T.wtMode = true
T.mapName = "snow"
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local Map = G.Map
local me = T.join("P1", 9901, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C
T.act("testDrive", "de_leo2a6")
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 15)
R.run(2)
local st = C.drive
check(st ~= nil, "坐在车里")
if not st then T.summary() return end
local e = P.vehicle
local Enum = R.Enum

local function grad(x, z)
  local h = 6
  return (Map.height(x + h, z) - Map.height(x - h, z)) / (2 * h), (Map.height(x, z + h) - Map.height(x, z - h)) / (2 * h)
end
-- 摆车：车头朝 yaw（0 = 朝 −Z），停着
local function place(x, z, yaw)
  local y = Map.ground(x, z)
  st.pos = V3(x, y, z)
  st.yaw, st.travel = yaw, yaw
  st.speed, st.slL, st.yr = 0, 0, 0
  st.airS, st.sus, st.gY0, st.gVy, st.dropT = nil, nil, nil, 0, nil
  st.surf, st.surfT = nil, 0
  G.moveEnt(e, CF(x, y + e.def.H / 2, z) * R.CFrame.Angles(0, yaw, 0))
end
local function yawOf(fx, fz) return math.atan2(-fx, -fz) end
-- 找一处：雪地、不在路上、坡度在 [a, b]、周围 20 格坡向差不多
local function findSlope(a, b)
  -- 模拟器的噪声和 Roblox 的不一样（地形细节不同）：搜得密一点、范围大一点
  for x = -3200, 3200, 23 do
    for z = -5200, 5200, 29 do
      if Map.valleyD(x, z) < 0.9 and not Map.onRoad(x, z, 40) and not Map.bldAt(x, z, 40) and Map.riverDist(x, z) > 200 then
        local gx, gz = grad(x, z)
        local s = math.sqrt(gx * gx + gz * gz)
        if s >= a and s <= b and Map.material(x, z, Map.ground(x, z), s) == Enum.Material.Snow then
          local ok = true
          for _, o in ipairs({ { 14, 0 }, { -14, 0 }, { 0, 14 }, { 0, -14 } }) do
            local hx, hz = grad(x + o[1], z + o[2])
            local s2 = math.sqrt(hx * hx + hz * hz)
            if s2 < a * 0.85 or s2 > b * 1.15 or (hx * gx + hz * gz) / (s * s2) < 0.9 then ok = false end
          end
          if ok then return x, z, gx, gz, s end
        end
      end
    end
  end
end
local function settle(sec)
  local n = math.floor(sec * 30)
  for _ = 1, n do R.run(1 / 30) end
end

print("① 横着停在雪坡上")
local x, z, gx, gz, s = findSlope(0.58, 0.85)
check(x ~= nil, "找到一处陡雪坡" .. (x and string.format("（%d, %d，坡度 %.2f）", x, z, s) or ""))
if x then
  local dx, dz = -gx / s, -gz / s   -- 下坡方向
  place(x, z, yawOf(dz, -dx))       -- 车头顺着等高线
  settle(0.2)
  local p0 = st.pos
  settle(3)
  local mv = st.pos - p0
  local down = mv.X * dx + mv.Z * dz
  check(down > 3, string.format("往坡下横着溜了 %.1f 格（横滑速度 %.1f 格 / 秒）", down, math.abs(st.slL or 0)))
end
local x2, z2, gx2, gz2, s2 = findSlope(0.04, 0.12)
if x2 then
  local dx, dz = -gx2 / s2, -gz2 / s2
  place(x2, z2, yawOf(dz, -dx))
  settle(0.2)
  local p0 = st.pos
  settle(3)
  check((st.pos - p0).Magnitude < 0.8, string.format("缓坡（%.2f）上停得住（挪了 %.2f 格）", s2, (st.pos - p0).Magnitude))
end

print("② 车头朝下停在陡雪坡上")
if x then
  local dx, dz = -gx / s, -gz / s
  place(x, z, yawOf(dx, dz))
  settle(0.2)
  local p0 = st.pos
  settle(3)
  local mv = st.pos - p0
  check(mv.X * dx + mv.Z * dz > 3, string.format("刹不住往下溜了 %.1f 格", mv.X * dx + mv.Z * dz))
end

print("③ 冰面：刹车、打方向")
-- 河上的冰（山村西北那一段，离桥远）
local ix, iz = nil, nil
local R1, R2 = nil, nil
-- 河道（弯过的）上找一段：离桥远、在谷里、前后 20 个点（1.2 公里）上都是冰
local RP = Map.RIVER_PTS
for i = 1, #RP - 4 do
  local px, pz = RP[i][1], RP[i][2]
  local nearB = false
  for _, B in ipairs(Map.BRIDGES) do if (B.x - px) ^ 2 + (B.z - pz) ^ 2 < 400 * 400 then nearB = true end end
  if not ix and not nearB and Map.valleyD(px, pz) < 0.8 and Map.onIce(px, pz) and Map.onIce(RP[i + 4][1], RP[i + 4][2]) then
    ix, iz = px, pz
    R1, R2 = RP[i], RP[i + 4]
  end
end
check(ix ~= nil, "找到河上的冰面")
local function brakeDist(x0, z0, fx, fz)
  place(x0, z0, yawOf(fx, fz))
  settle(0.2)
  st.speed = 16
  local p0 = st.pos
  T.key(Enum.KeyCode.S, true)
  local n = 0
  while st.speed > 0.3 and n < 300 do R.run(1 / 30) n = n + 1 end
  T.key(Enum.KeyCode.S, false)
  return (st.pos - p0).Magnitude
end
local roadD, iceD = nil, nil
do   -- 压实的雪路：主路锯木厂往北那一段
  local A, B = { -1150, 3300 }, { -900, 2200 }
  local L = math.sqrt((B[1] - A[1]) ^ 2 + (B[2] - A[2]) ^ 2)
  local fx, fz = (B[1] - A[1]) / L, (B[2] - A[2]) / L
  roadD = brakeDist(A[1] + fx * 300, A[2] + fz * 300, fx, fz)
end
if ix then
  local fx, fz = R2[1] - R1[1], R2[2] - R1[2]
  local L = math.sqrt(fx * fx + fz * fz)
  iceD = brakeDist(ix, iz, fx / L, fz / L)
end
check(roadD and iceD and iceD > roadD * 2, string.format("刹车距离：雪路 %.1f 格，冰面 %.1f 格", roadD or -1, iceD or -1))
if ix then   -- 冰上打方向：车头转过去了，车还往原来的方向滑
  local fx, fz = R2[1] - R1[1], R2[2] - R1[2]
  local L = math.sqrt(fx * fx + fz * fz)
  place(ix, iz, yawOf(fx / L, fz / L))
  settle(0.2)
  st.speed = 14
  T.key(Enum.KeyCode.D, true)
  local worst = 0
  for _ = 1, 30 do
    R.run(1 / 30)
    worst = math.max(worst, math.abs(st.slipA or 0))
  end
  T.key(Enum.KeyCode.D, false)
  check(math.deg(worst) > 8, string.format("冰上打方向车尾甩出去（车头和去向最多差 %.0f°）", math.deg(worst)))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
