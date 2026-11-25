-- 每辆车的改装（用户 11-25「都要做」，照战雷：车买来是原厂状态，打仗挣研究点一项项研究）：python3 tools/mock/run.py tools/mock/wtmods.lua
--   ① 数据：每辆车都有改装表、价钱、按级开、自动挑下一项
--   ② 原厂车出击：没有零件（修不了）、没有灭火器、没有烟幕弹、只有第一种弹、机动倍率 1
--   ③ 一局结束：开过的车的改装拿研究点、研究完自动装上（提示）
--   ④ 装上以后重新出击：机动倍率变大、能修车了
--   ⑤ 选研究目标：能选开了的；没开的级别被拒
--   ⑥ 改装界面：格子、点一格设成研究目标
--   ⑦ 乘员：一局攒经验、升级给技能点、点「装填」，重新出车装填快了（CrewRel）；点数不够被拒
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
local WM = R.require(R.services.ReplicatedStorage:FindFirstChild("WtMods"))
local WC = R.require(R.services.ReplicatedStorage:FindFirstChild("WtCrew"))

print("① 数据")
local bad = {}
for key, it in pairs(TT.byKey) do
  local list = WM.list(it)
  if #list < 6 then table.insert(bad, key .. " 改装太少") end
  for _, m in ipairs(list) do
    if WM.cost(it, m) <= 0 then table.insert(bad, key .. ":" .. m.key .. " 价钱") end
    if not (m.zh and m.dz and m.fx) then table.insert(bad, key .. ":" .. m.key .. " 缺字段") end
  end
end
check(#bad == 0, "每辆车都有改装表、价钱、说明" .. (#bad > 0 and ("：" .. table.concat(bad, " ", 1, math.min(6, #bad))) or ""))
local it96 = TT.get("cn_96")
check(WM.nextKey(it96, {}) == "tracks", "原厂车先研究第一级的机动（履带）：" .. tostring(WM.nextKey(it96, {})))
check(not WM.tierOpen(it96, { tracks = true }, 2) and WM.tierOpen(it96, { tracks = true, parts = true }, 2), "第一级研究完两项才开第二级")
local fx0 = WM.fx(it96, {})
check(fx0.speed == 1 and not fx0.repair and not fx0.ext and not fx0.smoke and fx0.ammo == 1, "原厂：倍率 1、不能修、没灭火器、没烟幕、一种弹")

print("② 原厂车出击")
local me = T.join("P1", 9301, true)
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
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local function deploy(key)
  T.act("deployVeh", key)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  return P.vehicle
end
local e = deploy("cn_96")
check(e ~= nil and e.wtFx ~= nil, "出击了，车上记着改装效果")
if e then
  local m = e.model
  check(m:GetAttribute("ModSpd") == 1 and m:GetAttribute("ModAmmo") == 1, "原厂：ModSpd 1、ModAmmo 1")
  check((e.smokeLeft or 0) == 0, "原厂：没有烟幕弹（" .. tostring(e.smokeLeft) .. "）")
  -- 打坏一个模块，按维修：没研究零件修不了
  local S = e.wt
  if S and S.mods and S.mods[1] then
    S.mods[1].hp = 0
    msgs = {}
    G.ACT.wtFix(P)
    local said = false
    for _, k in ipairs(msgs) do if k == "wt.needParts" then said = true end end
    check(S.fixT == nil and said, "修不了：「还没研究改装『零件』」（" .. table.concat(msgs, " ") .. "）")
  else
    check(false, "车上有战雷式模块（e.wt）")
  end
end

print("③ 一局结束：改装拿研究点")
local t = G.treeOf(P)
P.score, P.kills = 500, 2
P.treeUsedKeys = P.treeUsedKeys or {}
check(P.treeUsedKeys.cn_96 == true, "记着这一局开过 96 式")
msgs = {}
local rp = G.treeAward(P, true)
local md = t.mods and t.mods.cn_96
local nDone = md and WM.count(it96, md.done) or 0
local said = false
for _, k in ipairs(msgs) do if k == "tree.modDone" then said = true end end
check(rp > 0 and nDone >= 2 and said, string.format("挣了 %d 研究点：96 式研究完 %d 项改装、提示了（%s）", rp, nDone, table.concat(msgs, " ")))

-- 结算页明细（TechUI G.treeResultText；WtBattle 结算页那一行）
R.run(0.5)
local txt = ""
R.as("client", function() txt = T.C.treeResultText and T.C.treeResultText() or "" end)
check(txt:find("研究点 %+") ~= nil and txt:find("改装 %+") ~= nil and txt:find("乘员经验 %+") ~= nil, "结算页明细：" .. txt)

print("⑦ 乘员（先点技能，下面重新出车一起查）")
local cr = G.treeCrewOf(P, "cn_96")
check(cr ~= nil and (cr.xp or 0) > 0 and (P.treeCrewGain or {}).cn_96 ~= nil, "一局结束：96 式那一位的乘员攒了经验（" .. tostring(cr and cr.xp) .. "）")
if cr then
  cr.xp = WC.xpFor(3)   -- 3 级：9 点
  local slot
  for i, k in ipairs(G.treeLineup(P)) do if k == "cn_96" then slot = i end end
  for _ = 1, 3 do G.ACT.crewUp(P, "cn", slot, "load") end   -- 1 + 2 + 3 = 6 点
  check(cr.sk.load == 3 and WC.free(cr) == 3, "点了三级「装填」（剩 " .. WC.free(cr) .. " 点）")
  msgs = {}
  G.ACT.crewUp(P, "cn", slot, "load")   -- 第 4 级要 4 点，只剩 3
  local no = false
  for _, k in ipairs(msgs) do if k == "tree.crewNoPts" then no = true end end
  check(cr.sk.load == 3 and no, "点数不够：被拒")
end

print("④ 装上以后重新出击")
md.done.parts, md.done.tracks, md.done.susp, md.done.fpe, md.done.engine, md.done.smoke = true, true, true, true, true, true
G.treePublish(P)
if G.wtState then G.wtState(P).sp = 5000 end   -- 第二次出车要 SP（第一辆才免费）
if P.vehicle then T.remoteAs(me, "Drive", { op = "exit", hangar = true }) end
T.runUntil(function() return not P.alive end, 15)
R.run(3)
local e2 = deploy("cn_96")
if e2 then
  local m = e2.model
  check((m:GetAttribute("ModSpd") or 1) > 1.05 and (m:GetAttribute("ModAcc") or 1) > 1.1, string.format("发动机、悬挂装上了：车速 ×%.2f、加速 ×%.2f", m:GetAttribute("ModSpd") or 0, m:GetAttribute("ModAcc") or 0))
  check((e2.smokeLeft or 0) > 0, "烟幕弹装上了（" .. tostring(e2.smokeLeft) .. " 发）")
  check(math.abs((m:GetAttribute("CrewRel") or 1) - 0.88) < 0.001 and math.abs((e2.crewRel or 1) - 0.88) < 0.001, "乘员三级装填：装填时间 ×" .. tostring(m:GetAttribute("CrewRel")))
  local S = e2.wt
  if S and S.mods and S.mods[1] then
    S.mods[1].hp = 0
    G.ACT.wtFix(P)
    check(S.fixT ~= nil, "研究了零件：能修了")
  end
else
  check(false, "重新出击了：" .. table.concat(msgs, " "))
end

print("⑤ 选研究目标")
msgs = {}
G.ACT.treeMod(P, "cn_96", "tools")   -- 第四级：第三级还没研究完两项
local locked = false
for _, k in ipairs(msgs) do if k == "tree.modLocked" then locked = true end end
check(locked and md.cur ~= "tools", "没开的级别被拒（" .. table.concat(msgs, " ") .. "）")
local pick
for _, m in ipairs(WM.GROUND) do if WM.canResearch(it96, md.done, m.key) and m.key ~= "filter" then pick = m.key break end end
G.ACT.treeMod(P, "cn_96", pick)
check(pick ~= nil and md.cur == pick, "选了「" .. tostring(pick) .. "」做研究目标")

print("⑥ 改装界面")
local C = T.C
R.run(0.5)
R.as("client", function() C.openMods(it96) end)
R.run(0.5)
local mp = C.modsGui
local cells, cell = 0, nil
for _, c in ipairs(mp and mp:GetDescendants() or {}) do
  if c.Name:match("^Mod_") then cells = cells + 1 end
  if c.Name == "Mod_filter" then cell = c end
end
check(mp and mp.Visible and cells == #WM.GROUND, "改装面板开着：" .. cells .. " 格")
if cell then T.press(cell) end
R.run(0.5)
check(md.cur == "filter", "点一格「空滤」成了研究目标（" .. tostring(md.cur) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
