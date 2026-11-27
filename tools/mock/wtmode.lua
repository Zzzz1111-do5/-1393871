-- 两种模式（用户 11-25「都要做」：街机 / 历史；全真 11-27「把全真模式去掉」删了）：python3 tools/mock/run.py tools/mock/wtmode.lua
--   ① 默认历史；准备阶段投街机 → 这一局街机（workspace 属性 WtMode）；开战以后定住（再投全真也不变）；机库上的模式按钮
--   ② 飞机从自己机场的跑道出发（用户 11-25「召唤飞机就从机场跑道开始 然后自己起飞 包括回跑道降落补给也做出来」）：
--      停在跑道上、起落架放着、没有初速；地图上没有召唤柱；停在跑道上补给：加油、挂弹、修部件（发动机、机翼……）
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
-- 用户 11-25「把那个选择真实度的图改成选地图吧」：机库上不再有模式按钮，换成地图（点了展开地图列表）；模式照旧能投（服务器 ACT）
local abBtn, mapB
for _, c in ipairs(hg and hg:GetDescendants() or {}) do
  if c.Name == "Mode_ab" then abBtn = c end
  if c.Name == "MapVote" then mapB = c end
end
check(abBtn == nil and mapB ~= nil, "机库上是选地图、不是选模式")
if mapB then T.press(mapB) end
R.run(0.3)
local ml
for _, c in ipairs(hg:GetDescendants()) do if c.Name == "MapList" then ml = c end end
check(ml ~= nil and ml.Visible and #ml:GetChildren() >= 1, "点了展开地图列表")
T.act("wtModeVote", "ab")
R.run(1)
check(me:GetAttribute("ModeVote") == "ab" and G.wtModeNow() == "ab" and ws:GetAttribute("WtMode") == "ab", "投了街机：这一局街机")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
G.wtModeNow()
T.act("wtModeVote", "rb")
R.run(1)
check(G.wtModeNow() == "ab", "开战以后定住：再投历史也还是街机")
T.act("wtModeVote", "sb")
R.run(0.5)
check(me:GetAttribute("ModeVote") ~= "sb", "全真模式删了（用户 11-27「把全真模式去掉」）：投全真不认")

print("② 飞机从跑道出发、落地补给")
local padsF = ws:FindFirstChild("Map") and ws.Map:FindFirstChild("Pads")
local posts = 0
for _, x in ipairs(padsF and padsF:GetDescendants() or {}) do if x.Name == "Post" then posts = posts + 1 end end
check(posts == 0, "地图上没有召唤柱（" .. posts .. " 根）")
local airKey
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.get(k)
  if it and it.branch == "air" then airKey = k break end
end
check(airKey ~= nil, "阵容里有飞机：" .. tostring(airKey))
if airKey then
  -- 用户 11-25「第一辆必须是地面车，飞机要攒点数才能出」：这一局还没出过地面车，飞机出不来
  T.act("deployVeh", airKey)
  R.run(1)
  check(not (P.vehicle and P.vehicle.air), "第一辆不能是飞机（" .. tostring(P.vehicle and P.vehicle.def and P.vehicle.def.id) .. "）")
  local s0 = G.wtState(P)
  check(G.wtCost(P, TT.get(airKey).play, "air") > 0, "飞机不免费：要 " .. tostring(G.wtCost(P, TT.get(airKey).play, "air")) .. " SP")
  s0.ground, s0.sp = true, 5000   -- 当作已经开地面车攒够了 SP：下面测飞机从跑道出发
  T.act("deployVeh", airKey)
  T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
  local e = P.vehicle
  check(e ~= nil and e.air, "坐进飞机了（" .. tostring(e and e.def and e.def.id) .. "）：" .. table.concat(msgs, " "))
  if e then
    local pos = e.root.CFrame.Position
    local gy = G.Map.ground(pos.X, pos.Z)
    local HB = G.Map.BASES and G.Map.BASES[P.team]
    local A = HB and HB.airfield or G.Map.AFIELD2
    local onRw = A and math.abs(pos.Z - A.z) < A.wid / 2 + 2 and math.abs(pos.X - A.x) < A.len / 2
    check(e.onGround == true and (e.vel and e.vel.Magnitude or 0) < 1, "停在地上、没有初速")
    check(pos.Y - gy < 20, string.format("在地上（离地 %.1f 格）", pos.Y - gy))
    check(onRw == true, string.format("在自己机场的跑道上（%.0f, %.0f）", pos.X, pos.Z))
    check(e.model:GetAttribute("Gear") == 1, "起落架放着")
    T.runUntil(function() return C.fly ~= nil end, 8)
    local fs = C.fly
    check(fs and fs.ground == true, "客户端：在地上，自己推油门起飞")
    R.run(3)
    check(e.alive and P.vehicle == e, "3 秒后还在跑道上")
    -- 落地补给：打坏几块、油烧掉、弹打光，停着等地勤
    if e.wta then
      e.wta.p.eng, e.wta.p.tail, e.wta.p.wingL = 20, 35, 60
      e.wta.leak = 0.01
    end
    e.hp = math.floor(e.maxHp * 0.5)
    e.fuel = 0.2
    local full = {}
    for i, n in ipairs(e.stores or {}) do full[i] = n e.stores[i] = 0 end
    local gun0 = e.gunAmmo
    e.gunAmmo = 0
    e.rearmed, e.restT = false, 0
    e.model:SetAttribute("Rest", 0)   -- 原来是 −2（出生时就是满的）：等服务器下一次按新的状态写
    R.run(0.5)
    local sawFix = false
    T.runUntil(function()
      if e.model:GetAttribute("Rest") == -1 and (e.model:GetAttribute("RestK") or 1) < 1 then sawFix = true end
      return e.model:GetAttribute("Rest") == -2
    end, 45)
    check(sawFix, "补给中有进度（Rest −1、RestK）")
    check(e.model:GetAttribute("Rest") == -2, "补给、维修完毕（Rest " .. tostring(e.model:GetAttribute("Rest")) .. "）")
    local okS = true
    for i, n in ipairs(full) do if e.stores[i] ~= n then okS = false end end
    check(okS and e.gunAmmo == gun0, "弹药挂回去了（航炮 " .. tostring(e.gunAmmo) .. " / " .. tostring(gun0) .. "）")
    check((e.fuel or 0) >= (e.fuelSel or 1) - 0.01, string.format("油加满了（%.2f）", e.fuel or 0))
    check(e.hp >= e.maxHp, "机身修好了")
    check(not e.wta or (G.wtaFixK(e) >= 1 and e.wta.leak == 0), "发动机、尾翼、机翼都修好了，不漏油")
  end
end

check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
