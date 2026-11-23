-- PvE 关卡（模拟器；用户 11-23：「金币 pvp 或者打 pve 来 你搞一些关卡吧」）：python3 tools/mock/run.py tools/mock/pve.lua
--   ① 还没打通第 1 关：选第 2 关不行
--   ② 选第 1 关（服务器只有自己、同一张图）：换成这一关重开；真人在攻方；电脑：敌方 enemies、友军 allies；电脑的反应、散布按 skill 缩放
--   ③ 拿下要求的据点数：这一关赢了；奖励（第一次 × 2）、存档进度 pve = 1；下一局接着打第 2 关
--   ④ 客户端：选地图界面「关卡 PVE」页——第 1 关已通关、第 2 关能打、第 3 关锁着；左上角写着第几关、目标
--   ⑤ 只有自己的时候在对战页点地图：退出关卡（电脑水平、人数回到对战的），重新开一局
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
T.runUntil(function() return P.data ~= nil end, 10)
R.run(1)
local C = T.C
T.leaveMenu()
local PC = G.Config.Pve
local BC = G.Config.Bots
local reaction0 = BC.reaction

print("① 没打通第 1 关：第 2 关不行")
G.ACT.pickPve(P, 2)
R.run(0.3)
check(G.pve == nil, "没换成第 2 关")

print("② 选第 1 关")
G.ACT.pickPve(P, 1)
R.run(0.5)
check(G.pve and G.pve.n == 1, "这个服务器在打第 1 关")
check(P.team == "atk", "真人在攻方")
check(math.abs(BC.reaction - reaction0 / PC.levels[1].skill) < 1e-6, string.format("电脑反应按 skill 缩放（%.2f → %.2f 秒）", reaction0, BC.reaction))
T.runUntil(function() return G.botCount("def") >= PC.levels[1].enemies and G.botCount("atk") >= PC.levels[1].allies end, 12)
check(G.botCount("def") == PC.levels[1].enemies, "敌方电脑 " .. G.botCount("def") .. " 个（要 " .. PC.levels[1].enemies .. "）")
check(G.botCount("atk") == PC.levels[1].allies, "友军电脑 " .. G.botCount("atk") .. " 个（要 " .. PC.levels[1].allies .. "）")
G.pushOne(P)
R.run(0.3)
check(C.S and C.S.pve == 1, "客户端知道在打第 1 关")

print("③ 拿下 1 个据点：赢")
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
G.botsClear()
local c0 = P.data.coins
local pt = nil
for _, s in pairs(G.points) do if s.owner ~= "atk" and not pt then pt = s end end
pt.owner, pt.locked = "atk", true
G.emit("captured", pt)
R.run(0.3)
check(G.round.phase == "end" and G.round.winner == "atk", "这一关赢了（" .. tostring(G.round.phase) .. " / " .. tostring(G.round.winner) .. "）")
local gain = P.data.coins - c0
local want = PC.levels[1].reward * PC.firstBonus
check(gain >= want, string.format("发了金币 +%d（关卡奖励 %d，第一次翻倍；加上这一局的分）", gain, want))
check(P.data.pve == 1, "进度记上了（打通第 1 关）")
check(me:GetAttribute("PveCleared") == 1, "玩家属性 PveCleared = 1")
check(G.pve.next == 2, "下一局：第 2 关（同一张图）")
R.run(G.Config.Round.results + 2)
check(G.pve.n == 2 and G.round.phase == "prep", "新一局是第 2 关")
check(math.abs(BC.reaction - reaction0 / PC.levels[2].skill) < 1e-6, "电脑换成第 2 关的水平")

print("④ 客户端：关卡页、左上角")
R.as("client", function()
  C.showMapPick()
  C.mapPickTab("pve")
end)
R.run(0.5)
local cards = {}
for _, d in ipairs(me.PlayerGui:GetDescendants()) do
  local n = d.Name:match("^Pve_(%d+)$")
  if n then cards[tonumber(n)] = d end
end
local nCards = 0
for _ in pairs(cards) do nCards = nCards + 1 end
check(nCards == #PC.levels, "关卡页 " .. nCards .. " 关")
local function stateOf(n)
  local c = cards[n]
  if not c then return "" end
  for _, d in ipairs(c:GetChildren()) do
    if d.ClassName == "TextLabel" and d.AnchorPoint.X == 1 then return d.Text end
  end
  return ""
end
check(stateOf(1):find(C.T("pve.cleared"), 1, true) ~= nil, "第 1 关：已通关（" .. stateOf(1) .. "）")
check(stateOf(3) == C.T("pve.locked", 2), "第 3 关：锁着（" .. stateOf(3) .. "）")
R.as("client", function() C.mapPickTab("pvp") end)
R.run(0.2)
check(not me.PlayerGui.MapPick.Enabled or (cards[1] and not cards[1].Parent.Visible), "回到对战页：关卡页藏起来")
R.as("client", function() if C.showMapPick then end end)
local gui = me.PlayerGui:FindFirstChild("MapPick")
if gui then gui.Enabled = false end
G.pushOne(P)
R.run(0.5)
local tag = me.PlayerGui:FindFirstChild("Coins") and me.PlayerGui.Coins:FindFirstChild("PveTag")
check(tag ~= nil and tag.Visible and tag.Text:find(C.T("pve.n2"), 1, true) ~= nil, "左上角写着「" .. tostring(tag and tag.Text) .. "」")

print("⑤ 只有自己在对战页点地图：退出关卡、改打对战")
G.ACT.pickMap(P, G.mapId)
R.run(0.5)
check(G.pve == nil, "退出了关卡")
check(math.abs(BC.reaction - reaction0) < 1e-6, "电脑水平回到对战的")
check(G.botWanted == nil, "电脑人数回到对战的")
check(G.round.phase == "prep", "重新开了一局")
R.run(0.5)
check(C.S and C.S.pve == nil and not tag.Visible, "客户端：左上角的关卡行没了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
