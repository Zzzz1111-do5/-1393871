-- 坦克炮长瞄准镜（Client/GunSight.lua + ReplicatedStorage/SightDefs.lua）、车长望远镜——用户 11-27：「坦克的开镜你直接去按照战雷的做」+ 截图「这个样子」、
--   「然后再做一个望远镜」；11-26：「照真镜子重画」（白天黑色细线、上方各弹种表尺 + 指示线、两边每格 4 密位、左下 2.7 米测距曲线、按密位随倍率缩放）
--   python3 tools/mock/run.py tools/mock/gunsight.lua [shot=<目录>]（shot：各画面的界面写成 JSON，tools/mock/hud_render.py 画图）
--   ① 59 式白天开镜：苏式 TSh 分划（全屏、黑线）、竖线左边这一发弹的表尺（按真弹道）、上方各弹种表尺、测距曲线、方位刻度
--   ② 分划按密位随倍率缩放：3.5 → 7 倍，横线上「16」的位置跟着放大（按 tan 算）
--   ③ PageUp / PageDown：装定每次 100 米，表尺跟着挪（「12」在中心）；拨到 0 全在中心下面（截图那样），左边写「表尺 … 米」
--   ④ 镜头一下转过去、炮塔追不上：炮管指向的小十字偏在一边，炮塔转过来以后回到中心
--   ⑤ 弹药栏、左下损伤图在镜里也画；烟幕那格写 M、望远镜那格写 C
--   ⑥ 望远镜：C 打开（8 倍、两个圆、密位刻度）、R 车长估距（打到前面 500 米那辆车）、C 收起；望远镜里 Shift 直接进炮长瞄准镜
--   ⑦ T-90M（数字火控）：sovmod 分划、镜下写 BS 距离和弹种
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local SHOT = TEST_ARGS:match("shot=(%S+)")

local G = T.boot()
R.services.Workspace:SetAttribute("DayFix", 12.5)   -- 正午（钟点）：白天的光学通道（黑线分划）
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.allowInfantry = true
T.runUntil(function() return G.worldReady end, 900)
if G.botsClear then G.botsClear() end
local me = T.join("P1", 8311, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
R.services.Workspace:SetAttribute("DayFix", 12.5)
R.run(0.5)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
check(P.alive, "出生了")
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local SD = R.require(RS:FindFirstChild("SightDefs"))
local BAL = R.require(RS:FindFirstChild("Ballistics"))
local Map = G.Map
local cam = R.services.Workspace.CurrentCamera

local function find(name, root)
  for _, d in ipairs((root or me.PlayerGui):GetDescendants()) do
    if d.Name == name then return d end
  end
end
local function shown(f) return f ~= nil and T.visible(f) end
local function visibleKids(root, name)
  local n = 0
  if root then for _, f in ipairs(root:GetChildren()) do if f.Name == name and f.Visible then n = n + 1 end end end
  return n
end
-- 分划画布里写着 text 的字（ax：0 左对齐 / 0.5 居中 / 1 右对齐）
local function retText(text, ax)
  local rc = find("Reticle")
  for _, t in ipairs(rc and rc:GetChildren() or {}) do
    if t.Name == "T" and t.Visible and t.Text == text and (ax == nil or math.abs(t.AnchorPoint.X - ax) < 0.01) then return t end
  end
end

-- 车放在离人不远的平地上，前方 500 米再放一辆靶车（望远镜估距打它）
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local home = hrp and hrp.Position or V3(0, 0, 0)
local function flatAt(x, z) return Map.isLand(x, z) and Map.height(x, z) > 2 and Map.slope(x, z) < 0.25 end
local spot
for _, rr in ipairs({ 30, 60, 120, 240, 400 }) do
  for k = 0, 23 do
    local a = k / 24 * math.pi * 2
    local x, z = home.X + math.cos(a) * rr, home.Z + math.sin(a) * rr
    if flatAt(x, z) and flatAt(x + 12, z) then spot = { x = x, z = z } break end
  end
  if spot then break end
end
check(spot ~= nil, "找到放车的平地")
if not spot then T.summary() return end

local function mount(vid)
  local def = VD.get(vid)
  local e = G.newVehicle("def", vid, G.vehBaseAt(def, spot.x, spot.z, V3(0, 0, -1)))
  R.run(0.5)
  local h2 = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
  if h2 then h2.CFrame = CF(spot.x + 10, Map.height(spot.x + 10, spot.z) + 3, spot.z) end
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(1)
  return e
end
local function dismount(e)
  T.remoteAs(me, "Drive", { op = "exit" })
  R.run(1)
  if e.model then G.removeEnt(e) end
  R.run(0.3)
end
local function settle(t) R.run(t or 1.2) end

print("① 59 式白天开镜（苏式 TSh 分划）")
local e = mount("type59")
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 59 式")
if not st then T.summary() return end
R.as("client", function() C.driveSetSight(true) end)
settle()
check(C.gunSightFamily == "tsh", "59 式是苏式 TSh 分划（" .. tostring(C.gunSightFamily) .. "）")
local rc = find("Reticle")
check(visibleKids(rc, "L") >= 40, string.format("分划画出来了（%d 根线）", visibleKids(rc, "L")))
local ln = nil
for _, f in ipairs(rc and rc:GetChildren() or {}) do if f.Name == "L" and f.Visible then ln = f break end end
check(ln ~= nil and ln.BackgroundColor3.R < 0.1 and ln.BackgroundColor3.G < 0.1, "白天：分划是黑线")
local eyeF = find("Eyepiece")
check(not shown(eyeF), "全屏开镜：没有圆形目镜")
local gs = C.gunSight
local am = BAL.AMMO[st.fcs.am]
check(am ~= nil and gs.lastLadder ~= nil and #gs.lastLadder >= 10, string.format("表尺按这一发弹（%s）画了 %d 格", tostring(st.fcs.am), gs.lastLadder and #gs.lastLadder or 0))
check(gs.lastTop ~= nil and #gs.lastTop.cols >= 2, "上方各弹种表尺（" .. (gs.lastTop and #gs.lastTop.cols or 0) .. " 列）")
-- 表尺上「16」的位置：按真弹道（比装定的距离多抬几密位）换成像素
local function geomNow() return gs.geom(cam.FieldOfView, 6000) end
local R0 = st.fcs.R or (am and am.bs) or 1000
local function ladderY(r)
  for _, it in ipairs(SD.ladder(BAL, am, R0, 6000)) do if it.r == r then return it.y end end
end
local t16 = retText("16", 1)
local y16 = ladderY(1600)
check(t16 ~= nil and y16 ~= nil and math.abs(t16.Position.Y.Offset - geomNow().m(y16)) <= 1.5,
  string.format("表尺「16」在按弹道算的位置（%s 像素，算的 %.1f）", t16 and tostring(t16.Position.Y.Offset) or "-", y16 and geomNow().m(y16) or -1))
check(shown(find("Tape")) and visibleKids(find("Tape"), "L") >= 8 and visibleKids(find("Tape"), "T") >= 1, "顶上有方位刻度")
-- 光学感（用户 11-27「没有3a游戏的感觉」）：四角暗角一圈圈细环、进镜对焦的模糊放完撤掉
local nVig = 0
for _, f in ipairs(find("GunSight") and find("GunSight"):GetChildren() or {}) do if f.Name == "Vig" and f.Visible then nVig = nVig + 1 end end
check(nVig >= 16, "炮长镜四角暗角（" .. nVig .. " 圈细环）")
local focusB = R.services.Lighting:FindFirstChild("SightFocus")
check(focusB ~= nil and (not focusB.Enabled or focusB.Size < 0.1), "进镜对焦放完：模糊撤掉（" .. tostring(focusB and focusB.Size) .. "）")
if SHOT then dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/gunsight_type59.json", true) end

print("② 分划按密位随倍率缩放")
local function lat16()
  local rc2 = find("Reticle")
  for _, t in ipairs(rc2 and rc2:GetChildren() or {}) do
    if t.Name == "T" and t.Visible and t.Text == "16" and math.abs(t.AnchorPoint.X - 0.5) < 0.01 and t.Position.X.Offset > 0 then return t.Position.X.Offset end
  end
end
R.as("client", function() C.driveZoomStep(1) end)
settle(1.5)
local fov1, x1 = cam.FieldOfView, lat16()
R.as("client", function() C.driveZoomStep(2) end)
settle(1.5)
local fov2, x2 = cam.FieldOfView, lat16()
local want = (x1 or 0) * math.tan(math.rad(fov1) / 2) / math.tan(math.rad(fov2) / 2)
check(x1 ~= nil and x2 ~= nil and fov2 < fov1 and math.abs(x2 - want) <= 2,
  string.format("换倍率（视场 %.1f° → %.1f°）横线上「16」从 %s 挪到 %s 像素（按 tan 算 %.1f）", fov1, fov2, tostring(x1), tostring(x2), want))

print("③ PageUp / PageDown 装定表尺")
local before = st.fcs.R or (am and am.bs) or 0
T.tap(Enum.KeyCode.PageUp)
settle(0.3)
check(st.fcs.R == math.floor(before / 100 + 0.5) * 100 + 100 and st.fcs.man == true, string.format("PageUp：装定 %s → %s 米（手动）", tostring(before), tostring(st.fcs.R)))
check(#T.texts(C.T("gs.sightSet", st.fcs.R)) > 0, "左边写着「" .. C.T("gs.sightSet", st.fcs.R) .. "」")
for _ = 1, 50 do T.tap(Enum.KeyCode.PageDown) end
settle(0.3)
check(st.fcs.R == 0, "一直按 PageDown：拨到 0 米")
local allBelow = true
for _, it in ipairs(gs.lastLadder or {}) do if it.y <= 0 then allBelow = false end end
check(allBelow and #(gs.lastLadder or {}) > 0, "装定 0：表尺刻度全在中心下面（截图那样）")
if SHOT then dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/gunsight_type59_r0.json", true) end
R.as("client", function() C.driveSightRange(1) end)
for _ = 1, 11 do R.as("client", function() C.driveSightRange(1) end) end
settle(0.3)
check(st.fcs.R == 1200, "拨到 1200 米")
local c12 = nil
for _, it in ipairs(gs.lastLadder or {}) do if it.r == 1200 then c12 = it.y end end
check(c12 ~= nil and math.abs(c12) < 0.05, string.format("装定 1200：「12」在中心（%.3f 密位）", c12 or 99))
if SHOT then dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/gunsight_type59_r1200.json", true) end

print("④ 炮管指向的小十字")
local dyn = find("Dyn")
R.as("client", function() st.camYaw, st.camPitch = st.camYaw + 0.5, -0.01 end)   -- 平着看（59 式炮只能压低 5°，往下看太多炮管够不着，小十字本来就该偏着）
R.run(0.15)
local lagN = visibleKids(dyn, "L")
check(lagN >= 4, "镜头转过去、炮塔还没跟上：小十字偏在一边（" .. lagN .. " 根线）")
settle(5)
check(visibleKids(dyn, "L") == 0, "炮塔转过来以后小十字回到中心（不画）")

print("⑤ 镜里的弹药栏、损伤图")
local wt = me.PlayerGui:FindFirstChild("WtTank")
check(wt ~= nil and wt.Enabled, "开着镜也画战雷式弹药栏、损伤图（WtTank）")
local keys = {}
for _, d in ipairs(wt and wt:GetDescendants() or {}) do
  if d.ClassName == "TextLabel" and T.visible(d) then keys[d.Text] = true end
end
check(keys.M == true, "烟幕那格写 M（11-25 起烟幕是 M、X 是透视）")
check(keys.C == true, "弹药栏里有望远镜那格（C）")
check(shown(find("WtDamageInd")), "左下损伤图（档位、车速）在镜里也画")

print("⑥ 车长望远镜")
R.as("client", function() C.driveSetSight(false) end)
settle(0.5)
-- 靶车：500 米外、中间没东西挡着的方向（主基地里房子多：先打射线挑一个看得见的方向）
local tdef = VD.get("t72b3")
local gh0 = C.driveGunHit and C.driveGunHit()
local o0 = (gh0 and gh0.o) or cam.CFrame.Position   -- 从炮口看得见（炮比车长的眼睛低，按炮挑方向）
-- 地面有起伏：贴地 4 格高的射线 1400 格远常被小坡挡住——几个距离（360～610 米）× 72 个方向挨个试，估距按实际距离比
local tp, tdist = nil, nil
local nTry = 0
-- 射线不算自己这辆车、自己的人（炮口点在炮管里，镜头在车后上方：不排除的话每一条都先打在自己车上）
local rpOwn = R.RaycastParams.new()
rpOwn.FilterDescendantsInstances = { e.model, me.Character }
local why = {}
-- 从车头正前方（-Z，车是朝 -Z 摆的）开始，左右交替往两边找：炮塔不用转半圈（59 式转一圈要二十多秒）
for _, rr in ipairs({ 1400, 1260, 1540, 1120, 1700 }) do
  for k = 0, 71 do
    local a = math.pi + (k % 2 == 0 and 1 or -1) * math.floor((k + 1) / 2) * (math.pi / 36)
    local x, z = spot.x + math.sin(a) * rr, spot.z + math.cos(a) * rr
    if Map.isLand(x, z) and Map.slope(x, z) < 0.3 then
      nTry = nTry + 1
      local p = V3(x, Map.height(x, z) + 3, z)
      local hit = R.services.Workspace:Raycast(o0, (p - o0) * 0.98, rpOwn)
      local hitC = R.services.Workspace:Raycast(cam.CFrame.Position, (p - cam.CFrame.Position) * 0.98, rpOwn)
      if not hit and not hitC then tp, tdist = p, rr / 2.8 break end
      local h = hit or hitC
      local nm = h and h.Instance and h.Instance:GetFullName() or "?"
      why[nm] = (why[nm] or 0) + 1
    end
  end
  if tp then break end
end
check(tp ~= nil, string.format("找到 360～610 米外看得见的地方放靶车（试了 %d 处平地）", nTry))
if not tp then
  local top = {}
  for k, v in pairs(why) do top[#top + 1] = { k, v } end
  table.sort(top, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(6, #top) do print(string.format("    挡住：%s × %d", top[i][1], top[i][2])) end
end
if not tp then T.summary() return end
local tgt = G.newVehicle("atk", "t72b3", G.vehBaseAt(tdef, tp.X, tp.Z, (V3(spot.x, 0, spot.z) - V3(tp.X, 0, tp.Z)).Unit))
tgt.noScore = true
R.run(0.5)
T.tap(Enum.KeyCode.C)
settle(1.5)
check(st.binoc == true and shown(find("Binoculars")), "C：打开车长望远镜")
check(math.abs(cam.FieldOfView - 70 / SD.BINOC.mag) < 0.3, string.format("望远镜 %d 倍（视场 %.2f°）", SD.BINOC.mag, cam.FieldOfView))
check(visibleKids(find("BinoRet"), "L") >= 20, "望远镜的密位刻度（" .. visibleKids(find("BinoRet"), "L") .. " 根线）")
-- 「望远镜没有渐变啊」：每只镜筒里一圈圈细环叠成的边缘渐暗、色散、镀膜反光；举起来的模糊放完只剩转动时那一点
local nSoft = 0
for _, side in ipairs({ "ClipL", "ClipR" }) do
  local c = find(side)
  for _, f in ipairs(c and c:GetChildren() or {}) do if f.Name == "Soft" then nSoft = nSoft + 1 end end
end
check(nSoft >= 40, "两只镜筒的边缘渐暗（" .. nSoft .. " 圈细环）")
check(find("FringeW") ~= nil and find("Glare") ~= nil, "镜片边上的色散、镀膜反光")
local bb = R.services.Lighting:FindFirstChild("BinoBlur")
check(bb ~= nil and bb.Enabled and bb.Size < 1, "举起来的对焦放完了（模糊 " .. tostring(bb and bb.Size) .. "）")
check(not st.sight, "望远镜不是炮长瞄准镜")
-- 对准靶车：镜头从车长的位置看靶车中心
R.as("client", function()
  local dv = (tgt.root.CFrame.Position + V3(0, 1, 0)) - cam.CFrame.Position
  st.camYaw = math.atan(-dv.X, -dv.Z)
  st.camPitch = math.atan(dv.Y, math.sqrt(dv.X * dv.X + dv.Z * dv.Z))
end)
settle(0.5)
do   -- 镜头到靶车之间挡着什么（调试）
  local o = cam.CFrame.Position
  local dv = (tgt.root.CFrame.Position + V3(0, 1, 0)) - o
  local hit = R.services.Workspace:Raycast(o, dv * 1.05)
  print(string.format("    镜头到靶车 %.0f 米；射线打到 %s（%.0f 米）；aimPt %.0f 米", dv.Magnitude / 2.8, hit and hit.Instance and hit.Instance:GetFullName() or "nil",
    hit and (hit.Position - o).Magnitude / 2.8 or -1, st.aimPt and (st.aimPt - o).Magnitude / 2.8 or -1))
end
st.fcs.R = nil
T.tap(Enum.KeyCode.R)
R.run(0.3)
check(st.fcs.estimating == true, "R：车长估距中")
settle(2.5)
check(st.fcs.R ~= nil and math.abs(st.fcs.R - tdist) <= tdist * 0.12, string.format("估出来 %s 米（靶车 %.0f 米，差 12%% 以内）", tostring(st.fcs.R), tdist))
local bi = find("BinoInfo")
check(bi ~= nil and bi.Text:find("≈", 1, true) ~= nil, "望远镜下面写着估的距离：" .. tostring(bi and bi.Text))
if SHOT then dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/gunsight_binoc.json", true) end
T.tap(Enum.KeyCode.C)
settle(0.5)
check(st.binoc ~= true and not shown(find("Binoculars")), "再按 C：收起望远镜")
check(not (bb and bb.Enabled), "收起望远镜：模糊、镀膜调色撤掉")
T.tap(Enum.KeyCode.C)
settle(0.5)
R.as("client", function() C.driveSetSight(true) end)
settle(0.5)
check(st.sight == true and st.binoc ~= true and not shown(find("Binoculars")), "望远镜里进炮长瞄准镜：望远镜收起")
R.as("client", function() C.driveSetSight(false) end)
settle(0.3)

print("⑧ 第三人称：炮管标记在真落点、炮口被挡画叉")
-- 车外瞄着 500 米外的靶车：炮塔转过去以后，这一发的落点（Drive gunImpact）打在靶车上（原来顺着带超高角的炮管直线放，远处比车顶还高）
local function aimAt(p)
  R.as("client", function()
    local o = cam.CFrame.Position
    local dv = p - o
    st.camYaw = math.atan(-dv.X, -dv.Z)
    st.camPitch = math.atan(dv.Y, math.sqrt(dv.X * dv.X + dv.Z * dv.Z))
  end)
end
-- 等炮塔转过来（最多 20 秒）：标记打到靶车上就停
local function underTgt(inst)
  local q = inst
  while q and q ~= R.services.Workspace do if q == tgt.model then return true end q = q.Parent end
  return false
end
for _ = 1, 200 do
  aimAt(tgt.root.CFrame.Position + V3(0, 1, 0))
  R.run(0.1)
  local g = C.driveGunHit and C.driveGunHit()
  if g and g.inst and underTgt(g.inst) then break end
end
R.run(0.3)
local gh = C.driveGunHit and C.driveGunHit()
if C.driveGunErr then print("    gunImpact 出错：" .. tostring(C.driveGunErr)) end
local onTgt = gh ~= nil and gh.inst ~= nil and underTgt(gh.inst)
check(gh ~= nil and onTgt, string.format("炮管标记打在靶车上（落点 %s 米、打到 %s）", gh and string.format("%.0f", gh.R) or "-", gh and gh.inst and gh.inst:GetFullName() or "nil"))
check(gh ~= nil and gh.blocked == false, "没有被挡")
-- 炮口前面一道矮墙，还瞄着靶车：炮口被挡
-- 一道矮墙（真「炮口被挡」的样子：车后上方的镜头越过墙看得见靶车，低处的炮管打在墙上）：中心在炮口前 40 格、高 8 格
local wall = R.Instance.new("Part")
wall.Anchored = true
wall.Size = V3(40, 8, 40)
o0 = gh and gh.o or cam.CFrame.Position
local fl = V3((tgt.root.CFrame.Position - o0).X, 0, (tgt.root.CFrame.Position - o0).Z).Unit
local wp = o0 + fl * 40
wall.CFrame = CF(V3(wp.X, Map.height(wp.X, wp.Z) + 4, wp.Z))
wall.Parent = R.services.Workspace
for _ = 1, 10 do aimAt(tgt.root.CFrame.Position + V3(0, 1, 0)) R.run(0.1) end
gh = C.driveGunHit and C.driveGunHit()
check(gh ~= nil and gh.blocked == true, string.format("墙挡着炮口：标记画叉（落点 %s 米）", gh and string.format("%.1f", gh.R) or "-"))
local blk = find("WtGunBlocked")
check(shown(blk), "准星圈里画了叉（WtGunBlocked）")
wall:Destroy()
R.run(0.5)
G.removeEnt(tgt)
dismount(e)

print("⑦ T-90M：数字火控分划")
local e2 = mount("t90m")
st = C.drive
check(st ~= nil and P.vehicle == e2, "坐上了 T-90M")
if st then
  R.as("client", function() C.driveSetSight(true) end)
  settle()
  check(C.gunSightFamily == "sovmod", "T-90M 是数字火控分划（" .. tostring(C.gunSightFamily) .. "）")
  local rg = find("GsRange")
  check(shown(rg) and rg.Text:match("^BS %d%d%d%d$") ~= nil, "镜下写战斗瞄准距离：" .. tostring(rg and rg.Text))
  check(shown(find("GsAmmo")) and find("GsAmmo").Text ~= "", "镜下写弹种：" .. tostring(find("GsAmmo") and find("GsAmmo").Text))
  check(gs.lastLadder == nil or not shown(retText("8", 1)), "数字火控没有下坠表尺（弹道计算机自动装定）")
  if SHOT then dofile(MOCK_DIR .. "/uidump.lua")(T, me, SHOT .. "/gunsight_t90m.json", true) end
  R.as("client", function() C.driveSetSight(false) end)
  settle(0.3)
  dismount(e2)
end
T.summary()
