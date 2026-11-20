--!nocheck
-- 操作手感（用户：第一人称持枪参考 bodycam；坦克驾驶参考战雷）
--   ① 步行第一人称：记录仪观感开着（暗角、REC、时间），准星四根线不画、只有中间一个淡点；镜头跟着步子晃但不会越晃越偏
--   ② 上坦克：记录仪观感关掉；往前开：变速箱一档一档往上换（仪表显示档位数字），地上留下履带印
--   用法：lune run tools/test/ia_feel.luau <rbxlx>
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Enum = roblox.Enum
H.quietWarn = true

H.boot(process.args[1], { ds = "mock" })
H.run(0.5)
local G = H.Gs.server
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
H.runUntil(function() return G.worldReady end, 120)
local p1, p2 = H.addPlayer("P1", 8101), H.addPlayer("P2", 8102)
H.run(2)
local def = (G.P[p1].team == "def") and p1 or p2
H.removePlayer((def == p1) and p2 or p1)
H.run(0.5)
local CD = H.Gs[def.Name]
local cam = H.workspace.CurrentCamera

local fails = 0
local function check(ok, msg)
	print((ok and "  ✓ " or "  ✗ ") .. msg)
	if not ok then fails += 1 end
end
local function as(who, f)
	local prev = H.ctx
	H.ctx = who
	local co = coroutine.create(f)
	coroutine.resume(co)
	H.ctx = prev
end
local function act(who, ...)
	local a = table.pack(...)
	as(who, function() H.Gs[who.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
end
local function find(name)
	for _, d in def.PlayerGui:GetDescendants() do
		if d.Name == name then return d end
	end
end

print("① 步行第一人称：记录仪观感")
act(def, "deploy", "rifle", "camp")
H.run(3)
check(CD.fpActive == true, "第一人称")
check(CD.bodycamState and CD.bodycamState.on == true, "记录仪观感开着")
local bc = def.PlayerGui:FindFirstChild("Bodycam")
check(bc ~= nil and bc.Enabled, "暗角、噪点、REC 那一层在")
local clock = find("BodycamClock")
check(clock ~= nil and clock.Text:match("^%d%d%d%d%-%d%d%-%d%d  %d%d:%d%d:%d%d$") ~= nil, "右边写着日期时间：" .. tostring(clock and clock.Text))
local cross = find("Crosshair")
check(cross ~= nil and not cross.Visible, "第一人称不画四根线的准星")
local dot = find("BodycamDot")
check(dot ~= nil and dot.Visible, "中间一个淡淡的小点")
-- 不动的时候镜头一直在原地（每帧先撤掉上一帧的晃，不会越晃越偏）
local look0 = cam.CFrame.LookVector
local pos0 = cam.CFrame.Position
H.run(3)
local drift = (cam.CFrame.LookVector - look0).Magnitude
local pdrift = (cam.CFrame.Position - pos0).Magnitude
check(drift < 0.02 and pdrift < 0.6, string.format("站着三秒镜头没跑偏（朝向差 %.4f，位置差 %.2f）", drift, pdrift))

print("③ 手雷：按住右键画抛物线，炸点跟服务器扔出去的一样")
do
	-- 服务器那边记下手雷在哪炸的
	local boomAt = nil
	local prevEx = G.onExplode
	G.onExplode = function(pos, w, src, ...)
		if not boomAt and w and w.kind == "throw" then boomAt = pos end
		if prevEx then return prevEx(pos, w, src, ...) end
	end
	H.runUntil(function() return G.round.phase == "battle" end, 120)   -- 准备阶段不能开火、扔雷
	H.run(0.5)
	-- 换到手雷
	H.key(def, Enum.KeyCode.Two, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.Two, false)
	H.run(1.2)
	H.mouseDown(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.4)
	local arc = CD.nadeArc
	check(arc ~= nil and arc.on == true, "拿着手雷按住右键：画出抛物线")
	local pred = arc and arc.boom
	check(pred ~= nil, "画出了炸点（红圈）：" .. tostring(pred))
	local dotsOn = 0
	for _, f in H.workspace:GetChildren() do   -- 每个客户端一个 NadeArc（走了的那个人的还留着）：取画出来最多的那个
		if f.Name == "NadeArc" then
			local n = 0
			for _, d in f:GetChildren() do if d.Transparency < 0.9 then n += 1 end end
			dotsOn = math.max(dotsOn, n)
		end
	end
	check(dotsOn >= 30, "一串小点 + 圈：" .. dotsOn .. " 个")
	-- 照预览那一刻的准星点，让服务器按它自己的算法扔（Weapons.lua 的 G.shoot → KIND.throw）
	-- 同一帧取预览的炸点和准星点（记录仪的呼吸会让准星一点点动：隔几帧准星点就不一样了）
	pred = CD.nadeArc and CD.nadeArc.boom or pred
	local aim = CD.aimPoint(G.Config.Weapons.grenade.range or 90)
	H.ctx = nil
	-- 测试台里客户端拿起工具不会同步到服务器：服务器那边也把手雷拿到手上
	local PD = G.P[def]
	local char = PD.char
	local bp = def:FindFirstChildOfClass("Backpack")
	for _, t in (char and char:GetChildren() or {}) do   -- 手上只留手雷（测试台里客户端换武器时原来那把还留在手上）
		if t:IsA("Tool") and t:GetAttribute("Weapon") ~= "grenade" and bp then t.Parent = bp end
	end
	if char and not char:FindFirstChildOfClass("Tool") and bp then
		for _, t in bp:GetChildren() do
			if t:IsA("Tool") and t:GetAttribute("Weapon") == "grenade" then t.Parent = char end
		end
	end
	G.shoot(PD, "grenade", aim)
	local nNade = 0
	for _, sh in ipairs(G.shots or {}) do if sh.kind == "grenade" then nNade += 1 end end
	check(nNade >= 1, "服务器扔出了手雷")
	H.mouseUp(def, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(4)
	check(boomAt ~= nil, "手雷扔出去炸了")
	if boomAt and pred then
		local dd = (boomAt - pred).Magnitude
		check(dd < 8, string.format("炸点跟预览差 %.1f 格", dd))
	end
	H.run(0.3)
	check(CD.nadeArc and CD.nadeArc.on == false, "松开右键：抛物线收起来")
	G.onExplode = prevEx
	H.key(def, Enum.KeyCode.One, true)
	H.run(0.1)
	H.key(def, Enum.KeyCode.One, false)
	H.run(0.5)
end

print("② 坦克：变速箱、履带印")
local tp = H.pad(G, "m1a2")
local e = tp and H.usePad(G, def, tp)
if e then act(def, "enterVeh", e.id) end
H.run(2)
local st = CD.drive
check(st ~= nil, "坐上了 M1A2")
check(CD.bodycamState and CD.bodycamState.on == false, "开车时记录仪观感关掉")
if st then
	local n0 = CD.trackMarkCount and CD.trackMarkCount() or 0
	local maxGear = 0
	H.key(def, Enum.KeyCode.W, true)
	for _ = 1, 60 do
		H.run(0.1)
		maxGear = math.max(maxGear, st.gearN or 0)
	end
	H.key(def, Enum.KeyCode.W, false)
	H.run(0.5)
	check(maxGear >= 3, string.format("一档一档往上换（最高到 %d 档，车速 %.0f）", maxGear, math.abs(st.speed or 0)))
	local gear = find("Gear")
	check(gear ~= nil and (gear.Text:match("^%d$") ~= nil or gear.Text == "N"), "仪表上显示档位：" .. tostring(gear and gear.Text))
	local n1 = CD.trackMarkCount and CD.trackMarkCount() or 0
	check(n1 > n0 + 4, string.format("地上留下履带印（%d 段）", n1 - n0))
end

print(fails == 0 and "手感：全部通过" or ("手感：" .. fails .. " 项没过"))
H.shutdown()
process.exit(fails == 0 and 0 or 1)
