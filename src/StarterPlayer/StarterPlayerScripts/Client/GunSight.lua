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
  local RC = canvas(root, "Reticle", 6)      -- 分划（视场、弹种、装定距离变了才重画）
  local DC = canvas(root, "Dyn", 7)          -- 每帧：炮管指向、跟踪框
  local HC = canvas(root, "Tape", 7)         -- 方位刻度
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
    for _, c in ipairs({ RC, DC, HC }) do c.col, c.tr = col, cur.tr end
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
  local function drawTape(P, hdg)
    HC.begin()
    local s = math.clamp(P.vp.Y / 720, 0.8, 1.6)
    local y = -P.hh + 128 * s   -- 顶上是比分条（Hud，到 82）和目标那行字（到 108）：刻度放在它们下面
    local half = P.hw * 0.34
    local pxDeg = P.F * math.rad(1)
    local minor, major = SD.tapeSteps(pxDeg)
    local first = math.floor((hdg - half / pxDeg) / minor) * minor
    local a = first
    local CARD = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
    while (a - hdg) * pxDeg <= half do
      local x = (a - hdg) * pxDeg
      if x >= -half then
        local aa = a % 360
        local big = (aa % major) == 0
        HC.line(x, y, x, y + (big and 8 or 4) * s, 1)
        if big then HC.text(x, y - 8 * s, CARD[aa] or tostring(aa), 13) end
      end
      a += minor
    end
    HC.line(-6 * s, y + 16 * s, 0, y + 10 * s, 1)
    HC.line(6 * s, y + 16 * s, 0, y + 10 * s, 1)
    HC.finish()
  end

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

  function o.reset()   -- 出镜 / 换车：下次进镜从头画
    cur.sig, cur.lastR, cur.setMsg = nil, nil, nil
  end

  ---------------------------------------------------------------- 车长望远镜
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
  -- 两个圆（左右各在半边屏幕的裁剪框里：半边里两圆的并集就是那一边的圆）
  local function half(x)
    local clip = Instance.new("Frame")
    clip.Name = (x == 0) and "ClipL" or "ClipR"
    clip.BackgroundTransparency = 1
    clip.ClipsDescendants = true
    clip.Size = UDim2.fromScale(0.5, 1)
    clip.Position = UDim2.fromScale(x, 0)
    clip.ZIndex = 8
    clip.Parent = bino
    local circ = Instance.new("Frame")
    circ.Name = "Eye"
    circ.BackgroundTransparency = 1
    circ.AnchorPoint = V2(0.5, 0.5)
    circ.ZIndex = 8
    circ.Parent = clip
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = circ
    local stk = Instance.new("UIStroke")
    stk.Thickness = 1600
    stk.Color = Color3.new(0, 0, 0)
    stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stk.Parent = circ
    return clip, circ
  end
  local clipL, eyeL = half(0)
  local clipR, eyeR = half(0.5)
  local BC = canvas(bino, "BinoRet", 9)
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
  local binoSig = nil
  o.binoFov = 70 / SD.BINOC.mag

  function o.binoShow(on, kit)
    bino.Visible = on and true or false
    binoSig = nil
    if kit then cur.east = kit.east == true end   -- 望远镜的密位制跟着东西方（北约 6400）
  end
  function o.binoOn() return bino.Visible end

  -- info：{ R 估的距离（米）, est 正在估, yaw 镜头偏航 }
  function o.binoStep(info)
    local vp = cam.ViewportSize
    local D = vp.Y * 0.9
    local off = D * 0.27
    eyeL.Size, eyeR.Size = UDim2.fromOffset(D, D), UDim2.fromOffset(D, D)
    eyeL.Position = UDim2.fromOffset(vp.X / 2 - off, vp.Y / 2)
    eyeR.Position = UDim2.fromOffset(off, vp.Y / 2)
    local B = SD.BINOC
    local unit = (cur.east == false) and 6400 or B.unit   -- 北约的车：6400 制望远镜（M22 一类）
    local P = geom(cam.FieldOfView, unit)
    local sig = string.format("%d|%d|%.2f|%d", vp.X, vp.Y, cam.FieldOfView, unit)
    if sig ~= binoSig then
      binoSig = sig
      BC.begin()
      BC.col, BC.tr = RGB(16, 16, 16), 0
      local m = P.m
      -- 横的密位尺：每 5 密位一格、每 10 写数（苏式 BPC 望远镜的分划：10 20 30 40）
      local ext = m(B.lat.ext)
      BC.line(-ext, 0, ext, 0, 1)
      local k = B.lat.step
      while k <= B.lat.ext do
        local x = m(k)
        local lab = (k % B.lat.label) == 0
        local len = lab and 9 or 5
        BC.line(x, 0, x, -len, 1)
        BC.line(-x, 0, -x, -len, 1)
        if lab then
          BC.text(x, -len - 8, tostring(k), 11)
          BC.text(-x, -len - 8, tostring(k), 11)
        end
        k += B.lat.step
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
    binoT.Text = string.format("%s    %s    ×%d", rtxt, T("gs.hdg", math.floor(hdg + 0.5) % 360), B.mag)
    binoH.Text = T("gs.binoHint")
  end

  return o
end

return GunSight
