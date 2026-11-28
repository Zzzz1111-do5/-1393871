-- 飞机试驾（用户 11-27「飞机试驾不了」）：python3 tools/mock/run.py tools/mock/wttestair.lua
--   真游戏开着匹配（Config.Match.on）：没进局的人在「匹配中」的机库里，这里照这个跑（T.matchMode）——
--   ① 机库底下阵容里的飞机卡能选（原来 S.wt 一直有、这一局没出过地面车就整张卡禁选，点了不理，右边「试驾」只能开地面车）；
--      选中飞机点右边「试驾」：坐进这架飞机，停在训练场跑道东头、机头朝西、在地上；推满油门、到抬头速度拉杆：在跑道上离地、接着爬，
--      服务器不往回拉、飞机没坏、没报错；能开炮打靶（原来「匹配中」服务器、客户端都按没开战不让打）；长按 H 回机库
--   ② 阵容里的直升机也能选、试驾：停在训练场直升机坪，拉总距飞起来
--   ③ 科技树里点挂火箭巢的苏-25「试驾」：飞行物理的质量照真机（原来火箭巢按「巢里几发 × 一整个装满的巢」算：凭空重 27 吨、
--      43 吨推不动，推满油门滑出跑道几公里离不了地），在跑道上离地（这一架像手机一样往回拉摇杆抬头）；按 F 打得出挂着的弹
--   ④ 地面车试驾在「匹配中」也能开炮；打空待发弹架以后会从车体弹架补回来（试驾审查 3：原来回补只在开战以后跑）
--   ⑤ 满油满弹在训练场跑道上滑不起来的（静态估的滑跑比跑道剩的长：轰-6K）直接在空中出生、在飞（试驾审查 2）；歼-6 照旧在跑道上（①）——
--      在靶区南边朝北进场、炸弹落点还没到靶子，先送过去的是空中那一片（后续审查 1、2：原来在靶区中心正上方出来、预加载的是跑道东头）
--   ⑥ 无人机 MQ-9：操作员站在跑道南边的地上、钉住；剩的跑道不够长时空中出生；跑道上摆不下的兜底提示不说「滑不起来」（后续审查 4、5）
--   ① 里还查手机：摇杆往前推机头往下、往回拉机头往上（试驾审查 8：原来 Fly.lua pitchIn = mv.Z，反着）；①③ 比服务器估的滑跑和真滑的（差不到 5%）
--   局内选车（这一局算他的）照旧禁选飞机、没有「试驾」、服务器也不让试驾：tools/mock/match.lua ②
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
-- 服务器第 since 条以后发的试驾提示（Tech.lua testDrive 最后那条 G.msg：tree.testOn / testOnAir / testOnPad / testOnSky / testInAir）——
--   看 R.sent 不看界面（提示条 4 秒就没了，连着几次试驾还会叠着）
local function testMsg(since)
  local k
  for i = since + 1, #R.sent do
    local s = R.sent[i]
    if s.name == "Msg" and type(s.args[2]) == "string" and s.args[2]:find("^tree%.test") then k = s.args[2] end
  end
  return k
end
-- 服务器请客户端预加载过 pos 附近（水平 r 格以内）那一片没有（RequestStreamAroundAsync：模拟器记在 R.streamLog；要 G.streaming 开着）
local function streamNear(pos, r)
  for _, x in ipairs(R.streamLog or {}) do
    if x.op == "around" and x.pl == me and math.sqrt((x.pos.X - pos.X) ^ 2 + (x.pos.Z - pos.Z) ^ 2) < r then return true end
  end
  return false
end
-- 坐进试驾的飞机以后：在不在训练场跑道东头、机头朝西、在地上
local function onRunway(e, st)
  local pa = e.root.CFrame.Position
  check(math.abs(pa.Z - A.z) < A.wid / 2 and math.abs(pa.X - A.x) < A.len / 2 and pa.X > A.x + A.len / 2 - 400,
    string.format("停在训练场跑道东头（离跑道中心 %.0f, %.0f 格）", pa.X - A.x, pa.Z - A.z))
  check(st.ground == true and st.cf.LookVector.X < -0.95, string.format("在地上、机头朝西（%.2f）", st.cf.LookVector.X))
end
-- 推满油门（有加力推到加力）、到抬头速度拉杆：离地在跑道上、接着爬；返回滑了多少格（离地的地方离起点多远）
--   mobile：像手机一样拉杆——摇杆往回拉（MoveVector.Z = +1；手机上键盘的 S 是收油门、不管俯仰），查地上往回拉摇杆抬得起机头
--   （Fly.lua 地上 pitchIn < −0.3 抬头：试驾审查 8 修的 pitchIn = −mv.Z，原来地上往回拉反倒压机头）；油门照旧按住 Shift
local function takeoff(e, mobile)
  local st = C.fly
  local d = st.d
  C.flyMouseAim(false)
  fixes()
  local mob0 = C.mobile
  if mobile then
    C.mobile = true
    R.moveVec = nil
  end
  local function pull(on)
    if mobile then R.moveVec = on and T.V3(0, 0, 1) or nil else T.key(Enum.KeyCode.S, on) end
  end
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
      pull(true)
    end
    if not st.ground then
      liftX, liftT = st.cf.Position.X, t
      break
    end
  end
  check(liftX ~= nil and liftX > runEnd, string.format("%s推满油门滑跑、拉杆：在跑道上离地（%s 秒、滑了 %s 格，跑道还剩 %s 格）", mobile and "手机：往回拉摇杆，" or "",
    liftT and string.format("%.1f", liftT) or "?", liftX and string.format("%.0f", p0.X - liftX) or "?", liftX and string.format("%.0f", liftX - runEnd) or "?"))
  local yL = st and st.cf.Position.Y or 0
  R.run(2.5)
  pull(false)
  R.run(5)
  st = C.fly
  local y1 = st and st.cf.Position.Y or 0
  check(st ~= nil and not st.crashed and y1 > yL + 40 * M, string.format("离地以后接着爬（7.5 秒爬了 %.0f 米）", (y1 - yL) / M))
  local nf = fixes()
  check(nf == 0, "服务器没往回拉（" .. nf .. " 次）")
  check(e.alive, "飞机没坏")
  T.key(Enum.KeyCode.LeftShift, false)
  if mobile then C.mobile = mob0 end
  return liftX and (p0.X - liftX)
end
-- 服务器估的滑跑（AirDefs.takeoffRun，试驾按它挑跑道还是空中出生）和真滑的对得上：差不到 5%——改了 Fly.lua 地上那段（滑跑、抬头、质量）
--   没跟着改 takeoffRun 的，这里抓得到（原来只打印、不比，估偏了跑道上还是空中出生就悄悄变了）
local function runMatches(est, run, who)
  check(est ~= nil and run ~= nil and math.abs(run - est) <= est * 0.05, string.format("%s：服务器估的滑跑 %s 格、真滑了 %s 格（差 %s，不到 5%%）", who,
    est and string.format("%.0f", est) or "?", run and string.format("%.0f", run) or "?", (est and run) and string.format("%.1f%%", math.abs(run - est) / est * 100) or "?"))
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
-- 11-28 起新账号只白送地面树的一级车（飞机、直升机拿金币买，TechTree.pickStarter 只给 ground）：照原来的规则把这一系的
--   起步飞机、直升机直接写进科技树存档、放进阵容（同 wtbr.lua），再照原样测试驾
do
  local t = G.treeOf(P)
  local L2 = {}
  for _, k in ipairs(G.treeLineup(P)) do table.insert(L2, k) end
  for _, br in ipairs({ "air", "heli" }) do
    local it = TT.pickStarter(TT.list[t.nat][br], br)
    if it and not t.own[it.key] then
      t.res[it.key], t.own[it.key] = true, true
      table.insert(L2, it.key)
    end
  end
  G.ACT.treeLineup(P, t.nat, L2)
  G.treePublish(P)
  R.run(1)
end
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
local n0 = #R.sent
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local e = P.vehicle
check(e ~= nil and e.air and e.testDrive and e.treeKey == airKey, "坐进了试驾的飞机（" .. tostring(e and e.def and e.def.id) .. "，原来坐进的是坦克）")
R.run(1)
if e and e.air and C.fly then
  local rj, lj = estRun(airKey)
  check(rj ~= nil and lj and rj <= LEFT * 0.95, string.format("服务器估的满油满弹滑跑 %s 格，不到跑道剩的 %d 格的九成五：照旧摆在跑道上", rj and string.format("%.0f", rj) or "?", LEFT))
  check(testMsg(n0) == "tree.testOnAir", "提示：在跑道上推油门起飞（" .. tostring(testMsg(n0)) .. "）")
  onRunway(e, C.fly)
  runMatches(rj, takeoff(e), "歼-6")
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
n0 = #R.sent
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local eh = P.vehicle
check(eh ~= nil and eh.air and eh.def.kind == "heli" and eh.treeKey == heliKey, "坐进了试驾的直升机（" .. tostring(eh and eh.def and eh.def.id) .. "）")
R.run(1)
if eh and eh.air and C.fly then
  local ph = eh.root.CFrame.Position
  local hp = RM.heliPad(0)
  check(math.abs(ph.X - hp.X) < 120 and math.abs(ph.Z - hp.Z) < 120 and C.fly.ground == true, string.format("停在训练场直升机坪上（偏 %.0f, %.0f）", ph.X - hp.X, ph.Z - hp.Z))
  -- 原来直升机和固定翼一个提示（tree.testOnAir「在训练场跑道上，推油门起飞」）
  check(testMsg(n0) == "tree.testOnPad", "提示：在直升机坪上拉总距起飞（" .. tostring(testMsg(n0)) .. "）")
  fixes()
  local y0 = C.fly.cf.Position.Y
  T.key(Enum.KeyCode.W, true)   -- 直升机 W 提总距（11-28 起同战雷；原来是 E）
  T.runUntil(function() return C.fly == nil or C.fly.cf.Position.Y > y0 + 120 end, 20)
  T.key(Enum.KeyCode.W, false)
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
  runMatches(estRun(key), takeoff(es, true), "苏-25（手机摇杆拉杆）")   -- 这一架像手机一样往回拉摇杆抬头（① 是键盘）
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
-- 11-28 起俄系白送的是 BMP-1（俄系地面树没有一级坦克；它的 73 毫米炮是自动装弹机，没有待发弹架可查）：
--   先把这一系第一辆坦克写进科技树存档、排在阵容最前面（同上面①）
do
  local t = G.treeOf(P)
  local VDx = R.require(RS:FindFirstChild("VehDefs"))
  local tank = nil
  for _, it in ipairs(TT.list[t.nat].ground) do
    local d = VDx.get(it.play)
    if d and d.cat == "tank" then tank = it break end
  end
  if tank and not t.own[tank.key] then
    t.res[tank.key], t.own[tank.key] = true, true
    local L2 = { tank.key }
    for _, k in ipairs(G.treeLineup(P)) do table.insert(L2, k) end
    G.ACT.treeLineup(P, t.nat, L2)
    G.treePublish(P)
    R.run(1)
  end
end
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

print("⑤ 满油满弹在训练场跑道上滑不起来的大飞机（轰-6K）：直接在空中出生——在靶区南边朝北进场、在飞")
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
-- 流式加载（真游戏开着）：看服务器请客户端先送哪一片（模拟器只记一笔：R.streamLog）；⑥ 完了关回去
G.streaming = true
R.streamLog = {}
n0 = #R.sent
if tb then T.press(tb) end
T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
local eb = P.vehicle
check(eb ~= nil and eb.air and eb.testDrive and eb.treeKey == hKey, "坐进了试驾的轰-6K（" .. tostring(eb and eb.def and eb.def.id) .. "）")
R.run(1)
local tgt = RM.airTarget()
-- 在靶区南边朝北对着靶区（试驾审查后续 1：原来在靶区中心正上方朝北出来——地面靶在正前方 0～1460 格，炸弹要提前 5000 多格松手，一出来就飞过了靶子）
local function approach(st, who)
  local p = st.cf.Position
  local south = p.Z - tgt.Z   -- 北是 −Z
  check(south > 2000 and math.abs(p.X - tgt.X) < 300 and st.cf.LookVector.Z < -0.95,
    string.format("%s在靶区南边 %.0f 格、朝北对着靶区（横着偏 %.0f 格，机头 %.2f）", who, south, p.X - tgt.X, st.cf.LookVector.Z))
end
if eb and eb.air and C.fly then
  local st = C.fly
  local p = st.cf.Position
  local agl = p.Y - G.Map.height(p.X, p.Z)
  check(eb.onGround == false and st.ground == false and agl > 600, string.format("空中出生：没摆在跑道上，离地 %.0f 格（服务器 onGround = %s）", agl, tostring(eb.onGround)))
  approach(st, "")
  -- 现在平飞投下去的炸弹落在哪（客户端 G.bombImpact：同平显上的落点、轰炸瞄准镜的十字）：还在靶区南边——还没到投弹点，平飞过去就能对准了投
  local imp = C.bombImpact and C.bombImpact(p, st.vel)
  local lead = imp and (imp.Z - tgt.Z) / math.max(st.spd, 1)
  check(lead ~= nil and lead > 4, string.format("现在投弹落在靶区中心南边 %s 格：还要飞 %s 秒才到投弹点（原来一出来就过了）",
    imp and string.format("%.0f", imp.Z - tgt.Z) or "?", lead and string.format("%.1f", lead) or "?"))
  check(st.spd > st.d.stall * 1.2, string.format("带着速度出来（%.0f 格 / 秒，失速 %.0f）", st.spd, st.d.stall))
  check(testMsg(n0) == "tree.testOnSky", "提示：满油满弹跑道上滑不起来、在空中出发（" .. tostring(testMsg(n0)) .. "）")
  check(streamNear(p, 2500) and not streamNear(RM.runwayStart(0), 3000), "先送过来的是空中出生那一片（试驾审查后续 2：原来是跑道东头，离这儿一万多格）")
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

print("⑥ 无人机（MQ-9）试驾：操作员站在跑道边上、钉在地上；剩的跑道不够长时在空中出生；摆不到跑道上的兜底提示（试驾审查后续 4、5）")
-- 遥控无人机的人（Air.lua seat：拿平板、HumanoidRootPart 钉住）站在起飞位旁边跑道南边的地上——原来跑道上出生的站在起飞位上
--   （前面几个起飞位的飞机滑跑从他身上穿过去），空中出生的挪回起飞位上
local function operator(e, who)
  local hrp = P.char and P.char:FindFirstChild("HumanoidRootPart")
  local hp = hrp and hrp.Position
  local agl = hp and (hp.Y - G.Map.height(hp.X, hp.Z)) or -1
  local off = hp and (hp.Z - A.z) or 0   -- 离跑道中线多远（往南为正）
  check(P.remote == e and hrp ~= nil and hrp.Anchored == true and agl > 1 and agl < 6 and off > A.wid / 2 + 20,
    string.format("%s：人拿着平板遥控（P.remote），站在跑道南边的地上（离跑道中线 %.0f 格、离地 %.1f 格）、钉住了（Anchored = %s）",
      who, off, agl, tostring(hrp and hrp.Anchored)))
end
local function ride(k)
  local n = #R.sent
  T.act("testDrive", k)
  T.runUntil(function() return P.alive and P.vehicle ~= nil and C.fly ~= nil end, 30)
  R.run(1)
  return P.vehicle, testMsg(n)
end
local mqKey = "us_mq9"
-- (a) 照常：MQ-9 改装全装估 3026 格，第 0 个起飞位剩 3440 格，摆在跑道上
local em, mk = ride(mqKey)
check(em ~= nil and em.air and em.def.drone and em.testDrive and em.treeKey == mqKey, "坐进了试驾的 MQ-9（" .. tostring(em and em.def and em.def.id) .. "）")
if em and em.air then
  local pa = em.root.CFrame.Position
  check(em.onGround == true and math.abs(pa.Z - A.z) < A.wid / 2 and mk == "tree.testOnAir",
    string.format("停在训练场跑道上（离跑道中线 %.0f 格）、提示在跑道上起飞（%s）", pa.Z - A.z, tostring(mk)))
  operator(em, "跑道上")
end
backToHangar()
-- (b) 跑道剩得不够长（同时七个人以上在试驾时第 6 个起飞位起就是这样）：临时把剩的跑道改成 1000 格（Tech.lua 的 RangeMap 就是 G.Map.Range）
local rl0 = RM.runwayLeft
RM.runwayLeft = function() return 1000 end
R.streamLog = {}
em, mk = ride(mqKey)
RM.runwayLeft = rl0
check(em ~= nil and em.air and em.def.drone and em.treeKey == mqKey, "剩的跑道不够长：坐进了试驾的 MQ-9")
if em and em.air and C.fly then
  local p = em.root.CFrame.Position
  local agl = p.Y - G.Map.height(p.X, p.Z)
  check(em.onGround == false and C.fly.ground == false and agl > 600 and mk == "tree.testOnSky",
    string.format("空中出生：离地 %.0f 格（服务器 onGround = %s），提示跑道上滑不起来（%s）", agl, tostring(em.onGround), tostring(mk)))
  approach(C.fly, "无人机：")
  operator(em, "空中出生")
  check(streamNear(p, 2500), "先送过来的是无人机出生那一片（画面是无人机那边）")
end
backToHangar()
G.streaming = false
-- (c) 摆不到跑道上（G.spawnAircraft 出错）的兜底：照样在空中出来，提示不说「满油满弹滑不起来」（试驾审查后续 5：原来兜底也设 sky，提示说错原因）
local sa0 = G.spawnAircraft
G.spawnAircraft = function() error("测试：摆不到跑道上") end
local ej
ej, mk = ride("cn_j6")
G.spawnAircraft = sa0
if ej and ej.air and C.fly then
  local p = ej.root.CFrame.Position
  check(ej.onGround == false and p.Y - G.Map.height(p.X, p.Z) > 600 and mk == "tree.testInAir",
    string.format("跑道上摆不下的歼-6：在空中出来，提示「没摆下、在空中出发」（%s，原来是 tree.testOnSky）", tostring(mk)))
  approach(C.fly, "兜底：")
else
  check(false, "跑道上摆不下的歼-6：坐进去了（" .. tostring(ej and ej.def and ej.def.id) .. "）")
end
backToHangar()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
