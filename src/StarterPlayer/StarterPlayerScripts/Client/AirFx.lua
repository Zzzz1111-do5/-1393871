-- Roblox全面大战场（客户端）——飞机机动的云雾和音爆（用户：飞机机动的云雾效果和音爆）
--   翼尖涡流：过载 3.5 g 以上两个翼尖各拖一条细白线（Trail），拉得越狠越浓、越长
--   机翼水汽：过载 6 g 以上机翼上表面冒一层贴着翼面的白雾（粒子锁在机翼上，一出来就散），越狠越厚
--   蒸汽锥：速度到音障附近（这个游戏的速度比例里，带加力的战斗机军推速度的 1.18 倍算音速）机身中段一圈白雾
--   音爆：从音障下面冲过去的那一下——开飞机的人听到闷闷的一声、镜头震一下；外面的人按距离晚到（声速 340 米 / 秒），两声连着的「嘭——嘭」
--   尾焰喷到地上（用户 11-28「起飞时马赫环喷到地上要能有对应效果」）：起飞滑跑 / 贴地开大油门，喷口后面那一段离地近——
--     地上顺着尾流往后、往两边吹起一片尘土（看地面：跑道水泥灰白、沙地黄、草地土黄、雪地白雾、水面水花），开加力时地面被尾焰映成一片橙
--     （一盏点光，夜里更亮）；马赫环浓的老飞机（AirModels 的 strong）吹得更凶、映得更亮，先进的（blue）淡一点
--   自己开的用本地算的过载和速度（Fly.lua 的 st.gLoad、st.spd），别人的按位置变化估（View 的 v.vel，平滑过）；只管 2500 格以内的
local RS = game:GetService("ReplicatedStorage")

local AirFx = {}

function AirFx.init(G)
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  G.airModels = AM   -- 测试用（尾焰的样子：AM.plumeInfo）
  AM.lowQ = function() return (G.perfK or 1) < 0.7 end   -- 画质低：尾焰不画马赫环、喷口柔光少一半、不放热浪（AirModels.lua）
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local GR = AD.GRAV or 27.5
  local SOUND = 340 * (AD.M or 2.8)   -- 声速（格 / 秒）
  local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
  local NEAR = 2500
  local state = setmetatable({}, { __mode = "k" })   -- [视图] = 这架飞机的拖线、水汽、蒸汽锥和估的过载

  -- 这个游戏的「音障」：飞机的速度按真实的一半左右算，带加力的战斗机推满加力才过得去
  local function mach1(d) return (d.ab and d.vMil) and d.vMil * 1.18 or nil end
  G.airMach1 = mach1

  local function mount(M, cf0, size)
    local p = Instance.new("Part")
    p.Name = "FxMount"
    p.Size = size or V(0.2, 0.2, 0.2)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    AM.attach(M, p, cf0)
    return p
  end
  local function mist(parent, size, life, rate)
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "Vapor"
    pe.Texture = SMOKE
    pe.Color = ColorSequence.new(RGB(238, 242, 246))
    pe.LightEmission, pe.LightInfluence = 0.25, 0.8
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size[1]), NumberSequenceKeypoint.new(1, size[2]) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
    pe.Lifetime = NumberRange.new(life[1], life[2])
    pe.Speed = NumberRange.new(0.5, 2)
    pe.EmissionDirection = Enum.NormalId.Top
    pe.LockedToPart = true   -- 贴着机翼（不锁就被几百格每秒的飞机甩成一长条）
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-40, 40)
    pe.Rate = 0
    pe.Enabled = false
    pe.Parent = parent
    return pe, rate
  end

  -- 第一次用到时挂上：翼尖两条拖线、两边机翼上表面的水汽、机身中段的蒸汽锥
  local function build(v)
    local M, d = v.M, v.def
    local S = { M = M }
    local tR, tL = AM.tips(M)
    S.trails = {}
    if tR and tL then
      for _, tip in ipairs({ tR, tL }) do
        local p = mount(M, CF(tip))
        local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
        a0.Position, a1.Position = V(0, 0.14, 0), V(0, -0.14, 0)
        a0.Parent, a1.Parent = p, p
        local tr = Instance.new("Trail")
        tr.Name = "Vortex"
        tr.Attachment0, tr.Attachment1 = a0, a1
        tr.Lifetime = 0.9
        tr.MinLength = 0.2
        tr.FaceCamera = true
        tr.LightEmission, tr.LightInfluence = 0.35, 0.7
        tr.Color = ColorSequence.new(RGB(240, 244, 248))
        tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
        tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
        tr.Enabled = false
        tr.Parent = p
        table.insert(S.trails, tr)
      end
      -- 机翼上表面：翼根到翼尖八成、翼尖往前一截（弦长按机身长估）
      S.vapor = {}
      local chord = d.L * 0.18
      for _, tip in ipairs({ tR, tL }) do
        local half = math.abs(tip.X) * 0.4
        local c = V(tip.X * 0.5, tip.Y + 0.6, tip.Z - chord * 0.6)
        local p = mount(M, CF(c), V(half * 2, 0.4, chord))
        table.insert(S.vapor, (mist(p, { 1.6, 3.2 }, { 0.12, 0.25 })))
      end
    end
    local p = mount(M, CF(0, 0, -d.L * 0.05), V(math.max(d.W * 0.12, 3), d.H * 0.55, 0.8))
    S.cone = mist(p, { 2, 6 }, { 0.08, 0.16 })
    S.n, S.prevV = 1, nil
    return S
  end

  local function setOn(list, on)
    for _, x in ipairs(list or {}) do if x.Enabled ~= on then x.Enabled = on end end
  end

  ---------------------------------------------------------------- 尾焰喷到地上（见文件头）
  local Map = require(RS:WaitForChild("Map"))
  local MAT = Enum.Material
  local BLAST_NEAR, BLAST_H = 1500, 16   -- 离镜头多远以内画；喷口后面那段离地多高以内算喷到地上（格，约 5.7 米）
  local DUST = {
    [MAT.Sand] = RGB(206, 182, 138), [MAT.Sandstone] = RGB(200, 172, 128), [MAT.Salt] = RGB(226, 220, 206),
    [MAT.Snow] = RGB(238, 242, 246), [MAT.Glacier] = RGB(230, 238, 244), [MAT.Ice] = RGB(230, 238, 244),
    [MAT.Grass] = RGB(156, 148, 114), [MAT.LeafyGrass] = RGB(156, 148, 114), [MAT.Ground] = RGB(164, 146, 112), [MAT.Mud] = RGB(140, 122, 96),
    [MAT.Water] = RGB(226, 236, 240),
  }
  local DUST_DEF = RGB(188, 186, 180)   -- 跑道、水泥、柏油、石头：灰白
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  local function groundCol(v, q, water)
    if water then return DUST[MAT.Water] end
    rp.FilterDescendantsInstances = { v.model }
    local ok, res = pcall(function() return workspace:Raycast(q + V(0, 25, 0), V(0, -80, 0), rp) end)
    local m = ok and res and res.Material
    return (m and DUST[m]) or DUST_DEF
  end
  local function blastMake(v)
    local part = Instance.new("Part")
    part.Name = "JetBlast"
    part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
    part.Transparency, part.Size = 1, V(1, 1, 1)
    part.Parent = v.model
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "BlastDust"
    pe.Texture = SMOKE
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(0.9, 2.1)
    pe.Speed = NumberRange.new(18, 46)
    pe.SpreadAngle = Vector2.new(80, 80)   -- 从地面张开到快水平：往两边吹
    pe.EmissionDirection = Enum.NormalId.Top
    pe.Drag = 1.8
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-50, 50)
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.4, 9), NumberSequenceKeypoint.new(1, 17) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.72), NumberSequenceKeypoint.new(1, 1) })
    pe.LightEmission, pe.LightInfluence = 0, 1
    pcall(function()
      pe.Shape = Enum.ParticleEmitterShape.Box
      pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    end)
    pe.Parent = part
    local lt = Instance.new("PointLight")
    lt.Name = "BlastGlow"
    lt.Color = RGB(255, 146, 72)
    lt.Range = 34
    lt.Shadows = false
    lt.Brightness = 0
    lt.Enabled = false
    lt.Parent = part
    return { part = part, pe = pe, light = lt }
  end
  -- 一架飞机：喷口往后 2、4、6 个喷口直径的三个点里离地最近的那个，油门过七成才有
  local function blastStep(v, S, cp)
    local M, d, cf = v.M, v.def, v.cf
    local thr = (v.c and v.c.thr) or 0
    local k, ab, gp, dir, D = 0, 0, nil, nil, 2
    if cf and thr > 70 and (cf.Position - cp).Magnitude < BLAST_NEAR then
      local noz = S.noz
      if not noz then
        noz = AM.nozzles(M)
        S.noz = noz
      end
      local c0, r = V(), 0.6
      for _, n in ipairs(noz) do
        c0 += n.p
        r = math.max(r, n.r)
      end
      c0 /= math.max(#noz, 1)
      D = r * 2
      local p0 = cf * c0
      dir = cf.ZVector   -- 机头朝 −Z：往后
      local best = math.huge
      for _, u in ipairs({ 2, 4, 6 }) do
        local q = p0 + dir * (u * D)
        local gy = math.max(Map.height(q.X, q.Z), 0)
        if q.Y - gy < best then best, gp = q.Y - gy, V(q.X, gy, q.Z) end
      end
      ab = (thr > 100) and math.min(1, (thr - 100) / 25) or 0
      k = math.clamp((thr - 70) / 30, 0, 1) * math.clamp(1 - best / BLAST_H, 0, 1)
    end
    local B = S.blast
    if k < 0.03 then
      if B and B.on then
        B.on = false
        B.pe.Rate = 0
        B.light.Enabled = false
      end
      S.blastK = 0
      return
    end
    if not B then
      B = blastMake(v)
      S.blast = B
    end
    local sty = AM.PLUME_STYLE and AM.plumeStyle and AM.PLUME_STYLE[AM.plumeStyle(d)]
    local sf = (sty and sty.blast) or 1
    B.on = true
    local flat = V(dir.X, 0, dir.Z)
    flat = (flat.Magnitude > 0.05) and flat.Unit or V(0, 0, 1)
    B.part.CFrame = CFrame.lookAt(gp + V(0, 0.8, 0) + flat * D, gp + V(0, 0.8, 0) + flat * (D + 1))
    B.part.Size = V(D * 2.2, 0.4, D * 6)   -- 粒子在喷口后面那一长条地上出生
    local water = Map.height(gp.X, gp.Z) < 0.4
    S.blastT = (S.blastT or 0) + 1
    if S.blastT % 10 == 1 or B.water ~= water then   -- 地面的颜色半秒看一次
      B.water = water
      local col = groundCol(v, gp, water)
      if B.col ~= col then
        B.col = col
        B.pe.Color = ColorSequence.new(col)
      end
    end
    B.pe.Acceleration = flat * (30 + 40 * ab) + V(0, 2.5, 0)   -- 尾流把尘土往后推
    B.pe.Rate = math.floor((12 + 70 * k + 50 * ab * k) * sf + 0.5)
    local glow = ab > 0.05 and not water
    if B.light.Enabled ~= glow then B.light.Enabled = glow end
    if glow then
      local night = 1 - (G.dayK and G.dayK() or 1)
      B.light.Brightness = (1.2 + 2.2 * night) * ab * k * sf
    end
    S.blastK = k
  end
  G.airBlast = function(v) local S = state[v] return S and S.blast, S and S.blastK end   -- 测试用

  local acc = 0
  function G.stepAirFx(dt)
    acc += dt
    if acc < 0.05 then return end
    local step = acc
    acc = 0
    local cam = workspace.CurrentCamera
    local cp = cam.CFrame.Position
    local st = G.fly
    for em, v in pairs(G.views or {}) do
      local d = v.def
      if v.kind == "air" and v.M and d and d.kind == "jet" and em.Parent and not em:GetAttribute("Wreck") then
        local pos = v.cf and v.cf.Position or v.root.CFrame.Position
        local near = (pos - cp).Magnitude < NEAR
        local S = state[v]
        if near and (not S or S.M ~= v.M) then
          S = build(v)
          state[v] = S
        end
        if S then
          -- 过载、速度：自己开的用本地的；别人的按速度的变化估（服务器一秒十几次，平滑一下）
          local own = st and st.em == em and st
          local n, spd
          if own then
            n, spd = own.gLoad or 1, own.spd or 0
          else
            local vel = v.vel or V()
            spd = vel.Magnitude
            if S.prevV then
              local a = (vel - S.prevV) / step + V(0, GR, 0)
              S.n = S.n + (a.Magnitude / GR - S.n) * math.min(1, step * 3)
            end
            S.prevV = vel
            n = S.n
          end
          blastStep(v, S, cp)
          local fly = spd > (d.stall or 60) * 1.2 and near
          -- 翼尖涡流（用户 11-21：飞机太灵活，玩家开的过载上限收到七成——拖线 3 g、水汽 4.5 g 起，照样拉得出来）
          setOn(S.trails, fly and n > 3)
          -- 机翼水汽：4.5 g 往上越来越厚
          local rate = (fly and n > 4.5) and math.min(180, (n - 4.5) * 60 + 30) or 0
          for _, pe in ipairs(S.vapor or {}) do
            if (rate > 0) ~= pe.Enabled then pe.Enabled = rate > 0 end
            if rate > 0 and math.abs(pe.Rate - rate) > 10 then pe.Rate = rate end
          end
          -- 蒸汽锥、音爆
          local m1 = mach1(d)
          if m1 then
            local m = spd / m1
            local band = near and m > 0.95 and m < 1.06
            if S.cone.Enabled ~= band then S.cone.Enabled = band end
            if band and S.cone.Rate ~= 160 then S.cone.Rate = 160 end
            if m >= 1 and not S.sup then
              S.sup = true
              if near then
                pcall(function() S.cone:Emit(40) end)   -- 冲过去的那一下：一大团白雾
                if own then
                  if G.sfx then G.sfx("sonic", nil, { vol = 0.5, hiCut = -12 }) end   -- 座舱里：闷闷的一声
                  if G.shake then G.shake(0.25) end
                elseif G.sfx then
                  G.sfx("sonic", pos, { delay = (pos - cp).Magnitude / SOUND, rmin = 300, rmax = 6000 })   -- 外面：按距离晚到
                end
              end
            elseif m < 0.97 then
              S.sup = false
            end
          end
        end
      end
    end
  end
end

return AirFx
