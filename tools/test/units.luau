--!nocheck
-- 新兵种测试：每种都能造、能上场；医疗兵回步兵血、抢修车修车、巡飞弹撞上去用掉（不算损失）、电子战车干扰导弹、隐身轰炸机只有爱国者和战斗机打得到
-- 用法：lune run units.luau <rbxlx>
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1])
H.run(2)
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local p1 = H.addPlayer("P1", 4001)
H.run(6)
local G = H.Gs.server
local st = G.states[p1]
local Battle = G.Battle
local U = G.Config.Units
local function act(...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs.P1.R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = p1
	coroutine.resume(co)
	H.ctx = nil
end
st.data.cash = 1e9
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
for _ = 1, 16 do
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m then H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
	end
	H.run(1.3)
end
for _ = 1, 3 do act("hq") H.run(0.3) end

print("① 新兵种都能造")
local new = { "medic", "flamer", "commando", "repair", "heavytank", "ew", "loiter", "stealth" }
for _, t in new do act("buy", t) H.run(0.3) end
H.run(25)
local have = {}
for _, u in pairs(st.units) do have[u.t] = (have[u.t] or 0) + 1 end
for _, t in new do check(have[t] == 1, U[t].name .. " 造出来了（" .. G.Config.BuildingById[G.Config.UnitSource[t]].name .. "）") end
for _, t in { "tank", "heavytank", "loiter", "drone" } do
	print(string.format("     %s 高 %.1f", U[t].name, G.Models.heightOf(t)))
end
check(G.Models.heightOf("heavytank") > G.Models.heightOf("tank"), "重型坦克比主战坦克大")

print("② 推演里的机制（直接摆单位测）")
local function unit(t, team, x, z, extra)
	local d = U[t]
	local u = { t = t, def = d, team = team, x = x, y = d.air and d.alt or 0, z = z, h = 0, ty = 0, hp = d.hp, max = d.hp, dm = 1, cd = 0, rt = 0, alive = true }
	for k, v in pairs(extra or {}) do u[k] = v end
	return u
end
local fx = {}
local function newB(units)
	local B = { units = units, shells = {}, missiles = {}, pending = {}, deaths = {}, t = 0, byId = {}, alive1 = 0, alive2 = 0 }
	B.cb = {
		fx = function(e) table.insert(fx, e) end, world = function(x, y, z) return H.workspace.Terrain and require and nil end,
		muzzle = function() return nil end, aim = function() return nil end, hurt = function() end, heroHurt = function() end,
		die = function(u) end, kill = function() end, hit = function() end,
	}
	local roblox = require("@lune/roblox")
	B.cb.world = function(x, y, z) return roblox.Vector3.new(x, y, z) end
	B.cb.muzzle = function(u) return roblox.Vector3.new(u.x, 4, u.z) end
	B.cb.aim = function(t) return roblox.Vector3.new(t.x, 3, t.z) end
	return B
end
-- 医疗兵：受伤的步兵回血
do
	local inf = unit("inf", 1, 0, 300)
	inf.hp = 20
	local B = newB({ unit("medic", 1, 10, 300), inf, unit("tank", 2, 0, 900) })
	for _ = 1, 40 do Battle.step(B, 0.05) end
	check(inf.hp > 20, string.format("医疗兵 2 秒给步兵回血 20 → %.0f", inf.hp))
end
-- 抢修车：修坦克，不修步兵
do
	local tk = unit("tank", 1, 0, 300)
	tk.hp = 100
	local inf = unit("inf", 1, 5, 300)
	inf.hp = 20
	local B = newB({ unit("repair", 1, 12, 300), tk, inf, unit("tank", 2, 0, 900) })
	for _ = 1, 40 do Battle.step(B, 0.05) end
	check(tk.hp > 150 and inf.hp == 20, string.format("抢修车修坦克 100 → %.0f，步兵不管（%.0f）", tk.hp, inf.hp))
end
-- 巡飞弹：撞上去打坦克，自己没了、标记 spent
do
	local lo = unit("loiter", 1, 0, 600)
	local tk = unit("tank", 2, 0, 700)
	local B = newB({ lo, tk })
	for _ = 1, 100 do
		Battle.step(B, 0.05)
		if not lo.alive then break end
	end
	check(not lo.alive and lo.spent and tk.hp < U.tank.hp, string.format("巡飞弹撞上坦克：坦克血 %d → %.0f，巡飞弹用掉", U.tank.hp, tk.hp))
end
-- 隐身：防空车打不到，爱国者打得到
do
	local s = unit("stealth", 2, 0, 700)
	check(not Battle.canHit(U.aa, s) and not Battle.canHit(U.spaag, s) and not Battle.canHit(U.manpad, s), "防空车、弹炮、单兵防空打不到隐身轰炸机")
	check(Battle.canHit(U.sam, s) and Battle.canHit(U.fighter, s), "爱国者、战斗机打得到隐身轰炸机")
	check(Battle.canHit(U.aa, unit("bomber", 2, 0, 700)), "普通轰炸机防空车照样打得到（够得着的话）")
end
-- 电子战车：导弹命中率下降（统计 400 发）
do
	local function rate(withEw)
		local hits = 0
		for _ = 1, 400 do
			local tgt = unit("tank", 1, 0, 300)
			local us = { tgt, unit("at", 2, 0, 500) }
			if withEw then table.insert(us, unit("ew", 1, 30, 300)) end
			local B = newB(us)
			table.insert(B.missiles, { at = 0, tgt = tgt, dmg = 10, def = U.at, team = 2 })
			Battle.step(B, 0.05)
			if tgt.hp < tgt.max then hits += 1 end
		end
		return hits / 400
	end
	local a, b = rate(false), rate(true)
	check(b < a * 0.7, string.format("电子战车旁边导弹命中率 %.0f%% → %.0f%%", a * 100, b * 100))
end
-- 伪装：同样远的两个目标，敌人先打没伪装的
do
	local cm = unit("commando", 1, -10, 300)
	local inf = unit("inf", 1, 10, 300)
	local sh = unit("inf", 2, 0, 400)
	local B = newB({ cm, inf, sh })
	Battle.step(B, 0.05)
	check(sh.tgt == inf, "敌人先打没伪装的步兵班，不先打特种小队")
end

print("③ 带新兵种打几关（高关卡敌军里也会出现新兵种）")
local seen = {}
for _, lv in { 12, 18, 26 } do
	local list = Battle.genEnemy(lv)
	for _, t in list do seen[t] = true end
end
check(seen.medic or seen.flamer or seen.repair, "高关卡敌军里有医疗兵 / 火焰兵 / 抢修车")
check(seen.stealth or seen.loiter or seen.heavytank, "再往后有巡飞弹 / 重坦 / 隐身轰炸机")
for _, t in { "inf", "inf", "mg", "at", "tank", "tank", "ifv", "aa", "spaag", "sam", "arty", "heli" } do act("buy", t) H.run(0.2) end
H.run(25)
for _ = 1, 8 do act("tech") H.run(0.2) end
local sumLost = 0
for _, lv in { 12, 20, 26 } do
	st.data.level = lv
	G.makeEnemy(st)
	H.run(1)
	local n0 = G.count(st)
	act("battle")
	H.run(1)
	local ended = H.runUntil(function() return st.battle == nil end, 260)
	H.run(1)
	print(string.format("     第 %d 关：%s，部队 %d → %d", lv, ended and "打完" or "没打完", n0, G.count(st)))
	check(ended, "第 " .. lv .. " 关打完了")
	act("home")
	H.run(4)
	for _, t in { "loiter", "medic", "repair" } do if not have[t] then act("buy", t) end end
end
local flames, jams = 0, 0
for _, e in fx do
	if e.k == "jam" then jams += 1 end
end
H.summary()
print(string.format("新兵种测试：%d 项不对，脚本错误 %d 个", fails, #H.errors))
if fails > 0 or #H.errors > 0 then process.exit(1) end
