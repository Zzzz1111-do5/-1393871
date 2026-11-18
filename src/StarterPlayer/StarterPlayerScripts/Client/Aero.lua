-- Roblox全面大战场（客户端）——飞机的气动特效（用户 11-18：转弯的时候机翼内侧顺着出来的白色云雾；还有超音速的音障）
--   ① 机翼凝结雾：大过载 / 大迎角时，翼根前缘（边条）和内翼顺着机翼往后拖一片白雾（锁在飞机上的粒子），拉得越狠越浓
--   ② 翼尖涡流：同样大过载时两个翼尖各拖一道细白线（Trail）
--   ③ 跨音速蒸汽锥：快到音速时机身中段一圈白雾往后张开成锥，过了音速就散掉
--      游戏里的速度是按比例缩过的（歼-15T 加力最快 566 km/h），所以「一马赫」按各型加力最大速度的 0.965 算：
--      加力平飞加速到头的那几秒、俯冲的时候过音障；只有有加力的战斗机才过得了，A-10、轰炸机、无人机、直升机没有
--   ④ 音爆：往上越过一马赫的那一下，原地炸开一团白雾、闷响一声（自己开的镜头抖一下）；降回 0.95 以下才会再有
--   离镜头 1800 格外全关；自己开的按本地算的加速度算过载，别人的按属性里的拉杆量和收到的速度估
--   零件用 AirModels 的 AM.attach 挂在飞机上（每帧跟着 AM.pose 一起挪），飞机的样子重建 / 删掉时一起没了
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Aero = {}

function Aero.init(G)
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local NS, NSK = NumberSequence.new, NumberSequenceKeypoint.new
  local GR = AD.GRAV or 27.4
  local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
  local VAPOR = RGB(232, 238, 244)

  local function emitter(part, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Name = o.name or "Vapor"
    pe.Texture = SMOKE
    pe.EmissionDirection = Enum.NormalId.Back   -- 零件的 +Z：机尾方向
    pe.LockedToPart = true                      -- 跟着飞机走（不锁的话几百格每秒，一下就拖没了）
    pe.LightEmission, pe.LightInfluence = o.le or 0.15, 1
    pe.Lifetime = o.life
    pe.Speed = o.speed
    pe.SpreadAngle = o.spread or Vector2.new(6, 3)
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-60, 60)
    pe.Size = o.size
    pe.Transparency = o.tr
    pe.Color = ColorSequence.new(VAPOR)
    pe.Rate = 0
    pe.Enabled = false
    pe.Parent = part
    return pe
  end
  local function holder(M, cf0, name)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = V(0.2, 0.2, 0.2)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    AM.attach(M, p, cf0)
    return p
  end

  -- 搭一架飞机的特效零件（离镜头近、第一次要用时）
  local function rig(v)
    local M, d = v.M, v.def
    local R = { wing = {}, cone = {}, tips = {} }
    local w = d.wing
    local fusW = (d.fus and d.fus.w) or 4
    local fusH = (d.fus and d.fus.h) or 4
    local tipL, tipR = AM.tips(M)
    local wy = (tipL and tipL.Y) or (w and w.y) or 0
    -- ① 翼根前缘（边条）、内翼中段：机体坐标，机头朝 −Z
    if w and w.xt then
      local xr = w.xr or fusW / 2
      local span = w.xt - fusW / 2
      for _, s in ipairs({ 1, -1 }) do
        for k, f in ipairs({ 0.06, 0.34 }) do
          local x = s * (fusW / 2 + span * f + 0.4)
          local u = math.clamp((math.abs(x) - xr) / math.max(1, w.xt - xr), 0, 1)
          local zl = (w.zr0 or 0) + ((w.zt0 or 0) - (w.zr0 or 0)) * u   -- 这一截的前缘
          local chord = math.max(4, ((w.zr1 or 0) - (w.zr0 or 0)) * (1 - u) + ((w.zt1 or 0) - (w.zt0 or 0)) * u)
          local p = holder(M, CF(x, wy + 0.7 + (k == 1 and 0.3 or 0), zl + 1.2), "Vapor")
          local pe = emitter(p, { life = NumberRange.new(0.16, 0.26), speed = NumberRange.new(chord * 3.2, chord * 4.2),
            size = NS({ NSK(0, 1.6 + k * 0.6), NSK(0.5, 3.4 + k), NSK(1, 4.6 + k) }), tr = NS({ NSK(0, 0.72), NSK(0.2, 0.42), NSK(1, 1) }) })
          table.insert(R.wing, { pe = pe, base = (k == 1) and 1 or 0.7 })
        end
      end
    end
    -- ② 翼尖涡流：翼尖后缘两个挨着的附着点之间拖一道
    if tipL then
      for _, tp in ipairs({ tipL, tipR }) do
        local p = holder(M, CF(tp), "Vortex")
        local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
        a0.Position, a1.Position = V(0, 0.18, 0), V(0, -0.18, 0)
        a0.Parent, a1.Parent = p, p
        local tr = Instance.new("Trail")
        tr.Attachment0, tr.Attachment1 = a0, a1
        tr.Lifetime = 0.55
        tr.MinLength = 0.2
        tr.FaceCamera = true
        tr.LightEmission = 0.25
        pcall(function() tr.LightInfluence = 1 end)   -- 老版本的 Roblox / 测试台没有这个属性
        tr.Color = ColorSequence.new(VAPOR)
        tr.Transparency = NS({ NSK(0, 1), NSK(0.05, 0.55), NSK(1, 1) })
        tr.WidthScale = NS({ NSK(0, 1), NSK(1, 2.2) })
        tr.Enabled = false
        tr.Parent = p
        table.insert(R.tips, tr)
      end
    end
    -- ③ 蒸汽锥：翼根前缘那一截机身一圈 10 个，往后、往外张开
    if d.ab then
      local zc = (w and w.zr0) or -d.L * 0.1
      local rr = math.max(fusW, fusH) * 0.55 + 0.6
      for i = 0, 9 do
        local a = i / 10 * math.pi * 2
        local out = V(math.cos(a), math.sin(a), 0)
        local pos = V(0, wy, zc) + out * rr
        local dir = (V(0, 0, 1) + out * 0.55).Unit
        local p = holder(M, CFrame.lookAt(pos, pos - dir), "VaporCone")   -- 零件的 +Z（Back）朝 dir：往后往外
        table.insert(R.cone, emitter(p, { name = "Cone", life = NumberRange.new(0.1, 0.18), speed = NumberRange.new(d.L * 1.2, d.L * 1.7),
          spread = Vector2.new(4, 4), size = NS({ NSK(0, rr * 0.5), NSK(1, rr * 1.4) }), tr = NS({ NSK(0, 0.75), NSK(0.15, 0.45), NSK(1, 1) }), le = 0.2 }))
      end
    end
    v.aero = R
    return R
  end

  local function setRate(pe, rate)
    rate = math.floor(rate / 5 + 0.5) * 5   -- 分档，变了才改（每帧改粒子属性费）
    if pe.Rate ~= rate then pe.Rate = rate end
    local on = rate > 0
    if pe.Enabled ~= on then pe.Enabled = on end
  end

  -- ④ 音爆：原地炸开一团白雾（不锁在飞机上，留在空中散掉）、闷响一声
  local function sonicBoom(pos, vel, own)
    if G.fxPart then
      local p = G.fxPart(Enum.PartType.Ball, V(1, 1, 1), CFrame.new(pos - vel * 0.04), VAPOR, Enum.Material.SmoothPlastic, 1)
      local pe = Instance.new("ParticleEmitter")
      pe.Texture = SMOKE
      pe.LightEmission, pe.LightInfluence = 0.2, 1
      pe.Lifetime = NumberRange.new(0.6, 1.1)
      pe.Speed = NumberRange.new(45, 85)
      pe.SpreadAngle = Vector2.new(180, 180)
      pe.Drag = 4
      pe.Rotation = NumberRange.new(0, 360)
      pe.Size = NS({ NSK(0, 5), NSK(1, 17) })
      pe.Transparency = NS({ NSK(0, 0.35), NSK(1, 1) })
      pe.Color = ColorSequence.new(VAPOR)
      pe.Rate = 0
      pe.Parent = p
      pe:Emit(36)
      Debris:AddItem(p, 1.6)
    end
    if G.playSound then G.playSound("boom", pos, 1.25) end
    if own and G.shake then G.shake(0.35) end
  end

  local function allOff(R)
    R.on = false
    for _, it in ipairs(R.wing) do setRate(it.pe, 0) end
    for _, pe in ipairs(R.cone) do setRate(pe, 0) end
    for _, tr in ipairs(R.tips) do tr.Enabled = false end
  end

  -- 每帧（Fly.lua 的飞机样子那里调）：v 是飞机的样子，own 是自己开的这架（Fly 的 st）或 nil
  function G.aeroStep(v, dt, own, camPos)
    local d, M = v.def, v.M
    if not d or not M or d.kind ~= "jet" then return end
    local R = v.aero
    if v.wreck then
      if R and R.on then allOff(R) end
      return
    end
    local pos = v.cf.Position
    if (pos - camPos).Magnitude > 1800 then
      if R and R.on then allOff(R) end
      return
    end
    R = R or rig(v)
    R.on = true
    -- 速度、过载
    local vel = (own and own.vel) or (v.fl and v.fl.vel) or Vector3.zero
    local spd = vel.Magnitude
    local n
    if own and own.accV then   -- 自己开的：本地算的加速度，加上抵消重力的那 1 g，去掉沿航迹的部分
      local a = own.accV + V(0, GR, 0)
      local fwd = (spd > 1) and vel.Unit or v.cf.LookVector
      n = (a - fwd * a:Dot(fwd)).Magnitude / GR
    else   -- 别人的：拉杆量 × 速度估一个
      local pit = math.abs((v.c and v.c.pit) or 0)
      n = 1 + pit * (d.g or 8) * math.clamp(spd / math.max(d.vMax, 1), 0, 1.2)
    end
    v.aeroN = (v.aeroN or n) + (n - (v.aeroN or n)) * math.min(1, dt * 6)
    local fast = math.clamp((spd / math.max(d.vMax, 1) - 0.3) / 0.3, 0, 1)   -- 慢的时候没有
    local kv = math.clamp((v.aeroN - 3.2) / 3.0, 0, 1) * fast                 -- 3 g 多开始有，6 g 多最浓
    for _, it in ipairs(R.wing) do setRate(it.pe, 110 * kv * it.base) end
    local trOn = kv > 0.25
    for _, tr in ipairs(R.tips) do if tr.Enabled ~= trOn then tr.Enabled = trOn end end
    -- 跨音速
    if #R.cone > 0 then
      local mach = spd / (d.vMax * 0.965)
      if v.boomed == nil then v.boomed = mach >= 0.97 end   -- 第一次看到就已经超音速了：不补一声
      local kc = math.clamp((mach - 0.92) / 0.06, 0, 1) * math.clamp((1.035 - mach) / 0.03, 0, 1)
      for _, pe in ipairs(R.cone) do setRate(pe, 140 * kc) end
      if mach >= 1.0 and not v.boomed then
        v.boomed = true
        sonicBoom(pos, vel, own)
      elseif mach < 0.95 then
        v.boomed = false
      end
    end
  end
end

return Aero
