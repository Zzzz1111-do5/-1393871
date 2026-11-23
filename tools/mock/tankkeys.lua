-- 坦克第一人称：方向键转炮塔、抬压炮，WASD 照常开车；开炮的后坐不是一下子跳过去（模拟器）：python3 tools/mock/run.py tools/mock/tankkeys.lua [veh=m1a2]
--   用户 11-22：「顺便说一下坦克第一人称的话，炮管转动用上下左右键，然后 WASD 继续管车体移动」「坦克开炮，我记得第一人称的时候那个炮管会瞬间往后」
--   ① 坐上车、按 C 进车里
--   ② ← 按住 1 秒：炮塔往左转；点一下 →：只动零点几度（细瞄）；↑ 按住 1 秒：炮抬起来
--   ③ ↓ 一直按：压到俯角的头就停；松开再按 ↑：马上往上走（瞄准线没有越过头）
--   ④ 按住 W 同时按 ←：车往前开、炮塔照样转
--   ⑤ 只按 D（车体原地转）：炮指着的方向不跟着车转（炮塔稳定）
--   ⑥ 鼠标在车里只转头、不转炮塔；B 导演镜头里方向键挪镜头、不转炮塔
--   ⑦ 开一炮（60 帧）：车外的炮管、车里的炮尾都是几帧里坐到底、再慢慢复进，不是一帧跳过去；镜头后坐也有个起势
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local Map = G.Map
local cam = R.workspace.CurrentCamera

print("① 坐上 " .. VEH .. "，按 C 进车里")
local def = VD.get(VEH)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
-- 一块大平地（要往前开一段、原地转）
local best, bx, bz = math.huge, hp.X + 16, hp.Z
for k = 0, 47 do
  local a = k / 48 * math.pi * 2
  for _, rr in ipairs({ 20, 34, 50 }) do
    local x, z = hp.X + math.cos(a) * rr, hp.Z + math.sin(a) * rr
    if Map.isLand(x, z) and Map.height(x, z) > 2 then
      local s = Map.slope(x, z) + Map.slope(x + 12, z) + Map.slope(x - 12, z) + Map.slope(x, z + 12) + Map.slope(x, z - 12)
      -- 上面不能有东西（工事、帐篷、石头）：从高处往下打，先碰到的得是地面
      local clear = true
      for _, o in ipairs({ { 0, 0 }, { 10, 0 }, { -10, 0 }, { 0, 10 }, { 0, -10 }, { 7, 7 }, { -7, -7 }, { 7, -7 }, { -7, 7 } }) do
        local h = R.workspace:Raycast(V3(x + o[1], Map.height(x, z) + 40, z + o[2]), V3(0, -80, 0))
        if h and h.Instance and h.Instance.ClassName ~= "Terrain" then clear = false break end
      end
      if clear and s < best then best, bx, bz = s, x, z end
    end
  end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end   -- 人走到车边上（上车要离得近）
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 " .. VEH)
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
check(C.interiorOn() and I.mode == "seat", "按 C：坐进车里（" .. tostring(I.station) .. "）")
local d = st.d

local function hold(code, sec, dt)
  T.key(code, true)
  R.run(sec, dt or 1 / 30)
  T.key(code, false)
end
local function angd(a, b) return (a - b + 180) % 360 - 180 end
local function gunDir()
  local base = st.root * CF(0, -d.H / 2, 0)
  return VD.gunCF(d, base, st.ty, st.gp).LookVector
end
local function yawOf(v) return math.deg(math.atan2(-v.X, -v.Z)) end

print("② 方向键转炮塔、抬炮")
R.run(0.5)
local ty0, gp0 = st.ty, st.gp
hold(Enum.KeyCode.Left, 1.0)
R.run(0.4)
local dL = angd(st.ty, ty0)
check(dL < -18 and dL > -50, string.format("← 按住 1 秒：炮塔往左转了 %.1f°（转速 %d°/s，刚按下去慢）", -dL, d.turret.trav))
local ty1 = st.ty
T.key(Enum.KeyCode.Right, true)
R.step(1 / 60)
T.key(Enum.KeyCode.Right, false)
R.run(0.4)
local dT = angd(st.ty, ty1)
check(dT > 0.02 and dT < 1.0, string.format("点一下 →：只往右动 %.2f°（细瞄）", dT))
local gp1 = st.gp
hold(Enum.KeyCode.Up, 1.0)
R.run(0.4)
check(st.gp - gp1 > 4, string.format("↑ 按住 1 秒：炮抬起来 %.1f°", st.gp - gp1))

print("③ 压到俯角的头就停，不越过去")
hold(Enum.KeyCode.Down, 4.0)
R.run(0.4)
local lo = d.turret.elev[1]
check(math.abs(st.gp - lo) < 1.2, string.format("↓ 一直按：压到俯角的头 %.1f°（限 %d°）", st.gp, lo))
local gpLo = st.gp
hold(Enum.KeyCode.Up, 0.35)
R.run(0.3)
check(st.gp - gpLo > 0.5, string.format("松开再按 ↑ 0.35 秒：马上往上走了 %.1f°（瞄准线没有越过头）", st.gp - gpLo))
hold(Enum.KeyCode.Up, 0.6)
R.run(0.3)

print("④ 按住 W 开车，同时 ← 转炮塔")
local p0 = st.root.Position
local ty2 = st.ty
T.key(Enum.KeyCode.W, true)
hold(Enum.KeyCode.Left, 1.5)
T.key(Enum.KeyCode.W, false)
local moved = (st.root.Position - p0).Magnitude
check(moved > 4, string.format("W：车往前开了 %.1f 格", moved))
check(angd(st.ty, ty2) < -15, string.format("同时 ←：炮塔照样转了 %.1f°", -angd(st.ty, ty2)))
R.run(2.5)   -- 停下来

print("⑤ 只按 D：车体转、炮还指着原来的方向")
R.run(0.5)
local hy0 = math.deg(st.yaw)
local gy0 = yawOf(gunDir())
local ty3 = st.ty
hold(Enum.KeyCode.D, 1.5)
R.run(0.6)
local hTurn = angd(math.deg(st.yaw), hy0)
local gTurn = angd(yawOf(gunDir()), gy0)
check(math.abs(hTurn) > 12, string.format("D：车体转了 %.1f°", hTurn))
check(math.abs(gTurn) < 3, string.format("炮指的方向只差 %.1f°（炮塔相对车体反着转了 %.1f°）", gTurn, angd(st.ty, ty3)))

print("⑥ 鼠标只转头；导演镜头里方向键挪镜头")
local ty4 = st.ty
local look0 = cam.CFrame.LookVector
for _ = 1, 10 do
  R.mouseDelta = R.Vector2.new(30, 0)
  R.step(1 / 30)
end
R.run(0.5)
check(math.abs(angd(st.ty, ty4)) < 0.5, string.format("鼠标往右挪：炮塔没跟着转（%.2f°）", angd(st.ty, ty4)))
check(look0:Dot(cam.CFrame.LookVector) < 0.995, "鼠标往右挪：头转了")
T.tap(Enum.KeyCode.B)
R.run(0.3)
check(C.interiorState().mode == "free", "B：导演镜头")
local camP = cam.CFrame.Position
local ty5 = st.ty
hold(Enum.KeyCode.Left, 1.0)
R.run(0.3)
check(math.abs(angd(st.ty, ty5)) < 0.5, string.format("导演镜头里 ←：炮塔不转（%.2f°）", angd(st.ty, ty5)))
check((cam.CFrame.Position - camP).Magnitude > 1, "导演镜头里 ←：镜头挪了")
T.tap(Enum.KeyCode.B)
R.run(0.3)
check(C.interiorState().mode == "seat", "再按 B：回到乘员位")

print("⑦½ 坦克锁在炮长位（用户 11-23：「不要更新坦克驾驶员视角 就只锁定开炮手就完事了」）：F2～F5 都停在炮长位；Shift 进主瞄准镜、T 是车长的主观瞄")
for _, k in ipairs({ Enum.KeyCode.F2, Enum.KeyCode.F4, Enum.KeyCode.F5 }) do
  T.tap(k)
  R.run(0.3)
  check(C.interiorState().station == "gunner", k.Name .. "：还是炮长位（" .. tostring(C.interiorState().station) .. "）")
end
local gsp = C.interiorState().cur.spec.stations.gunner
check(#C.interiorState().cur.spec.order == 1, "乘员位只有炮长一个")
check(gsp.optics and gsp.optics.third ~= nil and gsp.optics.third.kind ~= "gps",
  "车长的主观瞄挪到炮长位的 T（" .. tostring(gsp.optics and gsp.optics.third and (gsp.optics.third.name or gsp.optics.third.kind)) .. "）")
T.tap(Enum.KeyCode.LeftShift)
R.run(0.6)
check(st.sight == true and C.interiorOptic == nil, "Shift：进了炮长主瞄准镜")
local lk0 = cam.CFrame.LookVector
for _ = 1, 30 do
  R.mouseDelta = R.Vector2.new(25, 0)
  R.step(1 / 30)
end
R.run(0.8)
local turn = math.deg(math.acos(clamp(lk0:Dot(cam.CFrame.LookVector), -1, 1)))
check(turn > 5, string.format("镜里鼠标往右挪：视角跟着炮转了 %.1f°", turn))
local lk1 = cam.CFrame.LookVector
hold(Enum.KeyCode.Left, 0.8)
R.run(0.6)
local turn2 = math.deg(math.acos(clamp(lk1:Dot(cam.CFrame.LookVector), -1, 1)))
check(turn2 > 5, string.format("镜里按 ←：视角跟着炮转了 %.1f°", turn2))
local sightCC = C.sightCC
local sm = C.drive and C.drive.mode
check(sightCC and sightCC.Enabled and sm == 3, "天黑默认热成像白热档（不是绿色的夜视）：档 " .. tostring(sm))
T.tap(Enum.KeyCode.LeftShift)
R.run(0.6)
check(not st.sight and C.interiorState().mode == "seat" and C.interiorState().station == "gunner", "再按 Shift：回到炮长位")
T.tap(Enum.KeyCode.T)
R.run(0.6)
local dop = C.interiorOpticState and C.interiorOpticState()
check(dop ~= nil and dop.o.kind == gsp.optics.third.kind, "T：车长的主观瞄（" .. tostring(dop and dop.o.name) .. "）")
local nvg = R.services.Lighting:FindFirstChild("NVGrade")
check(not (C.nvgOn() and nvg and nvg.Enabled), "开着车里的观瞄设备：夜视仪的绿色调色让开")
T.tap(Enum.KeyCode.T)
R.run(0.5)
check((C.interiorOpticState and C.interiorOpticState()) == nil, "再按 T 关掉")
check(C.interiorState().station == "gunner", "关了还在炮长位")

print("⑦¾ 车里第一人称 N：夜视 → 热成像 → 关")
if not C.nvgOn() then T.tap(Enum.KeyCode.N) R.run(0.4) end
check(C.nvgOn(), "夜视仪开着")
T.tap(Enum.KeyCode.N)
R.run(0.5)
local irc = R.services.Lighting:FindFirstChild("VehIrCC")
check(not C.nvgOn() and C.vehThermalShown() and irc and irc.Enabled, "按 N：换成热成像（白热，车里第一人称整个画面）")
T.tap(Enum.KeyCode.LeftShift)
R.run(0.6)
check(st.sight and not C.vehThermalShown(), "开着炮长瞄准镜：热成像让出画面（瞄准镜自己有热成像档）")
T.tap(Enum.KeyCode.LeftShift)
R.run(0.6)
check(not st.sight and C.vehThermalShown(), "退出瞄准镜：热成像回来")
T.tap(Enum.KeyCode.N)
R.run(0.5)
check(not C.nvgOn() and not C.vehThermalShown() and not irc.Enabled, "再按 N：都关掉")
T.tap(Enum.KeyCode.N)
R.run(0.5)
check(C.nvgOn(), "再按 N：夜视仪又开了")

print("⑦ 开一炮：后坐是几帧里坐到底、再慢慢复进")
T.tap(Enum.KeyCode.F3)
R.run(0.4)
local v = C.viewById(e.id)
check(v ~= nil, "View 里有这辆车")
local K = I.cur and I.cur.b.groups.recoil and true
local series, inner, kicks = {}, {}, {}
T.mouse(true)
for i = 1, 48 do
  R.step(1 / 60)
  if i == 2 then T.mouse(false) end
  series[i] = v and v.recoil or 0
  local g = I.cur and I.cur.b.groups.recoil
  inner[i] = g and g.anim.Position.Z or 0
  kicks[i] = st.kick or 0
end
local function firstNZ(a) for i = 1, #a do if a[i] > 1e-4 then return i end end return nil end
local function stats(a)
  local i0 = firstNZ(a)
  if not i0 then return nil end
  local mx, iMax, jump = 0, i0, 0
  for i = i0, #a do
    if a[i] > mx then mx, iMax = a[i], i end
    jump = math.max(jump, math.abs(a[i] - (a[i - 1] or 0)))
  end
  return { i0 = i0, first = a[i0], max = mx, iMax = iMax, jump = jump, last = a[#a] }
end
local so = stats(series)
check(so ~= nil, "开炮了：车外的炮管后坐")
if so then
  print(string.format("   车外炮管：第一帧 %.2f 格，第 %d 帧坐到底 %.2f 格，一帧最多动 %.2f 格，0.8 秒时 %.2f 格", so.first, so.iMax - so.i0 + 1, so.max, so.jump, so.last))
  check(so.first < 0.5 * so.max, string.format("车外炮管：不是一帧坐到底（第一帧 %.0f%%）", 100 * so.first / math.max(so.max, 1e-6)))
  check(so.iMax - so.i0 >= 3 and so.iMax - so.i0 <= 8, string.format("车外炮管：%d 帧里坐到底", so.iMax - so.i0 + 1))
  check(so.jump < 0.5 * so.max, string.format("车外炮管：一帧最多动 %.0f%%", 100 * so.jump / math.max(so.max, 1e-6)))
  check(so.last < 0.05 * so.max, "车外炮管：0.8 秒复进完")
end
local si = stats(inner)
check(K and si ~= nil, "车里的炮尾也后坐")
if si then
  print(string.format("   车里炮尾：第一帧 %.2f 格，第 %d 帧坐到底 %.2f 格，一帧最多动 %.2f 格", si.first, si.iMax - si.i0 + 1, si.max, si.jump))
  check(si.first < 0.5 * si.max and si.jump < 0.5 * si.max, "车里炮尾：不是一帧坐到底")
end
local sk = stats(kicks)
if sk then
  check(sk.first < 0.6 * sk.max and sk.iMax > sk.i0, string.format("镜头后坐有个起势（第一帧 %.0f%%，第 %d 帧最大）", 100 * sk.first / math.max(sk.max, 1e-6), sk.iMax - sk.i0 + 1))
else
  check(false, "开炮：镜头后坐")
end
T.summary()
