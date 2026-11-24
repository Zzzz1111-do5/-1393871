-- 战雷式机载雷达（模拟器）：python3 tools/mock/run.py tools/mock/radar.lua
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   ① 雷达屏（B 显）：歼-20 的 KLJ-5，正对着飞过来的敌机在屏上有亮点；它侧着飞（把我放在 3 / 9 点：置零）就看不见
--   ② 霹雳-15（主动雷达弹）锁定：雷达看得见才锁得上（STT）；锁着的那架侧着飞超过 1 秒丢锁、提示置零
--   ③ 导弹：远时按发射机的雷达跟踪飞（数据链）；发射机丢了锁就往最后估的拦截点飞；近了自己开导引头——目标侧着飞（置零）超过半秒甩掉；迎头的打得中
--   ④ 箔条：开了导引头的雷达弹会被骗（置零时更容易），数据链阶段的不会
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
check(st ~= nil and st.pilot and st.d.radar ~= nil, "坐进歼-20，有雷达：" .. tostring(st and st.d.radar and st.d.radar.name))
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
setFoe(p0 + V3(0, 0, -5000), V3(0, 0, 220))   -- 正对着飞过来
R.run(2.5)
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
local ok2, why2 = C.radarSees(st, fem)
check(ok2 == false and why2 == "notch", "侧着飞：雷达看不见（" .. tostring(why2) .. "）")
R.run(3)
check(blipN() == 0, "过一会儿屏上的亮点暗掉了（" .. blipN() .. "）")

print("② 霹雳-15 锁定：看得见才锁得上；侧飞超过 1 秒丢锁")
local slot
for i, w in ipairs(st.wl) do if AD.W[w] and AD.W[w].seeker == "radar" then slot = i end end
check(slot ~= nil, "挂着雷达弹（" .. tostring(slot and st.wl[slot]) .. "）")
st.wi = slot
st.lock, st.lockT = nil, 0
R.run(1)
check(st.lock == nil, "侧飞的目标锁不上")
setFoe(p0 + V3(0, 0, -5000), V3(0, 0, 220))
R.run(2.6)
local w = AD.W[st.wl[st.wi]]
check(st.lock ~= nil and st.lockT >= (w.lockTime or 1), string.format("迎头的锁上了（进度 %.1f / %.1f 秒）", st.lockT or 0, w.lockTime or 1))
local mode = gui:FindFirstChild("RadarMode", true)
check(mode and string.sub(mode.Text, 1, 3) == "TRK", "雷达屏写 TRK（跟踪；11-24 夜照战雷改了说法，原来写 STT）：" .. tostring(mode and mode.Text))
check(jet.radarTgt == foe.id, "服务器知道雷达跟踪着它（数据链）")
setFoe(fly.p, V3(220, 0, 0))
R.run(0.6)
check(st.lock ~= nil, "侧飞 0.6 秒：锁还在")
R.run(1.0)
check(st.lock == nil, "侧飞超过 1 秒：丢锁")
check(#T.texts(C.T("air.radarLostNotch")) > 0, "提示：目标置零，雷达丢失锁定")

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
setFoe(p0 + V3(0, 0, -7000), V3(0, 0, 150))
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
hold:Disconnect()
conn:Disconnect()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
