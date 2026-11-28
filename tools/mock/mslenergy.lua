-- 导弹能量（模拟器）：python3 tools/mock/run.py tools/mock/mslenergy.lua
--   用户 11-28「iff和导弹能量都搞一下」（照战雷）：服务器 Air.lua guideMissile 的速度——
--   ① 助推加速、续航顶住、烧完以后按阻力一直掉（不再一出架就到最快、烧完前一直保持）
--   ② 不分高低（用户 11-28「这个不需要引入空气密度差异」）：同样的弹、同样的出手速度，高处低处掉得一样
--   ③ 爬升掉速（重力沿弹道的分量）：往上 60° 打的比平飞的慢
--   ④ 急转弯掉速（诱导阻力）：转 90° 去追的比直飞的慢
--   ⑤ 没能量了（发动机关了、掉到 0.3 倍额定速度以下）：导引头放弃、一秒后自毁（原来最低保持 0.22 倍一直飞）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local w = AD.W.aim120
check(w ~= nil and w.speed > 1000 and (w.burn or 0) > 2, string.format("AIM-120：额定 %.0f 格 / 秒、发动机 %.1f 秒", w and w.speed or -1, w and w.burn or -1))

local function fire(pos, vel, extra)
  local s = G.launch({ kind = "missile", pos = pos, vel = vel, w = w, src = { team = "atk", name = "test" }, ignore = {}, life = 90,
    step = G.airGuideMissile, age = 0 })
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function alive(s)
  for _, x in ipairs(G.shots) do if x == s then return true end end
  return false
end
local function spdOf(s) return s.vel.Magnitude / w.speed end
local function run(t) T.runUntil(function() return false end, t, 1 / 30) end

-- 海上、离地 / 海面都远（不撞东西）
local gy = math.max(G.Map.ground(0, 0), 0)
local LOW, HIGH = gy + 1400, gy + 7000
local fwd = V3(0, 0, -1)
local v0 = w.speed * 0.32

print("① 助推、续航、烧完了一直掉")
local a = fire(V3(-6000, LOW, 6000), fwd * v0)
local peak, peakT, t0 = 0, 0, R.clock()
local atBurn = nil
while R.clock() - t0 < w.burn + 6 and alive(a) do
  run(0.1)
  local k = spdOf(a)
  if k > peak then peak, peakT = k, R.clock() - t0 end
  if not atBurn and R.clock() - t0 >= w.burn then atBurn = k end
end
local after = alive(a) and spdOf(a) or 0
check(peak > 0.85 and peak < 1.31, string.format("出手 0.32 倍，助推到最快 %.2f 倍（第 %.1f 秒）", peak, peakT))
check(peakT > 0.5, "不是一出架就到最快（原来 0.5 秒内到顶）")
check(atBurn ~= nil and atBurn > 0.75, string.format("续航顶住：烧完那一刻还有 %.2f 倍", atBurn or -1))
check(after < (atBurn or 0) - 0.08, string.format("烧完再过 6 秒掉到 %.2f 倍", after))
a.life = 0

print("② 不分高低")
local lo = fire(V3(-3000, LOW, 6000), fwd * w.speed)
local hi = fire(V3(-1000, HIGH, 6000), fwd * w.speed)
lo.age, hi.age = w.burn + 0.1, w.burn + 0.1   -- 发动机都已经关了：只看滑翔
run(6)
local kl, kh = spdOf(lo), spdOf(hi)
check(math.abs(kh - kl) < 0.01, string.format("同样满速出手滑 6 秒：低处 %.2f 倍、高处（%d 格）%.2f 倍", kl, HIGH, kh))
lo.life, hi.life = 0, 0

print("③ 爬升掉速")
local lv = fire(V3(1000, LOW, 6000), fwd * v0)
local up = fire(V3(3000, LOW, 6000), (fwd * 0.5 + V3(0, 0.866, 0)) * v0)
run(w.burn)
check(spdOf(up) < spdOf(lv) - 0.025, string.format("往上 60° 打的比平飞的慢（%.2f / %.2f 倍；重力 g·sin60°·烧的时间，真弹也就差这么多）", spdOf(up), spdOf(lv)))
lv.life, up.life = 0, 0

print("④ 急转弯掉速")
local st = fire(V3(5000, LOW, 6000), fwd * w.speed, { age = w.burn + 0.1 })
local tn = fire(V3(7000, LOW, 6000), fwd * w.speed, { age = w.burn + 0.1, aimPt = V3(7000 + 28000, LOW, 6000 - 28000) })   -- 目标点在右前 45°（导引头看得见）：满过载转过去
run(2.5)
check(spdOf(tn) < spdOf(st) - 0.05, string.format("转着追的比直飞的慢（%.2f / %.2f 倍）", spdOf(tn), spdOf(st)))
st.life, tn.life = 0, 0

print("⑥ 各型数据不一样、双脉冲、红外导引头分代（用户 11-28「不同导弹的数据要不一样别忘了」「双波段的 可以单独搞一下」）")
local sig, dup, miss = {}, {}, {}
for id, x in pairs(AD.W) do
  if x.kind == "aam" then
    if not x.mt or not x.dv or not x.out or (x.seeker == "ir" and not x.band) then table.insert(miss, id) end
    local k = table.concat({ tostring(x.speed), tostring(x.burn), tostring(x.g), tostring(x.bleed), tostring(x.mt), tostring(x.dv) }, "|")
    if sig[k] then table.insert(dup, sig[k] .. "=" .. id) end
    sig[k] = id
  end
end
table.sort(miss)
check(#miss == 0, "每一型空空弹都写了发动机、能量、（红外的）导引头" .. ((#miss > 0) and ("（缺：" .. table.concat(miss, " ") .. "）") or ""))
check(#dup == 0, "没有两型空空弹的数据完全一样" .. ((#dup > 0) and ("（" .. table.concat(dup, " ") .. "）") or ""))
check(AD.W.aim9x.band == "img" and AD.W.aim92.band == "2" and AD.W.igla.band == "2" and AD.W.r60.band == "1",
  "红外导引头：AIM-9X 成像、毒刺 / 针 双色、R-60 老式单色")
local pw = AD.W.pl15
local w0 = w
w = pw
local pp = fire(V3(11000, LOW, 6000), fwd * pw.speed * 0.6, { age = pw.pulse.at - 1.2 })
run(1.1)
local before = spdOf(pp)
run(pw.pulse.t * 0.8)
local after2 = spdOf(pp)
check(after2 > before + 0.15, string.format("霹雳-15 第二次脉冲：%.2f → %.2f 倍（再加一截）", before, after2))
pp.life = 0
w = w0

print("⑤ 没能量了：导引头放弃、一秒后自毁")
local n0 = #R.sent
local slow = fire(V3(9000, LOW, 6000), fwd * w.speed * 0.34, { age = w.burn + 0.1, aimPt = V3(9000, LOW, -40000) })
T.runUntil(function() return not alive(slow) end, 12, 1 / 30)
check(not alive(slow), "掉到 0.3 倍以下：没飞完寿命就自毁了")
check(slow.aimPt == nil and slow.tgt == nil, "自毁前导引头先放弃")
local boom = false
for i = n0 + 1, #R.sent do
  local s = R.sent[i]
  if s.name == "Fx" and type(s.args[1]) == "table" then
    for _, f in ipairs(s.args[1]) do if type(f) == "table" and f.k == "boom" and f.c == "msl" then boom = true end end
  end
end
check(boom, "自毁：空中一小团")
T.summary()
