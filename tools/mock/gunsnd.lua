-- 机枪、机关炮的声音（模拟器）：python3 tools/mock/run.py tools/mock/gunsnd.lua
--   用户 11-28「机枪机炮的音效不太好听」（照战雷；录音见 SoundLib 的 mg762、bmg50，Fx.lua G.gunSnd）：
--   ① 别人的并列机枪（服务器 gun 事件带 s = mg762）：一挺一个循环 Sound——循环录音里整数发的那段、按射速微调速度；边打边走还是同一挺；
--      停了放收尾（同一条录音最后一发起到回声完）；不再放原来那声 lmg；回声完了收回池里
--   ② 别人的 12.7（mg127）：网络一帧挤进来两发也按射速一发一发排开，一发不少；前一发淡掉、最后一发不淡（回声拖完）
--   ③ 别人的机关炮（vfire f = ac，带射速 r、口径 c）：同一辆车接成一串、按口径放慢（30 毫米比 25 毫米低）；车上发导弹不再响机枪声
--   ④ 自己开 BMP-2：空格打并列机枪——本地马上响（me:coax 循环），服务器回来的那一发带 by、客户端跳过（不多一挺）；松开空格马上收尾；
--      左键打 2A42 30 毫米：本地一发一发放（me:ac30），服务器回来的 vfire 带 r、c、不再响
--   ⑤ 慢的航炮（M230）：G.gunLoop 改成按射速一发一发打拍子（别人的 0.25 秒没再收到就停；自己的开到松开），快的（M61）照旧循环
--   ⑥ 录音没载上：照旧放原来那声（不会没声音）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local KEY = "bmp2"
T.fakeImport(KEY)
local me = T.join("P1", 8741, true)
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
local SL = R.require(RS:FindFirstChild("SoundLib"))
local cam = R.workspace.CurrentCamera

-- 服务器发出去的枪炮特效、客户端放的老声音都记下来
local sent = {}
local fx0 = G.fx
G.fx = function(e)
  if e.k == "gun" or e.k == "vfire" then sent[#sent + 1] = e end
  return fx0(e)
end
local played = {}
local ps0 = C.playSound
C.playSound = function(name, pos, sp)
  played[name] = (played[name] or 0) + 1
  return ps0(name, pos, sp)
end
-- 模拟器里没有真的预载：当作录音都载上了（mg762 只给一条，循环点好查）
local REAL = C.realSoundState()
local MG = "rbxassetid://9113185032"
local BMG = {}
for _, id in ipairs(SL.bmg50.ids) do BMG[#BMG + 1] = "rbxassetid://" .. id end
local function loaded()
  REAL.mg762 = { MG }
  REAL.bmg50 = { BMG[1], BMG[2], BMG[3], BMG[4] }
end
loaded()
local function onFx(list) R.as("client", function() C.onFx(list) end) end
local function gunEv(s, a, n)
  local list = {}
  for _ = 1, n or 1 do list[#list + 1] = { k = "gun", w = "lmg", s = s, a = a, b = a + V3(0, 0, -300), t = "atk" } end
  onFx(list)
end
local function find(kind, cls, key)
  for _, g in ipairs(C.gunSndState()) do
    if g.kind == kind and g.cls == cls and (key == nil or g.key == key) then return g end
  end
  return nil
end
local function count(cls)
  local n = 0
  for _, g in ipairs(C.gunSndState()) do if g.cls == cls then n = n + 1 end end
  return n
end

print("① 别人的并列机枪（gun 事件带 s = mg762）：一挺一个循环，停了放收尾")
local cut = SL.mg762.cut[9113185032]
local lmg0 = played.lmg or 0
local A = cam.CFrame.Position + V3(200, 0, 0)
for i = 1, 12 do
  gunEv("mg762", A + V3(i * 0.4, 0, 0))   -- 边打边走（车在开）
  R.run(0.08)
end
local g = find("loop", "mg762")
local v = g and g.voices[1]
check(g ~= nil and g.on and v.Looped and v.SoundId == MG and v.PlaybackRegionsEnabled, "一挺一个循环 Sound，开着（" .. tostring(v and v.SoundId) .. "）")
check(v ~= nil and math.abs(v.LoopRegion.Min - cut.loop[1]) < 1e-4 and math.abs(v.LoopRegion.Max - cut.loop[2]) < 1e-4,
  string.format("循环段是录音里整数发的那段（%.3f–%.3f 秒）", v and v.LoopRegion.Min or -1, v and v.LoopRegion.Max or -1))
check(v ~= nil and math.abs(v.PlaybackSpeed - 750 / 740) < 0.01, string.format("按射速微调：%.3f 倍（并列机枪 750 发 / 分，录音 740）", v and v.PlaybackSpeed or 0))
check(count("mg762") == 1, "边打边走还是同一挺（" .. count("mg762") .. " 个）")
check((played.lmg or 0) == lmg0, "不再放原来那声 lmg（多了 " .. ((played.lmg or 0) - lmg0) .. " 声）")
R.run(0.3)
local tl = g and g.voices[2]
check(g ~= nil and not g.on and g.tails == 1 and not tl.Looped and math.abs(tl.PlaybackRegion.Min - cut.tail) < 1e-4,
  string.format("停了：循环停、放收尾（从 %.3f 秒最后一发起到回声完）", tl and tl.PlaybackRegion.Min or -1))
R.run(4.5)
check(find("loop", "mg762") == nil, "回声完了收回池里")

print("② 别人的 12.7（mg127）：一帧挤进来两发也按射速排开，一发不少；前一发淡掉、最后一发回声拖完")
local B = cam.CFrame.Position + V3(-150, 0, 60)
local times, last, g2 = {}, 0, nil
for _ = 1, 5 do   -- 每 0.22 秒来一批两发（12.7 的射击间隔 0.11 秒）
  gunEv("mg127", B, 2)
  g2 = g2 or find("shot", "mg127")
  for _ = 1, 13 do
    if g2 and g2.shots > last then
      last = g2.shots
      times[#times + 1] = R.clock()
    end
    R.run(1 / 60)
  end
end
local minGap = math.huge
for i = 2, #times do minGap = math.min(minGap, times[i] - times[i - 1]) end
check(g2 ~= nil and g2.shots == 10, "十发一发不少（放了 " .. tostring(g2 and g2.shots) .. " 发）")
check(#times >= 9 and minGap >= 0.085, string.format("按射速排开：两发最近隔 %.3f 秒（射击间隔 0.11，一帧挤两发原来是一下子全响）", minGap))
R.run(0.3)
local li = g2 and g2.i
local others = 0
for k = 1, 4 do if g2 and k ~= li and g2.live[k] then others = others + 1 end end
check(g2 ~= nil and g2.live[li] and g2.fade[li] == nil and others == 0, "前面的几发淡掉停了（还响着的 " .. others .. " 个），最后一发不淡、回声拖完")
check(g2 ~= nil and math.abs(g2.voices[li].PlaybackSpeed - 1) < 0.02 and g2.voices[li].SoundId ~= "", string.format("12.7 原速（%.3f 倍）、.50 真录音", g2 and g2.voices[li].PlaybackSpeed or 0))

print("③ 别人的机关炮（vfire f = ac）：同一辆车接成一串，按口径放慢；车上发导弹不再响机枪声")
local Cp = cam.CFrame.Position + V3(100, 0, -100)
for _ = 1, 3 do
  onFx({ { k = "vfire", p = Cp, d = V3(0, 0, -1), f = "ac", id = "e900", r = 0.3, c = 0.2 } })
  R.run(0.3)
end
onFx({ { k = "vfire", p = Cp + V3(30, 0, 0), d = V3(0, 0, -1), f = "ac", id = "e901", r = 0.3, c = 0.18 } })
R.run(0.05)
local g3, g4 = find("shot", "ac", "ve900:"), find("shot", "ac", "ve901:")
check(g3 ~= nil and g3.shots == 3, "同一辆车三发接成一串（" .. tostring(g3 and g3.shots) .. " 发）")
check(g3 ~= nil and g4 ~= nil and g3.sp < g4.sp and math.abs(g3.sp - C.gunShotTone("ac", 0.2)) < 1e-6,
  string.format("30 毫米比 25 毫米低沉（%.2f / %.2f 倍）", g3 and g3.sp or 0, g4 and g4.sp or 0))
local lmg1 = played.lmg or 0
onFx({ { k = "vfire", p = Cp, d = V3(0, 0, -1), f = "msl", id = "e902" } })
check((played.lmg or 0) == lmg1, "车上发导弹：不再响一声机枪（发射声在新弹出现时放）")

print("④ 自己开 BMP-2：空格并列机枪、左键 2A42——本地马上响，服务器回来的跳过")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
local VD = R.require(RS:FindFirstChild("VehDefs"))
local Map = G.Map
local def = VD.get(KEY)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(0, 0, 0)
local e = G.newVehicle("def", KEY, G.vehBaseAt(def, hp.X + 30, hp.Z, V3(0, 0, -1)))
if me.Character then me.Character:PivotTo(CF(hp.X + 30 + def.W / 2 + 4, Map.height(hp.X + 30, hp.Z) + 3, hp.Z)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.5)
local st = C.drive
check(st ~= nil and P.vehicle == e, "坐上了 BMP-2")
if not st then T.summary() return end
sent = {}
local n0 = #C.gunSndState()
T.key(Enum.KeyCode.Space, true)
R.run(0.8)
local gc = find("loop", "mg762", "me:coax")
check(gc ~= nil and gc.on and gc.own, "按住空格：并列机枪本地循环（me:coax）")
local echo, withBy = 0, 0
for _, ev in ipairs(sent) do
  if ev.k == "gun" then
    echo = echo + 1
    if ev.s == "mg762" and ev.by == me.UserId then withBy = withBy + 1 end
  end
end
check(echo > 0 and withBy == echo, string.format("服务器的机枪事件带 s = mg762、by = 自己（%d / %d 发）", withBy, echo))
check(count("mg762") == 1, "服务器回来的那一发客户端跳过（并列机枪只一挺：" .. count("mg762") .. "）")
T.key(Enum.KeyCode.Space, false)
R.run(1 / 30)
check(gc ~= nil and not gc.on and gc.tails == 1, "松开空格马上收尾（不等超时）")
R.run(1)
sent = {}
for i, w in ipairs(def.weapons) do if w == "ac30" then st.wi = i end end   -- 主武器选 2A42（宿主 Lua 没有 table.find）
T.mouse(true)
R.run(1)
T.mouse(false)
R.run(0.4)
local ga = find("shot", "ac", "me:ac30")
local nv, rc = 0, 0
for _, ev in ipairs(sent) do
  if ev.k == "vfire" then
    nv = nv + 1
    if ev.r == VD.W.ac30.rate and ev.c == VD.W.ac30.cal then rc = rc + 1 end
  end
end
check(ga ~= nil and ga.shots >= 4 and ga.own, "左键 2A42：本地一发一发放（me:ac30，" .. tostring(ga and ga.shots) .. " 发）")
check(nv > 0 and rc == nv, string.format("服务器的 vfire 带射速、口径（%d / %d 发）", rc, nv))
check(find("shot", "ac", "v" .. tostring(e.id) .. ":") == nil, "服务器回来的 vfire 不再响（自己车的不多一串）")
check(ga ~= nil and n0 >= 0 and math.abs(ga.sp - C.gunShotTone("ac", VD.W.ac30.cal)) < 1e-6, string.format("30 毫米按口径放慢（%.2f 倍）", ga and ga.sp or 0))

print("⑤ 慢的航炮（M230）：按射速一发一发打拍子；快的（M61）照旧循环")
local H = cam.CFrame.Position + V3(0, 80, 200)
for _ = 1, 10 do
  R.as("client", function() C.gunLoop("tstHeli", "m230", H, true) end)
  R.run(0.1)
end
local gh = find("shot", "ac", "tstHeli")
local AD = R.require(RS:FindFirstChild("AirDefs"))
local want = 1 / AD.W.m230.rate
check(gh ~= nil and gh.till ~= nil and gh.shots >= 9 and gh.shots <= 12, string.format("一秒打了 %s 发（M230 射速 %.1f 发 / 秒）", tostring(gh and gh.shots), want))
R.run(0.3)   -- 最后一次收到以后 0.25 秒内还接着打
local s1 = gh and gh.shots
R.run(0.6)
check(gh ~= nil and gh.shots == s1, "0.25 秒没再收到就停了（停在 " .. tostring(s1) .. " 发）")
R.as("client", function() C.gunLoop("tstJet", "m61", H, true) end)
check(find("shot", "ac", "tstJet") == nil, "M61（一秒 80 多发）照旧循环声")
R.as("client", function() C.gunLoop("tstJet", nil, nil, false) end)
R.as("client", function() C.gunLoop("me", "m230", nil, true) end)
R.run(0.5)
local gm = find("shot", "ac", "me")
local sm = gm and gm.shots
R.as("client", function() C.gunLoop("me", nil, nil, false) end)
R.run(0.5)
check(gm ~= nil and sm >= 5 and gm.shots == sm and (gm.holder.CFrame.Position - cam.CFrame.Position).Magnitude < 0.01,
  string.format("自己的：按住打到松开（%s 发），声音在耳边", tostring(sm)))

print("⑥ 录音没载上：照旧放原来那声")
REAL.mg762, REAL.bmg50 = nil, nil
local lmg2 = played.lmg or 0
gunEv("mg127", cam.CFrame.Position + V3(50, 0, 50))
onFx({ { k = "vfire", p = cam.CFrame.Position + V3(60, 0, 0), d = V3(0, 0, -1), f = "ac", id = "e903", r = 0.2, c = 0.2 } })
check((played.lmg or 0) == lmg2 + 2, "机枪、机关炮各放了原来那一声（" .. ((played.lmg or 0) - lmg2) .. "）")
loaded()

T.summary()
