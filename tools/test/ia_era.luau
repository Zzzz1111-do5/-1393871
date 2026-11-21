--!nocheck
-- 爆反、主动防御、改装（用户 11-19）：
--   ① 改装出车（服务器 padSpawn 带改装）：主动防御 4 发、加特林进了武器表、车速变慢、模型属性 Mods；客户端模型上有发射器、雷达板、加特林
--   ② 火箭弹打带主动防御的 M1A2：在车外被打掉、车不掉血、少一发；打光以后火箭弹打在侧裙板上 → 爆反块炸了、伤害只剩三成多，
--      客户端那一块换成焦黑空位、放了特效
--   ③ 坦克炮打 99A 炮塔正面（重型爆反）：块炸了、伤害打七五折
--   ④ 改装界面：能打开、拼出 3D 模型、点「出车」把改装交给回调
--   lune run tools/test/ia_era.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF = roblox.Vector3, roblox.CFrame
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
	local ok, err = coroutine.resume(co)
	if not ok then print("    报错：" .. tostring(err)) end
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
local p1, p2 = H.addPlayer("P1", 5101), H.addPlayer("P2", 5102)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
local PD = G.P[def]
local CD = H.Gs[def.Name]
local RS = H.game:GetService("ReplicatedStorage")
local TM = H.require(RS.TankMods)
local VD = H.require(RS.VehDefs)

-- 守方营地的地面车位（召唤位，一排）
local pads = {}
for _, p in ipairs(G.pads or {}) do
	if p.kind == "veh" and p.team == "def" and p.summon then table.insert(pads, p) end
end
check(#pads >= 4, "守方营地有 " .. #pads .. " 个地面车位")

-- 先部署（营地出生），再走到车位旁边发 padSpawn（同 ia_veh）
CD.deploySel.spawn, CD.deploySel.role = "camp", "engineer"
H.leaveMenu(def)
CD.refreshDeploy()
H.click(def, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
check(PD.alive, "守方在营地出生了")
print("① 改装出车")
H.goPad(G, def, pads[1])
act(def, "padSpawn", pads[1].id, { aps = "hk", roof = "gau8" }, "m1a2")
H.run(1)
local eA = nil
for _, e in ipairs(G.vehicles) do if e.padId == pads[1].id and e.alive then eA = e end end
check(eA ~= nil, "按改装生成了一辆 M1A2")
if not eA then H.summary() process.exit(1) end
check(eA.def.mods and eA.def.mods.aps == "hk" and eA.def.mods.roof == "gau8", "改装：" .. tostring(eA.model:GetAttribute("Mods")))
check(eA.aps and eA.aps.n == 4 and eA.model:GetAttribute("Aps") == 4, "主动防御 4 发")
check(table.find(eA.def.weapons, "gau8") ~= nil and #eA.def.weapons == 3, "武器表：" .. table.concat(eA.def.weapons, ", "))
local base0 = VD.get("m1a2")
check(eA.def.speed < base0.speed and math.abs(eA.def.speed - base0.speed * 0.97 * 0.95) < 0.01, string.format("车速 %.1f → %.1f", base0.speed, eA.def.speed))
check(eA.era and eA.era.n >= 8, "爆反块 " .. tostring(eA.era and eA.era.n))
-- 客户端的模型
local vA = CD.viewById and CD.viewById(eA.id)
local nKit, nTur = 0, 0
if vA and vA.M then
	for _, it in ipairs(vA.M.parts) do
		if it[2] == "kit" then nKit += 1 end
		if it[2] == "turret" then nTur += 1 end
	end
end
check(vA and vA.M and vA.M.mods and vA.M.mods.aps == "hk", "客户端按改装拼的车")
check(nKit >= 10, "加特林的零件（kit 组）" .. nKit .. " 块")
check(vA and vA.M and vA.M.kpiv ~= nil, "加特林的俯仰轴")
local L = TM.eraOf("m1a2")
local mz = TM.kitMuzzle(L, eA.root.CFrame * CF.new(0, -eA.def.H / 2, 0), 0, 0)
local rel = (eA.root.CFrame * CF.new(0, -eA.def.H / 2, 0)):PointToObjectSpace(mz.Position)
check(rel.Y > 7.5 and rel.Z < -2, string.format("加特林的炮口在炮塔顶上、朝前（高 %.1f，前 %.1f）", rel.Y, -rel.Z))

print("② 主动防御拦火箭弹，打光以后爆反接住")
local RPG = G.Config.Weapons.rpg
local function rocketAt(target, from, team)
	G.launch({ kind = "rocket", pos = from, vel = (target - from).Unit * RPG.speed, w = RPG, src = { team = team or "atk", name = "测试" }, ignore = {}, life = 4 })
end
local cA = eA.root.CFrame.Position
local hp0 = eA.hp
G.apsHits, G.eraHits = 0, 0
rocketAt(cA, cA + eA.root.CFrame.LookVector * 80 + V3.new(0, 2, 0))
H.run(1.2)
check(G.apsHits == 1 and eA.hp == hp0 and eA.aps.n == 3, string.format("第一发在车外被拦了（拦截 %d 次、血 %d → %d、剩 %d 发）", G.apsHits, hp0, eA.hp, eA.aps.n))
for _ = 1, 3 do
	rocketAt(cA, cA + eA.root.CFrame.RightVector * 80 + V3.new(0, 2, 0))
	H.run(1.0)
end
check(G.apsHits == 4 and eA.aps.n == 0 and eA.model:GetAttribute("Aps") == 0, "又拦了三发，打光了（" .. G.apsHits .. " 次）")
check((CD.apsFxCount or 0) >= 1, "客户端放了拦截的特效（" .. tostring(CD.apsFxCount) .. " 次）")
-- 侧裙板上的一块（原模型自带的 ARAT）：从正侧面打过去
local base = eA.root.CFrame * CF.new(0, -eA.def.H / 2, 0)
local blk = nil
for i, b in ipairs(L.b) do if b[17] == "sk" and b[5] > 0.5 then blk = i break end end
local bcf = TM.blockCF(L, L.b[blk], base, eA.ty or 0)
local hp1 = eA.hp
rocketAt(bcf.Position, bcf.Position + bcf.ZVector * 12)   -- 车位一排挨着：从 12 格外打（远了起点会落在隔壁车上）
H.run(1.0)
local lossA = hp1 - eA.hp
check(G.eraHits >= 1 and eA.era.dead[blk] == true, "爆反块炸了（炸了 " .. G.eraHits .. " 块，属性 EraX = " .. tostring(eA.model:GetAttribute("EraX")) .. "）")
-- 对照：一辆不带爆反的 M1A2，同样的位置打一发
H.run(2.2)   -- 两次出车至少隔 2 秒
H.goPad(G, def, pads[4])
act(def, "padSpawn", pads[4].id, {}, "m1a2")
H.run(1)
local eB = nil
for _, e in ipairs(G.vehicles) do if e.padId == pads[4].id and e.alive then eB = e end end
check(eB ~= nil and eB.aps == nil, "对照车：没装主动防御")
if eB then
	eB.era = nil   -- 对照：去掉爆反
	local baseB = eB.root.CFrame * CF.new(0, -eB.def.H / 2, 0)
	local bcfB = TM.blockCF(L, L.b[blk], baseB, eB.ty or 0)
	local hpB = eB.hp
	rocketAt(bcfB.Position, bcfB.Position + bcfB.ZVector * 12)
	H.run(1.0)
	local lossB = hpB - eB.hp
	check(lossA > 0 and lossB > 0 and math.abs(lossA / lossB - TM.ERA.arat.k) < 0.05, string.format("伤害打折：有爆反掉 %d、没有掉 %d（%.2f 成，应 %.2f）", lossA, lossB, lossA / math.max(lossB, 1), TM.ERA.arat.k))
end
H.run(0.5)
vA = CD.viewById and CD.viewById(eA.id)
check(vA and vA.M and vA.M.era[blk] and vA.M.era[blk].blown == true, "客户端那一块换成了焦黑的空位")
check((CD.eraFxCount or 0) >= 1, "客户端放了爆反起爆的特效（" .. tostring(CD.eraFxCount) .. " 次）")

print("③ 坦克炮打 99A 炮塔正面（重型爆反 FY-4）")
local function newTank(id, padIdx)
	local p = pads[padIdx]
	return G.newVehicle("atk", id, p.base)
end
local eC, eD = newTank("ztz99a", 6), newTank("ztz99a", 8)
local L9 = TM.eraOf("ztz99a")
local tf = nil
for i, b in ipairs(L9.b) do if b[17] == "tf" and b[7] < -0.4 then tf = i break end end
check(tf ~= nil and not TM.own(L9, L9.b[tf]), "99A 炮塔正面有补贴的块（不是原模型自带的）")
local GUN = VD.W.gun120
local function shellAt(e, i)
	local bs = e.root.CFrame * CF.new(0, -e.def.H / 2, 0)
	local c = TM.blockCF(L9, L9.b[i], bs, e.ty or 0)
	local from = c.Position - (e.root.CFrame.LookVector * -1) * 0 + e.root.CFrame.LookVector * 120
	from = V3.new(from.X, c.Position.Y, from.Z)
	G.launch({ kind = "shell", pos = from, vel = (c.Position - from).Unit * GUN.speed, grav = false, w = GUN, src = { team = "def", name = "测试" }, ignore = {}, life = 2 })
end
local hc, hd = eC.hp, eD.hp
eD.era = nil
G.eraHits = 0
shellAt(eC, tf)
shellAt(eD, tf)
H.run(0.6)
local lc, ld = hc - eC.hp, hd - eD.hp
local deadZ = nil
for i in pairs(eC.era.dead) do deadZ = L9.b[i][17] end
check(G.eraHits == 1 and deadZ ~= nil, "99A 正面挨了一炮，一块爆反炸了（区 " .. tostring(deadZ) .. "：平射先碰到首上那一片）")
check(lc > 0 and ld > 0 and math.abs(lc / ld - TM.ERA.fy4.ke) < 0.05, string.format("穿甲弹伤害打折：%d / %d（%.2f，应 %.2f）", lc, ld, lc / math.max(ld, 1), TM.ERA.fy4.ke))

print("④ 改装界面")
local got = nil
as(def, function() CD.openGarage("ztz99a", { aps = "hk" }, function(m) got = m end) end)
H.run(0.5)
local S = CD.garageState and CD.garageState()
check(S ~= nil and S.M ~= nil and #S.M.parts > 20, "打开了，拼了 3D 模型（" .. (S and S.M and #S.M.parts or 0) .. " 块）")
-- 用户 11-21：改坦克的界面鼠标不显示——UI.lua 每帧按 G.menuOpen() 决定画不画鼠标指针、锁不锁（步行第一人称时藏起来），原来没算改装界面
check(CD.menuOpen and CD.menuOpen() == true, "改装界面开着算作菜单：鼠标指针画出来、不锁在屏幕中间")
local pg = def:FindFirstChildOfClass("PlayerGui")
local go = nil
for _, d in pg:GetDescendants() do if d:IsA("TextButton") and d.Name == "GarageGo" then go = d end end
check(go ~= nil, "有「出车」按钮")
if go then H.press(def, go) end
H.run(0.3)
check(got and got.aps == "hk" and got.era == "era" and got.roof == "stock", "点「出车」把改装交给了回调：" .. (got and TM.encode(got) or "-"))
check(not CD.garageOpen(), "界面关了")

print("⑤ 驾驶界面：敌人头顶的名字和距离、被发现、爆反 / 主动防御剩多少、圆形小地图")
local nearA = eA.root.CFrame * CF.new(eA.def.W / 2 + 4, 0, 0)
def.Character:PivotTo(CF.new(nearA.Position.X, G.Map.ground(nearA.Position.X, nearA.Position.Z) + 3, nearA.Position.Z))
H.run(0.3)
act(def, "enterVeh", eA.id)
H.run(1.5)
local st = CD.drive
check(st ~= nil and st.id == eA.id, "坐进了改装的 M1A2")
local fwd = eA.root.CFrame.LookVector
local fpos = eA.root.CFrame.Position + fwd * 120
local foeE = G.newVehicle("atk", "ztz96", CF.lookAt(V3.new(fpos.X, G.Map.ground(fpos.X, fpos.Z), fpos.Z), V3.new(fpos.X, G.Map.ground(fpos.X, fpos.Z), fpos.Z) - fwd))
H.run(1.5)
local tagTxt, spotted, armTxt = nil, false, nil
local th = pg:FindFirstChild("TankHud")
if th then
	for _, d in th:GetDescendants() do
		if d:IsA("TextLabel") and d.Visible and d.Parent and d.Parent:IsA("Frame") and d.Parent.Visible and d.TextColor3.R > 0.9 and d.TextColor3.G < 0.5 and d.Text ~= "" then tagTxt = d.Text end
		if d:IsA("TextLabel") and d.Text == CD.T("vh.spotted") and d.Parent.Visible then spotted = true end
		if d:IsA("TextLabel") and string.find(d.Text, CD.T("vh.aps", 0, 4):sub(1, 6), 1, true) then armTxt = d.Text end
	end
end
check(th ~= nil and th.Enabled, "坦克界面的补充层开着")
check(tagTxt ~= nil, "敌人头顶的名牌：" .. tostring(tagTxt))
check(spotted, "「被发现！」亮了（敌车 120 格、看得见）")
check(armTxt ~= nil, "爆反 / 主动防御剩多少：" .. tostring(armTxt))
check(CD.tankHudDocked and CD.tankHudDocked(), "小地图挪到左下变圆")

H.summary()
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
