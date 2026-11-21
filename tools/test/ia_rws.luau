--!nocheck
-- 遥控武器站测试（M1A2 的 CROWS + M2）：用户 11-18「观瞄系统位置要对、机枪也要能转动、开火位置和枪口对上、弹道顺着枪管和炮管」
--   守方开一辆 M1A2：型号表照原模型有遥控站、机枪那栏是 12.7 毫米机枪、炮长镜在模型的镜头上；准心转到右边，遥控站自己转过去；
--   开机枪：服务器那发子弹从 M2 枪口出、方向就是枪管方向；开主炮：炮弹从炮口出、方向就是炮管方向
-- 用法（仓库根目录）：lune run tools/test/ia_rws.luau <rbxlx>
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
H.run(0.5)
local G = H.Gs.server
G.fortsHold, G.navyNoAI = true, true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 5001), H.addPlayer("P2", 5002)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local PD, CD = G.P[def], H.Gs[def.Name]
local VD = H.require(H.game:GetService("ReplicatedStorage"):FindFirstChild("VehDefs"))
local d = VD.get("m1a2")
print("① 型号表")
check(d.rws ~= nil, "M1A2 有遥控武器站（照原模型）")
check(d.weapons[2] == "hmg", "机枪那栏换成 12.7 毫米机枪：" .. table.concat(d.weapons, ","))
check(d.sight and d.sight.X > 0.3 and d.sight.Y > 1, string.format("炮长镜在炮塔右前方（相对炮塔转轴 %.2f, %.2f, %.2f）", d.sight.X, d.sight.Y, d.sight.Z))
if not d.rws then H.summary() process.exit(1) end
local base0 = CF.new(0, 0, 0)
local m0 = VD.muzzle(d, base0, 0, 0, "rws", 0, 0)
local piv0 = (VD.turretCF(d, base0, 0) * CF.new(d.rws.pivot)).Position
check(m0.Position.Z < piv0.Z - 1.5 and math.abs(m0.Position.X - piv0.X) < 0.2, string.format("枪口在底座前面 %.1f 格", piv0.Z - m0.Position.Z))

print("② 守方开一辆 M1A2")
CD.deploySel.spawn, CD.deploySel.role = "camp", "engineer"
H.leaveMenu(def)
CD.refreshDeploy()
H.click(def, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
local tp = H.pad(G, "m1a2")
local e = tp and H.usePad(G, def, tp)
check(e ~= nil and e.def.id == "m1a2", "生成了 M1A2")
if not e then H.summary() process.exit(1) end
local hrp = def.Character.HumanoidRootPart
hrp.CFrame = CF.new(e.root.CFrame.Position + V3.new(0, 6, 0))
H.run(0.3)
local function as(pl, f) local prev = H.ctx H.ctx = pl local co = coroutine.create(f) coroutine.resume(co) H.ctx = prev end
as(def, function() CD.R.Act:FireServer("enterVeh", e.id) end)
H.run(1.5)
local st = CD.drive
check(st ~= nil and PD.vehicle == e, "坐进去了")
if not st then H.summary() process.exit(1) end

print("③ 准心转到右后方：遥控站自己转过去，比炮塔快")
local base = st.root * CF.new(0, -d.H / 2, 0)
local target = (base * CF.new(60, 6, 40)).Position   -- 右后方
-- 镜头转过去（客户端每帧按镜头重新算准心落点）
local function lookAt(p)
	local dir = p - st.root.Position
	st.camYaw, st.camPitch = math.atan2(-dir.X, -dir.Z), -0.04
end
local ty0 = st.ty
for i = 1, 30 do lookAt(target) H.run(1 / 30) end   -- 1 秒
local myW, mpW = VD.rwsAim(d, st.root * CF.new(0, -d.H / 2, 0), st.ty, st.aimPt)
local turned = math.abs(((st.ty - ty0 + 180) % 360) - 180)
check(math.abs(st.my) > 60, string.format("1 秒里遥控站转了 %.0f°（炮塔转了 %.0f°）：比炮塔快", st.my, turned))
for i = 1, 60 do lookAt(target) H.run(1 / 30) end
myW, mpW = VD.rwsAim(d, st.root * CF.new(0, -d.H / 2, 0), st.ty, st.aimPt)
check(math.abs(((st.my - myW + 180) % 360) - 180) < 4, string.format("遥控站对准了准心（%.0f°，要 %.0f°）", st.my, myW))
H.run(0.5)
check(math.abs((e.model:GetAttribute("My") or 0) - st.my) < 6, "服务器记下了遥控站的转角：" .. tostring(e.model:GetAttribute("My")))

print("④ 开机枪：子弹从 M2 枪口出、顺着枪管")
H.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
local shots = {}
local bs0 = G.botShot
G.botShot = function(from, to, w, ...) table.insert(shots, { from = from, to = to }) return bs0(from, to, w, ...) end
st.wi = 2
for i = 1, 6 do lookAt(target) H.run(1 / 30) end
as(def, function() CD.driveTryFire() end)
H.run(0.3)
G.botShot = bs0
local sh = shots[#shots]
check(sh ~= nil, "服务器开了一枪（" .. #shots .. " 发）")
if sh then
	local bse = G.vehBaseOf and G.vehBaseOf(e) or (e.root.CFrame * CF.new(0, -d.H / 2, 0))
	local mz = VD.muzzle(d, bse, e.ty, e.gp, "rws", e.my, e.mp)
	local off = (sh.from - mz.Position).Magnitude
	local dir = (sh.to - sh.from).Unit
	local ang = math.deg(math.acos(math.clamp(dir:Dot(mz.LookVector), -1, 1)))
	check(off < 0.6, string.format("子弹从 M2 枪口出（差 %.2f 格）", off))
	check(ang < 1.2, string.format("方向顺着枪管（差 %.2f°，只有机枪本身的散布）", ang))
	local cmz = VD.muzzle(d, st.root * CF.new(0, -d.H / 2, 0), st.ty, st.gp, "rws", st.my, st.mp)
	check((cmz.Position - sh.from).Magnitude < 1.5, string.format("和客户端画面上的枪口对得上（差 %.2f 格）", (cmz.Position - sh.from).Magnitude))
end
print("⑤ 每型坦克都有会转的车顶机枪（用户 11-19：坦克的机枪要能转，开火位置要在机枪）；99A 是车长舱口一挺手动的 12.7 毫米重机枪，并列机枪也留着（用户 11-21 晚）")
local VMm
H.ctx = def
VMm = H.require(def.PlayerScripts:FindFirstChild("Client", true):FindFirstChild("VehModels"))
H.ctx = nil
for _, side in ipairs({ "def", "atk" }) do
	for _, vid in ipairs(G.Config.Vehicles[side].tank) do
		local dd = VD.get(vid)
		local ok = dd.rws ~= nil and table.find(dd.weapons, "hmg") ~= nil and (dd.rws.mk == "manual" or not table.find(dd.weapons, "coax"))   -- 手动重机枪（99A）：并列机枪留着
		local mz = dd.rws and VD.muzzle(dd, base0, 30, 0, "rws", 25, 5)
		local pv = dd.rws and (VD.turretCF(dd, base0, 30) * CF.new(dd.rws.pivot)).Position
		local fwd = mz and pv and (mz.Position - pv).Magnitude or 0
		-- 模型：遥控站底座（rws）、机枪（rwg）都有零件（导入的原模型或者零件拼的）
		local nR, nG = 0, 0
		if VMm and VMm.build then
			local okB, M = pcall(VMm.build, dd, side)
			if okB and M then
				for _, it in ipairs(M.parts) do
					if it[2] == "rws" then nR += 1 elseif it[2] == "rwg" then nG += 1 end
				end
				M.model:Destroy()
			end
		end
		if dd.noRoofMg then
			check(dd.rws == nil and table.find(dd.weapons, "coax") ~= nil and nR == 0 and nG == 0, string.format("%s：车顶不放机枪（遥控站 %s，机枪栏 %s，零件 底座 %d 机枪 %d）",
				vid, tostring(dd.rws ~= nil), table.concat(dd.weapons, ","), nR, nG))
		else
			check(ok and fwd > 1.2 and nR > 0 and nG > 0, string.format("%s：遥控站 %s，机枪栏 %s，枪口离座圈 %.1f 格，零件 底座 %d 机枪 %d",
				vid, tostring(dd.rws ~= nil), table.concat(dd.weapons, ","), fwd, nR, nG))
			if dd.rws and dd.rws.mk == "manual" then
				check(table.find(dd.weapons, "coax") ~= nil and table.find(dd.weapons, "hmg") ~= nil, string.format("%s：手动重机枪，并列机枪也留着（机枪栏 %s）", vid, table.concat(dd.weapons, ",")))
			end
		end
	end
end
H.summary()
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
