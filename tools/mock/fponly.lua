-- 第一人称只留 M1A1、M1A2（模拟器）：python3 tools/mock/run.py tools/mock/fponly.lua
--   用户 11-25：「除了m1a1和a2 其他载具不要做第一人称模式」——Config.FirstPerson.only 白名单（Interior.lua 的 fpAllowed）
--   ① 白名单：m1a1 / m1a2 有，99A、T-90M、歼-20、阿帕奇没有
--   ② 坐进 99A 按 F2：不进车里（还是车外）；坐进 M1A2 按 F2：进车里（11-27 起车外的 C 归车长望远镜，进车内用 F2～F5 / T；车里的 C 照旧换乘员位、最后回车外）
--   ③ 开歼-20 按 V：不进座舱
--   ④ 11-27 审查第 2 条：拆出来的同族变型（VehDefs 的 like：M1、IPM1、科技树的 M1A1、M1A1 HC → m1a1，M1A2、SEP、SEPv3 → m1a2）
--      白名单、车内都退到 like 那一型（原来拆开以后这 7 项进不了车里）；坐进 SEPv3、M1 按 F2 进的是 M1A2 / M1A1 那套车内
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.act("deploy", "rifle", "base")
R.run(2.5)
check(P.alive, "出生了")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))

print("① 白名单")
local ok = C.interiorAllowed
check(ok ~= nil, "有 G.interiorAllowed")
if ok then
  check(ok("m1a1") and ok("m1a2"), "M1A1、M1A2 有第一人称")
  check(not ok("ztz99a") and not ok("t90m") and not ok("j20") and not ok("ah64e"), "99A、T-90M、歼-20、阿帕奇没有")
  -- ④ 同族变型退到 like（M1 一族 7 项）；like 不在白名单的照旧没有（96 式 → 96B、T-90A → T-90M、M2 → M2A3）
  local fam, bad = { "m1", "m1ip", "m1a1base", "m1a1hc", "m1a2base", "m1a2sep", "m1a2sep3" }, {}
  for _, id in ipairs(fam) do if not ok(id) then table.insert(bad, id) end end
  check(#bad == 0, "M1 一族 7 项（like 是 m1a1 / m1a2）有第一人称" .. (#bad > 0 and ("：没有 " .. table.concat(bad, " ")) or ""))
  check(not ok("ztz96base") and not ok("t90a") and not ok("m2a0") and not ok("leo2a5"), "like 不在白名单的（96 式、T-90A、M2、豹 2A5）照旧没有")
end

local function ride(id)
  local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
  if not hrp then return nil end
  local p = hrp.Position + V3(0, 0, -40)
  local d = VD.get(id)
  local e = nil
  pcall(function() e = G.newVehicle("def", id, G.vehBaseAt(d, p.X, p.Z, V3(0, 0, -1))) end)
  if not e then return nil end
  R.run(0.5)
  me.Character:PivotTo(CF(p.X + 6, G.Map.ground(p.X + 6, p.Z) + 3.5, p.Z))
  R.run(0.3)
  T.act("enterVeh", e.id)
  T.runUntil(function() return C.drive ~= nil end, 5)
  R.run(0.5)
  return e
end
local function leave()
  T.remoteAs(me, "Drive", { op = "exit" })
  T.runUntil(function() return C.drive == nil end, 5)
  R.run(1)
end

print("② 坦克按 F2（进驾驶员位）")
local e99 = ride("ztz99a")
check(C.drive ~= nil, "坐进 99A")
T.tap(Enum.KeyCode.F2)
R.run(1)
check(not (C.interiorOn and C.interiorOn()), "99A 按 F2：不进车里")
leave()
local eM = ride("m1a2")
check(C.drive ~= nil, "坐进 M1A2")
T.tap(Enum.KeyCode.F2)
T.runUntil(function() return C.interiorOn and C.interiorOn() end, 6)
check(C.interiorOn and C.interiorOn(), "M1A2 按 F2：进车里")
T.tap(Enum.KeyCode.C)
for _ = 1, 6 do
  if not (C.interiorOn and C.interiorOn()) then break end
  T.tap(Enum.KeyCode.C)
  R.run(0.3)
end
leave()

print("④ 同族变型按 F2：进的是 like 那一型的车内")
for _, c in ipairs({ { "m1a2sep3", "m1a2", "M1A2 SEPv3" }, { "m1", "m1a1", "M1" } }) do
  local ev = ride(c[1])
  check(C.drive ~= nil and C.drive.d and C.drive.d.id == c[1], "坐进 " .. c[3] .. "（" .. tostring(C.drive and C.drive.d and C.drive.d.id) .. "）")
  T.tap(Enum.KeyCode.F2)
  T.runUntil(function() return C.interiorOn and C.interiorOn() end, 6)
  local s = C.interiorState and C.interiorState()
  local key = s and s.cur and s.cur.key
  check(C.interiorOn and C.interiorOn() and key == c[2], c[3] .. " 按 F2：进车里，用的是 " .. tostring(key) .. " 的车内（应为 " .. c[2] .. "）")
  for _ = 1, 6 do
    if not (C.interiorOn and C.interiorOn()) then break end
    T.tap(Enum.KeyCode.C)
    R.run(0.3)
  end
  leave()
  if ev and ev.alive and G.removeEnt then G.removeEnt(ev) end
end

print("③ 飞机按 V")
local p0 = me.Character.HumanoidRootPart.Position
local cf = CF(p0.X, math.max(G.Map.ground(p0.X, p0.Z), 0) + 700, p0.Z)
local ej = G.spawnAircraft("def", "f16", cf, nil, P)
me.Character:PivotTo(cf * CF(4, 0, 0))
T.act("enterVeh", ej.id)
R.run(0.3)
local st = C.fly
check(st ~= nil and st.pilot, "坐进 F-16")
if st then
  st.ground = false
  st.spd = st.d.vMil * 0.8
  st.vel = st.cf.LookVector * st.spd
  st.vdir = st.cf.LookVector
  st.thr, st.gearWant, st.gear = 85, 0, 0
  R.run(0.5)
  T.tap(Enum.KeyCode.V)
  R.run(1)
  check(not (C.interiorOn and C.interiorOn()), "F-16 按 V：不进座舱")
end
T.summary()
