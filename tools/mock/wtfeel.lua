-- 战雷式飞行手感（模拟器）：python3 tools/mock/run.py tools/mock/wtfeel.lua [id=j11]
--   用户 11-24 夜：「看其他几个 ai 的提交，我要求你把飞机的驾驶感完全还原战争雷霆」——空中速度改成按力算（推力 − 废阻 − 诱导阻力 + 重力）：
--   ① 军推平飞：越接近最大平飞速度越加不上去，停在 vMil 附近（不冲过去）
--   ② 收到慢车：高速时减速快、低速时慢（废阻 ∝ 速度²）
--   ③ 军推爬升 40° 掉速；④ 慢车俯冲 40° 加速
--   ⑤ 最大过载盘旋：拉的过载超过这一型军推的持续过载就掉速（诱导阻力），没超过就差不多稳住
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
-- 等开战再上飞机：准备阶段转开战时服务器把每个人的载具状态重推一遍，客户端重新起一份飞行状态（G.fly 换了一张表），
--   原来测到一半（⑤⑥ 前后）正好开战，后面全在改那张旧表，结果全是 0
T.runUntil(function() return G.round.phase == "battle" end, 400, 1 / 10)
G.round.endsAt = (G.round.endsAt or 0) + 1e6   -- 模拟器里没有对手：开战阶段时间一到就判守方赢、回合结束、人全收回机库（后面全在旧状态上测）——这一局不结束
T.actAs(me, "deploy", "rifle", "base")   -- 沙海：只在自己基地出生（B 11-24）
R.run(2)
local gy = math.max(G.Map.ground(0, 0), 0)
local acf = CF(0, gy + 1100, 0)
local jet = G.spawnAircraft("atk", ID, acf, nil, P)
P.char:PivotTo(acf * CF(4, 0, 0))
T.act("enterVeh", jet.id)
R.run(0.2)
local st = C.fly
-- 客户端每帧的回调出错会被 init.client.lua 的 pcall 接住、只写在屏幕顶上的红条（G.showError），R.errors 里没有：这里也收下来
local cerr = {}
local se0 = C.showError
C.showError = function(msg)
  if #cerr < 5 then print("  客户端报错：" .. tostring(msg)) end
  table.insert(cerr, tostring(msg))
  if se0 then se0(msg) end
end
check(st ~= nil and st.pilot and st.d.id == ID, "空中坐进 " .. ID)
if not st then T.summary() return end
local d = st.d
C.flyMouseAim(true)
st.ground = false
st.gearWant, st.gear = 0, 0

-- 摆成平飞（朝 −Z、在地图中间、离地 alt 格，默认 1100），给速度、油门
--   飞行物理（FlightModel，11-26 晚）以后速度照真机：俯冲 4 秒要掉一千四五百格、爬升几秒就顶到 2600 格的升限（Fly.lua），
--   原来全在 1100 格高测，④ 俯冲直接撞地，后面⑤～⑩全在残骸上测（全是 0）
local function reset(spd, thr, pitchDeg, alt)
  if DIAG then
    print(string.format("    [诊断] C.fly=%s 同一张=%s pilot=%s crashed=%s ground=%s 载具=%s 机体=%s phase=%s spd=%s y=%s",
      tostring(C.fly ~= nil), tostring(C.fly == st), tostring(C.fly and C.fly.pilot), tostring(st.crashed), tostring(st.ground),
      tostring(P.vehicle and P.vehicle.id), tostring(jet.dead or jet.gone or (G.ents and G.ents[jet.id] == nil)), tostring(G.round.phase),
      tostring(st.spd and math.floor(st.spd)), tostring(st.cf and math.floor(st.cf.Position.Y))))
  end
  st = C.fly or st   -- 万一客户端重新起了飞行状态（换了一张表）：跟上现在这张
  local p = CF(0, math.min(gy + (alt or 1100), 2500), 0)
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
reset(d.vMil * 0.98, 100)
local s3 = st.spd
fly(2)
local a3 = (st.spd - s3) / 2
reset(d.vMil * 1.1, 100)
local s2 = st.spd
fly(2)
check(a1 > 0 and a1 < 27.5 * 1.1, string.format("半速时加速 %.1f 格/秒²（%.2f g，原来军推折算 1.6 g）", a1, g(a1)))
-- 飞行物理（FlightModel，11-26 晚）：战斗机军推最大平飞速度在 0.95～1 马赫的跨声速阻力墙上——九成多 vMil 还加得动（废阻按速度平方涨），
--   贴着 vMil 时波阻一下子上来、几乎加不上去（原来手调的模型阻力只按速度平方，九成二就只剩三成五）
check(a2 < a1 * 0.75, string.format("九成二 vMil 时加速 %.1f 格/秒²（半速时 %.1f）", a2, a1))
check(a3 < a1 * 0.3, string.format("贴着 vMil（九成八）时加速只剩 %.1f 格/秒²：跨声速阻力墙", a3))
check(st.spd < s2, string.format("军推比 vMil 快的时候减速（%.0f → %.0f 格/秒）：停在 vMil 附近", s2, st.spd))

print("② 收到慢车：高速减速快、低速慢")
-- 起始速度不超过这一型的结构极限速度（FlightModel 的 vne）：原来摆到 vMax 的 1.05 倍，比 vne 还快，飞 0.8 秒就按战雷规则超速撕掉一边机翼，
--   12 秒后服务器判坠毁（WtAir.lua）——⑤ 开始人就不在飞机上了，后面全是 0
local vHi = math.min(d.vMax * 1.05, (st.fmD and st.fmD.vne and st.fmD.vne * 2.8 or d.vMax * 1.05) * 0.97)
reset(vHi, 0)
s0 = st.spd
fly(2)
local dHi = (s0 - st.spd) / 2
reset(d.stall * 1.6, 0)
s0 = st.spd
fly(2)
local dLo = (s0 - st.spd) / 2
check(dHi > dLo * 2.5, string.format("慢车减速：%.0f 格/秒时 %.1f、%.0f 格/秒时 %.1f 格/秒²", vHi, dHi, d.stall * 1.6, dLo))

-- ③④ 照这一型的推力、阻力算该加 / 减多快（FlightModel.em 的平飞剩余推力 ∓ 重力沿航迹的分量），模拟器里飞出来的要对得上
local FM = R.require(R.services.ReplicatedStorage:FindFirstChild("FlightModel"))
local function predict(thr, gammaDeg)
  local D = st.fmD
  local m = C.flyMass and C.flyMass() or (D.m0 + D.fi)
  local e = FM.em(D, m, st.spd / 2.8, st.cf.Position.Y / 2.8, thr)
  return (e.acc - 9.81 * math.sin(math.rad(gammaDeg))) * 2.8
end
print("③ 军推爬升 40° 掉速")
reset(d.vMil * 0.9, 100, 40, 300)
s0 = st.spd
local aP = predict(100, 40)
local y0 = st.cf.Position.Y
fly(3)
local aM = (st.spd - s0) / 3
check(not st.crashed and st.spd < s0 and math.abs(aM - aP) < math.abs(aP) * 0.4 + 3,
  string.format("爬升 3 秒：%.0f → %.0f 格/秒（爬了 %.0f 格）：平均 %.1f 格/秒²，照推力、阻力、重力该是 %.1f", s0, st.spd, st.cf.Position.Y - y0, aM, aP))

print("④ 慢车俯冲 40° 加速")
reset(d.vMil * 0.6, 0, -40, 2400)
s0 = st.spd
aP = predict(0, -40)
fly(4)
aM = (st.spd - s0) / 4
check(not st.crashed and st.spd > s0 * 1.05 and math.abs(aM - aP) < math.abs(aP) * 0.4 + 3,
  string.format("俯冲 4 秒：%.0f → %.0f 格/秒：平均 %.1f 格/秒²，照推力、阻力、重力该是 %.1f", s0, st.spd, aM, aP))
check(not st.crashed, "俯冲完没撞地（后面接着测）")

print("⑤ 最大过载盘旋掉速")
-- 准心转得比这一型最大瞬时转弯率快两成（一直最大过载转，又不至于让准心转到身后去、教官掉头往下拉）；高 2000 格（转弯掉点高度也不撞地）
reset(d.vMil * 0.85, 100, 0, 2000)
s0 = st.spd
local maxG, minY = 0, 1e9
local FD = st.fmD
local wTurn = 9.81 * math.sqrt(math.max(FD.nzP * FD.nzP - 1, 1)) / (s0 / 2.8)
local mass5 = C.flyMass and C.flyMass() or (FD.m0 + FD.fi)
local em5 = FM.em(FD, mass5, s0 / 2.8, st.cf.Position.Y / 2.8, 100)
fly(5, function()
  st.aimYaw = st.aimYaw - wTurn * 1.2 / 15
  maxG = math.max(maxG, st.gLoad or 0)
  minY = math.min(minY, st.cf.Position.Y)
end)
check(not st.crashed and maxG > 5, string.format("拉到 %.1f g（最低到 %.0f 格高，%s）", maxG, minY - gy, st.crashed and "摔了" or "没摔"))
-- 飞行物理（FlightModel，11-26 晚）：掉不掉速照这一型军推的持续过载（能量机动：推力 = 阻力的那个过载）——
--   拉的过载比它大就掉速，翼载低、推力大的重型战斗机在这个速度上军推能稳住七八个 g、几乎不掉
local over = maxG - em5.ns
if over > 1 then
  check(st.spd < s0 * (1 - math.min(0.04, over * 0.006)), string.format("盘旋 5 秒：%.0f → %.0f 格/秒（拉 %.1f g，军推持续过载 %.1f g：该掉速）", s0, st.spd, maxG, em5.ns))
else
  check(st.spd < s0 * 1.02 and st.spd > s0 * 0.9, string.format("盘旋 5 秒：%.0f → %.0f 格/秒（拉 %.1f g，军推持续过载 %.1f g：差不多稳住）", s0, st.spd, maxG, em5.ns))
end

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
R.run(1 / 15)
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
  fly(1.6, function() mg = math.max(mg, st.gLoad or 0) end)
  T.key(Enum.KeyCode.S, false)
  return mg
end
local gSlow, gFast = pullAt(d.stall * 1.15), pullAt(d.stall * 2.5)
check(gSlow < 1.7, string.format("1.15 倍失速速度拉满杆：%.1f g", gSlow))
check(gFast > 4, string.format("2.5 倍失速速度拉满杆：%.1f g", gFast))

print("⑧ 滚转：中速最灵，太慢、太快都慢")
local function rollAt(spd, pitchDeg, alt)
  reset(spd, 100, pitchDeg, alt)
  local mr = 0
  T.key(Enum.KeyCode.D, true)
  fly(1.0, function() mr = math.max(mr, math.abs(st.rr or 0)) end)
  T.key(Enum.KeyCode.D, false)
  return math.deg(mr)
end
-- 「太快」那一下：比最大平飞速度快、但不超过结构极限速度（vne）——超了 0.8 秒就按战雷规则撕掉一边机翼，滚转一下子冲到四五百度每秒
local vFast = math.min(d.vMax * 1.25, (st.fmD and st.fmD.vne and st.fmD.vne * 2.8 or d.vMax * 1.25) * 0.97)
local rSlow, rMid, rFast = rollAt(d.stall * 1.1), rollAt(d.vMil * 0.8), rollAt(vFast, -30, 2200)
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

print("⑩ 失速：电传有迎角限制拉不进失速；增稳 / 机械操纵的低速拉满杆会失速、一边机翼先掉")
reset(d.stall * 0.75, 0, 20)
local b0 = math.deg(math.asin(st.cf.RightVector.Y))
T.key(Enum.KeyCode.S, true)
local mk, aMax = 0, 0
fly(2.5, function() mk = math.max(mk, st.stallK or 0) aMax = math.max(aMax, st.aoaDeg or 0) end)
T.key(Enum.KeyCode.S, false)
local b1 = math.deg(math.asin(math.max(-1, math.min(1, st.cf.RightVector.Y))))
local FD = st.fmD
if FD.fcs == "fbw" then
  check(mk < 0.3 and aMax < (FD.aL or FD.aS) + 4, string.format("电传：太慢还拉杆也不失速（迎角最大 %.0f°，限制 %d°）", aMax, FD.aL or FD.aS))
else
  check(mk > 0.3, string.format("太慢还拉杆：失速了（%.2f，迎角 %.0f°）", mk, aMax))
  check(math.abs(b1 - b0) > 12, string.format("一边机翼掉下去（坡度 %.0f° → %.0f°）", b0, b1))
end
C.flyMouseAim(true)
check(#R.errors == 0 and #cerr == 0, "没有报错：" .. table.concat(R.errors, " | ") .. table.concat(cerr, " | ", 1, math.min(#cerr, 3)))
T.summary()
