-- 防空火控显示（模拟器）：python3 tools/mock/run.py tools/mock/aafcs.lua [veh=pgz07]
--   用户 11-22：「高射炮加一个电子屏标记点位然后打」
--   ① 坐上防空车：一架敌机从前面横着飞过去——屏幕上给它画了框、写着型号和距离，左边的搜索雷达小圆屏上有个红点
--   ② 准星转过去：有提前量圈（在飞机的前面），准星压上去圈变绿
--   ③ Q 雷达锁定：框变红、写「锁定」；炮塔自己跟着提前量点转（鼠标不动）
--   ④ 按住左键开火：打得中（敌机掉血）
--   ⑤ 飞机被打下来 / 飞出射程：自动解锁；下车：火控显示收起来
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local VEH = TEST_ARGS:match("veh=(%w+)") or "pgz07"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
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
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "camp")
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local Map = G.Map
local cam = R.workspace.CurrentCamera

print("① 坐上 " .. VEH .. "，前面一架敌机横着飞过去")
local def = VD.get(VEH)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local bx, bz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then bx, bz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 " .. VEH)
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
-- 敌机：车头前面 700 格、高 330 格，横着从左往右飞（每秒 120 格）
local base = st.root * CF(0, -def.H / 2, 0)
local fwd = V3(base.LookVector.X, 0, base.LookVector.Z).Unit
local right = V3(-fwd.Z, 0, fwd.X)
local gy = Map.height(bx, bz)
local p0 = V3(bx, gy + 330, bz) + fwd * 700 - right * 260
local foe = G.newEnt({ kind = "air", team = "atk", cat = "air", hp = 900, size = V3(16, 6, 24), cf = R.CFrame.lookAt(p0, p0 + right), air = true })
foe.model:SetAttribute("Model", "j20")
local fly = { p = p0, v = right * 120 }
local conn = R.Heartbeat:Connect(function(dt)
  if foe.alive then
    fly.p = fly.p + fly.v * dt
    G.moveEnt(foe, R.CFrame.lookAt(fly.p, fly.p + fly.v))
  end
end)
-- 镜头往飞机那边看（鼠标转过去：设镜头角度）
local function lookAt(p)
  local d = (p - cam.CFrame.Position).Unit
  st.camYaw = math.atan2(-d.X, -d.Z)
  st.camPitch = clamp(math.asin(d.Y), -0.75, 0.6)
end
lookAt(fly.p)
R.run(0.5)
local gui = me.PlayerGui:FindFirstChild("AaFcs")
check(gui ~= nil and gui.Enabled, "火控显示开了")
local fs = C.aaFcsState and C.aaFcsState()
check(fs and fs.active, "火控在工作")
local function shownBoxes()
  local n, txt = 0, nil
  for _, f in ipairs(gui:GetChildren()) do
    if f:IsA("Frame") and f.Visible then
      local l = f:FindFirstChildOfClass("TextLabel")
      if l and l.Text:find("km", 1, true) then n = n + 1 txt = l.Text end
    end
  end
  return n, txt
end
local nb, bt = shownBoxes()
check(nb >= 1, "敌机画了框：" .. tostring(bt))
local radar = gui:FindFirstChild("AaRadar")
local reddots = 0
if radar then for _, f in ipairs(radar:GetChildren()) do if f:IsA("Frame") and f.Visible and f.BackgroundColor3.R > 0.8 and f.BackgroundColor3.G < 0.8 and f.Size.X.Offset == 6 then reddots = reddots + 1 end end end
check(reddots >= 1, "搜索雷达小圆屏上有红点（" .. reddots .. "）")

print("② 提前量圈")
fs = C.aaFcsState()
check(fs.target ~= nil, "指定了目标")
local leadOn = false
for _, f in ipairs(gui:GetChildren()) do
  if f:IsA("Frame") and f.Visible and f.Size.X.Offset == 20 and f:FindFirstChildOfClass("UIStroke") then leadOn = true end
end
check(leadOn, "有提前量圈")

print("③ Q 雷达锁定：炮塔自己跟着转")
T.tap(Enum.KeyCode.Q)
R.run(0.2)
fs = C.aaFcsState()
check(fs.lockId ~= nil, "锁定了（" .. tostring(fs.lockId) .. "）")
local status = gui:FindFirstChild("AaStatus")
check(status and (status.Text:find("锁定", 1, true) or status.Text:find("LOCK", 1, true)), "提示写着锁定：" .. tostring(status and status.Text))
-- 镜头转开（鼠标不管炮）：炮还跟着飞机
st.camYaw = st.camYaw + 1.2
R.run(2.5)
local gunDir = VD.gunCF(def, st.root * CF(0, -def.H / 2, 0), st.ty, st.gp).LookVector
local toFoe = (fly.p - (st.root.Position)).Unit
local ang = math.deg(math.acos(clamp(gunDir:Dot(toFoe), -1, 1)))
check(ang < 25, string.format("镜头转开了，炮还指着飞机那边（差 %.1f°，含提前量）", ang))

print("④ 按住左键开火")
local hp0 = foe.hp
lookAt(fly.p)
T.mouse(true)
R.run(3)
T.mouse(false)
R.run(1.5)
print(string.format("   敌机血量 %d → %d", hp0, math.floor(foe.hp)))
check(foe.hp < hp0, "打中了：敌机掉血")

print("⑤ 打下来 / 飞走：自动解锁；下车收起来")
if foe.alive then G.damageEnt(foe, 99999) end
R.run(0.5)
fs = C.aaFcsState()
check(fs.lockId == nil, "目标没了：自动解锁")
conn:Disconnect()
T.tap(Enum.KeyCode.F)
R.run(1)
check(C.drive == nil and not gui.Enabled, "下车：火控显示收起来")
T.summary()
