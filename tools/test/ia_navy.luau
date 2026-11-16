--!nocheck
-- 舰艇测试（照 tools/mock/navy.lua）：码头、舰艇生成点（泊位在深水里、终端柱在岸上）→ 守方在营地崖顶的终端柱生成 DDG-125、直接上舰桥 →
--   车钟、舵、开船（客户端算、服务器跟）→ 舰炮跟着准星转、开火 → 反舰导弹框住敌舰、打沉 → 近防炮拦截来袭导弹 → 防空导弹打敌机 →
--   回码头补弹、修理 → 下船站到终端柱旁 → 攻方在登陆平台码头生成 055、开船、下船站在码头上、再按 E 上船 → 爆炸按船体方块算距离 →
--   击沉（开船的人阵亡、名额冷却、客户端看船下沉）→ 港口巡逻艇生成点要据点 C → AI 舰艇出来巡逻、开炮
-- 用法（仓库根目录）：lune run tools/test/ia_navy.luau <rbxlx> [v]
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
local function tap(pl, k) H.key(pl, k, true) H.key(pl, k, false) end
local function flat(v) return V3.new(v.X, 0, v.Z) end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true   -- 工事不开火（同 tools/mock/navy.lua：最后测 AI 舰艇时也不让岸防炮还手）
G.navyNoAI = true    -- AI 舰艇最后再放出来
G.Config.Bots.minPerTeam = 0
G.Config.VehicleCats.ship.min = 2   -- 测试只有两个人：名额按人数算是 0，这里放开
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 7001), H.addPlayer("P2", 7002)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local atk = (def == p1) and p2 or p1
local PD, PA = G.P[def], G.P[atk]
local CD, CA = H.Gs[def.Name], H.Gs[atk.Name]
local Map, SD = G.Map, G.ShipDefs

print("① 码头、舰艇生成点")
local shipPads = {}
for _, p in ipairs(G.pads or {}) do if p.kind == "ship" then table.insert(shipPads, p) end end
check(#shipPads == 8, "舰艇生成点 " .. #shipPads .. " 个（攻方 3、守方 4、港口 1）")
local piers = H.workspace:FindFirstChild("Map") and H.workspace.Map:FindFirstChild("Piers")
check(piers ~= nil and #piers:GetChildren() > 60, "码头零件 " .. (piers and #piers:GetChildren() or 0) .. " 个")
local wet, dry = 0, 0
for _, p in ipairs(shipPads) do
	local d = SD.get(p.vid)
	local ok = true
	for _, o in ipairs({ { 0, -d.L / 2 }, { 0, d.L / 2 }, { d.W / 2, 0 }, { -d.W / 2, 0 }, { 0, 0 }, { d.W / 2, d.L / 2 }, { -d.W / 2, d.L / 2 } }) do
		local q = (p.base * CF.new(o[1], 0, o[2])).Position
		if Map.height(q.X, q.Z) > -d.draft * 0.35 then ok = false end
	end
	if ok then wet += 1 else print("    浅水：" .. p.vid) end
	if (p.ty or Map.ground(p.term.X, p.term.Z)) >= 0.5 then dry += 1 end
end
check(wet == #shipPads, "泊位都在够深的水里（" .. wet .. "/" .. #shipPads .. "）")
check(dry == #shipPads, "终端柱都在岸上、码头上（" .. dry .. "/" .. #shipPads .. "）")
check(CD.S.vehAvail and CD.S.vehAvail.ship and CD.S.vehAvail.ship.cap >= 1, "客户端拿到舰艇名额：" .. tostring(CD.S.vehAvail and CD.S.vehAvail.ship and CD.S.vehAvail.ship.cap))

print("② 守方在营地出生，走到崖顶的舰艇终端柱按 E：DDG-125 生成在崖下码头，人直接上舰桥")
act(def, "deploy", "rifle", "camp")
H.run(2)
check(PD.alive and def.Character ~= nil, "守方在营地出生")
local pd = H.pad(G, "ddg125")
check(pd ~= nil and pd.prompt.ObjectText == CD.T("veh.ddg125"), "终端柱按键文字照客户端的语言：" .. tostring(pd and pd.prompt.ObjectText))
local e = pd and H.usePad(G, def, pd)
check(e ~= nil and e.ship and e.sd.id == "ddg125", "生成了 DDG-125")
check(e ~= nil and e.driver == PD and PD.vehicle == e, "生成的人直接坐上舰桥")
check(def.Character and def.Character.HumanoidRootPart.Anchored and def.Character.Head.Transparency == 1, "人藏起来、锚定在船里")
H.run(1)
check(CD.sail ~= nil and e ~= nil and CD.sail.id == e.id, "客户端接管开船")
local v = CD.views and e and (function() for em, vv in pairs(CD.views) do if em == e.model then return vv end end end)()
check(v ~= nil and v.M ~= nil and #v.M.items > 60, "客户端拼好了舰艇：" .. (v and v.M and #v.M.items or 0) .. " 个零件")
local nOk = 0
for id in pairs(SD.D) do
	local ok, M = pcall(CD.buildShipModel, SD.get(id), "def")
	if ok and M and #M.items > 12 then
		nOk += 1
		M.model:Destroy()
	else
		print("    拼不出来：" .. id .. " " .. tostring(M))
	end
end
check(nOk == 7, "七型舰艇的模型都拼得出来（" .. nOk .. "/7）")

print("③ 开船：车钟加到前进四，往北开；左舵转向，松开回舵")
local st = CD.sail
local q0 = e.root.CFrame.Position
for _ = 1, 4 do tap(def, Enum.KeyCode.W) end
H.run(0.2)
check(st.order == 4, "车钟：" .. CD.T("ship.order." .. st.order))
H.run(10)
local q1 = e.root.CFrame.Position
local moved = (flat(q1) - flat(q0)).Magnitude
check(moved > 80, string.format("开出去 %.0f 格（服务器上的船跟着走）", moved))
check(q1.Z < q0.Z - 60, "朝北开（离开岸边）")
check((st.pos - flat(q1)).Magnitude < 25, "客户端、服务器位置一致")
check(e.speed > 10 and math.abs(e.speed - st.speed) < 6, string.format("航速 %.0f 格/秒", e.speed))
local yaw0 = st.yaw
H.key(def, Enum.KeyCode.A, true)
H.run(5)
check(st.rudder < -0.5, "舵打过去了")
H.key(def, Enum.KeyCode.A, false)
check(math.deg(st.yaw - yaw0) > 8, string.format("左舵转了 %.0f°", math.deg(st.yaw - yaw0)))
H.run(2)
check(math.abs(st.rudder) < 0.3, "松开回正舵")

print("④ 开战：舰炮跟着准星转、开火")
H.runUntil(function() return G.round.phase == "battle" end, 60)
st.order = 0
st.camYaw, st.camPitch = st.yaw, -0.06
H.run(3)
local nx0 = e.next[1]
H.mouseDown(def, 640, 360)
H.run(0.05)
local rec = v and v.rec[1] or 0
H.run(0.25)
H.mouseUp(def, 640, 360)
H.run(0.3)
local shell = false
for _, s in ipairs(G.shots) do if s.byEnt == e.id and s.kind == "shell" then shell = true end end
check(e.next[1] > nx0 and shell, "主炮打出一发（炮弹在飞）")
check(math.abs(e.ty[1] - st.ty[1]) < 3 and math.abs(e.gp[1] - st.gp[1]) < 3, string.format("服务器的炮塔角跟客户端一致（方位 %.0f°、俯仰 %.0f°）", e.ty[1], e.gp[1]))
check(rec > 0.3, string.format("客户端：炮管后坐 %.1f 格", rec))

print("⑤ 反舰导弹：准星对着敌舰自动框住，左键发射，打沉")
local fp = (e.root.CFrame * CF.new(0, 0, -1500)).Position
local foeShip = G.spawnShip("atk", "t022", CF.lookAt(V3.new(fp.X, 0, fp.Z), V3.new(fp.X + 1, 0, fp.Z)), nil)
check(foeShip ~= nil, "正前方 1500 格放一艘攻方 022")
H.run(1)
local rel = flat(foeShip.root.CFrame.Position) - st.pos
st.camYaw, st.camPitch = math.atan2(-rel.X, -rel.Z), -0.04
tap(def, Enum.KeyCode.Two)
H.run(0.6)
check(st.wi == 2, "换到反舰导弹")
check(st.lock ~= nil and st.lock.id == foeShip.id, "框住了敌舰")
local msl0 = e.msl
H.mouseDown(def, 640, 360)
H.run(0.1)
H.mouseUp(def, 640, 360)
H.run(0.5)
check(e.msl == msl0 - 1, string.format("发射了一枚（%d → %d）", msl0, e.msl))
H.runUntil(function() return not foeShip.alive end, 15)
check(not foeShip.alive, "打沉了敌舰")
tap(def, Enum.KeyCode.One)

print("⑥ 近防炮拦截来袭的反舰导弹（命中率设成必中 / 必不中各打一发）")
local bp = (e.root.CFrame * CF.new(-300, 0, -1800)).Position
local foe2 = G.spawnShip("atk", "t022", CF.lookAt(V3.new(bp.X, 0, bp.Z), V3.new(bp.X, 0, bp.Z - 1)), nil)
H.run(0.5)
local hp0 = e.hp
SD.W.ciws.kill = 1
check(G.navyFireMissile(foe2, e.id), "敌舰朝我发射")
H.run(12)
check(e.hp >= hp0 - 1, string.format("近防炮打掉了（血 %.0f → %.0f）", hp0, e.hp))
SD.W.ciws.kill = 0
H.run(1.5)
check(G.navyFireMissile(foe2, e.id), "再发一枚")
H.run(12)
check(e.hp < hp0 - 100, string.format("近防炮没拦住，挨了一发（血 %.0f）", e.hp))
SD.W.ciws.kill = 0.55
G.removeEnt(foe2)

print("⑦ 防空导弹打敌机")
local ap = (e.root.CFrame * CF.new(0, 0, -900)).Position + V3.new(0, 600, 0)
local jet = G.spawnAircraft("atk", "j20", CF.lookAt(ap, ap + V3.new(1, 0, 0)), nil, nil)
check(jet ~= nil, "头顶 900 格外放一架攻方歼-20")
if jet then
	jet.onGround = false
	local sam0 = e.samN
	H.run(1)
	check(e.samN < sam0, string.format("发射了防空导弹（%d → %d）", sam0, e.samN))
	H.runUntil(function() return jet.lastHitBy ~= nil end, 10)
	check(jet.lastHitBy ~= nil and jet.lastHitBy.team == "def", "打中了敌机")
end

print("⑧ 回码头停稳：导弹补满、修理")
local hb = pd.base
st.pos = flat(hb.Position)
st.yaw = math.atan2(-hb.LookVector.X, -hb.LookVector.Z)
st.speed, st.order = 0, 0
st.cf = CF.lookAt(st.pos, st.pos + hb.LookVector)
G.moveEnt(e, hb * CF.new(0, e.sd.H / 2 - e.sd.draft, 0))
e.lastSync, e.speed = os.clock(), 0
local hpA = e.hp
H.run(8)
check(e.msl == e.sd.missiles.n and e.samN == e.sd.sam.n, string.format("导弹补满（反舰 %d、防空 %d）", e.msl, e.samN))
check(e.hp > hpA, string.format("在修（血 %.0f → %.0f）", hpA, e.hp))

print("⑨ 下船：站到崖顶的终端柱旁边")
tap(def, Enum.KeyCode.F)
H.run(1)
check(PD.vehicle == nil and def.Character and not def.Character.HumanoidRootPart.Anchored, "下船了，能走")
local hp = def.Character.HumanoidRootPart.Position
check((flat(hp) - flat(pd.term)).Magnitude < 8 and hp.Y > 40, string.format("站在崖顶终端柱旁（高 %.0f）", hp.Y))
check(CD.sail == nil and CD.drive == nil, "客户端退出开船")

print("⑩ 攻方：登陆平台码头生成 055、开船，回来下船站在码头上，再按 E 上船")
act(atk, "deploy", "rifle", "barge")
H.run(2)
local p5 = H.pad(G, "t055")
local e5 = p5 and H.usePad(G, atk, p5)
check(e5 ~= nil and e5.driver == PA, "攻方生成 055、上了舰桥")
if e5 then
	H.run(1)
	local sa = CA.sail
	check(sa ~= nil and sa.id == e5.id, "攻方客户端接管开船")
	local z0 = e5.root.CFrame.Position.Z
	tap(atk, Enum.KeyCode.W) tap(atk, Enum.KeyCode.W)
	H.run(6)
	check(e5.root.CFrame.Position.Z < z0 - 15, string.format("离开码头往北开了 %.0f 格", z0 - e5.root.CFrame.Position.Z))
	tap(atk, Enum.KeyCode.S) tap(atk, Enum.KeyCode.S)
	H.run(1)
	-- 摆回泊位（两边一起挪）再下船
	if sa then
		sa.pos = flat(p5.base.Position)
		sa.yaw, sa.speed, sa.order = math.atan2(-p5.base.LookVector.X, -p5.base.LookVector.Z), 0, 0
		sa.cf = CF.lookAt(sa.pos, sa.pos + p5.base.LookVector)
	end
	G.moveEnt(e5, p5.base * CF.new(0, e5.sd.H / 2 - e5.sd.draft, 0))
	e5.lastSync = os.clock()
	H.run(0.5)
	drive(atk, { op = "exit" })
	H.run(0.5)
	check(PA.vehicle == nil, "下船")
	local fp2 = atk.Character.HumanoidRootPart.Position
	check(math.abs(fp2.Y - (Map.BARGE.top + 3.5)) < 2 and (flat(fp2) - flat(p5.term)).Magnitude < 8, "站在码头上终端柱旁")
	act(atk, "enterVeh", e5.id)
	H.run(0.5)
	check(PA.vehicle == e5 and e5.driver == PA, "在码头上按 E 又上了船")
end

print("⑪ 爆炸按船体方块算距离")
if e5 then
	local W = { dmg = 300, splash = 30, vs = { ship = 1, inf = 0 } }
	local hp1 = e5.hp
	G.explode((e5.root.CFrame * CF.new(e5.sd.W / 2 + 45, 0, -e5.sd.L * 0.3)).Position, W, { team = "def" })
	check(e5.hp == hp1, "船舷外 45 格（离船中心不到船长一半）的爆炸不伤船")
	G.explode((e5.root.CFrame * CF.new(e5.sd.W / 2 + 4, 0, e5.sd.L * 0.4)).Position, W, { team = "def" })
	check(e5.hp < hp1, "贴着船舷的爆炸伤到了")
end

print("⑫ 击沉：开船的人阵亡、名额冷却、客户端看到船沉下去")
if e5 then
	local used0 = G.vehAvail("atk").ship.u
	G.damageEnt(e5, 1e6, { P = PD, team = "def", name = def.DisplayName })
	H.run(1)
	check(not e5.alive and e5.wreck, "被击沉")
	check(not PA.alive, "开船的人阵亡")
	check(G.vehAvail("atk").ship.u == used0, "名额还占着（冷却中）")
	local v5 = (function() for em, vv in pairs(CD.views or {}) do if em == e5.model then return vv end end end)()
	H.run(3)
	check(v5 ~= nil and (v5.sinkT or 0) > 2, "客户端：船在往下沉")
end

print("⑬ 港口的巡逻艇生成点：据点 C 丢了就不能用")
local portPad
for _, p in ipairs(shipPads) do if p.need == "C" then portPad = p end end
check(portPad ~= nil and G.padOpen(portPad, "def"), "港口巡逻艇生成点开着")
local own0 = G.points.C.owner
G.points.C.owner = "atk"
check(portPad ~= nil and not G.padOpen(portPad, "def"), "据点 C 丢了：关了")
G.points.C.owner = own0

print("⑭ AI 舰艇：攻方 054A 在南面近海巡逻、炮击岸上；守方巡逻艇在港湾里")
G.navyNoAI = false
local function aiOf(team)
	for _, x in ipairs(G.ships) do if x.ai and x.team == team and x.alive then return x end end
	return nil
end
H.runUntil(function() return aiOf("atk") ~= nil and aiOf("def") ~= nil end, 5)
local ai, aiD = aiOf("atk"), aiOf("def")
check(ai ~= nil and ai.sd.id == "t054a", "攻方 AI 054A 出来了")
check(aiD ~= nil and aiD.sd.id == "pbr", "守方 AI 巡逻艇出来了")
if ai then
	local fired = 0
	local launch0 = G.launch
	G.launch = function(s)
		if s.byEnt == ai.id then fired += 1 end
		return launch0(s)
	end
	local a0 = ai.root.CFrame.Position
	H.run(25)
	G.launch = launch0
	check((ai.root.CFrame.Position - a0).Magnitude > 100, string.format("在巡逻（走了 %.0f 格）", (ai.root.CFrame.Position - a0).Magnitude))
	check(fired >= 2, "炮击了岸上目标 " .. fired .. " 发")
end

H.summary()
for i, w in ipairs(H.warns) do if i <= 8 then print("  警告：" .. w.side .. " " .. w.msg) end end
for i, x in ipairs(H.errors) do if i <= 8 then print("  错误：" .. tostring(x.side) .. " " .. tostring(x.msg)) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
