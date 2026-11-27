--!nocheck
-- 过失速机动、方向舵侧滑、尾冲（src/ReplicatedStorage/FlightModel.lua；用户待办「飞控放开机动：大迎角、失速后、推力矢量、方向舵侧滑、尾冲」）
--   lune run tools/test/poststall.luau
--   ① 苏-57（推力矢量）解除迎角限制拉满杆：迎角过 75°（眼镜蛇），松杆 4 秒内回到 30° 以内，高度变化不大
--   ② 不解除限制：迎角不超过限制几度
--   ③ 歼-11（苏-27 布局，没有推力矢量）解除限制：迎角过 55°，能改出
--   ④ F-16 解除限制：能拉过平时的 25° 限制
--   ⑤ 苏-57 低速一直拉杆：原地翻一整圈（库尔比特，俯仰转过 330° 以上），松杆能改出
--   ⑥ F-16 满右舵：侧滑 6° 以上、坡度不大；松舵侧滑回零
--   ⑦ 尾冲：F-16 机头朝上、油门收小一直爬到没速度——先机尾朝下往后滑，然后机头甩下去；一直不出 NaN、角速度不发散
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local FM = luau.load(fs.readFile("src/ReplicatedStorage/FlightModel.lua"), { debugName = "FlightModel" })()
local DEG = 180 / math.pi

local bad = 0
local function check(ok, msg)
  print((ok and "  通过 " or "  不对 ") .. msg)
  if not ok then bad += 1 end
end
local function mass(D) return D.m0 + 0.5 * D.fi + 300 end
local function finite(F)
  for _, k in ipairs({ "vx", "vy", "vz", "p", "q", "r", "qw", "qx", "qy", "qz" }) do
    local v = F[k]
    if v ~= v or v == math.huge or v == -math.huge then return false end
  end
  return true
end
local LEVEL = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }   -- 机头朝 −Z、平飞
local UP = { 1, 0, 0, 0, 0, -1, 0, 1, 0 }     -- 机头朝上（绕 X 转 90°）
-- 飞 T 秒，每 1/60 秒一帧；inpF(t) 给这一帧的输入；返回统计
local function fly(F, D, T, inpF, h0, each)
  local env = { m = mass(D), h = h0 }
  local st = { aMax = -1e9, aMin = 1e9, vMin = 1e9, hMin = h0, hMax = h0, pitchSum = 0, wMax = 0, ok = true }
  local t, dt, h = 0, 1 / 60, h0
  while t < T do
    local inp = inpF(t)
    local _, dy = FM.step(F, D, dt, inp, env)
    h += dy
    env.h = h
    t += dt
    if not finite(F) then st.ok = false break end
    local a = F.al * DEG
    st.aMax, st.aMin = math.max(st.aMax, a), math.min(st.aMin, a)
    local V = math.sqrt(F.vx * F.vx + F.vy * F.vy + F.vz * F.vz)
    st.vMin = math.min(st.vMin, V)
    st.hMin, st.hMax = math.min(st.hMin, h), math.max(st.hMax, h)
    st.pitchSum += F.q * dt
    st.wMax = math.max(st.wMax, math.abs(F.p), math.abs(F.q), math.abs(F.r))
    if each then each(t, F, h, st) end
  end
  st.h, st.a = h, F.al * DEG
  return st
end
local function stick(sy, sx, sz, thr, ovr) return { mode = "stick", sx = sx or 0, sy = sy or 0, sz = sz or 0, thr = thr or 100, ovr = ovr } end

print("① 苏-57 眼镜蛇（解除迎角限制）")
do
  local D = FM.get("su57")
  local F = FM.new(D, LEVEL, 0, 0, -115, 100)
  local s = fly(F, D, 1.8, function() return stick(1, 0, 0, 100, true) end, 3000)
  local aPeak = s.aMax
  local s2 = fly(F, D, 4, function() return stick(0, 0, 0, 100, true) end, s.h)
  check(s.ok and s2.ok, "不出 NaN")
  check(aPeak > 75, string.format("迎角最大 %.0f°（> 75°）", aPeak))
  check(math.abs(s2.a) < 30, string.format("松杆 4 秒后迎角 %.0f°（< 30°）", s2.a))
  check(math.abs(s2.h - 3000) < 300, string.format("高度变化 %.0f 米", s2.h - 3000))
  print(string.format("    速度最低 %.0f 米 / 秒", math.min(s.vMin, s2.vMin)))
end

print("② 苏-57 不解除限制")
do
  local D = FM.get("su57")
  local F = FM.new(D, LEVEL, 0, 0, -115, 100)
  local s = fly(F, D, 3, function() return stick(1, 0, 0, 100, false) end, 3000)
  check(s.ok and s.aMax < (D.aL or D.aS) + 5, string.format("迎角最大 %.0f°（限制 %d°）", s.aMax, D.aL or D.aS))
end

print("③ 歼-11 眼镜蛇（没有推力矢量）")
do
  local D = FM.get("j11")
  local F = FM.new(D, LEVEL, 0, 0, -115, 100)
  local s = fly(F, D, 2.2, function() return stick(1, 0, 0, 100, true) end, 3000)
  local s2 = fly(F, D, 5, function() return stick(0, 0, 0, 100, true) end, s.h)
  check(s.ok and s2.ok, "不出 NaN")
  check(s.aMax > 55, string.format("迎角最大 %.0f°（> 55°）", s.aMax))
  check(math.abs(s2.a) < 35, string.format("松杆 5 秒后迎角 %.0f°", s2.a))
end

print("④ F-16 解除限制")
do
  local D = FM.get("f16")
  local F = FM.new(D, LEVEL, 0, 0, -120, 100)
  local s = fly(F, D, 2.5, function() return stick(1, 0, 0, 100, true) end, 3000)
  local s2 = fly(F, D, 5, function() return stick(0, 0, 0, 100, true) end, s.h)
  check(s.ok and s2.ok, "不出 NaN")
  check(s.aMax > (D.aL or 25) + 8, string.format("迎角最大 %.0f°（平时限制 %d°）", s.aMax, D.aL or 25))
  check(math.abs(s2.a) < 35, string.format("松杆 5 秒后迎角 %.0f°", s2.a))
end

print("⑤ 苏-57 库尔比特（低速一直拉着）")
do
  local D = FM.get("su57")
  local F = FM.new(D, LEVEL, 0, 0, -75, 130)
  local s = fly(F, D, 5.5, function() return stick(1, 0, 0, 130, true) end, 3000)
  local s2 = fly(F, D, 6, function() return stick(0, 0, 0, 130, true) end, s.h)
  check(s.ok and s2.ok, "不出 NaN")
  check(s.pitchSum * DEG > 330, string.format("俯仰一共转了 %.0f°（> 330°）", s.pitchSum * DEG))
  check(math.abs(s2.a) < 40, string.format("松杆 6 秒后迎角 %.0f°", s2.a))
  check(s.wMax < 6 and s2.wMax < 6, string.format("角速度最大 %.1f rad/s", math.max(s.wMax, s2.wMax)))
end

print("⑥ F-16 方向舵侧滑")
do
  local D = FM.get("f16")
  local F = FM.new(D, LEVEL, 0, 0, -160, 90)
  local s = fly(F, D, 3, function() return stick(0, 0, 1, 90, false) end, 2000)
  local be = F.be * DEG
  local phi = (F.phi or 0) * DEG
  check(s.ok and math.abs(be) > 6, string.format("满右舵侧滑 %.1f°（> 6°）", be))
  check(be < 0, "踩右舵机头偏右（侧滑角为负）")
  check(math.abs(phi) < 20, string.format("坡度 %.0f°（< 20°）", phi))
  fly(F, D, 2.5, function() return stick(0, 0, 0, 90, false) end, s.h)
  check(math.abs(F.be * DEG) < 1.5, string.format("松舵 2.5 秒后侧滑 %.1f°", F.be * DEG))
end

print("⑦ 尾冲")
do
  local D = FM.get("f16")
  local F = FM.new(D, UP, 0, 90, 0, 30)
  local slid, whip = false, false
  local s = fly(F, D, 22, function() return stick(0, 0, 0, 30, false) end, 3000, function(t, F2, h, st)
    local _, _, _, _, _, _, fX, fY, fZ = FM.axes(F2)
    if fY > 0.7 and F2.vy < -5 then slid = true end    -- 机头还朝上、往下掉：机尾朝下往后滑
    if slid and fY < 0 then whip = true end             -- 之后机头甩到地平线以下
  end)
  check(s.ok, "不出 NaN")
  check(s.vMin < 20, string.format("速度掉到 %.0f 米 / 秒", s.vMin))
  check(slid, "机尾朝下往后滑")
  check(whip, "然后机头甩下去")
  check(s.wMax < 6, string.format("角速度最大 %.1f rad/s（不发散）", s.wMax))
end

print(bad == 0 and "全部通过" or ("不对 " .. bad .. " 处"))
