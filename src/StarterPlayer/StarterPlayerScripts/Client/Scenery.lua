-- Roblox全面大战场（客户端）——地图上的石头：按离镜头的距离摆出来（只在本机，不挡子弹、不挡人和车）
--   用户：花草树木删掉，用 Roblox 自带的草更合适——树林、灌木、草丛、花丛不再摆（下面 LAYERS 只留 rock），草地上是地形自带的会动的草；
--   下面的说明是原来摆树林时写的，树的代码留着（LAYERS 里加回 "tree" 等就恢复）
--   长在哪由 Flora.lua 按格子算（每个人看到的一样）；这里管「画多少、画哪一版」：
--     针叶树近处（130 格内）是完整的树、中距离（210 格内）是作者给的简化版、再远到 1300 格是公告板（两片交叉的贴图；松树借冷杉的）；
--     阔叶树、枯树 540 格内、灌木倒木 300 格内、石头 480 格内；草丛 115 格内、花丛 135 格内；按画质设置整体放远 / 拉近（画质 6 时乘 0.9）
--     这样密林里原模型一共约两百万个三角形
--   模型：Studio 里导入了 models/scenery/scenery.glb（Imports.lua 收进 ReplicatedStorage.Imported.Scenery.<键>）就用原模型，
--     没导入用零件拼的（树干 + 几团球形树冠、石块；草不拼——地形草已经开了）
--   性能：同一种、同一档大小的模型放进对象池反复用（离开范围的挪到地下藏起来），一次 BulkMoveTo 挪完；每帧算格子、换模型都有上限
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Tint = require(script.Parent:WaitForChild("Tint"))   -- 导入的贴图没出来时的底色（原贴图的平均色）
local TURN = require(RS:WaitForChild("ImportTurn")).TURN   -- 导入的每块网格被 Roblox 转了半圈（ImportTurn.lua）：摆的时候转回来

local Scenery = {}

function Scenery.init(G)
  local Flora = require(RS:WaitForChild("Flora"))
  local META = require(RS:WaitForChild("SceneryMeta"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local CELL = Flora.CELL
  local HIDE = CF(0, -6000, 0)

  local folder = Instance.new("Folder")
  folder.Name = "Scenery"
  folder.Parent = workspace
  G.sceneryFolder = folder

  -- 画质（1～10；自动按 6）：距离整体乘 0.65～1.1
  local quality = 6
  pcall(function()
    local lvl = UserSettings():GetService("UserGameSettings").SavedQualityLevel
    local n = tonumber(string.match(tostring(lvl), "(%d+)$"))
    if n then quality = n end
  end)
  local K = 0.6 + quality * 0.05
  local D = { near = 130 * K, mid = 210 * K, far = 1300 * K, broad = 540 * K, bush = 300 * K, rock = 480 * K, grass = 115 * K, flower = 135 * K }
  -- 没有远景版本的针叶树：远处借身高差不多的冷杉公告板（松树 50 格高 → fir2_f，小冷杉 → fir5_f）
  local FAR_PROXY = { pine = "fir2_f", nfir = "fir5_f" }
  local LAYER_R = { tree = D.far, bush = D.bush, rock = D.rock, grass = D.grass, flower = D.flower }
  G.sceneryDist = D

  -- 这一株在这个距离画哪一版（nil = 不画）
  local function want(k, d)
    local m = META[k]
    if not m then return nil end
    local kind = m.kind
    if kind == "conifer" or kind == "young" then
      if d < D.near then return k end
      if d < D.mid then return META[k .. "_m"] and (k .. "_m") or k end
      local f = META[k .. "_f"] and (k .. "_f") or FAR_PROXY[k]
      if f then return (d < D.far) and f or nil end
      return (d < D.broad) and k or nil
    elseif kind == "broad" or kind == "dead" then return (d < D.broad) and k or nil
    elseif kind == "bush" or kind == "log" then return (d < D.bush) and k or nil
    elseif kind == "rock" or kind == "outcrop" then return (d < D.rock) and k or nil
    elseif kind == "grass" then return (d < D.grass) and k or nil
    elseif kind == "flower" then return (d < D.flower) and k or nil end
    return nil
  end

  ---------------------------------------------------------------- 模板：导入的原模型，或者零件拼的

  local templates = {}   -- [键] = { { p = 零件, rel = 相对这株原点的 CFrame }, … }（false = 这种不画）
  local function importedFolder()
    local imp = RS:FindFirstChild("Imported")
    return imp and imp:FindFirstChild("Scenery")
  end
  local function prepPart(p, shadow)
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.CastShadow = shadow
  end
  -- 零件拼的：按种类、高、冠幅
  local TRUNK, NEEDLE, LEAF, BUSHC, ROCK = RGB(86, 66, 50), RGB(34, 58, 36), RGB(64, 96, 48), RGB(58, 84, 46), RGB(112, 110, 104)
  local function ball(list, d, c, color, mat)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = V(d, d, d)
    p.Color = color
    p.Material = mat or Enum.Material.Grass
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    table.insert(list, { p = p, rel = CF(c) })
  end
  local function trunk(list, h, dia, color)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Cylinder
    p.Size = V(h, dia, dia)
    p.Color = color or TRUNK
    p.Material = Enum.Material.Wood
    table.insert(list, { p = p, rel = CF(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2) })
  end
  local function fallback(k)
    local base = string.gsub(k, "_[mf]$", "")
    local m = META[base] or META[k]
    if not m then return false end
    local list = {}
    local h, r = m.h, m.r
    local kind = m.kind
    if kind == "conifer" or kind == "young" then
      trunk(list, h * 0.35, math.max(0.8, h * 0.035))
      for i = 0, 3 do   -- 下面大、上面小的几团：冷杉的样子
        local t = i / 3
        ball(list, r * 1.5 * (1 - t * 0.72), V(0, h * (0.32 + t * 0.48), 0), NEEDLE)
      end
    elseif kind == "broad" then
      trunk(list, h * 0.5, math.max(0.9, h * 0.03))
      ball(list, r * 1.3, V(0, h * 0.62, 0), LEAF)
      ball(list, r * 0.95, V(r * 0.35, h * 0.78, r * 0.2), LEAF)
      ball(list, r * 0.85, V(-r * 0.3, h * 0.74, -r * 0.25), LEAF)
    elseif kind == "dead" then
      trunk(list, h * 0.9, math.max(0.7, h * 0.025), RGB(96, 84, 72))
    elseif kind == "bush" then
      ball(list, r * 1.3, V(0, r * 0.45, 0), BUSHC)
      ball(list, r * 0.9, V(r * 0.4, r * 0.35, 0), BUSHC)
    elseif kind == "log" then
      local p = Instance.new("Part")
      p.Shape = Enum.PartType.Cylinder
      p.Size = V(r * 1.8, 1.6, 1.6)
      p.Color, p.Material = TRUNK, Enum.Material.Wood
      table.insert(list, { p = p, rel = CF(0, 0.8, 0) })
    elseif kind == "rock" or kind == "outcrop" then
      local n = (kind == "outcrop") and 3 or 1
      for i = 1, n do
        local p = Instance.new("Part")
        p.Size = V(r * 1.1, h * 0.9, r * 0.9) * ((i == 1) and 1 or 0.7)
        p.Color, p.Material = ROCK, Enum.Material.Rock
        table.insert(list, { p = p, rel = CF((i - 1) * r * 0.5, h * 0.4, (i % 2) * r * 0.3) * CFrame.Angles(0.2 * i, i, 0.15) })
      end
    elseif kind == "flower" and k == "flowers" then
      for i = 1, 6 do
        ball(list, 0.55, V(math.cos(i * 1.7) * r * 0.5, 0.7, math.sin(i * 2.3) * r * 0.5), RGB(236, 204, 40), Enum.Material.SmoothPlastic)
      end
    else
      return false   -- 草丛：零件拼不出来（地形草已经有了）
    end
    return list
  end
  -- 导入的原模型：各块按元数据里的中心找回这株的原点
  local function fromImport(k)
    local f = importedFolder()
    local src = f and f:FindFirstChild(k)
    local m = META[k]
    if not src or not m then return nil end
    local parts = {}
    for _, p in ipairs(src:GetChildren()) do
      if p:IsA("BasePart") then table.insert(parts, p) end
    end
    if #parts == 0 then return nil end
    -- 各块照元数据里的中心摆（相对这株的原点），再补回导入时转掉的半圈（ImportTurn.lua）——不用导入零件自己的位置和朝向
    local byName = {}
    for _, pm in ipairs(m.parts) do byName[pm.name] = pm end
    local list = {}
    for _, p in ipairs(parts) do
      local pm = byName[string.match(p.Name, "__([%w_]+)$") or ""]
      if pm then table.insert(list, { p = p, rel = CF(pm.c[1], pm.c[2], pm.c[3]) * TURN }) end
    end
    if #list == 0 then return nil end
    return list
  end
  local function template(k)
    local t = templates[k]
    if t == nil then
      t = fromImport(k) or fallback(k)
      templates[k] = t
    end
    return t
  end
  G.sceneryImported = function() local f = importedFolder() return f ~= nil and #f:GetChildren() > 0 end

  ---------------------------------------------------------------- 对象池（同一种、同一档大小）

  local pools = {}   -- [键 .. "#" .. 档] = { 实例, … }
  local nLive, nMade = 0, 0
  local function bucketOf(s) return math.clamp(math.floor((s - 0.85) / 0.15 + 0.5), 0, 2) end
  local function newInst(k, b)
    local t = template(k)
    if not t then return nil end
    local s = 0.85 + b * 0.15
    local kind = META[k] and META[k].kind or ""
    local shadow = (kind == "conifer" or kind == "broad" or kind == "rock" or kind == "outcrop") and quality >= 7
    local inst = { k = k, b = b, parts = {}, rels = {} }
    for i, it in ipairs(t) do
      local p = Tint.fix(it.p:Clone(), it.p)
      prepPart(p, shadow)
      p.Size = it.p.Size * s
      local r = it.rel
      inst.parts[i] = p
      inst.rels[i] = CF(r.Position * s) * (r - r.Position)
      p.CFrame = HIDE
      p.Parent = folder
    end
    nMade += 1
    return inst
  end
  local moveP, moveC = {}, {}
  local function queueMove(inst, cf)
    for i, p in ipairs(inst.parts) do
      moveP[#moveP + 1] = p
      moveC[#moveC + 1] = cf * inst.rels[i]
    end
  end
  local function take(k, s)
    local b = bucketOf(s)
    local key = k .. "#" .. b
    local pool = pools[key]
    local inst = pool and table.remove(pool)
    if not inst then inst = newInst(k, b) end
    if inst then nLive += 1 end
    return inst
  end
  local function give(inst)
    local key = inst.k .. "#" .. inst.b
    pools[key] = pools[key] or {}
    table.insert(pools[key], inst)
    queueMove(inst, HIDE)
    nLive -= 1
  end

  ---------------------------------------------------------------- 格子

  local cells = {}   -- [格子键] = { cx, cz, [层] = { 株, … } }
  local function cellKey(cx, cz) return cx * 100003 + cz end
  -- 用户：花草树木删掉——树、灌木、草丛、花丛都不摆了，只留石头；地形自带的草叶后来也去掉了（用户 11-21：直接把草删掉——World.lua 写地形不用 Grass 材质；Terrain.Decoration 脚本改不了）
  local LAYERS = { "rock" }
  local maxR = 0
  for _, l in ipairs(LAYERS) do maxR = math.max(maxR, LAYER_R[l] or 0) end

  local lastPos, timer = nil, 0
  -- 自动画质（Fx.lua 的 G.perfK）：卡了树林画得近一点，流畅了再放远；变了就整片重挑一次
  local D0, curK = {}, 1
  for name, r in pairs(D) do D0[name] = r end
  local function applyK(k)
    curK = k
    for name, r in pairs(D0) do D[name] = r * k end
    LAYER_R.tree, LAYER_R.bush, LAYER_R.rock, LAYER_R.grass, LAYER_R.flower = D.far, D.bush, D.rock, D.grass, D.flower
    maxR = 0
    for _, l in ipairs(LAYERS) do maxR = math.max(maxR, LAYER_R[l] or 0) end
    lastPos = nil
  end
  local stats = { cells = 0, items = 0, live = 0, made = 0, genMs = 0 }
  G.sceneryStats = stats

  -- 车压着的草、花、灌木、石头不画（用户：坦克都卡在地底下——草丛一丛 2～3.5 格高、石头半埋，原来照样从车身里长出来，
  --   履带、车体下半截全被盖住，夜视里看着就像车陷在地里）。车的占地（长宽各放 3 格）按车头方向算；树不管（车从树林穿过去照旧）
  local FLAT_KIND = { grass = true, flower = true, bush = true, log = true, rock = true, outcrop = true }
  local flats = {}
  local function collectFlats(cp)
    table.clear(flats)
    for _, v in pairs(G.views or {}) do
      local d = v.def
      if v.kind == "veh" and d and v.cf and d.L and d.W then
        local p = v.cf.Position
        if math.abs(p.X - cp.X) < maxR and math.abs(p.Z - cp.Z) < maxR then
          local lv = v.cf.LookVector
          local fx, fz = lv.X, lv.Z
          local m = math.sqrt(fx * fx + fz * fz)
          if m > 1e-3 then fx, fz = fx / m, fz / m else fx, fz = 0, -1 end
          table.insert(flats, { x = p.X, z = p.Z, fx = fx, fz = fz, hl = d.L / 2 + 3, hw = d.W / 2 + 3, r = math.sqrt(d.L * d.L + d.W * d.W) / 2 + 9 })
        end
      end
    end
  end
  local function underVeh(it)
    if #flats == 0 then return false end
    local m = META[it.k]
    if not m or not FLAT_KIND[m.kind] then return false end
    local rr = math.min(4, (m.r or 2) * (it.s or 1) * 0.5)
    for _, f in ipairs(flats) do
      local dx, dz = it.x - f.x, it.z - f.z
      if math.abs(dx) < f.r and math.abs(dz) < f.r then
        local along = dx * f.fx + dz * f.fz
        local side = dx * f.fz - dz * f.fx
        if math.abs(along) < f.hl + rr and math.abs(side) < f.hw + rr then return true end
      end
    end
    return false
  end
  G.sceneryUnderVeh = underVeh

  -- 一次更新：镜头附近的格子按距离挑版本；超出范围的收回池里
  local function update(budgetMs)
    local cp = cam.CFrame.Position
    local t0 = os.clock()
    collectFlats(cp)
    local ccx, ccz = math.floor(cp.X / CELL), math.floor(cp.Z / CELL)
    local rc = math.ceil(maxR / CELL) + 1
    local changes = 0
    local seen = {}
    -- 由近到远：先摆近的（预算用完了远处下次再说）
    local order = {}
    for dz = -rc, rc do
      for dx = -rc, rc do
        local x0, z0 = (ccx + dx) * CELL, (ccz + dz) * CELL
        local ex = math.max(x0 - cp.X, 0, cp.X - (x0 + CELL))
        local ez = math.max(z0 - cp.Z, 0, cp.Z - (z0 + CELL))
        local d = math.sqrt(ex * ex + ez * ez)
        if d < maxR then table.insert(order, { ccx + dx, ccz + dz, d }) end
      end
    end
    table.sort(order, function(a, b) return a[3] < b[3] end)
    for _, o in ipairs(order) do
      local cx, cz, dCell = o[1], o[2], o[3]
      local key = cellKey(cx, cz)
      seen[key] = true
      local c = cells[key]
      if not c then
        c = { cx = cx, cz = cz }
        cells[key] = c
      end
      for _, layer in ipairs(LAYERS) do
        if dCell < LAYER_R[layer] then
          local list = c[layer]
          if not list and os.clock() - t0 < budgetMs / 1000 then
            local g0 = os.clock()
            list = Flora.cell(cx, cz, layer)
            stats.genMs += (os.clock() - g0) * 1000
            c[layer] = list
            stats.items += #list
          end
          if list then
            for _, it in ipairs(list) do
              local dx, dz = it.x - cp.X, it.z - cp.Z
              local dy = (it.y - cp.Y) * 0.5   -- 天上往下看：高度算一半（飞机上看地面不至于全变公告板）
              local d = math.sqrt(dx * dx + dz * dz + dy * dy)
              local w = want(it.k, d)
              if w and underVeh(it) then w = nil end   -- 车压着：先收起来，车开走了下一次更新再摆回去
              if w ~= it.cur then
                if changes < 400 then
                  if it.inst then give(it.inst) it.inst = nil end
                  if w then
                    local inst = take(w, it.s)
                    if inst then
                      queueMove(inst, CF(it.x, it.y, it.z) * CFrame.Angles(0, it.yaw, 0))
                      it.inst = inst
                    end
                  end
                  it.cur = w
                  changes += 1
                end
              end
            end
          end
        elseif c[layer] then   -- 这一层超出范围：全收回
          for _, it in ipairs(c[layer]) do
            if it.inst then give(it.inst) it.inst = nil end
            it.cur = nil
          end
        end
      end
    end
    -- 远得不在范围里的格子：收回、扔掉（再回来重新算）
    for key, c in pairs(cells) do
      if not seen[key] then
        for _, layer in ipairs(LAYERS) do
          for _, it in ipairs(c[layer] or {}) do if it.inst then give(it.inst) it.inst = nil end end
        end
        cells[key] = nil
      end
    end
    if #moveP > 0 then
      workspace:BulkMoveTo(moveP, moveC, Enum.BulkMoveMode.FireCFrameChanged)
      table.clear(moveP)
      table.clear(moveC)
    end
    local n = 0
    for _ in pairs(cells) do n += 1 end
    stats.cells, stats.live, stats.made = n, nLive, nMade
    -- 按版本数：摆出来多少株、原模型的话一共多少三角形（调距离用）
    local byKey, tris = {}, 0
    for _, c in pairs(cells) do
      for _, layer in ipairs(LAYERS) do
        for _, it in ipairs(c[layer] or {}) do
          if it.cur then
            byKey[it.cur] = (byKey[it.cur] or 0) + 1
            tris += (META[it.cur] and META[it.cur].tris or 0)
          end
        end
      end
    end
    stats.byKey, stats.tris = byKey, tris
    return changes
  end
  G.sceneryUpdate = update

  ---------------------------------------------------------------- 远海
  -- 地形的海水只灌到 ±Map.R；再往外是跟着镜头走的一圈平面（11 × 11 块，每块 2048 格，镜头外一万格以上，盖过雾的尽头 8500）：飞到哪都看得到海一直铺到天边，
  --   不用在服务器上摆一大片（用户：海洋过于小了）。块按 2048 的格子对齐，地形海水那一片里的不摆（不和地形水面打架）
  local Map = G.Map
  -- 21 × 21 块：镜头外两万一千格（用户 11-22：视野改成无限远，大气放淡以后原来一万五千格的边看得出来；地形海水铺到 ±SEA_R 以后，这圈平面只在作战区边上才看得到）
  local OS, ON = 2048, 10
  local ocean = Instance.new("Folder")
  ocean.Name = "Ocean"
  ocean.Parent = workspace
  local tiles = {}
  for i = 1, (2 * ON + 1) ^ 2 do
    local p = Instance.new("Part")
    p.Name = "Sea"
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Size = V(OS, 1, OS)
    p.Material = Enum.Material.SmoothPlastic   -- 原来是半透明玻璃：要折射，铺满半个屏幕最费（用户：太卡了）；夜里不透明的看着一样
    p.Color = RGB(24, 84, 102)   -- 往地形海水的颜色靠（Terrain.WaterColor 30, 112, 136 透过深水看暗一些）
    p.Reflectance = 0.22
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CFrame = CF(0, -60000, 0)
    p.Parent = ocean
    tiles[i] = p
  end
  local seaKey = nil
  local shown, moveL, moveCF = {}, {}, {}
  local RI, SEA_Y = 0, -0.6
  -- 换地图：海岛是海水（地形海水占了 [−RI, RI) 这些格：近海 ±R 深水 + 外面 ±SEA_R 一圈薄水，World.lua）；
  --   沙海（Map.DESERT）也没有海：地形一直写到 ±SEA_R（外面一圈平地），再往外这圈平面是沙地，顶面和平原一样高
  local function oceanStyle()
    local desert = Map.DESERT
    RI = math.floor((Map.SEA_R or Map.R or 4096) / OS)
    SEA_Y = Map.DESERT and ((Map.PLAIN or 12) - 0.5) or -0.6
    local sand = (Map.DESERT and Map.COLORS and Map.COLORS.Sand) or RGB(176, 142, 100)
    for _, p in ipairs(tiles) do
      p.Color = desert and sand or RGB(24, 84, 102)
      p.Material = desert and Enum.Material.Sand or Enum.Material.SmoothPlastic
      p.Reflectance = desert and 0 or 0.22
      p.Name = desert and "FarSand" or "Sea"
    end
    seaKey = nil
  end
  oceanStyle()
  local function stepOcean()
    local c = cam.CFrame.Position
    local gx, gz = math.floor(c.X / OS), math.floor(c.Z / OS)
    local key = gx * 65536 + gz
    if key == seaKey then return end
    seaKey = key
    -- 一直挂在 Ocean 下面，一次 BulkMoveTo 挪完（原来过一块就把几百块零件摘下、挂上，开飞机每过两千格画面顿一下）；
    --   落在地形海水那片里的沉到底下（不和地形水面打架）
    local n = 0
    for i = gx - ON, gx + ON do
      for k = gz - ON, gz + ON do
        n += 1
        local inT = i >= -RI and i < RI and k >= -RI and k < RI
        moveL[n] = tiles[n]
        moveCF[n] = CF((i + 0.5) * OS, inT and -60000 or SEA_Y, (k + 0.5) * OS)
        shown[n] = not inT
      end
    end
    workspace:BulkMoveTo(moveL, moveCF, Enum.BulkMoveMode.FireCFrameChanged)
  end
  G.oceanTiles = function()
    local n = 0
    for i = 1, #tiles do if shown[i] then n += 1 end end
    return n
  end

  -- 换地图：石头全收回重算（Flora 按新地图的高度、坡度、路摆），远处那圈换成海或沙
  local function resetCells()
    for key, c in pairs(cells) do
      for _, layer in ipairs(LAYERS) do
        for _, it in ipairs(c[layer] or {}) do if it.inst then give(it.inst) it.inst = nil end end
      end
      cells[key] = nil
    end
    if #moveP > 0 then
      workspace:BulkMoveTo(moveP, moveC, Enum.BulkMoveMode.FireCFrameChanged)
      table.clear(moveP)
      table.clear(moveC)
    end
    lastPos = nil
  end
  if G.onMap then
    G.onMap(function()
      if Flora.reset then Flora.reset() end
      resetCells()
      oceanStyle()
    end)
  end

  -- 每帧：镜头挪了 10 格以上、或者过了 0.3 秒，更新一次（每次最多 4 毫秒算格子、400 处换模型）
  function G.stepScenery(dt)
    stepOcean()
    local pk = G.perfK or 1
    if math.abs(pk - curK) > 0.01 then applyK(pk) end
    timer += dt
    local cp = cam.CFrame.Position
    if (lastPos and (cp - lastPos).Magnitude < 10 and timer < 0.3) then return end
    if timer < 0.08 then return end
    timer = 0
    lastPos = cp
    update(4)
  end
  local _ = Players
end

return Scenery
