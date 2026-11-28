-- 烘焙地形（模拟器）：python3 tools/mock/run.py tools/mock/terrainbake.lua part=1|2|3
--   用户 11-28 夜「然后卡顿问题你给他想办法解决」：雪山图开服后十几二十分钟一直在后台写地形（服务器占着、客户端一直重建地形网格）。
--   World.bake（Studio 编辑模式的命令栏跑 TerrainBake）把整张地形一次写全、记下 Terrain 的属性 Baked = 「图 | 地形版本」，存档以后开服不再写：
--   ① part=1 烘焙：先清掉，整张图每一块起伏地块都写了、不垫底，记下 Baked = snow|版本
--   ② part=2 地点文件里烘好了同一张图、同一版本：开服不写地形（只量网格器那一小块），后台没有剩的，马上 worldReady
--   ③ part=3 烘的是旧版本：Output 里提示，清掉，照旧开服现写（后台还有剩的）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R = T.R
local check = T.check
local PART = tonumber(TEST_ARGS:match("part=(%d)") or "1") or 1
-- 开服前（脚本还没装进模拟的游戏里）：地形版本号照源文件读
local VER
do
  local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/MapSnow.lua"))
  VER = f:read("a"):match('Map%.TERRAIN_VER = "([^"]+)"')
  f:close()
end
local function mapVoxelWrites(from)
  local n = 0
  for i = from or 1, #(R.voxelLog or {}) do
    local w = R.voxelLog[i]
    if w.x0 and math.abs(w.x0) < 20000 and (w.y0 == nil or true) then n = n + 1 end
  end
  return n
end

T.mapName = "snow"
if PART == 2 or PART == 3 then
  -- 地点文件里已经有烘好的地形（存档带着 Terrain 的属性）：照 MapSnow 的版本号写，第三部分写个旧的
  local key = "snow|" .. tostring(VER)
  R.workspace.Terrain:SetAttribute("Baked", (PART == 2) and key or "snow|old")
end
R.voxelLog = {}
local G = T.boot()
T.runUntil(function() return G.worldReady end, 1200)

if PART == 1 then
  print("① 烘焙")
  local World = R.require(R.services.ServerScriptService:FindFirstChild("Main"):FindFirstChild("World"))
  local Map = G.Map
  local nRel = 0
  local C = Map.COLL
  for x0 = C.x0, C.x1 - 256, 256 do
    for z0 = C.z0, C.z1 - 256, 256 do
      if Map.chunkKind(x0, z0) ~= "flat" then nRel = nRel + 1 end
    end
  end
  local cl0 = R.terrainCleared or 0
  local f0 = #R.terrainFills
  local v0 = #R.voxelLog
  local done, chunks = false, 0
  R.as("server", function()
    R.task.spawn(function()
      local _, c = World.bake("snow")
      chunks = c or 0
      done = true
    end)
  end)
  T.runUntil(function() return done end, 3000, 0.5)
  check(done, "烘焙做完了")
  check((R.terrainCleared or 0) > cl0, "先清掉原来的地形")
  -- 每一块起伏地块都写了（256 格见方：按写入记录的那一片落在哪一块数）
  local seenC = {}
  for i = v0 + 1, #R.voxelLog do
    local w = R.voxelLog[i]
    if w.x0 then seenC[math.floor(w.x0 / 256) * 100000 + math.floor(w.z0 / 256)] = true end
  end
  local miss = 0
  for x0 = C.x0, C.x1 - 256, 256 do
    for z0 = C.z0, C.z1 - 256, 256 do
      if Map.chunkKind(x0, z0) ~= "flat" and not seenC[math.floor(x0 / 256) * 100000 + math.floor(z0 / 256)] then miss = miss + 1 end
    end
  end
  print(string.format("   起伏地块 %d 块，没写到的 %d 块", nRel, miss))
  check(miss == 0, "每一块起伏地块都写了")
  local under = 0
  for i = f0 + 1, #R.terrainFills do
    local f = R.terrainFills[i]
    if f.k == "block" and f.size and math.abs(f.size.Y - 4) < 0.01 and math.abs(f.size.X - 256) < 0.01 and f.p.Y > 0 then under = under + 1 end
  end
  check(under == 0, "不垫底（" .. under .. " 块）")
  check(R.workspace.Terrain:GetAttribute("Baked") == "snow|" .. tostring(Map.TERRAIN_VER), "记下 Baked = " .. tostring(R.workspace.Terrain:GetAttribute("Baked")))
elseif PART == 2 then
  print("② 烘好了同一张图、同一版本：开服不写地形")
  check(G.terrainBaked == true, "认出烘好的地形")
  check((G.terrainRest or 0) == 0, "后台没有剩的（" .. tostring(G.terrainRest) .. "）")
  local deep = 0
  local mapW = 0
  for _, w in ipairs(R.voxelLog) do
    if w.x0 then mapW = mapW + 1 end
  end
  -- 量网格器的试验平台在地图正下方很深的地方写几小块；地图本身一块都不写
  local fills = 0
  for _, f in ipairs(R.terrainFills) do
    if f.k == "block" and f.p and f.p.Y > -500 then fills = fills + 1 end
  end
  print(string.format("   开服写体素 %d 次（只有量网格器的平台）、地图上 FillBlock %d 次", mapW, fills))
  check(fills == 0, "地图上一次 FillBlock 都没有")
  check((R.terrainCleared or 0) == 0, "没有清地形")
else
  print("③ 烘的是旧版本：清掉、照旧现写")
  check(G.terrainBaked ~= true, "不当成烘好的")
  check((R.terrainCleared or 0) >= 1, "清掉了")
  local warned = false
  for _, w in ipairs(R.warns) do if tostring(w):find("烘焙的地形是", 1, true) then warned = true end end
  check(warned, "Output 里提示（烘的是哪一版、怎么重新烘）")
  check(R.workspace.Terrain:GetAttribute("Baked") == nil, "Baked 去掉了")
  check((G.terrainRest or 0) > 0, "后台照旧在写（还剩 " .. tostring(G.terrainRest) .. " 项）")
end
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
