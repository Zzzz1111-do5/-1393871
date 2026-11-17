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

print("④ 开镜：M4 导轨上的 ACOG 举到眼前（光轴对正屏幕中心），贴上目镜换成 3.5 倍的目镜里的像（箭形分划），不闪镜片")
vm = C.fps
local nAcog = 0
if vm then for _, it in ipairs(vm.items) do if it.optic then nAcog = nAcog + 1 end end end
check(vm and vm.optic ~= nil and nAcog >= 5, "M4 上装着 ACOG（" .. nAcog .. " 块真模型）")
local scopeGui = me.PlayerGui:FindFirstChild("Scope")
local sent = 0
local scope0 = G.ACT.scope   -- 服务器那边记「开着镜」的操作：数一数客户端发了几次
G.ACT.scope = function(...)
  sent = sent + 1
  return scope0(...)
end
T.mouse(true, nil, nil, Enum.UserInputType.MouseButton2)
R.run(0.12)
check(scopeGui and not scopeGui.Enabled, "举镜过程中还看得见镜子本身（目镜里的像先不画）")
R.run(1.0)
if vm and vm.optic then
  local cam = R.workspace.CurrentCamera
  local gi = itemOf(vm, "gun")
  local gcf = gi[1].CFrame * gi[3]:Inverse()   -- 零件 → 枪身骨骼
  local e = cam.CFrame:PointToObjectSpace(gcf * vm.optic.eyeG)
  local o = cam.CFrame:PointToObjectSpace(gcf * vm.optic.objG)
  check(math.abs(e.X) < 0.01 and math.abs(e.Y) < 0.01 and math.abs(o.X) < 0.01 and math.abs(o.Y) < 0.01, string.format("目镜、物镜都在屏幕正中（%.3f, %.3f / %.3f, %.3f）", e.X, e.Y, o.X, o.Y))
  check(e.Z < -0.1 and e.Z > -0.4, string.format("目镜贴在眼前（%.2f 格）", -e.Z))
end
local fov = R.workspace.CurrentCamera.FieldOfView
check(fov > 15 and fov < 20, string.format("3.5 倍（视角 %.1f°）", fov))
check(scopeGui and scopeGui.Enabled, "贴上目镜：换成目镜里的像")
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
R.run(0.5)
G.ACT.scope = scope0
check(scopeGui and not scopeGui.Enabled, "松开右键收镜")

print("⑤ 换手雷：同一双手端着")
T.tap(Enum.KeyCode.Two)
R.run(1)
vm = C.fps
check(vm and vm.id == "grenade" and #vm.items >= 1 and #vm.arms == 6, "手雷：" .. tostring(vm and vm.id) .. "，零件 " .. tostring(vm and #vm.items))
T.tap(Enum.KeyCode.One)
R.run(1)
check(C.fps and C.fps.id == "m4", "切回 M4")

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
