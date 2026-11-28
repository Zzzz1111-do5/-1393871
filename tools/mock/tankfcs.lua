-- 坦克炮的真实弹道和火控（模拟器）：python3 tools/mock/run.py tools/mock/tankfcs.lua [veh=m1a2]
--   用户 11-22 晚（钢铁猛兽 M1A2 热像截图：M830 HEAT-T、1790 米，曳光弹在左上方）：「开镜开炮炮弹从左上方落下去，符合真实物理学和火控系统」
--   ① 弹道模型：真实初速、重力、阻力（解析解和逐步积分对得上）
--   ② 坐上 M1A2、开主瞄准镜，瞄准一两公里外的一辆敌坦克（找一条看得见的线）；R 激光测距：测出来的距离对
--   ③ 测了距开炮（穿甲弹）：打中；曳光弹在镜里先在左边、升到瞄准线上方，最后落到分划中心（从左上方落下去）
--   ④ Q 换破甲弹（M830 HEAT-MP-T）：服务器打出去是 1140 米 / 秒，测距再打：照样打中，弹道更弯（中间更高）
--   ⑤ 不测距（战斗瞄准距离 1200 米）打远处这辆：打低（落在车前面）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m1a2"

local MAPID = TEST_ARGS:match("map=(%w+)")   -- map=sands：沙漠图（平，一两公里看得见的线多）
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
local me
if MAPID then   -- 先进人、选图（同 sands.lua）
  me = T.join("P1", 8101, true)
  R.run(4)
  R.as("client", function() T.C.menuPlay() end)
  R.run(0.3)
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do if d.Name == "Map_" .. MAPID then T.press(d) break end end
  R.run(0.5)
end
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
me = me or T.join("P1", 8101, true)
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
T.actAs(me, "deploy", "rifle", "base")   -- 11-28：「camp」现在的默认图上没有（人没出生、上不了车），同 ammofire 用两边的基地
R.run(1.5)
local RS = R.services.ReplicatedStorage
local VD = R.require(RS:FindFirstChild("VehDefs"))
local BAL = R.require(RS:FindFirstChild("Ballistics"))
local Map = G.Map
local cam = R.workspace.CurrentCamera
local S = BAL.S

print("① 弹道模型")
do
  local a = BAL.AMMO.m829a3
  local t, drop, v = BAL.flight(a, 2000)
  check(v > 1420 and v < 1470, string.format("M829A3 飞 2 公里还剩 %.0f 米 / 秒（每公里掉约 55 米 / 秒）", v))
  check(t > 1.25 and t < 1.40 and drop > 8 and drop < 10, string.format("2 公里飞 %.2f 秒、下坠 %.1f 米", t, drop))
  -- 逐步积分（同 Ents.lua：半隐式欧拉，1 / 60 秒）和解析解对得上
  local v0, k, gs = BAL.launchArgs(a)
  local GR = R.workspace.Gravity * 0.55 * gs
  local p, vel, tt = V3(0, 0, 0), V3(v0, 0, 0), 0
  while p.X < 2000 * S and tt < 5 do
    vel = vel + V3(0, -GR, 0) * (1 / 60)
    vel = vel - vel * math.min(0.5, k * vel.Magnitude * (1 / 60))
    p = p + vel * (1 / 60)
    tt = tt + 1 / 60
  end
  check(math.abs(-p.Y / S - drop) < 0.6 and math.abs(tt - t) < 0.03, string.format("逐步积分：%.2f 秒、下坠 %.1f 米（解析 %.2f 秒、%.1f 米）", tt, -p.Y / S, t, drop))
  local h = BAL.AMMO.m830
  local th, dh = BAL.flight(h, 1790)
  check(th > 1.6 and th < 1.8 and dh > 13 and dh < 17, string.format("M830 破甲弹打 1790 米：飞 %.2f 秒、下坠 %.1f 米（截图里那一发）", th, dh))
end

print("② 坐上 " .. VEH .. "、开镜、对准一两公里外的敌坦克、激光测距")
local def = VD.get(VEH)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
-- 找一块平地放自己的车，再找一两公里外一块平地放靶车，中间看得见（地形、东西都不挡）
local function flatAt(x, z) return Map.isLand(x, z) and Map.height(x, z) > 2 and Map.slope(x, z) < 0.25 end
local function losClear(a, b)
  local d = b - a
  local n = math.floor(d.Magnitude / 20)
  for i = 1, n - 1 do
    local p = a + d * (i / n)
    if Map.height(p.X, p.Z) > p.Y - 1.0 then return false end
  end
  return R.workspace:Raycast(a, d * 0.97) == nil
end
local pick
for _, rr in ipairs({ 18, 30, 60, 120, 300, 600, 1000 }) do
  for k = 0, 35 do
    local a0 = k / 36 * math.pi * 2
    local x, z = hp.X + math.cos(a0) * rr, hp.Z + math.sin(a0) * rr
    if flatAt(x, z) then
      local eye = V3(x, Map.height(x, z) + 7.8, z)
      for _, dm in ipairs({ 1790, 1600, 1400, 1200, 1000, 800 }) do
        for j = 0, 71 do
          local b = j / 72 * math.pi * 2
          local tx, tz = x + math.cos(b) * dm * S, z + math.sin(b) * dm * S
          if flatAt(tx, tz) then
            local tgt = V3(tx, Map.height(tx, tz) + 3.5, tz)
            if losClear(eye, tgt) then pick = { x = x, z = z, tx = tx, tz = tz, dm = dm } break end
          end
        end
        if pick then break end
      end
    end
    if pick then break end
  end
  if pick then break end
end
check(pick ~= nil, pick and string.format("找到一条看得见的线：%d 米", pick.dm) or "没找到看得见的线")
if not pick then T.summary() return end
local toT = V3(pick.tx - pick.x, 0, pick.tz - pick.z).Unit
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, pick.x, pick.z, toT))
local tdef = VD.get("ztz99a")
local side = V3(-toT.Z, 0, toT.X)   -- 靶车横着停（侧面对着我）
local tgt = G.newVehicle("atk", "ztz99a", G.vehBaseAt(tdef, pick.tx, pick.tz, side))
R.run(0.5)
-- 人走到车旁边再上车（车可能放在离营地几百格的平地上）
local hrp2 = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
if hrp2 then hrp2.CFrame = CF(pick.x + 9, Map.height(pick.x + 9, pick.z) + 3, pick.z) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
if not C.drive then T.summary() return end
T.runUntil(function() return G.round.phase == "battle" end, 60)
local st = C.drive
R.as("client", function() C.driveSetSight(true) end)
R.run(0.5)
check(st.sight == true, "开了主瞄准镜")
-- 瞄准线对着靶车车身中间（靶车的 Root 往上一点）
local function aimAt(p)
  local eye = cam.CFrame.Position
  local d = (p - eye).Unit
  st.camYaw = math.atan2(-d.X, -d.Z)
  st.camPitch = math.asin(d.Y)
end
local tc = tgt.root.CFrame.Position + V3(0, 0.6, 0)
for _ = 1, 6 do aimAt(tc) R.run(0.5) end
local trueR = (tc - cam.CFrame.Position).Magnitude / S
R.as("client", function() C.driveLase() end)
R.run(0.1)
check(st.fcs.R ~= nil and math.abs(st.fcs.R - trueR) < 12, string.format("激光测距 %s 米（实际 %.0f 米）", tostring(st.fcs.R), trueR))
for _ = 1, 8 do aimAt(tc) R.run(0.4) end   -- 等炮塔、炮到位（超高角）
check(#T.texts(string.format("%04d", st.fcs.R or 0)) > 0 and #T.texts(BAL.AMMO[st.fcs.am].sym) > 0,
  string.format("镜下沿显示测的距离 %04d、弹种 %s", st.fcs.R or 0, BAL.AMMO[st.fcs.am].sym))
local se = st.fcsSE or 0
check(se > 0.0015 and se < 0.012, string.format("超高角 %.2f 密位（%.3f°）", se * 1000, math.deg(se)))

-- 记曳光弹在镜里的路线：开炮那一刻的瞄准线为准，横向 x（右正）、纵向 y（上正），弧度
local track, fireCF = {}, nil
C.onTankShot = function(ev, fs)   -- 开炮那一刻的瞄准线（不算镜头后坐的晃动）
  track = { fs = fs, pts = {} }
  local eye = st.fcsAim and st.fcsAim.eye or cam.CFrame.Position
  fireCF = CF(eye) * R.CFrame.Angles(0, st.camYaw, 0) * R.CFrame.Angles(st.camPitch, 0, 0)
end
local function sample()
  if track.fs and fireCF then
    local q = fireCF:PointToObjectSpace(track.fs.p)
    if q.Z < -1 then table.insert(track.pts, { x = q.X / -q.Z, y = q.Y / -q.Z, d = -q.Z / S }) end
  end
end
local lastShell = nil   -- 打出去的这一发（服务器 G.launch 那一刻记下：打中了它就从 G.shots 里收走了，事后翻不到）
do
  local launch0 = G.launch
  G.launch = function(sh, ...)
    local r = launch0(sh, ...)
    if type(sh) == "table" and sh.kind == "shell" then lastShell = r or sh end
    return r
  end
end
local function shoot(wantAmmo)
  local hp0 = tgt.hp
  local nShots = #G.shots
  lastShell = nil
  R.as("client", function() C.driveTryFire() end)
  R.run(1 / 60)
  local s = lastShell or G.shots[#G.shots]
  local v0 = s and s.vel and s.vel.Magnitude / S or 0
  for _ = 1, 260 do
    R.run(1 / 60)
    sample()
    if tgt.hp < hp0 then break end
  end
  R.run(0.3)
  return tgt.hp < hp0, v0, nShots
end
local pathDump = TEST_ARGS:match("dump=(%S+)")   -- 把镜里看到的曳光弹路线写成 JSON（画图看）
local dumped = {}
local function report(tag)
  local pts = track.pts
  if pathDump then
    local L = {}
    for _, q in ipairs(pts) do L[#L + 1] = string.format("[%.5f,%.5f,%.1f]", q.x * 1000, q.y * 1000, q.d) end
    dumped[#dumped + 1] = string.format('{"tag":"%s","am":"%s","R":%.0f,"pts":[%s]}', tag, tostring(st.fcs.am), trueR, table.concat(L, ","))
    local f = io.open(pathDump, "w")
    f:write("[" .. table.concat(dumped, ",") .. "]")
    f:close()
  end
  if #pts < 6 then check(false, tag .. "：镜里记到的点太少（" .. #pts .. "）") return end
  local early, mid, last = nil, nil, pts[#pts]
  for _, q in ipairs(pts) do
    if not early and q.d > trueR * 0.15 then early = q end
    if not mid and q.d > trueR * 0.5 then mid = q end
  end
  early, mid = early or pts[2], mid or pts[math.floor(#pts / 2)]
  check(early.x < -0.0003, string.format("%s：前段在瞄准线左边（%.2f 密位）——炮在瞄准镜左边", tag, early.x * 1000))
  check(mid.y > 0.0001, string.format("%s：中段高过瞄准线（%.2f 密位，约 %.1f 米）", tag, mid.y * 1000, mid.y * mid.d))
  check(math.abs(last.x) < 0.0012 and math.abs(last.y) < 0.0015, string.format("%s：最后落到分划中心附近（%.2f, %.2f 密位）", tag, last.x * 1000, last.y * 1000))
  return mid.y
end

print("③ 测了距开炮（穿甲弹）")
tgt.hp = 1e6   -- 靶车打不坏（几发都打同一辆）
check(st.fcs.am == BAL.GUN.gun120[1] or VEH ~= "m1a2", "默认弹种 " .. tostring(st.fcs.am))
local hit, v0 = shoot()
-- 钢针（用户 11-28「钢针打出去的效果跟尾烟要有区别」）：M829A3 打出去炮口外面弹托三瓣飞开、弹芯细（不冒烟）
local sab = lastShell and lastShell.sab
check(sab == "fs", "服务器认得这是钢针（尾翼稳定脱壳穿甲弹，sab = " .. tostring(sab) .. "）")
check(C.fxSabotSeen ~= nil and C.fxSabotSeen >= 3, "炮口外面弹托三瓣飞开（" .. tostring(C.fxSabotSeen) .. " 瓣）")
-- 用户 11-28「然后钢针打出去的尾烟也改成战雷那样的」：后面拖一道细的淡白烟线（Trail），不是导弹那样一团团的烟
check(C.fxDartTrails ~= nil and C.fxDartTrails >= 1, "钢针后面拖一道细的淡白尾迹（" .. tostring(C.fxDartTrails) .. " 条）")
check(math.abs(v0 - BAL.AMMO[st.fcs.am].v0) < 30, string.format("服务器打出去 %.0f 米 / 秒（%s 初速 %d）", v0, BAL.AMMO[st.fcs.am].name, BAL.AMMO[st.fcs.am].v0))
check(hit, "打中了靶车（剩 " .. math.floor(tgt.hp) .. "）")
local midAp = report("穿甲弹")

print("④ Q 换破甲弹（M830），测距再打")
T.tap(Enum.KeyCode.Q)
R.run(0.1)
check(st.fcs.am == "m830", "Q 换成 " .. tostring(st.fcs.am))
for _ = 1, 17 do aimAt(tc) R.run(0.4) end   -- 换了弹种要重新装填（6 秒多）
R.as("client", function() C.driveLase() end)
for _ = 1, 6 do aimAt(tc) R.run(0.4) end
local hit2, v2 = shoot()
check(math.abs(v2 - 1140) < 30, string.format("破甲弹出膛 %.0f 米 / 秒（M830 真实 1140）", v2))
check(hit2, "破甲弹也打中了")
local midHeat = report("破甲弹")
if midAp and midHeat then check(midHeat > midAp * 1.4, string.format("破甲弹弹道更弯：中段比瞄准线高 %.2f 密位（穿甲弹 %.2f）", midHeat * 1000, midAp * 1000)) end

print("⑤ 不测距（战斗瞄准距离）打远处")
for _ = 1, 6 do   -- 换回穿甲弹（Q 一下下轮着换：多用途、高爆多用途、金属射流弹……，换到为止）
  if st.fcs.am == "m829a3" then break end
  T.tap(Enum.KeyCode.Q)
  R.run(0.05)
end
check(st.fcs.am == "m829a3", "又换回 " .. tostring(st.fcs.am))
st.fcs.R, st.fcs.laseT = nil, nil
for _ = 1, 17 do aimAt(tc) R.run(0.4) end
local hpB = tgt.hp
local hit3 = shoot()
local pts = track.pts
local lastB = pts[#pts]
if trueR > 1450 then
  check(not hit3 and lastB and lastB.y < 0, string.format("战斗瞄准距离 %d 米打 %.0f 米：打低了（%.2f 密位）", BAL.AMMO[st.fcs.am].bs, trueR, lastB and lastB.y * 1000 or 0))
else
  check(true, "靶车不够远（" .. math.floor(trueR) .. " 米），战斗瞄准距离照样打得中")
end
check(tgt.hp <= hpB, "（剩 " .. math.floor(tgt.hp) .. "）")
print("⑥ SEPv2 的第四种弹：M1028 霰弹（没有弹药数据链，没有 AMP）")
for _ = 1, 7 do   -- Q 一下下轮着换到霰弹为止（穿甲 → 破甲 → 多用途 → 霰弹 → 金属射流弹……，弹种表加过新弹）
  if st.fcs.am == "m1028" then break end
  T.tap(Enum.KeyCode.Q)
  R.run(0.05)
end
check(st.fcs.am == "m1028", "Q 换到 " .. tostring(st.fcs.am))
for _ = 1, 17 do aimAt(tc) R.run(0.4) end
local nb, ns0 = 0, #G.shots
local bs0 = G.botShot
G.botShot = function(...) nb = nb + 1 return bs0(...) end
R.as("client", function() C.driveTryFire() end)
R.run(0.2)
G.botShot = bs0
check(nb == BAL.AMMO.m1028.pellets and #G.shots == ns0, string.format("霰弹打出去一锥 %d 道弹丸，没有飞炮弹（%d 发）", nb, #G.shots - ns0))
check(#R.errors == 0, "全程没有报错：" .. table.concat(R.errors, " | "))
T.summary()
