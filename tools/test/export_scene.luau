--!nocheck
-- 把测试台里的场景导出成 JSON（零件的世界位置、大小、颜色、形状、材质、透明度 + 地形填充），给预览渲染用
-- 用法：lune run export_scene.luau <rbxlx> <输出.json> [all|base|battle]
--   all：把第 1 块基地的楼全盖了、造一批兵；battle：再开一仗、打到一半时导出
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = true
H.followCam = true
H.boot(process.args[1])
H.run(2)
local mode = process.args[3] or "all"
local p1 = H.addPlayer("P1", 9001)
H.run(6)
local G = H.Gs.server
local st = G.states[p1]
local function act(...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs.P1.R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = p1
	coroutine.resume(co)
	H.ctx = nil
end
if mode ~= "empty" then
	st.data.cash = 1e9
	local plotF = H.workspace.Plots["Plot" .. st.plot.index]
	for _ = 1, 16 do
		for _, b in G.Config.Buildings do
			local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
			if m and (mode ~= "base" or b.price < 5000) then H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
		end
		H.run(1.3)
	end
	for _ = 1, 3 do act("hq") H.run(0.3) end
	for _, t in { "inf", "inf", "mg", "at", "medic", "tank", "tank", "ifv", "heavytank", "aa", "spaag", "sam", "arty", "mlrs", "heli", "transport", "drone", "attacker", "fighter" } do
		act("buy", t)
		H.run(0.3)
	end
	H.run(30)
end
if mode == "theaters" then   -- 第 1~5 块基地的战场各摆一个战区
	for i, th in { "grass", "desert", "snow", "urban", "volcano" } do G.Scenery.theater(G.plots[i], th, G.Config) end
	H.run(1)
end
if mode == "battle" then
	st.data.level = tonumber(process.args[4]) or 14
	G.makeEnemy(st)
	H.run(1)
	act("battle")
	H.run(tonumber(process.args[5]) or 9)
end
-- 机场、直升机场的展示飞机在客户端里会起飞绕圈：导出前让它们回到停放的状态（看得清停在哪）
do
	local C1 = H.Gs.P1
	if C1 and C1.shows then
		for _, sh in pairs(C1.shows) do sh.t = 1 end
		H.run(0.05)
	end
end
local function rot(cf)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end
local function c3(c) return { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) } end
local out = { parts = {}, terrain = {}, origin = { st.plot.origin.X, st.plot.origin.Y, st.plot.origin.Z } }
for _, d in H.workspace:GetDescendants() do
	if d:IsA("BasePart") and d.ClassName ~= "Terrain" and d.Transparency < 0.99 and not H.destroyed[d] then
		local ok, e = pcall(function()
			local cf = H.worldCF(d)
			local okL, ltm = pcall(function() return d.LocalTransparencyModifier end)
			if okL and ltm and ltm > 0.5 then return nil end
			local shape = "Block"
			if d.ClassName == "Part" then
				local okS, sh = pcall(function() return d.Shape end)
				shape = okS and sh and sh.Name or "Block"
			elseif d.ClassName == "WedgePart" then
				shape = "Wedge"
			end
			return { p = { cf.X, cf.Y, cf.Z }, r = rot(cf), s = { d.Size.X, d.Size.Y, d.Size.Z }, c = c3(d.Color), t = d.Transparency, sh = shape, m = d.Material.Name }
		end)
		if ok and e then
			table.insert(out.parts, e)
		elseif not ok then
			H.exportErr = H.exportErr or tostring(e)
		end
	end
end
for _, op in H.terrainOps do
	local cf = op.cf
	table.insert(out.terrain, { k = op.k, p = { cf.X, cf.Y, cf.Z }, r = rot(cf), s = op.size and { op.size.X, op.size.Y, op.size.Z } or nil, rad = op.r, h = op.h, m = op.m })
end
if H.exportErr then print("导出出错（举例）：" .. H.exportErr) end
local L = H.game:GetService("Lighting")
out.light = { clock = L.ClockTime }
fs.writeFile(process.args[2], serde.encode("json", out))
print(string.format("导出：零件 %d 个，地形填充 %d 次 → %s", #out.parts, #out.terrain, process.args[2]))
