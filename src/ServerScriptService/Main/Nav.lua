-- Roblox全面大战场——寻路（机器人、AI 车辆用）：陆地按 CELL 格一格做网格，每个目的地（5 个据点、守方营地）算一张流场——
--   从目的地往外做 Dijkstra（八方向，边的代价 = 长度 ×（1 + 坡度 × 3），坡太陡、中间下水的边不通），
--   每格记「下一步去哪格」；走的时候看前面几格（顺一点、少拐）。开服地图生成完后在后台慢慢算（每帧最多算 4 毫秒就让）
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
  -- 选了地图以后（navBuild）按那张图重新定范围（沙海给了 NAVBOX、NAVCELL）
  local function setGrid()
    if Map.NAVBOX then   -- 沙海：自己给了范围、格子大小（原来只在开服时看——那时地图还没定、是岛，沙海的网格盖不住南边的红方基地）
      X0, Z0, X1, Z1 = Map.NAVBOX.x0, Map.NAVBOX.z0, Map.NAVBOX.x1, Map.NAVBOX.z1
      CELL = Map.NAVCELL or CELL
    end
    NX, NZ = math.ceil((X1 - X0) / CELL), math.ceil((Z1 - Z0) / CELL)
    G.navCell = CELL
  end
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
  local REV = { 2, 1, 4, 3, 8, 7, 6, 5 }   -- 反方向（原来每算一条边新建一张表）
  local edge = {}   -- [格号 * 8 + 方向] = 代价（false 不通）
  local function edgeCost(c, dIdx)
    local key = c * 8 + dIdx
    local v = edge[key]
    if v ~= nil then return v end
    local i, k = ik(c)
    local d = DIRS[dIdx]
    local j, l = i + d[1], k + d[2]
    local inside = j >= 0 and l >= 0 and j < NX and l < NZ
    local o = inside and id(j, l)
    local res = false
    if inside and H[o] then
      local x0, z0 = center(c)
      local x1, z1 = center(o)
      local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
      local prev = H[c]
      local worst, sum = 0, 0
      for q = 1, 4 do
        local t = q / 4
        local h = (q == 4) and H[o] or Map.height(x0 + (x1 - x0) * t, z0 + (z1 - z0) * t)
        if h < 0.4 then worst = 99 break end   -- 中间下水
        local sl = math.abs(h - prev) / (L / 4)
        if sl > worst then worst = sl end
        sum += sl
        prev = h
      end
      if worst <= MAXSLOPE then res = L * (1 + 3 * sum / 4) end
    end
    edge[key] = res
    if inside then edge[o * 8 + REV[dIdx]] = res end   -- 反方向一样
    return res
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

  -- 后台算的时候每帧最多占 SLICE 秒（用户 11-22：加载地图的时候坦克飞机抽搐——沙漠图 655 × 655 格、一张流场九万多格，
  --   原来流场每出堆 1500 次才让一帧（主要花在算边的代价、压堆上，Map.height 本身不贵），开局那十几秒服务器每帧卡几十上百毫秒，
  --   车和飞机的物理同步跟着一顿一顿的）。只改让帧的时机，算出来的流场不变（tools/mock/navslice.lua 比指纹）
  local SLICE, sliceT, work = 0.004, 0, 0   -- work：上次让帧以后干了多少（按次数兜底：时钟不准的时候也不会一口气算太多）
  local function yieldMaybe(cost, cap)
    work += cost
    if work >= cap or os.clock() - sliceT > SLICE then
      task.wait()
      sliceT, work = os.clock(), 0
    end
  end
  -- 从目的地往外做 Dijkstra。最小堆拆成格号、距离两张表（原来每压一个就新建一张 { c, d } 小表：沙漠图一张流场压几十万次）；
  --   上浮、下沉的比较和原来一模一样（同样距离的格出堆先后不变），算出来的流场不变
  local function buildFlow(key, x, z)
    local src = landCellNear(x, z)
    if not src then return end
    local dist, nxt = { [src] = 0 }, {}
    local hc, hd, m = { src }, { 0 }, 1
    local n = 0
    while m > 0 do
      local c, d = hc[1], hd[1]
      -- 出堆：最后一个挪到堆顶往下沉
      local lc, ld = hc[m], hd[m]
      hc[m], hd[m] = nil, nil
      m -= 1
      if m > 0 then
        local p = 1
        while true do
          local l = p * 2
          local s, sd = p, ld
          if l <= m and hd[l] < sd then s, sd = l, hd[l] end
          if l + 1 <= m and hd[l + 1] < sd then s, sd = l + 1, hd[l + 1] end
          if s == p then break end
          hc[p], hd[p] = hc[s], sd
          p = s
        end
        hc[p], hd[p] = lc, ld
      end
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
              -- 进堆：放到最后往上浮
              m += 1
              local q = m
              while q > 1 do
                local p = q // 2
                if hd[p] <= nd then break end
                hc[q], hd[q] = hc[p], hd[p]
                q = p
              end
              hc[q], hd[q] = o, nd
            end
          end
        end
        n += 1
        if n % 100 == 0 then yieldMaybe(100, 1500) end
      end
    end
    flows[key] = { dist = dist, nxt = nxt }
  end

  -- 地图好了以后在后台算：先记陆地格的高度，再挨个目的地算流场
  function G.navBuild()
    setGrid()
    task.spawn(function()
      sliceT = os.clock()
      for k = 0, NZ - 1 do
        for i = 0, NX - 1 do
          local x, z = X0 + (i + 0.5) * CELL, Z0 + (k + 0.5) * CELL
          local h = Map.height(x, z)
          if h > 0.4 then H[id(i, k)] = h end
          if i % 64 == 63 then yieldMaybe(64, 2000) end
        end
      end
      for _, p in ipairs(Map.POINTS) do buildFlow(p.id, p.x, p.z) end
      buildFlow("camp", Map.CAMP.x, Map.CAMP.z)
      if Map.CAMP_ATK then buildFlow("camp_atk", Map.CAMP_ATK.x, Map.CAMP_ATK.z) end
      ready = true
      G.navReady = true
    end)
  end

  -- 测试用：流场指纹（改算法、改让帧前后比，应一样）
  function G.navFinger()
    local list = {}
    for k, F in pairs(flows) do table.insert(list, { tostring(k), F }) end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local out = {}
    for _, e in ipairs(list) do
      local h, s, n = 0, 0, 0
      for c, m in pairs(e[2].nxt) do h = (h + c * 7919 + m * 104729) % 2147483647 n += 1 end
      for _, d in pairs(e[2].dist) do s = (s + math.floor(d * 1000)) % 2147483647 end
      table.insert(out, string.format("%s:%d/%d/%d", e[1], n, h, s))
    end
    return table.concat(out, " ")
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
