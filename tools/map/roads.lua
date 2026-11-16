-- 路网：离线算好写进 src/ReplicatedStorage/MapRoads.lua（开服时服务器、客户端都按它压平路面、换土路材质）
--   用法（仓库根目录）：python3 tools/mock/run.py tools/map/roads.lua [预览图目录]
--   按坡度找路（A*，12 格一格，八方向）：代价 = 距离 ×（1 + 坡度惩罚），坡太陡、海里、海滩沙地不走；绕开工事；后面的路走到已有的路上便宜一半（自然并到一起）
--   路线先抽稀（道格拉斯—普克）再倒角平滑（Chaikin 两遍），最后每 ≤ 20 格一个点
--   连接：营地—指挥所（翻过中央山脊的山口）、指挥所—港口镇、指挥所—机场、南岸沿海公路（红滩—港口镇—白滩—蓝滩—金滩—机场）、营地—东北侧翼滩、营地往西沿北岸一段
local SRC = SRC_DIR
local R = dofile(MOCK_DIR .. "/rbx.lua")
dofile(MOCK_DIR .. "/load.lua")(R, SRC)
local RS = R.services.ReplicatedStorage
local old = RS:FindFirstChild("MapRoads")
if old then old:Destroy() end   -- 按没有路的地形算
local Map = R.require(RS.Map)
local FortDefs = R.require(RS.FortDefs)
local OUT = TEST_ARGS:match("%S+")

local CELL = 12
local MI = Map.MAIN
local X0, X1 = MI.x - MI.hs, MI.x + MI.hs
local Z0, Z1 = MI.z - MI.N - 80, MI.z + MI.S + 220
local NX, NZ = math.floor((X1 - X0) / CELL) + 1, math.floor((Z1 - Z0) / CELL) + 1
local function cx(i) return X0 + i * CELL end
local function cz(k) return Z0 + k * CELL end
local function id(i, k) return k * NX + i end

-- 每格的高度（先算好）
local H = {}
for k = 0, NZ - 1 do
  for i = 0, NX - 1 do H[id(i, k)] = Map.height(cx(i), cz(k)) end
end
local function slopeAt(i, k)
  if i <= 0 or k <= 0 or i >= NX - 1 or k >= NZ - 1 then return 1 end
  local gx = (H[id(i + 1, k)] - H[id(i - 1, k)]) / (2 * CELL)
  local gz = (H[id(i, k + 1)] - H[id(i, k - 1)]) / (2 * CELL)
  return math.sqrt(gx * gx + gz * gz)
end

-- 工事（碉堡、岸防炮、高炮、炮位）：离它 30 格以内很贵
local forts = FortDefs.layout(Map)
local fortPts = {}
for _, f in ipairs(forts) do
  local p = f.pos or (f.cf and f.cf.Position)
  if p then table.insert(fortPts, { p.X, p.Z }) end
end
print("工事 " .. #fortPts .. " 处")
local penalty = {}
for k = 0, NZ - 1 do
  for i = 0, NX - 1 do
    local x, z = cx(i), cz(k)
    local p = 0
    for _, f in ipairs(fortPts) do
      local d = math.sqrt((x - f[1]) ^ 2 + (z - f[2]) ^ 2)
      if d < 34 then p = p + 400 * (1 - d / 34) end
    end
    penalty[id(i, k)] = p
  end
end

local onRoad = {}   -- 已经有路的格：再走便宜
local function cellOf(x, z) return math.floor((x - X0) / CELL + 0.5), math.floor((z - Z0) / CELL + 0.5) end

-- 二叉堆
local function heapPush(h, n, f)
  h.n = h.n + 1
  local i = h.n
  h[i] = { n, f }
  while i > 1 do
    local p = i // 2
    if h[p][2] <= h[i][2] then break end
    h[p], h[i] = h[i], h[p]
    i = p
  end
end
local function heapPop(h)
  if h.n == 0 then return nil end
  local top = h[1]
  h[1] = h[h.n]
  h[h.n] = nil
  h.n = h.n - 1
  local i = 1
  while true do
    local l, r, m = i * 2, i * 2 + 1, i
    if l <= h.n and h[l][2] < h[m][2] then m = l end
    if r <= h.n and h[r][2] < h[m][2] then m = r end
    if m == i then break end
    h[m], h[i] = h[i], h[m]
    i = m
  end
  return top[1], top[2]
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local function route(ax, az, bx, bz)
  local si, sk = cellOf(ax, az)
  local ti, tk = cellOf(bx, bz)
  local start, goal = id(si, sk), id(ti, tk)
  local g, came, closed = { [start] = 0 }, {}, {}
  local h = { n = 0 }
  local function hEst(i, k) return math.sqrt((i - ti) ^ 2 + (k - tk) ^ 2) * CELL * 0.6 end
  heapPush(h, start, hEst(si, sk))
  local nPop = 0
  while true do
    local cur = heapPop(h)
    if not cur then return nil end
    if cur == goal then break end
    if not closed[cur] then
      closed[cur] = true
      nPop = nPop + 1
      local i, k = cur % NX, cur // NX
      local h0 = H[cur]
      for _, d in ipairs(DIRS) do
        local ni, nk = i + d[1], k + d[2]
        if ni > 0 and nk > 0 and ni < NX - 1 and nk < NZ - 1 then
          local n = id(ni, nk)
          if not closed[n] then
            local hn = H[n]
            local L = (d[1] ~= 0 and d[2] ~= 0) and CELL * 1.4142 or CELL
            local nearEnd = math.abs(ni - ti) + math.abs(nk - tk) <= 4 or math.abs(ni - si) + math.abs(nk - sk) <= 4
            local grade = math.abs(hn - h0) / L
            local ok = hn > 0.9 and grade < 0.5
            if ok then
              local sl = slopeAt(ni, nk)
              local c = L * (1 + 45 * grade * grade + 6 * math.max(0, sl - 0.2) + 160 * math.max(0, grade - 0.16)) + penalty[n] * L / CELL
              if hn < 2.4 and not nearEnd then c = c + L * 8 end   -- 海滩沙地、水边：能不走就不走
              if onRoad[n] then c = c * 0.45 end
              local ng = g[cur] + c
              if not g[n] or ng < g[n] then
                g[n] = ng
                came[n] = cur
                heapPush(h, n, ng + hEst(ni, nk))
              end
            end
          end
        end
      end
    end
  end
  local path = {}
  local c = goal
  while c do
    table.insert(path, 1, { cx(c % NX), cz(c // NX) })
    c = came[c]
  end
  path[1] = { ax, az }
  path[#path] = { bx, bz }
  return path
end

-- 抽稀：道格拉斯—普克（容差 tol 格）
local function simplify(pts, tol)
  local keep = { [1] = true, [#pts] = true }
  local function rec(a, b)
    local ax, az, bx, bz = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
    local dx, dz = bx - ax, bz - az
    local L = math.sqrt(dx * dx + dz * dz)
    local best, bi = 0, nil
    for i = a + 1, b - 1 do
      local px, pz = pts[i][1] - ax, pts[i][2] - az
      local d = (L > 0) and math.abs(px * dz - pz * dx) / L or math.sqrt(px * px + pz * pz)
      if d > best then best, bi = d, i end
    end
    if bi and best > tol then
      keep[bi] = true
      rec(a, bi)
      rec(bi, b)
    end
  end
  rec(1, #pts)
  local out = {}
  for i, p in ipairs(pts) do if keep[i] then table.insert(out, p) end end
  return out
end
-- 倒角平滑（端点不动）
local function chaikin(pts)
  local out = { pts[1] }
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    table.insert(out, { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 })
    table.insert(out, { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 })
  end
  table.insert(out, pts[#pts])
  return out
end
local function resample(pts, step)
  local out = { pts[1] }
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local L = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    local n = math.max(1, math.ceil(L / step))
    for k = 1, n do
      local t = k / n
      table.insert(out, { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t })
    end
  end
  return out
end

---------------------------------------------------------------- 连接

local B = {}
for _, b in ipairs(Map.BEACHES) do B[b.id] = b end
local function beachExit(id)   -- 海滩后面、沙地以上
  local b = B[id]
  local dir = b.north and 1 or -1   -- 往岛里走
  for d = 90, 260, 10 do
    local z = b.z + dir * d
    if Map.height(b.cx, z) > 3.5 then return { b.cx, z + dir * 15 } end
  end
  return { b.cx, b.z + dir * 200 }
end
local C, E, D, P = Map.CAMP, Map.COMMAND, Map.AIRFIELD, Map.PORT
local camp = { C.x, C.z + 15 + 80 }   -- 营地南边（车场一侧）
local cmd = { E.x, E.z }
local port = { P.x, P.z - 60 }
local afd = { D.x - D.len / 2 - 40, D.z - 70 }   -- 机场西头、停机坪北面
local LINKS = {
  { "营地—指挥所", camp, cmd, 11 },
  { "指挥所—港口镇", cmd, port, 11 },
  { "指挥所—机场", cmd, afd, 11 },
  { "红滩—港口镇", beachExit("red"), port, 10 },
  { "港口镇—白滩", port, beachExit("white"), 10 },
  { "白滩—蓝滩", beachExit("white"), beachExit("blue"), 10 },
  { "蓝滩—金滩", beachExit("blue"), beachExit("gold"), 10 },
  { "金滩—机场", beachExit("gold"), { D.x + D.len / 2 + 30, D.z - 70 }, 10 },
  { "营地—侧翼滩", camp, beachExit("flank"), 10 },
  { "营地往西", { C.x - 220, C.z + 20 }, { -900, (Map.coastN(-900) or C.z) + 150 }, 9 },
}
local roads = {}
for _, L in ipairs(LINKS) do
  local path = route(L[2][1], L[2][2], L[3][1], L[3][2])
  if not path then
    print("  找不到路：" .. L[1])
  else
    for _, p in ipairs(path) do
      local i, k = cellOf(p[1], p[2])
      onRoad[id(i, k)] = true
    end
    local pts = resample(chaikin(chaikin(simplify(path, 5))), 20)
    local len = 0
    for i = 2, #pts do len = len + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
    print(string.format("  %s：%d 个点，%.0f 格", L[1], #pts, len))
    table.insert(roads, { name = L[1], w = L[4], pts = pts })
  end
end

---------------------------------------------------------------- 写文件

local lines = {
  "-- 路网（tools/map/roads.lua 离线算好的，别手改：改了地形重跑一遍）：Map.lua 开服时按它压平路面、换土路材质；客户端摆树、花草时避开",
  "--   每条路：name 名字、w 路面宽（格）、p 路线上的点 { x1, z1, x2, z2, … }（每 ≤ 20 格一个）",
  "return {",
}
for _, r in ipairs(roads) do
  local xs = {}
  for _, p in ipairs(r.pts) do table.insert(xs, string.format("%d,%d", math.floor(p[1] + 0.5), math.floor(p[2] + 0.5))) end
  table.insert(lines, string.format('  { name = "%s", w = %d, p = { %s } },', r.name, r.w, table.concat(xs, ",")))
end
table.insert(lines, "}")
local f = assert(io.open(SRC .. "/ReplicatedStorage/MapRoads.lua", "w"))
f:write(table.concat(lines, "\n") .. "\n")
f:close()
print("写好了 src/ReplicatedStorage/MapRoads.lua：" .. #roads .. " 条路")

-- 预览数据：每 8 格一个高度 + 路线（tools/map/preview.py 画图）
if OUT then
  local g = assert(io.open(OUT .. "/map_h.txt", "w"))
  local S = 8
  local nx, nz = math.floor((X1 - X0) / S), math.floor((Z1 - Z0) / S)
  g:write(string.format("%d %d %d %d %d\n", X0, Z0, S, nx, nz))
  for k = 0, nz - 1 do
    local row = {}
    for i = 0, nx - 1 do row[i + 1] = string.format("%.1f", Map.height(X0 + i * S, Z0 + k * S)) end
    g:write(table.concat(row, " ") .. "\n")
  end
  g:close()
  local r = assert(io.open(OUT .. "/map_roads.txt", "w"))
  for _, rd in ipairs(roads) do
    local xs = {}
    for _, p in ipairs(rd.pts) do table.insert(xs, string.format("%.0f %.0f", p[1], p[2])) end
    r:write(table.concat(xs, " ") .. "\n")
  end
  for _, f2 in ipairs(fortPts) do r:write(string.format("F %.0f %.0f\n", f2[1], f2[2])) end
  r:close()
end
TEST_CODE = 0
