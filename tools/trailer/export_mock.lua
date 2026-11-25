-- 宣传片（tools/trailer）用的数据，在模拟器里导出（没有 Lune 的机器用；跟 export_world.luau、export_meta.luau 导出的一样）：
--   python3 tools/mock/run.py tools/trailer/export_mock.lua out=<输出目录> [step=8]
--   height.bin  地形高度（Float32，(N+1) × (N+1)，从 -R 到 +R、每 STEP 格一个，按 z 行 x 列；海底是负的，水面在 0）
--   mat.bin     地形材质（Uint8，同上；编号见 world.json 的 mats）
--   world.json  地图上的点、世界里的零件（形状、大小、位置、颜色、材质、透明度）、灯
--   meta.json   ImportedMeta / ImportedAir / ImportedShip（炮塔转轴、炮口、旋翼、尾喷口、舰炮……）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local outDir = assert(TEST_ARGS:match("out=(%S+)"), "要 out=<输出目录>")
local STEP = tonumber(TEST_ARGS:match("step=(%d+)") or "8")
os.execute('mkdir -p "' .. outDir .. '"')

---------------------------------------------------------------- JSON
local function enc(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif math.type(v) == "integer" or (v == math.floor(v) and math.abs(v) < 1e15) then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.6g", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    local n, cnt = #v, 0
    for _ in pairs(v) do cnt = cnt + 1 end
    if n > 0 and n == cnt then
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        enc(v[i], out)
      end
      out[#out + 1] = "]"
    elseif cnt == 0 then
      out[#out + 1] = "{}"
    else
      out[#out + 1] = "{"
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        enc(tostring(k), out)
        out[#out + 1] = ":"
        enc(v[k], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end
local function json(v) local o = {} enc(v, o) return table.concat(o) end
local function writeFile(name, s)
  local f = assert(io.open(outDir .. "/" .. name, "wb"))
  f:write(s)
  f:close()
end

---------------------------------------------------------------- 模型元数据
do
  local out = {}
  for _, k in ipairs({ "ImportedMeta", "ImportedAir", "ImportedShip" }) do
    local f = assert(io.open(SRC_DIR .. "/ReplicatedStorage/" .. k .. ".lua"))
    local src = f:read("a")
    f:close()
    out[k] = assert(load(src, k))()
  end
  -- 稀疏数组（挂点 [7]、[8]）的键转成字符串，JSON 才存得下
  local function clean(v)
    if type(v) ~= "table" then return v end
    local n, cnt = #v, 0
    for _ in pairs(v) do cnt = cnt + 1 end
    local o = {}
    if n > 0 and n == cnt then
      for i = 1, n do o[i] = clean(v[i]) end
    else
      for k, x in pairs(v) do o[tostring(k)] = clean(x) end
    end
    return o
  end
  writeFile("meta.json", json(clean(out)))
  print("写好了 meta.json")
end

---------------------------------------------------------------- 搭世界
local G = T.boot()
G.Config.Bots.minPerTeam = 0
G.fortsHold = true
G.navyNoAI = true
T.runUntil(function() return G.worldReady end, 160)
T.join("Cam", 9301, true)   -- 工事、舰艇、生成点的样子是客户端搭的（FortView、ShipView、Depot），有人在才会出现
R.run(6)
print("世界搭好了")
local Map = G.Map
local ws = R.services.Workspace

-- 地形
local RR = Map.R
local N = math.floor(2 * RR / STEP)
local n1 = N + 1
local hs = {}
local t0 = os.clock()
for j = 0, N do
  local z = -RR + j * STEP
  for i = 0, N do
    hs[j * n1 + i + 1] = Map.height(-RR + i * STEP, z)
  end
end
print(string.format("高度 %d × %d：%.1f 秒", n1, n1, os.clock() - t0))
local function hAt(i, j)
  i = math.max(0, math.min(N, i))
  j = math.max(0, math.min(N, j))
  return hs[j * n1 + i + 1]
end
local mats, matId = {}, {}
local function mid(m)
  local k = tostring(m)
  if not matId[k] then mats[#mats + 1] = k matId[k] = #mats end
  return matId[k]
end
local hb, mb = {}, {}
t0 = os.clock()
for j = 0, N do
  local z = -RR + j * STEP
  for i = 0, N do
    local x = -RR + i * STEP
    local y = hAt(i, j)
    local sx = (hAt(i + 1, j) - hAt(i - 1, j)) / (2 * STEP)
    local sz = (hAt(i, j + 1) - hAt(i, j - 1)) / (2 * STEP)
    local k = j * n1 + i + 1
    hb[k] = string.pack("<f", y)
    mb[k] = string.char(mid(Map.material(x, z, y, math.sqrt(sx * sx + sz * sz))))
  end
end
print(string.format("材质：%.1f 秒", os.clock() - t0))
writeFile("height.bin", table.concat(hb))
writeFile("mat.bin", table.concat(mb))
hb, mb = nil, nil

-- 地图上的点
local function pt(p) return p and { x = p.x or p.X, z = p.z or p.Z, y = p.y or p.Y } or nil end
local meta = { R = RR, step = STEP, n = n1, mats = mats, points = {}, beaches = Map.BEACHES, fleet = Map.FLEET, barge = Map.BARGE,
  airfield = Map.AIRFIELD, afield2 = Map.AFIELD2, command = pt(Map.COMMAND), camp = pt(Map.CAMP), port = pt(Map.PORT),
  main = Map.MAIN, isles = {}, landings = Map.LANDINGS }
for _, p in ipairs(Map.POINTS or {}) do meta.points[#meta.points + 1] = { id = p.id, x = p.x, z = p.z, y = p.y } end
for _, I in ipairs(Map.ISLES or {}) do
  local c = {}
  for k, v in pairs(I) do if type(v) == "number" or type(v) == "string" then c[k] = v end end
  meta.isles[#meta.isles + 1] = c
end
meta.coastS, meta.coastN = {}, {}
for x = -RR, RR, 16 do
  local s, n = Map.coastS and Map.coastS(x), Map.coastN and Map.coastN(x)
  if s then meta.coastS[#meta.coastS + 1] = { x, s } end
  if n then meta.coastN[#meta.coastN + 1] = { x, n } end
end

-- 世界里的零件和灯（不要人物）
local parts, lights = {}, {}
local function top(d)
  local p, q = d, nil
  while p.Parent and p.Parent ~= ws do q = p p = p.Parent end
  return q and (p.Name .. "/" .. q.Name) or p.Name
end
local function r4(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function cfArr(cf)
  local t = { cf:GetComponents() }
  for i, v in ipairs(t) do t[i] = r4(v) end
  return t
end
local skip = 0
for _, d in ipairs(ws:GetDescendants()) do
  if d:IsA("BasePart") and not d:IsA("Terrain") then
    local m = d:FindFirstAncestorOfClass("Model")
    if m and m:FindFirstChildOfClass("Humanoid") then
      skip = skip + 1
    else
      local shape = d:IsA("Part") and tostring(d.Shape) or d.ClassName
      local sm = d:FindFirstChildOfClass("SpecialMesh")
      if sm then shape = "Mesh:" .. tostring(sm.MeshType) end
      parts[#parts + 1] = { n = d.Name, g = top(d), k = d.ClassName, sh = shape,
        s = { r4(d.Size.X), r4(d.Size.Y), r4(d.Size.Z) }, cf = cfArr(d.CFrame),
        c = { r4(d.Color.R), r4(d.Color.G), r4(d.Color.B) }, m = tostring(d.Material), t = r4(d.Transparency),
        an = d:GetAttribute("Anim") }
    end
  elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
    local p = d.Parent
    if p and p:IsA("BasePart") then
      local L = { k = d.ClassName, cf = cfArr(p.CFrame), c = { r4(d.Color.R), r4(d.Color.G), r4(d.Color.B) },
        r = d.Range, b = d.Brightness, sh = d.Shadows, g = top(p), en = d.Enabled }
      if not d:IsA("PointLight") then L.a, L.f = d.Angle, tostring(d.Face) end
      lights[#lights + 1] = L
    end
  end
end
meta.parts, meta.lights = parts, lights
local function clean(v, depth)
  local t = R.typeof(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  if t == "Vector3" then return { v.X, v.Y, v.Z } end
  if t == "table" and depth < 8 then
    local o = {}
    for k, x in pairs(v) do
      if type(k) == "string" or type(k) == "number" then o[k] = clean(x, depth + 1) end
    end
    return o
  end
  return nil
end
writeFile("world.json", json(clean(meta, 0)))
print(string.format("零件 %d、灯 %d（跳过人物零件 %d）；材质 %s", #parts, #lights, skip, table.concat(mats, " ")))
