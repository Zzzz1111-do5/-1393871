--!nocheck
-- 地图指引、建筑动画测试：地上箭头指向目标按钮、小地图有点、新楼从地下升起来再回原位、雷达在转、按钮在呼吸
-- 用法：lune run visual.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3 = roblox.Vector3
H.quietWarn = true
H.followCam = true
H.boot(process.args[1])
H.run(2)
local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local p1 = H.addPlayer("P1", 5001)
H.run(8)
local G = H.Gs.server
local st = G.states[p1]
local C1 = H.Gs.P1
H.click(p1, "^领取$")
H.run(1)

print("① 地上的箭头、小地图")
local fx = H.workspace:FindFirstChild("ClientFx")
local function arrows()
	local n, near = 0, math.huge
	local pad = C1.goalPadPart and C1.goalPadPart()
	for _, p in fx:GetChildren() do
		if p:IsA("BasePart") and p.Size.Z > 3 and p.Size.Y < 0.2 and p.Transparency < 0.9 then
			n += 1
			if pad then near = math.min(near, (p.CFrame.Position - pad.CFrame.Position).Magnitude) end
		end
	end
	return n, near
end
local n, near = arrows()
check(n >= 4, "地上有一串箭头（" .. n .. " 根亮着的条）")
local root = p1.Character.HumanoidRootPart
local pad = C1.goalPadPart()
local dist = (root.CFrame.Position - pad.CFrame.Position).Magnitude
check(near < dist, string.format("箭头往目标按钮那边排（离按钮最近 %.0f 格，人离按钮 %.0f 格）", near, dist))
check(C1.ui.minimap and H.visible(C1.ui.minimap), "小地图看得见")
local dots = 0
for _, d in C1.ui.minimap:GetDescendants() do
	if d:IsA("Frame") and d.Parent and d.Parent.Name == "Dynamic" then dots += 1 end
end
check(dots >= 1, "小地图上有按钮 / 部队的点（" .. dots .. " 个）")
-- 走到按钮旁边：箭头收起来
p1.Character:PivotTo(pad.CFrame + V3.new(0, 3, 0))
H.run(0.5)
local n2 = arrows()
check(n2 == 0, "走到按钮跟前箭头就收起来")

print("② 盖楼动画")
local plotF = H.workspace.Plots["Plot" .. st.plot.index]
H.ev(plotF.Pads.Pad_house1.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart)
H.run(0.1)
local m = plotF.Buildings:FindFirstChild("house1")
check(m ~= nil and type(m:GetAttribute("BuiltAt")) == "number", "新楼带着 BuiltAt")
H.run(0.3)
local body = m and m:FindFirstChild("Body")
local y0 = body and body.CFrame.Position.Y
local final = G.buildingPos(st.plot, G.Config.BuildingById.house1).Y
check(body ~= nil and y0 < final - 3, string.format("刚盖时楼沉在地下（主体中心 y %.1f，地面 %.1f）", y0 or 0, final))
H.run(3)
local y1 = body.CFrame.Position.Y
check(math.abs(y1 - (final + 0.6 + 16 / 2)) < 0.5, string.format("升起来回到原位（y %.1f）", y1))
local poles = 0
for _, p in fx:GetChildren() do if p:IsA("BasePart") and p.Color == roblox.Color3.fromRGB(240, 190, 40) then poles += 1 end end
check(poles == 0, "脚手架收掉了")

print("③ 雷达转、灯闪、按钮呼吸")
st.data.cash = 1e6
for _, id in { "barracks", "hq" } do
	H.run(1.5)
	local pm = plotF.Pads:FindFirstChild("Pad_" .. id)
	if pm then H.ev(pm.Pad, "Touched"):Fire(p1.Character.HumanoidRootPart) end
end
H.run(4)
local hq = plotF.Buildings:FindFirstChild("hq")
local dish, light
for _, d in hq:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Anim") == "spin" then dish = d end
	if d:IsA("BasePart") and d:GetAttribute("Anim") == "blink" then light = d end
end
check(dish ~= nil and light ~= nil, "指挥部有转的雷达、闪的灯")
local c1 = dish.CFrame
H.run(0.7)
local c2 = dish.CFrame
check((c1.LookVector - c2.LookVector).Magnitude > 0.05 and (c1.Position - c2.Position).Magnitude < 0.01, "雷达原地转")
local trs = {}
for _ = 1, 20 do
	H.run(0.1)
	trs[light.Transparency] = true
end
local kinds = 0
for _ in pairs(trs) do kinds += 1 end
check(kinds >= 2, "指示灯一亮一暗")
local anyPad
for _, pm in plotF.Pads:GetChildren() do
	if pm:FindFirstChild("Pad") and pm.Pad.Color == roblox.Color3.fromRGB(70, 220, 100) then anyPad = pm.Pad end
end
if anyPad then
	local seen = {}
	for _ = 1, 12 do
		H.run(0.1)
		seen[math.floor(anyPad.Transparency * 100)] = true
	end
	local k = 0
	for _ in pairs(seen) do k += 1 end
	check(k >= 3, "买得起的按钮一呼一吸")
end
H.summary()
print(string.format("指引 / 动画测试：%d 项不对，脚本错误 %d 个", fails, #H.errors))
if fails > 0 or #H.errors > 0 then process.exit(1) end
