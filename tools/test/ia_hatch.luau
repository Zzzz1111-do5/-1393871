--!nocheck
-- 舱盖、车门开合，车长探身，上车的小人（用户 11-24：「坦克舱门开合动画」「进入载具的动画」「你记得按照现实中不同坦克的舱门开合模式去做哈」）
--   假装导入了 M1A2（m1a2dc）、布雷德利（m2a3）的原模型，客户端 Hatch.lua 照 HatchDefs 做舱盖：
--   ① 没人的车停着：车长、装填手、驾驶员舱盖都开着，舱盖板在 HatchDefs 算的地方（车体 / 炮塔坐标 → 世界坐标）
--   ② 有人上车：做一个小人从刚才站的地方走过去、爬上车、钻进驾驶员舱口（动画放完才关驾驶员舱盖）；
--      有人开、没打仗：车长探出来（小人钻出舱口），车长舱盖开着
--   ③ 开炮：车长缩回去、舱盖关上（关上后舱盖板、黑底都藏起来，看原模型自己的）；12 秒后艾布拉姆斯停在「打开保护位」，30 秒后又探出来
--   ④ 布雷德利有人开、队友坐后面：尾部跳板放下（放倒到尖着地）、做一个小人顺着跳板走进去，3 秒后跳板收起
--   ⑤ 自己坐在车里看瞄准镜（外模型藏起来）：舱盖、车长小人一起藏
--   ⑥ 飞机停在地上有人登机：座舱左边靠登机梯，飞行员爬上去、跨进座舱坐下，模型自己的飞行员先藏后换回
-- 用法（仓库根目录）：lune run tools/test/ia_hatch.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")
local V3, CF, Inst, Enum = roblox.Vector3, roblox.CFrame, roblox.Instance, roblox.Enum
H.quietWarn = true

local env = setmetatable({ Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = _G })
local IM = luau.load(fs.readFile("src/ReplicatedStorage/ImportedMeta.lua"), { debugName = "ImportedMeta", environment = env })()
local HD = luau.load(fs.readFile("src/ReplicatedStorage/HatchDefs.lua"), { debugName = "HatchDefs", environment = env })()
local KEYS = { "m1a2dc", "m2a3" }
H.boot(process.args[1], { ds = "mock", before = function(game)
	for _, k in ipairs(KEYS) do
		local m = Inst.new("Model")
		m.Name = "V_" .. k
		for name, p in pairs(IM.m[k].parts) do
			local mp = Inst.new("MeshPart")
			mp.Name = "V_" .. k .. "__" .. name
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
local function as(pl, f)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(f)
	coroutine.resume(co)
	H.ctx = prev
end
local function act(pl, ...)
	local a = table.pack(...)
	as(pl, function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end

H.run(0.5)
local G = H.Gs.server
G.fortsHold, G.navyNoAI = true, true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local pls = { H.addPlayer("P1", 6201), H.addPlayer("P2", 6202) }
H.run(2)
for _, pl in ipairs(pls) do
	local P = G.P[pl]
	P.team = "def"
	pl.Team = G.TEAM.def
	pl.Neutral = false
	pl:SetAttribute("Side", "def")
	G.pushOne(P)
end
H.run(0.5)
local function deploy(pl)
	local C = H.Gs[pl.Name]
	C.deploySel.spawn, C.deploySel.role = "camp", "engineer"
	H.leaveMenu(pl)
	C.refreshDeploy()
	H.click(pl, "^" .. C.T("ui.deployBtn") .. "$")
end
for _, pl in ipairs(pls) do deploy(pl) end
H.run(2.5)
local A, B = pls[1], pls[2]
local PA, PB = G.P[A], G.P[B]
local CA, CB = H.Gs[A.Name], H.Gs[B.Name]
check(PA.alive and PB.alive, "两个人都在营地出生了")

local cam = H.workspace.CurrentCamera
local function lookAt(e)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CF.lookAt(e.root.CFrame.Position + V3.new(30, 20, 30), e.root.CFrame.Position)
end
local function viewOf(C, e)
	for em, v in pairs(C.views or {}) do if em == e.model then return v, em end end
	return nil
end
local function hatchOf(s, id)
	for _, h in ipairs(s and s.hs or {}) do if h.id == id then return h end end
	return nil
end

print("① 没人的 M1A2 停着：三块舱盖都开着，舱盖板在 HatchDefs 算的地方")
local tank = H.usePad(G, A, H.pad(G, "m1a2"))
check(tank ~= nil and tank.def.id == "m1a2", "生成了一辆 M1A2")
if not tank then process.exit(1) end
lookAt(tank)
H.run(2)
local v, em = viewOf(CA, tank)
check(v ~= nil and v.M and v.M.imported == "m1a2dc", "客户端用原模型 m1a2dc 画（" .. tostring(v and v.M and v.M.imported) .. "）")
local s = em and CA.hatchState(em)
check(s ~= nil and s ~= false and #s.hs == 3, "M1A2 有 3 块舱盖（" .. tostring(s and #s.hs) .. "）：车长、装填手、驾驶员")
local cmd, ldr, drv = hatchOf(s, "cmd"), hatchOf(s, "ldr"), hatchOf(s, "drv")
check(cmd and ldr and drv and cmd.p > 0.99 and ldr.p > 0.99 and drv.p > 0.99, "没人：三块都开到头")
if cmd and drv then
	check(cmd.lid.Transparency == 0 and cmd.hole.Transparency == 0, "开着：舱盖板、黑底都画出来")
	local want = v.tF * HD.lidCF(cmd, 1)
	check((cmd.lid.CFrame.Position - want.Position).Magnitude < 0.05, "车长舱盖板在炮塔上该在的地方（后铰链掀到 105°）")
	local wantD = v.hullF * HD.lidCF(drv, 1)
	check((drv.lid.CFrame.Position - wantD.Position).Magnitude < 0.05, "驾驶员舱盖板在车体上该在的地方（抬起来往右转开）")
	local rel = v.hullF:PointToObjectSpace(drv.lid.CFrame.Position)
	check(rel.X > drv.pv.X, string.format("驾驶员舱盖转到了转轴右边（x %.2f > %.2f）", rel.X, drv.pv.X))
end

-- 客户端每帧的步骤出错会写在屏幕顶上的红条里（UI.lua showError）："local hatch: …"
local function hatchErr()
	for _, pl in ipairs(pls) do
		for _, d in ipairs(pl.PlayerGui:GetDescendants()) do
			if d:IsA("TextLabel") and string.find(d.Text or "", "local hatch", 1, true) then return d.Text end
		end
	end
	return nil
end
local e1 = hatchErr()
check(e1 == nil, "舱盖这一步没出错" .. (e1 and ("：" .. e1) or ""))

print("② A 上车：小人走过去、爬上车、钻进驾驶员舱口；车长探出来")
-- A 站到车左边几格，再上车
A.Character:PivotTo(tank.root.CFrame * CF.new(-(tank.def.W / 2 + 4), 0, -2))
H.run(0.4)
act(A, "enterVeh", tank.id)
H.run(0.25)
check(tank.driver == PA, "A 开车")
local anim = nil
for _, x in ipairs(CB.hatchAnims or {}) do if x.kind == "drv" then anim = x end end
local sB = CB.hatchState(em)
check(anim ~= nil, "队友 B 的画面里有个上车的小人（开车的）")
if anim then
	local startL = v.hullF:PointToObjectSpace(anim.K[1].p + v.hullF.Position)
	check(anim.K[1].p.X < 0, string.format("小人从车左边过来（起点车体坐标 x %.1f）", anim.K[1].p.X))
	check(anim.dur > 2 and anim.dur < 4.5, string.format("上车动画 %.1f 秒", anim.dur))
end
H.run(1.2)
local drvB = hatchOf(sB, "drv")
check(drvB and drvB.p > 0.95, "小人还没钻进去：驾驶员舱盖开着")
H.run(4.5)
check(#(CB.hatchAnims or {}) == 0, "上车动画放完了，小人收掉")
check(drvB and drvB.p < 0.01, "钻进去以后驾驶员舱盖关上")
check(drvB and drvB.lid.Transparency == 1 and drvB.hole.Transparency == 1, "关上后舱盖板、黑底都藏起来（看原模型自己的舱盖）")
local cmdB = hatchOf(sB, "cmd")
check(cmdB and cmdB.p > 0.99, "有人开、没打仗：车长舱盖开着")
H.run(2)
check(sB.fig ~= nil and sB.fig.rise > 0.95, "车长探出舱口（rise " .. string.format("%.2f", sB.fig and sB.fig.rise or 0) .. "）")
local ldrF = sB.figs and sB.figs.ldr
check(ldrF ~= nil and ldrF.rise > 0.95 and hatchOf(sB, "ldr").p > 0.99, "装填手也探出来守着左边（装填手舱盖开着）")
if sB.fig then
	-- 测试台里 Motor6D 不会带着零件动，只看根零件（f.set 直接摆它，骨盆那里）：在舱口正下方一点，胸口以上露出舱圈
	local root = sB.fig.f.hrp.CFrame.Position
	local vB0 = viewOf(CB, tank)
	local top = (vB0.tF * CF.new(cmdB.loc)).Position
	local eye = root.Y + sB.fig.eyeY
	check(eye > top.Y + 1.0 and eye < top.Y + 3.0, string.format("车长的眼睛在舱圈上面 %.1f 格", eye - top.Y))
	local d = (root - top) * V3.new(1, 0, 1)
	check(d.Magnitude < 1.0, string.format("车长站在舱口里（离舱口中心 %.2f 格）", d.Magnitude))
end

print("③ 开炮：车长缩回去、舱盖关上；12 秒后打开保护位，30 秒后又探出来")
CB.vehRecoil(tank.id)   -- 同服务器开炮广播到客户端时一样（View 的后坐）
H.run(1.7)
check(sB.fig and sB.fig.rise < 0.05, "车长缩回去了")
check(ldrF and ldrF.rise < 0.05 and hatchOf(sB, "ldr").p < 0.05, "装填手也缩回去、舱盖关上")
check(cmdB.p < 0.05, string.format("车长舱盖关上（%.2f）", cmdB.p))
H.run(12)
check(math.abs(cmdB.p - HD.ABRAMS_OP) < 0.02, string.format("12 秒后停在打开保护位（%.3f ≈ %.3f）", cmdB.p, HD.ABRAMS_OP))
check(cmdB.lid.Transparency == 0, "打开保护位：舱盖板画出来（掀开一道缝）")
H.run(18)
check(cmdB.p > 0.99 and sB.fig and sB.fig.rise > 0.5, "30 秒没打仗：舱盖全开、车长又探出来")

print("④ 布雷德利：队友坐后面，尾部跳板放下、小人顺着跳板走进去")
-- 守方地面车位所有车型共用一个出车点：A 先把坦克开走，让出地方
H.key(A, Enum.KeyCode.W, true)
H.run(3)
H.key(A, Enum.KeyCode.W, false)
H.run(1)
local ifv = H.usePad(G, B, H.pad(G, "m2a3"))
check(ifv ~= nil, "生成了一辆布雷德利")
if ifv then
	lookAt(ifv)
	act(B, "enterVeh", ifv.id)
	H.run(6)
	check(ifv.driver == PB, "B 开布雷德利")
	local vi, emi = viewOf(CA, ifv)
	local si = emi and CA.hatchState(emi)
	local ramp = hatchOf(si, "ramp")
	check(vi and vi.M.imported == "m2a3" and ramp ~= nil, "布雷德利有尾部跳板")
	check(ramp and ramp.p < 0.01, "有人开着：跳板收着")
	-- A 下坦克，走到布雷德利右边，坐后面
	as(A, function() CA.R.Drive:FireServer({ op = "exit" }) end)
	H.run(1)
	A.Character:PivotTo(ifv.root.CFrame * CF.new(ifv.def.W / 2 + 3, 0, 0))
	H.run(0.4)
	act(A, "enterVeh", ifv.id)
	H.run(0.25)
	check(PA.vehicle == ifv, "A 坐在布雷德利后面")
	local pa = nil
	for _, x in ipairs(CB.hatchAnims or {}) do if x.kind == "pass" then pa = x end end
	check(pa ~= nil, "B 的画面里有个坐后面的小人在走")
	if pa then
		check(pa.K[1].p.X > 0, string.format("小人从车右边过来（x %.1f）", pa.K[1].p.X))
		-- 绕着车走：中间的路点都在车外面
		local inside = false
		for _, k in ipairs(pa.K) do
			if math.abs(k.p.X) < ifv.def.W / 2 - 0.2 and math.abs(k.p.Z) < ifv.def.L / 2 - 0.5 and k.walk and k.t < pa.dur - 1.3 then inside = true end
		end
		check(not inside, "走过去的路没有穿过车身")
	end
	local siB = CB.hatchState(select(2, viewOf(CB, ifv)))
	local rampB = hatchOf(siB, "ramp")
	H.run(1.5)
	check(rampB and rampB.p > 0.9, string.format("跳板放下来了（%.2f）", rampB and rampB.p or -1))
	if rampB then
		local vb = viewOf(CB, ifv)
		local tip = vb.hullF:PointToObjectSpace((rampB.lid.CFrame * CF.new(0, rampB.L / 2, 0)).Position)
		check(math.abs(tip.Y) < 0.6, string.format("跳板放倒到尖着地（尖离地 %.2f 格）", tip.Y))
	end
	H.run(6)
	check(rampB and rampB.p < 0.05, "人进去了：跳板收起来")
end

print("⑤ 自己在车里看瞄准镜：外模型藏起来，舱盖、车长小人也藏")
if not ifv then
	print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
	process.exit(1)
end
local mine = CB.views and select(2, viewOf(CB, ifv))
-- B 开着布雷德利：照 Drive 的做法把外模型的零件藏起来（LocalTransparencyModifier = 1），下一帧这些也该藏
local vb = viewOf(CB, ifv)
for _, it in ipairs(vb.M.parts) do it[1].LocalTransparencyModifier = 1 end
H.run(0.2)
local sib = CB.hatchState(mine)
local allHidden = true
for _, x in ipairs(sib.folder:GetDescendants()) do
	if x:IsA("BasePart") and x.LocalTransparencyModifier < 1 then allHidden = false end
end
check(allHidden, "车里看：舱盖、黑底一起藏起来")
for _, it in ipairs(vb.M.parts) do it[1].LocalTransparencyModifier = 0 end
H.run(0.2)
local back = true
for _, x in ipairs(sib.folder:GetDescendants()) do
	if x:IsA("BasePart") and x.LocalTransparencyModifier > 0 then back = false end
end
check(back, "出来看：又画出来")

print("⑥ 飞机停在地上有人登机：座舱左边靠一架登机梯，飞行员走过去、爬上去、跨进座舱坐下")
as(A, function() CA.R.Drive:FireServer({ op = "exit" }) end)
H.run(1.2)
local RS = H.game:GetService("ReplicatedStorage")
local prevCtx = H.ctx
H.ctx = B
local ADc = H.require(RS.AirDefs)
local AMc = H.require(B.PlayerScripts.Client.AirModels)
H.ctx = prevCtx
local dj = ADc.get("f22")
local hrpA = A.Character and A.Character:FindFirstChild("HumanoidRootPart")
local ap = hrpA and hrpA.CFrame.Position or tank.root.CFrame.Position
local x, z = ap.X + 40, ap.Z
local gy = G.airSurface(x, z)
local jet = G.spawnAircraft("def", "f22", CF.new(x, gy + dj.gearH, z), nil, PA)
check(jet ~= nil and jet.onGround, "停机坪上摆了一架 F-22")
if jet then
	lookAt(jet)
	H.run(1.5)
	local vj, emj = viewOf(CB, jet)
	check(vj ~= nil and vj.kind == "air", "B 的客户端画出了这架飞机")
	-- A 站到飞机左前方，登机
	A.Character:PivotTo(CF.new((jet.root.CFrame * CF.new(-14, 0, -6)).Position.X, gy + 3, (jet.root.CFrame * CF.new(-14, 0, -6)).Position.Z))
	H.run(0.4)
	act(A, "enterVeh", jet.id)
	H.run(0.25)
	check(PA.vehicle == jet, "A 坐进了 F-22")
	local aa = nil
	for _, x2 in ipairs(CB.hatchAnims or {}) do if x2.kind == "air" then aa = x2 end end
	check(aa ~= nil, "B 的画面里有个登机的飞行员")
	if aa and vj then
		check(aa.props and #aa.props >= 5, "座舱左边靠了一架登机梯（" .. tostring(aa.props and #aa.props) .. " 个零件）")
		local seat = AMc.seatCF(vj.M, 1)
		check(aa.K[1].p.X < seat.Position.X, string.format("飞行员从飞机左边过来（x %.1f）", aa.K[1].p.X))
		check(vj.M.pilotsOn == false, "爬的时候模型自己的飞行员先藏起来")
		local lastK = aa.K[#aa.K]
		check((lastK.p - seat.Position).Magnitude < 1.5, string.format("最后坐进座舱（离座位 %.2f 格）", (lastK.p - seat.Position).Magnitude))
		-- 梯子在左边、从地面靠到座舱边沿
		local ys, xs = {}, {}
		for _, pr in ipairs(aa.props) do table.insert(ys, pr[2].Position.Y) table.insert(xs, pr[2].Position.X) end
		table.sort(ys)
		check(xs[1] < seat.Position.X - 1, "梯子在座舱左边")
		local dur = aa.dur
		H.run(dur + 0.4)
		local still = false
		for _, x2 in ipairs(CB.hatchAnims or {}) do if x2 == aa then still = true end end
		check(not still, string.format("登机动画放完（%.1f 秒）收掉", dur))
		check(aa.props[1][1].Parent == nil, "登机梯撤掉了")
		check(vj.M.pilotsOn == true, "坐下以后换回模型自己的飞行员")
	end
end

local e2 = hatchErr()
check(e2 == nil, "整个过程舱盖这一步没出错" .. (e2 and ("：" .. e2) or ""))
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
