-- 空中相撞（模拟器）：python3 tools/mock/run.py tools/mock/aircollide.lua
--   用户 11-28「然后飞机要有物理引擎能相撞」（Air.lua collideStep）：
--   ① 两架迎头对飞、这一下就交错过去（一帧飞过三百格）：照样算撞上（按走过的那一段算最近离多近），两架都毁
--   ② 擦过（隔着两个球半径和的八成）：各掉一半血，都还活着
--   ③ 隔得比半径和远：没事；地上停着的两架挨着也不算
--   ④ 撞掉的是敌机：算对面那个人打下来的（拿分、记击落）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local Y = 1600
local function pair(id1, id2, dz, team2)
  local a = G.spawnAircraftAir("atk", id1, R.CFrame.lookAt(V3(0, Y, 0), V3(1, Y, 0)), nil, nil, nil, 200)
  local b = G.spawnAircraftAir(team2 or "def", id2, R.CFrame.lookAt(V3(300, Y, dz), V3(-1, Y, dz)), nil, nil, nil, 200)
  return a, b
end
local function move(e, p) G.moveEnt(e, R.CFrame.lookAt(p, p + e.root.CFrame.LookVector)) end
print("① 迎头对飞，一帧就交错过去")
local a, b = pair("f16", "j10", 0)
check(a ~= nil and b ~= nil and not a.onGround and not b.onGround, "两架在天上")
G.airCollideStep()   -- 记下起点
move(a, V3(200, Y, 0))
move(b, V3(100, Y, 0))
local n0 = G.airCollisions
G.airCollideStep()
check(G.airCollisions == n0 + 1, "交错过去也算撞上（按走过的那一段算）")
check(not a.alive and not b.alive, "正面撞上：两架都毁")
R.run(1)
print("② 擦过")
local rA, rB = G.airColR({ def = { kind = "jet", L = 42, W = 27 } }), G.airColR({ def = { kind = "jet", L = 42, W = 27 } })
local c, d = pair("f16", "f16", (rA + rB) * 0.8, "atk")
G.airCollideStep()
move(c, V3(200, Y, 0))
move(d, V3(100, Y, (rA + rB) * 0.8))
local hc, hd = c.hp, d.hp
G.airCollideStep()
check(c.alive and d.alive and c.hp < hc * 0.75 and d.hp < hd * 0.75, string.format("擦过：都还活着、各掉一半血（%.0f → %.0f、%.0f → %.0f）", hc, c.hp, hd, d.hp))
pcall(G.removeEnt, c) pcall(G.removeEnt, d)
print("③ 隔得远没事；地上停着的不算")
local e1, e2 = pair("f16", "f16", (rA + rB) * 1.3, "atk")
G.airCollideStep()
move(e1, V3(200, Y, 0))
move(e2, V3(100, Y, (rA + rB) * 1.3))
local n1 = G.airCollisions
G.airCollideStep()
check(G.airCollisions == n1 and e1.alive and e2.alive and e1.hp == e1.maxHp, "隔着 1.3 倍半径和：没撞")
e1.onGround, e2.onGround = true, true
move(e2, V3(200, Y, 4))
G.airCollideStep()
G.airCollideStep()
check(G.airCollisions == n1 and e1.alive and e2.alive, "地上停着、挨在一起：不算撞")
pcall(G.removeEnt, e1) pcall(G.removeEnt, e2)
print("④ 撞掉敌机：算对面那个人打下来的")
local me = T.join("P1", 9941, false)
local P = G.P[me]
P.team = "atk"
local f, g = pair("f16", "j10", 0)
f.driver = P
local got = nil
G.on("entDied", function(ent, src) if ent == g then got = src end end)
G.airCollideStep()
move(f, V3(200, Y, 0))
move(g, V3(100, Y, 0))
G.airCollideStep()
check(not g.alive and got ~= nil and got.P == P, "敌机记在撞它的人头上（" .. tostring(got and got.name) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
