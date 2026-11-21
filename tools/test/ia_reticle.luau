--!nocheck
-- 准星（用户 11-19：船、坦克的准心可以不一样，参考 MWT 和现代战舰）
--   ① 坦克（MWT）：瞄着敌方坦克的正面，照服务器的跳弹算法给颜色——正对着打绿「可击穿」、斜 68° 黄「可能跳弹」、斜 79° 红「会跳弹」；
--      换 12.7 毫米机枪打坦克红「打不穿」；准星是四段弧，不是舰艇那套
--   ② 舰艇（《现代战舰》）：主炮落点的大圈、距离和炮弹飞多久；敌舰横着开过来：目标卡、提前量；换导弹：四个角框住，先琥珀「锁定中」再红「已锁定」
--   用法：lune run tools/test/ia_reticle.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum, Color3 = roblox.Vector3, roblox.CFrame, roblox.Enum, roblox.Color3
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function find(pl, name)
	for _, d in pl.PlayerGui:GetDescendants() do if d.Name == name then return d end end
end
local function same(a, b) return a and b and math.abs(a.R - b.R) < 0.02 and math.abs(a.G - b.G) < 0.02 and math.abs(a.B - b.B) < 0.02 end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
G.Config.VehicleCats.ship.min = 2
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 7401), H.addPlayer("P2", 7402)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)
local CD = H.Gs[def.Name]
H.runUntil(function() return G.round.phase == "battle" end, 120)
local VD = G.VehDefs or H.require(H.game:GetService("ReplicatedStorage"):FindFirstChild("VehDefs"))
-- 能击穿：黄绿（15e4802 界面蓝改绿以后，跟没瞄着车的绿分开；同 VehHud.lua 的 PEN_OK / PEN_MAYBE / PEN_NO）
local GREEN, YELLOW, RED = Color3.fromRGB(176, 255, 84), Color3.fromRGB(255, 214, 72), Color3.fromRGB(255, 72, 60)

print("① 坦克：MWT 式准星，打不打得穿")
local function act(...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = def
	local co = coroutine.create(function() CD.R.Act:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end
act("deploy", "rifle", "camp")
H.run(2)
local tp = H.pad(G, "m1a2")
local e = tp and H.usePad(G, def, tp)
if e then act("enterVeh", e.id) end
H.run(2)
local st = CD.drive
check(st ~= nil and st.d.id == "m1a2", "坐上了 M1A2")
local tr, sr = find(def, "TankReticle"), find(def, "ShipReticle")
check(tr ~= nil and tr.Visible and (sr == nil or not sr.Visible), "坦克用 MWT 那套（四段弧），舰艇那套不显示")
local base = e.root.CFrame * CF.new(0, -e.root.Size.Y / 2, 0)
local fp = (base * CF.new(0, 0, -160)).Position
local foe = G.spawnGroundVeh("atk", "ztz99a", CF.lookAt(fp, fp + base.LookVector), false, nil)
check(foe ~= nil, "前方 160 格放一辆攻方 99A，车头朝我")
H.run(1)
local gun = VD.W[st.d.weapons[1]]
local mg = VD.W[st.d.weapons[2]]
local r = foe.root.CFrame
local fc = (r * CF.new(0, 0, -foe.root.Size.Z / 2)).Position
local function shot(alpha, w)
	local a = math.rad(alpha)
	local o = fc + (r.LookVector * math.cos(a) + r.RightVector * math.sin(a)) * 25   -- 近一点：中间不会隔着山坡
	local col, txt
	H.ctx = def
	col, txt = CD.tankPen(w, o, fc, e.model)
	H.ctx = nil
	return col, txt
end
local c1, t1 = shot(20, gun)
check(same(c1, GREEN), "主炮正对着打（20°）：黄绿「" .. tostring(t1) .. "」")
local c2, t2 = shot(68, gun)
check(same(c2, YELLOW) and tostring(t2):find("%d") ~= nil, "斜 68°：黄「" .. tostring(t2) .. "」")
local c3, t3 = shot(79, gun)
check(same(c3, RED), "斜 79°：红「" .. tostring(t3) .. "」")
local c4, t4 = shot(10, mg)
check(same(c4, RED), "机枪打坦克：红「" .. tostring(t4) .. "」")
local c5 = select(1, (function()
	H.ctx = def
	local c = CD.tankPen(gun, fc + V3.new(0, 80, 0), fc + V3.new(0, 80, -40), e.model)
	H.ctx = nil
	return c
end)())
check(c5 == nil, "没瞄着车：不给颜色（白的）")
G.removeEnt(foe)
H.key(def, Enum.KeyCode.Space, true)
H.run(0.1)
H.key(def, Enum.KeyCode.Space, false)
H.run(1.5)

print("② 舰艇：《现代战舰》式准星")
local pd = H.pad(G, "ddg125")
local es = pd and H.usePad(G, def, pd)
H.run(2)
local sst = CD.sail
check(sst ~= nil, "坐上了 DDG-125")
if sst then
	local sfwd = V3.new(-math.sin(sst.yaw), 0, -math.cos(sst.yaw))
	local sright = V3.new(-sfwd.Z, 0, sfwd.X)
	sst.pos = sst.pos + sfwd * 700   -- 挪到外海（码头在崖下，镜头会钻进崖壁）
	sst.cf = CF.lookAt(sst.pos, sst.pos + sfwd)
	sst.speed, sst.order = 0, 0
	G.moveEnt(es, sst.cf * CF.new(0, es.sd.H / 2 - es.sd.draft, 0))
	es.lastSync, es.speed = os.clock(), 0
	H.run(1)
	local fp2 = es.root.CFrame.Position + sfwd * 1300
	local foeS = G.spawnShip("atk", "t022", CF.lookAt(V3.new(fp2.X, 0, fp2.Z), V3.new(fp2.X, 0, fp2.Z) + sright), nil)
	local function aim()
		local rel = foeS.root.CFrame.Position - H.workspace.CurrentCamera.CFrame.Position
		sst.camYaw = math.atan2(-rel.X, -rel.Z)
		sst.camPitch = math.asin(math.clamp(rel.Unit.Y, -1, 1))
	end
	for _ = 1, 50 do
		G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5)
		aim()
		H.run(0.1)
	end
	sr, tr = find(def, "ShipReticle"), find(def, "TankReticle")
	check(sr ~= nil and sr.Visible and not tr.Visible, "舰艇用《现代战舰》那套（大圈、四根长线），坦克那套不显示")
	local rng, tof = find(def, "FlightTime"), nil
	check(rng ~= nil and rng.Text:match("^T %d+%.%d s$") ~= nil, "写着炮弹飞多久：" .. tostring(rng and rng.Text))
	local card = find(def, "TargetCard")
	check(card ~= nil and card.Visible, "瞄着的敌舰上方有目标卡")
	check(CD.shipLead() ~= nil, "敌舰在开：画出提前量")
	H.key(def, Enum.KeyCode.Two, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.Two, false)
	for _ = 1, 3 do G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5) aim() H.run(0.1) end
	local vis1, col1 = CD.shipLockState()
	check(vis1 and same(col1, YELLOW), "换导弹：四个角框住，琥珀「锁定中」")
	for _ = 1, 8 do G.moveEnt(foeS, foeS.root.CFrame + sright * 4.5) aim() H.run(0.1) end
	local vis2, col2 = CD.shipLockState()
	check(vis2 and same(col2, RED), "半秒后红「已锁定」")
	local lt = find(def, "LockText")
	check(lt ~= nil and lt.Visible and lt.Text:find("km") ~= nil, "下面写距离、导弹飞过去要多久：" .. tostring(lt and lt.Text))
end

print(fails == 0 and "准星：全部通过" or ("准星：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
