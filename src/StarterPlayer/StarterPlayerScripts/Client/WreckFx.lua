-- Roblox全面大战场（客户端）——车被打爆（用户 11-25「载具爆炸效果不够猛画风不够战雷」）：照真车殉爆的录像做，写实、不卡通
--   殉爆（服务器 Wt.lua destroy 的 why = "ammo"，View.lua 车变残骸那一帧调 G.wreckFx）：
--     ① 一瞬间白热的闪光照亮四周、离得近的震屏；一声闷响叠在服务器那声爆炸上（低一个八度、拖得长）
--     ② 车里冲出一团翻滚的大火球（白热的芯 → 橙红的火 → 裹着它往上翻的煤黑浓烟），一根火柱从炮塔座圈直冲上去（炮塔被顶飞：View.lua startToss）
--     ③ 十来块真的钢板碎块（会落地、会弹的零件）拖着火和黑烟飞出去，烧几秒灭掉，十几秒后慢慢没了
--     ④ 地上一圈冲击波、扬起一圈土；地面烧焦一大块（软边的黑斑，残骸在就一直在）
--     ⑤ 之后八九秒车里剩下的弹一发一发殉爆：一闪、一蓬火星、一小团火、噼啪响，越来越稀；舱口往外蹿火
--     ⑥ 车身大火、一根浓黑的烟柱升得很高、顺着风歪过去（View.lua 的 fire / black 发射器调粗调黑）
--   烧毁（"fire"）：没有大火球，发动机舱窜火、黑烟柱、地面烧焦；乘员打光（"crew"）和别的：一小团火、一缕黑烟
--   全在本机画；离镜头远、机器跟不上（G.perfK）的少画；同时最多 3 处殉爆在冒碎块
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local WreckFx = {}

function WreckFx.init(G)
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local Map = require(RS:WaitForChild("Map"))
  local cam = workspace.CurrentCamera
  local TX = {
    core = "rbxasset://textures/particles/explosion01_core_main.dds",
    glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
    ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
    fire = "rbxasset://textures/particles/fire_main.dds",
    smoke = "rbxasset://textures/particles/smoke_main.dds",
    spark = "rbxasset://textures/particles/sparkles_main.dds",
  }
  -- 写实的颜色：火是白热 → 金黄 → 橙红，烟是煤黑 → 灰褐（不要纯黑、不要发紫），土是灰褐
  local FIRE_HOT, FIRE_MID, FIRE_DARK = RGB(255, 241, 214), RGB(255, 158, 64), RGB(150, 52, 22)
  local SOOT, SOOT2 = RGB(24, 22, 20), RGB(78, 74, 70)
  local DUST = RGB(132, 118, 98)

  local function seq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do table.insert(kp, NSK(a[i], a[i + 1])) end
    return NumberSequence.new(kp)
  end
  local function cseq(...)
    local a, kp = { ... }, {}
    for i = 1, #a, 2 do table.insert(kp, CSK(a[i], a[i + 1])) end
    return ColorSequence.new(kp)
  end
  local function holder(cf)
    local p = Instance.new("Part")
    p.Size, p.CFrame, p.Transparency = V(0.3, 0.3, 0.3), cf, 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = G.fxFolder or workspace
    return p
  end
  -- 一个发射器：o 的字段同 Fx.lua burst（tex、life、spd、spread、size、tr、col、acc、drag、le、rot、dir、flat、z）；n 一次喷多少，rate 常喷
  local function emitter(h, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.spd[1], o.spd[2])
    pe.SpreadAngle = Vector2.new(o.spread or 180, o.spread2 or o.spread or 180)
    pe.Size = o.size
    pe.Transparency = o.tr
    pe.Color = o.col
    pe.Acceleration = o.acc or V()
    pe.Drag = o.drag or 0
    pe.LightEmission = o.le or 0
    pe.LightInfluence = (o.le or 0) > 0.5 and 0 or 1
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-(o.rot or 30), o.rot or 30)
    pe.ZOffset = o.z or 0
    pe.EmissionDirection = o.dir or Enum.NormalId.Top
    if o.flat then pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
    pe.Parent = h
    if o.rate then pe.Rate = o.rate elseif o.n and o.n > 0 then pe:Emit(o.n) end
    return pe
  end
  local function lod(p)
    local d = (p - cam.CFrame.Position).Magnitude
    local k = (G.perfK or 1)
    if d > 2500 then k = k * 0.4 elseif d > 1200 then k = k * 0.65 end
    return k, d
  end
  local function N(x, k) return math.max(1, math.floor(x * k + 0.5)) end
  local stat = { big = 0, chunks = 0, pops = 0, scorch = 0, jets = 0 }   -- 给测试看的（tools/mock/wreckfx.lua）
  G.wreckStat = stat
  local function groundAt(p) return math.max(Map.height(p.X, p.Z), 0) end

  -- 声音：闷响（服务器那声爆炸之外再叠一层低沉拖长的）、殉爆的噼啪
  local EXP = G.sndIds and G.sndIds.EXP or "rbxasset://sounds/impact_explosion_03.mp3"
  local function thump(p, d)
    if not G.sfx then return end
    local L = { { id = EXP, vol = 1.3, s = { 0.42, 0.48 }, eq = { 10, -4, -12 }, echo = { 0.35, 0.4, -6 } } }
    local RL = G.realLayer and G.realLayer("boomL", 0.78, 1.15)
    if RL then L = { RL, L[1] } end
    G.sfx(L, p, { delay = math.max(0, d - 250) / 960 + 0.04, rmin = 120, rmax = 6000, must = true })
  end
  local function pop(p, d, big)
    if not G.sfx or d > 1800 then return end
    local RL = G.realLayer and G.realLayer("boomS", big and 1.05 or (1.3 + math.random() * 0.3), big and 0.8 or 0.45)
    local L = RL and { RL } or { { id = EXP, vol = big and 0.8 or 0.45, s = big and { 1.0, 1.1 } or { 1.6, 2.1 }, reg = { 0.02, 0.6 } } }
    G.sfx(L, p, { delay = math.max(0, d - 250) / 960, rmin = 40, rmax = 2500 })
  end

  -- ① 闪光：白热的一团 + 点光源照亮四周（白天也看得出来：Fx.flash 按太阳高度加亮）
  local function flashAt(p, R)
    if G.flash then G.flash(p + V(0, R * 0.3, 0), RGB(255, 196, 128), math.min(90, 24 + R * 1.6), 10 + R / 5, 0.55) end
    local h = holder(CF(p))
    emitter(h, { tex = TX.glow, n = 1, life = { 0.14, 0.2 }, spd = { 0, 0 }, size = seq(0, R * 2.2, 1, R * 3.6), tr = seq(0, 0, 1, 1),
      col = cseq(0, RGB(255, 250, 236), 1, RGB(255, 200, 140)), le = 1, z = 4 })
    Debris:AddItem(h, 0.4)
  end

  -- ② 翻滚的大火球 + 裹着它往上翻的煤黑浓烟（蘑菇状）
  local function fireball(p, R, k)
    local h = holder(CF(p))
    -- 白热的芯：一下子胀开
    emitter(h, { tex = TX.core, n = N(10, k), life = { 0.35, 0.6 }, spd = { R * 0.6, R * 1.6 }, drag = 6, acc = V(0, R * 0.8, 0),
      size = seq(0, R * 0.6, 0.3, R * 1.2, 1, R * 1.5), tr = seq(0, 0, 0.6, 0.3, 1, 1), col = cseq(0, FIRE_HOT, 0.5, FIRE_MID, 1, FIRE_DARK), le = 1, rot = 120, z = 3 })
    -- 橙红的火：往外滚、被空气挡住、往上卷
    emitter(h, { tex = TX.fire, n = N(28, k), life = { 0.8, 1.6 }, spd = { R * 0.8, R * 2.4 }, drag = 4, acc = V(0, R * 1.1, 0),
      size = seq(0, R * 0.5, 0.25, R * 1.1, 1, R * 0.7), tr = seq(0, 0.05, 0.5, 0.25, 1, 1), col = cseq(0, RGB(255, 222, 160), 0.35, FIRE_MID, 1, FIRE_DARK), le = 0.9, rot = 70, z = 2 })
    -- 煤黑的浓烟：从火球外面翻上去，越升越大、越淡，顺风歪
    emitter(h, { tex = TX.smoke, n = N(26, k), life = { 4.5, 8 }, spd = { R * 0.5, R * 1.5 }, drag = 1.6, acc = V(2.2, R * 0.38 + 3, 1.0),
      size = seq(0, R * 0.7, 0.2, R * 1.6, 1, R * 3.2), tr = seq(0, 0.08, 0.35, 0.2, 1, 1), col = cseq(0, SOOT, 0.6, RGB(44, 41, 38), 1, SOOT2), rot = 18, z = 1 })
    -- 火星：往四周上方撒，带重力落
    emitter(h, { tex = TX.spark, n = N(80, k), life = { 0.9, 2.2 }, spd = { 30, 85 }, spread = 70, dir = Enum.NormalId.Top, acc = V(0, -70, 0), drag = 0.6,
      size = seq(0, 0.5, 1, 0.15), tr = seq(0, 0, 0.8, 0.2, 1, 1), col = cseq(0, RGB(255, 232, 170), 1, RGB(255, 150, 70)), le = 1, rot = 0 })
    Debris:AddItem(h, 9)
  end

  -- ④ 地上：贴地冲击波圈、扬起一圈土
  local function groundRing(p, R, k)
    local gy = groundAt(p)
    local h = holder(CF(p.X, gy + 0.8, p.Z))
    emitter(h, { tex = TX.ring, n = 1, life = { 0.45, 0.55 }, spd = { 0.05, 0.05 }, spread = 0, flat = true, size = seq(0, R * 0.5, 1, R * 5),
      tr = seq(0, 0.2, 1, 1), col = cseq(0, RGB(240, 226, 200), 1, RGB(240, 226, 200)), z = 0 })
    local dust = emitter(h, { tex = TX.smoke, n = 0, life = { 1.6, 2.8 }, spd = { R * 1.2, R * 2.4 }, spread = 2, spread2 = 2, drag = 2, acc = V(0, 1.2, 0), dir = Enum.NormalId.Front,
      size = seq(0, R * 0.4, 1, R * 1.6), tr = seq(0, 0.3, 1, 1), col = cseq(0, DUST, 1, RGB(170, 160, 142)), rot = 25 })
    local base = h.CFrame
    local n = N(22, k)
    for i = 1, n do   -- 一圈往外推的土（发射器转一圈、一个方向喷一颗）
      h.CFrame = base * CFrame.Angles(0, (i + math.random() * 0.5) * 2 * math.pi / n, 0)
      dust:Emit(1)
    end
    h.CFrame = base
    Debris:AddItem(h, 3.5)
  end

  -- ④ 地面烧焦：软边的黑斑（烟的贴图染黑，平铺在地上）；跟着残骸，残骸没了它也没了
  local function scorch(base, L, W, parent)
    local gy = groundAt(base.Position)
    local D = math.max(L, W) * 1.5
    local p = Instance.new("Part")
    p.Size = V(D, 0.05, D)
    p.CFrame = CF(base.Position.X, gy + 0.06, base.Position.Z) * CFrame.Angles(0, math.random() * 6.28, 0)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    for i = 1, 2 do
      local dc = Instance.new("Decal")
      dc.Face = Enum.NormalId.Top
      dc.Texture = TX.smoke
      dc.Color3 = RGB(0, 0, 0)
      dc.Transparency = (i == 1) and 0.05 or 0.35
      dc.Parent = p
    end
    p.Name = "Scorch"
    p.Parent = parent or G.fxFolder or workspace
    stat.scorch += 1
    return p
  end

  -- ③ 钢板碎块：真的零件，飞出去、落地弹、拖着火和烟，烧几秒灭掉，十几秒后淡掉
  local liveChunks = 0
  local function chunks(p, R, k, n)
    if liveChunks > 40 then return end
    n = N(n, k)
    for i = 1, n do
      local big = i <= 2
      local s = big and V(2.2 + math.random() * 1.4, 0.25, 1.6 + math.random()) or V(0.5 + math.random() * 1.2, 0.18 + math.random() * 0.2, 0.4 + math.random() * 0.9)
      local c = Instance.new((math.random() < 0.35) and "WedgePart" or "Part")
      c.Size = s
      c.CFrame = CF(p + V((math.random() - 0.5) * 3, 1 + math.random() * 2, (math.random() - 0.5) * 3)) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
      c.Material = Enum.Material.CorrodedMetal
      c.Color = RGB(46, 43, 40):Lerp(RGB(70, 62, 52), math.random())
      c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = false, true, false, false, true
      pcall(function() c.CustomPhysicalProperties = PhysicalProperties.new(7.8, 0.6, 0.15) end)   -- 钢：重、不怎么弹（模拟器没有这个类型）
      c.Parent = G.fxFolder or workspace
      local ang = math.random() * 6.28
      local hs = (big and 12 or 18) + math.random() * (big and 14 or 30)
      local lv = V(math.cos(ang) * hs, (big and 28 or 34) + math.random() * (big and 20 or 40), math.sin(ang) * hs)
      local av = V((math.random() - 0.5) * 18, (math.random() - 0.5) * 18, (math.random() - 0.5) * 18)
      pcall(function() c.AssemblyLinearVelocity = lv end)   -- 模拟器里没有的属性跳过（真 Roblox 都有）
      pcall(function() c.AssemblyAngularVelocity = av end)
      -- 拖着的火和黑烟
      local burn = big or math.random() < 0.6
      local f, sm
      if burn then
        f = emitter(c, { tex = TX.fire, rate = big and 26 or 16, life = { 0.25, 0.5 }, spd = { 0.5, 2 }, spread = 40, acc = V(0, 6, 0),
          size = seq(0, big and 2.2 or 1.3, 1, 0.3), tr = seq(0, 0.1, 1, 1), col = cseq(0, RGB(255, 210, 140), 1, FIRE_DARK), le = 0.9 })
        sm = emitter(c, { tex = TX.smoke, rate = big and 14 or 8, life = { 1.4, 2.6 }, spd = { 0.5, 2 }, spread = 30, acc = V(1, 3, 0.5),
          size = seq(0, big and 1.6 or 1, 1, big and 6 or 4), tr = seq(0, 0.25, 1, 1), col = cseq(0, SOOT, 1, SOOT2), rot = 20 })
      end
      liveChunks += 1
      stat.chunks += 1
      task.delay(2.5 + math.random() * 3, function()
        if f then f.Enabled = false end
        if sm then sm.Rate = 2 end
      end)
      task.delay(11 + math.random() * 4, function()
        if c.Parent then TweenService:Create(c, TweenInfo.new(2.5), { Transparency = 1 }):Play() end
        if sm then sm.Enabled = false end
      end)
      task.delay(14.5 + 4, function() liveChunks -= 1 end)
      Debris:AddItem(c, 18.5)
    end
  end

  G.wreckChunks = chunks   -- Fx.lua 的 boom（车 / 飞机 / 舰被打爆那一类）也用真碎块，不用方块贴图

  -- ⑤ 车里剩下的弹一发一发殉爆（越来越稀）；舱口往外蹿火（前几秒）
  local function cookOff(v, base, L, W, H, k, d)
    local n = N(9, math.min(1, k + 0.2))
    local t = 0.35
    for i = 1, n do
      t += 0.25 + math.random() * 0.55 * (1 + i / n)
      task.delay(t, function()
        if not (v.M and v.M.model and v.M.model.Parent) then return end
        local q = base.Position + base.RightVector * ((math.random() - 0.5) * W * 0.6) + base.LookVector * ((math.random() - 0.5) * L * 0.6) + V(0, H * (0.75 + math.random() * 0.35), 0)
        local bigOne = (i % 4 == 0)
        local h = holder(CF(q))
        if G.flash then G.flash(q, RGB(255, 186, 110), bigOne and 34 or 20, bigOne and 7 or 4, 0.18) end
        emitter(h, { tex = TX.glow, n = 1, life = { 0.08, 0.13 }, spd = { 0, 0 }, size = seq(0, bigOne and 9 or 5, 1, bigOne and 13 or 7), tr = seq(0, 0, 1, 1),
          col = cseq(0, RGB(255, 246, 220), 1, RGB(255, 190, 120)), le = 1, z = 3 })
        emitter(h, { tex = TX.spark, n = bigOne and 45 or 22, life = { 0.5, 1.3 }, spd = { 20, bigOne and 70 or 50 }, spread = 60, acc = V(0, -70, 0), drag = 0.5,
          size = seq(0, 0.4, 1, 0.1), tr = seq(0, 0, 1, 0.4), col = cseq(0, RGB(255, 230, 160), 1, RGB(255, 140, 60)), le = 1, rot = 0 })
        emitter(h, { tex = TX.fire, n = bigOne and 12 or 5, life = { 0.4, 0.8 }, spd = { 6, bigOne and 26 or 14 }, spread = 35, drag = 2.5, acc = V(0, 18, 0),
          size = seq(0, bigOne and 4 or 2.5, 0.4, bigOne and 7 or 4, 1, 1.5), tr = seq(0, 0.05, 1, 1), col = cseq(0, RGB(255, 226, 170), 1, FIRE_DARK), le = 0.9, rot = 60 })
        emitter(h, { tex = TX.smoke, n = bigOne and 6 or 3, life = { 2.5, 4.5 }, spd = { 4, 10 }, spread = 30, drag = 1.2, acc = V(1.5, 5, 0.6),
          size = seq(0, 3, 1, bigOne and 14 or 9), tr = seq(0, 0.2, 1, 1), col = cseq(0, SOOT, 1, SOOT2), rot = 15 })
        pop(q, d, bigOne)
        stat.pops += 1
        Debris:AddItem(h, 5)
      end)
    end
  end
  local function hatchJet(base, H, secs, strong)
    local p = base.Position + V(0, H + 0.5, 0)
    local h = holder(CFrame.lookAt(p, p + V(0, 1, 0)))
    local f = emitter(h, { tex = TX.fire, rate = strong and 42 or 24, life = { 0.45, 0.9 }, spd = { strong and 16 or 9, strong and 34 or 18 }, spread = 14, dir = Enum.NormalId.Front,
      drag = 1.5, acc = V(0, 8, 0), size = seq(0, 2.6, 0.4, strong and 6 or 4, 1, 1.5), tr = seq(0, 0.05, 0.7, 0.35, 1, 1),
      col = cseq(0, RGB(255, 236, 190), 0.35, FIRE_MID, 1, FIRE_DARK), le = 0.95, rot = 80, z = 2 })
    stat.jets += 1
    task.delay(secs, function() f.Rate = f.Rate * 0.3 end)
    task.delay(secs * 2.2, function() f.Enabled = false end)
    Debris:AddItem(h, secs * 2.2 + 1.2)
  end

  -- ⑥ 车身的大火、烟柱：View.lua 的 fire / black 发射器（平时关着）调粗、调黑、升高、顺风
  local function heavyBurn(M, strong)
    local f, b = M.fire, M.black
    if f then
      f.Size = seq(0, strong and 6 or 4.5, 0.4, strong and 9 or 7, 1, 2)
      f.Lifetime = NumberRange.new(0.7, 1.4)
      f.Speed = NumberRange.new(5, 11)
      f.SpreadAngle = Vector2.new(25, 25)
      f.Acceleration = V(0, 7, 0)
      f.Transparency = seq(0, 0.05, 0.6, 0.35, 1, 1)
      f.Color = cseq(0, RGB(255, 226, 170), 0.35, FIRE_MID, 1, FIRE_DARK)
      f.LightEmission = 0.9
      f.LightInfluence = 0
      f.RotSpeed = NumberRange.new(-60, 60)
      f.Rotation = NumberRange.new(0, 360)
    end
    if b then
      b.Lifetime = NumberRange.new(7, 12)
      b.Speed = NumberRange.new(8, 14)
      b.SpreadAngle = Vector2.new(12, 12)
      b.Drag = 0.35
      b.Acceleration = V(2.6, 2.4, 1.2)   -- 顺风歪过去、越升越高
      b.Size = seq(0, strong and 6 or 4.5, 0.25, strong and 16 or 12, 1, strong and 44 or 32)
      b.Transparency = seq(0, 0.05, 0.3, 0.12, 0.75, 0.55, 1, 1)
      b.Color = cseq(0, SOOT, 0.55, RGB(40, 38, 35), 1, SOOT2)
      b.RotSpeed = NumberRange.new(-12, 12)
      b.Rotation = NumberRange.new(0, 360)
      b.LightInfluence = 1
    end
  end

  local liveBig = 0
  -- v：View.lua 的车（v.M 模型、v.def 型号）；why：服务器的 WtWhy（"ammo" 殉爆、"fire" 烧毁、"crew" 乘员打光、nil 老式血量打光）；base：车底的 CFrame
  function G.wreckFx(v, why, base)
    local d0 = v.def or {}
    local M = v.M or {}
    if not base then return end
    local L, W, H = d0.L or 20, d0.W or 10, d0.hullH or (d0.H or 8) * 0.6
    local p = base.Position + V(0, H * 0.7, 0)
    local k, d = lod(p)
    if d > 6000 then return end
    local ammo = why == "ammo" or (why == nil and d0.cat == "tank")
    if ammo then
      local R = math.clamp(math.max(L, W) * 0.55, 9, 22)   -- 火球半径（格）：主战坦克 13～16
      stat.big += 1
      flashAt(p, R)
      fireball(p, R, k)
      groundRing(p, R, k)
      thump(p, d)
      if d < 1500 and liveBig < 3 then
        liveBig += 1
        task.delay(16, function() liveBig -= 1 end)
        chunks(p, R, k, 12)
      end
      hatchJet(base, H, 3.5, true)
      cookOff(v, base, L, W, H, k, d)
      if G.shake then
        local shR = 260
        if d < shR then G.shake(0.9 * (1 - d / shR)) end
      end
      heavyBurn(M, true)
    elseif why == "fire" then
      local q = base.Position - base.LookVector * L * 0.3 + V(0, H, 0)   -- 发动机舱在后面
      local h = holder(CF(q))
      emitter(h, { tex = TX.fire, n = N(18, k), life = { 0.6, 1.2 }, spd = { 6, 18 }, spread = 30, drag = 2, acc = V(0, 14, 0),
        size = seq(0, 3, 0.4, 7, 1, 2), tr = seq(0, 0.05, 1, 1), col = cseq(0, RGB(255, 226, 170), 0.4, FIRE_MID, 1, FIRE_DARK), le = 0.9, rot = 60 })
      emitter(h, { tex = TX.smoke, n = N(10, k), life = { 4, 7 }, spd = { 6, 14 }, spread = 25, drag = 1.2, acc = V(2, 4, 1),
        size = seq(0, 5, 1, 22), tr = seq(0, 0.1, 1, 1), col = cseq(0, SOOT, 1, SOOT2), rot = 15 })
      Debris:AddItem(h, 8)
      if G.flash then G.flash(q, RGB(255, 170, 90), 30, 5, 0.4) end
      hatchJet(base, H, 2.5, false)
      heavyBurn(M, true)
    else   -- 乘员打光：车停下、一小团火、一缕黑烟
      local h = holder(CF(p))
      emitter(h, { tex = TX.smoke, n = N(6, k), life = { 3, 5 }, spd = { 3, 8 }, spread = 30, drag = 1.2, acc = V(1.5, 3, 0.7),
        size = seq(0, 3, 1, 12), tr = seq(0, 0.2, 1, 1), col = cseq(0, RGB(54, 51, 48), 1, SOOT2), rot = 15 })
      Debris:AddItem(h, 6)
      heavyBurn(M, false)
    end
    -- 地面烧焦（殉爆、烧毁的）：跟着残骸的模型，残骸没了一起没
    if (ammo or why == "fire") and M.model then
      local ok = pcall(scorch, base, L, W, M.model)
      if not ok then scorch(base, L, W) end
    end
  end
end

return WreckFx
