-- 飞机被打下来的阵亡镜头（模拟器）：python3 tools/mock/run.py tools/mock/deathcam.lua
--   用户 11-27（给了战雷截图）：「飞机被干掉后不要立马爆炸 先跟随视角但是雷达什么图全部消失像这样 然后 5秒后 再自动切换到敌视角」
--   ① 试驾里在天上被打下来：飞行员马上判死（原来不在开战阶段 hurtChar 不打人，人卡在「活着、没车」回不了机库）；
--      服务器不当场炸（不发 boom），客户端的残骸着火往下掉；镜头跟着残骸；飞行界面、雷达屏都收了，正下方一行「损失的载具」；3 秒后回机库
--   ② 对局里被打下来（客户端当它不是试驾）：先跟残骸 5 秒，再转去看打你的那架（这里拿训练场的靶机当凶手），那一行换成凶手；再 4 秒回机库
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
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
local RM = R.require(R.services.ReplicatedStorage:FindFirstChild("MapRange"))
local me = T.join("P1", 9831, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
local C = T.C
T.leaveMenu()
T.runUntil(function() return G.rangeReady == true and T.findNamed("HangarGo") ~= nil end, 600, 1 / 10)
R.run(1)
local cam = R.services.Workspace.CurrentCamera

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
-- 屏上看得见的字（往上一路都 Visible、所在的 ScreenGui 开着）
local function shownText(guiName)
  local g = me.PlayerGui:FindFirstChild(guiName)
  if not g or not g.Enabled then return {} end
  local out = {}
  for _, x in ipairs(g:GetDescendants()) do
    if x:IsA("TextLabel") and x.Text ~= "" and x.TextTransparency < 0.9 then
      local ok, o = true, x
      while o and o ~= g do
        if o:IsA("GuiObject") and not o.Visible then ok = false break end
        o = o.Parent
      end
      if ok then table.insert(out, x) end
    end
  end
  return out
end
local function deathLine()
  for _, l in ipairs(shownText("DeathFx")) do
    if l.Name == "Title" then return l.Text end
  end
  return nil
end
local function boomsSince(n0, p, r)
  local n = 0
  for i = n0 + 1, #R.sent do
    local s = R.sent[i]
    if s.name == "Fx" and type(s.args[1]) == "table" then   -- 一包是一串特效
      for _, f in ipairs(s.args[1]) do
        if type(f) == "table" and f.k == "boom" and R.typeof(f.p) == "Vector3" and (f.p - p).Magnitude < r then n = n + 1 end
      end
    end
  end
  return n
end
-- 摆到训练场上空 1200 格、顺着 −Z 以 500 格 / 秒平飞
local function flyHigh()
  T.act("testDrive", "cn_j6")
  T.runUntil(function() return P.alive and P.vehicle ~= nil and P.vehicle.air and C.fly ~= nil end, 30)
  R.run(1)
  local e, st = P.vehicle, C.fly
  if not (e and st) then return nil end
  local p = V3(RM.X, RM.PLAIN + 1200, RM.Z - 2000)
  st.ground = false
  st.cf = R.CFrame.lookAt(p, p + V3(0, 0, -1))
  st.vdir, st.spd, st.vel = V3(0, 0, -1), 500, V3(0, 0, -500)
  st.gearWant, st.gear = 0, 0
  G.moveEnt(e, st.cf)
  e.vel = st.vel
  e.syncT, e.syncSlack = os.clock(), 160
  R.run(0.5)
  return e, st
end

print("① 试驾里在天上被打下来：不当场炸、镜头跟残骸、界面全收、3 秒回机库")
local e = flyHigh()
check(e ~= nil, "坐进了试驾的歼-6，摆到 1200 格高")
if e then
  local id, p0 = e.id, e.root.CFrame.Position
  local n0 = #R.sent
  G.damageEnt(e, 1e9, { team = "enemy", name = "Diag" })
  R.run(0.6)
  check(not P.alive, "飞机被毁：飞行员马上判死（试驾场不是开战阶段也一样）")
  check(boomsSince(n0, p0, 400) == 0, "天上被打下来不当场炸（服务器没发 boom）")
  local v = C.airWreckView and C.airWreckView(id)
  check(v ~= nil and v.wreck ~= nil, "客户端的残骸在演（着火往下掉）")
  local maxD, y0 = 0, v and v.cf.Position.Y or 0
  for _ = 1, 8 do
    R.run(0.25)
    local w = C.airWreckView and C.airWreckView(id)
    if w then maxD = math.max(maxD, (cam.CFrame.Position - w.cf.Position).Magnitude) end
  end
  local w = C.airWreckView and C.airWreckView(id)
  check(w ~= nil and w.cf.Position.Y < y0 - 40, string.format("残骸在往下掉（%.0f → %.0f）", y0, w and w.cf.Position.Y or -1))
  check(maxD > 0 and maxD < 160, string.format("镜头一直跟着残骸（最远 %.0f 格）", maxD))
  check(deathLine() == "损失的载具", "正下方一行「损失的载具」（" .. tostring(deathLine()) .. "）")
  check(#shownText("WtFlight") == 0 and #shownText("AirHud") == 0, "飞行界面收了")
  local radar = me.PlayerGui:FindFirstChild("Radar") or me.PlayerGui:FindFirstChild("AirRadar")
  check(radar == nil or not radar.Enabled or #shownText(radar.Name) == 0, "雷达屏收了")
  local t0 = R.clock()
  T.runUntil(function() return hangarShown() end, 8, 1 / 10)
  check(hangarShown() and R.clock() - t0 < 2.5, string.format("跟完 3 秒回机库（又过了 %.1f 秒）", R.clock() - t0))
  R.run(1)
end

print("② 对局里被打下来：先跟残骸 5 秒，再转去看凶手（4 秒），再回机库")
e = flyHigh()
check(e ~= nil, "第二次试驾坐进飞机（上一次判毁以后没卡住）")
if e then
  -- 训练场上空的靶机当凶手
  local drone, dd = nil, math.huge
  for _, x in ipairs(G.ents or {}) do
    if x.alive and x.testDummy and x.air then
      local d = (x.root.CFrame.Position - e.root.CFrame.Position).Magnitude
      if d < dd then drone, dd = x, d end
    end
  end
  check(drone ~= nil, string.format("找到当凶手的靶机（%.0f 格）", dd))
  e.model:SetAttribute("TestDrive", false)   -- 客户端当它是对局里的飞机
  R.run(0.3)
  local id = e.id
  if drone and C.onMsg then   -- 服务器 Battle.lua 的 killcam（带凶手坐的那架的实体号 kid）
    C.onMsg("killcam", { name = "Diag", d = 1400, kid = drone.id })
  end
  G.damageEnt(e, 1e9, { team = "enemy", name = "Diag" })
  R.run(0.5)
  local t0 = R.clock()
  local nearWreck, nearKiller = 0, 0
  local switched = nil
  while R.clock() - t0 < 8.5 do
    R.run(0.25)
    local u = R.clock() - t0
    local w = C.airWreckView and C.airWreckView(id)
    local dv = drone and C.viewById and C.viewById(drone.id)
    local kp = (dv and dv.cf and dv.cf.Position) or (drone and drone.root.CFrame.Position)
    local cp = cam.CFrame.Position
    if u > 0.5 and u < 4.2 and w and (cp - w.cf.Position).Magnitude < 160 then nearWreck = nearWreck + 1 end
    if u > 5.6 and u < 8 and kp and (cp - kp).Magnitude < 220 then
      nearKiller = nearKiller + 1
      switched = switched or deathLine()
    end
  end
  check(nearWreck >= 12, string.format("前 5 秒镜头跟着自己的残骸（%d / 15 帧）", nearWreck))
  check(nearKiller >= 6, string.format("5 秒后转去看凶手（%d / 9 帧）", nearKiller))
  check(switched ~= nil and switched:find("Diag") ~= nil, "那一行换成凶手（" .. tostring(switched) .. "）")
  T.runUntil(function() return hangarShown() end, 6, 1 / 10)
  local tot = R.clock() - t0
  check(hangarShown() and tot > 8.5 and tot < 11.5, string.format("看完凶手回机库（一共 %.1f 秒）", tot + 0.5))
end

T.summary()
