-- 出战场区域读秒判毁、坠机自动回机库（模拟器）：python3 tools/mock/run.py tools/mock/bounds.lua
--   用户 11-27 晚：「我坠机能不能自动返回主页 然后 超出战场区域开始读秒吧 读完了自动炸」（同战雷）
--   ① 飞机出了作战区：服务器开始读秒（飞机的 Oob 属性 10 → 0，平显正中「返回作战区域 N」），不再自动掉头；飞回来就停
--   ② 读完判毁；判毁以后几秒内回到机库（试驾的阵亡画面 2.4 秒）
--   ③ 读秒还没完就飞出作战区外 12000 格：直接判毁
--   ④ 客户端判了坠毁、服务器没判（那一包丢了）：3 秒后自己回机库
--   ⑤ 地面车开出战场区域（训练场地形边上往里 1200 格）：正中读秒，读完判毁
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

T.mapName = "city"
T.wtMode = true
T.rangeTerrain = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local RS = R.services.ReplicatedStorage
local Zones = R.require(RS:FindFirstChild("Zones"))
local RM = R.require(RS:FindFirstChild("MapRange"))
local TT = R.require(RS:FindFirstChild("TechTree"))
local Map = G.Map
local me = T.join("P1", 9811, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 600, 1 / 10)
R.run(1)

local function msgs(since, key)
  local n, last = 0, nil
  for i = since + 1, #R.sent do
    local s = R.sent[i]
    if s.name == "Msg" and s.args[2] == key then n, last = n + 1, s.args[3] end
  end
  return n, last
end
local function backToHangar()
  if P.alive then T.remoteAs(me, "Drive", { op = "exit", hangar = true }) end
  T.runUntil(function() return not P.alive end, 15)
  T.runUntil(function() return T.findNamed("HangarTest") ~= nil end, 15)
  R.run(1)
end
local function hangarShown()
  local b = T.findNamed("HangarTest")
  if not b then return false end
  local o = b
  while o and o.Parent do
    if o:IsA("GuiObject") and not o.Visible then return false end
    if o:IsA("ScreenGui") then return o.Enabled ~= false end
    o = o.Parent
  end
  return true
end
local function flyTest()
  T.act("testDrive", "cn_j6")
  T.runUntil(function() return P.alive and P.vehicle ~= nil and P.vehicle.air and C.fly ~= nil end, 30)
  R.run(0.5)
  return P.vehicle, C.fly
end
-- 摆到训练场里的某一点（服务器、客户端一起挪；顺着 look 以 600 格 / 秒飞）
local function place(ea, st, rx, rz, look)
  local p = V3(RM.X + rx, RM.PLAIN + 1500, RM.Z + rz)
  st.ground = false
  st.cf = R.CFrame.lookAt(p, p + look)
  st.vdir, st.spd, st.vel = look, 600, look * 600
  st.gearWant, st.gear = 0, 0
  G.moveEnt(ea, st.cf)
  ea.vel = st.vel
  ea.syncT, ea.syncSlack = os.clock(), 160
end
local function warnText()
  for _, x in ipairs(me.PlayerGui:GetDescendants()) do
    if x:IsA("TextLabel") and x.Visible and type(x.Text) == "string" and x.Text:find("返回作战区域") then return x.Text end
  end
end
local PLAY = Zones.RANGE.PLAY

print("① 飞机出了作战区：读秒、不自动掉头；飞回来就停")
local ea, st = flyTest()
check(ea ~= nil and st ~= nil, "坐进了试驾的歼-6")
if ea and st then
  place(ea, st, 0, -3000, V3(0, 0, -1))
  R.run(0.6)
  check(ea.model:GetAttribute("Oob") == nil and st.oob == false, "在训练场上空：不读秒")
  place(ea, st, PLAY + 600, 0, V3(1, 0, 0))
  st.aimYaw = math.atan2(-1, 0)   -- 鼠标想去的方向：接着往外（原来出界后自动驾驶把它改成朝训练场中心）
  R.run(0.6)
  local left = ea.model:GetAttribute("Oob")
  check(st.oob == true and left ~= nil and left >= 9 and left <= 10, "出界：服务器读秒（剩 " .. tostring(left) .. " 秒）")
  local yaw = st.aimYaw or 0
  check(math.abs(yaw - math.atan2(-1, 0)) < 0.01, string.format("不再自动掉头（鼠标想去的方向没被改，%.2f）", yaw))
  local w = warnText()
  check(w ~= nil and w:find("%d") ~= nil, "平显正中写「返回作战区域」和秒数（" .. tostring(w) .. "）")
  place(ea, st, 0, -3000, V3(0, 0, -1))
  R.run(0.8)
  check(ea.model:GetAttribute("Oob") == nil and ea.alive, "飞回来：读秒停了、飞机好好的")

  print("② 读完判毁、回机库")
  place(ea, st, PLAY + 600, 0, V3(1, 0, 0))
  local t0 = os.clock()
  T.runUntil(function() return not ea.alive end, 14, 1 / 10)
  local dt = os.clock() - t0
  check(not ea.alive and dt > 9 and dt < 11.5, string.format("读完判毁（%.1f 秒）", dt))
  local t1 = os.clock()
  T.runUntil(function() return not P.alive and hangarShown() end, 10, 1 / 10)
  check(not P.alive and hangarShown(), string.format("判毁后自动回到机库（%.1f 秒）", os.clock() - t1))
  R.run(1)
end

print("③ 读秒还没完就飞出 12000 格：直接判毁")
ea, st = flyTest()
if ea and st then
  place(ea, st, PLAY + 12400, 0, V3(1, 0, 0))
  T.runUntil(function() return not ea.alive end, 3, 1 / 10)
  check(not ea.alive, "飞出作战区外 12000 格：马上判毁")
  T.runUntil(function() return not P.alive and hangarShown() end, 10, 1 / 10)
  R.run(1)
else
  check(false, "第二次试驾坐进飞机")
end

print("④ 客户端判了坠毁、服务器没判：3 秒后自己回机库")
ea, st = flyTest()
if ea and st then
  place(ea, st, 0, -3000, V3(0, 0, -1))
  R.run(0.5)
  st.crashed = true   -- 只在客户端（坠机那一包没到服务器）
  local t0 = os.clock()
  T.runUntil(function() return not P.alive end, 8, 1 / 10)
  local dt = os.clock() - t0
  check(not P.alive and dt >= 2.9 and dt < 5, string.format("摔了 3 秒后自己回机库（%.1f 秒）", dt))
  T.runUntil(function() return hangarShown() end, 10, 1 / 10)
  check(hangarShown(), "机库出来了")
  R.run(1)
else
  check(false, "第三次试驾坐进飞机")
end

print("⑤ 地面车开出战场区域：正中读秒，读完判毁")
local gKey
for _, k in ipairs(G.treeLineup(P)) do
  local it = TT.byKey[k]
  if it and it.branch == "ground" and not gKey then gKey = k end
end
check(gKey ~= nil, "阵容里有地面车（" .. tostring(gKey) .. "）")
if gKey then
  T.act("testDrive", gKey)
  T.runUntil(function() return P.alive and P.vehicle ~= nil and not P.vehicle.air and C.drive ~= nil end, 30)
  R.run(1)
  local eg, sd = P.vehicle, C.drive
  check(eg ~= nil and sd ~= nil, "坐进了试驾的地面车（" .. tostring(eg and eg.def and eg.def.id) .. "）")
  if eg and sd then
    local lim = Zones.RANGE.R
    local x, z = RM.X + lim - 900, RM.Z
    local cf = CF(x, Map.height(x, z) + eg.def.H / 2 + 0.5, z)
    sd.root = cf
    G.moveEnt(eg, cf)
    eg.syncBudget = 1e6
    local n0 = #R.sent
    R.run(1.5)
    local n, last = msgs(n0, "ui.oobT")
    check(n >= 1 and last ~= nil and last <= 10, "出了战场区域：正中读秒（" .. tostring(last) .. "）")
    T.runUntil(function() return not eg.alive end, 14, 1 / 10)
    check(not eg.alive, "读完判毁")
  end
end

T.summary()
