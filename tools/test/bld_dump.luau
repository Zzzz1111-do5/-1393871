--!nocheck
-- 地图建筑导出（看零件拼的样子用）：lune run tools/test/bld_dump.luau <rbxlx> <输出 JSON>
--   开服把地图建好，Map/Scenery 下所有 Buildings 文件夹里的零件（方块、楔形、圆柱、球）写成 JSON：类名、形状、大小、CFrame（12 个数）、颜色、材质、透明度
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
local G
for _ = 1, 30 * 120 do
	H.step(1 / 30)
	G = G or H.Gs.server
	if G and G.worldReady then break end
end
local out = {}
local sites = {}
for _, d in ipairs(H.workspace:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("Bld") then
		local site = d.Parent and d.Parent.Parent and d.Parent.Parent.Name or "?"
		local list = {}
		for _, p in ipairs(d:GetDescendants()) do
			if p:IsA("BasePart") then
				local cf = p.CFrame
				local shape = p.ClassName == "WedgePart" and "Wedge" or (p:IsA("Part") and p.Shape.Name or "Block")
				table.insert(list, { c = p.ClassName, sh = shape, s = { p.Size.X, p.Size.Y, p.Size.Z }, cf = { cf:GetComponents() },
					col = { math.floor(p.Color.R * 255), math.floor(p.Color.G * 255), math.floor(p.Color.B * 255) }, m = p.Material.Name, t = p.Transparency })
			end
		end
		table.insert(out, { key = d:GetAttribute("Bld"), site = site, parts = list })
	end
end
fs.writeFile(process.args[2], serde.encode("json", out))
print(string.format("建筑 %d 座，错误 %d", #out, #H.errors))
for _, e in ipairs(H.errors) do print("  " .. tostring(e)) end
