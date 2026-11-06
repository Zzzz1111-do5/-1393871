--!nocheck
-- 建筑升级、工业区测试：升级扣钱、收入涨、楼变高、牌子上有级数；楼旁边的提示和「建筑」面板都能升；满级；
-- 炼油厂给油井加成、核电站给工厂加成；工业区的楼都盖在西墙外的工业区里；存档读回级数；重生清掉级数
-- 用法：lune run upgrade.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = true
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
	H.ctx = pl
	coroutine.resume(co)
	H.ctx = nil
end

local p1 = H.addPlayer("P1", 7101)
H.run(8)
local G = H.Gs.server
local Config = G.Config
local st = G.states[p1]
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
H.click(p1, "^领取")
H.run(1)
local function touch(id)
	local m = plotF.Pads:FindFirstChild("Pad_" .. id)
	if m then H.ev(m.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
	return m ~= nil
end
local function bodyH(id)
	local m = plotF.Buildings:FindFirstChild(id)
	local b = m and m:FindFirstChild("Body")
	return b and b.Size.Y or 0
end

print("① 升级扣钱、收入涨、楼变高")
st.data.cash = 1000
touch("house1")
H.run(2)
local B1 = Config.BuildingById.house1
local inc0, cash0, h0 = st.income, st.data.cash, bodyH("house1")
act(p1, "upgrade", "house1")
H.run(2.5)
check(st.data.lv.house1 == 2, "居民楼 A 升到 Lv.2")
check(math.abs((cash0 + st.income * 0) - st.data.cash - Config.UpgradeCost(B1, 1)) <= st.income * 3 + 1, "扣了 $" .. Config.UpgradeCost(B1, 1))
check(math.abs(st.income - inc0 - B1.income * Config.Upgrade.inc) < 0.01, string.format("收入 %.1f → %.1f", inc0, st.income))
check(bodyH("house1") > h0 + 3, string.format("楼变高了（%.0f → %.0f）", h0, bodyH("house1")))
local sign = nil
for _, d in plotF.Buildings.house1:GetDescendants() do
	if d:IsA("TextLabel") and string.find(d.Text, "Lv.2", 1, true) then sign = d end
end
check(sign ~= nil, "楼顶牌子写着 Lv.2")

print("② 楼旁边的提示、「建筑」面板")
st.data.cash = 1e6
local pp = nil
for _, d in plotF.Buildings.house1:GetDescendants() do
	if d:IsA("ProximityPrompt") then pp = d end
end
check(pp ~= nil and string.find(pp.ActionText, "Lv.3", 1, true) ~= nil, "旁边的提示：升级到 Lv.3")
if pp then
	H.ev(pp, "Triggered"):Fire(p1)
	H.run(2.5)
end
check(st.data.lv.house1 == 3, "按 E 升到 Lv.3")
H.click(p1, "^建筑$")
H.run(0.6)
local up = H.findButton(p1, "^升级 %$")
check(up ~= nil, "「建筑」面板里有升级按钮")
if up then
	H.press(p1, up)
	H.run(2.5)
end
check(st.data.lv.house1 == 4, "面板里点一下升到 Lv.4")
act(p1, "upgrade", "house1")
H.run(2.5)
act(p1, "upgrade", "house1")
H.run(2.5)
check(st.data.lv.house1 == Config.Upgrade.max, "最多 Lv." .. Config.Upgrade.max)
check(#H.texts(p1, "满级") > 0, "满级了有提示")
pp = nil
for _, d in plotF.Buildings.house1:GetDescendants() do
	if d:IsA("ProximityPrompt") then pp = d end
end
check(pp ~= nil and pp.Enabled == false, "满级后旁边的升级提示关掉")
check(math.abs(Config.BuildingIncome(B1, st.data.owned, 5) - B1.income * 3) < 0.01, "Lv.5 收入是原来的 3 倍")
act(p1, "upgrade", "hq")
act(p1, "upgrade", "nope")
act(p1, "upgrade", 12)
H.run(0.5)
check(st.data.lv.hq == nil, "没收入的楼、乱传的参数不能升")

print("③ 工业区：位置、加成")
st.data.cash = 1e9
for _ = 1, 20 do
	local any = false
	for _, b in Config.Buildings do
		if not st.data.owned[b.id] and touch(b.id) then any = true end
	end
	H.run(1.5)
	if not any then break end
end
H.run(3)
local I = Config.Industry
local inZone = 0
for _, id in { "oil1", "oil2", "oil3", "refinery", "ammo", "steel", "mine", "nuclear" } do
	local b = Config.BuildingById[id]
	local m = plotF.Buildings:FindFirstChild(id)
	if m and b.x > I.x0 and b.x < I.x1 and b.z > I.z0 and b.z < I.z1 then inZone += 1 end
end
check(inZone == 8, "工业区八栋楼都盖好了，都在西墙外的工业区里（" .. inZone .. " / 8）")
local o = st.data.owned
check(o.refinery and math.abs(Config.BuildingIncome(Config.BuildingById.oil1, o, 1) - 15 * Config.RefineryBoost) < 0.01, "炼油厂：油井收入 ×" .. Config.RefineryBoost)
check(o.nuclear and math.abs(Config.BuildingIncome(Config.BuildingById.factory1, o, 1) - 20 * Config.PowerBoost * Config.NuclearBoost) < 0.01, "核电站：工厂收入再 ×" .. Config.NuclearBoost)
local ind = plotF:FindFirstChild("Industry")
check(ind ~= nil and #ind:GetChildren() > 20, "工业区有地面、路、围栏、路灯")
-- 动画：抽油机点头、传送带上有弹药箱在走
local C1 = H.Gs.P1
local beam
for _, d in plotF.Buildings.oil1:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Anim") == "nod" then beam = d end
end
H.followCam = false
H.workspace.CurrentCamera.CFrame = roblox.CFrame.new(st.plot.origin + roblox.Vector3.new(-200, 40, -150), st.plot.origin + roblox.Vector3.new(-220, 0, -60))
H.run(0.3)
local y1 = beam and beam.CFrame.LookVector.Y
H.run(1.2)
local y2 = beam and beam.CFrame.LookVector.Y
check(beam ~= nil and math.abs(y1 - y2) > 0.02, "抽油机在点头")
local crates = 0
local fx = H.workspace:FindFirstChild("ClientFx")
if fx then
	for _, p in fx:GetChildren() do
		if p:IsA("BasePart") and p.Color == roblox.Color3.fromRGB(78, 92, 58) then crates += 1 end
	end
end
check(crates >= 4, "弹药厂传送带上有弹药箱（" .. crates .. " 个）")

print("④ 存档读回级数，重生清掉")
act(p1, "upgrade", "oil1")
H.run(2.5)
local lvOil = st.data.lv.oil1
H.removePlayer(p1)
H.run(3)
local p1b = H.addPlayer("P1", 7101)
H.run(8)
local st2 = G.states[p1b]
plotF = H.workspace.Plots["Plot" .. st2.plot.index]
check(st2.data.lv.house1 == 5 and st2.data.lv.oil1 == lvOil, "重进后级数还在（居民楼 A Lv." .. tostring(st2.data.lv.house1) .. "，油井 A Lv." .. tostring(st2.data.lv.oil1) .. "）")
check(bodyH("house1") > 30, string.format("重进后居民楼 A 还是 Lv.5 的高度（%.0f）", bodyH("house1")))
st2.data.level = Config.Rebirth.level
act(p1b, "rebirth")
H.run(2)
check(st2.data.rebirth == 1 and next(st2.data.lv) == nil, "重生后级数清零")
H.summary()
print(string.format("升级 / 工业区测试：%d 项不对，脚本错误 %d 个", fails, #H.errors))
if fails > 0 or #H.errors > 0 then process.exit(1) end
