-- Roblox全面大战场（客户端）——爆反起爆、主动防御拦截的特效（用户 11-19：给坦克实现爆反和主动拦截，画质要惊艳）
--   era（服务器 Era.lua）：块的位置 p、朝外 n——顺着朝外喷出去的一团火（白热的芯、橙色的外焰）、一圈冲击波、一把火星、几片翻滚的钢片、
--     一团黑灰色的硝烟慢慢往上飘；一声干脆的爆响叠一声闷响；夜里一闪照亮车身和地面；自己在车里 / 离得近的震一下
--   aps（服务器 Aps.lua）：那一侧的发射器口一闪、一道拦截弹的亮线射到来袭弹那里，空中炸开（火球小、破片锥朝外喷）、来袭弹的碎片
--     顺着原来的方向散落；发射器「砰」一声、空中「嘭」一声
--   都登记在 G.fxExtra（Fx.lua 的 onFx 分发）
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ArmorFx = {}

function ArmorFx.init(G)
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
  local NEON = Enum.Material.Neon
  local EXP = "rbxasset://sounds/impact_explosion_03.mp3"
  local THUD = "rbxasset://sounds/action_jump_land.mp3"
  local TICK = "rbxasset://sounds/volume_slider.ogg"
  local me = Players.LocalPlayer
  local part = G.fxPart
  local function tween(o, t, props, style, dir)
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
  end
  local SND = {
    era = { { id = EXP, vol = 1.1, s = { 1.35, 1.5 }, reg = { 0.02, 0.7 }, eq = { 2, 4, 3 } }, { id = THUD, vol = 1.0, s = { 0.62, 0.7 }, eq = { 6, 0, -6 } } },
    apsPop = { { id = EXP, vol = 0.55, s = { 2.2, 2.5 }, reg = { 0.02, 0.25 }, eq = { -4, 4, 6 } }, { id = TICK, vol = 0.8, s = { 0.5, 0.6 } } },
    apsBoom = { { id = EXP, vol = 0.9, s = { 1.15, 1.3 }, reg = { 0.02, 0.9 }, eq = { 3, 2, 0 } } },
  }

  -- 一个地方冒一团烟（粒子一次喷出来，烟自己慢慢散）
  local function smokeAt(p, n, color, size, life, count)
    local holder = part(nil, V(0.2, 0.2, 0.2), CF(p), RGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
    local em = Instance.new("ParticleEmitter")
    em.Texture = "rbxasset://textures/particles/smoke_main.dds"
    em.Color = ColorSequence.new(color, color:Lerp(RGB(30, 30, 30), 0.4))
    em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(0.4, size), NumberSequenceKeypoint.new(1, size * 1.8) })
    em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
    em.Lifetime = NumberRange.new(life * 0.6, life)
    em.Speed = NumberRange.new(3, 9)
    em.SpreadAngle = Vector2.new(50, 50)
    em.Acceleration = V(0, 2.2, 0)
    em.Drag = 2.2
    em.RotSpeed = NumberRange.new(-40, 40)
    em.Rotation = NumberRange.new(0, 360)
    em.LightInfluence = 0.85
    em.Enabled = false
    em.Parent = holder
    holder.CFrame = CFrame.lookAt(p, p + n)
    em.EmissionDirection = Enum.NormalId.Front
    em:Emit(count)
    Debris:AddItem(holder, life + 0.5)
  end

  -- 火星：count 颗沿着 n 周围的半球飞出去，划一道就灭
  local function sparks(p, n, count, speed, color)
    for _ = 1, count do
      local d = (n + V(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6).Unit
      local len = speed * (0.5 + math.random() * 0.6)
      local s = part(nil, V(0.09, 0.09, 0.7), CFrame.lookAt(p, p + d), color or RGB(255, 196, 110), NEON, 0)
      tween(s, 0.28 + math.random() * 0.2, { CFrame = CFrame.lookAt(p + d * len + V(0, -len * 0.15, 0), p + d * (len + 1)), Size = V(0.04, 0.04, 0.25), Transparency = 1 })
      Debris:AddItem(s, 0.55)
    end
  end

  -- 翻滚飞出去的碎片（钢片），落一点再淡掉
  local function debris(p, n, count, color, sz)
    for _ = 1, count do
      local d = (n * 0.8 + V(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)).Unit
      local s = part(nil, V(sz * (0.6 + math.random()), sz * (0.5 + math.random() * 0.6), 0.06), CF(p), color, Enum.Material.CorrodedMetal, 0)
      local far = 4 + math.random() * 7
      local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
      tween(s, 0.9, { CFrame = CF(p + d * far + V(0, -2.5, 0)) * spin }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
      task.delay(0.9, function() if s.Parent then tween(s, 0.5, { Transparency = 1 }) end end)
      Debris:AddItem(s, 1.5)
    end
  end

  -- 一团火：白热的芯 + 橙色外焰，顺着 n 拉长
  local function fireball(p, n, r)
    local look = CFrame.lookAt(p, p + n)
    local core = part(BALL, V(r * 0.5, r * 0.5, r * 0.9), look * CF(0, 0, -r * 0.2), RGB(255, 246, 220), NEON, 0)
    tween(core, 0.14, { Size = V(r * 1.1, r * 1.1, r * 2.1), Transparency = 1 })
    Debris:AddItem(core, 0.2)
    local outer = part(BALL, V(r * 0.8, r * 0.8, r * 1.2), look * CF(0, 0, -r * 0.4), RGB(255, 142, 44), NEON, 0.1)
    tween(outer, 0.3, { Size = V(r * 2.2, r * 2.2, r * 3.4), CFrame = look * CF(0, 0, -r * 1.1), Transparency = 1 })
    Debris:AddItem(outer, 0.35)
    -- 冲击波：贴着块的面往外扩的一圈
    local ring = part(CYL, V(0.08, r * 0.6, r * 0.6), look * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 226, 190), NEON, 0.35)
    tween(ring, 0.25, { Size = V(0.04, r * 4.5, r * 4.5), Transparency = 1 })
    Debris:AddItem(ring, 0.3)
  end

  local function nearMe(p, r)
    local cam = workspace.CurrentCamera
    return cam and (cam.CFrame.Position - p).Magnitude < r
  end

  G.fxExtra = G.fxExtra or {}

  G.fxExtra.era = function(e)
    if typeof(e.p) ~= "Vector3" then return end
    local n = (typeof(e.n) == "Vector3" and e.n.Magnitude > 0.5) and e.n.Unit or V(0, 1, 0)
    local p = e.p
    if G.flash then G.flash(p + n, RGB(255, 170, 90), 34, 7, 0.22) end
    fireball(p + n * 0.3, n, 2.4)
    sparks(p + n * 0.3, n, 18, 16)
    debris(p + n * 0.2, n, 4, RGB(64, 62, 54), 0.5)
    smokeAt(p + n * 0.8, n, RGB(70, 68, 64), 5, 3.2, 14)
    if G.sfx then G.sfx(SND.era, p, { must = true }) end
    if G.shake and nearMe(p, 60) then
      local mine = G.drive and G.drive.id == e.id
      G.shake(mine and 0.45 or 0.2)
    end
    G.eraFxCount = (G.eraFxCount or 0) + 1   -- 测试用
  end

  G.fxExtra.aps = function(e)
    if typeof(e.p) ~= "Vector3" then return end
    local p = e.p
    -- 发射器在哪：那辆车的炮塔上、来袭弹那一侧的发射器（VehModels 摆的）；找不到就从车中心
    local lp = nil
    local v = G.viewById and G.viewById(e.id)
    local M = v and v.M
    if M and M.eraL and M.eraL.aps and v.tF then
      local tp = M.tpiv or V()
      for _, a in ipairs(M.eraL.aps.l or {}) do
        if (a[1] - tp.X) * (e.side or 1) > 0 then lp = (v.tF * CF(V(a[1], a[2], a[3]) - tp + V(a[4], a[5], a[6]) * 1.6)).Position end
      end
    end
    if not lp and v and v.root then lp = v.root.CFrame.Position + V(0, 3, 0) end
    lp = lp or (p - (typeof(e.v) == "Vector3" and e.v or V(0, -1, 0)) * 10)
    local dir = (p - lp)
    local dist = dir.Magnitude
    dir = dist > 1e-3 and dir.Unit or V(0, 1, 0)
    -- 发射器口一闪、一团白烟
    if G.flash then G.flash(lp, RGB(255, 214, 150), 20, 5, 0.12) end
    local puff = part(BALL, V(1.2, 1.2, 1.2), CF(lp), RGB(255, 236, 200), NEON, 0.1)
    tween(puff, 0.12, { Size = V(2.4, 2.4, 2.4), Transparency = 1 })
    Debris:AddItem(puff, 0.15)
    smokeAt(lp, dir, RGB(200, 200, 196), 2.2, 1.6, 6)
    if G.sfx then G.sfx(SND.apsPop, lp, { must = true }) end
    -- 拦截弹的亮线（一下就到）
    local beam = part(nil, V(0.16, 0.16, dist), CFrame.lookAt(lp + dir * dist / 2, p), RGB(255, 230, 170), NEON, 0)
    tween(beam, 0.1, { Size = V(0.05, 0.05, dist), Transparency = 1 })
    Debris:AddItem(beam, 0.12)
    -- 空中炸开：火球、朝外的破片锥、来袭弹的碎片顺着原来的方向散
    task.delay(0.04, function()
      if G.flash then G.flash(p, RGB(255, 160, 80), 30, 6, 0.2) end
      fireball(p, dir, 1.8)
      sparks(p, dir, 22, 20, RGB(255, 210, 150))
      local tv = (typeof(e.v) == "Vector3" and e.v.Magnitude > 0.5) and e.v.Unit or -dir
      debris(p, tv, 5, RGB(80, 80, 76), 0.35)
      smokeAt(p, tv, RGB(56, 54, 52), 4, 2.6, 12)
      if G.sfx then G.sfx(SND.apsBoom, p, { must = true }) end
      if G.shake and nearMe(p, 70) then G.shake((G.drive and G.drive.id == e.id) and 0.3 or 0.12) end
    end)
    G.apsFxCount = (G.apsFxCount or 0) + 1   -- 测试用
  end

  -- 栅栏装甲卡住火箭弹（Kit.lua）：引信被栅条压坏、弹头没炸——一串火星、弹体碎片掉在地上、一点灰
  G.fxExtra.slat = function(e)
    local p = e.p
    if typeof(p) ~= "Vector3" then return end
    local n = (typeof(e.n) == "Vector3" and e.n.Magnitude > 0.1) and e.n.Unit or V(0, 1, 0)
    sparks(p, n, 16, 14, RGB(255, 200, 120))
    debris(p, n + V(0, 0.6, 0), 4, RGB(62, 66, 54), 0.25)
    smokeAt(p, n, RGB(150, 146, 136), 1.4, 1.4, 5)
    if G.playSound then G.playSound("ric", p, 1.1) end
  end
  -- 扫雷犁把雷翻到一边（Kit.lua）：一团土、一颗雷滚出去
  G.fxExtra.plowMine = function(e)
    local p = e.p
    if typeof(p) ~= "Vector3" then return end
    smokeAt(p + V(0, 0.5, 0), V(0, 1, 0), RGB(150, 128, 96), 2.2, 1.8, 10)
    local mine = part(CYL, V(0.35, 1.2, 1.2), CF(p + V(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(70, 76, 58), Enum.Material.Metal, 0)
    local side = (math.random() < 0.5) and -1 or 1
    tween(mine, 0.6, { CFrame = CF(p + V(side * 4, 0.3, 0)) * CFrame.Angles(math.rad(80), 0, math.pi / 2) })
    Debris:AddItem(mine, 6)
  end
  -- 激光压制（JD-3）：车上的干扰头一闪红光
  G.fxExtra.dazzle = function(e)
    local v = e.id and G.viewById and G.viewById(e.id)
    local cf = v and (v.tF or v.hullF)
    local p = cf and cf.Position
    if p and G.flash then G.flash(p + V(0, 2.5, 0), RGB(255, 60, 40), 26, 4, 0.25) end
  end
end

return ArmorFx
