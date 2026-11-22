-- Roblox全面大战场——寻路（机器人、AI 车辆用）：陆地按 CELL 格一格做网格，每个目的地（5 个据点、守方营地）算一张流场——
--   从目的地往外做 Dijkstra（八方向，边的代价 = 长度 ×（1 + 坡度 × 3），坡太陡、中间下水的边不通），
--   每格记「下一步去哪格」；走的时候看前面几格（顺一点、少拐）。开服地图生成完后在后台慢慢算（每算一批让出一帧）
local Nav = {}

function Nav.init(G)
  local Map = G.Map
  local V = Vector3.new
  local CELL = 40 * math.max(1, (Map.K or 1) / 2)   -- 地图放大了：网格跟着变粗一点（3 倍时 60 格一格），格子数别涨太多
  local K = Map.K or 1   -- 地图放大的倍数（Map.lua）
  local X0, Z0, X1, Z1 = -3200 * K, -3000 * K, 3200 * K, 1200 * K   -- 主岛和前哨岛、灯塔岛、西礁岛（攻方机场岛不用）
  if Map.NAVBOX then   -- 沙漠图：战区南北长（红方基地到蓝方营地三万多格），网格粗一点（大片平地，80 格一格够用）
    X0, Z0, X1, Z1 = Map.NAVBOX.x0, Map.NAVBOX.z0, Map.NAVBOX.x1, Map.NAVBOX.z1
    CELL = Map.NAVCELL or CELL
    G.navCell = CELL
  end
  local NX, NZ = math.ceil((X1 - X0) / CELL), math.ceil((Z1 - Z0) / CELL)
  local MAXSLOPE = 0.9   -- 比这陡（约 42°）走不了
  local H = {}           -- [格号] = 高度（只记陆地）
  local flows = {}       -- [目的地] = { nxt = {}, dist = {} }
  local ready = false
  G.navCell = CELL

  local function id(i, k) return k * NX + i end
  local function ik(c) return c % NX, c // NX end
  local function center(c)
    local i, k = ik(c)
    return X0 + (i + 0.5) * CELL, Z0 + (k + 0.5) * CELL
  end
  local function cellOf(x, z)
    local i, k = math.floor((x - X0) / CELL), math.floor((z - Z0) / CELL)
    if i < 0 or k < 0 or i >= NX or k >= NZ then return nil end
    return id(i, k)
  end

  local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
  local edge = {}   -- [格号 * 8 + 方向] = 代价（false 不通）
  local function edgeCost(c, dIdx)
    local key = c * 8 + dIdx
    local v = edge[key]
    if v ~= nil then return v end
    local i, k = ik(c)
    local d = DIRS[dIdx]
    local j, l = i + d[1], k + d[2]
    local res = false
    if j >= 0 and l >= 0 and j < NX and l < NZ and H[id(j, l)] then
      local x0, z0 = center(c)
      local x1, z1 = center(id(j, l))
      local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
      local prev = H[c]
      local worst, sum = 0, 0
      for q = 1, 4 do
        local t = q / 4
        local h = (q == 4) and H[id(j, l)] or Map.height(x0 + (x1 - x0) * t, z0 + (z1 - z0) * t)
        if h < 0.4 then worst = 99 break end   -- 中间下水
        local sl = math.abs(h - prev) / (L / 4)
        if sl > worst then worst = sl end
        sum += sl
        prev = h
      end
      if worst <= MAXSLOPE then res = L * (1 + 3 * sum / 4) end
    end
    edge[key] = res
    -- 反方向一样
    local rev = { [1] = 2, [2] = 1, [3] = 4, [4] = 3, [5] = 8, [6] = 7, [7] = 6, [8] = 5 }
    if j and l and j >= 0 and l >= 0 and j < NX and l < NZ then edge[id(j, l) * 8 + rev[dIdx]] = res end
    return res
  end

  -- 最小堆
  local function push(hp, c, d)
    local n = #hp + 1
    hp[n] = { c, d }
    while n > 1 do
      local p = n // 2
      if hp[p][2] <= hp[n][2] then break end
      hp[p], hp[n] = hp[n], hp[p]
      n = p
    end
  end
  local function pop(hp)
    local top = hp[1]
    local last = table.remove(hp)
    if #hp > 0 then
      hp[1] = last
      local n, m = 1, #hp
      while true do
        local l, r = n * 2, n * 2 + 1
        local s = n
        if l <= m and hp[l][2] < hp[s][2] then s = l end
        if r <= m and hp[r][2] < hp[s][2] then s = r end
        if s == n then break end
        hp[s], hp[n] = hp[n], hp[s]
        n = s
      end
    end
    return top
  end

  -- 离 (x, z) 最近的陆地格（自己那格不是陆地就往外找两圈）
  local function landCellNear(x, z)
    local c = cellOf(x, z)
    if c and H[c] then return c end
    local i0, k0 = math.floor((x - X0) / CELL), math.floor((z - Z0) / CELL)
    for r = 1, 3 do
      for di = -r, r do
        for dk = -r, r do
          local i, k = i0 + di, k0 + dk
          if i >= 0 and k >= 0 and i < NX and k < NZ and H[id(i, k)] then return id(i, k) end
        end
      end
    end
    return nil
  end

  local function buildFlow(key, x, z)
    local src = landCellNear(x, z)
    if not src then return end
    local dist, nxt = { [src] = 0 }, {}
    local hp = {}
    push(hp, src, 0)
    local n = 0
    while #hp > 0 do
      local top = pop(hp)
      local c, d = top[1], top[2]
      if d <= (dist[c] or math.huge) then
        local i, k = ik(c)
        for dIdx = 1, 8 do
          local w = edgeCost(c, dIdx)
          if w then
            local dd = DIRS[dIdx]
            local o = id(i + dd[1], k + dd[2])
            local nd = d + w
            if nd < (dist[o] or math.huge) then
              dist[o] = nd
              nxt[o] = c
              push(hp, o, nd)
            end
          end
        end
        n += 1
        if n % 1500 == 0 then task.wait() end
      end
    end
    flows[key] = { dist = dist, nxt = nxt }
  end

  -- 地图好了以后在后台算：先记陆地格的高度，再挨个目的地算流场
  function G.navBuild()
    task.spawn(function()
      local n = 0
      for k = 0, NZ - 1 do
        for i = 0, NX - 1 do
          local x, z = X0 + (i + 0.5) * CELL, Z0 + (k + 0.5) * CELL
          local h = Map.height(x, z)
          if h > 0.4 then H[id(i, k)] = h end
        end
        n += 1
        if n % 20 == 0 then task.wait() end
      end
      for _, p in ipairs(Map.POINTS) do buildFlow(p.id, p.x, p.z) end
      buildFlow("camp", Map.CAMP.x, Map.CAMP.z)
      ready = true
      G.navReady = true
    end)
  end

  -- 往 key（据点编号 / "camp"）去：返回下一个要走到的点（看前面 3 格），到不了（不在同一块陆地、还没算好）返回 nil
  function G.navNext(pos, key)
    local F = flows[key]
    if not F then return nil end
    local c = landCellNear(pos.X, pos.Z)
    if not c or not F.dist[c] then return nil end
    local n = c
    for _ = 1, 3 do
      local m = F.nxt[n]
      if not m then break end
      n = m
    end
    if n == c then return nil end   -- 已经在目的地那格
    local x, z = center(n)
    return V(x, 0, z)
  end
  -- 从 pos 到 key 的路程（格），到不了返回 nil
  function G.navDist(pos, key)
    local F = flows[key]
    if not F then return nil end
    local c = landCellNear(pos.X, pos.Z)
    return c and F.dist[c] or nil
  end
end

return Nav
