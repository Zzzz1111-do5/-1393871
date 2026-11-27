-- 对战中的卡顿排查（模拟器）：python3 tools/mock/run.py tools/mock/perf_battle.lua [开战后先打多少秒，默认 120] [测多少秒，默认 8]
--   开战后让 AI 载具、飞机、舰艇打一阵，再量服务器每一步（回合、实体、载具、工事、逐帧）和客户端每个回调的开销、
--   每帧的建 / 删 / 改属性 / 射线次数、远程事件数据量、场景里的实体和零件数
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local K = dofile(MOCK_DIR .. "/perfkit.lua")(T)
local nums = {}
for x in TEST_ARGS:gmatch("%d+") do nums[#nums + 1] = tonumber(x) end
local warm, secs = nums[1] or 120, nums[2] or 8

-- map=snow / map=city：量线上那两张图（默认照旧沙海，common.lua）
T.mapName = TEST_ARGS:match("map=(%w+)")
local G = T.boot()
T.runUntil(function() return G.worldReady end, 900)
local me = T.join("P1", 7401, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = "atk"
me.Team = G.TEAM.atk
me.Neutral = false
me:SetAttribute("Side", "atk")
G.pushOne(P)
R.run(1)
local C = T.C
-- 出生（11-27）：舰队出生点没了（Round.lua 只剩 base），主菜单要先关掉——原来的 deploy rifle fleet 出不了生，开坦克那段被跳过
T.leaveMenu()
T.actAs(me, "deploy", "rifle", "base")
T.runUntil(function() return P.alive and me.Character ~= nil end, 15)
R.run(1)
check(P.alive, "攻方在自己基地出生")
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
check(G.round.phase == "battle", "开战了")
print(string.format("开战后先打 %d 秒（步长 1/10）", warm))
R.run(warm, 1 / 10)

local function ents()
  local f = R.workspace:FindFirstChild("Ents")
  local cat = {}
  for _, em in ipairs(f and f:GetChildren() or {}) do
    local k = tostring(em:GetAttribute("Cat") or em._cls)
    cat[k] = (cat[k] or 0) + 1
  end
  local out = {}
  for k, v in pairs(cat) do out[#out + 1] = k .. " " .. v end
  table.sort(out)
  print("  实体（Ents）：" .. table.concat(out, "，"))
end
ents()
K.inventory("打了一阵", me)

local timed = { t = {}, n = {} }
K.wrap(C, "^step", "客户端 G.", timed)
K.wrap(G, "Step$", "服务器 G.", timed)
if G.flushFx then K.wrap(G, "^flushFx$", "服务器 G.", timed) end
print("① 步兵在舰队 / 岸上（对战进行中）")
K.measure("对战中", secs, timed)

-- 换成开坦克：攻方的坦克在玩家旁边
print("② 对战中开坦克")
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local tid = G.Config.Vehicles.atk.tank[1]
local d = VD.get(tid)
local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
if hrp then
  -- 找一块岸上的平地（目标附近），把人和车放过去
  local pt = G.points and (G.points.A or G.points.C)
  local px, pz = 0, 0
  if pt and pt.pos then px, pz = pt.pos.X + 200, pt.pos.Z + 200 end
  local found = false
  for r = 0, 600, 40 do
    for a = 0, 330, 30 do
      local x, z = px + math.cos(math.rad(a)) * r, pz + math.sin(math.rad(a)) * r
      if G.Map.height(x, z) > 4 and G.Map.slope(x, z) < 0.15 then px, pz, found = x, z, true break end
    end
    if found then break end
  end
  local e = G.newVehicle("atk", tid, G.vehBaseAt(d, px, pz, V3(0, 0, 1)))
  R.run(0.5)
  me.Character:PivotTo(CF(px + 6, G.Map.ground(px + 6, pz) + 3.5, pz))
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(2)
  check(C.drive ~= nil, "坐进坦克 " .. tid)
  T.key(Enum.KeyCode.W, true)
  K.measure("对战中开坦克", secs, timed)
  T.key(Enum.KeyCode.W, false)
end
T.summary()
