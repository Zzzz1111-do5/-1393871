-- 炮兵视角、火控计算机（模拟器）：python3 tools/mock/run.py tools/mock/arty.lua
--   用户 11-25：「部分远火高射形载具 更新一下要有坦克世界那种 可以把视角放到射程范围内的任何位置 但是对于敌载具的视野是要受限于我方信息的
--   然后 可以在目标点像截图这样在地面有一个3d的散步圈 然后 如果我目标标定移动很快的话 这个圈会变大 然后慢慢变小这样」
--   ① 坐上 M109A7，Shift 进炮兵视角：镜头在天上往下看，地上有散布圈、射程圈、弹道弧线，屏幕上写飞行时间、距离
--   ② 鼠标把瞄准点挪出射程：拉回射程圈上；挪得快圈胀大，停下几秒收小
--   ③ 全队看不见的敌车不画（模型隐藏），看得见的画
--   ④ 开炮：服务器收到散布圈大小，落点在圈里；Shift 退出，地上的圈收掉
--   ⑤ 火控计算机（「科技树里面根据年代给有火控计算机的坦克……更新火控计算机 可以有不同等级进行升级」）：按年代分代、改装树三级
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
G.Config.Round.prep = 4   -- 准备阶段缩短（测的不是它）
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "def"
me.Team = G.TEAM.def
me.Neutral = false
me:SetAttribute("Side", "def")
G.pushOne(P)
R.run(1)
local C = T.C
if T.leaveMenu then T.leaveMenu() elseif C.menuShown and C.menuShown() then C.menuEnter() end
-- 出生点：这张图上能用的第一个（camp / base / redbase……）；出生倒计时没到会被拒，隔一会儿再要
local spId = "camp"
for _, sp in ipairs(G.spawnList and G.spawnList(P.team, P) or {}) do
  if sp.ok and (sp.kind == "camp" or sp.kind == "base" or sp.kind == "redbase") then spId = sp.id break end
end
for _ = 1, 6 do
  if P.alive then break end
  T.actAs(me, "deploy", "rifle", spId)
  T.runUntil(function() return P.alive end, 4)
end
print("  （出生点 " .. tostring(spId) .. "，活着 " .. tostring(P.alive) .. "）")
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local WM = R.require(RS:FindFirstChild("WtMods"))
local TT = R.require(RS:FindFirstChild("TechTree"))
local Map = G.Map
local cam = R.workspace.CurrentCamera

print("① 坐上自行火炮、进炮兵视角")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local def = VD.get("m109a7")
local e = G.newVehicle("def", "m109a7", G.vehBaseAt(def, hp.X + 30, hp.Z, V3(0, 0, -1)))
R.run(0.5)
if hrp then hrp.CFrame = CF(hp.X + 40, Map.height(hp.X + 40, hp.Z) + 3, hp.Z) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
do
  local h2 = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
  print(string.format("  （上车前：活着 %s、队 %s / %s、车活着 %s、离车 %.1f 格、倒地 %s、车上 %s）", tostring(P.alive), tostring(P.team), tostring(e.team),
    tostring(e.alive), h2 and (h2.Position - e.root.CFrame.Position).Magnitude or -1, tostring(P.downed), tostring(P.vehicle and P.vehicle.def and P.vehicle.def.id)))
end
check(P.vehicle == e and C.drive ~= nil, "坐上了 M109A7")
if not C.drive then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 90)
local st = C.drive
local w = VD.W[def.weapons[st.wi]]
check(w and w.kind == "arty", "当前武器是曲射的（" .. tostring(def.weapons[st.wi]) .. "）")
R.as("client", function() C.driveToggleSight() end)
R.run(0.5)
check(st.arty == true and C.artyOn(), "Shift 进了炮兵视角")
check(st.sight ~= true, "不是开的瞄准镜")
local p0 = st.root.Position
local ap = st.aimPt
check(ap ~= nil and (cam.CFrame.Position.Y - ap.Y) > 200, string.format("镜头在瞄准点上方 %.0f 格", ap and cam.CFrame.Position.Y - ap.Y or -1))
local marks = R.workspace:FindFirstChild("ArtyMarks")
local n = marks and #marks:GetChildren() or 0
check(n > 150, "地上画了散布圈、射程圈、弹道弧线（" .. n .. " 段）")
check(#T.texts("秒") > 0 and #T.texts("米") > 0, "屏幕上写了飞行时间、距离")

print("② 挪瞄准点：出了射程拉回来；挪得快圈胀大，停下收小")
R.as("client", function() C.artyMouse(V3(0, -100000, 0), 1 / 60) end)
R.run(0.2)
local fd = V3(st.aimPt.X - p0.X, 0, st.aimPt.Z - p0.Z).Magnitude
check(fd <= w.maxR + 2 and fd >= w.maxR * 0.9, string.format("推到射程外：拉回射程圈上（%.0f / 最远 %d 格）", fd, w.maxR))
local b1 = C.artyBloom()
check(b1 > 0.5, string.format("刚挪过：圈胀开 %.2f", b1))
R.run(5)
local b2 = C.artyBloom()
check(b2 < 0.12, string.format("停下 5 秒：收到 %.2f", b2))

print("③ 敌车只画全队看得见的")
-- 放在 5000 格外（地面视线最远 3600 格，没有队友在那边）：全队都看不见它
local dir = V3(st.aimPt.X - p0.X, 0, st.aimPt.Z - p0.Z).Unit
local far = p0 + dir * 5000
local foe = G.newVehicle("atk", "ztz99a", G.vehBaseAt(VD.get("ztz99a"), far.X, far.Z, V3(1, 0, 0)))
R.run(1.5)
local v = C.views and C.views[foe.model]
local hid = 0
if v and v.model then
  for _, p in ipairs(v.model:GetDescendants()) do if p:IsA("BasePart") and p.LocalTransparencyModifier >= 0.99 then hid = hid + 1 end end
end
check(v ~= nil and hid > 0, "没人发现的敌车不画（藏了 " .. hid .. " 块）")
if G.spotted then G.spotted.def[foe.id] = os.clock() + 30 end   -- 队友侦察到它
R.run(1.5)
hid = 0
if v and v.model then
  for _, p in ipairs(v.model:GetDescendants()) do if p:IsA("BasePart") and p.LocalTransparencyModifier >= 0.99 then hid = hid + 1 end end
end
check(hid == 0, "队友侦察到以后画出来了（还藏着 " .. hid .. " 块）")

print("④ 开炮、退出")
local seenDisp = nil
G.R.Drive.OnServerEvent:Connect(function(_, d) if type(d) == "table" and d.op == "fire" then seenDisp = d.disp end end)
R.as("client", function() C.driveTryFire() end)
R.run(0.5)
check(seenDisp ~= nil and seenDisp < 0.2, "开炮带上了散布圈大小（" .. tostring(seenDisp) .. "）")
R.as("client", function() C.driveToggleSight() end)
R.run(0.3)
check(not C.artyOn() and st.arty ~= true, "Shift 退出炮兵视角")
check(R.workspace:FindFirstChild("ArtyMarks") == nil, "地上的圈收掉了")

print("⑥ X 透视自己的车、B 大地图（用户 11-25「烟幕改成m x改成透视自己的坦克」「按m放大地图」）")
-- 用户 11-26「x应该是摁住显示3d 松手就恢复原样 然后 不同区域要有不同颜色标识」：按住 X 才显示
T.key(T.Enum.KeyCode.X, true)
R.run(0.3)
local xf = R.workspace:FindFirstChild("OwnXray")
local grp, hls, cats = 0, 0, {}
if xf then
  for _, c in ipairs(xf:GetChildren()) do
    if c.ClassName == "Model" then grp = grp + 1 cats[c.Name] = true end
    for _, h in ipairs(c:GetChildren()) do if h.ClassName == "Highlight" then hls = hls + 1 end end
  end
end
local cl = {}
for k in pairs(cats) do cl[#cl + 1] = k end
table.sort(cl)
check(C.ownXrayOn() and grp >= 5 and hls >= grp, "按住 X：按类别分组上色（" .. table.concat(cl, " ") .. "），每组一个 Highlight")
check(cats.X_crew and cats.X_engine and cats.X_ammo, "乘员、发动机、弹药都有")
check(R.services.Players.LocalPlayer.PlayerGui:FindFirstChild("OwnXrayLegend") ~= nil, "屏幕上有图例")
T.key(T.Enum.KeyCode.X, false)
R.run(0.2)
check(not C.ownXrayOn() and R.workspace:FindFirstChild("OwnXray") == nil, "松开 X 恢复原样")
R.as("client", function() C.driveToggleSight() end)
R.run(0.3)
local inSight = C.drive and C.drive.sight
T.key(T.Enum.KeyCode.X, true)
R.run(0.3)
check(inSight and C.ownXrayOn() and not C.drive.sight, "瞄准镜里按住 X：退到车外看得见")
T.key(T.Enum.KeyCode.X, false)
R.run(0.3)
check(C.drive and C.drive.sight, "松开回到瞄准镜里")
R.as("client", function() C.driveToggleSight() end)
R.run(0.3)
R.as("client", function() C.wtMapToggle(true) end)
R.run(0.3)
local mg = me.PlayerGui:FindFirstChild("WtMap")
check(mg and mg.Enabled and C.mapRoot and C.mapRoot.Parent and C.mapRoot.Parent.Name == "Holder", "大地图页开着，地图挂在页里")
check(#T.texts("目标") > 0 and #T.texts("A") > 0, "左边写了目标、右边有网格坐标")
R.as("client", function() C.wtMapToggle(false) end)
R.run(0.3)
check(not mg.Enabled and C.mapRoot.Parent ~= nil and C.mapRoot.Parent.Name ~= "Holder", "关上以后地图挂回小地图")

print("⑤ 火控计算机按年代分代、改装树三级")
local okGen = 0
for _, it in pairs(TT.byKey) do
  local g = WM.fcsGen(it)
  if g then
    okGen = okGen + 1
    -- WtMods.GEN_FIX 照真车改过的不算（11-27：M60 / M60A1 有 M17 合像测距仪 + M13 弹道计算机，第 1 代）
    if it.year < 1965 and not WM.GEN_FIX[it.key] then check(g == 0, it.key .. " 1965 年以前没有火控计算机") end
  end
end
check(okGen >= 10, "有坦克炮的车都定了火控是哪一代（" .. okGen .. " 辆）")
local m1 = TT.byKey.us_m1a2 or TT.byKey.us_m1a1
if m1 then
  local L = WM.list(m1)
  local nF = 0
  for _, m in ipairs(L) do if m.key == "fcs1" or m.key == "fcs2" or m.key == "fcs3" then nF = nF + 1 end end
  check(nF == 3, m1.key .. " 的改装树里有三级火控升级（" .. nF .. "）")
  local P0, P3 = WM.fcsParams(WM.fcsGen(m1), 0), WM.fcsParams(WM.fcsGen(m1), 3)
  check(P3.sig < P0.sig and P3.rangeT < P0.rangeT and P3.lead >= P0.lead, "升满三级：测距快、散布小、提前量更好")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
