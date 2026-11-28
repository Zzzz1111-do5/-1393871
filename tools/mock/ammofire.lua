-- 弹药架起火、机枪连续贯穿的 X 光（模拟器）：python3 tools/mock/run.py tools/mock/ammofire.lua
--   用户 11-28：「弹药架起火如果不及时灭火修要爆炸」「机枪连续贯穿车体的话 x光就同一个角度然后一直放各种子弹打进去的x透视吧」
--   ① 弹药架起火：车里面板写「弹药架起火！N 秒内按 Y 灭火」、倒计时往下走；8 秒没灭——殉爆（原来烧完只有四成炸）
--   ② 起火后按 Y 灭火：不炸
--   ③ 机枪一串打穿同一辆：X 光不重画、不换角度，一发发叠进去（弹道越来越多），写「连续贯穿 ×N」；停了以后再打一发大的照常重画
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local KEY = "t72b3"
T.fakeImport(KEY)
local me = T.join("P1", 8711, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local Map = G.Map
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(0, 0, 0)
local def = VD.get(KEY)
local bx, bz = hp.X + 30, hp.Z
local function newTank(x, z)
  return G.newVehicle("def", KEY, G.vehBaseAt(def, x, z, V3(0, 0, -1)))
end
local function enter(e)
  if me.Character then me.Character:PivotTo(CF(e.root.CFrame.Position.X + def.W / 2 + 4, Map.height(e.root.CFrame.Position.X, e.root.CFrame.Position.Z) + 3, e.root.CFrame.Position.Z)) end
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(1)
end
local function panelTip()
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d:IsA("TextLabel") and d.Visible and type(d.Text) == "string" and d.Text:find("弹药架起火", 1, true) then return d.Text end
  end
end
local function ammoFire(e)   -- 同服务器 Wt.lua 发射药烧起来那一下（8 秒内不灭就殉爆）
  local t = R.clock()   -- 服务器的 now()（模拟时钟）；测试这边的 os.clock 是 CPU 时间
  e.wt.fireT, e.wt.ammoFireT, e.wt.ammoBoomT, e.wt.fireUntil = t, t, t + 8, t + 9
  G.wtPush(e)
end

print("① 弹药架起火：倒计时，8 秒没灭就殉爆")
local e = newTank(bx, bz)
R.run(1)
enter(e)
check(C.drive ~= nil, "坐进了车")
ammoFire(e)
R.run(1.2)
local left0 = e.model:GetAttribute("WtAFLeft")
local tip = panelTip()
check(type(left0) == "number" and left0 <= 8 and left0 >= 6, "车上记着还有几秒殉爆（WtAFLeft " .. tostring(left0) .. "）")
check(tip ~= nil and tip:find("%d") ~= nil, "面板写「弹药架起火！N 秒内按 Y 灭火」（" .. tostring(tip) .. "）")
R.run(3)
local left1 = e.model:GetAttribute("WtAFLeft")
check(type(left1) == "number" and left1 < left0, string.format("倒计时往下走（%s → %s）", tostring(left0), tostring(left1)))
T.runUntil(function() return not e.alive end, 8, 1 / 10)
check(not e.alive and e.model:GetAttribute("WtWhy") == "ammo", "没灭：殉爆（" .. tostring(e.model:GetAttribute("WtWhy")) .. "）")
T.runUntil(function() return not P.alive end, 10)
R.run(6)
T.actAs(me, "deploy", "rifle", "base")
R.run(2)

print("② 按 Y 灭火：不炸")
hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
hp = hrp and hrp.Position or hp
local e2 = newTank(hp.X + 30, hp.Z)
R.run(1)
enter(e2)
ammoFire(e2)
R.run(2)
T.actAs(me, "wtExt")
R.run(0.5)
check(e2.model:GetAttribute("WtAF") == false and e2.model:GetAttribute("WtAFLeft") == nil, "灭火器把弹药架的火灭了、倒计时没了")
R.run(9)
check(e2.alive, "过了殉爆的时间也没炸")

print("③ 机枪一串打穿同一辆：同一个角度往里叠")
local foe = newTank(hp.X + 30, hp.Z + 60)
R.run(1)
local xrF = me.PlayerGui:FindFirstChild("WtXray", true)   -- 命中的 X 光窗口（WtHud）
local vp = xrF and xrF:FindFirstChild("View")
local worldM = vp and vp:FindFirstChildOfClass("WorldModel")
local function hit(sub, k)
  local p = foe.root.CFrame.Position
  G.R.Drive:FireClient(me, { op = "wtHit", id = foe.id, veh = KEY, r = "pen", parts = {},
    xr = { p = { 0.3 * k, 1.2, -2.5 }, d = { 0, -0.05, 1 }, ty = 0, seed = 100 + k, half = 18, n = 3, core = 0.4, sub = sub } })
end
hit("ac", 1)
R.run(0.2)
local n1 = worldM and #worldM:GetChildren() or 0
local cf1 = vp and vp.CurrentCamera and vp.CurrentCamera.CFrame
check(xrF ~= nil and T.visible(xrF) and n1 > 0, "第一发：X 光出来了（" .. n1 .. " 块）")
for k = 2, 6 do
  hit("ac", k)
  R.run(0.12)
end
R.run(0.3)
local n2 = worldM and #worldM:GetChildren() or 0
local cf2 = vp and vp.CurrentCamera and vp.CurrentCamera.CFrame
check(n2 > n1 + 8, string.format("后面五发叠进去：%d → %d 块", n1, n2))
check(cf1 ~= nil and cf2 ~= nil and (cf1.Position - cf2.Position).Magnitude < 0.01, "镜头一直是同一个角度")
local burstTxt = nil
for _, d in ipairs(xrF and xrF:GetDescendants() or {}) do
  if d:IsA("TextLabel") and d.Visible and d.Text:find("连续贯穿", 1, true) then burstTxt = d.Text end
end
check(burstTxt ~= nil and burstTxt:find("6", 1, true) ~= nil, "写「连续贯穿 ×6」（" .. tostring(burstTxt) .. "）")
R.run(2)
hit("ds", 7)   -- 停了一会儿、一发大的：照常重画
R.run(0.3)
local n3 = worldM and #worldM:GetChildren() or 0
check(n3 < n2, string.format("停了以后一发脱壳弹：重画（%d 块）", n3))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | ", 1, math.min(#R.errors, 3)))
T.summary()
