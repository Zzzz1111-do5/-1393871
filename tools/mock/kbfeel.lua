-- 键盘开飞机的手感（模拟器）：python3 tools/mock/run.py tools/mock/kbfeel.lua [id=f16] [check=1]
--   用户 11-28「然后目前飞机操控有些奇怪 和我玩的空战飞机驾驶有区别」「有时候不该灵敏的时候过于灵敏 该灵敏的时候又有点迟钝」：
--   三个速度（350 / 550 / 750 格每秒）各量一遍——
--     点一下 S（0.08 秒）：过载最大多少、机头抬几度（小修正：该细）
--     按住 S：0.15 / 0.3 / 0.5 秒时的过载（猛拉：该很快起来）
--     点一下 D（0.08 秒）：滚了几度；按住 D：0.15 / 0.3 / 0.5 秒的滚转角速度；按住一秒松手：松手以后还滚了几度（该干脆停住）
--   check=1：照战雷的手感查（点一下的不超过一个量、按住 0.35 秒到满杆的八成以上、松手多滚的不多）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local ID = TEST_ARGS:match("id=(%w+)") or "f16"
local CHECK = TEST_ARGS:find("check=1", 1, true) ~= nil
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.allowInfantry = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9851, true)
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
local Y = gy + 2600
local jet = G.spawnAircraft("atk", ID, CF(0, Y, 0), nil, P)
P.char:PivotTo(CF(6, Y, 0))
T.act("enterVeh", jet.id)
R.run(0.3)
local st = C.fly
check(st ~= nil and st.pilot, "坐进了 " .. ID)
if not st then T.summary() return end
C.flyMouseAim(false)
local DT = 1 / 60
local function level(v)
  local p = V3(0, Y, 0)
  local look = V3(0, 0, -1)
  st.cf = CFr.lookAt(p, p + look)
  st.vdir, st.spd, st.vel = look, v, look * v
  st.thr, st.thrE = 100, 100
  st.ground, st.gearWant, st.gear = false, 0, 0
  st.kP, st.kR, st.kY = 0, 0, 0
  G.moveEnt(jet, st.cf)
  jet.vel = st.vel
  jet.syncT, jet.syncSlack = os.clock(), 400
  R.run(0.6, DT)
  -- 摆回水平、速度放回去（跑 0.6 秒稳下来时掉了一点高度、速度）
  local p2 = V3(0, Y, 0)
  st.cf = CFr.lookAt(p2, p2 + look)
  st.vel = look * v
  st.spd = v
  G.moveEnt(jet, st.cf)
  R.run(0.15, DT)
end
local function bank()
  local r, u = st.cf.RightVector, st.cf.UpVector
  return math.deg(math.atan(-r.Y, u.Y))
end
local function pitch() return math.deg(math.asin(math.max(-1, math.min(1, st.cf.LookVector.Y)))) end
local function g() return st.gLoad or 1 end
local function hold(k, secs, marks)
  local out = {}
  T.key(k, true)
  local t, mi = 0, 1
  local b0 = bank()
  local bPrev, tPrev = b0, 0
  while t < secs - 1e-6 do
    R.run(DT, DT)
    t = t + DT
    if marks and marks[mi] and t >= marks[mi] - 1e-6 then
      local b = bank()
      out[#out + 1] = { t = t, g = g(), rate = (b - bPrev) / math.max(t - tPrev, 1e-3), b = b - b0 }
      bPrev, tPrev = b, t
      mi = mi + 1
    end
  end
  T.key(k, false)
  return out
end
local rows = {}
for _, v in ipairs({ 350, 550, 750 }) do
  local row = { v = v }
  -- 点一下 S
  level(v)
  local p0 = pitch()
  T.key(Enum.KeyCode.S, true)
  R.run(0.08, DT)
  T.key(Enum.KeyCode.S, false)
  local gmax = 1
  for _ = 1, 60 do R.run(DT, DT) gmax = math.max(gmax, g()) end
  row.tapG, row.tapP = gmax, pitch() - p0
  -- 按住 S
  level(v)
  local hs = hold(Enum.KeyCode.S, 0.5, { 0.15, 0.3, 0.5 })
  row.g15, row.g30, row.g50 = hs[1] and hs[1].g or 0, hs[2] and hs[2].g or 0, hs[3] and hs[3].g or 0
  R.run(0.8, DT)
  -- 点一下 D
  level(v)
  local b0 = bank()
  T.key(Enum.KeyCode.D, true)
  R.run(0.08, DT)
  T.key(Enum.KeyCode.D, false)
  R.run(1.0, DT)
  row.tapR = bank() - b0
  -- 按住 D：0.15 / 0.3 / 0.5 秒的滚转角速度
  level(v)
  local b1 = bank()
  local hr = {}
  T.key(Enum.KeyCode.D, true)
  local t, last, lt = 0, b1, 0
  local unwrap, prevB = 0, b1
  local function bankU()
    local b = bank()
    local d = b - prevB
    if d < -180 then d = d + 360 elseif d > 180 then d = d - 360 end
    unwrap = unwrap + d
    prevB = b
    return unwrap
  end
  local marks = { 0.15, 0.3, 0.5, 1.0 }
  local mi = 1
  while t < 1.0 - 1e-6 do
    R.run(DT, DT)
    t = t + DT
    local bu = bankU()
    if marks[mi] and t >= marks[mi] - 1e-6 then
      hr[#hr + 1] = (bu - last) / (t - lt)
      last, lt = bu, t
      mi = mi + 1
    end
  end
  T.key(Enum.KeyCode.D, false)
  local atRel = unwrap
  for _ = 1, 90 do R.run(DT, DT) bankU() end
  row.r15, row.r30, row.r50, row.r100 = hr[1] or 0, hr[2] or 0, hr[3] or 0, hr[4] or 0
  row.over = unwrap - atRel
  rows[#rows + 1] = row
  print(string.format("  %3d 格/秒：点 S %.2f g、抬 %.1f°；按住 S %.1f / %.1f / %.1f g（0.15 / 0.3 / 0.5 秒）；点 D 滚 %.0f°；按住 D %.0f / %.0f / %.0f / %.0f °/s；松手多滚 %.0f°",
    v, row.tapG, row.tapP, row.g15, row.g30, row.g50, row.tapR, row.r15, row.r30, row.r50, row.r100, row.over))
end
if CHECK then
  for _, r in ipairs(rows) do
    check(r.tapG < 1.9 and math.abs(r.tapR) < 14, string.format("%d 格/秒：点一下是小修正（%.2f g、滚 %.0f°）", r.v, r.tapG, r.tapR))
    check(r.g30 >= 0.75 * r.g50 and r.g50 > 2.5, string.format("%d 格/秒：按住 S 很快拉起来（0.3 秒 %.1f g，0.5 秒 %.1f g）", r.v, r.g30, r.g50))
    check(r.r30 >= 0.6 * r.r100, string.format("%d 格/秒：按住 D 0.3 秒滚转角速度到了最大的六成以上（%.0f / %.0f °/s）", r.v, r.r30, r.r100))
    check(math.abs(r.over) < 25, string.format("%d 格/秒：松手干脆停住（多滚 %.0f°）", r.v, r.over))
  end
end
T.summary()
