--!nocheck
-- 瞄准镜真模型测试：假装在 Studio 里导入了 models/optics/atacr.glb、binoc.glb（按 OpticsMeta 摆一套同名的 MeshPart 放在 Workspace）→
--   开服时收进 ReplicatedStorage.Imported.Optics → 服务器发的狙击枪工具上装的是真瞄准镜（别人看到的）→ 第一人称狙击枪装着真瞄准镜 →
--   按住右键：先把镜子举到眼前（目镜里的像还没出来），举到了换成目镜里的像；目镜正对屏幕中心、光轴朝前、在屏幕上占高度的 86% →
--   滚轮变倍：视角变小、目镜推远（屏幕上一样大）、分划跟着放大（第一焦平面：每密位的像素数跟着倍率涨）→ 松开：收镜、模型又看得见 →
--   观察员的望远镜也是真模型，举到眼前后换成双圆视野 → 手持装备的真模型（这里还假装导入了 m40a5、rpg7）：服务器按阵营发的工具上装的是它，
--   美军狙击枪 = M40A5 + 导轨上的 ATACR，第一人称也是这一套、开镜看的是 ATACR 的目镜；解放军 RPG-7 的筒口在弹头尖
-- 用法（仓库根目录）：lune run tools/test/ia_optics.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Enum, Inst = roblox.Vector3, roblox.CFrame, roblox.Enum, roblox.Instance
H.quietWarn = process.args[2] ~= "v"
H.realProjection = true

local OM = luau.load(fs.readFile("src/ReplicatedStorage/OpticsMeta.lua"), { debugName = "OpticsMeta" })()
H.boot(process.args[1], { ds = "mock", before = function(game)
	for _, k in ipairs({ "atacr", "binoc", "m40a5", "rpg7" }) do
		local m = Inst.new("Model")
		m.Name = "O_" .. k
		for name, p in pairs(OM[k].parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "O_" .. k .. "__" .. name
			mp.Size = V3.new(math.max(0.05, p.s[1]), math.max(0.05, p.s[2]), math.max(0.05, p.s[3]))
			mp.CFrame = CF.new(300 + p.c[1], 80 + p.c[2], 300 + p.c[3])
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

print("① 开服：收好导入的瞄准镜、望远镜；狙击枪工具装的是真瞄准镜")
local RS = H.game:GetService("ReplicatedStorage")
local opt = RS:FindFirstChild("Imported") and RS.Imported:FindFirstChild("Optics")
check(opt and opt:FindFirstChild("atacr") and #opt.atacr:GetChildren() == 4 and opt:FindFirstChild("binoc") ~= nil, "Imported.Optics 里有 atacr（4 块）、binoc")
local function count(tool, pat) local n = 0 for _, c in ipairs(tool:GetChildren()) do if string.match(c.Name, pat) then n += 1 end end return n end
local TA, TD = G.TOOLS.atk, G.TOOLS.def
local nReal = count(TA.sniper, "^Scope_")
check(nReal == 4 and TA.sniper:FindFirstChild("Scope") == nil and count(TA.sniper, "^Gear_") == 0,
	"解放军狙击枪（QBU-88 没导入）：零件拼的枪上装着真瞄准镜（" .. nReal .. " 块），没有零件拼的镜筒")
check(count(TD.sniper, "^Gear_") == 3 and count(TD.sniper, "^Scope_") == 4 and TD.sniper:GetAttribute("Gear") == "m40a5" and TD.sniper:GetAttribute("GearMount") == "atacr",
	string.format("美军狙击枪：M40A5 真模型 %d 块 + 导轨上的 ATACR %d 块", count(TD.sniper, "^Gear_"), count(TD.sniper, "^Scope_")))
-- ATACR 的镜座底面贴在 M40A5 的导轨上（工具坐标：握把在把手处、枪口朝 −Z）
do
	local h = TD.sniper.Handle
	local mt = TD.sniper:FindFirstChild("Scope_Mount")
	local g, r = OM.m40a5.pts.grip, OM.m40a5.pts.rail
	local want = CF.Angles(0, math.pi, 0) * V3.new(r[1] - g[1], r[2] - g[2], r[3] - g[3]) + CF.Angles(0, math.pi, 0) * V3.new(OM.atacr.parts.Mount.c[1], OM.atacr.parts.Mount.c[2], OM.atacr.parts.Mount.c[3])
	local got = mt and h.CFrame:PointToObjectSpace(mt.CFrame.Position)
	check(got and (got - want).Magnitude < 1e-3, string.format("ATACR 镜座在 M40A5 导轨上（差 %.4f 格）", got and (got - want).Magnitude or -1))
end
do   -- RPG-7：筒口在弹头尖（器材坐标的 muzzle 点转到工具坐标）
	local g, m = OM.rpg7.pts.grip, OM.rpg7.pts.muzzle
	local want = V3.new(-(m[1] - g[1]), m[2] - g[2], -(m[3] - g[3]))
	local mz = TA.rpg.Handle:FindFirstChild("Muzzle")
	check(count(TA.rpg, "^Gear_") == 1 and count(TD.rpg, "^Gear_") == 0 and mz and (mz.Position - want).Magnitude < 1e-3,
		string.format("解放军火箭筒是 RPG-7 真模型、筒口在弹头尖（%.2f, %.2f, %.2f）；美军 AT4 没导入照旧零件拼", mz and mz.Position.X or 0, mz and mz.Position.Y or 0, mz and mz.Position.Z or 0))
end

print("② 狙击手出生、拿狙击枪：第一人称装着真瞄准镜")
local pl = H.addPlayer("P1", 9101)
H.run(2)
act(pl, "pickTeam", "atk")
H.run(0.5)
act(pl, "deploy", "sniper", "fleet")
H.run(2)
if G.round.phase == "prep" then G.round.prepEnds = 0 end   -- 准备阶段人是锚住的（拿不了枪）：直接开战
H.runUntil(function() return G.round.phase == "battle" end, 10)
H.run(2)
local C = H.Gs[pl.Name]
local P = G.P[pl]
check(P and P.alive, "狙击手在舰上出生")
H.key(pl, Enum.KeyCode.One, true) H.key(pl, Enum.KeyCode.One, false)
H.run(1)
if not (P.char and P.char:FindFirstChildOfClass("Tool")) then
	local prev = H.ctx
	H.ctx = pl
	C.equipSlot(1)
	H.ctx = prev
	H.run(1)
end
local vm = C.fps
local body, eyeInfo = nil, OM.atacr.eye
local nOptic = 0
if vm then for _, it in ipairs(vm.items) do if it.optic then nOptic += 1 if it.optic == "Body" then body = it[1] end end end end
check(vm and vm.id == "sniper" and nOptic == 4 and vm.optic ~= nil, "第一人称的狙击枪上是真瞄准镜（" .. nOptic .. " 块）")

print("③ 开镜：先举到眼前，再换成目镜里的像")
local cam = H.workspace.CurrentCamera
local sg = pl.PlayerGui:FindFirstChild("Scope")
H.mouseDown(pl, 640, 360, Enum.UserInputType.MouseButton2)
H.run(0.05)
check(C.fpsOpticPending() == true and not sg.Enabled, "刚按右键：还在举镜，目镜里的像没出来")
H.run(0.8)
check(C.fpsOpticPending() == false and sg.Enabled, "举到眼前：换成目镜里的像")
local function eyeCheck(tag)
	local bc = OM.atacr.parts.Body.c
	local e = eyeInfo.c
	local eyeW = body.CFrame * V3.new(e[1] - bc[1], e[2] - bc[2], e[3] - bc[3])
	local o = OM.atacr.obj.c
	local objW = body.CFrame * V3.new(o[1] - bc[1], o[2] - bc[2], o[3] - bc[3])
	local lp = cam.CFrame:PointToObjectSpace(eyeW)
	local axis = (objW - eyeW).Unit:Dot(cam.CFrame.LookVector)
	local frac = (eyeInfo.r / -lp.Z) / math.tan(math.rad(cam.FieldOfView) / 2)
	check(math.abs(lp.X) < 0.02 and math.abs(lp.Y) < 0.02 and lp.Z < 0 and axis > 0.995 and math.abs(frac - 0.86) < 0.08,
		string.format("%s：目镜正对中心（偏 %.3f, %.3f 格，距离 %.2f 格）、光轴朝前（%.4f）、占屏幕高度 %.0f%%（视角 %.1f°）", tag, lp.X, lp.Y, -lp.Z, axis, frac * 100, cam.FieldOfView))
	return -lp.Z
end
local d1 = eyeCheck("10 倍")
check(body.LocalTransparencyModifier == 1, "眼睛贴上目镜以后模型藏起来（屏幕上是目镜里的像）")
local function milPx()
	local f = sg:FindFirstChild("MilX5", true)
	return f and f.Position.X.Offset / 5 or 0
end
local k1 = milPx()
local z1 = C.scopeZoom(G.Config.Weapons.sniper)
H.wheel(pl, 1) H.wheel(pl, 1)
H.run(1.2)
local z2 = C.scopeZoom(G.Config.Weapons.sniper)
local d2 = eyeCheck(z2 .. " 倍")
local k2 = milPx()
check(z2 > z1 and d2 > d1 * 1.2, string.format("变倍 %s → %s 倍：目镜推远（%.2f → %.2f 格），屏幕上一样大", tostring(z1), tostring(z2), d1, d2))
check(k1 > 0 and k2 > k1 * 1.3, string.format("第一焦平面分划跟着放大：每密位 %.1f → %.1f 像素", k1, k2))
H.mouseUp(pl, 640, 360, Enum.UserInputType.MouseButton2)
H.run(0.8)
check(not sg.Enabled and body.LocalTransparencyModifier == 0, "松开右键：收镜，模型又看得见")

print("④ 观察员的望远镜：真模型，举到眼前后换成双圆视野")
local bp = pl:FindFirstChildOfClass("Backpack")
for _, c in ipairs(P.char:GetChildren()) do if c:IsA("Tool") then c.Parent = bp end end
H.run(0.3)
P.role = "spotter"
G.giveLoadout(P)
H.run(0.3)
H.key(pl, Enum.KeyCode.Two, true) H.key(pl, Enum.KeyCode.Two, false)
H.run(1)
vm = C.fps
local nb = 0
if vm then for _, it in ipairs(vm.items) do if it.optic then nb += 1 end end end
check(vm and vm.id == "binoc" and nb == 1, "第一人称拿的是真望远镜")
H.mouseDown(pl, 640, 360, Enum.UserInputType.MouseButton2)
H.run(0.05)
check(C.fpsOpticPending() == true and not sg.Enabled, "刚按右键：望远镜还在往眼前举")
H.run(0.8)
check(C.fpsOpticPending() == false and sg.Enabled and C.scopeOn, "举到眼前：双圆视野")
H.mouseUp(pl, 640, 360, Enum.UserInputType.MouseButton2)
H.run(0.5)

print("⑤ 美军狙击手：第一人称是 M40A5 真模型，导轨上的 ATACR 开镜")
local p2 = H.addPlayer("P2", 9102)
H.run(2)
act(p2, "pickTeam", "def")
H.run(0.5)
act(p2, "deploy", "sniper", "camp")
H.run(3)
local C2 = H.Gs[p2.Name]
local P2 = G.P[p2]
H.key(p2, Enum.KeyCode.One, true) H.key(p2, Enum.KeyCode.One, false)
H.run(1)
for _ = 1, 3 do
	if P2 and P2.char and P2.char:FindFirstChildOfClass("Tool") then break end
	local prev = H.ctx
	H.ctx = p2
	C2.equipSlot(1)
	H.ctx = prev
	H.run(1)
end
local vm2 = C2.fps
local nGun, nOpt = 0, 0
if vm2 then for _, it in ipairs(vm2.items) do if it.optic then nOpt += 1 elseif string.match(it[1].Name, "^O_m40a5__") then nGun += 1 end end end
check(P2 and P2.alive and P2.team == "def" and vm2 and vm2.id == "sniper" and nGun == 3 and nOpt == 4 and vm2.optic ~= nil,
	string.format("第一人称：M40A5 %d 块 + ATACR %d 块（开镜用 ATACR 的目镜；活着 %s、%s 队、拿着 %s、视图 %s 共 %d 块）", nGun, nOpt, tostring(P2 and P2.alive), tostring(P2 and P2.team),
		tostring(P2 and P2.char and P2.char:FindFirstChildOfClass("Tool") and P2.char:FindFirstChildOfClass("Tool"):GetAttribute("Gear")), tostring(vm2 and vm2.id), vm2 and #vm2.items or -1))
-- 开镜的目镜：ATACR 的目镜中心（装在导轨上）
if vm2 and vm2.optic then
	local g, r, e = OM.m40a5.pts.grip, OM.m40a5.pts.rail, OM.atacr.eye.c
	check(math.abs(vm2.optic.r - OM.atacr.eye.r) < 1e-6, "开镜用的是 ATACR 目镜的半径")
end

H.summary()
for i, e in ipairs(H.errors) do if i <= 10 then print("  错误：" .. tostring(e.where) .. " " .. tostring(e.err or e.msg)) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
