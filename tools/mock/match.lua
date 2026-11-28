-- 匹配与补人机（用户 11-26：「点开战先匹配，匹配一分钟后人不够就补人机，两边的人机的车辆要符合我匹配时带的最高权重的载具，
--   跟战雷一样，然后人机的分数也要出现在记分板」）：python3 tools/mock/run.py tools/mock/match.lua
--   ① 开服是「匹配中」，没人点开战不开打；② 点开战排上，到点开准备阶段，记成这一局的人、机库变成局内选车页（主按钮「出击」、匹配时点的那一辆选中，
--      飞机卡禁选、没有「试驾」，客户端直接发 testDrive 服务器也不理——同战雷的出击页），点出击坐进去
--   11-28 用户「被击毁重新召唤载具要有这个界面」（战雷截图）：局内选车改成战雷的出击页（WtSpawn.lua：顶上阵容卡、左栏出击设置、右边大地图、「加入战斗！」），
--     机库不再出来
--   ③ 开打后两队电脑车补满 teamSize（自己这队少一辆），车的战斗等级按我阵容里最高的那辆挑；④ 电脑车组进记分板，打掉车记击毁、得分、阵亡
--   ⑤ 车没了回局内选车页（卡上写这一局的账）、「退出战斗」退出这一局；⑥ 一局打完回到匹配中；⑦ 每局开局拨回早上（一天 48 分钟）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)   -- 跑得久：一行一行写出来（重定向到文件时也看得见进度）
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
check(T.findNamed("HangarTest") ~= nil, "匹配中（还没进局）：右边有「试驾」")

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
-- 用户 11-28 晚「点加入战斗就进入地图里面等着吧 等倒计时结束就开战」（同战雷）：匹配到了直接坐进点的那一辆、出现在自己基地，
--   准备阶段开不了、打不了，屏幕正中倒计时（原来先出局内选车页、再点「出击」——那一页现在是车没了以后才出来，见 ⑤）
local C = T.C
local function goLabel()
  local b = T.findNamed("HangarGo")
  if not b then return nil end
  for _, d in ipairs(b:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Name ~= "GoSub" and d.Text ~= "" then return d.Text end
  end
end
local function spawnGo() return T.findNamed("SpawnGo") end
local function spawnOn() return C.wtSpawnOn and C.wtSpawnOn() == true end
T.runUntil(function() return P.vehicle ~= nil end, 10)
check(P.vehicle ~= nil and P.vehicle.treeKey == key, "匹配到了：直接坐进点的那一辆（" .. tostring(P.vehicle and P.vehicle.treeKey) .. "）")
check(P.match == G.round.n, "记成这一局的人")
R.run(1)
check(not C.hangarGui.Visible and not spawnOn(), "坐在车里：机库、出击页都收起")
check(C.S.inMatch == true and C.wtHold ~= nil and C.wtHold(), "准备阶段：锁住（这一局算自己的、坐在车里）")
local cdBox = T.findNamed("PrepCountdown")
check(cdBox ~= nil and cdBox.Visible, "屏幕正中倒计时")
check(#T.texts("战斗将在") > 0, "写着「战斗将在 N 秒后开始」")
local mvP = P.vehicle
local p0 = mvP.root.Position
T.key(R.Enum.KeyCode.W, true)
R.run(2)
T.key(R.Enum.KeyCode.W, false)
R.run(0.3)
check((mvP.root.Position - p0).Magnitude < 1, string.format("准备阶段按 W 开不动（挪了 %.1f 格）", (mvP.root.Position - p0).Magnitude))
local br = G.treeRoundBr()
check(math.abs(br - myBr) < 0.01, string.format("本局战斗等级 = 我阵容里最高的 %.1f（%.1f）", myBr, br))

print("③ 开打：放开、电脑车补满")
T.runUntil(function() return G.round.phase == "battle" end, 60, 1 / 10)
R.run(0.5)
check(not C.wtHold() and not T.findNamed("PrepCountdown").Visible, "开战：放开、倒计时收起")
do
  local mv0 = P.vehicle
  local q0 = mv0 and mv0.root.Position
  T.key(R.Enum.KeyCode.W, true)
  R.run(2)
  T.key(R.Enum.KeyCode.W, false)
  check(mv0 and (mv0.root.Position - q0).Magnitude > 3, string.format("开战以后按 W 开得动（挪了 %.1f 格）", mv0 and (mv0.root.Position - q0).Magnitude or -1))
end
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

print("⑤ 车没了：回到局内选车页")
local mv = P.vehicle
G.wtRaw = true
G.damageEnt(mv, 1e6, { team = other, name = "bot" })
G.wtRaw = nil
T.runUntil(function() return P.vehicle == nil and not P.alive end, 10)
T.runUntil(function() return spawnOn() end, 20)
check(spawnOn() and not C.hangarGui.Visible, "车被打掉（阵亡效果放完）：回到战雷的出击页")
local card = T.findNamed("Spawn_" .. key)
local spTxt = nil
for _, d in ipairs(card and card:GetDescendants() or {}) do if d.Name == "Sp" then spTxt = d.Text end end
check(spTxt ~= nil and spTxt ~= "", "那一辆卡上写着这一局的账（" .. tostring(spTxt) .. "）")
check(T.findNamed("HangarTest") == nil, "回到局内选车页：还是没有「试驾」")
check(spawnGo() and spawnGo().Text:find("加入战斗！", 1, true) == 1, "主按钮是「加入战斗！（重生次数）」（" .. tostring(spawnGo() and spawnGo().Text) .. "）")
check(T.findNamed("SpawnLeave") ~= nil, "底下有「退出战斗」")
local holder = C.wtSpawnGui and C.wtSpawnGui:FindFirstChild("Holder", true)
check(holder ~= nil and #holder:GetChildren() > 0, "右边是大地图（小地图那张挂过来了）")
-- 服务器也不让局内试驾（Tech.lua testDrive 按 Round.lua G.inMatch 拦）：不回任何提示
T.runUntil(function() return G.rangeReady == true end, 30, 1 / 10)
local nTest = #R.sent
T.act("testDrive", key)
R.run(2)
local why = nil
for i = nTest + 1, #R.sent do
  local s2 = R.sent[i]
  if s2.name == "Msg" and type(s2.args[2]) == "string" and s2.args[2]:find("^tree%.") then why = s2.args[2] end
end
check(G.inMatch ~= nil and G.inMatch(P) and not P.alive and not P.inTest and P.vehicle == nil and why == nil,
  "局内选车：客户端直接发 testDrive，服务器也不让试驾（还在选车页；回的提示 " .. tostring(why) .. "）")
T.press(T.findNamed("SpawnLeave"))
R.run(0.8)
check(P.match == nil, "点「退出战斗」：这一局不打了")
T.runUntil(function() return C.hangarGui.Visible end, 5)
check(C.hangarGui.Visible and not spawnOn() and goLabel() == "加入战斗" and not T.findNamed("LeaveMatch"), "回到普通机库：主按钮「加入战斗」、没有「退出战斗」（" .. tostring(goLabel()) .. "）")
check(T.findNamed("HangarTest") ~= nil, "回到普通机库（局外）：「试驾」回来了")

print("⑥ 打完回到匹配中")
G.roundFinish(mine)
T.runUntil(function() return G.round.phase == "queue" end, 40, 1 / 10)
check(G.round.phase == "queue", "结算完：回到匹配中（" .. tostring(G.round.phase) .. "）")
check(#G.aiVehicles == 0, "电脑车都收走了（" .. #G.aiVehicles .. "）")

print("⑦ 昼夜")
local DC = R.require(R.services.ReplicatedStorage:FindFirstChild("DayClock"))
check(math.abs(DC.PERIOD - 48 * 60) < 1, "一天 48 分钟（" .. DC.PERIOD / 60 .. "）")
local c = DC.clock()
check(c > 7.5 and c < 9, string.format("开局是早上（%.2f 点）", c))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
