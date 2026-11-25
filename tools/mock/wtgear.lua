-- 战雷式开车手感（用户 11-25 晚「那你做战雷手感吧」）：python3 tools/mock/run.py tools/mock/wtgear.lua
--   ① 按住 W：一档起步、一档一档往上升，升档时离合断开那一下不加速；开到接近极速
--   ② 松开：慢下来自动降档，停住挂空档；③ 按住 S：挂倒挡往后开
--   ④ 开一炮：车身被后坐力推得一扬（俯仰角速度一下变大），之后晃回来
local T = dofile(MOCK_DIR .. "/common.lua")
local R, Enum = T.R, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)

local me = T.join("P1", 9701, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C

T.act("testDrive", "de_leo2a6")   -- 试驾场：前面是一大块平地
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 15)
R.run(2)
local st = C.drive
check(st ~= nil, "坐在车里")
if not st then T.summary() return end
local d = st.d

print("① 按住 W")
T.key(Enum.KeyCode.W, true)
local seq, cuts, cutGain, maxV = {}, 0, 0, 0
local lastG, inCut, vAtCut = nil, false, 0
local t = 0
while t < 26 do
  R.run(1 / 30)
  t = t + 1 / 30
  local gb = st.gb
  if gb then
    if gb.g ~= lastG then table.insert(seq, gb.g) lastG = gb.g end
    if gb.cut > 0 and not inCut then inCut, vAtCut = true, st.speed cuts = cuts + 1 end
    if inCut and gb.cut <= 0 then inCut = false cutGain = math.max(cutGain, st.speed - vAtCut) end
  end
  maxV = math.max(maxV, st.speed)
end
T.key(Enum.KeyCode.W, false)
local up = #seq >= 3
for i = 2, #seq do if seq[i] ~= seq[i - 1] + 1 then up = false end end
check(seq[1] == 1 and up, "一档起步、一档一档往上升：" .. table.concat(seq, " → "))
check(cuts >= 2, "升档 " .. cuts .. " 次（每次离合断开一下）")
check(cutGain < 0.6, string.format("离合断开那一下不加速（最多只多了 %.2f 格 / 秒）", cutGain))
check(maxV > d.speed * 0.8, string.format("开到 %.1f 格 / 秒（极速 %.1f）", maxV, d.speed))

print("② 松开")
T.runUntil(function() return math.abs(st.speed) < 0.05 end, 25)
R.run(0.5)
check(st.gb and st.gb.g == 0 and math.abs(st.speed) < 0.05, "停住、挂空档（" .. tostring(st.gb and st.gb.g) .. "）")

print("③ 按住 S")
T.key(Enum.KeyCode.S, true)
R.run(2.5)
T.key(Enum.KeyCode.S, false)
check(st.gb and st.gb.g <= -1 and st.speed < -1, string.format("挂倒挡往后开（档 %s，%.1f 格 / 秒）", tostring(st.gb and st.gb.g), st.speed))
T.runUntil(function() return math.abs(st.speed) < 0.05 end, 15)
R.run(1)

print("④ 开一炮")
local S = st.sus
local vp0 = S and S.vp or 0
local p0 = S and S.p or 0
-- 按住左键开一炮（同 veh.lua）；开炮那一刻记一下车身俯仰，看后坐力把车头推起来多少
local peak = 0
T.mouse(true)
for _ = 1, 12 do
  R.run(1 / 60)
  if S then peak = math.max(peak, S.p - p0) end
end
T.mouse(false)
for _ = 1, 12 do
  R.run(1 / 60)
  if S then peak = math.max(peak, S.p - p0) end
end
check(S ~= nil and peak > 0.005, string.format("开炮：车头一扬 %.2f°（俯仰角速度 %.2f → 冲量）", math.deg(peak), vp0))
R.run(1.5)
check(S ~= nil and math.abs(S.p - p0) < 0.01, string.format("一会儿晃回来（差 %.2f°）", math.deg((S and S.p or 0) - p0)))
T.summary()
