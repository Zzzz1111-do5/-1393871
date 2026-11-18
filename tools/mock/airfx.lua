-- 飞机机动的云雾和音爆（模拟器）：python3 tools/mock/run.py tools/mock/airfx.lua
--   用户：飞机机动的云雾效果和音爆；尾喷非常怪（换成锥形渐隐的火焰光带）；折叠机翼没有动画
--   ① 平飞：没有拖线、没有水汽；拉 4 g 翼尖拖线、拉 7 g 机翼上冒水汽
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
T.act("deploy", "rifle", "af2")
R.run(2)
local A2 = G.Map.AFIELD2
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
-- 真的滑跑起飞（直接把飞机摆到天上，服务器不认会拉回跑道）：W 推油门、准心往上抬（纯准心控制），离地后爬一会儿
T.key(Enum.KeyCode.W, true)
st.aimPitch = math.rad(12)
T.runUntil(function() return not st.ground end, 40)
R.run(1.5)
st.aimPitch = math.rad(3)
R.run(5)
T.key(Enum.KeyCode.W, false)
-- 一直按 W 油门推到了加力、快到音障（会冒蒸汽锥）：收到军推、速度放回巡航
st.thr, st.thrE = 90, 90
st.spd = math.min(st.spd, e.def.vMil * 0.8)
st.vel = st.vdir * st.spd
R.run(2)
local v = C.views and C.views[e.model]
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
-- 准心猛往上抬 80°：教官要大过载拉起来
local lk = st.cf.LookVector
st.aimYaw, st.aimPitch = math.atan2(-lk.X, -lk.Z), math.min(1.4, math.asin(math.max(-1, math.min(1, lk.Y))) + math.rad(80))
local got4, got7, gMax = false, false, 0
for _ = 1, 60 do
  R.run(1 / 20)
  gMax = math.max(gMax, st.gLoad or 0)
  if (st.gLoad or 0) > 4 and trailsOn() >= 2 then got4 = true end
  if (st.gLoad or 0) > 7 and vaporOn() >= 2 then got7 = true end
end
lk = st.cf.LookVector
st.aimYaw, st.aimPitch = math.atan2(-lk.X, -lk.Z), math.asin(math.max(-1, math.min(1, lk.Y)))
check(got4, string.format("拉到 4 g 以上：两个翼尖拖出白线（最大 %.1f g）", gMax))
check(got7, "拉到 7 g 以上：两边机翼上冒水汽")
R.run(3)

print("② 音障：蒸汽锥、音爆")
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

print("③ 尾喷：军推只有喷口里的热芯，加力两条渐隐的火焰光带，没有玻璃气泡")
local function beams()
  local n = 0
  for _, d in ipairs(v.M.model:GetDescendants()) do if d.ClassName == "Beam" and (d.Name == "AbFlame" or d.Name == "AbCore") and d.Enabled then n = n + 1 end end
  return n
end
local glass = 0
for _, d in ipairs(v.M.model:GetDescendants()) do if d:IsA("BasePart") and d.Material == Enum.Material.Glass and d.Name == "Haze" then glass = glass + 1 end end
check(glass == 0, "没有玻璃球热浪")
st.thr, st.thrE = 100, 100
R.run(0.3)
check(beams() == 0, "军推：没有火焰光带")
st.thr, st.thrE = 130, 130
R.run(0.3)
check(beams() >= 2, "加力：火焰光带亮了（" .. beams() .. " 条）")

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
