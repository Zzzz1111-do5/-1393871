-- 全面大战场（客户端）——战雷式机载雷达
--   用户 11-24 夜：「战雷我记得不同带有雷达的载具会根据雷达型号有雷达扫描图的，为雷达锁定式导弹提供引导，所以也有 39 机动的这种说法」
--   用户 11-27：「飞机雷达按型号照战雷做、能用键控制雷达方向」
--   每型、每个科技树版本的雷达在 ReplicatedStorage/Radars.lua（Fly.lua 开飞时按 AirDefs.radarOf(型号, TreeKey) 取到 st.rd：F-16A 是 APG-66、苏-30SM 是 N011M）
--   ① 扫描区：各型自己的扫描方式（rd.scans：方位半宽 × 行数，第一个是默认，Alt+Z 换）；波束按真机的扫描速度（rd.rate：机械扫描约 60°/秒、相控阵快，
--      用户 11-27 定的）在扫描区里一行一行来回扫——扫一帧 = 行数 × 2 × 半宽 / 速度（APG-68 ±60°×2 行 4 秒、×4 行 8 秒；KLJ-5 1.6 秒）。
--      **地平稳定**：方位按航向的水平投影、俯仰按地平线（真机给天线俯仰也是按地平线）；扫描中心可挪（「能用键控制雷达方向」）：Alt+←→ 方位
--      （|中心| ≤ 万向架 − 半宽：±60° 宽扫时挪不动，苏-35S 的转台能挪到 ±60°）、Alt+↑↓ / Alt+滚轮 俯仰、Alt+C 或双击雷达屏回中
--   ② 发现：**波束真扫过才算**——目标在这一帧波束扫过的那段里（方位 ± 波束半宽，俯仰离这一行不到半行 + 0.5°），再过 sees()：万向架（机体坐标
--      ±az、+elU / −elD，扫描区挪到外面的那段看不见）、量程（窄扇区 × far；脉冲多普勒往下看 × ldK）、置零（pd：目标对地速度在视线上的分量 < notch——
--      它侧着飞、把你放在 3 / 9 点）、地杂波（pulse：往下看、目标离地低于波束在那里的半宽 + 150 格）。扫到的亮一下，一帧多一点（RD.fade）以后暗掉
--   ③ 模式（Alt+E 循环，这部雷达没有的跳过，RD.modes）：RWS 搜索 → TWS 边扫边跟（rd.tws > 0：最多 rd.tws 批航迹，扫到就更新、两次之间按速度外推，
--      两帧没扫到就丢；AWG-9 只能用 twsScans 那两种扫描；R / Alt+T 在航迹里换指定目标；**对指定航迹打主动雷达弹不用 STT**：Fly.lua 的弹锁着指定航迹，
--      每次航迹更新报一次 lockOn（带 tws = 一帧几秒），服务器的数据链等一帧、对方告警器不报锁定，导弹开导引头时才报）→ ACM 近战（rd.acm：
--      平显视场 / 竖扫 / 瞄准线 / 可挪 / 头盔，机体坐标；Alt+Z 换子模式，可挪的用 Alt+方向键挪、头盔的跟着镜头看的方向；RD.ACQ 格（真机 10 海里）
--      以内第一个扫到的自动进 STT，不管选的是什么弹）→ 回 RWS
--   ④ STT 单目标跟踪（st.rdLock）：Alt+F 锁雷达屏上选中的（照战雷手动锁，用户 11-27 定的；Fly.lua G.flyRadarLock 查锁定距离）、近战自动截获；
--      天线跟着目标（只看万向架）；看不见了（置零 / 地杂波 / 出了万向架 / 太远）先按记忆外推 RD.MEM 秒（屏上 STT MEM），还是没有就丢锁
--      （提示置零 / 丢失）、回到原来的扫描；跟踪着每半秒报一次 lockOn（数据链、对方的告警）。换模式、关雷达就断开。
--      **跟所选武器脱钩**：雷达弹锁它（Fly.lua）、红外弹导引头跟着它指、机炮提前量优先算它
--   ⑤ 雷达屏（B 显，照战雷的方形雷达屏；用户 11-28 给了截图、「那就不做扇形了」）：右边一块方屏，横轴方位铺满这部雷达的方位万向架
--      （±rd.az，两个上角写两头的角度，同战雷「-70° … 70°」），扫描区是里面两条竖线；竖轴距离（四道距离线，右上量程、右下 0 km）；
--      扫描区两条竖线、底边下面小三角指扫描中心、左边一道竖括号是扫描的俯仰范围（一行一个小横道，正在扫的那行亮）、白横道是天线俯仰；
--      RWS 的目标一小横道（越久没扫到越暗）、TWS 的航迹小方块带速度线，选中的两边竖线「|—|」，STT 的方框 + 圆点 + 速度线；
--      顶上真机缩写的模式（RWS / TWS / STT / STT MEM / ACM VS…，中英一样：用户 11-27 定的）、左上扫描区「宽°x高°」（同战雷「40°x10°」）、右上量程、
--      屏里右上角扫描区在光标距离（量程一半）上盖住的海拔「上 / 下」（真机 B 显光标旁边那两个数）；自己打出去的主动雷达弹走数据链（见下）
--   ⑥ RCS（用户 11-28「引入一下rcs这个概念」）：量程按目标的 RCS 缩放（Radars.lua rcsOf / aspectK / rangeK：型号、外挂、方位）——隐身机近了才看得见；
--      敌我识别（「iff」）：友机也扫得到；带 IFF 的雷达（脉冲多普勒这一代）给它上面一道横线、不能选、不能锁、不建航迹，没有 IFF 的分不出来
--   G.radarSees(st, em) → 看得见吗、原因（off / gone / fov / range / notch / clutter）、机体方位°、俯仰°、距离（只看万向架：扫描区由波束管）
--   G.radarStep(st, dt)：每帧扫描、画屏；G.radarOff()；G.radarReset(st)：开飞（每架次）时雷达开着、量程最大、RWS、默认扫描方式、天线回中
--   G.airRadarContacts()：屏上的 { em, az, dist, locked }；G.radarHas(st, em)：在不在屏上；G.radarNext(st, cur)：下一个（TWS 在航迹里轮）；
--   G.radarStt(st, em) / G.radarUnlock(st)：进 / 出单目标跟踪；G.radarTrackOf(st, em)：TWS 航迹；G.radarTwsSel(st)：指定的航迹（Fly.lua 的雷达弹锁它）；
--   G.radarState()：模式、扫描区、波束、一帧几秒（测试；以后同步给服务器、座舱雷达页用）；G.radarAcmZone()：近战扫描区（WtFlight 画在平显上）
--   键（只给有雷达的固定翼，Fly.lua 让出了这些 Alt 组合键）：Alt+R 开关、Alt+Q 量程、Alt+E 模式、Alt+Z 扫描方式 / 近战子模式、
--   Alt+方向键 / Alt+滚轮 挪天线、Alt+C 回中、Alt+T 选目标（同 R）、Alt+F 锁定 / 解锁
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Radar = {}

function Radar.init(G)
  local me = Players.LocalPlayer
  local Map = G.Map or require(RS:WaitForChild("Map"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local RD = AD.Radars
  local V, RGB, U2, V2 = Vector3.new, Color3.fromRGB, UDim2, Vector2.new
  local clamp, rad, deg, atan2, asin = math.clamp, math.rad, math.deg, math.atan2, math.asin
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local function toast(k, ...) if G.toast then G.toast(T(k, ...), "info") end end
  local function ground(x, z) return AD.ground and AD.ground(Map, x, z) or Map.ground(x, z) end
  local BAR = (RD and RD.BAR) or 3.5
  local BEAM = (RD and RD.BEAM) or 2
  local MEM = (RD and RD.MEM) or 2
  local ACQ = (RD and RD.ACQ) or 13850
  local SLEW = (RD and RD.SLEW) or { az = 40, el = 25, wheel = 2 }
  local SIN_B, TAN_B = math.sin(rad(BEAM)), math.tan(rad(BEAM))

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

  -- 地平坐标（扫描区地平稳定）：航向的水平投影 f、往右 r；方位往右为正，俯仰按地平线
  local function hzBasis(cf)
    local lk = cf.LookVector
    local h = V(lk.X, 0, lk.Z)
    if h.Magnitude < 0.05 then   -- 机头快竖直了：航向按机背朝哪（往上拉时机背朝后、往下扎时朝前）
      local up = cf.UpVector
      h = V(up.X, 0, up.Z) * ((lk.Y > 0) and -1 or 1)
      if h.Magnitude < 1e-3 then h = V(0, 0, -1) end
    end
    local f = h.Unit
    return f, V(-f.Z, 0, f.X)
  end

  -- RCS（用户 11-28「引入一下rcs这个概念」，Radars.lua）：这架飞机迎头的 RCS（型号、科技树版本、外挂；Model / TreeKey / Load 属性变了才重算）
  --   × 方位（侧面大、尾后稍大），量程按 (σ / 5 m²)^(1/8) 缩放（雷达方程四次方根、游戏量程再按根号压缩）
  local rcsCache = setmetatable({}, { __mode = "k" })
  local function rcsClean(em)
    local id, tk, ld = em:GetAttribute("Model"), em:GetAttribute("TreeKey"), em:GetAttribute("Load")
    local c = rcsCache[em]
    if c and c.id == id and c.tk == tk and c.ld == ld then return c.s end
    local d = type(id) == "string" and AD.get(id) or nil
    local load = nil
    if d and type(ld) == "string" then
      load = {}
      local i = 0
      for w in string.gmatch(ld .. ",", "([^,]*),") do
        i += 1
        load[i] = (w ~= "") and w or false
      end
    end
    local sg = (RD and RD.rcsOf) and RD.rcsOf(d, tk, load, AD.W) or 5
    rcsCache[em] = { id = id, tk = tk, ld = ld, s = sg }
    return sg
  end
  local function rcsK(em, root, u)   -- u：雷达 → 目标的单位向量
    if not (RD and RD.rangeK) then return 1 end
    return RD.rangeK(rcsClean(em) * RD.aspectK(root.CFrame.LookVector:Dot(-u)))
  end
  -- 这一刻对它的量程倍数（Fly.lua 的锁定距离、测试）
  G.radarRcsK = function(em, st)
    st = st or G.fly
    local root = em and em.Parent and em:FindFirstChild("Root")
    if not st or not root then return 1 end
    local to = root.CFrame.Position - st.cf.Position
    if to.Magnitude < 1 then return 1 end
    return rcsK(em, root, to.Unit)
  end
  G.radarRcs = function(em) return em and rcsClean(em) or nil end   -- 测试用

  -- 看得见吗（只看万向架：扫描区由下面的波束管；单目标跟踪时天线跟着目标，也是这个）。far：这种扫描方式的量程倍数（窄扇区）
  local function sees(st, em, _, far)
    local rd = st and st.rd
    if not rd then return true end   -- 没有对空雷达的飞机：照旧（老规则，按导引头的视场）
    local root = em and em.Parent and em:FindFirstChild("Root")
    if not root then return false, "gone" end
    local p0, p = st.cf.Position, root.CFrame.Position
    local to = p - p0
    local dist = to.Magnitude
    if dist < 1 then return true, nil, 0, 0, dist end
    local u = to / dist
    local l = st.cf:VectorToObjectSpace(u)
    local az = deg(atan2(l.X, -l.Z))
    local el = deg(asin(clamp(l.Y, -1, 1)))
    local vT = velOf(em, p, os.clock())
    if math.abs(az) > rd.az or el > rd.elU or el < -rd.elD then return false, "fov", az, el, dist end
    -- 下视（视线比地平线低一个波束半宽以上）：脉冲多普勒的量程打折（ldK）；脉冲雷达贴地的目标埋在地杂波里
    local down = u.Y < -SIN_B
    local rng = rd.range * (far or 1) * rcsK(em, root, u)   -- 对这架的 RCS（隐身机近了才看得见）
    if down and rd.kind == "pd" then rng = rng * (rd.ldK or 1) end
    if dist > rng then return false, "range", az, el, dist end
    if rd.kind == "pd" then
      -- 脉冲多普勒：地面回波的多普勒频移 = 自己的速度在这个方向上的分量；目标的 = （它的 − 自己的）在视线上的分量。
      --   两个差的正好是目标相对地面的速度在视线上的分量——太小（侧着飞）就和地杂波混在一起被滤掉：置零
      if math.abs(vT:Dot(u)) < (rd.notch or 50) then return false, "notch", az, el, dist end
    elseif down then
      local tAlt = p.Y - math.max(ground(p.X, p.Z), 0)
      if tAlt < dist * TAN_B + 150 then return false, "clutter", az, el, dist end
    end
    return true, nil, az, el, dist
  end

  ---------------------------------------------------------------- 雷达屏（战雷式：右侧方形屏；用户 11-24 夜：「那个雷达屏在右侧」「战雷不同的雷达会有不同的扫描图」）
  --   照战雷 wiki（「Airborne radars」「机载雷达」）和真机 B 显：顶上工作模式、左上扫描区、两个上角方位窗口、右上量程、右下 0 km、左边俯仰刻度和天线俯仰；
  --   屏里竖的扫描波束来回扫；自己打出去的主动雷达弹（数据链，用户：「飞机本身会和自己的导弹形成数据链互相提供信息」）：弹一个小点，到目标一条线——
  --   导引头还没开机（靠你的雷达给目标位置）是虚线、预计命中点一个小圈；开机了实线（红）；数据链断了（你丢了锁、转开、雷达关了）只剩那个小圈
  local gui = Instance.new("ScreenGui")
  gui.Name = "AirRadar"   -- 别叫 Radar：UI.lua 的小地图框叫 Radar（tools/test/ia_ui_layout.luau、ia_radar.luau 按名字找它）
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local UIS = game:GetService("UserInputService")
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local TH = G.Theme   -- 统一外观（docs/style.md）：只用 HUD 绿 / WARN 琥珀 / BAD 红 / 白
  -- 屏底亮一点的半透明绿（照战雷 F/A-18 截图），线是 HUD 绿
  local GRN, LINE, FILL, BEAMC = TH.C.HUD, TH.C.HUD:Lerp(TH.C.INK, 0.12), TH.C.HUD:Lerp(TH.C.INK, 0.38), TH.C.HUD:Lerp(Color3.new(1, 1, 1), 0.3)
  local AMB, RED, WHITE = TH.C.WARN, TH.C.BAD, Color3.new(1, 1, 1)
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
    f.Rotation = deg(atan2(dy, dx))
    f.Visible = true
  end
  local W, H = mobile and 190 or 236, mobile and 180 or 224
  local scope = frame(gui, U2.fromOffset(W, H), mobile and U2.new(1, -16, 0.5, 60) or U2.new(1, -44, 0.5, 130), FILL, 0.45, V2(1, 0.5))   -- 右侧偏下：让开右上的圆形小地图和它下面的「被发现!」
  scope.Name = "RadarScope"
  scope.Active = true   -- 双击回中：点在屏上不算开炮
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
  -- 扫描区：两条竖线（扫描中心 ± 半宽）、底边下面一个小三角指扫描中心
  local zoneL = frame(scope, U2.new(0, 1.5, 1, 0), U2.fromScale(0, 0), GRN, 0.4, V2(0.5, 0))
  local zoneR = frame(scope, U2.new(0, 1.5, 1, 0), U2.fromScale(1, 0), GRN, 0.4, V2(0.5, 0))
  zoneL.Name, zoneR.Name = "ScanZoneL", "ScanZoneR"
  local ctrMark = label(scope, "ScanCtr", U2.new(0.5, 0, 1, 1), V2(0.5, 0), Enum.TextXAlignment.Center, 12)
  ctrMark.Size = U2.fromOffset(14, 10)
  ctrMark.Text = "^"
  local scan = frame(scope, U2.new(0, 7, 1, 0), U2.fromScale(0.5, 0), BEAMC, 0.55, V2(0.5, 0))
  scan.Name = "ScanLine"
  local blips = {}
  for i = 1, 14 do
    local b = frame(scope, U2.fromOffset(12, 3), U2.new(), WHITE, 0, V2(0.5, 0.5))
    b.Name = "Blip"
    b.Visible = false
    local l1 = frame(b, U2.fromOffset(2, 9), U2.new(0, -4, 0.5, 0), WHITE, 0, V2(0.5, 0.5))   -- 选中的：两边竖线「|—|」
    local l2 = frame(b, U2.fromOffset(2, 9), U2.new(1, 4, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    l1.Name, l2.Name = "SelL", "SelR"
    local iff = frame(b, U2.fromOffset(12, 2), U2.new(0.5, 0, 0, -4), WHITE, 0, V2(0.5, 1))   -- 敌我识别认出的友机：上面一道横线（同战雷）
    iff.Name = "Iff"
    iff.Visible = false
    blips[i] = { f = b, l1 = l1, l2 = l2, iff = iff }
  end
  -- 边扫边跟的航迹：小方块 + 速度线（往哪飞），指定的两边竖线
  local trk = {}
  for i = 1, 12 do
    local b = frame(scope, U2.fromOffset(8, 8), U2.new(), WHITE, 1, V2(0.5, 0.5))
    b.Name = "TwsTrack"
    b.Visible = false
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness = WHITE, 1.3
    s.Parent = b
    local l1 = frame(b, U2.fromOffset(2, 12), U2.new(0, -5, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    local l2 = frame(b, U2.fromOffset(2, 12), U2.new(1, 5, 0.5, 0), WHITE, 0, V2(0.5, 0.5))
    l1.Name, l2.Name = "SelL", "SelR"
    local vl = line(scope, WHITE, 1.2)
    vl.Name = "TwsVel"
    trk[i] = { f = b, l1 = l1, l2 = l2, vl = vl }
  end
  local lockBox = frame(scope, U2.fromOffset(14, 14), U2.new(), AMB, 1, V2(0.5, 0.5))
  lockBox.Name = "RadarLock"
  local ls = Instance.new("UIStroke")
  ls.Color, ls.Thickness = WHITE, 1.5
  ls.Parent = lockBox
  lockBox.Visible = false
  local lockDot = frame(scope, U2.fromOffset(5, 5), U2.new(), WHITE, 0, V2(0.5, 0.5))
  lockDot.Name = "TrackDot"
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = lockDot
  end
  lockDot.Visible = false
  local velLine = line(scope, WHITE, 1.4)
  velLine.Name = "TrackVel"
  -- 左边沿：扫描的俯仰范围（竖括号，一行一个小横道，正在扫的那行亮）、天线俯仰（白横道）
  local elSpan = frame(scope, U2.fromOffset(2, 10), U2.new(0, -6, 0.5, 0), GRN, 0.3, V2(0.5, 0))
  elSpan.Name = "ElSpan"
  local elBars = {}
  for i = 1, 10 do
    local b = frame(scope, U2.fromOffset(6, 2), U2.new(0, -6, 0.5, 0), GRN, 0.35, V2(0.5, 0.5))
    b.Name = "ElBar"
    b.Visible = false
    elBars[i] = b
  end
  local elMark = frame(scope, U2.fromOffset(9, 2), U2.new(0, -2, 0.5, 0), WHITE, 0, V2(1, 0.5))
  elMark.Name = "AntennaEl"
  -- 数据链：自己打出去的主动雷达弹
  local dl = {}
  for i = 1, 4 do
    local dot = frame(scope, U2.fromOffset(4, 4), U2.new(), WHITE, 0, V2(0.5, 0.5))
    dot.Name = "Missile"
    dot.Visible = false
    local ring = frame(scope, U2.fromOffset(10, 10), U2.new(), WHITE, 1, V2(0.5, 0.5))
    ring.Name = "IOG"
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = ring
    local rs = Instance.new("UIStroke")
    rs.Color, rs.Thickness = WHITE, 1.2
    rs.Parent = ring
    ring.Visible = false
    local segs = {}
    for k = 1, 8 do
      segs[k] = line(scope, WHITE, 1.2)
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
  local tElT = label(scope, "ElT", U2.new(0, -12, 0, 6), V2(1, 0.5), Enum.TextXAlignment.Right, 11)
  local tElB = label(scope, "ElB", U2.new(0, -12, 1, -6), V2(1, 0.5), Enum.TextXAlignment.Right, 11)
  local tAlt = label(scope, "AltCover", U2.new(1, -4, 0, 3), V2(1, 0), Enum.TextXAlignment.Right, 10)
  tAlt.Size = U2.fromOffset(130, 12)
  local tZero = label(scope, "RangeMin", U2.new(1, 0, 1, 4), V2(1, 0), Enum.TextXAlignment.Right)
  tZero.Text = "0 km"
  local tName = label(scope, "RadarName", U2.new(0, 0, 1, 4), V2(0, 0))
  tName.Size = U2.fromOffset(W - 50, 14)
  tName.TextSize = 11
  local tWarn = label(scope, "RadarWarn", U2.new(0.5, 0, 0.5, 0), V2(0.5, 0.5), Enum.TextXAlignment.Center, 14)
  tWarn.TextColor3 = AMB
  local tEmit = label(scope, "Emit", U2.new(0, 0, 1, 20), V2(0, 0), Enum.TextXAlignment.Left, 13)
  local tKeys = label(scope, "Keys", U2.new(0, 0, 1, 36), V2(0, 0), Enum.TextXAlignment.Left, 10)
  local tKeys2 = label(scope, "Keys2", U2.new(0, 0, 1, 49), V2(0, 0), Enum.TextXAlignment.Left, 10)
  for _, l in ipairs({ tKeys, tKeys2 }) do
    l.Size = U2.fromOffset(W + 80, 13)
    l.TextColor3 = RGB(200, 230, 205)
  end
  local function keysText()
    tKeys.Text = mobile and "" or T("rd.keys")
    tKeys2.Text = mobile and "" or T("rd.keys2")
  end
  keysText()

  ---------------------------------------------------------------- 状态

  local seen = setmetatable({}, { __mode = "k" })   -- 扫到过的：[em] = { t = 扫到的时刻, az（屏上的方位）, dist }
  local tracks = {}                                   -- 边扫边跟的航迹：[em] = { em, id, p, v, t（最后一次扫到）, t0, az, dist }
  local S = {}
  local SCALES = { 1, 0.5, 0.25 }
  local lastSt = nil
  local contacts = {}
  local function newS()
    S.on, S.scale, S.mode, S.scan, S.sub = true, 1, "rws", 1, 1
    S.ctrAz, S.ctrEl, S.slewAz, S.slewEl = 0, 0, 0, 0   -- 扫描中心（地平坐标）；近战「可挪」的扫描区挪了多少（机体坐标）
    S.zone, S.bx, S.bar, S.dir = nil, 0, 1, 1            -- 波束：在扫描区长的那边上的位置（相对中心）、第几行、往哪扫
    S.bAz, S.bEl = 0, 0                                  -- 波束（屏上画的）方位、俯仰
    S.frame0, S.frameT, S.frames = os.clock(), nil, 0    -- 这一帧从什么时候开始、上一帧扫了几秒、扫完几帧
    S.pingT = 0
  end
  newS()
  local function nTracks()
    local n = 0
    for _ in pairs(tracks) do n += 1 end
    return n
  end
  local function dropAll()
    table.clear(seen)
    table.clear(tracks)
    table.clear(contacts)
  end
  local function ping(m)
    local Rm = G.R
    if Rm and Rm.Drive then Rm.Drive:FireServer(m) end
  end
  -- 每架次重置（Fly.lua 开飞时调）：雷达开着、量程最大、RWS、默认扫描方式、天线回中，上一架的亮点、航迹清掉
  function G.radarReset(st)
    newS()
    dropAll()
    lastSt = st
    if st then st.rdLock, st.rdSel = nil, nil end
    keysText()   -- 换了语言下一架就换过来
  end
  -- 雷达扫得到的：天上所有的飞机（友机也在里面——敌我识别 IFF 才分得出来，用户 11-28「iff」）；friend[em] 记是不是友机
  local friend = setmetatable({}, { __mode = "k" })
  local function hostiles(st)
    local out = {}
    local f = workspace:FindFirstChild("Ents")
    if not f then return out end
    local myTeam = me:GetAttribute("Side")
    for _, em in ipairs(f:GetChildren()) do
      if em ~= st.em and em:GetAttribute("Kind") == "air" and not em:GetAttribute("Wreck") and (em:GetAttribute("Hp") or 1) > 0 then
        friend[em] = em:GetAttribute("Team") == myTeam
        table.insert(out, em)
      end
    end
    return out
  end
  -- 敌我识别认出来的友机（这部雷达带 IFF 才认得出；没有 IFF 的雷达友机跟敌机一样）：不能选、不能锁、不建航迹
  local function iffFriend(st, em) return st ~= nil and st.rd ~= nil and st.rd.iff == true and friend[em] == true end
  G.radarIffFriend = function(em) return iffFriend(lastSt, em) end
  -- 雷达关着：看不见（Fly.lua 的雷达弹锁不上、锁着的丢掉）
  G.radarSees = function(st, em, gimbal, far)
    if not S.on and st and st.rd then return false, "off" end
    return sees(st, em, gimbal, far)
  end
  G.radarOn = function() return S.on end

  -- 进 / 出单目标跟踪（STT）。Fly.lua 的 Alt+F 先查过「在屏上、看得见、锁定距离」；近战自动截获直接进
  local function enterStt(st, em)
    local root = em and em.Parent and em:FindFirstChild("Root")
    if not root then return false end
    local now = os.clock()
    local p = root.CFrame.Position
    st.rdLock = { em = em, id = em:GetAttribute("EntId"), t0 = now, seenT = now, p = p, v = velOf(em, p, now), dist = (p - st.cf.Position).Magnitude, mem = false }
    st.rdSel = em
    S.pingT = 0   -- 马上报一次 lockOn
    return true
  end
  function G.radarStt(st, em)
    if not st or st ~= lastSt or not st.rd or not S.on then return false end
    if iffFriend(st, em) then toast("rd.iffFriend") return false end   -- 敌我识别：友机不锁
    return enterStt(st, em)
  end
  function G.radarUnlock(st)
    if st then st.rdLock = nil end
  end

  -- 模式、扫描方式、天线
  local function setMode(st, rd, m)
    S.mode = m
    if st then st.rdLock = nil end   -- 换模式就断开单目标跟踪（真机也是）
    table.clear(tracks)
    if not RD.scanOk(rd, m, S.scan) then S.scan = (rd.twsScans and rd.twsScans[1]) or 1 end
    if m == "acm" then S.sub, S.slewAz, S.slewEl = 1, 0, 0 end
  end
  local function nextMode(st, rd)
    local ms = RD.modes(rd)
    local i = 1
    for j, m in ipairs(ms) do if m == S.mode then i = j end end
    local m = ms[i % #ms + 1]
    setMode(st, rd, m)
    if m == "acm" then
      local k = rd.acm[S.sub]
      toast("rd.modeT", RD.MODE_TAG.acm .. " " .. RD.tag(rd, k), T("rd.m.acm") .. " · " .. T("rd.acm." .. k))
    else
      toast("rd.modeT", RD.MODE_TAG[m], T("rd.m." .. m))
    end
  end
  local function nextScan(st, rd)
    if S.mode == "acm" then
      S.sub = S.sub % #rd.acm + 1
      S.slewAz, S.slewEl = 0, 0
      local k = rd.acm[S.sub]
      toast("rd.modeT", RD.MODE_TAG.acm .. " " .. RD.tag(rd, k), T("rd.acm." .. k))
      return
    end
    for _ = 1, #rd.scans do
      S.scan = S.scan % #rd.scans + 1
      if RD.scanOk(rd, S.mode, S.scan) then break end
    end
    local sc = rd.scans[S.scan]
    toast("rd.scanT", tostring(math.min(sc[1], rd.az)), tostring(sc[2]), string.format("%.1f", RD.frame(rd, S.scan)))
  end
  local function center(quiet)
    S.ctrAz, S.ctrEl, S.slewAz, S.slewEl = 0, 0, 0, 0
    if not quiet then toast("rd.center") end
  end
  local function altDown() return UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt) end
  local function mine(st) return st ~= nil and st == lastSt and G.fly == st and st.pilot and st.rd ~= nil end

  -- 键（战雷的默认键：Alt+R 开关、Alt+T 选目标、Alt+F 锁定；Alt+Q 量程、Alt+E 模式、Alt+Z 扫描方式、Alt+C 回中）。只在正开着这架有雷达的飞机时
  --   （下了飞机按 Alt+R 不再改 S.on）；Fly.lua 按住 Alt 时把这些键让出来（不再串成 R 换目标、T 迎角限制、Q / E 方向舵、F 发导弹、C 自由视角）
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not mine(lastSt) or not altDown() then return end
    local st, rd, k = lastSt, lastSt.rd, io.KeyCode
    if k == Enum.KeyCode.R then
      S.on = not S.on
      if not S.on then
        st.rdLock = nil
        dropAll()
      end
      toast(S.on and "wt.radarOn" or "wt.radarOff")
    elseif k == Enum.KeyCode.Q then
      S.scale = S.scale % #SCALES + 1
      local sc = rd.scans[S.scan] or rd.scans[1]
      toast("wt.radarRange", string.format("%.0f", rd.range * (sc.far or 1) * SCALES[S.scale] / AD.M / 1000))
    elseif k == Enum.KeyCode.E then
      nextMode(st, rd)
    elseif k == Enum.KeyCode.Z then
      nextScan(st, rd)
    elseif k == Enum.KeyCode.C then
      center()
    elseif k == Enum.KeyCode.T then
      if G.flyNextTarget then G.flyNextTarget(true) end   -- true：只在雷达屏上选（不管选的什么弹）
    elseif k == Enum.KeyCode.F then
      if G.flyRadarLock then G.flyRadarLock() end
    end
  end)
  -- Alt+滚轮（Fly.lua 交过来，不再动油门）：天线俯仰一格 SLEW.wheel 度（像真机油门杆上的天线俯仰轮）；近战「可挪」挪它的扫描区
  function G.radarWheel(z)
    if not mine(lastSt) then return end
    local d = (z > 0 and 1 or (z < 0 and -1 or 0)) * SLEW.wheel
    if S.mode == "acm" then S.slewEl += d else S.ctrEl += d end
  end
  -- 双击雷达屏：天线回中（手机上第 7 步还有拖屏）
  local lastClick = -9
  scope.InputBegan:Connect(function(io)
    local ty = io.UserInputType
    if ty ~= Enum.UserInputType.MouseButton1 and ty ~= Enum.UserInputType.Touch then return end
    if not mine(lastSt) then return end
    local now = os.clock()
    if now - lastClick < 0.4 then
      center()
      lastClick = -9
    else
      lastClick = now
    end
  end)

  -- 名字别跟 Hud.lua 的 G.radarContacts（小地图上的人和车，Coach.lua 的队友标记用）撞：原来这里覆盖了它，队友标记一直拿不到数据
  function G.airRadarContacts() return contacts end   -- 航向罗盘上的小三角（WtFlight.lua）、选目标
  -- 在不在雷达屏上（扫到过、还没暗掉；边扫边跟的航迹；单目标跟踪着的）
  function G.radarHas(st, em)
    if not em or not S.on or st == nil or st ~= lastSt or st.rd == nil then return false end
    return seen[em] ~= nil or tracks[em] ~= nil or (st.rdLock ~= nil and st.rdLock.em == em)
  end
  function G.radarTrackOf(st, em)
    if not em or not S.on or st ~= lastSt or S.mode ~= "tws" then return nil end
    return tracks[em]
  end
  -- 边扫边跟里指定的那条航迹（Fly.lua：对它打主动雷达弹不用 STT）
  function G.radarTwsSel(st)
    if not st or st ~= lastSt or not S.on or S.mode ~= "tws" or st.rdLock then return nil end
    local em = st.rdSel
    return (em and tracks[em]) and em or nil
  end
  -- 雷达屏上的下一个目标（从左往右轮；TWS 只在航迹里轮；cur 不在屏上时挑离屏幕正中最近的）；屏上没有返回 nil
  function G.radarNext(st, cur)
    if not st or st ~= lastSt or not S.on then return nil end
    local src = (S.mode == "tws" and next(tracks) ~= nil) and tracks or seen
    local list = {}
    for em, r in pairs(src) do
      if em.Parent and not iffFriend(st, em) then table.insert(list, { em = em, az = r.az or 0, dist = r.dist or 0 }) end   -- 敌我识别认出的友机不轮到
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) if a.az ~= b.az then return a.az < b.az end return a.dist < b.dist end)
    local ci = nil
    for i, c in ipairs(list) do if c.em == cur then ci = i end end
    if ci then return list[ci % #list + 1].em end
    local best, bs = nil, math.huge
    for _, c in ipairs(list) do
      local s2 = math.abs(c.az - S.ctrAz) + c.dist / 4000
      if s2 < bs then best, bs = c.em, s2 end
    end
    return best
  end

  ---------------------------------------------------------------- 扫描区、波束

  -- 这一帧的扫描区 Z：搜索（RWS / TWS）按地平坐标、长的那边是方位，一行一个俯仰；近战按机体坐标，竖扫长的那边是俯仰（一列一个方位），
  --   瞄准线、头盔波束不动（fixed）。lines：每行（列）在短的那边上的角度；c / half：长的那边的中心、半长；tol：离这一行多近算扫到
  local Z = { lines = {} }
  local function zoneOf(st, rd)
    local lines = Z.lines
    table.clear(lines)
    Z.far, Z.acq, Z.fixed, Z.head = 1, nil, false, false
    if S.mode == "acm" then
      local k = rd.acm[S.sub] or rd.acm[1]
      local g = RD.acmGeo(rd, k)
      Z.key, Z.tag, Z.body = "acm" .. S.sub, k, true
      local A, h = g.az, (g.el1 - g.el0) / 2
      local cAz, cEl = 0, (g.el0 + g.el1) / 2
      if g.slew then   -- 可挪：Alt+方向键 / 滚轮挪（夹在万向架里）
        S.slewAz = clamp(S.slewAz, -math.max(0, rd.az - A), math.max(0, rd.az - A))
        S.slewEl = clamp(S.slewEl, -rd.elD - g.el0, rd.elU - g.el1)
        cAz, cEl = S.slewAz, cEl + S.slewEl
      end
      if g.head then   -- 头盔：跟着镜头看的方向（出了万向架就看不见，sees 管）
        local cam = workspace.CurrentCamera
        local l = st.cf:VectorToObjectSpace(cam and cam.CFrame.LookVector or st.cf.LookVector)
        cAz, cEl = deg(atan2(l.X, -l.Z)), deg(asin(clamp(l.Y, -1, 1)))
        Z.head = true
      end
      Z.cAz, Z.cEl, Z.A, Z.H = cAz, cEl, A, h
      Z.acq = math.min(ACQ, rd.range)
      if A <= BEAM + 0.5 and h <= BEAM + 0.5 then
        Z.fixed, Z.long, Z.c, Z.half, Z.tol = true, "az", cAz, 0, 0
        lines[1] = cEl
      elseif h > A then   -- 竖扫：波束上下扫、一列一列往右挪
        local n = math.max(1, math.ceil(2 * A / BAR))
        for c = 1, n do lines[c] = cAz - A + (2 * A / n) * (c - 0.5) end
        Z.long, Z.c, Z.half, Z.tol = "el", cEl, h, A / n + 0.5
      else
        local n = math.max(1, math.ceil(2 * h / BAR))
        for b = 1, n do lines[b] = cEl + h - (2 * h / n) * (b - 0.5) end
        Z.long, Z.c, Z.half, Z.tol = "az", cAz, A, h / n + 0.5
      end
    else
      local sc = rd.scans[S.scan] or rd.scans[1]
      local w, bars = math.min(sc[1], rd.az), sc[2]
      local hh = bars * BAR / 2
      S.ctrAz = clamp(S.ctrAz, -math.max(0, rd.az - w), math.max(0, rd.az - w))
      S.ctrEl = clamp(S.ctrEl, -rd.elD + hh, rd.elU - hh)
      Z.key, Z.tag, Z.body = S.mode .. S.scan, nil, false
      Z.far = sc.far or 1
      Z.cAz, Z.cEl, Z.A, Z.H = S.ctrAz, S.ctrEl, w, hh
      for b = 1, bars do lines[b] = S.ctrEl + ((bars + 1) / 2 - b) * BAR end   -- 第 1 行在最上面
      Z.long, Z.c, Z.half, Z.tol = "az", S.ctrAz, w, BAR / 2 + 0.5
    end
    return Z
  end
  -- 波束往前扫 rate·dt 度：一行扫到头掉头、换下一行，最后一行扫完回到第一行（一帧）；每扫过一段调 onSeg(第几行, 从, 到)（相对中心）
  local function sweep(rate, dt, half, n, onSeg)
    local go = rate * dt
    local guard = 0
    while go > 1e-6 and guard < 40 do
      guard += 1
      local edge = (S.dir > 0) and half or -half
      local room = math.abs(edge - S.bx)
      local step = math.min(go, room)
      local x0 = S.bx
      S.bx = S.bx + S.dir * step
      onSeg(S.bar, x0, S.bx)
      go -= step
      if step >= room - 1e-9 then
        S.bx, S.dir = edge, -S.dir
        S.bar += 1
        if S.bar > n then
          S.bar = 1
          local now = os.clock()
          S.frameT, S.frame0, S.frames = now - S.frame0, now, S.frames + 1
        end
      end
    end
  end

  -- 每个敌机这一帧的角度（复用的小表）：地平方位 / 俯仰（hAz、hEl）、机体方位 / 俯仰（bAz、bEl）、距离
  local tg = {}
  local function angles(t, cf, f, r, p)
    local to = p - cf.Position
    local d = to.Magnitude
    local u = (d > 1e-3) and (to / d) or cf.LookVector
    t.dist = d
    t.hAz, t.hEl = deg(atan2(u:Dot(r), u:Dot(f))), deg(asin(clamp(u.Y, -1, 1)))
    local l = cf:VectorToObjectSpace(u)
    t.bAz, t.bEl = deg(atan2(l.X, -l.Z)), deg(asin(clamp(l.Y, -1, 1)))
    return t
  end
  local tmpA = {}

  ---------------------------------------------------------------- 每帧

  function G.radarStep(st, dt)
    lastSt = st
    local rd = st and st.rd
    if not rd or not st.pilot or st.uav then
      gui.Enabled = false
      table.clear(contacts)
      return
    end
    gui.Enabled = not st.eo and not st.bsight
    local now = os.clock()
    local cf = st.cf
    local p0 = cf.Position
    local f, r = hzBasis(cf)
    -- 按住 Alt 的方向键：挪扫描中心（近战「可挪」挪它的扫描区）
    if G.fly == st and altDown() then
      local dx = (UIS:IsKeyDown(Enum.KeyCode.Right) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Left) and 1 or 0)
      local dy = (UIS:IsKeyDown(Enum.KeyCode.Up) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Down) and 1 or 0)
      if S.mode == "acm" then
        S.slewAz += dx * SLEW.az * dt
        S.slewEl += dy * SLEW.el * dt
      else
        S.ctrAz += dx * SLEW.az * dt
        S.ctrEl += dy * SLEW.el * dt
      end
    end
    local z = zoneOf(st, rd)
    if z.key ~= S.zone then   -- 换了模式 / 扫描方式：从第一行的头上开始扫一帧
      S.zone, S.bar, S.dir, S.bx = z.key, 1, 1, -z.half
      S.frame0 = now
    end
    if S.bar > #z.lines then S.bar = 1 end
    S.bx = clamp(S.bx, -z.half, z.half)
    local range = rd.range * z.far * SCALES[S.scale]   -- 屏上的量程（窄扇区的 far 一起放大）
    local fade = (S.mode == "acm") and 2.6 or RD.fade(rd, S.scan)

    ---- 单目标跟踪：天线跟着目标；看不见了先按记忆外推 MEM 秒
    local lk = st.rdLock
    if lk and (not S.on or not lk.em.Parent or lk.em:GetAttribute("Wreck") or (lk.em:GetAttribute("Hp") or 1) <= 0) then
      st.rdLock, lk = nil, nil
    end
    if lk then
      local ok, why, _, _, dist = sees(st, lk.em, true, z.far)
      local root = lk.em:FindFirstChild("Root")
      if ok and root then
        lk.p = root.CFrame.Position
        lk.v = velOf(lk.em, lk.p, now)
        lk.dist, lk.seenT, lk.mem, lk.why = dist, now, false, nil
        -- 跟踪着的也算「屏上有」：解锁 / 丢锁以后它照旧在屏上（按最后的位置慢慢暗掉），马上能再锁
        local sr = seen[lk.em]
        if not sr then
          sr = {}
          seen[lk.em] = sr
        end
        local a = angles(tmpA, cf, f, r, lk.p)
        sr.t, sr.az, sr.dist = now, z.body and a.bAz or a.hAz, dist
      else
        lk.mem, lk.why = true, why
        lk.p = lk.p + (lk.v or V()) * dt
        lk.dist = (lk.p - p0).Magnitude
        if now - lk.seenT > MEM then
          st.rdLock, lk = nil, nil
          toast((why == "notch") and "air.radarLostNotch" or "air.radarLost")
        end
      end
    end
    if lk and not lk.mem and now >= S.pingT then   -- 跟踪着：半秒报一次（服务器给飞出去的雷达弹走数据链、对方告警「被雷达照射 / 锁定」）
      S.pingT = now + 0.5
      ping({ op = "lockOn", tgt = lk.id, full = now - lk.t0 >= 1 })
    end

    ---- 搜索 / 近战：波束扫过扫描区
    local list = (S.on and not lk) and hostiles(st) or {}
    local n = 0
    for _, em in ipairs(list) do
      local root = em:FindFirstChild("Root")
      if root then
        local p = root.CFrame.Position
        velOf(em, p, now)   -- 每帧都喂速度平滑（扫到时按最新的速度判置零）
        n += 1
        local t = tg[n] or {}
        tg[n] = t
        angles(t, cf, f, r, p)
        t.em, t.p, t.hit = em, p, false
      end
    end
    local frameS = RD.frame(rd, S.scan)
    local acqd = false
    local function detect(t)
      if t.hit or acqd then return end
      t.hit = true
      if not sees(st, t.em, nil, z.far) then return end
      local fr = iffFriend(st, t.em)   -- 敌我识别认出的友机：屏上标出来，不自动截获、不建航迹
      if z.acq then   -- 近战：近处第一个扫到的自动进单目标跟踪
        if not fr and t.dist <= z.acq and enterStt(st, t.em) then acqd = true end
        return
      end
      if t.dist > range then return end
      local az = t.hAz
      local sr = seen[t.em]
      if not sr then
        sr = {}
        seen[t.em] = sr
      end
      sr.t, sr.az, sr.dist, sr.friend = now, az, t.dist, fr
      if S.mode == "tws" and not fr then   -- 边扫边跟：建 / 更新航迹（批数满了只当亮点）
        local tr = tracks[t.em]
        if not tr and nTracks() < (rd.tws or 0) then
          tr = { em = t.em, id = t.em:GetAttribute("EntId"), t0 = now }
          tracks[t.em] = tr
        end
        if tr then
          tr.p, tr.v, tr.t = t.p, velOf(t.em, t.p, now), now
          if st.rdSel == t.em then ping({ op = "lockOn", tgt = tr.id, tws = frameS }) end   -- 指定的航迹更新了：数据链（对方告警器不报锁定）
        end
      end
    end
    if S.on and not lk then
      if z.fixed then
        for i = 1, n do
          local t = tg[i]
          local ta, te = z.body and t.bAz or t.hAz, z.body and t.bEl or t.hEl
          if math.abs(ta - z.cAz) <= math.max(z.A, BEAM) and math.abs(te - z.cEl) <= math.max(z.H, BEAM) then detect(t) end
        end
      else
        local vert = z.long == "el"
        sweep(rd.rate, dt, z.half, #z.lines, function(k, x0, x1)
          local lo, hi = math.min(x0, x1) - BEAM, math.max(x0, x1) + BEAM
          local ln = z.lines[k] or 0
          for i = 1, n do
            local t = tg[i]
            if not t.hit then
              local ta, te = z.body and t.bAz or t.hAz, z.body and t.bEl or t.hEl
              local tl, ts = ta - z.c, te
              if vert then tl, ts = te - z.c, ta end
              if tl >= lo and tl <= hi and math.abs(ts - ln) <= z.tol then detect(t) end
            end
          end
        end)
      end
    end
    -- 波束在哪（屏上画）：跟踪着在目标上，不然在扫描区里
    lk = st.rdLock
    if lk then
      local a = angles(tmpA, cf, f, r, lk.p)
      if z.body then S.bAz, S.bEl = a.bAz, a.bEl else S.bAz, S.bEl = a.hAz, a.hEl end
    elseif z.fixed then
      S.bAz, S.bEl = z.cAz, z.cEl
    elseif z.long == "el" then
      S.bAz, S.bEl = z.lines[S.bar] or z.cAz, z.c + S.bx
    else
      S.bAz, S.bEl = z.c + S.bx, z.lines[S.bar] or z.cEl
    end
    -- 航迹：两帧多没扫到就丢；没扫到的时候按速度外推
    local life = 2 * frameS + 0.5
    for em, tr in pairs(tracks) do
      if not em.Parent or now - tr.t > life or em:GetAttribute("Wreck") then
        tracks[em] = nil
      else
        local a = angles(tmpA, cf, f, r, tr.p + tr.v * (now - tr.t))
        tr.az, tr.dist = a.hAz, a.dist
      end
    end

    ---- 画
    -- 横轴铺满方位万向架（战雷：两个上角写万向架两头）；扫描区一直在万向架里，不用平移（头盔跟着镜头看出去的，夹在两边）
    local winH = math.max(rd.az or 60, 10)
    local winC = 0
    local function xRaw(az) return 0.5 + (az - winC) / (2 * winH) end
    local function xOf(az) return clamp(xRaw(az), 0.02, 0.98) end
    local function yOf(dist) return clamp(1 - dist / range, 0.02, 0.98) end
    local elSpanD = math.max(rd.elU + rd.elD, 1)
    local function elY(e) return clamp((rd.elU - e) / elSpanD, 0, 1) end
    local function dispAz(p)   -- 这一点在屏上的方位：近战按机体，别的按地平
      local a = angles(tmpA, cf, f, r, p)
      return z.body and a.bAz or a.hAz, a.dist
    end
    scan.Visible = S.on
    scan.Position = U2.fromScale(clamp(xRaw(S.bAz), 0, 1), 0)
    scan.BackgroundColor3 = (lk and not lk.mem) and AMB or BEAMC
    zoneL.Visible, zoneR.Visible, ctrMark.Visible = S.on and not z.fixed, S.on and not z.fixed, S.on
    zoneL.Position = U2.fromScale(clamp(xRaw(z.cAz - z.A), 0, 1), 0)
    zoneR.Position = U2.fromScale(clamp(xRaw(z.cAz + z.A), 0, 1), 0)
    ctrMark.Position = U2.new(clamp(xRaw(z.cAz), 0, 1), 0, 1, 1)
    -- 左边沿：扫描的俯仰范围、每一行、天线俯仰
    local eTop, eBot = z.cEl + z.H, z.cEl - z.H
    elSpan.Visible = S.on
    elSpan.Position = U2.new(0, -6, elY(eTop), 0)
    elSpan.Size = U2.new(0, 2, elY(eBot) - elY(eTop), 0)
    local nb = (z.long == "az") and #z.lines or 0
    for i, b in ipairs(elBars) do
      if S.on and i <= nb then
        b.Position = U2.new(0, -6, elY(z.lines[i]), 0)
        local cur = (i == S.bar) and not lk
        b.BackgroundColor3, b.BackgroundTransparency = cur and WHITE or GRN, cur and 0 or 0.35
        b.Visible = true
      else
        b.Visible = false
      end
    end
    elMark.Visible = S.on
    elMark.Position = U2.new(0, -2, elY(S.bEl), 0)
    -- 目标
    table.clear(contacts)
    local nBl, nTr = 0, 0
    for em, sr in pairs(seen) do
      local age = now - sr.t
      if age > fade or not em.Parent or not S.on then
        seen[em] = nil
        if st.rdSel == em and not tracks[em] and not (lk and lk.em == em) then st.rdSel = nil end   -- 选中的那个暗掉了：不再选着它（Fly.lua 锁不了屏上没有的）
      elseif not tracks[em] and not (lk and lk.em == em) then
        table.insert(contacts, { em = em, az = sr.az, dist = sr.dist, locked = false, friend = sr.friend == true })
        if nBl < #blips then
          nBl += 1
          local b = blips[nBl]
          b.f.Position = U2.fromScale(xOf(sr.az), yOf(sr.dist))
          b.f.BackgroundTransparency = clamp(age / fade, 0, 0.85)
          local sel = st.rdSel == em or (st.lock ~= nil and st.lock.em == em)   -- 选中的（R / Alt+T）、别的弹锁着的
          b.l1.Visible, b.l2.Visible = sel, sel
          b.iff.Visible = sr.friend == true
          b.iff.BackgroundTransparency = b.f.BackgroundTransparency
          b.f.Visible = true
        end
      end
    end
    for i = nBl + 1, #blips do blips[i].f.Visible = false end
    for em, tr in pairs(tracks) do
      if S.on and not (lk and lk.em == em) then
        table.insert(contacts, { em = em, az = tr.az, dist = tr.dist, locked = false })
        if nTr < #trk then
          nTr += 1
          local q = trk[nTr]
          local tx, ty = xOf(tr.az), yOf(tr.dist)
          q.f.Position, q.f.Visible = U2.fromScale(tx, ty), true
          local sel = st.rdSel == em
          q.l1.Visible, q.l2.Visible = sel, sel
          local hv = V(tr.v.X, 0, tr.v.Z)
          if hv.Magnitude > 5 then   -- 速度线：横是往左右、竖是往前后（往前飞在屏上往上）
            local u = hv.Unit
            local px, py = tx * W, ty * H
            setLine(q.vl, px, py, px + u:Dot(r) * 14, py - u:Dot(f) * 14)
          else
            q.vl.Visible = false
          end
        end
      end
    end
    for i = nTr + 1, #trk do
      trk[i].f.Visible = false
      trk[i].vl.Visible = false
    end
    -- 跟踪着的目标：方框 + 圆点 + 速度线（目标往哪飞）
    local showLock = lk ~= nil and S.on
    lockBox.Visible, lockDot.Visible = showLock, showLock
    if showLock then
      local laz, ldist = dispAz(lk.p)
      table.insert(contacts, { em = lk.em, az = laz, dist = ldist, locked = true })
      local lx, ly = xOf(laz), yOf(ldist)
      lockBox.Position, lockDot.Position = U2.fromScale(lx, ly), U2.fromScale(lx, ly)
      ls.Color = lk.mem and AMB or WHITE
      local vT = lk.v or V()
      local hv = V(vT.X, 0, vT.Z)
      if hv.Magnitude > 5 then
        local u = hv.Unit
        local px, py = lx * W, ly * H
        setLine(velLine, px, py, px + u:Dot(r) * 22, py - u:Dot(f) * 22)
      else
        velLine.Visible = false
      end
    else
      velLine.Visible = false
    end
    -- 数据链：自己打出去的主动雷达弹
    local fl = G.flyingShots or {}
    local di = 0
    local ents = workspace:FindFirstChild("Ents")
    for _, fs in pairs(fl) do
      if di >= #dl then break end
      local aw = fs.aw
      if fs.my and aw and aw.seeker == "radar" and aw.act and fs.p then
        di += 1
        local D = dl[di]
        local mAz, mDist = dispAz(fs.p)
        local mx, my = xOf(mAz) * W, yOf(mDist) * H
        D.dot.Position, D.dot.Visible = U2.fromOffset(mx, my), true
        -- 目标在屏上的位置（数据链给的）；断了就是最后估的命中点
        local tx, ty = nil, nil
        local tem = nil
        if fs.tg and ents then
          for _, em in ipairs(ents:GetChildren()) do
            if em:GetAttribute("EntId") == fs.tg then tem = em break end
          end
        end
        local troot = tem and tem:FindFirstChild("Root")
        if troot and not fs.lost then
          local taz, tdist = dispAz(troot.CFrame.Position)
          tx, ty = xOf(taz) * W, yOf(tdist) * H
          fs.iog = { tx, ty }
        elseif fs.iog then
          tx, ty = fs.iog[1], fs.iog[2]
        end
        local linkOk = not fs.lost and S.on and tem ~= nil and ((lk ~= nil and lk.em == tem and not lk.mem) or tracks[tem] ~= nil)
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
              sg.BackgroundColor3 = fs.act and RED or WHITE
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
    -- 字：模式（真机缩写，中英一样）、扫描区、量程、方位窗口、俯仰万向架、海拔覆盖
    local tag
    if not S.on then tag = "OFF"
    elseif lk then tag = RD.MODE_TAG.stt .. (lk.mem and (" " .. RD.MODE_TAG.mem) or "")
    elseif S.mode == "acm" then tag = RD.MODE_TAG.acm .. " " .. RD.tag(rd, z.tag)
    else tag = RD.MODE_TAG[S.mode] or "RWS" end
    tMode.Text = tag
    tZone.Text = string.format("%d°x%d°", math.floor(2 * z.A + 0.5), math.floor(2 * z.H + 0.5))   -- 战雷：扫描区宽 × 高
    tRange.Text = string.format("%.0f km", range / AD.M / 1000)
    tAzL.Text, tAzR.Text = string.format("%d°", math.floor(winC - winH + 0.5)), string.format("%d°", math.floor(winC + winH + 0.5))
    tElT.Text, tElB.Text = string.format("%d°", rd.elU), string.format("-%d°", rd.elD)   -- 俯仰万向架两头（战雷「60°」「-45°」）
    if S.on and S.mode ~= "acm" and not lk then
      local R0 = range / 2
      local h0 = p0.Y
      local hi = (h0 + R0 * math.sin(rad(eTop))) / AD.M / 1000
      local lo = (h0 + R0 * math.sin(rad(eBot))) / AD.M / 1000
      tAlt.Text = T("rd.alt", string.format("%.1f", hi), string.format("%.1f", lo))
    else
      tAlt.Text = ""
    end
    tName.Text = ((G.lang == "en") and rd.shortEn) or rd.short or rd.name or ""   -- 屏底只写短名（整名放在 186 像素宽的标签里会超出）
    tEmit.Text = S.on and "((o))" or "( . )"
    tEmit.TextColor3 = S.on and GRN or RGB(120, 140, 125)
    tWarn.Text = (lk and lk.mem and lk.why == "notch") and T("air.radarNotch") or ((lk and lk.mem and lk.why == "clutter") and T("air.radarClutter") or "")
    st.radarAz, st.radarStt = S.bAz, lk ~= nil and not lk.mem   -- 测试用
  end

  -- 雷达现在的样子（测试；第 6 步同步给服务器、第 8 步座舱雷达页用）
  local RST = {}
  function G.radarState()
    local st = lastSt
    local lk = st and st.rdLock
    RST.on, RST.mode, RST.scan, RST.sub, RST.scale = S.on, S.mode, S.scan, S.sub, S.scale
    RST.ctrAz, RST.ctrEl, RST.slewAz, RST.slewEl = S.ctrAz, S.ctrEl, S.slewAz, S.slewEl
    RST.w, RST.h, RST.bars, RST.zAz, RST.zEl = Z.A, Z.H, #Z.lines, Z.cAz, Z.cEl
    RST.bAz, RST.bEl, RST.bar, RST.dir = S.bAz, S.bEl, S.bar, S.dir
    RST.frameT, RST.frames = S.frameT, S.frames
    RST.stt, RST.mem = lk ~= nil and not lk.mem, lk ~= nil and lk.mem == true
    RST.tracks = nTracks()
    RST.acm = (S.mode == "acm") and Z.tag or nil
    return RST
  end
  -- 近战扫描区（机体坐标，WtFlight 画在平显上）：没开近战、跟踪着了、雷达关着返回 nil
  local ACMZ = {}
  function G.radarAcmZone()
    local st = lastSt
    if not S.on or S.mode ~= "acm" or not st or G.fly ~= st or st.rdLock or not st.rd then return nil end
    ACMZ.cAz, ACMZ.cEl, ACMZ.A, ACMZ.H = Z.cAz, Z.cEl, Z.A, Z.H
    ACMZ.fixed, ACMZ.vert, ACMZ.head, ACMZ.tag = Z.fixed, Z.long == "el", Z.head, Z.tag
    ACMZ.beam = BEAM
    return ACMZ
  end

  function G.radarOff()
    gui.Enabled = false
    dropAll()
  end
  G.radarGui = gui   -- 测试用
end

return Radar
