--!nocheck
-- 海上漂着什么（用户 11-18 截图：这些建筑漂在水里）：开服建完地图，列出摆在海上（Map.isLand 为假）、露出水面的固定零件，按最上一层的模型 / 文件夹归类
--   lune run tools/test/sea_props.luau <rbxlx>
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 300)
H.run(3)
local Map = G.Map
local groups = {}
local function groupOf(p)   -- 往上找到离 Workspace 第三层的那个（Workspace.Map.Scenery.<模型>）；名字里的编号去掉，同一类归一起
	local chain = {}
	local cur = p
	while cur and cur ~= H.workspace do
		table.insert(chain, 1, cur)
		cur = cur.Parent
	end
	return chain[math.min(3, #chain)] or p
end
for _, p in ipairs(H.workspace:GetDescendants()) do
	local okp, pos = pcall(function() return p:IsA("BasePart") and p.Anchored and not p:IsA("Terrain") and p.CFrame.Position end)
	if okp and pos then
		if not Map.isLand(pos.X, pos.Z) and pos.Y + p.Size.Y / 2 > 0.3 and pos.Y < 60 then
			local g = groupOf(p)
			local key = (string.gsub(g:GetFullName(), "%d+", "#"))
			local e = groups[key] or { n = 0, x = pos.X, z = pos.Z, y = pos.Y, name = g.Name, cls = g.ClassName, deep = 0, bed = 0 }
			e.n += 1
			local bed = Map.height(pos.X, pos.Z)
			e.bed = math.min(e.bed, bed)
			if bed < -2.5 then e.deep += 1 end   -- 底下的海比 2.5 格还深（零件要么浮着、要么是船、浮台）
			groups[key] = e
		end
	end
end
local list = {}
for k, e in pairs(groups) do table.insert(list, { k = k, e = e }) end
table.sort(list, function(a, b) return a.e.n > b.e.n end)
for i, it in ipairs(list) do
	if i <= 60 then print(string.format("%5d 块  %-60s  例 (%.0f, %.1f, %.0f)  底下深过 2.5 格的 %d 块，最深 %.1f", it.e.n, it.k, it.e.x, it.e.y, it.e.z, it.e.deep, it.e.bed)) end
end
print("共 " .. #list .. " 组")
-- 导出：海上零件（组、位置、大小）+ 陆地网格，给 python 画俯视图
if process.args[2] then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local out = { parts = {}, land = {}, step = 60, R = Map.R }
	for _, p in ipairs(H.workspace:GetDescendants()) do
		local okp, pos = pcall(function() return p:IsA("BasePart") and p.Anchored and not p:IsA("Terrain") and p.CFrame.Position end)
		if okp and pos and not Map.isLand(pos.X, pos.Z) and pos.Y + p.Size.Y / 2 > 0.3 and pos.Y < 60 then
			local g = groupOf(p)
			table.insert(out.parts, { g = (string.gsub(g:GetFullName(), "%d+", "#")), x = pos.X, y = pos.Y, z = pos.Z, sx = p.Size.X, sz = p.Size.Z, n = p.Name })
		end
	end
	local R = Map.R
	for z = -R, R, 60 do
		local row = {}
		for x = -R, R, 60 do table.insert(row, Map.isLand(x, z) and 1 or 0) end
		table.insert(out.land, row)
	end
	fs.writeFile(process.args[2], serde.encode("json", out))
	print("写好了 " .. process.args[2])
end
