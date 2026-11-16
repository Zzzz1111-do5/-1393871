--!nocheck
-- 瞄准镜真模型测试：假装在 Studio 里导入了 models/optics/atacr.glb、binoc.glb（按 OpticsMeta 摆一套同名的 MeshPart 放在 Workspace）→
--   开服时收进 ReplicatedStorage.Imported.Optics → 服务器发的狙击枪工具上装的是真瞄准镜（别人看到的）→ 第一人称狙击枪装着真瞄准镜 →
--   按住右键：先把镜子举到眼前（目镜里的像还没出来），举到了换成目镜里的像；目镜正对屏幕中心、光轴朝前、在屏幕上占高度的 86% →
--   滚轮变倍：视角变小、目镜推远（屏幕上一样大）、分划跟着放大（第一焦平面：每密位的像素数跟着倍率涨）→ 松开：收镜、模型又看得见 →
--   观察员的望远镜也是真模型，举到眼前后换成双圆视野
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
	for _, k in ipairs({ "atacr", "binoc" }) do
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
local nReal = 0
for _, c in ipairs(G.TOOLS.sniper:GetChildren()) do if string.match(c.Name, "^Scope_") then nReal += 1 end end
check(nReal == 4 and G.TOOLS.sniper:FindFirstChild("Scope") == nil, "狙击枪工具上装的是真瞄准镜（" .. nReal .. " 块），没有零件拼的镜筒")

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

H.summary()
for i, e in ipairs(H.errors) do if i <= 10 then print("  错误：" .. tostring(e.where) .. " " .. tostring(e.err or e.msg)) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
