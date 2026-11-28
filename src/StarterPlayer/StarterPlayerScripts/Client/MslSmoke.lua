-- Roblox全面大战场（客户端）——导弹 / 火箭弹的尾焰、尾烟（用户 11-28「然后导弹尾烟不够真实」）
--   原来（Fx.lua）：每隔几十毫秒在弹尾放一颗实心的白球、补间放大变透明——飞得快的弹（一秒两三千格）球和球之间隔着几十上百格，
--   天上是一串断开的珠子；烟不胀开、不翻、不飘，颜色一样，硬邦邦一颗颗。现在照真的固体火箭发动机的烟：
--   · 尾焰：喷口一截白黄 → 橙的火舌（Trail，最长几格：跟着弹走，不随速度拖长），原来那颗发光球是喷口的亮点
--   · 烟带（Trail）：一帧一段连着画，再快也不断；刚出来细、密，带一点火光映的暖色，越老越宽、越淡、越灰。挂在天上多久按发动机（AirDefs smoke）：
--       low 低烟发动机（AIM-120、霹雳-15、AIM-9X）细、淡、一秒多就散；med 一般（R-27、霹雳-12、反坦克导弹）；
--       heavy 老式发动机 / 助推器（霹雳-2、AIM-54、陶、舰艇导弹的助推器）又粗又浓、挂六七秒
--   · 烟团（ParticleEmitter，自带的柔边烟贴图）：每帧在这一帧飞过的那一段里撒几团——小零件拉成那一段那么长，粒子在它里面随机出生，
--       所以再快也是连着的；一团团往外胀、慢慢转、顺风飘、往上浮一点，烟带外面一层翻滚的毛边。撒多少按飞了多远（不按时间），
--       每秒有上限（飞得快就稀一点），按 G.perfK、离镜头远近、同时在飘的总量少撒
--   · 助推 + 续航的发动机（AirDefs mt = "bs"）：前 35% 燃烧时间是助推段，烟和火舌都浓、长；续航段细一点、淡一点（另起一条烟带：
--       Trail 的宽度 / 透明度曲线一改，已经画出去的那一截也跟着变）；双脉冲第二次点火重新冒烟
--   · 发动机一关（烧完、还没点火的抛射弹）：火舌灭、不再冒烟，已经冒出去的烟照样慢慢散；弹打中了 / 没了也一样（小零件留到烟散完）
--   · 发射器一枚弹几个：飞过 500 格或者 1.2 秒换一个新的（旧的停在原地不挪，粒子到寿命才收——同 VfxLib 的规矩：长寿命的烟不跟着零件跑远）
--   用户 11-28「尾烟还是不像战雷」：战雷的导弹尾烟又浓又白、在天上挂很久（看得清整条弹道），被太阳照着，越老越宽、越淡、越灰——
--   · 挂得久：低烟 5 秒、一般 14 秒、浓烟 22 秒（原来 1.3 / 3.4 / 6.5 秒，烟还没看清就没了）
--   · 粗：出来就一两米、头一两秒胀开，浓烟挂到最后十来米粗（原来不到一米、最多三米——一两公里外看只剩一根发丝）
--   · 烟带两层（同一条中线）：里层浓、窄，外层宽、淡——里浓外淡叠出虚的边（原来一条硬边的平带子）
--   · 烟团大一点、活得跟烟带一样久，撒在烟带四周，一团团慢慢胀开、转、往上飘一点：烟带外面一层翻滚的毛边
--   贴图只用 Roblox 自带的（VfxLib.TX.SMOKE），不上传图片
local MslSmoke = {}

function MslSmoke.new(G, FXF, VL)
  local M = {}
  local V, RGB = Vector3.new, Color3.fromRGB
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local Debris = game:GetService("Debris")
  local SMOKE_TEX = (VL and VL.TX and VL.TX.SMOKE) or "rbxasset://textures/particles/smoke_main.dds"
  M.stat = { trails = 0, emitters = 0, emitted = 0, live = 0, holders = 0 }

  -- 三档（格；1 米 = 2.8 格）：w 烟带刚出来多宽、life 烟带留多久、tr0 刚出来的透明度、grow 老了胀到几倍宽；
  --   gap 每飞几格撒一团、nps 每秒最多几团、pl 烟团寿命、ps 烟团 出生 / 一会儿 / 最后 多大、ptr 烟团起始透明度（贴图本身 alpha 只到 0.33）；
  --   flame 火舌多长（× 弹径系数）
  local CLS = {
    low = { w = 1.8, life = 5, tr0 = 0.52, grow = 4, gap = 14, nps = 30, pl = { 3, 5 }, ps = { 2.4, 8, 16 }, ptr = 0.45, flame = 2.4 },
    med = { w = 3.2, life = 14, tr0 = 0.16, grow = 6, gap = 9, nps = 80, pl = { 8, 12 }, ps = { 4, 15, 34 }, ptr = 0.22, flame = 3.4 },
    heavy = { w = 4.5, life = 22, tr0 = 0.05, grow = 7, gap = 7, nps = 120, pl = { 14, 20 }, ps = { 5, 20, 46 }, ptr = 0.12, flame = 4.4 },
  }
  M.CLS = CLS
  local WARM, FRESH, MID, OLD = RGB(255, 226, 190), RGB(244, 244, 240), RGB(228, 228, 226), RGB(196, 198, 204)   -- 老了偏灰、带一点冷色

  local function holder(name)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = V(0.2, 0.2, 0.2)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = FXF
    M.stat.holders += 1
    return p
  end
  local function attachPair(h, half)
    local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
    a0.Position, a1.Position = V(-half, 0, 0), V(half, 0, 0)
    a0.Parent, a1.Parent = h, h
    return a0, a1
  end
  local function nsq(...)   -- (t, v, t, v …)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = NSK(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  local function csq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do kp[#kp + 1] = CSK(a[i], a[i + 1]) end
    return ColorSequence.new(kp)
  end

  -- 一条烟带：c 档、k 宽度倍数、tk 透明度往上加（续航段淡一点）；返回里层、外层两条
  local function smokeTrail(S, c, k, tk)
    local half = c.w * k / 2
    local a0, a1 = attachPair(S.h, half)
    local tr = Instance.new("Trail")
    tr.Attachment0, tr.Attachment1 = a0, a1
    tr.FaceCamera = true
    tr.Lifetime = c.life
    tr.MinLength = 0.4
    local t0 = math.min(0.95, c.tr0 + (tk or 0))
    tr.Transparency = nsq(0, t0, 0.3, t0 + (1 - t0) * 0.35, 0.75, t0 + (1 - t0) * 0.78, 1, 1)
    tr.WidthScale = nsq(0, 0.45, 0.04, 1, 0.25, 1 + (c.grow - 1) * 0.55, 1, c.grow)   -- 头一两秒胀得最快（真的烟出来就翻开），后面慢慢胀
    tr.Color = csq(0, WARM, 0.05, FRESH, 0.45, MID, 1, OLD)
    tr.LightEmission, tr.LightInfluence = 0, 1   -- 烟受光照（夜里不自己发白）
    tr.Parent = S.h
    -- 外层：同一条中线、宽一倍、淡得多，活得稍短——里浓外淡叠出虚的边（一条硬边的平带子不像烟）
    local b0, b1 = attachPair(S.h, half * 1.9)
    local hl = Instance.new("Trail")
    hl.Name = "MslSmokeHalo"
    hl.Attachment0, hl.Attachment1 = b0, b1
    hl.FaceCamera = true
    hl.Lifetime = c.life * 0.9
    hl.MinLength = 0.4
    local th = math.min(0.97, 0.7 + 0.25 * t0)
    hl.Transparency = nsq(0, 1, 0.06, th, 0.5, th + (1 - th) * 0.45, 1, 1)
    hl.WidthScale = nsq(0, 0.45, 0.06, 1, 0.25, 1 + (c.grow * 1.25 - 1) * 0.55, 1, c.grow * 1.25)
    hl.Color = csq(0, FRESH, 0.5, MID, 1, OLD)
    hl.LightEmission, hl.LightInfluence = 0, 1
    hl.Parent = S.h
    M.stat.trails += 2
    return tr, hl
  end
  -- 火舌：喷口往后一截，最长 len 格，宽 fw
  local function flameTrail(S, len, fw)
    local a0, a1 = attachPair(S.h, fw / 2)
    local tr = Instance.new("Trail")
    tr.Attachment0, tr.Attachment1 = a0, a1
    tr.FaceCamera = true
    tr.Lifetime = 0.12
    tr.MinLength = 0.1
    tr.MaxLength = len
    tr.Transparency = nsq(0, 0, 0.45, 0.18, 1, 1)
    tr.WidthScale = nsq(0, 1, 1, 0.22)
    tr.Color = csq(0, RGB(255, 252, 240), 0.35, RGB(255, 214, 130), 1, RGB(255, 128, 52))
    tr.LightEmission, tr.LightInfluence = 1, 0
    pcall(function() tr.Brightness = 3 end)
    tr.Parent = S.h
    return tr
  end
  -- 烟团发射器（一个只在一段路上撒）：c 档
  local function puffEmitter(c)
    local h = holder("MslSmokeE")
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = SMOKE_TEX
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(c.pl[1], c.pl[2])
    pe.Speed = NumberRange.new(0.6, 2.4)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Drag = 0.8   -- 往外胀一点就停住（活十几秒也不会飘远）
    local acc = V(0, 0.5, 0)   -- 热烟往上浮一点
    if VL and VL.wind and VL.wind().Magnitude < 0.5 then acc += V(1.2, 0, 0.6) end   -- 地图没设风：补一点水平的
    pe.Acceleration = acc
    pe.Size = nsq(0, c.ps[1], 0.25, c.ps[2], 1, c.ps[3])
    pe.Transparency = nsq(0, c.ptr, 0.5, c.ptr + (1 - c.ptr) * 0.42, 1, 1)
    pe.Color = csq(0, RGB(244, 242, 238), 1, RGB(206, 206, 204))
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-8, 8)
    pe.LightEmission, pe.LightInfluence = 0, 1
    pe.EmissionDirection = Enum.NormalId.Top
    pcall(function()
      pe.Shape = Enum.ParticleEmitterShape.Box
      pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    end)
    pcall(function() pe.WindAffectsDrag = true end)
    pe.Parent = h
    M.stat.emitters += 1
    return { h = h, pe = pe, t0 = os.clock(), path = 0, c = c }
  end
  local function retireEmitter(E)
    if not E then return end
    Debris:AddItem(E.h, E.c.pl[2] + 0.5)
  end

  -- 同时在飘的烟团（估个数：每帧按平均寿命衰减）——多了少撒
  local live, LIVE_MAX = 0, 2600
  local cam = workspace.CurrentCamera

  -- s：Fx 的一枚弹（flying 项）；cf 弹的 CFrame（朝飞的方向）；back 弹尾离 cf 多远；on 发动机开着；cls 档；ph 1 一般 / "boost" / "sus"；
  --   d 弹径（格，火舌按它粗细）
  function M.step(s, cf, back, dt, on, cls, ph, d)
    local c = CLS[cls] or CLS.med
    local S = s.sm
    if not S then
      if not on then return end
      S = { h = holder("MslSmokeT"), trails = {}, halos = {}, last = nil }
      s.sm = S
    end
    local p = cf.Position - cf.LookVector * back
    S.h.CFrame = CFrame.new(p)
    live = live * math.exp(-dt / 10)   -- 烟团活十几秒
    M.stat.live = live
    -- 发动机关了：火舌灭、烟带不再长，已经冒出去的慢慢散
    if not on then
      if S.flame then S.flame.Enabled = false end
      for _, tr in pairs(S.trails) do tr.Enabled = false end
      for _, hl in pairs(S.halos) do hl.Enabled = false end
      if S.E then retireEmitter(S.E) S.E = nil end
      S.last, S.key, S.retire = nil, nil, nil
      return
    end
    local key = cls .. "_" .. tostring(ph or 1)
    local tr = S.trails[key]
    if not tr then
      local hl
      tr, hl = smokeTrail(S, c, (ph == "boost") and 1.15 or ((ph == "sus") and 0.7 or 1), (ph == "sus") and 0.18 or 0)
      S.trails[key], S.halos[key] = tr, hl
    end
    -- 换段（助推 → 续航、第二次点火）：旧的那条多开一帧再关（这一帧它也画到现在这一点，新旧两条接上，不断一截）
    if S.retire then
      S.retire.Enabled = false
      for k, t2 in pairs(S.trails) do if t2 == S.retire and S.halos[k] then S.halos[k].Enabled = false end end
      S.retire = nil
    end
    if S.key and S.key ~= key and S.trails[S.key] then S.retire = S.trails[S.key] end
    S.key = key
    for k, t2 in pairs(S.trails) do
      local on2 = (k == key) or (t2 == S.retire)
      t2.Enabled = on2
      if S.halos[k] then S.halos[k].Enabled = on2 end
    end
    local fk = (ph == "boost") and 1.3 or ((ph == "sus") and 0.7 or 1)
    local dk = math.clamp((d or 0.8) / 0.8, 0.6, 2.2)
    if not S.flame then S.flame = flameTrail(S, c.flame * fk * dk, math.max(0.45, (d or 0.8) * 1.25)) end
    S.flame.Enabled = true
    S.flame.MaxLength = c.flame * fk * dk
    -- 烟团：这一帧飞过的那一段
    if S.last then
      local seg = p - S.last
      local L = seg.Magnitude
      if L > 0.05 then
        local E = S.E
        if not E or E.c ~= c or E.path > 500 or os.clock() - E.t0 > 1.2 then   -- 换一个新的发射器（旧的停在原地）
          retireEmitter(E)
          E = puffEmitter(c)
          S.E = E
        end
        E.path += L
        local want = L / (c.gap / ((ph == "boost") and 1.35 or ((ph == "sus") and 0.75 or 1)))
        local k = math.clamp(G.perfK or 1, 0.4, 1.2)
        if cam then
          local dist = (cam.CFrame.Position - p).Magnitude
          if dist > 4000 then k *= 0.35 elseif dist > 1600 then k *= 0.6 end
        end
        if live > LIVE_MAX then k *= LIVE_MAX / live end
        S.carry = (S.carry or 0) + math.min(want, c.nps * dt * 1.5 + 1) * k
        local n = math.floor(S.carry)
        if n > 0 then
          S.carry -= n
          local wb = c.w * 0.8
          E.h.Size = V(wb, wb, math.max(L, 0.2))
          E.h.CFrame = CFrame.lookAt(S.last + seg / 2, p)
          E.pe:Emit(n)
          live += n
          M.stat.emitted += n
        end
      end
    end
    S.last = p
  end

  -- 弹没了（打中、自毁、出了范围）：不再冒烟，烟带、烟团留到散完再收
  function M.stop(s)
    local S = s.sm
    if not S then return end
    s.sm = nil
    if S.flame then S.flame.Enabled = false end
    local life = 0
    for _, tr in pairs(S.trails) do
      tr.Enabled = false
      life = math.max(life, tr.Lifetime)
    end
    for _, hl in pairs(S.halos or {}) do hl.Enabled = false end
    Debris:AddItem(S.h, life + 0.5)
    retireEmitter(S.E)
  end
  return M
end

return MslSmoke
