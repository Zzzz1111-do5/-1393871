-- 小队（模拟器；用户 11-23「这个游戏按你想的来弄」）：python3 tools/mock/run.py tools/mock/squads.lua
--   ① 同一边 6 个人：分成 A（4 人）、B（2 人）两个小队，玩家属性 Squad 写好了
--   ② 我死了：部署界面的出生点里有「小队：队友」（他活着、没挨打）；他刚挨了一枪：6 秒内不能往他身边出
--   ③ 往队友身边出生：出生在他旁边几格；④ 客户端：小队面板（标题、队友一行一行）、队友头顶绿标记
--   ⑤ 队友换了阵营：离开小队
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9301, true)
local others = {}
for i = 2, 6 do others[i] = T.join("P" .. i, 9300 + i, false) end
local foe = T.join("F1", 9399, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, "def")
for i = 2, 6 do setTeam(others[i], "def") end
setTeam(foe, "atk")
R.run(2)
local C = T.C
T.leaveMenu()

print("① 分小队")
local sqs = G.squadsOf("def")
local sizes = {}
for id, list in pairs(sqs) do sizes[#sizes + 1] = id .. "=" .. #list end
table.sort(sizes)
check(sqs.A and #sqs.A == 4 and sqs.B and #sqs.B == 2, "守方分成 A 4 人、B 2 人（" .. table.concat(sizes, " ") .. "）")
check(me:GetAttribute("Squad") ~= nil, "玩家属性上写着小队号（" .. tostring(me:GetAttribute("Squad")) .. "）")
local mates = G.squadMates(G.P[me])
check(#mates >= 1, "我的小队有队友（" .. #mates .. " 个）")
local mate = mates[1] and mates[1].pl
check(mate ~= nil and mate:GetAttribute("Squad") == me:GetAttribute("Squad"), "队友的小队号一样")
check(G.P[foe].squad ~= nil and G.P[foe].sqTeam == "atk", "攻方的人分在攻方的小队")

print("② 部署界面：小队队友身边")
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
T.actAsRemote(mate, "deploy", {}, "camp")
T.runUntil(function() return G.P[mate].alive and mate.Character and mate.Character:FindFirstChild("HumanoidRootPart") end, 10)
R.run(1)
G.pushOne(G.P[me])
R.run(0.3)
local function sqSpawn()
  for _, s in ipairs((C.S and C.S.spawns) or {}) do if s.kind == "squad" and s.uid == mate.UserId then return s end end
end
local s = sqSpawn()
check(s ~= nil and s.ok, "出生点里有「" .. (s and C.T("spawn.squad", s.name) or "?") .. "」，能出")
G.hurtChar(mate.Character, 10, { P = G.P[foe], team = "atk", name = "F1" }, mate.Character.HumanoidRootPart)
R.run(0.2)
G.pushOne(G.P[me])
R.run(0.3)
s = sqSpawn()
check(s ~= nil and not s.ok, "队友刚挨了一枪：不能往他身边出")
R.run(G.Config.Squad.safe + 0.5)
G.pushOne(G.P[me])
R.run(0.3)
s = sqSpawn()
check(s ~= nil and s.ok, "过了几秒：又能出了")

print("③ 往队友身边出生")
T.act("deploy", {}, "sq." .. mate.UserId)
T.runUntil(function() return G.P[me].alive and me.Character and me.Character:FindFirstChild("HumanoidRootPart") end, 10)
R.run(0.5)
local a, b = me.Character and me.Character:FindFirstChild("HumanoidRootPart"), mate.Character:FindFirstChild("HumanoidRootPart")
local d = (a and b) and (a.Position - b.Position).Magnitude or 1e9
check(d < 8, string.format("出生在队友旁边（%.1f 格）", d))

print("④ 客户端：小队面板、头顶标记")
R.run(0.5)
local panel = me.PlayerGui:FindFirstChild("SquadHud") and me.PlayerGui.SquadHud:FindFirstChild("Panel")
check(panel ~= nil and panel.Visible, "小队面板显示着")
check(#T.texts(C.T("squad.title", me:GetAttribute("Squad"))) > 0, "标题「" .. C.T("squad.title", me:GetAttribute("Squad")) .. "」")
check(#T.texts(mate.DisplayName) > 0, "队友的名字在面板上")
local marks = 0
for _, dd in ipairs(me.PlayerGui:GetDescendants()) do if dd.Name == "SquadMark" then marks = marks + 1 end end
check(marks >= 1, "队友头顶有绿色标记（" .. marks .. " 个，活着的队友）")

print("⑤ 队友换阵营：离开小队")
setTeam(mate, "atk")
R.run(1.5)
check(G.P[mate].sqTeam == "atk", "换到攻方的小队")
local still = false
for _, Q in ipairs(G.squadMates(G.P[me])) do if Q.pl == mate then still = true end end
check(not still, "我的小队里没有他了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
