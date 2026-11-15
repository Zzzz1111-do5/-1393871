-- 暗剑：登岛战（客户端）——特效与音效：曳光、枪口火光、飞行中的火箭弹 / 导弹 / 手雷（照服务器给的初速本地算弹道）、炮弹落下的呼啸、爆炸、溅水、
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

  local TRACER = { rifle = RGB(255, 220, 140), carbine = RGB(255, 220, 140), lmg = RGB(255, 190, 110), sniper = RGB(255, 245, 210), smg = RGB(255, 225, 160),
    smgsd = RGB(200, 200, 200), pistol = RGB(255, 225, 160) }
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
    if kind == "grenade" then
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
      if s.g then s.v += GRAV * dt end
      s.p += s.v * dt
      if s.kind == "grenade" then
        s.body.CFrame = CFrame.new(s.p)
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
      end
    end
  end

  function G.stepFx(dt) stepShots(dt or 1 / 60) end
end

return Fx
