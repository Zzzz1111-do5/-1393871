-- 主页不显示 SP（模拟器）：python3 tools/mock/run.py tools/mock/hangarsp.lua
--   用户 11-28 夜「主页不要显示sp点数」（TechUI.lua）：SP 只在这一局里用（局内选车页、准备 / 战斗阶段）——
--   ① 主页（匹配中、还没进局）的机库：顶栏不写 SP，阵容卡片上不写要多少 SP / 免费 / 备用
--   ② 进了这一局（匹配到了）：局内的出击页（WtSpawn）照旧写 SP
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check

T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.Match.wait = 3
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9631, true)
T.runUntil(function() return G.round ~= nil and G.P[me] ~= nil end, 30)
local P = G.P[me]
T.leaveMenu()
R.run(2)
local C = T.C
local function findAny(name)
  for _, d in ipairs(R.localPlayer.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local function visibleIn(o)
  while o and o.ClassName ~= "PlayerGui" do
    if o.ClassName == "ScreenGui" then if o.Enabled == false then return false end
    elseif o.Visible == false then return false end
    o = o.Parent
  end
  return true
end

print("① 主页（匹配中）")
check(G.round.phase == "queue", "匹配中（" .. tostring(G.round.phase) .. "）")
check(C.hangarGui and C.hangarGui.Visible, "机库开着")
local chip = findAny("SpChip")
check(chip ~= nil and not visibleIn(chip), "顶栏不写 SP（" .. tostring(chip and chip.Text) .. "）")
local spTexts = {}
for _, t in ipairs(T.texts()) do
  if t:match("^SP %d") or t:find("SP %d+ /") or t == "免费" or t:find("备用", 1, true) then spTexts[#spTexts + 1] = t end
end
check(#spTexts == 0, "阵容卡片上不写 SP、免费、备用（" .. table.concat(spTexts, "、") .. "）")

print("② 进了这一局：局内的出击页照旧写 SP")
local key = G.treeLineup(P)[1]
T.act("matchJoin", key)
T.runUntil(function() return G.round.phase ~= "queue" end, 20)
T.runUntil(function() return P.vehicle ~= nil end, 15)
R.run(1)
check(C.S and C.S.inMatch == true, "这一局算我的、坐进了车")
-- 长按 H 回去：局里回的是出击页（WtSpawn），上面写着这一局的 SP
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return P.vehicle == nil end, 10)
T.runUntil(function() return C.wtSpawnOn and C.wtSpawnOn() end, 10)
R.run(1)
local spIn = false
for _, t in ipairs(T.texts()) do if t:find("SP %d") then spIn = true end end
check(C.wtSpawnOn and C.wtSpawnOn() and spIn, "出击页上写着 SP")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
