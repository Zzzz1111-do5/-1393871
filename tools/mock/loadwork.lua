-- 沙海进入速度（用户 11-24：「验证一下这个沙海地图进入速度是否变快了」）：数开服到「能进」（G.worldReady）之前地形引擎要做多少活——
--   FillBlock 次数和体素、WriteVoxels 体素。真 Roblox 里卡在「正在生成地图……%」的就是这些活，模拟器的秒数只是 Lua 跑得快慢、不算数；
--   真的秒数看 Studio 输出里那行「[地形] 开服前写了基地一带：…」
--   python3 tools/mock/run.py tools/mock/loadwork.lua          只量开服前
--   python3 tools/mock/run.py tools/mock/loadwork.lua bg=1     再量后台把整张图铺完（模拟器里要跑二十来分钟）
-- 旧版本对比：git worktree add <目录> <提交>，在那个目录里跑同一个文件（这个文件不依赖版本，旧版本没有就拷过去）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local wall0 = os.clock()
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
if G.Config and G.Config.Bots then G.Config.Bots.minPerTeam = 0 end
local function snap()
  local n, vox = 0, 0
  for _, f in ipairs(R.terrainFills) do
    if f.k == "block" then
      n = n + 1
      local s = f.size
      vox = vox + math.ceil(s.X / 4 - 1e-6) * math.ceil(s.Y / 4 - 1e-6) * math.ceil(s.Z / 4 - 1e-6)
    end
  end
  return n, vox, R.voxelsWritten or 0
end
local sim = 0
while not G.worldReady and sim < 900 do R.run(1 / 30, 1 / 30) sim = sim + 1 / 30 end
local wall1 = os.clock()
local n1, v1, w1 = snap()
print(string.format("开服前：FillBlock %d 次（%.3f 亿体素），WriteVoxels %.3f 亿体素；模拟 %.1f 秒、墙钟 %.1f 秒；后台还剩 %s 项",
  n1, v1 / 1e8, w1 / 1e8, sim, wall1 - wall0, tostring(G.terrainRest)))
if not (TEST_ARGS or ""):match("bg=1") then return end
local sim2 = 0
while sim2 < 1500 do
  if G.terrainRest == 0 then break end
  R.run(1 / 15, 1 / 15)
  sim2 = sim2 + 1 / 15
end
local n2, v2, w2 = snap()
print(string.format("后台铺完（连开服前一共）：FillBlock %d 次（%.3f 亿体素），WriteVoxels %.3f 亿体素；模拟 %.0f 秒（模拟器的时钟一步里不走，这个数只看让了多少帧，不是真秒数）；还剩 %s 项",
  n2, v2 / 1e8, w2 / 1e8, sim2, tostring(G.terrainRest)))
