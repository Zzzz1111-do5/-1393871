-- 全面大战场（客户端）——坦克炮长瞄准镜里画的东西、车长望远镜（用户 11-27：「坦克的开镜你直接去按照战雷的做」+ 截图「这个样子」、
--   「然后再做一个望远镜」；11-26：「照真镜子重画」）。Drive.lua 建它、每帧调；分划的数和算法在 ReplicatedStorage/SightDefs.lua。
--   · 全屏，不套圆形目镜；分划是细线（白天黑色），尺寸按密位、跟着倍率缩放（每密位多少像素 = 屏幕半高 ÷ tan(半视场) × 一密位的弧度）
--   · 截图那样：中心一根横线（每 4 密位一格、每 8 密位写数），中心往下一根竖线，竖线左边是这一发弹的表尺（4 8 12 …，百米）；
--     苏式光学镜子上方还有各弹种表尺 + 指示线、左下 2.7 米测距曲线；数字火控的镜子镜下写距离、弹种、待发
--   · 顶上方位刻度（度，中间一个 ^），炮管实际指着哪里画一个小圈（炮塔还没转过来时它追着中心走）
--   · 装定距离一改（PageUp / PageDown、R 测距 / 估距），镜里左边写一会儿「表尺 1200 米」
--   · 车长望远镜（C）：两个圆的视场、8 倍、6000 制密位刻度（横、竖）和 2.7 米测距曲线；R 车长估距
--   外观（字体）用游戏自己的 Theme；分划的样子照真镜子
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local GunSight = {}

function GunSight.new(G, sightFrame, gui)
  local SD = require(RS:WaitForChild("SightDefs"))
  local BAL = require(RS:WaitForChild("Ballistics"))
  local cam = workspace.CurrentCamera
  local V2, UD2, RGB = Vector2.new, UDim2.new, Color3.fromRGB
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  -- 用户 11-27「镜子里的线条和字太粗了而且不够清晰」：线一律 1 像素（不加光晕），刻度上的数用等宽的 RobotoMono（细、数字对得齐）
  local FONT = Enum.Font.RobotoMono
  local o = {}

  ---------------------------------------------------------------- 画布：线、字的对象池（每次重画从头用，没用到的藏起来）
  local function canvas(parent, name, z)
    local c = { L = {}, T = {}, nl = 0, nt = 0, col = RGB(14, 14, 14), tr = 0, w = 1 }
    local root = Instance.new("Frame")
    root.Name = name
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.ZIndex = z
    root.Parent = parent
    c.root = root
    function c.begin() c.nl, c.nt = 0, 0 end
    -- 一根线：两端的像素坐标（相对画布中心），宽 w 像素
    function c.line(x1, y1, x2, y2, w)
      c.nl += 1
      local f = c.L[c.nl]
      if not f then
        f = Instance.new("Frame")
        f.Name = "L"
        f.BorderSizePixel = 0
        f.AnchorPoint = V2(0.5, 0.5)
        f.ZIndex = z
        f.Parent = root
        c.L[c.nl] = f
      end
      w = w or c.w
      local dx, dy = x2 - x1, y2 - y1
      if math.abs(dx) < 0.01 then
        f.Size = UDim2.fromOffset(w, math.max(math.abs(dy), w))
        f.Rotation = 0
      elseif math.abs(dy) < 0.01 then
        f.Size = UDim2.fromOffset(math.max(math.abs(dx), w), w)
        f.Rotation = 0
      else
        f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), w)
        f.Rotation = math.deg(math.atan2(dy, dx))
      end
      f.Position = UD2(0.5, math.floor((x1 + x2) / 2 + 0.5), 0.5, math.floor((y1 + y2) / 2 + 0.5))
      f.BackgroundColor3 = c.col
      f.BackgroundTransparency = c.tr
      f.Visible = true
      return f
    end
    -- 一行字：ax 0 左对齐（x 是左边）、0.5 居中、1 右对齐（x 是右边）
    function c.text(x, y, s, size, ax, ay)
      c.nt += 1
      local t = c.T[c.nt]
      if not t then
        t = Instance.new("TextLabel")
        t.Name = "T"
        t.BackgroundTransparency = 1
        t.Font = FONT
        t.ZIndex = z
        t.Parent = root
        c.T[c.nt] = t
      end
      size = size or 13
      ax = ax or 0.5
      t.Text = s
      t.TextSize = size
      t.TextColor3 = c.col
      t.TextTransparency = c.tr
      t.AnchorPoint = V2(ax, ay or 0.5)
      t.TextXAlignment = (ax >= 0.99) and Enum.TextXAlignment.Right or ((ax <= 0.01) and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center)
      t.Size = UDim2.fromOffset(math.max(28, #s * size * 0.62 + 6), size + 4)
      t.Position = UD2(0.5, math.floor(x + 0.5), 0.5, math.floor(y + 0.5))
      t.Visible = true
      return t
    end
    function c.finish()
      for i = c.nl + 1, #c.L do if c.L[i].Visible then c.L[i].Visible = false end end
      for i = c.nt + 1, #c.T do if c.T[i].Visible then c.T[i].Visible = false end end
    end
    return c
  end

  ---------------------------------------------------------------- 瞄准镜
  local root = Instance.new("Frame")
  root.Name = "GunSight"
  root.BackgroundTransparency = 1
  root.Size = UDim2.fromScale(1, 1)
  root.ZIndex = 6
  root.Parent = sightFrame
  -- 镜框的黑色渐变框（用户 11-28「开镜目前周围没有那个开镜的黑色渐变框」；原来只有四角很轻的暗角，11-27「这个做的没有3a游戏的感觉啊」）：
  --   同战雷开镜：中间一大块完全清楚，往四边越来越暗，贴着屏幕边那一道和四个角是纯黑。
  --   做法：一层层圆角矩形的描边（UIStroke 画在框外面），从清楚区的边往外一圈比一圈不透明（S 形曲线，看不出一道道环）；
  --   最外一圈描得很粗、纯黑，盖到屏幕边和四个角。窗口大小变了才重排。分划、读数的 ZIndex 在它上面（压着黑边的那截分划线跟着隐进黑里）
  --   进镜对焦（从糊到清楚 0.28 秒）、开炮那一下画面一糊（炮口冲击、镜子震）照旧
  local NVIG = 22
  local VIG = {}
  local function vigRing(tr, name)
    local f = Instance.new("Frame")
    f.Name = name or "Vig"
    f.BackgroundTransparency = 1
    f.AnchorPoint = V2(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.ZIndex = 5
    f.Parent = root
    local cr = Instance.new("UICorner")
    cr.Parent = f
    local sk = Instance.new("UIStroke")
    sk.Color = Color3.new(0, 0, 0)
    sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    sk.Transparency = tr
    sk.Parent = f
    return { f = f, s = sk, c = cr }
  end
  for i = 1, NVIG do
    local u = (i - 0.5) / NVIG   -- 0 清楚区的边 → 1 渐变带最外
    VIG[i] = vigRing(1 - 0.97 * (u * u * (3 - 2 * u)) ^ 1.15)
  end
  local vigEdge = vigRing(0, "VigEdge")
  local vigSig = nil
  local function layoutVig(vp)
    local sig = vp.X .. "x" .. vp.Y
    if sig == vigSig then return end
    vigSig = sig
    local H = vp.Y
    local band, edge, rc = H * 0.2, H * 0.015, H * 0.18   -- 渐变带宽、贴边纯黑那一道、清楚区的圆角
    local inset = band + edge
    local wc, hc = math.max(vp.X - 2 * inset, 2), math.max(H - 2 * inset, 2)
    local step = band / NVIG
    for i, v in ipairs(VIG) do
      local k = (i - 1) * step
      v.f.Size = UDim2.fromOffset(wc + 2 * k, hc + 2 * k)
      v.c.CornerRadius = UDim.new(0, rc + k)
      v.s.Thickness = step
    end
    vigEdge.f.Size = UDim2.fromOffset(wc + 2 * band, hc + 2 * band)
    vigEdge.c.CornerRadius = UDim.new(0, rc + band)
    vigEdge.s.Thickness = math.max(vp.X, H)
  end
  local focus = Instance.new("BlurEffect")
  focus.Name = "SightFocus"
  focus.Size = 0
  focus.Enabled = false
  focus.Parent = Lighting
  local RC = canvas(root, "Reticle", 6)      -- 分划（视场、弹种、装定距离变了才重画）
  local DC = canvas(root, "Dyn", 7)          -- 每帧：炮管指向、跟踪框
  -- 方位刻度（11-27 M3 丝滑：原来每帧重画 17 根线、7 个字，一帧 160 来次属性写入）：画成一条长带（镜头两边各三个窗口半宽的刻度），
  --   放在只露出窗口那么宽的裁剪框里，每帧只挪带子的 X；转出一个窗口半宽、视场 / 窗口大小 / 颜色变了才重画
  local tapeClip = Instance.new("Frame")
  tapeClip.Name = "TapeClip"
  tapeClip.BackgroundTransparency = 1
  tapeClip.ClipsDescendants = true
  tapeClip.AnchorPoint = V2(0.5, 0.5)
  tapeClip.ZIndex = 7
  tapeClip.Parent = root
  local HC = canvas(tapeClip, "Tape", 7)     -- 带子（名字、子零件跟原来一样：L 线、T 字）
  HC.root.AnchorPoint = V2(0.5, 0.5)
  local MC = canvas(root, "TapeMark", 7)     -- 中间那个 ^（不跟着挪）
  -- 镜下读数（数字火控）
  local function lbl(name, size, z)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.RobotoMono
    t.TextSize = size
    t.AnchorPoint = V2(0.5, 0.5)
    t.Size = UDim2.fromOffset(260, size + 6)
    t.ZIndex = z or 7
    t.Text = ""
    t.Parent = root
    return t
  end
  local rangeT = lbl("GsRange", 22)
  local ammoT = lbl("GsAmmo", 15)
  local statT = lbl("GsStatus", 13)
  local setT = lbl("GsSet", 15)            -- 「表尺 1200 米」（改了装定距离写一会儿）
  setT.AnchorPoint = V2(0, 0.5)
  setT.TextXAlignment = Enum.TextXAlignment.Left
  local readyB = Instance.new("Frame")
  readyB.Name = "GsReady"
  readyB.AnchorPoint = V2(0.5, 0.5)
  readyB.Size = UDim2.fromOffset(11, 11)
  readyB.BorderSizePixel = 0
  readyB.ZIndex = 7
  readyB.Parent = root
  local readyS = Instance.new("UIStroke")
  readyS.Thickness = 1.5
  readyS.Parent = readyB

  local cur = { fam = nil, famName = nil, mode = "day", col = RGB(14, 14, 14), tr = 0, sig = nil, setMsg = nil, setT = -99, lastR = nil }
  o.cur = cur
  local COL = {
    day = RGB(14, 14, 14), nv = RGB(10, 18, 10), ir = RGB(206, 236, 206), whot = RGB(238, 238, 238), bhot = RGB(14, 14, 14),
    night = RGB(232, 92, 56),   -- 白天通道夜里分划照明（真镜子的红色照明）：天黑了自动开，不然黑线看不见
  }

  -- 光电模式、年代变了（Drive applyMode 调）：分划是哪一家、什么颜色、亮度
  --   m 光电模式（day / nv / ir / whot / bhot），kit WtOptics.kit 的结果，st 正在开的车（retNight、retLvl、symLvl）
  function o.mode(m, kit, st)
    local tk = st and st.em and st.em:GetAttribute("TreeKey")
    local name, fam = SD.familyOf(kit, st and st.d and st.d.id, tk)
    cur.famName, cur.fam, cur.mode, cur.kit = name, fam, m, kit
    cur.night = (G.isNight and G.isNight()) and true or false
    cur.east = kit and kit.east == true
    local col = COL[m] or COL.day
    if m == "day" and ((st and st.retNight) or cur.night) then col = COL.night end
    cur.col = col
    cur.tr = ({ 0, 0.25, 0.5, 0.75 })[((st and st.retLvl) or 0) + 1] or 0
    cur.symTr = ({ 0, 0.3, 0.6, 1 })[((st and st.symLvl) or 0) + 1] or 0
    for _, c in ipairs({ RC, DC, HC, MC }) do c.col, c.tr = col, cur.tr end
    for _, t in ipairs({ rangeT, ammoT, statT, setT }) do t.TextColor3, t.TextTransparency = col, cur.symTr end
    readyS.Color, readyS.Transparency = col, cur.symTr
    readyB.BackgroundColor3 = col
    cur.sig = nil
    G.gunSightFamily = name   -- 测试、车里的面板看
  end

  -- 密位 → 像素
  local function geom(fov, unit)
    local vp = cam.ViewportSize
    local F = (vp.Y / 2) / math.tan(math.rad(fov) / 2)
    local rpm = SD.rad(unit)
    return { F = F, rpm = rpm, vp = vp, hw = vp.X / 2, hh = vp.Y / 2, m = function(mil) return F * math.tan(mil * rpm) end }
  end
  o.geom = geom

  -- 横线 + 刻度（每 step 密位一格，每 label 密位写数），full：线一直画到屏幕边（光学镜子），不然只画到刻度外一点（数字火控）
  local function drawLat(c, P, L, full)
    local m = P.m
    local gap = math.max(m(L.gap), 9)
    local tickPx = m(L.step)
    local outer = full and (P.hw + 4) or math.max(m(L.ext + 4), gap + 30)
    c.line(-outer, 0, -gap, 0)
    c.line(gap, 0, outer, 0)
    if tickPx < 3 then return end   -- 倍率太低、刻度挤成一团：只留横线
    local labEvery = L.label
    while m(labEvery) < 22 do labEvery *= 2 end   -- 字之间至少 22 像素
    local k = L.step
    while k <= L.ext + 1e-6 do
      local x = m(k)
      local lab = (k % L.label) == 0
      local len = lab and math.max(m(1.6), 7) or math.max(m(0.9), 4)
      for s = -1, 1, 2 do
        c.line(s * x, 0, s * x, -len)
        if lab and (k % labEvery) == 0 then c.text(s * x, -len - 9, tostring(k), 12) end
      end
      k += L.step
    end
  end

  -- 表尺：竖线左边一列（苏式，截图那样）或者北约式的横杠，每 200 米一格、400 米写数；装定的那个距离在中心
  local function drawLadder(c, P, fam, lad)
    local m = P.m
    local lastLab = -1e9
    for i, it in ipairs(lad) do
      local y = m(it.y)
      if y > -P.hh * 0.45 and y < P.hh + 4 and math.abs(y) >= 3 then
        local lab = it.label ~= nil
        if fam.ladder == "bars" then   -- 北约：横杠居中、越远越短，数写在右边
          local half = math.max(5, 12 - i * 0.35)
          c.line(-half, y, half, y)
          if lab and y - lastLab >= 13 then c.text(half + 5, y, it.label, 12, 0) lastLab = y end
        else
          local len = lab and 13 or 7
          c.line(-1, y, -len, y)
          if lab and y - lastLab >= 13 then c.text(-len - 4, y, it.label, 12, 1) lastLab = y end
        end
      end
    end
  end

  -- 上方各弹种表尺 + 指示线（苏式；这一块按像素排，不随倍率缩放——真镜子上它也是表尺不是角度）
  local function drawTop(c, P, ts)
    if not ts then return end
    local s = math.clamp(P.vp.Y / 720, 0.8, 1.6)
    local x0, y0, h = -P.hw * 0.36, -P.hh * 0.5, P.hh * 0.3   -- 中心左上方（左上角是提示框、比分条下面是目标那行字）
    local dxc = 34 * s
    local zh = G.lang ~= "en"
    for ci, col in ipairs(ts.cols) do
      local x = x0 + (ci - 1) * dxc
      c.line(x, y0, x, y0 + h, 1)
      local name = ({ ap = zh and "穿" or "AP", heat = zh and "破" or "HEAT", mpat = zh and "多" or "MP", he = zh and "榴" or "HE" })[col.cls] or col.cls
      c.text(x, y0 - 12, name, 12)
      local lastY = -1e9
      for _, tk in ipairs(col.ticks) do
        local y = y0 + tk.t * h
        c.line(x, y, x + (tk.label and 6 or 3) * s, y, 1)
        if tk.label and y - lastY >= 11 then c.text(x + 8 * s, y, tk.label, 10, 0) lastY = y end
      end
    end
    -- 指示线：横着跨所有列（装定的距离；一根线在每一列上读出那种弹的距离）
    local yi = y0 + ts.ind * h
    c.line(x0 - 8 * s, yi, x0 + (#ts.cols - 1) * dxc + 14 * s, yi, 1)
    c.line(x0 - 8 * s, yi, x0 - 14 * s, yi - 4 * s, 1)
    c.line(x0 - 8 * s, yi, x0 - 14 * s, yi + 4 * s, 1)
  end

  -- 测距曲线：目标高 h 米，在各距离（百米）上有多高（密位，真角度）；底线上一排竖杠，杠顶连成曲线，数写在底线下面
  local function drawStadia(c, P, h, unit, cx, cy, span)
    local m = P.m
    local R = SD.STADIA_R
    local pts = {}
    c.line(cx, cy, cx + span, cy, 1)
    for i, r in ipairs(R) do
      local x = cx + (i - 1) / (#R - 1) * span
      local hp = m(SD.stadiaMils(h, r, unit))
      c.line(x, cy, x, cy - hp, 1)
      c.text(x, cy + 9, tostring(r), 10)
      pts[i] = { x, cy - hp }
    end
    for i = 1, #pts - 1 do c.line(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], 1) end
  end

  -- 瞄准标
  local function drawCenter(c, P, fam)
    local m = P.m
    if fam.center == "chev" then   -- 苏式 ^：尖在瞄准点
      local hgt, wid = math.max(m(2.0), 9), math.max(m(1.25), 5.5)
      c.line(0, 0, -wid, hgt)
      c.line(0, 0, wid, hgt)
    elseif fam.center == "box" then   -- 方框，四个角留空
      local s = math.max(m(1.0), 6)
      local e = s * 0.55
      c.line(-e, -s, e, -s)
      c.line(-e, s, e, s)
      c.line(-s, -e, -s, e)
      c.line(s, -e, s, e)
    elseif fam.center == "dot" then   -- 十字留空 + 中心一个点
      local g, l = math.max(m(fam.lat.gap), 9), math.max(m(fam.lat.gap + 2), 16)
      c.line(0, -g, 0, -l)
      c.line(-1, 0, 1, 0, 2)   -- 中心一个 2 像素的点
    else   -- cross：十字留空（上面那根细线一直到顶）
      local g = math.max(m(fam.lat.gap), 9)
      c.line(0, -g, 0, -P.hh - 4, 1)
    end
  end

  local function drawReticle(fam, P, info)
    RC.begin()
    if fam then
      local classic = fam.ladder ~= nil
      drawLat(RC, P, fam.lat, classic)
      drawCenter(RC, P, fam)
      -- 中心往下的竖线：光学镜子画到屏幕底（表尺挂在上面），数字火控只一小截
      local y0 = math.max(P.m(fam.vline or 3), 9)
      local y1 = classic and (P.hh + 4) or math.max(P.m(fam.vlen or 10), y0 + 14)
      RC.line(0, y0, 0, y1)
      if classic and info.ladder then drawLadder(RC, P, fam, info.ladder) end
      if fam.top and info.top then drawTop(RC, P, info.top) end
      if fam.stadia then drawStadia(RC, P, fam.stadia, fam.unit, -P.hw * 0.56, P.hh * 0.32, P.hw * 0.3) end   -- 左下（再往下是损伤图）
    end
    RC.finish()
  end

  -- 顶上方位刻度：镜头朝向（度），刻度跟着视场——一度多少像素和画面上一样
  local CARD = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
  local tape = { vx = nil, vy = nil, px = nil, col = nil, tr = nil, base = 0, xo = nil }
  local function drawTape(P, hdg)
    local s = math.clamp(P.vp.Y / 720, 0.8, 1.6)
    local y = -P.hh + 128 * s   -- 顶上是比分条（Hud，到 82）和目标那行字（到 108）：刻度放在它们下面
    local half = P.hw * 0.34
    local pxDeg = P.F * math.rad(1)
    local d = ((hdg - tape.base + 540) % 360) - 180   -- 镜头离带子中间多少度
    if tape.vx ~= P.vp.X or tape.vy ~= P.vp.Y or math.abs((tape.px or 0) - pxDeg) > 1e-3 or tape.col ~= HC.col or tape.tr ~= HC.tr
      or math.abs(d) * pxDeg > half then
      tape.vx, tape.vy, tape.px, tape.col, tape.tr = P.vp.X, P.vp.Y, pxDeg, HC.col, HC.tr
      tape.base, d, tape.xo = hdg, 0, nil
      local H = math.floor(34 * s + 0.5)
      local yc = y - 2 * s   -- 框的中线：字在上、刻度在下
      local ty = y - yc
      local span = half * 3
      tapeClip.Size = UDim2.fromOffset(math.floor(2 * half + 0.5), H)
      tapeClip.Position = UD2(0.5, 0, 0.5, math.floor(yc + 0.5))
      HC.root.Size = UDim2.fromOffset(math.floor(2 * span + 0.5), H)
      HC.begin()
      local minor, major = SD.tapeSteps(pxDeg)
      local a = math.floor((hdg - span / pxDeg) / minor) * minor
      while (a - hdg) * pxDeg <= span do
        local x = (a - hdg) * pxDeg
        if x >= -span then
          local aa = a % 360
          local big = (aa % major) == 0
          HC.line(x, ty, x, ty + (big and 8 or 4) * s, 1)
          if big then HC.text(x, ty - 8 * s, CARD[aa] or tostring(aa), 13) end
        end
        a += minor
      end
      HC.finish()
      MC.begin()
      MC.line(-6 * s, y + 16 * s, 0, y + 10 * s, 1)
      MC.line(6 * s, y + 16 * s, 0, y + 10 * s, 1)
      MC.finish()
    end
    local xo = math.floor(-d * pxDeg + 0.5)
    if xo ~= tape.xo then
      tape.xo = xo
      HC.root.Position = UD2(0.5, xo, 0.5, 0)
    end
  end
  o.tapeState = function() return { base = tape.base, xo = tape.xo, clip = tapeClip, strip = HC.root } end   -- 测试用

  -- info（Drive 每帧给）：
  --   am / wid / amKey 弹、炮、弹种键（不是坦克炮时 nil）；R0 装定距离（米，没装定是 bs 战斗瞄准距离）；man / est 手动装定、车长估的；
  --   markPt 炮管实际指着的点（世界坐标，不含超高角）；trk 自动跟踪锁着的车；fcs 火控状态（数字读数）；ready 装好弹；yaw 镜头偏航
  function o.step(st, info)
    local fam = cur.fam
    if not fam then return end
    -- 天黑了 / 天亮了：白天通道的分划自动开 / 关照明（不然半夜黑线看不见）
    local nightNow = (G.isNight and G.isNight()) and true or false
    if nightNow ~= cur.night and cur.kit then o.mode(cur.mode, cur.kit, st) end
    local fov = cam.FieldOfView
    local P = geom(fov, fam.unit)
    layoutVig(P.vp)
    -- 对焦、开炮的一糊
    do
      local now = os.clock()
      if st.fireT and st.fireT ~= cur.lastFire then cur.lastFire, cur.fireSeen = st.fireT, now end
      local fs = 0
      if cur.focusT then
        local u = math.clamp((now - cur.focusT) / 0.28, 0, 1)
        fs = 9 * (1 - u) ^ 3
      end
      if cur.fireSeen then fs += 3 * math.exp(-(now - cur.fireSeen) * 10) end
      focus.Size = fs
      focus.Enabled = fs > 0.05
    end
    -- 表尺、上方表尺（弹种、装定距离变了才重算）
    local R0 = info.R0 or 0
    local key = info.amKey or ""
    local sig = string.format("%s|%d|%d|%.3f|%s|%d|%s|%s|%.2f", cur.famName, P.vp.X, P.vp.Y, fov, key, math.floor(R0 + 0.5), cur.mode,
      tostring(cur.col), cur.tr)
    if sig ~= cur.sig then
      cur.sig = sig
      if fam.ladder and info.am then info.ladder = SD.ladder(BAL, info.am, R0, fam.unit) end
      if fam.top and info.wid then info.top = SD.topScales(BAL, info.wid, key, R0) end
      drawReticle(fam, P, info)
      o.lastLadder, o.lastTop = info.ladder, info.top
    end
    -- 每帧：炮管指向（小圈）、自动跟踪框
    DC.begin()
    if info.markPt then
      local sp, on = cam:WorldToViewportPoint(info.markPt)
      if on then
        local dx, dy = sp.X - P.hw, sp.Y - P.hh
        if dx * dx + dy * dy > 16 then   -- 偏出中心 4 像素以上才画（炮塔还没转过来）
          local r = 8
          DC.line(dx - r, dy, dx - 3, dy, 1)
          DC.line(dx + 3, dy, dx + r, dy, 1)
          DC.line(dx, dy - r, dx, dy - 3, 1)
          DC.line(dx, dy + 3, dx, dy + r, 1)
        end
      end
    end
    if info.trk and info.trk.Parent then
      local ok, pv = pcall(function() return info.trk:GetPivot().Position end)
      if ok then
        local sp, on = cam:WorldToViewportPoint(pv)
        if on then
          local dx, dy, b = sp.X - P.hw, sp.Y - P.hh, 22
          DC.line(dx - b, dy - b, dx - b * 0.4, dy - b, 1) DC.line(dx + b * 0.4, dy - b, dx + b, dy - b, 1)
          DC.line(dx - b, dy + b, dx - b * 0.4, dy + b, 1) DC.line(dx + b * 0.4, dy + b, dx + b, dy + b, 1)
          DC.line(dx - b, dy - b, dx - b, dy - b * 0.4, 1) DC.line(dx - b, dy + b * 0.4, dx - b, dy + b, 1)
          DC.line(dx + b, dy - b, dx + b, dy - b * 0.4, 1) DC.line(dx + b, dy + b * 0.4, dx + b, dy + b, 1)
        end
      end
    end
    DC.finish()
    -- 方位刻度
    drawTape(P, SD.heading(info.yaw or 0))
    -- 数字读数（数字火控、TPD-K1 一类有激光的）：镜下一行
    local digital = fam.digital == true or (fam.digital == "lrf" and info.lrf)
    local s = math.clamp(P.vp.Y / 720, 0.8, 1.6)
    local yb = P.hh * 0.44
    rangeT.Visible, ammoT.Visible, readyB.Visible, statT.Visible = digital and info.am ~= nil, digital and info.am ~= nil, digital and info.am ~= nil, digital
    if digital and info.am then
      local f = info.fcs or {}
      rangeT.Text = f.R and ((f.lrf == "FIRST" and "F " or "") .. string.format("%04d", f.R)) or (f.noRet and "----" or string.format("BS %04d", info.bs or 0))
      rangeT.Position = UD2(0.5, 0, 0.5, yb)
      ammoT.Text = info.am.sym or ""
      ammoT.Position = UD2(0.5, -120 * s, 0.5, yb)
      readyB.Position = UD2(0.5, 96 * s, 0.5, yb)
      readyB.BackgroundTransparency = info.ready and cur.symTr or 1
      statT.Text = info.status or ""
      statT.Position = UD2(0.5, 0, 0.5, yb - 26 * s)
    elseif digital then
      statT.Text = info.status or ""
      statT.Position = UD2(0.5, 0, 0.5, yb - 26 * s)
    end
    -- 装定距离改了：左边写一会儿（光学镜子没有数字读数，真车是看表尺上的指示线；这里照游戏那样提示一下）
    local now = os.clock()
    local f = info.fcs
    local Rk = f and (f.R or -1) or -1
    if cur.lastR ~= nil and Rk ~= cur.lastR and Rk >= 0 then
      cur.setMsg = info.est and T("gs.estR", Rk) or T("gs.sightSet", Rk)
      cur.setT = now
    end
    cur.lastR = Rk
    local estimating = f and f.estimating
    setT.Position = UD2(0.5, 26, 0.5, P.hh * 0.2)   -- 竖线右边（左边是表尺）
    if estimating then
      setT.Text = T("wtt.est")
      setT.TextTransparency = cur.symTr
      setT.Visible = true
    elseif cur.setMsg and now - cur.setT < 2.6 then
      setT.Text = cur.setMsg
      setT.TextTransparency = math.max(cur.symTr, math.clamp((now - cur.setT - 1.8) / 0.8, 0, 1))
      setT.Visible = true
    else
      setT.Visible = false
    end
  end

  function o.reset(on)   -- 进镜 / 出镜（Drive setSight）：下次进镜从头画；进镜对焦、出镜撤掉模糊
    cur.sig, cur.lastR, cur.setMsg = nil, nil, nil
    if on then
      cur.focusT, cur.lastFire = os.clock(), nil
      focus.Size, focus.Enabled = 9, true
    else
      cur.focusT = nil
      focus.Size, focus.Enabled = 0, false
    end
  end

  ---------------------------------------------------------------- 车长望远镜
  -- 用户 11-27：「再做一个望远镜」，又「望远镜没有渐变啊」「这个做的没有3a游戏的感觉啊」——
  --   镜筒：两个圆（左右各在半边屏幕的裁剪框里：半边里两圆的并集正好是那一边的圆），圆外纯黑；
  --   圆里：边缘 24 圈细环叠成平滑的渐暗（越靠边越暗）、边上一道很淡的色散（外暖内冷）、斜着一片镀膜反光（对着太阳亮）；
  --   举起来：先黑、镜筒从小放到正常、画面从糊到清楚（0.35 秒）；转得快画面微糊、停下来清楚；镀膜偏暖、对比高一点；
  --   手的呼吸晃动在 Drive 的镜头上（只晃画面，不带炮塔）
  -- 单独一层、压在界面下面（DisplayOrder 2）：两个圆外面的黑只盖画面，比分条、小地图、弹药栏、损伤图照样在上面（战雷的望远镜也是这样）
  local bgui = Instance.new("ScreenGui")
  bgui.Name = "BinoView"
  bgui.ResetOnSpawn = false
  bgui.IgnoreGuiInset = true
  bgui.DisplayOrder = 2
  bgui.Parent = gui.Parent
  local bino = Instance.new("Frame")
  bino.Name = "Binoculars"
  bino.BackgroundTransparency = 1
  bino.Size = UDim2.fromScale(1, 1)
  bino.Visible = false
  bino.ZIndex = 8
  bino.Parent = bgui
  local NRING = 24
  local function half(x)
    local clip = Instance.new("Frame")
    clip.Name = (x == 0) and "ClipL" or "ClipR"
    clip.BackgroundTransparency = 1
    clip.ClipsDescendants = true
    clip.Size = UDim2.fromScale(0.5, 1)
    clip.Position = UDim2.fromScale(x, 0)
    clip.ZIndex = 8
    clip.Parent = bino
    local function circle(name)
      local f = Instance.new("Frame")
      f.Name = name
      f.BackgroundTransparency = 1
      f.AnchorPoint = V2(0.5, 0.5)
      f.ZIndex = 8
      f.Parent = clip
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(0.5, 0)
      cr.Parent = f
      return f
    end
    local function ring(name, col, tr)
      local f = circle(name)
      local sk = Instance.new("UIStroke")
      sk.Color = col or Color3.new(0, 0, 0)
      sk.Transparency = tr or 0
      sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      sk.Parent = f
      return { f = f, s = sk }
    end
    local L = { clip = clip }
    L.eye = ring("Eye")
    L.eye.s.Thickness = 1600
    L.rings = {}
    for i = 1, NRING do   -- 边缘渐暗：第 1 圈贴着镜筒最暗，往里一圈比一圈淡（指数 2.4，没有一道道的环）
      L.rings[i] = ring("Soft", nil, 1 - 0.93 * ((NRING - i + 1) / NRING) ^ 2.4)
    end
    L.warm = ring("FringeW", RGB(255, 150, 70), 0.8)    -- 色散：最外一道偏暖
    L.cool = ring("FringeC", RGB(110, 200, 205), 0.87)  -- 往里一点偏冷
    L.glare = circle("Glare")   -- 镀膜反光：左上方斜着一片，往右下淡没
    L.glare.BackgroundColor3 = Color3.new(1, 1, 1)
    L.glare.BackgroundTransparency = 0.9
    local g = Instance.new("UIGradient")
    g.Rotation = 35
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.28, 0.86),
      NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = L.glare
    return L
  end
  local LL = half(0)
  local RR = half(0.5)
  local function layoutLens(L, cx, cy, D)
    local pos = UDim2.fromOffset(cx, cy)
    L.eye.f.Size, L.eye.f.Position = UDim2.fromOffset(D, D), pos
    local R = D / 2
    local step = math.max(1, R * 0.011)
    for i, r in ipairs(L.rings) do
      local outer = R - (i - 1) * step
      local d = math.max(2, 2 * (outer - step))
      r.f.Size, r.f.Position = UDim2.fromOffset(d, d), pos
      r.s.Thickness = step
    end
    L.warm.f.Size, L.warm.f.Position, L.warm.s.Thickness = UDim2.fromOffset(D - 4, D - 4), pos, 1.5
    L.cool.f.Size, L.cool.f.Position, L.cool.s.Thickness = UDim2.fromOffset(D - 9, D - 9), pos, 1.5
    L.glare.Size, L.glare.Position = UDim2.fromOffset(D * 0.96, D * 0.96), pos
  end
  o.binoLens = { LL, RR }   -- 测试看
  local BC = canvas(bino, "BinoRet", 9)
  -- 底下的读数：垫一条两头渐隐的暗底（亮的天、雪地上也看得清）
  local strip = Instance.new("Frame")
  strip.Name = "BinoStrip"
  strip.AnchorPoint = V2(0.5, 1)
  strip.Size = UDim2.fromOffset(560, 52)
  strip.Position = UD2(0.5, 0, 1, -94)
  strip.BackgroundColor3 = Color3.new(0, 0, 0)
  strip.BackgroundTransparency = 0.45
  strip.BorderSizePixel = 0
  strip.ZIndex = 9
  strip.Parent = bino
  do
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.22, 0), NumberSequenceKeypoint.new(0.78, 0), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = strip
  end
  local binoT = Instance.new("TextLabel")
  binoT.Name = "BinoInfo"
  binoT.BackgroundTransparency = 1
  binoT.Font = Enum.Font.RobotoMono
  binoT.TextSize = 16
  binoT.TextColor3 = (G.Theme and G.Theme.C.TEXT) or RGB(230, 232, 226)
  binoT.AnchorPoint = V2(0.5, 1)
  binoT.Size = UDim2.fromOffset(700, 22)
  binoT.Position = UD2(0.5, 0, 1, -100)   -- 弹药栏上面
  binoT.ZIndex = 10
  binoT.Parent = bino
  local binoH = binoT:Clone()
  binoH.Name = "BinoHint"
  binoH.TextSize = 13
  binoH.TextColor3 = (G.Theme and (G.Theme.C.MUTE or G.Theme.C.FAINT)) or RGB(170, 174, 168)
  binoH.Position = UD2(0.5, 0, 1, -124)
  binoH.Parent = bino
  -- 举起来那一下：先黑再亮
  local fade = Instance.new("Frame")
  fade.Name = "BinoFade"
  fade.BackgroundColor3 = Color3.new(0, 0, 0)
  fade.BorderSizePixel = 0
  fade.Size = UDim2.fromScale(1, 1)
  fade.BackgroundTransparency = 1
  fade.ZIndex = 12
  fade.Parent = bino
  local blurB = Instance.new("BlurEffect")   -- 对焦：举起来时从糊到清楚；转得快微糊
  blurB.Name = "BinoBlur"
  blurB.Size = 0
  blurB.Enabled = false
  blurB.Parent = Lighting
  local ccB = Instance.new("ColorCorrectionEffect")   -- 镀膜：偏暖、对比高一点、饱和度低一点
  ccB.Name = "BinoCC"
  ccB.Contrast, ccB.Saturation, ccB.Brightness, ccB.TintColor = 0.07, -0.06, 0.015, RGB(255, 247, 234)
  ccB.Enabled = false
  ccB.Parent = Lighting
  local banim = { t0 = -99, look = nil, pan = 0, lastT = nil }
  local binoSig, lensSig = nil, nil
  -- 倍率：举起来默认 SD.BINOC.mag（8 倍），滚轮在 mags 里一格一格换（用户 11-28「望远镜要能缩放」）；换了以后 Drive 把视场缓过去，
  --   分划按现在的视场重画（密位刻度、估距的格子跟着放大缩小，读数照样对）；下次举起来还是上次的倍率
  local BMAGS = SD.BINOC.mags or { SD.BINOC.mag }
  o.binoMag = SD.BINOC.mag
  o.binoFov = 70 / o.binoMag
  function o.binoZoom(dir)
    local at = 1
    for i, v in ipairs(BMAGS) do if v == o.binoMag then at = i end end
    local m = BMAGS[math.clamp(at + (dir or 0), 1, #BMAGS)]
    if m ~= o.binoMag then
      o.binoMag = m
      o.binoFov = 70 / m
      if G.sfx then pcall(G.sfx, "uiClick") end
    end
    return o.binoMag
  end

  function o.binoShow(on, kit)
    bino.Visible = on and true or false
    binoSig, lensSig = nil, nil
    if kit then cur.east = kit.east == true end   -- 望远镜的密位制跟着东西方（北约 6400）
    blurB.Enabled, ccB.Enabled = bino.Visible, bino.Visible
    if on then
      banim.t0, banim.look, banim.pan, banim.lastT = os.clock(), nil, 0, nil
      blurB.Size = 14
      fade.BackgroundTransparency = 0
    else
      blurB.Size = 0
    end
  end
  function o.binoOn() return bino.Visible end
  -- 手持的呼吸晃动（Drive 乘在镜头上；瞄准点、炮塔照旧按没晃的算）：两三个慢正弦叠起来，±0.05° 左右，8 倍下是几个像素的漂
  function o.binoSway()
    local t = os.clock()
    return CFrame.Angles(math.sin(t * 0.9 + 2) * 0.0006 + math.sin(t * 2.3) * 0.00022, math.sin(t * 1.1) * 0.0008 + math.sin(t * 2.7 + 1) * 0.00025, 0)
  end

  -- info：{ R 估的距离（米）, est 正在估, yaw 镜头偏航 }
  function o.binoStep(info)
    local vp = cam.ViewportSize
    local now = os.clock()
    local u = math.clamp((now - banim.t0) / 0.35, 0, 1)
    local e = 1 - (1 - u) ^ 3
    local D = vp.Y * 0.9 * (0.9 + 0.1 * e)   -- 举起来：镜筒从小放到正常
    local off = D * 0.27
    -- 两只镜筒一共五十几个圈：举起来那 0.35 秒以后大小不变，窗口、镜筒没变就不再每帧重写（原来每帧写 170 来个属性）
    if not lensSig or lensSig[1] ~= vp.X or lensSig[2] ~= vp.Y or math.abs(lensSig[3] - D) > 0.01 then
      lensSig = { vp.X, vp.Y, D }
      layoutLens(LL, vp.X / 2 - off, vp.Y / 2, D)
      layoutLens(RR, off, vp.Y / 2, D)
    end
    local fa = math.clamp((now - banim.t0) / 0.16, 0, 1)
    if fade.BackgroundTransparency ~= fa then fade.BackgroundTransparency = fa end
    -- 转得快：画面微糊（眼睛、焦距跟不上），停下来清楚
    local lv = cam.CFrame.LookVector
    local dtv = banim.lastT and (now - banim.lastT) or 0
    banim.lastT = now
    if banim.look and dtv > 0 then
      local ang = math.acos(math.clamp(lv:Dot(banim.look), -1, 1)) / dtv
      local target = math.clamp((ang - 0.12) * 5, 0, 3)
      banim.pan += (target - banim.pan) * math.min(1, dtv * 8)
    end
    banim.look = lv
    -- 对焦放完、没在转：模糊几乎是 0——关掉（11-27 M3 丝滑：Size 0 也开着是白画一遍全屏后期）
    local bs = 14 * (1 - e) + banim.pan
    blurB.Size = bs
    local bOn = bino.Visible and bs > 0.05
    if blurB.Enabled ~= bOn then blurB.Enabled = bOn end
    -- 镀膜反光：对着太阳亮（夜里不亮）
    local okS, sun = pcall(function() return Lighting:GetSunDirection() end)
    local k = okS and sun and math.clamp((lv:Dot(sun) - 0.55) / 0.45, 0, 1) or 0
    local gt = (G.isNight and G.isNight()) and 0.97 or (0.9 - 0.42 * k)
    LL.glare.BackgroundTransparency, RR.glare.BackgroundTransparency = gt, gt
    local B = SD.BINOC
    local unit = (cur.east == false) and 6400 or B.unit   -- 北约的车：6400 制望远镜（M22 一类）
    local P = geom(cam.FieldOfView, unit)
    local sig = string.format("%d|%d|%.2f|%d", vp.X, vp.Y, cam.FieldOfView, unit)
    if sig ~= binoSig then
      binoSig = sig
      BC.begin()
      BC.col, BC.tr = RGB(22, 22, 20), 0.08   -- 刻在镜片上的线：深灰、一点点透（不是死黑的贴纸）
      local m = P.m
      -- 横的密位尺：每 5 密位一格、每 10 写数（苏式 BPC 望远镜的分划：10 20 30 40）
      local ext = m(B.lat.ext)
      BC.line(-ext, 0, ext, 0, 1)
      local k2 = B.lat.step
      while k2 <= B.lat.ext do
        local x = m(k2)
        local lab = (k2 % B.lat.label) == 0
        local len = lab and 9 or 5
        BC.line(x, 0, x, -len, 1)
        BC.line(-x, 0, -x, -len, 1)
        if lab then
          BC.text(x, -len - 8, tostring(k2), 11)
          BC.text(-x, -len - 8, tostring(k2), 11)
        end
        k2 += B.lat.step
      end
      -- 竖的密位尺：中心往下
      BC.line(0, 4, 0, m(B.vext), 1)
      local j = B.vstep
      while j <= B.vext do
        local y = m(j)
        BC.line(0, y, (j % 10 == 0) and 9 or 5, y, 1)
        if j % 10 == 0 then BC.text(16, y, tostring(j), 11, 0) end
        j += B.vstep
      end
      BC.line(-5, -4, 0, 0, 1)   -- 中心一个小 ^
      BC.line(5, -4, 0, 0, 1)
      drawStadia(BC, P, B.stadia, unit, P.hw * 0.18, P.hh * 0.42, P.hw * 0.24)
      BC.finish()
    end
    local hdg = SD.heading(info.yaw or 0)
    local rtxt
    if info.est then rtxt = T("wtt.est")
    elseif info.R then rtxt = T("gs.estR", info.R)
    else rtxt = T("gs.binoR") end
    binoT.Text = string.format("%s    %s    ×%d", rtxt, T("gs.hdg", math.floor(hdg + 0.5) % 360), o.binoMag or B.mag)
    binoH.Text = T("gs.binoHint")
  end

  return o
end

return GunSight
