-- 车内饰的真模型部件（用户 11-22 晚发来 M1A2 车长位照片：「图片里摇杆、计算机、屏幕……识别到了就去 Sketchfab 找类似的」）：
--   python3 tools/mock/run.py tools/mock/interior_props.lua [dump=<目录>]
--   ① 坐上 M1A2、进车内，等后台把真模型部件都生成好、内饰重建一次
--   ② 九件新部件都摆上了：带边键的显示控制单元（车长热像仪、炮长控制显示面板）、加固战术终端（指挥地图）、带侧键的显示器（CROWS）、
--      双握把、B-8 握杆、弹道计算机（车长握把下面的电子箱）、拨动开关面板、顶灯、弹箱
--   ③ 这四块屏是真模型外壳：显示面贴在原模型的玻璃前面（在外壳的包围盒里）、键帽盖在原模型的实体键上（也在包围盒里），键都能对准按
--   dump=<目录>：写 interior_m1a2_props.json（tools/mock/interior_view.cjs 画图，真模型部件按 models/optics 的 GLB 画）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local dumpDir = TEST_ARGS:match("dump=(%S+)")

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

print("① 坐上 M1A2、进车内，等真模型部件生成好")
local def = VD.get("m1a2")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 18, hp.Z + math.sin(a) * 18
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", "m1a2", G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 M1A2")
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
check(C.interiorOn() and C.interiorState().cur ~= nil, "按 C：坐进车里")
local NEW = { "ip_cdu", "ip_cdus", "ip_yoke", "ip_stick", "ip_asq2", "ip_sw", "ip_lamp", "ip_can" }
local waited = 0
T.runUntil(function()
  waited = waited + 1
  for _, k in ipairs(NEW) do if not C.opticReady(k) then return false end end
  local cur = C.interiorState().cur
  return cur ~= nil and cur.propsDone == true
end, 240)
local fails = {}
for _, k in ipairs(NEW) do if not C.opticReady(k) then table.insert(fails, k .. (C.opticFailed(k) and "（生成失败）" or "（还没好）")) end end
check(#fails == 0, "新部件都生成好了" .. (#fails > 0 and ("：没好的 " .. table.concat(fails, "、")) or ""))
R.run(1)

print("② 都摆上了")
local cur = C.interiorState().cur
local byKey = {}
for _, p in ipairs(cur.model:GetDescendants()) do
  local k = p:IsA("BasePart") and string.match(p.Name, "^O_(.-)__")
  if k then byKey[k] = (byKey[k] or 0) + 1 end
end
local WANT = { ip_cdu = 2, ip_cdus = 1, ip_yoke = 1, ip_stick = 1, ip_asq2 = 1, ip_sw = 4, ip_lamp = 3, ip_can = 4 }
local META = R.require(R.services.ReplicatedStorage:FindFirstChild("OpticsMeta"))
for _, k in ipairs(NEW) do
  local nParts = 0
  for _ in pairs(META[k].parts) do nParts = nParts + 1 end
  local n = math.floor((byKey[k] or 0) / nParts + 0.5)
  check(n == WANT[k], string.format("%s 摆了 %d 件（要 %d 件；%s）", k, n, WANT[k], META[k].credit and string.match(META[k].credit, "^([^：]+)") or "本项目照截图做的"))
end

print("③ 真模型外壳的屏幕：显示面、键帽在外壳里")
local hull = cur.b.groups.turret.world
local function boxOf(key, near)   -- near 附近那一件这种模型（所有块的包围盒并起来，炮塔坐标、格）
  local best, bd = nil, math.huge
  local groups = {}
  for _, p in ipairs(cur.model:GetDescendants()) do
    if p:IsA("BasePart") and string.match(p.Name, "^O_" .. key .. "__") then
      local q = hull:PointToObjectSpace(p.Position)
      local d = (q - near).Magnitude
      if d < 2.5 then table.insert(groups, p) end
      if d < bd then best, bd = p, d end
    end
  end
  local mn, mx = V3(1e9, 1e9, 1e9), V3(-1e9, -1e9, -1e9)
  for _, p in ipairs(groups) do
    local cf = hull:ToObjectSpace(p.CFrame)
    local s = p.Size * 0.5
    for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
      local w = cf * V3(sx * s.X, sy * s.Y, sz * s.Z)
      mn = V3(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
      mx = V3(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
    end end end
  end
  return best ~= nil, mn, mx
end
local function inBox(p, mn, mx, pad)
  return p.X > mn.X - pad and p.X < mx.X + pad and p.Y > mn.Y - pad and p.Y < mx.Y + pad and p.Z > mn.Z - pad and p.Z < mx.Z + pad
end
-- 车长显示单元（用户 11-23 钢铁猛兽截图）：上屏 CITV 左边 5 个 + 两屏之间 10 个键，下屏地图 VEH SYS、C3 + 4 个方向键 + 8 个横杠键 + 16 个键盘键
local SHELL = { gcdp = "ip_cdu", citv = "ip_cdus", cid = "ip_cdus", crows = "ip_cdu" }
local KEYN = { citv = 15, cid = 30 }
for page, key in pairs(SHELL) do
  local s
  for _, x in ipairs(cur.b.screens) do if x.page == page then s = x end end
  check(s ~= nil and s.opt and s.opt.propShell == true, page .. "：屏幕是真模型外壳（" .. key .. "）")
  if s then
    local c = hull:PointToObjectSpace(s.part.Position)
    local ok, mn, mx = boxOf(key, c)
    check(ok and inBox(c, mn, mx, 0.05), string.format("  显示面在外壳里（%.2f, %.2f, %.2f）", c.X, c.Y, c.Z))
    local nk, nin = 0, 0
    for _, k in ipairs(cur.b.softkeys) do
      if k.screen == s then
        nk = nk + 1
        if inBox(hull:PointToObjectSpace(k.part.Position), mn, mx, 0.06) then nin = nin + 1 end
      end
    end
    local want = KEYN[page] or (#(s.opt.keys.top or {}) + #(s.opt.keys.bottom or {}))
    check(nk == want and nin == nk, string.format("  %d 个键帽都盖在外壳的实体键上（在外壳里的 %d 个）", nk, nin))
  end
end
-- 对准一个键帽按下去：屏幕翻页（CITV 的 NFOV：窄视场）
T.tap(Enum.KeyCode.F4)
R.run(0.3)
local function press(label)
  for _, k in ipairs(cur.b.softkeys) do
    if k.label == label and k.screen and k.screen.onKey then return (pcall(k.screen.onKey, label, cur.env.act)) end
  end
  return false
end
check(press("NFOV"), "车长热像仪显示器上的 NFOV 键按得动")
-- 车长面前两块屏上下连一体（用户 11-23）：热像仪在上、指挥地图在下，同一个朝向、左右对齐，上下贴着
do
  local sU, sL
  for _, x in ipairs(cur.b.screens) do if x.page == "citv" then sU = x elseif x.page == "cid" then sL = x end end
  if sU and sL then
    local a, c = sU.part.CFrame, sL.part.CFrame
    local rel = a:ToObjectSpace(c)
    local same = a.LookVector:Dot(c.LookVector) > 0.999
    check(same and math.abs(rel.X) < 0.15 and rel.Y < -0.3 and rel.Y > -0.8 and math.abs(rel.Z) < 0.02,
      string.format("车长两块屏上下连一体：同一个朝向（%s）、下面那块在正下方 %.2f 格（左右差 %.3f、前后差 %.3f）", tostring(same), -rel.Y, rel.X, rel.Z))
  else
    check(false, "车长的热像仪屏、指挥地图屏都在")
  end
end
print("④ 车长显示单元的键：键盘打坐标设目标点、字母发消息、方向键挪地图；上屏选中的键亮灯、扫描扇区、收回")
do
  local sU, sL
  for _, x in ipairs(cur.b.screens) do if x.page == "citv" then sU = x elseif x.page == "cid" then sL = x end end
  local function pressOn(scr, label)
    for _, k in ipairs(cur.b.softkeys) do
      if k.label == label and k.screen == scr then return (pcall(scr.onKey, label, cur.env.act)) end
    end
    return false
  end
  R.run(0.6)
  local ms = sL and sL.mapState
  check(ms ~= nil, "下屏地图页有状态")
  if ms then
    local p = cur.b.groups.hull.world.Position
    local gx, gz = math.floor((p.X + 20000) / 2.8) % 100000, math.floor((20000 - p.Z) / 2.8) % 100000
    local dg = string.format("%05d%05d", gx, gz)
    for i = 1, #dg do pressOn(sL, string.sub(dg, i, i)) end
    check(ms.entry == dg, "键盘打了本车坐标 " .. tostring(ms.entry))
    pressOn(sL, "ENT")
    check(ms.wp ~= nil and math.abs(ms.wp.x - p.X) < 4 and math.abs(ms.wp.z - p.Z) < 4,
      string.format("ENT：目标点设在本车这里（差 %.1f、%.1f 格）", ms.wp and ms.wp.x - p.X or -1, ms.wp and ms.wp.z - p.Z or -1))
    pressOn(sL, "LTR")
    pressOn(sL, "3") pressOn(sL, "3") pressOn(sL, "NEXT") pressOn(sL, "3") pressOn(sL, "3") pressOn(sL, "3")
    check(ms.entry == "HI", "字母模式：3 连按两下 H、> 结束、再连按三下 I（" .. tostring(ms.entry) .. "）")
    pressOn(sL, "ENT")
    check(ms.sent[1] and ms.sent[1].txt == "HI" and ms.page == "MSG", "ENT：消息发出去了，翻到消息页")
    pressOn(sL, "UP") pressOn(sL, "RIGHT")
    check(ms.pan[2] < 0 and ms.pan[1] > 0 and ms.page == "MAP", "方向键：地图往北、往东挪了")
    pressOn(sL, "MAP")
    check(ms.pan[1] == 0 and ms.pan[2] == 0, "MAP 键：回到本车")
    pressOn(sL, "CLR")
    check(ms.wp == nil, "CLR（没字时）：清掉目标点")
    R.run(0.5)
  end
  local led = {}
  for _, l in ipairs(cur.b.leds) do if l.role == "key" and l.s == sU then led[l.k] = l end end
  pressOn(sU, "WFOV")
  R.run(0.3)
  check(led.WFOV and led.NFOV and led._PWR and sU.ledOn("WFOV") and not sU.ledOn("NFOV") and led.WFOV.p.Color == led.WFOV.on, "上屏键角上的绿灯：按 WFOV，宽视场的灯亮")
  pressOn(sU, "NFOV")
  R.run(0.3)
  check(sU.ledOn("NFOV") and not sU.ledOn("WFOV") and led.NFOV.p.Color == led.NFOV.on, "按 NFOV：窄视场的灯亮了、宽视场的灭了")
  pressOn(sU, "AUTO")
  R.run(0.3)
  local c = C.interiorState().cur
  local rel0 = c.data.citvRel or 0
  pressOn(sU, "SCAN L")
  check(c.citvSec and math.abs(c.citvSec[1] - math.min(rel0, 60)) < 30, "SCAN L：扫描扇区左边设好了")
  pressOn(sU, "STOW")
  R.run(0.4)
  check(math.abs(c.data.citvRel or 99) < 1, string.format("STOW：热像仪收回朝炮塔正前（%.1f°）", c.data.citvRel or 99))
  pressOn(sU, "MAN") pressOn(sU, "WFOV")
end
check(#R.errors == 0, "全程没有报错：" .. table.concat(R.errors, " | "))
if dumpDir then
  -- 预览图的镜头：每块真模型外壳的屏幕正前方 0.55 米、炮长看双握把、车长看右手边的电子箱和握杆
  local cams = {}
  local S = 2.8
  for _, x in ipairs(cur.b.screens) do
    if x.opt and x.opt.propShell then
      local f = x.part.CFrame
      local eye = (f * T.CF(0, 0.05 * S, -0.55 * S)).Position
      cams["scr_" .. x.page] = R.CFrame.lookAt(eye, f.Position)
    end
  end
  local tw = cur.b.groups.turret.world
  local function at(a, b2) return R.CFrame.lookAt((tw * T.CF(a[1] * S, a[2] * S, a[3] * S)).Position, (tw * T.CF(b2[1] * S, b2[2] * S, b2[3] * S)).Position) end
  cams.gunner_grips = at({ 0.90, 0.22, -0.42 }, { 0.55, -0.02, -0.74 })
  cams.cmdr_right = at({ 0.45, 0.45, 0.25 }, { 0.92, -0.05, -0.12 })
  cams.cmdr_front = at({ 0.56, 0.62, 0.15 }, { 0.62, 0.35, -0.40 })
  cams.cmdr_eye = at({ 0.56, 0.60, 0.02 }, { 0.82, 0.38, -0.36 })
  cams.cmdr_cdu = at({ 0.62, 0.58, -0.04 }, { 0.80, 0.39, -0.46 })
  cams.cmdr_up = at({ 0.56, 0.60, 0.06 }, { 0.57, 1.05, 0.40 })   -- 车长位往上看：八边形指挥塔（用户 11-23）
  cams.gunner_eye = at({ 0.54, 0.36, -0.60 }, { 0.72, 0.02, -0.84 })
  cams.loader_cans = at({ -0.35, 0.10, -0.20 }, { -0.95, -0.55, -0.70 })
  local dumpOut = dofile(MOCK_DIR .. "/interior_dump.lua")
  local v = C.viewById(e.id)
  dumpOut(cur, v.hullF, cams, dumpDir .. "/interior_m1a2_props.json", R.workspace.CurrentCamera, Enum)
end
T.summary()
