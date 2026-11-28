-- 没人投票也能开图、进训练场（模拟器）：python3 tools/mock/run.py tools/mock/mapidle.lua
--   用户 11-28：「然后主页如果我不换snowpeak就没法进训练场」——开服不定图，等进来的人在选地图界面投票；没人投时原来要等
--   Config.MapWaitMax（15 分钟）才按默认那张开，图没开、训练场也不建，试驾一直「训练场还在准备」。现在：
--   ① 有人进来就倒计时 Config.MapVote.idle 秒，到点没人投按 Config.MapDefault 开（不用非得去点雪山）
--   ② 战场建完马上建训练场（原来等远景替身、生成点、寻路、开局都做完）：没投票也能坐进试驾的坦克
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check

T.mapName = "-"   -- 不定图：走投票（Map.profile("-") 不存在）
T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
print("① 进来一个人、谁也不投")
R.run(1)
check(G.mapId == nil, "开服还没定图（等投票）")
local me = T.join("P1", 9901, true)
local t0 = os.clock()
T.runUntil(function() return G.mapId ~= nil end, 200, 0.25)
local waited = os.clock() - t0
check(G.mapId == G.Config.MapDefault, string.format("没人投：按默认那张开（%s）", tostring(G.mapId)))
check(waited < ((G.Config.MapVote and G.Config.MapVote.idle) or 20) + 15, string.format("等了 %.0f 秒（不是十五分钟）", waited))
T.runUntil(function() return G.worldReady end, 900)
check(G.worldReady == true, "战场建好了")
print("② 训练场跟着建，试驾能坐进车")
T.runUntil(function() return G.rangeReady == true end, 300, 0.5)
check(G.rangeReady == true, "训练场建好了")
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 300, 1 / 10)
G.round.endsAt = (G.round.endsAt or 0) + 1e6
R.run(1)
T.act("testDrive", "de_leo2a6")
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
local e = P.vehicle
check(e ~= nil and e.testDrive, "没投票照样坐进了试驾的车")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
