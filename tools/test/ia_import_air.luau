--!nocheck
-- 飞机原模型测试：假装在 Studio 里导入了 models/air/ 的歼-15、阿帕奇、歼-20（按 ImportedAir 摆同名的 MeshPart 放在 Workspace）→
--   开服收进 ReplicatedStorage.Imported.Air → 客户端拼的飞机用原模型的块（蒙皮去掉，挂架和弹、灯、加力火焰留着）→
--   挂架挂在原模型的机翼下表面、弹挂在下面 → 起落架收放（原模型自带的藏起来；没带的歼-20 用零件拼的）→
--   歼-15 折翼（外翼、挂的弹、翼尖灯一起绕原模型的铰链转）→ 加力火焰从原模型的尾喷口喷 → 阿帕奇旋翼转 → 所有型号都能拼、摆姿态
--   → 直-10 原模型自带的「转起来的桨盘」停着不显示、转快了才出现 → 在航母上按 E 弹出挂载编辑器，里面的歼-15T 也是原模型
-- 用法（仓库根目录）：lune run tools/test/ia_import_air.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = process.args[2] ~= "v"

local IA = luau.load(fs.readFile("src/ReplicatedStorage/ImportedAir.lua"), { debugName = "ImportedAir" })()
local KEYS = { "j15", "ah64", "j20", "z10w" }
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

print("② 歼-15T：蒙皮换成原模型，挂架、弹、灯、火焰留着")
local d = AD.get("j15t")
local load = AD.presetLoad(d, "ag")
local M = AM.build(d, "atk", load)
local I = IA.m.j15
local meshes, leftover, tags = 0, 0, {}
for _, it in ipairs(M.items) do
	if it.p:IsA("MeshPart") then meshes += 1
	else
		tags[it.tag or it.kind] = (tags[it.tag or it.kind] or 0) + 1
		if not (it.kind == "ab" or it.tag == "lamp" or it.tag == "store") then leftover += 1 end
	end
end
local tl = {}
for k, n in pairs(tags) do table.insert(tl, k .. " " .. n) end
table.sort(tl)
check(M.imported == "j15" and meshes == count(I.parts), string.format("原模型 %d 块全用上（元数据 %d 块）", meshes, count(I.parts)))
check(leftover == 0, "零件拼的只剩挂架和弹、灯、火焰：" .. table.concat(tl, "、") .. "（别的 " .. leftover .. " 个）")
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
-- 起落架：原模型自带的，放下看得见，收起藏起来
pose(M, { gear = 1, fold = 0, thr = 50 })
local function gearVis()
	local vis, n = 0, 0
	for _, it in ipairs(M.items) do
		if it.p:IsA("MeshPart") and string.find(it.p.Name, "__Gear_") then
			n += 1
			if it.p.Transparency < 1 then vis += 1 end
		end
	end
	return vis, n
end
local v1, n1 = gearVis()
pose(M, { gear = 0, fold = 0, thr = 50 })
local v0 = gearVis()
check(n1 > 0 and v1 == n1 and v0 == 0, string.format("起落架 %d 块：放下 %d 块看得见，收起 %d 块", n1, v1, v0))
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
		if (p - V3.new(nz[1], nz[2] + O, nz[3])).Magnitude < 0.01 then near = true end
	end
	if not near then flOk = false end
end
check(flOk, string.format("%d 个火焰零件都在原模型的尾喷口（%d 个）", #M.flames, #I.noz))

print("③ 阿帕奇：旋翼、尾桨转；挂的弹在原模型短翼下面")
local dh = AD.get("ah64e")
local lh = AD.presetLoad(dh, "at")
local MH = AM.build(dh, "def", lh)
check(MH.imported == "ah64", "用的是原模型")
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
local lowOk, lowN = true, 0
for i, list in pairs(MH.stores) do
	local adj = IA.m.ah64.pyl.ah64e and IA.m.ah64.pyl.ah64e[i]
	if #list > 0 and dh.st[i].name ~= "tip" then   -- 翼尖的毒刺挂在翼尖导轨上（不在翼下）
		lowN += 1
		local y = 0
		for _, it in ipairs(list) do y += it.cf0.Position.Y end
		if not adj or y / #list > adj[1] - dh.gearH then lowOk = false end
	end
end
check(lowOk and lowN > 0, string.format("%d 个挂点的弹都挂在原模型短翼下表面以下", lowN))

print("③b 直-10：原模型自带的「转起来的桨盘」停着不显示，转快了才淡淡地出现、桨叶变虚")
do
	local dz = AD.get("z10")
	local MZ = AM.build(dz, "atk", AD.presetLoad(dz))
	local discs, blades = {}, {}
	for _, it in ipairs(MZ.items) do
		if it.p:IsA("MeshPart") then
			local nm = string.match(it.p.Name, "__(.+)$")
			if nm == "Rotor_2" or nm == "TRotor_2" then table.insert(discs, it.p) elseif nm == "Rotor_1" or nm == "TRotor_1" then table.insert(blades, it.p) end
		end
	end
	local function tr(list) local a = {} for _, p in ipairs(list) do table.insert(a, p.Transparency) end return a end
	pose(MZ, { gear = 1, rpm = 0 })   -- 挂载编辑器里就是这样摆的
	local d0, b0 = tr(discs), tr(blades)
	pose(MZ, { gear = 1, spin1 = 2, spinT = 3, rpm = 100 })
	local d1, b1 = tr(discs), tr(blades)
	check(MZ.imported == "z10w" and #discs == 2 and #blades == 2, string.format("原模型：桨盘 %d 块、桨叶 %d 块", #discs, #blades))
	check(#discs == 2 and d0[1] == 1 and d0[2] == 1 and b0[1] == 0 and b0[2] == 0, string.format("停着：桨盘藏起来（%s），桨叶实心（%s）", table.concat(d0, " / "), table.concat(b0, " / ")))
	check(#discs == 2 and d1[1] < 1 and d1[2] < 1 and b1[1] > 0, string.format("转快了：桨盘出现（透明 %s），桨叶变虚（%s）", table.concat(d1, " / "), table.concat(b1, " / ")))
	MZ.model:Destroy()
end

print("④ 歼-20：原模型没放起落架，用零件拼的起落架（会收放）")
local dj = AD.get("j20")
local MJ = AM.build(dj, "atk", AD.presetLoad(dj, "aa"))
local gearN = 0
for _, it in ipairs(MJ.items) do if it.tag == "gear" then gearN += 1 end end
check(MJ.imported == "j20" and gearN > 0, string.format("原模型 + 零件拼的起落架 %d 个零件", gearN))
pose(MJ, { gear = 1 })
local g1
for _, it in ipairs(MJ.items) do if it.tag == "gear" then g1 = rel(it.p) break end end
pose(MJ, { gear = 0 })
local g0
for _, it in ipairs(MJ.items) do if it.tag == "gear" then g0 = rel(it.p) break end end
check(g1 and g0 and (g1.Position - g0.Position).Magnitude > 0.5, "收起落架时零件拼的起落架收进去了")

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
check(HS and HS.M and HS.M.imported == "j15", "挂载编辑器里是原模型（" .. tostring(HS and HS.M and HS.M.imported) .. "）")

H.summary()
for i, w in ipairs(H.warns) do if i <= 6 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
