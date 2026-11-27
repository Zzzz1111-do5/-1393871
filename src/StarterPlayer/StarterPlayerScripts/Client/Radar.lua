-- 全面大战场（客户端）——战雷式机载雷达
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   每型飞机的雷达在 AirDefs 的 radar（pd 脉冲多普勒 / pulse 脉冲、搜索 / 锁定距离、方位俯仰扫描范围、置零门限）：
--   ① 搜索（SRC）：扫描线在方位里来回扫，扫到的敌机在雷达屏上亮一下、慢慢暗下去。看不见的：出了扫描范围、太远、
--      置零（pd：目标相对地面的速度在视线上的分量太小——它侧着飞、把你放在 3 点 / 9 点方向）、地杂波（pulse：往下看、目标贴地）
--   ② 锁定（STT）：Fly.lua 拿雷达弹锁着一架时，扫描线停在它身上；它置零 / 出了范围超过 1 秒就丢锁（Fly.lua 管）
--   ③ 雷达屏（B 显）：左边中间一块方屏，横轴方位、竖轴距离；敌机一小横道，锁定的那架套方框；上面写雷达型号、模式，下面量程，
--      锁着的目标在置零时写「置零」
--   G.radarSees(st, em) → 看得见吗、看不见的原因（range / fov / notch / clutter）、方位°、俯仰°、距离（Fly.lua 挑目标、保持锁定用）
--   G.radarStep(st, dt, lockEm)：每帧扫描、画屏；G.radarOff()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Radar = {}

function Radar.init(G)
  local me = Players.LocalPlayer
  local Map = G.Map or require(RS:WaitForChild("Map"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local V, RGB, U2, V2 = Vector3.new, Color3.fromRGB, UDim2, Vector2.new
  local clamp = math.clamp
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local function ground(x, z) return AD.ground and AD.ground(Map, x, z) or Map.ground(x, z) end

  -- 敌机的速度：按位置两帧差平滑（服务器不发速度）
  local track = setmetatable({}, { __mode = "k" })
  --   只在服务器真挪了它时按两次挪之间的时间算（View.lua G.velTrack；原来每帧差分，「0、0、一大截」）
  local function velOf(em, p, now)
    local t = track[em]
    if not t then
      t = {}
      track[em] = t
    end
    if G.velTrack then return G.velTrack(t, p, now, 2000) end
    t.p, t.t, t.v = p, now, t.v or V()
    return t.v
  end

  local function sees(st, em)
    local rd = st and st.d and st.d.radar
    if not rd then return true end   -- 没有对空雷达的飞机：照旧（老规则，按导引头的视场）
    local root = em and em.Parent and em:FindFirstChild("Root")
    if not root then return false, "gone" end
    local p0, p = st.cf.Position, root.CFrame.Position
    local to = p - p0
    local dist = to.Magnitude
    if dist < 1 then return true, nil, 0, 0, dist end
    local u = to / dist
    local l = st.cf:VectorToObjectSpace(u)
    local az = math.deg(math.atan2(l.X, -l.Z))
    local el = math.deg(math.asin(clamp(l.Y, -1, 1)))
    local vT = velOf(em, p, os.clock())
    if dist > rd.range then return false, "range", az, el, dist end
    if math.abs(az) > rd.az or math.abs(el) > rd.el then return false, "fov", az, el, dist end
    if rd.kind == "pd" then
      -- 脉冲多普勒：地面回波的多普勒频移 = 自己的速度在这个方向上的分量；目标的 = （它的 − 自己的）在视线上的分量。
      --   两个差的正好是目标相对地面的速度在视线上的分量——太小（侧着飞）就和地杂波混在一起被滤掉：置零
      if math.abs(vT:Dot(u)) < (rd.notch or 50) then return false, "notch", az, el, dist end
    else
      -- 脉冲雷达：往下看时背景是地面，贴地的目标埋在地杂波里
      local tAlt = p.Y - math.max(ground(p.X, p.Z), 0)
      if u.Y < -0.06 and tAlt < 700 then return false, "clutter", az, el, dist end
    end
    return true, nil, az, el, dist
  end
  G.radarSees = sees

  ---------------------------------------------------------------- 雷达屏（战雷式：右侧方形屏；用户 11-24 夜：「那个雷达屏在右侧」「战雷不同的雷达会有不同的扫描图」）
  --   照战雷 wiki（「Airborne radars」「机载雷达」）：顶上「工作模式 + 信号处理」（SRC 搜索 / TRK 跟踪，PD 脉冲多普勒；老的脉冲雷达只写 SRC / TRK；
  --   跟踪的目标一时看不见、雷达按记忆外推时 TRK MEM）；左上扫描范围「方位 × 俯仰」、两个上角方位极限、右上量程、右下 0 km、左边俯仰角和天线俯仰标记；
  --   屏里竖的扫描波束来回扫；搜到的目标一短横（越久没扫到越暗），选中的两边加竖线，跟踪着的套方框、带一根速度线；
  --   自己打出去的主动雷达弹（数据链，用户：「飞机本身会和自己的导弹形成数据链互相提供信息」）：弹一个小点，到目标一条线——
  --   导引头还没开机（靠你的雷达给目标位置）是虚线、预计命中点一个小圈；开机了实线；数据链断了（你丢了锁、转开、雷达关了）只剩那个小圈
  --   键：Alt+R 开关雷达、Alt+Q 换量程（量程外的不显示）、Alt+T 换目标（同 R）；屏下面一排按键提示
  local gui = Instance.new("ScreenGui")
  gui.Name = "Radar"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local UIS = game:GetService("UserInputService")
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local GRN, LINE, FILL, BEAM = TH.C.HUD, TH.C.HUD:Lerp(TH.C.INK, 0.12), TH.C.HUD:Lerp(TH.C.INK, 0.55), TH.C.HUD:Lerp(Color3.new(1, 1, 1), 0.3)
  local AMB, RED = TH.C.WARN, TH.C.BAD
  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or U2.new()
    f.AnchorPoint = anchor or V2(0, 0)
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col, tr, 0
    f.Parent = parent
    return f
  end
  local function label(parent, name, pos, anchor, align, ts)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = U2.fromOffset(90, 14), pos, anchor or V2(0, 0)
    l.Font, l.TextSize, l.TextColor3 = Enum.Font.RobotoMono, ts or 13, GRN
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.45, RGB(0, 20, 8)
    l.Text = ""
    l.Parent = parent
    return l
  end
  local function line(parent, col, th)
    local f = frame(parent, U2.fromOffset(2, th or 1.4), U2.new(), col or GRN, 0, V2(0.5, 0.5))
    f.Visible = false
    return f
  end
  local function setLine(f, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    f.Size = U2.fromOffset(math.sqrt(dx * dx + dy * dy), f.Size.Y.Offset)
    f.Position = U2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
    f.Rotation = math.deg(math.atan2(dy, dx))
    f.Visible = true
  end
  local W, H = mobile and 190 or 236, mobile and 180 or 224
  local scope = frame(gui, U2.fromOffset(W, H), mobile and U2.new(1, -16, 0.5, 60) or U2.new(1, -44, 0.5, 130), FILL, 0.5, V2(1, 0.5))   -- 右侧偏下：让开右上的圆形小地图和它下面的「被发现!」
  scope.Name = "RadarScope"
  local st0 = Instance.new("UIStroke")
  st0.Color, st0.Thickness, st0.Transparency = LINE, 1.2, 0.25
  st0.Parent = scope
  -- 网格：方位八格、距离四格
  for i = 1, 7 do
    local v = frame(scope, U2.new(0, 1, 1, 0), U2.fromScale(i / 8, 0), LINE, (i == 4) and 0.35 or 0.6)
    v.Name = "Grid"
  end
  for i = 1, 3 do
    local h = frame(scope, U2.new(1, 0, 0, 1), U2.fromScale(0, i / 4), LINE, 0.6)
    h.Name = "Grid"
  end
  local scan = frame(scope, U2.new(0, 7, 1, 0), U2.fromScale(0.5, 0), BEAM, 0.55, V2(0.5, 0))
  scan.Name = "ScanLine"
  local blips = {}
  for i = 1, 14 do
    local b = frame(scope, U2.fromOffset(12, 3), U2.new(), Color3.new(1, 1, 1), 0, V2(0.5, 0.5))
    b.Name = "Blip"
    b.Visible = false
    local l1 = frame(b, U2.fromOffset(2, 9), U2.new(0, -4, 0.5, 0), Color3.new(1, 1, 1), 0, V2(0.5, 0.5))   -- 选中的：两边竖线「|—|」
    local l2 = frame(b, U2.fromOffset(2, 9), U2.new(1, 4, 0.5, 0), Color3.new(1, 1, 1), 0, V2(0.5, 0.5))
    l1.Name, l2.Name = "SelL", "SelR"
    blips[i] = { f = b, l1 = l1, l2 = l2 }
  end
  local lockBox = frame(scope, U2.fromOffset(14, 14), U2.new(), AMB, 1, V2(0.5, 0.5))
  lockBox.Name = "RadarLock"
  local ls = Instance.new("UIStroke")
  ls.Color, ls.Thickness = Color3.new(1, 1, 1), 1.5
  ls.Parent = lockBox
  lockBox.Visible = false
  local lockDot = frame(scope, U2.fromOffset(5, 5), U2.new(), Color3.new(1, 1, 1), 0, V2(0.5, 0.5))
  lockDot.Name = "TrackDot"
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = lockDot
  end
  lockDot.Visible = false
  local velLine = line(scope, Color3.new(1, 1, 1), 1.4)
  velLine.Name = "TrackVel"
  -- 天线俯仰标记：左边沿一小横道
  local elMark = frame(scope, U2.fromOffset(9, 2), U2.new(0, -2, 0.5, 0), Color3.new(1, 1, 1), 0, V2(1, 0.5))
  elMark.Name = "AntennaEl"
  -- 数据链：自己打出去的主动雷达弹
  local dl = {}
  for i = 1, 4 do
    local dot = frame(scope, U2.fromOffset(4, 4), U2.new(), Color3.new(1, 1, 1), 0, V2(0.5, 0.5))
    dot.Name = "Missile"
    dot.Visible = false
    local ring = frame(scope, U2.fromOffset(10, 10), U2.new(), Color3.new(1, 1, 1), 1, V2(0.5, 0.5))
    ring.Name = "IOG"
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = ring
    local rs = Instance.new("UIStroke")
    rs.Color, rs.Thickness = Color3.new(1, 1, 1), 1.2
    rs.Parent = ring
    ring.Visible = false
    local segs = {}
    for k = 1, 8 do
      segs[k] = line(scope, Color3.new(1, 1, 1), 1.2)
      segs[k].Name = "DlSeg"
    end
    dl[i] = { dot = dot, ring = ring, segs = segs }
  end
  -- 屏外的字
  local tMode = label(scope, "RadarMode", U2.new(0.5, 0, 0, -36), V2(0.5, 0), Enum.TextXAlignment.Center, 14)
  local tZone = label(scope, "RadarZone", U2.new(0, -6, 0, -36), V2(0, 0))
  local tRange = label(scope, "RadarRange", U2.new(1, 0, 0, -18), V2(1, 0), Enum.TextXAlignment.Right)
  local tAzL = label(scope, "AzL", U2.new(0, 2, 0, -18), V2(0, 0))
  local tAzR = label(scope, "AzR", U2.new(1, -40, 0, -18), V2(1, 0), Enum.TextXAlignment.Right)
  local tElT = label(scope, "ElT", U2.new(0, -6, 0.2, 0), V2(1, 0.5), Enum.TextXAlignment.Right)
  local tElB = label(scope, "ElB", U2.new(0, -6, 0.8, 0), V2(1, 0.5), Enum.TextXAlignment.Right)
  local tZero = label(scope, "RangeMin", U2.new(1, 0, 1, 4), V2(1, 0), Enum.TextXAlignment.Right)
  tZero.Text = "0 km"
  local tName = label(scope, "RadarName", U2.new(0, 0, 1, 4), V2(0, 0))
  tName.Size = U2.fromOffset(W - 50, 14)
  tName.TextSize = 11
  local tWarn = label(scope, "RadarWarn", U2.new(0.5, 0, 0.5, 0), V2(0.5, 0.5), Enum.TextXAlignment.Center, 14)
  tWarn.TextColor3 = AMB
  local tEmit = label(scope, "Emit", U2.new(0, 0, 1, 20), V2(0, 0), Enum.TextXAlignment.Left, 13)
  local tKeys = label(scope, "Keys", U2.new(0, 0, 1, 36), V2(0, 0), Enum.TextXAlignment.Left, 10)
  tKeys.Size = U2.fromOffset(W + 60, 14)
  tKeys.TextColor3 = RGB(200, 230, 205)
  tKeys.Text = mobile and "" or "Alt+R 开关  Alt+Q 量程  Alt+T / R 换目标"

  ---------------------------------------------------------------- 每帧

  local seen = setmetatable({}, { __mode = "k" })   -- [em] = { t = 扫到的时刻, az, dist }
  local S = { az = 0, dir = 1, on = true, scale = 1, el = 0, eld = 1 }
  local SCALES = { 1, 0.5, 0.25 }
  local lastSt = nil
  local function hostiles(st)
    local out = {}
    local f = workspace:FindFirstChild("Ents")
    if not f then return out end
    local myTeam = me:GetAttribute("Side")
    for _, em in ipairs(f:GetChildren()) do
      if em ~= st.em and em:GetAttribute("Kind") == "air" and em:GetAttribute("Team") ~= myTeam and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        table.insert(out, em)
      end
    end
    return out
  end
  -- 雷达关着：看不见（Fly.lua 的雷达弹锁不上、锁着的一秒后丢）
  local sees0 = sees
  sees = function(st, em)
    if not S.on and st and st.d and st.d.radar then return false, "off" end
    return sees0(st, em)
  end
  G.radarSees = sees
  G.radarOn = function() return S.on end

  -- 键：Alt+R 开关、Alt+Q 量程、Alt+T 换目标
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not lastSt or not lastSt.pilot or not (lastSt.d and lastSt.d.radar) then return end
    if not (UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)) then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.R then
      S.on = not S.on
      if G.toast then G.toast(T(S.on and "wt.radarOn" or "wt.radarOff"), "info") end
    elseif k == Enum.KeyCode.Q then
      S.scale = S.scale % #SCALES + 1
      local rd = lastSt.d.radar
      if G.toast then G.toast(T("wt.radarRange", string.format("%.0f", rd.range * SCALES[S.scale] / AD.M / 1000)), "info") end
    elseif k == Enum.KeyCode.T then
      if G.flyNextTarget then G.flyNextTarget() end
    end
  end)

  local contacts = {}
  function G.radarContacts() return contacts end   -- 航向罗盘上的小三角（WtFlight.lua）

  function G.radarStep(st, dt, lockEm)
    lastSt = st
    local rd = st and st.d and st.d.radar
    if not rd or not st.pilot or st.uav then
      gui.Enabled = false
      table.clear(contacts)
      return
    end
    gui.Enabled = not st.eo and not st.bsight
    local now = os.clock()
    local range = rd.range * SCALES[S.scale]
    local pd = rd.kind == "pd"
    -- 扫描线：锁着就停在目标上（TRK），不然在方位里来回扫；雷达关着不扫
    local stt = false
    local lockOk, lockWhy, lockAz, lockEl, lockDist = false, nil, nil, nil, nil
    if lockEm then
      lockOk, lockWhy, lockAz, lockEl, lockDist = sees(st, lockEm)
      if lockAz then stt = true end
    end
    if not S.on then
      stt = false
    elseif stt and lockOk then
      S.az = clamp(lockAz, -rd.az, rd.az)
      S.el = clamp(lockEl or 0, -rd.el, rd.el)
    else
      S.az = S.az + S.dir * rd.az * 2 / 1.1 * dt
      if S.az > rd.az then S.az, S.dir = rd.az, -1 elseif S.az < -rd.az then S.az, S.dir = -rd.az, 1 end
      S.el = S.el + S.eld * rd.el * 2 / 4.4 * dt   -- 天线俯仰慢慢上下扫（一来一回将近九秒）
      if S.el > rd.el * 0.8 then S.el, S.eld = rd.el * 0.8, -1 elseif S.el < -rd.el * 0.8 then S.el, S.eld = -rd.el * 0.8, 1 end
    end
    -- 扫到的（扫描线扫过它的方位附近）、看得见的、在量程里的：记下来；没扫到的照旧显示一会儿再暗下去
    local list = S.on and hostiles(st) or {}
    for _, em in ipairs(list) do
      local ok, _, az, _, dist = sees(st, em)
      if ok and az and dist <= range and (math.abs(az - S.az) < 7 or em == lockEm) then
        seen[em] = { t = now, az = az, dist = dist }
      end
    end
    -- 画
    local function xOf(az) return clamp(0.5 + az / (2 * rd.az), 0.02, 0.98) end
    local function yOf(dist) return clamp(1 - dist / range, 0.02, 0.98) end
    scan.Visible = S.on
    scan.Position = U2.fromScale(xOf(S.az), 0)
    scan.BackgroundColor3 = (stt and lockOk) and AMB or BEAM
    elMark.Position = U2.new(0, -2, clamp(0.5 - S.el / (2 * rd.el), 0.02, 0.98), 0)
    local n = 0
    table.clear(contacts)
    for em, r in pairs(seen) do
      local age = now - r.t
      if age > 2.6 or not em.Parent or not S.on then
        seen[em] = nil
      else
        table.insert(contacts, { em = em, az = r.az, dist = r.dist, locked = em == lockEm })
        if n < #blips and em ~= lockEm then
          n += 1
          local b = blips[n]
          b.f.Position = U2.fromScale(xOf(r.az), yOf(r.dist))
          b.f.BackgroundTransparency = clamp(age / 2.6, 0, 0.85)
          local sel = st.lock ~= nil and st.lock.em == em
          b.l1.Visible, b.l2.Visible = sel, sel
          b.f.Visible = true
        end
      end
    end
    for i = n + 1, #blips do blips[i].f.Visible = false end
    -- 跟踪着的目标：方框 + 圆点 + 速度线（目标往哪飞，屏上横是方位、竖是距离）
    local showLock = stt and lockAz ~= nil and lockDist ~= nil
    lockBox.Visible, lockDot.Visible = showLock, showLock
    if showLock then
      local lx, ly = xOf(lockAz), yOf(lockDist)
      lockBox.Position, lockDot.Position = U2.fromScale(lx, ly), U2.fromScale(lx, ly)
      local root = lockEm:FindFirstChild("Root")
      local vT = root and velOf(lockEm, root.CFrame.Position, now) or V()
      if vT.Magnitude > 5 then
        local l = st.cf:VectorToObjectSpace(vT.Unit)
        local px, py = lx * W, ly * H
        setLine(velLine, px, py, px + l.X * 22, py + l.Z * 22)   -- 往前飞（−Z）在屏上往上
      else
        velLine.Visible = false
      end
    else
      velLine.Visible = false
    end
    -- 数据链：自己打出去的主动雷达弹
    local fl = G.flyingShots or {}
    local di = 0
    for _, fs in pairs(fl) do
      if di >= #dl then break end
      local aw = fs.aw
      if fs.my and aw and aw.seeker == "radar" and aw.act and fs.p then
        di += 1
        local D = dl[di]
        local l = st.cf:PointToObjectSpace(fs.p)
        local mAz = math.deg(math.atan2(l.X, -l.Z))
        local mx, my = xOf(mAz) * W, yOf(l.Magnitude) * H
        D.dot.Position, D.dot.Visible = U2.fromOffset(mx, my), true
        -- 目标在屏上的位置（数据链给的）；断了就是最后估的命中点
        local tx, ty = nil, nil
        local tem = nil
        local ents = workspace:FindFirstChild("Ents")
        if fs.tg and ents then
          for _, em in ipairs(ents:GetChildren()) do
            if em:GetAttribute("EntId") == fs.tg then tem = em break end
          end
        end
        local troot = tem and tem:FindFirstChild("Root")
        if troot and not fs.lost then
          local tl = st.cf:PointToObjectSpace(troot.CFrame.Position)
          tx, ty = xOf(math.deg(math.atan2(tl.X, -tl.Z))) * W, yOf(tl.Magnitude) * H
          fs.iog = { tx, ty }
        elseif fs.iog then
          tx, ty = fs.iog[1], fs.iog[2]
        end
        local linkOk = not fs.lost and S.on and stt and lockEm == tem
        if tx then
          D.ring.Position = U2.fromOffset(tx, ty)
          D.ring.Visible = not fs.act   -- 导引头开机前：预计命中点一个小圈
          local segs = D.segs
          local nseg = #segs
          for kq, sg in ipairs(segs) do
            if fs.act or linkOk then
              local a0 = (kq - 1) / nseg
              local a1 = fs.act and (kq / nseg) or ((kq - 0.5) / nseg)   -- 开机前虚线、开机后实线
              setLine(sg, mx + (tx - mx) * a0, my + (ty - my) * a0, mx + (tx - mx) * a1, my + (ty - my) * a1)
              sg.BackgroundColor3 = fs.act and RED or Color3.new(1, 1, 1)
            else
              sg.Visible = false
            end
          end
        else
          D.ring.Visible = false
          for _, sg in ipairs(D.segs) do sg.Visible = false end
        end
      end
    end
    for i = di + 1, #dl do
      dl[i].dot.Visible, dl[i].ring.Visible = false, false
      for _, sg in ipairs(dl[i].segs) do sg.Visible = false end
    end
    -- 字
    local mode = (stt and lockOk) and "TRK" or ((stt and not lockOk) and "TRK MEM" or "SRC")
    tMode.Text = S.on and (mode .. (pd and " PD" or "")) or "OFF"
    tZone.Text = string.format("%d°×%d°", rd.az * 2, rd.el * 2)
    tRange.Text = string.format("%.0f km", range / AD.M / 1000)
    tAzL.Text, tAzR.Text = string.format("-%d°", rd.az), string.format("%d°", rd.az)
    tElT.Text, tElB.Text = string.format("%d°", math.floor(rd.el * 0.6)), string.format("-%d°", math.floor(rd.el * 0.6))
    tName.Text = rd.name or ""
    tEmit.Text = S.on and "((o))" or "( . )"
    tEmit.TextColor3 = S.on and GRN or RGB(120, 140, 125)
    tWarn.Text = (stt and lockWhy == "notch") and T("air.radarNotch") or ((stt and lockWhy == "clutter") and T("air.radarClutter") or "")
    st.radarAz, st.radarStt = S.az, stt and lockOk   -- 测试用
  end

  function G.radarOff()
    gui.Enabled = false
    table.clear(contacts)
  end
  G.radarGui = gui   -- 测试用
end

return Radar
