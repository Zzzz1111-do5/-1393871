-- 车被打爆的特效（模拟器）：python3 tools/mock/run.py tools/mock/wreckfx.lua [veh=t90m]
--   用户 11-25「载具爆炸效果不够猛画风不够战雷」：
--   ① 弹药殉爆：大火球、炮塔被顶飞、十来块钢板碎块（真零件，会落地）飞出去、舱口窜火、地面烧焦一块
--   ② 之后几秒车里的弹接连殉爆（一发一发）
--   ③ 十几秒后碎块清掉；残骸还在、地面的焦斑跟着残骸；全程没报错
--   ④ 乘员打光的车：不炸、不出碎块
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "t90m"

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
-- 车摆在镜头附近（离镜头远的特效少画、六千格外不画）
local cam = R.workspace.CurrentCamera
local hp = cam.CFrame.Position
local function spot(r)
  for k = 0, 35 do
    local a = k / 36 * math.pi * 2
    local x, z = hp.X + math.cos(a) * r, hp.Z + math.sin(a) * r
    if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then return x, z end
  end
  return hp.X + r, hp.Z
end
local fx = R.workspace:FindFirstChild("ClientFx")
local function chunks()
  local n = 0
  for _, p in ipairs(fx and fx:GetChildren() or {}) do
    if p:IsA("BasePart") and p.Material == R.Enum.Material.CorrodedMetal and not p.Anchored then n = n + 1 end
  end
  return n
end
local function killAs(e, why)
  e.model:SetAttribute("WtWhy", why)
  e.wtWhy = why
  G.wtRaw = true
  G.damageEnt(e, 1e9, nil)
  G.wtRaw = false
end

print("① " .. VEH .. " 弹药殉爆")
local bx, bz = spot(60)
local e = G.newVehicle("atk", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
R.run(1.5)
local st = C.wreckStat
check(st ~= nil, "WreckFx 起来了")
local big0, ch0 = st and st.big or 0, st and st.chunks or 0
killAs(e, "ammo")
-- 弹药在底下转盘里的车（用户 11-26「要先着火再飞」，WtDamage.CAROUSEL）：先从舱口往外窜火几秒，再掀炮塔、炸开
local WD = R.require(R.services.ReplicatedStorage:FindFirstChild("WtDamage"))
local cook = WD.CAROUSEL[VEH] and WD.cookSecs(e.id) or 0
if cook > 0 then
  R.run(0.6)
  check(st and (st.cook or 0) >= 1 and st.big == big0, string.format("转盘弹药：先着火（%s 次），还没炸（火球 %d）——%.1f 秒后再炸", tostring(st and st.cook), st and st.big or -1, cook))
  R.run(cook)
else
  R.run(0.6)
end
check(st and st.big == big0 + 1, "殉爆：大火球（" .. tostring(st and st.big) .. "）")
local nc = chunks()
check(nc >= 6, "钢板碎块飞出去了（" .. nc .. " 块真零件）")
check(st and st.jets >= 1, "舱口窜火")
check(st and st.scorch >= 1, "地面烧焦一块")
R.run(2.5)
local fell = 0
for _, p in ipairs(fx and fx:GetChildren() or {}) do
  if p:IsA("BasePart") and p.Material == R.Enum.Material.CorrodedMetal and not p.Anchored then
    local gy = Map.height(p.Position.X, p.Position.Z)
    if p.Position.Y < gy + 12 then fell = fell + 1 end
  end
end
check(fell >= 1, "碎块落回地上（" .. fell .. " 块离地不到 12 格）")

print("② 接连殉爆")
R.run(6)
check(st and st.pops >= 5, "车里的弹一发一发殉爆（" .. tostring(st and st.pops) .. " 下）")

print("③ 碎块清掉、焦斑跟着残骸")
R.run(14)
check(chunks() == 0, "十几秒后碎块都清掉了（还剩 " .. chunks() .. "）")

print("④ 乘员打光的车：不炸")
local bx2, bz2 = spot(90)
local e2 = G.newVehicle("atk", VEH, G.vehBaseAt(def, bx2, bz2, V3(0, 0, -1)))
R.run(1.5)
local big1, ch1 = st.big, chunks()
killAs(e2, "crew")
R.run(1)
check(st.big == big1 and chunks() == ch1, string.format("没有大火球、没有碎块（火球 %d → %d，碎块 %d → %d）", big1, st.big, ch1, chunks()))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
