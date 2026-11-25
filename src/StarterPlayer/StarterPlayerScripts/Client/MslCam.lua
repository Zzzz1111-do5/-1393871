-- Roblox全面大战场（客户端）——导弹视角
--   用户 11-25「我发射导弹就不要加那个导弹视角小窗了 而是按一个键可以第三人称看跟踪我的导弹就像战雷那样」：
--   发射以后不再自动弹小窗，屏幕下方提示「L 跟踪导弹」；按 L 镜头切到导弹后上方跟着飞（第三人称，追尾），
--   命中 / 没打中以后在落点停一秒半再回到原来的镜头，飞的时候再按一次 L 马上回来。下面原来的小窗代码留着（不再打开）
-- 原注释（用户：继续做导弹视角小窗）：
--   自己开飞机打出去的导弹 / 制导炸弹：右上角开一个小窗，从弹上往目标看——导引头的画面：暗灰的底、目标白热、十字线、
--   目标多远、还剩几秒；导引头视场跟着距离缩（目标在画面里大小差不多，越近越大）
--   Roblox 的小窗（ViewportFrame）画不了地形和别的东西，只把目标的模型复制进去（一次，之后只挪小窗里的镜头）：
--   空中目标背后是天，地面 / 海上目标脚下铺一块暗灰的地；没有目标（没锁定就打的）就顺着弹飞的方向看那块地
--   弹没了：离目标 30 格以内写「命中」，不然「未命中」，停一秒多再关；同时只看最后发的那一枚
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local MslCam = {}

function MslCam.init(G)
  local AD = require(RS:WaitForChild("AirDefs"))
  local me = Players.LocalPlayer
  local pg = me:WaitForChild("PlayerGui")
  local V = Vector3.new
  local RGB = Color3.fromRGB
  local M_PER = AD.M or 2.8
  local function T(k, ...) return G.T(k, ...) end

  local gui = Instance.new("ScreenGui")
  gui.Name = "MslCam"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 8
  gui.Enabled = false
  gui.Parent = pg
  local box = Instance.new("Frame")
  box.Name = "Box"
  box.Size = UDim2.fromOffset(300, 196)
  box.AnchorPoint = Vector2.new(1, 0)
  box.Position = UDim2.new(1, -20, 0, 92)
  box.BackgroundColor3 = RGB(0, 0, 0)
  box.BackgroundTransparency = 0.35
  box.BorderSizePixel = 0
  box.Parent = gui
  local stroke = Instance.new("UIStroke")
  stroke.Color, stroke.Transparency, stroke.Thickness = RGB(150, 255, 170), 0.35, 1
  stroke.Parent = box
  local vpf = Instance.new("ViewportFrame")
  vpf.Name = "View"
  vpf.Size = UDim2.new(1, -8, 1, -30)
  vpf.Position = UDim2.fromOffset(4, 4)
  vpf.BackgroundColor3 = RGB(26, 28, 30)
  vpf.BorderSizePixel = 0
  vpf.Ambient = RGB(170, 170, 170)
  vpf.LightColor = RGB(255, 255, 255)
  vpf.LightDirection = V(-0.3, -1, -0.2)
  vpf.Parent = box
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 12
  vcam.Parent = vpf
  vpf.CurrentCamera = vcam
  local GREEN = RGB(150, 255, 170)
  local function line(size, pos)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos, Vector2.new(0.5, 0.5)
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = GREEN, 0.25, 0
    f.Parent = vpf
    return f
  end
  -- 十字线（中间留空）
  line(UDim2.fromOffset(26, 1), UDim2.new(0.5, -24, 0.5, 0))
  line(UDim2.fromOffset(26, 1), UDim2.new(0.5, 24, 0.5, 0))
  line(UDim2.fromOffset(1, 18), UDim2.new(0.5, 0, 0.5, -18))
  line(UDim2.fromOffset(1, 18), UDim2.new(0.5, 0, 0.5, 18))
  local function label(name, pos, anchor, align, size, color)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size = UDim2.fromOffset(150, 18)
    l.Position, l.AnchorPoint = pos, anchor
    l.Font = Enum.Font.RobotoMono
    l.TextSize = size or 13
    l.TextColor3 = color or GREEN
    l.TextXAlignment = align
    l.TextStrokeTransparency = 0.6
    l.Text = ""
    l.Parent = box
    return l
  end
  local title = label("Title", UDim2.new(0, 8, 1, -4), Vector2.new(0, 1), Enum.TextXAlignment.Left)
  local info = label("Info", UDim2.new(1, -8, 1, -4), Vector2.new(1, 1), Enum.TextXAlignment.Right)
  local result = label("Result", UDim2.new(0.5, 0, 0.5, -14), Vector2.new(0.5, 0.5), Enum.TextXAlignment.Center, 22, RGB(255, 240, 200))
  result.Size = UDim2.fromOffset(280, 30)
  result.Font = Enum.Font.BuilderSansExtraBold

  local cur = nil   -- { id, w, tgt = { em, anchor, cl0 }, clone, ground, t0, done, endAt }

  local function clearView()
    for _, c in ipairs(vpf:GetChildren()) do
      if not c:IsA("Camera") and not (c:IsA("Frame") and c.Name ~= "Model") then c:Destroy() end
    end
  end
  -- 目标的实体：服务器的模型（workspace.Ents 里 EntId 对得上的）；客户端画的那一份（View 的视图）拿来复制
  local function findTarget(tg)
    if not tg then return nil end
    local ents = workspace:FindFirstChild("Ents")
    for _, m in ipairs(ents and ents:GetChildren() or {}) do
      if m:GetAttribute("EntId") == tg then
        local v = G.views and G.views[m]
        local anchor = (v and v.anchor) or m:FindFirstChild("Root")
        return m, v and v.model, anchor
      end
    end
    return nil
  end
  -- 复制一份白热的：去掉贴图、特效、灯，零件刷成亮白（导引头的红外画面）
  local function thermalClone(src)
    local ok, cl = pcall(function() return src:Clone() end)
    if not ok or not cl then return nil end
    for _, d in ipairs(cl:GetDescendants()) do
      if d:IsA("BasePart") then
        if d:IsA("MeshPart") then pcall(function() d.TextureID = "" end) end
        d.Color = RGB(236, 236, 232)
        d.Material = Enum.Material.SmoothPlastic
      elseif d:IsA("SurfaceAppearance") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") or d:IsA("Decal")
        or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Sound") or d:IsA("Attachment") then
        d:Destroy()
      end
    end
    cl.Name = "Model"
    return cl
  end
  local function groundPlane(at)
    local p = Instance.new("Part")
    p.Name = "Ground"
    p.Anchored = true
    p.Size = V(6000, 1, 6000)
    p.CFrame = CFrame.new(at.X, math.max(G.Map.ground(at.X, at.Z), 0) - 0.5, at.Z)
    p.Color = RGB(54, 56, 58)
    p.Material = Enum.Material.SmoothPlastic
    p.Parent = vpf
    return p
  end

  function G.onMyShot(e)
    clearView()
    local aw = e.w and AD.W[e.w]
    cur = { id = e.id, w = e.w, t0 = os.clock() }
    title.Text = T("mcam.title", aw and T("aw." .. e.w) or "")
    result.Text = ""
    local em, src, anchor = findTarget(e.tg)
    if em and src and anchor then
      local cl = thermalClone(src)
      if cl then
        cl.Parent = vpf
        local lo, hi = nil, nil   -- 目标多大（各零件的包围盒）：导引头视场按它缩
        for _, d in ipairs(cl:GetDescendants()) do
          if d:IsA("BasePart") and d.Transparency < 1 then
            local c, h = d.Position, d.Size * 0.5
            lo = lo and V(math.min(lo.X, c.X - h.X), math.min(lo.Y, c.Y - h.Y), math.min(lo.Z, c.Z - h.Z)) or (c - h)
            hi = hi and V(math.max(hi.X, c.X + h.X), math.max(hi.Y, c.Y + h.Y), math.max(hi.Z, c.Z + h.Z)) or (c + h)
          end
        end
        cur.tgt = { em = em, anchor = anchor, cl0 = anchor.CFrame, size = math.max(lo and (hi - lo).Magnitude or 0, 8) }
        local p = anchor.Position
        if p.Y - math.max(G.Map.ground(p.X, p.Z), 0) < 40 then groundPlane(p) end   -- 地面、海上的目标：脚下一块地
      end
    end
    if not cur.tgt then groundPlane(e.p) end
    local L = G.hudLayout   -- 右上是小地图（Hud.lua）：镜头框放到它左边
    box.Position = (L and L.radarRight) and UDim2.new(1, -(L.radarX + L.radarSize + 12), 0, L.radarY) or UDim2.new(1, -20, 0, 92)
    -- 11-25：小窗不再自动打开（gui.Enabled 一直关着），只提示按 L 跟踪
    if G.mslFollowHint then G.mslFollowHint() end
  end

  function G.onShotEnd(id, s)
    if not cur or cur.id ~= id or cur.done then return end
    cur.done, cur.endAt = true, os.clock() + 1.3
    local hit = false
    local t = cur.tgt
    if t and t.anchor and t.anchor.Parent then hit = (t.anchor.Position - s.p).Magnitude < 30 end
    result.Text = T(hit and "mcam.hit" or "mcam.miss")
    result.TextColor3 = hit and RGB(255, 236, 170) or RGB(200, 210, 210)
  end
  G.mslCamState = function() return cur end   -- 测试用

  ---------------------------------------------------------------- 按 L 跟踪自己的导弹（第三人称追尾）
  local UIS = game:GetService("UserInputService")
  local RunService = game:GetService("RunService")
  local hintGui = Instance.new("ScreenGui")
  hintGui.Name = "MslFollow"
  hintGui.ResetOnSpawn = false
  hintGui.IgnoreGuiInset = true
  hintGui.DisplayOrder = 9
  hintGui.Parent = pg
  local TH = G.Theme
  local hint = Instance.new("TextLabel")
  hint.Name = "Hint"
  hint.AnchorPoint = Vector2.new(0.5, 1)
  hint.Position = UDim2.new(0.5, 0, 1, -150)
  hint.Size = UDim2.fromOffset(260, 26)
  hint.BackgroundColor3, hint.BackgroundTransparency, hint.BorderSizePixel = RGB(8, 10, 12), 0.35, 0
  hint.Font = (TH and TH.F.bold) or Enum.Font.BuilderSansBold
  hint.TextSize = 15
  hint.TextColor3 = RGB(236, 238, 236)
  hint.TextStrokeTransparency = 0.5
  hint.Visible = false
  hint.Parent = hintGui
  local follow = nil   -- { id, sm 平滑后的镜头位置, look, endAt }
  local hintUntil = 0
  function G.mslFollowHint()
    hintUntil = os.clock() + 4
    hint.Text = T("mcam.followHint")
    hint.Visible = true
  end
  local function liveShot() return cur and not cur.done and G.flyingShots and G.flyingShots[cur.id] end
  G.mslFollowAvail = function() return liveShot() ~= nil or follow ~= nil end   -- Interior.lua：座舱里 L 是灯光，有弹在飞时让给这里
  G.mslFollowing = function() return follow ~= nil end
  UIS.InputBegan:Connect(function(io, gp)
    if gp or io.KeyCode ~= Enum.KeyCode.L then return end
    if follow then follow = nil return end
    local s = liveShot()
    if s then
      follow = { id = cur.id, last = s.p, dir = (s.v and s.v.Magnitude > 1) and s.v.Unit or Vector3.new(0, 0, -1) }
      hint.Visible = false
    end
  end)
  pcall(function()
    RunService:BindToRenderStep("IAMslFollow", Enum.RenderPriority.Last.Value + 5, function(dt)
      if hint.Visible and os.clock() > hintUntil then hint.Visible = false end
      if not follow then return end
      local s = G.flyingShots and G.flyingShots[follow.id]
      local tNow = os.clock()
      if s then
        follow.last = s.p
        if s.v and s.v.Magnitude > 1 then follow.dir = follow.dir:Lerp(s.v.Unit, math.min(1, dt * 6)).Unit end
      elseif not follow.endAt then
        follow.endAt = tNow + 1.5   -- 弹没了：在落点停一秒半
      end
      if follow.endAt and tNow >= follow.endAt then follow = nil return end
      local cam = workspace.CurrentCamera
      if not cam then return end
      local dir = follow.dir
      local want = follow.last - dir * 26 + Vector3.new(0, 7, 0)
      follow.sm = follow.sm and follow.sm:Lerp(want, math.min(1, dt * 10)) or want
      cam.CameraType = Enum.CameraType.Scriptable
      cam.CFrame = CFrame.lookAt(follow.sm, follow.last + dir * 30)
      cam.FieldOfView = 62
    end)
  end)

  function G.stepMslCam()
    if not cur then return end
    if cur.done then
      if os.clock() >= cur.endAt then
        cur = nil
        gui.Enabled = false
        clearView()
      end
      return
    end
    local s = G.flyingShots and G.flyingShots[cur.id]
    if not s then return end
    local p = s.p
    local t = cur.tgt
    if t and t.anchor and t.anchor.Parent then
      local a = t.anchor.CFrame
      local tp = a.Position
      local dist = (tp - p).Magnitude
      -- 小窗里的目标一直摆在复制时的位置：把「弹看目标」换到那个位置上（目标转了、动了，镜头跟着相对地转）
      local camWorld = CFrame.lookAt(p, tp)
      vcam.CFrame = t.cl0 * a:Inverse() * camWorld
      vcam.FieldOfView = math.clamp(math.deg(2 * math.atan(t.size * 1.6 / math.max(dist, 1))), 2, 50)
      local close = (s.v and s.v.Magnitude or 0)
      info.Text = string.format("%.1f km  T-%.1f", dist / M_PER / 1000, dist / math.max(close, 1))
    else
      local fwd = (s.v and s.v.Magnitude > 1) and s.v.Unit or V(0, -1, 0)
      vcam.CFrame = CFrame.lookAt(p, p + fwd)
      vcam.FieldOfView = 30
      info.Text = T("mcam.noTgt")
    end
  end
end

return MslCam
