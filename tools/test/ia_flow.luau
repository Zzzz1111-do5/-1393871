--!nocheck
-- 全面大战场流程测试：开服生成地图 → 玩家进来分进两队 → 准备阶段选兵种、出生点部署 → 开战 → 开枪打死对面、复活 →
--   乘登陆艇抢滩 → 占领据点（时间 +3 分钟）→ 时间到守方赢 → 结算 → 下一局重新分队
-- 用法（仓库根目录）：lune run tools/test/ia_flow.luau <rbxlx> [v]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
local V3, CF = roblox.Vector3, roblox.CFrame
H.quietWarn = process.args[2] ~= "v"
local clock0 = os.clock()
H.boot(process.args[1], { ds = "mock" })

local fails = 0
local function check(ok, what)
	print((ok and "  通过 " or "  不对 ") .. what)
	if not ok then fails += 1 end
end
local function act(pl, ...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R.Act:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end
local function shoot(pl, ...)
	local a = table.pack(...)
	local prev = H.ctx
	H.ctx = pl
	local co = coroutine.create(function() H.Gs[pl.Name].R.Shoot:FireServer(table.unpack(a, 1, a.n)) end)
	coroutine.resume(co)
	H.ctx = prev
end

print("① 开服：生成地图")
H.run(0.5)
local G = H.Gs.server
G.fortsHold = true   -- 这里测的不是工事：工事不开火（同 tools/mock/*.lua；不然岸防炮会把测试里的登陆艇打沉）
check(G ~= nil, "服务器模块起来了")
G.Config.Bots.minPerTeam = 0   -- 这个测试不要机器人（机器人另有 ia_bots）
local ok = H.runUntil(function() return G.worldReady end, 900)
check(ok, string.format("地图生成完（模拟 %.0f 秒，实际 %.1f 秒）：%s 个地形块、%s 个体素", H.now, os.clock() - clock0, tostring(G.terrainChunks), tostring(G.terrainVoxels)))
check(#G.bootErrors == 0, "开服没有报错：" .. table.concat(G.bootErrors, " | "))
local pts = H.workspace:FindFirstChild("Map") and H.workspace.Map:FindFirstChild("Points")
check(pts ~= nil and #pts:GetChildren() == 5, "5 个据点模型")
check(G.decks ~= nil and #G.decks >= 3, "舰队甲板 " .. tostring(G.decks and #G.decks))

print("② 玩家进来：分队、准备阶段")
local pls = {}
for i = 1, 6 do pls[i] = H.addPlayer("P" .. i, 3000 + i) end
H.run(2)
local nA, nD = G.teamCount("atk", true), G.teamCount("def", true)
check(nA == 3 and nD == 3, "6 个人分成 3 : 3（" .. nA .. " : " .. nD .. "）")
local C1 = H.Gs.P1
check(C1 ~= nil and C1.S ~= nil, "客户端收到了战况")
check(G.round.phase == "prep" or G.round.phase == "battle", "回合阶段 " .. G.round.phase)
local dep = pls[1].PlayerGui:FindFirstChild("Main") and pls[1].PlayerGui.Main:FindFirstChild("Deploy")
-- 选阵营：进服先看选阵营界面（解放军 / 美军两张卡）；人多的一边进不去；点自己这一边的「加入」定下来
-- 进服先到主菜单（Menu.lua），点「进入战斗」才是选阵营
local mg = pls[1].PlayerGui:FindFirstChild("Menu")
check(mg ~= nil and mg.Enabled, "进服先看到主菜单")
-- 主菜单背后是透明的 3D 场景（MenuStage.lua）：下面的部署界面先不画，免得透上来
check(dep ~= nil and not dep.Visible and H.workspace:FindFirstChild("MenuStage") ~= nil, "主菜单开着：背后是 3D 场景，部署界面不透上来")
do
	local prev = H.ctx
	H.ctx = pls[1]
	H.Gs.P1.menuEnter()
	H.ctx = prev
	H.run(0.6)
end
local fg = pls[1].PlayerGui:FindFirstChild("Faction")
check(fg ~= nil and fg.Enabled and not mg.Enabled, "点「进入战斗」后看到选阵营界面")
check(dep ~= nil and dep.Visible, "没出生时显示部署界面")
do
	local P1 = G.P[pls[1]]
	local other = (P1.team == "atk") and "def" or "atk"
	local C1x = H.Gs.P1
	local card = fg:FindFirstChild("Card_" .. other, true)
	local btn = card and card:FindFirstChild("Join")
	check(btn ~= nil and btn.Text == C1x.T("faction.full"), "3 : 3 时对面那一边显示「人数已满」：" .. tostring(btn and btn.Text))
	act(pls[1], "pickTeam", other)
	H.run(0.5)
	check(P1.team ~= other and not P1.picked, "人多的一边进不去")
	local mine = fg:FindFirstChild("Card_" .. P1.team, true)
	local join = mine and mine:FindFirstChild("Join")
	if join then H.press(pls[1], join) end
	H.run(0.6)
	check(P1.picked and not fg.Enabled, "点「加入」定下阵营，选阵营界面关了")
end
for _, pl in ipairs(pls) do act(pl, "pickTeam", G.P[pl].team) end
H.run(0.5)

-- 按队分好
local atk, def = {}, {}
for _, pl in ipairs(pls) do
	local P = G.P[pl]
	table.insert((P.team == "atk") and atk or def, pl)
	check(pl:GetAttribute("Side") == P.team, pl.Name .. " 的 Side 属性 = " .. tostring(pl:GetAttribute("Side")))
end

print("③ 部署：界面上选兵种、出生点，点出击")
local a1, d1 = atk[1], def[1]
local CA, CD = H.Gs[a1.Name], H.Gs[d1.Name]
CA.deploySel.role, CA.deploySel.spawn = "rifle", "fleet"
CA.refreshDeploy()
H.click(a1, "^" .. CA.T("ui.deployBtn") .. "$")
CD.deploySel.role, CD.deploySel.spawn = "engineer", "camp"
CD.refreshDeploy()
H.click(d1, "^" .. CD.T("ui.deployBtn") .. "$")
H.run(2)
local PA, PD = G.P[a1], G.P[d1]
check(PA.alive and a1.Character ~= nil, "攻方 " .. a1.Name .. " 在舰上出生")
check(PD.alive and d1.Character ~= nil, "守方 " .. d1.Name .. " 在营地出生")
if a1.Character then
	local p = a1.Character.HumanoidRootPart.Position
	check(p.Z > 1800, string.format("攻方出生在舰队那边（z = %.0f）", p.Z))
	local tools = {}
	for _, t in ipairs(a1.Backpack:GetChildren()) do table.insert(tools, t.Name) end
	for _, t in ipairs(a1.Character:GetChildren()) do if t:IsA("Tool") then table.insert(tools, t.Name .. "（手里）") end end
	check(#tools == 2, "攻方步枪兵发了 2 件武器（M4、手雷）：" .. table.concat(tools, "、"))
end
if d1.Character then
	local p = d1.Character.HumanoidRootPart.Position
	check(p.Z < -1500, string.format("守方出生在北边营地（z = %.0f）", p.Z))
	check(math.abs(d1.Character.Humanoid.MaxHealth - G.Config.RoleById.engineer.hp) < 0.01, "工兵血量按兵种")
end
-- 夜战：夜晚的光照；头盔、夜视仪、红外频闪；按 N 开夜视（画面调色、镜筒框、服务器那边镜筒翻下来），再按关掉、恢复
local Lighting = H.game:GetService("Lighting")
local Enum = roblox.Enum
check(Lighting.ClockTime < 5 or Lighting.ClockTime > 20, string.format("锁定晚上（用户 11-18：把白天模式去掉）：钟点 %.1f", Lighting.ClockTime))
check(Lighting:FindFirstChild("NightBloom") ~= nil and Lighting:FindFirstChildOfClass("Sky") ~= nil, "泛光、天空（夜里有星空）")
if a1.Character then
	local ch = a1.Character
	check(ch:FindFirstChild("Helmet") and ch:FindFirstChild("NVG") and ch:FindFirstChild("IRStrobe"), "戴着头盔、夜视仪，头盔后面有红外频闪")
	local hinge = ch.NVG:FindFirstChild("NVGHinge")
	-- 锁定晚上（用户 11-18）：出生自动开夜视（全屏调色、镜筒翻下来）；按 N 关掉、再按又开
	-- 测试台里几个客户端共用一个 Lighting：数调色的个数（NVGrade）前后差一份，不看曝光（几个客户端的昼夜都在写）
	local function nGrade()
		local n = 0
		for _, c in ipairs(Lighting:GetChildren()) do if c.Name == "NVGrade" then n += 1 end end
		return n
	end
	H.run(0.9)
	local nv = a1.PlayerGui:FindFirstChild("NVG")
	local nOn = nGrade()
	local cOn = hinge and hinge.C0
	check(CA.nvgOn and CA.nvgOn() and nOn >= 1 and not (nv and nv.Enabled), "锁定晚上：出生自动开了夜视（整个画面调色，全屏，没有望远镜那样的镜筒框）")
	check(ch:GetAttribute("NVG") == true and hinge ~= nil, "镜筒翻下来了（别人也看得到）")
	H.key(a1, Enum.KeyCode.N, true) H.key(a1, Enum.KeyCode.N, false)
	H.run(0.5)
	check(not CA.nvgOn() and nGrade() == nOn - 1, "按 N 关掉")
	check(ch:GetAttribute("NVG") == false and hinge and hinge.C0 ~= cOn, "镜筒翻上去了")
	H.key(a1, Enum.KeyCode.N, true) H.key(a1, Enum.KeyCode.N, false)
	H.run(0.5)
	check(CA.nvgOn() and nGrade() == nOn and ch:GetAttribute("NVG") == true, "再按 N 又开了")
end
local cv = H.workspace.Map.Fleet:FindFirstChild("Ship_carrier1")
local nLights = 0
if cv then for _, x in ipairs(cv:GetDescendants()) do if x:IsA("BillboardGui") and x.Name == "Glow" then nLights += 1 end end end
check(nLights > 60, "航母甲板上的夜灯 " .. nLights .. " 盏（着舰中线、边灯、下降灯、着舰指示器、弹射器、航行灯）")
-- 分阶段突破：第一阶段只列前哨岛的登陆点；准备阶段就能上艇，艇在海上等着，开战一起冲滩
local has = { red = false, outpost = false }
for _, s in ipairs(G.spawnList("atk", G.P[atk[2]])) do
	if s.id == "beach.red" then has.red = true end
	if s.id == "beach.outpost" then has.outpost = s.ok end
end
check(has.outpost and not has.red, "第一阶段只能在前哨岛抢滩（主岛的海滩还没开）")
act(atk[2], "deploy", "rifle", "beach.outpost")
H.run(0.5)
local boat0 = G.P[atk[2]].boat
check(G.P[atk[2]].alive and boat0 ~= nil and boat0.state == "loading", "准备阶段上了登陆艇，在海上等着")

print("④ 开战")
local okB = H.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB, "准备 " .. G.Config.Round.prep .. " 秒后开战")
local st1 = G.Config.Stages[1]
check(G.round.stage == 1 and math.abs((G.round.endsAt - H.now) - st1.time) < 5, "第一阶段（抢滩）限时 " .. st1.time .. " 秒")
check(G.pointActive("A") and not G.pointActive("C"), "第一阶段只能占 A（C 还没开）")
H.run(1.5)
check(boat0 and boat0.state ~= "loading", "开战了艇一起冲滩（" .. tostring(boat0 and boat0.state) .. "）")
local briefA, briefD = a1.PlayerGui.Main.OperationBrief, d1.PlayerGui.Main.OperationBrief
check(briefA.Visible and briefA.Orders.Text == CA.T("stage.beach.atk"), "攻方看到抢滩目标")
check(briefD.Visible and briefD.Orders.Text == CD.T("stage.beach.def"), "守方看到防守目标")
local sweep = H.workspace.Map.Scenery.Lighthouse.LighthouseSweep
local look = sweep.CFrame.LookVector
H.run(0.25)
check((sweep.CFrame.LookVector - look).Magnitude > 0.01 and sweep.SeaHaze:IsA("Beam"), "灯塔的两层光束随转轴扫动")
-- 狙击镜（Scope.lua）：换成狙击手的武器、拿狙击枪、按住右键开镜 → 圆形目镜；服务器记下开着镜、朝哪看（对面画镜片闪光）；滚轮变倍；松开收镜
if a1.Character and PA.alive then
	local ch = a1.Character
	local bp = a1:FindFirstChildOfClass("Backpack")
	local function regive(role)
		for _, c in ipairs(ch:GetChildren()) do if c:IsA("Tool") then c.Parent = bp end end
		H.run(0.3)
		PA.role = role
		G.giveLoadout(PA)
		H.run(0.3)
	end
	regive("sniper")
	H.key(a1, Enum.KeyCode.One, true) H.key(a1, Enum.KeyCode.One, false)
	H.run(0.5)
	H.mouseDown(a1, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.8)
	local sg = a1.PlayerGui:FindFirstChild("Scope")
	check(sg ~= nil and sg.Enabled and CA.scopeOn == true, "狙击枪按住右键：开镜（圆形目镜）")
	check(ch:GetAttribute("Scoped") == true and typeof(ch:GetAttribute("ScopeDir")) == "Vector3", "服务器记下开着镜、朝哪看")
	local z0 = CA.scopeZoom(G.Config.Weapons.sniper)
	H.wheel(a1, 1) H.wheel(a1, 1)
	H.run(0.3)
	local z1 = CA.scopeZoom(G.Config.Weapons.sniper)
	check(z1 > z0, string.format("滚轮变倍：%s 倍 → %s 倍", tostring(z0), tostring(z1)))
	local head = ch:FindFirstChild("Head")
	check(head ~= nil and head:FindFirstChild("ScopeGlint") ~= nil, "对面（守方）那边攻方的镜片上挂了闪光")
	H.mouseUp(a1, 640, 360, Enum.UserInputType.MouseButton2)
	H.run(0.6)
	check(sg ~= nil and not sg.Enabled and not CA.scopeOn and ch:GetAttribute("Scoped") == false, "松开右键：收镜，服务器那边也取消")
	H.run(0.6)
	check(head == nil or head:FindFirstChild("ScopeGlint") == nil, "收镜后闪光也去掉了")
	regive("rifle")
end

print("⑤ 开枪：攻方打死守方，守方等几秒复活")
-- 把两人摆到一处：守方站在攻方正前方 30 格
local pa = V3.new(150, H.map.ground(150, 700) + 3.5, 700)
local pd = V3.new(150, H.map.ground(150, 670) + 3.5, 670)
a1.Character:PivotTo(CF.lookAt(pa, pd))
d1.Character:PivotTo(CF.new(pd))
H.run(0.2)
local hum = d1.Character.Humanoid
local hp0 = hum.Health
-- 客户端开枪（只发准星点）：手里拿着步枪（客户端出生时自动拿起第一件）
local tool = a1.Character:FindFirstChildOfClass("Tool") or a1.Backpack:FindFirstChild("m4")
if tool and tool.Parent ~= a1.Character then tool.Parent = a1.Character end
local wid = tool and tool:GetAttribute("Weapon") or "m4"
check(wid == "m4", "手里是 M4：" .. tostring(wid))
local shots = 0
for i = 1, 60 do
	if hum.Health <= 0 then break end
	shoot(a1, wid, d1.Character.HumanoidRootPart.Position)
	shots += 1
	H.run(0.15)
end
check(hum.Health < hp0, string.format("打中了（%d 发，血 %.0f → %.0f）", shots, hp0, hum.Health))
H.run(0.5)
check(not PD.alive, "守方阵亡")
check(PA.kills == 1, "攻方记一次击杀（" .. PA.kills .. "）")
check(PD.deaths == 1, "守方记一次阵亡")
act(d1, "deploy", "engineer", "camp")
H.run(0.5)
check(not PD.alive, "复活要等 " .. G.Config.RespawnDelay .. " 秒")
H.run(G.Config.RespawnDelay + 0.5)
act(d1, "deploy", "rifle", "camp")
H.run(1)
check(PD.alive, "等够了能复活")

print("⑥ 抢滩：登陆艇把人送上前哨岛的滩")
local a2 = atk[2]
local P2 = G.P[a2]
check(P2.alive, "攻方 " .. a2.Name .. " 还在艇上 / 已经上岸")
local landed = H.runUntil(function()
	local hrp = a2.Character and a2.Character:FindFirstChild("HumanoidRootPart")
	return hrp and not hrp.Anchored and H.map.isLand(hrp.Position.X, hrp.Position.Z)
end, 40)
check(landed, "靠滩后人下艇站到了岸上")

print("⑦ 占领据点 A：攻方 3 人在圈里、没人守")
local A = G.points.A
for i, pl in ipairs(atk) do
	if not G.P[pl].alive then
		act(pl, "deploy", "rifle", "fleet")
		H.run(1.5)
	end
end
for i, pl in ipairs(atk) do
	if pl.Character then
		pl.Character:PivotTo(CF.new(A.x + i * 4, A.y + 3.5, A.z))
		local hrp = pl.Character.HumanoidRootPart
		hrp.Anchored = true   -- 测试台没有物理：钉住，免得别的逻辑挪走
	end
end
for _, pl in ipairs(def) do
	local P = G.P[pl]
	if P.alive and pl.Character then pl.Character:PivotTo(CF.new(0, 100, -2000)) end
end
-- 守方机器人还守在 A 的圈里（地图放大后来不及走开，模拟测试 flow.lua 同样处理）：清掉，「没人守」
for _, e in pairs(G.entById) do
	if e.alive and e.kind == "bot" and e.team == "def" then
		local p = e.root.CFrame.Position
		if (p.X - A.x) ^ 2 + (p.Z - A.z) ^ 2 < 300 * 300 then G.damageEnt(e, 1e6, nil) end
	end
end
local tk0 = G.round.tickets
H.run(2)
check(A.prog > 0, string.format("占领进度在涨（%.2f）", A.prog))
local nearby = a1.PlayerGui.Main.ObjectiveStatus
check(nearby.Visible and nearby.Status.Text == CA.T("operation.capturing"), "占领区内显示服务器的推进状态")
check(not d1.PlayerGui.Main.ObjectiveStatus.Visible, "离开占领区的玩家不显示据点状态")
local capOk = H.runUntil(function() return A.owner == "atk" end, G.Config.Capture.fast + 10)
check(capOk, "15 秒左右拿下 A（攻方多 3 人）")
check(A.locked, "拿下后锁定")
local st2 = G.Config.Stages[2]
check(G.round.stage == 2 and math.abs((G.round.endsAt - H.now) - st2.time) < 3, "拿下 A 进入第二阶段（主岛），重新计时 " .. st2.time .. " 秒")
check((G.round.tickets or 0) >= tk0 + G.Config.Tickets.perStage - 5, string.format("攻方兵力补了（%d → %d）", tk0 or -1, G.round.tickets or -1))
check(G.pointActive("C") and G.pointActive("D") and not G.pointActive("E"), "第二阶段能占 C、D，E 还没开")
local spA = false
for _, s in ipairs(G.spawnList("atk", G.P[atk[1]])) do if s.id == "point.A" and s.ok then spA = true end end
check(spA, "攻方可以在 A 出生")
-- 攻击出发阵地（第二阶段起）：C、D 前面各一处，守方没压过来就能用、推荐它，不在守方碉堡的射界里（同 tools/mock/flow.lua）
local stg, recK = {}, nil
for _, s in ipairs(G.spawnList("atk", G.P[atk[1]])) do
	if s.kind == "staging" then stg[s.point] = s end
	if s.rec then recK = s.kind end
end
check(stg.C ~= nil and stg.C.ok and stg.D ~= nil and stg.D.ok, "第二阶段 C、D 前面各有攻击出发阵地能出生")
check(recK == "staging", "推荐的出生点是攻击出发阵地（" .. tostring(recK) .. "）")
check(stg.D ~= nil and not G.stagingCovered(stg.D.x, stg.D.z), "机场 D 的出发阵地不在守方碉堡的射界里")
-- 重新部署（H）：不算阵亡、不扣兵力，回部署界面；接着在 D 的出发阵地出生
local Pr = G.P[atk[2]]
Pr.dmgLog = {}
local d0, tk1 = Pr.deaths, G.round.tickets
act(atk[2], "redeploy")
H.run(0.5)
check(not Pr.alive and Pr.deaths == d0 and G.round.tickets == tk1, string.format("按 H 重新部署：回部署界面，不算阵亡（%d → %d）、不扣兵力（%d → %d）", d0, Pr.deaths, tk1, G.round.tickets))
act(atk[2], "deploy", "rifle", "stage.D")
H.run(1.5)
local hrpR = atk[2].Character and atk[2].Character:FindFirstChild("HumanoidRootPart")
check(Pr.alive and hrpR ~= nil and stg.D ~= nil and ((hrpR.Position.X - stg.D.x) ^ 2 + (hrpR.Position.Z - stg.D.z) ^ 2) ^ 0.5 < 40, "在 D 的攻击出发阵地出生")
H.run(1)
check(CA.S.points[1].owner == "atk", "客户端顶栏上 A 变成攻方")
check(briefA.Visible and briefA.Title.Text == CA.T("stage." .. G.Config.Stages[2].id) and not nearby.Visible, "进入第二阶段显示简报并收起旧据点（" .. briefA.Title.Text .. "）")
local briefLate = atk[3].PlayerGui.Main.OperationBrief
check(briefLate.Title.Text == H.Gs[atk[3].Name].T("stage." .. G.Config.Stages[2].id), "活着进入新阶段的队友也读到了当前目标")
H.run(5)
check(not briefA.Visible, "同一阶段持续收战况时简报不会重复显示")

print("⑧ 时间到守方赢 → 结算 → 下一局")
G.round.endsAt = H.now + 1
for _, pl in ipairs(atk) do
	if pl.Character then pl.Character.HumanoidRootPart.Anchored = false pl.Character:PivotTo(CF.new(0, 100, 2100)) end
end
local over = H.runUntil(function() return G.round.phase == "end" end, 10)
check(over and G.round.winner == "def", "时间到、守方手里还有据点 → 守方赢（" .. tostring(G.round.winner) .. "）")
H.run(1)
local res = #H.texts(d1, "^" .. CD.T("ui.youWon") .. "$") > 0
check(res, "守方看到胜利结算：" .. table.concat(H.texts(d1, CD.T("ui.youWon")), "|"))
local nxt = H.runUntil(function() return G.round.phase == "prep" and G.round.n == 2 end, G.Config.Round.results + 5)
check(nxt, "结算后开下一局")
nA, nD = G.teamCount("atk", true), G.teamCount("def", true)
check(nA == 3 and nD == 3, "重新分队 3 : 3")
check(G.points.A.owner == "def" and not G.points.A.locked, "据点重置")
H.run(1)
local C1s = H.Gs.P1.S
check(not G.P[pls[1]].alive and pls[1].PlayerGui.Main.Deploy.Visible, string.format("新一局回到部署界面（alive=%s 客户端 alive=%s phase=%s）", tostring(G.P[pls[1]].alive), tostring(C1s.alive), tostring(C1s.phase)))

print("⑨ 有人退出")
H.removePlayer(pls[6])
H.run(1)
check(G.P[pls[6]] == nil, "退出的人清掉了")

H.summary()
local errs = {}
for _, e in ipairs(H.errors) do table.insert(errs, e) end
for i, e in ipairs(errs) do
	if i > 12 then break end
	print("  错误：" .. tostring(e.where) .. " " .. tostring(e.err or e.msg))
end
for i, w in ipairs(H.warns) do if i <= 8 then print("  警告：" .. w.side .. " " .. w.msg) end end
if #H.errors > 0 then fails += 1 end
print(fails == 0 and "全部通过" or ("不对 " .. fails .. " 处"))
process.exit(fails == 0 and 0 or 1)
