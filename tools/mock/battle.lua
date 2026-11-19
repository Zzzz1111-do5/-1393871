-- 战场氛围测试（模拟器）：python3 tools/mock/run.py tools/mock/battle.lua [v]
--   用户 11-18：按 3A 游戏的标准做到惊艳（参考战雷、战地）——服务器 Battle.lua、客户端 Warfx.lua
--   ① 弹坑：炮弹在空地上炸出一个碗形的坑（空气球）、坑边烧成焦土（Mud）；坑深有上限；同一处不再挖；
--      水里、半空、航炮、坑口边上有锚住的零件（房子、工事、车）的不挖；炸弹的坑大一些；新一局把挖过的地按原来的高度写回去
--   ② 照明弹：开战后服务器自己打；客户端从发射点飞上去、炸开后挂着伞烧（亮光、照地面的灯、烟柱），烧完熄灭、收掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6301, true)
T.runUntil(function() return G.round and G.round.phase == "battle" end, 90)
check(G.round.phase == "battle", "开战了")
local Map = G.Map
local FD = R.require(R.services.ReplicatedStorage:FindFirstChild("FortDefs"))
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local WS = R.services.Workspace
local SRC = { team = "atk", name = "test" }

-- 一块开阔的平地（高 6～80 格、坡缓、往下打射线一圈都是地形）
local function clear(x, z, r)
  local s = Map.height(x, z)
  for i = 0, 8 do
    local px, pz = x, z
    if i > 0 then px, pz = x + math.cos(i * 0.785) * r, z + math.sin(i * 0.785) * r end
    local res = WS:Raycast(V3(px, s + 40, pz), V3(0, -60, 0))
    if res and res.Instance and res.Instance.ClassName ~= "Terrain" then return false end
  end
  return true
end
local spots = {}
for gx = -2600, 2600, 113 do
  for gz = -2200, 2200, 97 do
    local h = Map.height(gx, gz)
    if h > 6 and h < 80 and Map.slope(gx, gz) < 0.12 and clear(gx, gz, 26) then
      spots[#spots + 1] = V3(gx, h, gz)
      if #spots >= 4 then break end
    end
  end
  if #spots >= 4 then break end
end
check(#spots >= 3, "找到几块开阔的平地（" .. #spots .. " 块）")

local function fills(from)
  local out = {}
  for i = from + 1, #R.terrainFills do out[#out + 1] = R.terrainFills[i] end
  return out
end

print("① 弹坑")
do
  local p = spots[1]
  local n0, c0 = #R.terrainFills, #G.craters
  G.explode(p + V3(0, 0.5, 0), FD.W.how155, SRC)
  R.run(0.5)
  local f = fills(n0)
  local ball, mud = nil, 0
  for _, o in ipairs(f) do
    if o.k == "ball" and o.mat == "Air" then ball = o end
    if o.k == "replace" and o.mat == "Mud" then mud = mud + 1 end
  end
  check(ball ~= nil and #G.craters == c0 + 1, "155 榴弹在空地上炸出一个坑（挖了 " .. (#G.craters - c0) .. " 个）")
  if ball then
    local floor = ball.p.Y - ball.r
    local depth = p.Y - floor
    local cr = G.craters[#G.craters]
    check(math.abs(ball.p.X - p.X) < 0.01 and math.abs(ball.p.Z - p.Z) < 0.01 and ball.p.Y > p.Y, "空气球的球心在炸点正上方")
    check(depth > 1 and depth <= G.Config.Battle.crater.maxDepth + 0.01, string.format("坑深 %.1f 格（上限 %.1f）", depth, G.Config.Battle.crater.maxDepth))
    check(cr and cr.rc > 6 and cr.rc <= G.Config.Battle.crater.maxR, string.format("坑口半径 %.1f 格（155 榴弹杀伤半径 %d）", cr and cr.rc or 0, FD.W.how155.splash))
    check(cr and math.abs((ball.r * ball.r - (ball.r - depth) ^ 2) ^ 0.5 - cr.rc) < 0.05, "球冠在地面上的口径就是坑口半径")
  end
  check(mud >= 3, "坑里、坑边的草 / 土 / 沙换成焦土（" .. mud .. " 次）")
  local n1 = #G.craters
  G.explode(p + V3(2, 0.5, 1), FD.W.how155, SRC)
  R.run(0.5)
  check(#G.craters == n1, "同一处再炸不再挖（不越挖越深）")
  -- 水里、半空、航炮
  local sea
  for gx = 0, 6000, 200 do if Map.height(gx, 9000) < -5 then sea = V3(gx, 0, 9000) break end end
  if sea then
    G.explode(sea, FD.W.how155, SRC)
    R.run(0.5)
    check(#G.craters == n1, "海里炸不挖坑")
  end
  local q = spots[2]
  G.explode(q + V3(0, 60, 0), FD.W.how155, SRC)
  R.run(0.3)
  check(#G.craters == n1, "半空炸不挖坑")
  G.explode(q + V3(0, 0.5, 0), AD.W.gsh30, SRC)
  R.run(0.3)
  check(#G.craters == n1, "航炮不挖坑")
  -- 坑口边上有锚住的零件（房子、工事、车）：不挖
  local wall = R.Instance.new("Part")
  wall.Anchored, wall.Size = true, V3(6, 8, 6)
  wall.CFrame = CF(q.X + 6, q.Y + 4, q.Z)
  wall.Parent = WS
  G.explode(q + V3(0, 0.5, 0), FD.W.how155, SRC)
  R.run(0.3)
  check(#G.craters == n1, "坑口边上有房子 / 工事不挖")
  wall:Destroy()
  -- 炸弹：坑大一些，深度照样有上限
  local b = spots[3]
  G.explode(b + V3(0, 0.5, 0), AD.W.gbu31, SRC)
  R.run(0.5)
  local cb = G.craters[#G.craters]
  check(#G.craters == n1 + 1 and cb.rc >= 12 and cb.h <= G.Config.Battle.crater.maxDepth + 0.01,
    string.format("2000 磅炸弹炸出大坑（坑口半径 %.1f、深 %.1f）", cb and cb.rc or 0, cb and cb.h or 0))
end

print("② 照明弹")
do
  local C = T.C
  G.Config.Battle.illum.burn = 6
  local f0 = G.illumFired()
  T.runUntil(function() return G.illumFired() > f0 end, 40)
  check(G.illumFired() > f0, "开战后服务器自己打照明弹")
  R.run(0.2)
  check(C.flares and #C.flares >= 1, "客户端收到照明弹")
  local f = C.flares[#C.flares]
  T.runUntil(function() return f.core ~= nil end, 15)
  local camD = f.core and (f.core.Position - WS.CurrentCamera.CFrame.Position).Magnitude or 0
  check(f.core ~= nil and f.chute ~= nil and f.groundLight ~= nil and f.halo ~= nil, "炸开：亮光、降落伞、照地面的灯都挂上了")
  check((f.smoke ~= nil) == (camD < 6000), string.format("烟柱：离镜头 %.0f 格（6000 格内才画）%s", camD, f.smoke and "，画了" or "，没画"))
  R.run(1)
  local okLight = f.groundLight and f.groundLight.Enabled and f.groundLight.Brightness > 1 and f.groundLight.Range >= 59
  check(okLight, "照地面的灯亮着（" .. (f.groundLight and string.format("%.1f", f.groundLight.Brightness) or "无") .. "）")
  local y1 = f.core.Position.Y
  R.run(1)
  check(f.core.Position.Y < y1 - 1, string.format("挂着伞慢慢落（1 秒落了 %.1f 格）", y1 - f.core.Position.Y))
  local anchorAlt = f.anchor.Position.Y - math.max(0, Map.ground(f.anchor.Position.X, f.anchor.Position.Z))
  check(anchorAlt <= 40.5, string.format("照地面的灯在照明弹正下方离地 %.0f 格（点光源最远 60 格）", anchorAlt))
  T.runUntil(function() return f.out end, 12)
  check(f.out and not f.groundLight.Enabled and f.core.Transparency == 1, "烧完熄灭")
  T.runUntil(function() local found = false for _, x in ipairs(C.flares) do if x == f then found = true end end return not found end, 15)
  local still = false
  for _, x in ipairs(C.flares) do if x == f then still = true end end
  check(not still, "烧完以后从列表里收掉")
  check(type(C.illum) == "table" and type(C.illum.k) == "number", "环境光的亮度给 DayNight（G.illum.k）")
end

print("④ 夜空、探照灯、远处的炮声")
do
  local C = T.C
  local cl = C.nightClouds
  check(cl ~= nil and cl.Parent ~= nil and cl.Cover > 0.5 and cl.Density > 0.3, "地形上有一层低云")
  check(C.searchlights and #C.searchlights >= 6, "守方要地的对空探照灯（" .. (C.searchlights and #C.searchlights or 0) .. " 盏）")
  local L = C.searchlights and C.searchlights[1]
  if L then
    local d0 = L.head.CFrame.RightVector
    R.run(4)
    local d1 = L.head.CFrame.RightVector
    check(d1.Y > 0.5, string.format("光柱往天上照（仰角 %.0f°）", math.deg(math.asin(math.min(1, d1.Y)))))
    check((d1 - d0).Magnitude > 0.01, "探照灯在扫（4 秒转了一点）")
    local b = L.beams[1]
    local tip = L.lens.CFrame:PointToWorldSpace(b.Attachment1.Position)
    check(tip.Y > L.lens.Position.Y + 500, string.format("光柱的另一头在天上（高出 %.0f 格）", tip.Y - L.lens.Position.Y))
  end
  local r0 = C.rumbleCount()
  R.run(20)
  check(C.rumbleCount() > r0, "远处时不时传来闷闷的炮声（20 秒 " .. (C.rumbleCount() - r0) .. " 次）")
end

print("⑤ 房子：炸掉一半着火、炸光了塌成废墟")
local B
do
  local C = T.C
  check(G.buildings and #G.buildings >= 5, "地图上的房子登记了血量（" .. (G.buildings and #G.buildings or 0) .. " 栋）")
  B = G.buildings and G.buildings[1]
  if B then
    local side = V3(B.center.X, B.lo.Y + 2, B.hi.Z + 2)   -- 房子南墙外 2 格
    local hp0 = B.hp
    G.explode(side, FD.W.how155, SRC)
    R.run(0.3)
    check(B.hp < hp0, string.format("榴弹在墙边炸：房子掉血（%.0f → %.0f）", hp0, B.hp))
    while B.hp >= B.hp0 * 0.55 and not B.down do G.explode(side, FD.W.how155, SRC) end
    R.run(1.5)
    check(B.m:GetAttribute("Burning") == true, "掉到一半以下：着火（属性 Burning）")
    check(B.m:FindFirstChild("BldFire") ~= nil, "客户端：屋顶冒火、冒烟、火光")
    local c0 = C.collapseCount()
    G.explode(side, AD.W.gbu31, SRC)
    R.run(1.5)
    local inWS = B.m:IsDescendantOf(R.services.Workspace)
    check(B.down and not inWS, "2000 磅炸弹：房子塌了（模型从场景里拿走：不再挡人、挡子弹）")
    local n = 0
    if B.ruin then for _, x in ipairs(B.ruin:GetChildren()) do if x:IsA("BasePart") then n = n + 1 end end end
    check(B.ruin ~= nil and B.ruin:IsDescendantOf(R.services.Workspace) and n >= 12, "原地一摊废墟（" .. n .. " 块：碎石堆、断墙、梁）")
    check(C.collapseCount() > c0, "客户端：塌的特效（尘土、碎块、轰隆一声）")
    check(B.ruin and B.ruin:FindFirstChild("RuinSmoke") ~= nil, "废墟冒烟")
  end
end

print("⑥ 暴风雨：下雨、打闪、打雷，过去以后雨停")
do
  local C = T.C
  local WS = R.services.Workspace
  -- 先出生（镜头跟着人到地面上：云下面才下雨）
  local P = G.P[me]
  P.team = "atk"
  me.Team = G.TEAM.atk
  me.Neutral = false
  me:SetAttribute("Side", "atk")
  G.pushOne(P)
  R.run(1)
  T.act("deploy", "rifle", "af2")
  R.run(3)
  check(P.alive, "出生了")
  G.Config.Battle.storm.ramp = 2
  local cover0 = C.nightClouds and C.nightClouds.Cover or 0
  local b0 = C.boltCount()
  G.startStorm(0, 24)
  R.run(4)
  local k = WS:GetAttribute("StormK") or 0
  check(k > 0.9, string.format("服务器：暴风雨来了（强度 %.2f）", k))
  check(C.weather.k > 0.3, string.format("客户端跟上强度（%.2f）", C.weather.k))
  local rain = C.fxFolder and C.fxFolder:FindFirstChild("Rain")
  local pe = rain and rain:FindFirstChildOfClass("ParticleEmitter")
  local camY = WS.CurrentCamera.CFrame.Position.Y
  if camY < 700 then
    check(pe ~= nil and pe.Rate > 100, "镜头上方下雨（" .. (pe and pe.Rate or 0) .. " 滴 / 秒）")
  else
    check(pe ~= nil and pe.Rate == 0, string.format("镜头在云上面（%.0f 格高）：不下雨", camY))
  end
  -- 镜头压到地面附近一帧：云下面要下雨（测试台的镜头停在主菜单的机位上）
  WS.CurrentCamera.CFrame = CF(spots[1].X, spots[1].Y + 6, spots[1].Z)
  R.run(1 / 60, 1 / 60)
  local lowRate = pe and pe.Rate or 0
  check(lowRate > 100, "镜头在地面附近：头顶下雨（" .. lowRate .. " 滴 / 秒）")
  check(C.nightClouds and C.nightClouds.Cover > cover0 + 0.05, string.format("云变厚（%.2f → %.2f）", cover0, C.nightClouds and C.nightClouds.Cover or 0))
  T.runUntil(function() return C.boltCount() > b0 end, 20)
  check(C.boltCount() > b0, "打闪、打雷（" .. (C.boltCount() - b0) .. " 道）")
  T.runUntil(function() return (WS:GetAttribute("StormK") or 0) == 0 end, 30)
  R.run(8)
  check((WS:GetAttribute("StormK") or 0) == 0 and pe and pe.Rate == 0, "暴风雨过去：雨停了")
  G.Config.Battle.storm.ramp = 25
end

print("⑦ 阵亡镜头：死了以后镜头转向凶手、拉近，3 秒后复原")
do
  local C = T.C
  local WS = R.services.Workspace
  local P = G.P[me]
  if not P.alive then
    T.act("deploy", "rifle", "af2")
    R.run(3)
  end
  local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
  check(P.alive and hrp ~= nil, "出生了")
  if hrp then
    -- 一个假的机器人凶手：站在 60 格外
    local root = R.Instance.new("Part")
    root.Anchored, root.Size = true, V3(2, 5, 2)
    root.CFrame = CF(hrp.Position + V3(60, 0, 0))
    root.Parent = WS
    local bot = { e = { root = root }, team = (P.team == "atk") and "def" or "atk", name = "神枪手", k = 0, s = 0 }
    local n0 = C.killcamCount()
    local fov0 = WS.CurrentCamera.FieldOfView
    G.hurtChar(P.char, 999, { bot = bot, team = bot.team, name = bot.name })
    R.run(0.3)
    check(C.killcamCount() > n0, "阵亡：服务器把凶手的位置发过来，镜头转过去")
    R.run(1.6)
    local cam = WS.CurrentCamera
    local look = cam.CFrame.LookVector
    local want = (root.Position - cam.CFrame.Position).Unit
    check(look:Dot(want) > 0.97, string.format("镜头对着凶手（夹角 %.0f°）", math.deg(math.acos(math.min(1, look:Dot(want))))))
    check(cam.FieldOfView < fov0 - 10, string.format("视野拉近（%.0f° → %.0f°）", fov0, cam.FieldOfView))
    check(R.services.Lighting:FindFirstChild("KillcamGrade") ~= nil, "画面去色")
    local zoomed = cam.FieldOfView
    R.run(2)
    check(not C.killcamOn(), "3 秒后放开镜头")
    check(R.services.Lighting:FindFirstChild("KillcamGrade") == nil and R.services.Lighting:FindFirstChild("KillcamFocus") == nil, "去色、景深收掉")
    check(WS.CurrentCamera.FieldOfView > zoomed + 20, string.format("视野不再拉近（%.0f°）", WS.CurrentCamera.FieldOfView))
    root:Destroy()
  end
end

print("③ 新一局：挖过的地写回去、房子复原")
do
  local v0 = R.voxelsWritten or 0
  local nc = #G.craters
  G.roundStart()
  R.run(1)
  check(#G.craters == 0, "新一局：弹坑记录清空")
  check(nc >= 2 and (R.voxelsWritten or 0) > v0, string.format("新一局：挖过的 %d 处按原来的高度重写（写了 %d 个体素）", nc, (R.voxelsWritten or 0) - v0))
  if B then
    check(not B.down and B.m:IsDescendantOf(R.services.Workspace) and B.ruin == nil and B.m:GetAttribute("Burning") ~= true and B.hp == B.hp0,
      "新一局：塌了的房子复原、废墟收掉、不再着火、满血")
  end
end

T.summary()
