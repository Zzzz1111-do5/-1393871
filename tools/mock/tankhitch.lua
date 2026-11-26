-- 卡一下坦克速度不归零（用户 11-26：「然后目前卡 过一阵子就卡一回 卡的时候坦克速度就归零」）：python3 tools/mock/run.py tools/mock/tankhitch.lua
--   试驾场的大平地上按住 W 往前开，人为制造各种「卡一下」，每样都看：卡完 1 秒内车速不掉（≥ 卡前的八五成）、
--   位置不往回跳、服务器没有拉回（op = fix）、车（客户端 G.drive）没有被重建：
--   ① 正在换档（离合断开）时卡 0.4 秒
--   ② 客户端卡 0.5 秒，卡的那一帧发出的包晚走、和卡完的下一包挤在一起到服务器（真 Roblox 的网络在帧尾才发：帧里卡住，这一帧的包跟着晚走）
--   ③ 服务器卡 0.6 秒（这段时间的包攒着，一帧里一起处理）
--   ④ 网络抖动 4 秒：每包随机晚 0～180 毫秒（远程事件可靠、有序，按顺序到），中间再卡两次 0.3 秒
--   ⑤ 一帧 dt = 0.5、1.0 秒（包马上到）
--   ⑥ 服务器硬拉回一次（op = fix）：车被挪回去，车速照旧
--   ⑦ 拉回之后、客户端还没收到之前发出的旧包：服务器不再接着拉（一次拉回不连成一串）
--   ⑧ 真瞬移（一包挪 400 格）照样拉回
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check

T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)

local me = T.join("P1", 9811, true)
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

T.act("testDrive", "de_leo2a6")   -- 试驾场：前面一大块平地
T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 15)
R.run(2)
local st = C.drive
local e = P.vehicle
check(st ~= nil and e ~= nil, "坐在车里")
if not st or not e then T.summary() return end
local d = st.d

-- 客户端 → 服务器的开车包（op = state）在这里拦一道：hold 全攒着、lag 每包晚多少秒（按顺序到）
local sig = G.R.Drive.OnServerEvent
local fire0 = sig.Fire
local held, lastAt = {}, 0
local net = { hold = false, lag = nil }
sig.Fire = function(self, pl, m, ...)
  if type(m) == "table" and m.op == "state" and (net.hold or net.lag) then
    local at = net.hold and math.huge or (R.clock() + net.lag())
    if at < lastAt then at = lastAt end
    lastAt = at
    table.insert(held, { pl = pl, m = m, at = at })
    return
  end
  return fire0(self, pl, m, ...)
end
local function release(upTo)   -- 到点的（upTo 没给：全部）按顺序在同一刻交给服务器
  local rest = {}
  for _, h in ipairs(held) do
    if not upTo or h.at <= upTo then R.as("server", function() fire0(sig, h.pl, h.m) end) else rest[#rest + 1] = h end
  end
  held = rest
end
-- 服务器发给这个人的「拉回」
local function fixesSince(i0)
  local n = 0
  for i = i0, #R.sent do
    local s = R.sent[i]
    if s.name == "Drive" and type(s.args[1]) == "table" and s.args[1].op == "fix" then n = n + 1 end
  end
  return n
end

local fwd0 = V3(-math.sin(st.yaw), 0, -math.cos(st.yaw))
local function prog() return (C.drive and C.drive.pos or V3()):Dot(fwd0) end
-- 往前开 sec 秒（dtf(t) 给每帧的 dt，没给 1/30）：最低车速、位置最多往回跳了多少、车有没有被重建
local function drive(sec, dtf, each)
  local vmin, back, rebuilt = math.huge, 0, false
  local hi = prog()
  local t = 0
  while t < sec do
    local dt = dtf and dtf(t) or 1 / 30
    R.step(dt)
    if net.lag then release(R.clock()) end
    if each then each(t) end
    t = t + dt
    if C.drive ~= st then rebuilt = true end
    vmin = math.min(vmin, C.drive and C.drive.speed or 0)
    local p = prog()
    if p < hi - 0.5 then back = math.max(back, hi - p) end
    hi = math.max(hi, p)
  end
  return vmin, back, rebuilt
end
-- 一样「卡」做完以后的检查
local function judge(name, v0, vmin, back, rebuilt, fx, allowFix)
  check(vmin >= v0 * 0.85, string.format("%s：车速不掉（卡前 %.1f、之后最低 %.1f 格 / 秒）", name, v0, vmin))
  if not allowFix then
    check(back < 0.5 and fx == 0, string.format("%s：没被拉回（服务器拉回 %d 次、位置往回跳 %.1f 格）", name, fx, back))
  end
  check(not rebuilt, name .. "：车没被重建（G.drive 还是原来那个）")
  local gap = (V3(e.root.CFrame.Position.X, 0, e.root.CFrame.Position.Z) - V3(st.root.Position.X, 0, st.root.Position.Z)).Magnitude
  check(gap < 25, string.format("%s：服务器那边的车跟上了（差 %.1f 格）", name, gap))
end

print("① 换档时卡 0.4 秒")
T.key(Enum.KeyCode.W, true)
local cutSeen = T.runUntil(function() return st.gb and st.gb.cut > 0 and st.gb.g >= 1 end, 12, 1 / 30)
check(cutSeen, "起步后升档（离合断开）")
do
  local v0, g0 = st.speed, st.gb and st.gb.g
  local i0 = #R.sent + 1
  local vmin, back, rebuilt = drive(1.4, function(t) return (t == 0) and 0.4 or 1 / 30 end)
  judge("换档时卡", v0, vmin, back, rebuilt, fixesSince(i0))
  check(st.gb and st.gb.g > (g0 or 0), string.format("卡完离合接上、进了下一档（%s → %s）", tostring(g0), tostring(st.gb and st.gb.g)))
end

-- 开到高档、接近极速
T.runUntil(function() return st.speed > d.speed * 0.8 end, 30, 1 / 30)
R.run(1.5)
local vTop = st.speed
check(vTop > d.speed * 0.75, string.format("开到 %.1f 格 / 秒（极速 %.1f）", vTop, d.speed))

print("② 客户端卡 0.5 秒，前一包晚走、和卡完的那包挤在一起到")
do
  local v0 = st.speed
  local i0 = #R.sent + 1
  net.hold = true
  st.sendT = 0                -- 卡住的这一帧正好要发一包
  R.step(1 / 30)              -- 卡住的这一帧（包发了，网络还没走）
  R.step(0.5)                 -- 卡完的下一帧：dt 0.5 秒
  net.hold = false
  release()                   -- 两包挤在一起到服务器
  local vmin, back, rebuilt = drive(1.5)
  judge("客户端卡、包挤在一起", v0, vmin, back, rebuilt, fixesSince(i0))
end

print("③ 服务器卡 0.6 秒（包攒着一起处理）")
do
  local v0 = st.speed
  local i0 = #R.sent + 1
  net.hold = true
  R.run(0.6, 1 / 30)
  net.hold = false
  release()
  local vmin, back, rebuilt = drive(1.5)
  judge("服务器卡", v0, vmin, back, rebuilt, fixesSince(i0))
end

print("④ 网络抖动 4 秒（每包晚 0～180 毫秒），中间客户端再卡两次 0.3 秒")
do
  local v0 = st.speed
  local i0 = #R.sent + 1
  net.lag = function() return math.random() * 0.18 end
  local vmin, back, rebuilt = drive(4, function(t) if math.abs(t - 1) < 0.02 or math.abs(t - 2.5) < 0.02 then return 0.3 end return 1 / 30 end)
  net.lag = nil
  release()
  local vmin2, back2, rebuilt2 = drive(1)
  judge("网络抖动", v0, math.min(vmin, vmin2), math.max(back, back2), rebuilt or rebuilt2, fixesSince(i0))
end

print("⑤ 一帧 dt = 0.5、1.0 秒（包马上到）")
for _, big in ipairs({ 0.5, 1.0 }) do
  local v0 = st.speed
  local i0 = #R.sent + 1
  local vmin, back, rebuilt = drive(1.5, function(t) return (t == 0) and big or 1 / 30 end)
  judge("一帧 " .. big .. " 秒", v0, vmin, back, rebuilt, fixesSince(i0))
end

print("⑥ 服务器硬拉回一次")
do
  local v0 = st.speed
  local fixN0 = e.fixN or 0
  R.as("server", function() G.R.Drive:FireClient(me, { op = "fix", cf = e.root.CFrame, n = fixN0 }) end)
  local vmin, back, rebuilt = drive(1.2)
  judge("服务器拉回", v0, vmin, back, rebuilt, 0, true)
end

print("⑦ 拉回之后、客户端还没收到之前的旧包")
do
  local v0 = st.speed
  local i0 = #R.sent + 1
  -- 服务器把车往后挪 30 格（像别的原因拉回了一次）、拉回的消息 0.15 秒以后才到客户端；这期间客户端照旧发包
  local back0 = e.root.CFrame - fwd0 * 30
  local fixN = (e.fixN or 0) + 1
  R.as("server", function()
    e.fixN, e.fixT = fixN, os.clock()
    G.moveEnt(e, back0)
  end)
  local sent = false
  local vmin, back, rebuilt = drive(1.5, nil, function(t)
    if not sent and t >= 0.15 then
      sent = true
      R.as("server", function() G.R.Drive:FireClient(me, { op = "fix", cf = back0, n = fixN }) end)
    end
  end)
  local extra = fixesSince(i0) - 1
  check(extra == 0, string.format("拉回只有那一次（旧包没再引出 %d 次拉回）", math.max(extra, 0)))
  check(vmin >= v0 * 0.85, string.format("拉回以后车速照旧（卡前 %.1f、之后最低 %.1f）", v0, vmin))
  check(not rebuilt, "车没被重建")
end

print("⑧ 真瞬移照样拉回")
do
  local i0 = #R.sent + 1
  R.step(0.2)
  R.as("server", function()
    G.driveInput(P, { op = "state", cf = e.root.CFrame + fwd0 * 400, ty = 0, gp = 0, sp = st.speed, fn = e.fixN })
  end)
  R.run(0.3)
  check(fixesSince(i0) >= 1, "一包挪 400 格：服务器拉回")
end
T.key(Enum.KeyCode.W, false)
T.summary()
