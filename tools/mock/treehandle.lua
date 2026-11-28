-- 科技树关上的滑出（TechUI closeTree）：关完把手箭头对不对、滑到一半再点把手能不能重新打开
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.leaveMenu()
R.run(1)
local h
for _, x in ipairs(me:FindFirstChild("PlayerGui"):GetDescendants()) do if x.Name == "TreeHandle" then h = x end end
check(h ~= nil, "找到科技树把手")
local function ht()
  for _, c in ipairs(h:GetDescendants()) do if c:IsA("TextLabel") then return c.Text end end
end
local hangarOn = C.hangarActive and C.hangarActive()
print("  机库开着：" .. tostring(hangarOn) .. "，把手：" .. tostring(ht()))
R.as("client", function() C.openTechTree() end)
R.run(0.5)
print("  打开后：科技树 " .. tostring(C.treeGui.Visible) .. "，把手：" .. tostring(ht()))
T.press(h)
R.run(0.6)
check(not C.treeGui.Visible, "点把手关上了科技树")
local t1 = ht() or ""
check(t1:find("︽") ~= nil and t1:find("︾") == nil, "关上以后把手是「打开」的箭头 ︽（现在是：" .. t1 .. "）")
R.as("client", function() C.openTechTree() end)
R.run(0.5)
T.press(h)          -- 开始关（滑出 0.2 秒）
R.run(1 / 30)
T.press(h)          -- 滑到一半又点把手
R.run(0.6)
check(C.treeGui.Visible == true, "滑出中又点把手：科技树又开着（现在 " .. tostring(C.treeGui.Visible) .. "）")
T.summary()
