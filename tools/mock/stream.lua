-- 流式加载（模拟器；用户 11-24 晚「streaming 优化」「各种 3A 游戏的那种优化」）：python3 tools/mock/run.py tools/mock/stream.lua
--   地点文件里开着 Workspace.StreamingEnabled（tools/build_rbxlx.py）：客户端只收身边一片的地图零件和地形。模拟器整个世界本来都在，
--   这里用 R.streamSim（rbx.lua）假装：客户端打到的地形、地图零件离本机玩家超过半径的算没加载
--   ① 开服：服务器、客户端都知道开着 streaming；实体代理、据点、舰队设成 Persistent（一直在）
--   ② 出生：角色 Persistent；出生前服务器先请把出生点那一片送过来（RequestStreamAroundAsync）
--   ③ 远处的射线（G.rayFar）：流式半径外的地面普通射线打空，按地形高度算出来，和真地形差不到一格；朝天打还是打空；海上落在海面
--   ④ 坦克激光测距打两千格外的山坡：手机内存紧、600 格外都卸掉了，测出来的距离和整张图都在时一样（5 米一档），不打空
--   ⑤ 遥控无人机：无人机也算加载中心（AddReplicationFocus），收起平板去掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

R.workspace.StreamingEnabled = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
local side = "def"
P.team = side
me.Team = G.TEAM[side]
me.Neutral = false
me:SetAttribute("Side", side)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
local Map = G.Map
local PERS = Enum.ModelStreamingMode.Persistent

print("① 开服：开着 streaming，一直要在的设成 Persistent")
check(G.streaming == true and C.streaming == true, "服务器、客户端都知道开着 streaming")
local nEnt, pEnt = 0, 0
for _, m in ipairs(R.workspace.Ents:GetChildren()) do
  nEnt = nEnt + 1
  if m.ModelStreamingMode == PERS then pEnt = pEnt + 1 end
end
check(nEnt > 0 and pEnt == nEnt, string.format("实体代理都是 Persistent（%d / %d）", pEnt, nEnt))
local map = R.workspace:FindFirstChild("Map")
local function allPers(folder)
  local n, p = 0, 0
  for _, m in ipairs(folder and folder:GetChildren() or {}) do
    if m:IsA("Model") then
      n = n + 1
      if m.ModelStreamingMode == PERS then p = p + 1 end
    end
  end
  return n, p
end
local nP, pP = allPers(map and map:FindFirstChild("Points"))
check(nP > 0 and pP == nP, string.format("据点（远处看得见旗杆上的字母）Persistent（%d / %d）", pP, nP))
local nF, pF = allPers(map and map:FindFirstChild("Fleet"))
if Map.LANDONLY then   -- 沙海（11-24 起只剩这张图）没有舰队
  check(nF == 0, "沙海没有舰队（不用查 Persistent）")
else
  check(nF > 0 and pF == nF, string.format("舰队 Persistent（%d / %d）", pF, nF))
end

print("② 出生：角色 Persistent，出生前先预加载出生点那一片")
T.runUntil(function() return G.round.phase == "battle" end, 90)
R.streamLog = {}
-- 出生点：岛图是守方营地 camp；沙海（11-24 起只剩这张图）只能在自己主基地 base 出生
T.actAs(me, "deploy", "rifle", Map.LANDONLY and "base" or "camp")
R.run(2)
check(P.alive and me.Character ~= nil, "出生了")
check(me.Character and me.Character.ModelStreamingMode == PERS, "角色 Persistent（别人那边全图都看得见：队友标记、复活）")
local around
for _, x in ipairs(R.streamLog) do if x.op == "around" and x.pl == me then around = x end end
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
check(around ~= nil and hrp ~= nil and (around.pos - hrp.Position).Magnitude < 12,
  string.format("出生前请服务器把出生点那一片送过来（差 %.1f 格）", around and hrp and (around.pos - hrp.Position).Magnitude or -1))

print("③ 远处的射线：普通射线打空，G.rayFar 按地形高度算")
R.streamSim = 4096
local hp = hrp.Position
-- 找一个 5000～9000 格外的陆地点（流式半径 4096 外）、一个海上的点
local land, sea
for _, rr in ipairs({ 6000, 5000, 7500, 9000 }) do
  for k = 0, 143 do
    local a = k / 144 * math.pi * 2
    local x, z = hp.X + math.cos(a) * rr, hp.Z + math.sin(a) * rr
    local h = (Map.height(x, z))
    if not land and h > 3 then land = V3(x, h, z) end
    if not sea and h < -8 then sea = V3(x, h, z) end
  end
end
check(land ~= nil, string.format("流式半径外找到一块陆地（离人 %.0f 格）", land and (land - hp).Magnitude or -1))
local params = R.RaycastParams.new()
params.FilterDescendantsInstances = { me.Character }
if land then
  local o = land + V3(0, 300, 0)
  local plain, far, up
  R.as("client", function()
    plain = R.workspace:Raycast(o, V3(0, -1000, 0), params)
    far = C.rayFar(o, V3(0, -1000, 0), params)
    up = C.rayFar(o, V3(0, 1000, 0), params)
  end)
  check(plain == nil, "普通射线打空（流式半径外的地形算没加载）")
  local truth = R.workspace:Raycast(o, V3(0, -1000, 0), params)   -- 服务器那边整张图都在
  check(far ~= nil and far.far == true and truth ~= nil and math.abs(far.Position.Y - truth.Position.Y) < 1.5,
    string.format("G.rayFar 按地形高度算出落点（%.1f，真地形 %.1f）", far and far.Position.Y or -1, truth and truth.Position.Y or -1))
  check(far ~= nil and far.Instance == R.workspace.Terrain and R.typeof(far.Normal) == "Vector3" and far.Normal.Y > 0.2, "落点跟 RaycastResult 一样用（Instance = Terrain、法线朝上）")
  check(up == nil, "朝天打还是打空")
end
if sea then
  local o = sea + V3(0, 200, 0)
  o = V3(o.X, 200, o.Z)
  local far
  R.as("client", function() far = C.rayFar(o, V3(0, -1000, 0), params) end)
  check(far ~= nil and math.abs(far.Position.Y) < 0.6, string.format("海上落在海面（%.2f）", far and far.Position.Y or -99))
end

print("④ 坦克激光测距：远处的地形被流出去了，测出来的距离和整张图都在时一样")
--   StreamOutBehavior = LowMemory：内存紧的手机会把 StreamingMinRadius（512 格）以外的卸掉，激光（最远 5000 米 = 14000 格）照样要测得到
R.streamSim = nil
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local def = VD.get("m1a2")
-- 找一块空地（四周 14 格内从上往下打先碰到的都是地形，不是房子、坡道这些零件）和一条落在 900 格外地形上的视线（服务器那边整张图都在）
local truthP = R.RaycastParams.new()
truthP.FilterDescendantsInstances = { me.Character }
local function bare(x, z)
  if not Map.isLand(x, z) or Map.slope(x, z) > 0.2 then return false end
  for _, o in ipairs({ { 0, 0 }, { 14, 0 }, { -14, 0 }, { 0, 14 }, { 0, -14 }, { 10, 10 }, { -10, -10 }, { 10, -10 }, { -10, 10 } }) do
    local h = R.workspace:Raycast(V3(x + o[1], 900, z + o[2]), V3(0, -1400, 0), truthP)
    if not h or h.Instance ~= R.workspace.Terrain then return false end
  end
  return true
end
local spot
for _, rr in ipairs({ 60, 140, 260, 420, 640 }) do
  for k = 0, 23 do
    local a = k / 24 * math.pi * 2
    local x, z = hp.X + math.cos(a) * rr, hp.Z + math.sin(a) * rr
    if bare(x, z) then
      local eye = V3(x, (Map.height(x, z)) + 6, z)
      for _, dp in ipairs({ -0.008, -0.015, -0.004, -0.03 }) do
        for j = 0, 35 do
          local b = j / 36 * math.pi * 2
          local d = V3(math.cos(b), dp, math.sin(b)).Unit
          local res = R.workspace:Raycast(eye + d * 20, d * 12000, truthP)
          local dist = res and (res.Position - eye).Magnitude or 0
          if res and res.Instance == R.workspace.Terrain and dist > 900 then spot = { x = x, z = z, pick = res.Position, dir = V3(d.X, 0, d.Z).Unit } break end
        end
        if spot then break end
      end
    end
    if spot then break end
  end
  if spot then break end
end
check(spot ~= nil, spot and string.format("找到一块空地、一条落在 %.0f 格外地形上的视线", (spot.pick - V3(spot.x, spot.pick.Y, spot.z)).Magnitude) or "没找到空地和远处的视线")
G.econAll = true
local cx, cz = spot and spot.x or hp.X + 18, spot and spot.z or hp.Z
local e = G.newVehicle(side, "m1a2", G.vehBaseAt(def, cx, cz, spot and spot.dir or V3(0, 0, -1)))
R.run(0.5)
local hrp2 = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
if hrp2 then hrp2.CFrame = CF(cx + 9, (Map.height(cx + 9, cz)) + 3, cz) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 M1A2（车头对着那块地）")
if st and spot then
  local pick = spot.pick
  local function laseAt()
    st.fcs.R, st.fcs.noRet, st.fcs.laseT = nil, nil, nil
    R.as("client", function()
      st.sight = false
      st.aimPt = pick + V3(0, 1, 0)   -- 瞄准线对着那块地（地面上一格）
      C.driveLase()
    end)
    return st.fcs.R, st.fcs.noRet
  end
  local r0, n0 = laseAt()   -- 整张图都在
  R.streamSim = 600
  R.streamDrop = 0
  local r1, n1 = laseAt()   -- 600 格外的卸掉了
  R.streamSim = nil
  local trueR = (pick - V3(cx, pick.Y, cz)).Magnitude / 2.8
  check(r0 ~= nil and n0 == false, string.format("整张图都在：测到 %s 米（大约 %.0f 米）", tostring(r0), trueR))
  check((R.streamDrop or 0) > 0, "卸掉以后普通射线确实打空了（模拟器丢了 " .. tostring(R.streamDrop) .. " 次）")
  check(r1 ~= nil and n1 == false and r0 ~= nil and math.abs(r1 - r0) <= 10,
    string.format("卸掉了也测得到：%s 米（整张图都在时 %s 米）", tostring(r1), tostring(r0)))
end
T.remoteAs(me, "Drive", { op = "exit" })
R.run(1)

print("⑤ 遥控无人机：无人机也算加载中心")
R.streamLog = {}
-- 终端前放出无人机：spawnAircraft 直接让人端起平板（Air.lua seat）；放在平地上（离地 6 格，跟召唤位一样）
local ux, uz = cx + 40, cz
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = cx + math.cos(a) * 45, cz + math.sin(a) * 45
  if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then ux, uz = x, z break end
end
local uav = G.spawnAircraft(side, "mq9", CF(ux, (Map.height(ux, uz)) + 6, uz), nil, P, 1)
R.run(1)
local added, removed
for _, x in ipairs(R.streamLog) do
  if x.op == "add" and x.pl == me and uav and x.part == uav.root then added = true end
end
check(uav ~= nil and P.remote == uav and added == true, "端起平板遥控：无人机加成加载中心（AddReplicationFocus）")
T.remoteAs(me, "Drive", { op = "exit" })
R.run(1)
for _, x in ipairs(R.streamLog) do
  if x.op == "remove" and x.pl == me and uav and x.part == uav.root then removed = true end
end
check(removed == true and P.remote == nil, "收起平板：去掉这个加载中心")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
