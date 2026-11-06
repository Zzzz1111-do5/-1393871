--!nocheck
-- 冒烟测试 2：完整流程——领每日奖励、踩按钮盖楼、造兵、布阵、开战（拿枪打、开车）、打完回基地、突袭、买武器、领任务、第二个玩家约战、重生、退出
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local place = process.args[1]
H.verbose = process.args[2] == "v"
H.quietWarn = true
H.showToasts = true
H.showNet = false
H.boot(place, { ds = process.args[3] or "unpublished" })
H.run(2)

local function say(...) print("●", ...) end
local function asClient(pl, f)
	local co = coroutine.create(f)
	local prev = H.ctx
	H.ctx = pl
	local ok, err = coroutine.resume(co)
	H.ctx = prev
	if not ok then H.report("测试脚本（客户端）", err, co) end
end
local function act(pl, ...)
	local args = table.pack(...)
	asClient(pl, function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(args, 1, args.n)) end)
end

local p1 = H.addPlayer("P1", 1001)
H.run(8)
local G = H.Gs.server
local st = G.states[p1]
local C1 = H.Gs.P1
say("进服：现金", st.data.cash, "客户端状态", C1.S ~= nil)

-- 每日奖励
H.click(p1, "^领取$")
H.run(1.5)
say("领每日奖励后现金", st.data.cash)

-- 踩按钮盖楼
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
local function touchPad(id)
	local m = plotF.Pads:FindFirstChild("Pad_" .. id)
	if not m then return false end
	H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart)
	return true
end
say("能买的：", #plotF.Pads:GetChildren())
touchPad("house1")
H.run(1.5)
say("盖居民楼 A 后：现金", st.data.cash, "收入", st.income, "已有", st.data.owned.house1)
st.data.cash = 2e6
for round = 1, 20 do
	local any = false
	for _, b in G.Config.Buildings do
		if not st.data.owned[b.id] and touchPad(b.id) then any = true end
	end
	H.run(1.5)
	if not any then break end
end
local n = 0
for _ in pairs(st.data.owned) do n += 1 end
say("盖好的建筑", n, "/", #G.Config.Buildings, "收入", st.income, "按钮剩", #plotF.Pads:GetChildren())

-- 指挥部升满、科技升几级
for _ = 1, 3 do act(p1, "hq") H.run(0.3) end
for _ = 1, 5 do act(p1, "tech") H.run(0.3) end
H.run(1)
say("指挥部", st.data.hq, "上限", G.capOf(st.data), "科技", st.data.tech)

-- 造兵（按客户端兵工厂的按钮：先切页签）
local want = { "inf", "inf", "mg", "at", "manpad", "sniper", "mortar", "jeep", "ifv", "tank", "tank", "td", "breacher", "aa", "spaag", "cram", "sam", "howitzer", "arty", "mlrs", "heli", "transport", "drone", "attacker", "fighter", "bomber" }
st.data.cash = 2e6
for _, t in want do act(p1, "buy", t) H.run(0.2) end
H.run(25)
say("部队数", G.count(st), "现金", math.floor(st.data.cash))
local moving = 0
for _, u in pairs(st.units) do if u.path then moving += 1 end end
say("还在路上的", moving)

-- 布阵：进布阵、一键排阵、点一个部队再点地面
H.click(p1, "^布阵$")
H.run(1)
H.click(p1, "一键排阵")
H.run(8)
say("模式", C1.mode)
H.click(p1, "^回基地$")
H.run(1)

-- 开战
H.click(p1, "开战")
H.run(2)
local B = st.battle
say("开战：", B ~= nil, B and #B.units, "客户端 battle", C1.battle ~= nil, "英雄", st.hero ~= nil)
-- 拿枪：把步枪从背包拿到手上，对着最近的敌人开几枪
local tool = p1.Backpack:FindFirstChildOfClass("Tool")
say("背包里的枪", tool and tool.Name)
if tool then
	tool.Parent = p1.Character
	H.run(0.5)
	say("客户端认出拿着枪", C1.mode)
	local target
	for _, u in B.units do
		if u.team == 2 and u.alive then target = u break end
	end
	if target then
		local tp = B.origin + V3.new(target.x, 3, target.z)
		local head = p1.Character.Head
		H.workspace.CurrentCamera.CFrame = CF.lookAt(head.Position + V3.new(0, 1, 0), tp)
		local hp0 = target.hp
		for _ = 1, 10 do
			H.mouseDown(p1, 640, 360)
			H.run(0.15)
			H.mouseUp(p1, 640, 360)
			H.run(0.1)
		end
		H.run(1)
		say("开枪后目标血量", hp0, "→", target.hp, "弹药", C1.ui and C1.ui.ammo.Text)
	end
	tool.Parent = p1.Backpack
	H.run(0.3)
end
-- 开车：打开「开车 / 开飞机」，点第一个「开」
do
	local n, mine, bu, dead, veh = 0, 0, 0, 0, 0
	for m in pairs(C1.vis) do
		n += 1
		if m:GetAttribute("Owner") == p1.UserId then mine += 1 end
		if m:GetAttribute("BU") then bu += 1 end
		if m:GetAttribute("Dead") then dead += 1 end
		local d = G.Config.Units[m:GetAttribute("Type") or ""]
		if d and not d.foot and m:GetAttribute("Owner") == p1.UserId and m:GetAttribute("BU") and not m:GetAttribute("Dead") and m.Parent then veh += 1 end
	end
	say("客户端跟踪的模型", n, "自己的", mine, "有 BU", bu, "打掉的", dead, "能开的", veh)
end
local db = H.findButton(p1, "开车")
if db then
	H.press(p1, db)
	H.run(0.5)
	local go = H.findButton(p1, "^开$")
	say("能开的车", go ~= nil)
	if go then
		H.press(p1, go)
		H.run(1)
		say("驾驶中：服务器", st.driving and st.driving.t, "客户端", C1.drive and C1.drive.t, "模式", C1.mode)
		H.key(p1, Enum.KeyCode.W, true)
		H.mouseDown(p1, 640, 300)
		H.run(4)
		H.mouseUp(p1, 640, 300)
		H.key(p1, Enum.KeyCode.W, false)
		H.run(0.5)
		if st.driving then say("开出去的位置", math.floor(st.driving.x), math.floor(st.driving.z)) end
		H.key(p1, Enum.KeyCode.F, true)
		H.key(p1, Enum.KeyCode.F, false)
		H.run(1)
		say("下车：服务器", st.driving == nil, "客户端", C1.drive == nil, "英雄", st.hero ~= nil)
	end
end
-- 打到结束
local ended = H.runUntil(function() return st.battle == nil end, 260)
H.run(1)
say("打完：", ended, "关卡", st.data.level, "现金", math.floor(st.data.cash), "部队", G.count(st))
for _, t in H.texts(p1, "胜利") do say("  ", t) end
for _, t in H.texts(p1, "失败") do say("  ", t) end
for _, t in H.texts(p1, "时间到") do say("  ", t) end
H.click(p1, "^回基地$")
H.run(3)

-- 突袭（没有存档服务：AI 指挥官）
H.click(p1, "^突袭")
H.run(3)
say("突袭开战：", st.battle ~= nil, st.battle and st.battle.mode)
local ended2 = H.runUntil(function() return st.battle == nil end, 260)
H.run(1)
say("突袭打完：", ended2, "积分", st.data.rating)
H.click(p1, "^回基地$")
H.run(1)

-- 买武器、领任务
st.data.cash = 1e6
H.click(p1, "^武器$")
H.run(0.5)
for _, b in select(2, H.findButton(p1, "^%$")) do
	if b.Text:find("^%$%d") and b.Parent and b.Parent.Parent and b.Parent.Parent.Parent and b.Parent.Parent.Parent.Visible ~= false then end
end
for _, id in G.Config.WeaponOrder do act(p1, "weapon", id) H.run(0.3) end
H.run(1)
local wn = 0
for _ in pairs(st.data.weapons) do wn += 1 end
say("武器", wn, "背包", #p1.Backpack:GetChildren())
for i = 1, 3 do act(p1, "mission", i) H.run(0.2) end
H.click(p1, "^任务")
H.run(0.5)
H.click(p1, "^×$")

-- 第二个玩家、约战
local p2 = H.addPlayer("P2", 1002)
H.run(10)
local st2 = G.states[p2]
st2.data.cash = 1e5
for _, b in G.Config.Buildings do
	if b.id == "house1" or b.id == "barracks" then
		local m = H.workspace.Plots["Plot" .. st2.plot.index].Pads:FindFirstChild("Pad_" .. b.id)
		if m then H.ev(m.Pad, "Touched"):Fire(p2.Character.HumanoidRootPart) end
		H.run(1.5)
	end
end
for _ = 1, 3 do act(p2, "buy", "inf") H.run(0.2) end
H.run(10)
say("P2 部队", G.count(st2))
act(p1, "duel", 1002)
H.run(1)
local acc = H.findButton(p2, "^接受$")
say("P2 收到邀请", acc ~= nil)
if acc then H.press(p2, acc) end
H.run(2)
say("约战开打", st.battle ~= nil and st.battle.mode, st2.battle ~= nil)
local ended3 = H.runUntil(function() return st.battle == nil and st2.battle == nil end, 260)
H.run(2)
say("约战打完", ended3, "P1 部队", G.count(st), "P2 部队", G.count(st2))

-- 重生
st.data.level = 20
H.run(1.5)
local rb = H.findButton(p1, "^重生$")
say("重生按钮", rb ~= nil)
if rb then
	H.press(p1, rb)
	H.run(0.5)
	H.click(p1, "确定重生")
	H.run(2)
	say("重生后：次数", st.data.rebirth, "关卡", st.data.level, "现金", st.data.cash, "建筑", next(st.data.owned) == nil and "清空" or "还有")
end

-- 退出
H.removePlayer(p2)
H.run(2)
H.removePlayer(p1)
H.run(2)
say("退出后服务器状态表", next(G.states) == nil)
H.shutdown()
H.summary()
local seen = {}
for _, e in H.errors do
	local k = e.msg:sub(1, 200)
	if not seen[k] then
		seen[k] = true
		print("错误（首次 " .. string.format("%.1f", e.t) .. " 秒，" .. e.side .. "）：" .. e.tb:sub(1, 1500))
	end
end
local ws = {}
for _, w in H.warns do ws[w.msg:sub(1, 160)] = (ws[w.msg:sub(1, 160)] or 0) + 1 end
for m, c in pairs(ws) do print("警告 ×" .. c .. "：" .. m) end
