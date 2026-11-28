-- 飞机的镜头不被拽回机头（模拟器）：python3 tools/mock/run.py tools/mock/aircam.lua
--   用户 11-28：「飞机驾驶不要强制让镜头跟着机头」——原来纯键盘驾驶（设置「固定翼操纵」，飞行中按 M 也会切过去并存进设置）镜头钉在机头上，
--   只有按住右键才能转、松开就滑回去；战雷鼠标瞄准在地上滑跑时也是镜头钉在机头上
--   ① 纯键盘、在空中：拨鼠标镜头转开；停 5 秒还在那里；飞机压坡度转弯，镜头看的方向不跟着转；按 C 回到身后
--   ② 纯键盘：按住右键拖开、松开，镜头停在拖到的地方
--   ③ 战雷鼠标瞄准、在空中：镜头顺着准星圈（鼠标想去的方向），飞机追过去
--   ④ 战雷鼠标瞄准、在地上：拨鼠标镜头转开（准星圈照旧在机头上，滑跑不被鼠标带偏）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local V2 = R.Vector2.new
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.allowInfantry = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9811, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
local CFr = R.CFrame
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
local cam = R.workspace.CurrentCamera
local gy = math.max(G.Map.ground(0, 0), 0)
local function ang(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a.Unit:Dot(b.Unit))))) end

local cur = nil
local function board(id, acf)
  if cur and cur.model and cur.model.Parent then
    T.remoteAs(me, "Drive", { op = "exit" })
    R.run(0.5)
    G.removeEnt(cur)
    R.run(0.3)
  end
  local jet = G.spawnAircraft("atk", id, acf, nil, P)
  P.char:PivotTo(acf * CF(6, 0, 0))
  T.act("enterVeh", jet.id)
  R.run(0.3)
  cur = jet
  return C.fly, jet
end
local function airborne(st, jet)
  local p = V3(0, gy + 1200, 0)
  local look = V3(0, 0, -1)
  st.cf = CFr.lookAt(p, p + look)
  st.vdir, st.spd, st.vel = look, 220, look * 220
  st.thr, st.thrE = 0.8, 0.8
  st.ground, st.gearWant, st.gear = false, 0, 0
  G.moveEnt(jet, st.cf)
  jet.vel = st.vel
  jet.syncT, jet.syncSlack = os.clock(), 160
end
local function drag(dx, n)
  for _ = 1, n do
    R.mouseDelta = V2(dx, 0)
    R.run(1 / 30)
  end
  R.mouseDelta = V2(0, 0)
end

print("① 纯键盘、在空中：拨鼠标镜头转开、停在那里")
local st, jet = board("f16", CF(0, gy + 1200, 0))
check(st ~= nil and st.d and st.d.kind == "jet", "坐上了 F-16")
if not st then T.summary() return end
C.flyMouseAim(false)
airborne(st, jet)
R.run(1)
check(ang(cam.CFrame.LookVector, st.cf.LookVector) < 10, string.format("开始镜头在身后、顺着机头（%.1f°）", ang(cam.CFrame.LookVector, st.cf.LookVector)))
drag(30, 10)
local away = ang(cam.CFrame.LookVector, st.cf.LookVector)
check(away > 20, string.format("拨鼠标：镜头转开 %.0f°（不用按右键）", away))
local look0 = cam.CFrame.LookVector
R.run(5)
check(ang(cam.CFrame.LookVector, look0) < 4, string.format("停 5 秒：镜头还看着那个方向，不被拽回机头（偏了 %.1f°）", ang(cam.CFrame.LookVector, look0)))
local look1 = cam.CFrame.LookVector
local nose1 = st.cf.LookVector
T.key(Enum.KeyCode.D, true)
R.run(0.6)
T.key(Enum.KeyCode.D, false)
T.key(Enum.KeyCode.S, true)
R.run(1.6)
T.key(Enum.KeyCode.S, false)
local turned = ang(st.cf.LookVector, nose1)
check(turned > 8, string.format("飞机压坡度拉杆转过去 %.0f°", turned))
check(ang(cam.CFrame.LookVector, look1) < 4, string.format("镜头看的方向不跟着机头转（偏了 %.1f°）", ang(cam.CFrame.LookVector, look1)))
T.tap(Enum.KeyCode.C)
R.run(0.8)
check(ang(cam.CFrame.LookVector, st.cf.LookVector) < 10, string.format("按 C：镜头回到身后（离机头 %.1f°）", ang(cam.CFrame.LookVector, st.cf.LookVector)))

print("② 纯键盘：按住右键拖开、松开，镜头停在拖到的地方")
airborne(st, jet)
R.run(1)
T.mouse(true, 640, 360, Enum.UserInputType.MouseButton2)
drag(-30, 10)
T.mouse(false, 640, 360, Enum.UserInputType.MouseButton2)
R.run(0.2)
local look2 = cam.CFrame.LookVector
local away2 = ang(look2, st.cf.LookVector)
check(away2 > 20, string.format("右键拖开 %.0f°", away2))
R.run(2)
check(ang(cam.CFrame.LookVector, look2) < 4, string.format("松开右键 2 秒：镜头停在那里（偏了 %.1f°）", ang(cam.CFrame.LookVector, look2)))
T.tap(Enum.KeyCode.C)
R.run(0.8)

print("③ 战雷鼠标瞄准、在空中：镜头顺着准星圈")
C.flyMouseAim(true)
airborne(st, jet)
st.aimYaw, st.aimPitch = 0, 0
R.run(1)
drag(25, 8)
R.run(0.4)
local aimV = (CFr.Angles(0, st.aimYaw, 0) * CFr.Angles(st.aimPitch, 0, 0)).LookVector
check(ang(cam.CFrame.LookVector, aimV) < 6, string.format("镜头顺着鼠标想去的方向（差 %.1f°）", ang(cam.CFrame.LookVector, aimV)))
local n0 = st.cf.LookVector
R.run(3)
check(ang(st.cf.LookVector, n0) > 10, string.format("飞机追过去了（转了 %.0f°）", ang(st.cf.LookVector, n0)))

print("④ 战雷鼠标瞄准、在地上：拨鼠标镜头转开，准星圈还在机头上")
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local d = AD.get("f16")
local hp = P.char.HumanoidRootPart.Position
local gpos = V3(hp.X + 60, G.airSurface(hp.X + 60, hp.Z) + d.gearH, hp.Z)
st, jet = board("f16", CF(gpos))
R.run(1.5)
check(st and st.ground == true, "停在地上")
if st and st.ground then
  C.flyMouseAim(true)
  R.run(0.5)
  local noseG = st.cf.LookVector
  drag(30, 10)
  R.run(0.3)
  local awayG = ang(cam.CFrame.LookVector, noseG)
  check(awayG > 20, string.format("地上拨鼠标：镜头转开 %.0f°", awayG))
  local aimG = (CFr.Angles(0, st.aimYaw, 0) * CFr.Angles(st.aimPitch, 0, 0)).LookVector
  check(ang(V3(aimG.X, 0, aimG.Z), V3(noseG.X, 0, noseG.Z)) < 5, string.format("准星圈还在机头上（差 %.1f°）", ang(V3(aimG.X, 0, aimG.Z), V3(noseG.X, 0, noseG.Z))))
  R.run(3)
  check(ang(cam.CFrame.LookVector, noseG) > 15, string.format("停 3 秒镜头还转开着（%.0f°）", ang(cam.CFrame.LookVector, noseG)))
end
print("⑤ 高速飞行的前方预加载（用户 11-28「飞机飞太快 地图加载跟不上 做一个流体预加载 根据飞机的速度和方向」）")
G.streaming = true   -- 模拟器里没开 streaming：当作开着（G.streamFocus 照样调，模拟器的 AddReplicationFocus 不管它）
C.flyMouseAim(false)
st, jet = board("f16", CF(0, gy + 1200, 0))
if st then
  airborne(st, jet)
  -- 11-28 收紧以后每秒 250 格以上才挂前方加载点：推满油门、给到 320 格 / 秒
  st.spd, st.vel = 320, st.vdir * 320
  st.thr, st.thrE = 100, 100
  jet.vel = st.vel
  R.run(1.5)
  local ap = G.airAhead and G.airAhead(jet)
  check(ap ~= nil, "开起来了：有一个前方加载点")
  if ap and jet.vel and jet.vel.Magnitude > 1 then
    local rel = ap.Position - jet.root.Position
    local want = math.min(jet.vel.Magnitude * 2.5, 2000)   -- 11-28「开飞机太卡了」收紧：2.5 秒、最远 2000 格
    check(math.abs(rel.Magnitude - want) < want * 0.3, string.format("在 2.5 秒后要到的地方（前面 %.0f 格，按速度该是 %.0f 格）", rel.Magnitude, want))
    check(rel.Unit:Dot(jet.vel.Unit) > 0.9, string.format("顺着飞的方向（夹角 %.0f°）", ang(rel, jet.vel)))
  end
  local lead = C.sceneryLead and C.sceneryLead()
  local vh = V3(st.vel.X, 0, st.vel.Z)
  check(lead ~= nil and lead.Magnitude > 50 and vh.Magnitude > 1 and lead.Unit:Dot(vh.Unit) > 0.9,
    string.format("树、石头摆的中心往前挪了 %.0f 格", lead and lead.Magnitude or 0))
  T.remoteAs(me, "Drive", { op = "exit" })
  R.run(1)
  check(G.airAhead(jet) == nil, "下了飞机：前方加载点撤了")
  local f = R.workspace:FindFirstChild("StreamAhead")
  check(f == nil or #f:GetChildren() == 0, "没有留下没人用的加载点")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
