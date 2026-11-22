--!nocheck
-- 宣传片（海湾战争版，tools/trailer/film/gulf）用的沙漠地图数据：直接载入 ReplicatedStorage/MapSands.lua（地图「沙海」，id sands；原名 MapDesert.lua）（纯数学，不用开服），导出
--   height.bin / mat.bin       近处细网格：±FR、每 8 格一个（Float32 / Uint8，(N+1) × (N+1)，按 z 行 x 列）
--   height2.bin / mat2.bin     整张图粗网格：±SEA_R、每 32 格一个
--   world.json                 网格参数、材质表、锚点（据点、基地、机场、镇子、油田、油井、路、干河谷、沙墙、断崖……）
-- 用法（仓库根目录）：lune run tools/trailer/export_desert.luau <输出目录> [细网格半径，默认 14336]
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local outDir = assert(process.args[1], "用法：lune run tools/trailer/export_desert.luau <输出目录> [细网格半径]")
local FR = tonumber(process.args[2] or "14336")
if not fs.isDir(outDir) then fs.writeDir(outDir) end
local env = setmetatable({ Color3 = roblox.Color3, Enum = roblox.Enum, Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = _G })
local Map = luau.load(fs.readFile("src/ReplicatedStorage/MapSands.lua"), { debugName = "MapSands", environment = env })()

local mats, matId = {}, {}
local function mid(m)
  local k = m.Name
  if not matId[k] then table.insert(mats, k) matId[k] = #mats end
  return matId[k]
end
local function grid(R, step, name)
  local N = math.floor(2 * R / step)
  local n1 = N + 1
  local hb = buffer.create(n1 * n1 * 4)
  local mb = buffer.create(n1 * n1)
  local t0 = os.clock()
  for j = 0, N do
    local z = -R + j * step
    for i = 0, N do
      buffer.writef32(hb, (j * n1 + i) * 4, (Map.height(-R + i * step, z)))
    end
  end
  local function hAt(i, j) i = math.clamp(i, 0, N) j = math.clamp(j, 0, N) return buffer.readf32(hb, (j * n1 + i) * 4) end
  for j = 0, N do
    local z = -R + j * step
    for i = 0, N do
      local sx = (hAt(i + 1, j) - hAt(i - 1, j)) / (2 * step)
      local sz = (hAt(i, j + 1) - hAt(i, j - 1)) / (2 * step)
      buffer.writeu8(mb, j * n1 + i, mid(Map.material(-R + i * step, z, hAt(i, j), math.sqrt(sx * sx + sz * sz))))
    end
  end
  fs.writeFile(outDir .. "/height" .. name .. ".bin", hb)
  fs.writeFile(outDir .. "/mat" .. name .. ".bin", mb)
  print(string.format("%s：%d × %d，每 %d 格，%.1f 秒", name == "" and "细网格" or "粗网格", n1, n1, step, os.clock() - t0))
  return { R = R, step = step, n = n1 }
end
local fine = grid(FR, 8, "")
local coarse = grid(Map.SEA_R, 32, "2")

local function pt(p) return p and { x = p.x, z = p.z, y = p.y } or nil end
local meta = {
  map = "desert", R = fine.R, step = fine.step, n = fine.n, coarse = coarse, mats = mats, MAPR = Map.R,
  points = {}, airfield = Map.AIRFIELD, afield2 = Map.AFIELD2, command = pt(Map.COMMAND), camp = pt(Map.CAMP), town = pt(Map.TOWN),
  oilfield = pt(Map.OILFIELD), redbase = pt(Map.REDBASE), wells = Map.OILWELLS, starts = Map.STARTS, breach = Map.BREACH,
  roads = {}, wadis = Map.WADIS, sabkha = Map.SABKHA, passes = Map.PASSES, parts = {}, lights = {},
}
for _, p in ipairs(Map.POINTS) do table.insert(meta.points, { id = p.id, x = p.x, z = p.z, y = p.y }) end
for _, r in ipairs(Map.ROADS) do
  local pts = {}
  for i = 1, #r.x, 2 do table.insert(pts, { math.floor(r.x[i] + 0.5), math.floor(r.z[i] + 0.5), math.floor(r.y[i] * 10 + 0.5) / 10 }) end
  table.insert(meta.roads, { name = r.name, w = r.w, p = pts })
end
-- 沙墙、岩岭、断崖线（片子里摆哨塔、给镜头找位置用）
meta.berm, meta.ridge, meta.esc = {}, {}, {}
for x = -Map.R, Map.R, 256 do
  table.insert(meta.berm, { x, math.floor(Map.bermZ(x) + 0.5) })
  if x > -15000 and x < 14000 then table.insert(meta.ridge, { x, math.floor(Map.ridgeZ(x) + 0.5) }) end
  table.insert(meta.esc, { x, math.floor(Map.escZ(x) + 0.5) })
end
fs.writeFile(outDir .. "/world.json", serde.encode("json", meta))
print("写好了：" .. outDir)
