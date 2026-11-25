-- 沙海后台写地形不卡服务器（用户 11-25：「把抽搐bug弄完」——11-22 那条「加载地图的时候坦克飞机抽搐」）：python3 tools/mock/run.py tools/mock/terrainbg.lua [秒数]
--   开服前只写两边主基地一带，其余开打以后在后台写（World.lua terrainDesert）。原来后台的平地按矩形合并成一次 FillBlock（最大 2048 × 2048 × 16 格、
--   一百万体素），Roblox 铺一块要几十上百毫秒，「每帧 8 毫秒」拦不住单次调用——服务器停一下，车、飞机、人一抽。现在一小份一小份写：
--   ① 开服以后的每次 FillBlock 不超过 512 × 512 格见方（6.6 万体素）；起伏块一次只写 16 × 16 列
--   ② 每一步（服务器一帧）铺的地形有上限（测试台的时钟同一步里不走，按份数让：8 份一让）——比原来一步一百多万体素小一个数量级
--   ③ 后台照样往前写（剩下的块数在减少），据点、有人的地方先写
--   测试台量不出 Roblox 地形引擎真正的毫秒数；真游戏里开服输出窗口会打「后台单次 FillBlock 最长几毫秒、小块边长」
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local SECS = tonumber(TEST_ARGS:match("(%d+)")) or 40

local G = T.boot()
G.fortsHold = true
local me = T.join("P1", 7301, true)
local ok = T.runUntil(function() return G.worldReady end, 900)
check(ok and G.mapId == "sands", "沙海建好了")
local rest0 = G.terrainRest or 0
R.run(0.5)
local tiles0 = G.terrainTilesLeft or 0
print(string.format("  开服时后台还剩 %d 块（还没铺的大块 %d）", rest0, tiles0))

-- 从这里起记：每一步写了多少地形
local n0 = R.stepNo or 0
local f0 = #R.terrainFills
R.voxelLog = {}
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 60)
T.actAs(me, "deploy", "rifle", "base")
R.run(SECS)
local tiles1 = G.terrainTilesLeft or 0

local per, maxFill, maxFillSz, nFill = {}, 0, nil, 0
for i = f0 + 1, #R.terrainFills do
  local f = R.terrainFills[i]
  if f.k == "block" and f.n and f.n > n0 then
    local s = f.size
    local v = math.ceil(s.X / 4) * math.ceil(s.Y / 4) * math.ceil(s.Z / 4)
    nFill = nFill + 1
    if v > maxFill then maxFill, maxFillSz = v, s end
    per[f.n] = (per[f.n] or 0) + v
  end
end
local maxCols, nVox = 0, 0
for _, w in ipairs(R.voxelLog) do
  if w.n and w.n > n0 then
    nVox = nVox + 1
    if w.cols > maxCols then maxCols = w.cols end
    per[w.n] = (per[w.n] or 0) + w.v
  end
end
local maxStep, steps = 0, 0
for _, v in pairs(per) do
  steps = steps + 1
  if v > maxStep then maxStep = v end
end
print(string.format("  开打后 %d 秒：FillBlock %d 次、WriteVoxels %d 次，写过地形的步数 %d；单次 FillBlock 最大 %d 体素（%s），一步最多 %d 体素",
  SECS, nFill, nVox, steps, maxFill, maxFillSz and string.format("%.0f × %.0f × %.0f 格", maxFillSz.X, maxFillSz.Y, maxFillSz.Z) or "-", maxStep))
local d = G.terrainDiag or {}
print(string.format("  后台：FillBlock %s 次、起伏小份 %s 份、小块边长 %s 格", tostring(d.bgFills), tostring(d.bgPieces), tostring(d.side)))

print("① 开服以后一次只铺一小份")
check(nFill + nVox > 0, "开打以后后台在写地形（FillBlock " .. nFill .. " 次、WriteVoxels " .. nVox .. " 次）")
check(maxFill <= 128 * 4 * 128, string.format("单次 FillBlock 不超过 512 × 512 × 16 格（最大 %d 体素；原来整块 2048 格见方一次一百万）", maxFill))
check(maxCols <= 16 * 16, string.format("起伏块一次只写 16 × 16 列（最大 %d 列；原来 32 × 32）", maxCols))
print("② 每一步铺的地形有上限")
check(maxStep <= 8 * 128 * 4 * 128 + 200000, string.format("一步最多 %d 体素（上限约 72 万：8 份一让）", maxStep))
print("③ 后台照样往前写")
check(tiles1 < tiles0, string.format("后台还没铺的大块在减少（%d → %d）", tiles0, tiles1))
check(#R.errors == 0, "没有报错：" .. table.concat(R.errors, " | "):sub(1, 600))
T.summary()
