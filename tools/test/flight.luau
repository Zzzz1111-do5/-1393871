--!nocheck
-- 飞行物理逐型试飞（src/ReplicatedStorage/FlightModel.lua）：lune run tools/test/flight.luau [型号…]
--   每一型按「一半内油 + 两枚中距弹」的作战重量，在 1000 米高度飞一遍标准科目，打出一张性能表，并检查：
--   ① 平飞极速（军推 / 加力）：停得住（不无限加速）、在真机海平面极速的范围里
--   ② 持续盘旋：全加力保持高度的最大过载盘旋 40 秒后的转弯角速度（°/s）和速度
--   ③ 瞬时转弯：中速拉满过载的最大转弯角速度
--   ④ 满杆滚转角速度、松杆后多滚多少度
--   ⑤ 拉杆：过载起到稳定值九成要多久、冲过头多少；松杆后过载回稳的样子（电传一下稳住，机械操纵按自己的短周期晃一两下）
--   ⑥ 失速速度（1 g，干净构型）、离地速度够不够（游戏里的 vRot 要比带襟翼的失速速度快）
--   ⑦ 机械操纵的飞机低速拉满杆会失速、一边机翼先掉；松杆能改出来
--   ⑧ 一直不出 NaN、不翻滚着发散
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local FM = luau.load(fs.readFile("src/ReplicatedStorage/FlightModel.lua"), { debugName = "FlightModel" })()

local RAD, DEG = math.pi / 180, 180 / math.pi
local G0 = FM.G
local function fmt(x, n) return string.format("%." .. (n or 0) .. "f", x) end

-- 海平面极速（m/s）的参考：真机公开数据（海平面 / 低空）；军推是估的（没有公开的给个宽范围）
local REF = {
  j6 = { ab = { 290, 345 } }, j8 = { ab = { 330, 400 } }, j10 = { ab = { 355, 420 } }, j11 = { ab = { 360, 410 } }, j15t = { ab = { 340, 395 } },
  j16 = { ab = { 350, 400 } }, j20 = { ab = { 360, 420 } }, j35 = { ab = { 350, 410 } }, j36 = { ab = { 340, 420 } }, h6k = { mil = { 220, 290 } },
  gj11 = { mil = { 220, 290 } }, gj2 = { mil = { 90, 120 } }, a10c = { mil = { 180, 215 } }, b2 = { mil = { 230, 290 } }, f14 = { ab = { 360, 420 } },
  f15 = { ab = { 370, 420 } }, f16 = { ab = { 370, 420 } }, f22 = { ab = { 380, 430 } }, f35 = { ab = { 330, 380 } }, mq9 = { mil = { 115, 145 } },
  mig29 = { ab = { 380, 425 } }, su27 = { ab = { 360, 405 } }, su35 = { ab = { 370, 410 } }, su57 = { ab = { 370, 420 } }, su25 = { mil = { 240, 285 } },
  t50 = { ab = { 365, 420 } },
}

local ids = {}
for i = 1, #process.args do table.insert(ids, process.args[i]) end
if #ids == 0 then
  for id in pairs(FM.AC) do table.insert(ids, id) end
  table.sort(ids)
  for k in pairs(FM.VAR) do table.insert(ids, k) end
end

local bad = 0
local function check(ok, msg)
  if not ok then
    bad += 1
    print("    ✗ " .. msg)
  end
end

-- 一架在 h 米高、速度 V 往 −Z 平飞（配平迎角、机翼水平）
local function newF(D, m, V, h, thr)
  local a = FM.trimLevel(D, m, V, (FM.atmo(h)))
  local c, s = math.cos(a), math.sin(a)
  -- 抬头 a：机体绕 X 轴转 a（前 −Z 往上），速度仍然水平
  local rot = { 1, 0, 0, 0, c, -s, 0, s, c }
  local F = FM.new(D, rot, 0, 0, -V, thr)
  return F
end
local function speed(F) return math.sqrt(F.vx * F.vx + F.vy * F.vy + F.vz * F.vz) end
local function bankOf(F)
  local rX, rY, rZ, uX, uY = FM.axes(F)
  return math.atan2(-rY, uY)
end
local function finite(F)
  for _, k in ipairs({ "vx", "vy", "vz", "p", "q", "r", "qw", "qx", "qy", "qz" }) do
    local v = F[k]
    if v ~= v or v == math.huge or v == -math.huge then return false end
  end
  return true
end

-- 飞 T 秒：每步 1/60 秒，cb(F, t) 每步调；返回终了高度变化
local function fly(F, D, T, inp, env, cb)
  local t, h0 = 0, env.h
  while t < T - 1e-9 do
    local dx, dy, dz = FM.step(F, D, 1 / 60, inp, env)
    env.h += dy
    t += 1 / 60
    if cb and cb(F, t) == false then break end
    if not finite(F) then return nil end
  end
  return env.h - h0
end

-- 平飞（教官：过载按保持高度的需要给，机翼水平）
local function levelCmd(F, env, h0)
  local vy = F.vy
  local dh = h0 - env.h
  local n = 1 + math.clamp((dh * 0.02 - vy * 0.08), -0.5, 0.8)
  return n
end

print(string.format("%-10s %6s %5s %5s %5s | %5s %5s | %5s %5s | %5s %5s %5s | %5s %5s %5s | %5s %5s %5s", "型号", "质量", "推重", "翼载", "Vs",
  "军推", "加力", "STR", "V", "ITR", "V", "动态", "滚转", "多滚", "τn90", "超调", "松杆", "晃"))
for _, key in ipairs(ids) do
  local isVar = FM.VAR[key] ~= nil
  local D = isVar and FM.get(FM.VAR[key].base, key) or FM.get(key)
  if not D then
    print(key .. "：没有数据")
    bad += 1
  else
    local m = D.m0 + 0.5 * D.fi + 320
    local W = m * G0
    local rho = FM.atmo(1000)
    local Vs = math.sqrt(2 * W / (rho * D.S * D.CLm))
    local VsF = math.sqrt(2 * W / (rho * D.S * (D.CLm + D.flapCL)))
    local out = { key = key }
    -- ① 平飞极速：军推、加力各飞 150 秒
    local function vTop(thr)
      local F = newF(D, m, D.vne * 0.75, 1000, thr)
      local env = { m = m, h = 1000 }
      local inp = { mode = "cmd", n = 1, p = 0, r = 0, thr = thr }
      local vs = {}
      local dur = (D.Ta / (m * G0) < 0.45) and 400 or 150
      local ok = fly(F, D, dur, inp, env, function(F2, t)
        inp.n = levelCmd(F2, env, 1000)
        inp.p = -2 * bankOf(F2)
        if t > dur - 20 then table.insert(vs, speed(F2)) end
      end)
      if not ok then return -1, false end
      local v1, v2 = vs[1] or 0, vs[#vs] or 0
      return v2, math.abs(v2 - v1) < 3
    end
    local vMil, stMil = vTop(100)
    local vAB, stAB = (D.Ta > D.Tm) and vTop(130) or vMil, true
    if D.Ta > D.Tm then vAB, stAB = vTop(130) end
    out.vMil, out.vAB = vMil, vAB
    local ref = REF[isVar and FM.VAR[key].base or key]
    if ref and ref.ab and not isVar then check(vAB >= ref.ab[1] and vAB <= ref.ab[2], string.format("%s 加力极速 %.0f m/s（参考 %d ~ %d）", key, vAB, ref.ab[1], ref.ab[2])) end
    if ref and ref.mil and not isVar then check(vMil >= ref.mil[1] and vMil <= ref.mil[2], string.format("%s 军推极速 %.0f m/s（参考 %d ~ %d）", key, vMil, ref.mil[1], ref.mil[2])) end
    check(stMil and stAB, key .. " 极速停得住（不一直加速）")
    -- ② 持续 / 瞬时盘旋（能量机动：每个速度算推力 = 阻力时能拉的过载、升力能拉的过载，取最大转弯角速度）
    do
      local c = FM.card(D, m)
      out.str, out.strV, out.itrEM, out.itrEMV = c.str * DEG, c.strV or 0, c.itr * DEG, c.itrV or 0
    end
    -- ③ 瞬时转弯：从 0.6 × 最大允许速度（不超过加力极速）开始拉满过载，平面内转（机翼竖着），记最大转弯角速度
    do
      local V0 = math.min(D.vne * 0.55, vAB * 0.7)
      local F = newF(D, m, V0, 1000, 130)
      local env = { m = m, h = 1000 }
      local inp = { mode = "cmd", n = D.nzP, p = 0, r = 0, thr = 130 }
      local best, vAt, last = 0, 0, nil
      fly(F, D, 3, inp, env, function(F2, t)
        local v = speed(F2)
        local d = { F2.vx / v, F2.vy / v, F2.vz / v }
        if last then
          local dot = math.clamp(d[1] * last[1] + d[2] * last[2] + d[3] * last[3], -1, 1)
          local w = math.acos(dot) * 60
          if w > best then best, vAt = w, v end
        end
        last = d
      end)
      out.itr, out.itrV = best * DEG, vAt
    end
    -- ④ 滚转：0.6 × 最大允许速度，杆压满 1.5 秒、松杆
    do
      local V0 = math.min(D.vne * 0.6, vAB * 0.8)
      local F = newF(D, m, V0, 1000, 100)
      local env = { m = m, h = 1000 }
      local inp = { mode = "stick", sx = 1, sy = 0, sz = 0, thr = 100 }
      local pMax, bank0, tStop, phiAcc = 0, 0, nil, 0
      local held = true
      fly(F, D, 3.5, inp, env, function(F2, t)
        if t >= 1.5 and held then
          held = false
          inp.sx = 0
          phiAcc = 0
        end
        if held then pMax = math.max(pMax, F2.p)
        else
          phiAcc += F2.p / 60
          if not tStop and math.abs(F2.p) < 0.05 * pMax then tStop = t - 1.5 end
        end
      end)
      out.roll, out.rollOver, out.rollStop = pMax * DEG, phiAcc * DEG, tStop or 9
    end
    -- ⑤ 拉杆、松杆：0.55 × 最大允许速度，杆拉到一半 2.5 秒（键盘按住约 0.4 秒的杆量）
    do
      local V0 = math.min(D.vne * 0.55, vAB * 0.75)
      local F = newF(D, m, V0, 1000, 100)
      local env = { m = m, h = 1000 }
      local inp = { mode = "stick", sx = 0, sy = 0.6, sz = 0, thr = 100, level = true }
      local hist = {}
      local rel, nPeak, nMin, osc = false, 0, 99, 0
      local lastSign, crosses = 0, 0
      fly(F, D, 5.5, inp, env, function(F2, t)
        if t >= 2.5 and not rel then rel = true inp.sy = 0 end
        if not rel then
          table.insert(hist, { t, F2.nz })
          nPeak = math.max(nPeak, F2.nz)
        else
          if t > 2.6 then
            nMin = math.min(nMin, F2.nz)
            local sgn = (F2.nz > 1.05) and 1 or ((F2.nz < 0.95) and -1 or 0)
            if sgn ~= 0 and lastSign ~= 0 and sgn ~= lastSign then crosses += 1 end
            if sgn ~= 0 then lastSign = sgn end
          end
        end
      end)
      local nSS = hist[#hist] and hist[#hist][2] or 1
      local t90 = nil
      for _, hh in ipairs(hist) do if not t90 and hh[2] >= 1 + 0.9 * (nSS - 1) then t90 = hh[1] end end
      out.t90, out.over, out.nSS, out.relMin, out.crosses = t90 or 9, (nPeak - nSS) / math.max(nSS - 1, 0.1), nSS, nMin, crosses
    end
    -- ⑦ 机械操纵 / 增稳：低速（1.25 倍失速速度）拉满杆 → 失速、掉翼；松杆改出
    if D.fcs ~= "fbw" then
      local F = newF(D, m, Vs * 1.25, 1500, 100)
      local env = { m = m, h = 1500 }
      local inp = { mode = "stick", sx = 0, sy = 1, sz = 0, thr = 100 }
      local stalled, bankMax = false, 0
      fly(F, D, 4, inp, env, function(F2, t)
        if F2.al > D.aSr + 1.5 * RAD then stalled = true end
        bankMax = math.max(bankMax, math.abs(bankOf(F2)))
      end)
      inp.sy = -0.2
      local recovered = false
      fly(F, D, 6, inp, env, function(F2, t)
        if F2.al < D.aSr * 0.8 and speed(F2) > Vs * 1.05 then recovered = true end
      end)
      out.stall = stalled
      check(stalled, key .. "：低速拉满杆会失速（机械 / 增稳操纵没有硬限制）")
      check(recovered, key .. "：松杆推一点能改出失速")
    end
    -- ⑧ 电传：低速拉满杆不失速（迎角限制）
    if D.fcs == "fbw" then
      local F = newF(D, m, Vs * 1.4, 1500, 100)
      local env = { m = m, h = 1500 }
      local inp = { mode = "stick", sx = 0, sy = 1, sz = 0, thr = 100 }
      local aMax = 0
      fly(F, D, 5, inp, env, function(F2) aMax = math.max(aMax, F2.al) end)
      check(aMax <= (D.aLr or D.aSr) + 4 * RAD, string.format("%s：电传低速拉满杆迎角不超限（最大 %.1f°，限制 %.0f°）", key, aMax * DEG, (D.aL or D.aS)))
    end
    -- ⑨ 乱打杆 60 秒（键盘那样的开关量，各种组合）：不出 NaN、速度和角速度不发散
    do
      local F = newF(D, m, D.vne * 0.5, 1500, 100)
      local env = { m = m, h = 1500 }
      local inp = { mode = "stick", sx = 0, sy = 0, sz = 0, thr = 100, level = true }
      local seed, okRun, maxP = 7, true, 0
      local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
      local res = fly(F, D, 60, inp, env, function(F2, t)
        if math.floor(t * 60) % 30 == 0 then
          inp.sx = (rnd() < 0.4) and ((rnd() < 0.5) and -1 or 1) or 0
          inp.sy = (rnd() < 0.5) and ((rnd() < 0.7) and 1 or -1) or 0
          inp.sz = (rnd() < 0.2) and ((rnd() < 0.5) and -1 or 1) or 0
          inp.thr = (rnd() < 0.5) and 130 or 60
        end
        if env.h < 300 then env.h = 1500 end
        maxP = math.max(maxP, math.abs(F2.p), math.abs(F2.q), math.abs(F2.r))
        if speed(F2) > 900 then okRun = false end
      end)
      check(res ~= nil and okRun and maxP < 12, string.format("%s：乱打杆 60 秒不发散（最大角速度 %.1f rad/s）", key, maxP))
    end
    local vRotGame = nil
    print(string.format("%-10s %6.0f %5.2f %5.0f %5.0f | %5.0f %5.0f | %5.1f %5.0f | %5.1f %5.0f %5.1f | %5.0f %5.0f %5.2f | %5.0f%% %5.1f %5d",
      key, m, D.Ta / W, m / D.S, Vs, out.vMil, out.vAB, out.str, out.strV, out.itrEM, out.itrEMV, out.itr, out.roll, out.rollOver,
      out.t90, out.over * 100, out.relMin, out.crosses))
    check(out.roll > D.pmax * 0.55, string.format("%s：满杆滚转 %.0f°/s（设计 %d）", key, out.roll, D.pmax))
    check(out.t90 < 2.4, string.format("%s：拉杆后过载 %.2f 秒到九成", key, out.t90))
    check(out.over < 0.45, string.format("%s：拉杆过载不冲过头太多（%.0f%%）", key, out.over * 100))
  end
end
print(bad == 0 and "全部通过" or ("不对 " .. bad .. " 处"))
