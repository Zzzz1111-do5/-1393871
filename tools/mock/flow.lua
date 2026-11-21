-- 流程测试（照 tools/test/ia_flow.luau，在没有 Lune 的机器上用模拟器跑）：
--   开服生成地图 → 6 人进来分成两队 → 准备阶段选兵种、出生点部署 → 开战 → 开枪打死对面、复活 →
--   乘登陆艇抢滩 → 占领据点（时间 +3 分钟）→ 时间到守方赢 → 结算 → 下一局重新分队 → 有人退出
--   python3 tools/mock/run.py tools/mock/flow.lua
-- 模拟器同一时间只跑一个客户端：P1 跑客户端（界面上点出击、看结算），其余人直接往服务器发操作
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

print("① 开服：生成地图")
local G = T.boot()
G.fortsHold = true   -- 这里测的不是工事：工事不开火
check(G ~= nil, "服务器模块起来了")
G.Config.Bots.minPerTeam = 0
local ok = T.runUntil(function() return G.worldReady end, 900)
check(ok, string.format("地图生成完：%s 个地形块、%s 个体素", tostring(G.terrainChunks), tostring(G.terrainVoxels)))
check(#G.bootErrors == 0, "开服没有报错：" .. table.concat(G.bootErrors, " | "))
local map = workspace and workspace:FindFirstChild("Map") or R.services.Workspace:FindFirstChild("Map")
local pts = map and map:FindFirstChild("Points")
check(pts ~= nil and #pts:GetChildren() == 5, "5 个据点模型")
check(G.decks ~= nil and #G.decks >= 3, "舰队甲板 " .. tostring(G.decks and #G.decks))

print("② 玩家进来：分队、准备阶段")
local pls = {}
for i = 1, 6 do pls[i] = T.join("P" .. i, 3000 + i, i == 1) end
R.run(2)
local nA, nD = G.teamCount("atk", true), G.teamCount("def", true)
check(nA == 3 and nD == 3, "6 个人分成 3 : 3（" .. nA .. " : " .. nD .. "）")
local C = T.C
check(C ~= nil and C.S ~= nil, "客户端收到了战况")
check(G.round.phase == "prep" or G.round.phase == "battle", "回合阶段 " .. G.round.phase)
local dep = pls[1].PlayerGui:FindFirstChild("Main") and pls[1].PlayerGui.Main:FindFirstChild("Deploy")
-- 进服先到主菜单（背后是透明的 3D 场景，部署界面先不画）；点「进入战斗」后才有部署界面（同 Luau 的 ia_flow）
if C.menuShown and C.menuShown() then
  check(dep ~= nil and not dep.Visible, "主菜单开着：部署界面不透上来")
  C.menuEnter()
  R.run(0.5)
end
check(dep ~= nil and dep.Visible, "没出生时显示部署界面")
local atk, def = {}, {}
for _, pl in ipairs(pls) do
  local P = G.P[pl]
  table.insert((P.team == "atk") and atk or def, pl)
  check(pl:GetAttribute("Side") == P.team, pl.Name .. " 的 Side 属性 = " .. tostring(pl:GetAttribute("Side")))
end
-- 跑客户端的 P1 排在自己队的第一个
local function front(list) for i, pl in ipairs(list) do if pl == pls[1] then table.remove(list, i) table.insert(list, 1, pl) end end end
front(atk)
front(def)

print("③ 部署：界面上选兵种、出生点，点出击")
local a1, d1 = atk[1], def[1]
local function deployUI(pl, role, spawn)
  if pl == pls[1] then
    C.deploySel.mode, C.deploySel.role, C.deploySel.spawn = "inf", role, spawn
    R.as("client", function() C.refreshDeploy() end)
    T.click("^" .. C.T("ui.deployBtn") .. "$")
  else
    T.actAsRemote(pl, "deploy", role, spawn)
  end
end
deployUI(a1, "rifle", "fleet")
deployUI(d1, "engineer", "camp")
R.run(2)
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
-- 分阶段突破：第一阶段只列前哨岛的登陆点；准备阶段就能上艇，艇在海上等着，开战一起冲滩
local has = { red = false, outpost = false }
for _, s in ipairs(G.spawnList("atk", G.P[atk[2]])) do
  if s.id == "beach.red" then has.red = true end
  if s.id == "beach.outpost" then has.outpost = s.ok end
end
check(has.outpost and not has.red, "第一阶段只能在前哨岛抢滩（主岛的海滩还没开）")
T.actAsRemote(atk[2], "deploy", "rifle", "beach.outpost")
R.run(0.5)
local boat0 = G.P[atk[2]].boat
check(G.P[atk[2]].alive and boat0 ~= nil and boat0.state == "loading", "准备阶段上了登陆艇，在海上等着")
R.run(5)
check(boat0 and boat0.state == "loading", "准备阶段艇不开（等开战一起冲）")

print("④ 开战")
local okB = T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB, "准备 " .. G.Config.Round.prep .. " 秒后开战")
local st1 = G.Config.Stages[1]
check(G.round.stage == 1 and math.abs((G.round.endsAt - R.clock()) - st1.time) < 5, "第一阶段（抢滩）限时 " .. st1.time .. " 秒")
check((G.round.tickets or 0) >= G.Config.Tickets.start, "攻方兵力 " .. tostring(G.round.tickets))
local actA, actC = G.pointActive("A"), G.pointActive("C")
check(actA and not actC, "第一阶段只能占 A（C 还没开）")
R.run(1.5)
check(boat0 and boat0.state ~= "loading", "开战了艇一起冲滩（" .. tostring(boat0 and boat0.state) .. "）")
local brief = pls[1].PlayerGui.Main.OperationBrief
check(brief.Visible and brief.Orders.Text == C.T("stage.beach." .. C.S.team), "开战简报显示本阵营目标")
local sweep = map.Scenery.Lighthouse.LighthouseSweep
local look = sweep.CFrame.LookVector
R.run(0.25)
check((sweep.CFrame.LookVector - look).Magnitude > 0.01 and sweep.SeaHaze:IsA("Beam"), "灯塔的两层光束随转轴扫动")

print("⑤ 开枪：攻方打死守方，守方等几秒复活")
local pa = V3(150, G.Map.ground(150, 700) + 3.5, 700)
local pd = V3(150, G.Map.ground(150, 670) + 3.5, 670)
a1.Character:PivotTo(R.CFrame.lookAt(pa, pd))
d1.Character:PivotTo(CF(pd.X, pd.Y, pd.Z))
R.run(0.2)
local hum = d1.Character.Humanoid
local hp0 = hum.Health
local tool = a1.Character:FindFirstChildOfClass("Tool") or a1.Backpack:FindFirstChild("m4")
if tool and tool.Parent ~= a1.Character then tool.Parent = a1.Character end
local wid = tool and tool:GetAttribute("Weapon") or "m4"
check(wid == "m4", "手里是 M4：" .. tostring(wid))
local shots = 0
for _ = 1, 60 do
  if hum.Health <= 0 then break end
  T.remoteAs(a1, "Shoot", wid, d1.Character.HumanoidRootPart.Position)
  shots = shots + 1
  R.run(0.15)
end
check(hum.Health < hp0, string.format("打中了（%d 发，血 %.0f → %.0f）", shots, hp0, hum.Health))
R.run(0.5)
check(not PD.alive, "守方阵亡")
check(PA.kills == 1, "攻方记一次击杀（" .. PA.kills .. "）")
check(PD.deaths == 1, "守方记一次阵亡")
T.actAsRemote(d1, "deploy", "engineer", "camp")
R.run(0.5)
check(not PD.alive, "复活要等 " .. G.Config.RespawnDelay .. " 秒")
R.run(G.Config.RespawnDelay + 0.5)
T.actAsRemote(d1, "deploy", "rifle", "camp")
R.run(1)
check(PD.alive, "等够了能复活")

print("⑥ 抢滩：登陆艇把人送上前哨岛的滩")
local a2 = atk[2]
local P2 = G.P[a2]
check(P2.alive, "攻方 " .. a2.Name .. " 还在艇上 / 已经上岸")
local landed = T.runUntil(function()
  local hrp = a2.Character and a2.Character:FindFirstChild("HumanoidRootPart")
  return hrp and not hrp.Anchored and G.Map.isLand(hrp.Position.X, hrp.Position.Z)
end, 40)
check(landed, "靠滩后人下艇站到了岸上")

print("⑥½ 第一波以后：不能再坐艇，攻方在 A 前面 200～300 格的攻击出发阵地出生")
T.runUntil(function() return not G.firstWave() end, G.Config.FirstWave + 5)
local beachLeft, stA = false, nil
for _, s in ipairs(G.spawnList("atk", G.P[atk[1]])) do
  if s.kind == "beach" then beachLeft = true end
  if s.id == "stage.A" then stA = s end
end
local Ap = G.points.A
local dA = stA and ((stA.x - Ap.x) ^ 2 + (stA.z - Ap.z) ^ 2) ^ 0.5 or -1
check(not beachLeft and stA ~= nil and dA >= 195 and dA <= 305, string.format("开战 %d 秒后海滩关了，A 的出发阵地离 A %.0f 格", G.Config.FirstWave, dA))

print("⑦ 占领据点 A：攻方 3 人在圈里、没人守")
local A = G.points.A
for _, pl in ipairs(atk) do
  if not G.P[pl].alive then
    T.actAsRemote(pl, "deploy", "rifle", "fleet")
    R.run(1.5)
  end
end
for i, pl in ipairs(atk) do
  if pl.Character then
    pl.Character:PivotTo(CF(A.x + i * 4, A.y + 3.5, A.z))
    pl.Character.HumanoidRootPart.Anchored = true   -- 模拟器没有物理：钉住，免得别的逻辑挪走
  end
end
for _, pl in ipairs(def) do
  local P = G.P[pl]
  if P.alive and pl.Character then pl.Character:PivotTo(CF(0, 100, -2000)) end
end
-- 开局时生成的守方机器人还守在 A 的圈里（地图放大后来不及走开）：清掉，「没人守」
for _, e in pairs(G.entById) do
  if e.alive and e.kind == "bot" and e.team == "def" then
    local p = e.root.CFrame.Position
    if (p.X - A.x) ^ 2 + (p.Z - A.z) ^ 2 < 300 * 300 then G.damageEnt(e, 1e6, nil) end
  end
end
local tk0 = G.round.tickets
R.run(2)
check(A.prog > 0, string.format("占领进度在涨（%.2f）", A.prog))
local nearby = pls[1].PlayerGui.Main.ObjectiveStatus
check(nearby.Visible == (C.S.team == "atk"), "据点状态只在占领区内显示")
if C.S.team == "atk" then
  check(nearby.Status.Text == C.T("operation.capturing"), "占领区内显示服务器的推进状态")
end
local capOk = T.runUntil(function() return A.owner == "atk" end, G.Config.Capture.fast + 10)
check(capOk, "15 秒左右拿下 A（攻方多 3 人）")
check(A.locked, "拿下后锁定")
local st2 = G.Config.Stages[2]
check(G.round.stage == 2 and math.abs((G.round.endsAt - R.clock()) - st2.time) < 3, "拿下 A 进入第二阶段（港口），重新计时 " .. st2.time .. " 秒")
check((G.round.tickets or 0) >= tk0 + G.Config.Tickets.perStage - 5, string.format("攻方兵力补了（%d → %d）", tk0 or -1, G.round.tickets or -1))
check(G.pointActive("C") and not G.pointActive("D") and not G.pointActive("B") and not G.pointActive("E"), "第二阶段只开港口 C（同一时间一个交战区；D、E 还没开，灯塔岛 B 不开放）")
-- 交战区外不能出生：攻方没有海滩（第一波以后不坐艇）、不能在拿下的 A 出生；守方只能在 C 和它后面的集结点（还有营地、机场这种开载具的地方）
local ids = {}
local stg, recK = {}, nil
for _, s in ipairs(G.spawnList("atk", G.P[atk[1]])) do
  ids[s.id] = s.ok
  if s.kind == "staging" then stg[s.point] = s end
  if s.rec then recK = s.kind end
end
local beachAny = false
for id in pairs(ids) do if id:sub(1, 6) == "beach." then beachAny = true end end
check(not beachAny and ids["point.A"] == nil, "攻方：第二阶段没有登陆艇、不能在 A 出生")
local Cp = G.points.C
local function dist(s, p) return ((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2) ^ 0.5 end
check(stg.C ~= nil and stg.C.ok and stg.D == nil, "攻方：港口 C 前面有攻击出发阵地（D 的没有）")
check(stg.C ~= nil and dist(stg.C, Cp) >= 195 and dist(stg.C, Cp) <= 305, string.format("出发阵地离 C %.0f 格（200～300）", stg.C and dist(stg.C, Cp) or -1))
check(recK == "staging", "推荐的出生点是攻击出发阵地（" .. tostring(recK) .. "）")
local dids, rallyC = {}, nil
for _, s in ipairs(G.spawnList("def", G.P[def[1]])) do
  dids[s.id] = true
  if s.id == "rally.C" then rallyC = s end
end
check(dids["point.C"] and rallyC ~= nil and not dids["point.D"] and not dids["point.E"] and not dids["point.B"] and not dids["rally.D"], "守方：只能在 C 和 C 的集结点出生（D、E、B 不行）")
check(rallyC ~= nil and dist(rallyC, Cp) >= 145 and dist(rallyC, Cp) <= 255, string.format("集结点在 C 后面 %.0f 格（150～250）", rallyC and dist(rallyC, Cp) or -1))
check(dids["camp"] and dids["afield"], "守方的营地、机场（开载具、飞机）照旧能去")
-- 重新部署（H）：不算阵亡、不扣兵力，回部署界面；接着在 C 的出发阵地出生
local Pr = G.P[atk[2]]
Pr.dmgLog = {}
local d0, tk1 = Pr.deaths, G.round.tickets
T.actAsRemote(atk[2], "redeploy")
R.run(0.5)
check(not Pr.alive and Pr.deaths == d0 and G.round.tickets == tk1, string.format("按 H 重新部署：回部署界面，不算阵亡（%d → %d）、不扣兵力（%d → %d）", d0, Pr.deaths, tk1, G.round.tickets))
T.actAsRemote(atk[2], "deploy", "rifle", "stage.C")
R.run(1.5)
local hrpR = atk[2].Character and atk[2].Character:FindFirstChild("HumanoidRootPart")
check(Pr.alive and hrpR ~= nil and stg.C ~= nil and ((hrpR.Position.X - stg.C.x) ^ 2 + (hrpR.Position.Z - stg.C.z) ^ 2) ^ 0.5 < 40, "在 C 的攻击出发阵地出生")
R.run(1)
check(C.S.points[1].owner == "atk", "客户端顶栏上 A 变成攻方")
check(brief.Visible and brief.Title.Text == C.T("stage." .. G.Config.Stages[2].id) and not nearby.Visible, "进入第二阶段显示简报并收起旧据点（" .. brief.Title.Text .. "）")
R.run(5)
check(not brief.Visible, "同一阶段持续收战况时简报不会重复显示")

print("⑧ 时间到守方赢 → 结算 → 下一局")
G.round.endsAt = R.clock() + 1
for _, pl in ipairs(atk) do
  if pl.Character then pl.Character.HumanoidRootPart.Anchored = false pl.Character:PivotTo(CF(0, 100, 2100)) end
end
local over = T.runUntil(function() return G.round.phase == "end" end, 10)
check(over and G.round.winner == "def", "时间到、守方手里还有据点 → 守方赢（" .. tostring(G.round.winner) .. "）")
R.run(1)
local mine = (G.P[pls[1]].team == "def") and "ui.youWon" or "ui.youLost"
local res = #T.texts("^" .. C.T(mine) .. "$") > 0
check(res, "P1（" .. G.P[pls[1]].team .. "）看到结算：" .. C.T(mine))
local nxt = T.runUntil(function() return G.round.phase == "prep" and G.round.n == 2 end, G.Config.Round.results + 5)
check(nxt, "结算后开下一局")
nA, nD = G.teamCount("atk", true), G.teamCount("def", true)
check(nA == 3 and nD == 3, "重新分队 3 : 3")
check(G.points.A.owner == "def" and not G.points.A.locked, "据点重置")
R.run(1)
check(not G.P[pls[1]].alive and pls[1].PlayerGui.Main.Deploy.Visible, string.format("新一局回到部署界面（alive=%s 客户端 alive=%s phase=%s）", tostring(G.P[pls[1]].alive), tostring(C.S.alive), tostring(C.S.phase)))

print("⑨ 有人退出")
R.removePlayer(pls[6])
R.run(1)
check(G.P[pls[6]] == nil, "退出的人清掉了")
T.summary()
