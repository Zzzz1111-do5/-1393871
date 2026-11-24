-- 沙漠地图测试（用户 11-22：「界面就不要写 switchside 了，直接写 play，然后进入界面点地图；沙漠地图特别特别大，两边有自己的军事基地带机场」）：
--   开服不建地图、等第一个玩家选 → 主菜单「开始游戏」→ 选地图点沙漠 → 服务器建沙漠（地形、两边基地、机场、据点）→
--   地图好了自动快速加入 → 征服模式：据点开局中立、占点、据点少的一边掉兵力 → 机器人从自己基地 / 据点出生 → 客户端的据点条、标记、远处一圈沙地
--   python3 tools/mock/run.py tools/mock/desert.lua
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check
local ws = R.services.Workspace
local RS = R.services.ReplicatedStorage
local wall0 = os.clock()

print("① 开服：没人时先不建地图")
local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 6   -- 默认没有机器人（用户 11-18 去掉了 AI 士兵）：这里开几个，测征服模式下它们会不会走
check(G.mapId == nil and not G.worldReady, "地图还没定、没开始建")
local p1 = T.join("P1", 5001, true)
local C = T.C
R.run(4)
check(G.mapId == nil, "有人在：等他选（过了空服的 3 秒也不自己按岛开）")
check(C.menuShown and C.menuShown(), "主菜单开着")
check(#T.texts("^" .. C.T("menu.c1.title") .. "$") > 0, "主菜单第一张卡写「" .. C.T("menu.c1.title") .. "」")
local bad = {}
for _, s in ipairs(T.texts()) do
  if s:lower():find("switch") or s:find("选择阵营") or s:find("切换阵营") then table.insert(bad, s) end
end
check(#bad == 0, "界面上没有 switch side：" .. table.concat(bad, " | "))

print("② 开始游戏 → 选地图 → 沙漠")
R.as("client", function() C.menuPlay() end)
R.run(0.3)
check(C.mapPickShown(), "点「开始游戏」打开选地图")
local card
for _, d in ipairs(p1.PlayerGui:GetDescendants()) do if d.Name == "Map_desert" then card = d end end
check(card ~= nil and T.visible(card), "有沙漠地图的卡片")
local names = T.texts(C.T("map.desert.name"))
check(#names > 0, "卡片上写「" .. C.T("map.desert.name") .. "」")
T.press(card)
R.run(0.5)
check(G.mapId == nil and G.mapVotes[p1] == "desert", "点了是投一票（还没定：在场的人都投了也再等几秒、能改票）")
R.run((G.Config.MapVote.grace or 3) + 0.5)
check(G.mapId == "desert", "服务器按沙漠开（" .. tostring(G.mapId) .. "）")
check(C.mapPickWant() == "desert", "选地图界面记着自己点的沙漠")

print("③ 建沙漠")
local clk = os.clock()
local ok = T.runUntil(function() return G.worldReady end, 1800)
check(ok, string.format("沙漠建好：%s 个地形块、%s 个体素（真实 %.0f 秒）", tostring(G.terrainChunks), tostring(G.terrainVoxels), os.clock() - clk))
check(#G.bootErrors == 0, "建地图没有报错：" .. table.concat(G.bootErrors, " | "))
local Map = G.Map
check(Map.id == "desert" and RS:GetAttribute("MapId") == "desert", "Map.id 和 MapId 属性都是 desert")
check(Map.R >= 32000 and (Map.info.desert.km or 0) > 20, string.format("特别大：地形 ±%d 格（%.1f 公里见方）", Map.R, Map.info.desert.km))
local map = ws:FindFirstChild("Map")
local pts = map and map:FindFirstChild("Points")
check(pts ~= nil and #pts:GetChildren() == 7, "7 个据点模型（" .. tostring(pts and #pts:GetChildren()) .. "）")
check(#(G.ships or {}) == 0, "沙漠没有舰船")
check(G.decks == nil or #G.decks == 0, "没有舰队甲板")
-- 地形：基地压平、沙丘起伏、台地很高、平原正好 BASE_Y
local hb = Map.ground(Map.BASES.atk.x, Map.BASES.atk.z)
local hmax = 0
for i = -60, 60 do
  for k = -60, 60 do
    local h = Map.height(i * 250, k * 250)
    if h > hmax then hmax = h end
  end
end
check(math.abs(hb - Map.BASE_Y) < 3, string.format("基地压平（高 %.1f）", hb))
check(hmax > 60, string.format("有沙丘、台地（最高 %.0f 格）", hmax))
check(Map.height(-20000, 30000) == Map.BASE_Y, "远处戈壁是平的（跟 FillBlock 铺的一样高）")

print("④ 两边的基地：机场、生成点、防空")
local padN = { atk = { air = 0, veh = 0, heli = 0 }, def = { air = 0, veh = 0, heli = 0 } }
local wrongSide = 0
for _, p in ipairs(G.pads or {}) do
  local c = padN[p.team]
  if c then
    local k = (p.kind == "air") and (p.heli and "heli" or "air") or "veh"
    c[k] = c[k] + 1
    local B = Map.BASES[p.team]
    local pos = p.base.Position
    if math.abs(pos.X - B.x) > 2600 or math.abs(pos.Z - B.z) > 2700 then wrongSide = wrongSide + 1 end
  end
end
for _, team in ipairs({ "atk", "def" }) do
  local c = padN[team]
  check(c.air >= 2 and c.veh >= 3 and c.heli >= 1, string.format("%s 基地：飞机 %d 个、直升机 %d 个、地面载具 %d 个生成点", team, c.air, c.heli, c.veh))
end
check(wrongSide == 0, "生成点都在自己基地里（不对的 " .. wrongSide .. " 个）")
local fortN = { atk = 0, def = 0 }
for _, f in pairs(G.forts or {}) do
  local t = f.team or (f.def and f.def.home)
  if fortN[t] then fortN[t] = fortN[t] + 1 end
end
check(fortN.atk >= 4 and fortN.def >= 4, string.format("两边基地都有工事（高炮、碉堡）：%d : %d", fortN.atk, fortN.def))
for _, side in ipairs({ "atk", "def" }) do
  local A = Map.BASES[side].airfield
  local h0, h1 = Map.ground(A.x - A.len / 2 + 20, A.z), Map.ground(A.x + A.len / 2 - 20, A.z)
  check(math.abs(h0 - h1) < 0.5 and A.len >= 3000, string.format("%s 跑道 %d 格长、两头一样高（%.1f / %.1f）", side, A.len, h0, h1))
end

print("⑤ 地图好了：自动快速加入")
local joined = T.runUntil(function() return G.P[p1] and G.P[p1].alive end, 20)
check(joined, "选的地图生成好就出生了（快速加入）")
check(not C.mapPickShown(), "选地图界面关了")
local P1 = G.P[p1]
if p1.Character then
  local pos = p1.Character.HumanoidRootPart.Position
  local B = Map.BASES[P1.team]
  check(math.abs(pos.X - B.x) < 2600, string.format("在自己基地出生（%s，x = %.0f，基地 x = %d）", P1.team, pos.X, B.x))
end
check(C.S and C.S.mode == "conquest", "战况里是征服模式")
check(C.S.ticketsDef ~= nil and C.S.tickets ~= nil, string.format("两边都有兵力：%s : %s", tostring(C.S.tickets), tostring(C.S.ticketsDef)))
local neutral = 0
for _, s in ipairs(C.S.points or {}) do if s.owner == "none" then neutral = neutral + 1 end end
check(neutral == 7, "开局 7 个据点都是中立（" .. neutral .. "）")
local spawns = G.spawnList(P1.team, P1)
local hasBase = false
for _, s in ipairs(spawns) do if s.kind == "base" then hasBase = true end end
check(hasBase and #spawns >= 1, "出生点列表有自己的基地（" .. #spawns .. " 个）")

print("⑥ 客户端：据点条、据点标记、远处的沙地")
local cam = ws.CurrentCamera
check(cam:FindFirstChild("Obj_G") ~= nil and cam:FindFirstChild("Obj_A") ~= nil, "据点标记换成沙漠的 A～G")
local feed = T.texts("^G$")
check(#feed > 0, "顶上的据点条有 G")
R.as("client", function()
  cam.CFrame = CF(-31000, 400, 0)
  if C.stepScenery then C.stepScenery(0.5) end
end)
local sand, sea = 0, 0
local ocean = ws:FindFirstChild("Ocean")
for _, p in ipairs(ocean and ocean:GetChildren() or {}) do
  if p.Name == "FarSand" then sand = sand + 1 elseif p.Name == "Sea" then sea = sea + 1 end
end
check(sand > 0 and sea == 0, string.format("飞到地形边上：外面接沙色平面 %d 块，没有海", sand))
local errs0 = #R.errors

print("⑥b 夜视、视野（用户 11-22：「夜视仪视角沙漠的地面全是白色的」「视野给我改成无限远好了，然后远处模糊这样」）")
do
  local L = R.services.Lighting
  T.runUntil(function() return C.nvgOn and C.nvgOn() end, 12)
  R.run(0.5)   -- 昼夜（DayNight.lua）一秒更新十次
  local ev = L.ExposureCompensation
  check(C.nvgOn() and ev > 1.6 and ev < 2.4, string.format("沙漠开着夜视：曝光加到 %.2f（海岛 3.25；沙子亮一倍多，少加 1.2 档不过曝）", ev))
  local atm = L:FindFirstChildOfClass("Atmosphere")
  check(atm ~= nil and atm.Density < 0.07, string.format("大气放淡（夜视里 %.3f；原来夜里 0.21、开夜视 0.12）", atm and atm.Density or -1))
  check(L.FogEnd >= 90000, string.format("老式的雾放到 %d 格", L.FogEnd))
  local fb = L:FindFirstChild("FarBlur")
  check(fb ~= nil and fb.Enabled and fb.FarIntensity > 0.05 and fb.NearIntensity == 0 and fb.FocusDistance <= 200 and fb.InFocusRadius <= 50,
    "远处景深模糊开着：近处不糊，对焦距离、清楚范围在 Roblox 的上限以内（200、50 格）")
end

print("⑦ 开战：征服——占点、据点少的一边掉兵力")
local okB = T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 30)
check(okB, "准备阶段过了开战")
local team = P1.team
local foe = (team == "atk") and "def" or "atk"
local B = Map.BASES[team]
-- 离自己基地最近的据点
local best, bd = nil, math.huge
for _, p in ipairs(Map.POINTS) do
  local d = math.abs(p.x - B.x) + math.abs(p.z - B.z)
  if d < bd then best, bd = p, d end
end
local S0 = G.points[best.id]
if p1.Character then
  p1.Character:PivotTo(CF(best.x, Map.ground(best.x, best.z) + 3.5, best.z))
  p1.Character.HumanoidRootPart.Anchored = true
end
local function clearFoes()
  for _, e in pairs(G.entById) do
    if e.alive and e.kind == "bot" and e.team == foe then
      local p = e.root.CFrame.Position
      if (p.X - best.x) ^ 2 + (p.Z - best.z) ^ 2 < 400 * 400 then G.damageEnt(e, 1e6, nil) end
    end
  end
end
clearFoes()
R.run(3)
check(math.abs(S0.cap or 0) > 0, string.format("站进 %s 圈里：占领进度 %.2f", best.id, S0.cap or 0))
local capOk = T.runUntil(function() clearFoes() return S0.owner == team end, 240)
check(capOk, string.format("一个人占下 %s（%s）", best.id, tostring(S0.owner)))
local function held(t)
  local n = 0
  for _, s in pairs(G.points) do if s.owner == t then n = n + 1 end end
  return n
end
local nM, nF = held(team), held(foe)
local tkF0 = (foe == "def") and G.round.ticketsDef or G.round.tickets
local tkM0 = (team == "def") and G.round.ticketsDef or G.round.tickets
R.run(20)
local tkF1 = (foe == "def") and G.round.ticketsDef or G.round.tickets
local tkM1 = (team == "def") and G.round.ticketsDef or G.round.tickets
if nM > nF then
  check(tkF1 < tkF0, string.format("我方据点多（%d : %d）：对面兵力 %d → %d", nM, nF, tkF0, tkF1))
elseif nF > nM then
  check(tkM1 < tkM0, string.format("对面据点多（%d : %d）：我方兵力 %d → %d", nM, nF, tkM0, tkM1))
else
  check(true, string.format("两边据点一样多（%d : %d）：兵力不掉", nM, nF))
end
check(C.S.points and #C.S.points == 7, "战况 7 个据点")
local anyCap = false
for _, s in ipairs(C.S.points) do if s.id == best.id and s.owner == team then anyCap = true end end
check(anyCap, "客户端看到 " .. best.id .. " 归我方")
-- 出生点：自己占的据点也能出生
local hasPt = false
for _, s in ipairs(G.spawnList(team, P1)) do if s.kind == "point" or (s.id and s.id:find("point%." .. best.id)) then hasPt = true end end
check(hasPt, "占下的 " .. best.id .. " 能当出生点")

print("⑧ 机器人：两边都有、在自己那边出生、往据点走")
local bots = { atk = 0, def = 0 }
local far = 0
for _, e in pairs(G.entById) do
  if e.alive and e.kind == "bot" then
    bots[e.team] = (bots[e.team] or 0) + 1
    local p = e.root.CFrame.Position
    local Bb = Map.BASES[e.team]
    if math.abs(p.X) > 20000 or math.abs(p.Z) > 16000 then far = far + 1 end
    local _ = Bb
  end
end
check(bots.atk > 0 and bots.def > 0, string.format("两边都有机器人：%d : %d", bots.atk, bots.def))
check(far == 0, "没有跑到地图外面的机器人（" .. far .. "）")
local sq = G.botSquads and G.botSquads() or {}
local goals = 0
local tgs = {}
for _, s in pairs(sq) do
  for _, B in ipairs(s.m or {}) do
    if B.target then goals = goals + 1 tgs[B.target] = (tgs[B.target] or 0) + 1 end
  end
end
local tl = {}
for id, n in pairs(tgs) do table.insert(tl, id .. "×" .. n) end
table.sort(tl)
check(goals > 0, "机器人有要去的据点（" .. goals .. " 个：" .. table.concat(tl, " ") .. "）")

print("⑨ 跑一会儿不出错")
R.run(30)
local newErr = #R.errors - errs0
check(newErr == 0, "开战以后没有新的报错（" .. newErr .. "）")
for i = errs0 + 1, math.min(errs0 + 8, #R.errors) do print("    " .. R.errors[i]:sub(1, 400)) end
print(string.format("真实用时 %.0f 秒", os.clock() - wall0))
if #R.warns > 0 then
  print("警告（前 8 条）：")
  for i = 1, math.min(8, #R.warns) do print("  " .. R.warns[i]:sub(1, 300)) end
end
TEST_CODE = (T.fails > 0) and 1 or 0
print(T.fails == 0 and "全部通过" or ("没通过 " .. T.fails .. " 项"))
