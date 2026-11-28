-- 一张图一个服务器（模拟器）：python3 tools/mock/run.py tools/mock/places.lua [part=1|2]
--   用户 11-28「能不能这样 训练场 还有各种地图单独做成一个服务器」「试驾你就让我在雪山地图试驾吧搞点靶车」（Places.lua、SnowRange.lua）：
--   ① 起始服务器（all），游戏里另有训练场、雪山两个地点：点试驾 → 传送到训练场（带着那一辆）；选雪山 → 传送到雪山服务器；
--      传送失败 → 留在本服务器、在本服务器的训练场区块里试驾
--   ② 训练场服务器（PlaceRole = range）：开的是雪山图、不建训练场区块；从别处传送过来带着「试驾 豹 2A6」：到了自动坐进去，
--      车在攻方基地北边的射击位上、朝北；靶车五辆以上、每一辆从射击位都看得见；靶机比圈上的山高；
--      在训练场点「开战」→ 传送回起始服务器（带着出击的那一辆）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
local check = T.check
local PART = tonumber(TEST_ARGS:match("part=(%d)") or "") or 0
local KEY = "de_leo2a6"

local function dummies(G)
  local out = { ground = {}, air = {} }
  local f = R.workspace:FindFirstChild("Ents")
  for _, m in ipairs(f and f:GetChildren() or {}) do
    if m:GetAttribute("TestDummy") then
      local e = G.entById[m:GetAttribute("EntId")]
      if e and e.alive then table.insert(e.air and out.air or out.ground, e) end
    end
  end
  return out
end

if PART ~= 2 then
  print("① 起始服务器：试驾 / 选图传送过去")
  T.mapName = "city"
  T.wtMode = true
  T.matchMode = true
  local G = T.boot()
  G.fortsHold = true
  G.navyNoAI = true
  G.aiVehOff = true
  G.Config.Bots.minPerTeam = 0
  T.runUntil(function() return G.placesReady end, 15)
  check(G.placeRole == "all", "Studio / 测试台默认一个服务器全包（" .. tostring(G.placeRole) .. "）")
  G.placeLive = true
  G.placeIds = { range = 9001, snow = 9002 }
  T.runUntil(function() return G.worldReady end, 900)
  local me = T.join("P1", 9921, true)
  local P = G.P[me]
  R.run(2)
  R.teleports = {}
  T.act("testDrive", KEY)
  R.run(2)
  local tp = R.teleports[1]
  check(tp ~= nil and tp.place == 9001 and type(tp.data) == "table" and tp.data.td == KEY and tp.data.from == "all",
    "点试驾：传送到训练场地点（带着 " .. tostring(tp and tp.data and tp.data.td) .. "）")
  local me2 = T.join("P2", 9922, false)
  local P2 = G.P[me2]
  R.run(2)
  T.actAs(me2, "pickMap", "snow")
  R.run(1)
  local tp2 = R.teleports[2]
  check(tp2 ~= nil and tp2.place == 9002 and tp2.data and tp2.data.map == "snow", "选雪山：传送到雪山地点")
  local me3 = T.join("P3", 9923, false)
  local P3 = G.P[me3]
  R.run(2)
  R.tpFail = true
  T.actAs(me3, "testDrive", KEY)
  R.run(2)
  R.tpFail = false
  check(G.rangeReady ~= nil, "传送失败：本服务器的训练场区块开始建")
  T.runUntil(function() return G.rangeReady == true end, 200, 0.5)
  T.actAs(me3, "testDrive", KEY)
  T.runUntil(function() return P3.vehicle ~= nil and P3.vehicle.testDrive end, 30)
  local Zones = R.require(R.services.ReplicatedStorage:FindFirstChild("Zones"))
  local p = P3.vehicle and P3.vehicle.root.Position
  check(p ~= nil and Zones.of(p.X, p.Z) == "range", "传送失败的人在本服务器的训练场区块里试驾")
  check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
  if PART == 1 then T.summary() return end
  T.summary()
  return
end

print("② 训练场服务器：雪山图上试驾")
T.mapName = "-"
T.placeRole = "range"
T.wtMode = true
T.matchMode = true
local G = T.boot()
T.runUntil(function() return G.placesReady end, 15)
check(G.placeRole == "range", "这个服务器是训练场（PlaceRole = range）")
T.runUntil(function() return G.worldReady end, 1200)
check(G.mapId == "snow", "开的是雪山图（" .. tostring(G.mapId) .. "）")
check(G.rangeFolder == nil, "不建训练场区块（雪山图上试驾）")
T.runUntil(function() return G.rangeReady == true end, 60)
check(G.testRange ~= nil and G.rangeReady == true, "雪山图上的靶道算好了")
check(G.aiVehOff == true and G.Config.Bots.minPerTeam == 0, "训练场不放人机")
R.joinData = R.joinData or {}
R.joinData[9931] = { from = "all", td = KEY }
local me = T.join("P1", 9931, true)
local P = G.P[me]
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 60)
local e = P.vehicle
check(e ~= nil and e.testDrive, "传送过来带着「试驾」：到了自动坐进去")
if not e then T.summary() return end
local Map = G.Map
local B = Map.BASES.atk
local pos = e.root.Position
print(string.format("   车在 (%.0f, %.0f, %.0f)；攻方基地 (%.0f, %.0f)", pos.X, pos.Y, pos.Z, B.x, B.z))
check(pos.Z < B.z and pos.Z > B.z - 1400 and math.abs(pos.X - B.x) < 2000, "车在攻方基地北边的射击位上")
check(e.root.CFrame.LookVector.Z < -0.9, "车头朝北（顺着河谷）")
R.run(6)
local D = dummies(G)
print(string.format("   靶车 %d 辆、靶机 %d 架", #D.ground, #D.air))
local dists, far = {}, 0
for _, d in ipairs(D.ground) do
  local m = (d.root.Position - pos).Magnitude / 2.8
  dists[#dists + 1] = string.format("%.0f", m)
  far = math.max(far, m)
end
table.sort(dists, function(a, b) return tonumber(a) < tonumber(b) end)
print("   靶车离射击位（米）：" .. table.concat(dists, " / "))
-- 雪山河谷故意做得起伏（交战区崎岖）：从车上看得见的靶位不多，看不见的往近处、两边挪，实在没有就少摆（模拟器的噪声和 Roblox 不一样，地形细节不同）
--   （量过：瞄准镜垫到 30 格高也只多看得见一两档——这张图本来就是近距离交战的崎岖河谷，靶车多在几百米内）
check(#D.ground >= 4 and far >= 250, string.format("靶车四辆以上（%d 辆）、最远的在 250 米外（%.0f 米）", #D.ground, far))
local TR = G.testRange
local lane1 = TR.lane(1)
local eye = V3(lane1.X, Map.height(lane1.X, lane1.Z) + (TR.EYE or 6), lane1.Z)   -- 炮塔上的瞄准镜那么高
local blind = 0
for _, d in ipairs(D.ground) do
  local q = d.root.Position
  local gy = Map.height(q.X, q.Z)
  if not d.testSwing and not Map.lineClear(eye, V3(q.X, gy + (TR.AIM or 5), q.Z), 16) then blind = blind + 1 end
end
check(blind == 0, "每一辆靶车从射击位都看得见炮塔（看不见的 " .. blind .. " 辆；来回开的不算这一刻在哪）")
local low = 0
for _, d in ipairs(D.air) do
  local q = d.root.Position
  if q.Y - Map.height(q.X, q.Z) < 60 then low = low + 1 end
end
check(#D.air >= 2 and low == 0, "靶机在天上、比下面的山高（贴地的 " .. low .. " 架）")
print("③ 在训练场点「开战」：传送回起始服务器")
G.placeLive = true
G.placeIds = { all = 9000 }
R.teleports = {}
G.ACT.matchJoin(P, KEY)
R.run(1)
local tp = R.teleports[1]
check(tp ~= nil and tp.place == 9000 and tp.data and tp.data.battle == KEY and tp.data.from == "range", "传送回起始服务器（带着出击的 " .. tostring(tp and tp.data and tp.data.battle) .. "）")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
