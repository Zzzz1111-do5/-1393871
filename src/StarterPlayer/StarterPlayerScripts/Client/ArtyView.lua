-- 全面大战场（客户端）——炮兵视角（用户 11-25：「部分远火高射形载具 更新一下要有坦克世界那种 可以把视角放到射程范围内的任何位置
--   但是对于敌载具的视野是要受限于我方信息的 然后 可以在目标点像截图这样在地面有一个3d的散步圈 然后 如果我目标标定移动很快的话
--   这个圈会变大 然后慢慢变小这样」）
--   · 开着自行火炮 / 火箭炮（当前武器是曲射的 arty）按 Shift：镜头升到天上往下看，鼠标把瞄准点挪到射程圈里任何地方，滚轮升降镜头
--   · 瞄准点那里地面上一圈贴地的散布圈（一段段跟着地形起伏）：瞄准点挪得快、车在开、炮在转，圈胀大（变黄）；停下来慢慢收小（变绿）——
--     开火时把圈的大小（0～1）发给服务器，服务器按它定落点散多开（Armor.lua）
--   · 地上画射程圈（最远白、最近红）、从炮口到瞄准点的弹道弧线；屏幕上写飞行时间、距离、装填
--   · 敌人的车只画全队看得见的（服务器 WtMatch 每半秒发的 teamSeen：队友视线里的、被侦察 / 标记的）——
--     镜头挪到敌后也看不到没人发现的车；收不到 teamSeen（PvE）时只画离自己车 600 格以内的
--   Drive.lua 调：G.artyToggle(st)、G.artyMouse(md)、G.artyWheel(z)、G.artyStep(st, dt) → 镜头、瞄准点；G.artyBloom() 开火时的散布；G.artyOff()
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ArtyView = {}

function ArtyView.init(G)
  local VD = require(RS:WaitForChild("VehDefs"))
  local Map = require(RS:WaitForChild("Map"))
  local TH = require(RS:WaitForChild("Theme"))
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local M = 2.8   -- 1 米多少格
  local function L(zh, en) return (G.lang == "en") and en or zh end

  local A = { on = false, aim = nil, h = 620, yaw = 0, bloom = 1, hidden = {}, seenAt = 0 }
  local folder = nil
  local ring, rangeMax, rangeMin, arc = {}, {}, {}, {}
  local RING_N, RANGE_N, ARC_N = 40, 96, 26

  local function groundY(x, z)
    local ok, y = pcall(function() return (Map.ground or Map.height)(x, z) end)
    return (ok and type(y) == "number") and math.max(y, 0) or 0
  end
  local function seg(list, i, col, tr)
    local p = list[i]
    if not p then
      p = Instance.new("Part")
      p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
      p.Material = Enum.Material.Neon
      p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
      p.Parent = folder
      list[i] = p
    end
    p.Color, p.Transparency = col, tr
    return p
  end
  local function hideList(list) for _, p in ipairs(list) do p.Transparency = 1 end end
  -- 一圈贴地的线：圆心 c、半径 r、n 段，粗 w；每段两头按地面高度摆（地形起伏的地方跟着弯）
  local function drawRing(list, n, c, r, w, col, tr, lift)
    local pts = {}
    for i = 0, n do
      local a = i / n * math.pi * 2
      local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
      pts[i] = V(x, groundY(x, z) + (lift or 0.8), z)
    end
    for i = 1, n do
      local a, b = pts[i - 1], pts[i]
      local p = seg(list, i, col, tr)
      local len = (b - a).Magnitude
      p.Size = V(w, w * 0.35, len + w * 0.6)
      p.CFrame = CFrame.lookAt((a + b) / 2, b)
    end
  end

  -- 屏幕上的字：飞行时间（左）、距离（右）、装填（下）、操作提示
  local gui = Instance.new("ScreenGui")
  gui.Name = "ArtyView"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local function lab(name, pos, anchor, size, font, col)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.Size = UDim2.fromOffset(220, 28)
    t.Position, t.AnchorPoint = pos, anchor
    t.Font, t.TextSize, t.TextColor3 = font, size, col
    t.TextStrokeTransparency = 0.45
    t.Parent = gui
    return t
  end
  local tofT = lab("Tof", UDim2.new(0.5, -70, 0.5, 0), Vector2.new(1, 0.5), TH.S.sub, TH.F.mono, TH.C.HUD)
  tofT.TextXAlignment = Enum.TextXAlignment.Right
  local distT = lab("Dist", UDim2.new(0.5, 70, 0.5, 0), Vector2.new(0, 0.5), TH.S.sub, TH.F.mono, TH.C.HUD)
  distT.TextXAlignment = Enum.TextXAlignment.Left
  local relT = lab("Reload", UDim2.new(0.5, 0, 0.5, 46), Vector2.new(0.5, 0), TH.S.small, TH.F.bold, TH.C.TEXT)
  local hintT = lab("Hint", UDim2.new(0.5, 0, 1, -118), Vector2.new(0.5, 1), TH.S.small, TH.F.bold, TH.C.TEXT)
  hintT.Size = UDim2.fromOffset(760, 24)
  hintT.Text = L("炮兵视角 · 鼠标挪瞄准点 · 滚轮升降 · 左键开火 · Shift 退出 · 敌车只显示全队发现的",
    "Artillery view · mouse moves the aim · wheel zooms · LMB fires · Shift exits · only spotted enemies are shown")
  local cross = Instance.new("Frame")   -- 正中一个小点（瞄准点在屏幕中间）
  cross.Name = "Dot"
  cross.Size = UDim2.fromOffset(4, 4)
  cross.AnchorPoint = Vector2.new(0.5, 0.5)
  cross.Position = UDim2.fromScale(0.5, 0.5)
  cross.BackgroundColor3 = TH.C.HUD
  cross.BorderSizePixel = 0
  cross.Parent = gui

  local function wpnOf(st)
    local d = st and st.d
    local w = d and VD.W[d.weapons[st.wi] or ""]
    return (w and w.kind == "arty") and w or nil
  end
  G.artyWeapon = wpnOf

  -- 敌车只画全队看得见的：Hud.lua 收的 teamSeen（G.teamSeenId）；收不到（PvE）就只画离自己车 600 格以内的
  local function showAll()
    for em, parts in pairs(A.hidden) do
      for _, p in ipairs(parts) do if p.Parent then p.LocalTransparencyModifier = 0 end end
      A.hidden[em] = nil
    end
  end
  local function fog(st)
    local mine = me:GetAttribute("Side")
    local myPos = st.root and st.root.Position or cam.CFrame.Position
    local hasTeam = G.teamSeenFresh and G.teamSeenFresh()
    for em, v in pairs(G.views or {}) do
      local team = em.Parent and em:GetAttribute("Team")
      local enemy = team ~= nil and mine ~= nil and team ~= mine
      local vis = true
      if enemy then
        local id = em:GetAttribute("EntId")
        if hasTeam then vis = id ~= nil and G.teamSeenId(id)
        else
          local r = em:FindFirstChild("Root")
          vis = r ~= nil and (r.Position - myPos).Magnitude < 600
        end
      end
      local model = v.model
      if not vis and model and not A.hidden[em] then
        local parts = {}
        for _, p in ipairs(model:GetDescendants()) do
          if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 table.insert(parts, p) end
        end
        A.hidden[em] = parts
      elseif vis and A.hidden[em] then
        for _, p in ipairs(A.hidden[em]) do if p.Parent then p.LocalTransparencyModifier = 0 end end
        A.hidden[em] = nil
      end
    end
  end

  function G.artyOn() return A.on end
  function G.artyBloom() return A.on and math.clamp(A.bloom, 0, 1) or 1 end
  function G.artyOff()
    if not A.on then return end
    A.on = false
    gui.Enabled = false
    if folder then folder:Destroy() folder = nil end
    ring, rangeMax, rangeMin, arc = {}, {}, {}, {}
    showAll()
  end
  -- 开 / 关：开的时候瞄准点从原来准星的地方开始（没有就车头前方射程中间）
  function G.artyToggle(st)
    if A.on then G.artyOff() return false end
    local w = wpnOf(st)
    if not w then return false end
    A.on = true
    A.bloom = 1
    folder = Instance.new("Folder")
    folder.Name = "ArtyMarks"
    folder.Parent = workspace
    local p0 = st.root.Position
    local ap = st.aimPt
    local flat = ap and V(ap.X - p0.X, 0, ap.Z - p0.Z) or nil
    if not flat or flat.Magnitude < w.minR or flat.Magnitude > w.maxR then
      local look = st.root.CFrame.LookVector
      look = V(look.X, 0, look.Z).Unit
      flat = look * ((w.minR + w.maxR) / 2)
    end
    A.aim = V(p0.X + flat.X, 0, p0.Z + flat.Z)
    A.yaw = math.atan2(-flat.X, -flat.Z)   -- 屏幕上方朝开炮的方向
    A.rangeAt = nil
    gui.Enabled = true
    return true
  end
  -- 鼠标挪瞄准点（按镜头高度换算：越高挪得越快），挪得越快散布圈胀得越大
  function G.artyMouse(md, dt)
    if not A.on or not A.aim then return end
    local k = A.h * 0.0017
    local fwd = V(-math.sin(A.yaw), 0, -math.cos(A.yaw))
    local right = V(-fwd.Z, 0, fwd.X)
    local mv = right * (md.X * k) - fwd * (md.Y * k)
    A.aim += mv
    A.move = (A.move or 0) + mv.Magnitude
  end
  function G.artyWheel(z)
    if not A.on then return end
    A.h = math.clamp(A.h * ((z > 0) and 0.85 or 1.18), 220, 1800)
  end

  -- 每帧（Drive.lua）：限制在射程圈里、散布圈胀缩、画圈和弧线、写字；返回镜头和瞄准点
  function G.artyStep(st, dt)
    local w = wpnOf(st)
    if not A.on or not w then G.artyOff() return nil end
    local p0 = st.root.Position
    local flat = V(A.aim.X - p0.X, 0, A.aim.Z - p0.Z)
    local dist = flat.Magnitude
    if dist > w.maxR then flat = flat.Unit * w.maxR
    elseif dist < w.minR then flat = (dist > 1 and flat.Unit or V(-math.sin(A.yaw), 0, -math.cos(A.yaw))) * w.minR end
    dist = flat.Magnitude
    local ax, az = p0.X + flat.X, p0.Z + flat.Z
    local ay = groundY(ax, az)
    A.aim = V(ax, 0, az)
    local aimPt = V(ax, ay, az)
    -- 散布圈（同服务器 Armor.lua：基础 scatter + 距离的 1%；圈 = 基础 × (0.5 + 1.5 × 胀开的程度)）
    local base = (w.scatter or 10) + dist * 0.01
    local speedPx = (A.move or 0) / math.max(dt, 1e-3)   -- 瞄准点每秒挪了多少格
    A.move = 0
    local drive = math.abs(st.speed or 0) / math.max(st.d.speed or 1, 1)
    A.bloom += (speedPx / (base * 6) + drive * 0.9) * dt
    A.bloom = math.clamp(A.bloom * math.exp(-dt / 1.3), 0, 1)   -- 停下来 3～4 秒收到最小
    local r = base * (0.5 + 1.5 * A.bloom)
    local col = TH.C.HUD:Lerp(RGB(255, 214, 90), math.clamp(A.bloom * 1.4, 0, 1))
    local wth = math.clamp(A.h * 0.0045, 0.8, 7)
    drawRing(ring, RING_N, aimPt, r, wth, col, 0.05, 0.9)
    -- 射程圈：最远白、最近红（车挪了二十格以上再重画）
    if not A.rangeAt or (A.rangeAt - p0).Magnitude > 20 or math.abs((A.rangeW or 0) - wth) > 0.5 then
      A.rangeAt, A.rangeW = p0, wth
      drawRing(rangeMax, RANGE_N, p0, w.maxR, wth * 0.8, RGB(235, 235, 230), 0.35, 1.2)
      drawRing(rangeMin, 48, p0, w.minR, wth * 0.7, TH.C.BAD, 0.4, 1.2)
    end
    -- 弹道弧线：炮口 → 瞄准点，抛物线（榴弹炮高、火箭弹低一点）
    local mz = st.muzzle and st.muzzle() or (p0 + V(0, st.d.H, 0))
    local apex = dist * ((w.mag or 1) > 1 and 0.22 or 0.34)
    for i = 1, ARC_N do
      local u = i / (ARC_N + 1)
      local p = mz:Lerp(aimPt, u) + V(0, 4 * apex * u * (1 - u), 0)
      local b = seg(arc, i, RGB(250, 250, 245), 0.25 + 0.5 * u)
      b.Shape = Enum.PartType.Ball
      local s = wth * 0.9
      b.Size = V(s, s, s)
      b.CFrame = CF(p)
    end
    -- 字：飞行时间（同服务器 Armor.lua：flight + 距离 / 700）、距离、装填
    local tof = (w.flight or 6) + dist / 700
    tofT.Text = string.format(L("%.1f 秒", "%.1f s"), tof)
    distT.Text = string.format(L("%d 米", "%d m"), math.floor(dist / M + 0.5))
    tofT.TextColor3, distT.TextColor3 = col, col
    local left = st.reloadLeft and st.reloadLeft() or 0
    relT.Text = (left > 0.05) and string.format(L("装填 %.1f 秒", "Reloading %.1f s"), left) or L("待发", "READY")
    relT.TextColor3 = (left > 0.05) and TH.C.WARN or TH.C.GOOD
    -- 敌车只画看得见的（0.2 秒一次）
    A.fogT = (A.fogT or 0) - dt
    if A.fogT <= 0 then
      A.fogT = 0.2
      fog(st)
    end
    -- 镜头：瞄准点正上方往后一点，朝开炮方向往下看
    local fwd = V(-math.sin(A.yaw), 0, -math.cos(A.yaw))
    local camPos = aimPt - fwd * (A.h * 0.32) + V(0, A.h, 0)
    cam.FieldOfView = 50
    return CFrame.lookAt(camPos, aimPt), aimPt
  end
end

return ArtyView
