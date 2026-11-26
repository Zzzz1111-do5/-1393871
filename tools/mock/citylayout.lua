-- 钢城（MapCity.lua）的布局检查：python3 tools/mock/run.py tools/mock/citylayout.lua [out=<json>]
--   只载 ReplicatedStorage 的模块（不开服）：楼和楼不重叠、楼不压路、树不在路上 / 楼里、据点圈里空着、基地里空着、两边对称地离据点一样远；
--   out=：把路、楼、树、据点写成 JSON（tools/map/citypng.py 画成俯视图）
local T = dofile(MOCK_DIR .. "/common.lua")
local R = T.R
local check = T.check
local out = TEST_ARGS:match("out=(%S+)")

T.scripts = dofile(MOCK_DIR .. "/load.lua")(R, SRC_DIR)
local RS = R.services.ReplicatedStorage
local Map = R.require(RS:FindFirstChild("Map"))
check(Map.id == "city" and Map.CITY == true, "默认地图是钢城（" .. tostring(Map.id) .. "）")
local B, TR, S = Map.BLD, Map.TREES, Map.SEGS
print(string.format("  楼 / 设施 %d 座、路段 %d 段、树 %d 棵", #B, #S, #TR))
check(#B > 250 and #B < 2000, "楼的数量合适（" .. #B .. "）")
check(#TR > 1500 and #TR < 7000, "树的数量合适（" .. #TR .. "）")

-- 楼和楼不重叠（外接矩形；车厢只看和楼重不重）
local over = 0
local first = nil
for i = 1, #B do
  local a = B[i]
  for j = i + 1, #B do
    local b = B[j]
    if math.abs(a.x - b.x) < (a.w + b.w) / 2 - 0.5 and math.abs(a.z - b.z) < (a.d + b.d) / 2 - 0.5 then
      if not (a.k == "wagon" and b.k == "wagon") then
        over = over + 1
        first = first or string.format("%d(%s %.0f,%.0f %.0fx%.0f) × %d(%s %.0f,%.0f %.0fx%.0f)", a.id, a.k, a.x, a.z, a.w, a.d, b.id, b.k, b.x, b.z, b.w, b.d)
      end
    end
  end
end
check(over == 0, "楼和楼不重叠（" .. over .. " 处" .. (first and ("：" .. first) or "") .. "）")
-- 楼不压路（四角、四边中点、中心离路中线都超过半个路宽）
local onRoad, firstR = 0, nil
for _, b in ipairs(B) do
  for _, o in ipairs({ { 0, 0 }, { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 }, { 0, -0.5 }, { 0, 0.5 }, { -0.5, 0 }, { 0.5, 0 } }) do
    local x, z = b.x + o[1] * (b.w - 1), b.z + o[2] * (b.d - 1)
    if b.k ~= "wagon" and Map.onRoad(x, z, 0) then
      onRoad = onRoad + 1
      firstR = firstR or string.format("%d(%s %.0f,%.0f %.0fx%.0f)", b.id, b.k, b.x, b.z, b.w, b.d)
      break
    end
  end
end
check(onRoad == 0, "楼不压路（" .. onRoad .. " 座" .. (firstR and ("：" .. firstR) or "") .. "）")
-- 树：不在路上、不在楼里
local badT = 0
for _, t in ipairs(TR) do
  if Map.onRoad(t.x, t.z, 0) or Map.bldAt(t.x, t.z, 0) then badT = badT + 1 end
end
check(badT == 0, "树不在路上、楼里（" .. badT .. " 棵）")
-- 据点圈里没有楼、没有树
for _, p in ipairs(Map.POINTS) do
  local nb, nt = 0, 0
  for _, b in ipairs(B) do
    local dx = math.max(0, math.abs(p.x - b.x) - b.w / 2)
    local dz = math.max(0, math.abs(p.z - b.z) - b.d / 2)
    if dx * dx + dz * dz < Map.POINT_R ^ 2 then nb = nb + 1 end
  end
  for _, t in ipairs(TR) do if (t.x - p.x) ^ 2 + (t.z - p.z) ^ 2 < Map.POINT_R ^ 2 then nt = nt + 1 end end
  check(nb == 0 and nt == 0, string.format("据点 %s 圈里空着（楼 %d、树 %d）", p.id, nb, nt))
end
-- 两边基地里没有楼、没有树
local inBase = 0
for _, b in ipairs(B) do if Map.inBase(b.x, b.z, 60) then inBase = inBase + 1 end end
for _, t in ipairs(TR) do if Map.inBase(t.x, t.z, 60) then inBase = inBase + 1 end end
check(inBase == 0, "两边基地里没有楼、树（" .. inBase .. "）")
-- 统治那三个点（B / C / D）离两边基地一样远
local A, D = Map.BASES.atk, Map.BASES.def
for _, id in ipairs({ "B", "C", "D" }) do
  local p
  for _, q in ipairs(Map.POINTS) do if q.id == id then p = q end end
  local da = math.sqrt((p.x - A.x) ^ 2 + (p.z - A.z) ^ 2)
  local dd = math.sqrt((p.x - D.x) ^ 2 + (p.z - D.z) ^ 2)
  check(math.abs(da - dd) < 1, string.format("据点 %s 离两边基地一样远（%.0f / %.0f）", id, da, dd))
end
-- 寻路格子：城里的街中线上的格子没被楼占着
local blockedStreet = 0
for i = 0, 12 do
  local x = -Map.C0 + i * Map.GRID
  for z = -Map.C0, Map.C0, 64 do
    if Map.onRoad(x, z, 0) and Map.navBlocked(x, z) then blockedStreet = blockedStreet + 1 end
  end
end
check(blockedStreet == 0, "街中线上的寻路格子都能走（" .. blockedStreet .. " 格被占）")
-- 地形：平地块、高度
local K1, H1, M1 = Map.chunkKind(0, 0)
check(K1 == "flat" and H1 == Map.PLAIN, "城中心是平地块（" .. tostring(K1) .. "）")
local K2 = Map.chunkKind(9000, 0)
check(K2 == "relief", "东边丘陵是起伏块（" .. tostring(K2) .. "）")
check(math.abs(Map.height(0, 0) - Map.PLAIN) < 1e-6 and Map.height(9000, 0) > Map.PLAIN + 5, string.format("高度：城里 %.1f、丘陵 %.1f", Map.height(0, 0), Map.height(9000, 0)))
local _ = M1

if out then
  local f = io.open(out, "w")
  local parts = {}
  local function num(v) return string.format("%.1f", v) end
  table.insert(parts, '{"segs":[')
  for i, s in ipairs(S) do
    table.insert(parts, (i > 1 and "," or "") .. "[" .. num(s[1]) .. "," .. num(s[2]) .. "," .. num(s[3]) .. "," .. num(s[4]) .. "," .. num(s[5]) .. ',"' .. s[6] .. '"]')
  end
  table.insert(parts, '],"blds":[')
  for i, b in ipairs(B) do
    table.insert(parts, (i > 1 and "," or "") .. "[" .. num(b.x) .. "," .. num(b.z) .. "," .. num(b.w) .. "," .. num(b.d) .. "," .. num(b.h) .. "," .. b.st .. ',"' .. b.k .. '"]')
  end
  table.insert(parts, '],"trees":[')
  for i, t in ipairs(TR) do table.insert(parts, (i > 1 and "," or "") .. "[" .. num(t.x) .. "," .. num(t.z) .. "," .. num(t.s) .. "]") end
  table.insert(parts, '],"points":[')
  for i, p in ipairs(Map.POINTS) do table.insert(parts, (i > 1 and "," or "") .. '["' .. p.id .. '",' .. num(p.x) .. "," .. num(p.z) .. "]") end
  table.insert(parts, '],"bases":[')
  local n = 0
  for side, Bs in pairs(Map.BASES) do
    n = n + 1
    local r = Bs.rect
    table.insert(parts, (n > 1 and "," or "") .. '["' .. side .. '",' .. num(r.x0) .. "," .. num(r.z0) .. "," .. num(r.x1) .. "," .. num(r.z1) .. "," .. num(Bs.airfield.x) .. "," .. num(Bs.airfield.z) .. "," .. num(Bs.airfield.len) .. "," .. num(Bs.airfield.wid) .. "]")
  end
  table.insert(parts, '],"rail":[')
  for i, q in ipairs(Map.RAIL.path) do table.insert(parts, (i > 1 and "," or "") .. "[" .. num(q[1]) .. "," .. num(q[2]) .. "]") end
  table.insert(parts, "]}")
  f:write(table.concat(parts))
  f:close()
  print("  写好 " .. out)
end
T.summary()
