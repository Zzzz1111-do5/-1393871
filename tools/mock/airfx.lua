-- 飞机机动的云雾和音爆（模拟器）：python3 tools/mock/run.py tools/mock/airfx.lua
--   用户：飞机机动的云雾效果和音爆；尾喷非常怪（换成锥形渐隐的火焰光带）；折叠机翼没有动画
--   ① 平飞：没有拖线、没有水汽；拉 3 g 翼尖拖线、拉 4.5 g 机翼上冒水汽（11-21 过载上限收到七成）
--   ② 推到音障附近有蒸汽锥；冲过音障放一声音爆（自己听到闷的、震一下）
--   ③ 尾喷：军推没有火焰光带、喷口里发亮；加力有两条光带（外层长、里层短），没有玻璃气泡
--   ④ 折叠机翼：别人的舰载机折翼属性从 0 变 1，显示是几秒慢慢折起来的
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", G.Map.LANDONLY and "baseAir" or "af2")   -- 沙海（11-24 起只剩这张）：主基地机场
R.run(2)
local A2 = G.Map.AFIELD2 or G.Map.AIRFIELD
local x, z = A2.x + 300, A2.z - A2.wid / 2 - 220
local gy = G.airSurface(x, z)
local e = G.spawnAircraft("atk", "j20", CF(x, gy + 6, z), nil, P)
me.Character:PivotTo(CF(x + 20, gy + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.fly
check(st ~= nil and st.pilot, "坐进了歼-20")
if not st then T.summary() return end
-- 真的滑跑起飞（直接把飞机摆到天上，服务器不认会拉回跑道）：Shift 推油门、速度到了按住 S 抬头（用户 11-21：WASD 控制方向），离地后爬一会儿
T.key(Enum.KeyCode.LeftShift, true)
T.runUntil(function() return st.spd >= e.def.vRot end, 40)
do   -- 用户 11-28「起飞时马赫环喷到地上要能有对应效果」：滑跑推满油门，喷口后面的地上吹起尘土；开着加力地面映成橙色
  R.run(0.2)
  local v0 = C.views and C.views[e.model]
  local B, k = nil, 0
  if v0 and C.airBlast then B, k = C.airBlast(v0) end
  check(B ~= nil and (k or 0) > 0.1 and B.pe.Rate > 0,
    string.format("起飞滑跑：喷口后面的地上吹起尘土（强度 %.2f、每秒 %s 团，油门 %d）", k or 0, B and tostring(B.pe.Rate) or "-", st.thr or 0))
  if (st.thr or 0) > 105 then check(B ~= nil and B.light.Enabled and B.light.Brightness > 0, "开着加力：地面被尾焰映成橙色") end
end
T.key(Enum.KeyCode.S, true)
T.runUntil(function() return not st.ground end, 10)
R.run(1)
T.key(Enum.KeyCode.S, false)
R.run(5)
T.key(Enum.KeyCode.LeftShift, false)
-- 一直按 Shift 油门推到了加力、快到音障（会冒蒸汽锥）：收到军推、速度放回巡航
st.thr, st.thrE = 90, 90
-- 飞行物理（11-26 晚）以后加速照真机：起飞爬升五六秒才三百来格 / 秒，这么慢拉满杆升力也只够两三 g——直接给到八成 vMil（测的是拉杆的云雾，不是加速）
st.spd = e.def.vMil * 0.8
st.vel = st.vdir * st.spd
R.run(2)
local v = C.views and C.views[e.model]
do
  local B, k = C.airBlast(v)
  check((k or 0) == 0 and (not B or B.pe.Rate == 0), "飞高了：地上不再吹尘土")
end
local function trailsOn()
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "Trail" and d.Name == "Vortex" and d.Enabled then n = n + 1 end end
  return n
end
local function vaporOn()
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "ParticleEmitter" and d.Name == "Vapor" and d.Enabled then n = n + 1 end end
  return n
end
print("① 平飞没有云雾；拉杆有翼尖涡流、机翼水汽")
check(v ~= nil and v.M ~= nil, "客户端拼好了飞机")
check(trailsOn() == 0 and vaporOn() == 0, string.format("平飞：没有拖线、没有水汽（拖线 %d、水汽 %d，%.1f g，%.0f 格 / 秒）", trailsOn(), vaporOn(), st.gLoad or 0, st.spd or 0))
-- 按住 S 猛拉杆（用户 11-21：WASD 控制方向；过载上限收到七成，歼-20 约 6.5 g）
local y0 = st.cf.Position.Y   -- 拉杆前的高度（② 摆回这个高度）
T.key(Enum.KeyCode.S, true)
local got4, got7, gMax = false, false, 0
for _ = 1, 60 do
  R.run(1 / 20)
  gMax = math.max(gMax, st.gLoad or 0)
  if (st.gLoad or 0) > 3.5 and trailsOn() >= 2 then got4 = true end
  if (st.gLoad or 0) > 5 and vaporOn() >= 2 then got7 = true end
end
T.key(Enum.KeyCode.S, false)
check(got4, string.format("拉到 3.5 g 以上：两个翼尖拖出白线（最大 %.1f g）", gMax))
check(got7, "拉到 5 g 以上：两边机翼上冒水汽")
R.run(3)

print("② 音障：蒸汽锥、音爆")
-- ① 拉满杆三秒（飞行物理以后速度够，拉出来是半个筋斗、爬高一大截）：摆回拉杆前的高度、平飞，再看音障（蒸汽锥要低空的湿空气）
do
  local p = st.cf.Position
  local f = st.cf.LookVector
  local flat = R.Vector3.new(f.X, 0, f.Z)
  flat = (flat.Magnitude > 0.1) and flat.Unit or R.Vector3.new(0, 0, -1)
  local np = R.Vector3.new(p.X, y0, p.Z)
  st.cf = R.CFrame.lookAt(np, np + flat)
  st.vdir, st.vel = flat, flat * st.spd
  st.pr, st.rr, st.yr = 0, 0, 0
  st.aimYaw, st.aimPitch = math.atan2(-flat.X, -flat.Z), 0
  if G.moveEnt then G.moveEnt(e, st.cf) end
  R.run(0.5)
end
local m1 = C.airMach1 and C.airMach1(e.def)
check(m1 ~= nil, "歼-20 有音障速度（" .. tostring(m1) .. " 格 / 秒）")
local booms = 0
local sfx0 = C.sfx
C.sfx = function(def, pos, o) if def == "sonic" then booms = booms + 1 end return sfx0(def, pos, o) end
st.thr, st.thrE = 130, 130
st.spd = m1 * 0.96
st.vel = st.vdir * st.spd
R.run(0.2)
local coneOn = false
for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "ParticleEmitter" and d.Name == "Vapor" and d.Enabled and d.Parent.Size.Z < 1 then coneOn = true end end
check(coneOn, "音障附近：机身中段一圈蒸汽锥")
st.spd = m1 * 1.03
st.vel = st.vdir * st.spd
R.run(0.3)
check(booms == 1, "冲过音障：放了一声音爆（" .. booms .. "）")
R.run(1)
check(booms == 1, "一直在音障上面不再响")
C.sfx = sfx0

print("③ 尾喷（用户 11-28「飞机尾喷的效果非常烂而且不是立体的」「这个特效太卡通了吧」）：军推只有喷口里的热芯；加力是柔边发光粒子的焰身、焰芯 + 一串马赫环；喷口里发橙粉色；没有光带、蓝边管子、玻璃气泡")
local function beams(name)
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "Beam" and d.Name == name and d.Enabled then n = n + 1 end end
  return n
end
local function shown(name)   -- 看得见的（不全透明）这种零件有几块
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d:IsA("BasePart") and d.Name == name and d.Transparency < 0.95 then n = n + 1 end end
  return n
end
local glass = 0
for _, d in ipairs(v.M.model:GetDescendants()) do if d:IsA("BasePart") and d.Material == Enum.Material.Glass and d.Name == "Haze" then glass = glass + 1 end end
check(glass == 0, "没有玻璃球热浪")
local haze = 0
for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "ParticleEmitter" and d.Name == "HeatHaze" then haze = haze + 1 end end
check(haze == 0, "喷口后面没有圆团的热浪粒子（用户 11-18：喷口有怪异的泡泡）")
-- 用户 11-28「发动机中心还有小小的热浪」：喷口正中一小股，顺着气流拉长的细丝、很淡
local shim, shimOk = 0, true
for _, d in ipairs(v.M.model:GetDescendants()) do
  if d.ClassName == "ParticleEmitter" and d.Name == "HeatShimmer" then
    shim = shim + 1
    local minTr = 1
    for _, kp in ipairs(d.Transparency.Keypoints) do minTr = math.min(minTr, kp.Value) end
    if d.Orientation ~= Enum.ParticleOrientation.VelocityParallel or minTr < 0.88 or not d.LockedToPart then shimOk = false end
  end
end
check(shim >= 1 and shimOk, string.format("喷口正中一小股热浪：顺着气流拉长的细丝、很淡、锁在喷口上（%d 股）", shim))
st.thr, st.thrE = 100, 100
R.run(0.3)
local function emitting(name)   -- 开着的这种粒子有几个
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "ParticleEmitter" and d.Name == name and d.Enabled then n = n + 1 end end
  return n
end
check(emitting("AbBody") == 0 and emitting("AbDiamond") == 0, "军推：没有加力火焰")
st.thr, st.thrE = 130, 130
R.run(0.3)
local nEng = #(v.M.plumes or {})
check(nEng >= 1 and emitting("AbBody") >= nEng and emitting("AbCore") >= nEng and emitting("AbDiamond") >= nEng,
  string.format("加力：每个喷口一股柔边发光的焰身、焰芯，一串马赫环（%d 台：焰身 %d、焰芯 %d、马赫环 %d 颗）", nEng, emitting("AbBody"), emitting("AbCore"), emitting("AbDiamond")))
check(beams("AbFill") == 0 and beams("AbCore") == 0, "不再是朝镜头的光带（立体的）")
check(shown("AbTube") == 0 and shown("MachRing") == 0, "没有 11-23 那版的蓝边管子、马赫环")
local fillLen = 0
for _, I in ipairs(C.airModels and C.airModels.plumeInfo(v.M) or {}) do fillLen = math.max(fillLen, I.Lv or 0) end
check(fillLen > 12, string.format("火焰拉得长（%.0f 格，满加力约六个半喷口直径）", fillLen))
local hotOk = false
for _, d in ipairs(v.M.model:GetDescendants()) do
  if d:IsA("BasePart") and d.Transparency < 0.3 and d.Color.R > 0.95 and d.Color.G > 0.55 and d.Color.B > 0.3 and d.Color.B < 0.8 then hotOk = true end
end
check(hotOk, "喷口里烧得发橙粉色")

print("⑤ 导弹视角小窗：自己打出去的弹，右上角从弹上看目标；命中写「命中」，停一会儿关掉")
do
  local p0 = st.cf.Position
  local foe = G.spawnAircraft("def", "f22", CF(p0.X + 600, p0.Y + 40, p0.Z - 900), nil, nil)
  R.run(0.5)
  check(foe ~= nil, "前面放一架敌机")
  if foe then
    local id = 990001
    local mpos = p0 + st.cf.LookVector * 20
    local body = R.Instance.new("Part")
    C.flyingShots[id] = { p = mpos, v = (foe.root.CFrame.Position - mpos).Unit * 900, t = 0, kind = "missile", body = body, trailT = 0, half = 1.2 }
    R.as("client", function() C.onMyShot({ id = id, tg = foe.id, w = "pl15", p = mpos, by = st.id }) end)
    R.run(0.2)
    local gui = me.PlayerGui:FindFirstChild("MslCam")
    local vpf = gui and gui:FindFirstChild("View", true)
    local cl = vpf and vpf:FindFirstChild("Model")
    check(gui and gui.Enabled, "开了导弹视角小窗")
    check(cl ~= nil, "小窗里复制了一份目标（白热）")
    local cam2 = vpf and vpf.CurrentCamera
    local okLook = false
    if cam2 and cl then
      local sum, n = V3(0, 0, 0), 0
      for _, d in ipairs(cl:GetDescendants()) do if d:IsA("BasePart") then sum = sum + d.Position n = n + 1 end end
      local pv = sum / math.max(n, 1)
      okLook = (pv - cam2.CFrame.Position).Unit:Dot(cam2.CFrame.LookVector) > 0.97
    end
    check(okLook, "小窗的镜头对着目标")
    local info = gui and gui:FindFirstChild("Info", true)
    check(info and info.Text:find("km", 1, true), "写着目标多远、还剩几秒：" .. tostring(info and info.Text))
    -- 命中：弹飞到目标身上没了
    C.flyingShots[id].p = foe.root.CFrame.Position + V3(3, 0, 0)
    R.as("client", function() C.onShotEnd(id, C.flyingShots[id]) end)
    C.flyingShots[id] = nil
    R.run(0.2)
    local res = gui and gui:FindFirstChild("Result", true)
    check(res and res.Text == C.T("mcam.hit"), "写着「命中」")
    R.run(1.5)
    check(not gui.Enabled, "过一会儿关掉了")
  end
end

print("④ 折叠机翼：慢慢折起来")
T.tap(Enum.KeyCode.Space)
R.run(1.5)
local cv = nil
for _, x2 in ipairs(G.aircraft or {}) do if x2.alive and x2.def.fold and x2 ~= e then cv = x2 end end
if not cv then
  cv = G.spawnAircraft("atk", "j15t", CF(x + 200, gy + 6, z), nil, P)
  me.Character:PivotTo(CF(x + 200, gy + 3.5, z + 40))
  R.run(1)
end
local vv = cv and C.views and C.views[cv.model]
check(vv ~= nil, "有一架舰载机（" .. tostring(cv and cv.def.id) .. "）")
if vv then
  cv.model:SetAttribute("Fold", 1)
  R.run(1)
  local f1 = vv.c.fold
  R.run(5)
  local f2 = vv.c.fold
  check(f1 > 0.05 and f1 < 0.6 and f2 > 0.95, string.format("折翼不是一下跳过去：1 秒 %.2f、6 秒 %.2f", f1 or -1, f2 or -1))
end
T.summary()
