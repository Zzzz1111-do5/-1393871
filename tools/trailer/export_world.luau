--!nocheck
-- 宣传片（tools/trailer）用的地图数据：开一个服务器把世界搭好（地形、工事、营地、机场、灯塔、舰队……），导出
--   height.bin  地形高度（Float32，(N+1) × (N+1)，从 -R 到 +R、每 STEP 格一个，按 z 行 x 列；海底是负的，水面在 0）
--   mat.bin     地形材质（Uint8，同上；编号见 world.json 的 mats）
--   world.json  地图上的点（据点、海滩、舰队、机场……）、世界里的零件（形状、大小、位置、颜色、材质、透明度）、灯（点光、聚光、面光）
-- 用法（仓库根目录）：lune run tools/trailer/export_world.luau <rbxlx> <输出目录> [STEP，默认 8]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("../test/harness")
H.quietWarn = true

local place, outDir = process.args[1], process.args[2]
local STEP = tonumber(process.args[3] or "8")
assert(place and outDir, "用法：lune run tools/trailer/export_world.luau <rbxlx> <输出目录> [STEP]")
if not fs.isDir(outDir) then fs.writeDir(outDir) end

H.boot(place, { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.Config.Bots.minPerTeam = 0
G.fortsHold = true
G.navyNoAI = true
H.runUntil(function() return G.worldReady end, 160)
-- 进一个玩家：工事、舰艇、生成点的样子是客户端搭的（FortView、ShipView、Depot），有人在才会出现
local pl = H.addPlayer("Cam", 9301)
H.run(6)
print("世界搭好了")

local RS = H.game:GetService("ReplicatedStorage")
local Map = H.require(RS:FindFirstChild("Map"))

-- 地形
local R = Map.R
local N = math.floor(2 * R / STEP)
local n1 = N + 1
local hb = buffer.create(n1 * n1 * 4)
local mb = buffer.create(n1 * n1)
local mats, matId = {}, {}
local function mid(m)
	local k = tostring(m)
	if not matId[k] then table.insert(mats, k) matId[k] = #mats end
	return matId[k]
end
local t0 = os.clock()
for j = 0, N do
	local z = -R + j * STEP
	for i = 0, N do
		local x = -R + i * STEP
		local y = Map.height(x, z)
		buffer.writef32(hb, (j * n1 + i) * 4, y)
	end
end
print(string.format("高度 %d × %d：%.1f 秒", n1, n1, os.clock() - t0))
t0 = os.clock()
local function hAt(i, j)
	i = math.clamp(i, 0, N) j = math.clamp(j, 0, N)
	return buffer.readf32(hb, (j * n1 + i) * 4)
end
for j = 0, N do
	local z = -R + j * STEP
	for i = 0, N do
		local x = -R + i * STEP
		local y = hAt(i, j)
		local sx = (hAt(i + 1, j) - hAt(i - 1, j)) / (2 * STEP)
		local sz = (hAt(i, j + 1) - hAt(i, j - 1)) / (2 * STEP)
		local slope = math.sqrt(sx * sx + sz * sz)
		buffer.writeu8(mb, j * n1 + i, mid(Map.material(x, z, y, slope)))
	end
end
print(string.format("材质：%.1f 秒", os.clock() - t0))
fs.writeFile(outDir .. "/height.bin", hb)
fs.writeFile(outDir .. "/mat.bin", mb)

-- 地图上的点
local function pt(p) return p and { x = p.x, z = p.z, y = p.y } or nil end
local meta = { R = R, step = STEP, n = n1, mats = mats, points = {}, beaches = Map.BEACHES, fleet = Map.FLEET, barge = Map.BARGE,
	airfield = Map.AIRFIELD, afield2 = Map.AFIELD2, command = pt(Map.COMMAND), camp = pt(Map.CAMP), port = pt(Map.PORT),
	main = Map.MAIN, isles = {}, landings = Map.LANDINGS }
for _, p in ipairs(Map.POINTS) do table.insert(meta.points, { id = p.id, x = p.x, z = p.z, y = p.y }) end
for _, I in ipairs(Map.ISLES or {}) do
	local c = {}
	for k, v in pairs(I) do if type(v) == "number" or type(v) == "string" then c[k] = v end end
	table.insert(meta.isles, c)
end
-- 海岸线（主岛南北岸每 16 格一个点）
meta.coastS, meta.coastN = {}, {}
for x = -R, R, 16 do
	local s, n = Map.coastS(x), Map.coastN(x)
	if s then table.insert(meta.coastS, { x, s }) end
	if n then table.insert(meta.coastN, { x, n }) end
end

-- 世界里的零件和灯（不要人物）
local parts, lights = {}, {}
local function top(d)   -- 归到哪一类：workspace 下第一层 / 第二层的名字
	local p, q = d, nil
	while p.Parent and p.Parent ~= H.workspace do q = p p = p.Parent end
	return q and (p.Name .. "/" .. q.Name) or p.Name
end
local function r4(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function cfArr(cf)
	local t = { cf:GetComponents() }
	for i, v in ipairs(t) do t[i] = r4(v) end
	return t
end
local skip = 0
for _, d in ipairs(H.workspace:GetDescendants()) do
	if d:IsA("BasePart") and not d:IsA("Terrain") then
		local m = d:FindFirstAncestorOfClass("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then
			skip += 1
		else
			local shape = d:IsA("Part") and tostring(d.Shape) or d.ClassName
			local sm = d:FindFirstChildOfClass("SpecialMesh")
			if sm then shape = "Mesh:" .. tostring(sm.MeshType) end
			table.insert(parts, { n = d.Name, g = top(d), k = d.ClassName, sh = shape,
				s = { r4(d.Size.X), r4(d.Size.Y), r4(d.Size.Z) }, cf = cfArr(d.CFrame),
				c = { r4(d.Color.R), r4(d.Color.G), r4(d.Color.B) }, m = tostring(d.Material), t = r4(d.Transparency),
				an = d:GetAttribute("Anim") })
		end
	elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
		local p = d.Parent
		if p and p:IsA("BasePart") then
			local L = { k = d.ClassName, cf = cfArr(p.CFrame), c = { r4(d.Color.R), r4(d.Color.G), r4(d.Color.B) },
				r = d.Range, b = d.Brightness, sh = d.Shadows, g = top(p), en = d.Enabled }
			if not d:IsA("PointLight") then L.a, L.f = d.Angle, tostring(d.Face) end
			table.insert(lights, L)
		end
	end
end
meta.parts, meta.lights = parts, lights
-- 地图表里可能夹着 Vector3、枚举、函数：Vector3 转成数组，其余不能存的丢掉
local function clean(v, depth)
	local t = typeof(v)
	if t == "number" or t == "string" or t == "boolean" then return v end
	if t == "Vector3" then return { v.X, v.Y, v.Z } end
	if t == "table" and depth < 8 then
		local o = {}
		for k, x in pairs(v) do
			if type(k) == "string" or type(k) == "number" then o[k] = clean(x, depth + 1) end
		end
		return o
	end
	return nil
end
fs.writeFile(outDir .. "/world.json", serde.encode("json", clean(meta, 0)))
print(string.format("零件 %d、灯 %d（跳过人物零件 %d）；材质 %s", #parts, #lights, skip, table.concat(mats, " ")))
process.exit(0)
