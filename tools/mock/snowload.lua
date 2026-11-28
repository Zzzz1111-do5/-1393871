-- 雪山图后台写地形：真人身边先写、没人在场上写得快、没写到的块垫雪（模拟器）：python3 tools/mock/run.py tools/mock/snowload.lua
--   用户 11-28 晚截图「雪山图这一块一直加载不 这个图非常卡顿」：开服前只写两边基地一带，其余四千七百多块起伏地块在后台每帧 4 毫秒慢慢写
--   （一块六十多毫秒，全岛要十几二十分钟）；还没写到的块先垫一层薄底——原来一律铺在平地往下 8 格、用「沙」，这张图的沙是黑沙滩的深灰：
--   没写到的地方是一片深灰的大坑，车、树、靶车悬在半空。插队写的时候真人和十几辆电脑车身边的块混在一起排，真人身边那几块要跟两千多块抢。现在（World.lua）：
--   ① 一个真人都没在场上（都在机库、主菜单）：后台每帧 12 毫秒
--   ② 真人开的车开进还没写的谷里、十辆电脑车也在别处没写的地方：真人身边那块先写（比电脑车那边早），真人身边还有没写的时候每帧 8 毫秒
--   ③ 没写到的起伏块垫的是雪、按这一块最低的地面往下 3 格（不再是平地往下 8 格的深灰沙）
local T = dofile(MOCK_DIR .. "/common.lua")
pcall(function() io.stdout:setvbuf("line") end)
local R, V3 = T.R, T.V3
local check = T.check

T.mapName = "snow"
T.wtMode = true
local G = T.boot()
G.fortsHold = true
G.navyNoAI = true
G.aiVehOff = true
G.Config.Bots.minPerTeam = 0
T.runUntil(function() return G.worldReady end, 1200)
local Map = G.Map
R.voxelLog = {}
local f0 = #R.terrainFills
local me = T.join("P1", 9621, true)
T.runUntil(function() return G.P[me] ~= nil and G.P[me].data ~= nil end, 30)
local P = G.P[me]
R.run(1.5)

print("① 没人在场上（都在机库）")
check(P.alive ~= true, "P1 在机库（没出来）")
check(G.terrainBudget == 0.012, "后台每帧 12 毫秒（" .. tostring(G.terrainBudget) .. "）")

print("② 真人的车开进还没写的谷里，十辆电脑车在别处")
local CH = 256
local function covered(x, z, from)
  for i = from or 1, #R.voxelLog do
    local w = R.voxelLog[i]
    if w.x0 and x >= w.x0 and x < w.x1 and z >= w.z0 and z < w.z1 then return w.n end
  end
  return nil
end
-- 谷里还没写过的点：从谷中间往两边找（核心区是两头基地一带）
local spots = {}
for z = -2400, 2400, 600 do
  for x = -1200, 1200, 600 do
    if Map.isLand(x, z) and not covered(x, z) and math.abs(Map.height(x, z) - Map.PLAIN) < 30 then spots[#spots + 1] = V3(x, 0, z) end
  end
end
print("   谷里还没写的点 " .. #spots .. " 个")
check(#spots >= 11, "找得到十一处还没写的谷底")
local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
local id = "leo2a6"
local d = VD.get(id)
local function car(p)
  return G.newVehicle("atk", id, G.vehBaseAt(d, p.X, p.Z, V3(0, 0, -1)))
end
-- 电脑车先摆（先排进插队）
local ais = {}
for i = 2, math.min(11, #spots) do ais[#ais + 1] = car(spots[i]) end
R.run(1)
local mine = car(spots[1])
mine.driver = P   -- 当成 P1 开着（插队按真人算；车的步进没人坐时会把 driver 清掉，再打个试驾的记号：同样按真人算）
mine.testDrive = true
local n0 = R.stepNo or 0
local t0 = 0
local gotMine = nil
local sawMineBudget = false
local trace = {}
local nMine = nil   -- 插队扫到真人这辆车（真人身边有没写的块）是第几步
for i = 1, 400 do
  R.run(0.1)
  t0 = t0 + 0.1
  if G.terrainMinePending and G.terrainBudget == 0.008 then sawMineBudget = true end
  if G.terrainMinePending and not nMine then nMine = R.stepNo end
  if i % 5 == 0 then trace[#trace + 1] = string.format("%.1f:%s/%s", t0, tostring(G.terrainBudget), tostring(G.terrainMinePending)) end
  gotMine = gotMine or covered(spots[1].X, spots[1].Z)
  if gotMine then break end
end
print("   预算（秒：每帧 / 真人身边还有没写的）：" .. table.concat(trace, " "))
-- 插队扫到真人这辆车以后、真人车底下那块写到以前，电脑车底下写了几块（正在写的那一块不算插队）
local aiBefore = 0
for _, e in ipairs(ais) do
  local p = e.root.Position
  for _, w in ipairs(R.voxelLog) do
    if w.n and w.n > (nMine or n0) and gotMine and w.n < gotMine and w.x0 and p.X >= w.x0 and p.X < w.x1 and p.Z >= w.z0 and p.Z < w.z1 then aiBefore = aiBefore + 1 break end
  end
end
print(string.format("   真人车底下那块：第 %s 步写到（%.1f 秒）；这之前电脑车底下写了 %d 块", tostring(gotMine), t0, aiBefore))
check(gotMine ~= nil, "真人车底下那块写了（" .. string.format("%.1f", t0) .. " 秒内）")
check(nMine ~= nil and gotMine ~= nil and aiBefore <= 1, "比电脑车那边先写（扫到真人这辆车以后，电脑车底下只写完了正在写的那一块：" .. aiBefore .. "）")
check(sawMineBudget, "真人身边还有没写的时候：每帧 8 毫秒")

print("③ 没写到的起伏块垫的是雪")
local snowU, sandU = 0, 0
for i = f0 + 1, #R.terrainFills do
  local f = R.terrainFills[i]
  if f.k == "block" and f.size and math.abs(f.size.Y - 4) < 0.01 and math.abs(f.size.X - CH) < 0.01 and f.p.Y > 0 then   -- 地底下补的实心底（y −2）不算
    if f.mat == "Snow" then snowU = snowU + 1 elseif f.mat == "Sand" then
      -- 同 World.lua underlay：这一块 3 × 3 个点里最低的地面高过 2 格（不是海边）还垫沙就不对
      local x0, z0 = f.p.X - CH / 2, f.p.Z - CH / 2
      local lo = math.huge
      for i = 0, 2 do for k = 0, 2 do lo = math.min(lo, Map.voxelHeight(x0 + 16 + i * 112, z0 + 16 + k * 112)) end end
      if lo > 2 and Map.material(f.p.X, f.p.Z, lo, 0) ~= R.Enum.Material.Sand then sandU = sandU + 1 end   -- 海边（中间是黑沙滩）照旧垫沙
    end
  end
end
print(string.format("   垫雪 %d 块、陆地上还垫沙 %d 块", snowU, sandU))
check(snowU > 0 and sandU == 0, "陆地上没写到的块垫的是雪")
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 800))
T.summary()
