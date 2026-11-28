-- 空空弹的导引头、锁定圈照战雷（模拟器）：python3 tools/mock/run.py tools/mock/seeker.lua
--   用户 11-28 夜「然后目前飞机驾驶的导弹ui不够还原战雷 我们的锁定圈貌似比战雷小 你去对照一下以及各种音效以及锁定机制」
--   「我记得有雷达锁定和导弹火控锁定两种吧 有时候那个大环会变红」（对照战雷官方 wiki「Infrared Missiles in War Thunder」和截图）：
--   ① 红外弹（F-16C 的 AIM-9X）：小圈是导引头的截获圈，约占屏幕高的 8～9%（原来固定 26 像素）；目标在大圈里、小圈外——不截获（原来大圈里自动挑）
--   ② 目标进了小圈：截获（嗡嗡变响）、锁定时间到了锁上——大圈、小圈一起变红，小圈套在目标上，底下写「导引头：已锁定」
--   ③ 能离轴的导引头锁上以后自己跟着目标转：目标偏到 25°（大圈里）照旧锁着，小圈跟着目标
--   ④ 目标出了大圈：不能发射（圈变白），过一会儿丢锁
--   ⑤ 雷达弹（AIM-120）：雷达锁上（Alt+F）小圈马上跳到目标上（白的）——导弹还没锁上；锁定时间到了两个圈一起变红（「大环变红」）
--   ⑥ 旧式不能离轴的（歼-6 的霹雳-2）：只有一个圈；锁上以后目标出了这个圈就丢
--   ⑦ 不锁发射（「然后有的导弹不需要雷达锁定就能发射吧」）：主动雷达弹「疯狗」打出去，飞一段自己开导引头咬上前方的敌机；
--      红外弹打出去自己盯着前方找；半主动雷达弹（要发射机的雷达一直照着）没锁打不出去、提示要雷达锁定
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6531, true)
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
T.actAs(me, "deploy", "rifle", "base")
R.run(2)
T.runUntil(function() return G.round.phase == "battle" end, 120)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local gy = math.max(G.Map.ground(0, 0), 0)
local p0 = V3(0, gy + 1500, 0)

-- 换一架（同 radar.lua 的 fly2：空格下飞机，新的一架摆在旁边，人挪过去坐进去）
local holdP = p0
local nBoard = 0
local function board(id)
  if C.fly and P.vehicle then
    T.tap(R.Enum.KeyCode.Space)
    R.run(1)
  end
  if not P.alive then T.actAs(me, "deploy", "rifle", "base") R.run(2) end
  holdP = p0 + V3(nBoard * 300, 0, 0)
  nBoard = nBoard + 1
  local jet = G.spawnAircraft("atk", id, CF(holdP.X, holdP.Y, holdP.Z), nil, P)
  P.char:PivotTo(CF(holdP.X + 4, holdP.Y, holdP.Z))
  R.run(0.2)
  if jet then T.act("enterVeh", jet.id) end
  R.run(0.4)
  return C.fly, jet
end
-- 机头朝 −Z 钉在原地（测锁定，不管飞）
local hold = R.Heartbeat:Connect(function()
  if C.fly then
    C.fly.cf = CFr.lookAt(holdP, holdP + V3(0, 0, -1))
    C.fly.vdir, C.fly.spd, C.fly.vel = V3(0, 0, -1), 0, V3()
    C.fly.ground, C.fly.gear, C.fly.gearWant = false, 0, 0
  end
end)
-- 敌机：放在机头前 dist 格、偏 az 度（往右为正），迎头飞（不置零）；红外弹锁得到的距离近（AIM-9X 1900 格、霹雳-2 1100 格）
local foe = G.newEnt({ kind = "air", team = "def", cat = "air", hp = 900, size = V3(16, 6, 24), cf = CF(p0.X, p0.Y, p0.Z - 3000), air = true })
foe.model:SetAttribute("Model", "su27")
local foeP = p0 + V3(0, 0, -3000)
local foeMove = false   -- 雷达看多普勒：要真的在动（钉在原地只给速度，雷达当它置零看不见）；测红外的时候钉住
local conn = R.Heartbeat:Connect(function(dt)
  if foe.alive then
    local v = (holdP - foeP).Unit * 150
    if foeMove then foeP = foeP + v * (dt or 1 / 60) end
    G.moveEnt(foe, CFr.lookAt(foeP, foeP + v))
    foe.vel = v
  end
end)
local function putFoe(az, dist)
  local a = math.rad(az)
  foeP = holdP + V3(math.sin(a), 0, -math.cos(a)) * (dist or 3000)
  R.run(0.05)
end
local function ui(name)   -- 平显上的圈、字（T.findNamed 只找按钮）
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == name then return d end end
end
local function strokeOf(f)
  for _, c in ipairs(f and f:GetChildren() or {}) do if c.ClassName == "UIStroke" then return c end end
end
local RED = nil
local function isRed(col) return col and col.R > 0.8 and col.G < 0.5 and col.B < 0.5 end
local function isWhite(col) return col and col.R > 0.85 and col.G > 0.85 and col.B > 0.85 end
local function scr(p)
  local cam = R.workspace.CurrentCamera
  local v = cam:WorldToViewportPoint(p)
  return v.X, v.Y
end
local function near2(f, p, tol)
  local x, y = scr(p)
  local fx, fy = f.Position.X.Offset, f.Position.Y.Offset
  return math.abs(fx - x) < tol and math.abs(fy - y) < tol, string.format("圈 (%.0f, %.0f) 目标 (%.0f, %.0f)", fx, fy, x, y)
end
local function slotOf(st, pred)
  for i, w in ipairs(st.wl or {}) do
    local ww = AD.W[w]
    if ww and pred(ww) then return i end
  end
end

print("① 红外弹：小圈是截获圈，大圈里、小圈外的不截获")
local st = board("f16")
check(st ~= nil and st.pilot, "坐进 F-16C")
if not st then T.summary() return end
local sI = slotOf(st, function(w) return w.kind == "aam" and w.seeker ~= "radar" end)
check(sI ~= nil, "挂着红外弹（" .. tostring(sI and st.wl[sI]) .. "）")
st.wi = sI
local wI = AD.W[st.wl[sI]]
putFoe(15, 1500)
R.run(2)
local head, cone = ui("SeekerHead"), ui("SeekerCone")
check(head and head.Visible and cone and cone.Visible, "大圈、小圈都在")
local vh = R.workspace.CurrentCamera.ViewportSize.Y
local dHead = head and head.Size.X.Offset or 0
print(string.format("   小圈直径 %.0f 像素（屏幕高 %.0f 的 %.1f%%）、大圈直径 %.0f 像素；%s 的离轴角 %d°", dHead, vh, 100 * dHead / vh, cone and cone.Size.X.Offset or 0, st.wl[sI], wI.cone))
check(dHead / vh > 0.075 and dHead / vh < 0.12, "小圈约占屏幕高的 8～9%（战雷截图；原来 26 像素）")
check(st.lock == nil, "目标偏 15°（大圈里、小圈外）：导引头不截获（原来大圈里自动挑）")
local sel = ui("WtSeeker")
check(sel and sel.Text:find(C.T("wt.seekOn"), 1, true) ~= nil, "底下写「导引头：开启」（" .. tostring(sel and sel.Text) .. "）")
check(isWhite(strokeOf(head) and strokeOf(head).Color) and isWhite(strokeOf(cone) and strokeOf(cone).Color), "没锁：两个圈都是白的")

print("② 目标进了小圈：截获、锁上，两个圈变红")
putFoe(1.5, 1500)
R.run(0.3)
check(st.lock ~= nil and st.lock.em == foe.model, "截获（目标在小圈里）")
R.run((wI.lockTime or 1) + 0.3)
check(st.lock ~= nil and st.lockT >= (wI.lockTime or 1), "锁上了（" .. string.format("%.1f / %.1f 秒", st.lockT or 0, wI.lockTime or 1) .. "）")
check(isRed(strokeOf(head).Color) and isRed(strokeOf(cone).Color), "大圈、小圈一起变红")
local okP, why = near2(head, foeP, 25)
check(okP, "小圈套在目标上（" .. why .. "）")
check(sel.Text:find(C.T("wt.seekLock"), 1, true) ~= nil, "底下写「导引头：已锁定」")

print("③ 能离轴：锁上以后目标偏到 25°（大圈里）照旧锁着、小圈跟着")
for a = 3, 25, 2 do putFoe(a, 1500) end
R.run(0.4)
check(st.lock ~= nil and not st.lock.out and st.lockT >= (wI.lockTime or 1), "目标偏 25°：照旧锁着")
okP, why = near2(head, foeP, 30)
check(okP and isRed(strokeOf(head).Color), "小圈跟着目标、红的（" .. why .. "）")

print("④ 出了大圈：圈变白（不能发射），过一会儿丢锁")
putFoe(wI.cone + 12, 1500)
R.run(0.4)
check(st.lock ~= nil and st.lock.out == true, "出了离轴角：锁还留着、标成出界")
check(isWhite(strokeOf(cone).Color), "大圈变白（不能发射）")
R.run(4.5)
check(st.lock == nil or st.lock.em ~= foe.model, "偏出去 4 秒：丢锁")

print("⑤ 雷达弹：雷达先锁、导弹再锁（锁上了大圈变红）")
local sR = slotOf(st, function(w) return w.kind == "aam" and w.seeker == "radar" end)
check(sR ~= nil, "挂着雷达弹（" .. tostring(sR and st.wl[sR]) .. "）")
if sR then
  st.wi = sR
  local wR = AD.W[st.wl[sR]]
  foeMove = true
  putFoe(8, 4000)
  R.run(4.5)   -- 雷达扫一帧（±60° × 2 行约 4 秒，迎头 3000 格）
  T.runUntil(function() return C.flyRadarLockOn and C.flyRadarLockOn(foe.model) end, 8, 0.25)
  R.run(0.2)
  check(st.rdLock ~= nil and st.rdLock.em == foe.model, "雷达锁上（单目标跟踪）")
  local x, y = scr(foeP)
  check(st.lock ~= nil and (st.lockT or 0) < (wR.lockTime or 2), "导弹还没锁上")
  okP, why = near2(head, foeP, 30)
  check(okP and isWhite(strokeOf(head).Color), "小圈马上跳到雷达锁着的目标上、白的（" .. why .. "）")
  check(isWhite(strokeOf(cone).Color), "大圈还是白的")
  R.run((wR.lockTime or 2) + 0.4)
  check(st.lockT >= (wR.lockTime or 2), "导弹锁上了")
  check(isRed(strokeOf(cone).Color) and isRed(strokeOf(head).Color), "大环、小圈一起变红")
  foeMove = false
end

print("⑥ 旧式不能离轴的（歼-6 的霹雳-2）：只有一个圈，出了圈就丢")
local s6 = board("j6")
local sC = s6 and slotOf(s6, function(w) return w.caged == true end)
if not sC then
  print("   歼-6 这一架没挂霹雳-2：跳过")
else
  s6.wi = sC
  local wC = AD.W[s6.wl[sC]]
  putFoe(0.5, 800)
  R.run((wC.lockTime or 1.5) + 0.5)
  check(s6.lock ~= nil and s6.lockT >= (wC.lockTime or 1.5), "正前方：锁上")
  check(not ui("SeekerCone").Visible, "只有一个圈（没有大圈）")
  for a = 1, 9, 2 do putFoe(a, 800) end
  R.run(0.5)
  check(s6.lock == nil, "目标偏到 9°（出了小圈）：丢锁（导引头不跟着转）")
end
print("⑦ 不锁发射（用户「有的导弹不需要雷达锁定就能发射吧」）：主动雷达弹「疯狗」、红外弹打出去自己找；半主动没锁不让打")
local function newShot(n0, wid)
  for i = n0 + 1, #G.shots do
    local sh = G.shots[i]
    if sh and sh.wid == wid then return sh end
  end
end
local s7 = board("f16")
local sA = s7 and slotOf(s7, function(w) return w.kind == "aam" and w.seeker == "radar" and w.act ~= nil end)
check(sA ~= nil, "F-16C 挂着主动雷达弹（" .. tostring(sA and s7.wl[sA]) .. "）")
if sA then
  s7.wi = sA
  foeMove = true
  putFoe(4, 2600)
  R.run(0.5)
  check(s7.rdLock == nil and (s7.lock == nil or (s7.lockT or 0) < 0.1), "雷达没锁")
  local n0 = #G.shots
  local Fk = R.Enum.KeyCode.F
  T.key(Fk, true) R.run(0.1) T.key(Fk, false)
  R.run(0.1)
  local sh = newShot(n0, s7.wl[sA])
  check(sh ~= nil and sh.search == "arh" and sh.tgt == nil, "没锁也打出去了（「疯狗」：先直飞，没目标）")
  check(#T.texts(C.T("air.madDog")) > 0, "提示「未锁定发射：导弹自己开导引头找」")
  local hp0 = foe.hp
  T.runUntil(function() return sh and (sh.tgt == foe or sh.life == 0 or not foe.alive) end, 4, 0.05)
  check(sh and (sh.tgt == foe or not foe.alive or (foe.hp or 0) < hp0), "飞了一段自己开导引头、咬上前方的敌机")
end
-- 红外弹：目标在小圈外（客户端没锁上），打出去以后弹头前方 12° 里找
local sI7 = s7 and slotOf(s7, function(w) return w.kind == "aam" and w.seeker ~= "radar" end)
foeMove = false
if not foe.alive then   -- 上面那发打下来了：再放一架
  foe = G.newEnt({ kind = "air", team = "def", cat = "air", hp = 900, size = V3(16, 6, 24), cf = CF(p0.X, p0.Y, p0.Z - 1500), air = true })
  foe.model:SetAttribute("Model", "su27")
  R.run(0.2)
end
if sI7 then
  s7.wi = sI7
  putFoe(6, 1500)
  R.run(0.5)
  check(s7.lock == nil, "目标偏 6°（小圈外）：没锁")
  s7.nextFire = 0
  local n0 = #G.shots
  T.key(R.Enum.KeyCode.F, true) R.run(0.1) T.key(R.Enum.KeyCode.F, false)
  R.run(0.1)
  local sh = newShot(n0, s7.wl[sI7])
  check(sh ~= nil and sh.search == "ir", "红外弹没锁也打出去了")
  T.runUntil(function() return sh and (sh.tgt == foe or not foe.alive) end, 2, 0.05)
  check(sh and (sh.tgt == foe or not foe.alive), "打出去以后自己盯上前方的敌机")
end
-- 半主动（苏-27 的 R-27R / ER）：没有雷达锁不让打
local s8 = board("su27")
local sS = s8 and slotOf(s8, function(w) return w.kind == "aam" and w.seeker == "radar" and w.act == nil end)
if not sS then
  print("   这一架没挂半主动雷达弹：跳过")
else
  s8.wi = sS
  R.run(0.3)
  local n0 = #G.shots
  T.key(R.Enum.KeyCode.F, true) R.run(0.1) T.key(R.Enum.KeyCode.F, false)
  R.run(0.2)
  check(newShot(n0, s8.wl[sS]) == nil, "半主动雷达弹（" .. s8.wl[sS] .. "）没锁：打不出去")
  check(#T.texts(C.T("air.needRadar")) > 0, "提示「需要雷达锁定」")
end
hold:Disconnect()
conn:Disconnect()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
