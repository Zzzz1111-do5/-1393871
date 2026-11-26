-- 击毁效果、音效、奖励（用户 11-26「击杀敌坦克准心莫名其妙会变成正方形 很难看 你自己设计一个击杀效果和音效以及奖励」）：
--   python3 tools/mock/run.py tools/mock/killfx.lua [shot=<目录>]
--   ① 命中标记、击毁确认是细条拼的（不再用「✕」字：字体里没有这个字形就画成方框）
--   ② 打掉一辆敌车：准星上击毁确认（斜杠 + 扩散的环 + 收拢的折角）、击毁音效（killConfirm 叠层）
--   ③ 奖励：服务器当场发金币（存档里真的加了）、报这一辆的研究点和 SP；准星右边一列「击毁 · 车名」+SP +金币 +研究点
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 4
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9701, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
R.run(1)
local key = G.treeLineup(P)[1]
T.act("matchJoin", key)
T.runUntil(function() return G.round.phase == "prep" end, 15)
R.run(1)
T.press(T.findNamed("HangarGo"))
T.runUntil(function() return P.vehicle ~= nil end, 10)
T.runUntil(function() return G.round.phase == "battle" end, 60, 1 / 10)
-- 等电脑车上场，挑一辆敌车
local victim = nil
T.runUntil(function()
  for _, e in ipairs(G.aiVehicles or {}) do if e.alive and e.team ~= P.team then victim = e return true end end
  return false
end, 60, 1 / 10)
check(victim ~= nil, "有一辆敌车（" .. tostring(victim and victim.def and victim.def.id) .. "）")
if not victim then T.summary() return end

print("① 打中：标记是细条拼的")
R.as("client", function() C.hitMarker("hit") end)
R.run(0.05)
local st = C.killFxState()
check(st.shown and not st.kill, "命中标记出来了（不是击毁）")
check(#T.texts("✕") == 0, "界面上没有「✕」字")

print("② 打掉它")
local coins0 = (P.data and P.data.coins) or 0
G.wtRaw = true
G.damageEnt(victim, 1e6, { P = P, team = P.team, name = me.Name })
G.wtRaw = nil
R.run(0.4)
st = C.killFxState()
check(st.kill and st.shown, "准星上是击毁确认")
local rs = C.killRewardState()
check(rs.shown, "准星右边出奖励一列")
check(rs.veh ~= "", "写着打掉的是哪一辆（" .. tostring(rs.veh) .. "）")
check(rs.coins:match("^%+%d+$") ~= nil and tonumber(rs.coins:sub(2)) > 0, "金币 " .. tostring(rs.coins))
check(rs.rp:match("^%+%d+$") ~= nil and tonumber(rs.rp:sub(2)) > 0, "研究点 " .. tostring(rs.rp))
check(rs.sp:match("^%+%d+$") ~= nil, "SP " .. tostring(rs.sp))
local gained = ((P.data and P.data.coins) or 0) - coins0
check(gained > 0 and ("+" .. gained) == rs.coins, string.format("金币当场到账：%d（界面写 %s）", gained, rs.coins))
check(#T.texts("✕") == 0, "击毁时也没有「✕」字（原来那个方框）")
local shotDir = TEST_ARGS and TEST_ARGS:match("shot=(%S+)")
if shotDir then
  R.run(0.25)
  local dump = dofile(MOCK_DIR .. "/uidump.lua")
  dump(T, me, shotDir .. "/killfx.json", true)
end
R.run(5)
check(not C.killRewardState().shown and not C.killFxState().shown, "几秒后都淡掉了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
