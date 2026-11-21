-- Roblox全面大战场（客户端）——内饰里各块屏幕的页面（SurfaceGui），由 Interior.lua 按实时数据刷新
--   热像（CITV、驾驶员视觉增强器、炮长面板的小窗）：没有第二台摄像机，按地形高度图一列列算山脊线（软件渲染），
--     车、人按真实位置投到画面上（白热 / 黑热）；遮挡也按地形算——看得见什么就是什么
--   指挥地图（JBC-P）：附近 ±1.6 公里的陆地按高度分层（一行行合并的色块）、据点、友军、看得见的敌人、自己的车和炮的指向
--   驾驶员仪表（DID）：车速、转速、油量、挡位、炮塔相对车体的方位、告警；炮长面板（GCDP）：弹种、待发、测距、倍率、极性
--   页面用 build(s, env) 搭界面，返回 update(d)（d 是 Interior 每次给的数据，见 Interior.lua 的 gather）
local Screens = {}
local RGB = Color3.fromRGB
local UD2 = UDim2.new
local V3 = Vector3.new
local PI = math.pi
local FONT = Enum.Font.Code
local FONTB = Enum.Font.GothamBold
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

---------------------------------------------------------------- 画图的小工具（像素坐标）

local function F(parent, x, y, w, h, col, tr, z)
  local f = Instance.new("Frame")
  f.Position = UD2(0, x, 0, y)
  f.Size = UD2(0, w, 0, h)
  f.BackgroundColor3 = col or RGB(0, 0, 0)
  f.BackgroundTransparency = tr or 0
  f.BorderSizePixel = 0
  f.ZIndex = z or 1
  f.Parent = parent
  return f
end
Screens.F = F
local function Tx(parent, s, x, y, w, h, size, col, align, font, z)
  local l = Instance.new("TextLabel")
  l.Position = UD2(0, x, 0, y)
  l.Size = UD2(0, w, 0, h)
  l.BackgroundTransparency = 1
  l.Text = s
  l.TextSize = size
  l.TextColor3 = col or RGB(255, 255, 255)
  l.Font = font or FONT
  l.TextXAlignment = align or Enum.TextXAlignment.Left
  l.TextYAlignment = Enum.TextYAlignment.Center
  l.ZIndex = z or 3
  l.Parent = parent
  return l
end
Screens.Tx = Tx
-- 一条线（转过角度的细框）
local function Ln(parent, x0, y0, x1, y1, t, col, z)
  local f = Instance.new("Frame")
  f.AnchorPoint = Vector2.new(0.5, 0.5)
  f.BorderSizePixel = 0
  f.BackgroundColor3 = col or RGB(255, 255, 255)
  f.ZIndex = z or 2
  f.Parent = parent
  local function set(a0, b0, a1, b1)
    local dx, dy = a1 - a0, b1 - b0
    f.Position = UD2(0, (a0 + a1) / 2, 0, (b0 + b1) / 2)
    f.Size = UD2(0, math.sqrt(dx * dx + dy * dy), 0, t or 1)
    f.Rotation = math.deg(math.atan2(dy, dx))
  end
  set(x0, y0, x1, y1)
  return f, set
end
Screens.Ln = Ln
-- 圆圈（描边）
local function Ring(parent, cx, cy, r, t, col, z, fill)
  local f = Instance.new("Frame")
  f.AnchorPoint = Vector2.new(0.5, 0.5)
  f.Position = UD2(0, cx, 0, cy)
  f.Size = UD2(0, r * 2, 0, r * 2)
  f.BackgroundColor3 = fill or RGB(0, 0, 0)
  f.BackgroundTransparency = fill and 0 or 1
  f.ZIndex = z or 2
  f.Parent = parent
  local c = Instance.new("UICorner")
  c.CornerRadius = UDim.new(0.5, 0)
  c.Parent = f
  if t and t > 0 then
    local s = Instance.new("UIStroke")
    s.Thickness = t
    s.Color = col or RGB(255, 255, 255)
    s.Parent = f
  end
  return f
end
Screens.Ring = Ring
local function grad(f, c0, c1, rot)
  local g = Instance.new("UIGradient")
  g.Color = ColorSequence.new(c0, c1)
  g.Rotation = rot or 90
  g.Parent = f
  return g
end
-- 方框（只描边）
local function Box(parent, x, y, w, h, t, col, z)
  local f = F(parent, x, y, w, h, RGB(0, 0, 0), 1, z)
  local s = Instance.new("UIStroke")
  s.Thickness = t or 1
  s.Color = col or RGB(255, 255, 255)
  s.Parent = f
  return f, s
end
Screens.Box = Box

---------------------------------------------------------------- 热像（软件渲染）

-- 极性 / 模式的配色：天、远处地面、近处地面、热目标
local PAL = {
  WHT = { sky0 = RGB(10, 12, 12), sky1 = RGB(46, 48, 48), g0 = RGB(70, 72, 70), g1 = RGB(122, 124, 120), hot = RGB(245, 245, 238), warm = RGB(190, 190, 184), ridge = RGB(150, 152, 146) },
  BLK = { sky0 = RGB(236, 236, 230), sky1 = RGB(200, 200, 194), g0 = RGB(170, 170, 164), g1 = RGB(120, 120, 116), hot = RGB(12, 12, 12), warm = RGB(60, 60, 58), ridge = RGB(110, 110, 106) },
  DAY = { sky0 = RGB(18, 26, 38), sky1 = RGB(52, 64, 78), g0 = RGB(46, 54, 40), g1 = RGB(66, 72, 52), hot = RGB(30, 32, 30), warm = RGB(60, 62, 56), ridge = RGB(70, 80, 60) },
  GRN = { sky0 = RGB(4, 16, 6), sky1 = RGB(20, 60, 26), g0 = RGB(40, 110, 50), g1 = RGB(80, 170, 90), hot = RGB(210, 255, 210), warm = RGB(150, 230, 160), ridge = RGB(110, 200, 120) },
}
Screens.PAL = PAL

-- 在 parent（W × H 像素）里画热像；返回 { render(view) }：view = { eye, f, r, u（世界坐标的基）, hfov 水平视角（度）, pal, ents, Map, range }
function Screens.thermal(parent, W, H, opt)
  opt = opt or {}
  local N = opt.cols or 36
  local o = {}
  local sky = F(parent, 0, 0, W, H, RGB(255, 255, 255), 0, 1)
  local skyG = grad(sky, RGB(0, 0, 0), RGB(0, 0, 0), 90)
  local cw = W / N
  local cols = {}
  for i = 1, N do
    local c = F(parent, math.floor((i - 1) * cw), H, math.ceil(cw) + 1, 0, RGB(255, 255, 255), 0, 2)
    local g = grad(c, RGB(0, 0, 0), RGB(0, 0, 0), 90)
    local edge = F(c, 0, 0, math.ceil(cw) + 1, 2, RGB(255, 255, 255), 0, 3)
    cols[i] = { f = c, g = g, e = edge, top = H }
  end
  local blobs = {}
  local function blob(i)
    local b = blobs[i]
    if not b then
      local f = F(parent, 0, 0, 4, 4, RGB(255, 255, 255), 0, 4)
      local cr = Instance.new("UICorner")
      cr.CornerRadius = UDim.new(0.35, 0)
      cr.Parent = f
      local core = F(f, 0, 0, 2, 2, RGB(255, 255, 255), 0, 5)
      core.AnchorPoint = Vector2.new(0.5, 0.5)
      core.Position = UD2(0.5, 0, 0.55, 0)
      core.Size = UD2(0.55, 0, 0.45, 0)
      local cc = Instance.new("UICorner")
      cc.CornerRadius = UDim.new(0.5, 0)
      cc.Parent = core
      b = { f = f, core = core }
      blobs[i] = b
    end
    return b
  end
  -- 噪点（热像的颗粒感）：几条半透明的横纹，每次随机挪
  local grain = {}
  for i = 1, 6 do grain[i] = F(parent, 0, 0, W, 1, RGB(255, 255, 255), 0.93, 6) end
  local cache = { eye = nil, f = nil, fov = nil }
  local DIST = { 6, 10, 16, 24, 34, 46, 60, 78, 100, 130, 170, 220, 290, 380, 500, 650, 850, 1100, 1450, 1900, 2500, 3300 }

  function o.render(view)
    local pal = view.pal or PAL.WHT
    local eye, f, r, u = view.eye, view.f, view.r, view.u
    local tx = math.tan(math.rad(view.hfov or 30) / 2)
    local ty = tx * H / W
    skyG.Color = ColorSequence.new(pal.sky0, pal.sky1)
    -- 山脊线：视线没怎么变就不重算（省事；转炮塔、开车才重算）
    local moved = not cache.eye or (cache.eye - eye).Magnitude > 1.5 or cache.f:Dot(f) < 0.99996 or cache.fov ~= view.hfov
    local Map = view.Map
    if moved and Map then
      cache.eye, cache.f, cache.fov = eye, f, view.hfov
      local fh = V3(f.X, 0, f.Z)
      if fh.Magnitude < 1e-3 then fh = V3(0, 0, -1) end
      fh = fh.Unit
      local rh = V3(-fh.Z, 0, fh.X)
      for i = 1, N do
        local sx = ((i - 0.5) / N - 0.5) * 2 * tx
        local d = (fh + rh * sx).Unit
        local best = H
        local near = 0
        for _, dist in ipairs(DIST) do
          local px, pz = eye.X + d.X * dist, eye.Z + d.Z * dist
          local hy = math.max(Map.height(px, pz), -1)
          local q = V3(px, hy, pz) - eye
          local z = q:Dot(f)
          if z > 0.5 then
            local y = q:Dot(u) / z
            local s = H / 2 - y / ty * H / 2
            if s < best then best, near = s, dist end
          end
        end
        local c = cols[i]
        local top = math.clamp(math.floor(best), -2, H)
        c.top = top
        c.near = near
        c.f.Position = UD2(0, c.f.Position.X.Offset, 0, top)
        c.f.Size = UD2(0, math.ceil(cw) + 1, 0, H - top)
      end
    end
    for i = 1, N do
      local c = cols[i]
      local k = clamp((c.near or 0) / 2000, 0, 1)   -- 远的山更暗（大气、温差小）
      c.g.Color = ColorSequence.new(pal.g0:Lerp(pal.sky1, k * 0.5), pal.g1)
      c.e.BackgroundColor3 = pal.ridge:Lerp(pal.sky1, k * 0.6)
    end
    -- 目标：车（大、热）、人（小、温）
    local n = 0
    for _, e in ipairs(view.ents or {}) do
      local q = e.pos - eye
      local z = q:Dot(f)
      local dist = q.Magnitude
      if z > 2 and dist < (view.range or 4000) then
        local x, y = q:Dot(r) / z, q:Dot(u) / z
        if math.abs(x) < tx * 1.1 and math.abs(y) < ty * 1.1 then
          -- 被山挡住：沿视线抽几处地形高度
          local hidden = false
          if Map then
            for s = 1, 7 do
              local p = eye + q * (s / 8)
              if Map.height(p.X, p.Z) > p.Y + 0.5 then hidden = true break end
            end
          end
          if not hidden then
            n += 1
            local b = blob(n)
            local sx = W / 2 + x / tx * W / 2
            local sy = H / 2 - y / ty * H / 2
            local pw = math.max(2, (e.w or 8) / z / tx * W / 2)
            local ph = math.max(2, (e.h or 6) / z / ty * H / 2)
            b.f.Visible = true
            b.f.Position = UD2(0, sx - pw / 2, 0, sy - ph / 2)
            b.f.Size = UD2(0, pw, 0, ph)
            b.f.BackgroundColor3 = (e.kind == "veh") and pal.warm or pal.warm:Lerp(pal.g1, 0.3)
            b.core.BackgroundColor3 = pal.hot
            b.core.Visible = e.kind == "veh" or e.kind == "air"
          end
        end
      end
    end
    for i = n + 1, #blobs do blobs[i].f.Visible = false end
    for _, g in ipairs(grain) do
      g.Position = UD2(0, 0, 0, math.random(0, H))
      g.BackgroundTransparency = 0.9 + math.random() * 0.08
    end
  end
  return o
end

---------------------------------------------------------------- 分划、读数（几种瞄准镜画面共用）

local function reticleTank(parent, W, H, col)
  local cx, cy = W / 2, H / 2
  local g = math.max(3, W * 0.02)
  local L = W * 0.12
  Ln(parent, cx - L - g, cy, cx - g, cy, 2, col, 7)
  Ln(parent, cx + g, cy, cx + L + g, cy, 2, col, 7)
  Ln(parent, cx, cy + g, cx, cy + L * 0.8 + g, 2, col, 7)
  Ln(parent, cx, cy - g * 3, cx, cy - g, 1, col, 7)
  for i = 1, 4 do   -- 横线上的刻度（密位）
    Ln(parent, cx - g - i * L / 4, cy - 3, cx - g - i * L / 4, cy + 3, 1, col, 7)
    Ln(parent, cx + g + i * L / 4, cy - 3, cx + g + i * L / 4, cy + 3, 1, col, 7)
  end
end

---------------------------------------------------------------- 页面

local P = {}
Screens.pages = P

-- 驾驶员视觉增强器：车头方向的热像（黑热），几乎没有符号
P.dve = function(s, env)
  local W, H = s.px.X, s.px.Y
  local th = Screens.thermal(s.root, W, H, { cols = 28 })
  local t1 = Tx(s.root, "DVE  BH", 6, 4, 80, 14, 12, RGB(200, 200, 200), nil, FONT, 8)
  local bar = F(s.root, W - 10, H * 0.2, 4, H * 0.6, RGB(200, 200, 200), 0.6, 8)
  local _ = t1 and bar
  return function(d)
    if not d.hullEye then return end
    th.render({ eye = d.hullEye, f = d.hullF, r = d.hullR, u = d.hullU, hfov = 40, pal = PAL.BLK, ents = d.ents, Map = env.Map, range = 1800 })
  end
end

---------------------------------------------------------------- 按键：真实的标签 → 功能（中文标签换成同一个功能键）、提示说明
-- 资料：M1A2 SEP 的车长显示器（CDU：上半是独立热像仪画面、下半是战术显示）、热像仪模式（手动扫描 / 自动扫描 / 随炮 / 主瞄准镜画面 /
--   指示）、驾驶员综合显示器（PUSH TO START、SHUT OFF、MAIN MENU、MAINT/BACKUP、DIAG）、炮长控制显示面板（MAIN MENU、ADJUST、ZERO、
--   BORESIGHT、MRS、键盘和四向开关）出自美军训练资料、Steel Beasts 社区说明和陆军研究报告；99A 的按键按同类功能用中文
Screens.KEYMAP = {
  ["白热"] = "WHT", ["黑热"] = "BLK", ["宽视场"] = "WFOV", ["窄视场"] = "NFOV", ["手动"] = "MAN", ["扫描"] = "AUTO", ["随炮"] = "GUN LOS", ["指示"] = "DESIG",
  ["地图"] = "MAP", ["消息"] = "MSG", ["态势"] = "STAT", ["导航"] = "NAV", ["坐标"] = "POS", ["放大"] = "ZOOM+", ["缩小"] = "ZOOM-", ["标绘"] = "OVLY",
  ["亮+"] = "BRT+", ["亮-"] = "BRT-", ["主菜单"] = "MAIN", ["弹种"] = "AMMO", ["测距"] = "RANGE", ["校炮"] = "BSGT", ["激光"] = "LRF", ["极性"] = "WHT/BLK",
  ["倍率"] = "3X/10X", ["火控"] = "FCS", ["自检"] = "BIT", ["复位"] = "RESET", ["状态"] = "STATUS", ["故障"] = "W/C/A", ["维护"] = "MAINT",
  ["起动"] = "PUSH TO START", ["熄火"] = "SHUT OFF", ["怠速"] = "TAC IDLE", ["灯检"] = "LAMP TEST", ["消音"] = "ALARM ACK", ["MAIN MENU"] = "MAIN",
}
Screens.KEYDESC = {
  MAIN = "主菜单：回到这块屏的主页面", STATUS = "状态：发动机、传动、液压、电气的详细读数", ["W/C/A"] = "告警 / 注意 / 提示列表（红色告警、黄色注意、白色提示）",
  NAV = "导航：指向下一个目标点的方向和距离", MAINT = "维护 / 备份：机内自检（BIT）结果", ["PUSH TO START"] = "起动：按一下发动机自动起动",
  ["SHUT OFF"] = "熄火：正常关闭发动机（熄火后车开不动，再按起动）", ["TAC IDLE"] = "战术怠速：怠速转速提高，给电瓶充电、随时能走",
  ["LAMP TEST"] = "灯检：所有指示灯亮一遍，查灯泡", ["ALARM ACK"] = "确认告警：关掉告警音",
  AMMO = "弹种选择：火控按选的弹种算弹道，装填手 / 自动装弹机按它拿弹", RANGE = "手动装定距离（激光测不到的时候）：每按一次加 100 米",
  ADJUST = "调整：校炮、归零", LRF = "激光测距：第一回波 / 最后回波", ["WHT/BLK"] = "热像极性：白热 / 黑热", ["3X/10X"] = "主瞄准镜倍率",
  FCS = "火控方式：正常 / 应急 / 手动", BSGT = "校炮：瞄准镜和炮膛轴线对正", MRS = "炮口基准系统：测炮管热弯曲，自动修正", BIT = "机内自检", RESET = "复位",
  WHT = "热像白热（热的东西是白的）", BLK = "热像黑热（热的东西是黑的）", WFOV = "宽视场（3 倍）：找目标", NFOV = "窄视场（13 倍）：认目标",
  SYM = "符号：分划、方位刻度开 / 关", MAN = "手动扫描：热像仪跟着车长看的方向转", AUTO = "自动扫描：在扇区里来回扫",
  ["GUN LOS"] = "随炮：热像仪对准炮指的方向", ["GPS LOS"] = "看炮长主瞄准镜的画面", DESIG = "指示（猎-歼）：炮塔自动转到车长热像仪看的方向，交给炮长打",
  MAP = "战术地图（友军、敌情、目标点）", MSG = "消息：上级通报、敌情报告", STAT = "本车状态：弹药、油、损伤", POS = "本车坐标、高度、方向",
  ["ZOOM+"] = "地图放大", ["ZOOM-"] = "地图缩小", OVLY = "叠加层：目标点 / 单位标号开关", ["BRT+"] = "屏幕调亮", ["BRT-"] = "屏幕调暗",
  ARM = "遥控武器站：解除保险", SAFE = "遥控武器站：保险", THERM = "遥控武器站：白天 / 热像", ZOOM = "遥控武器站：变倍", LASE = "遥控武器站：激光测距",
  SLAVE = "遥控武器站跟着车长热像仪转",
}
local KM = Screens.KEYMAP
local function canon(k) return KM[k] or k end
Screens.canon = canon

-- 文字页（菜单、列表、状态）：盖在主页面上面，一行行写
local function textPage(s, title, n, col)
  local W, H = s.px.X, s.px.Y
  local f = F(s.root, 0, 0, W, H, RGB(2, 5, 6), 0, 20)
  f.Visible = false
  local lh = math.floor((H - 26) / n)
  local hdr = Tx(f, title, 6, 2, W - 12, 16, 13, col, nil, FONTB, 21)
  F(f, 4, 19, W - 8, 1, col, 0, 21)
  local L = {}
  for i = 1, n do L[i] = Tx(f, "", 8, 22 + (i - 1) * lh, W - 16, lh, math.max(10, math.min(14, lh - 2)), col, nil, FONT, 21) end
  return { f = f, hdr = hdr, set = function(lines, cols)
    for i = 1, n do
      L[i].Text = lines[i] or ""
      L[i].TextColor3 = (cols and cols[i]) or col
    end
  end }
end
-- 指向箭头（导航页）
local function arrow(parent, cx, cy, r, col)
  local _, a = Ln(parent, cx, cy, cx, cy - r, 4, col, 22)
  local _, b = Ln(parent, cx, cy - r, cx - 8, cy - r + 12, 4, col, 22)
  local _, c = Ln(parent, cx, cy - r, cx + 8, cy - r + 12, 4, col, 22)
  return function(ang)
    local sx, sy = math.sin(ang), -math.cos(ang)
    local tx, ty = cx + sx * r, cy + sy * r
    a(cx - sx * r * 0.6, cy - sy * r * 0.6, tx, ty)
    local l = ang + math.rad(150)
    local rr = ang - math.rad(150)
    b(tx, ty, tx + math.sin(l) * 14, ty - math.cos(l) * 14)
    c(tx, ty, tx + math.sin(rr) * 14, ty - math.cos(rr) * 14)
  end
end
local function objective(d)
  -- 下一个目标点：还在打的那个（阶段里活动的据点），没有就最近的
  local best, bd = nil, math.huge
  for _, p in ipairs(d.points or {}) do
    if p.owner ~= d.team and d.pos then
      local dd = ((p.x - d.pos.X) ^ 2 + (p.z - d.pos.Z) ^ 2) ^ 0.5
      if dd < bd then best, bd = p, dd end
    end
  end
  return best, bd
end
local function navText(d, zh)
  local o, dist = objective(d)
  if not o or not d.pos then return nil end
  local brg = math.deg(math.atan2(o.x - d.pos.X, -(o.z - d.pos.Z))) % 360
  return o, dist, brg
end

-- 驾驶员综合显示器（M1A2 SEP 的 DID）：主页（车速、转速、油量、挡位、炮塔方位、告警）+ 状态 / 告警 / 导航 / 维护页；起动、熄火真起作用
P.did = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(4, 6, 8)
  local G = RGB(90, 230, 120)
  local A = RGB(255, 190, 60)
  local Wt = RGB(220, 230, 220)
  local RD = RGB(255, 80, 60)
  local function L(en, cn) return zh and cn or en end
  Tx(R, L("DRIVER'S INTEGRATED DISPLAY", "驾驶员综合显示器"), 6, 2, W - 12, 14, 11, RGB(120, 160, 130), Enum.TextXAlignment.Center, FONT, 3)
  F(R, 4, 17, W - 8, 1, RGB(60, 90, 70), 0, 2)
  local spd = Tx(R, "0", 8, 24, W * 0.36, 44, 40, Wt, Enum.TextXAlignment.Right, FONTB)
  Tx(R, L("MPH", "km/h"), 8, 66, W * 0.36, 14, 12, G, Enum.TextXAlignment.Right)
  local rpm = {}
  for i = 1, 20 do rpm[i] = F(R, 10 + (i - 1) * (W * 0.42 / 20), 92, W * 0.42 / 20 - 2, 12, G, 0, 2) end
  local rpmT = Tx(R, "RPM 0", 10, 106, W * 0.42, 14, 11, G)
  local gears = {}
  for i, g in ipairs({ "R", "N", "D", "L" }) do
    local f = F(R, 10 + (i - 1) * 26, 124, 22, 20, RGB(20, 30, 24), 0, 2)
    gears[g] = { f = f, t = Tx(f, g, 0, 0, 22, 20, 14, G, Enum.TextXAlignment.Center, FONTB) }
  end
  local fuelBg = F(R, W * 0.5, 26, 14, 80, RGB(20, 30, 24), 0, 2)
  local fuel = F(fuelBg, 0, 80, 14, 0, G, 0, 3)
  local fuelT = Tx(R, "", W * 0.5 + 18, 26, W * 0.24, 14, 11, G)
  local battT = Tx(R, "", W * 0.5 + 18, 44, W * 0.24, 14, 11, G)
  local oilT = Tx(R, "", W * 0.5 + 18, 62, W * 0.24, 14, 11, G)
  local engT = Tx(R, "", W * 0.5 + 18, 80, W * 0.24, 14, 11, G)
  local cx, cy, rr = W * 0.86, 62, math.min(W * 0.11, 40)
  Box(R, cx - rr * 0.55, cy - rr, rr * 1.1, rr * 2, 2, Wt, 3)
  Ring(R, cx, cy + rr * 0.1, rr * 0.42, 2, Wt, 3)
  local _, gunSet = Ln(R, cx, cy, cx, cy - rr * 1.2, 3, A, 4)
  Tx(R, L("TURRET", "炮塔"), cx - 40, cy + rr + 4, 80, 12, 10, RGB(140, 170, 150), Enum.TextXAlignment.Center)
  local tyT = Tx(R, "000", cx - 40, cy + rr + 16, 80, 12, 11, A, Enum.TextXAlignment.Center)
  F(R, 4, H - 34, W - 8, 1, RGB(60, 90, 70), 0, 2)
  local warn = Tx(R, "", 8, H - 30, W - 16, 26, 13, G, Enum.TextXAlignment.Left, FONTB)
  -- 其他页
  local pages = {
    STATUS = textPage(s, L("STATUS", "状态"), 9, G), ["W/C/A"] = textPage(s, L("WARNINGS / CAUTIONS / ADVISORIES", "告警 / 注意 / 提示"), 8, G),
    NAV = textPage(s, L("POSNAV  STEER TO", "导航"), 4, G), MAINT = textPage(s, L("MAINT / BACKUP  -  BIT", "维护 / 自检"), 9, G),
  }
  local navArrow = arrow(pages.NAV.f, W * 0.72, H * 0.58, math.min(W, H) * 0.25, A)
  local st = { page = "MAIN", tac = false, ack = false, msg = nil, msgT = 0 }
  s.onKey = function(k, act)
    k = canon(k)
    if k == "MAIN" or k == "STATUS" or k == "W/C/A" or k == "NAV" or k == "MAINT" then st.page = (st.page == k and k ~= "MAIN") and "MAIN" or k
    elseif k == "PUSH TO START" then act.engine(true) st.msg, st.msgT = L("ENGINE START - AUTO SEQUENCE", "发动机起动中（自动程序）"), os.clock()
    elseif k == "SHUT OFF" then act.engine(false) st.msg, st.msgT = L("ENGINE SHUTDOWN", "发动机熄火"), os.clock()
    elseif k == "TAC IDLE" then st.tac = not st.tac
    elseif k == "LAMP TEST" then act.lampTest()
    elseif k == "ALARM ACK" then st.ack = true end
  end
  return function(d)
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    local off = d.engineOff
    local mph = math.abs(d.speed or 0) / 2.8 * (zh and 3.6 or 2.237)
    spd.Text = string.format("%d", math.floor(mph + 0.5))
    local k = off and 0 or clamp((d.rpm or 0) + (st.tac and 0.12 or 0), 0, 1)
    for i = 1, 20 do
      local on = i / 20 <= k + 0.001
      rpm[i].BackgroundColor3 = on and ((i > 17) and RD or (i > 14 and A or G)) or RGB(20, 30, 24)
    end
    rpmT.Text = off and L("ENGINE OFF", "发动机熄火") or string.format(L("RPM %d", "转速 %d"), math.floor(600 + k * 2400))
    for g, it in pairs(gears) do
      local on = g == (d.gear or "N")
      it.f.BackgroundColor3 = on and G or RGB(20, 30, 24)
      it.t.TextColor3 = on and RGB(0, 0, 0) or G
    end
    local fu = clamp(d.fuel or 1, 0, 1)
    fuel.Position = UD2(0, 0, 0, 80 * (1 - fu))
    fuel.Size = UD2(0, 14, 0, 80 * fu)
    fuel.BackgroundColor3 = fu < 0.2 and RD or G
    fuelT.Text = zh and string.format("油量 %d L", math.floor(1450 * fu)) or string.format("FUEL %d GAL", math.floor(504 * fu))
    battT.Text = string.format(L("BATT %.1f V", "电压 %.1f V"), (off and 24.1 or 27.6) + math.sin((d.t or 0) * 0.3) * 0.2)
    oilT.Text = string.format(L("OIL %3d C", "油温 %3d ℃"), math.floor((off and 60 or 80) + k * 30))
    engT.Text = st.tac and L("TAC IDLE", "战术怠速") or (off and "" or L("ENG RUN", "运转"))
    local a = math.rad(d.ty or 0)
    gunSet(cx, cy + rr * 0.1, cx + math.sin(a) * rr * 1.3, cy + rr * 0.1 - math.cos(a) * rr * 1.3)
    tyT.Text = string.format("%04d", math.floor(((d.ty or 0) % 360) / 360 * 6400 + 0.5) % 6400)
    local w, wc = {}, {}
    local function add(t, c) table.insert(w, t) table.insert(wc, c) end
    if (d.hp or 1) < 0.35 then add(L("WARNING  HULL DAMAGE", "告警  车体损伤"), RD) end
    if (d.hp or 1) < 0.6 then add(L("CAUTION  ENG OIL PRESS LOW", "注意  机油压力低"), A) end
    if fu < 0.2 then add(L("CAUTION  LOW FUEL", "注意  油量低"), A) end
    if math.abs(((d.ty or 0) + 180) % 360 - 180) > 120 then add(L("ADVISORY  GUN OVER DECK", "提示  炮在车尾方向"), Wt) end
    if off then add(L("ADVISORY  ENGINE OFF", "提示  发动机熄火"), Wt) end
    if st.msg and os.clock() - st.msgT < 4 then warn.Text, warn.TextColor3 = st.msg, A
    else
      warn.Text = (#w > 0) and w[1] or L("NO WARNINGS", "无故障")
      warn.TextColor3 = (#w > 0) and wc[1] or G
    end
    if st.page == "STATUS" then
      pages.STATUS.set({
        string.format(L("ENGINE      %s   N2 %3d%%", "发动机  %s   转速 %3d%%"), off and L("OFF", "停") or L("RUN", "运转"), math.floor(k * 100)),
        string.format(L("PTIT        %4d F", "涡轮温度  %4d ℃"), off and 120 or math.floor(1100 + k * 500)),
        string.format(L("ENG OIL     %3d PSI  %3d C", "机油  %3d kPa  %3d ℃"), off and 0 or math.floor(40 + k * 30), math.floor(80 + k * 30)),
        string.format(L("XMSN OIL    %3d PSI  %3d C", "传动油  %3d kPa  %3d ℃"), off and 0 or math.floor(60 + k * 40), math.floor(84 + k * 22)),
        string.format(L("HYD         %4d PSI", "液压  %4d kPa"), off and 0 or 1500),
        string.format(L("BATT        %.1f V   GEN %s", "电压  %.1f V  发电机 %s"), (off and 24.1 or 27.8), off and L("OFF", "停") or "ON"),
        string.format(L("FUEL FRONT  %3d GAL", "前油箱  %3d L"), math.floor((zh and 760 or 200) * fu)),
        string.format(L("FUEL REAR   %3d GAL", "后油箱  %3d L"), math.floor((zh and 690 or 304) * fu)),
        string.format(L("SPEED       %3d", "车速  %3d"), math.floor(mph + 0.5)),
      })
    elseif st.page == "W/C/A" then
      local lines, cols = {}, {}
      for i, t in ipairs(w) do lines[i], cols[i] = t, wc[i] end
      if #lines == 0 then lines[1] = L("NO WARNINGS / CAUTIONS", "无告警、无注意") end
      if st.ack then table.insert(lines, L("ALARM ACKNOWLEDGED", "告警已确认")) end
      pages["W/C/A"].set(lines, cols)
    elseif st.page == "NAV" then
      local o, dist, brg = navText(d)
      if o then
        pages.NAV.set({ string.format(L("STEER TO  OBJ %s", "前往  据点 %s"), o.id), string.format(L("RANGE  %5d M", "距离  %5d 米"), math.floor(dist / 2.8)),
          string.format(L("BEARING  %03d", "方位  %03d°"), math.floor(brg)), string.format(L("HEADING  %03d", "车头  %03d°"), math.floor(d.hdg or 0)) })
        navArrow(math.rad(brg - (d.hdg or 0)))
      else
        pages.NAV.set({ L("NO WAYPOINT", "没有目标点") })
      end
    elseif st.page == "MAINT" then
      pages.MAINT.set({ L("BIT  COMPLETE", "自检  完成"), L("ENGINE ......... GO", "发动机 ...... 正常"), L("TRANSMISSION ... GO", "传动 ........ 正常"),
        L("HULL NETWORK ... GO", "车体网络 .... 正常"), L("TURRET NETWORK . GO", "炮塔网络 .... 正常"), L("FIRE CONTROL ... GO", "火控 ........ 正常"),
        L("NBC ............ GO", "三防 ........ 正常"), L("FIRE SUPPR ..... GO", "灭火抑爆 .... 正常"), (d.hp or 1) < 0.6 and L("ENG OIL PRESS .. NO-GO", "机油压力 .... 故障") or L("POWER .......... GO", "电源 ........ 正常") })
    end
  end
end

-- 炮长控制显示面板（GCDP）：主瞄准镜小画面 + 弹种、待发、距离、方式；弹种 / 手动距离 / 激光回波 / 极性 / 倍率 / 火控方式 / 校炮 / 炮口基准都能按
P.gcdp = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(4, 6, 6)
  local G = RGB(100, 240, 130)
  local A = RGB(255, 190, 60)
  local function L(en, cn) return zh and cn or en end
  local vw, vh = math.floor(W * 0.56), math.floor(H * 0.70)
  local view = F(R, W - vw - 4, 4, vw, vh, RGB(0, 0, 0), 0, 1)
  view.ClipsDescendants = true
  local th = Screens.thermal(view, vw, vh, { cols = 24 })
  reticleTank(view, vw, vh, G)
  local LIST = zh and { { "ap", "穿甲弹" }, { "heat", "破甲弹" }, { "he", "榴弹" }, { "gl", "炮射导弹" } }
    or { { "SABOT", "SABOT" }, { "HEAT", "HEAT" }, { "MPAT", "MPAT" }, { "AMP", "AMP" }, { "CAN", "CAN" } }
  local ammo = {}
  for i, a in ipairs(LIST) do
    local f = F(R, 4, 4 + (i - 1) * ((vh - 4) / #LIST), W - vw - 12, (vh - 4) / #LIST - 3, RGB(18, 26, 20), 0, 2)
    ammo[a[1]] = { f = f, t = Tx(f, a[2], 4, 0, W - vw - 16, (vh - 4) / #LIST - 3, 12, G, Enum.TextXAlignment.Left, FONTB) }
  end
  local ready = F(R, 4, vh + 8, W * 0.42, H - vh - 12, RGB(18, 26, 20), 0, 2)
  local readyT = Tx(ready, "", 0, 0, W * 0.42, H - vh - 12, 13, G, Enum.TextXAlignment.Center, FONTB)
  local rng = Tx(R, "", W * 0.46, vh + 8, W * 0.52, (H - vh - 12) / 2, 13, G, nil, FONTB)
  local mode = Tx(R, "", W * 0.46, vh + 8 + (H - vh - 12) / 2, W * 0.52, (H - vh - 12) / 2, 11, G)
  local pages = { MAIN = textPage(s, L("MAIN MENU", "主菜单"), 7, G), ADJUST = textPage(s, L("ADJUST", "调整"), 6, G), BSGT = textPage(s, L("BORESIGHT", "校炮"), 6, G) }
  local st = { page = nil, ammo = LIST[1][1], manRange = nil, last = false, fcs = 1, msg = nil, msgT = 0, bs = { 0, 0 } }
  local FCS = zh and { "自动", "应急", "手动" } or { "NORMAL", "EMERGENCY", "MANUAL" }
  s.onKey = function(k, act)
    k = canon(k)
    if k == "MAIN" or k == "ADJUST" or k == "BSGT" then st.page = (st.page == k) and nil or k
    elseif k == "AMMO" then
      local idx = 1
      for i, a in ipairs(LIST) do if a[1] == st.ammo then idx = i end end
      st.ammo = LIST[idx % #LIST + 1][1]
      act.ammo(st.ammo)
    elseif k == "RANGE" then st.manRange = ((st.manRange or 0) + 100) % 4100
      if st.manRange == 0 then st.manRange = nil end
    elseif k == "LRF" then st.last = not st.last
    elseif k == "WHT/BLK" then act.polarity()
    elseif k == "3X/10X" then act.zoom()
    elseif k == "FCS" then st.fcs = st.fcs % 3 + 1
    elseif k == "MRS" then st.msg, st.msgT = L("MRS UPDATE COMPLETE", "炮口基准更新完成"), os.clock()
    elseif k == "BIT" then st.msg, st.msgT = L("FCS BIT  GO", "火控自检  正常"), os.clock()
    elseif k == "RESET" then st.manRange, st.page = nil, nil end
  end
  return function(d)
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    if d.gunEye and not st.page then
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = (d.zoomTxt == "10X") and 7 or 20, pal = (d.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
    end
    for a, it in pairs(ammo) do
      local on = a == st.ammo
      it.f.BackgroundColor3 = on and G or RGB(18, 26, 20)
      it.t.TextColor3 = on and RGB(0, 0, 0) or G
    end
    local rd = d.ready
    ready.BackgroundColor3 = rd and G or RGB(18, 26, 20)
    readyT.TextColor3 = rd and RGB(0, 0, 0) or A
    readyT.Text = rd and L("READY TO FIRE", "待发") or L("LOADING", "装填中")
    if st.msg and os.clock() - st.msgT < 3 then rng.Text = st.msg
    elseif st.manRange then rng.Text = string.format(L("MAN RANGE %04d", "手动距离 %04d"), st.manRange)
    else rng.Text = d.range and string.format(L("RANGE %04d %s", "距离 %04d %s"), math.floor(d.range), st.last and L("L", "末") or L("F", "首")) or L("RANGE ----", "距离 ----") end
    mode.Text = string.format("%s  %s  %s", FCS[st.fcs], (d.pol == "BLK") and L("BLK", "黑热") or L("WHT", "白热"), (d.zoomTxt == "10X") and L("10X", "10倍") or L("3X", "3倍"))
    if st.page == "MAIN" then
      pages.MAIN.set({ L("1  AMMO SELECT", "1  弹种选择"), L("2  RANGE ENTRY", "2  手动装定距离"), L("3  ADJUST  (BORESIGHT / ZERO)", "3  调整（校炮 / 归零）"),
        L("4  MRS UPDATE", "4  炮口基准更新"), L("5  LRF  FIRST / LAST RETURN", "5  激光  首回波 / 末回波"), L("6  FCS MODE  " .. FCS[st.fcs], "6  火控方式  " .. FCS[st.fcs]),
        L("7  BIT / TONE TEST", "7  自检 / 音响测试") })
    elseif st.page == "ADJUST" then
      pages.ADJUST.set({ L("BORESIGHT  (BSGT)", "校炮（校炮键）"), L("ZERO", "归零"), string.format(L("AZ  %+.2f MIL", "方向  %+.2f 密位"), st.bs[1]), string.format(L("EL  %+.2f MIL", "高低  %+.2f 密位"), st.bs[2]),
        L("4-WAY SWITCH TO ADJUST", "四向开关调整"), L("PRESS MAIN TO EXIT", "按主菜单退出") })
    elseif st.page == "BSGT" then
      pages.BSGT.set({ L("BORESIGHT", "校炮"), L("ALIGN RETICLE TO MRS", "分划对准炮口基准"), string.format(L("AZ  %+.2f", "方向  %+.2f"), st.bs[1]), string.format(L("EL  %+.2f", "高低  %+.2f"), st.bs[2]), L("BORESIGHT OK", "校炮完成"), "" })
    end
  end
end

-- 车长独立热像仪（CITV / 99A 车长周视镜）：手动扫描跟着车长的视线、自动扫描扇区、随炮、看主瞄准镜画面；指示键让炮塔转过去（猎-歼）
P.citv = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th = Screens.thermal(R, W, H, { cols = 32 })
  local G = RGB(230, 240, 230)
  local sym = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 6)
  local cx, cy = W / 2, H / 2
  Box(sym, cx - W * 0.08, cy - H * 0.08, W * 0.16, H * 0.16, 1.5, G, 7)
  Ln(sym, cx - W * 0.18, cy, cx - W * 0.08, cy, 1.5, G, 7)
  Ln(sym, cx + W * 0.08, cy, cx + W * 0.18, cy, 1.5, G, 7)
  Ln(sym, cx, cy + H * 0.08, cx, cy + H * 0.2, 1.5, G, 7)
  F(sym, W * 0.15, 6, W * 0.7, 1, G, 0, 7)
  local mark = Tx(sym, "▼", 0, 6, 14, 12, 12, G, Enum.TextXAlignment.Center, FONTB, 8)
  local gunM = Tx(sym, "G", 0, 8, 14, 12, 11, RGB(255, 190, 60), Enum.TextXAlignment.Center, FONTB, 8)
  local info = Tx(sym, "", 6, H - 18, W - 12, 14, 12, G, nil, FONTB, 8)
  local rng = Tx(sym, "", W - 110, 20, 104, 14, 12, G, Enum.TextXAlignment.Right, FONTB, 8)
  local flash = Tx(R, "", 0, H * 0.3, W, 20, 16, RGB(255, 210, 90), Enum.TextXAlignment.Center, FONTB, 9)
  local st = { pol = "WHT", nfov = false, sym = true, fT = 0 }
  local MODE = zh and { MAN = "手动", AUTO = "扫描", ["GUN LOS"] = "随炮", ["GPS LOS"] = "主镜" } or { MAN = "MAN SCAN", AUTO = "AUTO SCAN", ["GUN LOS"] = "GUN LOS", ["GPS LOS"] = "GPS LOS" }
  s.onKey = function(k, act)
    k = canon(k)
    if k == "WHT" or k == "BLK" then st.pol = k
    elseif k == "WFOV" or k == "NFOV" then st.nfov = k == "NFOV" act.citvFov(st.nfov and 7 or 22)
    elseif k == "SYM" then st.sym = not st.sym
    elseif MODE[k] then act.citvMode(k)
    elseif k == "DESIG" then
      act.designate()
      flash.Text = zh and "指示  炮塔转向目标" or "DESIGNATE  -  TURRET SLEWING"
      st.fT = os.clock()
    end
  end
  return function(d)
    local gps = d.citvMode == "GPS LOS"
    if gps and d.gunEye then
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = (d.zoomTxt == "10X") and 7 or 20, pal = (st.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
    elseif d.citvEye then
      th.render({ eye = d.citvEye, f = d.citvF, r = d.citvR, u = d.citvU, hfov = d.citvFov or 22, pal = (st.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
    end
    sym.Visible = st.sym
    local k = clamp((d.citvRel or 0) / 180, -1, 1)
    mark.Position = UD2(0, W / 2 + k * W * 0.35 - 7, 0, 8)
    gunM.Position = UD2(0, W / 2 - 7, 0, 18)
    info.Text = string.format("%s  %s  %s  %s", zh and "热像" or "CITV", MODE[d.citvMode or "MAN"] or "", (d.citvFov or 22) < 10 and (zh and "窄视场" or "NFOV 13X") or (zh and "宽视场" or "WFOV 3X"),
      (st.pol == "BLK") and (zh and "黑热" or "BLK") or (zh and "白热" or "WHT"))
    rng.Text = d.citvRange and string.format("RNG %04d", math.floor(d.citvRange)) or ""
    if os.clock() - st.fT > 2.5 then flash.Text = "" end
  end
end

-- 车长遥控武器站（CROWS-LP）的屏幕
P.crows = function(s, env)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th = Screens.thermal(R, W, H, { cols = 22 })
  local G = RGB(240, 240, 240)
  reticleTank(R, W, H, G)
  local t = Tx(R, "", 4, 3, W - 8, 13, 11, G, nil, FONTB, 8)
  local am = Tx(R, "400", W - 50, H - 16, 46, 13, 12, G, Enum.TextXAlignment.Right, FONTB, 8)
  local st = { armed = false, therm = false, zoom = false, lase = nil, slave = false }
  s.onKey = function(k)
    if k == "ARM" then st.armed = true elseif k == "SAFE" then st.armed = false
    elseif k == "THERM" then st.therm = not st.therm elseif k == "ZOOM" then st.zoom = not st.zoom
    elseif k == "LASE" then st.lase = os.clock() elseif k == "SLAVE" then st.slave = not st.slave end
  end
  return function(d)
    local eye, f, r, u = d.rwsEye, d.rwsF, d.rwsR, d.rwsU
    if st.slave and d.citvEye then eye, f, r, u = d.citvEye, d.citvF, d.citvR, d.citvU end
    if eye then th.render({ eye = eye, f = f, r = r, u = u, hfov = st.zoom and 9 or 30, pal = st.therm and PAL.WHT or PAL.DAY, ents = d.ents, Map = env.Map, range = 2500 }) end
    t.Text = string.format("CROWS  M2  %s  %s%s", st.armed and "ARMED" or "SAFE", st.therm and "TI" or "DAY", st.slave and "  SLAVE" or "")
    am.Text = (st.lase and os.clock() - st.lase < 3 and d.range) and string.format("%04d", math.floor(d.range)) or tostring(d.rwsAmmo or 400)
  end
end

-- 指挥地图（M1A2 的战术显示 / JBC-P；99A 的综合显示终端）：地图 / 消息 / 本车状态 / 导航 / 坐标页，放大缩小、叠加层、亮度
P.cid = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local function L(en, cn) return zh and cn or en end
  R.BackgroundColor3 = RGB(18, 34, 52)
  local view = F(R, 0, 18, W, H - 36, RGB(18, 34, 52), 0, 1)
  view.ClipsDescendants = true
  local land = F(view, 0, 0, W, H, RGB(0, 0, 0), 1, 2)
  local top = F(R, 0, 0, W, 18, RGB(10, 14, 20), 0, 5)
  local clock = Tx(top, "", 4, 0, W * 0.4, 18, 11, RGB(200, 220, 240), nil, FONT, 6)
  local grid = Tx(top, "", W * 0.4, 0, W * 0.6 - 4, 18, 11, RGB(200, 220, 240), Enum.TextXAlignment.Right, FONT, 6)
  local bot = F(R, 0, H - 18, W, 18, RGB(10, 14, 20), 0, 5)
  local scaleT = Tx(bot, "", 4, 0, W - 8, 18, 10, RGB(160, 200, 230), nil, FONTB, 6)
  local dim = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 30)
  local S = { cx = nil, cz = nil, span = (env.zooms or { 0, 3200 })[2], cell = 64, job = nil }
  S.cell = S.span / 50
  local scale = (H - 36) / S.span
  local function landCol(h)
    if h < 0.3 then return nil end
    if h < 6 then return RGB(196, 186, 140) end
    if h < 40 then return RGB(120, 150, 96) end
    if h < 110 then return RGB(104, 128, 84) end
    if h < 220 then return RGB(132, 122, 96) end
    return RGB(160, 152, 136)
  end
  local function rebuild(cx, cz)
    S.job = { cx = cx, cz = cz, n = math.floor(S.span / S.cell), j = 0, frames = {} }
  end
  local function stepJob()
    local J = S.job
    local Map = env.Map
    local calls = 0
    while J.j < J.n and calls < 160 do
      local j = J.j
      local z = J.cz - S.span / 2 + (j + 0.5) * S.cell
      local run, runCol = nil, nil
      for i = 0, J.n do
        local col = nil
        if i < J.n then
          col = landCol(Map.height(J.cx - S.span / 2 + (i + 0.5) * S.cell, z))
          calls += 1
        end
        if col ~= runCol then
          if runCol and run then table.insert(J.frames, { run, j, i - run, runCol }) end
          run, runCol = i, col
        end
      end
      J.j += 1
    end
    if J.j < J.n then return false end
    for _, c in ipairs(land:GetChildren()) do c:Destroy() end
    local px = S.cell * scale
    for _, fr in ipairs(J.frames) do F(land, fr[1] * px, fr[2] * px, fr[3] * px + 1, px + 1, fr[4], 0, 2) end
    S.cx, S.cz = J.cx, J.cz
    S.scale = scale
    return true
  end
  local gridF = F(view, 0, 0, W, H, RGB(0, 0, 0), 1, 3)
  local objs = {}
  local function obj(i)
    local o = objs[i]
    if not o then
      local f = F(view, 0, 0, 10, 10, RGB(80, 160, 255), 0, 6)
      local t = Tx(f, "", -20, -14, 50, 12, 10, RGB(255, 255, 255), Enum.TextXAlignment.Center, FONTB, 7)
      o = { f = f, t = t }
      objs[i] = o
    end
    return o
  end
  local me = F(view, 0, 0, 12, 12, RGB(80, 170, 255), 0, 8)
  local meC = Instance.new("UICorner")
  meC.CornerRadius = UDim.new(0.5, 0)
  meC.Parent = me
  local _, hdgSet = Ln(view, 0, 0, 0, 0, 2, RGB(80, 170, 255), 8)
  local _, gunSet = Ln(view, 0, 0, 0, 0, 2, RGB(255, 200, 60), 8)
  local gl = {}
  for i = 1, 8 do gl[i] = F(gridF, 0, 0, 1, H, RGB(255, 255, 255), 0.82, 3) end
  for i = 9, 16 do gl[i] = F(gridF, 0, 0, W, 1, RGB(255, 255, 255), 0.82, 3) end
  local pages = { MSG = textPage(s, L("MESSAGES", "消息"), 7, RGB(200, 225, 245)), STAT = textPage(s, L("VEHICLE STATUS", "本车状态"), 7, RGB(200, 225, 245)),
    NAV = textPage(s, L("NAVIGATION", "导航"), 4, RGB(200, 225, 245)), POS = textPage(s, L("POSITION", "坐标"), 5, RGB(200, 225, 245)) }
  local navArrow = arrow(pages.NAV.f, W * 0.75, H * 0.6, math.min(W, H) * 0.22, RGB(255, 200, 60))
  local ZOOMS = env.zooms or { 1600, 3200, 6400 }
  local st = { page = "MAP", z = 2, ovly = true, brt = 0 }
  s.onKey = function(k)
    k = canon(k)
    if k == "MAP" or k == "MSG" or k == "STAT" or k == "NAV" or k == "POS" then st.page = k
    elseif k == "ZOOM+" then st.z = math.max(1, st.z - 1) elseif k == "ZOOM-" then st.z = math.min(3, st.z + 1)
    elseif k == "OVLY" then st.ovly = not st.ovly
    elseif k == "BRT+" then st.brt = math.max(0, st.brt - 0.15) elseif k == "BRT-" then st.brt = math.min(0.75, st.brt + 0.15) end
  end
  return function(d)
    if not d.pos then return end
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    dim.BackgroundTransparency = 1 - st.brt
    local p = d.pos
    local want = ZOOMS[st.z]
    if want ~= S.span and not S.job then S.span, S.cx = want, nil scale = (H - 36) / S.span end
    if not S.job and (not S.cx or math.abs(p.X - S.cx) > S.span * 0.22 or math.abs(p.Z - S.cz) > S.span * 0.22) then
      S.cell = S.span / 50
      rebuild(math.floor(p.X / S.cell) * S.cell, math.floor(p.Z / S.cell) * S.cell)
    end
    if S.job and stepJob() then S.job = nil end
    local vx, vz = W / 2, (H - 36) / 2
    if S.cx then
      land.Position = UD2(0, vx - (p.X - (S.cx - S.span / 2)) * scale, 0, vz - (p.Z - (S.cz - S.span / 2)) * scale)
      land.Size = UD2(0, S.span * scale, 0, S.span * scale)
    end
    local g0x = math.floor((p.X - S.span / 2) / 1000) * 1000
    local g0z = math.floor((p.Z - S.span / 2) / 1000) * 1000
    for i = 1, 8 do
      local x = vx + (g0x + i * 1000 - p.X) * scale
      gl[i].Position = UD2(0, x, 0, 0)
      gl[i].Visible = x > 0 and x < W
    end
    for i = 9, 16 do
      local z = vz + (g0z + (i - 8) * 1000 - p.Z) * scale
      gl[i].Position = UD2(0, 0, 0, z)
      gl[i].Visible = z > 0 and z < H - 36
    end
    me.Position = UD2(0, vx - 6, 0, vz - 6)
    local h = math.rad(d.hdg or 0)
    hdgSet(vx, vz, vx + math.sin(h) * 22, vz - math.cos(h) * 22)
    local tg = math.rad((d.hdg or 0) + (d.ty or 0))
    gunSet(vx, vz, vx + math.sin(tg) * 34, vz - math.cos(tg) * 34)
    local n = 0
    if st.ovly then
      for _, pt in ipairs(d.points or {}) do
        n += 1
        local o = obj(n)
        local x, z = vx + (pt.x - p.X) * scale, vz + (pt.z - p.Z) * scale
        o.f.Visible = x > -10 and x < W + 10 and z > -10 and z < H
        o.f.Position = UD2(0, x - 8, 0, z - 8)
        o.f.Size = UD2(0, 16, 0, 16)
        o.f.BackgroundColor3 = (pt.owner == d.team) and RGB(70, 140, 255) or ((pt.owner == nil) and RGB(200, 200, 200) or RGB(230, 70, 60))
        o.f.BackgroundTransparency = 0.25
        o.f.Rotation = 45
        o.t.Text = pt.id
        o.t.Rotation = -45
      end
      for _, e in ipairs(d.ents or {}) do
        local friend = e.team == d.team
        if friend or e.seen then
          n += 1
          local o = obj(n)
          local x, z = vx + (e.pos.X - p.X) * scale, vz + (e.pos.Z - p.Z) * scale
          o.f.Visible = x > -10 and x < W + 10 and z > -10 and z < H
          local sz = (e.kind == "veh") and 9 or ((e.kind == "air") and 8 or 5)
          o.f.Position = UD2(0, x - sz / 2, 0, z - sz / 2)
          o.f.Size = UD2(0, sz, 0, sz)
          o.f.BackgroundColor3 = friend and RGB(80, 160, 255) or RGB(255, 70, 60)
          o.f.BackgroundTransparency = 0
          o.f.Rotation = friend and 0 or 45
          o.t.Text = ""
          o.t.Rotation = 0
        end
      end
    end
    for i = n + 1, #objs do objs[i].f.Visible = false end
    local t = d.clock or 0
    clock.Text = string.format("%02d:%02d:%02dZ  %s", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, math.floor(t) % 60, d.callsign or (zh and "01 号车" or "A-12"))
    local gx, gz = math.floor((p.X + 20000) / 2.8) % 100000, math.floor((20000 - p.Z) / 2.8) % 100000
    grid.Text = string.format("52S  %05d %05d", gx, gz)
    scaleT.Text = string.format(L("SCALE 1:%dK   %s", "比例 1:%dK   %s"), math.floor(S.span / 2.8 / 100), st.ovly and L("OVERLAY ON", "标绘 开") or L("OVERLAY OFF", "标绘 关"))
    if st.page == "MSG" then
      local lines = {}
      local nE = 0
      for _, e in ipairs(d.ents or {}) do if e.seen and e.team ~= d.team then nE += 1 end end
      table.insert(lines, string.format(L("%02d%02dZ  SPOT RPT: %d ENEMY IN SECTOR", "%02d%02d  敌情：本区发现敌 %d 个"), math.floor(t / 3600) % 24, math.floor(t / 60) % 60, nE))
      for _, pt in ipairs(d.points or {}) do
        if pt.owner == d.team then table.insert(lines, string.format(L("OBJ %s SECURED", "据点 %s 已控制"), pt.id))
        else table.insert(lines, string.format(L("OBJ %s HELD BY ENEMY", "据点 %s 在敌手"), pt.id)) end
      end
      pages.MSG.set(lines)
    elseif st.page == "STAT" then
      local lines = {}
      for wid, a in pairs(d.ammoAll or {}) do table.insert(lines, string.format(L("%-8s RDY %2d  STOW %3d", "%-8s 待发 %2d  备弹 %3d"), wid, a[1] or 0, a[2] or 0)) end
      table.insert(lines, string.format(L("FUEL  %3d%%", "油量  %3d%%"), math.floor((d.fuel or 1) * 100)))
      table.insert(lines, string.format(L("DAMAGE  %3d%%", "损伤  %3d%%"), math.floor((1 - (d.hp or 1)) * 100)))
      table.insert(lines, d.ready and L("MAIN GUN  READY", "主炮  待发") or L("MAIN GUN  LOADING", "主炮  装填中"))
      pages.STAT.set(lines)
    elseif st.page == "NAV" then
      local o, dist, brg = navText(d)
      if o then
        pages.NAV.set({ string.format(L("WAYPOINT  OBJ %s", "目标点  据点 %s"), o.id), string.format(L("DIST  %5d M", "距离  %5d 米"), math.floor(dist / 2.8)),
          string.format(L("BRG   %03d", "方位  %03d°"), math.floor(brg)), string.format(L("HDG   %03d", "车头  %03d°"), math.floor(d.hdg or 0)) })
        navArrow(math.rad(brg - (d.hdg or 0)))
      else pages.NAV.set({ L("NO WAYPOINT", "没有目标点") }) end
    elseif st.page == "POS" then
      pages.POS.set({ string.format(L("GRID  52S %05d %05d", "坐标  52S %05d %05d"), gx, gz), string.format(L("ALT   %4d M", "高度  %4d 米"), math.floor(p.Y / 2.8)),
        string.format(L("HDG   %03d", "车头  %03d°"), math.floor(d.hdg or 0)), string.format(L("TURRET %03d", "炮塔  %03d°"), math.floor(((d.hdg or 0) + (d.ty or 0)) % 360)),
        L("GPS  3D FIX", "北斗  三维定位") })
    end
  end
end

---------------------------------------------------------------- 99A 的页面（中文）

P.cnmap = function(s, env) return P.cid(s, env, true) end
P.drvcn = function(s, env) return P.did(s, env, true) end
P.fcscn = function(s, env) return P.gcdp(s, env, true) end
P.citvcn = function(s, env) return P.citv(s, env, true) end

-- 炮长显示器：主瞄准镜的热像 + 分划
P.gunsight = function(s, env)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th = Screens.thermal(R, W, H, { cols = 26 })
  local G = RGB(230, 240, 230)
  reticleTank(R, W, H, G)
  local info = Tx(R, "", 4, H - 16, W - 8, 14, 12, G, nil, FONTB, 8)
  local rng = Tx(R, "", W - 100, 3, 96, 14, 12, G, Enum.TextXAlignment.Right, FONTB, 8)
  return function(d)
    if d.gunEye then
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = (d.zoomTxt == "10X") and 7 or 20, pal = (d.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
    end
    info.Text = string.format("热像  %s  %s", (d.pol == "BLK") and "黑热" or "白热", (d.zoomTxt == "10X") and "10倍" or "3.5倍")
    rng.Text = d.range and string.format("距离 %04d", math.floor(d.range)) or ""
  end
end

---------------------------------------------------------------- 飞机座舱的页面（数据见 Interior.lua 的 gatherAir）

-- 姿态（主飞行显示）：天地线跟着俯仰、滚转，左边空速、右边高度、上面航向
P.pfd = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local clip = F(R, W * 0.18, H * 0.12, W * 0.64, H * 0.76, RGB(0, 0, 0), 0, 1)
  clip.ClipsDescendants = true
  local cw, ch = W * 0.64, H * 0.76
  local ball = F(clip, cw / 2 - cw * 1.5, ch / 2 - ch * 1.5, cw * 3, ch * 3, RGB(40, 110, 200), 0, 2)
  local ground = F(ball, 0, ch * 1.5, cw * 3, ch * 1.5, RGB(130, 84, 40), 0, 3)
  F(ball, 0, ch * 1.5 - 1, cw * 3, 2, RGB(255, 255, 255), 0, 4)
  local rungs = {}
  for i = -6, 6 do
    if i ~= 0 then
      local y = ch * 1.5 - i * 5 * (ch / 50)
      local w = (i % 2 == 0) and cw * 0.32 or cw * 0.18
      table.insert(rungs, F(ball, cw * 1.5 - w / 2, y, w, 1, RGB(255, 255, 255), 0, 4))
      if i % 2 == 0 then Tx(ball, tostring(math.abs(i * 5)), cw * 1.5 + w / 2 + 2, y - 7, 30, 14, 11, RGB(255, 255, 255), nil, FONT, 5) end
    end
  end
  -- 飞机符号
  local Y = RGB(255, 210, 40)
  F(clip, cw * 0.28, ch / 2 - 1, cw * 0.16, 3, Y, 0, 8)
  F(clip, cw * 0.56, ch / 2 - 1, cw * 0.16, 3, Y, 0, 8)
  F(clip, cw / 2 - 3, ch / 2 - 3, 6, 6, Y, 0, 8)
  local spd = Tx(R, "", 2, H / 2 - 10, W * 0.16, 20, 15, RGB(255, 255, 255), Enum.TextXAlignment.Right, FONTB, 9)
  Box(R, 2, H / 2 - 11, W * 0.16, 22, 1, RGB(255, 255, 255), 9)
  local alt = Tx(R, "", W * 0.83, H / 2 - 10, W * 0.16, 20, 15, RGB(255, 255, 255), Enum.TextXAlignment.Left, FONTB, 9)
  Box(R, W * 0.82, H / 2 - 11, W * 0.17, 22, 1, RGB(255, 255, 255), 9)
  local hdg = Tx(R, "", W * 0.4, 2, W * 0.2, 16, 14, RGB(255, 255, 255), Enum.TextXAlignment.Center, FONTB, 9)
  local bot = Tx(R, "", 4, H - 16, W - 8, 14, 11, RGB(160, 230, 160), nil, FONT, 9)
  Tx(R, zh and "空速" or "KT", 2, H / 2 + 12, W * 0.16, 12, 10, RGB(160, 200, 160), Enum.TextXAlignment.Right, FONT, 9)
  Tx(R, zh and "高度 米" or "ALT FT", W * 0.83, H / 2 + 12, W * 0.16, 12, 10, RGB(160, 200, 160), nil, FONT, 9)
  return function(d)
    local pitch, roll = d.pitch or 0, d.roll or 0
    local py = pitch * (ch / 50)
    ball.Rotation = -roll
    ball.Position = UD2(0, cw / 2 - cw * 1.5 + math.sin(math.rad(roll)) * py, 0, ch / 2 - ch * 1.5 + math.cos(math.rad(roll)) * py)
    spd.Text = zh and string.format("%d", math.floor(d.kmh or 0)) or string.format("%d", math.floor(d.kt or 0))
    alt.Text = zh and string.format("%d", math.floor(d.altM or 0)) or string.format("%d", math.floor((d.altM or 0) * 3.281))
    hdg.Text = string.format("%03d", math.floor((d.hdg or 0) % 360))
    bot.Text = string.format("G %.1f   AOA %.0f   M %.2f   VS %+d", d.g or 1, d.aoa or 0, d.mach or 0, math.floor(d.vs or 0))
  end
end

-- 雷达（B 显示）：横着是方位 ±60°、竖着是距离；目标小方块，锁定的加框
P.radar = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G = RGB(80, 230, 110)
  local x0, y0, w0, h0 = W * 0.08, H * 0.1, W * 0.84, H * 0.8
  Box(R, x0, y0, w0, h0, 1, G, 2)
  for i = 1, 3 do F(R, x0, y0 + h0 * i / 4, w0, 1, G, 0.7, 2) F(R, x0 + w0 * i / 4, y0, 1, h0, G, 0.7, 2) end
  local top = Tx(R, "", 4, 2, W - 8, 14, 11, G, nil, FONTB, 4)
  local rngT = Tx(R, "", 2, y0 - 2, x0 - 2, 14, 10, G, Enum.TextXAlignment.Right, FONT, 4)
  local pool = {}
  local lockB = Box(R, 0, 0, 14, 14, 2, RGB(255, 220, 60), 6)
  lockB.Visible = false
  local scan = F(R, x0, y0, 2, h0, G, 0.3, 3)
  local st = { rng = 80 }
  s.onKey = function(k) if k == "RNG" then st.rng = (st.rng == 80) and 40 or ((st.rng == 40) and 160 or 80) end end
  return function(d)
    local n = 0
    for _, c in ipairs(d.contacts or {}) do
      local x = x0 + w0 * (0.5 + clamp(c.az / 120, -0.5, 0.5))
      local y = y0 + h0 * (1 - clamp(c.km / st.rng, 0, 1))
      n += 1
      local f = pool[n] or F(R, 0, 0, 8, 8, G, 0, 5)
      pool[n] = f
      f.Visible = c.km < st.rng
      f.Position = UD2(0, x - 4, 0, y - 4)
      f.BackgroundColor3 = c.friend and RGB(80, 160, 255) or G
      if c.locked then
        lockB.Visible = true
        lockB.Position = UD2(0, x - 7, 0, y - 7)
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
    if not d.lockAny then lockB.Visible = false end
    local t = (d.t or 0) * 0.8
    scan.Position = UD2(0, x0 + w0 * (0.5 + 0.5 * math.sin(t)), 0, y0)
    top.Text = zh and string.format("雷达  边扫描边跟踪  %d 公里  目标 %d", st.rng, n) or string.format("RDR  TWS  %d NM  TGT %d", math.floor(st.rng * 0.54), n)
    rngT.Text = tostring(st.rng)
  end
end

-- 战术态势（地图）：同坦克的指挥地图，比例大（飞机飞得快）
P.sa = function(s, env, zh)
  return P.cid(s, setmetatable({ zooms = { 12000, 24000, 48000 } }, { __index = env }), zh)
end

-- 外挂管理（武器）：每种挂载的名字、剩几发，选中的那种亮，航炮弹数，主保险
P.sms = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G = RGB(90, 230, 120)
  Tx(R, zh and "外挂管理" or "STORES", 4, 2, W - 8, 14, 12, G, Enum.TextXAlignment.Center, FONTB, 3)
  -- 机身俯视轮廓
  local cx = W / 2
  F(R, cx - 4, H * 0.14, 8, H * 0.46, RGB(60, 90, 70), 0, 2)
  F(R, cx - W * 0.36, H * 0.34, W * 0.72, 6, RGB(60, 90, 70), 0, 2)
  F(R, cx - W * 0.14, H * 0.56, W * 0.28, 5, RGB(60, 90, 70), 0, 2)
  local rows = {}
  for i = 1, 6 do rows[i] = Tx(R, "", 8, H * 0.62 + (i - 1) * (H * 0.36 / 6), W - 16, H * 0.36 / 6, 12, G, nil, FONT, 3) end
  local arm = Tx(R, "", 4, H * 0.18, W * 0.4, 14, 11, RGB(255, 190, 60), nil, FONTB, 3)
  return function(d)
    local i = 0
    for _, w in ipairs(d.weapons or {}) do
      i += 1
      if rows[i] then
        rows[i].Text = string.format("%s %-10s ×%d", w.sel and "▶" or " ", w.name or "?", w.n or 0)
        rows[i].TextColor3 = w.sel and RGB(255, 255, 255) or G
      end
    end
    for j = i + 1, #rows do rows[j].Text = "" end
    arm.Text = zh and "主保险 开" or "MASTER ARM"
  end
end

-- 发动机 / 燃油
P.eng = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G = RGB(90, 230, 120)
  Tx(R, zh and "发动机  燃油" or "ENGINE  FUEL", 4, 2, W - 8, 14, 12, G, Enum.TextXAlignment.Center, FONTB, 3)
  local bars = {}
  for i = 1, 2 do
    local bg = F(R, W * (0.18 + (i - 1) * 0.22), H * 0.18, W * 0.12, H * 0.5, RGB(20, 34, 24), 0, 2)
    bars[i] = { f = F(bg, 0, 0, W * 0.12, 0, G, 0, 3), t = Tx(R, "", W * (0.14 + (i - 1) * 0.22), H * 0.70, W * 0.2, 14, 11, G, Enum.TextXAlignment.Center, FONTB, 3) }
  end
  local info = Tx(R, "", W * 0.62, H * 0.18, W * 0.36, H * 0.6, 11, G, nil, FONT, 3)
  info.TextYAlignment = Enum.TextYAlignment.Top
  info.TextWrapped = true
  return function(d)
    local k = clamp((d.thr or 0) / 100, 0, 1.3)
    for _, b in ipairs(bars) do
      local hh = H * 0.5 * clamp(k / 1.3, 0, 1)
      b.f.Size = UD2(0, W * 0.12, 0, hh)
      b.f.Position = UD2(0, 0, 0, H * 0.5 - hh)
      b.f.BackgroundColor3 = (k > 1) and RGB(255, 150, 60) or G
      b.t.Text = (k > 1) and (zh and "加力" or "AB") or string.format("%d%%", math.floor(60 + k * 40))
    end
    local fuel = clamp(d.fuel or 1, 0, 1)
    info.Text = string.format(zh and "内油 %d kg\n外油 %d kg\n油耗 %d kg/h\n排温 %d ℃\n液压 正常\n电源 正常" or "INT %d LB\nEXT %d LB\nFF %d PPH\nEGT %d C\nHYD 3000\nGEN ON",
      math.floor((zh and 12000 or 18000) * fuel), math.floor((zh and 3000 or 4500) * (d.fuelX or 0)), math.floor((zh and 3000 or 6000) * (0.3 + k)), math.floor(450 + k * 350))
  end
end

-- 多功能显示器：五个页面（姿态 / 雷达 / 态势 / 武器 / 发动机），上排按键换页
local function mfd(first)
  return function(s, env, zh)
    local W, H = s.px.X, s.px.Y
    local subs, ups = {}, {}
    for _, name in ipairs({ "pfd", "radar", "sa", "sms", "eng" }) do
      local f = F(s.root, 0, 0, W, H, RGB(0, 0, 0), 0, 1)
      local sub = { root = f, px = s.px, page = name }
      ups[name] = P[name](sub, env, zh)
      subs[name] = { f = f, sub = sub }
    end
    local st = { page = first }
    local MAP = { PFD = "pfd", RDR = "radar", SA = "sa", SMS = "sms", ENG = "eng", ["姿态"] = "pfd", ["雷达"] = "radar", ["态势"] = "sa", ["武器"] = "sms", ["发动机"] = "eng" }
    s.onKey = function(k, act)
      if MAP[k] then st.page = MAP[k]
      else
        local sb = subs[st.page].sub
        if sb.onKey then sb.onKey(canon(k), act) end
      end
    end
    return function(d)
      for name, it in pairs(subs) do it.f.Visible = name == st.page end
      local u = ups[st.page]
      if u then u(d) end
    end
  end
end
P.mfd_pfd, P.mfd_sa, P.mfd_sms, P.mfd_eng, P.mfd_rdr = mfd("pfd"), mfd("sa"), mfd("sms"), mfd("eng"), mfd("radar")

-- 全景座舱显示器（F-35 的 20×8 英寸、歼-20 的大屏）：左边态势 / 雷达、中间姿态、右边武器 / 发动机；按键换左右两块
P.pano = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local areas = { { 0, 0.42, "sa" }, { 0.42, 0.28, "pfd" }, { 0.70, 0.30, "sms" } }
  local subs = {}
  for i, a in ipairs(areas) do
    local f = F(s.root, W * a[1] + 2, 0, W * a[2] - 4, H, RGB(0, 0, 0), 0, 1)
    local sub = { root = f, px = Vector3.new(W * a[2] - 4, H, 0) }
    subs[i] = { f = f, sub = sub, name = a[3], up = P[a[3]](sub, env, zh) }
  end
  local function swap(i, name)
    local it = subs[i]
    if it.name == name then return end
    for _, c in ipairs(it.f:GetChildren()) do c:Destroy() end
    it.name = name
    it.sub.onKey = nil
    it.up = P[name](it.sub, env, zh)
  end
  local MAP = { SA = { 1, "sa" }, RDR = { 1, "radar" }, SMS = { 3, "sms" }, ENG = { 3, "eng" }, PFD = { 2, "pfd" },
    ["态势"] = { 1, "sa" }, ["雷达"] = { 1, "radar" }, ["武器"] = { 3, "sms" }, ["发动机"] = { 3, "eng" }, ["姿态"] = { 2, "pfd" } }
  s.onKey = function(k, act)
    local m = MAP[k]
    if m then swap(m[1], m[2])
    elseif subs[1].sub.onKey then subs[1].sub.onKey(canon(k), act) end
  end
  return function(d)
    for _, it in ipairs(subs) do if it.up then it.up(d) end end
  end
end

-- 上前显示器（通信、导航、时间、油量）
local function ufd(second)
  return function(s, env, zh)
    local W, H = s.px.X, s.px.Y
    local G = RGB(90, 230, 120)
    local L = {}
    for i = 1, 4 do L[i] = Tx(s.root, "", 4, 2 + (i - 1) * (H - 4) / 4, W - 8, (H - 4) / 4, 11, G, nil, FONT, 3) end
    return function(d)
      local t = d.clock or 0
      if second then
        L[1].Text = string.format(zh and "油量 %d%%" or "FUEL %d%%", math.floor((d.fuel or 1) * 100))
        L[2].Text = d.gear and d.gear > 0.5 and (zh and "起落架 放" or "GEAR DN") or (zh and "起落架 收" or "GEAR UP")
        L[3].Text = string.format(zh and "过载 %.1f" or "G %.1f", d.g or 1)
        L[4].Text = (d.warn and d.warn ~= "") and d.warn or ""
      else
        L[1].Text = zh and "通信1  251.000" or "COM1 251.000"
        L[2].Text = zh and "通信2  305.500" or "COM2 305.500"
        L[3].Text = string.format("%02d:%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, math.floor(t) % 60)
        L[4].Text = string.format(zh and "航向 %03d" or "HDG %03d", math.floor(d.hdg or 0))
      end
    end
  end
end
P.ufd, P.ufd2 = ufd(false), ufd(true)

-- 备份仪表：姿态球、空速表、高度表（指针）
local function dial(s, n, label)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(12, 12, 12)
  Ring(R, W / 2, H / 2, W * 0.46, 2, RGB(200, 200, 200), 2, RGB(16, 16, 16))
  for i = 0, n - 1 do
    local a = i / n * 2 * math.pi
    Ln(R, W / 2 + math.sin(a) * W * 0.38, H / 2 - math.cos(a) * H * 0.38, W / 2 + math.sin(a) * W * 0.44, H / 2 - math.cos(a) * H * 0.44, 1, RGB(220, 220, 220), 3)
  end
  Tx(R, label, 0, H * 0.62, W, 12, 10, RGB(200, 200, 200), Enum.TextXAlignment.Center, FONT, 3)
  local _, nd = Ln(R, W / 2, H / 2, W / 2, H * 0.12, 2, RGB(255, 255, 255), 5)
  return function(a) nd(W / 2, H / 2, W / 2 + math.sin(a) * W * 0.40, H / 2 - math.cos(a) * H * 0.40) end
end
P.asi = function(s, env, zh)
  local set = dial(s, 10, zh and "空速" or "KNOTS")
  return function(d) set((d.kt or 0) / 1000 * 2 * math.pi) end
end
P.alt = function(s, env, zh)
  local set = dial(s, 10, zh and "高度" or "ALT")
  return function(d) set(((d.altM or 0) * 3.281 % 1000) / 1000 * 2 * math.pi) end
end
P.adi = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local ball = F(R, -W, -H, W * 3, H * 3, RGB(70, 130, 210), 0, 2)
  F(ball, 0, H * 1.5, W * 3, H * 1.5, RGB(30, 30, 30), 0, 3)
  F(ball, 0, H * 1.5 - 1, W * 3, 2, RGB(255, 255, 255), 0, 4)
  F(R, W * 0.25, H / 2 - 1, W * 0.5, 3, RGB(255, 200, 40), 0, 6)
  return function(d)
    local py = (d.pitch or 0) * H / 60
    ball.Rotation = -(d.roll or 0)
    ball.Position = UD2(0, -W + math.sin(math.rad(d.roll or 0)) * py, 0, -H + math.cos(math.rad(d.roll or 0)) * py)
  end
end
-- A-10 的一排机械仪表（两台发动机转速、涡轮温度、燃油、油压）
P.gauges = function(s, env)
  local W, H = s.px.X, s.px.Y
  local sets = {}
  local labels = { "RPM L", "RPM R", "ITT L", "ITT R", "FUEL", "OIL" }
  for i, lb in ipairs(labels) do
    local f = F(s.root, (i - 1) * W / 6, 0, W / 6, H, RGB(10, 10, 10), 0, 1)
    sets[i] = dial({ root = f, px = Vector3.new(W / 6, H, 0) }, 10, lb)
  end
  return function(d)
    local k = clamp((d.thr or 0) / 100, 0, 1.2)
    sets[1](k * 4.5) sets[2](k * 4.5) sets[3](2 + k * 2.5) sets[4](2 + k * 2.5)
    sets[5]((d.fuel or 1) * 5) sets[6](3 + k)
  end
end

-- 平显：符号按眼睛的位置投到组合玻璃上（看着像在无穷远——机头指哪、速度矢量指哪就画在哪）
P.hud = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundTransparency = 1
  local G = RGB(120, 255, 150)
  local function mk(w, h) local f = F(R, 0, 0, w, h, G, 0, 3) f.AnchorPoint = Vector2.new(0.5, 0.5) return f end
  local fpm = Ring(R, 0, 0, 7, 2, G, 4)
  local fpmL, fpmR, fpmT = mk(10, 2), mk(10, 2), mk(2, 6)
  local bore = Tx(R, "—w—", 0, 0, 60, 16, 14, G, Enum.TextXAlignment.Center, FONTB, 4)
  bore.AnchorPoint = Vector2.new(0.5, 0.5)
  local rungs = {}
  for i = -9, 9 do
    if i ~= 0 then
      local f = mk(70, 2)
      local t = Tx(R, tostring(math.abs(i * 10)), 0, 0, 30, 14, 12, G, Enum.TextXAlignment.Left, FONT, 4)
      t.AnchorPoint = Vector2.new(0, 0.5)
      rungs[#rungs + 1] = { f = f, t = t, p = i * 10 }
    end
  end
  local horizon = mk(W * 0.9, 2)
  local spd = Tx(R, "", W * 0.04, H * 0.42, W * 0.18, 18, 16, G, Enum.TextXAlignment.Right, FONTB, 4)
  local alt = Tx(R, "", W * 0.78, H * 0.42, W * 0.2, 18, 16, G, Enum.TextXAlignment.Left, FONTB, 4)
  local hdg = Tx(R, "", W * 0.4, H * 0.04, W * 0.2, 16, 15, G, Enum.TextXAlignment.Center, FONTB, 4)
  local info = Tx(R, "", W * 0.04, H * 0.80, W * 0.92, 16, 13, G, Enum.TextXAlignment.Left, FONT, 4)
  local wpn = Tx(R, "", W * 0.04, H * 0.88, W * 0.92, 16, 13, G, Enum.TextXAlignment.Left, FONTB, 4)
  local box = Box(R, 0, 0, 22, 22, 2, G, 5)
  box.AnchorPoint = Vector2.new(0.5, 0.5)
  local warn = Tx(R, "", W * 0.2, H * 0.6, W * 0.6, 20, 18, G, Enum.TextXAlignment.Center, FONTB, 6)
  return function(d)
    local proj = d.hudProj   -- 世界方向 → 平显上的像素（Interior 给的，按眼睛的位置算）
    if not proj then return end
    local function put(f, dir)
      local x, y = proj(dir)
      if not x or x < -40 or x > W + 40 or y < -40 or y > H + 40 then f.Visible = false return nil end
      f.Visible = true
      f.Position = UD2(0, x, 0, y)
      return x, y
    end
    local fx, fy = put(fpm, d.velDir or d.fwd)
    if fx then
      fpmL.Visible, fpmR.Visible, fpmT.Visible = true, true, true
      fpmL.Position, fpmR.Position, fpmT.Position = UD2(0, fx - 13, 0, fy), UD2(0, fx + 13, 0, fy), UD2(0, fx, 0, fy - 9)
    else fpmL.Visible, fpmR.Visible, fpmT.Visible = false, false, false end
    put(bore, d.fwd)
    -- 俯仰梯：按世界的地平线画（跟着机身滚转倾斜）
    local fh = Vector3.new(d.fwd.X, 0, d.fwd.Z)
    if fh.Magnitude > 1e-3 then
      fh = fh.Unit
      local rh = Vector3.new(-fh.Z, 0, fh.X)
      local hx, hy = proj(fh)
      local hx2, hy2 = proj((fh + rh * 0.3).Unit)
      if hx and hx2 then
        horizon.Visible = true
        horizon.Position = UD2(0, hx, 0, hy)
        horizon.Rotation = math.deg(math.atan2(hy2 - hy, hx2 - hx))
      else horizon.Visible = false end
      for _, r in ipairs(rungs) do
        local p = math.rad(r.p)
        local dir = fh * math.cos(p) + Vector3.new(0, math.sin(p), 0)
        local x, y = proj(dir)
        local x2, y2 = proj((dir + rh * 0.15).Unit)
        if x and x2 and x > 0 and x < W and y > 0 and y < H then
          r.f.Visible, r.t.Visible = true, true
          r.f.Position = UD2(0, x, 0, y)
          r.f.Rotation = math.deg(math.atan2(y2 - y, x2 - x))
          r.f.BackgroundTransparency = (r.p < 0) and 0.45 or 0
          r.t.Position = UD2(0, x + 40, 0, y)
        else r.f.Visible, r.t.Visible = false, false end
      end
    end
    spd.Text = zh and string.format("%d", math.floor(d.kmh or 0)) or string.format("%d", math.floor(d.kt or 0))
    alt.Text = zh and string.format("%d", math.floor(d.altM or 0)) or string.format("%d", math.floor((d.altM or 0) * 3.281))
    hdg.Text = string.format("%03d", math.floor((d.hdg or 0) % 360))
    info.Text = string.format("G %.1f  M %.2f  α %.0f", d.g or 1, d.mach or 0, d.aoa or 0)
    wpn.Text = d.wpnText or ""
    if d.lockDir then
      local x = put(box, d.lockDir)
      box.Visible = x ~= nil
    else box.Visible = false end
    warn.Text = d.warn or ""
  end
end

function Screens.make(s, env)
  local fn = P[s.page]
  if not fn then return nil end
  local ok, up = pcall(fn, s, env, env and env.zh)   -- zh：中文座舱（歼-20 等）的页面写中文
  if ok then return up end
  warn("[内饰] 屏幕页面 " .. tostring(s.page) .. " 出错：" .. tostring(up))
  return nil
end

return Screens
