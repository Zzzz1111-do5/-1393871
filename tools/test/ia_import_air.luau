--!nocheck
-- 飞机原模型测试：假装在 Studio 里导入了 models/air/ 的歼-15、阿帕奇、歼-20（按 ImportedAir 摆同名的 MeshPart 放在 Workspace）→
--   开服收进 ReplicatedStorage.Imported.Air → 客户端拼的飞机用原模型的块（蒙皮去掉，挂架和弹、灯、加力火焰留着）→
--   挂架挂在原模型的机翼下表面、弹挂在下面 → 起落架收放（原模型自带的藏起来；歼-20 v4 的起落架是 j20_gear.py 补的网格，往前收、舱门跟着开关）→
--   歼-15 折翼（外翼、挂的弹、翼尖灯一起绕原模型的铰链转）→ 加力火焰从原模型的尾喷口喷 → 阿帕奇旋翼转 → 所有型号都能拼、摆姿态
--   → 在航母上按 E 弹出挂载编辑器，里面的歼-15T 也是原模型（原来还测直-10 的桨盘，直-10 11-27 删了）
-- 用法（仓库根目录）：lune run tools/test/ia_import_air.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
local Enum = roblox.Enum
H.quietWarn = process.args[2] ~= "v"

local IA = luau.load(fs.readFile("src/ReplicatedStorage/ImportedAir.lua"), { debugName = "ImportedAir" })()
local KEYS = { "j15t", "ah64_v2", "j20_v4", "a10_v3", "tvc", "f22a", "j16_v3", "h6k_v3" }
local function count(t) local n = 0 for _ in pairs(t) do n += 1 end return n end

H.boot(process.args[1], { ds = "mock", before = function(game)
	for _, k in ipairs(KEYS) do
		local m = Inst.new("Model")
		m.Name = "A_" .. k
		for name, p in pairs(IA.m[k].parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "A_" .. k .. "__" .. name
			mp.Size = V3.new(p.s[1], p.s[2], p.s[3])
			mp.CFrame = CF.new(900 + p.c[1], 200 + p.c[2], 900 + p.c[3])
			mp.Anchored = true
			mp.Parent = m
		end
		m.Parent = game:GetService("Workspace")
	end
	-- 导弹合集（models/wpn/missiles.glb）：W_<型号>__Body_1，大小照转换出来的（格）
	local w = Inst.new("Model")
	w.Name = "W_missiles"
	for k, sz in pairs({ aim9x = { 1.85, 1.85, 8.15 }, gbu32 = { 1.4, 1.4, 7.9 }, gbu12 = { 3.3, 3.3, 9.5 }, agm65 = { 2.0, 2.0, 6.9 } }) do
		local mp = Inst.new("MeshPart")
		mp.Name = "W_" .. k .. "__Body_1"
		mp.Size = V3.new(sz[1], sz[2], sz[3])
		mp.Anchored = true
		mp.Parent = w
	end
	w.Parent = game:GetService("ReplicatedStorage")
end })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)

print("① 开服：把导入的飞机原模型收好")
local RS = H.game:GetService("ReplicatedStorage")
for _, k in ipairs(KEYS) do
	local f = RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Air") and RS.Imported.Air:FindFirstChild(k)
	check(f ~= nil and #f:GetChildren() == count(IA.m[k].parts), string.format("Imported.Air.%s 里 %d 块（元数据 %d 块）", k, f and #f:GetChildren() or 0, count(IA.m[k].parts)))
end
check(G.importedAir and #G.importedAir == #KEYS, "服务器记下了：" .. table.concat(G.importedAir or {}, ","))

-- 客户端的 AirModels（按这个玩家的上下文取）
local p1, p2 = H.addPlayer("P1", 7001), H.addPlayer("P2", 7002)
H.run(2)
local atk = (G.P[p1].team == "atk") and p1 or p2
local prev = H.ctx
H.ctx = atk
local AM = H.require(atk.PlayerScripts.Client.AirModels)
local AD = H.require(RS.AirDefs)
H.ctx = prev
local function pose(M, c) AM.pose(M, CF.new(0, 200, 0), c, 0) end
local function rel(p) return CF.new(0, 200, 0):ToObjectSpace(p.CFrame) end

print("② 歼-15T（用户给的「J-15T with YJ-83K」）：蒙皮换成原模型，挂架、弹、灯、火焰、零件拼的起落架留着")
local d = AD.get("j15t")
local load = AD.presetLoad(d, "ag")
local M = AM.build(d, "atk", load)
local I = IA.m.j15t
local meshes, leftover, tags = 0, 0, {}
for _, it in ipairs(M.items) do
	if it.p:IsA("MeshPart") then
		if string.sub(it.p.Name, 1, 8) == "A_j15t__" then meshes += 1 end   -- 推力矢量喷口另算（②b），挂的弹（导弹合集的原模型）不算
	else
		tags[it.tag or it.kind] = (tags[it.tag or it.kind] or 0) + 1
		if not (it.kind == "ab" or it.tag == "lamp" or it.tag == "store" or it.tag == "gear" or it.tag == "pilot") then leftover += 1 end   -- 原模型是收起起落架的样子：起落架零件拼；座舱里没人：飞行员零件拼的挪进座舱
	end
end
local tl = {}
for k, n in pairs(tags) do table.insert(tl, k .. " " .. n) end
table.sort(tl)
check(M.imported == "j15t" and meshes == count(I.parts), string.format("原模型 %d 块全用上（元数据 %d 块）", meshes, count(I.parts)))
check(leftover == 0, "零件拼的只剩挂架和弹、灯、火焰、起落架、飞行员：" .. table.concat(tl, "、") .. "（别的 " .. leftover .. " 个）")
-- 挂架顶贴着原模型的机翼下表面
local O = -d.gearH
local pylOk, pylN = true, 0
for i, adj in pairs(I.pyl.j15t or {}) do
	if load[i] then
		local found = false
		for _, pp in ipairs(M.pylons) do
			local c0 = pp.cf0.Position
			if math.abs(c0.X - adj[3]) < 0.01 and math.abs(c0.Z - adj[2]) < 0.01 then
				found = true
				local top = c0.Y + pp.p.Size.Y / 2
				-- 挂架最短 0.4 格（翼尖导轨挂得浅时顶端伸进翼面里一点，看不见）
				local dy = top - (adj[1] + O)
				if not (math.abs(dy) < 0.05 or (pp.p.Size.Y <= 0.41 and dy > 0 and dy < 0.3)) then pylOk = false end
			end
		end
		if found then pylN += 1 else pylOk = false end
	end
end
check(pylOk and pylN > 0, string.format("%d 个挂架顶贴着原模型的机翼下表面", pylN))
-- 弹挂在挂架下面（每个挂点的弹按零件的平均高度算：弹翼会高出弹体一点）
local stOk, stN = true, 0
for i, list in pairs(M.stores) do
	local adj = I.pyl.j15t and I.pyl.j15t[i]
	if adj and #list > 0 then
		stN += 1
		local y = 0
		for _, it in ipairs(list) do y += it.cf0.Position.Y end
		if y / #list > adj[1] + O then stOk = false end
	end
end
check(stOk and stN > 0, string.format("%d 个挂点的弹都挂在翼下表面以下", stN))
-- 起落架：原模型是收起的样子，用零件拼的（放下、收起会动）
local gN = 0
for _, it in ipairs(M.items) do if it.tag == "gear" then gN += 1 end end
pose(M, { gear = 1, fold = 0, thr = 50 })
local gq1
for _, it in ipairs(M.items) do if it.tag == "gear" then gq1 = rel(it.p) break end end
pose(M, { gear = 0, fold = 0, thr = 50 })
local gq0
for _, it in ipairs(M.items) do if it.tag == "gear" then gq0 = rel(it.p) break end end
check(I.gear == false and gN > 0 and gq1 and gq0 and (gq1.Position - gq0.Position).Magnitude > 0.5, string.format("零件拼的起落架 %d 个零件，收放会动", gN))
-- 折翼：外翼、外侧挂的弹、右翼尖灯一起绕原模型的铰链转
local wing, store, lampR
for _, it in ipairs(M.items) do
	if it.p:IsA("MeshPart") and string.find(it.p.Name, "__FoldR_") and not wing then wing = it.p end
	if it.st and it.fold == 1 and not store then store = it.p end
	if it.lamp == "nav" and it.fold == 1 and not lampR then lampR = it.p end
end
pose(M, { gear = 1, fold = 0 })
local w0, s0, l0 = rel(wing), store and rel(store), lampR and rel(lampR)
pose(M, { gear = 1, fold = 1 })
local w1, s1, l1 = rel(wing), store and rel(store), lampR and rel(lampR)
check(w1.Position.Y > w0.Position.Y + 3 and w1.Position.X < w0.Position.X, string.format("折翼：右外翼抬起 %.1f 格、往里收 %.1f 格", w1.Position.Y - w0.Position.Y, w0.Position.X - w1.Position.X))
local keep = store and ((w0:ToObjectSpace(s0)).Position - (w1:ToObjectSpace(s1)).Position).Magnitude < 0.01
check(keep, "外侧挂的弹跟着外翼一起转（相对外翼不动）")
check(lampR and ((w0:ToObjectSpace(l0)).Position - (w1:ToObjectSpace(l1)).Position).Magnitude < 0.01, "右翼尖航行灯跟着外翼一起转")
check(lampR and math.abs(l0.Position.X - (I.tip[1] + 0.2)) < 0.05, string.format("右翼尖航行灯在原模型翼尖外 0.2 格（x %.2f，翼尖 %.2f）", l0 and l0.Position.X or 0, I.tip[1]))
-- 加力火焰从原模型的尾喷口喷
local flOk = #M.flames > 0
for _, it in ipairs(M.flames) do
	local p = it.base.Position
	local near = false
	for _, nz in ipairs(I.noz) do
		-- 装了推力矢量喷口：火焰从它的出口喷（原模型喷口正后方）
		local q = p - V3.new(nz[1], nz[2] + O, nz[3])
		if math.abs(q.X) < 0.01 and math.abs(q.Y) < 0.01 and q.Z > -0.01 and q.Z < 4 then near = true end
	end
	if not near then flOk = false end
end
check(flOk, string.format("%d 个火焰零件都在原模型的尾喷口正后方（推力矢量喷口的出口，%d 个）", #M.flames, #I.noz))

print("②b 推力矢量喷口（用户给的 F-15 SE Thrust Vector Nozzle）：两个尾喷口各一只，加力时调节片张开，抬头时出口往上，火焰跟着偏")
do
	check(#M.tvc == 2 * count(IA.m.tvc.parts), string.format("推力矢量喷口 %d 块（两只 × %d）", #M.tvc, count(IA.m.tvc.parts)))
	local pet, fl
	for _, it in ipairs(M.tvc) do if it.petal and not pet then pet = it end end
	for _, it in ipairs(M.flames) do if not it.ring and not fl then fl = it end end
	local function axisDist(it)   -- 这片离喷口轴线多远（同一只喷口的调节片中心）
		local q = rel(it.p).Position
		local best = math.huge
		for _, nz in ipairs(I.noz) do best = math.min(best, math.sqrt((q.X - nz[1]) ^ 2 + (q.Y - (nz[2] - d.gearH)) ^ 2)) end
		return best
	end
	pose(M, { gear = 0, thr = 90, pit = 0 })
	local r0, y0, f0 = pet and axisDist(pet), pet and rel(pet.p).Position.Y, fl and rel(fl.p).Position.Y
	pose(M, { gear = 0, thr = 130, pit = 0 })
	local r1 = pet and axisDist(pet)
	check(pet and r1 > r0 + 0.05, string.format("开加力：调节片往外张（离轴线 %.2f → %.2f 格）", r0 or 0, r1 or 0))
	pose(M, { gear = 0, thr = 90, pit = 1 })
	local y1, f1 = pet and rel(pet.p).Position.Y, fl and rel(fl.p).Position.Y
	check(pet and y1 > y0 + 0.1 and fl and f1 > f0 + 0.1, string.format("拉杆抬头：喷口出口往上偏（调节片 +%.2f 格，火焰 +%.2f 格）", (y1 or 0) - (y0 or 0), (f1 or 0) - (f0 or 0)))
end

print("③ 阿帕奇：旋翼、尾桨转；挂的弹在原模型短翼下面")
local dh = AD.get("ah64e")
local lh = AD.presetLoad(dh, "at")
local MH = AM.build(dh, "def", lh)
check(MH.imported == "ah64_v2", "用的是原模型（拆出了机炮的 v2）")
local rotor, trotor
for _, it in ipairs(MH.items) do
	if it.p:IsA("MeshPart") and string.find(it.p.Name, "__Rotor_") and not rotor then rotor = it end
	if it.p:IsA("MeshPart") and string.find(it.p.Name, "__TRotor_") and not trotor then trotor = it end
end
pose(MH, { gear = 1, spin1 = 0, spinT = 0, rpm = 100 })
local r0, t0 = rel(rotor.p), rel(trotor.p)
pose(MH, { gear = 1, spin1 = 1.0, spinT = 1.0, rpm = 100 })
local r1, t1 = rel(rotor.p), rel(trotor.p)
local hub = rotor.hub.Position
local dist0, dist1 = (V3.new(r0.Position.X, 0, r0.Position.Z) - V3.new(hub.X, 0, hub.Z)).Magnitude, (V3.new(r1.Position.X, 0, r1.Position.Z) - V3.new(hub.X, 0, hub.Z)).Magnitude
local turned = select(2, r0:ToObjectSpace(r1):ToAxisAngle())
check(math.abs(turned - 1.0) < 0.02 and math.abs(dist0 - dist1) < 0.01, string.format("主旋翼绕桨毂转了 %.2f 弧度", turned))
check((t0.Position - t1.Position).Magnitude > 0.001 or select(2, t0:ToObjectSpace(t1):ToAxisAngle()) > 0.5, "尾桨转了")
-- 机头炮塔（用户 11-21：直升机炮管不会转动）：原模型拆出来的炮跟着方位、俯仰转，炮塔座只转方位
local gunIt, gunY
for _, it in ipairs(MH.items) do
	if string.find(it.p.Name, "__Gun_") then gunIt = it end
	if string.find(it.p.Name, "__GunY_") then gunY = it end
end
check(gunIt ~= nil and gunIt.kind == "t" and gunY ~= nil and gunY.yawOnly, "机炮、炮塔座是单独的炮塔件")
if gunIt and gunY then
	pose(MH, { gear = 1, ty = 0, gp = 0 })
	local g0, y0 = rel(gunIt.p), rel(gunY.p)
	pose(MH, { gear = 1, ty = 60, gp = -20 })
	local g1, y1 = rel(gunIt.p), rel(gunY.p)
	local _, ga = g0:ToObjectSpace(g1):ToAxisAngle()
	check(ga > math.rad(50), string.format("方位 60°、俯仰 −20°：炮转了 %.0f°", math.deg(ga)))
	check(g1.Position.X > g0.Position.X + 0.5, "炮口转到右边")
	local yl = y0:ToObjectSpace(y1).LookVector
	check(math.abs(yl.Y) < 0.01, "炮塔座不跟着俯仰")
end
local lowOk, lowN = true, 0
for i, list in pairs(MH.stores) do
	local adj = IA.m.ah64_v2.pyl.ah64e and IA.m.ah64_v2.pyl.ah64e[i]
	if #list > 0 and dh.st[i].name ~= "tip" then   -- 翼尖的毒刺挂在翼尖导轨上（不在翼下）
		lowN += 1
		local y = 0
		for _, it in ipairs(list) do y += it.cf0.Position.Y end
		if not adj or y / #list > adj[1] - dh.gearH then lowOk = false end
	end
end
check(lowOk and lowN > 0, string.format("%d 个挂点的弹都挂在原模型短翼下表面以下", lowN))

-- ③b 原来测直-10 原模型自带的「转起来的桨盘」（AirModels 的 BLUR）：直-10 11-27 删了（原模型是扒的），现在没有带桨盘的模型

print("④ 歼-20（j20_v4）：原模型不减面；起落架是 tools/models/j20_gear.py 补的网格（关键帧往前收），起落架舱门跟着开关；零件拼的起落架不画了")
local dj = AD.get("j20")
local MJ = AM.build(dj, "atk", AD.presetLoad(dj, "aa"))
local gearN = 0
for _, it in ipairs(MJ.items) do if it.tag == "gear" then gearN += 1 end end
check(MJ.imported == "j20_v4" and gearN == 0, string.format("用的是 %s，零件拼的起落架 %d 个零件（应该没有）", tostring(MJ.imported), gearN))
-- 绿色编队灯带（用户 11-18：歼-20 改得跟现实的一样，包括绿色光条；v4 也照 airpaint.py 重涂过）：元数据 glow 的那几块是 Neon、绿色，不带贴图
do
	local gl = IA.m.j20_v4.glow or {}
	local want, ok = count(gl), 0
	for _, it in ipairs(MJ.items) do
		local nm = it.p and it.p:IsA("MeshPart") and string.match(it.p.Name, "__(.+)$")
		if nm and gl[nm] and it.p.Material == Enum.Material.Neon and it.p.Color.G > 0.9 then ok += 1 end
	end
	check(want >= 4 and ok == want, string.format("绿色灯带 %d / %d 块发光（Neon）", ok, want))
end
-- 侧弹舱、起落架舱（用户：侧弹仓打开为什么能看穿飞机）：tools/models/doorbay.py 做的舱 Well_1…5 画出来、深灰色
do
	local n, dark, nd = 0, 0, 0
	for _, it in ipairs(MJ.items) do
		local nm = it.p and string.match(it.p.Name, "^A_j20_v4__(Well_%d+)$")
		if nm then
			n += 1
			if it.p.Color.R < 0.3 and it.p.Color.G < 0.3 then dark += 1 end
		end
		local dn = it.p and string.match(it.p.Name, "^A_j20_v4__(Duct_%d+)$")
		if dn and it.p.Color.R < 0.2 then nd += 1 end
	end
	check(n == 5 and dark == 5, string.format("舱门里封好的舱 %d 个（深灰 %d 个，应该 5 个）", n, dark))
	-- 进气道（用户：从前下方能从进气道口看穿）：唇口后面补的深色管道，两边各一个
	check(nd == 2, string.format("进气道里深色的管道 %d 个（应该 2 个）", nd))
end
local function partsOf(g)
	local list = {}
	for _, it in ipairs(MJ.items) do
		local nm = it.p and string.match(it.p.Name, "^A_j20_v4__(.+)$")
		local p = nm and IA.m.j20_v4.parts[nm]
		if p and p.g == g then table.insert(list, it) end
	end
	return list
end
local function center(list)
	if #list == 0 then return nil end
	local s = V3.new(0, 0, 0)
	for _, it in ipairs(list) do s += rel(it.p).Position end
	return s / #list
end
local GL, DN = partsOf("GearL"), partsOf("GDoorN1")
pose(MJ, { gear = 1 })
local c1, dn1 = center(GL), center(DN)
pose(MJ, { gear = 0.25 })
local cq = center(GL)
pose(MJ, { gear = 0 })
local c0, dn0 = center(GL), center(DN)
check(c1 and c0 and c0.Y - c1.Y > 2 and c0.Z < c1.Z - 2,
	string.format("收起落架：左主起落架往前 %.1f 格、往上 %.1f 格收进机身（%d 块）", c1 and c0 and (c1.Z - c0.Z) or 0, c1 and c0 and (c0.Y - c1.Y) or 0, #GL))
check(cq and c0 and (cq - c0).Magnitude < 0.05, "操纵量 0.25 时支柱已经收到底（之后舱门才关）")
check(dn1 and dn0 and dn1.Y < dn0.Y - 0.3, string.format("前起落架舱门：放下时往下开（%.2f 格），收起时关上", dn1 and dn0 and (dn1.Y - dn0.Y) or 0))

print("④b A-10：原模型是收起起落架的样子（「起落架」那几块其实是蒙皮）→ 当蒙皮一直画、整架抬高、用零件拼的起落架（用户：部分飞机没有起落架）")
do
	local da = AD.get("a10c")
	local MA = AM.build(da, "def", AD.presetLoad(da))
	local gN, fake, fakeShown = 0, 0, 0
	for _, it in ipairs(MA.items) do if it.tag == "gear" then gN += 1 end end
	pose(MA, { gear = 0 })
	for _, it in ipairs(MA.items) do
		if it.p:IsA("MeshPart") and string.find(it.p.Name, "__Gear_") then
			fake += 1
			if it.p.Transparency < 1 then fakeShown += 1 end
		end
	end
	check(MA.imported == "a10_v3" and gN > 0, string.format("原模型 + 零件拼的起落架 %d 个零件", gN))
	check(fake > 0 and fakeShown == fake, string.format("收起落架时原模型那 %d 块「起落架」照样看得见（是蒙皮）", fake))
	MA.model:Destroy()
end

print("④d 歼-16 的绿色灯带（模型里没有：贴在量出来的蒙皮位置）、H-6 / A-10 的发动机堵头（从后往前看不再是空的）")
do
	local function neonN(M)
		local n = 0
		for _, it in ipairs(M.items) do if it.p and it.p:IsA("Part") and it.p.Material == Enum.Material.Neon and it.p.Color.G > 0.9 and it.p.Size.Y <= 0.06 then n += 1 end end
		return n
	end
	local d16 = AD.get("j16")
	local M16 = AM.build(d16, "atk", AD.presetLoad(d16))
	check(M16.imported == "j16_v3" and neonN(M16) == #(IA.m.j16_v3.strips or {}) and neonN(M16) >= 4, string.format("歼-16：灯带 %d 条（元数据 %d 条）", neonN(M16), #(IA.m.j16_v3.strips or {})))
	M16.model:Destroy()
	for _, pair in ipairs({ { "h6k", "h6k_v3" }, { "a10c", "a10_v3" } }) do
		local dd = AD.get(pair[1])
		local MM = AM.build(dd, "def", AD.presetLoad(dd))
		local plugs = 0
		for _, it in ipairs(MM.items) do if it.p and it.p:IsA("Part") and it.p.Shape == Enum.PartType.Cylinder and it.p.Color.R < 0.15 and it.p.Size.X < 0.2 then plugs += 1 end end
		local want = #(IA.m[pair[2]].plugs or {})
		check(MM.imported == pair[2] and want >= 2 and plugs >= want, string.format("%s：发动机堵头 %d 个（元数据 %d 个）", pair[1], plugs, want))
		MM.model:Destroy()
	end
end

print("④c F-22A（用户给的带动画的「F22 Raptor FREE」）：原模型动画里的起落架、舱门、侧弹舱照关键帧动；主弹舱门、舵面、座舱盖绕铰链转")
do
	local df = AD.get("f22")
	local MF = AM.build(df, "def", AD.presetLoad(df))
	local gN, meshes = 0, 0
	for _, it in ipairs(MF.items) do
		if it.tag == "gear" then gN += 1 end
		if it.p:IsA("MeshPart") and string.sub(it.p.Name, 1, 8) == "A_f22a__" then meshes += 1 end   -- 不算挂的弹（导弹合集的原模型）
	end
	check(MF.imported == "f22a" and gN == 0 and meshes == count(IA.m.f22a.parts), string.format("原模型 %d 块全用上（元数据 %d 块），不用零件拼的起落架（%d）", meshes, count(IA.m.f22a.parts), gN))
	-- 一组部件（名字里有 __<组>_）的包围盒最低点、中心（机体坐标）
	local function grp(pat)
		local lo, sum, n = math.huge, V3.new(0, 0, 0), 0
		for _, it in ipairs(MF.items) do
			if it.p:IsA("MeshPart") and string.find(it.p.Name, "__" .. pat) then
				local cf, h = rel(it.p), it.p.Size / 2
				for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
					lo = math.min(lo, (cf * V3.new(sx * h.X, sy * h.Y, sz * h.Z)).Y)
				end end end
				sum += cf.Position
				n += 1
			end
		end
		return lo, n > 0 and sum / n or nil, n
	end
	pose(MF, { gear = 1 })
	local loM = math.min((grp("GearL_")), (grp("GearR_")))
	local loN = (grp("GearN_"))
	local ground = -df.gearH
	check(math.abs(loM - ground) < 0.6 and math.abs(loN - ground) < 0.8, string.format("放下起落架：主轮最低 %.2f、前轮最低 %.2f 格，地面 %.2f（gearH %.2f）", loM, loN, ground, df.gearH))
	local _, cD = grp("GDoor3L_")
	pose(MF, { gear = 0 })
	local loM0 = math.min((grp("GearL_")), (grp("GearR_")))
	local _, cU = grp("GDoor3L_")
	check(loM0 > loM + 1.5, string.format("收起落架：主轮收上去了（最低点 %.2f → %.2f）", loM, loM0))
	check(cD and cU and (cD - cU).Magnitude > 0.5, string.format("起落架舱门跟着关上（挪了 %.2f 格）", cD and cU and (cD - cU).Magnitude or -1))
	pose(MF, { gear = 0, bay = 0, bayS = 0 })
	local _, b0 = grp("BayML_")
	local _, s0 = grp("BayS1L_")
	local _, t0 = grp("BayS3L_")
	pose(MF, { gear = 0, bay = 1, bayS = 1 })
	local lb, b1 = grp("BayML_")
	local _, s1 = grp("BayS1L_")
	local _, t1 = grp("BayS3L_")
	check(b0 and b1 and b1.Y < b0.Y - 0.5, string.format("主弹舱门往下翻开（中心 %.2f → %.2f）", b0 and b0.Y or 0, b1 and b1.Y or 0))
	check(s0 and s1 and (s1 - s0).Magnitude > 0.5 and t0 and t1 and (t1 - t0).Magnitude > 0.1, string.format("侧弹舱门打开、发射架伸出（门 %.2f、发射架 %.2f 格）", s0 and s1 and (s1 - s0).Magnitude or -1, t0 and t1 and (t1 - t0).Magnitude or -1))
	pose(MF, { gear = 0, yaw = 0 })
	local _, r0 = grp("RudL_")
	pose(MF, { gear = 0, yaw = 1 })
	local _, r1 = grp("RudL_")
	check(r0 and r1 and (r1 - r0).Magnitude > 0.2, string.format("方向舵跟着偏航动（%.2f 格）", r0 and r1 and (r1 - r0).Magnitude or -1))
	pose(MF, { gear = 0, can = 0 })
	local _, c0 = grp("Canopy_")
	pose(MF, { gear = 0, can = 1 })
	local _, c1 = grp("Canopy_")
	check(c0 and c1 and c1.Y > c0.Y + 0.5, string.format("座舱盖往上掀（中心 %.2f → %.2f）", c0 and c0.Y or 0, c1 and c1.Y or 0))
	MF.model:Destroy()
end

print("④d 导弹合集（用户给的 Missile & Bomb Collection）：导入了的型号挂在飞机上、飞出去都用原模型，按弹长等比缩放")
do
	local RS2 = H.game:GetService("ReplicatedStorage")
	local wf = RS2:FindFirstChild("Imported") and RS2.Imported:FindFirstChild("Wpn")
	check(wf and wf:FindFirstChild("aim9x") and wf:FindFirstChild("gbu32") and not RS2:FindFirstChild("W_missiles"), "开服收进 Imported.Wpn.<型号>（外面包着的 Model 删掉了）")
	local prev2 = H.ctx
	H.ctx = atk
	local WMc = H.require(RS2.WeaponModels)
	H.ctx = prev2
	local s9 = WMc.spec(AD.W.aim9x, false)
	check(#s9 == 1 and s9[1].t == "mesh" and math.abs(s9[1].size.Z - AD.W.aim9x.shape.L) < 0.01, string.format("AIM-9X 用原模型，缩放到弹长 %.2f 格（%s）", AD.W.aim9x.shape.L, tostring(s9[1] and s9[1].size)))
	local s38 = WMc.spec(AD.W.gbu38, true)
	check(#s38 == 1 and s38[1].t == "mesh" and s38[1].src.Name == "W_gbu32__Body_1" and math.abs(s38[1].size.Z - AD.W.gbu38.shape.L) < 0.01, "GBU-38 借 GBU-32 的模型缩小")
	local sp = WMc.spec(AD.W.pl15, false)
	check(#sp > 3 and sp[1].t ~= "mesh", string.format("没导入的（霹雳-15）照旧零件拼（%d 个零件）", #sp))
	local df = AD.get("f22")
	local MF = AM.build(df, "def", AD.presetLoad(df))
	local nW = 0
	for _, it in ipairs(MF.items) do
		if it.tag == "store" and it.p:IsA("MeshPart") and it.p.Name == "W_aim9x__Body_1" then nW += 1 end
	end
	check(nW > 0, string.format("F-22 侧弹舱里的 AIM-9X 是原模型（%d 枚）", nW))
	MF.model:Destroy()
end

print("⑤ 所有型号都能拼、摆姿态（没导入的照旧零件拼）")
local bad = {}
for id, dd in pairs(AD.D) do
	local ok, err = pcall(function()
		local MM = AM.build(dd, "atk", AD.presetLoad(dd))
		for _, c in ipairs({ { gear = 1, fold = 1, bay = 1, bayS = 1, thr = 120, spin1 = 1, spin2 = 2, spinT = 3, rpm = 100 }, { gear = 0, fold = 0, thr = 60 } }) do pose(MM, c) end
		MM.model:Destroy()
	end)
	if not ok then table.insert(bad, id .. "：" .. tostring(err)) end
end
check(#bad == 0, "全部能拼" .. ((#bad > 0) and ("，出错：" .. table.concat(bad, "；")) or ""))

print("⑥ 航母上按 E：挂载编辑器里的歼-15T 也是原模型")
local CA = H.Gs[atk.Name]
local function act(pl, ...)
	local a = table.pack(...)
	local prv = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prv
end
act(atk, "deploy", "rifle", "cv")
H.run(2)
local jp = H.pad(G, "j15t")
if jp then H.usePad(G, atk, jp) end
local HS = CA.hangarState and CA.hangarState()
check(HS and HS.M and HS.M.imported == "j15t", "挂载编辑器里是原模型（" .. tostring(HS and HS.M and HS.M.imported) .. "）")

H.summary()
for i, w in ipairs(H.warns) do if i <= 6 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
