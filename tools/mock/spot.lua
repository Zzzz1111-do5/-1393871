-- 人人都能按 Z 标记敌人（模拟器；用户 11-23「这个游戏按你想的来弄」）：python3 tools/mock/run.py tools/mock/spot.lua
--   ① 敌人站在面前空地上：对着他按 Z（客户端发 ACT.spot）→ 守方的标记表里有他、加了标记分；客户端收到 spots
--   ② 冷却：马上再按不算；③ 倒地的人不能标记
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9401, true)
local foe = T.join("F1", 9402, false)
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
setTeam(foe, "atk")
R.run(1)
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 10)
T.act("deploy", {}, "camp")
T.actAsRemote(foe, "deploy", {}, "fleet")
T.runUntil(function() return G.P[me].alive and G.P[foe].alive and me.Character and foe.Character end, 10)
R.run(1)
-- 模拟器里角色的头不跟着身子走（没有关节解算）：摆到身子上面（服务器从头那里看）；敌人放在我正前方 40 格、同样的高度（中间是空气）
local h = me.Character.HumanoidRootPart
h.Anchored = true
me.Character:PivotTo(h.CFrame + V3(0, 60, 0))   -- 营地里到处是房子、车：两个人都抬到空中，中间一定是空的
R.run(0.1)
local head0 = me.Character:FindFirstChild("Head")
if head0 then head0.CFrame = h.CFrame * CF(0, 1.5, 0) end
local p0 = h.Position
foe.Character:PivotTo(CF(p0.X, p0.Y + 1, p0.Z - 40))
foe.Character.HumanoidRootPart.Anchored = true
R.run(0.3)
local spotsGot = 0
local fx0 = C.onFx
C.onFx = function(list, ...)
  for _, e in ipairs(list) do if e.k == "spots" and #e.list > 0 then spotsGot = spotsGot + 1 end end
  return fx0(list, ...)
end

print("① 按 Z 标记")
local s0 = G.P[me].score
T.act("spot", foe.Character.HumanoidRootPart.Position)
R.run(1.2)
local key = "p" .. foe.UserId
check(G.spotted and G.spotted.def and G.spotted.def[key] ~= nil, "守方的标记表里有这个敌人")
check(G.P[me].score - s0 == G.Config.Score.spot, "加了标记分（+" .. (G.P[me].score - s0) .. "）")
check(spotsGot > 0, "客户端收到了标记位置")

print("② 冷却")
local s1 = G.P[me].score
T.act("spot", foe.Character.HumanoidRootPart.Position)
R.run(0.2)
check(G.P[me].score == s1, "马上再按：不算")

print("③ 倒地的不能标记")
R.run(G.Config.QuickSpot.cd + 0.2)
G.hurtChar(me.Character, 130, { P = G.P[foe], team = "atk", name = "F1" }, me.Character.HumanoidRootPart)
R.run(0.2)
check(G.P[me].downed ~= nil, "我倒地了")
local s2 = G.P[me].score
T.act("spot", foe.Character.HumanoidRootPart.Position)
R.run(0.3)
check(G.P[me].score == s2, "倒地按 Z：不算")
C.onFx = fx0
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
