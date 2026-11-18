--!nocheck
-- 某一片地方的零件导出（看样子用）：lune run tools/test/area_dump.luau <rbxlx> <输出 JSON> <x> <z> <半径>
--   开服把地图、生成点、码头建好，半径内所有固定零件写成 JSON：形状、大小、CFrame（12 个数）、颜色、透明度
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 300)
H.run(3)
local cx, cz, r = tonumber(process.args[3]), tonumber(process.args[4]), tonumber(process.args[5])
local out = {}
for _, p in ipairs(H.workspace:GetDescendants()) do
	local ok, cf = pcall(function() return p:IsA("BasePart") and not p:IsA("Terrain") and p.CFrame end)
	if ok and cf and math.sqrt((cf.Position.X - cx) ^ 2 + (cf.Position.Z - cz) ^ 2) < r and p.Transparency < 0.99 then
		local shape = p.ClassName == "WedgePart" and "Wedge" or (p:IsA("Part") and p.Shape.Name or "Block")
		table.insert(out, { sh = shape, s = { p.Size.X, p.Size.Y, p.Size.Z }, cf = { cf:GetComponents() },
			col = { math.floor(p.Color.R * 255), math.floor(p.Color.G * 255), math.floor(p.Color.B * 255) }, t = p.Transparency, n = p.Name })
	end
end
fs.writeFile(process.args[2], serde.encode("json", out))
print("导出 " .. #out .. " 块")
