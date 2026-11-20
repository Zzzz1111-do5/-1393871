--!nocheck
-- 载具操控（用户 11-20：「这个游戏目前所有的载具操控都不够 3A，你用虚幻引擎 5 的水平全面升级」）
--   ① 坦克：弹簧臂镜头——起步镜头往后坠、刹车往前冲；排气加速时浓；升档咔哒一声
--   ② 路面：沙滩上跑不到土路那么快（极速按路面打折）
--   ③ 腾空：冲过坡顶飞起来（在天上不能转向），落地按砸下来的速度震屏、一声闷响
--   ④ 撞墙：斜着撞上房子顺着墙滑过去（不是钉死），正面撞上才停；撞上那一下有声音
--   ⑤ 轮式车：高速急转车尾往外甩（车头和真正的去向分开）、轮胎沙沙响
--   用法：lune run tools/test/ia_handling.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Enum = roblox.Enum
local V3, CF = roblox.Vector3, roblox.CFrame
H.quietWarn = true

H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8201), H.addPlayer("P2", 8202)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)
H.run(0.5)
local CD = H.Gs[def.Name]
local Map = G.Map

local fails = 0
local function check(ok, msg)
	print((ok and "  ✓ " or "  ✗ ") .. msg)
	if not ok then fails += 1 end
end
local function as(who, f)
	local prev = H.ctx
	H.ctx = who
	local co = coroutine.create(f)
	coroutine.resume(co)
	H.ctx = prev
end
local function act(who, ...)
	local a = table.pack(...)
	as(who, function() H.Gs[who.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end
-- 记下放了哪些音效
local played = {}
local sfx0 = CD.sfx
CD.sfx = function(def2, ...)
	if type(def2) == "string" then played[def2] = (played[def2] or 0) + 1 end
	return sfx0(def2, ...)
end

act(def, "deploy", "rifle", "camp")
H.run(3)
H.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)

local VD = H.require(H.game:GetService("ReplicatedStorage"):FindFirstChild("VehDefs"))
-- 在 (x, z) 放一辆车、朝 dir，坐进去
local function drive(vid, x, z, dir)
	if CD.drive then
		H.key(def, Enum.KeyCode.Space, true)
		H.run(0.1)
		H.key(def, Enum.KeyCode.Space, false)
		H.run(1)
	end
	local d = VD.get(vid)
	local e = G.newVehicle("def", vid, G.vehBaseAt(d, x, z, dir))
	H.run(0.3)
	def.Character:PivotTo(CF.new(x + d.W / 2 + 3, Map.ground(x + d.W / 2 + 3, z) + 3.5, z))
	H.run(0.3)
	act(def, "enterVeh", e.id)
	H.run(1)
	H.runUntil(function() return CD.drive ~= nil and CD.drive.em == e.model end, 3)
	H.run(0.5)
	return CD.drive, d, e
end
-- 从 (x, z) 往 dir 开 len 格，车身高度上有没有房子、码头挡着
local mapRp = nil
local function pathClear(x, z, dir, len)
	local mp = H.workspace:FindFirstChild("Map")
	if not mp then return true end
	if not mapRp then
		mapRp = H.genv.RaycastParams.new()
		mapRp.FilterType = H.genv.Enum.RaycastFilterType.Include
		mapRp.FilterDescendantsInstances = { mp }
	end
	for _, side in ipairs({ -5, 0, 5 }) do
		local r = V3.new(-dir.Z, 0, dir.X) * side
		local o = V3.new(x, Map.ground(x, z) + 2.5, z) + r - dir * 16
		if H.workspace:Raycast(o, dir * (len + 16), mapRp) then return false end
	end
	return true
end
-- 找一块平地：半径 r 内高差小、都是陆地、按 want 的地面（nil = 不挑）；dir 给了的话，往那边开 r 格的路上不能有房子
local function flatSpot(cx, cz, want, r, tries, dir)
	for i = 1, tries or 400 do
		local a = i * 2.39996
		local rr = 30 + (i % 80) * 40
		local x, z = cx + math.cos(a) * rr, cz + math.sin(a) * rr
		local h = Map.height(x, z)
		if h > 3 then
			local ok = true
			local mat = Map.material(x, z, h, Map.slope(x, z))
			if want and mat ~= want then ok = false end
			if ok then
				for _, o in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r * 0.7, r * 0.7 }, { -r * 0.7, -r * 0.7 } }) do
					local h2 = Map.height(x + o[1], z + o[2])
					if math.abs(h2 - h) > r * 0.06 or h2 < 3 then ok = false break end
					if want and Map.material(x + o[1], z + o[2], h2, Map.slope(x + o[1], z + o[2])) ~= want then ok = false break end
				end
			end
			if ok and dir and not pathClear(x, z, dir, r) then ok = false end
			if ok then return x, z end
		end
	end
	if want then   -- 附近没有：全图按网格找
		for gx = -3200, 3200, 64 do
			for gz = -3200, 3200, 64 do
				local h = Map.height(gx, gz)
				if h > 3 and Map.material(gx, gz, h, Map.slope(gx, gz)) == want then
					local ok = true
					for _, o in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
						local h2 = Map.height(gx + o[1], gz + o[2])
						if math.abs(h2 - h) > r * 0.1 or h2 < 3 or Map.material(gx + o[1], gz + o[2], h2, Map.slope(gx + o[1], gz + o[2])) ~= want then ok = false break end
					end
					if ok then return gx, gz end
				end
			end
		end
	end
end

local camp = def.Character.HumanoidRootPart.CFrame.Position

print("① 坦克：弹簧臂镜头（起步往后坠、刹车往前冲）、排气、换挡声")
local tx, tz = flatSpot(camp.X, camp.Z, nil, 70, 2000, V3.new(0, 0, -1))
check(tx ~= nil, "找到一块平地")
if tx then
	local st, d = drive("m1a2", tx, tz, V3.new(0, 0, -1))
	check(st ~= nil, "坐进 M1A2")
	if st then
		local v = CD.views and CD.views[st.em]
		local ex = v and v.M and v.M.exhaust
		check(ex ~= nil and #ex == 2, "车尾两个排气口")
		local idle = ex and ex[1].Rate or 0
		H.key(def, Enum.KeyCode.W, true)
		local pushB, accRate = 0, 0
		for _ = 1, 12 do
			H.run(0.1)
			local s = CD.vehCamState and CD.vehCamState("drive")
			local fwd = st.root.LookVector
			if s then pushB = math.min(pushB, s.push:Dot(fwd)) end
			if ex then accRate = math.max(accRate, ex[1].Rate) end
		end
		print(string.format("    起步 1.2 秒：车速 %.1f、档位 %s", st.speed, tostring(st.gearN)))
		check(pushB < -0.5, string.format("起步：镜头往后坠（%.2f 格）", -pushB))
		check(accRate > idle + 4, string.format("加油门：排气变浓（怠速 %.1f → %.1f）", idle, accRate))
		for _ = 1, 40 do H.run(0.1) end
		check((played.gearShift or 0) >= 2, string.format("升档咔哒一声（%d 次）", played.gearShift or 0))
		H.key(def, Enum.KeyCode.W, false)
		H.key(def, Enum.KeyCode.S, true)
		local pushF = 0
		for _ = 1, 8 do
			H.run(0.1)
			local s = CD.vehCamState and CD.vehCamState("drive")
			if s then pushF = math.max(pushF, s.push:Dot(st.root.LookVector)) end
		end
		H.key(def, Enum.KeyCode.S, false)
		check(pushF > 0.8, string.format("刹车：镜头往前冲（%.2f 格）", pushF))
		H.run(2)
	end
end

print("② 路面：沙地上跑不到土路那么快（同一块平地上，分别按沙地、土路开 7 秒）")
local function topOn(mat, label)
	if not tx then return nil end
	local st, d = drive("m1a2", tx, tz, V3.new(0, 0, -1))
	if not st or not CD.driveSurf then return nil end
	local top = 0
	H.key(def, Enum.KeyCode.W, true)
	for _ = 1, 70 do
		st.surf, st.surfT = CD.driveSurf[mat], 1e9   -- 按这种路面算
		H.run(0.1)
		top = math.max(top, st.speed)
	end
	H.key(def, Enum.KeyCode.W, false)
	H.run(2)
	print(string.format("    %s：最快 %.1f 格 / 秒（车型极速 %.1f）", label, top, d.speed))
	return top
end
local sand = topOn(Enum.Material.Sand, "沙地")
local road = topOn(Enum.Material.Ground, "土路")
check(sand ~= nil and road ~= nil and sand < road * 0.95, string.format("沙地 %.1f < 土路 %.1f", sand or -1, road or -1))
local sm = Map.material
local foundSand = false
for gx = -3200, 3200, 80 do
	for gz = -3200, 3200, 80 do
		local h = Map.height(gx, gz)
		if h > -1 and sm(gx, gz, h, Map.slope(gx, gz)) == Enum.Material.Sand then foundSand = true break end
	end
	if foundSand then break end
end
check(foundSand, "地图上有沙地（海滩）——开上去按沙地算")

print("③ 腾空：冲过坡顶飞起来、落地有冲击")
if tx then
	local st, d = drive("m1a2", tx, tz, V3.new(0, 0, -1))
	if st then
		H.key(def, Enum.KeyCode.W, true)
		H.run(3)
		-- 刚从一个往上的坡冲出来（地面往上走的速度 18 格 / 秒）：下一帧平地就接不住了
		st.gVy = 18
		st.gY0 = st.root.Position.Y - d.H / 2 - 0.02
		local airN0 = st.airN or 0
		H.run(0.05)
		check((st.airN or 0) > airN0 and st.airS ~= nil, "冲出坡顶：车离地飞起来")
		local yaw0 = st.yaw
		H.key(def, Enum.KeyCode.D, true)
		H.run(0.25)
		H.key(def, Enum.KeyCode.D, false)
		check(math.abs(st.yaw - yaw0) < 0.05, string.format("在天上转不了向（车头转了 %.3f 弧度）", math.abs(st.yaw - yaw0)))
		local land0 = played.vehLand or 0
		H.runUntil(function() return st.airS == nil end, 3)
		H.run(0.1)
		check(st.airS == nil and (played.vehLand or 0) > land0 and (st.landK or 0) > 0, string.format("落地：一声闷响、震屏（冲击 %.2f）", st.landK or 0))
		H.key(def, Enum.KeyCode.W, false)
		H.run(1.5)
	end
end

print("④ 撞墙：斜着撞上房子顺着墙滑过去，正面撞上才停")
local function wallSpot()
	local mp = H.workspace:FindFirstChild("Map")
	if not mp then return nil end
	local best = nil
	for _, p in ipairs(mp:GetDescendants()) do
		if p:IsA("BasePart") and p.Size.Y >= 8 and math.max(p.Size.X, p.Size.Z) >= 34 and math.min(p.Size.X, p.Size.Z) >= 4 then
			local cf, sz = p.CFrame, p.Size
			local pos = cf.Position
			local g = Map.ground(pos.X, pos.Z)
			if math.abs((pos.Y - sz.Y / 2) - g) < 3 and math.abs(cf.UpVector.Y) > 0.99 then
				local alongX = sz.X >= sz.Z
				local n0 = alongX and cf.LookVector or cf.RightVector
				local half = alongX and sz.Z / 2 or sz.X / 2
				local tng = alongX and cf.RightVector or cf.LookVector
				for _, sg in ipairs({ 1, -1 }) do
					local n = V3.new(n0.X * sg, 0, n0.Z * sg).Unit
					local face = V3.new(pos.X, 0, pos.Z) + n * half
					local ok = true
					for _, o in ipairs({ { 12, -26 }, { 30, -26 }, { 12, 0 }, { 30, 0 }, { 6, 20 }, { 20, 20 } }) do
						local q = face + n * o[1] + V3.new(tng.X, 0, tng.Z).Unit * o[2]
						local h = Map.height(q.X, q.Z)
						if h < 3 or math.abs(h - g) > 2.5 then ok = false break end
					end
					local tt = V3.new(tng.X, 0, tng.Z).Unit
					if ok then   -- 照测试的开法（墙外 22 格、往墙斜 30°）：路上第一个碰到的得是这面墙
						local a = math.rad(30)
						local dir = (tt * math.cos(a) - n * math.sin(a)).Unit
						local st0 = face + n * 22 - tt * 26
						if not mapRp then pathClear(0, 0, V3.new(1, 0, 0), 1) end
						local hit = H.workspace:Raycast(V3.new(st0.X, g + 2.5, st0.Z) - dir * 14, dir * 120, mapRp)
						if not (hit and hit.Instance == p) then ok = false end
					end
					if ok then
						best = { face = face, n = n, t = tt, g = g, part = p }
						break
					end
				end
				if best then break end
			end
		end
	end
	return best
end
local W = wallSpot()
check(W ~= nil, "找到一面平地上的长墙")
if W then
	-- 从墙外 26 格、往墙那边斜 30°（大半是顺着墙）开过去
	local a = math.rad(30)
	local dir = (W.t * math.cos(a) - W.n * math.sin(a)).Unit
	local start = W.face + W.n * 22 - W.t * 26
	local st, d = drive("m1a2", start.X, start.Z, dir)
	if st then
		local hit0 = played.vehHit or 0
		local p0 = st.pos
		local w0 = st.wallT
		local halfLen = math.max(W.part.Size.X, W.part.Size.Z) / 2
		local center = V3.new(W.part.CFrame.Position.X, 0, W.part.CFrame.Position.Z)
		H.key(def, Enum.KeyCode.W, true)
		local wallSeen, minOff = false, math.huge
		for _ = 1, 50 do
			H.run(0.1)
			if st.wallT ~= w0 then wallSeen = true end
			local q = V3.new(st.pos.X, 0, st.pos.Z)
			if math.abs((q - center):Dot(W.t)) < halfLen - 3 then minOff = math.min(minOff, (q - W.face):Dot(W.n)) end
		end
		local spd = math.abs(st.speed)
		H.key(def, Enum.KeyCode.W, false)
		local moved = (st.pos - p0)
		local along = moved:Dot(W.t)
		local off = (V3.new(st.pos.X, 0, st.pos.Z) - W.face):Dot(W.n)
		print(string.format("    顺着墙走了 %.1f 格，在墙的长度里离墙面最近 %.1f 格（车宽 %.1f），最后车速 %.1f", along, minOff, d.W, spd))
		check(wallSeen, "蹭上了墙（顺着墙滑）")
		check(along > 40 and spd > d.speed * 0.3, "没被钉死：顺着墙接着往前走")
		check(minOff > d.W * 0.25, "没穿墙")
		check((played.vehHit or 0) > hit0, "撞上那一下有声音")
		H.run(1)
	end
end

print("⑤ 轮式车：高速急转车尾往外甩、轮胎沙沙响")
local wx, wz = flatSpot(camp.X, camp.Z, nil, 90, 3000, V3.new(1, 0, 0))
if wx then
	local st = drive("jltv", wx, wz, V3.new(1, 0, 0))
	check(st ~= nil and st.d.arch == "wheeled", "坐进 JLTV（轮式）")
	if st then
		H.key(def, Enum.KeyCode.W, true)
		H.run(4)
		print(string.format("    直线跑了 4 秒：车速 %.1f（极速 %.1f）", st.speed, st.d.speed))
		H.key(def, Enum.KeyCode.D, true)
		local maxSlip, skid = 0, 0
		for _ = 1, 15 do
			H.run(0.1)
			maxSlip = math.max(maxSlip, math.abs(st.slipA or 0))
		end
		H.key(def, Enum.KeyCode.D, false)
		H.key(def, Enum.KeyCode.W, false)
		print(string.format("    侧滑角最大 %.1f°", math.deg(maxSlip)))
		check(maxSlip > math.rad(4), "急转：车头比去向多转了几度（车尾往外甩）")
		H.run(3)
		check(math.abs(st.slipA or 0) < math.rad(2), "慢下来、回正以后车头和去向又对齐")
	end
end

print(fails == 0 and "载具操控：全部通过" or ("载具操控：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
