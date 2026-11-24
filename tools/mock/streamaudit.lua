-- 流式加载前的家底（模拟器）：python3 -u tools/mock/run.py tools/mock/streamaudit.lua
--   用户 11-24 夜：「这个地图加载为什么这么慢」→「那就按照这个做」——开流式加载前先数清楚：开服以后 workspace 里每个文件夹有多少零件、
--   哪些是对局要用的（实体、据点、舰队）、哪些只是摆设（地形上的房子、掩体、残骸），地形写了多少体素
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check

local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.Config.Bots.minPerTeam = 0
local t0 = os.clock()
T.runUntil(function() return G.worldReady end, 900)
print(string.format("地图好了（模拟器墙钟 %.0f 秒）：%s 块地形、%s 个体素", os.clock() - t0, tostring(G.terrainChunks), tostring(G.terrainVoxels)))

local function count(inst)
  local parts, all = 0, 0
  for _, d in ipairs(inst:GetDescendants()) do
    all = all + 1
    if d:IsA("BasePart") then parts = parts + 1 end
  end
  return parts, all
end
local ws = R.services.Workspace
local total = 0
for _, c in ipairs(ws:GetChildren()) do
  local p, a = count(c)
  total = total + p
  print(string.format("workspace.%s（%s）：%d 个零件、%d 个实例", c.Name, c.ClassName, p, a))
  if c.Name == "Map" then
    for _, f in ipairs(c:GetChildren()) do
      local p2, a2 = count(f)
      print(string.format("  Map.%s：%d 个零件、%d 个实例", f.Name, p2, a2))
      if f.Name == "Scenery" then
        for _, g in ipairs(f:GetChildren()) do
          local p3, a3 = count(g)
          if p3 > 50 then print(string.format("    Scenery.%s（%s）：%d 个零件、%d 个实例", g.Name, g.ClassName, p3, a3)) end
        end
      end
    end
  end
end
print("零件合计 " .. total)
check(G.worldReady == true, "地图建好了")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "))
T.summary()
