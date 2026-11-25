-- 直升机操纵测试（模拟器）：python3 tools/mock/run.py tools/mock/heli.lua [v]
--   用户：升降 E 升、Q 降（Q 升 E 降之后又改回来）；W / S 前后、A / D 转向；鼠标只转镜头、瞄机炮（不再带着飞机转）
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
T.tap(Enum.KeyCode.Backspace)   -- 先关上出生时的「目标与据点」说明（开着的时候三步卡等它）
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
local st = C.fly
check(P.vehicle == e and st ~= nil and st.d.kind == "heli", "坐进了直升机")
if not st then T.summary() return end
-- 新手指导（Coach.lua）：最下面一排只给几个键；旋翼没转起来时只有一句「等转速到 100%」；第一次开直升机弹三步卡
local function keyShown(k)
  for _, dd in ipairs(me.PlayerGui:GetDescendants()) do
    if dd.ClassName == "TextLabel" and dd.Name == "Key" and dd.Text == k and T.visible(dd) then return true end
  end
  return false
end
R.run(0.2)
check(#T.texts("^" .. (C.T("coach.spool"):gsub("%p", "%%%0")) .. "$") > 0, "旋翼还没转起来：提示等转速到 100%")
check(C.coachCard and C.coachCard() == "heli" and #T.texts((C.T("coach.card.heli.2"):gsub("%p", "%%%0"))) > 0, "第一次开直升机：左边弹出三步卡（第二步写着 E 升、Q 降）")
T.runUntil(function() return st.rpm and st.rpm >= 95 end, 15)
check(st.rpm >= 95, string.format("旋翼转起来了（%.0f%%）", st.rpm))
R.run(0.2)
check(keyShown("E/Q") and keyShown("W/S") and keyShown("A/D") and #T.texts("^" .. C.T("coach.updown") .. "$") > 0,
  "能飞了：最下面一排换成 鼠标 机头朝向、E/Q 升降、W/S 前倾 / 刹车、A/D 侧飞……")
T.tap(Enum.KeyCode.Return)
R.run(0.2)
check(C.coachCard() == nil and me:GetAttribute("Seen") and me:GetAttribute("Seen"):find("heli", 1, true), "回车关上三步卡；服务器记下看过了（" .. tostring(me:GetAttribute("Seen")) .. "）")

print("② E 升、Q 降")
local y0 = st.cf.Position.Y
T.key(Enum.KeyCode.E, true)
R.run(4)
T.key(Enum.KeyCode.E, false)
local y1 = st.cf.Position.Y
check(y1 > y0 + 25 and not st.ground, string.format("按住 E 往上升（%.0f → %.0f 格）", y0, y1))
R.run(2)
local y2 = st.cf.Position.Y
T.key(Enum.KeyCode.Q, true)
R.run(2)
T.key(Enum.KeyCode.Q, false)
local y3 = st.cf.Position.Y
check(y3 < y2 - 5, string.format("按住 Q 往下降（%.0f → %.0f 格）", y2, y3))
T.key(Enum.KeyCode.E, true)
R.run(4)
T.key(Enum.KeyCode.E, false)
R.run(2)

print("③ W 桨盘前倾往前冲；松杆桨盘回平、人还往前飘（有惯性）；S 往后带杆刹车")
local function fwdSpeed()
  local f = V3(-math.sin(st.yaw), 0, -math.cos(st.yaw))
  return st.hv:Dot(f)
end
local function sideSpeed()
  local r = V3(math.cos(st.yaw), 0, -math.sin(st.yaw))
  return st.hv:Dot(r)
end
local v0 = fwdSpeed()
T.key(Enum.KeyCode.W, true)
R.run(4)
local v1 = fwdSpeed()
check(st.tiltP < -0.15, string.format("桨盘往前倾了（%.0f°）", math.deg(st.tiltP)))
check(v1 > v0 + 25, string.format("往前冲（前进速度 %.0f → %.0f 格 / 秒）", v0, v1))
T.key(Enum.KeyCode.W, false)
R.run(1.5)
local vc = fwdSpeed()
check(math.abs(st.tiltP) < 0.12 and vc > v1 * 0.6, string.format("松开 W：桨盘回平（%.0f°），速度还留着（%.0f → %.0f），不会一下停住", math.deg(st.tiltP), v1, vc))
T.key(Enum.KeyCode.S, true)
R.run(3)
T.key(Enum.KeyCode.S, false)
local v2 = fwdSpeed()
check(v2 < vc - 10, string.format("按 S 往后带杆刹车（%.0f → %.0f）", vc, v2))
R.run(6)

print("④ 准心决定机头朝向：鼠标转准心，机头跟过去（尾桨有惯性，不一下到位）；A / D 侧飞；按住 Alt 自由看")
local function angd(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end
local yaw0 = st.yaw
st.camYaw = yaw0 - 1.2   -- 鼠标往右转 69°
R.run(0.25)
local early = angd(yaw0, st.yaw)
check(early < -0.02 and early > -0.6, string.format("机头开始往右转，但不是一下子到位（0.25 秒转了 %.0f°）", -math.deg(early)))
R.run(2.5)
check(math.abs(angd(st.yaw, st.camYaw)) < 0.06, string.format("机头转到准心那边（还差 %.1f°）", math.deg(angd(st.yaw, st.camYaw))))
local yaw2 = st.yaw
T.key(Enum.KeyCode.D, true)
R.run(3)
local vs = sideSpeed()
check(st.tiltR > 0.1 and vs > 10, string.format("按 D：桨盘往右倾（%.0f°），往右侧飞（%.0f 格 / 秒）", math.deg(st.tiltR), vs))
check(math.abs(angd(yaw2, st.yaw)) < 0.05, string.format("侧飞时机头还对着准心（%.1f°）", math.deg(angd(yaw2, st.yaw))))
T.key(Enum.KeyCode.D, false)
R.run(4)
local yaw3, cy = st.yaw, st.camYaw
T.key(Enum.KeyCode.LeftAlt, true)
R.run(0.1)
st.camYaw = cy + 1.4   -- 按着 Alt 往左看
R.run(2)
check(math.abs(angd(yaw3, st.yaw)) < 0.05, string.format("按住 Alt 自由看：机头不跟着转（%.1f°）", math.deg(angd(yaw3, st.yaw))))
T.key(Enum.KeyCode.LeftAlt, false)
R.run(0.2)
check(math.abs(angd(cy, st.camYaw)) < 0.01, "松开 Alt：准心回到原来的方向")

print("⑤ 快速前飞时转机头：桨盘自动往那边压坡度，航迹跟着机头弯过去")
T.key(Enum.KeyCode.W, true)
R.run(6)
local sp0 = st.hv.Magnitude
local yaw4 = st.yaw
st.camYaw = yaw4 - math.pi / 2   -- 准心往右 90°
local bankMax = 0
for _ = 1, 50 do
  R.run(0.1)
  bankMax = math.max(bankMax, st.tiltR)
end
local f4 = V3(-math.sin(st.yaw), 0, -math.cos(st.yaw))
local hu = (st.hv.Magnitude > 1) and st.hv.Unit or f4
local off = math.deg(math.acos(math.max(-1, math.min(1, hu:Dot(f4)))))
check(bankMax > 0.12, string.format("往右转时桨盘往右压坡度（最大 %.0f°，速度 %.0f 格 / 秒）", math.deg(bankMax), sp0))
check(off < 35, string.format("五秒后航迹跟着机头弯过去了（还差 %.0f°）", off))
T.key(Enum.KeyCode.W, false)
T.key(Enum.KeyCode.S, true)
R.run(3)
T.key(Enum.KeyCode.S, false)
R.run(3)
local p = st.cf.Position
check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "位置正常（没有 NaN）")
print("⑥ 准心决定机头（用户 11-22）：准心往下 → 桨盘前倾往前飞；准心猛往上 → 往后仰，受力往后、往上；机炮比机身先对上准心")
R.run(4)
local base = -0.15
st.camPitch = base - 0.35   -- 准心往下 20°
local vA = fwdSpeed()
R.run(4)
local vB = fwdSpeed()
check(st.tiltP < -0.2 and vB > vA + 20, string.format("准心往下：机头、桨盘往前倾（%.0f°），往前飞（%.0f → %.0f 格 / 秒）", math.deg(st.tiltP), vA, vB))
st.camPitch = base + 0.45   -- 准心猛往上 26°
local vyMax, yS = -1e9, st.cf.Position.Y
for _ = 1, 20 do
  R.run(0.1)
  vyMax = math.max(vyMax, st.vy)
end
local vC = fwdSpeed()
check(st.tiltP > 0.15, string.format("准心猛往上：机头往后仰（%.0f°）", math.deg(st.tiltP)))
check(vC < vB - 10, string.format("受力往后：前进速度 %.0f → %.0f 格 / 秒", vB, vC))
check(vyMax > 3 and st.cf.Position.Y > yS, string.format("受力往上：升降速度最大 %.1f 格 / 秒，高度 %.0f → %.0f", vyMax, yS, st.cf.Position.Y))
st.camPitch = base
R.run(6)
local yawN = st.yaw
st.camYaw = yawN + 0.9   -- 准心往左 52°
R.run(0.25)
local noseLeft = math.abs(angd(st.yaw, st.camYaw))
local gunLeft = -(st.ty or 0)   -- 炮塔相对机头往左转了多少度
check(noseLeft > 0.45 and gunLeft > 25, string.format("准心一甩：机身才转了 %.0f°（还差 %.0f°），机头炮塔已经往左转了 %.0f°", math.deg(0.9) - math.deg(noseLeft), math.deg(noseLeft), gunLeft))
check(math.abs(math.rad(gunLeft) - noseLeft) < noseLeft * 0.35, string.format("炮比机身先对上准心（炮还差 %.0f°，机身还差 %.0f°）", math.abs(math.deg(noseLeft) - gunLeft), math.deg(noseLeft)))
R.run(4)
-- 开了一会儿（看过三步卡的 10 秒后）：最下面收成一个「F1 全部按键」；F1 打开全部按键（原来最下面那一整行说明的全文）
check(keyShown("F1") and not keyShown("E/Q"), "开了一会儿：最下面收成「F1 全部按键」")
T.tap(Enum.KeyCode.F1)
R.run(0.2)
local panel = me.PlayerGui:FindFirstChild("CoachPanel", true)
local qd = C.T("air.helpHeli"):match("E ([^·]-)%s*·")   -- 「升 / Q 降」：E 那一格的动作
check(panel and T.visible(panel) and keyShown("E") and keyShown("A/D") and keyShown("F") and qd and #T.texts("^" .. qd:gsub("%p", "%%%0") .. "$") > 0,
  "F1：全部按键面板（E 升 / Q 降、A/D 侧飞、F 导弹……）")
T.tap(Enum.KeyCode.F1)
R.run(0.2)
check(not T.visible(panel), "再按 F1 关上")

T.summary()
