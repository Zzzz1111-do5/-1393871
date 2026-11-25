-- 各型导弹的发动机、能量、尾烟（模拟器）：python3 tools/mock/run.py tools/mock/missiles.lua
--   用户 11-24 夜：「各种导弹……不同导弹尾烟 动能 速度都是不一样的」——服务器 Air.lua 的导引按 AirDefs 的 burn / pulse / cruise / g / bleed 飞，
--   客户端 Fx.lua 按 smoke 画尾烟：
--   ① AIM-9X：烧 3.4 秒到最快，烧完很快掉速；AIM-54（大弹）掉得慢——同样滑翔 6 秒后剩的速度比例 AIM-54 高
--   ② 霹雳-15 双脉冲：第一次烧完掉速，第 9 秒第二次点火又加上去
--   ③ 巡航弹（鹰击-83K）发动机一直开，匀速
--   ④ 过载按速度²：满速时转得快，掉到一半速度时转弯角速度少一半左右
--   ⑤ 尾烟：AIM-54 浓、AIM-120 淡、巡航弹起飞助推那一下浓；发动机关了不冒烟
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3 = T.R, T.V3
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
check(G.airGuideMissile ~= nil, "服务器的导弹导引函数在")
if not G.airGuideMissile then T.summary() return end

-- 一枚弹直直往前飞（没有目标、瞄准点在正前方很远）：按 dt 一步步推
local function fly(wid, secs, opts)
  local w = AD.W[wid]
  local s = { pos = V3(0, 3000, 0), vel = V3(0, 0, -w.speed * 0.3), w = w, age = 0, aimPt = V3(0, 3000, -1e7), src = { team = "atk", name = "t" } }
  if opts and opts.side then s.aimPt = V3(1e7, 3000, 0) end   -- 一直往右边拐（测转弯）
  local log, dt = {}, 1 / 30
  for i = 1, math.floor(secs / dt) do
    G.airGuideMissile(s, dt)
    s.pos = s.pos + s.vel * dt
    if i % 3 == 0 then table.insert(log, { t = s.age, v = s.vel.Magnitude, dir = s.vel.Unit }) end
  end
  return log, w
end
local function at(log, t)
  for _, e in ipairs(log) do if e.t >= t then return e end end
  return log[#log]
end

print("① 近距弹烧完很快掉速，大弹掉得慢")
local l9, w9 = fly("aim9x", 12)
local l54, w54 = fly("aim54", 18)
local v9max, v54max = at(l9, w9.burn).v, at(l54, w54.burn).v
check(v9max > w9.speed * 0.95, string.format("AIM-9X 烧完（%.1f 秒）到 %.0f 格/秒（最快 %d）", w9.burn, v9max, w9.speed))
local r9 = at(l9, w9.burn + 6).v / v9max
local r54 = at(l54, w54.burn + 6).v / v54max
check(r9 < 0.62, string.format("AIM-9X 滑翔 6 秒剩 %.0f%% 速度", r9 * 100))
check(r54 > r9 + 0.12, string.format("AIM-54 滑翔 6 秒剩 %.0f%%（比 AIM-9X 多）", r54 * 100))

print("② 霹雳-15 双脉冲")
local l15, w15 = fly("pl15", 16)
local vA, vB, vC = at(l15, w15.burn).v, at(l15, w15.pulse.at - 0.1).v, at(l15, w15.pulse.at + w15.pulse.t - 0.1).v
check(vB < vA * 0.85, string.format("第一次烧完到第 9 秒掉到 %.0f（烧完时 %.0f）", vB, vA))
check(vC > vB * 1.15, string.format("第二次点火又加上去：%.0f 格/秒", vC))

print("③ 巡航弹匀速")
local l83, w83 = fly("yj83k", 14)
check(math.abs(at(l83, 12).v - w83.speed) < w83.speed * 0.03, string.format("鹰击-83K 第 12 秒还是 %.0f 格/秒（%d）", at(l83, 12).v, w83.speed))

print("④ 过载按速度²")
local function turnRate(wid, vK)
  local w = AD.W[wid]
  -- 目标在右前方 45°（导引头视场以内；正右边 90° 超出 75° 的导引头框，弹会当成丢了目标直飞）
  local s = { pos = V3(0, 3000, 0), vel = V3(0, 0, -w.speed * vK), w = w, age = 50, aimPt = V3(1e7, 3000, -1e7), src = { team = "atk", name = "t" } }   -- age 50：发动机早关了
  local d0 = s.vel.Unit
  G.airGuideMissile(s, 0.1)
  return math.deg(math.acos(math.max(-1, math.min(1, s.vel.Unit:Dot(d0))))) / 0.1
end
local tF, tH = turnRate("aim120", 0.95), turnRate("aim120", 0.45)
check(tH < tF * 0.7, string.format("AIM-120 满速时每秒转 %.0f°、半速时 %.0f°（后段的弹转不动）", tF, tH))

print("⑤ 尾烟")
check(AD.smokeOf(AD.W.aim54, 1) == "heavy" and AD.smokeOf(AD.W.aim120, 1) == "low", "AIM-54 浓烟、AIM-120 低烟")
check(AD.smokeOf(AD.W.yj83k, 1) == "heavy" and AD.smokeOf(AD.W.yj83k, 5) == "low", "巡航弹起飞助推那一下浓烟，之后涡喷淡")
check(AD.motorOn(AD.W.aim9x, 2) == true and AD.motorOn(AD.W.aim9x, 6) == false, "AIM-9X 第 6 秒发动机关了（不冒烟、不发光）")
check(AD.motorOn(AD.W.pl15, 10) == true, "霹雳-15 第 10 秒第二次脉冲开着")

print("⑥ 抛射（用户 11-25「部分直升机我记得发射导弹是抛射」「或许不止直升机」）")
check(AD.EJ and AD.EJ.tube and AD.EJ.drop, "有抛射表（筒射 / 弹射下落）")
check(AD.W.aim92.eject == "tube" and AD.W.igla.eject == "tube" and AD.W.ty90.eject == "tube", "直升机的毒刺、针-V、天燕-90 筒射")
check(AD.W.aim9x.eject == nil and AD.W.agm114.eject == nil, "响尾蛇、地狱火照旧在导轨上点火")
local bayMain, ejSt = 0, 0
for _, a in pairs(AD.D or {}) do
  for _, st in ipairs(a.st or {}) do
    if st.bay == "main" then bayMain = bayMain + 1 end
    if st.ej then ejSt = ejSt + 1 end
  end
end
check(bayMain >= 10 and ejSt >= 8, string.format("主弹舱挂点 %d 个、标了弹射挂架的机身挂点 %d 个", bayMain, ejSt))
do   -- 从弹舱弹射下去：先只往下掉、不加速不导引，ejT 秒后点火（发动机时间从点火算）
  local w = AD.W.aim120
  local E = AD.EJ.drop
  local s = { pos = V3(0, 3000, 0), vel = V3(0, -E.d, -200), w = w, age = 0, ejT = E.t, aimPt = V3(1e7, 3000, 0), src = { team = "atk", name = "t" }, id = "ejtest" }
  local dt = 1 / 30
  local n = math.floor(E.t / dt) - 1
  for _ = 1, n do G.airGuideMissile(s, dt) s.pos = s.pos + s.vel * dt end
  check(s.age == 0, string.format("弹射的 %.2f 秒里发动机没开（age %.2f）", n * dt, s.age))
  check(s.vel.Y < -E.d - 5 and math.abs(s.vel.X) < 1, string.format("只往下掉、不往目标拐（下落 %.0f 格/秒，横向 %.1f）", -s.vel.Y, s.vel.X))
  for _ = 1, 45 do G.airGuideMissile(s, dt) s.pos = s.pos + s.vel * dt end
  check(s.age > 1 and s.vel.Magnitude > 400 and s.vel.X > 50, string.format("点火以后加速、往目标拐（%.0f 格/秒）", s.vel.Magnitude))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
