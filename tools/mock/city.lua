-- 钢城（用户 11-26：「做一个两边带机场的城市地图吧」「要有可以撞倒的树，也可以被打倒」）：python3 tools/mock/run.py tools/mock/city.lua
--   ① 开服默认钢城，盖好了城（楼、路），两边基地带跑道；② 开车撞树：本地先倒、服务器认了、广播；③ 炸、炮弹、机枪把树打倒；
--   ④ 新一局树都立回来；⑤ 寻路：流场走街，不穿楼；电脑车的视线被楼挡住
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

T.wtMode = true
T.mapName = "city"
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local Map = G.Map
check(G.mapId == "city" and Map.CITY == true, "开的是钢城（" .. tostring(G.mapId) .. "）")
check((G.cityParts or 0) > 2000, "城盖好了（" .. tostring(G.cityParts) .. " 个零件）")
local bf = R.workspace:FindFirstChild("Map") and R.workspace.Map:FindFirstChild("Scenery")
local city = bf and bf:FindFirstChild("City")
local nb = 0
if city and city:FindFirstChild("Buildings") then
  for _, m in ipairs(city.Buildings:GetChildren()) do if m:GetAttribute("CityIdx") then nb = nb + 1 end end
end
check(nb > 300, "楼都带着编号（" .. nb .. " 座）")
check(G.fobParts and G.fobParts.atk ~= nil and G.fobParts.def ~= nil, "两边主基地（带跑道）都建了")

local me = T.join("P1", 9901, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C
check(C.Map and C.Map.id == "city", "客户端也换成钢城（" .. tostring(C.Map and C.Map.id) .. "）")

print("② 开车撞树")
T.act("testDrive", "de_leo2a6")
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 15)
R.run(2)
local st = C.drive
check(st ~= nil, "坐在车里")
if not st then T.summary() return end
-- 挑公园里一棵树，车摆到它南边 30 格、车头朝北冲过去
local tree = nil
for _, t in ipairs(Map.TREES) do
  if t.x < -2300 and t.x > -2800 and t.z > 150 and t.z < 400 and not Map.bldAt(t.x, t.z + 30, 12) then tree = t break end
end
check(tree ~= nil, "找到公园里的一棵树")
local e = P.vehicle
local function place(x, z, yaw)
  local y = Map.ground(x, z)
  st.pos = V3(x, y, z)
  st.yaw, st.travel = yaw, yaw
  local cf = CF(x, y + e.def.H / 2, z) * R.CFrame.Angles(0, yaw, 0)
  G.moveEnt(e, cf)
end
place(tree.x, tree.z + 30, 0)   -- yaw 0：车头朝 −Z（北）
-- 试驾场在东边丘陵上（高几十格）：挪过来以后车先从原来的高度落下来，落稳了再开
for _ = 1, 75 do st.speed = 0 R.run(1 / 30) end
place(tree.x, tree.z + 30, 0)
st.speed = 10
local hitC, hitS = false, false
for _ = 1, 150 do
  st.speed = math.max(st.speed, 8)
  R.run(1 / 30)
  if C.treeIsDown and C.treeIsDown(tree.id) then hitC = true end
  if G.treeIsDown(tree.id) then hitS = true end
  if hitC and hitS then break end
end
check(hitC, "撞上：客户端这边马上倒了")
check(hitS, "服务器认了（车就在旁边）")
local downC = C.treeDownList and C.treeDownList()[tree.id]
check(downC and math.abs(math.cos(downC.yaw) + 1) < 0.5, "往车开的方向（北）倒（方位 " .. string.format("%.0f", downC and math.deg(downC.yaw) or -1) .. "°）")

print("③ 炸、炮弹、机枪")
local function freeTree(skip)
  for _, t in ipairs(Map.TREES) do
    if not G.treeIsDown(t.id) and not skip[t.id] and t.x < -2300 and t.z < -150 then return t end
  end
end
local skip = {}
local t1 = freeTree(skip)
skip[t1.id] = true
G.explode(V3(t1.x + 6, Map.ground(t1.x, t1.z) + 1, t1.z), { id = "test", dmg = 200, splash = 14 }, nil)
check(G.treeIsDown(t1.id), "爆炸半径里的树倒了")
local t2 = freeTree(skip)
skip[t2.id] = true
local y2 = Map.ground(t2.x, t2.z) + 6
G.treeSeg({}, V3(t2.x - 40, y2, t2.z), V3(t2.x + 40, y2, t2.z))
check(G.treeIsDown(t2.id), "炮弹从树干穿过：打断")
local t3 = freeTree(skip)
skip[t3.id] = true
local shots = 0
while not G.treeIsDown(t3.id) and shots < 60 do
  shots = shots + 1
  G.treeRay(V3(t3.x - 300, Map.ground(t3.x, t3.z) + 5, t3.z), V3(t3.x + 10, Map.ground(t3.x, t3.z) + 5, t3.z), { dmg = 34 })
end
check(G.treeIsDown(t3.id) and shots > 3 and shots < 30, "重机枪打了 " .. shots .. " 发打断（不是一枪就倒）")
R.run(1.5)
local attr = R.workspace:GetAttribute("TreesDown")
check(type(attr) == "string" and attr:find(tostring(t3.id) .. ":") ~= nil, "后进来的人看的属性里有它（" .. tostring(attr and #attr) .. " 字）")
check(C.treeIsDown(t1.id) and C.treeIsDown(t2.id) and C.treeIsDown(t3.id), "客户端那边也都倒了")

print("④ 新一局：立回来")
G.roundFinish("def")
T.runUntil(function() return G.round.phase == "prep" end, 40, 1 / 10)
R.run(1)
check(not G.treeIsDown(tree.id) and not G.treeIsDown(t1.id), "服务器：都立回来了")
check(not C.treeIsDown(tree.id) and not C.treeIsDown(t3.id), "客户端：都立回来了")

print("⑤ 寻路、视线")
T.runUntil(function() return G.navReady end, 400, 1 / 5)
check(G.navReady == true, "流场算好了")
local pos = V3(-1536, 12, 1792)   -- 城里一条街上
local steps, bad, at = 0, 0, pos
for _ = 1, 60 do
  local wp = G.navNext(at, "C")
  if not wp then break end
  if Map.segBlocked(at.X, at.Z, wp.X, wp.Z, 4) then bad = bad + 1 end
  at = V3(wp.X, 12, wp.Z)
  steps = steps + 1
  if (at - V3(0, 12, 0)).Magnitude < 150 then break end
end
check(steps > 3 and (at - V3(0, 12, 0)).Magnitude < 200, string.format("顺着流场走到广场（%d 步，最后离 C %.0f 格）", steps, (at - V3(0, 12, 0)).Magnitude))
check(bad == 0, "每一步都不穿楼（" .. bad .. " 步穿了）")
local b = Map.BLD[1]
for _, x in ipairs(Map.BLD) do if x.k == "block" and x.h > 40 then b = x break end end
local a1, a2 = V3(b.x - b.w, 20, b.z), V3(b.x + b.w, 20, b.z)
check(not Map.lineClear(a1, a2), "隔着楼看不见")
check(Map.lineClear(V3(0, 20, -1536), V3(0, 20, 1536)), "顺着中央大道看得见")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
