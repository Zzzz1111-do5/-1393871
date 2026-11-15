--!nocheck
-- 开服计时：一步一步推，每秒（模拟）打印地图生成进度和实际耗时；lune run tools/test/ia_boot.luau <rbxlx> [最多实际秒数]
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
local maxReal = tonumber(process.args[2]) or 120
local c0 = os.clock()
H.boot(process.args[1], { ds = "mock" })
local G
local last = 0
while os.clock() - c0 < maxReal do
	local s0 = os.clock()
	H.step(1 / 30)
	local ds = os.clock() - s0
	G = G or H.Gs.server
	if ds > 0.5 then print(string.format("  慢的一步：模拟 %.2f 秒处 %.2f 秒", H.now, ds)) end
	if H.now - last >= 1 then
		last = H.now
		print(string.format("模拟 %.0f 秒 实际 %.1f 秒 进度 %.2f ready=%s 零件 %d", H.now, os.clock() - c0, G and G.worldProgress or -1, tostring(G and G.worldReady), #H.workspace:GetDescendants()))
	end
	if G and G.worldReady then break end
end
print(string.format("结束：模拟 %.1f 秒，实际 %.1f 秒，地形块 %s，体素 %s，错误 %d", H.now, os.clock() - c0, tostring(G and G.terrainChunks), tostring(G and G.terrainVoxels), #H.errors))
