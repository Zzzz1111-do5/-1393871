-- 战雷式机载雷达（模拟器）：python3 tools/mock/run.py tools/mock/radar.lua
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   用户 11-27：「飞机雷达按型号照战雷做、能用键控制雷达方向」（雷达在 Radars.lua；锁定照战雷改手动：R / Alt+T 选目标、Alt+F 锁定）
--   ① 雷达屏（B 显）：歼-20 的 KLJ-5，选着霹雳-15 也不自动锁（原来一进座舱就锁上，锁着的画成 RadarLock 不算亮点，这一项一直数出 0 个）；
--      正对着飞过来的敌机在屏上有亮点；它侧着飞（把我放在 3 / 9 点：置零）就看不见
--   ② 霹雳-15（主动雷达弹）手动锁：屏上没有的锁不上；R 选中（「|—|」）、Alt+F 进单目标跟踪（STT）、再按解锁；锁着的那架侧着飞超过 1 秒丢锁、提示置零、不自己再锁
--   ③ 导弹：远时按发射机的雷达跟踪飞（数据链）；发射机丢了锁就往最后估的拦截点飞；近了自己开导引头——目标侧着飞（置零）超过半秒甩掉；迎头的打得中
--   ④ 箔条：开了导引头的雷达弹会被骗（置零时更容易），数据链阶段的不会
--   ⑤ Alt 组合键只给雷达：Alt+T 不切迎角限制、Alt+R 不换目标、Alt+F 不发导弹、按住 Alt+Q 不打舵、Alt+↑ / Alt+滚轮 不动油门（不按 Alt 照旧）
--   ⑥ 每架次重置、按科技树版本取雷达：关了雷达、换了量程，下一架照旧开着、量程最大；F-16A（TreeKey us_f16a）是 APG-66、
--      苏-30SM（歼-16 + ru_su30sm）是 N011M、不带 TreeKey 的 F-16 是 APG-68(V)5、苏-27（借苏-35S 的模型）是 N001
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6501, true)
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
T.actAs(me, "deploy", "rifle", "base")
R.run(2)
T.runUntil(function() return G.round.phase == "battle" end, 120)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local gy = math.max(G.Map.ground(0, 0), 0)
local p0 = V3(0, gy + 1500, 0)
local jet = G.spawnAircraft("atk", "j20", CF(p0.X, p0.Y, p0.Z), nil, P)
P.char:PivotTo(CF(p0.X + 4, p0.Y, p0.Z))
T.act("enterVeh", jet.id)
R.run(0.2)
local st = C.fly
check(st ~= nil and st.pilot and st.rd ~= nil and st.rd == st.d.radar, "坐进歼-20，有雷达：" .. tostring(st and st.rd and st.rd.name))
if not st then T.summary() return end
-- 摆平、朝 −Z，停在原地（测雷达，不管飞）：每帧把飞机放回去
st.ground, st.gear, st.gearWant = false, 0, 0
local holdV = V3()   -- 报给服务器的速度（位置照旧钉住）：④ 里给它一个迎着导弹的速度，不然静止的靶子在导引头看来就是置零
local hold = R.Heartbeat:Connect(function()
  if C.fly then
    C.fly.cf = CFr.lookAt(p0, p0 + V3(0, 0, -1))
    C.fly.vdir, C.fly.spd, C.fly.vel = V3(0, 0, -1), 0, holdV
  end
end)
-- 敌机：前方 5000 格，速度按测的情况给
local foe = G.newEnt({ kind = "air", team = "def", cat = "air", hp = 900, size = V3(16, 6, 24), cf = CF(p0.X, p0.Y, p0.Z - 5000), air = true })
foe.model:SetAttribute("Model", "f22")
local fly = { p = p0 + V3(0, 0, -5000), v = V3(0, 0, 200) }
local conn = R.Heartbeat:Connect(function(dt)
  if foe.alive then
    fly.p = fly.p + fly.v * dt
    G.moveEnt(foe, CFr.lookAt(fly.p, fly.p + (fly.v.Magnitude > 1 and fly.v or V3(0, 0, 1))))
    foe.vel = fly.v
  end
end)
local function setFoe(pos, vel)
  fly.p, fly.v = pos, vel
  R.run(0.3)
end

print("① 雷达屏：迎头的看得见，侧着飞（置零）看不见")
local w0 = AD.W[st.wl[st.wi]]
setFoe(p0 + V3(0, 0, -5000), V3(0, 0, 220))   -- 正对着飞过来
R.run(2.5)
check(w0 and w0.seeker == "radar" and st.lock == nil, "选着霹雳-15（" .. tostring(st.wl[st.wi]) .. "）也不自动锁：照战雷手动锁")
local gui = C.radarGui
local fem = foe.model
local ok1, why1 = C.radarSees(st, fem)
check(gui ~= nil and gui.Enabled, "雷达屏开着")
local function blipN()
  local n = 0
  for _, b in ipairs(gui:GetDescendants()) do if b.Name == "Blip" and b.Visible then n = n + 1 end end
  return n
end
check(ok1 == true, "迎头飞来：雷达看得见（" .. tostring(why1) .. "）")
check(blipN() >= 1, "雷达屏上有亮点（" .. blipN() .. "）")
local nm = gui:FindFirstChild("RadarName", true)
check(nm ~= nil and nm.Text:find("KLJ", 1, true) ~= nil, "屏上写着雷达型号：" .. tostring(nm and nm.Text))
setFoe(p0 + V3(0, 0, -5000), V3(220, 0, 0))   -- 横着飞：把我放在它的 3 / 9 点
-- 敌机的速度按位置差平滑（Radar.lua velOf）：KLJ-5 的置零门限 40 格 / 秒（原来 45），要零点几秒才认出它侧着飞
local ok2, why2 = C.radarSees(st, fem)
T.runUntil(function() ok2, why2 = C.radarSees(st, fem) return ok2 == false end, 1)
check(ok2 == false and why2 == "notch", "侧着飞：雷达看不见（" .. tostring(why2) .. "）")
R.run(3)
check(blipN() == 0, "过一会儿屏上的亮点暗掉了（" .. blipN() .. "）")

print("② 霹雳-15 照战雷手动锁：R 选目标、Alt+F 锁定；看得见才锁得上；侧飞超过 1 秒丢锁")
local function altKey(code)   -- 按住 Alt 点一下
  T.key(Enum.KeyCode.LeftAlt, true)
  T.tap(code)
  T.key(Enum.KeyCode.LeftAlt, false)
end
local slot
for i, w in ipairs(st.wl) do if AD.W[w] and AD.W[w].seeker == "radar" then slot = i end end
check(slot ~= nil, "挂着雷达弹（" .. tostring(slot and st.wl[slot]) .. "）")
st.wi = slot
st.lock, st.lockT, st.rdSel = nil, 0, nil
R.run(1)
check(st.lock == nil, "侧飞的目标锁不上")
altKey(Enum.KeyCode.F)
check(st.lock == nil and #T.texts(C.T("rd.noTgt")) > 0, "雷达屏上没有：Alt+F 锁不上，提示「雷达屏上没有目标」")
setFoe(p0 + V3(0, 0, -5000), V3(0, 0, 220))
local onScope = T.runUntil(function() return C.radarHas(st, fem) end, 3)
check(onScope, "迎头飞来：扫到了，雷达屏上有它")
R.run(1)
check(st.lock == nil, "屏上有目标、选着雷达弹：还是不自动锁")
T.tap(Enum.KeyCode.R)
check(st.rdSel == fem and st.lock == nil, "R 选中它（还没锁）")
R.run(1 / 30)
local selOn = false
for _, b in ipairs(gui:GetDescendants()) do if b.Name == "SelL" and T.visible(b) then selOn = true end end
check(selOn, "雷达屏上选中的那个两边加竖线「|—|」")
altKey(Enum.KeyCode.F)
check(st.lock ~= nil and st.lock.em == fem, "Alt+F 锁定：进单目标跟踪")
R.run(2.6)
local w = AD.W[st.wl[st.wi]]
check(st.lock ~= nil and st.lockT >= (w.lockTime or 1), string.format("迎头的锁上了（进度 %.1f / %.1f 秒）", st.lockT or 0, w.lockTime or 1))
local mode = gui:FindFirstChild("RadarMode", true)
check(mode and string.sub(mode.Text, 1, 3) == "TRK", "雷达屏写 TRK（跟踪；11-24 夜照战雷改了说法，原来写 STT）：" .. tostring(mode and mode.Text))
check(jet.radarTgt == foe.id, "服务器知道雷达跟踪着它（数据链）")
altKey(Enum.KeyCode.F)
check(st.lock == nil and st.rdSel == fem, "再按 Alt+F 解锁（还选着它）")
R.run(0.5)
check(st.lock == nil, "解了锁不自己再锁上")
altKey(Enum.KeyCode.F)
check(st.lock ~= nil, "Alt+F 又锁上")
R.run(0.3)
setFoe(fly.p, V3(220, 0, 0))
R.run(0.6)
check(st.lock ~= nil, "侧飞 0.6 秒：锁还在")
R.run(1.0)
check(st.lock == nil, "侧飞超过 1 秒：丢锁")
check(#T.texts(C.T("air.radarLostNotch")) > 0, "提示：目标置零，雷达丢失锁定")
R.run(0.5)
check(st.lock == nil, "丢了锁不自己再锁")

print("③ 导弹：数据链、惯导、开导引头、被置零甩掉")
-- 客户端换成不是雷达弹的那格（不然它又自己锁上、一直报 lockOn，数据链断不了）；这一段的数据链由测试直接写 jet.radarT
for i, w2 in ipairs(st.wl) do if AD.W[w2] and AD.W[w2].seeker == "ir" then st.wi = i break end end   -- 红外弹那格（选炮格的话 F 打的还是第一种挂弹）
st.lock, st.lockT = nil, 0
R.run(0.6)
local pl = AD.W.pl15
local function launch(from, vel)
  return G.launch({ kind = "missile", pos = from, vel = vel, w = pl, src = { team = "atk", name = "test" }, ignore = {}, life = 20,
    step = G.airGuideMissile, age = 0, tgt = foe, tgId = foe.id, byEnt = jet.id, ref = foe })
end
-- 远：9500 格（霹雳-15 开导引头的距离 11-25 照真实尺度放大成 2800 × 2.5 = 7000 格以后，原来 7000 格的靶子一打出去就开机，走不到数据链）
setFoe(p0 + V3(0, 0, -9500), V3(0, 0, 150))
jet.radarTgt, jet.radarT = foe.id, 1e12   -- 很大的数：一直算「刚报过」（服务器的时钟和测试脚本的 os.clock 不是一个）
local m1 = launch(p0 + V3(0, -10, -30), V3(0, 0, -700))
R.run(0.4)
check(m1.dl == true and m1.tgt == foe, "远：按发射机的雷达跟踪飞（数据链）")
jet.radarT = -1e12   -- 发射机丢了锁（很久没报）
R.run(0.4)
check(m1.tgt == nil and m1.aimPt ~= nil, "发射机丢锁：往最后估的拦截点飞（惯导）")
-- 近处：直接放一枚在目标前方 1500 格（比开导引头的距离近），目标侧着飞
setFoe(p0 + V3(0, 0, -6000), V3(240, 0, 0))
local m2 = launch(fly.p + V3(0, 0, 1500), V3(0, 0, -700))
R.run(0.2)
check(m2.active == true, "近了：开导引头")
R.run(0.8)
check(m2.tgt == nil, "目标侧着飞（置零）：导引头甩掉了")
-- 迎头的：打得中
setFoe(p0 + V3(0, 0, -6000), V3(0, 0, 200))
local hp0 = foe.hp
local m3 = launch(fly.p + V3(0, 0, 1800), V3(0, 0, -700))
T.runUntil(function() return foe.hp < hp0 or not foe.alive end, 6)
check(foe.hp < hp0 or not foe.alive, string.format("迎头飞来的：打中了（血 %d → %d）", hp0, math.floor(foe.alive and foe.hp or 0)))
for _, s in ipairs(G.shots) do if s == m1 or s == m2 or s == m3 then s.life = 0 end end

print("④ 箔条：开了导引头的会被骗，数据链阶段的不会")
holdV = V3(0, 0, -200)
R.run(0.5)
-- 拿自己这架当靶子：从前方打一枚霹雳-15 过来，按 X 放诱饵弹（随机数固定成 0.01：只要有机会就骗得到）
local rnd = math.random
local function shoot(dist)
  local tp = jet.root.CFrame.Position
  return G.launch({ kind = "missile", pos = tp + V3(0, 0, -dist), vel = V3(0, 0, 700), w = pl, src = { team = "def", name = "test" }, ignore = {}, life = 20,
    step = G.airGuideMissile, age = 0, tgt = jet, tgId = jet.id, byEnt = foe.id, ref = jet })
end
foe.radarTgt, foe.radarT = jet.id, 1e12
local far = shoot(6000)
R.run(0.2)
math.random = function(a, b) if a then return rnd(a, b) end return 0.01 end
T.key(Enum.KeyCode.X, true)
R.run(0.3)
T.key(Enum.KeyCode.X, false)
math.random = rnd
check(far.tgt == jet, "数据链阶段：箔条骗不了")
local near = shoot(1500)
R.run(0.2)
check(near.active == true, "这枚开了导引头")
st.flareNext = 0
math.random = function(a, b) if a then return rnd(a, b) end return 0.01 end
T.key(Enum.KeyCode.X, true)
R.run(0.3)
T.key(Enum.KeyCode.X, false)
math.random = rnd
check(near.tgt ~= jet and near.tgt and near.tgt.decoy, "开了导引头的被箔条骗走了")
for _, s in ipairs(G.shots) do if s == far or s == near then s.life = 0 end end
holdV = V3()

print("⑤ Alt 组合键只给雷达：不再串成 T 迎角限制、R 换目标、F 发导弹、Q 方向舵、↑ / 滚轮 油门")
local UIS = R.services.UserInputService
local nNext, nextF = 0, C.flyNextTarget
C.flyNextTarget = function(...) nNext = nNext + 1 return nextF(...) end   -- 数一数「换目标」被调了几次（Fly.lua 的 R、Radar.lua 的 Alt+T 都走它）
local ovr0 = st.ovr
altKey(Enum.KeyCode.T)
check(st.ovr == ovr0 and nNext == 1, string.format("Alt+T：选雷达目标（换目标 %d 次），迎角限制没动（%s）", nNext, tostring(st.ovr)))
T.tap(Enum.KeyCode.T)
check(st.ovr ~= ovr0, "不按 Alt 的 T 照旧切迎角限制")
T.tap(Enum.KeyCode.T)
altKey(Enum.KeyCode.R)
check(C.radarOn() == false and nNext == 1, "Alt+R：只开关雷达，不换目标（换目标 " .. nNext .. " 次）")
altKey(Enum.KeyCode.R)
check(C.radarOn() == true, "再按 Alt+R 雷达又开了")
T.tap(Enum.KeyCode.R)
check(nNext == 2, "不按 Alt 的 R 照旧换目标")
C.flyNextTarget = nextF
T.key(Enum.KeyCode.LeftAlt, true)
T.key(Enum.KeyCode.F, true)
check(st.missile ~= true, "Alt+F：是雷达锁定，不发导弹")
T.key(Enum.KeyCode.F, false)
T.key(Enum.KeyCode.Q, true)
R.run(0.4)
local kyAlt = st.kY or 0
T.key(Enum.KeyCode.Q, false)
T.key(Enum.KeyCode.LeftAlt, false)
R.run(0.2)
T.key(Enum.KeyCode.Q, true)
R.run(0.4)
local kyQ = st.kY or 0
T.key(Enum.KeyCode.Q, false)
R.run(0.3)
check(math.abs(kyAlt) < 0.01 and kyQ < -0.3, string.format("按住 Alt+Q 不打舵（杆量 %.2f），只按 Q 打左舵（%.2f）", kyAlt, kyQ))
st.thr = 60
T.key(Enum.KeyCode.LeftAlt, true)
T.key(Enum.KeyCode.Up, true)
R.run(0.4)
local thrAlt = st.thr
T.key(Enum.KeyCode.Up, false)
R.as("client", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, 1) }, false) end)
local thrWheelAlt = st.thr
T.key(Enum.KeyCode.LeftAlt, false)
R.as("client", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, 1) }, false) end)
local thrWheel = st.thr
T.key(Enum.KeyCode.Up, true)
R.run(0.3)
T.key(Enum.KeyCode.Up, false)
check(math.abs(thrAlt - 60) < 0.01 and math.abs(thrWheelAlt - 60) < 0.01, string.format("按住 Alt 的 ↑、滚轮不动油门（%.1f / %.1f）", thrAlt, thrWheelAlt))
check(thrWheel > thrWheelAlt + 4 and st.thr > thrWheel + 5, string.format("不按 Alt 照旧：滚轮 %.1f → %.1f，↑ → %.1f", thrWheelAlt, thrWheel, st.thr))
st.thr = 85

print("⑥ 每架次重置；按科技树版本取雷达")
altKey(Enum.KeyCode.R)
altKey(Enum.KeyCode.Q)
R.run(0.2)
local rng = gui:FindFirstChild("RadarRange", true)
check(C.radarOn() == false, "这一架把雷达关了、量程换小了")
hold:Disconnect()   -- 下面换的几架自己飞（别把它们拽回 p0：服务器会当成瞬移）
local function fly2(id, treeKey, dx)
  T.tap(Enum.KeyCode.Space)   -- 下飞机
  R.run(1)
  local pos = p0 + V3(dx, 0, 300)
  local e = G.spawnAircraft("atk", id, CF(pos.X, pos.Y, pos.Z), nil, P)
  if e and treeKey then e.model:SetAttribute("TreeKey", treeKey) end   -- 科技树出的车（Tech.lua 出生以后写 TreeKey）
  P.char:PivotTo(CF(pos.X + 4, pos.Y, pos.Z))
  R.run(0.2)
  if e then T.act("enterVeh", e.id) end
  R.run(0.4)
  return C.fly
end
local s2 = fly2("f16", "us_f16a", 80)
local nm2 = gui:FindFirstChild("RadarName", true)
check(s2 ~= nil and s2 ~= st and s2.rd and s2.rd.short == "APG-66", "F-16A（TreeKey us_f16a）：APG-66（" .. tostring(s2 and s2.rd and s2.rd.short) .. "）")
check(C.radarOn() == true and rng and rng.Text == string.format("%.0f km", s2.rd.range / AD.M / 1000), "换了一架：雷达开着、量程最大（" .. tostring(rng and rng.Text) .. "）")
check(nm2 and nm2.Text == "APG-66", "雷达屏上写 APG-66：" .. tostring(nm2 and nm2.Text))
local s3 = fly2("j16", "ru_su30sm", 160)
check(s3 and s3.rd and s3.rd.short == "N011M" and nm2.Text == "N011M", "苏-30SM（歼-16 + ru_su30sm）：N011M（" .. tostring(s3 and s3.rd and s3.rd.short) .. "）")
local s4 = fly2("f16", nil, 240)
check(s4 and s4.rd and s4.rd.short == "APG-68(V)5", "不带 TreeKey 的 F-16：APG-68(V)5（" .. tostring(s4 and s4.rd and s4.rd.short) .. "）")
local s5 = fly2("su27", nil, 320)
check(s5 and s5.rd and s5.rd.short == "N001", "苏-27（借苏-35S 的模型）：N001（" .. tostring(s5 and s5.rd and s5.rd.short) .. "）")
conn:Disconnect()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
