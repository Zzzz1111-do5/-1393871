-- 载具内饰测试（模拟器）：python3 tools/mock/run.py tools/mock/interior.lua [dump=<目录>]
--   用户 11-21：所有载具一比一还原内饰和里面所有功能性的东西（屏幕等），对标 Steel Beasts，要拿去拍电影
--   ① 坐上 M1A2，按 C 进车内：内饰拼出来了（零件、四个乘员、屏幕、灯），镜头在车体里
--   ② F2～F5 换四个乘员位：镜头在各自的位置、都在车里；自己坐的那个乘员不画头
--   ③ 开一炮：炮闩后坐、落下；装填手转身开弹药舱门、抽弹、推弹入膛、关闩，按装填时间走完；弹架上少一发
--   ④ Shift 进主瞄准镜：内饰收起来、镜头归瞄准镜；再按回来
--   ⑤ B 导演镜头：方向键挪得动、还跟着车走；U 藏界面、再按放回来
--   ⑥ C 一路换到车外：内饰收起来；下车：内饰拆掉
--   dump=<目录>：把内饰零件（车体坐标）、各乘员位的镜头、灯写成 interior_m1a2.json，tools/mock/interior_view.cjs 画成图
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"
local dumpCams = {}

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

print("① 坐上 " .. VEH .. "，按 C 进车内")
local def = VD.get(VEH)
check(P.alive and me.Character ~= nil, "守方在营地出生了")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
-- 车停在人旁边一块平地上（上车要离车不远）
local cx, cz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 18, hp.Z + math.sin(a) * 18
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
check(C.interiorOn() and I.cur ~= nil and I.mode == "seat", "按 C：坐进车里（" .. tostring(I.station) .. "）")
local cur = I.cur
local nParts, nCrew, nScreens, nLights = 0, 0, 0, 0
if cur then
  nParts = #cur.b.parts
  for _ in pairs(cur.crew) do nCrew = nCrew + 1 end
  nScreens = #cur.b.screens
  nLights = #cur.b.lights
end
check(nParts > 400, "内饰零件 " .. nParts .. " 个")
check(nCrew == #cur.spec.order, string.format("乘员 %d 个（%d 个乘员位）", nCrew, #cur.spec.order))
check(nScreens >= 5, "屏幕 " .. nScreens .. " 块")
local live = 0
if cur then for _, s in ipairs(cur.b.screens) do if s.update then live = live + 1 end end end
check(live == nScreens, string.format("屏幕页面都起来了（%d / %d）", live, nScreens))
check(nLights >= 4, "车里的灯 " .. nLights .. " 盏")
-- 屏幕不反光（用户 11-21：坐在车里看，坦克屏幕有一块地方反光、看不清）：显示面哑光、不反射，字的亮度不超过夜里泛光的门槛（1.05）
local glossy, bright = 0, 0
if cur then
  for _, s in ipairs(cur.b.screens) do
    if s.page ~= "hud" then
      if s.part.Material == Enum.Material.Glass or (s.part.Reflectance or 0) > 0 then glossy = glossy + 1 end
      if (s.gui.Brightness or 1) > 1.05 then bright = bright + 1 end
    end
  end
end
check(glossy == 0 and bright == 0, string.format("屏幕哑光、不泛光（反光的 %d 块、太亮的 %d 块）", glossy, bright))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
-- 镜头在车体的方框里
local cam = R.workspace.CurrentCamera
local function inside(tag)
  local v = C.viewById(e.id)
  local hull = v and v.hullF
  if not hull then return false end
  local q = hull:PointToObjectSpace(cam.CFrame.Position)
  local ok = math.abs(q.X) < def.W / 2 and q.Y > 0.3 and q.Y < def.H + 0.6 and math.abs(q.Z) < def.L / 2
  check(ok, string.format("%s：镜头在车里（车体坐标 %.1f, %.1f, %.1f 格）", tag, q.X, q.Y, q.Z))
  return ok, q
end
inside("进车内")

print("② F2～F5 换乘员位")
local camAt = {}
local KEYS = { driver = Enum.KeyCode.F2, gunner = Enum.KeyCode.F3, commander = Enum.KeyCode.F4, loader = Enum.KeyCode.F5 }
for _, name in ipairs(cur.spec.order) do
  T.tap(KEYS[name])
  R.run(0.3)
  local st = C.interiorState()
  check(st.station == name, "换到 " .. name)
  local _, q = inside(name)
  camAt[name] = q
  local cr = st.cur and st.cur.crew[name]
  check(cr ~= nil and cr.headShown == false, name .. "：自己这个乘员不画头（第一人称）")
  local hidden, total = 0, 0   -- 手和腿也不画（用户 11-21：第一人称不要显示我的腿和胳膊）
  for _, p in ipairs(cr and cr.f.model:GetDescendants() or {}) do
    if p:IsA("BasePart") then
      total = total + 1
      if p.LocalTransparencyModifier == 1 then hidden = hidden + 1 end
    end
  end
  check(total > 0 and hidden == total, string.format("%s：自己整个人都不画（%d / %d 块）", name, hidden, total))
end
if camAt.driver and camAt.gunner and camAt.commander then
  check(camAt.driver.Z < camAt.gunner.Z - 1 and camAt.commander.Y > camAt.gunner.Y - 0.5,
    string.format("位置对：驾驶员在最前（z %.1f）、炮长（x %.1f）、车长（x %.1f, y %.1f）", camAt.driver.Z, camAt.gunner.X, camAt.commander.X, camAt.commander.Y))
end

-- 导出给预览图
local dumpOut = dofile(MOCK_DIR .. "/interior_dump.lua")
local function dumpJSON(path)
  local v = C.viewById(e.id)
  dumpOut(C.interiorState().cur, v.hullF, dumpCams, path, cam, Enum)
end
for _, name in ipairs(cur.spec.order) do
  T.tap(KEYS[name])
  R.run(0.2)
  dumpCams[name] = cam.CFrame
end

print("③ 开一炮：后坐、开闩、装填手装弹")
local st0 = C.interiorState()
local c0 = st0.cur
local rack0 = c0 and c0.rackN
T.mouse(true)
R.run(0.1)
T.mouse(false)
local maxR, blkOpen = 0, false
for _ = 1, 15 do
  R.run(1 / 30)
  local g = c0.b.groups.recoil
  local z = g and g.anim.Position.Z or 0
  if z > maxR then maxR = z end
end
check(maxR > 0.7 and maxR < 0.95, string.format("炮闩后坐 %.2f 格（M256 真实 0.305 米 = 0.85 格）", maxR))
R.run(0.6)
local blk = c0.b.groups.blk
blkOpen = blk and blk.anim.Position.Y < -0.2
check(blkOpen, "复进时炮闩自动打开（落下）")
check(c0.loadT ~= nil, "装填手开始装弹")
local carousel = c0.spec.loader == "carousel"
local sawDoor, sawCarry, sawRam, sawTurn, sawLift, sawRammer = false, false, false, false, false, false
local a0 = c0.carA or 0
local lift0 = c0.b.groups.lift and c0.b.groups.lift.world.Position
local t0 = 0
while c0.loadT and t0 < 9 do
  R.run(0.1)
  t0 = t0 + 0.1
  if c0.door.L > 0.8 then sawDoor = true end
  if c0.carry then sawCarry = true end
  if c0.lo and c0.lo.k > 0.7 then sawRam = true end
  if carousel then
    if math.abs((c0.carA or 0) - a0) > 0.05 then sawTurn = true end
    local lw = c0.b.groups.lift.world.Position
    if lift0 and (lw - lift0).Magnitude > 1.5 then sawLift = true end
    if c0.b.groups.rammer.anim.Position.Magnitude > 0.5 then sawRammer = true end
  end
end
if carousel then
  check(sawTurn, "自动装弹机：转盘转到要的弹种")
  check(sawLift, "提弹机把弹盒提到炮尾")
  check(sawRammer, "链式推弹机推弹")
else
  check(sawDoor, "膝盖顶开弹药舱门（门滑开）")
  check(sawCarry, "从弹架上抽出一发")
  check(sawRam, "推弹入膛")
end
check(c0.loadT == nil and c0.loaded, string.format("装填完成（%.1f 秒）", t0))
check(blk.anim.Position.Y > -0.05, "炮闩关上了")
R.run(0.5)
check(c0.rackN == (rack0 or 0) - 1, string.format("弹架 / 转盘上少了一发（%s → %s）", tostring(rack0), tostring(c0.rackN)))

print("④ 炮长位 Shift 进主瞄准镜")
T.tap(Enum.KeyCode.F3)
R.run(0.2)
T.tap(Enum.KeyCode.LeftShift)
R.run(0.3)
check(C.drive.sight and c0.model.Parent == nil, "进了瞄准镜：内饰收起来")
T.tap(Enum.KeyCode.LeftShift)
R.run(0.3)
check(not C.drive.sight and c0.model.Parent ~= nil and C.interiorOn(), "出瞄准镜：回到炮长位")

print("⑤ B 导演镜头、U 藏界面")
T.tap(Enum.KeyCode.B)
R.run(0.1)
local p0 = C.viewById(e.id).hullF:PointToObjectSpace(cam.CFrame.Position)
T.key(Enum.KeyCode.Up, true)
R.run(0.6)
T.key(Enum.KeyCode.Up, false)
local p1 = C.viewById(e.id).hullF:PointToObjectSpace(cam.CFrame.Position)
check(C.interiorState().mode == "free" and (p1 - p0).Magnitude > 1, string.format("导演镜头挪动了 %.1f 格", (p1 - p0).Magnitude))
T.tap(Enum.KeyCode.U)
R.run(0.1)
local pg = me.PlayerGui
local en = 0
for _, g in ipairs(pg:GetChildren()) do if g:IsA("ScreenGui") and g.Enabled then en = en + 1 end end
check(en == 0, "U：界面全藏起来（还开着 " .. en .. " 个）")
T.tap(Enum.KeyCode.U)
R.run(0.1)
en = 0
for _, g in ipairs(pg:GetChildren()) do if g:IsA("ScreenGui") and g.Enabled then en = en + 1 end end
check(en > 3, "再按 U：界面回来了（" .. en .. " 个）")
T.tap(Enum.KeyCode.B)
R.run(0.2)
check(C.interiorState().mode == "seat", "B：回到乘员位")
print("⑤½ 屏幕边的按键：指示（猎-歼）、熄火 / 起动、换页")
local function keyOf(label)
  for _, k in ipairs(C.interiorState().cur.b.softkeys) do if k.label == label then return k end end
end
local function press(label)
  local k = keyOf(label)
  if not k or not k.screen.onKey then return false end
  R.as("client", function() k.screen.onKey(label, C.interiorState().cur.env.act) end)
  R.run(0.3)
  return true
end
local nKeys = #C.interiorState().cur.b.softkeys
check(nKeys >= 20, "屏幕边有 " .. nKeys .. " 个带字的按键")
local desig = (VEH == "m1a2") and "DESIG" or "指示"
-- 先坐到炮长位，把热像仪手动转到左前 40°（不在车长位时停在上次的方向）
T.tap(KEYS.gunner)
R.run(0.2)
local cur5 = C.interiorState().cur
cur5.citvMode = "MAN"
cur5.citvMan = R.Vector3.new(-math.sin(math.rad(40)), 0, -math.cos(math.rad(40)))
cur5.b.screens[1].nextT = 0
R.run(0.6)
local aim0 = C.drive.aimPt
local ty0 = C.drive.ty
if press(desig) then
  R.run(2)
  check(C.drive.aimPt ~= aim0 and math.abs(((C.drive.ty - ty0 + 180) % 360) - 180) > 0.5, string.format("按「%s」：炮塔转向热像仪看的方向（%.0f° → %.0f°）", desig, ty0, C.drive.ty))
else check(false, "找到「" .. desig .. "」键") end
local off = (VEH == "m1a2") and "SHUT OFF" or "熄火"
local on = (VEH == "m1a2") and "PUSH TO START" or "起动"
press(off)
check(C.interiorEngineOff == true, "按「" .. off .. "」：发动机熄火")
T.key(Enum.KeyCode.W, true)
local p0e = C.drive.pos
R.run(1)
T.key(Enum.KeyCode.W, false)
check((C.drive.pos - p0e).Magnitude < 1, string.format("熄火了按 W 开不动（挪了 %.1f 格）", (C.drive.pos - p0e).Magnitude))
press(on)
check(C.interiorEngineOff == false, "按「" .. on .. "」：起动")
print("⑤¾ 各乘员位的观瞄设备：Shift 主镜、G 备用镜、T 第三个")
local KEYS2 = { primary = Enum.KeyCode.LeftShift, alt = Enum.KeyCode.G, third = Enum.KeyCode.T }
for _, name in ipairs(C.interiorState().cur.spec.order) do
  T.tap(KEYS[name])
  R.run(0.3)
  local sp = C.interiorState().cur.spec.stations[name]
  for _, slot in ipairs({ "primary", "alt", "third" }) do
    local o = sp.optics and sp.optics[slot]
    if o then
      T.tap(KEYS2[slot])
      R.run(0.6)
      if o.kind == "gps" then
        check(C.drive.sight == true, string.format("%s 的%s：主瞄准镜（头先凑过去再进镜）", name, slot))
        T.tap(KEYS2[slot] == Enum.KeyCode.LeftShift and Enum.KeyCode.LeftShift or KEYS2[slot])
        R.run(0.6)
        check(not C.drive.sight, "  退出主瞄准镜")
      else
        local op = C.interiorOpticState()
        check(op ~= nil and op.o.kind == o.kind and C.interiorOptic == o.kind, string.format("%s 的%s：%s（%s）", name, slot, o.name or o.kind, op and op.o.kind or "没开"))
        if o.useSight then check(C.drive.sight == true, "  辅助瞄准镜：炮跟着鼠标瞄（瞄准镜状态开着）") end
        T.tap(KEYS2[slot])
        R.run(0.4)
        check(C.interiorOpticState() == nil and C.interiorOptic == nil and not C.drive.sight, "  再按一次退出")
      end
    end
  end
end
T.tap(KEYS[C.interiorState().cur.spec.order[1]])
R.run(0.2)
local mapK = (VEH == "m1a2") and "STAT" or "态势"
check(press(mapK), "地图换到本车状态页（" .. mapK .. "）")
if dumpDir then dumpJSON(dumpDir .. "/interior_" .. VEH .. ".json") end

print("⑥ 回车外、下车")
for _ = 1, 6 do
  if not C.interiorOn() then break end
  T.tap(Enum.KeyCode.C)
  R.run(0.2)
end
check(not C.interiorOn() and (C.interiorState().cur == nil or C.interiorState().cur.model.Parent == nil), "C 换过最后一个乘员位：回到车外，内饰收起来")
-- T（车外）：直接坐到车长位、开他的主观瞄（用户 11-21：99A 模型上那个多边形的观瞄舱要能第一人称看出去；M1A2 是 CITV）；再按 T 回车外
T.tap(Enum.KeyCode.T)
R.run(0.6)
local qs, qo = C.interiorState(), C.interiorOpticState and C.interiorOpticState()
check(qs.mode == "seat" and qs.station == "commander" and qo ~= nil and qo.quick == true,
  string.format("车外按 T：坐到车长位、开了车长主镜（位置 %s，镜 %s）", tostring(qs.station), tostring(qo and qo.o and qo.o.name)))
T.tap(Enum.KeyCode.T)
R.run(0.4)
check(not C.interiorOn() and (C.interiorOpticState == nil or C.interiorOpticState() == nil), "再按 T：关镜、回到车外")
T.tap(Enum.KeyCode.F)
R.run(1)
check(C.drive == nil and C.interiorState().cur == nil, "下车：内饰拆掉")
check(#R.errors == 0, "全程没有报错：" .. table.concat(R.errors, " | "))
T.summary()
