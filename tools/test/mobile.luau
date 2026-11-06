--!nocheck
-- 手机：触屏、没有键盘、屏幕 844 × 390。查紧凑排版（不放小地图、兵工厂能收起、布阵时自动收起、回基地再打开）、
-- 打仗时技能栏在右边竖排、钱和关卡信息让开，开直升机时有「升高」「降低」键、按住能升降、运兵直升机降到最低放兵
-- 用法：lune run mobile.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = true
H.boot(process.args[1], { ds = "mock" })
H.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(844, 390)
H.UIS.TouchEnabled = true
H.UIS.KeyboardEnabled = false
H.UIS.MouseEnabled = false
H.run(2)
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function act(pl, ...)
	local a = table.pack(...)
	local co = coroutine.create(function() H.Gs[pl.Name].R.Action:FireServer(table.unpack(a, 1, a.n)) end)
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = nil
end

local p1 = H.addPlayer("P1", 9001)
H.run(8)
local G = H.Gs.server
local st = G.states[p1]
local C = H.Gs.P1
local ui = C.ui

print("① 紧凑排版")
check(C.mobile == true and C.compact == true, "认出是手机、用紧凑排版")
check(ui.minimap ~= nil and not ui.minimap.Visible, "不放小地图")
check(H.findButton(p1, "^领取") ~= nil, "每日奖励弹出来了")
H.click(p1, "^领取")
H.run(1)
check(ui.shop.Visible, "兵工厂开着")
H.click(p1, "^收起$")
H.run(0.3)
check(not ui.shop.Visible and H.findButton(p1, "打开兵工厂") ~= nil, "收起后右上角有「打开兵工厂」")
H.click(p1, "打开兵工厂")
H.run(0.3)
check(ui.shop.Visible and H.findButton(p1, "打开兵工厂") == nil, "又打开了")

print("② 盖楼、造兵")
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
st.data.cash = 2e6
for _ = 1, 20 do
	local any = false
	for _, b in G.Config.Buildings do
		local m = plotF.Pads:FindFirstChild("Pad_" .. b.id)
		if m and not st.data.owned[b.id] then
			H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart)
			any = true
		end
	end
	H.run(1.5)
	if not any then break end
end
for _ = 1, 3 do act(p1, "hq") H.run(0.3) end
st.data.cash = 2e6
for _, t in { "transport", "heli", "tank", "ifv", "inf", "inf" } do
	act(p1, "buy", t)
	H.run(0.2)
end
H.run(25)
check(G.count(st) >= 6, "部队 " .. G.count(st) .. " 个")

print("③ 布阵时兵工厂收起，回基地再打开")
H.click(p1, "^布阵$")
H.run(1)
check(C.mode == "deploy" and not ui.shop.Visible, "布阵：兵工厂收起了")
H.click(p1, "^回基地$")
H.run(1)
check(C.mode == "free" and ui.shop.Visible, "回基地：兵工厂打开了")

print("④ 打仗")
H.click(p1, "开战")
H.run(4)
check(st.battle ~= nil, "开打")
-- 第 1 关敌人少，几秒就打完：给敌人加厚血，留时间开直升机
if st.battle then
	for _, u in st.battle.units do
		if u.team == 2 then
			u.hp *= 50
			u.max *= 50
		end
	end
end
check(ui.sbar.Visible and ui.sbar.AnchorPoint.X == 1, "技能栏在右边")
check(not ui.shop.Visible and not ui.goal.Visible, "兵工厂、目标收起来了")
local cash = H.texts(p1, "^%$")
check(#cash == 0, "钱让开了（打仗时不显示）")

print("⑤ 开运兵直升机：升高、降低、放兵")
H.click(p1, "开车")
H.run(0.5)
-- 找「运兵直升机」那一行的「开」
local go = nil
local pg = p1:FindFirstChildOfClass("PlayerGui")
for _, d in pg:GetDescendants() do
	if d:IsA("TextLabel") and H.visible(d) and string.find(d.Text, "^运兵直升机") then
		for _, b in d.Parent:GetChildren() do
			if b:IsA("TextButton") and b.Text == "开" and b.Position.Y.Offset == d.Position.Y.Offset then go = b end
		end
	end
end
check(go ~= nil, "选单里有运兵直升机")
if go then
	H.press(p1, go)
	H.run(1.5)
	check(C.drive ~= nil and C.drive.t == "transport", "开上了运兵直升机")
	check(ui.upBtn.Visible and ui.downBtn.Visible and ui.fireBtn.Visible, "有「升高」「降低」「开火」")
	if C.drive then
		local y0 = C.drive.y
		H.ev(ui.upBtn, "MouseButton1Down"):Fire(0, 0)
		H.run(2)
		H.ev(ui.upBtn, "MouseButton1Up"):Fire(0, 0)
		local y1 = C.drive.y
		check(y1 > y0 + 30, string.format("按住「升高」2 秒：%d → %d", y0, y1))
		H.run(1)
		local inf0 = 0
		for _, u in st.battle.units do
			if u.team == 1 and u.t == "inf" and u.alive then inf0 += 1 end
		end
		H.ev(ui.downBtn, "MouseButton1Down"):Fire(0, 0)
		H.run(6)
		H.ev(ui.downBtn, "MouseButton1Up"):Fire(0, 0)
		H.run(1.5)
		check(C.drive and C.drive.y <= 7, "按住「降低」：降到最低（" .. (C.drive and math.floor(C.drive.y) or -1) .. "）")
		local inf1 = 0
		for _, u in st.battle.units do
			if u.team == 1 and u.t == "inf" and u.alive then inf1 += 1 end
		end
		check(inf1 >= inf0 + 2, string.format("放下了步兵（步兵班 %d → %d）", inf0, inf1))
		check(H.findButton(p1, "^下车$") ~= nil, "有「下车」键（手机上不写 F）")
		H.click(p1, "^下车$")
		H.run(1)
		check(C.drive == nil and not ui.upBtn.Visible, "下车后升降键收起")
	end
end
H.runUntil(function() return st.battle == nil end, 260)
H.run(3)
H.summary()
print(string.format("手机测试：%d 项不对，脚本错误 %d 个", fails, #H.errors))
if fails > 0 or #H.errors > 0 then process.exit(1) end
