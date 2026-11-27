-- 试驾（用户 11-25「都要做」）：python3 tools/mock/run.py tools/mock/wttest.lua
--   ① 科技树详情点「试驾」（没研究、没买的车也行）：人坐在车里，在训练场（自己一块区块 Zones.RANGE，用户 11-26 晚「把训练场单独做一张地图吧」）
--      自己那条靶道的射击线上；改装全装；前面七辆靶车
--   ② 打掉靶车：不加分、不记击毁；10 秒后再摆一辆
--   ③ 下车：回机库，靶车清掉，兵力不扣
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))

print("① 试驾")
local me = T.join("P1", 9501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local key = "de_leo2a6"
local it = TT.get(key)
check(it ~= nil and not TT.owned(G.treeOf(P), key), "挑一辆没买的：" .. tostring(it and it.name))
-- 像玩家一样：开科技树、点这一格、点「试驾」
local C = T.C
R.as("client", function() C.openTechTree() end)
R.run(0.3)
local panel = C.treeGui
local function find(root, name)
  for _, c in ipairs(root and root:GetDescendants() or {}) do if c.Name == name then return c end end
end
local nat = find(panel, "Nat_de")
if nat then T.press(nat) R.run(0.3) end
local card = find(panel, "Card_" .. key)
if card then T.press(card) R.run(0.3) end
local tb = find(panel, "TestBtn")
check(tb ~= nil, "详情里有「试驾」")
local score0, tk0 = P.score or 0, G.round.tickets
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
local e = P.vehicle
check(e ~= nil and e.testDrive and e.model:GetAttribute("TreeKey") == key, "坐在试驾的车里（" .. tostring(e and e.def and e.def.id) .. "）")
if e then
  local p = e.root.CFrame.Position
  local Zn, RM = G.Map.Zones, G.Map.Range
  check(Zn ~= nil and Zn.of(p.X, p.Z) == "range", string.format("在训练场那一块（%.0f, %.0f）", p.X, p.Z))
  if RM then
    local lp = RM.lane(1)
    check(math.abs(p.Z - lp.Z) < 60 and math.abs(p.Y - (RM.ground(p.X, p.Z) + (e.def.H or 4) / 2)) < 12,
      string.format("停在射击线上（离射击线 %.0f 格）", p.Z - lp.Z))
  end
  check((e.model:GetAttribute("ModSpd") or 1) > 1.1 and e.wtFx and e.wtFx.repair and e.wtFx.ext, "改装全装上了（车速 ×" .. tostring(e.model:GetAttribute("ModSpd")) .. "、能修、有灭火器）")
end
local dummies = {}
for _, x in ipairs(G.vehicles or {}) do if x.alive and x.testDummy then table.insert(dummies, x) end end
check(#dummies == 7, "前面摆了 7 辆靶车（" .. #dummies .. "）")
-- 用户 11-25「试驾场也多一点坦克和天上的飞机」：天上三架靶机（借无人机自动盘旋绕圈）；两辆靶车横着来回开
local drones = {}
for _, x in ipairs(G.ents or {}) do if x.alive and x.air and x.testDummy then table.insert(drones, x) end end
check(#drones == 3, "天上三架靶机（" .. #drones .. "）")
local p0 = {}
for i, x in ipairs(dummies) do p0[i] = x.root.CFrame.Position end
local d0 = drones[1] and drones[1].root.CFrame.Position
R.run(3)
local moved = 0
for i, x in ipairs(dummies) do
  local dd = (x.root.CFrame.Position - p0[i]).Magnitude
  if x.alive and dd > 5 then moved = moved + 1 end
  if x.testSwing then print(string.format("  来回开的靶车 %s：%.1f 格", x.def.id, dd)) end
end
check(moved == 2, "两辆靶车在跑（" .. moved .. " 辆动了）")
check(drones[1] and d0 and (drones[1].root.CFrame.Position - d0).Magnitude > 50 and drones[1].root.CFrame.Position.Y > 200, "靶机在天上飞着")
check(not (drones[1] and drones[1].driver), "靶机没人开、不还手")
local tm = {}
for _, x in ipairs(dummies) do table.insert(tm, tostring(x.team) .. "/" .. tostring(x.model:GetAttribute("Team"))) end
print("  靶车队伍：" .. table.concat(tm, " "), "玩家队伍", tostring(P.team), "试驾车队伍", tostring(e and e.team))

print("② 打掉靶车")
if dummies[1] then
  local s = G.wtState and G.wtState(P)
  local vk0 = s and s.vk or 0
  G.damageEnt(dummies[1], (dummies[1].hp or 0) + 1e6, { P = P })
  R.run(1)
  check((P.score or 0) == score0 and ((s and s.vk) or 0) == vk0, string.format("不加分、不记击毁（得分 %d → %d）", score0, P.score or 0))
  R.run(11)
  local n = 0
  for _, x in ipairs(G.vehicles or {}) do if x.alive and x.testDummy then n = n + 1 end end
  check(n == 7, "10 秒后又摆了一辆（" .. n .. " 辆）")
end

print("③ 下车回机库")
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
R.run(1)
local left = 0
for _, x in ipairs(G.vehicles or {}) do if x.alive and x.testDummy then left = left + 1 end end
check(not P.alive and left == 0, "回机库了，靶车清掉（剩 " .. left .. " 辆）")
check(G.round.tickets == tk0, "兵力没扣（" .. tostring(tk0) .. " → " .. tostring(G.round.tickets) .. "）")
check(not P.inTest, "不在试驾里了")
local nd = 0
for _, x in ipairs(G.ents or {}) do if x.alive and x.testDummy then nd = nd + 1 end end
check(nd == 0, "靶机也收走了（剩 " .. nd .. "）")

print("④ 试驾飞机：停在训练场跑道上，北边空中靶区有靶机、靶车")
R.run(8)
local akey = (P.team == "atk") and "cn_j6" or "us_f16c"
T.act("testDrive", akey)
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
local ea = P.vehicle
check(ea ~= nil and ea.air and ea.testDrive, "坐进了试驾的飞机（" .. tostring(ea and ea.def and ea.def.id) .. "）")
if ea then
  local pa = ea.root.CFrame.Position
  local gh = G.Map.height(pa.X, pa.Z)
  check(pa.Y - math.max(gh, 0) < 25, string.format("停在地上（离地 %.1f 格）", pa.Y - math.max(gh, 0)))
  local RM = G.Map.Range
  if RM then
    local A = RM.airfield()
    check(math.abs(pa.Z - A.z) < A.wid / 2 and math.abs(pa.X - A.x) < A.len / 2, string.format("在训练场跑道上（离跑道中心 %.0f, %.0f 格）", pa.X - A.x, pa.Z - A.z))
  end
end
R.run(1)
local da, dg = 0, 0
for _, x in ipairs(G.ents or {}) do
  if x.alive and x.testDummy then if x.air then da = da + 1 else dg = dg + 1 end end
end
check(da == 3 and dg == 6, string.format("三架靶机、六辆地面靶（%d / %d）", da, dg))
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
if P.alive and P.vehicle and G.ACT.exitVeh then G.ACT.exitVeh(P) end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
