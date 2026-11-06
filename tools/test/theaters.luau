--!nocheck
-- 战区测试：进服按关卡摆战区；打过第 10 关（首领）进沙漠、战场换样子、有播报；沙漠 / 城市的速度、射程倍数；火山弹落下来敌我都伤；竞技场有战区样子
-- 用法：lune run theaters.luau <rbxlx>
local process = require("@lune/process")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
H.run(2)
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local G
local function act(pl, ...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = nil
end

print("① 竞技场")
G = H.Gs.server
local a1 = H.workspace.Arenas.Arena1:FindFirstChild("Decor")
local a2 = H.workspace.Arenas.Arena2:FindFirstChild("Decor")
check(a1 ~= nil and a2 ~= nil and #a1:GetChildren() > 50, "两个竞技场都有战区道具（" .. (a1 and #a1:GetChildren() or 0) .. " 个）")

local p1 = H.addPlayer("P1", 6001)
H.run(6)
local st = G.states[p1]
check(st.plot.theater == "grass", "第 1 关：绿野战区")
st.data.cash = 1e9
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
for _ = 1, 16 do
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m then H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
	end
	H.run(1.3)
end
for _ = 1, 3 do act(p1, "hq") H.run(0.3) end
for _ = 1, 25 do act(p1, "tech") H.run(0.12) end
for _, t in { "tank", "tank", "tank", "heavytank", "ifv", "ifv", "aa", "spaag", "sam", "heli", "heli", "attacker", "fighter", "at", "at", "inf", "inf", "medic", "repair", "arty" } do
	act(p1, "buy", t)
	H.run(0.25)
end
H.run(30)

print("② 打过首领进沙漠")
st.data.level = 10
G.makeEnemy(st)
H.run(1)
local decor0 = plotF:FindFirstChild("Decor")
act(p1, "battle")
H.run(1)
local ended = H.runUntil(function() return st.battle == nil end, 260)
H.run(5)
check(ended and st.data.level == 11, "第 10 关打赢了（现在第 " .. st.data.level .. " 关）")
check(st.plot.theater == "desert", "战场换成沙漠（" .. tostring(st.plot.theater) .. "）")
check(plotF.Field.Material.Name == "Sand", "战场地面是沙子")
check(plotF:FindFirstChild("Decor") ~= decor0, "道具重摆了")
check(#H.texts(p1, "进入新战区") > 0, "有「进入新战区」大字播报")
check(#H.texts(p1, "沙漠战区") > 0, "界面上写着沙漠战区")

print("③ 沙漠、城市的倍数")
act(p1, "home")
H.run(4)
act(p1, "battle")
H.run(1)
check(st.battle and st.battle.speedK == 0.9, "沙漠：地面速度 × 0.9")
H.runUntil(function() return st.battle == nil end, 260)
H.run(4)
st.data.level = 31
G.makeEnemy(st)
H.run(1)
act(p1, "battle")
H.run(1)
check(st.battle and math.abs(st.battle.rangeK - 0.88) < 1e-6 and st.plot.theater == "urban", "城市废墟：射程 × 0.88，战场换成城市")
H.runUntil(function() return st.battle == nil end, 260)
H.run(4)

print("④ 火山弹")
print("     打完城市剩 " .. G.count(st) .. " 个单位，补兵")
for _, t in { "tank", "tank", "heavytank", "ifv", "aa", "sam", "heli", "inf", "inf", "medic" } do
	act(p1, "buy", t)
	H.run(0.25)
end
H.run(20)
st.data.level = 41
G.makeEnemy(st)
H.run(1)
local quakes, lava = 0, 0
H.ev(H.game.ReplicatedStorage.Remotes.Fx, "OnClientEvent@P1"):Connect(function(list)
	for _, e in list do
		if e.k == "quake" then quakes += 1 end
		if e.k == "bomb" and e.u == "lava" then lava += 1 end
	end
end)
act(p1, "battle")
H.run(1)
local B = st.battle
check(B and B.quake and st.plot.theater == "volcano", "火山战区：开着火山弹")
-- 战斗拖长一点，看火山弹
for _, u in B.units do
	u.hp *= 20
	u.max *= 20
end
H.run(40)
check(quakes >= 2 and lava >= 6, string.format("40 秒里火山弹预警 %d 次、落下 %d 颗", quakes, lava))
local hurt1, hurt2 = false, false
for _, u in B.units do
	if u.alive and u.hp < u.max then
		if u.team == 1 then hurt1 = true else hurt2 = true end
	end
end
check(hurt1 and hurt2, "敌我都挂了彩")
H.runUntil(function() return st.battle == nil end, 260)
H.run(2)

print("⑤ 重进：按关卡直接摆战区")
H.removePlayer(p1)
H.run(3)
local p1b = H.addPlayer("P1", 6001)
H.run(8)
local st2 = G.states[p1b]
check(st2.plot.theater == G.Config.TheaterOf(st2.data.level).id, "重进第 " .. st2.data.level .. " 关：" .. tostring(st2.plot.theater))
H.summary()
print(string.format("战区测试：%d 项不对，脚本错误 %d 个", fails, #H.errors))
if fails > 0 or #H.errors > 0 then process.exit(1) end
