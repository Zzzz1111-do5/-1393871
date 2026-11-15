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
  local function tween(o, t, props, style)
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
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
  local function newShot(e)
    local kind = e.kind
    local body
    if kind == "shell" then   -- 炮弹：一道亮的曳光
      local big = e.f == "tank"
      body = part(CYL, big and V(5, 0.45, 0.45) or V(2.6, 0.22, 0.22), CFrame.new(e.p), big and RGB(255, 236, 190) or RGB(255, 200, 120), Enum.Material.Neon, 0)
      flying[e.id] = { body = body, p = e.p, v = e.v, g = e.g, gs = e.gs or 1, t = 0, kind = kind, trailT = 0 }
      return
    elseif kind == "grenade" then
      body = part(BALL, V(0.7, 0.7, 0.7), CFrame.new(e.p), RGB(70, 80, 60), Enum.Material.Metal, 0)
    else
      body = part(CYL, V(2.2, 0.5, 0.5), CFrame.new(e.p), RGB(80, 86, 70), Enum.Material.Metal, 0)
      local glow = part(BALL, V(0.9, 0.9, 0.9), CFrame.new(e.p), RGB(255, 200, 120), Enum.Material.Neon, 0)
      glow.Name = "Glow"
      glow.Parent = body
    end
    flying[e.id] = { body = body, p = e.p, v = e.v, g = e.g, t = 0, kind = kind, trailT = 0 }
    if kind == "rocket" or kind == "missile" then G.playSound("rocket", e.p) end
  end
  local function endShot(id)
    local s = flying[id]
    if s then
      s.body:Destroy()
      flying[id] = nil
    end
  end
  local function stepShots(dt)
    for id, s in pairs(flying) do
      s.t += dt
      if s.g then s.v += GRAV * (s.gs or 1) * dt end
      s.p += s.v * dt
      if s.kind == "grenade" then
        s.body.CFrame = CFrame.new(s.p)
      elseif s.kind == "shell" then
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
        if g then g.CFrame = CFrame.new(s.p - s.v.Unit * 1.2) end
        s.trailT += dt
        if s.trailT > 0.04 then   -- 尾烟
          s.trailT = 0
          local sm = part(BALL, V(1, 1, 1), CFrame.new(s.p - s.v.Unit * 1.5), RGB(200, 200, 200), Enum.Material.SmoothPlastic, 0.3)
          tween(sm, 1.2, { Size = V(3.5, 3.5, 3.5), Transparency = 1 })
          Debris:AddItem(sm, 1.25)
        end
      end
      if s.t > 15 then endShot(id) end
    end
  end

  -- 车炮开火：炮口火光、一团烟、坦克炮还有一圈扬尘；离得近震屏
  local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
  local function vfire(e)
    local big = e.f == "tank" or e.f == "arty"
    local dir = (typeof(e.d) == "Vector3") and e.d or V(0, 0, -1)
    local fl = part(BALL, big and V(4, 4, 4) or V(1.6, 1.6, 1.6), CFrame.new(e.p + dir * (big and 2 or 0.6)), RGB(255, 210, 120), Enum.Material.Neon, 0)
    tween(fl, big and 0.12 or 0.06, { Transparency = 1, Size = (big and V(9, 9, 9) or V(3, 3, 3)) })
    Debris:AddItem(fl, 0.15)
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
    if G.vehRecoil and e.id then G.vehRecoil(e.id) end
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
        if e.by ~= me.UserId then G.gunFx(e.w, e.a, e.b, false) end
      elseif k == "boom" then boom(e.p, e.s)
      elseif k == "shot" then newShot(e)
      elseif k == "shotEnd" then endShot(e.id)
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
      elseif k == "smokeLaunch" then smokeLaunch(e)
      elseif k == "smokeCloud" then smokeCloud(e)
      end
    end
  end

  function G.stepFx(dt) stepShots(dt or 1 / 60) end
end

return Fx
