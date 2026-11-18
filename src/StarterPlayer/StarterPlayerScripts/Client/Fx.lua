-- Roblox全面大战场（客户端）——特效与音效：曳光、枪口火光、飞行中的火箭弹 / 导弹 / 手雷（照服务器给的初速本地算弹道）、炮弹落下的呼啸、爆炸、溅水、
--   治疗光圈、修车火花、据点易手、被标记的敌人（头顶红菱形 + 地图红点）、震屏；音效用 Roblox 自带的声音变调（不用上传素材）
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Fx = {}

function Fx.init(G)
  local Config = G.Config
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
  local me = Players.LocalPlayer
  local AD = require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs"))
  local WM = require(game:GetService("ReplicatedStorage"):WaitForChild("WeaponModels"))
  local MapM = require(game:GetService("ReplicatedStorage"):WaitForChild("Map"))

  local FXF = Instance.new("Folder")
  FXF.Name = "ClientFx"
  FXF.Parent = workspace
  G.fxFolder = FXF

  local function part(shape, size, cf, color, mat, tr)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Size, p.CFrame, p.Color = size, cf, color
    p.Material = mat or Enum.Material.Neon
    p.Transparency = tr or 0
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = FXF
    return p
  end
  G.fxPart = part
  local function tween(o, t, props, style)
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
  end
  -- 夜战：一闪的光（枪口焰、炮口、爆炸）——看不见的锚定小零件挂一个点光源，亮度很快降到 0（Future 光照下会照亮四周的地面、墙、车）
  -- 一卡一卡（用户 11-18）：夜里每声枪响、每次爆炸都点一盏，同时亮着的太多（尤其投影子的）显卡一顿一顿——
  --   同时最多 10 盏、投影子的最多 2 盏，离镜头太远（光照范围外再 400 格）的不点
  local liveFlash, liveShadow = 0, 0
  local function flash(p, color, range, bright, t)
    local cam = workspace.CurrentCamera
    if cam and (cam.CFrame.Position - p).Magnitude > range + 400 then return nil end
    if liveFlash >= 10 then return nil end
    local shadows = range > 20 and liveShadow < 2
    local h = part(nil, V(0.2, 0.2, 0.2), CFrame.new(p), color, Enum.Material.SmoothPlastic, 1)
    local pl = Instance.new("PointLight")
    pl.Color, pl.Range, pl.Brightness, pl.Shadows = color, range, bright, shadows
    pl.Parent = h
    tween(pl, t, { Brightness = 0 })
    Debris:AddItem(h, t + 0.05)
    liveFlash += 1
    if shadows then liveShadow += 1 end
    task.delay(t + 0.05, function()
      liveFlash -= 1
      if shadows then liveShadow -= 1 end
    end)
    return pl
  end
  G.flash = flash
  -- 跟着一个零件走的光（导弹尾焰、热诱弹）
  local function glowOn(p, color, range, bright)
    local pl = Instance.new("PointLight")
    pl.Color, pl.Range, pl.Brightness, pl.Shadows = color, range, bright, false
    pl.Parent = p
    return pl
  end
  G.tween = tween

  ---------------------------------------------------------------- 音效

  local EXP = "rbxasset://sounds/impact_explosion_03.mp3"
  local TICK = "rbxasset://sounds/volume_slider.ogg"
  local SND = {
    boom = { EXP, 0.9, 0.8, 1.0 }, rocket = { EXP, 0.35, 1.7, 2.0 }, rifle = { EXP, 0.16, 2.9, 3.3 }, lmg = { EXP, 0.18, 2.7, 3.0 },
    sniper = { EXP, 0.4, 1.9, 2.1 }, pistol = { EXP, 0.14, 3.3, 3.6 }, quiet = { TICK, 0.25, 0.7, 0.8 }, mortar = { EXP, 0.4, 1.2, 1.4 },
    hit = { TICK, 0.5, 2.5, 2.7 }, killding = { TICK, 0.7, 1.7, 1.8 }, heal = { TICK, 0.5, 1.6, 1.7 }, capture = { TICK, 0.9, 1.3, 1.3 },
    hurt = { "rbxasset://sounds/ouch.ogg", 0.45, 1, 1.1 }, splash = { "rbxasset://sounds/action_jump_land.mp3", 0.6, 0.5, 0.6 },
  }
  local soundT, soundN = 0, 0
  function G.playSound(name, pos, speed)
    local def = SND[name]
    if not def then return end
    local t = os.clock()
    if t - soundT > 0.1 then soundT, soundN = t, 0 end
    soundN += 1
    if soundN > 8 then return end
    if pos and (pos - cam.CFrame.Position).Magnitude > 1800 then return end
    local snd = Instance.new("Sound")
    snd.SoundId = def[1]
    snd.Volume = def[2]
    snd.PlaybackSpeed = speed or (def[3] + (def[4] - def[3]) * math.random())
    snd.RollOffMinDistance = 30
    snd.RollOffMaxDistance = 1600
    if pos then
      local p = part(nil, V(0.2, 0.2, 0.2), CFrame.new(pos), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
      snd.Parent = p
      snd:Play()
      Debris:AddItem(p, 5)
    else
      snd.Parent = SoundService
      snd:Play()
      Debris:AddItem(snd, 5)
    end
  end

  ---------------------------------------------------------------- 自动画质（用户：太卡了优化不到位、视野很短）
  -- 按实际帧率调「画多远、画多细」：每两秒算一次平均帧率，连着两次低于 40 帧就往下降一档（树林 Scenery、士兵 Soldier、爆炸粒子都乘 G.perfK），
  --   高于 57 帧慢慢升回去，最高 1.2（机器好的树林画得更远）。G.perfFixed 为真时不调（模拟测试）
  G.perfK, G.frameRate = 1, 60   -- 帧率别叫 G.fps：那是 FPSView 的第一人称视图模型
  do
    local acc, n, low = 0, 0, 0
    RunService.RenderStepped:Connect(function(dt)
      acc += dt
      n += 1
      if acc < 2 then return end
      local fps = n / acc
      acc, n = 0, 0
      G.frameRate = fps
      if G.perfFixed then return end
      local k = G.perfK
      if fps < 40 then
        low += 1
        if low >= 2 then k = math.max(0.55, k - ((fps < 28) and 0.15 or 0.08)) end
      else
        low = 0
        if fps > 57 then k = math.min(1.2, k + 0.04) end
      end
      G.perfK = math.floor(k * 100 + 0.5) / 100
    end)
  end

  ---------------------------------------------------------------- 武器音效：几层叠起来（Roblox 自带的声音只有十来个：爆炸、风、水、咔哒……
  --   content/sounds 里就这些，不用上传素材）——截一段、循环一小段、变速、加效果（失真、均衡、回声）做出不同武器的声音：
  --   航炮：循环爆炸声起爆的那一小段，一圈正好一发（射速快的连成「嗡——」，链式炮一下一下的）；火箭弹：短促的「噗」+ 呼的一下；
  --   导弹：低沉的点火声 + 跟着弹飞走的发动机呼啸（风声加失真）；炸弹：挂架弹开「咣」一声；爆炸按大小分（远处的晚一点到、高音被吃掉）
  local WIND = "rbxasset://sounds/action_falling.ogg"
  local THUD = "rbxasset://sounds/action_jump_land.mp3"
  local WATER = "rbxasset://sounds/impact_water.mp3"
  local LEN = { [EXP] = 2.59, [WIND] = 10, [TICK] = 0.85, [THUD] = 0.27, [WATER] = 2.38 }
  local SFX = {
    -- 每层：id 采样、vol 音量、s 速度范围、reg 截取（采样里的秒）、loop 循环区间、eq {低, 中, 高} 分贝、dist 失真、echo {延迟, 反馈, 湿声分贝}、
    --   delay 晚几秒、fade 最后几秒淡出
    rkt = { { id = EXP, vol = 0.5, s = { 1.25, 1.4 }, reg = { 0.04, 0.34 }, eq = { 3, 0, -4 } },
      { id = WIND, vol = 10, s = { 1.7, 1.9 }, reg = { 2, 3.5 }, eq = { 0, 10, 3 }, fade = 0.4 } },
    msl = { { id = EXP, vol = 0.65, s = { 0.78, 0.86 }, reg = { 0.04, 1.2 }, eq = { 6, 0, -5 } },
      { id = WIND, vol = 10, s = { 1.05, 1.15 }, reg = { 3, 5.2 }, eq = { 4, 10, 0 }, dist = 0.5, fade = 0.8 } },
    bombRel = { { id = TICK, vol = 1, s = { 0.3, 0.34 } }, { id = THUD, vol = 0.8, s = { 0.5, 0.56 } } },
    -- 子弹从耳边飞过：一下尖的「嗖」（风声截短、拉快、削掉低音）+ 一声脆响
    whiz = { { id = WIND, vol = 7, s = { 2.6, 3.3 }, reg = { 2.1, 2.45 }, eq = { -12, 4, 8 } }, { id = TICK, vol = 0.45, s = { 3.6, 4.2 } } },
    -- 音爆（AirFx.lua）：N 形波的头尾两声连着的低沉「嘭——嘭」，放慢、失真、削掉高音；远处的人按距离晚到
    sonic = { { id = EXP, vol = 1.2, s = { 0.5, 0.55 }, reg = { 0, 1.7 }, eq = { 10, 0, -16 }, dist = 0.55 },
      { id = EXP, vol = 1, s = { 0.47, 0.5 }, reg = { 0, 1.5 }, eq = { 10, -2, -18 }, dist = 0.55, delay = 0.14 } },
    -- 爽感（Juice.lua）：爆头——打在头盔上的一声脆「叮」；连杀——往上走的三声；低血量——一下一下的心跳
    headshot = { { id = TICK, vol = 1, s = { 3.3, 3.4 }, eq = { -10, 2, 6 } }, { id = TICK, vol = 0.7, s = { 4.7, 4.8 }, eq = { -10, 0, 8 }, delay = 0.035 } },
    streak = { { id = TICK, vol = 0.8, s = { 1.6, 1.6 } }, { id = TICK, vol = 0.8, s = { 2.0, 2.0 }, delay = 0.09 }, { id = TICK, vol = 0.9, s = { 2.5, 2.5 }, delay = 0.18 },
      { id = EXP, vol = 0.25, s = { 1.6, 1.7 }, reg = { 0.02, 0.3 }, eq = { 6, 0, -8 } } },
    heart = { { id = THUD, vol = 1.6, s = { 0.5, 0.52 }, eq = { 10, -4, -24 } }, { id = THUD, vol = 1.1, s = { 0.47, 0.49 }, eq = { 10, -4, -24 }, delay = 0.24 } },
  }
  -- 导弹飞行中的发动机声：挂在弹上跟着飞走（燃烧完就停）
  local ROAR = { id = WIND, vol = 10, s = { 0.95, 1.05 }, loop = { 0.5, 9.5 }, eq = { 6, 10, -1 }, dist = 0.55 }

  local function makeSound(L, parent, o)
    local snd = Instance.new("Sound")
    snd.SoundId = L.id
    snd.Volume = math.min(10, L.vol * (o.vol or 1))
    local sp = (L.s[1] + (L.s[2] - L.s[1]) * math.random()) * (o.speed or 1)
    snd.PlaybackSpeed = sp
    snd.RollOffMinDistance = o.rmin or 40
    snd.RollOffMaxDistance = o.rmax or 1800
    if L.reg or L.loop then
      snd.PlaybackRegionsEnabled = true
      if L.reg then snd.PlaybackRegion = NumberRange.new(L.reg[1], L.reg[2]) end
      if L.loop then
        snd.Looped = true
        snd.LoopRegion = NumberRange.new(L.loop[1], L.loop[2])
      end
    end
    local hi = (L.eq and L.eq[3] or 0) + (o.hiCut or 0)
    if L.eq or hi ~= 0 then
      local e = Instance.new("EqualizerSoundEffect")
      e.LowGain, e.MidGain, e.HighGain = L.eq and L.eq[1] or 0, L.eq and L.eq[2] or 0, math.max(-80, hi)
      e.Parent = snd
    end
    if L.dist then
      local e = Instance.new("DistortionSoundEffect")
      e.Level = L.dist
      e.Parent = snd
    end
    if L.echo then
      local e = Instance.new("EchoSoundEffect")
      e.Delay, e.Feedback, e.WetLevel, e.DryLevel = L.echo[1], L.echo[2], L.echo[3], 0
      e.Parent = snd
    end
    snd.Parent = parent
    snd:Play()
    local len = L.loop and math.huge or ((L.reg and (L.reg[2] - L.reg[1]) or LEN[L.id] or 3) / sp + (L.echo and L.echo[1] * 8 or 0))
    if L.fade and len < math.huge then
      task.delay(math.max(0, len - L.fade), function() if snd.Parent then tween(snd, L.fade, { Volume = 0 }, Enum.EasingStyle.Linear) end end)
    end
    return snd, len
  end
  G.makeSound = makeSound

  -- 放一个叠层的声音：def 是 SFX 的名字或层表；pos 是世界坐标（nil：耳边）；o：vol 音量倍数、speed、delay 晚几秒、hiCut 高音衰减、rmax 传多远
  local sfxT, sfxN = 0, 0
  function G.sfx(def, pos, o)
    if type(def) == "string" then def = SFX[def] end
    if not def then return end
    o = o or {}
    local t = os.clock()
    if t - sfxT > 0.1 then sfxT, sfxN = t, 0 end
    if sfxN >= 10 and not o.must then return end
    sfxN += 1
    local function go()
      local holder = pos and part(nil, V(0.2, 0.2, 0.2), CFrame.new(pos), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1) or nil
      local longest = 0
      for _, L in ipairs(def) do
        local function one()
          local snd, len = makeSound(L, holder or SoundService, o)
          if not holder then Debris:AddItem(snd, len + 0.3) end
        end
        if L.delay then task.delay(L.delay, one) else one() end
        local sp = (L.s[1] + L.s[2]) / 2 * (o.speed or 1)
        longest = math.max(longest, (L.delay or 0) + (L.reg and (L.reg[2] - L.reg[1]) or LEN[L.id] or 3) / sp + (L.echo and L.echo[1] * 8 or 0))
      end
      if holder then Debris:AddItem(holder, longest + 0.5) end
    end
    if o.delay and o.delay > 0.03 then task.delay(o.delay, go) else go() end
  end

  -- 航炮：每架开火的飞机一个循环声（自己开的在耳边，别人的在炮口那里）；循环的是爆炸声起爆那一小段，一圈 = 一发（射速）
  local guns = {}
  local function gunLayer(w)
    local per = w.rate or 0.05
    local sp = math.clamp(0.05 / per, 0.9, 2.6)   -- 射速快的放快一点：一圈里能装下起爆的那一下（M61 尖、GAU-8 粗、链式炮一下一下）
    local a = 0.044   -- 采样里起爆前一点点
    return { id = EXP, vol = 1, s = { sp, sp }, loop = { a, a + per * sp }, eq = { (per > 0.03) and 7 or 4, 0, (per < 0.02) and 2 or -3 } }
  end
  function G.gunLoop(key, gid, p, on)
    local g = guns[key]
    if g and (not on or g.gid ~= gid) then
      g.snd:Destroy()
      if g.holder then g.holder:Destroy() end
      guns[key], g = nil, nil
    end
    if not on then return end
    local w = AD.W[gid or ""]
    if not w then return end
    if not g then
      local holder = p and part(nil, V(0.2, 0.2, 0.2), CFrame.new(p), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1) or nil
      local snd = makeSound(gunLayer(w), holder or SoundService, { vol = holder and 0.9 or 0.42, rmin = 60, rmax = 3000 })
      g = { snd = snd, holder = holder, gid = gid }
      guns[key] = g
    elseif p and g.holder then
      g.holder.CFrame = CFrame.new(p)
    end
    g.till = (key == "me") and math.huge or (os.clock() + 0.25)   -- 别人的：0.25 秒没再收到炮弹就停（服务器每 0.1 秒发一发）
  end
  local function stepGuns()
    local t = os.clock()
    for k, g in pairs(guns) do
      if t > g.till then G.gunLoop(k, nil, nil, false) end
    end
  end

  -- 震屏
  local trauma = 0
  function G.shake(a) trauma = math.min(1, trauma + a) end
  pcall(function()
    RunService:BindToRenderStep("IAShake", Enum.RenderPriority.Last.Value, function(dt)
      if trauma <= 0.002 then return end
      local s = trauma * trauma
      local t = os.clock() * 26
      cam.CFrame = cam.CFrame * CFrame.Angles(math.noise(t, 1.7) * 0.05 * s, math.noise(t, 5.3) * 0.05 * s, math.noise(t, 9.1) * 0.03 * s)
      trauma = math.max(0, trauma - dt * 1.6)
    end)
  end)
  -- 开枪的后坐：视线往上一跳（用户：后坐稍微调低一点——比原来小三成）
  function G.kick(w)
    local k = (w.dmg or 20) / 860
    cam.CFrame = cam.CFrame * CFrame.Angles(k * (0.6 + math.random() * 0.4), (math.random() - 0.5) * k * 0.6, 0)
  end

  ---------------------------------------------------------------- 曳光、枪口火光

  local TRACER = { m4 = RGB(255, 220, 140), rifle = RGB(255, 220, 140), lmg = RGB(255, 190, 110), sniper = RGB(255, 245, 210) }
  -- 一卡一卡（用户 11-18）：几十个机器人一起开枪，每一发都新建曳光、枪口火、灯光、弹着点的灰——一秒几百个零件加补间。
  --   别人打的：枪口离镜头 900 格外、弹道也没从镜头 300 格内擦过的不画；350 格外的只画曳光（不点灯、没有枪口火球和弹着灰）；
  --   画全套的每秒最多 50 发（多出来的也只画曳光）。自己打的照旧全画
  local gunTok, gunTokT = 50, 0
  function G.gunFx(id, a, b, mine)
    local d = b - a
    local L = d.Magnitude
    if L < 0.5 then return end
    local lite = false
    if not mine then
      local c = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or a
      local da = (a - c).Magnitude
      if da > 350 then
        local u = math.clamp((c - a):Dot(d) / (L * L), 0, 1)
        if da > 900 and (a + d * u - c).Magnitude > 300 then return end
        lite = true
      end
      local now = os.clock()
      gunTok = math.min(50, gunTok + (now - gunTokT) * 50)
      gunTokT = now
      if not lite then
        if gunTok >= 1 then gunTok -= 1 else lite = true end
      end
    end
    local col = TRACER[id] or RGB(255, 220, 140)
    local len = math.min(L, 14)
    local tr = part(nil, V(0.12, 0.12, len), CFrame.lookAt(a + d.Unit * len / 2, b), col, Enum.Material.Neon, 0.1)
    local speed = 900
    local tw = tween(tr, L / speed, { CFrame = CFrame.lookAt(b - d.Unit * len / 2, b + d.Unit) }, Enum.EasingStyle.Linear)
    Debris:AddItem(tr, L / speed + 0.05)
    if not lite then
      local fl = part(BALL, V(0.9, 0.9, 0.9), CFrame.new(a), RGB(255, 210, 120), Enum.Material.Neon, 0.2)
      tween(fl, 0.06, { Transparency = 1, Size = V(1.4, 1.4, 1.4) })
      Debris:AddItem(fl, 0.08)
      if id ~= "smgsd" then flash(a, RGB(255, 196, 120), 14, 3.2, 0.07) end   -- 枪口焰照亮四周（消音的没有）
      -- 弹着点一小团灰
      task.delay(L / speed, function()
        local puff = part(BALL, V(0.8, 0.8, 0.8), CFrame.new(b), RGB(180, 170, 150), Enum.Material.SmoothPlastic, 0.3)
        tween(puff, 0.4, { Size = V(2.2, 2.2, 2.2), Transparency = 1 })
        Debris:AddItem(puff, 0.45)
      end)
    end
    local snd = (id == "smgsd") and "quiet" or ((id == "sniper" or id == "lmg" or id == "pistol") and id or "rifle")
    G.playSound(snd, a)
  end

  ---------------------------------------------------------------- 爆炸
  --   按武器分（服务器 G.explode 给类别 c）：gun 航炮 / 小口径炮弹、nade 手雷 / 炸药、shell 炮弹 / 地雷、rkt 火箭弹、msl 导弹、bomb 炸弹、
  --   flak 高炮空炸、wreck 车 / 飞机 / 舰被击毁；没给的按大小猜。全用粒子（Roblox 自带的爆炸贴图）：白热闪光、翻卷的火球、地上冲起的尘土柱、
  --   乱飞的碎块和火星、贴地冲击波圈和一圈扬尘、往上飘的烟柱（炸弹的飘十来秒），大的还留一会儿余火；海面上是白色水柱和水雾；
  --   半空炸是一团火 + 一团黑烟。用户：导弹、炮弹爆炸效果都很小，要按不同武器改
  local TX = {
    core = "rbxasset://textures/particles/explosion01_core_main.dds",       -- 火球（橙色、翻卷）
    ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",  -- 冲击波圈
    glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",  -- 白热的一团（闪光、火星）
    fire = "rbxasset://textures/particles/fire_main.dds",
    smoke = "rbxasset://textures/particles/smoke_main.dds",
    chunk = "rbxasset://textures/particles/SquareParticle.png",
  }
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local function nseq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = NSK(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  local function cseq(a, b) return ColorSequence.new({ CSK(0, a), CSK(1, b) }) end
  -- 一组粒子：n 个，tex 贴图、life / spd 范围、size / tr 序列、col 颜色、acc 加速度、drag 阻力、le 自发光、dir 方向、spread 散开角、
  --   flat 平躺（冲击波圈）、radial 沿地面一圈往外（零件绕竖轴转着发，发射方向跟着零件转）、rate 持续冒（余火）
  local function burst(h, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex
    pe.Rate = 0
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
    pe.RotSpeed = NumberRange.new(-(o.rot or 40), o.rot or 40)
    pe.ZOffset = o.z or 0
    pe.EmissionDirection = o.dir or Enum.NormalId.Top
    if o.flat then pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
    pe.Parent = h
    if o.rate then
      pe.Rate = o.rate
    elseif o.radial then
      local base = h.CFrame
      for i = 1, o.n do
        h.CFrame = base * CFrame.Angles(0, (i + math.random() * 0.6) * 2 * math.pi / o.n, 0)
        pe:Emit(1)
      end
      h.CFrame = base
    else
      pe:Emit(o.n)
    end
    return pe
  end

  -- 爆炸声按大小：小的脆，大的低沉、带回声，炸弹再叠一层滚雷似的闷响；水里的加一声哗；远处的晚一点到（声速）、高音被吃掉
  local function boomSound(p, r, c, d, water)
    if c == "gun" and d > 900 then return end
    local L
    if c == "gun" then L = { { id = EXP, vol = 0.32, s = { 1.6, 1.9 }, reg = { 0.04, 0.55 } } }
    elseif r < 9 or c == "nade" then L = { { id = EXP, vol = 0.75, s = { 1.12, 1.28 } } }
    elseif r < 18 then L = { { id = EXP, vol = 0.95, s = { 0.92, 1.02 }, echo = { 0.2, 0.22, -10 } } }
    elseif c ~= "bomb" and r < 28 then L = { { id = EXP, vol = 1.15, s = { 0.76, 0.84 }, eq = { 4, 0, -2 }, echo = { 0.26, 0.28, -8 } } }
    else
      L = { { id = EXP, vol = 1.4, s = { 0.58, 0.64 }, eq = { 8, 0, -4 }, echo = { 0.32, 0.35, -6 } },
        { id = EXP, vol = 0.9, s = { 0.4, 0.44 }, eq = { 10, -6, -14 }, delay = 0.1 } }
    end
    if water then L = { L[1], { id = WATER, vol = 0.9, s = { 0.62, 0.72 }, delay = 0.06 } } end
    local far = math.clamp((d - 300) / 2500, 0, 1)
    G.sfx(L, p, { delay = math.max(0, d - 250) / 960, hiCut = -16 * far, rmin = 40 + r * 6, rmax = (c == "bomb") and 9000 or 4500, must = r >= 18 })
  end

  local KF = { nade = 0.5, shell = 0.75, rkt = 0.8, msl = 0.9, bomb = 1, flak = 0.6, wreck = 0.8 }   -- 火球半径 / 杀伤半径
  local RMIN = { shell = 5, rkt = 6, msl = 9, bomb = 24, wreck = 10 }
  local boomT, boomN = 0, 0
  local function boom(p, s, c)
    s = s or 1
    local r = 12 * s   -- 杀伤半径（格）
    if not c then c = (r < 5 and "gun") or (r < 13 and "shell") or (r < 26 and "msl") or "bomb" end
    local d = (p - cam.CFrame.Position).Magnitude
    local gy = MapM.height(p.X, p.Z)
    local water = gy < 0.3 and p.Y < 5
    local surf = water and 0 or math.max(gy, 0)
    local air = c == "flak" or (p.Y - surf) > math.max(6, r * 0.6)
    boomSound(p, r, c, d, water and not air)
    if d > ((c == "gun") and 1600 or ((c == "bomb" or c == "wreck") and 9000 or 5000)) then return end
    if c ~= "gun" then   -- 离得近震一下
      local shR = r * 12 + 60
      if d < shR then G.shake(math.clamp(r / 32, 0.12, 0.85) * (1 - d / shR)) end
    end
    local t = os.clock()
    if t - boomT > 0.25 then boomT, boomN = t, 0 end
    boomN += 1
    local lod = (d > 2500 or boomN > 6 or (G.perfK or 1) < 0.8) and 0.5 or 1   -- 远的、同一时刻扎堆的（集束、齐射）、机器跟不上的少画一半
    local function n(x) return math.max(1, math.floor(x * lod + 0.5)) end
    local h = part(nil, V(1, 1, 1), CFrame.new(p), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local keep = 2.5

    if c == "gun" then   -- 航炮、小口径炮弹：一点火光、几颗火星、一小团土（水里一小柱水）
      burst(h, { tex = TX.glow, n = 1, life = { 0.07, 0.1 }, spd = { 0, 0 }, size = nseq(0, r * 0.9, 1, r * 1.4), tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 236, 190), RGB(255, 180, 100)), le = 1, z = 2 })
      burst(h, { tex = TX.glow, n = n(5), life = { 0.25, 0.5 }, spd = { 18, 50 }, spread = 70, acc = V(0, -90, 0), size = nseq(0, 0.5, 1, 0), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 230, 160), RGB(255, 150, 60)), le = 1 })
      local col = water and RGB(236, 242, 246) or RGB(142, 124, 100)
      burst(h, { tex = TX.smoke, n = n(3), life = { 0.8, 1.4 }, spd = { r * 1.2, r * 2.6 }, spread = water and 12 or 35, acc = V(0, water and -40 or -10, 0), drag = 2,
        size = nseq(0, r * 0.5, 1, r * 1.6), tr = nseq(0, 0.2, 1, 1), col = cseq(col, col) })
      if d < 500 then flash(p + V(0, 2, 0), RGB(255, 190, 110), 12, 3, 0.12) end
      Debris:AddItem(h, 1.6)
      return
    end

    local R = math.max(r * (KF[c] or 0.8), RMIN[c] or 3)   -- 火球半径
    if water and not air then R = R * 0.6 end              -- 水里炸：火小、水柱大
    -- 白热闪光 + 照亮四周
    burst(h, { tex = TX.glow, n = 1, life = { 0.12, 0.18 }, spd = { 0, 0 }, size = nseq(0, R * 2.4, 1, R * 3.4), tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 244, 220), RGB(255, 196, 130)), le = 1, z = 3 })
    flash(p + V(0, R * 0.5, 0), RGB(255, 170, 90), math.min(60, 14 + R * 2.5), 8 + R / 4, 0.3 + R / 45)
    -- 翻卷的火球：往外冲一下就被空气挡住、热气往上升
    burst(h, { tex = TX.core, n = n(6 + R / 3), life = { 0.45, 0.85 + R / 50 }, spd = { R * 0.8, R * 2.2 }, drag = 5, acc = V(0, R * 1.2, 0),
      size = nseq(0, R * 0.9, 0.25, R * 1.6, 1, R * 2.1), tr = nseq(0, 0.05, 0.5, 0.35, 1, 1), col = cseq(RGB(255, 236, 200), RGB(150, 70, 30)), le = 0.85, rot = 90, z = 1 })
    -- 火星
    burst(h, { tex = TX.glow, n = n(6 + r / 2), life = { 0.4, 1 }, spd = { r * 2, r * 4.5 + 20 }, spread = air and 180 or 70, acc = V(0, -90, 0), drag = 0.8,
      size = nseq(0, 0.6 + r / 40, 1, 0), tr = nseq(0, 0, 1, 0.4), col = cseq(RGB(255, 230, 160), RGB(255, 140, 60)), le = 1 })

    local smokeT = (c == "bomb") and 9 or ((c == "msl" or c == "wreck") and 6 or 3.5)
    if air then
      -- 半空炸：一团黑烟（高炮的就是这一团），慢慢散开
      burst(h, { tex = TX.smoke, n = n(4 + r / 4), life = { smokeT * 0.5, smokeT * 0.8 }, spd = { r * 0.3, r * 0.8 }, drag = 2, acc = V(1, 1.5, 0.6),
        size = nseq(0, r * 0.5, 0.3, r * 1.3, 1, r * 1.9), tr = nseq(0, 1, 0.06, 0.15, 0.6, 0.4, 1, 1), col = cseq(RGB(42, 40, 38), RGB(96, 94, 92)), rot = 15 })
      keep = smokeT
    elseif water then
      -- 海面：白色水柱 + 一圈水雾 + 平躺的一圈白沫
      local wcol = RGB(238, 244, 248)
      burst(h, { tex = TX.smoke, n = n(10 + r / 2), life = { 1.3, 2.2 + r / 40 }, spd = { r * 2, r * 4.2 }, spread = 12, acc = V(0, -r * 3, 0), drag = 0.6,
        size = nseq(0, r * 0.3, 0.35, r * 0.85, 1, r * 1.4), tr = nseq(0, 0.05, 0.6, 0.3, 1, 1), col = cseq(wcol, RGB(214, 226, 232)), rot = 25 })
      burst(h, { tex = TX.smoke, n = n(8 + r / 3), radial = true, dir = Enum.NormalId.Front, spread = 10, life = { 1, 1.8 }, spd = { r * 1.2, r * 2.4 }, drag = 1.6,
        size = nseq(0, r * 0.35, 1, r * 1.3), tr = nseq(0, 0.25, 1, 1), col = cseq(wcol, wcol) })
      h.CFrame = CFrame.new(p.X, 0.6, p.Z)
      burst(h, { tex = TX.ring, n = 1, life = { 2.2, 2.8 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = nseq(0, r * 0.5, 1, r * 3.5), tr = nseq(0, 0.2, 1, 1), col = cseq(wcol, wcol) })
      keep = 3
    else
      -- 地上：冲起的尘土柱（车、飞机被打爆没有）、乱飞的碎块、贴地冲击波圈和一圈扬尘、往上飘的烟柱
      local soil = RGB(116, 98, 74)
      if c ~= "wreck" then
        burst(h, { tex = TX.smoke, n = n(8 + r / 2), life = { 1.2, 2.2 + r / 40 }, spd = { r * 1.4, r * ((c == "bomb") and 4 or 3.2) }, spread = 22, acc = V(0, -r * 2.4, 0), drag = 1.4,
          size = nseq(0, r * 0.35, 0.3, r * 0.9, 1, r * 1.5), tr = nseq(0, 0.1, 0.6, 0.45, 1, 1), col = cseq(soil, RGB(150, 136, 116)), rot = 30 })
      end
      local chunk = (c == "wreck") and RGB(52, 52, 50) or RGB(60, 50, 40)
      burst(h, { tex = TX.chunk, n = n(6 + r / 2), life = { 1, 2.2 }, spd = { r * 1.6, r * 3.6 }, spread = 55, acc = V(0, -110, 0), drag = 0.4,
        size = nseq(0, 0.5 + r / 30, 1, 0.3 + r / 50), tr = nseq(0, 0, 0.8, 0, 1, 1), col = cseq(chunk, RGB(36, 32, 28)), rot = 400 })
      if r >= 7 then
        h.CFrame = CFrame.new(p.X, surf + 1.2, p.Z)
        burst(h, { tex = TX.ring, n = 1, life = { 0.35 + r / 120, 0.4 + r / 100 }, spd = { 0.05, 0.05 }, spread = 0, flat = true,
          size = nseq(0, r * 0.4, 1, r * 4.5), tr = nseq(0, 0.25, 1, 1), col = cseq(RGB(235, 220, 195), RGB(235, 220, 195)) })
        burst(h, { tex = TX.smoke, n = n(10 + r / 3), radial = true, dir = Enum.NormalId.Front, spread = 8, life = { 1.4, 2.4 + r / 30 }, spd = { r * 1.2, r * 2.2 }, drag = 1.8,
          acc = V(0, r * 0.15, 0), size = nseq(0, r * 0.4, 1, r * 1.3), tr = nseq(0, 0.35, 1, 1), col = cseq(RGB(170, 154, 128), RGB(190, 180, 160)) })
        h.CFrame = CFrame.new(p)
      end
      burst(h, { tex = TX.smoke, n = n(5 + r / 4), life = { smokeT * 0.6, smokeT }, spd = { r * 0.4, r * 1.1 }, spread = 60, drag = 1.2, acc = V(1.5, r * 0.35 + 2, 0.8),
        size = nseq(0, r * 0.6, 0.4, r * 1.6, 1, r * 2.6), tr = nseq(0, 1, 0.08, 0.2, 0.6, 0.45, 1, 1), col = cseq(RGB(58, 54, 50), RGB(128, 124, 118)), rot = 15 })
      keep = smokeT
      -- 大的留一会儿余火和黑烟（弹坑、残骸在烧）
      if (c == "bomb" or c == "msl" or c == "wreck") and lod == 1 then
        local fireT = (c == "bomb") and 7 or 5
        local f1 = burst(h, { tex = TX.fire, rate = 12, life = { 0.6, 1.2 }, spd = { 2, 6 }, spread = 25, acc = V(0, 6, 0), size = nseq(0, R * 0.3, 1, R * 0.05),
          tr = nseq(0, 0.2, 1, 1), col = cseq(RGB(255, 190, 110), RGB(255, 90, 40)), le = 0.9 })
        local f2 = burst(h, { tex = TX.smoke, rate = 3, life = { 4, 6 }, spd = { 3, 6 }, spread = 15, acc = V(1.2, 3, 0.6), size = nseq(0, R * 0.4, 1, R * 1.8),
          tr = nseq(0, 0.4, 1, 1), col = cseq(RGB(40, 38, 36), RGB(110, 108, 104)) })
        task.delay(fireT, function() f1.Enabled = false f2.Enabled = false end)
        keep = math.max(keep, fireT + 6)
      end
    end
    Debris:AddItem(h, keep + 0.5)
  end
  G.boom = boom

  -- 弹掉进海里：一小柱水
  local function splash(p)
    local h = part(nil, V(1, 1, 1), CFrame.new(p.X, 0.5, p.Z), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local wcol = RGB(236, 242, 246)
    burst(h, { tex = TX.smoke, n = 5, life = { 0.8, 1.3 }, spd = { 10, 22 }, spread = 14, acc = V(0, -40, 0), drag = 0.8, size = nseq(0, 1.5, 1, 4), tr = nseq(0, 0.15, 1, 1), col = cseq(wcol, wcol) })
    Debris:AddItem(h, 1.6)
    G.playSound("splash", p)
  end

  ---------------------------------------------------------------- 飞行中的弹（照服务器给的初速本地算，收到结束就删）

  local GRAV = V(0, -workspace.Gravity * 0.55, 0)
  local flying = {}
  -- 导弹的发动机声挂在弹上跟着飞走（同时最多 4 枚，离镜头远的不挂）
  local roars = 0
  local function addRoar(s, holder, p, k)
    if roars >= 4 or (p - cam.CFrame.Position).Magnitude > 2500 then return end
    roars += 1
    s.roar = makeSound(ROAR, holder, { vol = k or 1, rmin = 50, rmax = 2600 })
  end
  local function stopRoar(s)
    if not s.roar then return end
    local snd = s.roar
    s.roar = nil
    roars -= 1
    tween(snd, 0.4, { Volume = 0 })
    Debris:AddItem(snd, 0.45)
  end
  -- 自己开的飞机打出去的：开火那一下 Fly.lua 已经在耳边放过了，这里不再放一遍
  local function mine(e) return G.fly ~= nil and e.by ~= nil and G.fly.id == e.by end

  local function newShot(e)
    local kind = e.kind
    local aw = e.w and AD.W[e.w]
    if kind == "shell" and e.f == "agun" and e.by and not mine(e) then G.gunLoop(e.by, e.w, e.p, true) end   -- 别人的航炮：炮口那里一个循环声
    if aw and (kind == "missile" or kind == "bomb") and typeof(e.v) == "Vector3" and e.v.Magnitude > 0.1 then   -- 机载导弹、炸弹：按型号的外形（折叠翼展开）
      local cf = CFrame.lookAt(e.p, e.p + e.v)
      local mdl = WM.make(FXF, aw, cf, true)
      local glow = nil
      if kind == "missile" then
        glow = part(BALL, V(1.1, 1.1, 1.1) * math.max(1, aw.shape and aw.shape.d * 1.6 or 1), CFrame.new(e.p), RGB(255, 200, 120), Enum.Material.Neon, 0)
        glowOn(glow, RGB(255, 180, 100), 22, 4)   -- 尾焰照亮弹体和周围
      end
      if not mine(e) then G.sfx((kind == "missile") and "msl" or "bombRel", e.p) end
      flying[e.id] = { wm = mdl, glow = glow, half = (aw.shape and aw.shape.L or 5) / 2, p = e.p, v = e.v, gb = kind == "bomb", t = 0, kind = kind, trailT = 0,
        burn = aw.burn or 4, cfs = table.create(#mdl.parts), tg = e.tg, w = e.w }
      if glow then addRoar(flying[e.id], glow, e.p) end
      if mine(e) and G.onMyShot then G.onMyShot(e) end   -- 自己打出去的：导弹视角小窗（MslCam.lua）
      return
    end
    local body
    if kind == "shell" then   -- 炮弹：一道亮的曳光
      local big = e.f == "tank"
      body = part(CYL, big and V(5, 0.45, 0.45) or V(2.6, 0.22, 0.22), CFrame.new(e.p), big and RGB(255, 236, 190) or RGB(255, 200, 120), Enum.Material.Neon, 0)
      if big then glowOn(body, RGB(255, 220, 170), 10, 2) end
      flying[e.id] = { body = body, p = e.p, v = e.v, g = e.g, gs = e.gs or 1, t = 0, kind = kind, trailT = 0 }
      return
    elseif kind == "grenade" then
      body = part(BALL, V(0.7, 0.7, 0.7), CFrame.new(e.p), RGB(70, 80, 60), Enum.Material.Metal, 0)
    elseif kind == "bomb" then   -- 机载炸弹：粗短的弹体，真实重力往下掉（服务器隔一会儿校一下）
      body = part(CYL, V(3.6, 1, 1), CFrame.new(e.p), RGB(70, 76, 66), Enum.Material.Metal, 0)
      flying[e.id] = { body = body, p = e.p, v = e.v, gb = true, t = 0, kind = kind, trailT = 0 }
      return
    else
      local big = (e.w == "asm") and V(8, 1.3, 1.3) or ((e.w == "sam") and V(6, 1, 1)) or nil   -- 舰艇的反舰 / 防空导弹：大一号、灰白色
      body = part(CYL, big or V(2.2, 0.5, 0.5), CFrame.new(e.p), big and RGB(196, 198, 194) or RGB(80, 86, 70), Enum.Material.Metal, 0)
      local glow = part(BALL, big and V(1.8, 1.8, 1.8) or V(0.9, 0.9, 0.9), CFrame.new(e.p), RGB(255, 200, 120), Enum.Material.Neon, 0)
      if big then glowOn(glow, RGB(255, 190, 110), 26, 4) end
      glow.Name = "Glow"
      glow.Parent = body
    end
    flying[e.id] = { body = body, p = e.p, v = e.v, g = e.g, t = 0, kind = kind, trailT = 0, half = body.Size.X / 2 + 0.1 }
    if (kind == "rocket" or kind == "missile") and not mine(e) then
      G.sfx((kind == "missile" and (e.w == "asm" or e.w == "sam")) and "msl" or "rkt", e.p, { vol = aw and 1 or 0.85 })
    end
    if kind == "missile" and (e.w == "asm" or e.w == "sam") then
      local g = body:FindFirstChild("Glow")
      if g then addRoar(flying[e.id], g, e.p, 1.2) end
    end
  end
  G.flyingShots = flying   -- 导弹视角小窗按弹的位置摆镜头
  local function endShot(id)
    local s = flying[id]
    if s and G.onShotEnd then G.onShotEnd(id, s) end
    if s then
      stopRoar(s)
      if s.body then s.body:Destroy() end
      if s.wm then for _, p in ipairs(s.wm.parts) do p:Destroy() end end
      if s.glow then s.glow:Destroy() end
      flying[id] = nil
    end
  end
  local function stepShots(dt)
    for id, s in pairs(flying) do
      s.t += dt
      if s.g then s.v += GRAV * (s.gs or 1) * dt end
      if s.gb then s.v += V(0, -27.5, 0) * dt end   -- 机载炸弹：AirDefs.GRAV
      s.p += s.v * dt
      if s.wm then   -- 按型号拼的弹：整枚一起挪，导弹尾焰烧完就灭、尾烟跟着淡
        local cf = CFrame.lookAt(s.p, s.p + ((s.v.Magnitude > 0.1) and s.v or V(0, -1, 0)))
        for i, o in ipairs(s.wm.offs) do s.cfs[i] = cf * o end
        workspace:BulkMoveTo(s.wm.parts, s.cfs, Enum.BulkMoveMode.FireCFrameChanged)
        local burning = s.t < s.burn
        if not burning and s.roar then stopRoar(s) end
        if s.glow then
          s.glow.CFrame = cf * CFrame.new(0, 0, s.half + 0.5)
          s.glow.Transparency = burning and 0 or 1
        end
        if s.kind == "missile" then
          s.trailT += dt
          if s.trailT > (burning and 0.035 or 0.12) then
            s.trailT = 0
            local sm = part(BALL, V(1.3, 1.3, 1.3), cf * CFrame.new(0, 0, s.half + 1), RGB(222, 222, 218), Enum.Material.SmoothPlastic, burning and 0.25 or 0.6)
            tween(sm, burning and 2.2 or 1.2, { Size = V(5, 5, 5), Transparency = 1 })
            Debris:AddItem(sm, 2.3)
          end
        end
      elseif s.kind == "grenade" then
        s.body.CFrame = CFrame.new(s.p)
      elseif s.kind == "shell" or s.kind == "bomb" then
        s.body.CFrame = CFrame.lookAt(s.p, s.p + s.v) * CFrame.Angles(0, math.pi / 2, 0)
      elseif s.kind == "smoke" then   -- 烟幕弹：小罐子，后面拖一点白烟
        s.body.CFrame = CFrame.new(s.p)
        s.trailT += dt
        if s.trailT > 0.05 then
          s.trailT = 0
          local sm = part(BALL, V(0.6, 0.6, 0.6), CFrame.new(s.p), RGB(230, 230, 225), Enum.Material.SmoothPlastic, 0.4)
          tween(sm, 0.8, { Size = V(2.2, 2.2, 2.2), Transparency = 1 })
          Debris:AddItem(sm, 0.85)
        end
        if s.t > (s.life or 1) then endShot(id) end
      else
        local cf = CFrame.lookAt(s.p, s.p + s.v) * CFrame.Angles(0, math.pi / 2, 0)
        s.body.CFrame = cf
        local g = s.body:FindFirstChild("Glow")
        local back = s.half or 1.2
        if g then g.CFrame = CFrame.new(s.p - s.v.Unit * back) end
        s.trailT += dt
        if s.trailT > 0.04 then   -- 尾烟（舰艇导弹的粗一些）
          s.trailT = 0
          local k = math.max(1, back / 1.6)
          local sm = part(BALL, V(1, 1, 1) * k, CFrame.new(s.p - s.v.Unit * (back + 0.3)), RGB(200, 200, 200), Enum.Material.SmoothPlastic, 0.3)
          tween(sm, 1.2 * k, { Size = V(3.5, 3.5, 3.5) * k, Transparency = 1 })
          Debris:AddItem(sm, 1.25 * k)
        end
      end
      if s.t > ((s.kind == "bomb") and 40 or 15) then endShot(id) end
    end
  end
  -- 抛副油箱：照挂着的样子拼一个（WeaponModels 的外形），带着飞机的速度往下掉——空箱子阻力大很快慢下来，重心靠前机头往下栽、绕纵轴慢慢转；
  --   掉到海里溅一下、地上起一团土就没了
  local drops = {}
  local function tankDrop(e)
    local aw = e.w and AD.W[e.w]
    if not aw or typeof(e.cf) ~= "CFrame" then return end
    local mdl = WM.make(FXF, aw, e.cf, false)
    table.insert(drops, { wm = mdl, cf = e.cf, v = (typeof(e.v) == "Vector3") and e.v or V(), t = 0, spin = (math.random() - 0.5) * 2.4, cfs = table.create(#mdl.parts) })
    G.playSound("quiet", e.cf.Position, 0.6)
  end
  local function stepDrops(dt)
    for i = #drops, 1, -1 do
      local s = drops[i]
      s.t += dt
      s.v = (s.v + V(0, -27.5, 0) * dt) * (1 - 0.3 * dt)
      local p = s.cf.Position + s.v * dt
      s.cf = CFrame.new(p) * (s.cf - s.cf.Position) * CFrame.Angles(-0.8 * dt * math.min(1, s.t), 0, s.spin * dt)
      for k, o in ipairs(s.wm.offs) do s.cfs[k] = s.cf * o end
      workspace:BulkMoveTo(s.wm.parts, s.cfs, Enum.BulkMoveMode.FireCFrameChanged)
      local gy = math.max(AD.ground(MapM, p.X, p.Z), 0)   -- 甲板也算（落在航母上就没了）
      if p.Y <= gy + 0.5 or s.t > 30 then
        if p.Y <= gy + 2 then
          if gy <= 0.5 then splash(p) else
            local d = part(BALL, V(4, 4, 4), CFrame.new(p), RGB(168, 150, 122), Enum.Material.SmoothPlastic, 0.3)
            tween(d, 1.3, { Size = V(15, 15, 15), Transparency = 1 })
            Debris:AddItem(d, 1.35)
          end
        end
        for _, q in ipairs(s.wm.parts) do q:Destroy() end
        table.remove(drops, i)
      end
    end
  end
  -- 服务器校正：导弹拐弯、炸弹滑翔（本地只会直线 / 抛物线）
  local function fixShot(e)
    local s = flying[e.id]
    if not s or typeof(e.p) ~= "Vector3" or typeof(e.v) ~= "Vector3" then return end
    if (s.p - e.p).Magnitude > 60 then s.p = e.p else s.p = s.p:Lerp(e.p, 0.6) end
    s.v = e.v
  end
  -- 热诱弹：一串亮点往后下方撒开，拖着白烟
  local function flares(e)
    local v0 = (typeof(e.v) == "Vector3") and e.v or V()
    for i = 1, 4 do
      local dir = (-v0.Unit * 0.4 + V((math.random() - 0.5) * 1.6, -0.4 - math.random() * 0.4, (math.random() - 0.5) * 1.6)).Unit
      local f = part(BALL, V(1.4, 1.4, 1.4), CFrame.new(e.p), RGB(255, 236, 170), Enum.Material.Neon, 0)
      local p1 = e.p + v0 * 0.35 + dir * (40 + i * 8)
      tween(f, 1.8, { CFrame = CFrame.new(p1 - V(0, 30, 0)), Transparency = 1, Size = V(0.6, 0.6, 0.6) })
      if i <= 2 then tween(glowOn(f, RGB(255, 222, 160), 34, 5), 1.8, { Brightness = 0 }) end   -- 夜里热诱弹把飞机照亮
      Debris:AddItem(f, 1.85)
      for k = 1, 4 do
        task.delay(k * 0.25, function()
          local q = e.p:Lerp(p1, k / 4) - V(0, 30 * (k / 4) ^ 2, 0)
          local sm = part(BALL, V(1.5, 1.5, 1.5), CFrame.new(q), RGB(235, 235, 230), Enum.Material.SmoothPlastic, 0.35)
          tween(sm, 1.6, { Size = V(5, 5, 5), Transparency = 1 })
          Debris:AddItem(sm, 1.65)
        end)
      end
    end
    G.playSound("quiet", e.p, 1.6)
  end
  -- 弹射座椅：座舱盖飞走、座椅带着一道火冲上去
  local function eject(e)
    local cap = part(nil, V(3, 1.2, 6), CFrame.new(e.p), RGB(40, 56, 66), Enum.Material.Glass, 0.3)
    tween(cap, 1.2, { CFrame = CFrame.new(e.p + V(math.random() * 20 - 10, 25, 30)) * CFrame.Angles(2, 1, 0.5), Transparency = 1 })
    Debris:AddItem(cap, 1.25)
    local fl = part(BALL, V(2, 2, 2), CFrame.new(e.p), RGB(255, 190, 90), Enum.Material.Neon, 0)
    tween(fl, 0.5, { CFrame = CFrame.new(e.p + V(0, 30, 0)), Transparency = 1, Size = V(4, 4, 4) })
    Debris:AddItem(fl, 0.55)
    G.playSound("rocket", e.p, 1.2)
  end

  -- 车炮开火：炮口火光、一团烟、坦克炮还有一圈扬尘；离得近震屏
  local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
  local function vfire(e)
    local big = e.f == "tank" or e.f == "arty"
    local dir = (typeof(e.d) == "Vector3") and e.d or V(0, 0, -1)
    local fl = part(BALL, big and V(4, 4, 4) or V(1.6, 1.6, 1.6), CFrame.new(e.p + dir * (big and 2 or 0.6)), RGB(255, 210, 120), Enum.Material.Neon, 0)
    tween(fl, big and 0.12 or 0.06, { Transparency = 1, Size = (big and V(9, 9, 9) or V(3, 3, 3)) })
    Debris:AddItem(fl, 0.15)
    flash(e.p + dir * (big and 3 or 1), RGB(255, 190, 110), big and 46 or 16, big and 9 or 4, big and 0.28 or 0.1)
    if big then
      local holder = part(nil, V(0.2, 0.2, 0.2), CFrame.lookAt(e.p, e.p + dir), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
      local pe = Instance.new("ParticleEmitter")
      pe.Texture = SMOKE_TEX
      pe.Rate = 0
      pe.Lifetime = NumberRange.new(1.5, 3)
      pe.Speed = NumberRange.new(10, 26)
      pe.SpreadAngle = Vector2.new(25, 25)
      pe.Drag = 3
      pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) })
      pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
      pe.Color = ColorSequence.new(RGB(200, 196, 186))
      pe.EmissionDirection = Enum.NormalId.Front
      pe.Parent = holder
      pe:Emit(14)
      Debris:AddItem(holder, 4)
      -- 地上一圈扬尘（炮口暴风）
      local gy = G.Map and G.Map.ground and G.Map.ground(e.p.X, e.p.Z) or e.p.Y - 4
      local ring = part(CYL, V(0.5, 6, 6), CFrame.new(e.p.X, gy + 0.6, e.p.Z) * CFrame.Angles(0, 0, math.pi / 2), RGB(190, 170, 130), Enum.Material.SmoothPlastic, 0.45)
      tween(ring, 0.7, { Size = V(0.5, 34, 34), Transparency = 1 })
      Debris:AddItem(ring, 0.75)
      G.playSound("boom", e.p, 0.75)
    else
      G.playSound("lmg", e.p)
    end
    if G.vehRecoil and e.id then G.vehRecoil(e.id, e.g) end
    local dd = (e.p - cam.CFrame.Position).Magnitude
    if big and dd < 140 then G.shake(0.3 * (1 - dd / 140)) end
  end

  -- 烟幕弹：从每根发射筒飞出去（小抛物线），0.9 秒后落地起一大团烟（持续 life 秒）
  local smokeN = 0
  local function smokeLaunch(e)
    for _, it in ipairs(e.list or {}) do
      local a, b = it.a, it.b
      local T0 = 0.9
      local v = (b - a) / T0 - GRAV * 0.5 * T0
      smokeN += 1
      local body = part(CYL, V(0.7, 0.32, 0.32), CFrame.new(a), RGB(70, 80, 64), Enum.Material.Metal, 0)
      flying["sm" .. smokeN] = { body = body, p = a, v = v, g = true, gs = 1, t = 0, kind = "smoke", trailT = 0, life = T0 }
    end
    G.playSound("rocket", e.list and e.list[1] and e.list[1].a or nil, 2.4)
  end
  local function smokeCloud(e)
    local holder = part(nil, V(0.2, 0.2, 0.2), CFrame.new(e.p), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local life = e.life or 30
    for i = 1, 2 do
      local pe = Instance.new("ParticleEmitter")
      pe.Texture = SMOKE_TEX
      pe.Rate = (i == 1) and 8 or 4
      pe.Lifetime = NumberRange.new(6, 10)
      pe.Speed = NumberRange.new(1, 4)
      pe.SpreadAngle = Vector2.new(180, 180)
      pe.Acceleration = V(0, 0.6, 0)
      pe.Drag = 1.2
      pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(0.3, (e.r or 20) * 1.1), NumberSequenceKeypoint.new(1, (e.r or 20) * 1.5) })
      pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
      pe.Color = ColorSequence.new((i == 1) and RGB(226, 228, 226) or RGB(190, 194, 192))
      pe.LightInfluence = 0.8
      pe.Parent = holder
      pe:Emit(18)
      task.delay(math.max(1, life - 8), function() pe.Rate = 0 end)
    end
    G.playSound("splash", e.p, 1.6)
    Debris:AddItem(holder, life + 12)
  end

  -- 垂发：舱口一团火光、往上翻的一大团白烟（防空导弹的小一点）
  local function vls(e)
    local s = e.sam and 0.7 or 1
    local fl = part(BALL, V(3, 3, 3) * s, CFrame.new(e.p), RGB(255, 214, 140), Enum.Material.Neon, 0)
    tween(fl, 0.3, { Size = V(9, 9, 9) * s, Transparency = 1 })
    Debris:AddItem(fl, 0.35)
    flash(e.p + V(0, 3, 0), RGB(255, 196, 120), 50 * s, 8, 0.5)
    for i = 1, 6 do
      local off = V(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * 6 * s
      local sm = part(BALL, V(5, 5, 5) * s, CFrame.new(e.p + off), RGB(226, 226, 222), Enum.Material.SmoothPlastic, 0.2)
      tween(sm, 3 + math.random(), { Size = V(22, 22, 22) * s, Transparency = 1, CFrame = CFrame.new(e.p + off + V(0, 14 + i * 3, 0)) })
      Debris:AddItem(sm, 4.2)
    end
    G.playSound("rocket", e.p, 0.9)
    local d = (e.p - cam.CFrame.Position).Magnitude
    if d < 200 then G.shake(0.25 * (1 - d / 200)) end
  end

  -- 炮弹：落地前一秒多传来呼啸声
  local function shell(e)
    local t = e.t or 3
    task.delay(math.max(0, t - 1.3), function() G.playSound("rocket", e.p, 0.6) end)
  end

  ---------------------------------------------------------------- 被标记的敌人

  local spotMarks = {}
  local function spots(list)
    for _, m in ipairs(spotMarks) do m:Destroy() end
    spotMarks = {}
    for _, p in ipairs(list or {}) do
      local a = part(nil, V(0.2, 0.2, 0.2), CFrame.new(p + V(0, 6, 0)), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
      local bb = Instance.new("BillboardGui")
      bb.Size = UDim2.fromOffset(18, 18)
      bb.AlwaysOnTop = true
      bb.MaxDistance = 2500
      bb.Parent = a
      local l = Instance.new("TextLabel")
      l.Size = UDim2.fromScale(1, 1)
      l.BackgroundTransparency = 1
      l.Text = "◆"
      l.TextScaled = true
      l.TextColor3 = RGB(255, 60, 50)
      l.Parent = bb
      table.insert(spotMarks, a)
    end
    if G.mapSpots then G.mapSpots(list) end
  end

  ---------------------------------------------------------------- 服务器发来的特效

  -- 子弹擦身（用户：感受不到激烈对抗）：敌人的枪弹从离头 7 格以内飞过——嗖的一声，屏幕边缘发暗、微微模糊（压制，Hud.lua G.suppress），越近越重
  local function nearMiss(e)
    if typeof(e.a) ~= "Vector3" or typeof(e.b) ~= "Vector3" then return end
    if e.t and e.t == me:GetAttribute("Side") then return end   -- 自己人的
    local ch = me.Character
    local head = ch and ch:FindFirstChild("Head")
    if not head then return end
    local p = head.Position
    local ab = e.b - e.a
    local L2 = ab:Dot(ab)
    if L2 < 4 then return end
    local u = math.clamp((p - e.a):Dot(ab) / L2, 0, 1)
    if u < 0.04 then return end   -- 枪口就在身边（贴脸开枪的不算擦身）
    local q = e.a + ab * u
    local d = (q - p).Magnitude
    if d > 7 then return end
    if G.sfx then G.sfx("whiz", q, { vol = 1.15 - d / 9, rmax = 60 }) end
    if G.suppress then G.suppress(math.clamp(1 - d / 7, 0.2, 1) * 0.32) end
  end

  function G.onFx(list)
    for _, e in ipairs(list) do
      local k = e.k
      if k == "gun" then
        if e.ent then   -- 机器人开的枪：小兵后坐、枪口焰，曳光从它的枪口出来（Soldier.lua）
          if G.vehRecoil then G.vehRecoil(e.ent) end
          local mz = G.botMuzzle and G.botMuzzle(e.ent)
          if mz and (mz - e.a).Magnitude < 8 then e.a = mz end
        end
        if e.by ~= me.UserId then
          nearMiss(e)
          G.gunFx(e.w, e.a, e.b, false)
          if G.radarShot then G.radarShot(e.a, e.t, e.q) end   -- 雷达：敌人开枪的地方闪一下（Hud.lua）
        end
      elseif k == "boom" then boom(e.p, e.s, e.c)
      elseif k == "shot" then newShot(e)
      elseif k == "shotEnd" then endShot(e.id)
      elseif k == "shotFix" then fixShot(e)
      elseif k == "flares" then flares(e)
      elseif k == "eject" then eject(e)
      elseif k == "shell" then shell(e)
      elseif k == "splash" then splash(e.p)
      elseif k == "mortarFire" then G.playSound("mortar", e.p)
      elseif k == "heal" then
        local r = part(CYL, V(0.3, 4, 4), CFrame.new(e.p - V(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(90, 255, 120), Enum.Material.Neon, 0.3)
        tween(r, 0.8, { Size = V(0.3, 28, 28), Transparency = 1 })
        Debris:AddItem(r, 0.85)
        G.playSound("heal", e.p)
      elseif k == "repair" then
        local sp = part(BALL, V(0.6, 0.6, 0.6), CFrame.new(e.p + V(math.random() - 0.5, 2, math.random() - 0.5) * 3), RGB(255, 220, 120), Enum.Material.Neon, 0)
        tween(sp, 0.3, { Size = V(0.1, 0.1, 0.1), Transparency = 1 })
        Debris:AddItem(sp, 0.35)
      elseif k == "capture" then G.playSound("capture")
      elseif k == "spots" then spots(e.list)
      elseif k == "ramp" then G.playSound("splash")
      elseif k == "vfire" then vfire(e)
      elseif k == "vls" then vls(e)
      elseif k == "smokeLaunch" then smokeLaunch(e)
      elseif k == "smokeCloud" then smokeCloud(e)
      elseif k == "tankDrop" then tankDrop(e)
      elseif G.fxExtra and G.fxExtra[k] then G.fxExtra[k](e)   -- 别的模块登记的（战术平板的空投、空袭：TacPad.lua）
      end
    end
  end

  function G.stepFx(dt)
    stepShots(dt or 1 / 60)
    stepGuns()
    if #drops > 0 then stepDrops(dt or 1 / 60) end
  end
end

return Fx
