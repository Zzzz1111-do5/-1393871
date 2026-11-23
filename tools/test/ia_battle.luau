--!nocheck
-- 战场氛围（服务器 Battle.lua + 客户端 Warfx.lua；同 tools/mock/battle.lua）：用户 11-18 按 3A 游戏的标准做到惊艳（参考战雷、战地）
--   ① 弹坑：炮弹在空地上炸出碗形的坑、坑边烧成焦土；同一处不再挖；水里、半空、航炮、旁边有锚住的零件不挖；炸弹的坑大、深度有上限
--   ② 照明弹：开战后服务器自己打；客户端挂上亮光、降落伞、照地面的灯，慢慢落，烧完熄灭、收掉
--   ③ 新一局：挖过的地按原来的高度重写
-- 用法（仓库根目录）：lune run tools/test/ia_battle.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = process.args[2] ~= "v"

H.boot(process.args[1], { ds = "mock" })
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1 = H.addPlayer("P1", 8301)
H.run(2)
H.runUntil(function() return G.round.phase == "battle" end, 90)
check(G.round.phase == "battle", "开战了")
local Map = G.Map
local RS = H.game:GetService("ReplicatedStorage")
local FD = H.require(RS:FindFirstChild("FortDefs"))
local AD = H.require(RS:FindFirstChild("AirDefs"))
local SRC = { team = "atk", name = "test" }

-- 开阔的平地：高 25～80 格（测试台的地形射线是 y = 0 的平面：这么高的地方往下 60 格打不到它，只看零件）、坡缓
local spots = {}
for gx = -2600, 2600, 113 do
	for gz = -2200, 2200, 97 do
		local h = Map.height(gx, gz)
		if h > 25 and h < 80 and Map.slope(gx, gz) < 0.12 then
			table.insert(spots, V3.new(gx, h, gz))
			if #spots >= 4 then break end
		end
	end
	if #spots >= 4 then break end
end
check(#spots >= 3, "找到几块开阔的平地（" .. #spots .. " 块）")
local function ops(from)
	local out = {}
	for i = from + 1, #H.terrainOps do table.insert(out, H.terrainOps[i]) end
	return out
end

print("① 弹坑")
do
	local p = spots[1]
	local n0, c0 = #H.terrainOps, #G.craters
	G.explode(p + V3.new(0, 0.5, 0), FD.W.how155, SRC)
	H.run(0.5)
	local ball, mud = nil, 0
	for _, o in ops(n0) do
		if o.k == "ball" and o.m == "Air" then ball = o end
		if o.k == "replace" and o.m == "Mud" then mud += 1 end
	end
	check(ball ~= nil and #G.craters == c0 + 1, "155 榴弹在空地上炸出一个坑")
	if ball then
		local depth = p.Y - (ball.cf.Position.Y - ball.r)
		check(depth > 1 and depth <= G.Config.Battle.crater.maxDepth + 0.01, string.format("坑深 %.1f 格（上限 %.1f）", depth, G.Config.Battle.crater.maxDepth))
	end
	check(mud >= 3, "坑里、坑边换成焦土（" .. mud .. " 次）")
	local n1 = #G.craters
	G.explode(p + V3.new(2, 0.5, 1), FD.W.how155, SRC)
	H.run(0.3)
	check(#G.craters == n1, "同一处再炸不再挖")
	local q = spots[2]
	G.explode(q + V3.new(0, 60, 0), FD.W.how155, SRC)
	G.explode(q + V3.new(0, 0.5, 0), AD.W.gsh30, SRC)
	H.run(0.3)
	check(#G.craters == n1, "半空炸、航炮不挖坑")
	local wall = Inst.new("Part")
	wall.Anchored, wall.Size = true, V3.new(6, 8, 6)
	wall.CFrame = CF.new(q.X + 6, q.Y + 4, q.Z)
	wall.Parent = H.game:GetService("Workspace")
	G.explode(q + V3.new(0, 0.5, 0), FD.W.how155, SRC)
	H.run(0.3)
	check(#G.craters == n1, "坑边有锚住的零件（房子、工事、车）不挖")
	wall:Destroy()
	G.explode(spots[3] + V3.new(0, 0.5, 0), AD.W.gbu31, SRC)
	H.run(0.5)
	local cb = G.craters[#G.craters]
	check(#G.craters == n1 + 1 and cb.rc >= 12 and cb.h <= G.Config.Battle.crater.maxDepth + 0.01,
		string.format("2000 磅炸弹炸出大坑（坑口半径 %.1f、深 %.1f）", cb and cb.rc or 0, cb and cb.h or 0))
end

print("② 照明弹")
do
	local C = H.Gs.P1
	G.Config.Battle.illum.burn = 6
	local f0 = G.illumFired()
	H.runUntil(function() return G.illumFired() > f0 end, 40)
	check(G.illumFired() > f0, "开战后服务器自己打照明弹")
	H.run(0.3)
	check(C.flares ~= nil and #C.flares >= 1, "客户端收到照明弹")
	local f = C.flares and C.flares[#C.flares]
	if f then
		H.runUntil(function() return f.core ~= nil end, 15)
		check(f.core ~= nil and f.chute ~= nil and f.groundLight ~= nil, "炸开：亮光、降落伞、照地面的灯")
		H.run(1)
		local y1 = f.core and f.core.CFrame.Position.Y or 0
		H.run(1)
		check(f.core and f.core.CFrame.Position.Y < y1 - 1, "挂着伞慢慢落")
		check(f.groundLight and f.groundLight.Brightness > 1, "照地面的灯亮着")
		H.runUntil(function() return f.out end, 12)
		check(f.out and f.groundLight and not f.groundLight.Enabled, "烧完熄灭")
		H.runUntil(function() return table.find(C.flares, f) == nil end, 15)
		check(table.find(C.flares, f) == nil, "烧完以后收掉")
	end
end

print("④ 夜空、探照灯、远处的炮声")
do
	local C = H.Gs.P1
	local cl = C.nightClouds
	check(cl ~= nil and cl.Cover > 0.5, "地形上有一层低云")
	check(C.searchlights and #C.searchlights >= 6, "守方要地的对空探照灯（" .. (C.searchlights and #C.searchlights or 0) .. " 盏）")
	local L = C.searchlights and C.searchlights[1]
	if L then
		H.run(1)
		local d1 = L.head.CFrame.RightVector
		check(d1.Y > 0.5, string.format("光柱往天上照（仰角 %.0f°）", math.deg(math.asin(math.min(1, d1.Y)))))
	end
	local r0 = C.rumbleCount()
	H.run(20)
	check(C.rumbleCount() > r0, "远处时不时传来炮声")
end

print("⑤ 房子：炸掉一半着火、炸光了塌成废墟")
local B
do
	local C = H.Gs.P1
	local WS = H.game:GetService("Workspace")
	check(G.buildings and #G.buildings >= 5, "地图上的房子登记了血量（" .. (G.buildings and #G.buildings or 0) .. " 栋）")
	B = G.buildings and G.buildings[1]
	if B then
		local side = V3.new(B.center.X, B.lo.Y + 2, B.hi.Z + 2)
		local hp0 = B.hp
		G.explode(side, FD.W.how155, SRC)
		H.run(0.3)
		check(B.hp < hp0, string.format("榴弹在墙边炸：房子掉血（%.0f → %.0f）", hp0, B.hp))
		while B.hp >= B.hp0 * 0.55 and not B.down do G.explode(side, FD.W.how155, SRC) end
		H.run(1.5)
		check(B.m:GetAttribute("Burning") == true, "掉到一半以下：着火")
		local c0 = C.collapseCount()
		G.explode(side, AD.W.gbu31, SRC)
		H.run(1.5)
		check(B.down and not B.m:IsDescendantOf(WS), "2000 磅炸弹：房子塌了（模型从场景里拿走）")
		local n = 0
		if B.ruin then for _, x in B.ruin:GetChildren() do if x:IsA("BasePart") then n += 1 end end end
		check(B.ruin ~= nil and B.ruin:IsDescendantOf(WS) and n >= 12, "原地一摊废墟（" .. n .. " 块）")
		check(C.collapseCount() > c0, "客户端：塌的特效")
	end
end

print("⑥ 暴风雨：下雨、打闪、打雷，过去以后雨停")
do
	local C = H.Gs.P1
	local WS = H.game:GetService("Workspace")
	-- 先出生（镜头跟着人到地面上：云下面才下雨）
	local P1 = G.P[p1]
	local function remote(pl, name, ...)
		local args = table.pack(...)
		local prev = H.ctx
		H.ctx = pl
		local co = coroutine.create(function() H.Gs[pl.Name].R[name]:FireServer(table.unpack(args, 1, args.n)) end)
		coroutine.resume(co)
		H.ctx = prev
	end
	remote(p1, "Act", "pickTeam", P1.team)
	H.run(0.5)
	remote(p1, "Act", "deploy", "rifle", (P1.team == "atk") and "fleet" or "camp")
	H.run(3)
	check(P1.alive, "出生了")
	G.Config.Battle.storm.ramp = 2
	local b0 = C.boltCount()
	G.startStorm(0, 24)
	H.run(4)
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
	H.runUntil(function() return C.boltCount() > b0 end, 20)
	check(C.boltCount() > b0, "打闪、打雷")
	H.runUntil(function() return (WS:GetAttribute("StormK") or 0) == 0 end, 30)
	H.run(8)
	check((WS:GetAttribute("StormK") or 0) == 0 and pe and pe.Rate == 0, "暴风雨过去：雨停了")
	G.Config.Battle.storm.ramp = 25
end

print("⑦ 阵亡效果（用户 11-23：死亡不要瞬间切到部署画面，加一个 GTA5 的死亡效果）：黑白、镜头拉开看着倒下的地方、正中「阵亡」和凶手，4 秒多以后复原")
do
	local C = H.Gs.P1
	local WS = H.game:GetService("Workspace")
	local P = G.P[p1]
	local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
	check(P.alive and hrp ~= nil, "活着")
	if hrp then
		local root = Inst.new("Part")
		root.Anchored, root.Size = true, V3.new(2, 5, 2)
		root.CFrame = CF.new(hrp.CFrame.Position + V3.new(60, 0, 0))
		root.Parent = WS
		local bot = { e = { root = root }, team = (P.team == "atk") and "def" or "atk", name = "神枪手", k = 0, s = 0 }
		local cam = WS.CurrentCamera
		local fov0 = cam.FieldOfView
		local n0 = C.deathFxState().n
		G.hurtChar(P.char, 999, { bot = bot, team = bot.team, name = bot.name })
		H.run(0.3)
		check(C.deathFxOn() and C.deathFxState().n > n0, "阵亡：放阵亡效果")
		H.run(1.4)
		local grade = H.game:GetService("Lighting"):FindFirstChild("DeathGrade")
		check(grade ~= nil and grade.Saturation < -0.9, "画面黑白")
		check(C.deathFxState().killerName == "神枪手", "下面写着凶手（" .. tostring(C.deathFxState().killerName) .. "）")
		check(not C.killcamOn(), "原来转镜头看凶手那段让给阵亡效果")
		H.runUntil(function() return not C.deathFxOn() end, 6)
		H.run(0.2)
		check(not C.deathFxOn() and cam.CameraType ~= Enum.CameraType.Scriptable and cam.FieldOfView >= math.min(fov0, 70) - 1,
			string.format("放完：镜头还回去、视野不再收窄（死前 %.0f°，现在 %.0f°）", fov0, cam.FieldOfView))
		root:Destroy()
	end
end

print("③ 新一局：挖过的地写回去、房子复原")
do
	local v0 = H.voxelWrites
	local nc = #G.craters
	G.roundStart()
	H.run(1)
	check(#G.craters == 0 and nc >= 2 and H.voxelWrites > v0, string.format("挖过的 %d 处重写（写了 %d 次）", nc, H.voxelWrites - v0))
	if B then
		check(not B.down and B.m:IsDescendantOf(H.game:GetService("Workspace")) and B.ruin == nil and B.hp == B.hp0, "塌了的房子复原、废墟收掉、满血")
	end
end

print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
