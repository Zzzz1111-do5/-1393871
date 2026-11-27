-- X 透视自己的车（模拟器）：python3 tools/mock/run.py tools/mock/xrayown.lua
--   用户 11-27「x 透视不够细节」（11-26「x透视做的非常潦草 且没有显示」「x应该是摁住显示3d 松手就恢复原样 然后 不同区域要有不同颜色标识」）：
--   ① T-72B3（转盘自动装弹机、模型上的爆反）按住 X：乘员是零件拼的人（每人十个零件以上、只有一个球是头）、人在车里面；按类别分组上色、
--      Highlight 不超过 31 个、零件不超过 600 个；柴油机、炮塔驱动画成好几个零件；鼠标放开、画出指针；每帧在主循环的 steps 里（View 之后）摆
--   ② 弹药按发数：转盘里画的 = 车上 Rdy 发（每个位置弹丸 + 药筒两个零件）、车体弹架 = 备弹 − 待发；待发少了三发，透视里也少三发；
--      AmL 里第一种弹打光了：转盘第一格写的换成下一种弹
--   ③ 炮管、炮闩跟着炮的俯仰和炮塔方位走：炮管方向 = VehDefs.gunCF（车体、炮塔转角、俯仰）；抬炮以后还对得上；炮塔转过 60° 以后炮长的头
--      还在 WtDamage.fromTur 算的地方（炮塔系的件跟着炮塔转）
--   ④ 真按住 X、挪鼠标（审查 11-27：原来测试手动把镜头挪到炮管侧面、直接写鼠标位置，游戏里鼠标锁在屏幕中间根本指不到——假阳性）：
--      按住 X 时鼠标放开（Default、指针画出来），挪鼠标镜头和炮塔不转；鼠标挪到发动机上：旁边写「发动机」「柴油机」；挪到炮口：「炮管」「完好」「125 毫米」；
--      挪到车外：提示框收起；观瞄打坏 → 观瞄进「打坏」那一组、写「损毁」；炮长受伤；起火 → 发动机进「起火」那一组；
--      乘员状态按座位（WtC「状态 + 座位」：车长顶上阵亡的炮长以后，炮长位是活人、车长位阵亡）
--   ⑤ 松手全清：OwnXray、图例都没了，车身透明度还原，鼠标锁回屏幕中间；零件收进对象池——再按住一个零件都不新建；稳着按住的时候不新建、不换组；
--      车长望远镜里按住 X：先收起望远镜、松手回去；车内视角按 X 不响应；开着车辆热成像（Night.lua，1 + 最多 24 个 Highlight）按 X：热成像让开，
--      全场 Highlight 不超过 31 个，松手热成像回来
--   ⑥ 每一型车（VehDefs 全部）算出来：零件 ≤ 600、Highlight ≤ 31、乘员都是人形且在车里、炮管画到炮口、燃气轮机是一节节圆柱；
--      车长的头在指挥塔半径内或者不高过炮塔顶；转盘车炮塔里的人不和弹药、发动机的零件相交（转四个方位）；加特林画转膛机匣；
--      BMP-1 / 2 / 2M、M2A3 画出反坦克导弹发射架
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
pcall(function() io.stdout:setvbuf("line") end)   -- 跑得久：一行一行写出来（重定向到文件时也看得见进度）

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
local UIS = R.services.UserInputService
local VD = R.require(RS:FindFirstChild("VehDefs"))
local W = R.require(RS:FindFirstChild("WtDamage"))
local B = R.require(RS:FindFirstChild("Ballistics"))
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
local function legend() return me.PlayerGui:FindFirstChild("OwnXrayLegend") end
local function allHl()   -- 全场的 Highlight（透视的在 workspace.OwnXray，热成像的在镜头下面）
  local n = 0
  for _, o in ipairs(R.workspace:GetDescendants()) do if o.ClassName == "Highlight" then n = n + 1 end end
  return n
end

-- 车身本来的透明度（松手以后要一模一样）
local v0 = C.views and C.views[em]
local ltm0, nModel = 0, 0
if v0 and v0.model then
  for _, p in ipairs(v0.model:GetDescendants()) do
    if p:IsA("BasePart") then nModel = nModel + 1 ltm0 = ltm0 + p.LocalTransparencyModifier end
  end
end

print("① 按住 X：零件拼的人、按类别分组")
check(UIS.MouseBehavior == Enum.MouseBehavior.LockCenter, "开车时鼠标锁在屏幕中间")
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
check(legend() ~= nil, "屏幕上有图例")
check(UIS.MouseBehavior == Enum.MouseBehavior.Default and UIS.MouseIconEnabled == true, "按住 X：鼠标放开、指针画出来（去指部件）")
do   -- 主循环每一步的计时（G.perfT，半秒清一次）：透视记在 steps 的「xray」下面，不再单独连 RenderStepped（「XrayOwn」）
  local sawX, sawOld = false, false
  for _ = 1, 10 do
    R.run(1 / 30)
    if C.perfT and C.perfT.xray ~= nil then sawX = true end
    if C.perfT and C.perfT.XrayOwn ~= nil then sawOld = true end
  end
  check(sawX and not sawOld, "透视在主循环的 steps 里（View 之后）摆，不单独连 RenderStepped")
end

print("② 弹药按发数、按弹种")
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
do   -- AmL（服务器写的每种弹几发）：第一种打光了，转盘第一格写的换成下一种（原来只在建的时候排一次）
  local aml0 = em:GetAttribute("AmL")
  local list = {}
  for k, n in string.gmatch(tostring(aml0), "([%w_]+):(%d+)") do list[#list + 1] = { k = k, n = tonumber(n) } end
  local k1, k2
  for _, it in ipairs(list) do
    if it.n > 0 then
      if not k1 then k1 = it.k elseif not k2 then k2 = it.k end
    end
  end
  local n1 = C.ownXrayInfo().racks.ammo.names[1]
  print(string.format("  （AmL「%s」；转盘第一格「%s」）", tostring(aml0), tostring(n1)))
  if k1 and k2 then
    check(n1 == (B.AMMO[k1] and B.AMMO[k1].name), "转盘第一格是 AmL 里的第一种弹（" .. tostring(n1) .. "）")
    local bits = {}
    for _, it in ipairs(list) do bits[#bits + 1] = it.k .. ":" .. ((it.k == k1) and 0 or it.n) end
    e.model:SetAttribute("AmL", table.concat(bits, ","))
    R.run(0.2)
    local n2 = C.ownXrayInfo().racks.ammo.names[1]
    check(n2 == (B.AMMO[k2] and B.AMMO[k2].name), "第一种弹打光了：转盘第一格换成下一种（" .. tostring(n2) .. "）")
    e.model:SetAttribute("AmL", aml0)
    R.run(0.2)
    check(C.ownXrayInfo().racks.ammo.names[1] == n1, "补回来又排回去")
  else
    check(false, "AmL 里至少两种弹（" .. tostring(aml0) .. "）")
  end
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
-- 炮塔转过 60° 以上：炮塔里的件（炮长的头）跟着转（审查：原来只测了俯仰，炮塔一直在 0° 上下）
local Pl0 = C.ownXrayPlan(d)
local headT
for _, x in ipairs(Pl0.items) do
  if x.kind == "crew" and x.it.role == "gnr" then
    for _, s in ipairs(x.specs) do if s.sh == "S" then headT = s.cf.Position end end
  end
end
local cy0, ty00 = st.camYaw, st.ty or 0
T.key(Enum.KeyCode.X, false)   -- 按住 X 的时候鼠标不转炮塔：先松开、转好炮塔再按住
R.run(0.2)
st.camYaw = cy0 + math.rad(75)
R.run(3.5)
T.key(Enum.KeyCode.X, true)
R.run(0.4)
do
  local gi = C.ownXrayInfo().items.gnr
  local hpart
  for _, q in ipairs(gi and gi.parts or {}) do if q.p.Shape == Enum.PartType.Ball then hpart = q.p end end
  local got = hpart and hullF():PointToObjectSpace(hpart.Position)
  local exp = headT and W.fromTur(d, headT, st.ty or 0)
  local dd = (got and exp) and (got - exp).Magnitude or 99
  local dty = (((st.ty or 0) - ty00 + 180) % 360) - 180   -- 转角是 0～360 的：按差多少度算
  print(string.format("  （炮塔 %.1f° → %.1f°；炮长的头 透视 %s、按 fromTur 算 %s）", ty00, st.ty or 0, tostring(got), tostring(exp)))
  check(math.abs(dty) > 60, "炮塔转过了 60°（转了 " .. string.format("%.1f", dty) .. "°）")
  check(dd < 0.3, string.format("炮塔转了以后炮长的头还在炮塔系算的地方（差 %.2f 格）", dd))
end
T.key(Enum.KeyCode.X, false)
R.run(0.2)
st.camYaw = cy0
R.run(3.5)
T.key(Enum.KeyCode.X, true)
R.run(0.4)

print("④ 真按住 X、挪鼠标：指着的部件写名字、状态")
local cam = R.workspace.CurrentCamera
check(UIS.MouseBehavior == Enum.MouseBehavior.Default, "按住 X：鼠标没锁")
do   -- 挪鼠标镜头、炮塔不转（鼠标归指部件）
  local yaw0, pitch0, ty0 = st.camYaw, st.camPitch, st.ty
  R.mouseDelta = R.Vector2.new(320, 140)
  R.run(1 / 30)
  R.run(0.3)
  local dty = ((((st.ty or 0) - (ty0 or 0)) + 180) % 360) - 180   -- 转角是 0～360 的
  check(math.abs(st.camYaw - yaw0) < 1e-6 and math.abs(st.camPitch - pitch0) < 1e-6 and math.abs(dty) < 0.5, "按住 X 挪鼠标：镜头、炮塔不跟着转")
end
-- 镜头往下压（第三人称镜头在车后上方：平着看的时候车尾的发动机在画面底边外头）；按住 X 时鼠标不转镜头，测试直接改俯仰
st.camPitch = -0.7
R.run(1.2)
local lg = legend()
local tip = lg and lg:FindFirstChild("Tip")
local function tipText(name) local l = tip and tip:FindFirstChild(name) return l and l.Text or "" end
local function pointAt(p)
  local sp, on = cam:WorldToViewportPoint(p)
  R.mouseAt = R.Vector2.new(sp.X, sp.Y)
  R.run(0.2)
  return sp, on
end
do   -- 发动机：最上面那一件（风扇）——从后上方的镜头看过去前面没别的
  local top
  for _, q in ipairs(C.ownXrayInfo().items.engine.parts) do
    if q.vis and (not top or q.p.Position.Y > top.Position.Y) then top = q.p end
  end
  local sp, on = pointAt(top.Position)
  local ml = UIS:GetMouseLocation()
  print(string.format("  （发动机在屏幕 %.0f, %.0f；鼠标 %.0f, %.0f；旁边写「%s」「%s」「%s」）", sp.X, sp.Y, ml.X, ml.Y, tipText("Name"), tipText("State"), tipText("Info")))
  check(on and math.abs(ml.X - sp.X) < 1 and math.abs(ml.Y - sp.Y) < 1, "鼠标真挪到了发动机上（没锁在屏幕中间）")
  check(tip and tip.Visible and tipText("Name") == "发动机", "鼠标指着发动机：旁边写「发动机」")
  check(string.find(tipText("State"), "完好", 1, true) ~= nil and string.find(tipText("Info"), "柴油机", 1, true) ~= nil, "写「完好」「柴油机」")
  check(C.ownXrayInfo().hover == "engine", "指着的那一件换成高亮那一组")
end
do   -- 炮口那一截
  local g = VD.gunCF(d, hullF(), st.ty, st.gp)
  pointAt(g * V3(0, 0, -d.gun.len * 0.97))
  print(string.format("  （炮口：旁边写「%s」「%s」「%s」）", tipText("Name"), tipText("State"), tipText("Info")))
  check(tipText("Name") == "炮管" and string.find(tipText("State"), "完好", 1, true) ~= nil and string.find(tipText("Info"), "125", 1, true) ~= nil, "鼠标挪到炮口：「炮管」「完好」「125 毫米」")
end
R.mouseAt = R.Vector2.new(6, 6)   -- 画面左上角（远处的地上 / 天上）
R.run(0.2)
check(tip and not tip.Visible and C.ownXrayInfo().hover == nil, "鼠标挪到车外：提示框收起")
R.mouseAt = nil
st.camPitch = -0.12
R.run(0.5)
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
do   -- 换了座：WtC 按乘员的次序写「状态 + 现在的座位」——车长顶上阵亡的炮长：「2drv,0cmd,2gnr」（第二个人阵亡、坐到了车长位上）
  em:SetAttribute("WtC", "2drv,0cmd,2gnr")
  R.run(0.3)
  local ci = C.ownXrayInfo()
  check(ci.items.gnr.ov == nil and ci.items.cmd.ov == "kia", "乘员按座位：炮长位上是活人（原来的车长）、车长位阵亡（按次序读的话反过来）")
  G.wtPush(e)
  R.run(0.3)
  check(C.ownXrayInfo().items.cmd.ov == nil, "换回来：车长位活着")
end
e.model:SetAttribute("WtF", true)
R.run(0.3)
local ei = C.ownXrayInfo().items.engine
check(ei and ei.ov == "fire", "起火：发动机进「起火」那一组（火光色一闪一闪）")
e.model:SetAttribute("WtF", false)
R.run(0.3)
check(C.ownXrayInfo().items.engine.ov == nil, "灭了：发动机回到原来的颜色")

print("⑤ 松手全清、对象池、每帧只改 CFrame；望远镜、车内视角、热成像")
local i3 = C.ownXrayInfo()
local made0, parts0 = i3.stats.made, i3.parts
T.key(Enum.KeyCode.X, false)
R.run(0.3)
local i4 = C.ownXrayInfo()
check(not C.ownXrayOn() and not i4.on, "松开 X：透视关了")
check(R.workspace:FindFirstChild("OwnXray") == nil, "OwnXray 整个删了")
check(legend() == nil, "图例删了")
if v0 and v0.model then
  local ltm1 = 0
  for _, p in ipairs(v0.model:GetDescendants()) do if p:IsA("BasePart") then ltm1 = ltm1 + p.LocalTransparencyModifier end end
  check(math.abs(ltm1 - ltm0) < 0.01, string.format("车身透明度还原（%d 块）", nModel))
end
do
  local ml = UIS:GetMouseLocation()
  check(UIS.MouseBehavior == Enum.MouseBehavior.LockCenter and math.abs(ml.X - 640) < 1 and math.abs(ml.Y - 360) < 1, "松手：鼠标锁回屏幕中间（指针在屏幕中心）")
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
-- 车长望远镜（C）里按住 X：先收起望远镜看车，松手回到望远镜里（原来只退瞄准镜：零件在望远镜镜头底下糊满屏）
R.as("client", function() C.driveBinoc(true) end)
R.run(0.3)
local inBino = st.binoc == true
T.key(Enum.KeyCode.X, true)
R.run(0.4)
check(inBino and C.ownXrayOn() and not st.binoc, "望远镜里按住 X：先收起望远镜、透视打开")
T.key(Enum.KeyCode.X, false)
R.run(0.3)
check(st.binoc == true and not C.ownXrayOn(), "松开 X：回到望远镜里")
R.as("client", function() C.driveBinoc(false) end)
R.run(0.3)
-- 车内视角（Interior）：按 X 不响应（几百个零件围着镜头）
do
  local io0 = C.interiorOn
  C.interiorOn = function() return true end
  T.key(Enum.KeyCode.X, true)
  R.run(0.3)
  local on = C.ownXrayOn()
  T.key(Enum.KeyCode.X, false)
  C.interiorOn = io0
  R.run(0.3)
  check(not on and R.workspace:FindFirstChild("OwnXray") == nil, "车内视角按 X：不响应")
end
-- 车辆热成像（N，Night.lua 的 VehIr：1 + 最多 24 个 Highlight）开着按 X：热成像让开，全场 Highlight 不超过 31 个；松手热成像回来
if C.vehThermal then
  R.as("client", function() C.vehThermal(true) end)
  R.run(0.4)
  local irOn, h0 = C.vehThermalShown and C.vehThermalShown(), allHl()
  T.key(Enum.KeyCode.X, true)
  R.run(0.4)
  local h1 = allHl()
  print(string.format("  （热成像开着 %d 个 Highlight；按住 X 全场 %d 个）", h0, h1))
  check(irOn and C.ownXrayOn() and not C.vehThermalShown() and h1 <= 31, "热成像开着按 X：热成像让开，全场 Highlight " .. h1 .. " 个（上限 31）")
  T.key(Enum.KeyCode.X, false)
  R.run(0.4)
  check(C.vehThermalShown() == true, "松开 X：热成像回来")
  R.as("client", function() C.vehThermal(false) end)
  R.run(0.2)
end

print("⑥ 每一型车")
-- 两个零件（方盒 / 圆柱 / 球都按方盒算，各缩 0.05 格）相交没有：分离轴（全用数字算，模拟器里的 Vector3 每次运算都要新建表，太慢）
local function obb(cf, size, sh)
  local p, r, u, l = cf.Position, cf.RightVector, cf.UpVector, cf.LookVector
  local hx, hy, hz = math.max(size.X / 2 - sh, 0.01), math.max(size.Y / 2 - sh, 0.01), math.max(size.Z / 2 - sh, 0.01)
  return { c = { p.X, p.Y, p.Z }, a = { { r.X, r.Y, r.Z }, { u.X, u.Y, u.Z }, { l.X, l.Y, l.Z } }, h = { hx, hy, hz }, rad = math.sqrt(hx * hx + hy * hy + hz * hz) }
end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function overlap(A, Bx)
  local t = { Bx.c[1] - A.c[1], Bx.c[2] - A.c[2], Bx.c[3] - A.c[3] }
  if dot(t, t) > (A.rad + Bx.rad) ^ 2 then return false end   -- 外接球都碰不到
  local axes = { A.a[1], A.a[2], A.a[3], Bx.a[1], Bx.a[2], Bx.a[3] }
  for i = 1, 3 do
    for j = 1, 3 do
      local p, q = A.a[i], Bx.a[j]
      local cr = { p[2] * q[3] - p[3] * q[2], p[3] * q[1] - p[1] * q[3], p[1] * q[2] - p[2] * q[1] }
      local m = math.sqrt(dot(cr, cr))
      if m > 1e-4 then axes[#axes + 1] = { cr[1] / m, cr[2] / m, cr[3] / m } end
    end
  end
  for _, L in ipairs(axes) do
    local ra = A.h[1] * math.abs(dot(A.a[1], L)) + A.h[2] * math.abs(dot(A.a[2], L)) + A.h[3] * math.abs(dot(A.a[3], L))
    local rb = Bx.h[1] * math.abs(dot(Bx.a[1], L)) + Bx.h[2] * math.abs(dot(Bx.a[2], L)) + Bx.h[3] * math.abs(dot(Bx.a[3], L))
    if math.abs(dot(t, L)) > ra + rb then return false end
  end
  return true
end
local XO = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("XrayOwn"))
local nV, over, hlOver, crewBad, barrelBad, turbBad, carBad = 0, {}, {}, {}, {}, {}, {}
local cupBad, carHit, otherHit, gatBad, atgmBad = {}, {}, {}, {}, {}
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
    local tp = dd.turret and dd.turret.pivot or V3()
    for _, x in ipairs(Pl.items) do
      if x.kind == "crew" then
        local bad = #x.specs < 10
        -- 车体两边、前后；炮塔里的人还可以在炮塔伸出车体的那一块里（CRAM 的炮塔转轴偏在左边，炮塔探出车体）
        local xm, zm = dd.W / 2, dd.L / 2
        if x.it.tur and dd.turret then
          local ts = Pl.lay.ts
          xm, zm = math.max(xm, math.abs(tp.X) + ts.X / 2), math.max(zm, math.abs(tp.Z) + ts.Z / 2)
        end
        for _, s in ipairs(x.specs) do
          local p = s.cf.Position
          if x.it.tur then p = W.fromTur(dd, p, 0) end
          if p.Y < -0.1 or p.Y > dd.H + 0.1 or math.abs(p.X) > xm + 0.1 or math.abs(p.Z) > zm + 0.1 then bad = true end
        end
        if bad then crewBad[#crewBad + 1] = id .. "." .. x.k end
        -- 车长的头：在指挥塔那一圈里面（伸进指挥塔），不然头顶不高过炮塔顶（T-64、T-80 原来从指挥塔旁边的炮塔顶冒出去）
        if x.it.role == "cmd" and x.it.tur and dd.cupola then
          for _, s in ipairs(x.specs) do
            if s.sh == "S" then
              local hp2 = s.cf.Position
              local off = math.sqrt((hp2.X - dd.cupola.X) ^ 2 + (hp2.Z - dd.cupola.Z) ^ 2)
              local topY = Pl.ctx.turTop - tp.Y
              if off > 0.625 + 0.01 and hp2.Y + s.s.X / 2 > topY + 0.05 then
                cupBad[#cupBad + 1] = id .. string.format("(离指挥塔 %.2f、头顶高出 %.2f)", off, hp2.Y + s.s.X / 2 - topY)
              end
            end
          end
        end
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
      elseif x.k == "breech" and dd.gun and dd.gun.gatling then   -- 加特林：转膛机匣（圆柱），不是坦克炮的摇架、防危板
        local s1 = x.specs[1]
        local plates = 0
        for _, s in ipairs(x.specs) do if s.sh == "B" and s.s.X <= 0.07 then plates = plates + 1 end end
        if not s1 or s1.sh ~= "C" or plates > 0 then gatBad[#gatBad + 1] = id end
      end
    end
    -- 反坦克导弹发射架
    local aw
    for _, w in ipairs(dd.weapons or {}) do if XO.ATGM[w] then aw = w break end end
    if aw then
      local found
      for _, x in ipairs(Pl.items) do if x.k == "atgm" then found = x end end
      local slots = 0
      if found then for _, s in ipairs(found.specs) do if s.slot then slots = math.max(slots, s.slot) end end end
      if not found or found.launch.cap ~= XO.ATGM[aw].n or slots ~= XO.ATGM[aw].n then atgmBad[#atgmBad + 1] = id .. "(" .. aw .. ")" end
    end
    -- 乘员零件和弹药 / 发动机的零件相交没有（炮塔转 0 / 45 / 90 / 180°）：转盘车算进检查，别的车只列出来（WtDamage 布局里原来就挤在一起的）
    for _, yaw in ipairs({ 0, 45, 90, 180 }) do
      local function hullCF(x, s)
        if x.frame == "hull" then return s.cf end
        local tf = CF(tp) * R.CFrame.Angles(0, -math.rad(yaw), 0)
        if x.frame == "tur" then return tf * s.cf end
        return tf * CF(dd.gun and dd.gun.pivot or V3()) * s.cf
      end
      local hits = {}
      local Bs = {}   -- 弹药、发动机的零件（这个方位算一次）
      for _, b in ipairs(Pl.items) do
        if (b.cat == "ammo" or b.k == "engine") and b.specs then
          for _, sb in ipairs(b.specs) do Bs[#Bs + 1] = { o = obb(hullCF(b, sb), sb.s, 0.05), k = b.k } end
        end
      end
      for _, a in ipairs(Pl.items) do
        if a.kind == "crew" then
          local got = {}
          for _, sa in ipairs(a.specs) do
            local A = obb(hullCF(a, sa), sa.s, 0.05)
            for _, bq in ipairs(Bs) do
              if not got[bq.k] and overlap(A, bq.o) then got[bq.k] = true hits[#hits + 1] = a.k .. "×" .. bq.k end
            end
          end
        end
      end
      if #hits > 0 then
        local line = id .. "@" .. yaw .. "°(" .. table.concat(hits, ",") .. ")"
        if W.CAROUSEL[id] then carHit[#carHit + 1] = line else otherHit[#otherHit + 1] = line end
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
check(#cupBad == 0, "车长的头在指挥塔那一圈里、或者不高过炮塔顶" .. ((#cupBad > 0) and ("：" .. table.concat(cupBad, "、")) or ""))
check(#carHit == 0, "转盘车（T-64 / 72 / 80 / 90、96、99A）炮塔里的人不和弹药、发动机的零件相交（转四个方位）" .. ((#carHit > 0) and ("：" .. table.concat(carHit, "、")) or ""))
check(#gatBad == 0, "加特林（M163、LD-2000、C-RAM）画转膛机匣，不是坦克炮闩" .. ((#gatBad > 0) and ("：" .. table.concat(gatBad, "、")) or ""))
check(#atgmBad == 0, "BMP-1 / 2 / 2M、M2A3 画出反坦克导弹发射架（一具一发）" .. ((#atgmBad > 0) and ("：" .. table.concat(atgmBad, "、")) or ""))
if #otherHit > 0 then print("  （别的车 WtDamage 布局里原来就挤在一起的，没算进检查：" .. table.concat(otherHit, "、") .. "）") end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
