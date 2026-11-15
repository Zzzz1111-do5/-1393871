-- 载具测试（照 tools/test/ia_veh.luau，在没有 Lune 的机器上用模拟器跑）：
--   python3 tools/mock/run.py tools/mock/veh.lua def   守方：坦克部署、开车、悬架、瞄准镜四种模式、开炮、烟幕弹、下车上车、被毁
--   python3 tools/mock/run.py tools/mock/veh.lua atk   攻方：两栖车从海里开上岸、坦克坐气垫艇上滩
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local side = TEST_ARGS:match("atk") and "atk" or "def"

local G = T.boot()
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
check(G.worldReady, "地图生成好了（地形体素 " .. tostring(R.voxelsWritten) .. "）")
local me = T.join("P1", 5001, true)
local other = T.join("P2", 5002, false)
-- 有客户端的这个人放到要测的一方
local function setTeam(pl, team)
  local P = G.P[pl]
  P.team = team
  pl.Team = G.TEAM[team]
  pl.Neutral = false
  pl:SetAttribute("Side", team)
  G.pushOne(P)
end
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
-- 开局时会打乱分队：等分好了再把有客户端的这个人放到要测的一方
setTeam(me, side)
setTeam(other, side == "def" and "atk" or "def")
R.run(1)
local P, PO = G.P[me], G.P[other]
local C = T.C
check(C ~= nil and C.S ~= nil, "客户端收到了服务器状态")

if side == "def" then
  print("① 守方在营地部署一辆坦克")
  local tankId = G.Config.Vehicles.def.tank[3]
  check(C.S.vehModels and #C.S.vehModels > 0, "客户端拿到了能开的型号：" .. table.concat(C.S.vehModels or {}, ","))
  check(C.S.vehAvail and C.S.vehAvail.tank and C.S.vehAvail.tank.cap >= 1, "坦克名额 " .. tostring(C.S.vehAvail and C.S.vehAvail.tank and C.S.vehAvail.tank.cap))
  C.deploySel.mode, C.deploySel.veh, C.deploySel.spawn, C.deploySel.role = "veh", tankId, "camp", "engineer"
  R.as("client", function() C.refreshDeploy() end)
  T.click("^" .. C.T("ui.deployBtn") .. "$")
  R.run(2)
  local e = P.vehicle
  check(e ~= nil and e.alive and e.def.id == tankId, "坐进了 " .. tostring(e and e.def.id))
  check(P.alive and me.Character and me.Character.HumanoidRootPart.Anchored, "人锚定在车里")
  check(C.drive ~= nil and C.drive.id == (e and e.id), "客户端接管驾驶")
  local v
  if C.views and e then for em, vv in pairs(C.views) do if em == e.model then v = vv end end end
  check(v ~= nil and v.M ~= nil and #v.M.parts > 40, "客户端拼好了车的模型：" .. (v and v.M and #v.M.parts or 0) .. " 个零件、" .. (v and v.M and #v.M.wheels or 0) .. " 个负重轮")

  print("② 开车：按住 W 往前开，服务器跟着动")
  local p0 = e.root.CFrame.Position
  T.key(Enum.KeyCode.W, true)
  R.run(4)
  T.key(Enum.KeyCode.W, false)
  R.run(1)
  local p1 = e.root.CFrame.Position
  local moved = (V3(p1.X, 0, p1.Z) - V3(p0.X, 0, p0.Z)).Magnitude
  check(moved > 40, string.format("开出去 %.0f 格", moved))
  local gy = G.Map.ground(p1.X, p1.Z)
  check(math.abs((p1.Y - e.def.H / 2) - gy) < 3, string.format("贴着地（车底 %.1f，地面 %.1f）", p1.Y - e.def.H / 2, gy))
  local lo, hi = 0, 0
  if v then for _, w in ipairs(v.M.wheels) do lo, hi = math.min(lo, w.dy), math.max(hi, w.dy) end end
  check(hi - lo > 0.05, string.format("负重轮各自上下（%.2f ～ %.2f 格）", lo, hi))

  print("③ 瞄准镜：昼光 → 夜视 → 热成像白热 → 黑热")
  T.tap(Enum.KeyCode.V)
  R.run(0.3)
  local cc = C.sightCC
  check(C.drive.sight and cc and cc.Enabled, "进瞄准镜，画面调色开了")
  local modes = {}
  for _ = 1, 3 do
    T.tap(Enum.KeyCode.N)
    R.run(0.6)
    modes[#modes + 1] = tostring(({ "day", "nv", "whot", "bhot" })[C.drive.mode])
  end
  check(modes[1] == "nv" and modes[2] == "whot" and modes[3] == "bhot", "N 依次切夜视、白热、黑热：" .. table.concat(modes, " → "))
  T.tap(Enum.KeyCode.V)
  R.run(0.3)
  check(not C.drive.sight and not cc.Enabled, "退出瞄准镜，调色关了")

  print("④ 开战后开炮、放烟幕弹")
  T.runUntil(function() return G.round.phase == "battle" end, 40)
  local w1 = e.def.weapons[1]
  local ammo0 = e.wst[w1].reserve + e.wst[w1].mag
  T.mouse(true)
  R.run(0.2)
  T.mouse(false)
  R.run(1)
  local ammo1 = e.wst[w1].reserve + e.wst[w1].mag
  check(ammo1 == ammo0 - 1, string.format("主炮打了一发（%d → %d）", ammo0, ammo1))
  T.tap(Enum.KeyCode.X)
  R.run(1.5)
  check(#G.smokes == e.def.smoke.n * #e.def.smoke.banks, "烟幕弹落地起了 " .. #G.smokes .. " 团烟")

  print("⑤ 下车、再上车")
  T.tap(Enum.KeyCode.F)
  R.run(1)
  check(P.vehicle == nil and not me.Character.HumanoidRootPart.Anchored, "下车了，能走")
  check(C.drive == nil, "客户端退出驾驶")
  T.act("enterVeh", e.id)
  R.run(1)
  check(P.vehicle == e and C.drive ~= nil, "按 E 又坐回去了")

  print("⑥ 被击毁：车组阵亡、名额冷却")
  local used0 = G.vehAvail("def").tank.u
  G.damageEnt(e, 1e6, { P = PO, team = PO.team, name = other.DisplayName })
  R.run(1)
  check(not e.alive and e.wreck, "车被打爆、变成残骸")
  check(not P.alive, "车组阵亡")
  check(G.vehAvail("def").tank.u == used0, "名额还占着（冷却中）")
else
  print("⑦ 攻方：两栖步战车从海里开上来；坦克坐气垫艇上滩")
  T.runUntil(function() return G.round.phase == "battle" end, 40)
  T.act("deployVeh", "zbd05", "beach.white", "rifle")
  R.run(2)
  local ea = P.vehicle
  check(ea ~= nil and ea.def.id == "zbd05", "两栖车 ZBD-05 出生在海里")
  if ea then
    local pz = ea.root.CFrame.Position
    check(G.Map.height(pz.X, pz.Z) < -2, string.format("在海里（水深 %.1f）", -G.Map.height(pz.X, pz.Z)))
    T.key(Enum.KeyCode.W, true)
    local track = {}
    local ashore = T.runUntil(function()
      local q = ea.root.CFrame.Position
      if #track < 1300 then track[#track + 1] = q end
      return G.Map.height(q.X, q.Z) > 1
    end, 40)
    T.key(Enum.KeyCode.W, false)
    local q = ea.root.CFrame.Position
    check(ashore, string.format("自己游上了岸（停在 x %.0f z %.0f，地面 %.1f）", q.X, q.Z, G.Map.height(q.X, q.Z)))
    -- 从浮着到踩着海底再到上岸，车身高度是连续的（不在某一下弹起）
    local jump = 0
    for i = 2, #track do jump = math.max(jump, math.abs(track[i].Y - track[i - 1].Y)) end
    check(jump < 0.6, string.format("上岸一路车身每帧高低最多变 %.2f 格", jump))
    if not ashore and TEST_ARGS:match("trace") then
      for i = 1, #track, 15 do local t = track[i] print(string.format("    %.1fs  x %.1f z %.1f y %.2f  地面 %.2f", i / 30, t.X, t.Z, t.Y, G.Map.height(t.X, t.Z))) end
    end
    T.tap(Enum.KeyCode.F)
    R.run(1)
  end
  G.hurtChar(me.Character, 1e5, { P = PO, team = PO.team, name = other.DisplayName })
  R.run(G.Config.RespawnDelay + 1)
  T.act("deployVeh", G.Config.Vehicles.atk.tank[3], "beach.blue", "rifle")
  R.run(1.5)
  local et = P.vehicle
  check(et ~= nil and et.locked, "坦克在气垫艇上（锁定，不能开）")
  local unl = T.runUntil(function() return et and not et.locked end, 30)
  check(unl, "气垫艇冲上滩、坦克放下来")
  if et then
    local q = et.root.CFrame.Position
    check(G.Map.height(q.X, q.Z) > 0.3, string.format("坦克在岸上（地面 %.1f）", G.Map.height(q.X, q.Z)))
  end
end
T.summary()
