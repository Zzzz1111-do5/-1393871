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
local Hd = he("d", "he")
local nH, kH = sum(Hd)
print(string.format("    土上 125 毫米榴弹：%d 颗、%d 层", nH, kH))
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
check(VL.stat.made == made0 and count("ParticleEmitter") == pe0, string.format("扫一串：不新建发射器（多了 %d 个）", count("ParticleEmitter") - pe0))
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
VL.logOn = true
VL.log = {}
killAs(e2, "ammo")
local cook = WD.CAROUSEL[VEH] and WD.cookSecs(e2.id) or 0
R.run(cook + 0.4)
local Lw3 = VL.log
VL.logOn = false
check(st.big == big0 + 1, "殉爆：大火球（样子 " .. tostring(st.last) .. "）")
for _, nm in ipairs({ "wFlash", "wCore", "wFire", "wSoot", "wSpark", "wDust", "wShock" }) do check(has(Lw3, nm), "有 " .. nm) end
local wf = find(Lw3, "wFire")
check(wf and wf.tex == "fire_main" and wf.li == 0 and wf.bright >= 3, "火：fire_main 不受光照、亮度 " .. tostring(wf and wf.bright))
local ws = find(Lw3, "wSoot")
check(ws and ws.tex == "explosion01_smoke_main" and ws.li == 1 and ws.wind, "黑烟：深灰的烟贴图、受光照、跟着风")
local wsp = find(Lw3, "wSpark")
check(wsp and wsp.vp and wsp.tex == "explosion01_implosion_main", "火星：白点拉成线")
local first = 0
for _, x in ipairs(Lw3) do if x.name:sub(1, 1) == "w" and x.name ~= "wPopFlash" and x.name ~= "wPopSpark" and x.name ~= "wPopFire" and x.name ~= "wPopSmoke" and x.name ~= "wCrackle" then first = first + x.n end end
check(first <= 300, "第一秒 ≤ 300 颗（" .. first .. "）")
local big120 = false
for _, a in ipairs(rig:GetChildren()) do
  local pl = a:FindFirstChildOfClass("PointLight")
  if pl and pl.Enabled and pl.Range >= 119 then big120 = true end
end
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
check(C.tossVy and C.tossVy >= 27 and C.tossVy <= 50, string.format("炮塔掀飞：往上 %.1f 格/秒（三档 27～50）", C.tossVy or 0))
local styles = {}
for i = 1, 60 do styles[C.wreckStyleOf({ id = "veh" .. i })] = true end
check(styles.A and styles.B and styles.C, "殉爆三种样子按编号挑（大火球、座圈火柱、连爆）")
-- 碎块全局 ≤ 40
for i = 1, 6 do R.as("client", function() C.wreckChunks(gpos(cx + 20 * i, cz), 14, 1, 12) end) end
local liveC = 0
for _, c in ipairs(C.wreckChunkList()) do if not c.dead and c.p.Parent then liveC = liveC + 1 end end
check(liveC <= 40, "碎块全局最多 40 块（" .. liveC .. "）")

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
print(string.format("    这次一共喷了 %d 次、%d 颗；活着的约 %d 颗；每秒最多新建 %d 个发射器", VL.stat.emits, VL.stat.emitted, VL.live, VL.madeMax))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
