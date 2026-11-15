--!nocheck
-- 登岛战流程测试：开服生成地图 → 玩家进来分进两队 → 准备阶段选兵种、出生点部署 → 开战 → 开枪打死对面、复活 →
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
check(G ~= nil, "服务器模块起来了")
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
check(dep ~= nil and dep.Visible, "没出生时显示部署界面")

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
CD.deploySel.role, CD.deploySel.spawn = "mg", "camp"
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
	check(#tools == 3, "攻方步枪兵发了 3 件武器：" .. table.concat(tools, "、"))
end
if d1.Character then
	local p = d1.Character.HumanoidRootPart.Position
	check(p.Z < -1500, string.format("守方出生在北边营地（z = %.0f）", p.Z))
	check(math.abs(d1.Character.Humanoid.MaxHealth - G.Config.RoleById.mg.hp) < 0.01, "机枪手血量按兵种")
end
-- 其余人：攻方抢滩不能在准备阶段选
act(atk[2], "deploy", "rifle", "beach.red")
H.run(0.5)
check(not G.P[atk[2]].alive, "准备阶段不能选抢滩")

print("④ 开战")
local okB = H.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB, "准备 " .. G.Config.Round.prep .. " 秒后开战")
check(math.abs((G.round.endsAt - H.now) - G.Config.Round.battle) < 5, "战斗时间 " .. G.Config.Round.battle .. " 秒")

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
local tool = a1.Character:FindFirstChildOfClass("Tool") or a1.Backpack:FindFirstChild("rifle")
if tool and tool.Parent ~= a1.Character then tool.Parent = a1.Character end
local wid = tool and tool:GetAttribute("Weapon") or "rifle"
check(wid == "rifle", "手里是步枪：" .. tostring(wid))
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
act(d1, "deploy", "mg", "camp")
H.run(0.5)
check(not PD.alive, "复活要等 " .. G.Config.RespawnDelay .. " 秒")
H.run(G.Config.RespawnDelay + 0.5)
act(d1, "deploy", "rifle", "camp")
H.run(1)
check(PD.alive, "等够了能复活")

print("⑥ 抢滩：登陆艇把人送上滩")
local a2 = atk[2]
act(a2, "deploy", "rifle", "beach.red")
H.run(1)
local P2 = G.P[a2]
check(P2.alive, "攻方 " .. a2.Name .. " 上了登陆艇")
local z0 = a2.Character and a2.Character.HumanoidRootPart.Position.Z or 0
H.run(8)
local z1 = a2.Character and a2.Character.HumanoidRootPart.Position.Z or 0
check(z1 < z0 - 100, string.format("艇往岸边开（z %.0f → %.0f）", z0, z1))
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
local endsBefore = G.round.endsAt
H.run(2)
check(A.prog > 0, string.format("占领进度在涨（%.2f）", A.prog))
local capOk = H.runUntil(function() return A.owner == "atk" end, G.Config.Capture.fast + 10)
check(capOk, "15 秒左右拿下 A（攻方多 3 人）")
check(A.locked, "拿下后锁定")
check(math.abs((G.round.endsAt - endsBefore) - G.Config.Round.perCapture) < 0.01, "战斗时间 +" .. G.Config.Round.perCapture .. " 秒")
local spA = false
for _, s in ipairs(G.spawnList("atk", G.P[atk[1]])) do if s.id == "point.A" and s.ok then spA = true end end
check(spA, "攻方可以在 A 出生")
H.run(1)
check(CA.S.points[1].owner == "atk", "客户端顶栏上 A 变成攻方")

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
