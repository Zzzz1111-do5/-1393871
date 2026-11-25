-- 地面载具内饰的通用测试（模拟器）：python3 tools/mock/run.py tools/mock/interior_all.lua veh=<型号> [dump=<目录>]
--   用户 11-21：所有载具都要有内饰、所有观瞄设备都要实现。每型：坐上、C 进车内（零件、乘员、屏幕都起来了，没报错）→ F2～F5 换遍乘员位（镜头在车里）→
--   每个乘员位的观瞄设备（Shift 主镜、G 备用、T 第三个）开了再关 → 开一炮 / 打一梭 → 开着走、打方向（方向盘 / T 形把跟着转）→ C 出去
local T = dofile(MOCK_DIR .. "/common.lua")
T.fpAll = true   -- 测的是别的车 / 飞机的车内、座舱（默认只有 M1A1、M1A2 有第一人称）
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "m2a3"
local dumpDir = TEST_ARGS:match("dump=(%S+)")

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8101, true)
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
local def = VD.get(VEH)
print("① 坐上 " .. VEH .. "，C 进车内")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 18, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 20, hp.Z + math.sin(a) * 20
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle("def", VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
local I = C.interiorState()
local cur = I.cur
check(C.interiorOn() and cur ~= nil and I.mode == "seat", "C：坐进车里（" .. tostring(I.station) .. "）")
if not cur then T.summary() return end
local nCrew = 0
for _ in pairs(cur.crew) do nCrew = nCrew + 1 end
local live = 0
for _, s in ipairs(cur.b.screens) do if s.update then live = live + 1 end end
check(#cur.b.parts > 150, "内饰零件 " .. #cur.b.parts .. " 个")
check(#cur.b.screens >= 2 and live == #cur.b.screens, string.format("屏幕 %d 块、页面都起来了（%d）", #cur.b.screens, live))
check(nCrew == 0, string.format("车里不画乘员小人（用户 11-22 晚：「驾驶室不要显示人了」）：%d 个", nCrew))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
local cam = R.workspace.CurrentCamera
local function inside(tag)
  local v = C.viewById(e.id)
  local hull = v and v.hullF
  if not hull then return false end
  local q = hull:PointToObjectSpace(cam.CFrame.Position)
  local ok = math.abs(q.X) < def.W / 2 + 0.3 and q.Y > -0.3 and q.Y < def.H + 1.2 and math.abs(q.Z) < def.L / 2 + 0.3
  check(ok, string.format("%s：镜头在车里（车体坐标 %.1f, %.1f, %.1f 格）", tag, q.X, q.Y, q.Z))
  return ok
end
inside("进车内")

print("② F2～F5 换乘员位，各位的观瞄设备")
local FK = { Enum.KeyCode.F2, Enum.KeyCode.F3, Enum.KeyCode.F4, Enum.KeyCode.F5 }
local SLOT = { primary = Enum.KeyCode.LeftShift, alt = Enum.KeyCode.G, third = Enum.KeyCode.T }
local dumpCams = {}
for i, name in ipairs(cur.spec.order) do
  if FK[i] then
    T.tap(FK[i])
    R.run(0.3)
    check(C.interiorState().station == name, string.format("F%d：%s", i + 1, name))
    inside(name)
    dumpCams[name] = C.viewById(e.id).hullF:ToObjectSpace(cam.CFrame)   -- 按车体坐标记（后面车会开走）
    local sp = cur.spec.stations[name]
    for _, slot in ipairs({ "primary", "alt", "third" }) do
      local o = sp.optics and sp.optics[slot]
      if o then
        T.tap(SLOT[slot])
        R.run(0.7)
        if o.kind == "gps" then
          check(C.drive.sight == true, string.format("  %s 的 %s：瞄准镜", name, slot))
          T.tap(SLOT[slot])
          R.run(0.6)
          check(not C.drive.sight, "  退出瞄准镜")
        else
          local op = C.interiorOpticState()
          check(op ~= nil and op.o.kind == o.kind, string.format("  %s 的 %s：%s", name, slot, o.name or o.kind))
          T.tap(SLOT[slot])
          R.run(0.5)
          check(C.interiorOpticState() == nil, "  关掉")
        end
      end
    end
  end
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))

print("③ 开火、开车打方向")
T.tap(FK[1])
R.run(0.3)
T.mouse(true)
R.run(0.2)
T.mouse(false)
R.run(1)
local wheel = cur.b.groups.swheel or cur.b.groups.tbar
local a0 = wheel and wheel.anim
T.key(Enum.KeyCode.W, true)
T.key(Enum.KeyCode.D, true)
R.run(1.2)
local a1 = wheel and wheel.anim
T.key(Enum.KeyCode.D, false)
T.key(Enum.KeyCode.W, false)
if wheel then
  local ang = math.deg(select(2, a0:ToObjectSpace(a1):ToAxisAngle()))
  check(ang > 5, string.format("打方向：%s 跟着转了 %.0f°", cur.b.groups.swheel and "方向盘" or "T 形把", ang))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
if dumpDir then
  local v = C.viewById(e.id)
  local cams = {}
  for k, rel in pairs(dumpCams) do cams[k] = v.hullF * rel end
  dofile(MOCK_DIR .. "/interior_dump.lua")(cur, v.hullF, cams, dumpDir .. "/interior_" .. VEH .. ".json", cam, Enum)
end

print("④ C 出车外")
for _ = 1, 8 do
  if not C.interiorOn() then break end
  T.tap(Enum.KeyCode.C)
  R.run(0.3)
end
check(not C.interiorOn(), "回到车外")
check(#R.errors == 0, "全程没有报错：" .. table.concat(R.errors, " | "))
T.summary()
