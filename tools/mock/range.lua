-- 训练场、地图分区（模拟器）：python3 tools/mock/run.py tools/mock/range.lua
--   用户 11-26 晚：「把训练场单独做一张地图吧」「目前游戏里的几个地图是连起来的 不行 我需要每个地图单独一个区块或者说单独一个服务器」——
--   ① 地图函数按区块分派（Map.lua zoneWrap）：训练场里的高度、材质是训练场的（平地 12、挡弹墙鼓起来），战场里的照旧
--   ② 训练场建好（G.rangeReady）：地形写了（平地 FillBlock、挡弹墙逐列写体素）、设施都在（8 条靶道、距离牌、跑道、直升机坪、靶区）
--   ③ 坦克试驾：车在训练场第 1 条靶道的射击线上，七辆靶车在这条靶道 300～2000 米，三架靶机在训练场上空；第二个人用第 2 条靶道
--   ④ 飞机试驾：停在训练场跑道东头；在训练场里飞不算出界，飞出训练场作战区按训练场中心掉头（不往战场飞）
--   ⑤ 大厅（主菜单、机库厂房、机库停机坪）离战场、训练场都几万格
--   ⑥ 镜头在训练场：远处那圈平地换成训练场的草地、在训练场平地的高度；回机库沉在场景最低的零件底下；回战场换回来
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)   -- 跑得久：一行一行写出来（重定向到文件时也看得见进度）
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

T.mapName = "city"
T.wtMode = true
T.rangeTerrain = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local Zones = R.require(RS:FindFirstChild("Zones"))
local RM = R.require(RS:FindFirstChild("MapRange"))
local Map = G.Map

print("① 地图函数按区块分派")
local lp = RM.lane(1)
check(Zones.of(lp.X, lp.Z) == "range" and Zones.of(0, 0) == "battle", "射击线在训练场那一块、地图中心在战场")
check(math.abs(Map.height(lp.X, lp.Z) - RM.PLAIN) < 0.01, string.format("训练场射击线的地面高 %.2f（训练场平地 %d）", Map.height(lp.X, lp.Z), RM.PLAIN))
local bx, bz = RM.toWorld(0, RM.BERM_W)
check(Map.height(bx, bz) > RM.PLAIN + 60, string.format("挡弹墙鼓起来 %.0f 格", Map.height(bx, bz) - RM.PLAIN))
local cityH = Map.height(100, 100)
local profile = Map.profile and Map.profile("city")
check(profile ~= nil and math.abs(cityH - profile.height(100, 100)) < 1e-6, "战场里的高度照旧问钢城")
check(Map.material(lp.X, lp.Z - 300 * 2.8, RM.PLAIN, 0) == Enum.Material.Ground, "靶道是土路（材质 Ground）")

print("② 训练场建好")
T.runUntil(function() return G.rangeReady == true end, 600, 1 / 10)
check(G.rangeReady == true, "G.rangeReady")
local fills = 0
for _, f in ipairs(R.terrainFills or {}) do
  if f.k == "block" and Zones.inRange(f.p._x or f.p.X, f.p._z or f.p.Z) then fills = fills + 1 end
end
check(fills >= 50, string.format("训练场平地 FillBlock 了 %d 块", fills))
check((R.voxelsWritten or 0) > 0, "挡弹墙逐列写了体素（" .. tostring(R.voxelsWritten) .. "）")
local f = G.rangeFolder
local function count(name)
  local c = f and f:FindFirstChild(name)
  local n = 0
  for _, d in ipairs(c and c:GetDescendants() or {}) do if R.base.IsA(d, "BasePart") then n = n + 1 end end
  return n
end
check(count("Lanes") > 60 and count("LaneMarks") > 50, string.format("靶道（%d 块）、分界杆（%d 根）", count("Lanes"), count("LaneMarks")))
check(count("Airfield") > 20 and count("HeliPad") > 5 and count("TargetArea") > 10, string.format("跑道 %d、直升机坪 %d、靶区 %d", count("Airfield"), count("HeliPad"), count("TargetArea")))
local boards = 0
for _, d in ipairs(f and f:GetDescendants() or {}) do
  if d.ClassName == "TextLabel" and tostring(d.Text):match("^%d+ m$") then boards = boards + 1 end
end
check(boards == RM.LANES * #RM.DIST, string.format("距离牌 %d 块（%d 条靶道 × %d 个靶位）", boards, RM.LANES, #RM.DIST))

print("③ 坦克试驾")
local me = T.join("P1", 9811, true)
local other = T.join("P2", 9812, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local function setTeam(pl, side)
  local P = G.P[pl]
  P.team = side
  pl.Team = G.TEAM[side]
  pl.Neutral = false
  pl:SetAttribute("Side", side)
  G.pushOne(P)
end
setTeam(me, "atk")
setTeam(other, "atk")
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 300, 1 / 10)
G.round.endsAt = (G.round.endsAt or 0) + 1e6   -- 模拟器里没有对手：别让这一局时间到了结束（人会被收回机库）
R.run(1)
local P, P2 = G.P[me], G.P[other]
T.act("testDrive", "de_leo2a6")
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 20)
local e = P.vehicle
check(e ~= nil and e.testDrive, "坐进了试驾的车")
if e then
  local p = e.root.CFrame.Position
  check(Zones.of(p.X, p.Z) == "range", string.format("车在训练场（%.0f, %.0f）", p.X, p.Z))
  check(math.abs(p.X - lp.X) < 40 and math.abs(p.Z - lp.Z) < 40, string.format("在第 1 条靶道的射击线上（偏 %.0f, %.0f）", p.X - lp.X, p.Z - lp.Z))
  local look = e.root.CFrame.LookVector
  check(look.Z < -0.95, "车头朝北（朝着靶道）")
end
local dummies, inLane = 0, 0
for _, x in ipairs(G.vehicles or {}) do
  if x.alive and x.testDummy then
    dummies = dummies + 1
    local q = x.root.CFrame.Position
    if math.abs(q.X - lp.X) < RM.LANE_W / 2 + 40 and q.Z < lp.Z - 200 and Zones.of(q.X, q.Z) == "range" then inLane = inLane + 1 end
  end
end
check(dummies == 7 and inLane == 7, string.format("七辆靶车在自己的靶道里（%d / %d）", inLane, dummies))
local drones = 0
for _, x in ipairs(G.ents or {}) do
  if x.alive and x.air and x.testDummy then
    local q = x.root.CFrame.Position
    if Zones.of(q.X, q.Z) == "range" and q.Y > RM.PLAIN + 100 then drones = drones + 1 end
  end
end
check(drones == 3, "三架靶机在训练场上空（" .. drones .. "）")
-- ⑥a 镜头在训练场（跟着试驾的车）：远处那圈平地是训练场的
R.run(0.5)
local function tilesAt()
  local oc = R.workspace:FindFirstChild("Ocean")
  local y, name, n = nil, nil, 0
  for _, p in ipairs(oc and oc:GetChildren() or {}) do
    if p._p.CFrame and p._p.CFrame.Position.Y > -1000 then
      y, name, n = p._p.CFrame.Position.Y, p._p.Name, n + 1
    end
  end
  return y, name, n
end
local y1, n1, c1 = tilesAt()
check(y1 and math.abs(y1 - (RM.PLAIN - 0.5)) < 0.01 and n1 == "FarLand" and c1 > 0, string.format("镜头在训练场：远处平地在 %s 格高（%s，%d 块露着）", tostring(y1), tostring(n1), c1))
-- 第二个人：第 2 条靶道
G.ACT.testDrive(P2, "de_leo2a6")
T.runUntil(function() return P2.alive and P2.vehicle ~= nil end, 20)
local e2 = P2.vehicle
local lp2 = RM.lane(2)
if e2 then
  local p = e2.root.CFrame.Position
  check(math.abs(p.X - lp2.X) < 40 and math.abs(p.Z - lp2.Z) < 40, string.format("第二个人在第 2 条靶道（偏 %.0f, %.0f）", p.X - lp2.X, p.Z - lp2.Z))
else
  check(false, "第二个人也坐进了试驾的车")
end
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
T.runUntil(function() return not P.alive end, 15)
R.run(9)

print("④ 飞机试驾：训练场跑道，出界按训练场中心掉头")
T.act("testDrive", "cn_j6")
T.runUntil(function() return P.alive and P.vehicle ~= nil and P.vehicle.air end, 20)
local ea = P.vehicle
R.run(0.5)
local C = T.C
local st = C.fly
check(ea ~= nil and ea.air and st ~= nil and st.pilot, "坐进了试驾的飞机")
if ea and st then
  local pa = ea.root.CFrame.Position
  local A = RM.airfield()
  check(math.abs(pa.Z - A.z) < A.wid / 2 and math.abs(pa.X - A.x) < A.len / 2, string.format("停在训练场跑道上（离跑道中心 %.0f, %.0f）", pa.X - A.x, pa.Z - A.z))
  check(st.ground == true and st.cf.LookVector.X < -0.95, "在地上、机头朝西（顺着跑道）")
  -- 摆到训练场上空：不算出界；再摆到训练场作战区外：掉头朝训练场中心
  local function place(x, z, look)
    local p = V3(x, RM.PLAIN + 1500, z)
    st.ground = false
    st.cf = R.CFrame.lookAt(p, p + look)
    st.vdir, st.spd, st.vel = look, 600, look * 600
    st.gearWant, st.gear = 0, 0
    G.moveEnt(ea, st.cf)
    ea.vel = st.vel
    ea.syncT, ea.syncSlack = os.clock(), 160
  end
  place(RM.X, RM.Z - 3000, V3(0, 0, -1))
  R.run(0.5)
  check(st.oob == false, "在训练场上空飞：不算出界（原来离战场中心十万格，一直当出界往回拽）")
  place(RM.X + Zones.RANGE.PLAY + 600, RM.Z, V3(1, 0, 0))
  R.run(0.5)
  local yaw = st.aimYaw or 0
  local aim = V3(-math.sin(yaw), 0, -math.cos(yaw))
  check(st.oob == true and aim.X < -0.9, string.format("飞出训练场作战区：掉头朝训练场中心（准心朝 %.2f, %.2f）", aim.X, aim.Z))
  check(ea.alive and Zones.of(ea.root.CFrame.Position.X, ea.root.CFrame.Position.Z) == "range", "服务器认（没当成飞出地图拉回去）")
end
T.remoteAs(me, "Drive", { op = "exit", hangar = true })
if P.alive and P.vehicle and G.ACT.exitVeh then G.ACT.exitVeh(P) end

print("⑤ 大厅离战场、训练场都远")
local function far(cf)
  local p = cf.Position
  local dB = math.sqrt(p.X * p.X + p.Z * p.Z)
  local dR = math.sqrt((p.X - RM.X) ^ 2 + (p.Z - RM.Z) ^ 2)
  return dB, dR
end
for _, k in ipairs({ "HANGAR", "HANGAR_AIR", "MENU" }) do
  local dB, dR = far(Zones[k])
  check(dB > (Map.SEA_R or Map.R) + 40000 and dR > 60000 and Zones.of(Zones[k].Position.X, Zones[k].Position.Z) == "lobby",
    string.format("%s 离战场中心 %.0f、离训练场 %.0f 格", k, dB, dR))
end
local hs
R.as("client", function() hs = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("HangarStage")) end)
check(hs and hs.floorCF and (hs.floorCF().Position - Zones.HANGAR.Position).Magnitude < 1, "机库厂房搭在大厅（Zones.HANGAR）")

print("⑥ 远处那圈平地跟着区块换样式（训练场的在 ③ 里查过）")
-- 远处那圈平地每帧跟着镜头在哪块换（Scenery.lua 的 stepOcean）：回机库以后先让它走几帧，镜头到了大厅再看
local function camZone()
  local c = R.workspace.CurrentCamera.CFrame.Position
  return Zones.of(c.X, c.Z)
end
T.runUntil(function() return camZone() == "lobby" end, 10)
R.run(0.3)
-- 大厅那圈平地沉在场景的地面底下（Scenery.lua；原来顶面正好 900，和厂房地面抢深度）：不抄 Scenery 里的数，
--   照 tools/mock/hangarzfight.lua 的查法——露着的那几块的顶面低于镜头所在那处场景（厂房 / 停机坪）最低的零件底面
local y3, _, n3 = tilesAt()
local top3 = nil
local oc3 = R.workspace:FindFirstChild("Ocean")
for _, p in ipairs(oc3 and oc3:GetChildren() or {}) do
  local y = p.CFrame.Position.Y
  if y > -1000 then top3 = math.max(top3 or -1e18, y + p.Size.Y / 2) end
end
local function meshed(p)
  for _, c in ipairs(p:GetChildren()) do
    local k = c.ClassName
    if k == "SpecialMesh" or k == "BlockMesh" or k == "CylinderMesh" or k == "FileMesh" then return true end
  end
  return false
end
-- 厂房：所有零件（停进来的车是子 Model，不算）；停机坪：水泥坪、外圈那块地（远处那道山本来就插在地里，同 hangarzfight ②）
local hall = R.workspace:FindFirstChild("HangarStage")
local stage = hall or R.workspace:FindFirstChild("HangarApron")
local low, nParts = nil, 0
for _, p in ipairs(stage and stage:GetChildren() or {}) do
  if p.ClassName == "Part" and p.Transparency < 0.999 and not meshed(p) and (hall or p.Name == "Field" or p.Name == "Apron") then
    local _, y, _, _, _, _, r10, r11, r12 = p.CFrame:GetComponents()
    local s = p.Size
    low = math.min(low or 1e18, y - (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2)
    nParts = nParts + 1
  end
end
check(y3 ~= nil and n3 > 0 and top3 ~= nil and low ~= nil and top3 < low - 0.5,
  string.format("回机库（大厅）：远处平地顶面 %s 在%s最低的零件底面（%s，%d 个零件）底下", tostring(top3), stage and stage.Name or "（没找到场景）",
    low and string.format("%.2f", low) or "?", nParts))
-- 回战场：当步兵在自己基地出生（战雷模式默认不让步行：这里放开）
R.run(9)
G.allowInfantry = true
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 20)
T.runUntil(function() return camZone() == "battle" end, 10)   -- 出生以后镜头从大厅切回战场
if camZone() ~= "battle" then
  -- 模拟器里是服务器直接让人出生（没走客户端的出击界面），机库那套镜头没收：镜头直接摆到战场上看远处平地换不换
  R.workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
  R.workspace.CurrentCamera.CFrame = CF(0, 300, 0)
end
R.run(1)
local y2 = tilesAt()
local far0 = Map.FAR
check(y2 and far0 and math.abs(y2 - far0.y) < 0.01, string.format("回战场：远处平地在 %s 格高（钢城 %s）", tostring(y2), tostring(far0 and far0.y)))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
