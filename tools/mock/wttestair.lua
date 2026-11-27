-- 飞机试驾（用户 11-27「飞机试驾不了」）：python3 tools/mock/run.py tools/mock/wttestair.lua
--   真游戏开着匹配（Config.Match.on）：没进局的人在「匹配中」的机库里，这里照这个跑（T.matchMode）——
--   ① 机库底下阵容里的飞机卡能选（原来 S.wt 一直有、这一局没出过地面车就整张卡禁选，点了不理，右边「试驾」只能开地面车）；
--      选中飞机点右边「试驾」：坐进这架飞机，停在训练场跑道东头、机头朝西、在地上；推满油门、到抬头速度拉杆：在跑道上离地、接着爬，
--      服务器不往回拉、飞机没坏、没报错；能开炮打靶（原来「匹配中」服务器、客户端都按没开战不让打）；长按 H 回机库
--   ② 阵容里的直升机也能选、试驾：停在训练场直升机坪，拉总距飞起来
--   ③ 科技树里点挂火箭巢的苏-25「试驾」：飞行物理的质量照真机（原来火箭巢按「巢里几发 × 一整个装满的巢」算：凭空重 27 吨、
--      43 吨推不动，推满油门滑出跑道几公里离不了地），在跑道上离地；按 F 打得出挂着的弹
--   ④ 地面车试驾在「匹配中」也能开炮；打空待发弹架以后会从车体弹架补回来（试驾审查 3：原来回补只在开战以后跑）
--   ⑤ 满油满弹在训练场跑道上滑不起来的（静态估的滑跑比跑道剩的长：轰-6K）直接在靶区上空出生、在飞（试驾审查 2）；歼-6 照旧在跑道上（①）
--   ① 里还查手机：摇杆往前推机头往下、往回拉机头往上（试驾审查 8：原来 Fly.lua pitchIn = mv.Z，反着）
--   局内选车（这一局算他的）照旧禁选飞机、没有「试驾」：tools/mock/match.lua ②
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)   -- 跑得久：一行一行写出来（重定向到文件时也看得见进度）
local R, Enum = T.R, T.Enum
local check = T.check

T.mapName = "city"
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local TT = R.require(RS:FindFirstChild("TechTree"))
local me = T.join("P1", 9561, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 120, 1 / 10)
R.run(1)
check(G.round.phase == "queue" and not (C.S and C.S.pick), "在匹配中的机库（还没进局）：" .. tostring(G.round.phase))
local RM = G.Map.Range
local A = RM.airfield()
local M = 2.8
local DT = 1 / 30

-- 服务器发给客户端的「拉回去」（Air.lua sync 不认客户端报的位置）
local fixSeen = #R.sent
local function fixes()
  local n = 0
  for i = fixSeen + 1, #R.sent do
    local s = R.sent[i]
    if s.name == "Drive" and type(s.args[1]) == "table" and s.args[1].op == "fix" then n = n + 1 end
  end
  fixSeen = #R.sent
  return n
end
local function selName()
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "SelName" then return d.Text end end
end
-- 坐进试驾的飞机以后：在不在训练场跑道东头、机头朝西、在地上
local function onRunway(e, st)
  local pa = e.root.CFrame.Position
  check(math.abs(pa.Z - A.z) < A.wid / 2 and math.abs(pa.X - A.x) < A.len / 2 and pa.X > A.x + A.len / 2 - 400,
    string.format("停在训练场跑道东头（离跑道中心 %.0f, %.0f 格）", pa.X - A.x, pa.Z - A.z))
  check(st.ground == true and st.cf.LookVector.X < -0.95, string.format("在地上、机头朝西（%.2f）", st.cf.LookVector.X))
end
-- 推满油门（有加力推到加力）、到抬头速度拉杆：离地在跑道上、接着爬
local function takeoff(e)
  local st = C.fly
  local d = st.d
  C.flyMouseAim(false)
  fixes()
  local p0 = st.cf.Position
  local runEnd = A.x - A.len / 2
  T.key(Enum.KeyCode.LeftShift, true)
  local t, pulled, liftX, liftT = 0, false, nil, nil
  while t < 60 do
    R.run(DT)
    t = t + DT
    st = C.fly
    if not st then break end
    if not pulled and st.spd >= d.vRot then
      pulled = true
      T.key(Enum.KeyCode.S, true)
    end
    if not st.ground then
      liftX, liftT = st.cf.Position.X, t
      break
    end
  end
  check(liftX ~= nil and liftX > runEnd, string.format("推满油门滑跑、拉杆：在跑道上离地（%s 秒、滑了 %s 格，跑道还剩 %s 格）",
    liftT and string.format("%.1f", liftT) or "?", liftX and string.format("%.0f", p0.X - liftX) or "?", liftX and string.format("%.0f", liftX - runEnd) or "?"))
  local yL = st and st.cf.Position.Y or 0
  R.run(2.5)
  T.key(Enum.KeyCode.S, false)
  R.run(5)
  st = C.fly
  local y1 = st and st.cf.Position.Y or 0
  check(st ~= nil and not st.crashed and y1 > yL + 40 * M, string.format("离地以后接着爬（7.5 秒爬了 %.0f 米）", (y1 - yL) / M))
  local nf = fixes()
  check(nf == 0, "服务器没往回拉（" .. nf .. " 次）")
  check(e.alive, "飞机没坏")
  T.key(Enum.KeyCode.LeftShift, false)
end
local function backToHangar()
  T.remoteAs(me, "Drive", { op = "exit", hangar = true })
  T.runUntil(function() return not P.alive end, 15)
  T.runUntil(function() return T.findNamed("HangarTest") ~= nil end, 10)
  R.run(1)
end
-- 试驾前服务器怎么估的（Tech.lua testDrive：AirDefs.takeoffRun 满油、默认挂载、改装全装的推力，比第 0 个起飞位往西剩下的跑道的九成五长就空中出生）
local AD = R.require(RS:FindFirstChild("AirDefs"))
local WM = R.require(RS:FindFirstChild("WtMods"))
local LEFT = RM.runwayLeft(0)
local function estRun(k)
  local it = TT.byKey[k]
  local all = {}
  for _, m in ipairs(WM.list(it)) do all[m.key] = true end
  return AD.takeoffRun(AD.get(it.play), { treeKey = k, thrK = WM.fx(it, all).thr, h = RM.runwayStart(0).Y })
end
-- 机头俯仰角（度，抬头为正）、俯仰角速度（飞行物理的 q，抬头为正）
local function nose()
  local st = C.fly
  if not st then return 0, 0 end
  local y = math.max(-1, math.min(1, st.cf.LookVector.Y))
  return math.deg(math.asin(y)), math.deg((st.fm and st.fm.q) or 0)
end
-- 手机（试驾审查 8）：摇杆直接当驾驶杆（Fly.lua jetPhysics：G.mobile 时读 controls:GetMoveVector()；模拟器里摇杆是 R.moveVec）——
--   往前推（MoveVector.Z = −1，同按 W）机头往下，往回拉（Z = +1，同按 S）机头往上。原来 pitchIn = mv.Z，正好反着
local function mobilePitch()
  local mob0 = C.mobile
  C.mobile = true
  R.moveVec = nil
  R.run(0.4)
  local calls0 = R.moveCalls or 0
  local a0 = nose()
  R.moveVec = T.V3(0, 0, -1)
  R.run(0.8)
  local a1, q1 = nose()
  R.moveVec = T.V3(0, 0, 1)
  R.run(1.2)
  local a2, q2 = nose()
  R.moveVec = nil
  C.mobile = mob0
  R.run(0.3)
  check((R.moveCalls or 0) > calls0, string.format("手机：摇杆当驾驶杆（读了 %d 次 MoveVector）", (R.moveCalls or 0) - calls0))
  check(a1 < a0 - 0.5 and q1 < 0, string.format("手机摇杆往前推：机头往下（%.1f° → %.1f°，俯仰角速度 %.1f°/s）", a0, a1, q1))
  check(a2 > a1 + 0.5 and q2 > 0, string.format("手机摇杆往回拉：机头往上（%.1f° → %.1f°，俯仰角速度 %.1f°/s）", a1, a2, q2))
end

print("① 机库阵容里的飞机：选中、右边「试驾」、跑道上起飞")
local keys = G.treeLineup(P)
local airKey, heliKey
for _, k in ipairs(keys) do
  local it = TT.byKey[k]
  if it and it.branch == "air" and not airKey then airKey = k end
  if it and it.branch == "heli" and not heliKey then heliKey = k end
end
check(airKey ~= nil and heliKey ~= nil, "阵容里有飞机、直升机（" .. table.concat(keys, " ") .. "）")
local card = airKey and T.findNamed("Line_" .. airKey)
check(card ~= nil and card:GetAttribute("Locked") ~= true, "飞机卡没被禁选（匹配中还没进局，原来整张压暗、点了不理）")
if card then T.press(card) R.run(0.5) end
check(airKey ~= nil and selName() == TT.byKey[airKey].name, "点飞机卡：右边选中这架飞机（" .. tostring(selName()) .. "）")
local tb = T.findNamed("HangarTest")
check(tb ~= nil, "右边有「试驾」")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local e = P.vehicle
check(e ~= nil and e.air and e.testDrive and e.treeKey == airKey, "坐进了试驾的飞机（" .. tostring(e and e.def and e.def.id) .. "，原来坐进的是坦克）")
R.run(1)
if e and e.air and C.fly then
  local rj, lj = estRun(airKey)
  check(rj ~= nil and lj and rj <= LEFT * 0.95, string.format("服务器估的满油满弹滑跑 %s 格，不到跑道剩的 %d 格的九成五：照旧摆在跑道上", rj and string.format("%.0f", rj) or "?", LEFT))
  onRunway(e, C.fly)
  takeoff(e)
  mobilePitch()
  -- 打靶：这一局还在「匹配中」——原来服务器、客户端都按「没开战」不让打（航炮不出弹、导弹炸弹弹「尚未开战」）
  local g0 = e.gunAmmo or 0
  T.mouse(true)
  R.run(1)
  T.mouse(false)
  R.run(0.3)
  check((e.gunAmmo or 0) < g0, string.format("匹配中试驾也能开炮（炮弹 %d → %d）", g0, e.gunAmmo or 0))
end
backToHangar()
check(not P.alive and not P.inTest, "长按 H 回机库")

print("② 阵容里的直升机：选中、试驾、拉总距飞起来")
card = heliKey and T.findNamed("Line_" .. heliKey)
check(card ~= nil and card:GetAttribute("Locked") ~= true, "直升机卡也能选")
if card then T.press(card) R.run(0.5) end
tb = T.findNamed("HangarTest")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local eh = P.vehicle
check(eh ~= nil and eh.air and eh.def.kind == "heli" and eh.treeKey == heliKey, "坐进了试驾的直升机（" .. tostring(eh and eh.def and eh.def.id) .. "）")
R.run(1)
if eh and eh.air and C.fly then
  local ph = eh.root.CFrame.Position
  local hp = RM.heliPad(0)
  check(math.abs(ph.X - hp.X) < 120 and math.abs(ph.Z - hp.Z) < 120 and C.fly.ground == true, string.format("停在训练场直升机坪上（偏 %.0f, %.0f）", ph.X - hp.X, ph.Z - hp.Z))
  fixes()
  local y0 = C.fly.cf.Position.Y
  T.key(Enum.KeyCode.E, true)
  T.runUntil(function() return C.fly == nil or C.fly.cf.Position.Y > y0 + 120 end, 20)
  T.key(Enum.KeyCode.E, false)
  R.run(1)
  local y1 = C.fly and C.fly.cf.Position.Y or y0
  check(y1 > y0 + 100, string.format("拉总距飞起来了（高了 %.0f 格）", y1 - y0))
  local nf = fixes()
  check(nf == 0 and eh.alive, "服务器没往回拉（" .. nf .. " 次）、直升机没坏")
end
backToHangar()

print("③ 科技树里挂火箭巢的苏-25：质量照真机，跑道上离地")
R.as("client", function() C.openTechTree() end)
R.run(0.3)
local panel = C.treeGui
local function find(name)
  for _, c in ipairs(panel and panel:GetDescendants() or {}) do if c.Name == name then return c end end
end
local key = "ru_su25"
for _, n in ipairs({ "Nat_ru", "Br_air", "Card_" .. key }) do
  local b = find(n)
  if b then T.press(b) R.run(0.3) end
end
tb = find("TestBtn")
check(tb ~= nil, "科技树详情里有「试驾」")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local es = P.vehicle
check(es ~= nil and es.air and es.treeKey == key, "坐进了试驾的苏-25（" .. tostring(es and es.def and es.def.id) .. "）")
R.run(1)
if es and es.air and C.fly then
  local AD = R.require(RS:FindFirstChild("AirDefs"))
  local rk = 0
  for i, w in ipairs(es.load or {}) do
    local W = w and AD.W[w]
    if W and W.kind == "rkt" and (es.stores[i] or 0) > 1 then rk = rk + 1 end
  end
  local m = C.flyMass()
  check(rk >= 2 and m > 12000 and m < 20000, string.format("挂着 %d 个火箭巢，质量 %.0f 公斤（真机最大起飞约 1.76 万；原来 4.3 万）", rk, m))
  onRunway(es, C.fly)
  takeoff(es)
  -- 按 F 打挂着的弹（选中的第一种）：匹配中照样打得出去
  local function left()
    local n = 0
    for _, k in ipairs(es.stores or {}) do n = n + k end
    return n
  end
  local s0 = left()
  T.key(Enum.KeyCode.F, true)
  R.run(0.2)
  T.key(Enum.KeyCode.F, false)
  R.run(1)
  check(left() < s0 and #T.texts("尚未开战") == 0, string.format("匹配中试驾也能打挂着的弹（服务器那边挂的 %d → %d，没弹「尚未开战」）", s0, left()))
end
backToHangar()

print("④ 地面车试驾也一样：匹配中照样能开炮打靶车")
local gKey
for _, k in ipairs(G.treeLineup(P)) do   -- ③ 在科技树里点了俄国旗：机库跟着换成俄系的阵容
  local it = TT.byKey[k]
  if it and it.branch == "ground" and not gKey then gKey = k end
end
card = gKey and T.findNamed("Line_" .. gKey)
if card then T.press(card) R.run(0.5) end
tb = T.findNamed("HangarTest")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil end, 30)
local eg = P.vehicle
check(eg ~= nil and not eg.air and eg.testDrive and eg.treeKey == gKey, "坐进了试驾的地面车（" .. tostring(eg and eg.def and eg.def.id) .. "）")
R.run(2)
if eg and not eg.air then
  local wid = eg.def.weapons[1]
  local ws = eg.wst and eg.wst[wid]
  local before = ws and (ws.mag + ws.reserve) or 0
  T.remoteAs(me, "Drive", { op = "fire", w = wid, dir = eg.root.CFrame.LookVector })
  R.run(0.5)
  ws = eg.wst and eg.wst[wid]
  local after = ws and (ws.mag + ws.reserve) or 0
  check(after < before, string.format("主炮打出去了（%s：%d → %d 发）", tostring(wid), before, after))
  -- 打空待发弹架（Wt.lua：转盘 22 发 / 尾舱 15 发）以后不开炮的时候从车体弹架一发一发补回来——原来回补（rackStep）只在开战以后跑，
  --   匹配中试驾打空了就一直不补、后面每一发都按从车体拿的慢速装（试驾审查 3）。这里把待发弹架当成刚打空（上面那一发记着 lastShot）
  if eg.rdyCap then
    eg.rdy = 0
    local ok = T.runUntil(function() return (eg.rdy or 0) > 0 end, 30, 1 / 10)
    check(ok and eg.model:GetAttribute("Rdy") == eg.rdy, string.format("匹配中试驾打空待发弹架：不开炮的时候补回来（待发 0 → %d / %d 发，属性 Rdy %s）",
      eg.rdy or 0, eg.rdyCap, tostring(eg.model:GetAttribute("Rdy"))))
  else
    check(false, "这辆车有待发弹架（" .. tostring(eg.def.id) .. "）")
  end
end
backToHangar()

print("⑤ 满油满弹在训练场跑道上滑不起来的大飞机（轰-6K）：直接在空中出生、在飞")
local hKey = "cn_h6k"
local rh, lh = estRun(hKey)
check(rh ~= nil and (not lh or rh > LEFT * 0.95), string.format("服务器估的满油满弹滑跑 %s 格（%s），比跑道剩的 %d 格的九成五长",
  rh and string.format("%.0f", rh) or "?", lh and "离得了地" or "两分钟离不了地", LEFT))
R.as("client", function() C.openTechTree() end)
R.run(0.3)
panel = C.treeGui
for _, n in ipairs({ "Nat_cn", "Br_air", "Card_" .. hKey }) do
  local b = find(n)
  if b then T.press(b) R.run(0.3) end
end
tb = find("TestBtn")
check(tb ~= nil, "科技树详情里有「试驾」")
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local eb = P.vehicle
check(eb ~= nil and eb.air and eb.testDrive and eb.treeKey == hKey, "坐进了试驾的轰-6K（" .. tostring(eb and eb.def and eb.def.id) .. "）")
R.run(1)
if eb and eb.air and C.fly then
  local st = C.fly
  local p = st.cf.Position
  local agl = p.Y - G.Map.height(p.X, p.Z)
  local tgt = RM.airTarget()
  local dH = math.sqrt((p.X - tgt.X) ^ 2 + (p.Z - tgt.Z) ^ 2)
  check(eb.onGround == false and st.ground == false and agl > 600, string.format("空中出生：没摆在跑道上，离地 %.0f 格（服务器 onGround = %s）", agl, tostring(eb.onGround)))
  check(dH < 3000, string.format("在北边靶区上空（离靶区中心 %.0f 格）", dH))
  check(st.spd > st.d.stall * 1.2, string.format("带着速度出来（%.0f 格 / 秒，失速 %.0f）", st.spd, st.d.stall))
  local msg = T.texts("滑不起来")
  print("  提示：" .. tostring(msg[1]))
  fixes()
  R.run(4)
  st = C.fly
  local p1 = st and st.cf.Position
  local agl1 = p1 and (p1.Y - G.Map.height(p1.X, p1.Z)) or 0
  check(st ~= nil and not st.crashed and eb.alive and not st.ground and agl1 > 400 and st.spd > st.d.stall,
    string.format("4 秒后还在飞（离地 %.0f 格、%.0f 格 / 秒）", agl1, st and st.spd or 0))
  local nf = fixes()
  check(nf == 0, "服务器没往回拉（" .. nf .. " 次）")
end
backToHangar()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
