-- 战雷式机载雷达（模拟器）：python3 tools/mock/run.py tools/mock/radar.lua
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   用户 11-27：「飞机雷达按型号照战雷做、能用键控制雷达方向」（雷达在 Radars.lua；锁定照战雷改手动：R / Alt+T 选目标、Alt+F 锁定）
--   ① 雷达屏（B 显）：歼-20 的 KLJ-5，选着霹雳-15 也不自动锁（原来一进座舱就锁上，锁着的画成 RadarLock 不算亮点，这一项一直数出 0 个）；
--      正对着飞过来的敌机在屏上有亮点；它侧着飞（把我放在 3 / 9 点：置零）就看不见
--   ② 霹雳-15（主动雷达弹）手动锁：屏上没有的锁不上；R 选中（「|—|」）、Alt+F 进单目标跟踪（STT）、再按解锁；锁着的那架侧着飞：
--      先按记忆外推（屏上 STT MEM、锁还在）、2 秒还没找回来丢锁、提示置零、不自己再锁
--   ③ 导弹：远时按发射机的雷达跟踪飞（数据链）；发射机丢了锁就往最后估的拦截点飞；近了自己开导引头——目标侧着飞（置零）超过半秒甩掉；迎头的打得中
--   ④ 箔条：开了导引头的雷达弹会被骗（置零时更容易），数据链阶段的不会
--   ⑤ Alt 组合键只给雷达：Alt+T 不切迎角限制、Alt+R 不换目标、Alt+F 不发导弹、按住 Alt+Q 不打舵、Alt+↑ / Alt+滚轮 不动油门（不按 Alt 照旧）
--   ⑥ 每架次重置、按科技树版本取雷达：关了雷达、换了量程，下一架照旧开着、量程最大；F-16A（TreeKey us_f16a）是 APG-66、
--      苏-30SM（歼-16 + ru_su30sm）是 N011M、不带 TreeKey 的 F-16 是 APG-68(V)5、苏-27（借苏-35S 的模型）是 N001
--   ⑦ 扫描区（F-16C 的 APG-68，照战雷机械扫描 120°/秒）：默认 ±60°×4 行一帧 4 秒（11-28 夜「有的飞机雷达扫描区域很窄的」：原来 2 行）；波束扫过才出亮点；扫描区外（机头上方 30°）扫一整帧也没有，
--      按住 Alt+↑ 把天线抬上去就扫到；Alt+C 回中、Alt+滚轮一格 2°、Alt+Z 换扫描方式（提示一帧几秒）；±30° 扫描按住 ←（11-28 起不用按 Alt）最多挪到 −30°、屏上两条竖线跟着；
--      扫描区外、万向架里的新目标锁不上，已经 STT 的出了扫描区照旧跟着
--   ⑧ 边扫边跟（TWS）：Alt+E 进 TWS，两架都成航迹（屏上两个小方块）；Alt+T 指定一条，雷达弹不用 STT 就锁上它、对方告警器不报锁定；
--      离上次航迹更新超过 1.3 秒（老的数据链有效期）再打，数据链照旧通（等一帧）；发射时对方不报导弹、导引头开机才报；对比：Alt+F STT 了对方马上报锁定
--   ⑨ 近战（ACM）：Alt+E 进近战、Alt+Z 换竖扫（屏上写 ACM VS）；13850 格外的不自动锁；机头上方 30°、3000 格的一帧以内自动 STT（选着雷达弹也好、
--      什么弹都好）；雷达锁定跟武器脱钩：换红外弹，导引头先咬雷达锁着的那架（不是离机头最近的那架）
--   ⑩ RCS：同样距离 F-22 看不见、苏-27 看得见，F-22 要近得多；侧面 RCS 大；敌我识别：友机亮点上一道横线、不轮到、锁不上
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

print("② 霹雳-15 照战雷手动锁：R 选目标、Alt+F 锁定（STT）；看得见才锁得上；侧飞先记忆外推，2 秒找不回来丢锁")
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
check(mode and mode.Text == "STT", "雷达屏写 STT（单目标跟踪，真机缩写：用户 11-27 定的）：" .. tostring(mode and mode.Text))
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
R.run(0.7)
check(st.lock ~= nil and st.rdLock ~= nil and st.rdLock.mem == true and mode.Text == "STT MEM" and st.lock.radarWhy == "notch",
  "侧飞 1.6 秒：雷达按记忆外推（屏上 " .. tostring(mode.Text) .. "），锁还在、不能发射（" .. tostring(st.lock and st.lock.radarWhy) .. "）")
local lost = T.runUntil(function() return st.lock == nil end, 2)
check(lost and st.rdLock == nil, "记忆外推 2 秒还没找回来：丢锁")
check(#T.texts(C.T("air.radarLostNotch")) > 0, "提示：目标置零，雷达丢失锁定")
R.run(0.5)
check(st.lock == nil and st.rdLock == nil, "丢了锁不自己再锁")

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
-- 置零半秒就甩掉（11-28 导弹能量：弹助推得快、一秒内冲近几百格，目标转出置零角以后照规则还能再咬上——只看一秒内甩掉过没有）
local shook = T.runUntil(function() return m2.tgt == nil end, 1.0)
check(shook, "目标侧着飞（置零）：导引头甩掉了")
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
G.flareRoll = function() return 0.01 end   -- 服务器的随机数（模拟器里脚本的 math 是开服时拷的一份，改测试这边的 math.random 管不到它）
T.key(Enum.KeyCode.X, true)
R.run(0.3)
T.key(Enum.KeyCode.X, false)
G.flareRoll = nil
check(far.tgt == jet, "数据链阶段：箔条骗不了")
local near = shoot(1500)
R.run(0.2)
check(near.active == true, "这枚开了导引头")
st.flareNext = 0
G.flareRoll = function() return 0.01 end
T.key(Enum.KeyCode.X, true)
R.run(0.3)
T.key(Enum.KeyCode.X, false)
G.flareRoll = nil
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
  return C.fly, e
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

print("⑦ 扫描区：F-16C 的 APG-68（照战雷机械扫描 120°/秒、默认 4 行）一帧几秒、波束扫过才出亮点、Alt 键挪天线")
local sF, jetF = fly2("f16", nil, 400)
check(sF ~= nil and sF.rd ~= nil and sF.rd.key == "apg68", "坐进 F-16C：APG-68(V)5（" .. tostring(sF and sF.rd and sF.rd.short) .. "）")
if not (sF and sF.rd and jetF) then T.summary() return end
local holdPos = sF.cf.Position
local hold2 = R.Heartbeat:Connect(function()   -- 摆平、朝 −Z，钉在原地
  if C.fly then
    C.fly.cf = CFr.lookAt(holdPos, holdPos + V3(0, 0, -1))
    C.fly.vdir, C.fly.spd, C.fly.vel = V3(0, 0, -1), 0, V3()
  end
end)
local RSt = C.radarState
local function dirOf(az, el)   -- 地平坐标（本机朝 −Z）：方位往右为正、俯仰往上为正
  local a, e = math.rad(az), math.rad(el)
  return V3(math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e))
end
local function placeFoe(az, el, dist, sp)   -- 摆到这个方向、朝我飞来（不置零）
  local d = dirOf(az, el)
  fly.p, fly.v = holdPos + d * dist, d * -(sp or 150)
end
-- 第二架敌机（⑧ 边扫边跟、⑨ 近战用）：先摆在身后（万向架外）
local foe2 = G.newEnt({ kind = "air", team = "def", cat = "air", hp = 900, size = V3(16, 6, 24), cf = CF(holdPos.X, holdPos.Y, holdPos.Z + 9000), air = true })
foe2.model:SetAttribute("Model", "su27")
local fly3 = { p = holdPos + V3(0, 0, 9000), v = V3() }
local conn2 = R.Heartbeat:Connect(function(dt)
  if foe2.alive then
    fly3.p = fly3.p + fly3.v * dt
    G.moveEnt(foe2, CFr.lookAt(fly3.p, fly3.p + (fly3.v.Magnitude > 1 and fly3.v or V3(0, 0, 1))))
    foe2.vel = fly3.v
  end
end)
local function placeFoe2(az, el, dist, sp)
  local d = dirOf(az, el)
  fly3.p, fly3.v = holdPos + d * dist, d * -(sp or 150)
end
placeFoe(0, 0, 40000, 0)   -- 先挪远（量程外）
R.run(0.5)
local function waitFrame(maxT)
  local f0 = RSt().frames
  return T.runUntil(function() return RSt().frames > f0 end, maxT)
end
waitFrame(6)
local t1 = R.clock()
waitFrame(6)
local t2 = R.clock()
check(math.abs((t2 - t1) - 4.0) < 0.1 and math.abs((RSt().frameT or 0) - 4.0) < 0.1,
  string.format("APG-68 默认扫描（±60°×4 行、120°/秒）扫一帧 %.2f 秒（4 秒；雷达记的 %.2f）", t2 - t1, RSt().frameT or -1))
local zoneT = gui:FindFirstChild("RadarZone", true)
check(zoneT and zoneT.Text == "120°x14°" and mode.Text == "RWS", "雷达屏写 RWS、扫描区照战雷写宽 × 高（±60° · 4 行 × 3.5° = 120°x14°）：" .. tostring(zoneT and zoneT.Text))
-- 波束在左边往右扫的时候把敌机摆到右前方 40°：等波束扫到 40° 那里才出亮点
T.runUntil(function() local s = RSt() return s.bar == 1 and s.dir > 0 and s.bAz < -40 end, 8)
placeFoe(40, 0, 6000)
R.run(1 / 30)
local bNow = RSt().bAz
check(not C.radarHas(sF, fem), string.format("刚摆到右前方 40°、波束还在 %.0f°：屏上没有它", bNow))
local got = T.runUntil(function() return C.radarHas(sF, fem) end, 5)
local bAt = RSt().bAz
check(got and math.abs(bAt - 40) <= 4.5, string.format("波束扫到那里（%.1f°）才出亮点（目标在 40°）", bAt))
-- 机头上方 30°：俯仰万向架里、扫描区外（默认 4 行只扫地平线上下七度）
placeFoe(0, 30, 5000)
R.run(5.5)
check(not C.radarHas(sF, fem), "机头上方 30°：在扫描区外，扫一整帧多（5.5 秒）屏上也没有")
local altL = gui:FindFirstChild("AltCover", true)
local alt0 = altL.Text
local elm = gui:FindFirstChild("AntennaEl", true)
local elY0 = elm.Position.Y.Scale
T.key(Enum.KeyCode.LeftAlt, true)
T.key(Enum.KeyCode.Up, true)
R.run(1.2)
T.key(Enum.KeyCode.Up, false)
T.key(Enum.KeyCode.LeftAlt, false)
check(math.abs(RSt().ctrEl - 30) < 0.6, string.format("按住 Alt+↑ 1.2 秒：扫描中心抬到 %.1f°（25°/秒）", RSt().ctrEl))
local got2 = T.runUntil(function() return C.radarHas(sF, fem) end, 4.5)
check(got2, "天线抬上去：一帧以内扫到上方的敌机")
check(elm.Position.Y.Scale < elY0 - 0.15 and altL.Text ~= alt0,
  string.format("屏上天线俯仰标记往上走了（%.2f → %.2f），扫描区盖住的海拔变了（%s → %s）", elY0, elm.Position.Y.Scale, alt0, altL.Text))
altKey(Enum.KeyCode.C)
check(RSt().ctrEl == 0 and RSt().ctrAz == 0, "Alt+C：天线回中")
T.key(Enum.KeyCode.LeftAlt, true)
R.as("client", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, 1) }, false) end)
T.key(Enum.KeyCode.LeftAlt, false)
check(math.abs(RSt().ctrEl - 2) < 1e-6, string.format("Alt+滚轮一格：天线俯仰 +2°（%.1f）", RSt().ctrEl))
altKey(Enum.KeyCode.Z)
check(RSt().scan == 2 and #T.texts(C.T("rd.scanT", "60", "2", "2.0")) > 0, "Alt+Z 换扫描方式：±60° · 2 行，提示一帧 2.0 秒")
altKey(Enum.KeyCode.Z)
-- 用户 11-28「飞机雷达偏转改成左右建控制吧」：左右偏转直接按 ← / →（不用按 Alt；↑ / ↓ 不按 Alt 还是油门）
local thrLR = sF.thr
T.key(Enum.KeyCode.Right, true)
R.run(0.25)
T.key(Enum.KeyCode.Right, false)
check(RSt().ctrAz > 8 and RSt().ctrAz < 12.5 and math.abs(sF.thr - thrLR) < 1e-6,
  string.format("不按 Alt 按住 → 0.25 秒：扫描中心往右挪到 %.1f°（40°/秒，模拟器按帧算多一点），油门没动", RSt().ctrAz))
T.key(Enum.KeyCode.Left, true)
R.run(1.5)
T.key(Enum.KeyCode.Left, false)
R.run(1 / 30)
local zl, zr = gui:FindFirstChild("ScanZoneL", true), gui:FindFirstChild("ScanZoneR", true)
check(RSt().scan == 3 and math.abs(RSt().ctrAz + 30) < 1e-6, string.format("±30° 扫描：按住 ← 1.5 秒挪到 %.0f°（40°/秒，最多 ±(60 − 30)°）", RSt().ctrAz))
T.key(Enum.KeyCode.LeftAlt, true)
T.key(Enum.KeyCode.Right, true)
R.run(0.25)
T.key(Enum.KeyCode.Right, false)
T.key(Enum.KeyCode.LeftAlt, false)
check(RSt().ctrAz > -22 and RSt().ctrAz < -17.5, string.format("按着 Alt 的 → 照旧能挪（%.1f°）", RSt().ctrAz))
T.key(Enum.KeyCode.Left, true)
R.run(0.5)
T.key(Enum.KeyCode.Left, false)
R.run(1 / 30)
check(math.abs(zl.Position.X.Scale) < 0.01 and math.abs(zr.Position.X.Scale - 0.5) < 0.01,
  string.format("屏上扫描区的两条竖线在 −60°、0°（%.2f、%.2f）", zl.Position.X.Scale, zr.Position.X.Scale))
placeFoe(-45, 0, 6000)
check(T.runUntil(function() return C.radarHas(sF, fem) end, 5), "左前方 45°：挪过去的扫描区扫到了")
placeFoe2(-50, 20, 6500)   -- 另一架：扫描区外（扫描区只到地平线上 9° 多，它在上面 20°）、万向架里，一直没扫到过
altKey(Enum.KeyCode.T)
altKey(Enum.KeyCode.F)
check(sF.rdLock ~= nil and sF.rdLock.em == fem, "Alt+T 选中、Alt+F 锁定：STT")
altKey(Enum.KeyCode.C)
R.run(1.5)
check(sF.rdLock ~= nil and sF.rdLock.em == fem and not sF.rdLock.mem, "扫描区回中（±30°）：−45° 的目标出了扫描区，STT 照旧跟着（只看万向架）")
altKey(Enum.KeyCode.F)
check(sF.rdLock == nil and C.flyRadarLockOn(foe2.model) == false and sF.rdLock == nil, "扫描区外、万向架里的新目标（上方 20°，没扫到过）锁不上")

print("⑧ 边扫边跟（TWS）：两批航迹；对指定航迹打雷达弹不用 STT，对方告警器不报锁定、导引头开机才报导弹")
foe.model:SetAttribute("Model", "mig29")   -- ⑧ ⑨ 测雷达本身：靶机换成 5 m² 的米格-29（F-22 隐身了，远处扫不到；⑩ 再换回去测 RCS）
foe.driver = { pl = me }   -- 给靶机一个「驾驶员」：服务器发给它的 rwrLock / rwr 记在 R.sent 里
foe.hp = 900
local slotR, slotI
for i, w2 in ipairs(sF.wl) do
  local ww = AD.W[w2]
  if ww and ww.seeker == "radar" and not slotR then slotR = i end
  if ww and ww.seeker == "ir" and not slotI then slotI = i end
end
check(slotR ~= nil and slotI ~= nil, "F-16C 挂着雷达弹、红外弹（" .. tostring(slotR and sF.wl[slotR]) .. "、" .. tostring(slotI and sF.wl[slotI]) .. "）")
sF.wi = slotR or sF.wi
local n0 = #R.sent
altKey(Enum.KeyCode.E)
sF.rdSel = nil   -- ⑦ 里选着的那架先不算（不然一成航迹就是指定的）
R.run(1 / 30)
check(RSt().mode == "tws" and mode.Text == "TWS", "Alt+E：边扫边跟（屏上 " .. tostring(mode.Text) .. "）")
placeFoe(-10, 0, 14000, 120)   -- 远一点：等锁、等数据链空档的这十几秒里它飞近了，打出去时还在导引头开机的距离（6500 格）外
placeFoe2(20, 0, 8000, 100)
local two = T.runUntil(function() return RSt().tracks >= 2 end, 9)
local nSq = 0
for _, b in ipairs(gui:GetDescendants()) do if b.Name == "TwsTrack" and T.visible(b) then nSq = nSq + 1 end end
check(two and RSt().tracks == 2 and nSq == 2, string.format("两架都成了航迹（%d 批，屏上 %d 个小方块）", RSt().tracks, nSq))
altKey(Enum.KeyCode.T)
check(sF.rdSel == fem and sF.rdLock == nil, "Alt+T：指定离扫描中心近的那条（没进 STT）")
local wR = AD.W[sF.wl[sF.wi]]
local twsLock = T.runUntil(function() return sF.lock ~= nil and sF.lock.tws == true and sF.lockT >= (wR.lockTime or 1) end, 9)
check(twsLock and sF.rdLock == nil, string.format("雷达弹锁上了指定航迹（不用 STT；进度 %.1f / %.1f 秒）", sF.lockT or 0, wR.lockTime or 1))
local function sentOps(i0, op)
  local k = 0
  for i = i0 + 1, #R.sent do
    local x = R.sent[i]
    if x.name == "Drive" and type(x.args[1]) == "table" and x.args[1].op == op then k = k + 1 end
  end
  return k
end
local pinged = T.runUntil(function() return jetF.radarTgt == foe.id and jetF.radarTws ~= nil end, 5)
check(pinged and sentOps(n0, "rwrLock") == 0, string.format("服务器按边扫边跟记下数据链（一帧 %s 秒），对方告警器没报锁定（rwrLock %d 次）", tostring(jetF.radarTws), sentOps(n0, "rwrLock")))
-- 离上次航迹更新超过 1.3 秒（原来的数据链有效期）再打
T.runUntil(function() return R.clock() - (jetF.radarT or 0) > 1.6 end, 5)
local gap = R.clock() - (jetF.radarT or 0)
local n1 = #R.sent
T.key(Enum.KeyCode.F, true)
local shot = nil
T.runUntil(function()
  for _, s2 in ipairs(G.shots) do if s2.byEnt == jetF.id and s2.ref == foe then shot = s2 end end
  return shot ~= nil
end, 1)
T.key(Enum.KeyCode.F, false)
-- 等导弹飞第一步（服务器按 Config.Tick = 0.1 秒一步推演导弹，arhStep 那时才算数据链）
T.runUntil(function() return shot == nil or shot.dl ~= nil or shot.active == true end, 0.5)
check(shot ~= nil and shot.dl == true and not shot.active, string.format("打出去了：离上次航迹更新 %.1f 秒（原来 1.3 秒就断），数据链照旧通（等一帧）", gap))
check(shot ~= nil and sentOps(n1, "rwr") == 0, "发射的时候对方告警器不报导弹（边扫边跟打的）")
local act = shot ~= nil and T.runUntil(function() return shot.active == true end, 8)   -- 靶机钉在原地（发射速度 0）：11-28 导弹能量以后助推三秒才到满速，飞到开机距离要四秒多
R.run(1 / 30)
check(act and sentOps(n1, "rwr") >= 1, "导引头开机：对方这时才收到「导弹来袭」（rwr " .. sentOps(n1, "rwr") .. " 次）")
if shot then shot.life = 0 end
placeFoe(-10, 0, 8000)   -- 挪近一点（服务器 12000 格以内才转告锁定）
R.run(0.2)
local n2 = #R.sent
altKey(Enum.KeyCode.F)
R.run(0.3)
check(sF.rdLock ~= nil and sF.rdLock.em == fem and sentOps(n2, "rwrLock") >= 1 and sF.lock ~= nil and sF.lock.em == fem and sF.lock.tws == false,
  "对比：指定航迹上按 Alt+F 进 STT，对方马上报锁定（rwrLock " .. sentOps(n2, "rwrLock") .. " 次），弹的锁改成跟着 STT")
foe.driver = nil

print("⑨ 近战（ACM）：竖扫自动锁近处的；雷达锁定跟武器脱钩")
altKey(Enum.KeyCode.E)
altKey(Enum.KeyCode.Z)
R.run(1 / 30)
check(RSt().mode == "acm" and RSt().acm == "vert" and sF.rdLock == nil and mode.Text == "ACM VS", "Alt+E 进近战（断开了 STT）、Alt+Z 换竖扫：屏上 " .. tostring(mode.Text))
placeFoe(0, 30, 16000)
placeFoe2(12, 0, 9000)   -- 竖扫区外（方位 ±5°）
R.run(3.5)
check(sF.rdLock == nil, "竖扫区里、13850 格外的不自动锁；区外的也不锁")
placeFoe(0, 30, 3000)
local tA = R.clock()
local acq = T.runUntil(function() return sF.rdLock ~= nil end, 3.5)
check(acq and sF.rdLock.em == fem and mode.Text == "STT", string.format("机头上方 30°、3000 格：%.1f 秒自动锁上（STT；竖扫一帧 3 秒）", R.clock() - tA))
R.run(0.2)
check(sF.lock ~= nil and sF.lock.em == fem, "选着雷达弹：弹的锁跟着雷达锁的那架")
placeFoe2(3, 0, 2500, 60)   -- 离机头更近的另一架：红外弹自己挑的话挑它
sF.wi = slotI or sF.wi
sF.lock, sF.lockT = nil, 0
R.run(0.3)
check(sF.lock ~= nil and sF.lock.em == fem and sF.lock.slaved == true, "换红外弹：导引头先咬雷达锁着的那架（不是离机头最近的那架）")
print("⑩ RCS、敌我识别（用户 11-28「引入一下rcs这个概念」「iff」）")
foe.model:SetAttribute("Model", "f22")
altKey(Enum.KeyCode.E)   -- 近战 → RWS
R.run(1 / 30)
sF.rdLock, sF.lock, sF.rdSel = nil, nil, nil
local Rr = sF.rd.range
placeFoe(0, 0, Rr * 0.6)       -- F-22 迎头、0.6 倍量程
placeFoe2(10, 0, Rr * 0.6)     -- 苏-27 同距离
R.run(0.3)
local okF, whyF = C.radarSees(sF, fem)
local okS = C.radarSees(sF, foe2.model)
check(not okF and whyF == "range" and okS == true, string.format("同在 %.0f 格：F-22（0.0003 m²，量程只剩 %.0f%%）看不见（%s）、苏-27（15 m²）看得见",
  Rr * 0.6, (C.radarRcsK(fem, sF) or 0) * 100, tostring(whyF)))
placeFoe(0, 0, Rr * 0.22)
R.run(0.3)
check(C.radarSees(sF, fem) == true, "F-22 近到 0.22 倍量程才看得见")
local kNose = C.radarRcsK(foe2.model, sF)
fly3.v = V3(1, 0, 0) * 150   -- 苏-27 侧过来（机头朝侧面）
R.run(0.2)
check(C.radarRcsK(foe2.model, sF) > kNose * 1.2, string.format("侧面 RCS 大：量程倍数迎头 %.2f → 侧面 %.2f", kNose, C.radarRcsK(foe2.model, sF)))
-- 敌我识别：苏-27 改成我方，F-22 挪远
placeFoe(0, 0, 60000, 0)
foe2.model:SetAttribute("Team", "atk")
placeFoe2(5, 0, 6000)
waitFrame(9)
waitFrame(9)
check(C.radarIffFriend(foe2.model) == true, "APG-68 带敌我识别：认得出这架是友机")
local iffShown = false
for _, d in ipairs(C.radarGui:GetDescendants()) do
  if d.Name == "Iff" and d:IsA("Frame") and d.Visible and d.Parent and d.Parent.Visible then iffShown = true end
end
check(iffShown, "雷达屏上友机的亮点上面一道横线")
check(C.radarNext(sF, nil) ~= foe2.model, "R / Alt+T 不轮到友机")
check(C.radarStt(sF, foe2.model) == false and sF.rdLock == nil, "友机锁不上（提示「敌我识别：友机」）")
foe2.model:SetAttribute("Team", "def")
hold2:Disconnect()
conn2:Disconnect()
conn:Disconnect()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
