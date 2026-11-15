--!nocheck
-- 导出地图高度（看岛的形状）：lune run tools/test/map_export.luau <输出文件> [每格多少 stud，默认 8]
--   输出：一行头（宽 高 步长 原点）+ 每点高度（Float32 小端）+ 每点材质编号（UInt8）；tools/test/map_png.py 画成图
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")

local env = setmetatable({ Color3 = roblox.Color3, Enum = roblox.Enum, Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = _G })
local src = fs.readFile("src/ReplicatedStorage/Map.lua")
local Map = luau.load(src, { debugName = "Map", environment = env })()

local out = process.args[1] or "map.bin"
local step = tonumber(process.args[2]) or 8
local R = Map.R
local n = math.floor(2 * R / step)
local t0 = os.clock()
local hs = buffer.create(n * n * 4)
local ms = buffer.create(n * n)
local MID = { Sand = 1, Rock = 2, Slate = 3, Ground = 4, LeafyGrass = 5, Grass = 6 }
for j = 0, n - 1 do
	local z = -R + (j + 0.5) * step
	for i = 0, n - 1 do
		local x = -R + (i + 0.5) * step
		local y = Map.height(x, z)
		buffer.writef32(hs, (j * n + i) * 4, y)
		if y > 0.3 then
			local m = Map.material(x, z, y, Map.slope(x, z))
			buffer.writeu8(ms, j * n + i, MID[m.Name] or 9)
		end
	end
end
local meta = { n = n, step = step, R = R, points = {}, beaches = {}, fleet = {}, flat = {} }
for _, p in ipairs(Map.POINTS) do table.insert(meta.points, { p.id, p.x, p.z, p.y }) end
for _, b in ipairs(Map.BEACHES) do table.insert(meta.beaches, { b.id, b.x0, b.x1, b.z }) end
for _, f in ipairs(Map.FLEET) do table.insert(meta.fleet, { f.kind, f.x, f.z }) end
for _, k in ipairs({ "AIRFIELD", "COMMAND", "CAMP", "PORT", "AFIELD2" }) do table.insert(meta.flat, { k, Map[k].x, Map[k].z, Map[k].y }) end
local net = require("@lune/serde")
fs.writeFile(out .. ".json", net.encode("json", meta))
fs.writeFile(out, buffer.tostring(hs))
fs.writeFile(out .. ".mat", buffer.tostring(ms))
print(string.format("导出 %d × %d，用时 %.1f 秒", n, n, os.clock() - t0))
