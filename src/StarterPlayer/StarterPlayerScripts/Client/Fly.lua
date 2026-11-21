-- Roblox全面大战场（客户端）——飞机、直升机：样子和驾驶
--   样子（G.viewKind.air，View.lua 每帧调）：AirModels 按型号拼零件；位置平滑跟着服务器的 Root，舵面、起落架、弹舱、座舱盖、旋翼按实体属性
--     （Thr、Gear、Pit、Rol、Yaw、Bay、BayS、Rpm、Ty、Gp……）摆；自己开的用本地的；被击毁的往下掉、冒火冒黑烟，落地炸一下
--   驾驶（服务器推来的 S.veh.air）：位置在本地算，每秒 15 次报给服务器（Air.lua 查速度、查撞地）
--     固定翼（用户 11-21：改成 WASD 控制方向、不要准心控制；飞机太灵活）：键盘就是驾驶杆——S 拉杆抬头、W 推杆低头、A / D 滚转、
--       Q / E 方向舵（杆量 0.3 秒推满、松开回中），Shift / Ctrl 油门（推满再推进加力，↑ / ↓ 同样）；松杆 1 g，小坡度自己慢慢摆平；
--       镜头钉在机身后上方顺着机头看，机头前方的全息标记一直在屏幕正中（航炮就打那里）；按住 Alt 鼠标自由看；
--       滚转、俯仰角速度和最大过载收到真飞机的五六七成（AGIL）。无人机（平板上飞）照旧鼠标给方向、W / S 油门；
--       开着光电吊舱、飞出作战区自动掉头时也是按给的方向自动飞（教官）；
--       速度不够失速（机头往下掉）、爬升掉速、俯冲加速、拉杆转弯掉能量；跑道 / 甲板上：油门加速，速度够了按 S 抬头离地；
--       放着起落架、下沉不快、速度不快、姿态平就能落地（落在自己的机场 / 甲板上停 5 秒补弹修理）
--     直升机：W / S 前后、A / D 转向（快的时候压坡度转弯）、E 升 / Q 降，旋翼先转起来才飞得动；鼠标转镜头、机头炮塔跟着镜头瞄
--     武器：鼠标左键 机炮（直升机机头炮塔跟着鼠标瞄）；F 发导弹 / 火箭 / 炸弹（1～6 选用哪种；导弹、制导炸弹要锁定：目标在导引头视场里待够锁定时间），
--       R 换目标；X 热诱弹；G 起落架；空格 下飞机（在天上跳伞）
--     平显：速度、高度、油门、准星（机头指向）、锁定框、炸弹落点、失速 / 拉起 / 导弹来袭 / 飞出作战区警告（鼠标瞄准圈只有无人机画）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Fly = {}

function Fly.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local AM = require(script.Parent:WaitForChild("AirModels"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local rad, deg = math.rad, math.deg
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local GR = AD.GRAV
  -- 用户 11-21：飞机过于灵活——玩家开的固定翼滚转、俯仰角速度和最大过载都收一截（起转、停住的快慢跟着一起慢下来）
  local AGIL = { roll = 0.45, pitch = 0.65, g = 0.72 }
  local function T(k, ...) return G.T(k, ...) end
  local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
  local function approach(a, b, s)
    if a < b then return math.min(b, a + s) end
    return math.max(b, a - s)
  end
  local function angDiff(a, b) return (b - a + math.pi) % (2 * math.pi) - math.pi end
  local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
  local function ground(x, z) return AD.ground(Map, x, z) end

  local st = nil   -- 正在开 / 坐的飞机
  G.fly = nil
  G.AD = AD

  ---------------------------------------------------------------- 样子

  -- 挂载属性 "pl15,pl15,,kd88" → { "pl15", "pl15", false, "kd88" }
  local function parseLoad(s, d)
    local out = {}
    local i = 0
    for w in string.gmatch((s or "") .. ",", "([^,]*),") do
      i += 1
      out[i] = (w ~= "") and w or false
    end
    for k = 1, #(d.st or {}) do if out[k] == nil then out[k] = false end end
    return out
  end

  local CH = { thr = "Thr", gear = "Gear", flap = "Flap", pit = "Pit", rol = "Rol", yaw = "Yaw", bay = "Bay", bayS = "BayS", rpm = "Rpm", col = "Col", can = "Can",
    hook = "Hook", brk = "Brk", ty = "Ty", gp = "Gp", fold = "Fold" }

  G.viewKind = G.viewKind or {}
  G.viewKind.air = {
    importReady = function(v) return v.M ~= nil and not v.M.imported and v.def ~= nil and AM.importedFor(v.def) ~= nil end,   -- 原模型后来才复制齐：View 重建
    build = function(v, em, team)
      local d = AD.get(em:GetAttribute("Model") or "")
      if not d then return false end
      local M = AM.build(d, team, parseLoad(em:GetAttribute("Load"), d))
      v.M, v.def, v.model, v.anchor = M, d, M.model, M.anchor
      v.c = {}
      v.spin1, v.spin2, v.spinT, v.spinP = math.random() * 6, math.random() * 6, 0, 0
      v.cf = v.root.CFrame
      v.frame = 0
      return true
    end,
    step = function(v, dt, camPos)
      local em, d, M = v.em, v.def, v.M
      local own = st and st.em == em and st
      local target = v.root.CFrame
      if em:GetAttribute("Wreck") then   -- 被击毁：带着速度往下掉、翻滚、冒烟，落地炸一下（别人的飞机：速度按收到的位置快照算，View.lua G.follow）
        if not v.wreck then
          v.wreck = { vel = (own and own.vel) or (v.fl and v.fl.vel) or V(), spin = (math.random() - 0.5) * 3, t = 0 }
          if v.M then v.M.dark = true end   -- 被击毁：灯全灭
          for _, it in ipairs(M.items) do
            local p = it.p
            if p:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
              for _, sa in ipairs(p:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
              pcall(function() p.TextureID = "" end)
              if p.Transparency < 1 then p.Color = Color3.fromRGB(40, 38, 36) end
            elseif p:IsA("BasePart") and p.Transparency < 1 then p.Color = p.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.6) end
          end
        end
        local W = v.wreck
        W.t += dt
        if not W.down then
          W.vel += V(0, -GR, 0) * dt
          W.vel *= (1 - 0.1 * dt)
          local p = v.cf.Position + W.vel * dt
          local g = ground(p.X, p.Z)
          if p.Y < g + 1 then
            W.down = true
            p = V(p.X, g + 1, p.Z)
            if G.boom then G.boom(p, 2, "wreck") end
          end
          local look = (W.vel.Magnitude > 5) and W.vel.Unit or v.cf.LookVector
          v.cf = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, W.t * W.spin)
          W.smokeT = (W.smokeT or 0) - dt
          if W.smokeT <= 0 and G.fxPart then
            W.smokeT = 0.06
            local s = G.fxPart(Enum.PartType.Ball, V(4, 4, 4), CFrame.new(p), RGB(40, 38, 36), Enum.Material.SmoothPlastic, 0.3)
            if G.tween then G.tween(s, 2.4, { Size = V(16, 16, 16), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s, 2.5)
            local f = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(p), RGB(255, 140, 40), Enum.Material.Neon, 0.1)
            if G.tween then G.tween(f, 0.4, { Size = V(6, 6, 6), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(f, 0.45)
          end
        end
      elseif own then
        v.cf = own.cf
      else   -- 别人的飞机：快照插值（匀速，不一顿一顿；跳太远直接过去）
        v.cf = G.follow(v, target, 400)
      end
      -- 通道：自己开的用本地的操纵量；别人的读属性
      local c = v.c
      if own then
        for k in pairs(CH) do c[k] = own.c[k] or 0 end
      else
        for k, a in pairs(CH) do c[k] = em:GetAttribute(a) or 0 end
        if em:GetAttribute("BayS") == nil then c.bayS = c.bay end
        v.foldS = approach(v.foldS or c.fold, c.fold, dt / 4)   -- 折翼：服务器按 0.1 一档推过来，这边平滑成动画
        c.fold = v.foldS
      end
      v.canS = approach(v.canS or c.can, c.can, dt * 0.7)   -- 座舱盖开关是 0 / 1：显示时一秒多一点慢慢掀开、合上
      c.can = v.canS
      v.foldS = approach(v.foldS or c.fold, c.fold, dt / 4.5)   -- 折叠机翼（用户：折叠机翼没有动画）：也是 0 / 1，显示时四秒多慢慢折起、展开
      c.fold = v.foldS
      local onGround = c.gear > 0.9 and (v.cf.Position.Y - ground(v.cf.Position.X, v.cf.Position.Z) - d.gearH) < 1.5
      c.door = (d.sideDoor and onGround) and 1 or 0
      c.ramp = (d.ramp and onGround) and 1 or 0
      -- 旋翼、螺旋桨转（看着慢一点，免得一格一格跳）
      local rpm = c.rpm or 0
      if d.rotor then v.spin1 = (v.spin1 + rpm / 100 * d.rotor.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.rotor2 then v.spin2 = (v.spin2 + rpm / 100 * d.rotor2.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2) end
      if d.tail then v.spinT = (v.spinT + rpm / 100 * 18 * dt) % (math.pi * 2) end
      if d.prop then v.spinP = (v.spinP + (c.thr or 0) / 100 * 30 * dt) % (math.pi * 2) end
      if d.fanEng then v.spinF = ((v.spinF or 0) + (0.25 + (c.thr or 0) / 100) * 45 * dt) % (math.pi * 2) end   -- 涡扇风扇（A-10）：慢车也转
      c.spin1, c.spin2, c.spinT, c.spinP, c.spinF = v.spin1, v.spin2, v.spinT, v.spinP, v.spinF
      AM.setStores(M, em:GetAttribute("Stores"))
      -- 远的少摆几次（一架几百个零件）
      v.frame += 1
      local dist = (v.cf.Position - camPos).Magnitude
      local every = (own or dist < 1500) and 1 or ((dist < 4000) and 2 or 4)
      if v.frame % every == 0 then AM.pose(M, v.cf, c, os.clock()) end
      if G.aeroStep then G.aeroStep(v, dt, own or nil, camPos) end   -- 机翼凝结雾、翼尖涡流、蒸汽锥、音爆（Aero.lua）
      -- 旋翼下洗（用户 11-20：载具照 UE5 的水平升级）：直升机离地 / 水面 70 格以内，正下方往四周吹起一圈尘土（陆地）或水雾（海面），越低越浓
      if d.rotor and dist < 2200 then
        local p = v.cf.Position
        local h = Map.height(p.X, p.Z)
        local gy = math.max(h, 0)
        local k = math.clamp(rpm / 100, 0, 1) * math.clamp(1 - (p.Y - gy) / 70, 0, 1)
        local W = v.wash
        if k > 0.03 and not W then
          local part = Instance.new("Part")
          part.Name = "RotorWash"
          part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
          part.Transparency, part.Size = 1, Vector3.new(1, 1, 1)
          part.Parent = v.model
          local pe = Instance.new("ParticleEmitter")
          pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
          pe.Rate = 0
          pe.Lifetime = NumberRange.new(1.2, 2.6)
          pe.Speed = NumberRange.new(22, 44)
          pe.SpreadAngle = Vector2.new(88, 88)   -- 从正上方张开到快水平：往四周吹
          pe.EmissionDirection = Enum.NormalId.Top
          pe.Acceleration = V(0, 3, 0)
          pe.Drag = 2.2
          pe.Rotation = NumberRange.new(0, 360)
          pe.RotSpeed = NumberRange.new(-40, 40)
          pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 17) })
          pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
          pe.LightInfluence = 1
          pe.Parent = part
          W = { part = part, pe = pe }
          v.wash = W
        end
        if W then
          W.part.CFrame = CF(p.X, gy + 0.6, p.Z)
          local water = h < 0.4
          if W.water ~= water then
            W.water = water
            W.pe.Color = ColorSequence.new(water and Color3.fromRGB(226, 234, 236) or Color3.fromRGB(170, 150, 118))
          end
          W.pe.Rate = (k > 0.03) and (8 + 70 * k) or 0
          v.washK = k   -- 测试用
        end
      end
    end,
  }

  ---------------------------------------------------------------- 平显

  local ui = G.ui
  local gui = Instance.new("ScreenGui")
  gui.Name = "Fly"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Parent = me:WaitForChild("PlayerGui")
  local HUD = RGB(118, 240, 140)   -- 绿色全息（用户 11-19：飞机操作界面照 MWT 改，跟开坦克的界面一套颜色，那时是青色；用户 11-21：蓝色全部改成绿色）
  local function hud(text, size, pos, ts, anchor, align)
    local l = ui.label(gui, text, size, pos, ts or 16, HUD, Enum.Font.Code, anchor, align)
    l.TextStrokeTransparency = 0.5
    l.TextStrokeColor3 = RGB(0, 24, 10)
    l.Visible = false
    return l
  end
  -- 原来的 DCS 式平显（速度 / 高度框、航向、大圈、右侧武器栏、下面的信息栏、G / α / M、速度矢量、机头十字）收进这个框：
  --   用户 11-19 要开飞机的界面照 MWT 的截图改（AirHud.lua：右上机型和全息侧影、准星两边高度 / 速度、六边形武器键……），
  --   只有遥控无人机（画面在战术平板里，四边是平板的外壳）还用原来这一套
  local dcs = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  dcs.Name = "DcsHud"
  dcs.Visible = false
  local panel = ui.frame(gui, UDim2.fromOffset(460, 86), UDim2.new(0.5, 0, 1, -24), RGB(12, 16, 20), 0.35, Vector2.new(0.5, 1))   -- 操作说明在屏幕最下面一行（UI.lua，st.help）
  panel.Visible = false
  local aName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local aInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 44), 14, Color3.new(1, 1, 1), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  local aWpn = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 62), 14, RGB(255, 220, 120), Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  ui.flatPanel(panel, { hp = hpBg, name = aName })   -- 跟新界面一个样子（UI.lua）
  local bore = hud("+", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 34, Vector2.new(0.5, 0.5))   -- 机头指向
  local aimRing = hud("◯", UDim2.fromOffset(36, 36), UDim2.fromScale(0.5, 0.5), 30, Vector2.new(0.5, 0.5))   -- 鼠标想去的方向
  aimRing.TextColor3 = Color3.new(1, 1, 1)
  local lockBox = ui.frame(gui, UDim2.fromOffset(46, 46), UDim2.new(), HUD, 1, Vector2.new(0.5, 0.5))
  lockBox.Visible = false
  local lockStroke = ui.stroke(lockBox, HUD, 2, 0)
  local lockText = hud("", UDim2.fromOffset(160, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  local pipper = hud("◎", UDim2.fromOffset(30, 30), UDim2.new(), 26, Vector2.new(0.5, 0.5))   -- 炸弹落点
  pipper.TextColor3 = RGB(255, 200, 80)
  local spdText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, -230, 0.5, 0), 20, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local altText = hud("", UDim2.fromOffset(140, 26), UDim2.new(0.5, 230, 0.5, 0), 20, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local thrText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, -230, 0.5, 26), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local vsText = hud("", UDim2.fromOffset(140, 18), UDim2.new(0.5, 230, 0.5, 26), 14, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local fuelText = hud("", UDim2.fromOffset(200, 18), UDim2.new(0.5, -230, 0.5, 46), 14, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)   -- 油量、按现在的油门还能飞多久
  local warnText = hud("", UDim2.fromOffset(520, 34), UDim2.new(0.5, 0, 0.5, -130), 26, Vector2.new(0.5, 0.5))
  warnText.TextColor3 = RGB(255, 80, 70)
  local landMark = hud("◇", UDim2.fromOffset(34, 34), UDim2.new(), 30, Vector2.new(0.5, 0.5))   -- 降落点
  landMark.TextColor3 = RGB(120, 236, 150)

  ---------------------------------------------------------------- 平显的俯仰梯、速度矢量、过载 / 迎角 / 马赫（用户：飞机飞行参考 DCS）
  -- 固定翼才有：俯仰梯每 5° 一档（正的实线、端头往下，负的虚线、端头往上；地平线一根长的），按真实的方向投到屏幕上（跟着天地转、跟着机头偏）；
  --   速度矢量（航迹）一个带两翼一尾的小圈；左边 G 过载、α 迎角、M 马赫；过载太大眼前发灰（灰视）、负过载发红（红视）
  local ladderPool = {}
  local function ladderLine()
    local holder = ui.frame(gui, UDim2.fromOffset(10, 10), UDim2.new(), HUD, 1, Vector2.new(0.5, 0.5))
    holder.Name = "PitchLadder"
    holder.Visible = false
    local segs = {}
    for i = 1, 4 do   -- 左右各两段（负的画成虚线：每边两段中间留空；正的两段连成一段）
      segs[i] = ui.frame(holder, UDim2.fromOffset(10, 2), UDim2.new(), HUD, 0.15, Vector2.new(0.5, 0.5))
    end
    local ticks = { ui.frame(holder, UDim2.fromOffset(2, 9), UDim2.new(), HUD, 0.15, Vector2.new(0.5, 0)), ui.frame(holder, UDim2.fromOffset(2, 9), UDim2.new(), HUD, 0.15, Vector2.new(0.5, 0)) }
    local labs = { ui.label(holder, "", UDim2.fromOffset(30, 14), UDim2.new(), 12, HUD, Enum.Font.Code, Vector2.new(0.5, 0.5)), ui.label(holder, "", UDim2.fromOffset(30, 14), UDim2.new(), 12, HUD, Enum.Font.Code, Vector2.new(0.5, 0.5)) }
    for _, l in ipairs(labs) do l.TextStrokeTransparency, l.TextStrokeColor3 = 0.5, RGB(0, 24, 10) end
    return { f = holder, segs = segs, ticks = ticks, labs = labs }
  end
  for i = 1, 11 do ladderPool[i] = ladderLine() end
  local fpm = ui.frame(gui, UDim2.fromOffset(16, 16), UDim2.new(), HUD, 1, Vector2.new(0.5, 0.5))
  fpm.Name = "FlightPathMarker"
  fpm.Visible = false
  do
    ui.stroke(fpm, HUD, 1.6, 0.05)
    ui.round(fpm, 8)
    ui.frame(fpm, UDim2.fromOffset(14, 2), UDim2.new(0, -14, 0.5, 0), HUD, 0.05, Vector2.new(0, 0.5))
    ui.frame(fpm, UDim2.fromOffset(14, 2), UDim2.new(1, 0, 0.5, 0), HUD, 0.05, Vector2.new(0, 0.5))
    ui.frame(fpm, UDim2.fromOffset(2, 8), UDim2.new(0.5, 0, 0, -8), HUD, 0.05, Vector2.new(0.5, 0))
  end
  local gText = hud("", UDim2.fromOffset(120, 18), UDim2.new(0.5, -230, 0.5, 70), 15, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local aText = hud("", UDim2.fromOffset(120, 18), UDim2.new(0.5, -230, 0.5, 90), 15, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  local mText = hud("", UDim2.fromOffset(120, 18), UDim2.new(0.5, -230, 0.5, 110), 15, Vector2.new(1, 0.5), Enum.TextXAlignment.Right)
  gText.Name, aText.Name, mText.Name = "GLoad", "AoA", "Mach"
  -- 灰视 / 红视：四边往里压的渐变 + 整屏一层（过载撑久了越来越重，松杆一两秒缓过来）
  local gGui = Instance.new("ScreenGui")
  gGui.Name = "GEffect"
  gGui.IgnoreGuiInset = true
  gGui.ResetOnSpawn = false
  gGui.DisplayOrder = 6   -- 盖在平显上面：灰视、红视连平显一起看不清（跟真的一样）
  gGui.Parent = me:WaitForChild("PlayerGui")
  local gVig = {}
  for _, e in ipairs({ { Vector2.new(0, 0), UDim2.new(1, 0, 0.42, 0), 90 }, { Vector2.new(0, 1), UDim2.new(1, 0, 0.42, 0), -90 },
    { Vector2.new(0, 0), UDim2.new(0.34, 0, 1, 0), 0 }, { Vector2.new(1, 0), UDim2.new(0.34, 0, 1, 0), 180 } }) do
    local f = ui.frame(gGui, e[2], UDim2.fromScale(e[1].X, e[1].Y), RGB(0, 0, 0), 0, e[1])
    local gr = Instance.new("UIGradient")
    gr.Rotation = e[3]
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    gr.Parent = f
    f.Visible = false
    table.insert(gVig, f)
  end
  local gFill = ui.frame(gGui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  gFill.Name = "GFill"
  local gCC = Instance.new("ColorCorrectionEffect")
  gCC.Name = "GLocCC"
  gCC.Enabled = false
  gCC.Parent = game:GetService("Lighting")
  local gStress = 0   -- 过载累积（正：灰视，负：红视）
  local landText = hud("", UDim2.fromOffset(260, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  landText.TextColor3 = RGB(120, 236, 150)
  -- 落地补给的状态（服务器的 Rest 属性）：停稳倒计时 / 维修中 / 可以起飞 / 这里不能补给
  local restText = hud("", UDim2.fromOffset(560, 26), UDim2.new(0.5, 0, 0.5, -96), 20, Vector2.new(0.5, 0.5))
  restText.Name = "RestText"
  -- 用户发的截图那样：速度、高度各在一个绿框里（左、右），顶上航向；中间一个大圈（选中武器能锁的范围：导弹导引头的离轴角、
  --   航炮 / 火箭 / 炸弹的瞄准圈），圈底下写着武器和射程
  local function box(w, h, pos, anchor)
    local f = ui.frame(gui, UDim2.fromOffset(w, h), pos, RGB(0, 22, 8), 0.72, anchor)
    ui.stroke(f, HUD, 2, 0.1)
    f.Visible = false
    return f
  end
  local spdBox = box(120, 46, UDim2.new(0.5, -300, 0.5, 0), Vector2.new(1, 0.5))
  local altBox = box(120, 46, UDim2.new(0.5, 300, 0.5, 0), Vector2.new(0, 0.5))
  local hdgBox = box(74, 30, UDim2.new(0.5, 0, 0, 104), Vector2.new(0.5, 0.5))
  spdBox.Name, altBox.Name, hdgBox.Name = "SpdBox", "AltBox", "HdgBox"
  for _, it in ipairs({ { spdText, spdBox }, { altText, altBox } }) do
    local l = it[1]
    l.Parent, l.Size, l.Position, l.AnchorPoint = it[2], UDim2.new(1, -8, 1, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
    l.TextSize, l.TextXAlignment, l.Visible = 30, Enum.TextXAlignment.Center, true
  end
  local hdgText = ui.label(hdgBox, "", UDim2.fromScale(1, 1), nil, 18, HUD, Enum.Font.Code)
  local spdCap = hud(T("hud.spd"), UDim2.fromOffset(120, 16), UDim2.new(0.5, -420, 0.5, -34), 13, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  local altCap = hud(T("hud.alt"), UDim2.fromOffset(120, 16), UDim2.new(0.5, 300, 0.5, -34), 13, Vector2.new(0, 0.5), Enum.TextXAlignment.Left)
  thrText.Position, vsText.Position, fuelText.Position = UDim2.new(0.5, -300, 0.5, 36), UDim2.new(0.5, 300, 0.5, 36), UDim2.new(0.5, -300, 0.5, 56)
  thrText.AnchorPoint, vsText.AnchorPoint, fuelText.AnchorPoint = Vector2.new(1, 0), Vector2.new(0, 0), Vector2.new(1, 0)
  local ring = ui.frame(gui, UDim2.fromOffset(300, 300), UDim2.fromScale(0.5, 0.5), HUD, 1, Vector2.new(0.5, 0.5))
  ring.Name = "HudRing"
  ui.round(ring, 2000)
  ui.stroke(ring, HUD, 1.5, 0.55)   -- 细、淡（用户：这个圈太小了挡视野——放大到画面边上，线也别抢眼）
  ring.Visible = false
  for _, a in ipairs({ { 0.5, 0, 2, 12 }, { 0.5, 1, 2, 12 }, { 0, 0.5, 12, 2 }, { 1, 0.5, 12, 2 } }) do   -- 上下左右四个刻度
    ui.frame(ring, UDim2.fromOffset(a[3], a[4]), UDim2.fromScale(a[1], a[2]), HUD, 0.45, Vector2.new(0.5, 0.5))
  end
  local ringText = hud("", UDim2.fromOffset(240, 18), UDim2.new(), 14, Vector2.new(0.5, 0))
  ringText.Name = "RingText"

  -- 右侧竖排武器栏（用户：导弹什么的在侧面显示，按几切换到什么导弹，带导弹的图标和剩余数量）：
  --   每行 [按键] 图标 名字 ×剩几发，选中的那行亮；打光了变灰；最下面一行热诱弹（X）
  local wList = ui.frame(gui, UDim2.fromOffset(260, 10), UDim2.new(1, -18, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(1, 0.5))
  wList.Name = "WeaponList"
  wList.Visible = false
  local wRows = {}
  -- 弹的图标：几块小方块拼的（空空弹细长带弹翼、空地弹粗、火箭巢、炸弹、航炮一排炮弹、热诱弹三颗亮点）
  local function drawIcon(ic, it)
    local kind = it.flare and "flare" or (it.w and it.w.kind) or "gun"
    local function r(x, y, sw, sh, rot, rr)
      local f = ui.frame(ic, UDim2.fromOffset(sw, sh), UDim2.fromOffset(x, y), HUD, 0, Vector2.new(0.5, 0.5))
      if rot then f.Rotation = rot end
      if rr then ui.round(f, rr) end
      return f
    end
    if kind == "aam" then
      r(30, 10, 44, 3) r(53, 10, 6, 3, nil, 2)
      r(12, 6, 8, 2, -35) r(12, 14, 8, 2, 35)
      r(31, 7, 6, 2, -30) r(31, 13, 6, 2, 30)
    elseif kind == "agm" then
      r(30, 10, 40, 6) r(51, 10, 6, 6, nil, 3)
      r(12, 5, 9, 3, -40) r(12, 15, 9, 3, 40)
    elseif kind == "rkt" then
      local pod = r(28, 10, 36, 16, nil, 5)
      pod.BackgroundTransparency = 0.55
      for k = -1, 1 do r(43, 10 + k * 4, 3, 3, nil, 2) end
    elseif kind == "bomb" then
      r(30, 10, 30, 9, nil, 5) r(13, 6, 7, 2, -30) r(13, 14, 7, 2, 30)
    elseif kind == "flare" then
      for k = 0, 2 do
        local d = r(16 + k * 14, 10 + ((k == 1) and -3 or 3), 6, 6, nil, 3)
        d.BackgroundColor3 = RGB(255, 232, 150)
      end
    else
      for k = 0, 3 do r(12 + k * 12, 10, 9, 4, nil, 2) end
    end
  end

  -- 光电吊舱的画面（P 键；用户给的参考：F-16 的瞄准吊舱页面 TGP）：
  --   中间 4:3 的显示器（外面全黑），四边是多功能显示器的按键字（上 A-G / NARO 1.0x / OVRD / CNTL，左 WHOT / SP / CZ，下 SWAP / HSD / SMS / [TGP] / DCLT），
  --   贯穿全屏、中间留空的细十字；跟踪到车、船、飞机就套一个 POINT 方框，没跟踪是 AREA；右上指北箭头；
  --   左下激光编码 L 1688、目标斜距 T（海里），右下高度（英尺）、TTI 弹着时间；
  --   显示器右边一栏：投放方式 · 武器、TTI 大字和进度条、武器状态（投出去了 AWAY、激光 ARM、LST）、一句提示、按键说明
  local MFD = RGB(232, 234, 230)
  local MFD_DIM = RGB(150, 154, 150)
  local MOB = G.mobile == true
  local eoGui = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  eoGui.Name = "EoView"
  eoGui.Visible = false
  eoGui.ZIndex = 10   -- 盖住平显（速度、高度框等）
  local TG = {}
  local disp = ui.frame(eoGui, UDim2.fromScale(1, 0.78), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  disp.Name = "TgpDisplay"
  disp.ZIndex = 10
  do
    local a = Instance.new("UIAspectRatioConstraint")
    a.AspectRatio = 4 / 3
    a.Parent = disp
    local mask = Instance.new("UIStroke")   -- 显示器外面全黑
    mask.Thickness = 3000
    mask.Color = RGB(0, 0, 0)
    mask.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mask.Parent = disp
    local edge = ui.frame(disp, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
    edge.ZIndex = 11
    ui.stroke(edge, RGB(90, 94, 90), 1, 0.2)
  end
  local function mfd(text, pos, anchor, size, col, align)
    local l = ui.label(disp, text, UDim2.fromOffset(150, (size or 16) + 4), pos, size or (MOB and 12 or 16), col or MFD, Enum.Font.Code, anchor or Vector2.new(0.5, 0.5), align)
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.55, RGB(0, 0, 0)
    l.ZIndex = 12
    return l
  end
  local TS = MOB and 12 or 16
  -- 上排、下排、左列的按键字
  TG.ag = mfd("A-G", UDim2.new(0.165, 0, 0, 22), nil, TS)
  TG.fov = mfd("NARO", UDim2.new(0.5, 0, 0, 22), nil, TS)
  TG.zoom = mfd("1.0x", UDim2.new(0.5, 0, 0, 22 + TS + 4), nil, TS)
  mfd("OVRD", UDim2.new(0.665, 0, 0, 22), nil, TS)
  mfd("CNTL", UDim2.new(0.83, 0, 0, 22), nil, TS)
  local eoMode = mfd("WHOT", UDim2.new(0.1, 0, 0.1, 0), nil, TS)
  mfd("SP", UDim2.new(0, 10, 0.33, 0), Vector2.new(0, 0.5), TS, nil, Enum.TextXAlignment.Left)
  mfd("CZ", UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5), TS, nil, Enum.TextXAlignment.Left)
  for i, tx in ipairs({ "SWAP", "HSD", "SMS", "TGP", "DCLT" }) do
    local l = mfd(tx, UDim2.new(({ 0.165, 0.33, 0.5, 0.665, 0.83 })[i], 0, 1, -18), nil, TS)
    if tx == "TGP" then   -- 现在这一页：框起来
      local b = ui.frame(disp, UDim2.fromOffset(TS * 3 + 10, TS + 10), UDim2.new(0.665, 0, 1, -18), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
      b.ZIndex = 12
      ui.stroke(b, MFD, 1, 0.15)
      l.Name = "TgpPage"
    end
  end
  -- 左下、右下的数
  TG.laser = mfd("L 1688", UDim2.new(0, 46, 1, -76), Vector2.new(0, 0.5), TS + 2, nil, Enum.TextXAlignment.Left)
  TG.rng = mfd("T --", UDim2.new(0, 46, 1, -50), Vector2.new(0, 0.5), TS + 2, nil, Enum.TextXAlignment.Left)
  TG.alt = mfd("", UDim2.new(1, -46, 1, -76), Vector2.new(1, 0.5), TS + 2, nil, Enum.TextXAlignment.Right)
  TG.tti = mfd("", UDim2.new(1, -46, 1, -50), Vector2.new(1, 0.5), TS + 4, nil, Enum.TextXAlignment.Right)
  -- 细十字：横竖贯穿，中间留空
  local GAP = MOB and 22 or 34
  for _, c in ipairs({ { UDim2.new(0, 1, 0.5, -GAP), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0) }, { UDim2.new(0, 1, 0.5, -GAP), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1) },
    { UDim2.new(0.5, -GAP, 0, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5) }, { UDim2.new(0.5, -GAP, 0, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5) } }) do
    local l = ui.frame(disp, c[1], c[2], MFD, 0.35, c[3])
    l.ZIndex = 11
  end
  -- 跟踪框（POINT）/ 区域跟踪的小框（AREA）、跟踪方式字
  TG.box = ui.frame(disp, UDim2.fromOffset(52, 52), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  TG.box.Name = "TrackBox"
  TG.box.ZIndex = 12
  TG.boxStroke = ui.stroke(TG.box, MFD, 1.5, 0)
  TG.track = mfd("AREA", UDim2.new(0.5, 0, 0.5, MOB and 70 or 112), nil, TS + 2)
  TG.track.Name = "TrackMode"
  -- 指北箭头
  TG.north = ui.label(disp, "➤", UDim2.fromOffset(30, 30), UDim2.new(0.9, 0, 0.11, 0), MOB and 18 or 26, MFD, Enum.Font.GothamBold, Vector2.new(0.5, 0.5))
  TG.north.ZIndex = 12
  TG.northN = mfd("N", UDim2.new(0.9, -22, 0.11, -18), nil, TS - 2)
  -- 右边一栏（显示器外面的黑边上）
  local side = ui.frame(disp, UDim2.fromOffset(MOB and 170 or 236, 300), UDim2.new(1, 18, 0, 0), RGB(0, 0, 0), 1)
  side.Name = "TgpSide"
  side.ZIndex = 12
  local function sl(text, y, size, col, font)
    local l = ui.label(side, text, UDim2.new(1, 0, 0, (size or 12) + 4), UDim2.fromOffset(0, y), size or 12, col or MFD, font or Enum.Font.Code, nil, Enum.TextXAlignment.Left)
    l.ZIndex = 12
    l.TextWrapped = true
    return l
  end
  TG.rel = sl("", 0, MOB and 10 or 11, MFD_DIM)
  ui.label(side, "TTI", UDim2.fromOffset(30, 14), UDim2.fromOffset(0, MOB and 36 or 52), MOB and 10 or 11, MFD_DIM, Enum.Font.Code, nil, Enum.TextXAlignment.Left).ZIndex = 12
  TG.ttiBig = ui.label(side, "-:--", UDim2.fromOffset(160, 34), UDim2.fromOffset(34, MOB and 22 or 34), MOB and 22 or 32, MFD, Enum.Font.Code, nil, Enum.TextXAlignment.Left)
  TG.ttiBig.ZIndex = 12
  local barBg = ui.frame(side, UDim2.new(0.86, 0, 0, 3), UDim2.fromOffset(0, MOB and 58 or 76), RGB(70, 72, 70), 0)
  barBg.ZIndex = 12
  TG.bar = ui.frame(barBg, UDim2.fromScale(0, 1), nil, MFD, 0)
  TG.bar.ZIndex = 13
  local y0 = MOB and 68 or 94
  TG.away = sl("", y0, MOB and 10 or 11, MFD)
  TG.arm = sl("", y0 + (MOB and 15 or 20), MOB and 10 or 11, RGB(236, 200, 120))
  TG.lst = sl("", y0 + (MOB and 30 or 40), MOB and 10 or 11, MFD)
  TG.say = sl("", y0 + (MOB and 50 or 70), MOB and 12 or 16, MFD, Enum.Font.Garamond)
  TG.say.Size = UDim2.new(1, 0, 0, MOB and 40 or 56)
  local eoHint = sl("", y0 + (MOB and 96 or 140), MOB and 9 or 10, MFD_DIM)
  eoHint.Size = UDim2.new(1, 0, 0, 90)
  eoHint.TextYAlignment = Enum.TextYAlignment.Top
  local eoInfo = TG.rng
  eoMode.Name, eoInfo.Name, eoHint.Name = "EoMode", "EoInfo", "EoHint"
  -- 光电的画面效果：电视（黑白、对比高一点）、热成像白热 / 黑热（所有实体高亮成白 / 黑）
  local eoCC = Instance.new("ColorCorrectionEffect")
  eoCC.Name = "EoCC"
  eoCC.Enabled = false
  eoCC.Parent = game:GetService("Lighting")
  local eoHl = Instance.new("Highlight")
  eoHl.Name = "EoHeat"
  eoHl.Enabled = false
  eoHl.FillTransparency, eoHl.OutlineTransparency = 0.08, 0.6
  eoHl.DepthMode = Enum.HighlightDepthMode.Occluded
  eoHl.Parent = cam
  local EO_MODES = { "tv", "whot", "bhot" }

  local HUDS = { bore, aimRing, spdBox, altBox, hdgBox, spdCap, altCap, thrText, vsText, warnText, fuelText, ring, ringText, wList, gText, aText, mText }
  for _, l in ipairs({ panel, bore, spdBox, altBox, hdgBox, spdCap, altCap, thrText, vsText, fuelText, ring, ringText, wList, gText, aText, mText, fpm }) do l.Parent = dcs end

  -- 降落引导：自己这边能落的地方（航母拦阻索区、攻方机场岛、主岛机场——据点 D 在自己手里时），返回 接地点、着陆方向
  local function landSites()
    local out = {}
    local team = me:GetAttribute("Side")
    local function pointMine(id)
      for _, p in ipairs((G.S and G.S.points) or {}) do if p.id == id then return p.owner == team end end
      return false
    end
    local function runway(A)
      for s = -1, 1, 2 do   -- 两头都能落：接地点在跑道头往里 60 格
        local td = V(A.x + s * (A.len / 2 - 60), (A.y or 0), A.z)
        table.insert(out, { p = V(td.X, AD.ground(Map, td.X, td.Z), td.Z), dir = V(-s, 0, 0) })
      end
    end
    if team == "atk" then
      local base = AD.carrierCF(Map)
      if base and st.d.carrier then
        local Wd = AD.WIRES
        local td = (base * CF(Wd.x, 0, (Wd.z0 + Wd.z1) / 2)).Position
        table.insert(out, { p = td, dir = base:VectorToWorldSpace(V(-math.sin(Wd.a), 0, -math.cos(Wd.a))), deck = true })
      end
      runway(Map.AFIELD2)
      if pointMine("D") then runway(Map.AIRFIELD) end
    elseif pointMine("D") then
      runway(Map.AIRFIELD)
    end
    return out
  end

  ---------------------------------------------------------------- 手机：杆、油门 / 升降、开火、换武器、热诱弹、起落架、下飞机

  local touch = nil
  local touchUI = nil
  if UIS.TouchEnabled then
    touch = { up = false, down = false, fire = false, flare = false }
    local lb = ui.frame(gui, UDim2.fromOffset(90, 170), UDim2.new(0, 20, 1, -320), RGB(0, 0, 0), 1)
    local rb = ui.frame(gui, UDim2.fromOffset(250, 230), UDim2.new(1, -260, 1, -340), RGB(0, 0, 0), 1)
    local function hold(parent, text, size, pos, key)
      local b = ui.button(parent, text, size, pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = true end end)
      b.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.Touch then touch[key] = false end end)
      return b
    end
    local function tap(parent, text, pos, f)
      local b = ui.button(parent, text, UDim2.fromOffset(60, 60), pos, RGB(30, 36, 42))
      b.BackgroundTransparency = 0.35
      b.TextSize = 14
      b.Activated:Connect(function() if st then f() end end)
      return b
    end
    hold(lb, "▲", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 0), "up")
    hold(lb, "▼", UDim2.fromOffset(80, 80), UDim2.fromOffset(5, 90), "down")
    hold(rb, "●", UDim2.fromOffset(96, 96), UDim2.fromOffset(150, 130), "fire")
    tap(rb, "1/2", UDim2.fromOffset(80, 150), function() G.flyNextWeapon() end)
    hold(rb, "X", UDim2.fromOffset(60, 60), UDim2.fromOffset(150, 60), "flare")   -- 热诱弹：按住连续放
    tap(rb, "G", UDim2.fromOffset(80, 80), function() if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end end)
    tap(rb, "R", UDim2.fromOffset(10, 150), function() G.flyNextTarget() end)
    tap(rb, "F", UDim2.fromOffset(10, 80), function() G.R.Drive:FireServer({ op = "exit" }) end)
    tap(rb, "J", UDim2.fromOffset(80, 10), function() G.R.Drive:FireServer({ op = "jettison" }) end)
    touchUI = { lb, rb }
    for _, f in ipairs(touchUI) do f.Visible = false end
  end

  ---------------------------------------------------------------- 武器栏、光电吊舱

  local function buildList()
    for _, r in ipairs(wRows) do r.f:Destroy() end
    wRows = {}
    if not st then return end
    local items = {}
    for i, wid in ipairs(st.wl) do items[#items + 1] = { key = tostring(i), wid = wid, w = AD.W[wid], idx = i } end
    items[#items + 1] = { key = "X", flare = true }
    local H = 34
    wList.Size = UDim2.fromOffset(260, #items * (H + 4))
    for i, it in ipairs(items) do
      local f = ui.frame(wList, UDim2.new(1, 0, 0, H), UDim2.fromOffset(0, (i - 1) * (H + 4)), RGB(0, 16, 6), 0.6)
      f.Name = "Row_" .. (it.wid or "flare")
      local sk = ui.stroke(f, HUD, 1, 0.7)
      local kb = ui.frame(f, UDim2.fromOffset(24, 24), UDim2.new(0, 6, 0.5, 0), RGB(0, 0, 0), 0.4, Vector2.new(0, 0.5))
      ui.stroke(kb, HUD, 1, 0.2)
      local kl = ui.label(kb, it.key, UDim2.fromScale(1, 1), nil, 15, HUD, Enum.Font.Code)
      kl.Name = "Key"
      local ic = ui.frame(f, UDim2.fromOffset(60, 20), UDim2.new(0, 38, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0, 0.5))
      ic.Name = "Icon"
      drawIcon(ic, it)
      local nm = ui.label(f, it.flare and T("air.flareName") or T("aw." .. it.wid), UDim2.new(1, -164, 1, 0), UDim2.fromOffset(104, 0), 14, HUD, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
      nm.TextWrapped = false
      nm.Name = "Name"
      local cnt = ui.label(f, "", UDim2.fromOffset(58, H), UDim2.new(1, -6, 0, 0), 17, HUD, Enum.Font.Code, Vector2.new(1, 0), Enum.TextXAlignment.Right)
      cnt.Name = "Count"
      wRows[i] = { f = f, s = sk, cnt = cnt, nm = nm, it = it }
    end
  end

  -- 自己的飞机：看光电时藏起来（吊舱在机腹，不然一低头就是自己的机翼）；热成像高亮所有实体时也不把自己涂白
  local ownAir = Instance.new("Model")
  ownAir.Name = "OwnAir"
  ownAir.Parent = workspace
  local function ownHide(on)
    local v = st and G.views and G.views[st.em]
    if not v or not v.M then return end
    for _, p in ipairs(v.M.plist or {}) do
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 1 or 0 end
    end
    if on and v.model and v.model.Parent == G.viewFolder then v.model.Parent = ownAir
    elseif not on and v.model and v.model.Parent == ownAir and G.viewFolder then v.model.Parent = G.viewFolder end
  end
  local function eoApply()
    local on = st ~= nil and st.eo == true
    eoGui.Visible = on
    if st then   -- 吊舱页面盖满屏幕：平显的速度、高度、航向框、武器栏、下面的信息栏收起来，出来再放回去
      for _, l in ipairs(HUDS) do if l ~= warnText then l.Visible = st.pilot == true and not on end end
      panel.Visible = not on
    end
    local m = on and EO_MODES[st.eoMode or 1] or nil
    eoCC.Enabled = on
    eoHl.Enabled = on and m ~= "tv"
    if on then
      if m == "tv" then
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.25, 0.02, Color3.new(1, 1, 1)
      elseif m == "whot" then
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.45, -0.3, RGB(225, 225, 225)
        eoHl.FillColor, eoHl.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
      else
        eoCC.Saturation, eoCC.Contrast, eoCC.Brightness, eoCC.TintColor = -1, 0.25, 0.22, RGB(235, 235, 235)
        eoHl.FillColor, eoHl.OutlineColor = Color3.new(0, 0, 0), Color3.new(0, 0, 0)
      end
      eoHl.Adornee = G.viewFolder
    end
  end
  -- P：进出光电吊舱（用户：飞机驾驶按 P 也要能切换光电视角）。鼠标只转吊舱（稳定在世界方向上），飞机自己保持平飞（固定翼按住进吊舱时的航向、
  --   航迹拉平；直升机机头不跟着转、不低头）；Z / 滚轮变焦，V 电视 / 白热 / 黑热；画面里的瞄准点就是吊舱看着的地方（对地弹、机头炮塔都朝那里）
  local function setEO(on)
    if not st then return end
    if st.uav then st.dcam = (st.dcam == "nose") and "chase" or "nose" return end   -- 无人机本来就有前视光电：P 跟 V 一样切
    on = on and st.pilot and not st.crashed
    if on == (st.eo == true) then return end
    st.eo = on
    if on then
      local look = cam.CFrame.LookVector
      st.eoYaw = math.atan2(-look.X, -look.Z)
      st.eoPitch = clamp(math.asin(clamp(look.Y, -1, 1)) - 0.15, -1.5, 0.35)
      st.eoMode = st.eoMode or 1
      st.zoom = 1
      if st.d.kind == "jet" then   -- 自动驾驶：按现在的航向平飞
        local v = (st.vel.Magnitude > 1) and st.vel.Unit or st.cf.LookVector
        st.aimYaw = math.atan2(-v.X, -v.Z)
        st.aimPitch = clamp(math.asin(clamp(v.Y, -1, 1)), -0.06, 0.12)
      else   -- 直升机：镜头回到略往下看，机头不跟吊舱转
        st.camPitch, st.camYaw = -0.12, st.yaw
      end
    else
      st.zoom = 1
    end
    ownHide(on)
    eoApply()
    if G.playSound then G.playSound("quiet", nil, on and 1.5 or 1.2) end
  end
  G.flyEO = setEO

  ---------------------------------------------------------------- 开始 / 结束

  local function findEnt(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do
      if em:GetAttribute("EntId") == id then return em end
    end
    return nil
  end

  local heliCamParams = RaycastParams.new()   -- 直升机的弹簧臂别钻进山坡、房子（地形也算）
  heliCamParams.FilterType = Enum.RaycastFilterType.Include
  local mapParams = RaycastParams.new()
  mapParams.FilterType = Enum.RaycastFilterType.Include
  local aimParams = RaycastParams.new()
  aimParams.FilterType = Enum.RaycastFilterType.Exclude

  local controls = nil
  task.spawn(function()
    local ok, res = pcall(function()
      local pm = require(me:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
      return pm:GetControls()
    end)
    if ok then controls = res end
  end)

  -- 接地（用户 11-20：载具照 UE5 的水平升级）：按下沉率——镜头一震、固定翼主轮一声吱（轮胎冒一小团烟）、直升机滑橇一声闷响
  local Debris = game:GetService("Debris")
  local function touchdown(sink, wheels)
    if not st or sink < 3 then return end
    local k = math.clamp((sink - 3) / 25, 0, 1)
    if G.shake then G.shake(0.05 + 0.35 * k) end
    if G.sfx then G.sfx(wheels and "touchdown" or "skidLand", nil, { vol = 0.5 + 0.7 * k }) end
    st.tdK, st.tdN = k, (st.tdN or 0) + 1   -- 测试用
    if wheels then
      local p = st.cf.Position
      local part = Instance.new("Part")
      part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.Transparency = true, false, false, false, 1
      part.Size = Vector3.new(1, 1, 1)
      part.CFrame = CF(p.X, ground(p.X, p.Z) + 0.4, p.Z)
      part.Parent = workspace
      local pe = Instance.new("ParticleEmitter")
      pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
      pe.Rate = 0
      pe.Lifetime = NumberRange.new(0.8, 1.6)
      pe.Speed = NumberRange.new(2, 6)
      pe.SpreadAngle = Vector2.new(60, 60)
      pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 7) })
      pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
      pe.Color = ColorSequence.new(Color3.fromRGB(214, 214, 210))
      pe.Parent = part
      pcall(function() pe:Emit(math.floor(6 + 14 * k)) end)
      Debris:AddItem(part, 3)
    end
  end

  local function begin(vs)
    local em = findEnt(vs.id)
    if not em then return end
    local d = AD.get(vs.m)
    if not d then return end
    local cf = em.Root.CFrame
    local look = cf.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local onGround = vs.ground == true
    st = { id = vs.id, em = em, d = d, pilot = vs.pilot == true, cf = cf, vel = V(), spd = 0, sink = 0, pr = 0, rr = 0, yr = 0,
      thr = onGround and 0 or 85, ground = onGround, gearWant = onGround and 1 or 0, gear = onGround and 1 or 0, rpm = (d.kind == "heli" and not onGround) and 100 or 0,
      yaw = yaw, hv = V(), vy = 0, tiltP = 0, tiltR = 0, camYaw = yaw, camPitch = -0.15, aimYaw = yaw, aimPitch = 0, c = {},
      load = vs.load or {}, wl = AD.groups(d, vs.load or {}), wi = 1, firing = false, trig = false, sendT = 0, lock = nil, lockT = 0, nextFire = 0,
      ty = 0, gp = 0, lastHv = V(), crashed = false, bay = 0, bayS = 0 }
    for i, wid in ipairs(st.wl) do   -- 默认选中第一种挂载（机炮一直在鼠标左键上）
      local w = AD.W[wid]
      if w and w.kind ~= "gun" then st.wi = i break end
    end
    if not onGround then   -- 空中出发：带着速度
      if d.kind == "jet" then st.spd = d.vMil * 0.8 else st.hv = look * d.vMax * 0.6 end
      st.vel = look * ((d.kind == "jet") and st.spd or d.vMax * 0.6)
    end
    -- 遥控无人机（服务器 vs.uav）：人在地上端着战术平板，画面是平板（Tablet.lua）；默认前视光电，右键 / V 换外部视角，Z 变焦
    st.uav = vs.uav == true and d.drone == true
    st.dcam, st.zoom, st.zoomS = st.uav and "nose" or nil, 1, 1
    G.fly, G.drive = st, st   -- G.drive：步兵的操作（Play）先停下
    -- 直升机按住 E 爬升：身边的「按 E」提示（上车、召唤位终端）先关掉，免得误触
    pcall(function() game:GetService("ProximityPromptService").Enabled = false end)
    cam.CameraType = Enum.CameraType.Scriptable
    panel.Visible = true
    -- 平板模式：面板挪进平板屏幕里（底边外壳上不放东西）
    local rect = G.tabletRect
    panel.Position = (st.uav and rect) and UDim2.new(0.5, 0, rect[4], -12) or UDim2.new(0.5, 0, 1, -24)
    if st.uav and G.tabletOpen then G.tabletOpen(st) end
    for _, l in ipairs(HUDS) do l.Visible = st.pilot end
    dcs.Visible = st.uav == true   -- 无人机：原来那一套；有人开的飞机：AirHud（每帧 G.airHudStep）
    buildList()
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = st.pilot end end
    local m = workspace:FindFirstChild("Map")
    mapParams.FilterDescendantsInstances = m and { m } or {}
    heliCamParams.FilterDescendantsInstances = m and { workspace.Terrain, m } or { workspace.Terrain }
    -- 抖振的嗡嗡声（固定翼）：音量在镜头那里按抖得多厉害调
    if d.kind == "jet" and G.makeSound then
      st.buffetSnd = G.makeSound({ id = "rbxasset://sounds/impact_explosion_03.mp3", vol = 1, s = { 0.34, 0.34 }, loop = { 0.06, 0.5 }, eq = { 10, -4, -18 } },
        game:GetService("SoundService"), {})
      if st.buffetSnd then st.buffetSnd.Volume = 0 end
    end
    -- 发动机声（用户 11-21：声音要真，SoundLib 的真录音；没载上就没有这一层）：固定翼喷气发动机、直升机休伊的旋翼，坐后面的也听得到
    if G.realLoop then st.engSnd = G.realLoop((d.kind == "jet") and "jetEngine" or "heliRotor", game:GetService("SoundService")) end
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    pcall(function() game:GetService("ProximityPromptService").Enabled = true end)
    if st and st.trig then G.R.Drive:FireServer({ op = "trig", on = false }) end
    if G.gunLoop then G.gunLoop("me", nil, nil, false) end
    if st and st.eo then
      ownHide(false)
      st.eo = false
    end
    eoGui.Visible, eoCC.Enabled, eoHl.Enabled = false, false, false
    local old = st
    st = nil
    G.fly = nil
    G.hitMarkerAt = nil
    if G.drive == old then G.drive = nil end
    cam.CameraType = Enum.CameraType.Custom
    cam.FieldOfView = 70
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then UIS.MouseBehavior = Enum.MouseBehavior.Default end
    panel.Visible = false
    for _, l in ipairs(HUDS) do l.Visible = false end
    dcs.Visible = false
    if G.airHudOff then G.airHudOff() end
    lockBox.Visible, lockText.Visible, pipper.Visible = false, false, false
    landMark.Visible, landText.Visible, restText.Visible = false, false, false
    if touchUI then for _, f in ipairs(touchUI) do f.Visible = false end end
    panel.Position = UDim2.new(0.5, 0, 1, -24)
    if old and old.uav and G.tabletClose then G.tabletClose() end
    if old and old.buffetSnd then old.buffetSnd:Destroy() end
    if old and old.engSnd then old.engSnd:Destroy() end
    if G.vehCamReset then G.vehCamReset("heli") end
  end

  ---------------------------------------------------------------- 武器

  local function curW()
    local wid = st.wl[st.wi]
    return wid, wid and AD.W[wid]
  end
  -- 鼠标左键打的机炮（没有炮就是 nil）；F 打的挂载（选中的那种，选的是炮就用第一种挂载）——用户：F 控制导弹，鼠标控制机枪
  local function gunW()
    for _, wid in ipairs(st.wl) do
      local w = AD.W[wid]
      if w and w.kind == "gun" then return wid, w end
    end
    return nil
  end
  local function storeW()
    local wid, w = curW()
    if w and w.kind ~= "gun" then return wid, w end
    for _, wid2 in ipairs(st.wl) do
      local w2 = AD.W[wid2]
      if w2 and w2.kind ~= "gun" then return wid2, w2 end
    end
    return nil
  end
  -- 这种弹还剩几枚（S.veh.stores 是服务器的数，开火时本地先扣）
  local function left(wid)
    local w = AD.W[wid]
    if not w then return 0 end
    if w.kind == "gun" then return st.gunAmmo or 0 end
    local n = 0
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid then n += (st.stores and st.stores[i]) or 0 end
    end
    return n
  end
  function G.flyNextWeapon()
    if not st or #st.wl == 0 then return end
    st.wi = st.wi % #st.wl + 1
    st.lock, st.lockT = nil, 0
  end
  -- 弹舱：选中的弹在哪个舱里，那个舱门就开着
  local function bayOf(wid)
    local main, side = false, false
    for i, s in ipairs(st.d.st or {}) do
      if st.load[i] == wid and s.bay then
        if s.bay == "main" then main = true else side = true end
      end
    end
    return main, side
  end

  -- 能锁的目标：敌方实体（空空弹打飞机，空地弹 / 炸弹打地面、海上的）
  local GROUND_KINDS = { veh = true, bot = true, fort = true, lcm = true, lcac = true, ship = true }
  local function candidates(w)
    local out = {}
    local f = workspace:FindFirstChild("Ents")
    if not f or not st then return out end
    local myTeam = me:GetAttribute("Side")
    local p0 = st.cf.Position
    for _, em in ipairs(f:GetChildren()) do
      local kind = em:GetAttribute("Kind")
      local root = em:FindFirstChild("Root")
      if root and em ~= st.em and em:GetAttribute("Team") ~= myTeam and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        local ok = (w.kind == "aam") and kind == "air" or ((w.kind == "agm" or w.kind == "bomb") and GROUND_KINDS[kind])
        if ok then
          local to = root.CFrame.Position - p0
          local dist = to.Magnitude
          if dist < (w.range or 3200) and dist > 30 then table.insert(out, { em = em, id = em:GetAttribute("EntId"), dir = to.Unit, dist = dist, pos = root.CFrame.Position }) end
        end
      end
    end
    return out
  end
  -- 导引头视场：导弹看机头前方 cone 度；炸弹看飞机下前方（俯冲投弹也行）
  local function inCone(w, c)
    local fwd = st.cf.LookVector
    if w.kind == "bomb" then
      local down = (fwd * 0.6 + V(0, -1, 0)).Unit
      return down:Dot(c.dir) > math.cos(rad(w.cone or 60))
    end
    local cone = w.cone or 30
    if st.d.kind == "heli" and w.kind == "agm" then cone += 20 end
    return fwd:Dot(c.dir) > math.cos(rad(cone))
  end
  -- 出了导弹的离轴角还能跟多宽（用户 11-19：脱离导弹发射角度锁定的菱形变黄——锁还留着、这时不能发射；再偏更多或者偏太久才丢）
  local function inTrack(w, c)
    local fwd = st.cf.LookVector
    if w.kind == "bomb" then
      local down = (fwd * 0.6 + V(0, -1, 0)).Unit
      return down:Dot(c.dir) > math.cos(rad(math.min((w.cone or 60) * 1.5, 89)))
    end
    local cone = w.cone or 30
    if st.d.kind == "heli" and w.kind == "agm" then cone += 20 end
    return fwd:Dot(c.dir) > math.cos(rad(math.min(cone * 2.2, 85)))
  end
  -- 机炮黏住目标（用户 11-21：机炮也能像 MWT 那样黏在载具上）：机头前方 6° 以内、炮的射程里的敌方载具（车、船、飞机、工事、登陆艇），
  --   挑离机头最近的（远的稍微吃亏）；黏住以后偏到 9° 才松开（不来回跳）。瞄准点放在提前量上：目标的位置 + 相对速度 × 炮弹飞过去的时间
  --   （炮弹带着自己飞机的速度出膛，所以用相对速度）+ 下坠；服务器的固定机炮最多偏 12° 朝这一点打（Air.lua 的 gunDir）
  local STICK_IN, STICK_OUT = math.cos(rad(6)), math.cos(rad(9))
  local STICK_KINDS = { veh = true, fort = true, lcm = true, lcac = true, ship = true, air = true }
  local function gunStick()
    local gw = nil   -- 这架飞机的炮：挂载表里的炮（固定翼），没有就看机型的 gun（歼-20 没有内置机炮，不黏）
    for _, wid in ipairs(st.wl or {}) do
      local w = AD.W[wid]
      if w and w.kind == "gun" then gw = w break end
    end
    gw = gw or AD.W[st.d.gun or ""]
    local f = workspace:FindFirstChild("Ents")
    if not gw or not f then return nil end
    local myTeam = me:GetAttribute("Side")
    local p0, fwd = st.cf.Position, st.cf.LookVector
    local keep = st.stick and st.stick.em
    local best, bestS = nil, math.huge
    for _, em in ipairs(f:GetChildren()) do
      local root = em:FindFirstChild("Root")
      if root and em ~= st.em and STICK_KINDS[em:GetAttribute("Kind") or ""] and em:GetAttribute("Team") ~= myTeam
        and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        local p = root.CFrame.Position
        local to = p - p0
        local dist = to.Magnitude
        if dist > 40 and dist < gw.range then
          local c = fwd:Dot(to / dist)
          if c > ((em == keep) and STICK_OUT or STICK_IN) then
            local sc = (1 - c) * 1000 + dist / gw.range - ((em == keep) and 2 or 0)
            if sc < bestS then best, bestS = { em = em, p = p, dist = dist }, sc end
          end
        end
      end
    end
    if not best then st.stickV = nil return nil end
    -- 目标的速度：两帧位置差，平滑一下
    local now = os.clock()
    local sv = st.stickV
    local vT = V()
    if sv and sv.em == best.em and now > sv.t + 1e-3 then
      local raw = (best.p - sv.p) / (now - sv.t)
      vT = (raw.Magnitude < 1500) and (sv.v or raw):Lerp(raw, 0.3) or (sv.v or V())
    elseif sv and sv.em == best.em then
      vT = sv.v or V()
    end
    st.stickV = { em = best.em, p = best.p, t = now, v = vT }
    local vr = vT - (st.vel or V())
    local t = best.dist / gw.speed
    local lead = best.p
    for _ = 1, 2 do
      lead = best.p + vr * t
      t = (lead - p0).Magnitude / gw.speed
    end
    best.lead = lead + V(0, 0.5 * workspace.Gravity * 0.08 * t * t, 0)   -- 炮弹的下坠（服务器的 gscale 0.08）
    return best
  end
  -- 鼠标瞄准方向（用户：准星也要能控制飞行方向，WASD 也不要动）：固定翼的鼠标想去的方向；光电吊舱、飞出作战区时自动驾驶也用它
  local function autoDir() return (CFrame.Angles(0, st.aimYaw, 0) * CFrame.Angles(st.aimPitch, 0, 0)).LookVector end
  -- 镜头跟着机身（用户 11-21：飞机的飞行方向标志动来动去，应该固定位置）：原来镜头顺着鼠标瞄准方向看（战雷那样），
  --   机头前方的全息标记跟着机头在画面里到处跑；现在镜头钉在机身后上方、顺着机头看——标记一直在屏幕正中，
  --   鼠标推的是准星圈（想去的方向），飞机转过去、圈子回到标记上。镜头的上方：地平线跟着坡度歪三成；
  --   大坡度、倒飞、快竖直时慢慢变成整个跟着机身（不然翻筋斗过顶那一下画面整个翻过来）
  local function jetCamBasis()
    local cf = st.cf
    local fwd = cf.LookVector
    local kw = st.camUpK or 0.7
    local upC = V(0, 1, 0) * kw + cf.UpVector * (1 - kw)
    local rt = fwd:Cross(upC)
    if rt.Magnitude < 1e-3 then rt = cf.RightVector end
    rt = rt.Unit
    return fwd, rt:Cross(fwd).Unit, rt
  end
  -- 准星圈只能在机头前方一个椭圆里（左右 32°、上下 22°，屏幕上一直看得见）：推到边上就是一直往那边满舵转，松开飞机转过去、圈子回到标记上
  local AIM_X, AIM_Y = rad(32), rad(22)
  local function clampAim(a)
    local fwd, up, rt = jetCamBasis()
    local x, y, z = a:Dot(rt), a:Dot(up), a:Dot(fwd)
    local ax, ay
    if z > 0.05 then
      ax, ay = math.atan2(x, z), math.atan2(y, z)
      local e = (ax / AIM_X) ^ 2 + (ay / AIM_Y) ^ 2
      if e <= 1 then return a end
      ax, ay = ax / math.sqrt(e), ay / math.sqrt(e)
    else   -- 跑到身后去了：落到椭圆边上同一个方向
      local ph = (math.abs(x) + math.abs(y) > 1e-4) and math.atan2(y, x) or math.pi / 2
      ax, ay = AIM_X * math.cos(ph), AIM_Y * math.sin(ph)
    end
    return (fwd + rt * math.tan(ax) + up * math.tan(ay)).Unit
  end
  local function setAim(a)
    st.aimYaw, st.aimPitch = math.atan2(-a.X, -a.Z), math.asin(clamp(a.Y, -1, 1))
  end
  -- 准星圈画在哪：鼠标给的方向（飞控让航迹对准它）往机身上方抬一个平飞迎角——平飞时机头就比航迹高这么多，
  --   圈子正好压在机头的全息标记上（不然一直在标记下面一点，看着像飞机没往标记那里飞）
  local function aimRingDir()
    local a = autoDir()
    if st.d.kind ~= "jet" or st.ground then return a end
    local trim = math.min(rad(6), (st.d.stall / math.max(st.spd, st.d.stall)) ^ 2 * rad(st.d.aoaMax or 24))
    local u = st.cf.UpVector - a * a:Dot(st.cf.UpVector)
    if u.Magnitude < 1e-3 then return a end
    return (a * math.cos(trim) + u.Unit * math.sin(trim)).Unit
  end
  G.flyAimRingDir = function() return st and aimRingDir() end   -- 测试用
  -- 瞄准 / 挑目标的方向：固定翼是鼠标瞄准方向（手机上是机头），直升机是镜头（鼠标瞄机头炮塔）
  local function aimDirNow()
    if st.d.kind == "jet" then return (G.mobile or not st.uav) and st.cf.LookVector or autoDir() end   -- 有人开的固定翼：机头（WASD 飞，没有准心）
    return cam.CFrame.LookVector
  end
  -- 光电吊舱看着的方向（世界方向，鼠标转）；瞄准、挑目标用的方向：开着光电就是吊舱，不然是鼠标瞄准方向
  local function eoDir() return (CFrame.Angles(0, st.eoYaw or 0, 0) * CFrame.Angles(st.eoPitch or 0, 0, 0)).LookVector end
  local function lookDir() return st.eo and eoDir() or aimDirNow() end
  local function pickTarget(w, skip)
    local best, bs = nil, math.huge
    local want = lookDir()
    for _, c in ipairs(candidates(w)) do
      if inCone(w, c) and c.id ~= skip then
        local s = 1 - want:Dot(c.dir) + c.dist / 20000
        if s < bs then best, bs = c, s end
      end
    end
    return best
  end
  function G.flyNextTarget()
    if not st then return end
    local _, w = storeW()
    if not w or w.kind == "gun" or w.kind == "rkt" then return end
    local c = pickTarget(w, st.lock and st.lock.id)
    st.lock, st.lockT = c, 0
  end

  local function setTrig(on)
    -- 航炮声：按住扳机就一直响（循环一小段起爆声，一圈一发），打光了就停
    local loud = on and (st.gunAmmo or 0) > 0 and (not G.S or G.S.phase == "battle")
    if G.gunLoop and loud ~= (st.gunSnd == true) then
      st.gunSnd = loud
      G.gunLoop("me", st.d.gun, nil, loud)
    end
    if st.trig == on then return end
    st.trig = on
    G.R.Drive:FireServer({ op = "trig", on = on, aim = st.aimPt, stk = st.stick ~= nil })
  end

  local function fireStore(wid, w)
    local t = os.clock()
    if t < st.nextFire or left(wid) <= 0 then return end
    if G.S and G.S.phase ~= "battle" then G.toast(T("air.notYet"), "info") return end
    local locked = st.lock and st.lockT >= (w.lockTime or 1)
    if locked and st.lock.out and w.kind ~= "rkt" then G.toast(T("air.outCone"), "info") return end   -- 出了发射角度：锁着也不能打（菱形是黄的）
    if w.kind == "aam" and not locked then G.toast(T("air.needLock"), "info") return end
    st.nextFire = t + ((w.kind == "rkt") and (w.rate or 0.12) or 0.4)
    G.R.Drive:FireServer({ op = "fire", w = wid, tgt = locked and st.lock.id or nil, aim = st.aimPt })
    for i in ipairs(st.d.st or {}) do   -- 本地先扣一枚（服务器的数随后推过来）
      if st.load[i] == wid and (st.stores[i] or 0) > 0 then
        st.stores[i] -= 1
        break
      end
    end
    -- 开火声按武器（Fx.lua 的 G.sfx）：导弹低沉的点火 + 呼啸、火箭弹「噗」一声 + 呼的一下、炸弹挂架弹开「咣」一声
    if G.sfx then G.sfx((w.kind == "rkt") and "rkt" or ((w.kind == "bomb") and "bombRel" or "msl"), nil, { vol = (w.kind == "rkt") and 0.7 or 0.8 }) end
  end

  ---------------------------------------------------------------- 物理：固定翼

  local function key(k) return UIS:IsKeyDown(k) end
  local function crash()
    if st.crashed then return end
    st.crashed = true
    G.R.Drive:FireServer({ op = "crash", hit = true })
    if G.shake then G.shake(1) end
  end

  local function jetPhysics(dt)
    local d = st.d
    local ROLL, PITCH, GMAX = rad(d.roll) * AGIL.roll, rad(d.pitch) * AGIL.pitch, d.g * AGIL.g
    -- 用户 11-21：飞机改成 WASD 控制方向、不要准心控制（原来 11-18 是鼠标给方向的纯准心控制、W / S 油门）——
    --   有人开的固定翼键盘就是驾驶杆：W 低头、S 抬头（跟摇杆一样往前推是低头）、A / D 滚转、Q / E 方向舵；油门挪到 Shift 加、Ctrl 收（↑ / ↓ 也行），
    --   地上油门收到底按住 Ctrl 倒退。键是开关量：杆量 0.3 秒推满、松开 0.2 秒回中，不会一按就猛地一转。
    --   无人机（平板上飞）照旧鼠标给方向、W / S 油门；开着光电吊舱、飞出作战区自动掉头时照旧按给的方向自动飞（下面的教官）
    local kb = not st.uav and not G.mobile
    local up, dn
    if kb then
      up = key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift) or key(Enum.KeyCode.Up) or (touch and touch.up)
      dn = key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.RightControl) or key(Enum.KeyCode.Down) or (touch and touch.down)
    else
      up = key(Enum.KeyCode.W) or key(Enum.KeyCode.Up) or key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift) or (touch and touch.up)
      dn = key(Enum.KeyCode.S) or key(Enum.KeyCode.Down) or key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.RightControl) or (touch and touch.down)
    end
    st.thr = clamp(st.thr + ((up and 1 or 0) - (dn and 1 or 0)) * 55 * dt, 0, d.ab and 130 or 100)
    -- 自动收油门（真飞机拉平时自动油门收到慢车）：接地太快贴着跑道飘的时候不按 W 就自己往回收（按住 W 是复飞）
    if not up and os.clock() - (st.floatT or -9) < 0.3 then st.thr = math.max(0, st.thr - 55 * dt) end
    if st.out then st.thr = 0 end   -- 油烧干了：发动机熄火，只能滑翔
    local rev = st.ground and not st.cat and not st.trap and dn and st.thr <= 0.5   -- 地上油门收到底还按着 Ctrl（无人机：S）：倒退（推出来、调头）
    local rollIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn, pitchIn = 0, 0   -- 无人机：键盘不管俯仰、方向舵（鼠标给方向）；手机上摇杆当驾驶杆
    if kb then
      local function ramp(cur, want)   -- 推上去 0.3 秒到头、松开 0.2 秒回中，反着按先回中再推
        local rate = (want ~= 0 and (cur == 0 or (cur > 0) == (want > 0))) and (1 / 0.3) or (1 / 0.2)
        return approach(cur, want, rate * dt)
      end
      st.kP = ramp(st.kP or 0, (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0))
      st.kR = ramp(st.kR or 0, rollIn)
      st.kY = ramp(st.kY or 0, (key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0))
      pitchIn, rollIn, yawIn = st.kP, st.kR, st.kY
    end
    if G.mobile and controls then   -- 手机：摇杆直接当驾驶杆（往前推是低头）
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.X) > 0.1 then rollIn = mv.X end
        if math.abs(mv.Z) > 0.1 then pitchIn = mv.Z end
      end
    end
    local cf = st.cf
    local fwd, upV, right = cf.LookVector, cf.UpVector, cf.RightVector
    -- 降落辅助（用户：把降落做好）：起落架放着、离地不到 45 格、底下是跑道 / 甲板 / 能落的地方——
    --   不按 A / D 就自动摆平机翼，贴近时把下沉率收到能落的范围（真飞机的拉平），见下面天上那段
    local landAid = nil
    if st.gear and st.gear > 0.9 and not st.ground then
      local p0 = cf.Position
      local gH = ground(p0.X, p0.Z)
      local agl = p0.Y - d.gearH - gH
      if agl < 45 and (gH > 0.4 or AD.onDeck(Map, p0.X, p0.Z) ~= nil) then landAid = math.max(agl, 0) end
    end
    st.landAid = landAid
    -- 速度：油门给目标速度（加力到 vAB），往目标加减速；爬升掉速、俯冲加速、拉杆转弯掉能量；地上没油门时滚着慢下来
    -- 重量感（用户：飞机驾驶没有重量感）：W 越大越「沉」——F-22、歼-20 约 1，A-10 约 2，轰-6K、B-2、MQ-9 是 3
    local W = math.clamp(220 / math.max(d.roll or 200, 1), 1, 3)
    -- 发动机有迟滞：推力跟着油门慢慢起来（加力点着要一下）
    st.thrE = approach(st.thrE or st.thr, st.thr, (st.thr > (st.thrE or 0) and 38 or 55) / W * dt)
    local thr = st.thrE
    local tgt = (thr <= 100) and d.vMil * thr / 100 or (d.vMil + (d.vMax - d.vMil) * (thr - 100) / 30)
    local acc = (thr > 100) and (d.accel + (d.abAccel or 0)) or d.accel
    -- 副油箱的阻力：最大速度、加速度都少几成；油多就重：加速慢（满内油 + 两个副油箱比一半内油重三成多）
    tgt *= 1 - (st.drag or 0)
    acc *= (1 - (st.drag or 0)) / (st.heavy or 1)
    if rev then tgt = -12 end   -- 倒退：慢慢往后滑（约 4 米 / 秒）
    -- 进近自动油门（真飞机的速度保护 / 迎角地板）：起落架放着在天上，速度不掉到 1.2 倍失速以下——
    --   油门收太多也不至于失速、掉在跑道前面的海里（收起落架就没有这个保护）
    local apc = st.gear > 0.9 and not st.ground and not st.out and tgt < d.stall * 1.2
    if apc then tgt = d.stall * 1.2 end
    st.apc = apc
    -- 地上滑跑：推力要先克服整架飞机的重量和轮子的阻力，加速度只有天上的四分之一（战斗机滑跑两三百米、轰炸机五百米上下，
    --   一推油门不再四五十米就飞起来；弹射器单独算）
    if st.ground and not st.cat then acc *= 0.25 end
    if st.trap then   -- 挂着拦阻索：发动机推力不算，地上那段按拦阻索减速
    -- 地上减速：B 刹车 70；油门收到底自动刹车 36（落地滑跑五六秒停住，不用一直按 B）；带着点油门滑行只有轮子阻力 22
    elseif tgt > st.spd then st.spd += math.min(tgt - st.spd, acc * dt)
    else st.spd -= math.min(st.spd - tgt, (st.ground and ((key(Enum.KeyCode.B) and 70) or (st.thr < 5 and 36) or 22) or acc * 0.45) * dt) end
    if not st.ground then
      local vd = st.vdir or fwd
      st.spd -= GR * vd.Y * 0.9 * dt   -- 沿航迹爬升掉速、俯冲加速（拉杆掉的能量在下面按过载算：诱导阻力）
    end
    if st.trig and (st.gunAmmo or 0) > 0 then st.spd -= 5 * dt end   -- 航炮的后坐：开火时掉一点速度（30 毫米炮的后坐力有几吨）
    st.spd = clamp(st.spd, (st.ground and not st.cat) and -12 or 0, d.vMax * 1.3)
    local q = clamp((st.spd - d.stall * 0.4) / d.stall, 0.12, 1)   -- 舵效：慢了舵不灵
    -- 想怎么转（用户 11-18：方向只听鼠标准心，A / D 滚转不把准心拽回）：纯准心控制——像《战争雷霆》的教官，鼠标给想去的方向，
    --   自动压坡度让准心落到升力方向上、按偏差要过载（拉杆）转过去；按着 A / D 时滚转听键盘，俯仰照旧往准心拉
    --   飞机本身按升力物理飞（用户：操作感像玩具）：教官给的是「要几个 g」，飞控找迎角、升力带着航迹转，机头先抬、航迹慢半拍，拉得狠掉速；
    --   手机上摇杆当驾驶杆：往后拉要过载、松杆 1 g，坡度 33° 以内补一点杆保高度
    local bank = math.asin(clamp(right.Y, -1, 1))
    local upright = upV.Y > 0.3   -- 没倒飞、没在翻筋斗
    local nCmd, rc, yc
    if G.mobile or (kb and not st.eo and not st.oob) then
      -- 驾驶杆（键盘 / 手机摇杆）：往后拉要过载、松杆 1 g，坡度 33° 以内补一点杆保高度；没压 A / D、坡度 20° 以内机翼慢慢自己摆平
      local pull = -pitchIn   -- 往后拉为正
      nCmd = (pull >= 0) and (1 + pull * (GMAX - 1)) or (1 + pull * 3)   -- 推杆到 −2 g
      if math.abs(pitchIn) < 0.05 and upright and not st.ground then
        local phi = math.min(math.abs(bank), rad(75))
        nCmd = 1 + (1 / math.cos(phi) - 1) * (1 - Map.smooth(rad(33), rad(60), phi))
      end
      rc, yc = rollIn * ROLL, yawIn * rad(d.yaw) * 0.6
      if rollIn == 0 and upright and not st.ground and math.abs(bank) < rad(20) then rc = clamp(bank * 2.5, -1, 1) * ROLL * 0.3 end
      if landAid and rollIn == 0 then rc = clamp(bank * 2.5, -1, 1) * ROLL end   -- 贴着跑道 / 甲板：机翼自动摆平
      if kb then setAim((not st.ground and st.vdir) or fwd) end   -- 鼠标瞄准方向跟着航迹（开光电吊舱、自动掉头时从现在的航向接着飞）
    else
      local aim = autoDir()
      local l = cf:VectorToObjectSpace(aim)
      local fz = -l.Z
      local off = math.acos(clamp(fz, -1, 1))
      local w = Map.smooth(rad(2), rad(10), off)
      local toTarget = math.atan2(l.X, l.Y)   -- 让目标落到机头正上方（升力方向）要滚多少
      if fz < -0.2 and math.abs(l.X) < 0.15 then toTarget = 0 end   -- 目标在正后方偏一点点：先拉起来（筋斗），别来回滚
      local level = clamp(bank * 2.5, -1, 1)   -- 摆平机翼的滚转（bank 右翼抬起为正，rc 为正往右滚）
      local vd0 = st.vdir or cf.LookVector
      -- 准心相对航迹偏左 / 右多少（世界坐标里水平量，右为正）
      local vdH = V(vd0.X, 0, vd0.Z)
      local aimH = V(aim.X, 0, aim.Z)
      local psi = 0
      if vdH.Magnitude > 1e-3 and aimH.Magnitude > 1e-3 then
        vdH, aimH = vdH.Unit, aimH.Unit
        psi = math.atan2(aimH:Dot(V(-vdH.Z, 0, vdH.X)), aimH:Dot(vdH))
      end
      -- 降落辅助：离地 30 格以内拉平——航迹最陡只到下沉 6～14 格 / 秒（越低越平），准心压得再低也不往跑道上扎
      --   （原来下面只把航迹托平、机头照样压向准心，接地时机头朝下二十度判摔）：把要去的方向抬到这个下滑角
      --   准心不在前方 45° 以内（飞过了瞄的那一点、准心落到身后）就顺着现在的航向拉平，不往回拽
      local aimL = aim
      local flare = landAid and landAid < 30 and vdH.Magnitude > 0.5
      if flare then
        local gMin = -math.asin(clamp((6 + 8 * math.min(landAid, 25) / 25) / math.max(st.spd, 30), 0, 1))
        local ahead = aimH.Magnitude > 0.5 and aimH:Dot(vdH) > 0.7
        local gA = math.asin(clamp(aim.Y, -1, 1))
        if not ahead or gA < gMin then
          local g2 = ahead and math.max(gA, gMin) or gMin
          aimL = (ahead and aimH or vdH.Unit) * math.cos(g2) + V(0, math.sin(g2), 0)
        end
      end
      -- 机体的升力方向（垂直于航迹）
      local lh = upV - vd0 * vd0:Dot(upV)
      lh = (lh.Magnitude > 1e-3) and lh.Unit or upV
      -- 准心在机头下方不远（下滑、进近、对准跑道；放着起落架时 35° 以内，平时 15° 以内）：不翻过去「把目标滚到头顶再拉」
      --   （原来准心压到机头下面十度就整架翻过来，测试里进近时坡度一下子到 79°）；也不能只按机体坐标往目标那侧滚（机身一歪，
      --   下面的目标在机体坐标里就跑到低的那侧机翼，越滚越歪）——按升力矢量算：航迹要往准心那边转多快 → 要多大的加速度，
      --   加上抵消重力那份，就是升力该有的方向和大小；滚到那个方向、拉那么多 g。往下最多 0.8 g（一直是正过载，不翻过去），
      --   放着起落架时左右最多 0.58 g（坡度 30° 以内）；准心压得更低的照旧滚过去拉（俯冲攻击）
      -- 用户 11-21（镜头改成跟着机身以后看得清清楚楚）：准心在侧面、上面 60° 以内也按升力矢量飞——原来侧面偏十几度就滚到 80° 坡度、
      --   整个升力朝侧面拉，机头往下掉、冲过头再滚回来（准星圈在标记两边来回甩）；按升力矢量算是带着抵消重力那份的协调转弯，坡度刚好够用。
      --   准心在机头下方 15° 以外（俯冲攻击）照旧滚过去拉
      local gentle = flare or (l.Y < 0 and (off < rad(15) or (st.gear > 0.9 and off < rad(35))))
        or (off < rad(60) and l.Y > -math.sin(rad(15)) and fz > 0.3)
      local nGentle, gentleW = nil, 0
      if gentle then
        toTarget = 0
        local ang = math.acos(clamp(vd0:Dot(aimL), -1, 1))
        local ev = aimL - vd0 * vd0:Dot(aimL)
        local aDes = (ev.Magnitude > 1e-4) and ev.Unit * math.min(ang * 2.1, PITCH) * math.max(st.spd, 30) or V()
        local dnP = V(0, -1, 0) - vd0 * (-vd0.Y)   -- 垂直于航迹、朝下
        if dnP.Magnitude > 1e-3 then
          dnP = dnP.Unit
          local sdP = vd0:Cross(dnP)   -- 垂直于航迹的水平方向
          local cD, cS = aDes:Dot(dnP), aDes:Dot(sdP)
          local sMax = ((st.gear > 0.9) and 0.58 or 4) * GR
          aDes = dnP * math.min(cD, 0.8 * GR) + sdP * clamp(cS, -sMax, sMax)
        end
        local aL = aDes - (V(0, -GR, 0) - vd0 * (-GR * vd0.Y))   -- 升力要给的加速度 = 想要的 − 重力（垂直于航迹那份）
        local lhat = (aL.Magnitude > 1e-3) and aL.Unit or lh
        local th = math.atan2(vd0:Dot(lh:Cross(lhat)), lh:Dot(lhat))   -- 升力方向要绕航迹转多少（正：往右滚）
        -- 偏得很少（10° 以内，平时打仗修一点点方向）跟原来一样以摆平机翼为主，不为了几度就压个大坡度；拉平时全按升力矢量
        local wg = flare and 1 or w
        rc = (wg * clamp(th * 2.5, -1, 1) + (1 - wg) * level) * ROLL
        nGentle = math.max(aL:Dot(lh), 0) / GR
        gentleW = wg
      else
        rc = (w * clamp(toTarget * 3.2, -1, 1) + (1 - w) * level) * ROLL
      end
      -- 贴着跑道 / 甲板：机翼自动摆平，只留几度坡度对准跑道
      if landAid and rollIn == 0 then rc = clamp((bank + clamp(psi * 1.5, -rad(8), rad(8))) * 2.5, -1, 1) * ROLL end
      -- 俯仰按航迹（速度方向）对准心：机头比航迹高一个迎角，按机头对准心的话平飞会一直往下掉
      local pz, py = aimL:Dot(vd0), aimL:Dot(lh)
      local pe = math.atan2(py, math.max(pz, 0.05))
      if pz < 0 then pe = (py >= 0) and math.pi / 2 or -math.pi / 2 end
      local pc = clamp(pe * 2.1, -1, 1) * PITCH   -- 增益再低一点（用户 11-18 两次：转弯稍微多一些迟钝感、再笨重一点）
      if math.abs(toTarget) > rad(100) and off > rad(25) then pc = math.min(pc, PITCH * 0.15) end   -- 还没滚过去别乱拉
      local nPe = 1 + pc * math.max(st.spd, 30) / GR
      nCmd = nGentle and (gentleW * nGentle + (1 - gentleW) * math.max(nPe, 0)) or nPe
      -- 偏得不多（10° 以内）、坡度不大：方向舵把机头往准心那边蹬（原来 2° 以内机翼摆平、左右那一点偏差一直修不掉，准星圈停在标记旁边）
      local bankK = clamp(1 - math.abs(bank) / rad(40), 0, 1)
      yc = clamp(psi * 2.2, -rad(d.yaw) * 0.6, rad(d.yaw) * 0.6) * (1 - Map.smooth(rad(6), rad(12), off)) * bankK
      if rollIn ~= 0 then rc = rollIn * ROLL end
    end
    st.nCmd = clamp(nCmd, -2, GMAX / math.sqrt(st.heavy or 1))   -- 重了拉不了那么多 g
    st.yawCmd = yc * q
    st.rr = approach(st.rr, rc * q, ROLL * 2.2 / W ^ 0.5 * dt)   -- 滚转有惯性：重的起来慢（2.8 → 2.2：用户说再笨重一点）
    if st.ground then st.rr, st.yr = 0, 0 end
    st.c.pit, st.c.rol, st.c.yaw = clamp(st.pr / math.max(PITCH, 1e-3), -1, 1), clamp(st.rr / math.max(ROLL, 1e-3), -1, 1), clamp(st.yr / math.max(rad(d.yaw), 1e-3), -1, 1)
    local pos = cf.Position
    if st.ground and st.cat then
      -- 航母弹射器：卡上以后原地不动，油门推满按空格（手机：推满等一秒半）沿轨道加速，冲到舰艏就离舰
      local start, dir, len = AD.cat(Map, st.cat.i)
      if st.cat.state == "hooked" then
        st.spd = 0
        st.yaw = math.atan2(-dir.X, -dir.Z)
        pos = start + V(0, d.gearH, 0)
        cf = CFrame.lookAt(pos, pos + dir)
        st.cat.full = (st.thr >= 90) and ((st.cat.full or 0) + dt) or 0
        if st.thr >= 90 and st.cat.full > 1.2 and (st.foldK or 0) < 0.02 then   -- 推满油门一会儿就弹（空格改成下飞机了）；机翼还没展开完不弹
          st.cat.state, st.cat.s, st.cat.v = "launch", 0, 0
          if G.shake then G.shake(0.4) end
          if G.playSound then G.playSound("boom", pos, 1.6) end
        end
      else
        local vEnd = math.max(d.vRot * 1.2, d.stall * 1.35)
        st.cat.v += vEnd * vEnd / (2 * len) * dt
        st.cat.s += st.cat.v * dt
        st.spd = st.cat.v
        if st.cat.s >= len then   -- 离舰
          st.ground, st.cat = false, nil
          st.pr = rad(5)
          pos = start + dir * len + V(0, d.gearH + 1, 0)
          cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(rad(5), 0, 0)
        else
          pos = start + dir * st.cat.s + V(0, d.gearH, 0)
          cf = CFrame.lookAt(pos, pos + dir)
          st.steamT = (st.steamT or 0) - dt
          if st.steamT <= 0 and G.fxPart then   -- 弹射轨道上一路冒白汽
            st.steamT = 0.05
            local s2 = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(pos - V(0, d.gearH - 0.5, 0)), RGB(236, 236, 232), Enum.Material.SmoothPlastic, 0.35)
            if G.tween then G.tween(s2, 1.4, { Size = V(9, 9, 9), Transparency = 1 }) end
            game:GetService("Debris"):AddItem(s2, 1.5)
          end
        end
      end
      st.vel = cf.LookVector * st.spd
      st.vdir, st.accV = cf.LookVector, nil
      st.sink = 0
    elseif st.ground then
      -- 地上：机头只能左右转（前轮转向：A / D、Q / E，或者鼠标往哪边），速度够了按 S 抬头（或者鼠标往上抬）就离地
      local aimG = autoDir()
      local lg = cf:VectorToObjectSpace(aimG)
      local steer = G.mobile and 0 or clamp(math.atan2(lg.X, math.max(-lg.Z, 0.05)) * 1.5, -1, 1)
      if yawIn ~= 0 or rollIn ~= 0 or G.mobile then steer = (yawIn ~= 0) and yawIn or rollIn end
      local sk = (st.spd >= 0) and clamp(st.spd / 25, 0.15, 1) or -clamp(-st.spd / 25, 0.15, 0.5)   -- 倒退时前轮转向反过来
      st.yaw -= steer * rad(30) * sk * dt
      -- 航母甲板：没上弹射器滑不快（起飞要靠弹射器）；挂上拦阻索的一路被拉停
      local deck = AD.onDeck(Map, pos.X, pos.Z)
      if st.trap then
        st.spd = math.max(0, st.spd - st.trapA * dt)
        if st.spd < 1 then st.trap = nil end
      elseif deck == "carrier" then
        st.spd = math.min(st.spd, AD.TAXI)
      end
      -- 滑到弹射器起点、机头对正、速度慢：卡上
      if deck == "carrier" and d.carrier and not st.trap and st.spd < 15 then
        local look0 = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
        for i = 1, #AD.CATS do
          local start, dir = AD.cat(Map, i)
          local rel = V(pos.X - start.X, 0, pos.Z - start.Z)
          local along = rel:Dot(dir)
          local lat = (rel - dir * along).Magnitude
          if math.abs(along) < 12 and lat < 7 and look0:Dot(dir) > math.cos(rad(25)) then
            st.cat = { i = i, state = "hooked" }
            if G.playSound then G.playSound("capture", pos) end   -- 卡上：咔一声，不出字
            break
          end
        end
      end
      local look = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
      pos += look * st.spd * dt
      local g = ground(pos.X, pos.Z)
      local wantUp = pitchIn < -0.3 or (not G.mobile and aimG.Y > math.sin(rad(3)))
      if st.spd >= d.vRot and wantUp then   -- 离地
        st.ground = false
        st.pr = rad(6)
        cf = CFrame.lookAt(pos + V(0, 0.5, 0), pos + V(0, 0.5, 0) + look) * CFrame.Angles(rad(4), 0, 0)
      elseif pos.Y - d.gearH > g + 2.5 then   -- 冲出甲板 / 跑道尽头：掉下去
        st.ground = false
        cf = CFrame.lookAt(pos, pos + look)
      else
        pos = V(pos.X, g + d.gearH, pos.Z)
        cf = CFrame.lookAt(pos, pos + look)
      end
      st.vel = look * st.spd
      st.vdir, st.accV = (st.ground and look) or cf.LookVector, nil
      st.sink = 0
    else
      -- 天上（用户：很像玩具——原来航迹直接被拉向机头，压坡度不拉杆就不转）：按真飞机的道理——
      --   升力 ∝ 速度² × 迎角，方向垂直于航迹、在机翼的上方；压坡度升力就斜过去，带着航迹转弯（竖直的那份不够重力就掉高度）；
      --   失速速度上用最大迎角正好 1 g，再慢就托不住；过了失速迎角升力往下掉。拉得越狠诱导阻力越大（∝ 过载² / 速度²），掉速
      --   飞控：要 nCmd 个 g 需要多大迎角（限在最大迎角里），机体俯仰角速度 = 航迹转的角速度 + 把迎角往要的那个收（零点几秒）
      cf = cf * CFrame.Angles(st.pr * dt, -st.yr * dt, -st.rr * dt)
      local fw, upB, rtB = cf.LookVector, cf.UpVector, cf.RightVector
      local spd = math.max(st.spd, 1)
      local vd = st.vdir or fw
      local aoa = math.atan2(-vd:Dot(upB), math.max(vd:Dot(fw), 0.05))
      local beta = math.asin(clamp(vd:Dot(rtB), -1, 1))
      local aMax = rad(d.aoaMax or 24)
      local ka = GR / (d.stall * d.stall * aMax) * spd * spd
      local function liftOf(a)
        if a > aMax then return ka * aMax * math.max(0.35, 1 - (a - aMax) / aMax * 1.5) end
        if a < -aMax * 0.6 then return -ka * aMax * 0.6 end
        return ka * a
      end
      local lhat = upB - vd * vd:Dot(upB)
      lhat = (lhat.Magnitude > 1e-3) and lhat.Unit or upB
      local gv = V(0, -GR, 0)
      local gPerp = gv - vd * vd:Dot(gv)
      local L = liftOf(aoa)
      local aNeed = clamp((st.nCmd or 1) * GR / math.max(ka, 1e-3), -aMax * 0.5, aMax * 0.95)
      local pc = (L + gPerp:Dot(lhat)) / spd + (aNeed - aoa) * 5
      pc = clamp(pc, -PITCH * 0.7, PITCH)
      st.pr = approach(st.pr, pc, PITCH * 3.2 / W ^ 0.8 * dt)   -- 转动惯量：零点几秒角速度才起来，重的更慢（4 → 3.2：再笨重一点）
      st.yr = approach(st.yr, clamp(beta * 3, -rad(d.yaw), rad(d.yaw)) + (st.yawCmd or 0), 1.5 / W ^ 0.6 * dt)   -- 自动协调：侧滑往零收
      local aPerp = lhat * L + gPerp - rtB * vd:Dot(rtB) * spd * 1.5   -- 升力 + 重力（垂直于航迹那份）+ 侧滑的侧力
      vd = vd + aPerp / spd * dt
      st.vdir = (vd.Magnitude > 1e-3) and vd.Unit or fw
      -- 降落辅助：离地 25 格以内把下沉率收到 6～14 格 / 秒（越低越小）——真飞机接地前的拉平（加上地效）；
      --   玩家把准心压在跑道上、速度别太快就落得住（原来照直往下扎，下沉过了 24 格 / 秒就判摔）
      if landAid and landAid < 25 and st.vdir.Y < 0 then
        local vyT = -(6 + 8 * landAid / 25) / spd
        if st.vdir.Y < vyT then
          local h = V(st.vdir.X, 0, st.vdir.Z)
          if h.Magnitude > 1e-3 then
            local vy = approach(st.vdir.Y, vyT, 1.2 * dt)
            st.vdir = h.Unit * math.sqrt(math.max(0, 1 - vy * vy)) + V(0, vy, 0)
          end
        end
      end
      local n = L / GR
      st.gLoad = n
      st.aoaDeg = math.deg(aoa)
      st.spd = math.max(0, st.spd - 0.33 * GR * n * n * (d.stall / spd) ^ 2 * dt)   -- 诱导阻力
      st.sink = 0
      local v0 = st.vel
      st.vel = st.vdir * st.spd
      if v0 then   -- 加速度（镜头用：过载把镜头甩开）
        local acc = (st.vel - v0) / math.max(dt, 1e-3)
        st.accV = (st.accV or acc):Lerp(acc, math.min(1, dt * 6))
      end
      pos += st.vel * dt
      cf = cf - cf.Position + pos
      -- 撞地 / 落地
      local g = ground(pos.X, pos.Z)
      if pos.Y - d.gearH <= g + 0.3 then
        local fw = cf.LookVector
        local bank = math.abs(deg(math.asin(clamp(cf.RightVector.Y, -1, 1))))
        local pitch = deg(math.asin(clamp(fw.Y, -1, 1)))
        local deckK = AD.onDeck(Map, pos.X, pos.Z)
        local landable = g > 0.4 or deckK ~= nil
        -- 用户：把降落做好——姿态放宽一点（下沉 30 格 / 秒、坡度 25°、俯仰 −10°～25° 以内）；
        --   姿态对、只是太快（1.5 倍着陆速度以内）：不摔，贴着跑道飘（地效托着、落不下去），提示收油门，慢到能落了就接地；
        --   航母上尾钩放着、飘过拦阻索区照样挂上（真舰载机是全推力着舰、靠拦阻索拉停）
        local attOk = st.gear > 0.9 and landable and st.vel.Y > -30 and bank < 25 and pitch > -10 and pitch < 25
        local hookOk = deckK == "carrier" and (st.c.hook or 0) > 0.5 and AD.inWires(Map, pos.X, pos.Z)
        if attOk and st.spd >= d.landMax and st.spd < d.landMax * 1.5 and not hookOk then
          pos = V(pos.X, g + d.gearH + 0.5, pos.Z)
          st.vdir = V(st.vdir.X, math.max(st.vdir.Y, 0), st.vdir.Z).Unit
          st.spd = math.max(0, st.spd - 14 * dt)   -- 地效 + 拉平的迎角：比空中多掉一点速度
          st.vel = st.vdir * st.spd
          cf = cf - cf.Position + pos
          st.floatT = os.clock()
        elseif attOk and (st.spd < d.landMax or (hookOk and st.spd < d.landMax * 1.5)) then
          st.ground = true
          st.yaw = math.atan2(-fw.X, -fw.Z)
          pos = V(pos.X, g + d.gearH, pos.Z)
          cf = CFrame.lookAt(pos, pos + V(fw.X, 0, fw.Z))
          st.sink, st.pr, st.rr, st.yr = 0, 0, 0, 0
          -- 接地：不按 W 就自动收到慢车（地上油门收到底就自动刹车，五六秒停住、停稳补给）；按住 W 是连续起降
          if not up and st.thr <= 100 then st.thr = 0 end
          if G.shake then G.shake(0.15) end
          touchdown(-(st.vel.Y or 0), true)
          -- 航母：尾钩放着、落在拦阻索区，被拦阻索拉停（85 格内停住）
          if AD.onDeck(Map, pos.X, pos.Z) == "carrier" and (st.c.hook or 0) > 0.5 and AD.inWires(Map, pos.X, pos.Z) then
            st.trap, st.trapA = true, math.max(20, st.spd * st.spd / (2 * 85))
            if G.shake then G.shake(0.5) end
          end
        else
          crash()
        end
      end
    end
    st.cf = cf
    -- 起落架（用户：起飞自动把起落架收了）：离地爬过 15 米、还在往上爬就自动收一次；这次起飞只收一次，之后按 G 放下就听玩家的；
    --   地上一直放着，落地重置
    if st.ground then
      st.gearWant, st.gearAuto = 1, false
    elseif not st.gearAuto and st.gearWant > 0.5 and st.vel and st.vel.Y > 0.5 then
      local p0 = cf.Position
      if p0.Y - d.gearH - math.max(ground(p0.X, p0.Z), 0) > 15 * AD.M then
        st.gearAuto, st.gearWant = true, 0
        if G.toast then G.toast(T("coach.gearAuto"), "info") end
      end
    end
    st.gear = approach(st.gear, st.gearWant, dt / 2.5)
    st.c.gear = st.gear
    st.c.thr = st.thr
    st.c.flap = (st.gear > 0.5 and st.spd < d.stall * 1.6) and 1 or 0
    st.c.can = (st.ground and st.thr < 5 and st.spd < 3) and 1 or 0
    -- 折翼（用户：飞机机翼折叠没有动画）：原来直接 0 / 1 一下就折好；现在约 4 秒折起 / 展开（真机十几秒，游戏里缩短），
    --   一上来就停在甲板上的直接是折着的；推油门就开始展开，展开完才能弹射
    local foldWant = (d.fold and st.ground and st.thr < 5 and st.spd < 3 and AD.onDeck(Map, pos.X, pos.Z)) and 1 or 0
    if st.foldK == nil then st.foldK = foldWant end
    st.foldK = approach(st.foldK, foldWant, dt / 4)
    st.c.fold = st.foldK
    st.c.hook = (d.gear and d.gear.hook and st.gear > 0.9 and not st.ground) and 1 or 0
    st.c.brk = (key(Enum.KeyCode.B)) and 1 or 0
    st.c.rpm = st.thr
  end

  ---------------------------------------------------------------- 物理：直升机

  -- 直升机（用户：直升机操作感觉不太真实）：按真直升机的道理飞——旋翼拉力沿桨盘法线，桨盘往哪倾就往哪加速：
  --   W / S 前推后拉驾驶杆（低头加速、抬头减速 / 后退）；姿态有惯性（二阶弹簧），松杆自动回平；
  --   低速（悬停附近）松杆时自动往反方向带一点把飘移收住，快的时候松杆就保持平飞、靠阻力慢慢减速（要停下来得抬头拉一下）；
  --   E / Q 总距（E 升、Q 降）：拉力大小（同样的总距，机身一倾、竖直方向的拉力就小了，会掉高度）；不按时自动把升降速度收到 0（定高）；
  --   A / D 脚蹬：偏航角速度，有惯性；速度上来以后压坡度就会转弯（协调转弯），尾翼让机头顺着来流（风标效应）；
  --   平移升力（二十几格每秒以上旋翼效率高一点）、地效（离地一个旋翼直径以内托得更稳）；最高平飞速度、爬升率照型号表
  local function heliPhysics(dt)
    local d = st.d
    if st.out then st.rpm = approach(st.rpm, 72, 9 * dt) else st.rpm = approach(st.rpm, 100, 22 * dt) end   -- 旋翼转起来要四五秒；熄火后靠气流自转，转速掉下来
    local lift = st.rpm >= 92
    local auto = st.out and not st.ground   -- 熄火自转下滑：还能往前飘一点，快落地时拉总距（空格）下沉慢一些
    -- 用户：桨盘对着哪里往哪飞（按受力算，要有物理引擎的感觉），准心决定机头朝向——
    --   鼠标转准心（镜头），机头跟着准心转：尾桨有惯性，最快 d.yaw 度 / 秒，起转、停住都要一会儿（按住 Alt 自由看，机头不跟）
    --   W / S 桨盘前倾 / 后仰（往前飞 / 带杆刹车、倒飞），A / D 桨盘左右倾（侧飞）；E 升、Q 降（Ctrl / C 也降）；空格下飞机
    --   拉力顺着桨盘法线：倾得越多水平推力越大、往上托的越少（猛一推杆先掉一点高度）；速度有惯性，松杆桨盘回平但人还往前冲，靠阻力慢慢停
    --   快速前飞时转机头，桨盘自动往那边压坡度（协调转弯），航迹跟着机头弯过去；侧面阻力大，侧飞快不起来
    local fwdIn = (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0)
    local sideIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn = 0
    local upIn = ((key(Enum.KeyCode.E) or (touch and touch.up)) and 1 or 0)
      - ((key(Enum.KeyCode.Q) or key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.C) or (touch and touch.down)) and 1 or 0)
    if G.mobile and controls then
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.Z) > 0.1 then fwdIn = -mv.Z end
        if math.abs(mv.X) > 0.1 then yawIn, sideIn = mv.X, 0 end   -- 手机没有鼠标：摇杆左右转机头
      end
    end
    local GS = GR or 27.5
    local heavy = st.heavy or 1
    local maxT = rad(d.tilt)
    local f = V(-math.sin(st.yaw), 0, -math.cos(st.yaw))
    local r = V(math.cos(st.yaw), 0, -math.sin(st.yaw))
    local hv = st.hv
    local spd = hv.Magnitude
    local vf, vr = hv:Dot(f), hv:Dot(r)
    local g0 = ground(st.cf.Position.X, st.cf.Position.Z)
    local agl = st.cf.Position.Y - d.gearH - math.max(g0, 0)
    -- 机头：朝准心（镜头方位）转，角速度有上限、有角加速度（尾桨）；在地上转速够了才能原地慢慢转
    local maxR = rad(d.yaw)
    local yrWant
    if G.mobile then
      yrWant = -yawIn * maxR
    else
      yrWant = clamp(angDiff(st.yaw, st.noseYaw or st.camYaw) * 3.2, -maxR, maxR)
    end
    if st.ground then yrWant *= (lift and 0.3 or 0) end
    st.yr = approach(st.yr or 0, yrWant, maxR * 2.6 * dt)
    st.yaw += st.yr * dt
    -- 驾驶杆 → 桨盘想要的倾角（俯仰：负的是低头 = 往前倾）；松杆桨盘回平
    local tP = -fwdIn * maxT
    local tR = sideIn * maxT * 0.8
    -- 往前飞得快时转机头：桨盘自动压坡度——要的侧向加速度 = 转弯的向心那份（速度 × 角速度）+ 消掉侧滑的那份（没按 A / D 时），
    --   tan 坡度 = 侧向加速度 / g；坡度给的侧向力把航迹拉着跟机头弯过去（压不过来的那一截就是侧滑，靠侧面阻力慢慢吃掉）
    if not st.ground then
      local aLat = spd * -st.yr - ((sideIn == 0) and vr * 0.8 or 0)
      tR += clamp(math.atan(aLat / GS), -maxT, maxT) * smooth(12, 40, vf)
    end
    tP, tR = clamp(tP, -maxT, maxT), clamp(tR, -maxT, maxT)
    if st.ground then tP, tR = 0, 0 end
    -- 桨盘姿态：二阶弹簧（有惯性、接近临界阻尼，一秒左右到位）
    st.pR = (st.pR or 0) + ((tP - st.tiltP) * 12 - (st.pR or 0) * 6.5) * dt
    st.rR = (st.rR or 0) + ((tR - st.tiltR) * 12 - (st.rR or 0) * 6.5) * dt
    st.tiltP += st.pR * dt
    st.tiltR += st.rR * dt
    -- 拉力：总距（松开时慢慢稳住升降，不替你补桨盘倾斜少掉的那份；停在地上时放到底）× 平移升力 × 地效
    local colWant = upIn
    if upIn == 0 then colWant = clamp(-st.vy * 0.05, -0.6, 0.6) end
    if st.ground and upIn <= 0 then colWant = -0.5 end
    if upIn < 0 and agl < 25 then colWant = -0.45 end   -- 快到地面了：下降慢一点（落地不摔）
    st.col = approach(st.col or 0, colWant, dt * 1.6)
    local k = d.climb * 0.6 / GS / heavy   -- 满总距的爬升率 ≈ 型号表 climb
    local etl = 1 + 0.08 * smooth(16, 36, spd)
    local ige = 1 + 0.1 * (1 - clamp(agl / ((d.rotor and d.rotor.r or 20) * 2), 0, 1))
    local Tm
    if auto then Tm = GS * (0.74 + 0.3 * math.max(upIn, 0))
    elseif not lift then Tm = GS * (st.rpm / 100) * 0.8
    else Tm = GS * (1 + st.col * k) * etl * ige end
    local cfA = CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.tiltP, 0, -st.tiltR)
    local up = cfA.UpVector
    -- 阻力（按机身方向分开算）：前后流线——桨盘前倾到底、拉力托住重量时正好飞到型号表的 vMax；侧面大得多，侧飞四十几格每秒就到头；
    --   悬停附近多一点（好稳住，不然松杆飘半天）
    local clF = 0.05 + 0.1 * (1 - smooth(6, 30, spd))
    local cq = math.max(1e-5, (GS * math.tan(maxT) - 0.05 * d.vMax) / (d.vMax * d.vMax)) * (1 + (st.drag or 0))
    st.lastHv = hv
    local acc = V(up.X, 0, up.Z) * Tm - f * (vf * (clF + cq * math.abs(vf))) - r * (vr * (clF * 2 + cq * 3 * math.abs(vr)))
    if st.ground then acc = V() hv *= math.max(0, 1 - 5 * dt) end
    st.hv = hv + acc * dt
    st.vy += (Tm * up.Y - GS - st.vy * 0.5) * dt
    -- 合速度不超过服务器认的（往下冲时重力也在加速）
    local v3 = st.hv + V(0, st.vy, 0)
    local cap = d.vMax * 1.3
    if v3.Magnitude > cap then
      v3 = v3.Unit * cap
      st.hv, st.vy = V(v3.X, 0, v3.Z), v3.Y
    end
    local pos = st.cf.Position + (st.hv + V(0, st.vy, 0)) * dt
    local g = ground(pos.X, pos.Z)
    if pos.Y - d.gearH <= g then
      local overSea = g <= 0.4 and not AD.onDeck(Map, pos.X, pos.Z)
      if (st.vy < -30 or overSea) and not st.ground and not st.crashed then crash() end
      if not st.ground and not st.crashed and st.vy < -5 then touchdown(-st.vy, false) end
      pos = V(pos.X, g + d.gearH, pos.Z)
      st.vy = math.max(st.vy, 0)
      st.ground = upIn <= 0 and Tm * up.Y <= GS * 1.02
      if st.ground then st.hv *= math.max(0, 1 - 5 * dt) end
    else
      st.ground = false
    end
    st.cf = CF(pos) * CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(st.tiltP, 0, -st.tiltR)
    st.vel = st.hv + V(0, st.vy, 0)
    -- 动画通道：驾驶杆（桨盘跟着倾）、脚蹬（尾桨）、总距
    st.c.pit = approach(st.c.pit or 0, clamp(-tP / maxT, -1, 1), dt * 4)
    st.c.rol = approach(st.c.rol or 0, clamp(tR / maxT, -1, 1), dt * 4)
    st.c.yaw, st.c.col = clamp(-st.yr / maxR, -1, 1), clamp(st.col, -1, 1)
    st.c.rpm, st.c.thr, st.c.gear = st.rpm, st.rpm, 1
  end

  ---------------------------------------------------------------- 输入

  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.Space then G.R.Drive:FireServer({ op = "exit" }) return end   -- 用户：空格键脱离载具（在天上就跳伞）
    if not st.pilot then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      if G.interiorHover and G.interiorHover() then return end   -- 座舱里对着屏幕边的按键：左键是按键，不开炮（Interior.lua）
      st.firing = true
    elseif k == Enum.KeyCode.F then   -- 发导弹 / 火箭 / 炸弹（选中的那种）
      st.missile = true
    elseif k == Enum.KeyCode.C and st.d.kind == "jet" and st.uav then   -- 无人机：准星圈回到正前方，按航迹（飞机照直飞）
      local lk = (not st.ground and st.vdir) or st.cf.LookVector
      st.aimYaw, st.aimPitch = math.atan2(-lk.X, -lk.Z), math.asin(clamp(lk.Y, -1, 1))
    elseif k == Enum.KeyCode.C and st.d.kind == "jet" and st.pilot then   -- 有人开的固定翼：视角立刻回到身后（座舱里回到正前方）
      st.lookYaw, st.lookPitch, st.lookT = 0, 0, 0
    elseif k == Enum.KeyCode.X then   -- 热诱弹：按住连续放（用户），每帧里按节拍发（stepFly）
      st.flareHold = true
      if os.clock() >= (st.flareNext or 0) and (st.flares or 0) > 0 then   -- 点一下也放一组（按下、松开在同一帧里的话，按住的逻辑一组都发不出去）
        st.flareNext = os.clock() + 0.3
        G.R.Drive:FireServer({ op = "flare" })
      end
    elseif k == Enum.KeyCode.J then   -- 抛副油箱（进空战前）
      G.R.Drive:FireServer({ op = "jettison" })
    elseif k == Enum.KeyCode.G then
      if st.d.kind == "jet" and not st.ground then st.gearWant = (st.gearWant > 0.5) and 0 or 1 end
    elseif k == Enum.KeyCode.R then
      G.flyNextTarget()
    elseif k == Enum.KeyCode.P then   -- 光电吊舱视角
      setEO(not st.eo)
    elseif st.eo and k == Enum.KeyCode.V then   -- 光电：电视 → 热成像白热 → 黑热
      st.eoMode = (st.eoMode or 1) % #EO_MODES + 1
      eoApply()
    elseif st.uav and (k == Enum.KeyCode.V or io.UserInputType == Enum.UserInputType.MouseButton2) then   -- 平板：前视光电 ↔ 外部视角
      st.dcam = (st.dcam == "nose") and "chase" or "nose"
    elseif (st.uav or st.eo) and k == Enum.KeyCode.Z then   -- 变焦一档一档跳：1× → 3× → 8× → 1×
      st.zoom = (st.zoom < 3.9) and 4 or ((st.zoom < 11.9) and 12 or ((st.zoom < 29.9) and 30 or 1))   -- 用户：光电要看得远一点（最大 30 倍）
    else
      local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6 })[k]
      if n and st.wl[n] then
        st.wi = n
        st.lock, st.lockT = nil, 0
      end
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if st and io.UserInputType == Enum.UserInputType.MouseButton1 then st.firing = false end
    if st and io.KeyCode == Enum.KeyCode.F then st.missile = false end
    if st and io.KeyCode == Enum.KeyCode.X then st.flareHold = false end
  end)
  UIS.InputChanged:Connect(function(io, gp)   -- 平板前视光电：滚轮细调倍率（1× ~ 12×）
    if gp or not st or not (st.uav or st.eo) or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    st.zoom = clamp(st.zoom * (1 + 0.18 * io.Position.Z), 1, 40)
  end)

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" or not st then return end
    if m.op == "fix" and typeof(m.cf) == "CFrame" then   -- 服务器不认：拉回去
      st.cf = m.cf
      if typeof(m.v) == "Vector3" then
        st.vel = m.v
        st.spd = m.v.Magnitude
        st.hv = V(m.v.X, 0, m.v.Z)
      end
      -- 航迹方向跟着拉回去（不然留着原来的航迹，机头和航迹差得远，一下子掉光速度失速）
      st.vdir = (typeof(m.v) == "Vector3" and m.v.Magnitude > 1) and m.v.Unit or m.cf.LookVector
      st.accV = nil
    elseif m.op == "rwr" then   -- 有导弹朝我来了
      st.rwrT = os.clock() + 4
      if G.playSound then G.playSound("capture", nil, 2.2) end
    end
  end)

  ---------------------------------------------------------------- 每帧

  local SENS = 0.0042
  local function project(p)
    local sp, on = cam:WorldToViewportPoint(p)
    return UDim2.fromOffset(sp.X, sp.Y), on
  end

  -- 打中了（服务器发来的命中标记）：开着飞机时镜头猛跳一下、准星变红放大（Play.lua 的 G.hitMarker 调）
  function G.onHitMarker(kind)
    if st and st.pilot then st.hitKick = math.min(1.3, (st.hitKick or 0) + ((kind == "kill") and 1.0 or 0.45)) end
  end
  -- 吊舱页面每帧（用户给的 TGP 参考）：模式、视场、跟踪框、斜距、高度、指北、TTI、右栏
  -- 平显：俯仰梯、速度矢量、G / α / M（固定翼、飞行员、不在吊舱里）
  local function dcsHud(pos, kmh)
    local d = st.d
    -- 俯仰梯、速度矢量、G / α / M 只在遥控无人机（原来那一套平显）里画；有人开的飞机是 AirHud 的界面（用户 11-19：中间不要一段段线拼起来的东西）
    local on = d.kind == "jet" and st.pilot and not st.eo and not st.crashed and st.uav == true
    fpm.Visible, gText.Visible, aText.Visible, mText.Visible = false, on, on, on
    if not on then
      for _, L in ipairs(ladderPool) do L.f.Visible = false end
      return
    end
    local camP = cam.CFrame.Position
    local v = (st.vel.Magnitude > 5) and st.vel.Unit or st.cf.LookVector
    local hz = Vector3.new(v.X, 0, v.Z)
    hz = (hz.Magnitude > 1e-3) and hz.Unit or Vector3.new(0, 0, -1)
    local side = Vector3.new(-hz.Z, 0, hz.X)
    if not st.ground then
      local fp, fon = project(camP + v * 1000)
      fpm.Position, fpm.Visible = fp, fon
    end
    -- 俯仰梯：镜头看着的俯仰角上下各 25° 里每 5° 一根
    local lv = cam.CFrame.LookVector
    local camPitch = math.deg(math.asin(clamp(lv.Y, -1, 1)))
    local k0 = math.ceil((camPitch - 25) / 5)
    local used = 0
    local vh = cam.ViewportSize.Y
    for k = k0, k0 + 10 do
      local pa = k * 5
      if pa >= -90 and pa <= 90 then
        local r = rad(pa)
        local dirC = hz * math.cos(r) + Vector3.new(0, math.sin(r), 0)
        local c = camP + dirC * 1000
        local w = (pa == 0) and 260 or 130   -- 半宽（世界里一千格外的长度：地平线长一倍）
        local pl, onL = project(c - side * w)
        local pr, onR = project(c + side * w)
        if onL and onR then
          used += 1
          local L = ladderPool[used]
          if not L then break end
          local ax, ay = pl.X.Offset + pl.X.Scale * cam.ViewportSize.X, pl.Y.Offset + pl.Y.Scale * vh
          local bx, by = pr.X.Offset + pr.X.Scale * cam.ViewportSize.X, pr.Y.Offset + pr.Y.Scale * vh
          local cx, cy = (ax + bx) / 2, (ay + by) / 2
          local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
          L.f.Position = UDim2.fromOffset(cx, cy)
          L.f.Size = UDim2.fromOffset(len, 2)
          L.f.Rotation = math.deg(math.atan2(by - ay, bx - ax))
          L.f.Visible = true
          local gap = math.min(70, len * 0.22)   -- 中间留空给速度矢量
          local half = len / 2 - gap
          local neg = pa < 0
          for i, sgm in ipairs(L.segs) do
            local left = i <= 2
            local inner = (i % 2 == 0)
            local x0 = left and 0 or (len / 2 + gap)
            if neg then   -- 虚线：每边两段
              local sl = half * 0.42
              local xs = x0 + (inner == left and (half - sl) or 0)
              if not left then xs = x0 + (inner and 0 or (half - sl)) end
              sgm.Size = UDim2.fromOffset(sl, 2)
              sgm.Position = UDim2.fromOffset(xs + sl / 2, 1)
              sgm.Visible = true
            else
              sgm.Size = UDim2.fromOffset(half, 2)
              sgm.Position = UDim2.fromOffset(x0 + half / 2, 1)
              sgm.Visible = (i == 1 or i == 3)
            end
          end
          -- 端头的小竖线：正的往下（指地平线），负的往上
          for i, tk in ipairs(L.ticks) do
            tk.Visible = pa ~= 0
            tk.Position = UDim2.fromOffset((i == 1) and 1 or (len - 1), neg and -8 or 1)
          end
          for i, lb in ipairs(L.labs) do
            lb.Text = (pa ~= 0) and tostring(math.abs(pa)) or ""
            lb.Position = UDim2.fromOffset((i == 1) and -18 or (len + 18), neg and -6 or 6)
            lb.Rotation = 0
          end
        end
      end
    end
    for i = used + 1, #ladderPool do ladderPool[i].f.Visible = false end
    -- G、α、M
    local gl = st.gLoad or 1
    gText.Text = string.format("G %.1f", gl)
    gText.TextColor3 = (gl > 7.5 or gl < -2.5) and RGB(255, 90, 80) or HUD
    aText.Text = string.format("α %.1f", st.aoaDeg or 0)
    mText.Text = string.format("M %.2f", st.vel.Magnitude / AD.M / 340)
  end
  -- 灰视 / 红视：正过载超过 6.5g 慢慢变暗、发灰（撑得越久越重，到 9g 几乎全黑），负过载超过 −2.5g 发红；松了一两秒恢复
  local function gEffect(dt)
    local gl = (st and st.d and st.d.kind == "jet" and st.pilot and not st.ground and not st.crashed) and (st.gLoad or 1) or 1
    local want = 0
    if gl > 6.5 then want = (gl - 6.5) / 2.5 elseif gl < -2.5 then want = (gl + 2.5) / 1.5 end
    want = clamp(want, -1, 1)
    local rate = (math.abs(want) > math.abs(gStress)) and 0.55 or 1.4   -- 压上去慢、缓过来快
    gStress += (want - gStress) * math.min(1, dt * rate)
    local k = math.abs(gStress)
    local red = gStress < 0
    local on = k > 0.02
    for _, f in ipairs(gVig) do
      f.Visible = on
      if on then
        f.BackgroundColor3 = red and RGB(120, 0, 0) or RGB(0, 0, 0)
        f.BackgroundTransparency = 1 - math.min(1, k * 1.3)
      end
    end
    gFill.BackgroundColor3 = red and RGB(110, 0, 0) or RGB(0, 0, 0)
    gFill.BackgroundTransparency = 1 - clamp((k - 0.5) * 1.6, 0, 0.92)
    gCC.Enabled = on
    if on then gCC.Saturation, gCC.Brightness = -k * 0.9, red and 0 or -k * 0.12 end
    G.gStress = gStress   -- 测试用
  end
  G.flyGEffect = gEffect

  local tgpStep
  local REL = { bomb = "CCRP", agm = "PRE", rkt = "RKT", aam = "SRM", gun = "GUN" }
  local function fmtT(t)
    if not t or t ~= t or t < 0 or t > 599 then return "-:--" end
    return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
  end
  function tgpStep(pos, wid, w)
    local m = EO_MODES[st.eoMode or 1]
    eoMode.Text = T("eo." .. m)
    TG.fov.Text = (st.zoomS >= 3) and "NARO" or "WIDE"
    TG.zoom.Text = string.format("%.1fx", st.zoomS)
    TG.ag.Text = (w and w.kind == "aam") and "A-A" or "A-G"
    local camP = cam.CFrame.Position
    local vs = cam.ViewportSize
    local dispH = vs.Y * 0.78
    local dispW = math.min(vs.X, dispH * 4 / 3)
    -- 跟踪：吊舱正看着车、船、飞机 → POINT，框按它在画面里多大；锁着的目标不在中间就框到它那里；都没有是 AREA（中间一个小框）
    local point, bx, by, bs = false, dispW / 2, dispH / 2, MOB and 18 or 26
    local function sizeOf(model, at)
      local root = model and model:FindFirstChild("Root")
      local sz = root and math.max(root.Size.X, root.Size.Y, root.Size.Z) or 10
      local dist = math.max(1, (at - camP).Magnitude)
      local f = (vs.Y / 2) / math.tan(math.rad(cam.FieldOfView / 2))
      return clamp(sz / dist * f * 1.15, MOB and 20 or 28, MOB and 90 or 150)
    end
    if st.aimEnt and st.aimEnt.Parent then
      point = true
      local root = st.aimEnt:FindFirstChild("Root")
      bs = sizeOf(st.aimEnt, root and root.CFrame.Position or st.aimPt)
    elseif st.lock and st.lock.pos then
      local sp, on = cam:WorldToViewportPoint(st.lock.pos)
      local lx, ly = sp.X - (vs.X - dispW) / 2, sp.Y - (vs.Y - dispH) / 2
      if on and lx > 0 and lx < dispW and ly > 0 and ly < dispH then
        point, bx, by = true, lx, ly
        bs = sizeOf(st.lock.em, st.lock.pos)
      end
    end
    TG.box.Position = UDim2.fromOffset(bx, by)
    TG.box.Size = UDim2.fromOffset(bs, bs)
    TG.boxStroke.Thickness = point and 1.5 or 1
    TG.track.Text = point and "POINT" or "AREA"
    -- 斜距（海里）、高度（英尺）、指北
    local slant = (st.aimPt - camP).Magnitude / AD.M
    TG.rng.Text = string.format("T %.1f", slant / 1852)
    TG.alt.Text = string.format("%d", math.floor(pos.Y / AD.M * 3.281 + 0.5))
    local lv = cam.CFrame.LookVector
    TG.north.Rotation = -90 - math.deg(math.atan2(lv.X, -lv.Z))
    -- 投出去的弹还在飞：TTI 按它离瞄准点多远、多快；没投就按现在投下去要飞多久
    local live, tti = nil, nil
    for _, s2 in pairs(G.flyingShots or {}) do
      if s2.by ~= nil and s2.by == st.id and (s2.kind == "bomb" or s2.kind == "missile" or s2.kind == "rocket") then
        if not live or s2.t < live.t then live = s2 end
      end
    end
    if live then
      tti = (st.aimPt - live.p).Magnitude / math.max(live.v.Magnitude, 1)
      live.tti0 = live.tti0 or math.max(tti, 0.1)
      TG.bar.Size = UDim2.fromScale(clamp(1 - tti / live.tti0, 0, 1), 1)
    else
      TG.bar.Size = UDim2.fromScale(0, 1)
      if w and w.kind == "bomb" then
        local h = pos.Y - math.max(ground(pos.X, pos.Z), 0)
        local vy = -st.vel.Y
        tti = (vy + math.sqrt(math.max(0, vy * vy + 2 * GR * math.max(h, 0)))) / GR
      elseif w and (w.kind == "agm" or w.kind == "rkt") then
        tti = slant * AD.M / math.max(w.speed or 300, 1)
      end
    end
    TG.tti.Text = "TTI " .. fmtT(tti)
    TG.ttiBig.Text = fmtT(tti)
    -- 右栏
    local nm = wid and T("aw." .. wid) or "--"
    TG.rel.Text = (REL[w and w.kind or "gun"] or "PRE") .. "  ·  " .. nm
    TG.away.Text = live and (nm .. "  AWAY") or ""
    local laser = w ~= nil and (w.kind == "bomb" or w.kind == "agm")
    TG.arm.Text = laser and "LASER ARM" or ""
    TG.lst.Text = live and string.format("LST %d s  ·  1688", math.max(0, math.floor((tti or 0) - 8))) or (laser and "LST  ·  1688" or "")
    TG.say.Text = live and T("eo.sayHold") or (point and T("eo.sayPoint") or T("eo.sayArea"))
    eoHint.Text = T("eo.hint")
  end

  function G.stepFly(dt)
    G.try_(gEffect, dt)
    local S = G.S
    local vs = S and S.alive and S.veh or nil
    if vs and not vs.air then vs = nil end
    if vs and (not st or st.id ~= vs.id) then
      if st then stop() end
      begin(vs)
    elseif not vs and st then
      stop()
    end
    if not st then return end
    if not st.em.Parent then stop() return end
    local d = st.d
    st.pilot = vs.pilot == true
    st.stores = st.storesLocal or {}
    -- 服务器推来的弹药数（半秒一次）：比本地扣的数少才换（本地先扣过的不回弹）
    if vs.stores then
      st.storesLocal = st.storesLocal or table.clone(vs.stores)
      for i, n in ipairs(vs.stores) do
        if st.storesSeen == nil or st.storesSeen[i] ~= n then st.storesLocal[i] = n end
      end
      st.storesSeen = table.clone(vs.stores)
      st.stores = st.storesLocal
    end
    st.gunAmmo, st.flares, st.load = vs.gun or 0, vs.flares or 0, vs.load or st.load
    -- 油量（服务器算，属性 Fuel / FuelX）：烧干了熄火；挂着的副油箱算阻力，油多算重量
    local f0, x0 = st.em:GetAttribute("Fuel"), st.em:GetAttribute("FuelX")
    st.fuel = (type(f0) == "number") and f0 or 1
    st.fuelX = (type(x0) == "number") and x0 or 0
    st.out = st.fuel <= 0 and st.fuelX <= 0
    st.heavy = AD.heavy(d, st.fuel, st.fuelX)
    st.drag, st.tanks = 0, 0
    for i, s2 in ipairs(d.st or {}) do
      local w2 = st.load and st.load[i] and AD.W[st.load[i]]
      if w2 and w2.kind == "tank" and (st.stores[i] or 0) > 0 then
        st.drag += w2.drag * st.stores[i]
        st.tanks += st.stores[i]
      end
    end
    -- 镜头转动
    if not G.mobile then UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end
    local md = UIS:GetMouseDelta()
    -- 平板前视光电变焦：倍率越大鼠标越慢（准星在画面上走得一样快）
    st.zoomS = st.zoomS + ((((st.uav and st.dcam == "nose") or st.eo) and st.zoom or 1) - st.zoomS) * math.min(1, dt * 8)
    if st.uav or st.eo then md = md / st.zoomS end
    if st.eo then   -- 光电：鼠标只转吊舱（飞机按自动驾驶飞）
      st.eoYaw -= md.X * SENS
      st.eoPitch = clamp(st.eoPitch - md.Y * SENS, -1.5, 0.35)
    else
      local pitLook = key(Enum.KeyCode.LeftAlt) and G.interiorOn and G.interiorOn()   -- 座舱里按住 Alt 自由看（Interior.lua 转头）：准心不动
      if d.kind == "jet" and not G.mobile and not pitLook then
        if st.pilot and not st.uav then
          -- 有人开的固定翼（用户 11-21：WASD 控制方向、不要准心控制）：鼠标不管方向，只转视角——
          --   用户 11-21（晚）：飞机要允许用鼠标转视角：不用再按住 Alt，鼠标一动镜头就绕着飞机转（座舱里就是转头看，Interior.lua），
          --   停在拨到的地方；鼠标 2.5 秒不动才慢慢回到身后，C 立刻回正
          if md.X ~= 0 or md.Y ~= 0 then
            st.lookYaw = clamp((st.lookYaw or 0) - md.X * SENS, -2.8, 2.8)
            st.lookPitch = clamp((st.lookPitch or 0) - md.Y * SENS, -1.2, 1.2)
            st.lookT = os.clock()
          end
        elseif st.pilot then   -- 无人机：鼠标推的是想去的方向（飞机自动转过去）
          -- 镜头跟着机身：按镜头的左右、上下转（倒飞、竖直爬升时鼠标往上照样是画面上方），再限制在机头前方的椭圆里
          --   （鼠标没动就不管：自动驾驶、降落辅助给的方向照原样）
          if md.X ~= 0 or md.Y ~= 0 then
            local _, up, rt = jetCamBasis()
            local a = autoDir()
            if md.X ~= 0 then a = CFrame.fromAxisAngle(up, -md.X * SENS):VectorToWorldSpace(a) end
            if md.Y ~= 0 then a = CFrame.fromAxisAngle(rt, -md.Y * SENS):VectorToWorldSpace(a) end
            setAim(clampAim(a))
          end
        else
          st.aimYaw -= md.X * SENS
          st.aimPitch = clamp(st.aimPitch - md.Y * SENS, -1.45, 1.45)
        end
      end
      -- 直升机：机头跟着准心转（鼠标转的就是准心）；手机没有鼠标、坐后面的人不开飞机：镜头跟着机头一起转
      if d.kind == "heli" then
        if (G.mobile or not st.pilot) and st.yawSeen then st.camYaw += angDiff(st.yawSeen, st.yaw) end
        -- 按住 Alt 自由看：机头停在按下时的准心上；松开回到原来的准心
        local alt = st.pilot and not G.mobile and key(Enum.KeyCode.LeftAlt)
        if alt and not st.freeLook then
          st.freeLook = { st.camYaw, st.camPitch }
          st.noseYaw = st.camYaw
        elseif not alt and st.freeLook then
          st.camYaw, st.camPitch = st.freeLook[1], st.freeLook[2]
          st.freeLook, st.noseYaw = nil, nil
        end
      end
      st.yawSeen = st.yaw
      st.camYaw -= md.X * SENS
      st.camPitch = clamp(st.camPitch - md.Y * SENS, -1.2, 0.9)
    end
    -- 飞
    if st.pilot and not st.crashed then
      if d.kind == "jet" then jetPhysics(dt) else heliPhysics(dt) end
      -- 撞楼、撞舰岛：沿着速度方向打一条射线
      local stepV = st.vel * dt * 1.6
      if stepV.Magnitude > 0.5 and not st.ground then
        local res = workspace:Raycast(st.cf.Position, stepV + stepV.Unit * d.L * 0.4, mapParams)
        if res and res.Normal.Y < 0.6 then crash() end
      end
      -- 飞出作战区（±Map.PLAY，约 5 公里）：自动掉头（喷气机掉头半径七八百格）；再往外硬拦住（服务器在 Map.PLAY + 1200 以外不认）
      local p = st.cf.Position
      local lim = Map.PLAY
      st.oob = math.abs(p.X) > lim or math.abs(p.Z) > lim
      if st.oob and d.kind == "jet" then
        local back = V(-p.X, 0, -p.Z).Unit
        st.aimYaw = math.atan2(-back.X, -back.Z)
        st.aimPitch = 0.05
      end
      local hard = Map.PLAY + 1000
      if math.abs(p.X) > hard or math.abs(p.Z) > hard then
        st.cf = st.cf - p + V(math.clamp(p.X, -hard, hard), p.Y, math.clamp(p.Z, -hard, hard))
        if d.kind == "heli" then st.hv = V() end
      end
      if p.Y > 2600 then st.cf = st.cf - V(0, p.Y - 2600, 0) end
    else
      st.cf = st.em.Root.CFrame   -- 坐在后面：跟着服务器
    end
    -- 发动机声跟着油门（固定翼：加力更尖更响）、总距（直升机：拉得越狠越沉）
    if st.engSnd then
      if d.kind == "jet" then
        local tq = math.clamp((st.thrE or st.thr or 0) / 100, 0, 1.3)
        st.engSnd.PlaybackSpeed = 0.75 + 0.45 * tq
        st.engSnd.Volume = 0.3 + 0.6 * tq
      else
        local load = math.clamp(math.abs((st.c and st.c.col) or 0), 0, 1)
        st.engSnd.PlaybackSpeed = 0.95 + 0.12 * load
        st.engSnd.Volume = 0.7 + 0.4 * load
      end
      if st.crashed then st.engSnd.Volume = 0 end
    end
    -- 航炮后坐：开火时机身高频抖一点（模型跟着抖，用户：飞机机炮要有散布、后坐力和打击感）
    local gunOn = st.pilot and st.trig and (st.gunAmmo or 0) > 0 and not st.crashed
    st.recoil = approach(st.recoil or 0, gunOn and 1 or 0, dt * (gunOn and 14 or 6))
    st.hitKick = math.max(0, (st.hitKick or 0) - dt * 5)
    if st.recoil > 0.02 and st.pilot then
      local t = os.clock()
      local a = math.rad(0.05) * st.recoil
      st.cf = st.cf * CFrame.Angles(math.noise(t * 37, 2.1) * a, math.noise(t * 33, 5.3) * a, math.noise(t * 29, 8.7) * a)
    end
    -- 镜头
    local pos = st.cf.Position
    if st.eo then
      -- 光电吊舱：机腹下面（固定翼）/ 机头下面的光电球（直升机），视线稳定在世界方向上，不画镜头抖动
      local eye = (d.kind == "jet") and (st.cf * CF(0, -d.H * 0.5 - 0.6, -d.L * 0.12)).Position or (st.cf * CF(0, -d.H * 0.3, -d.L * 0.5 - 0.8)).Position
      cam.CFrame = CFrame.lookAt(eye, eye + eoDir() * 100)
    elseif st.uav and st.dcam == "nose" then
      -- 无人机前视光电（机头下面的光电球）：顺着鼠标想去的方向看（手机上就是机头方向），不画镜头抖动
      local eye = (st.cf * CF(0, -d.H * 0.22, -d.L * 0.5 - 0.8)).Position
      local look = G.mobile and st.cf.LookVector or aimDirNow()
      cam.CFrame = CFrame.lookAt(eye, eye + look * 100)
    elseif d.kind == "jet" and st.pilot then
      -- 镜头钉在飞机后上方、顺着机头看（用户 11-21：飞行方向标志应该固定位置）：机头前方的全息标记一直在屏幕正中，
      --   鼠标推的准星圈在画面里走（原来镜头顺着鼠标瞄准方向看，标记跟着机头在画面里到处跑）；手机上一样
      local fwd0 = st.cf.LookVector
      local upY = st.cf.UpVector.Y
      local kwT = 0.7 * clamp((0.97 - math.abs(fwd0.Y)) / 0.25, 0, 1) * clamp((upY + 0.3) / 0.6, 0, 1)
      st.camUpK = (st.camUpK or kwT) + (kwT - (st.camUpK or kwT)) * math.min(1, dt * 2.5)
      local fwd, upC = jetCamBasis()
      -- 机头标记跟着机动小幅位移（用户 11-21：像 MWT 那样视角里有个会位移的飞机小标志）：镜头的朝向慢半拍跟上机头——
      --   一阶平滑（不会来回晃），最多偏 7°；压杆转弯时标记往转的那边挪一点，松杆回到正中。原来镜头死钉在机头上，标记一动不动；
      --   再原来镜头跟着鼠标瞄准方向，标记在画面里到处跑（偏 229 像素、来回摆四次，用户嫌乱）
      do
        local noseF = fwd
        local cf2 = noseF
        if st.camF and st.camF:Dot(noseF) > 0.5 then
          cf2 = st.camF:Lerp(noseF, 1 - math.exp(-dt * 4.5))
          cf2 = (cf2.Magnitude > 1e-3) and cf2.Unit or noseF
          local MAXA = rad(7)
          if cf2:Dot(noseF) < math.cos(MAXA) then
            local axis = noseF:Cross(cf2)
            if axis.Magnitude > 1e-6 then cf2 = CFrame.fromAxisAngle(axis.Unit, MAXA):VectorToWorldSpace(noseF) end
          end
        end
        st.camF = cf2
        fwd = cf2
      end
      -- 鼠标转视角：镜头绕着飞机转到鼠标拨到的方向，停在那里；鼠标 2.5 秒不动才慢慢回到身后（无人机照旧马上回）
      if st.uav or os.clock() - (st.lookT or 0) > 2.5 then
        local kk = math.exp(-dt * (st.uav and 5 or 2.2))
        st.lookYaw = (st.lookYaw or 0) * kk
        st.lookPitch = (st.lookPitch or 0) * kk
      end
      if math.abs(st.lookYaw or 0) + math.abs(st.lookPitch or 0) > 1e-3 then
        fwd = CFrame.fromAxisAngle(upC, st.lookYaw):VectorToWorldSpace(fwd)
        local rt2 = fwd:Cross(upC)
        if rt2.Magnitude > 1e-3 then fwd = CFrame.fromAxisAngle(rt2.Unit, st.lookPitch):VectorToWorldSpace(fwd) end
      end
      -- 用户：视角要离飞机近一点（最早一倍半机身长再往后 26 格；11-18 改成 0.85 倍 + 12 格；11-18 晚又说再近一点）：
      --   现在 0.62 倍 + 6 格（歼-20 从 60 格到 41 格），按机身长和七成翼展里大的算——B-2 这种翼展比机身长得多的，镜头转到侧面不钻进机翼
      local size = math.max(d.L, d.W * 0.7)
      local back = size * 0.62 + 6
      -- 镜头的位置带弹簧慢半拍跟上，加速度把镜头往反方向甩开一点（转弯时飞机在画面里往外偏、拉起时往下沉）；大过载、加力时轻轻抖。
      --   看的方向一直是机头前方 300 格那一点（全息标记就在那里），位置怎么甩标记都在正中
      local want = -fwd * back + upC * (d.H * 0.45 + 2.5)
      st.camOff = st.camOff and st.camOff:Lerp(want, 1 - math.exp(-dt * 7)) or want
      local acc = st.accV or V()
      local push = -acc * 0.014
      if push.Magnitude > 5 then push = push.Unit * 5 end
      st.camPush = (st.camPush or push):Lerp(push, 1 - math.exp(-dt * 4))
      local camPos = pos + st.camOff + st.camPush
      local gl = acc.Magnitude / GR   -- 大概几个 g
      local amp = math.clamp((gl - 3) * 0.0016, 0, 0.012) + ((st.thrE or 0) > 100 and 0.0012 or 0)
      local t = os.clock()
      -- 抖振（用户 11-20：载具照 UE5 的水平升级）：迎角大（12° 以上）、快失速时机身一阵阵发抖——镜头高频抖、一层低沉的嗡嗡声
      local buf = 0
      if not st.ground then
        local aoaK = math.clamp((math.abs(st.aoaDeg or 0) - 12) / 12, 0, 1)
        local stallK = math.clamp((d.stall * 1.3 - st.spd) / math.max(d.stall * 0.3, 1), 0, 1)
        buf = math.max(aoaK, stallK)
      end
      st.buffet = buf
      if st.buffetSnd then
        st.buffetSnd.Volume = buf * 1.4
        st.buffetSnd.PlaybackSpeed = 0.32 + buf * 0.12
      end
      local ab = buf * 0.006 * (0.6 + 0.4 * math.abs(math.noise(t * 3, 9.9)))
      local shake = CFrame.Angles(math.noise(t * 18, 1.3) * amp + math.noise(t * 34, 2.6) * ab, math.noise(t * 18, 7.1) * amp + math.noise(t * 31, 5.3) * ab,
        math.noise(t * 29, 3.7) * ab * 0.6)
      cam.CFrame = CFrame.lookAt(camPos, pos + fwd * 300, upC) * shake
    elseif d.kind == "jet" then
      local camPos = (st.cf * CF(0, d.H * 0.5 + 3, math.max(d.L, d.W * 0.7) * 0.65 + 7)).Position   -- 手机 / 坐后面的：也近一点
      cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, (st.cf * CF(0, 4, -300)).Position), math.min(1, dt * 8))
    else
      -- 直升机：弹簧臂（VehCam.lua，用户 11-20：照 UE5 的水平升级）——跟随有惯性（加速、急停、拉起有推拉），跟着机身坡度歪两成，
      --   旋翼的细震（越使劲越抖）；臂碰到山坡、房子平滑缩近
      local dirCam = CFrame.Angles(0, st.camYaw, 0) * CFrame.Angles(st.camPitch, 0, 0)
      local load = math.clamp(math.abs(st.c.col or 0), 0, 1)
      local camCF, camShake, fov = G.vehCam({ key = "heli", pivot = pos + V(0, d.H * 0.45, 0), dir = dirCam, dist = d.L * 0.62 + 7, up = 0, vel = st.vel, dt = dt,
        rough = 0.45 + 0.6 * load, speedK = math.clamp(0.35 + st.vel.Magnitude / math.max(d.vMax, 1) * 0.65, 0, 1.2), up3 = st.cf.UpVector, params = heliCamParams,
        fov0 = 70, fovK = 3, pushK = 0.03, maxPush = 3, follow = 8, maxLag = 3 })
      cam.CFrame = camCF * camShake
    end
    -- 视野：固定翼越快越宽；光电吊舱 / 无人机前视按倍率收（另一会话：开火时镜头抖、视野收一点，打中时再猛跳一下）
    local fovT = (d.kind == "jet") and math.clamp(70 + st.spd / d.vMax * 10, 70, 82) or 70
    if (st.uav and st.dcam == "nose") or st.eo then fovT = 70 / st.zoomS end
    st.fov = st.fov or cam.FieldOfView
    st.fov += (fovT - st.fov) * math.min(1, dt * ((st.uav and 10) or 4))
    local kick = (st.eo and 0) or ((st.recoil or 0) * 0.8 + (st.hitKick or 0))
    if kick > 0.01 then
      local t = os.clock()
      local a = math.rad(0.32) * kick
      cam.CFrame = cam.CFrame * CFrame.Angles(math.noise(t * 31, 1.3) * a, math.noise(t * 27, 7.1) * a, math.noise(t * 23, 4.7) * a * 0.5)
    end
    cam.FieldOfView = st.fov - (st.eo and 0 or (1.6 * (st.recoil or 0) + 1.2 * (st.hitKick or 0)))
    -- 瞄准点：镜头中间（固定翼：鼠标瞄准方向）打出去碰到的地方
    local ex = { G.viewFolder }
    if me.Character then table.insert(ex, me.Character) end
    table.insert(ex, st.em)
    aimParams.FilterDescendantsInstances = ex
    local adir = lookDir()
    local o = (d.kind == "jet" and not st.eo) and pos or cam.CFrame.Position
    local far = (st.eo or st.uav) and 24000 or 9000   -- 光电吊舱、前视光电看得远（八公里多）
    local res = workspace:Raycast(o + adir * (d.L * 0.6), adir * far, aimParams)
    st.aimPt = res and res.Position or (o + adir * far)
    if d.kind == "jet" and st.pilot and not st.uav and not st.eo and not st.crashed then   -- 机炮黏住目标：瞄准点换成目标的提前量（发给服务器）
      st.stick = gunStick()
      if st.stick then st.aimPt = st.stick.lead end
    else
      st.stick = nil
    end
    do   -- 瞄准点打在哪个实体上（吊舱页面的 POINT 跟踪框）
      local hm = res and res.Instance and res.Instance:FindFirstAncestorOfClass("Model")
      st.aimEnt = (hm and hm ~= st.em and hm:GetAttribute("EntId") ~= nil) and hm or nil
    end
    -- 机头炮塔：跟着瞄准点转（鼠标瞄）
    local gid, gw = gunW()
    local wid, w = storeW()
    if d.gunPos and gw and gw.turret then
      local vw = G.views and G.views[st.em]
      local l = st.cf:PointToObjectSpace(st.aimPt) - ((vw and vw.M and vw.M.gunPiv) or d.gunPos)   -- 原模型拆出了机炮：按它的耳轴算
      st.ty = clamp(deg(math.atan2(l.X, -l.Z)), -110, 110)
      st.gp = clamp(deg(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z))), -60, 11)
    end
    st.c.ty, st.c.gp = st.ty, st.gp
    -- 弹舱门
    local bm, bs = false, false
    if wid then bm, bs = bayOf(wid) end
    st.bay = approach(st.bay, bm and 1 or 0, dt * 2.5)
    st.bayS = approach(st.bayS, bs and 1 or 0, dt * 2.5)
    st.c.bay, st.c.bayS = st.bay, st.bayS
    -- 开火：鼠标左键 机炮按住连发（扳机发给服务器）；F 挂的弹一下一发（火箭按住连发）。没有炮的飞机左键也发挂的弹
    --   手机：开火键按选中的那种（选的是炮就打炮）
    if st.pilot then
      local _, cw = curW()
      local touchGun = touch and touch.fire and cw and cw.kind == "gun"
      local gunOn = gid ~= nil and ((st.firing and not G.mobile) or touchGun or false)
      if gid then setTrig(gunOn) end
      local fireS = st.missile or (st.firing and not gid) or (touch and touch.fire and not touchGun)
      if w and fireS then
        if w.kind == "rkt" or not st.fireLatch then fireStore(wid, w) end
        st.fireLatch = true
      else
        st.fireLatch = false
      end
    end
    -- 锁定：选中的弹要锁的话，目标在视场里待够锁定时间
    if st.pilot and w and (w.kind == "aam" or w.kind == "agm" or (w.kind == "bomb" and w.guided)) then
      if st.lock and (not st.lock.em.Parent or st.lock.em:GetAttribute("Wreck")) then st.lock = nil end
      if st.lock then
        local root = st.lock.em:FindFirstChild("Root")
        if root then
          local to = root.CFrame.Position - pos
          st.lock.dir, st.lock.dist, st.lock.pos = to.Unit, to.Magnitude, root.CFrame.Position
          -- 在离轴角里：锁定进度往上走；出了离轴角、还在跟踪范围里：锁留着（菱形变黄、不能发射，进度不涨），偏出去 4 秒才丢
          local inside = inCone(w, st.lock)
          if st.lock.dist < (w.range or 3200) * 1.1 and (inside or inTrack(w, st.lock)) then
            st.lock.out = not inside
            if inside then
              st.lockT += dt
              st.lock.outT = 0
            else
              st.lock.outT = (st.lock.outT or 0) + dt
              if st.lock.outT > 4 then st.lock, st.lockT = nil, 0 end
            end
          else
            st.lock, st.lockT = nil, 0
          end
        else
          st.lock = nil
        end
      end
      if not st.lock then
        st.lock = pickTarget(w)
        st.lockT = 0
      end
    else
      st.lock, st.lockT = nil, 0
    end
    -- 报给服务器（每秒 15 次）
    -- 热诱弹：按住 X（手机按住 X 键）每 0.3 秒放一组
    if st.pilot and (st.flareHold or (touch and touch.flare)) and os.clock() >= (st.flareNext or 0) and (st.flares or 0) > 0 then
      st.flareNext = os.clock() + 0.3
      G.R.Drive:FireServer({ op = "flare" })
    end
    st.sendT -= dt
    if st.sendT <= 0 and st.pilot and not st.crashed then
      st.sendT = math.max(st.sendT + 1 / 15, 0)   -- 按平均每秒 15 次（原来每次重设，帧率低时间隔拖成两三帧）
      local c = st.c
      G.R.Drive:FireServer({ op = "state", cf = st.cf, v = st.vel, gd = st.ground, aim = st.aimPt, stk = st.stick ~= nil, thr = c.thr, gear = c.gear, flap = c.flap, cp = c.pit, cr = c.rol,
        cy = c.yaw, bay = c.bay, bays = c.bayS, rpm = c.rpm, col = c.col, can = c.can, hook = c.hook, brk = c.brk, ty = c.ty, gp = c.gp, fold = c.fold })
    end
    -- 平显
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    aName.Text = T("veh." .. d.id) .. (st.pilot and "" or ("   " .. T("air.passenger")))
    local kmh = math.floor(st.vel.Magnitude / AD.M * 3.6 + 0.5)
    local agl = math.floor((pos.Y - ground(pos.X, pos.Z) - d.gearH) / AD.M + 0.5)
    st.aglM, st.kmh = agl, kmh   -- 离地高度（米）、速度（km/h）：Coach.lua 看要不要提示放起落架
    aInfo.Text = T("ui.speed", kmh) .. "    " .. T("air.alt", math.max(0, agl)) .. "    " .. T("air.flares", st.flares) .. "    " .. T("air.fuelP", math.floor((st.fuel + st.fuelX) * 100 + 0.5))
      .. ((d.kind == "jet") and ("    " .. T("air.gearState." .. ((st.gearWant > 0.5) and "down" or "up"))) or "")
    if wid then
      aWpn.Text = "F  [" .. st.wi .. "/" .. #st.wl .. "] " .. T("aw." .. wid) .. "  ×" .. left(wid) .. (gid and ("    " .. T("air.mouseGun", T("aw." .. gid), left(gid))) or "")
    elseif gid then
      aWpn.Text = T("air.mouseGun", T("aw." .. gid), left(gid))
    else
      aWpn.Text = T("air.noWeapon")
    end
    st.help = st.pilot and (st.uav and "air.helpUav" or ((d.kind == "jet") and "air.helpJet" or "air.helpHeli")) or "air.helpPass"
    -- 开飞机的界面（AirHud.lua，照 MWT 的截图）要的数：这一帧算出来的塞进 info，最后交给 G.airHudStep
    local info = { d = d, pilot = st.pilot == true, hp = hp, mx = mx, kmh = kmh, agl = agl }
    if st.pilot then
      spdText.Text = string.format("%d", kmh)
      altText.Text = string.format("%d", math.max(0, agl))
      thrText.Text = (d.kind == "jet") and ((st.thr > 100) and T("air.ab") or (string.format("%d%%", math.floor(st.thr + 0.5)) .. (st.apc and ("  " .. T("air.apc")) or ""))) or string.format("RPM %d%%", math.floor(st.rpm))
      vsText.Text = string.format("%+d", math.floor(st.vel.Y / AD.M + 0.5))
      -- 油量：内油 %（+ 副油箱 %）、照现在的油门还能飞几分几秒；少于两成半变黄、一成变红
      local tot = st.fuel + st.fuelX
      local rate = AD.burn(d, (d.kind == "heli") and 100 or st.thr, st.c.col or 0, (d.kind == "heli") and st.rpm or st.thr, st.vel.Magnitude / math.max(d.vMax, 1), st.ground)
      local secs = (rate > 0) and tot / rate or math.huge
      local left2 = (secs < 5999) and string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60)) or "--:--"
      fuelText.Text = T("air.fuel", math.floor(st.fuel * 100 + 0.5)) .. ((st.fuelX > 0) and string.format(" +%d", math.floor(st.fuelX * 100 + 0.5)) or "") .. "  " .. left2
      fuelText.TextColor3 = (tot < 0.1) and RGB(255, 90, 80) or ((tot < 0.25) and RGB(255, 200, 90) or HUD)
      info.fuel = T("air.fuelLeft", math.floor(tot * 100 + 0.5), left2)
      info.fuelCol = (tot < 0.1) and RGB(255, 90, 80) or ((tot < 0.25) and RGB(255, 200, 90) or nil)
      info.thr = thrText.Text
      info.vs = T("air.vs", vsText.Text)
      info.gear = (d.kind == "jet" and st.gearWant > 0.5) and T("air.gearState.down") or nil
      local bp, bon = project(pos + st.cf.LookVector * 400)
      bore.Position, bore.Visible = bp, bon and not st.eo
      G.try_(dcsHud, pos, kmh)
      -- 命中标记标在炮口指的地方（固定的航炮顺着机头打；机头炮塔跟着瞄准圈），打中时这个准星放大一下、变红（另一会话）
      G.hitMarkerAt = gw and (gw.turret and (G.mobile and UDim2.fromScale(0.5, 0.5) or aimRing.Position) or bp) or nil
      local hk = math.min(1, st.hitKick or 0)
      bore.TextSize = 34 + 14 * hk
      bore.TextColor3 = Color3.new(1, 1 - 0.7 * hk, 1 - 0.75 * hk)
      info.hk, info.cf = hk, st.cf
      -- 大圈：圈心在机头指向；大小是选中武器能锁的离轴角（导弹的导引头）/ 航炮、火箭、炸弹的瞄准圈；圈底下写武器和剩几发
      local rdeg = (not w and 3) or (w.kind == "rkt" and 5) or (w.kind == "bomb" and 9) or (w.cone or 20)
      if d.kind == "heli" and w and w.kind == "agm" then rdeg += 20 end
      local vh = cam.ViewportSize.Y
      -- 用户：圈太小、挡视野——原来按导引头离轴角画，小的只有一两百像素、正好套在飞机和前方上；现在至少框到画面高度的八成，
      --   飞机和前方留空，离轴角大的弹（近距格斗弹）再大一点；武器名写在圈里靠下
      local px = clamp(vh / math.tan(rad(cam.FieldOfView / 2)) * math.tan(rad(math.min(rdeg, 55))), vh * 0.8, vh * 0.94)
      ring.Size, ring.Position, ring.Visible = UDim2.fromOffset(px, px), bp, bon and not st.eo and not st.uav
      ringText.Position, ringText.Visible = bp + UDim2.fromOffset(0, px / 2 - 30), bon and not st.eo and not st.uav
      ringText.Text = wid and (T("aw." .. wid) .. "  ×" .. left(wid)) or (gid and (T("aw." .. gid) .. "  ×" .. left(gid))) or ""
      local lk = st.cf.LookVector
      hdgText.Text = string.format("%03d", math.floor((math.deg(math.atan2(lk.X, -lk.Z)) + 360) % 360 + 0.5) % 360)
      -- 右侧武器栏：剩几发、选中的那行亮、打光了变灰
      for _, r in ipairs(wRows) do
        local n = r.it.flare and st.flares or left(r.it.wid)
        r.cnt.Text = "×" .. n
        local sel = r.it.idx == st.wi
        r.f.BackgroundColor3, r.f.BackgroundTransparency = sel and RGB(18, 78, 36) or RGB(0, 16, 6), sel and 0.3 or 0.6
        r.s.Transparency, r.s.Thickness = sel and 0 or 0.7, sel and 2 or 1
        local col = (n <= 0) and RGB(110, 124, 130) or HUD
        r.cnt.TextColor3, r.nm.TextColor3 = col, col
      end
      -- 六边形武器键（AirHud）：每种挂载一个（按键号、剩几发、选中的亮），最后一个热诱弹；准星上方写选中的那种
      local items = {}
      for i, wid2 in ipairs(st.wl) do items[i] = { key = tostring(i), wid = wid2, w = AD.W[wid2], n = left(wid2), sel = i == st.wi } end
      items[#items + 1] = { key = "X", flare = true, n = st.flares }
      info.wl = items
      local cw, cww = curW()
      info.wid, info.w, info.cnt = cw, cww, cw and left(cw) or 0
      -- 光电画面的字：模式、倍率、目标距离、吊舱相对机头的方位 / 俯仰
      if st.eo then tgpStep(pos, wid, w) end
      if st.eo or (st.uav and st.dcam == "nose") then
        aimRing.Visible = false   -- 光电 / 前视光电：镜头就是瞄准方向，画十字线
      elseif d.kind == "jet" and not G.mobile and st.uav then   -- 无人机：小十字是机头（bore），圆圈是鼠标瞄准（飞机往圆圈那边转）
        local ap, aon = project(pos + aimRingDir() * 400)
        aimRing.Position, aimRing.Visible = ap, aon
      elseif d.kind == "jet" then
        -- 机炮黏住了目标（用户 11-21：像 MWT 那样）：准星圈画在提前量那一点上、转着；没黏住不画（瞄准就是机头标记）
        if st.stick and st.stick.lead and st.pilot then
          local ap, aon = project(st.stick.lead)
          aimRing.Position, aimRing.Visible = ap, aon
        else
          aimRing.Visible = false
        end
      else
        aimRing.Position, aimRing.Visible = UDim2.fromScale(0.5, 0.5), d.kind == "heli"
      end
      -- 警告
      local warn = nil
      if st.rwrT and os.clock() < st.rwrT then warn = ((os.clock() * 4) % 1 < 0.6) and T("air.missile") or ""
      elseif st.out and not st.ground then warn = T("air.flameout")
      elseif st.oob then warn = T("air.oob")
      elseif d.kind == "jet" and not st.ground and st.spd < d.stall * 1.05 then warn = T("air.stall")
      elseif os.clock() - (st.floatT or -9) < 0.6 then warn = T("air.tooFast")   -- 接地太快、贴着跑道飘：收油门
      elseif not st.ground and agl < 60 and st.vel.Y < -25 then warn = T("air.pullup")
      elseif not st.ground and st.fuel + st.fuelX < 0.12 then warn = ((os.clock() * 2) % 1 < 0.6) and T("air.bingo") or "" end   -- 油不多了：该回去了
      warnText.Text = warn or ""
      warnText.Visible = warn ~= nil
      -- 落地补给（用户：降落回去可以回血、补武器）：服务器 Rest 属性——1～5 停稳倒计时、10 在自己的机场还在滑、
      --   −1 补完了正在修、−2 全好了、−3 这里不是自己的机场 / 甲板
      local rest = st.ground and em:GetAttribute("Rest") or 0
      local rtx, rcol = nil, RGB(120, 230, 140)
      if type(rest) ~= "number" or rest == 0 then rtx = nil
      elseif rest > 0 and rest <= 5 then rtx = T("air.restWait", math.floor(rest))
      elseif rest == 10 then rtx = T("air.restRoll")
      elseif rest == -1 then rtx = T("air.restFix", math.floor(clamp(hp / mx, 0, 1) * 100))
      elseif rest == -2 then rtx = T("air.restDone")
      elseif rest == -3 and math.abs(st.spd) < 30 then rtx, rcol = T("air.restNo"), RGB(255, 200, 90) end
      restText.Text, restText.TextColor3, restText.Visible = rtx or "", rcol, rtx ~= nil
      -- 降落引导：起落架放着、在天上：最近的能落的地方画个菱形，旁边写公里数；菱形按下滑道（3.5°）变色——绿正好、黄偏高、红偏低
      local site = nil
      if d.kind == "jet" and not st.ground and st.gearWant > 0.5 then
        local bd = math.huge
        for _, s2 in ipairs(landSites()) do
          local dd = (V(s2.p.X, 0, s2.p.Z) - V(pos.X, 0, pos.Z)).Magnitude
          if dd < bd then site, bd = s2, dd end
        end
        if site then
          local lp, lon = project(site.p + V(0, 1, 0))
          landMark.Position, landMark.Visible = lp, lon
          landText.Position, landText.Visible = lp + UDim2.fromOffset(0, 22), lon
          local ideal = bd * math.tan(rad(3.5))
          local dh = (pos.Y - d.gearH - site.p.Y) - ideal
          local tol = ideal * 0.35 + 18
          local col = (dh > tol) and RGB(255, 200, 90) or ((dh < -tol) and RGB(255, 90, 80) or RGB(120, 230, 140))
          landMark.TextColor3, landText.TextColor3 = col, col
          landText.Text = string.format("%.1f", bd / AD.M / 1000)
        end
      end
      if not site then landMark.Visible, landText.Visible = false, false end
      -- 锁定框
      if st.lock then
        local lp, lon = project(st.lock.pos)
        local locked = st.lockT >= (w.lockTime or 1)
        lockBox.Position, lockBox.Visible = lp, lon
        lockStroke.Color = locked and RGB(255, 80, 70) or HUD
        lockBox.Size = locked and UDim2.fromOffset(38, 38) or UDim2.fromOffset(52, 52)
        lockText.Position = lp + UDim2.fromOffset(0, 30)
        lockText.Visible = lon
        -- 距离：MWT 式界面写在准星左边（AirHud），这里只写锁定的状态；无人机照旧带距离
        lockText.Text = locked and (T("air.locked") .. (st.uav and string.format("  %dm", math.floor(st.lock.dist / AD.M)) or "")) or T("air.locking", math.floor(st.lockT / (w.lockTime or 1) * 100))
        lockText.TextColor3 = locked and RGB(255, 80, 70) or HUD
        info.lockDist = st.lock.dist
        info.lock = { p = lp, on = lon, k = st.lockT / (w.lockTime or 1), locked = locked, inCone = not st.lock.out }
        if not st.uav then lockBox.Visible, lockText.Visible = false, false end   -- MWT 式界面：AirHud 画菱形和四个直角
      else
        lockBox.Visible, lockText.Visible = false, false
      end
      -- 炸弹落点（不制导的、或者没锁上的制导炸弹）
      if w and w.kind == "bomb" and not (st.lock and st.lockT >= (w.lockTime or 1)) then
        local h = pos.Y - math.max(ground(pos.X, pos.Z), 0)
        local vy = -st.vel.Y
        local tf = (vy + math.sqrt(math.max(0, vy * vy + 2 * GR * math.max(h, 0)))) / GR
        local hit = pos + V(st.vel.X, 0, st.vel.Z) * tf * 0.97
        local gp2, gon = project(V(hit.X, ground(hit.X, hit.Z), hit.Z))
        pipper.Position, pipper.Visible = gp2, gon
      else
        pipper.Visible = false
      end
      if st.eo then   -- 吊舱画面里：平显的落点、降落菱形、锁定框都收起来（吊舱自己画跟踪框）
        pipper.Visible, landMark.Visible, landText.Visible, lockBox.Visible, lockText.Visible, restText.Visible = false, false, false, false, false, false
      end
    end
    -- MWT 式的界面（AirHud.lua）：有人开 / 坐的飞机都用；遥控无人机（战术平板）、光电吊舱的画面不用
    if not st.uav then dcs.Visible = false end
    warnText.Position = UDim2.new(0.5, 0, 0.5, st.uav and -130 or -172)   -- 告警：让开准星上方的武器名牌
    if not st.uav and not st.eo then
      if st.pilot then info.aim = aimRing.Visible and aimRing.Position or nil end   -- 准星由 AirHud 画（发光的细圈），这里的「◯」字收起来
      aimRing.Visible = false
      if G.airHudStep then G.try_(G.airHudStep, st, info) end
      if G.tankHudExtra then G.try_(G.tankHudExtra, st, clamp(hp / mx, 0, 1), "air") end   -- 左上圆形雷达、「被发现!」、敌人头顶带血条的名牌（TankHud.lua）
    elseif G.airHudOff then
      G.airHudOff()
    end
  end

  -- 被击毁 / 跳伞：服务器推来 alive = false 或 veh = nil，下一帧 stop()
end

return Fly
