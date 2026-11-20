-- Roblox全面大战场（客户端）——坦克驾驶界面的补充（用户 11-19 给了一张手机坦克游戏的截图：「坦克驾驶操作界面改成这样」）
--   照那张图的布局和感觉做（不照抄它的图标、配色细节）：
--   · 敌人头顶：看得见的敌方车辆上面一个小牌子（红色的型号名、距离「183 米」），最多 6 个，离得远的、被挡住的不画
--   · 「被发现！」：附近有敌人看得见自己（视线没被挡），或者刚挨了打——左边一块琥珀色的牌子，一闪一闪
--   · 主动防御还剩多少（右下面板上面一行，青色；爆反不显示——用户 11-19）
--   · 开坦克时（电脑）右上的方形小地图挪到左下角、裁成圆的，外圈 0 / 90 / 180 / 270 的方位刻度；下车、换别的载具恢复
--   VehHud.lua 每帧调 G.tankHudExtra(st, 血量比例)；准星两边的弹药数、已就绪、测距在 VehHud 里
--   飞机模式（Fly.lua 调 G.tankHudExtra(st, 血量比例, "air")；用户 11-19：飞机操作界面也照 MWT 的截图改）：
--     圆形小地图挪到左上（里面一个跟着镜头转的视野扇形），「被发现!」在它下面；名牌多一道血条、远的写「x.x 千米」，飞机直升机也有；
--     导弹告警也算被发现；车旁的全息 km/h 牌、主动防御那行不要
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local TankHud = {}

function TankHud.init(G)
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local cam = workspace.CurrentCamera
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local CYAN, RED = RGB(110, 226, 240), RGB(255, 78, 64)
  local MONO, BOLD = Enum.Font.RobotoMono, Enum.Font.GothamBold
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

  local gui = Instance.new("ScreenGui")
  gui.Name = "TankHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 4
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 13, color or CYAN, font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency = 0.55
    l.Parent = parent
    return l
  end

  -- 敌人头顶的牌子（对象池）
  local tags = {}
  for i = 1, 6 do
    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(110, 28)
    f.AnchorPoint = V2(0.5, 1)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = gui
    local nm = label(f, "", UD2(1, 0, 0, 13), UD2(0, 0, 0, 0), 11, RED, BOLD)   -- 字号照 MWT（用户 11-19：文字精简、小一点）
    local dist = label(f, "", UD2(1, 0, 0, 13), UD2(0, 0, 0, 14), 12, Color3.new(1, 1, 1), BOLD)
    -- 飞机模式：名字和距离中间一道红血条
    local barBg = Instance.new("Frame")
    barBg.AnchorPoint, barBg.Position, barBg.Size = V2(0.5, 0), UD2(0.5, 0, 0, 14), UDim2.fromOffset(52, 3)
    barBg.BackgroundColor3, barBg.BackgroundTransparency, barBg.BorderSizePixel = RGB(40, 8, 6), 0.35, 0
    barBg.Visible = false
    barBg.Parent = f
    local bar = Instance.new("Frame")
    bar.Size, bar.BackgroundColor3, bar.BorderSizePixel = UD2(1, 0, 1, 0), RED, 0
    bar.Parent = barBg
    tags[i] = { f = f, nm = nm, dist = dist, barBg = barBg, bar = bar }
  end

  -- 「被发现!」：照 MWT 的样子（用户 11-19：和 MWT 的被发现一模一样的效果，换个颜色）——
  --   左边一道白光拖过来、一个发光的小太阳（圆 + 八道光芒、外面一圈光晕）、后面一块实心的小牌子写「被发现!」（深色字）；
  --   MWT 是橙黄的，这里是红的。刚被发现时整块从左边滑进来、光拖得长一点，之后光晕一呼一吸
  local SPOT = RGB(255, 86, 74)
  local spot = Instance.new("Frame")
  spot.Name = "Spotted"
  spot.Size = UDim2.fromOffset(110, 22)
  spot.AnchorPoint = V2(0, 0.5)
  spot.Position = mobile and UD2(0, 16, 0.3, 0) or UD2(0, 60, 0.43, 0)
  spot.BackgroundTransparency = 1
  spot.Visible = false
  spot.Parent = gui
  local spotX = spot.Position
  local streak = Instance.new("Frame")   -- 拖过来的白光：左边透明、右边亮
  streak.AnchorPoint, streak.Position, streak.Size = V2(1, 0.5), UD2(0, 10, 0.5, 0), UDim2.fromOffset(34, 2)
  streak.BackgroundColor3, streak.BorderSizePixel = Color3.new(1, 1, 1), 0
  streak.Parent = spot
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 0.05) })
    g.Parent = streak
  end
  local sun = Instance.new("Frame")   -- 发光的小太阳
  sun.AnchorPoint, sun.Position, sun.Size = V2(0.5, 0.5), UD2(0, 14, 0.5, 0), UDim2.fromOffset(22, 22)
  sun.BackgroundTransparency = 1
  sun.Parent = spot
  local halo = Instance.new("Frame")
  halo.AnchorPoint, halo.Position, halo.Size = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0), UDim2.fromOffset(20, 20)
  halo.BackgroundColor3, halo.BackgroundTransparency, halo.BorderSizePixel = SPOT, 0.7, 0
  halo.Parent = sun
  local core = Instance.new("Frame")
  core.AnchorPoint, core.Position, core.Size = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0), UDim2.fromOffset(8, 8)
  core.BackgroundColor3, core.BorderSizePixel = RGB(255, 236, 230), 0
  core.Parent = sun
  for _, f in ipairs({ halo, core }) do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
  end
  local rays = {}
  for k = 0, 7 do   -- 八道光芒（绕自己的中心转：按中点摆）
    local a = math.rad(k * 45)
    local r = Instance.new("Frame")
    r.AnchorPoint, r.Size = V2(0.5, 0.5), UDim2.fromOffset(1.5, 4)
    r.Position = UD2(0.5, math.sin(a) * 8, 0.5, -math.cos(a) * 8)
    r.Rotation = k * 45
    r.BackgroundColor3, r.BorderSizePixel = RGB(255, 220, 212), 0
    r.Parent = sun
    rays[k + 1] = r
  end
  local tag = Instance.new("Frame")   -- 实心的小牌子
  tag.AnchorPoint, tag.Position, tag.Size = V2(0, 0.5), UD2(0, 28, 0.5, 0), UDim2.fromOffset(50, 17)
  tag.BackgroundColor3, tag.BackgroundTransparency, tag.BorderSizePixel = SPOT, 0.06, 0
  tag.Parent = spot
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = tag
  end
  local spotTxt = label(tag, "", UD2(1, 0, 1, 0), UD2(0, 0, 0, 0), 11, RGB(70, 10, 8), BOLD)
  spotTxt.TextStrokeTransparency = 1
  local spotOn, spotT0 = false, 0

  -- 车旁边的全息屏：车速（用户 11-19：坦克旁边也要有个牌子写着 km/h，要有全息屏的感觉，照 MWT）——
  --   镜头右边那一侧、炮塔高度浮着一块半透明的青色屏（细边框、四角亮线、扫描线、偶尔闪一下），大字车速、小字 km/h；
  --   斜着一点朝镜头，跟着车走；只在本机（放在镜头下面），开着瞄准镜、下车就收起
  local holo = Instance.new("Part")
  holo.Name = "SpeedHolo"
  holo.Anchored, holo.CanCollide, holo.CanQuery, holo.CanTouch, holo.CastShadow = true, false, false, false, false
  holo.Transparency = 1
  holo.Size = V3(4.2, 1.9, 0.05)
  holo.Parent = cam
  local hsg = Instance.new("SurfaceGui")
  hsg.Name = "SpeedHoloGui"
  hsg.Face = Enum.NormalId.Front
  hsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
  hsg.PixelsPerStud = 60
  hsg.LightInfluence = 0
  hsg.AlwaysOnTop = true
  pcall(function() hsg.Brightness = 1.6 end)   -- 测试用的模拟器里没有这个属性
  hsg.Enabled = false
  hsg.Parent = holo
  local hp = Instance.new("Frame")   -- 屏：上浓下淡的青色
  hp.Size, hp.BackgroundColor3, hp.BackgroundTransparency, hp.BorderSizePixel = UD2(1, 0, 1, 0), CYAN, 0.8, 0
  hp.Parent = hsg
  do
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.8) })
    g.Parent = hp
    local st0 = Instance.new("UIStroke")
    st0.Color, st0.Thickness, st0.Transparency = CYAN, 2, 0.35
    st0.Parent = hp
    for i = 0, 18 do   -- 扫描线
      local l = Instance.new("Frame")
      l.Size, l.Position = UD2(1, 0, 0, 1), UD2(0, 0, 0, 3 + i * 6)
      l.BackgroundColor3, l.BackgroundTransparency, l.BorderSizePixel = CYAN, 0.82, 0
      l.Parent = hp
    end
    for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do   -- 四角的亮线
      for _, sz in ipairs({ { 16, 3 }, { 3, 16 } }) do
        local l = Instance.new("Frame")
        l.AnchorPoint, l.Position, l.Size = V2(c[1], c[2]), UD2(c[1], 0, c[2], 0), UDim2.fromOffset(sz[1], sz[2])
        l.BackgroundColor3, l.BorderSizePixel = CYAN, 0
        l.Parent = hp
      end
    end
  end
  local hSpd = label(hp, "0", UD2(0.62, 0, 1, -8), UD2(0, 8, 0, 4), 66, CYAN, BOLD, nil, Enum.TextXAlignment.Right)
  hSpd.TextStrokeColor3, hSpd.TextStrokeTransparency = CYAN, 0.75
  local hUnit = label(hp, "km/h", UD2(0.36, -8, 0, 30), UD2(0.64, 0, 1, -40), 26, CYAN, BOLD, nil, Enum.TextXAlignment.Left)
  hUnit.TextStrokeTransparency = 0.85
  local holoT = -9   -- 上一次 tankHudExtra 摆它的时刻（瞄准镜里、下车不调 → 收起）
  G.speedHolo = function() return hsg.Enabled and hSpd.Text or nil end   -- 测试用

  -- 主动防御还剩多少（爆反不显示）
  local armLine = label(gui, "", UDim2.fromOffset(240, 14), mobile and UD2(0.5, 0, 0, 72) or UD2(1, -24, 1, -150), 11, CYAN, MONO,
    mobile and V2(0.5, 0) or V2(1, 1), mobile and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right)

  -- 圆形小地图的方位刻度（挪到左下时才显示）
  local MS = 210
  local ring = Instance.new("Frame")
  ring.Size = UDim2.fromOffset(MS + 30, MS + 30)
  ring.AnchorPoint = V2(0.5, 0.5)
  ring.Position = UD2(0, 26 + MS / 2, 1, -26 - MS / 2)
  ring.BackgroundTransparency = 1
  ring.Visible = false
  ring.Parent = gui
  local ringStroke, ringLabs = nil, {}   -- 坦克：青色；飞机：白色（照 MWT 截图左上的雷达：白色细圈、白字）
  do
    local edge = Instance.new("Frame")
    edge.Size = UDim2.fromOffset(MS + 6, MS + 6)
    edge.AnchorPoint, edge.Position = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0)
    edge.BackgroundTransparency = 1
    edge.Parent = ring
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = edge
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = CYAN, 1.5, 0.35
    s.Parent = edge
    ringStroke = s
    for _, b in ipairs({ { 0, "0" }, { 90, "90" }, { 180, "180" }, { 270, "270" } }) do
      local a = math.rad(b[1])
      table.insert(ringLabs, label(ring, b[2], UDim2.fromOffset(30, 12), UD2(0.5, math.sin(a) * (MS / 2 + 10), 0.5, -math.cos(a) * (MS / 2 + 10)), 9, CYAN, MONO, V2(0.5, 0.5)))
    end
  end
  local function ringLook(air)
    ringStroke.Color, ringStroke.Thickness, ringStroke.Transparency = air and Color3.new(1, 1, 1) or CYAN, air and 1.4 or 1.5, air and 0.15 or 0.35
    for _, l in ipairs(ringLabs) do
      l.TextColor3, l.TextSize = air and Color3.new(1, 1, 1) or CYAN, air and 10 or 9
    end
  end

  -- 视野扇形（飞机模式，用户 11-19：照 MWT 截图左上的圆形雷达）：顶点在圆心、朝镜头看的方向（小地图北朝上），放在小地图里（裁成圆）
  local cone = Instance.new("ImageLabel")
  cone.Name = "ViewCone"
  cone.BackgroundTransparency = 1
  cone.AnchorPoint, cone.Position, cone.Size = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0), UD2(1, 0, 1, 0)
  cone.ImageColor3, cone.ImageTransparency = RGB(214, 218, 220), 0.3   -- 淡灰的扇形、中间一根线
  cone.ZIndex = 19   -- 地图上面、亮点（20）下面
  cone.Visible = false
  local coneArt = nil
  -- 正中间自己那架：白色的小飞机，跟着机头转（Hud 的「▲」在飞机模式里藏起来）
  local selfIc = Instance.new("ImageLabel")
  selfIc.Name = "SelfPlane"
  selfIc.BackgroundTransparency = 1
  selfIc.AnchorPoint, selfIc.Position, selfIc.Size = V2(0.5, 0.5), UD2(0.5, 0, 0.5, 0), UDim2.fromOffset(17, 17)
  selfIc.ZIndex = 23
  selfIc.Visible = false
  local selfArt, arrowSaved = nil, nil
  local function hubArrow(box)   -- Hud.lua 小地图正中间的「▲」
    for _, c in ipairs(box:GetChildren()) do
      if c:IsA("TextLabel") and c.Text == "▲" then return c end
    end
  end
  -- 小地图挪到左下（开坦克）/ 左上（开飞机）变圆 / 恢复
  local docked, saved, dockAir = false, nil, false
  local AIR_X, AIR_Y = 64, 62   -- 飞机：左上，让开 Roblox 自己的按钮那一排、左上角的菜单键（≡）
  local function dock(on, air)
    if mobile then on = false end
    air = on and air == true
    if on and docked and air ~= dockAir then   -- 坦克 ↔ 飞机：只换位置
      local box = G.hudParts and G.hudParts.miniBox
      if box then
        box.AnchorPoint = air and V2(0, 0) or V2(0, 1)
        box.Position = air and UD2(0, AIR_X, 0, AIR_Y) or UD2(0, 26, 1, -26)
      end
      dockAir = air
      ring.Position = air and UD2(0, AIR_X + MS / 2, 0, AIR_Y + MS / 2) or UD2(0, 26 + MS / 2, 1, -26 - MS / 2)
      ringLook(air)
      return
    end
    if on == docked then return end
    local box = G.hudParts and G.hudParts.miniBox
    if not box then return end
    docked = on
    local corner = box:FindFirstChildOfClass("UICorner")
    local squad = G.hudParts.hud and G.hudParts.hud:FindFirstChild("Squad")   -- 左下的小队名单（Hud.lua）：挪到圆形小地图右边，不叠在一起
    -- 用户 11-19（MWT 截图）：圆形小地图里只有地图和亮点——方框式的网格、取景框、N / 航向 / 范围读数收起（外圈 0 / 90 / 180 / 270 是这里画的）；
    --   小队名单开坦克时收起（截图上没有）
    local function deco(show)
      for _, c in ipairs(box:GetChildren()) do
        if c.Name == "RadarDeco" and c:IsA("GuiObject") then c.Visible = show end
      end
    end
    if on then
      saved = { a = box.AnchorPoint, p = box.Position, s = box.Size, r = corner and corner.CornerRadius,
        rr = G.hudLayout and G.hudLayout.radarRight, sq = squad and squad.Visible }
      box.AnchorPoint, box.Position, box.Size = air and V2(0, 0) or V2(0, 1), air and UD2(0, AIR_X, 0, AIR_Y) or UD2(0, 26, 1, -26), UDim2.fromOffset(MS, MS)
      dockAir = air
      ring.Position = air and UD2(0, AIR_X + MS / 2, 0, AIR_Y + MS / 2) or UD2(0, 26 + MS / 2, 1, -26 - MS / 2)
      ringLook(air)
      if corner then corner.CornerRadius = UDim.new(0.5, 0) end
      if G.hudLayout then G.hudLayout.radarRight = false end
      if squad then squad.Visible = false end
      deco(false)
    elseif saved then
      box.AnchorPoint, box.Position, box.Size = saved.a, saved.p, saved.s
      if corner and saved.r then corner.CornerRadius = saved.r end
      if G.hudLayout then G.hudLayout.radarRight = saved.rr end
      if squad and saved.sq ~= nil then squad.Visible = saved.sq end
      deco(true)
      dockAir = false
    end
    ring.Visible = on
  end
  G.tankHudDocked = function() return docked end   -- 测试用
  G.airRadarDocked = function() return docked and dockAir end   -- 开飞机、小地图在左上（Coach.lua 把三步卡挪到它下面）

  ---------------------------------------------------------------- 谁看得见
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  local function entOf(inst)
    local ents = workspace:FindFirstChild("Ents")
    while inst and inst.Parent and inst.Parent ~= ents do inst = inst.Parent end
    return (inst and inst.Parent == ents) and inst or nil
  end
  local function excludeList(st)
    local list = {}
    local vf = workspace:FindFirstChild("EntView")   -- View.lua 画的车、船、小兵（看不见的命中盒在 Ents 里）
    if vf then table.insert(list, vf) end   -- 客户端画的车、船（看不见的命中盒在 Ents 里）
    if st and st.em then table.insert(list, st.em) end
    if me.Character then table.insert(list, me.Character) end
    return list
  end
  local function clear(from, to, target, st)
    rp.FilterDescendantsInstances = excludeList(st)
    local hit = workspace:Raycast(from, to - from, rp)
    if not hit then return true end
    local e = entOf(hit.Instance)
    return e ~= nil and e == target
  end

  local cands, lastScan, lastSpot, spotted, hurtT, lastK = {}, 0, 0, false, -9, nil
  local function enemy(em, side)
    if em:GetAttribute("Wreck") or (em:GetAttribute("Hp") or 1) <= 0 then return false end
    local tm = em:GetAttribute("Team")
    return tm ~= nil and tm ~= side
  end

  local airT = -9   -- 飞机模式上一次调的时刻（下了飞机 Fly 不调了 → 收起）
  local CATS = { armor = true, light = true, ship = true }
  local CATS_AIR = { armor = true, light = true, ship = true, air = true, aa = true }   -- 飞机、直升机的实体类别是 air
  function G.tankHudExtra(st, hpK, mode)
    local air = mode == "air"
    gui.Enabled = true
    dock(true, air)
    local t = os.clock()
    if air then airT = t end
    local side = me:GetAttribute("Side")
    local myPos = (st.root and st.root.Position) or (st.cf and st.cf.Position) or cam.CFrame.Position
    -- 飞机模式：小地图里的视野扇形跟着镜头转
    local box = G.hudParts and G.hudParts.miniBox
    if air and docked and box then
      if cone.Parent ~= box then cone.Parent = box end
      if coneArt == nil then coneArt = G.hudIconOn ~= nil and G.hudIconOn(cone, "viewCone") == true end
      local lv = cam.CFrame.LookVector
      cone.Rotation = math.deg(math.atan2(lv.X, -lv.Z))
      cone.Visible = coneArt
      if selfIc.Parent ~= box then selfIc.Parent = box end
      if selfArt == nil then selfArt = G.hudIconOn ~= nil and G.hudIconOn(selfIc, "radarJet") == true end
      local nose = st.cf and st.cf.LookVector or lv
      selfIc.Rotation = math.deg(math.atan2(nose.X, -nose.Z))
      selfIc.Visible = selfArt
      local ar = hubArrow(box)
      if ar and selfArt then
        if arrowSaved == nil then arrowSaved = ar.TextTransparency end
        ar.TextTransparency = 1
      end
    else
      if cone.Visible then cone.Visible = false end
      if selfIc.Visible then selfIc.Visible = false end
      if arrowSaved ~= nil and box then
        local ar = hubArrow(box)
        if ar then ar.TextTransparency = arrowSaved end
        arrowSaved = nil
      end
    end
    local ents = workspace:FindFirstChild("Ents")
    -- 敌人：每 0.25 秒重新挑一遍（距离、视线），每帧摆牌子
    if t - lastScan > 0.25 then
      lastScan = t
      cands = {}
      for _, em in ipairs(ents and ents:GetChildren() or {}) do
        local cat = em:GetAttribute("Cat")
        if (air and CATS_AIR or CATS)[cat] and enemy(em, side) then
          local r = em:FindFirstChild("Root")
          if r then
            local d = (r.CFrame.Position - myPos).Magnitude   -- CFrame.Position：测试台的零件只认这个
            if d < (air and 11200 or 1100) and clear(cam.CFrame.Position, r.CFrame.Position, em, st) then table.insert(cands, { em = em, r = r, d = d }) end
          end
        end
      end
      table.sort(cands, function(a, b) return a.d < b.d end)
    end
    local n = 0
    for _, c in ipairs(cands) do
      if n >= #tags then break end
      if c.em.Parent and c.r.Parent then
        -- 飞机模式：名牌摆在目标中心往上 34 像素（锁定的菱形、四个直角框在目标身上，名字、血条、距离叠在框的上面，照 MWT 截图）
        local top = air and c.r.CFrame.Position or (c.r.CFrame.Position + V3(0, c.r.Size.Y / 2 + 2.5, 0))
        local sp, on = cam:WorldToViewportPoint(top)
        if on then
          n += 1
          local tg = tags[n]
          tg.f.Visible = true
          tg.f.Position = UDim2.fromOffset(sp.X, sp.Y - (air and 34 or 0))
          local id = c.em:GetAttribute("Model")
          tg.nm.Text = id and (string.match(T("veh." .. id), "^(%S+)") or T("veh." .. id)) or ""   -- 只写型号
          local m = (c.r.CFrame.Position - myPos).Magnitude / 2.8
          tg.dist.Text = (air and m >= 1000) and T("vh.km", string.format("%.1f", m / 1000)) or T("vh.m", math.floor(m + 0.5))
          -- 飞机模式：名字下面一道血条，距离往下挪
          tg.barBg.Visible = air
          tg.dist.Position = air and UD2(0, 0, 0, 19) or UD2(0, 0, 0, 14)
          if air then
            local hp, mx = c.em:GetAttribute("Hp") or 1, c.em:GetAttribute("MaxHp") or 1
            tg.bar.Size = UD2(math.clamp(hp / math.max(mx, 1), 0, 1), 0, 1, 0)
          end
        end
      end
    end
    for i = n + 1, #tags do tags[i].f.Visible = false end
    -- 被发现：附近（500 格以内）的敌方车辆、敌方玩家看得见自己；或者刚挨了打
    if lastK and hpK < lastK - 0.001 then hurtT = t end
    lastK = hpK
    if t - lastSpot > 0.4 then
      lastSpot = t
      spotted = false
      for _, c in ipairs(cands) do
        if c.d < (air and 2800 or 500) then spotted = true break end   -- 我看得见它，它也看得见我（同一条视线）；飞机：一千米以内
      end
      if air and st.rwrT and os.clock() < st.rwrT then spotted = true end   -- 被导弹锁了 / 来袭（Fly 的告警）
      if not spotted then
        for _, pl in ipairs(Players:GetPlayers()) do
          if pl ~= me and pl:GetAttribute("Side") and pl:GetAttribute("Side") ~= side then
            local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.CFrame.Position - myPos).Magnitude < (air and 2800 or 500) then
              rp.FilterDescendantsInstances = excludeList(st)
              local hit = workspace:Raycast(myPos + V3(0, 4, 0), hrp.CFrame.Position - myPos - V3(0, 4, 0), rp)
              if not hit or hit.Instance:IsDescendantOf(pl.Character) then spotted = true break end
            end
          end
        end
      end
    end
    local show = spotted or (t - hurtT < 3)
    if show and not spotOn then spotT0 = t end   -- 刚被发现：从左边滑进来
    spotOn = show
    spot.Visible = show
    if show then
      spotTxt.Text = T("vh.spotted")
      local a = math.clamp((t - spotT0) / 0.22, 0, 1)
      local e = 1 - (1 - a) * (1 - a)
      local base = (air and docked) and UD2(0, AIR_X + 4, 0, AIR_Y + MS + 34) or spotX   -- 飞机：左上圆形雷达的正下方（照 MWT 截图）
      spot.Position = base + UD2(0, -40 * (1 - e), 0, 0)
      streak.Size = UDim2.fromOffset(34 + 60 * (1 - e), 2)
      local pulse = 0.5 + 0.5 * math.sin(t * 5)
      halo.BackgroundTransparency = 0.55 + 0.3 * pulse
      halo.Size = UDim2.fromOffset(16 + 8 * pulse, 16 + 8 * pulse)
      for _, r in ipairs(rays) do r.BackgroundTransparency = 0.15 + 0.35 * pulse end
      streak.BackgroundTransparency = 0.1 + 0.25 * pulse
    end
    -- 车旁边的全息屏：镜头右边那一侧、炮塔高度，斜一点朝着镜头
    local root = (not air) and st.root or nil   -- 飞机不要（速度在准星右边的括号里）
    if root then
      local d = st.d or {}
      local cp = cam.CFrame
      local right = V3(cp.RightVector.X, 0, cp.RightVector.Z)
      right = (right.Magnitude > 0.01) and right.Unit or V3(1, 0, 0)
      local W, H = (d.W or 10), (d.H or 7)
      local pos = root.Position + right * (W * 0.5 + 3.2) + V3(0, H * 0.1, 0)
      holo.Size = V3(4.2, 1.9, 0.05) * math.clamp(W / 10, 0.8, 1.2)
      holo.CFrame = CFrame.lookAt(pos, cp.Position) * CFrame.Angles(0, math.rad(-16), 0)
      local kmh = math.floor(math.abs(st.speed or 0) / 2.8 * 3.6 + 0.5)
      hSpd.Text = tostring(kmh)
      local flick = (math.noise(t * 3, 1.7) > 0.42) and 0.12 or 0   -- 偶尔闪一下
      hp.BackgroundTransparency = 0.8 + flick
      hSpd.TextTransparency = flick * 0.8
      hsg.Enabled = true
      holoT = t
    end
    -- 爆反、主动防御
    local em = st.em
    local parts = {}
    -- 爆反还剩几块不显示了（用户 11-19：不要显示爆反了）；装了主动防御的照旧写还剩几发
    local aps = (not air) and em and em:GetAttribute("ApsMax")
    if aps then table.insert(parts, T("vh.aps", em:GetAttribute("Aps") or 0, aps)) end
    armLine.Text = table.concat(parts, "   ·   ")
  end

  -- 不在开坦克：收起来，小地图放回去
  G.frameConn("TankHud", function()
    if hsg.Enabled and os.clock() - holoT > 0.15 then hsg.Enabled = false end   -- 开着瞄准镜、下车：全息屏收起
    if not G.myVeh and os.clock() - airT > 0.2 then   -- 不在开坦克、也不在开飞机
      if gui.Enabled then
        gui.Enabled = false
        for _, tg in ipairs(tags) do tg.f.Visible = false end
      end
      if docked then dock(false) end
      -- 飞机模式留在小地图里的扇形、小飞机收起来，「▲」放回来
      if cone.Visible then cone.Visible = false end
      if selfIc.Visible then selfIc.Visible = false end
      if arrowSaved ~= nil then
        local box = G.hudParts and G.hudParts.miniBox
        local ar = box and hubArrow(box)
        if ar then ar.TextTransparency = arrowSaved end
        arrowSaved = nil
      end
    end
  end)
end

return TankHud
