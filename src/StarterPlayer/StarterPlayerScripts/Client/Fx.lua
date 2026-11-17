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
  local function flash(p, color, range, bright, t)
    local h = part(nil, V(0.2, 0.2, 0.2), CFrame.new(p), color, Enum.Material.SmoothPlastic, 1)
    local pl = Instance.new("PointLight")
    pl.Color, pl.Range, pl.Brightness, pl.Shadows = color, range, bright, range > 20
    pl.Parent = h
    tween(pl, t, { Brightness = 0 })
    Debris:AddItem(h, t + 0.05)
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
  -- 开枪的后坐：视线往上一跳
  function G.kick(w)
    local k = (w.dmg or 20) / 600
    cam.CFrame = cam.CFrame * CFrame.Angles(k * (0.6 + math.random() * 0.4), (math.random() - 0.5) * k * 0.6, 0)
  end

  ---------------------------------------------------------------- 曳光、枪口火光

  local TRACER = { m4 = RGB(255, 220, 140), rifle = RGB(255, 220, 140), lmg = RGB(255, 190, 110), sniper = RGB(255, 245, 210) }
  function G.gunFx(id, a, b, mine)
    local d = b - a
    local L = d.Magnitude
    if L < 0.5 then return end
    local col = TRACER[id] or RGB(255, 220, 140)
    local len = math.min(L, 14)
    local tr = part(nil, V(0.12, 0.12, len), CFrame.lookAt(a + d.Unit * len / 2, b), col, Enum.Material.Neon, 0.1)
    local speed = 900
    local tw = tween(tr, L / speed, { CFrame = CFrame.lookAt(b - d.Unit * len / 2, b + d.Unit) }, Enum.EasingStyle.Linear)
    Debris:AddItem(tr, L / speed + 0.05)
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
    local snd = (id == "smgsd") and "quiet" or ((id == "sniper" or id == "lmg" or id == "pistol") and id or "rifle")
    G.playSound(snd, a)
  end

  ---------------------------------------------------------------- 爆炸

  local function boom(p, s)
    s = s or 1
    local f = part(BALL, V(2, 2, 2) * s, CFrame.new(p), RGB(255, 170, 60), Enum.Material.Neon, 0)
    tween(f, 0.35, { Size = V(16, 16, 16) * s, Transparency = 1 })
    Debris:AddItem(f, 0.4)
    flash(p + V(0, 3, 0), RGB(255, 150, 70), math.min(60, 34 * s), 10, 0.9)   -- 爆炸把周围照亮一下
    for i = 1, 5 do
      local off = V(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 8 * s
      local sm = part(BALL, V(4, 4, 4) * s, CFrame.new(p + off), RGB(70, 66, 62), Enum.Material.SmoothPlastic, 0.15)
      tween(sm, 2 + math.random(), { Size = V(14, 14, 14) * s, Transparency = 1, CFrame = CFrame.new(p + off + V(0, 10 * s, 0)) })
      Debris:AddItem(sm, 3.2)
    end
    G.playSound("boom", p)
    local d = (p - cam.CFrame.Position).Magnitude
    if d < 160 * s then G.shake(0.5 * s * (1 - d / (160 * s))) end
  end
  G.boom = boom

  local function splash(p)
    local w = part(CYL, V(1, 3, 3), CFrame.new(p) * CFrame.Angles(0, 0, math.pi / 2), RGB(230, 240, 245), Enum.Material.SmoothPlastic, 0.2)
    tween(w, 0.8, { Size = V(14, 7, 7), Transparency = 1 })
    Debris:AddItem(w, 0.9)
    G.playSound("splash", p)
  end

  ---------------------------------------------------------------- 飞行中的弹（照服务器给的初速本地算，收到结束就删）

  local GRAV = V(0, -workspace.Gravity * 0.55, 0)
  local flying = {}
  local AD = require(game:GetService("ReplicatedStorage"):WaitForChild("AirDefs"))
  local WM = require(game:GetService("ReplicatedStorage"):WaitForChild("WeaponModels"))
  local function newShot(e)
    local kind = e.kind
    local aw = e.w and AD.W[e.w]
    if aw and (kind == "missile" or kind == "bomb") and typeof(e.v) == "Vector3" and e.v.Magnitude > 0.1 then   -- 机载导弹、炸弹：按型号的外形（折叠翼展开）
      local cf = CFrame.lookAt(e.p, e.p + e.v)
      local mdl = WM.make(FXF, aw, cf, true)
      local glow = nil
      if kind == "missile" then
        glow = part(BALL, V(1.1, 1.1, 1.1) * math.max(1, aw.shape and aw.shape.d * 1.6 or 1), CFrame.new(e.p), RGB(255, 200, 120), Enum.Material.Neon, 0)
        glowOn(glow, RGB(255, 180, 100), 22, 4)   -- 尾焰照亮弹体和周围
        G.playSound("rocket", e.p)
      end
      flying[e.id] = { wm = mdl, glow = glow, half = (aw.shape and aw.shape.L or 5) / 2, p = e.p, v = e.v, gb = kind == "bomb", t = 0, kind = kind, trailT = 0,
        burn = aw.burn or 4, cfs = table.create(#mdl.parts) }
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
    if kind == "rocket" or kind == "missile" then G.playSound("rocket", e.p) end
  end
  local function endShot(id)
    local s = flying[id]
    if s then
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

  function G.onFx(list)
    for _, e in ipairs(list) do
      local k = e.k
      if k == "gun" then
        if e.by ~= me.UserId then
          G.gunFx(e.w, e.a, e.b, false)
          if G.radarShot then G.radarShot(e.a, e.t, e.q) end   -- 雷达：敌人开枪的地方闪一下（Hud.lua）
        end
      elseif k == "boom" then boom(e.p, e.s)
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
      end
    end
  end

  function G.stepFx(dt) stepShots(dt or 1 / 60) end
end

return Fx
