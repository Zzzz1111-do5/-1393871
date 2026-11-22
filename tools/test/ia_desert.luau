--!nocheck
-- 沙漠图「沙海」（MapDesert.lua）测试：开服写地形、没有海上那一套、出生点、生成点、工事、建筑、玩家部署、开战后攻击出发阵地、机器人
-- 用法（仓库根目录）：lune run tools/test/ia_desert.luau <rbxlx> [v]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")
H.quietWarn = process.args[2] ~= "v"
local clock0 = os.clock()
H.boot(process.args[1], { ds = "mock", before = function(game) game:GetService("Workspace"):SetAttribute("MapName", "desert") end })

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
local function count(root, pred)
	local n = 0
	if root then for _, d in ipairs(root:GetDescendants()) do if pred(d) then n += 1 end end end
	return n
end

print("① 开服：沙漠地形")
H.run(0.5)
local G = H.Gs.server
check(G ~= nil and G.Map and G.Map.DESERT == true, "选了沙漠图（Map.NAME = " .. tostring(G and G.Map and G.Map.NAME) .. "）")
G.Config.Bots.minPerTeam = 0
G.aiVehOff = true
local ok = H.runUntil(function() return G.worldReady end, 1800)
check(ok, string.format("地图生成完（模拟 %.0f 秒，实际 %.1f 秒）：起伏块 %s，体素 %s，后台还剩 %s 块", H.now, os.clock() - clock0,
	tostring(G.terrainChunks), tostring(G.terrainVoxels), tostring(G.terrainRest)))
check(#G.bootErrors == 0, "开服没有报错：" .. table.concat(G.bootErrors, " | "))
local M = G.Map
check(G.Config.Map == "desert" and G.Config.Stages[1].id == "border" and #G.Config.Stages == 5, "沙漠版的五个阶段（边境 → 油田 → 镇子 → 空军基地 → 指挥部）")
local mapF = H.workspace:FindFirstChild("Map")
local scen = mapF and mapF:FindFirstChild("Scenery")
check(scen and scen:FindFirstChild("Harbor", true) == nil and scen:FindFirstChild("Lighthouse", true) == nil, "没有港口、灯塔")
check(#(G.decks or {}) == 0 and #(G.ships or {}) == 0, "没有舰队甲板、舰艇")
local water = 0
for _, op in ipairs(H.terrainOps) do if op.m == "Water" then water += 1 end end
check(water == 0, "地形里没灌一滴水（" .. water .. " 处）")
local des = scen and scen:FindFirstChild("Desert")
local town = des and des:FindFirstChild("Town")
local nAdobe = count(town, function(d) return d:IsA("Model") and d.Name == "Adobe" end)
check(nAdobe >= 60, "镇子土坯房 " .. nAdobe .. " 座")
check(town and town:FindFirstChild("Mosque") ~= nil, "镇子里有清真寺")
local oil = des and des:FindFirstChild("Oilfield")
local nPump = count(oil, function(d) return d:IsA("Model") and d.Name == "Pumpjack" end)
local nRock = count(oil, function(d) return d:IsA("BasePart") and d:GetAttribute("Anim") == "rock" end)
check(nPump >= 15 and nRock == nPump * 2, "油田抽油机 " .. nPump .. " 台（游梁、驴头带点头动画 " .. nRock .. " 件）")
check(count(oil, function(d) return d:IsA("Fire") end) >= 3, "几口井在烧")
check(des and des:FindFirstChild("HighwayOfDeath") and #des.HighwayOfDeath:GetChildren() > 80, "死亡公路上一路残骸（" .. tostring(des and des:FindFirstChild("HighwayOfDeath") and #des.HighwayOfDeath:GetChildren()) .. " 个零件）")
check(des and des:FindFirstChild("RedBase") ~= nil and des:FindFirstChild("Shelters") ~= nil, "红方前进基地、加固机库")
-- 建筑别压在路上、别压在据点圈里
local onRoad, inPoint = 0, 0
for _, m in ipairs(town and town:GetChildren() or {}) do
	if m:IsA("Model") and m.Name == "Adobe" then
		local p = m:GetPivot().Position
		if M.roadDist(p.X, p.Z) < 14 then onRoad += 1 end
		if (p.X - M.TOWN.x) ^ 2 + (p.Z - M.TOWN.z) ^ 2 < (M.POINT_R + 20) ^ 2 then inPoint += 1 end
	end
end
check(onRoad == 0 and inPoint == 0, "土坯房不压路（" .. onRoad .. "）、不在据点圈里（" .. inPoint .. "）")

print("② 工事、障碍")
local forts = 0
for _, e in ipairs(G.ents or {}) do if e.fort then forts += 1 end end
check(forts >= 15, "工事 " .. forts .. " 处（碉堡、高炮、M777）")
local kinds = {}
for _, e in ipairs(G.ents or {}) do if e.fort then kinds[e.fkind] = (kinds[e.fkind] or 0) + 1 end end
check((kinds.coastal or 0) == 0 and (kinds.howitzer or 0) == 6 and (kinds.bunker or 0) >= 10, string.format("没有岸防炮；碉堡 %d、高炮 %d、榴弹炮 %d", kinds.bunker or 0, kinds.aaa or 0, kinds.howitzer or 0))
-- 碉堡、榴弹炮的朝向：都朝南（攻方来的方向）
local north = 0
for _, e in ipairs(G.ents or {}) do
	if e.fort and e.base and (e.fkind == "howitzer") and e.base.LookVector.Z < 0.5 then north += 1 end
end
check(north == 0, "榴弹炮都朝南")

print("③ 生成点")
local atkVeh, atkHeli, atkJet, carrierJet = 0, 0, 0, false
for _, p in ipairs(G.pads or {}) do
	if p.team == "atk" then
		local pos = p.base.Position
		if p.kind == "veh" then
			atkVeh += 1
			check(not p.sea and (pos - roblox.Vector3.new(M.REDBASE.x, pos.Y, M.REDBASE.z)).Magnitude < 400, string.format("攻方车位在前进基地（%.0f, %.0f）", pos.X, pos.Z))
		elseif p.kind == "air" and p.heli then atkHeli += 1
		elseif p.kind == "air" then
			atkJet += 1
			for _, id in ipairs(p.vids or {}) do if id == "j15t" then carrierJet = true end end
		end
	end
end
check(atkVeh >= 4 and atkHeli >= 1 and atkJet >= 4, string.format("攻方：车位 %d、直升机坪 %d、固定翼召唤位 %d", atkVeh, atkHeli, atkJet))
check(carrierJet, "没有航母：歼-15T 也能在前进机场召唤")

print("④ 玩家：部署、开战")
local pls = {}
for i = 1, 4 do pls[i] = H.addPlayer("P" .. i, 4000 + i) end
H.run(2)
for _, pl in ipairs(pls) do act(pl, "pickTeam", G.P[pl].team) end
H.run(0.5)
local atk, def = {}, {}
for _, pl in ipairs(pls) do table.insert((G.P[pl].team == "atk") and atk or def, pl) end
local a1, d1 = atk[1], def[1]
local list = G.spawnList("atk", G.P[a1])
local ids = {}
for _, s in ipairs(list) do ids[s.id] = s end
check(ids.redbase ~= nil and ids.af2 ~= nil and ids.fleet == nil and ids.cv == nil and ids.barge == nil, "攻方出生点：前进基地、前进机场，没有舰队、航母、登陆平台")
local beach = false
for id in pairs(ids) do if string.sub(id, 1, 6) == "beach." then beach = true end end
check(not beach, "没有登陆艇的海滩出生点")
act(a1, "deploy", "rifle", "redbase")
act(d1, "deploy", "rifle", "camp")
H.run(2)
local pa = a1.Character and a1.Character:FindFirstChild("HumanoidRootPart")
check(pa ~= nil and math.abs(pa.Position.Z - M.REDBASE.z) < 400, string.format("攻方在前进基地出生（z = %.0f）", pa and pa.Position.Z or 0))
local pd = d1.Character and d1.Character:FindFirstChild("HumanoidRootPart")
check(pd ~= nil and pd.Position.Z < -12000, string.format("守方在岭北营地出生（z = %.0f）", pd and pd.Position.Z or 0))
local okB = H.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB and G.round.stage == 1 and G.pointActive("A") and not G.pointActive("B"), "开战：第一阶段只能占边境哨所 A")
local st = nil
for _, s in ipairs(G.spawnList("atk", G.P[atk[2] or a1])) do if s.id == "stage.A" then st = s end end
check(st ~= nil and st.ok, "一开战就能在 A 的攻击出发阵地出生（没有第一波登陆艇）")
if st then
	check(st.z > 7050, string.format("出发阵地在 A 南边（z = %.0f）", st.z))
end
local CA = H.Gs[a1.Name]
check(CA and CA.T("point.A") == "A 边境哨所" or (CA and CA.T("point.A") == "A Border Post"), "据点名换成沙漠的说法：" .. tostring(CA and CA.T("point.A")))

print("⑤ 机器人")
G.Config.Bots.minPerTeam = 6
G.aiVehOff = false
H.run(40)
local nb = { atk = 0, def = 0 }
for _, e in ipairs(G.ents or {}) do
	if e.alive and e.bot and e.team then nb[e.team] = (nb[e.team] or 0) + 1 end
end
local ba, bd = G.botCount("atk"), G.botCount("def")
check(ba > 0 and bd > 0, string.format("两边都有机器人（攻 %d、守 %d；场上活着的 %d / %d）", ba, bd, nb.atk, nb.def))
check(#H.errors == 0, "全程没有脚本错误（" .. #H.errors .. "）")
for i, e in ipairs(H.errors) do if i <= 5 then print("    " .. e.msg) end end
print(string.format("%s：%d 处不对（实际 %.0f 秒）", fails == 0 and "全部通过" or "有问题", fails, os.clock() - clock0))
process.exit(fails == 0 and 0 or 1)
