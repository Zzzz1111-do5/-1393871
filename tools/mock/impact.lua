-- 弹着点（用户：枪打在坦克上有没有火花，做一些）：python3 tools/mock/run.py tools/mock/impact.lua
--   ① 服务器发的枪响特效带上「打在什么上面」：坦克 a、地面 d / n / r、海面 w、打到天上没有
--   ② 客户端：别人打在坦克上——火花发射器挪到弹着点、叮的一声；打在土上——土发射器、闷的一下；打到天上什么都不出
--   ③ 自己开的枪（不带 h）：本地探出打中的是坦克，照样出火花
--   ④ 炮弹直接打在坦克上：服务器发 spark，客户端一大团（大闪光那个发射器）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF = T.R, T.V3, T.CF
local check = T.check

print("① 开服、两个人进来、开战")
local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local p1 = T.join("P1", 4101, true)
local p2 = T.join("P2", 4102, false)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then
  C.menuEnter()
  R.run(0.5)
end
local P1, P2 = G.P[p1], G.P[p2]
local function spawnOf(P) return (P.team == "atk") and "fleet" or "camp" end
T.actAsRemote(p1, "deploy", "rifle", spawnOf(P1))
T.actAsRemote(p2, "deploy", "rifle", spawnOf(P2))
R.run(1)
T.runUntil(function() return G.round.phase == "battle" end, G.Config.Round.prep + 5)
check(P1.alive and G.round.phase == "battle", "开战了")

-- 场地：攻方机场岛的跑道上（平地、旁边没有房子），P1 站在西边 120 格，敌方坦克停在这儿
local A2 = G.Map.AFIELD2
local tx, tz = A2.x + 600, A2.z
local gy = G.airSurface(tx, tz)
local tank = G.spawnGroundVeh(P2.team, "m1a2", CF(tx, gy, tz) * R.CFrame.Angles(0, math.pi / 2, 0), false, nil)
check(tank ~= nil and tank.cat == "armor", "放了一辆敌方 M1A2（类别 " .. tostring(tank and tank.cat) .. "）")
local stand = V3(tx - 120, gy + 3.5, tz)
p1.Character.HumanoidRootPart.CFrame = CF(stand)
p1.Character.Head.CFrame = CF(stand + V3(0, 1.5, 0))
R.run(0.5)
local cam = R.workspace.CurrentCamera
print("  镜头离坦克 " .. math.floor((cam.CFrame.Position - tank.root.CFrame.Position).Magnitude) .. " 格")
-- 模拟器里镜头不一定跟着人：摆到 P1 身后（弹着点按离镜头远近决定画不画）
local function camHere() cam.CFrame = R.CFrame.lookAt(stand + V3(-10, 6, 0), tank.root.CFrame.Position) end
camHere()

-- 服务器发出去的特效记下来
local sent = {}
local fx0 = G.fx
G.fx = function(e)
  if e.k == "gun" or e.k == "spark" then sent[#sent + 1] = e end
  return fx0(e)
end
-- 客户端的音效记下来
local sounds = {}
local sfx0 = C.sfx
C.sfx = function(def, pos, o)
  if type(def) == "string" then sounds[#sounds + 1] = def end
  return sfx0(def, pos, o)
end
local ws = R.workspace
local function holder(name) return ws:FindFirstChild("ClientFx") and ws.ClientFx:FindFirstChild("Imp_" .. name) end
local function near(h, p, r) return h and (h.CFrame.Position - p).Magnitude < (r or 6) end
local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

print("② 机器人 / 工事那样开一枪：打坦克、打地、打海、打天上")
local from = stand + V3(0, 2, 0)
local tp = tank.root.CFrame.Position
local W = { dmg = 1, range = 800, fx = "rifle" }
local src = { team = P1.team, name = "测试" }
sent, sounds = {}, {}
camHere()
G.botShot(from, tp, W, src, { p1.Character }, 0)
local eTank = sent[#sent]
check(eTank and eTank.h == "a", "打在坦克上：特效带 h = a（" .. tostring(eTank and eTank.h) .. "）")
R.run(0.6)   -- 等曳光飞到
check(near(holder("spark"), eTank and eTank.b or tp, 8), "客户端：火花发射器挪到了弹着点")
check(near(holder("flash"), eTank and eTank.b or tp, 8), "客户端：白热的一闪也在弹着点")
check(has(sounds, "ping"), "叮的一声（" .. table.concat(sounds, ",") .. "）")

sent, sounds = {}, {}
local gp = V3(tx - 60, gy, tz + 25)
camHere()
G.botShot(from, gp - V3(0, 2, 0), W, src, { p1.Character }, 0)
local eG = sent[#sent]
check(eG and (eG.h == "d" or eG.h == "n" or eG.h == "r"), "打在地上：h = " .. tostring(eG and eG.h))
R.run(0.4)
local dustH = holder((eG and eG.h == "n") and "sand" or ((eG and eG.h == "r") and "rock" or "dirt"))
check(near(dustH, eG and eG.b or gp, 8), "客户端：扬尘的发射器挪到了弹着点")
check(not has(sounds, "ping") and not has(sounds, "clang"), "打土没有金属声")

sent = {}
local sea = V3(A2.x, 0, A2.z - 3200)
G.botShot(V3(sea.X, 40, sea.Z + 200), sea, W, src, {}, 0)
local eW = sent[#sent]
check(eW and eW.h == "w", "打在海里：h = w（" .. tostring(eW and eW.h) .. "）")

sent = {}
G.botShot(from, from + V3(0, 500, 0), W, src, { p1.Character }, 0)
local eS = sent[#sent]
check(eS and eS.h == nil, "打到天上：不带 h（" .. tostring(eS and eS.h) .. "）")
local sp0 = holder("spark").CFrame.Position
R.run(0.8)
check((holder("spark").CFrame.Position - sp0).Magnitude < 0.01, "打到天上：客户端什么都不出")

print("③ 自己开的枪（客户端本地判）")
sounds = {}
holder("spark").CFrame = CF(0, -500, 0)
camHere()
C.gunFx("m4", from, tp + (from - tp).Unit * 5.2, true)   -- 打在坦克命中盒表面附近
R.run(0.4)
check(near(holder("spark"), tp, 16), "自己打在坦克上：火花发射器挪过去了")
check(has(sounds, "ping"), "叮的一声")

print("④ 炮弹直接打在坦克上")
sent = {}
camHere()
G.launch({ kind = "shell", pos = tp + V3(-60, 3, 0), vel = V3(400, 0, 0), grav = false, w = { dmg = 1, splash = 4, cal = 0.42, fx = "tank" },
  src = src, ignore = {}, life = 1 })
R.run(0.4)
local sk = nil
for _, e in ipairs(sent) do if e.k == "spark" then sk = e end end
check(sk ~= nil and sk.h == "a" and (sk.s or 0) > 1.8, "服务器发了钢甲火花（h " .. tostring(sk and sk.h) .. "，大小 " .. tostring(sk and sk.s) .. "）")
R.run(0.2)
check(sk and near(holder("flash3"), sk.p, 8), "客户端：大闪光在弹着点")
check(sk and near(holder("spark2"), sk.p, 8), "客户端：大火星在弹着点")

-- 真录音（SoundLib.lua，用户 11-21：声音要逼真）：模拟器里没法真的载音频——假装几样载上了，看是不是换成真录音、没载上的照旧叠出来
print("⑨ 真录音：载上了的换成真录音，没载上的照旧")
local REAL = C.realSoundState and C.realSoundState()
check(REAL ~= nil, "有真录音的表")
if REAL then
  REAL.tankGun = { "rbxassetid://18221697746" }
  REAL.boomM = { "rbxassetid://18245316227" }
  REAL.tankEngine = { "rbxassetid://8213083943" }
  local function soundsWith(id)
    local n = 0
    for _, d in ipairs(R.workspace:GetDescendants()) do if d.ClassName == "Sound" and d.SoundId == id then n = n + 1 end end
    for _, d in ipairs(R.game:GetService("SoundService"):GetDescendants()) do if d.ClassName == "Sound" and d.SoundId == id then n = n + 1 end end
    return n
  end
  local p0 = R.workspace.CurrentCamera.CFrame.Position + V3(40, 0, 0)
  C.sfx("tankGun", p0, { must = true })
  check(soundsWith("rbxassetid://18221697746") > 0, "坦克炮换成了真录音（88mm 车外）")
  C.sfx("whiz", p0, { must = true })
  check(soundsWith("rbxassetid://9113634361") == 0 and soundsWith("rbxassetid://9113634444") == 0, "没载上的（子弹呼啸）照旧用叠出来的")
  local eng = C.realLoop("tankEngine", R.game:GetService("SoundService"))
  check(eng ~= nil and eng.Looped == true and eng.SoundId == "rbxassetid://8213083943", "坦克发动机的循环真录音")
  if eng then eng:Destroy() end
  check(C.realLoop("jetEngine", R.game:GetService("SoundService")) == nil, "没载上的循环（喷气发动机）返回空，照旧叠出来的")
  REAL.tankGun, REAL.boomM, REAL.tankEngine = nil, nil, nil
end

T.summary()
