--!nocheck
-- 舰艇武器（用户 11-19：船的建模换成 Sketchfab 上好的；所有船上的武器都能有作用、能动）
--   ① 原模型的部件（测试里在 ReplicatedStorage.Imported.Ship.<型号> 放同名的方块代替 Studio 导入的网格）：
--      054A 的炮塔、炮管、两座近防炮分成会动的部件；元数据有炮管耳轴、近防炮的朝向、垂发格子、发射箱
--   ② 炮管：跟着炮塔转、绕耳轴俯仰——炮管的中心落在服务器算的炮膛线上（炮弹从看得见的炮口出去），炮口在炮管尖上
--   ③ 近防炮：敌舰朝 054A、DDG-125 各打一枚反舰导弹 → 服务器每座近防炮各自开火（带船的编号、第几座）→
--      客户端那一座转向导弹（原模型的整座、零件拼的那座都转）
--   ④ 斜置发射箱（054A 的鹰击-83）：导弹从箱口顺着箱子冲出去；客户端箱口崩盖子、箱尾喷气
--   ⑤ 垂发（054A 的海红旗-16）：防空导弹从一个格子竖直窜出去；客户端掀开那一格的舱盖、几秒后合上去掉
--   用法：lune run tools/test/ia_shipwpn.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function angDiff(a, b) return (b - a + 180) % 360 - 180 end

H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local RS = H.game:GetService("ReplicatedStorage")
local IS = H.require(RS:FindFirstChild("ImportedShip"))
local SD = G.ShipDefs

print("① 原模型的部件、元数据")
local info = IS.m.t054a
check(info.guns[1].b == "B1" and info.guns[1].trn ~= nil, "054A 主炮：炮管单独一块（B1），有耳轴")
check(info.ciws and #info.ciws == 2 and info.ciws[1].g == "C1" and info.ciws[2].g == "C2", "两座近防炮各是一块（C1、C2）")
check(info.vls and #info.vls == 1 and info.cans and #info.cans == 2, "一块垂发、两组斜置发射箱")
local d054 = SD.get("t054a")
check(d054.guns[1].trn ~= nil and math.abs(d054.guns[1].len - (info.guns[1].tip + (info.guns[1].trn[3] - info.guns[1].piv[3]))) < 0.01, "ShipDefs：耳轴、炮管长照原模型")
check(#d054.ciws == 2 and math.abs(d054.ciws[1].X - info.ciws[1].piv[1]) < 0.01, "ShipDefs：近防炮照原模型的位置")
for _, id in ipairs({ "t055", "ddg125", "cg47", "t054a", "t022" }) do
	local m = IS.m[id]
	local nb, nc = 0, 0
	for _, g in ipairs(m.guns) do if g and g.b then nb += 1 end end
	for _, c in ipairs(m.ciws or {}) do if c.g then nc += 1 end end
	check(nb == #m.guns and nc == #(m.ciws or {}), string.format("%s：%d 门炮的炮管都分出来了，%d 座近防炮", id, nb, nc))
end
-- 假装 Studio 导入了 054A：ReplicatedStorage.Imported.Ship.t054a 下放同名零件
local imp = RS:FindFirstChild("Imported") or Instance.new("Folder")
imp.Name = "Imported"
imp.Parent = RS
local shipF = imp:FindFirstChild("Ship") or Instance.new("Folder")
shipF.Name = "Ship"
shipF.Parent = imp
local f = Instance.new("Folder")
f.Name = "t054a"
local n = 0
for name, p in pairs(info.parts) do
	local part = Instance.new("Part")
	part.Name = "S_t054a__" .. name
	part.Size = V3.new(p.s[1], p.s[2], p.s[3])
	part.Parent = f
	n += 1
end
f:SetAttribute("N", n)
f.Parent = shipF

local p1, p2 = H.addPlayer("P1", 7301), H.addPlayer("P2", 7302)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)
local CD = H.Gs[def.Name]
H.runUntil(function() return G.round.phase == "battle" end, 120)
H.run(0.5)

local pd = H.pad(G, "ddg125")
local base = pd.base * CF.new(0, 0, -700)
local e054 = G.spawnShip("def", "t054a", base, nil)
local eddg = G.spawnShip("def", "ddg125", base * CF.new(140, 0, 0), nil)
check(e054 ~= nil and eddg ~= nil, "守方 054A、DDG-125 停在海上")
H.run(2)
local function viewOf(e)
	for em, vv in pairs(CD.views or {}) do if em == e.model then return vv end end
end
local v = viewOf(e054)
local vd = viewOf(eddg)
check(v ~= nil and v.M ~= nil and v.M.imported == "t054a", "客户端用的是原模型")
local count = { ti = 0, bi = 0, c = 0 }
for _, it in ipairs(v and v.M.items or {}) do if count[it.g] then count[it.g] += 1 end end
check(count.ti >= 1 and count.bi >= 1 and count.c >= 2, string.format("炮塔 %d 块、炮管 %d 块、近防炮 %d 块会动", count.ti, count.bi, count.c))
local cProc = 0
for _, it in ipairs(vd and vd.M.items or {}) do if it.g == "c" then cProc += 1 end end
check(vd ~= nil and not vd.M.imported and cProc >= 4, "DDG-125 没导入：零件拼的近防炮 " .. cProc .. " 块也会转")

print("② 炮管：跟着炮塔转、绕耳轴俯仰，中心在炮膛线上")
local function shipCF(vv)   -- 客户端这一帧摆船用的 CFrame（随浪起伏）：从一块船体零件倒推
	for _, it in ipairs(vv.M.items) do
		if it.g == "hull" and not it.tag then return it.p.CFrame * it.off:Inverse() end
	end
end
local function boreCheck(ty, gp)
	e054.ty[1], e054.gp[1] = ty, gp
	e054.model:SetAttribute("Ty1", ty)
	e054.model:SetAttribute("Gp1", gp)
	H.run(1.5)
	local cf = shipCF(v)
	local gcf = SD.gunCF(d054, cf, 1, v.ty[1], v.gp[1])
	local worst, far = 0, 0
	for _, it in ipairs(v.M.items) do
		if it.g == "bi" then
			local rel = gcf:PointToObjectSpace(it.p.CFrame.Position)
			worst = math.max(worst, math.sqrt(rel.X * rel.X + rel.Y * rel.Y))
			far = math.max(far, -rel.Z)
		end
	end
	local mz = SD.muzzle(d054, cf, 1, v.ty[1], v.gp[1]).Position
	check(worst < 0.6 and far > 0.5 and far < d054.guns[1].len,
		string.format("方位 %d°、俯仰 %d°：炮管中心离炮膛线 %.2f 格、在耳轴前 %.1f 格（炮口在 %.1f 格）", ty, gp, worst, far, d054.guns[1].len))
	return mz
end
local mzA = boreCheck(0, 0)
local mzB = boreCheck(40, 30)
check((mzB - mzA).Magnitude > 3 and mzB.Y > mzA.Y + 1.5, string.format("转了、抬了：炮口挪了 %.1f 格、高了 %.1f 格", (mzB - mzA).Magnitude, mzB.Y - mzA.Y))

print("③ 近防炮：来袭的导弹 → 服务器每座各自开火（带船的编号、第几座）→ 客户端那一座转过去")
local fxLog = {}
local fx0 = G.fx
G.fx = function(ev)
	if type(ev) == "table" then table.insert(fxLog, ev) end
	return fx0(ev)
end
local function cPose(vv, mi)   -- 第 mi 座近防炮相对船的朝向
	local cf = shipCF(vv)
	for _, it in ipairs(vv.M.items) do
		if it.g == "c" and it.i == mi then return cf:ToObjectSpace(it.p.CFrame) end
	end
end
local pose0 = { cPose(v, 1), cPose(v, 2) }
local poseD = cPose(vd, 1)
local fp = (e054.root.CFrame * CF.new(-200, 0, -1700)).Position
local foe = G.spawnShip("atk", "t022", CF.lookAt(V3.new(fp.X, 0, fp.Z), V3.new(fp.X, 0, fp.Z - 1)), nil)
H.run(0.5)
SD.W.ciws.kill = 1
check(G.navyFireMissile(foe, e054.id), "敌舰朝 054A 发射")
H.run(1.3)
check(G.navyFireMissile(foe, eddg.id), "敌舰朝 DDG-125 发射")
-- 打的时候一帧帧看近防炮转了多少（拦下来三秒后又转回原位）
local maxRot = { 0, 0 }
local maxRotD = 0
local function rotOf(a, b) return (a and b) and math.deg(math.acos(math.clamp(a.LookVector:Dot(b.LookVector), -1, 1))) or 0 end
for _ = 1, 110 do
	H.run(0.1)
	for mi = 1, 2 do maxRot[mi] = math.max(maxRot[mi], rotOf(cPose(v, mi), pose0[mi])) end
	maxRotD = math.max(maxRotD, rotOf(cPose(vd, 1), poseD))
end
local ciwsFx = {}
for _, ev in ipairs(fxLog) do
	if ev.k == "gun" and ev.w == "ciws" then
		ciwsFx[ev.id .. ":" .. tostring(ev.mi)] = (ciwsFx[ev.id .. ":" .. tostring(ev.mi)] or 0) + 1
	end
end
local n054 = (ciwsFx[e054.id .. ":1"] or 0) + (ciwsFx[e054.id .. ":2"] or 0)
check(n054 > 0 and (ciwsFx[eddg.id .. ":1"] or 0) + (ciwsFx[eddg.id .. ":2"] or 0) > 0, string.format("两条船的近防炮都开火了（054A %d 串，带船号和第几座）", n054))
local turned = 0
for mi = 1, 2 do
	local was = v.cyAt and v.cyAt[mi] or -1e9
	local ry = d054.ciwsInfo[mi].ry
	if was > 0 then
		local dRot = maxRot[mi]
		print(string.format("    第 %d 座：原来朝 %.0f°，打的时候转到 %.0f°（零件最多转了 %.0f°）", mi, ry, v.cyT[mi], dRot))
		if math.abs(angDiff(ry, v.cyT[mi])) > 20 and dRot > 10 then turned += 1 end
	end
end
check(turned >= 1, "054A 的近防炮（原模型的整座）转向来袭的导弹：" .. turned .. " 座")
check(maxRotD > 10, string.format("DDG-125 零件拼的近防炮也转了（最多 %.0f°）", maxRotD))
H.run(4)
check(rotOf(cPose(v, 1), pose0[1]) < 2 and rotOf(cPose(v, 2), pose0[2]) < 2, "不打了：三秒后转回原位")
SD.W.ciws.kill = 0.55

print("④ 斜置发射箱：054A 的反舰导弹从箱口顺着箱子冲出去，箱口崩盖子、箱尾喷气")
local can0 = CD.shipCanCount or 0
fxLog = {}
local shots0 = {}
for _, s in ipairs(G.shots) do shots0[s] = true end
e054.mslAt = 0
check(G.navyFireMissile(e054, foe.id), "054A 发射")
H.run(0.05)
local vlsEv = nil
for _, ev in ipairs(fxLog) do if ev.k == "vls" and ev.id == e054.id then vlsEv = ev end end
check(vlsEv ~= nil and vlsEv.can ~= nil, "服务器说从第 " .. tostring(vlsEv and vlsEv.can) .. " 组箱子出去")
local msl = nil
for _, s in ipairs(G.shots) do if not shots0[s] and s.byEnt == e054.id then msl = s end end
if vlsEv and vlsEv.can and msl then
	local c = d054.cans[vlsEv.can]
	local cf = e054.root.CFrame * CF.new(0, -(d054.H / 2 - d054.draft), 0)
	local mouth = (cf * SD.canTube(d054, vlsEv.can, vlsEv.tube)).Position
	local axis = (cf * SD.canCF(d054, vlsEv.can)).LookVector
	check((msl.pos - mouth).Magnitude < 8, string.format("导弹在箱口（差 %.1f 格）", (msl.pos - mouth).Magnitude))
	check(msl.vel.Unit:Dot(axis) > 0.9, string.format("顺着箱子的方向（朝 %.0f°、仰 %.0f°）", c.yaw, c.pitch))
end
H.run(0.5)
check((CD.shipCanCount or 0) > can0, "客户端：箱口崩盖子、箱尾喷气")

print("⑤ 垂发：防空导弹从一个格子竖直窜出去，客户端掀开那一格的舱盖")
local lid0 = CD.shipLidCount or 0
fxLog = {}
local ap = (e054.root.CFrame * CF.new(0, 0, -900)).Position + V3.new(0, 500, 0)
local jet = G.spawnAircraft("atk", "j20", CF.lookAt(ap, ap + V3.new(1, 0, 0)), nil, nil)
check(jet ~= nil, "头顶放一架攻方歼-20")
if jet then
	jet.onGround = false
	local sam0 = e054.samN
	H.runUntil(function() return e054.samN < sam0 end, 6)
	check(e054.samN < sam0, string.format("发射了防空导弹（%d → %d）", sam0, e054.samN))
	local ev = nil
	for _, x in ipairs(fxLog) do if x.k == "vls" and x.sam and x.id == e054.id then ev = x end end
	check(ev ~= nil and ev.b == 1 and ev.c ~= nil, "从垂发第 " .. tostring(ev and ev.c) .. " 格出去")
	if ev and ev.c then
		local cf = e054.root.CFrame * CF.new(0, -(d054.H / 2 - d054.draft), 0)
		local cell = cf * CF.new((SD.vlsCell(d054, ev.b, ev.c)))
		check((ev.p - cell.Position).Magnitude < 2, string.format("出筒的位置就在那一格上（差 %.1f 格）", (ev.p - cell.Position).Magnitude))
	end
	H.run(0.35)
	local lid = v.lids and v.lids[#v.lids]
	check((CD.shipLidCount or 0) > lid0 and lid ~= nil, "客户端掀开了舱盖")
	if lid then
		local cf = shipCF(v)
		local up = cf:VectorToObjectSpace(lid.lid.CFrame.UpVector)
		check(up.Y < 0.2, string.format("舱盖竖起来了（盖子朝上的那面转到 %.0f°）", math.deg(math.acos(math.clamp(up.Y, -1, 1)))))
		check(lid.hole.Parent ~= nil, "底下露出打开的黑格子")
	end
	G.removeEnt(jet)   -- 不再打第二发（防空导弹 4 秒一发）
	H.run(4)
	check(#v.lids == 0, "几秒后舱盖合上、去掉")
end

G.fx = fx0
print(fails == 0 and "舰艇武器：全部通过" or ("舰艇武器：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
