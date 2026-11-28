-- 训练场一直是白天（模拟器）：python3 tools/mock/run.py tools/mock/rangeday.lua part=1|2
--   用户 11-28 夜「然后训练场改成持续百天吧」（持续白天）：
--   ① part=1 起始服务器（Studio 一个服务器全包、战场是雪山图）：这一局是夜里 23 点——机库里照这一局的钟点；点试驾：服务器先给玩家记
--      TestDriveAt（人先生出来、车后到），出生不自动开夜视；坐进车以后自己的画面是上午 11 点（服务器的钟点照旧 23 点），光照直接到位
--      不慢慢亮；长按 H 回机库：马上换回夜里，TestDriveAt 去掉
--   ② part=2 训练场服务器（PlaceRole = range）：服务器、客户端的钟点都钉在 11 点（拨钟、每局开局拨回早上都不动），机库里也是白天
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check
local PART = tonumber(TEST_ARGS:match("part=(%d)") or "1") or 1
local KEY = "de_leo2a6"
local L = R.services.Lighting
local RS = R.services.ReplicatedStorage
local function near(a, b, e) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (e or 0.03) end

if PART == 1 then
  T.mapName = "snow"
  T.wtMode = true
  T.matchMode = true
  local G = T.boot()
  G.fortsHold = true
  G.Config.Match.wait = 3
  T.runUntil(function() return G.worldReady end, 1200)
  local DC = R.require(RS:FindFirstChild("DayClock"))
  local LL = R.require(RS:FindFirstChild("LightLooks"))
  local RC = DC.RANGE_CLOCK
  check(near(RC, 11, 1e-6), "训练场的钟点 rangeClock = 11 点（" .. tostring(RC) .. "）")
  check(not DC.rangePlace(), "这是起始服务器（不是训练场服务器）")
  -- 这一局是夜里
  R.workspace:SetAttribute("DayFix", 23)
  local me = T.join("P1", 9641, true)
  T.runUntil(function() return G.round ~= nil and G.P[me] ~= nil and G.P[me].data ~= nil end, 30)
  local P = G.P[me]
  T.leaveMenu()
  R.run(1.5)
  local C = T.C
  print("① 起始服务器：这一局夜里 23 点")
  check(near(L.ClockTime, 23), "机库里照这一局的钟点（" .. tostring(L.ClockTime) .. "）")
  check(C.isNight and C.isNight() == true, "这一局是夜里")
  -- 点试驾：服务器先记 TestDriveAt（人先生出来、车后到），客户端这一下就按白天算（夜视不自动开）
  T.act("testDrive", KEY)
  local sawAt = false
  T.runUntil(function()
    if type(me:GetAttribute("TestDriveAt")) == "number" then sawAt = true end
    return P.vehicle ~= nil and P.vehicle.testDrive
  end, 30, 0.05)
  check(sawAt, "出车前服务器给玩家记了 TestDriveAt")
  local e = P.vehicle
  check(e ~= nil and e.testDrive, "坐进试驾的车")
  T.runUntil(function() return C.inTestDrive and C.inTestDrive() end, 10, 0.05)
  check(C.inTestDrive and C.inTestDrive(), "客户端认出在试驾")
  -- 两次更新（0.1 秒一次）以内：钟点 11 点、光照直接是白天那套（不按 0.8 秒慢慢亮）
  R.run(0.25)
  local key = LL.keyFor(G.Map, R.workspace.CurrentCamera.CFrame.Position)
  local vd = LL.at(key, LL.weights(RC, DC))
  print(string.format("   试驾：钟点 %.2f、亮度 %.2f（白天那套 %.2f）、曝光 %.2f（%.2f）；服务器的钟点 %.1f", L.ClockTime, L.Brightness, vd.bright, L.ExposureCompensation, vd.exp, DC.clock()))
  check(near(L.ClockTime, RC), "自己的画面是上午 11 点")
  check(near(L.Brightness, vd.bright, 0.02), "光照直接到位（亮度是白天那套，不在画面上慢慢亮起来）")
  check(C.isNight() == false and C.dayK() > 0.95, "试驾时算白天（dayK " .. string.format("%.2f", C.dayK()) .. "）")
  check(near(DC.clock(), 23), "服务器的钟点照旧夜里 23 点（只换自己的画面）")
  check(C.nvLight ~= true, "出生没有自动打开夜视仪")
  -- 开一会儿还是白天
  R.run(5)
  check(near(L.ClockTime, RC) and C.isNight() == false, "开了 5 秒还是白天（" .. tostring(L.ClockTime) .. "）")
  check(C.nvLight ~= true, "一直没开夜视仪")
  print("   长按 H 回机库")
  T.remoteAs(me, "Drive", { op = "exit", hangar = true })
  T.runUntil(function() return P.vehicle == nil end, 10)
  T.runUntil(function()
    local cam = R.workspace.CurrentCamera
    return cam and G.Map.Zones.of(cam.CFrame.Position.X, cam.CFrame.Position.Z) == "lobby"
  end, 10, 0.05)
  R.run(0.3)
  check(me:GetAttribute("TestDriveAt") == nil, "TestDriveAt 去掉了")
  check(near(L.ClockTime, 23), "回到机库马上换回这一局的钟点（" .. tostring(L.ClockTime) .. "）")
  check(C.isNight() == true, "又是夜里")
else
  print("② 训练场服务器：钟点钉在白天")
  T.mapName = "-"
  T.placeRole = "range"
  T.wtMode = true
  T.matchMode = true
  local G = T.boot()
  T.runUntil(function() return G.placesReady end, 15)
  check(G.placeRole == "range", "这个服务器是训练场（PlaceRole = range）")
  T.runUntil(function() return G.worldReady end, 1200)
  local DC = R.require(RS:FindFirstChild("DayClock"))
  local RC = DC.RANGE_CLOCK
  check(DC.rangePlace(), "DayClock 认出是训练场服务器")
  check(near(DC.clock(), RC), "服务器的钟点 11 点（" .. tostring(DC.clock()) .. "）")
  -- 拨到夜里也不动；每局开局拨回早上也不动
  R.workspace:SetAttribute("DayFix", 23)
  check(near(DC.clock(), RC), "拨到夜里 23 点也照旧 11 点")
  R.workspace:SetAttribute("DayFix", nil)
  R.workspace:SetAttribute("DayT0", DC.t0For(21, R.workspace:GetServerTimeNow()))
  check(near(DC.clock(), RC), "这一圈按 21 点起算也照旧 11 点")
  local me = T.join("P1", 9642, true)
  T.runUntil(function() return G.round ~= nil and G.P[me] ~= nil and G.P[me].data ~= nil end, 30)
  T.leaveMenu()
  R.run(1.5)
  local C = T.C
  check(near(L.ClockTime, RC), "客户端（机库里）也是 11 点（" .. tostring(L.ClockTime) .. "）")
  check(C.isNight and C.isNight() == false, "算白天")
  local P = G.P[me]
  T.act("testDrive", KEY)
  T.runUntil(function() return P.vehicle ~= nil and P.vehicle.testDrive end, 60)
  R.run(1)
  check(P.vehicle ~= nil and near(L.ClockTime, RC) and C.isNight() == false, "试驾时也是 11 点")
  if G.roundStart then
    pcall(G.roundStart)
    R.run(0.5)
    check(near(DC.clock(), RC) and near(L.ClockTime, RC), "新的一局开局（拨回早上那一下）也照旧 11 点")
  end
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
