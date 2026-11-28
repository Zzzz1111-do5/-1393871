-- Roblox全面大战场（客户端）——飞机、直升机：样子和驾驶
--   样子（G.viewKind.air，View.lua 每帧调）：AirModels 按型号拼零件；位置平滑跟着服务器的 Root，舵面、起落架、弹舱、座舱盖、旋翼按实体属性
--     （Thr、Gear、Pit、Rol、Yaw、Bay、BayS、Rpm、Ty、Gp……）摆；自己开的用本地的；被击毁的往下掉、冒火冒黑烟，落地炸一下
--   驾驶（服务器推来的 S.veh.air）：位置在本地算，每秒 15 次报给服务器（Air.lua 查速度、查撞地）
--     固定翼（用户 11-21：改成 WASD 控制方向、不要准心控制；飞机太灵活）：键盘就是驾驶杆——S 拉杆抬头、W 推杆低头、A / D 滚转、
--       Q / E 方向舵（杆量按住 0.25～0.3 秒匀速推满、松开回中），Shift / Ctrl 油门（推满再推进加力，↑ / ↓ 同样）；松杆 1 g，小坡度自己慢慢摆平；
--       镜头钉在机身后上方顺着机头看，机头前方的全息标记一直在屏幕正中（航炮就打那里）；按住 Alt 鼠标自由看；
--       滚转、俯仰角速度和最大过载收到真飞机的五六七成（AGIL）。无人机（平板上飞）照旧鼠标给方向、W / S 油门；
--       开着光电吊舱、飞出作战区自动掉头时也是按给的方向自动飞（教官）；
--       速度不够失速（机头往下掉）、爬升掉速、俯冲加速、拉杆转弯掉能量；跑道 / 甲板上：油门加速，速度够了按 S 抬头离地；
--       放着起落架、下沉不快、速度不快、姿态平就能落地（落在自己的机场 / 甲板上停 5 秒补弹修理）
--     直升机（11-28 起照战雷的鼠标瞄准）：鼠标准心定方向（往下往前飞、往上减速）、W 升 / S 降、A / D 侧飞、Q / E 转机头（快的时候压坡度转弯），旋翼先转起来才飞得动；机头炮塔跟着镜头瞄
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
  -- 固定翼的飞行物理（用户 11-26 晚：「每个飞机要有不同的参数」「现在飞机驾驶感觉过于灵敏」）：FlightModel.lua 的六自由度——
  --   每型按自己的重量、推力、翼面积、升力、阻力、过载 / 失速迎角、转动惯量、稳定性、阻尼飞；原来「滚转 / 俯仰角速度乘个系数」（AGIL）的手调法去掉了
  local FM = require(RS:WaitForChild("FlightModel"))
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
  local flStart, flStop   -- 自由视角（下面定义）
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

  -- 转的东西（旋翼、尾桨、螺旋桨、风扇、涡轮）每帧转多少：一帧最多转过叶片间隔的四成（用户 11-26「飞机发动机有 bug」）——
  --   一帧转过半个间隔以上，眼睛看到的就是停住、倒着转（车轮效应）：原来涡轮满油门一帧转 40°（18 片叶片正好两个间隔），
  --   推满油门涡轮反而不动、往回转；A-10 的风扇一帧 54°（14 片，两个间隔多）也是；帧率低时旋翼、尾桨也会这样
  local function spinStep(cur, rate, nBlades, dt)
    return ((cur or 0) + math.min(rate * dt, 0.4 * (2 * math.pi / math.max(nBlades, 1)))) % (math.pi * 2)
  end
  local CH = { thr = "Thr", gear = "Gear", flap = "Flap", pit = "Pit", rol = "Rol", yaw = "Yaw", bay = "Bay", bayS = "BayS", rpm = "Rpm", col = "Col", can = "Can",
    hook = "Hook", brk = "Brk", ty = "Ty", gp = "Gp", fold = "Fold" }

  ---------------------------------------------------------------- 被击毁的飞机：坠落（用户 11-23：把宣传片里的动画做进游戏）
  --   照片子里阿帕奇被防空车打中的样子——直升机：尾桨没了，机身越转越快（一开始每秒 2 弧度多、往上加到 9）、机头往下栽、左右晃，
  --     尾梁上一团火、拖着一长条黑烟往下掉；固定翼：顺着速度栽下去、慢慢滚转，发动机那里拖着火和黑烟；砸到地上炸开，残骸躺在地上接着烧十几秒。
  --   原来服务器 4 秒后就把实体收了，高处打下来的掉到一半凭空没了：收了以后这里接着演完（viewKind.air.remove 留下、falling 每帧接着动）
  local falling = {}
  G.airFalling = falling   -- 测试用
  local function wreckStart(v, vel)
    local d, M = v.def, v.M
    local heli = d.kind == "heli"
    local lv = v.cf.LookVector
    v.wreck = { vel = vel, t = 0, heli = heli, spin = (math.random() - 0.5) * 3, yaw = math.atan2(-lv.X, -lv.Z),
      pitch = math.asin(clamp(lv.Y, -1, 1)) }
    local W = v.wreck
    if M then M.dark = true end   -- 被击毁：灯全灭
    for _, it in ipairs(M.items) do
      local p = it.p
      if p:IsA("MeshPart") then   -- 原模型：贴图盖住颜色，烧黑要先把贴图去掉
        for _, sa in ipairs(p:GetChildren()) do if sa:IsA("SurfaceAppearance") then sa:Destroy() end end
        pcall(function() p.TextureID = "" end)
        if p.Transparency < 1 then p.Color = Color3.fromRGB(40, 38, 36) end
      elseif p:IsA("BasePart") and p.Transparency < 1 then p.Color = p.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.6) end
    end
    -- 火、黑烟：挂在尾梁（直升机）/ 尾喷口（固定翼）上的一个看不见的零件，粒子留在世界里，自然拖成一条
    local h = Instance.new("Part")
    h.Name = "WreckFire"
    h.Anchored, h.CanCollide, h.CanQuery, h.CanTouch, h.CastShadow = true, false, false, false, false
    h.Transparency, h.Size = 1, V(0.4, 0.4, 0.4)
    h.Parent = v.model
    local fire = Instance.new("ParticleEmitter")
    fire.Texture = "rbxasset://textures/particles/fire_main.dds"
    fire.Rate = 70
    fire.Lifetime = NumberRange.new(0.25, 0.6)
    fire.Speed = NumberRange.new(2, 7)
    fire.SpreadAngle = Vector2.new(35, 35)
    fire.LightEmission = 1
    fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(0.4, 5.5), NumberSequenceKeypoint.new(1, 1.5) })
    fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
    fire.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 236, 180)), ColorSequenceKeypoint.new(0.45, RGB(255, 140, 50)), ColorSequenceKeypoint.new(1, RGB(90, 30, 15)) })
    fire.Parent = h
    local smoke = Instance.new("ParticleEmitter")
    smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
    smoke.Rate = 26
    smoke.Lifetime = NumberRange.new(3.5, 6)
    smoke.Speed = NumberRange.new(1, 4)
    smoke.SpreadAngle = Vector2.new(25, 25)
    smoke.Drag = 0.6
    smoke.Acceleration = V(0, 2.5, 0)
    smoke.Rotation = NumberRange.new(0, 360)
    smoke.RotSpeed = NumberRange.new(-25, 25)
    smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 24) })
    smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
    smoke.Color = ColorSequence.new(RGB(38, 34, 30))
    smoke.Parent = h
    local light = Instance.new("PointLight")
    light.Color, light.Range, light.Brightness, light.Shadows = RGB(255, 140, 60), 34, 4, false
    light.Parent = h
    W.h, W.fire, W.smoke, W.light = h, fire, smoke, light
    W.hold = heli and CF(0, d.H * 0.18, d.L * 0.36) or CF(0, 0, d.L * 0.46)   -- 尾梁 / 尾喷口（机头是 −Z）
  end
  local function wreckMove(v, dt)
    local W, d = v.wreck, v.def
    if not W then return end
    W.t += dt
    if W.down then   -- 躺在地上烧：火慢慢小下去
      W.burn = (W.burn or 0) + dt
      local k = math.max(0, 1 - W.burn / 15)
      if W.fire then W.fire.Rate = 45 * k end
      if W.smoke then W.smoke.Rate = 6 + 14 * k end
      if W.light then W.light.Brightness = 3 * k * (0.8 + 0.2 * math.sin(os.clock() * 13)) end
      return
    end
    W.vel += V(0, -GR, 0) * dt
    W.vel = V(W.vel.X * (1 - (W.heli and 0.35 or 0.1) * dt), W.vel.Y * (1 - 0.06 * dt), W.vel.Z * (1 - (W.heli and 0.35 or 0.1) * dt))
    local p = v.cf.Position + W.vel * dt
    local g = ground(p.X, p.Z)
    if p.Y < g + 1 then   -- 砸到地上：炸开，残骸躺下、歪着
      W.down = true
      p = V(p.X, g + 1, p.Z)
      if G.boom then G.boom(p, W.heli and 2.6 or 3, "wreck") end
      if G.flash then G.flash(p + V(0, 6, 0), RGB(255, 160, 70), 90, 18, 1.1) end
      v.cf = CF(p) * CFrame.Angles(0, W.yaw, 0) * CFrame.Angles(0.1, 0, W.heli and 0.5 or 0.2)
      if W.h then W.h.CFrame = v.cf * (W.heli and CF(0, 0, 0) or W.hold) end
      return
    end
    if W.heli then
      -- 尾桨没了：机身越转越快、机头往下栽、左右晃
      local rate = math.min(9, 2.2 + 3.2 * W.t)
      W.yaw += rate * dt
      local pitch = math.max(-0.6, -(0.12 + 0.08 * W.t))
      v.cf = CF(p) * CFrame.Angles(0, W.yaw, 0) * CFrame.Angles(pitch, 0, math.sin(W.t * 3) * 0.25)
    else
      local look = (W.vel.Magnitude > 5) and W.vel.Unit or v.cf.LookVector
      v.cf = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, W.t * W.spin)
      W.yaw = math.atan2(-look.X, -look.Z)
    end
    if W.h then W.h.CFrame = v.cf * W.hold end
  end
  -- 服务器收了实体以后接着演：落地烧够了再删
  G.frameConn("AirWreck", function(dt)
    if #falling == 0 then return end
    local now = os.clock()
    for i = #falling, 1, -1 do
      local v = falling[i]
      local ok = pcall(function()
        wreckMove(v, dt)
        local d = v.def
        if d.rotor and v.c and not (v.wreck and v.wreck.down) then   -- 主旋翼还在转（尾桨没了）
          v.spin1 = ((v.spin1 or 0) + 0.7 * d.rotor.rpm / 60 * math.pi * 2 * 0.3 * dt) % (math.pi * 2)
          v.c.spin1 = v.spin1
        end
        if v.M then AM.pose(v.M, v.cf, v.c or {}, now) end
      end)
      local W = v.wreck
      if not ok or not W or (W.down and (W.burn or 0) > 16) or W.t > 60 then
        if v.model then v.model:Destroy() end
        table.remove(falling, i)
      end
    end
  end)

  -- 阵亡镜头跟着自己那架往下掉的残骸（DeathFx.lua，用户 11-27「飞机被干掉后不要立马爆炸 先跟随视角」）：
  --   实体还在就是 View 里那一份，服务器收走以后在上面的 falling 里接着演
  G.airWreckView = function(id)
    if id == nil then return nil end
    local v = G.viewById and G.viewById(id)
    if v and v.def then return v end
    for _, f in ipairs(falling) do if f.id == id then return f end end
    return nil
  end

  G.viewKind = G.viewKind or {}
  G.viewKind.air = {
    importReady = function(v) return v.M ~= nil and not v.M.imported and v.def ~= nil and AM.importedFor(v.def) ~= nil end,   -- 原模型后来才复制齐：View 重建
    -- 实体被服务器收走：被击毁、还在往下掉 / 躺着烧的留下来接着演（上面的 falling），别的照常删
    remove = function(v)
      if v.wreck and not (v.wreck.down and (v.wreck.burn or 0) > 16) then
        if v.bb then v.bb:Destroy() v.bb = nil end
        table.insert(falling, v)
        return true
      end
      return false
    end,
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
      if em:GetAttribute("Wreck") then   -- 被击毁：坠落（wreckStart / wreckMove 在上面）
        if not v.wreck then wreckStart(v, (own and own.vel) or (v.fl and v.fl.vel) or V()) end
        wreckMove(v, dt)
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
      -- 发动机打坏了（WtAir WtaEng = 0）、油烧干了（Fuel = 0）、成了残骸：喷口里不再发亮、没有尾焰（原来照着油门一直喷）
      local engK = em:GetAttribute("WtaEng")
      local engDead = (engK ~= nil and engK <= 0) or em:GetAttribute("Fuel") == 0 or em:GetAttribute("Wreck") == true
      if engDead then c.thr = 0 end
      v.canS = approach(v.canS or c.can, c.can, dt * 0.7)   -- 座舱盖开关是 0 / 1：显示时一秒多一点慢慢掀开、合上
      c.can = v.canS
      v.foldS = approach(v.foldS or c.fold, c.fold, dt / 4.5)   -- 折叠机翼（用户：折叠机翼没有动画）：也是 0 / 1，显示时四秒多慢慢折起、展开
      c.fold = v.foldS
      local onGround = c.gear > 0.9 and (v.cf.Position.Y - ground(v.cf.Position.X, v.cf.Position.Z) - d.gearH) < 1.5
      c.door = (d.sideDoor and onGround) and 1 or 0
      c.ramp = (d.ramp and onGround) and 1 or 0
      -- 旋翼、螺旋桨转（看着慢一点，免得一格一格跳）
      local rpm = c.rpm or 0
      if d.rotor then v.spin1 = spinStep(v.spin1, rpm / 100 * d.rotor.rpm / 60 * math.pi * 2 * 0.3, d.rotor.blades or 4, dt) end
      if d.rotor2 then v.spin2 = spinStep(v.spin2, rpm / 100 * d.rotor2.rpm / 60 * math.pi * 2 * 0.3, d.rotor2.blades or 4, dt) end
      if d.tail then v.spinT = spinStep(v.spinT, rpm / 100 * 18, (type(d.tail) == "table" and d.tail.blades) or 4, dt) end
      if d.prop then   -- 推进式螺旋桨（MQ-9、攻击-2）：慢车也转（原来按油门，收了油门桨就停在半空）；打坏 / 没油几秒里慢下来，只剩迎风空转
        v.rpmP = approach(v.rpmP or 32, engDead and 8 or (32 + 0.68 * math.clamp(c.thr or 0, 0, 100)), (engDead and 10 or 45) * dt)
        v.spinP = spinStep(v.spinP, v.rpmP / 100 * 34, 3, dt)
      end
      if d.fanEng then v.spinF = spinStep(v.spinF, (0.25 + (c.thr or 0) / 100) * 9, 14, dt) end   -- 涡扇风扇（A-10）：慢车也转
      -- 喷气发动机的涡轮（AirModels 的发动机后段，18 片叶片）：跟着转速，慢车也转；
      --   发动机打坏 / 没油 / 成了残骸：转速几秒里掉到只剩风车转（原来照着油门接着转）
      if d.kind == "jet" and not d.prop then
        v.rpmJ = approach(v.rpmJ or rpm, engDead and 0 or math.clamp(rpm, 0, 110), (engDead and 25 or 70) * dt)
        v.spinJ = spinStep(v.spinJ, (0.12 + v.rpmJ / 100) * 7.6, 18, dt)
      end
      c.spin1, c.spin2, c.spinT, c.spinP, c.spinF, c.spinJ = v.spin1, v.spin2, v.spinT, v.spinP, v.spinF, v.spinJ
      c.rpmP = v.rpmP   -- 螺旋桨转速：AM.pose 按它让桨叶变虚、出桨盘
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
    local l = ui.label(gui, text, size, pos, ts or 16, HUD, Enum.Font.RobotoMono, anchor, align)
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
  local aName = ui.label(panel, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 6), 16, Color3.new(1, 1, 1), Enum.Font.BuilderSansMedium, nil, Enum.TextXAlignment.Left)
  local hpBg = ui.frame(panel, UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 30), RGB(0, 0, 0), 0.4)
  local hpBar = ui.frame(hpBg, UDim2.fromScale(1, 1), nil, RGB(90, 210, 110), 0)
  local aInfo = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 44), 14, Color3.new(1, 1, 1), Enum.Font.BuilderSans, nil, Enum.TextXAlignment.Left)
  local aWpn = ui.label(panel, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 62), 14, RGB(255, 220, 120), Enum.Font.BuilderSans, nil, Enum.TextXAlignment.Left)
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
    local labs = { ui.label(holder, "", UDim2.fromOffset(30, 14), UDim2.new(), 12, HUD, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5)), ui.label(holder, "", UDim2.fromOffset(30, 14), UDim2.new(), 12, HUD, Enum.Font.RobotoMono, Vector2.new(0.5, 0.5)) }
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
  local hdgText = ui.label(hdgBox, "", UDim2.fromScale(1, 1), nil, 18, HUD, Enum.Font.RobotoMono)
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

  -- 光电吊舱的画面（P 键）。用户 11-28「吊舱ui和战雷对其」：照战雷的瞄准吊舱画面重排（原来照 F-16 多功能显示器的 TGP 页：中间 4:3 的框、
  --   四边一圈 A-G / NARO / OVRD / SWAP / HSD 之类的按键字）——
  --   · 整屏就是吊舱的画面，四边一圈渐暗（镜头的暗角）；贯穿全屏的细十字，正中留空、空口两头各一小横，正中一个小点
  --   · 跟踪：看着车、船、飞机套 POINT 方框（按它在画面里多大），没跟踪是正中一个小 AREA 框，框下面写跟踪方式
  --   · 左上：模式（CCD / WHOT / BHOT）大字，下面倍率和视场角、对地 / 对空，再下面指北箭头和视线方位（右上留给小地图）
  --   · 下面正中：目标距离（公里）、激光编码；它左边：吊舱转角框（横着是方位、竖着是俯仰，亮点是吊舱看着的方向，上沿中间的刻度是机头）
  --     和俯视的小飞机（飞机往哪飞，相对吊舱看的方向）；右下：高度（米）、弹着时间（左下留给小队名单）
  --   · 右边一栏（小地图下面）：投放方式 · 武器、TTI 大字和进度条、投放状态、一句提示、按键说明
  local MFD = RGB(232, 234, 230)
  local MFD_DIM = RGB(150, 154, 150)
  local MOB = G.mobile == true
  local eoGui = ui.frame(gui, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  eoGui.Name = "EoView"
  eoGui.Visible = false
  eoGui.ZIndex = 10   -- 盖住平显（速度、高度框等）
  local TG = {}
  local disp = ui.frame(eoGui, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  disp.Name = "TgpDisplay"
  disp.ZIndex = 10
  do   -- 暗角：四边一圈渐暗
    for _, e in ipairs({ { UDim2.new(1, 0, 0.16, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.16, 0), UDim2.fromScale(0, 0.84), 270 },
      { UDim2.new(0.12, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0.12, 0, 1, 0), UDim2.fromScale(0.88, 0), 180 } }) do
      local f = ui.frame(disp, e[1], e[2], RGB(0, 0, 0), 0)
      f.Name = "Vignette"
      f.ZIndex = 10
      local g = Instance.new("UIGradient")
      g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
      g.Rotation = e[3]
      g.Parent = f
    end
  end
  local function mfd(text, pos, anchor, size, col, align)
    local l = ui.label(disp, text, UDim2.fromOffset(170, (size or 16) + 4), pos, size or (MOB and 12 or 16), col or MFD, Enum.Font.RobotoMono, anchor or Vector2.new(0.5, 0.5), align)
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.55, RGB(0, 0, 0)
    l.ZIndex = 12
    return l
  end
  local TS = MOB and 12 or 16
  local L0, T0 = MOB and 18 or 34, MOB and 14 or 28   -- 左右、上下的边距
  local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
  -- 左上：模式大字、倍率、视场角、对地 / 对空
  local eoMode = mfd("CCD", UDim2.fromOffset(L0, T0), Vector2.new(0, 0), TS + 8, nil, LEFT)
  TG.zoom = mfd("1.0x", UDim2.fromOffset(L0, T0 + TS + 14), Vector2.new(0, 0), TS + 2, nil, LEFT)
  TG.fov = mfd("", UDim2.fromOffset(L0 + (MOB and 52 or 72), T0 + TS + 16), Vector2.new(0, 0), TS - 2, MFD_DIM, LEFT)
  TG.ag = mfd("A-G", UDim2.fromOffset(L0, T0 + 2 * TS + 22), Vector2.new(0, 0), TS - 2, MFD_DIM, LEFT)
  -- 左上那一组的下面：指北箭头、视线方位
  local NY = T0 + 3 * TS + 42
  TG.northN = mfd("N", UDim2.fromOffset(L0 + 6, NY), nil, TS - 2)
  TG.north = ui.label(disp, "➤", UDim2.fromOffset(30, 30), UDim2.fromOffset(L0 + 30, NY), MOB and 18 or 22, MFD, Enum.Font.BuilderSansMedium, Vector2.new(0.5, 0.5))
  TG.north.ZIndex = 12
  TG.brg = mfd("BRG 000", UDim2.fromOffset(L0 + 52, NY), Vector2.new(0, 0.5), TS - 2, MFD_DIM, LEFT)
  TG.brg.Name = "EoBearing"
  -- 细十字：横竖贯穿，中间留空；空口两头各一小横；正中一个小点
  local GAP = MOB and 22 or 34
  for _, c in ipairs({ { UDim2.new(0, 1, 0.5, -GAP), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0) }, { UDim2.new(0, 1, 0.5, -GAP), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1) },
    { UDim2.new(0.5, -GAP, 0, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5) }, { UDim2.new(0.5, -GAP, 0, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5) } }) do
    local l = ui.frame(disp, c[1], c[2], MFD, 0.35, c[3])
    l.Name = "Cross"
    l.ZIndex = 11
  end
  local TICK = MOB and 5 or 8
  for _, c in ipairs({ { 0, -GAP }, { 0, GAP }, { -GAP, 0 }, { GAP, 0 } }) do
    local horiz = c[1] == 0
    local f = ui.frame(disp, horiz and UDim2.fromOffset(TICK * 2, 1) or UDim2.fromOffset(1, TICK * 2), UDim2.new(0.5, c[1], 0.5, c[2]), MFD, 0.2, Vector2.new(0.5, 0.5))
    f.Name = "CrossTick"
    f.ZIndex = 11
  end
  local cdot = ui.frame(disp, UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5), MFD, 0.1, Vector2.new(0.5, 0.5))
  cdot.Name = "CrossDot"
  cdot.ZIndex = 11
  -- 跟踪框（POINT）/ 区域跟踪的小框（AREA）、跟踪方式字
  TG.box = ui.frame(disp, UDim2.fromOffset(52, 52), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
  TG.box.Name = "TrackBox"
  TG.box.ZIndex = 12
  TG.boxStroke = ui.stroke(TG.box, MFD, 1.5, 0)
  TG.track = mfd("AREA", UDim2.new(0.5, 0, 0.5, MOB and 52 or 78), nil, TS - 2, MFD_DIM)
  TG.track.Name = "TrackMode"
  -- 下面正中：目标距离（公里）、激光编码
  TG.rng = mfd("D --", UDim2.new(0.5, 0, 1, -(MOB and 46 or 72)), nil, TS + 6)
  TG.laser = mfd("LSR 1688", UDim2.new(0.5, 0, 1, -(MOB and 26 or 44)), nil, TS - 2, MFD_DIM)
  -- 下面正中偏左：吊舱转角框（横着方位 −180°～180°，竖着俯仰 +20°～−90°）
  local GW, GH = MOB and 84 or 120, MOB and 44 or 62
  local EL_TOP, EL_BOT = 20, -90
  local GX = MOB and -250 or -360   -- 框的左边离屏幕中线
  do
    local gb = ui.frame(disp, UDim2.fromOffset(GW, GH), UDim2.new(0.5, GX, 1, -(MOB and 30 or 46)), RGB(0, 0, 0), 0.6, Vector2.new(0, 1))
    gb.Name = "EoGimbal"
    gb.ZIndex = 11
    ui.stroke(gb, MFD, 1, 0.35)
    local nose = ui.frame(gb, UDim2.fromOffset(1, 7), UDim2.new(0.5, 0, 0, 0), MFD, 0.15, Vector2.new(0.5, 0))
    nose.ZIndex = 12
    local hz = ui.frame(gb, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, EL_TOP / (EL_TOP - EL_BOT), 0), MFD, 0.7)
    hz.ZIndex = 12
    TG.gimDot = ui.frame(gb, UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), MFD, 0, Vector2.new(0.5, 0.5))
    TG.gimDot.Name = "Dot"
    TG.gimDot.ZIndex = 13
    TG.gimTxt = mfd("", UDim2.new(0.5, GX, 1, -(MOB and 30 or 46) - GH - 4), Vector2.new(0, 1), TS - 4, MFD_DIM, LEFT)
  end
  -- 飞机航向（用户 11-22：「那个飞机图标……用来在电子吊舱的时候知道飞机航向嘛」）：转角框右边一个俯视的小飞机，
  --   机头朝哪 = 飞机往哪飞（相对吊舱现在看的方向：朝上就是吊舱顺着机头看），下面一行写航向度数
  do
    local hb = ui.frame(disp, UDim2.fromOffset(56, 56), UDim2.new(0.5, GX + GW + 44, 1, -(MOB and 52 or 74)), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
    hb.Name = "EoHeading"
    hb.ZIndex = 12
    local ring = ui.frame(hb, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
    ring.ZIndex = 12
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0.5, 0)
    rc.Parent = ring
    ui.stroke(ring, MFD, 1.5, 0.35)
    local plane = ui.frame(hb, UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 1, Vector2.new(0.5, 0.5))
    plane.Name = "Plane"
    plane.ZIndex = 13
    local function bar(w, h, x, y)   -- 机身、机翼、平尾：几条亮线拼成俯视的飞机
      local f = ui.frame(plane, UDim2.fromOffset(w, h), UDim2.new(0.5, x, 0.5, y), MFD, 0, Vector2.new(0.5, 0.5))
      f.ZIndex = 13
      return f
    end
    bar(4, 34, 0, 0)        -- 机身
    bar(30, 4, 0, -2)       -- 机翼
    bar(14, 3, 0, 13)       -- 平尾
    bar(6, 6, 0, -16)       -- 机头
    TG.plane = plane
    TG.hdg = mfd("000", UDim2.new(0.5, GX + GW + 44, 1, -(MOB and 18 or 32)), nil, TS - 2)
  end
  -- 右下：高度（米）、弹着时间
  TG.alt = mfd("", UDim2.new(1, -L0, 1, -(MOB and 46 or 72)), Vector2.new(1, 0.5), TS + 2, nil, RIGHT)
  TG.tti = mfd("", UDim2.new(1, -L0, 1, -(MOB and 26 or 44)), Vector2.new(1, 0.5), TS + 2, nil, RIGHT)
  -- 右边一栏
  local side = ui.frame(disp, UDim2.fromOffset(MOB and 170 or 236, 300), UDim2.new(1, -L0, 0.38, 0), RGB(0, 0, 0), 1, Vector2.new(1, 0))
  side.Name = "TgpSide"
  side.ZIndex = 12
  local function sl(text, y, size, col, font)
    local l = ui.label(side, text, UDim2.new(1, 0, 0, (size or 12) + 4), UDim2.fromOffset(0, y), size or 12, col or MFD, font or Enum.Font.RobotoMono, nil, RIGHT)
    l.ZIndex = 12
    l.TextWrapped = true
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.6, RGB(0, 0, 0)
    return l
  end
  TG.rel = sl("", 0, MOB and 10 or 12, MFD_DIM)
  local ttiCap = ui.label(side, "TTI", UDim2.fromOffset(30, 14), UDim2.new(1, -(MOB and 112 or 150), 0, MOB and 36 or 52), MOB and 10 or 11, MFD_DIM, Enum.Font.RobotoMono, nil, LEFT)
  ttiCap.ZIndex = 12
  TG.ttiBig = ui.label(side, "-:--", UDim2.fromOffset(MOB and 80 or 112, 34), UDim2.new(1, 0, 0, MOB and 22 or 34), MOB and 22 or 32, MFD, Enum.Font.RobotoMono, Vector2.new(1, 0), RIGHT)
  TG.ttiBig.ZIndex = 12
  local barBg = ui.frame(side, UDim2.new(0.7, 0, 0, 3), UDim2.new(1, 0, 0, MOB and 58 or 76), RGB(70, 72, 70), 0, Vector2.new(1, 0))
  barBg.ZIndex = 12
  TG.bar = ui.frame(barBg, UDim2.fromScale(0, 1), nil, MFD, 0)
  TG.bar.ZIndex = 13
  local y0 = MOB and 68 or 94
  TG.away = sl("", y0, MOB and 10 or 11, MFD)
  TG.arm = sl("", y0 + (MOB and 15 or 20), MOB and 10 or 11, RGB(236, 200, 120))
  TG.lst = sl("", y0 + (MOB and 30 or 40), MOB and 10 or 11, MFD)
  TG.say = sl("", y0 + (MOB and 50 or 70), MOB and 12 or 15, MFD, Enum.Font.BuilderSans)
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
    local HB = Map.BASES and Map.BASES[team]
    if HB and HB.airfield then   -- 沙海：只落自己主基地的跑道
      runway(HB.airfield)
      return out
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

  -- 解除 / 恢复迎角限制（过失速机动：眼镜蛇、有推力矢量的能翻库尔比特；只在直接操纵时生效）——键盘 T、手机右下「T」
  local function toggleOvr()
    if not st or st.d.kind ~= "jet" or st.uav or not st.fmD then return end
    if st.fmD.fcs == "mech" then
      if G.toast then G.toast(T("air.ovrMech"), "info") end
      return
    end
    st.ovr = not st.ovr
    if G.toast then G.toast(T(st.ovr and (st.fmD.tvc and "air.ovrOnTvc" or "air.ovrOn") or "air.ovrOff"), st.ovr and "warn" or "info") end
  end

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
    tap(rb, "T", UDim2.fromOffset(10, 10), toggleOvr)
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
      local kl = ui.label(kb, it.key, UDim2.fromScale(1, 1), nil, 15, HUD, Enum.Font.RobotoMono)
      kl.Name = "Key"
      local ic = ui.frame(f, UDim2.fromOffset(60, 20), UDim2.new(0, 38, 0.5, 0), RGB(0, 0, 0), 1, Vector2.new(0, 0.5))
      ic.Name = "Icon"
      drawIcon(ic, it)
      local nm = ui.label(f, it.flare and T("air.flareName") or T("aw." .. it.wid), UDim2.new(1, -164, 1, 0), UDim2.fromOffset(104, 0), 14, HUD, Enum.Font.BuilderSans, nil, Enum.TextXAlignment.Left)
      nm.TextWrapped = false
      nm.Name = "Name"
      local cnt = ui.label(f, "", UDim2.fromOffset(58, H), UDim2.new(1, -6, 0, 0), 17, HUD, Enum.Font.RobotoMono, Vector2.new(1, 0), Enum.TextXAlignment.Right)
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
    if not on and G.sceneryFocus then G.sceneryFocus(nil) end
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
    if on then st.bsight = false end   -- 轰炸瞄准镜和吊舱只开一个（自己的飞机照旧藏着，吊舱关了再放出来）
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
    local v0 = (not onGround and typeof(vs.v) == "Vector3") and vs.v or nil   -- 空中出生（战雷街机）：接着服务器给的初速飞
    st = { id = vs.id, em = em, d = d, pilot = vs.pilot == true, cf = cf, vel = v0 or V(), spd = v0 and v0.Magnitude or 0, sink = 0, pr = 0, rr = 0, yr = 0,
      thr = onGround and 0 or 85, ground = onGround, gearWant = onGround and 1 or 0, gear = onGround and 1 or 0, rpm = (d.kind == "heli" and not onGround) and 100 or 0,
      yaw = yaw, hv = v0 and V(v0.X, 0, v0.Z) or V(), vy = 0, tiltP = 0, tiltR = 0, camYaw = yaw, camPitch = -0.15, aimYaw = yaw, aimPitch = 0, c = {},
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
    -- 固定翼的飞行物理（FlightModel）：这一型（科技树的版本优先）的物理量；没登记的按同类借一型
    if d.kind == "jet" then
      local tk = em:GetAttribute("TreeKey")
      st.fmD = FM.get(d.id, tk) or FM.get(d.like or "") or FM.get(d.prop and "mq9" or ((d.g or 9) < 4 and "h6k" or "f16"))
      local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
      st.fm = FM.new(st.fmD, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, st.vel.X / AD.M, st.vel.Y / AD.M, st.vel.Z / AD.M, st.thr)
      st.fm.live = false
      -- 对空雷达（Radars.lua）：同 FM 按科技树的版本取（F-16A 是 APG-66、苏-30SM 是 N011M）；不退回 like（苏-27 借苏-35S 的模型，雷达是 N001）
      st.rd = AD.radarOf and AD.radarOf(d.id, tk) or d.radar
    end
    if G.radarReset then G.radarReset(st) end   -- 雷达每架次重置：开着、量程最大（上一架关了雷达，这一架照旧开着）
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
      -- 风声（用户 11-25 晚：开飞机要脆但有质量——侧边对话里说的「大过载时有轻微抖动和风声」）：一直低低的一层，越快越响，
      --   拉大过载时变响、音调往上走；收在机身外面那种持续、低沉、顺滑的呼呼声，不尖
      st.windSnd = G.makeSound({ id = "rbxasset://sounds/action_falling.ogg", vol = 1, s = { 0.6, 0.6 }, loop = { 1, 9 }, eq = { 4, -2, -14 } },
        game:GetService("SoundService"), {})
      if st.windSnd then st.windSnd.Volume = 0 end
    end
    -- 发动机声（用户 11-21：声音要真，SoundLib 的真录音；没载上就没有这一层）：固定翼喷气发动机、直升机休伊的旋翼，坐后面的也听得到
    if G.realLoop then st.engSnd = G.realLoop((d.kind == "jet") and "jetEngine" or "heliRotor", game:GetService("SoundService")) end
    if G.playSound then G.playSound("capture") end
  end

  local function stop()
    pcall(function() game:GetService("ProximityPromptService").Enabled = true end)
    if st and st.trig then G.R.Drive:FireServer({ op = "trig", on = false }) end
    if G.gunLoop then G.gunLoop("me", nil, nil, false) end
    if st and (st.eo or st.bsight) then
      ownHide(false)
      st.eo, st.bsight = false, false
    end
    if G.bsOff then G.bsOff() end   -- 轰炸瞄准镜、目标点的画面
    if G.radarOff then G.radarOff() end   -- 雷达屏
    eoGui.Visible, eoCC.Enabled, eoHl.Enabled = false, false, false
    local old = st
    st = nil
    G.fly = nil
    G.hitMarkerAt = nil
    if G.airAudioOff then G.airAudioOff() end
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
    if old and old.windSnd then old.windSnd:Destroy() end
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
  -- 挂着的炸弹：选中的是炸弹就用它，不然挂载里第一种还有的炸弹（CCRP 自动投、轰炸瞄准镜用；F 照旧投选中的那种）
  local function bombW()
    local wid, w = curW()
    if w and w.kind == "bomb" and left(wid) > 0 then return wid, w end
    for _, wid2 in ipairs(st.wl) do
      local w2 = AD.W[wid2]
      if w2 and w2.kind == "bomb" and left(wid2) > 0 then return wid2, w2 end
    end
    return nil
  end
  -- 炸弹现在投下去落在哪、落下要几秒：按服务器的炸弹物理往前推（Marks.lua 的 G.bombImpact）
  local function bombNow()
    local cf = st.cf
    local p0 = (cf * CF(0, -(st.d.H or 4) * 0.35 - 1.5, 0)).Position
    local v0 = (st.vel or V()) - cf.UpVector * 4
    if G.bombImpact then return G.bombImpact(p0, v0) end
    local h = p0.Y - math.max(ground(p0.X, p0.Z), 0)
    local vy = -v0.Y
    local tf = (vy + math.sqrt(math.max(0, vy * vy + 2 * GR * math.max(h, 0)))) / GR
    local hit = p0 + V(v0.X, 0, v0.Z) * tf * 0.97
    return V(hit.X, math.max(ground(hit.X, hit.Z), 0), hit.Z), tf
  end
  -- F7 轰炸瞄准镜（战雷的「轰炸机视角」）：镜头到机腹往下看炸弹的落点；选上炸弹；鼠标瞄准时教官改成平飞、照现在的航向飞
  local function setBS(on)
    if not st then return end
    local bw = bombW()
    on = on and st.pilot and not st.crashed and not st.ground and st.d.kind == "jet" and bw ~= nil
    if on == (st.bsight == true) then return false end
    if on and st.eo then setEO(false) end
    st.bsight = on
    if on then
      for i, wid2 in ipairs(st.wl) do
        if wid2 == bw and st.wi ~= i then
          st.wi = i
          st.lock, st.lockT = nil, 0
        end
      end
      st.bsZoom, st.bsAim = 1, nil
      local v = (st.vel.Magnitude > 1) and st.vel.Unit or st.cf.LookVector
      st.aimYaw = math.atan2(-v.X, -v.Z)
      st.aimPitch = clamp(math.asin(clamp(v.Y, -1, 1)), -0.06, 0.12)
    end
    if not on then st.bsOffT = os.clock() end
    ownHide(on)
    if G.playSound then G.playSound("quiet", nil, on and 1.5 or 1.2) end
    return true
  end
  G.flyBombsight = setBS
  -- Alt + 中键（战雷默认）：在镜头中心对着的地面标目标点（兴趣点）；对着天上按就取消
  local function markPoi()
    if not st or not st.pilot then return end
    local o, dir = cam.CFrame.Position, cam.CFrame.LookVector
    local res = workspace:Raycast(o, dir * 12000, aimParams)
    local p = res and res.Position
    if not p and dir.Y < -0.02 then   -- 射线没碰到东西（地形还没加载）：按地面高度一步步找
      for i = 1, 240 do
        local q = o + dir * (i * 50)
        local g = math.max(ground(q.X, q.Z), 0)
        if q.Y <= g then p = V(q.X, g, q.Z) break end
      end
    end
    if p and (p - st.cf.Position).Magnitude > 30 then
      st.poi, st.ccrpArm, st.ccrpRelT = p, nil, nil
      G.toast(T("air.poiSet"), "info")
    else
      st.poi = nil
      G.toast(T("air.poiOff"), "info")
    end
  end
  G.flyMarkPoi = markPoi
  -- F7 归不归轰炸瞄准镜（Perf.lua 的性能面板也用 F7）：开着挂炸弹的固定翼（或者瞄准镜开着）、没按 Ctrl
  function G.flyWantsF7()
    if not st or not st.pilot or st.d.kind ~= "jet" or st.uav then return false end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then return false end
    return st.bsight == true or os.clock() - (st.bsOffT or -9) < 0.1 or bombW() ~= nil
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
        -- 雷达弹（战雷，用户 11-24 夜）：只能锁自己雷达看得见的（Radar.lua：扫描范围、距离、置零、地杂波）
        if ok and w.seeker == "radar" and st.rd and G.radarSees and not G.radarSees(st, em) then ok = false end
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
  -- 战雷式机炮（用户 11-24 夜：「把飞机的驾驶感完全还原战争雷霆」）：固定机炮顺着机头打，不黏目标、不自动打提前量（上面 11-21 那套 MWT 的关掉）；
  --   敌机在机头前方 20° 以内、炮的射程 1.3 倍以内：算它的提前量（同下面），平显上画一个小圈（AirHud 的 LeadMark），把机头的「+」压上去打
  local WT_GUNS = true
  local LEAD_IN, LEAD_OUT, LEAD_KINDS = math.cos(rad(20)), math.cos(rad(26)), { air = true }
  local function gunStick(wt)
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
    -- 雷达单目标跟踪着的（Radar.lua 的 st.rdLock，跟选的什么弹无关）在圈里就先算它：雷达测的距离、速度（真机的机炮提前量就靠雷达测距）
    local rdl = (st.rdLock and not st.rdLock.mem) and st.rdLock or nil
    local best, bestS = nil, math.huge
    for _, em in ipairs(f:GetChildren()) do
      local root = em:FindFirstChild("Root")
      if root and em ~= st.em and (wt and LEAD_KINDS or STICK_KINDS)[em:GetAttribute("Kind") or ""] and em:GetAttribute("Team") ~= myTeam
        and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        local p = root.CFrame.Position
        local to = p - p0
        local dist = to.Magnitude
        if dist > 40 and dist < gw.range * (wt and 1.3 or 1) then
          local c = fwd:Dot(to / dist)
          if c > ((em == keep) and (wt and LEAD_OUT or STICK_OUT) or (wt and LEAD_IN or STICK_IN)) then
            local sc = (1 - c) * 1000 + dist / gw.range - ((em == keep) and 2 or 0) - ((rdl and rdl.em == em) and 1e4 or 0)
            if sc < bestS then best, bestS = { em = em, p = p, dist = dist }, sc end
          end
        end
      end
    end
    if not best then st.stickV = nil return nil end
    -- 目标的速度：只在服务器真挪了它时按两次挪之间的时间算、按时间平滑（View.lua G.velTrack；原来每帧差分 × 0.3，
    --   提前量一跳一跳、帧率不同手感也不同）；换了目标重新量。雷达单目标跟踪着的用雷达测的速度（velTrack 照样跟着量，丢了雷达锁接得上）
    local now = os.clock()
    local sv = st.stickV
    if not sv or sv.em ~= best.em then
      sv = { em = best.em }
      st.stickV = sv
    end
    local vT
    if G.velTrack then vT = G.velTrack(sv, best.p, now, 1500)
    else
      sv.p, sv.t, sv.v = best.p, now, sv.v or V()
      vT = sv.v
    end
    best.radar = rdl ~= nil and rdl.em == best.em
    if best.radar and rdl.v then vT = rdl.v end
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
  -- 战雷式鼠标瞄准（用户 11-24：「飞机锁定敌目标改成战雷一模一样的 包括投弹以及各方面操作细节和手感」）：
  --   鼠标转的是想去的方向（屏幕正中的小圈），镜头顺着它看，教官自动压坡度、拉杆把机头追过去（机头的「+」在画面里跟着走）；
  --   按着 W / S / A / D / Q / E 就是直接操纵（松开教官又追回鼠标那里）；按住 C 自由看（飞机照旧往鼠标那里飞）。
  --   M 切换：战雷鼠标瞄准 ↔ 纯键盘驾驶（用户 11-21 要的那一套：鼠标只转视角）
  -- 11-24 夜（「我不想让准心控制飞机飞行方向」）一度默认纯键盘驾驶；11-27 用户又要「目前飞机机头朝向会影响我的准心位置 这个也改一下
  --   不要影响我的视角位置 驾驶飞机时我也要有自由准心」——纯键盘时镜头钉在机身上、准心就是机头。默认改回战雷鼠标瞄准（准星自由、镜头跟着鼠标、
  --   地平线水平），设置「固定翼操纵」里能换纯键盘（存档），飞行中按 M 也能换（一并存进设置）
  -- 11-28 用户「默认飞机不要准心控制吧 就键盘控制」：默认又是纯键盘（Settings.lua 的默认值；设置还没读到时也按纯键盘）
  local mouseAim = G.airMouseAim == true
  G.flyMouseAim = function(v, fromPrefs)
    if v ~= nil then
      mouseAim = v == true
      G.airMouseAim = mouseAim
      if not fromPrefs and G.setPref then G.setPref("airAim", mouseAim and "mouse" or "kb") end
    end
    return mouseAim
  end
  -- 自由视角（用户 11-26 晚：「自由视角不要因为飞机的机动动作而影响 然后 自由视角的移动改成鼠标右键拖动」）：
  --   按住右键（战雷鼠标瞄准时 C 也行）拖动——看的是世界里的一个方向（方位、俯仰），飞机怎么滚、怎么拉都不带着它转；地平线是平的；
  --   松开 0.35 秒滑回追尾镜头。原来鼠标一动就绕着飞机转（跟着机身坐标走，飞机一滚画面也滚），2.5 秒不动才回去
  flStart = function(by)
    if not st or st.fl then return end
    local lk = cam.CFrame.LookVector
    st.fl = { by = by, yaw = math.atan2(-lk.X, -lk.Z), pitch = math.asin(clamp(lk.Y, -1, 1)) }
  end
  flStop = function()
    if not st then return end
    -- 纯键盘驾驶、在地上：右键拖到哪，松开镜头就停在哪（不滑回机头，用户 11-28）；战雷鼠标瞄准在空中照旧回到准星圈
    if st.fl and st.fl.by == "rmb" and (not mouseAim or st.ground) and st.pilot and not st.uav then
      st.kbLook = { yaw = st.fl.yaw, pitch = st.fl.pitch }
    end
    st.fl = nil
  end
  G.flyFreeLook = function(on) if on then flStart("rmb") else flStop() end end   -- 测试用
  -- 战雷的投弹（用户 11-24：「……包括投弹以及各方面操作细节和手感」）：Shift + B 投弹数量（单投 → 双投 → 齐投，整局记着）；
  --   F7 轰炸瞄准镜（战雷的「轰炸机视角」）；Alt + 中键在镜头中心对着的地面标目标点（战雷的「兴趣点」）：落点走到目标点自动投
  --   （航向偏太多这一趟不投）。画面在 Bombsight.lua，地上的红方框在 Marks.lua
  local bombSeries = 1   -- 1 单投、2 双投、0 齐投（这种炸弹全部，一枚接一枚）
  G.flyBombSeries = function(v) if v ~= nil then bombSeries = v end return bombSeries end
  local SERIES_GAP = 0.08   -- 齐投一枚接一枚的间隔（秒，跟服务器 Air.lua 的 BOMB_GAP 一样）
  -- 鼠标瞄准方向（用户：准星也要能控制飞行方向，WASD 也不要动）：固定翼的鼠标想去的方向；光电吊舱、飞出作战区时自动驾驶也用它
  local function autoDir() return (CFrame.Angles(0, st.aimYaw, 0) * CFrame.Angles(st.aimPitch, 0, 0)).LookVector end
  -- 镜头跟着机身（用户 11-21：飞机的飞行方向标志动来动去，应该固定位置）：原来镜头顺着鼠标瞄准方向看（战雷那样），
  --   机头前方的全息标记跟着机头在画面里到处跑；现在镜头钉在机身后上方、顺着机头看——标记一直在屏幕正中，
  --   鼠标推的是准星圈（想去的方向），飞机转过去、圈子回到标记上。镜头的上方：地平线跟着坡度歪三成；
  --   大坡度、倒飞、快竖直时慢慢变成整个跟着机身（不然翻筋斗过顶那一下画面整个翻过来）
  local function jetCamBasis()
    local cf = st.cf
    local fwd = cf.LookVector
    local kw = st.camUpK or (1 - math.clamp(G.camRollK or 0, 0, 1))
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
  -- 雷达弹照战雷手动锁（用户 11-27 定的）：不再「选了雷达弹就自动锁最近的」——雷达屏上的目标 R / Alt+T 选中（st.rdSel，屏上「|—|」），
  --   Alt+F 锁定进雷达的单目标跟踪（STT：Radar.lua 的 st.rdLock）、再按一下解锁；锁着时 R / Alt+T 换成屏上的下一个。红外弹、空地弹、炸弹照旧自动挑
  --   **雷达锁定跟所选武器脱钩**（战雷那样）：STT 是雷达自己的，选什么弹都能锁；雷达弹的锁（st.lock）就锁雷达跟踪着的那架（或者 TWS 里指定的航迹），
  --   红外弹的导引头跟着雷达指（雷达锁着的在导引头视场里就先咬它），机炮的提前量优先算雷达锁着的（gunStick）
  --   手机还没有锁定键（第 7 步加：点亮点选、按钮锁）：R 选中就锁
  local function radarManual(w) return st ~= nil and st.rd ~= nil and w ~= nil and w.kind == "aam" and w.seeker == "radar" end
  local function toastT(k, ...) if G.toast then G.toast(T(k, ...), "info") end end
  local function candOf(w, em)
    for _, c in ipairs(candidates(w)) do if c.em == em then return c end end
    return nil
  end
  -- 雷达锁这一架（进 STT）：要在雷达屏上、看得见、在这部雷达的锁定距离里；锁不上返回 false、原因（Lang 键）、参数。
  --   选着雷达弹的话马上接上弹的锁（射程、离轴角够不着的等飞近了下面每帧自己接上）
  local function radarLockOn(em)
    local ok, why, _, _, dist = G.radarSees(st, em)
    if why == "off" then return false, "rd.isOff" end
    if not ok or not (G.radarHas and G.radarHas(st, em)) then return false, "rd.cantSee" end
    local lockR = st.rd.lock * (G.radarRcsK and G.radarRcsK(em, st) or 1)   -- 按它的 RCS（隐身机要近得多才锁得上）
    if dist > lockR then return false, "rd.lockFar", string.format("%.1f", lockR / AD.M / 1000) end
    if not (G.radarStt and G.radarStt(st, em)) then return false, "rd.cantSee" end
    local _, w = storeW()
    if radarManual(w) then
      local c = candOf(w, em)
      if c and inTrack(w, c) then st.lock, st.lockT = c, 0 end
    end
    return true
  end
  G.flyRadarLockOn = function(em)   -- 直接锁这一架（同 Alt+F 锁选中的；测试用）：锁上返回 true
    if not st or not st.rd then return false end
    return (radarLockOn(em))
  end
  -- radarKey：Alt+T（Radar.lua 转过来）——只在雷达屏上选，不管选的什么弹；R 照旧：选着雷达弹在雷达屏上选，别的弹按导引头挑
  function G.flyNextTarget(radarKey)
    if not st then return end
    local _, w = storeW()
    if st.rd and (radarKey == true or radarManual(w)) then
      local lk = st.rdLock
      local cur = (lk and lk.em) or st.rdSel
      local nx = G.radarNext and G.radarNext(st, cur)
      if not nx then
        if not lk then toastT((G.radarOn and not G.radarOn()) and "rd.isOff" or "rd.noTgt") end
        return
      end
      local ok, why, arg = true, nil, nil
      if lk then   -- 锁着：换成下一个（锁不上就留着原来的）
        if nx ~= lk.em then ok, why, arg = radarLockOn(nx) end
      else
        st.rdSel = nx
        if G.mobile then ok, why, arg = radarLockOn(nx) end
      end
      if not ok then toastT(why, arg) end
      return
    end
    if not w or w.kind == "gun" or w.kind == "rkt" then return end
    local c = pickTarget(w, st.lock and st.lock.id)
    st.lock, st.lockT = c, 0
  end
  -- Alt+F（Radar.lua 转过来）：雷达锁着就解锁（还选着它），没锁就锁选中的（没选中的挑屏上离扫描中心最近的）
  function G.flyRadarLock()
    if not st or not st.pilot or not st.rd then return end
    local lk = st.rdLock
    if lk then
      st.rdSel = lk.em
      if G.radarUnlock then G.radarUnlock(st) end
      local _, w = storeW()
      if st.lock and st.lock.em == lk.em and radarManual(w) then st.lock, st.lockT = nil, 0 end
      toastT("rd.unlock")
      return
    end
    local em = st.rdSel or (G.radarNext and G.radarNext(st, nil))
    if not em then toastT((G.radarOn and not G.radarOn()) and "rd.isOff" or "rd.noTgt") return end
    st.rdSel = em
    local ok, why, arg = radarLockOn(em)
    if not ok then toastT(why, arg) end
  end
  -- 选中这一架（手机点雷达屏上的亮点用，第 7 步接）：要在雷达屏上
  function G.flyPickTarget(em)
    if not st or not st.rd or not (G.radarHas and G.radarHas(st, em)) then return false end
    st.rdSel = em
    return true
  end

  -- 武器能不能用：开战以后；试驾（训练场，模型的 TestDrive 属性）什么时候都能打靶——真游戏开着匹配，机库里试驾时这一局还在「匹配中」
  local function weaponsHot()
    return not G.S or G.S.phase == "battle" or (st and st.em and st.em:GetAttribute("TestDrive") == true)
  end
  local function setTrig(on)
    -- 航炮声：按住扳机就一直响（循环一小段起爆声，一圈一发），打光了就停
    local loud = on and (st.gunAmmo or 0) > 0 and weaponsHot()
    if G.gunLoop and loud ~= (st.gunSnd == true) then
      st.gunSnd = loud
      G.gunLoop("me", st.d.gun, nil, loud)
    end
    if st.trig == on then return end
    st.trig = on
    G.R.Drive:FireServer({ op = "trig", on = on, aim = st.aimPt, stk = st.stick ~= nil })
  end

  -- aimAt：CCRP 自动投弹给的目标点（制导炸弹照这个坐标飞，像杰达姆；不管锁没锁别的）；投出去了返回 true
  local function fireStore(wid, w, aimAt)
    local t = os.clock()
    if t < st.nextFire or left(wid) <= 0 then return false end
    if not weaponsHot() then G.toast(T("air.notYet"), "info") return false end
    local locked = (not aimAt) and st.lock and st.lockT >= (w.lockTime or 1)
    if locked and st.lock.out and w.kind ~= "rkt" then G.toast(T("air.outCone"), "info") return false end   -- 出了发射角度：锁着也不能打（菱形是黄的）
    if w.kind == "aam" and not locked then G.toast(T("air.needLock"), "info") return false end
    if st.d.sideArm and select(2, bayOf(wid)) and st.bayS < 0.75 then return false end   -- 歼-20 侧弹舱：挂架还没把弹转出舱外（选中后约一秒）
    -- 炸弹按投弹数量（Shift + B）：单投一枚、双投两枚一起、齐投这种全部一枚接一枚
    local n = 1
    if w.kind == "bomb" then n = (bombSeries == 0) and left(wid) or math.min(bombSeries, left(wid)) end
    local rip = w.kind == "bomb" and bombSeries == 0 and n > 1
    st.nextFire = t + ((w.kind == "rkt") and (w.rate or 0.12) or 0.4) + (rip and (n - 1) * SERIES_GAP or 0)
    G.R.Drive:FireServer({ op = "fire", w = wid, tgt = locked and st.lock.id or nil, aim = aimAt or st.aimPt, n = (n > 1) and n or nil, rip = rip or nil })
    local need = w.nuke and 0 or n   -- 本地先扣（服务器的数随后推过来）；核导弹不先扣（冷却中服务器不发，数不会推回来）
    for i in ipairs(st.d.st or {}) do
      while need > 0 and st.load[i] == wid and (st.stores[i] or 0) > 0 do
        st.stores[i] -= 1
        need -= 1
      end
    end
    -- 开火声按武器（Fx.lua 的 G.sfx）：导弹低沉的点火 + 呼啸、火箭弹「噗」一声 + 呼的一下、炸弹挂架弹开「咣」一声
    if G.sfx then G.sfx((w.kind == "rkt") and "rkt" or ((w.kind == "bomb") and "bombRel" or "msl"), nil, { vol = (w.kind == "rkt") and 0.7 or 0.8 }) end
    return true
  end

  ---------------------------------------------------------------- 物理：固定翼

  local function key(k) return UIS:IsKeyDown(k) end
  local function crash()
    if st.crashed then return end
    st.crashed = true
    G.R.Drive:FireServer({ op = "crash", hit = true })
    if G.shake then G.shake(1) end
  end

  -- 质量（kg）和外挂的阻力系数增量：空重 + 内油（st.fuel 几成）+ 副油箱里的油（st.fuelX，按内油的几成）+ 挂着的弹 / 副油箱（按外形估的重量）；
  --   弹舱里的不算阻力
  --   火箭巢（kind rkt）：一个挂点挂一个巢，stores 记的是巢里还剩几发（AD.count = 管数 19 / 20），FM.storeMass / storeDrag 按外形算的是一整个装满的巢——
  --   原来照「发数 × 一整个巢」算（用户 11-27「飞机试驾不了」时查到）：苏-25（四个 B-8 巢）凭空重了 27 吨、43 吨推不动，推满油门滑出跑道两三公里还离不了地；
  --   A-10（两个火箭巢）重 11 吨、滑出跑道才离地。现在一个巢：空巢壳四成 + 剩下的火箭按发数折，阻力按一个巢（打空了巢还挂着）
  --   算法挪进了 FlightModel.loadout（机库整备的性能对比、资料卡用同一套，不另编数）：这里给它现在挂的、每个挂点还剩几枚、两种油
  local function fmMass(D)
    local L = FM.loadout(st.d, st.load, st.fuel or 1, { D = D, stores = st.stores or {}, fuelX = st.fuelX or 0, AD = AD })
    return L.m, L.dCD0
  end
  G.flyMass = function() if st and st.fmD then return fmMass(st.fmD) end return nil end   -- 测试用：质量、外挂阻力增量

  local function jetPhysics(dt)
    local d = st.d
    local D = st.fmD
    local ROLL, PITCH, GMAX = D.pmaxr, D.qmax, D.nzP   -- 教官用：最大滚转角速度、拉杆的俯仰角速度、过载上限（照这一型）
    -- 用户 11-21：飞机改成 WASD 控制方向、不要准心控制（原来 11-18 是鼠标给方向的纯准心控制、W / S 油门）——
    --   有人开的固定翼键盘就是驾驶杆：W 低头、S 抬头（跟摇杆一样往前推是低头）、A / D 滚转、Q / E 方向舵；油门挪到 Shift 加、Ctrl 收（↑ / ↓ 也行），
    --   地上油门收到底按住 Ctrl 倒退。键是开关量：杆量 0.3 秒推满、松开 0.2 秒回中，不会一按就猛地一转。
    --   无人机（平板上飞）照旧鼠标给方向、W / S 油门；开着光电吊舱、飞出作战区自动掉头时照旧按给的方向自动飞（下面的教官）
    local kb = not st.uav and not G.mobile
    local mAim = kb and mouseAim   -- 战雷式：鼠标给方向（教官飞），按方向键时直接操纵
    local up, dn
    -- 按住 Alt 的 ↑↓ 归雷达（有雷达的飞机：Alt+↑↓ 天线俯仰；←→ 不按 Alt 就是方位偏转，Radar.lua），不动油门；Alt+Q / Alt+E 也不打舵（下面）
    local altRd = st.rd ~= nil and (key(Enum.KeyCode.LeftAlt) or key(Enum.KeyCode.RightAlt))
    local kUp, kDn = key(Enum.KeyCode.Up) and not altRd, key(Enum.KeyCode.Down) and not altRd
    if kb then
      up = key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift) or kUp or (touch and touch.up)
      dn = key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.RightControl) or kDn or (touch and touch.down)
    else
      up = key(Enum.KeyCode.W) or kUp or key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift) or (touch and touch.up)
      dn = key(Enum.KeyCode.S) or kDn or key(Enum.KeyCode.LeftControl) or key(Enum.KeyCode.RightControl) or (touch and touch.down)
    end
    st.thr = clamp(st.thr + ((up and 1 or 0) - (dn and 1 or 0)) * 55 * dt, 0, d.ab and 130 or 100)
    -- 准备阶段在跑道上等开战（用户 11-28 晚「点加入战斗就进入地图里面等着吧 等倒计时结束就开战」，WtBattle.lua G.wtHold）：油门推不上去、滑不起来
    if st.ground and G.wtHold and G.wtHold() then st.thr = 0 end
    -- 超速保护（用户 11-27「j6为什么这么容易坠机」：歼-6 低空加力平飞就快到撕翼速度，带着加力一俯冲就超、机翼被撕掉）：
    --   鼠标瞄准（教官飞）时，到了极限速度九成三先把加力关掉、九成七收到慢车，降回八成八再放开——玩家自己再推油门照样能推上去（下一帧又收）
    if mAim and not st.ground and st.fmD and st.fmD.vne then
      local vneG = d.vne or (st.fmD.vne * AD.M * 1.03)
      if st.spd > vneG * 0.97 then st.vneCut = 0
      elseif st.spd > vneG * 0.93 then st.vneCut = math.min(st.vneCut or 100, 100)
      elseif st.vneCut and st.spd < vneG * 0.88 then st.vneCut = nil end
      if st.vneCut then st.thr = math.min(st.thr, st.vneCut) end
    end
    -- 自动收油门（真飞机拉平时自动油门收到慢车）：接地太快贴着跑道飘的时候不按 W 就自己往回收（按住 W 是复飞）
    if not up and os.clock() - (st.floatT or -9) < 0.3 then st.thr = math.max(0, st.thr - 55 * dt) end
    if st.out then st.thr = 0 end   -- 油烧干了：发动机熄火，只能滑翔
    local rev = st.ground and not st.cat and not st.trap and dn and st.thr <= 0.5   -- 地上油门收到底还按着 Ctrl（无人机：S）：倒退（推出来、调头）
    local rollIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn, pitchIn = 0, 0   -- 无人机：键盘不管俯仰、方向舵（鼠标给方向）；手机上摇杆当驾驶杆
    if kb then
      -- 键盘当驾驶杆（用户 11-26 晚「飞机驾驶感觉过于灵敏」；原来 0.12 秒推满杆）。11-28 用户「有时候不该灵敏的时候过于灵敏 该灵敏的时候又有点迟钝」：
      --   原来按住是往满杆指数地推（时间常数 0.28 秒，按住一秒才满），再过飞控的前置滤波、低速时跟得慢的增益——量出来 F-16 在 450 公里 / 时
      --   按住 S 半秒才 1.8 g、按住 D 半秒才 56°/s（tools/mock/kbfeel.lua）。现在按住匀速推杆、T 秒满杆（俯仰、滚转 0.25 秒，方向舵 0.3 秒）——
      --   点一下（0.08 秒）三成杆；松开 0.05 秒回中、反着按先回中再推。杆量进飞控不再过给摇杆的那道三次方（inp.lin：两道叠起来按住头 0.2 秒
      --   几乎没反应、之后猛冲上去），飞控那边：拉杆按这个速度拉得出来的过载分、迎角往要的地方靠时按平尾转得过来的时间刹住、平尾副翼转得快一倍
      --   （FlightModel；量的见 tools/test/kbfeel.luau：F-16 在 450 公里 / 时点 S 0.3 秒，机头原来自己翻上去 45°，现在 11°）
      local function ramp(cur, want, T)
        if want ~= 0 and (cur == 0 or (cur > 0) == (want > 0)) then
          return approach(cur, want, dt / T)
        end
        return approach(cur, want, dt / 0.05)
      end
      st.kP = ramp(st.kP or 0, (key(Enum.KeyCode.W) and 1 or 0) - (key(Enum.KeyCode.S) and 1 or 0), 0.25)
      st.kR = ramp(st.kR or 0, rollIn, 0.25)
      st.kY = ramp(st.kY or 0, altRd and 0 or ((key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0)), 0.3)   -- Alt+Q 是雷达量程、Alt+E 雷达模式
      pitchIn, rollIn, yawIn = st.kP, st.kR, st.kY
    end
    if G.mobile and controls then   -- 手机：摇杆直接当驾驶杆（往前推是低头）
      -- pitchIn 的符号同键盘：W 推杆（低头）= +1、S 拉杆（抬头）= −1（下面 pull = −pitchIn、inp.sy = −pitchIn，地上 pitchIn < −0.3 抬机头）。
      --   Roblox 的 MoveVector 往前推（同按 W）Z = −1，所以要取反——原来 pitchIn = mv.Z：往前推成了拉杆、往回拉成了推杆，
      --   手机上往回拉想抬头起飞反倒压机头（试驾审查 8；直升机那段 fwdIn = −mv.Z 本来就是对的）
      local ok, mv = pcall(function() return controls:GetMoveVector() end)
      if ok and typeof(mv) == "Vector3" then
        if math.abs(mv.X) > 0.1 then rollIn = mv.X end
        if math.abs(mv.Z) > 0.1 then pitchIn = -mv.Z end
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
    -- 发动机（FlightModel.engine：转速有惯性、加力要点火）：地上滑跑、天上都按它；st.thrE 给声音、尾焰（0 ~ 130）
    local F = st.fm
    local wa = G.wtaFlight and G.wtaFlight(st.em)   -- 战雷式受伤（WtAir.lua）：发动机、操纵面、平尾、断翼、飞行员昏迷
    if st.thrE and st.fmThrE and math.abs(st.thrE - st.fmThrE) > 0.5 then   -- 别处直接设了发动机状态（重生、测试摆状态）：转速照它
      F.N = clamp(st.thrE, 0, 100) / 100
      F.abf = (st.thrE > 100 and D.Ta > D.Tm) and clamp((st.thrE - 100) / 30, 0, 1) or 0
      F.abLit = F.abf > 0
    end
    FM.engine(F, D, dt, st.thr, st.out)
    st.thrE = F.N * 100 + F.abf * 30
    st.fmThrE = st.thrE
    -- 质量（空重 + 内油 + 副油箱的油 + 挂的弹）、外挂阻力；科技树改装（WtMods：散热器、压缩机、发动机）、受伤的推力
    local mass, dCD0 = fmMass(D)
    local thrK = ((st.em and st.em:GetAttribute("ModThr")) or 1) * (wa and wa.eng or 1)
    local rho = FM.atmo(cf.Position.Y / AD.M)
    local tgt = (st.thr <= 100) and d.vMil * st.thr / 100 or d.vMax   -- 地上：油门给滑行的目标速度（推力按真的算）
    if rev then tgt = -12 end   -- 倒退：慢慢往后滑（约 4 米 / 秒）
    -- 进近自动油门（真飞机的速度保护 / 迎角地板）：起落架放着在天上，速度掉到 1.3 倍（带襟翼的）失速速度以下自动加油门——
    --   油门收太多也不至于失速、掉在跑道前面的海里（收起落架就没有这个保护）
    local vsFM = math.sqrt(2 * mass * FM.G / (rho * D.S * (D.CLm + D.flapCL))) * AD.M
    local apc = st.gear > 0.9 and not st.ground and not st.out and st.spd < vsFM * 1.3
    st.apc = apc
    st.airbrake = false
    if st.trap then   -- 挂着拦阻索：发动机推力不算，地上那段按拦阻索减速
    elseif st.ground then
      -- 地上：推力 − 气动阻力 − 机轮滚动阻力（真的推重比：战斗机开加力十来秒就到离地速度，轰炸机要跑很远）；
      --   减速：B / 空格刹车 70、油门收到底自动刹车 36（落地滑跑五六秒停住，不用一直按 B）、带着点油门滑行 22
      if tgt > st.spd then
        local V0 = math.max(st.spd, 0) / AD.M
        local T = FM.thrust(D, F.N, F.abf, V0 / 340, rho, V0) * thrK
        local Dr = 0.5 * rho * V0 * V0 * D.S * (D.CD0 + dCD0 + D.gearCD + 0.03 * (st.flapK or 0))
        local a = (T - Dr - 0.03 * mass * FM.G) / mass * AD.M
        st.spd += clamp(a, 0, math.max(tgt - st.spd, 0) / math.max(dt, 1e-3)) * dt
      else
        st.spd -= math.min(st.spd - tgt, (((key(Enum.KeyCode.B) or key(Enum.KeyCode.Space)) and 70) or (st.thr < 5 and 36) or 22) * dt)   -- 空格也是机轮刹车
      end
      st.spd = clamp(st.spd, -12, d.vMax)
    end
    -- 教官摆坡度的增益：配飞控滚转响应的时间常数（前置滤波 + 内回路），到了就稳稳停住、不来回甩
    local tauR = D.tp + 1 / (10 * D.bw) + 0.05
    local kRoll = clamp(0.42 / (tauR * math.max(ROLL, 0.3)), 1.4, 3.2)
    -- 想怎么转（用户 11-18：方向只听鼠标准心，A / D 滚转不把准心拽回）：纯准心控制——像《战争雷霆》的教官，鼠标给想去的方向，
    --   自动压坡度让准心落到升力方向上、按偏差要过载（拉杆）转过去；按着 A / D 时滚转听键盘，俯仰照旧往准心拉
    --   飞机本身按升力物理飞（用户：操作感像玩具）：教官给的是「要几个 g」，飞控找迎角、升力带着航迹转，机头先抬、航迹慢半拍，拉得狠掉速；
    --   手机上摇杆当驾驶杆：往后拉要过载、松杆 1 g，坡度 33° 以内补一点杆保高度
    local bank = math.asin(clamp(right.Y, -1, 1))
    local upright = upV.Y > 0.3   -- 没倒飞、没在翻筋斗
    local nCmd, rc, yc
    local stickHeld = math.abs(st.kP or 0) + math.abs(st.kR or 0) + math.abs(st.kY or 0) > 0.02
    if G.mobile or (kb and not st.eo and (not mAim or stickHeld)) then   -- 出作战区也照旧自己飞（不再自动掉头，服务器读秒）
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
      if kb and not mAim then setAim((not st.ground and st.vdir) or fwd) end   -- 鼠标瞄准方向跟着航迹（开光电吊舱、自动掉头时从现在的航向接着飞）；
      --   战雷式按着方向键时不动它：松开以后教官追回鼠标那里
      if mAim and st.ground then setAim(fwd) end   -- 地上滑跑：鼠标圈跟着机头（离地以后再交给鼠标）
    else
      local aim = autoDir()
      local l = cf:VectorToObjectSpace(aim)
      local fz = -l.Z
      local off = math.acos(clamp(fz, -1, 1))
      local w = Map.smooth(rad(2), rad(10), off)
      local toTarget = math.atan2(l.X, l.Y)   -- 让目标落到机头正上方（升力方向）要滚多少
      if fz < -0.2 and math.abs(l.X) < 0.15 then toTarget = 0 end   -- 目标在正后方偏一点点：先拉起来（筋斗），别来回滚
      local vd0 = st.vdir or cf.LookVector
      -- 准心相对航迹偏左 / 右多少（世界坐标里水平量，右为正）
      local vdH = V(vd0.X, 0, vd0.Z)
      local aimH = V(aim.X, 0, aim.Z)
      local psi = 0
      if vdH.Magnitude > 1e-3 and aimH.Magnitude > 1e-3 then
        vdH, aimH = vdH.Unit, aimH.Unit
        psi = math.atan2(aimH:Dot(V(-vdH.Z, 0, vdH.X)), aimH:Dot(vdH))
      end
      -- 摆平机翼的滚转（bank 右翼抬起为正，rc 为正往右滚）；准心只偏一点点时带一个小坡度转过去（自动驾驶的航向保持：偏 1° 压 2.5°，最多 12°）——
      --   飞行物理以后只靠方向舵修，航迹一直慢慢漂（wtfeel / bombsight：轰-6K 照航向飞 3 秒偏出去十几米，自动投弹不投）
      local level = clamp((bank + clamp(psi * 2.5, -rad(12), rad(12))) * kRoll * 0.8, -1, 1)
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
          -- 左右最多：放着起落架 0.58 g（坡度 30° 以内）；平时按这一型的最大过载（满过载平转的水平分量 √(n² − 1)）——
          --   原来卡在 4 g：准心偏 60° 以内（大多数缠斗）教官最多拉 4 g 出头，满过载转不出来（wtfeel ⑤）
          local sMax = ((st.gear > 0.9) and 0.58 or math.sqrt(math.max(GMAX * GMAX - 1, 1))) * GR
          aDes = dnP * math.min(cD, 0.8 * GR) + sdP * clamp(cS, -sMax, sMax)
        end
        local aL = aDes - (V(0, -GR, 0) - vd0 * (-GR * vd0.Y))   -- 升力要给的加速度 = 想要的 − 重力（垂直于航迹那份）
        local lhat = (aL.Magnitude > 1e-3) and aL.Unit or lh
        local th = math.atan2(vd0:Dot(lh:Cross(lhat)), lh:Dot(lhat))   -- 升力方向要绕航迹转多少（正：往右滚）
        -- 偏得很少（10° 以内，平时打仗修一点点方向）跟原来一样以摆平机翼为主，不为了几度就压个大坡度；拉平时全按升力矢量
        local wg = flare and 1 or w
        rc = (wg * clamp(th * kRoll * 0.8, -1, 1) + (1 - wg) * level) * ROLL
        nGentle = math.max(aL:Dot(lh), 0) / GR
        gentleW = wg
      else
        -- 准心在侧面、后面、上面（不是往下俯冲攻击、也不是正后方要翻筋斗）：同上面按升力矢量算——想要的加速度（这一型最大过载以内）减去重力，
        --   坡度刚好让升力的竖直分量托住飞机（满过载平转：坡度 = arccos(1 / n)）。原来把准心滚到机头正上方再拉：准心在水平线上时一滚就是
        --   90° 坡度、升力全朝侧面，满过载转一圈掉几百米高、越转越快（wtfeel ⑤：米格-29 军推盘旋 5 秒反倒加速 2%）
        local ev = aimL - vd0 * vd0:Dot(aimL)
        if aimL.Y > -math.sin(rad(15)) and not (fz < -0.2 and math.abs(l.X) < 0.15) and ev.Magnitude > 1e-3 then
          local e = ev.Unit
          local gp = V(0, -GR, 0) - vd0 * (-GR * vd0.Y)   -- 重力垂直于航迹的那份
          local eg = e:Dot(gp)
          local aN = GMAX * GR
          local sMax = eg + math.sqrt(math.max(0, eg * eg - gp:Dot(gp) + aN * aN))   -- 朝准心那边最多能给多大的加速度（升力不超过最大过载）
          local ang = math.acos(clamp(vd0:Dot(aimL), -1, 1))
          local aL = e * math.min(ang * 2.1 * math.max(st.spd, 30), math.max(sMax, 0)) - gp
          if aL.Magnitude > 1e-3 then
            local lhat = aL.Unit
            local th = math.atan2(vd0:Dot(lh:Cross(lhat)), lh:Dot(lhat))
            rc = (w * clamp(th * kRoll * 0.8, -1, 1) + (1 - w) * level) * ROLL
            -- 先滚后拉：升力方向还差 40° 以上时少拉（不然一边滚一边满过载，航迹先被拽向错的那边）
            local nG = aL.Magnitude / GR
            local al = math.abs(th)
            if al > rad(40) then nG = 1 + (nG - 1) * clamp(1 - (al - rad(40)) / rad(60), 0.15, 1) end
            nGentle, gentleW = nG, 1
            toTarget = th
          else
            rc = (w * clamp(toTarget * kRoll, -1, 1) + (1 - w) * level) * ROLL
          end
        else
          rc = (w * clamp(toTarget * kRoll, -1, 1) + (1 - w) * level) * ROLL
        end
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
    -- 教官给的过载、滚转角速度、偏航（飞行员昏迷、断翼、平尾没了这些交给 FlightModel 按受伤算）
    st.nCmd = clamp(nCmd, -2, GMAX)
    st.yawCmd = yc
    local stickMode = G.mobile or (kb and not st.eo and (not mAim or stickHeld))   -- 键盘 / 手机摇杆直接操纵（不然教官飞）
    if st.ground then st.pr, st.rr, st.yr = 0, 0, 0 st.c.pit, st.c.rol, st.c.yaw = 0, 0, 0 end
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
        local vEnd = d.stall * 1.8   -- 冲出舰艏的速度（原来按 1.5 倍失速速度的抬头速度再乘 1.2；抬头速度改成 1.2 倍以后弹射照旧）
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
      -- 抬头、离地（飞行物理，11-26 晚：原来一到抬头速度就整架抬 4° 飞起来，升力只够一半，离地马上又落回跑道）：到抬头速度拉杆，
      --   机头绕主轮往上抬（每秒 3.5°，最多到擦尾角）；按这一型的升力曲线（带着襟翼）算升力，够托住飞机了才离地——离地时迎角就是抬起的角度；
      --   松杆机头慢慢放回去；刚接地时机头还抬着，也是慢慢放下来（离地时迎角 = 抬起的角度）
      local big = (d.g or 9) < 4   -- 轰炸机、运输机：擦尾角小、抬头慢
      local rotMax = rad(big and 9 or 12)
      if st.spd >= d.vRot and wantUp then
        st.rotP = math.min((st.rotP or 0) + rad(big and 3 or 6) * dt, rotMax)   -- 战斗机一秒多抬到离地姿态（开加力抬头那几秒还在猛加速）
      else
        st.rotP = math.max((st.rotP or 0) - rad(3) * dt, 0)
      end
      local lifted = false
      if (st.rotP or 0) > rad(2) and st.spd >= d.vRot then
        local mass = fmMass(D)
        local rho = FM.atmo(pos.Y / AD.M)
        local Vm = st.spd / AD.M
        local L = 0.5 * rho * Vm * Vm * D.S * FM.CL(D, st.rotP, st.flapK or 0)
        lifted = L >= mass * FM.G * 1.02
      end
      local function pitched(p)   -- 绕主轮（重心正下方的地面）抬机头
        local gp = p - V(0, d.gearH, 0)
        return CFrame.lookAt(gp, gp + look) * CFrame.Angles(st.rotP or 0, 0, 0) * CFrame.new(0, d.gearH, 0)
      end
      if lifted then   -- 离地：高出接地判定线一点、带一点往上的速度（原来只高 0.3 格、速度是平的，下一帧正好又判成接地，一路在跑道上弹）
        st.ground = false
        st.pr = rad(2)
        pos = V(pos.X, g + d.gearH + 1.2, pos.Z)
        cf = pitched(pos)
        st.rotP = 0
        st.liftVy = 1.5 * AD.M   -- 下面算 st.vel 时加上（离地瞬间的爬升率约 1.5 米 / 秒）
      elseif pos.Y - d.gearH > g + 2.5 then   -- 冲出甲板 / 跑道尽头：掉下去
        st.ground = false
        st.rotP = 0
        cf = CFrame.lookAt(pos, pos + look)
      else
        pos = V(pos.X, g + d.gearH, pos.Z)
        cf = ((st.rotP or 0) > 1e-4) and pitched(pos) or CFrame.lookAt(pos, pos + look)
      end
      st.vel = look * st.spd
      if st.liftVy then
        st.vel = st.vel + V(0, st.liftVy, 0)
        st.liftVy = nil
      end
      st.vdir, st.accV = (st.ground and look) or cf.LookVector, nil
      st.sink = 0
    else
      -- 天上：六自由度飞行物理（FlightModel.lua，用户 11-26 晚：每型自己的重量、推力、翼面积、升力、阻力、过载上限、失速迎角、转动惯量、稳定性、阻尼）——
      --   键盘 / 手机摇杆是驾驶杆（电传：拉杆要过载、压杆要滚转角速度、松杆保持航迹和坡度；机械操纵：杆对舵面，松杆按自己的短周期回稳）；
      --   鼠标瞄准、光电吊舱、飞出作战区自动掉头是教官给过载、滚转角速度。原来那套「要几个 g 就有几个 g、滚转一阶 0.085 秒」的运动学去掉了
      -- 别处直接改了位置、姿态、速度（服务器拉回、测试摆姿态、出界拦回……）：按改过的重新起步（航炮后坐那点抖动不算）
      if F.live and st.fmCF and ((cf.Position - st.fmCF.Position).Magnitude > 0.05 or cf.LookVector:Dot(st.fmCF.LookVector) < 0.99995
        or cf.UpVector:Dot(st.fmCF.UpVector) < 0.99995 or (st.vel - st.fmVel).Magnitude > 0.05) then
        F.live = false
      end
      if not F.live then   -- 刚离地 / 弹射离舰 / 服务器拉回 / 空中出生：按现在的姿态、速度起步（发动机转速接着用）
        local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
        local v0 = (st.vel and st.vel.Magnitude > 1) and st.vel or cf.LookVector * st.spd
        FM.reset(F, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, v0.X / AD.M, v0.Y / AD.M, v0.Z / AD.M, st.pr or 0)
        F.flap = st.flapK or 0   -- 襟翼是放着的（地上滑跑时 FlightModel 不推演，它那份襟翼还停在 0：离地头两秒少了襟翼的升力）
        F.live = true
      end
      local p0 = cf.Position
      local gH = ground(p0.X, p0.Z)
      local inp = { thr = apc and math.max(st.thr, 92) or st.thr, gear = st.gear, flap = st.flapK or 0, brake = (not G.mobile and key(Enum.KeyCode.B)) or false }
      if stickMode then
        inp.mode, inp.sx, inp.sy, inp.sz = "stick", rollIn, -pitchIn, yawIn   -- W 推杆（低头）、S 拉杆
        inp.lin = kb and not G.mobile   -- 键盘：杆量是按住多久匀速推出来的，飞控不再过给摇杆的那道三次方（FlightModel inp.lin）
        inp.level = rollIn == 0
        inp.levelHard = landAid ~= nil and rollIn == 0   -- 贴着跑道 / 甲板：机翼自动摆平
        inp.ovr = st.ovr and not landAid   -- T 解除迎角限制（过失速机动）；进近着陆时照常限制
      else
        inp.mode, inp.n, inp.p, inp.r = "cmd", st.nCmd, rc, st.yawCmd
      end
      local env = { m = mass, h = p0.Y / AD.M, agl = math.max(0, (p0.Y - d.gearH - math.max(gH, 0)) / AD.M), dCD0 = dCD0, thrK = thrK, out = st.out,
        nzK = math.min(1, (D.m0 + 0.6 * D.fi + 1000) / mass) }   -- 重了过载上限按重量打折
      if wa then
        env.ctlK = wa.ctl
        if wa.tail then env.pitchK, env.Mext = 0.25, 0.04 * math.sin(os.clock() * 2.3) end   -- 没了平尾：俯仰不受控、上下乱晃
        if wa.wing then env.liftK, env.Lext = 0.55, (wa.wing == "L") and -0.045 or 0.045 end   -- 断翼：升力少一半、往断的那边滚
        env.ko = wa.ko   -- 飞行员昏迷：松了杆，机头慢慢掉下去
      end
      st.airbrake = inp.brake
      local dx, dy, dz = FM.step(F, D, dt, inp, env)
      if st.trig and (st.gunAmmo or 0) > 0 then   -- 航炮的后坐：开火时掉一点速度（30 毫米炮的后坐力有几吨）
        local k = math.max(0, 1 - (5 / AD.M) * dt / math.max(F.Va, 1))
        F.vx, F.vy, F.vz = F.vx * k, F.vy * k, F.vz * k
      end
      -- 降落辅助：离地 25 格以内把下沉率收到 6～14 格 / 秒（越低越小）——真飞机接地前的拉平（加上地效）；
      --   玩家把准心压在跑道上、速度别太快就落得住（下沉过了 30 格 / 秒判摔）
      if landAid and landAid < 25 then
        local vyT = -(6 + 8 * landAid / 25) / AD.M
        if F.vy < vyT then
          local sp = math.sqrt(F.vx * F.vx + F.vy * F.vy + F.vz * F.vz)
          local vy = approach(F.vy, vyT, 1.2 * sp * dt)
          local hz = math.sqrt(F.vx * F.vx + F.vz * F.vz)
          if hz > 1e-3 then
            local k = math.sqrt(math.max(0, sp * sp - vy * vy)) / hz
            F.vx, F.vz, F.vy = F.vx * k, F.vz * k, vy
          end
        end
      end
      do   -- 速度上限（服务器只认 1.6 倍最大平飞速度以内；俯冲到这里早该撕翼了）
        local sp = math.sqrt(F.vx * F.vx + F.vy * F.vy + F.vz * F.vz)
        local cap = d.vMax * 1.45 / AD.M
        if sp > cap then
          local k = cap / sp
          F.vx, F.vy, F.vz = F.vx * k, F.vy * k, F.vz * k
        end
      end
      pos = p0 + V(dx, dy, dz) * AD.M
      cf = CFrame.new(pos.X, pos.Y, pos.Z, F.qx, F.qy, F.qz, F.qw)
      local v0 = st.vel
      st.vel = V(F.vx, F.vy, F.vz) * AD.M
      st.spd = st.vel.Magnitude
      st.vdir = (st.spd > 1e-3) and st.vel.Unit or cf.LookVector
      if v0 then   -- 加速度（镜头用：过载把镜头甩开）
        local acc = (st.vel - v0) / math.max(dt, 1e-3)
        st.accV = (st.accV or acc):Lerp(acc, math.min(1, dt * 6))
      end
      st.pr, st.rr, st.yr = F.q, F.p, F.r
      local n = F.nz
      st.gLoad = n
      st.aoaDeg = deg(F.al)
      st.stallK = F.stallK
      st.thrust = F.T
      -- 舵面、推力矢量喷口跟着真的舵偏（AirModels：c.pit 拉杆为正、c.rol 右滚为正、c.yaw 机头往右为正）
      st.c.pit = clamp(-F.de / D.der, -1, 1)
      st.c.rol = clamp(F.da / D.dar, -1, 1)
      st.c.yaw = clamp(-F.dr / D.drr, -1, 1)
      local spd = st.spd
      -- 超速 / 过载撕翼（用户 11-25「全部都做」⑪：战雷里超过极限速度、过载撕掉机翼）：超过这一型的海平面最大允许速度（FlightModel 的 vne）
      --   或过载门槛（设计过载的 1.45 倍：破坏载荷）连着 0.8 秒——报服务器（WtAir.lua G.ACT.wtaOver，一边机翼撕掉）；快到了屏幕上警告
      do
        local vne = d.vne or (D.vne * AD.M * 1.03)
        local gLim = d.gLim or math.max(3.5, D.nzP * 1.45)
        local over = spd > vne or n > gLim
        if over and not st.ground then
          st.overT = (st.overT or 0) + dt
          if st.overT > ((spd > vne) and 1.5 or 0.8) and not st.overSent then   -- 超速给 1.5 秒（过载照旧 0.8 秒）
            st.overSent = true
            G.R.Act:FireServer("wtaOver", (spd > vne) and "speed" or "g")
          end
        else
          st.overT = math.max(0, (st.overT or 0) - dt * 2)
        end
        if (spd > vne * 0.92 or n > gLim * 0.9) and os.clock() > (st.overWarnT or 0) and G.toast then   -- 九成二就警告（原来九成五，来不及）
          st.overWarnT = os.clock() + 2
          G.toast(T((spd > vne * 0.92) and "wta.warnSpeed" or "wta.warnG"), "bad")
        end
      end
      st.sink = 0
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
          if st.fm and st.fm.live then st.fm.vx, st.fm.vy, st.fm.vz = st.vel.X / AD.M, st.vel.Y / AD.M, st.vel.Z / AD.M end
          cf = cf - cf.Position + pos
          st.floatT = os.clock()
        elseif attOk and (st.spd < d.landMax or (hookOk and st.spd < d.landMax * 1.5)) then
          st.ground = true
          st.yaw = math.atan2(-fw.X, -fw.Z)
          st.rotP = clamp(rad(pitch), 0, rad(12))   -- 主轮先着地：机头还抬着，滑跑里慢慢放下来（地上那段每秒 3°）
          pos = V(pos.X, g + d.gearH, pos.Z)
          cf = CFrame.lookAt(pos, pos + V(fw.X, 0, fw.Z))
          st.sink, st.pr, st.rr, st.yr = 0, 0, 0, 0
          if st.fm then st.fm.live = false end   -- 下次离地按那时的姿态重新起步
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
    if st.fm and st.fm.live then st.fmCF, st.fmVel = cf, st.vel end   -- 飞行物理这一帧的结果（下一帧看别处改没改过）
    -- 起落架（用户：起飞自动把起落架收了）：离地爬过 15 米、还在往上爬就自动收一次；这次起飞只收一次，之后按 G 放下就听玩家的；
    --   地上一直放着，落地重置
    --   对标战雷（用户 11-27「你看一下战雷有没有自动收起落架这些 对标」）：战雷里起落架是自己按 G 收放的（没有自动收），襟翼有自动管理——
    --   这里自动收起落架留着（用户早先要的），设置「起飞后自动收起落架」能关；襟翼照战雷自动（下面）
    if st.ground then
      st.gearWant, st.gearAuto = 1, false
    elseif G.autoGearOff then
      st.gearAuto = true   -- 关了：这一趟不再自动收
    elseif not st.gearAuto and st.gearWant > 0.5 and st.vel and st.vel.Y > 0.5 then
      local p0 = cf.Position
      if p0.Y - d.gearH - math.max(ground(p0.X, p0.Z), 0) > 15 * AD.M then
        st.gearAuto, st.gearWant = true, 0
        if G.toast then G.toast(T("coach.gearAuto"), "info") end
      end
    end
    -- 起落架放着超速（⑪）：超过 vGear（默认不开加力最大平飞的六成）1.2 秒——报服务器，起落架坏了以后放不下来（只能机腹迫降）
    if st.em and st.em:GetAttribute("WtaGear") == false then st.gearWant = 0 end
    if st.gear > 0.3 and not st.ground and st.spd > (d.vGear or (d.vMil or 300) * 0.6) and not st.gearSent then
      st.gearOverT = (st.gearOverT or 0) + dt
      if st.gearOverT > 1.2 then
        st.gearSent = true
        G.R.Act:FireServer("wtaOver", "gear")
      end
    else
      st.gearOverT = 0
    end
    st.gear = approach(st.gear, st.gearWant, dt / 2.5)
    st.c.gear = st.gear
    st.c.thr = st.thr
    -- 襟翼（战雷的自动襟翼）：放着起落架、慢的时候放着陆襟翼（全放）；收着起落架、速度不快（2.2 倍失速以下）拉 2.5 g 以上放战斗襟翼（三成，
    --   多一点升力好转弯）；快了自己收（不会被吹坏）
    local wantFlap = 0
    if st.gear > 0.5 and st.spd < d.stall * 1.6 then wantFlap = 1
    elseif not st.ground and d.kind == "jet" and (st.gLoad or 1) > 2.5 and st.spd < d.stall * 2.2 then wantFlap = 0.33 end
    st.c.flap = wantFlap
    st.flapK = approach(st.flapK or 0, st.c.flap, dt / 2)   -- 襟翼放下 / 收起要两秒（升力、阻力按它）
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
  --   W / S 总距（W 升、S 降；11-28 前是 E / Q）：拉力大小（同样的总距，机身一倾、竖直方向的拉力就小了，会掉高度）；不按时自动把升降速度收到 0（定高）；
  --   A / D 脚蹬：偏航角速度，有惯性；速度上来以后压坡度就会转弯（协调转弯），尾翼让机头顺着来流（风标效应）；
  --   平移升力（二十几格每秒以上旋翼效率高一点）、地效（离地一个旋翼直径以内托得更稳）；最高平飞速度、爬升率照型号表
  local function heliPhysics(dt)
    local d = st.d
    if st.out then st.rpm = approach(st.rpm, 72, 9 * dt) else st.rpm = approach(st.rpm, 100, 22 * dt) end   -- 旋翼转起来要四五秒；熄火后靠气流自转，转速掉下来
    local lift = st.rpm >= 92
    local auto = st.out and not st.ground   -- 熄火自转下滑：还能往前飘一点，快落地时拉总距（空格）下沉慢一些
    -- 用户：桨盘对着哪里往哪飞（按受力算，要有物理引擎的感觉），准心决定机头朝向——
    --   鼠标转准心（镜头），机头跟着准心转：尾桨有惯性，最快 d.yaw 度 / 秒，起转、停住都要一会儿（按住 Alt 自由看，机头不跟）
    --   准心往下 / 往上：桨盘前倾 / 后仰（往前飞 / 带杆刹车、倒飞），A / D 桨盘左右倾（侧飞）；W 升、S 降；空格下飞机
    --   拉力顺着桨盘法线：倾得越多水平推力越大、往上托的越少（猛一推杆先掉一点高度）；速度有惯性，松杆桨盘回平但人还往前冲，靠阻力慢慢停
    --   快速前飞时转机头，桨盘自动往那边压坡度（协调转弯），航迹跟着机头弯过去；侧面阻力大，侧飞快不起来
    -- 照战雷的鼠标瞄准（用户 11-28「直升机……反正就弄成和战雷一样就行」；战雷开发日志：鼠标定直升机要去的方向，
    --   教官管周期变距和脚蹬，总距玩家自己管）：W / S 总距（升 / 降，松开自动定高）、鼠标准心定方向（往下前倾往前飞、往上后仰减速）、
    --   A / D 侧飞、Q / E 转机头（直接转准心，机头跟过去、不会被拽回去）。原来 E / Q 升降、W / S 前推后拉
    local fwdIn = 0
    local sideIn = (key(Enum.KeyCode.D) and 1 or 0) - (key(Enum.KeyCode.A) and 1 or 0)
    local yawIn = 0
    local upIn = ((key(Enum.KeyCode.W) or (touch and touch.up)) and 1 or 0)
      - ((key(Enum.KeyCode.S) or (touch and touch.down)) and 1 or 0)
    if not G.mobile then
      local qe = (key(Enum.KeyCode.E) and 1 or 0) - (key(Enum.KeyCode.Q) and 1 or 0)
      if qe ~= 0 then   -- Q / E：转准心的方位（按住 Alt 自由看时转机头记着的那个方位）
        local dy = -qe * rad(d.yaw) * dt
        if st.noseYaw then st.noseYaw += dy else st.camYaw = (st.camYaw or st.yaw) + dy end
      end
    end
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
    --   用户 11-22：「准心决定机头对准哪里——鼠标准心往下，螺旋桨对准前面，往前飞；准心突然往上，直升机受力往后和往上」：
    --   电脑上俯仰跟着准心（镜头的俯仰）：准心比平常那个略往下看的角度（AIM0）低多少，机头、桨盘就往前倾多少（到型号的最大倾角为止），
    --   高多少就往后仰多少（W / S 是总距，不再前推后拉）；按住 Alt 自由看时停在按下那一刻的俯仰；手机没有鼠标照旧用摇杆前后
    local tP = -fwdIn * maxT
    if not G.mobile then
      local AIM0 = -0.15   -- 坐进来时镜头的俯仰（略往下看）：这时桨盘是平的
      local aimP = st.nosePitch or st.camPitch or AIM0
      tP = (aimP - AIM0) * 1.15 - fwdIn * maxT
    end
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
    -- 战雷式受伤（WtAir.lua）：发动机受损拉力打折、旋翼打断没有拉力；尾桨打断机身打转
    local wa = G.wtaFlight and G.wtaFlight(st.em)
    if wa and not st.ground then
      Tm *= (wa.lift or 1) * (0.35 + 0.65 * wa.eng)
      if wa.tail then st.yaw += 1.7 * dt end
      if wa.ko then Tm = math.min(Tm, GS * 0.8) end   -- 飞行员昏迷：没人拉总距，往下掉
    end
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
    -- 拉平（flare）：往前飞时桨盘往后仰，迎面的气流从下往上穿过桨盘、拉力变大——速度换成高度（往后、往上顶）
    local flare = 0
    if lift and not st.ground and st.tiltP > 0 and vf > 0 then
      flare = GS * 2.2 * math.sin(math.min(st.tiltP, maxT)) * smooth(4, 45, vf)
    end
    st.vy += (Tm * up.Y + flare - GS - st.vy * 0.5) * dt
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

  local RADAR_ALT = {}   -- 按住 Alt 时归雷达的键（Radar.lua：R 开关、T 选目标、F 锁定、Q 量程、E 模式、Z 扫描方式、C 回中、方向键挪天线）
  for _, kc in ipairs({ "R", "T", "F", "Q", "E", "Z", "C", "Up", "Down", "Left", "Right" }) do RADAR_ALT[Enum.KeyCode[kc]] = true end
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not st then return end
    local k = io.KeyCode
    -- 用户：空格键脱离载具（在天上就跳伞）；战雷式（不当步兵）没有跳伞、下飞机——空格是机轮刹车（地上），回机库长按 H（Hud.lua）
    if k == Enum.KeyCode.Space and not (G.hangarActive and G.hangarActive()) then G.R.Drive:FireServer({ op = "exit" }) return end
    if not st.pilot then return end
    -- Alt 组合键只给雷达（有雷达的固定翼；战雷的默认键 Alt+R 开关、Alt+T 选目标、Alt+F 锁定，Radar.lua 接）：原来 Alt+T 同时切迎角限制、
    --   Alt+R 同时换目标、Alt+F 同时发导弹。W / S / A / D 不拦（座舱里按住 Alt 转头时还得能拉杆）；Alt+中键标目标点按 UserInputType 判断，不受影响
    if st.rd and RADAR_ALT[k] and (key(Enum.KeyCode.LeftAlt) or key(Enum.KeyCode.RightAlt)) then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      if G.interiorHover and G.interiorHover() then return end   -- 座舱里对着屏幕边的按键：左键是按键，不开炮（Interior.lua）
      st.firing = true
    elseif io.UserInputType == Enum.UserInputType.MouseButton3 and (key(Enum.KeyCode.LeftAlt) or key(Enum.KeyCode.RightAlt)) and st.d.kind == "jet" then
      markPoi()   -- 战雷：Alt + 中键 标目标点（兴趣点）
    elseif k == Enum.KeyCode.F then   -- 发导弹 / 火箭 / 炸弹（选中的那种）
      st.missile = true
    elseif k == Enum.KeyCode.C and st.d.kind == "jet" and st.uav then   -- 无人机：准星圈回到正前方，按航迹（飞机照直飞）
      local lk = (not st.ground and st.vdir) or st.cf.LookVector
      st.aimYaw, st.aimPitch = math.atan2(-lk.X, -lk.Z), math.asin(clamp(lk.Y, -1, 1))
    elseif io.UserInputType == Enum.UserInputType.MouseButton2 and st.d.kind == "jet" and not st.uav and not st.eo and not st.bsight then
      flStart("rmb")   -- 自由视角：按住右键拖动
    elseif k == Enum.KeyCode.C and st.d.kind == "jet" and st.pilot then
      if mouseAim and not st.ground then flStart("c") else st.fl, st.kbLook = nil, nil end   -- 战雷鼠标瞄准：按住 C 也是自由视角；纯键盘、地上：C 镜头回到身后
    elseif k == Enum.KeyCode.X then   -- 热诱弹：按住连续放（用户），每帧里按节拍发（stepFly）
      st.flareHold = true
      if os.clock() >= (st.flareNext or 0) and (st.flares or 0) > 0 then   -- 点一下也放一组（按下、松开在同一帧里的话，按住的逻辑一组都发不出去）
        st.flareNext = os.clock() + 0.3
        G.R.Drive:FireServer({ op = "flare" })
        if G.airAudioEvent then G.airAudioEvent("flare") end
      end
    elseif k == Enum.KeyCode.T and st.d.kind == "jet" then   -- 解除 / 恢复迎角限制
      toggleOvr()
    elseif k == Enum.KeyCode.M and st.d.kind == "jet" and not st.uav and not G.mobile then   -- 战雷式鼠标瞄准 ↔ 纯键盘驾驶
      G.flyMouseAim(not mouseAim)   -- 一并存进设置（「固定翼操纵」）
      setAim((not st.ground and st.vdir) or st.cf.LookVector)   -- 从现在的航向接着飞，不猛地一转
      st.lookYaw, st.lookPitch = 0, 0
      if G.toast then G.toast(T(mouseAim and "air.mouseAimOn" or "air.mouseAimOff"), "info") end
    elseif k == Enum.KeyCode.B and (key(Enum.KeyCode.LeftShift) or key(Enum.KeyCode.RightShift)) and st.d.kind == "jet" then   -- 战雷：Shift + B 投弹数量
      bombSeries = (bombSeries == 1) and 2 or ((bombSeries == 2) and 0 or 1)
      G.toast(T("air.bombN" .. bombSeries), "info")
    elseif k == Enum.KeyCode.F7 and G.flyWantsF7() then   -- 战雷：F7 轰炸机视角（没挂炸弹的飞机 F7 照旧是性能面板，Ctrl + F7 一直是）
      setBS(not st.bsight)
    elseif st.bsight and k == Enum.KeyCode.Z then   -- 瞄准镜变焦 1 → 2 → 4 倍
      st.bsZoom = ((st.bsZoom or 1) == 1) and 2 or ((st.bsZoom == 2) and 4 or 1)
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
      if n and G.radioOpen and G.radioOpen() then n = nil end   -- 无线电菜单开着（WtComms.lua）：数字键选无线电
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
    if st and ((io.UserInputType == Enum.UserInputType.MouseButton2 and st.fl and st.fl.by == "rmb") or (io.KeyCode == Enum.KeyCode.C and st.fl and st.fl.by == "c")) then flStop() end
  end)
  UIS.InputChanged:Connect(function(io, gp)
    if gp or not st or io.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if st.uav or st.eo then   -- 平板前视光电：滚轮细调倍率（1× ~ 12×）
      st.zoom = clamp(st.zoom * (1 + 0.18 * io.Position.Z), 1, 40)
    elseif st.pilot and st.rd and (key(Enum.KeyCode.LeftAlt) or key(Enum.KeyCode.RightAlt)) then   -- Alt+滚轮归雷达（挪天线俯仰），不动油门
      if G.radarWheel then G.radarWheel(io.Position.Z) end
    elseif st.pilot and st.d.kind == "jet" then   -- 战雷：滚轮是油门（一格 5%，推过 100% 就是加力）
      st.thr = clamp(st.thr + io.Position.Z * 5, 0, st.d.ab and 130 or 100)
    end
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
      if st.fm then st.fm.live = false end   -- 飞行物理按拉回来的姿态、速度重新起步
    elseif m.op == "rwr" then   -- 有导弹朝我来了
      st.rwrT = os.clock() + 4
      if G.wtRwrEvent then G.wtRwrEvent("rwr", m) end   -- 战雷式雷达告警圆盘（WtFlight.lua）
      if G.playSound then G.playSound("capture", nil, 2.2) end
    elseif m.op == "rwrLock" then   -- 被敌机的雷达锁着（战雷的 RWR）：对方半秒报一次，停了一秒多就算丢了
      st.rwrLockT = os.clock() + 1.1
      if G.wtRwrEvent then G.wtRwrEvent("rwrLock", m) end
      st.rwrLockFull = m.full == true
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
    if st and st.pilot then
      st.hitKick = math.min(1.3, (st.hitKick or 0) + ((kind == "kill") and 1.0 or 0.45))
      if G.airAudioEvent then G.airAudioEvent((kind == "kill") and "kill" or "hit") end   -- 战雷式命中「叮」、击落两声
    end
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
    TG.fov.Text = string.format("%.1f°", cam.FieldOfView)
    TG.zoom.Text = string.format("%.1fx", st.zoomS)
    TG.ag.Text = (w and w.kind == "aam") and "A-A" or "A-G"
    -- 放大看的那一片：树按放大后的距离挑版本（Scenery.lua）；服务器那边按同步的瞄准点把那一片先送过来（Air.lua aheadStep）
    if G.sceneryFocus then G.sceneryFocus(st.aimPt, st.zoomS) end
    -- 下面的小飞机：机头朝向相对吊舱镜头转（镜头朝北、飞机朝东：小飞机机头朝右）
    do
      local acf = st and st.cf
      local al = acf and acf.LookVector
      local cl = cam.CFrame.LookVector
      if al and (al.X * al.X + al.Z * al.Z) > 1e-6 and (cl.X * cl.X + cl.Z * cl.Z) > 1e-6 then
        local ya = math.atan2(-al.X, -al.Z)
        local yc = math.atan2(-cl.X, -cl.Z)
        TG.plane.Rotation = -math.deg(ya - yc)
        TG.hdg.Text = string.format("%03d", math.floor((math.deg(-ya) % 360) + 0.5) % 360)
      end
    end
    -- 吊舱转角：横着是吊舱视线相对机头的方位，竖着是俯仰；视线方位（真方位，度）
    do
      local lv0 = cam.CFrame.LookVector
      local al = st.cf.LookVector
      if (lv0.X * lv0.X + lv0.Z * lv0.Z) > 1e-6 and (al.X * al.X + al.Z * al.Z) > 1e-6 then
        local yc = math.atan2(-lv0.X, -lv0.Z)
        local ya = math.atan2(-al.X, -al.Z)
        local az = math.deg(angDiff(yc, ya))   -- 往右为正
        local el = math.deg(math.asin(clamp(lv0.Y, -1, 1)))
        TG.gimDot.Position = UDim2.fromScale(clamp(0.5 + az / 360, 0, 1), clamp((EL_TOP - el) / (EL_TOP - EL_BOT), 0, 1))
        TG.gimTxt.Text = string.format("AZ %+04d  EL %+03d", math.floor(az + 0.5), math.floor(el + 0.5))
        TG.brg.Text = string.format("BRG %03d", math.floor((math.deg(-yc) % 360) + 0.5) % 360)
      end
    end
    local camP = cam.CFrame.Position
    local vs = cam.ViewportSize
    local dispH = vs.Y   -- 整屏就是吊舱画面（11-28 照战雷；原来中间 4:3 的显示器）
    local dispW = vs.X
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
    -- 目标距离（公里）、高度（米）、指北（照战雷用公制；原来照 F-16 写海里、英尺）
    local slant = (st.aimPt - camP).Magnitude / AD.M
    TG.rng.Text = string.format("D %.2f km", slant / 1000)
    TG.alt.Text = string.format("ALT %d m", math.floor(pos.Y / AD.M + 0.5))
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
    local fl = G.flyLast or {}   -- 阵亡镜头（DeathFx.lua）：刚才坐的是哪一架（死的那一刻这里可能已经 stop 了）
    fl.id, fl.t, fl.kind, fl.test = st.id, os.clock(), d.kind, st.em:GetAttribute("TestDrive") == true
    G.flyLast = fl
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
    local md = G.mouseDelta and G.mouseDelta(st.eo or st.uav) or UIS:GetMouseDelta()   -- 设置里的灵敏度、反转 Y（Settings.lua）
    -- 平板前视光电变焦：倍率越大鼠标越慢（准星在画面上走得一样快）
    st.zoomS = st.zoomS + ((((st.uav and st.dcam == "nose") or st.eo) and st.zoom or 1) - st.zoomS) * math.min(1, dt * 8)
    if st.uav or st.eo then md = md / st.zoomS end
    if st.eo then   -- 光电：鼠标只转吊舱（飞机按自动驾驶飞）
      st.eoYaw -= md.X * SENS
      st.eoPitch = clamp(st.eoPitch - md.Y * SENS, -1.5, 0.35)
    else
      local pitLook = key(Enum.KeyCode.LeftAlt) and G.interiorOn and G.interiorOn()   -- 座舱里按住 Alt 自由看（Interior.lua 转头）：准心不动
      if st.bsight and d.kind == "jet" and st.pilot then
        -- 轰炸瞄准镜里（战雷）：鼠标左右只细细地修航向（教官带着转、保持平飞），上下不管；纯键盘驾驶时鼠标不管飞
        if mouseAim and not G.mobile then
          st.aimYaw -= md.X * SENS * 0.15
          st.aimPitch += (0 - st.aimPitch) * math.min(1, dt * 1.2)
        end
      elseif d.kind == "jet" and not G.mobile and not pitLook then
        if st.fl then   -- 自由视角（右键拖着）：鼠标转世界里的方向（准心、飞机照旧）
          st.fl.yaw -= md.X * SENS
          st.fl.pitch = clamp(st.fl.pitch - md.Y * SENS, -1.45, 1.45)
        elseif st.pilot and not st.uav and mouseAim and not key(Enum.KeyCode.C) and not st.ground then
          -- 战雷式鼠标瞄准：鼠标转想去的方向（世界里的方向，可以转到身后——飞机掉头追过去）
          st.aimYaw -= md.X * SENS
          st.aimPitch = clamp(st.aimPitch - md.Y * SENS, -1.45, 1.45)
        elseif st.pilot and not st.uav then
          -- 有人开的固定翼（用户 11-21：WASD 控制方向、不要准心控制）、战雷鼠标瞄准时在地上滑跑：鼠标不管方向，鼠标直接转镜头——
          --   看世界里的一个方向（方位、俯仰），转到哪停在哪，不再被拽回机头（用户 11-28「飞机驾驶不要强制让镜头跟着机头」；
          --   原来纯键盘时镜头钉在机头上，只有按住右键才能转、松开就滑回去）；按 C 回到身后
          if md.X ~= 0 or md.Y ~= 0 then
            if not st.kbLook then
              local lk = cam.CFrame.LookVector
              st.kbLook = { yaw = math.atan2(-lk.X, -lk.Z), pitch = math.asin(clamp(lk.Y, -1, 1)) }
            end
            st.kbLook.yaw -= md.X * SENS
            st.kbLook.pitch = clamp(st.kbLook.pitch - md.Y * SENS, -1.45, 1.45)
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
          st.noseYaw, st.nosePitch = st.camYaw, st.camPitch   -- 机头的方位、俯仰都停在按下那一刻
        elseif not alt and st.freeLook then
          st.camYaw, st.camPitch = st.freeLook[1], st.freeLook[2]
          st.freeLook, st.noseYaw, st.nosePitch = nil, nil, nil
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
      -- 作战区按所在的区块算（Zones.lua：训练场在十万格外，边界、掉头的方向都按训练场中心）
      local Zn = Map.Zones
      local zn = Zn and Zn.of(p.X, p.Z) or "battle"
      local cx, cz = 0, 0
      if Zn then cx, cz = Zn.center(zn) end
      local lim = Zn and Zn.play(zn, Map) or Map.PLAY
      local rx, rz = p.X - cx, p.Z - cz
      -- 出了作战区：不再自动掉头（用户 11-27「超出战场区域开始读秒吧 读完了自动炸」，同战雷）——操纵照旧在玩家手里，
      --   服务器读秒（Air.lua oobStep，剩几秒在飞机的 Oob 属性上，平显正中写），读完判毁；再往外 12000 格服务器直接判毁，
      --   这里的硬边只是保险（别飞进别的区块）
      st.oob = math.abs(rx) > lim or math.abs(rz) > lim
      local hard = lim + 12500
      if math.abs(rx) > hard or math.abs(rz) > hard then
        st.cf = st.cf - p + V(cx + math.clamp(rx, -hard, hard), p.Y, cz + math.clamp(rz, -hard, hard))
        if d.kind == "heli" then st.hv = V() end
      end
      local ceil = Map.CEIL or 2600   -- 升限按地图（雪山的角峰四千多格，上面还要留两三千格飞：Map.CEIL 7200）
      if p.Y > ceil then
        st.cf = st.cf - V(0, p.Y - ceil, 0)
        if st.fm and st.fm.live then st.fm.vy = math.min(st.fm.vy, 0) end
      end
    else
      st.cf = st.em.Root.CFrame   -- 坐在后面：跟着服务器
    end
    -- 发动机声跟着油门（固定翼：加力更尖更响）、总距（直升机：拉得越狠越沉）
    if st.engSnd then
      -- 发动机打坏了 / 油烧干（用户 11-25「发动机各种状态 冒烟什么的都要做出来」）：转速慢慢掉下去、声音没了，只剩风声；受伤的转得发涩（音高低一点、一抖一抖）
      local wae = G.wtaFlight and G.wtaFlight(st.em)
      local dead = st.out == true or (wae ~= nil and wae.eng <= 0)
      st.engDie = approach(st.engDie or 0, dead and 1 or 0, dt / (dead and 3.5 or 1.5))
      if d.kind == "jet" then
        local tq = math.clamp((st.thrE or st.thr or 0) / 100, 0, 1.3)
        local rough = (wae and wae.eng < 1 and wae.eng > 0) and (1 - wae.eng) or 0
        st.engSnd.PlaybackSpeed = (0.75 + 0.45 * tq) * (1 - 0.45 * st.engDie) * (1 - 0.12 * rough + 0.05 * rough * math.sin(os.clock() * 23))
        st.engSnd.Volume = (0.3 + 0.6 * tq) * (1 - st.engDie)
      else
        local load = math.clamp(math.abs((st.c and st.c.col) or 0), 0, 1)
        st.engSnd.PlaybackSpeed = 0.95 + 0.12 * load
        st.engSnd.Volume = 0.7 + 0.4 * load
      end
      if st.crashed then st.engSnd.Volume = 0 end
    end
    -- 摔了（客户端判的坠毁）3 秒服务器还没判毁（没认成坠机、或者那一包丢了）：自己回机库，不用再长按 H
    --   （用户 11-27「我坠机能不能自动返回主页」；服务器判毁的照常走阵亡画面，几秒后自动回机库）
    if st.pilot and st.crashed then
      st.crashT = st.crashT or os.clock()
      if not st.crashBack and os.clock() - st.crashT > 3 then
        st.crashBack = true
        G.R.Drive:FireServer({ op = "exit", hangar = true })
      end
    end
    -- 航炮后坐：开火时机身高频抖一点（模型跟着抖，用户：飞机机炮要有散布、后坐力和打击感）
    local gunOn = st.pilot and st.trig and (st.gunAmmo or 0) > 0 and not st.crashed
    st.recoil = approach(st.recoil or 0, gunOn and 1 or 0, dt * (gunOn and 14 or 6))
    st.hitKick = math.max(0, (st.hitKick or 0) - dt * 5)
    -- 航炮开火不再抖机身（用户 11-27「机炮开打的时候屏幕不要往前拉 就正常就行 也别搞后坐力」）：st.recoil 只留给界面用
    -- 镜头
    local pos = st.cf.Position
    -- 按 L 跟踪自己的导弹（MslCam.lua，用户 11-27「l没法看导弹视角」）：那边每帧摆镜头，这一帧飞行镜头算完照旧还给它——
    --   两边都在每帧写镜头，谁后写谁赢：原来飞行镜头在 RenderStepped 里后写，跟踪导弹的镜头一闪就被盖掉
    local mslHold = (G.mslFollowing ~= nil and G.mslFollowing()) and { cam.CFrame, cam.FieldOfView } or nil
    if st.eo then
      -- 光电吊舱：机腹下面（固定翼）/ 机头下面的光电球（直升机），视线稳定在世界方向上，不画镜头抖动
      local eye = (d.kind == "jet") and (st.cf * CF(0, -d.H * 0.5 - 0.6, -d.L * 0.12)).Position or (st.cf * CF(0, -d.H * 0.3, -d.L * 0.5 - 0.8)).Position
      cam.CFrame = CFrame.lookAt(eye, eye + eoDir() * 100)
    elseif st.uav and st.dcam == "nose" then
      -- 无人机前视光电（机头下面的光电球）：顺着鼠标想去的方向看（手机上就是机头方向），不画镜头抖动
      local eye = (st.cf * CF(0, -d.H * 0.22, -d.L * 0.5 - 0.8)).Position
      local look = G.mobile and st.cf.LookVector or aimDirNow()
      cam.CFrame = CFrame.lookAt(eye, eye + look * 100)
    elseif st.bsight and d.kind == "jet" and st.pilot then
      -- 轰炸瞄准镜（F7）：机腹下面往下看，稳定地对着炸弹现在投下去的落点（十字中心）；画面的上方是航迹方向，
      --   地面从上往下滑过十字（目标走到十字中心就投）；不画抖动
      local imp, tf = bombNow()
      st.bsImp, st.bsTf = imp, tf
      st.bsAim = st.bsAim and st.bsAim:Lerp(imp, 1 - math.exp(-dt * 12)) or imp
      local eye = (st.cf * CF(0, -d.H * 0.5 - 0.8, -d.L * 0.15)).Position
      local look = st.bsAim - eye
      look = (look.Magnitude > 1) and look.Unit or V(0, -1, 0)
      local hv = V(st.vel.X, 0, st.vel.Z)
      local lk0 = V(st.cf.LookVector.X, 0, st.cf.LookVector.Z)
      local trk = (hv.Magnitude > 1 and hv.Unit) or (lk0.Magnitude > 1e-3 and lk0.Unit) or V(0, 0, -1)
      local sK = clamp(-look.Y, 0, 1)
      cam.CFrame = CFrame.lookAt(eye, eye + look * 100, (trk * sK + V(0, 1, 0) * (1 - sK)).Unit)
      -- 视野：镜片（屏幕高的 92%）从十字到上边框住落点前方 4.5 秒的地面（目标提前几秒就看得见滑过来），
      --   慢的时候至少框住三倍杀伤半径；Z 变焦 1 → 2 → 4 倍
      local _, bww = bombW()
      local slant = math.max((st.bsAim - eye).Magnitude, 1)
      local ahead = st.bsAim + trk * (hv.Magnitude * 4.5)
      local a1 = math.acos(clamp(look:Dot((ahead - eye).Unit), -1, 1))
      local a2 = math.atan(((bww and bww.splash) or 30) * 3 / slant)
      st.bsFov = clamp(2 * deg(math.max(a1, a2)) / 0.92, 6, 75) / (st.bsZoom or 1)
    elseif d.kind == "jet" and st.pilot then
      -- 镜头钉在飞机后上方、顺着机头看（用户 11-21：飞行方向标志应该固定位置）：机头前方的全息标记一直在屏幕正中，
      --   鼠标推的准星圈在画面里走（原来镜头顺着鼠标瞄准方向看，标记跟着机头在画面里到处跑）；手机上一样
      local fwd0 = st.cf.LookVector
      local upY = st.cf.UpVector.Y
      -- 镜头跟着机身滚转几成：设置「纯键盘时镜头跟着滚转」（默认 0：地平线水平，同战雷；用户 11-27 问「视角会跟随飞机滚筒而滚动 战雷是否是这样」）
      local kwT = (1 - clamp(G.camRollK or 0, 0, 1)) * clamp((0.97 - math.abs(fwd0.Y)) / 0.25, 0, 1) * clamp((upY + 0.3) / 0.6, 0, 1)
      st.camUpK = (st.camUpK or kwT) + (kwT - (st.camUpK or kwT)) * math.min(1, dt * 2.5)
      local fwd, upC = jetCamBasis()
      local wtCam = mouseAim and not st.uav and not G.mobile and not st.ground
      if wtCam then   -- 战雷式：镜头顺着鼠标想去的方向（飞机在画面里追过去），镜头的上方就是天上（地平线不歪）
        local a = autoDir()
        st.camF = st.camF and st.camF:Lerp(a, 1 - math.exp(-dt * 14)) or a
        if st.camF.Magnitude > 1e-3 then st.camF = st.camF.Unit end
        fwd, upC = st.camF, V(0, 1, 0)
      end
      -- 机头标记跟着机动小幅位移（用户 11-21：像 MWT 那样视角里有个会位移的飞机小标志）：镜头的朝向慢半拍跟上机头——
      --   一阶平滑（不会来回晃），最多偏 7°；压杆转弯时标记往转的那边挪一点，松杆回到正中。原来镜头死钉在机头上，标记一动不动；
      --   再原来镜头跟着鼠标瞄准方向，标记在画面里到处跑（偏 229 像素、来回摆四次，用户嫌乱）
      if wtCam then st.kbLook = nil end   -- 离地以后交给鼠标瞄准（镜头顺着准星圈）
      if not wtCam and st.kbLook then   -- 鼠标转开的镜头：停在那个方向，地平线放平（不跟着机头）
        fwd = (CFrame.Angles(0, st.kbLook.yaw, 0) * CFrame.Angles(st.kbLook.pitch, 0, 0)).LookVector
        upC = V(0, 1, 0)
        st.camF = fwd
      elseif not wtCam then
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
      -- 自由视角（右键拖动）：看世界里的方向（方位、俯仰），地平线放平，跟飞机的滚转、拉杆无关；松开 0.35 秒滑回追尾。
      --   两头按方位角、俯仰角插值（往身后看也不会从机身里穿过去）
      st.flK = approach(st.flK or 0, st.fl and 1 or 0, dt / (st.fl and 0.12 or 0.35))
      if st.fl then st.flLast = { yaw = st.fl.yaw, pitch = st.fl.pitch } end
      st.flDir = nil
      if st.flK > 1e-3 and st.flLast then
        local k = st.flK * st.flK * (3 - 2 * st.flK)
        local y0, p0 = math.atan2(-fwd.X, -fwd.Z), math.asin(clamp(fwd.Y, -1, 1))
        local yw = y0 + angDiff(y0, st.flLast.yaw) * k
        local pt = p0 + (st.flLast.pitch - p0) * k
        fwd = (CFrame.Angles(0, yw, 0) * CFrame.Angles(pt, 0, 0)).LookVector
        upC = upC:Lerp(V(0, 1, 0), k)
        upC = (upC.Magnitude > 1e-3) and upC.Unit or V(0, 1, 0)
        if st.fl then st.flDir = fwd end   -- 座舱里转头也看这个方向（Interior.lua）
      end
      st.lookYaw, st.lookPitch = 0, 0
      -- 用户：视角要离飞机近一点（最早一倍半机身长再往后 26 格；11-18 改成 0.85 倍 + 12 格；11-18 晚又说再近一点）：
      --   现在 0.62 倍 + 6 格（歼-20 从 60 格到 41 格），按机身长和七成翼展里大的算——B-2 这种翼展比机身长得多的，镜头转到侧面不钻进机翼
      local size = math.max(d.L, d.W * 0.7)
      local back = size * 0.62 + 6
      -- 镜头的位置带弹簧慢半拍跟上，加速度把镜头往反方向甩开一点（转弯时飞机在画面里往外偏、拉起时往下沉）；大过载、加力时轻轻抖。
      --   看的方向一直是机头前方 300 格那一点（全息标记就在那里），位置怎么甩标记都在正中
      local want = -fwd * back + upC * (d.H * 0.45 + 2.5)
      st.camOff = st.camOff and st.camOff:Lerp(want, 1 - math.exp(-dt * 7)) or want
      local acc = st.accV or V()
      local push = -acc * 0.014 * (1 - (st.flK or 0))   -- 自由视角：不被过载甩
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
      if st.windSnd then   -- 风声：速度给底（0.25 倍极速以上才有），过载 3 g 以上变响、往上走
        local sk = math.clamp((st.spd - d.vMax * 0.25) / math.max(d.vMax * 0.9, 1), 0, 1.2)
        local gk = math.clamp(((st.gLoad or 1) - 3) / 5, 0, 1)
        local want = st.ground and 0 or (0.05 + 0.22 * sk) * (1 + 1.6 * gk)
        st.windSnd.Volume += (want - st.windSnd.Volume) * math.min(1, dt * 4)
        st.windSnd.PlaybackSpeed = 0.5 + 0.25 * sk + 0.18 * gk
      end
      if st.buffetSnd then
        st.buffetSnd.Volume = buf * 1.4
        st.buffetSnd.PlaybackSpeed = 0.32 + buf * 0.12
      end
      local ab = buf * 0.006 * (0.6 + 0.4 * math.abs(math.noise(t * 3, 9.9)))
      local shake = CFrame.Angles(math.noise(t * 18, 1.3) * amp + math.noise(t * 34, 2.6) * ab, math.noise(t * 18, 7.1) * amp + math.noise(t * 31, 5.3) * ab,
        math.noise(t * 29, 3.7) * ab * 0.6)
      if (st.flK or 0) > 0.5 then shake = CFrame.new() end   -- 自由视角：画面不跟着机身抖
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
        fov0 = G.fov3Air or G.fov3 or 70, fovK = 3, pushK = 0.03, maxPush = 3, follow = 8, maxLag = 3 })   -- 设置：空战第三人称视野
      cam.CFrame = G.noShake and camCF or (camCF * camShake)   -- 设置里能关镜头晃动
    end
    -- 视野：固定翼越快越宽；光电吊舱 / 无人机前视按倍率收（另一会话：开火时镜头抖、视野收一点，打中时再猛跳一下）
    local fovT = (d.kind == "jet") and math.clamp(70 + st.spd / d.vMax * 10, 70, 82) or 70
    if (st.uav and st.dcam == "nose") or st.eo then fovT = 70 / st.zoomS end
    if st.bsight and st.bsFov then fovT = st.bsFov end
    st.fov = st.fov or cam.FieldOfView
    st.fov += (fovT - st.fov) * math.min(1, dt * ((st.uav and 10) or 4))
    -- 开火、打中都不再晃镜头、收视场角（用户 11-27「机炮开打的时候屏幕不要往前拉 就正常就行 也别搞后坐力」）
    cam.FieldOfView = st.fov
    if mslHold then cam.CFrame, cam.FieldOfView = mslHold[1], mslHold[2] end   -- 跟踪导弹：镜头还给 MslCam
    -- 瞄准点：镜头中间（固定翼：鼠标瞄准方向）打出去碰到的地方
    local ex = { G.viewFolder }
    if me.Character then table.insert(ex, me.Character) end
    table.insert(ex, st.em)
    aimParams.FilterDescendantsInstances = ex
    local adir = lookDir()
    local o = (d.kind == "jet" and not st.eo) and pos or cam.CFrame.Position
    local far = (st.eo or st.uav) and 24000 or 9000   -- 光电吊舱、前视光电看得远（八公里多）
    local res = G.rayFar(o + adir * (d.L * 0.6), adir * far, aimParams)   -- 光电吊舱看八公里外：远处没加载的地形按高度算（Stream.lua）
    st.aimPt = res and res.Position or (o + adir * far)
    if d.kind == "jet" and st.pilot and not st.uav and not st.eo and not st.crashed then
      if WT_GUNS then   -- 战雷：机炮顺着机头打，只画敌机的提前量圈（st.lead；keep 用 st.stick 那一套，这里存在 st.lead）
        local keep0 = st.stick
        st.stick = st.leadKeep
        st.lead = gunStick(true)
        st.leadKeep, st.stick = st.lead, nil
        if keep0 then st.stickV = nil end
      else   -- MWT（11-21）：机炮黏住目标，瞄准点换成目标的提前量（发给服务器）
        st.stick = gunStick()
        if st.stick then st.aimPt = st.stick.lead end
      end
    else
      st.stick, st.lead, st.leadKeep = nil, nil, nil
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
    st.bayS = approach(st.bayS, bs and 1 or 0, dt * (d.sideArm and 0.9 or 2.5))   -- 歼-20 侧弹舱：开门、转出、关门三段，一秒多一点
    st.c.bay, st.c.bayS = st.bay, st.bayS
    -- 开火：鼠标左键 机炮按住连发（扳机发给服务器）；F 挂的弹一下一发（火箭按住连发）。没有炮的飞机左键也发挂的弹
    --   手机：开火键按选中的那种（选的是炮就打炮）
    if st.pilot then
      local _, cw = curW()
      local touchGun = touch and touch.fire and cw and cw.kind == "gun"
      local gunOn = gid ~= nil and ((st.firing and not G.mobile) or touchGun or false)
      if gid then setTrig(gunOn) end
      local fireS = st.missile or (st.firing and not gid) or (touch and touch.fire and not touchGun)
      if w and w.nuke then   -- 核导弹（惊雷-1）：要按住 1.2 秒才发（免得手滑）；HUD 中间一条解锁进度（客户端 Nuke.lua）
        local HOLD = 1.2
        if fireS and left(wid) > 0 and not st.fireLatch then
          st.nukeHold = (st.nukeHold or 0) + dt
          if st.nukeHold >= HOLD then
            fireStore(wid, w)
            st.fireLatch, st.nukeHold = true, 0
          end
        elseif not fireS then
          st.nukeHold, st.fireLatch = 0, false
        end
        if G.nukeArmUI then G.nukeArmUI(left(wid) > 0, (st.nukeHold or 0) / HOLD) end
      elseif w and fireS then
        if G.nukeArmUI then G.nukeArmUI(false) end
        if w.kind == "rkt" or not st.fireLatch then fireStore(wid, w) end
        st.fireLatch = true
      else
        if G.nukeArmUI then G.nukeArmUI(false) end
        st.fireLatch = false
      end
    end
    -- 战雷的 CCRP（Alt + 中键标的目标点）：落点顺着航迹走到目标点就自动投（按投弹数量；齐投让一串的中间落在目标上）；
    --   航向偏得多（落点从目标旁边超过七成杀伤半径走过）这一趟不投，掉头再来。在地上、瞄准镜外面也照样算（屏幕上的箭头在 Bombsight.lua）
    st.ccrp = nil
    if st.bsight and (st.ground or st.crashed or not st.pilot) then setBS(false) end
    if st.poi and st.pilot and d.kind == "jet" and not st.ground and not st.crashed then
      local bw, bww = bombW()
      if bw then
        local imp, tf
        if st.bsight and st.bsImp then imp, tf = st.bsImp, st.bsTf else imp, tf = bombNow() end
        local hv = V(st.vel.X, 0, st.vel.Z)
        local gs = hv.Magnitude
        if gs > 10 then
          local dir = hv / gs
          local rel = V(st.poi.X - imp.X, 0, st.poi.Z - imp.Z)
          local along = rel:Dot(dir)
          local crossM = (rel - dir * along).Magnitude
          -- 要转多少度：航迹穿过目标点落点才走得到——从飞机正下方看目标点的方向和航迹差的角（正的往右转）
          local to = V(st.poi.X - pos.X, 0, st.poi.Z - pos.Z)
          local dev = 0
          if to.Magnitude > 1 then
            local tu = to.Unit
            dev = -deg(math.atan2(dir:Cross(tu).Y, dir:Dot(tu)))
          end
          local nb = (bombSeries == 0) and left(bw) or math.min(bombSeries, left(bw))
          local lead = (bombSeries == 0) and (nb - 1) * 0.5 * SERIES_GAP * gs or 0
          local ttr = (along - lead) / gs
          local ok = crossM <= math.max(14, (bww.splash or 24) * 0.7)
          if ttr > 0.3 then st.ccrpArm = true end
          if st.ccrpArm and ttr <= 0 then
            if not ok or ttr < -0.6 then
              st.ccrpArm = false   -- 偏了 / 投不出去（上一串还没投完）：这一趟算了
            elseif fireStore(bw, bww, st.poi) then   -- 制导炸弹照目标点的坐标飞（像杰达姆）
              st.ccrpArm = false
              st.ccrpRelT = os.clock()
            end
          end
          st.ccrp = { ttr = ttr, dev = dev, ok = ok, cross = crossM, tf = tf, passed = ttr < 0 and not st.ccrpArm }
        end
      end
    end
    -- 锁定：选中的弹要锁的话，目标在视场里待够锁定时间
    if st.pilot and w and (w.kind == "aam" or w.kind == "agm" or (w.kind == "bomb" and w.guided)) then
      local rdl = st.rdLock   -- 雷达的单目标跟踪（Radar.lua）：跟选的什么弹无关
      if radarManual(w) then
        -- 雷达弹锁的就是雷达跟踪着的：STT，或者 TWS 里指定的航迹（不用 STT：对方告警器不报锁定，Radar.lua 每次航迹更新报一次数据链）
        local want = (rdl and rdl.em) or (G.radarTwsSel and G.radarTwsSel(st)) or nil
        if st.lock and st.lock.em ~= want then st.lock, st.lockT = nil, 0 end
        if st.lock then st.lock.tws = rdl == nil end   -- 指定航迹上又按了 Alt+F（进了 STT）/ STT 丢了还在航迹里：同一架，换个跟法
        if not st.lock and want then
          local c = candOf(w, want)
          if c and inTrack(w, c) then
            c.tws = rdl == nil
            st.lock, st.lockT = c, 0
          end
        end
      elseif rdl and not rdl.mem and w.kind == "aam" and w.seeker == "ir" and not (st.lock and st.lock.em == rdl.em) then
        -- 红外弹的导引头跟着雷达指：雷达锁着的在导引头视场里就先咬它（不按离机头最近的挑）
        local c = candOf(w, rdl.em)
        if c and inCone(w, c) then
          c.slaved = true
          st.lock, st.lockT = c, 0
        end
      end
      if st.lock and (not st.lock.em.Parent or st.lock.em:GetAttribute("Wreck")) then st.lock = nil end
      if st.lock then
        local root = st.lock.em:FindFirstChild("Root")
        if root then
          local to = root.CFrame.Position - pos
          local d0 = st.lock.dist
          st.lock.dir, st.lock.dist, st.lock.pos = to.Unit, to.Magnitude, root.CFrame.Position
          if d0 and dt > 0 then   -- 接近速度（米 / 秒，近了为正）：战雷式锁定框右边写的那个，平滑一下
            local vc = (d0 - st.lock.dist) / dt / AD.M
            st.lock.vc = st.lock.vc and (st.lock.vc + (vc - st.lock.vc) * math.min(1, dt * 3)) or vc
          end
          -- 雷达弹（战雷）：雷达得一直跟着它——STT 这一帧看得见（它侧着飞把你放在 3 / 9 点置零、钻进地杂波、出了万向架时 Radar.lua 先按记忆外推，
          --   这时进度不涨、不能发射；记忆外推 RD.MEM 秒还没找回来 Radar.lua 丢锁、提示，上面 want 没了这里跟着丢）；TWS 的航迹还在（没过期）
          local rOk, rWhy = true, nil
          if radarManual(w) then
            if st.lock.tws then
              rOk = G.radarTrackOf ~= nil and G.radarTrackOf(st, st.lock.em) ~= nil
              rWhy = (not rOk) and "track" or nil
            else
              rOk = rdl ~= nil and rdl.em == st.lock.em and not rdl.mem
              rWhy = (rdl and rdl.why) or "track"
            end
          end
          st.lock.radarWhy = (not rOk) and rWhy or nil
          -- 在离轴角里：锁定进度往上走；出了离轴角、还在跟踪范围里：锁留着（菱形变黄、不能发射，进度不涨），偏出去 4 秒才丢
          local inside = inCone(w, st.lock) and rOk
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
        if not radarManual(w) then st.lock = pickTarget(w) end   -- 雷达弹照战雷手动锁（R / Alt+T 选、Alt+F 锁），不自动挑
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
      if G.airAudioEvent then G.airAudioEvent("flare") end
    end
    st.sendT -= dt
    if st.sendT <= 0 and st.pilot and not st.crashed then
      st.sendT = math.max(st.sendT + 1 / 15, 0)   -- 按平均每秒 15 次（原来每次重设，帧率低时间隔拖成两三帧）
      local c = st.c
      G.R.Drive:FireServer({ op = "state", cf = st.cf, v = st.vel, gd = st.ground, aim = st.aimPt, eo = st.eo or nil, stk = st.stick ~= nil, thr = c.thr, gear = c.gear, flap = c.flap, cp = c.pit, cr = c.rol,
        cy = c.yaw, bay = c.bay, bays = c.bayS, rpm = c.rpm, col = c.col, can = c.can, hook = c.hook, brk = c.brk, ty = c.ty, gp = c.gp, fold = c.fold })
    end
    -- 平显
    local em = st.em
    local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
    hpBar.Size = UDim2.fromScale(clamp(hp / mx, 0, 1), 1)
    hpBar.BackgroundColor3 = ui.hpColor(hp / mx)
    local tk = em:GetAttribute("TreeKey")   -- 科技树出的飞机写科技树里的名字
    aName.Text = (tk and T("tree." .. tk) or T("veh." .. d.id)) .. (st.pilot and "" or ("   " .. T("air.passenger")))
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
    st.help = st.pilot and (st.uav and "air.helpUav" or ((d.kind == "jet") and (mouseAim and "air.helpJet" or "air.helpJetKb") or "air.helpHeli")) or "air.helpPass"
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
      info.fuelT = left2   -- 战雷式左上参数表（WtFlight.lua）：燃油量写还能飞几分几秒
      info.fuelCol = (tot < 0.1) and RGB(255, 90, 80) or ((tot < 0.25) and RGB(255, 200, 90) or nil)
      info.thr = thrText.Text
      info.vs = T("air.vs", vsText.Text)
      info.gear = (d.kind == "jet" and st.gearWant > 0.5) and T("air.gearState.down") or nil
      if d.kind == "jet" and st.ovr then info.gear = (info.gear and (info.gear .. " · ") or "") .. T("air.ovrTag") end
      local bp, bon = project(pos + st.cf.LookVector * 400)
      bore.Position, bore.Visible = bp, bon and not st.eo and not G.wtFlightOn   -- 战雷式界面（WtFlight.lua）有自己的机头 ⊕
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
      -- 战雷式界面（WtFlight.lua）开着时不画这个绿大圈：导弹的大圈小圈按导引头真实的离轴角画（锁定前白、锁上红）
      local wtOn = G.wtFlightOn == true
      ring.Size, ring.Position, ring.Visible = UDim2.fromOffset(px, px), bp, bon and not st.eo and not st.uav and not wtOn
      ringText.Position, ringText.Visible = bp + UDim2.fromOffset(0, px / 2 - 30), bon and not st.eo and not st.uav and not wtOn
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
      elseif st.rwrLockT and os.clock() < st.rwrLockT then warn = ((os.clock() * 2) % 1 < 0.7) and T(st.rwrLockFull and "air.radarLock" or "air.radarTrack") or ""
      elseif st.out and not st.ground then warn = T("air.flameout")
      elseif st.oob or st.em:GetAttribute("Oob") then   -- 出作战区：服务器读的秒（Air.lua oobStep）
        local left = st.em:GetAttribute("Oob")
        warn = left and T("air.oobT", left) or T("air.oob")
      elseif d.kind == "jet" and not st.ground and st.spd < d.stall * 1.05 then warn = T("air.stall")
      elseif os.clock() - (st.floatT or -9) < 0.6 then warn = T("air.tooFast")   -- 接地太快、贴着跑道飘：收油门
      elseif not st.ground and agl < 60 and st.vel.Y < -25 then warn = T("air.pullup")
      elseif not st.ground and st.fuel + st.fuelX < 0.12 then warn = ((os.clock() * 2) % 1 < 0.6) and T("air.bingo") or "" end   -- 油不多了：该回去了
      warnText.Text = warn or ""
      warnText.Visible = warn ~= nil
      -- 提示音、告警音（AirAudio.lua，用户 11-24：「把开飞机的各种 ui 声音做成战雷」）：导引头声、雷达弹锁定、导弹来袭、失速、拉起、油少、熄火、起落架
      if G.airAudioStep then
        local lk = st.lock
        G.airAudioStep(dt, { on = st.pilot == true and not st.crashed and not st.uav, w = w, hasTgt = lk ~= nil, lockT = st.lockT or 0,
          locked = lk ~= nil and w ~= nil and (st.lockT or 0) >= (w.lockTime or 1), out = lk ~= nil and lk.out == true,
          rwr = st.rwrT ~= nil and os.clock() < st.rwrT, flameout = (st.out == true or (G.wtaFlight and (G.wtaFlight(st.em) or {}).eng == 0)) and not st.ground,   -- 发动机打坏了也报熄火
          rwrLock = st.rwrLockT ~= nil and os.clock() < st.rwrLockT, rwrFull = st.rwrLockFull == true,   -- 被敌机雷达锁着（A 加的，服务器转告）
          stall = d.kind == "jet" and not st.ground and st.spd < d.stall * 1.05,
          pullup = not st.ground and agl < 60 and st.vel.Y < -25, bingo = not st.ground and st.fuel + st.fuelX < 0.12,
          gear = (d.kind == "jet") and st.gear or nil, hp = hp / math.max(mx, 1) })
      end
      -- 落地补给（用户：降落回去可以回血、补武器）：服务器 Rest 属性——1～5 停稳倒计时、10 在自己的机场还在滑、
      --   −1 补完了正在修、−2 全好了、−3 这里不是自己的机场 / 甲板
      local rest = st.ground and em:GetAttribute("Rest") or 0
      local rtx, rcol = nil, RGB(120, 230, 140)
      if type(rest) ~= "number" or rest == 0 then rtx = nil
      elseif rest > 0 and rest <= 5 then rtx = T("air.restWait", math.floor(rest))
      elseif rest == 10 then rtx = T("air.restRoll")
      elseif rest == -1 then rtx = T("air.restFix", math.floor(clamp(tonumber(em:GetAttribute("RestK")) or (hp / mx), 0, 1) * 100))   -- 服务器的补给进度（油、弹、部件、机身血里最慢的那样）
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
        -- 战雷式锁定（AirHud）：目标型号写在框上面，距离、接近速度写在右边；红外弹的导引头圈从机头滑到目标上
        local mdl = st.lock.em and st.lock.em:GetAttribute("Model")
        local nm = nil
        if mdl then
          for _, pre in ipairs({ "veh.", "ship.", "fort." }) do
            local tx = T(pre .. mdl)
            if tx ~= pre .. mdl then nm = tx break end
          end
          nm = nm or string.upper(mdl)
        end
        info.lock = { p = lp, on = lon, k = st.lockT / (w.lockTime or 1), locked = locked, inCone = not st.lock.out,
          name = nm, dist = st.lock.dist, vc = st.lock.vc, seeker = w.seeker or w.guide, bore = bp }
        if not st.uav then lockBox.Visible, lockText.Visible = false, false end   -- MWT 式界面：AirHud 画菱形和四个直角
      else
        lockBox.Visible, lockText.Visible = false, false
      end
      -- 锁定音（导引头嗡嗡、雷达弹嘀声）：B 的 AirAudio.lua（上面 G.airAudioStep），A 原来在这里那套 11-24 合并时去掉了（两套一起响）
      -- 雷达锁着敌机报服务器（lockOn：数据链、对方的告警）挪到了 Radar.lua：STT 跟踪着半秒一次、TWS 指定的航迹每次更新一次——跟选的什么弹无关
      -- 炸弹落点（不制导的、或者没锁上的制导炸弹）
      if w and w.kind == "bomb" and not (st.lock and st.lockT >= (w.lockTime or 1)) then
        local gp2, gon = project((bombNow()))   -- 按服务器的炸弹物理算（跟地上的红圈、瞄准镜十字一个点）
        pipper.Position, pipper.Visible = gp2, gon
      else
        pipper.Visible = false
      end
      if st.eo or st.bsight then   -- 吊舱 / 轰炸瞄准镜画面里：平显的落点、降落菱形、锁定框、机头标记、大圈都收起来（各自画自己的）
        pipper.Visible, landMark.Visible, landText.Visible, lockBox.Visible, lockText.Visible, restText.Visible = false, false, false, false, false, false
        bore.Visible, ring.Visible, ringText.Visible, aimRing.Visible = false, false, false, false
      end
    end
    -- MWT 式的界面（AirHud.lua）：有人开 / 坐的飞机都用；遥控无人机（战术平板）、光电吊舱的画面不用
    if not st.uav then dcs.Visible = false end
    warnText.Position = UDim2.new(0.5, 0, 0.5, st.uav and -130 or -172)   -- 告警：让开准星上方的武器名牌
    if not st.uav and not st.eo and not st.bsight then
      if st.pilot then info.aim = aimRing.Visible and aimRing.Position or nil end   -- 准星由 AirHud 画（发光的细圈），这里的「◯」字收起来
      -- 战雷式鼠标瞄准的小圈（屏幕上鼠标想去的方向）：AirHud 画白色细圈
      info.maim = nil
      if st.pilot and d.kind == "jet" and mouseAim and not st.uav and not G.mobile and not st.eo and not st.ground then
        local mp, mon = project(pos + aimRingDir() * 400)
        if mon then info.maim = mp end
      end
      -- 战雷式机炮提前量圈（AirHud 的 LeadMark）：敌机的提前量点、距离
      info.lead, info.leadDist = nil, nil
      if st.lead and st.lead.lead and st.pilot then
        local lp, lon = project(st.lead.lead)
        if lon then info.lead, info.leadDist = lp, st.lead.dist end
      end
      aimRing.Visible = false
      if G.airHudStep then G.try_(G.airHudStep, st, info) end
      if G.tankHudExtra then G.try_(G.tankHudExtra, st, clamp(hp / mx, 0, 1), "air") end   -- 左上圆形雷达、「被发现!」、敌人头顶带血条的名牌（TankHud.lua）
    elseif G.airHudOff then
      G.airHudOff()
    end
    -- 战雷式机载雷达屏（Radar.lua）：搜索 / 边扫边跟 / 近战扫描、单目标跟踪（st.rdLock，跟选的什么弹无关）
    if G.radarStep then G.try_(G.radarStep, st, dt) end
    -- 战雷的轰炸瞄准镜画面、CCRP 目标点的方框和箭头（Bombsight.lua）
    if G.bsDraw then
      local s2 = { on = st.bsight == true, poi = (st.pilot and not st.crashed) and st.poi or nil, ccrp = st.ccrp, relT = st.ccrpRelT }
      if s2.poi and not st.ccrp then s2.noBomb = bombW() == nil end
      if s2.on and st.bsImp then
        local bw = bombW() or curW()
        local hv = V(st.vel.X, 0, st.vel.Z)
        s2.imp, s2.tf, s2.gs = st.bsImp, st.bsTf, hv.Magnitude
        s2.dir = (hv.Magnitude > 1) and hv.Unit or nil
        s2.agl = (pos.Y - st.bsImp.Y) / AD.M
        s2.kmh = hv.Magnitude / AD.M * 3.6
        s2.mode, s2.zoom = bombSeries, st.bsZoom
        s2.wname, s2.left = bw and T("aw." .. bw) or "", bw and left(bw) or 0
      end
      G.try_(G.bsDraw, s2)
    end
  end

  -- 被击毁 / 跳伞：服务器推来 alive = false 或 veh = nil，下一帧 stop()
end

return Fly
