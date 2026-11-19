-- 全面大战场（客户端）——战场氛围。用户 11-18：「按照 3A 游戏的标准把这款游戏做到惊艳，自由发挥，参考战雷、战地」（夜晚照旧锁定）
--   1. 照明弹（服务器 Battle.lua 打的，特效 k = "illum"）：按服务器时间算——
--      发射：从舰炮 / 迫击炮那里一颗拖着短尾巴的亮点抛物线飞上去（离镜头远的不画）；炸开：一闪、一小团烟、「噗」一声（按距离晚到）；
--      挂着降落伞慢慢落、随风飘，一边烧一边拖出一条往上飘的白烟柱（被它自己照亮），往下掉火星；烧到最后几秒忽明忽暗、熄灭，伞掉得快了、淡掉。
--      照亮：Roblox 的点光源最远 60 格，照明弹在一百多格高——光源放在照明弹正下方离地 40 格的地方跟着走（离镜头最近的那发投影子：
--      影子跟着照明弹慢慢挪），再加上「附近有照明弹，整片地都亮起来」：G.illum = { k 亮度 0～1.2 }，DayNight.lua 按它把环境光往暖白抬、曝光加一点，一闪一闪
--   2. 夜空：一层低云；守方要地的对空探照灯慢慢扫；远处时不时的闷炮声（只有声音）
--   3. 房子着火、塌（服务器 Battle.lua）：着火的房子冒火、冒烟、火光一闪一闪；塌的时候扬起一大团尘土、碎块乱飞、轰隆一声；废墟冒一阵烟
local Warfx = {}

function Warfx.init(G)
  local RunService = game:GetService("RunService")
  local Debris = game:GetService("Debris")
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local MapM = G.Map
  local FXF = G.fxFolder or workspace
  local function camPos() local c = workspace.CurrentCamera return c and c.CFrame.Position or V() end
  local function serverNow()
    local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
    return ok and t or os.clock()
  end
  local TX = {
    glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
    smoke = "rbxasset://textures/particles/smoke_main.dds",
  }
  local EXP = "rbxasset://sounds/impact_explosion_03.mp3"
  local WIND = "rbxasset://sounds/action_falling.ogg"
  local WARM = RGB(255, 238, 208)

  local function part(shape, size, cf, color, mat, tr)
    local p = Instance.new("Part")
    p.Shape = shape or Enum.PartType.Block
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = mat or Enum.Material.SmoothPlastic
    p.Transparency = tr or 0
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = FXF
    return p
  end
  local function emitter(h, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex
    pe.Rate = o.rate or 0
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.spd[1], o.spd[2])
    pe.SpreadAngle = Vector2.new(o.spread or 180, o.spread or 180)
    pe.Size = o.size
    pe.Transparency = o.tr
    pe.Color = o.col
    pe.Acceleration = o.acc or V()
    pe.Drag = o.drag or 0
    pe.LightEmission = o.le or 0
    pe.LightInfluence = (o.le or 0) > 0.5 and 0 or 1
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-(o.rot or 20), o.rot or 20)
    pe.ZOffset = o.z or 0
    pe.EmissionDirection = o.dir or Enum.NormalId.Top
    pe.Parent = h
    return pe
  end
  local function nseq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = NSK(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  local function cseq(a, b) return ColorSequence.new({ CSK(0, a), CSK(1, b) }) end

  ---------------------------------------------------------------- 照明弹

  local GR = V(0, -60, 0)   -- 上升段的「重力」（看着像一发炮弹抛上去，不按真实重力：几秒就到）
  local flares = {}         -- 正在飞 / 烧的
  G.flares = flares         -- 测试用
  local illumK = 0

  -- 照明弹在本地时刻 t（os.clock）的位置：上升段抛物线，炸开后随风飘、慢慢落、轻轻摆
  --   收到时按服务器时间算出它已经飞了多久，换成本地时钟的起点 f.t0（以后只看本地时钟：不受服务器时间抖动影响）
  local function flarePos(f, t)
    local e = f.e
    local u = t - f.t0
    if u < e.fl then
      local v0 = (e.p - e.o - GR * (0.5 * e.fl * e.fl)) / e.fl
      return e.o + v0 * u + GR * (0.5 * u * u), "rise"
    end
    local b = u - e.fl
    local fall = e.fall * b
    if b > e.burn then fall = e.fall * e.burn + (b - e.burn) * e.fall * 4 end   -- 烧完了伞兜不住，掉得快
    local sway = V(math.sin(b * 0.9 + f.ph) * 1.6, 0, math.cos(b * 0.7 + f.ph) * 1.2)
    return e.p + (e.w or V()) * b - V(0, fall, 0) + sway, (b <= e.burn) and "burn" or "out"
  end

  -- 亮度 0～1：点着的头半秒亮起来，烧着时轻轻闪，最后 4 秒忽明忽暗地暗下去
  local function flareI(f, b, burn)
    if b < 0 or b > burn then return 0 end
    local up = math.clamp(b / 0.5, 0, 1)
    local fl = 0.88 + 0.07 * math.sin(b * 23 + f.ph) + 0.05 * math.sin(b * 37.7 + f.ph * 2)
    local tail = 1
    if b > burn - 4 then
      tail = math.clamp((burn - b) / 4, 0, 1)
      if math.random() < 0.25 then tail *= 0.45 end   -- 快烧完：噼啪地暗一下
    end
    return up * fl * tail
  end

  local function popSound(p, d)
    if not G.sfx or d > 3200 then return end
    G.sfx({ { id = EXP, vol = 0.55, s = { 1.9, 2.15 }, reg = { 0.02, 0.28 }, eq = { -6, 0, 0 } },
      { id = EXP, vol = 0.25, s = { 0.9, 1 }, reg = { 0.04, 0.6 }, eq = { 6, -4, -14 }, delay = 0.03 } },
      p, { delay = d / 960, rmin = 120, rmax = 3200, hiCut = -10 * math.clamp((d - 400) / 2000, 0, 1) })
  end

  local function ignite(f, pos)
    local d = (pos - camPos()).Magnitude
    if G.flash and d < 2400 then G.flash(pos, WARM, 50, 6, 0.3) end
    popSound(pos, d)
    local core = part(Enum.PartType.Ball, V(0.9, 0.9, 0.9), CFrame.new(pos), RGB(255, 246, 228), Enum.Material.Neon, 0)
    core.Name = "Illum"
    f.core = core
    -- 刺眼的一团光晕（一闪一闪）
    f.halo = emitter(core, { tex = TX.glow, rate = 22, life = { 0.12, 0.2 }, spd = { 0, 0 }, size = nseq(0, 6.5, 1, 9), tr = nseq(0, 0.2, 1, 0.65),
      col = cseq(RGB(255, 250, 236), WARM), le = 1, z = 1 })
    -- 往下掉的火星
    f.sparks = emitter(core, { tex = TX.glow, rate = 7, life = { 0.6, 1.4 }, spd = { 2, 6 }, spread = 35, dir = Enum.NormalId.Bottom, acc = V(0, -40, 0),
      size = nseq(0, 0.4, 1, 0), tr = nseq(0, 0, 1, 0.4), col = cseq(RGB(255, 236, 190), RGB(255, 150, 70)), le = 1 })
    -- 往上飘的白烟柱：被照明弹自己照亮（受光），一条留在半空慢慢散开
    local pk = G.perfK or 1
    if d < 6000 then
      f.smoke = emitter(core, { tex = TX.smoke, rate = (pk < 0.75) and 4 or 9, life = { 9, 15 }, spd = { 0.5, 1.5 }, spread = 25,
        acc = V(0, 0.8, 0) + (f.e.w or V()) * 0.3, drag = 0.3, size = nseq(0, 1.6, 0.3, 4.5, 1, 10), tr = nseq(0, 0.3, 0.6, 0.6, 1, 1),
        col = cseq(RGB(228, 224, 216), RGB(150, 150, 158)), rot = 15 })
    end
    -- 降落伞：一顶白伞 + 一根吊绳
    f.chute = part(Enum.PartType.Ball, V(5.2, 2, 5.2), CFrame.new(pos + V(0, 5.5, 0)), RGB(226, 226, 220), Enum.Material.Fabric, 0)
    f.cord = part(Enum.PartType.Block, V(0.06, 5, 0.06), CFrame.new(pos + V(0, 2.6, 0)), RGB(60, 60, 60), Enum.Material.SmoothPlastic, 0)
    -- 照亮自己周围（烟、伞）的小灯
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness, pl.Color, pl.Shadows = 30, 2, WARM, false
    pl.Parent = core
    f.selfLight = pl
    -- 照地面的灯：在照明弹正下方离地 40 格（最远 60 格）
    local anchor = part(Enum.PartType.Block, V(0.2, 0.2, 0.2), CFrame.new(pos), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local gl = Instance.new("PointLight")
    gl.Range, gl.Brightness, gl.Color, gl.Shadows = 60, 4, WARM, false
    gl.Parent = anchor
    f.anchor, f.groundLight = anchor, gl
    -- 烧着的嘶嘶声
    if G.makeSound and d < 600 then
      f.hiss = G.makeSound({ id = WIND, vol = 2.2, s = { 1.6, 1.8 }, loop = { 0.5, 9.5 }, eq = { -16, 0, 4 } }, core, { rmin = 20, rmax = 260 })
    end
  end

  local function extinguish(f)
    if f.out then return end
    f.out = true
    for _, k in ipairs({ "halo", "sparks", "smoke" }) do if f[k] then f[k].Enabled = false end end
    if f.selfLight then f.selfLight.Enabled = false end
    if f.groundLight then f.groundLight.Enabled = false end
    if f.core then f.core.Transparency = 1 end
    if f.hiss then f.hiss:Stop() end
    if f.core then Debris:AddItem(f.core, 16) end   -- 烟柱的粒子还要飘一会儿
    if f.anchor then Debris:AddItem(f.anchor, 0.1) end
    if f.chute then
      if G.tween then
        G.tween(f.chute, 5, { Transparency = 1 })
        G.tween(f.cord, 5, { Transparency = 1 })
      end
      Debris:AddItem(f.chute, 5.2)
      Debris:AddItem(f.cord, 5.2)
    end
  end

  local function newIllum(e)
    if typeof(e.o) ~= "Vector3" or typeof(e.p) ~= "Vector3" or type(e.t) ~= "number" then return end
    e.fl, e.burn, e.fall = e.fl or 3, e.burn or 30, e.fall or 2.6
    local u = math.max(0, serverNow() - e.t)
    if u > e.fl + e.burn then return end   -- 进服前就烧完了
    local f = { e = e, ph = math.random() * 6.28, t0 = os.clock() - u }
    -- 上升段：一颗拖着短尾巴的亮点（发射点、炸开点都离镜头远的不画）
    local cp = camPos()
    if u < e.fl and math.min((e.o - cp).Magnitude, (e.p - cp).Magnitude) < 2500 then
      local sh = part(Enum.PartType.Ball, V(0.5, 0.5, 0.5), CFrame.new(e.o), RGB(255, 214, 160), Enum.Material.Neon, 0)
      local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
      a0.Position, a1.Position = V(0, 0.25, 0), V(0, -0.25, 0)
      a0.Parent, a1.Parent = sh, sh
      local tr = Instance.new("Trail")
      tr.Attachment0, tr.Attachment1 = a0, a1
      tr.Lifetime, tr.LightEmission, tr.FaceCamera = 0.35, 1, true
      tr.Color = cseq(RGB(255, 226, 180), RGB(255, 150, 80))
      tr.Transparency = nseq(0, 0.2, 1, 1)
      tr.Parent = sh
      f.shell = sh
      if (e.o - cp).Magnitude < 1800 then
        if e.by == "def" then
          if G.playSound then G.playSound("mortar", e.o) end
        elseif G.sfx then
          G.sfx({ { id = EXP, vol = 0.9, s = { 0.62, 0.7 }, reg = { 0, 1.4 }, eq = { 8, 0, -10 } } }, e.o, { delay = (e.o - cp).Magnitude / 960, rmin = 150, rmax = 6000 })
        end
      end
    end
    table.insert(flares, f)
  end

  local function stepFlares()
    if #flares == 0 then
      illumK = 0
      return
    end
    local t = os.clock()
    local cp = camPos()
    local k, nearest, nd = 0, nil, math.huge
    for i = #flares, 1, -1 do
      local f = flares[i]
      local e = f.e
      local pos, ph = flarePos(f, t)
      local b = t - f.t0 - e.fl
      if ph == "rise" then
        if f.shell then f.shell.CFrame = CFrame.new(pos) end
      else
        if f.shell then
          f.shell:Destroy()
          f.shell = nil
        end
        if not f.core and ph == "burn" then ignite(f, pos) end
        local gy = math.max(0, MapM.ground(pos.X, pos.Z))
        local alt = pos.Y - gy
        if f.core and not f.out and (ph == "out" or alt < 3) then extinguish(f) end
        if f.out then
          -- 已熄灭：伞还在掉（落到地上就停）
          if f.chute and f.chute.Parent and alt > 2 then
            f.chute.CFrame = CFrame.new(pos + V(0, 5.5, 0))
            f.cord.CFrame = CFrame.new(pos + V(0, 2.6, 0))
          end
        elseif f.core then
          local I = flareI(f, b, e.burn)
          f.core.CFrame = CFrame.new(pos)
          if f.chute then
            local tilt = CFrame.Angles(math.sin(b * 0.9 + f.ph) * 0.12, 0, math.cos(b * 0.7 + f.ph) * 0.12)
            f.chute.CFrame = CFrame.new(pos + V(0, 5.5, 0)) * tilt
            f.cord.CFrame = CFrame.new(pos + V(0, 2.6, 0)) * tilt
          end
          f.halo.Rate = 22 * math.max(0.2, I)
          f.selfLight.Brightness = 2.4 * I
          f.anchor.CFrame = CFrame.new(pos.X, gy + math.min(alt, 40), pos.Z)
          f.groundLight.Brightness = 4.5 * I
          local d = (pos - cp).Magnitude
          if d < nd then nearest, nd = f, d end
          -- 整片地亮起来：离照明弹 140 格内最亮，700 格外没有
          k += I * math.clamp(1 - (d - 140) / 560, 0, 1)
        end
        if b > e.burn + 6 then table.remove(flares, i) end
      end
    end
    -- 只有离镜头最近的那发投影子（点光源投影子很贵）
    for _, f in ipairs(flares) do
      if f.groundLight then f.groundLight.Shadows = (f == nearest) and nd < 900 end
    end
    illumK = math.min(1.2, k)
  end

  G.illum = { k = 0, col = WARM }
  G.fxExtra = G.fxExtra or {}
  G.fxExtra.illum = newIllum

  ---------------------------------------------------------------- 夜空：低云
  -- Roblox 地形的云（Terrain.Clouds）：一层压得低的深灰蓝的云，月光照着边、遮住一半星星，开飞机能钻进去；机器跟不上（G.perfK 低）就关掉
  local clouds
  pcall(function()
    local T = workspace.Terrain
    clouds = T:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
    clouds.Cover, clouds.Density, clouds.Color = 0.6, 0.5, RGB(66, 72, 88)
    clouds.Parent = T
  end)
  G.nightClouds = clouds   -- 测试用

  ---------------------------------------------------------------- 探照灯
  -- 守方几处要地（指挥部、机场、港口、营地）各两盏对空探照灯：灰绿色的灯筒架在矮杆上，一道淡蓝白的光柱斜着照上天，慢慢来回扫
  --   （二战登陆夜战那种画面）。只是画面：每个客户端自己画，扫的角度按服务器时间算（大家看到的差不多同步）；离镜头 9000 格外的不更新、不画
  local LIGHTS = {}
  G.searchlights = LIGHTS   -- 测试用
  local slFolder = Instance.new("Folder")
  slFolder.Name = "Searchlights"
  slFolder.Parent = FXF
  local function addLight(x, z, ph, az0)
    local gy = math.max(0, MapM.ground(x, z))
    local base = V(x, gy, z)
    local pole = part(Enum.PartType.Block, V(0.8, 7, 0.8), CFrame.new(base + V(0, 3.5, 0)), RGB(48, 52, 46), Enum.Material.Metal, 0)
    pole.Parent = slFolder
    local head = part(Enum.PartType.Cylinder, V(3.2, 3.6, 3.6), CFrame.new(base + V(0, 8.5, 0)), RGB(66, 74, 60), Enum.Material.Metal, 0)
    head.Parent = slFolder
    local lens = part(Enum.PartType.Cylinder, V(0.2, 3.1, 3.1), CFrame.new(base + V(0, 8.5, 0)), RGB(230, 238, 255), Enum.Material.Neon, 0)
    lens.Parent = slFolder
    local a0 = Instance.new("Attachment")
    a0.Parent = lens
    local beams = {}
    for _, spec in ipairs({ { len = 1100, w0 = 3, w1 = 60, a = 0.84 }, { len = 650, w0 = 1.6, w1 = 18, a = 0.7 } }) do
      local a1 = Instance.new("Attachment")
      a1.Position = V(spec.len, 0, 0)   -- 圆柱的轴是 X：灯头朝 +X 照（下面摆灯头时把 +X 转到光的方向）
      a1.Parent = lens
      local b = Instance.new("Beam")
      b.Attachment0, b.Attachment1 = a0, a1
      b.Width0, b.Width1 = spec.w0, spec.w1
      b.FaceCamera, b.LightEmission, b.LightInfluence, b.Segments = true, 1, 0, 1
      b.Color = ColorSequence.new(RGB(226, 234, 255), RGB(190, 206, 240))
      b.Transparency = nseq(0, spec.a, 0.12, spec.a + 0.03, 1, 1)
      b.Parent = lens
      table.insert(beams, b)
    end
    table.insert(LIGHTS, { base = base, head = head, lens = lens, beams = beams, ph = ph, az0 = az0 })
  end
  pcall(function()
    local sites = {}
    if MapM.COMMAND then table.insert(sites, { MapM.COMMAND.x, MapM.COMMAND.z }) end
    if MapM.AIRFIELD then table.insert(sites, { MapM.AIRFIELD.x, MapM.AIRFIELD.z - 160 }) end
    if MapM.PORT then table.insert(sites, { MapM.PORT.x, MapM.PORT.z - 60 }) end
    if MapM.CAMP then table.insert(sites, { MapM.CAMP.x, MapM.CAMP.z }) end
    for i, s in ipairs(sites) do
      -- 朝海（南边，攻方来的方向）照：两盏一左一右、相位错开
      addLight(s[1] - 55, s[2] + 30, i * 1.7, math.rad(160))
      addLight(s[1] + 55, s[2] + 30, i * 1.7 + 2.4, math.rad(200))
    end
  end)

  local function stepLights()
    if #LIGHTS == 0 then return end
    local t = serverNow()
    local cp = camPos()
    for _, L in ipairs(LIGHTS) do
      local near = (L.base - cp).Magnitude < 9000
      for _, b in ipairs(L.beams) do b.Enabled = near end
      if near then
        -- 方位角在朝海方向左右各 50° 里慢慢来回，仰角 35°～72°
        local az = L.az0 + math.rad(50) * math.sin(t * 0.11 + L.ph)
        local el = math.rad(53) + math.rad(19) * math.sin(t * 0.17 + L.ph * 1.3)
        local dir = V(math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el))
        local p = L.base + V(0, 8.5, 0)
        local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.pi / 2, 0)   -- lookAt 的 −Z 朝 dir；绕 Y 转 90° 以后 +X 朝 dir（圆柱的轴）
        L.head.CFrame = cf
        L.lens.CFrame = cf * CFrame.new(1.65, 0, 0)
      end
    end
  end

  ---------------------------------------------------------------- 远处的炮声
  -- 战地那种「远处还在打」的底噪：每隔 7～16 秒，镜头外三四千格（作战区外、海那边）随机一个方向一声低沉的闷响（放慢、只留低音、长回声），
  --   有时候连着两三声（一轮齐射）。只有声音：不画东西（画了会让人以为那边有人）
  local rumbleAt = os.clock() + 8
  local rumbles = 0
  G.rumbleCount = function() return rumbles end   -- 测试用
  local function stepRumble()
    local t = os.clock()
    if t < rumbleAt then return end
    rumbleAt = t + 7 + math.random() * 9
    if not G.sfx then return end
    local a = math.random() * 2 * math.pi
    local p = camPos() + V(math.cos(a), 0, math.sin(a)) * (3200 + math.random() * 1800)
    local n = (math.random() < 0.35) and math.random(2, 3) or 1
    for i = 1, n do
      G.sfx({ { id = EXP, vol = 0.55, s = { 0.4, 0.48 }, reg = { 0, 2.2 }, eq = { 10, -6, -26 }, echo = { 0.42, 0.45, -8 }, delay = (i - 1) * (0.5 + math.random() * 0.6) } },
        p, { rmin = 2500, rmax = 9000 })
    end
    rumbles += 1
  end

  ---------------------------------------------------------------- 房子着火、塌（服务器 Battle.lua）
  -- 着火：房子模型的属性 Burning（被炸掉一半血）——屋顶那一层冒火、往上冒黑烟、橙色的火光一闪一闪（夜里很远就看得到）；
  --   效果挂在房子模型底下（本地的）：房子塌了被服务器挪走，效果跟着没。每秒查一次属性；房子列表 15 秒重扫一次（新一局复原的房子是新的副本）
  -- 塌：特效 collapse——扬起一大团尘土（往外冲的一圈 + 往上翻的一大团）、十几块碎块真的飞出去落地、轰隆一声（按距离晚到）、近处镜头震
  -- 废墟（Ruins 文件夹里的 Ruin_ 模型）：冒一阵烟、几点余火（90 秒后烟停）
  local FIRE = "rbxasset://textures/particles/fire_main.dds"
  local THUD = "rbxasset://sounds/action_jump_land.mp3"
  local bldList, scanAt = {}, 0
  local burning = {}   -- [模型] = { h, light, ph }
  local ruinFx = {}    -- [模型] = true
  local collapses = 0
  G.collapseCount = function() return collapses end   -- 测试用

  local function decorateFire(m)
    local base, size = m:GetAttribute("BldBase"), m:GetAttribute("BldSize")
    if typeof(base) ~= "CFrame" or typeof(size) ~= "Vector3" then return end
    local h = part(Enum.PartType.Block, V(math.min(size.X, 14) * 0.6, 1, math.min(size.Z, 14) * 0.6), base * CFrame.new(0, size.Y * 0.7, 0), RGB(0, 0, 0), nil, 1)
    h.Name = "BldFire"
    h.Parent = m
    emitter(h, { tex = FIRE, rate = 16, life = { 0.6, 1.2 }, spd = { 3, 7 }, spread = 25, acc = V(0, 8, 0), size = nseq(0, 4.5, 1, 1),
      tr = nseq(0, 0.15, 1, 1), col = cseq(RGB(255, 204, 128), RGB(255, 92, 40)), le = 0.9 })
    emitter(h, { tex = TX.smoke, rate = 4, life = { 7, 11 }, spd = { 4, 8 }, spread = 15, acc = V(1.5, 4, 0.8), size = nseq(0, 4, 1, 18),
      tr = nseq(0, 0.35, 1, 1), col = cseq(RGB(38, 34, 32), RGB(96, 92, 88)), rot = 10 })
    local pl = Instance.new("PointLight")
    pl.Range, pl.Brightness, pl.Color, pl.Shadows = 44, 3, RGB(255, 150, 80), false
    pl.Parent = h
    burning[m] = { h = h, light = pl, ph = math.random() * 6.28 }
  end

  local function decorateRuin(m)
    ruinFx[m] = true
    local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
    if not ok or typeof(cf) ~= "CFrame" then
      local p0 = m:FindFirstChildWhichIsA("BasePart")
      if not p0 then return end
      cf, size = p0.CFrame, V(12, 4, 12)
    end
    local h = part(Enum.PartType.Block, V(math.max(4, size.X * 0.5), 1, math.max(4, size.Z * 0.5)), CFrame.new(cf.Position), RGB(0, 0, 0), nil, 1)
    h.Name = "RuinSmoke"
    h.Parent = m
    local sm = emitter(h, { tex = TX.smoke, rate = 3, life = { 8, 13 }, spd = { 2, 5 }, spread = 25, acc = V(1.2, 2.5, 0.6), size = nseq(0, 5, 1, 16),
      tr = nseq(0, 0.45, 1, 1), col = cseq(RGB(70, 66, 62), RGB(120, 116, 110)), rot = 8 })
    local em = emitter(h, { tex = TX.glow, rate = 4, life = { 0.8, 1.6 }, spd = { 1, 4 }, spread = 40, acc = V(0, 3, 0), size = nseq(0, 0.35, 1, 0),
      tr = nseq(0, 0, 1, 0.5), col = cseq(RGB(255, 190, 110), RGB(255, 110, 50)), le = 1 })
    task.delay(90, function() sm.Enabled = false em.Enabled = false end)
  end

  local function stepBlds()
    local t = os.clock()
    if t >= scanAt then
      scanAt = t + 15
      table.clear(bldList)
      for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") and d:GetAttribute("Bld") then table.insert(bldList, d) end
      end
    end
    for _, m in ipairs(bldList) do
      local on = m.Parent ~= nil and m:GetAttribute("Burning") == true
      if on and not burning[m] then
        decorateFire(m)
      elseif not on and burning[m] then
        if burning[m].h.Parent then burning[m].h:Destroy() end
        burning[m] = nil
      end
    end
    for m in pairs(burning) do
      if not m.Parent then burning[m] = nil end
    end
    local rf = workspace:FindFirstChild("Ruins")
    if rf then
      for _, m in ipairs(rf:GetChildren()) do
        if m:IsA("Model") and not ruinFx[m] then decorateRuin(m) end
      end
    end
    for m in pairs(ruinFx) do
      if not m.Parent then ruinFx[m] = nil end
    end
  end

  local function stepBurn()
    local cp = camPos()
    local t = os.clock()
    for m, b in pairs(burning) do
      if b.h.Parent and (b.h.CFrame.Position - cp).Magnitude < 1500 then
        b.light.Brightness = 2.6 + 0.6 * math.sin(t * 11 + b.ph) + 0.4 * math.sin(t * 23.7 + b.ph * 2)
      end
    end
  end

  G.fxExtra.collapse = function(e)
    if typeof(e.p) ~= "Vector3" or typeof(e.s) ~= "Vector3" then return end
    collapses += 1
    local p, s = e.p, e.s
    local gy = (typeof(e.cf) == "CFrame") and e.cf.Position.Y or (p.Y - s.Y / 2)
    local cp = camPos()
    local d = (p - cp).Magnitude
    if G.sfx and d < 5000 then
      G.sfx({ { id = EXP, vol = 1.3, s = { 0.36, 0.42 }, reg = { 0, 2.4 }, eq = { 10, -2, -16 }, echo = { 0.3, 0.35, -8 } },
        { id = THUD, vol = 1.2, s = { 0.32, 0.36 }, eq = { 8, 0, -12 }, delay = 0.25 },
        { id = THUD, vol = 0.9, s = { 0.4, 0.45 }, eq = { 6, 0, -10 }, delay = 0.6 } },
        p, { delay = d / 960, rmin = 80, rmax = 4500, must = true })
    end
    if d < 400 and G.shake then G.shake(0.55 * (1 - d / 400)) end
    if d > 4000 then return end
    local w = math.max(s.X, s.Z)
    local h = part(Enum.PartType.Block, V(1, 1, 1), CFrame.new(p.X, gy + 1.5, p.Z), RGB(0, 0, 0), nil, 1)
    -- 往外冲的一圈尘浪：零件绕竖轴转着一颗一颗往前发
    local ring = emitter(h, { tex = TX.smoke, life = { 2.5, 4.5 }, spd = { w * 0.6, w * 1.2 }, spread = 8, drag = 1.6, dir = Enum.NormalId.Front,
      acc = V(0, 1.5, 0), size = nseq(0, w * 0.18, 1, w * 0.55), tr = nseq(0, 0.25, 1, 1), col = cseq(RGB(164, 152, 134), RGB(140, 132, 120)), rot = 20 })
    local base = h.CFrame
    for i = 1, 18 do
      h.CFrame = base * CFrame.Angles(0, (i + math.random() * 0.6) * 2 * math.pi / 18, 0)
      ring:Emit(1)
    end
    h.CFrame = base
    -- 往上翻的一大团
    local col = emitter(h, { tex = TX.smoke, life = { 5, 9 }, spd = { w * 0.25, w * 0.7 }, spread = 50, drag = 1.2, acc = V(1, 3.5, 0.5),
      size = nseq(0, w * 0.3, 0.4, w * 0.75, 1, w * 1.1), tr = nseq(0, 0.12, 0.6, 0.45, 1, 1), col = cseq(RGB(150, 140, 124), RGB(104, 98, 90)), rot = 12 })
    col:Emit(math.floor(10 + w / 3))
    Debris:AddItem(h, 10)
    -- 碎块：真的零件往外飞、落地弹几下（本地物理）
    local n = math.clamp(math.floor(w / 2), 8, 18)
    if (G.perfK or 1) < 0.8 then n = math.floor(n / 2) end
    for i = 1, n do
      local c = Instance.new("Part")
      c.Size = V(0.6 + math.random() * 1.8, 0.5 + math.random() * 1.2, 0.6 + math.random() * 1.8)
      c.Color = (i % 3 == 0) and RGB(64, 58, 52) or RGB(108, 100, 90)
      c.Material = Enum.Material.Concrete
      c.CFrame = CFrame.new(p + V((math.random() - 0.5) * s.X * 0.6, (math.random() - 0.2) * s.Y * 0.4, (math.random() - 0.5) * s.Z * 0.6))
      c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = false, true, false, false, true
      c.Parent = FXF
      local dir = V(math.random() - 0.5, 0, math.random() - 0.5)
      dir = dir.Magnitude > 0.05 and dir.Unit or V(1, 0, 0)
      pcall(function()
        c.AssemblyLinearVelocity = dir * (8 + math.random() * 18) + V(0, 10 + math.random() * 22, 0)
        c.AssemblyAngularVelocity = V(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
      end)
      Debris:AddItem(c, 4 + math.random())
    end
  end

  local acc, bAcc = 0, 0
  RunService.RenderStepped:Connect(function(dt)
    local ok, err = pcall(stepFlares)
    if not ok and G.showError then G.showError("照明弹：" .. tostring(err)) end
    G.illum.k = illumK
    acc += dt or 1 / 60
    if acc >= 1 / 30 then   -- 探照灯、远处的炮声：一秒 30 次就够
      acc = 0
      local ok2, err2 = pcall(function()
        stepLights()
        stepRumble()
        stepBurn()
        if clouds then clouds.Enabled = (G.perfK or 1) >= 0.7 end
      end)
      if not ok2 and G.showError then G.showError("战场氛围：" .. tostring(err2)) end
    end
    bAcc += dt or 1 / 60
    if bAcc >= 1 then   -- 房子着火、废墟：一秒查一次
      bAcc = 0
      local ok3, err3 = pcall(stepBlds)
      if not ok3 and G.showError then G.showError("房子：" .. tostring(err3)) end
    end
  end)
end

return Warfx
