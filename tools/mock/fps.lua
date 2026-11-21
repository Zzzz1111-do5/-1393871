-- 第一人称持枪测试（模拟器）：python3 tools/mock/run.py tools/mock/fps.lua [v]
--   主枪统一成 M4 → 出生后第一人称（镜头距离锁 0.5）→ 镜头前的 M4 和方块手臂 → 拔枪动作 → 开枪后坐、枪口火光、曳光从枪口出去 →
--   换弹播换弹动作 → 开镜（照门、准星对到屏幕正中）→ 换别的装备（手雷）用同一双手端着 → V 切到第三人称（视图模型收起）→
--   嵌在游戏里的真 M4（EditableMesh 生成）→ 导入的原模型优先
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7001, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
local C = T.C
-- 视图模型里跟某条轨道的第一个零件
local function itemOf(vm, track)
  for _, it in ipairs(vm and vm.items or {}) do if it[2] == track then return it end end
end

print("① 兵种、武器：主枪统一成 M4")
local guns = {}
for _, r in ipairs(G.Config.Roles) do
  for _, w in ipairs(r.weapons) do if G.Config.Weapons[w].kind == "gun" then guns[w] = true end end
end
local list = {}
for k in pairs(guns) do table.insert(list, k) end
table.sort(list)
check(#list == 2 and guns.m4 and guns.sniper, "只剩两种枪：" .. table.concat(list, "、"))
check(G.Config.RoleById.mg == nil and G.Config.RoleById.engineer ~= nil and G.Config.RoleById.sniper ~= nil, "机枪手并进步枪兵；工兵、狙击手等还在（" .. #G.Config.Roles .. " 种）")

print("② 出生：第一人称、镜头前的 M4 和方块手臂")
T.actAs(me, "deploy", "rifle", P.team == "atk" and "fleet" or "camp")
R.run(2.5)
check(P.alive and me.Character ~= nil, "出生了")
check(me.CameraMinZoomDistance == 0.5 and me.CameraMaxZoomDistance == 0.5, "第一人称（镜头距离锁 0.5）")
local vm = C.fps
check(vm ~= nil and vm.id == "m4", "镜头前有 M4：" .. tostring(vm and vm.id))
if vm then
  check(#vm.items >= 8, "M4 的零件：" .. #vm.items .. " 个")
  check(#vm.arms == 6, "方块手臂：上臂、小臂、手掌 × 2")
  local cam = R.workspace.CurrentCamera
  local vmModel = cam:FindFirstChild("FPSViewModel")
  check(vmModel ~= nil, "视图模型挂在镜头下（只有自己看得见）")
  -- 手臂在镜头前、屏幕下半部分
  local hand = vm.arms[3][1]
  local rel = cam.CFrame:PointToObjectSpace(hand.Position)
  check(rel.Z < 0.2 and rel.Y < 0, string.format("右手在镜头前下方（%.2f, %.2f, %.2f）", rel.X, rel.Y, rel.Z))
  local gi = itemOf(vm, "gun")
  local g = cam.CFrame:PointToObjectSpace((gi[1].CFrame * gi[3]:Inverse()).Position)   -- 枪身骨骼（握把上方的机匣那儿）
  check(g.Z < -0.2 and math.abs(g.X) < 1.5 and g.Y < 0.3, string.format("枪在正前方偏下（%.2f, %.2f, %.2f）", g.X, g.Y, g.Z))
  -- 方块形：手掌、胳膊都是长方块（Part，Block）
  check(hand.ClassName == "Part" and hand.Shape == Enum.PartType.Block, "手掌是方块")
  -- 第三人称那把枪藏起来
  local tool = me.Character:FindFirstChildOfClass("Tool")
  local anyShown = false
  if tool then for _, p in ipairs(tool:GetDescendants()) do if p:IsA("BasePart") and p.LocalTransparencyModifier < 1 and p.Transparency < 1 then anyShown = true end end end
  check(tool ~= nil and not anyShown, "手里那把（第三人称用的）在自己镜头里藏起来")
end

print("③ 拔枪动作、开枪后坐、换弹动作")
check(vm and (vm.act == nil or vm.act.clip ~= nil), "拔枪动作播过 / 在播")
T.runUntil(function() return G.round.phase == "battle" end, 40)
R.run(1.5)
print("  （等嵌在游戏里的真 M4 生成好）")
local genOk = T.runUntil(function()
  local v = C.fps
  return v ~= nil and itemOf(v, "gun") ~= nil and itemOf(v, "gun")[1].ClassName == "MeshPart"
end, 30)
check(genOk, string.format("枪换成了动作包里的真 M4（EditableMesh 生成 %d 块网格、%d 个三角形、%d 张贴图）", R.editStats.meshes, R.editStats.tris, R.editStats.images))
check(R.editStats.tris > 9000 and R.editStats.images >= 2, "网格、贴图都齐")
-- 瞄准镜、望远镜的真模型（Optics.lua，开局后台用 EditableMesh / EditableImage 生成：狙击镜 4 块、望远镜 1 块）
local opOk = T.runUntil(function() return C.opticReady and C.opticReady("acog") and C.opticReady("atacr") and C.opticReady("binoc") end, 30)
check(opOk, string.format("瞄准镜、望远镜的真模型也生成好了（这时一共 %d 块网格、%d 张贴图）", R.editStats.meshes, R.editStats.images))
vm = C.fps
local idleGun = vm and itemOf(vm, "gun")[1].CFrame
local shots0 = 0
local gunFx0 = C.gunFx
local fromMuzzle = false
C.gunFx = function(id, a, b, mine)
  shots0 = shots0 + 1
  if vm and vm.mzWorld and (a - vm.mzWorld).Magnitude < 0.01 then fromMuzzle = true end
  return gunFx0(id, a, b, mine)
end
T.mouse(true)
R.run(0.35)
T.mouse(false)
R.run(0.02)
check(shots0 >= 3, "按住左键连发：" .. shots0 .. " 发")
check(fromMuzzle, "曳光从镜头前那支枪的枪口出去")
if vm then
  local moved = (itemOf(vm, "gun")[1].CFrame.Position - idleGun.Position).Magnitude
  check(moved > 0.005, string.format("后坐：枪动了 %.3f 格", moved))
end
R.run(1)
C.gunFx = gunFx0
T.tap(Enum.KeyCode.R)
R.run(0.3)
check(vm and vm.act and (vm.act.clip == nil or true) and vm.act ~= nil, "按 R 播换弹动作")
local mag = vm and itemOf(vm, "mag1") and itemOf(vm, "mag1")[1]
local m0 = mag and mag.Position
R.run(1.0)
check(mag and (mag.Position - m0).Magnitude > 0.05, "换弹时弹匣动了")
R.run(2.5)
check(vm and vm.act == nil, "换完回到待机")

print("④ 开镜：M4 导轨上的 ACOG 举到眼前、光轴对正屏幕中心，镜身一直看得见；镜内单独放大（画中画）：镜外普通开镜，镜片那个圆里是 3.5 倍的战场")
vm = C.fps
local nAcog = 0
if vm then for _, it in ipairs(vm.items) do if it.optic then nAcog = nAcog + 1 end end end
check(vm and vm.optic ~= nil and nAcog >= 5, "M4 上装着 ACOG（" .. nAcog .. " 块真模型）")
-- 视图模型里叫这个名字（O_acog__<块名>）的零件
local function optPart(v, name)
  for _, it in ipairs(v and v.items or {}) do if it[1].Name == "O_acog__" .. name then return it[1] end end
end
check(optPart(vm, "Eyepiece") ~= nil, "补上的正圆目镜圈（原模型的目镜是八边形）也装着")
local scopeGui = me.PlayerGui:FindFirstChild("Scope")
local sent = 0
local scope0 = G.ACT.scope   -- 服务器那边记「开着镜」的操作：数一数客户端发了几次
G.ACT.scope = function(...)
  sent = sent + 1
  return scope0(...)
end
local cam = R.workspace.CurrentCamera
T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
R.run(0.1)
local fovMid = cam.FieldOfView
local ep = optPart(vm, "Eyepiece")
check(ep and ep.LocalTransparencyModifier == 0, "举镜过程中镜身、目镜圈都看得见")
check(fovMid > 50 and fovMid < 67.9, string.format("镜外跟着举镜进度稍微放大一点（这会儿视角 %.1f°）", fovMid))
R.run(1.0)
if vm and vm.optic then
  local gi = itemOf(vm, "gun")
  local gcf = gi[1].CFrame * gi[3]:Inverse()   -- 零件 → 枪身骨骼
  local e = cam.CFrame:PointToObjectSpace(gcf * vm.optic.eyeG)
  local o = cam.CFrame:PointToObjectSpace(gcf * vm.optic.objG)
  check(math.abs(e.X) < 0.01 and math.abs(e.Y) < 0.01 and math.abs(o.X) < 0.01 and math.abs(o.Y) < 0.01, string.format("目镜、物镜都在屏幕正中（%.3f, %.3f / %.3f, %.3f）", e.X, e.Y, o.X, o.Y))
  check(e.Z < -0.1 and e.Z > -0.4, string.format("目镜在眼前（%.2f 格，视角越小推得越远）", -e.Z))
end
local fov = cam.FieldOfView
check(math.abs(fov - 68 / 1.25) < 1, string.format("镜外只是普通开镜：1.25 倍（视角 %.1f°），不跟着 3.5 倍放大", fov))
check(scopeGui and scopeGui.Enabled, "举到眼前：目镜上画着镜片那一层")
-- 镜身还在（使命召唤那样），镜筒里面挡着视线的块藏起来
local nIn, inHid, bodyOn = 0, true, false
for _, it in ipairs(vm and vm.items or {}) do
  if it.inner then
    nIn = nIn + 1
    if it[1].LocalTransparencyModifier ~= 1 then inHid = false end
  end
end
bodyOn = optPart(vm, "Body") ~= nil and optPart(vm, "Body").LocalTransparencyModifier == 0 and optPart(vm, "Eyepiece").LocalTransparencyModifier == 0
check(nIn >= 3 and inHid, "镜筒里面的块（内壁、镜片、分划板 " .. nIn .. " 块）藏起来：从目镜的洞里直接看放大的画面")
check(bodyOn, "镜身、正圆的目镜圈一直看得见（不再整屏涂黑）")
-- 镜片那一层：正圆（CanvasGroup + UICorner 按圆裁剪），正好盖在 3D 目镜的洞上（屏幕正中、直径占屏高五成）
local lensF = scopeGui and scopeGui:FindFirstChild("ScopeLens", true)
local vs = cam.ViewportSize
if lensF then
  local corner = lensF:FindFirstChildOfClass("UICorner")
  local w, h = lensF.Size.X.Offset, lensF.Size.Y.Offset
  local px, py = lensF.Position.X.Offset, lensF.Position.Y.Offset
  check(lensF.ClassName == "CanvasGroup" and T.visible(lensF) and corner and corner.CornerRadius.Scale == 0.5 and w == h,
    string.format("镜片是正圆（%s，%d×%d，圆角 0.5）", lensF.ClassName, w, h))
  check(math.abs(px - vs.X / 2) < 2 and math.abs(py - vs.Y / 2) < 2 and math.abs(w / vs.Y - 0.3) < 0.03,
    string.format("镜片在屏幕正中（%.1f, %.1f）、直径是屏高的 %.2f（画中画时 GunMods pipK 0.3）", px, py, w / vs.Y))
  check(lensF.GroupTransparency < 0.02, "举好了：镜片那一层满（淡入完）")
else
  check(false, "镜片那一层（ScopeLens）")
end
-- 画中画：镜片底下一个圆的 ViewportFrame，镜头就在眼睛这儿、朝准星看，视角 = 镜片的角大小 ÷ 3.5；里面有地形网格、海、雾
local pst, pv, pwm, pcm = C.pipDebug()
check(pst.ok == true and pv.Visible and pv.Parent and pv.Parent.Parent == scopeGui, "镜片底下是画中画（ViewportFrame）")
if lensF and pv.Visible then
  check(pv.Size.X.Offset == lensF.Size.X.Offset and pv.Position.X.Offset == lensF.Position.X.Offset and pv.Position.Y.Offset == lensF.Position.Y.Offset,
    "画中画正好在镜片那个圆里（" .. pv.Size.X.Offset .. " 像素）")
  local fm = (vs.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
  local want = 2 * math.deg(math.atan((lensF.Size.X.Offset / 2 / fm) / 3.5))
  check(math.abs(pcm.FieldOfView - want) < 0.05 and (pcm.CFrame.Position - cam.CFrame.Position).Magnitude < 1e-3 and pcm.CFrame.LookVector:Dot(cam.CFrame.LookVector) > 0.9999,
    string.format("画中画的镜头在眼睛这儿、朝准星看，视角 %.2f°（镜片的角大小 ÷ 3.5 = %.2f°）", pcm.FieldOfView, want))
end
local nTer = 0
for _, d in ipairs(pwm:GetChildren()) do if d.Name == "PipTerrain" then nTer = nTer + 1 end end
check(nTer >= 2 and pst.lv[1] and pst.lv[2], "地形网格：脚下两级都生成好了（" .. nTer .. " 张）")
-- 正前方放一块火光（ClientFx）、地图上一块墙（Map）：画中画里各有一份；烟幕补灰球
local look = cam.CFrame.LookVector
local fx = R.make("Part")
fx._p.Name = "PipProbeFx"
fx.Size, fx.CFrame, fx.Anchored = V3(3, 3, 3), CF(cam.CFrame.Position + look * 120), true
fx.Parent = R.workspace:FindFirstChild("ClientFx")
local wall = R.make("Part")
wall._p.Name = "PipProbeWall"
wall.Size, wall.CFrame, wall.Anchored = V3(20, 12, 2), CF(cam.CFrame.Position + look * 260), true
wall.Parent = R.workspace:FindFirstChild("Map")
C.pipSmoke(cam.CFrame.Position + look * 400, 20, 30)
R.run(0.6)
local seen = {}
for _, d in ipairs(pwm:GetDescendants()) do seen[d.Name] = (seen[d.Name] or 0) + 1 end
check((seen.PipProbeFx or 0) >= 1, "会动的东西（火光、曳光、车、人）镜像进画中画")
check((seen.PipProbeWall or 0) >= 1, "地图上的东西（锥里的格子）克隆进画中画")
local balls = 0
for _, d in ipairs(pwm:GetChildren()) do if d.ClassName == "Part" and d.Shape == Enum.PartType.Ball and d.Transparency < 0.9 then balls = balls + 1 end end
check(balls >= 6, "烟幕在画中画里是一团团里外几层的烟（" .. balls .. " 个），透过镜子看不穿")
fx:Destroy()
wall:Destroy()
local nOut = 0
for _, f in ipairs(scopeGui and scopeGui:GetDescendants() or {}) do
  if f.Name == "ScopeOuter" and T.visible(f) then nOut = nOut + 1 end
end
check(nOut >= 8, "镜片外面：贴着镜片一圈羽化、再往外整片压暗（" .. nOut .. " 圈）")
local dofE = R.services.Lighting:FindFirstChild("ScopeDOF")
check(dofE and dofE.Enabled and dofE.NearIntensity > 0.1 and dofE.NearIntensity < 0.3, string.format("近处的镜身轻轻糊一点（ScopeDOF %.2f；画中画时清楚的金属才像真的）", dofE and dofE.NearIntensity or -1))
-- 镜身、目镜罩、画中画地形都是 Roblox 自带的真材质（用户 11-21：镜片效果太假）
local eyeP, bodyP = optPart(vm, "Eyepiece"), optPart(vm, "Body")
check(eyeP and eyeP.Material == Enum.Material.Rubber and bodyP and bodyP.Material == Enum.Material.Metal, "目镜罩是橡胶、镜身是金属材质（不再是平涂的塑料）")
local terMats = {}
for _, d in ipairs(pwm:GetDescendants()) do
  if d.ClassName == "MeshPart" and d.Name:sub(1, 11) == "PipTerrain_" then terMats[d.Material.Name] = true end
end
local tm = {}
for k in pairs(terMats) do tm[#tm + 1] = k end
table.sort(tm)
check(#tm >= 2 and not terMats.SmoothPlastic, "画中画的地形按材质分块、贴真材质纹理（" .. table.concat(tm, "、") .. "）")
local fake = 0
for _, d in ipairs(scopeGui:GetDescendants()) do
  if d.ClassName == "UIStroke" and T.visible(d.Parent) and d.Thickness <= 3 and (d.Color.R > 0.6 or d.Color.B > 0.6) and d.Transparency < 0.95 then fake = fake + 1 end
end
check(fake == 0, "镜片上没有反光弧、红蓝彩边圈这些假的东西（" .. fake .. " 道）")
local acogN, retShown = 0, false
if scopeGui then
  for _, f in ipairs(scopeGui:GetDescendants()) do
    if f.ClassName == "Frame" and f.Rotation ~= 0 and T.visible(f) and f.BackgroundColor3.R > 0.9 and f.BackgroundColor3.G < 0.3 then acogN = acogN + 1 end
    if f.Name == "MilX5" and T.visible(f) then retShown = true end
  end
end
check(acogN >= 2 and not retShown, "红色箭形分划（" .. acogN .. " 道斜线），没有狙击镜的密位分划")
check(sent == 0, "步枪开镜不告诉服务器（不闪镜片）")
T.mouse(false, nil, nil, Enum.UserInputType.MouseButton2)
R.run(0.6)
G.ACT.scope = scope0
check(scopeGui and not scopeGui.Enabled and not (dofE and dofE.Enabled), "松开右键：镜片那一层跟着淡出、收掉，景深关上")
check(math.abs(cam.FieldOfView - 68) < 1.5, string.format("视角回到 68°（%.1f°）", cam.FieldOfView))
check(not pv.Visible, "画中画跟着收起来")
-- 画中画用不了（游戏没开 EditableMesh、地形网格还没好）：照旧整屏放大 3.5 倍，镜片占屏高五成
C.pipForceOff = true
T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
R.run(1.0)
check(math.abs(cam.FieldOfView - 68 / 3.5) < 1 and not pv.Visible, string.format("画中画用不了：整屏放大 3.5 倍（视角 %.1f°）", cam.FieldOfView))
if lensF then check(math.abs(lensF.Size.X.Offset / vs.Y - 0.5) < 0.03, string.format("镜片占屏高 %.2f（lensK 0.5）", lensF.Size.X.Offset / vs.Y)) end
T.mouse(false, nil, nil, Enum.UserInputType.MouseButton2)
R.run(0.6)
C.pipForceOff = nil

print("⑤ 换武器：按 2（第二件，不管装备栏哪格空着）、滚轮、Q 切回上一把；同一双手端着")
local UISv = R.services.UserInputService
local function wheel(z)
  R.as("client", function() UISv.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, z) }, false) end)
end
T.tap(Enum.KeyCode.Two)
R.run(1)
vm = C.fps
local id2 = vm and vm.id
check(vm and id2 ~= "m4" and #vm.items >= 1 and #vm.arms == 6, "按 2 换成第二件：" .. tostring(id2) .. "，零件 " .. tostring(vm and #vm.items))
T.tap(Enum.KeyCode.Q)
R.run(1)
check(C.fps and C.fps.id == "m4", "Q 切回上一把（M4）")
wheel(-1)
R.run(1)
check(C.fps and C.fps.id == id2, "滚轮往下：下一件（" .. tostring(C.fps and C.fps.id) .. "）")
wheel(1)
R.run(1)
check(C.fps and C.fps.id == "m4", "滚轮往上：回到 M4")
T.tap(Enum.KeyCode.One)
R.run(0.5)
T.tap(Enum.KeyCode.One)
R.run(1)
check(C.fps and C.fps.id == "m4", "按 1 拿着 M4")

print("⑥ V 切到第三人称")
T.tap(Enum.KeyCode.V)
R.run(0.5)
check(me.CameraMinZoomDistance >= 8 and C.fps == nil, "第三人称：镜头拉开，视图模型收起")
T.tap(Enum.KeyCode.V)
R.run(0.5)
check(me.CameraMaxZoomDistance == 0.5 and C.fps ~= nil, "再按 V 回到第一人称")

print("⑦ 导入的原模型：ReplicatedStorage.Imported.FPS_M4")
local RSv = R.services.ReplicatedStorage
local imp = R.make("Folder")
imp._p.Name = "Imported"
local mdl = R.make("Model")
mdl._p.Name = "FPS_M4"
for _, n in ipairs({ "FPS_M4_Main", "FPS_M4_Mag1", "FPS_M4_Mag2", "FPS_M4_Bolt", "FPS_M4_BoltCatch", "FPS_M4_Trigger", "FPS_M4_Round1", "FPS_M4_Round2" }) do
  local mp = R.make("MeshPart")
  mp._p.Name = n
  mp.Parent = mdl
end
mdl.Parent = imp
imp.Parent = RSv
T.tap(Enum.KeyCode.Two)
R.run(0.6)
T.tap(Enum.KeyCode.One)
R.run(0.8)
vm = C.fps
local meshN = 0
if vm then for _, it in ipairs(vm.items) do if it[1].ClassName == "MeshPart" and not it.optic then meshN = meshN + 1 end end end   -- ACOG 的块不算
check(meshN == 8, "换成了导入的网格：" .. meshN .. " 个 MeshPart")
T.summary()
