-- 沙漠图「沙海」（MapSands.lua，地图 id sands）合并后的测试：两个会话各做了一张沙漠图，用户 11-22 说两张都留——
--   沙海改成走 Map.use 选图（原来开服按 Config.Map 整个换模块）：选地图界面有三张卡 → 点沙海 → 服务器按沙海建（地形、没有海上那一套）→
--   阶段表换成沙海的五个阶段（Config.useMap）→ 客户端的据点名、阶段名用 @sands 的说法、远处那圈是沙地
--   python3 tools/mock/run.py tools/mock/sands.lua
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local RS = R.services.ReplicatedStorage
local CF = T.CF
local wall0 = os.clock()

print("① 开服、进人、开选地图")
local G = T.boot()
G.fortsHold = true
local p1 = T.join("P1", 5101, true)
local C = T.C
R.run(4)
check(G.mapId == nil, "有人在：等他选")
R.as("client", function() C.menuPlay() end)
R.run(0.3)
check(C.mapPickShown(), "点「开始游戏」打开选地图")
local cards = {}
for _, d in ipairs(p1.PlayerGui:GetDescendants()) do
  local id = d.Name:match("^Map_(%w+)$")
  if id then cards[id] = d end
end
check(cards.island and cards.desert and cards.sands, "三张地图的卡片都在（岛、沙漠风暴、沙海）")
check(#T.texts(C.T("map.sands.name")) > 0 and #T.texts(C.T("map.desert.name")) > 0, "卡片上写「" .. C.T("map.sands.name") .. "」「" .. C.T("map.desert.name") .. "」")

print("② 点沙海 → 服务器按沙海建")
T.press(cards.sands)
R.run((G.Config.MapVote.grace or 3) + 0.6)   -- 投票：在场的人都投了，再等几秒（还能改票）就开
check(G.mapId == "sands", "服务器按沙海开（" .. tostring(G.mapId) .. "）")
local t0 = os.clock()
T.runUntil(function() return G.worldReady end, 900)
print(string.format("  建图 %.0f 秒（墙钟）", os.clock() - t0))
check(G.worldReady, "地图建好了")
local Map = G.Map
check(Map.id == "sands" and Map.NAME == "sands" and Map.DESERT == true and Map.LANDONLY == true and not Map.desert, "Map 表换成沙海（DESERT、LANDONLY；不是沙漠风暴的 desert 标志）")
check(RS:GetAttribute("MapId") == "sands", "MapId 属性是 sands")
check(G.Config.Map == "sands" and #G.Config.Stages == 5 and G.Config.Stages[1].id == "border" and G.Config.Stages[5].id == "hq", "阶段表换成沙海的五个阶段（边境 → 油田 → 镇子 → 空军基地 → 指挥部）")
check((G.terrainChunks or 0) > 0, "写了地形（" .. tostring(G.terrainChunks) .. " 块）")
local nShips = 0
for _ in pairs(G.ships or {}) do nShips = nShips + 1 end
check(nShips == 0, "没有舰艇（" .. nShips .. "）")
local ids = {}
for _, p in ipairs(Map.POINTS or {}) do ids[#ids + 1] = p.id end
check(#ids == 5, "五个据点：" .. table.concat(ids, " "))

-- 地图是开服以后投票定的：服务器各模块初始化时 Map 还是岛，定了图以后要按沙海重算（原来没重算：A 的攻击出发阵地在岛的坐标上、寻路网格盖不住南边的红方基地）
T.runUntil(function() return G.mapTablesFor and G.mapTablesFor() == "sands" end, 60)
check(G.mapTablesFor and G.mapTablesFor() == "sands", "开局前按沙海重算了阶段、出发阵地、集结点")
check(G.STAGES and #G.STAGES == 5 and G.stageOf.E == 5, "服务器的阶段表是沙海的五个阶段（E 是第 5 阶段）")
local pA
for _, p in ipairs(Map.POINTS) do if p.id == "A" then pA = p end end
local sA = G.stagingOf and G.stagingOf("A")
local dA = (pA and sA) and math.sqrt((sA.x - pA.x) ^ 2 + (sA.z - pA.z) ^ 2) or 0
check(pA and sA and sA.z > pA.z and dA > 150 and dA < 350, string.format("A 的攻击出发阵地在 A 南边（攻方那一侧，离 A %.0f 格；碉堡射界外的侧边优先）：A (%.0f, %.0f)，出发阵地 (%.0f, %.0f)",
  dA, pA and pA.x or 0, pA and pA.z or 0, sA and sA.x or 0, sA and sA.z or 0))
T.runUntil(function() return G.navCell == Map.NAVCELL end, 60)
check(G.navCell == Map.NAVCELL, "寻路网格按沙海的范围、格子大小（" .. tostring(G.navCell) .. " 格一格）")

print("③ 客户端跟着换")
R.run(2)
check(C.Map.id == "sands", "客户端的 Map 也换成沙海")
check(C.Config.Map == "sands" and C.Config.Stages[1].id == "border", "客户端的阶段表也换了")
local route
for _, d in ipairs(p1.PlayerGui:GetDescendants()) do if d.Name == "Route" then route = d end end
local stopIds = {}
for _, c in ipairs(route and route:GetChildren() or {}) do if c.ClassName == "Frame" then stopIds[#stopIds + 1] = c.Name end end
check(#stopIds == 5 and route:FindFirstChild("hq") ~= nil, "战役路线条换成沙海的五个阶段（" .. table.concat(stopIds, " ") .. "；原来留着岛的）")
local a = C.T("point.A")
check(a ~= "point.A" and (a:find("边境") or a:find("Border")), "据点 A 叫「" .. a .. "」（@sands 的说法）")
local st = C.T("stage.border")
check(st ~= "stage.border", "阶段名「" .. st .. "」")
-- 远处那圈平面只铺在地形外面（地形里那几块沉到底下）：镜头挪到地形边上再数
local cam = R.workspace.CurrentCamera
local edge = (Map.SEA_R or Map.R) - 300
R.as("client", function()
  cam.CFrame = CF(edge, 400, 0)
  if C.stepScenery then C.stepScenery(0.5) end
end)
R.run(0.3)
local n = C.oceanTiles and C.oceanTiles() or 0
local sand, sea, y = 0, 0, nil
local ocean = R.workspace:FindFirstChild("Ocean")
for _, p in ipairs(ocean and ocean:GetChildren() or {}) do
  if p.Name == "FarSand" then
    sand = sand + 1
    if p.Position.Y > -1000 then y = p.Position.Y end
  elseif p.Name == "Sea" then sea = sea + 1 end
end
check(n > 0 and sand > 0 and sea == 0, string.format("镜头到地形边上（x = %d）：外面铺了 %d 块沙地平面，没有海（%d）", edge, n, sea))
check(y and math.abs(y - ((Map.PLAIN or 12) - 0.5)) < 0.01, "沙地平面顶和平原一样高（y = " .. tostring(y) .. "）")

print("④ 开战")
T.runUntil(function() return G.round and G.round.phase == "battle" end, 120)
check(G.round and G.round.phase == "battle", "进了战斗阶段")
R.run(5)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
print(string.format("用时 %.0f 秒", os.clock() - wall0))
T.summary()
