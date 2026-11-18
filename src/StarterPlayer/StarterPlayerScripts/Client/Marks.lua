-- Roblox全面大战场（客户端）——落点标记
--   ① 手雷弹道（用户：手榴弹增加一个弹道）：拿着手雷时，按服务器扔雷的算法（Weapons.lua KIND.throw：往准星那边 45° 抛出去，
--      速度按水平距离算；重力是 0.55 倍）一步一步模拟，画一串小亮点到第一次落地，落地那里一个杀伤半径的圈
--   ② 炸弹落点（用户：飞机空投炸弹在地面要有标记，方便查看投到哪）：开飞机选中炸弹时，按服务器炸弹的算法（Air.lua guideBomb：
--      投出去带着飞机的速度、往下 4 格 / 秒，重力 AD.GRAV、一点阻力）算出落在哪，地上画一个杀伤半径的红圈、中间十字、一道竖光柱
--      （高空也看得见）；制导炸弹锁上了就标在目标上。扔出去的炸弹落地前，地上也一直标着它要落在哪（小一点的圈）
--   标记零件都只在本地、不碰撞、不挡射线
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Marks = {}

function Marks.init(G)
  local AD = require(RS:WaitForChild("AirDefs"))
  local Map = G.Map or require(RS:WaitForChild("Map"))
  local W = G.Config.Weapons
  local me = Players.LocalPlayer
  local V, RGB = Vector3.new, Color3.fromRGB
  local GR = AD.GRAV or 27.5
  local function ground(x, z) return AD.ground and AD.ground(Map, x, z) or Map.ground(x, z) end

  local folder = Instance.new("Folder")
  folder.Name = "Marks"
  folder.Parent = workspace
  local function part(size, color, shape, tr)
    local p = Instance.new("Part")
    if shape then p.Shape = shape end
    p.Size, p.Color = size, color
    p.Material = Enum.Material.Neon
    p.Transparency = tr or 0
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Parent = nil
    return p
  end
  -- 地上的一个圈：扁圆柱（轴竖着）+ 中间一个亮点
  local function ring(color, tr)
    local disc = part(V(0.3, 10, 10), color, Enum.PartType.Cylinder, tr)
    disc.Name = "MarkRing"
    return disc
  end
  local function placeRing(disc, pos, r)
    disc.Size = V(0.3, r * 2, r * 2)
    disc.CFrame = CFrame.new(pos + V(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2)
    disc.Parent = folder
  end

  ---------------------------------------------------------------- ① 手雷弹道

  local NDOT = 26
  local dots = {}
  for i = 1, NDOT do
    local d = part(V(0.32, 0.32, 0.32), RGB(255, 246, 210), Enum.PartType.Ball, 0.15)
    d.Name = "NadeDot"
    dots[i] = d
  end
  local nadeRing = ring(RGB(255, 120, 60), 0.72)
  local nadeCore = part(V(0.32, 1.6, 1.6), RGB(255, 90, 50), Enum.PartType.Cylinder, 0.1)
  nadeCore.Name = "NadeCore"
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  local function hideNade()
    for _, d in ipairs(dots) do d.Parent = nil end
    nadeRing.Parent, nadeCore.Parent = nil, nil
  end
  -- 模拟一颗手雷：返回路径点和落点（第一次碰到东西）
  local function nadePath(w, head, aim)
    local m = head + V(0, 0.5, 0)
    local flat = V(aim.X - m.X, 0, aim.Z - m.Z)
    local d = math.min(flat.Magnitude, w.range)
    local dir = (flat.Magnitude > 0.1) and flat.Unit or V(0, 0, -1)
    local sp = math.clamp(math.sqrt(math.max(1, d) * workspace.Gravity * 0.55), 20, w.speed)
    local vel = dir * sp * 0.7071 + V(0, sp * 0.7071, 0)
    local g = V(0, -workspace.Gravity * 0.55, 0)
    local pts, pos, dt = { m }, m, 1 / 15   -- 一步 1/15 秒（每帧几十条射线就够，弹道是抛物线，步子大点也准）
    for _ = 1, 90 do
      vel += g * dt
      local step = vel * dt
      local res = workspace:Raycast(pos, step, rp)
      if res then
        table.insert(pts, res.Position)
        return pts, res.Position
      end
      pos += step
      table.insert(pts, pos)
      if pos.Y < ground(pos.X, pos.Z) then return pts, V(pos.X, ground(pos.X, pos.Z), pos.Z) end
    end
    return pts, pos
  end
  G.nadePath = nadePath   -- 测试用

  local function stepNade()
    local id = G.weaponNow and G.weaponNow()
    local w = id and W[id]
    local char = me.Character
    local head = char and char:FindFirstChild("Head")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not w or w.kind ~= "throw" or not head or not hum or hum.Health <= 0 or G.drive or G.fly or not G.aimPoint then
      hideNade()
      return
    end
    local ex = { char, folder }   -- 不挡弹道的：自己、标记、特效（没有的不放，表里不能有空洞）
    if G.fxFolder then table.insert(ex, G.fxFolder) end
    if G.viewFolder then table.insert(ex, G.viewFolder) end
    rp.FilterDescendantsInstances = ex
    local aim = G.aimPoint(w.range or 90)
    local pts, land = nadePath(w, head.Position, aim)
    -- 小亮点按路径长度均匀摆
    local total = 0
    for i = 2, #pts do total += (pts[i] - pts[i - 1]).Magnitude end
    local segI, acc = 2, 0
    for k = 1, NDOT do
      local want = total * k / (NDOT + 1)
      while segI < #pts and acc + (pts[segI] - pts[segI - 1]).Magnitude < want do
        acc += (pts[segI] - pts[segI - 1]).Magnitude
        segI += 1
      end
      local a, b = pts[segI - 1], pts[segI]
      local L = (b - a).Magnitude
      local p = (L > 1e-4) and a:Lerp(b, math.clamp((want - acc) / L, 0, 1)) or b
      dots[k].CFrame = CFrame.new(p)
      dots[k].Parent = folder
    end
    placeRing(nadeRing, land, w.splash or 14)
    nadeCore.CFrame = CFrame.new(land + V(0, 0.32, 0)) * CFrame.Angles(0, 0, math.pi / 2)
    nadeCore.Parent = folder
  end

  ---------------------------------------------------------------- ② 炸弹落点

  local bombRing = ring(RGB(255, 60, 40), 0.68)
  local crossA = part(V(0.4, 0.4, 14), RGB(255, 70, 50), nil, 0.1)
  local crossB = part(V(14, 0.4, 0.4), RGB(255, 70, 50), nil, 0.1)
  local beam = part(V(0.6, 160, 0.6), RGB(255, 90, 60), nil, 0.55)
  crossA.Name, crossB.Name, beam.Name = "BombCross", "BombCross", "BombBeam"
  local function hideBomb()
    bombRing.Parent, crossA.Parent, crossB.Parent, beam.Parent = nil, nil, nil, nil
  end
  -- 按服务器的炸弹物理往前推，落到地面（或海面）为止
  local function bombImpact(p, v)
    local dt = 0.05
    for _ = 1, 1200 do
      v += V(0, -GR, 0) * dt
      v = v * (1 - 0.02 * dt)
      local np = p + v * dt
      local g = math.max(ground(np.X, np.Z), 0)
      if np.Y <= g then
        local k = (p.Y - g) / math.max(p.Y - np.Y, 1e-3)
        local hit = p:Lerp(np, math.clamp(k, 0, 1))
        return V(hit.X, g, hit.Z)
      end
      p = np
    end
    return V(p.X, math.max(ground(p.X, p.Z), 0), p.Z)
  end
  G.bombImpact = bombImpact   -- 测试用

  local function stepBomb()
    local st = G.fly
    if not st or not st.pilot or st.crashed or st.ground or not st.wl then
      hideBomb()
      return
    end
    local wid = st.wl[st.wi]
    local w = wid and AD.W[wid]
    if not w or w.kind ~= "bomb" then
      -- 选的是炮：看看挂载里第一种是不是炸弹（F 打的是它）
      for _, wid2 in ipairs(st.wl) do
        local w2 = AD.W[wid2]
        if w2 and w2.kind ~= "gun" then w = w2 break end
      end
    end
    if not w or w.kind ~= "bomb" then
      hideBomb()
      return
    end
    local hit
    local locked = st.lock and st.lockT and st.lockT >= (w.lockTime or 1)
    if w.guided and locked then   -- 制导炸弹锁上了：标在目标上
      local em = st.lock.em
      local root = em and em.Parent and em:FindFirstChild("Root")
      local tp = root and root.CFrame.Position or st.lock.pos
      if tp then hit = V(tp.X, math.max(ground(tp.X, tp.Z), 0), tp.Z) end
    end
    if not hit then
      local cf = st.cf
      local p0 = (cf * CFrame.new(0, -(st.d.H or 4) * 0.35 - 1.5, 0)).Position
      hit = bombImpact(p0, (st.vel or V()) - cf.UpVector * 4)
    end
    local r = w.splash or 30
    placeRing(bombRing, hit, r)
    crossA.Size, crossB.Size = V(0.5, 0.5, r * 2.2), V(r * 2.2, 0.5, 0.5)
    crossA.CFrame, crossB.CFrame = CFrame.new(hit + V(0, 0.45, 0)), CFrame.new(hit + V(0, 0.45, 0))
    beam.CFrame = CFrame.new(hit + V(0, 80, 0))
    crossA.Parent, crossB.Parent, beam.Parent = folder, folder, folder
  end

  -- 扔出去的炸弹：每颗地上一个小圈，跟着算到落地
  local live = {}   -- [弹编号] = 圈
  local function stepDropped()
    local fs = G.flyingShots or {}
    for id, s in pairs(fs) do
      if s.gb and s.my and s.p and s.v then
        local r = live[id]
        if not r then
          r = ring(RGB(255, 150, 60), 0.6)
          live[id] = r
        end
        local aw = s.w and AD.W[s.w]
        placeRing(r, bombImpact(s.p, s.v), math.max(8, (aw and aw.splash or 30) * 0.45))
      end
    end
    for id, r in pairs(live) do
      if not fs[id] then
        r:Destroy()
        live[id] = nil
      end
    end
  end

  RunService.RenderStepped:Connect(function()
    G.try_(stepNade)
    G.try_(stepBomb)
    G.try_(stepDropped)
  end)
end

return Marks
