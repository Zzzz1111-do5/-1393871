-- 特效照战雷重做（模拟器）：python3 tools/mock/run.py tools/mock/vfxreal.lua
--   用户 11-27：「光影、炮弹爆炸、机枪打地、坦克爆炸、坦克开炮都要照战雷做」「M3 上要非常丝滑」——模拟器不渲染画面，这里只查逻辑、参数、实例数量：
--   ① 发射器池（VfxLib）：起来了、放在 ClientFx/VfxPool；常用的弹着点层预先建好；闪光灯 8 盏挂在 Attachment 上
--   ② 坦克开炮：白闪、二次焰火球（14～20 格、0.16～0.24 秒、自己发光）、火舌、药粒火星（白点拉成线）、激波圈、推进剂烟、炮口烟团、地面扇形尘幕……
--      近处 ≤ 110 颗、1100 格内 ≤ 45 颗（没有激波圈、砂砾）、2500 格内 ≤ 12 颗、更远白天不画；开镜按视场折算；第二炮不新建发射器、不新建灯
--      有制退器的（自行火炮）才往两边横喷；贴脸开炮烟尘少、小、淡；沙地尘多、石头少、水上是水雾
--   ③ 榴弹打在土上、雪上：各层都有、颜色对（土深褐、雪是脏雪 → 白）、久留尘云 10 秒以上、焦痕 24 块轮着用、60 秒后淡掉；破甲弹、打在车上、穿甲弹打在车上
--   ④ 机枪扫一串地：每发步枪 ≤ 12 颗、12.7 毫米 ≤ 18 颗；雪、冰、石头、水、木头各是各的；远处只一颗尘；不新建发射器
--   ⑤ 打爆一辆车：闪光、火球、火、黑烟、火星、碎块挂恒力（重力 45）、负重轮、殉爆样子按编号；车身的火推亮、黑烟换深灰贴图；炮塔掀飞的速度在三档里
--   ⑥ 全局：所有池里的发射器——发光的不受光照、别的受光照；火的贴图亮度 ≥ 2.5；不用八角星、白方块；发射器总数有上限；碎块全局 ≤ 40
--   11-27 审查之后加的：
--   ① 进局分几帧预建（开炮 k≈1、榴弹 S=1、殉爆、机枪打地）：第一炮、第一发榴弹不现建发射器
--   ② 同一帧在两处喷（两颗白闪）用两处零件；自行火炮仰 45° 时制退器横喷绕炮管自己的「上」转（垂直略往后）
--   ③ 草地上的榴弹土柱、扬尘不减半（dustK 0.9）；长寿命的烟每处爆炸借一处零件、粒子没灭完不挪走，到寿命再还；
--      高炮空炸火星四面八方；炮射导弹、反坦克导弹按破甲画；榴弹灯白天 ≤ 1.5 倍
--   ⑤ 殉爆第一秒所有粒子发射器（Emit + Rate × 时间）加起来 ≤ 350 颗（最费的连爆样子）；只点一盏大灯；服务器那一下大爆炸不重复画；
--      老式扣血判毁的步战车、悍马有爆炸；老残骸、活着的车旁边 30 格内的工事被毁有爆炸；黑烟远近两个发射器换着喷（不改 Size）；
--      碎块满 40 块收最早定住的
--   ⑦ 曳光池（不每发新建零件）；发射器到上限后不返回空（借最近一档或收最久没用的）；火箭弹、导弹的弹种（服务器 Ents.rocketAm）
--   11-27 复核之后加的：
--   ⑤ 殉爆第一秒按连爆炸三下（最多的那种）数；离镜头 5000 / 7000 格的转盘车殉爆车身照样烧、冒黑烟；
--      殉爆炸开那一刻旁边 12 格的步战车被老式判毁，它自己的爆炸照样画（不当重复吞掉）
--   ⑦ 曳光一组 96 根、满了顶离镜头最远的、自己打的单独一组；常喷的发射器按喷稳了以后的量记进全局预算
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8401, true)
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
local VL = C.vfx
local FXF = R.workspace:FindFirstChild("ClientFx")
local hp = cam.CFrame.Position
local function spot(r)
  for k = 0, 35 do
    local a = k / 36 * math.pi * 2
    local x, z = hp.X + math.cos(a) * r, hp.Z + math.sin(a) * r
    if Map.isLand(x, z) and Map.slope(x, z) < 0.2 then return x, z end
  end
  return hp.X + r, hp.Z
end
local function gpos(x, z) return V3(x, Map.height(x, z), z) end
local function rgb(c) return c and string.format("(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "nil" end
local function near(c, r, g, b, tol)
  tol = tol or 0.04
  return c and math.abs(c.R - r / 255) < tol and math.abs(c.G - g / 255) < tol and math.abs(c.B - b / 255) < tol
end
local function count(cls, root)
  local n = 0
  for _, d in ipairs((root or FXF):GetDescendants()) do if d.ClassName == cls then n = n + 1 end end
  return n
end
-- 镜头放到离 p 这么远的地方、朝着它（视场 fov）；然后在客户端跑 f，返回这一下喷了哪几层（VfxLib 的记录）
local function shot(p, dist, f, fov)
  cam.FieldOfView = fov or 70
  cam.CFrame = R.CFrame.lookAt(p + V3(dist * 0.8, dist * 0.25, dist * 0.55), p)
  VL.logOn = true
  VL.log = {}
  R.as("client", f)
  local out = VL.log
  VL.log = {}
  cam.FieldOfView = 70
  return out
end
local function sum(log)
  local n, keys, nk = 0, {}, 0
  for _, x in ipairs(log) do
    n = n + x.n
    if not keys[x.key] then keys[x.key] = true nk = nk + 1 end
  end
  return n, nk
end
local function find(log, name)
  for _, x in ipairs(log) do if x.name == name then return x end end
end
local function has(log, name) return find(log, name) ~= nil end
local function emOf(x) return x and VL.pools[x.key] end

print("① 发射器池、闪光灯池")
check(VL ~= nil and VL.folder and VL.folder.Parent == FXF and VL.folder.Name == "VfxPool", "VfxLib 起来了：发射器的小零件放在 ClientFx/VfxPool（画中画不去克隆）")
check(VL.pools.Imp_spark and VL.pools.Imp_dirt and VL.pools.Imp_flash3, "常用的弹着点层预先建好了（Imp_spark、Imp_dirt、Imp_flash3）")
local rig = VL.folder:FindFirstChild("FlashRig")
local nAtt, nPL = 0, 0
for _, a in ipairs(rig and rig:GetChildren() or {}) do
  if a.ClassName == "Attachment" then
    nAtt = nAtt + 1
    if a:FindFirstChildOfClass("PointLight") then nPL = nPL + 1 end
  end
end
check(nAtt == 8 and nPL == 8, string.format("闪光灯池：%d 个 Attachment、%d 盏点光源（同时最多 8 盏）", nAtt, nPL))
do
T.runUntil(function() return VL.warmLeft() == 0 end, 10)
check(VL.warmLeft() == 0 and VL.stat.warm >= 100, string.format("进局分几帧预建好了（%d 个，一帧 4 个；还剩 %d 个没建）", VL.stat.warm, VL.warmLeft()))
local warmKeys = { "mBall#0", "mFlash#0", "gFan#0d", "gRise#0d", "eBall#0", "eCol#0v", "eCloud#0d", "Imp_grass", "Imp_grassL", "wCore#0", "wCore#-1", "tFire", "kFurrow#4d" }
local missing = {}
for _, k in ipairs(warmKeys) do if not VL.pools[k] then missing[#missing + 1] = k end end
check(#missing == 0, "开炮、榴弹、殉爆、机枪打地常用的层都预建了（没建的：" .. table.concat(missing, ",") .. "）")
check(VL.pools["mFlash#0"] and #VL.pools["mFlash#0"].sites == 2 and VL.pools["kFurrow#4d"] and #VL.pools["kFurrow#4d"].sites == 5,
  "一下要在几处喷的层多建了几处（白闪 2 处、犁沟 5 处）")
end

print("② 坦克开炮")
local bx, bz = spot(70)
local VEH = "t90m"
local def = VD.get(VEH)
local e = G.newVehicle("atk", VEH, G.vehBaseAt(def, bx, bz, V3(0, 0, -1)))
R.run(1.5)
local gp = gpos(bx, bz)
local M = gp + V3(0, 6.5, -12)
local F = V3(0, 0, -1)
local k = C.gunInfo({ id = e.id, f = "tank" })
check(k > 0.95 and k < 1.15, string.format("口径系数按炮管口径（%s：k = %.2f）", VEH, k))
local function fire(dist, extra, fov)
  local ev = { k = "vfire", p = M, d = F, f = "tank", id = e.id }
  for kk, vv in pairs(extra or {}) do ev[kk] = vv end
  return shot(M, dist, function() C.vfire(ev) end, fov)
end
C.fxGroundTest = "d"
local em0 = VL.stat.made
local pl0 = count("PointLight")
local L1 = fire(120)
local n1, k1 = sum(L1)
print(string.format("    近处（120 格）：%d 颗、%d 层", n1, k1))
check(VL.stat.made == em0, "第一炮：要用的层都预建好了，不现建发射器（新建 " .. (VL.stat.made - em0) .. " 个）")
do
local fl1, fl2 = nil, nil
for _, x in ipairs(L1) do if x.name == "mFlash" then if not fl1 then fl1 = x else fl2 = x end end end
check(fl1 and fl2 and fl1.site ~= fl2.site and (fl1.pos - fl2.pos).Magnitude > 1, "同一帧在两处喷的白闪：两处各用自己的零件（不在一帧里把一个零件挪来挪去）")
end
for _, nm in ipairs({ "mFlash", "mBall", "mTongue", "mSpark", "mShock", "mTrail", "mHang", "gFan", "gRise", "gGrit", "gRing" }) do
  check(has(L1, nm), "有 " .. nm)
end
check(not has(L1, "mBrake"), "120 / 125 滑膛炮没有制退器：不往两边横喷")
check(n1 <= 110, "近处 ≤ 110 颗（" .. n1 .. "）")
local ball = find(L1, "mBall")
check(ball and ball.big >= 14 and ball.big <= 20 and ball.li == 0 and ball.bright >= 3 and ball.life[1] >= 0.15 and ball.life[2] <= 0.25,
  string.format("二次焰火球：最大 %.1f 格（比炮塔宽）、%.2f～%.2f 秒、不受光照、亮度 %.1f", ball and ball.big or 0, ball and ball.life[1] or 0, ball and ball.life[2] or 0, ball and ball.bright or 0))
check(ball and near(ball.col, 255, 240, 200), "火球起头白热 " .. rgb(ball and ball.col))
local sp = find(L1, "mSpark")
check(sp and sp.vp and sp.sq and sp.tex == "explosion01_implosion_main", "药粒火星：白点顺着速度拉成线（不是八角星）")
for _, nm in ipairs({ "mTrail", "mHang", "gFan", "gRise" }) do
  local x = find(L1, nm)
  check(x and x.li == 1 and x.wind, nm .. "：受光照、跟着风")
end
local fan = find(L1, "gFan")
local fpe = emOf(fan) and emOf(fan).pe
check(fpe and math.abs(fpe.SpreadAngle.X - 75) < 0.1 and fpe.SpreadAngle.Y <= 6 and fpe.EmissionDirection == R.Enum.NormalId.Front,
  string.format("扇形尘幕：往前左右各 %.0f°、上下 %.0f°", fpe and fpe.SpreadAngle.X or 0, fpe and fpe.SpreadAngle.Y or 0))
check(fpe and fpe.Squash.Keypoints[1].Value < 0, "尘幕又宽又扁（Squash < 0）")
check(fan and near(fan.col, 124, 104, 80), "土地的尘是土色 " .. rgb(fan and fan.col))
local lit, lsh = VL.lightsOn()
check(lit >= 1 and count("PointLight") == pl0, string.format("炮口一闪的光：用池里的灯（亮着 %d 盏），没有新建点光源", lit))
R.run(0.4)
check(select(1, VL.lightsOn()) == 0, "0.14 秒后灯还回池里")
local madeBefore = VL.stat.made
fire(120)
check(VL.stat.made == madeBefore, "再开一炮：不新建发射器（" .. (VL.stat.made - madeBefore) .. " 个）")
-- 地面：沙多、石头少、水上是水雾；草地加草屑
C.fxGroundTest = "n"
local Ln = fire(120)
C.fxGroundTest = "r"
local Lr = fire(120)
C.fxGroundTest = "w"
local Lw = fire(120)
C.fxGroundTest = "v"
local Lv = fire(120)
local function nOf(log, nm) local x = find(log, nm) return x and x.n or 0 end
check(nOf(Ln, "gFan") > nOf(L1, "gFan") and nOf(Lr, "gFan") < nOf(L1, "gFan"), string.format("尘幕：沙 %d 颗 > 土 %d > 石头 %d", nOf(Ln, "gFan"), nOf(L1, "gFan"), nOf(Lr, "gFan")))
check(has(Lw, "gMist") and has(Lw, "gRipple") and not has(Lw, "gFan"), "水上：白色水雾 + 涟漪，没有土")
check(has(Lv, "gGrass"), "草地：加几颗草屑")
C.fxGroundTest = "d"
-- 制退器：自行火炮
local La = fire(120, { f = "arty" })
check(has(La, "mBrake") and nOf(La, "mTrail") > nOf(L1, "mTrail"), "自行火炮（有制退器）：两边横喷、烟多三成")
do
-- 仰 45° 开炮：横喷绕炮管自己的「上」转 ±95°——跟炮管夹角 95°（垂直略往后）、跟炮管的「上」垂直（原来绕世界竖轴：夹角只有 63°、往前上方喷）
local F45 = V3(0, math.sin(math.rad(45)), -math.cos(math.rad(45)))
local L45 = fire(120, { f = "arty", d = F45 })
local bu45 = (V3(0, 1, 0) - F45 * F45.Y).Unit
local okB, nB, angs = true, 0, {}
for _, x in ipairs(L45) do
  if x.name == "mBrake" then
    nB = nB + 1
    local ang = math.deg(math.acos(math.max(-1, math.min(1, x.look:Dot(F45)))))
    angs[#angs + 1] = string.format("%.0f°", ang)
    if math.abs(ang - 95) > 2 or math.abs(x.look:Dot(bu45)) > 0.02 then okB = false end
  end
end
check(nB == 2 and okB, "自行火炮仰 45°：两边横喷跟炮管夹角 95°、垂直于炮管的「上」（" .. table.concat(angs, " / ") .. "）")
end
-- 贴脸（镜头 40 格内）：烟尘少、小、淡
local Lc = fire(25)
local fc = find(Lc, "gFan")
check(fc and fc.var:find("C") and fc.big < (fan and fan.big or 0) and fc.n < nOf(L1, "gFan"), string.format("贴脸开炮：尘幕小一号（%.1f < %.1f 格）、少（%d 颗）", fc and fc.big or 0, fan and fan.big or 0, fc and fc.n or 0))
-- 远近分档
local Lm = fire(700)
local nm_ = sum(Lm)
check(nm_ <= 45 and not has(Lm, "mShock") and not has(Lm, "gGrit") and not has(Lm, "gRing"), "1100 格内：≤ 45 颗（" .. nm_ .. "），没有激波圈、砂砾、冲击圈")
local Lf = fire(1800)
local nf = sum(Lf)
check(nf <= 12 and has(Lf, "mBall"), "2500 格内：只有闪光、火球、几团烟（" .. nf .. " 颗）")
local dk0 = C.dayK
C.dayK = function() return 1 end
local Lff = fire(3200)
check(sum(Lff) == 0, "白天 2500 格外：不画粒子（" .. sum(Lff) .. "）")
C.dayK = function() return 0 end
local Lnight = fire(3200)
check(sum(Lnight) <= 1 and has(Lnight, "mFlash"), "夜里 2500 格外：只闪一下（" .. sum(Lnight) .. " 颗发光的白点）")
C.dayK = dk0
R.run(0.5)
local Lz = fire(3200, nil, 8)
check(sum(Lz) > 45 and has(Lz, "gFan"), "开 8 倍镜看 3200 格外开炮：按看上去的远近画全（" .. sum(Lz) .. " 颗）")
C.fxGroundTest = nil

print("③ 榴弹、破甲弹")
local hx, hz = spot(110)
local hpnt = gpos(hx, hz) + V3(0, 0.3, 0)
local dv = V3(0, -0.35, -1).Unit
local function he(hs, am, dist, s)
  return shot(hpnt, dist or 150, function() C.boom(hpnt, s or (11.5 / 12), "shell", hs, dv, am) end)
end
local sc0 = select(1, VL.scorchLive())
local madeH = VL.stat.made
local Hd = he("d", "he")
local nH, kH = sum(Hd)
print(string.format("    土上 125 毫米榴弹：%d 颗、%d 层", nH, kH))
check(VL.stat.made == madeH, "第一发榴弹：层都预建好了，不现建发射器（新建 " .. (VL.stat.made - madeH) .. " 个）")
for _, nm in ipairs({ "eFlash", "eBall", "eCol", "eSoot", "eClod", "eRing", "eCloud" }) do check(has(Hd, nm), "有 " .. nm) end
check(nH <= 120 and kH <= 9, "≤ 120 颗、≤ 9 层（" .. nH .. " 颗、" .. kH .. " 层）")
local col = find(Hd, "eCol")
check(col and col.col.R < 0.4 and col.li == 1, "土柱起头深褐（土块色）、受光照 " .. rgb(col and col.col))
local soot = find(Hd, "eSoot")
check(soot and soot.tex == "explosion01_smoke_main", "黑烟用深灰的烟贴图")
local cl = find(Hd, "eCloud")
check(cl and cl.life[1] >= 10 and cl.wind, string.format("久留尘云：%.0f～%.0f 秒、顺风飘", cl and cl.life[1] or 0, cl and cl.life[2] or 0))
local eb = find(Hd, "eBall")
check(eb and eb.li == 0 and eb.bright >= 3 and eb.big >= 10 and eb.big <= 14, string.format("火球自己发光（亮度 %.1f）、最大 %.1f 格", eb and eb.bright or 0, eb and eb.big or 0))
local ecl = find(Hd, "eClod")
check(ecl and ecl.vp and ecl.tex == "explosion01_implosion_main" and ecl.li == 1, "土块：白点染色、顺着飞的方向拉成线、受光照")
check(select(1, VL.scorchLive()) == sc0 + 1, "弹坑焦痕一块")
local Hi = he("i", "he")
local ci = find(Hi, "eCol")
check(ci and near(ci.col, 120, 112, 104), "雪上：脏雪土柱（起头 120,112,104）" .. rgb(ci and ci.col))
local ri = find(Hi, "eRing")
check(ri and ri.col.R > 0.9 and has(Hi, "eIce") and find(Hi, "eRing").n > find(Hd, "eRing").n, "雪上：白色粉雪扬尘圈更多、冰晶")
local dirty = false
for _, x in ipairs(Hi) do if x.name == "eClod" and x.var == "iD" then dirty = true end end
check(dirty, "雪上：三成是脏雪块")
local Hn = he("n", "he")
check(find(Hn, "eCloud") and find(Hn, "eCloud").life[1] >= 14, "沙上：尘云留 14～20 秒")
do
-- 草地（钢城郊外、公园、训练场最常见的地面，审查 4）：爆炸的尘量 0.9，不再减半
R.run(0.3)
local function nOf3(log, nm) local x = find(log, nm) return x and x.n or 0 end
local Hv = he("v", "he")
local cvN, cdN = nOf3(Hv, "eCol"), nOf3(Hd, "eCol")
local rvN, rdN = nOf3(Hv, "eRing"), nOf3(Hd, "eRing")
print(string.format("    草地榴弹：土柱 %d 颗（土地 %d）、扬尘圈 %d 颗（土地 %d）", cvN, cdN, rvN, rdN))
check(cvN >= cdN * 0.85 and rvN >= rdN * 0.85 and has(Hv, "eCloud") and has(Hv, "eClod"), "草地上的榴弹：土柱、扬尘圈不少于土地的八成五，有尘云、土块")
check(find(Hv, "eCol") and near(find(Hv, "eCol").col, 74 * 0.7 + 120 * 0.3, 86 * 0.7 + 110 * 0.3, 50 * 0.7 + 86 * 0.3, 0.06), "草地的土柱起头是草皮土块色 " .. rgb(find(Hv, "eCol") and find(Hv, "eCol").col))
-- 白天的榴弹灯（审查 6）：最多亮 1.5 倍（10 → 15），不再 ×2.5
local dk1 = C.dayK
C.dayK = function() return 1 end
R.run(0.5)
he("d", "he")
local dayB = 0
for _, a in ipairs(rig:GetChildren()) do
  local pl = a:FindFirstChildOfClass("PointLight")
  if pl and pl.Enabled and pl.Brightness > dayB then dayB = pl.Brightness end
end
check(dayB > 0 and dayB <= 15.01, string.format("白天的榴弹灯最多亮 1.5 倍（%.1f ≤ 15）", dayB))
C.dayK = dk1
R.run(0.5)
-- 长寿命的烟（eSoot 3.5～6 秒）：每处爆炸借一处零件，粒子没灭完不挪走（审查 3c），到寿命再还
local pA, pB = hpnt + V3(-160, 0, 40), hpnt + V3(160, 0, -40)
local LA = shot(pA, 150, function() C.boom(pA, 11.5 / 12, "shell", "d", dv, "he") end)
local LB = shot(pB, 150, function() C.boom(pB, 11.5 / 12, "shell", "d", dv, "he") end)
local sA, sB = find(LA, "eSoot"), find(LB, "eSoot")
check(sA and sB and sA.long and sA.site ~= sB.site and (sA.site.Position - pA).Magnitude < 12,
  string.format("两处爆炸的黑烟各在自己的零件上：第二处没把第一处的挪走（第一处的零件离落点 %.1f 格）", sA and (sA.site.Position - pA).Magnitude or -1))
local cloudA = find(LA, "eCloud")
check(cloudA and cloudA.long and (cloudA.site.Position - pA).Magnitude < 12, "久留尘云也是一处一个零件")
local soKey = sA and sA.key
local nSoot = soKey and #VL.pools[soKey].sites or 0
R.run(7)
local pC = hpnt + V3(0, 0, 220)
local LCc = shot(pC, 150, function() C.boom(pC, 11.5 / 12, "shell", "d", dv, "he") end)
local sC = find(LCc, "eSoot")
check(sC and #VL.pools[soKey].sites == nSoot, string.format("到寿命了：那一处还回池里，再炸不多借（黑烟这一层 %d 处）", soKey and #VL.pools[soKey].sites or -1))
-- 高炮空炸：火星往四面八方（不是上半锥），审查 9
local skyP = hpnt + V3(0, 260, 0)
local Lfk = shot(skyP, 150, function() C.boom(skyP, 0.7, "flak") end)
local fk = find(Lfk, "eSparkA")
check(fk and fk.spread and fk.spread.X >= 179 and fk.spread.Y >= 179 and not has(Lfk, "eSpark"),
  string.format("高炮空炸：火星四面八方（散开角 %.0f° × %.0f°）", fk and fk.spread.X or -1, fk and fk.spread.Y or -1))
-- 炮射导弹、反坦克导弹（服务器给 am = atgm，审查 10）：按破甲画；车载反坦克导弹（杀伤半径 4、服务器不给类别）不再画成航炮弹那一小团火
local Lat = shot(hpnt, 150, function() C.boom(hpnt, 4 / 12, nil, "d", dv, "atgm") end)
local fat = find(Lat, "eFlash")
check(has(Lat, "eJet") and has(Lat, "eGrey") and fat and fat.var == "H" and not has(Lat, "acFlash") and not has(Lat, "eSoot"),
  "反坦克导弹（atgm）：破甲弹那一套（白尖的闪、射流、灰烟），不是航炮弹的一小团火")
local Lrf = shot(hpnt, 150, function() C.boom(hpnt, 0.5, "shell", "d", dv, "atgm") end)
check(has(Lrf, "eJet") and has(Lrf, "eGrey") and not has(Lrf, "eSoot"), "炮射导弹（9M119M，类别 shell、弹种 atgm）：按破甲画")
end
local Hh = he("d", "heat")
local nHh = sum(Hh)
check(has(Hh, "eJet") and has(Hh, "eGrey") and not has(Hh, "eSoot") and nHh <= 80, "破甲弹：射流白光、灰烟（不是黑的）、≤ 80 颗（" .. nHh .. "）")
local fh = find(Hh, "eFlash")
check(fh and fh.var == "H" and fh.bright >= 8, "破甲弹的闪光更白更亮")
local scA = select(1, VL.scorchLive())
local Hm = he("a", "he")
check(has(Hm, "eMetal") and not has(Hm, "eCol") and not has(Hm, "eClod") and not has(Hm, "eRing") and not has(Hm, "eCloud"), "榴弹打在车上：金属火星，没有土柱、土块、扬尘、尘云")
check(select(1, VL.scorchLive()) == scA, "打在车上不留弹坑")
local Hap = he("a", "ap")
check(#Hap == 0, "穿甲弹打在钢甲上不画爆炸（spark 那边画火花）")
-- 久留尘云同时最多 8 团
local nCloud = 0
for i = 1, 12 do
  local L = shot(hpnt, 150, function() C.boom(hpnt + V3(i * 30, 0, 0), 11.5 / 12, "shell", "d", dv, "he") end)
  if has(L, "eCloud") then nCloud = nCloud + 1 end
end
check(nCloud <= 8, "一下子 12 发：久留尘云最多 8 团（" .. nCloud .. "）")
-- 焦痕池
for i = 1, 30 do shot(hpnt, 150, function() C.boom(hpnt + V3(0, 0, i * 25), 11.5 / 12, "shell", "d", dv, "he") end) end
local liveS, poolS = VL.scorchLive()
check(poolS <= 24 and liveS <= 24, string.format("焦痕池 24 块轮着用（建了 %d 块、亮着 %d 块）", poolS, liveS))
check(VL.SCORCH_HOLD == 60 and VL.SCORCH_FADE == 10, "焦痕留 60 秒、再 10 秒淡掉")
VL.SCORCH_HOLD, VL.SCORCH_FADE = 2, 1.5   -- 模拟器里跑 70 秒太慢：缩短了试淡掉的那段
R.run(4)
check(select(1, VL.scorchLive()) == 0, "到时候都淡掉了（还亮着 " .. select(1, VL.scorchLive()) .. " 块）")
VL.SCORCH_HOLD, VL.SCORCH_FADE = 60, 10
-- 远处降级
local Hfar = he("d", "he", 1800)
check(sum(Hfar) <= 15 and not has(Hfar, "eClod"), "2500 格内：只画闪光、火球、几团烟（" .. sum(Hfar) .. " 颗）")
local Hmid = he("d", "he", 700)
check(sum(Hmid) < nH and not has(Hmid, "eClod"), "1100 格内：减半、没有土块（" .. sum(Hmid) .. " 颗）")

print("④ 机枪扫一串地")
local ix, iz = spot(90)
local ip = gpos(ix, iz)
local du = V3(0.2, -0.45, -1).Unit
local function mg(hs, kk, dist)
  return shot(ip, dist or 60, function() C.impact(ip, du, hs, kk or 1, V3(0, 1, 0)) end)
end
R.run(2)   -- 每秒最多 40 处：先攒够
local Ld = mg("d")
local nd = sum(Ld)
check(has(Ld, "Imp_dirt") and has(Ld, "Imp_chips") and nd <= 12, "步枪打土：一股土 + 深色碎渣，≤ 12 颗（" .. nd .. "）")
local Lh = mg("d", 1.7)
check(has(Lh, "Imp_dirt") and find(Lh, "Imp_dirt").key == "Imp_dirtL" and sum(Lh) <= 18, "12.7 毫米：大一号的那套、≤ 18 颗（" .. sum(Lh) .. "）")
check(find(Lh, "Imp_dirt").big > find(Ld, "Imp_dirt").big * 1.3, "12.7 毫米的尘大 1.35 倍")
local Ls = mg("i")
check(has(Ls, "Imp_snow") and has(Ls, "Imp_snowGlint") and not has(Ls, "Imp_chips") and near(find(Ls, "Imp_snow").col, 238, 242, 248), "雪：白色粉雪 + 冰晶，没有深色碎渣")
local nIceSpark = 0
for _ = 1, 10 do
  R.run(0.05)
  if has(mg("j"), "Imp_spark") then nIceSpark = nIceSpark + 1 end
end
check(nIceSpark == 0, "冰：不迸火星")
check(has(mg("j"), "Imp_iceChips"), "冰：冰屑")
local Lg = mg("v")
check(has(Lg, "Imp_grass") and has(Lg, "Imp_grassBits"), "草地：淡一点的尘 + 草屑")
local Lo = mg("o")
check(has(Lo, "Imp_splinter") and find(Lo, "Imp_splinter").vp, "木头：木屑（拉成细条）")
local rockSpark = 0
for _ = 1, 12 do
  R.run(0.05)
  local L = mg("r")
  if has(L, "Imp_spark") then rockSpark = rockSpark + 1 end
end
check(rockSpark >= 2 and rockSpark <= 11, "石头：大约一半迸火星（12 发里 " .. rockSpark .. " 发）")
local Lw2 = mg("w", 1, 60)
check(has(Lw2, "Imp_spout") and has(Lw2, "Imp_ripple"), "水：细水柱 + 近处一圈涟漪")
local Lfar = mg("d", 1, 400)
check(sum(Lfar) == 1, "250 格外：只一颗尘（" .. sum(Lfar) .. "）")
-- 扫一串：每秒最多 40 处、不新建发射器（先扫一遍把要用的层建好，过一秒再扫一遍数）
local function sweep()
  cam.CFrame = R.CFrame.lookAt(ip + V3(30, 20, 30), ip)
  R.as("client", function()
    for i = 1, 120 do C.impact(ip + V3(i * 0.8, 0, 0), du, (i % 3 == 0) and "n" or "d", (i % 5 == 0) and 1.7 or 1, V3(0, 1, 0)) end
  end)
end
sweep()
R.run(1.2)
local made0, pe0 = VL.stat.made, count("ParticleEmitter")
local hits = 0
VL.logOn = true
VL.log = {}
sweep()
for _, x in ipairs(VL.log) do if x.name == "Imp_dirt" or x.name == "Imp_sand" then hits = hits + 1 end end
VL.logOn = false
check(hits <= 41, "一下子 120 发：每秒最多 40 处（画了 " .. hits .. " 处）")
do
-- 同一帧要在几十处喷：每层最多借 6 处零件（审查 3b），不新建层
local maxSites, newPE = 0, count("ParticleEmitter") - pe0
for key, ent in pairs(VL.pools) do if key:sub(1, 4) == "Imp_" and #ent.sites > maxSites then maxSites = #ent.sites end end
check(newPE == VL.stat.made - made0 and maxSites <= 6, string.format("扫一串：不新建层，同一帧在几十处喷的每层最多 6 处零件（多了 %d 处，最多的一层 %d 处）", newPE, maxSites))
R.run(1.2)
sweep()
R.run(1.2)
local made1 = VL.stat.made
sweep()
check(VL.stat.made - made1 <= 2, "再扫两串以后：基本不再新建（新建 " .. (VL.stat.made - made1) .. " 个）")
end
check(VL.liveImp <= VL.IMP_MAX, "同时活着的弹着点粒子 ≤ 600（" .. VL.liveImp .. "）")

print("⑤ 打爆一辆车")
local function killAs(ent, why)
  ent.model:SetAttribute("WtWhy", why)
  ent.wtWhy = why
  G.wtRaw = true
  G.damageEnt(ent, 1e9, nil)
  G.wtRaw = false
end
local WD = R.require(R.services.ReplicatedStorage:FindFirstChild("WtDamage"))
local cx, cz = spot(60)
local e2 = G.newVehicle("atk", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(1.5)
local st = C.wreckStat
local big0, wh0 = st.big, st.wheels
cam.CFrame = R.CFrame.lookAt(gpos(cx, cz) + V3(40, 25, 40), gpos(cx, cz))
local function viewOf(ent)
  for em2, vv in pairs(C.views or {}) do if em2 == ent.model then return vv end end
end
local v2 = viewOf(e2)
-- 殉爆第一秒所有粒子发射器一共喷了多少（审查 5：池里的 + 掀炮塔的 + 碎块拖的火和烟 + 舱口火柱 + 炮塔身上的火和烟 + 车身大火）：
--   模拟器数 ClientFx 下面和这辆车的样子下面所有 ParticleEmitter 的 Emit 颗数、开着的 Rate × 时间；样子用最费的「连爆」、炸三下（最多的那种）
C.wreckStyleOverride = "C"
C.wreckBlastsOverride = 3
R.peCount = { emit = 0, rate = 0, roots = { FXF, v2 and v2.model } }
VL.logOn = true
VL.log = {}
killAs(e2, "ammo")
local cook = WD.CAROUSEL[VEH] and WD.cookSecs(e2.id) or 0
local base1, t1, bigLights, srvSkip, big120 = nil, nil, -1, nil, false
local prevE, prevR = 0, 0
for _ = 1, math.ceil((cook + 4) * 30) do
  R.run(1 / 30, 1 / 30)
  if not base1 and st.big > big0 then
    base1, t1 = { prevE, prevR }, R.clock()
    bigLights = 0
    for _, a in ipairs(rig:GetChildren()) do
      local pl = a:FindFirstChildOfClass("PointLight")
      if pl and pl.Enabled and pl.Range >= 60 then bigLights = bigLights + 1 end
      if pl and pl.Enabled and pl.Range >= 119 then big120 = true end
    end
    -- 服务器殉爆那一下的大爆炸（Wt.lua 发的 c = "wreck"、s 4.6）同一刻到：客户端只出声、震屏（火球 WreckFx 画了）
    local nb = #VL.log
    R.as("client", function() C.boom(v2.hullF.Position + V3(0, 3, 0), 4.6, "wreck") end)
    srvSkip = true
    for i = nb + 1, #VL.log do if VL.log[i].name == "eBall" or VL.log[i].name == "eFlash" then srvSkip = false end end
  end
  if base1 and R.clock() - t1 >= 1 then break end
  prevE, prevR = R.peCount.emit, R.peCount.rate
end
local pcE, pcR = base1 and (R.peCount.emit - base1[1]) or -1, base1 and (R.peCount.rate - base1[2]) or -1
R.peCount = nil
C.wreckStyleOverride = nil
C.wreckBlastsOverride = nil
R.run(0.4)
local Lw3 = VL.log
VL.logOn = false
print(string.format("    殉爆第一秒（连爆）：Emit %d 颗 + 常喷的 %.0f 颗 = %.0f 颗", pcE, pcR, pcE + pcR))
check(base1 ~= nil and pcE + pcR <= 350, string.format("殉爆第一秒所有发射器加起来 ≤ 350 颗（%.0f）", pcE + pcR))
check(bigLights == 1, "殉爆只点一盏大灯（Range ≥ 60 的亮着 " .. bigLights .. " 盏）")
check(srvSkip == true, "服务器殉爆那一下的大爆炸（c = wreck）：火球交给 WreckFx，不重复画")
check(st.toss >= 1 and has(Lw3, "tFire") and has(Lw3, "tSpark"), "掀炮塔的火柱、火星走池（tFire、tSpark）")
check(st.big == big0 + 1, "殉爆：大火球（样子 " .. tostring(st.last) .. "，测试强制最费的连爆）")
for _, nm in ipairs({ "wFlash", "wCore", "wFire", "wSoot", "wSpark", "wDust", "wShock" }) do check(has(Lw3, nm), "有 " .. nm) end
local wf = find(Lw3, "wFire")
check(wf and wf.tex == "fire_main" and wf.li == 0 and wf.bright >= 3, "火：fire_main 不受光照、亮度 " .. tostring(wf and wf.bright))
local ws = find(Lw3, "wSoot")
check(ws and ws.tex == "explosion01_smoke_main" and ws.li == 1 and ws.wind, "黑烟：深灰的烟贴图、受光照、跟着风")
local wsp = find(Lw3, "wSpark")
check(wsp and wsp.vp and wsp.tex == "explosion01_implosion_main", "火星：白点拉成线")
local first = 0
for _, x in ipairs(Lw3) do if x.name:sub(1, 1) == "w" and x.name ~= "wPopFlash" and x.name ~= "wPopSpark" and x.name ~= "wPopFire" and x.name ~= "wPopSmoke" and x.name ~= "wCrackle" then first = first + x.n end end
check(first <= 300, "池里的殉爆几层（不算接连殉爆）≤ 300 颗（" .. first .. "）")
check(big120, "殉爆的大灯 Range 120")
local nForce, okForce = 0, true
for _, c in ipairs(C.wreckChunkList()) do
  local vf = c.p:FindFirstChildOfClass("VectorForce")
  if vf then
    nForce = nForce + 1
    local s = c.p.Size
    local m = 7.8 * s.X * s.Y * s.Z * (c.p:IsA("WedgePart") and 0.5 or 1)
    if math.abs(vf.Force.Y - m * (196.2 - 45)) > m * 2 then okForce = false end
  end
end
check(nForce >= 6 and okForce, "碎块挂恒力：重力降到 45 格/秒²（" .. nForce .. " 块）")
check(st.wheels > wh0, "履带车甩出负重轮（" .. (st.wheels - wh0) .. " 个）")
local v2
for em2, vv in pairs(C.views or {}) do if em2 == e2.model then v2 = vv end end
local Mv = v2 and v2.M
check(Mv and Mv.black and Mv.black.Texture:find("explosion01_smoke_main") and Mv.black.LightInfluence == 1, "残骸的黑烟：深灰的烟贴图、受光照")
check(Mv and Mv.fire and Mv.fire.LightInfluence == 0 and Mv.fire.Brightness >= 3, "残骸的火：推亮")
do
-- 镜头走近残骸：换成小一号的那根黑烟（两个发射器换着喷，审查 7），Size 曲线不动（已经在飘的不会一起缩放）
local bF, bN = Mv and Mv.black, Mv and Mv.blackN
local sizeF0 = bF and bF.Size
local rate0 = bF and bF.Rate or 0
cam.CFrame = R.CFrame.lookAt(gpos(cx, cz) + V3(20, 12, 20), gpos(cx, cz))
R.run(1.2)
local nearOk = bF and bN and bN.Rate > 0 and bF.Rate == 0 and bF.Size == sizeF0 and math.abs(bN.Rate - rate0) < 0.01
check(nearOk, string.format("走近残骸：换成小一号那根黑烟（远 %.1f / 近 %.1f 颗每秒），Size 不改", bF and bF.Rate or -1, bN and bN.Rate or -1))
check(bN and bN.Size.Keypoints[#bN.Size.Keypoints].Value < bF.Size.Keypoints[#bF.Size.Keypoints].Value, "近处那根小一号")
cam.CFrame = R.CFrame.lookAt(gpos(cx, cz) + V3(80, 40, 80), gpos(cx, cz))
R.run(1.2)
check(bF and bN and bF.Rate > 0 and bN.Rate == 0 and bF.Size == sizeF0, "走远了：换回远处那根")
cam.CFrame = R.CFrame.lookAt(gpos(cx, cz) + V3(40, 25, 40), gpos(cx, cz))
end
check(C.tossVy and C.tossVy >= 27 and C.tossVy <= 50, string.format("炮塔掀飞：往上 %.1f 格/秒（三档 27～50）", C.tossVy or 0))
local styles = {}
for i = 1, 60 do styles[C.wreckStyleOf({ id = "veh" .. i })] = true end
check(styles.A and styles.B and styles.C, "殉爆三种样子按编号挑（大火球、座圈火柱、连爆）")
do
-- 碎块全局 ≤ 40（审查 15c：两条路都走到）——先「没有定住的：新的不收」，再「满了收最早定住的」
local function liveChunks()
  local n = 0
  for _, c in ipairs(C.wreckChunkList()) do if not c.dead and c.p.Parent then n = n + 1 end end
  return n
end
local function settle(pred)   -- 模拟器没有物理：摆到地上、速度清零（落地、4 秒后定住）
  for _, c in ipairs(C.wreckChunkList()) do
    if not c.dead and c.p.Parent and not c.land and pred(c) then
      local pos = c.p.Position
      c.p.CFrame = CF(pos.X, math.max(Map.height(pos.X, pos.Z), 0) + 1, pos.Z)
      c.p.AssemblyLinearVelocity = V3(0, 0, 0)
    end
  end
end
for i = 1, 4 do R.as("client", function() C.wreckChunks(gpos(cx + 20 * i, cz), 14, 1, 12) end) end
local liveC = liveChunks()
check(liveC <= 40, "碎块全局最多 40 块：还没定住的，新的不收（" .. liveC .. "）")
settle(function(c) return c.owner ~= nil end)   -- 先让残骸那几块落地定住
R.run(0.6)
R.run(2)
settle(function() return true end)              -- 两秒后别的也落地
R.run(0.6)
R.run(4.6)
local restT = {}
local nRest, nOwnRest = 0, 0
for _, c in ipairs(C.wreckChunkList()) do
  if not c.dead and c.p.Parent and c.rest then
    nRest = nRest + 1
    restT[c] = c.rest
    if c.owner then nOwnRest = nOwnRest + 1 end
  end
end
check(nRest >= 30 and nOwnRest >= 6, string.format("都定住了（%d 块，跟着残骸的 %d 块）", nRest, nOwnRest))
local kill0 = st.capKill or 0
R.as("client", function() C.wreckChunks(gpos(cx - 40, cz + 30), 14, 1, 12) end)
local killed, maxKilled, minLeft = 0, -1, math.huge
for c, t in pairs(restT) do
  if c.dead or not c.p.Parent then
    killed = killed + 1
    if t > maxKilled then maxKilled = t end
  elseif t < minLeft then minLeft = t end
end
local liveC2 = liveChunks()
check(liveC2 <= 40 and (st.capKill or 0) > kill0 and killed >= 6 and maxKilled <= minLeft,
  string.format("满了收最早定住的：收了 %d 块（都是最早定住的那批），新炸出来的收进来，全局 %d 块", killed, liveC2))

-- 老式扣血判毁（Tech.lua 回机库判毁、Ents.lua wtGeneric 出错回落：没有 WtWhy）的步战车、悍马：有爆炸（审查 1；原来只剩一缕烟）
--   服务器这一下发两个 c = "wreck"（Ents.lua 一个、Armor.lua 的 onDeath 一个）：只画一个
local function legacyKill(id, x, z)
  local d2 = VD.get(id)
  local e3 = G.newVehicle("atk", id, G.vehBaseAt(d2, x, z, V3(0, 0, -1)))
  R.run(1.5)
  cam.CFrame = R.CFrame.lookAt(gpos(x, z) + V3(40, 25, 40), gpos(x, z))
  VL.logOn = true
  VL.log = {}
  local toss0 = C.tossCount or 0
  G.wtRaw = true
  G.damageEnt(e3, (e3.hp or 0) + 1e6, nil)
  G.wtRaw = nil
  -- 大灯（Range ≥ 60）同时亮几盏：复核——别的车老式判毁掀炮塔时 View 原来还点一盏 Range 70 的，跟服务器那一下（boom）Range 120 的同时亮
  local bigL = 0
  for _ = 1, 6 do
    R.run(1 / 30, 1 / 30)
    local n = 0
    for _, a in ipairs(rig:GetChildren()) do
      local pl = a:FindFirstChildOfClass("PointLight")
      if pl and pl.Enabled and pl.Range >= 60 then n = n + 1 end
    end
    if n > bigL then bigL = n end
  end
  R.run(1.0)
  local out = VL.log
  VL.logOn = false
  return out, e3, bigL, (C.tossCount or 0) - toss0
end
local lx, lz = spot(140)
for _, id in ipairs({ "bmp2", "hmmwv" }) do
  local Ll, _, bigL, tossed = legacyKill(id, lx, lz)
  local nFl = 0
  for _, x in ipairs(Ll) do if x.name == "eFlash" then nFl = nFl + 1 end end
  check(has(Ll, "eBall") and nFl == 1 and bigL == 1,
    string.format("老式扣血判毁的 %s：有爆炸（火球），服务器的两个 wreck 只画一个（白闪 %d 次），大灯只亮一盏（%d 盏；掀炮塔 %d 次）", id, nFl, bigL, tossed))
  lx = lx + 45
end
local Lt = legacyKill(VEH, lx + 30, lz)
check(has(Lt, "wCore") and not has(Lt, "eBall"), "老式判毁的坦克：WreckFx 画殉爆，服务器那一下不重复画火球")
-- 车旁 30 格内的工事被毁：旁边是老残骸（这辆车二十多秒前殉爆的）、旁边是活着的车，都有爆炸
local function fortKill(x, z)
  local y = Map.height(x, z)
  local f = G.newEnt({ kind = "sandbag", team = "atk", cat = "fort", hp = 100, size = V3(6, 4, 6), cf = CF(x, y + 2, z) })
  R.run(0.3)
  cam.CFrame = R.CFrame.lookAt(V3(x, y, z) + V3(40, 25, 40), V3(x, y, z))
  VL.logOn = true
  VL.log = {}
  G.damageEnt(f, 1e6, nil)
  R.run(0.5)
  local out = VL.log
  VL.logOn = false
  return out
end
local wp = v2.hullF.Position
local Lf1 = fortKill(wp.X + 14, wp.Z + 8)
check(C.ownCookOff and not C.ownCookOff(wp, 30), "二十多秒前的老残骸：不再算「这一次的殉爆」")
check(has(Lf1, "eBall"), "老残骸旁边 30 格内的工事被毁：有爆炸")
local ep = e.root.CFrame.Position
local Lf2 = fortKill(ep.X + 16, ep.Z - 6)
check(has(Lf2, "eBall"), "活着的车旁边 30 格内的工事被毁：有爆炸")

-- 复核（特效 1）：离镜头 4000 格外的转盘车殉爆——wreckCook 不接手，车身照别的残骸马上烧起来（原来残骸 40 秒不冒黑烟，6000 格外连火也没有）
local function blackOf(Mx) return (Mx.black and Mx.black.Rate or 0) + (Mx.blackN and Mx.blackN.Rate or 0) end
for _, far in ipairs({ 5000, 7000 }) do
  local fx, fz = spot(far / 10 - 180)   -- 320 / 520 格外（离前面几辆车、残骸远一点）
  local ef = G.newVehicle("atk", VEH, G.vehBaseAt(def, fx, fz, V3(0, 0, -1)))
  R.run(1.5)
  local vf = viewOf(ef)
  cam.CFrame = R.CFrame.lookAt(gpos(fx, fz) + V3(far, 300, 0), gpos(fx, fz))
  killAs(ef, "ammo")
  R.run(0.5)
  local Mf = vf and vf.M
  local f0, b0 = Mf and Mf.fire.Rate or -1, Mf and blackOf(Mf) or -1
  R.run((WD.CAROUSEL[VEH] and WD.cookSecs(ef.id) or 0) + 1.5)
  local f1, b1 = Mf and Mf.fire.Rate or -1, Mf and blackOf(Mf) or -1
  check(Mf and vf.cookT and not vf.cookJets and f0 > 0 and b0 > 0 and f1 > 0 and b1 > 0,
    string.format("离镜头 %d 格的转盘车殉爆：先烧那几秒火 %.0f / 黑烟 %.0f，炸开以后火 %.0f / 黑烟 %.0f（都有）", far, f0, b0, f1, b1))
end
cam.CFrame = R.CFrame.lookAt(gpos(cx, cz) + V3(40, 25, 40), gpos(cx, cz))

-- 复核（wreckDup）：殉爆炸开那一刻旁边 12 格的步战车被老式判毁——它自己那一下照样画（原来殉爆那一下先登记了位置，0.6 秒内 15 格内的当重复吞掉；
--   ownCookOff 也只认离这一下最近的那辆车）
do
  local ax, az = spot(420)
  local ea = G.newVehicle("atk", VEH, G.vehBaseAt(def, ax, az, V3(0, 0, -1)))
  local eb = G.newVehicle("atk", "bmp2", G.vehBaseAt(VD.get("bmp2"), ax + 12, az, V3(0, 0, -1)))
  R.run(1.5)
  cam.CFrame = R.CFrame.lookAt(gpos(ax, az) + V3(50, 30, 50), gpos(ax, az))
  local big1 = st.big
  killAs(ea, "ammo")
  local tA = nil
  for _ = 1, 150 do
    R.run(1 / 30, 1 / 30)
    if st.big > big1 then tA = R.clock() break end
  end
  VL.logOn = true
  VL.log = {}
  R.as("client", function() C.boom(viewOf(ea).hullF.Position + V3(0, 3, 0), 4.6, "wreck") end)   -- 服务器殉爆那一下（同一刻到）
  G.wtRaw = true
  G.damageEnt(eb, (eb.hp or 0) + 1e6, nil)   -- 旁边的步战车老式判毁：服务器发它自己的 c = "wreck"
  G.wtRaw = nil
  R.run(0.4)
  local bp = eb.root.CFrame.Position
  local nearB = false
  for _, x in ipairs(VL.log) do if x.name == "eBall" and (x.pos - bp).Magnitude < 10 then nearB = true end end
  VL.logOn = false
  check(tA ~= nil and nearB, "殉爆那一刻旁边 12 格的步战车被老式判毁：它自己的爆炸照样画（不当成殉爆那一下的重复）")
end
end

print("⑥ 全局")
local bad, badTex, dim, nPE = {}, {}, {}, 0
for key, ent in pairs(VL.pools) do
  local pe = ent.pe
  nPE = nPE + 1
  local glow = pe.LightEmission > 0.5
  if (glow and pe.LightInfluence ~= 0) or (not glow and pe.LightInfluence ~= 1) then bad[#bad + 1] = key end
  if pe.Texture:find("sparkles_main") or pe.Texture:find("SquareParticle") or not pe.Texture:find("^rbxasset://textures/particles/") then badTex[#badTex + 1] = key end
  if pe.Texture:find("fire_main") and pe.Brightness < 2.5 then dim[#dim + 1] = key end
end
check(#bad == 0, "发光的层不受光照、别的层受光照（不对的：" .. table.concat(bad, ",") .. "）")
check(#badTex == 0, "只用自带的粒子贴图、不用八角星和白方块（不对的：" .. table.concat(badTex, ",") .. "）")
check(#dim == 0, "火的贴图亮度 ≥ 2.5（不对的：" .. table.concat(dim, ",") .. "）")
local nEm, nH = VL.count()
check(nEm <= 420 and nH >= nEm, string.format("池里一共 %d 个发射器（上限 420）、%d 个小零件", nEm, nH))
print(string.format("    这次一共喷了 %d 次、%d 颗；活着的约 %.0f 颗；每秒最多新建 %d 个发射器（预建的 %d 个不算）；%d 处零件、借最早到期的 %d 次",
  VL.stat.emits, VL.stat.emitted, VL.live, VL.madeMax, VL.stat.warm, VL.stat.sites, VL.stat.stolen))

do
print("⑦ 曳光池、发射器上限、火箭弹导弹的弹种")
-- 曳光（审查 14）：每发不再新建 Neon 零件 + 补间——池里的零件轮着用，每帧挪；飞到了藏回地底下
local function tracers()
  local n = 0
  for _, c in ipairs(FXF:GetChildren()) do if c.Name == "Tracer" then n = n + 1 end end
  return n
end
local ta = gpos(hx, hz) + V3(0, 3, 0)
cam.CFrame = R.CFrame.lookAt(ta + V3(-20, 6, 0), ta + V3(0, 0, -200))
local tr0 = tracers()
local function burst()
  R.as("client", function()
    for i = 1, 10 do C.gunFx("m4", ta, ta + V3(i * 2, 0, -600), false, nil, false) end
  end)
end
burst()
R.run(0.05)
local tr1 = tracers()
local _, _, act = C.tracerPool()
local midOk = false
for _, r in ipairs(act) do if r.p.Position.Y > -100 and (r.p.Position - ta).Magnitude > 5 then midOk = true end end
check(tr1 - tr0 >= 1 and tr1 - tr0 <= 10 and midOk, string.format("曳光：池里的零件（%d 根）、每帧往前挪", tr1 - tr0))
R.run(1.2)
local parked = 0
for _, c in ipairs(FXF:GetChildren()) do if c.Name == "Tracer" and c.Position.Y < -1000 then parked = parked + 1 end end
check(parked == tr1 and #act == 0, string.format("飞到了藏回地底下、还回池里（%d / %d 根）", parked, tr1))
burst()
R.run(0.05)
check(tracers() == tr1, "第二梭子：一根新零件都不建（" .. (tracers() - tr1) .. "）")
R.run(1.2)
do
-- 复核（特效 3）：一组最多 96 根（原来 32：别人车上的并列机枪、大机枪、工事、步兵机枪都挤在 lmg 一组，三挺就满了，快飞到的那根半路没了）；
--   自己打的单独一组（lmg_me），不被别人的顶掉；满了顶离镜头最远的那根
local _, trN2, act2, cap0 = C.tracerPool()
local function live(key, maxD)
  local n = 0
  for _, r in ipairs(act2) do if r.key == key and (not maxD or (r.p0 - cam.CFrame.Position).Magnitude < maxD) then n = n + 1 end end
  return n
end
R.as("client", function()
  for i = 1, 10 do C.gunFx("lmg", ta, ta + V3(i * 2, 0, -600), true, nil, false) end                              -- 自己打的 10 发
  for i = 1, 70 do C.gunFx("lmg", ta + V3(0, 0, -700), ta + V3(i, 0, -1300), false, nil, false) end            -- 别人的：700 格外打过来 70 发
  for i = 1, 60 do C.gunFx("lmg", ta + V3(0, 0, -5), ta + V3(i, 0, -600), false, nil, false) end               -- 别人的：镜头跟前打 60 发
end)
local nMe, nAll, nNear = live("lmg_me"), live("lmg"), live("lmg", 100)
check(cap0 >= 96 and nMe == 10 and nAll == math.min(130, cap0) and nNear == 60 and trN2.lmg <= cap0,
  string.format("曳光一组最多 %d 根：别人的 130 发在飞 %d 根（镜头跟前那 60 根都在，顶掉的是 700 格外的）；自己打的 10 发单独一组、一根没被顶掉（%d 根）",
    cap0, nAll, nMe))
R.run(1.5)
end
do
-- 复核（特效 2）：常喷的发射器（碎块拖的火和烟、舱口火柱……）记进全局预算按喷稳了以后同时活着的量（原来把这几秒要喷的全记成「现在活着」：
--   8 颗 / 秒喷 4 秒、每颗活 0.5 秒的一下记 34 颗，真活着的 4 颗；一次殉爆记九百多颗，两三辆车接连殉爆就提前砍火星）
local VfxLib = R.require(R.services.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("VfxLib"))
local f2 = R.Instance.new("Folder")
f2.Parent = R.workspace
local L2 = VfxLib.new({}, f2)
L2.rateK(8, 4, 0.5, 2)
local a1 = L2.live
L2.rateK(4, 11, 2.6, 2)
local a2 = L2.live
R.run(5)
L2.rateK(0, 0, 0)
local a3 = L2.live
f2:Destroy()
check(math.abs(a1 - 4) < 0.01 and math.abs(a2 - 14.4) < 0.01 and math.abs(a3 - 10.4) < 0.01,
  string.format("常喷的记进全局预算：8 颗/秒 × 活 0.5 秒记 %.1f 颗（真活着 4）、再加 4 颗/秒 × 活 2.6 秒共 %.1f（14.4）；5 秒后头一个喷完、灭完了剩 %.1f（10.4）", a1, a2, a3))
end
-- 发射器到上限（审查 11）：没建过的层不返回空——借同一层最近的一档，再不行收最久没用的那一层
local nNow = select(1, VL.count())
VL.MAX_EM = nNow + 1
VL.def("zTest", function(sz) return { tex = VL.TX.SMOKE, life = { 0.5, 1 }, spd = { 1, 2 }, size = VL.ns(0, sz, 1, sz * 2), tr = VL.ns(0, 0.5, 1, 1), col = VL.cs(R.Color3.fromRGB(200, 200, 200)) } end)
VL.def("zTest2", function(sz) return { tex = VL.TX.SMOKE, life = { 0.5, 1 }, spd = { 1, 2 }, size = VL.ns(0, sz, 1, sz * 2), tr = VL.ns(0, 0.5, 1, 1), col = VL.cs(R.Color3.fromRGB(120, 120, 120)) } end)
local okAll, rec0, bor0 = true, VL.stat.recycled, VL.stat.borrowed
R.as("client", function()
  for i, sz in ipairs({ 1, 1.2, 4, 9, 0.3 }) do
    if not VL.emit("zTest", sz, CF(ta + V3(i * 3, 0, 0)), 2) then okAll = false end
    if not VL.emit("zTest2", sz, CF(ta + V3(i * 3, 3, 0)), 2) then okAll = false end
  end
end)
local nAfter = select(1, VL.count())
check(okAll and nAfter <= VL.MAX_EM and VL.stat.recycled > rec0 and VL.stat.borrowed > bor0,
  string.format("到上限以后照样画：借最近一档 %d 次、收最久没用的 %d 次（发射器 %d / 上限 %d）", VL.stat.borrowed - bor0, VL.stat.recycled - rec0, nAfter, VL.MAX_EM))
VL.MAX_EM = 420
-- 服务器：火箭弹、导弹的爆炸带上弹种（Ents.rocketAm）
local VW = VD.W
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local refW = G.tankWeaponOf and select(1, G.tankWeaponOf("gun125u", VW.gun125u or VW.gun125, "refleks"))
local am = {
  tow2 = G.rocketAm({ w = VW.tow2 }), kornet = G.rocketAm({ w = VW.kornet }), refleks = refW and G.rocketAm({ w = refW }),
  rpg = G.rocketAm({ w = G.Config.Weapons and G.Config.Weapons.rpg or { kind = "proj" } }), hellfire = G.rocketAm({ w = AD.W.agm114 }),
  kh29 = G.rocketAm({ w = AD.W.kh29 }), hydra = G.rocketAm({ w = AD.W.hydra }), shell = G.rocketAm({ cls = "he", w = VW.gun125 }),
}
local amS = {}
for _, k2 in ipairs({ "refleks", "tow2", "kornet", "rpg", "hellfire", "kh29", "hydra", "shell" }) do amS[#amS + 1] = k2 .. "=" .. tostring(am[k2]) end
check(am.tow2 == "atgm" and am.kornet == "atgm" and (refW == nil or am.refleks == "atgm") and am.rpg == "heat" and am.hellfire == "heat"
  and am.kh29 == nil and am.hydra == nil and am.shell == "he", "火箭弹、导弹的弹种：" .. table.concat(amS, " "))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
