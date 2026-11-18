-- AI 开载具测试（模拟器）：python3 tools/mock/run.py tools/mock/aiveh.lua
--   用户：AI 会自己找载具开
--   ① 开战后两队各派出 AI 车：守方从营地车位出发，攻方在登陆平台旁坐气垫艇；Driver 属性 −1（没有「E 上车」），不占玩家的名额
--   ② 守方往主岛上的据点开（第一阶段的前哨岛过不去：先去下一阶段的据点等着）；攻方冲上前哨岛的沙滩、放下气垫艇，往据点 A 开
--   ③ 旁边摆一辆敌方的车：炮塔转过去、开炮
--   ④ 血掉到三成五以下往回撤，撤到出发的地方收走（不算被毁）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
G.botsClear()   -- 每队人数设成 0 之前刷出来的机器人也收掉（不然坦克拿机枪打小兵、小兵挡在碉堡的射线上）
T.join("P1", 7001, true)
T.runUntil(function() return G.round and G.round.phase == "battle" end, 120)
check(G.round.phase == "battle", "开战了")
local Map = G.Map
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))

print("① 两队各派出 AI 车")
local function pick(team)
  for _, e in ipairs(G.aiVehicles or {}) do if e.team == team and e.alive then return e end end
end
T.runUntil(function() return pick("atk") ~= nil and pick("def") ~= nil end, 40)
local A, D = pick("atk"), pick("def")
check(A ~= nil and D ~= nil, string.format("攻方 %s、守方 %s", A and A.def.id or "无", D and D.def.id or "无"))
if not (A and D) then T.summary() return end
check(D.model:GetAttribute("Driver") == -1 and A.model:GetAttribute("Driver") == -1, "AI 车 Driver 属性 −1（有人开着，没有「E 上车」）")
local avD = G.vehAvail("def")[D.vcat]
check(avD and avD.u == 0, string.format("不占玩家的名额（守方%s在用 %d）", D.vcat, avD and avD.u or -1))
check(A.lcac ~= nil and A.ai.state == "boat", "攻方 AI 车坐在气垫艇上（第一阶段打前哨岛）")

print("② 往据点开")
local function goalOf(e)
  for _, p in ipairs(Map.POINTS) do if p.id == e.ai.goal then return p end end
end
local function dist(e, p) local q = e.root.CFrame.Position return ((q.X - p.x) ^ 2 + (q.Z - p.z) ^ 2) ^ 0.5 end
local gD = goalOf(D)
check(gD ~= nil and gD.land == "main", "守方的目标在主岛上：" .. tostring(gD and gD.id))
local d0 = gD and dist(D, gD) or 0
local landed = T.runUntil(function() return not A.alive or A.lcac == nil end, 90)
check(landed and A.alive and A.lcac == nil and A.ai and A.ai.state ~= "boat", "攻方 AI 车冲上沙滩、放下了气垫艇")
check(A.ai and Map.landOf(A.root.CFrame.Position.X, A.root.CFrame.Position.Z) == "outpost", "在前哨岛上")
R.run(15)
local d1 = gD and dist(D, gD) or 0
check(D.alive and d1 < d0 - 150, string.format("守方 AI 车往据点 %s 开：%.0f → %.0f 格", tostring(gD and gD.id), d0, d1))
local gA = A.ai and goalOf(A)
check(gA ~= nil and gA.id == "A", "攻方的目标是据点 A")

print("③ 旁边摆一辆敌方的车：炮塔转过去、开炮")
-- 守方 AI 车先停下（停车点就设在脚下），在它四周找一块从车长位置看得见的平地（180～320 格），摆一辆攻方的空坦克
D.ai.hold = D.root.CFrame.Position
R.run(0.5)
local tid = G.Config.Vehicles.atk.tank[1]
local tdef = VD.get(tid)
local eye = (G.vehBaseOf(D) * CF(0, D.def.H + 1, 0)).Position
local p = D.root.CFrame.Position
local spot = nil
for k = 0, 47 do
  local a = k / 48 * math.pi * 2
  for _, r in ipairs({ 220, 300, 180, 140 }) do
    local x, z = p.X + math.cos(a) * r, p.Z + math.sin(a) * r
    if not spot and Map.isLand(x, z) and Map.slope(x, z) < 0.4 and Map.lineClear(eye, V3(x, Map.ground(x, z) + tdef.H / 2 + 1.5, z), 10) then spot = V3(x, 0, z) end
  end
end
check(spot ~= nil, "找到一块看得见的地方摆靶车")
local shots, ty0 = 0, D.ty
local launch0 = G.launch
G.launch = function(s)
  if s.src and D.ai and s.src.bot == D.ai.crew then shots = shots + 1 end
  return launch0(s)
end
local tgt = spot and G.newVehicle("atk", tid, G.vehBaseAt(tdef, spot.X, spot.Z, V3(1, 0, 0)))
local hp0 = tgt and tgt.hp
T.runUntil(function() return shots >= 1 end, 20)
G.launch = launch0
check(D.ai and D.ai.tgt ~= nil and D.ai.tgt.ref == tgt, "认出了敌方的车（目标）")
check(math.abs(((D.ty - ty0 + 180) % 360) - 180) > 1 or shots >= 1, string.format("炮塔转过去了（%.0f° → %.0f°）", ty0, D.ty))
check(shots >= 1, "开炮了（" .. shots .. " 发）")

print("④ 血少了往回撤，撤到出发的地方收走")
D.hp = D.maxHp * 0.2
R.run(0.5)
check(D.ai and D.ai.state == "retreat", "血掉到三成五以下：往回撤")
local h = D.ai and D.ai.home
if h then G.moveEnt(D, CF(h.X + 8, Map.ground(h.X + 8, h.Z) + 4, h.Z)) end
R.run(1)
local still = false
for _, e in ipairs(G.aiVehicles or {}) do if e == D then still = true end end
check(not D.alive and not still and not D.wreck, "撤到了：收走了（不是被打爆）")
T.summary()
