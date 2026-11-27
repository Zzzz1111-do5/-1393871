-- 飞机发动机（模拟器）：python3 tools/mock/run.py tools/mock/jeteng.lua
--   用户 11-26「飞机发动机有 bug」：从跑道上推油门起飞，看发动机这一圈都对得上——
--   ① 推油门：推力、发动机声（音量、音高）、喷口里的涡轮转速跟着上去；推满进加力
--   ② 发动机打坏（WtaEng = 0）：没推力、声音降下去、涡轮只剩风车转（原来照着油门接着转）、喷口不亮、平显报熄火
--   ③ 落地修好：推力回来
--   ④ 左上参数表的油温：不会出一个永远走不完的「还能撑多久」倒计时（喷气机不过热，原来开加力就挂着一个 0:33 不动的橙色倒计时）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.wtaNoRepair = true   -- 停在自己营地边上：落地补给会把打坏的发动机修回来（Air.lua），这里自己控制修没修
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 8601, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.picked = true
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", "base")
R.run(1.5)
T.runUntil(function() return G.round.phase == "battle" end, 90)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local d = AD.get("j20")
local hrp = P.char:FindFirstChild("HumanoidRootPart")
local x, z = hrp.Position.X + 60, hrp.Position.Z
local gy = G.airSurface(x, z)
local e = G.spawnAircraft(P.team, "j20", CF(x, gy + d.gearH + 0.5, z), nil, P)
check(e ~= nil, "放了一架歼-20")
if not e then T.summary() return end
P.char:PivotTo(CF(x + 20, gy + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1.2)
local st = C.fly
check(st ~= nil and st.pilot, "坐进了驾驶座")
if not st then T.summary() return end
local function view()
  for em2, v in pairs(C.views or {}) do if em2 == st.em and v.M then return v end end
end

print("① 推油门")
local thr0 = st.thr
local spin0 = (view() or {}).spinJ or 0
T.key(Enum.KeyCode.LeftShift, true)
R.run(1.0)
local v = view()
-- 涡轮每帧转多少（18 片叶片，间隔 20°）：超过半个间隔看着就是停住 / 倒转
local function perFrame()
  local mx = 0
  for _ = 1, 20 do
    local a = v and v.spinJ or 0
    R.run(1 / 60)
    local b = v and v.spinJ or 0
    mx = math.max(mx, (b - a) % (2 * math.pi))
  end
  return mx
end
local spinRateLow = perFrame()
R.run(1.5)
T.key(Enum.KeyCode.LeftShift, false)
print(string.format("  油门 %.0f → %.0f，推力 %.2f，表速 %.0f", thr0, st.thr, st.thrust or -1, st.spd or 0))
check(st.thr > 100, string.format("推满进了加力（%.0f）", st.thr))
-- 飞行物理（FlightModel.engine，11-26 晚）：转速照这一型的加速时间往上走（歼-20 慢车到军推 4 秒，真涡扇三到五秒），油门推上去的同时一路跟着
check((st.thrE or 0) > 60, string.format("发动机在跟上来（推满后 %.0f）", st.thrE or 0))
R.run(1.6)
check((st.thrE or 0) > 95, string.format("再过一会儿到军推、点上加力（%.0f）", st.thrE or 0))
local snd = st.engSnd
if snd then
  print(string.format("  发动机声：音量 %.2f、音高 %.2f", snd.Volume, snd.PlaybackSpeed))
  check(snd.Volume > 0.7 and snd.PlaybackSpeed > 1.0, "发动机声大了、音调高了")
else
  print("  （模拟器里没有真录音的发动机声，跳过声音那几条）")
end
local c = v and v.c or {}
check((c.rpm or 0) > 90 and (c.thr or 0) > 90, string.format("别人看到的转速、油门也上去了（%.0f / %.0f）", c.rpm or 0, c.thr or 0))
local spinRateHi = perFrame()
print(string.format("  涡轮每帧转（画面）：推油门中 %.1f°、加力 %.1f°（叶片间隔 20°）", math.deg(spinRateLow), math.deg(spinRateHi)))
check(spinRateHi < math.rad(10) and spinRateHi > spinRateLow * 0.99 and spinRateHi > math.rad(2), "加力时涡轮转得快、但一帧不超过半个叶片间隔（看着不会停住、倒转）")
local _ = spin0

print("② 发动机打坏")
e.model:SetAttribute("WtaEng", 0)
if e.wta then e.wta.p.eng = 0 end
T.key(Enum.KeyCode.LeftShift, true)
R.run(4.5)
T.key(Enum.KeyCode.LeftShift, false)
check((st.thrust or 1) == 0 or st.ground, string.format("打坏了没推力（%.2f）", st.thrust or -1))
if snd then check(snd.Volume < 0.15, string.format("发动机声没了（%.2f）", snd.Volume)) end
local spinDead = perFrame()
print(string.format("  涡轮每帧转（画面）：打坏后 %.2f°", math.deg(spinDead)))
check(spinDead < spinRateHi * 0.4, string.format("打坏了涡轮只剩风车转（%.2f°，加力时 %.2f°）", math.deg(spinDead), math.deg(spinRateHi)))
check((v and v.c and v.c.thr or 1) == 0, "喷口不亮（c.thr = 0）")

local offTxt = false
for _, dd in ipairs(me.PlayerGui:GetDescendants()) do
  if dd:IsA("TextLabel") and dd.Text and dd.Text:find(C.T("wt.engOff"), 1, true) then offTxt = true end
end
check(offTxt, "参数表的引擎温度后面写着「熄火」")

print("③ 修好")
e.model:SetAttribute("WtaEng", 1)
if e.wta then e.wta.p.eng = 100 end
R.run(1.0)
check(st.ground or (st.thrust or 0) > 0, string.format("修好了推力回来（%.2f）", st.thrust or -1))

print("④ 参数表的油温")
local rows = C.wtFlightRows and C.wtFlightRows() or nil
local stuck = false
local found = false
for _, dd in ipairs(me.PlayerGui:GetDescendants()) do
  if dd:IsA("TextLabel") and dd.Text and dd.Text:find("°C", 1, true) then
    found = true
    if dd.Text:find("%d+:%d%d") then stuck = true end
  end
end
local _2 = rows
print("  参数表里有油温：" .. tostring(found))
check(not stuck, "喷气机的油温后面没有永远走不完的倒计时")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
