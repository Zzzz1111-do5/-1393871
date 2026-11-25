-- 全面大战场（客户端）——会转的履带（用户 11-25「坦克履带也要能动」）
--   原模型的履带和车身是同一块网格、贴图在 Roblox 里又不能滚动，所以在原来的履带外面贴一串履带板，按左右履带的速度走：
--   · 轮廓从原模型量好（tools/models/trackfit.py → ReplicatedStorage.TrackLoops）：下面一段（车头那头 → 贴地 → 车尾那头，
--     含前后弧的下半截）、上面一段（上沿高度，前后收到贴地那段两头；有几辆量不准就不画上面）
--   · 履带板外表面比原履带外面高出一点点，盖住原来静止的花纹；隔一块深一块浅，走起来看得出在动
--   · 下面一段往后走、上面一段往前走（相对车身），贴地那几块相对地面不动——同真车；转向时外侧快、内侧慢，原地转向一边往前一边往后
--   · 车速、转向按车身这一帧和上一帧算（自己开的、别人开的、电脑开的都一样）
--   · 省事：离镜头 220 格以内、最多 8 辆才画；远了、车毁了就藏起来不动
--   View.lua 每帧算完车身位置调 G.tracksStep(v, M, hullF, dt, far)
local RS = game:GetService("ReplicatedStorage")

local Tracks = {}

function Tracks.init(G)
  local okTL, TL = pcall(function() return require(RS:WaitForChild("TrackLoops", 10)) end)
  if not okTL or type(TL) ~= "table" then return end
  local V = Vector3.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local cam = workspace.CurrentCamera
  local PITCH = 0.95   -- 一块履带板多长（格）：真车一节 15～19 厘米，画成两节一块，近处、远处都看得出在走
  local TH = 0.24      -- 板厚
  local RANGE = 220
  local MAXN = 8
  local C1, C2 = RGB(66, 64, 60), RGB(46, 45, 42)

  -- 折线（z, y 交替）→ 段表：每段起点、长度、切线、外法线（往车外、往下那边）
  local function chainOf(pts)
    local segs, total = {}, 0
    for i = 1, #pts / 2 - 1 do
      local z0, y0, z1, y1 = pts[2 * i - 1], pts[2 * i], pts[2 * i + 1], pts[2 * i + 2]
      local dz, dy = z1 - z0, y1 - y0
      local L = math.sqrt(dz * dz + dy * dy)
      if L > 1e-3 then
        local tz, ty = dz / L, dy / L
        table.insert(segs, { z = z0, y = y0, L = L, tz = tz, ty = ty, nz = ty, ny = -tz, a = total })
        total += L
      end
    end
    return segs, total
  end
  local cache = {}
  local function shapeOf(key)
    local c = cache[key]
    if c ~= nil then return c or nil end
    local T = TL[key]
    if not T or type(T.pts) ~= "table" or #T.pts < 4 then cache[key] = false return nil end
    local segs, total = chainOf(T.pts)
    c = { T = T, segs = segs, low = total, xm = (T.xi + T.xo) / 2, w = (T.xo - T.xi) + 0.1,
      topL = (T.z0 and T.z1) and math.max(0, T.z1 - T.z0) or 0 }
    c.nLow = math.max(1, math.floor(c.low / PITCH))
    c.nTop = (c.topL > 1) and math.floor(c.topL / PITCH) or 0
    cache[key] = c
    return c
  end

  local active = {}   -- [v] = 状态
  local nActive = 0
  local function build(v, M, sh)
    local parts, cfs = {}, {}
    for side = 1, 2 do
      for i = 1, sh.nLow + sh.nTop do
        local p = Instance.new("Part")
        p.Name = "TrackLink"
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
        p.Material = Enum.Material.Metal
        p.Color = (i % 2 == 0) and C1 or C2
        p.Size = V(sh.w, TH, PITCH * 0.72)
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Parent = M.model   -- 跟车模型一起（车模型删了它也没了；炮兵视角藏敌车时一起藏）
        parts[#parts + 1] = p
        cfs[#cfs + 1] = CF()
      end
    end
    return { sh = sh, parts = parts, cfs = cfs, s = { 0, 0 }, last = nil, shown = true }
  end
  local function hide(S, on)
    if S.shown == on then return end
    S.shown = on
    for _, p in ipairs(S.parts) do p.Transparency = on and 0 or 1 end
  end

  -- 下面一段上弧长 a 处：位置（z, y）、外法线（nz, ny）
  local function atLow(sh, a)
    local segs = sh.segs
    local k = #segs
    for i = 1, #segs do
      if a < segs[i].a + segs[i].L then k = i break end
    end
    local g = segs[k]
    local u = a - g.a
    return g.z + g.tz * u, g.y + g.ty * u, g.nz, g.ny
  end

  function G.tracksStep(v, M, hullF, dt, far)
    local key = M and M.imported
    if not key then return end
    local sh = shapeOf(key)
    if not sh then return end
    local S = active[v]
    local near = not far and not v.wrecked and (hullF.Position - cam.CFrame.Position).Magnitude < RANGE
    if not near then
      if S then hide(S, false) end
      return
    end
    if not S then
      if nActive >= MAXN or not M.model or not M.model.Parent then return end
      S = build(v, M, sh)
      active[v] = S
      nActive += 1
      M.model.Destroying:Connect(function()
        if active[v] then active[v] = nil nActive -= 1 end
      end)
    end
    hide(S, true)
    -- 车速（往前为正）、转向角速度：按车身这一帧和上一帧
    local fwd, yawRate = 0, 0
    if S.last and dt > 1e-4 then
      local d = hullF.Position - S.last.Position
      fwd = d:Dot(hullF.LookVector) / dt
      local l0, l1 = S.last.LookVector, hullF.LookVector
      local a0, a1 = math.atan2(-l0.X, -l0.Z), math.atan2(-l1.X, -l1.Z)
      yawRate = ((a1 - a0 + math.pi) % (2 * math.pi) - math.pi) / dt
      if math.abs(fwd) > 80 then fwd = 0 end   -- 一帧挪太远（刚摆上、被拉回）：不算
    end
    S.last = hullF
    -- 左转（yawRate > 0）右边那条是外侧，走得快
    S.s[1] += (fwd - yawRate * sh.xm) * dt   -- 左
    S.s[2] += (fwd + yawRate * sh.xm) * dt   -- 右
    local T = sh.T
    local n = 0
    for side = 1, 2 do
      local x = (side == 1) and -sh.xm or sh.xm
      local s = S.s[side]
      for i = 0, sh.nLow - 1 do
        local a = (i * PITCH + s) % sh.low
        local z, y, nz, ny = atLow(sh, a)
        n += 1
        local pos = V(x, y - ny * (TH / 2 - 0.04), z - nz * (TH / 2 - 0.04))
        S.cfs[n] = hullF * CFrame.fromMatrix(pos, V(1, 0, 0), V(0, ny, nz))
      end
      for i = 0, sh.nTop - 1 do
        local z = T.z1 - ((i * PITCH + s) % sh.topL)
        n += 1
        S.cfs[n] = hullF * CF(x, T.top - (TH / 2 - 0.04), z)
      end
    end
    workspace:BulkMoveTo(S.parts, S.cfs, Enum.BulkMoveMode.FireCFrameChanged)
  end
end

return Tracks
