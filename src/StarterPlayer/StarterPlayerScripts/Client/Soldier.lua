-- Roblox全面大战场（客户端）——机器人士兵的样子：Roblox 正常小人（用户：士兵建模太粗糙了，就用 Roblox 正常小人的建模）
--   服务器开服时用 Players:CreateHumanoidModelFromDescription 生成一个默认的 R15 小人当模板（ReplicatedStorage.BotRig，Bots.lua），
--   这里每个机器人克隆一个：上身、胳膊按队伍迷彩上色，裤子深一点，手套黑；戴头盔和夜视仪、右臂臂章、右手端一支步枪；
--   动作用 Roblox 自带的动画（待机、走、跑，右手一直端着），跟玩家的小人一样；死了往后倒，几秒后消失
--   没有模板（Studio 里连不上资源、模拟测试）：用零件拼经典的 R6 小人（圆头、笑脸、1 × 2 × 1 的胳膊腿），腿绕胯摆
--   零件都不碰撞、不挡射线（子弹打的是服务器上的命中盒）
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Soldier = {}

function Soldier.init(G)
  local Config = G.Config
  local V, CF, RGB = Vector3.new, CFrame.new, Color3.fromRGB
  local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }   -- 同 Round.lua 给玩家穿的
  local HELMET = { atk = RGB(96, 104, 72), def = RGB(146, 128, 96) }
  local SKIN, GLOVE, GUN = RGB(234, 194, 150), RGB(38, 38, 36), RGB(42, 44, 46)
  local HALF = 2.8   -- 服务器命中盒的中心在脚底上 2.8 格
  local ANIM = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714", hold = "rbxassetid://507768375" }
  local animObj = {}
  pcall(function()   -- 模拟测试里没有动画类：没有就不放动作（R15 小人只在真 Roblox 里有模板）
    for k, id in pairs(ANIM) do
      local a = Instance.new("Animation")
      a.AnimationId = id
      animObj[k] = a
    end
  end)

  local function quiet(p, anchored)
    p.Anchored = anchored == true
    p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
    p.Massless = true
  end
  local function part(parent, size, color, mat, shape)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Size, p.Color = size, color
    p.Material = mat or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    quiet(p, false)
    p.Parent = parent
    return p
  end
  local function weld(p0, p1, c0)
    local w = Instance.new("Weld")
    w.Part0, w.Part1, w.C0 = p0, p1, c0
    w.Parent = p1
    return w
  end

  -- 步枪（M4 的样子）：原点在握把上，枪口朝 −Z、顶上朝 +Y；焊在 attach 上
  local function rifle(parent, attach, c0)
    local function g(size, off, color, shape)
      local p = part(parent, size, color or GUN, Enum.Material.Metal, shape)
      weld(attach, p, c0 * off)
      return p
    end
    g(V(0.2, 0.3, 1.1), CF(0, 0.16, -0.35))                      -- 机匣
    g(V(0.19, 0.22, 0.8), CF(0, 0.18, -1.25))                    -- 护木
    g(V(0.6, 0.08, 0.08), CF(0, 0.18, -1.95) * CFrame.Angles(0, math.pi / 2, 0), GUN, Enum.PartType.Cylinder)   -- 枪管
    g(V(0.18, 0.3, 0.7), CF(0, 0.06, 0.55))                      -- 枪托
    g(V(0.14, 0.45, 0.22), CF(0, -0.18, -0.55) * CFrame.Angles(math.rad(-10), 0, 0))   -- 弹匣
    g(V(0.12, 0.34, 0.15), CF(0, -0.1, 0) * CFrame.Angles(math.rad(18), 0, 0))         -- 握把
    g(V(0.14, 0.15, 0.38), CF(0, 0.39, -0.32), RGB(30, 31, 32))  -- 瞄准镜
  end
  -- 头盔、夜视仪（头的大小按 1.2 格的 R15 头算，k 缩放）
  local function helmet(parent, head, team, k, y0)
    local col = HELMET[team] or HELMET.def
    local h = part(parent, V(1.42, 0.86, 1.5) * k, col, Enum.Material.Fabric)
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Parent = h
    weld(head, h, CF(0, y0 + 0.42 * k, 0.04 * k))
    weld(head, part(parent, V(1.46, 0.14, 1.54) * k, col:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric), CF(0, y0 + 0.08 * k, 0.04 * k))
    weld(head, part(parent, V(0.34, 0.26, 0.16) * k, RGB(34, 36, 38), Enum.Material.Metal), CF(0, y0 + 0.42 * k, -0.74 * k))
    for _, sx in ipairs({ -1, 1 }) do   -- 夜视仪镜筒（翻上去的）
      weld(head, part(parent, V(0.4, 0.22, 0.22) * k, RGB(22, 24, 26), Enum.Material.Metal, Enum.PartType.Cylinder),
        CF(sx * 0.17 * k, y0 + 0.62 * k, -0.78 * k) * CFrame.Angles(0, math.pi / 2, math.rad(70)))
    end
  end

  ---------------------------------------------------------------- R15 小人（模板克隆）

  local function buildRig(v, tpl, team)
    local m = tpl:Clone()
    m.Name = "bot"
    local U = UNIFORM[team] or UNIFORM.atk
    local hrp = m:FindFirstChild("HumanoidRootPart")
    local head = m:FindFirstChild("Head")
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not hrp or not head or not hum then
      m:Destroy()
      return false
    end
    local low = math.huge
    for _, p in ipairs(m:GetDescendants()) do
      if p:IsA("BasePart") then
        quiet(p, p == hrp)
        local n = p.Name
        if n == "Head" then p.Color = SKIN
        elseif string.find(n, "Hand") then p.Color = GLOVE
        elseif string.find(n, "Leg") or string.find(n, "Foot") or n == "LowerTorso" then p.Color = U[2]
        elseif string.find(n, "Arm") or n == "UpperTorso" then p.Color = U[1] end
        if p ~= hrp then low = math.min(low, p.Position.Y - p.Size.Y / 2) end
      elseif p:IsA("BodyColors") then
        p:Destroy()
      end
    end
    hrp.Transparency = 1
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    pcall(function() hum.EvaluateStateMachine = false end)   -- 不跑人物的状态机（站、跳、掉）：位置是这里摆的
    local hip = hrp.Position.Y - low   -- HumanoidRootPart 中心离脚底多高
    local k = head.Size.Y / 1.2
    helmet(m, head, team, k, 0)
    local rh = m:FindFirstChild("RightHand")
    if rh then rifle(m, rh, CF(0, -0.12, 0) * CFrame.Angles(-math.pi / 2, 0, 0)) end   -- 端枪动作里右臂平伸，手的 −Y 朝前：枪口顺着胳膊
    local rua = m:FindFirstChild("RightUpperArm")
    if rua then weld(rua, part(m, V(rua.Size.X + 0.06, 0.3, rua.Size.Z + 0.06), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(0, 0.15, 0)) end
    local an = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
    an.Parent = hum
    v.tracks = {}
    pcall(function()
      for key, a in pairs(animObj) do
        local tr = an:LoadAnimation(a)
        tr.Looped = true
        tr.Priority = (key == "hold") and Enum.AnimationPriority.Action or ((key == "idle") and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement)
        v.tracks[key] = tr
      end
      v.tracks.hold:Play(0)
      v.tracks.idle:Play(0)
    end)
    v.anim = "idle"
    v.model, v.anchor, v.hrp, v.hip, v.rig = m, head, hrp, hip, true
    return true
  end

  ---------------------------------------------------------------- 经典 R6 小人（零件拼）

  local function buildClassic(v, team)
    local m = Instance.new("Model")
    m.Name = "bot"
    local U = UNIFORM[team] or UNIFORM.atk
    local root = part(m, V(1, 1, 1), U[1])   -- 隐形的根：别的零件焊在它上面
    root.Transparency = 1
    root.Anchored = true
    local torso = part(m, V(2, 2, 1), U[1])
    weld(root, torso, CF(0, 0.2, 0))
    local head = part(m, V(2, 1, 1), SKIN)
    local hm = Instance.new("SpecialMesh")
    hm.MeshType = Enum.MeshType.Head
    hm.Scale = V(1.25, 1.25, 1.25)
    hm.Parent = head
    local face = Instance.new("Decal")
    face.Name = "face"
    face.Texture = "rbxasset://textures/face.png"
    face.Face = Enum.NormalId.Front
    face.Parent = head
    weld(root, head, CF(0, 1.7, 0))
    helmet(m, head, team, 1, 0)
    -- 胳膊、腿：绕肩、胯转（关节在零件顶上；根在脚底上 2.8 格：胯在根下 0.8、肩在根上 1.2）
    local function limb(size, color, joint)
      local p = part(m, size, color)
      local off = CF(0, -size.Y / 2, 0)
      local w = weld(root, p, joint * off)
      return { p = p, w = w, j = joint, off = off }
    end
    v.lleg = limb(V(1, 2, 1), U[2], CF(-0.5, -0.8, 0))
    v.rleg = limb(V(1, 2, 1), U[2], CF(0.5, -0.8, 0))
    v.larm = limb(V(1, 2, 1), U[1], CF(-1.5, 1.2, 0))
    local rarm = limb(V(1, 2, 1), U[1], CF(1.5, 1.2, 0))
    rarm.w.C0 = rarm.j * CFrame.Angles(math.pi / 2, 0, 0) * rarm.off   -- 右臂平伸端枪
    weld(rarm.p, part(m, V(1.06, 0.3, 1.06), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(0, 0.6, 0))
    rifle(m, rarm.p, CF(0, -0.95, 0) * CFrame.Angles(-math.pi / 2, 0, 0))
    v.model, v.anchor, v.hrp, v.hip, v.rig = m, head, root, HALF, false
    return true
  end

  ---------------------------------------------------------------- 接到 View.lua（G.viewKind.bot）

  local dying = {}
  G.viewKind = G.viewKind or {}
  G.viewKind.bot = {
    build = function(v, em, team)
      local tpl = RS:FindFirstChild("BotRig")
      local ok = tpl and buildRig(v, tpl, team)
      if not ok then buildClassic(v, team) end
      v.spd, v.lastP, v.phase = 0, v.root.CFrame.Position, 0
      v.cf = v.root.CFrame
      return true
    end,
    step = function(v, dt, camPos)
      local target = v.root.CFrame
      local p = target.Position
      -- 走多快：服务器一秒挪十几次，按位置的变化估、再平滑
      local moved = (V(p.X, 0, p.Z) - V(v.lastP.X, 0, v.lastP.Z)).Magnitude
      v.lastP = p
      v.spd = v.spd + (moved / math.max(dt, 1 / 240) - v.spd) * math.min(1, dt * 5)
      v.cf = v.cf:Lerp(target, math.min(1, dt * 10))
      v.hrp.CFrame = v.cf * CF(0, v.hip - HALF, 0)
      local far = (p - camPos).Magnitude > 700
      if v.rig then
        local want = (v.spd > 19) and "run" or ((v.spd > 1.5) and "walk" or "idle")
        local T = v.tracks
        if T and T[want] then
          if want ~= v.anim then
            if T[v.anim] then T[v.anim]:Stop(0.25) end
            T[want]:Play(0.25)
            v.anim = want
          end
          if want ~= "idle" then T[want]:AdjustSpeed(far and 0 or math.clamp(v.spd / ((want == "run") and 24 or 14), 0.5, 1.6)) end
        end
      elseif not far then
        v.phase += dt * math.clamp(v.spd, 0, 24) * 0.45
        local a = math.sin(v.phase) * 0.75 * math.clamp(v.spd / 10, 0, 1)
        v.lleg.w.C0 = v.lleg.j * CFrame.Angles(a, 0, 0) * v.lleg.off
        v.rleg.w.C0 = v.rleg.j * CFrame.Angles(-a, 0, 0) * v.rleg.off
        v.larm.w.C0 = v.larm.j * CFrame.Angles(-a * 0.6, 0, 0) * v.larm.off
      end
    end,
    -- 死了：往后倒（绕脚底），6 秒后消失；返回 true = 模型自己收（View.lua 不马上删）
    remove = function(v)
      if (v.em:GetAttribute("Hp") or 1) > 0 then return false end
      if v.tracks then for _, tr in pairs(v.tracks) do pcall(function() tr:Stop(0.1) end) end end
      if v.bb then v.bb:Destroy() end
      table.insert(dying, { v = v, t0 = os.clock(), cf = v.cf })
      return true
    end,
  }
  RunService.RenderStepped:Connect(function()
    local t = os.clock()
    for i = #dying, 1, -1 do
      local d = dying[i]
      local a = t - d.t0
      if a > 6 or not d.v.model.Parent then
        d.v.model:Destroy()
        table.remove(dying, i)
      else
        local k = math.clamp(a / 0.45, 0, 1)
        local cf = d.cf * CF(0, -HALF, 0) * CFrame.Angles(k * k * 1.45, 0, 0) * CF(0, HALF - 0.4 * k, 0)
        d.v.hrp.CFrame = cf * CF(0, d.v.hip - HALF, 0)
      end
    end
  end)
end

return Soldier
