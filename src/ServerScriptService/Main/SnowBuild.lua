-- 全面大战场：雪山（MapSnow.lua）开服时盖的东西——
--   · 房子（Map.BLD）：导入了 models/bld/snow.glb 就摆 Sketchfab 的写实模型（World.building：看不见的碰撞盒挡人挡车挡子弹，废墟按自己的碰撞盒，
--     炸多了照样塌），没导入用零件拼一座同样大小的（积雪坡屋顶的木屋、红谷仓、只剩半截墙的废墟）
--   · 锯木厂（A）的大工棚和木料堆、雷达站（B）的雷达塔（天线会转）、水电站（D）的厂房和湖边的坝、山口检查站（E）的栏杆岗亭沙袋
--   · 路过河的地方一座桥（主路石桥、支路钢桥）、主路两边的雪桩、几道反坦克墩和钢刺猬（坦克的掩体，步兵的据点）
--   · 交战区四周看不见的墙（只挡人和车；飞机、子弹、炮弹照样过去）：谷外的山体模型脚下只有一层体素壳，壳外面就没有地面了
--   用户 11-26 晚：「多搞点房屋 你自己去sketchfeb找 再加点坏掉的屋子这样」「雪地地图交战一定要搞得地形复崎岖方便坦克互相打起来有意思」
local RS = game:GetService("ReplicatedStorage")
local Map = require(RS:WaitForChild("Map"))

local SnowBuild = {}

local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
local CYL = Enum.PartType.Cylinder
local UP = CFrame.Angles(0, 0, math.pi / 2)   -- 圆柱的轴在 X：立起来

local SNOW = RGB(238, 242, 248)
local LOG = RGB(104, 74, 52)
local LOG2 = RGB(84, 60, 44)
local STONE = RGB(128, 124, 118)
local CONC = RGB(158, 156, 150)
local BURNT = RGB(42, 38, 36)

function SnowBuild.build(World, root, G)
  local part, cyl = World.part, World.cyl
  local PL = Map.PLAIN
  local function folder(name, parent)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
  end
  local function slab(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape, true) end
  local function deco(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape) end
  local function wedge(m, size, cf, col, mat, solid)
    local w = Instance.new("WedgePart")
    w.Anchored, w.Size, w.CFrame, w.Color, w.Material = true, size, cf, col, mat or MAT.SmoothPlastic
    if not solid then w.CanCollide, w.CanQuery, w.CanTouch = false, false, false end
    w.Parent = m
    return w
  end
  local function atomic(m) pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end) end
  local function gy(x, z) return Map.ground(x, z) end
  local sf = folder("Snow", root)
  local nParts0 = 0

  ---------------------------------------------------------------- 房子

  local bf = folder("Buildings", sf)
  local function rnd(b, k) return ((b.sd * 9301 + k * 49297) % 233280) / 233280 end
  local function tag(m, b, base, w, h, d, kind)
    m:SetAttribute("Bld", kind)
    m:SetAttribute("BldBase", base)
    m:SetAttribute("BldSize", V(w, h, d))
    m:SetAttribute("CityIdx", b.id)   -- 塌了以后电脑车的视线不再算它（Map.lineClear）
    atomic(m)
    m.Parent = bf
  end
  -- 两坡屋顶（脊沿 X）：两块楔子，上面各盖一层雪
  local function gable(m, base, w, d, y0, rh, col, snowK)
    for _, sd in ipairs({ -1, 1 }) do
      local c = base * CF(0, y0 + rh / 2, sd * (d / 4 + 0.6)) * CFrame.Angles(0, (sd > 0) and math.pi or 0, 0)
      local r = wedge(m, V(w + 3, rh, d / 2 + 1.2), c, col, MAT.WoodPlanks, true)
      r.CastShadow = true
      if snowK > 0 then   -- 雪：贴着坡面的一层（同一块楔子往上挪一点、薄一点）
        local s2 = wedge(m, V(w + 3.4, rh * 0.98, d / 2 + 1.4), c * CF(0, 0.55, 0), SNOW, MAT.Snow)
        s2.CastShadow = false
      end
    end
  end
  -- 零件拼的木屋（没导入 snow.glb 时；尺寸照模型的）：石头勒脚、原木墙、窗带、积雪的坡屋顶、烟囱
  local function homeParts(b, w, h, d, base)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    local plinth = math.min(3, h * 0.12)
    slab(m, V(w, plinth, d), base * CF(0, plinth / 2, 0), STONE, MAT.Cobblestone)
    local eave = h * 0.55
    slab(m, V(w - 1, eave - plinth, d - 1), base * CF(0, plinth + (eave - plinth) / 2, 0), (rnd(b, 1) < 0.5) and LOG or LOG2, MAT.Wood)
    deco(m, V(w - 0.6, 2.6, d - 0.6), base * CF(0, plinth + (eave - plinth) * 0.55, 0), RGB(40, 46, 52), MAT.Glass).CastShadow = false
    gable(m, base, w, d, eave, h - eave, RGB(70, 52, 40), 1)
    slab(m, V(3, h * 0.3, 3), base * CF(w * 0.25, h * 0.85, d * 0.12), STONE, MAT.Brick)
    deco(m, V(5, 8, 0.4), base * CF(0, plinth + 4, -d / 2 - 0.2), RGB(70, 48, 34), MAT.Wood)
    tag(m, b, base, w, h, d, "snow_home")
  end
  local function barnParts(b, w, h, d, base)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    local eave = h * 0.5
    slab(m, V(w, eave, d), base * CF(0, eave / 2, 0), (rnd(b, 2) < 0.6) and RGB(122, 44, 36) or RGB(96, 76, 58), MAT.WoodPlanks)
    gable(m, base, w, d, eave, h - eave, RGB(64, 60, 58), 1)
    deco(m, V(w * 0.3, eave * 0.8, 0.4), base * CF(0, eave * 0.4, -d / 2 - 0.2), RGB(60, 40, 30), MAT.WoodPlanks)
    tag(m, b, base, w, h, d, "snow_barn")
  end
  -- 废墟：勒脚、几截高高低低的残墙、焦黑的梁、碎砖堆（没有屋顶）
  local function ruinParts(b, w, h, d, base)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    slab(m, V(w * 0.8, 2, d * 0.8), base * CF(0, 1, 0), STONE, MAT.Cobblestone)
    local walls = { { 0, -d * 0.38, w * 0.8, 2.2 }, { 0, d * 0.38, w * 0.8, 2.2 }, { -w * 0.38, 0, 2.2, d * 0.8 }, { w * 0.38, 0, 2.2, d * 0.8 } }
    for i, wl in ipairs(walls) do
      local hh = h * (0.25 + 0.6 * rnd(b, i + 10))
      if rnd(b, i + 20) > 0.2 then
        slab(m, V(wl[3], hh, wl[4]), base * CF(wl[1], hh / 2, wl[2]), (rnd(b, 3) < 0.5) and STONE or RGB(116, 96, 80), MAT.Brick)
      end
    end
    for q = 1, 3 do   -- 焦黑的梁斜插着
      deco(m, V(1.4, 1.4, d * 0.7), base * CF((rnd(b, q + 30) - 0.5) * w * 0.6, h * 0.25, 0) * CFrame.Angles(0.5 - rnd(b, q + 40), 0, 0), BURNT, MAT.Wood)
    end
    for q = 1, 3 do   -- 碎砖堆
      wedge(m, V(w * 0.3, 3 + rnd(b, q + 50) * 3, d * 0.3), base * CF((rnd(b, q + 60) - 0.5) * w * 0.5, 2.5, (rnd(b, q + 70) - 0.5) * d * 0.5) * CFrame.Angles(0, rnd(b, q + 80) * 6.28, 0),
        RGB(112, 104, 98), MAT.Slate, true)
    end
    tag(m, b, base, w, h, d, "snow_ruin")
  end
  local nModel = 0
  local function house(b)
    local key = b.model
    if World.importedBld and World.importedBld(key) then
      local _, m = World.building(bf, key, b.x, b.z, b.rot or 0, { scale = b.scale or 1, coll = Map.SNOW_COLL and Map.SNOW_COLL[key] })
      if m then
        m:SetAttribute("CityIdx", b.id)
        nModel += 1
        return
      end
    end
    -- 没导入：照模型的尺寸用零件拼（模型自己的长宽高 × 缩放，转角同模型）
    local w, d, h = Map.modelDims(key)
    local s = b.scale or 1
    w, d, h = w * s, d * s, h * s
    local y = math.min(gy(b.x, b.z), gy(b.x - b.w / 2, b.z - b.d / 2), gy(b.x + b.w / 2, b.z + b.d / 2)) - 0.25
    local base = CF(b.x, y, b.z) * CFrame.Angles(0, b.rot or 0, 0)
    if string.sub(key, 1, 5) == "ruin_" then ruinParts(b, w, h, d, base)
    elseif string.sub(key, 1, 5) == "barn_" then barnParts(b, w, h, d, base)
    else homeParts(b, w, h, d, base) end
  end
  G.snowModels = function() return nModel end   -- 测试用

  -- 锯木厂的大工棚：一圈柱子、两坡铁皮顶（积雪），里面一台带锯、几堆原木
  local function mill(b)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    local base = CF(b.x, gy(b.x, b.z) - 0.2, b.z)
    local w, d, h = b.w, b.d, b.h
    for i = 0, 6 do
      for _, sz in ipairs({ -1, 1 }) do
        slab(m, V(1.6, h * 0.6, 1.6), base * CF(-w / 2 + 2 + i * (w - 4) / 6, h * 0.3, sz * (d / 2 - 1)), LOG2, MAT.Wood)
      end
    end
    gable(m, base, w, d, h * 0.6, h * 0.4, RGB(92, 96, 100), 1)
    slab(m, V(w * 0.9, 1, d * 0.9), base * CF(0, 0.5, 0), RGB(120, 104, 84), MAT.WoodPlanks)
    slab(m, V(14, 5, 3), base * CF(0, 2.5, 0), RGB(60, 64, 70), MAT.Metal)   -- 带锯台
    tag(m, b, base, w, h, d, "snow_mill")
  end
  -- 水电站厂房：混凝土大厅、高窗、屋顶积雪、侧面变压器
  local function plant(b)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    local base = CF(b.x, gy(b.x, b.z) - 0.2, b.z)
    local w, d, h = b.w, b.d, b.h
    slab(m, V(w, h, d), base * CF(0, h / 2, 0), CONC, MAT.Concrete)
    deco(m, V(w + 0.3, h * 0.42, d * 0.6), base * CF(0, h * 0.55, 0), RGB(40, 52, 60), MAT.Glass).Reflectance = 0.15
    deco(m, V(w + 0.6, 1.2, d + 0.6), base * CF(0, h + 0.6, 0), SNOW, MAT.Snow).CastShadow = false
    for i = -1, 1 do   -- 变压器
      slab(m, V(8, 9, 6), base * CF(i * 14, 4.5, d / 2 + 10), RGB(82, 90, 84), MAT.Metal)
      deco(m, V(1, 6, 1), base * CF(i * 14, 12, d / 2 + 10), RGB(210, 200, 180), MAT.SmoothPlastic)
    end
    tag(m, b, base, w, h, d, "snow_plant")
  end
  -- 营房、岗楼（雷达站、检查站）：低矮的板房，平顶积雪
  local function hut(b)
    local m = Instance.new("Model")
    m.Name = "Bld_snow_" .. b.id
    local base = CF(b.x, gy(b.x, b.z) - 0.2, b.z)
    local w, d, h = b.w, b.d, b.h
    slab(m, V(w, h, d), base * CF(0, h / 2, 0), RGB(96, 104, 92), MAT.Concrete)
    deco(m, V(w + 0.3, 2.4, d + 0.3), base * CF(0, h * 0.6, 0), RGB(40, 46, 52), MAT.Glass).CastShadow = false
    deco(m, V(w + 1, 1, d + 1), base * CF(0, h + 0.5, 0), SNOW, MAT.Snow).CastShadow = false
    tag(m, b, base, w, h, d, "snow_hut")
  end
  local nB = 0
  for _, b in ipairs(Map.BLD) do
    local ok, err = pcall(function()
      if b.k == "model" then house(b)
      elseif b.k == "mill" then mill(b)
      elseif b.k == "plant" then plant(b)
      else hut(b) end
    end)
    if not ok then warn("[雪山] 第 " .. b.id .. " 座（" .. tostring(b.model or b.k) .. "）出错：" .. tostring(err)) end
    nB += 1
    if nB % 8 == 0 then task.wait() end
  end

  ---------------------------------------------------------------- 桥：路过河的地方（主路石桥：拱、栏板；支路钢桥：钢梁、栏杆）

  local brf = folder("Bridges", sf)
  for i, B in ipairs(Map.BRIDGES) do
    local m = Instance.new("Model")
    m.Name = "Bridge_" .. i
    local ax, az, bx, bz = B.ax, B.az, B.bx, B.bz
    local dx, dz = bx - ax, bz - az
    local L = math.sqrt(dx * dx + dz * dz) + 40   -- 两头各搭到岸上 20 格
    local c = V((ax + bx) / 2, PL + 0.35, (az + bz) / 2)
    local cf = CFrame.lookAt(c, c + V(dx, 0, dz))
    local stone = B.k == "main"
    local w = B.w
    slab(m, V(w, 2, L), cf * CF(0, -1, 0), stone and RGB(140, 134, 124) or RGB(70, 74, 78), stone and MAT.Cobblestone or MAT.DiamondPlate)
    for _, sx in ipairs({ -1, 1 }) do   -- 栏板 / 栏杆
      if stone then
        slab(m, V(2, 3.2, L), cf * CF(sx * (w / 2 + 1), 1.6, 0), RGB(150, 144, 134), MAT.Limestone)
      else
        slab(m, V(0.6, 3, L), cf * CF(sx * (w / 2 + 0.3), 1.5, 0), RGB(54, 58, 62), MAT.Metal)
        deco(m, V(1.2, 5, L), cf * CF(sx * (w / 2 - 0.8), -4.5, 0), RGB(54, 58, 62), MAT.Metal)   -- 钢梁
      end
    end
    -- 桥墩：每 40 格一个，立到冰面下面
    local n = math.max(1, math.floor(L / 40))
    for q = 1, n - 1 do
      local t = -L / 2 + q * L / n
      local p = (cf * CF(0, 0, t)).Position
      local bot = gy(p.X, p.Z) - 4
      local hh = math.max(4, PL - 2 - bot)
      slab(m, V(w * 0.8, hh, stone and 7 or 4), cf * CF(0, -2 - hh / 2, t), stone and RGB(120, 116, 108) or RGB(90, 92, 94), stone and MAT.Cobblestone or MAT.Concrete)
    end
    -- 雪：桥面两边堆着一溜
    for _, sx in ipairs({ -1, 1 }) do
      deco(m, V(2.4, 0.8, L - 4), cf * CF(sx * (w / 2 - 1.4), 0.4, 0), SNOW, MAT.Snow).CastShadow = false
    end
    atomic(m)
    m.Parent = brf
  end

  ---------------------------------------------------------------- 主路两边的雪桩（橙色，下雪看得见路在哪）

  local pf = folder("RoadPoles", sf)
  do
    local n = 0
    for _, s in ipairs(Map.SEGS) do
      if s[6] == "main" then
        local ax, az, bx, bz, w = s[1], s[2], s[3], s[4], s[5]
        local dx, dz = bx - ax, bz - az
        local L = math.sqrt(dx * dx + dz * dz)
        local ux, uz = dx / L, dz / L
        local step = 80
        for t = step / 2, L, step do
          for _, sd in ipairs({ -1, 1 }) do
            local x, z = ax + ux * t - uz * sd * (w / 2 + 3), az + uz * t + ux * sd * (w / 2 + 3)
            if Map.riverDist(x, z) > 90 and not Map.inBase(x, z, 40) then
              local y = gy(x, z)
              local p = deco(pf, V(0.5, 7, 0.5), CF(x, y + 3.5, z), ((n % 2) == 0) and RGB(226, 96, 30) or RGB(236, 236, 236), MAT.SmoothPlastic)
              p.CastShadow = false
              n += 1
            end
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 锯木厂（A）：几堆原木、成垛的木板

  local af = folder("Sawmill", sf)
  do
    local P = Map.POINTS[1]
    local R = Random.new(7311)
    for k = 1, 6 do   -- 原木堆：三层叠成梯形（挡步兵、车能当掩体）
      local x, z = P.x - 60 + R:NextNumber(-120, 160), P.z + 40 + R:NextNumber(-160, 120)
      if not Map.bldAt(x, z, 8) and not Map.onRoad(x, z, 6) then
        local y = gy(x, z)
        local yaw = R:NextNumber(0, math.pi)
        local base = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
        local L = R:NextNumber(26, 40)
        for row = 0, 2 do
          for i = 0, 3 - row do
            local p = slab(af, V(L, 3.2, 3.2), base * CF(0, 1.6 + row * 2.8, (i - (3 - row) / 2) * 3.3) * CFrame.Angles(0, 0, 0), LOG, MAT.Wood, CYL)
            p.CastShadow = row == 2
          end
        end
        deco(af, V(L, 0.6, (4 - 2) * 3.3 + 1), base * CF(0, 1.6 + 2 * 2.8 + 1.8, 0), SNOW, MAT.Snow).CastShadow = false
      end
      if k % 2 == 0 then task.wait() end
    end
    for k = 1, 4 do   -- 木板垛
      local x, z = P.x + 40 + R:NextNumber(-60, 60), P.z - 120 + R:NextNumber(-40, 40)
      if not Map.bldAt(x, z, 10) and not Map.onRoad(x, z, 6) then
        local y = gy(x, z)
        local base = CF(x, y, z) * CFrame.Angles(0, R:NextNumber(0, math.pi), 0)
        slab(af, V(18, 5, 7), base * CF(0, 2.5, 0), RGB(176, 140, 96), MAT.WoodPlanks)
        deco(af, V(18.4, 0.5, 7.4), base * CF(0, 5.25, 0), SNOW, MAT.Snow).CastShadow = false
      end
    end
  end

  ---------------------------------------------------------------- 雷达站（B）：格构塔、塔顶的雷达天线（会转）、天线杆、铁丝网

  local rf = folder("Radar", sf)
  do
    local P = Map.POINTS[2]
    local x, z = P.x + 30, P.z - 40
    local y = gy(x, z)
    local H = 46
    local m = Instance.new("Model")
    m.Name = "RadarTower"
    for _, o in ipairs({ { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } }) do
      slab(m, V(1.2, H, 1.2), CF(x + o[1], y + H / 2, z + o[2]), RGB(96, 100, 104), MAT.Metal)
    end
    for k = 1, 5 do   -- 横撑
      local yy = y + k * H / 6
      for _, o in ipairs({ { 0, -5, 10, 0.6 }, { 0, 5, 10, 0.6 }, { -5, 0, 0.6, 10 }, { 5, 0, 0.6, 10 } }) do
        deco(m, V(o[3], 0.6, o[4]), CF(x + o[1], yy, z + o[2]), RGB(96, 100, 104), MAT.Metal)
      end
    end
    slab(m, V(14, 1.2, 14), CF(x, y + H + 0.6, z), RGB(80, 84, 88), MAT.DiamondPlate)
    -- 天线：抛物面用一块弯不了的板凑——竖着的大板 + 背后的支架，绕塔中心转（Night.lua 的 spin）
    local dish = deco(m, V(22, 9, 1), CF(x, y + H + 7, z + 3) * CFrame.Angles(-0.25, 0, 0), RGB(214, 216, 220), MAT.SmoothPlastic)
    dish.CastShadow = true
    dish:SetAttribute("Anim", "spin")
    dish:SetAttribute("Spd", 0.12)
    dish:SetAttribute("Pivot", V(x, y + H + 7, z))
    local arm = deco(m, V(1, 1, 5), CF(x, y + H + 5, z + 1), RGB(70, 72, 76), MAT.Metal)
    arm:SetAttribute("Anim", "spin")
    arm:SetAttribute("Spd", 0.12)
    arm:SetAttribute("Pivot", V(x, y + H + 7, z))
    World.light(m, V(x, y + H + 13, z), RGB(255, 40, 40), 1.2, 16, 1.6):SetAttribute("Anim", "blink")
    atomic(m)
    m.Parent = rf
    -- 天线杆、发电机
    for _, o in ipairs({ { -90, 60, 30 }, { 120, -60, 24 } }) do
      local xx, zz = P.x + o[1], P.z + o[2]
      cyl(rf, o[3], 0.8, CF(xx, gy(xx, zz) + o[3] / 2, zz), RGB(120, 122, 124), MAT.Metal, true)
    end
    World.sandbags(rf, V(P.x, 0, P.z), 70, -0.6, 1.4, 3)
  end

  ---------------------------------------------------------------- 水电站（D）：湖西岸一道混凝土坝（坝顶走得了人）、两座取水塔

  local hf = folder("Hydro", sf)
  do
    local Lk = Map.LAKE   -- 湖在高台上（湖面比谷底高 40 格），坝挡在西头的豁口上，坝下是厂房（D）
    local x = Lk.damX
    local z0, z1 = Lk.z - Lk.damHalf, Lk.z + Lk.damHalf
    local top = Lk.y + 6
    local bot = Lk.foot - 6
    local m = Instance.new("Model")
    m.Name = "Dam"
    local L = z1 - z0
    slab(m, V(14, top - bot, L), CF(x, (top + bot) / 2, (z0 + z1) / 2), CONC, MAT.Concrete)
    for _, sx in ipairs({ -1, 1 }) do
      slab(m, V(0.8, 3, L), CF(x + sx * 6.6, top + 1.5, (z0 + z1) / 2), RGB(170, 168, 162), MAT.Concrete)
    end
    deco(m, V(13, 0.6, L - 4), CF(x, top + 0.3, (z0 + z1) / 2), SNOW, MAT.Snow).CastShadow = false
    for _, zz in ipairs({ Lk.z - 120, Lk.z + 110 }) do   -- 取水塔（湖里）
      local tx = x + 40
      cyl(m, top + 8 - bot, 16, CF(tx, (top + 8 + bot) / 2, zz), RGB(150, 148, 142), MAT.Concrete, true)
      slab(m, V(30, 2, 4), CF(x + 22, top, zz), RGB(150, 148, 142), MAT.Concrete)   -- 栈桥
      World.light(m, V(tx, top + 9, zz), RGB(255, 210, 150), 0.8, 26, 1.2)
    end
    -- 压力水管：坝 → 厂房（两根粗管趴在坡上）
    local P = Map.POINTS[4]
    for _, dz in ipairs({ -12, 12 }) do
      local a = V(x - 8, top - 8, Lk.z + dz)
      local b2 = V(P.x - 160, Lk.foot + 6, P.z + 40 + dz)
      local mid = (a + b2) / 2
      local len = (b2 - a).Magnitude
      slab(m, V(len, 7, 7), CFrame.lookAt(mid, b2) * CFrame.Angles(0, math.pi / 2, 0), RGB(70, 76, 80), MAT.Metal, CYL)
    end
    atomic(m)
    m.Parent = hf
  end

  ---------------------------------------------------------------- 山口检查站（E）：栏杆、岗亭、水泥墩、沙袋

  local ef = folder("Checkpoint", sf)
  do
    local P = Map.POINTS[5]
    local x, z = P.x, P.z
    local y = gy(x, z)
    -- 栏杆横在主路上（红白的杆）
    slab(ef, V(2, 5, 2), CF(x - 22, y + 2.5, z), RGB(80, 84, 88), MAT.Metal)
    for i = 0, 5 do
      deco(ef, V(7, 0.8, 0.8), CF(x - 18.5 + i * 7, y + 4.5, z), (i % 2 == 0) and RGB(200, 40, 36) or RGB(236, 236, 236), MAT.SmoothPlastic)
    end
    -- 岗亭
    slab(ef, V(8, 9, 8), CF(x - 32, y + 4.5, z + 10), RGB(90, 98, 88), MAT.Concrete)
    deco(ef, V(8.3, 2.4, 8.3), CF(x - 32, y + 6, z + 10), RGB(40, 48, 54), MAT.Glass)
    deco(ef, V(9, 0.8, 9), CF(x - 32, y + 9.4, z + 10), SNOW, MAT.Snow).CastShadow = false
    World.light(ef, V(x - 32, y + 11, z + 10), RGB(255, 200, 140), 0.8, 30, 1.3)
    -- 路两边的水泥墩（之字形，车要减速绕）
    for i = 0, 5 do
      local zz = z - 60 + i * 24
      local xx = x + ((i % 2 == 0) and -9 or 9)
      slab(ef, V(12, 3.6, 2.6), CF(xx, gy(xx, zz) + 1.8, zz), RGB(176, 174, 166), MAT.Concrete)
    end
    World.sandbags(ef, V(x + 46, 0, z - 20), 14, -1.2, 1.2, 3)
    World.sandbags(ef, V(x - 52, 0, z - 30), 14, 1.9, 4.4, 3)
  end

  ---------------------------------------------------------------- 反坦克墩（据点外围几道，坦克的掩体）、钢刺猬

  local tf = folder("Obstacles", sf)
  do
    local R = Random.new(9127)
    local lines = {
      { Map.POINTS[3].x - 420, Map.POINTS[3].z + 380, 0.5 },    -- 山村西南
      { Map.POINTS[3].x + 460, Map.POINTS[3].z - 320, -0.6 },   -- 山村东北
      { Map.POINTS[5].x - 300, Map.POINTS[5].z + 420, 0.1 },    -- 山口南边
      { Map.POINTS[1].x + 380, Map.POINTS[1].z - 300, 1.2 },    -- 锯木厂北边
    }
    for _, ln in ipairs(lines) do
      local cx, cz, a = ln[1], ln[2], ln[3]
      for i = -6, 6 do
        local x, z = cx + math.cos(a) * i * 9, cz + math.sin(a) * i * 9
        if not Map.onRoad(x, z, 4) and Map.riverDist(x, z) > 100 and not Map.bldAt(x, z, 6) then
          local y = gy(x, z)
          local p = slab(tf, V(4.6, 4.4, 4.6), CF(x, y + 1.9, z) * CFrame.Angles(0, a + R:NextNumber(-0.2, 0.2), R:NextNumber(-0.08, 0.08)), RGB(170, 168, 160), MAT.Concrete)
          p.CastShadow = true
          deco(tf, V(4.8, 0.6, 4.8), p.CFrame * CF(0, 2.4, 0), SNOW, MAT.Snow).CastShadow = false
        end
      end
      task.wait()
    end
    -- 钢刺猬：三根角钢交叉（散在锯木厂、水电站外围）
    for _, c in ipairs({ { Map.POINTS[1].x - 300, Map.POINTS[1].z - 260 }, { Map.POINTS[4].x - 360, Map.POINTS[4].z + 260 }, { Map.POINTS[2].x + 380, Map.POINTS[2].z + 120 } }) do
      for k = 1, 8 do
        local x, z = c[1] + R:NextNumber(-90, 90), c[2] + R:NextNumber(-60, 60)
        if not Map.onRoad(x, z, 4) and not Map.bldAt(x, z, 6) then
          local y = gy(x, z) + 2.2
          local yaw = R:NextNumber(0, math.pi)
          for q = 0, 2 do
            local r = CFrame.Angles(0, yaw, 0) * ((q == 0) and CFrame.Angles(math.rad(54.7), math.rad(45), 0)
              or (q == 1) and CFrame.Angles(math.rad(54.7), math.rad(-45), 0) or CFrame.Angles(0, 0, math.rad(90)))
            slab(tf, V(0.7, 0.7, 7.5), CF(x, y, z) * r, RGB(58, 52, 48), MAT.CorrodedMetal)
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 山村的路灯（夜里广场一圈亮着）

  local lf = folder("Lamps", sf)
  do
    for k = 0, 9 do
      local a = k / 10 * math.pi * 2
      local x, z = math.cos(a) * 120, math.sin(a) * 100
      if not Map.bldAt(x, z, 3) then
        local y = gy(x, z)
        slab(lf, V(0.8, 14, 0.8), CF(x, y + 7, z), RGB(40, 42, 44), MAT.Metal)
        World.light(lf, V(x, y + 14.4, z), RGB(255, 196, 132), 1, 36, 1.4)
      end
    end
  end

  ---------------------------------------------------------------- 打过仗的痕迹（Map.PROPS，用户 11-27「弹坑、战壕、沙袋、篱笆、电线杆、车辆残骸、木料堆都很少」）：
  --   沙袋墙（战壕胸墙上的射击位）、铁丝网（壕前）、木篱笆（农庄一圈，有的倒了）、电线杆和电线（主路边，据点附近的打歪了）、
  --   木料堆、干草垛、车辆残骸的碰撞盒（残骸的样子：Client/SnowLook.lua 用真车模型烧黑）。弹坑、战壕本身挖在地形里（MapSnow）
  local PR = Map.PROPS
  if PR then
    local wfold = folder("War", sf)
    local SAND, SAND2 = RGB(146, 130, 100), RGB(118, 104, 80)
    local WOOD, WOOD2 = RGB(92, 70, 52), RGB(70, 54, 42)
    local n0 = 0
    -- 沙袋墙：两层，两头按地面高低斜着放；顶上一层雪
    for i, sb in ipairs(PR.sandbag) do
      local x, z, yaw, len = sb[1], sb[2], sb[3], sb[4]
      local ux, uz = -math.sin(yaw) , -math.cos(yaw)
      local ya, yb = gy(x - ux * len / 2, z - uz * len / 2), gy(x + ux * len / 2, z + uz * len / 2)
      local base = CFrame.lookAt(V(x, (ya + yb) / 2, z), V(x + ux, (ya + yb) / 2 + (yb - ya) / len, z + uz))
      slab(wfold, V(3.4, 1.7, len), base * CF(0, 0.6, 0), SAND, MAT.Fabric)
      slab(wfold, V(2.9, 1.5, len - 1.6), base * CF(0, 2.1, 0.4), SAND2, MAT.Fabric)
      deco(wfold, V(2.6, 0.35, len - 2), base * CF(0, 2.95, 0.4), SNOW, MAT.Snow).CastShadow = false
      n0 += 3
      if i % 10 == 0 then task.wait() end
    end
    -- 铁丝网：每 16 格一根木桩，两道铁丝（照地面一段段接）
    local WIRE = RGB(58, 56, 54)
    for i, w in ipairs(PR.wire) do
      local ax, az, bx, bz = w[1], w[2], w[3], w[4]
      local L = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local nb = math.max(1, math.floor(L / 16))
      local prev = nil
      for q = 0, nb do
        local t = q / nb
        local x, z = ax + (bx - ax) * t, az + (bz - az) * t
        local y = gy(x, z)
        local top = V(x, y + 4, z)
        deco(wfold, V(0.45, 4.4, 0.45), CF(x, y + 2, z) * CFrame.Angles((q % 2) * 0.12 - 0.06, 0, 0.08), WOOD2, MAT.Wood)
        if prev then
          for _, hh in ipairs({ 1.3, 3.3 }) do
            local a, b2 = prev + V(0, hh - 4, 0), top + V(0, hh - 4, 0)
            local d = (b2 - a).Magnitude
            deco(wfold, V(0.12, 0.12, d), CFrame.lookAt((a + b2) / 2, b2), WIRE, MAT.Metal).CastShadow = false
          end
        end
        prev = top
        n0 += 3
      end
      if i % 8 == 0 then task.wait() end
    end
    -- 木篱笆：每段 20 格，一根桩、两道横杆；断了的那段横杆一头掉在地上
    for i, f in ipairs(PR.fence) do
      local ax, az, bx, bz, broken = f[1], f[2], f[3], f[4], f[5]
      local ya, yb = gy(ax, az), gy(bx, bz)
      deco(wfold, V(0.7, 5, 0.7), CF(ax, ya + 2.3, az), WOOD, MAT.Wood)
      for _, hh in ipairs({ 1.6, 3.6 }) do
        local a, b2 = V(ax, ya + hh, az), V(bx, yb + hh, bz)
        if broken == 1 then b2 = V(bx, yb + 0.3, bz) end
        local d = (b2 - a).Magnitude
        deco(wfold, V(0.35, 0.5, d), CFrame.lookAt((a + b2) / 2, b2), (hh < 2) and WOOD or WOOD2, MAT.WoodPlanks)
      end
      n0 += 3
      if i % 20 == 0 then task.wait() end
    end
    -- 电线杆：木杆、横担；歪了的不挂线
    local tops = {}
    for i, pl in ipairs(PR.pole) do
      local x, z, yaw, tilt = pl[1], pl[2], pl[3], pl[4]
      local y = gy(x, z)
      local base = CF(x, y - 1.5, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, tilt * 0.5)
      cyl(wfold, 36, 1.1, base * CF(0, 18, 0), RGB(84, 66, 50), MAT.Wood, false)
      deco(wfold, V(9, 0.7, 0.7), base * CF(0, 33.5, 0), RGB(84, 66, 50), MAT.Wood)
      tops[i] = { base * CF(-3.8, 34.2, 0), base * CF(0, 34.2, 0), base * CF(3.8, 34.2, 0) }
      n0 += 2
      if i % 20 == 0 then task.wait() end
    end
    for i, ww in ipairs(PR.wires) do
      local A, B = tops[ww[1]], tops[ww[2]]
      if A and B then
        for k = 1, 3 do
          local a, b2 = A[k].Position, B[k].Position
          local mid = (a + b2) / 2 - V(0, 1.6, 0)   -- 往下垂一点：两段折线
          for _, sgm in ipairs({ { a, mid }, { mid, b2 } }) do
            local d = (sgm[2] - sgm[1]).Magnitude
            deco(wfold, V(0.14, 0.14, d), CFrame.lookAt((sgm[1] + sgm[2]) / 2, sgm[2]), RGB(36, 36, 38), MAT.Metal).CastShadow = false
          end
        end
        n0 += 6
      end
      if i % 20 == 0 then task.wait() end
    end
    -- 木料堆、干草垛
    for i, lg in ipairs(PR.logs) do
      local x, z, yaw, nl = lg[1], lg[2], lg[3], lg[4]
      local y = gy(x, z)
      local base = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
      local L = 22 + (i % 5) * 3
      for row = 0, nl - 1 do
        for q = 0, nl - 1 - row do
          local p = slab(wfold, V(L, 2.8, 2.8), base * CF(0, 1.3 + row * 2.4, (q - (nl - 1 - row) / 2) * 2.9), (q % 2 == 0) and RGB(110, 80, 56) or RGB(96, 70, 50), MAT.Wood, CYL)
          p.CastShadow = row == nl - 1
          n0 += 1
        end
      end
      deco(wfold, V(L - 1, 0.5, (nl - 1) * 2.9 + 1), base * CF(0, 1.3 + (nl - 1) * 2.4 + 1.6, 0), SNOW, MAT.Snow).CastShadow = false
      if i % 6 == 0 then task.wait() end
    end
    for _, hy in ipairs(PR.hay) do
      local x, z = hy[1], hy[2]
      local y = gy(x, z)
      for k = 0, 1 do
        local p = slab(wfold, V(5, 6.5, 6.5), CF(x + k * 7, y + 3, z) * UP * CFrame.Angles(0, 0, 0), RGB(170, 150, 96), MAT.Grass, CYL)
        p.CastShadow = true
        deco(wfold, V(5.4, 0.5, 5.6), CF(x + k * 7, y + 6.4, z), SNOW, MAT.Snow).CastShadow = false
        n0 += 2
      end
    end
    -- 车辆残骸的碰撞盒（看不见：挡车、挡子弹，样子是客户端画的真车模型）
    local okM, IM = pcall(function() return require(RS:WaitForChild("ImportedMeta", 5)) end)
    for _, w in ipairs(PR.wreck) do
      local x, z, yaw, key = w[1], w[2], w[3], w[4]
      local info = okM and IM and IM.m and IM.m[key]
      local W, H, L = 13, 9, 26
      if info then W, H, L = info.w * 0.92, info.h * 0.8, info.len * 0.85 end
      local y = gy(x, z)
      local p = slab(wfold, V(W, H, L), CF(x, y + H / 2 - 0.6, z) * CFrame.Angles(0, yaw, 0), RGB(40, 36, 34), MAT.CorrodedMetal)
      p.Transparency = 1
      p.Name = "Wreck_" .. key
      n0 += 1
    end
    print(string.format("[雪山] 打过仗的痕迹：沙袋墙 %d 段、铁丝网 %d 道、篱笆 %d 段、电线杆 %d 根、木料堆 %d、干草垛 %d、残骸 %d 辆（%d 个零件）；弹坑 %d 个、战壕 %d 条",
      #PR.sandbag, #PR.wire, #PR.fence, #PR.pole, #PR.logs, #PR.hay, #PR.wreck, n0, #(Map.CRATERS or {}), #(Map.TRENCH or {})))
    G.snowWar = function() return { parts = n0, wrecks = #PR.wreck, craters = #(Map.CRATERS or {}), trenches = #(Map.TRENCH or {}) } end   -- 测试用
  end

  ---------------------------------------------------------------- 交战区四周看不见的墙：只挡人、车（飞机是锚住的、子弹炮弹是射线，都过得去）
  --   用户 11-27「河谷可能成狙击走廊」：墙沿着谷边（valleyD = 0.97）围一圈——谷两侧抬起来的山麓在墙外面，车开不上去居高临下打整个谷
  local wf = folder("Bounds", sf)
  do
    local VB = Map.BOUND or 0.97
    local top = (Map.MAXH or 4500) + 200
    local function wallSeg(a, b2)
      local mid = (a + b2) / 2
      local L = (b2 - a).Magnitude
      if L < 1 then return end
      for y0 = -60, top, 1200 do
        local p = part(wf, V(4, 1200, L + 4), CFrame.lookAt(V(mid.X, y0 + 600, mid.Z), V(b2.X, y0 + 600, b2.Z)), RGB(255, 255, 255), MAT.SmoothPlastic, nil, true)
        p.Transparency = 1
        p.CanQuery, p.CanTouch, p.CastShadow = false, false, false
        p.Name = "Bound"
      end
    end
    -- 边界线：按 z 一段段找谷边（左右两边各二分查 valleyD = VB）
    local function edgeX(z, sgn)
      local lo, hi = 0, 9000
      local cx = Map.valleyX(z)
      for _ = 1, 22 do
        local mid = (lo + hi) / 2
        if Map.valleyD(cx + sgn * mid, z) < VB then lo = mid else hi = mid end
      end
      return cx + sgn * lo
    end
    local zEnd = 0
    do   -- 谷两头（z 方向）的边：中线上二分
      local lo, hi = 0, 14000
      for _ = 1, 22 do
        local mid = (lo + hi) / 2
        if Map.valleyD(Map.valleyX(mid), mid) < VB then lo = mid else hi = mid end
      end
      zEnd = lo
    end
    local L, Rr = {}, {}
    local n = math.floor(zEnd * 2 / 320)
    for i = 0, n do
      local z = -zEnd + i * (zEnd * 2 / n)
      table.insert(L, V(edgeX(z, -1), 0, z))
      table.insert(Rr, V(edgeX(z, 1), 0, z))
    end
    for i = 1, #L - 1 do
      wallSeg(L[i], L[i + 1])
      wallSeg(Rr[i], Rr[i + 1])
    end
    wallSeg(L[1], Rr[1])
    wallSeg(L[#L], Rr[#Rr])
  end

  local n = 0
  for _, d in ipairs(sf:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
  print(string.format("[雪山] 房子 %d 座（导入的模型 %d 座）、桥 %d 座；零件 %d 块", #Map.BLD, nModel, #Map.BRIDGES, n - nParts0))
end

return SnowBuild
