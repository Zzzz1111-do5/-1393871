-- 开服就能试驾（模拟器）：python3 tools/mock/run.py tools/mock/tdboot.lua
--   用户 11-28「主界面不切地图就试驾不了」：原来训练场要等投票定图（没人投要等二十秒）、战场整张建完才开始建，
--   主界面点试驾一直「训练场还在准备」。现在训练场开服就建（init.server.lua），试驾的人直接生在训练场（Round.lua deploy 的 P.testSpawnCF），
--   不看战场的出生点、不看开没开局：
--   ① 进服、谁也不投票、停在主界面，隔一秒点一次试驾：战场的图还没定就坐进了试驾的车，车在训练场那一块
--   ② 点「开战」（没选过图：用户 11-28 晚起不再进来二十秒就替人定图）→ 按默认那张开图、战场建完：试驾的车还在（不被开局清掉），没有报错
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check
T.mapName = "-"   -- 不定图：走投票
T.mapIds = "city,snow"   -- 两张都能选（11-28 晚起钢城收起来、只剩雪山时开服直接建）
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local RS = R.services.ReplicatedStorage
local Zones = R.require(RS:FindFirstChild("Zones"))
R.run(0.5)
print("① 进服、不投票，主界面点试驾")
local me = T.join("P1", 9911, true)
local P = G.P[me]
local key = TEST_ARGS:match("key=(%S+)") or "de_leo2a6"
local t, okAt, mapAt = 0, nil, nil
local busy = 0
local m0 = G.msg
G.msg = function(pl, kind, k, ...)
  if k == "tree.rangeBusy" then busy = busy + 1 end
  return m0(pl, kind, k, ...)
end
while t < 60 do
  T.act("testDrive", key)
  R.run(1, 1 / 10)
  t = t + 1
  if P.vehicle and P.vehicle.testDrive then okAt = t break end
end
print(string.format("   %s 秒坐进车（「训练场还在准备」%d 次）；这时战场的图：%s", tostring(okAt), busy, tostring(G.mapId)))
check(okAt ~= nil and okAt <= 15, "开服十几秒内坐进了试驾的车（" .. tostring(okAt) .. " 秒）")
check(okAt ~= nil and G.mapId == nil, "那时战场的图还没定（不用等投票）")
local e = P.vehicle
local p = e and e.root and e.root.Position
check(p ~= nil and Zones.of(p.X, p.Z) == "range", "车在训练场那一块")
print("② 点开战（没选过图）→ 按默认那张开图、战场建完")
R.run(5)
check(G.mapId == nil, "没人选图、没人点开战：图一直不定（" .. tostring(G.mapId) .. "）")
T.act("matchJoin", key)
T.runUntil(function() return G.mapId ~= nil end, 30, 0.25)
check(G.mapId == (G.Config.MapDefault or "city"), "点开战按默认那张开（" .. tostring(G.mapId) .. "）")
T.runUntil(function() return G.worldReady end, 900)
T.runUntil(function() return G.round and G.round.phase ~= "boot" end, 60)
R.run(3)
print(string.format("   开的是 %s，局 %s", tostring(G.mapId), tostring(G.round and G.round.phase)))
check(G.mapId ~= nil and G.worldReady == true, "默认那张图开了、建好了")
check(P.vehicle == e and e ~= nil and e.alive ~= false, "试驾的车还在（开局没把它清掉）")
print("③ 两个人同一刻点试驾（用户 11-28「如果这个游戏里有两个人同时选择开始试驾怎么办」）")
local q1 = T.join("P2", 9912, false)
local q2 = T.join("P3", 9913, false)
R.run(2)
local Q1, Q2 = G.P[q1], G.P[q2]
T.actAsRemote(q1, "testDrive", key)   -- 照真游戏走远程事件（服务器那边一个人一个线程：雪山图上的靶道第一次用到要算几帧）
T.actAsRemote(q2, "testDrive", key)   -- 同一帧：第一个人还没生出来、没登记
T.runUntil(function() return Q1.vehicle ~= nil and Q2.vehicle ~= nil end, 30)
local v1, v2 = Q1.vehicle, Q2.vehicle
local gap = (v1 and v2) and (v1.root.Position - v2.root.Position).Magnitude or 0
check(v1 ~= nil and v2 ~= nil and gap > 300, string.format("分到不同的靶道（两辆车隔 %.0f 格，不是生在一起）", gap))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
