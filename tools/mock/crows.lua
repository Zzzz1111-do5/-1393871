-- 车长遥控武器站（模拟器）：python3 tools/mock/run.py tools/mock/crows.lua
--   M1A2 车长位按 T 看 CROWS 屏：鼠标转的是武器站（M2），炮塔不跟着转（还归炮长的准星）；开火打的是 12.7 毫米机枪，从 M2 枪口出；
--   摄像头装在托架上，画面跟着 M2 转、俯仰（以前画面转了、M2 不动）
--   ① 坐上 M1A2、进车内、换到车长位，按 T：开的是 CROWS，武器换成 12.7 毫米机枪，画面顺着 M2
--   ② 鼠标往右、往上：M2 转过去、抬起来，炮塔不动；抬到头不超过俯仰范围
--   ③ 开火：服务器那发从 M2 枪口出、顺着枪管
--   ④ 再按 T：退出，武器换回来，M2 交回炮长的准星
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = "m1a2"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8301, true)
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
local def = VD.get(VEH)

print("① 坐上 M1A2、进车内、换到车长位，按 T")
check(def.rws ~= nil, string.format("M1A2 有遥控武器站（俯仰 %d°～%d°）", def.rws and def.rws.elev[1] or 0, def.rws and def.rws.elev[2] or 0))
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 18, hp.Z + math.sin(a) * 18
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(P.vehicle == e and st ~= nil, "坐上了 M1A2")
if not st then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
local ci
for i, k in ipairs(I.cur and I.cur.spec.order or {}) do if k == "commander" then ci = i end end
check(ci ~= nil, "有车长位（F" .. tostring(ci and ci + 1) .. "）")
if not ci then T.summary() return end
T.tap(Enum.KeyCode["F" .. (ci + 1)])
R.run(0.4)
check(C.interiorState().station == "commander", "换到车长位")
local wi0, ty0 = st.wi, st.ty
T.tap(Enum.KeyCode.T)
R.run(0.8)
local os_ = C.interiorOpticState()
check(os_ ~= nil and os_.o.kind == "crows", "开的是 CROWS（" .. tostring(os_ and os_.o.kind) .. "）")
check(st.d.weapons[st.wi] == "hmg", "武器换成 12.7 毫米机枪：" .. tostring(st.d.weapons[st.wi]))
local v
for em, vv in pairs(C.views or {}) do if em == e.model then v = vv end end
check(v ~= nil and v.rgF ~= nil, "画出来的车有遥控武器站（会转、会俯仰）")
local cam = R.workspace.CurrentCamera
if v and v.rgF then
  local ang = math.deg(math.acos(math.max(-1, math.min(1, cam.CFrame.LookVector:Dot(v.rgF.LookVector)))))
  check(ang < 3, string.format("CROWS 画面顺着 M2 看（差 %.1f°）", ang))
end

print("② 鼠标往右、往上：M2 转过去、抬起来，炮塔不跟着转")
local my0, mp0 = st.my, st.mp
-- 鼠标灵敏度跟着视场走（Interior：0.0035 弧度 / 像素 × 视场 / 72）：CROWS 宽视场 30°
local fov = os_ and os_.o.fovs[1] or 30
local perPx = math.deg(0.0035 * fov / 72)
for _ = 1, 10 do R.mouseDelta = R.Vector2.new(30, 0) R.run(1 / 30) end   -- 往右一共 300 像素
R.run(1.2)
local dTy = math.abs(((st.ty - ty0 + 180) % 360) - 180)
check(st.my - my0 > 300 * perPx * 0.85, string.format("M2 往右转了 %.0f°（鼠标给了 %.0f°）", st.my - my0, 300 * perPx))
check(dTy < 3, string.format("炮塔没跟着转（%.1f°）", dTy))
for _ = 1, 10 do R.mouseDelta = R.Vector2.new(0, -40) R.run(1 / 30) end   -- 往上 400 像素
R.run(1.2)
local wantUp = math.min(400 * perPx, def.rws.elev[2] - mp0)
check(st.mp - mp0 > wantUp * 0.85 and st.mp <= def.rws.elev[2] + 0.1, string.format("M2 抬起来 %.0f°（鼠标给了 %.0f°，上限 %d°）", st.mp, 400 * perPx, def.rws.elev[2]))
for _ = 1, 60 do R.mouseDelta = R.Vector2.new(0, -60) R.run(1 / 30) end
R.run(1.5)
check(st.mp <= def.rws.elev[2] + 0.1 and st.mp > def.rws.elev[2] - 3, string.format("抬到头是 %.0f°（上限 %d°）", st.mp, def.rws.elev[2]))
for _ = 1, 60 do R.mouseDelta = R.Vector2.new(0, 60) R.run(1 / 30) end   -- 放平
R.run(1.5)

print("③ 开火：子弹从 M2 枪口出、顺着枪管")
local shots = {}
local bs0 = G.botShot
G.botShot = function(from, to, w, ...) table.insert(shots, { from = from, to = to }) return bs0(from, to, w, ...) end
R.as("client", function() C.driveTryFire() end)
R.run(0.3)
G.botShot = bs0
local sh = shots[#shots]
check(sh ~= nil, "服务器开了一枪（" .. #shots .. " 发）")
if sh then
  local bse = G.vehBaseOf and G.vehBaseOf(e) or (e.root.CFrame * CF(0, -def.H / 2, 0))
  local mz = VD.muzzle(def, bse, e.ty, e.gp, "rws", e.my, e.mp)
  local off = (sh.from - mz.Position).Magnitude
  local dir = (sh.to - sh.from).Unit
  local ang = math.deg(math.acos(math.max(-1, math.min(1, dir:Dot(mz.LookVector)))))
  check(off < 0.6, string.format("子弹从 M2 枪口出（差 %.2f 格）", off))
  check(ang < 1.5, string.format("顺着枪管（差 %.2f°）", ang))
end

print("④ 再按 T：退出")
T.tap(Enum.KeyCode.T)
R.run(0.5)
check(C.interiorOpticState() == nil, "退出了")
check(st.wi == wi0, "武器换回原来那件（" .. tostring(st.d.weapons[st.wi]) .. "）")
check(st.rwsPt == nil, "M2 交回炮长的准星")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
