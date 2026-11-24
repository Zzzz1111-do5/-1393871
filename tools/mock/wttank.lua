-- 战雷式坦克（模拟器）：python3 tools/mock/run.py tools/mock/wttank.lua [veh=m1a2]
--   用户 11-24 夜「把整个游戏做成战雷」：①② 车辆伤害模型 + 坦克界面
--   ① 坐上车：战雷界面开着（准星、底部弹药栏、左下损伤图），MWT 那套收起；弹药栏格数 = 主炮弹种 + 别的武器 + 烟幕 + 维修
--   ② 数字键：2 选第二种弹（M830）、1 回到 M829A3，5 选同轴机枪
--   ③ 正前方放一辆敌方 T-90M：准星对着它不是白的（穿深指示）；M829A3 打车体正面、榴弹打正面颜色不一样
--   ④ 开一炮：服务器走战雷伤害（G.wtHits 加一），客户端命中提示出来；损伤图里那辆车的状态跟着变
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"

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
T.actAs(me, "deploy", "rifle", "base")   -- 11-24 B：只在自己主基地出生（base / baseAir）
R.run(1.5)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local Map = G.Map
local function find(name)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == name then return d end
  end
end

print("① 坐上 " .. VEH)
local def = VD.get(VEH)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
-- 前面 300 格都是平地的一块（要放敌车、打一炮）
local best, bx, bz = math.huge, hp.X + 16, hp.Z
for k = 0, 47 do
  local a = k / 48 * math.pi * 2
  for _, rr in ipairs({ 20, 40, 70 }) do
    local x, z = hp.X + math.cos(a) * rr, hp.Z + math.sin(a) * rr
    if Map.isLand(x, z) and Map.isLand(x, z - 240) and Map.height(x, z) > 2 then
      local s = 0
      for j = 0, 8 do s = s + Map.slope(x, z - j * 30) end
      s = s + math.abs(Map.height(x, z) - Map.height(x, z - 240)) * 0.05
      if s < best then best, bx, bz = s, x, z end
    end
  end
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
R.run(0.6)
check(e.wt ~= nil and e.model:GetAttribute("WtC") ~= nil, "服务器给这辆车建了乘员 / 模块（WtC " .. tostring(e.model:GetAttribute("WtC")) .. "）")
local gui = me.PlayerGui:FindFirstChild("WtTank")
check(gui ~= nil and gui.Enabled, "战雷界面开着")
local mwt = find("MWT")
check(mwt == nil or not T.visible(mwt), "MWT 那套收起")
local aim = find("WtGunAim")
check(aim ~= nil and T.visible(aim), "准星画出来了")
local slots = C.wtTankSlots and C.wtTankSlots() or {}
local list = {}
for _, sd in ipairs(slots) do table.insert(list, (sd.am or sd.wid or sd.k) .. (sd.num and ("[" .. sd.num .. "]") or "")) end
print("  弹药栏：" .. table.concat(list, " "))
local nGun = #(R.require(R.services.ReplicatedStorage:FindFirstChild("Ballistics")).GUN[def.weapons[1]] or { 1 })
local extra = ((def.cat == "apc" or def.cat == "aa") and 1 or 0) + ((def.cat ~= "aa") and 1 or 0)   -- 侦察（轻型车）、火炮支援（不是防空车）
check(#slots == nGun + (#def.weapons - 1) + 2 + extra, "弹药栏格数 = 主炮 " .. nGun .. " 种弹 + 别的武器 + 烟幕 + 维修 + 侦察 / 火炮（" .. #slots .. "）")
local di = find("WtDamageInd")
local sch = find("Schematic")
local nSch = sch and #sch:GetDescendants() or 0
check(di ~= nil and T.visible(di) and nSch > 20, "左下损伤图（" .. nSch .. " 个零件）")
local old = find("WtCrew")
check(old == nil or not T.visible(old), "原来的车组图标面板收起")

print("② 数字键选弹种")
local BAL = R.require(R.services.ReplicatedStorage:FindFirstChild("Ballistics"))
local gl = BAL.GUN[def.weapons[1]]
if gl and #gl >= 2 then
  T.tap(Enum.KeyCode.Two)
  R.run(0.2)
  check(st.wi == 1 and st.fcs.am == gl[2], "按 2：" .. tostring(st.fcs.am))
  T.tap(Enum.KeyCode.One)
  R.run(0.2)
  check(st.wi == 1 and st.fcs.am == gl[1], "按 1：" .. tostring(st.fcs.am))
  local mgN = #gl + 1
  if def.weapons[2] and mgN <= 6 then
    T.tap(({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six })[mgN])
    R.run(0.2)
    check(st.wi == 2, "按 " .. mgN .. "：换到 " .. tostring(def.weapons[st.wi]))
    T.tap(Enum.KeyCode.One)
    R.run(0.2)
  end
end

print("③ 正前方一辆敌方 T-90M：准星的颜色（穿深指示）")
local d2 = VD.get("t90m")
local e2 = G.newVehicle("atk", "t90m", G.vehBaseAt(d2, bx, bz - 180, V3(0, 0, 1)))
check(e2 ~= nil, "放了敌车")
R.run(1.5)
local ring = aim and aim:FindFirstChild("Frame") or nil
local function ringColor()
  for _, f in ipairs(aim:GetChildren()) do
    local s = f:FindFirstChildOfClass("UIStroke")
    if s and s.Thickness > 1.5 and s.Thickness < 1.7 then return s.Color end
  end
end
-- 直接按炮口 → 敌车车体正面中间算一次（镜头在模拟器里不一定对着它）
local base = st.root * CF(0, -def.H / 2, 0)
local gcf = VD.gunCF(def, base, st.ty or 0, st.gp or 0)
local tgt = e2.root.Position + V3(0, -0.5, d2.L / 2 - 1)
local function colFor(am)
  C.wtTankStep(st, { p = tgt, o = gcf.Position, relK = 1, ready = true, left = 0, wid = def.weapons[1], w = VD.W[def.weapons[1]], am = am })
  local c = ringColor()
  return c and string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "?"
end
local cAP = colFor(gl and gl[1])
local cHE = colFor(gl and gl[#gl])
print("  " .. tostring(gl and gl[1]) .. "：" .. cAP .. "   " .. tostring(gl and gl[#gl]) .. "：" .. cHE)
check(cAP ~= "240,244,244", "穿甲弹对着敌车不是白的")
check(cAP ~= cHE, "穿甲弹、" .. tostring(gl and gl[#gl]) .. " 颜色不一样")

print("④ 开一炮：服务器走战雷伤害、客户端命中提示")
local h0 = G.wtHits or 0
-- 镜头（瞄准线）对着敌车车身，等炮塔、炮转过去（同 tankfcs.lua）
local cam = R.workspace.CurrentCamera
local function aimAt(p)
  local eye = cam.CFrame.Position
  local dd = (p - eye).Unit
  st.camYaw = math.atan2(-dd.X, -dd.Z)
  st.camPitch = math.asin(dd.Y)
end
local tc = e2.root.CFrame.Position + V3(0, 0.6, 0)
for _ = 1, 12 do aimAt(tc) R.run(0.4) end
local c2 = ringColor()
print("  对着敌车时游戏里的准星：" .. (c2 and string.format("%d,%d,%d", math.floor(c2.R * 255 + 0.5), math.floor(c2.G * 255 + 0.5), math.floor(c2.B * 255 + 0.5)) or "?"))
R.as("client", function() C.driveTryFire() end)
for _ = 1, 240 do
  R.run(1 / 60)
  if (G.wtHits or 0) > h0 then break end
end
R.run(1.5)
local h1 = G.wtHits or 0
local L = G.wtLast
print("  wtHits " .. h0 .. " → " .. h1 .. (L and ("，结果 " .. tostring(L.r) .. " 穿深 " .. tostring(L.pen and math.floor(L.pen)) .. " 等效 " .. tostring(L.eff and math.floor(L.eff)) .. " 毫米") or ""))
check(h1 > h0, "炮弹打中敌车走了战雷伤害")
local ht = find("WtHitText")
check(ht ~= nil, "命中提示框在")
print("  敌车 WtC " .. tostring(e2.model:GetAttribute("WtC")) .. " WtM " .. tostring(e2.model:GetAttribute("WtM")))

T.summary()
