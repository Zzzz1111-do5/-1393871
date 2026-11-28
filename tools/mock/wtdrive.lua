-- 方向机 / 高低机打坏（模拟器）：python3 tools/mock/run.py tools/mock/wtdrive.lua
--   用户 11-28「方向机也要能被打坏」：照战雷历史模式——受损（没打坏）照常转，打坏了炮塔转不动、炮管俯仰定住；修好就恢复
--   ① 两个模块都在（WtDamage.layout：方向机在炮塔座圈边上、高低机在炮耳下面），框够大、打得中；X 光回放、左下面板认得它们
--   ② 方向机受损：照常转（WtTrav 1）
--   ③ 方向机打坏：WtTrav 0，镜头转到侧面，炮塔不动、车体自己往瞄的方向转
--   ④ 高低机打坏：WtElev false，往上瞄炮管不抬
--   ⑤ 按 Y 修好：两个都恢复，炮塔转过去、炮管抬起来
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
if G.botsClear then G.botsClear() end
local KEY = "t72b3"
T.fakeImport(KEY)
local me = T.join("P1", 8721, true)
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
T.runUntil(function() return P.alive and P.char ~= nil end, 15)
R.run(1)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local Map = G.Map
local cam = R.services.Workspace.CurrentCamera
local def = VD.get(KEY)

print("① 方向机、高低机两个模块")
local lay = W.layout(def)
local td, ed
for _, it in ipairs(lay.list) do
  if it.k == "tdrive" then td = it elseif it.k == "edrive" then ed = it end
end
check(td ~= nil and ed ~= nil, "布局里有方向机、高低机")
if not (td and ed) then T.summary() return end
local function vol(it) local s = it.hi - it.lo return s.X * s.Y * s.Z end
check(vol(td) >= 1.5 and vol(ed) >= 0.8, string.format("框打得中（方向机 %.1f、高低机 %.1f 立方格；原来方向机一小块 0.3）", vol(td), vol(ed)))
check(td.tur and ed.tur, "都装在炮塔上（跟着炮塔转）")
local last = lay.list[#lay.list]
check(last.k == "edrive", "高低机排在最后（WtM 的位置不动：老的存档 / 属性按顺序读）")

-- 车放在平地上，坐进去
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local home = hrp and hrp.Position or V3(0, 0, 0)
local function flatAt(x, z) return Map.isLand(x, z) and Map.height(x, z) > 2 and Map.slope(x, z) < 0.2 end
local spot
for _, rr in ipairs({ 30, 60, 120, 240 }) do
  for k = 0, 23 do
    local a = k / 24 * math.pi * 2
    local x, z = home.X + math.cos(a) * rr, home.Z + math.sin(a) * rr
    if flatAt(x, z) and flatAt(x + 14, z) and flatAt(x - 14, z) then spot = { x = x, z = z } break end
  end
  if spot then break end
end
check(spot ~= nil, "找到放车的平地")
if not spot then T.summary() return end
local e = G.newVehicle("def", KEY, G.vehBaseAt(def, spot.x, spot.z, V3(0, 0, -1)))
R.run(0.5)
if me.Character then me.Character:PivotTo(CF(spot.x + def.W / 2 + 4, Map.height(spot.x, spot.z) + 3, spot.z)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.drive
check(P.vehicle == e and st ~= nil and e.wt ~= nil, "坐进了 T-72B3（服务器建了乘员 / 模块）")
if not st or not e.wt then T.summary() return end
e.wtFx = nil   -- 原厂车没研究「零件」修不了：测试直接当研究过
local S = e.wt
check(S.byK.tdrive ~= nil and S.byK.edrive ~= nil, "服务器认得方向机、高低机")
check(e.model:GetAttribute("WtTrav") == 1 and e.model:GetAttribute("WtElev") == true, "好的时候：WtTrav 1、WtElev true")

local function yawOf(cf) local lv = cf.LookVector return math.deg(math.atan2(-lv.X, -lv.Z)) end
local function angDiff(a, b) return (b - a + 180) % 360 - 180 end
local function hullYaw() return yawOf(e.root.CFrame) end
-- 瞄到车体正前方偏 deg 度、高低 pitch 度（镜头角度，Drive 每帧按它算瞄准点）
local function aim(deg, pitch)
  R.as("client", function()
    local hy = math.rad(hullYaw())
    st.camYaw = hy + math.rad(deg)
    st.camPitch = math.rad(pitch or -2)
  end)
end
local function worldTurretYaw() return (hullYaw() - (st.ty or 0)) end   -- 炮塔在世界里朝哪（Drive：ty 是相对车体，右转为正）

print("② 方向机受损（没打坏）：照常转")
S.byK.tdrive.hp = S.byK.tdrive.max * 0.4
G.wtPush(e)
R.run(0.3)
check(e.model:GetAttribute("WtTrav") == 1, "受损：WtTrav 还是 1（战雷：受损不影响）")
local ty0 = st.ty
aim(60)
R.run(1.5)
check(math.abs(angDiff(ty0, st.ty)) > 20, string.format("受损的方向机照常转（炮塔 %.0f° → %.0f°）", ty0, st.ty))
aim(0)
R.run(2.5)

print("③ 方向机打坏：炮塔不动，车体自己转过去")
S.byK.tdrive.hp = 0
G.wtPush(e)
R.run(0.3)
check(e.model:GetAttribute("WtTrav") == 0, "打坏：WtTrav 0")
local ty1, hy1 = st.ty, hullYaw()
aim(90)
R.run(3)
local ty2, hy2 = st.ty, hullYaw()
print(string.format("   炮塔（相对车体）%.1f° → %.1f°；车体 %.1f° → %.1f°", ty1, ty2, hy1, hy2))
check(math.abs(angDiff(ty1, ty2)) < 0.5, "炮塔转不动（相对车体）")
check(math.abs(angDiff(hy1, hy2)) > 15, string.format("车体自己往瞄的方向转了（%.0f°）", angDiff(hy1, hy2)))
check(C.drive and C.drive.travDead == true, "客户端知道方向机坏了（转车体瞄）")

print("④ 高低机打坏：炮管俯仰定住")
aim(0, -2)
R.run(1.5)
S.byK.edrive.hp = 0
G.wtPush(e)
R.run(0.3)
check(e.model:GetAttribute("WtElev") == false, "打坏：WtElev false")
local gp1 = st.gp
aim(0, 10)
R.run(1.5)
check(math.abs((st.gp or 0) - (gp1 or 0)) < 0.2, string.format("往上瞄炮管不抬（%.1f° → %.1f°）", gp1 or 0, st.gp or 0))

print("⑤ 按 Y 修好：都恢复")
T.act("wtFix")
R.run(0.5)
check(S.fixT ~= nil, "开始修")
T.runUntil(function() return S.fixT == nil end, 60, 1 / 5)
R.run(0.5)
check(S.byK.tdrive.hp > 0 and S.byK.edrive.hp > 0, "修好了（两个模块都有血）")
check(e.model:GetAttribute("WtTrav") == 1 and e.model:GetAttribute("WtElev") == true, "WtTrav 1、WtElev true")
local ty3, gp3 = st.ty, st.gp   -- 修好那一刻炮管已经朝④里瞄的 10° 抬上去了（高低机好了）：这里再往下瞄，看它跟着动
aim(70, -1)
R.run(2)
check(math.abs(angDiff(ty3, st.ty)) > 20, string.format("炮塔又能转了（%.0f° → %.0f°）", ty3, st.ty))
check(math.abs((st.gp or 0) - (gp3 or 0)) > 3, string.format("炮管又能俯仰了（%.1f° → %.1f°）", gp3 or 0, st.gp or 0))
local _ = worldTurretYaw
T.summary()
