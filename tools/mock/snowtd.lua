-- 主界面试驾在雪山图上（模拟器）：python3 tools/mock/run.py tools/mock/snowtd.lua
--   用户 11-28「试驾你就让我在雪山地图试驾吧搞点靶车」、晚上又问「为什么训练场现在还是没有雪山地图」——原来只有单独发布的训练场地点
--   （Places.lua 的 range）才在雪山上试，Studio、只发布了一个地点的照旧去绿草的训练场区块（MapRange）。现在（Tech.lua chooseRM）：
--   ① 战场是雪山图的起始服务器（Studio 一个服务器全包）：开服不建训练场区块；匹配中点试驾 → 坐进车、在战场这张雪山图上（不在训练场区块），
--      攻方基地北边的射击位、朝北；靶车四辆以上、靶机在天上；提示「雪山图上试驾」
--   ② 长按 H 回机库：车、靶车、靶机都收走
--   ③ 有人开战、匹配到了：在这张图上试驾的另一个人回机库（提示「雪山图要开打一局了」）；这张图在打的时候再点试驾 →
--      训练场区块（这时候才建，提示还在准备、好了自动接着试，不用再点）
--   ④ 这一局的真人都退出了（Round.lua）：几秒后收掉这一局（电脑车收走）、回到匹配中；训练场区块里的照旧在试；再点试驾又在雪山图上
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check
local KEY = "de_leo2a6"

T.mapName = "snow"
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.Config.Match.wait = 3
T.runUntil(function() return G.worldReady end, 1200)
R.run(2)
local Map = G.Map
local Zones = Map.Zones
local function zoneOf(e)
  local p = e and e.root and e.root.Position
  return p and Zones.of(p.X, p.Z) or "?"
end
local function dummies()
  local out = { ground = {}, air = {} }
  local f = R.workspace:FindFirstChild("Ents")
  for _, m in ipairs(f and f:GetChildren() or {}) do
    if m:GetAttribute("TestDummy") then
      local e = G.entById and G.entById[m:GetAttribute("EntId")]
      if e and e.alive then table.insert(e.air and out.air or out.ground, e) end
    end
  end
  return out
end
check(G.mapId == "snow", "战场是雪山图（" .. tostring(G.mapId) .. "）")
check(G.rangeFolder == nil and not G.rangeReady, "开服不建训练场区块（试驾在雪山图上）")
check(G.battleRange ~= nil, "雪山图上的靶道（SnowRange）算好了")

local msgs = {}
local msg0 = G.msg
G.msg = function(pl, kind, key, ...)
  msgs[#msgs + 1] = { pl = pl, key = key }
  return msg0(pl, kind, key, ...)
end
local function gotMsg(pl, key, from)
  for i = (from or 0) + 1, #msgs do if msgs[i].pl == pl and msgs[i].key == key then return true end end
  return false
end

local me = T.join("P1", 9611, true)
T.runUntil(function() return G.round ~= nil and G.P[me] ~= nil and G.P[me].data ~= nil end, 30)
local P = G.P[me]
T.leaveMenu()
R.run(1)
check(G.round.phase == "queue", "匹配中（" .. tostring(G.round.phase) .. "）")

print("① 匹配中点试驾：在战场这张雪山图上")
local m0 = #msgs
T.act("testDrive", KEY)
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 30)
local e = P.vehicle
check(e ~= nil and e.testDrive, "坐进试驾的车")
if e then
  local pos = e.root.Position
  local B = Map.BASES.atk
  print(string.format("   车在 (%.0f, %.0f, %.0f)（%s）；攻方基地 (%.0f, %.0f)", pos.X, pos.Y, pos.Z, zoneOf(e), B.x, B.z))
  check(zoneOf(e) ~= "range", "在战场这张雪山图上（不在训练场区块）")
  check(pos.Z < B.z and pos.Z > B.z - 1400 and math.abs(pos.X - B.x) < 2000, "攻方基地北边的射击位上")
  check(e.root.CFrame.LookVector.Z < -0.9, "车头朝北（顺着河谷）")
end
check(gotMsg(me, "tree.testOnSnow", m0), "提示「雪山图上试驾」")
R.run(6)
local D = dummies()
print(string.format("   靶车 %d 辆、靶机 %d 架", #D.ground, #D.air))
check(#D.ground >= 4 and #D.air >= 2, "靶车四辆以上、靶机两架以上")
local allSnow = true
for _, d in ipairs(D.ground) do if zoneOf(d) == "range" then allSnow = false end end
check(allSnow, "靶车也都在雪山图上")

print("② 长按 H 回机库")
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 10)
R.run(1)
local D2 = dummies()
check(not P.alive and P.vehicle == nil and not P.inTest, "回机库了")
check(#D2.ground == 0 and #D2.air == 0, string.format("靶车、靶机都收走了（还剩 %d / %d）", #D2.ground, #D2.air))

print("③ 有人开战：在雪山图上试驾的人回机库；这张图在打的时候再点试驾 → 训练场区块")
local p2 = T.join("P2", 9612, false)
T.runUntil(function() return G.P[p2] ~= nil and G.P[p2].data ~= nil end, 30)
local P2 = G.P[p2]
T.actAsRemote(p2, "testDrive", KEY)
T.runUntil(function() return P2.vehicle ~= nil and P2.vehicle.testDrive end, 30)
check(P2.vehicle ~= nil and zoneOf(P2.vehicle) ~= "range", "P2 在雪山图上试驾（" .. zoneOf(P2.vehicle) .. "）")
local m1 = #msgs
T.act("matchJoin", G.treeLineup(P)[1])
T.runUntil(function() return G.round.phase ~= "queue" end, 20)
check(G.round.phase == "prep", "P1 排上、匹配到了：准备阶段（" .. tostring(G.round.phase) .. "）")
R.run(1)
check(not P2.alive and P2.vehicle == nil and not P2.inTest, "P2 回机库了（这张图要开打）")
check(gotMsg(p2, "tree.testMatch", m1), "P2 收到「雪山图要开打一局了：试驾结束」")
check(#dummies().ground == 0, "P2 的靶车收走了")
local m2 = #msgs
T.actAsRemote(p2, "testDrive", KEY)
R.run(0.5)
check(gotMsg(p2, "tree.rangeBusy", m2), "这张图在打：训练场区块这时候才建（提示还在准备、好了自动接着试）")
T.runUntil(function() return P2.vehicle ~= nil and P2.vehicle.testDrive end, 400, 0.5)
check(P2.vehicle ~= nil and zoneOf(P2.vehicle) == "range", "不用再点、自动接着试：在训练场区块里（" .. zoneOf(P2.vehicle) .. "）")
check(gotMsg(p2, "tree.rangeMatch", m2), "提示「雪山图上正在打一局：这次在训练场试驾」")

print("④ 这一局的真人都退出了：收掉这一局，回到匹配中")
T.runUntil(function() return P.vehicle ~= nil end, 20)
check(P.vehicle ~= nil and P.match == G.round.n, "P1 匹配到了：坐在这一局的车里")
T.runUntil(function() return #(G.aiVehicles or {}) > 0 end, 20)
local nAi = #(G.aiVehicles or {})
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return P.vehicle == nil end, 10)
R.run(0.5)
T.act("matchLeave")
R.run(0.5)
check(P.match == nil, "P1 退出了这一局")
local phaseLeft = G.round.phase
T.runUntil(function() return G.round.phase == "queue" end, 15)
check(G.round.phase == "queue", "几秒后收掉这一局、回到匹配中（退出时 " .. tostring(phaseLeft) .. "）")
R.run(1)
local nAi2 = 0
for _, x in ipairs(G.aiVehicles or {}) do if x.alive then nAi2 = nAi2 + 1 end end
check(nAi > 0 and nAi2 == 0, string.format("电脑车收走了（退出前 %d 辆，现在 %d 辆）", nAi, nAi2))
check(P2.vehicle ~= nil and P2.vehicle.alive and P2.inTest, "训练场区块里的 P2 照旧在试驾")
T.remoteAs(p2, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P2.alive end, 10)
R.run(1)
local m3 = #msgs
T.act("testDrive", KEY)
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 30)
check(P.vehicle ~= nil and zoneOf(P.vehicle) ~= "range" and gotMsg(me, "tree.testOnSnow", m3), "再点试驾：又在雪山图上（" .. zoneOf(P.vehicle) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
