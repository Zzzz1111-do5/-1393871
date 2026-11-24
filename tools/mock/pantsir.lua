-- 铠甲-S1 弹炮合一防空车（模拟器）：python3 tools/mock/run.py tools/mock/pantsir.lua
--   用户 11-24：「没事干了就去找俄系……越多越逼真越好」——铠甲-S1：两门 2A38M 双管 30 炮 + 12 枚 57E6 地空导弹
--   （高炮那套火控照 aafcs.lua veh=pantsir 测）。这里测导弹：
--   ① 换到 57E6：没用雷达锁住飞机就按开火——提示先按 Q 锁定，不发
--   ② Q 锁住前面的敌机，开火：服务器从发射筒打出一枚导弹、追着那架飞（导弹的目标就是锁住的那架），12 枚少一枚
--   ③ 导弹打中：敌机掉血 / 被打下来；被打的要是有人开，会收到导弹来袭告警（这里是没人开的靶机，只看打中）
--   ④ 原模型（blveh.json pantsir）的搜索雷达那块元数据带 k = radar：车模里那块带 Radar 属性（一直转）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8131, true)
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

local def = VD.get("pantsir")
check(def ~= nil and def.cat == "aa", "有铠甲-S1（防空）")
local hasSam = false
for _, w in ipairs(def.weapons) do if VD.W[w] and VD.W[w].kind == "sam" then hasSam = true end end
check(hasSam, "武器里有地空导弹：" .. table.concat(def.weapons, "、"))
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local bx, bz = hp.X + 20, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 26, hp.Z + math.sin(a) * 26
  if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then bx, bz = x, z break end
end
local e = G.newVehicle("def", "pantsir", G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了铠甲-S1")
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
-- 靶机：车头前面 900 格、高 380 格，慢慢横着飞（每秒 70 格）
local base = st.root * CF(0, -def.H / 2, 0)
local fwd = V3(base.LookVector.X, 0, base.LookVector.Z).Unit
local right = V3(-fwd.Z, 0, fwd.X)
local gy = Map.height(bx, bz)
local p0 = V3(bx, gy + 380, bz) + fwd * 900 - right * 120
local foe = G.newEnt({ kind = "air", team = "atk", cat = "air", hp = 900, size = V3(16, 6, 24), cf = R.CFrame.lookAt(p0, p0 + right), air = true })
foe.model:SetAttribute("Model", "j20")
local fly = { p = p0, v = right * 70 }
local conn = R.Heartbeat:Connect(function(dt)
  if foe.alive then
    fly.p = fly.p + fly.v * dt
    G.moveEnt(foe, R.CFrame.lookAt(fly.p, fly.p + fly.v))
  end
end)
local function lookAt(p)
  local d = (p - cam.CFrame.Position).Unit
  st.camYaw = math.atan2(-d.X, -d.Z)
  st.camPitch = clamp(math.asin(d.Y), -0.75, 0.6)
end
lookAt(fly.p)
R.run(0.5)

print("① 换到 57E6，没锁就开火：不发、提示先锁")
local samI
for i, w in ipairs(def.weapons) do if w == "s57e6" then samI = i end end
C.driveWeapon(samI)
R.run(0.2)
local launched = {}
local launch0 = G.launch
G.launch = function(s)
  if s.kind == "missile" and s.byEnt == e.id then table.insert(launched, s) end
  return launch0(s)
end
local fs = C.aaFcsState and C.aaFcsState()
check(fs and fs.active, "选着导弹：防空火控照样工作（框、雷达屏）")
if fs and fs.lockId then T.tap(Enum.KeyCode.Q) R.run(0.1) end
T.mouse(true)
R.run(0.3)
T.mouse(false)
R.run(0.3)
check(#launched == 0, "没锁住：一枚都没发（" .. #launched .. "）")
local tip = T.texts(C.T("veh.samNeedLock"))
check(#tip > 0, "提示：先按 Q 用雷达锁住一架飞机")

print("② Q 锁住，开火：一枚导弹追着锁住的那架")
lookAt(fly.p)
R.run(0.3)
T.tap(Enum.KeyCode.Q)
R.run(0.2)
fs = C.aaFcsState()
check(fs.lockId ~= nil and fs.lockId == foe.id, "锁住了靶机（" .. tostring(fs.lockId) .. "）")
local mag0 = e.wst.s57e6.mag
R.run(1.2)   -- 炮塔转过去
T.mouse(true)
R.run(0.2)
T.mouse(false)
R.run(0.3)
check(#launched == 1 and launched[1].tgt == foe, string.format("发了 %d 枚，目标是锁住的那架（%s）", #launched, tostring(launched[1] and launched[1].tgId)))
check(e.wst.s57e6.mag == mag0 - 1, string.format("导弹 %d → %d 枚", mag0, e.wst.s57e6.mag))

print("③ 打中")
local hp0 = foe.hp
T.runUntil(function() return not foe.alive or foe.hp < hp0 end, 12)
check(not foe.alive or foe.hp < hp0, string.format("导弹打中了：靶机血量 %d → %d", hp0, math.floor(foe.alive and foe.hp or 0)))
G.launch = launch0
conn:Disconnect()

print("④ 原模型的搜索雷达那块会转")
local IM = R.require(R.services.ReplicatedStorage:FindFirstChild("ImportedMeta"))
local info = IM.m and IM.m.pantsir
if info then
  local rk = nil
  for name, p in pairs(info.parts) do if p.k == "radar" then rk = name end end
  check(rk ~= nil, "元数据：搜索雷达天线单独一块、k = radar（" .. tostring(rk) .. "）")
  check(IM.alias and IM.alias.pantsir == "pantsir", "alias：型号 pantsir → 模型 pantsir")
else
  print("  （ImportedMeta 里还没有 pantsir：模型没转，这项跳过）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
