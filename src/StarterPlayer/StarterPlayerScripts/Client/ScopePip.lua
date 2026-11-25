-- Roblox全面大战场——瞄准镜画中画（客户端）：镜内单独放大（用户 11-21：「改成镜内单独放大」，像三角洲行动、塔科夫那样）
--   Roblox 一帧只画一次主画面，地形、粒子、光影都只在主画面里。所以镜外照普通开镜（约 1.25 倍）不放大，
--   镜片那个圆里用 ViewportFrame 另画一份放大的战场（镜头就在眼睛这儿、朝准星看，视角 = 镜片的角大小 ÷ 倍率）：
--   · 地形：按 Map.height / Map.material（开服生成地形用的同一套）车成网格（EditableMesh），按材质分块、用 Roblox 自带的草 / 沙 / 岩石……
--     材质（有纹理，UV 按世界坐标铺），颜色同地形、顶点色带一点明暗斑驳（11-21：原来一整块顶点色的光滑塑料，太假）：
--     脚下 4 格一点（约 380 格见方，人走开 100 格重新生成）、20 格一点（1800 格见方）、64 格一点（全岛和小岛，生成一次）；
--     细的盖在粗的上面（粗的往下沉一点、每张边上一圈再往下沉，接缝藏在下面）。后台慢慢算，每帧最多 1.5 毫秒
--   · 海面（半透明，浅滩看得见沙）+ 底下一层深海色、天空（按看的仰角取色）、雾（镜头前几张半透明的大片，越远叠得越多，按大气浓度）、
--     灯光（太阳 / 月亮的方向、昼夜、夜视仪变绿、照明弹）
--   · 地图上的东西（workspace 的 Map、Scenery、Ruins）：按 128 格的格子分好，镜子看过去那一条锥里的格子才克隆进去，克隆过的留着下回直接用
--     （最多留 6000 块，超了扔掉最久没看的格子）；新加、删掉的跟着加减
--   · 会动的（实体的样子 EntView：步兵、车、飞机、船；别的玩家；ClientFx 的火光、曳光）：在锥里的克隆一份，每帧照原来的零件摆
--   · 烟幕（粒子画不进 ViewportFrame）：补几团灰球（G.pipSmoke），透过镜子也看不穿烟
--   EditableMesh 用不了（游戏设置里没开 Mesh / Image API）时不做画中画：Scope.lua 退回整屏放大
--   接口：G.pipReady() 能用了；G.pipAttach(父) 把镜片那个 ViewportFrame 放进界面；G.pipStep(镜片圆心 x, y, 半径, 倍率, 淡入) 每帧（Scope 调），
--     返回画中画的焦距（像素，分划按它摆）；G.pipHide()；G.pipSmoke(位置, 半径, 秒)；G.PIP_ADS 镜外的开镜放大
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local ScopePip = {}

-- 地形材质的颜色（同 World.lua 的 TERRAIN_COLORS：开服时 SetMaterialColor 设的那套）；沙漠、沙海这类图自己带一张（Map.COLORS），先查它
--   用户 11-24「开镜有bug……屏幕有一块色斑」：原来只有岛上那几种材质，沙漠的盐碱地、砂岩，沙海的石灰岩台地、盐壳查不到就画成草绿色——
--   开镜看过去镜里一块块绿斑，镜外是沙色
local TC = {
  Grass = { 98, 148, 64 }, LeafyGrass = { 98, 148, 64 }, Sand = { 226, 208, 160 }, Rock = { 124, 118, 110 }, Slate = { 98, 98, 104 },
  Ground = { 122, 98, 70 }, Mud = { 54, 47, 40 }, Concrete = { 150, 148, 140 }, Asphalt = { 70, 72, 76 },
  Sandstone = { 190, 142, 98 }, Salt = { 228, 222, 206 }, Limestone = { 198, 182, 150 }, Basalt = { 60, 62, 64 },
}
-- 跟着人走的两级：step 每格几格、n 每边几格、drop 整张往下沉、edge 最外一圈再沉、move 人走开多远重新生成
local LEVELS = {
  { step = 4, n = 96, drop = 0, edge = 1.6, move = 100 },
  { step = 20, n = 90, drop = 1, edge = 4, move = 420 },
}
-- 没有海的图（沙漠、沙海）多一级：64 格一点、6400 格见方。沙漠的「全岛」那级只铺有起伏的块，戈壁平原上 900 格以外原来没有地形网格；
--   有了这级，动的东西画到的范围（DYN_RANGE）里车都踩在真的地面上，更远才是垫底的平地。不算进「能用了」（opt）
local LEVEL3 = { step = 64, n = 100, drop = 2, edge = 5, move = 1200, opt = true }
local function levels(sea)
  if sea then return LEVELS end
  return { LEVELS[1], LEVELS[2], LEVEL3 }
end
local FAR = { step = 64, drop = 2.5, edge = 6 }   -- 全岛（生成一次）
local CELL = 128            -- 地图上的东西按 128 格的格子分
local RANGE = 5200          -- 静态的东西画多远
local DYN_RANGE = 3400      -- 会动的东西画多远
local MAX_CLONES = 6000     -- 克隆的静态零件最多留多少
local BUDGET = 0.0015       -- 后台生成每帧最多用多少秒
local HAZE = { 260, 650, 1200, 1950, 3000, 4500 }   -- 雾的几张大片离镜头多远

-- 克隆过来不要的东西：脚本、声音、粒子、灯、界面、关节（每块零件各自照原来的摆，连着关节会被拖着走）、小人的 Humanoid
local STRIP = {
  Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true, Beam = true, Trail = true, Fire = true, Smoke = true,
  Sparkles = true, PointLight = true, SpotLight = true, SurfaceLight = true, BillboardGui = true, SurfaceGui = true, Highlight = true,
  ProximityPrompt = true, ClickDetector = true, Humanoid = true, AnimationController = true, Animator = true, Explosion = true,
}

function ScopePip.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local AS = game:GetService("AssetService")
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local V, CF, RGB, C3 = Vector3.new, CFrame.new, Color3.fromRGB, Color3.new
  local now = os.clock
  local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
  local noise = math.noise
  G.PIP_ADS = 1.25

  -- st：ok 能不能用（nil 还不知道）、lv 两级地形（{ mp, cx, cz }）、far 全岛那几张、busy 正在后台生成
  local st = { ok = nil, lv = {}, far = false, farM = {}, gen = 0, busy = false, started = false, warned = false, nClones = 0, cellT = 0, syncT = 0, dynT = 0, mkBudget = 0, chk = nil }

  ---------------------------------------------------------------- 画中画的窗口（圆的：UICorner 裁成圆）

  local vpf = Instance.new("ViewportFrame")
  vpf.Name = "ScopePip"
  vpf.AnchorPoint = Vector2.new(0.5, 0.5)
  vpf.BackgroundColor3 = RGB(120, 140, 160)
  vpf.BorderSizePixel = 0
  vpf.ZIndex = 1
  vpf.Visible = false
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = vpf
  end
  local wm = Instance.new("WorldModel")
  wm.Parent = vpf
  local pcam = Instance.new("Camera")
  pcam.Parent = vpf
  vpf.CurrentCamera = pcam
  function G.pipAttach(parent) vpf.Parent = parent end

  local function props(p)
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
  end
  local function plate(size, color, alpha, mat)
    local p = Instance.new("Part")
    p.Size, p.Color, p.Transparency = size, color, alpha or 0
    p.Material = mat or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    props(p)
    p.Parent = wm
    return p
  end

  -- 这张图有没有海（Map.info[id].sea；沙漠、沙海没有）
  local function seaMap()
    local inf = Map.info and Map.info[Map.id]
    return not inf or inf.sea ~= false
  end
  -- 这种材质在这张图上的颜色：图自己的表（Map.COLORS，Color3）→ 岛上那套（TC）→ 没有的：有海的图当草地、没海的当沙地
  local function matColor(m)
    local mc = Map.COLORS and Map.COLORS[m.Name]
    if typeof(mc) == "Color3" then return mc end
    local c = TC[m.Name] or (seaMap() and TC.Grass or TC.Sand)
    return RGB(c[1], c[2], c[3])
  end

  -- 海面（半透明：浅滩透出底下的沙）、深海色的底（没有地形网格的地方）：5 × 5 块 2048 见方，跟着镜头挪
  --   没有海的图（沙漠、沙海）：这 25 块改成平地——每块按里面 3 × 3 个点的地面高度取中位数、材质取最多的那种，放低 3 格垫在地形网格下面。
  --   沙漠的地形网格只铺有起伏的地方（detailBoxes），戈壁平原是开服 FillBlock 铺的平地：原来镜里远处的平原透出底下这层蓝绿的海
  local water, deep = {}, {}
  for i = 1, 25 do
    water[i] = plate(V(2048, 1, 2048), RGB(26, 82, 98), 0.32)   -- 同 Terrain.WaterColor（30, 112, 136）透过深水看暗一些
    deep[i] = plate(V(2048, 1, 2048), RGB(10, 34, 44), 0)
  end
  local WATER_C = RGB(26, 82, 98)
  local waterAt, waterMap = nil, nil
  local function groundPlate(p, x, z)
    local ys, cnt = {}, {}
    for a = -1, 1 do
      for b = -1, 1 do
        local sx, sz = x + a * 640, z + b * 640
        local y = (Map.height(sx, sz))
        table.insert(ys, y)
        local ok, m = pcall(Map.material, sx, sz, y, 0)
        if ok and typeof(m) == "EnumItem" then cnt[m] = (cnt[m] or 0) + 1 end
      end
    end
    table.sort(ys)
    local best, bn = Enum.Material.Sand, -1
    for m, n in pairs(cnt) do if n > bn then best, bn = m, n end end
    p.CFrame = CF(x, ys[5] - 3.5, z)   -- 板厚 1 格：上表面比地面低 3 格（远处那级网格往下沉 2.5，别跟它打架）
    p.Material = best
    p.Color = matColor(best)
    p.Transparency = 0
  end
  local function placeWater(pos)
    local gx, gz = floor(pos.X / 2048 + 0.5) * 2048, floor(pos.Z / 2048 + 0.5) * 2048
    if waterAt and waterAt.X == gx and waterAt.Z == gz and waterMap == Map.id then return end
    waterAt, waterMap = V(gx, 0, gz), Map.id
    local sea = seaMap()
    local i = 0
    for a = -2, 2 do
      for b = -2, 2 do
        i += 1
        local x, z = gx + a * 2048, gz + b * 2048
        if sea then
          water[i].CFrame = CF(x, -0.5, z)
          water[i].Material, water[i].Color, water[i].Transparency = Enum.Material.SmoothPlastic, WATER_C, 0.32
          deep[i].CFrame = CF(x, -10.5, z)
          deep[i].Transparency = 0
        else
          groundPlate(water[i], x, z)
          deep[i].Transparency = 1
        end
      end
    end
  end
  -- 雾：镜头前几张半透明的大片（不受光的 Neon，颜色按大气）
  local haze = {}
  for i = 1, #HAZE do haze[i] = plate(V(10, 10, 0.05), RGB(150, 160, 175), 1, Enum.Material.Neon) end

  ---------------------------------------------------------------- 地形网格

  local function warnOnce(msg)
    if st.warned then return end
    st.warned = true
    warn("[全面大战场] 瞄准镜画中画用不了（" .. tostring(msg) .. "），开镜退回整屏放大")
  end

  -- 一张地形：中心 (cx, cz)、每格 step、nx × nz 格；drop 整张往下沉、edge 最外一圈再沉。
  --   按地形材质分成几块 MeshPart（草、深色草、沙、土、岩石……各一块），每块用 Roblox 自带的那种材质（有纹理、有法线的起伏，像真的地面，
  --   用户 11-21：镜里的画面太假——原来是一整块顶点色的光滑塑料），颜色同开服时设的地形颜色；顶点色只带一点明暗斑驳；
  --   UV 按世界坐标每 TILE 格一个循环（纹理大小和地形上的差不多）。返回一个 Model；EditableMesh 用不了时出错，外面接住
  local TILE = 12
  local function terrainMesh(cx, cz, step, nx, nz, drop, edge)
    local W = nx + 1
    local N = W * (nz + 1)
    local hs, mats, nrm, shade = table.create(N), table.create(N), table.create(N), table.create(N)
    local x0, z0 = cx - nx * step / 2, cz - nz * step / 2
    local t0 = now()
    local function tick()
      if now() - t0 > BUDGET then
        task.wait()
        t0 = now()
      end
    end
    for k = 0, nz do
      for i = 0, nx do hs[k * W + i + 1] = (Map.height(x0 + i * step, z0 + k * step)) end
      tick()
    end
    for k = 0, nz do   -- 每个点：材质（同开服生成地形）、法线、斑驳
      for i = 0, nx do
        local id = k * W + i + 1
        local x, z = x0 + i * step, z0 + k * step
        local y = hs[id]
        local ia, ib = max(i - 1, 0), min(i + 1, nx)
        local ka, kb = max(k - 1, 0), min(k + 1, nz)
        local dx = (hs[k * W + ib + 1] - hs[k * W + ia + 1]) / ((ib - ia) * step)
        local dz = (hs[kb * W + i + 1] - hs[ka * W + i + 1]) / ((kb - ka) * step)
        mats[id] = Map.material(x, z, y, sqrt(dx * dx + dz * dz))
        nrm[id] = V(-dx, 1, -dz).Unit
        local v = 0.88 + 0.09 * noise(x / 37, z / 37, 2.7) + 0.04 * noise(x / 9, z / 9, 8.1)   -- 大片的明暗斑驳（纹理管细节）
        if y < -0.5 then v *= 0.72 end   -- 水下
        shade[id] = min(1, v)
      end
      tick()
    end
    local groups = {}   -- [材质] = { em, vid / nid / uid / cid（点号 → 这块里的编号）, 包围盒 }
    local function vert(g, id)
      local v = g.vid[id]
      if v then return v end
      local i, k = (id - 1) % W, math.floor((id - 1) / W)
      local x, z = x0 + i * step, z0 + k * step
      local yy = hs[id] - drop - (((i == 0 or k == 0 or i == nx or k == nz) and edge) or 0)
      local px, pz = x - cx, z - cz
      g.lx, g.ly, g.lz = min(g.lx, px), min(g.ly, yy), min(g.lz, pz)
      g.hx, g.hy, g.hz = max(g.hx, px), max(g.hy, yy), max(g.hz, pz)
      local em = g.em
      v = em:AddVertex(V(px, yy, pz))
      g.vid[id] = v
      g.nid[id] = em:AddNormal(nrm[id])
      g.uid[id] = em:AddUV(Vector2.new(x / TILE, z / TILE))
      local sh = shade[id]
      g.cid[id] = em:AddColor(C3(sh, sh, sh), 1)
      return v
    end
    local function tri(a, b, c)
      local ma, mb, mc = mats[a], mats[b], mats[c]
      local m = (ma == mb or ma == mc) and ma or ((mb == mc) and mb or ma)   -- 三个点里多数的材质
      local g = groups[m]
      if not g then
        g = { em = AS:CreateEditableMesh(), vid = {}, nid = {}, uid = {}, cid = {}, lx = 1e9, ly = 1e9, lz = 1e9, hx = -1e9, hy = -1e9, hz = -1e9 }
        groups[m] = g
      end
      local va, vb, vc = vert(g, a), vert(g, b), vert(g, c)
      local em = g.em
      local f = em:AddTriangle(va, vb, vc)
      em:SetFaceNormals(f, { g.nid[a], g.nid[b], g.nid[c] })
      em:SetFaceUVs(f, { g.uid[a], g.uid[b], g.uid[c] })
      em:SetFaceColors(f, { g.cid[a], g.cid[b], g.cid[c] })
    end
    for k = 0, nz - 1 do
      for i = 0, nx - 1 do
        local a, b, c, d = k * W + i + 1, (k + 1) * W + i + 1, k * W + i + 2, (k + 1) * W + i + 2
        -- 朝上（从上往下看逆时针）：(i, k) → (i, k+1) → (i+1, k)、(i+1, k) → (i, k+1) → (i+1, k+1)
        tri(a, b, c)
        tri(c, b, d)
      end
      tick()
    end
    local model = Instance.new("Model")
    model.Name = "PipTerrain"
    for m, g in pairs(groups) do
      local mp = AS:CreateMeshPartAsync(Content.fromObject(g.em))
      mp.Name = "PipTerrain_" .. m.Name
      mp.Material = m   -- Roblox 自带材质：草、沙、岩石……的纹理按网格的 UV 铺
      mp.Color = matColor(m)   -- 这张图的地形颜色（沙漠、沙海的盐壳、砂岩……原来查不到画成草绿）
      props(mp)
      mp.CFrame = CF(cx + (g.lx + g.hx) / 2, (g.ly + g.hy) / 2, cz + (g.lz + g.hz) / 2)   -- 生成的网格原点在包围盒中心
      mp.Parent = model
    end
    return model
  end

  -- 后台生成：一次一件（脚下那级优先，再中间那级，最后全岛）
  local function job(f)
    st.busy = true
    task.spawn(function()
      local ok, err = pcall(f)
      if not ok then
        st.ok = false
        warnOnce(err)
      end
      st.busy = false
    end)
  end
  local function here()
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or cam.CFrame.Position
  end
  -- 后台生成的网格按「第几代」认：换了地图（G.onMap）代数加一，还在算的旧图网格算完直接扔掉
  local function maintain()
    if st.busy or st.ok == false then return end
    local p = here()
    local gen = st.gen
    for i, L in ipairs(levels(seaMap())) do
      local cur = st.lv[i]
      if not cur or (V(p.X - cur.cx, 0, p.Z - cur.cz)).Magnitude > L.move then
        local snap = L.step * 4
        local cx, cz = floor(p.X / snap + 0.5) * snap, floor(p.Z / snap + 0.5) * snap
        job(function()
          local mp = terrainMesh(cx, cz, L.step, L.n, L.n, L.drop, L.edge)
          st.ok = true
          if gen ~= st.gen then mp:Destroy() return end
          mp.Parent = wm
          if st.lv[i] and st.lv[i].mp then st.lv[i].mp:Destroy() end
          st.lv[i] = { mp = mp, cx = cx, cz = cz }
        end)
        return
      end
    end
    if not st.far then
      st.far = true
      job(function()
        for _, b in ipairs(Map.landBoxes()) do
          local nx, nz = math.ceil((b[3] - b[1]) / FAR.step), math.ceil((b[4] - b[2]) / FAR.step)
          local parts = math.ceil(nx * nz * 2 / 18000)   -- 一张网格不超过 1.8 万个三角形
          local w = math.ceil(nx / parts)
          for s = 0, parts - 1 do
            local n = min(w, nx - s * w)
            if n > 0 then
              local cx = b[1] + (s * w + n / 2) * FAR.step
              local mp = terrainMesh(cx, (b[2] + b[4]) / 2, FAR.step, n, nz, FAR.drop, FAR.edge)
              if gen ~= st.gen then mp:Destroy() return end
              mp.Parent = wm
              table.insert(st.farM, mp)
            end
          end
        end
      end)
    end
  end
  -- 换地图（进服以后才在选图界面定的那张）：岛上算好的地形网格全扔掉，按新图重新生成；垫底的那层（海面 / 平地）也重摆
  local function resetTerrain()
    st.gen += 1
    for _, cur in pairs(st.lv) do if cur.mp then cur.mp:Destroy() end end
    table.clear(st.lv)
    for _, mp in ipairs(st.farM) do mp:Destroy() end
    table.clear(st.farM)
    st.far = false
    waterAt = nil
  end
  if G.onMap then G.onMap(resetTerrain) end
  -- 能用了：EditableMesh 好用，脚下两级都生成好了、离现在的位置不远（没海的图第三级不等）
  function G.pipReady()
    if st.ok ~= true or G.pipForceOff then return false end   -- pipForceOff：测试 / 调试时关掉画中画（退回整屏放大）
    local p = here()
    for i, L in ipairs(levels(seaMap())) do
      local cur = st.lv[i]
      if not L.opt and (not cur or (V(p.X - cur.cx, 0, p.Z - cur.cz)).Magnitude > L.move * 1.6) then return false end
    end
    return true
  end

  ---------------------------------------------------------------- 地图上的东西：按格子分，锥里的格子才克隆

  local cells, cellOf = {}, setmetatable({}, { __mode = "k" })
  local function ckey(x, z) return floor(x / CELL) * 65536 + floor(z / CELL) end
  local function clean(c)
    for _, d in ipairs(c:GetDescendants()) do
      if STRIP[d.ClassName] or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint") or d:IsA("GuiBase3d") then d:Destroy() end
    end
  end
  local function cloneStatic(c, p)
    local ok, q = pcall(function() return p:Clone() end)
    if not ok or not q then return end
    for _, d in ipairs(q:GetDescendants()) do   -- 子零件各自另有一份（每块零件都登记了）
      if d:IsA("BasePart") then d:Destroy() end
    end
    clean(q)
    props(q)
    q.Parent = c.fold
    c.clones[p] = q
    st.nClones += 1
  end
  local function addStatic(p)
    if not p:IsA("BasePart") or cellOf[p] or p.Transparency >= 0.99 then return end   -- 看不见的命中盒、碰撞板不要
    local pos = p.CFrame.Position   -- 同 p.Position；Lune 测试台读地图文件里的零件读不出 Position（同 TankHud、Night）
    local k = ckey(pos.X, pos.Z)
    local c = cells[k]
    if not c then
      c = { parts = {}, n = 0, x = (floor(pos.X / CELL) + 0.5) * CELL, z = (floor(pos.Z / CELL) + 0.5) * CELL, ylo = pos.Y, yhi = pos.Y, ext = 0, seen = 0 }
      cells[k] = c
    end
    c.parts[p] = true
    c.n += 1
    c.ylo, c.yhi = min(c.ylo, pos.Y), max(c.yhi, pos.Y)
    c.ext = max(c.ext, p.Size.Magnitude / 2)
    cellOf[p] = k
    if c.fold then cloneStatic(c, p) end   -- 这格已经克隆过：新来的也克隆一份
  end
  local function removeStatic(p)
    local k = cellOf[p]
    if not k then return end
    cellOf[p] = nil
    local c = cells[k]
    if not c then return end
    c.parts[p] = nil
    c.n -= 1
    local q = c.clones and c.clones[p]
    if q then
      q:Destroy()
      c.clones[p] = nil
      st.nClones -= 1
    end
  end
  local SRC = { "Map", "Scenery", "Ruins" }
  local watched = {}
  local function watchStatic()
    for _, name in ipairs(SRC) do
      local f = workspace:FindFirstChild(name)
      if f and not watched[f] then
        watched[f] = true
        f.DescendantAdded:Connect(addStatic)
        f.DescendantRemoving:Connect(removeStatic)
        task.spawn(function()
          local t0 = now()
          for i, d in ipairs(f:GetDescendants()) do
            addStatic(d)
            if i % 400 == 0 and now() - t0 > BUDGET then
              task.wait()
              t0 = now()
            end
          end
        end)
      end
    end
  end

  ---------------------------------------------------------------- 锥：镜头位置 E、朝向 D、半角 A（弧度）

  local E, D, A = V(), V(0, 0, -1), 0.05
  local function inCone(p, r, range)
    local v = p - E
    local dist = v.Magnitude
    if dist <= r then return true end
    if dist - r > range then return false end
    local c = v:Dot(D) / dist
    if c >= 1 then return true end
    return math.acos(math.max(-1, c)) <= A + math.asin(min(1, r / dist))
  end

  -- 静态格子：锥里的克隆进来（每帧最多克隆 150 块，转得快时一格一格补上）、锥外的收起来；克隆太多扔掉最久没看的
  local shown = {}
  local function updateCells(t)
    local budget = 150
    local want = {}
    local Aw = A
    A = A * 1.6 + 0.02   -- 隔 0.1 秒才挑一次：锥放宽一点，转镜头时边上不缺
    for k, c in pairs(cells) do
      if c.n > 0 and inCone(V(c.x, (c.ylo + c.yhi) / 2, c.z), CELL * 0.71 + c.ext + (c.yhi - c.ylo) / 2, RANGE) then want[k] = c end
    end
    A = Aw
    for k, c in pairs(shown) do
      if not want[k] then
        if c.fold then c.fold.Parent = nil end
        shown[k] = nil
      end
    end
    for k, c in pairs(want) do
      c.seen = t
      if not c.fold then
        c.fold = Instance.new("Folder")
        c.clones = {}
        c.pending = true
      end
      if c.pending and budget > 0 then
        local done = true
        for p in pairs(c.parts) do
          if not c.clones[p] then
            if budget <= 0 then
              done = false
              break
            end
            cloneStatic(c, p)
            budget -= 1
          end
        end
        c.pending = not done
      end
      if c.fold.Parent ~= wm then c.fold.Parent = wm end
      shown[k] = c
    end
    if st.nClones > MAX_CLONES then   -- 扔掉最久没看的格子
      local list = {}
      for k, c in pairs(cells) do if c.fold and not shown[k] then table.insert(list, { k = k, c = c }) end end
      table.sort(list, function(a, b) return a.c.seen < b.c.seen end)
      for _, e in ipairs(list) do
        if st.nClones <= MAX_CLONES * 0.8 then break end
        for _ in pairs(e.c.clones) do st.nClones -= 1 end
        e.c.fold:Destroy()
        e.c.fold, e.c.clones, e.c.pending = nil, nil, nil
      end
    end
  end
  -- 静态的也可能动（门、旗、被打坏的工事）：看着的格子每半秒照原来的摆一遍
  local function syncCells()
    for _, c in pairs(shown) do
      if c.clones then
        for p, q in pairs(c.clones) do
          if p.Parent then
            q.CFrame = p.CFrame
            if q.Transparency ~= p.Transparency then q.Transparency = p.Transparency end
            if q.Color ~= p.Color then q.Color = p.Color end
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- 会动的：在锥里的克隆一份，每帧照原来的零件摆

  local dyn = {}                                       -- [原来的] = { m 克隆, sp / dp 两边一一对应的零件, cf, n 零件数, r 半径, root }
  local rootOf = setmetatable({}, { __mode = "k" })   -- [原来的] = 它的一块零件（量位置用）
  local function partsOf(src)
    local list = {}
    if src:IsA("BasePart") then list[1] = src end
    for _, d in ipairs(src:GetDescendants()) do if d:IsA("BasePart") then list[#list + 1] = d end end
    return list
  end
  local function makeDyn(src)
    local was = src.Archivable
    src.Archivable = true   -- 玩家的小人默认不让克隆
    local ok, c = pcall(function() return src:Clone() end)
    src.Archivable = was
    if not ok or not c then return nil end
    local sp, cp = partsOf(src), partsOf(c)
    if #cp ~= #sp then   -- 有不让克隆的零件：按名字对（同名的按先后）
      local pool = {}
      for _, q in ipairs(cp) do
        pool[q.Name] = pool[q.Name] or {}
        table.insert(pool[q.Name], q)
      end
      local s2, d2 = {}, {}
      for _, p in ipairs(sp) do
        local l = pool[p.Name]
        if l and #l > 0 then
          table.insert(s2, p)
          table.insert(d2, table.remove(l, 1))
        end
      end
      sp, cp = s2, d2
    end
    local m = c
    if c:IsA("BasePart") then   -- 单块零件（火光、曳光）：包一层 Model
      m = Instance.new("Model")
      c.Parent = m
    end
    clean(m)
    for _, q in ipairs(cp) do
      props(q)
      for _, d in ipairs(q:GetChildren()) do if d:IsA("BasePart") and not table.find(cp, d) then d:Destroy() end end
    end
    local r = 4
    for _, p in ipairs(sp) do r = max(r, p.Size.Magnitude / 2) end
    if #sp > 1 then
      local okE, ext = pcall(function() return src:IsA("Model") and src:GetExtentsSize() or nil end)
      if okE and ext then r = max(r, ext.Magnitude / 2) end
    end
    return { m = m, sp = sp, dp = cp, cf = table.create(#sp), n = #partsOf(src), r = r, tT = 0 }
  end
  local function dropDyn(src)
    local d = dyn[src]
    if d then
      d.m:Destroy()
      dyn[src] = nil
    end
  end
  local function rootPart(src)
    local r = rootOf[src]
    if r and r.Parent then return r end
    if src:IsA("BasePart") then r = src
    elseif src:IsA("Model") then r = src.PrimaryPart or src:FindFirstChildWhichIsA("BasePart", true) end
    rootOf[src] = r
    return r
  end
  local function considerDyn(src, t, live)
    if src == me.Character then return end
    local root = rootPart(src)
    if not root then return end
    local d = dyn[src]
    live[src] = true
    if inCone(root.Position, d and d.r or 40, DYN_RANGE) then
      if not d then
        -- 每帧克隆的零件有上限（一下子转到一艘几百块零件的舰上不卡那一帧）：这帧的额度用完了下一帧再克隆
        if st.mkBudget <= 0 then return end
        d = makeDyn(src)
        if not d then return end
        st.mkBudget -= #d.sp
        dyn[src] = d
      end
      local sp, cf = d.sp, d.cf
      for i = 1, #sp do cf[i] = sp[i].CFrame end
      wm:BulkMoveTo(d.dp, cf, Enum.BulkMoveMode.FireCFrameChanged)
      if t - d.tT > 0.25 then   -- 透明度（被打掉、隐身、远了收起来）四分之一秒对一次
        d.tT = t
        for i = 1, #sp do
          local p = sp[i]
          local a = p.Parent and max(p.Transparency, p.LocalTransparencyModifier) or 1
          if d.dp[i].Transparency ~= a then d.dp[i].Transparency = a end
        end
      end
      if d.m.Parent ~= wm then d.m.Parent = wm end
    elseif d and d.m.Parent then
      d.m.Parent = nil
    end
  end
  local function updateDyn(t)
    local live = {}
    st.mkBudget = 160
    local ev = G.viewFolder
    if ev then for _, m in ipairs(ev:GetChildren()) do considerDyn(m, t, live) end end
    for _, pl in ipairs(Players:GetPlayers()) do
      if pl ~= me and pl.Character then considerDyn(pl.Character, t, live) end
    end
    for _, name in ipairs({ "ClientFx", "GunKitFx" }) do
      local f = workspace:FindFirstChild(name)
      if f then for _, m in ipairs(f:GetChildren()) do if m:IsA("BasePart") or m:IsA("Model") then considerDyn(m, t, live) end end end
    end
    if t - st.dynT > 1 then   -- 一秒查一次：没了的扔掉
      st.dynT = t
      for src in pairs(dyn) do
        if not live[src] or not src.Parent then dropDyn(src) end
      end
    end
    -- 零件多了少了（车被打坏、换了武器）的重建：每帧轮着查一个（大模型数一遍零件也要点时间）
    local src, d = next(dyn, st.chk)
    if src == nil then src, d = next(dyn) end
    st.chk = src
    if src and d and #partsOf(src) ~= d.n then
      dropDyn(src)
      st.chk = nil
    end
  end

  ---------------------------------------------------------------- 烟幕：几团灰球（粒子画不进画中画，不补的话开镜能看穿烟）

  local smokes = {}
  function G.pipSmoke(p, r, life)
    if typeof(p) ~= "Vector3" then return end
    r = r or 20
    local e = { t0 = now(), life = life or 30, balls = {} }
    -- 六团，每团里外三层（越外越大越淡）：边缘是软的，看着像一团烟，不像几个灰球；中间那层不透明，开镜照样看不穿
    for i = 1, 6 do
      local a = i / 6 * math.pi * 2
      local c = p + V(math.cos(a) * r * 0.55, r * (0.2 + 0.4 * math.random()), math.sin(a) * r * 0.55)
      local g = 196 + math.random(0, 18)
      for layer = 1, 3 do
        local sz = r * (0.75 + 0.35 * layer) * (0.9 + 0.3 * math.random())
        local b = plate(V(sz, sz, sz), RGB(g, g + 2, g), 1)
        b.Shape = Enum.PartType.Ball
        b.CFrame = CF(c + V(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * r * 0.15)
        b:SetAttribute("A", ({ 0.12, 0.45, 0.72 })[layer])   -- 这一层满的时候的透明度
        table.insert(e.balls, b)
      end
    end
    table.insert(smokes, e)
  end
  local function updateSmoke(t)
    for i = #smokes, 1, -1 do
      local e = smokes[i]
      local age = t - e.t0
      if age > e.life then
        for _, b in ipairs(e.balls) do b:Destroy() end
        table.remove(smokes, i)
      else
        local k = math.clamp(age / 2.5, 0, 1) * math.clamp((e.life - age) / 6, 0, 1)   -- 两秒半散开，最后六秒淡掉
        for _, b in ipairs(e.balls) do b.Transparency = 1 - (1 - (b:GetAttribute("A") or 0.2)) * k end
      end
    end
  end

  ---------------------------------------------------------------- 灯光、天空、雾（跟着昼夜、夜视仪）

  local function lerpC(a, b, k) return a:Lerp(b, math.clamp(k, 0, 1)) end
  local function lighting(elev)
    local dk = G.dayK and G.dayK() or 0.7
    local nv = (G.nvgOn and G.nvgOn()) and dk < 0.6
    local okS, sun = pcall(function() return Lighting:GetSunDirection() end)
    local L = (okS and typeof(sun) == "Vector3") and sun or V(0.4, 0.8, 0.3)
    if L.Y < -0.03 then
      local okM, moon = pcall(function() return Lighting:GetMoonDirection() end)
      if okM and typeof(moon) == "Vector3" then L = moon end
    end
    vpf.LightDirection = -L.Unit
    local amb = lerpC(C3(0.06, 0.07, 0.1), C3(0.5, 0.51, 0.54), dk)
    local lc = lerpC(C3(0.1, 0.12, 0.17), C3(0.82, 0.79, 0.72), dk)
    local il = G.illum and G.illum.k or 0   -- 照明弹
    if il > 0.01 then
      amb = lerpC(amb, C3(0.45, 0.42, 0.38), 0.6 * min(il, 1))
    end
    if nv then   -- 夜视仪：夜里增亮、变绿
      amb = lerpC(amb, C3(0.4, 0.52, 0.42), 1 - dk)
      lc = lerpC(lc, C3(0.32, 0.42, 0.34), 1 - dk)
    end
    -- 跟着主画面的曝光走（DayNight 夜里曝光 +0.55）：不然镜里一片黑、镜外亮着
    if not nv then
      local ek = math.clamp(2 ^ ((Lighting.ExposureCompensation or 0) * 0.7), 0.6, 1.6)
      amb = C3(min(1, amb.R * ek), min(1, amb.G * ek), min(1, amb.B * ek))
      lc = C3(min(1, lc.R * ek), min(1, lc.G * ek), min(1, lc.B * ek))
    end
    vpf.Ambient, vpf.LightColor = amb, lc
    -- 色调跟着主画面的调色（夜里偏冷蓝：DayNight 的 NightGrade），夜视仪变绿
    local tint = C3(1, 1, 1)
    local grade = Lighting:FindFirstChild("NightGrade")
    if grade and grade:IsA("ColorCorrectionEffect") and grade.Enabled then tint = grade.TintColor end
    if nv then tint = C3(0.74, 1, 0.76) end
    vpf.ImageColor3 = tint
    -- 天空：地平线是雾的颜色，往上是天顶色（看的范围就几度，整块按仰角取一个颜色）
    local fog = Lighting.FogColor
    local zen = lerpC(C3(0.03, 0.04, 0.07), C3(0.36, 0.53, 0.78), dk)
    vpf.BackgroundColor3 = lerpC(fog, zen, (math.clamp(elev / 0.4, 0, 1)) ^ 0.7)
    -- 雾：按大气浓度换算能见度（白天约 3000 格衰减到 1/e）
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    local dens = atm and atm.Density or 0.17
    if nv then dens *= 0.55 end
    local Df = 500 / math.max(0.04, dens)
    local hc = atm and lerpC(atm.Color, fog, 0.5) or fog
    hc = C3(hc.R * 0.88, hc.G * 0.88, hc.B * 0.88)
    local prev = 0
    for i, d in ipairs(HAZE) do
      local h = haze[i]
      h.Color = hc
      h.Transparency = math.exp(-(d - prev) / Df)
      prev = d
    end
  end

  ---------------------------------------------------------------- 每帧（Scope.lua 调）

  -- 镜片圆心 (x, y)、半径 r（像素），Z 倍率，f 淡入（0～1）；返回画中画的焦距（像素）
  function G.pipStep(x, y, r, Z, f)
    local t = now()
    local vs = cam.ViewportSize
    local fm = (vs.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)   -- 主镜头的焦距（像素）
    local tb = (r / fm) / math.max(1, Z)   -- 画中画半视角的正切：镜片的角大小 ÷ 倍率
    local d2 = math.floor(r + 0.5) * 2
    vpf.Size = UDim2.fromOffset(d2, d2)
    vpf.Position = UDim2.fromOffset(x, y)
    vpf.ImageTransparency, vpf.BackgroundTransparency = 1 - f, 1 - f
    vpf.Visible = true
    local cf = cam.CFrame
    pcam.CFrame = cf
    pcam.FieldOfView = 2 * math.deg(math.atan(tb))
    E, D, A = cf.Position, cf.LookVector, math.atan(tb * 1.42) + 0.004   -- 方形视口的对角
    lighting(math.asin(math.clamp(D.Y, -1, 1)))
    -- 雾的几张大片：正对镜头，盖住视野
    for i, d in ipairs(HAZE) do
      local s = math.min(2040, 2.6 * d * tb + 4)
      haze[i].Size = V(s, s, 0.05)
      haze[i].CFrame = cf * CF(0, 0, -d)
    end
    placeWater(E)
    if t - st.cellT > 0.1 then
      st.cellT = t
      updateCells(t)
    end
    if t - st.syncT > 0.5 then
      st.syncT = t
      syncCells()
    end
    updateDyn(t)
    updateSmoke(t)
    return r / tb
  end
  function G.pipHide()
    vpf.Visible = false
  end
  function G.pipDebug() return st, vpf, wm, pcam, dyn end   -- 测试用

  -- 后台：第一人称活着时把地形网格准备好、登记地图上的东西（开镜前就弄好，开镜那一下不卡）
  G.frameConn("ScopePip", function()
    if st.ok == false then return end
    local ch = me.Character
    if not ch or not G.fpActive then return end
    local v = G.fps   -- 手里是带瞄准镜的枪才准备（拿红点、全息、机械瞄具时不白算）
    if not (v and v.optic and v.optic.kind == "scope") then return end
    if not st.started then
      st.started = true
      watchStatic()
    end
    if now() - (st.watchT or 0) > 5 then   -- Ruins 之类的文件夹可能后来才有
      st.watchT = now()
      watchStatic()
    end
    maintain()
  end)
end

return ScopePip
