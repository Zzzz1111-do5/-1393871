--!nocheck
-- 航母（福建舰）测试（用户 11-21：航母不够真）：
--   ① 假装在 Studio 里导入了 models/ship/fujian.glb（按 CarrierMeta 摆同名的 MeshPart 放在 Workspace）→ 开服收进 Imported.Ship.fujian →
--      攻方航母用原模型（每块照元数据摆、颜色材质照元数据、不参与碰撞），甲板是看不见的碰撞板、舰岛有碰撞盒
--   ② 甲板判定照原模型的轮廓：舰艏两边、舰尾外面是海，斜角甲板往左舷伸出去的地方是甲板；三条弹射器、拦阻索区都在甲板上
--   ③ 右舷三个停机位、舰岛旁的出生点都在甲板上，不压着舰区、不压舰岛；夜灯够多
--   ④ 没导入（lune run tools/test/ia_carrier.luau <rbxlx> plain）：照轮廓拼的甲板看得见、有船体和舰岛
-- 用法（仓库根目录）：lune run tools/test/ia_carrier.luau <rbxlx> [plain]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = true
local plain = process.args[2] == "plain"

local CM = luau.load(fs.readFile("src/ReplicatedStorage/CarrierMeta.lua"), { debugName = "CarrierMeta" })()
local nParts = 0
for _ in pairs(CM.parts) do nParts += 1 end

H.boot(process.args[1], { ds = "mock", before = function(game)
	if plain then return end
	local m = Inst.new("Model")
	m.Name = "fujian"
	for name, p in pairs(CM.parts) do
		local mp = Inst.new("MeshPart")
		mp.Name = "S_fujian__" .. name
		mp.Size = V3.new(p.s[1], p.s[2], p.s[3])
		mp.CFrame = CF.new(1800 + p.c[1], 300 + p.c[2], 1800 + p.c[3])
		mp.Anchored = true
		mp.Parent = m
	end
	m.Parent = game:GetService("Workspace")
end })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local G = H.Gs.server
H.runUntil(function() return G.worldReady == true end, 120)
H.run(1)
local Map = G.Map
local AirDefs = G.AirDefs

local cv = H.workspace.Map.Fleet:FindFirstChild("Ship_carrier1")
check(cv ~= nil, "攻方航母在舰队里")
if not cv then process.exit(1) end
local s = Map.FLEET[1]
local base = CF.new(s.x, 0, s.z) * CF.Angles(0, s.rot or 0, 0)

if not plain then
	print("① 原模型")
	check(cv:GetAttribute("Imported") == true, "用了原模型（Imported 属性）")
	local n, okPos, okCol, coll = 0, 0, 0, 0
	for _, d in ipairs(cv:GetChildren()) do
		if d:IsA("MeshPart") and d.Name:match("^S_fujian__") then
			n += 1
			local p = CM.parts[d.Name:sub(#"S_fujian__" + 1)]
			if p then
				local want = (base * CF.new(p.c[1], p.c[2], p.c[3])).Position
				if (d.CFrame.Position - want).Magnitude < 0.05 then okPos += 1 end
				local c = d.Color
				if math.abs(c.R * 255 - p.col[1]) < 1.5 and math.abs(c.G * 255 - p.col[2]) < 1.5 then okCol += 1 end
			end
			if d.CanCollide then coll += 1 end
		end
	end
	check(n == nParts, string.format("原模型 %d / %d 块都摆上了", n, nParts))
	check(okPos == nParts, string.format("每块照元数据的中心摆（%d 块对）", okPos))
	check(okCol == nParts, string.format("颜色照元数据（%d 块对）", okCol))
	check(coll == 0, "原模型的网格不参与碰撞")
	local decks, hidden, isl = 0, 0, 0
	for _, d in ipairs(cv:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Deck" then
			decks += 1
			if d.Transparency >= 1 and d.CanCollide then hidden += 1 end
		elseif d:IsA("BasePart") and d.Name == "Collision" then
			isl += 1
		end
	end
	check(decks >= #CM.outline - 1 and hidden == decks, string.format("甲板碰撞板 %d 块（看不见、挡人）", decks))
	check(isl == 2, "舰岛两个碰撞盒")
else
	print("④ 没导入：照轮廓拼")
	check(cv:GetAttribute("Imported") == false, "没用原模型")
	local vis, isl = 0, false
	for _, d in ipairs(cv:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Deck" and d.Transparency < 1 then vis += 1 end
		if d.Name == "Island" then isl = true end
	end
	check(vis >= #CM.outline - 1, string.format("甲板 %d 块看得见", vis))
	check(isl, "有零件拼的舰岛")
end

print("② 甲板判定照轮廓")
local function W(lx, lz) local p = (base * CF.new(lx, 0, lz)).Position return p.X, p.Z end
check(AirDefs.onDeck(Map, W(0, -290)) == "carrier", "舰艏中间是甲板")
check(AirDefs.onDeck(Map, W(50, -280)) == nil, "舰艏右边（原来长方甲板的角上）是海")
check(AirDefs.onDeck(Map, W(-70, -40)) == "carrier", "斜角甲板往左舷伸出去的地方是甲板")
check(AirDefs.onDeck(Map, W(0, 330)) == nil, "舰尾外面是海")
local x0, z0 = W(70, -280)
check(AirDefs.ground(Map, x0, z0) < 5, string.format("舰艏外面落地高度是海面（%.1f）", AirDefs.ground(Map, x0, z0)))
for i = 1, #AirDefs.CATS do
	local st, dir, len = AirDefs.cat(Map, i)
	local e = st + dir * len
	check(AirDefs.onDeck(Map, st.X, st.Z) == "carrier" and AirDefs.onDeck(Map, e.X - dir.X * 4, e.Z - dir.Z * 4) == "carrier", "弹射器 " .. i .. " 从头到尾都在甲板上")
end
local Wd = AirDefs.WIRES
local zc = (Wd.z0 + Wd.z1) / 2
local wx, wz = W(Wd.x, zc)
check(AirDefs.inWires(Map, wx, wz) and AirDefs.onDeck(Map, wx, wz) == "carrier", "拦阻索区中间在甲板上")
check(not AirDefs.inWires(Map, W(Wd.x + 50, zc)), "拦阻索区右边 50 格不算")

print("③ 停机位、出生点、灯")
local function inLanding(lx, lz, pad)   -- 着舰区（两条红线之间）
	local f1, f2 = CM.foul[1], CM.foul[2]
	local function lineX(f, z) return f[1][1] + (f[2][1] - f[1][1]) * (z - f[1][2]) / (f[2][2] - f[1][2]) end
	local xr, xl = lineX(f1, lz), lineX(f2, lz)
	return lx - pad < xr and lx + pad > xl
end
local nPad = 0
for _, p in ipairs(G.pads or {}) do
	if p.kind == "air" and p.team == "atk" and not p.heli then
		local l = base:PointToObjectSpace(p.base.Position)
		if math.abs(l.Z) < 320 and math.abs(l.X) < 100 then
			nPad += 1
			local half = (p.size and p.size.X or 30) / 2
			check(AirDefs.onDeck(Map, p.base.Position.X, p.base.Position.Z) == "carrier", string.format("停机位 (%.0f, %.0f) 在甲板上", l.X, l.Z))
			check(not inLanding(l.X, l.Z, half), string.format("停机位 (%.0f, %.0f) 不压着舰区（翼展一半 %.0f）", l.X, l.Z, half))
			local I = CM.island.base
			check(not (l.X + half > I[1] and l.Z - 18 < I[4] and l.Z + 18 > I[3]), "停机位不压舰岛")
		end
	end
end
check(nPad == 3, "航母上三个停机位（" .. nPad .. "）")
local okSp = 0
for k = 1, 12 do
	local cf = G.spawnCFOf and G.spawnCFOf({ team = "atk" }, { kind = "cv" })
	if cf then
		local l = base:PointToObjectSpace(cf.Position)
		if AirDefs.onDeck(Map, cf.Position.X, cf.Position.Z) == "carrier" and not inLanding(l.X, l.Z, 2) and l.X < CM.island.base[1] - 2 then okSp += 1 end
	end
end
if G.spawnCFOf then check(okSp == 12, "舰岛旁的出生点都在甲板上、不在着舰区、不在舰岛里（" .. okSp .. " / 12）") end
local nLights = 0
for _, x in ipairs(cv:GetDescendants()) do if x:IsA("BillboardGui") and x.Name == "Glow" then nLights += 1 end end
check(nLights > 60, "甲板上的夜灯 " .. nLights .. " 盏")
local nums = 0
for _, x in ipairs(cv:GetDescendants()) do if x:IsA("TextLabel") and x.Text == "18" then nums += 1 end end
check(nums >= 2, "两舷舷号 18（" .. nums .. "）")

print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
