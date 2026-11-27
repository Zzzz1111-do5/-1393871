-- 开飞机的手感（模拟器）：python3 tools/mock/run.py tools/mock/wtcrisp.lua
--   用户 11-26 晚：「每个飞机要有不同的参数」「现在飞机驾驶感觉过于灵敏」——飞行物理换成 FlightModel 的六自由度（每型自己的重量、推力、
--   翼面积、升力、阻力、过载、失速迎角、转动惯量、稳定性、阻尼），键盘杆量按住才慢慢推满：
--   ① 点一下 D（0.1 秒）：只滚一点（不再一点就甩出去）
--   ② 按住 D：一秒左右滚转快到头；松手半秒内停住
--   ③ 按住 S：一秒多过载才到九成，不冲过头；机头先转、航迹慢半拍；一直拉着掉速
--   ④ 各型不一样：歼-10C（轻、电传）滚得比 A-10（重、机械操纵）快、过载起得快；轰-6K 最慢
--   ⑤ 自由视角（用户 11-26 晚：「不要因为飞机的机动动作而影响」「改成鼠标右键拖动」）：按住右键时飞机滚转、拉杆，镜头看的方向不变
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.allowInfantry = true   -- 先当步兵出生，再空中坐进测试放的飞机
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
R.run(1)
local C = T.C
local CFr = R.CFrame
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
local gy = math.max(G.Map.ground(0, 0), 0)

-- 空中坐进一架，摆成平飞（服务器那边也摆过去，不然当成瞬移拉回去）
local cur = nil
local function board(id)
  if cur and cur.model and cur.model.Parent then
    T.remoteAs(me, "Drive", { op = "exit" })
    R.run(0.5)
    G.removeEnt(cur)
    R.run(0.3)
  end
  local acf = CF(0, gy + 1200, 0)
  local jet = G.spawnAircraft("atk", id, acf, nil, P)
  P.char:PivotTo(acf * CF(4, 0, 0))
  T.act("enterVeh", jet.id)
  R.run(0.3)
  cur = jet
  local st = C.fly
  if st then
    C.flyMouseAim(false)
    st.ground = false
    st.gearWant, st.gear = 0, 0
  end
  return st, jet
end
local function reset(st, jet, spd, thr)
  local p = CF(0, gy + 1200, 0)
  local look = V3(0, 0, -1)
  st.cf = CFr.lookAt(p.Position, p.Position + look)
  st.vdir, st.spd, st.vel = look, spd, look * spd
  st.pr, st.rr, st.yr = 0, 0, 0
  st.thr, st.thrE = thr, thr
  st.kP, st.kR, st.kY = 0, 0, 0
  st.ground, st.gearWant, st.gear = false, 0, 0
  G.moveEnt(jet, st.cf)
  jet.vel = st.vel
  jet.syncT, jet.syncSlack = os.clock(), 160
end
local function bankDeg(st) return math.deg(math.atan2(-st.cf.RightVector.Y, st.cf.UpVector.Y)) end
local DT = 1 / 30
local function run(sec, each)
  local t = 0
  while t < sec - 1e-6 do
    R.run(DT)
    t = t + DT
    if each then each(t) end
  end
end

local cerr = {}
local se0 = C.showError
C.showError = function(msg)   -- 客户端回调出错只写在红条上（init.client.lua 的 pcall 接住）：也收下来
  if #cerr < 5 then print("  客户端报错：" .. tostring(msg)) end
  table.insert(cerr, tostring(msg))
  if se0 then se0(msg) end
end
local res = {}
local function trial(id, full)
  local st, jet = board(id)
  check(st ~= nil and st.pilot and st.d.id == id and st.fmD ~= nil, "空中坐进 " .. id .. "（有自己的飞行物理数据 " .. tostring(st and st.fmD and st.fmD.key) .. "）")
  if not st then return end
  local D = st.fmD
  local V0 = math.min(D.vne * 0.6, st.d.vMil * 0.85 / 2.8) * 2.8
  local out = { id = id }
  -- ① 点一下 D
  reset(st, jet, V0, 90)
  run(0.5)
  local b0 = bankDeg(st)
  T.key(Enum.KeyCode.D, true)
  run(0.1)
  T.key(Enum.KeyCode.D, false)
  run(1.0)
  out.tap = math.abs(bankDeg(st) - b0)
  -- ② 按住 D 1.6 秒、松手
  reset(st, jet, V0, 90)
  run(0.5)
  T.key(Enum.KeyCode.D, true)
  local pMax, t85 = 0, nil
  local samples = {}
  run(1.6, function(t)
    local p = math.deg(st.rr or 0)
    pMax = math.max(pMax, p)
    table.insert(samples, { t, p })
  end)
  for _, s in ipairs(samples) do if not t85 and s[2] >= 0.85 * pMax then t85 = s[1] end end
  T.key(Enum.KeyCode.D, false)
  local stopT, extra, last = nil, 0, bankDeg(st)
  run(1.2, function(t)
    local b = bankDeg(st)
    local db = (b - last + 540) % 360 - 180
    last = b
    if not stopT then extra = extra + math.abs(db) end
    if not stopT and math.abs(math.deg(st.rr or 0)) < 0.08 * pMax then stopT = t end
  end)
  out.roll, out.t85, out.stop, out.extra = pMax, t85 or 9, stopT or 9, extra
  -- ③ 按住 S 3 秒
  if full then
    reset(st, jet, V0, 100)
    run(0.5)
    T.key(Enum.KeyCode.S, true)
    local gh, aoaMax, lag = {}, 0, false
    local v0 = st.spd
    run(3.0, function(t)
      table.insert(gh, { t, st.gLoad or 1 })
      aoaMax = math.max(aoaMax, st.aoaDeg or 0)
      if (st.aoaDeg or 0) > 2 and st.vdir and st.cf.LookVector:Dot(st.vdir) < 0.9995 then lag = true end
    end)
    T.key(Enum.KeyCode.S, false)
    local gEnd = gh[#gh][2]
    local gPeak, t90 = 0, nil
    for _, s in ipairs(gh) do
      gPeak = math.max(gPeak, s[2])
      if not t90 and s[2] >= 1 + 0.9 * (gEnd - 1) then t90 = s[1] end
    end
    out.gEnd, out.gPeak, out.tG, out.aoa, out.lag, out.bleed = gEnd, gPeak, t90 or 9, aoaMax, lag, st.spd / v0
  end
  res[id] = out
  print(string.format("  %s：点一下 D 滚 %.0f°；按住 %.2f 秒到 %.0f°/s 的八成五、松手 %.2f 秒停（多滚 %.0f°）%s", id, out.tap, out.t85, out.roll, out.stop, out.extra,
    full and string.format("；拉杆 %.2f 秒到 %.1f g 的九成（最高 %.1f g、迎角 %.0f°、3 秒后速度剩 %.0f%%）", out.tG, out.gEnd, out.gPeak, out.aoa, out.bleed * 100) or ""))
  return st, jet
end

print("①②③ 歼-10C（轻、电传）")
local st, jet = trial("j10", true)
local r = res.j10
if r then
  check(r.tap < 25, string.format("点一下 D 只滚 %.0f°（不一点就甩出去）", r.tap))
  check(r.t85 > 0.35 and r.t85 < 1.3, string.format("按住 D %.2f 秒滚转到八成五（不是一按就满）", r.t85))
  check(r.stop < 0.7, string.format("松手 %.2f 秒停住", r.stop))
  check(r.tG > 0.5 and r.tG < 1.8, string.format("按住 S %.2f 秒过载到九成（稳住 %.1f g）", r.tG, r.gEnd))
  check(r.gPeak <= r.gEnd * 1.2 + 0.3, string.format("过载不冲过头（最高 %.1f、稳住 %.1f）", r.gPeak, r.gEnd))
  check(r.lag and r.aoa > 3, string.format("机头先转、航迹慢半拍（迎角最大 %.1f°）", r.aoa))
  check(r.bleed < 0.97, string.format("一直拉着掉速（剩 %.0f%%）", r.bleed * 100))
end

print("⑤ 自由视角：按住右键，飞机滚转时镜头看的方向不变")
if st and jet then
  reset(st, jet, st.d.vMil * 0.8, 90)
  run(0.6)
  C.flyFreeLook(true)
  run(0.4)
  local cam = R.services.Workspace.CurrentCamera
  local look0 = cam.CFrame.LookVector
  local up0 = cam.CFrame.UpVector
  T.key(Enum.KeyCode.D, true)
  local maxDev, maxRoll = 0, 0
  run(1.2, function()
    local lk = cam.CFrame.LookVector
    maxDev = math.max(maxDev, math.deg(math.acos(clamp(lk:Dot(look0), -1, 1))))
    maxRoll = math.max(maxRoll, math.abs(bankDeg(st)))
  end)
  T.key(Enum.KeyCode.D, false)
  local upDev = math.deg(math.acos(clamp(cam.CFrame.UpVector:Dot(up0), -1, 1)))
  check(maxRoll > 60, string.format("飞机滚过去了（坡度到 %.0f°）", maxRoll))
  check(maxDev < 6 and upDev < 6, string.format("自由视角看的方向没跟着转（偏 %.1f°，画面歪 %.1f°）", maxDev, upDev))
  C.flyFreeLook(false)
  run(1.0)
  local lk = cam.CFrame.LookVector
  local nose = st.cf.LookVector
  check(lk:Dot(nose) > 0.85, "松开右键：镜头回到机身后面")
end

print("④ 各型不一样")
trial("a10c", true)
trial("h6k", true)
local a, b, h = res.j10, res.a10c, res.h6k
if a and b and h then
  check(a.roll > b.roll * 1.6 and b.roll > h.roll * 2, string.format("滚转：歼-10C %.0f > A-10C %.0f > 轰-6K %.0f °/s", a.roll, b.roll, h.roll))
  check(a.tG < h.tG, string.format("过载起来：歼-10C %.2f 秒比轰-6K %.2f 秒快", a.tG, h.tG))
  check(h.gEnd < 3.2, string.format("轰-6K 拉满也就 %.1f g（过载上限 2.5）", h.gEnd))
end
check(#cerr == 0, "客户端没有报错：" .. table.concat(cerr, " | ", 1, math.min(#cerr, 3)))
T.summary()
