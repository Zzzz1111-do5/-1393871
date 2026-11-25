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
  local V2, V3, UD2 = Vector2.new, Vector3.new, UDim2.new
  local CF = CFrame.new
  local RGB = Color3.fromRGB
  local me = Players.LocalPlayer
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MONO = Enum.Font.BuilderSansBold, Enum.Font.RobotoMono
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
    hitBox.Visible = true
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
    hitBox.Visible = true
    hitUntil = os.clock() + (big and 3 or 1.6)
  end

  ---------------------------------------------------------------- X 光命中回放

  local XW, XH = mobile and 240 or 320, mobile and 150 or 196
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
  vp.BackgroundColor3, vp.BackgroundTransparency = RGB(14, 22, 30), 0.1
  vp.Ambient, vp.LightColor, vp.LightDirection = RGB(170, 175, 185), RGB(255, 255, 255), V3(-0.4, -1, -0.3)
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
  -- 状态：先看实体属性（服务器刚写的），没有就按这一发报来的
  local function states(em, d)
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
    return out
  end
  ---------------------------------------------------------------- X 光：射流的慢放动画
  --   用户 11-24 夜「射流弹击中别的坦克的 x 光动画要有特殊效果」：破甲 / 金属射流弹打穿时 X 光窗口里慢放——
  --   ① 弹飞进来（镜头从侧面推近到命中点）② 打上装甲：一团白闪、贴着装甲面一圈冲击波、窗口整个亮一下、镜头一震，弹坑烧红再冷下去
  --   ③ 白热的射流一点点钻进车里（越往里越慢），射流头一颗亮球、光套跳动，经过的地方甩出熔化的金属珠（白 → 橙 → 暗红），
  --      后面一截慢的杵体（真的聚能装药：射流头每秒七八公里，杵体只有几百米）④ 破片一根根往外长，打到的乘员 / 模块闪红再定色
  --   ⑤ 弹药殉爆一团火球 / 起火一簇火 ⑥ 镜头拉回来看整辆车、慢慢绕；底下一行字：穿深 / 等效毫米（击毁时换成「弹药殉爆」）
  local xInfo = label(xr, "", UD2(1, -12, 0, 16), UD2(0, 6, 1, -19), 12, RGB(200, 236, 255), BOLD, nil, Enum.TextXAlignment.Left)
  xInfo.Name = "XrInfo"
  xInfo.ZIndex = 3
  local xSlow = label(xr, "", UD2(0, 90, 0, 14), UD2(1, -8, 0, 26), 11, RGB(255, 210, 120), BOLD, V2(1, 0), Enum.TextXAlignment.Right)
  xSlow.Name = "XrSlow"
  xSlow.ZIndex = 3
  local xStroke = xr:FindFirstChildOfClass("UIStroke")
  local VP_BG, XR_LINE, INFO = TH.C.BG, TH.C.HUD, TH.C.TEXT
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
    A.info = T(big and "wt.xrJetB" or "wt.xrJet", m.pen or "?", m.arm or "?")
    A.info2 = m.kill and T((m.why == "ammo") and "wt.killAmmo" or ((m.why == "fire") and "wt.killFire" or "wt.kill")) or nil
    return A
  end

  local function xaStep(t, dt)
    local A = xa
    local p0, dv, core, w = A.p0, A.dv, A.core, A.w
    local ti = t - TI
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
    -- ⑤ 打到的乘员 / 模块：到的那一刻红白闪、胀一下，再定成最后的颜色
    for _, H in ipairs(A.hitP) do
      local ht = t - H.at
      if ht >= 0 then
        if ht < 0.7 then
          H.p.Color = (math.floor(ht * 14) % 2 == 0) and RGB(255, 255, 255) or RGB(255, 40, 30)
          H.p.Transparency = 0
          H.p.Size = H.size * (1 + 0.3 * (1 - ht / 0.7))
        elseif not H.done then
          H.done = true
          H.p.Color, H.p.Transparency, H.p.Size = H.col, H.tr, H.size
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

  local function showXray(m)
    local d = VD.get and VD.get(m.veh) or VD[m.veh]
    local x = m.xr
    if not d or not x then return end
    world:ClearAllChildren()
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
      for _, p in ipairs(v.model:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 0.9 and n < 400 then
          n += 1
          local c = p:Clone()
          for _, ch in ipairs(c:GetChildren()) do if not ch:IsA("SpecialMesh") then ch:Destroy() end end
          pcall(function() c.TextureID = "" end)
          c.Anchored, c.CanCollide, c.CastShadow = true, false, false
          c.Material, c.Color, c.Transparency = Enum.Material.SmoothPlastic, RGB(150, 190, 220), 0.88
          c.CFrame = inv * p.CFrame
          c.Parent = world
        end
      end
    end
    if n == 0 then
      local hH = lay.hH
      box(V3(d.W, hH - (d.clear or 1.2), d.L), CF(0, ((d.clear or 1.2) + hH) / 2, 0), RGB(150, 190, 220), 0.85)
      if d.turret then
        local tcf = CF(W.fromTur(d, V3(), yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
        box(lay.ts, tcf * CF(0, lay.ts.Y / 2, 0), RGB(150, 190, 220), 0.8)
      end
    end
    -- 乘员、模块
    local st = states(entModel(m.id), d)
    local hitK = {}
    for _, p in ipairs(m.parts or {}) do hitK[p.k] = true end
    local anim = x.jet and (m.r == "pen" or m.kill) and true or false   -- 射流打穿：放慢放动画
    local hitP = {}   -- 动画里打到的乘员 / 模块：先画成没事的样子，射流 / 破片到了才变色
    for _, it in ipairs(lay.list) do
      local s = st[it] or 2
      local col
      if it.kind == "crew" then col = (s == 0) and DEAD or ((s == 1) and HURT or OK)
      else col = (s == 0) and DEAD or ((s == 1) and HURT or RGB(120, 150, 170)) end
      local size = it.hi - it.lo
      local c = (it.lo + it.hi) / 2
      local cf
      if it.tur then cf = CF(W.fromTur(d, c, yaw)) * CFrame.Angles(0, -math.rad(yaw), 0)
      else cf = CF(c) end
      local tr = (it.kind == "crew") and 0.1 or ((s == 2 and not hitK[it.k]) and 0.55 or 0.15)
      local bs = (it.kind == "crew") and size * 0.8 or size
      local p = box(bs, cf, col, tr)
      if it.kind == "crew" then
        local sm = Instance.new("SpecialMesh")
        sm.MeshType = Enum.MeshType.Sphere
        sm.Parent = p
      end
      if anim and hitK[it.k] then
        table.insert(hitP, { p = p, it = it, col = col, tr = tr, size = p.Size })
        p.Color, p.Transparency = (it.kind == "crew") and OK or RGB(120, 150, 170), (it.kind == "crew") and 0.1 or 0.55
      end
    end
    -- 弹道：外面一段、弹芯往里一段（橙），破片一锥（黄）；射流打穿的换成慢放动画
    local p0 = V3(x.p[1], x.p[2], x.p[3])
    local dv = V3(x.d[1], x.d[2], x.d[3]).Unit
    if anim then
      xa = xaBuild(m, x, d, yaw, p0, dv, hitP)
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
    xrDist = math.max(d.L, d.W) * 1.55 + 4
    xrDir = (-dv * V3(1, 0, 1))
    if xrDir.Magnitude < 0.1 then xrDir = V3(0, 0, 1) end
    xrDir = xrDir.Unit
    xrSpin = anim and math.rad(50) or 0
    local nm = (m.tk and T("tree." .. m.tk) ~= "tree." .. m.tk) and T("tree." .. m.tk) or T("veh." .. m.veh)   -- 科技树出的车写科技树里的名字
    xTitle.Text = T("wt.xrTitle", nm, m.dist or 0)
    xr.Visible = true
    xrUntil = os.clock() + (anim and (m.kill and 7 or 6.2) or (m.kill and 5.5 or 4.5))
    if xa then G.try_(xaStep, 0, 0) end   -- 先摆好第一帧（不然头一帧是没藏好的件）
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
    if fire then panelTip.Text, panelTip.TextColor3 = T("wt.tipFire"), ((t * 3) % 1 < 0.6) and DEAD or HURT
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
    if hitBox.Visible and t > hitUntil then hitBox.Visible = false end
    if hurtText.Visible and t > hurtUntil then hurtText.Visible = false end
    if xr.Visible then
      if t > xrUntil then
        xr.Visible = false
        world:ClearAllChildren()
        xa = nil
      elseif xa then
        G.try_(xaStep, t - xa.t0, dt)
      else
        xrSpin += dt * math.rad(16)
        local d = CFrame.Angles(0, xrSpin, 0) * xrDir
        local eye = xrC + d * xrDist + V3(0, xrDist * 0.35, 0)
        vcam.CFrame = CFrame.lookAt(eye, xrC)
      end
    end
    G.try_(updatePanel)
  end)
end

return WtHud
