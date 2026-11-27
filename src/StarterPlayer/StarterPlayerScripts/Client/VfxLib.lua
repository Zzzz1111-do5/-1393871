-- 全面大战场（客户端）——特效共用的底子（用户 11-27：开炮、炮弹打地、机枪打地、坦克殉爆都照战雷 Eagle's Shadow 做，「在 M3 的 Mac 上要丝滑」）
--   · 粒子发射器池：每一「层」（贴图、颜色、大小曲线……）按大小分档常驻发射器，用的时候把它的小零件挪到位置、Emit 几颗——
--     不每发都 Instance.new 一堆零件和发射器再 Destroy。粒子喷出去就留在世界里（不跟零件走）。
--     颜色、大小、透明度曲线改了会连已经在飞的粒子一起变，所以按「层 + 大小档 + 变体（地面颜色、贴脸）」各建一份，不在用的时候改；
--     速度、散开角只影响新喷的，可以按次改（emitK）。发射器总数有上限（MAX_EM），满了借同一层最近的一档，再不行收最久没用的那一层
--   · 一层可以有几「处」（site：一个小零件 + 一个发射器，配置一样）——下面三条引擎行为模拟器验证不了，代码里不去赌它（11-27 审查 3）：
--     (b) 同一帧里把一个零件挪来挪去、喷好几次，粒子是不是出在各自的位置：同一帧里换了位置 / 朝向就换一处喷（犁沟那一串土团、
--         两颗白闪、制退器两边），一处只在一个地方喷
--     (c) 发射器挪到别处去喷，上一处还在飘的长寿命烟会不会跟着零件出了视野被一起剔除：寿命上限 ≥ 3 秒的烟、尘云（eSoot、eCloud、
--         mHang、gRise、eRing、kHang、wSoot……碎屑火星除外）每处爆炸借一处，固定在那里，粒子没灭完不挪走（到寿命才还回池里）；
--         离上一处不到 10 格的照用那一处（挪一点不碍事）。一层最多 8 处（长寿命）/ 6 处（别的），都占满了才借最早到期的那处
--     (a) EmissionDirection = Front 时 SpreadAngle 的 X 是不是左右（水平）——见下面 SPREAD_XH：
--         Studio 里怎么看：Play（钢城、沙海都行），开坦克在平地上开一炮——炮口前应该是一大片又宽又扁、贴着地往前、往两边推开的扇形尘幕；
--         再往远处地上打一发榴弹（或看别人的落点）——落点那圈扬尘应该贴着地面往四周推开、是平的一圈。
--         要是看到的是竖起来的一堵墙、竖着的一个圈（尘往天上喷成一道竖缝），就是 X / Y 反了：把本文件里 `local SPREAD_XH = true`
--         改成 false（只改这一行，所有用到 {左右, 上下} 的层一起换过来），再开一炮看一遍
--   · 闪光灯池：8 盏点光源挂在 Attachment 上轮着用，亮度每帧按 Quad Out 降到 0（不每次新建零件、灯、补间）；投影子的同时只 1 盏
--   · 弹坑焦痕池（24 块，60 秒后 10 秒淡掉，满了收最旧的）、余火池（6 处：炸弹、导弹炸完坑里烧一会儿）
--   · 远近分档：离镜头 400 / 1100 / 2500 格（开镜按视场折算成看上去的远近）；同时活着的粒子估个数，太多了先砍碎屑、火星；
--     不走池的常喷发射器（碎块拖的火和烟、舱口火柱、炮塔身上的火）用 rateK 记进同一个数、按它少喷
--   · 预建（prewarmLater）：常用的层进局时分几帧建好（一帧 4 个），第一炮、第一次殉爆不顿
--   · 贴图只用 Roblox 自带的（rbxasset://textures/particles/…），不上传图片
--   · 测试：L.logOn = true 以后每喷一次记一笔（L.log），tools/mock/vfxreal.lua、groundhit.lua、boom.lua 按它查
local VfxLib = {}

function VfxLib.new(G, FXF)
  local L = {}
  local V, RGB = Vector3.new, Color3.fromRGB
  local NSK, CSK = NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs

  -- 自带贴图（客户端 content/textures/particles 里的单张图，没有序列帧网格）
  local TX = {
    GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds",   -- 白色柔边圆点：闪光、火星（拉长）、冰晶、染色的小碎屑
    CORE = "rbxasset://textures/particles/explosion01_core_main.dds",        -- 橙褐色翻卷的一团：火球（染不白）
    FIRE = "rbxasset://textures/particles/fire_main.dds",                    -- 细丝状的火，本身暗褐：要 LightInfluence 0 + Brightness 3
    SMOKE = "rbxasset://textures/particles/smoke_main.dds",                  -- 白色柔软的一团（alpha 最高 0.33）：尘土、浅色的烟、水雾
    SOOT = "rbxasset://textures/particles/explosion01_smoke_main.dds",       -- 深灰黑、团块明显（alpha 0.33）：黑烟
    RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds",   -- 白色双圈：冲击波圈、水面涟漪
    GRIT = "rbxasset://textures/particles/fire_sparks_main.dds",             -- 一片细碎的深色点：一颗就是一把砂砾
  }
  L.TX = TX

  ---------------------------------------------------------------- 序列
  -- ns(t0, v0, t1, v1, …) 或 ns(v)；cs(c) / cs(a, b) / cs(t0, c0, t1, c1, …)
  function L.ns(...)
    local a = { ... }
    if #a == 1 then return NumberSequence.new(a[1]) end
    local kp = {}
    for i = 1, #a, 2 do kp[#kp + 1] = NSK(a[i], a[i + 1]) end
    return NumberSequence.new(kp)
  end
  function L.cs(...)
    local a = { ... }
    if #a == 1 then return ColorSequence.new(a[1]) end
    if #a == 2 then return ColorSequence.new({ CSK(0, a[1]), CSK(1, a[2]) }) end
    local kp = {}
    for i = 1, #a, 2 do kp[#kp + 1] = CSK(a[i], a[i + 1]) end
    return ColorSequence.new(kp)
  end
  -- 透明度曲线整体加一点（贴脸、开镜时淡一点）：(t, v) 对的表
  function L.nsAdd(pairs_, add)
    local kp = {}
    for i = 1, #pairs_, 2 do kp[#kp + 1] = NSK(pairs_[i], min(1, pairs_[i + 1] + add)) end
    return NumberSequence.new(kp)
  end
  -- 零件的 +Y（EmissionDirection = Top 的发射方向）朝 up
  function L.upCF(p, up)
    local r = up:Cross((abs(up.Y) < 0.95) and V(0, 1, 0) or V(1, 0, 0)).Unit
    return CFrame.fromMatrix(p, r, up)
  end
  -- 零件的正面（EmissionDirection = Front）朝 dir、顶朝上（扇面、贴地一圈）
  function L.lookCF(p, dir)
    if dir.Magnitude < 1e-3 then return CFrame.new(p) end
    local d = dir.Unit
    if abs(d.Y) > 0.98 then return CFrame.lookAt(p, p + d, V(0, 0, 1)) end
    return CFrame.lookAt(p, p + d)
  end

  ---------------------------------------------------------------- 发射器池
  local POOL = Instance.new("Folder")   -- 放在 ClientFx 下面的子文件夹：画中画（ScopePip）只看 ClientFx 的直接子零件，不会去克隆这些看不见的小零件
  POOL.Name = "VfxPool"
  POOL.Parent = FXF
  L.folder = POOL
  local HIDE = CFrame.new(0, -2000, 0)
  local function holder(name, size)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size or V(0.2, 0.2, 0.2)
    p.Transparency = 1
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.CFrame = HIDE
    p.Parent = POOL
    return p
  end
  L.holder = holder

  -- SpreadAngle 的 (X, Y)：EmissionDirection = Front 时 X 是左右、Y 是上下（文档：Top 时两个分量是 X / Z 两个轴上的散开）。
  --   Studio 里要是看着反了（贴地一圈变成竖着的一圈、开炮的扇形尘幕变成竖着的一堵墙），把这里改成 false（怎么看见文件开头 (a)）
  local SPREAD_XH = true
  local function spreadV(sp)
    if type(sp) == "number" then return Vector2.new(sp, sp) end
    if type(sp) == "table" then
      if SPREAD_XH then return Vector2.new(sp[1], sp[2]) end
      return Vector2.new(sp[2], sp[1])
    end
    return Vector2.new(0, 0)
  end
  L.spreadV = spreadV

  -- 风（Workspace.GlobalWind，格/秒）：烟尘层开 WindAffectsDrag 顺风飘。地图没设风（0）时，烟尘层的加速度里补一点水平的（原来各处写死的那份）
  local wind = V()
  local windT = -10
  local FALLBACK = V(1.4, 0, 0.7)
  local function windNow()
    local t = os.clock()
    if t - windT > 2 then
      windT = t
      local ok, w = pcall(function() return workspace.GlobalWind end)
      wind = (ok and typeof(w) == "Vector3") and w or V()
    end
    return wind
  end
  L.wind = windNow

  local DEFS = {}      -- 层名 → { f = function(档的大小倍数, 变体) → 配置, fixed = 不分档 }
  local POOLS = {}     -- 键 → 层 { name, key, ti, var, o, sites = { 一处 = { h 小零件, pe 发射器, cf, t 上次喷, till 占到什么时候 } } }
  local nEm = 0
  L.MAX_EM = 420   -- 发射器（处）一共最多几个（测试可以临时调小）
  local SITE_LONG, SITE_SHORT = 8, 6   -- 一层最多几处：长寿命的烟尘 8 处（同时 8 处在飘），别的 6 处（一帧里在 6 个地方喷：犁沟的一串土团）
  local LONG = 3          -- 寿命上限 ≥ 3 秒的（碎屑火星除外）：每处借一处，粒子没灭完不挪走
  local NEAR_R = 10       -- 离上一处不到 10 格：照用那一处
  local RECENT = 0.04     -- 「同一帧」：这么久以内喷过（帧率 25 以上都算得住；算多了只是多借一处）
  L.stat = { emitters = 0, made = 0, emits = 0, emitted = 0, flashes = 0, scorch = 0, burners = 0, borrowed = 0, cut = 0,
    sites = 0, stolen = 0, recycled = 0, warm = 0, rated = 0 }
  local madeT, madeN = 0, 0   -- 每秒新建了几个发射器（测试查：别一下子建太多；预建的不算）
  L.madeMax = 0

  -- 配置字段：tex 贴图、life / spd {小, 大}、size / tr（NumberSequence）、col（ColorSequence）、acc 加速度、drag 阻力、
  --   le LightEmission、li LightInfluence（不写：le > 0.5 的 0，别的 1）、bright Brightness（不写：火的贴图 3，别的 1）、z ZOffset、
  --   dir EmissionDirection、spread 数或 {左右, 上下}、rot 转速、flat 平躺（VelocityPerpendicular）、vp 顺着速度拉长（VelocityParallel）、
  --   sq Squash、wind 跟着风、shape {"Sphere"/"Box"/…, 体积或表面, 往外或往里}、box 小零件的大小（出生的体积）、
  --   prio 1 要紧（闪光、火球）/ 2 一般 / 3 碎屑火星（粒子多了先砍）、cat "imp"（弹着点：另有 600 颗的上限）、
  --   site true / false：一处一个零件、粒子没灭完不挪（不写：寿命上限 ≥ 3 秒、prio 不是 3 的算）
  function L.def(name, f, fixed)
    DEFS[name] = { f = f, fixed = fixed }
  end
  function L.has(name) return DEFS[name] ~= nil end

  local LN12 = math.log(1.2)
  local function tierOf(s)
    s = math.clamp(tonumber(s) or 1, 0.05, 40)
    local i = floor(math.log(s) / LN12 + 0.5)
    return i, 1.2 ^ i
  end
  L.tierOf = tierOf

  local function maxOf(seq)
    local m = 0
    for _, k in ipairs(seq.Keypoints) do if k.Value > m then m = k.Value end end
    return m
  end
  local function apply(pe, o)
    pe.Texture = o.tex
    pe.Rate = o.rate or 0
    pe.Lifetime = NumberRange.new(o.life[1], o.life[2])
    pe.Speed = NumberRange.new(o.spd[1], o.spd[2])
    pe.SpreadAngle = spreadV(o.spread)
    pe.Size = o.size
    pe.Transparency = o.tr
    pe.Color = o.col
    local acc = o.acc or V()
    if o.wind and windNow().Magnitude < 0.5 then acc += FALLBACK end
    pe.Acceleration = acc
    pe.Drag = o.drag or 0
    local le = o.le or 0
    pe.LightEmission = le
    pe.LightInfluence = o.li or ((le > 0.5) and 0 or 1)
    pe.Brightness = o.bright or ((o.tex == TX.FIRE) and 3 or 1)
    pe.ZOffset = o.z or 0
    pe.EmissionDirection = o.dir or Enum.NormalId.Top
    if o.vp then
      pe.Orientation = Enum.ParticleOrientation.VelocityParallel
      pe.Rotation = NumberRange.new(0)
      pe.RotSpeed = NumberRange.new(0)
    else
      if o.flat then pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
      pe.Rotation = NumberRange.new(0, 360)
      pe.RotSpeed = NumberRange.new(-(o.rot or 30), o.rot or 30)
    end
    -- 新一点的属性（老版本 Studio 没有也别整个特效出错）
    if o.sq then pcall(function() pe.Squash = o.sq end) end
    if o.wind then pcall(function() pe.WindAffectsDrag = true end) end
    if o.shape then
      pcall(function()
        pe.Shape = Enum.ParticleEmitterShape[o.shape[1]]
        pe.ShapeStyle = Enum.ParticleEmitterShapeStyle[o.shape[2] or "Volume"]
        pe.ShapeInOut = Enum.ParticleEmitterShapeInOut[o.shape[3] or "Outward"]
      end)
    end
  end
  L.apply = apply

  local warming = false   -- 正在预建（不算进「每秒新建了几个」）
  local function newSite(e)
    local n = #e.sites
    local h = holder((n == 0) and e.key or (e.key .. "~" .. (n + 1)), e.o.box)
    local pe = Instance.new("ParticleEmitter")
    apply(pe, e.o)
    pe.Parent = h
    local s = { h = h, pe = pe, cf = nil, t = -1e9, till = 0 }
    e.sites[n + 1] = s
    nEm += 1
    L.stat.emitters = nEm
    L.stat.made += 1
    L.stat.sites += 1
    if not warming then
      local t = os.clock()
      if t - madeT > 1 then madeT, madeN = t, 0 end
      madeN += 1
      if madeN > L.madeMax then L.madeMax = madeN end
    end
    return s
  end
  local function shortTex(t) return (t and t:match("([%w_]+)%.%w+$")) or tostring(t) end
  local function newEm(name, key, ti, var, o)
    local long = o.site
    if long == nil then long = o.life[2] >= LONG and (o.prio or 2) ~= 3 end
    local e = { name = name, key = key, ti = ti, var = var, o = o, life = (o.life[1] + o.life[2]) / 2,
      big = maxOf(o.size), tex = shortTex(o.tex), used = os.clock(), long = long == true, sites = {} }
    local s = newSite(e)
    e.h, e.pe = s.h, s.pe   -- 第一处（测试、别的模块看配置用：几处的配置都一样）
    POOLS[key] = e
    return e
  end

  -- 到上限：收最久没用的那一层（它的粒子早灭了），腾出位置
  local function recycle(keep)
    local now = os.clock()
    local old, ot, oldBusy, obt = nil, math.huge, nil, math.huge
    for _, x in pairs(POOLS) do
      if x ~= keep then
        local busy = false
        for _, s in ipairs(x.sites) do
          if now < s.till or now - s.t < x.o.life[2] + 0.2 then busy = true break end
        end
        if not busy and x.used < ot then old, ot = x, x.used end
        if x.used < obt then oldBusy, obt = x, x.used end
      end
    end
    old = old or oldBusy
    if not old then return false end
    for _, s in ipairs(old.sites) do
      s.h:Destroy()
      nEm -= 1
    end
    POOLS[old.key] = nil
    L.stat.emitters = nEm
    L.stat.recycled += 1
    return true
  end

  local function keyOf(name, s, var)
    local D = DEFS[name]
    if not D then return nil end
    local ti, sc = 0, 1
    if not D.fixed then ti, sc = tierOf(s) end
    local key = D.fixed and (name .. (var or "")) or (name .. "#" .. ti .. (var or ""))
    return key, ti, sc, D
  end
  local function get(name, s, var)
    local key, ti, sc, D = keyOf(name, s, var)
    if not key then return nil end
    local e = POOLS[key]
    if e then
      e.used = os.clock()
      return e
    end
    if nEm >= L.MAX_EM then
      -- 满了：先借同一层、同一变体最近的一档（差三档以内：大小差不到一倍，总比不画好），没有就收最久没用的那一层，腾出来建这一层
      local best, bd = nil, math.huge
      for _, x in pairs(POOLS) do
        if x.name == name and x.var == var and abs(x.ti - ti) < bd then best, bd = x, abs(x.ti - ti) end
      end
      if best and bd <= 3 then
        L.stat.borrowed += 1
        best.used = os.clock()
        return best
      end
      if not recycle(nil) then return best end
    end
    local ok, o = pcall(D.f, sc, var)
    if not ok or type(o) ~= "table" then
      warn("[特效] 层 " .. name .. " 配置出错：" .. tostring(o))
      return nil
    end
    return newEm(name, key, ti, var, o)
  end
  L.get = get

  -- 这一次喷在哪一处（见文件开头 (b)、(c)）
  local function sameCF(a, b)
    return (a.Position - b.Position).Magnitude < 0.05 and a.LookVector:Dot(b.LookVector) > 0.9995 and a.UpVector:Dot(b.UpVector) > 0.9995
  end
  local function pickSite(e, cf, now)
    local sites = e.sites
    local p = cf.Position
    -- ① 这一帧在同一个位置、同一个朝向喷过的：接着用
    for _, s in ipairs(sites) do
      if now - s.t < RECENT and s.cf and sameCF(s.cf, cf) then return s end
    end
    -- ② 这一帧没用过、离上一处不到 10 格的：挪一点照用（上一处的烟还在零件附近）
    local best, bd = nil, NEAR_R
    for _, s in ipairs(sites) do
      if now - s.t >= RECENT and s.cf then
        local d = (s.cf.Position - p).Magnitude
        if d < bd then best, bd = s, d end
      end
    end
    if best then return best end
    -- ③ 这一帧没用过、粒子已经灭完的（长寿命的到寿命了；别的喷完就能挪）
    for _, s in ipairs(sites) do
      if now - s.t >= RECENT and now >= s.till then return s end
    end
    -- ④ 再建一处
    if #sites < (e.long and SITE_LONG or SITE_SHORT) and nEm < L.MAX_EM then return newSite(e) end
    -- ⑤ 都占着（太多了才会这样）：借这一帧没用过、最早到期的那处
    local old = nil
    for _, s in ipairs(sites) do
      if now - s.t >= RECENT and (not old or s.till < old.till) then old = s end
    end
    L.stat.stolen += 1
    return old or sites[1]
  end
  L.pickSite = pickSite   -- 测试用

  ---------------------------------------------------------------- 同时活着的粒子：按到期时间分桶估个数（每 0.25 秒一桶，管 40 秒）
  local NB, BW = 160, 0.25
  local bAll, bImp = table.create(NB, 0), table.create(NB, 0)
  local curB = floor(os.clock() / BW)
  L.live, L.liveImp = 0, 0
  local function advance()
    local nb = floor(os.clock() / BW)
    if nb <= curB then return end
    if nb - curB >= NB then
      for i = 1, NB do bAll[i], bImp[i] = 0, 0 end
      L.live, L.liveImp = 0, 0
    else
      for b = curB + 1, nb do
        local i = b % NB + 1
        L.live -= bAll[i]
        L.liveImp -= bImp[i]
        bAll[i], bImp[i] = 0, 0
      end
    end
    curB = nb
  end
  local function accountAt(n, expiry, imp)
    local b = floor(expiry / BW)
    if b <= curB then b = curB + 1 end
    if b - curB >= NB then b = curB + NB - 1 end
    local i = b % NB + 1
    bAll[i] += n
    L.live += n
    if imp then
      bImp[i] += n
      L.liveImp += n
    end
  end
  local function account(e, n) accountAt(n, os.clock() + e.life, e.o.cat == "imp") end
  -- 全局：活着的超过 SOFT 开始砍（碎屑火星先砍、一般的少砍、闪光火球不砍），到 HARD 只留要紧的
  L.SOFT, L.HARD, L.IMP_MAX = 1800, 2800, 600
  local function budgetK(pr)
    local live = L.live
    if live > L.HARD then return (pr == 1) and 0.5 or 0 end
    if live > L.SOFT then
      local f = (live - L.SOFT) / (L.HARD - L.SOFT)
      if pr == 3 then return 1 - f elseif pr == 2 then return 1 - 0.6 * f end
    end
    return 1
  end
  local function budget(e, n)
    advance()
    local pr = e.o.prio or 2
    local k = budgetK(pr)
    if e.o.cat == "imp" and L.liveImp + n > L.IMP_MAX then k = 0 end
    local m = floor(n * k + 0.5)
    if pr == 1 and n >= 1 and m < 1 and L.live <= L.HARD * 1.3 then m = 1 end
    if m < n then L.stat.cut += n - m end
    return m
  end
  -- 不走池的常喷发射器（碎块拖的火和烟、舱口火柱、炮塔身上挂的火和烟……）：rate 每秒几颗、secs 喷几秒、life 每颗活多久——
  --   按到期时间记进同时活着的粒子数（全局预算管得到它们）；返回现在该按几成喷（粒子太多时少喷：Rate 乘它）
  function L.rateK(rate, secs, life, prio)
    advance()
    local k = budgetK(prio or 2)
    local per = (rate or 0) * k * BW
    if per > 0 then
      local now = os.clock()
      for t = 0, math.max(0, secs or 0), BW do accountAt(per, now + t + (life or 1)) end
      L.stat.rated += rate * k * (secs or 0)
    end
    return k
  end

  L.logOn, L.log = false, {}
  local function logIt(e, n, cf, s)
    local o = e.o
    local c0 = o.col.Keypoints[1].Value
    L.log[#L.log + 1] = { name = e.name, key = e.key, tex = e.tex, n = n, big = e.big, flat = o.flat == true, vp = o.vp == true,
      le = o.le or 0, li = s.pe.LightInfluence, bright = s.pe.Brightness, col = c0, pos = cf.Position, wind = o.wind == true,
      life = { o.life[1], o.life[2] }, var = e.var, sq = o.sq ~= nil, cat = o.cat, site = s.h, long = e.long,
      spread = s.pe.SpreadAngle, look = cf.LookVector, up = cf.UpVector }
  end

  -- 速度、散开角（只影响新喷的）：这一处的值不一样才写
  local function kickSite(s, spd, spread)
    if spd and (s.ks1 ~= spd[1] or s.ks2 ~= spd[2]) then
      s.ks1, s.ks2 = spd[1], spd[2]
      s.pe.Speed = NumberRange.new(spd[1], spd[2])
    end
    if spread and s.ksp ~= spread then
      s.ksp = spread
      s.pe.SpreadAngle = spreadV(spread)
    end
  end
  local function emitIn(e, cf, n, spd, spread)
    n = budget(e, floor(n + 0.5))
    if n < 1 then return e end
    local now = os.clock()
    local s = pickSite(e, cf, now)
    kickSite(s, spd, spread)
    s.h.CFrame = cf
    s.cf = cf
    s.pe:Emit(n)
    s.t = now
    if e.long then s.till = max(s.till, now + e.o.life[2] + 0.3) end
    account(e, n)
    L.stat.emits += 1
    L.stat.emitted += n
    if L.logOn then logIt(e, n, cf, s) end
    return e
  end
  -- 喷：name 层、s 大小倍数（按 1.2 倍一档）、cf 小零件放哪（Top 发射的 +Y、Front 发射的正面朝要喷的方向）、n 几颗、var 变体
  function L.emit(name, s, cf, n, var)
    if not n or n < 0.5 then return nil end
    local e = get(name, s, var)
    if not e then return nil end
    return emitIn(e, cf, n)
  end
  -- 先改速度 / 散开角再喷（同一层不同次的初速不一样：入射角、口径）
  function L.emitK(name, s, cf, n, var, spd, spread)
    if not n or n < 0.5 then return nil end
    local e = get(name, s, var)
    if not e then return nil end
    return emitIn(e, cf, n, spd, spread)
  end
  -- 改一层所有处的速度 / 散开角（别的模块用）
  function L.kick(e, spd, spread)
    if not e then return end
    for _, s in ipairs(e.sites) do kickSite(s, spd, spread) end
  end
  function L.count()
    local nh = 0
    for _, c in ipairs(POOL:GetChildren()) do if c:IsA("BasePart") then nh += 1 end end
    return nEm, nh
  end
  L.pools = POOLS
  -- 马上建好（弹着点那几种常用的：测试一开始就找得到）
  function L.prewarm(list, s, var)
    for _, name in ipairs(list) do get(name, s or 1, var) end
  end
  -- 分几帧建好（进局时：开炮、榴弹、殉爆、机枪打地常用的那几层；一帧 WARM_N 个，第一炮、第一次殉爆不用现建）：
  --   list = { { 层名, 大小, 变体, 几处（不写 1：一下要在两处喷的白闪、制退器、犁沟的一串土团多建几处） }, … }
  local warmQ, warmI = {}, 1
  local WARM_N = 4
  function L.prewarmLater(list)
    for _, it in ipairs(list) do warmQ[#warmQ + 1] = it end
  end
  function L.warmLeft() return #warmQ - warmI + 1 end
  local function stepWarm()
    if warmI > #warmQ then
      if #warmQ > 0 then warmQ, warmI = {}, 1 end
      return
    end
    local n = 0
    warming = true
    while warmI <= #warmQ and n < WARM_N do
      local it = warmQ[warmI]
      warmI += 1
      local key = keyOf(it[1], it[2], it[3])
      if key and nEm < L.MAX_EM - 40 then   -- 留 40 个给打起来现用的
        local e = POOLS[key]
        if not e then
          e = get(it[1], it[2], it[3])
          L.stat.warm += 1
          n += 1
        end
        while e and #e.sites < math.min(it[4] or 1, e.long and SITE_LONG or SITE_SHORT) do
          newSite(e)
          L.stat.warm += 1
          n += 1
        end
      end
    end
    warming = false
  end

  ---------------------------------------------------------------- 远近分档
  -- 1：400 格内全画；2：1100 格内数量减半、不画碎屑和冲击圈；3：2500 格内只画闪光、火球、几团烟和灯；4：更远夜里只点灯
  --   开镜（视场小）按看上去的远近算：8 倍镜里 3000 格外的炮弹落点看着像 400 格
  function L.lod(p)
    local cam = workspace.CurrentCamera
    local d = cam and (p - cam.CFrame.Position).Magnitude or 0
    local fov = cam and cam.FieldOfView or 70
    local de = d * min(1, fov / 70)
    local t = (de <= 400 and 1) or (de <= 1100 and 2) or (de <= 2500 and 3) or 4
    return t, d, de
  end
  function L.perfK() return math.clamp(G.perfK or 1, 0.5, 1.2) end

  ---------------------------------------------------------------- 闪光灯池
  local MAXL = 8
  local rig = holder("FlashRig")
  rig.CFrame = CFrame.new()
  local LS = {}
  for i = 1, MAXL do
    local a = Instance.new("Attachment")
    a.Name = "Flash" .. i
    a.Parent = rig
    local pl = Instance.new("PointLight")
    pl.Enabled, pl.Brightness, pl.Shadows = false, 0, false
    pl.Parent = a
    LS[i] = { a = a, pl = pl, on = false, t0 = 0, dur = 0.1, b0 = 0, range = 0, sh = false }
  end
  local liveSh = 0
  local function release(s)
    s.on = false
    s.pl.Enabled = false
    s.pl.Brightness = 0
    if s.sh then
      s.pl.Shadows = false
      s.sh = false
      liveSh -= 1
    end
  end
  -- p 位置、color、range（最大 120）、bright（夜里的亮度；白天自动加亮）、t 几秒降到 0、
  --   o.shadow 想投影子（同时只给 1 盏）、o.day 白天最多亮几倍（不写 2.5：小的闪光白天要亮一倍半才看得出来；
  --   殉爆、榴弹、炸弹那种大灯给 1.5——Realistic 光照下白天再乘 2.5 一大片过曝）
  L.DAY_MUL, L.DAY_MUL_BIG = 2.5, 1.5
  function L.flash(p, color, range, bright, t, o)
    if typeof(p) ~= "Vector3" then return nil end
    local cam = workspace.CurrentCamera
    range = min(120, range or 20)
    if cam and (cam.CFrame.Position - p).Magnitude > range + 400 then return nil end
    local dk = G.dayK and G.dayK() or 0
    local dm = (o and o.day) or L.DAY_MUL
    local b = (bright or 4) * (1 + (dm - 1) * dk)
    local now = os.clock()
    local slot, weak, wv = nil, nil, math.huge
    for i = 1, MAXL do
      local s = LS[i]
      if not s.on then
        slot = s
        break
      end
      local u = math.clamp((now - s.t0) / s.dur, 0, 1)
      local cur = s.b0 * (1 - u) * (1 - u) * s.range
      if cur < wv then weak, wv = s, cur end
    end
    if not slot then   -- 8 盏都亮着：比最暗的那盏亮就顶掉它
      if weak and wv < b * range then
        slot = weak
        release(slot)
      else
        return nil
      end
    end
    local want = (o and o.shadow and liveSh < 1 and (G.perfK or 1) >= 0.8) and true or false
    local pl = slot.pl
    slot.a.Position = p
    pl.Color, pl.Range, pl.Brightness = color, range, b
    if pl.Shadows ~= want then pl.Shadows = want end
    if want then liveSh += 1 end
    slot.sh = want
    pl.Enabled = true
    slot.on, slot.t0, slot.dur, slot.b0, slot.range = true, now, max(0.03, t or 0.1), b, range
    L.stat.flashes += 1
    return pl
  end
  function L.lightsOn()
    local n, s = 0, 0
    for i = 1, MAXL do
      if LS[i].on then n += 1 end
      if LS[i].sh then s += 1 end
    end
    return n, s
  end
  L.MAXL = MAXL

  ---------------------------------------------------------------- 弹坑焦痕池（榴弹、炸弹、导弹打在地上：薄零件上两张烟的贴图染黑，平铺在地上）
  local SC, scI = {}, 0
  local SC_MAX = 24
  function L.scorch(pos, D, col, tr, nrm)
    scI = scI % SC_MAX + 1
    local s = SC[scI]
    if not s then
      local p = holder("Crater")
      local ds = {}
      for i = 1, 2 do
        local dc = Instance.new("Decal")
        dc.Face = Enum.NormalId.Top
        dc.Texture = TX.SMOKE
        dc.Transparency = 1
        dc.Parent = p
        ds[i] = dc
      end
      s = { p = p, d = ds }
      SC[scI] = s
    end
    local up = (typeof(nrm) == "Vector3" and nrm.Magnitude > 0.5) and nrm.Unit or V(0, 1, 0)
    s.p.Size = V(D, 0.05, D)
    s.p.CFrame = L.upCF(pos + up * 0.07, up) * CFrame.Angles(0, math.random() * 6.28, 0)
    s.base, s.t0, s.on = tr, os.clock(), true
    for _, dc in ipairs(s.d) do
      dc.Color3 = col
      dc.Transparency = tr
    end
    L.stat.scorch += 1
    return s.p
  end
  function L.scorchLive()
    local n = 0
    for _, s in ipairs(SC) do if s.on then n += 1 end end
    return n, #SC
  end
  L.SCORCH_HOLD, L.SCORCH_FADE = 60, 10

  ---------------------------------------------------------------- 余火池：炸弹、导弹、大的残骸炸完坑里还烧一会儿（6 处轮着用）
  local BU = {}
  local BU_MAX = 6
  function L.burn(pos, R, secs)
    local now = os.clock()
    local s, old = nil, nil
    for _, b in ipairs(BU) do
      if now > b.free then
        s = b
        break
      end
      if not old or b.t0 < old.t0 then old = b end
    end
    if not s and #BU < BU_MAX then
      local h = holder("Burner")
      local f = Instance.new("ParticleEmitter")
      apply(f, { tex = TX.FIRE, life = { 0.6, 1.2 }, spd = { 2, 6 }, spread = 25, acc = V(0, 6, 0), size = L.ns(0, 3, 1, 0.5),
        tr = L.ns(0, 0.2, 1, 1), col = L.cs(RGB(255, 196, 120), RGB(255, 96, 40)), le = 0.9, li = 0, bright = 3, rot = 60 })
      f.Parent = h
      local k = Instance.new("ParticleEmitter")
      apply(k, { tex = TX.SOOT, life = { 4, 6 }, spd = { 3, 6 }, spread = 15, acc = V(0, 3, 0), drag = 1, wind = true, size = L.ns(0, 4, 1, 16),
        tr = L.ns(0, 0.15, 1, 1), col = L.cs(RGB(255, 255, 255)), rot = 15 })
      k.Parent = h
      s = { h = h, f = f, k = k, free = 0, t0 = 0, R = 0 }
      BU[#BU + 1] = s
    end
    s = s or old
    if not s then return nil end
    s.h.CFrame = CFrame.new(pos)
    if abs(s.R - R) > 0.5 then   -- 大小换了才改（这一处原来的粒子早灭了）
      s.R = R
      s.f.Size = L.ns(0, R * 0.3, 1, R * 0.05)
      s.k.Size = L.ns(0, R * 0.4, 1, R * 1.8)
    end
    local kb = L.rateK(15, secs, 3, 2)   -- 记进全局预算（火 12 + 烟 3 颗 / 秒）
    s.f.Rate, s.k.Rate = 12 * kb, 3 * kb
    s.t0, s.till, s.free = now, now + secs, now + secs + 6
    L.stat.burners += 1
    return s
  end
  function L.burnersLive()
    local n = 0
    for _, b in ipairs(BU) do if b.till then n += 1 end end
    return n, #BU
  end

  ---------------------------------------------------------------- 每帧（Fx 的 stepFx 调）
  local slowT = 0
  local stepHooks = {}   -- 别的模块每帧要跟着跑的（Fx 的曳光池）
  function L.onStep(f) stepHooks[#stepHooks + 1] = f end
  function L.step(dt)
    local now = os.clock()
    for i = 1, MAXL do
      local s = LS[i]
      if s.on then
        local u = (now - s.t0) / s.dur
        if u >= 1 then release(s) else s.pl.Brightness = s.b0 * (1 - u) * (1 - u) end
      end
    end
    for _, f in ipairs(stepHooks) do f(dt or 1 / 60, now) end
    stepWarm()
    slowT += dt or 0
    if slowT < 0.25 then return end
    slowT = 0
    advance()
    for _, s in ipairs(SC) do   -- 焦痕：60 秒后 10 秒淡掉
      if s.on then
        local age = now - s.t0
        if age > L.SCORCH_HOLD + L.SCORCH_FADE then
          s.on = false
          for _, dc in ipairs(s.d) do dc.Transparency = 1 end
        elseif age > L.SCORCH_HOLD then
          local f = (age - L.SCORCH_HOLD) / L.SCORCH_FADE
          for _, dc in ipairs(s.d) do dc.Transparency = s.base + (1 - s.base) * f end
        end
      end
    end
    for _, b in ipairs(BU) do   -- 余火：到时候关
      if b.till and now > b.till then
        b.till = nil
        b.f.Rate, b.k.Rate = 0, 0
      end
    end
  end

  return L
end

return VfxLib
