--!nocheck
-- 原模型测试：假装在 Studio 里导入了 models/veh/m1a2v3.glb（按 ImportedMeta 摆一套同名的 MeshPart 放在 Workspace）→
--   开服时收进 ReplicatedStorage.Imported.Veh → 守方生成 M1A2、坐进去 → 客户端用的是原模型的块（不是零件拼的）、真实尺寸 →
--   炮塔、炮管按原模型的转轴转，车轮跟着转、有悬架 → 开炮：炮弹从原模型的炮口出去 → 打爆后贴图去掉、烧黑
-- 用法（仓库根目录）：lune run tools/test/ia_import.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Enum, Inst = roblox.Vector3, roblox.CFrame, roblox.Enum, roblox.Instance
H.quietWarn = process.args[2] ~= "v"

local IM = luau.load(fs.readFile("src/ReplicatedStorage/ImportedMeta.lua"), { debugName = "ImportedMeta" })()
local KEY = "m1a2v3"
local info = IM.m[KEY]
local nParts = 0
for _ in pairs(info.parts) do nParts += 1 end
local KEYS = { KEY, "jltv", "ztq15" }   -- JLTV 原模型没有贴图（只有材质颜色）：看游戏里有没有照原色上色；ZTQ-15 是 Sketchfab 上的扫描模型（tools/models/sfveh.py）

H.boot(process.args[1], { ds = "mock", before = function(game)
	-- Studio「导入 3D」的样子：一个 Model 里一堆 MeshPart（导入时放在 Workspace，位置随便；不带材质颜色、没有贴图）
	for _, k in ipairs(KEYS) do
		local m = Inst.new("Model")
		m.Name = "V_" .. k
		for name, p in pairs(IM.m[k].parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "V_" .. k .. "__" .. name
			mp.Size = V3.new(p.s[1], p.s[2], p.s[3])
			mp.CFrame = CF.new(500 + p.c[1], 100 + p.c[2], 500 + p.c[3])
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
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)

print("① 开服：把导入的原模型收好")
local RS = H.game:GetService("ReplicatedStorage")
local folder = RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Veh") and RS.Imported.Veh:FindFirstChild(KEY)
check(folder ~= nil and #folder:GetChildren() == nParts, string.format("ReplicatedStorage.Imported.Veh.%s 里 %d 块（元数据 %d 块）", KEY, folder and #folder:GetChildren() or 0, nParts))
check(H.workspace:FindFirstChild("V_" .. KEY) == nil, "Workspace 里导入时的空 Model 删掉了")
check(G.importedVeh and table.find(G.importedVeh, KEY) ~= nil and table.find(G.importedVeh, "jltv") ~= nil and table.find(G.importedVeh, "ztq15") ~= nil, "服务器记下了：" .. table.concat(G.importedVeh or {}, ","))

print("② 守方生成 M1A2、坐进去")
local p1, p2 = H.addPlayer("P1", 6001), H.addPlayer("P2", 6002)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local PD = G.P[def]
local CD = H.Gs[def.Name]
CD.deploySel.spawn, CD.deploySel.role = "camp", "engineer"
CD.refreshDeploy()
H.click(def, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
-- 先生成一辆 JLTV（不上车）：看客户端拼的样子
local tj = H.pad(G, "jltv")
local ej = tj and H.usePad(G, def, tj)
H.run(1)
local vj = nil
for em, vv in pairs(CD.views) do if ej and em == ej.model then vj = vv end end
local nCol, okCol = 0, vj ~= nil and vj.M.imported == "jltv"
if vj then
	for _, it in ipairs(vj.M.parts) do
		local p = it[1]:IsA("MeshPart") and IM.m.jltv.parts[string.match(it[1].Name, "__(.+)$") or ""]
		if p and p.col then
			nCol += 1
			local c = it[1].Color
			if math.abs(c.R * 255 - p.col[1]) > 1 or math.abs(c.G * 255 - p.col[2]) > 1 or math.abs(c.B * 255 - p.col[3]) > 1 then okCol = false end
		end
	end
end
check(okCol and nCol > 40, string.format("JLTV 用原模型、没贴图的 %d 块照原材质颜色上了色（生成点 %s，车 %s，样子 %s）", nCol, tostring(tj and tj.id), tostring(ej and ej.id), tostring(vj and vj.M.imported)))
check(vj and #vj.M.wheels >= 4, "JLTV 原模型车轮和车身是一整块：照型号表的轮位放了 " .. (vj and #vj.M.wheels or 0) .. " 个看不见的弹簧（车身照样随地面起伏）")
-- ZTQ-15（Sketchfab 上的手机扫描模型）：客户端直接拼一辆看——车体、炮塔、炮管拆开了，炮塔转轴、炮口照原模型
do
	local prev = H.ctx
	H.ctx = def
	local VM = H.require(def.PlayerScripts.Client.VehModels)
	local VD = H.require(RS.VehDefs)
	H.ctx = prev
	local d15, i15 = VD.get("ztq15"), IM.m.ztq15
	local Mz = VM.build(d15, "atk")
	local n15, nT, nG, front = 0, 0, 0, 1e9
	for _ in pairs(i15.parts) do n15 += 1 end
	local cnt = 0
	for _, it in ipairs(Mz.parts) do
		if it[1]:IsA("MeshPart") then
			cnt += 1
			if it[2] == "turret" then nT += 1 end
			if it[2] == "gun" then   -- 贴图分了块，炮管也按贴图分成几块：取最前面的
				nG += 1
				front = math.min(front, it[3].Position.Z - it[1].Size.Z / 2)
			end
		end
	end
	check(Mz.imported == "ztq15" and cnt == n15 and nT >= 1 and nG >= 1, string.format("ZTQ-15 用 Sketchfab 的扫描模型：%d / %d 块，炮塔 %d、炮 %d", cnt, n15, nT, nG))
	check(#Mz.wheels == 2 * d15.rw.n, string.format("扫描的车轮和车身是一整块：照型号表放了 %d 个看不见的弹簧", #Mz.wheels))
	check((d15.turret.pivot - V3.new(i15.tur[1], i15.tur[2], i15.tur[3])).Magnitude < 1e-3 and math.abs(d15.gun.len - i15.muz) < 1e-3,
		string.format("型号表的炮塔转轴、炮口照扫描模型（转轴高 %.1f 格，炮口离耳轴 %.1f 格）", d15.turret.pivot.Y, d15.gun.len))
	-- 炮管的最前端就是炮口（相对炮耳轴往前 muz 格）
	check(nG >= 1 and math.abs(front + i15.muz) < 0.05, string.format("炮管最前端在耳轴前 %.2f 格（元数据 %.2f）", -front, i15.muz))
	Mz.model:Destroy()
	-- 没导入原模型的型号（这里没假装导入斯特赖克）：零件拼的炮塔按型号表原来的转轴摆，坐在车体顶上——
	--   型号表的转轴照原模型改过（高 2 格），零件拼的要是也按它摆，炮塔就悬在车体上面
	local ds = VD.get("stryker")
	local Ms = VM.build(ds, "def")
	local lowT = 1e9
	for _, it in ipairs(Ms.parts) do
		if it[2] == "turret" then lowT = math.min(lowT, (Ms.tpiv or ds.turret.pivot).Y + it[3].Position.Y - it[1].Size.Y / 2) end
	end
	check(Ms.imported == nil and Ms.tpiv == ds.turret.pivot0 and ds.turret.pivot0 ~= ds.turret.pivot and math.abs(lowT - ds.hullH) < 0.4,
		string.format("没导入的斯特赖克：零件拼的炮塔底在 %.2f 格（车体顶 %.2f；型号表转轴照原模型是 %.2f 格高）", lowT, ds.hullH, ds.turret.pivot.Y))
	Ms.model:Destroy()
end
H.run(2.2)   -- 一个人两次生成之间要隔 2 秒
local tp = H.pad(G, "m1a2")
local e = tp and H.usePad(G, def, tp)
check(e ~= nil and e.def.id == "m1a2", "生成了 M1A2")
act(def, "enterVeh", e.id)
H.run(1.5)
check(PD.vehicle == e and CD.drive ~= nil, "坐进去了")
local v = nil
for em, vv in pairs(CD.views) do if em == e.model then v = vv end end
local M = v and v.M
check(M ~= nil and M.imported == KEY, "客户端用的是原模型（" .. tostring(M and M.imported) .. "）")
local meshes, turret, gun, wheels = 0, 0, 0, 0
local aTurret, aGun = nil, nil
if M then
	for _, it in ipairs(M.parts) do
		if it[1]:IsA("MeshPart") then
			meshes += 1
			if it[2] == "turret" then turret += 1 aTurret = aTurret or it[1] end
			if it[2] == "gun" then gun += 1 aGun = aGun or it[1] end
			if it[2] == "wheel" then wheels += 1 end
		end
	end
end
check(meshes == nParts, string.format("原模型 %d 块全用上：车体 %d、炮塔 %d、炮 %d、车轮 %d", meshes, meshes - turret - gun - wheels, turret, gun, wheels))
check(M and #M.wheels == 18, "18 个负重轮 / 主动轮 / 诱导轮各自一个弹簧：" .. (M and #M.wheels or 0))
-- 真实尺寸：不缩放（块的大小 = 元数据里的）
local okSize = true
if M then
	for _, it in ipairs(M.parts) do
		local p = info.parts[string.match(it[1].Name, "__(.+)$") or ""]
		if p and (it[1].Size - V3.new(p.s[1], p.s[2], p.s[3])).Magnitude > 0.01 then okSize = false end
	end
end
check(okSize, string.format("真实尺寸（长 %.1f 格 = %.1f 米）", info.len, info.len / 2.8))
-- 看得见的车身（不含炮塔、炮）正好在碰撞盒中间：原点按车身取，不按含炮管的整个包围盒
local zlo, zhi, xlo, xhi = 1e9, -1e9, 1e9, -1e9
if M then
	for _, it in ipairs(M.parts) do
		if it[1]:IsA("MeshPart") and (it[2] == "hull" or it[2] == "wheel") then
			local r = v.hullF:ToObjectSpace(it[1].CFrame)
			zlo, zhi = math.min(zlo, r.Position.Z - it[1].Size.Z / 2), math.max(zhi, r.Position.Z + it[1].Size.Z / 2)
			xlo, xhi = math.min(xlo, r.Position.X - it[1].Size.X / 2), math.max(xhi, r.Position.X + it[1].Size.X / 2)
		end
	end
end
check(math.abs((zlo + zhi) / 2) < 0.3 and math.abs((xlo + xhi) / 2) < 0.3, string.format("车身中心对准碰撞盒中心（前后差 %.2f、左右差 %.2f 格；车身长 %.1f，碰撞盒长 %.1f）", (zlo + zhi) / 2, (xlo + xhi) / 2, zhi - zlo, e.def.L))
local d = e.def
check((d.turret.pivot - V3.new(info.tur[1], info.tur[2], info.tur[3])).Magnitude < 1e-3, "炮塔转轴照原模型")
check(math.abs(d.gun.len - info.muz) < 1e-3, string.format("炮口离耳轴 %.2f 格（原模型）", d.gun.len))

print("③ 炮塔、炮管跟着转")
local function rel(part) return v.hullF:ToObjectSpace(part.CFrame) end
local t0 = aTurret and rel(aTurret)
local g0 = aGun and rel(aGun)
-- 镜头转到车的右边、往上抬一点（瞄准点照镜头算）：炮塔转过去、炮抬起来
for _ = 1, 120 do
	CD.drive.camYaw, CD.drive.camPitch = CD.drive.yaw - math.pi / 2, 0.15
	H.step(1 / 30)
end
local t1 = aTurret and rel(aTurret)
local g1 = aGun and rel(aGun)
local tyN = ((CD.drive.ty + 180) % 360) - 180
check(t0 and t1 and (t1.Position - t0.Position).Magnitude > 0.5 and math.abs(tyN - 90) < 5, string.format("炮塔转到右边（转角 %.0f°），原模型的炮塔块跟着挪了", tyN))
check(g0 and g1 and (g1.Position - g0.Position).Magnitude > 0.5 and CD.drive.gp > 3, string.format("炮管跟着转、抬起 %.1f°", CD.drive.gp))

print("④ 开动：车轮转、悬架动")
local spin0 = M.wheels[1].spin
H.key(def, Enum.KeyCode.W, true)
H.run(3)
H.key(def, Enum.KeyCode.W, false)
H.run(0.5)
check(math.abs(M.wheels[1].spin - spin0) > 1, string.format("车轮转了 %.1f 弧度", math.abs(M.wheels[1].spin - spin0)))
local lo, hi = 0, 0
for _, w in ipairs(M.wheels) do lo, hi = math.min(lo, w.dy), math.max(hi, w.dy) end
check(hi - lo > 0.01 and hi - lo <= 0.4, string.format("负重轮动一点（%.2f～%.2f 格；履带是死的，不能动太多）", lo, hi))

print("⑤ 开炮：炮弹从原模型的炮口出去")
H.runUntil(function() return G.round.phase == "battle" end, 40)
local shot = nil
local orig = G.launch
G.launch = function(s)
	if s.kind == "shell" and not shot then shot = s.pos end
	return orig(s)
end
H.mouseDown(def, 640, 360)
H.run(0.2)
H.mouseUp(def, 640, 360)
H.run(0.5)
G.launch = orig
if shot and aGun then
	-- 炮管前端：耳轴往前 muz 格
	local base = e.root.CFrame * CF.new(0, -d.H / 2, 0)
	local gcf = base * CF.new(d.turret.pivot) * roblox.CFrame.Angles(0, -math.rad(e.ty), 0) * CF.new(d.gun.pivot) * roblox.CFrame.Angles(math.rad(e.gp), 0, 0)
	local tip = (gcf * CF.new(0, 0, -info.muz)).Position
	check((shot - tip).Magnitude < 2, string.format("炮弹出膛的地方离原模型炮口 %.2f 格", (shot - tip).Magnitude))
else
	check(false, "没打出炮弹（阶段 " .. tostring(G.round.phase) .. "）")
end

print("⑥ 打爆：贴图去掉、烧黑")
G.damageEnt(e, 1e6, { team = "atk", name = "test" })
H.run(1)
local dark = 0
for _, it in ipairs(M.parts) do
	if it[1]:IsA("MeshPart") and it[1].TextureID == "" then dark += 1 end
end
check(dark == meshes, string.format("%d / %d 块烧黑", dark, meshes))

H.summary()
for i, w in ipairs(H.warns) do if i <= 6 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
