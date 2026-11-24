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
  local function velOf(em, p, now)
    local t = track[em]
    if not t then
      track[em] = { p = p, t = now, v = V() }
      return V()
    end
    if now - t.t > 1e-3 then
      local raw = (p - t.p) / (now - t.t)
      if raw.Magnitude < 2000 then t.v = t.v:Lerp(raw, math.min(1, (now - t.t) * 6)) end
      t.p, t.t = p, now
    end
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

  ---------------------------------------------------------------- 雷达屏

  local gui = Instance.new("ScreenGui")
  gui.Name = "Radar"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 5
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local GRN, DIM, AMB = RGB(110, 255, 150), RGB(60, 150, 90), RGB(255, 200, 80)
  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or U2.new()
    f.AnchorPoint = anchor or V2(0, 0)
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col, tr, 0
    f.Parent = parent
    return f
  end
  local function label(parent, name, pos, anchor, align)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Size, l.Position, l.AnchorPoint = U2.fromOffset(120, 14), pos, anchor or V2(0, 0)
    l.Font, l.TextSize, l.TextColor3 = Enum.Font.Code, 12, GRN
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.5, RGB(0, 20, 8)
    l.Text = ""
    l.Parent = parent
    return l
  end
  local W, H = 200, 190
  local scope = frame(gui, U2.fromOffset(W, H), U2.new(0, 18, 0.5, 30), RGB(4, 14, 8), 0.35, V2(0, 0.5))
  scope.Name = "RadarScope"
  local st0 = Instance.new("UIStroke")
  st0.Color, st0.Thickness, st0.Transparency = GRN, 1, 0.35
  st0.Parent = scope
  -- 网格：方位 0°、±一半；距离四分之一一格
  for _, fx in ipairs({ 0.25, 0.5, 0.75 }) do
    local v = frame(scope, U2.new(0, 1, 1, 0), U2.fromScale(fx, 0), DIM, (fx == 0.5) and 0.35 or 0.65)
    v.Name = "Grid"
    local h = frame(scope, U2.new(1, 0, 0, 1), U2.fromScale(0, fx), DIM, 0.65)
    h.Name = "Grid"
  end
  local scan = frame(scope, U2.new(0, 2, 1, 0), U2.fromScale(0.5, 0), GRN, 0.25, V2(0.5, 0))
  scan.Name = "ScanLine"
  local blips = {}
  for i = 1, 14 do
    local b = frame(scope, U2.fromOffset(9, 3), U2.new(), GRN, 0, V2(0.5, 0.5))
    b.Name = "Blip"
    b.Visible = false
    blips[i] = b
  end
  local lockBox = frame(scope, U2.fromOffset(16, 12), U2.new(), AMB, 1, V2(0.5, 0.5))
  lockBox.Name = "RadarLock"
  local ls = Instance.new("UIStroke")
  ls.Color, ls.Thickness = AMB, 1.5
  ls.Parent = lockBox
  lockBox.Visible = false
  local tName = label(scope, "RadarName", U2.fromOffset(4, -16))
  tName.Size = U2.fromOffset(W - 50, 14)
  local tMode = label(scope, "RadarMode", U2.new(1, -4, 0, -16), V2(1, 0), Enum.TextXAlignment.Right)
  local tRange = label(scope, "RadarRange", U2.new(0, 4, 1, 2))
  local tWarn = label(scope, "RadarWarn", U2.new(1, -4, 1, 2), V2(1, 0), Enum.TextXAlignment.Right)
  tWarn.TextColor3 = AMB

  ---------------------------------------------------------------- 每帧

  local seen = setmetatable({}, { __mode = "k" })   -- [em] = { t = 扫到的时刻, az, dist }
  local S = { az = 0, dir = 1 }
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

  function G.radarStep(st, dt, lockEm)
    local rd = st and st.d and st.d.radar
    if not rd or not st.pilot or st.uav then
      gui.Enabled = false
      return
    end
    gui.Enabled = true
    local now = os.clock()
    -- 扫描线：锁着就停在目标上（STT），不然在方位里来回扫（一来一回两秒多）
    local stt = false
    local lockOk, lockWhy, lockAz, _, lockDist = false, nil, nil, nil, nil
    if lockEm then
      lockOk, lockWhy, lockAz, _, lockDist = sees(st, lockEm)
      if lockAz then stt = true end
    end
    if stt and lockOk then
      S.az = clamp(lockAz, -rd.az, rd.az)
    else
      S.az = S.az + S.dir * rd.az * 2 / 1.1 * dt
      if S.az > rd.az then S.az, S.dir = rd.az, -1 elseif S.az < -rd.az then S.az, S.dir = -rd.az, 1 end
    end
    -- 扫到的（扫描线扫过它的方位附近）、看得见的：记下来；没扫到的照旧显示一会儿再暗下去
    local list = hostiles(st)
    for _, em in ipairs(list) do
      local ok, _, az, _, dist = sees(st, em)
      if ok and az and (math.abs(az - S.az) < 7 or em == lockEm) then
        seen[em] = { t = now, az = az, dist = dist }
      end
    end
    -- 画
    local function xOf(az) return clamp(0.5 + az / (2 * rd.az), 0.02, 0.98) end
    local function yOf(dist) return clamp(1 - dist / rd.range, 0.02, 0.98) end
    scan.Position = U2.fromScale(xOf(S.az), 0)
    scan.BackgroundColor3 = (stt and lockOk) and AMB or GRN
    local n = 0
    for em, r in pairs(seen) do
      local age = now - r.t
      if age > 2.6 or not em.Parent then
        seen[em] = nil
      elseif n < #blips then
        n += 1
        local b = blips[n]
        b.Position = U2.fromScale(xOf(r.az), yOf(r.dist))
        b.BackgroundTransparency = clamp(age / 2.6, 0, 0.9)
        b.Visible = true
      end
    end
    for i = n + 1, #blips do blips[i].Visible = false end
    lockBox.Visible = stt and lockAz ~= nil and lockDist ~= nil
    if lockBox.Visible then lockBox.Position = U2.fromScale(xOf(lockAz), yOf(lockDist)) end
    tName.Text = rd.name or ""
    tMode.Text = (stt and lockOk) and "STT" or (stt and "STT ?" or "SRC")
    tRange.Text = string.format("%.0f km", rd.range / AD.M / 1000)
    tWarn.Text = (stt and lockWhy == "notch") and T("air.radarNotch") or ((stt and lockWhy == "clutter") and T("air.radarClutter") or "")
    st.radarAz, st.radarStt = S.az, stt and lockOk   -- 测试用
  end

  function G.radarOff()
    gui.Enabled = false
  end
  G.radarGui = gui   -- 测试用
end

return Radar
