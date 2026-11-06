--!nocheck
-- 新功能测试：新手目标、补给空投、战场支援技能（按技能键 + 点战场）、命中反馈 / 战报、首领关播报、评星、老兵存档读回、结算出错的保底收尾
-- 用法：lune run flow_new.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
H.quietWarn = true
H.showToasts = process.args[2] == "v"
H.boot(process.args[1], { ds = "mock" })
H.run(2)

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function act(pl, ...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	local prev = H.ctx
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = prev
end
local function toastsFor(name, pattern)
	local n = 0
	for _, t in H.toasts or {} do
		if t.to == name and (not pattern or t.msg:find(pattern)) then n += 1 end
	end
	return n
end

local p1 = H.addPlayer("P1", 2001)
H.run(6)
local G = H.Gs.server
local st = G.states[p1]
local C1 = H.Gs.P1
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
local function touchPad(id)
	local m = plotF.Pads:FindFirstChild("Pad_" .. id)
	if not m then return false end
	H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart)
	return true
end
-- 技能键的字在按钮里面的 TextLabel 上：按字找到再按它的父按钮
local function skillBtn(pl, name)
	for _, d in pl.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == name and d.Parent and d.Parent:IsA("TextButton") and H.visible(d.Parent) then return d.Parent end
	end
	return nil
end
local function goalText()
	return C1.ui.goal and C1.ui.goal:FindFirstChildWhichIsA("TextLabel") and table.concat(H.texts(p1, "居民楼") , "|") or ""
end

print("① 新手目标")
H.click(p1, "^领取$")
H.run(1.5)
local t1 = table.concat(H.texts(p1, "盖第一栋"), "|")
check(t1 ~= "", "一进来提示盖第一栋楼：" .. t1)
local arrow = p1.PlayerGui:FindFirstChild("GoalArrow")
check(arrow ~= nil and arrow.Enabled and arrow.Adornee ~= nil and arrow.Adornee.Parent.Name == "Pad_house1", "箭头指着居民楼 A 的按钮")
touchPad("house1")
H.run(2)
check(#H.texts(p1, "盖「兵营」") > 0, "盖完第一栋提示盖兵营：" .. table.concat(H.texts(p1, "兵营"), "|"))

print("② 补给空投")
local cash0 = st.data.cash
local landed = H.runUntil(function() return st.crate ~= nil and st.crate.landed end, 60)
check(landed, "35 秒左右空投一个补给箱并落地")
if st.crate then
	local box = st.crate.box
	check(box.Parent ~= nil and box.Parent.Parent == plotF.Drops, "箱子在自己基地的 Drops 文件夹里")
	local amt = math.max(G.Config.Crate.min, math.floor(st.income * G.Config.Crate.sec))
	H.ev(box, "Touched"):Fire(p1.Character.HumanoidRootPart)
	H.run(1)
	check(st.crate == nil and st.data.cash >= cash0 + amt - 1, "碰一下拿到钱：+" .. amt .. "（现在 " .. math.floor(st.data.cash) .. "）")
end

print("③ 造兵、打第 1 关：命中反馈、战报、评星、老兵")
st.data.cash = 5e5
for _, b in G.Config.Buildings do touchPad(b.id) H.run(1.3) end
for _ = 1, 20 do
	local any = false
	for _, b in G.Config.Buildings do
		if not st.data.owned[b.id] and touchPad(b.id) then any = true end
	end
	H.run(1.3)
	if not any then break end
end
for _ = 1, 3 do act(p1, "hq") H.run(0.3) end
for _, t in { "inf", "inf", "mg", "tank", "tank", "ifv", "heli", "arty", "aa", "at" } do act(p1, "buy", t) H.run(0.25) end
H.run(25)
st.data.level = 6
G.makeEnemy(st)
H.run(1)
H.click(p1, "开战")
H.run(2)
local B = st.battle
check(B ~= nil, "开战了")
-- 敌军加厚，免得几秒就打完、测不到后面的技能
for _, u in B.units do
	if u.team == 2 then
		u.hp *= 8
		u.max *= 8
	end
end
check(C1.ui.sbar.Visible and skillBtn(p1, "迫击炮急袭") ~= nil and skillBtn(p1, "空袭") ~= nil, "技能栏出来了（迫击炮急袭、空袭……）")
-- 俯瞰战场，按 Z（迫击炮急袭）、点屏幕中间
H.click(p1, "俯瞰战场")
H.run(1.5)
local enemyHp0 = 0
for _, u in B.units do if u.team == 2 then enemyHp0 += u.hp end end
H.key(p1, Enum.KeyCode.Z, true)
H.key(p1, Enum.KeyCode.Z, false)
H.run(0.2)
check(C1.aim == "mortar", "按 Z 进入瞄准")
H.mouseDown(p1, 640, 330)
H.mouseUp(p1, 640, 330)
H.run(0.5)
check(st.skillCD and (st.skillCD.mortar or 0) > H.now, "服务器放了迫击炮急袭、进入冷却")
H.run(4)
-- 空投援军：点技能键（界面按钮），再点
local nUnits = #B.units
H.press(p1, skillBtn(p1, "空投援军"))
H.run(0.2)
H.mouseDown(p1, 600, 360)
H.mouseUp(p1, 600, 360)
H.run(3)
local temps = 0
for _, u in B.units do if u.temp and u.team == 1 then temps += 1 end end
check(temps >= 3, "空投援军落地 " .. temps .. " 个步兵班")
-- 战地急救、炮火覆盖、空袭
for _, k in { Enum.KeyCode.X, Enum.KeyCode.V, Enum.KeyCode.N } do
	H.key(p1, k, true)
	H.key(p1, k, false)
	H.run(0.1)
	H.mouseDown(p1, 640, 300)
	H.mouseUp(p1, 640, 300)
	H.run(0.6)
end
check((st.skillCD.heal or 0) > H.now and (st.skillCD.barrage or 0) > H.now and (st.skillCD.strike or 0) > H.now, "急救、炮火覆盖、空袭都放了")
H.run(5)
local enemyHp1 = 0
for _, u in B.units do if u.team == 2 and u.alive then enemyHp1 += u.hp end end
check(enemyHp1 < enemyHp0, string.format("支援火力打掉了敌军血量 %.0f → %.0f", enemyHp0, enemyHp1))
-- 冷却中再按：不放
local cd0 = st.skillCD.mortar
H.key(p1, Enum.KeyCode.Z, true)
H.key(p1, Enum.KeyCode.Z, false)
H.run(0.2)
check(C1.aim == nil and st.skillCD.mortar == cd0, "冷却中按技能键不进入瞄准")
-- 拿枪打：命中标记
local hits = 0
H.ev(H.game.ReplicatedStorage.Remotes.Battle, "OnClientEvent@P1"):Connect(function(ev) if ev.phase == "hit" then hits += 1 end end)
H.click(p1, "跟随自己")
H.run(0.5)
local tool = p1.Backpack:FindFirstChildOfClass("Tool")
if tool then
	tool.Parent = p1.Character
	H.run(0.3)
	local target
	for _, u in B.units do if u.team == 2 and u.alive and not u.def.air then target = u break end end
	if target then
		-- 跑到离它 60 格的地方再打（步枪射程 450）
		p1.Character:PivotTo(CF.new(B.origin + V3.new(target.x, 4, target.z - 60)))
		H.run(0.2)
		local head = p1.Character.Head
		H.workspace.CurrentCamera.CFrame = CF.lookAt(head.Position + V3.new(0, 1, 0), B.origin + V3.new(target.x, 3, target.z))
		for _ = 1, 8 do
			H.mouseDown(p1, 640, 360)
			H.run(0.15)
			H.mouseUp(p1, 640, 360)
			H.run(0.1)
		end
	end
	tool.Parent = p1.Backpack
end
H.run(1)
check(hits > 0, "开枪打中有命中反馈（" .. hits .. " 次）")
local ended = H.runUntil(function() return st.battle == nil end, 250)
H.run(1.5)
check(ended, "打完了")
local starsT = C1.ui.resStars and C1.ui.resStars.Text or ""
check(C1.ui.result.Visible and (starsT:find("★") ~= nil or C1.ui.resTitle.Text ~= "胜利！"), "结算面板：" .. C1.ui.resTitle.Text .. " " .. starsT)
for _, l in H.texts(p1, "奖励") do print("     " .. l:gsub("\n", " / ")) end
local feedSeen = toastsFor("P1", "老兵晋升")
local vets = 0
for _, u in pairs(st.units) do if (u.v or 0) > 0 then vets += 1 end end
check(vets > 0, "活下来的部队攒了老兵经验（" .. vets .. " 个）")

print("④ 首领关")
H.click(p1, "^回基地$")
H.run(2)
st.data.level = 10
G.makeEnemy(st)
H.run(1)
H.click(p1, "开战")
H.run(1)
check(#H.texts(p1, "首领来袭") > 0, "首领关开打有大字播报")
local ended2 = H.runUntil(function() return st.battle == nil end, 250)
H.run(1)
check(ended2, "首领关打完：" .. C1.ui.resTitle.Text)
H.click(p1, "^回基地$")
H.run(1)

print("⑤ 结算出错的保底：故意让老兵提示出错")
local real = G.vetTag
G.vetTag = function() error("测试：故意出错") end
for _, u in pairs(st.units) do u.v = 2 end   -- 再活一仗就升星 → 调 vetTag → 出错
st.data.level = 2
G.makeEnemy(st)
H.run(1)
H.click(p1, "开战")
H.run(2)
local ended3 = H.runUntil(function() return st.battle == nil end, 250)
H.run(2)
G.vetTag = real
check(ended3 and st.battle == nil, "结算出错也能退出打仗状态")
local errShown = #H.texts(p1, "故意出错") > 0
check(errShown, "出错原文显示在屏幕上方的红条里")
H.click(p1, "开战")
H.run(2)
check(st.battle ~= nil, "出错之后还能接着开战")
H.runUntil(function() return st.battle == nil end, 250)
H.run(1)

print("⑥ 存档读回（模拟的 DataStore）")
local units0, v0 = 0, 0
for _, u in pairs(st.units) do
	units0 += 1
	v0 += u.v or 0
end
local level0, cash1 = st.data.level, math.floor(st.data.cash)
H.removePlayer(p1)
H.run(3)
local p1b = H.addPlayer("P1", 2001)
H.run(8)
local st2 = G.states[p1b]
local units1, v1 = 0, 0
for _, u in pairs(st2.units) do
	units1 += 1
	v1 += u.v or 0
end
check(st2.data.level == level0 and units1 == units0 and v1 == v0, string.format("关卡 %d/%d、部队 %d/%d、老兵经验 %d/%d 都读回来了", st2.data.level, level0, units1, units0, v1, v0))
check(math.abs(math.floor(st2.data.cash) - cash1) <= st2.income * 12, "现金读回来了（" .. cash1 .. " → " .. math.floor(st2.data.cash) .. "，差的是重进后这几秒的收入）")

H.removePlayer(p1b)
H.run(2)
H.shutdown()
H.summary()
local real_errors = 0
for _, e in H.errors do
	if not e.msg:find("测试：故意出错") then real_errors += 1 end
end
print(string.format("新功能测试：%d 项不对，非故意的脚本错误 %d 个", fails, real_errors))
if fails > 0 or real_errors > 0 then process.exit(1) end
