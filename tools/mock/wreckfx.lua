-- 车被打爆的特效（模拟器）：python3 tools/mock/run.py tools/mock/wreckfx.lua [veh=t90m]
--   用户 11-25「载具爆炸效果不够猛画风不够战雷」：
--   ① 弹药殉爆：大火球、炮塔被顶飞、十来块钢板碎块（真零件，挂恒力）飞出去、舱口窜火、地面烧焦一块；碎块的碰撞组只碰地形、建筑
--   ② 之后几秒车里的弹接连殉爆（一发一发）
--   ③ 碎块按新设计「落地定住、留到残骸消失」（11-27 审查 15b：模拟器没有物理，碎块自己不会动——原来那两条「落回地上」「十几秒后清掉」
--      是走了「一直没落地、9 秒淡掉」那条路的假阳性，跟设计正相反）：这里把碎块摆到地上、速度清零，看它落地就关恒力、4 秒后定住
--      （锚定、不再碰撞），残骸在就一直留着（过 20 秒还在），残骸没了一起收掉
--   ④ 乘员打光的车：不炸、不出碎块；全程没报错
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
local function chunks(anchored)
  local n = 0
  for _, p in ipairs(fx and fx:GetChildren() or {}) do
    if p:IsA("BasePart") and p.Material == R.Enum.Material.CorrodedMetal and (p.Anchored == (anchored == true)) then n = n + 1 end
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
local list = C.wreckChunkList()
local nVF, nGrp = 0, 0
for _, c in ipairs(list) do
  local vf = c.p:FindFirstChildOfClass("VectorForce")
  if vf and vf.Enabled then nVF = nVF + 1 end
  if c.p.CollisionGroup == "VfxChunk" then nGrp = nGrp + 1 end
end
check(nVF == #list and #list >= 6, string.format("碎块飞的时候挂着恒力（%d / %d 块）", nVF, #list))
check(C.wreckGroupsOk == true and nGrp == #list, string.format("碎块的碰撞组 VfxChunk（%d / %d 块）", nGrp, #list))
local PS = R.services.PhysicsService
check(PS:CollisionGroupsAreCollidable("VfxChunk", "Default") and not PS:CollisionGroupsAreCollidable("VfxChunk", "VfxActor"),
  "碎块只跟地形、建筑（Default）碰，不碰角色和车（VfxActor）")
local vView
for em2, vv in pairs(C.views or {}) do if em2 == e.model then vView = vv end end
local vPart = vView and vView.M and vView.M.parts[1] and vView.M.parts[1][1]
check(vPart and vPart.CollisionGroup == "VfxActor", string.format("车的样子放进 VfxActor（%s）", tostring(vPart and vPart.CollisionGroup)))
check(st and (st.jets >= 1 or (cook > 0 and (st.cook or 0) >= 1)), "舱口窜火（转盘车：先烧的那两个舱口接着喷）")
check(st and st.scorch >= 1, "地面烧焦一块")

print("② 接连殉爆")
R.run(6)
check(st and st.pops >= 5, "车里的弹一发一发殉爆（" .. tostring(st and st.pops) .. " 下）")

print("③ 碎块落地定住、留到残骸消失（模拟器没有物理：碎块摆到地上、速度清零）")
local mine = {}
for _, c in ipairs(C.wreckChunkList()) do
  if not c.dead and c.p.Parent and c.owner then
    mine[#mine + 1] = c
    local pos = c.p.Position
    c.p.CFrame = CF(pos.X, math.max(Map.height(pos.X, pos.Z), 0) + 1, pos.Z)
    c.p.AssemblyLinearVelocity = V3(0, 0, 0)
  end
end
check(#mine >= 6, "跟着残骸的碎块（" .. #mine .. " 块）")
R.run(0.6)
local landed, vfOff = 0, 0
for _, c in ipairs(mine) do
  if c.land then landed = landed + 1 end
  if not c.vf or not c.vf.Enabled then vfOff = vfOff + 1 end
end
check(landed == #mine and vfOff == #mine, string.format("落地就关恒力（落地 %d、关了 %d / %d 块）", landed, vfOff, #mine))
R.run(4.5)
local rested, anch = 0, 0
for _, c in ipairs(mine) do
  if c.rest then rested = rested + 1 end
  if c.p.Anchored and not c.p.CanCollide and c.p.Parent then anch = anch + 1 end
end
check(rested == #mine and anch == #mine, string.format("落地 4 秒后定住：锚定、不再碰撞（%d / %d 块）", anch, #mine))
R.run(20)
local still = 0
for _, c in ipairs(mine) do if c.p.Parent and not c.dead and c.p.Transparency < 0.5 then still = still + 1 end end
check(still == #mine, string.format("残骸还在：碎块一直留着（过 20 秒还剩 %d / %d 块）", still, #mine))
G.removeEnt(e)
R.run(0.5)
local gone = 0
for _, c in ipairs(mine) do if not c.p.Parent or c.dead then gone = gone + 1 end end
check(gone == #mine, string.format("残骸没了：碎块一起收掉（%d / %d 块）", gone, #mine))

print("④ 乘员打光的车：不炸")
local bx2, bz2 = spot(90)
local e2 = G.newVehicle("atk", VEH, G.vehBaseAt(def, bx2, bz2, V3(0, 0, -1)))
R.run(1.5)
local big1, ch1 = st.big, st.chunks
killAs(e2, "crew")
R.run(1)
check(st.big == big1 and st.chunks == ch1, string.format("没有大火球、没有碎块（火球 %d → %d，碎块 %d → %d）", big1, st.big, ch1, st.chunks))
print("⑤ 角色也放进 VfxActor（碎块不碰角色）")
T.actAs(me, "deploy", "rifle", "base")   -- 前面用的 camp 在现在的图（Map.BASES）上出不了生：这里按 base 出生，看角色的零件
R.run(1.5)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
check(hrp ~= nil and hrp.CollisionGroup == "VfxActor", string.format("出生的角色放进 VfxActor（%s）", tostring(hrp and hrp.CollisionGroup)))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
