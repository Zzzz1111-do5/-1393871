-- 战雷式开飞机的手感（用户 11-25 晚：「像纸片、薯片一样脆，很丝滑很脆，但又不会觉得这个飞机没有质量」）：
--   python3 tools/mock/run.py tools/mock/wtcrisp.lua
--   机头这一层要脆：① 按住 D，0.2 秒内滚转快到头；松手后 0.25 秒内停住、多滚不过 20°（原来要 0.45 秒、多滚三十来度）
--   ② 按住 S 拉杆：0.5 秒内过载起来、不冲过头
--   航迹这一层要沉：③ 拉杆时机头先转、航迹慢半拍跟着（迎角是正的）；一直拉着急转，速度往下掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)

local me = T.join("P1", 9801, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
T.leaveMenu()
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
R.run(1)
local C = T.C

T.act("testDrive", "cn_j10c")
T.runUntil(function() return C.fly ~= nil end, 20)
R.run(1)
local st = C.fly
check(st ~= nil, "坐进了试驾的歼-10C")
if not st then T.summary() return end
local d = st.d
-- 摆到天上平飞（同 wtflight.lua）：高 900 格、军推 85% 的速度
local function levelOff()
  local p = st.cf.Position
  local h = math.max(G.Map.ground(p.X, p.Z), 0) + 900
  local fw = st.cf.LookVector
  local hz = V3(fw.X, 0, fw.Z)
  if hz.Magnitude < 0.1 then hz = V3(0, 0, -1) end
  st.cf = R.CFrame.lookAt(V3(p.X, h, p.Z), V3(p.X, h, p.Z) + hz.Unit)
  st.ground, st.cat, st.trap = false, nil, nil
  st.spd = d.vMil * 0.85
  st.vdir = st.cf.LookVector
  st.vel = st.vdir * st.spd
  st.thr, st.thrE, st.gearWant, st.gear = 90, 90, 0, 0
  st.pr, st.rr, st.yr = 0, 0, 0
  st.kP, st.kR, st.kY = 0, 0, 0
end
levelOff()
R.run(1)
levelOff()
R.run(0.3)
local function bankDeg() return math.deg(math.asin(clamp(st.cf.RightVector.Y, -1, 1))) end
local function rollRateDeg() return math.deg(st.rr) end
local ROLLmax = math.deg(math.rad(d.roll) * 0.75)

print("① 按住 D 滚转、松手")
T.key(Enum.KeyCode.D, true)
local t, t90 = 0, nil
while t < 0.6 do
  R.run(1 / 60)
  t = t + 1 / 60
  if not t90 and math.abs(rollRateDeg()) > 0.85 * ROLLmax * 0.9 then t90 = t end
end
local rateHeld = math.abs(rollRateDeg())
local bank0 = bankDeg()
T.key(Enum.KeyCode.D, false)
local tStop, extra = nil, 0
t = 0
while t < 0.8 do
  R.run(1 / 60)
  t = t + 1 / 60
  if not tStop and math.abs(rollRateDeg()) < 0.1 * rateHeld then tStop = t end
end
extra = math.abs(bankDeg() - bank0)
check(t90 ~= nil and t90 <= 0.25, string.format("按住 D：%.2f 秒滚转就快到头（%.0f°/秒，最快 %.0f°/秒）", t90 or -1, rateHeld, ROLLmax))
check(tStop ~= nil and tStop <= 0.3, string.format("松手 %.2f 秒就停住", tStop or -1))
check(extra < 22, string.format("松手后只多滚了 %.1f°（不过冲、不来回晃）", extra))

print("② 按住 S 拉杆")
levelOff()
R.run(0.5)
T.key(Enum.KeyCode.S, true)
local gPeak, tG, aoaMax, lagSeen = 0, nil, 0, false
local v0 = st.spd
t = 0
local gTarget = nil
while t < 3.0 do
  R.run(1 / 60)
  t = t + 1 / 60
  local g = st.gLoad or 1
  gPeak = math.max(gPeak, g)
  aoaMax = math.max(aoaMax, st.aoaDeg or 0)
  if (st.aoaDeg or 0) > 2 and st.vdir and st.cf.LookVector:Dot(st.vdir) < 0.9995 then lagSeen = true end
  if t > 1.2 and not gTarget then gTarget = g end
end
T.key(Enum.KeyCode.S, false)
local v1 = st.spd
-- 过载多快起来：重新拉一次，记到「稳定值的九成」的时间
levelOff()
R.run(0.5)
T.key(Enum.KeyCode.S, true)
local t90g, gMaxShort = nil, 0
t = 0
while t < 1.0 do
  R.run(1 / 60)
  t = t + 1 / 60
  local g = st.gLoad or 1
  gMaxShort = math.max(gMaxShort, g)
  if not t90g and gTarget and g >= 1 + 0.9 * (gTarget - 1) then t90g = t end
end
T.key(Enum.KeyCode.S, false)
check(t90g ~= nil and t90g <= 0.5, string.format("拉杆 %.2f 秒过载就到九成（稳住在 %.1f g）", t90g or -1, gTarget or 0))
check(gPeak <= (gTarget or 0) * 1.18 + 0.3, string.format("过载不冲过头（最高 %.1f g，稳住 %.1f g）", gPeak, gTarget or 0))
check(lagSeen and aoaMax > 3, string.format("机头先转、航迹慢半拍跟着（迎角最大 %.1f°）", aoaMax))
check(v1 < v0 * 0.93, string.format("一直拉着急转掉速（%.0f → %.0f 格 / 秒）", v0, v1))
T.summary()
