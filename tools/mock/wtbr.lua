-- 战斗等级配对（用户 11-25「都要做」）：python3 tools/mock/run.py tools/mock/wtbr.lua
--   ① 这一局的战斗等级 = 准备阶段真人出击阵容里最高的那辆（workspace 属性 WtBr），开战以后定住
--   ② 超出这一局 BR + 1.0 的车出不了（「这一辆战斗等级 …」），机库卡片标灰
--   ③ 电脑开的车从科技树里挑 [BR − 1.0, BR]，车上记着科技树的键（TreeKey）、能占点（counts）；真人不够一队 8 个时电脑车补到每队 5 辆
--   ④ 出击阵容按科技树的键记（WtMatch 的 ln）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local TT = R.require(R.services.ReplicatedStorage:FindFirstChild("TechTree"))
local W = G.Config.Wt

print("① 这一局的战斗等级")
local me = T.join("P1", 9201, true)
local msgs = {}
local msg0 = G.msg
G.msg = function(pl, kind, key, ...) if pl == me then table.insert(msgs, tostring(key)) end return msg0(pl, kind, key, ...) end
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
R.run(1)
local lineup = G.treeLineup(P)
local want = TT.lineupBr(lineup)
local rb = G.treeRoundBr()
check(math.abs(rb - want) < 0.01, string.format("这一局 BR = 阵容里最高的（%.1f，阵容 %.1f）", rb, want))
check(R.workspace:GetAttribute("WtBr") == rb, "写给客户端：workspace 属性 WtBr = " .. tostring(R.workspace:GetAttribute("WtBr")))

print("② 超出这一局 BR + 1.0 的出不了")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local t = G.treeOf(P)
local high
for _, it in ipairs(TT.list[t.nat].ground) do
  if it.br > rb + (W.brUp or 1) + 0.5 then high = it break end
end
check(high ~= nil, "有一辆高出这一局的：" .. tostring(high and high.name) .. " BR " .. tostring(high and high.br))
if high then
  t.res[high.key], t.own[high.key] = true, true
  local L2 = { high.key }
  for _, k in ipairs(G.treeLineup(P)) do if #L2 < 5 then table.insert(L2, k) end end
  G.ACT.treeLineup(P, t.nat, L2)
  G.treePublish(P)
  R.run(0.5)
  check(math.abs(G.treeRoundBr() - rb) < 0.01, "开战以后这一局的 BR 定住了（阵容里加了高的也不变）")
  msgs = {}
  T.act("deployVeh", high.key)
  R.run(2)
  local said = false
  for _, k in ipairs(msgs) do if k == "tree.brHigh" then said = true end end
  check(not P.alive and said, "出不了，告诉玩家（" .. table.concat(msgs, " ") .. "）")
  -- 机库卡片：标灰
  local hg = T.C.hangarGui
  T.runUntil(function() return hg and hg.Visible end, 5)
  R.run(1.5)
  local go
  for _, c in ipairs(hg and hg:GetDescendants() or {}) do
    if c.Name == "Line_" .. high.key then go = c:FindFirstChild("Sp") end   -- 机库 11-25 重排：卡片底下那行状态字
  end
  check(go ~= nil and go.Text:find("超出") ~= nil, "机库卡片写着超出本局战斗等级（" .. tostring(go and go.Text) .. "）")
end

print("③ 电脑开的车按 BR 从科技树挑")
G.aiVehOff = false
T.runUntil(function()
  local n = 0
  for _, e in ipairs(G.aiVehicles or {}) do if e.alive then n = n + 1 end end
  return n >= 8
end, 300, 1 / 5)
local nAtk, nDef, bad, named, counts = 0, 0, {}, 0, 0
for _, e in ipairs(G.aiVehicles or {}) do
  if e.alive then
    if e.team == "atk" then nAtk = nAtk + 1 else nDef = nDef + 1 end
    local it = e.treeKey and TT.get(e.treeKey)
    if it then
      named = named + 1
      if it.br > rb + 0.06 or it.br < rb - (W.brUp or 1) - 2.06 then table.insert(bad, it.key .. " " .. it.br) end
      if e.model:GetAttribute("TreeKey") ~= it.key then table.insert(bad, it.key .. " 模型上没记") end
    end
    if e.counts == 1 then counts = counts + 1 end
  end
end
local nAll = nAtk + nDef
check(nAll >= 4, string.format("电脑车出来了（攻 %d、守 %d）", nAtk, nDef))
check(named == nAll and #bad == 0, string.format("每辆都从科技树里挑、在这一局的 BR 范围里（%d / %d）%s", named, nAll, #bad > 0 and ("：" .. table.concat(bad, " ")) or ""))
check(counts == nAll, "电脑车能占点（counts）")
check(nDef > 2 or nAtk > 2, "真人不够一队 8 个：电脑车补到每队 2 辆以上")

print("④ 出击阵容按科技树的键记")
local low
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.get(k)
  if it and it.branch == "ground" and it.br <= G.treeBrCap() then low = it break end
end
if low then
  msgs = {}
  T.act("deployVeh", low.key)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  local s = G.wtState and G.wtState(P)
  check(s and (s.ln[low.key] or 0) == 1, "WtMatch 记的是科技树的键（" .. low.key .. "：" .. tostring(s and s.ln[low.key]) .. "）")
  check(P.vehicle and P.vehicle.wtVid == low.key, "车上记的也是科技树的键")
  if not P.vehicle then print("  服务器给这个人的提示：" .. table.concat(msgs, " "), "alive", tostring(P.alive)) end
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
