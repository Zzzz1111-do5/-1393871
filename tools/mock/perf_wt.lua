-- 战雷式对局（默认雪地图）对战中的卡顿排查（模拟器）：python3 tools/mock/run.py tools/mock/perf_wt.lua "[开战后先打多少秒，默认 60] [测多少秒，默认 8] [map=snow]"
--   用户 11-28 晚「而且现在太卡了」：照真游戏的流程——点开战、匹配到了坐进车、准备阶段、开战，两队电脑车补满（每队 teamSize），
--   自己开着坦克往前走，量服务器每一步和客户端每个回调的开销、每帧的建 / 删 / 改属性 / 射线次数、远程事件数据量、场景里的实体和零件数
--   （准备阶段量一次、开战打一阵再量一次）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, Enum = T.R, T.Enum
local check = T.check
local K = dofile(MOCK_DIR .. "/perfkit.lua")(T)
local nums = {}
for x in TEST_ARGS:gmatch("%d+") do nums[#nums + 1] = tonumber(x) end
local warm, secs = nums[1] or 60, nums[2] or 8

T.mapName = TEST_ARGS:match("map=(%w+)") or "snow"
T.wtMode = true
T.matchMode = true
local G = T.boot()
G.Config.Match.wait = 3
local c0 = os.clock()
T.runUntil(function() return G.worldReady end, 900)
print(string.format("地图 %s 生成好了（模拟器 CPU %.1f 秒）", T.mapName, os.clock() - c0))
local me = T.join("P1", 7401, true)
T.runUntil(function() return G.round ~= nil end, 30)
local P = G.P[me]
T.leaveMenu()
R.run(1)
local key = G.treeLineup(P)[1]
T.act("matchJoin", key)
T.runUntil(function() return G.round.phase ~= "queue" end, 20)
T.runUntil(function() return P.vehicle ~= nil end, 15)
check(P.vehicle ~= nil, "匹配到了、坐进车 " .. tostring(key))
local C = T.C

local timed = { t = {}, n = {} }
K.wrap(C, "^step", "客户端 G.", timed)
K.wrap(G, "Step$", "服务器 G.", timed)
if G.flushFx then K.wrap(G, "^flushFx$", "服务器 G.", timed) end
for _, nm in ipairs({ "aiVehThink", "vehFindTarget" }) do
  if type(G[nm]) == "function" then K.wrap(G, "^" .. nm .. "$", "服务器 G.", timed) end
end

local function ents(title)
  local f = R.workspace:FindFirstChild("Ents")
  local cat, ai = {}, 0
  for _, em in ipairs(f and f:GetChildren() or {}) do
    local k = tostring(em:GetAttribute("Cat") or em._cls)
    cat[k] = (cat[k] or 0) + 1
    if em:GetAttribute("AI") then ai = ai + 1 end
  end
  local out = {}
  for k, v in pairs(cat) do out[#out + 1] = k .. " " .. v end
  table.sort(out)
  print(string.format("  %s 实体（Ents）：%s；电脑车 %d", title, table.concat(out, "，"), ai))
end

if G.round.phase == "prep" then
  R.run(4)
  ents("准备阶段")
  K.measure("准备阶段（坐在车里等）", math.min(secs, 4), timed)
end
T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10)
check(G.round.phase == "battle", "开战了")
print(string.format("开战后先打 %d 秒（步长 1/10）", warm))
R.run(warm, 1 / 10)
ents("打了一阵")
K.inventory("打了一阵", me)
if C.drive then T.key(Enum.KeyCode.W, true) end
K.measure("对战中开着坦克", secs, timed)
if C.drive then T.key(Enum.KeyCode.W, false) end
T.summary()
