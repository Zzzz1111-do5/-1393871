--!nocheck
-- 键盘开飞机的手感（只跑飞行模型，几秒出结果）：lune run tools/test/kbfeel.luau [型号…] [trace]
--   用户 11-28「然后目前飞机操控有些奇怪 和我玩的空战飞机驾驶有区别」「有时候不该灵敏的时候过于灵敏 该灵敏的时候又有点迟钝」。
--   照 Fly.lua 的键盘推杆喂杆量（按住匀速推、0.25 秒满杆，松开 0.05 秒回中；inp.lin：飞控不过摇杆的三次方），三个速度
--   （0.3 / 0.48 / 0.65 倍最大允许速度，低的那个不低于 1.6 倍失速速度）各量一遍，查：
--   ① 点一下 D（0.08 秒）看得见地滚一点：按住一秒的滚转角速度的 0.6% 以上（F-16 约 1.5°，现在 3～5°）、不超过 10°
--      （原来 F-16 只滚 1°：杆量过了三次方只剩一成）；最大滚转不到 100°/s 的（轰炸机、无人机）点一下本来就看不出来，不查
--   ② 电传 / 增稳的战斗机（最大滚转 180°/s 以上）按住 D 没有「先愣一下」：0.2 秒时的滚转角速度有按住一秒的 25% 以上
--      （原来 F-16 两成、苏-27 一成半：53 / 252、35 / 241°/s）；轰炸机、无人机、老飞机滚转本来就慢，不查这条
--   ③ 满速滚转松手停得住：多滚不超过 42°（原来 F-16 46°、苏-27 49°）
--   ④ 点 S 0.3 秒（小修正）：机头一共抬不超过 18°、松手以后不超过 12°（原来 F-16 在 450 公里 / 时点 0.3 秒，迎角冲到 38°（限制 25°）、
--      一共抬了 45°、松手后机头还自己翻了 42°；苏-27 29°）
--   ⑤ 电传 / 增稳：点 S、按住 S 一秒过载都不超过上限（原来 F-16 在 700 公里 / 时点 0.3 秒冲到 9.8 g）；电传的迎角不冲过限制 3° 以上
--      （机械操纵的老飞机没有过载限制，高速拉满杆能拉过头：飞行员自己管）
--   比较改前：FM_PATH=旧的 FlightModel.lua 文件
--   trace：逐帧打印第一个型号中间那个速度点 S 0.3 秒的过程
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local FM = luau.load(fs.readFile(process.env.FM_PATH or "src/ReplicatedStorage/FlightModel.lua"), { debugName = "FlightModel" })()
local RAD, DEG = math.pi / 180, 180 / math.pi
local G0 = FM.G

local ids, TRACE = {}, false
for i = 1, #process.args do
  local a = process.args[i]
  if a == "trace" then TRACE = true else table.insert(ids, a) end
end
if #ids == 0 then
  for id in pairs(FM.AC) do table.insert(ids, id) end
  table.sort(ids)
end

local bad = 0
local function check(ok, msg)
  if not ok then
    bad += 1
    print("    ✗ " .. msg)
  end
end
local function bankOf(F)
  local rX, rY, rZ, uX, uY = FM.axes(F)
  return math.atan2(-rY, uY)
end
local function pitchOf(F)
  local _, _, _, _, _, _, fX, fY = FM.axes(F)
  return math.asin(math.clamp(fY, -1, 1))
end
local function wrap(a)
  while a > math.pi do a -= 2 * math.pi end
  while a < -math.pi do a += 2 * math.pi end
  return a
end
local function approach(cur, want, step)
  if cur < want then return math.min(want, cur + step) end
  return math.max(want, cur - step)
end
local DT = 1 / 60

-- 一个科目：axis "x"（D）/ "y"（S），按住 hold 秒、松手再飞 after 秒；返回量到的东西
local function run(D, m, V, axis, hold, after, trace)
  local h = 1000
  local a = FM.trimLevel(D, m, V, (FM.atmo(h)))
  local c, s = math.cos(a), math.sin(a)
  local F = FM.new(D, { 1, 0, 0, 0, c, -s, 0, s, c }, 0, 0, -V, 100)
  local env = { m = m, h = h }
  local inp = { mode = "stick", sx = 0, sy = 0, sz = 0, thr = 100, lin = true }
  for _ = 1, 90 do local _, dy = FM.step(F, D, DT, inp, env) env.h += dy end   -- 松杆飞 1.5 秒稳住
  local phi0, th0 = bankOf(F), pitchOf(F)
  local k, t = 0, 0
  local r = { pAt = {}, nMax = 0, aMax = 0, pMax = 0 }
  local phiRel, thRel, thStop = nil, nil, nil
  while t < hold + after - 1e-9 do
    local want = (t < hold - 1e-9) and 1 or 0
    if want ~= 0 then k = approach(k, want, DT / 0.25) else k = approach(k, 0, DT / 0.05) end
    if axis == "x" then inp.sx = k else inp.sy = k end
    local _, dy = FM.step(F, D, DT, inp, env)
    env.h += dy
    t += DT
    r.nMax = math.max(r.nMax, F.nz)
    r.aMax = math.max(r.aMax, F.al)
    if t <= hold + 1e-9 then r.pMax = math.max(r.pMax, F.p) end
    for _, tt in ipairs({ 0.2, 1.0 }) do
      if math.abs(t - tt) < DT / 2 then r.pAt[tt] = F.p end
    end
    if t > hold and not phiRel then phiRel, thRel = bankOf(F), pitchOf(F) end
    if thRel and not thStop and F.q <= 0.02 then thStop = pitchOf(F) end
    if trace and math.floor(t / DT + 0.5) % 3 == 0 then
      print(string.format("      t %.2f 杆 %.2f  过载指令 %5.2f  平尾 %6.1f°  q %6.1f°/s  过载 %5.2f  迎角 %5.1f°  俯仰 %6.1f°", t, k, F.nf, F.de * DEG,
        F.q * DEG, F.nz, F.al * DEG, (pitchOf(F) - th0) * DEG))
    end
  end
  r.phi = wrap(bankOf(F) - phi0) * DEG
  r.over = phiRel and wrap(bankOf(F) - phiRel) * DEG or 0
  local thEnd = thStop or pitchOf(F)
  r.thTot = (thEnd - th0) * DEG
  r.thAfter = thRel and (thEnd - thRel) * DEG or 0
  return r
end

print("型号      速度 m/s | 点D° | D 0.2/1.0 秒 °/s | 满速松手多滚° | 点S 0.3 秒：共抬° 松手后° 最大g 最大迎角°")
for _, id in ipairs(ids) do
  local D = FM.get(id)
  if D then
    local m = D.m0 + 0.5 * D.fi + 320
    local rho0 = FM.atmo(1000)
    local Vs = math.sqrt(2 * m * G0 / (rho0 * D.S * D.CLm))
    local speeds = { math.max(D.vne * 0.3, Vs * 1.6), D.vne * 0.48, D.vne * 0.65 }
    local aLim = (D.fcs == "fbw") and (D.aLr or D.aSr * 0.92) or nil
    for j, V in ipairs(speeds) do
      local tap = run(D, m, V, "x", 0.08, 1.0)
      local hold = run(D, m, V, "x", 1.0, 1.5)
      local s3 = run(D, m, V, "y", 0.3, 1.5, TRACE and id == ids[1] and j == 2)
      local s1 = run(D, m, V, "y", 1.0, 1.0)
      local p2, p10 = (hold.pAt[0.2] or 0) * DEG, (hold.pAt[1.0] or 0) * DEG
      print(string.format("%-9s %5.0f   | %4.1f | %5.0f / %5.0f    | %6.1f        | %5.1f  %5.1f  %4.1f  %5.1f", id, V, tap.phi, p2, p10, hold.over,
        s3.thTot, s3.thAfter, s3.nMax, s3.aMax * DEG))
      local tag = string.format("%s %.0f m/s：", id, V)
      local fcsLaw = D.fcs ~= "mech"
      if D.pmax >= 100 then
        check(tap.phi >= 0.006 * p10 and tap.phi <= 10, tag .. string.format("点一下 D 滚 %.1f°（该是按住一秒 %.0f°/s 的 0.6%% 以上、10° 以内）", tap.phi, p10))
      end
      if fcsLaw and D.pmax >= 180 then
        check(p2 >= 0.25 * p10, tag .. string.format("按住 D 0.2 秒 %.0f°/s，按住一秒 %.0f°/s（头 0.2 秒该有 25%% 以上）", p2, p10))
      end
      check(hold.over <= 42, tag .. string.format("满速滚转松手多滚 %.0f°（该 42° 以内）", hold.over))
      check(s3.thTot <= 18 and s3.thAfter <= 12, tag .. string.format("点 S 0.3 秒机头一共抬 %.1f°、松手后 %.1f°（该 18° / 12° 以内）", s3.thTot, s3.thAfter))
      if fcsLaw then
        check(s3.nMax <= D.nzP + 0.3 and s1.nMax <= D.nzP + 0.3, tag .. string.format("过载不超上限（点 %.1f g、按住 %.1f g，上限 %.1f g）", s3.nMax, s1.nMax, D.nzP))
      end
      if aLim then
        check(math.max(s3.aMax, s1.aMax) <= aLim + 3 * RAD,
          tag .. string.format("迎角不冲过限制（最大 %.1f°，限制 %.0f°）", math.max(s3.aMax, s1.aMax) * DEG, aLim * DEG))
      end
    end
  end
end
print(bad == 0 and "全部通过" or ("不对 " .. bad .. " 处"))
if bad > 0 then process.exit(1) end
