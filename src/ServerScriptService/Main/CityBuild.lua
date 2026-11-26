-- 全面大战场：钢城（MapCity.lua）开服时盖的城——街道、楼、广场、公园、火车站、电视塔、钢厂、郊区小楼、农舍、铁路、路灯
--   用户 11-26：「做一个两边带机场的城市地图吧」。地形整块是平的（World 一次 FillBlock 铺好），这里只摆零件：
--   · 路：每段一块柏油零件（路面比平地高 0.1 格，互相压着的高低错开），大街中间一道白线；田间土路是土色的
--   · 楼：照 Map.BLD 一座一座盖——楼身一块实心的（挡车、挡子弹），每层一圈玻璃窗带（比楼身大一圈的薄盒子：四面墙的窗户一块零件），
--     顶上女儿墙一圈、空调外机、楼梯间；老城的楼外墙几道竖的壁柱、底层门脸；高楼是玻璃幕墙；
--     楼带 Bld / BldBase / BldSize 属性：Battle.lua 的房子炸塌照样认（炸多了塌成一摊废墟），CityIdx 记是 Map.BLD 的第几座（塌了视线就不再算它）
--   · 零件尽量少：一座楼十来块（四五百座楼一共五千多块）；装饰都不挡人、不挡射线、不投影
local RS = game:GetService("ReplicatedStorage")
local Map = require(RS:WaitForChild("Map"))

local CityBuild = {}

local V, CF, RGB, MAT = Vector3.new, CFrame.new, Color3.fromRGB, Enum.Material
local CYL = Enum.PartType.Cylinder
local UP = CFrame.Angles(0, 0, math.pi / 2)   -- 圆柱的轴在 X：立起来

-- 楼的样式（Map.BLD 的 st）：墙、勒脚 / 女儿墙、窗玻璃、墙的材质
local STY = {
  [1] = { wall = RGB(170, 170, 164), trim = RGB(138, 138, 134), glass = RGB(52, 64, 76), mat = MAT.Concrete },     -- 灰板楼
  [2] = { wall = RGB(206, 190, 158), trim = RGB(172, 156, 128), glass = RGB(50, 60, 70), mat = MAT.Concrete },     -- 米黄抹灰
  [3] = { wall = RGB(146, 84, 64), trim = RGB(196, 186, 170), glass = RGB(42, 52, 60), mat = MAT.Brick },          -- 红砖
  [4] = { wall = RGB(198, 190, 172), trim = RGB(160, 150, 130), glass = RGB(46, 56, 64), mat = MAT.Limestone },    -- 浅色石头（老城）
  [5] = { wall = RGB(84, 104, 118), trim = RGB(160, 168, 174), glass = RGB(78, 116, 136), mat = MAT.Glass, curtain = true },   -- 玻璃写字楼
  [6] = { wall = RGB(106, 76, 62), trim = RGB(128, 122, 114), glass = RGB(38, 44, 48), mat = MAT.Brick },          -- 深色砖（厂房）
  [7] = { wall = RGB(226, 224, 216), trim = RGB(188, 188, 184), glass = RGB(50, 68, 82), mat = MAT.SmoothPlastic },   -- 白色新楼
  [8] = { wall = RGB(198, 162, 98), trim = RGB(222, 212, 192), glass = RGB(46, 54, 60), mat = MAT.Concrete },     -- 赭黄（老城）
}
local AWN = { RGB(150, 40, 36), RGB(36, 80, 120), RGB(40, 104, 64), RGB(176, 128, 40), RGB(90, 60, 110) }   -- 底层门脸的遮阳篷

function CityBuild.build(World, root, G)
  local part = World.part
  local PL = Map.PLAIN
  local FH = Map.FH
  local function folder(name, parent)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
  end
  local function slab(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape, true) end
  local function deco(m, size, cf, col, mat, shape) return part(m, size, cf, col, mat, shape) end
  local function atomic(m) pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end) end
  local cf0 = folder("City", root)
  local nParts0 = 0
  local function count(f) local n = 0 for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end return n end

  ---------------------------------------------------------------- 路

  local rf = folder("Roads", cf0)
  local ASPH, DIRT, LINE, YEL = RGB(50, 52, 56), RGB(112, 96, 72), RGB(214, 214, 206), RGB(210, 170, 50)
  for _, s in ipairs(Map.SEGS) do
    local ax, az, bx, bz, w, k, yo = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
    local dx, dz = bx - ax, bz - az
    local L = math.sqrt(dx * dx + dz * dz)
    if L > 1 and w > 0 then
      local dir = V(dx / L, 0, dz / L)
      local dirt = (k == "lane" or k == "lane2")
      local n = math.ceil(L / 2000)
      for q = 0, n - 1 do
        local l = L / n
        local c = V(ax, 0, az) + dir * (l * (q + 0.5))
        local cf = CFrame.lookAt(V(c.X, PL + yo - 0.5, c.Z), V(c.X, PL + yo - 0.5, c.Z) + dir)
        local p = slab(rf, V(w, 1, l + ((q < n - 1) and 0.05 or 0)), cf, dirt and DIRT or ASPH, dirt and MAT.Ground or MAT.Asphalt)
        p.CastShadow = false
        -- 中线：大街、公路一道（双向四车道的中央大道、和平大街是黄的），窄街白的；土路不画
        if not dirt and w >= 30 then
          local lc = (w >= 60) and YEL or LINE
          local ln = deco(rf, V((w >= 60) and 1.2 or 0.7, 0.06, l * 0.995), cf * CF(0, 0.53, 0), lc, MAT.SmoothPlastic)
          ln.CastShadow = false
          if w >= 60 then   -- 中央大道：车道分界的虚线换成两道细白线（零件少）
            for _, sx in ipairs({ -w / 4, w / 4 }) do
              local ll = deco(rf, V(0.5, 0.06, l * 0.995), cf * CF(sx, 0.53, 0), LINE, MAT.SmoothPlastic)
              ll.CastShadow = false
            end
          end
        end
      end
    end
  end
  -- 中央广场：一整块石板（铺在两条大街交叉的地方），中间纪念碑、一圈喷水池的池沿
  do
    local P = Map.PLAZA
    local pz = folder("Plaza", cf0)
    local s = slab(pz, V(2 * P, 1, 2 * P), CF(0, PL + 0.12 - 0.5, 0), RGB(150, 142, 130), MAT.Cobblestone)
    s.CastShadow = false
    -- 纪念碑：两级台基、方尖碑、碑顶一点金色
    slab(pz, V(46, 3, 46), CF(0, PL + 1.5, 0), RGB(170, 164, 152), MAT.Limestone)
    slab(pz, V(30, 4, 30), CF(0, PL + 5, 0), RGB(180, 174, 162), MAT.Limestone)
    slab(pz, V(11, 72, 11), CF(0, PL + 43, 0), RGB(196, 190, 176), MAT.Limestone)
    local tip = part(pz, V(11, 8, 11), CF(0, PL + 83, 0), RGB(200, 170, 80), MAT.Metal)
    tip.Shape = Enum.PartType.Block
    -- 喷水池（坦克能当掩护的一圈矮墙）：池沿按 16 段围一圈，里面一块蓝灰的水面
    local R0 = 74
    for q = 0, 15 do
      local a = q / 16 * math.pi * 2
      local p = V(math.cos(a) * R0, 0, math.sin(a) * R0)
      slab(pz, V(30, 4, 4), CFrame.lookAt(V(p.X, PL + 2, p.Z), V(p.X, PL + 2, p.Z) + V(-math.sin(a), 0, math.cos(a))), RGB(168, 162, 150), MAT.Limestone)
    end
    local water = deco(pz, V(1, 2 * R0 - 6, 2 * R0 - 6), CF(0, PL + 1.2, 0) * UP, RGB(60, 96, 110), MAT.Glass, CYL)
    water.Reflectance = 0.3
    water.Transparency = 0.15
  end

  ---------------------------------------------------------------- 楼

  local bf = folder("Buildings", cf0)
  local function rnd(b, k) return ((b.sd * 9301 + k * 49297) % 233280) / 233280 end
  -- 一般的楼（block / slab / low / tower / hall / church）
  local function block(b)
    local S = STY[b.st] or STY[1]
    local m = Instance.new("Model")
    m.Name = "Bld_city_" .. b.id
    local base = CF(b.x, PL - 0.2, b.z)
    local H = b.h - 2
    slab(m, V(b.w, H, b.d), base * CF(0, H / 2, 0), S.wall, S.mat)
    -- 每层一圈窗带（四面墙一块零件）：玻璃幕墙的楼窗带高、层间只剩一道窄的
    local fl = b.fl
    local glassK = S.curtain and 0.78 or ((b.k == "slab") and 0.42 or 0.5)
    for k = 0, fl - 1 do
      local y0 = k * FH
      local wh, yc
      if k == 0 then wh, yc = FH * 0.62, FH * 0.44 else wh, yc = FH * glassK, y0 + FH * 0.56 end
      local g = deco(m, V(b.w + 0.3, wh, b.d + 0.3), base * CF(0, yc, 0), (k == 0 and not S.curtain) and RGB(34, 40, 46) or S.glass, MAT.Glass)
      g.Reflectance = S.curtain and 0.25 or 0.12
      g.CastShadow = false
    end
    -- 女儿墙（顶上一圈，比楼身宽一点）、勒脚
    slab(m, V(b.w + 0.8, 2, b.d + 0.8), base * CF(0, H + 1, 0), S.trim, S.mat)
    deco(m, V(b.w + 0.5, 1.4, b.d + 0.5), base * CF(0, 0.7, 0), S.trim, MAT.Concrete).CastShadow = false
    -- 老城的楼：长的那两面墙几道竖的壁柱（凹凸），底层一条遮阳篷
    if b.st == 4 or b.st == 8 or b.st == 3 then
      local long = b.w >= b.d
      local L = long and b.w or b.d
      local n = math.clamp(math.floor(L / 34), 2, 5)
      for q = 1, n do
        local u = -L / 2 + q * L / (n + 1)
        for _, sd in ipairs({ -1, 1 }) do
          local off = (long and b.d or b.w) / 2 + 0.45
          local cf = long and (base * CF(u, H / 2 + FH * 0.5, sd * off)) or (base * CF(sd * off, H / 2 + FH * 0.5, u))
          local sz = long and V(2.2, H - FH, 0.9) or V(0.9, H - FH, 2.2)
          deco(m, sz, cf, S.trim, S.mat).CastShadow = false
        end
      end
      if b.k ~= "hall" and b.k ~= "church" then
        local awn = AWN[1 + math.floor(rnd(b, 3) * #AWN)]
        local sd = (rnd(b, 4) < 0.5) and -1 or 1
        local cf = long and (base * CF(0, FH * 0.86, sd * (b.d / 2 + 2.2)) * CFrame.Angles(sd * 0.32, 0, 0)) or (base * CF(sd * (b.w / 2 + 2.2), FH * 0.86, 0) * CFrame.Angles(0, 0, -sd * 0.32))
        local sz = long and V(b.w * 0.86, 0.4, 5) or V(5, 0.4, b.d * 0.86)
        deco(m, sz, cf, awn, MAT.Fabric)
      end
    end
    -- 屋顶：楼梯间、空调外机、水箱（高楼顶上一圈设备层、一根天线）
    if b.k ~= "church" then
      slab(m, V(math.min(16, b.w * 0.3), 6, math.min(14, b.d * 0.3)), base * CF(b.w * (rnd(b, 5) - 0.5) * 0.4, H + 3, b.d * (rnd(b, 6) - 0.5) * 0.4), S.trim, MAT.Concrete)
      deco(m, V(5, 3, 4), base * CF(-b.w * 0.25, H + 1.5, b.d * 0.2), RGB(190, 192, 190), MAT.Metal)
      if b.w * b.d > 3000 then deco(m, V(5, 3, 4), base * CF(b.w * 0.22, H + 1.5, -b.d * 0.24), RGB(186, 188, 186), MAT.Metal) end
    end
    if b.k == "tower" then
      slab(m, V(b.w * 0.8, 8, b.d * 0.8), base * CF(0, H + 6, 0), S.trim, MAT.Metal)
      deco(m, V(1, 40, 1), base * CF(b.w * 0.2, H + 30, 0), RGB(150, 150, 150), MAT.Metal)
      local l = World.light(m, (base * CF(b.w * 0.2, H + 50.5, 0)).Position, RGB(255, 40, 40), 1.2, 18, 1.4)   -- 航空障碍灯（一闪一闪）
      l:SetAttribute("Anim", "blink")
      l:SetAttribute("Spd", 0.7)
    end
    -- 市政厅、教堂：顶上一座钟楼（市政厅方的，教堂的高、带尖顶）
    if b.tower then
      local tw = (b.k == "church") and 26 or 34
      local th = (b.k == "church") and 70 or 46
      local tc = base * CF((b.k == "church") and (b.w / 2 - tw / 2 - 4) or 0, 0, 0)
      slab(m, V(tw, H + th, tw), tc * CF(0, (H + th) / 2, 0), S.wall, S.mat)
      slab(m, V(tw + 2, 2, tw + 2), tc * CF(0, H + th + 1, 0), S.trim, S.mat)
      for q = 0, 3 do   -- 四面钟（白底、黑框）
        local f = tc * CFrame.Angles(0, q * math.pi / 2, 0) * CF(0, H + th - 12, -tw / 2 - 0.3)
        deco(m, V(0.3, 12, 12), f * CFrame.Angles(0, math.pi / 2, 0), RGB(236, 232, 220), MAT.SmoothPlastic, CYL)
      end
      if b.k == "church" then
        local sp = part(m, V(tw * 0.8, 40, tw * 0.8), tc * CF(0, H + th + 22, 0), RGB(80, 92, 90), MAT.Slate, nil, true)
        sp.Shape = Enum.PartType.Block
        deco(m, V(2, 12, 2), tc * CF(0, H + th + 48, 0), RGB(200, 170, 80), MAT.Metal)
      else
        slab(m, V(tw * 0.7, 12, tw * 0.7), tc * CF(0, H + th + 8, 0), RGB(90, 100, 96), MAT.Slate)
      end
    end
    -- 正门：朝最近的那条街（中线离哪边近就开在哪边）
    do
      local gx = ((b.x + Map.C0) % Map.GRID) / Map.GRID   -- 在街坊里的位置（0～1）
      local gz = ((b.z + Map.C0) % Map.GRID) / Map.GRID
      local ex = math.min(gx, 1 - gx)
      local ez = math.min(gz, 1 - gz)
      local cfD
      if ex < ez then
        local sd = (gx < 0.5) and -1 or 1
        cfD = base * CF(sd * (b.w / 2 + 0.25), 3.6, 0) * CFrame.Angles(0, sd * math.pi / 2, 0)
      else
        local sd = (gz < 0.5) and -1 or 1
        cfD = base * CF(0, 3.6, sd * (b.d / 2 + 0.25)) * CFrame.Angles(0, (sd > 0) and 0 or math.pi, 0)
      end
      deco(m, V(6, 7, 0.4), cfD, RGB(54, 50, 46), MAT.Wood)
    end
    m:SetAttribute("Bld", "city" .. b.st)
    m:SetAttribute("BldBase", base)
    m:SetAttribute("BldSize", V(b.w, b.h, b.d))
    m:SetAttribute("CityIdx", b.id)
    atomic(m)
    m.Parent = bf
    return m
  end

  -- 锯齿顶厂房、谷仓：砖墙、一排朝北的采光天窗（锯齿）/ 两坡的红顶
  local function shed(b)
    local S = STY[b.st] or STY[6]
    local m = Instance.new("Model")
    m.Name = "Bld_city_" .. b.id
    local base = CF(b.x, PL - 0.2, b.z)
    local eave = (b.k == "barn") and b.h * 0.55 or b.h * 0.66
    slab(m, V(b.w, eave, b.d), base * CF(0, eave / 2, 0), S.wall, S.mat)
    local rh = b.h - eave
    if b.k == "barn" then
      local W = Instance.new("WedgePart")
      for _, sd in ipairs({ -1, 1 }) do
        local w = W:Clone()
        w.Anchored, w.Size = true, V(b.w, rh, b.d / 2)
        w.CFrame = base * CF(0, eave + rh / 2, sd * b.d / 4) * CFrame.Angles(0, (sd > 0) and math.pi or 0, 0)
        w.Color, w.Material = RGB(140, 46, 38), MAT.CorrodedMetal
        w.Parent = m
      end
      W:Destroy()
    else
      local n = math.max(2, math.floor(b.d / 40))
      for q = 0, n - 1 do
        local z = -b.d / 2 + (q + 0.5) * b.d / n
        local w = Instance.new("WedgePart")
        w.Anchored, w.Size = true, V(b.w, rh, b.d / n)
        w.CFrame = base * CF(0, eave + rh / 2, z) * CFrame.Angles(0, math.pi, 0)
        w.Color, w.Material = RGB(96, 92, 88), MAT.CorrodedMetal
        w.Parent = m
        local g = deco(m, V(b.w - 2, rh * 0.8, 0.4), base * CF(0, eave + rh * 0.45, z - b.d / n / 2 - 0.2), RGB(60, 74, 84), MAT.Glass)
        g.Reflectance = 0.15
      end
    end
    -- 高窗一圈、两扇大门
    deco(m, V(b.w + 0.3, 4, b.d + 0.3), base * CF(0, eave * 0.72, 0), RGB(44, 50, 54), MAT.Glass).CastShadow = false
    for _, sx in ipairs({ -b.w / 4, b.w / 4 }) do
      deco(m, V(math.min(22, b.w * 0.25), math.min(16, eave * 0.7), 0.5), base * CF(sx, math.min(16, eave * 0.7) / 2, -b.d / 2 - 0.2), RGB(120, 124, 120), MAT.DiamondPlate)
    end
    m:SetAttribute("Bld", "city6")
    m:SetAttribute("BldBase", base)
    m:SetAttribute("BldSize", V(b.w, b.h, b.d))
    m:SetAttribute("CityIdx", b.id)
    atomic(m)
    m.Parent = bf
  end

  -- 废墟：几截高矮不一的断墙、一摊碎砖（坦克能躲在后面）；本来就塌了，不再算房子
  local function ruin(b)
    local S = STY[b.st] or STY[2]
    local m = Instance.new("Model")
    m.Name = "Ruin_city_" .. b.id
    local base = CF(b.x, PL - 0.2, b.z)
    local burnt = S.wall:Lerp(RGB(40, 36, 32), 0.45)
    for q = 0, 3 do
      local h = 6 + rnd(b, q) * 16
      local long = (q % 2 == 0)
      local off = (long and b.d or b.w) / 2
      local sd = (q < 2) and -1 or 1
      local len = (long and b.w or b.d) * (0.45 + rnd(b, q + 10) * 0.5)
      local cf = long and (base * CF((rnd(b, q + 20) - 0.5) * b.w * 0.3, h / 2, sd * off)) or (base * CF(sd * off, h / 2, (rnd(b, q + 20) - 0.5) * b.d * 0.3))
      slab(m, long and V(len, h, 2) or V(2, h, len), cf, burnt, S.mat)
    end
    for q = 0, 2 do   -- 碎砖堆（楔形）
      local w = Instance.new("WedgePart")
      w.Anchored, w.Size = true, V(b.w * 0.3, 4 + rnd(b, q + 30) * 3, b.d * 0.3)
      w.CFrame = base * CF((rnd(b, q + 40) - 0.5) * b.w * 0.5, 2.5, (rnd(b, q + 50) - 0.5) * b.d * 0.5) * CFrame.Angles(0, rnd(b, q + 60) * 6.28, 0)
      w.Color, w.Material = burnt:Lerp(RGB(120, 110, 100), 0.3), MAT.Slate
      w.Parent = m
    end
    atomic(m)
    m.Parent = bf
  end

  -- 郊区小楼、农舍：导入了 models/bld/buildings.glb 就摆原模型（World.building：Sketchfab 上 CC-BY 的写实民房），没导入用几块零件拼一座坡顶小楼
  local function house(b)
    local key = b.model
    if key and World.importedBld and World.importedBld(key) then
      local _, m = World.building(bf, key, b.x, b.z, b.rot or 0)
      if m then m:SetAttribute("CityIdx", b.id) end
      return
    end
    local S = STY[b.st] or STY[2]
    local m = Instance.new("Model")
    m.Name = "Bld_city_" .. b.id
    local base = CF(b.x, PL - 0.2, b.z) * CFrame.Angles(0, b.rot or 0, 0)
    local w, d = b.w, b.d
    if math.abs(math.sin(b.rot or 0)) > 0.5 then w, d = b.d, b.w end   -- 转过 90° 的：外接矩形是转过的，楼本身按没转的长宽
    local eave = b.h * 0.58
    slab(m, V(w, eave, d), base * CF(0, eave / 2, 0), S.wall, S.mat)
    local rh = b.h - eave
    for _, sd in ipairs({ -1, 1 }) do
      local wp = Instance.new("WedgePart")
      wp.Anchored, wp.Size = true, V(w + 2, rh, d / 2 + 1)
      wp.CFrame = base * CF(0, eave + rh / 2, sd * (d / 4 + 0.5)) * CFrame.Angles(0, (sd > 0) and math.pi or 0, 0)
      wp.Color, wp.Material = RGB(120, 62, 48), MAT.Slate
      wp.Parent = m
    end
    deco(m, V(w + 0.3, 3.4, d + 0.3), base * CF(0, eave * 0.55, 0), RGB(46, 54, 62), MAT.Glass).CastShadow = false
    deco(m, V(4, 7, 0.4), base * CF(0, 3.5, -d / 2 - 0.2), RGB(90, 62, 44), MAT.Wood)
    m:SetAttribute("Bld", "city2")
    m:SetAttribute("BldBase", base)
    m:SetAttribute("BldSize", V(w, b.h, d))
    m:SetAttribute("CityIdx", b.id)
    atomic(m)
    m.Parent = bf
  end

  -- 火车站：一座长的拱顶大厅（站房）
  local function station(b)
    local S = STY[4]
    local m = Instance.new("Model")
    m.Name = "Bld_city_" .. b.id
    local base = CF(b.x, PL - 0.2, b.z)
    local wall = 30
    slab(m, V(b.w, wall, b.d), base * CF(0, wall / 2, 0), S.wall, S.mat)
    local roof = slab(m, V(b.d, b.w * 0.92, b.w * 0.92), base * CF(0, wall - b.w * 0.1, 0) * CFrame.Angles(0, math.pi / 2, 0), RGB(88, 100, 104), MAT.CorrodedMetal, CYL)
    roof.CastShadow = true
    deco(m, V(b.w + 0.3, 10, b.d + 0.3), base * CF(0, 16, 0), RGB(54, 70, 82), MAT.Glass).Reflectance = 0.2
    -- 正面（朝西、对着站台那一边）的钟和站名牌
    deco(m, V(0.4, 9, 9), base * CF(-b.w / 2 - 0.3, wall + 8, 0), RGB(236, 232, 220), MAT.SmoothPlastic, CYL)
    local sg = deco(m, V(0.5, 5, 60), base * CF(-b.w / 2 - 0.3, wall - 4, 0), RGB(30, 60, 110), MAT.SmoothPlastic)
    World.sign(sg, "钢城站", 0, 40, 5, RGB(240, 240, 240), 900)
    m:SetAttribute("Bld", "city4")
    m:SetAttribute("BldBase", base)
    m:SetAttribute("BldSize", V(b.w, b.h, b.d))
    m:SetAttribute("CityIdx", b.id)
    atomic(m)
    m.Parent = bf
  end

  -- 电视塔：混凝土塔身（圆柱）、半腰的观光塔楼（两层圆盘）、顶上的天线和一串红灯（据点 E 的地标，炸不塌）
  local function tvtower(b)
    local m = Instance.new("Model")
    m.Name = "TvTower"
    local base = CF(b.x, PL - 0.2, b.z)
    local H = 330
    slab(m, V(60, 8, 60), base * CF(0, 4, 0), RGB(150, 148, 142), MAT.Concrete)
    slab(m, V(H, 30, 30), base * CF(0, H / 2, 0) * UP, RGB(206, 204, 198), MAT.Concrete, CYL)
    slab(m, V(14, 78, 78), base * CF(0, 262, 0) * UP, RGB(190, 188, 182), MAT.Concrete, CYL)
    local g = deco(m, V(10, 80, 80), base * CF(0, 274, 0) * UP, RGB(60, 90, 110), MAT.Glass, CYL)
    g.Reflectance = 0.25
    slab(m, V(8, 64, 64), base * CF(0, 284, 0) * UP, RGB(196, 60, 50), MAT.Metal, CYL)
    slab(m, V(90, 6, 6), base * CF(0, H + 45, 0) * UP, RGB(170, 170, 168), MAT.Metal, CYL)
    for _, y in ipairs({ 120, 230, 300, H + 88 }) do
      local l = World.light(m, (base * CF(0, y, 16)).Position, RGB(255, 40, 40), 1.4, 20, 1.6)
      l:SetAttribute("Anim", "blink")
      l:SetAttribute("Spd", 0.6)
    end
    atomic(m)
    m.Parent = bf
  end

  -- 货车厢：一节节的棚车 / 敞车 / 罐车（挡车、挡子弹的掩护，不算房子）
  local WAGON = { RGB(120, 60, 44), RGB(70, 78, 70), RGB(60, 66, 80), RGB(116, 100, 70) }
  local function wagon(b)
    local m = Instance.new("Model")
    m.Name = "Wagon"
    local base = CF(b.x, PL - 0.2, b.z)
    local col = WAGON[1 + math.floor(rnd(b, 1) * #WAGON)]
    local kind = rnd(b, 2)
    slab(m, V(10, 2.6, b.d), base * CF(0, 2.6, 0), RGB(36, 36, 38), MAT.Metal)   -- 底架
    if kind < 0.6 then
      slab(m, V(b.w, 10, b.d - 1), base * CF(0, 9, 0), col, MAT.CorrodedMetal)      -- 棚车
    elseif kind < 0.8 then
      slab(m, V(b.w, 5, b.d - 1), base * CF(0, 6.5, 0), col, MAT.CorrodedMetal)     -- 敞车
    else
      slab(m, V(b.d - 4, 10, 10), base * CF(0, 9, 0) * CFrame.Angles(0, math.pi / 2, 0), RGB(40, 42, 44), MAT.Metal, CYL)   -- 罐车
    end
    for _, z in ipairs({ -b.d * 0.32, b.d * 0.32 }) do deco(m, V(10.4, 2.6, 6), base * CF(0, 1.3, z), RGB(28, 28, 30), MAT.Metal) end   -- 转向架
    atomic(m)
    m.Parent = bf
  end

  local nB = 0
  for _, b in ipairs(Map.BLD) do
    local k = b.k
    local ok, err = pcall(function()
      if k == "shed" or k == "barn" then shed(b)
      elseif k == "ruin" then ruin(b)
      elseif k == "house" then house(b)
      elseif k == "station" then station(b)
      elseif k == "tvtower" then tvtower(b)
      elseif k == "wagon" then wagon(b)
      else block(b) end
    end)
    if not ok then warn("[钢城] 第 " .. b.id .. " 座（" .. tostring(k) .. "）出错：" .. tostring(err)) end
    nB += 1
    if nB % 40 == 0 then task.wait() end
  end

  ---------------------------------------------------------------- 铁路、站台

  local railF = folder("Rail", cf0)
  do
    local RL = Map.RAIL
    local p = RL.path
    for i = 1, #p - 1 do
      local a, b = V(p[i][1], 0, p[i][2]), V(p[i + 1][1], 0, p[i + 1][2])
      local d = b - a
      local L = d.Magnitude
      local dir = d.Unit
      local right = V(-dir.Z, 0, dir.X)
      local n = math.ceil(L / 2000)
      for q = 0, n - 1 do
        local l = L / n
        local c = a + dir * (l * (q + 0.5))
        for _, o in ipairs(RL.tracks) do
          local cc = c + right * o
          local cf = CFrame.lookAt(V(cc.X, PL, cc.Z), V(cc.X, PL, cc.Z) + dir)
          local bal = deco(railF, V(10, 0.6, l + 0.1), cf * CF(0, 0.2, 0), RGB(88, 84, 80), MAT.Slate)   -- 道砟
          bal.CastShadow = false
          for _, rx in ipairs({ -2.4, 2.4 }) do
            local r = deco(railF, V(0.5, 0.6, l + 0.1), cf * CF(rx, 0.8, 0), RGB(96, 90, 84), MAT.Metal)
            r.CastShadow = false
          end
        end
      end
    end
    -- 站台：中间一座岛式站台（两股道之间）、东边一座靠站房，上面一溜雨棚
    local x = RL.x
    for _, pl in ipairs({ { x, 52 }, { x + 106, 40 } }) do
      slab(railF, V(pl[2], 3, 620), CF(pl[1], PL + 1.5, 0), RGB(164, 160, 152), MAT.Concrete)
      deco(railF, V(pl[2] * 0.8, 0.8, 600), CF(pl[1], PL + 15, 0), RGB(80, 92, 96), MAT.Metal)
      for z = -280, 280, 70 do deco(railF, V(1, 12, 1), CF(pl[1], PL + 9, z), RGB(70, 74, 78), MAT.Metal) end
    end
  end

  ---------------------------------------------------------------- 公园（据点 B）：绕着据点一圈的小路、南北一条小路、凉亭、长椅

  local pk = folder("Park", cf0)
  do
    local B = nil
    for _, p in ipairs(Map.POINTS) do if p.id == "B" then B = p end end
    local GRAV = RGB(176, 160, 128)
    local R0 = 300
    for q = 0, 31 do
      local a0, a1 = q / 32 * math.pi * 2, (q + 1) / 32 * math.pi * 2
      local pa = V(B.x + math.cos(a0) * R0, 0, B.z + math.sin(a0) * R0)
      local pb = V(B.x + math.cos(a1) * R0, 0, B.z + math.sin(a1) * R0)
      local c = (pa + pb) / 2
      local L = (pb - pa).Magnitude
      if math.abs(c.Z) > 40 then   -- 和平大街那一段不铺
        local p = deco(pk, V(14, 0.3, L + 1), CFrame.lookAt(V(c.X, PL + 0.1, c.Z), V(c.X, PL + 0.1, c.Z) + (pb - pa).Unit), GRAV, MAT.Ground)
        p.CastShadow = false
      end
    end
    for _, z0 in ipairs({ { -490, -40 }, { 40, 490 } }) do
      local L = z0[2] - z0[1]
      deco(pk, V(14, 0.3, L), CF(B.x, PL + 0.1, (z0[1] + z0[2]) / 2), GRAV, MAT.Ground).CastShadow = false
    end
    -- 凉亭：据点北边（八根柱子、一圈顶）
    local cx, cz = B.x + 150, B.z - 150
    for q = 0, 7 do
      local a = q / 8 * math.pi * 2
      slab(pk, V(1.6, 14, 1.6), CF(cx + math.cos(a) * 16, PL + 7, cz + math.sin(a) * 16), RGB(220, 216, 206), MAT.Marble)
    end
    slab(pk, V(3, 40, 40), CF(cx, PL + 15, cz) * UP, RGB(120, 70, 56), MAT.Slate, CYL)
    -- 长椅
    for q = 0, 11 do
      local a = q / 12 * math.pi * 2 + 0.13
      local p = V(B.x + math.cos(a) * (R0 + 12), PL + 1.2, B.z + math.sin(a) * (R0 + 12))
      deco(pk, V(8, 1, 2.6), CFrame.lookAt(p, p + V(-math.sin(a), 0, math.cos(a))), RGB(110, 76, 50), MAT.Wood)
    end
  end

  ---------------------------------------------------------------- 钢厂（A）、电视塔（E）的配套：烟囱、储罐、管廊、卫星天线

  local ex = folder("Works", cf0)
  do
    local A, E = nil, nil
    for _, p in ipairs(Map.POINTS) do if p.id == "A" then A = p elseif p.id == "E" then E = p end end
    for _, c in ipairs({ { A.x - 150, A.z - 300 }, { A.x + 150, A.z + 310 } }) do
      slab(ex, V(140, 14, 14), CF(c[1], PL + 70, c[2]) * UP, RGB(150, 120, 100), MAT.Brick, CYL)   -- 烟囱
      deco(ex, V(4, 15, 15), CF(c[1], PL + 136, c[2]) * UP, RGB(60, 56, 52), MAT.Metal, CYL)
    end
    for q = 0, 2 do   -- 储罐
      slab(ex, V(34, 36, 36), CF(A.x + 330, PL + 17, A.z - 80 + q * 60) * UP, RGB(186, 186, 180), MAT.Metal, CYL)
    end
    slab(ex, V(300, 4, 6), CF(A.x, PL + 36, A.z - 210), RGB(110, 114, 112), MAT.Metal)   -- 管廊
    for q = -1, 1 do slab(ex, V(2, 34, 2), CF(A.x + q * 120, PL + 17, A.z - 210), RGB(90, 94, 92), MAT.Metal) end
    -- 电视台院里几面卫星天线
    for q = 0, 3 do
      local p = V(E.x - 330 + q * 40, PL, E.z - 200)
      slab(ex, V(1.6, 8, 1.6), CF(p.X, PL + 4, p.Z), RGB(150, 150, 150), MAT.Metal)
      deco(ex, V(0.8, 16, 16), CF(p.X, PL + 12, p.Z) * CFrame.Angles(0, 0, math.rad(55)), RGB(226, 226, 222), MAT.SmoothPlastic, CYL)
    end
  end

  ---------------------------------------------------------------- 路灯（中央大道、和平大街两边每 96 格一盏；每四盏一盏亮的点光源）

  local lf = folder("Lamps", cf0)
  do
    local POST = RGB(60, 62, 66)
    local k = 0
    local function lamp(x, z, ax, az)
      k += 1
      slab(lf, V(0.8, 22, 0.8), CF(x, PL + 11, z), POST, MAT.Metal)
      deco(lf, V(0.5, 0.5, 6), CFrame.lookAt(V(x, PL + 22, z), V(x, PL + 22, z) + V(ax, 0, az)) * CF(0, 0, -3), POST, MAT.Metal)
      local pos = V(x + ax * 6, PL + 21.4, z + az * 6)
      if k % 4 == 0 then
        World.light(lf, pos, RGB(255, 214, 160), 0.8, 60, 1.6, { face = Enum.NormalId.Bottom, angle = 100 }, 2)
      else
        local p = deco(lf, V(1.6, 0.6, 1.6), CF(pos), RGB(255, 226, 180), MAT.Neon)
        p.CastShadow = false
      end
    end
    local C0 = Map.C0
    for u = -C0 + 48, C0 - 48, 96 do
      local mid = math.abs(u) < Map.PLAZA + 20
      if not mid then
        for _, sd in ipairs({ -1, 1 }) do
          local off = 32 + 4
          if not Map.bldAt(sd * off, u, 2) and not Map.onRoad(sd * off, u, 0) then lamp(sd * off, u, -sd, 0) end
          if not Map.bldAt(u, sd * off, 2) and not Map.onRoad(u, sd * off, 0) and Map.railNear(u, sd * off) > 90 then lamp(u, sd * off, 0, -sd) end
        end
      end
    end
  end

  ---------------------------------------------------------------- 停车场、工地、球场的东西：烧毁的车、水泥墩、塔吊

  local cv = folder("Cover", cf0)
  do
    local R = Random.new(5150)
    local CARS = { RGB(140, 30, 30), RGB(40, 60, 100), RGB(200, 200, 196), RGB(30, 30, 32), RGB(90, 96, 100) }
    for i = 0, 11 do
      for j = 0, 11 do
        local t = Map.blockType(i, j)
        local x0, x1, z0, z1 = Map.blockInterior(i, j)
        if t == "parking" then
          for row = 0, 2 do
            for q = 0, 9 do
              if R:NextNumber() < 0.6 then
                local x = x0 + 30 + q * (x1 - x0 - 60) / 9
                local z = z0 + 60 + row * (z1 - z0 - 120) / 2
                local burnt = R:NextNumber() < 0.35
                local col = burnt and RGB(44, 40, 36) or CARS[R:NextInteger(1, #CARS)]
                local c = CF(x, PL, z) * CFrame.Angles(0, (R:NextNumber() - 0.5) * 0.3, 0)
                slab(cv, V(7, 3.4, 15), c * CF(0, 2.6, 0), col, burnt and MAT.CorrodedMetal or MAT.Metal)
                deco(cv, V(6.4, 2.6, 8), c * CF(0, 5.4, 0.5), burnt and RGB(30, 28, 26) or RGB(40, 50, 60), burnt and MAT.CorrodedMetal or MAT.Glass)
              end
            end
          end
        elseif t == "works" then   -- 工地：塔吊、一座盖了一半的楼架子、几堆材料
          local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
          slab(cv, V(6, 160, 6), CF(cx - 80, PL + 80, cz), RGB(220, 180, 40), MAT.Metal)
          deco(cv, V(220, 4, 4), CF(cx - 20, PL + 158, cz), RGB(220, 180, 40), MAT.Metal)
          for _, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
            slab(cv, V(3, 60, 3), CF(cx + 60 + q[1] * 50, PL + 30, cz + q[2] * 40), RGB(150, 150, 146), MAT.Concrete)
          end
          for f = 1, 3 do slab(cv, V(106, 2, 86), CF(cx + 60, PL + f * 18, cz), RGB(160, 158, 152), MAT.Concrete) end
          for _ = 1, 4 do
            slab(cv, V(R:NextNumber(14, 24), R:NextNumber(4, 8), R:NextNumber(10, 18)), CF(x0 + R:NextNumber(30, x1 - x0 - 30), PL + 3, z0 + R:NextNumber(30, z1 - z0 - 30)) * CFrame.Angles(0, R:NextNumber(0, 3), 0),
              RGB(130, 120, 106), MAT.WoodPlanks)
          end
        elseif t == "sports" then   -- 球场：一块绿的场地、两个球门
          local s = deco(cv, V(x1 - x0 - 60, 0.3, z1 - z0 - 80), CF((x0 + x1) / 2, PL + 0.15, (z0 + z1) / 2), RGB(70, 120, 60), MAT.Grass)
          s.CastShadow = false
          for _, sd in ipairs({ -1, 1 }) do
            deco(cv, V(24, 8, 1), CF((x0 + x1) / 2, PL + 4, (z0 + z1) / 2 + sd * ((z1 - z0) / 2 - 44)), RGB(236, 236, 236), MAT.Metal)
          end
        end
      end
    end
    -- 据点附近的掩体：水泥墩、沙袋（不堵死街，摆在人行道、广场边上）
    for _, p in ipairs(Map.POINTS) do
      for q = 0, 5 do
        local a = q / 6 * math.pi * 2 + 0.4
        local r = Map.POINT_R + 30
        local x, z = p.x + math.cos(a) * r, p.z + math.sin(a) * r
        if not Map.bldAt(x, z, 4) and Map.railNear(x, z) > 30 then
          local c = CFrame.lookAt(V(x, PL, z), V(p.x, PL, p.z))
          slab(cv, V(8.4, 1.1, 2.3), c * CF(0, 0.55, 0), RGB(184, 180, 168), MAT.Concrete)
          slab(cv, V(8.4, 1.6, 0.95), c * CF(0, 1.9, 0), RGB(184, 180, 168), MAT.Concrete)
        end
      end
    end
  end

  local n = count(cf0)
  G.cityParts = n
  print(string.format("[钢城] 盖好了：%d 座楼 / 设施、%d 段路、%d 棵树（树在客户端画），一共 %d 个零件", #Map.BLD, #Map.SEGS, #(Map.TREES or {}), n))
  local _ = nParts0
  return cf0
end

return CityBuild
