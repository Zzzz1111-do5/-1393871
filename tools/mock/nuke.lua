-- 核导弹测试（模拟器；用户 11-22：「给 h6k 加一个高超音速战术核弹的挂载吧」）：python3 tools/mock/run.py tools/mock/nuke.lua
--   轰-6K 挂「核打击」预设（弹舱一枚惊雷-1）→ 开战没多久不能发 → 天上按住 F 1.2 秒才发射（中间一条解锁进度）→ 两队都收到警报 →
--   导弹投放、点火、爬升、滑翔、俯冲、空爆 → 圈里的敌人和工事没了、外圈的受伤、自己人不受伤 → 辐射区每秒掉血 → 这一队冷却 →
--   客户端：警报条、红圈、核爆的火球 / 蘑菇云摆出来，九十多秒后全收掉，没有报错
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local RS = R.services.ReplicatedStorage

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
G.aiVehOff = true
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6001, true)
local foe = T.join("P2", 6002, false)
local foe2 = T.join("P3", 6003, false)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
setTeam(me, "atk")
setTeam(foe, "def")
setTeam(foe2, "def")
R.run(1)
local C = T.C
T.leaveMenu()
local AD = R.require(RS:FindFirstChild("AirDefs"))
local Map = G.Map
local P, PF, PF2 = G.P[me], G.P[foe], G.P[foe2]

print("① 挂载：轰-6K 弹舱能挂一枚惊雷-1，「核打击」预设")
local h6 = AD.get("h6k")
local load = AD.presetLoad(h6, "nuke")
local bayI = nil
for i, s in ipairs(h6.st) do if s.name == "bay" then bayI = i end end
check(bayI ~= nil and load[bayI] == "hn1", "核打击预设：弹舱挂 hn1（" .. tostring(bayI and load[bayI]) .. "）")
check(AD.count(h6.st[bayI], "hn1") == 1, "弹舱只挂一枚")
local W = AD.W.hn1
check(W and W.nuke and W.hyper and W.shape.L < (h6.bays.main.z1 - h6.bays.main.z0), string.format("弹长 %.1f 格放得进弹舱（%d 格）", W.shape.L, h6.bays.main.z1 - h6.bays.main.z0))
check(C.T("aw.hn1") ~= "aw.hn1" and C.T("preset.nuke") ~= "preset.nuke", "名字有中文：" .. C.T("aw.hn1") .. " / " .. C.T("preset.nuke"))

print("② 开战前、开战没多久不能发")
T.actAsRemote(foe, "deploy", "rifle", "camp")
T.actAsRemote(foe2, "deploy", "rifle", "camp")
T.act("deploy", "rifle", "fleet")
R.run(2)
local okB = T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(okB, "开战")
local ok0, why0 = G.nukeCheck("atk")
check(not ok0 and why0 == "nuke.early", "开战 " .. G.Config.Nuke.first .. " 秒内不能发（" .. tostring(why0) .. "）")
G.Config.Nuke.first = 0
check(G.nukeCheck("atk") == true, "解锁了")

print("③ 目标：守方的据点；圈里站一个守方，重伤圈边上站一个")
local tp = Map.POINTS[1]
local gz = V3(tp.x, Map.ground(tp.x, tp.z), tp.z)
local function put(pl, dx)
  local c = pl.Character
  if not c then return end
  local x, z = gz.X + dx, gz.Z
  c:PivotTo(CF(x, Map.ground(x, z) + 3.5, z))
  c.HumanoidRootPart.Anchored = true
end
put(foe, 250)
put(foe2, 1800)
local forts0 = {}
for _, f in pairs(G.forts or {}) do
  if f.alive and f.team == "def" and f.root then
    local d = (f.root.CFrame.Position - gz).Magnitude
    if d < G.Config.Nuke.kill * 0.8 then table.insert(forts0, f) end
  end
end
check(PF.alive and PF2.alive, "两个守方都活着")

print("④ 轰-6K 在 9 公里外、2600 格高，朝着目标飞")
local from = V3(gz.X, 2600, gz.Z + 9000)
local e = G.spawnAircraft("atk", "h6k", R.CFrame.lookAt(from, V3(gz.X, 2600, gz.Z)), load, P, 1)
check(e ~= nil, "生成了轰-6K")
me.Character:PivotTo(CF(from.X + 20, from.Y, from.Z))
R.run(0.2)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and e.driver == P, "坐进了驾驶舱")
check(C.fly ~= nil, "客户端开始开飞机")
-- 选到核导弹（挂的弹列表里）
local st = C.fly
if st then
  for i, wid in ipairs(st.wl or {}) do if wid == "hn1" then st.wi = i end end
end
check(st and st.wl and st.wl[st.wi] == "hn1", "选中了惊雷-1")
-- 客户端每帧按镜头重新算瞄准点（模拟器的镜头不一定对着目标）：发射时服务器那边按目标点算
local arm0 = G.nukeArm
G.nukeArm = function(team, from, aim) return arm0(team, from, gz) end

print("⑤ 按住 F：要 1.2 秒才发")
T.key(Enum.KeyCode.F, true)
R.run(0.5)
local armTexts = T.texts("核导弹")
check(#armTexts > 0 and G.nukeCount() == 0, "按了半秒：显示解锁进度（" .. tostring(armTexts[1]) .. "），还没发")
R.run(1.0)
T.key(Enum.KeyCode.F, false)
R.run(0.3)
check(G.nukeCount() == 1, "按够了：发射了")
check((e.stores[bayI] or 0) == 0, "弹舱的那枚用掉了")
local warnN = select(2, C.nukeActive())
check(warnN == 1, "客户端收到警报（" .. tostring(warnN) .. " 个）")
local banner = T.texts(C.T("nuke.launched"))
check(#banner > 0, "我方看到「" .. C.T("nuke.launched") .. "」")
local nShot = nil
for _, s in ipairs(G.shots) do if s.w == W then nShot = s end end
check(nShot ~= nil and nShot.hyper.phase == "drop", "导弹先掉下去（不点火）")
local tgtErr = nShot and (V3(nShot.hyper.tgt.X, 0, nShot.hyper.tgt.Z) - V3(gz.X, 0, gz.Z)).Magnitude or -1
check(tgtErr >= 0 and tgtErr < 5, string.format("瞄准点落在地面上（差 %.1f 格）", tgtErr))

print("⑥ 飞：点火、爬升、滑翔、俯冲、空爆")
local phases, maxSpd, apex = {}, 0, 0
local det = T.runUntil(function()
  if nShot then
    phases[nShot.hyper.phase] = true
    maxSpd = math.max(maxSpd, nShot.vel.Magnitude)
    apex = math.max(apex, nShot.pos.Y)
  end
  return G.nukeLast ~= nil
end, 60, 1 / 30)
check(det, "炸了")
check(phases.boost and phases.dive, "经过了助推和俯冲（" .. (phases.boost and "助推 " or "") .. (phases.glide and "滑翔 " or "") .. (phases.dive and "俯冲" or "") .. "）")
check(maxSpd > 5000, string.format("最快 %.0f 格 / 秒（约 %.1f 马赫）", maxSpd, maxSpd / 2.8 / 343))
check(apex > 4000, string.format("弹道顶点 %.0f 格", apex))
local L = G.nukeLast
if L then
  local dh = (V3(L.p.X, 0, L.p.Z) - V3(gz.X, 0, gz.Z)).Magnitude
  local hb = L.p.Y - gz.Y
  check(dh < 250, string.format("落点离目标 %.0f 格", dh))
  check(hb > 30 and hb < 300, string.format("空爆：离地 %.0f 格", hb))
end

print("⑦ 伤害：圈里的敌人、工事没了，外圈的受伤，自己人没事")
R.run(0.5)
check(not PF.alive, "爆心 250 格的守方死了")
local hum2 = foe2.Character and foe2.Character:FindFirstChildOfClass("Humanoid")
check(PF2.alive and hum2 and hum2.Health < hum2.MaxHealth and hum2.Health > 0, string.format("1800 格外的守方受伤没死（血 %s）", tostring(hum2 and math.floor(hum2.Health))))
local fortDead = 0
for _, f in ipairs(forts0) do if not f.alive then fortDead = fortDead + 1 end end
check(#forts0 == 0 or fortDead == #forts0, string.format("圈里守方的工事全毁（%d / %d）", fortDead, #forts0))
check(e.alive and P.alive, "自己的轰炸机、飞行员没事")
local ok2, why2 = G.nukeCheck("atk")
check(not ok2 and why2 == "nuke.cd", "攻方要冷却（" .. tostring(why2) .. "）")
check(G.nukeCheck("def") == true, "守方不受影响")

-- 地面：焦土（中心熔岩壳、外面玄武岩 / 板岩色）、爆心一个浅坑
R.run(2)
local burn = { CrackedLava = 0, Basalt = 0, Slate = 0 }
local ball = 0
for _, f in ipairs(R.terrainFills or {}) do
  if f.k == "replace" and burn[f.mat] then burn[f.mat] = burn[f.mat] + 1 end
  if f.k == "ball" and f.mat == "Air" and (V3(f.p.X, 0, f.p.Z) - V3(gz.X, 0, gz.Z)).Magnitude < 5 then ball = ball + 1 end
end
check(burn.CrackedLava > 0 and burn.Basalt > 0 and burn.Slate > 0, string.format("地上烧出焦土（熔岩 %d、玄武岩 %d、板岩 %d 处）", burn.CrackedLava, burn.Basalt, burn.Slate))
check(ball > 0, "爆心挖了一个浅坑")

print("⑧ 辐射区：守方站进去每秒掉血")
put(foe2, 200)
local h0 = hum2 and hum2.Health or 0
R.run(3)
local h1 = hum2 and hum2.Health or 0
check(h1 < h0, string.format("辐射区里 3 秒：血 %.0f → %.0f", h0, h1))
put(foe2, 3000)

print("⑨ 客户端：核爆摆出来，过一会儿全收掉")
local nAct = C.nukeActive()
local fx = R.services.Workspace:FindFirstChild("NukeFx")
check(nAct == 1 and fx and #fx:GetChildren() > 40, string.format("核爆在画（%d 个零件）", fx and #fx:GetChildren() or 0))
local e0 = #R.errors
R.run(100)
nAct = C.nukeActive()
check(nAct == 0, "九十多秒后收掉了")
check(fx and #fx:GetChildren() == 0, "零件都删了（剩 " .. tostring(fx and #fx:GetChildren()) .. " 个）")
check(#R.errors == e0, "没有新的报错（" .. (#R.errors - e0) .. "）")
for i = e0 + 1, math.min(e0 + 6, #R.errors) do print("    " .. R.errors[i]:sub(1, 300)) end
for i = 1, math.min(6, #R.errors) do print("  报错：" .. R.errors[i]:sub(1, 300)) end
TEST_CODE = (T.fails > 0) and 1 or 0
print(T.fails == 0 and "全部通过" or ("没通过 " .. T.fails .. " 项"))
