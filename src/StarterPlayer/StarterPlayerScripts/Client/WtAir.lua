-- Roblox全面大战场（客户端）——战雷式飞机受伤（用户 11-24 夜「把整个游戏做成战雷」④）
--   服务器 WtAir.lua 写在飞机实体上的属性：WtaP（每个部件一位 0～9）、WtaEng 推力系数、WtaCtl 舵效系数、WtaWing 断了哪边翼（L / R）、
--   WtaTail 尾翼 / 尾桨没了、WtaLift 直升机旋翼还在不在、WtaFire 起火、WtaLeak 漏油、WtaKO 飞行员昏迷
--   · 飞控（Fly.lua 每帧问 G.wtaFlight）：推力、舵效打折；断翼往断的那边滚、升力少一大半；没了尾翼俯仰乱晃；昏迷松杆往下掉
--   · 外面看（谁的飞机都画，2500 格以内）：用户 11-25「发动机各种状态 冒烟什么的都要做出来」——按发动机那块的血分档，从每个喷口出来：
--     轻伤（≤ 66）拖一缕淡灰烟、重伤（≤ 33）浓的深灰烟、打坏了（0）熄火：喷口不亮（Fly.lua）、拖一道黑烟；
--     起火：喷口一团火（一闪一闪）+ 滚滚黑烟；漏油：受伤那边机翼拖一道白色油雾
--   · 断翼（用户 11-25「飞机如果断了机翼 那机翼应该要能掉下去」「机翼应该会消失才对」）：WtaWing 一变，那边外翼从模型上消失
--     （AirModels.breakWing：原模型按 wingcut.py 切出来的外翼块、挂在上面的弹、翼尖灯），断口一块烧黑的截面；
--     复制出来的那截外翼带着飞机的速度往外甩出去，翻滚着掉（重力、阻力），拖油雾和烟，落地躺一会儿再消失
--   · 自己开的：左下一个俯视的飞机损伤图（机翼、尾翼、发动机、油箱、座舱、操纵面按状态上色：淡灰好、黄伤、红没了），
--     起火 / 漏油 / 断翼的字；飞行员昏迷整屏慢慢黑下去、写「飞行员昏迷」
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local WtAir = {}

function WtAir.init(G)
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V, UD2, V2 = Vector3.new, UDim2.new, Vector2.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD = Enum.Font.BuilderSansMedium
  local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
  local FIRE = "rbxasset://textures/particles/fire_main.dds"
  local NEAR = 2500
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local M_OK, M_HURT, M_BAD, M_DEAD = TH.C.NEUTRAL, TH.C.WARN, TH.C.WARN:Lerp(TH.C.BAD, 0.5), TH.C.BAD

  ---------------------------------------------------------------- 飞控要的数（每帧问一次，同一帧缓存）
  local cacheEm, cacheT, cache = nil, -1, nil
  function G.wtaFlight(em)
    if not em then return nil end
    local t = os.clock()
    if em == cacheEm and t == cacheT then return cache end
    cacheEm, cacheT = em, t
    if em:GetAttribute("WtaP") == nil then cache = nil return nil end
    cache = {
      eng = em:GetAttribute("WtaEng") or 1, ctl = em:GetAttribute("WtaCtl") or 1, wing = em:GetAttribute("WtaWing"),
      tail = em:GetAttribute("WtaTail") == true, lift = em:GetAttribute("WtaLift") or 1, ko = em:GetAttribute("WtaKO") == true,
    }
    return cache
  end

  ---------------------------------------------------------------- 外面看：起火、漏油
  local fx = setmetatable({}, { __mode = "k" })   -- [视图] = { M, fire, smoke, leak }
  local function mount(M, cf0)
    local p = Instance.new("Part")
    p.Name = "WtaFx"
    p.Size = V(0.4, 0.4, 0.4)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    AM.attach(M, p, cf0)
    return p
  end
  local function emitter(parent, tex, col, size, life, rate, light)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = tex
    pe.Color = ColorSequence.new(col)
    pe.LightEmission, pe.LightInfluence = light or 0, light and 0 or 0.8
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size[1]), NumberSequenceKeypoint.new(1, size[2]) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
    pe.Lifetime = NumberRange.new(life[1], life[2])
    pe.Speed = NumberRange.new(0.5, 3)
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-60, 60)
    pe.Rate = rate
    pe.Enabled = false
    pe.Parent = parent
    return pe
  end
  local function build(v)
    local M, d = v.M, v.def
    local S = { M = M, fire = {}, smoke = {}, haze = {}, dark = {} }
    -- 每个喷口一组：火、着火的黑烟、轻伤的淡灰烟、重伤 / 熄火的深灰烟（喷口往后半个喷口直径，烟不从机身里冒出来）
    for _, nz in ipairs(AM.nozzles and AM.nozzles(M) or { { p = V(0, 0, d.L * 0.4), r = 0.8 } }) do
      local r = math.max(0.4, nz.r)
      local m = mount(M, CF(nz.p + V(0, 0, r)))
      table.insert(S.fire, emitter(m, FIRE, RGB(255, 150, 60), { r * 3.2, r * 0.6 }, { 0.25, 0.5 }, 60, 0.9))
      table.insert(S.smoke, emitter(m, SMOKE, RGB(40, 38, 36), { r * 3, r * 13 }, { 2.5, 4.5 }, 30))
      table.insert(S.haze, emitter(m, SMOKE, RGB(176, 178, 180), { r * 1.4, r * 6 }, { 1.2, 2.2 }, 10))
      table.insert(S.dark, emitter(m, SMOKE, RGB(74, 72, 70), { r * 2.2, r * 10 }, { 2, 3.6 }, 22))
    end
    for _, pe in ipairs(S.haze) do pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }) end
    local wingX = (d.W or 20) * 0.28
    S.leakL = emitter(mount(M, CF(-wingX, 0, 0)), SMOKE, RGB(236, 240, 244), { 1.2, 5 }, { 1.2, 2.2 }, 40)
    S.leakR = emitter(mount(M, CF(wingX, 0, 0)), SMOKE, RGB(236, 240, 244), { 1.2, 5 }, { 1.2, 2.2 }, 40)
    return S
  end
  local function setOn(pe, on)
    if pe == nil then return end
    if typeof(pe) == "Instance" then
      if pe.Enabled ~= on then pe.Enabled = on end
    else   -- 每个喷口一个：一组
      for _, x in ipairs(pe) do if x.Enabled ~= on then x.Enabled = on end end
    end
  end
  -- 发动机那块的血（WtaP 里 eng 那一位，0～9；没有就 9）
  local function engDigit(em)
    local wp = em:GetAttribute("WtaP")
    if type(wp) ~= "string" then return 9 end
    local i = (#wp == 6) and 3 or 4   -- 直升机 6 块（rotor, tail, eng…），固定翼 7 块（wingL, wingR, tail, eng…）
    return tonumber(wp:sub(i, i)) or 9
  end

  ---------------------------------------------------------------- 自己开的：左下损伤图
  local gui = Instance.new("ScreenGui")
  gui.Name = "WtAirHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or M_OK, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function round(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0, 2)
    c.Parent = f
    return f
  end
  local function label(parent, text, size, pos, ts, color, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 12, color or Color3.new(1, 1, 1), BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.4, RGB(0, 0, 0)
    l.Parent = parent
    return l
  end
  -- 飞机放在左下（开飞机时圆形小地图在左上，左下空着）
  local DI = frame(gui, UD2(0, 230, 0, 128), UD2(0, 24, 1, -24), RGB(0, 0, 0), 1, V2(0, 1))
  DI.Name = "WtAirDamage"
  local scale = Instance.new("UIScale")
  scale.Parent = DI
  do
    local bg = round(frame(DI, UD2(1, 0, 1, 0), nil, RGB(0, 0, 0), 0.55), UDim.new(0, 4))
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = bg
  end
  -- 俯视飞机（机头朝上），每块一个框
  local PL = {}
  local function part(name, size, pos)
    local f = round(frame(DI, size, pos, M_OK, 0.75, V2(0.5, 0.5)))
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = M_OK, 1, 0.45
    s.Parent = f
    f.Name = name
    PL[name] = { f = f, s = s, last = 9, flash = 0 }
    return f
  end
  local CX, CY = 58, 64
  part("fuse", UD2(0, 12, 0, 96), UD2(0, CX, 0, CY))
  part("pilot", UD2(0, 8, 0, 14), UD2(0, CX, 0, CY - 34))
  part("fuel", UD2(0, 10, 0, 22), UD2(0, CX, 0, CY - 6))
  part("eng", UD2(0, 10, 0, 22), UD2(0, CX, 0, CY + 22))
  part("wingL", UD2(0, 44, 0, 18), UD2(0, CX - 28, 0, CY + 2))
  part("wingR", UD2(0, 44, 0, 18), UD2(0, CX + 28, 0, CY + 2))
  part("tail", UD2(0, 34, 0, 9), UD2(0, CX, 0, CY + 40))
  part("ctrl", UD2(0, 4, 0, 4), UD2(0, CX + 52, 0, CY + 52))   -- 操纵面：只在受损时亮（一个小点 + 字）
  part("rotor", UD2(0, 92, 0, 4), UD2(0, CX, 0, CY - 8))   -- 直升机的旋翼：一道横条
  PL.fuse.f.ZIndex, PL.fuel.f.ZIndex, PL.eng.f.ZIndex, PL.pilot.f.ZIndex = 1, 3, 3, 3
  local fireDot = round(frame(DI, UD2(0, 16, 0, 16), UD2(0, CX, 0, CY + 22), RGB(255, 120, 30), 0.1, V2(0.5, 0.5)), UDim.new(0.5, 0))
  fireDot.ZIndex = 5
  local tip = label(DI, "", UD2(0, 110, 0, 100), UD2(0, 118, 0, 12), 12)
  tip.TextWrapped = true
  tip.TextYAlignment = Enum.TextYAlignment.Top
  tip.RichText = true
  local black = frame(gui, UD2(1, 0, 1, 0), nil, RGB(0, 0, 0), 1)
  black.ZIndex = 10
  local koT = label(black, "", UD2(1, 0, 0, 30), UD2(0, 0, 0.5, -15), 24, RGB(255, 90, 76), nil, Enum.TextXAlignment.Center)
  koT.ZIndex = 11
  local koSince = nil

  local ORDER_JET = { "wingL", "wingR", "tail", "eng", "fuel", "pilot", "ctrl" }
  local ORDER_HELI = { "rotor", "tail", "eng", "fuel", "pilot", "ctrl" }
  local function stepHud(st)
    local em = st and st.em
    local wp = em and em:GetAttribute("WtaP")
    if not wp or em:GetAttribute("Wreck") then gui.Enabled = false koSince = nil return end
    gui.Enabled = true
    local vp = workspace.CurrentCamera.ViewportSize
    -- 手机：左下是摇杆和油门键，挪到右上小地图下面；开着光电吊舱时左下是吊舱的读数，先收起
    local touch = game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").KeyboardEnabled
    if touch then DI.AnchorPoint, DI.Position = V2(1, 0), UD2(1, -12, 0, 236) end
    scale.Scale = touch and 0.8 or math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.8, 1.25)
    DI.Visible = not st.eo
    local heli = st.d and st.d.kind == "heli"
    local order = heli and ORDER_HELI or ORDER_JET
    PL.wingL.f.Visible, PL.wingR.f.Visible, PL.rotor.f.Visible = not heli, not heli, heli
    local t = os.clock()
    local states = {}
    for i, k in ipairs(order) do
      local s = tonumber(string.sub(wp, i, i)) or 9
      states[k] = s
      local o = PL[k]
      if s < o.last then o.flash = t + 1 end
      o.last = s
      local col, tr = M_OK, 0.75
      if s <= 0 then col, tr = M_DEAD, 0.1 elseif s <= 3 then col, tr = M_BAD, 0.15 elseif s <= 6 then col, tr = M_HURT, 0.25 end
      if t < o.flash and (t * 8) % 1 < 0.5 then col, tr = Color3.new(1, 1, 1), 0 end
      o.f.BackgroundColor3, o.f.BackgroundTransparency = col, tr
      o.s.Color, o.s.Transparency = col, (s >= 7) and 0.45 or 0
      if k == "ctrl" then o.f.Visible = s < 7 end
      if (k == "wingL" or k == "wingR") and s <= 0 then o.f.BackgroundTransparency = 0.6 end   -- 断了：只剩一个红框
    end
    local fire = em:GetAttribute("WtaFire") == true
    fireDot.Visible = fire
    if fire then
      local pu = 0.5 + 0.5 * math.sin(t * 9)
      fireDot.Size = UD2(0, 12 + 7 * pu, 0, 12 + 7 * pu)
      fireDot.BackgroundColor3 = RGB(255, 90 + math.floor(90 * pu), 30)
    end
    -- 右边的字：起火、漏油、断翼、发动机、尾翼、操纵
    local lines = {}
    local function add(key, col) table.insert(lines, string.format('<font color="#%02X%02X%02X">%s</font>', math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), T(key))) end
    if fire then add("wta.tFire", ((t * 3) % 1 < 0.6) and M_DEAD or M_BAD) end
    if em:GetAttribute("WtaLeak") then add("wta.tLeak", M_HURT) end
    if em:GetAttribute("WtaWing") then add("wta.tWing", M_DEAD) end
    if heli and (states.rotor or 9) <= 0 then add("wta.tRotor", M_DEAD) end
    local eng = em:GetAttribute("WtaEng") or 1
    if eng <= 0 then add("wta.tEngDead", M_DEAD) elseif eng < 1 then add("wta.tEng", M_HURT) end
    if em:GetAttribute("WtaTail") then add(heli and "wta.tTailRotor" or "wta.tTail", M_DEAD) end
    if (states.ctrl or 9) < 7 then add("wta.tCtrl", M_HURT) end
    tip.Text = table.concat(lines, "\n")
    -- 飞行员昏迷：整屏慢慢黑下去
    local ko = em:GetAttribute("WtaKO") == true
    if ko and not koSince then koSince = t end
    if not ko then koSince = nil end
    local k = koSince and math.clamp((t - koSince) / 1.6, 0, 1) or 0
    black.BackgroundTransparency = 1 - 0.92 * k
    koT.Text = (k > 0.3) and T("wta.ko") or ""
  end
  G.wtaHudShown = function() return gui.Enabled end   -- 测试用

  ---------------------------------------------------------------- 断掉的外翼：翻滚着掉下去
  local GRAV = AD.GRAV or 27.5
  local debris = {}
  local function groundAt(p)
    local Map = G.Map
    local ok, h = pcall(function() return Map and AD.ground(Map, p.X, p.Z) end)
    return (ok and type(h) == "number") and h or -1e9
  end
  local function spawnDebris(list, v, side)
    if #list == 0 then return end
    local cf0 = v.cf or list[1].cf
    local c = V()
    for _, x in ipairs(list) do c += x.cf.Position end
    c /= #list
    local piv = CF(c) * (cf0 - cf0.Position)
    local m = Instance.new("Model")
    m.Name = "WingDebris"
    local plist, rel = {}, {}
    local big, bigV = nil, 0
    for _, x in ipairs(list) do
      x.p.Parent = m
      table.insert(plist, x.p)
      table.insert(rel, piv:ToObjectSpace(x.cf))
      local s = x.p.Size
      if s.X * s.Y * s.Z > bigV then big, bigV = x.p, s.X * s.Y * s.Z end
    end
    m.Parent = workspace
    if big then   -- 断口那头拖油雾、烟（几秒后淡掉）
      local att = Instance.new("Attachment")
      att.Parent = big
      local sx = (side == "L") and 1 or -1   -- 断口在靠机身那边
      att.Position = big.CFrame:PointToObjectSpace(big.Position + cf0.RightVector * sx * big.Size.X * 0.4)
      local pe1 = emitter(att, SMOKE, RGB(236, 240, 244), { 1.5, 6 }, { 1, 2 }, 40)
      local pe2 = emitter(att, SMOKE, RGB(60, 56, 52), { 2, 9 }, { 2, 3.5 }, 18)
      pe1.Enabled, pe2.Enabled = true, true
      task.delay(4, function() pe1.Enabled = false end)
      task.delay(7, function() pe2.Enabled = false end)
    end
    local sgn = (side == "L") and -1 or 1
    local vel = (v.vel or V()) + cf0.RightVector * sgn * 16 + cf0.UpVector * 6
    local spin = V((math.random() - 0.5) * 2, (math.random() - 0.5) * 1.5, -sgn * (2.5 + math.random() * 2.5))
    table.insert(debris, { m = m, plist = plist, rel = rel, cf = piv, vel = vel, spin = spin, t = 0, clist = {} })
  end
  local function stepDebris(dt)
    for i = #debris, 1, -1 do
      local D = debris[i]
      D.t += dt
      if D.t > 22 or not D.m.Parent then
        D.m:Destroy()
        table.remove(debris, i)
      elseif not D.landed then
        -- 一截机翼：阻力大（翼面迎着风翻滚），掉得比飞机慢，横着飘
        D.vel += V(0, -GRAV, 0) * dt
        D.vel *= math.max(0, 1 - 0.45 * dt)
        local p = D.cf.Position + D.vel * dt
        local gy = groundAt(p)
        if p.Y < gy + 0.5 then
          p = V(p.X, gy + 0.5, p.Z)
          D.landed = true
        end
        D.cf = CF(p) * (D.cf - D.cf.Position) * CFrame.Angles(D.spin.X * dt, D.spin.Y * dt, D.spin.Z * dt)
        for k, r in ipairs(D.rel) do D.clist[k] = D.cf * r end
        workspace:BulkMoveTo(D.plist, D.clist, Enum.BulkMoveMode.FireCFrameChanged)
      elseif D.t > 16 then   -- 落地躺一会儿，淡掉
        local k = (D.t - 16) / 6
        for _, q in ipairs(D.plist) do q.Transparency = math.max(q.Transparency, k) end
      end
    end
  end
  G.wtaDebris = function() return #debris end   -- 测试用

  ---------------------------------------------------------------- 每帧
  local acc = 0
  G.frameConn("WtAir", function(dt)
    local st = G.fly
    G.try_(stepHud, st and st.pilot ~= false and st or nil)
    if #debris > 0 then G.try_(stepDebris, dt) end
    acc += dt
    if acc < 0.1 then return end
    acc = 0
    local cp = workspace.CurrentCamera.CFrame.Position
    for em, v in pairs(G.views or {}) do
      if v.kind == "air" and v.M and v.def and em.Parent then
        local wreck = em:GetAttribute("Wreck") == true
        local fire = not wreck and em:GetAttribute("WtaFire") == true
        local leak = not wreck and em:GetAttribute("WtaLeak") ~= nil
        local ed = wreck and 9 or engDigit(em)   -- 0 打坏、1～3 重伤、4～6 轻伤
        local hurt = ed <= 6
        local pos = v.cf and v.cf.Position or (v.root and v.root.CFrame.Position) or cp
        local near = (pos - cp).Magnitude < NEAR
        -- 断翼：那边外翼消失、掉下去（远处的只藏不掉）；落地修好了（WtaWing 清掉）外翼回来；成了残骸的不再变
        local wingA = em:GetAttribute("WtaWing")
        local gone = v.M.wingGone
        if (wingA == "L" or wingA == "R") and not (gone and gone[wingA]) then
          local list = AM.breakWing(v.M, wingA)
          if near then spawnDebris(list, v, wingA) else for _, x in ipairs(list) do x.p:Destroy() end end
        elseif wingA == nil and gone and not wreck then
          for sd in pairs(gone) do AM.restoreWing(v.M, sd) end
        end
        local S = fx[v]
        if (fire or leak or hurt) and near and (not S or S.M ~= v.M) then
          S = build(v)
          fx[v] = S
        end
        if S then
          setOn(S.fire, fire and near)
          setOn(S.smoke, fire and near)
          setOn(S.haze, near and not fire and ed >= 4 and ed <= 6)
          setOn(S.dark, near and not fire and ed <= 3)
          -- 着火的火苗一闪一闪（不是一直一样大）；熄火的黑烟淡一点（没有排气推着）
          if fire and near then
            local k = 0.75 + 0.35 * math.sin(os.clock() * 17 + #S.fire) + 0.15 * math.sin(os.clock() * 41)
            for _, pe in ipairs(S.fire) do pe.Rate = 60 * k end
          end
          if ed == 0 then for _, pe in ipairs(S.dark) do pe.Rate = 12 end
          else for _, pe in ipairs(S.dark) do pe.Rate = 22 end end
          -- 漏油：被打的那边机翼（不知道哪边就两边都冒一点）
          local wing = em:GetAttribute("WtaWing")
          setOn(S.leakL, leak and near and wing ~= "L")
          setOn(S.leakR, leak and near and wing ~= "R")
        end
      end
    end
  end)
end

return WtAir
