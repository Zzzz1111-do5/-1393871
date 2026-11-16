--!nocheck
-- 舰艇原模型测试：假装在 Studio 里导入了 models/ship/ 的 7 艘船（按 ImportedShip 摆同名的 MeshPart 放在 Workspace）→ 开服收进 ReplicatedStorage.Imported.Ship →
--   七型舰艇拼出来都是原模型（零件拼的只剩灯、粒子、舰旗）→ 型号表的炮位、炮管长照原模型改了 → 桅顶灯在原模型最高点上 →
--   守方生成 DDG-125、下船，炮塔角变了原模型的主炮跟着转（绕原模型的炮塔转轴，船体不动）→ 击沉后贴图去掉、烧黑
-- 用法（仓库根目录）：lune run tools/test/ia_import_ship.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst, Enum = roblox.Vector3, roblox.CFrame, roblox.Instance, roblox.Enum
H.quietWarn = process.args[2] ~= "v"

local IS = luau.load(fs.readFile("src/ReplicatedStorage/ImportedShip.lua"), { debugName = "ImportedShip" })()
local function count(t) local n = 0 for _ in pairs(t) do n += 1 end return n end

H.boot(process.args[1], { ds = "mock", before = function(game)
	for id, info in pairs(IS.m) do
		local m = Inst.new("Model")
		m.Name = "S_" .. id
		for name, p in pairs(info.parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "S_" .. id .. "__" .. name
			mp.Size = V3.new(p.s[1], p.s[2], p.s[3])
			mp.CFrame = CF.new(1500 + p.c[1], 300 + p.c[2], 1500 + p.c[3])
			mp.Anchored = true
			mp.Parent = m
		end
		m.Parent = game:GetService("Workspace")
	end
end })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function act(pl, ...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.VehicleCats.ship.min = 2   -- 测试只有两个人：名额按人数算是 0，这里放开
H.runUntil(function() return G.worldReady end, 120)

print("① 开服：把导入的舰艇原模型收好")
local RS = H.game:GetService("ReplicatedStorage")
local okAll = true
for id, info in pairs(IS.m) do
	local f = RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Ship") and RS.Imported.Ship:FindFirstChild(id)
	if not (f and #f:GetChildren() == count(info.parts)) then okAll = false print("    " .. id .. " 不对") end
end
check(okAll and G.importedShip and #G.importedShip == 7, "七艘都收进 Imported.Ship：" .. table.concat(G.importedShip or {}, ","))

print("② 七型舰艇拼出来都是原模型")
local p1, p2 = H.addPlayer("P1", 7301), H.addPlayer("P2", 7302)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local PD, CD = G.P[def], H.Gs[def.Name]
local SD = G.ShipDefs
local bad = {}
for id, info in pairs(IS.m) do
	local d = SD.get(id)
	local M = CD.buildShipModel(d, "def")
	local meshes, other, ti = 0, 0, 0
	for _, it in ipairs(M.items) do
		if it.p:IsA("MeshPart") then
			meshes += 1
			if it.g == "ti" then ti += 1 end
		elseif not (it.tag == "lamp" or it.tag == "fx" or it.tag == "flag") then
			other += 1
		end
	end
	local wantTi = 0
	for name, p in pairs(info.parts) do if string.match(p.g, "^T%d+$") and info.guns[tonumber(string.sub(p.g, 2))] then wantTi += 1 end end
	if M.imported ~= id or meshes ~= count(info.parts) or other ~= 0 or ti ~= wantTi then
		table.insert(bad, string.format("%s（原模型 %d/%d 块，主炮 %d/%d，零件拼的蒙皮 %d）", id, meshes, count(info.parts), ti, wantTi, other))
	end
	-- 桅顶白灯在原模型最高点上面
	local top = info.top
	local hi = -1e9
	for _, it in ipairs(M.items) do if it.tag == "lamp" then hi = math.max(hi, it.off.Position.Y) end end
	if top and math.abs(hi - (top[2] + 1.2)) > 0.01 then table.insert(bad, id .. " 桅顶灯 " .. hi .. " / " .. (top[2] + 1.2)) end
	M.model:Destroy()
end
check(#bad == 0, "原模型全用上、主炮单独成组、蒙皮去掉、桅顶灯挪到原模型最高点" .. ((#bad > 0) and ("：" .. table.concat(bad, "；")) or ""))
-- 型号表的炮位、炮管长照原模型
local dd = SD.get("ddg125")
local gd = IS.m.ddg125.guns[1]
check((dd.guns[1].pos - V3.new(gd.piv[1], gd.piv[2], gd.piv[3])).Magnitude < 1e-3, string.format("DDG-125 的炮位照原模型（z %.1f）", dd.guns[1].pos.Z))
local c47 = SD.get("cg47")
check(c47.guns[2].pos.Z > 100 and c47.guns[1].pos.Z < -80, string.format("CG-47 前后两门炮照原模型（%.1f、%.1f）", c47.guns[1].pos.Z, c47.guns[2].pos.Z))

print("③ 守方生成 DDG-125、下船；炮塔角变了，原模型的主炮跟着转")
act(def, "deploy", "rifle", "camp")
H.run(2)
local pd = H.pad(G, "ddg125")
local e = pd and H.usePad(G, def, pd)
check(e ~= nil and e.ship, "生成了 DDG-125")
H.run(1)
H.key(def, Enum.KeyCode.F, true) H.key(def, Enum.KeyCode.F, false)
H.run(1.5)
check(PD.vehicle == nil, "下船了")
local v = nil
for em, vv in pairs(CD.views) do if e and em == e.model then v = vv end end
check(v and v.M and v.M.imported == "ddg125", "客户端看到的是原模型")
local gun, hull
for _, it in ipairs(v.M.items) do
	if it.g == "ti" and not gun then gun = it end
	if it.g == "hull" and it.p:IsA("MeshPart") and not hull then hull = it end
end
local function rel(p) return v.base:ToObjectSpace(p.CFrame) end
e.model:SetAttribute("Ty1", 0)
H.run(1.5)
local g0, h0 = rel(gun.p), rel(hull.p)
e.model:SetAttribute("Ty1", 90)
H.run(2)
local g1, h1 = rel(gun.p), rel(hull.p)
local piv = gun.piv.Position
local d0 = (V3.new(g0.Position.X, 0, g0.Position.Z) - V3.new(piv.X, 0, piv.Z)).Magnitude
local d1 = (V3.new(g1.Position.X, 0, g1.Position.Z) - V3.new(piv.X, 0, piv.Z)).Magnitude
local turned = math.deg(select(2, (g0.Rotation:Inverse() * g1.Rotation):ToAxisAngle()))
local dev = math.min(math.abs(turned - 90), math.abs(turned - 270))   -- 绕 +Y 转 −90°（右转）读出来是 270°
check(dev < 8 and math.abs(d0 - d1) < 0.2, string.format("主炮绕原模型的转轴转了 %.0f°（离转轴 %.2f → %.2f 格；船随浪起伏会差一点）", turned, d0, d1))
check((h0.Position - h1.Position).Magnitude < 0.6, "船体不跟着转")

print("④ 击沉：贴图去掉、烧黑")
G.damageEnt(e, 1e9, { team = "atk", name = "test" })
H.run(3)
local dark, n = 0, 0
for _, it in ipairs(v.M.items) do
	if it.p:IsA("MeshPart") then
		n += 1
		if it.p.TextureID == "" then dark += 1 end
	end
end
check(n > 0 and dark == n, string.format("%d / %d 块烧黑", dark, n))

H.summary()
for i, w in ipairs(H.warns) do if i <= 6 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
