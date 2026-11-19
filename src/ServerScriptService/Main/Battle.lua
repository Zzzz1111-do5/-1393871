-- 全面大战场——战场氛围（服务器）。用户 11-18：「按照 3A 游戏的标准把这款游戏做到惊艳，自由发挥，参考战雷、战地」（夜晚照旧锁定）
--   1. 弹坑（战地那种越打越烂的地面）：炮弹、火箭弹、导弹、炸弹在地上炸，地形上炸出一个浅碗形的坑，坑里、坑边烧成焦土（Mud）。
--      坑口半径 = 杀伤半径（splash）× 按种类的系数（Config.Battle.crater.k；航炮、手雷、高炮空炸不挖）；坑深不到坑口半径的三分之一、最多 maxDepth 格
--      （约 2 米：坦克、登陆艇、两栖车照样开得过去）。不挖的：水里、海边坑底会低于海面、半空炸、太陡的坡、
--      坑口一圈往下打射线先碰到房子 / 工事 / 沙袋 / 车 / 障碍（锚住的零件）的、离已有的坑太近（同一处不越挖越深）。
--      挖法：一个球心在地面上方的空气球（Terrain:FillBall Air）切出碗底，再把坑口外扩 3 格那一块里的草、土、沙换成焦土（ReplaceMaterial）。
--      一局最多 max 个、一秒最多 perSec 个（集束炸弹一串排队挖）；新一局开始时按 Map 原来的高度把挖过的那一小块地重写回去（World.writeChunk）。
--   2. 照明弹（夜战，战地 1、二战登陆夜战里那种半空吊着的白光）：开战后每隔 every 秒，往当前阶段还没拿下的据点上空打一发——
--      sea 的比例是攻方舰队的星弹（从最近的登陆舰那边打过来），其余是守方迫击炮（从据点后方离海远的那边打上去）；
--      有人在争夺的据点优先。在离地 height 格炸开，挂着降落伞每秒落 fall 格、烧 burn 秒，同时最多 alive 发。
--      只发一条特效 { k = "illum", o 发射点, p 炸开的点, t 服务器时刻, fl 飞几秒, burn, fall, w 风 }：客户端（Warfx.lua）按服务器时间算出它在哪、多亮，
--      所有人看到的是同一发、照亮的是同一片（不影响谁能打中谁：只是画面）
--   3. 房子炸塌（战地的招牌）：地图上的房子有血量，炸掉一半着火，炸光了塌成一摊废墟（不再挡人、挡子弹），新一局复原。见下面「房子炸塌」
--   4. 暴风雨：每局开战后几分钟可能变天，服务器只给强度（workspace 属性 StormK），雨、闪电、雷声、云、浪、雾都是客户端画
--   5. 阵亡镜头：死了以后告诉客户端凶手在哪（G.killcam，Round.lua 调），客户端镜头转过去、拉近、红色标出来
local Battle = {}

function Battle.init(G)
  local Config, Map, World = G.Config, G.Map, G.World
  local BC = Config.Battle or {}
  local CR, IL = BC.crater or {}, BC.illum or {}
  local V = Vector3.new
  local MAT = Enum.Material
  local T = workspace.Terrain
  local now = os.clock
  local function rnd(a, b) return a + (b - a) * math.random() end

  ---------------------------------------------------------------- 弹坑

  local KC = CR.k or {}
  local craters = {}   -- 这一局挖过的 { x, z, s 地面高, rc 坑口半径, h 深 }
  local queue = {}
  local dug = 0        -- 这一局挖了几个（含排队的）
  G.craters = craters  -- 测试用

  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  rayP.IgnoreWater = true
  pcall(function() rayP.FilterDescendantsInstances = { workspace:FindFirstChild("ClientFx") } end)

  -- 坑口中心、半个坑口一圈、坑口外扩 2 格一圈（各 8 个点）：从地面上方 40 格往下打，先碰到锚住的零件（房子、工事、沙袋、车的命中盒、障碍）就不挖
  local function blocked(x, s, z, rc)
    local function hit(px, pz)
      local res = workspace:Raycast(V(px, s + 40, pz), V(0, -60, 0), rayP)
      return res and res.Instance and res.Instance ~= T and res.Instance:IsA("BasePart") and res.Instance.Anchored
    end
    if hit(x, z) then return true end
    for _, rr in ipairs({ rc * 0.5, rc + 2 }) do
      for i = 0, 7 do
        local a = i * math.pi / 4
        if hit(x + math.cos(a) * rr, z + math.sin(a) * rr) then return true end
      end
    end
    return false
  end

  local SCORCH = { MAT.Grass, MAT.LeafyGrass, MAT.Ground, MAT.Sand }
  local function snapDn(v) return math.floor(v / 4) * 4 end
  local function snapUp(v) return math.ceil(v / 4) * 4 end

  local function dig(c)
    local rc, h = c.rc, c.h
    -- 球冠：坑口半径 rc、深 h 的碗，球的半径 Rs = (rc² + h²) / 2h，球心在坑底往上 Rs
    local Rs = (rc * rc + h * h) / (2 * h)
    T:FillBall(V(c.x, c.s - h + Rs, c.z), Rs, MAT.Air)
    local e = rc + 3
    local reg = Region3.new(V(snapDn(c.x - e), snapDn(c.s - h - 4), snapDn(c.z - e)), V(snapUp(c.x + e), snapUp(c.s + 4), snapUp(c.z + e)))
    for _, m in ipairs(SCORCH) do
      pcall(function() T:ReplaceMaterial(reg, 4, m, MAT.Mud) end)
    end
  end

  -- 爆炸后看要不要挖（G.onExplode：Ents.lua 的 G.explode 调；Forts.lua 也挂在上面，串起来）
  local function crater(pos, w)
    if not w or dug >= (CR.max or 240) then return end
    local kind = G.boomKind and G.boomKind(w)
    local k = kind and KC[kind]
    if not k or k <= 0 then return end
    local rc = math.min((w.splash or 8) * k, CR.maxR or 13)
    if rc < (CR.minR or 3.2) then return end
    local x, z = pos.X, pos.Z
    local s = Map.height(x, z)
    if s < 1.2 then return end                                     -- 水里、水边
    if pos.Y - s > math.max(3, rc * 0.8) then return end            -- 半空炸
    if (Map.slope and Map.slope(x, z) or 0) > 0.42 then return end  -- 陡坡（球会切进坡里）
    local h = math.min(rc * (CR.depth or 0.34), CR.maxDepth or 5.5)
    if s - h < 0.6 then h = s - 0.6 end                             -- 坑底不低于海面（海边的坑没水灌进来，看着怪）
    if h < 1 then return end
    local gap = CR.gap or 0.55
    for _, o in ipairs(craters) do
      local dx, dz = o.x - x, o.z - z
      local dd = gap * (o.rc + rc)
      if dx * dx + dz * dz < dd * dd then return end
    end
    for _, o in ipairs(queue) do
      local dx, dz = o.x - x, o.z - z
      local dd = gap * (o.rc + rc)
      if dx * dx + dz * dz < dd * dd then return end
    end
    if blocked(x, s, z, rc) then return end
    dug += 1
    table.insert(queue, { x = x, z = z, s = s, rc = rc, h = h })
  end
  G.crater = crater

  local explode0 = G.onExplode
  G.onExplode = function(pos, w, src)
    if explode0 then explode0(pos, w, src) end
    G.try("弹坑", crater, pos, w)
  end

  -- 排队的坑：一秒最多 perSec 个
  local tokens, tokAt = 0, now()
  local function stepCraters()
    if #queue == 0 then return end
    local t = now()
    tokens = math.min(CR.perSec or 8, tokens + (t - tokAt) * (CR.perSec or 8))
    tokAt = t
    while tokens >= 1 and #queue > 0 do
      tokens -= 1
      local c = table.remove(queue, 1)
      G.try("挖弹坑", dig, c)
      table.insert(craters, c)
    end
  end

  -- 新一局：挖过的地方按原来的高度重写（一小块一小块，每几块让一帧）
  local function restore(list)
    for i, c in ipairs(list) do
      local e = c.rc + 8
      local x0, z0 = snapDn(c.x - e), snapDn(c.z - e)
      local n = math.ceil((c.x + e - x0) / 4) + 1
      G.try("填弹坑", World.writeChunk, T, x0, z0, n, c.s - c.h - 8)
      if i % 6 == 0 then task.wait() end
    end
  end
  G.on("roundStart", function()
    local list = table.clone(craters)   -- 排队还没挖的不用填，一起清掉
    table.clear(craters)
    table.clear(queue)
    dug = 0
    if #list > 0 and World.writeChunk then task.spawn(restore, list) end
  end)

  ---------------------------------------------------------------- 照明弹

  local alive = {}     -- 还在烧的 { die }
  local nextAt = nil
  local fired = 0
  G.illumFired = function() return fired end   -- 测试用

  local function stagePoints()
    local R = G.round
    local st = R and Config.Stages and Config.Stages[R.stage]
    local out = {}
    if not st or not G.points then return out end
    local ids = {}
    for _, id in ipairs(st.points or {}) do table.insert(ids, id) end
    for _, id in ipairs(st.flank or {}) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
      local s = G.points[id]
      if s and not s.locked then table.insert(out, s) end
    end
    return out
  end

  -- 舰队里离目标最近的登陆舰 / 两栖攻击舰（航母不打炮）
  local function fleetNear(x, z)
    local best, bd
    for _, f in ipairs(Map.FLEET or {}) do
      if f.kind ~= "carrier" then
        local d = (f.x - x) ^ 2 + (f.z - z) ^ 2
        if not bd or d < bd then best, bd = f, d end
      end
    end
    return best
  end

  local function fireIllum()
    local pts = stagePoints()
    if #pts == 0 then return false end
    -- 有人在争夺的（据点里有攻方、或者占领进度不是零）权重大
    local tot, ws = 0, {}
    for i, s in ipairs(pts) do
      ws[i] = ((s.atk or 0) > 0 or (s.prog or 0) > 0) and 3 or 1
      tot += ws[i]
    end
    local r, pick = math.random() * tot, pts[1]
    for i, s in ipairs(pts) do
      r -= ws[i]
      if r <= 0 then pick = s break end
    end
    local PR = Map.POINT_R or 80
    local gx, gz = pick.x + rnd(-0.7, 0.7) * PR, pick.z + rnd(-0.7, 0.7) * PR
    local gy = math.max(0, Map.ground(gx, gz))
    local p = V(gx, gy + rnd(IL.height and IL.height[1] or 105, IL.height and IL.height[2] or 135), gz)
    local f = fleetNear(gx, gz)
    local o, by
    if f and math.random() < (IL.sea or 0.6) then
      o, by = V(f.x, 16, f.z), "atk"   -- 舰炮：从登陆舰上打过来
    else
      -- 守方迫击炮：据点后面、离舰队远的那一边 150～260 格
      local away = f and V(gx - f.x, 0, gz - f.z) or V(0, 0, -1)
      away = away.Magnitude > 1 and away.Unit or V(0, 0, -1)
      local q = V(gx, 0, gz) + away * rnd(150, 260)
      o, by = V(q.X, math.max(0, Map.ground(q.X, q.Z)) + 1, q.Z), "def"
    end
    local fl = math.clamp((p - o).Magnitude / 520, 2.4, 9)
    local burn, fall = IL.burn or 32, IL.fall or 2.6
    local okW, wind = pcall(function() return workspace.GlobalWind end)
    if not okW or typeof(wind) ~= "Vector3" or wind.Magnitude < 0.1 then wind = V(2.2, 0, 1.1) end
    G.fx({ k = "illum", o = o, p = p, t = workspace:GetServerTimeNow(), fl = fl, burn = burn, fall = fall, w = V(wind.X, 0, wind.Z) * 0.6, by = by })
    table.insert(alive, { die = now() + fl + burn })
    fired += 1
    return true
  end
  G.fireIllum = fireIllum   -- 测试用

  local function stepIllum()
    local R = G.round
    if not R or R.phase ~= "battle" then
      nextAt = nil
      return
    end
    local t = now()
    if not nextAt then nextAt = t + (IL.first or 6) end   -- 开战后第一发
    if t < nextAt then return end
    local ev = IL.every or { 14, 24 }
    nextAt = t + rnd(ev[1], ev[2])
    for i = #alive, 1, -1 do
      if alive[i].die < t then table.remove(alive, i) end
    end
    if #alive >= (IL.alive or 3) then return end
    fireIllum()
  end

  ---------------------------------------------------------------- 房子炸塌（战地的招牌）
  -- 地图上的房子（World.building 建的 Bld_<种类> 模型）有血量：按占地面积算（Config.Battle.bld：每平方格 hpPerArea，hpMin～hpMax）。
  --   爆炸按到房子外接盒的距离算伤害（中心全伤、边上三成），按爆炸种类乘 k（手雷很少、炸弹加倍、航炮 / 高炮空炸不算）；
  --   血掉到 fire 以下：着火（模型属性 Burning：客户端窗口里冒火、往上冒黑烟、火光一闪一闪）；
  --   掉光：塌——房子收进 ServerStorage（客户端那边就没了，碰撞盒也没了：不再挡人、挡子弹），原地堆一摊废墟（几块碎石堆、几截断墙、几根歪倒的梁，
  --   锚住、能踩上去、矮：车开得过去），发一条 collapse 特效（客户端：扬起一大团尘土、碎块乱飞、轰隆一声）；新一局全部复原
  local BD = BC.bld or {}
  local KB = BD.k or { nade = 0.3, shell = 1, rkt = 0.8, msl = 1, bomb = 1.4 }
  local blds = {}
  G.buildings = blds   -- 测试用
  local scanned = false
  local SS = game:GetService("ServerStorage")
  local store = SS:FindFirstChild("RuinedBuildings") or Instance.new("Folder")
  store.Name = "RuinedBuildings"
  store.Parent = SS
  local ruinsF = workspace:FindFirstChild("Ruins") or Instance.new("Folder")
  ruinsF.Name = "Ruins"
  ruinsF.Parent = workspace

  local function scanBlds()
    scanned = true
    for _, m in ipairs(workspace:GetDescendants()) do
      if m:IsA("Model") and m:GetAttribute("Bld") and m:GetAttribute("BldBase") then
        local base, size = m:GetAttribute("BldBase"), m:GetAttribute("BldSize")
        if typeof(base) == "CFrame" and typeof(size) == "Vector3" then
          -- 外接盒（世界坐标、轴对齐）：按占地四角和高
          local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
          for _, cx in ipairs({ -0.5, 0.5 }) do
            for _, cz in ipairs({ -0.5, 0.5 }) do
              for _, cy in ipairs({ 0, 1 }) do
                local q = base * V(size.X * cx, size.Y * cy, size.Z * cz)
                x0, y0, z0 = math.min(x0, q.X), math.min(y0, q.Y), math.min(z0, q.Z)
                x1, y1, z1 = math.max(x1, q.X), math.max(y1, q.Y), math.max(z1, q.Z)
              end
            end
          end
          local lo, hi = V(x0, y0, z0), V(x1, y1, z1)
          local hp = math.clamp(size.X * size.Z * (BD.hpPerArea or 1.5), BD.hpMin or 700, BD.hpMax or 4000)
          table.insert(blds, { m = m, key = m:GetAttribute("Bld"), base = base, size = size, lo = lo, hi = hi, center = (lo + hi) / 2,
            hp = hp, hp0 = hp, seed = #blds + 1 })
        end
      end
    end
  end

  local function boxDist(p, lo, hi)
    local dx = math.max(lo.X - p.X, 0, p.X - hi.X)
    local dy = math.max(lo.Y - p.Y, 0, p.Y - hi.Y)
    local dz = math.max(lo.Z - p.Z, 0, p.Z - hi.Z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  -- 废墟：几块碎石堆（方块、楔形）、几截断墙、几根歪倒的梁；颜色灰褐、烧黑
  local RGB = Color3.fromRGB
  local CF = CFrame.new
  local function makeRuin(b)
    local rng = Random.new(b.seed * 7919)
    local m = Instance.new("Model")
    m.Name = "Ruin_" .. tostring(b.key)
    m:SetAttribute("Ruin", b.key)
    local w, h, d = b.size.X, b.size.Y, b.size.Z
    local hh = math.min(h, 16)
    local cols = { RGB(96, 90, 82), RGB(72, 68, 63), RGB(112, 104, 94), RGB(54, 50, 47) }
    local function piece(kind, size, cf, col, mat, solid)
      local p = Instance.new(kind)
      p.Size = size
      p.CFrame = cf
      p.Color = col
      p.Material = mat or Enum.Material.Concrete
      p.Anchored = true
      p.CanCollide = solid ~= false
      p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
      p.Parent = m
      return p
    end
    for i = 1, 9 do   -- 碎石堆
      local sx, sz = rng:NextNumber(0.25, 0.55) * w, rng:NextNumber(0.25, 0.55) * d
      local sy = rng:NextNumber(0.1, 0.24) * hh + 0.8
      local ox, oz = rng:NextNumber(-0.32, 0.32) * w, rng:NextNumber(-0.32, 0.32) * d
      piece((i % 3 == 0) and "WedgePart" or "Part", V(sx, sy, sz),
        b.base * CF(ox, sy / 2 - 0.4, oz) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 6.28), rng:NextNumber(-0.12, 0.12)),
        cols[rng:NextInteger(1, #cols)], (i % 4 == 0) and Enum.Material.Slate or Enum.Material.Concrete)
    end
    for i = 1, 3 do   -- 断墙：贴着占地的边，一截矮一截高、歪一点
      local side = rng:NextInteger(0, 3)
      local along = rng:NextNumber(-0.35, 0.35)
      local wh = rng:NextNumber(0.25, 0.5) * hh + 2
      local ww = rng:NextNumber(0.18, 0.4) * ((side % 2 == 0) and w or d)
      local ox = (side % 2 == 0) and along * w or ((side == 1) and 0.5 or -0.5) * w
      local oz = (side % 2 == 0) and ((side == 0) and 0.5 or -0.5) * d or along * d
      local rot = (side % 2 == 0) and 0 or math.pi / 2
      piece("Part", V(ww, wh, 1.2), b.base * CF(ox, wh / 2 - 0.5, oz) * CFrame.Angles(0, rot, rng:NextNumber(-0.18, 0.18)), cols[1])
    end
    for i = 1, 3 do   -- 歪倒的梁
      local L = rng:NextNumber(0.4, 0.7) * math.max(w, d)
      piece("Part", V(L, 0.9, 0.9), b.base * CF(rng:NextNumber(-0.25, 0.25) * w, rng:NextNumber(1.5, 0.3 * hh + 2), rng:NextNumber(-0.25, 0.25) * d)
        * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.35, 0.35)), RGB(48, 40, 34), Enum.Material.Wood)
    end
    m.Parent = ruinsF
    return m
  end

  local function collapse(b)
    b.down = true
    b.parent = b.m.Parent
    G.fx({ k = "collapse", p = b.center, s = b.size, cf = b.base })
    b.m.Parent = store
    b.ruin = makeRuin(b)
  end
  G.collapseBuilding = collapse   -- 测试用

  local function bldHit(pos, w)
    if not w or not w.dmg then return end
    if not scanned then scanBlds() end
    local kind = G.boomKind and G.boomKind(w)
    local km = kind and KB[kind]
    if not km or km <= 0 then return end
    local r = w.splash or 8
    for _, b in ipairs(blds) do
      if not b.down then
        local d = boxDist(pos, b.lo, b.hi)
        if d < r then
          b.hp -= w.dmg * km * (1 - 0.7 * d / r)
          if b.hp <= 0 then
            collapse(b)
          elseif b.hp < b.hp0 * (BD.fire or 0.55) and not b.fire then
            b.fire = true
            b.m:SetAttribute("Burning", true)
          end
        end
      end
    end
  end

  local explode1 = G.onExplode
  G.onExplode = function(pos, w, src)
    if explode1 then explode1(pos, w, src) end
    G.try("炸房子", bldHit, pos, w)
  end

  G.on("roundStart", function()
    for _, b in ipairs(blds) do
      if b.down then
        b.m.Parent = b.parent
        if b.ruin then b.ruin:Destroy() end
        b.down, b.ruin = false, nil
      end
      if b.fire then
        b.fire = false
        b.m:SetAttribute("Burning", false)
      end
      b.hp = b.hp0
    end
  end)

  ---------------------------------------------------------------- 暴风雨（战地 4 那种中途变天）
  -- 每局开战后 at 秒（随机）有 chance 的机会来一场暴风雨，持续 dur 秒：前后 ramp 秒慢慢变大、变小。
  --   服务器只管强度：workspace 的属性 StormK（0～1，每半秒更新一次，后进服的人也对得上）；下雨、打闪、打雷、云、浪、雾都是客户端（Warfx.lua）照它画
  local ST = BC.storm or {}
  local storm = nil    -- { t0, dur } 本局的暴风雨（os.clock）
  local stormRound = -1
  local stormK, stormSent = 0, -1
  local function setStormK(k)
    stormK = k
    if math.abs(k - stormSent) > 0.02 or (k == 0 and stormSent ~= 0) then
      stormSent = k
      pcall(function() workspace:SetAttribute("StormK", math.floor(k * 100 + 0.5) / 100) end)
    end
  end
  function G.startStorm(delay, dur)   -- 测试用：delay 秒后来一场，持续 dur 秒
    storm = { t0 = now() + (delay or 0), dur = dur or 180 }
  end
  local stormAcc = 0
  local function stepStorm(dt)
    stormAcc += dt or 0
    if stormAcc < 0.5 then return end
    stormAcc = 0
    local R = G.round
    if R and R.phase == "battle" and stormRound ~= R.n then
      stormRound = R.n
      if math.random() < (ST.chance or 0.85) then
        local at, du = ST.at or { 150, 420 }, ST.dur or { 150, 230 }
        storm = { t0 = now() + rnd(at[1], at[2]), dur = rnd(du[1], du[2]) }
      end
    end
    local k = 0
    if storm then
      local u = now() - storm.t0
      local ramp = ST.ramp or 25
      if u > 0 and u < storm.dur then
        k = math.clamp(math.min(u / ramp, (storm.dur - u) / ramp), 0, 1)
      elseif u >= storm.dur then
        storm = nil
      end
    end
    setStormK(k)
  end
  G.on("roundStart", function()
    storm = nil
    setStormK(0)
  end)

  ---------------------------------------------------------------- 阵亡镜头（战地那种：死了以后镜头转过去、拉近，看清是谁打死的）
  -- Round.lua 记完阵亡调 G.killcam(P, killer)：killer 是伤害记录里最后打伤的（真人 by、机器人 bot）。算出凶手现在在哪，只发给死的人：
  --   { p 凶手的位置, from 死的人头的位置, name 名字, d 距离（格）, uid 真人的 UserId }；客户端（Warfx.lua）镜头转过去、拉近、标出来
  function G.killcam(P, killer)
    if not killer or not P or not P.pl then return end
    local pos
    local K = killer.by
    if K and K ~= P then
      local root = K.vehicle and K.vehicle.root
      if root then
        pos = root.CFrame.Position
      else
        local ch = K.char or (K.pl and K.pl.Character)
        local h = ch and ch:FindFirstChild("HumanoidRootPart")
        pos = h and h.CFrame.Position
      end
    elseif killer.bot then
      local e = killer.bot.e
      pos = e and e.root and e.root.CFrame.Position
    end
    if not pos then return end
    local ch = P.char or P.pl.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local from = hrp and (hrp.CFrame.Position + Vector3.new(0, 1.6, 0)) or nil   -- 眼睛的高度
    G.msg(P.pl, "killcam", { p = pos, from = from, name = killer.name, d = from and (pos - from).Magnitude or nil,
      uid = K and K.pl and K.pl.UserId or nil })
  end

  G.onFrame(function(dt)
    stepCraters()
    stepIllum()
    stepStorm(dt)
    if not scanned and G.worldReady then scanBlds() end
  end)
end

return Battle
