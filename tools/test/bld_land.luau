--!nocheck
-- 地图建筑都在陆地上（用户 11-18 截图：这些建筑漂在水里）：开服建完地图，每座建筑（Bld_<键> 模型）按占地的四角、四边中点、中心量地面——
--   有一点是海（Map.isLand 为假）就算漂在水上；也打印每座的位置、底面高度、落在水里的那几个点
--   lune run tools/test/bld_land.luau <rbxlx> [v]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = process.args[2] ~= "v"

H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 300)
local Map = G.Map
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

local n, wet = 0, {}
for _, m in ipairs(H.workspace:GetDescendants()) do
	if m:IsA("Model") and m:GetAttribute("Bld") then
		n += 1
		local cf, size = m:GetBoundingBox()
		local bad = 0
		for _, o in ipairs({ { 0, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
			local p = cf * roblox.Vector3.new(o[1] * size.X * 0.45, 0, o[2] * size.Z * 0.45)
			if not Map.isLand(p.X, p.Z) then bad += 1 end
		end
		if bad > 0 then
			table.insert(wet, string.format("%s（%s）在 (%.0f, %.0f)，%d / 9 个点在海里，底面高 %.1f", m.Name, m.Parent and m.Parent.Name or "?", cf.Position.X, cf.Position.Z, bad, cf.Position.Y - size.Y / 2))
		end
	end
end
check(n > 20, "地图上有 " .. n .. " 座建筑")
for _, s in ipairs(wet) do print("    " .. s) end
check(#wet == 0, string.format("没有建筑漂在水上（%d 座有一部分在海里）", #wet))
H.summary()
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
