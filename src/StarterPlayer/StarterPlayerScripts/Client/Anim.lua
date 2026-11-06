-- 军事大亨（客户端）：建筑动画（都在本地播，不占网络）——
--   新盖的楼（模型属性 BuiltAt 是刚才）：零件从地下按高度一层层升上来，四角搭着脚手架、落地扬尘；
--   零件属性 Anim = "spin" 的绕竖轴转（雷达），"blink" 的一闪一闪（指示灯、跑道灯）；
--   买得起的绿色购买按钮一呼一吸，隔一会儿冒一圈光
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Anim = {}

function Anim.init(G)
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local spinning = {}   -- [part] = { cf0, spd, model }
  local blinking = {}   -- [part] = { spd, tr0 }
  local pads = {}       -- [pad] = true
  local busy = {}       -- [model] = 升起动画放完的时刻（这之前不转）
  local GREEN = RGB(70, 220, 100)

  local function register(m)
    for _, d in ipairs(m:GetDescendants()) do
      if d:IsA("BasePart") then
        local a = d:GetAttribute("Anim")
        if a == "spin" then
          spinning[d] = { cf0 = d.CFrame, spd = d:GetAttribute("Spd") or 0.3, model = m }
        elseif a == "blink" then
          blinking[d] = { spd = d:GetAttribute("Spd") or 1, tr0 = d.Transparency, ph = math.random() * 6 }
        end
      end
    end
  end

  -- 从地里升起来：每个零件先沉到地下，按离地高度依次升回原位
  local function rise(m)
    local parts = {}
    local y0, y1 = math.huge, -math.huge
    for _, d in ipairs(m:GetDescendants()) do
      if d:IsA("BasePart") then
        table.insert(parts, d)
        local p = d.CFrame.Position
        y0 = math.min(y0, p.Y - d.Size.Y / 2)
        y1 = math.max(y1, p.Y + d.Size.Y / 2)
      end
    end
    if #parts == 0 then return end
    local h = math.max(4, y1 - y0)
    local total = 1.6
    busy[m] = os.clock() + total + 0.3
    for _, p in ipairs(parts) do
      local cf = p.CFrame
      local k = math.clamp((cf.Position.Y - y0) / h, 0, 1)
      p.CFrame = cf - V(0, h + 2, 0)
      task.delay(k * total * 0.55, function()
        if p.Parent then TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf }):Play() end
      end)
    end
    -- 脚手架：四角的黄色立杆 + 顶上一圈，盖完淡掉
    local body = m.PrimaryPart
    if body and G.fxPart then
      local c = body.CFrame.Position
      local sx, sz = body.Size.X / 2 + 1.5, body.Size.Z / 2 + 1.5
      local poles = {}
      for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local pole = G.fxPart(nil, V(0.5, h, 0.5), CFrame.new(c.X + o[1] * sx, y0 + h / 2, c.Z + o[2] * sz), RGB(240, 190, 40), Enum.Material.Metal, 0)
        table.insert(poles, pole)
      end
      for _, o in ipairs({ { 0, -1, 2 * sx, 0.4 }, { 0, 1, 2 * sx, 0.4 }, { -1, 0, 0.4, 2 * sz }, { 1, 0, 0.4, 2 * sz } }) do
        local bar = G.fxPart(nil, V(o[3], 0.4, o[4]), CFrame.new(c.X + o[1] * sx, y0 + h, c.Z + o[2] * sz), RGB(240, 190, 40), Enum.Material.Metal, 0)
        table.insert(poles, bar)
      end
      task.delay(total, function()
        for _, q in ipairs(poles) do
          if q.Parent then
            TweenService:Create(q, TweenInfo.new(0.5), { Transparency = 1 }):Play()
            Debris:AddItem(q, 0.55)
          end
        end
      end)
      -- 扬尘
      for i = 1, 10 do
        local a = i / 10 * math.pi * 2
        local q = V(c.X + math.cos(a) * sx, y0 + 1, c.Z + math.sin(a) * sz)
        local sm = G.fxPart(Enum.PartType.Ball, V(3, 3, 3), CFrame.new(q), RGB(196, 186, 160), Enum.Material.SmoothPlastic, 0.3)
        TweenService:Create(sm, TweenInfo.new(1.4), { Size = V(9, 9, 9), Transparency = 1, CFrame = CFrame.new(q + V(0, 4, 0)) }):Play()
        Debris:AddItem(sm, 1.5)
      end
      task.delay(total * 0.9, function()
        if G.playSound then G.playSound("build", c) end
      end)
    end
  end

  local function onBuilding(m)
    if not m:IsA("Model") then return end
    local at = m:GetAttribute("BuiltAt")
    local fresh = type(at) == "number" and (workspace:GetServerTimeNow() - at) < 4
    register(m)   -- 先记下原位（升起动画会先把零件沉到地下）
    if fresh then rise(m) end
  end
  local function onPad(m)
    local pad = m:FindFirstChild("Pad")
    if pad then pads[pad] = true end
  end

  local function watch(folder, fn)
    folder.ChildAdded:Connect(function(c)
      task.wait()
      if c.Parent then fn(c) end
    end)
    for _, c in ipairs(folder:GetChildren()) do fn(c) end
  end
  task.spawn(function()
    local plots = workspace:WaitForChild("Plots")
    local function onPlot(p)
      local b = p:WaitForChild("Buildings", 30)
      if b then watch(b, onBuilding) end
      local pd = p:WaitForChild("Pads", 30)
      if pd then watch(pd, onPad) end
    end
    plots.ChildAdded:Connect(onPlot)
    for _, p in ipairs(plots:GetChildren()) do task.spawn(onPlot, p) end
  end)

  local t, ringT = 0, 0
  function G.stepAnim(dt)
    t = t + dt
    ringT = ringT + dt
    local cp = cam.CFrame.Position
    local now = os.clock()
    for p, s in pairs(spinning) do
      if not p.Parent then
        spinning[p] = nil
      elseif not (busy[s.model] and now < busy[s.model]) and (s.cf0.Position - cp).Magnitude < 600 then
        p.CFrame = CFrame.new(s.cf0.Position) * CFrame.Angles(0, t * s.spd * math.pi * 2, 0) * (s.cf0 - s.cf0.Position)
      end
    end
    for p, b in pairs(blinking) do
      if not p.Parent then
        blinking[p] = nil
      else
        local on = math.sin((t + b.ph) * b.spd * math.pi * 2) > -0.2
        p.Transparency = on and b.tr0 or 0.85
      end
    end
    local ring = ringT > 2.2
    if ring then ringT = 0 end
    for pad in pairs(pads) do
      if not pad.Parent then
        pads[pad] = nil
      elseif pad.Color == GREEN and (pad.CFrame.Position - cp).Magnitude < 400 then
        pad.Transparency = 0.25 * (0.5 + 0.5 * math.sin(t * 4))
        if ring and G.fxPart then   -- 买得起：冒一圈往外扩的光
          local c = pad.CFrame.Position
          local r = G.fxPart(Enum.PartType.Cylinder, V(0.2, 7, 7), CFrame.new(c.X, c.Y + 0.4, c.Z) * CFrame.Angles(0, 0, math.pi / 2), GREEN, Enum.Material.Neon, 0.35)
          TweenService:Create(r, TweenInfo.new(1), { Size = V(0.2, 16, 16), Transparency = 1 }):Play()
          Debris:AddItem(r, 1.05)
        end
      else
        pad.Transparency = 0
      end
    end
  end
end

return Anim
