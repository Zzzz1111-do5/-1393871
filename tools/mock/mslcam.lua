-- 导弹视角、导弹画法（模拟器）：python3 tools/mock/run.py tools/mock/mslcam.lua
--   用户 11-27：「l没法看导弹视角目前」「导弹转弯貌似是一个个直角这样转弯的」「激光制导导弹是顺时针旋转着这样打过去的」
--   ① 开着飞机打出去一枚弹，按 L：镜头跟到弹后面（飞行镜头不再把它盖掉）；再按 L 回来
--   ② 弹急转弯：客户端画的弹一帧一帧的方向变化都不大（不再每 0.3 秒一下拐个角），总共转过去一大截
--   ③ 驾束 / 指令制导的反坦克弹（旋风、突击）绕弹轴顺时针转；空空弹不转
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 6511, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.actAs(me, "deploy", "rifle", "base")
R.run(2)
T.runUntil(function() return G.round.phase == "battle" end, 120)
local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
local gy = math.max(G.Map.ground(0, 0), 0)
local p0 = V3(0, gy + 1500, 0)
local jet = G.spawnAircraft("atk", "j20", CF(p0.X, p0.Y, p0.Z), nil, P)
P.char:PivotTo(CF(p0.X + 4, p0.Y, p0.Z))
T.act("enterVeh", jet.id)
R.run(0.3)
local st = C.fly
check(st ~= nil and st.pilot, "坐进歼-20")
if not st then T.summary() return end
st.ground, st.gear, st.gearWant = false, 0, 0
local hold = R.Heartbeat:Connect(function()
  if C.fly then
    C.fly.cf = R.CFrame.lookAt(p0, p0 + V3(0, 0, -1))
    C.fly.vel, C.fly.spd, C.fly.vdir = V3(0, 0, -300), 300, V3(0, 0, -1)
  end
end)
R.run(0.5)
local cam = R.services.Workspace.CurrentCamera

local function fire(wid, aimPt)
  local w = AD.W[wid]
  return G.launch({ kind = "missile", pos = p0 + V3(0, -6, -30), vel = V3(0, 0, -900), w = w, src = { P = P, team = "atk", name = "P1" }, ignore = { jet.model },
    life = 30, step = G.airGuideMissile, age = 0, byEnt = jet.id, aimPt = aimPt })
end

print("① 按 L 跟踪自己的导弹")
local s1 = fire("pl10", p0 + V3(0, 0, -30000))
R.run(0.4)
local fs = C.flyingShots and C.flyingShots[s1.id]
check(fs ~= nil and C.mslCamState() ~= nil, "客户端认出这是自己打的弹（可以按 L 跟踪）")
T.tap(Enum.KeyCode.L)
R.run(0.6)
check(C.mslFollowing() == true, "按 L：进跟踪")
fs = C.flyingShots[s1.id]
local d1 = fs and (cam.CFrame.Position - fs.p).Magnitude or math.huge
local d0 = (cam.CFrame.Position - st.cf.Position).Magnitude
check(fs ~= nil and d1 < 80 and d0 > 150, string.format("镜头在弹后面（离弹 %.0f 格、离自己的飞机 %.0f 格）", d1, d0))
T.tap(Enum.KeyCode.L)
R.run(0.4)
check(C.mslFollowing() == false and (cam.CFrame.Position - st.cf.Position).Magnitude < 150, "再按 L：回到自己的飞机")
s1.life = 0
R.run(0.3)

print("② 急转弯画得顺")
local s2 = fire("pl10", p0 + V3(30000, 0, -2000))   -- 目标点在右边：一直满过载往右转
R.run(0.1)
local prev, maxStep, first, last = nil, 0, nil, nil
for _ = 1, 75 do
  R.run(1 / 30, 1 / 30)
  local f = C.flyingShots[s2.id]
  if not f or f.v.Magnitude < 1 then break end
  local d = f.v.Unit
  first = first or d
  if prev then maxStep = math.max(maxStep, math.deg(math.acos(math.clamp(prev:Dot(d), -1, 1)))) end
  prev, last = d, d
end
local total = (first and last) and math.deg(math.acos(math.clamp(first:Dot(last), -1, 1))) or 0
check(total > 40, string.format("2.5 秒里一共转过去 %.0f°", total))
check(maxStep < 6, string.format("一帧最多转 %.1f°（原来每 0.3 秒一下拐个角）", maxStep))
s2.life = 0
R.run(0.3)

print("③ 驾束 / 指令制导的反坦克弹顺时针自转")
local s3 = fire("vikhr", p0 + V3(0, -1400, -9000))
local s4 = fire("pl10", p0 + V3(0, 0, -30000))
R.run(0.2)
local f3, f4 = C.flyingShots[s3.id], C.flyingShots[s4.id]
local r0 = f3 and f3.roll or 0
R.run(0.3)
check(f3 ~= nil and f3.spin ~= nil and f3.spin > 0 and f3.roll ~= r0, string.format("旋风在转（每秒 %.1f 圈）", f3 and (f3.spin or 0) / (2 * math.pi) or 0))
check(f4 ~= nil and f4.spin == nil, "空空弹不转")
s3.life, s4.life = 0, 0
hold:Disconnect()
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
