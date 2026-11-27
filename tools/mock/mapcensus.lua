-- 地图零件普查（模拟器）：python3 tools/mock/run.py tools/mock/mapcensus.lua [map=city]
--   用户 11-26 晚「游戏很卡顿」：渲染的负担主要是零件个数、投影子的零件、半透明零件。按地图下面的分组（第二层的名字去掉编号）
--   数零件、投影子的、半透明的，再按零件大小分档，看哪一类该关阴影、合并、远处换替身
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
T.mapName = TEST_ARGS:match("map=(%w+)") or "city"
local G = T.boot()
T.runUntil(function() return G.worldReady end, 900)
R.run(1)

local function isPart(c) return R.base.IsA(c, "BasePart") end
local groups, sizes = {}, {}
local total, shadowT = 0, 0
local function bucket(sz)
  local m = math.max(sz.X, sz.Y, sz.Z)
  if m < 2 then return "a <2"
  elseif m < 6 then return "b 2-6"
  elseif m < 16 then return "c 6-16"
  elseif m < 48 then return "d 16-48"
  else return "e >48" end
end
local function nm(c) return (tostring(c._p.Name or c._cls):gsub("[%d_%-]+$", "")) end
local function walk(o, key, depth)
  depth = depth or 1
  for _, c in ipairs(o._kids) do
    local k = key
    if depth == 1 then k = nm(c)
    elseif depth == 2 then k = key .. "/" .. nm(c) end
    if isPart(c) then
      total = total + 1
      local g = groups[k] or { n = 0, sh = 0, tr = 0, mesh = 0, b = {} }
      groups[k] = g
      g.n = g.n + 1
      if c._cls == "MeshPart" then g.mesh = g.mesh + 1 end
      local sh = c._p.CastShadow ~= false and (c._p.Transparency or 0) < 1
      if sh then g.sh = g.sh + 1 shadowT = shadowT + 1 end
      local tr = c._p.Transparency or 0
      if tr > 0 and tr < 1 then g.tr = g.tr + 1 end
      local sz = c._p.Size
      if sz and sh then
        local b = bucket(sz)
        g.b[b] = (g.b[b] or 0) + 1
        sizes[b] = (sizes[b] or 0) + 1
      end
    end
    walk(c, k, depth + 1)
  end
end
print("地图：" .. tostring(G.mapId))
for _, top in ipairs(R.workspace._kids) do
  if top._p.Name == "Map" then
    walk(top)
  end
end
print(string.format("Map 下零件 %d 个，投影子的 %d 个", total, shadowT))
local rows = {}
for k, g in pairs(groups) do rows[#rows + 1] = { k = k, g = g } end
table.sort(rows, function(a, b) return a.g.n > b.g.n end)
for i = 1, math.min(40, #rows) do
  local r = rows[i]
  local bs = {}
  for _, b in ipairs({ "a <2", "b 2-6", "c 6-16", "d 16-48", "e >48" }) do
    if r.g.b[b] then bs[#bs + 1] = b .. ":" .. r.g.b[b] end
  end
  print(string.format("  %-34s 零件 %6d  投影 %6d  半透明 %4d  网格 %5d  投影的按大小 %s", r.k, r.g.n, r.g.sh, r.g.tr, r.g.mesh, table.concat(bs, " ")))
end
local bs = {}
for _, b in ipairs({ "a <2", "b 2-6", "c 6-16", "d 16-48", "e >48" }) do bs[#bs + 1] = b .. ":" .. (sizes[b] or 0) end
print("投影子的零件按最长边（格）：" .. table.concat(bs, "  "))
T.summary()
