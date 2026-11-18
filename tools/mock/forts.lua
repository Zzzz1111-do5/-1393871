-- 工事测试（模拟器）：python3 tools/mock/run.py tools/mock/forts.lua [v]
--   地图自带的工事、障碍都摆好了 → AI 碉堡打走到射界里的攻方 → 踩雷、铁丝网减速、爆炸炸断铁丝网 →
--   守方玩家走到高炮旁按 E 接手、开火、F 离开；接手岸防炮开一炮 → 工事被打掉（记分、残骸）→ 据点被拿下后附近的工事归攻方 →
--   工兵的破障器材探雷、排雷 → 停车、出生避开工事
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.Config.Bots.minPerTeam = 0
G.navyNoAI = true   -- 不要 AI 舰艇：攻方 054A 一开战就炮击岸防炮（76 毫米每秒一发），等不到⑤接手就打掉了
G.aiVehOff = true   -- 也不要 AI 坦克（AIVeh.lua）：冲上前哨岛就打碉堡，等不到⑥看工事归攻方
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6001, true)
local foe = T.join("P2", 6002, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, "def")
setTeam(foe, "atk")
R.run(1)
local P, PF = G.P[me], G.P[foe]
local C = T.C
local Map = G.Map
local FD = R.requireModule and R.requireModule("FortDefs") or nil

print("① 地图自带的工事、障碍")
local kinds = {}
for _, e in ipairs(G.forts) do kinds[e.fkind] = (kinds[e.fkind] or 0) + 1 end
check(#G.forts >= 30, "工事 " .. #G.forts .. " 处：碉堡 " .. tostring(kinds.bunker) .. "、岸防炮 " .. tostring(kinds.coastal) .. "、高炮 " .. tostring(kinds.aaa) .. "、榴弹炮 " .. tostring(kinds.howitzer))
check((kinds.bunker or 0) >= 15 and (kinds.coastal or 0) == 4 and (kinds.aaa or 0) == 7 and (kinds.howitzer or 0) == 2, "四种都有")
local def = R.workspace.Map:FindFirstChild("Defenses")
local wireF = R.workspace.Map:FindFirstChild("Wire")
check(def ~= nil and #def:GetChildren() > 300, "钢刺猬、警示牌、沙袋：" .. (def and #def:GetChildren() or 0) .. " 个零件")
check(wireF ~= nil and #wireF:GetChildren() > 40, "铁丝网 " .. (wireF and #wireF:GetChildren() or 0) .. " 段")
local mines = G.fortsDebug.mines()
check(#mines >= 60, "地雷 " .. #mines .. " 颗")
-- 工事都在陆地上、不在水里，离据点、海滩合理
local wet = 0
for _, e in ipairs(G.forts) do
  local p = e.base.Position
  if Map.height(p.X, p.Z) < 1 then wet = wet + 1 end
end
check(wet == 0, "工事都在岸上（在水里的 " .. wet .. " 处）")
-- 客户端拼好了样子
local nv = 0
for _ in pairs(C.fortViews or {}) do nv = nv + 1 end
check(nv == #G.forts, "客户端画了 " .. nv .. " 处工事")

print("② 开战：AI 碉堡打走进射界的攻方")
T.runUntil(function() return G.round.phase == "battle" end, 40)
T.actAs(foe, "deploy", "rifle", "fleet")
R.run(1.5)
check(PF.alive and foe.Character ~= nil, "攻方出生")
-- 找一座海滩碉堡，把攻方放到它正前方 160 格的滩上
local bk
for _, e in ipairs(G.forts) do if e.fkind == "bunker" and e.tag == "white" then bk = e break end end
check(bk ~= nil, "白滩有碉堡")
local hum = foe.Character.Humanoid
if bk then
  local p = bk.base.Position + bk.base.LookVector * 160
  local y = Map.ground(p.X, p.Z) + 3.5
  foe.Character:PivotTo(CF(p.X, y, p.Z))
  local dead = T.runUntil(function() return hum.Health <= 0 or not PF.alive end, 25)
  check(dead or hum.Health < hum.MaxHealth, string.format("碉堡开火打中了（血 %.0f）", hum.Health))
  check(bk.model:GetAttribute("Ty") ~= nil, "碉堡转了机枪：方位 " .. tostring(bk.model:GetAttribute("Ty")) .. "°")
end

print("③ 雷区、铁丝网")
local function respawn(pl, role, spawn)
  R.run(G.Config.RespawnDelay + 0.5)
  T.actAs(pl, "deploy", role or "rifle", spawn or "fleet")
  R.run(1.5)
end
if not PF.alive then respawn(foe) end
G.fortsHold = true   -- 下面测别的：工事先不开火
local m1
for _, m in ipairs(mines) do if m.alive and not m.at then m1 = m break end end
check(m1 ~= nil, "有防步兵雷")
if m1 and foe.Character then
  foe.Character:PivotTo(CF(m1.x, Map.ground(m1.x, m1.z) + 3.5, m1.z))
  R.run(0.5)
  check(not m1.alive, "踩到雷就炸了")
  check(not PF.alive or foe.Character.Humanoid.Health < foe.Character.Humanoid.MaxHealth, "踩雷的人受伤 / 阵亡")
end
if not PF.alive then respawn(foe) end
local wires = G.fortsDebug.wires()
local w1 = wires[3]
if w1 and foe.Character then
  local mid = (w1.a + w1.b) / 2
  foe.Character:PivotTo(CF(mid.X, Map.ground(mid.X, mid.Z) + 3.5, mid.Z))
  R.run(0.6)
  local ws = foe.Character.Humanoid.WalkSpeed
  check(ws < G.Config.RoleById.rifle.speed * 0.5, string.format("铁丝网里走得慢（%.1f）", ws))
  foe.Character:PivotTo(CF(mid.X, Map.ground(mid.X, mid.Z - 40) + 3.5, mid.Z - 40))
  R.run(0.6)
  check(math.abs(foe.Character.Humanoid.WalkSpeed - G.Config.RoleById.rifle.speed) < 0.01, "出来就恢复")
  G.explode(V3(mid.X, Map.ground(mid.X, mid.Z) + 1, mid.Z), { dmg = 50, splash = 12, vs = {} }, { team = "atk" })
  R.run(0.2)
  check(not w1.alive and w1.model == nil, "一炸就断")
end
-- 爆炸引爆附近的雷（炮火准备开通路）
local m2
for _, m in ipairs(mines) do if m.alive then m2 = m break end end
if m2 then
  G.explode(V3(m2.x + 3, m2.y + 1, m2.z), { dmg = 50, splash = 12, vs = {} }, { team = "atk" })
  R.run(1)
  check(not m2.alive, "附近的爆炸把雷引爆了")
end

print("④ 守方玩家走到高炮旁按 E 接手")
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
check(P.alive and me.Character ~= nil, "守方在营地出生")
local aa
for _, e in ipairs(G.forts) do if e.fkind == "aaa" and e.tag == "camp" then aa = e end end
check(aa ~= nil, "营地有高炮")
if aa and me.Character then
  local mp = (aa.base * CF(FD and FD.MAN.aaa or V3(5.5, 1.5, 3))).Position
  me.Character:PivotTo(CF(mp.X, Map.ground(mp.X, mp.Z) + 3.5, mp.Z))
  R.run(0.6)
  local v = C.fortViews[aa.id]
  check(v ~= nil and v.prompt ~= nil and v.prompt.Enabled, "走过去出现「E 操作」提示")
  if v and v.prompt then R.as("client", function() v.prompt.Triggered:Fire(me) end) end
  R.run(1)
  check(P.vehicle == aa and aa.gunner == P, "接手了高炮")
  check(C.gunner ~= nil and C.gunner.id == aa.id, "客户端进入操作模式")
  check(me.Character.HumanoidRootPart.Anchored, "人锚定在炮位上")
  -- 鼠标往右：炮往右转（镜头朝向的方位角变大，北 0°、东 90°）
  local cam = R.services.Workspace.CurrentCamera
  local function brg() local l = cam.CFrame.LookVector return math.deg(math.atan2(l.X, -l.Z)) end
  local b0 = brg()
  for _ = 1, 10 do R.mouseDelta = R.Vector2.new(30, 0) R.run(1 / 30) end
  local db = (brg() - b0 + 540) % 360 - 180
  check(db > 5, string.format("鼠标往右，高炮往右转（方位 %+.0f°）", db))
  G.fortsHold = false
  local n0 = #G.shots
  T.mouse(true)
  R.run(1.2)
  local flak = 0
  for _, s in ipairs(G.shots) do if s.w and s.w.id == "flak35" then flak = flak + 1 end end
  T.mouse(false)
  R.run(0.3)
  check(flak > 0, "按住左键连发高炮弹（空中 " .. flak .. " 发）")
  check(aa.mag and aa.mag < 40, "弹匣在减少：" .. tostring(aa.mag))
  T.tap(Enum.KeyCode.F)
  R.run(1)
  check(P.vehicle == nil and aa.gunner == nil, "按 F 离开")
  check(not me.Character.HumanoidRootPart.Anchored and C.gunner == nil, "能走了、客户端退出操作")
end

print("⑤ 接手岸防炮开一炮")
local cg
for _, e in ipairs(G.forts) do if e.fkind == "coastal" and e.tag == "cape" then cg = e break end end
if cg and me.Character then
  local mp = (cg.base * CF(V3(0, 2, 11))).Position
  me.Character:PivotTo(CF(mp.X, Map.ground(mp.X, mp.Z) + 3.5, mp.Z))
  R.run(0.5)
  T.act("enterVeh", cg.id)
  R.run(1)
  check(P.vehicle == cg, "接手了岸防炮")
  check(C.gunner ~= nil and C.gunner.id == cg.id, "客户端进入操作模式")
  local fired = 0
  local launch0 = G.launch
  G.launch = function(s) if s.w and s.w.id == "naval127" then fired = fired + 1 end return launch0(s) end
  R.run(0.5)
  T.mouse(true)
  R.run(0.2)
  T.mouse(false)
  R.run(0.3)
  G.launch = launch0
  check(fired > 0, "打出去一发 127 毫米炮弹（fireAt " .. tostring(cg.fireAt and (cg.fireAt - R.clock())) .. "）")
  T.tap(Enum.KeyCode.F)
  R.run(1)
end

print("⑥ 工事被打掉、据点被拿下后归攻方")
local victim
for _, e in ipairs(G.forts) do if e.alive and e.fkind == "bunker" and not e.pt then victim = e break end end
if victim then
  local s0 = PF.score
  G.damageEnt(victim, 1e6, { P = PF, team = "atk", name = foe.DisplayName })
  R.run(0.5)
  check(not victim.alive and victim.model:GetAttribute("Wreck"), "碉堡被炸成残骸")
  check(PF.score - s0 >= G.Config.Score.fortKill, "打掉的人加分 " .. (PF.score - s0))
  local v = C.fortViews[victim.id]
  check(v ~= nil and v.wrecked, "客户端画成塌了的残骸")
end
G.emit("captured", { id = "A" })
R.run(0.5)
local flipped, total = 0, 0
for _, e in ipairs(G.forts) do
  if e.pt == "A" then
    total = total + 1
    if e.team == "atk" then flipped = flipped + 1 end
  end
end
check(total > 0 and flipped == total, "据点 A 的 " .. total .. " 处工事归攻方")

print("⑦ 工兵的破障器材：探雷、排雷")
G.hurtChar(foe.Character, 1e5, nil)
respawn(foe, "engineer", "fleet")
local bp = foe:FindFirstChildOfClass("Backpack")
local kit = bp and bp:FindFirstChild("breach")
check(kit ~= nil, "工兵带的是破障器材（不再能自己埋雷）")
local m3
for _, m in ipairs(mines) do if m.alive then m3 = m break end end
if kit and m3 then
  kit.Parent = foe.Character
  foe.Character:PivotTo(CF(m3.x + 4.5, Map.ground(m3.x + 4.5, m3.z) + 3.5, m3.z))
  G.fortsDebug.fields = G.fortsDebug.fields
  -- 工兵站在雷旁边不会踩响（4.5 格外）；探雷
  R.as("server", function() G.shoot(PF, "breach", "scan") end)
  check(m3.alive, "站在雷旁边没踩响")
  check(m3.known and m3.known.atk, "探出来了（全队都能看见）")
  local s0 = PF.score
  R.as("server", function() G.shoot(PF, "breach", "start", "m" .. m3.i) end)
  R.run(0.5)
  R.as("server", function() G.shoot(PF, "breach", "done", "m" .. m3.i) end)
  check(m3.alive, "按得不够久不算")
  R.as("server", function() G.shoot(PF, "breach", "start", "m" .. m3.i) end)
  R.run(1.7)
  R.as("server", function() G.shoot(PF, "breach", "done", "m" .. m3.i) end)
  check(not m3.alive and PF.score > s0, "按住够久，排掉了（加分）")
end

print("⑧ 停车、出生避开工事")
local some = G.forts[1]
local sp = some.base.Position
check(not G.spotClear(sp.X, sp.Z, 5, 5, 6), "工事上不能停车")
check(G.spotClear(Map.CAMP.x + 40, Map.CAMP.z - 60, 3, 3, 5) ~= nil, "空地能停")
T.summary()
