-- Roblox全面大战场（客户端）——地图上的树林、灌木、石头、草丛、花丛：按离镜头的距离摆出来（只在本机，不挡子弹、不挡人和车）
--   长在哪由 Flora.lua 按格子算（每个人看到的一样）；这里管「画多少、画哪一版」：
--     针叶树近处（130 格内）是完整的树、中距离（210 格内）是作者给的简化版、再远到 1300 格是公告板（两片交叉的贴图；松树借冷杉的）；
--     阔叶树、枯树 540 格内、灌木倒木 300 格内、石头 480 格内；草丛 115 格内、花丛 135 格内；按画质设置整体放远 / 拉近（画质 6 时乘 0.9）
--     这样密林里原模型一共约两百万个三角形
--   模型：Studio 里导入了 models/scenery/scenery.glb（Imports.lua 收进 ReplicatedStorage.Imported.Scenery.<键>）就用原模型，
--     没导入用零件拼的（树干 + 几团球形树冠、石块；草不拼——地形草已经开了）
--   性能：同一种、同一档大小的模型放进对象池反复用（离开范围的挪到地下藏起来），一次 BulkMoveTo 挪完；每帧算格子、换模型都有上限
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

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
    local origin, n = V(), 0
    local byName = {}
    for _, pm in ipairs(m.parts) do byName[pm.name] = pm end
    for _, p in ipairs(parts) do
      local pm = byName[string.match(p.Name, "__([%w_]+)$") or ""]
      if pm then
        origin += p.Position - V(pm.c[1], pm.c[2], pm.c[3])
        n += 1
      end
    end
    if n == 0 then return nil end
    origin /= n
    local list = {}
    for _, p in ipairs(parts) do table.insert(list, { p = p, rel = CF(origin):ToObjectSpace(p.CFrame) }) end
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
      local p = it.p:Clone()
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
  local LAYERS = { "tree", "bush", "rock", "grass", "flower" }
  local maxR = 0
  for _, r in pairs(LAYER_R) do maxR = math.max(maxR, r) end

  local lastPos, timer = nil, 0
  local stats = { cells = 0, items = 0, live = 0, made = 0, genMs = 0 }
  G.sceneryStats = stats

  -- 一次更新：镜头附近的格子按距离挑版本；超出范围的收回池里
  local function update(budgetMs)
    local cp = cam.CFrame.Position
    local t0 = os.clock()
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

  -- 每帧：镜头挪了 10 格以上、或者过了 0.3 秒，更新一次（每次最多 4 毫秒算格子、400 处换模型）
  function G.stepScenery(dt)
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
