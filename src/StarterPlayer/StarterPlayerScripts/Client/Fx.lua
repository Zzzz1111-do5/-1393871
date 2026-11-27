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
  -- 特效共用的底子（VfxLib.lua，11-27）：粒子发射器池、闪光灯池、弹坑焦痕池、余火池、远近分档
  --   等 10 秒等不到就报错跳过（init.client.lua 每个模块单独 pcall）：地点里少了 VfxLib（脚本没换全）不能把后面的模块全卡死（项目 11-20 的规矩）
  local vlMod = script.Parent:WaitForChild("VfxLib", 10)
  if not vlMod then error("缺少 Client.VfxLib（脚本没换全？）") end
  local VL = require(vlMod).new(G, FXF)
  G.vfx = VL
  -- 夜战：一闪的光（枪口焰、炮口、爆炸）——VfxLib 的 8 盏灯轮着用（挂在 Attachment 上，亮度按 Quad Out 降到 0），不每次新建零件、灯、补间；
  --   一卡一卡（用户 11-18）：同时最多 8 盏、投影子的只 1 盏（要了 o.shadow 才给），离镜头太远（光照范围外再 400 格）的不点；Range 最大 120
  local function flash(p, color, range, bright, t, o) return VL.flash(p, color, range, bright, t, o) end
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
  -- 按实际帧率调「画多远、画多细」：每两秒算一次平均帧率，连着两次低于 50 帧就往下降一档（树林 Scenery、士兵 Soldier、爆炸粒子都乘 G.perfK），
  --   高于 58 帧慢慢升回去，最高 1.2（机器好的树林画得更远）。G.perfFixed 为真时不调（模拟测试）
  --   11-27（用户：M3 上要非常丝滑，目标 60 帧）：门槛从 40 / 57 提到 50 / 58——掉到五十几帧就开始少画，不等掉到 40
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
      if fps < 50 then
        low += 1
        if low >= 2 then k = math.max(0.55, k - ((fps < 28) and 0.15 or 0.08)) end
      else
        low = 0
        if fps > 58 then k = math.min(1.2, k + 0.04) end
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
    -- 树倒（钢城，Scenery.lua）：树干「咔」地断开（放慢的脆响 + 一小截低沉的爆裂）、倒下去带风的呼一声、落地「嘭」的一下闷响
    treeFall = { { id = TICK, vol = 1.3, s = { 0.5, 0.58 }, eq = { 6, 2, -6 } },
      { id = EXP, vol = 0.3, s = { 2.0, 2.3 }, reg = { 0.02, 0.2 }, eq = { 4, 2, -10 }, delay = 0.02 },
      { id = WIND, vol = 4, s = { 0.85, 0.95 }, reg = { 2, 3.1 }, eq = { 2, 4, -6 }, delay = 0.25, fade = 0.6 },
      { id = THUD, vol = 1.8, s = { 0.4, 0.45 }, eq = { 10, -2, -18 }, delay = 1.25 } },
    -- 音爆（AirFx.lua）：N 形波的头尾两声连着的低沉「嘭——嘭」，放慢、失真、削掉高音；远处的人按距离晚到
    sonic = { { id = EXP, vol = 1.2, s = { 0.5, 0.55 }, reg = { 0, 1.7 }, eq = { 10, 0, -16 }, dist = 0.55 },
      { id = EXP, vol = 1, s = { 0.47, 0.5 }, reg = { 0, 1.5 }, eq = { 10, -2, -18 }, dist = 0.55, delay = 0.14 } },
    -- 爽感（Juice.lua）：爆头——打在头盔上的一声脆「叮」；连杀——往上走的三声；低血量——一下一下的心跳
    headshot = { { id = TICK, vol = 1, s = { 3.3, 3.4 }, eq = { -10, 2, 6 } }, { id = TICK, vol = 0.7, s = { 4.7, 4.8 }, eq = { -10, 0, 8 }, delay = 0.035 } },
    streak = { { id = TICK, vol = 0.8, s = { 1.6, 1.6 } }, { id = TICK, vol = 0.8, s = { 2.0, 2.0 }, delay = 0.09 }, { id = TICK, vol = 0.9, s = { 2.5, 2.5 }, delay = 0.18 },
      { id = EXP, vol = 0.25, s = { 1.6, 1.7 }, reg = { 0.02, 0.3 }, eq = { 6, 0, -8 } } },
    heart = { { id = THUD, vol = 1.6, s = { 0.5, 0.52 }, eq = { 10, -4, -24 } }, { id = THUD, vol = 1.1, s = { 0.47, 0.49 }, eq = { 10, -4, -24 }, delay = 0.24 } },
    -- 击毁确认（KillFx.lua，用户 11-26「你自己设计一个击杀效果和音效」）：一记压得很低的「咚」（有分量）+ 一下短促的爆破起头（只留低音），
    --   接着两声往上走的金属「叮—叮」（第二声高一个四度、带一点回声尾巴）——干脆、清楚，不刺耳
    killConfirm = { { id = THUD, vol = 2.2, s = { 0.42, 0.44 }, eq = { 12, -4, -22 } },
      { id = EXP, vol = 0.22, s = { 1.55, 1.65 }, reg = { 0.02, 0.22 }, eq = { 8, -2, -14 } },
      { id = TICK, vol = 0.9, s = { 2.38, 2.38 }, eq = { -10, 2, 4 }, delay = 0.05 },
      { id = TICK, vol = 0.95, s = { 3.18, 3.18 }, eq = { -10, 2, 6 }, echo = { 0.09, 0.25, -12 }, delay = 0.13 } },
    -- 奖励到账：一串很轻的硬币声（三下由低到高，很快）
    coinSparkle = { { id = TICK, vol = 0.35, s = { 4.2, 4.3 }, eq = { -12, 0, 6 } }, { id = TICK, vol = 0.32, s = { 5.0, 5.1 }, eq = { -12, 0, 8 }, delay = 0.05 },
      { id = TICK, vol = 0.3, s = { 5.9, 6.0 }, eq = { -12, 0, 8 }, delay = 0.1 } },
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
  function G.shake(a) if G.noShake then return end trauma = math.min(1, trauma + a) end   -- 设置里关了镜头晃动（Settings.lua）
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
  -- 曳光池（11-27 审查 14：原来每发新建一个 Neon 零件 + 补间再 Debris，机枪扫射时这是「每帧新建实例」里剩下最大的一块）：
  --   按样子（武器：颜色、粗细；光晕、跳弹各一组）分组，每组最多 TR_CAP 根零件轮着用；飞的时候每帧一起挪（BulkMoveTo），
  --   飞到了挪回地底下藏着、还回组里。零件还是 ClientFx 的直接子零件：画中画（ScopePip）照样克隆它们画曳光（一组的零件不换样子，
  --   画中画里克隆的那份颜色、粗细才对得上）。
  --   11-27 复核：一组原来最多 32 根、满了顶掉最早的那根（快飞到目标的那根半路没了）——「lmg」一组挤着别人车上的并列机枪、大机枪（VehDefs 的
  --   coax / hmg 都是 fx = "lmg"）、工事和舰上的机枪、步兵机枪，「rifle」一组是所有机器人步兵：并列机枪每秒 12.5 发、打远处一挺就有十几根在飞，
  --   三挺就满了；自己打的也跟别人挤一组、会被顶掉。现在：一组最多 96 根（跳弹 16；上限只管同时在飞的根数，藏在地底下的零件不画）；
  --   自己打的单独一组（键后面加 _me：不会被别人的顶掉）；满了顶离镜头最远的那根（看得最不清楚的）
  local TR_HIDE = CFrame.new(0, -2600, 0)
  local TR_CAP = { ric = 16 }
  local TR_CAP0 = 96
  local trFree, trN, trAct = {}, {}, {}   -- 组 → 空着的零件；组 → 一共几根；正在飞的（按开始的先后）
  local trParts, trCfs = {}, {}
  G.tracerPool = function() return trFree, trN, trAct, TR_CAP0 end   -- 测试用
  -- 一根曳光：key 组、size、col、tr0 起始透明度（tr1 飞到时的透明度：跳弹越飞越淡）、p0 起点（零件中心）、du 方向、travel 中心走多远、dur 几秒
  local function streak(key, size, col, tr0, p0, du, travel, dur, tr1)
    local free = trFree[key]
    if not free then
      free = {}
      trFree[key], trN[key] = free, 0
    end
    local p = table.remove(free)
    if not p then
      if trN[key] >= (TR_CAP[key] or TR_CAP0) then   -- 这一组用满了：顶掉这一组离镜头最远的那根
        local cp = cam.CFrame.Position
        local far, fi, fd = nil, nil, -1
        for i, r in ipairs(trAct) do
          if r.key == key then
            local dd = (r.p.Position - cp).Magnitude
            if dd > fd then far, fi, fd = r, i, dd end
          end
        end
        if far then
          p = far.p
          table.remove(trAct, fi)
        end
      end
      if not p then
        p = part(nil, size, TR_HIDE, col, Enum.Material.Neon, tr0)
        p.Name = "Tracer"
        trN[key] += 1
      end
    end
    if p.Size ~= size then p.Size = size end
    if p.Color ~= col then p.Color = col end
    if p.Transparency ~= tr0 then p.Transparency = tr0 end
    p.CFrame = CFrame.lookAt(p0, p0 + du)
    trAct[#trAct + 1] = { p = p, key = key, p0 = p0, du = du, travel = math.max(0, travel), dur = math.max(0.02, dur), t0 = os.clock(), tr0 = tr0, tr1 = tr1 }
  end
  VL.onStep(function(_, now)
    if #trAct == 0 then return end
    local k, i = 0, 1
    while i <= #trAct do
      local r = trAct[i]
      local u = (now - r.t0) / r.dur
      k += 1
      trParts[k] = r.p
      if now - r.t0 > r.dur + 0.05 then   -- 飞到了（同原来多留 0.05 秒）：藏起来、还回组里
        trCfs[k] = TR_HIDE
        table.insert(trFree[r.key], r.p)
        table.remove(trAct, i)
      else
        u = math.min(1, u)
        local c = r.p0 + r.du * (r.travel * u)
        trCfs[k] = CFrame.lookAt(c, c + r.du)
        if r.tr1 then
          local a = r.tr0 + (r.tr1 - r.tr0) * u
          if math.abs(a - r.p.Transparency) > 0.03 then r.p.Transparency = a end
        end
        i += 1
      end
    end
    for j = k + 1, #trParts do trParts[j], trCfs[j] = nil, nil end
    workspace:BulkMoveTo(trParts, trCfs, Enum.BulkMoveMode.FireCFrameChanged)
  end)
  local IMPK = { hmg = 1.7, coax = 1.4, ciws = 2, agun = 2, ac = 2, sniper = 1.3, lmg = 1.1 }   -- 弹着点的大小（按口径：步枪 1）
  -- h：打在什么上面（HitSurf 代号；别人打的服务器给，nil 是什么都没打中；自己打的不给，本地探一下）
  -- pel：霰弹的其余弹丸（只画曳光和弹着点，枪口火、枪声那一发已经有了）
  function G.gunFx(id, a, b, mine, h, quiet, pel)
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
    local du0 = d.Unit
    local tk = (TRACER[id] and id or "x") .. (mine and "_me" or "")   -- 自己打的单独一组（不被别人的顶掉）
    streak(tk, V(r, r, len), col, hv and 0 or 0.1, a + du0 * (len / 2), du0, L - len, L / speed)   -- 曳光（池里的零件，每帧挪）
    if hv and not lite then   -- 光晕：同一条线上粗一圈、很淡
      streak(tk .. "_g", V(hv.glow, hv.glow, len * 0.8), col, 0.78, a + du0 * (len / 2), du0, L - len * 0.9, L / speed)
    end
    if not lite and not quiet and not pel then   -- 消音器：没有枪口那团火
      VL.emit((id == "hmg") and "mzH" or "mzR", 1, CFrame.new(a), 1)   -- 枪口一闪（池化的白点，原来每发一个 Neon 球零件）
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
    if pel then return end
    if mine and (id == "m4" or id == "sniper" or id == "rifle" or id == "qbz191") then   -- 自己开的：耳边叠层的枪声，弹壳过一会儿落地
      G.sfx(quiet and ((id == "sniper") and "sniperSdMe" or "rifleSdMe") or ((id == "sniper") and "sniperMe" or "rifleMe"), nil, { must = true })
      if math.random() < 0.35 then G.sfx("brass", nil, { delay = 0.35 + math.random() * 0.25 }) end
      return
    end
    local snd = (id == "smgsd" or quiet) and "quiet" or ((id == "sniper" or id == "lmg" or id == "pistol") and id or (id == "shotgun" and "sniper") or "rifle")   -- 装了消音器的：闷响；霰弹枪按狙击枪那一声（闷、重）
    G.playSound(snd, a)
  end

  ---------------------------------------------------------------- 爆炸、弹着点
  --   按武器分（服务器 G.explode 给类别 c）：gun 航炮 / 小口径炮弹、nade 手雷 / 炸药、shell 炮弹 / 地雷、rkt 火箭弹、msl 导弹、bomb 炸弹、
  --   flak 高炮空炸、wreck 车 / 飞机 / 舰被击毁；没给的按大小猜。
  --   用户 11-27「光影、炮弹爆炸、机枪打地、坦克爆炸、坦克开炮都要照战雷做」「M3 上要非常丝滑」（规格：战雷 Eagle's Shadow 那一版）——
  --   · 全用 VfxLib 的发射器池：每一层（贴图、颜色、大小曲线）按大小分档常驻一个发射器，挪过去 Emit；不每发新建零件和发射器
  --   · 烟、尘、土块受光照（LightInfluence 1：夜里不再自己发亮成灰白一团，黄昏带太阳的暖色，被火光照成橙色）；火、闪光自己发光
  --     （LightInfluence 0 + Brightness 推过泛光门槛，白天也有暖色光晕）
  --   · 火星、土块、碎屑是白色圆点染色、顺着速度拉成短线（VelocityParallel + Squash），不用八角星（sparkles）和白方块（SquareParticle）
  --   · smoke_main 一颗最多三分之一不透明：土柱、尘幕靠多叠几颗；黑烟用 explosion01_smoke_main（本身深灰）；烟尘跟着风（WindAffectsDrag）
  --   · 远近分档（VfxLib.lod，开镜按视场折算）：400 格内全画，1100 格内减半、不画碎屑，2500 格内只画闪光、火球、几团烟，再远只点灯
  local TX = VL.TX
  local nseq, cseq = VL.ns, VL.cs
  local upCF, lookCF = VL.upCF, VL.lookCF
  local NID = Enum.NormalId
  local UP = V(0, 1, 0)

  -- 地面（HitSurf 代号）：dust 尘土、dust2 散开以后、clod 土块碎石、life 尘土留多久、soot 弹坑焦痕、scorch 焦痕的透明度、
  --   gk 开炮掀起的尘土多少（沙、雪多，石头、木头少；草地 0.45：草皮压着，炮口冲击波掀不起多少土）、
  --   dustK 爆炸的尘量（11-27 审查 4：草地 0.9——榴弹、破甲弹、炸弹照样把草皮下面的土整块掀起来，钢城郊外、公园、训练场几乎全是草地，
  --   原来的 0.5 让最常见的地面上 125 毫米榴弹的土柱只剩一半）、spark 硬地（迸火星、跳弹）、snow 雪、ice 冰、grass 草
  local GPAL = {
    n = { dust = RGB(206, 182, 134), dust2 = RGB(230, 214, 180), clod = RGB(176, 150, 108), life = 1.4, soot = RGB(96, 80, 60), scorch = 0.35, gk = 1.4, dustK = 1 },
    d = { dust = RGB(124, 104, 80), dust2 = RGB(160, 142, 116), clod = RGB(58, 46, 34), life = 1.0, soot = RGB(34, 28, 22), scorch = 0.25, gk = 1.0, dustK = 1 },
    v = { dust = RGB(120, 110, 86), dust2 = RGB(150, 140, 116), clod = RGB(74, 86, 50), life = 0.8, soot = RGB(34, 28, 22), scorch = 0.25, gk = 0.45, dustK = 0.9, grass = true },
    i = { dust = RGB(238, 242, 248), dust2 = RGB(226, 232, 242), clod = RGB(214, 222, 234), life = 1.3, soot = RGB(58, 50, 44), scorch = 0.15, gk = 1.5, dustK = 1, snow = true },
    j = { dust = RGB(222, 232, 242), dust2 = RGB(236, 242, 248), clod = RGB(210, 224, 236), life = 0.6, soot = RGB(58, 50, 44), scorch = 0.3, gk = 0.4, dustK = 0.4, ice = true },
    r = { dust = RGB(150, 148, 142), dust2 = RGB(186, 184, 178), clod = RGB(104, 102, 98), life = 0.8, soot = RGB(40, 38, 36), scorch = 0.5, gk = 0.35, dustK = 0.8, spark = true },
    c = { dust = RGB(162, 160, 154), dust2 = RGB(198, 196, 190), clod = RGB(124, 122, 116), life = 0.9, soot = RGB(40, 38, 36), scorch = 0.5, gk = 0.35, dustK = 0.8, spark = true },
    o = { dust = RGB(138, 112, 82), dust2 = RGB(170, 146, 114), clod = RGB(176, 140, 96), life = 0.7, soot = RGB(34, 28, 22), scorch = 0.3, gk = 0.3, dustK = 0.7 },
    g = { dust = RGB(200, 210, 210), dust2 = RGB(230, 236, 236), clod = RGB(214, 230, 232), life = 0.5, soot = RGB(40, 38, 36), scorch = 0.5, gk = 0.35, dustK = 0.5, spark = true },
    f = { dust = RGB(120, 104, 86), dust2 = RGB(150, 136, 116), clod = RGB(70, 58, 46), life = 0.6, soot = RGB(34, 28, 22), scorch = 0.3, gk = 0.6, dustK = 0.6 },
  }
  -- 没给材质：雪山按雪、沙漠按沙、别的按土
  local function codeOf(hs)
    if hs and GPAL[hs] then return hs end
    if MapM.NAME == "snow" then return "i" end
    return MapM.DESERT and "n" or "d"
  end
  local function palOf(hs) return GPAL[codeOf(hs)] end
  G.groundPal = palOf
  G.groundCode = codeOf
  -- 一处脚下是什么地（往下探 12 格；残骸、开炮的地面扬尘用）：返回 HitSurf 代号（钢甲上返回 nil）、地面点、射线结果
  local gProbe = RaycastParams.new()
  gProbe.FilterType = Enum.RaycastFilterType.Exclude
  local function groundUnder(p, depth)
    local ex = { FXF }
    if G.viewFolder then ex[#ex + 1] = G.viewFolder end
    if me.Character then ex[#ex + 1] = me.Character end
    gProbe.FilterDescendantsInstances = ex
    local res = workspace:Raycast(p, V(0, -(depth or 20), 0), gProbe)
    if not res then return nil end
    local hs = HitSurf.of(res.Instance, res.Material)
    if res.Material == Enum.Material.Water then hs = "w" end
    if G.fxGroundTest then hs = G.fxGroundTest end   -- 测试用（模拟器的地形射线一律给草地）
    return hs, res.Position, res
  end
  G.groundUnder = groundUnder
  -- 地面的朝向（地形按高度差分；焦痕贴着坡）
  local function groundNormal(x, z)
    local e = 1.5
    local hx = MapM.height(x + e, z) - MapM.height(x - e, z)
    local hz = MapM.height(x, z + e) - MapM.height(x, z - e)
    return V(-hx, 2 * e, -hz).Unit
  end

  ---------------------------------------------------------------- 弹着点（机枪、步枪、航炮打在东西上）
  -- 用户：枪打在坦克上要有火花。按打中的东西（HitSurf：别人打的服务器给，自己打的本地判）：
  --   钢甲（坦克、步战车、舰艇）——白热的一闪 + 一蓬往外溅的火星（细长、带重力、一下就灭）+ 一小缕青烟，三成子弹跳弹（擦着打的六成：
  --     一小段曳光斜着飞走），「叮」的一声（重机枪、航炮是低一点的「当」）；轻型车、飞机：火星少一点；炮弹直接命中（服务器的 spark）一大团；
  --   地面（11-27 照战雷按地面分）：土——一股土 + 深色碎渣；草地——淡一点的尘 + 草屑；沙——黄沙、细沙粒；雪——白色粉雪 + 冰晶；
  --     冰——一点白雾 + 冰屑（不迸火星）；石头、水泥、沥青——灰尘 + 碎石，一半迸几颗火星、三成一下白闪；木头——木屑；水——细水柱 + 水雾 + 近处一圈涟漪
  --   每种地面两套（步枪一套、12.7 毫米以上大一号：数量 ×1.5、大小 ×1.35、速度 ×1.3），每次打中不用改发射器的属性；
  --   250 格外只画一颗尘，钢甲的火花画到 900 格；每秒最多 40 处，同时活着的弹着点粒子最多 600 颗（VfxLib）
  local SPARK_C = cseq(RGB(255, 250, 225), RGB(255, 132, 36))
  local function impDef(name, o)
    o.cat = "imp"
    VL.def("Imp_" .. name, function() return o end, true)
  end
  impDef("spark", { tex = TX.GLOW, life = { 0.12, 0.36 }, spd = { 22, 60 }, spread = 62, size = nseq(0, 0.3, 0.6, 0.2, 1, 0.05),
    tr = nseq(0, 0, 0.7, 0.15, 1, 1), col = SPARK_C, acc = V(0, -70, 0), drag = 3.5, le = 1, li = 0, bright = 4, vp = true, sq = nseq(0, 2.6, 1, 1.4), z = 0.5, prio = 3 })
  impDef("spark2", { tex = TX.GLOW, life = { 0.18, 0.55 }, spd = { 26, 72 }, spread = 70, size = nseq(0, 0.5, 0.6, 0.32, 1, 0.08),
    tr = nseq(0, 0, 0.7, 0.15, 1, 1), col = SPARK_C, acc = V(0, -70, 0), drag = 3, le = 1, li = 0, bright = 5, vp = true, sq = nseq(0, 2.8, 1, 1.5), z = 0.5, prio = 3 })
  impDef("flash", { tex = TX.GLOW, life = { 0.05, 0.08 }, spd = { 0, 0 }, size = nseq(0, 1.3, 1, 2.4),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 240), RGB(255, 205, 130)), le = 1, li = 0, bright = 5, z = 1, prio = 1 })
  impDef("flash2", { tex = TX.GLOW, life = { 0.06, 0.1 }, spd = { 0, 0 }, size = nseq(0, 2.6, 1, 4.6),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 240), RGB(255, 200, 120)), le = 1, li = 0, bright = 6, z = 1, prio = 1 })
  impDef("flash3", { tex = TX.GLOW, life = { 0.08, 0.13 }, spd = { 0, 0 }, size = nseq(0, 5, 1, 10),
    tr = nseq(0, 0, 1, 1), col = cseq(RGB(255, 255, 245), RGB(255, 190, 100)), le = 1, li = 0, bright = 7, z = 1, prio = 1 })
  impDef("smoke", { tex = TX.SMOKE, life = { 0.5, 0.9 }, spd = { 1.5, 4 }, spread = 25, size = nseq(0, 0.5, 1, 2.4),
    tr = nseq(0, 0.55, 1, 1), col = cseq(RGB(150, 150, 146), RGB(118, 118, 116)), acc = V(0, 3, 0), drag = 2, rot = 30, wind = true, prio = 2 })
  -- 地面的尘（n 几颗、sz 三个关键点的大小、life、spd、spread、acc 竖直加速度、drag）
  local IMPD = {
    dirt = { code = "d", n = 3, sz = { 0.6, 2.0, 2.8 }, life = { 0.6, 1.2 }, spd = { 8, 18 }, spread = 22, acc = -8, drag = 2.5 },
    grass = { code = "v", n = 2, sz = { 0.5, 1.6, 2.2 }, life = { 0.5, 1.0 }, spd = { 6, 14 }, spread = 22, acc = -6, drag = 2.5 },
    sand = { code = "n", n = 3, sz = { 0.9, 2.6, 3.8 }, life = { 1.0, 1.8 }, spd = { 8, 20 }, spread = 26, acc = -5, drag = 2.5 },
    snow = { code = "i", n = 4, sz = { 0.8, 2.6, 3.6 }, life = { 1.2, 2.2 }, spd = { 6, 14 }, spread = 30, acc = -2.5, drag = 3 },
    ice = { code = "j", n = 1, sz = { 0.5, 1.0, 1.4 }, life = { 0.5, 0.9 }, spd = { 6, 14 }, spread = 24, acc = -6, drag = 2.5 },
    rock = { code = "r", n = 2, sz = { 0.5, 1.6, 2.2 }, life = { 0.5, 1.0 }, spd = { 7, 16 }, spread = 28, acc = -8, drag = 2.5 },
    wood = { code = "o", n = 1, sz = { 0.5, 1.0, 1.4 }, life = { 0.5, 0.8 }, spd = { 6, 14 }, spread = 24, acc = -8, drag = 2.5 },
  }
  -- 碎渣：白点染色、顺着飞的方向拉成短线（sq 0 的不拉：冰晶）
  local IMPB = {
    chips = { n = 5, col = RGB(58, 46, 34), sz = { 0.22, 0.1 }, life = { 0.35, 0.7 }, spd = { 18, 38 }, acc = -40, drag = 0.5, spread = 30, sq = 1.2 },
    grassBits = { n = 4, col = RGB(78, 96, 52), sz = { 0.25, 0.2 }, life = { 0.6, 1.0 }, spd = { 8, 18 }, acc = -12, drag = 3, spread = 35, sq = 1.2 },
    sandGrain = { n = 6, col = RGB(200, 176, 128), sz = { 0.12, 0.08 }, life = { 0.3, 0.6 }, spd = { 20, 40 }, acc = -40, drag = 0.5, spread = 28, sq = 1.2 },
    snowGlint = { n = 5, col = RGB(250, 252, 255), sz = { 0.1, 0.05 }, life = { 0.6, 1.2 }, spd = { 6, 16 }, acc = -6, drag = 1.5, spread = 40, sq = 0 },
    iceChips = { n = 6, col = RGB(225, 235, 245), sz = { 0.18, 0.1 }, life = { 0.35, 0.7 }, spd = { 20, 40 }, acc = -40, drag = 0.5, spread = 30, sq = 1.2 },
    gravel = { n = 5, col = RGB(104, 102, 98), sz = { 0.2, 0.1 }, life = { 0.35, 0.7 }, spd = { 18, 38 }, acc = -40, drag = 0.5, spread = 32, sq = 1.2 },
    splinter = { n = 6, col = RGB(176, 140, 96), sz = { 0.22, 0.12 }, life = { 0.4, 0.8 }, spd = { 16, 34 }, acc = -36, drag = 0.6, spread = 32, sq = 2 },
  }
  for name, o in pairs(IMPD) do
    VL.def("Imp_" .. name, function(_, v)
      local zs, vs = (v == "L") and 1.35 or 1, (v == "L") and 1.3 or 1
      local P = GPAL[o.code]
      return { tex = TX.SMOKE, life = o.life, spd = { o.spd[1] * vs, o.spd[2] * vs }, spread = o.spread, drag = o.drag, acc = V(0, o.acc, 0), wind = true, rot = 40,
        size = nseq(0, o.sz[1] * zs, 0.4, o.sz[2] * zs, 1, o.sz[3] * zs), tr = nseq(0, 0.25, 0.6, 0.55, 1, 1), col = cseq(P.dust, P.dust2), prio = 2, cat = "imp" }
    end, true)
  end
  for name, o in pairs(IMPB) do
    VL.def("Imp_" .. name, function(_, v)
      local zs, vs = (v == "L") and 1.35 or 1, (v == "L") and 1.3 or 1
      return { tex = TX.GLOW, life = o.life, spd = { o.spd[1] * vs, o.spd[2] * vs }, spread = o.spread, drag = o.drag, acc = V(0, o.acc, 0),
        size = nseq(0, o.sz[1] * zs, 1, o.sz[2] * zs), tr = nseq(0, 0, 0.8, 0.1, 1, 1), col = cseq(o.col), li = 1,
        vp = o.sq > 0, sq = (o.sq > 0) and nseq(0, o.sq, 1, o.sq * 0.7) or nil, prio = 3, cat = "imp" }
    end, true)
  end
  VL.def("Imp_spout", function(_, v)
    local zs = (v == "L") and 1.35 or 1
    return { tex = TX.SMOKE, life = { 0.35, 0.7 }, spd = (v == "L") and { 24, 40 } or { 16, 26 }, spread = 6, acc = V(0, -45, 0), drag = 1, rot = 20,
      size = nseq(0, 0.3 * zs, 0.5, 0.9 * zs, 1, 1.4 * zs), tr = nseq(0, 0.15, 0.7, 0.5, 1, 1), col = cseq(RGB(236, 243, 246), RGB(220, 230, 236)), prio = 2, cat = "imp" }
  end, true)
  impDef("mist", { tex = TX.SMOKE, life = { 0.4, 0.7 }, spd = { 2, 5 }, spread = 60, size = nseq(0, 0.8, 1, 2.4),
    tr = nseq(0, 0.5, 1, 1), col = cseq(RGB(230, 238, 242), RGB(215, 225, 232)), drag = 2, rot = 20, wind = true, prio = 3 })
  impDef("ripple", { tex = TX.RING, life = { 0.55, 0.65 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = nseq(0, 0.4, 1, 3.5),
    tr = nseq(0, 0.35, 1, 1), col = cseq(RGB(230, 238, 242)), li = 1, prio = 3 })
  VL.prewarm({ "Imp_spark", "Imp_spark2", "Imp_flash", "Imp_flash2", "Imp_flash3", "Imp_smoke", "Imp_dirt", "Imp_sand", "Imp_rock", "Imp_chips" })
  -- 哪种地面用哪套尘、哪种碎渣
  local IMPNAME = { d = "dirt", v = "grass", n = "sand", i = "snow", j = "ice", r = "rock", c = "rock", g = "rock", o = "wood", f = "dirt" }
  local IMPBITS = { d = "chips", v = "grassBits", n = "sandGrain", i = "snowGlint", j = "iceChips", r = "gravel", c = "gravel", g = "gravel", o = "splinter" }

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
  local function impactSound(p, d, kind, vol)
    if d > ((kind == "thud") and 90 or 260) then return end
    local t = os.clock()
    if t - impSndT > 0.25 then impSndT, impSndN = t, 0 end
    if impSndN >= 4 then return end
    impSndN += 1
    G.sfx(kind, p, { vol = math.max(0.25, 1 - d / 320) * (vol or 1), rmin = 10, rmax = 320 })
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
    streak("ric", V(r, r, len), RGB(255, 205, 130), 0.05, p + rd * (len / 2), rd, dist - len, dur, 0.9)   -- 曳光池里的「跳弹」组，越飞越淡
    if d < 150 and math.random() < 0.35 then G.sfx("ric", p, { vol = 0.8, rmin = 10, rmax = 200 }) end
  end

  local impTok, impTokT = 40, 0
  -- p 弹着点、du 弹道方向、h 打在什么上面（HitSurf）、k 大小（步枪 1、重机枪 1.7、航炮 2、炮弹 3 上下）、nrm 表面朝向（没探到就当正对着打）
  impact = function(p, du, h, k, nrm)
    if not h then return end
    local _, d, de = VL.lod(p)   -- de：开镜按视场折算的远近（看上去多远）；声音按真的距离
    if de > 900 then return end
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
      local far = de > 250 and 0.5 or 1
      VL.emit((tier > 1) and "Imp_spark2" or "Imp_spark", 1, upCF(p + nrm * 0.15, sd), (steel and 12 or 7) * math.min(k, 3) * far)
      VL.emit(((tier == 3) and "Imp_flash3") or ((tier == 2) and "Imp_flash2") or "Imp_flash", 1, upCF(p + nrm * 0.2, nrm), 1)
      if de < 300 then VL.emit("Imp_smoke", 1, upCF(p + nrm * 0.3, nrm), (tier == 3) and 4 or (steel and 1 or 2)) end
      if tier > 1 and d < 400 then flash(p + nrm * 0.6, RGB(255, 222, 165), 8 * k, 2.4, 0.06) end   -- 夜里照亮一下车身
      if steel and de < 600 then
        local graze = math.abs(du:Dot(nrm)) < 0.5
        if math.random() < (graze and 0.6 or 0.3) then ricochet(p, refl, k, d) end
      end
      impactSound(p, d, (tier > 1) and "clang" or "ping")
    elseif h == "w" then
      local big = (k >= 1.5) and "L" or nil
      VL.emit("Imp_spout", 1, upCF(p, UP), (6 + math.random() * 2) * (big and 1.3 or 1), big)
      VL.emit("Imp_mist", 1, upCF(p, UP), 2)
      if de < 150 then VL.emit("Imp_ripple", 1, upCF(p + V(0, 0.15, 0), UP), 1) end
    else
      -- 入射角（用户 11-25「不同角度不同材质不同弹种有不同效果」）：垂直打一股往上，越斜越顺着弹道往前掀；擦着地打（入射角大于七十度）前面再拖一道土
      local cosI = math.clamp(-du:Dot(nrm), 0, 1)
      local refl = du - 2 * du:Dot(nrm) * nrm
      local up = nrm * (0.35 + cosI) + refl * (1 - cosI) * 0.9
      up = (up.Magnitude > 1e-3) and up.Unit or nrm
      local cf = upCF(p + nrm * 0.1, up)
      local big = (k >= 1.5) and "L" or nil
      local cnt = big and 1.5 or 1
      local name = IMPNAME[h] or "dirt"
      if de > 250 then   -- 远了：一颗尘
        VL.emit("Imp_" .. name, 1, cf, 1, big)
        return
      end
      VL.emit("Imp_" .. name, 1, cf, (h == "f") and 1 or IMPD[name].n * cnt, big)
      local bits = IMPBITS[h]
      if bits then VL.emit("Imp_" .. bits, 1, cf, IMPB[bits].n * cnt, big) end
      if cosI < 0.35 and (h == "d" or h == "n" or h == "i" or h == "v") then   -- 擦地：顺着弹道往前再拖一道
        local fw = (refl * 0.85 + nrm * 0.25)
        fw = (fw.Magnitude > 1e-3) and fw.Unit or up
        VL.emit("Imp_" .. name, 1, upCF(p + refl * (1.2 + k), fw), 2 * cnt, big)
      end
      if h == "r" or h == "c" or h == "g" then   -- 石头、水泥：一半迸几颗火星、三成一下白闪
        if math.random() < 0.5 then VL.emit("Imp_spark", 1, upCF(p + nrm * 0.1, up), 3 + math.random()) end
        if math.random() < 0.3 then VL.emit("Imp_flash", 1, upCF(p + nrm * 0.15, nrm), 1) end
      end
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

  ---------------------------------------------------------------- 爆炸的各层（S：爆炸系数，125 毫米榴弹 = 1；按 1.2 倍一档建发射器）
  -- E1 白闪（战雷 Eagle's Shadow：榴弹、燃烧弹命中一下很亮的白闪）；var H：破甲弹——更白、更尖、更短
  VL.def("eFlash", function(S, v)
    local h = v == "H"
    return { tex = TX.GLOW, life = h and { 0.05, 0.07 } or { 0.06, 0.09 }, spd = { 0, 0 }, size = h and nseq(0, 12 * S, 1, 20 * S) or nseq(0, 10 * S, 1, 18 * S),
      tr = nseq(0, 0, 1, 1), col = h and cseq(RGB(255, 252, 244), RGB(255, 220, 170)) or cseq(RGB(255, 248, 230), RGB(255, 200, 130)),
      le = 1, li = 0, bright = h and 8 or 6, z = 3, prio = 1 }
  end)
  -- E2 火球：从一个球体里往外翻滚，白热 → 金黄 → 橙红 → 暗褐
  VL.def("eBall", function(S)
    return { tex = TX.CORE, life = { 0.18, 0.32 }, spd = { 10, 30 }, spread = 180, drag = 7, acc = V(0, 8 * S, 0), rot = 90,
      size = nseq(0, 5 * S, 0.3, 10 * S, 1, 12 * S), tr = nseq(0, 0, 0.3, 0.1, 0.7, 0.6, 1, 1),
      col = cseq(0, RGB(255, 236, 196), 0.35, RGB(255, 160, 70), 0.7, RGB(170, 70, 30), 1, RGB(70, 40, 26)),
      le = 0.85, li = 0, bright = 3, z = 2, shape = { "Sphere", "Volume", "Outward" }, box = V(4 * S, 4 * S, 4 * S), prio = 1 }
  end)
  -- E3 黑褐土柱：土块色混一点尘土色起头（深），散开变浅；var：地面代号（+ g 偏灰：破甲弹）
  VL.def("eCol", function(S, v)
    local P = GPAL[v:sub(1, 1)] or GPAL.d
    local c0, c1, c2 = P.clod:Lerp(P.dust, 0.3), P.dust, P.dust2
    if P.snow then c0, c1, c2 = RGB(120, 112, 104), RGB(186, 186, 190), RGB(226, 232, 242) end   -- 脏雪：下暗上白
    if v:sub(2, 2) == "g" then
      local gr = RGB(140, 138, 134)
      c0, c1, c2 = c0:Lerp(gr, 0.35), c1:Lerp(gr, 0.35), c2:Lerp(gr, 0.35)
    end
    return { tex = TX.SMOKE, life = { 2.2 * P.life, 4 * P.life }, spd = { 20 * S, 45 * S }, spread = 16, drag = 1.8, acc = V(0, -14, 0), rot = 30,
      size = nseq(0, 3 * S, 0.3, 9 * S, 1, 15 * S), tr = nseq(0, 0.15, 0.5, 0.3, 1, 1), col = cseq(0, c0, 0.4, c1, 1, c2), prio = 2 }
  end)
  -- E4 TNT 黑烟（贴图本身深灰，颜色填白）；var b：炸弹、导弹、残骸，留得久
  VL.def("eSoot", function(S, v)
    return { tex = TX.SOOT, life = (v == "b") and { 6, 10 } or { 3.5, 6 }, spd = { 6, 16 }, spread = 35, drag = 1.2, acc = V(0, 3, 0), wind = true, rot = 15,
      size = nseq(0, 5 * S, 0.4, 12 * S, 1, 18 * S), tr = nseq(0, 1, 0.06, 0.1, 0.5, 0.3, 1, 1), col = cseq(RGB(255, 255, 255)), prio = 2 }
  end)
  -- E4' 破甲弹：灰烟，不是黑的
  VL.def("eGrey", function(S)
    return { tex = TX.SMOKE, life = { 3, 5 }, spd = { 6, 14 }, spread = 35, drag = 1.2, acc = V(0, 3, 0), wind = true, rot = 15,
      size = nseq(0, 5 * S, 0.4, 11 * S, 1, 16 * S), tr = nseq(0, 1, 0.06, 0.2, 0.5, 0.4, 1, 1), col = cseq(RGB(110, 106, 100), RGB(150, 146, 140)), prio = 2 }
  end)
  -- E5 土块：白点染成土块色、顺着飞的方向拉成短线，按真重力的样子（−32 格/秒²）慢慢落；var：地面代号（+ D 脏雪块）
  VL.def("eClod", function(S, v)
    local P = GPAL[v:sub(1, 1)] or GPAL.d
    local col = (v:sub(2, 2) == "D") and RGB(58, 50, 44) or P.clod
    return { tex = TX.GLOW, life = { 1.8, 3.6 }, spd = { 26 * S ^ 0.5, 60 * S ^ 0.5 }, spread = 25, drag = 0.3, acc = V(0, -32, 0),
      size = nseq(0, 0.9 * S, 1, 0.5 * S), tr = nseq(0, 0, 0.85, 0, 1, 1), col = cseq(col), li = 1, vp = true, sq = nseq(0, 1.6, 1, 0.6), prio = 3 }
  end)
  -- E6 冲击扬尘圈：贴地一整圈往外推（Sons of Attila 那层）、又宽又扁
  VL.def("eRing", function(S, v)
    local P = GPAL[v] or GPAL.d
    local lk = P.snow and 1.2 or ((v == "n") and 1.3 or 1)
    local c0, c1 = P.dust2, P.dust2:Lerp(RGB(200, 196, 188), 0.4)
    if P.snow then c0, c1 = RGB(240, 243, 248), RGB(222, 228, 238) end   -- 白色粉雪
    return { tex = TX.SMOKE, life = { 3 * P.life * lk, 6 * P.life * lk }, spd = { 25 * S ^ 0.5, 55 * S ^ 0.5 }, dir = NID.Front, spread = { 180, 4 },
      drag = 3.5, acc = V(0, 0.8, 0), wind = true, rot = 20, size = nseq(0, 4 * S, 0.35, 12 * S, 1, 18 * S), tr = nseq(0, 0.45, 1, 1),
      col = cseq(c0, c1), sq = nseq(0, -0.5, 1, -0.5), prio = 2 }
  end)
  -- E7 久留尘云（Eagle's Shadow：落点升起一团尘云，慢慢沉降、顺风散开）；同时最多 8 团
  VL.def("eCloud", function(S, v)
    local P = GPAL[v] or GPAL.d
    local life = (v == "n") and { 14, 20 } or (P.snow and { 12, 18 } or { 10, 16 })
    local c0, c1 = P.dust2:Lerp(RGB(150, 144, 134), 0.5), RGB(176, 170, 160)
    if v == "n" then c1 = P.dust2:Lerp(RGB(176, 170, 160), 0.5) end
    if P.snow then c0, c1 = RGB(232, 236, 244), RGB(214, 220, 230) end
    return { tex = TX.SMOKE, life = life, spd = { 2, 6 }, spread = 50, drag = 1, acc = V(0, 0.6, 0), wind = true, rot = 8,
      size = nseq(0, 10 * S, 0.4, 22 * S, 1, 30 * S), tr = nseq(0, 1, 0.1, 0.55, 0.6, 0.65, 1, 1), col = cseq(c0, c1), prio = 2 }
  end)
  -- E8 硬地火星
  VL.def("eSpark", function(S)
    local r = 11.5 * S
    return { tex = TX.GLOW, life = { 0.3, 0.8 }, spd = { r * 2.5, r * 5 + 20 }, spread = 60, drag = 1, acc = V(0, -60, 0),
      size = nseq(0, 0.5, 1, 0.1), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 236, 170), RGB(255, 150, 60)), le = 1, li = 0, bright = 3,
      vp = true, sq = nseq(0, 2.2, 1, 1), prio = 3 }
  end)
  -- 半空炸（高炮）的火星：往四面八方（不是 eSpark 的上半锥）
  VL.def("eSparkA", function(S)
    local r = 11.5 * S
    return { tex = TX.GLOW, life = { 0.3, 0.8 }, spd = { r * 2.5, r * 5 + 20 }, spread = 180, drag = 1, acc = V(0, -60, 0),
      size = nseq(0, 0.5, 1, 0.1), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 236, 170), RGB(255, 150, 60)), le = 1, li = 0, bright = 3,
      vp = true, sq = nseq(0, 2.2, 1, 1), prio = 3 }
  end)
  -- 雪地的冰晶
  VL.def("eIce", function()
    return { tex = TX.GLOW, life = { 1, 2 }, spd = { 6, 20 }, spread = 70, drag = 2, acc = V(0, -4, 0),
      size = nseq(0, 0.12, 1, 0.08), tr = nseq(0, 0, 0.7, 0.2, 1, 1), col = cseq(RGB(250, 252, 255)), li = 1, prio = 3 }
  end, true)
  -- 榴弹打在车上：金属火星
  VL.def("eMetal", function()
    return { tex = TX.GLOW, life = { 0.3, 0.9 }, spd = { 40, 110 }, spread = 70, drag = 1.2, acc = V(0, -60, 0),
      size = nseq(0, 0.45, 1, 0.1), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 240, 200), RGB(255, 150, 60)), le = 1, li = 0, bright = 4,
      vp = true, sq = nseq(0, 2.4, 1, 1), prio = 3 }
  end, true)
  -- 破甲弹：聚能射流打进去那一下，顺着来弹方向一道白热的细光
  VL.def("eJet", function(S)
    return { tex = TX.GLOW, life = { 0.07, 0.15 }, spd = { 70, 140 }, spread = 10, size = nseq(0, 4 * S, 1, 0.5 * S), tr = nseq(0, 0, 1, 0.5),
      col = cseq(RGB(255, 255, 250), RGB(255, 214, 150)), le = 1, li = 0, bright = 6, z = 2, vp = true, sq = nseq(0, 2.5, 1, 2.5), prio = 1 }
  end)
  -- 导弹、炸弹、残骸：贴地冲击波圈
  VL.def("eShock", function(S)
    local r = 11.5 * S
    return { tex = TX.RING, life = { 0.35 + r / 120, 0.4 + r / 100 }, spd = { 0.05, 0.05 }, spread = 0, flat = true,
      size = nseq(0, r * 0.4, 1, r * 4.5), tr = nseq(0, 0.25, 1, 1), col = cseq(RGB(235, 220, 195)), li = 1, prio = 3 }
  end)
  -- 半空炸（高炮）：一团黑烟；var b 留得久
  VL.def("eAirSoot", function(S, v)
    local r = 11.5 * S
    local T = (v == "b") and 9 or 3.5
    return { tex = TX.SOOT, life = { T * 0.5, T * 0.8 }, spd = { r * 0.3, r * 0.8 }, spread = 180, drag = 2, wind = true, rot = 15,
      size = nseq(0, r * 0.5, 0.3, r * 1.3, 1, r * 1.9), tr = nseq(0, 1, 0.06, 0.12, 0.6, 0.35, 1, 1), col = cseq(RGB(255, 255, 255)), prio = 2 }
  end)
  -- 海面：白色水柱、一圈水雾、平躺的一圈白沫
  VL.def("wCol", function(S)
    local r = 11.5 * S
    return { tex = TX.SMOKE, life = { 1.3, 2.2 + r / 40 }, spd = { r * 2, r * 4.2 }, spread = 12, drag = 0.6, acc = V(0, -r * 3, 0), rot = 25,
      size = nseq(0, r * 0.3, 0.35, r * 0.85, 1, r * 1.4), tr = nseq(0, 0.05, 0.6, 0.3, 1, 1), col = cseq(RGB(238, 244, 248), RGB(214, 226, 232)), prio = 2 }
  end)
  VL.def("wMist", function(S)
    local r = 11.5 * S
    return { tex = TX.SMOKE, life = { 1, 1.8 }, spd = { r * 1.2, r * 2.4 }, dir = NID.Front, spread = { 180, 10 }, drag = 1.6, wind = true,
      size = nseq(0, r * 0.35, 1, r * 1.3), tr = nseq(0, 0.25, 1, 1), col = cseq(RGB(238, 244, 248)), prio = 2 }
  end)
  VL.def("wRing", function(S)
    local r = 11.5 * S
    return { tex = TX.RING, life = { 2.2, 2.8 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = nseq(0, r * 0.5, 1, r * 3.5),
      tr = nseq(0, 0.2, 1, 1), col = cseq(RGB(238, 244, 248)), li = 1, prio = 3 }
  end)
  -- 航炮、小口径炮弹（s = 杀伤半径 / 3.6）：白闪、一小团火、火星、一小团土、碎渣
  VL.def("acFlash", function(s)
    local r = 3.6 * s
    return { tex = TX.GLOW, life = { 0.06, 0.09 }, spd = { 0, 0 }, size = nseq(0, r * 0.9, 1, r * 1.4), tr = nseq(0, 0, 1, 1),
      col = cseq(RGB(255, 240, 200), RGB(255, 186, 110)), le = 1, li = 0, bright = 5, z = 2, prio = 1 }
  end)
  VL.def("acCore", function(s)
    return { tex = TX.CORE, life = { 0.1, 0.14 }, spd = { 2, 6 }, spread = 180, drag = 6, size = nseq(0, 1.5 * s, 1, 3 * s), tr = nseq(0, 0, 0.6, 0.3, 1, 1),
      col = cseq(0, RGB(255, 236, 196), 0.5, RGB(255, 160, 70), 1, RGB(120, 60, 30)), le = 0.85, li = 0, bright = 3, z = 1, prio = 1 }
  end)
  VL.def("acSpark", function()
    return { tex = TX.GLOW, life = { 0.25, 0.5 }, spd = { 18, 50 }, spread = 70, drag = 1, acc = V(0, -60, 0), size = nseq(0, 0.45, 1, 0.08),
      tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 230, 160), RGB(255, 150, 60)), le = 1, li = 0, bright = 3, vp = true, sq = nseq(0, 2, 1, 1), prio = 3 }
  end, true)
  VL.def("acDust", function(s, v)
    local P = GPAL[v] or GPAL.d
    local r = 3.6 * s
    return { tex = TX.SMOKE, life = { 0.9 * P.life, 1.6 * P.life }, spd = { r * 1.4, r * 3 }, spread = 28, drag = 2, acc = V(0, -12, 0), wind = true, rot = 30,
      size = nseq(0, r * 0.6, 1, r * 2), tr = nseq(0, 0.15, 1, 1), col = cseq(P.dust, P.dust2), prio = 2 }
  end)
  VL.def("acChips", function(s, v)
    local P = GPAL[v] or GPAL.d
    local r = 3.6 * s
    return { tex = TX.GLOW, life = { 0.6, 1.1 }, spd = { r * 2.5, r * 5 }, spread = 35, drag = 0.5, acc = V(0, -40, 0), size = nseq(0, 0.35, 1, 0.2),
      tr = nseq(0, 0, 0.8, 0, 1, 1), col = cseq(P.clod), li = 1, vp = true, sq = nseq(0, 1.2, 1, 0.8), prio = 3 }
  end)
  -- 弹掉进海里：一小柱水
  VL.def("splash", function()
    return { tex = TX.SMOKE, life = { 0.8, 1.3 }, spd = { 10, 22 }, spread = 14, acc = V(0, -40, 0), drag = 0.8, size = nseq(0, 1.5, 1, 4),
      tr = nseq(0, 0.15, 1, 1), col = cseq(RGB(236, 242, 246)), prio = 2 }
  end, true)

  local KF = { nade = 0.5, shell = 0.75, rkt = 0.8, msl = 0.9, bomb = 1, flak = 0.6, wreck = 0.8 }   -- 老的火球半径 / 杀伤半径（灯、余火的大小按它）
  local RMIN = { shell = 5, rkt = 6, msl = 9, bomb = 24, wreck = 10 }
  local boomT, boomN = 0, 0
  local clouds = {}   -- 久留尘云的到期时间（同时最多 8 团）
  -- 斜着打进地里的弹：土柱往哪边掀（垂直落下的朝天，越斜越顺着来弹方向往前倒）
  local function tiltUp(dv)
    if typeof(dv) ~= "Vector3" or dv.Magnitude < 0.5 then return UP end
    local du = dv.Unit
    local cosI = math.clamp(-du.Y, 0, 1)
    local fwd = V(du.X, 0, du.Z)
    local u = V(0, 0.55 + cosI, 0) + ((fwd.Magnitude > 1e-3) and fwd.Unit or V()) * (1 - cosI) * 0.9
    return u.Unit
  end
  -- 炮弹打在钢甲上（用户 11-21：打中目标，如果是金属也要有火花）：再迸一大把亮的火星（顺着飞的方向拉成线、带重力落下），一下白热的闪光
  VL.def("hsSpark", function()
    return { tex = TX.GLOW, life = { 0.35, 1.1 }, spd = { 40, 120 }, spread = 65, dir = NID.Front, drag = 0.8, acc = V(0, -60, 0),
      size = nseq(0, 0.6, 1, 0.1), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 236, 180), RGB(255, 160, 70)), le = 1, li = 0, bright = 4,
      vp = true, sq = nseq(0, 2.4, 1, 1), prio = 3 }
  end, true)
  VL.def("hsFlash", function(s)
    return { tex = TX.GLOW, life = { 0.08, 0.14 }, spd = { 0, 0 }, size = nseq(0, 3 * s, 1, 5.5 * s), tr = nseq(0, 0, 1, 1),
      col = cseq(RGB(255, 245, 220), RGB(255, 210, 150)), le = 1, li = 0, bright = 6, z = 2, prio = 1 }
  end)
  local function hotSparks(p, n, s)
    if (p - cam.CFrame.Position).Magnitude > 1500 then return end
    local cf = lookCF(p + n * 0.3, n)
    VL.emit("hsSpark", 1, cf, 22 * s * VL.perfK())
    VL.emit("hsFlash", s, cf, 1)
  end

  -- 航炮、小口径炮弹（机炮榴弹）：白闪、一小团火、几颗火星、按地面一小团土 + 碎渣（水里一小柱水）；400 格内照亮一下
  local function gunBoom(p, r, hs, dv, water, air, metal, tl, K, d)
    local s = r / 3.6
    VL.emit("acFlash", s, CFrame.new(p), 1)
    if tl <= 2 then VL.emit("acCore", s, CFrame.new(p), 2) end
    if tl == 1 then VL.emit("acSpark", 1, upCF(p, UP), 5 * K) end
    if not air and not metal and tl <= 2 then
      if water then
        VL.emit("Imp_spout", 1, upCF(p, UP), 6 * K, "L")
      else
        local code = codeOf(hs)
        local cf = upCF(p, tiltUp(dv))
        VL.emit("acDust", s, cf, 4 * K, code)
        if tl == 1 and d < 600 then VL.emit("acChips", s, cf, 5 * K, code) end
      end
    end
    if d < 400 then flash(p + V(0, 2, 0), RGB(255, 190, 110), 12, 3, 0.12) end
  end

  -- 车被打爆（服务器发的 c = "wreck"）：这一下是不是附近那辆车自己的殉爆——是的话 WreckFx 照这辆车的样子画殉爆的大火球（View 看到残骸那一帧），
  --   这里就只出声、震屏（原来两边各画一个大火球叠在一起，这一下几百颗、最大的九十多格）。11-27 审查 1：原来 30 格内有车（不管死活）就不画，
  --   老式扣血判毁（回机库判毁、战雷伤害出错回落）的步战车、悍马只剩一缕烟，车旁 30 格内的工事、坠毁的飞机也没了爆炸。现在三条都满足才跳过：
  --   · r 格内那辆车已经是残骸（Wreck 属性；属性和这条特效是服务器同一帧发的，属性先到）
  --   · WreckFx 会把它当殉爆画：WtWhy == "ammo"，或者没有 WtWhy（老式血量打光）的坦克
  --   · 是这一次的：View 还没处理到、处理了不到 2 秒，或者转盘车先烧完炸开的那一刻前后 2 秒（不是早就躺在那儿的老残骸）
  --   只看 r 格内离这一下最近的那辆车（11-27 复核：原来 30 格内任何一辆满足就算——殉爆那一刻旁边十几格的步战车被老式判毁，
  --   它自己那一下也被当成殉爆的、不画；服务器发的位置就在那辆车的车身 / 炮塔座圈上，最近的那辆就是它）
  local function ownCookOff(p, r)
    local now = os.clock()
    local bv, bem, bd = nil, nil, r
    for em, v in pairs(G.views or {}) do
      if v.kind == "veh" and v.hullF then
        local dd = (v.hullF.Position - p).Magnitude
        if dd < bd then bv, bem, bd = v, em, dd end
      end
    end
    if not bv then return false end
    local m = bv.em or bem
    if m and m:GetAttribute("Wreck") then
      local why = m:GetAttribute("WtWhy")
      if why == "ammo" or (why == nil and bv.def and bv.def.cat == "tank") then
        if not bv.wrecked or (bv.wreckT and now - bv.wreckT < 2) or (bv.cookT and math.abs(now - bv.cookT) < 2) then return true end
      end
    end
    return false
  end
  G.ownCookOff = ownCookOff   -- 测试用
  -- 同一处 0.6 秒内又来一个 c = "wreck" 的（老式判毁：Ents.lua 先发一个、Armor.lua / Air.lua 的 onDeath 又发一个）：只画一个、只响一声
  --   （同一批里的在 G.onFx 先挑了最大的那个；这里管跨批的）。own：这一下是不是附近那辆车自己的殉爆（ownCookOff，只出声不画）——
  --   11-27 复核：原来不分，殉爆那一下（不画）也登记了，0.6 秒内 15 格内另一辆车（非坦克）的爆炸被当成重复吞掉；现在只跟同一种的比
  local wreckSeen = {}
  local function wreckDup(p, own)
    local now = os.clock()
    for i = #wreckSeen, 1, -1 do
      local w = wreckSeen[i]
      if now - w.t > 0.6 then table.remove(wreckSeen, i)
      elseif w.own == own and (w.p - p).Magnitude < 15 then return true end
    end
    wreckSeen[#wreckSeen + 1] = { p = p, t = now, own = own }
    return false
  end
  -- hs 地面材质（钢甲：打在车上）、dv 来弹方向（服务器 G.explode 的 info）；am 炮弹的弹种（Ballistics 的 cls；火箭弹、导弹按战斗部，Ents.lua）：
  --   he / 没给：榴弹——白闪、火球、黑褐土柱、TNT 黑烟、土块、贴地扬尘圈、久留尘云、弹坑焦痕；
  --   heat / jet / atgm（破甲战斗部的炮射导弹、反坦克导弹、火箭弹）：破甲弹——闪光又白又尖、一道射流白光、火球小、土少偏灰、灰烟；
  --   mpat：在两者中间；can（霰弹）不炸；
  --   打在钢甲上：没有土柱、土块、扬尘、尘云、弹坑，火球小一点、黑烟多一点，迸一大把金属火星（穿甲弹打在钢甲上不是爆炸：spark 那边画火花）
  local function boom(p, s, c, hs, dv, am)
    s = s or 1
    if am == "atgm" and not c then   -- 车载反坦克导弹（陶式、婴儿、短号：服务器的 boomKind 不认 atgm，杀伤半径只有 3～4 格）：
      c = "rkt"                      --   按破甲战斗部的火箭弹画、不小于破甲弹（原来按杀伤半径猜成了航炮弹的一小团火）
      s = math.max(s, 0.6)
    end
    local r = 12 * s   -- 杀伤半径（格）
    if not c then c = (r < 5 and "gun") or (r < 13 and "shell") or (r < 26 and "msl") or "bomb" end
    if am == "can" then return end
    local metal = hs ~= nil and HitSurf.METAL[hs] == true
    if metal and am == "ap" then return end
    local own = (c == "wreck") and ownCookOff(p, 30)
    if c == "wreck" and wreckDup(p, own) then return end
    local d = (p - cam.CFrame.Position).Magnitude
    local gy = MapM.height(p.X, p.Z)
    local water = gy < 0.3 and p.Y < 5 and not metal   -- 打在船身上（吃水线附近）算打在钢甲上，不是水柱
    local surf = (gy < 0.3) and 0 or math.max(gy, 0)
    local air = c == "flak" or ((not metal) and (p.Y - surf) > math.max(6, r * 0.6))
    boomSound(p, r, c, d, water and not air)
    if d > ((c == "gun") and 1600 or ((c == "bomb" or c == "wreck") and 9000 or 5000)) then return end
    if c ~= "gun" then   -- 离得近震一下
      local shR = r * 12 + 60
      if d < shR then G.shake(math.clamp(r / 32, 0.12, 0.85) * (1 - d / shR)) end
      if G.concuss then G.concuss(d, r, c) end   -- 近处：耳鸣、发闷、一白一糊（Shock.lua）
    end
    -- 车殉爆（服务器 Wt.lua 殉爆那一下 s 4.2～4.6、老式判毁的坦克 s 2～2.4）：WreckFx.lua 照车的样子画火球、碎块、黑烟，这里只出声、震屏（见 ownCookOff）
    if own then return end
    local t = os.clock()
    if t - boomT > 0.25 then boomT, boomN = t, 0 end
    boomN += 1
    local tl = VL.lod(p)
    -- 同一时刻扎堆的（集束、齐射）、远的、机器跟不上的少画
    local K = VL.perfK() * ((boomN > 6) and 0.5 or 1) * ((tl == 2) and 0.5 or 1)
    local function n(x) return x * K end
    if c == "gun" then
      gunBoom(p, r, hs, dv, water, air, metal, tl, K, d)
      return
    end
    local S = (c == "shell") and math.clamp(r / 11.5, 0.5, 2) or math.clamp(r / 11.5, 0.4, 3.2)
    local heat = am == "heat" or am == "jet" or am == "atgm"
    local mp = am == "mpat"
    local R = math.max(r * (KF[c] or 0.8), RMIN[c] or 3)
    local long = c == "bomb" or c == "msl" or c == "wreck"
    local wreck = c == "wreck"
    local dirU = (typeof(dv) == "Vector3" and dv.Magnitude > 0.5) and -dv.Unit or UP   -- 迎着来弹的方向
    -- E10 光：照亮四周（VfxLib.flash 只点离镜头 range + 400 格以内的——远处、开镜看远处的落点不点灯，远处靠下面的白闪看落点）；
    --   白天最多亮 1.5 倍（同殉爆的大灯：Realistic 光照下白天再乘 2.5 一大片过曝）
    local dk = G.dayK and G.dayK() or 0
    flash(p + V(0, R * 0.5, 0), RGB(255, 170, 90), math.min(120, 30 + 4 * r), 10, long and 0.4 or 0.25, { day = VL.DAY_MUL_BIG })
    if tl == 4 then   -- 很远（开镜也看着很远）：夜里闪一下；大的留两团烟（看得见落点）
      if dk < 0.5 then VL.emit("eFlash", S, CFrame.new(p), 1, heat and "H" or nil) end
      if S >= 0.8 and not air then VL.emit(water and "wCol" or "eSoot", S, upCF(p, UP), 2) end
      return
    end
    -- E1 白闪、E2 火球
    VL.emit("eFlash", S, CFrame.new(p), 2, heat and "H" or nil)
    local bk = ((heat and 0.75) or (mp and 0.85) or (metal and 0.8) or 1) * ((water and not air) and 0.6 or 1)
    VL.emit("eBall", S * bk, CFrame.new(p + V(0, 0.5 * S, 0)), (tl == 3) and 4 or math.max(3, n(8 * ((heat and 0.75) or 1))))
    local up = tiltUp(dv)
    local code = codeOf(hs)
    local P = GPAL[code]
    if tl == 3 then   -- 中远：闪光、火球、几团烟
      if air then VL.emit("eAirSoot", S, CFrame.new(p), 2, long and "b" or nil)
      elseif water then VL.emit("wCol", S, upCF(p, UP), 3)
      else
        VL.emit(heat and "eGrey" or "eSoot", S, upCF(p, up), 2, (long and not heat) and "b" or nil)
        if not metal and not wreck then VL.emit("eCol", S, upCF(p, up), 2, code .. ((heat or mp) and "g" or "")) end
      end
      return
    end
    if air then   -- 半空炸：一团火、往四面八方的火星（原来 180：不只往上半锥）、一团黑烟（高炮的就是这一团），慢慢散开
      VL.emit("eSparkA", S, CFrame.new(p), n(6 + r / 2))
      VL.emit("eAirSoot", S, CFrame.new(p), n(4 + r / 4), long and "b" or nil)
      return
    end
    if water then   -- 海面：白色水柱 + 一圈水雾 + 平躺的一圈白沫
      VL.emit("wCol", S, upCF(p, UP), n((10 + r / 2) * 1.2))
      VL.emit("wMist", S, lookCF(V(p.X, 0.8, p.Z), V(1, 0, 0)), n(8 + r / 3))
      VL.emit("wRing", S, upCF(V(p.X, 0.6, p.Z), UP), 1)
      return
    end
    if metal then   -- 打在车上
      VL.emit(heat and "eGrey" or "eSoot", S, upCF(p, UP), n(heat and 4 or 9))
      VL.emit("eMetal", 1, upCF(p, dirU), n(20))   -- 再加上 spark 消息那边的 hotSparks（服务器炮弹打在钢甲上另发一条 spark）
      if heat then VL.emit("eJet", S, upCF(p, dirU), n(7)) end
      return
    end
    -- E3 土柱（车、飞机被打爆没有）、射流、火星、冰晶
    if not wreck then
      VL.emit("eCol", S, upCF(p, up), n(21 * ((heat and 0.6) or (mp and 0.8) or 1) * P.dustK), code .. ((heat or mp) and "g" or ""))
      if heat or mp then VL.emit("eJet", S, upCF(p, dirU), n(heat and 7 or 4)) end
      if P.spark and d < 1500 then VL.emit("eSpark", S, upCF(p, up), n(8 + r / 2)) end
      if P.snow then VL.emit("eIce", 1, upCF(p, up), n(12)) end
    end
    -- E4 黑烟（破甲弹灰烟）
    if heat then VL.emit("eGrey", S, upCF(p, up), n(3.5))
    else VL.emit("eSoot", S, upCF(p, up), n(7 * (mp and 0.75 or 1)), long and "b" or nil) end
    -- E5 土块（车、飞机被打爆：真的钢板碎块，WreckFx.lua）
    if wreck then
      if G.wreckChunks and d < 1500 then G.wreckChunks(p, R, K, 6) end
    elseif tl == 1 then
      local cn = n(24 * ((heat and 0.5) or (mp and 0.75) or 1))
      if P.snow then
        VL.emit("eClod", S, upCF(p, up), cn * 0.7, code)
        VL.emit("eClod", S, upCF(p, up), cn * 0.3, code .. "D")
      else
        VL.emit("eClod", S, upCF(p, up), cn, code)
      end
    end
    -- E6 冲击扬尘圈（贴地往外推的一整圈）
    if tl == 1 or S >= 1.3 then
      local rk = ((heat and 0.8) or (mp and 0.9) or 1) * (P.snow and 1.3 or ((code == "n") and 1.4 or 1)) * P.dustK
      VL.emit("eRing", S, lookCF(V(p.X, surf + 1, p.Z), V(1, 0, 0)), n(18 * rk), code)
    end
    if (long or c == "rkt") and r >= 7 and tl == 1 then VL.emit("eShock", S, upCF(V(p.X, surf + 1.2, p.Z), UP), 1) end
    -- E7 久留尘云：慢慢沉降、顺风散开（同时最多 8 团，多了新来的不画这层）
    if not wreck and S >= 0.6 then
      local now = os.clock()
      for i = #clouds, 1, -1 do if clouds[i] < now then table.remove(clouds, i) end end
      if #clouds < 8 then
        local ck = ((heat and 0.6) or (mp and 0.8) or 1) * (P.snow and 1.3 or ((code == "n") and 1.4 or 1)) * P.dustK
        VL.emit("eCloud", S, upCF(V(p.X, surf + 2 * S, p.Z), UP), math.max(2, n(6 * ck)), code)
        clouds[#clouds + 1] = now + ((code == "n") and 17 or (P.snow and 15 or 13))
      end
    end
    -- E9 弹坑焦痕（贴着地面，60 秒后 10 秒淡掉）
    if not wreck and tl <= 2 and p.Y - surf < 4 then
      local D = (7 + math.random() * 2) * S * ((heat and 0.7) or (mp and 0.85) or 1)
      VL.scorch(V(p.X, surf, p.Z), D, P.soot, P.scorch, groundNormal(p.X, p.Z))
    end
    -- 大的留一会儿余火和黑烟（弹坑、残骸在烧）
    if long and tl == 1 then VL.burn(p, R, (c == "bomb") and 7 or 5) end
  end
  G.boom = boom

  ---------------------------------------------------------------- 穿甲弹（动能弹）打在地上
  -- 服务器 Ents.lua 的 gimp；用户 11-25「炮弹和导弹 子弹击中地面 不同角度不同材质不同弹种有不同效果」：不炸、没有火球——
  --   高速的弹芯把土石掀成一股窄而高的喷泉，顺着弹道往前溅；擦着地打（入射角大）犁出一道沟：顺着弹道一串土团，弹芯跳起来接着飞（一道曳光）；
  --   石头、水泥、玻璃上白热一闪、迸一大把火星；沙地黄沙大团、飘得久；雪地白色粉雪 + 冰晶（不迸火星）；冰面只有一点冰屑、容易跳弹（叮一声）；
  --   水面一柱细高的水。s 口径（坦克炮 2 上下、航炮 1）；一处最多 70 颗
  VL.def("kFount", function(s, v)
    local P = GPAL[v] or GPAL.d
    return { tex = TX.SMOKE, life = { 0.9 * P.life, 1.9 * P.life }, spd = { 16 * s, 34 * s }, spread = 14, drag = 1.5, acc = V(0, -36, 0), rot = 40,
      size = nseq(0, 0.8 * s, 0.35, 2.4 * s, 1, 4 * s), tr = nseq(0, 0.1, 0.55, 0.35, 1, 1), col = cseq(P.dust, P.dust2), prio = 2 }
  end)
  VL.def("kClod", function(s, v)
    local P = GPAL[v] or GPAL.d
    return { tex = TX.GLOW, life = { 0.8, 1.7 }, spd = { 14 * s, 30 * s }, spread = 26, drag = 0.4, acc = V(0, -32, 0),
      size = nseq(0, 0.3 + 0.18 * s, 1, 0.18 + 0.1 * s), tr = nseq(0, 0, 0.8, 0, 1, 1), col = cseq(P.clod), li = 1, vp = true, sq = nseq(0, 1.4, 1, 0.6), prio = 3 }
  end)
  VL.def("kRing", function(s, v)
    local P = GPAL[v] or GPAL.d
    return { tex = TX.SMOKE, life = { 1.2 * P.life, 2.4 * P.life }, spd = { 6 * s, 13 * s }, dir = NID.Front, spread = { 180, 6 }, drag = 2, acc = V(0, 1.2, 0),
      wind = true, rot = 20, size = nseq(0, 1.1 * s, 1, 4.2 * s), tr = nseq(0, 0.35, 1, 1), col = cseq(P.dust2), sq = nseq(0, -0.5, 1, -0.5), prio = 2 }
  end)
  VL.def("kHang", function(s, v)
    local P = GPAL[v] or GPAL.d
    return { tex = TX.SMOKE, life = { 6 * P.life, 10 * P.life }, spd = { 1, 3 }, spread = 60, drag = 1, wind = true, rot = 10,
      size = nseq(0, 2 * s, 1, 6 * s), tr = nseq(0, 0.55, 1, 1), col = cseq(P.dust2), prio = 2 }
  end)
  VL.def("kFurrow", function(s, v)
    local P = GPAL[v] or GPAL.d
    return { tex = TX.SMOKE, life = { 0.8 * P.life, 1.6 * P.life }, spd = { 7 * s, 16 * s }, spread = 18, drag = 1.6, acc = V(0, -40, 0), rot = 40,
      size = nseq(0, 0.7 * s, 0.4, 1.9 * s, 1, 3 * s), tr = nseq(0, 0.12, 0.6, 0.45, 1, 1), col = cseq(P.dust, P.dust2), prio = 2 }
  end)
  VL.def("kSpark", function()
    return { tex = TX.GLOW, life = { 0.2, 0.6 }, spd = { 40, 110 }, spread = 40, drag = 2.2, acc = V(0, -60, 0), size = nseq(0, 0.45, 1, 0.1),
      tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 246, 210), RGB(255, 150, 50)), le = 1, li = 0, bright = 4, vp = true, sq = nseq(0, 2.2, 1, 1), prio = 3 }
  end, true)
  VL.def("kFlash", function(s)
    return { tex = TX.GLOW, life = { 0.07, 0.12 }, spd = { 0, 0 }, size = nseq(0, 2.2 * s, 1, 4 * s), tr = nseq(0, 0, 1, 1),
      col = cseq(RGB(255, 255, 240), RGB(255, 205, 130)), le = 1, li = 0, bright = 5, z = 2, prio = 1 }
  end)
  VL.def("kIce", function()
    return { tex = TX.GLOW, life = { 1, 2 }, spd = { 6, 16 }, spread = 50, drag = 2, acc = V(0, -4, 0), size = nseq(0, 0.1, 1, 0.06),
      tr = nseq(0, 0, 0.7, 0.2, 1, 1), col = cseq(RGB(250, 252, 255)), li = 1, prio = 3 }
  end, true)
  VL.def("kWCol", function(s)
    return { tex = TX.SMOKE, life = { 0.9, 1.6 }, spd = { 22 * s, 40 * s }, spread = 6, drag = 0.8, acc = V(0, -90, 0), rot = 25,
      size = nseq(0, 0.6 * s, 0.4, 1.8 * s, 1, 3 * s), tr = nseq(0, 0.05, 0.6, 0.35, 1, 1), col = cseq(RGB(238, 244, 248), RGB(214, 226, 232)), prio = 2 }
  end)
  VL.def("kWRing", function(s)
    return { tex = TX.SMOKE, life = { 0.9, 1.6 }, spd = { 6 * s, 12 * s }, dir = NID.Front, spread = { 180, 10 }, drag = 1.6, wind = true,
      size = nseq(0, 0.8 * s, 1, 3.2 * s), tr = nseq(0, 0.3, 1, 1), col = cseq(RGB(238, 244, 248)), prio = 2 }
  end)
  local kinT, kinN = 0, 0
  local function kineticHit(p, nrm, dv, hs, s)
    if typeof(p) ~= "Vector3" then return end
    s = math.clamp(tonumber(s) or 2, 1, 3)
    local tl, d, de = VL.lod(p)
    if de > 3500 then return end
    local t = os.clock()
    if t - kinT > 0.25 then kinT, kinN = t, 0 end
    kinN += 1
    if kinN > 10 then return end   -- 一齐打过来的太多：后面的不画
    nrm = (typeof(nrm) == "Vector3" and nrm.Magnitude > 0.5) and nrm.Unit or UP
    local du = (typeof(dv) == "Vector3" and dv.Magnitude > 0.5) and dv.Unit or -nrm
    local code = (hs == "w") and "w" or codeOf(hs)
    if tl >= 3 then   -- 远：一小团土（开镜看得见打在哪）
      if tl == 3 then
        if code == "w" then VL.emit("kWCol", s, upCF(p, UP), 2) else VL.emit("kFount", s, upCF(p + nrm * 0.2, nrm), 2, code) end
      end
      return
    end
    local K = VL.perfK() * ((kinN > 4) and 0.5 or 1) * ((tl == 2) and 0.5 or 1)
    if code == "w" then   -- 水面：一柱又细又高的水 + 一圈水雾
      VL.emit("kWCol", s, upCF(p, UP), (8 + 4 * s) * K)
      VL.emit("kWRing", s, lookCF(p + V(0, 0.5, 0), V(1, 0, 0)), (6 + 2 * s) * K)
      if d < 700 then G.sfx({ { id = WATER, vol = 0.8, s = { 0.85, 1.05 } } }, p, { rmin = 15, rmax = 700, delay = d / 960 }) end
      return
    end
    local P = GPAL[code]
    local hard = P.spark == true   -- 硬地（冰不算：不迸火星）
    local cosI = math.clamp(-du:Dot(nrm), 0, 1)       -- 1 垂直打下去，0 擦着地
    local refl = du - 2 * du:Dot(nrm) * nrm            -- 反弹方向
    local along = du - du:Dot(nrm) * nrm               -- 贴着地面往前
    if along.Magnitude > 1e-3 then along = along.Unit else along = nil end
    local up = nrm * (0.45 + cosI) + refl * (1 - cosI) * 1.1
    up = (up.Magnitude > 1e-3) and up.Unit or nrm
    local furrow = along ~= nil and cosI < 0.5
    -- 一处最多 70 颗：先算这一下要喷多少，多了按比例少喷
    local nF = (9 + 5 * s) * (P.ice and 0.4 or 1)
    local nC = (hard and 14 or 10) * s
    local plan = nF + ((tl == 1) and nC or 0) + (7 + 3 * s) + (2 + s) + (furrow and (4 + 2 * s) * (3 + s) * 0.8 or 0) + ((P.snow and tl == 1) and 8 or 0) + (hard and 14 * s or 0)
    local bk = math.min(1, 70 / plan)
    local function n(x) return x * K * bk end
    -- ① 喷泉：窄、高，往上冲（越斜越往前倒）
    VL.emitK("kFount", s, upCF(p + nrm * 0.2, up), n(nF), code, nil, 8 + 12 * cosI)
    -- ② 土块、碎石（木头是木屑、雪地是雪块、冰面是冰屑）
    if tl == 1 then VL.emit("kClod", s, upCF(p + nrm * 0.2, up), n(nC), code) end
    if P.snow and tl == 1 then VL.emit("kIce", 1, upCF(p + nrm * 0.2, up), n(8)) end
    -- ③ 贴地一圈扬尘（往四周推开、慢慢散）、一团留着随风飘的灰
    VL.emit("kRing", s, lookCF(p + nrm * 0.8, V(1, 0, 0)), n(7 + 3 * s), code)
    VL.emit("kHang", s, upCF(p + nrm * 0.8, nrm), n(2 + s), code)
    -- ④ 擦着地打：犁出一道沟——顺着弹道往前一串土团，一团比一团小
    if furrow then
      local L = (6 + 5 * s) * (1 - cosI)
      local k = math.floor(3 + s)
      local fw = (along * 0.6 + nrm * 0.8).Unit
      for i = 1, k do
        local f = i / k
        VL.emit("kFurrow", s, upCF(p + along * (L * f) + nrm * 0.3, fw), n((4 + 2 * s) * (1.1 - f * 0.6)), code)
      end
    end
    -- ⑤ 硬地（石头、水泥、玻璃）：白热一闪，一大把火星往反弹方向溅
    if hard then
      local sd = nrm + refl
      sd = (sd.Magnitude > 1e-3) and sd.Unit or nrm
      VL.emit("kSpark", 1, upCF(p + nrm * 0.2, sd), n(14 * s))
      VL.emit("kFlash", s, CFrame.new(p + nrm * 0.3), 1)
      if d < 500 then flash(p + nrm, RGB(255, 222, 165), 10 * s, 3, 0.08) end
    end
    -- 弹芯跳起来接着飞（擦着地打的多；硬地、冰面更多）
    local ricP = ((hard and 0.75) or (P.ice and 0.6) or 0.35) * (1 - cosI)
    if d < 900 and math.random() < ricP then ricochet(p + nrm * 0.3, refl, s * 1.3, d) end
    -- ⑥ 一声闷响（远的晚一点到），打在石头上还有一声跳弹、冰面叮的一声；离得近震一下
    if d < 700 then
      G.sfx({ { id = EXP, vol = 0.5, s = { 1.45, 1.7 }, reg = { 0.03, 0.5 } } }, p, { rmin = 15, rmax = 700, delay = d / 960 })
      if hard and d < 300 then G.sfx("shellRic", p, { vol = 0.8, rmax = 500 })
      elseif P.ice and d < 300 then G.sfx("ping", p, { vol = 0.7, rmax = 400 }) end
    end
    if d < 45 then G.shake(0.12 * (1 - d / 45)) end
  end
  G.kineticHit = kineticHit

  -- 弹掉进海里：一小柱水
  local function splash(p)
    VL.emit("splash", 1, upCF(V(p.X, 0.5, p.Z), UP), 5)
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

  -- 导弹尾烟三档（AirDefs.smokeOf）：gap 多久一团、s0 / s1 起始 / 最后的大小、tr 起始透明度、life 留多久
  local MSL_SMOKE = {
    low = { gap = 0.07, s0 = 0.9, s1 = 3.2, tr = 0.55, life = 1.3, col = RGB(226, 226, 222) },
    med = { gap = 0.04, s0 = 1.3, s1 = 5.5, tr = 0.32, life = 2.4, col = RGB(222, 222, 218) },
    heavy = { gap = 0.022, s0 = 2.0, s1 = 9.0, tr = 0.12, life = 4.5, col = RGB(214, 212, 206) },
  }
  -- 抛射的弹点火（服务器 shotIgn，或者时候到了还没收到）：发动机声、尾焰从这里开始，发动机的时间（双脉冲、助推段）从这里算
  local function ejIgnite(s)
    if not s.ejUntil then return end
    s.ejDur, s.ejUntil, s.ejg = s.t, nil, nil
    if s.glow and not s.roar then addRoar(s, s.glow, s.p) end
    if not s.my then G.sfx("msl", s.p) end   -- 自己打的：开火那一下 Fly.lua 已经放过
  end
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
      if not mine(e) and not aw.hyper then G.sfx((kind == "missile" and not e.ej) and "msl" or "bombRel", e.p) end   -- 抛射的：先是挂架弹开的一声
      flying[e.id] = { wm = mdl, glow = glow, half = (aw.shape and aw.shape.L or 5) / 2, p = e.p, v = e.v, gb = kind == "bomb", t = 0, kind = kind, trailT = 0,
        burn = aw.burn or 4, aw = aw, cfs = table.create(#mdl.parts), tg = e.tg, w = e.w, my = mine(e) }   -- my：自己打出去的（Marks.lua 给自己的炸弹标落点）
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
      if e.ej and kind == "missile" then   -- 抛射：先往下掉、不喷火，点火（服务器 shotIgn，或者到时候了）才亮、才有发动机声
        local fs = flying[e.id]
        fs.ejUntil = os.clock() + e.ej + 0.25   -- 服务器的 shotIgn 丢了也照样点火
        fs.ejg = true
        if glow then glow.Transparency = 1 end
      elseif glow then addRoar(flying[e.id], glow, e.p) end
      if mine(e) and G.onMyShot then G.onMyShot(e) end   -- 自己打出去的：按 L 跟踪（MslCam.lua）
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
      if s.gb or s.ejg then s.v += V(0, -27.5, 0) * dt end   -- 机载炸弹、还没点火的抛射弹：AirDefs.GRAV（不用 gb：Marks.lua 按它画炸弹落点）
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
        if s.ejUntil and os.clock() >= s.ejUntil then ejIgnite(s) end
        local tm = s.t - (s.ejDur or 0)   -- 抛射的弹：发动机从点火那一刻算
        local burning = s.aw and AD.motorOn(s.aw, tm) or (tm < s.burn)   -- 双脉冲第二次、巡航弹一直开
        if s.hyper then burning = s.lit end
        if s.ejUntil then burning = false end   -- 抛射的弹：还没点火
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
        elseif s.kind == "missile" and burning then
          -- 尾烟按型号（AirDefs 的 smoke；用户 11-24 夜：「不同导弹尾烟……都是不一样的」）：低烟发动机细、淡、散得快（AIM-120、AIM-9X、霹雳-15），
          --   老式发动机、助推器又粗又浓、挂在天上很久（AIM-54、57E6 的助推段、巡航弹起飞那一下）；发动机一关就不冒烟（只靠惯性滑翔）
          local sp = MSL_SMOKE[AD.smokeOf(s.aw, tm)] or MSL_SMOKE.med
          s.trailT += dt
          if s.trailT > sp.gap then
            s.trailT = 0
            local sm = part(BALL, V(sp.s0, sp.s0, sp.s0), cf * CFrame.new(0, 0, s.half + 1), sp.col, Enum.Material.SmoothPlastic, sp.tr)
            sm.Name = "MslSmoke"
            tween(sm, sp.life, { Size = V(sp.s1, sp.s1, sp.s1), Transparency = 1 })
            Debris:AddItem(sm, sp.life + 0.1)
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
      if s.t > ((s.kind == "bomb") and 40 or (s.hyper and 95 or ((s.kind == "shell") and 65 or 15))) then endShot(id) end   -- 炮弹：等服务器的 shotEnd（11-26 原来 15 秒就删，远的弹半路没了）
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
    if s and e.lost then s.lost = true end   -- 数据链断了 / 导引头丢了目标（雷达屏上只剩预计命中点那个小圈，Radar.lua）
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
    -- 箔条（战雷：每组诱饵弹里都有，骗开了导引头的雷达弹；服务器 Air.lua 的 flare）：机尾后面一团闪着银光的碎屑云，慢慢散开飘落
    for k = 1, 2 do
      local q = e.p - v0 * 0.12 + V((math.random() - 0.5) * 8, -2 - math.random() * 4, (math.random() - 0.5) * 8)
      local ch = part(BALL, V(3, 3, 3), CFrame.new(q), RGB(214, 218, 224), Enum.Material.Foil, 0.45)
      ch.Name = "Chaff"
      tween(ch, 2.4, { CFrame = CFrame.new(q + v0 * 0.25 - V(0, 14, 0)), Size = V(16, 12, 16), Transparency = 1 })
      Debris:AddItem(ch, 2.45)
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

  -- 一组新建的粒子（别的模块用：ShipView 垂发的箱口火、箱尾燃气）：o 的 tex、life、speed、spread、drag、acc、size {起, 止}、tr、color、glow、n、dir；
  --   11-27：烟、尘（glow ≤ 0.5）受光照（LightInfluence 1，原来没设、Instance.new 默认 0：夜里自己发亮成灰白一团），火、闪光自己发光；
  --   bright 亮度（火默认 3）、wind 顺风、sq 拉长 / 压扁、vp 顺着速度
  local SMOKE_TEX = TX.SMOKE
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
    pe.LightInfluence = o.li or (((o.glow or 0) > 0.5) and 0 or 1)
    pe.Brightness = o.bright or ((pe.Texture == TX.FIRE) and 3 or 1)
    pe.EmissionDirection = o.dir or Enum.NormalId.Front
    if o.vp then
      pe.Orientation = Enum.ParticleOrientation.VelocityParallel
      pe.Rotation, pe.RotSpeed = NumberRange.new(0), NumberRange.new(0)
    end
    if o.sq then pcall(function() pe.Squash = o.sq end) end
    if o.wind then pcall(function() pe.WindAffectsDrag = true end) end
    pe.Parent = holder
    pe:Emit(math.max(1, math.floor(o.n * math.clamp(G.perfK or 1, 0.4, 1.2) + 0.5)))
    return pe
  end
  G.emitBurst = emitter

  ---------------------------------------------------------------- 车炮开火
  -- 用户 11-27「坦克开炮照战雷做」（截图：Eagle's Shadow 那版——比炮塔还大的橙黄火球 + 被冲击波往前、往两边推开的扇形尘幕）：
  --   L1 炮口一下白闪；L2 二次焰火球（直径 14～17 格、0.2 秒，从炮口前一段盒子里翻出来）；L3 顺着炮管的一道火舌；
  --   L4 只有带炮口制退器的炮才往两边横喷（120 / 125 滑膛炮没有；自行火炮、VehDefs 里写了 brake 的有）；L5 燃烧的药粒顺着炮管拉成细线；
  --   L6 垂直炮管一下撑开的激波圈（300 格内）；L7 跟着炮弹冲出去的一道推进剂烟（停在前面 13～38 格）；L8 炮口挂着慢慢往上飘的烟团；
  --   L9 炮口离地不到 14 格：往下探地面，按地面掀起扇形尘幕、升腾的尘团、砂砾、贴地冲击圈（水上是水雾、涟漪、白沫）；
  --   L10 照亮四周的光（自己开的炮、天黑了才投影子）；L11 声音、震屏、车体后坐照旧。
  --   口径系数 k = 炮管口径 / 0.42（120 / 125 毫米 = 1），全用 VfxLib 的池；离镜头远的按档少画（400 格内 ≤ 110 颗、1100 格内 ≤ 45、再远 ≤ 12）
  VL.def("mFlash", function(k)
    return { tex = TX.GLOW, life = { 0.05, 0.07 }, spd = { 0, 0 }, size = nseq(0, 5 * k, 1, 9 * k), tr = nseq(0, 0, 1, 1),
      col = cseq(RGB(255, 250, 236), RGB(255, 214, 150)), le = 1, li = 0, bright = 6, z = 3, prio = 1 }
  end)
  VL.def("mBall", function(k)
    return { tex = TX.CORE, life = { 0.16, 0.24 }, spd = { 8, 30 }, dir = NID.Front, spread = 35, drag = 8, rot = 120,
      size = nseq(0, 7 * k, 0.35, 14 * k, 1, 17 * k), tr = nseq(0, 0, 0.3, 0.05, 0.7, 0.4, 1, 1),
      col = cseq(0, RGB(255, 240, 200), 0.35, RGB(255, 176, 80), 0.7, RGB(214, 92, 38), 1, RGB(108, 46, 24)),
      le = 0.9, li = 0, bright = 3.5, z = 2, sq = nseq(0, 0, 1, -0.3), shape = { "Box", "Volume", "Outward" }, box = V(4 * k, 4 * k, 10 * k), prio = 1 }
  end)
  VL.def("mTongue", function(k)
    return { tex = TX.CORE, life = { 0.06, 0.09 }, spd = { 60, 90 }, dir = NID.Front, spread = 3, drag = 10, size = nseq(0, 4 * k, 1, 8 * k),
      tr = nseq(0, 0, 0.6, 0.2, 1, 1), col = cseq(RGB(255, 236, 190), RGB(255, 150, 60)), le = 1, li = 0, bright = 4, z = 2, vp = true, sq = nseq(0, 1.2, 1, 1.2), prio = 1 }
  end)
  VL.def("mBrake", function(k)
    return { tex = TX.CORE, life = { 0.07, 0.11 }, spd = { 40, 70 }, dir = NID.Front, spread = 6, drag = 9, size = nseq(0, 3 * k, 1, 7 * k),
      tr = nseq(0, 0, 0.6, 0.2, 1, 1), col = cseq(RGB(255, 226, 170), RGB(255, 140, 60)), le = 1, li = 0, bright = 4, z = 2, vp = true, sq = nseq(0, 1.5, 1, 1.5), prio = 1 }
  end)
  VL.def("mSpark", function()
    return { tex = TX.GLOW, life = { 0.2, 0.6 }, spd = { 80, 160 }, dir = NID.Front, spread = 9, drag = 2, acc = V(0, -28, 0),
      size = nseq(0, 0.35, 1, 0.1), tr = nseq(0, 0, 0.8, 0.3, 1, 1), col = cseq(RGB(255, 226, 160), RGB(255, 130, 50)), le = 1, li = 0, bright = 3,
      vp = true, sq = nseq(0, 2.4, 1, 1), prio = 3 }
  end, true)
  VL.def("mShock", function(k)
    return { tex = TX.RING, life = { 0.12, 0.16 }, spd = { 0.1, 0.1 }, dir = NID.Front, spread = 0, flat = true, size = nseq(0, 3 * k, 1, 28 * k),
      tr = nseq(0, 0.55, 1, 1), col = cseq(RGB(230, 224, 214)), li = 1, prio = 3 }
  end)
  -- 烟尘的变体：C 贴脸（镜头 40 格内：小一点、淡一点，少叠几层大的半透明），S 自己开镜（淡一点：挡视线 1.5～2.5 秒就够）
  local function nearAdd(v) return (v and v:find("C", 1, true)) and 0.15 or ((v and v:find("S", 1, true)) and 0.15 or 0), (v and v:find("C", 1, true)) and 0.8 or 1 end
  VL.def("mTrail", function(k, v)
    local add, sz = nearAdd(v)
    return { tex = TX.SMOKE, life = { 2.2, 4 }, spd = { 40, 120 }, dir = NID.Front, spread = 7, drag = 4.5, acc = V(0, 1.2, 0), wind = true, rot = 25,
      size = nseq(0, 3 * k * sz, 0.4, 9 * k * sz, 1, 13 * k * sz), tr = VL.nsAdd({ 0, 0.35, 0.3, 0.5, 1, 1 }, add), col = cseq(RGB(210, 206, 198), RGB(176, 172, 164)), prio = 2 }
  end)
  VL.def("mHang", function(k, v)
    local add, sz = nearAdd(v)
    return { tex = TX.SMOKE, life = { 3.5, 6 }, spd = { 3, 12 }, dir = NID.Front, spread = 60, drag = 1.5, acc = V(0, 1.6, 0), wind = true, rot = 20,
      size = nseq(0, 5 * k * sz, 0.4, 13 * k * sz, 1, 18 * k * sz), tr = VL.nsAdd({ 0, 0.4, 1, 1 }, add), col = cseq(RGB(196, 192, 184), RGB(170, 166, 160)), prio = 2 }
  end)
  -- L9 地面扬尘：var = 地面代号（+ B 制退器：扇面更宽）（+ C / S 同上）
  local function dustVar(v)
    local P = GPAL[v:sub(1, 1)] or GPAL.d
    local add, sz = nearAdd(v)
    return P, v:find("B", 2, true) ~= nil, add, sz
  end
  VL.def("gFan", function(k, v)   -- 9a 贴地扇形尘幕：被冲击波往前、往两边推开的那一大片
    local P, brake, add, sz = dustVar(v)
    return { tex = TX.SMOKE, life = { 2.5 * P.life, 5 * P.life }, spd = { 30, 75 }, dir = NID.Front, spread = brake and { 95, 6 } or { 75, 5 }, drag = 4,
      acc = V(0, 0.8, 0), wind = true, rot = 15, size = nseq(0, 4 * k * sz, 0.35, 14 * k * sz, 1, 20 * k * sz), tr = VL.nsAdd({ 0, 0.45, 0.3, 0.55, 1, 1 }, add),
      col = cseq(0, P.dust, 0.4, P.dust2, 1, P.dust2), sq = nseq(0, -0.6, 1, -0.3), prio = 2 }
  end)
  VL.def("gRise", function(k, v)   -- 9b 升腾的尘团
    local P, _, add, sz = dustVar(v)
    return { tex = TX.SMOKE, life = { 4, 7 }, spd = { 10, 28 }, spread = 45, drag = 2, acc = V(0, 2, 0), wind = true, rot = 12,
      size = nseq(0, 6 * k * sz, 0.4, 16 * k * sz, 1, 24 * k * sz), tr = VL.nsAdd({ 0, 0.5, 1, 1 }, add), col = cseq(P.dust2:Lerp(RGB(255, 255, 255), 0.12)), prio = 2 }
  end)
  VL.def("gGrit", function(_, v)   -- 9c 砂砾：土是一把深色的砂砾（fire_sparks），沙是细沙粒，雪、冰是冰晶
    local P = GPAL[v] or GPAL.d
    if P.snow or P.ice then
      return { tex = TX.GLOW, life = { 1, 2 }, spd = { 35, 70 }, dir = NID.Front, spread = { 60, 4 }, drag = 2.5, acc = V(0, -4, 0),
        size = nseq(0, 0.12, 1, 0.08), tr = nseq(0, 0, 0.7, 0.2, 1, 1), col = cseq(RGB(250, 252, 255)), li = 1, prio = 3 }
    elseif v == "n" then
      return { tex = TX.GLOW, life = { 0.4, 0.8 }, spd = { 35, 70 }, dir = NID.Front, spread = { 60, 4 }, drag = 2.5, acc = V(0, -30, 0),
        size = nseq(0, 0.12, 1, 0.08), tr = nseq(0, 0, 0.8, 0.2, 1, 1), col = cseq(RGB(200, 176, 128)), li = 1, prio = 3 }
    end
    return { tex = TX.GRIT, life = { 0.4, 0.8 }, spd = { 35, 70 }, dir = NID.Front, spread = { 60, 4 }, drag = 2.5, acc = V(0, -30, 0), rot = 90,
      size = nseq(0, 1.6, 1, 2.4), tr = nseq(0, 0, 0.7, 0.3, 1, 1), col = cseq(P.clod), li = 1, prio = 3 }
  end, true)
  VL.def("gRing", function(k, v)   -- 9d 贴地冲击圈（替掉原来的塑料圆柱）
    local P = GPAL[v] or GPAL.d
    return { tex = TX.RING, life = { 0.3, 0.4 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = nseq(0, 6 * k, 1, 36 * k),
      tr = nseq(0, 0.6, 1, 1), col = cseq(P.dust2), li = 1, prio = 3 }
  end)
  VL.def("gGrass", function()
    return { tex = TX.GLOW, life = { 0.6, 1.0 }, spd = { 20, 40 }, dir = NID.Front, spread = { 60, 8 }, drag = 3, acc = V(0, -12, 0),
      size = nseq(0, 0.25, 1, 0.2), tr = nseq(0, 0, 0.8, 0.1, 1, 1), col = cseq(RGB(74, 86, 50)), li = 1, vp = true, sq = nseq(0, 1.2, 1, 1), prio = 3 }
  end, true)
  VL.def("gMist", function(k)   -- 水上：白色水雾、涟漪、平铺的白沫
    return { tex = TX.SMOKE, life = { 1.2, 2 }, spd = { 20, 40 }, dir = NID.Front, spread = { 75, 5 }, drag = 3, acc = V(0, 1, 0), wind = true, rot = 15,
      size = nseq(0, 3 * k, 0.4, 9 * k, 1, 13 * k), tr = nseq(0, 0.4, 1, 1), col = cseq(RGB(236, 242, 246)), prio = 2 }
  end)
  VL.def("gRipple", function(k)
    return { tex = TX.RING, life = { 1.1, 1.3 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = nseq(0, 4 * k, 1, 40 * k),
      tr = nseq(0, 0.4, 1, 1), col = cseq(RGB(236, 242, 246)), li = 1, prio = 3 }
  end)
  VL.def("gFoam", function(k)
    return { tex = TX.SMOKE, life = { 2.5, 3.5 }, spd = { 2, 6 }, dir = NID.Front, spread = { 180, 2 }, drag = 1.5, wind = true, rot = 8,
      size = nseq(0, 4 * k, 1, 14 * k), tr = nseq(0, 0.3, 1, 1), col = cseq(RGB(240, 244, 246)), sq = nseq(0, -1, 1, -1), prio = 3 }
  end)
  -- 小口径（机炮、并列机枪、遥控武器站）：池化的白点闪一下（原来是 Neon 球零件）；机炮再加一小团火
  VL.def("mzR", function()
    return { tex = TX.GLOW, life = { 0.04, 0.045 }, spd = { 0, 0 }, size = nseq(0, 0.8, 1, 1.4), tr = nseq(0, 0.05, 1, 1),
      col = cseq(RGB(255, 230, 170), RGB(255, 186, 110)), le = 1, li = 0, bright = 4, z = 1, prio = 1 }
  end, true)
  VL.def("mzH", function()
    return { tex = TX.GLOW, life = { 0.05, 0.055 }, spd = { 0, 0 }, size = nseq(0, 1.4, 1, 2.4), tr = nseq(0, 0.05, 1, 1),
      col = cseq(RGB(255, 230, 170), RGB(255, 180, 100)), le = 1, li = 0, bright = 4, z = 1, prio = 1 }
  end, true)
  VL.def("mzA", function()
    return { tex = TX.GLOW, life = { 0.05, 0.055 }, spd = { 0, 0 }, size = nseq(0, 2, 1, 4), tr = nseq(0, 0.05, 1, 1),
      col = cseq(RGB(255, 236, 190), RGB(255, 176, 96)), le = 1, li = 0, bright = 4, z = 1, prio = 1 }
  end, true)
  VL.def("mzAc", function()
    return { tex = TX.CORE, life = { 0.06, 0.065 }, spd = { 0, 0 }, size = nseq(0, 1.5, 1, 3), tr = nseq(0, 0, 0.6, 0.3, 1, 1),
      col = cseq(RGB(255, 226, 170), RGB(255, 140, 60)), le = 1, li = 0, bright = 4, z = 1, prio = 1 }
  end, true)
  G.muzzleSmall = function(kind, p, dir)   -- 测试、别的模块用：kind "r" 步枪、"h" 12.7、"a" 机炮
    if kind == "a" then
      VL.emit("mzA", 1, CFrame.new(p), 1)
      VL.emit("mzAc", 1, lookCF(p + dir * 0.6, dir), 1)
    else
      VL.emit((kind == "h") and "mzH" or "mzR", 1, CFrame.new(p), 1)
    end
  end

  -- 炮的口径系数、有没有制退器（VehDefs 的 gun：cal 口径、brake 炮口制退器；自行火炮一般有制退器）
  local function gunInfo(e)
    local v = e.id and G.viewById and G.viewById(e.id)
    local gd = v and v.def and v.def.gun
    local k = math.clamp(((gd and tonumber(gd.cal)) or 0.42) / 0.42, 0.6, 1.15)
    return k, (gd ~= nil and gd.brake == true) or e.f == "arty"
  end
  G.gunInfo = gunInfo
  -- L9 地面扬尘：从炮口往下探 20 格找地面，炮口离地不到 14 格才画；强度 = 口径 × 地面系数 × 离地越低越大
  local function muzzleDust(M, F, k, brake, tl, close, sight, mult)
    local fh = V(F.X, 0, F.Z)
    if fh.Magnitude < 0.1 then return end   -- 炮口朝天
    fh = fh.Unit
    local hs, Gp = groundUnder(M, 20)
    if not Gp then return end
    local h = M.Y - Gp.Y
    if h >= 14 or (hs and HitSurf.METAL[hs]) then return end   -- 炮口下面是别的车、船甲板：不画
    local fade = math.clamp(1.25 - h / 16, 0.3, 1)
    local G2 = Gp + fh * 3 * k + V(0, 1.5, 0)
    if hs == "w" then
      VL.emit("gMist", k, lookCF(G2, fh), 14 * fade * mult)
      if tl == 1 then
        VL.emit("gRipple", k, upCF(Gp + V(0, 0.3, 0), UP), 1)
        VL.emit("gFoam", k, lookCF(Gp + V(0, 0.6, 0), fh), 6 * mult)
      end
      return
    end
    local code = codeOf(hs)
    local P = GPAL[code]
    local s = k * P.gk * fade * mult
    local flag = (close and "C") or (sight and "S") or ""
    local cf = lookCF(G2, fh)
    if tl >= 3 then
      VL.emit("gFan", k, cf, math.max(1, 2 * s), code .. flag)
      return
    end
    local nk = close and 0.6 or 1
    VL.emit("gFan", k, cf, (18 + math.random() * 8) * s * nk, code .. (brake and "B" or "") .. flag)
    if brake then VL.emit("gFan", k, lookCF(G2 - fh * 4 * k, -fh), 6 * s * nk, code .. "B" .. flag) end   -- 制退器往后也掀一点
    VL.emit("gRise", k, upCF(G2, (fh * 0.866 + UP * 0.5).Unit), (7 + math.random() * 3) * s * nk, code .. flag)
    if tl == 1 then
      VL.emit("gGrit", 1, cf, (6 + math.random() * 4) * s, code)
      VL.emit("gRing", k, upCF(Gp + V(0, 0.4, 0), UP), 1, code)
      if P.grass then VL.emit("gGrass", 1, cf, 4) end
    end
  end
  local function vfire(e)
    local big = e.f == "tank" or e.f == "arty"
    local dir = (typeof(e.d) == "Vector3" and e.d.Magnitude > 0.01) and e.d.Unit or V(0, 0, -1)
    local M = e.p
    if typeof(M) ~= "Vector3" then return end
    local tl, dd = VL.lod(M)
    if not big then   -- 小口径：池化的一闪 + 灯 + 枪声
      if tl <= 2 then
        local f = e.f
        G.muzzleSmall((f == "ac" or f == "agun" or f == "ciws" or f == "msl") and "a" or "h", M + dir * 0.6, dir)
      end
      flash(M + dir, RGB(255, 190, 110), 16, 4, 0.1)
      G.playSound("lmg", M)
      if G.vehRecoil and e.id then G.vehRecoil(e.id, e.g) end
      return
    end
    local k, brake = gunInfo(e)
    local arty = e.f == "arty"
    local mine = G.drive ~= nil and G.drive.id ~= nil and G.drive.id == e.id
    local close = dd < 40
    local sight = mine and G.drive.sight == true
    local pk = VL.perfK()
    local look = lookCF(M, dir)
    local dk = G.dayK and G.dayK() or 0
    -- L10 光（自己开的炮、天黑才投影子）；白天最多亮 1.5 倍（同榴弹、殉爆的大灯：白天再乘 2.5 一大片过曝）
    flash(M + dir * 5 * k, RGB(255, 178, 96), math.min(120, 60 * k), 10, 0.14, { shadow = mine and dk < 0.5, day = VL.DAY_MUL_BIG })
    if tl == 4 and dk < 0.5 then VL.emit("mFlash", k, CFrame.new(M), 1) end   -- 很远：夜里只闪一下（白天不画）
    if tl <= 3 then   -- L1 白闪、L2 火球
      VL.emit("mFlash", k, CFrame.new(M), 1)
      VL.emit("mFlash", k, CFrame.new(M + dir * 4 * k), 1)
      VL.emit("mBall", k, lookCF(M + dir * 6 * k, dir), (tl == 1 and 8) or (tl == 2 and 5) or 4)
    end
    if tl <= 2 then
      local nk = close and 0.6 or 1
      local vC = (close and "C") or (sight and "S") or nil
      VL.emit("mTongue", k, look, 2)
      if brake then   -- L4 制退器往两边横喷（稍往后）：绕炮管自己的「上」转 ±95°（原来绕世界的竖轴：自行火炮仰 45° 时喷流往前上方去了）
        local bu = UP - dir * dir:Dot(UP)   -- 炮管的上：竖直方向去掉顺着炮管的那一份（炮口朝天时随便取一个）
        bu = (bu.Magnitude > 1e-3) and bu.Unit or V(1, 0, 0)
        for sx = -1, 1, 2 do
          VL.emit("mBrake", k, lookCF(M - dir * 0.3, CFrame.fromAxisAngle(bu, sx * math.rad(95)) * dir), 2)
        end
      end
      VL.emit("mSpark", 1, look, ((tl == 1) and 20 or 6) * pk)
      if tl == 1 and dd < 300 then VL.emit("mShock", k, lookCF(M + dir * 2 * k, dir), 1) end
      -- 烟：近处推进剂烟 14、烟团 6（自行火炮多三成，贴脸少四成）；中距离（1100 格内，整炮 ≤ 45 颗）5 / 2
      local sK = (arty and 1.3 or 1) * pk * nk
      VL.emit("mTrail", k, look, ((tl == 1) and 14 or 4) * sK, vC)
      VL.emit("mHang", k, lookCF(M + dir * 2 * k, dir), ((tl == 1) and 6 or 2) * sK, vC)
      muzzleDust(M, dir, k, brake and tl == 1, tl, close, sight, ((tl == 1) and 1 or 0.4) * pk)
    elseif tl == 3 then
      VL.emit("mHang", k, look, 2)
      muzzleDust(M, dir, k, false, tl, false, false, pk)
    end
    -- L11 声音：脆响 + 低沉的轰隆 + 回声（远处的晚一点到、高音被吃掉）；车体后坐、离得近震屏
    G.sfx("tankGun", M, { must = true, rmax = 2600, delay = dd / 1100, hiCut = -math.min(18, dd / 80) })
    if G.vehRecoil and e.id then G.vehRecoil(e.id, e.g) end
    if dd < 200 then G.shake(0.38 * (1 - dd / 200)) end
  end
  G.vfire = vfire   -- 测试用

  -- 跳弹（用户：跳弹也做出来）：服务器判了打得太斜、弹头滑开——迸一串火星（顺着跳出去的方向拉成一溜）、一点白烟、「当」一声 + 尖啸飞走；
  --   飞着的曳光改走跳出去的方向（服务器给新的位置和速度）
  VL.def("ricSpark", function()
    return { tex = TX.GLOW, life = { 0.25, 0.7 }, spd = { 50, 110 }, dir = NID.Front, spread = 16, acc = V(0, -50, 0), drag = 0.5,
      size = nseq(0, 0.55, 1, 0.2), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 236, 180), RGB(255, 170, 80)), le = 1, li = 0, bright = 4,
      vp = true, sq = nseq(0, 2.2, 1, 1), prio = 3 }
  end, true)
  VL.def("ricSpark2", function()
    return { tex = TX.GLOW, life = { 0.2, 0.5 }, spd = { 15, 45 }, dir = NID.Front, spread = 70, acc = V(0, -60, 0), drag = 0.5,
      size = nseq(0, 0.4, 1, 0.15), tr = nseq(0, 0, 1, 0.3), col = cseq(RGB(255, 200, 120), RGB(255, 150, 70)), le = 1, li = 0, bright = 3,
      vp = true, sq = nseq(0, 2, 1, 1), prio = 3 }
  end, true)
  VL.def("ricSmoke", function()
    return { tex = TX.SMOKE, life = { 0.8, 1.6 }, spd = { 3, 9 }, dir = NID.Front, spread = 50, drag = 2, wind = true, rot = 30,
      size = nseq(0, 1.2, 1, 5), tr = nseq(0, 0.45, 1, 1), col = cseq(RGB(200, 196, 190)), prio = 2 }
  end, true)
  VL.def("ricGlint", function()
    return { tex = TX.GLOW, life = { 0.1, 0.13 }, spd = { 0, 0 }, size = nseq(0, 1.6, 1, 3.5), tr = nseq(0, 0, 1, 1),
      col = cseq(RGB(255, 246, 220), RGB(255, 214, 150)), le = 1, li = 0, bright = 6, z = 2, prio = 1 }
  end, true)
  G.ricochetCount = 0   -- 测试用
  local function shellRicochet(e)
    if typeof(e.p) ~= "Vector3" then return end
    G.ricochetCount += 1
    local out = (typeof(e.v) == "Vector3" and e.v.Magnitude > 0.1) and e.v.Unit or UP
    local n = (typeof(e.n) == "Vector3") and e.n or out
    local tl = VL.lod(e.p)
    if tl <= 3 then
      local cf = lookCF(e.p, out)
      VL.emit("ricGlint", 1, CFrame.new(e.p + n * 0.3), 1)
      VL.emit("ricSpark", 1, cf, (tl == 1) and 40 or 16)
      if tl <= 2 then
        VL.emit("ricSpark2", 1, cf, 18)
        VL.emit("ricSmoke", 1, cf, 6)
      end
    end
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
  -- 被标记的敌人（用户 11-27「如果发现了敌载具可以进行全队标记 你仿照战雷就行」）：服务器每半秒发一次位置——
  --   车 / 飞机的红菱形按服务器给的实体编号挂在那辆车上（跟着它走，不再半秒一跳一跳）；远处也画（原来 2500 格外就不画了）；
  --   人照旧摆在那个位置上
  local spotGui = Instance.new("Folder")
  spotGui.Name = "SpotMarks"
  spotGui.Parent = me:WaitForChild("PlayerGui")
  -- 被标记的那辆车挂红菱形的零件：客户端这辆车的视图（View.lua）上挂血条的锚点 / 模型里的零件；没有视图就用服务器复制过来的实体根零件
  local function hostFor(id)
    local v = id and G.viewById and G.viewById(id)
    if v then
      local a = v.anchor or (v.model and (v.model.PrimaryPart or v.model:FindFirstChildWhichIsA("BasePart", true)))
      if a then return a, v.model end
    end
    local ents = id and workspace:FindFirstChild("Ents")
    if ents then
      for _, m in ipairs(ents:GetChildren()) do
        if m:GetAttribute("EntId") == id and m.PrimaryPart then return m.PrimaryPart, m end
      end
    end
    return nil
  end
  local function spots(list, ids)
    for _, m in ipairs(spotMarks) do m:Destroy() end
    spotMarks = {}
    for i, p in ipairs(list or {}) do
      local bb = Instance.new("BillboardGui")
      bb.Size = UDim2.fromOffset(16, 16)
      bb.AlwaysOnTop = true
      bb.MaxDistance = 1e5
      local root, host = hostFor(ids and ids[i] or nil)
      if root then
        local ok, _, size = pcall(function() return host:GetBoundingBox() end)
        local h = (ok and size) and size.Y or 8
        bb.Adornee = root
        bb.StudsOffsetWorldSpace = V(0, h * 0.6 + 3, 0)
        bb.Parent = spotGui
        table.insert(spotMarks, bb)
      else
        local a = part(nil, V(0.2, 0.2, 0.2), CFrame.new(p + V(0, 6, 0)), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
        bb.Parent = a
        table.insert(spotMarks, a)
      end
      local l = Instance.new("TextLabel")
      l.Size = UDim2.fromScale(1, 1)
      l.BackgroundTransparency = 1
      l.Text = "◆"
      l.TextScaled = true
      l.TextColor3 = RGB(255, 60, 50)
      l.TextStrokeTransparency = 0.5
      l.Parent = bb
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
    -- 同一批里同一处的几个 c = "wreck"（老式判毁：Ents.lua 发一个、Armor.lua / Air.lua 的 onDeath 又发一个）：只画最大的那个
    local wl = nil
    for _, e in ipairs(list) do
      if type(e) == "table" and e.k == "boom" and e.c == "wreck" and typeof(e.p) == "Vector3" then
        wl = wl or {}
        wl[#wl + 1] = e
      end
    end
    if wl and #wl > 1 then
      for i, a in ipairs(wl) do
        for j, b in ipairs(wl) do
          if i ~= j and (a.p - b.p).Magnitude < 15 and ((b.s or 1) > (a.s or 1) or ((b.s or 1) == (a.s or 1) and j < i)) then
            a.dupW = true
            break
          end
        end
      end
    end
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
          G.gunFx(e.w, e.a, e.b, false, e.h, e.q, e.pel)
          if G.radarShot then G.radarShot(e.a, e.t, e.q) end   -- 雷达：敌人开枪的地方闪一下（Hud.lua）
        end
      elseif k == "boom" then
        if not e.dupW then boom(e.p, e.s, e.c, e.h, e.d, e.am) end
      elseif k == "tree" or k == "treeReset" then   -- 钢城的树倒了 / 新一局立回去（服务器 Trees.lua；Scenery.lua 画）
        if G.onTreeFx then G.onTreeFx(e) end
      elseif k == "gimp" then kineticHit(e.p, e.n, e.d, e.h, e.s)   -- 穿甲弹打在地上（Ents.lua）
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
      elseif k == "shotIgn" then   -- 抛射的弹点火了：喷火、拖烟，发动机的时间从这里算
        local s = flying[e.id]
        if s then ejIgnite(s) end
      elseif k == "shotAct" then   -- 主动雷达弹导引头开机（服务器 Air.lua arhStep）：雷达屏上数据链虚线变实线
        local fs = flying[e.id]
        if fs then fs.act, fs.lost = true, false end
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
      elseif k == "spots" then spots(e.list, e.ids)
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

  -- 预建（审查 12：层第一次用到才现建，第一炮、第一次扫射一帧里新建十几个发射器会顿一下）：进局时把开炮（口径系数 k≈1）、
  --   榴弹（S = 1）、穿甲弹打地、机枪打地常用的那几层排进 VfxLib，一帧建 4 个（几十帧建完；殉爆那几层 WreckFx.lua 自己排）。
  --   按地面分的层按这张图的地面代号排；11-27 复核：原来只按 Fx 初始化那一刻的图排——地图是进服以后才投出来的（雪山、沙海），
  --   那张图的地面（雪 i、冰 j、沙 n）那几层没预建，第一炮、第一发还是现建：换图（G.onMap）时把新地面的补排上
  do
    local warmed = {}   -- 哪些地面代号排过了
    local function mapCodes()
      local codes = { "d", "v", "r" }
      if MapM.DESERT then codes[#codes + 1] = "n" end
      if MapM.NAME == "snow" then codes[#codes + 1] = "i" codes[#codes + 1] = "j" end
      return codes
    end
    local list = {}
    local function add(name, s, var, n) list[#list + 1] = { name, s, var, n } end
    add("mFlash", 1, nil, 2)   -- 炮口、炮口前各一颗：两处
    add("mBrake", 1, nil, 2)   -- 制退器左右：两处
    for _, nm in ipairs({ "mBall", "mTongue", "mShock", "mSpark", "eBall", "eGrey", "eSpark", "eSparkA", "eIce", "eMetal", "eJet", "eShock",
      "acFlash", "acCore", "acSpark", "mzR", "mzH", "mzA", "mzAc", "hsSpark", "kSpark", "kIce", "Imp_mist", "Imp_ripple", "splash" }) do add(nm, 1) end
    add("hsFlash", 2.1)   -- 坦克炮弹打在钢甲上（大小按口径 2.1）
    add("kFlash", 2.1)    -- 穿甲弹打在硬地上
    for _, v in ipairs({ false, "C", "S" }) do
      add("mTrail", 1, v or nil)
      add("mHang", 1, v or nil)
    end
    add("eFlash", 1)
    add("eFlash", 1, "H")
    add("eSoot", 1)
    add("eSoot", 1, "b")
    add("eAirSoot", 1)
    add("Imp_spout", 1)
    add("Imp_spout", 1, "L")
    local function perCode(c)
      if warmed[c] then return end
      warmed[c] = true
      for _, f in ipairs({ "", "C", "S" }) do
        add("gFan", 1, c .. f)
        add("gRise", 1, c .. f)
      end
      add("gFan", 1, c .. "B")
      add("gGrit", 1, c)
      add("gRing", 1, c)
      add("eCol", 1, c)
      add("eCol", 1, c .. "g")
      add("eClod", 1, c)
      add("eRing", 1, c)
      add("eCloud", 1, c)
      add("acDust", 1, c)
      add("acChips", 1, c)
      for _, nm in ipairs({ "kFount", "kClod", "kRing", "kHang" }) do add(nm, 2.1, c) end
      add("kFurrow", 2.1, c, 5)   -- 擦地犁沟：一串五团，五处
      local nm = IMPNAME[c]
      if nm then
        add("Imp_" .. nm, 1)
        add("Imp_" .. nm, 1, "L")
      end
      local bits = IMPBITS[c]
      if bits then
        add("Imp_" .. bits, 1)
        add("Imp_" .. bits, 1, "L")
      end
      if c == "i" then add("eClod", 1, "iD") end
    end
    for _, c in ipairs(mapCodes()) do perCode(c) end
    add("gGrass", 1)
    VL.prewarmLater(list)
    if G.onMap then
      G.onMap(function()
        list = {}
        for _, c in ipairs(mapCodes()) do perCode(c) end
        if #list > 0 then VL.prewarmLater(list) end
      end)
    end
  end

  function G.stepFx(dt)
    VL.step(dt or 1 / 60)
    stepShots(dt or 1 / 60)
    stepGuns()
    if #drops > 0 then stepDrops(dt or 1 / 60) end
  end
end

return Fx
