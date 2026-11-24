--!nocheck
-- 车贴着看得见的地面（用户 11-22：无数个 AI 修了半天修不好坦克半截身子卡在地里）：
--   真正的原因——客户端一进游戏就 require Map，ReplicatedStorage 里几千块导入的网格还在往下传，MapRoads 常常还没到，
--   原来 FindFirstChild 查不到就当没有路：这个客户端算的地面少了路的挖填（最多差 6 格），可地形是服务器按有路写的，
--   自己开的车按客户端的高度摆，路堤上整车矮下去半截
--   ① Map.lua：MapRoads 晚到也等得到——客户端和服务器的地面高度一模一样；地点里根本没有 MapRoads 时打一句警告
--   ② B 的 terrainLift（车底五点打射线，真地形和公式差多少整车补多少）：等到了路就是 0；对照没等到路时要补的比它能补的（最多 4 格）多
--   ③ 开一段：车底贴着地形（不陷、不悬空）
-- 用法（仓库根目录）：lune run tools/test/ia_ground.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, Enum = roblox.Vector3, roblox.Enum
H.quietWarn = true

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

-- 单独加载一份 Map.lua：mode = "present"（服务器：开服时什么都在）/ "late"（客户端：MapRoads 晚到）/ "missing"（地点里没有）
local mapSrc = fs.readFile("src/ReplicatedStorage/Map.lua")
local roadsSrc = fs.readFile("src/ReplicatedStorage/MapRoads.lua")
local function loadMap(mode)
	local fake = { Name = "MapRoads" }
	local waited, warned = 0, 0
	local parent = {
		FindFirstChild = function(_, n) if n == "MapRoads" and mode == "present" then return fake end return nil end,
		WaitForChild = function(_, n) waited += 1 if n == "MapRoads" and mode == "late" then return fake end return nil end,
	}
	local env = setmetatable({
		script = { Parent = parent },
		require = function(m) if m == fake then return luau.load(roadsSrc, { debugName = "MapRoads" })() end error("require " .. tostring(m)) end,
		warn = function() warned += 1 end,
		Enum = roblox.Enum, Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, Vector2 = roblox.Vector2,
	}, { __index = _G })
	return luau.load(mapSrc, { debugName = "Map", environment = env })(), waited, warned
end

print("① MapRoads 晚到：客户端等得到，地面高度和服务器一样")
local MS = loadMap("present")
local ML, waitedL = loadMap("late")
local MN, waitedN, warnedN = loadMap("missing")
check(#MS.ROADS > 0 and #ML.ROADS == #MS.ROADS, string.format("晚到的客户端也有 %d 条路（服务器 %d 条，等了 %d 次）", #ML.ROADS, #MS.ROADS, waitedL))
check(#MN.ROADS == 0 and warnedN == 1, "地点里没有 MapRoads：没有路，打一句警告")
-- 路上的采样点；挑路堤（有路比没路高出 3 格以上：原来这里车陷进去半截）
local pts, emb = {}, {}
for _, r in ipairs(MS.ROADS) do
	for i = 1, #r.x - 1 do
		local x0, z0, x1, z1 = r.x[i], r.z[i], r.x[i + 1], r.z[i + 1]
		local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		if L > 0.01 then
			for s = 0, L, 9 do
				local x, z = x0 + (x1 - x0) * s / L, z0 + (z1 - z0) * s / L
				if MS.ground(x, z) > 0.5 then
					table.insert(pts, { x, z })
					if MS.ground(x, z) - MN.ground(x, z) > 3 then table.insert(emb, { x, z }) end
				end
			end
		end
	end
end
local dmax = 0
for _, p in ipairs(pts) do dmax = math.max(dmax, math.abs(MS.ground(p[1], p[2]) - ML.ground(p[1], p[2]))) end
check(#pts > 500 and dmax < 1e-6, string.format("路上 %d 个点：晚到的客户端和服务器的地面高度最多差 %.6f 格", #pts, dmax))
local worst = 0
for _, p in ipairs(emb) do worst = math.max(worst, MS.ground(p[1], p[2]) - MN.ground(p[1], p[2])) end
check(#emb > 20, string.format("（对照：原来没等到路的客户端，路堤上 %d 个点矮了 3 格以上，最多 %.1f 格）", #emb, worst))

print("② 开车：车按看得见的地面摆（B 的 terrainLift：车底五点打射线，真地形比公式高 / 低多少整车补多少）")
H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.fortsHold, G.navyNoAI = true, true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 5001), H.addPlayer("P2", 5002)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local CD = H.Gs[def.Name]
check(type(CD.terrainLift) == "function", "客户端有量真地形的函数（Drive.lua G.terrainLift）")
CD.deploySel.spawn, CD.deploySel.role = "camp", "engineer"
H.leaveMenu(def)
CD.refreshDeploy()
H.click(def, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
local tp = H.pad(G, G.Config.Vehicles.def.tank[3])
local e = tp and H.usePad(G, def, tp)
check(e ~= nil, "营地生成了一辆坦克")
if e then
	local prev = H.ctx
	H.ctx = def
	coroutine.resume(coroutine.create(function() H.Gs[def.Name].R.Act:FireServer("enterVeh", e.id) end))
	H.ctx = prev
	H.run(1.5)
	check(CD.drive ~= nil, "坐上了")
	local d = CD.drive and CD.drive.d or e.def
	-- 客户端的公式等到了路：路堤上量出来的差（真地形 − 公式）是 0，terrainLift 不用补
	local lmax = 0
	for i = 1, math.min(#emb, 60) do
		local p = emb[i]
		local L = CD.terrainLift(d, V3.new(p[1], 0, p[2]), 0) or 0
		lmax = math.max(lmax, math.abs(L))
	end
	check(lmax < 0.1, string.format("路堤上 %d 个点：真地形和客户端公式最多差 %.3f 格（等到了路，不用补）", math.min(#emb, 60), lmax))
	-- 对照：原来没等到路的客户端，terrainLift 要补 3～5 格，可它最多补 4 格（放低最多 1.5）——只靠它补不全，所以一定要等到路
	local cMap = CD.Map
	local h0, g0 = cMap.height, cMap.ground
	cMap.height, cMap.ground = MN.height, MN.ground
	local need, got = 0, 0
	for i = 1, math.min(#emb, 60) do
		local p = emb[i]
		local L = CD.terrainLift(d, V3.new(p[1], 0, p[2]), 0) or 0
		local want = MS.ground(p[1], p[2]) - MN.ground(p[1], p[2])
		if want > need then need, got = want, L end
	end
	cMap.height, cMap.ground = h0, g0
	check(need > 3, string.format("（对照：没等到路时这一点要补 %.1f 格，terrainLift 补了 %.1f 格）", need, got))

	print("③ 开一段：车底贴着地形（不陷、不悬空）")
	H.key(def, Enum.KeyCode.W, true)
	local worstGap, n = 0, 0
	for _ = 1, 30 do
		H.run(0.2)
		local st = CD.drive
		if st and st.root then
			local base = st.root * roblox.CFrame.new(0, -st.d.H / 2, 0)
			local p = base.Position
			local gap = p.Y - math.max(H.terrainHeight(p.X, p.Z), 0)
			if not st.airS then   -- 腾空的那一下不算
				n += 1
				if math.abs(gap) > math.abs(worstGap) then worstGap = gap end
			end
		end
	end
	H.key(def, Enum.KeyCode.W, false)
	check(n > 10 and math.abs(worstGap) < 0.8, string.format("开了 %d 帧：车底和地形最多差 %.2f 格（负的是陷进去）", n, worstGap))
end

print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
