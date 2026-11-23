-- 宣传片里的动画做进游戏（模拟器；用户 11-23：「在游戏里实现动画里的动画」）：python3 tools/mock/run.py tools/mock/wreckfx.lua
--   ① 坦克被打爆、炮塔掀飞：照片子里调好的样子——顶起不超过 5 米（14 格）、慢慢翻、落在车旁边（20 格以内）停住
--   ② 直升机在空中被打掉：尾桨没了越转越快、机头往下栽，尾梁拖着火和黑烟；服务器 4 秒后收了实体，客户端的残骸还在、接着往下掉；
--      砸到地上炸开，躺着烧十几秒才删
--   ③ 固定翼被打掉：顺着速度栽下去、拖着火和黑烟，也是收了实体以后接着掉到地上
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local function has(list, x) for _, y in ipairs(list or {}) do if y == x then return true end end return false end

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 9301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
T.leaveMenu()

-- 找一块陆地（离出生的地方不远、平一点）
local A2 = G.Map.AFIELD2 or { x = 0, z = 0, wid = 200 }
local X, Z = A2.x + 300, A2.z - (A2.wid or 200) / 2 - 260
local gy = G.airSurface(X, Z)

print("① 坦克被打爆：炮塔掀飞")
local tank = G.spawnGroundVeh("def", "ztz99a", CF(X, gy + 2, Z), nil, nil)
check(tank ~= nil, "放了一辆 99A")
local cam = R.workspace.CurrentCamera
cam.CFrame = R.CFrame.lookAt(V3(X + 60, gy + 20, Z + 60), V3(X, gy, Z))
R.run(1)
local v = tank and C.viewById(tank.id)
check(v ~= nil and v.tF ~= nil, "客户端有这辆车的样子")
local toss0 = C.tossCount
if tank then G.damageEnt(tank, 1e6, { team = "atk", name = "test" }) end
local maxUp, p0 = 0, v and v.tF and v.tF.Position
local landed = false
for _ = 1, 80 do
  R.run(0.05)
  if v and v.toss then
    local p = v.toss.cf.Position
    if p0 then maxUp = math.max(maxUp, p.Y - p0.Y) end
    if v.toss.rest then landed = true break end
  end
end
check(C.tossCount == toss0 + 1, "炮塔掀飞了")
check(maxUp > 3 and maxUp < 14, string.format("顶起来 %.1f 格（不超过 5 米，原来能飞十几米）", maxUp))
check(landed, "落地停住了")
if v and v.toss and p0 then
  local p = v.toss.cf.Position
  local dh = math.sqrt((p.X - p0.X) ^ 2 + (p.Z - p0.Z) ^ 2)
  check(dh < 20, string.format("落在车旁边（离座圈 %.1f 格）", dh))
  check(v.toss.w.Magnitude < 2.5, string.format("翻得慢（每秒 %.2f 弧度）", v.toss.w.Magnitude))
end

print("② 直升机在空中被打掉")
local H0 = gy + 340   -- 120 米高
local heli = G.spawnAircraft("def", "ah64e", CF(X + 200, H0, Z), nil, nil)
check(heli ~= nil, "放了一架阿帕奇（120 米高）")
cam.CFrame = R.CFrame.lookAt(V3(X + 420, gy + 60, Z + 260), V3(X + 200, H0 - 150, Z))
R.run(1)
local hv = heli and C.viewById(heli.id)
check(hv ~= nil and hv.model ~= nil, "客户端有这架直升机")
if heli then G.damageEnt(heli, 1e6, { team = "atk", name = "test" }) end
R.run(1.0)
check(hv and hv.wreck ~= nil and hv.wreck.heli, "进了坠落")
local yaw1 = hv and hv.wreck and hv.wreck.yaw or 0
R.run(0.5)
local yaw2 = hv and hv.wreck and hv.wreck.yaw or 0
R.run(0.5)
local yaw3 = hv and hv.wreck and hv.wreck.yaw or 0
check((yaw3 - yaw2) > (yaw2 - yaw1) and (yaw2 - yaw1) > 0.8, string.format("越转越快（半秒转 %.2f → %.2f 弧度）", yaw2 - yaw1, yaw3 - yaw2))
local fire = hv and hv.model and hv.model:FindFirstChild("WreckFire")
check(fire ~= nil and fire:FindFirstChildOfClass("ParticleEmitter") ~= nil, "尾梁上挂着火和黑烟")
local y4 = hv and hv.cf.Position.Y or 0
check(y4 < H0 - 20, string.format("往下掉了（%.0f 格）", H0 - y4))
-- 服务器 4 秒后收走实体：残骸还在
R.run(2.6)
check(C.viewById(heli and heli.id or -1) == nil, "服务器把实体收了")
check(hv and hv.model and hv.model.Parent ~= nil and has(C.airFalling, hv), "客户端的残骸还在、接着掉")
T.runUntil(function() return hv.wreck.down end, 20)
check(hv.wreck.down, string.format("砸到地上了（离地 %.1f 格）", hv.cf.Position.Y - G.airSurface(hv.cf.Position.X, hv.cf.Position.Z)))
R.run(8)
check(hv.model.Parent ~= nil, "残骸躺着烧")
T.runUntil(function() return hv.model.Parent == nil end, 15)
check(hv.model.Parent == nil and not has(C.airFalling, hv), "烧完删掉了")

print("③ 固定翼被打掉")
local jet = G.spawnAircraft("def", "j10", CF(X - 300, H0, Z), nil, nil)
if not jet then jet = G.spawnAircraft("def", "f35", CF(X - 300, H0, Z), nil, nil) end
check(jet ~= nil, "放了一架战斗机")
R.run(1)
local jv = jet and C.viewById(jet.id)
if jet then
  jet.vel = V3(0, 0, -150)
  G.damageEnt(jet, 1e6, { team = "atk", name = "test" })
end
R.run(0.6)
check(jv and jv.wreck and not jv.wreck.heli, "固定翼进了坠落")
local f2 = jv and jv.model and jv.model:FindFirstChild("WreckFire")
check(f2 ~= nil, "尾喷口拖着火和黑烟")
T.runUntil(function() return jv.wreck.down end, 25)
check(jv.wreck.down, "砸到地上了")

T.summary()
