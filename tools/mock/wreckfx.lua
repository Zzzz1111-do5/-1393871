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
-- 用户 11-28 晚「坦克被穿透关键部位要直接爆 炮塔炮管子都要崩飞」：打中就炸（不再先烧），炮塔顶飞、炮管从炮塔上断开单独甩出去——哪种坦克都是
local function viewOfE(ent)
  for em2, vv in pairs(C.views or {}) do if em2 == ent.model then return vv end end
end
local function tossCheck(ent, name)
  local vv = viewOfE(ent)
  check(vv and vv.toss ~= nil and vv.gtoss ~= nil, name .. "：炮塔、炮管都飞起来了（" .. tostring(vv and vv.toss ~= nil) .. " / " .. tostring(vv and vv.gtoss ~= nil) .. "）")
  if vv and vv.toss and vv.gtoss then
    local gap = (vv.gtoss.cf.Position - vv.toss.cf.Position).Magnitude
    local h0 = vv.hullF and vv.hullF.Position.Y or 0
    check(gap > 4, string.format("%s：炮管跟炮塔分开飞（隔 %.1f 格）", name, gap))
    local peak = math.max(vv.gtoss.cf.Position.Y, vv.toss.cf.Position.Y) - h0
    check(peak > 2, string.format("%s：飞起来了（高出车体 %.1f 格）", name, peak))
  end
end
tossCheck(e, VEH)
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
-- 用户 11-28（战雷截图）：火球大到占满半个屏幕（约一个车长）、烧着的碎块甩出一道道拖着黑烟的弧（Trail 烟带）
check(st and (st.lastR or 0) >= math.min(28, math.max(def.L, def.W)) - 0.01,
  string.format("火球半径约一个车长（%.1f 格，车长 %.1f）", st and st.lastR or -1, def.L))
local nTr = 0
for _, c in ipairs(C.wreckChunkList()) do
  if c.tr and c.tr.Parent == c.p and c.tr.Enabled and c.tr.FaceCamera and c.tr.Lifetime >= 2.5 then nTr = nTr + 1 end
end
check(nTr >= 4, string.format("烧着的碎块拖着烟带（%d 条 Trail）", nTr))

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
-- 碎块落地以后烟带不再往后拖（已经拖出来的自己淡掉）
local trOn = 0
for _, c in ipairs(mine) do if c.tr and c.tr.Enabled then trOn = trOn + 1 end end
check(trOn == 0, "落地了：烟带不再拖新的（还开着 " .. trOn .. " 条）")
-- 用户 11-28「然后有浓烈的烟雾我持续冒」：原来七十秒只剩一缕烟——改成 60 秒火小一半、烟照样浓，150 秒以后小火 + 烟柱一直冒
do
  local BR = C.wreckBurnRates
  local function rates()
    local M = vView and vView.M
    local b, bn = M and M.black, M and M.blackN
    return (M and M.fire and M.fire.Rate) or -1, ((b and b.Rate) or 0) + ((bn and bn.Rate) or 0)
  end
  local f0, b0 = rates()
  check(BR ~= nil and f0 == BR.fire[1] and b0 == BR.black[1], string.format("打爆二十来秒：大火 %s、浓烟 %s 颗 / 秒", tostring(f0), tostring(b0)))
  vView.wreckT = vView.wreckT - 45   -- 当作烧了一分多钟
  R.run(0.3)
  local f1, b1 = rates()
  check(f1 == BR.fire[2] and b1 == BR.black[2], string.format("一分钟以后：火小一半（%s）、烟照样浓（%s）", tostring(f1), tostring(b1)))
  vView.wreckT = vView.wreckT - 120   -- 两分半以后
  R.run(0.3)
  local f2, b2 = rates()
  check(f2 == BR.fire[3] and b2 == BR.black[3] and b2 >= 5, string.format("两分半以后：小火苗（%s）、烟柱接着冒（%s 颗 / 秒，不是一缕）", tostring(f2), tostring(b2)))
  vView.wreckT = vView.wreckT - 600
  R.run(0.6)
  local _, b3 = rates()
  check(b3 == BR.black[3], string.format("十几分钟了还在冒（%s 颗 / 秒）", tostring(b3)))
end
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
-- 用户 11-28 晚「炮塔炮管子都要崩飞」：弹在炮塔尾舱 / 车体里的西方坦克殉爆也掀炮塔、炮管单独飞（放最后：多等的几秒不碍前面碎块烟带那几项）
do   -- 弹在炮塔尾舱 / 车体里的西方坦克（原来殉爆炮塔不飞）
  local VEH2 = "leo2a6"   -- VehDefs 的型号（科技树的键是 de_leo2a6）
  local def2 = VD.get(VEH2)
  if def2 and def2.turret then
    local x2, z2 = spot(110)
    local e2 = G.newVehicle("atk", VEH2, G.vehBaseAt(def2, x2, z2, V3(0, 0, -1)))
    R.run(1.5)
    killAs(e2, "ammo")
    R.run(0.25)
    tossCheck(e2, VEH2)
    R.run(4)
    local vv = viewOfE(e2)
    check(vv and vv.gtoss and vv.gtoss.rest, VEH2 .. "：炮管落地躺平（" .. tostring(vv and vv.gtoss and vv.gtoss.rest) .. "）")
  end
end
T.summary()
