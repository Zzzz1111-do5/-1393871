-- 暗剑：登岛战（客户端）——实体的样子：服务器上只有一个隐形的 Root（位置）和属性（Kind 种类、Team 队伍、Hp 血量），
--   这里按种类拼一个本地模型，每帧平滑地跟着 Root 走（服务器 10 次 / 秒地挪，直接跟会一顿一顿的）；头顶血条
--   机器人步兵（摆腿走路）、登陆艇（放跳板）、炸药包、地雷；载具、舰艇、工事在后面的版本里接
local Players = game:GetService("Players")

local View = {}

function View.init(G)
  local Config = G.Config
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer

  local VF = Instance.new("Folder")
  VF.Name = "EntView"
  VF.Parent = workspace
  G.viewFolder = VF

  local function p(m, size, cf, color, mat, shape)
    local x = Instance.new("Part")
    if shape then x.Shape = shape end
    x.Size, x.CFrame, x.Color = size, cf, color
    x.Material = mat or Enum.Material.SmoothPlastic
    x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
    x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    x.Parent = m
    return x
  end

  -- 每种实体：build 拼零件（相对 Root 的偏移记在 parts 里），animate 每帧额外动（腿、跳板）
  local UNIFORM = { atk = { RGB(150, 128, 92), RGB(110, 96, 70) }, def = { RGB(84, 104, 70), RGB(64, 78, 54) } }
  local KINDS = {}
  KINDS.bot = function(m, team)
    local U = UNIFORM[team] or UNIFORM.atk
    local L = {}
    L.torso = { p(m, V(2, 2, 1), CF(), U[1]), CF(0, 0.6, 0) }
    L.head = { p(m, V(1.2, 1.2, 1.2), CF(), RGB(230, 190, 150)), CF(0, 2.2, 0) }
    L.helmet = { p(m, V(1.4, 0.6, 1.4), CF(), U[2], Enum.Material.SmoothPlastic), CF(0, 2.75, 0) }
    L.lleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(-0.5, -1.4, 0), "leg", 1 }
    L.rleg = { p(m, V(0.9, 2, 0.9), CF(), U[2]), CF(0.5, -1.4, 0), "leg", -1 }
    L.larm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(-1.4, 0.6, -0.4) * CFrame.Angles(-1.2, 0, 0) }
    L.rarm = { p(m, V(0.8, 1.9, 0.8), CF(), U[1]), CF(1.4, 0.6, -0.4) * CFrame.Angles(-1.2, 0, 0) }
    L.gun = { p(m, V(0.4, 0.5, 3), CF(), RGB(45, 47, 50)), CF(0.4, 0.9, -1.6) }
    L.band = { p(m, V(0.85, 0.35, 0.85), CF(), Config.Teams[team or "atk"].color, Enum.Material.Neon), CF(1.4, 1.2, -0.4) }
    return L
  end
  KINDS.lcm = function(m, team)
    local L = {}
    local hull = RGB(96, 104, 98)
    L.bottom = { p(m, V(16, 2, 34), CF(), hull, Enum.Material.Metal), CF(0, -2, 0) }
    L.lwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(-7.5, 1, 0) }
    L.rwall = { p(m, V(1, 6, 34), CF(), hull, Enum.Material.Metal), CF(7.5, 1, 0) }
    L.back = { p(m, V(16, 7, 1), CF(), hull, Enum.Material.Metal), CF(0, 1.5, 16.5) }
    L.cab = { p(m, V(6, 4, 4), CF(), RGB(120, 128, 120), Enum.Material.Metal), CF(0, 5, 14) }
    L.ramp = { p(m, V(15, 6, 0.8), CF(), hull, Enum.Material.Metal), CF(0, 1, -17), "ramp" }
    return L
  end
  KINDS.c4 = function(m) return { b = { p(m, V(1.1, 0.5, 0.7), CF(), RGB(176, 156, 112)), CF() }, l = { p(m, V(0.2, 0.2, 0.2), CF(), RGB(255, 40, 40), Enum.Material.Neon), CF(0, 0.3, 0) } } end
  KINDS.mine = function(m) return { b = { p(m, V(0.4, 1.4, 1.4), CF(), RGB(86, 96, 64), Enum.Material.Metal, Enum.PartType.Cylinder), CFrame.Angles(0, 0, math.pi / 2) } } end

  local views = {}   -- [entModel] = { model, parts, cf, kind, t }
  local function bar(m, root)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(46, 6)
    bb.StudsOffsetWorldSpace = V(0, 5, 0)
    bb.MaxDistance = 260
    bb.Adornee = root
    bb.Parent = m
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = RGB(0, 0, 0)
    bg.BackgroundTransparency = 0.4
    bg.BorderSizePixel = 0
    bg.Parent = bb
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BorderSizePixel = 0
    f.Parent = bg
    return bb, f
  end

  local function add(em)
    local kind = em:GetAttribute("Kind")
    local mk = KINDS[kind]
    local root = em:FindFirstChild("Root")
    if not mk or not root then return end
    local m = Instance.new("Model")
    m.Name = kind
    local team = em:GetAttribute("Team")
    local parts = mk(m, team)
    m.Parent = VF
    local bb, fill = bar(m, parts[next(parts)][1])
    fill.BackgroundColor3 = Config.Teams[team or "atk"].color
    views[em] = { model = m, parts = parts, cf = root.CFrame, root = root, kind = kind, t = 0, bb = bb, fill = fill, team = team }
  end
  local function remove(em)
    local v = views[em]
    if v then
      v.model:Destroy()
      views[em] = nil
    end
  end

  local function watch(folder)
    for _, em in ipairs(folder:GetChildren()) do task.defer(add, em) end
    folder.ChildAdded:Connect(function(em) task.defer(add, em) end)
    folder.ChildRemoved:Connect(remove)
  end
  task.spawn(function()
    local f = workspace:WaitForChild("Ents", 60)
    if f then watch(f) end
  end)

  function G.stepView(dt)
    local myTeam = me:GetAttribute("Side")
    for em, v in pairs(views) do
      if not em.Parent then
        remove(em)
      else
        local target = v.root.CFrame
        local moved = (target.Position - v.cf.Position).Magnitude
        v.cf = v.cf:Lerp(target, math.min(1, dt * 10))
        v.t += dt * math.clamp(moved * 2, 0, 12)
        local hp, mx = em:GetAttribute("Hp") or 1, em:GetAttribute("MaxHp") or 1
        v.fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, mx), 0, 1), 1)
        v.bb.Enabled = hp < mx and (myTeam == v.team or hp < mx)
        for _, L in pairs(v.parts) do
          local off = L[2]
          if L[3] == "leg" then off = off * CFrame.Angles(math.sin(v.t * 1.2) * 0.7 * L[4], 0, 0)
          elseif L[3] == "ramp" and em:GetAttribute("Ramp") then off = off * CFrame.Angles(-1.3, 0, 0) end
          L[1].CFrame = v.cf * off
        end
      end
    end
  end
end

return View
