-- 匹配与补人机（用户 11-26：「点开战先匹配，匹配一分钟后人不够就补人机，两边的人机的车辆要符合我匹配时带的最高权重的载具，
--   跟战雷一样，然后人机的分数也要出现在记分板」）：python3 tools/mock/run.py tools/mock/match.lua
--   ① 开服是「匹配中」，没人点开战不开打；② 点开战排上，到点开准备阶段，人坐进点的那一辆、记成这一局的人
--   ③ 开打后两队电脑车补满 teamSize（自己这队少一辆），车的战斗等级按我阵容里最高的那辆挑；④ 电脑车组进记分板，打掉车记击毁、得分、阵亡
--   ⑤ 一局打完回到匹配中；⑥ 每局开局拨回早上（一天 48 分钟）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 6   -- 测试里匹配等 6 秒（真游戏 60 秒）
T.runUntil(function() return G.worldReady end, 900)

local me = T.join("P1", 9801, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
T.leaveMenu()
R.run(1)

print("① 开服：匹配中")
check(G.round.phase == "queue", "开服以后是匹配中（" .. tostring(G.round.phase) .. "）")
R.run(8)
check(G.round.phase == "queue", "没人点开战：一直等着，不开打")
check(G.round.queueEnds == nil, "没人排：不起算倒计时")

print("② 点开战")
local key = G.treeLineup(P)[1]
check(key ~= nil, "出击阵容里有车：" .. tostring(key))
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local myBr = TT.lineupBr(G.treeLineup(P))
T.act("matchJoin", key)
R.run(0.5)
check(P.queued == key, "排上了（" .. tostring(P.queued) .. "）")
local qs = G.queueState()
check(qs and qs.n == 1 and qs.left and qs.left <= 6 and qs.left >= 4, string.format("匹配状态：%s 人、还剩 %s 秒", tostring(qs and qs.n), tostring(qs and qs.left)))
T.act("matchCancel")
R.run(0.5)
check(P.queued == nil, "再点取消")
R.run(1)
check(G.round.queueEnds == nil, "都取消了：停表")
T.act("matchJoin", key)
R.run(0.5)
T.runUntil(function() return G.round.phase ~= "queue" end, 12)
check(G.round.phase == "prep", "到点：开准备阶段（" .. tostring(G.round.phase) .. "）")
T.runUntil(function() return P.vehicle ~= nil end, 10)
check(P.vehicle ~= nil and P.vehicle.treeKey == key, "自动坐进点的那一辆（" .. tostring(P.vehicle and P.vehicle.treeKey) .. "）")
check(P.match == G.round.n, "记成这一局的人")
local br = G.treeRoundBr()
check(math.abs(br - myBr) < 0.01, string.format("本局战斗等级 = 我阵容里最高的 %.1f（%.1f）", myBr, br))

print("③ 开打：电脑车补满")
T.runUntil(function() return G.round.phase == "battle" end, 60, 1 / 10)
T.runUntil(function()
  local n = { atk = 0, def = 0 }
  for _, e in ipairs(G.aiVehicles) do if e.alive then n[e.team] = n[e.team] + 1 end end
  local ts = G.Config.Wt.teamSize
  local mine = P.team
  local other = (mine == "atk") and "def" or "atk"
  return n[mine] >= ts - 1 and n[other] >= ts
end, 60, 1 / 10)
local n = { atk = 0, def = 0 }
local brOk, brAll, brs = 0, 0, {}
for _, e in ipairs(G.aiVehicles) do
  if e.alive then
    n[e.team] = n[e.team] + 1
    local it = e.treeKey and TT.byKey[e.treeKey]
    if it then
      brAll = brAll + 1
      table.insert(brs, TT.brText(it.br))
      if it.br <= br + 0.05 and it.br >= br - 1.05 then brOk = brOk + 1 end
    end
  end
end
local ts = G.Config.Wt.teamSize
local mine = P.team
local other = (mine == "atk") and "def" or "atk"
check(n[mine] == ts - 1 and n[other] == ts, string.format("电脑车：我这队 %d 辆（补到 %d 减我 1）、对面 %d 辆", n[mine], ts, n[other]))
check(brAll > 0 and brOk == brAll, string.format("电脑车的战斗等级都在 %.1f−1.0～%.1f 里（%d / %d：%s）", br, br, brOk, brAll, table.concat(brs, " ")))

print("④ 记分板")
local board = G.aiBoard()
local rows = { atk = 0, def = 0 }
for _, r in ipairs(board) do if r.bot then rows[r.t] = rows[r.t] + 1 end end
check(rows[mine] == ts - 1 and rows[other] == ts, string.format("记分板里电脑车组：我这队 %d 行、对面 %d 行", rows[mine], rows[other]))
-- 我这队的一辆电脑车打掉对面一辆电脑车
local killer, victim
for _, e in ipairs(G.aiVehicles) do
  if e.alive and e.team == mine and not killer then killer = e end
  if e.alive and e.team == other and not victim then victim = e end
end
local kc, vc = killer.ai.crew, victim.ai.crew
local s0 = kc.s
G.wtRaw = true   -- 直接扣血打死（不走战雷式伤害的模块判定）
G.damageEnt(victim, 1e6, { team = mine, name = kc.name, bot = kc })
G.wtRaw = nil
R.run(0.3)
check(kc.vk == 1 and kc.k == 1 and kc.s > s0, string.format("打掉一辆：击毁 %d、击杀 %d、得分 %d → %d", kc.vk, kc.k, s0, kc.s))
check(vc.d == 1, "被打掉的那个车组记一次阵亡（" .. tostring(vc.d) .. "）")
local found = false
for _, r in ipairs(G.aiBoard()) do if r.n == kc.name and r.vk == 1 then found = true end end
check(found, "记分板上那一行跟着变")
-- 被打掉的车组下一辆还是他开（名单不变长）
R.run(50, 1 / 10)
check(#G.aiCrews[other] == ts, string.format("对面名单还是 %d 个人（%d）", ts, #G.aiCrews[other]))

print("⑤ 打完回到匹配中")
G.roundFinish(mine)
T.runUntil(function() return G.round.phase == "queue" end, 40, 1 / 10)
check(G.round.phase == "queue", "结算完：回到匹配中（" .. tostring(G.round.phase) .. "）")
check(#G.aiVehicles == 0, "电脑车都收走了（" .. #G.aiVehicles .. "）")

print("⑥ 昼夜")
local DC = R.require(R.services.ReplicatedStorage:FindFirstChild("DayClock"))
check(math.abs(DC.PERIOD - 48 * 60) < 1, "一天 48 分钟（" .. DC.PERIOD / 60 .. "）")
local c = DC.clock()
check(c > 7.5 and c < 9, string.format("开局是早上（%.2f 点）", c))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
