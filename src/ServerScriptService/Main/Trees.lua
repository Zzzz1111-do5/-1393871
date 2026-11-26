-- 全面大战场——撞得倒、打得倒的树（服务器）：用户 11-26「要有可以撞倒的树，也可以被打倒」（钢城 MapCity.lua 的 Map.TREES）
--   树本身只在客户端画（Scenery.lua 按距离摆），这里只记哪一棵倒了、往哪边倒，广播给所有人：
--   · 车撞：玩家自己开的车客户端先倒（撞上那一下就倒，不等网络），再发 treeHit（服务器看车是不是真在旁边）；电脑开的车（AIVeh.lua）这里直接算
--   · 炸：爆炸（G.onExplode）半径里的树往外倒（半径按杀伤半径，最多 30 格）
--   · 炮弹、火箭弹、导弹飞过树干（Ents.lua 每步问 G.treeSeg）：一下打断，往弹飞的方向倒
--   · 机枪、步枪（Weapons.lua 的 G.treeRay）：打在树干上掉血，多打几下打断（大树要十来发重机枪）
--   · 新一局全部立回去；后进来的人看 workspace 属性 TreesDown（"编号:方位角度数,…"，一秒最多写一次）
local Trees = {}

function Trees.init(G)
  local Map = G.Map
  local down = {}   -- [编号] = 方位角（弧度）
  local hp = {}     -- [编号] = 剩下的血（子弹打的）
  local dirty, syncAt = false, 0
  local buf = {}
  local now = os.clock

  local function treeList() return Map.TREES end
  function G.treeIsDown(id) return down[id] ~= nil end
  -- 倒一棵：dx, dz 往哪边倒（不用是单位向量）
  function G.treeFell(t, dx, dz, why)
    if not t or down[t.id] then return false end
    local m = math.sqrt(dx * dx + dz * dz)
    if m < 1e-4 or m ~= m then dx, dz, m = 0, 1, 1 end
    local yaw = math.atan2(dx / m, dz / m)
    down[t.id] = yaw
    dirty = true
    G.fx({ k = "tree", id = t.id, d = math.floor(yaw * 1000 + 0.5) / 1000 })
    G.treesFelled = (G.treesFelled or 0) + 1
    local _ = why
    return true
  end

  -- 车的占地（按车头方向的矩形，四边各放宽树干半径）碰到的树都倒：电脑车每步调（玩家的车客户端算）
  function G.treeTouch(pos, d, look)
    if not treeList() or not d then return end
    local fx, fz = look.X, look.Z
    local m = math.sqrt(fx * fx + fz * fz)
    if m < 1e-3 then return end
    fx, fz = fx / m, fz / m
    local hl, hw = (d.L or 20) * 0.5, (d.W or 10) * 0.5
    for _, t in ipairs(Map.treesNear(pos.X, pos.Z, hl + 6, buf)) do
      if not down[t.id] then
        local rx, rz = t.x - pos.X, t.z - pos.Z
        local a = rx * fx + rz * fz
        local b = rx * fz - rz * fx
        if math.abs(a) < hl + t.r and math.abs(b) < hw + t.r then G.treeFell(t, fx, fz, "veh") end
      end
    end
  end

  -- 玩家的车撞倒的（客户端发来）：车在、离树不远才认
  G.ACT.treeHit = function(P, id, dx, dz)
    if type(id) ~= "number" or type(dx) ~= "number" or type(dz) ~= "number" or dx ~= dx or dz ~= dz then return end
    local T = treeList()
    local t = T and T[id]
    if not t or down[id] then return end
    local e = P.vehicle
    if not e or not e.alive or not e.root or not e.root.Parent then return end
    local p = e.root.CFrame.Position
    if (p.X - t.x) ^ 2 + (p.Z - t.z) ^ 2 > 70 * 70 then return end
    G.treeFell(t, dx, dz, "veh")
  end

  -- 线段 a → b 打在哪棵树的树干上（树干：竖的圆柱，半径 r，从地面到树高的六成）；返回树、打中的点、沿线段的比例
  local function segHit(a, b)
    local T = treeList()
    if not T then return nil end
    local d = b - a
    local L = math.sqrt(d.X * d.X + d.Z * d.Z)
    local best, bt, bp = nil, math.huge, nil
    local n = math.max(1, math.ceil(L / 64))
    for q = 0, n do   -- 沿线段每 64 格取一圈查
      local u = q / n
      local cx, cz = a.X + d.X * u, a.Z + d.Z * u
      for _, t in ipairs(Map.treesNear(cx, cz, 48, buf)) do
        if not down[t.id] then
          -- 二维：线段离树干中心最近的那一点
          local ex, ez = t.x - a.X, t.z - a.Z
          local L2 = d.X * d.X + d.Z * d.Z
          local s = (L2 > 1e-6) and math.clamp((ex * d.X + ez * d.Z) / L2, 0, 1) or 0
          local px, pz = a.X + d.X * s, a.Z + d.Z * s
          if (px - t.x) ^ 2 + (pz - t.z) ^ 2 < t.r * t.r then
            local y = a.Y + d.Y * s
            if y > t.y - 1 and y < t.y + t.h * 0.6 and s < bt then best, bt, bp = t, s, Vector3.new(px, y, pz) end
          end
        end
      end
    end
    return best, bp, bt
  end
  G.treeSegHit = segHit   -- 测试用

  -- 炮弹、火箭弹、导弹每一步（Ents.lua）：飞过树干就打断
  function G.treeSeg(s, a, b)
    if not treeList() then return end
    local t = segHit(a, b)
    if t then
      local v = b - a
      G.treeFell(t, v.X, v.Z, "shell")
    end
  end

  -- 机枪、步枪（Weapons.lua）：打在树干上掉血（伤害 × 0.35），血光了倒
  function G.treeRay(a, b, w)
    if not treeList() or not w then return end
    local t = segHit(a, b)
    if not t then return end
    local h0 = hp[t.id] or (60 + 80 * t.s)
    h0 -= (w.dmg or 30) * 0.35
    hp[t.id] = h0
    if h0 <= 0 then
      local v = b - a
      G.treeFell(t, v.X, v.Z, "gun")
    end
  end

  -- 爆炸：半径里的树往外倒（离地太高的空炸不算）
  local explode0 = G.onExplode
  G.onExplode = function(pos, w, src)
    if explode0 then explode0(pos, w, src) end
    if not treeList() or not w then return end
    G.try("炸树", function()
      local r = math.min(30, (w.splash or 8) * 0.9 + 3)
      if r < 4 then return end
      local gy = Map.ground(pos.X, pos.Z)
      if pos.Y - gy > 40 then return end
      for _, t in ipairs(Map.treesNear(pos.X, pos.Z, r, buf)) do
        if not down[t.id] then
          local dx, dz = t.x - pos.X, t.z - pos.Z
          if dx * dx + dz * dz < 1 then dx, dz = math.random() - 0.5, math.random() - 0.5 end
          G.treeFell(t, dx, dz, "boom")
        end
      end
    end)
  end

  -- 新一局：全部立回去
  G.on("roundStart", function()
    if next(down) == nil and next(hp) == nil then return end
    table.clear(down)
    table.clear(hp)
    dirty = true
    G.fx({ k = "treeReset" })
  end)

  -- 后进来的人看的属性（一秒最多写一次）
  G.onFrame(function()
    if not dirty then return end
    local t = now()
    if t < syncAt then return end
    syncAt = t + 1
    dirty = false
    local parts = {}
    for id, yaw in pairs(down) do table.insert(parts, id .. ":" .. math.floor(math.deg(yaw) + 0.5)) end
    pcall(function() workspace:SetAttribute("TreesDown", table.concat(parts, ",")) end)
  end)
  G.treesDown = function() return down end   -- 测试用
end

return Trees
