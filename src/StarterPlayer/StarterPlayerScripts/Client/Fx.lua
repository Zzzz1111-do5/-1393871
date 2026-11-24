-- Roblox全面大战场（客户端）——特效与音效：曳光、枪口火光、弹着点（钢甲火花、跳弹、土、沙、水）、飞行中的火箭弹 / 导弹 / 手雷（照服务器给的初速本地算弹道）、炮弹落下的呼啸、爆炸、溅水、
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
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
  local me = Players.LocalPlayer
  local AD = require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs"))
  local WM = require(game:GetService("ReplicatedStorage"):WaitForChild("WeaponModels"))
  local MapM = require(game:GetService("ReplicatedStorage"):WaitForChild("Map"))
  local HitSurf = require(game:GetService("ReplicatedStorage"):WaitForChild("HitSurf"))   -- 子弹打在什么上面（弹着点按它画）

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
  -- 真录音（SoundLib.lua，用户 11-21：声音要逼真）：开局预载，载上了的才用；载不下来（被删、私有、没网）照旧用下面叠出来的
  local SL = {}
  pcall(function() SL = require(game:GetService("ReplicatedStorage"):WaitForChild("SoundLib", 5)) or {} end)
  local REAL, REALLEN = {}, {}   -- [键] = { 载上了的 SoundId… }；[SoundId] = 秒
  task.spawn(function()
    local list, byId = {}, {}
    for key, cfg in pairs(SL) do
      for _, id in ipairs(cfg.ids or {}) do
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. tostring(id)
        table.insert(list, s)
        byId[s.SoundId] = key
        REALLEN[s.SoundId] = cfg.len or 3
      end
    end
    if #list == 0 then return end
    local ok = pcall(function()
      game:GetService("ContentProvider"):PreloadAsync(list, function(cid, status)
        local key = byId[cid]
        if key and status == Enum.AssetFetchStatus.Success then
          REAL[key] = REAL[key] or {}
          table.insert(REAL[key], cid)
        end
      end)
    end)
    for _, s in ipairs(list) do
      local okL, tl = pcall(function() return s.TimeLength end)
      if okL and tl and tl > 0 then REALLEN[s.SoundId] = tl end
      s:Destroy()
    end
    G.realLoaded = ok
  end)
  local function real(key)   -- 这个声音载上了的真录音（随机挑一个）和它的设置；没有就 nil
    local l = REAL[key]
    if not l or #l == 0 then return nil end
    return l[math.random(#l)], SL[key]
  end
  G.realSound = real
  G.realSoundState = function() return REAL end   -- 测试用
  -- 简单音效换成真录音：名字 → { SoundLib 的键, 速度倍数, 音量倍数 }
  local SNDREAL = { rifle = { "rifle", 1, 1 }, lmg = { "hmg", 1.1, 0.9 }, sniper = { "rifle", 0.85, 1.3 }, pistol = { "rifle", 1.25, 0.7 },
    boom = { "boomM", 1, 1 }, rocket = { "missile", 1.1, 0.9 }, mortar = { "boomS", 0.9, 1 } }
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
    local rm = SNDREAL[name]
    local rid, rcfg = nil, nil
    if rm then rid, rcfg = real(rm[1]) end
    if rid then   -- 真录音
      snd.SoundId = rid
      snd.Volume = math.min(10, (rcfg.vol or 1) * rm[3])
      snd.PlaybackSpeed = speed or ((rcfg.s[1] + (rcfg.s[2] - rcfg.s[1]) * math.random()) * rm[2])
    else
      snd.SoundId = def[1]
      snd.Volume = def[2]
      snd.PlaybackSpeed = speed or (def[3] + (def[4] - def[3]) * math.random())
    end
    snd.RollOffMinDistance = 30
    snd.RollOffMaxDistance = 1600
    if pos then
      local p = part(nil, V(0.2, 0.2, 0.2), CFrame.new(pos), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
      snd.Parent = p
      snd:Play()
      Debris:AddItem(p, rid and 8 or 5)
    else
      snd.Parent = SoundService
      snd:Play()
      Debris:AddItem(snd, rid and 8 or 5)
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
  setmetatable(LEN, { __index = function(_, id) return REALLEN[id] end })   -- 真录音的长度（预载完按实际长度）
  -- 叠层的音效换成真录音：SFX 的名字 → { SoundLib 的键, 速度倍数, 音量倍数 }（别的照旧叠：落地、换挡、心跳、拉栓……）
  local SFXREAL = { tankGun = { "tankGun", 1, 1 }, rkt = { "missile", 1.15, 0.8 }, msl = { "missile", 1, 1 }, whiz = { "whiz", 1, 1 }, ric = { "ric", 1, 1 },
    shellRic = { "ric", 0.8, 1.4 }, ping = { "metalHit", 1.2, 0.8 }, clang = { "metalHit", 0.85, 1.1 }, sonic = { "sonic", 1, 1 },
    rifleMe = { "rifle", 1, 1.1 }, sniperMe = { "rifle", 0.85, 1.3 }, earRing = { "earRing", 1, 1 } }
  local function realLayer(key, sp, vol)
    local id, cfg = real(key)
    if not id then return nil end
    sp = sp or 1
    return { id = id, vol = (cfg.vol or 1) * (vol or 1), s = { cfg.s[1] * sp, cfg.s[2] * sp } }
  end
  G.realLayer = realLayer   -- 核爆（Nuke.lua）叠自己的声音用
  G.sndIds = { EXP = EXP, TICK = TICK, WIND = WIND, THUD = THUD, WATER = WATER }
  -- 发动机之类的循环真录音（Drive / Sail / Fly 用）：没载上返回 nil（照旧用叠出来的）
  function G.realLoop(key, parent)
    local id, cfg = real(key)
    if not id then return nil end
    local snd = Instance.new("Sound")
    snd.SoundId = id
    snd.Volume = cfg.vol or 1
    snd.Looped = true
    if type(cfg.loop) == "table" then
      snd.PlaybackRegionsEnabled = true
      snd.LoopRegion = NumberRange.new(cfg.loop[1], cfg.loop[2])
    end
    snd.Parent = parent
    snd:Play()
    return snd
  end
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
    -- 阵亡（DeathFx.lua，GTA5 那一下「WASTED」）：放慢的低沉爆炸（只留低音、一点失真）+ 放慢的风声呼一下
    death = { { id = EXP, vol = 1.1, s = { 0.42, 0.45 }, reg = { 0, 2.4 }, eq = { 10, -3, -20 }, dist = 0.3 },
      { id = WIND, vol = 7, s = { 0.62, 0.66 }, reg = { 2, 4.2 }, eq = { 6, 4, -10 }, fade = 1.4 } },
    -- 自己开枪（耳边，用户 11-18：提高手感；原来是一层拉快的爆炸声，薄）：脆的一下（起爆那一截拉快）+ 低沉的一下（放慢、只留低音）
    --   + 枪机的咔哒 + 很短的回声尾巴；狙击枪更重、尾巴更长
    rifleMe = { { id = EXP, vol = 0.3, s = { 2.5, 2.8 }, reg = { 0.02, 0.3 }, eq = { -3, 2, 4 } },
      { id = EXP, vol = 0.3, s = { 1.28, 1.4 }, reg = { 0, 0.34 }, eq = { 9, -3, -12 } },
      { id = TICK, vol = 0.18, s = { 1.9, 2.2 }, eq = { -6, 2, 2 }, delay = 0.012 },
      { id = EXP, vol = 0.08, s = { 0.95, 1.05 }, reg = { 0.06, 1.0 }, eq = { 2, -2, -14 }, echo = { 0.13, 0.2, -14 }, delay = 0.03 } },
    sniperMe = { { id = EXP, vol = 0.5, s = { 1.9, 2.05 }, reg = { 0.02, 0.4 }, eq = { -2, 2, 4 } },
      { id = EXP, vol = 0.5, s = { 0.9, 0.98 }, reg = { 0, 0.55 }, eq = { 10, -2, -12 } },
      { id = TICK, vol = 0.25, s = { 1.2, 1.35 }, eq = { -4, 2, 0 }, delay = 0.5 },
      { id = EXP, vol = 0.16, s = { 0.7, 0.76 }, reg = { 0.05, 1.8 }, eq = { 4, -2, -14 }, echo = { 0.22, 0.3, -10 }, delay = 0.05 } },
    dry = { { id = TICK, vol = 0.6, s = { 1.45, 1.55 }, eq = { -6, 3, 0 } } },   -- 打空了扣扳机
    -- 装了消音器（改枪）：自己听到的是一声闷的「噗」加枪机的金属撞击声，没有尾音和回声
    rifleSdMe = { { id = EXP, vol = 0.16, s = { 3.2, 3.6 }, reg = { 0.02, 0.18 }, eq = { -8, 0, -6 } },
      { id = TICK, vol = 0.3, s = { 1.7, 2.0 }, eq = { -6, 2, 4 }, delay = 0.01 }, { id = TICK, vol = 0.14, s = { 2.6, 3.0 }, eq = { -8, 0, 6 }, delay = 0.03 } },
    sniperSdMe = { { id = EXP, vol = 0.3, s = { 2.2, 2.4 }, reg = { 0.02, 0.25 }, eq = { -4, 0, -8 } },
      { id = TICK, vol = 0.25, s = { 1.2, 1.35 }, eq = { -4, 2, 0 }, delay = 0.5 } },
    brass = { { id = TICK, vol = 0.07, s = { 3.3, 3.9 }, eq = { -14, 0, 4 } }, { id = TICK, vol = 0.05, s = { 3.6, 4.2 }, eq = { -14, 0, 4 }, delay = 0.09 } },   -- 弹壳落地
    -- 弹着点（用户：枪打在坦克上要有火花）：子弹打在钢甲上一声脆的「叮」+ 一下金属的「嚓」；重机枪、航炮打上去低一点、重一点的「当」；
    --   跳弹飞走一声尖细的「啾——」；打在土、石头上闷闷的一下
    ping = { { id = TICK, vol = 0.85, s = { 2.6, 3.3 }, eq = { -12, 2, 6 } }, { id = EXP, vol = 0.14, s = { 2.6, 3.0 }, reg = { 0.02, 0.16 }, eq = { -12, 0, 6 } } },
    clang = { { id = TICK, vol = 1, s = { 1.45, 1.8 }, eq = { -6, 3, 4 } }, { id = EXP, vol = 0.3, s = { 1.7, 1.95 }, reg = { 0.02, 0.22 }, eq = { -4, 2, 2 } } },
    ric = { { id = WIND, vol = 6, s = { 2.8, 3.5 }, reg = { 2.15, 2.5 }, eq = { -14, 6, 6 } } },
    thud = { { id = THUD, vol = 0.45, s = { 1.6, 2.1 }, eq = { 0, 0, -4 } } },
    -- 载具（用户 11-20：照 UE5 的水平升级）：落地——放慢的闷响 + 只留低音的一下轰；撞上东西——闷响 + 一截爆炸声的碎响 + 金属咔；
    --   换挡——咔哒一下（放慢、留低音）+ 很轻的闷响
    vehLand = { { id = THUD, vol = 1.2, s = { 0.42, 0.5 }, eq = { 10, -2, -14 } }, { id = EXP, vol = 0.35, s = { 0.55, 0.62 }, reg = { 0, 0.5 }, eq = { 10, -4, -16 } } },
    vehHit = { { id = THUD, vol = 1, s = { 0.55, 0.65 }, eq = { 8, 0, -8 } }, { id = EXP, vol = 0.3, s = { 1.1, 1.3 }, reg = { 0.02, 0.3 }, eq = { 2, 2, -2 } },
      { id = TICK, vol = 0.5, s = { 0.7, 0.8 }, eq = { 2, 4, -2 } } },
    gearShift = { { id = TICK, vol = 0.55, s = { 0.5, 0.56 }, eq = { 8, 0, -8 } }, { id = THUD, vol = 0.25, s = { 1.2, 1.3 }, eq = { 6, -2, -10 } } },
    -- 飞机接地：主轮一声吱（风声截短、拉快、只留中高音）+ 一下闷响；直升机滑橇：闷响 + 金属咔
    touchdown = { { id = WIND, vol = 5, s = { 2.4, 2.8 }, reg = { 2.2, 2.6 }, eq = { -14, 6, 4 } }, { id = THUD, vol = 0.8, s = { 0.6, 0.7 }, eq = { 8, -2, -10 } } },
    skidLand = { { id = THUD, vol = 1, s = { 0.5, 0.58 }, eq = { 9, -2, -12 } }, { id = TICK, vol = 0.4, s = { 0.8, 0.9 }, eq = { 2, 3, -4 } } },
    -- 船头砸浪：拍水声（放慢、留低音）+ 一下闷响
    bowSlam = { { id = WATER, vol = 0.9, s = { 0.55, 0.65 }, eq = { 6, 0, -6 } }, { id = THUD, vol = 0.5, s = { 0.5, 0.56 }, eq = { 8, -2, -12 } } },
    -- 坦克炮（用户：开火动画做的好一点）：起爆那一截拉快的脆响 + 放慢、失真、只留低音的轰隆 + 拖得很长的回声尾巴
    tankGun = { { id = EXP, vol = 0.9, s = { 1.5, 1.65 }, reg = { 0.02, 0.4 }, eq = { -2, 3, 4 } },
      { id = EXP, vol = 1.2, s = { 0.58, 0.64 }, reg = { 0, 2.2 }, eq = { 12, 0, -14 }, dist = 0.4 },
      { id = EXP, vol = 0.35, s = { 0.5, 0.55 }, reg = { 0.1, 2.4 }, eq = { 6, -2, -16 }, echo = { 0.3, 0.35, -8 }, delay = 0.08 } },
    -- 炮弹跳弹：钢甲上一声重的「当」+ 一下金属的「嚓」+ 尖啸着飞走
    shellRic = { { id = TICK, vol = 1, s = { 0.9, 1.05 }, eq = { -4, 4, 4 } }, { id = EXP, vol = 0.4, s = { 2.2, 2.5 }, reg = { 0.02, 0.2 }, eq = { -6, 2, 6 } },
      { id = WIND, vol = 8, s = { 2.2, 2.8 }, reg = { 2.1, 2.9 }, eq = { -14, 6, 8 }, delay = 0.03, fade = 0.2 } },
  }
  -- 导弹飞行中的发动机声：挂在弹上跟着飞走（燃烧完就停）
  local ROAR = { id = WIND, vol = 10, s = { 0.95, 1.05 }, loop = { 0.5, 9.5 }, eq = { 6, 10, -1 }, dist = 0.55 }

  local function makeSound(L, parent, o)
    local snd = Instance.new("Sound")
    snd.SoundId = L.id
    -- 震荡（Shock.lua）：近处刚炸过，别的声音发闷、变小（耳鸣本身 o.dry 不闷）
    local muf = (not o.dry and G.muffle) and G.muffle() or 0
    snd.Volume = math.min(10, L.vol * (o.vol or 1)) * (1 - 0.55 * muf)
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
    local hi = (L.eq and L.eq[3] or 0) + (o.hiCut or 0) - 34 * muf
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
    if type(def) == "string" then
      local rm = SFXREAL[def]
      local L = rm and realLayer(rm[1], rm[2], rm[3])
      if L and def == "tankGun" and pos and (pos - cam.CFrame.Position).Magnitude < 30
        and ((G.interiorOn and G.interiorOn()) or (G.drive and G.drive.sight)) then
        L = realLayer("tankGunIn", 1, 1) or L   -- 自己在车里 / 炮长镜里开炮：车内的录音（闷、震）
      end
      def = L and { L } or SFX[def]
    end
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

  -- 镜头上的震屏和开枪后坐（用户 11-18：提高手感）
  --   Roblox 自带的镜头（步行时）每帧从「现在的朝向」接着算：往 cam.CFrame 上加的俯仰、偏航会一直留下。原来震屏每帧加全量，
  --   炸一下准星就被甩到别处（随机游走）；后坐每发一下子跳 1～1.7°、不回落，一梭子打完视线往上飘四五十度。现在分两份：
  --   · 一下就回来的（震屏、后坐的「踢」——弹簧，约 0.03 秒到顶、0.15 秒回到原处）：步行时每帧只加这一帧的增量，晃完视线回到原处；
  --     开车、开飞机是脚本镜头（每帧重新摆），照旧加全量。横滚每帧都被 Roblox 镜头摆正，加全量
  --   · 留下来的（后坐的上抬、左右飘）：几帧里平滑加上去（不是一下跳），要自己往下压枪
  local trauma = 0
  function G.shake(a) trauma = math.min(1, trauma + a) end
  local pp, py, pr, vp, vy, vr = 0, 0, 0, 0, 0, 0   -- 踢：俯仰、偏航、横滚（弧度）和角速度
  local climbP, climbY = 0, 0                       -- 还没加上去的上抬、左右飘
  local aP, aY = 0, 0                               -- 步行时已经加进镜头朝向里的「一下就回来的」那份
  local SPR = 30                                    -- 弹簧角频率（临界阻尼）
  -- 什么时候加（用户 11-21：边走边开枪后坐力是往下的）：步行时在镜头模块之后、记录仪晃动（Bodycam，Camera + 5）之前加——
  --   原来在最后（Last）加，记录仪下一帧开头还原晃动时发现镜头被动过就不还原，它那份总是往下的低头晃动每帧都留在镜头里，
  --   边走边打一路往下压。开车、开飞机的脚本镜头每帧重新摆，还是要在最后加（IAShakeLate）
  local tP, tY, tR, live = 0, 0, 0, false
  pcall(function()
    RunService:BindToRenderStep("IAShakeLate", Enum.RenderPriority.Last.Value, function()
      if live and cam.CameraType == Enum.CameraType.Scriptable then cam.CFrame = cam.CFrame * CFrame.Angles(tP, tY, tR) end
    end)
  end)
  pcall(function()
    RunService:BindToRenderStep("IAShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
      dt = math.min(dt, 0.1)
      live = false
      if trauma <= 0.002 and climbP == 0 and climbY == 0 and math.abs(pp) + math.abs(py) + math.abs(pr) + math.abs(vp) + math.abs(vy) + math.abs(vr) < 1e-5
        and aP == 0 and aY == 0 then
        pp, py, pr, vp, vy, vr = 0, 0, 0, 0, 0, 0
        return
      end
      live = true
      local n = math.max(1, math.ceil(dt / (1 / 240)))   -- 弹簧分小步算（帧率低时不发散）
      local h = dt / n
      for _ = 1, n do
        vp += (-SPR * SPR * pp - 2 * SPR * vp) * h
        vy += (-SPR * SPR * py - 2 * SPR * vy) * h
        vr += (-SPR * SPR * pr - 2 * SPR * vr) * h
        pp += vp * h
        py += vy * h
        pr += vr * h
      end
      local sP, sY, sR = 0, 0, 0
      if trauma > 0.002 then
        local s = trauma * trauma
        local t = os.clock() * 26
        sP, sY, sR = math.noise(t, 1.7) * 0.05 * s, math.noise(t, 5.3) * 0.05 * s, math.noise(t, 9.1) * 0.03 * s
        trauma = math.max(0, trauma - dt * 1.6)
      else
        trauma = 0
      end
      tP, tY, tR = pp + sP, py + sY, pr + sR
      local f = 1 - math.exp(-dt * 40)   -- 上抬几帧里加完（60 帧时一帧加一半）
      local cP, cY = climbP * f, climbY * f
      climbP -= cP
      climbY -= cY
      if math.abs(climbP) < 1e-6 then climbP = 0 end
      if math.abs(climbY) < 1e-6 then climbY = 0 end
      if cam.CameraType == Enum.CameraType.Scriptable then
        aP, aY = 0, 0   -- 脚本镜头：IAShakeLate 在最后加全量
      else
        cam.CFrame = cam.CFrame * CFrame.Angles(cP + tP - aP, cY + tY - aY, tR)
        aP, aY = tP, tY
        if math.abs(aP) < 1e-6 and math.abs(aY) < 1e-6 and trauma == 0 then aP, aY = 0, 0 end
      end
    end)
  end)
  -- 开枪的后坐：up 每发留下来的上抬（度）、side 左右飘、punch 一下就回来的踢、roll 踢的横滚；开镜（ads）上抬 × 0.45、踢 × 0.45
  --   （开着 3.5 倍镜，同样的角度看着大三倍多）；一梭子的头一发 × 0.55，越打越大，第五发起 × 1.15（点射稳、扫射飘）；
  --   左右飘按一梭子里慢慢摆（每梭子起点随机），不是每发乱跳
  local RC = { m4 = { up = 0.3, side = 0.12, punch = 1.0, roll = 0.5 }, sniper = { up = 1.8, side = 0.35, punch = 3.4, roll = 1.2 } }
  local burstN, lastShot, driftPh = 0, 0, 0
  function G.kick(w, ads, id)
    local d = w.dmg or 20
    local rc = w.rc or RC[id or ""] or { up = d * 0.012, side = d * 0.0045, punch = d * 0.04, roll = 0.5 }   -- w.rc：改枪按后坐力控制改过的
    local t = os.clock()
    if t - lastShot > (w.rate or 0.1) * 2.5 + 0.08 then
      burstN = 0
      driftPh = math.random() * 2 * math.pi
    end
    lastShot = t
    burstN += 1
    local k = math.min(1.15, 0.55 + 0.15 * (burstN - 1)) * (ads and 0.45 or 1)
    local r = math.rad
    climbP += r(rc.up) * k * (0.85 + math.random() * 0.3)
    climbY += r(rc.side) * k * (math.sin(driftPh + burstN * 0.55) * 0.8 + (math.random() - 0.5) * 0.9)
    local v0 = r(rc.punch) * (ads and 0.45 or 1) * SPR * math.exp(1)   -- 临界阻尼弹簧：初速 v0 的峰值 = v0 / (ω·e)
    vp += v0 * (0.9 + math.random() * 0.2)
    vy += v0 * 0.25 * (math.random() - 0.5)
    vr += r(rc.roll) * (ads and 0.5 or 1) * SPR * math.exp(1) * (math.random() - 0.5) * 2
  end

  ---------------------------------------------------------------- 曳光、枪口火光

  local TRACER = { m4 = RGB(255, 220, 140), rifle = RGB(255, 220, 140), lmg = RGB(255, 190, 110), sniper = RGB(255, 245, 210),
    hmg = RGB(255, 96, 52), coax = RGB(255, 150, 70) }
  -- 车载机枪（遥控武器站的 M2、并列机枪）：曳光弹粗、长、亮，外面再套一层淡的光晕，飞得慢一点看得清（用户：机枪开火子弹要明显、要有曳光弹）
  local HEAVY = { hmg = { r = 0.32, len = 30, glow = 1.1, speed = 640 }, coax = { r = 0.24, len = 24, glow = 0.8, speed = 700 } }
  -- 一卡一卡（用户 11-18）：几十个机器人一起开枪，每一发都新建曳光、枪口火、灯光、弹着点的灰——一秒几百个零件加补间。
  --   别人打的：枪口离镜头 900 格外、弹道也没从镜头 300 格内擦过的不画；350 格外的只画曳光（不点灯、没有枪口火球和弹着灰）；
  --   画全套的每秒最多 50 发（多出来的也只画曳光）。自己打的照旧全画
  local gunTok, gunTokT = 50, 0
  local impact, probeAt   -- 弹着点（下面「弹着点」一节）
  local IMPK = { hmg = 1.7, coax = 1.4, ciws = 2, agun = 2, ac = 2, sniper = 1.3, lmg = 1.1 }   -- 弹着点的大小（按口径：步枪 1）
  -- h：打在什么上面（HitSurf 代号；别人打的服务器给，nil 是什么都没打中；自己打的不给，本地探一下）
  function G.gunFx(id, a, b, mine, h, quiet)
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
    local hv = HEAVY[id]
    local len = math.min(L, hv and hv.len or 14)
    local r = hv and hv.r or 0.12
    local speed = hv and hv.speed or 900
    local tr = part(nil, V(r, r, len), CFrame.lookAt(a + d.Unit * len / 2, b), col, Enum.Material.Neon, hv and 0 or 0.1)
    local tw = tween(tr, L / speed, { CFrame = CFrame.lookAt(b - d.Unit * len / 2, b + d.Unit) }, Enum.EasingStyle.Linear)
    Debris:AddItem(tr, L / speed + 0.05)
    if hv and not lite then   -- 光晕：同一条线上粗一圈、很淡
      local gl = part(nil, V(hv.glow, hv.glow, len * 0.8), CFrame.lookAt(a + d.Unit * len / 2, b), col, Enum.Material.Neon, 0.78)
      tween(gl, L / speed, { CFrame = CFrame.lookAt(b - d.Unit * len * 0.4, b + d.Unit) }, Enum.EasingStyle.Linear)
      Debris:AddItem(gl, L / speed + 0.05)
    end
    if not lite and not quiet then   -- 消音器：没有枪口那团火
      local fl = part(BALL, V(0.9, 0.9, 0.9), CFrame.new(a), RGB(255, 210, 120), Enum.Material.Neon, 0.2)
      tween(fl, 0.06, { Transparency = 1, Size = V(1.4, 1.4, 1.4) })
      Debris:AddItem(fl, 0.08)
      if id ~= "smgsd" and not quiet then flash(a, RGB(255, 196, 120), 14, 3.2, 0.07) end   -- 枪口焰照亮四周（消音的没有）
    end
    -- 弹着点（原来不管打中什么都是一小团灰，打到天上也有）：按打中的东西画，曳光飞到了才出；
    --   远处只画钢甲上的火花（看得见）。打中的零件记下来，飞到时按它现在的位置画（车在走，火花跟着车身）
    if not lite or (h and HitSurf.METAL[h]) then
      local du = d.Unit
      local res = (h or mine) and probeAt(b, du) or nil
      if mine and h == nil and res then h = HitSurf.of(res.Instance, res.Material) end
      if h then
        local hp, rel, nl = nil, nil, nil
        if res then
          hp = res.Instance
          rel, nl = hp.CFrame:PointToObjectSpace(res.Position), hp.CFrame:VectorToObjectSpace(res.Normal)
        end
        local k = IMPK[id] or 1
        task.delay(L / speed, function()
          local p, nrm = b, nil
          if hp and hp.Parent then p, nrm = hp.CFrame * rel, hp.CFrame:VectorToWorldSpace(nl) end
          impact(p, du, h, k, nrm)
        end)
      end
    end
    if mine and (id == "m4" or id == "sniper" or id == "rifle") then   -- 自己开的：耳边叠层的枪声，弹壳过一会儿落地
      G.sfx(quiet and ((id == "sniper") and "sniperSdMe" or "rifleSdMe") or ((id == "sniper") and "sniperMe" or "rifleMe"), nil, { must = true })
      if math.random() < 0.35 then G.sfx("brass", nil, { delay = 0.35 + math.random() * 0.25 }) end
      return
    end
    local snd = (id == "smgsd" or quiet) and "quiet" or ((id == "sniper" or id == "lmg" or id == "pistol") and id or "rifle")   -- 装了消音器的：闷响
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

  ---------------------------------------------------------------- 弹着点
  -- 用户：枪打在坦克上要有火花。按打中的东西（HitSurf：别人打的服务器给，自己打的本地判）：
  --   钢甲（坦克、步战车、舰艇）——白热的一闪 + 一蓬往外溅的火星（细长、带重力、一下就灭）+ 一小缕青烟，三成子弹跳弹（擦着打的六成：
  --     一小段曳光斜着飞走），「叮」的一声（重机枪、航炮是低一点的「当」）；轻型车、飞机：火星少一点；炮弹直接命中（服务器的 spark）一大团；
  --   土、草地——往上踢起一股土和碎渣；沙——黄沙；石头、水泥、工事——灰尘、碎屑，偶尔一两颗火星；木头——木屑；水——一股细水柱；人——一小团灰
  --   粒子发射器常驻（每种一个看不见的小零件，打中了挪过去、朝该溅的方向 Emit，飞出去的粒子留在原地），不每发都新建零件；每秒最多 40 处
  local IMP = {}
  local function impEmitter(name, o)
    local h = part(nil, V(0.2, 0.2, 0.2), CFrame.new(0, -500, 0), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    h.Name = "Imp_" .. name
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.spd[1], o.spd[2])
    pe.SpreadAngle = Vector2.new(o.spread or 30, o.spread or 30)
    pe.Size = o.size
    pe.Transparency = o.tr
    pe.Color = o.col
    pe.Acceleration = o.acc or V()
    pe.Drag = o.drag or 0
    pe.LightEmission = o.le or 0
    pe.LightInfluence = (o.le or 0) > 0.5 and 0 or 1
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-(o.rot or 0), o.rot or 0)
    pe.ZOffset = o.z or 0
    pe.EmissionDirection = Enum.NormalId.Top
    if o.streak then   -- 火星：顺着飞的方向拉成细长一道（Squash：老版本没有这个属性就算了）
      pe.Orientation = Enum.ParticleOrientation.VelocityParallel
      pe.Rotation = NumberRange.new(0)
      pcall(function() pe.Squash = o.streak end)
    end
    if o.bright then pe.Brightness = o.bright end
    pe.Parent = h
    IMP[name] = { h = h, pe = pe, spd = o.spd }
  end
  local SPARK_C = cseq(RGB(255, 250, 225), RGB(255, 132, 36))
  impEmitter("spark", { tex = TX.glow, life = { 0.12, 0.36 }, spd = { 22, 60 }, spread = 62, size = nseq(0, 0.3, 0.6, 0.2, 1, 0),
    tr = nseq(0, 0, 0.7, 0.15, 1, 1), col = SPARK_C, acc = V(0, -70, 0), drag = 3.5, le = 1, bright = 4, streak = nseq(0, 2.6, 1, 1.4), z = 0.5 })
  impEmitter("spark2", { tex = TX.glow, life = { 0.18, 0.55 }, spd = { 26, 72 }, spread = 70, size = nseq(0, 0.5, 0.6, 0.32, 1, 0),
    tr = nseq(0, 0, 0.7, 0.15, 1, 1), col = SPARK_C, acc = V(0, -70, 0), drag = 3, le = 1, bright = 5, streak = nseq(0, 2.8, 1, 1.5), z = 0.5 })
  impEmitter("flash", { tex = TX.glow, life = { 0.05, 0.08 }, spd = { 0, 0 }, spread = 0, size = nseq(0, 1.3, 1, 2.4),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 240), RGB(255, 205, 130)), le = 1, bright = 5, z = 1 })
  impEmitter("flash2", { tex = TX.glow, life = { 0.06, 0.1 }, spd = { 0, 0 }, spread = 0, size = nseq(0, 2.6, 1, 4.6),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 240), RGB(255, 200, 120)), le = 1, bright = 6, z = 1 })
  impEmitter("flash3", { tex = TX.glow, life = { 0.08, 0.13 }, spd = { 0, 0 }, spread = 0, size = nseq(0, 5, 1, 10),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 245), RGB(255, 190, 100)), le = 1, bright = 7, z = 1 })
  impEmitter("smoke", { tex = TX.smoke, life = { 0.5, 0.9 }, spd = { 1.5, 4 }, spread = 25, size = nseq(0, 0.5, 1, 2.4),
    tr = nseq(0, 0.55, 1, 1), col = cseq(RGB(150, 150, 146), RGB(118, 118, 116)), acc = V(0, 3, 0), drag = 2, rot = 30 })
  impEmitter("dirt", { tex = TX.smoke, life = { 0.35, 0.8 }, spd = { 8, 18 }, spread = 22, size = nseq(0, 0.6, 0.4, 1.8, 1, 2.8),
    tr = nseq(0, 0.25, 0.6, 0.55, 1, 1), col = cseq(RGB(112, 92, 66), RGB(148, 128, 98)), acc = V(0, -24, 0), drag = 2.5, rot = 40 })
  impEmitter("sand", { tex = TX.smoke, life = { 0.4, 0.9 }, spd = { 8, 18 }, spread = 24, size = nseq(0, 0.6, 0.4, 1.9, 1, 3),
    tr = nseq(0, 0.25, 0.6, 0.55, 1, 1), col = cseq(RGB(212, 188, 138), RGB(228, 210, 170)), acc = V(0, -22, 0), drag = 2.5, rot = 40 })
  impEmitter("rock", { tex = TX.smoke, life = { 0.4, 0.85 }, spd = { 6, 15 }, spread = 26, size = nseq(0, 0.5, 0.4, 1.6, 1, 2.6),
    tr = nseq(0, 0.3, 0.6, 0.6, 1, 1), col = cseq(RGB(150, 148, 142), RGB(186, 183, 176)), acc = V(0, -10, 0), drag = 2.5, rot = 40 })
  impEmitter("chips", { tex = TX.chunk, life = { 0.3, 0.6 }, spd = { 14, 30 }, spread = 35, size = nseq(0, 0.22, 1, 0.12),
    tr = nseq(0, 0, 1, 0.4), col = cseq(RGB(72, 64, 54), RGB(72, 64, 54)), acc = V(0, -90, 0), drag = 1, rot = 360 })
  impEmitter("spout", { tex = TX.smoke, life = { 0.35, 0.6 }, spd = { 16, 26 }, spread = 7, size = nseq(0, 0.35, 0.5, 0.8, 1, 1.3),
    tr = nseq(0, 0.15, 0.7, 0.5, 1, 1), col = cseq(RGB(236, 243, 246), RGB(220, 230, 236)), acc = V(0, -75, 0), drag = 1, rot = 20 })
  impEmitter("mist", { tex = TX.smoke, life = { 0.4, 0.7 }, spd = { 2, 5 }, spread = 60, size = nseq(0, 0.8, 1, 2.4),
    tr = nseq(0, 0.5, 1, 1), col = cseq(RGB(230, 238, 242), RGB(215, 225, 232)), drag = 2, rot = 20 })

  -- 让零件的 +Y（粒子往外飞的方向）朝 up
  local function upCF(p, up)
    local r = up:Cross((math.abs(up.Y) < 0.95) and V(0, 1, 0) or V(1, 0, 0)).Unit
    return CFrame.fromMatrix(p, r, up)
  end
  local function fire(name, cf, n, k)
    local e = IMP[name]
    if not e or n < 1 then return end
    e.h.CFrame = cf
    k = k or 1
    e.pe.Speed = NumberRange.new(e.spd[1] * k ^ 0.5, e.spd[2] * k ^ 0.5)   -- 大口径溅得远一点
    e.pe:Emit(math.floor(n + 0.5))
  end

  -- 弹着点打中的是什么零件、朝哪（沿弹道在落点前后各探 3 格）：客户端的样子（View 的文件夹）、特效、自己的角色不算
  local probe = RaycastParams.new()
  probe.FilterType = Enum.RaycastFilterType.Exclude
  probeAt = function(b, du)
    local ex = { FXF }
    if G.viewFolder then ex[#ex + 1] = G.viewFolder end
    if me.Character then ex[#ex + 1] = me.Character end
    probe.FilterDescendantsInstances = ex
    return workspace:Raycast(b - du * 3, du * 6, probe)
  end

  local impSndT, impSndN = 0, 0
  local function impactSound(p, d, kind)
    if d > ((kind == "thud") and 90 or 260) then return end
    local t = os.clock()
    if t - impSndT > 0.25 then impSndT, impSndN = t, 0 end
    if impSndN >= 4 then return end
    impSndN += 1
    G.sfx(kind, p, { vol = math.max(0.25, 1 - d / 320), rmin = 10, rmax = 320 })
  end

  -- 跳弹：一小段曳光从弹着点斜着飞走（每秒最多 12 道）
  local ricT, ricN = 0, 0
  local function ricochet(p, refl, k, d)
    local t = os.clock()
    if t - ricT > 1 then ricT, ricN = t, 0 end
    if ricN >= 12 then return end
    ricN += 1
    local rd = refl + V((math.random() - 0.5) * 0.9, math.random() * 0.5, (math.random() - 0.5) * 0.9)
    rd = (rd.Magnitude > 1e-3) and rd.Unit or refl
    local len = 2.6 * math.min(k, 1.6)
    local dist = 50 + math.random() * 60
    local dur = dist / 280
    local r = 0.09 * math.min(k, 1.8)
    local tr = part(nil, V(r, r, len), CFrame.lookAt(p + rd * len / 2, p + rd * (len + 1)), RGB(255, 205, 130), Enum.Material.Neon, 0.05)
    tween(tr, dur, { CFrame = CFrame.lookAt(p + rd * (dist - len / 2), p + rd * (dist + 1)), Transparency = 0.9 }, Enum.EasingStyle.Linear)
    Debris:AddItem(tr, dur + 0.05)
    if d < 150 and math.random() < 0.35 then G.sfx("ric", p, { vol = 0.8, rmin = 10, rmax = 200 }) end
  end

  local impTok, impTokT = 40, 0
  -- p 弹着点、du 弹道方向、h 打在什么上面（HitSurf）、k 大小（步枪 1、重机枪 1.7、航炮 2、炮弹 3 上下）、nrm 表面朝向（没探到就当正对着打）
  impact = function(p, du, h, k, nrm)
    if not h then return end
    local d = (p - cam.CFrame.Position).Magnitude
    if d > 900 then return end
    local t = os.clock()
    impTok = math.min(40, impTok + (t - impTokT) * 40)
    impTokT = t
    if impTok < 1 then return end
    impTok -= 1
    nrm = nrm or -du
    if HitSurf.METAL[h] then
      local steel = h == "a" or h == "s"
      local tier = (k >= 2.5 and 3) or (k >= 1.5 and 2) or 1
      local refl = du - 2 * du:Dot(nrm) * nrm
      local sd = nrm + refl * 0.7   -- 火星往外溅：在法线和反弹方向之间
      sd = (sd.Magnitude > 1e-3) and sd.Unit or nrm
      local far = d > 250 and 0.5 or 1
      fire((tier > 1) and "spark2" or "spark", upCF(p + nrm * 0.15, sd), (steel and 12 or 7) * k * far, k)
      fire(((tier == 3) and "flash3") or ((tier == 2) and "flash2") or "flash", upCF(p + nrm * 0.2, nrm), 1)
      if d < 300 then fire("smoke", upCF(p + nrm * 0.3, nrm), (tier == 3) and 4 or (steel and 1 or 2)) end
      if tier > 1 and d < 400 then flash(p + nrm * 0.6, RGB(255, 222, 165), 8 * k, 2.4, 0.06) end   -- 夜里照亮一下车身
      if steel and d < 600 then
        local graze = math.abs(du:Dot(nrm)) < 0.5
        if math.random() < (graze and 0.6 or 0.3) then ricochet(p, refl, k, d) end
      end
      impactSound(p, d, (tier > 1) and "clang" or "ping")
    elseif h == "w" then
      fire("spout", upCF(p, V(0, 1, 0)), 7 * k, k)
      fire("mist", upCF(p, V(0, 1, 0)), 2)
    else
      local cf = upCF(p + nrm * 0.1, (nrm + V(0, 0.35, 0)).Unit)
      local name = ((h == "n") and "sand") or ((h == "r" or h == "c" or h == "g") and "rock") or "dirt"
      fire(name, cf, (h == "f") and 1 or 3 * k, k)
      if h ~= "f" and d < 250 then fire("chips", cf, ((h == "o") and 7 or 4) * k, k) end
      if (h == "r" or h == "c") and math.random() < 0.25 then fire("spark", upCF(p + nrm * 0.1, nrm), 3, 0.8) end   -- 打在石头上偶尔迸一两颗火星
      if h ~= "f" then impactSound(p, d, "thud") end
    end
  end
  G.impact = impact   -- 测试用

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
    if c ~= "gun" then   -- 真录音的爆炸：按大小挑（水里照旧叠一层水声）
      local RL = realLayer((r < 13 and "boomS") or (r < 26 and "boomM") or "boomL", (c == "bomb") and 0.92 or 1, 1)
      if RL then L = water and { RL, { id = WATER, vol = 0.9, s = { 0.62, 0.72 }, delay = 0.06 } } or { RL } end
    end
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
      if G.concuss then G.concuss(d, r, c) end   -- 近处：耳鸣、发闷、一白一糊（Shock.lua）
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
      if not mine(e) and not aw.hyper then G.sfx((kind == "missile") and "msl" or "bombRel", e.p) end
      flying[e.id] = { wm = mdl, glow = glow, half = (aw.shape and aw.shape.L or 5) / 2, p = e.p, v = e.v, gb = kind == "bomb", t = 0, kind = kind, trailT = 0,
        burn = aw.burn or 4, cfs = table.create(#mdl.parts), tg = e.tg, w = e.w, my = mine(e) }   -- my：自己打出去的（Marks.lua 给自己的炸弹标落点）
      if aw.hyper and glow then   -- 高超音速（惊雷-1）：先掉一下不点火；点火后一大团白热尾焰 + 一条很长的尾迹（速度太快，一颗颗烟球连不起来）
        local fs = flying[e.id]
        fs.hyper, fs.lit = true, false
        glow.Size = V(5, 5, 5)
        local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
        a0.Position, a1.Position = V(0, 1.6, 0), V(0, -1.6, 0)
        a0.Parent, a1.Parent = glow, glow
        local tr = Instance.new("Trail")
        tr.Attachment0, tr.Attachment1 = a0, a1
        tr.Lifetime = 3.2
        tr.MinLength = 2
        tr.FaceCamera = true
        tr.LightEmission = 0.6
        tr.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 236, 200)), ColorSequenceKeypoint.new(0.15, RGB(255, 170, 90)), ColorSequenceKeypoint.new(1, RGB(210, 210, 214)) })
        tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) })
        tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.2) })
        tr.Enabled = false
        tr.Parent = glow
        fs.trail = tr
        glow.Transparency = 1
      end
      if glow then addRoar(flying[e.id], glow, e.p) end
      if mine(e) and G.onMyShot then G.onMyShot(e) end   -- 自己打出去的：导弹视角小窗（MslCam.lua）
      return
    end
    local body
    if kind == "shell" then   -- 炮弹：一道亮的曳光
      local big = e.f == "tank"
      body = part(CYL, big and V(5, 0.45, 0.45) or V(2.6, 0.22, 0.22), CFrame.new(e.p), big and RGB(255, 236, 190) or RGB(255, 200, 120), Enum.Material.Neon, 0)
      if big then glowOn(body, RGB(255, 220, 170), 10, 2) end
      -- 坦克炮弹的曳光管（用户 11-22 晚：开镜开炮看得见炮弹从左上方落下去）：一两公里外弹体不到一个像素，
      --   曳光管是一个一直这么大的亮点（屏幕上几个像素，越远越看得见光点、看不出大小），被地形、车挡住就看不见；飞两三秒烧完
      if big and e.tr then
        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(9, 9)
        bb.LightInfluence = 0
        bb.AlwaysOnTop = false
        bb.MaxDistance = 20000
        pcall(function() bb.Brightness = 3 end)
        bb.Adornee = body
        local dotF = Instance.new("Frame")
        dotF.AnchorPoint = Vector2.new(0.5, 0.5)
        dotF.Position = UDim2.fromScale(0.5, 0.5)
        dotF.Size = UDim2.fromScale(1, 1)
        dotF.BackgroundColor3 = RGB(255, 132, 70)
        dotF.BorderSizePixel = 0
        local cr = Instance.new("UICorner")
        cr.CornerRadius = UDim.new(0.5, 0)
        cr.Parent = dotF
        local core = dotF:Clone()
        core.Size = UDim2.fromScale(0.45, 0.45)
        core.BackgroundColor3 = RGB(255, 236, 200)
        core.Parent = dotF
        dotF.Parent = bb
        bb.Parent = body
      end
      flying[e.id] = { body = body, p = e.p, v = e.v, g = e.g, gs = e.gs or 1, dr = e.dr, t = 0, kind = kind, trailT = 0, tracer = big and e.tr or nil }
      if G.onTankShot and big then pcall(G.onTankShot, e, flying[e.id]) end   -- 测试用：火控测试看曳光弹在镜里怎么走
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
  -- 核导弹的弹道（同服务器 Nuke.lua：三次贝塞尔曲线，进度 u = 0.55x + 0.45x²）：按收到 nukePath 以后过了多久算位置、速度
  local function pathAt(s)
    local P = s.path
    local x = math.clamp((os.clock() - s.pathT0) / s.pathTf, 0, 1)
    local u = 0.55 * x + 0.45 * x * x
    local a = 1 - u
    local pos = P[1] * (a * a * a) + P[2] * (3 * a * a * u) + P[3] * (3 * a * u * u) + P[4] * (u * u * u)
    local d = (P[2] - P[1]) * (3 * a * a) + (P[3] - P[2]) * (6 * a * u) + (P[4] - P[3]) * (3 * u * u)
    return pos, d * ((0.55 + 0.9 * x) / s.pathTf)
  end
  local function stepShots(dt)
    for id, s in pairs(flying) do
      s.t += dt
      if s.g then s.v += GRAV * (s.gs or 1) * dt end
      if s.dr then s.v -= s.v * math.min(0.5, s.dr * s.v.Magnitude * dt) end   -- 空气阻力（同服务器 Ents.lua，坦克炮弹）
      if s.gb then s.v += V(0, -27.5, 0) * dt end   -- 机载炸弹：AirDefs.GRAV
      s.p += s.v * dt
      if s.path then
        local pv, vv = pathAt(s)
        s.p = pv
        if vv.Magnitude > 1 then s.v = vv end
      end
      if s.wm then   -- 按型号拼的弹：整枚一起挪，导弹尾焰烧完就灭、尾烟跟着淡
        local cf = CFrame.lookAt(s.p, s.p + ((s.v.Magnitude > 0.1) and s.v or V(0, -1, 0)))
        for i, o in ipairs(s.wm.offs) do s.cfs[i] = cf * o end
        workspace:BulkMoveTo(s.wm.parts, s.cfs, Enum.BulkMoveMode.FireCFrameChanged)
        local burning = s.t < s.burn
        if s.hyper then burning = s.lit end
        if not burning and s.roar then stopRoar(s) end
        if s.glow then
          s.glow.CFrame = cf * CFrame.new(0, 0, s.half + (s.hyper and 2.5 or 0.5))
          s.glow.Transparency = burning and 0 or 1
        end
        if s.hyper then   -- 高超音速：尾迹交给 Trail；俯冲时弹头烧得发红（等离子体）
          if s.trail then s.trail.Enabled = s.lit end
          if s.lit and s.v.Y < -1500 and not s.plasma and s.wm.parts[1] then
            s.plasma = true
            for _, q in ipairs(s.wm.parts) do q.Color = q.Color:Lerp(RGB(255, 140, 70), 0.55) q.Material = Enum.Material.Neon end
          end
        elseif s.kind == "missile" then
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
        if s.tracer and not s.burnt and s.t > 3.2 then   -- 曳光管烧完了（约 3 秒、四五公里）
          s.burnt = true
          local g = s.body:FindFirstChildOfClass("BillboardGui")
          if g then g.Enabled = false end
        end
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
      if s.t > ((s.kind == "bomb") and 40 or (s.hyper and 95 or 15)) then endShot(id) end
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
    if not s or s.path or typeof(e.p) ~= "Vector3" or typeof(e.v) ~= "Vector3" then return end
    if (s.p - e.p).Magnitude > 60 then s.p = e.p else s.p = s.p:Lerp(e.p, 0.6) end
    s.v = e.v
  end
  -- 热诱弹：一串亮点往后下方撒开，拖着白烟
  local function flares(e)   -- 一组几发（按住 X 连续放：服务器每 0.25 秒一组 2 发）
    local v0 = (typeof(e.v) == "Vector3") and e.v or V()
    for i = 1, (e.n or 4) do
      local dir = (-v0.Unit * 0.4 + V((math.random() - 0.5) * 1.6, -0.4 - math.random() * 0.4, (math.random() - 0.5) * 1.6)).Unit
      local f = part(BALL, V(1.4, 1.4, 1.4), CFrame.new(e.p), RGB(255, 236, 170), Enum.Material.Neon, 0)
      local p1 = e.p + v0 * 0.35 + dir * (40 + i * 8)
      tween(f, 1.8, { CFrame = CFrame.new(p1 - V(0, 30, 0)), Transparency = 1, Size = V(0.6, 0.6, 0.6) })
      if i <= 2 then tween(glowOn(f, RGB(255, 222, 160), 34, 5), 1.8, { Brightness = 0 }) end   -- 夜里热诱弹把飞机照亮
      Debris:AddItem(f, 1.85)
      for k = 1, 3 do   -- 每发拖三团烟（连着放时零件不至于太多）
        task.delay(k * 0.3, function()
          local q = e.p:Lerp(p1, k / 3) - V(0, 30 * (k / 3) ^ 2, 0)
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

  -- 车炮开火（用户：开火动画做的好一点）：
  --   小口径：一小团火光 + 枪声；
  --   坦克炮、自行火炮：顺着炮管拉长的火球（外面再一层橙色的）、炮口制退器两边横喷的火（十字形的闪）、垂直炮管一下子撑开的激波圈、
  --   向前喷一股快烟 + 一大团挂在空中慢慢飘上去的硝烟（开炮后前面一下子看不清，战雷那样）、炮口下面地上掀起的一圈土（在水上是水雾）、
  --   照亮四周的闪光、闷响 + 脆响 + 回声；炮管后坐、车体一晃（View 的 vehRecoil）；离得近震屏
  local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
  local function emitter(holder, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex or SMOKE_TEX
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.speed[1], o.speed[2])
    pe.SpreadAngle = Vector2.new(o.spread, o.spread)
    pe.Drag = o.drag or 0
    pe.Acceleration = o.acc or V()
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.size[1]), NumberSequenceKeypoint.new(1, o.size[2]) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.tr or 0.3), NumberSequenceKeypoint.new(1, 1) })
    pe.Color = ColorSequence.new(o.color)
    pe.RotSpeed = NumberRange.new(-40, 40)
    pe.Rotation = NumberRange.new(0, 360)
    pe.LightEmission = o.glow or 0
    pe.EmissionDirection = o.dir or Enum.NormalId.Front
    pe.Parent = holder
    pe:Emit(math.max(1, math.floor(o.n * math.clamp(G.perfK or 1, 0.4, 1.2) + 0.5)))
    return pe
  end
  G.emitBurst = emitter
  -- 炮弹打在钢甲上（用户 11-21：打中目标，如果是金属也要有火花）：再迸一大把亮的火星（比子弹的大、飞得远、带重力落下），一下白热的闪光
  local function hotSparks(p, n, s)
    if (p - cam.CFrame.Position).Magnitude > 1500 then return end
    local h = part(nil, V(0.2, 0.2, 0.2), CFrame.lookAt(p + n * 0.3, p + n * 2), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    emitter(h, { tex = TX.glow, life = { 0.35, 1.1 }, speed = { 40, 120 }, spread = 65, drag = 0.8, acc = V(0, -90, 0), size = { 0.7, 0 }, tr = 0, color = RGB(255, 222, 150), glow = 1, n = math.floor(22 * s) })
    emitter(h, { tex = TX.glow, life = { 0.08, 0.14 }, speed = { 0, 0 }, spread = 0, size = { 3 * s, 5.5 * s }, tr = 0, color = RGB(255, 245, 220), glow = 1, n = 1 })
    Debris:AddItem(h, 1.5)
  end
  local function vfire(e)
    local big = e.f == "tank" or e.f == "arty"
    local dir = (typeof(e.d) == "Vector3") and e.d.Unit or V(0, 0, -1)
    local dd = (e.p - cam.CFrame.Position).Magnitude
    if not big then
      local fl = part(BALL, V(1.6, 1.6, 1.6), CFrame.new(e.p + dir * 0.6), RGB(255, 210, 120), Enum.Material.Neon, 0)
      tween(fl, 0.06, { Transparency = 1, Size = V(3, 3, 3) })
      Debris:AddItem(fl, 0.08)
      flash(e.p + dir, RGB(255, 190, 110), 16, 4, 0.1)
      G.playSound("lmg", e.p)
      if G.vehRecoil and e.id then G.vehRecoil(e.id, e.g) end
      return
    end
    local look = CFrame.lookAt(e.p, e.p + dir)
    local near = dd < 1100   -- 远了只画火光、出声
    -- ① 火球：顺着炮管拉长的白热一团 + 外面一层橙色的，0.1 秒内胀大、透明
    local core = part(BALL, V(2.4, 2.4, 7), look * CF(0, 0, -4.5), RGB(255, 240, 190), Enum.Material.Neon, 0)
    tween(core, 0.1, { Size = V(4, 4, 13), Transparency = 1, CFrame = look * CF(0, 0, -7) })
    Debris:AddItem(core, 0.12)
    local outer = part(BALL, V(5, 5, 6), look * CF(0, 0, -3), RGB(255, 150, 60), Enum.Material.Neon, 0.2)
    tween(outer, 0.16, { Size = V(11, 11, 13), Transparency = 1 })
    Debris:AddItem(outer, 0.18)
    -- ② 炮口制退器两边横喷的火
    for sx = -1, 1, 2 do
      local j = part(BALL, V(1.2, 1.2, 4), look * CF(sx * 2.1, 0, -0.6) * CFrame.Angles(0, sx * math.rad(78), 0), RGB(255, 205, 130), Enum.Material.Neon, 0.1)
      tween(j, 0.08, { Size = V(1.8, 1.8, 7.5), Transparency = 1 })
      Debris:AddItem(j, 0.1)
    end
    flash(e.p + dir * 3, RGB(255, 186, 104), 64, 13, 0.32)
    if near then
      -- ③ 激波圈：垂直炮管的薄圆盘（圆柱的轴转到炮管方向），一下子撑开
      local disc = part(CYL, V(0.25, 3, 3), look * CF(0, 0, -2.5) * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 236, 214), Enum.Material.SmoothPlastic, 0.55)
      tween(disc, 0.18, { Size = V(0.25, 24, 24), Transparency = 1 })
      Debris:AddItem(disc, 0.2)
      -- ④ 炮口烟：快的一股往前喷，慢的一大团挂着往上飘
      local holder = part(nil, V(0.2, 0.2, 0.2), look * CF(0, 0, -1.5), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
      emitter(holder, { life = { 1.1, 2.4 }, speed = { 16, 40 }, spread = 22, drag = 3.2, size = { 2.5, 11 }, tr = 0.25, color = RGB(214, 208, 196), n = 16 })
      emitter(holder, { life = { 3.5, 6 }, speed = { 2, 9 }, spread = 70, drag = 1.1, acc = V(0, 1.4, 0), size = { 5, 19 }, tr = 0.4, color = RGB(170, 164, 154), n = 10 })
      emitter(holder, { tex = "rbxasset://textures/particles/sparkles_main.dds", life = { 0.15, 0.4 }, speed = { 40, 80 }, spread = 12, size = { 0.5, 0.2 }, tr = 0, color = RGB(255, 210, 130), glow = 1, n = 12 })
      -- 炮口迸出的火星（用户 11-21：炮弹飞出炮管要有火花）：顺着炮管往前喷一大把白热的火星（带重力往下掉、一下就暗），
      --   制退器两边也横着喷一点
      emitter(holder, { tex = TX.glow, life = { 0.25, 0.75 }, speed = { 70, 170 }, spread = 10, drag = 1.2, acc = V(0, -70, 0), size = { 0.6, 0 }, tr = 0, color = RGB(255, 216, 146), glow = 1, n = 36 })
      for sx = -1, 1, 2 do
        local side = part(nil, V(0.2, 0.2, 0.2), look * CF(sx * 1.6, 0, -0.6) * CFrame.Angles(0, sx * math.rad(78), 0), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
        emitter(side, { tex = TX.glow, life = { 0.15, 0.45 }, speed = { 40, 95 }, spread = 16, drag = 2, acc = V(0, -60, 0), size = { 0.45, 0 }, tr = 0, color = RGB(255, 196, 120), glow = 1, n = 10 })
        Debris:AddItem(side, 1)
      end
      Debris:AddItem(holder, 6.5)
      -- ⑤ 地上一圈掀起来的土（炮口离地不高才有；水上是白的水雾）
      local gy = G.Map and G.Map.ground and G.Map.ground(e.p.X, e.p.Z) or (e.p.Y - 4)
      if e.p.Y - gy < 10 then
        local wet = gy <= 0.2
        local col = wet and RGB(220, 230, 236) or RGB(176, 156, 120)
        local gp = V(e.p.X + dir.X * 3, gy + 0.6, e.p.Z + dir.Z * 3)
        local dust = part(nil, V(0.2, 0.2, 0.2), CFrame.lookAt(gp, gp + V(0, 1, 0)), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
        emitter(dust, { life = { 1, 2.6 }, speed = { 12, 30 }, spread = 80, drag = 2.8, acc = V(0, -5, 0), size = { 2, 10 }, tr = 0.3, color = col, n = 24 })
        Debris:AddItem(dust, 3)
        local ring = part(CYL, V(0.4, 6, 6), CFrame.new(gp) * CFrame.Angles(0, 0, math.pi / 2), col, Enum.Material.SmoothPlastic, 0.5)
        tween(ring, 0.55, { Size = V(0.4, 40, 40), Transparency = 1 })
        Debris:AddItem(ring, 0.6)
      end
    end
    -- ⑥ 声音：脆响 + 低沉的轰隆 + 回声（远处的晚一点到、高音被吃掉）
    G.sfx("tankGun", e.p, { must = true, rmax = 2600, delay = dd / 1100, hiCut = -math.min(18, dd / 80) })
    if G.vehRecoil and e.id then G.vehRecoil(e.id, e.g) end
    if dd < 200 then G.shake(0.38 * (1 - dd / 200)) end
  end

  -- 跳弹（用户：跳弹也做出来）：服务器判了打得太斜、弹头滑开——迸一串火星（顺着跳出去的方向拉成一溜）、一点白烟、「当」一声 + 尖啸飞走；
  --   飞着的曳光改走跳出去的方向（服务器给新的位置和速度）
  G.ricochetCount = 0   -- 测试用
  local function shellRicochet(e)
    if typeof(e.p) ~= "Vector3" then return end
    G.ricochetCount += 1
    local out = (typeof(e.v) == "Vector3" and e.v.Magnitude > 0.1) and e.v.Unit or V(0, 1, 0)
    local n = (typeof(e.n) == "Vector3") and e.n or out
    local holder = part(nil, V(0.2, 0.2, 0.2), CFrame.lookAt(e.p, e.p + out), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    emitter(holder, { tex = "rbxasset://textures/particles/sparkles_main.dds", life = { 0.25, 0.7 }, speed = { 50, 110 }, spread = 16, acc = V(0, -50, 0), size = { 0.55, 0.2 }, tr = 0, color = RGB(255, 226, 150), glow = 1, n = 40 })
    emitter(holder, { tex = "rbxasset://textures/particles/sparkles_main.dds", life = { 0.2, 0.5 }, speed = { 15, 45 }, spread = 70, acc = V(0, -60, 0), size = { 0.4, 0.15 }, tr = 0, color = RGB(255, 180, 90), glow = 1, n = 18 })
    emitter(holder, { life = { 0.8, 1.6 }, speed = { 3, 9 }, spread = 50, drag = 2, size = { 1.2, 5 }, tr = 0.45, color = RGB(200, 196, 190), n = 6 })
    Debris:AddItem(holder, 2)
    local glint = part(BALL, V(1.6, 1.6, 1.6), CFrame.new(e.p + n * 0.3), RGB(255, 246, 220), Enum.Material.Neon, 0)
    tween(glint, 0.12, { Size = V(3.5, 3.5, 3.5), Transparency = 1 })
    Debris:AddItem(glint, 0.14)
    flash(e.p, RGB(255, 220, 160), 20, 6, 0.15)
    G.sfx("shellRic", e.p, { must = true, rmax = 700 })
    local s = e.id and flying[e.id]
    if s and typeof(e.v) == "Vector3" then s.p, s.v = e.p, e.v end
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
    if G.pipSmoke then G.pipSmoke(e.p, e.r or 20, life + 6) end   -- 瞄准镜画中画里补几团灰球（不然开镜能看穿烟）
    Debris:AddItem(holder, life + 12)
  end

  -- 垂发：舱口一团火光、往上翻的一大团白烟（防空导弹的小一点）
  local function vls(e)
    local s = e.sam and 0.7 or 1
    -- 船上掀开那一格垂发的舱盖 / 发射箱箱口崩盖子、箱尾喷气（ShipView.lua）
    local v = e.id and G.viewById and G.viewById(e.id)
    if v and v.ext and v.ext.launch then G.try_(v.ext.launch, v, e) end
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
        if e.mi and e.id then   -- 舰艇的近防炮：那一座转向目标（ShipView.lua）
          local v = G.viewById and G.viewById(e.id)
          if v and v.ext and v.ext.ciws then G.try_(v.ext.ciws, v, e.mi, e.b) end
        end
        if e.ent then   -- 机器人开的枪：小兵后坐、枪口焰，曳光从它的枪口出来（Soldier.lua）
          if G.vehRecoil then G.vehRecoil(e.ent) end
          local mz = G.botMuzzle and G.botMuzzle(e.ent)
          if mz and (mz - e.a).Magnitude < 8 then e.a = mz end
        end
        if e.by ~= me.UserId then
          nearMiss(e)
          G.gunFx(e.w, e.a, e.b, false, e.h, e.q)
          if G.radarShot then G.radarShot(e.a, e.t, e.q) end   -- 雷达：敌人开枪的地方闪一下（Hud.lua）
        end
      elseif k == "boom" then boom(e.p, e.s, e.c)
      elseif k == "spark" then   -- 炮弹、航炮直接打在车、船、飞机上：钢甲上一大团火花（Ents.lua）
        if typeof(e.p) == "Vector3" then
          local n = (typeof(e.n) == "Vector3" and e.n.Magnitude > 0.5) and e.n.Unit or V(0, 1, 0)
          impact(e.p, -n, e.h or "a", (e.s or 1) * 1.6, n)
          if (e.s or 1) >= 1.5 then hotSparks(e.p, n, e.s) end   -- 炮弹打在钢甲上：再迸一大把亮的火星
        end
      elseif k == "shot" then
        newShot(e)
        local fs = flying[e.id]
        if fs then fs.by = e.by end   -- 谁打的（飞机的吊舱页面算自己投的弹的 TTI）
      elseif k == "nukeIgn" then   -- 核导弹助推器点火（服务器 Nuke.lua）
        local fs = flying[e.id]
        if fs then
          fs.lit = true
          if fs.glow then addRoar(fs, fs.glow, e.p, 1.6) end
        end
        if G.nukeEvent then (G.try_ or pcall)(G.nukeEvent, e) end
      elseif k == "nukePath" then   -- 核导弹点火后的弹道（按同一条曲线算，不用校正）
        local fs = flying[e.id]
        if fs and typeof(e.a) == "Vector3" and typeof(e.d) == "Vector3" then
          fs.path, fs.pathT0, fs.pathTf, fs.lit = { e.a, e.b, e.c, e.d }, os.clock(), e.tf or 5, true
        end
      elseif k == "nuke" or k == "nukeWarn" or k == "nukeDive" then
        if G.nukeEvent then (G.try_ or pcall)(G.nukeEvent, e) end
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
      elseif k == "ricochet" then shellRicochet(e)
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
