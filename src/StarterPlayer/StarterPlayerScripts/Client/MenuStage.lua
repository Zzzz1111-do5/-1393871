-- Roblox全面大战场（客户端）——主菜单背后的场景（用户给了《坠落》主菜单的截图：「初始界面用这种背景图改一下」）：
--   夜里废墟、暗红的火光、往上飘的火星和烟，一个全副武装的士兵（头盔、放下来的夜视仪、防弹插板背心、弹匣包，手里本阵营的枪）的低机位特写，
--   人在画面右边（左边是菜单卡片）。只在本机：零件搭在地图外很远的地方，主菜单开着时镜头对着它、慢慢呼吸似地晃，关了主菜单收起来、镜头还给游戏。
--   枪用服务器放在 ReplicatedStorage.ToolPreview 里的工具样子（导入了原模型就是原模型）；没有就用零件拼一支
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Stage = {}

local RGB = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ORIGIN = CF(9000, 900, -9000)   -- 地图外（地图在 ±3000 格以内）、半空里：周围什么都没有
local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }   -- 同 Round.lua 的迷彩色
local HELMET = { atk = RGB(96, 104, 72), def = RGB(146, 128, 96) }
local GEAR = { atk = RGB(70, 76, 56), def = RGB(118, 104, 80) }   -- 背心、弹匣包
local DARK = RGB(26, 26, 28)

local model, built, team0 = nil, false, nil
local fireLights, emitters = {}, {}
local cam0 = nil   -- 进主菜单前镜头的类型和视角（关了主菜单还回去）
local t = 0

local function part(parent, name, size, cf, color, mat, shape)
  local p = Instance.new("Part")
  p.Name = name
  p.Size = size
  p.CFrame = cf
  p.Color = color
  p.Material = mat or Enum.Material.SmoothPlastic
  if shape then p.Shape = shape end
  p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  p.Parent = parent
  return p
end
-- 从 a 到 b 的一截（手臂、腿）
local function limb(parent, name, a, b, w, color, mat)
  local d = (b - a).Magnitude
  return part(parent, name, V(w, w, d), CFrame.lookAt((a + b) / 2, b), color, mat)
end

-- 士兵（站在 at，面朝 -Z）；团队决定迷彩、头盔、背心颜色
local function soldier(parent, at, team)
  local U = UNIFORM[team] or UNIFORM.def
  local gear, helm = GEAR[team] or GEAR.def, HELMET[team] or HELMET.def
  local m = Instance.new("Model")
  m.Name = "Soldier"
  m.Parent = parent
  local function P(name, size, off, color, mat, shape) return part(m, name, size, at * off, color, mat, shape) end
  local function L(name, a, b, w, color, mat) return limb(m, name, (at * CF(a)).Position, (at * CF(b)).Position, w, color, mat) end
  -- 腿：左腿在前一点，右腿在后（站姿）；护膝、靴子
  for _, s in ipairs({ { -0.5, -0.25, 1 }, { 0.5, 0.35, -1 } }) do
    local x, z = s[1], s[2]
    L("Thigh", V(x, 2.95, 0), V(x * 1.05, 1.6, z * 0.6), 0.95, U[2], Enum.Material.Fabric)
    L("Shin", V(x * 1.05, 1.6, z * 0.6), V(x * 1.1, 0.45, z), 0.88, U[2], Enum.Material.Fabric)
    P("KneePad", V(0.72, 0.6, 0.3), CF(x * 1.05, 1.62, z * 0.6 - 0.48), DARK, Enum.Material.Plastic)
    P("Boot", V(0.98, 0.55, 1.3), CF(x * 1.1, 0.28, z - 0.2), RGB(36, 30, 26), Enum.Material.Leather)
  end
  -- 腰带、腿挂
  P("Belt", V(2.15, 0.42, 1.18), CF(0, 2.98, 0), DARK, Enum.Material.Fabric)
  P("DropPouch", V(0.5, 0.7, 0.45), CF(-1.05, 2.6, 0.15), gear, Enum.Material.Fabric)
  -- 上身、防弹插板背心、弹匣包、无线电
  P("Torso", V(2, 2.05, 1), CF(0, 4.15, 0), U[1], Enum.Material.Fabric)
  P("PlateFront", V(1.9, 1.55, 0.34), CF(0, 4.3, -0.62), gear, Enum.Material.Fabric)
  P("PlateBack", V(1.9, 1.6, 0.34), CF(0, 4.3, 0.62), gear, Enum.Material.Fabric)
  P("Cummerbund", V(2.12, 0.7, 1.3), CF(0, 3.62, 0), gear, Enum.Material.Fabric)
  for i = -1, 1 do
    P("MagPouch", V(0.46, 0.66, 0.3), CF(i * 0.52, 3.72, -0.86), gear:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Fabric)
    P("MagFlap", V(0.48, 0.12, 0.34), CF(i * 0.52, 4.08, -0.87), gear:Lerp(Color3.new(0, 0, 0), 0.22), Enum.Material.Fabric)
  end
  P("Radio", V(0.5, 0.9, 0.4), CF(-0.62, 4.3, 0.98), DARK, Enum.Material.Plastic)
  P("Antenna", V(0.06, 1.6, 0.06), CF(-0.75, 5.4, 1.05) * CFrame.Angles(math.rad(-8), 0, math.rad(6)), DARK, Enum.Material.Metal)
  for _, sx in ipairs({ -1, 1 }) do P("Strap", V(0.36, 0.25, 1.36), CF(sx * 0.62, 5.12, 0), gear, Enum.Material.Fabric) end
  -- 头：面罩、耳机、头盔、放下来的夜视仪
  P("Neck", V(0.62, 0.35, 0.62), CF(0, 5.3, 0), DARK, Enum.Material.Fabric)
  local head = P("Head", V(1.15, 1.15, 1.15), CF(0, 5.95, -0.05) * CFrame.Angles(0, math.rad(-12), 0), RGB(34, 34, 36), Enum.Material.Fabric)
  local hc = head.CFrame
  local function H(name, size, off, color, mat) return part(m, name, size, hc * off, color, mat) end
  local shell = H("Helmet", V(1.46, 0.92, 1.56), CF(0, 0.45, 0.04), helm, Enum.Material.Fabric)
  local sm = Instance.new("SpecialMesh")
  sm.MeshType = Enum.MeshType.Sphere
  sm.Parent = shell
  H("HelmetRim", V(1.5, 0.14, 1.6), CF(0, 0.1, 0.04), helm:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Fabric)
  for _, sx in ipairs({ -1, 1 }) do
    H("Rail", V(0.1, 0.18, 0.8), CF(sx * 0.74, 0.32, 0.05), DARK, Enum.Material.Metal)
    H("EarCup", V(0.26, 0.6, 0.5), CF(sx * 0.66, -0.02, 0.05), RGB(52, 56, 46), Enum.Material.Plastic)
  end
  H("NVGMount", V(0.36, 0.26, 0.18), CF(0, 0.42, -0.78), DARK, Enum.Material.Metal)
  H("NVGBody", V(0.66, 0.22, 0.24), CF(0, 0.12, -0.9), RGB(30, 32, 34), Enum.Material.Metal)
  for _, sx in ipairs({ -1, 1 }) do
    local tube = H("NVGTube", V(0.34, 0.26, 0.26), CF(sx * 0.2, 0.03, -1.04) * CFrame.Angles(0, math.rad(90), 0), RGB(24, 26, 28), Enum.Material.Metal, nil)
    tube.Shape = Enum.PartType.Cylinder
    local lens = H("NVGLens", V(0.04, 0.2, 0.2), CF(sx * 0.2, 0.03, -1.18) * CFrame.Angles(0, math.rad(90), 0), RGB(40, 120, 70), Enum.Material.Neon)
    lens.Shape = Enum.PartType.Cylinder
    lens.Transparency = 0.35
  end
  H("Strobe", V(0.22, 0.14, 0.14), CF(0, 0.55, 0.78), DARK, Enum.Material.Plastic)
  -- 手臂：右手握把、左手护木（低姿持枪）；肩、肘、手的位置先定，再拉两截
  local T = V(0, 4.15, 0)
  local hands = { R = T + V(0.45, -0.35, -0.9), L = T + V(-0.4, -0.78, -1.62) }   -- 低姿持枪：护木的左手比握把低，枪口朝前下
  for _, s in ipairs({ { "R", 1 }, { "L", -1 } }) do
    local sh = T + V(s[2] * 1.12, 0.78, 0)
    local hand = hands[s[1]]
    local elbow = (sh + hand) / 2 + V(s[2] * 0.42, -0.5, 0.2)
    L("UpperArm", sh, elbow, 0.86, U[1], Enum.Material.Fabric)
    L("Forearm", elbow, hand, 0.8, U[1], Enum.Material.Fabric)
    P("Glove", V(0.62, 0.62, 0.62), CF(hand), RGB(30, 30, 30), Enum.Material.Leather)
    P("ShoulderPad", V(0.95, 0.4, 1.05), CF(sh + V(0, 0.15, 0)), gear, Enum.Material.Fabric)
  end
  -- 枪：右手到左手的方向，枪口朝前下方
  local grip = at * CF(hands.R)
  local fore = (at * CF(hands.L)).Position
  local dir = (fore - grip.Position).Unit
  local gunCF = CFrame.lookAt(grip.Position, grip.Position + dir)
  local prev = RS:FindFirstChild("ToolPreview")
  local tool = nil
  if prev and prev:FindFirstChild(team) then
    for _, tl in ipairs(prev[team]:GetChildren()) do
      if tl:GetAttribute("Weapon") == "m4" then tool = tl end
    end
  end
  local placed = false
  if tool then
    local ok = pcall(function()
      local c = tool:Clone()
      local handle = c:FindFirstChild("Handle")
      if not handle then error("no handle") end
      local g = Instance.new("Model")
      g.Name = "Rifle"
      for _, x in ipairs(c:GetDescendants()) do
        if x:IsA("BasePart") then x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false end
      end
      -- 握持：握点 × 工具 Grip 的逆 = 把手（Roblox 拿工具就是这么焊的）；游戏里的枪沿把手的 −Z 朝前，握点的 −Z 对着枪口方向
      local rel = {}
      for _, x in ipairs(c:GetDescendants()) do
        if x:IsA("BasePart") then rel[x] = handle.CFrame:ToObjectSpace(x.CFrame) end
      end
      local hcf = gunCF * c.Grip:Inverse()
      for x, r in pairs(rel) do x.CFrame = hcf * r end
      for _, x in ipairs(c:GetChildren()) do x.Parent = g end
      c:Destroy()
      g.Parent = m
    end)
    placed = ok
  end
  if not placed then   -- 零件拼一支卡宾枪
    local function G2(name, size, off, color, mat) return part(m, name, size, gunCF * off, color, mat) end
    G2("Receiver", V(0.22, 0.38, 1.3), CF(0, 0.12, -0.35), DARK, Enum.Material.Metal)
    G2("Handguard", V(0.24, 0.26, 1.15), CF(0, 0.16, -1.5), RGB(34, 34, 36), Enum.Material.Metal)
    G2("Barrel", V(0.08, 0.08, 0.7), CF(0, 0.16, -2.4), RGB(20, 20, 22), Enum.Material.Metal)
    G2("Stock", V(0.2, 0.36, 0.95), CF(0, 0.06, 0.65), DARK, Enum.Material.Plastic)
    G2("Mag", V(0.16, 0.6, 0.3), CF(0, -0.3, -0.62) * CFrame.Angles(math.rad(12), 0, 0), DARK, Enum.Material.Metal)
    G2("Optic", V(0.18, 0.2, 0.42), CF(0, 0.42, -0.45), RGB(16, 16, 18), Enum.Material.Metal)
    G2("Grip", V(0.18, 0.45, 0.24), CF(0, -0.18, 0.05) * CFrame.Angles(math.rad(-15), 0, 0), DARK, Enum.Material.Plastic)
  end
  return m
end

local function build(team)
  model = Instance.new("Model")
  model.Name = "MenuStage"
  local o = ORIGIN
  local function W(name, size, off, color, mat) return part(model, name, size, o * off, color, mat) end
  -- 地面、瓦砾（随机数固定种子：每次一样）
  W("Ground", V(90, 1, 90), CF(0, -0.5, 0), RGB(36, 32, 30), Enum.Material.Concrete)
  local rnd = Random.new(7)
  for i = 1, 46 do
    local s = rnd:NextNumber(0.4, 2.6)
    local x, z = rnd:NextNumber(-22, 22), rnd:NextNumber(-6, 24)
    if math.abs(x) > 2.4 or z > 3 then
      local c = (rnd:NextNumber() < 0.5) and RGB(58, 50, 44) or RGB(44, 40, 38)
      W("Rubble", V(s * rnd:NextNumber(0.6, 1.6), s * rnd:NextNumber(0.3, 0.8), s), CF(x, s * 0.2, z) * CFrame.Angles(rnd:NextNumber(-0.4, 0.4), rnd:NextNumber(0, 6.28), rnd:NextNumber(-0.4, 0.4)),
        c, (i % 3 == 0) and Enum.Material.Brick or Enum.Material.Concrete)
    end
  end
  -- 后面一堵烧过的残墙：窗洞里透出外面的火光；柱子、断梁
  -- （镜头朝 +Z 看：屏幕右边是 −X、左边是 +X）
  W("WallL", V(26, 22, 2), CF(-12, 10, 26), RGB(50, 40, 34), Enum.Material.Brick)
  W("WallR", V(26, 22, 2), CF(24, 10, 26), RGB(48, 38, 32), Enum.Material.Brick)
  W("WallTop", V(10, 8, 2), CF(6, 17, 26), RGB(46, 36, 30), Enum.Material.Brick)
  W("WallLow", V(10, 5, 2), CF(6, 2.5, 26), RGB(46, 36, 30), Enum.Material.Brick)
  local glow = W("WindowGlow", V(10, 8, 0.4), CF(6, 9, 29), RGB(255, 120, 40), Enum.Material.Neon)
  glow.Transparency = 0.55
  W("Pillar", V(2.4, 24, 2.4), CF(-5, 11, 16), RGB(40, 34, 30), Enum.Material.Concrete)
  W("Beam", V(16, 1.4, 1.4), CF(-9, 6, 20) * CFrame.Angles(0, -0.3, -0.45), RGB(30, 26, 24), Enum.Material.Wood)
  W("SideWall", V(2, 16, 30), CF(-24, 8, 12), RGB(42, 36, 32), Enum.Material.Brick)
  -- 左后方一辆烧毁的车
  local car = Instance.new("Model")
  car.Name = "Wreck"
  car.Parent = model
  local cc = o * CF(12, 0, 14) * CFrame.Angles(0, -0.5, 0)
  local function C(name, size, off, color, mat, shape)
    return part(car, name, size, cc * off, color, mat, shape)
  end
  C("Body", V(6, 2.2, 11), CF(0, 1.8, 0), RGB(30, 27, 25), Enum.Material.CorrodedMetal)
  C("Cab", V(5.6, 2, 5), CF(0, 3.9, 1.5), RGB(26, 24, 22), Enum.Material.CorrodedMetal)
  for _, w in ipairs({ { -3, -3.5 }, { 3, -3.5 }, { -3, 3.5 }, { 3, 3.5 } }) do
    C("Wheel", V(0.9, 2.4, 2.4), CF(w[1], 1.1, w[2]), RGB(18, 18, 18), Enum.Material.Rubber, Enum.PartType.Cylinder)
  end
  -- 士兵
  soldier(model, o * CF(0, 0, 0) * CFrame.Angles(0, math.rad(-24), 0), team)   -- 朝镜头、稍微侧向左边的菜单
  -- 火：右前方地上（画面外）一堆烧着的瓦砾照亮士兵；车里也有余火；后面窗洞外的火
  local function fire(at, heat, size, light)
    local f = W("Fire", V(2, 1, 2), at, RGB(40, 30, 24), Enum.Material.Slate)
    local fi = Instance.new("Fire")
    fi.Heat, fi.Size = heat, size
    fi.Color, fi.SecondaryColor = RGB(255, 120, 40), RGB(255, 210, 120)
    fi.Parent = f
    if light then
      local pl = Instance.new("PointLight")
      pl.Color, pl.Range, pl.Brightness, pl.Shadows = RGB(255, 130, 60), light, 2.4, true
      pl.Parent = f
      table.insert(fireLights, { l = pl, b = 2.4, seed = #fireLights * 1.7 })
    end
    return f
  end
  fire(CF(-6, 0.5, -4), 9, 6, 26)
  fire(CF(12, 2.4, 13), 6, 4, 16)
  fire(CF(6, 0.5, 33), 12, 10, 30)
  -- 冷色的轮廓光：左后方一点蓝灰，把人从暗背景里勾出来
  do
    local rim = W("Rim", V(1, 1, 1), CF(7, 8, 8), Color3.new(0, 0, 0))
    rim.Transparency = 1
    local pl = Instance.new("PointLight")
    pl.Color, pl.Range, pl.Brightness = RGB(130, 150, 200), 18, 0.7
    pl.Parent = rim
  end
  -- 火星：从火堆一带往上飘、随风往左；烟：大团、慢慢往上
  local src = W("Embers", V(26, 1, 20), CF(-2, 0.5, 6), Color3.new(0, 0, 0))
  src.Transparency = 1
  local em = Instance.new("ParticleEmitter")
  em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
  em.Color = ColorSequence.new(RGB(255, 170, 70), RGB(255, 90, 30))
  em.LightEmission = 1
  em.LightInfluence = 0
  em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.03) })
  em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) })
  em.Lifetime = NumberRange.new(3.5, 7)
  em.Rate = 26
  em.Speed = NumberRange.new(1.5, 4.5)
  em.SpreadAngle = Vector2.new(35, 35)
  em.Acceleration = V(1.2, 1.4, 0)   -- 往屏幕左边飘
  em.RotSpeed = NumberRange.new(-90, 90)
  em.EmissionDirection = Enum.NormalId.Top
  em.Parent = src
  table.insert(emitters, em)
  local sm = Instance.new("ParticleEmitter")
  sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
  sm.Color = ColorSequence.new(RGB(70, 60, 56), RGB(30, 28, 28))
  sm.LightInfluence = 0.6
  sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) })
  sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) })
  sm.Lifetime = NumberRange.new(8, 13)
  sm.Rate = 2.5
  sm.Speed = NumberRange.new(0.6, 1.8)
  sm.SpreadAngle = Vector2.new(25, 25)
  sm.Acceleration = V(0.4, 0.5, 0)
  sm.RotSpeed = NumberRange.new(-12, 12)
  sm.EmissionDirection = Enum.NormalId.Top
  sm.Parent = src
  table.insert(emitters, sm)
  built, team0 = true, team
end

-- 镜头：低机位、离人十来格，人在画面右边（镜头朝 +Z 看，看向人的 +X 一侧 = 屏幕左边一点）
local function camCF(k)
  local o = ORIGIN
  local eye = (o * CF(2.2 + math.sin(k * 0.21) * 0.25, 3.1 + math.sin(k * 0.37) * 0.12, -11.5)).Position
  local look = (o * CF(2.7, 4.3, 0)).Position
  return CFrame.lookAt(eye, look)
end

-- 打开 / 关上（Menu.lua 调）
function Stage.show(on, team)
  local cam = workspace.CurrentCamera
  if on then
    if built and team0 ~= team and model then   -- 换了阵营：换身衣服、换枪
      model:Destroy()
      built, model, fireLights, emitters = false, nil, {}, {}
    end
    if not built then
      local ok, err = pcall(build, team or "def")
      if not ok then warn("[全面大战场] 主菜单背景没搭好：" .. tostring(err)) return end
    end
    model.Parent = workspace
    for _, e in ipairs(emitters) do e.Enabled = true end
    if not cam0 then cam0 = { type = cam.CameraType, fov = cam.FieldOfView } end
    cam.CameraType = Enum.CameraType.Scriptable
    cam.FieldOfView = 38
    cam.CFrame = camCF(t)
  else
    if model and model.Parent then
      for _, e in ipairs(emitters) do e.Enabled = false end
      model.Parent = nil
    end
    if cam0 then
      cam.CameraType = cam0.type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or cam0.type
      cam.FieldOfView = cam0.fov
      cam0 = nil
    end
  end
end

function Stage.step(dt)
  if not (model and model.Parent) then return end
  t += dt
  workspace.CurrentCamera.CFrame = camCF(t)
  for _, f in ipairs(fireLights) do   -- 火光闪
    f.l.Brightness = f.b * (0.78 + 0.16 * math.sin(t * 9.3 + f.seed) + 0.1 * math.sin(t * 23.1 + f.seed * 2))
  end
end

function Stage.active() return model ~= nil and model.Parent ~= nil end

return Stage
