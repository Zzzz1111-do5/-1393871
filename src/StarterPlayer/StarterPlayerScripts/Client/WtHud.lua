-- Roblox全面大战场（客户端）——战雷式伤害的界面（用户 11-24「把整个游戏做成战雷」：乘员和模块伤害 + X 光回放）
--   · 命中提示（打出去的）：准星下面一行——击穿（橙）/ 未击穿（灰）/ 跳弹（黄）/ 已击毁（红：弹药殉爆、车组全灭、烧毁），
--     后面跟这一发伤了谁：「炮长阵亡 · 炮闩损毁 · 起火」
--   · X 光命中回放（右下一个小窗，四五秒）：目标车的外形半透明、里面的乘员和模块按状态上色（绿好、黄伤、红没了 / 毁了），
--     弹芯 / 射流一道橙线、破片一锥黄线（服务器、客户端用同一个伪随机，画出来和算的一样）；镜头从来弹方向慢慢绕
--   · 自己的车挨打：底下一行红字「被击穿：装填手阵亡」；左下车组 / 模块面板（驾 / 炮 / 车 / 装，发 / 传 / 履 / 炮管 / 闩 / 驱 / 弹 / 油），
--     起火、维修进度、「Y 维修 / 灭火」提示；换位「装填手 6 秒后接替炮长」
--   服务器 Wt.lua 发 { op = "wtHit" / "wtHurt" / "wtSwap" / "wtSwapped" / "wtFireOut" / "wtFixed" }，车的状态在实体属性 WtC / WtM / WtF / WtFix
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WtHud = {}

function WtHud.init(G)
  local W = require(RS:WaitForChild("WtDamage"))
  local VD = require(RS:WaitForChild("VehDefs"))
  local XO = nil   -- X 透视（XrayOwn.lua）的共用形状：X 光回放里的乘员也画成零件拼的人
  do
    local ms = script.Parent and script.Parent:FindFirstChild("XrayOwn")
    if ms then
      local ok, r = pcall(require, ms)
      if ok and type(r) == "table" then XO = r end
    end
  end
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MONO = Enum.Font.BuilderSansMedium, Enum.Font.RobotoMono
  local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local OK, HURT, DEAD, GREY = TH.C.GOOD, TH.C.WARN, TH.C.BAD, TH.C.MUTE
  -- 打中的结果（站在开炮的人这边说）：击毁白、击穿琥珀、跳弹 / 没击穿灰（统一外观：红只留给「敌人、危险」）
  local PEN, RIC, KILL = TH.C.WARN, TH.C.MUTE, TH.C.TEXT

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtHud"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 6
  gui.Parent = me:WaitForChild("PlayerGui")

  local function label(parent, text, size, pos, ts, color, font, anchor, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position, l.AnchorPoint = size, pos or UD2(), anchor or V2()
    l.BackgroundTransparency = 1
    l.Text, l.TextSize, l.TextColor3, l.Font = text or "", ts or 14, color or Color3.new(1, 1, 1), font or BOLD
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.35, RGB(0, 0, 0)
    l.Parent = parent
    return l
  end
  local function frame(parent, size, pos, color, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position, f.AnchorPoint = size, pos or UD2(), anchor or V2()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or RGB(0, 0, 0), tr or 0, 0
    f.Parent = parent
    return f
  end

  local function partName(p)
    if p.kind == "crew" then return T("wt.r." .. (p.seat or p.k)) end
    return T("wt.m." .. p.k)
  end
  -- 这一下伤了谁：「炮长阵亡 · 发动机损毁 · 起火」
  local function details(m)
    local bits = {}
    for _, p in ipairs(m.parts or {}) do
      if p.kind == "crew" then
        table.insert(bits, partName(p) .. T((p.s == 0) and "wt.dead" or "wt.hurt"))
      elseif p.s == 0 then
        table.insert(bits, partName(p) .. T("wt.broken"))
      elseif p.s == 1 then
        table.insert(bits, partName(p) .. T("wt.damaged"))
      end
    end
    if m.blow then table.insert(bits, T("wt.blowout")) end
    if m.fire then table.insert(bits, T("wt.onFire")) end
    return table.concat(bits, " · ")
  end

  ---------------------------------------------------------------- 命中提示（打出去的）

  local hitBox = frame(gui, UDim2.fromOffset(640, 52), UD2(0.5, 0, 0.5, 70), RGB(0, 0, 0), 1, V2(0.5, 0))
  hitBox.Name = "WtHitText"
  local hitTop = label(hitBox, "", UD2(1, 0, 0, 24), UD2(0, 0, 0, 0), 20, PEN, TH.F.bold)
  hitTop.Name = "Result"
  local hitSub = label(hitBox, "", UD2(1, 0, 0, 18), UD2(0, 0, 0, 26), 14, TH.C.TEXT)
  hitSub.Name = "Detail"
  hitBox.Visible = false
  local hitUntil = 0
  -- 出现、换内容、消失（11-27 审查）：原来每来一条都从 1.15 倍瞬间跳回去再缩——机炮一秒 3～30 条，缩放永远走不完，正中那行字一直在闪
  --   （docs/style.md「正中：命中提示（一闪就走）」）。现在只在三种时候轻轻弹一下（1.07 倍，0.12 秒）：原来没显示、结果升级了
  --   （击穿 → 击毁 / 致命）、离上次弹超过 0.4 秒；连着来的只换字。到点不再一下子没了：字 0.18 秒淡掉再藏（又来一条就接着显示）
  local HIT_FADE = 0.18
  local hitRank, hitPopAt = 0, -9
  local function hitShown(rank)
    local now = os.clock()
    local was = hitBox.Visible and now <= hitUntil   -- 正在淡出的当成没显示：重新弹出来
    if hitTop.TextTransparency ~= 0 then
      hitTop.TextTransparency, hitTop.TextStrokeTransparency = 0, 0.35
      hitSub.TextTransparency, hitSub.TextStrokeTransparency = 0, 0.35
    end
    hitBox.Visible = true
    if not was or rank > hitRank or now - hitPopAt > 0.4 then
      hitPopAt = now
      if G.uiPop then G.uiPop(hitBox, 1.07) end
    end
    hitRank = was and math.max(hitRank, rank) or rank   -- 显示期间只记最高一级（机炮打车击穿、跳弹混着来，跳弹 → 击穿不算升级）
  end
  local function showHit(m)
    local top, col
    if m.kill then
      top, col = T((m.why == "ammo") and "wt.killAmmo" or ((m.why == "fire") and "wt.killFire" or "wt.kill")), KILL
    elseif m.r == "pen" then top, col = T("wt.pen"), PEN
    elseif m.r == "ric" then top, col = T("wt.ric"), RIC
    elseif m.r == "np" then top, col = T("wt.np"), GREY
    else top, col = T("wt.hit"), PEN end
    hitTop.Text, hitTop.TextColor3 = top, col
    if m.kill then G.wtKillShownAt = os.clock() end   -- Hud.lua 的 G.pop 看到就不再弹第二条「击毁 XX」（屏幕中间只留一处）
    local sub = details(m)
    if (m.r == "np" or m.r == "ric") and m.pen and m.arm then sub = T("wt.mm", m.arm, m.pen) .. ((sub ~= "") and ("   " .. sub) or "") end
    hitSub.Text = sub
    hitShown(m.kill and 3 or ((m.r == "pen") and 2 or 1))
    hitUntil = os.clock() + (m.kill and 3.6 or 2.6)
  end

  -- 飞机（WtAir.lua）：打中了哪块、断翼 / 起火 / 漏油 / 飞行员昏迷
  local function airBits(m)
    local bits, seen = {}, {}
    for _, ev in ipairs(m.ev or {}) do
      if not seen[ev] then seen[ev] = true table.insert(bits, T("wta.e." .. ev)) end
    end
    if #bits == 0 then
      for _, k in ipairs(m.parts or {}) do
        if not seen[k] then seen[k] = true table.insert(bits, T("wta.p." .. k)) end
      end
    end
    return table.concat(bits, " · ")
  end
  local function showAirHit(m)
    local big = false
    for _, ev in ipairs(m.ev or {}) do if ev ~= "leak" then big = true end end
    hitTop.Text = T(big and "wta.crit" or "wt.hit")
    hitTop.TextColor3 = big and KILL or PEN
    hitSub.Text = airBits(m)
    hitShown(big and 3 or 1)
    hitUntil = os.clock() + (big and 3 or 1.6)
  end

  ---------------------------------------------------------------- X 光命中回放

  local XW, XH = mobile and 260 or 380, mobile and 156 or 214   -- 11-28：照战雷的命中回放放大一点（原来 320 × 196，弹药一发发的看不清）
  local xr = frame(gui, UDim2.fromOffset(XW, XH + 22), mobile and UD2(1, -12, 0, 120) or UD2(1, -20, 1, -300), RGB(8, 12, 14), 0.25, V2(1, mobile and 0 or 1))
  xr.Name = "WtXray"
  xr.Visible = false
  do
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = RGB(120, 200, 140), 1, 0.4
    s.Parent = xr
  end
  local xTitle = label(xr, "", UD2(1, -10, 0, 18), UD2(0, 6, 0, 2), 12, Color3.new(1, 1, 1), BOLD, nil, Enum.TextXAlignment.Left)
  local vp = Instance.new("ViewportFrame")
  vp.Name = "View"
  vp.Size, vp.Position = UD2(1, -4, 1, -24), UD2(0, 2, 0, 22)
  -- 11-28（「x光效果还是不如战雷」）：底色石板蓝灰（原来近乎黑：半透明的车壳、部件糊在一起）；环境光压低、主光暖一点，实心部件有明暗
  vp.BackgroundColor3, vp.BackgroundTransparency = RGB(30, 36, 44), 0
  vp.Ambient, vp.LightColor, vp.LightDirection = RGB(118, 124, 134), RGB(255, 248, 236), V3(-0.45, -1, -0.35)
  vp.Parent = xr
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 40
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local xrUntil, xrSpin, xrC, xrDist, xrDir = 0, 0, V3(), 30, V3(0, 0, -1)

  local function box(size, cf, color, tr, mat)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Size = V3(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
    p.CFrame = cf
    p.Color, p.Transparency = color, tr or 0
    p.Material = mat or Enum.Material.SmoothPlastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.Parent = world
    return p
  end
  local function line(a, b, color, th)
    local d = b - a
    if d.Magnitude < 0.05 then return end
    box(V3(th or 0.12, th or 0.12, d.Magnitude), CFrame.lookAt((a + b) / 2, b), color, 0, Enum.Material.Neon)
  end
  local function entModel(id)
    local f = workspace:FindFirstChild("Ents")
    if not f then return nil end
    for _, em in ipairs(f:GetChildren()) do if em:GetAttribute("EntId") == id then return em end end
    return nil
  end
  -- 状态：先看实体属性（服务器刚写的），这一发报来的（m.parts：打到的乘员 / 模块打完以后的状态）盖在上面——
  --   11-28：原来只看属性，开炮的人这边那辆车没流下来（远、刚出生）时全按没事画，打死的驾驶员还是绿的
  local function states(em, d, m)
    local lay = W.layout(d)
    local cs, ms = {}, {}
    local wc = em and em:GetAttribute("WtC")
    local wm = em and em:GetAttribute("WtM")
    local i = 0
    for tok in string.gmatch(wc or "", "[^,]+") do i += 1 cs[i] = tonumber(string.sub(tok, 1, 1)) or 2 end
    for j = 1, #(wm or "") do ms[j] = tonumber(string.sub(wm, j, j)) or 2 end
    local out = {}
    local ci, mi = 0, 0
    for _, it in ipairs(lay.list) do
      if it.kind == "crew" then ci += 1 out[it] = cs[ci] or 2 else mi += 1 out[it] = ms[mi] or 2 end
    end
    if m and m.parts then
      local byK = {}
      for _, it in ipairs(lay.list) do byK[it.k] = it end
      for _, pt in ipairs(m.parts) do
        local it = pt.k and byK[pt.k]
        if it and type(pt.s) == "number" then out[it] = math.min(out[it] or 2, pt.s) end
      end
    end
    return out
  end
  ---------------------------------------------------------------- X 光：射流的慢放动画
  --   用户 11-24 夜「射流弹击中别的坦克的 x 光动画要有特殊效果」：破甲 / 金属射流弹打穿时 X 光窗口里慢放——
  --   ① 弹飞进来（镜头从侧面推近到命中点）② 打上装甲：一团白闪、贴着装甲面一圈冲击波、窗口整个亮一下、镜头一震，弹坑烧红再冷下去
  --   ③ 白热的射流一点点钻进车里（越往里越慢），射流头一颗亮球、光套跳动，经过的地方甩出熔化的金属珠（白 → 橙 → 暗红），
  --      后面一截慢的杵体（真的聚能装药：射流头每秒七八公里，杵体只有几百米）④ 破片一根根往外长，打到的乘员 / 模块闪红再定色
  --   ⑤ 弹药殉爆一团火球 / 起火一簇火 ⑥ 镜头拉回来看整辆车、慢慢绕；底下一行字：穿深 / 等效毫米（击毁时换成「弹药殉爆」）
  local xInfo = label(xr, "", UD2(1, -12, 0, 30), UD2(0, 6, 1, -33), 12, RGB(200, 236, 255), BOLD, nil, Enum.TextXAlignment.Left)
  xInfo.Name = "XrInfo"
  xInfo.ZIndex = 3
  xInfo.TextWrapped, xInfo.TextYAlignment = true, Enum.TextYAlignment.Bottom   -- 长的字幕（弹种说明 + 穿深）折成两行，不再出框
  xInfo.TextStrokeTransparency, xInfo.TextStrokeColor3 = 0.45, RGB(10, 14, 18)
  local xSlow = label(xr, "", UD2(0, 90, 0, 14), UD2(1, -8, 0, 26), 11, RGB(255, 210, 120), BOLD, V2(1, 0), Enum.TextXAlignment.Right)
  xSlow.Name = "XrSlow"
  xSlow.ZIndex = 3
  local xStroke = xr:FindFirstChildOfClass("UIStroke")
  local VP_BG, XR_LINE, INFO = RGB(30, 36, 44), TH.C.HUD, TH.C.TEXT
  -- 没事的部件按类别的颜色（实心打光；照战雷的命中回放：一眼分得出弹药、油箱、发动机、乘员）
  local XC = {
    crew = RGB(160, 188, 136), troops = RGB(160, 188, 136), ammo = RGB(206, 170, 102), fuel = RGB(114, 130, 98),
    engine = RGB(140, 148, 158), trans = RGB(122, 134, 150), breech = RGB(114, 120, 128), barrel = RGB(114, 120, 128),
    tdrive = RGB(128, 136, 148), optics = RGB(96, 170, 180), track = RGB(94, 98, 104), other = RGB(130, 138, 148),
  }
  local KIA = RGB(128, 30, 26)   -- 乘员阵亡：暗红（毁了的模块是亮红 DEAD）
  local BLACKC = Color3.new(0, 0, 0)
  local function xrCol(kind, cat, s, hit)   -- 一件的颜色：状态（伤琥珀、毁红、阵亡暗红）、没事的按类别；这一发没打到的往底色退一点
    if kind == "crew" then return (s == 0) and KIA or ((s == 1) and HURT or XC.crew) end
    if s == 0 then return DEAD elseif s == 1 then return HURT end
    local c = XC[cat] or XC.other
    return hit and c or c:Lerp(VP_BG, 0.22)
  end
  local function xrTr(kind, s, hit)   -- 乘员、打到的、伤了毁了的实心；没打到的没事模块淡一点（打到的才醒目）
    if kind == "crew" or s < 2 or hit then return 0 end
    return 0.35
  end
  local function xrSub(col, g, s, cat)   -- 一件里的子件：深色件（排气、缸盖、炮管的箍）、弹头、玻璃
    if g == "dk" then return col:Lerp(BLACKC, 0.3) end
    if g == "tip" then return (s == 2) and RGB(78, 82, 90) or col:Lerp(BLACKC, 0.35) end
    if g == "gl" then return (s == 2) and RGB(130, 206, 214) or col end
    return col
  end
  local TI, JD = 0.7, 0.95   -- 弹飞进来 0.7 秒；射流钻进去 0.95 秒（都是慢放的）
  local xa = nil
  local function ease(q) q = math.clamp(q, 0, 1) return 1 - (1 - q) ^ 2.4 end
  local function lerp(a, b, q) return a + (b - a) * q end
  local function rng(seed)   -- 确定的伪随机（同一发每次放出来一样）
    local s = math.floor(seed or 1) % 2147483647
    if s <= 0 then s = 1 end
    return function() s = (s * 16807) % 2147483647 return s / 2147483647 end
  end
  local function nb(size, cf, col, shape)   -- 一个发光件，先藏着
    local p = box(size, cf, col, 1, Enum.Material.Neon)
    if shape then p.Shape = shape end
    return p
  end
  local function seg(p, a, b, th)   -- 把一根件摆成 a → b
    local L = (b - a).Magnitude
    if L < 0.03 then p.Transparency = 1 return false end
    p.Size = V3(th, th, L)
    p.CFrame = CFrame.lookAt((a + b) / 2, b)
    return true
  end
  local function heat(q, c0, c1, c2, k)   -- 白热 → 橙 → 暗红（k 那一点到橙）
    if q < k then return c0:Lerp(c1, q / k) end
    return c1:Lerp(c2, math.clamp((q - k) / (1 - k), 0, 1))
  end
  local WHITE, ORANGE, EMBER = RGB(255, 246, 225), RGB(255, 150, 55), RGB(140, 32, 22)

  local function xaBuild(m, x, d, yaw, p0, dv, hitP)
    local big = x.big == true
    local M = W.M
    local core = math.max((x.core or 0) * M, 1.2)
    local R = rng(x.seed)
    local A = { t0 = os.clock(), p0 = p0, dv = dv, core = core, big = big, hitP = hitP }
    A.shell = nb(V3(0.24, 0.24, 1.2), CF(p0 - dv * 12), RGB(255, 205, 130))
    A.trail = nb(V3(0.08, 0.08, 0.1), CF(p0 - dv * 12), RGB(255, 120, 40))
    -- 装甲面的法线（冲击波贴着它扩开）：炮塔上的按炮塔转角换回底座系
    local zone, _, _, n = W.where(d, p0, dv, yaw)
    if zone == "tur" and n then n = W.fromTur(d, n, yaw) - W.fromTur(d, V3(), yaw) end
    if not n or n.Magnitude < 0.5 then n = -dv end
    n = n.Unit
    A.flash = nb(V3(1, 1, 1), CF(p0), RGB(255, 255, 255), Enum.PartType.Ball)
    A.ring = nb(V3(0.05, 1, 1), CFrame.lookAt(p0 + n * 0.06, p0 + n * 1.06) * CFrame.Angles(0, math.pi / 2, 0), RGB(200, 230, 255), Enum.PartType.Cylinder)
    A.crater = nb(V3(0.9, 0.9, 0.9), CF(p0), ORANGE, Enum.PartType.Ball)
    -- 射流：白热的芯、青白的光套、外面一层淡光，射流头一颗亮球，后面一截慢的杵体
    local w = big and 0.2 or 0.15
    A.w = w
    A.jet = nb(V3(w, w, 0.1), CF(p0), RGB(245, 252, 255))
    A.glow = nb(V3(w, w, 0.1), CF(p0), RGB(130, 205, 255))
    A.halo = nb(V3(w, w, 0.1), CF(p0), RGB(90, 160, 255))
    A.tip = nb(V3(1, 1, 1), CF(p0), RGB(255, 255, 255), Enum.PartType.Ball)
    A.slug = nb(V3(w * 2.4, w * 2.4, w * 5.5), CF(p0), RGB(255, 200, 120))
    -- 熔化的金属珠：射流头经过那一刻甩出来（射流头的位置 = core · ease(τ / JD)，反过来求经过的时刻）
    A.beads = {}
    local r1 = dv:Cross(math.abs(dv.Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)).Unit
    local r2 = dv:Cross(r1).Unit
    local NB = big and 26 or 16
    for i = 1, NB do
      local u = (i - 0.5) / NB * 0.94
      local a = R() * math.pi * 2
      local v = (r1 * math.cos(a) + r2 * math.sin(a)) * (0.5 + R() * 1.7) + dv * (R() * 0.9 - 0.25)
      table.insert(A.beads, { p = nb(V3(0.3, 0.3, 0.3), CF(p0), WHITE, Enum.PartType.Ball), u = u, v = v, s = 0.16 + R() * 0.24,
        t = TI + JD * (1 - (1 - u) ^ (1 / 2.4)) })
    end
    -- 打到的乘员 / 模块什么时候「到」：射流经过、破片打到，都没有就在射流快钻完时
    local function mark(it, tt)
      for _, H in ipairs(hitP) do if H.it == it and (not H.at or tt < H.at) then H.at = tt end end
    end
    for _, h in ipairs(W.trace(d, yaw, p0 + dv * 0.1, dv, core, true)) do
      mark(h.it, TI + JD * (1 - (1 - math.clamp(h.t / core, 0, 1)) ^ (1 / 2.4)))
    end
    A.spall = {}
    local cone = W.cone(dv, x.half or 18, x.n or 0, x.seed)
    for i, rv in ipairs(cone) do
      local len = (1.4 + (i % 4) * 0.35) * M
      local hits = W.trace(d, yaw, p0 + dv * 0.1, rv, len, true)
      local l2 = hits[1] and math.max(0.3, hits[1].t + 0.4) or len
      local t1 = TI + 0.14 + (i - 1) * (0.55 / math.max(#cone, 1)) + R() * 0.05
      local dur = 0.26 + l2 / M * 0.07
      table.insert(A.spall, { p = nb(V3(0.06, 0.06, 0.1), CF(p0), RGB(255, 240, 150)), tip = nb(V3(0.26, 0.26, 0.26), CF(p0), RGB(255, 250, 220), Enum.PartType.Ball),
        rv = rv, len = l2, t = t1, d = dur })
      if hits[1] then mark(hits[1].it, t1 + dur * 0.45) end
    end
    for _, H in ipairs(hitP) do
      if not H.at then H.at = W.inside(d, yaw, p0, H.it, 0.6) and TI or (TI + JD * 0.8) end   -- 车外的零件（履带、炮管）：打上那一下
    end
    -- 击毁：弹药殉爆（打到的那个弹药架）、起火（打到的油箱 / 发动机）
    local lay = W.layout(d)
    local hk = {}
    for _, H in ipairs(hitP) do hk[H.it.k] = H.it end
    local function find(keys)
      for _, k in ipairs(keys) do if hk[k] then return hk[k] end end
      for _, k in ipairs(keys) do for _, it in ipairs(lay.list) do if it.k == k then return it end end end
      return nil
    end
    if m.kill and m.why == "ammo" then
      local it = find({ "ammo", "ammoH" })
      if it then
        A.boom = nb(V3(1, 1, 1), CF(W.center(d, yaw, it)), WHITE, Enum.PartType.Ball)
        A.boomR = math.max(d.W or 6, 6) * 1.1
        A.boomT = TI + JD + 0.3
      end
    end
    if m.fire or (m.kill and m.why == "fire") then
      local it = find({ "fuelL", "fuelR", "engine", "ammoH" })
      if it then
        local c = W.center(d, yaw, it)
        A.fire, A.fireT = {}, TI + JD + (A.boom and 0.9 or 0.35)
        for i = 1, 4 do
          table.insert(A.fire, { p = nb(V3(1, 1, 1), CF(c), (i % 2 == 0) and RGB(255, 190, 70) or RGB(255, 110, 40), Enum.PartType.Ball),
            c = c + V3((R() - 0.5) * 1.6, (i - 1) * 0.45, (R() - 0.5) * 1.6), s = 1.1 + R() * 0.8 })
        end
      end
    end
    if x.tan then   -- 串联破甲：主装药前面一小段，前级先炸一下（引爆爆反、开路）
      A.pre = nb(V3(1, 1, 1), CF(p0 - dv * 0.9), RGB(255, 236, 200), Enum.PartType.Ball)
      A.preR = nb(V3(0.05, 1, 1), CFrame.lookAt(p0 - dv * 0.9, p0 - dv * 1.9) * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 210, 150), Enum.PartType.Cylinder)
    end
    A.info = T(big and "wt.xrJetB" or (x.tan and "wt.xr.tandem" or "wt.xrJet"), m.pen or "?", m.arm or "?")
    A.info2 = m.kill and T((m.why == "ammo") and "wt.killAmmo" or ((m.why == "fire") and "wt.killFire" or "wt.kill")) or nil
    return A
  end

  local function xaStep(t, dt)
    local A = xa
    local p0, dv, core, w = A.p0, A.dv, A.core, A.w
    local ti = t - TI
    -- 串联：前级在主装药打上前 0.14 秒先炸一小团
    if A.pre then
      local pq = (t - (TI - 0.14)) / 0.32
      if pq >= 0 and pq < 1 then
        A.pre.Size, A.pre.Transparency = V3(1, 1, 1) * lerp(0.4, 2.6, ease(pq)), pq
        A.preR.Size, A.preR.Transparency = V3(0.05, lerp(0.4, 3.4, ease(pq)), lerp(0.4, 3.4, ease(pq))), lerp(0.25, 1, pq)
      else A.pre.Transparency, A.preR.Transparency = 1, 1 end
    end
    -- ① 弹飞进来，尾巴拖一道曳光
    if ti < 0 then
      local sp = p0 - dv * (12 * (1 - t / TI))
      A.shell.CFrame = CFrame.lookAt(sp, sp + dv)
      A.shell.Transparency = 0
      if seg(A.trail, p0 - dv * 12, sp - dv * 0.6, 0.08) then A.trail.Transparency = 0.2 end
    else
      A.shell.Transparency = 1
      if seg(A.trail, p0 - dv * 12, p0, 0.08) then A.trail.Transparency = math.clamp(0.2 + ti * 0.4, 0.2, 0.7) end
    end
    if ti >= 0 then
      -- ② 命中：白闪、冲击波、弹坑；窗口亮一下、框变橙
      local fq = ti / 0.35
      A.flash.Transparency = (fq < 1) and fq or 1
      A.flash.Size = V3(1, 1, 1) * lerp(0.6, A.big and 4.4 or 3.4, ease(fq))
      local rq = ti / 0.6
      local r = lerp(0.4, A.big and 7.5 or 5.5, ease(rq))
      A.ring.Size = V3(0.05, r, r)
      A.ring.Transparency = (rq < 1) and lerp(0.15, 1, rq) or 1
      local cq = math.clamp(ti / 2.4, 0, 1)
      A.crater.Color = heat(cq, WHITE, ORANGE, EMBER, 0.2)
      A.crater.Transparency = lerp(0, 0.3, cq)
      vp.BackgroundColor3 = RGB(190, 222, 255):Lerp(VP_BG, math.clamp(ti / 0.3, 0, 1))
      if xStroke then xStroke.Color = RGB(255, 190, 110):Lerp(XR_LINE, math.clamp(ti / 1.2, 0, 1)) end
      -- ③ 射流
      local jq = ti / JD
      local a = p0 + dv * 0.05
      local pulse = 1 + 0.22 * math.sin(t * 47) + 0.12 * math.sin(t * 83)
      if jq < 1 then
        local b = p0 + dv * math.max(core * ease(jq), 0.08)
        if seg(A.jet, a, b, w) then A.jet.Transparency = 0 end
        if seg(A.glow, a, b, w * 3.2 * pulse) then A.glow.Transparency = 0.45 end
        if seg(A.halo, a, b, w * 7 * pulse) then A.halo.Transparency = 0.82 end
        A.tip.CFrame, A.tip.Size, A.tip.Transparency = CF(b), V3(1, 1, 1) * w * 4.6 * pulse, 0
      else   -- 射流用完了：芯子冷成一道烧红的孔道，光套、射流头淡掉
        local b = p0 + dv * core
        local cq2 = math.clamp((ti - JD) / 1.6, 0, 1)
        if seg(A.jet, a, b, w * lerp(1, 0.7, cq2)) then
          A.jet.Color = RGB(245, 252, 255):Lerp(RGB(255, 110, 50), cq2)
          A.jet.Transparency = lerp(0, 0.25, cq2)
        end
        if seg(A.glow, a, b, w * 3.2) then A.glow.Transparency = lerp(0.45, 1, cq2) end
        A.halo.Transparency = 1
        A.tip.Transparency = math.clamp((ti - JD) / 0.25, 0, 1)
      end
      -- 杵体：跟在后面慢慢走，只走到射流长度的三成多
      if ti > 0.1 then
        local sq = math.clamp((ti - 0.1) / (JD * 1.7), 0, 1)
        local sp = p0 + dv * (core * 0.36 * ease(sq))
        A.slug.CFrame = CFrame.lookAt(sp, sp + dv)
        A.slug.Color = heat(sq, RGB(255, 215, 140), ORANGE, EMBER, 0.35)
        A.slug.Transparency = lerp(0.05, 0.35, sq)
      end
      -- 熔化的金属珠：往外甩、慢慢往下掉、冷下去
      for _, B in ipairs(A.beads) do
        local bt = t - B.t
        if bt >= 0 then
          local q = bt / 1.5
          if q < 1 then
            B.p.CFrame = CF(p0 + dv * (core * B.u) + B.v * ease(q) + V3(0, -0.7 * q * q, 0))
            B.p.Size = V3(1, 1, 1) * lerp(B.s, B.s * 0.45, q)
            B.p.Color = heat(q, WHITE, ORANGE, EMBER, 0.3)
            B.p.Transparency = lerp(0, 0.65, q)
          else B.p.Transparency = 1 end
        end
      end
    end
    -- ④ 破片一根根往外长（头上一颗亮点），长完从黄冷成橙
    for _, Sx in ipairs(A.spall) do
      local st = t - Sx.t
      if st >= 0 then
        local q = st / Sx.d
        local cur = Sx.len * ease(q)
        if seg(Sx.p, p0, p0 + Sx.rv * math.max(cur, 0.06), 0.06) then
          if q < 1 then
            Sx.p.Color, Sx.p.Transparency = RGB(255, 240, 150), 0
            Sx.tip.CFrame, Sx.tip.Transparency = CF(p0 + Sx.rv * cur), 0
          else
            local fq = math.clamp((st - Sx.d) / 1.2, 0, 1)
            Sx.p.Color, Sx.p.Transparency = RGB(255, 226, 90):Lerp(RGB(255, 140, 50), fq), lerp(0, 0.3, fq)
            Sx.tip.Transparency = 1
          end
        end
      end
    end
    -- ⑤ 打到的乘员 / 模块：到的那一刻红白闪、胀一下，再定成最后的颜色（乘员是零件拼的人：H.ps 每个零件一起闪）
    for _, H in ipairs(A.hitP) do
      local ht = t - H.at
      if ht >= 0 then
        if ht < 0.7 then
          local fc = (math.floor(ht * 14) % 2 == 0) and RGB(255, 255, 255) or RGB(255, 40, 30)
          local gk = 1 + 0.3 * (1 - ht / 0.7)
          for _, q in ipairs(H.ps or { H }) do
            q.p.Color, q.p.Transparency, q.p.Size = fc, 0, q.size * gk
          end
        elseif not H.done then
          H.done = true
          for _, q in ipairs(H.ps or { H }) do q.p.Color, q.p.Transparency, q.p.Size = xrSub(H.col, q.g, H.s or 2, H.cat), H.tr, q.size end
        end
      end
    end
    -- ⑥ 弹药殉爆、起火
    if A.boom and t >= A.boomT then
      local q = (t - A.boomT) / 1.2
      if q < 1 then
        A.boom.Size = V3(1, 1, 1) * lerp(1, A.boomR, ease(q))
        A.boom.Color = heat(q, WHITE, ORANGE, EMBER, 0.3)
        A.boom.Transparency = lerp(0.05, 1, q ^ 1.5)
        vp.BackgroundColor3 = RGB(255, 170, 90):Lerp(VP_BG, math.clamp(q * 3, 0, 1))
      else A.boom.Transparency = 1 end
    end
    if A.fire and t >= A.fireT then
      for i, F in ipairs(A.fire) do
        local fl = 0.75 + 0.22 * math.sin(t * (9 + i * 3.7) + i) + 0.14 * math.sin(t * 23 + i * 2)
        F.p.Size = V3(1, 1, 1) * F.s * fl
        F.p.CFrame = CF(F.c + V3(0, (fl - 0.6) * 0.9, 0))
        F.p.Transparency = 0.25
      end
    end
    -- 字幕
    if ti >= 0 and not A.said then A.said = true xInfo.Text, xInfo.TextColor3, xInfo.Visible = A.info, INFO, true end
    if A.info2 and not A.said2 and t >= (A.boomT or (TI + JD)) + 0.15 then A.said2 = true xInfo.Text, xInfo.TextColor3 = A.info2, KILL end
    xSlow.Visible = t < TI + JD + 0.4
    -- 镜头：先从斜侧面推近到命中点（跟一点射流），射流钻完拉回来看整辆车、慢慢绕；打上那一下一震
    xrSpin += dt * ((t < TI + JD) and math.rad(7) or math.rad(16))
    local back = ease((t - (TI + JD + 0.2)) / 1.1)
    local tgt = (p0 + dv * math.min(core * 0.35 * ease(ti / JD), 3)):Lerp(xrC, back)
    local dist = lerp(lerp(xrDist * 0.95, xrDist * 0.48, ease(t / TI)), xrDist, back)
    local eye = tgt + CFrame.Angles(0, xrSpin, 0) * xrDir * dist + V3(0, dist * 0.32, 0)
    if ti >= 0 and ti < 0.5 then
      local k = (1 - ti / 0.5) ^ 2 * (A.big and 0.45 or 0.32)
      eye += V3(math.sin(t * 91) * k, math.sin(t * 73 + 1) * k, math.sin(t * 57 + 2) * k)
    end
    vcam.CFrame = CFrame.lookAt(eye, tgt)
  end

  ---------------------------------------------------------------- X 光：动能弹、穿甲爆破、杀爆、碎甲的慢放（用户待办「不同弹种击中的 X 光效果不一样」）
  --   服务器给 x.sub（Wt.lua xrSub），这里一种一个样子（伤害上的区别在 Wt.lua SUBFX）：
  --   fs 长杆尾翼稳定脱壳穿甲弹：细长的杆扎进去，杆头被装甲啃短（入口往回溅一圈火花），里面一道窄而密的破片锥，剩下的杆接着往里钻
  --   ds 脱壳穿甲弹：粗短的钨芯，钻得浅一点、破片锥宽一点
  --   ap 全口径穿甲弹：胖弹头把一块烧红的装甲塞子顶进车里，破片锥最宽、块头最大
  --   aphe 穿甲爆破弹：先像 ap 一样钻进去，走一米多（引信延时）在车里炸开——一团火、破片四面八方、窗口一片橙
  --   ac 机炮 / 机枪的小弹：小闪、细孔、几片
  --   he 杀爆弹：在车外炸开——半个火球、贴着装甲的大冲击波、破片往外飞，烟往上冒；薄皮车才有几片钻进来
  --   hesh 碎甲弹：弹头拍扁成一张饼贴在装甲上、起爆，冲击波一圈圈穿过装甲，内壁烧红、崩成一大锥碎片往里飞（装甲没有洞）
  local KS = {
    fs = { len = 2.6, w = 0.09, col = RGB(255, 238, 180), TI = 0.5, P = 0.42, back = 10, deep = 1, erode = 0.6 },
    ds = { len = 1.5, w = 0.17, col = RGB(235, 235, 245), TI = 0.55, P = 0.48, back = 7, deep = 0.9, erode = 0.35 },
    ap = { len = 1.15, w = 0.38, col = RGB(205, 175, 120), TI = 0.62, P = 0.6, back = 4, deep = 1, plug = true, wide = true },
    aphe = { len = 1.15, w = 0.38, col = RGB(205, 175, 120), TI = 0.62, P = 0.6, back = 4, deep = 1, plug = true, wide = true, burst = 1.2 },
    ac = { len = 0.6, w = 0.07, col = RGB(255, 220, 150), TI = 0.4, P = 0.3, back = 4, deep = 1, small = true },
    he = { len = 1.0, w = 0.42, col = RGB(126, 132, 100), TI = 0.62, P = 0.5, blast = true },
    hesh = { len = 1.0, w = 0.44, col = RGB(160, 158, 118), TI = 0.62, P = 0.6, scab = true },
  }
  -- 方向随机散在一个锥里（半角 deg）
  local function coneDir(R, axis, deg)
    local a = R() * math.pi * 2
    local th = math.rad(deg) * math.sqrt(R())
    local u1 = axis:Cross(math.abs(axis.Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)).Unit
    local u2 = axis:Cross(u1).Unit
    return (axis * math.cos(th) + (u1 * math.cos(a) + u2 * math.sin(a)) * math.sin(th)).Unit
  end
  -- 击毁：弹药殉爆（打到的那个弹药架）、起火（打到的油箱 / 发动机），tB 殉爆的时刻
  local function killFx(A, m, d, yaw, hitP, R, tB)
    local lay = W.layout(d)
    local hk = {}
    for _, H in ipairs(hitP) do hk[H.it.k] = H.it end
    local function find(keys)
      for _, k in ipairs(keys) do if hk[k] then return hk[k] end end
      for _, k in ipairs(keys) do for _, it in ipairs(lay.list) do if it.k == k then return it end end end
      return nil
    end
    if m.kill and m.why == "ammo" then
      local it = find({ "ammo", "ammoH" })
      if it then
        A.boom = nb(V3(1, 1, 1), CF(W.center(d, yaw, it)), WHITE, Enum.PartType.Ball)
        A.boomR = math.max(d.W or 6, 6) * 1.1
        A.boomT = tB
      end
    end
    if m.fire or (m.kill and m.why == "fire") then
      local it = find({ "fuelL", "fuelR", "engine", "ammoH" })
      if it then
        local c = W.center(d, yaw, it)
        A.fire, A.fireT = {}, tB + (A.boom and 0.6 or 0.05)
        for i = 1, 4 do
          table.insert(A.fire, { p = nb(V3(1, 1, 1), CF(c), (i % 2 == 0) and RGB(255, 190, 70) or RGB(255, 110, 40), Enum.PartType.Ball),
            c = c + V3((R() - 0.5) * 1.6, (i - 1) * 0.45, (R() - 0.5) * 1.6), s = 1.1 + R() * 0.8 })
        end
      end
    end
  end
  -- 一根往外长的破片（头上一颗亮点）：o 起点、rv 方向、len 长、t 开始、d 长出来用的时间
  local function frag(list, o, rv, len, t, dur, th, col)
    table.insert(list, { p = nb(V3(th, th, 0.1), CF(o), col or RGB(255, 240, 150)), tip = nb(V3(th * 3.4, th * 3.4, th * 3.4), CF(o), RGB(255, 250, 220), Enum.PartType.Ball),
      o = o, rv = rv, len = len, t = t, d = dur, th = th })
  end
  local function fragStep(list, t)
    for _, F in ipairs(list) do
      local ft = t - F.t
      if ft >= 0 then
        local q = ft / F.d
        local cur = F.len * ease(q)
        if seg(F.p, F.o, F.o + F.rv * math.max(cur, 0.06), F.th) then
          if q < 1 then
            F.p.Color, F.p.Transparency = RGB(255, 240, 150), 0
            F.tip.CFrame, F.tip.Transparency = CF(F.o + F.rv * cur), 0
          else
            local fq = math.clamp((ft - F.d) / 1.2, 0, 1)
            F.p.Color, F.p.Transparency = RGB(255, 226, 90):Lerp(RGB(255, 140, 50), fq), lerp(0, 0.35, fq)
            F.tip.Transparency = 1
          end
        end
      end
    end
  end

  local function xkBuild(m, x, d, yaw, p0, dv, hitP, sub)
    local K = KS[sub]
    local M = W.M
    local R = rng(x.seed)
    local A = { t0 = os.clock(), p0 = p0, dv = dv, K = K, sub = sub, hitP = hitP, TI = K.TI, P = K.P, frags = {}, back = {} }
    A.step = nil   -- 下面赋值（xkStep 在后面定义）
    A.core = math.max((x.core or 0) * M, K.small and 0.6 or 1.0)
    local zone, _, _, n = W.where(d, p0, dv, yaw)
    if zone == "tur" and n then n = W.fromTur(d, n, yaw) - W.fromTur(d, V3(), yaw) end
    if not n or n.Magnitude < 0.5 then n = -dv end
    n = n.Unit
    A.n = n
    A.shell = nb(V3(K.w, K.w, K.len), CF(p0 - dv * 12), K.col)
    A.trail = nb(V3(0.06, 0.06, 0.1), CF(p0 - dv * 12), RGB(255, 140, 50))
    A.flash = nb(V3(1, 1, 1), CF(p0), RGB(255, 255, 255), Enum.PartType.Ball)
    A.ring = nb(V3(0.05, 1, 1), CFrame.lookAt(p0 + n * 0.06, p0 + n * 1.06) * CFrame.Angles(0, math.pi / 2, 0), RGB(220, 235, 255), Enum.PartType.Cylinder)
    A.crater = nb(V3(0.7, 0.7, 0.7), CF(p0), ORANGE, Enum.PartType.Ball)
    local function mark(it, tt)
      for _, H in ipairs(hitP) do if H.it == it and (not H.at or tt < H.at) then H.at = tt end end
    end
    -- 往回溅的火花（杆头被装甲啃下来的碎渣）
    for _ = 1, (K.back or 0) do
      table.insert(A.back, { p = nb(V3(0.16, 0.16, 0.16), CF(p0), WHITE, Enum.PartType.Ball), v = coneDir(R, n, 55) * (1.2 + R() * 2.2), t = K.TI + R() * 0.12, s = 0.1 + R() * 0.14 })
    end
    local half = x.half or 18
    local nF = math.max(4, x.n or 10)
    if K.blast then
      -- 杀爆：车外炸开（火球半个露在外面）、烟往上冒，破片往外飞；打穿了（薄皮车）几片钻进来
      A.fbR = math.max((x.bl or 2.2) * M * 0.45, 2.4)
      A.fb = nb(V3(1, 1, 1), CF(p0 + n * 0.4), WHITE, Enum.PartType.Ball)
      A.smoke = nb(V3(1, 1, 1), CF(p0 + n * 1.2), RGB(92, 90, 86), Enum.PartType.Ball)
      for _ = 1, 16 do frag(A.frags, p0 + n * 0.2, coneDir(R, n, 78), (1.6 + R() * 1.8) * M, K.TI + R() * 0.06, 0.32 + R() * 0.2, 0.07, RGB(255, 220, 130)) end
      if m.r == "pen" or m.kill then
        for _ = 1, 6 do
          local rv = coneDir(R, dv, 35)
          local len = (0.8 + R() * 0.8) * M
          local hits = W.trace(d, yaw, p0 + dv * 0.2, rv, len, true)
          local l2 = hits[1] and math.max(0.3, hits[1].t + 0.3) or len
          local t1 = K.TI + 0.06 + R() * 0.08
          frag(A.frags, p0 + dv * 0.2, rv, l2, t1, 0.26, 0.06)
          if hits[1] then mark(hits[1].it, t1 + 0.15) end
        end
      end
    elseif K.scab then
      -- 碎甲：拍扁的炸药饼、穿过装甲的冲击波、内壁烧红崩落成一大锥
      A.pan = nb(V3(0.4, 0.4, 0.4), CFrame.lookAt(p0 + n * 0.08, p0 + n * 1.08) * CFrame.Angles(0, math.pi / 2, 0), RGB(232, 214, 150), Enum.PartType.Cylinder)
      A.wave = nb(V3(0.05, 1, 1), CF(p0), RGB(200, 230, 255), Enum.PartType.Cylinder)
      local inner = p0 + dv * 0.3 * M
      A.inner = inner
      A.scab = nb(V3(0.16, 1.3, 1.3), CFrame.lookAt(inner, inner + dv) * CFrame.Angles(0, math.pi / 2, 0), ORANGE, Enum.PartType.Cylinder)
      for _ = 1, math.floor(nF * 1.6 + 0.5) do
        local rv = coneDir(R, dv, half * 2.4)
        local len = (1.0 + R() * 1.3) * M
        local hits = W.trace(d, yaw, inner, rv, len, true)
        local l2 = hits[1] and math.max(0.3, hits[1].t + 0.3) or len
        local t1 = K.TI + 0.42 + R() * 0.1
        local dur = 0.24 + l2 / M * 0.06
        frag(A.frags, inner, rv, l2, t1, dur, 0.09, RGB(255, 214, 130))
        if hits[1] then mark(hits[1].it, t1 + dur * 0.5) end
      end
    else
      -- 动能弹：孔道、杆头、（全口径）装甲塞子；破片从穿出来的地方喷；穿甲爆破弹走一米多炸开
      A.chan = nb(V3(K.w, K.w, 0.1), CF(p0), RGB(255, 200, 120))
      A.chanGlow = nb(V3(K.w, K.w, 0.1), CF(p0), RGB(255, 140, 60))
      if K.plug then A.plug = nb(V3(0.14, 1.0, 1.0), CF(p0), RGB(255, 160, 80), Enum.PartType.Cylinder) end
      local deep = A.core * (K.deep or 1)
      A.deep = deep
      local function tOf(dist) return K.TI + K.P * (1 - (1 - math.clamp(dist / deep, 0, 1)) ^ (1 / 2.4)) end
      for _, h in ipairs(W.trace(d, yaw, p0 + dv * 0.1, dv, deep, true)) do mark(h.it, tOf(h.t)) end
      local ex = p0 + dv * (K.small and 0.15 or 0.35)
      local nS = K.wide and math.floor(nF * 1.25 + 0.5) or nF
      if sub == "aphe" then nS = math.floor(nF * 0.6 + 0.5) end
      for i = 1, nS do
        local rv = coneDir(R, dv, half * (K.wide and 1.6 or (sub == "fs" and 0.8 or 1.1)))
        local len = (1.2 + R() * 1.3) * M * (K.small and 0.5 or 1)
        local hits = W.trace(d, yaw, ex, rv, len, true)
        local l2 = hits[1] and math.max(0.3, hits[1].t + 0.4) or len
        local t1 = K.TI + 0.06 + (i - 1) * (0.35 / nS) + R() * 0.04
        local dur = 0.22 + l2 / M * 0.06
        frag(A.frags, ex, rv, l2, t1, dur, (K.wide and 0.1 or 0.06) * (0.8 + R() * 0.6))
        if hits[1] then mark(hits[1].it, t1 + dur * 0.45) end
      end
      if K.burst then
        local bd = math.min(deep, K.burst * M)
        A.bp, A.tb = p0 + dv * bd, tOf(bd)
        A.fb = nb(V3(1, 1, 1), CF(A.bp), WHITE, Enum.PartType.Ball)
        for _ = 1, 18 do
          local rv = coneDir(R, dv, 175)
          local len = (1.0 + R() * 1.0) * M
          local hits = W.trace(d, yaw, A.bp, rv, len, true)
          local l2 = hits[1] and math.max(0.3, hits[1].t + 0.3) or len
          local dur = 0.18 + l2 / M * 0.05
          local t1 = A.tb + R() * 0.05
          frag(A.frags, A.bp, rv, l2, t1, dur, 0.07, RGB(255, 210, 110))
          if hits[1] then mark(hits[1].it, t1 + dur * 0.5) end
        end
      end
    end
    for _, H in ipairs(hitP) do
      if not H.at then H.at = W.inside(d, yaw, p0, H.it, 0.6) and K.TI or (K.TI + K.P * 0.8) end
    end
    killFx(A, m, d, yaw, hitP, R, (A.tb or (K.TI + K.P)) + 0.35)
    A.info = T("wt.xr." .. sub, m.pen or "?", m.arm or "?")
    A.info2 = m.kill and T((m.why == "ammo") and "wt.killAmmo" or ((m.why == "fire") and "wt.killFire" or "wt.kill")) or nil
    return A
  end

  local function xkStep(t, dt)
    local A = xa
    local K, p0, dv, n = A.K, A.p0, A.dv, A.n
    local TIk, Pk = A.TI, A.P
    local ti = t - TIk
    -- ① 飞进来，尾巴拖一道曳光
    if ti < 0 then
      local sp = p0 - dv * (12 * (1 - t / TIk) + K.len * 0.5)
      A.shell.CFrame = CFrame.lookAt(sp, sp + dv)
      A.shell.Transparency = 0
      if seg(A.trail, p0 - dv * 12, sp - dv * K.len * 0.5, 0.06) then A.trail.Transparency = 0.25 end
    elseif seg(A.trail, p0 - dv * 12, p0, 0.06) then
      A.trail.Transparency = math.clamp(0.25 + ti * 0.5, 0.25, 1)
    end
    if ti >= 0 then
      -- ② 打上：白闪、贴着装甲的一圈、弹坑烧红；窗口亮一下、框变橙
      local fq = ti / 0.3
      A.flash.Transparency = (fq < 1) and fq or 1
      A.flash.Size = V3(1, 1, 1) * lerp(0.4, (K.small and 1.4) or (K.blast and 5) or 2.8, ease(fq))
      local rq = ti / 0.55
      local r = lerp(0.3, (K.blast and 9) or (K.scab and 6) or (K.small and 2) or 4.5, ease(rq))
      A.ring.Size = V3(0.05, r, r)
      A.ring.Transparency = (rq < 1) and lerp(0.2, 1, rq) or 1
      local cq = math.clamp(ti / 2.2, 0, 1)
      A.crater.Color = heat(cq, WHITE, ORANGE, EMBER, 0.2)
      A.crater.Transparency = lerp(0, 0.35, cq)
      vp.BackgroundColor3 = RGB(190, 222, 255):Lerp(VP_BG, math.clamp(ti / 0.25, 0, 1))
      if xStroke then xStroke.Color = RGB(255, 190, 110):Lerp(XR_LINE, math.clamp(ti / 1.2, 0, 1)) end
      if K.blast or K.scab then A.shell.Transparency = 1 end
    end
    -- 往回溅的火花
    for _, B in ipairs(A.back) do
      local bt = t - B.t
      if bt >= 0 then
        local q = bt / 0.6
        if q < 1 then
          B.p.CFrame = CF(p0 + B.v * ease(q) + V3(0, -0.4 * q * q, 0))
          B.p.Size = V3(1, 1, 1) * lerp(B.s, B.s * 0.4, q)
          B.p.Color = heat(q, WHITE, ORANGE, EMBER, 0.35)
          B.p.Transparency = lerp(0, 0.7, q)
        else B.p.Transparency = 1 end
      end
    end
    -- ③ 钻进去：杆头往里走（越往里越慢），长杆被啃短；孔道一路烧红再冷下去；全口径弹顶着一块装甲塞子
    if A.chan and ti >= 0 then
      local q = math.clamp(ti / Pk, 0, 1)
      local tipD = A.deep * ease(q)
      local tip = p0 + dv * math.max(tipD, 0.05)
      local L = K.len * (1 - (K.erode or 0) * q)
      A.shell.CFrame = CFrame.lookAt(tip - dv * L * 0.5, tip)
      A.shell.Size = V3(K.w, K.w, math.max(L, 0.1))
      if q < 1 then
        A.shell.Color, A.shell.Transparency = K.col:Lerp(WHITE, 0.5), 0
      else
        local cq = math.clamp((ti - Pk) / 1.4, 0, 1)
        A.shell.Color, A.shell.Transparency = heat(cq, WHITE, ORANGE, EMBER, 0.25), lerp(0, 0.2, cq)
      end
      if A.tb and t >= A.tb then A.shell.Transparency = 1 end   -- 穿甲爆破弹：炸了就没了
      local hq = math.clamp(ti / 2, 0, 1)
      if seg(A.chan, p0, tip, K.w * 0.8) then A.chan.Transparency, A.chan.Color = 0.1, heat(hq, RGB(255, 230, 170), ORANGE, EMBER, 0.3) end
      if seg(A.chanGlow, p0, tip, K.w * 2.6) then A.chanGlow.Transparency = lerp(0.55, 1, math.clamp(ti / 1.6, 0, 1)) end
      if A.plug then
        local pq = math.clamp(ti / (Pk * 0.6), 0, 1)
        local pp = p0 + dv * (math.min(tipD, A.deep * 0.45) + 0.12)
        A.plug.CFrame = CFrame.lookAt(pp, pp + dv) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(pq * 1.4, 0, 0)
        A.plug.Color, A.plug.Transparency = heat(math.clamp(ti / 1.8, 0, 1), RGB(255, 220, 160), ORANGE, EMBER, 0.3), 0
      end
    end
    -- ④ 破片
    fragStep(A.frags, t)
    -- ⑤ 穿甲爆破弹在车里炸开 / 杀爆在车外炸开 / 碎甲拍饼、冲击波、内壁崩落
    if A.tb and A.fb then
      local bt = t - A.tb
      if bt >= 0 then
        local q = bt / 0.8
        if q < 1 then
          A.fb.Size = V3(1, 1, 1) * lerp(0.5, 2.6 * W.M, ease(q))
          A.fb.Color = heat(q, WHITE, ORANGE, EMBER, 0.25)
          A.fb.Transparency = lerp(0, 0.9, q ^ 1.4)
          vp.BackgroundColor3 = RGB(255, 190, 120):Lerp(VP_BG, math.clamp(q * 3, 0, 1))
        else A.fb.Transparency = 1 end
      end
    end
    if K.blast and ti >= 0 then
      local q = ti / 0.9
      if q < 1 then
        A.fb.Size = V3(1, 1, 1) * lerp(0.8, A.fbR * 2, ease(q))
        A.fb.Color = heat(q, WHITE, ORANGE, RGB(70, 60, 55), 0.25)
        A.fb.Transparency = lerp(0, 0.85, q ^ 1.3)
      else A.fb.Transparency = 1 end
      local sq = (ti - 0.25) / 2.5
      if sq > 0 and sq < 1 then
        A.smoke.Size = V3(1, 1, 1) * lerp(1.5, A.fbR * 2.6, ease(sq))
        A.smoke.CFrame = CF(p0 + n * (1.2 + 2 * sq) + V3(0, 2.4 * sq, 0))
        A.smoke.Transparency = lerp(0.5, 1, sq)
      elseif sq >= 1 then A.smoke.Transparency = 1 end
    end
    if K.scab and ti >= 0 then
      local pq = math.clamp(ti / 0.15, 0, 1)
      local pr = lerp(0.4, 1.9, ease(pq))
      A.pan.Size = V3(lerp(0.4, 0.12, pq), pr, pr)
      A.pan.Transparency = (ti < 0.22) and 0 or 1
      local wq = (ti - 0.2) / 0.22
      if wq >= 0 and wq < 1 then
        local wp = p0 + dv * (0.3 * W.M * wq)
        A.wave.CFrame = CFrame.lookAt(wp, wp + dv) * CFrame.Angles(0, math.pi / 2, 0)
        A.wave.Size = V3(0.06, 1.6 + 1.4 * wq, 1.6 + 1.4 * wq)
        A.wave.Transparency = 0.2 + 0.6 * wq
      else A.wave.Transparency = 1 end
      local sq = (ti - 0.4) / 0.3
      if sq >= 0 then
        A.scab.Transparency = (sq < 1) and lerp(0, 1, sq) or 1
        A.scab.Color = heat(math.clamp(sq, 0, 1), WHITE, ORANGE, EMBER, 0.4)
      end
    end
    -- ⑥ 打到的乘员 / 模块：到的那一刻红白闪、胀一下，再定成最后的颜色（乘员是零件拼的人：H.ps 每个零件一起闪）
    for _, H in ipairs(A.hitP) do
      local ht = t - H.at
      if ht >= 0 then
        if ht < 0.7 then
          local fc = (math.floor(ht * 14) % 2 == 0) and RGB(255, 255, 255) or RGB(255, 40, 30)
          local gk = 1 + 0.3 * (1 - ht / 0.7)
          for _, q in ipairs(H.ps or { H }) do
            q.p.Color, q.p.Transparency, q.p.Size = fc, 0, q.size * gk
          end
        elseif not H.done then
          H.done = true
          for _, q in ipairs(H.ps or { H }) do q.p.Color, q.p.Transparency, q.p.Size = xrSub(H.col, q.g, H.s or 2, H.cat), H.tr, q.size end
        end
      end
    end
    -- ⑦ 弹药殉爆、起火
    if A.boom and t >= A.boomT then
      local q = (t - A.boomT) / 1.2
      if q < 1 then
        A.boom.Size = V3(1, 1, 1) * lerp(1, A.boomR, ease(q))
        A.boom.Color = heat(q, WHITE, ORANGE, EMBER, 0.3)
        A.boom.Transparency = lerp(0.05, 1, q ^ 1.5)
        vp.BackgroundColor3 = RGB(255, 170, 90):Lerp(VP_BG, math.clamp(q * 3, 0, 1))
      else A.boom.Transparency = 1 end
    end
    if A.fire and t >= A.fireT then
      for i, F in ipairs(A.fire) do
        local fl = 0.75 + 0.22 * math.sin(t * (9 + i * 3.7) + i) + 0.14 * math.sin(t * 23 + i * 2)
        F.p.Size = V3(1, 1, 1) * F.s * fl
        F.p.CFrame = CF(F.c + V3(0, (fl - 0.6) * 0.9, 0))
        F.p.Transparency = 0.25
      end
    end
    -- 字幕
    if ti >= 0 and not A.said then A.said = true xInfo.Text, xInfo.TextColor3, xInfo.Visible = A.info, INFO, true end
    if A.info2 and not A.said2 and t >= (A.boomT or (TIk + Pk)) + 0.15 then A.said2 = true xInfo.Text, xInfo.TextColor3 = A.info2, KILL end
    xSlow.Visible = t < TIk + Pk + 0.5
    -- 镜头：从斜侧面推近到命中点、跟一点弹芯，打完拉回来看整辆车、慢慢绕；打上那一下一震
    xrSpin += dt * ((t < TIk + Pk) and math.rad(7) or math.rad(16))
    local back = ease((t - (TIk + Pk + 0.3)) / 1.1)
    local focus = A.chan and (p0 + dv * math.min((A.deep or 0) * 0.35 * ease(math.max(ti, 0) / Pk), 3)) or p0
    local tgt = focus:Lerp(xrC, back)
    local dist = lerp(lerp(xrDist * 0.95, xrDist * 0.5, ease(t / TIk)), xrDist, back)
    local eye = tgt + CFrame.Angles(0, xrSpin, 0) * xrDir * dist + V3(0, dist * 0.32, 0)
    if ti >= 0 and ti < 0.45 then
      local k = (1 - ti / 0.45) ^ 2 * ((K.blast and 0.5) or (K.small and 0.12) or 0.3)
      eye += V3(math.sin(t * 91) * k, math.sin(t * 73 + 1) * k, math.sin(t * 57 + 2) * k)
    end
    vcam.CFrame = CFrame.lookAt(eye, tgt)
  end

  local GHOST_N = 120   -- 回放里车的半透明影子最多几块
  -- 车壳影子的样子（11-28：浅一点、更透——原来 150,190,220 / 0.88，几层模型叠起来一片浑蓝，盖住里面的部件）
  local GHOST = { col = RGB(206, 220, 234), tr = 0.9, mat = Enum.Material.SmoothPlastic }
  local XR_LIMIT = 360   -- 回放里部件最多几个零件（XrayOwn.plan 的 limit：弹多的车一发一个零件、再多少画几发）
  local lastGhost = nil   -- 测试 / 截图用（tools/mock/xrshot.lua）：这一回放的车壳用哪个原模型、炮塔转角、样子
  local IMeta = nil       -- ImportedMeta（第一次用到时 require；没有记 false）
  G.wtXrStyle = function()
    if not lastGhost then return {} end
    local s = lastGhost.style
    return { ghost = { key = lastGhost.key, ty = lastGhost.ty, tur = lastGhost.tur,
      style = { col = { math.floor(s.col.R * 255 + 0.5), math.floor(s.col.G * 255 + 0.5), math.floor(s.col.B * 255 + 0.5) }, tr = s.tr,
        mat = tostring(s.mat):match("([%w_]+)$") } } }
  end
  -- 影子用哪几块（11-27 审查）：原来按包围盒体积挑最大的 120 块——履带板（Tracks.lua 挂在车模型下的 TrackLink，一辆八九十块）占了名额，
  --   细长的件（炮管、天线、机枪，体积小）被挤掉，而炮管是回放里最好认的东西。现在履带板不要，按最长的那条边排：丢的是螺栓、灯座这种小块
  local function ghostParts(model)
    local cand = {}
    for _, p in ipairs(model:GetDescendants()) do
      if p:IsA("BasePart") and p.Transparency < 0.9 and p.Name ~= "TrackLink" then
        local sz = p.Size
        cand[#cand + 1] = { p, math.max(sz.X, sz.Y, sz.Z) }
      end
    end
    if #cand > GHOST_N then table.sort(cand, function(a, b) return a[2] > b[2] end) end
    local out = {}
    for i = 1, math.min(#cand, GHOST_N) do out[i] = cand[i][1] end
    return out
  end
  G.wtGhostParts = ghostParts   -- 测试用
  -- 机枪 / 机炮连着打穿同一辆（用户 11-28「机枪连续贯穿车体的话 x光就同一个角度然后一直放各种子弹打进去的x透视吧」）：
  --   1.5 秒内同一辆的下一发小弹不重画、不换角度——这一发的弹道、弹芯、破片接着画进去，打到的乘员 / 模块按现在的状态改色，镜头停住不绕
  local xrBurst = nil   -- { id, t, n }
  local xrHold = false  -- 镜头停住（连发时）
  local xrParts = {}    -- 上一次完整画的乘员 / 模块：[布局项] = { p, ps }
  local function burstHit(m, d, x)
    local p0 = V3(x.p[1], x.p[2], x.p[3])
    local dv = V3(x.d[1], x.d[2], x.d[3]).Unit
    local yaw = x.ty or 0
    line(p0 - dv * 9, p0, RGB(255, 120, 40), 0.16)
    if m.r == "pen" or m.kill then
      local core = (x.core or 0) * W.M
      if core > 0 then line(p0, p0 + dv * core, RGB(255, 150, 50), 0.2) end
      for i, rv in ipairs(W.cone(dv, x.half or 18, x.n or 0, x.seed)) do
        local len = (1.4 + (i % 4) * 0.35) * W.M
        local hits = W.trace(d, yaw, p0 + dv * 0.1, rv, len, true)
        local l2 = hits[1] and math.max(0.3, hits[1].t + 0.4) or len
        line(p0, p0 + rv * l2, RGB(255, 226, 90), 0.06)
      end
    end
    box(V3(0.5, 0.5, 0.5), CF(p0), RGB(255, 240, 200), 0, Enum.Material.Neon)
    local st = states(entModel(m.id), d, m)
    for it, P in pairs(xrParts) do
      local sv = st[it] or 2
      local hit = sv < 2
      local col = xrCol(P.kind, P.cat or "other", sv, hit)
      local tr = xrTr(P.kind, sv, hit)
      for _, q in ipairs(P.ps or { { p = P.p } }) do q.p.Color, q.p.Transparency = xrSub(col, q.g, sv, P.cat), tr end
    end
    xrBurst.n += 1
    xrBurst.t = os.clock()
    xrUntil = math.max(xrUntil, os.clock() + 2.5)
    xSlow.Visible = false
    xInfo.Text, xInfo.Visible = T("wt.xrBurst", xrBurst.n), true
  end
  local function showXray(m)
    local d = VD.get and VD.get(m.veh) or VD[m.veh]
    local x = m.xr
    if not d or not x then return end
    if x.sub == "ac" and xrBurst and xrBurst.id == m.id and xr.Visible and os.clock() - xrBurst.t < 1.5 then
      burstHit(m, d, x)
      return
    end
    world:ClearAllChildren()
    table.clear(xrParts)
    xa = nil
    vp.BackgroundColor3 = VP_BG
    if xStroke then xStroke.Color = XR_LINE end
    xInfo.Visible, xSlow.Visible = false, false
    xSlow.Text = T("wt.xrSlow")
    local lay = W.layout(d)
    local yaw = x.ty or 0
    local base = CF()   -- 回放里车底座在原点
    -- 车的外形：看得见那辆车就照它的模型复制一份半透明的；看不见画车体、炮塔两个半透明的框
    local v = G.viewById and G.viewById(m.id)
    local n = 0
    if v and v.model and v.hullF then
      local inv = (v.hullF):Inverse()
      -- 只复制 GHOST_N 块（11-27 M3 丝滑：原来最多复制 400 块，命中那一下卡一顿；零件拼的车小零件上百块，
      --   88% 透明的影子里看不出来；原模型的车本来就没几块，照旧整辆）
      for _, p in ipairs(ghostParts(v.model)) do
        n += 1
        local c = p:Clone()
        for _, ch in ipairs(c:GetChildren()) do if not ch:IsA("SpecialMesh") then ch:Destroy() end end
        pcall(function() c.TextureID = "" end)
        c.Anchored, c.CanCollide, c.CastShadow = true, false, false
        c.Material, c.Color, c.Transparency = GHOST.mat, GHOST.col, GHOST.tr
        c.CFrame = inv * p.CFrame
        c.Parent = world
      end
    end
    if n == 0 then
      local hH = lay.hH
      local b1 = box(V3(d.W, hH - (d.clear or 1.2), d.L), CF(0, ((d.clear or 1.2) + hH) / 2, 0), RGB(150, 190, 220), 0.85)
      b1:SetAttribute("XrGhost", true)
      if d.turret then
        local tcf = CF(W.fromTur(d, V3(), yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
        local b2 = box(lay.ts, tcf * CF(0, lay.ts.Y / 2, 0), RGB(150, 190, 220), 0.8)
        b2:SetAttribute("XrGhost", true)
      end
    end
    do   -- 截图用：这辆车的原模型键（ImportedMeta 的 alias）、炮塔转角
      if IMeta == nil then
        local ms = RS:FindFirstChild("ImportedMeta")
        local okIM, r = ms ~= nil, nil
        if okIM then okIM, r = pcall(require, ms) end
        IMeta = (okIM and type(r) == "table") and r or false
      end
      local key = IMeta and IMeta.alias and IMeta.alias[d.id]
      local info = key and IMeta.m and IMeta.m[key]
      lastGhost = { key = key, ty = yaw, tur = info and info.tur, style = GHOST }
    end
    -- 乘员、模块（用户 11-28「目前x光效果还是不如战雷」：照战雷的命中回放重画）——每件照真东西的样子画（XrayOwn.plan，同按住 X 的透视：
    --   一发发的弹、发动机缸体、变速箱、油箱、炮闩炮管、人形乘员），实心、打光（原来除了乘员都是一个半透明的方块、统一一种蓝灰）；
    --   没事的按类别一种沉着的颜色（XC：弹药黄铜、油箱橄榄、发动机钢灰……），这一发没打到的淡一点、退后一点，打到的才醒目；
    --   伤了琥珀、毁了红、乘员阵亡暗红；拿不到形状的退回一个方块
    local st = states(entModel(m.id), d, m)
    local hitK = {}
    for _, p in ipairs(m.parts or {}) do hitK[p.k] = true end
    local sub = (not x.jet) and KS[x.sub or ""] and x.sub or nil   -- 动能弹 / 穿甲爆破 / 杀爆 / 碎甲：各自的慢放（xkBuild）
    local anim = (x.jet or sub) and (m.r == "pen" or m.kill) and x.sub ~= "ac" and true or false   -- 打穿了才放慢放动画（机枪 / 机炮的小弹不放：连发时同一个角度往里叠）
    local hitP = {}   -- 动画里打到的乘员 / 模块：先画成没事的样子，射流 / 破片到了才变色
    local tF = d.turret and (CF(W.fromTur(d, V3(), yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)) or CF()
    local FR = { hull = CF(), tur = tF, gun = (d.gun and d.turret) and (tF * CF(d.gun.pivot) * CFrame.Angles(math.rad(x.gp or 0), 0, 0)) or tF }
    local plan = nil
    if XO and XO.plan then
      local okP, r = pcall(XO.plan, d, { limit = XR_LIMIT })
      if okP and type(r) == "table" and r.items then plan = r end
    end
    local byIt = {}
    if plan then for _, x2 in ipairs(plan.items) do if x2.it then byIt[x2.it] = x2 end end end
    local function partsOf(specs, F, colFn, tr)   -- 一件的零件：{ { p, size, g } … }
      local ps = {}
      for _, sp in ipairs(specs) do
        local q = box(sp.s, F * sp.cf, colFn(sp.g), tr)
        if sp.sh == "S" then q.Shape = Enum.PartType.Ball elseif sp.sh == "C" then q.Shape = Enum.PartType.Cylinder end
        q.Size = sp.s
        ps[#ps + 1] = { p = q, size = q.Size, g = sp.g }
      end
      return ps
    end
    for _, it in ipairs(lay.list) do
      local s = st[it] or 2
      local x2 = byIt[it]
      local cat = (it.kind == "crew") and "crew" or (x2 and x2.cat) or "other"
      local col = xrCol(it.kind, cat, s, hitK[it.k])
      local tr = xrTr(it.kind, s, hitK[it.k])
      local ps = nil
      if x2 and x2.specs and #x2.specs > 0 then
        ps = partsOf(x2.specs, FR[x2.frame] or FR.hull, function(g) return xrSub(col, g, s, cat) end, tr)
      end
      local p
      if ps and #ps > 0 then
        p = ps[1].p
      else
        local size = it.hi - it.lo
        local c = (it.lo + it.hi) / 2
        local cf = it.tur and (CF(W.fromTur(d, c, yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)) or CF(c)
        p = box((it.kind == "crew") and size * 0.8 or size, cf, col, tr)
        if it.kind == "crew" then
          local sm = Instance.new("SpecialMesh")
          sm.MeshType = Enum.MeshType.Sphere
          sm.Parent = p
        end
        ps = nil
      end
      xrParts[it] = { p = p, ps = ps, kind = it.kind, cat = cat }
      if anim and hitK[it.k] then
        table.insert(hitP, { p = p, ps = ps, it = it, col = col, tr = tr, size = p.Size, cat = cat, s = s })
        local c0 = xrCol(it.kind, cat, 2, true)   -- 射流 / 破片到之前：没事的样子
        for _, q in ipairs(ps or { { p = p } }) do q.p.Color, q.p.Transparency = xrSub(c0, q.g, 2, cat), 0 end
      end
    end
    if plan then   -- 不算伤害的件（并列机枪、车长周视镜、热像仪、反坦克导弹发射架）：没事的颜色、淡一点
      for _, x2 in ipairs(plan.items) do
        if not x2.it and x2.specs and x2.cat ~= "era" then
          local col = xrCol("mod", x2.cat, 2, false)
          partsOf(x2.specs, FR[x2.frame] or FR.hull, function(g) return xrSub(col, g, 2, x2.cat) end, xrTr("mod", 2, false))
        end
      end
    end
    -- 弹道：外面一段、弹芯往里一段（橙），破片一锥（黄）；射流打穿的换成慢放动画
    local p0 = V3(x.p[1], x.p[2], x.p[3])
    local dv = V3(x.d[1], x.d[2], x.d[3]).Unit
    if anim and x.jet then
      xa = xaBuild(m, x, d, yaw, p0, dv, hitP)
      xa.step = xaStep
    elseif anim then
      xa = xkBuild(m, x, d, yaw, p0, dv, hitP, sub)
      xa.step = xkStep
    else
      line(p0 - dv * 9, p0, RGB(255, 120, 40), 0.16)
      if m.r == "pen" or m.kill then
        local core = (x.core or 0) * W.M
        if core > 0 then line(p0, p0 + dv * core, RGB(255, 150, 50), 0.2) end
        for i, rv in ipairs(W.cone(dv, x.half or 18, x.n or 0, x.seed)) do
          local len = (1.4 + (i % 4) * 0.35) * W.M
          local hits = W.trace(d, yaw, p0 + dv * 0.1, rv, len, true)
          local l2 = hits[1] and math.max(0.3, hits[1].t + 0.4) or len
          line(p0, p0 + rv * l2, RGB(255, 226, 90), 0.06)
        end
      end
      box(V3(0.5, 0.5, 0.5), CF(p0), RGB(255, 240, 200), 0, Enum.Material.Neon)
    end
    -- 镜头：从来弹方向、稍高一点看车中心，慢慢绕（射流动画先从斜侧面推近，见 xaStep）
    xrC = V3(0, (d.H or 7) * 0.45, 0)
    xrDist = math.max(d.L, d.W) * 1.32 + 3   -- 11-28：窗口放大了、车也拉近一点（原来 × 1.55 + 4，车只占一半）
    xrDir = (-dv * V3(1, 0, 1))
    if xrDir.Magnitude < 0.1 then xrDir = V3(0, 0, 1) end
    xrDir = xrDir.Unit
    xrSpin = anim and math.rad(50) or 0
    local nm = (m.tk and T("tree." .. m.tk) ~= "tree." .. m.tk) and T("tree." .. m.tk) or T("veh." .. m.veh)   -- 科技树出的车写科技树里的名字
    xTitle.Text = T("wt.xrTitle", nm, m.dist or 0)
    xr.Visible = true
    xrUntil = os.clock() + (anim and (m.kill and 7 or 6.2) or (m.kill and 5.5 or 4.5))
    xrBurst = (x.sub == "ac") and { id = m.id, t = os.clock(), n = 1 } or nil   -- 机枪 / 机炮：接下来 1.5 秒内的同一辆往里叠
    xrHold = x.sub == "ac"
    if xrHold then xrSpin = 0 end
    if xa then G.try_(xa.step, 0, 0) end   -- 先摆好第一帧（不然头一帧是没藏好的件）
    local _ = base
  end

  ---------------------------------------------------------------- 左下：自己这辆车的车组 / 模块

  local panel = frame(gui, UDim2.fromOffset(226, 96), mobile and UD2(0, 12, 1, -238) or UD2(0, 254, 1, -24), RGB(6, 10, 12), 0.35, V2(0, 1))
  panel.Name = "WtCrew"
  panel.Visible = false
  do
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness, s.Transparency = RGB(120, 200, 140), 1, 0.55
    s.Parent = panel
  end
  local crewIcons, modIcons = {}, {}
  local CREW_ROW = { "drv", "gnr", "cmd", "ldr" }
  for i, r in ipairs(CREW_ROW) do
    local f = frame(panel, UDim2.fromOffset(48, 30), UD2(0, 6 + (i - 1) * 54, 0, 6), RGB(20, 30, 26), 0.2)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = f
    local l = label(f, T("wt.rs." .. r), UD2(1, 0, 1, 0), UD2(), 15, OK, BOLD)
    f.Name = "Crew_" .. r
    crewIcons[r] = { f = f, l = l }
  end
  local MOD_ROW = { "engine", "trans", "track", "barrel", "breech", "tdrive", "ammo", "fuel" }
  for i, k in ipairs(MOD_ROW) do
    local f = frame(panel, UDim2.fromOffset(25, 20), UD2(0, 6 + (i - 1) * 27, 0, 42), RGB(20, 30, 26), 0.2)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = f
    local l = label(f, T("wt.ms." .. k), UD2(1, 0, 1, 0), UD2(), 11, OK, BOLD)
    f.Name = "Mod_" .. k
    modIcons[k] = { f = f, l = l }
  end
  local panelTip = label(panel, "", UD2(1, -8, 0, 16), UD2(0, 4, 0, 72), 12, Color3.new(1, 1, 1), BOLD, nil, Enum.TextXAlignment.Left)
  panelTip.Name = "Tip"
  local flashUntil = 0

  local hurtText = label(gui, "", UDim2.fromOffset(700, 22), UD2(0.5, 0, 1, -150), 17, DEAD, BOLD, V2(0.5, 1))
  hurtText.Name = "WtHurtText"
  hurtText.Visible = false
  local hurtUntil = 0
  local function say(text, col, dur)
    hurtText.Text, hurtText.TextColor3 = text, col or DEAD
    hurtText.Visible = true
    hurtUntil = os.clock() + (dur or 3)
  end

  local function colOf(s) return (s == 0) and DEAD or ((s == 1) and HURT or OK) end
  local function updatePanel()
    local st = G.myVeh
    local em = st and st.em
    local wc = em and em:GetAttribute("WtC")
    if not wc or (G.S and G.S.veh == nil and not st) then panel.Visible = false return end
    if G.wtTankShown and G.wtTankShown() then panel.Visible = false return end   -- 电脑上是战雷那套的损伤示意图（WtTank.lua）
    panel.Visible = true
    local d = st.d or (VD.get and VD.get(em:GetAttribute("Model") or ""))
    if not d then panel.Visible = false return end
    local lay = W.layout(d)
    -- 乘员：按座位（谁坐在这个位子上、活没活）
    local seatState, have = {}, {}
    for tok in string.gmatch(wc, "[^,]+") do
      local s, seat = tonumber(string.sub(tok, 1, 1)) or 2, string.sub(tok, 2)
      if seatState[seat] == nil or s > seatState[seat] then seatState[seat] = s end
      have[seat] = true
    end
    for _, r in ipairs(CREW_ROW) do
      local ic = crewIcons[r]
      ic.f.Visible = have[r] == true
      if have[r] then ic.l.TextColor3 = colOf(seatState[r]) end
    end
    -- 模块：几块合成一个图标的取最差的（左右履带、几个弹药架、几个油箱）
    local wm = em:GetAttribute("WtM") or ""
    local worst = {}
    local mi = 0
    for _, it in ipairs(lay.list) do
      if it.kind ~= "crew" then
        mi += 1
        local s = tonumber(string.sub(wm, mi, mi)) or 2
        local k = it.k
        if k == "trackL" or k == "trackR" then k = "track" elseif k == "ammoH" then k = "ammo" elseif k == "fuelL" or k == "fuelR" then k = "fuel" end
        if worst[k] == nil or s < worst[k] then worst[k] = s end
      end
    end
    for _, k in ipairs(MOD_ROW) do
      local ic = modIcons[k]
      ic.f.Visible = worst[k] ~= nil
      if worst[k] then ic.l.TextColor3 = colOf(worst[k]) end
    end
    local t = os.clock()
    local flash = t < flashUntil and (t * 8) % 1 < 0.5
    panel.BackgroundColor3 = flash and RGB(90, 20, 14) or RGB(6, 10, 12)
    -- 提示：起火、维修中、坏了能修
    local fire = em:GetAttribute("WtF") == true
    local fix = em:GetAttribute("WtFix")
    local anyBad = false
    for _, s in pairs(worst) do if s < 2 then anyBad = true end end
    local afLeft = em:GetAttribute("WtAFLeft")   -- 弹药架起火：几秒内不灭就殉爆（服务器 Wt.lua，用户 11-28「弹药架起火如果不及时灭火修要爆炸」）
    if fire and type(afLeft) == "number" then panelTip.Text, panelTip.TextColor3 = T("wt.tipAmmoFire", afLeft), ((t * 5) % 1 < 0.6) and DEAD or Color3.new(1, 1, 1)
    elseif fire then panelTip.Text, panelTip.TextColor3 = T("wt.tipFire"), ((t * 3) % 1 < 0.6) and DEAD or HURT
    elseif fix then panelTip.Text, panelTip.TextColor3 = T("wt.tipFixing", math.floor(fix * 100)), HURT
    elseif anyBad then panelTip.Text, panelTip.TextColor3 = T("wt.tipFix"), Color3.new(1, 1, 1)
    else panelTip.Text = "" end
  end

  ---------------------------------------------------------------- 金属射流（破甲弹、金属射流弹打在车上）
  --   用户 11-24 夜「再做一个金属射流弹」：命中点一团白光、往外喷一圈火花，一道白热的射流顺着来向钻进去（从车外伸进去一截，
  --   打穿的钻得深、射流弹更粗更亮），零点几秒淡掉；没打穿只有一小截
  local TS = game:GetService("TweenService")
  local function jetFx(e)
    if typeof(e.p) ~= "Vector3" or typeof(e.d) ~= "Vector3" then return end
    if (e.p - workspace.CurrentCamera.CFrame.Position).Magnitude > 3000 then return end
    local d = (e.d.Magnitude > 0.01) and e.d.Unit or V3(0, 0, -1)
    local len = math.clamp(e.len or 2, 0.5, 24)
    local big = e.big == true
    local a0, a1 = e.p - d * 1.4, e.p + d * len
    local mid, L = (a0 + a1) / 2, (a1 - a0).Magnitude
    local f = Instance.new("Folder")
    f.Name = "WtJet"
    f.Parent = workspace
    local function mk(size, cf, col, tr, shape)
      local q = Instance.new("Part")
      q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.CastShadow = true, false, false, false, false
      q.Material, q.Color, q.Transparency, q.Size, q.CFrame = Enum.Material.Neon, col, tr, size, cf
      if shape then q.Shape = shape end
      q.Parent = f
      return q
    end
    local w = big and 0.22 or 0.14
    local core = mk(V3(w, w, L), CFrame.lookAt(mid, a1), RGB(240, 250, 255), 0.02)
    local glow = mk(V3(w * 4, w * 4, L), CFrame.lookAt(mid, a1), RGB(150, 210, 255), 0.6)
    local flash = mk(V3(1, 1, 1) * (big and 3.4 or 2.6), CFrame.new(e.p), RGB(255, 236, 200), 0.15, Enum.PartType.Ball)
    local lt = Instance.new("PointLight")
    lt.Color, lt.Brightness, lt.Range = RGB(200, 225, 255), big and 8 or 5, 22
    lt.Parent = flash
    local pe = Instance.new("ParticleEmitter")   -- 火花：从命中点往外喷（射流反溅出来的铜和钢的碎渣）
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    pe.Color = ColorSequence.new(RGB(255, 236, 190), RGB(255, 140, 60))
    pe.LightEmission = 1
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.05) })
    pe.Lifetime = NumberRange.new(0.18, 0.45)
    pe.Speed = NumberRange.new(30, 70)
    pe.SpreadAngle = Vector2.new(55, 55)
    pe.Drag = 4
    pe.Rate = 0
    pe.EmissionDirection = Enum.NormalId.Front
    local emit = Instance.new("Attachment")
    emit.CFrame = CFrame.lookAt(Vector3.zero, -d)   -- 往来向那边喷
    emit.Parent = flash
    pe.Parent = emit
    pcall(function() pe:Emit(big and 46 or 30) end)
    local ti = TweenInfo.new(big and 0.32 or 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TS:Create(core, ti, { Transparency = 1 }):Play()
    TS:Create(glow, ti, { Transparency = 1, Size = V3(w * 7, w * 7, L) }):Play()
    TS:Create(flash, ti, { Transparency = 1, Size = flash.Size * 1.8 }):Play()
    TS:Create(lt, ti, { Brightness = 0 }):Play()
    task.delay(0.8, function() f:Destroy() end)
  end
  G.R.Fx.OnClientEvent:Connect(function(list)
    if type(list) ~= "table" then return end
    for _, e in ipairs(list) do
      if type(e) == "table" and e.k == "wtJet" then G.try_(jetFx, e) end
    end
  end)

  ---------------------------------------------------------------- 服务器发来的

  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" then return end
    local op = m.op
    if op == "wtHit" then
      showHit(m)
      if G.wtVoice then   -- 车组语音（⑬，WtVoice.lua）
        G.wtVoice(m.kill and ((m.why == "ammo") and "killAmmo" or "kill") or ((m.r == "pen") and "pen" or ((m.r == "ric") and "ric" or ((m.r == "np") and "np" or "hit"))))
      end
      if m.xr and (m.r == "pen" or m.kill) then G.try_(showXray, m) end
    elseif op == "wtHurt" then
      flashUntil = os.clock() + 1.2
      if G.wtVoice then   -- 车组语音（⑬）：被击穿 / 跳弹、着火、谁阵亡、哪个模块坏了
        if m.r == "pen" then G.wtVoice("hurtPen") elseif m.r == "ric" then G.wtVoice("hurtRic") end
        if m.fire then G.wtVoice("fire") end
        for _, p in ipairs(m.parts or {}) do
          if p.kind == "crew" and p.s == 0 then G.wtVoice(p.seat or p.k)
          elseif p.s == 0 and (p.k == "engine" or p.k == "barrel" or p.k == "breech") then G.wtVoice(p.k)
          elseif p.s == 0 and (p.k == "trackL" or p.k == "trackR") then G.wtVoice("track") end
        end
      end
      local head = T((m.r == "pen") and "wt.youPen" or ((m.r == "fire") and "wt.youFire" or ((m.r == "ric") and "wt.youRic" or ((m.r == "np") and "wt.youNp" or "wt.youHit"))))
      local sub = details(m)
      say(head .. ((sub ~= "") and ("：" .. sub) or ""), (m.r == "ric" or m.r == "np") and GREY or DEAD, 3.2)
    elseif op == "wtSwap" then
      if G.wtVoice then G.wtVoice("swap") end
      say(T("wt.swap", T("wt.r." .. m.from), T("wt.r." .. m.role), m.t or 6), HURT, 3)
    elseif op == "wtSwapped" then
      say(T("wt.swapped", T("wt.r." .. m.from), T("wt.r." .. m.role)), OK, 2.5)
    elseif op == "wtFireOut" then
      if G.wtVoice then G.wtVoice("fireOut") end
      say(T(m.ext and "wt.extOk" or "wt.fireOut"), OK, 2)
    elseif op == "wtSupply" then
      if G.wtVoice then G.wtVoice("resupply") end   -- 停在自己的据点里补给（服务器 Wt.lua supplyStep）
      local bits = {}
      if m.ammo then table.insert(bits, T("wt.supAmmo")) end
      if m.crew then table.insert(bits, T("wt.supCrew", T("wt.r." .. m.crew))) end
      say(table.concat(bits, " · "), OK, 2)
    elseif op == "wtFixed" then
      if G.wtVoice then G.wtVoice("fixed") end
      say(T("wt.fixed"), OK, 2)
    elseif op == "wtKilled" then   -- 自己的车被打掉：「被 XX 的 YY 击毁」+ 那一发的 X 光（战雷的击毁回放）
      G.wtKiller = m.kid and { id = m.kid, t = os.clock() } or nil   -- 击杀镜头（⑮）：阵亡效果（DeathFx.lua）的镜头转去看打你的那辆
      local kv = m.kveh and (string.match(T("veh." .. m.kveh), "^(%S+)") or T("veh." .. m.kveh)) or nil
      if m.kk and T("tree." .. m.kk) ~= "tree." .. m.kk then kv = T("tree." .. m.kk) end   -- 打你的是科技树出的车：写科技树里的名字
      say(kv and T("wt.killedBy", m.from or "?", kv) or T("wt.killedBy2", m.from or "?"), DEAD, 5)
      if m.xr then G.try_(showXray, m) end
    elseif op == "wtaHit" then
      showAirHit(m)
    elseif op == "wtaHurt" then
      local only = #(m.ev or {}) == 1 and m.ev[1] == "fireOut"
      if only then say(T("wta.e.fireOut"), OK, 2)
      else say(T("wta.hurt") .. "：" .. airBits(m), DEAD, 3) end
    end
  end)

  G.frameConn("WtHud", function(dt)
    local t = os.clock()
    if hitBox.Visible and t > hitUntil then   -- 到点：字淡掉再藏
      local a = math.clamp((t - hitUntil) / HIT_FADE, 0, 1)
      if a >= 1 then
        hitBox.Visible = false
        hitRank = 0
      else
        local st = 0.35 + 0.65 * a
        hitTop.TextTransparency, hitTop.TextStrokeTransparency = a, st
        hitSub.TextTransparency, hitSub.TextStrokeTransparency = a, st
      end
    end
    if hurtText.Visible and t > hurtUntil then hurtText.Visible = false end
    if xr.Visible then
      if t > xrUntil then
        xr.Visible = false
        world:ClearAllChildren()
        xa = nil
      elseif xa then
        G.try_(xa.step or xaStep, t - xa.t0, dt)
      else
        if not xrHold then xrSpin += dt * math.rad(16) end   -- 连发叠画时镜头停住（同一个角度）
        local d = CFrame.Angles(0, xrSpin, 0) * xrDir
        local eye = xrC + d * xrDist + V3(0, xrDist * 0.35, 0)
        vcam.CFrame = CFrame.lookAt(eye, xrC)
      end
    end
    G.try_(updatePanel)
  end)
end

return WtHud
