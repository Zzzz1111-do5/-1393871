--!nocheck
-- 小地图「卫星图」预览（MapPaint.lua）：整张图的底图、主岛一块细节，写成 PPM 图片（看配色、阴影、细节用）
--   用法：lune run tools/test/map_preview.luau <rbxlx> <输出目录>
local process = require("@lune/process")
local fs = require("@lune/fs")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
H.run(0.3)
local G = H.Gs.server
local Map = G.Map
local RS = H.game:GetService("ReplicatedStorage")
local Paint = H.require(RS:FindFirstChild("MapPaint"))
local out = process.args[2] or "."
local K = Map.K
local X0, Z0, SPAN = -3000 * K, -2500 * K, 6100 * K

local function save(name, P)
	local buf = buffer.create(P.w * P.h * 4)
	local t0 = os.clock()
	Paint.paint(Map, P, 0, P.h, buf)
	local dt = os.clock() - t0
	local parts = { string.format("P6\n%d %d\n255\n", P.w, P.h) }
	local rgb = buffer.create(P.w * P.h * 3)
	for i = 0, P.w * P.h - 1 do
		buffer.writeu8(rgb, i * 3, buffer.readu8(buf, i * 4))
		buffer.writeu8(rgb, i * 3 + 1, buffer.readu8(buf, i * 4 + 1))
		buffer.writeu8(rgb, i * 3 + 2, buffer.readu8(buf, i * 4 + 2))
	end
	table.insert(parts, buffer.tostring(rgb))
	fs.writeFile(out .. "/" .. name .. ".ppm", table.concat(parts))
	print(string.format("%s：%d×%d，%.2f 秒（%.2f 微秒 / 像素）", name, P.w, P.h, dt, dt / (P.w * P.h) * 1e6))
end

-- 整张图（小地图拉远、部署地图）：512 × 512，每像素 SPAN/512 格
save("map_base", { x0 = X0, z0 = Z0, step = SPAN / 512, w = 512, h = 512, detail = false, exag = 2.6 })
-- 主岛南岸、港湾一带的细节（小地图跟着人时的样子）：每像素 6.25 格
local cx, cz = Map.PORT.x, Map.PORT.z
save("map_detail", { x0 = cx - 2000, z0 = cz - 1400, step = 6.25, w = 640, h = 448, detail = true, exag = 1.5 })
local A = Map.AIRFIELD
save("map_airfield", { x0 = A.x - 1600, z0 = A.z - 900, step = 6.25, w = 512, h = 288, detail = true, exag = 1.5 })
-- 小地图里看到的那一块：守方营地一带，步兵的雷达范围（±520 格，每像素 6.25 格）
local C = Map.CAMP
save("map_mini", { x0 = C.x - 520, z0 = C.z - 520, step = 6.25, w = 166, h = 166, detail = true, exag = 1.5 })
local P2 = Map.POINTS[1]
save("map_mini_a", { x0 = P2.x - 520, z0 = P2.z - 520, step = 6.25, w = 166, h = 166, detail = true, exag = 1.5 })
H.shutdown()
process.exit(0)
