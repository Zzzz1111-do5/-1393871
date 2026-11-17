--!nocheck
-- 载具测试：部署坦克（守方营地）→ 坐进去、开车（服务器跟着动）、悬架（轮子按地面上下）→ 开炮（炮弹飞出去、扣弹药）→
--   烟幕弹（从发射筒打出、落地起烟团、挡住视线）→ 瞄准镜四种模式（昼光 / 夜视 / 热成像白热 / 黑热：调色 + 高亮）→
--   下车、再上车 → 被击毁（车组阵亡、名额冷却）→ 攻方两栖车从海里开上来、不会游的坐气垫艇上滩
-- 用法（仓库根目录）：lune run tools/test/ia_veh.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
H.quietWarn = process.args[2] ~= "v"
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
local function drive(pl, msg) as(pl, function() H.Gs[pl.Name].R.Drive:FireServer(msg) end) end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true   -- 这里测的不是工事：工事不开火（同 tools/mock/*.lua；不然岸防炮会把测试里的登陆艇打沉）
G.navyNoAI = true   -- 也不要 AI 舰艇（守方 PBR 打登陆艇、攻方 054A 炮击岸上；同 tools/mock/veh.lua、forts.lua）
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 5001), H.addPlayer("P2", 5002)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local atk = (def == p1) and p2 or p1
local PD, PA = G.P[def], G.P[atk]
local CD = H.Gs[def.Name]

print("① 守方在营地出生，走到车场的坦克生成点按 E 生成，再走过去坐上")
local tankId = G.Config.Vehicles.def.tank[3]
check(CD.S.vehModels and #CD.S.vehModels > 0, "客户端拿到了能开的型号：" .. table.concat(CD.S.vehModels or {}, ","))
check(CD.S.vehAvail and CD.S.vehAvail.tank and CD.S.vehAvail.tank.cap >= 1, "坦克名额 " .. tostring(CD.S.vehAvail and CD.S.vehAvail.tank and CD.S.vehAvail.tank.cap))
check(#(G.pads or {}) >= 20, "地图里摆了 " .. #(G.pads or {}) .. " 个载具生成点")
CD.deploySel.spawn, CD.deploySel.role = "camp", "engineer"
H.leaveMenu(def)
CD.refreshDeploy()
H.click(def, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
check(PD.alive and PD.vehicle == nil, "步兵在营地出生")
local tp = H.pad(G, tankId)
check(tp ~= nil and tp.team == "def", "营地车场有 " .. tankId .. " 的生成点")
check(tp.prompt.ObjectText == CD.T("veh." .. tankId) and tp.prompt.ActionText == CD.T("pad.spawn"), "按键文字照客户端的语言：" .. tp.prompt.ActionText .. " " .. tp.prompt.ObjectText)
local e = H.usePad(G, def, tp)
check(e ~= nil and e.alive and e.def.id == tankId and e.driver == nil, "生成了一辆空的 " .. tostring(e and e.def.id) .. "，停在地台上")
local again = H.usePad(G, def, tp)
check(#G.vehicles == 1, "地台上停着车：不能再生成（在场 " .. #G.vehicles .. " 辆）")
-- 别人 30 秒内上不去
act(atk, "enterVeh", e.id)
H.run(0.5)
check(e.driver == nil, "刚生成的车别人上不去")
act(def, "enterVeh", e.id)
H.run(1.5)
check(PD.vehicle == e, "走过去按 E 坐上了")
check(PD.alive and def.Character and def.Character.HumanoidRootPart.Anchored, "人锚定在车里")
check(def.Character and def.Character.Head.Transparency == 1, "人藏起来了")
check(CD.drive ~= nil and CD.drive.id == (e and e.id), "客户端接管驾驶")
local v = CD.views and e and (function() for em, vv in pairs(CD.views) do if em == e.model then return vv end end end)()
check(v ~= nil and v.M ~= nil and #v.M.parts > 40, "客户端拼好了车的模型：" .. (v and v.M and #v.M.parts or 0) .. " 个零件、" .. (v and v.M and #v.M.wheels or 0) .. " 个负重轮")
local smokeTubes = 0
if v then for _, it in ipairs(v.M.parts) do if math.abs(it[1].Size.X - 0.85) < 1e-3 and it[1].Shape == Enum.PartType.Cylinder then smokeTubes += 1 end end end
check(smokeTubes == e.def.smoke.n * #e.def.smoke.banks, "烟幕弹发射筒 " .. smokeTubes .. " 根（型号规定 " .. e.def.smoke.n * #e.def.smoke.banks .. "）")

print("② 开车：按住 W 往前开，服务器跟着动")
local p0 = e.root.CFrame.Position
H.key(def, Enum.KeyCode.W, true)
H.run(4)
H.key(def, Enum.KeyCode.W, false)
H.run(1)
local p1v = e.root.CFrame.Position
local moved = (V3.new(p1v.X, 0, p1v.Z) - V3.new(p0.X, 0, p0.Z)).Magnitude
check(moved > 40, string.format("开出去 %.0f 格", moved))
local gy = G.Map.ground(p1v.X, p1v.Z)
check(math.abs((p1v.Y - e.def.H / 2) - gy) < 3, string.format("贴着地（车底 %.1f，地面 %.1f）", p1v.Y - e.def.H / 2, gy))
-- 悬架：轮子按地面上下（有的往上、有的往下）
local lo, hi = 0, 0
if v then for _, w in ipairs(v.M.wheels) do lo, hi = math.min(lo, w.dy), math.max(hi, w.dy) end end
check(hi - lo > 0.05, string.format("负重轮各自上下（%.2f ～ %.2f 格）", lo, hi))
H.key(def, Enum.KeyCode.A, true)
H.run(1.5)
H.key(def, Enum.KeyCode.A, false)
check(CD.drive and math.abs(CD.drive.steer) > 0, "按 A 转向")

print("③ 瞄准镜：默认夜视 → 热成像白热 → 黑热 → 昼光")
H.key(def, Enum.KeyCode.V, true) H.key(def, Enum.KeyCode.V, false)
H.run(0.3)
local cc = CD.sightCC   -- 测试台里几个客户端共用一棵树：用这个客户端自己的
check(CD.drive.sight and cc and cc.Enabled, "进瞄准镜，画面调色开了")
local modes = {}
for i = 1, 3 do
	H.key(def, Enum.KeyCode.N, true) H.key(def, Enum.KeyCode.N, false)
	H.run(0.6)
	local nh = 0
	for _, x in ipairs(H.workspace.CurrentCamera:GetChildren()) do if x:IsA("Highlight") then nh += 1 end end
	table.insert(modes, string.format("%s 饱和度 %.1f 亮度 %.2f 高亮 %d", tostring(({ "day", "nv", "whot", "bhot" })[CD.drive.mode]), cc.Saturation, cc.Brightness, nh))
end
print("    " .. table.concat(modes, " | "))
check(modes[1]:find("whot") and modes[2]:find("bhot") and modes[3]:find("day"), "瞄准镜默认夜视档，N 依次切白热、黑热、昼光")
check(modes[1]:find("高亮 [1-9]") ~= nil, "热成像有高亮（热的东西发白）")
H.key(def, Enum.KeyCode.V, true) H.key(def, Enum.KeyCode.V, false)
H.run(0.3)
check(not CD.drive.sight and not cc.Enabled, "退出瞄准镜，调色关了")

print("④ 开战后开炮、放烟幕弹")
H.runUntil(function() return G.round.phase == "battle" end, 40)
local ammo0 = e.wst[e.def.weapons[1]].reserve + e.wst[e.def.weapons[1]].mag
H.mouseDown(def, 640, 360)
H.run(0.2)
H.mouseUp(def, 640, 360)
H.run(1)
local ammo1 = e.wst[e.def.weapons[1]].reserve + e.wst[e.def.weapons[1]].mag
check(ammo1 == ammo0 - 1, string.format("主炮打了一发（%d → %d）", ammo0, ammo1))
local nSmoke0 = #G.smokes
H.key(def, Enum.KeyCode.X, true) H.key(def, Enum.KeyCode.X, false)
H.run(1.5)
check(#G.smokes == e.def.smoke.n * #e.def.smoke.banks, "烟幕弹落地起了 " .. #G.smokes .. " 团烟")
if #G.smokes > 0 then
	local s = G.smokes[1]
	local a = s.p + V3.new(60, 2, 0)
	local b = s.p - V3.new(60, -2, 0)
	check(G.smokeBlocks(a, b), "穿过烟团的视线被挡住")
	check(not G.smokeBlocks(s.p + V3.new(0, 200, 0), s.p + V3.new(50, 200, 0)), "烟团上面的视线不挡")
	-- 烟幕弹从发射筒打出去：落点在车的前方两侧 25～40 格（按弹道落地：车停在下坡上会落得远一些，上限放到 60）
	local base = e.root.CFrame * CF.new(0, -e.def.H / 2, 0)
	local lp = base:PointToObjectSpace(s.p)
	check((lp * V3.new(1, 0, 1)).Magnitude > 20 and (lp * V3.new(1, 0, 1)).Magnitude < 60, string.format("烟团在车旁 %.0f 格", (lp * V3.new(1, 0, 1)).Magnitude))
end
check(e.smokeLeft == 1, "烟幕弹还剩一次齐射：" .. tostring(e.smokeLeft))

print("⑤ 下车、再上车")
H.key(def, Enum.KeyCode.F, true) H.key(def, Enum.KeyCode.F, false)
H.run(1)
check(PD.vehicle == nil and not def.Character.HumanoidRootPart.Anchored, "下车了，能走")
check(def.Character.Head.Transparency == 0, "人显出来了")
check(CD.drive == nil, "客户端退出驾驶")
act(def, "enterVeh", e.id)
H.run(1)
check(PD.vehicle == e and CD.drive ~= nil, "按 E 又坐回去了")

print("⑥ 被击毁：车组阵亡、名额冷却")
local used0 = G.vehAvail("def").tank.u
G.damageEnt(e, 1e6, { P = PA, team = PA.team, name = atk.DisplayName })
H.run(1)
check(not e.alive and e.wreck, "车被打爆、变成残骸")
check(not PD.alive, "车组阵亡")
check(G.vehAvail("def").tank.u == used0, "名额还占着（冷却中）：" .. G.vehAvail("def").tank.u .. "，要等 " .. G.vehAvail("def").tank.cd .. " 秒")

print("⑦ 攻方：登陆平台出生，水面上的生成点生成坦克（站在气垫艇上），连艇一起开到海滩，冲上岸艇放下车；两栖车下水自己游上岸")
local CA = H.Gs[atk.Name]
-- 摆车（测试里瞬移：服务器、客户端两边一起挪，不然服务器当成作弊拉回去）：base 是车底
local function placeVeh(pl, e, base)
	H.run(0.1)
	local root = base * CF.new(0, e.def.H / 2, 0)
	G.moveEnt(e, root)
	e.lastSync = os.clock()
	local st = H.Gs[pl.Name].drive
	if st then
		st.pos = base.Position
		local look = base.LookVector
		st.yaw = math.atan2(-look.X, -look.Z)
		st.speed = 0
		st.root = root
	end
end
act(atk, "deploy", "rifle", "barge")
H.run(2)
local hrpA = atk.Character and atk.Character:FindFirstChild("HumanoidRootPart")
check(PA.alive and hrpA and math.abs(hrpA.Position.Z - G.Map.BARGE.z) < G.Map.BARGE.L / 2 + 5 and hrpA.Position.Y > G.Map.BARGE.top, "步兵在登陆平台上出生")
local tkId = G.Config.Vehicles.atk.tank[3]
local tpA = H.pad(G, tkId)
check(tpA ~= nil and tpA.sea and tpA.team == "atk", "登陆平台边上有 " .. tkId .. " 的生成点（车在水面上）")
local et = H.usePad(G, atk, tpA)
check(et ~= nil and et.lcac ~= nil and et.model:GetAttribute("Lcac") == true, "坦克生成在气垫艇上")
act(atk, "enterVeh", et and et.id)
H.run(1)
check(et and PA.vehicle == et and CA.drive ~= nil, "从平台边上走过去坐上了")
if et and CA.drive then
	-- 往前开一段：连艇一起在海上走（不会游的车原来下不了水），艇跟着车
	local z0 = et.root.CFrame.Position.Z
	H.key(atk, Enum.KeyCode.W, true)
	H.run(4)
	local z1 = et.root.CFrame.Position.Z
	check(z0 - z1 > 100, string.format("站在气垫艇上往岛那边开了 %.0f 格", z0 - z1))
	local lp = et.lcac and et.lcac.root.CFrame.Position
	check(lp and math.abs(lp.Z - et.root.CFrame.Position.Z) < 8, "气垫艇跟着车走")
	-- 一路开到海滩要四十来秒：直接摆到蓝滩外 300 格（滩头通道正对着），接着往前开
	local b = G.Map.landingOf("blue")
	local p0 = V3.new(b.cx, G.LCAC.deck, b.z + b.dir * 300)
	placeVeh(atk, et, CF.lookAt(p0, p0 + V3.new(0, 0, -b.dir)))
	local landed = H.runUntil(function() return et.lcac == nil end, 30)
	H.run(1.5)
	H.key(atk, Enum.KeyCode.W, false)
	check(landed and et.model:GetAttribute("Lcac") == false, "冲上岸，气垫艇把车放下了")
	local q = et.root.CFrame.Position
	check(G.Map.height(q.X, q.Z) > 0.3, string.format("坦克在岸上（地面 %.1f）", G.Map.height(q.X, q.Z)))
	H.key(atk, Enum.KeyCode.F, true) H.key(atk, Enum.KeyCode.F, false)
	H.run(1)
end
-- 两栖车：在登陆平台生成（也坐气垫艇），上岸后从海里自己游回来（浮着 → 踩着海底 → 上岸，车身高度连续）
local ea = nil
local ap = H.pad(G, "zbd05")
if ap then ea = H.usePad(G, atk, ap) end
check(ea ~= nil and ea.lcac ~= nil, "两栖车 ZBD-05 也站在气垫艇上生成")
if ea then
	act(atk, "enterVeh", ea.id)
	H.run(1)
	local b = G.Map.landingOf("white")
	local p0 = V3.new(b.cx, G.LCAC.deck, b.z + b.dir * 260)
	placeVeh(atk, ea, CF.lookAt(p0, p0 + V3.new(0, 0, -b.dir)))
	H.key(atk, Enum.KeyCode.W, true)
	local landed = H.runUntil(function() return ea.lcac == nil end, 30)
	H.key(atk, Enum.KeyCode.W, false)
	check(landed, "两栖车随气垫艇上了岸")
	-- 再摆回海里 140 格（没有艇）：自己游
	local p1 = V3.new(b.cx, -ea.def.hullH * 0.55, b.z + b.dir * 140)
	placeVeh(atk, ea, CF.lookAt(p1, p1 + V3.new(0, 0, -b.dir)))
	H.key(atk, Enum.KeyCode.W, true)
	local track = {}
	local ashore = H.runUntil(function()
		local q = ea.root.CFrame.Position
		table.insert(track, q.Y)
		return G.Map.height(q.X, q.Z) > 1
	end, 40)
	H.key(atk, Enum.KeyCode.W, false)
	check(ashore, "两栖车自己游上了岸")
	local jump = 0
	for i = 2, #track do jump = math.max(jump, math.abs(track[i] - track[i - 1])) end
	check(jump < 0.8, string.format("上岸一路车身每帧高低最多变 %.2f 格", jump))
end

H.summary()
for i, w in ipairs(H.warns) do if i <= 8 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
