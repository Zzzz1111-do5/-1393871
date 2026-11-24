-- 99A / 96 车里自己拼的零件换成 Sketchfab 真模型件（用户 11-23：「很粗糙 你从sketchfeb找模型去替代不要自己建模 然后用blender」）：
--   python3 tools/mock/run.py tools/mock/interior_props_cn.lua [veh=ztz99a|ztz96] [dump=<目录>]
--   ① 坐上车、进车内，等后台把真模型件都生成好、内饰重建一次
--   ② 每件摆了几个：驾驶员 / 炮长 / 车长座椅（卡车驾驶座去掉气囊底座）、方向盘（99A）或两根操纵杆（96）、换挡杆、踏板、
--      炮长两个 + 车长一个握把、显示单元外壳（99A 驾驶员也是；96 驾驶员是指针式仪表）、开关面板、顶灯
--   ③ 方向盘跟着转向转（swheel 组绕自己的 Z 轴转，真模型件跟着组走）
--   dump=<目录>：写 interior_<型号>_props.json（AMB=1.0 node tools/mock/interior_view.cjs 画图，真模型件按 models/optics 的 GLB 画）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, Enum = T.R, T.V3, T.Enum
local check = T.check
local VEH = TEST_ARGS:match("veh=(%w+)") or "ztz99a"
local dumpDir = TEST_ARGS:match("dump=(%S+)")
local is96 = VEH == "ztz96"

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
G.botsClear()
local me = T.join("P1", 8131, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local def = VD.get(VEH)
local team = (def and def.team) or "def"
local P = G.P[me]
P.team = team
me.Team = G.TEAM[team]
me.Neutral = false
me:SetAttribute("Side", team)
G.pushOne(P)
R.run(1)
local C = T.C
if C.menuShown and C.menuShown() then C.menuEnter() end
T.actAs(me, "deploy", "rifle", (team == "atk") and "barge" or "camp")
R.run(1.5)
local Map = G.Map

print("① 坐上 " .. VEH .. "、进车内，等真模型件生成好")
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
local hp = hrp and hrp.Position or V3(Map.CAMP.x, 0, Map.CAMP.z)
local cx, cz = hp.X + 16, hp.Z
for k = 0, 23 do
  local a = k / 24 * math.pi * 2
  local x, z = hp.X + math.cos(a) * 18, hp.Z + math.sin(a) * 18
  if Map.isLand(x, z) and Map.slope(x, z) < 0.25 then cx, cz = x, z break end
end
local e = G.newVehicle(team, VEH, G.vehBaseAt(def, cx, cz, V3(0, 0, -1)))
R.run(0.5)
if me.Character then me.Character:PivotTo(e.root.CFrame * T.CF(8, 2, 0)) end
R.run(0.3)
T.act("enterVeh", e.id)
R.run(1)
check(P.vehicle == e and C.drive ~= nil, "坐上了 " .. VEH)
T.runUntil(function() return G.round.phase == "battle" end, 60)
T.tap(Enum.KeyCode.C)
R.run(0.6)
check(C.interiorOn() and C.interiorState().cur ~= nil, "按 C：坐进车里")
local NEW = { "ip_dseat", "ip_lever", "ip_pedals", "ip_grip", "ip_cdu", "ip_sw", "ip_lamp", is96 and "ip_gauges" or "ip_swheel" }
T.runUntil(function()
  for _, k in ipairs(NEW) do if not C.opticReady(k) then return false end end
  local cur = C.interiorState().cur
  return cur ~= nil and cur.propsDone == true
end, 240)
local fails = {}
for _, k in ipairs(NEW) do if not C.opticReady(k) then table.insert(fails, k .. (C.opticFailed(k) and "（生成失败）" or "（还没好）")) end end
check(#fails == 0, "真模型件都生成好了" .. (#fails > 0 and ("：没好的 " .. table.concat(fails, "、")) or ""))
R.run(1)

print("② 每件摆了几个")
local cur = C.interiorState().cur
local byKey = {}
for _, p in ipairs(cur.model:GetDescendants()) do
  local k = p:IsA("BasePart") and string.match(p.Name, "^O_(.-)__")
  if k then byKey[k] = (byKey[k] or 0) + 1 end
end
local WANT = is96 and { ip_dseat = 3, ip_lever = 3, ip_pedals = 1, ip_grip = 3, ip_cdu = 3, ip_gauges = 1, ip_sw = 2, ip_lamp = 2, ip_swheel = 0 }
  or { ip_dseat = 3, ip_lever = 1, ip_pedals = 1, ip_grip = 3, ip_cdu = 4, ip_gauges = 0, ip_sw = 2, ip_lamp = 2, ip_swheel = 1 }
local META = R.require(R.services.ReplicatedStorage:FindFirstChild("OpticsMeta"))
for k, want in pairs(WANT) do
  local nParts = 0
  for _ in pairs(META[k].parts) do nParts = nParts + 1 end
  local n = math.floor((byKey[k] or 0) / nParts + 0.5)
  check(n == want, string.format("%s 摆了 %d 件（要 %d 件；%s）", k, n, want, META[k].credit and string.match(META[k].credit, "^([^：]+)") or ""))
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))

if not is96 then
  print("③ 方向盘跟着转向转")
  local function wheelPart()
    for _, p in ipairs(cur.model:GetDescendants()) do
      if p:IsA("BasePart") and string.match(p.Name, "^O_ip_swheel__") then return p end
    end
  end
  local w = wheelPart()
  local hull = cur.b.groups.hull.world
  local r0 = w and hull:ToObjectSpace(w.CFrame).Rotation
  -- 按住 D 打方向（自己开的车：View 每帧把 G.myVeh.steer 抄给内饰动画读的那辆车）
  T.key(Enum.KeyCode.D, true)
  R.run(1.0)
  local r1 = w and cur.b.groups.hull.world:ToObjectSpace(w.CFrame).Rotation   -- 车原地转了：按现在的车体量
  local ang = 0
  if r0 and r1 then
    local ax, a = (r0:Inverse() * r1):ToAxisAngle()
    ang = math.deg(math.abs(a))
  end
  check(ang > 30, string.format("打满方向，方向盘转了 %.0f°", ang))
  T.key(Enum.KeyCode.D, false)
end

if dumpDir then
  local cam = R.workspace.CurrentCamera
  local dumpCams = {}
  for _, k in ipairs({ Enum.KeyCode.F2, Enum.KeyCode.F3, Enum.KeyCode.F4 }) do
    T.tap(k)
    R.run(0.5)
    dumpCams[tostring(C.interiorState().station)] = cam.CFrame
  end
  local dumpOut = dofile(MOCK_DIR .. "/interior_dump.lua")
  local v = C.viewById(e.id)
  dumpOut(C.interiorState().cur, v.hullF, dumpCams, dumpDir .. "/interior_" .. VEH .. "_props.json", cam, Enum)
  print("  写了 " .. dumpDir .. "/interior_" .. VEH .. "_props.json")
end
check(#R.errors == 0, "换位没有报错：" .. table.concat(R.errors, " | "))
T.summary()
