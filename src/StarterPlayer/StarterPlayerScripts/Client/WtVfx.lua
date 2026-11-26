-- 全面大战场（客户端）——战雷式车辆受伤的样子（用户 11-26「很多载具自带爆反……不同部位被击中也要有不同效果，如弹药舱燃烧、
--   炮管损毁、殉爆、观瞄受损之类的，并且对应效果」）。服务器 Wt.lua 把模块状态写在车上（WtM 模块、WtF 起火、WtAF 弹药架起火、
--   WtBlow 泄压板泄了几次），这里照着画——谁的车都画（离镜头 900 格以内、没成残骸）：
--   · 发动机受损：发动机盖上冒一缕淡灰烟；打坏了：浓黑烟（原来车着火、发动机坏了外面什么都看不出来，只有车身慢慢熏黑）
--   · 起火（WtF）：发动机舱一团跳动的火苗 + 滚滚黑烟 + 一闪一闪的火光
--   · 弹药架起火（WtAF）：车长、炮长舱口往上喷几米高的火柱，噼啪乱飞的火星，火光很亮（烧完没灭有四成殉爆）
--   · 泄压板（WtBlow 变了，M1 炮塔尾舱）：尾舱顶上一道冲天火柱，烧六七秒慢慢小下去，后面一股黑烟
--   · 炮管打坏：炮管耷拉下来（View.lua 按 G.wtModState）；履带打断：那边的履带板停住、上面一段掉了（Tracks.lua）
--   · 自己的车观瞄（optics）受损：开镜时镜里几道裂纹、发糊；打坏：裂成一片、更糊、只剩最低倍率、没有热成像（Drive.lua 问 G.opticsDead）
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local WtVfx = {}

function WtVfx.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
  local cam = workspace.CurrentCamera
  local me = Players.LocalPlayer
  local FIRE = "rbxasset://textures/particles/fire_main.dds"
  local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
  local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
  local NEAR = 900

  -- 模块状态（2 好、1 受损、0 毁了），给别的客户端模块用
  function G.wtModState(em, d, k) return W.modState(em, d, k) end

  local function mount(parent)
    local p = Instance.new("Part")
    p.Name = "WtVfx"
    p.Size = V(0.3, 0.3, 0.3)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = parent
    return p
  end
  local function emitter(parent, o)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = o.tex
    pe.Color = o.col
    pe.LightEmission, pe.LightInfluence = o.emit or 0, o.emit and 0 or 0.9
    pe.Size = o.size
    pe.Transparency = o.tr or NS({ NK(0, 0.2), NK(1, 1) })
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.speed[1], o.speed[2])
    pe.SpreadAngle = Vector2.new(o.spread or 12, o.spread or 12)
    pe.Acceleration = o.acc or V(0, 3, 0)
    pe.Drag = o.drag or 0.6
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-80, 80)
    pe.EmissionDirection = Enum.NormalId.Top
    pe.Rate = 0
    pe.Enabled = true
    pe.Parent = parent
    return pe
  end
  local function light(parent, col, range)
    local l = Instance.new("PointLight")
    l.Color, l.Range, l.Brightness, l.Shadows = col, range, 0, false
    l.Parent = parent
    return l
  end

  -- 一辆车的几处位置（车底坐标 / 炮塔坐标，同 WtDamage）：发动机盖、舱口、弹药架顶
  local function spotsOf(d)
    local lay = W.layout(d)
    local eng, ammo
    for _, it in ipairs(lay.list) do
      if it.k == "engine" then eng = it end
      if it.k == "ammo" then ammo = it end
    end
    local hH = lay.hH
    local s = {}
    if eng then s.eng = V((eng.lo.X + eng.hi.X) / 2, hH + 0.2, (eng.lo.Z + eng.hi.Z) / 2) else s.eng = V(0, hH + 0.2, d.L * 0.3) end
    local T = d.turret
    if T then
      local top = (T.size and T.size.Y or 2.2) + 0.1
      local cu = d.cupola or V(1.3, top, 0.4)
      s.hatch = { V(cu.X, top, cu.Z), V(-cu.X * 0.9, top, cu.Z - 0.4) }   -- 车长、炮长（另一边）舱口
    else
      s.hatch = { V(0, hH + 0.3, -d.L * 0.1) }
    end
    if ammo and ammo.tur then s.bustle = V((ammo.lo.X + ammo.hi.X) / 2, ammo.hi.Y + 0.15, (ammo.lo.Z + ammo.hi.Z) / 2) end
    return s
  end

  local fx = setmetatable({}, { __mode = "k" })   -- [视图] = 这辆车的特效
  local function build(v)
    local d = v.def
    local F = { spots = spotsOf(d) }
    local parent = v.model or workspace
    -- 发动机盖：烟（受损淡灰、毁了浓黑）、火（起火）
    F.engP = mount(parent)
    F.engSmoke = emitter(F.engP, { tex = SMOKE, col = ColorSequence.new(RGB(150, 148, 144)), size = NS({ NK(0, 2), NK(1, 9) }), life = { 2.5, 4 }, speed = { 3, 6 }, spread = 14 })
    F.fire = emitter(F.engP, { tex = FIRE, col = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 220, 150)), ColorSequenceKeypoint.new(0.5, RGB(255, 120, 40)), ColorSequenceKeypoint.new(1, RGB(160, 40, 20)) }),
      size = NS({ NK(0, 2.6), NK(0.6, 3.4), NK(1, 0.8) }), life = { 0.45, 0.8 }, speed = { 4, 8 }, spread = 18, emit = 1, acc = V(0, 6, 0),
      tr = NS({ NK(0, 0.15), NK(0.7, 0.45), NK(1, 1) }) })
    F.fireSmoke = emitter(F.engP, { tex = SMOKE, col = ColorSequence.new(RGB(34, 32, 30)), size = NS({ NK(0, 3.5), NK(1, 18) }), life = { 3.5, 5.5 }, speed = { 6, 10 }, spread = 16, acc = V(0, 4, 0) })
    F.fireLight = light(F.engP, RGB(255, 140, 60), 22)
    -- 舱口：弹药架起火的火柱、火星
    F.hatch = {}
    for _ = 1, #F.spots.hatch do
      local p = mount(parent)
      table.insert(F.hatch, { p = p,
        jet = emitter(p, { tex = FIRE, col = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 246, 210)), ColorSequenceKeypoint.new(0.35, RGB(255, 170, 70)), ColorSequenceKeypoint.new(1, RGB(200, 60, 24)) }),
          size = NS({ NK(0, 1.6), NK(0.3, 3.2), NK(1, 1.0) }), life = { 0.35, 0.6 }, speed = { 22, 34 }, spread = 7, emit = 1, acc = V(0, 4, 0), drag = 1.2,
          tr = NS({ NK(0, 0.05), NK(0.6, 0.35), NK(1, 1) }) }),
        spark = emitter(p, { tex = SPARK, col = ColorSequence.new(RGB(255, 200, 120)), size = NS({ NK(0, 0.45), NK(1, 0.1) }), life = { 0.4, 0.9 }, speed = { 25, 45 }, spread = 32, emit = 1,
          acc = V(0, -20, 0), drag = 0.4, tr = NS({ NK(0, 0), NK(1, 1) }) }) })
    end
    F.afLight = light(F.engP, RGB(255, 190, 110), 34)
    -- 泄压板：尾舱顶上的火柱
    if F.spots.bustle then
      F.bP = mount(parent)
      F.bJet = emitter(F.bP, { tex = FIRE, col = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 250, 225)), ColorSequenceKeypoint.new(0.3, RGB(255, 180, 80)), ColorSequenceKeypoint.new(1, RGB(210, 70, 28)) }),
        size = NS({ NK(0, 2.2), NK(0.4, 4.2), NK(1, 1.4) }), life = { 0.45, 0.75 }, speed = { 32, 46 }, spread = 5, emit = 1, acc = V(0, 6, 0), drag = 1.0,
        tr = NS({ NK(0, 0.05), NK(0.6, 0.3), NK(1, 1) }) })
      F.bSmoke = emitter(F.bP, { tex = SMOKE, col = ColorSequence.new(RGB(40, 38, 36)), size = NS({ NK(0, 4), NK(1, 20) }), life = { 3, 5 }, speed = { 14, 20 }, spread = 8, acc = V(0, 5, 0) })
      F.bLight = light(F.bP, RGB(255, 200, 120), 40)
    end
    return F
  end
  local function off(F)
    F.engSmoke.Rate, F.fire.Rate, F.fireSmoke.Rate = 0, 0, 0
    F.fireLight.Brightness, F.afLight.Brightness = 0, 0
    for _, h in ipairs(F.hatch) do h.jet.Rate, h.spark.Rate = 0, 0 end
    if F.bJet then F.bJet.Rate, F.bSmoke.Rate, F.bLight.Brightness = 0, 0, 0 end
  end

  -- 泄压板泄了几次（WtBlow）：第一次看到这辆车时记下（后进来的人不重放以前的），以后一变就喷
  local blowSeen = setmetatable({}, { __mode = "k" })   -- [视图] = { n = 次数, t = 这次喷的时刻 }
  local acc = 0
  RunService.RenderStepped:Connect(function(dt)
    acc += dt
    local t = os.clock()
    local cp = cam.CFrame.Position
    for em, v in pairs(G.views or {}) do
      if v.kind == "veh" and v.def and v.hullF and em.Parent then
        local d = v.def
        local near = not v.wrecked and (v.hullF.Position - cp).Magnitude < NEAR
        local F = fx[v]
        local engS = W.modState(em, d, "engine")
        local fire = em:GetAttribute("WtF") == true
        local af = em:GetAttribute("WtAF") == true
        local blowN = em:GetAttribute("WtBlow") or 0
        local bs = blowSeen[v]
        if not bs then
          bs = { n = blowN, t = nil }
          blowSeen[v] = bs
        elseif blowN ~= bs.n then
          bs.n, bs.t = blowN, t
        end
        local busy = engS < 2 or fire or af or (bs.t ~= nil and t - bs.t < 9)
        if near and busy and (not F or F.M ~= v.M) then
          local ok, r = pcall(build, v)
          if ok then
            F = r
            F.M = v.M
            fx[v] = F
          end
        end
        if F then
          if not near then off(F)
          else
            -- 位置：发动机盖跟车身、舱口跟炮塔（WtDamage 的炮塔系：炮塔转轴、转角同 View）
            local tf = d.turret and (v.hullF * CF(d.turret.pivot) * CFrame.Angles(0, -math.rad(v.ty or 0), 0)) or v.hullF
            F.engP.CFrame = v.hullF * CF(F.spots.eng)
            for i, h in ipairs(F.hatch) do h.p.CFrame = (d.turret and tf or v.hullF) * CF(F.spots.hatch[i]) end
            if F.bP then F.bP.CFrame = tf * CF(F.spots.bustle) end
            -- 发动机烟
            if engS == 0 then F.engSmoke.Rate, F.engSmoke.Color = 16, ColorSequence.new(RGB(48, 46, 44))
            elseif engS == 1 then F.engSmoke.Rate, F.engSmoke.Color = 6, ColorSequence.new(RGB(150, 148, 144))
            else F.engSmoke.Rate = 0 end
            -- 起火：火苗一跳一跳、火光一闪一闪
            local k = 0.75 + 0.3 * math.sin(t * 13 + v.t) + 0.15 * math.sin(t * 31)
            F.fire.Rate = (fire and not af) and 34 * k or (af and 14 or 0)
            F.fireSmoke.Rate = fire and 10 or 0
            F.fireLight.Brightness = fire and (2.2 * k) or 0
            -- 弹药架起火：舱口火柱
            for _, h in ipairs(F.hatch) do
              h.jet.Rate = af and (95 * (0.8 + 0.4 * math.sin(t * 19 + h.p.Position.X))) or 0
              h.spark.Rate = af and 45 or 0
            end
            F.afLight.Brightness = af and (5 * k) or 0
            -- 泄压板：WtBlow 一变就喷六七秒
            if F.bJet then
              local age = bs.t and (t - bs.t) or 99
              local q = (age < 6.5) and math.clamp(1 - (age - 3) / 3.5, 0.15, 1) or 0
              F.bJet.Rate = 140 * q
              F.bSmoke.Rate = (age < 9) and 12 or 0
              F.bLight.Brightness = 6 * q * k
            end
          end
        end
      end
    end
  end)

  ---------------------------------------------------------------- 自己的车：观瞄受损（开镜时）
  local gui = Instance.new("ScreenGui")
  gui.Name = "SightDamage"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local root = Instance.new("Frame")
  root.Size, root.BackgroundTransparency = UDim2.fromScale(1, 1), 1
  root.Parent = gui
  local blur = nil
  local function crackSet(seed, n, heavy)
    local R = Random.new(seed)
    local f = Instance.new("Frame")
    f.Size, f.BackgroundTransparency = UDim2.fromScale(1, 1), 1
    f.Parent = root
    for _ = 1, n do   -- 每个裂点：十来道放射状裂纹 + 两圈碎的环
      local cx, cy = 0.3 + R:NextNumber() * 0.4, 0.28 + R:NextNumber() * 0.44
      for i = 1, heavy and 16 or 11 do
        local a = (i + R:NextNumber() * 0.6) / (heavy and 16 or 11) * 360
        local len = (heavy and 120 or 70) + R:NextNumber() * (heavy and 320 or 200)
        local l = Instance.new("Frame")
        l.AnchorPoint = Vector2.new(0, 0.5)
        l.Position = UDim2.new(cx, 0, cy, 0)
        l.Size = UDim2.fromOffset(len, (R:NextNumber() < 0.3) and 2 or 1)
        l.Rotation = a
        l.BorderSizePixel = 0
        l.BackgroundColor3 = (R:NextNumber() < 0.55) and RGB(235, 240, 245) or RGB(10, 10, 12)
        l.BackgroundTransparency = 0.35 + R:NextNumber() * 0.3
        l.Parent = f
      end
      for ring = 1, 2 do
        local rr = (heavy and 40 or 26) * ring + R:NextNumber() * 18
        for s = 1, 9 do
          local a = (s + R:NextNumber() * 0.4) / 9 * math.pi * 2
          local l = Instance.new("Frame")
          l.AnchorPoint = Vector2.new(0.5, 0.5)
          l.Position = UDim2.new(cx, math.cos(a) * rr, cy, math.sin(a) * rr)
          l.Size = UDim2.fromOffset(rr * 0.55, 1)
          l.Rotation = math.deg(a) + 90 + (R:NextNumber() - 0.5) * 30
          l.BorderSizePixel = 0
          l.BackgroundColor3 = RGB(225, 230, 235)
          l.BackgroundTransparency = 0.45
          l.Parent = f
        end
      end
      local dot = Instance.new("Frame")   -- 弹着点：一团白的碎渣
      dot.AnchorPoint = Vector2.new(0.5, 0.5)
      dot.Position = UDim2.new(cx, 0, cy, 0)
      dot.Size = UDim2.fromOffset(heavy and 34 or 20, heavy and 34 or 20)
      dot.BackgroundColor3 = RGB(230, 232, 236)
      dot.BackgroundTransparency = 0.35
      dot.BorderSizePixel = 0
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = dot
      dot.Parent = f
    end
    for _ = 1, heavy and 6 or 3 do   -- 污渍：镜片上一块块发暗的地方
      local s = Instance.new("Frame")
      s.AnchorPoint = Vector2.new(0.5, 0.5)
      s.Position = UDim2.fromScale(0.2 + R:NextNumber() * 0.6, 0.2 + R:NextNumber() * 0.6)
      local r = (heavy and 160 or 100) + R:NextNumber() * 120
      s.Size = UDim2.fromOffset(r, r)
      s.BackgroundColor3 = RGB(8, 8, 8)
      s.BackgroundTransparency = heavy and 0.55 or 0.72
      s.BorderSizePixel = 0
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = s
      s.Parent = f
    end
    f.Visible = false
    return f
  end
  local hurtSet, deadSet = crackSet(1101, 1, false), crackSet(2207, 3, true)
  local note = Instance.new("TextLabel")
  note.AnchorPoint = Vector2.new(0.5, 0)
  note.Position = UDim2.new(0.5, 0, 0, 66)
  note.Size = UDim2.fromOffset(420, 22)
  note.BackgroundTransparency = 1
  note.Font = Enum.Font.BuilderSansBold
  note.TextSize = 16
  note.TextColor3 = RGB(255, 170, 90)
  note.TextStrokeTransparency = 0.4
  note.Text = ""
  note.Parent = root
  local optS = 2
  function G.opticsDead() return optS == 0 end
  RunService.RenderStepped:Connect(function()
    local st = G.drive
    local em = st and st.em
    local d = st and st.d
    local s = (em and d) and W.modState(em, d, "optics") or 2
    if s ~= optS then
      optS = s
      if G.sightReapply then pcall(G.sightReapply) end   -- 打坏了：热成像没了（Drive.lua 换回昼光）
    end
    local on = st ~= nil and st.sight == true and s < 2
    gui.Enabled = on
    hurtSet.Visible = on and s == 1
    deadSet.Visible = on and s == 0
    note.Text = on and ((s == 0) and (G.T and G.T("wt.optDead") or "") or (G.T and G.T("wt.optDmg") or "")) or ""
    if on and not blur then
      blur = Instance.new("BlurEffect")
      blur.Name = "SightDamageBlur"
      blur.Parent = Lighting
    end
    if blur then
      blur.Enabled = on
      blur.Size = (s == 0) and 9 or 3.5
    end
  end)
  G.sightDamageGui = function() return gui, hurtSet, deadSet end   -- 测试用
end

return WtVfx
