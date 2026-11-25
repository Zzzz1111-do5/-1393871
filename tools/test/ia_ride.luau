--!nocheck
-- 运兵车、步战车载人（用户 11-24：「运载车步战车要真的能载人」）：
--   ① 守方一个人开悍马，另一个队友走过去按 E：坐后面当乘客（服务器 e.pass、人藏起来锚定；客户端 Ride.lua 接管镜头，不接管驾驶）
--   ② 车往前开：乘客跟着车走
--   ③ 乘客按 F 下车：从车尾下去、人露出来；开车的照旧在开
--   ④ 座位满了上不去；坦克没有乘客位
--   ⑤ 车被打爆：乘客一起阵亡
-- 用法（仓库根目录）：lune run tools/test/ia_ride.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })

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
local pls = { H.addPlayer("P1", 6101), H.addPlayer("P2", 6102), H.addPlayer("P3", 6103) }
H.run(2)
-- 三个人都放进守方（营地有悍马）
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
local A, B, C3 = pls[1], pls[2], pls[3]
local PA, PB, PC = G.P[A], G.P[B], G.P[C3]
check(PA.alive and PB.alive and PC.alive, "三个人都在营地出生了")

print("① 一个人开悍马，队友按 E 坐后面")
local apcId = "hmmwv"
local tp = H.pad(G, apcId)
local e = tp and H.usePad(G, A, tp)
check(e ~= nil and e.def.id == apcId, "生成了一辆悍马（座位 " .. tostring(e and e.def.seats) .. "，乘客位 " .. tostring(e and (e.def.seats - 1)) .. "）")
if not e then process.exit(1) end
act(A, "enterVeh", e.id)
H.run(1)
check(e.driver == PA, "A 开车")
local CA, CB = H.Gs[A.Name], H.Gs[B.Name]
-- B 走到车边
local function goNear(pl, veh)
	veh = veh or e
	if pl.Character then pl.Character:PivotTo(veh.root.CFrame * CF.new(-(veh.def.W / 2 + 3), 0, 0)) end
end
goNear(B)
H.run(0.3)
local prompt
for em, v in pairs(CB.views or {}) do if em == e.model then prompt = v.prompt end end
check(prompt ~= nil and prompt.Enabled and prompt.ActionText == CB.T("ui.ride", 0, e.def.seats - 1), "队友看到「" .. tostring(prompt and prompt.ActionText) .. "」")
act(B, "enterVeh", e.id)
H.run(1)
check(PB.vehicle == e and e.pass and e.pass[1] == PB, "B 坐在后面（e.pass）")
check(e.driver == PA, "开车的还是 A")
local hrpB = B.Character and B.Character:FindFirstChild("HumanoidRootPart")
check(hrpB and hrpB.Anchored and B.Character.Head.Transparency == 1, "B 藏进车里、锚定")
check(CB.S and CB.S.veh and CB.S.veh.pass == true, "B 的客户端知道自己是乘客")
check(CB.drive == nil, "B 的客户端没有接管驾驶")
check(CB.riding ~= nil, "B 的客户端是乘客镜头（Ride.lua）")

print("② 车往前开：乘客跟着车走")
local p0 = e.root.CFrame.Position
H.key(A, Enum.KeyCode.W, true)
H.run(3)
H.key(A, Enum.KeyCode.W, false)
H.run(0.5)
local p1 = e.root.CFrame.Position
local moved = (V3.new(p1.X, 0, p1.Z) - V3.new(p0.X, 0, p0.Z)).Magnitude
check(moved > 25, string.format("车开出去 %.0f 格", moved))
local gap = hrpB and (hrpB.Position - p1).Magnitude or 999
check(gap < 3, string.format("B 跟着车（离车 %.1f 格）", gap))

print("③ 乘客按 F 下车：从车尾下去")
H.key(B, Enum.KeyCode.F, true)
H.key(B, Enum.KeyCode.F, false)
H.run(1)
check(PB.vehicle == nil and #e.pass == 0, "B 下车了")
check(e.driver == PA, "A 还在开")
if hrpB then
	local l = e.root.CFrame:PointToObjectSpace(hrpB.Position)
	check(l.Z > e.def.L / 2, string.format("B 在车尾后面下的车（车尾后 %.1f 格）", l.Z - e.def.L / 2))
	check(not hrpB.Anchored and B.Character.Head.Transparency < 1, "B 露出来、能走了")
end
check(CB.riding == nil, "B 的乘客镜头收了")

print("④ 座位满了上不去；坦克没有乘客位")
goNear(B)
act(B, "enterVeh", e.id)
goNear(C3)
act(C3, "enterVeh", e.id)
H.run(1)
check(#e.pass == 2, "两个队友都坐上了（" .. #e.pass .. " / " .. (e.def.seats - 1) .. "）")
local seats0 = e.def.seats
e.def.seats = 3   -- 只剩两个乘客位：第三个人上不去
local extra = H.addPlayer("P4", 6104)
H.run(1)
local PX = G.P[extra]
PX.team = "def"
extra.Team = G.TEAM.def
extra:SetAttribute("Side", "def")
G.pushOne(PX)
deploy(extra)
H.run(2.5)
goNear(extra)
act(extra, "enterVeh", e.id)
H.run(0.6)
check(PX.vehicle == nil and #e.pass == 2, "座位满了：第四个人上不去")
e.def.seats = seats0
local tankId = G.Config.Vehicles.def.tank[3]
local tpT = H.pad(G, tankId)
local tk = tpT and H.usePad(G, extra, tpT)
if tk then
	act(extra, "enterVeh", tk.id)
	H.run(1)
	local hrpA = A.Character and A.Character:FindFirstChild("HumanoidRootPart")
	-- A 下车，走到坦克边上试着坐后面
	as(A, function() H.Gs[A.Name].R.Drive:FireServer({ op = "exit" }) end)
	H.run(1)
	goNear(A, tk)
	act(A, "enterVeh", tk.id)
	H.run(0.6)
	check(tk.driver == PX and PA.vehicle == nil, "坦克有人开：别人坐不上去（没有乘客位）")
end

print("⑤ 车被打爆：乘客一起阵亡（开战以后才掉血）")
H.runUntil(function() return G.round.phase == "battle" end, 90)
check(PB.vehicle == e and PC.vehicle == e, "两个乘客还在悍马里")
e:onDeath(nil)
H.run(1.5)
check(not PB.alive and not PC.alive, "车被打爆：两个乘客都阵亡了")

print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
