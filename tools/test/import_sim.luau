--!nocheck
-- 模拟在 Studio 里导入了合并包 all_units.glb：按 GLB 里每个网格的包围盒摆一个零件（名字、层级照 GLB），
-- 分「保留层级」和「压平成一层」两种，开服看游戏能不能把 24 个兵种都认出来、单位用上导入的模型
-- 用法：lune run import_sim.luau <rbxlx> <all_units.glb> [flat]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF = roblox.Vector3, roblox.CFrame
local Inst = roblox.Instance
H.quietWarn = false
local flat = process.args[3] == "flat"

local raw = fs.readFile(process.args[2])
local jlen = string.unpack("<I4", raw, 13)
local J = serde.decode("json", string.sub(raw, 21, 20 + jlen))

local function build(game)
	local ws = game:GetService("Workspace")
	local top = Inst.new("Model")
	top.Name = "all_units"
	local count = 0
	local function walk(ni, parentModel, off)
		local n = J.nodes[ni + 1]
		local t = n.translation and V3.new(n.translation[1], n.translation[2], n.translation[3]) or V3.new()
		local here = off + t
		if n.mesh then
			local mn, mx = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
			for _, p in J.meshes[n.mesh + 1].primitives do
				local a = J.accessors[p.attributes.POSITION + 1]
				mn = V3.new(math.min(mn.X, a.min[1]), math.min(mn.Y, a.min[2]), math.min(mn.Z, a.min[3]))
				mx = V3.new(math.max(mx.X, a.max[1]), math.max(mx.Y, a.max[2]), math.max(mx.Z, a.max[3]))
			end
			local part = Inst.new("MeshPart")
			part.Name = n.name
			part.Size = V3.new(math.max(0.05, mx.X - mn.X), math.max(0.05, mx.Y - mn.Y), math.max(0.05, mx.Z - mn.Z))
			part.CFrame = CF.new(here + (mn + mx) / 2)
			part.Anchored = false
			part.Parent = flat and top or parentModel
			count += 1
		end
		if n.children then
			local holder = parentModel
			if not n.mesh and not flat then
				holder = Inst.new("Model")
				holder.Name = n.name
				holder.Parent = parentModel
			end
			for _, c in n.children do walk(c, holder, here) end
		end
	end
	for _, r in J.scenes[1].nodes do walk(r, top, V3.new()) end
	top.Parent = ws
	print(string.format("模拟导入：%d 个零件，%s", count, flat and "压平成一层" or "保留层级"))
end

H.boot(process.args[1], { before = build })
H.run(3)
local imported = nil
for _, pr in H.prints do
	if pr.msg:find("用上了导入的原模型") then imported = pr.msg end
end
print(imported or "没认出导入的模型")
local n = 0
if imported then for _ in imported:gmatch("、") do n += 1 end n += 1 end
local left = H.workspace:FindFirstChild("all_units")
print("认出", n, "个；地图里剩下的导入壳：", left and #left:GetDescendants() or 0)
local p1 = H.addPlayer("P1", 3001)
H.run(6)
local G = H.Gs.server
local st = G.states[p1]
st.data.cash = 1e6
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
for _ = 1, 16 do
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m then H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
	end
	H.run(1.3)
end
local co = coroutine.create(function() H.Gs.P1.R.Action:FireServer("hq") end)
H.ctx = p1 coroutine.resume(co) H.ctx = nil
H.run(1)
for _, t in { "inf", "mg", "at", "tank", "heli", "fighter", "spaag", "mlrs" } do
	local co2 = coroutine.create(function() H.Gs.P1.R.Action:FireServer("buy", t) end)
	H.ctx = p1 coroutine.resume(co2) H.ctx = nil
	H.run(0.3)
end
H.run(20)
for _, u in pairs(st.units) do
	local meshes, hubs = 0, 0
	for _, d in u.model:GetDescendants() do
		if d:IsA("MeshPart") then meshes += 1 end
		if d:IsA("Motor6D") then hubs += 1 end
	end
	print(string.format("  %-8s 导入网格 %2d 个，转动部件 %d 个，高 %.1f", u.t, meshes, hubs, G.Models.heightOf(u.t)))
end
co = coroutine.create(function() H.Gs.P1.R.Action:FireServer("battle") end)
H.ctx = p1 coroutine.resume(co) H.ctx = nil
H.runUntil(function() return st.battle == nil end, 260)
H.run(1)
H.summary()
if #H.errors > 0 or n < 24 then process.exit(1) end
