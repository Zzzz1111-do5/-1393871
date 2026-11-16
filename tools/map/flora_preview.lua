-- 树林、花地、石头分布的俯视预览：python3 tools/mock/run.py tools/map/flora_preview.lua <目录>，再 python3 -I tools/map/preview.py <目录>
local R = dofile(MOCK_DIR .. "/rbx.lua")
dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local Map = R.require(RS.Map)
local Flora = R.require(RS.Flora)
local OUT = TEST_ARGS:match("%S+")
local MI = Map.MAIN
local C = Flora.CELL
local f = assert(io.open(OUT .. "/map_trees.txt", "w"))
local count = {}
local t0 = os.clock()
local cells = 0
for cz = math.floor((MI.z - MI.N - 80) / C), math.floor((MI.z + MI.S + 200) / C) do
  for cx = math.floor((MI.x - MI.hs) / C), math.floor((MI.x + MI.hs) / C) do
    cells = cells + 1
    for _, layer in ipairs({ "tree", "bush", "rock" }) do
      for _, it in ipairs(Flora.cell(cx, cz, layer)) do
        count[it.k] = (count[it.k] or 0) + 1
        local t = (layer == "rock") and "r" or ((it.k:match("^fir") or it.k == "pine" or it.k == "nfir") and "c" or (layer == "bush" and "b" or "d"))
        f:write(string.format("%s %.0f %.0f\n", t, it.x, it.z))
      end
    end
    if cx % 2 == 0 and cz % 2 == 0 then   -- 花只抽样画（四分之一的格子）
      for _, it in ipairs(Flora.cell(cx, cz, "flower")) do
        count.flowers = (count.flowers or 0) + 1
        f:write(string.format("f %.0f %.0f\n", it.x, it.z))
      end
    end
  end
end
f:close()
local t = {}
for k, v in pairs(count) do t[#t + 1] = k .. " " .. v end
table.sort(t)
print(string.format("%d 格，用了 %.1f 秒（每格 %.1f 毫秒）", cells, os.clock() - t0, (os.clock() - t0) / cells * 1000))
print(table.concat(t, "，"))
TEST_CODE = 0
