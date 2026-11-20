-- 场景负担清单（模拟器）：python3 tools/mock/run.py tools/mock/perf_scene.lua
--   BillboardGui / 灯 / 粒子 / 没锚定的零件都挂在哪、开没开阴影——找渲染和物理的大头
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7301, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
R.run(3)
local function path(o, depth)
  local t = {}
  local a = o
  while a and a ~= R.workspace and #t < (depth or 4) do
    table.insert(t, 1, a._p.Name)
    a = rawget(a, "_parent")
  end
  return table.concat(t, "/")
end
local function group(cls, depth, filter)
  local m, n = {}, 0
  for _, o in ipairs(R.workspace:GetDescendants()) do
    if o._cls == cls and (not filter or filter(o)) then
      n = n + 1
      local par = rawget(o, "_parent")
      local k = path(par, depth)
      m[k] = (m[k] or 0) + 1
    end
  end
  local rows = {}
  for k, v in pairs(m) do rows[#rows + 1] = { k = k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  print(string.format("%s：%d 个", cls, n))
  for i = 1, math.min(10, #rows) do print(string.format("  %5d  %s", rows[i].v, rows[i].k)) end
end
group("BillboardGui", 2)
group("UICorner", 2)
group("PointLight", 2)
group("PointLight", 2, function(o) return o._p.Shadows == true end)
group("SpotLight", 2)
group("SurfaceLight", 2)
group("ParticleEmitter", 2)
group("Part", 1, function(o) return o._p.Anchored ~= true end)
group("MeshPart", 1, function(o) return o._p.Anchored ~= true end)
-- 投影子的零件按所在文件夹、按大小（最长边）分
do
  local m, sz = {}, { 0, 0, 0, 0 }
  for _, o in ipairs(R.workspace:GetDescendants()) do
    if R.base.IsA(o, "BasePart") and o._p.CastShadow ~= false and (o._p.Transparency or 0) < 1 then
      local k = path(rawget(o, "_parent"), 2)
      m[k] = (m[k] or 0) + 1
      local s = o._p.Size
      local L = s and math.max(s.X, s.Y, s.Z) or 4
      if L < 2 then sz[1] = sz[1] + 1 elseif L < 6 then sz[2] = sz[2] + 1 elseif L < 20 then sz[3] = sz[3] + 1 else sz[4] = sz[4] + 1 end
    end
  end
  local rows = {}
  for k, v in pairs(m) do rows[#rows + 1] = { k = k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  print(string.format("投影子的零件：最长边 <2 格 %d，2～6 %d，6～20 %d，≥20 %d", sz[1], sz[2], sz[3], sz[4]))
  for i = 1, math.min(14, #rows) do print(string.format("  %5d  %s", rows[i].v, rows[i].k)) end
end
local L = R.services.Lighting
print("Lighting：", tostring(L._p.Technology), "GlobalShadows", tostring(L._p.GlobalShadows), "ShadowSoftness", tostring(L._p.ShadowSoftness))
for _, c in ipairs(L:GetChildren()) do io.write(c._cls, " ") end
print()
local bb = nil
for _, o in ipairs(R.workspace:GetDescendants()) do if o._cls == "BillboardGui" then bb = o break end end
if bb then
  print("第一个 BillboardGui：", path(bb, 6), "AlwaysOnTop", tostring(bb._p.AlwaysOnTop), "MaxDistance", tostring(bb._p.MaxDistance), "Enabled", tostring(bb._p.Enabled))
  for _, c in ipairs(bb:GetDescendants()) do io.write(c._cls, ":", c._p.Name, " ") end
  print()
end
T.summary()
