-- 三种模式（用户 11-25「都要做」：街机 / 历史 / 全真）：python3 tools/mock/run.py tools/mock/wtmode.lua
--   ① 默认历史；准备阶段投街机 → 这一局街机（workspace 属性 WtMode）；开战以后定住（再投全真也不变）；机库上的模式按钮
--   ② 街机：飞机直接在空中出生（离地、收起落架、有初速、在机场上空）
--   ③ 全真：开地面车自动进第一人称（瞄准镜 / 车内），退瞄准镜退不回第三人称
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
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local ws = R.workspace

print("① 投票、定住")
local me = T.join("P1", 9401, true)
local msgs = {}
local msg0 = G.msg
G.msg = function(pl, kind, key, ...) if pl == me then table.insert(msgs, tostring(key)) end return msg0(pl, kind, key, ...) end
T.runUntil(function() return G.round and G.round.phase == "prep" end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
R.run(1)
check(G.wtModeNow() == "rb" and ws:GetAttribute("WtMode") == "rb", "默认历史（" .. tostring(ws:GetAttribute("WtMode")) .. "）")
local C = T.C
local hg = C.hangarGui
local abBtn
for _, c in ipairs(hg and hg:GetDescendants() or {}) do if c.Name == "Mode_ab" then abBtn = c end end
check(abBtn ~= nil, "机库上有模式按钮")
if abBtn then T.press(abBtn) end
R.run(1)
check(me:GetAttribute("ModeVote") == "ab" and G.wtModeNow() == "ab" and ws:GetAttribute("WtMode") == "ab", "投了街机：这一局街机")
R.run(2.5)
check(abBtn and abBtn.Text:find("✓") ~= nil, "按钮上打勾（" .. tostring(abBtn and abBtn.Text) .. "）")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
G.wtModeNow()
T.act("wtModeVote", "sb")
R.run(1)
check(G.wtModeNow() == "ab", "开战以后定住：再投全真也还是街机")

print("② 街机：飞机空中出生")
local airKey
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.get(k)
  if it and it.branch == "air" then airKey = k break end
end
check(airKey ~= nil, "阵容里有飞机：" .. tostring(airKey))
if airKey then
  T.act("deployVeh", airKey)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  local e = P.vehicle
  check(e ~= nil and e.air, "坐进飞机了（" .. tostring(e and e.def and e.def.id) .. "）：" .. table.concat(msgs, " "))
  if e then
    local y = e.root.CFrame.Position.Y
    local gy = G.Map.ground(e.root.CFrame.Position.X, e.root.CFrame.Position.Z)
    check(e.onGround == false and (e.vel and e.vel.Magnitude or 0) > 50, string.format("离地、有初速（%.0f 格 / 秒）", e.vel and e.vel.Magnitude or 0))
    check(y - gy > 500, string.format("在天上（离地 %.0f 格）", y - gy))
    check(e.model:GetAttribute("Gear") == 0, "起落架收着")
    T.runUntil(function() return C.fly ~= nil end, 8)
    local fs = C.fly
    check(fs and (fs.spd or 0) > 50, "客户端接着初速飞（" .. tostring(fs and math.floor(fs.spd or 0)) .. "）")
    R.run(3)
    fs = C.fly
    local y2 = e.root.CFrame.Position.Y - G.Map.ground(e.root.CFrame.Position.X, e.root.CFrame.Position.Z)
    check(fs and (fs.spd or 0) > 50 and y2 > 300 and e.alive, string.format("3 秒后还在飞（速度 %s、离地 %.0f 格）", tostring(fs and math.floor(fs.spd or 0)), y2))
  end
end

print("③ 全真：只能第一人称")
-- 换成全真（测试直接改；真游戏是下一局投票）
ws:SetAttribute("WtMode", "sb")
if P.vehicle then T.remoteAs(me, "Drive", { op = "exit" }) end
T.runUntil(function() return not P.alive end, 15)
local gKey
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.get(k)
  if it and it.branch == "ground" then gKey = k break end
end
if G.wtState then G.wtState(P).sp = 5000 end
T.act("deployVeh", gKey)
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
R.run(1.5)
local d = C.drive
local fp = d and (d.sight or (C.interiorOn and C.interiorOn()))
check(fp == true, "开车自动进第一人称（瞄准镜 " .. tostring(d and d.sight) .. "、车内 " .. tostring(C.interiorOn and C.interiorOn()) .. "）")
if d and d.sight and not (C.interiorOn and C.interiorOn()) then
  T.tap(Enum.KeyCode.LeftShift)   -- 退镜：全真退不回第三人称
  R.run(1)
  check(d.sight or (C.interiorOn and C.interiorOn()), "按 Shift 退镜：还是第一人称")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
