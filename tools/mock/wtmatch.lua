-- 战雷式对局（模拟器）：python3 tools/mock/run.py tools/mock/wtmatch.lua
--   用户 11-24 夜「把整个游戏做成战雷」③：重生点数 SP、出击阵容、战后结算
--   ① 开战后第一辆车免费；第二辆 SP 不够被拒
--   ② 得分攒 SP（每分 0.5），够了再出：花掉、出过两次（第一次 + 备用）以后这一型不能再出
--   ③ 出击阵容：五种车以后第六种不给出
--   ④ 自己的车被打掉记「已毁」；打掉敌车记击毁地面
--   ⑤ 客户端：比分条下面 SP 那一块；结算：「任务完成 / 任务失败」、两张表、原来的结算卡收起
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8401, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true   -- 选过阵营（真人进服要先选，比分条、SP 那一块才出来）
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")   -- 11-24 B：只在自己主基地出生（base / baseAir）
R.run(1.5)
T.runUntil(function() return G.round.phase == "battle" end, 90)
R.run(1)
check(P.alive and P.char ~= nil, "出生了（" .. tostring(P.team) .. "）")

-- 本队的地面召唤位
local pad = nil
for _, p in ipairs(G.pads or {}) do
  if p.kind == "veh" and p.summon and p.team == P.team and p.vids and #p.vids >= 6 then pad = p break end
end
check(pad ~= nil, "找到本队的地面召唤位（" .. (pad and #pad.vids or 0) .. " 型）")
if not pad then T.summary() return end
local function stand()
  local y = G.airSurface(pad.term.X, pad.term.Z)
  P.char:PivotTo(CF(pad.term.X + 1.5, y + 3, pad.term.Z + 1.5))
  R.run(0.2)
end
local function spawn(vid)
  stand()
  P.padT = 0
  local e = G.padSpawnAt(P, pad, nil, vid)
  R.run(0.2)
  return e
end
local function clear(e) if e and e.alive then G.removeEnt(e) R.run(0.2) end end
local W = G.wtState(P)
local ids = pad.vids
print("① 第一辆免费，第二辆 SP 不够")
local e1 = spawn(ids[1])
check(e1 ~= nil and W.free == false and W.sp == 0, "第一辆 " .. ids[1] .. " 出来了，没花 SP（SP " .. W.sp .. "）")
clear(e1)
local e2 = spawn(ids[1])
check(e2 == nil, "第二辆（备用）SP 不够：没出（要 " .. G.wtCost(P, ids[1], "veh") .. "）")
clear(e2)

print("② 攒 SP 再出；出过两次以后不能再出")
G.addScore(P, 700)
check(W.sp == 350 and W.earned == 350, "得 700 分攒了 350 SP（" .. W.sp .. "）")
local c2 = G.wtCost(P, ids[1], "veh")
local e3 = spawn(ids[1])
check(e3 ~= nil and W.sp == 350 - c2 and W.ln[ids[1]] == 2, "备用那次出来了，花了 " .. c2 .. "（剩 " .. W.sp .. "）")
clear(e3)
G.addScore(P, 9000)
check(W.sp == 3000, "SP 封顶 3000（" .. W.sp .. "）")
local e4 = spawn(ids[1])
check(e4 == nil, "同一型第三次：备用用完了，不给出")
clear(e4)

print("③ 出击阵容最多 5 种")
local got = 1
for i = 2, 6 do
  G.addScore(P, 4000)
  local e = spawn(ids[i])
  if i <= 5 then
    check(e ~= nil, "第 " .. i .. " 种 " .. ids[i] .. " 出来了（SP " .. W.sp .. "）")
    if e then got = got + 1 end
  else
    check(e == nil and #W.order == 5, "第 6 种 " .. ids[i] .. " 不给出（阵容 " .. #W.order .. " 种）")
  end
  clear(e)
end

print("④ 被毁、击毁")
G.addScore(P, 4000)
local e5 = spawn(ids[2])   -- 第 2 种的备用
check(e5 ~= nil, "第 2 种备用出来了")
if e5 then
  G.damageEnt(e5, 1e9, nil)
  R.run(1)
  check(W.lost[ids[2]] == 1, "自己的车被打掉：阵容里记已毁（" .. tostring(W.lost[ids[2]]) .. "）")
end
local foe = (P.team == "atk") and "def" or "atk"
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local d6 = VD.get("t90m") or VD.get(ids[1])
local hrp = P.char:FindFirstChild("HumanoidRootPart")
local ex = G.newVehicle(foe, d6.id or "t90m", G.vehBaseAt(d6, hrp.Position.X + 80, hrp.Position.Z + 80, V3(0, 0, -1)))
R.run(0.5)
G.damageEnt(ex, 1e9, { P = P, team = P.team })
R.run(1)
check(W.vk == 1, "打掉敌车记击毁地面（" .. W.vk .. "）")

print("⑤ 客户端：SP 那一块、结算页")
R.run(1)
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local chip = find("WtSp")
check(chip ~= nil and T.visible(chip), "比分条下面有 SP 那一块")
local tag = C.wtTagOf and C.wtTagOf(ids[3], nil)
check(tag ~= nil, "召唤卡片的 SP 字：" .. tostring(tag))
G.roundFinish(P.team)
R.run(1.5)
local res = find("WtResults")
local title = res and res:FindFirstChild("Title", true)
check(res ~= nil and T.visible(res), "结算页出来了")
check(title ~= nil and title.Text ~= "" , "大字：" .. tostring(title and title.Text))
local oldRes = nil
for _, d in ipairs(me.PlayerGui:GetDescendants()) do
  if d.Name == "Results" and d:IsA("Frame") then oldRes = d end
end
check(oldRes == nil or not T.visible(oldRes), "原来那张结算卡收起")
T.summary()
