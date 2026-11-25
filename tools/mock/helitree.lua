-- 直升机科技树（用户 11-25「直升机也做一下各个国家的」）：python3 tools/mock/run.py tools/mock/helitree.lua
--   ① 五国都有直升机树：每一架型号是直升机、有名字，挂的武器、机炮都有定义和名字
--   ② 车少的树不锁死：各国打头的运输直升机白送；德国虎式、日本 OH-1 前面隔着空级也能研究；研究完一架就开下一级
--   ③ 出击：直升机停在本队的直升机坪上（不是跑道），落在地上
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
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local AD = R.require(RS:FindFirstChild("AirDefs"))
local Lang = R.require(RS:FindFirstChild("Lang"))

print("① 五国都有直升机树")
local bad, n = {}, 0
for _, nat in ipairs(TT.NATIONS) do
  local L = TT.list[nat].heli
  if not L or #L < 2 then table.insert(bad, nat .. " 没有直升机") end
  for _, it in ipairs(L or {}) do
    n = n + 1
    local d = AD.get(it.play)
    if not d or d.kind ~= "heli" then table.insert(bad, it.key .. " 型号 " .. tostring(it.play)) end
    if not (Lang.zh["veh." .. it.play] and Lang.en["veh." .. it.play]) then table.insert(bad, it.key .. " 名字") end
    for _, s in ipairs(d and d.st or {}) do
      for _, w in ipairs(s.opts or {}) do
        if not AD.W[w] then table.insert(bad, it.play .. " 挂点 " .. s.name .. " 武器 " .. w) end
        if not Lang.zh["aw." .. w] then table.insert(bad, "aw." .. w .. " 没名字") end
      end
    end
    if d and d.gun and not (AD.W[d.gun] and Lang.zh["aw." .. d.gun]) then table.insert(bad, it.play .. " 炮 " .. d.gun) end
    for _, p in ipairs(d and d.presets or {}) do
      for _, w in pairs(p.map or {}) do if not AD.W[w] then table.insert(bad, it.play .. " 预设 " .. p.key .. " " .. w) end end
    end
  end
end
check(#bad == 0 and n >= 15, "每一架：型号是直升机、有名字、挂的武器都有（" .. n .. " 架）" .. (#bad > 0 and ("：" .. table.concat(bad, " ", 1, math.min(12, #bad))) or ""))
check(AD.W.vikhr.guide == "laser" and AD.W.ataka.guide == "cmd" and Lang.zh["guide.cmd"] ~= nil, "导引方式：旋风激光驾束、攻击无线电指令")
check(AD.get("ka52").rotor2 ~= nil and AD.get("ka52").tail == nil, "卡-52 共轴双旋翼、没有尾桨")

print("② 车少的树不锁死")
local save = { res = {}, own = {}, rp = {}, cur = {} }
local freeAll = TT.get("us_ch47").free and TT.get("ru_mi8").free and TT.get("cn_z8").free and TT.get("de_nh90").free and TT.get("jp_ch47j").free
check(freeAll, "每国打头的运输直升机白送：CH-47、米-8、直-8、NH90、CH-47J")
check(TT.canResearch(save, "de_tiger") == true, "德国虎式（六级、前面只有白送的 NH90）能直接研究")
check(TT.rankOpen(save, "jp", "heli", 5) == true and TT.canResearch(save, "jp_ah1s") == true, "日本：四级一架都没有，五级照样开（隔着空级不锁死）；AH-1S 能直接研究")
local okMi28 = TT.canResearch(save, "ru_mi28")
save.res.ru_mi24 = true
check(not okMi28 and TT.canResearch(save, "ru_mi28") == true, "研究完米-24（三级），隔着空级的米-28（六级）才开")
check(TT.rankOpen(save, "us", "ground", 3) == false, "坦克树照旧：二级（M163）没研究不开三级")

print("③ 出击：停在直升机坪上")
local me = T.join("P1", 9801, true)
T.runUntil(function() return G.round and G.round.phase == "prep" end, 60)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
T.leaveMenu()
R.run(1)
T.act("treeNat", "us")
R.run(0.3)
T.act("treeLineup", "us", { "us_ch47" })
R.run(0.3)
check(G.treeLineup(P)[1] == "us_ch47", "阵容里是 CH-47（" .. tostring(G.treeLineup(P)[1]) .. "）")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
do   -- 用户 11-25：第一辆必须是地面车、飞机要攒 SP——这里测直升机本身，当作已经开地面车攒够了
  local s0 = G.wtState(P)
  s0.ground, s0.sp = true, 5000
end
T.act("deployVeh", "us_ch47")
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
local e = P.vehicle
check(e ~= nil and e.def and e.def.id == "ch47" and e.def.kind == "heli", "坐进 CH-47 了（" .. tostring(e and e.def and e.def.id) .. "）")
if e then
  local pos = e.root.CFrame.Position
  local bd = math.huge
  for _, p in ipairs(G.pads or {}) do
    if p.heli and p.team == P.team then
      local dv = p.base.Position - pos
      bd = math.min(bd, math.sqrt(dv.X * dv.X + dv.Z * dv.Z))
    end
  end
  check(bd < 30, string.format("停在本队的直升机坪上（离最近的坪 %.1f 格）", bd))
  check(e.onGround == true, "在地上")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
