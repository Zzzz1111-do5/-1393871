-- 战雷式飞行手感（模拟器）：python3 tools/mock/run.py tools/mock/wtfeel.lua [id=j11]
--   用户 11-24 夜：「看其他几个 ai 的提交，我要求你把飞机的驾驶感完全还原战争雷霆」——空中速度改成按力算（推力 − 废阻 − 诱导阻力 + 重力）：
--   ① 军推平飞：越接近最大平飞速度越加不上去，停在 vMil 附近（不冲过去）
--   ② 收到慢车：高速时减速快、低速时慢（废阻 ∝ 速度²）
--   ③ 军推爬升 40° 掉速；④ 慢车俯冲 40° 加速
--   ⑤ 最大过载盘旋几秒掉三成以上速度（诱导阻力）
--   ⑥ 天上按 B 减速板、放起落架：阻力大，减速更快
--   ⑦ 慢了拉不动（1.15 倍失速速度时拉满杆过载不到 1.6 g；2.5 倍时能到 4 g 以上）
--   ⑧ 滚转：中速比快失速时滚得快；太快（俯冲超过最大速度）舵变沉
--   ⑨ 滚轮是油门（一格 5%）；⑩ 失速一边机翼先掉
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local ID = TEST_ARGS:match("id=(%w+)") or "j11"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 300)
local me = T.join("P1", 6401, true)
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
T.actAs(me, "deploy", "rifle", "base")   -- 沙海：只在自己基地出生（B 11-24）
R.run(2)
local gy = math.max(G.Map.ground(0, 0), 0)
local acf = CF(0, gy + 1100, 0)
local jet = G.spawnAircraft("atk", ID, acf, nil, P)
P.char:PivotTo(acf * CF(4, 0, 0))
T.act("enterVeh", jet.id)
R.run(0.2)
local st = C.fly
check(st ~= nil and st.pilot and st.d.id == ID, "空中坐进 " .. ID)
if not st then T.summary() return end
local d = st.d
C.flyMouseAim(true)
st.ground = false
st.gearWant, st.gear = 0, 0

-- 摆成平飞（朝 −Z、在地图中间、高 1100 格），给速度、油门
local function reset(spd, thr, pitchDeg)
  local p = CF(0, gy + 1100, 0)
  local a = math.rad(pitchDeg or 0)
  local look = V3(0, math.sin(a), -math.cos(a))
  st.cf = CFr.lookAt(p.Position, p.Position + look)
  st.vdir, st.spd, st.vel = look, spd, look * spd
  st.pr, st.rr, st.yr = 0, 0, 0
  st.thr, st.thrE = thr, thr
  st.aimYaw, st.aimPitch = 0, a
  st.kP, st.kR, st.kY = 0, 0, 0
  st.stallK, st.dropDir = 0, nil
  -- 服务器那边也摆过去（不然它当成瞬移，把位置、速度拉回去：Air.lua 的 sync / fix）
  G.moveEnt(jet, st.cf)
  jet.vel = st.vel
  jet.syncT, jet.syncSlack = os.clock(), 160
end
local function fly(sec, each)   -- 一步 1/15 秒（沙海图的模拟器一步要零点几秒，步长放大一倍省时间；物理按 dt 算，不受影响）
  local n = math.floor(sec * 15 + 0.5)
  for i = 1, n do
    if each then each(i) end
    R.run(1 / 15)
  end
end
local function g(x) return x / 27.5 end

print("① 军推平飞：越接近 vMil 越加不上去")
reset(d.vMil * 0.5, 100)
local s0 = st.spd
fly(2)
local a1 = (st.spd - s0) / 2
reset(d.vMil * 0.92, 100)
local s1 = st.spd
fly(2)
local a2 = (st.spd - s1) / 2
reset(d.vMil * 1.1, 100)
local s2 = st.spd
fly(2)
check(a1 > 0 and a1 < 27.5 * 1.1, string.format("半速时加速 %.1f 格/秒²（%.2f g，原来军推折算 1.6 g）", a1, g(a1)))
check(a2 < a1 * 0.35, string.format("接近最大平飞速度时加速只剩 %.1f 格/秒²（半速时 %.1f）", a2, a1))
check(st.spd < s2, string.format("军推比 vMil 快的时候减速（%.0f → %.0f 格/秒）：停在 vMil 附近", s2, st.spd))

print("② 收到慢车：高速减速快、低速慢")
reset(d.vMax * 1.05, 0)
s0 = st.spd
fly(2)
local dHi = (s0 - st.spd) / 2
reset(d.stall * 1.6, 0)
s0 = st.spd
fly(2)
local dLo = (s0 - st.spd) / 2
check(dHi > dLo * 2.5, string.format("慢车减速：%.0f 格/秒时 %.1f、%.0f 格/秒时 %.1f 格/秒²", d.vMax * 1.05, dHi, d.stall * 1.6, dLo))

print("③ 军推爬升 40° 掉速")
reset(d.vMil * 0.9, 100, 40)
s0 = st.spd
local y0 = st.cf.Position.Y
fly(5)
check(st.spd < s0 * 0.85, string.format("爬升 5 秒：%.0f → %.0f 格/秒（爬了 %.0f 格）", s0, st.spd, st.cf.Position.Y - y0))

print("④ 慢车俯冲 40° 加速")
reset(d.vMil * 0.6, 0, -40)
s0 = st.spd
fly(4)
check(st.spd > s0 * 1.15, string.format("俯冲 4 秒：%.0f → %.0f 格/秒", s0, st.spd))

print("⑤ 最大过载盘旋掉速")
reset(d.vMil * 0.85, 100)
s0 = st.spd
local maxG = 0
fly(5, function()
  st.aimYaw = st.aimYaw - math.rad(5)   -- 鼠标一直往右推：一直最大过载转
  maxG = math.max(maxG, st.gLoad or 0)
end)
check(maxG > 5, string.format("拉到 %.1f g", maxG))
check(st.spd < s0 * 0.75, string.format("盘旋 5 秒：%.0f → %.0f 格/秒（掉 %.0f%%）", s0, st.spd, (1 - st.spd / s0) * 100))

print("⑥ 减速板、起落架")
reset(d.vMil, 0)
s0 = st.spd
fly(2)
local dClean = s0 - st.spd
reset(d.vMil, 0)
s0 = st.spd
T.key(Enum.KeyCode.B, true)
fly(2)
T.key(Enum.KeyCode.B, false)
local dBrk = s0 - st.spd
check(st.airbrake == false and dBrk > dClean * 1.8, string.format("按住 B（减速板）2 秒掉 %.0f 格/秒，不按掉 %.0f", dBrk, dClean))
reset(d.vMil, 0)
st.gear, st.gearWant = 1, 1
s0 = st.spd
fly(2)
local dGear = s0 - st.spd
st.gear, st.gearWant = 0, 0
check(dGear > dClean * 1.4, string.format("放着起落架 2 秒掉 %.0f 格/秒（收着 %.0f）", dGear, dClean))

print("⑦ 慢了拉不动")
C.flyMouseAim(false)
local function pullAt(spd)
  reset(spd, 100)
  local mg = 0
  T.key(Enum.KeyCode.S, true)
  fly(1.0, function() mg = math.max(mg, st.gLoad or 0) end)
  T.key(Enum.KeyCode.S, false)
  return mg
end
local gSlow, gFast = pullAt(d.stall * 1.15), pullAt(d.stall * 2.5)
check(gSlow < 1.7, string.format("1.15 倍失速速度拉满杆：%.1f g", gSlow))
check(gFast > 4, string.format("2.5 倍失速速度拉满杆：%.1f g", gFast))

print("⑧ 滚转：中速最灵，太慢、太快都慢")
local function rollAt(spd, pitchDeg)
  reset(spd, 100, pitchDeg)
  local mr = 0
  T.key(Enum.KeyCode.D, true)
  fly(1.0, function() mr = math.max(mr, math.abs(st.rr or 0)) end)
  T.key(Enum.KeyCode.D, false)
  return math.deg(mr)
end
local rSlow, rMid, rFast = rollAt(d.stall * 1.1), rollAt(d.vMil * 0.8), rollAt(d.vMax * 1.25, -30)
check(rMid > rSlow * 1.4, string.format("滚转角速度：快失速时 %.0f°/秒、中速 %.0f°/秒", rSlow, rMid))
check(rFast < rMid * 0.85, string.format("超过最大速度俯冲时 %.0f°/秒（舵变沉）", rFast))
check(rMid > 130, string.format("中速滚转 %.0f°/秒（战雷侧卫一秒两百多度；原来 90）", rMid))

print("⑨ 滚轮油门")
reset(d.vMil * 0.8, 50)
local UIS = R.services.UserInputService
local t0 = st.thr
R.as("client", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, 1) }, false) end)
R.as("client", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = V3(0, 0, 1) }, false) end)
check(math.abs(st.thr - (t0 + 10)) < 1.5, string.format("滚轮往前两格：油门 %.0f → %.0f%%", t0, st.thr))

print("⑩ 失速掉翼")
reset(d.stall * 0.75, 0, 20)
local b0 = math.deg(math.asin(st.cf.RightVector.Y))
T.key(Enum.KeyCode.S, true)
local mk = 0
fly(2.5, function() mk = math.max(mk, st.stallK or 0) end)
T.key(Enum.KeyCode.S, false)
local b1 = math.deg(math.asin(math.max(-1, math.min(1, st.cf.RightVector.Y))))
check(mk > 0.5, string.format("太慢还拉杆：失速了（%.2f）", mk))
check(math.abs(b1 - b0) > 12, string.format("一边机翼掉下去（坡度 %.0f° → %.0f°）", b0, b1))
C.flyMouseAim(true)
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
