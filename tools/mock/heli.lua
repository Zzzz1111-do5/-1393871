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
  "能飞了：最下面一排换成 E/Q 升降、W/S 前后、A/D 转向……")
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

print("③ W 压机头往前冲、S 抬头刹车")
local function fwdSpeed()
  local f = V3(-math.sin(st.yaw), 0, -math.cos(st.yaw))
  return st.hv:Dot(f)
end
local v0 = fwdSpeed()
T.key(Enum.KeyCode.W, true)
R.run(4)
local v1 = fwdSpeed()
check(st.tiltP < -0.15, string.format("机头压下去了（%.0f°）", math.deg(st.tiltP)))
check(v1 > v0 + 25, string.format("往前冲（前进速度 %.0f → %.0f 格 / 秒）", v0, v1))
T.key(Enum.KeyCode.W, false)
T.key(Enum.KeyCode.S, true)
R.run(3)
T.key(Enum.KeyCode.S, false)
local v2 = fwdSpeed()
check(v2 < v1 - 10, string.format("按 S 抬头刹车（%.0f → %.0f）", v1, v2))
R.run(4)

print("④ A / D 转向，镜头跟着机头转；鼠标只转镜头（瞄机炮），不带着飞机转")
local function angd(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end
st.camYaw = st.yaw
local yaw0 = st.yaw
T.key(Enum.KeyCode.D, true)
R.run(1)   -- 一秒转七八十度（超过半圈就分不清往哪边转了）
T.key(Enum.KeyCode.D, false)
R.run(0.5)
local turned = angd(yaw0, st.yaw)
check(turned < -0.6, string.format("按 D 往右转（%.0f°）", -math.deg(turned)))
check(math.abs(angd(st.yaw, st.camYaw)) < 0.2, string.format("镜头跟着机头转（差 %.0f°）", math.deg(angd(st.yaw, st.camYaw))))
R.run(3)   -- 松开 D 以后转动的惯性停下来
local yaw1 = st.yaw
st.camYaw = yaw1 + 1.2   -- 鼠标往左转镜头
R.run(4)
check(math.abs(angd(yaw1, st.yaw)) < 0.12, string.format("鼠标转镜头，机头不跟着转（%.0f°）", math.deg(angd(yaw1, st.yaw))))
local p = st.cf.Position
check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "位置正常（没有 NaN）")
-- 开了一会儿（看过三步卡的 10 秒后）：最下面收成一个「F1 全部按键」；F1 打开全部按键（原来最下面那一整行说明的全文）
check(keyShown("F1") and not keyShown("E/Q"), "开了一会儿：最下面收成「F1 全部按键」")
T.tap(Enum.KeyCode.F1)
R.run(0.2)
local panel = me.PlayerGui:FindFirstChild("CoachPanel", true)
local qd = C.T("air.helpHeli"):match("E ([^·]-)%s*·")   -- 「升 / Q 降」：E 那一格的动作
check(panel and T.visible(panel) and keyShown("E") and keyShown("A/D") and keyShown("F") and qd and #T.texts("^" .. qd:gsub("%p", "%%%0") .. "$") > 0,
  "F1：全部按键面板（E 升 / Q 降、A/D 转向、F 导弹……）")
T.tap(Enum.KeyCode.F1)
R.run(0.2)
check(not T.visible(panel), "再按 F1 关上")

T.summary()
