-- 寻路后台让帧（用户 11-22：加载地图的时候坦克飞机抽搐）：选沙漠图，量 Map.height 一次多久、Nav.lua 后台算网格 / 流场时一次占服务器多久
--   python3 tools/mock/run.py tools/mock/navslice.lua
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local G = T.boot()
G.fortsHold = true
local p1 = T.join("P1", 5101, true)
local C = T.C
R.run(2)
R.as("client", function() C.menuPlay() end)
R.run(0.3)
local card
for _, d in ipairs(p1.PlayerGui:GetDescendants()) do if d.Name == "Map_desert" then card = d end end
if card then T.press(card) end
-- 量后台寻路每段连续跑了多久：包一层 task.wait，记两次让帧之间过了多少 CPU 时间（只算 Nav 协程）
local worst, slices = 0, 0
local task = R.task
local realWait = task.wait
local navCo = nil
local last = nil
local origBuild = nil
T.runUntil(function() return G.navBuild ~= nil end, 60)
origBuild = G.navBuild
G.navBuild = function(...)
  local spawn0 = task.spawn
  task.spawn = function(f, ...)
    return spawn0(function(...)
      navCo = coroutine.running()
      last = os.clock()
      return f(...)
    end, ...)
  end
  local r = origBuild(...)
  task.spawn = spawn0
  return r
end
-- 模拟器的 os.clock 一帧之内不走：只给寻路协程看真时间（Roblox 里 os.clock 是真的 CPU 时间，Nav.lua 按它每帧算 4 毫秒就让）
local cpu, over = 0, 0   -- over：超过 8 毫秒的段数（大表扩容那一下会长一点）
R.clockHook = function()
  if navCo and coroutine.running() == navCo then return os.clock() end
end
task.wait = function(...)
  if navCo and coroutine.running() == navCo and last then
    local d = os.clock() - last
    if d > worst then worst = d end
    cpu = cpu + d
    if d > 0.008 then over = over + 1 end
    slices = slices + 1
  end
  local r = realWait(...)
  if navCo and coroutine.running() == navCo then last = os.clock() end
  return r
end
T.runUntil(function() return G.worldReady end, 1800)
check(G.mapId == "desert" and G.worldReady, "沙漠图建好了")
local Map = G.Map or R.require(R.services.ReplicatedStorage:FindFirstChild("Map"))
local t0 = os.clock()
local n = 0
for i = 1, 20000 do
  local x, z = (i * 37) % 60000 - 30000, (i * 91) % 60000 - 30000
  n = n + Map.height(x, z)
end
local per = (os.clock() - t0) / 20000
print(string.format("  Map.height 一次 %.1f 微秒（模拟器的 Lua，Roblox 的 Luau 快几倍）；原来一帧 20 行 × 655 格 = 13100 次 ≈ %.0f 毫秒", per * 1e6, per * 13100 * 1000))
T.runUntil(function() return G.navReady end, 3000)
check(G.navReady == true, "寻路算完了")
R.clockHook = nil
print(string.format("  寻路后台：让了 %d 次帧，一共算了 %.1f 秒，最长一段连续算了 %.1f 毫秒，超过 8 毫秒的 %d 段", slices, cpu, worst * 1000, over))
-- 流场指纹：改写堆、边代价前后应一样（同一张图、同一个种子）
if G.navFinger then print("  流场指纹 " .. G.navFinger()) end
-- 原来（每 20 行、每出堆 1500 次才让）这里最长 110 毫秒
check(worst < 0.025, string.format("寻路后台每段不超过 25 毫秒（%.1f 毫秒；每帧按 4 毫秒让，模拟器的 Lua 比 Luau 慢）", worst * 1000))
check(over <= 12, string.format("超过 8 毫秒的段只有偶尔几段（%d 段）", over))
T.summary()
