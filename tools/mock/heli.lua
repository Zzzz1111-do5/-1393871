-- 直升机操纵测试（模拟器）：python3 tools/mock/run.py tools/mock/heli.lua [v]
--   用户：升降改成 Q / E；镜头往哪看就往哪飞——往下看机头压下去、惯性往前冲；配合 WASD（W / S 前后、A / D 左右平移）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check

local G = T.boot()
G.fortsHold = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 6001, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", "af2")
R.run(2)
check(P.alive, "出生了")

print("① 在机场岛上放一架直升机、坐进去，等旋翼转起来")
local A2 = G.Map.AFIELD2
local x, z = A2.x + 300, A2.z - A2.wid / 2 - 200
local d = G.AD and G.AD.get and G.AD.get("z10")
local gy = G.airSurface(x, z)
local e = G.spawnAircraft("atk", "z10", CF(x, gy + 6, z), nil, P)
check(e ~= nil, "放了一架直-10")
if not e then T.summary() return end
me.Character:PivotTo(CF(x + 20, gy + 3.5, z))
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.fly
check(P.vehicle == e and st ~= nil and st.d.kind == "heli", "坐进了直升机")
if not st then T.summary() return end
T.runUntil(function() return st.rpm and st.rpm >= 95 end, 15)
check(st.rpm >= 95, string.format("旋翼转起来了（%.0f%%）", st.rpm))

print("② Q 升、E 降")
local y0 = st.cf.Position.Y
T.key(Enum.KeyCode.Q, true)
R.run(4)
T.key(Enum.KeyCode.Q, false)
local y1 = st.cf.Position.Y
check(y1 > y0 + 25 and not st.ground, string.format("按住 Q 往上升（%.0f → %.0f 格）", y0, y1))
R.run(2)
local y2 = st.cf.Position.Y
T.key(Enum.KeyCode.E, true)
R.run(2)
T.key(Enum.KeyCode.E, false)
local y3 = st.cf.Position.Y
check(y3 < y2 - 5, string.format("按住 E 往下降（%.0f → %.0f 格）", y2, y3))
T.key(Enum.KeyCode.Q, true)
R.run(4)
T.key(Enum.KeyCode.Q, false)
R.run(2)

print("③ 往下看：机头压下去、往前冲；往上看：抬头刹车")
local function fwdSpeed()
  local f = V3(-math.sin(st.yaw), 0, -math.cos(st.yaw))
  return st.hv:Dot(f)
end
local v0 = fwdSpeed()
st.camYaw = st.yaw
st.camPitch = -0.12 - 0.45   -- 比平常往下看 26°
R.run(4)
local v1 = fwdSpeed()
check(st.tiltP < -0.15, string.format("机头压下去了（%.0f°）", math.deg(st.tiltP)))
check(v1 > v0 + 25, string.format("往前冲（前进速度 %.0f → %.0f 格 / 秒）", v0, v1))
st.camPitch = -0.12 + 0.35   -- 往上看
R.run(4)
local v2 = fwdSpeed()
check(v2 < v1 - 10, string.format("往上看抬头刹车（%.0f → %.0f）", v1, v2))
st.camPitch = -0.12
R.run(4)

print("④ A / D 左右平移；机头跟着镜头转")
local function sideSpeed()
  local r = V3(math.cos(st.yaw), 0, -math.sin(st.yaw))
  return st.hv:Dot(r)
end
local s0 = sideSpeed()
T.key(Enum.KeyCode.D, true)
R.run(2.5)
T.key(Enum.KeyCode.D, false)
local s1 = sideSpeed()
check(s1 > s0 + 8, string.format("按 D 往右平移（侧向速度 %.0f → %.0f）", s0, s1))
R.run(3)
local yaw0 = st.yaw
st.camYaw = yaw0 + 1.2
R.run(5)
local turned = (st.yaw - yaw0 + math.pi) % (2 * math.pi) - math.pi
check(turned > 0.6, string.format("机头跟着镜头转过去（%.0f°）", math.deg(turned)))
local p = st.cf.Position
check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "位置正常（没有 NaN）")
local helpOk = false
for _, t in ipairs(T.texts("Q")) do if t:find("E", 1, true) and t:find("A/D", 1, true) then helpOk = true end end
check(helpOk, "最下面一行写着 Q 升 / E 降、A/D 平移")

T.summary()
