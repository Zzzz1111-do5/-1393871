-- X 透视自己的车（模拟器）：python3 tools/mock/run.py tools/mock/xrayown.lua
--   用户 11-27「x 透视不够细节」（11-26「x透视做的非常潦草 且没有显示」「x应该是摁住显示3d 松手就恢复原样 然后 不同区域要有不同颜色标识」）：
--   ① T-72B3（转盘自动装弹机、模型上的爆反）按住 X：乘员是零件拼的人（每人十个零件以上、只有一个球是头）、人在车里面；按类别分组上色、
--      Highlight 不超过 31 个、零件不超过 600 个；柴油机、炮塔驱动画成好几个零件
--   ② 弹药按发数：转盘里画的 = 车上 Rdy 发（每个位置弹丸 + 药筒两个零件）、车体弹架 = 备弹 − 待发；待发少了三发，透视里也少三发
--   ③ 炮管、炮闩跟着炮的俯仰和炮塔方位走：炮管方向 = VehDefs.gunCF（车体、炮塔转角、俯仰）；抬炮以后还对得上
--   ④ 鼠标指着炮管：旁边写「炮管」「完好」「125 毫米」；观瞄打坏 → 观瞄进「打坏」那一组、写「损毁」；起火 → 发动机进「起火」那一组
--   ⑤ 松手全清：OwnXray、图例都没了，车身透明度还原；零件收进对象池——再按住一个零件都不新建；稳着按住的时候不新建、不换组
--   ⑥ 每一型车（VehDefs 全部）算出来：零件 ≤ 600、Highlight ≤ 31、乘员都是人形且在车里、炮管画到炮口、燃气轮机是一节节圆柱
local T = dofile(MOCK_DIR .. "/common.lua")
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
R.run(1.5)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local Map = G.Map
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(0, 0, 0)
local def = VD.get(KEY)
local bx, bz = hp.X + 30, hp.Z
local e = G.newVehicle("def", KEY, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
R.run(1)
if hrp then me.Character:PivotTo(CF(bx + def.W / 2 + 4, Map.height(bx, bz) + 3, bz)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.drive
check(st ~= nil, "坐进了 T-72B3")
if not st then T.summary() return end
local em = st.em
local d = st.d
local function clamp1(x) return math.max(-1, math.min(1, x)) end
local function angle(a, b) return math.deg(math.acos(clamp1(a.Unit:Dot(b.Unit)))) end
local function hullF()
  local v = C.views and C.views[em]
  return (v and v.hullF) or (st.root * CF(0, -d.H / 2, 0))
end
local function inGroup(q) return q.p.Parent and q.p.Parent.Name or "-" end

-- 车身本来的透明度（松手以后要一模一样）
local v0 = C.views and C.views[em]
local ltm0, nModel = 0, 0
if v0 and v0.model then
  for _, p in ipairs(v0.model:GetDescendants()) do
    if p:IsA("BasePart") then nModel = nModel + 1 ltm0 = ltm0 + p.LocalTransparencyModifier end
  end
end

print("① 按住 X：零件拼的人、按类别分组")
T.key(Enum.KeyCode.X, true)
R.run(0.4)
local info = C.ownXrayInfo()
check(C.ownXrayOn() and info.on, "按住 X 透视打开了")
local roles, okN, okBall = {}, true, true
for role, n in pairs(info.crew) do
  roles[#roles + 1] = role .. " " .. n
  if n < 10 then okN = false end
  local balls = 0
  for _, q in ipairs(info.items[role].parts) do if q.p.Shape == Enum.PartType.Ball then balls = balls + 1 end end
  if balls ~= 1 then okBall = false end
end
table.sort(roles)
check(#roles == 3 and okN, "三个乘员都是零件拼的人（头、躯干、上臂、前臂、大腿、小腿……）：" .. table.concat(roles, "、"))
check(okBall, "每个人只有一个球（头），别的是一段段的胳膊腿")
do   -- 人在车里面：底座系里不低于车底、不高过车顶、不出车体两边和前后
  local hf = hullF()
  local bad = {}
  for role in pairs(info.crew) do
    for _, q in ipairs(info.items[role].parts) do
      local lp = hf:PointToObjectSpace(q.p.Position)
      if lp.Y < -0.1 or lp.Y > d.H + 0.1 or math.abs(lp.X) > d.W / 2 + 0.1 or math.abs(lp.Z) > d.L / 2 + 0.1 then
        bad[#bad + 1] = role .. string.format("(%.1f,%.1f,%.1f)", lp.X, lp.Y, lp.Z)
        break
      end
    end
  end
  check(#bad == 0, "乘员都在车体里（没穿出去）" .. ((#bad > 0) and ("：" .. table.concat(bad, " ")) or ""))
end
local xf = R.workspace:FindFirstChild("OwnXray")
local names = {}
if xf then for _, c in ipairs(xf:GetChildren()) do if c.ClassName == "Model" then names[c.Name] = true end end end
local have = {}
for _, k in ipairs({ "X_crew", "X_engine", "X_engine_dk", "X_trans", "X_fuel", "X_ammo", "X_ammo_tip", "X_breech", "X_barrel", "X_tdrive", "X_optics", "X_track", "X_era" }) do
  if names[k] then have[#have + 1] = k end
end
check(#have >= 12, "按类别分组（" .. table.concat(have, " ") .. "）")
check(info.hl <= 31, "Highlight 一共 " .. info.hl .. " 个（Roblox 上限 31）")
check(info.parts <= 600, "零件一共 " .. info.parts .. " 个（上限 600）")
check(info.items.engine and info.items.engine.n >= 20, "柴油机：曲轴箱、两排气缸、缸盖罩、排气歧管和支管、风扇……（" .. tostring(info.items.engine and info.items.engine.n) .. " 个零件）")
check(info.items.tdrive and info.items.tdrive.n >= 14, "炮塔驱动：座圈齿圈一圈 + 电机（" .. tostring(info.items.tdrive and info.items.tdrive.n) .. " 个零件）")
check(info.items.era_hull ~= nil or info.items.era_tur ~= nil, "爆反块照模型上真的块画")
check(R.services.Players.LocalPlayer.PlayerGui:FindFirstChild("OwnXrayLegend") ~= nil, "屏幕上有图例")

print("② 弹药按发数")
local rdy, cap = em:GetAttribute("Rdy"), em:GetAttribute("RdyCap")
local rk, hk = info.racks.ammo, info.racks.ammoH
print(string.format("  （车上 Rdy %s / RdyCap %s；透视：转盘 %s / %s，车体 %s）", tostring(rdy), tostring(cap), tostring(rk and rk.n), tostring(rk and rk.cap), tostring(hk and hk.n)))
check(rk and rdy and rk.n == rdy and rk.cap == cap, "转盘自动装弹机画了 Rdy 发、RdyCap 个位置")
check(rk and rk.shown == 1 + rk.n * 2, "转盘每个位置弹丸 + 药筒两个零件（加一块底板：" .. tostring(rk and rk.shown) .. "）")
local am = C.S and C.S.veh and C.S.veh.ammo and C.S.veh.ammo[d.weapons[1]]
if am and hk and rdy then
  check(hk.n == math.max(0, am[2] - rdy), string.format("车体弹架 = 备弹 %d − 待发 %d = %d", am[2], rdy, hk.n))
end
if rdy and rdy >= 3 then
  e.model:SetAttribute("Rdy", rdy - 3)   -- 打了三发（服务器那边写的同一个属性）
  R.run(0.2)
  local i2 = C.ownXrayInfo()
  check(i2.racks.ammo.n == rdy - 3 and i2.racks.ammo.shown == 1 + (rdy - 3) * 2, "待发少了三发：透视里转盘也少三发（" .. i2.racks.ammo.n .. "）")
  e.model:SetAttribute("Rdy", rdy)
  R.run(0.2)
  check(C.ownXrayInfo().racks.ammo.n == rdy, "补回来以后又画满")
end

print("③ 炮管、炮闩跟着俯仰和方位")
local function tube() local it = C.ownXrayInfo().items.barrel return it and it.parts[1] and it.parts[1].p end
local function breech() local it = C.ownXrayInfo().items.breech return it and it.parts[1] and it.parts[1].p end
local function want() return VD.gunCF(d, hullF(), st.ty, st.gp).LookVector end
local t1, b1 = tube(), breech()
check(t1 and angle(t1.CFrame.RightVector, want()) < 2, string.format("炮管方向对着炮（差 %.2f°，俯仰 %.1f°、方位 %.1f°）", t1 and angle(t1.CFrame.RightVector, want()) or -1, st.gp or 0, st.ty or 0))
check(b1 and angle(b1.CFrame.LookVector, want()) < 2, "炮闩方向对着炮")
local gp0 = st.gp or 0
st.camPitch = 0.45   -- 往上看：炮抬起来
R.run(1.5)
local t2, b2 = tube(), breech()
local dg = (st.gp or 0) - gp0
print(string.format("  （俯仰 %.1f° → %.1f°）", gp0, st.gp or 0))
check(math.abs(dg) > 3, "炮抬起来了")
check(t2 and angle(t2.CFrame.RightVector, want()) < 2, string.format("抬炮以后炮管还对得上（差 %.2f°）", t2 and angle(t2.CFrame.RightVector, want()) or -1))
check(b2 and angle(b2.CFrame.LookVector, want()) < 2, "抬炮以后炮闩也跟着")
do   -- 炮管画到炮口
  local mz = VD.gunCF(d, hullF(), st.ty, st.gp) * V3(0, 0, -d.gun.len)
  local far = 1e9
  for _, q in ipairs(C.ownXrayInfo().items.barrel.parts) do
    local p = q.p
    local tip = p.Position + p.CFrame.RightVector * (p.Size.X / 2)
    if p.Shape == Enum.PartType.Cylinder then far = math.min(far, (tip - mz).Magnitude) end
  end
  check(far < 0.4, string.format("炮管画到炮口（离炮口 %.2f 格）", far))
end
st.camPitch = -0.12
R.run(1)

print("④ 鼠标指着的部件：名字、状态")
local cam = R.workspace.CurrentCamera
local g = VD.gunCF(d, hullF(), st.ty, st.gp)
local P0 = g * V3(0, 0, -d.gun.len * 0.85)
local keep = cam.CFrame
cam.CFrame = R.CFrame.lookAt(P0 + g.RightVector * 24, P0)   -- 镜头挪到炮管侧面（这一下马上算，不跑帧：Drive 每帧会把镜头摆回去）
local k1, n1 = C.ownXrayPick(640, 360)
cam.CFrame = keep
check(k1 == "barrel" and n1 == "炮管", "从侧面对着炮管：指着的是「" .. tostring(n1) .. "」")
R.run(0.1)
local sp, on = cam:WorldToViewportPoint(P0)
R.mouseAt = R.Vector2 and R.Vector2.new(sp.X, sp.Y) or nil
R.run(0.2)
local lg = R.services.Players.LocalPlayer.PlayerGui:FindFirstChild("OwnXrayLegend")
local tip = lg and lg:FindFirstChild("Tip")
local function tipText(name) local l = tip and tip:FindFirstChild(name) return l and l.Text or "" end
print(string.format("  （镜头里炮口那一截在 %.0f, %.0f；旁边写「%s」「%s」「%s」）", sp.X, sp.Y, tipText("Name"), tipText("State"), tipText("Info")))
if R.mouseAt and on then
  check(tip and tip.Visible and tipText("Name") ~= "", "鼠标指着部件：旁边写了名字")
  check(tipText("Name") ~= "炮管" or (string.find(tipText("State"), "完好", 1, true) ~= nil and string.find(tipText("Info"), "125", 1, true) ~= nil), "指着炮管：写「完好」「125 毫米」")
  check(C.ownXrayInfo().hover ~= nil, "指着的那一件换成高亮那一组")
end
R.mouseAt = nil
-- 观瞄打坏 → 打坏那一组、写「损毁」
local opt = e.wt and e.wt.byK.optics
if opt then
  opt.hp = 0
  G.wtPush(e)
  R.run(0.3)
  local oi = C.ownXrayInfo().items.optics
  check(oi and oi.ov == "broken" and inGroup(oi.parts[1]) == "X_broken", "观瞄打坏了：进「打坏」那一组（红）")
  opt.hp = opt.max
  G.wtPush(e)
  R.run(0.3)
  oi = C.ownXrayInfo().items.optics
  check(oi and oi.ov == nil and inGroup(oi.parts[1]) == "X_optics", "修好了：回到观瞄那一组")
end
local gnr = e.wt and e.wt.seat and e.wt.seat.gnr
if gnr then
  local h0 = gnr.hp
  gnr.hp = 30
  G.wtPush(e)
  R.run(0.3)
  local gi = C.ownXrayInfo().items.gnr
  check(gi and gi.ov == "hurt", "炮长受伤：进「受损」那一组（琥珀）")
  gnr.hp = h0
  G.wtPush(e)
  R.run(0.3)
end
e.model:SetAttribute("WtF", true)
R.run(0.3)
local ei = C.ownXrayInfo().items.engine
check(ei and ei.ov == "fire", "起火：发动机进「起火」那一组（火光色一闪一闪）")
e.model:SetAttribute("WtF", false)
R.run(0.3)
check(C.ownXrayInfo().items.engine.ov == nil, "灭了：发动机回到原来的颜色")

print("⑤ 松手全清、对象池、每帧只改 CFrame")
local i3 = C.ownXrayInfo()
local made0, parts0 = i3.stats.made, i3.parts
T.key(Enum.KeyCode.X, false)
R.run(0.3)
local i4 = C.ownXrayInfo()
check(not C.ownXrayOn() and not i4.on, "松开 X：透视关了")
check(R.workspace:FindFirstChild("OwnXray") == nil, "OwnXray 整个删了")
check(R.services.Players.LocalPlayer.PlayerGui:FindFirstChild("OwnXrayLegend") == nil, "图例删了")
if v0 and v0.model then
  local ltm1 = 0
  for _, p in ipairs(v0.model:GetDescendants()) do if p:IsA("BasePart") then ltm1 = ltm1 + p.LocalTransparencyModifier end end
  check(math.abs(ltm1 - ltm0) < 0.01, string.format("车身透明度还原（%d 块）", nModel))
end
check(i4.pooled >= parts0, "零件收进对象池（" .. i4.pooled .. " / " .. parts0 .. "）")
T.key(Enum.KeyCode.X, true)
R.run(0.4)
local i5 = C.ownXrayInfo()
check(i5.on and i5.stats.made == made0, "再按住：零件全从对象池拿，没新建（新建过 " .. made0 .. " 个，现在 " .. i5.stats.made .. "）")
local rg0 = i5.stats.regroup
R.run(0.5)
local i6 = C.ownXrayInfo()
check(i6.stats.made == made0 and i6.stats.regroup == rg0, "稳着按住：不新建、不换组（每帧只改 CFrame）")
T.key(Enum.KeyCode.X, false)
R.run(0.2)

print("⑥ 每一型车")
local nV, over, hlOver, crewBad, barrelBad, turbBad, carBad = 0, {}, {}, {}, {}, {}, {}
local ids = {}
for id in pairs(VD.D) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do
  local dd = VD.D[id]
  local ok, Pl = pcall(C.ownXrayPlan, dd)
  if not ok then
    over[#over + 1] = id .. " 出错：" .. tostring(Pl)
  else
    nV = nV + 1
    if Pl.total > 600 then over[#over + 1] = id .. " " .. Pl.total end
    if Pl.nKeys + 6 > 31 then hlOver[#hlOver + 1] = id .. " " .. (Pl.nKeys + 6) end
    for _, x in ipairs(Pl.items) do
      if x.kind == "crew" then
        local bad = #x.specs < 10
        -- 车体两边、前后；炮塔里的人还可以在炮塔伸出车体的那一块里（CRAM 的炮塔转轴偏在左边，炮塔探出车体）
        local xm, zm = dd.W / 2, dd.L / 2
        if x.it.tur and dd.turret then
          local tp, ts = dd.turret.pivot, Pl.lay.ts
          xm, zm = math.max(xm, math.abs(tp.X) + ts.X / 2), math.max(zm, math.abs(tp.Z) + ts.Z / 2)
        end
        for _, s in ipairs(x.specs) do
          local p = s.cf.Position
          if x.it.tur then p = W.fromTur(dd, p, 0) end
          if p.Y < -0.1 or p.Y > dd.H + 0.1 or math.abs(p.X) > xm + 0.1 or math.abs(p.Z) > zm + 0.1 then bad = true end
        end
        if bad then crewBad[#crewBad + 1] = id .. "." .. x.k end
      elseif x.k == "barrel" and (dd.gun.len or 0) >= 1 and (dd.gun.cal or 0) > 0 then
        local far = 1e9
        for _, s in ipairs(x.specs) do
          if s.sh == "C" then
            local tipZ = s.cf.Position.Z - s.s.X / 2
            far = math.min(far, math.abs(tipZ + dd.gun.len))
          end
        end
        if far > 0.3 then barrelBad[#barrelBad + 1] = id .. string.format("(%.2f)", far) end
      elseif x.k == "engine" and dd.turbine then
        local cyl = 0
        for _, s in ipairs(x.specs) do if s.sh == "C" then cyl = cyl + 1 end end
        if cyl < 8 then turbBad[#turbBad + 1] = id .. " " .. cyl end
      elseif x.k == "ammo" and W.CAROUSEL[id] and x.rack then
        if x.rack.cap < 15 or #x.specs < 1 + x.rack.cap * 2 then carBad[#carBad + 1] = id .. " " .. #x.specs end
      end
    end
  end
end
check(#over == 0, nV .. " 型车的零件都不超过 600" .. ((#over > 0) and ("：" .. table.concat(over, "、")) or ""))
check(#hlOver == 0, "Highlight 组都不超过 31" .. ((#hlOver > 0) and ("：" .. table.concat(hlOver, "、")) or ""))
check(#crewBad == 0, "每一型车的乘员都是人形、都在车里" .. ((#crewBad > 0) and ("：" .. table.concat(crewBad, "、")) or ""))
check(#barrelBad == 0, "炮管都画到炮口" .. ((#barrelBad > 0) and ("：" .. table.concat(barrelBad, "、")) or ""))
check(#turbBad == 0, "燃气轮机（M1、T-80）是一节节圆柱" .. ((#turbBad > 0) and ("：" .. table.concat(turbBad, "、")) or ""))
check(#carBad == 0, "转盘自动装弹机的车：一圈弹丸 + 药筒" .. ((#carBad > 0) and ("：" .. table.concat(carBad, "、")) or ""))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
