-- 全面大战场（客户端）——战场氛围。用户 11-18：「按照 3A 游戏的标准把这款游戏做到惊艳，自由发挥，参考战雷、战地」（夜晚照旧锁定）
--   1. 照明弹（服务器 Battle.lua 打的，特效 k = "illum"）：按服务器时间算——
--      发射：从舰炮 / 迫击炮那里一颗拖着短尾巴的亮点抛物线飞上去（离镜头远的不画）；炸开：一闪、一小团烟、「噗」一声（按距离晚到）；
--      挂着降落伞慢慢落、随风飘，往上冒烟、往下掉火星，最后几秒逐渐熄灭。
--      照亮：Roblox 的点光源最远 60 格，照明弹在一百多格高——光源放在照明弹正下方离地 40 格的地方跟着走（离镜头最近的那发投影子：
--      影子跟着照明弹慢慢挪），DayNight.lua 按 G.illum 平滑提高附近环境光与曝光。
--   2. 夜空：一层低云；守方要地的对空探照灯慢慢扫；远处时不时的闷炮声（只有声音）
--   3. 房子着火、塌（服务器 Battle.lua）：着火的房子冒火、冒烟、火光一闪一闪；塌的时候扬起一大团尘土、碎块乱飞、轰隆一声；废墟冒一阵烟
--   4. 暴风雨（服务器给强度 StormK）：雨、闪电、雷声，云变厚、浪变大、风变大、雾变近
--   5. 阵亡镜头：死了以后镜头转向凶手、拉近，去色、景深，红色标记
local Warfx = {}

function Warfx.init(G)
  local RunService = game:GetService("RunService")
  local Debris = game:GetService("Debris")
  local Lighting = game:GetService("Lighting")
  local Players = game:GetService("Players")
  local GuiService = game:GetService("GuiService")
  local reducedMotion = false
  pcall(function()
    local function readMotion() reducedMotion = GuiService.ReducedMotionEnabled == true end
    readMotion()
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(readMotion)
  end)
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

  -- 柔和升降亮度，避免把高频闪烁传给整个夜间调色。
  local function flareI(f, b, burn)
    if b < 0 or b > burn then return 0 end
    local up = math.clamp(b / 0.75, 0, 1)
    local tail = math.clamp((burn - b) / 4, 0, 1)
    local glow = reducedMotion and 0.95 or (0.95 + 0.05 * math.sin(b * 2.4 + f.ph))
    return up * glow * tail
  end

  local function popSound(p, d)
    if not G.sfx or d > 3200 then return end
    G.sfx({ { id = EXP, vol = 0.55, s = { 1.9, 2.15 }, reg = { 0.02, 0.28 }, eq = { -6, 0, 0 } },
      { id = EXP, vol = 0.25, s = { 0.9, 1 }, reg = { 0.04, 0.6 }, eq = { 6, -4, -14 }, delay = 0.03 } },
      p, { delay = d / 960, rmin = 120, rmax = 3200, hiCut = -10 * math.clamp((d - 400) / 2000, 0, 1) })
  end

  local function ignite(f, pos, age)
    local d = (pos - camPos()).Magnitude
    if age < 0.65 then
      if not reducedMotion and G.flash and d < 2400 then G.flash(pos, WARM, 50, 2.7, 0.3) end
      popSound(pos, d)
    end
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
      G.illum.pos = nil
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
        if not f.core and ph == "burn" then ignite(f, pos, b) end
        if not f.groundAt or t >= f.groundAt then
          f.ground = math.max(0, MapM.ground(pos.X, pos.Z))
          f.groundAt = t + 1 / 20
        end
        local gy = f.ground
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
      if f.groundLight then
        local shadows = f == nearest and nd < 900 and not reducedMotion and (G.perfK or 1) >= 0.8
        if f.groundLight.Shadows ~= shadows then f.groundLight.Shadows = shadows end
      end
    end
    illumK = math.min(1.2, k)
    G.illum.pos = (nearest and nearest.core and nd < 1500) and nearest.core.Position or nil   -- 座舱盖上的划痕迎着它反光（Interior.lua）
  end

  G.illum = { k = 0, col = WARM }
  G.brightFlare = function() return G.illum.pos end   -- 离镜头最近、还在烧的照明弹在哪（没有就 nil）
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

  ---------------------------------------------------------------- 积云（用户 11-24：「要能在任何位置都适合打坦克战、空战，包括云朵」）
  -- 地形的云是平平的一层；空战要一团一团的积云（能钻进去躲、穿出来）：按定死的种子在作战区上空摆几十团，每团十来个半透明的大球
  --   挤在一起（底下一块扁的云底、上面鼓起来），夜里是月光照着的灰蓝色、越往上越亮；不碰撞、不挡射线、不投影；客户端自己的、只摆一次
  local banks = Instance.new("Folder")
  banks.Name = "CloudBanks"
  banks.Parent = FXF
  G.cloudBanks = banks   -- 测试用
  local cloudParts = {}   -- { 零件, 上下位置 0 云底 ～ 1 云顶 }：昼夜更替跟着时间重新上色（stepCloudTint）
  -- 云跟着时间变色（用户 11-25「给沙漠地图做个昼夜更替」）：夜里月光照着的灰蓝、白天白、日出日落染一层橙粉；
  --   地形的那层云（clouds）也一样。亮度变了 0.02 以上才重新上色（几秒一次）
  local C_NLOW, C_NHIGH = RGB(70, 78, 94), RGB(122, 130, 146)
  local C_DLOW, C_DHIGH = RGB(198, 200, 206), RGB(248, 248, 246)
  local C_TW = RGB(250, 178, 140)
  local tintK = -1        -- 上次按哪个亮度上的色
  local tintLo, tintHi, tintI = nil, nil, 0   -- 正在重新上色（drainTint）：这一轮的云底色、云顶色，上到第几块了
  -- 现在该是什么颜色：亮度键、云底色、云顶色、昼夜（0 夜 ～ 1 昼）、日出日落的染色
  local function tintNow()
    local dk = G.dayK and G.dayK() or 0
    local c = G.clockNow and G.clockNow() or 2.3
    local alt = math.sin((c - 6) / 12 * math.pi)
    local tw = math.clamp(1 - math.abs(alt - 0.05) / 0.25, 0, 1) * 0.55
    return dk + tw * 3, C_NLOW:Lerp(C_DLOW, dk):Lerp(C_TW, tw), C_NHIGH:Lerp(C_DHIGH, dk):Lerp(C_TW, tw * 0.8), dk, tw
  end
  local fading, builtAt = nil, -99   -- fading：正在淡掉的那批球 { t0, list = { { 零件, 原来的透明度 } }, acc }；builtAt：这批是什么时候摆的
  local function dropFading()
    if not fading then return end
    for _, f in ipairs(fading.list) do f[1]:Destroy() end
    fading = nil
  end
  local function cloudBanks()
    -- 雪山上导入了体积云（SnowClouds.lua 开着，G.snowCloudsOn）：不再摆这几十团半透明的球——两套云叠着，
    --   五百多个透明大球一层层排序、填满屏幕是显卡最贵的（11-27 M3 丝滑）；没导入体积云照旧摆。
    --   已经摆了一会儿的（clouds.glb 晚到：SnowClouds 每 3 秒查一次、最多两分钟）1 秒淡掉再删，不一下子全没；刚摆的（换图那一下）直接删
    if G.snowCloudsOn then
      if #cloudParts > 0 then
        if os.clock() - builtAt > 2 then
          dropFading()
          local list = {}
          for _, it in ipairs(cloudParts) do if it[1].Parent then list[#list + 1] = { it[1], it[1].Transparency } end end
          fading = { t0 = os.clock(), list = list, acc = 0 }
        else
          dropFading()
          banks:ClearAllChildren()
        end
        table.clear(cloudParts)
      end
      tintLo = nil
      return
    end
    fading = nil
    banks:ClearAllChildren()
    table.clear(cloudParts)
    -- 摆的时候就按现在的钟点上色（原来先摆成夜里的灰蓝，要等下一次一秒一查才重新上色；正在分帧上色的那一轮也作废，不刷到新零件上）
    local key, LOW, HIGH, dk, tw = tintNow()
    tintK, tintLo = key, nil
    if clouds then clouds.Color = RGB(66, 72, 88):Lerp(RGB(244, 242, 238), dk):Lerp(C_TW, tw) end   -- 地形那层云同一个钟点（stepCloudTint 看到键没变就不再上）
    builtAt = os.clock()
    local rng = Random.new(91124)
    local span = (MapM.PLAY or 20000) * 0.9
    for _ = 1, 54 do
      local cx, cz = rng:NextNumber(-span, span), rng:NextNumber(-span, span)
      local cy = rng:NextNumber(1900, 3600)
      local size = rng:NextNumber(280, 720)
      local base = Instance.new("Part")
      base.Shape = Enum.PartType.Cylinder
      base.Size = Vector3.new(size * 0.22, size * 2.2, size * 2.2)
      base.CFrame = CFrame.new(cx, cy, cz) * CFrame.Angles(0, 0, math.pi / 2)
      base.Color, base.Transparency = LOW, 0.62
      table.insert(cloudParts, { base, 0 })
      for _, b in ipairs({ base }) do
        b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.CastShadow = true, false, false, false, false
        b.Material = Enum.Material.SmoothPlastic
        b.Parent = banks
      end
      for _ = 1, rng:NextInteger(7, 12) do
        local r = size * rng:NextNumber(0.32, 0.62)
        local up = rng:NextNumber(0, 1)
        local b = Instance.new("Part")
        b.Shape = Enum.PartType.Ball
        b.Size = Vector3.new(r * 2, r * 2, r * 2)
        b.CFrame = CFrame.new(cx + rng:NextNumber(-1, 1) * size * 0.9, cy + r * 0.35 + up * size * 0.32, cz + rng:NextNumber(-0.7, 0.7) * size * 0.9)
        b.Color = LOW:Lerp(HIGH, up)
        table.insert(cloudParts, { b, up })
        b.Transparency = rng:NextNumber(0.5, 0.68)
        b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.CastShadow = true, false, false, false, false
        b.Material = Enum.Material.SmoothPlastic
        b.Parent = banks
      end
    end
  end
  pcall(cloudBanks)
  if G.onMap then G.onMap(function() pcall(cloudBanks) end) end   -- 换地图（作战区大小变了）重摆
  G.cloudBanksRefresh = function() pcall(cloudBanks) end   -- SnowClouds 开 / 关时调
  -- 淡掉的那批球：一秒 20 次往透明走，1 秒后删（五百多块，每帧都写太多）
  local function stepFading(dt)
    local f = fading
    if not f then return end
    local u = (os.clock() - f.t0) / 1
    if u >= 1 then
      dropFading()
      return
    end
    f.acc += dt or 1 / 60
    if f.acc < 0.05 then return end
    f.acc = 0
    for _, it in ipairs(f.list) do it[1].Transparency = it[2] + (1 - it[2]) * u end
  end
  G.cloudBanksFading = function() return fading ~= nil end   -- 测试用
  G.cloudTintBusy = function() return tintLo ~= nil end       -- 测试用：还在分帧上色
  local function stepCloudTint()
    local key, lo, hi, dk, tw = tintNow()
    if math.abs(key - tintK) < 0.02 then return end
    tintK = key
    tintLo, tintHi, tintI = lo, hi, 0   -- 五百多块分几帧上色（drainTint），不在一帧里全改（11-27：那一帧一顿）
    if clouds then clouds.Color = RGB(66, 72, 88):Lerp(RGB(244, 242, 238), dk):Lerp(C_TW, tw) end
  end
  local TINT_N = 120   -- 一帧最多上色几块
  local function drainTint()
    if not tintLo then return end
    local n = #cloudParts
    local stop = math.min(n, tintI + TINT_N)
    for i = tintI + 1, stop do
      local it = cloudParts[i]
      if it[1].Parent then it[1].Color = tintLo:Lerp(tintHi, it[2]) end
    end
    tintI = stop
    if tintI >= n then tintLo = nil end
  end

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
    local t = reducedMotion and 0 or serverNow()
    local cp = camPos()
    for _, L in ipairs(LIGHTS) do
      local near = (L.base - cp).Magnitude < 9000 and not (G.dayK and G.dayK() > 0.45)   -- 白天不开（昼夜更替，用户 11-25）
      if L.near ~= near then
        L.near = near
        for _, b in ipairs(L.beams) do b.Enabled = near end
      end
      if near and L.time ~= t then
        L.time = t
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

  -- 房子（模型属性 Bld）着火（属性 Burning）挂火焰、废墟（workspace.Ruins）冒烟。
  --   用户 11-25「游戏一阵一阵卡 然后枪 坦克 飞机一阵一阵抽搐」：原来每 15 秒把 Map.Scenery 整个 GetDescendants 一遍找房子——沙海的景物有四五万个实例，
  --   每 15 秒卡一下（tools/mock/hitch.lua 按行采样：尖峰那几帧三成多的时间在这里，平常的帧里一次都没有）；每秒还把每栋房子的属性读一遍。
  --   现在：开服后分帧扫一遍（只走文件夹和模型、不进零件，每帧 1500 个），以后靠 DescendantAdded 接新来的（开了 streaming 流进来的也是）；
  --   每栋房子盯着自己的 Burning 属性，变了才挂 / 撤火焰；废墟靠 ChildAdded
  local watched = setmetatable({}, { __mode = "k" })
  local function syncFire(m)
    local on = m.Parent ~= nil and m:GetAttribute("Burning") == true
    if on and not burning[m] then
      decorateFire(m)
    elseif not on and burning[m] then
      if burning[m].h.Parent then burning[m].h:Destroy() end
      burning[m] = nil
    end
  end
  local function watchBld(m)
    if watched[m] or not m:IsA("Model") or not m:GetAttribute("Bld") then return end
    watched[m] = true
    m:GetAttributeChangedSignal("Burning"):Connect(function() pcall(syncFire, m) end)
    if m:GetAttribute("Burning") == true then syncFire(m) end
  end
  G.bldWatched = function() local n = 0 for _ in pairs(watched) do n += 1 end return n end   -- 测试用
  local sceneryHooked, ruinsHooked = false, false
  local function hookScenery(scenery)
    sceneryHooked = true
    scenery.DescendantAdded:Connect(function(d)
      if d:IsA("Model") then task.defer(function() if d.Parent then pcall(watchBld, d) end end) end   -- 等属性到了再看
    end)
    task.spawn(function()
      local stack, n = { scenery }, 0
      while #stack > 0 do
        local node = table.remove(stack)
        if node.Parent then
          for _, c in ipairs(node:GetChildren()) do
            if c:IsA("Model") then
              if c:GetAttribute("Bld") then watchBld(c) else table.insert(stack, c) end
            elseif c:IsA("Folder") then
              table.insert(stack, c)
            end
            n += 1
            if n % 1500 == 0 then task.wait() end
          end
        end
      end
    end)
  end
  local function hookRuins(rf)
    ruinsHooked = true
    rf.ChildAdded:Connect(function(m)
      task.defer(function() if m.Parent and m:IsA("Model") and not ruinFx[m] then pcall(decorateRuin, m) end end)
    end)
    for _, m in ipairs(rf:GetChildren()) do
      if m:IsA("Model") and not ruinFx[m] then decorateRuin(m) end
    end
  end
  local function stepBlds()
    if not sceneryHooked then
      local map = workspace:FindFirstChild("Map")
      local scenery = map and map:FindFirstChild("Scenery")
      if scenery then hookScenery(scenery) end
    end
    if not ruinsHooked then
      local rf = workspace:FindFirstChild("Ruins")
      if rf then hookRuins(rf) end
    end
    for m in pairs(burning) do   -- 拆掉 / 流出去的房子
      if not m.Parent then
        if burning[m].h.Parent then burning[m].h:Destroy() end
        burning[m] = nil
      end
    end
    for m in pairs(ruinFx) do
      if not m.Parent then ruinFx[m] = nil end
    end
  end

  local function stepBurn()
    local cp = camPos()
    local t = os.clock()
    for _, b in pairs(burning) do
      if b.h.Parent and (b.h.CFrame.Position - cp).Magnitude < 1500 then
        local brightness = reducedMotion and 2.6 or (2.6 + 0.32 * math.sin(t * 3.1 + b.ph))
        if math.abs(b.light.Brightness - brightness) > 0.025 then b.light.Brightness = brightness end
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
    if d < 400 and G.shake and not reducedMotion then G.shake(0.55 * (1 - d / 400)) end
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

  ---------------------------------------------------------------- 暴风雨（服务器 Battle.lua 给强度：workspace 的属性 StormK）
  -- 雨：镜头上方一块看不见的板子往下撒细长的雨丝（顺着速度方向拉长；受光：照明弹、火光、探照灯附近的雨亮晶晶，黑处几乎看不见）；
  --   开飞机飞到云上面（700 格以上）不下。闪电保留远处的短光与雷声，减少动态效果时只保留雷声；
  --   云变厚变黑、海浪变大、风把草吹得乱晃、雾变近（DayNight.lua 读 G.weather.k）；雨声的「沙——」跟着强度
  local stormK = 0
  local rainPart, rainPE, rainSnd
  local rainActive, rainSoundOn = false, false
  local weatherAcc, lastLook = 0, 0
  local nextBolt = 0
  local bolts = 0
  G.boltCount = function() return bolts end   -- 测试用
  G.weather = { k = 0 }
  local stormCloud = RGB(40, 44, 54)
  local T0 = { cover = clouds and clouds.Cover or 0.6, dens = clouds and clouds.Density or 0.5, color = clouds and clouds.Color or RGB(66, 72, 88) }
  local terr = workspace:FindFirstChildOfClass("Terrain")
  local waterSize, waterSpeed, wind

  local function ensureRain()
    if rainPart then return end
    rainPart = part(Enum.PartType.Block, V(86, 1, 86), CFrame.new(0, -500, 0), RGB(0, 0, 0), nil, 1)
    rainPart.Name = "Rain"
    rainPE = emitter(rainPart, { tex = "rbxasset://textures/particles/SquareParticle.png", rate = 0, life = { 0.45, 0.6 }, spd = { 140, 175 }, spread = 6,
      dir = Enum.NormalId.Bottom, size = nseq(0, 0.07, 1, 0.07), tr = nseq(0, 0.45, 1, 0.55), col = cseq(RGB(206, 214, 228), RGB(190, 200, 216)), rot = 0 })
    rainPE.LightEmission, rainPE.LightInfluence = 0.15, 0.85
    rainPE.RotSpeed = NumberRange.new(0, 0)
    rainPE.Rotation = NumberRange.new(0, 0)
    pcall(function() rainPE.Orientation = Enum.ParticleOrientation.VelocityParallel end)
    pcall(function() rainPE.Squash = NumberSequence.new(3) end)   -- 拉成细长的雨丝
  end

  local function drawBolt(x, gy, z)
    local y = math.max(800, gy + 140)
    local pts = { V(x, y, z) }
    while y > gy + 1 do
      y = math.max(gy, y - (60 + math.random() * 70))
      local last = pts[#pts]
      table.insert(pts, V(last.X + (math.random() - 0.5) * 70, y, last.Z + (math.random() - 0.5) * 70))
    end
    local function seg(p0, p1, wdt)
      local L = (p1 - p0).Magnitude
      local s = part(Enum.PartType.Block, V(wdt, wdt, L), CFrame.lookAt((p0 + p1) / 2, p1), RGB(190, 207, 235), Enum.Material.Neon, 0.25)
      if G.tween then G.tween(s, 0.28, { Transparency = 1 }) end
      Debris:AddItem(s, 0.3)
    end
    for i = 1, #pts - 1 do seg(pts[i], pts[i + 1], 1.6) end
    local k0 = math.random(2, math.max(2, #pts - 2))   -- 分叉
    local bp = pts[k0]
    for i = 1, 3 do
      local nb = bp + V((math.random() - 0.5) * 120, -(50 + math.random() * 60), (math.random() - 0.5) * 120)
      seg(bp, nb, 0.9)
      bp = nb
    end
  end

  local function bolt(cp)
    local a = math.random() * 2 * math.pi
    local dist = 1200 + math.random() * 3800
    local x, z = cp.X + math.cos(a) * dist, cp.Z + math.sin(a) * dist
    local gy = math.max(0, MapM.ground(x, z))
    if not reducedMotion then drawBolt(x, gy, z) end
    local d = (V(x, gy, z) - cp).Magnitude
    if G.sfx then
      G.sfx({ { id = EXP, vol = 1.5, s = { 0.3, 0.36 }, reg = { 0, 2.5 }, eq = { 8, -2, -18 }, echo = { 0.5, 0.5, -6 } },
        { id = EXP, vol = 0.9, s = { 0.25, 0.28 }, reg = { 0, 2.5 }, eq = { 10, -4, -24 }, delay = 0.4 } },
        V(x, gy + 50, z), { delay = d / 960, rmin = 4000, rmax = 12000, must = true })
    end
    bolts += 1
  end

  local function stepRain(k, cp, look)
    if k > 0.01 then ensureRain() end
    if not rainPE then return end
    local active = k > 0.01 and cp.Y <= 700
    if active then
      local target = cp + V(look.X * 20, 38, look.Z * 20)
      if (rainPart.CFrame.Position - target).Magnitude >= 0.5 then rainPart.CFrame = CFrame.new(target) end
    elseif rainActive then
      pcall(function() rainPE:Clear() end)
    end
    rainActive = active
    local budget = G.mobile and 100 or 400
    if reducedMotion then budget = G.mobile and 68 or 120 end
    local rate = active and math.floor(budget * k * math.clamp(G.perfK or 1, 0.4, 1)) or 0
    if rainPE.Rate ~= rate then rainPE.Rate = rate end

    if active then
      if not rainSnd and G.makeSound then
        rainSnd = G.makeSound({ id = WIND, vol = 0.01, s = { 1.25, 1.3 }, loop = { 0.5, 9.5 }, eq = { -24, -4, 5 } }, game:GetService("SoundService"), {})
        rainSoundOn = rainSnd ~= nil
      end
      if rainSnd then
        local volume = k * 1.4
        if math.abs(rainSnd.Volume - volume) >= 0.015 then rainSnd.Volume = volume end
        if not rainSoundOn then rainSnd:Play() rainSoundOn = true end
      end
    elseif rainSoundOn then
      rainSnd:Stop()
      rainSoundOn = false
    end
  end

  local function setWeatherLook(k)
    if k == lastLook or (k > 0 and math.abs(k - lastLook) < 0.012) then return end
    if lastLook == 0 then
      if terr then waterSize, waterSpeed = terr.WaterWaveSize, terr.WaterWaveSpeed end
      pcall(function() wind = workspace.GlobalWind end)
    end
    lastLook = k
    if clouds then
      clouds.Cover = T0.cover + (0.9 - T0.cover) * k
      clouds.Density = T0.dens + (0.82 - T0.dens) * k
      clouds.Color = T0.color:Lerp(stormCloud, k)
    end
    if terr then
      terr.WaterWaveSize = waterSize + (0.55 - waterSize) * k
      terr.WaterWaveSpeed = waterSpeed + (18 - waterSpeed) * k
    end
    if wind then pcall(function() workspace.GlobalWind = wind:Lerp(V(20, 0, 10), k) end) end
  end

  local function stepStorm(dt)
    local target = workspace:GetAttribute("StormK")
    target = type(target) == "number" and math.clamp(target, 0, 1) or 0
    stormK += (target - stormK) * (1 - math.exp(-dt * 0.8))
    if math.abs(target - stormK) < 0.005 then stormK = target end
    G.weather.k = stormK
    local cam = workspace.CurrentCamera
    if cam and (stormK > 0 or rainActive) then
      local cf = cam.CFrame
      stepRain(stormK, cf.Position, cf.LookVector)
      if stormK > 0.4 and os.clock() >= nextBolt then
        nextBolt = os.clock() + (5 + math.random() * 9) / stormK
        bolt(cf.Position)
      end
    elseif rainActive then
      stepRain(0, V(), V())
    end
    weatherAcc += dt
    if weatherAcc >= 0.12 then
      weatherAcc %= 0.12
      setWeatherLook(stormK)
    end
  end

  ---------------------------------------------------------------- 阵亡镜头（服务器 Battle.lua 的 G.killcam 发来 killcam）
  -- 阵亡后短暂转向事件来源。减少动态效果、重新部署、主菜单和镜头切换均优先接管。
  local player = Players.LocalPlayer
  local kc = nil
  local kcN = 0
  G.killcamCount = function() return kcN end   -- 测试用
  G.killcamOn = function() return kc ~= nil end
  local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

  local function endKillcam()
    if not kc then return end
    local shot = kc
    kc = nil
    pcall(function() RunService:UnbindFromRenderStep("Killcam") end)
    if workspace.CurrentCamera == shot.cam then shot.cam.FieldOfView = shot.fov0 end
    for _, o in ipairs(shot.objs) do if o.Parent then o:Destroy() end end
  end
  G.killcamStop = endKillcam   -- 阵亡效果（DeathFx.lua）开始时先停掉

  local function stepKillcam()
    if not kc then return end
    local u = os.clock() - kc.t0
    local cam = workspace.CurrentCamera
    local character = player.Character
    local round = G.S and G.S.round
    if u > 3.2 or reducedMotion or cam ~= kc.cam or (character and character ~= kc.character)
      or (kc.round and round and kc.round ~= round) or (G.menuShown and G.menuShown()) then
      endKillcam()
      return
    end
    local angle = smooth(u / 0.85)
    cam.CFrame = kc.fromView:Lerp(kc.focusView, angle)
    cam.FieldOfView = kc.fov0 + (kc.fovZ - kc.fov0) * smooth((u - 0.45) / 1.1)
  end

  local function startKillcam(e)
    if reducedMotion or (G.menuShown and G.menuShown()) or type(e) ~= "table" or typeof(e.p) ~= "Vector3" then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local from = (typeof(e.from) == "Vector3") and e.from or cam.CFrame.Position
    local d = (e.p - from).Magnitude
    if d < 3 or d > 2500 then return end
    endKillcam()
    kcN += 1
    -- 视野收到凶手周围约 14 格（远的拉得多），最窄 8°
    local fov = cam.FieldOfView
    local fovZ = math.clamp(math.deg(2 * math.atan(14 / d)), math.min(8, fov), fov)
    local eye = from + V(0, 0.4, 0)
    kc = { t0 = os.clock(), cam = cam, character = player.Character, round = G.S and G.S.round,
      fromView = CFrame.new(eye) * cam.CFrame.Rotation, focusView = CFrame.lookAt(eye, e.p),
      fov0 = fov, fovZ = fovZ, objs = {} }
    -- 凶手头顶的标记
    local anchor = part(Enum.PartType.Block, V(0.2, 0.2, 0.2), CFrame.new(e.p + V(0, 4.5, 0)), RGB(0, 0, 0), nil, 1)
    anchor.Name = "KillcamTag"
    table.insert(kc.objs, anchor)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(240, 64)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Adornee = anchor
    bb.Parent = anchor
    local mark = Instance.new("Frame")
    mark.Size = UDim2.fromOffset(16, 16)
    mark.AnchorPoint = Vector2.new(0.5, 0.5)
    mark.Position = UDim2.new(0.5, 0, 1, -10)
    mark.Rotation = 45
    mark.BackgroundColor3 = RGB(230, 52, 46)
    mark.BorderSizePixel = 0
    mark.Parent = bb
    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(1, 0, 0, 36)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.BuilderSansBold
    lab.TextSize = 18
    lab.TextColor3 = RGB(255, 236, 232)
    lab.TextStrokeTransparency = 0.4
    lab.Text = string.format("%s  ·  %d m", tostring(e.name or "?"), math.floor(d / 2.8 + 0.5))
    lab.Parent = bb
    -- 真人：一圈红色描边
    if type(e.uid) == "number" then
      local pl = Players:GetPlayerByUserId(e.uid)
      local ch = pl and pl.Character
      if ch then
        local hl = Instance.new("Highlight")
        hl.FillColor, hl.OutlineColor = RGB(230, 52, 46), RGB(255, 90, 80)
        hl.FillTransparency, hl.OutlineTransparency = 0.8, 0
        hl.Adornee = ch
        hl.Parent = ch
        table.insert(kc.objs, hl)
      end
    end
    -- 去色 + 景深（对准凶手）
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "KillcamGrade"
    cc.Saturation, cc.Contrast, cc.TintColor = -0.55, 0.12, RGB(255, 228, 222)
    cc.Parent = Lighting
    table.insert(kc.objs, cc)
    pcall(function()
      local dof = Instance.new("DepthOfFieldEffect")
      dof.Name = "KillcamFocus"
      dof.FocusDistance, dof.InFocusRadius, dof.FarIntensity, dof.NearIntensity = d, math.max(8, d * 0.15), 0.55, 0.75
      dof.Parent = Lighting
      table.insert(kc.objs, dof)
    end)
    RunService:BindToRenderStep("Killcam", Enum.RenderPriority.Camera.Value + 20, function()
      local ok, err = pcall(stepKillcam)
      if not ok then
        endKillcam()
        if G.showError then G.showError("阵亡镜头：" .. tostring(err)) end
      end
    end)
  end
  local prevMsg = G.onMsg
  G.onMsg = function(kind, key, ...)
    if kind == "killcam" then
      local ok, err = pcall(startKillcam, key)
      if not ok then
        endKillcam()
        if G.showError then G.showError("阵亡镜头：" .. tostring(err)) end
      end
      return
    end
    if prevMsg then return prevMsg(kind, key, ...) end
  end

  local acc, bAcc = 0, 0
  G.frameConn("Warfx", function(dt)
    local okS, errS = pcall(stepStorm, dt or 1 / 60)
    if not okS and G.showError then G.showError("暴风雨：" .. tostring(errS)) end
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
        if clouds then
          local enabled = (G.perfK or 1) >= 0.7
          if clouds.Enabled ~= enabled then clouds.Enabled = enabled end
        end
      end)
      if not ok2 and G.showError then G.showError("战场氛围：" .. tostring(err2)) end
    end
    if tintLo then pcall(drainTint) end
    if fading then pcall(stepFading, dt) end
    bAcc += dt or 1 / 60
    if bAcc >= 1 then   -- 房子着火、废墟、云的颜色：一秒查一次
      bAcc = 0
      pcall(stepCloudTint)
      local ok3, err3 = pcall(stepBlds)
      if not ok3 and G.showError then G.showError("房子：" .. tostring(err3)) end
    end
  end)
end

return Warfx
