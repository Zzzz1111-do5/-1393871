-- 起步车（用户 11-26：选系页做了两版都不满意——「所有系都自动送一辆最低级的车吧 选系去掉」）：
--   python3 tools/mock/run.py tools/mock/starters.lua
--   ① 新玩家离开主菜单直接进机库（没有选系页），主按钮在
--   ② 每个系的起步车（TechTree 的 free：地面、飞机、直升机各一辆）一进来就是自己的，地面那辆是这个系最基础的坦克
--      （用户 11-26 早先定的「每个系从只给一辆最基础的坦克开始」：只在坦克那几列挑，步战车、防空车不算）
--   ③ 出击阵容是默认系的起步车；机库左边点别的系的国旗，阵容换成那个系的起步车
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
local me = T.join("P1", 9911, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
R.run(1)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

print("① 直接进机库")
local np
for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "NationPick" then np = d end end
check(np == nil, "没有选系页")
T.runUntil(function() return T.findNamed("HangarGo") ~= nil end, 5)
check(T.findNamed("HangarGo") ~= nil, "机库的主按钮在（一进来就是机库）")

print("② 每个系的起步车都是自己的")
local t = G.treeOf(P)
for _, nat in ipairs(TT.NATIONS) do
  local st = TT.starter(nat, "ground")
  local lo = math.huge
  for _, it in ipairs(TT.list[nat].ground) do if it.col <= 3 then lo = math.min(lo, it.rank) end end   -- 坦克那几列（主战、第二条线、轻型）
  check(st ~= nil and st.rank == lo and st.col <= 3 and TT.owned(t, st.key) and TT.researched(t, st.key),
    string.format("%s：送 %s（等级 %s，这个系坦克最低 %s）", nat, tostring(st and st.name), tostring(st and st.rank), tostring(lo)))
  for _, br in ipairs({ "air", "heli" }) do
    local s2 = TT.starter(nat, br)
    if s2 then check(TT.owned(t, s2.key), string.format("%s 的%s起步：%s 也是送的", nat, br == "air" and "飞机" or "直升机", s2.name)) end
  end
end

print("③ 阵容")
local lu = G.treeLineup(P)
local cnSt = TT.starter(t.nat, "ground")
check(cnSt and has(lu, cnSt.key), "默认系（" .. tostring(t.nat) .. "）的阵容里有它的起步坦克：" .. table.concat(lu, " "))
local usFlag = T.findNamed("Nat_us")
check(usFlag ~= nil, "机库左边有美国的国旗")
if usFlag then
  T.press(usFlag)
  R.run(1)
  local lu2 = G.treeLineup(P)
  local usSt = TT.starter("us", "ground")
  check(G.treeOf(P).nat == "us" and usSt and has(lu2, usSt.key), "点美国：阵容换成美国的起步车（" .. table.concat(lu2, " ") .. "）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
