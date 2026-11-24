-- 全面大战场（客户端）——地面车的舱盖、车门、跳板开合，车长探出舱口，上车的人爬上车钻进舱口 / 从尾门走进去
--   （用户 11-24：「坦克舱门开合动画」「进入载具的动画」「坦克要有精细的roblox人物有不同的动画来负责干不同的活」
--    「你记得按照现实中不同坦克的舱门开合模式去做哈」）
--   · 原模型的舱盖和车身是一整块网格、掀不起来：照 HatchDefs 在原位置做一块同样大小的板，照真车的动法动；开着时下面垫一块黑的当舱口
--     （盖住原模型自己那块关着的舱盖）。关着时板和黑底都藏起来，看到的是原模型自己的舱盖（细节都在）
--     动法见 HatchDefs：艾布拉姆斯后铰链 + 「打开保护位」、T-90 / 96 往前开、99A 往后开、驾驶员舱盖抬起来横着转开、
--     布雷德利 / 斯特赖克尾部跳板放倒、BMP-3 两扇尾门往两边开 + 车顶两块大舱盖往外翻
--   · 什么时候开：没人的车停着——全开；有人上车——驾驶员舱盖开着等人钻进去；乘客上下车（Pass 变了）——尾门 / 跳板开 3 秒；
--     有人开、一阵没开炮没挨打——车长探出舱口（小人：两手扶舱圈、端望远镜、四下看），开炮或者挨打——车长缩回去、舱盖关上；
--     艾布拉姆斯打完一阵（12～30 秒）车长舱盖先停在「打开保护位」（掀开一道缝）
--   · 上车：有人坐上来（Driver / Pass 变了）时，按那个人刚才站的地方做一个小人——走到车边、两手扒着车体爬上去、
--     走到驾驶员舱口、扶着舱圈钻进去；乘客走到车尾、顺着跳板 / 跨进尾门弯腰钻进去（服务器那边人已经藏起来坐好了，这里只是画给大家看）
--   · 飞机：停在地上有人登机（Driver 变成玩家）——座舱左边靠一架登机梯，飞行员小人走过去、顺着梯子爬上去、跨进座舱坐下
--     （座舱盖停机时本来就开着：Fly.lua 的 can；直升机没有梯子，踩着机身踏板钻进左边舱门）；放完梯子撤掉、换回模型自己的飞行员
--   · 260 格以内才建、320 格外收掉；自己坐在车里（车内视角、瞄准镜）时这辆车外面的这些都不画
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Hatch = {}

function Hatch.init(G)
  local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
  local HD = require(RS:WaitForChild("HatchDefs"))
  local Kit = nil   -- InteriorKit（小人）：第一次要用时再拿
  local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
  local function smooth(u) u = clamp(u, 0, 1) return u * u * (3 - 2 * u) end
  local BLACK = Color3.fromRGB(12, 12, 12)

  local st = {}      -- 每辆车：em → { hs = { 舱盖 }, fig, … }（false：这辆车没有舱盖可画）
  local hist = {}    -- 每个玩家最近 0.8 秒站在哪（上车动画从那里开始）：player → { list = { { t, p } … }, out }
  local anims = {}   -- 正在上车的小人

  local AM = nil   -- AirModels（飞机座位）：第一次要用时再拿
  local function airModels()
    if AM == nil then
      local ok, m = pcall(function() return require(script.Parent:WaitForChild("AirModels")) end)
      AM = ok and m or false
    end
    return AM or nil
  end

  local function kit()
    if Kit == nil then
      local ok, k = pcall(function() return require(script.Parent:WaitForChild("InteriorKit")) end)
      Kit = ok and k or false
    end
    return Kit or nil
  end

  -- 做一个小人；量好站着时骨盆离脚底多高、眼睛比骨盆高多少（R15 模板和真人比例的人体模型不一样大）
  local function newFig(dress, parent)
    local K = kit()
    local f = K and K.crew(dress)
    if not f then return nil end
    local m = f.model
    local lt = m:FindFirstChild("LowerTorso")
    local ltY = lt and lt.CFrame.Position.Y or f.hrp.CFrame.Position.Y
    local bottom = nil
    for _, p in ipairs(m:GetDescendants()) do
      if p:IsA("BasePart") and p ~= f.hrp then
        local b = p.CFrame.Position.Y - p.Size.Y / 2
        if not bottom or b < bottom then bottom = b end
      end
    end
    local k = f.head.Size.Y / 1.2
    local F = { f = f, k = k, pelvisH = clamp(ltY - (bottom or ltY - 2.9 * k), 1.4 * k, 4 * k), eyeY = clamp(f.head.CFrame.Position.Y - ltY, 1.2 * k, 3.4 * k) }
    m.Parent = parent
    return F
  end

  local function newPart(parent, shape, size, color)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.CastShadow = true
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    if shape == "round" then p.Shape = Enum.PartType.Cylinder end
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.SmoothPlastic
    p.Transparency = 1
    p.Parent = parent
    return p
  end

  -- 舱盖的颜色：原模型里包住舱口那一块（同组、包围盒装得下舱口、最小的那块）的颜色——Tint 已经按贴图平均色上过色；找不到用同组按大小加权的平均色
  local function lidColor(v, h)
    local best, bv = nil, math.huge
    local r, g, b, n = 0, 0, 0, 0
    for _, it in ipairs(v.M and v.M.parts or {}) do
      local p, grp, off = it[1], it[2], it[3]
      if p:IsA("BasePart") and p.Transparency < 0.5 and grp == h.g and off then
        local rel = off.Position - h.loc
        local s = p.Size / 2 + V(0.3, 0.3, 0.3)
        local vol = p.Size.X * p.Size.Y * p.Size.Z
        if math.abs(rel.X) < s.X and math.abs(rel.Y) < s.Y and math.abs(rel.Z) < s.Z and vol < bv and vol > 0.05 then best, bv = p, vol end
        local w = (p.Size.X * p.Size.Z) ^ 0.5
        local c = p.Color
        r, g, b, n = r + c.R * w, g + c.G * w, b + c.B * w, n + w
      end
    end
    if best then return best.Color end
    if n > 0 then return Color3.new(r / n, g / n, b / n) end
    return Color3.fromRGB(96, 98, 84)
  end

  local function build(v)
    local key = v.M and v.M.imported
    local list = key and HD[key]
    if not list and not key and v.def then list = HD.generic(v.def) end   -- 零件拼的车按型号表摆一套；原模型表里没有的不乱画
    if not list or #list == 0 then return false end
    local folder = Instance.new("Folder")
    folder.Name = "Hatches"
    folder.Parent = v.model
    local tpiv = (v.M and v.M.tpiv) or (v.def and v.def.turret and v.def.turret.pivot) or V()
    local s = { folder = folder, hs = {}, combatT = -999, drvT = -999, passT = -999, hp = nil, drv = nil, pass = nil,
      seed = math.random() * 100, cn = v.em:GetAttribute("Team") == "atk", hide = false }   -- 攻方解放军、守方美军（车可以开对面的型号，乘员照自己这边穿）
    for _, d in ipairs(list) do
      local h = HD.prep(d, tpiv)
      h.p = 0
      local col = lidColor(v, h)
      h.lid = newPart(folder, h.shape, h.size, col)
      h.hole = newPart(folder, h.shape, h.holeSize, BLACK)
      h.hole.CastShadow = false
      table.insert(s.hs, h)
      if h.use == "drv" then s.drvH = h end
      if h.use == "pass" then s.passH = s.passH or {} table.insert(s.passH, h) end
      if h.crew == "commander" then s.cmdH = h end
    end
    return s
  end

  local function dropFig(F) if F then F.f.model:Destroy() end end
  -- 自己在车里看（外模型藏着）时新做出来的小人、梯子也一起藏
  local function hideNew(s, inst)
    if not (s and s.hide and inst) then return end
    for _, x in ipairs(inst:GetDescendants()) do
      if x:IsA("BasePart") then x.LocalTransparencyModifier = 1 end
    end
    if inst:IsA("BasePart") then inst.LocalTransparencyModifier = 1 end
  end
  local function drop(em)
    local s = st[em]
    st[em] = nil
    if not s then return end
    for _, F in pairs(s.figs or {}) do dropFig(F) end
    for i = #anims, 1, -1 do
      local A = anims[i]
      if A.s == s then
        dropFig(A.F)
        if A.done then pcall(A.done) end   -- 登机梯收掉、飞行员换回来
        table.remove(anims, i)
      end
    end
    if s.folder then s.folder:Destroy() end
  end

  ---------------------------------------------------------------- 车长 / 装填手探出舱口
  --   车长：四下看、隔一阵端望远镜看前面；装填手（艾布拉姆斯）：守着左边和后面（装填手舱口在炮塔左边），手扶舱圈
  local function crewFig(s, v, h, dt, now)
    s.figs = s.figs or {}
    local F = s.figs[h.id]
    local want = (s.out and h.p > 0.85) and 1 or 0
    if not F then
      if want == 0 then return end
      F = newFig(s.cn and "tank_cn" or "tank_us", s.folder)
      if not F then return end
      F.rise = 0
      s.figs[h.id] = F
      if h.crew == "commander" then s.fig = F end
      hideNew(s, F.f.model)
    end
    F.rise += clamp(want - F.rise, -dt * 2.4, dt * 1.3)   -- 缩回去快、钻出来慢一点
    local m = F.f.model
    if F.rise <= 0.01 and want == 0 then
      if m.Parent then m.Parent = nil end
      return
    end
    if m.Parent ~= s.folder then m.Parent = s.folder end
    local frame = (h.g == "hull") and v.hullF or v.tF
    if not frame then return end
    local C = h.loc
    -- 四下看：慢慢左右扫（每辆车相位不一样），隔一阵端起望远镜看前面；装填手看左边（左后方）
    local ldr = h.crew == "loader"
    local ph = ldr and 1.7 or 0
    local yaw = math.sin(now * 0.23 + s.seed + ph) * math.rad(ldr and 45 or 70) + math.sin(now * 0.071 + s.seed * 2 + ph) * math.rad(40)
    if ldr then yaw += math.rad(95) end
    local binoc = (not ldr) and math.sin(now * 0.19 + s.seed * 3) > 0.55
    if binoc then yaw *= 0.25 end
    local up = F.rise * 2.05 * F.k   -- 眼睛离舱圈多高：胸口露出来
    local body = frame * CF(C + V(0, up - 0.25 * F.k, 0.12)) * ANG(0, yaw * 0.45, 0)
    local pelvis = body * CF(0, -F.eyeY, 0.05)
    local look = (frame * ANG(0, yaw, 0)).LookVector + V(0, binoc and 0.03 or -0.07, 0)
    local lh, rh
    if binoc and F.rise > 0.9 then
      local face = body * CF(0, -0.1 * F.k, -0.45 * F.k)
      lh, rh = (face * CF(-0.17 * F.k, 0, 0)).Position, (face * CF(0.17 * F.k, 0, 0)).Position
    else   -- 两手扶着舱圈
      local hr = h.r or (h.w and h.w / 2) or 0.8
      lh = (frame * CF(C + V(-hr * 0.85, 0.22, -0.15))).Position
      rh = (frame * CF(C + V(hr * 0.85, 0.22, -0.15))).Position
    end
    F.f.set({ pelvis = pelvis, chest = ANG(math.rad(-4), 0, 0), look = look, lh = lh, rh = rh,
      lf = (pelvis * CF(-0.4 * F.k, -F.pelvisH, -0.2 * F.k)).Position, rf = (pelvis * CF(0.4 * F.k, -F.pelvisH, 0.1 * F.k)).Position })
  end

  ---------------------------------------------------------------- 上车的小人
  -- 关键帧（车体坐标）：t 秒、p 骨盆、yaw 朝向（0 朝车头 −Z）、lean 弯腰、lh / rh / lf / rf 手脚（nil：自然垂着 / 走路）；walk 这一段迈步
  local function keyAt(K, t)
    local a, b = K[1], K[#K]
    for i = 1, #K - 1 do
      if t < K[i + 1].t then a, b = K[i], K[i + 1] break end
    end
    local u = (b.t > a.t) and smooth((t - a.t) / (b.t - a.t)) or 1
    local function lp(x, y) if x and y then return x:Lerp(y, u) end return nil end
    local function ln(x, y) return (x or 0) + ((y or 0) - (x or 0)) * u end
    -- 转向走最近的那边
    local dy = ((b.yaw or 0) - (a.yaw or 0) + math.pi) % (2 * math.pi) - math.pi
    return { p = lp(a.p, b.p), yaw = (a.yaw or 0) + dy * u, lean = ln(a.lean, b.lean), lh = lp(a.lh, b.lh), rh = lp(a.rh, b.rh),
      lf = lp(a.lf, b.lf), rf = lp(a.rf, b.rf), walk = a.walk and b.walk }
  end

  -- 绕着车走：直线穿过车身（车体坐标里的长方形 |x| < hw、|z| < hl）就从车角绕过去
  local function route(a, b, hw, hl)
    local function hits(p, q)
      for i = 1, 23 do
        local t = i / 24
        local x, z = p.X + (q.X - p.X) * t, p.Z + (q.Z - p.Z) * t
        if math.abs(x) < hw and math.abs(z) < hl then return true end
      end
      return false
    end
    if not hits(a, b) then return { b } end
    local cs = { V(hw + 0.3, b.Y, hl + 0.3), V(-hw - 0.3, b.Y, hl + 0.3), V(hw + 0.3, b.Y, -hl - 0.3), V(-hw - 0.3, b.Y, -hl - 0.3) }
    local best, bl = nil, math.huge
    for _, c in ipairs(cs) do
      if not hits(a, c) and not hits(c, b) then
        local l = (a - c).Magnitude + (c - b).Magnitude
        if l < bl then best, bl = { c, b }, l end
      end
    end
    if best then return best end
    for _, c1 in ipairs(cs) do
      for _, c2 in ipairs(cs) do
        if c1 ~= c2 and not hits(a, c1) and not hits(c1, c2) and not hits(c2, b) then
          local l = (a - c1).Magnitude + (c1 - c2).Magnitude + (c2 - b).Magnitude
          if l < bl then best, bl = { c1, c2, b }, l end
        end
      end
    end
    return best or { b }
  end
  -- 从 from 走到 to（绕开车身），最后转到 yawEnd：往 K 里加关键帧，返回走完的时刻
  local function walkTo(K, from, to, yawEnd, v, k)
    local hw, hl = ((v.def and v.def.W) or 10) / 2 + 0.4, ((v.def and v.def.L) or 16) / 2 + 0.4
    local pts = route(from, to, hw, hl)
    local t, p = 0, from
    local spd = 11 * k   -- 小跑，约 4 米 / 秒
    for i, q in ipairs(pts) do
      local d = q - p
      local yaw = math.atan2(-d.X, -d.Z)
      if i == 1 then table.insert(K, { t = 0, p = p, yaw = yaw, walk = true })
      else
        t += 0.12
        table.insert(K, { t = t, p = p, yaw = yaw, walk = true })
      end
      t += math.max(d.Magnitude / spd, 0.12)
      table.insert(K, { t = t, p = q, yaw = yaw, walk = true })
      p = q
    end
    t += 0.15
    table.insert(K, { t = t, p = to, yaw = yawEnd, walk = true })
    return t
  end
  -- 关键帧没给手脚的补上自然的位置（两手垂在身边、两脚站着），前后两帧之间才接得上不跳
  local function fill(K, F)
    local P, k = F.pelvisH, F.k
    for _, key in ipairs(K) do
      local R = ANG(0, key.yaw or 0, 0)
      key.lh = key.lh or (key.p + R * V(-1.0 * k, -0.9 * k, 0))
      key.rh = key.rh or (key.p + R * V(1.0 * k, -0.9 * k, 0))
      key.lf = key.lf or (key.p + R * V(-0.42 * k, -P, 0))
      key.rf = key.rf or (key.p + R * V(0.42 * k, -P, 0))
    end
    return K
  end

  -- 开车的：走到车边 → 扒着车体爬上去 → 走到驾驶员舱口 → 扶着舱圈钻进去
  local function drvKeys(v, h, from, F)
    local W = (v.def and v.def.W) or 10
    local C = h.loc
    local hr = h.r or (h.w and h.w / 2) or 0.8   -- 扶舱圈的手离中心多远
    local s = (from.X >= 0) and 1 or -1
    local P, k = F.pelvisH, F.k
    local roof = C.Y
    local zs = C.Z + 0.4
    local edge = s * W / 2
    local G0 = V(edge + s * 1.0 * k, P, zs)
    local face = s * math.pi / 2   -- 面朝车：yaw = +90° 时 LookVector 是 −X
    local sink = roof - F.eyeY - 0.5 * k
    local K = {}
    local t1 = walkTo(K, V(from.X, P, from.Z), G0, face, v, k)
    for _, key in ipairs({
      -- 两手扒住车体上沿
      { t = t1 + 0.18, p = G0, yaw = face, lh = V(edge - s * 0.25, roof + 0.05, zs + s * 0.6 * k), rh = V(edge - s * 0.25, roof + 0.05, zs - s * 0.6 * k),
        lf = V(edge + s * 1.0 * k, 0.1, zs + s * 0.35 * k), rf = V(edge + s * 1.0 * k, 0.1, zs - s * 0.35 * k) },
      -- 一只脚蹬上翼子板 / 车体侧面，身子往上拔
      { t = t1 + 0.55, p = V(edge + s * 0.55 * k, roof + P * 0.35, zs), yaw = face, lean = 0.5,
        lh = V(edge - s * 0.35, roof + 0.05, zs + s * 0.6 * k), rh = V(edge - s * 0.35, roof + 0.05, zs - s * 0.6 * k),
        lf = V(edge + s * 0.25 * k, roof * 0.5, zs + s * 0.35 * k), rf = V(edge + s * 0.85 * k, 0.1, zs - s * 0.35 * k) },
      -- 两脚上了车体，蹲着
      { t = t1 + 0.9, p = V(edge - s * 0.6 * k, roof + P * 0.72, zs), yaw = face, lean = 0.35,
        lh = V(edge - s * 1.1 * k, roof + 0.05, zs + s * 0.55 * k), rh = V(edge - s * 1.1 * k, roof + 0.05, zs - s * 0.55 * k),
        lf = V(edge - s * 0.45 * k, roof, zs + s * 0.35 * k), rf = V(edge - s * 0.45 * k, roof, zs - s * 0.35 * k) },
      -- 站起来走到舱口边上，转身朝前
      { t = t1 + 1.3, p = V(C.X + s * 0.95 * k, roof + P, C.Z), yaw = 0,
        lf = V(C.X + s * 0.75 * k, roof, C.Z - 0.2 * k), rf = V(C.X + s * 1.15 * k, roof, C.Z + 0.2 * k) },
      -- 一脚跨进舱口，手扶舱圈
      { t = t1 + 1.6, p = V(C.X + s * 0.25 * k, roof + P * 0.82, C.Z), yaw = 0, lean = 0.15,
        lh = V(C.X - hr * 0.9, roof + 0.12, C.Z - 0.1), rh = V(C.X + hr * 0.9, roof + 0.12, C.Z - 0.1),
        lf = V(C.X, roof - 0.6 * k, C.Z), rf = V(C.X + s * 1.0 * k, roof, C.Z + 0.2 * k) },
      -- 钻进去
      { t = t1 + 2.15, p = V(C.X, sink, C.Z), yaw = 0,
        lh = V(C.X - hr * 0.7, roof - 0.1, C.Z), rh = V(C.X + hr * 0.7, roof - 0.1, C.Z),
        lf = V(C.X - 0.3 * k, sink - P, C.Z), rf = V(C.X + 0.3 * k, sink - P, C.Z) },
    }) do table.insert(K, key) end
    return fill(K, F), t1 + 2.15
  end

  -- 坐后面的：走到车尾 → 顺着跳板走上去 / 跨上尾门的踏板 → 弯腰钻进去
  local function passKeys(v, h, from, F)
    local P, k = F.pelvisH, F.k
    local B = h.base
    local sill = math.max(B.Y, 0)
    local out = (h.m == "ramp") and (h.L * math.sin(h.t0 + h.open) + 1.2 * k) or 1.8 * k   -- 跳板放倒后尖在车后多远
    local X = B.X
    if h.m == "door" then X = B.X + ((h.hinge == "L") and 0.15 or -0.15) end
    local hl = ((v.def and v.def.L) or 16) / 2 + 0.4
    local R0 = V(X, P, math.max(B.Z + out, hl + 0.8))
    local K = {}
    local t1 = walkTo(K, V(from.X, P, from.Z), R0, 0, v, k)
    if h.m == "ramp" then
      table.insert(K, { t = t1 + 0.7, p = V(X, sill + P * 0.92, B.Z + 0.3), yaw = 0, lean = 0.35, walk = true })
      table.insert(K, { t = t1 + 1.25, p = V(X, sill + P * 0.85, B.Z - 2.6 * k), yaw = 0, lean = 0.45, walk = true })
      return fill(K, F), t1 + 1.25
    end
    for _, key in ipairs({
      -- 一脚踩上踏板 / 门槛，手扶门框
      { t = t1 + 0.4, p = V(X, sill * 0.55 + P * 0.95, B.Z + 0.6 * k), yaw = 0, lean = 0.3,
        lh = V(X - 0.75 * k, sill + 1.4 * k, B.Z + 0.1), rh = V(X + 0.75 * k, sill + 1.4 * k, B.Z + 0.1),
        lf = V(X - 0.25 * k, sill, B.Z - 0.2), rf = V(X + 0.3 * k, 0.1, B.Z + 1.1 * k) },
      -- 弯腰钻进去
      { t = t1 + 0.95, p = V(X, sill + P * 0.8, B.Z - 2.2 * k), yaw = 0, lean = 0.6,
        lf = V(X - 0.3 * k, sill, B.Z - 2.0 * k), rf = V(X + 0.3 * k, sill, B.Z - 2.4 * k) },
    }) do table.insert(K, key) end
    return fill(K, F), t1 + 0.95
  end

  local function startBoard(v, s, kind, fromW)
    local h
    if kind == "drv" then h = s.drvH
    else   -- 几扇门挑离人近的
      local best, bd = nil, math.huge
      for _, x in ipairs(s.passH or {}) do
        if (x.m == "ramp" or x.m == "door") and v.hullF then
          local dd = fromW and ((v.hullF * x.base) - fromW).Magnitude or 0
          if dd < bd then best, bd = x, dd end
        end
      end
      h = best
    end
    if not h or not v.hullF then return end
    if not fromW then   -- 不知道刚才站哪：开车的从左边、乘客从车尾过来
      fromW = (kind == "drv") and (v.hullF * V(-((v.def.W or 10) / 2 + 6), 0, h.loc.Z)) or (v.hullF * V(0, 0, (v.def.L or 16) / 2 + 6))
    end
    local from = v.hullF:PointToObjectSpace(fromW)
    local F = newFig(kind == "drv" and (s.cn and "tank_cn" or "tank_us") or (s.cn and "crew_cn" or "crew_us"), s.folder)
    if not F then return end
    hideNew(s, F.f.model)
    local K, dur
    if kind == "drv" then K, dur = drvKeys(v, h, from, F) else K, dur = passKeys(v, h, from, F) end
    table.insert(anims, { v = v, s = s, h = h, F = F, K = K, dur = dur, t = 0, kind = kind, stride = 0 })
    if kind == "drv" then s.drvHold = true else s.passHold = (s.passHold or 0) + 1 end
  end

  -- 飞机登机：座舱左边一架登机梯（机体坐标），飞行员走过去、爬梯子、跨进座舱坐下；直升机踩着踏板钻进左边舱门
  local function airBoard(v, s, fromW)
    local A = airModels()
    local seat = A and v.M and A.seatCF(v.M, 1)
    if not seat or not v.cf then return end
    local d = v.def or {}
    local heli = d.rotor ~= nil
    local F = newFig(heli and (s.cn and "heli_cn" or "heli_us") or (s.cn and "pilot_cn" or "pilot_us"), s.folder)
    if not F then return end
    local P, k = F.pelvisH, F.k
    local S = seat.Position
    local g = -(d.gearH or 3)                    -- 地面（机体坐标：根零件离地 gearH）
    local sill = S.Y + 0.9                       -- 座舱边沿
    local side = -1                              -- 从左边上（战斗机登机梯一般挂左边）
    local lx = S.X + side * 2.2                  -- 梯子顶靠在机身侧面
    local fx = lx + side * math.max(1.2, (sill - g) * 0.28)   -- 梯子脚往外撇一点
    local from = v.cf:PointToObjectSpace(fromW or (v.cf * V(side * 12, g, S.Z + 4)))
    local K = {}
    local Fp = V(fx + side * 0.75 * k, g + P, S.Z)
    local face = side * math.pi / 2   -- 面朝机身（side −1：站在左边、朝 +X）
    local t1 = walkTo(K, V(from.X, g + P, from.Z), Fp, face, { def = { W = 4, L = 4 } }, k)
    local props = {}
    if not heli then
      -- 梯子：两根扶手 + 一档一档的踏棍（黄色地勤设备），从地面斜靠到座舱边沿
      local foot, top = V(fx, g, S.Z), V(lx, sill + 0.5, S.Z)
      local u = top - foot
      local L = u.Magnitude
      local mid = foot + u / 2
      local base = CF(mid) * ANG(0, 0, -math.atan2(u.X, u.Y))   -- 竖着的扶手（长在 Y 上）绕 Z 转到 foot → top 的方向
      local col = Color3.fromRGB(214, 176, 48)
      for _, z in ipairs({ -0.45, 0.45 }) do
        local r = newPart(s.folder, nil, V(0.14, L, 0.14), col)
        r.Transparency = 0
        table.insert(props, { r, base * CF(0, 0, z) })
      end
      local n = math.max(3, math.floor(L / 0.9))
      for i = 1, n do
        local r = newPart(s.folder, nil, V(0.1, 0.1, 0.9), Color3.fromRGB(70, 72, 74))
        r.Transparency = 0
        table.insert(props, { r, base * CF(0, -L / 2 + i * L / (n + 1), 0) })
      end
      -- 爬：一步一档，左右手脚交替（身子贴着梯子，面朝机身）
      local steps = math.max(3, math.floor((sill - g) / 0.9))
      local t = t1 + 0.15
      for i = 1, steps do
        local u2 = i / steps
        local px = fx + side * 0.75 * k + (lx - fx) * u2
        local py = g + P * (1 - 0.15 * u2) + (sill - g - P * 0.55) * u2
        local hy = py + P * 0.55
        local even = i % 2 == 0
        -- 面朝 +X（side −1）时左手在 −Z：左右按 side 换
        table.insert(K, { t = t + i * 0.32, p = V(px, py, S.Z), yaw = face, lean = 0.1,
          lh = V(px - side * 0.45 * k, hy + (even and 0.45 or 0), S.Z + side * 0.42), rh = V(px - side * 0.45 * k, hy + (even and 0 or 0.45), S.Z - side * 0.42),
          lf = V(px - side * 0.3 * k, py - P * (even and 0.6 or 0.85), S.Z + side * 0.2), rf = V(px - side * 0.3 * k, py - P * (even and 0.85 or 0.6), S.Z - side * 0.2) })
      end
      t = t + steps * 0.32
      -- 跨进座舱：一条腿先迈进去，身子转向前，坐下
      table.insert(K, { t = t + 0.45, p = V(S.X + side * 0.9, sill + P * 0.35, S.Z + 0.3), yaw = side * math.pi / 4, lean = 0.3,
        lh = V(S.X + side * 0.8, sill + 0.1, S.Z - 0.9), rh = V(S.X + side * 0.8, sill + 0.1, S.Z + 0.9),
        lf = V(S.X + side * 0.3, sill - 0.6, S.Z - 0.4), rf = V(S.X + side * 1.6, sill - 0.2, S.Z + 0.2) })
      table.insert(K, { t = t + 1.1, p = S + V(0, -0.45 * k, 0.15), yaw = 0, lean = -0.1,
        lh = V(S.X - 0.55, sill - 0.1, S.Z - 0.6), rh = V(S.X + 0.55, sill - 0.1, S.Z - 0.6),
        lf = V(S.X - 0.35, S.Y - 1.6 * k, S.Z - 2.0 * k), rf = V(S.X + 0.35, S.Y - 1.6 * k, S.Z - 2.0 * k) })
      t = t + 1.1
      fill(K, F)
      table.insert(anims, { v = v, s = s, F = F, K = K, dur = t, t = 0, kind = "air", stride = 0, props = props })
    else
      -- 直升机：走到左边舱门，踩上踏板，弯腰钻进去坐下
      local dx = S.X + side * 2.0
      table.insert(K, { t = t1 + 0.4, p = V(dx, g + P + 0.6, S.Z), yaw = face, lean = 0.35,
        lh = V(dx - side * 0.5, S.Y + 0.9, S.Z - 0.7), rh = V(dx - side * 0.5, S.Y + 0.9, S.Z + 0.7),
        lf = V(dx - side * 0.2, g + 0.9, S.Z - 0.2), rf = V(dx + side * 0.3, g + 0.1, S.Z + 0.2) })
      table.insert(K, { t = t1 + 1.1, p = S + V(0, -0.45 * k, 0.15), yaw = 0,
        lf = V(S.X - 0.35, S.Y - 1.6 * k, S.Z - 1.8 * k), rf = V(S.X + 0.35, S.Y - 1.6 * k, S.Z - 1.8 * k) })
      fill(K, F)
      table.insert(anims, { v = v, s = s, F = F, K = K, dur = t1 + 1.1, t = 0, kind = "air", stride = 0, props = props })
    end
    -- 别人的飞机：爬的时候先把模型自己坐好的飞行员藏起来，坐下了再换回来（自己的不动：座舱视角 Interior 自己管飞行员显不显示）
    local own = v.em:GetAttribute("Driver") == Players.LocalPlayer.UserId
    anims[#anims].own = own
    if not own and A.setPilots then
      pcall(A.setPilots, v.M, false)
      anims[#anims].done = function()
        for _, pr in ipairs(props) do pr[1]:Destroy() end
        pcall(A.setPilots, v.M, true)
      end
    else
      anims[#anims].done = function() for _, pr in ipairs(props) do pr[1]:Destroy() end end
    end
  end

  local function stepAnims(dt)
    for i = #anims, 1, -1 do
      local A = anims[i]
      A.t += dt
      local v, F = A.v, A.F
      local frame = (A.kind == "air") and v.cf or v.hullF
      -- 自己的飞机进了座舱视角（Interior）：镜头就在座位上，小人别挡着，直接收掉
      local inCockpit = A.own and G.interiorOn and G.interiorOn()
      if A.t >= A.dur + 0.05 or not frame or st[v.em] ~= A.s or inCockpit then
        dropFig(F)
        if A.kind == "drv" then A.s.drvHold = nil elseif A.kind == "pass" then A.s.passHold = math.max(0, (A.s.passHold or 1) - 1) end
        if A.done then A.done() end
        table.remove(anims, i)
      else
        local k = keyAt(A.K, A.t)
        if A.props then   -- 登机梯：跟着飞机摆
          local pl, cl = {}, {}
          for _, pr in ipairs(A.props) do table.insert(pl, pr[1]) table.insert(cl, frame * pr[2]) end
          workspace:BulkMoveTo(pl, cl, Enum.BulkMoveMode.FireCFrameChanged)
        end
        local pos = k.p
        if A.last then A.stride += (pos - A.last).Magnitude end
        A.last = pos
        local body = frame * CF(pos) * ANG(0, k.yaw, 0)
        local pelvis = body * ANG(-(k.lean or 0) * 0.35, 0, 0)
        local function w(x) return x and (frame * x) or nil end
        local P = { pelvis = pelvis, chest = ANG(-(k.lean or 0) * 0.65, 0, 0), look = body.LookVector + V(0, -0.15, 0),
          lh = w(k.lh), rh = w(k.rh), lf = w(k.lf), rf = w(k.rf) }
        if k.walk then   -- 迈步：两脚前后交替，抬起来的那只离地一点
          local ph = A.stride / (1.6 * F.k) * math.pi
          local sw = math.sin(ph) * 0.55 * F.k
          local lift = math.max(0, math.cos(ph)) * 0.3 * F.k
          local lift2 = math.max(0, -math.cos(ph)) * 0.3 * F.k
          P.lf = (body * CF(-0.42 * F.k, -F.pelvisH + lift, -sw)).Position
          P.rf = (body * CF(0.42 * F.k, -F.pelvisH + lift2, sw)).Position
          P.lh = (body * CF(-1.0 * F.k, -0.9 * F.k, sw * 0.8)).Position
          P.rh = (body * CF(1.0 * F.k, -0.9 * F.k, -sw * 0.8)).Position
        end
        F.f.set(P)
      end
    end
  end

  ---------------------------------------------------------------- 每帧
  local function sampleHist(now)
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      if hrp then
        local H = hist[pl]
        if not H then H = { list = {} } hist[pl] = H end
        table.insert(H.list, { t = now, p = hrp.CFrame.Position })
        while #H.list > 0 and now - H.list[1].t > 0.8 do table.remove(H.list, 1) end
      end
    end
    for pl in pairs(hist) do
      if not pl.Parent then hist[pl] = nil end
    end
  end
  -- 这个人上车前最后站在哪：服务器上车时把人挪到车的根零件上（Armor.lua seat）——从最近往前找第一个不在那里的位置
  local function lastOutside(pl, v)
    local H = hist[pl]
    if not H then return nil end
    local c = v.root and v.root.CFrame.Position or (v.cf or v.hullF).Position
    for i = #H.list, 1, -1 do
      local p = H.list[i].p
      if (p - c).Magnitude > 1.0 then return p end
    end
    return nil
  end

  function G.stepHatches(dt)
    local views = G.views
    if not views then return end
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position or V()
    local now = os.clock()
    for em in pairs(st) do
      if not em.Parent or not views[em] then drop(em) end
    end
    local plist, clist = {}, {}
    for em, v in pairs(views) do
      if v.kind == "air" and v.model and v.cf and v.M then
        -- 飞机：只管登机的小人（座舱盖、舱门、跳板 AirModels 自己会动）
        local dist = (v.cf.Position - camPos).Magnitude
        local s = st[em]
        if dist > 320 or em:GetAttribute("Wreck") then
          if s ~= nil then drop(em) end
        elseif dist < 260 or s then
          if s == nil then
            local folder = Instance.new("Folder")
            folder.Name = "Boarding"
            folder.Parent = v.model
            s = { folder = folder, hs = {}, air = true, cn = em:GetAttribute("Team") == "atk", hide = false }
            st[em] = s
          end
          local drv = em:GetAttribute("Driver") or 0
          if s.drv ~= nil and s.drv ~= drv and drv > 0 then
            local c = v.c or {}
            local parked = (c.gear or 0) > 0.9 and (c.thr or 0) < 10   -- 停在地上（放着起落架、慢车）
            local pl = Players:GetPlayerByUserId(drv)
            if pl and parked then airBoard(v, s, lastOutside(pl, v)) end
          end
          s.drv = drv
        end
      elseif v.kind == "veh" and v.model and v.hullF then
        local dist = (v.hullF.Position - camPos).Magnitude
        local s = st[em]
        if dist > 320 or em:GetAttribute("Wreck") then
          if s ~= nil then drop(em) end
        elseif dist < 260 or s then
          if s == nil then
            s = build(v)
            st[em] = s
          end
          if s then
            -- 有没有人、谁上了车、打没打仗
            local drv = em:GetAttribute("Driver") or 0
            local crewed = drv ~= 0
            if s.drv ~= nil and s.drv ~= drv then
              s.drvT = now
              local pl = drv > 0 and Players:GetPlayerByUserId(drv)
              if pl then startBoard(v, s, "drv", lastOutside(pl, v)) end
            end
            s.drv = drv
            local pass = em:GetAttribute("Pass") or 0
            if s.pass ~= nil and s.pass ~= pass then
              s.passT = now
              -- 谁上来了：服务器把乘客挪到车中心、藏起来——现在离车中心很近、刚才还在外面的
              local n = pass - s.pass
              if n > 0 then
                local c = v.root and v.root.CFrame.Position or (v.cf or v.hullF).Position
                for _, pl in ipairs(Players:GetPlayers()) do
                  if n <= 0 then break end
                  local ch = pl.Character
                  local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                  if hrp and pl.UserId ~= drv and (hrp.CFrame.Position - c).Magnitude < 2.5 then
                    local out = lastOutside(pl, v)
                    if out then
                      startBoard(v, s, "pass", out)
                      n -= 1
                    end
                  end
                end
              end
            end
            s.pass = pass
            local hp = em:GetAttribute("Hp")
            if hp and s.hp and hp < s.hp - 0.5 then s.combatT = now end   -- 挨打
            s.hp = hp
            if (v.recoil or 0) > 0.05 or (v.shots or 0) ~= (s.shots or 0) then s.combatT = now end   -- 开炮（View 的后坐、开炮次数）
            s.shots = v.shots or 0
            local calm = now - s.combatT
            local moving = math.abs(v.speed or 0) > 1
            s.out = crewed and calm > 30
            -- 自己坐在这辆车里（瞄准镜 / 车内视角）：外模型藏起来了，这些也藏
            local p1 = v.M and v.M.parts[1] and v.M.parts[1][1]
            local okL, ltm = pcall(function() return p1.LocalTransparencyModifier end)   -- 测试台里没设过的属性读不出来
            local hide = (okL and type(ltm) == "number" and ltm > 0.5) and true or false
            if hide ~= s.hide then
              s.hide = hide
              for _, x in ipairs(s.folder:GetDescendants()) do
                if x:IsA("BasePart") then x.LocalTransparencyModifier = hide and 1 or 0 end
              end
            end
            for _, h in ipairs(s.hs) do
              local want
              if h.crew then   -- 车长、装填手：没打仗探出来，打起来缩回去
                if not crewed then want = 1
                elseif calm < 12 then want = 0
                elseif h.m == "abrams" and calm < 30 then want = HD.ABRAMS_OP   -- 打开保护位
                elseif calm < 30 then want = 0
                else want = 1 end
                local F = s.figs and s.figs[h.id]
                if want < h.p and F and F.rise > 0.05 then want = h.p end   -- 人要钻回去：等人缩进去再关
              elseif h.use == "drv" then
                want = (not crewed or s.drvHold or now - s.drvT < 2.5) and 1 or 0
              elseif h.use == "pass" then
                want = (((s.passHold or 0) > 0) or now - s.passT < 3 or (not crewed and not moving)) and 1 or 0
              else
                want = (not crewed) and 1 or 0
              end
              local spd = (h.m == "ramp") and 0.8 or 2.2
              h.p += clamp(want - h.p, -dt * spd, dt * spd)
              local frame = (h.g == "hull") and v.hullF or v.tF
              -- 关着：板和黑底都藏起来（看原模型自己的舱盖）；原模型那块本来就开着的（M1A1 车长舱盖）：一直用原模型的，只有车长探身 / 缩回去
              local lidOn, holeOn
              if h.orig == "open" then lidOn, holeOn = false, false
              else lidOn, holeOn = h.p > 0.004, h.p > 0.004 end
              h.lid.Transparency = lidOn and 0 or 1
              h.hole.Transparency = holeOn and 0 or 1
              if frame then
                if lidOn then
                  table.insert(plist, h.lid)
                  table.insert(clist, frame * HD.lidCF(h, h.p))
                end
                if holeOn then
                  table.insert(plist, h.hole)
                  table.insert(clist, frame * h.holeCF)
                end
              end
              if h.crew and (s.out or (s.figs and s.figs[h.id])) then crewFig(s, v, h, dt, now) end
            end
          end
        end
      end
    end
    if #plist > 0 then workspace:BulkMoveTo(plist, clist, Enum.BulkMoveMode.FireCFrameChanged) end
    stepAnims(dt)
    sampleHist(now)
  end
  G.hatchState = function(em) return st[em] end   -- 测试用
  G.hatchAnims = anims
  -- 测试用：直接让某架飞机（G.views 里的）放一次登机动画
  G.hatchAirBoard = function(em, fromW)
    local v = G.views and G.views[em]
    if not v or v.kind ~= "air" then return false end
    local s = st[em]
    if not s then
      local folder = Instance.new("Folder")
      folder.Name = "Boarding"
      folder.Parent = v.model
      s = { folder = folder, hs = {}, air = true, cn = em:GetAttribute("Team") == "atk", hide = false }
      st[em] = s
    end
    local n0 = #anims
    airBoard(v, s, fromW)
    return #anims > n0
  end
end

return Hatch
