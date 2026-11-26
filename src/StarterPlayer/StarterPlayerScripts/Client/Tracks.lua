-- 全面大战场（客户端）——会转的履带（用户 11-25「坦克履带也要能动」；11-26「坦克履带动画也有 bug」重写）
--   原模型的履带和车身是同一块网格、贴图在 Roblox 里又不能滚动，所以在原来的履带外面套一圈履带板，按左右履带的速度绕着走：
--   · 轮廓从原模型量好（tools/models/trackfit.py → ReplicatedStorage.TrackLoops）：下面一段（车头那头 → 贴地 → 车尾那头，含前后弧的下半截）、
--     上沿高度、上面一段的前后端。这里连成闭合的一圈：下面一段 → 后弧（三次贝塞尔，顺着两头的走向，按圆弧定控制柄）→ 上面一段 → 前弧 → 回到开头
--   · 11-26 修的 bug：
--     ① 槽位（最多 8 辆）原来一占就不放（车开远了、成了残骸也占着）——开一会儿以后新来的坦克履带全不动。现在藏起来超过 2 秒就放掉，
--       满了还能抢比它远得多的那辆的
--     ② 原来下面一段、上面一段各自首尾循环：板走到头一下跳回另一头，段长又不是板长的整数倍，还有一个空档跟着走。现在整圈等距排、一直绕着走
--     ③ 折线拐角处板一下子翻过去：现在把一圈加密成 0.1 格一个点，切线按前后各 0.4 格算，过拐角、绕轮子都是圆滑地转过去
--     ④ 车速原来按带悬挂晃动的车身算（车身颠、点头也算成在走，停着履带也来回抖）：现在按没加晃动的车底位置算，再稍微平滑、太小的当 0
--   · 上面一段量不准的几辆（TrackLoops 里 z0 = nil，量到了挡泥板）：后弧、上面一段、前弧上的板藏着，只露下面一段
--   · 下面一段往后走、上面一段往前走（相对车身），贴地那几块相对地面不动——同真车；转向时外侧快、内侧慢，原地转向一边往前一边往后
--   · 省事：离镜头 220 格以内、最多 8 辆才画；远了、车毁了就藏起来不动
--   · 11-26（用户「履带 bug 是坦克同时有两副履带，一副会动」）：大多数原模型的履带本来就是单独的块（TrackLoops 的 trk），
--     原来履带板只是叠在它外面，板与板之间留着缝、拐角处和它差着一点，露出底下那副不动的——看着就是两副。
--     现在套上履带板时把原来那几块藏起来（Transparency = 1；离远了、让出槽位、车毁了放回来），整圈照这几块侧视的外轮廓（loop）走；
--     履带和车身是同一块网格、藏不掉的（豹 2A7V、M163……），履带板连成一整条、比原履带宽一点、外表面高出一点，把它整个盖住
--   View.lua 每帧算完车身位置调 G.tracksStep(v, M, hullF, dt, far, base)
local RS = game:GetService("ReplicatedStorage")

local Tracks = {}

function Tracks.init(G)
  local okTL, TL = pcall(function() return require(RS:WaitForChild("TrackLoops", 10)) end)
  if not okTL or type(TL) ~= "table" then return end
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local now = os.clock
  local PITCH = 0.95   -- 一块履带板多长（格）：真车一节 15～19 厘米，画成两节一块，近处、远处都看得出在走
  local TH = 0.28      -- 板厚
  local IN = TH / 2 - 0.035   -- 板中心比轮廓往里收多少（板外表面比原履带外面高出 0.035 格：藏不掉的原履带被整个盖住，不打架闪烁）
  local LINK = 0.97    -- 板长占节距多少：连成一整条，只留一道细缝看得出一节一节（原来 0.74，板缝里露出底下不动的原履带）
  local RANGE = 220
  local MAXN = 8
  local FREE_T = 2     -- 藏起来超过几秒放掉槽位
  local STEAL = 40     -- 槽位满了：比我远这么多格的那辆让给我
  local DS = 0.1       -- 一圈加密的步长（格）
  local TW = 0.4       -- 切线按前后各多少格算（拐角圆滑）
  local C1, C2 = RGB(66, 64, 60), RGB(46, 45, 42)

  local function unit(z, y)
    local m = math.sqrt(z * z + y * y)
    if m < 1e-6 then return 0, 0 end
    return z / m, y / m
  end
  -- 三次贝塞尔（不含两头）：从 (z0, y0) 朝 (tz0, ty0) 出发，到 (z3, y3) 时朝 (tz3, ty3)；控制柄长按同样转角的圆弧定
  local function arc(out, z0, y0, tz0, ty0, z3, y3, tz3, ty3)
    local ch = math.sqrt((z3 - z0) ^ 2 + (y3 - y0) ^ 2)
    if ch < 1e-3 then return end
    local th = math.acos(math.clamp(tz0 * tz3 + ty0 * ty3, -1, 1))
    local k = (th > 1e-3) and ch * (4 / 3) * math.tan(th / 4) / (2 * math.sin(th / 2)) or ch / 3
    local z1, y1 = z0 + tz0 * k, y0 + ty0 * k
    local z2, y2 = z3 - tz3 * k, y3 - ty3 * k
    local n = math.max(4, math.ceil(ch / 0.3))
    for i = 1, n - 1 do
      local u = i / n
      local a, b, c, d = (1 - u) ^ 3, 3 * (1 - u) ^ 2 * u, 3 * (1 - u) * u * u, u ^ 3
      out[#out + 1] = a * z0 + b * z1 + c * z2 + d * z3
      out[#out + 1] = a * y0 + b * y1 + c * y2 + d * y3
    end
  end

  -- 一辆车的履带一圈：加密成等距的点（已往里收好板中心）、每点外法线、露不露
  local cache = {}
  local function shapeOf(key)
    local c = cache[key]
    if c ~= nil then return c or nil end
    local T = TL[key]
    if not T or type(T.pts) ~= "table" or #T.pts < 4 then cache[key] = false return nil end
    local P, lowLen, hasTop = {}, 0, true
    if type(T.loop) == "table" and #T.loop >= 8 then
      -- 原模型单独的履带块侧视的外轮廓（trackfit.py）：逆时针一整圈，从最前面那一点开始；下面一半到最后面那一点
      for i = 1, #T.loop do P[i] = T.loop[i] end
      lowLen = T.lowL or 0
    else
      local L = T.pts
      local n = #L
      local zs, ys, ze, ye = L[1], L[2], L[n - 1], L[n]
      local tzs, tys = unit(L[3] - L[1], L[4] - L[2])
      local tze, tye = unit(L[n - 1] - L[n - 3], L[n] - L[n - 2])
      hasTop = (T.z0 ~= nil and T.z1 ~= nil and T.z1 - T.z0 > 1)
      local top = T.top or 3
      local z0, z1 = T.z0, T.z1
      if not hasTop then   -- 上面一段量不准：回程只是藏着走的路，按贴地那段的两头连
        local lo, hi = math.huge, -math.huge
        for i = 1, n, 2 do if L[i + 1] < 0.3 then lo, hi = math.min(lo, L[i]), math.max(hi, L[i]) end end
        if lo > hi then lo, hi = zs * 0.8, ze * 0.8 end
        z0, z1 = lo, hi
      end
      -- 折线：下面一段 → 后弧 → 上面一段 → 前弧（逆时针：z 往右、y 往上），记下面一段有多长
      for i = 1, n do P[i] = L[i] end
      for i = 1, n / 2 - 1 do lowLen += math.sqrt((L[2 * i + 1] - L[2 * i - 1]) ^ 2 + (L[2 * i + 2] - L[2 * i]) ^ 2) end
      arc(P, ze, ye, tze, tye, z1, top, -1, 0)
      P[#P + 1], P[#P + 2] = z1, top
      P[#P + 1], P[#P + 2] = z0, top
      arc(P, z0, top, -1, 0, zs, ys, tzs, tys)
    end
    -- 闭合一圈的累计长度
    local m = #P / 2
    local cum = { 0 }
    for i = 1, m do
      local j = i % m + 1
      cum[i + 1] = cum[i] + math.sqrt((P[2 * j - 1] - P[2 * i - 1]) ^ 2 + (P[2 * j] - P[2 * i]) ^ 2)
    end
    local total = cum[m + 1]
    if total < 2 then cache[key] = false return nil end
    -- 等距加密
    local N = math.max(16, math.ceil(total / DS))
    local ds = total / N
    local rz, ry = {}, {}
    local k = 1
    for i = 0, N - 1 do
      local a = i * ds
      while k < m and cum[k + 1] <= a do k += 1 end
      local j = k % m + 1
      local segL = cum[k + 1] - cum[k]
      local u = (segL > 1e-6) and (a - cum[k]) / segL or 0
      rz[i + 1] = P[2 * k - 1] + (P[2 * j - 1] - P[2 * k - 1]) * u
      ry[i + 1] = P[2 * k] + (P[2 * j] - P[2 * k]) * u
    end
    local w = math.max(1, math.floor(TW / ds + 0.5))
    local sz, sy, nz, ny, vis = {}, {}, {}, {}, {}
    for i = 1, N do
      local a, b = (i - 1 - w) % N + 1, (i - 1 + w) % N + 1
      local tz, ty = unit(rz[b] - rz[a], ry[b] - ry[a])
      local oz, oy = ty, -tz   -- 外法线（逆时针一圈：切线顺时针转 90°）
      nz[i], ny[i] = oz, oy
      sz[i], sy[i] = rz[i] - oz * IN, ry[i] - oy * IN
      vis[i] = hasTop or (i - 1) * ds <= lowLen + 0.2
    end
    local nl = math.max(4, math.floor(total / PITCH + 0.5))
    local xi, xo = T.bxi or T.xi, T.bxo or T.xo   -- 有单独的履带块：宽度按它量的
    c = { T = T, N = N, ds = ds, total = total, z = sz, y = sy, nz = nz, ny = ny, vis = vis,
      nl = nl, sp = total / nl, xm = (xi + xo) / 2, w = (xo - xi) + 0.14, top = hasTop, lowLen = lowLen, trk = T.trk }
    cache[key] = c
    return c
  end
  G.tracksShape = shapeOf   -- 测试用

  local active = {}   -- [v] = 状态
  local nActive = 0
  -- 原模型自己那几块履带：套上履带板时藏起来、板藏起来时放回来（按原来的透明度）
  local function origShow(S, on)
    if S.origOn == on then return end
    S.origOn = on
    for _, o in ipairs(S.orig) do
      if o.p.Parent then o.p.Transparency = on and o.tr or 1 end
    end
  end
  local function release(v)
    local S = active[v]
    if not S then return end
    active[v] = nil
    nActive -= 1
    if S.conn then S.conn:Disconnect() end
    origShow(S, true)
    for _, p in ipairs(S.parts) do p:Destroy() end
  end
  local function build(v, M, sh)
    local parts, cfs, vis = {}, {}, {}
    for _ = 1, 2 do
      for i = 1, sh.nl do
        local p = Instance.new("Part")
        p.Name = "TrackLink"
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
        p.Material = Enum.Material.Metal
        p.Color = (i % 2 == 0) and C1 or C2
        p.Size = V(sh.w, TH, sh.sp * LINK)
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Transparency = 1
        p.Parent = M.model   -- 跟车模型一起（车模型删了它也没了；炮兵视角藏敌车时一起藏）
        parts[#parts + 1] = p
        cfs[#cfs + 1] = CF()
        vis[#vis + 1] = false
      end
    end
    -- 原模型自己的履带块（VehModels 克隆时保留了名字 V_<键>__<块名>）
    local orig = {}
    for _, nm in ipairs(sh.trk or {}) do
      local q = M.model:FindFirstChild("V_" .. M.imported .. "__" .. nm)
      if q and q:IsA("BasePart") then orig[#orig + 1] = { p = q, tr = q.Transparency } end
    end
    local S = { sh = sh, parts = parts, cfs = cfs, vis = vis, s = { 0, 0 }, last = nil, shown = true, hidT = nil, fwd = 0, yr = 0, dist = 0, orig = orig, origOn = true }
    S.conn = M.model.Destroying:Connect(function()
      if active[v] == S then
        active[v] = nil
        nActive -= 1
      end
    end)
    return S
  end
  local function hideAll(S)
    if not S.shown then return end
    S.shown = false
    S.hidT = now()
    for i, p in ipairs(S.parts) do
      if S.vis[i] then p.Transparency = 1 S.vis[i] = false end
    end
    origShow(S, true)   -- 履带板不画了：原来那副露出来（不然车底下没履带）
  end
  -- 槽位满了：放掉一辆藏了的（藏得最久的），没有就放掉比 dist 远 STEAL 格以上、最远的那辆
  local function freeSlot(dist)
    local victim, best = nil, -math.huge
    for v, S in pairs(active) do
      local score
      if not S.shown then score = 1e6 + (now() - (S.hidT or 0))
      elseif S.dist > dist + STEAL then score = S.dist end
      if score and score > best then victim, best = v, score end
    end
    if victim then release(victim) return true end
    return false
  end

  function G.tracksStep(v, M, hullF, dt, far, base)
    local key = M and M.imported
    if not key then return end
    local sh = shapeOf(key)
    if not sh then return end
    local S = active[v]
    local dist = (hullF.Position - cam.CFrame.Position).Magnitude
    local near = not far and not v.wrecked and dist < RANGE
    if not near then
      if S then
        hideAll(S)
        if now() - (S.hidT or 0) > FREE_T then release(v) end
      end
      return
    end
    if not S then
      if not M.model or not M.model.Parent then return end
      if nActive >= MAXN and not freeSlot(dist) then return end
      S = build(v, M, sh)
      active[v] = S
      nActive += 1
    end
    S.shown, S.hidT, S.dist = true, nil, dist
    origShow(S, false)
    -- 车速（往前为正）、转向角速度：按没加悬挂晃动的车底（base）这一帧和上一帧
    local ref = base or hullF
    local fwd, yawRate = 0, 0
    if S.last and dt > 1e-4 then
      local d = ref.Position - S.last.Position
      fwd = d:Dot(ref.LookVector) / dt
      local l0, l1 = S.last.LookVector, ref.LookVector
      local a0, a1 = math.atan2(-l0.X, -l0.Z), math.atan2(-l1.X, -l1.Z)
      yawRate = ((a1 - a0 + math.pi) % (2 * math.pi) - math.pi) / dt
      if math.abs(fwd) > 80 or math.abs(yawRate) > 6 then fwd, yawRate = 0, 0 end   -- 一帧挪太远（刚摆上、被拉回）：不算
    end
    S.last = ref
    local kf = math.min(1, dt * 18)
    S.fwd += (fwd - S.fwd) * kf
    S.yr += (yawRate - S.yr) * kf
    local f, y = S.fwd, S.yr
    if math.abs(f) < 0.05 then f = 0 end
    if math.abs(y) < 0.004 then y = 0 end
    -- 履带打断了（战雷式伤害 Wt.lua 的 trackL / trackR 模块，11-26）：那一边的履带板停住，上面一段（后弧 → 前弧）掉了不画
    local brk = S.brk or { false, false }
    S.brk = brk
    if G.wtModState and v.def then
      local em = v.em
      brk[1] = em ~= nil and G.wtModState(em, v.def, "trackL") == 0
      brk[2] = em ~= nil and G.wtModState(em, v.def, "trackR") == 0
    end
    -- 左转（yawRate > 0）右边那条是外侧，走得快
    if not brk[1] then S.s[1] = (S.s[1] + (f - y * sh.xm) * dt) % sh.total end   -- 左
    if not brk[2] then S.s[2] = (S.s[2] + (f + y * sh.xm) * dt) % sh.total end   -- 右
    local N, ds, Z, Y, NZ, NY, VIS = sh.N, sh.ds, sh.z, sh.y, sh.nz, sh.ny, sh.vis
    local n = 0
    for side = 1, 2 do
      local x = (side == 1) and -sh.xm or sh.xm
      local s = S.s[side]
      for i = 0, sh.nl - 1 do
        local a = (i * sh.sp + s) % sh.total
        local q = a / ds
        local j = math.floor(q)
        local u = q - j
        j = j % N + 1
        local j2 = j % N + 1
        local z = Z[j] + (Z[j2] - Z[j]) * u
        local yy = Y[j] + (Y[j2] - Y[j]) * u
        local oz, oy = NZ[j] + (NZ[j2] - NZ[j]) * u, NY[j] + (NY[j2] - NY[j]) * u
        local m = math.sqrt(oz * oz + oy * oy)
        if m > 1e-6 then oz, oy = oz / m, oy / m else oz, oy = 0, -1 end
        n += 1
        S.cfs[n] = hullF * CFrame.fromMatrix(V(x, yy, z), V(1, 0, 0), V(0, oy, oz))
        local vis = VIS[j] and not (brk[side] and (j - 1) * ds > sh.lowLen + 0.2)
        if S.vis[n] ~= vis then
          S.vis[n] = vis
          S.parts[n].Transparency = vis and 0 or 1
        end
      end
    end
    workspace:BulkMoveTo(S.parts, S.cfs, Enum.BulkMoveMode.FireCFrameChanged)
  end
  G.tracksActive = function() return active, nActive end   -- 测试用
end

return Tracks
