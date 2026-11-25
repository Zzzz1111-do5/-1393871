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
local FONT = Enum.Font.RobotoMono
local FONTB = Enum.Font.BuilderSansBold
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
-- 军标（用户 11-22：「电子屏地图要能显示敌单位，坦克、车之类的要有不同符号」）：照北约 APP-6 的样子简化——
--   友军蓝色长方框、敌军红色菱形框；框里的图形分兵种：坦克（装甲）一个椭圆（履带）、装甲车 / 步战车一个叉加椭圆（机械化步兵）、步兵一个叉、
--   自行火炮 / 岸炮一个实心圆点（炮兵）、防空车 / 高炮一道拱（防空）、直升机一个蝴蝶结（旋翼）、飞机一个尖头（固定翼）、军舰一条船身、工事一排垛口。
--   sym(parent, z) 返回一个能反复用的军标：set(x, y, typ, hostile, size)
local SYM_TYPES = { tank = true, apc = true, inf = true, arty = true, aa = true, heli = true, jet = true, ship = true, fort = true }
local function Sym(parent, z)
  local o = { typ = nil, hostile = nil }
  o.f = F(parent, 0, 0, 20, 20, RGB(0, 0, 0), 1, z)
  o.rect = F(o.f, 2, 4.5, 16, 11, RGB(70, 140, 255), 0.45, z + 1)
  o.rectS = Instance.new("UIStroke")
  o.rectS.Thickness, o.rectS.Color = 1.4, RGB(150, 200, 255)
  o.rectS.Parent = o.rect
  o.dia = F(o.f, 4, 4, 12, 12, RGB(230, 60, 50), 0.4, z + 1)
  o.dia.Rotation = 45
  o.diaS = Instance.new("UIStroke")
  o.diaS.Thickness, o.diaS.Color = 1.4, RGB(255, 150, 140)
  o.diaS.Parent = o.dia
  o.icon = F(o.f, 0, 0, 20, 20, RGB(0, 0, 0), 1, z + 2)
  local INK = RGB(250, 250, 250)
  local function line(x0, y0, x1, y1, t) return (Ln(o.icon, x0, y0, x1, y1, t or 1.3, INK, z + 3)) end
  local function ellipse(w, h)
    local e = F(o.icon, 10 - w / 2, 10 - h / 2, w, h, INK, 1, z + 3)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = e
    local st = Instance.new("UIStroke")
    st.Thickness, st.Color = 1.2, INK
    st.Parent = e
    return e
  end
  local function build(typ, hostile)
    for _, ch in ipairs(o.icon:GetChildren()) do ch:Destroy() end
    local k = hostile and 0.72 or 1   -- 菱形框里能画的地方小一点
    local a, b = 10 - 6 * k, 10 + 6 * k   -- 叉、线的左右端
    local u, v = 10 - 4 * k, 10 + 4 * k   -- 上下
    if typ == "tank" then ellipse(10 * k, 5 * k)
    elseif typ == "apc" then line(a, u, b, v) line(a, v, b, u) ellipse(8 * k, 4 * k)
    elseif typ == "inf" then line(a, u, b, v) line(a, v, b, u)
    elseif typ == "arty" then
      local d = F(o.icon, 10 - 2.2, 10 - 2.2, 4.4, 4.4, INK, 0, z + 3)
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = d
    elseif typ == "aa" then   -- 一道拱：一个圆只露上半截
      local clip = F(o.icon, 10 - 5 * k, 10 - 3 * k, 10 * k, 5 * k, INK, 1, z + 3)
      clip.ClipsDescendants = true
      local r = F(clip, 0, 0, 10 * k, 10 * k, INK, 1, z + 3)
      local c = Instance.new("UICorner")
      c.CornerRadius = UDim.new(0.5, 0)
      c.Parent = r
      local st = Instance.new("UIStroke")
      st.Thickness, st.Color = 1.2, INK
      st.Parent = r
      line(10 - 5 * k, 10 + 2 * k, 10 + 5 * k, 10 + 2 * k, 1)
    elseif typ == "heli" then line(a, u, b, v) line(a, v, b, u) line(a, u, a, v) line(b, u, b, v)
    elseif typ == "jet" then line(a, v, 10, u) line(10, u, b, v) line(10, u, 10, v + 1)
    elseif typ == "ship" then line(a, 10 + 1, b, 10 + 1) line(a + 1.5 * k, v, b - 1.5 * k, v) line(a, 10 + 1, a + 1.5 * k, v) line(b, 10 + 1, b - 1.5 * k, v) line(10, u, 10, 10 + 1)
    else   -- 工事：一排垛口
      line(a, v, b, v)
      for i = 0, 2 do F(o.icon, a + (i * 2 + 0.5) * (b - a) / 6 - 1, 10 - 1 * k, (b - a) / 6, 3 * k + 1, INK, 0, z + 3) end
    end
  end
  function o.set(x, y, typ, hostile, size)
    typ = SYM_TYPES[typ] and typ or "apc"
    if typ ~= o.typ or hostile ~= o.hostile then
      o.typ, o.hostile = typ, hostile
      o.rect.Visible, o.dia.Visible = not hostile, hostile
      build(typ, hostile)
    end
    local sc = (size or 20) / 20
    o.f.Size = UD2(0, 20, 0, 20)
    o.f.Position = UD2(0, x - 10, 0, y - 10)
    if not o.scale then
      o.scale = Instance.new("UIScale")
      o.scale.Parent = o.f
    end
    o.scale.Scale = sc
    o.f.Visible = true
  end
  return o
end
Screens.Sym = Sym

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
  GRNB = { sky0 = RGB(168, 236, 168), sky1 = RGB(128, 206, 132), g0 = RGB(92, 168, 98), g1 = RGB(58, 126, 64), hot = RGB(6, 26, 8), warm = RGB(26, 72, 30), ridge = RGB(70, 140, 76) },   -- 绿色黑热（M1A2 CITV）
}
Screens.PAL = PAL

-- 在 parent（W × H 像素）里画热像；返回 { render(view) }：view = { eye, f, r, u（世界坐标的基）, hfov 水平视角（度）, pal, ents, Map, range }
function Screens.thermal(parent, W, H, opt)
  opt = opt or {}
  -- 列数（山脊线一列一列算）：按画面宽度加密到每 5 个设计像素一列、最多 72 列（用户 11-23：显示屏清晰度太低——原来 22～36 列，山一格一格的）
  local N = math.max(opt.cols or 36, math.min(72, math.floor(W / 5)))
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
  -- M1A2 SEPv2 车长显示单元（用户 11-23 发来钢铁猛兽截图）：上屏左边一列、下屏键盘、方向键
  ["SCAN L"] = "自动扫描扇区的左边：设在热像仪现在指的方向", ["SCAN R"] = "自动扫描扇区的右边：设在热像仪现在指的方向", STOW = "热像仪收回、朝炮塔正前",
  ["VEH SYS"] = "本车状态：弹药、油、损伤", C3 = "指挥通信：上级通报、敌情报告、自己发出的消息",
  UP = "地图往北挪", DOWN = "地图往南挪", LEFT = "地图往西挪", RIGHT = "地图往东挪",
  ["1"] = "1（字母模式：A B C 连按换字母）", ["2"] = "2（字母模式：D E F）", ["3"] = "3（字母模式：G H I）", ["4"] = "4（字母模式：J K L）", ["5"] = "5（字母模式：M N O）",
  ["6"] = "6（字母模式：P Q R）", ["7"] = "7（字母模式：S T U）", ["8"] = "8（字母模式：V W X）", ["9"] = "9（字母模式：Y Z）", ["0"] = "0（字母模式：空格）",
  ["."] = "小数点", ["-"] = "横杠", CLR = "删掉最后一个字；没字了再按：清掉目标点", LTR = "切换字母 / 数字", NEXT = "这个字母打完了（连按同一个键打下一个字母）",
  ENT = "确定：偶数位数字（4 / 6 / 8 / 10 位，前一半东、后一半北）设目标点；打的是字就当消息发出去",
  -- M1A1 计算机控制面板 CCP 的数字键盘、主瞄准镜 / 热像仪控制面板上的旋钮（用户 11-23：电脑和观瞄设备实现现实中的功能）
  ["CCP ENT"] = "确定：把打的四位数装定成距离（米），弹道计算机按它算超高角", ["CCP CLR"] = "清除：删掉打了一半的数；没在打就清掉手动距离",
  ["DAY/TIS"] = "主瞄准镜视野选择：昼光通道 / 热像通道（下次开镜生效）", SABOT = "穿甲弹（M829）", HEAT = "破甲弹（M830）", MPAT = "多用途弹（M830A1）",
  CAN = "霰弹（M1028）", TEST = "计算机自检 + 灯检", DATA = "弹道数据页：弹种、距离、初速、超高角、飞行时间、侧倾",
}
for i = 0, 9 do Screens.KEYDESC["CCP " .. i] = "数字 " .. i .. "：手动装定距离（打四位数，再按 ENT）" end
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
  -- 竖屏（真模型的显示控制单元 ip_cdu：玻璃高比宽大）：画面在上，弹种两列在下，再下面待发、距离、方式各一行；横屏照旧
  local portrait = H > W * 1.1
  local vw, vh = math.floor(W * 0.56), math.floor(H * 0.70)
  if portrait then vw, vh = W - 8, math.floor(H * 0.46) end
  local view = F(R, portrait and 4 or (W - vw - 4), 4, vw, vh, RGB(0, 0, 0), 0, 1)
  view.ClipsDescendants = true
  local th = Screens.thermal(view, vw, vh, { cols = 24 })
  reticleTank(view, vw, vh, G)
  local LIST = zh and { { "ap", "穿甲弹" }, { "heat", "破甲弹" }, { "he", "榴弹" }, { "gl", "炮射导弹" } }
    or { { "SABOT", "SABOT" }, { "HEAT", "HEAT" }, { "MPAT", "MPAT" }, { "CAN", "CAN" } }   -- M1A2 SEPv2（没有弹药数据链，没有 AMP）
  local ammo = {}
  for i, a in ipairs(LIST) do
    if portrait then
      local cw, rh = (W - 12) / 2, 15
      local f = F(R, 4 + ((i - 1) % 2) * (cw + 4), vh + 8 + math.floor((i - 1) / 2) * (rh + 2), cw, rh, RGB(18, 26, 20), 0, 2)
      ammo[a[1]] = { f = f, t = Tx(f, a[2], 3, 0, cw - 4, rh, 11, G, Enum.TextXAlignment.Left, FONTB) }
    else
      local f = F(R, 4, 4 + (i - 1) * ((vh - 4) / #LIST), W - vw - 12, (vh - 4) / #LIST - 3, RGB(18, 26, 20), 0, 2)
      ammo[a[1]] = { f = f, t = Tx(f, a[2], 4, 0, W - vw - 16, (vh - 4) / #LIST - 3, 12, G, Enum.TextXAlignment.Left, FONTB) }
    end
  end
  local ready, readyT, rng, mode
  if portrait then
    local by = vh + 8 + math.ceil(#LIST / 2) * 17 + 2
    ready = F(R, 4, by, W - 8, 14, RGB(18, 26, 20), 0, 2)
    readyT = Tx(ready, "", 0, 0, W - 8, 14, 11, G, Enum.TextXAlignment.Center, FONTB)
    rng = Tx(R, "", 4, by + 16, W - 8, 13, 11, G, nil, FONTB)
    mode = Tx(R, "", 4, by + 30, W - 8, 12, 9, G)
  else
    ready = F(R, 4, vh + 8, W * 0.42, H - vh - 12, RGB(18, 26, 20), 0, 2)
    readyT = Tx(ready, "", 0, 0, W * 0.42, H - vh - 12, 13, G, Enum.TextXAlignment.Center, FONTB)
    rng = Tx(R, "", W * 0.46, vh + 8, W * 0.52, (H - vh - 12) / 2, 13, G, nil, FONTB)
    mode = Tx(R, "", W * 0.46, vh + 8 + (H - vh - 12) / 2, W * 0.52, (H - vh - 12) / 2, 11, G)
  end
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
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or ((d.zoomTxt == "10X") and 7 or 20), pal = (d.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
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

-- M1A1 计算机控制面板 CCP（用户 11-23：「有一个带内饰的 m1a1 里面的电脑……给那个电脑和观瞄设备实现现实中的功能」）：
--   炮长右手边那个斜挂着的黑盒子（原模型的器材，tools/models/blveh.py 转的 m1a1i），左边是显示窗、右边 3 × 4 的键盘。
--   真车上这台弹道计算机按激光测的距离、弹种、耳轴倾斜（侧倾）、横风、药温、气压、炮口基准算超高角和提前量；数据都从这里看、从这里装定。
--   显示窗（橙红色的数码管字）：大字是弹道计算机现在用的距离 + 来源（LRF 激光测的 / MAN 手动装定 / BSGT 战斗瞄准距离 / ---- 没回波），
--     下面四个弹种灯（选中的亮）、超高角（密位）和飞行时间（秒，Ballistics 真算的）、侧倾、待发；DATA 页列全部弹道数据，TEST 页是机内自检
--   键盘（原模型上是 3 × 4 的数字键盘：1 2 3 / 4 5 6 / 7 8 9 / CLR 0 ENT，都真起作用）：打四位数、按 ENT——手动装定距离
--     （弹道计算机就按它算超高角，开镜看得到炮跟着抬）；CLR 删掉打了一半的数，没在打就清掉手动距离（回到激光测的 / 战斗瞄准距离）
--   目镜右边两块面板上的旋钮、拨杆也接到这里（Interior 的 m1a1 内饰）：WHT/BLK 热像极性、3X/10X 倍率、DAY/TIS 昼光 / 热像、AMMO 弹种选择开关
P.ccp = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(6, 4, 4)
  local LED = RGB(255, 92, 36)          -- 数码管的橙红
  local DIM = RGB(52, 18, 10)           -- 没亮的段（数码管底下隐约看得见的 8）
  local GRN = RGB(120, 255, 120)
  local function L(en, cn) return zh and cn or en end
  local BALOK, BAL = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Ballistics", 2)) end)
  if not BALOK then BAL = nil end
  local top = Tx(R, "CCP  M1A1", 6, 3, W * 0.5, 14, 11, LED, nil, FONTB, 3)
  local fcsT = Tx(R, "", W * 0.5, 3, W * 0.5 - 6, 14, 11, LED, Enum.TextXAlignment.Right, FONTB, 3)
  local _ = top
  -- 大字：距离（底下一排暗的 8888）
  local bigY, bigH = 20, math.floor(H * 0.34)
  Tx(R, "8888", 6, bigY, W * 0.62, bigH, bigH, DIM, Enum.TextXAlignment.Right, FONT, 3)
  local big = Tx(R, "----", 6, bigY, W * 0.62, bigH, bigH, LED, Enum.TextXAlignment.Right, FONT, 4)
  local unit = Tx(R, "M", W * 0.64, bigY + bigH * 0.12, W * 0.12, bigH * 0.4, bigH * 0.36, LED, nil, FONTB, 4)
  local src = Tx(R, "", W * 0.64, bigY + bigH * 0.52, W * 0.34, bigH * 0.4, bigH * 0.3, LED, nil, FONTB, 4)
  local _2 = unit
  -- 弹种灯
  local AM = { "SABOT", "HEAT", "MPAT", "CAN" }
  local lamps = {}
  local ly = bigY + bigH + 6
  local lw = (W - 12 - 3 * 4) / 4
  for i, a in ipairs(AM) do
    local f = F(R, 6 + (i - 1) * (lw + 4), ly, lw, 16, RGB(30, 10, 6), 0, 3)
    lamps[a] = { f = f, t = Tx(f, a, 0, 0, lw, 16, 11, DIM, Enum.TextXAlignment.Center, FONTB, 4) }
  end
  local se = Tx(R, "", 6, ly + 22, W - 12, 14, 12, LED, nil, FONT, 3)
  local cantT = Tx(R, "", 6, ly + 38, W - 12, 14, 12, LED, nil, FONT, 3)
  local stat = F(R, 6, H - 22, W - 12, 18, RGB(30, 10, 6), 0, 3)
  local statT = Tx(stat, "", 0, 0, W - 12, 18, 12, LED, Enum.TextXAlignment.Center, FONTB, 4)
  local pages = { DATA = textPage(s, L("BALLISTIC DATA", "弹道数据"), 8, LED), TEST = textPage(s, L("COMPUTER SELF TEST", "计算机自检"), 7, LED) }
  local FCS = zh and { "正常", "应急", "手动" } or { "NORMAL", "EMERGENCY", "MANUAL" }
  local st = { page = nil, fcs = 1, msg = nil, msgT = 0, testT = nil, R = nil, entry = "", sym = "SABOT" }
  local SYM = { m829a3 = "SABOT", m830 = "HEAT", m830a1 = "MPAT", m1028 = "CAN", m900 = "SABOT", m456 = "HEAT" }
  s.st = st   -- 测试用
  s.onKey = function(k, act)
    k = canon(k)
    local dig = string.match(k, "^CCP (%d)$")
    if dig then   -- 数字键：最多四位
      if #st.entry < 4 then st.entry = st.entry .. dig end
    elseif k == "CCP ENT" then
      local r = tonumber(st.entry)
      st.entry = ""
      if r and r >= 100 and r <= 5000 then act.range(r) st.msg, st.msgT = string.format(L("MAN RANGE %d M", "手动距离 %d 米"), r), os.clock()
      else st.msg, st.msgT = L("RANGE ERROR", "距离超出范围"), os.clock() end
    elseif k == "CCP CLR" then
      if st.entry ~= "" then st.entry = ""
      else act.range(nil) st.msg, st.msgT = L("MAN RANGE CLEARED", "手动距离已清"), os.clock() end
    elseif k == "AMMO" then   -- 弹种选择开关：SABOT → HEAT → MPAT → CAN
      local i = table.find(AM, st.sym) or 1
      act.ammo(AM[i % #AM + 1])
    elseif k == "SABOT" or k == "HEAT" or k == "MPAT" or k == "CAN" then act.ammo(k)
    elseif k == "LRF" then act.lase()
    elseif k == "FCS" then st.fcs = st.fcs % 3 + 1 act.fcsMode(st.fcs)
    elseif k == "TEST" then st.testT, st.page = os.clock(), "TEST" if act.bit then act.bit() else act.lampTest() end
    elseif k == "BSGT" then   -- 战斗瞄准：清掉测的 / 手动的距离，回到这个弹种的战斗瞄准距离
      if act.battlesight then act.battlesight() end
      st.entry = ""
      st.msg, st.msgT = L("BATTLESIGHT", "战斗瞄准"), os.clock()
    elseif k == "MRS" then   -- 炮口基准更新：量炮管的热弯曲，计算机按它修正
      if act.mrs then act.mrs() end
      st.msg, st.msgT = L("MRS UPDATE COMPLETE", "炮口基准更新完成"), os.clock()
    elseif k == "DATA" then st.page = (st.page == "DATA") and nil or "DATA"
    elseif k == "WHT/BLK" then act.polarity() st.msg, st.msgT = L("TIS POLARITY", "热像极性"), os.clock()
    elseif k == "3X/10X" then act.zoom() st.msg, st.msgT = L("GPS MAGNIFICATION", "主瞄准镜倍率"), os.clock()
    elseif k == "DAY/TIS" then act.thermal() st.msg, st.msgT = L("GPS VISION SELECT", "主瞄准镜昼光 / 热像"), os.clock() end
  end
  return function(d)
    st.fcs = d.fcsMode or st.fcs   -- 火控方式以 Drive 的为准（目镜下面的旋钮也能拨）
    if d.bitT and d.bitT ~= st.bitSeen then st.bitSeen, st.testT, st.page = d.bitT, d.bitT, "TEST" end   -- 面板上的自检按钮
    if st.page == "TEST" and st.testT and os.clock() - st.testT > 6 then st.page = nil end
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    local amKey = d.fcsAm
    local am = BAL and amKey and BAL.AMMO[amKey]
    local sym = SYM[amKey or ""] or (am and am.sym) or "SABOT"
    st.sym = sym
    for a, it in pairs(lamps) do
      local on = a == sym
      it.f.BackgroundColor3 = on and LED or RGB(30, 10, 6)
      it.t.TextColor3 = on and RGB(20, 4, 0) or DIM
    end
    -- 弹道计算机现在用的距离：激光测的 / 手动装定的 / 没测就是这种弹的战斗瞄准距离
    local Rm, tag
    if d.fcsR then Rm, tag = d.fcsR, d.fcsMan and "MAN" or ((d.lrf == "FIRST") and "LRF F" or "LRF L") .. (d.multi and " M" or "")
    elseif d.fcsNoRet then Rm, tag = nil, L("NO RTN", "无回波")
    else Rm, tag = d.bsR or (am and am.bs) or nil, "BSGT" end
    st.R = Rm
    if st.entry ~= "" then   -- 正在打数：大字显示打的数（没打满的位闪下划线）
      local blink = math.floor(os.clock() * 3) % 2 == 0
      big.Text = st.entry .. string.rep(blink and "_" or " ", 4 - #st.entry)
      src.Text = L("ENTER", "输入")
    else
      big.Text = Rm and string.format("%4d", math.floor(Rm + 0.5)) or "----"
      src.Text = tag
    end
    fcsT.Text = FCS[st.fcs]
    local seMil, tof = nil, nil
    if am and Rm and BAL then
      local a, t = BAL.superElev(am, Rm, 0)
      seMil, tof = a * 6400 / (2 * PI), t
    end
    se.Text = seMil and string.format(L("SE %5.2f MIL   TOF %4.2f S", "超高角 %5.2f 密位  飞行 %4.2f 秒"), seMil, tof) or L("SE  --.--", "超高角 --.--")
    cantT.Text = string.format(L("CANT %+5.1f   %s  %s", "侧倾 %+5.1f°  %s  %s"), d.cant or 0, (d.sightMode == 4) and "BLK" or ((d.sightMode == 3) and "WHT" or "DAY"), (d.zoom == 2) and "10X" or "3X")
    local rd = d.ready
    local adv = nil   -- 提示：稳定器关、激光保险、炮口基准该更新了（炮管热弯曲没修正的超过 0.25 毫弧度）
    if math.abs(d.droopErr or 0) > 0.25 then adv = L("MRS UPDATE REQUIRED", "需要炮口基准更新")
    elseif d.stab == false then adv = L("STAB OFF", "稳定器关")
    elseif d.arm == false then adv = L("LRF SAFE", "激光保险") end
    if st.msg and os.clock() - st.msgT < 2.5 then statT.Text, statT.TextColor3 = st.msg, LED
    elseif adv and math.floor(os.clock() * 1.5) % 2 == 0 then statT.Text, statT.TextColor3 = adv, LED
    else
      statT.Text = rd and L("READY TO FIRE", "待发") or L("LOADING", "装填中")
      statT.TextColor3 = rd and GRN or LED
    end
    if st.page == "DATA" then
      pages.DATA.set({
        string.format(L("AMMO      %s", "弹种    %s"), am and am.name or "--"),
        string.format(L("RANGE     %s M  (%s)", "距离    %s 米（%s）"), Rm and tostring(math.floor(Rm + 0.5)) or "----", tag),
        string.format(L("MUZZLE V  %d M/S", "初速    %d 米/秒"), am and am.v0 or 0),
        seMil and string.format(L("SUPERELEV %.2f MIL", "超高角  %.2f 密位"), seMil) or "",
        tof and string.format(L("TIME OF FLIGHT %.2f S", "飞行时间 %.2f 秒"), tof) or "",
        string.format(L("CANT      %+.1f DEG", "侧倾    %+.1f°"), d.cant or 0),
        L("XWIND 0 KN  TEMP 21 C  BARO 1013", "横风 0  气温 21℃  气压 1013"),
        string.format(L("LEAD      %s", "提前量  %s"), (d.fcsAim and d.fcsAim.lead) and L("ON", "有") or L("OFF", "无")),
      })
    elseif st.page == "TEST" then
      local k = math.floor((os.clock() - (st.testT or 0)) / 0.7)
      local items = { L("PROCESSOR ..... GO", "处理器 ...... 正常"), L("MEMORY ........ GO", "存储器 ...... 正常"), L("LRF ........... GO", "激光测距 .... 正常"),
        L("CANT SENSOR ... GO", "侧倾传感器 .. 正常"), L("WIND SENSOR ... GO", "横风传感器 .. 正常"), L("GPS / TIS ..... GO", "瞄准镜 / 热像 正常"), L("TEST COMPLETE", "自检完成") }
      local lines = {}
      for i = 1, math.min(#items, k) do lines[i] = items[i] end
      pages.TEST.set(lines)
    end
  end
end

-- M1A2 SEPv2 炮长控制显示面板 GCDP（用户 11-24：「m1a2sepv2……按钮什么的实现功能，实现现实中那几块屏幕所有的功能」）：
--   炮长右手边那台机器（M1A1 原模型的计算机外壳，InteriorAbrams 借过来）：左边显示窗、右边 3 × 4 数字键盘、下面两排软键。
--   真车上 GCDP 是炮长手动给火控输入、看火控状态、做维护的那块面板（FM 3-20.21：「manual inputs to the fire control computer, bypassing automatic inputs,
--   and performing maintenance functions」）——这里每个键都真起作用（Interior 的动作 → Drive.lua 的火控）：
--   · 主页：左边主瞄准镜的画面（热像 / 昼光，照极性、视场），右边弹种（选中的亮）、待发；下面一行距离（激光末 / 首回波、多回波 M、手动 MAN、战斗瞄准 BS），
--     弹道计算机算的超高角和飞行时间，再下面火控方式、稳定器、激光保险、极性、倍率；炮管热弯曲没修正的超过 0.25 毫弧度闪「需要炮口基准更新」
--   · MAIN 菜单（数字键选）· AMMO 下一种弹（换了要重新装填）· RANGE 键盘打四位数 ENT 装定距离（CLR 删 / 清）· ADJUST 校炮偏差（4 / 6 方向、2 / 8 高低，
--     每下 0.05 密位，0 归零）、这种弹的战斗瞄准距离（1 / 3 减 / 加 50 米，5 回默认）· LRF 末回波 ↔ 首回波 · WHT/BLK · 3X/10X 视场下一档 ·
--     FCS 正常 → 应急（没有提前量）→ 手动（没有弹道计算机、没有稳定）· BSGT 战斗瞄准 · MRS 炮口基准更新 · BIT 自检 · RESET 关页面、清输入
P.gcdp2 = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(3, 6, 5)
  local G0 = RGB(110, 240, 140)
  local DIMG = RGB(30, 60, 38)
  local AMB = RGB(255, 186, 60)
  local RED = RGB(255, 80, 60)
  local function L(en, cn) return zh and cn or en end
  local BALOK, BAL = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Ballistics", 2)) end)
  if not BALOK then BAL = nil end
  local top = Tx(R, "GCDP  M1A2 SEPv2", 5, 2, W * 0.6, 14, 11, G0, nil, FONTB, 3)
  local fcsT = Tx(R, "", W * 0.4, 2, W * 0.6 - 5, 14, 11, G0, Enum.TextXAlignment.Right, FONTB, 3)
  local _ = top
  local vw, vh = math.floor(W * 0.60), math.floor(H * 0.58)
  local view = F(R, 4, 18, vw, vh, RGB(0, 0, 0), 0, 1)
  view.ClipsDescendants = true
  local th = Screens.thermal(view, vw, vh, { cols = 24 })
  reticleTank(view, vw, vh, G0)
  local viewT = Tx(view, "", 3, vh - 13, vw - 6, 12, 10, G0, Enum.TextXAlignment.Right, FONT, 8)
  local AM = { "SABOT", "HEAT", "MPAT", "CAN" }
  local amBox = {}
  local cx, cw = vw + 10, W - vw - 14
  local rh = math.floor((vh - 22) / 4)
  for i, a in ipairs(AM) do
    local f = F(R, cx, 18 + (i - 1) * rh, cw, rh - 3, DIMG, 0, 2)
    amBox[a] = { f = f, t = Tx(f, a, 4, 0, cw - 8, rh - 3, 12, G0, nil, FONTB, 3) }
  end
  local ready = F(R, cx, 18 + 4 * rh, cw, vh - 4 * rh, DIMG, 0, 2)
  local readyT = Tx(ready, "", 0, 0, cw, vh - 4 * rh, 11, G0, Enum.TextXAlignment.Center, FONTB, 3)
  local y0 = 22 + vh
  local lh = math.floor((H - y0 - 2) / 3)
  local rngT = Tx(R, "", 5, y0, W - 10, lh, math.min(15, lh), G0, nil, FONTB, 3)
  local seT = Tx(R, "", 5, y0 + lh, W - 10, lh, math.min(12, lh - 1), G0, nil, FONT, 3)
  local stT = Tx(R, "", 5, y0 + 2 * lh, W - 10, lh, math.min(12, lh - 1), G0, nil, FONT, 3)
  local pages = { MAIN = textPage(s, L("MAIN MENU", "主菜单"), 9, G0), AMMO = textPage(s, L("AMMUNITION SELECT", "弹种选择"), 6, G0),
    RANGE = textPage(s, L("MANUAL RANGE ENTRY", "手动装定距离"), 6, G0), ADJUST = textPage(s, L("ADJUST", "调整"), 8, G0), BIT = textPage(s, L("FCS BUILT-IN TEST", "火控自检"), 8, G0) }
  local FCSN = zh and { "正常", "应急", "手动" } or { "NORMAL", "EMERGENCY", "MANUAL" }
  local st = { page = nil, entry = "", msg = nil, msgT = 0, bitT = nil, fcs = 1, am = "SABOT", amKey = nil, bitSeen = nil }
  s.st = st   -- 测试用
  local function say(m) st.msg, st.msgT = m, os.clock() end
  local function digitKey(k)
    local dg = string.match(k, "^CCP (%d)$") or string.match(k, "^(%d)$")
    return dg and tonumber(dg) or nil
  end
  s.onKey = function(k, act)
    k = canon(k)
    local dg = digitKey(k)
    local isEnt = k == "CCP ENT" or k == "ENT"
    local isClr = k == "CCP CLR" or k == "CLR"
    if st.page == "ADJUST" and (dg or isClr) then
      if dg == 4 then act.bore(-0.05, 0) elseif dg == 6 then act.bore(0.05, 0)
      elseif dg == 8 then act.bore(0, 0.05) elseif dg == 2 then act.bore(0, -0.05)
      elseif dg == 0 then act.bore(nil, nil) say(L("BORESIGHT ZEROED", "校炮偏差归零"))
      elseif dg == 1 or dg == 3 then   -- 这种弹的战斗瞄准距离减 / 加 50 米
        local key = BAL and BAL.PANEL[st.am]
        local bs0 = key and BAL.AMMO[key] and BAL.AMMO[key].bs or 1000
        act.bsRange(key, (st.bsR or bs0) + ((dg == 3) and 50 or -50))
      elseif dg == 5 then
        local key = BAL and BAL.PANEL[st.am]
        act.bsRange(key, nil)
        say(L("BATTLESIGHT RANGE DEFAULT", "战斗瞄准距离恢复默认"))
      elseif isClr then st.page = nil end
      return
    end
    if st.page == "MAIN" and dg then   -- 菜单：数字键选
      local MENU = { "AMMO", "RANGE", "ADJUST", "LRF", "FCS", "BSGT", "MRS", "BIT" }
      if MENU[dg] then st.page = nil k = MENU[dg] dg = nil end
    elseif st.page == "AMMO" and dg and AM[dg] then
      act.ammo(AM[dg])
      say(L("INDEXED ", "已选 ") .. AM[dg])
      st.page = nil
      return
    end
    if dg then   -- 主页 / 装定距离页：打数
      st.page = "RANGE"
      if #st.entry < 4 then st.entry = st.entry .. tostring(dg) end
      return
    elseif isEnt then
      if st.page == "RANGE" or st.entry ~= "" then
        local r = tonumber(st.entry)
        st.entry = ""
        st.page = nil
        if r and r >= 100 and r <= 5000 then act.range(r) say(string.format(L("MAN RANGE %d M", "手动距离 %d 米"), r))
        else say(L("RANGE ERROR  100-5000", "距离超出范围（100～5000）")) end
      end
      return
    elseif isClr then
      if st.entry ~= "" then st.entry = string.sub(st.entry, 1, -2)
      elseif st.page then st.page = nil
      else act.range(nil) say(L("MAN RANGE CLEARED", "手动距离已清")) end
      return
    end
    if k == "MAIN" then st.page = (st.page == "MAIN") and nil or "MAIN"
    elseif k == "AMMO" then
      if st.page == "AMMO" then   -- 弹种页里再按：下一种
        local i = table.find(AM, st.am) or 1
        act.ammo(AM[i % #AM + 1])
      else st.page = "AMMO" end
    elseif k == "RANGE" then st.page, st.entry = "RANGE", ""
    elseif k == "ADJUST" then st.page = (st.page == "ADJUST") and nil or "ADJUST"
    elseif k == "LRF" then act.lrfToggle() say(L("LRF RETURN SELECT", "激光回波选择"))
    elseif k == "WHT/BLK" then act.polarity()
    elseif k == "3X/10X" then act.zoom()
    elseif k == "FCS" then st.fcs = st.fcs % 3 + 1 act.fcsMode(st.fcs)
    elseif k == "BSGT" then act.battlesight() st.entry = "" say(L("BATTLESIGHT", "战斗瞄准"))
    elseif k == "MRS" then act.mrs() say(L("MRS UPDATE COMPLETE", "炮口基准更新完成"))
    elseif k == "BIT" then act.bit()
    elseif k == "RESET" then st.page, st.entry = nil, "" say(L("RESET", "复位"))
    elseif k == "LASE" then act.lase() end
  end
  return function(d)
    st.fcs = d.fcsMode or 1
    if d.bitT and d.bitT ~= st.bitSeen then st.bitSeen, st.bitT, st.page = d.bitT, d.bitT, "BIT" end
    if st.page == "BIT" and st.bitT and os.clock() - st.bitT > 7 then st.page = nil end
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    local am = BAL and d.fcsAm and BAL.AMMO[d.fcsAm]
    st.am = (am and am.sym) or st.am
    st.bsR = d.bsR
    if d.gunEye and not st.page then
      local thermal = d.sightMode == 3 or d.sightMode == 4
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or 20,
        pal = thermal and ((d.pol == "BLK") and PAL.BLK or PAL.WHT) or PAL.DAY or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
      viewT.Text = string.format("%s  %s", thermal and ((d.pol == "BLK") and "BLK" or "WHT") or "DAY", d.zoomTxt or "")
    end
    for a, it in pairs(amBox) do
      local on = a == st.am
      it.f.BackgroundColor3 = on and G0 or DIMG
      it.t.TextColor3 = on and RGB(0, 0, 0) or G0
    end
    local rd = d.ready
    ready.BackgroundColor3 = rd and G0 or DIMG
    readyT.TextColor3 = rd and RGB(0, 0, 0) or AMB
    readyT.Text = rd and L("READY", "待发") or L("LOADING", "装填中")
    fcsT.Text = FCSN[st.fcs] or ""
    fcsT.TextColor3 = (st.fcs == 1) and G0 or ((st.fcs == 2) and AMB or RED)
    -- 距离：手动 / 激光（末 / 首回波、多回波）/ 战斗瞄准 / 没回波
    local Rm, src
    if st.entry ~= "" then
      local blink = math.floor(os.clock() * 3) % 2 == 0
      rngT.Text = L("ENTER RANGE ", "输入距离 ") .. st.entry .. string.rep(blink and "_" or " ", 4 - #st.entry)
    else
      if d.fcsR then Rm, src = d.fcsR, d.fcsMan and "MAN" or (((d.lrf == "FIRST") and "LRF F" or "LRF L") .. (d.multi and "  MULTI" or ""))
      elseif d.fcsNoRet then Rm, src = nil, L("NO RETURN", "无回波")
      else Rm, src = d.bsR or (am and am.bs) or nil, "BS" end
      rngT.Text = (Rm and string.format(L("RANGE %04d  ", "距离 %04d  "), math.floor(Rm + 0.5)) or L("RANGE ----  ", "距离 ----  ")) .. (src or "")
    end
    local seMil, tof
    if am and BAL and (Rm or d.bsR) and st.fcs ~= 3 then
      local a, t = BAL.superElev(am, Rm or d.bsR or am.bs, 0)
      seMil, tof = a * 6400 / (2 * math.pi), t
    end
    seT.Text = (st.fcs == 3) and L("MANUAL - NO BALLISTIC SOLUTION", "手动方式：没有弹道解算")
      or (seMil and string.format(L("SE %5.2f MIL   TOF %4.2f S   CANT %+4.1f", "超高角 %5.2f 密位  飞行 %4.2f 秒  侧倾 %+4.1f°"), seMil, tof, d.cant or 0) or "")
    local adv
    if math.abs(d.droopErr or 0) > 0.25 then adv = L("MRS UPDATE REQUIRED", "需要炮口基准更新") end
    local stLine = string.format("%s  %s  %s", d.stab and L("STAB ON", "稳定") or L("STAB OFF", "稳定器关"), d.arm and L("LRF ARM", "激光待命") or L("LRF SAFE", "激光保险"),
      (d.bore and (d.bore[1] ~= 0 or d.bore[2] ~= 0)) and string.format(L("BORE %+.2f/%+.2f", "校炮 %+.2f/%+.2f"), d.bore[1], d.bore[2]) or "")
    if st.msg and os.clock() - st.msgT < 2.5 then stT.Text, stT.TextColor3 = st.msg, AMB
    elseif adv and math.floor(os.clock() * 1.5) % 2 == 0 then stT.Text, stT.TextColor3 = adv, AMB
    else stT.Text, stT.TextColor3 = stLine, (d.stab and d.arm) and G0 or AMB end
    if st.page == "MAIN" then
      pages.MAIN.set({ L("1  AMMUNITION SELECT", "1  弹种选择"), L("2  MANUAL RANGE ENTRY", "2  手动装定距离"), L("3  ADJUST (BORESIGHT / BATTLESIGHT)", "3  调整（校炮 / 战斗瞄准距离）"),
        L("4  LRF  ", "4  激光  ") .. ((d.lrf == "FIRST") and L("FIRST RETURN", "首回波") or L("LAST RETURN", "末回波")),
        L("5  FCS MODE  ", "5  火控方式  ") .. (FCSN[st.fcs] or ""), L("6  BATTLESIGHT", "6  战斗瞄准"), L("7  MRS UPDATE", "7  炮口基准更新"), L("8  BUILT-IN TEST", "8  自检"),
        L("CLR  EXIT", "CLR  退出") })
    elseif st.page == "AMMO" then
      local lines = {}
      for i, a in ipairs(AM) do lines[i] = string.format("%d  %s%s", i, a, (a == st.am) and L("   << INDEXED", "   << 已选") or "") end
      lines[6] = L("KEY 1-4 TO INDEX   AMMO = NEXT", "按 1～4 选   AMMO 下一种")
      pages.AMMO.set(lines)
    elseif st.page == "RANGE" then
      local blink = math.floor(os.clock() * 3) % 2 == 0
      pages.RANGE.set({ L("ENTER 4 DIGITS (METERS)", "打四位数（米）"), "", "      " .. st.entry .. string.rep(blink and "_" or " ", 4 - #st.entry), "",
        L("ENT  APPLY     CLR  DELETE", "ENT 装定     CLR 删除"), L("RANGE 100 - 5000", "范围 100～5000") })
    elseif st.page == "ADJUST" then
      local key = BAL and BAL.PANEL[st.am]
      local bs0 = key and BAL.AMMO[key] and BAL.AMMO[key].bs or 0
      pages.ADJUST.set({
        string.format(L("BORESIGHT AZ  %+.2f MIL", "校炮 方向  %+.2f 密位"), d.bore and d.bore[1] or 0),
        string.format(L("BORESIGHT EL  %+.2f MIL", "校炮 高低  %+.2f 密位"), d.bore and d.bore[2] or 0),
        L("4 / 6  AZ   2 / 8  EL   0  ZERO", "4 / 6 方向  2 / 8 高低  0 归零"),
        string.format(L("BATTLESIGHT %s  %d M", "战斗瞄准 %s  %d 米"), st.am, d.bsR or bs0),
        L("1 / 3  -50 / +50 M   5  DEFAULT", "1 / 3 减 / 加 50 米  5 默认"),
        string.format(L("TUBE BEND %.2f MRAD  (MRS %+.2f)", "炮管弯曲 %.2f 毫弧度（未修正 %+.2f）"), d.droop or 0, d.droopErr or 0),
        string.format(L("CANT %+.1f DEG", "侧倾 %+.1f°"), d.cant or 0),
        L("CLR  EXIT", "CLR  退出") })
    elseif st.page == "BIT" then
      local kk = math.floor((os.clock() - (st.bitT or 0)) / 0.6)
      local items = { L("FIRE CONTROL ELECTRONICS .. GO", "火控电子 .......... 正常"), L("GUNNER'S PRIMARY SIGHT ... GO", "主瞄准镜 .......... 正常"),
        L("2ND GEN FLIR ............. GO", "二代热像 .......... 正常"), L("LASER RANGEFINDER ........ GO", "激光测距 .......... 正常"),
        L("CANT / CROSSWIND SENSOR .. GO", "侧倾 / 横风传感器 . 正常"), d.stab and L("GUN / TURRET DRIVE ....... GO", "炮 / 炮塔驱动 ..... 正常") or L("STABILIZATION ........ OFF", "稳定器 ............ 关"),
        (math.abs(d.droopErr or 0) > 0.25) and L("MRS ........ UPDATE REQUIRED", "炮口基准 .......... 要更新") or L("MUZZLE REFERENCE ......... GO", "炮口基准 .......... 正常"),
        L("BIT COMPLETE", "自检完成") }
      local lines = {}
      for i = 1, math.min(#items, kk) do lines[i] = items[i] end
      pages.BIT.set(lines)
    end
  end
end

-- M1A1 车长位的状态显示器（原模型车长面前两块屏的版面：FLIR、PWR、CITV、SGF、CEU、FCEU、CCHA 七格）：每格是一个分系统，绿 GO、黄 / 红有毛病；
--   PWR 电源（发动机熄火就只剩电瓶）、FCEU 火控电子组件、CEU 车长电子组件、SGF 稳定器、CCHA 车长操纵握把、FLIR / CITV 热像通道
P.m1stat = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(8, 12, 22)
  local LINE = RGB(210, 220, 230)
  local GRN, AMB, RED = RGB(90, 230, 120), RGB(255, 180, 60), RGB(255, 70, 50)
  local function L(en, cn) return zh and cn or en end
  -- 七格（照原模型屏上的版面：左边一列 FLIR、SGF，中间 PWR、指示、CEU，右边 CITV、FCEU、CCHA）
  local cells = {
    FLIR = { 0.03, 0.06, 0.24, 0.42 }, PWR = { 0.30, 0.06, 0.18, 0.18 }, IND = { 0.30, 0.28, 0.18, 0.20 }, CITV = { 0.52, 0.10, 0.45, 0.28 },
    SGF = { 0.03, 0.52, 0.24, 0.42 }, CEU = { 0.30, 0.52, 0.18, 0.42 }, FCEU = { 0.52, 0.42, 0.45, 0.26 }, CCHA = { 0.52, 0.70, 0.45, 0.24 },
  }
  local out = {}
  for name, c in pairs(cells) do
    local f = F(R, W * c[1], H * c[2], W * c[3], H * c[4], RGB(10, 16, 28), 0, 2)
    Box(f, 0, 0, W * c[3], H * c[4], 1.5, LINE, 3)
    local t = Tx(f, name == "IND" and "" or name, 4, 2, W * c[3] - 8, 12, 11, LINE, nil, FONTB, 4)
    local v = Tx(f, "", 4, H * c[4] - 18, W * c[3] - 8, 14, 11, GRN, nil, FONTB, 4)
    out[name] = { f = f, t = t, v = v }
  end
  local bar = F(out.IND.f, W * 0.03, H * 0.07, W * 0.12, 3, AMB, 0, 5)
  local clock = Tx(R, "", W * 0.52, H * 0.015, W * 0.45, 10, 9, LINE, Enum.TextXAlignment.Right, FONT, 3)
  return function(d)
    local hp = d.hp or 1
    local off = d.engineOff
    local function set(name, txt, col)
      out[name].v.Text, out[name].v.TextColor3 = txt, col
    end
    set("PWR", off and L("BATT", "电瓶") or "GO", off and AMB or GRN)
    set("FCEU", hp < 0.3 and "NO-GO" or "GO", hp < 0.3 and RED or GRN)
    set("CEU", "GO", GRN)
    set("SGF", hp < 0.5 and L("DEGR", "降级") or "GO", hp < 0.5 and AMB or GRN)
    set("CCHA", "GO", GRN)
    local th = d.sightMode == 3 or d.sightMode == 4
    set("FLIR", th and ((d.sightMode == 4) and "BLK" or "WHT") or L("STBY", "待机"), th and GRN or AMB)
    set("CITV", string.format("%03d", math.floor(((d.ty or 0) % 360) / 360 * 6400 / 10)), GRN)
    bar.BackgroundColor3 = d.ready and GRN or AMB
    local t = d.clock or 0
    clock.Text = string.format("%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60)
  end
end

-- 车长独立热像仪（99A 车长周视镜；以前 M1A2 也用这一版）：手动扫描跟着车长的视线、自动扫描扇区、随炮、看主瞄准镜画面；指示键让炮塔转过去（猎-歼）
P.citvClassic = function(s, env, zh)
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
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or ((d.zoomTxt == "10X") and 7 or 20), pal = (st.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
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

-- M1A2 SEPv2 车长显示单元的上屏：独立热像仪 CITV（用户 11-23 发来钢铁猛兽截图：「严格按照这个图，上面是一块 CITV」「两个屏幕中间的横排按钮是对应上面的屏幕的」）：
--   绿色热像铺满整块屏（白热：热的亮；黑热反过来），右上角倍率（宽视场 3X、窄视场 13X），中间四个角的框（截图里的位置），
--   下面一块黑底：↓ / ↑（热像仪看得比炮低 / 高）、方框里的弹种字母（K 穿甲、H 破甲、M 多用途、C 霰弹）、距离（10 秒内测过距用测的，没测按这种弹的战斗瞄准距离，穿甲弹 1200），
--   右下角小图：车头朝上，炮（实线）和热像仪视场（开口）的方向；左上角小字：扫描方式
--   键：两屏之间一排 SYM、DESIG、WHT / BLK、WFOV / NFOV、MAN / AUTO、GUN LOS / GPS LOS；左边一列 BRT+、BRT-、SCAN L、SCAN R（自动扫描扇区的左右边：按下时热像仪指的方向）、STOW（收回朝正前）
--   s.ledOn(k)：键角上的绿灯（选中的亮）和右边灯条（_PWR 电源、_SCAN 自动扫描、_DES 刚指示过）
local AMMO_LETTER = { SABOT = "K", HEAT = "H", MPAT = "M", CAN = "C" }
local BALM = nil
P.citv = function(s, env, zh)
  if zh then return P.citvClassic(s, env, zh) end
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th = Screens.thermal(R, W, H, { cols = 36 })
  local G = RGB(206, 255, 206)
  local GT = RGB(72, 236, 104)
  local sym = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 6)
  local bx0, bx1, by0, by1 = W * 0.34, W * 0.665, H * 0.45, H * 0.69
  local aw, ah = W * 0.04, H * 0.05
  for _, c in ipairs({ { bx0, by0, 1, 1 }, { bx1, by0, -1, 1 }, { bx0, by1, 1, -1 }, { bx1, by1, -1, -1 } }) do
    Ln(sym, c[1], c[2], c[1] + c[3] * aw, c[2], 1.5, G, 7)
    Ln(sym, c[1], c[2], c[1], c[2] + c[4] * ah, 1.5, G, 7)
  end
  local mag = Tx(sym, "3X", W * 0.78, H * 0.09, W * 0.19, H * 0.09, 15, GT, Enum.TextXAlignment.Right, Enum.Font.BuilderSansExtraBold, 8)
  local modeT = Tx(sym, "", W * 0.03, H * 0.04, W * 0.5, H * 0.07, 9, GT, nil, FONTB, 8)
  -- 下面黑底的数据框：箭头、弹种、距离
  local dw, dh = W * 0.26, H * 0.11
  local dbox = F(sym, W * 0.29, H * 0.85, dw, dh, RGB(0, 0, 0), 0, 7)
  local _, aS = Ln(dbox, 0, 0, 1, 1, 1.5, G, 8)
  local _, aL = Ln(dbox, 0, 0, 1, 1, 1.5, G, 8)
  local _, aR = Ln(dbox, 0, 0, 1, 1, 1.5, G, 8)
  local amB = F(dbox, dw * 0.2, dh * 0.16, dh * 0.68, dh * 0.68, RGB(0, 0, 0), 1, 8)
  do
    local st0 = Instance.new("UIStroke")
    st0.Color, st0.Thickness = G, 1.2
    st0.Parent = amB
  end
  local amT = Tx(amB, "K", 0, 0, dh * 0.68, dh * 0.68, 11, G, Enum.TextXAlignment.Center, FONTB, 9)
  local rngT = Tx(dbox, "", dw * 0.45, dh * 0.12, dw * 0.5, dh * 0.8, 11, G, Enum.TextXAlignment.Right, FONT, 9)
  -- 右下角：车体方框（车头朝上）、炮、热像仪视场
  local iw, ih = W * 0.085, H * 0.135
  local ibox = F(sym, W * 0.895, H * 0.825, iw, ih, RGB(0, 0, 0), 0, 7)
  local hullF = F(ibox, iw * 0.3, ih * 0.22, iw * 0.4, ih * 0.66, RGB(0, 0, 0), 1, 8)
  do
    local st0 = Instance.new("UIStroke")
    st0.Color, st0.Thickness = G, 1.2
    st0.Parent = hullF
  end
  local icx, icy = iw * 0.5, ih * 0.55
  local _, gunL = Ln(ibox, icx, icy, icx, icy - 1, 1.5, G, 9)
  local _, cvL = Ln(ibox, icx, icy, icx, icy - 1, 1, GT, 9)
  local _, cvR = Ln(ibox, icx, icy, icx, icy - 1, 1, GT, 9)
  local flash = Tx(R, "", 0, H * 0.24, W, 18, 13, RGB(255, 214, 96), Enum.TextXAlignment.Center, FONTB, 9)
  local dim = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 30)
  local st = { pol = "WHT", nfov = false, sym = true, fT = 0, brt = 0, rel = 0, mode = "MAN", desT = nil, wf = 1, nf = 1 }
  local MODE = { MAN = "MAN SCAN", AUTO = "AUTO SCAN", ["GUN LOS"] = "GUN LOS", ["GPS LOS"] = "GPS LOS", STOW = "STOW" }
  -- 视场（SEPv2 的 CITV 是第二代前视红外：宽视场 3 / 6 倍，窄视场 13 / 25 / 50 倍——同一个键再按一下换下一档）
  local WF, NF = { 23.3, 11.7 }, { 5.4, 2.8, 1.4 }
  s.onKey = function(k, act)
    k = canon(k)
    if k == "WHT" or k == "BLK" then st.pol = k
    elseif k == "WFOV" then
      if not st.nfov then st.wf = st.wf % #WF + 1 end
      st.nfov = false
      act.citvFov(WF[st.wf])
    elseif k == "NFOV" then
      if st.nfov then st.nf = st.nf % #NF + 1 end
      st.nfov = true
      act.citvFov(NF[st.nf])
    elseif k == "SYM" then st.sym = not st.sym
    elseif k == "BRT+" then st.brt = math.max(0, st.brt - 0.15)
    elseif k == "BRT-" then st.brt = math.min(0.75, st.brt + 0.15)
    elseif k == "SCAN L" or k == "SCAN R" then
      if act.citvSector then act.citvSector((k == "SCAN L") and 1 or 2, st.rel) end
      flash.Text = string.format("%s  %+d", (k == "SCAN L") and "SCAN LEFT LIMIT" or "SCAN RIGHT LIMIT", math.floor(st.rel + 0.5))
      st.fT = os.clock()
    elseif MODE[k] then act.citvMode(k) st.mode = k
    elseif k == "DESIG" then
      act.designate()
      flash.Text = "DESIGNATE  -  TURRET SLEWING"
      st.fT, st.desT = os.clock(), os.clock()
    end
  end
  s.ledOn = function(k)
    if k == "WHT" or k == "BLK" then return st.pol == k end
    if k == "WFOV" then return not st.nfov end
    if k == "NFOV" then return st.nfov end
    if MODE[k] then return st.mode == k end
    if k == "SYM" then return st.sym end
    if k == "DESIG" or k == "_DES" then return st.desT ~= nil and os.clock() - st.desT < 3 and math.floor(os.clock() * 4) % 2 == 0 end
    if k == "_SCAN" then return st.mode == "AUTO" end
    return k == "_PWR"
  end
  return function(d)
    st.mode = d.citvMode or st.mode
    st.rel = d.citvRel or st.rel
    local pal = (st.pol == "BLK") and PAL.GRNB or PAL.GRN
    if st.mode == "GPS LOS" and d.gunEye then
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or ((d.zoomTxt == "10X") and 7 or 20), pal = pal, ents = d.ents, Map = env.Map, range = 4000 })
    elseif d.citvEye then
      th.render({ eye = d.citvEye, f = d.citvF, r = d.citvR, u = d.citvU, hfov = d.citvFov or 22, pal = pal, ents = d.ents, Map = env.Map, range = 4000 })
    end
    sym.Visible = st.sym
    dim.BackgroundTransparency = 1 - st.brt
    mag.Text = string.format("%dX", math.floor(70 / (d.citvFov or 22) + 0.5))
    modeT.Text = MODE[st.mode] or ""
    -- 箭头：热像仪比炮低 → 朝下，高 → 朝上
    local de = 0
    if d.citvF and d.gunF then de = math.deg(math.asin(clamp(d.citvF.Y, -1, 1)) - math.asin(clamp(d.gunF.Y, -1, 1))) end
    local ax, y0, y1 = dw * 0.09, dh * 0.18, dh * 0.82
    local tip = (de > 0.5) and y0 or y1
    local sg = (de > 0.5) and 1 or -1
    aS(ax, y0, ax, y1)
    aL(ax, tip, ax - dh * 0.16, tip + sg * dh * 0.22)
    aR(ax, tip, ax + dh * 0.16, tip + sg * dh * 0.22)
    -- 弹种、距离（火控 Drive.lua 的 st.fcs）
    if BALM == nil then
      local ok, m = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Ballistics", 2)) end)
      BALM = ok and m or false
    end
    local a = BALM and d.wid and BALM.ammo(d.wid, d.fcsAm)
    amT.Text = a and (AMMO_LETTER[a.sym] or string.sub(a.sym, 1, 1)) or "-"
    -- 车长热像仪自己的激光测距（SEPv2：握把上的按钮，测完把那一片看得见的敌人报告给全队）10 秒内用它；不然炮长测的；都没有是战斗瞄准距离
    local r
    if d.citvRT and os.clock() - d.citvRT < 10 then r = d.citvRange
    else r = (d.fcsR and d.fcsLaseT and os.clock() - d.fcsLaseT < 10) and d.fcsR or (a and a.bs) end
    rngT.Text = r and string.format("%d", math.floor(r)) or "----"
    -- 右下角：炮、热像仪相对车头的方向
    local L0 = ih * 0.42
    local tg = math.rad(d.ty or 0)
    gunL(icx, icy, icx + math.sin(tg) * L0, icy - math.cos(tg) * L0)
    local cv = math.rad((d.ty or 0) + (d.citvRel or 0))
    local half = math.rad(math.clamp((d.citvFov or 22) / 2, 1.5, 20))
    cvL(icx, icy, icx + math.sin(cv - half) * L0 * 0.9, icy - math.cos(cv - half) * L0 * 0.9)
    cvR(icx, icy, icx + math.sin(cv + half) * L0 * 0.9, icy - math.cos(cv + half) * L0 * 0.9)
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
    if d.rwsNoGun then   -- 坦克不带机枪：只剩摄像头（看、测距），没有武器、没有弹数
      t.Text = string.format("CROWS  CAM  NO WPN  %s%s", st.therm and "TI" or "DAY", st.slave and "  SLAVE" or "")
      am.Text = (st.lase and os.clock() - st.lase < 3 and d.range) and string.format("%04d", math.floor(d.range)) or "---"
      return
    end
    t.Text = string.format("CROWS  M2  %s  %s%s", st.armed and "ARMED" or "SAFE", st.therm and "TI" or "DAY", st.slave and "  SLAVE" or "")
    am.Text = (st.lase and os.clock() - st.lase < 3 and d.range) and string.format("%04d", math.floor(d.range)) or tostring(d.rwsAmmo or 400)
  end
end

-- 指挥地图（M1A2 的战术显示 / JBC-P；99A 的综合显示终端）：地图 / 消息 / 本车状态 / 导航 / 坐标页，放大缩小、叠加层、亮度
--   M1A2 SEPv2 显示单元的下屏（s.opt.paper，用户 11-23 发来钢铁猛兽截图）：白底地图、水面淡蓝、红色双线道路（Map.ROADS），
--   左边 VEH SYS（本车状态）、C3（消息）两个键，左下四个方向键挪地图（MAP 键回到本车），下边 8 个橙色横杠键（功能名写在屏幕下沿 s.opt.dash），
--   右边字母数字键盘：打偶数位数字（4 / 6 / 8 / 10 位，前一半东、后一半北，同坐标页的格式）按 ENT 设目标点（地图上一个三角，导航页指过去）；
--   LTR 切字母（同一个键连按换字母，> 结束这个字母）、打的是字按 ENT 当消息发出去（消息页看得到）；CLR 删一个字，没字了再按清掉目标点
local PADLET = { ["1"] = "ABC", ["2"] = "DEF", ["3"] = "GHI", ["4"] = "JKL", ["5"] = "MNO", ["6"] = "PQR", ["7"] = "STU", ["8"] = "VWX", ["9"] = "YZ", ["0"] = " " }
P.cid = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local function L(en, cn) return zh and cn or en end
  local paper = s.opt and s.opt.paper
  local BAR = paper and 14 or 18
  local VH = H - BAR * 2
  local WATER = paper and RGB(184, 210, 232) or RGB(18, 34, 52)
  local TXT = paper and RGB(26, 30, 36) or RGB(200, 220, 240)
  local BARC = paper and RGB(212, 212, 204) or RGB(10, 14, 20)
  R.BackgroundColor3 = WATER
  local view = F(R, 0, BAR, W, VH, WATER, 0, 1)
  view.ClipsDescendants = true
  local land = F(view, 0, 0, W, H, RGB(0, 0, 0), 1, 2)
  local top = F(R, 0, 0, W, BAR, BARC, 0, 5)
  local clock = Tx(top, "", 4, 0, W * 0.45, BAR, paper and 10 or 11, TXT, nil, FONT, 6)
  local grid = Tx(top, "", W * 0.4, 0, W * 0.6 - 4, BAR, paper and 10 or 11, TXT, Enum.TextXAlignment.Right, FONT, 6)
  local bot = F(R, 0, H - BAR, W, BAR, BARC, 0, 5)
  local scaleT = Tx(bot, "", 4, 0, W - 8, BAR, 10, paper and TXT or RGB(160, 200, 230), nil, FONTB, 6)
  if paper and s.opt.dash then   -- 下边橙色横杠键的功能名（键在屏幕正下方）
    scaleT.Visible = false
    for _, k in ipairs(s.opt.dash) do Tx(bot, k[1], clamp(W * k[2] - 18, 0, W - 36), 0, 36, BAR, 8, RGB(16, 16, 16), Enum.TextXAlignment.Center, FONTB, 6) end
  end
  local dim = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 30)
  -- 键盘打的字、提示（MAP 页左下角、正上方）
  local entF = F(R, 4, H - BAR - 17, W * 0.62, 15, RGB(255, 255, 255), 0.08, 12)
  local entT = Tx(entF, "", 4, 0, W * 0.62 - 8, 15, 10, RGB(0, 0, 0), nil, FONT, 13)
  local noteT = Tx(R, "", 0, BAR + 2, W, 14, 10, RGB(200, 40, 30), Enum.TextXAlignment.Center, FONTB, 13)
  local S = { cx = nil, cz = nil, span = (env.zooms or { 0, 3200 })[2], cell = 64, job = nil, w = 0, h = 0 }   -- cell：地图色块（用户 11-23 显示屏清晰度太低：每屏高 66 / 72 格，原来 44 / 50）
  S.cell = S.span / (paper and 66 or 72)
  local scale = VH / S.span
  local function landCol(h)
    if h < 0.3 then return nil end   -- 水：底色
    if paper then   -- 纸地图：几乎白，越高越灰、稍带绿（截图那种白底地图）
      if h < 6 then return RGB(240, 236, 222) end
      if h < 40 then return RGB(238, 240, 232) end
      if h < 110 then return RGB(228, 234, 220) end
      if h < 220 then return RGB(226, 224, 214) end
      return RGB(216, 212, 204)
    end
    if h < 6 then return RGB(196, 186, 140) end
    if h < 40 then return RGB(120, 150, 96) end
    if h < 110 then return RGB(104, 128, 84) end
    if h < 220 then return RGB(132, 122, 96) end
    return RGB(160, 152, 136)
  end
  -- 重画底图的范围：纸地图横向按屏幕宽高比放宽、再各留半屏（挪地图、开车时边上不露底色）
  local function rebuild(cx, cz)
    local sw = S.span * (paper and math.max(1, W / VH) * 1.5 or 1)
    local sh = S.span * (paper and 1.5 or 1)
    S.job = { cx = cx, cz = cz, nx = math.floor(sw / S.cell), nz = math.floor(sh / S.cell), w = sw, h = sh, j = 0, frames = {} }
  end
  -- 道路：红色双线（纸地图）；每段至少 7 像素，路线上的点太密就跳着连
  local function drawRoads()
    local RD = paper and env.Map and env.Map.ROADS
    if not RD then return end
    local x0, z0 = S.cx - S.w / 2, S.cz - S.h / 2
    local minL = 7 / scale
    local function seg(ax, az, bx, bz)
      local inA = ax > x0 and ax < x0 + S.w and az > z0 and az < z0 + S.h
      local inB = bx > x0 and bx < x0 + S.w and bz > z0 and bz < z0 + S.h
      if not (inA or inB) then return end
      local px0, pz0, px1, pz1 = (ax - x0) * scale, (az - z0) * scale, (bx - x0) * scale, (bz - z0) * scale
      Ln(land, px0, pz0, px1, pz1, 3, RGB(204, 72, 70), 3)
      Ln(land, px0, pz0, px1, pz1, 1, RGB(248, 226, 222), 4)
    end
    for _, r in ipairs(RD) do
      local xs, zs = r.x, r.z
      local lx, lz = xs[1], zs[1]
      for i = 2, #xs do
        local x, z = xs[i], zs[i]
        if i == #xs or (x - lx) ^ 2 + (z - lz) ^ 2 >= minL * minL then
          seg(lx, lz, x, z)
          lx, lz = x, z
        end
      end
    end
  end
  local function stepJob()
    local J = S.job
    local Map = env.Map
    local calls = 0
    while J.j < J.nz and calls < 700 do
      local j = J.j
      local z = J.cz - J.h / 2 + (j + 0.5) * S.cell
      local run, runCol = nil, nil
      for i = 0, J.nx do
        local col = nil
        if i < J.nx then
          col = landCol(Map.height(J.cx - J.w / 2 + (i + 0.5) * S.cell, z))
          calls += 1
        end
        if col ~= runCol then
          if runCol and run then table.insert(J.frames, { run, j, i - run, runCol }) end
          run, runCol = i, col
        end
      end
      J.j += 1
    end
    if J.j < J.nz then return false end
    for _, c in ipairs(land:GetChildren()) do c:Destroy() end
    local px = S.cell * scale
    for _, fr in ipairs(J.frames) do F(land, fr[1] * px, fr[2] * px, fr[3] * px + 1, px + 1, fr[4], 0, 2) end
    S.cx, S.cz, S.w, S.h = J.cx, J.cz, J.w, J.h
    S.scale = scale
    drawRoads()
    return true
  end
  local gridF = F(view, 0, 0, W, H, RGB(0, 0, 0), 1, 3)
  local objs = {}
  local units = {}   -- 军标（Sym）
  local function obj(i)
    local o = objs[i]
    if not o then
      local f = F(view, 0, 0, 10, 10, RGB(80, 160, 255), 0, 6)
      local t = Tx(f, "", -20, -14, 50, 12, 10, paper and RGB(20, 20, 20) or RGB(255, 255, 255), Enum.TextXAlignment.Center, FONTB, 7)
      o = { f = f, t = t }
      objs[i] = o
    end
    return o
  end
  local me = F(view, 0, 0, 12, 12, RGB(80, 170, 255), 0, 8)
  local meC = Instance.new("UICorner")
  meC.CornerRadius = UDim.new(0.5, 0)
  meC.Parent = me
  local _, hdgSet = Ln(view, 0, 0, 0, 0, 2, paper and RGB(20, 70, 200) or RGB(80, 170, 255), 8)
  local _, gunSet = Ln(view, 0, 0, 0, 0, 2, paper and RGB(220, 120, 0) or RGB(255, 200, 60), 8)
  -- 目标点（键盘打坐标设的）：一个三角加中心点
  local wpL = {}
  for i = 1, 3 do local f, set = Ln(view, 0, 0, 1, 1, 2, RGB(210, 40, 30), 9) wpL[i] = { f = f, set = set } end
  local wpDot = F(view, 0, 0, 4, 4, RGB(210, 40, 30), 0, 9)
  local gl = {}
  local GLC, GLT = paper and RGB(120, 120, 120) or RGB(255, 255, 255), paper and 0.55 or 0.82
  for i = 1, 8 do gl[i] = F(gridF, 0, 0, 1, H, GLC, GLT, 3) end
  for i = 9, 16 do gl[i] = F(gridF, 0, 0, W, 1, GLC, GLT, 3) end
  local pages = { MSG = textPage(s, L("MESSAGES", "消息"), 7, RGB(200, 225, 245)), STAT = textPage(s, L("VEHICLE STATUS", "本车状态"), 7, RGB(200, 225, 245)),
    NAV = textPage(s, L("NAVIGATION", "导航"), 4, RGB(200, 225, 245)), POS = textPage(s, L("POSITION", "坐标"), 5, RGB(200, 225, 245)) }
  local navArrow = arrow(pages.NAV.f, W * 0.75, H * 0.6, math.min(W, H) * 0.22, RGB(255, 200, 60))
  local ZOOMS = env.zooms or { 1600, 3200, 6400 }
  local st = { page = "MAP", z = 2, ovly = true, brt = 0, pan = { 0, 0 }, entry = "", ltr = false, tapK = nil, tapN = 0, tapT = 0, wp = nil, sent = {}, note = nil, noteT = 0, newMsg = false }
  local function note(t) st.note, st.noteT = t, os.clock() end
  -- 坐标页的格式：东 = (X + 20000) / 2.8 米、北 = (20000 − Z) / 2.8 米，各 5 位；打 2n 位数字 = 前 n 位东、后 n 位北（精度 10^(5−n) 米，取格子中心）
  local function gridToWorld(dg)
    local n = #dg
    if n < 4 or n > 10 or n % 2 == 1 then return nil end
    local h = n / 2
    local unit = 10 ^ (5 - h)
    local e = tonumber(string.sub(dg, 1, h)) * unit + unit / 2
    local nn = tonumber(string.sub(dg, h + 1)) * unit + unit / 2
    return e * 2.8 - 20000, 20000 - nn * 2.8
  end
  s.onKey = function(k)
    k = canon(k)
    if k == "MAP" then st.page = "MAP" st.pan = { 0, 0 }   -- 地图键：回到地图页、以本车为中心
    elseif k == "MSG" or k == "C3" then st.page = "MSG"
    elseif k == "STAT" or k == "VEH SYS" then st.page = "STAT"
    elseif k == "NAV" or k == "POS" then st.page = k
    elseif k == "ZOOM+" then st.z = math.max(1, st.z - 1) elseif k == "ZOOM-" then st.z = math.min(3, st.z + 1)
    elseif k == "OVLY" then st.ovly = not st.ovly
    elseif k == "BRT+" then st.brt = math.max(0, st.brt - 0.15) elseif k == "BRT-" then st.brt = math.min(0.75, st.brt + 0.15)
    elseif k == "UP" or k == "DOWN" or k == "LEFT" or k == "RIGHT" then   -- 地图上北下南：往北挪 = 中心往 −Z
      st.page = "MAP"
      local q = S.span * 0.25
      if k == "UP" then st.pan[2] -= q elseif k == "DOWN" then st.pan[2] += q elseif k == "LEFT" then st.pan[1] -= q else st.pan[1] += q end
    elseif PADLET[k] then
      if st.ltr then   -- 字母：同一个键 1.5 秒内连按换下一个字母
        local lt = PADLET[k]
        if st.tapK == k and os.clock() - st.tapT < 1.5 then
          st.tapN = st.tapN % #lt + 1
          st.entry = string.sub(st.entry, 1, -2) .. string.sub(lt, st.tapN, st.tapN)
        else
          st.tapN = 1
          st.entry = st.entry .. string.sub(lt, 1, 1)
        end
        st.tapK, st.tapT = k, os.clock()
      else
        st.entry = st.entry .. k
      end
      if #st.entry > 24 then st.entry = string.sub(st.entry, 1, 24) end
    elseif k == "." or k == "-" then st.entry = st.entry .. k st.tapK = nil
    elseif k == "NEXT" then
      if st.tapK then st.tapK = nil else st.entry = st.entry .. " " end
    elseif k == "LTR" then st.ltr = not st.ltr st.tapK = nil
    elseif k == "CLR" then
      st.tapK = nil
      if #st.entry > 0 then st.entry = string.sub(st.entry, 1, -2)
      elseif st.wp then st.wp = nil note(L("WAYPOINT CLEARED", "目标点已清除")) end
    elseif k == "ENT" then
      local e = st.entry
      st.entry, st.tapK = "", nil
      local dg = string.gsub(e, "[%s%.%-]", "")
      local x, z = nil, nil
      if string.match(dg, "^%d+$") then x, z = gridToWorld(dg) end
      if x then
        st.wp = { x = x, z = z, txt = dg }
        st.page = "MAP"
        note(string.format(L("WAYPOINT  %s", "目标点  %s"), dg))
      elseif string.match(dg, "^%d+$") then
        note(L("GRID NEEDS 4/6/8/10 DIGITS", "坐标要 4 / 6 / 8 / 10 位"))
      elseif #e > 0 then
        table.insert(st.sent, 1, { t = os.clock(), txt = e })
        if #st.sent > 3 then table.remove(st.sent) end
        st.page = "MSG"
        note(L("MESSAGE SENT", "消息已发出"))
      end
    end
  end
  s.ledOn = function(k)
    if k == "_MSG" then return st.newMsg end
    if k == "LTR" then return st.ltr end
    return k == "_PWR"
  end
  s.mapState = st   -- 测试用
  return function(d)
    if not d.pos then return end
    for name, pg in pairs(pages) do pg.f.Visible = st.page == name end
    dim.BackgroundTransparency = 1 - st.brt
    local p = d.pos
    local want = ZOOMS[st.z]
    if want ~= S.span and not S.job then
      S.span, S.cx = want, nil
      S.cell = S.span / (paper and 66 or 72)
      scale = VH / S.span
    end
    local cxw, czw = p.X + st.pan[1], p.Z + st.pan[2]   -- 地图中心（挪过就不是本车）
    if not S.job and (not S.cx or math.abs(cxw - S.cx) > S.span * 0.22 or math.abs(czw - S.cz) > S.span * 0.22) then
      rebuild(math.floor(cxw / S.cell) * S.cell, math.floor(czw / S.cell) * S.cell)
    end
    if S.job and stepJob() then S.job = nil end
    local vx, vz = W / 2, VH / 2
    if S.cx then
      land.Position = UD2(0, vx - (cxw - (S.cx - S.w / 2)) * scale, 0, vz - (czw - (S.cz - S.h / 2)) * scale)
      land.Size = UD2(0, S.w * scale, 0, S.h * scale)
    end
    local g0x = math.floor((cxw - W / 2 / scale) / 1000) * 1000   -- 从屏幕左边起（纸地图横向比竖向宽）
    local g0z = math.floor((czw - S.span / 2) / 1000) * 1000
    for i = 1, 8 do
      local x = vx + (g0x + i * 1000 - cxw) * scale
      gl[i].Position = UD2(0, x, 0, 0)
      gl[i].Visible = x > 0 and x < W
    end
    for i = 9, 16 do
      local z = vz + (g0z + (i - 8) * 1000 - czw) * scale
      gl[i].Position = UD2(0, 0, 0, z)
      gl[i].Visible = z > 0 and z < VH
    end
    local mx, mz = vx + (p.X - cxw) * scale, vz + (p.Z - czw) * scale
    me.Position = UD2(0, mx - 6, 0, mz - 6)
    me.Visible = mx > -6 and mx < W + 6 and mz > -6 and mz < VH + 6
    local h = math.rad(d.hdg or 0)
    hdgSet(mx, mz, mx + math.sin(h) * 22, mz - math.cos(h) * 22)
    local tg = math.rad((d.hdg or 0) + (d.ty or 0))
    gunSet(mx, mz, mx + math.sin(tg) * 34, mz - math.cos(tg) * 34)
    -- 目标点
    local wp = st.wp
    for _, q in ipairs(wpL) do q.f.Visible = wp ~= nil end
    wpDot.Visible = wp ~= nil
    if wp then
      local x, z = vx + (wp.x - cxw) * scale, vz + (wp.z - czw) * scale
      local r = 9
      local P3 = { { x, z - r }, { x - r * 0.87, z + r * 0.5 }, { x + r * 0.87, z + r * 0.5 } }
      for i = 1, 3 do local a, b2 = P3[i], P3[i % 3 + 1] wpL[i].set(a[1], a[2], b2[1], b2[2]) end
      wpDot.Position = UD2(0, x - 2, 0, z - 2)
    end
    local n, nu = 0, 0
    local nE = 0
    for _, e in ipairs(d.ents or {}) do if e.seen and e.team ~= d.team then nE += 1 end end
    st.newMsg = nE > 0
    if st.ovly then
      for _, pt in ipairs(d.points or {}) do
        n += 1
        local o = obj(n)
        local x, z = vx + (pt.x - cxw) * scale, vz + (pt.z - czw) * scale
        o.f.Visible = x > -10 and x < W + 10 and z > -10 and z < VH + 10
        o.f.Position = UD2(0, x - 8, 0, z - 8)
        o.f.Size = UD2(0, 16, 0, 16)
        o.f.BackgroundColor3 = (pt.owner == d.team) and RGB(70, 140, 255) or ((pt.owner == nil) and RGB(200, 200, 200) or RGB(230, 70, 60))
        o.f.BackgroundTransparency = 0.25
        o.f.Rotation = 45
        o.t.Text = pt.id
        o.t.Rotation = -45
      end
      -- 友军、看得见的敌人：按兵种画军标（坦克、装甲车、步兵、炮兵、防空、直升机、飞机、军舰、工事）
      for _, e in ipairs(d.ents or {}) do
        local friend = e.team == d.team
        if friend or e.seen then
          local x, z = vx + (e.pos.X - cxw) * scale, vz + (e.pos.Z - czw) * scale
          if x > -12 and x < W + 12 and z > -12 and z < VH + 12 then
            nu += 1
            local u = units[nu]
            if not u then u = Sym(view, 9) units[nu] = u end
            local typ = e.typ or ((e.kind == "air") and "jet" or ((e.kind == "inf") and "inf" or "apc"))
            u.set(x, z, typ, not friend, (typ == "inf") and 15 or 19)
          end
        end
      end
    end
    for i = n + 1, #objs do objs[i].f.Visible = false end
    for i = nu + 1, #units do units[i].f.Visible = false end
    local t = d.clock or 0
    clock.Text = string.format("%02d:%02d:%02dZ  %s", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, math.floor(t) % 60, d.callsign or (zh and "01 号车" or "A-12"))
    local gx, gz = math.floor((p.X + 20000) / 2.8) % 100000, math.floor((20000 - p.Z) / 2.8) % 100000
    grid.Text = string.format("52S  %05d %05d", gx, gz)
    scaleT.Text = string.format(L("SCALE 1:%dK   %s", "比例 1:%dK   %s"), math.floor(S.span / 2.8 / 100), st.ovly and L("OVERLAY ON", "标绘 开") or L("OVERLAY OFF", "标绘 关"))
    entF.Visible = #st.entry > 0 or st.ltr
    entT.Text = (st.ltr and "LTR> " or "> ") .. st.entry .. ((math.floor(os.clock() * 2) % 2 == 0) and "_" or " ")
    noteT.Text = (st.note and os.clock() - st.noteT < 3) and st.note or ""
    if st.page == "MSG" then
      local lines = {}
      for _, m in ipairs(st.sent) do
        local tt = t - (os.clock() - m.t)
        table.insert(lines, string.format(L("%02d%02dZ  SENT: %s", "%02d%02d  已发：%s"), math.floor(tt / 3600) % 24, math.floor(tt / 60) % 60, m.txt))
      end
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
      if wp then   -- 键盘设的目标点优先
        local dist = math.sqrt((wp.x - p.X) ^ 2 + (wp.z - p.Z) ^ 2)
        local brg = math.deg(math.atan2(wp.x - p.X, -(wp.z - p.Z))) % 360
        pages.NAV.set({ string.format(L("WAYPOINT  GRID %s", "目标点  坐标 %s"), wp.txt), string.format(L("DIST  %5d M", "距离  %5d 米"), math.floor(dist / 2.8)),
          string.format(L("BRG   %03d", "方位  %03d°"), math.floor(brg)), string.format(L("HDG   %03d", "车头  %03d°"), math.floor(d.hdg or 0)) })
        navArrow(math.rad(brg - (d.hdg or 0)))
      else
        local o, dist, brg = navText(d)
        if o then
          pages.NAV.set({ string.format(L("WAYPOINT  OBJ %s", "目标点  据点 %s"), o.id), string.format(L("DIST  %5d M", "距离  %5d 米"), math.floor(dist / 2.8)),
            string.format(L("BRG   %03d", "方位  %03d°"), math.floor(brg)), string.format(L("HDG   %03d", "车头  %03d°"), math.floor(d.hdg or 0)) })
          navArrow(math.rad(brg - (d.hdg or 0)))
        else pages.NAV.set({ L("NO WAYPOINT", "没有目标点") }) end
      end
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
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or ((d.zoomTxt == "10X") and 7 or 20), pal = (d.pol == "BLK") and PAL.BLK or PAL.WHT, ents = d.ents, Map = env.Map, range = 4000 })
    end
    info.Text = string.format("热像  %s  %s", (d.pol == "BLK") and "黑热" or "白热", (d.zoomTxt == "10X") and "10倍" or "3.5倍")
    rng.Text = d.range and string.format("距离 %04d", math.floor(d.range)) or ""
  end
end

-- 布雷德利炮长的综合瞄准具显示器（IBAS；用户 11-24 发来的 M3 车内截图：目镜右下一块四周一圈方键的显示器，绿色热像、括号形分划）
--   四周的键都真起作用：上排 视场、极性、增益、电平、符号亮度；下排 昼光 / 热像、激光测距、首 / 末回波、分划亮度、自检；
--   左边 射速（高 / 低 / 单发）、武器（25 毫米炮 / 并列机枪）、武器保险；右边 战斗瞄准、稳定器、屏幕亮度
P.ibas = function(s, env)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th = Screens.thermal(R, W, H, { cols = 26 })
  local G = RGB(190, 255, 190)
  local cx, cy = W / 2, H / 2
  local bw, bh = W * 0.17, H * 0.14
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do   -- 四个直角（截图里两个括号）
    local x0, y0 = cx + c[1] * bw, cy + c[2] * bh
    F(R, math.min(x0, x0 - c[1] * bw * 0.4), y0 - 1, bw * 0.4, 2, G, 0, 6)
    F(R, x0 - 1, math.min(y0, y0 - c[2] * bh * 0.5), 2, bh * 0.5, G, 0, 6)
  end
  F(R, cx - 2, cy - 2, 4, 4, G, 0, 6)
  local top = Tx(R, "", 6, 4, W - 12, 14, 12, G, nil, FONTB, 8)
  local rng = Tx(R, "", W - 112, 4, 106, 14, 12, G, Enum.TextXAlignment.Right, FONTB, 8)
  local info = Tx(R, "", 6, H - 18, W - 12, 14, 12, G, nil, FONTB, 8)
  local msg = Tx(R, "", 6, H - 34, W - 12, 14, 12, G, nil, FONTB, 8)
  local dim = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 9)
  local st = { brt = 0, msgT = 0 }
  local function say(m) msg.Text, st.msgT = m, os.clock() end
  s.onKey = function(k, act)
    local d = st.d or {}
    local sy = (act.sync and act.sync()) or {}
    if k == "FOV" then act.zoom() say("FIELD OF VIEW")
    elseif k == "POL" then act.polarity() say("POLARITY")
    elseif k == "GAIN" and act.gain then act.gain(((d.thGain or 2) + 1) % 5) say("GAIN " .. (((d.thGain or 2) + 1) % 5 - 2))
    elseif k == "LVL" and act.level then act.level(((d.thLevel or 2) + 1) % 5) say("LEVEL " .. (((d.thLevel or 2) + 1) % 5 - 2))
    elseif k == "SYM" and act.symb then act.symb(((d.symLvl or 0) + 1) % 4) say("SYMBOLOGY")
    elseif k == "TIS" and act.thermalSet then act.thermalSet((sy.vis == 1) and 0 or 1) say((sy.vis == 1) and "DAY TV" or "FLIR")
    elseif k == "LRF" and act.lase then act.lase()
    elseif k == "F/L" and act.lrfToggle then act.lrfToggle() say("LRF RETURN")
    elseif k == "RET" and act.reticle then act.reticle(((d.retLvl or 0) + 1) % 4) say("RETICLE")
    elseif k == "TEST" and act.bit then act.bit() say("BIT")
    elseif k == "ROF" and act.rof then act.rof(((sy.rof or 0) + 1) % 3) say("RATE " .. ({ "HI", "LO", "SS" })[((sy.rof or 0) + 1) % 3 + 1])
    elseif k == "WPN" and act.weapon then act.weapon(((sy.wpn or 0) + 1) % 2) say((((sy.wpn or 0) + 1) % 2 == 0) and "25MM" or "COAX")
    elseif k == "ARM" and act.armGun then act.armGun((sy.armg == 1) and 0 or 1) say((sy.armg == 1) and "ARMED" or "SAFE")
    elseif k == "BSGT" and act.battlesight then act.battlesight() say("BATTLESIGHT")
    elseif k == "STAB" and act.stab then act.stab((sy.stab == 1) and 0 or 1) say((sy.stab == 1) and "STAB ON" or "STAB OFF")
    elseif k == "BRT" then st.brt = (st.brt + 1) % 3 end
  end
  return function(d)
    st.d = d
    if d.gunEye then
      th.render({ eye = d.gunEye, f = d.gunF, r = d.gunR, u = d.gunU, hfov = d.zoomFov or 17, pal = (d.pol == "BLK") and PAL.GRNB or PAL.GRN, ents = d.ents, Map = env.Map, range = 4000 })
    end
    top.Text = string.format("IBAS  FLIR  %s  %s", (d.pol == "BLK") and "BLK" or "WHT", d.zoomTxt or "")
    rng.Text = d.range and string.format("%04d M", math.floor(d.range)) or "---- M"
    info.Text = string.format("%s  %s  %s  %s", d.rof or "HI", (d.wpn == 2) and "COAX" or "25MM", d.armSafe and "SAFE" or "ARMED", (d.lrf == "FIRST") and "FIRST" or "LAST")
    if os.clock() - st.msgT > 2 then msg.Text = "" end
    dim.BackgroundTransparency = ({ 1, 0.35, 0.6 })[st.brt + 1]
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

-- 战术态势显示（F-22 的 8 × 8 英寸主显示器、F-35 全景屏左边的大门户，docs/cockpit_research.md）：俯视图，自己在下方、机头朝上；
--   照 F-22 资料里的符号：敌机红三角、友机绿圆、地面 / 海上目标红菱形（地空导弹的五边形没有数据，不画），锁定的加黄框；
--   距离弧三道（RNG 键 40 / 80 / 160 公里），据点按真实位置画成带字母的小方块，上面方框里是航向
P.tsd = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local cx, cy = W / 2, H * 0.84
  local RP = H * 0.74   -- 满量程的像素半径
  local LINE, DIM = RGB(76, 104, 116), RGB(40, 56, 64)
  local st = { rng = 80 }
  s.onKey = function(k) if k == "RNG" then st.rng = (st.rng == 80) and 160 or ((st.rng == 160) and 40 or 80) end end
  for i = 1, 3 do Ring(R, cx, cy, RP * i / 3, 1, LINE, 2) end
  for _, a in ipairs({ -60, -30, 30, 60 }) do
    local ra = math.rad(a)
    Ln(R, cx, cy, cx + math.sin(ra) * RP * 1.1, cy - math.cos(ra) * RP * 1.1, 1, DIM, 2)
  end
  local lbl = {}
  for i = 1, 3 do lbl[i] = Tx(R, "", cx + 4, cy - RP * i / 3 - 13, 70, 12, 10, LINE, nil, FONT, 3) end
  local WH = RGB(235, 235, 235)   -- 自己：白色小飞机
  F(R, cx - 1, cy - 9, 3, 18, WH, 0, 6)
  F(R, cx - 10, cy - 2, 21, 3, WH, 0, 6)
  F(R, cx - 4, cy + 7, 9, 2, WH, 0, 6)
  local hdgT = Tx(R, "", W / 2 - 30, 2, 60, 15, 12, WH, Enum.TextXAlignment.Center, FONTB, 6)
  Box(R, W / 2 - 24, 2, 48, 15, 1, RGB(200, 200, 200), 6)
  local rngT = Tx(R, "", 4, H - 15, W * 0.5, 13, 10, LINE, nil, FONT, 6)
  local cntT = Tx(R, "", W * 0.5, H - 15, W * 0.5 - 4, 13, 10, LINE, Enum.TextXAlignment.Right, FONT, 6)
  local pool, ppool, gpool = {}, {}, {}
  local lockB = Box(R, 0, 0, 18, 18, 2, RGB(255, 220, 60), 7)
  lockB.Visible = false
  local function sym(list, i, size)
    local t = list[i]
    if not t then
      t = Tx(R, "", 0, 0, size, size, size - 2, WH, Enum.TextXAlignment.Center, FONTB, 5)
      list[i] = t
    end
    t.Visible = true
    return t
  end
  local function at(az, km, rng)
    local k = km / rng
    return cx + math.sin(math.rad(az)) * k * RP, cy - math.cos(math.rad(az)) * k * RP
  end
  return function(d)
    local rng = st.rng
    local u = zh and 1 or 0.54   -- 中文机型按公里，美军按海里
    for i = 1, 3 do lbl[i].Text = tostring(math.floor(rng * u * i / 3 + 0.5)) end
    hdgT.Text = string.format("%03d", math.floor((d.hdg or 0) % 360))
    rngT.Text = zh and string.format("量程 %d 公里", rng) or string.format("RNG %d NM", math.floor(rng * u + 0.5))
    local n, nh, ng = 0, 0, 0
    lockB.Visible = false
    for _, c in ipairs(d.contacts or {}) do
      if c.km < rng then
        n += 1
        local x, y = at(c.az, c.km, rng)
        if c.kind == "air" then   -- 飞机：F-22 的符号（敌机红三角、友机绿圆）
          local t = sym(pool, n, 16)
          t.Position = UD2(0, x - 8, 0, y - 8)
          if c.friend then t.Text, t.TextColor3 = "●", RGB(90, 230, 120)
          else t.Text, t.TextColor3 = "▲", RGB(255, 70, 60) nh += 1 end
        else   -- 地面、海上目标：按兵种画军标（用户 11-22：坦克、车之类的要有不同符号）
          if pool[n] then pool[n].Visible = false end
          ng += 1
          local u = gpool[ng]
          if not u then u = Sym(R, 5) gpool[ng] = u end
          u.set(x, y, c.typ or "apc", not c.friend, 17)
          if not c.friend then nh += 1 end
        end
        if c.locked then
          lockB.Visible = true
          lockB.Position = UD2(0, x - 9, 0, y - 9)
        end
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
    for i = ng + 1, #gpool do gpool[i].f.Visible = false end
    local m = 0
    if d.pos and d.points then
      for _, p in ipairs(d.points) do
        local dx, dz = (p.x - d.pos.X) / 2.8, (p.z - d.pos.Z) / 2.8
        local km = math.sqrt(dx * dx + dz * dz) / 1000
        if km < rng then
          m += 1
          local az = math.deg(math.atan2(dx, -dz)) - (d.hdg or 0)
          local x, y = at(az, km, rng)
          local t = sym(ppool, m, 14)
          t.Text = p.id
          t.Position = UD2(0, x - 7, 0, y - 7)
          t.TextColor3 = (p.owner == d.team) and RGB(90, 230, 120) or RGB(255, 200, 80)
          if not t:FindFirstChild("Edge") then
            local e = Instance.new("UIStroke")
            e.Name = "Edge"
            e.Thickness = 1
            e.Color = RGB(150, 170, 180)
            e.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            e.Parent = t
          end
        end
      end
    end
    for i = m + 1, #ppool do ppool[i].Visible = false end
    cntT.Text = zh and string.format("目标 %d  敌 %d", n, nh) or string.format("TRK %d  HOSTILE %d", n, nh)
  end
end

-- 备份飞行显示器（F-35 的 SFD：480 × 480 像素，独立显示姿态、高度、空速、升降速度、迎角；歼-20 中间那块小屏也用它）
P.sfd = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local ball = F(R, -W, -H, W * 3, H * 3, RGB(40, 110, 200), 0, 2)
  F(ball, 0, H * 1.5, W * 3, H * 1.5, RGB(130, 84, 40), 0, 3)
  F(ball, 0, H * 1.5 - 1, W * 3, 2, RGB(255, 255, 255), 0, 4)
  for i = -2, 2 do
    if i ~= 0 then F(ball, W * 1.5 - W * 0.08, H * 1.5 - i * H * 0.12, W * 0.16, 1, RGB(255, 255, 255), 0, 4) end
  end
  local Y = RGB(255, 210, 40)
  F(R, W * 0.32, H / 2 - 1, W * 0.12, 3, Y, 0, 8)
  F(R, W * 0.56, H / 2 - 1, W * 0.12, 3, Y, 0, 8)
  F(R, W / 2 - 2, H / 2 - 2, 4, 4, Y, 0, 8)
  local function readout(x)
    F(R, x, H / 2 - 9, W * 0.25, 18, RGB(0, 0, 0), 0.15, 8)
    Box(R, x, H / 2 - 9, W * 0.25, 18, 1, RGB(230, 230, 230), 9)
    return Tx(R, "", x, H / 2 - 9, W * 0.25 - 3, 18, 12, RGB(255, 255, 255), Enum.TextXAlignment.Right, FONTB, 9)
  end
  local spd, alt = readout(2), readout(W * 0.75 - 2)
  F(R, W * 0.35, 0, W * 0.30, 15, RGB(0, 0, 0), 0.15, 8)
  local hdg = Tx(R, "", W * 0.35, 0, W * 0.30, 15, 11, RGB(255, 255, 255), Enum.TextXAlignment.Center, FONTB, 9)
  F(R, 0, H - 14, W, 14, RGB(0, 0, 0), 0.15, 8)
  local bot = Tx(R, "", 2, H - 14, W - 4, 14, 10, RGB(160, 240, 170), Enum.TextXAlignment.Center, FONT, 9)
  return function(d)
    local pitch, roll = d.pitch or 0, d.roll or 0
    local py = pitch * H * 0.12 / 10
    ball.Rotation = -roll
    ball.Position = UD2(0, -W + math.sin(math.rad(roll)) * py, 0, -H + math.cos(math.rad(roll)) * py)
    spd.Text = zh and string.format("%d", math.floor(d.kmh or 0)) or string.format("%d", math.floor(d.kt or 0))
    alt.Text = zh and string.format("%d", math.floor(d.altM or 0)) or string.format("%d", math.floor((d.altM or 0) * 3.281))
    hdg.Text = string.format("%03d", math.floor((d.hdg or 0) % 360))
    bot.Text = zh and string.format("升降 %+d  迎角 %d", math.floor(d.vs or 0), math.floor(d.aoa or 0))
      or string.format("VVI %+d  AOA %d", math.floor((d.vs or 0) * 196.85), math.floor(d.aoa or 0))
  end
end

-- 液晶的正前方控制板（歼-15T：UFC 从发光二极管点阵换成液晶，兼作专用显示器显示航姿等关键飞参；歼-16 的 UFC 显示面积也加大了）：
--   左边一个小姿态窗，右边两行：速度 / 高度 / 航向，过载 / 迎角 / 电台
P.ufc = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local Gc = RGB(120, 240, 160)
  local cw, ch = W * 0.26, H - 4
  local clip = F(R, 2, 2, cw, ch, RGB(0, 0, 0), 0, 2)
  clip.ClipsDescendants = true
  local ball = F(clip, -cw, -ch, cw * 3, ch * 3, RGB(30, 90, 170), 0, 2)
  F(ball, 0, ch * 1.5, cw * 3, ch * 1.5, RGB(110, 72, 36), 0, 3)
  F(ball, 0, ch * 1.5 - 1, cw * 3, 2, RGB(255, 255, 255), 0, 4)
  F(clip, cw * 0.28, ch / 2 - 1, cw * 0.44, 2, RGB(255, 210, 40), 0, 6)
  local L1 = Tx(R, "", W * 0.29, 2, W * 0.70, (H - 4) / 2, 12, Gc, nil, FONTB, 3)
  local L2 = Tx(R, "", W * 0.29, H / 2, W * 0.70, (H - 4) / 2, 11, Gc, nil, FONT, 3)
  return function(d)
    local py = (d.pitch or 0) * ch / 60
    ball.Rotation = -(d.roll or 0)
    ball.Position = UD2(0, -cw + math.sin(math.rad(d.roll or 0)) * py, 0, -ch + math.cos(math.rad(d.roll or 0)) * py)
    L1.Text = string.format(zh and "速度 %d  高度 %d  航向 %03d" or "IAS %d  ALT %d  HDG %03d",
      math.floor(zh and (d.kmh or 0) or (d.kt or 0)), math.floor(zh and (d.altM or 0) or ((d.altM or 0) * 3.281)), math.floor((d.hdg or 0) % 360))
    L2.Text = string.format(zh and "过载 %.1f  迎角 %d  通信 251.000" or "G %.1f  AOA %d  COM1 251.000", d.g or 1, math.floor(d.aoa or 0))
  end
end

-- 控制显示单元（A-10C 右侧操纵台上那块）：航路点、导航方式、位置、高度航向、地速、时间、系统（绿字一行行）
P.cdu = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local Gc = RGB(110, 255, 140)
  local L = {}
  for i = 1, 8 do L[i] = Tx(s.root, "", 4, 2 + (i - 1) * (H - 4) / 8, W - 8, (H - 4) / 8, 11, Gc, nil, FONT, 3) end
  return function(d)
    local p = d.pos or Vector3.new()
    local t = d.clock or 0
    L[1].Text = "WAYPT        STEER PT 01"
    L[2].Text = "NAV MODE     EGI    GPS"
    L[3].Text = string.format("POS  %06dE  %06dN", math.floor((p.X / 2.8 + 500000) % 1000000), math.floor((500000 - p.Z / 2.8) % 1000000))
    L[4].Text = string.format("ALT %6d FT  HDG %03d", math.floor((d.altM or 0) * 3.281), math.floor((d.hdg or 0) % 360))
    L[5].Text = string.format("GS  %4d KT   G %.1f", math.floor(d.kt or 0), d.g or 1)
    L[6].Text = string.format("TIME %02d:%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, math.floor(t) % 60)
    L[7].Text = "SYS  LASTE  HARS  EGI"
    L[8].Text = (d.warn and d.warn ~= "") and d.warn or "READY"
  end
end

-- 圆形雷达显示（歼-20 参考图大屏左边：一圈圈绿色距离环、扫描线转，目标按方位和距离画：敌红三角、友蓝圆）
P.rscope = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local G = RGB(80, 230, 110)
  local cx, cy, r = W / 2, H / 2 + 6, math.min(W, H) * 0.42
  for i = 1, 4 do Ring(R, cx, cy, r * i / 4, 1, (i == 4) and G or RGB(40, 120, 60), 2) end
  for a = 0, 330, 30 do
    local ra = math.rad(a)
    Ln(R, cx + math.sin(ra) * r * 0.25, cy - math.cos(ra) * r * 0.25, cx + math.sin(ra) * r, cy - math.cos(ra) * r, 1, RGB(30, 90, 50), 2)
  end
  local _, sweep = Ln(R, cx, cy, cx, cy - r, 2, G, 3)
  local title = Tx(R, "", 4, 2, W - 8, 14, 11, G, nil, FONTB, 4)
  local pool = {}
  local rng = 80   -- 公里
  return function(d)
    local t = os.clock() * 1.2
    sweep(cx, cy, cx + math.sin(t) * r, cy - math.cos(t) * r)
    local n = 0
    for _, c in ipairs(d.contacts or {}) do
      if c.km < rng then
        n += 1
        local f = pool[n] or Tx(R, "", 0, 0, 14, 14, 12, G, Enum.TextXAlignment.Center, FONTB, 5)
        pool[n] = f
        f.Visible = true
        local k = c.km / rng * r
        f.Position = UD2(0, cx + math.sin(math.rad(c.az)) * k - 7, 0, cy - math.cos(math.rad(c.az)) * k - 7)
        f.Text = c.friend and "●" or ((c.kind == "air") and "▲" or "◆")
        f.TextColor3 = c.friend and RGB(90, 200, 255) or RGB(255, 90, 70)
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
    title.Text = zh and string.format("雷达  %d 公里  目标 %d", rng, n) or string.format("RDR  %d NM  TGT %d", math.floor(rng * 0.54), n)
  end
end

-- 雷达告警（歼-16 参考图：大屏右边一块圆屏、大屏里的「告警」窗口）：两圈圆、中间自己，敌方目标按方位画（越远越靠外）
P.rwr = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local G = RGB(90, 230, 120)
  local cx, cy, r = W / 2, H / 2, math.min(W, H) * 0.42
  Ring(R, cx, cy, r, 2, G, 2)
  Ring(R, cx, cy, r * 0.5, 1, RGB(50, 140, 80), 2)
  for _, a in ipairs({ 0, 90, 180, 270 }) do
    local ra = math.rad(a)
    Ln(R, cx + math.sin(ra) * r * 0.86, cy - math.cos(ra) * r * 0.86, cx + math.sin(ra) * r, cy - math.cos(ra) * r, 2, G, 3)
  end
  F(R, cx - 1, cy - 6, 2, 12, G, 0, 4)
  F(R, cx - 6, cy - 1, 12, 2, G, 0, 4)
  local pool = {}
  return function(d)
    local n = 0
    for _, c in ipairs(d.contacts or {}) do
      if not c.friend then
        n += 1
        local t = pool[n] or Tx(R, "", 0, 0, 16, 16, 13, RGB(255, 90, 70), Enum.TextXAlignment.Center, FONTB, 5)
        pool[n] = t
        t.Visible = true
        local k = clamp((c.km or 0) / 100, 0.2, 0.9) * r
        t.Position = UD2(0, cx + math.sin(math.rad(c.az)) * k - 8, 0, cy - math.cos(math.rad(c.az)) * k - 8)
        t.Text = (c.kind == "air") and "▲" or "◆"
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
  end
end

-- 歼-20 正前方控制板（用户 11-21 给的真机座舱照片）：一块触摸屏，蓝紫底，4 × 4 一格格中文触摸键，下面一排页签、正中一个绿色圆键
P.ufct = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(255, 255, 255)
  local gr = Instance.new("UIGradient")
  gr.Color = ColorSequence.new(RGB(78, 68, 176), RGB(28, 34, 92))
  gr.Rotation = 90
  gr.Parent = R
  local labels = zh and { "导航", "通信", "识别", "告警", "雷达", "光电", "电子战", "数据链", "武器", "燃油", "航路", "进场", "自检", "记录", "灯光", "菜单" }
    or { "NAV", "COM", "IFF", "WARN", "RDR", "EO", "EW", "LINK", "WPN", "FUEL", "ROUTE", "APP", "BIT", "REC", "LIGHT", "MENU" }
  local gx, gy = W * 0.05, H * 0.05
  local cw, ch = (W - gx * 2) / 4, (H * 0.76 - gy) / 4
  local cells = {}
  for i, t in ipairs(labels) do
    local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
    local x, y = gx + c * cw + 3, gy + r * ch + 3
    F(R, x, y, cw - 6, ch - 6, RGB(16, 22, 64), 0.4, 3)
    Box(R, x, y, cw - 6, ch - 6, 1, RGB(120, 140, 230), 4)
    cells[i] = Tx(R, t, x, y, cw - 6, ch - 6, 12, RGB(225, 232, 255), Enum.TextXAlignment.Center, FONTB, 5)
  end
  local tabs = zh and { "主页", "飞行", "姿态", "", "外挂", "检查", "设置" } or { "HOME", "FLT", "ATT", "", "STORES", "CHK", "SET" }
  local tw = W / #tabs
  for i, t in ipairs(tabs) do
    if t ~= "" then Tx(R, t, (i - 1) * tw, H * 0.84, tw, H * 0.12, 10, RGB(160, 230, 170), Enum.TextXAlignment.Center, FONT, 5) end
  end
  local okR = math.min(tw, H * 0.16) * 0.5
  Ring(R, W / 2, H * 0.9, okR, 2, RGB(110, 240, 140), 6, RGB(40, 170, 80))
  Tx(R, zh and "确认" or "OK", W / 2 - okR, H * 0.9 - okR, okR * 2, okR * 2, 10, RGB(240, 255, 240), Enum.TextXAlignment.Center, FONTB, 7)
  return function(d)
    local warn = d.warn and d.warn ~= ""   -- 有告警时「告警」格闪红
    cells[4].TextColor3 = (warn and (math.floor(os.clock() * 3) % 2 == 0)) and RGB(255, 90, 80) or RGB(225, 232, 255)
  end
end

-- 正前方控制板的小液晶（歼-15T 参考图：一行行电台、导航、方式字）
P.ufcc = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local G = RGB(120, 240, 160)
  local L = {}
  for i = 1, 4 do L[i] = Tx(s.root, "", 3, 1 + (i - 1) * (H - 2) / 4, W - 6, (H - 2) / 4, 10, G, nil, FONT, 3) end
  return function(d)
    L[1].Text = zh and "通信1 125.35 话音  120.22 数据" or "COM1 125.35 VOICE 120.22 DATA"
    L[2].Text = zh and "通信2 305.50 加密  导航 塔康" or "COM2 305.50 SEC  NAV TCN"
    L[3].Text = string.format(zh and "高度 %d 米  航向 %03d" or "ALT %d FT  HDG %03d",
      math.floor(zh and (d.altM or 0) or ((d.altM or 0) * 3.281)), math.floor((d.hdg or 0) % 360))
    L[4].Text = (d.warn and d.warn ~= "") and d.warn or (zh and "自驾 关  敌我 正常" or "A/P OFF  IFF NORM")
  end
end

-- F-22 左上前显示器：告警 / 注意 / 提示一列字（ICAWS：红告警、黄注意、绿提示；真机照片上是一列黄绿字）
P.icaws = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local L = {}
  for i = 1, 6 do L[i] = Tx(s.root, "", 3, 1 + (i - 1) * (H - 2) / 6, W - 6, (H - 2) / 6, 10, RGB(255, 210, 60), nil, FONTB, 3) end
  local GN, YL, RD = RGB(110, 240, 140), RGB(255, 210, 60), RGB(255, 70, 60)
  return function(d)
    local rows = {}
    if d.warn and d.warn ~= "" then table.insert(rows, { d.warn, RD }) end
    if (d.fuel or 1) < 0.3 then table.insert(rows, { "FUEL LOW", YL }) end
    if (d.gear or 0) > 0.5 then table.insert(rows, { "GEAR DOWN", YL }) end
    table.insert(rows, { "ECS AUTO", GN })
    table.insert(rows, { "OBOGS ON", GN })
    table.insert(rows, { string.format("G %.1f", d.g or 1), GN })
    for i = 1, 6 do
      local r = rows[i]
      L[i].Text = r and r[1] or ""
      if r then L[i].TextColor3 = r[2] end
    end
  end
end

-- 按键的字 → 页面（多功能显示器、全景屏的触摸菜单共用）：F-22 的 TSD、A-10C 的 TAD / DSMS / STAT、F-35 的 FUEL（docs/cockpit_research.md）
local KEYPAGE = { PFD = "pfd", RDR = "radar", SA = "sa", SMS = "sms", ENG = "eng", TSD = "tsd", TAD = "sa", DSMS = "sms", STAT = "eng", FUEL = "eng",
  FCR = "radar", HSD = "sa", FLT = "pfd",   -- F-16 的页名：火控雷达、水平态势、飞行
  CDU = "cdu", LOAD = "sms", ["姿态"] = "pfd", ["雷达"] = "radar", ["态势"] = "sa", ["武器"] = "sms", ["发动机"] = "eng", ["油量"] = "eng" }
-- 多功能显示器：几个页面（默认 姿态 / 雷达 / 态势 / 武器 / 发动机），按键换页；names 给这一型有的页面（A-10C 没有雷达页）
local function mfd(first, names, bg)
  return function(s, env, zh)
    local W, H = s.px.X, s.px.Y
    local subs, ups = {}, {}
    for _, name in ipairs(names or { "pfd", "radar", "sa", "sms", "eng" }) do
      local f = F(s.root, 0, 0, W, H, bg or RGB(0, 0, 0), 0, 1)
      local sub = { root = f, px = s.px, page = name }
      ups[name] = P[name](sub, env, zh)
      subs[name] = { f = f, sub = sub }
    end
    local st = { page = first }
    local MAP = KEYPAGE
    s.onKey = function(k, act)
      if MAP[k] and subs[MAP[k]] then st.page = MAP[k]
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
P.mfd_tsd = mfd("tsd", { "tsd", "radar", "pfd", "sms", "eng" })          -- F-22 主显示器：战术态势俯视图
P.mfd_tad = mfd("sa", { "sa", "pfd", "sms", "eng", "cdu" })              -- A-10C 左 MFCD：TAD（没有雷达）
P.mfd_dsms = mfd("sms", { "sms", "sa", "pfd", "eng", "cdu" })            -- A-10C 右 MFCD：外挂（DSMS）、CDU 页
-- F-22（用户 11-21 给的真机照片）：三块主显示器是深蓝底、上面一圈圈距离环
local NAVY = RGB(10, 22, 62)
P.f22_tsd = mfd("tsd", { "tsd", "radar", "pfd", "sms", "eng" }, NAVY)
P.f22_sms = mfd("sms", { "sms", "tsd", "radar", "pfd", "eng" }, NAVY)
P.f22_eng = mfd("eng", { "eng", "tsd", "radar", "pfd", "sms" }, NAVY)
-- F-16C 的两块 4 英寸多功能显示器（用户 11-23 加 F-16：原模型座舱里贴的就是这两页）：左边默认火控雷达 FCR、右边默认外挂管理 SMS；
--   上排键换页（FCR 雷达、HSD 水平态势、SMS 外挂、FUEL 发动机燃油、FLT 飞行），下排 RNG 换雷达 / 态势的量程
P.f16l = mfd("radar", { "radar", "sa", "sms", "eng", "pfd" })
P.f16r = mfd("sms", { "sms", "sa", "radar", "eng", "pfd" })

-- 一块宽屏分几个窗口（F-35 的「门户」、歼-20 / 歼-35 / 歼-16 的大屏）：areas = { { 起点, 宽（占屏宽几成）, 页面, 标题, 底色 }, … }，
--   map[键] = { 第几个窗口, 页面 }；每个窗口顶上一条窄标题（门户的名字），窗口之间一道暗缝；没在 map 里的键交给第一个窗口自己的页面
local function multi(areas, map)
  return function(s, env, zh)
    local W, H = s.px.X, s.px.Y
    local subs = {}
    local hh = math.max(10, math.floor(H * 0.07))
    for i, a in ipairs(areas) do
      local x0, w0 = W * a[1] + 2, W * a[2] - 4
      local head = a[4] and Tx(s.root, a[4], x0, 0, w0, hh, math.max(9, hh - 3), RGB(150, 210, 190), Enum.TextXAlignment.Center, FONTB, 6)
      if head then F(s.root, x0, hh - 1, w0, 1, RGB(60, 110, 96), 0, 6) end
      local top = head and hh or 0
      local f = F(s.root, x0, top, w0, H - top, a[5] or RGB(0, 0, 0), 0, 1)
      local sub = { root = f, px = Vector3.new(w0, H - top, 0) }
      subs[i] = { f = f, sub = sub, name = a[3], head = head, up = P[a[3]](sub, env, zh) }
      if i > 1 then F(s.root, W * a[1] - 1, 0, 2, H, RGB(26, 30, 30), 0, 7) end   -- 窗口之间的缝
    end
    local TITLE = { sa = zh and "态势" or "TSD", tsd = zh and "态势" or "TSD", radar = zh and "雷达" or "FCR", pfd = zh and "飞行" or "FLT",
      sms = zh and "武器" or "SMS", eng = zh and "发动机 燃油" or "FUEL / ENG", cdu = "CDU", rscope = zh and "雷达" or "FCR", rwr = zh and "告警" or "RWR" }
    local function swap(i, name)
      local it = subs[i]
      if not it or it.name == name then return end
      for _, c in ipairs(it.f:GetChildren()) do c:Destroy() end
      it.name = name
      it.sub.onKey = nil
      it.up = P[name](it.sub, env, zh)
      if it.head then it.head.Text = TITLE[name] or name end
    end
    s.onKey = function(k, act)
      local m = map[k]
      if m then swap(m[1], m[2])
      elseif subs[1].sub.onKey then subs[1].sub.onKey(canon(k), act) end
    end
    return function(d)
      for _, it in ipairs(subs) do if it.up then it.up(d) end end
    end
  end
end
-- 全景大屏（歼-35、歼-50：整块触摸大屏，资料只到「大横屏」）：左边态势 / 雷达、中间姿态、右边武器 / 发动机
P.pano = multi({ { 0, 0.42, "sa" }, { 0.42, 0.28, "pfd" }, { 0.70, 0.30, "sms" } },
  { SA = { 1, "sa" }, RDR = { 1, "radar" }, SMS = { 3, "sms" }, ENG = { 3, "eng" }, PFD = { 2, "pfd" },
    ["态势"] = { 1, "sa" }, ["雷达"] = { 1, "radar" }, ["武器"] = { 3, "sms" }, ["发动机"] = { 3, "eng" }, ["姿态"] = { 2, "pfd" }, ["油量"] = { 3, "eng" } })
-- 歼-20 主屏（24 × 9 英寸触摸屏；用户 11-21 给的真机座舱照片）：左边一窗上面一排小表 + 圆形雷达 + 目标表，中间飞机俯视挂弹，
--   右边一半是地图（照片上是卫星图）；触摸菜单换窗口内容
P.j20_main = multi({ { 0, 0.30, "j20left" }, { 0.30, 0.20, "sms" }, { 0.50, 0.50, "sa" } },
  { ["态势"] = { 3, "sa" }, ["雷达"] = { 1, "j20left" }, ["武器"] = { 2, "sms" }, ["发动机"] = { 2, "eng" }, ["油量"] = { 2, "eng" }, ["姿态"] = { 2, "pfd" } })
-- 歼-16 大屏（用户 11-21 给的「J-16 座舱环视」参考图：一整块横屏分四个窗口）：飞行、雷达、态势、雷达告警
P.j16_main = multi({ { 0, 0.25, "pfd", "飞行" }, { 0.25, 0.25, "radar", "雷达" }, { 0.5, 0.25, "tsd", "态势" }, { 0.75, 0.25, "rwr", "告警" } },
  { ["姿态"] = { 1, "pfd" }, ["雷达"] = { 2, "radar" }, ["态势"] = { 3, "tsd" }, ["武器"] = { 4, "sms" }, ["发动机"] = { 4, "eng" }, ["油量"] = { 4, "eng" } })
-- F-35 全景座舱显示器（20 × 8 英寸，两块 10 × 8 英寸拼成，4 个门户）：左半是大号 TSD（两个门户合成一个），右半两个门户（燃油发动机、外挂）
--   真机照片（用户 11-21 给的）：门户是深蓝、绿、紫的色块底，不是全黑
P.f35l = multi({ { 0, 1, "tsd", "TSD", RGB(14, 20, 60) } }, { TSD = { 1, "tsd" }, RDR = { 1, "radar" }, FLT = { 1, "pfd" } })
P.f35r = multi({ { 0, 0.5, "eng", "FUEL / ENG", RGB(10, 46, 34) }, { 0.5, 0.5, "sms", "SMS", RGB(40, 18, 66) } },
  { FUEL = { 1, "eng" }, ENG = { 1, "eng" }, SMS = { 2, "sms" }, FLT = { 1, "pfd" }, TSD = { 2, "tsd" } })
-- 歼-15T：下方一整块大屏（两块拼起来的，中间一道缝）：左半态势 / 雷达，右半飞行 + 武器
P.j15l = multi({ { 0, 1, "radar", "雷达" } }, { ["雷达"] = { 1, "radar" }, ["态势"] = { 1, "sa" }, ["姿态"] = { 1, "pfd" } })
P.j15r = multi({ { 0, 0.5, "pfd", "飞行" }, { 0.5, 0.5, "sms", "武器" } }, { ["武器"] = { 2, "sms" }, ["发动机"] = { 2, "eng" }, ["油量"] = { 2, "eng" }, ["姿态"] = { 1, "pfd" } })

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
-- 第三块小辅助屏（歼-20：一块大屏 + 三块小屏）：马赫数、攻角、高度、垂直速度
P.ufd3 = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local G = RGB(90, 230, 120)
  local L = {}
  for i = 1, 4 do L[i] = Tx(s.root, "", 4, 2 + (i - 1) * (H - 4) / 4, W - 8, (H - 4) / 4, 11, G, nil, FONT, 3) end
  return function(d)
    L[1].Text = string.format(zh and "马赫 %.2f" or "M %.2f", d.mach or 0)
    L[2].Text = string.format(zh and "攻角 %.1f°" or "AOA %.1f", d.aoa or 0)
    L[3].Text = string.format(zh and "高度 %d 米" or "ALT %d M", math.floor(d.altM or 0))
    L[4].Text = string.format(zh and "垂速 %+d" or "VS %+d", math.floor(d.vs or 0))
  end
end

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
-- 升降速度表（A-10C 中间那列）：零在九点钟，往上爬指针往上转，满刻度 ±30 米 / 秒
P.vvi = function(s, env, zh)
  local set = dial(s, 12, zh and "升降" or "VVI")
  return function(d) set(-PI / 2 + clamp((d.vs or 0) / 30, -1, 1) * PI * 0.9) end
end
-- 水平状态指示器（A-10C 中间那列，姿态仪下面）：罗盘刻度盘跟着航向转，上面一根固定的航向标线、中间飞机符号
P.hsi = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.BackgroundColor3 = RGB(12, 12, 12)
  Ring(R, W / 2, H / 2, W * 0.47, 2, RGB(190, 190, 190), 2, RGB(16, 16, 16))
  local card = F(R, 0, 0, W, H, RGB(0, 0, 0), 1, 3)   -- 转的刻度盘（透明底，子件跟着一起转）
  for i = 0, 35 do
    local a = math.rad(i * 10)
    local r0 = (i % 3 == 0) and 0.34 or 0.39
    Ln(card, W / 2 + math.sin(a) * W * r0, H / 2 - math.cos(a) * H * r0, W / 2 + math.sin(a) * W * 0.44, H / 2 - math.cos(a) * H * 0.44, 1, RGB(230, 230, 230), 4)
  end
  for i, t in ipairs({ "N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33" }) do
    local a = math.rad((i - 1) * 30)
    Tx(card, t, W / 2 + math.sin(a) * W * 0.27 - 10, H / 2 - math.cos(a) * H * 0.27 - 6, 20, 12, 10, RGB(240, 240, 240), Enum.TextXAlignment.Center, FONTB, 5)
  end
  F(R, W / 2 - 1, H * 0.03, 3, H * 0.12, RGB(255, 200, 40), 0, 7)    -- 航向标线
  F(R, W / 2 - 1, H / 2 - 7, 2, 14, RGB(255, 255, 255), 0, 7)       -- 飞机符号
  F(R, W / 2 - 7, H / 2 - 2, 14, 2, RGB(255, 255, 255), 0, 7)
  return function(d) card.Rotation = -((d.hdg or 0) % 360) end
end
-- 过载表（歼-15T 参考图：控制板右边那个指针小表）：1 g 在左边，9 g 转到右下
P.gmeter = function(s, env, zh)
  local set = dial(s, 12, zh and "过载" or "G")
  return function(d) set(-PI / 2 + clamp(((d.g or 1) - 1) / 8, -0.4, 1) * PI * 1.25) end
end
-- 歼-20 大屏左边那一窗（真机照片）：上面一排四个小表（左右发动机转速、排温）+ 飞机图标，中间圆形雷达，下面一张目标表
P.j20left = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local th, bh = H * 0.2, H * 0.2
  local sets = {}
  for i = 1, 4 do
    local f = F(R, (i - 1) * W * 0.16, 0, W * 0.16, th, RGB(0, 0, 0), 0, 2)
    sets[i] = dial({ root = f, px = Vector3.new(W * 0.16, th, 0) }, 8, "")
    f.BackgroundTransparency = 1
  end
  Tx(R, "✈", W * 0.66, 0, W * 0.14, th, math.floor(th * 0.7), RGB(90, 230, 120), Enum.TextXAlignment.Center, FONTB, 3)
  local tab = Tx(R, "", W * 0.80, 2, W * 0.2 - 2, th - 4, 9, RGB(90, 230, 120), nil, FONT, 3)
  local mid = F(R, 0, th, W, H - th - bh, RGB(0, 0, 0), 1, 2)
  local up = P.rscope({ root = mid, px = Vector3.new(W, H - th - bh, 0) }, env, zh)
  local rows = {}
  for i = 1, 3 do rows[i] = Tx(R, "", 4, H - bh + (i - 1) * bh / 3, W - 8, bh / 3, 10, RGB(90, 230, 120), nil, FONT, 3) end
  return function(d)
    local k = clamp((d.thr or 0) / 100, 0, 1.3)
    sets[1](0.6 + k * 3.6) sets[2](0.6 + k * 3.6) sets[3](1.4 + k * 2.6) sets[4](1.4 + k * 2.6)
    tab.Text = string.format(zh and "油 %d%%\n过载 %.1f" or "FUEL %d%%\nG %.1f", math.floor((d.fuel or 1) * 100), d.g or 1)
    up(d)
    local n = 0
    for _, c in ipairs(d.contacts or {}) do
      if not c.friend and n < 3 then
        n += 1
        rows[n].Text = string.format(zh and "目标%d  方位 %03d  %d 公里" or "TGT%d  BRG %03d  %d KM", n, math.floor((c.az or 0) % 360), math.floor(c.km or 0))
      end
    end
    for i = n + 1, 3 do rows[i].Text = (i == 1) and (zh and "无目标" or "NO TGT") or "" end
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

-- 防空雷达（平面位置显示器 PPI）：一圈圈距离环、扫描线转、空中目标（友军蓝、敌军绿）；地面车辆的雷达（自行高炮、C-RAM、操作员控制台）
-- 数据输入显示器（F-16 的 DED、F-15 正前方控制板上那一小条液晶）：绿色字，通信频率、导航点、时间、敌我识别、航向 / 马赫 / 过载、油量和告警
P.ded = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local G = RGB(120, 255, 140)
  local n = clamp(math.floor(H / 14), 2, 5)
  local L = {}
  for i = 1, n do L[i] = Tx(s.root, "", 3, 1 + (i - 1) * (H - 2) / n, W - 6, (H - 2) / n, clamp(math.floor((H - 2) / n) - 2, 8, 13), G, nil, FONT, 3) end
  return function(d)
    local t = d.clock or 0
    local rows = {
      string.format("UHF 251.00  STPT %2d", 1 + math.floor(t / 600) % 9),
      string.format("VHF 136.00  %02d:%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60, math.floor(t) % 60),
      string.format("HDG %03d  M%.2f  G%.1f", math.floor((d.hdg or 0) % 360), d.mach or 0, d.g or 1),
      string.format("FUEL %3d%%  %s", math.floor((d.fuel or 1) * 100), (d.gear or 0) > 0.5 and "GEAR DN" or "M1 3 C 1200"),
      (d.warn and d.warn ~= "") and d.warn or "IFF  MODE 4 ON",
    }
    for i = 1, n do L[i].Text = rows[i] or "" end
  end
end

-- F-15C 的垂直态势显示器 VSD / F-14 后座的细节数据显示器 DDD：单色绿的雷达 B 显示（同 radar 页），屏上一道道扫描线（老式 CRT）
P.vsd = function(s, env, zh)
  local up = P.radar(s, env, zh)
  local W, H = s.px.X, s.px.Y
  for y = 0, H, 4 do F(s.root, 0, y, W, 1, RGB(0, 0, 0), 0.82, 8) end
  return up
end

-- F-14 前座的垂直显示器 VDI：绿色单色 CRT 的姿态画面（天地线、俯仰梯、飞机符号），下面一行速度、高度、航向
P.vdi = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G, DG = RGB(110, 255, 140), RGB(0, 46, 16)
  local clip = F(R, W * 0.06, H * 0.06, W * 0.88, H * 0.74, RGB(0, 8, 2), 0, 1)
  clip.ClipsDescendants = true
  local cw, ch = W * 0.88, H * 0.74
  local ball = F(clip, cw / 2 - cw * 1.5, ch / 2 - ch * 1.5, cw * 3, ch * 3, RGB(0, 8, 2), 1, 2)
  F(ball, 0, ch * 1.5, cw * 3, ch * 1.5, DG, 0, 3)   -- 地面一侧暗绿
  F(ball, 0, ch * 1.5 - 1, cw * 3, 2, G, 0, 4)
  for i = -6, 6 do
    if i ~= 0 then
      local y = ch * 1.5 - i * 5 * (ch / 50)
      local w = (i % 2 == 0) and cw * 0.30 or cw * 0.16
      F(ball, cw * 1.5 - w / 2, y, w, 1, G, (i < 0) and 0.35 or 0, 4)
      if i % 2 == 0 then Tx(ball, tostring(math.abs(i * 5)), cw * 1.5 + w / 2 + 2, y - 6, 26, 12, 10, G, nil, FONT, 5) end
    end
  end
  F(clip, cw * 0.30, ch / 2 - 1, cw * 0.14, 2, G, 0, 8)
  F(clip, cw * 0.56, ch / 2 - 1, cw * 0.14, 2, G, 0, 8)
  F(clip, cw / 2 - 2, ch / 2 - 2, 4, 4, G, 0, 8)
  for y = 0, H, 4 do F(R, 0, y, W, 1, RGB(0, 0, 0), 0.85, 9) end
  local bot = Tx(R, "", 4, H * 0.82, W - 8, H * 0.16, 11, G, Enum.TextXAlignment.Center, FONT, 9)
  return function(d)
    local pitch, roll = d.pitch or 0, d.roll or 0
    local py = pitch * (ch / 50)
    ball.Rotation = -roll
    ball.Position = UD2(0, cw / 2 - cw * 1.5 + math.sin(math.rad(roll)) * py, 0, ch / 2 - ch * 1.5 + math.cos(math.rad(roll)) * py)
    bot.Text = string.format("%d KT   %d FT   %03d", math.floor(d.kt or 0), math.floor((d.altM or 0) * 3.281), math.floor((d.hdg or 0) % 360))
  end
end

-- F-14 后座的战术信息显示器 TID（9 英寸圆屏，RIO 看的空情）：本机在中间、机头朝上，距离环，每个目标一个航迹号
--   （敌机 ∧、友机半圆、地面 / 海上目标菱形），锁定的那个加方框；RNG 键 50 / 100 / 200 公里
P.tid = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  R.ClipsDescendants = true
  local G = RGB(120, 240, 150)
  local cx, cy, r = W / 2, H / 2, math.min(W, H) * 0.46
  local cr = Instance.new("UICorner")
  cr.CornerRadius = UDim.new(0.5, 0)
  cr.Parent = R
  for i = 1, 4 do Ring(R, cx, cy, r * i / 4, 1, (i == 4) and G or RGB(40, 110, 60), 2) end
  for a = 0, 330, 30 do
    local ra = math.rad(a)
    Ln(R, cx + math.sin(ra) * r * 0.94, cy - math.cos(ra) * r * 0.94, cx + math.sin(ra) * r, cy - math.cos(ra) * r, 1, G, 2)
  end
  F(R, cx - 1, cy - 7, 2, 14, G, 0, 4)   -- 本机
  F(R, cx - 7, cy - 1, 14, 2, G, 0, 4)
  local title = Tx(R, "", cx - r * 0.7, cy + r * 0.66, r * 1.4, 14, 11, G, Enum.TextXAlignment.Center, FONTB, 6)
  local st = { rng = 100 }
  s.onKey = function(k) if k == "RNG" then st.rng = (st.rng == 100) and 200 or ((st.rng == 200) and 50 or 100) end end
  local pool = {}
  local lockB = Box(R, 0, 0, 22, 22, 2, RGB(255, 230, 90), 7)
  lockB.Visible = false
  return function(d)
    local n = 0
    lockB.Visible = false
    for i, c in ipairs(d.contacts or {}) do
      if c.km < st.rng then
        n += 1
        local t = pool[n] or Tx(R, "", 0, 0, 40, 14, 11, G, Enum.TextXAlignment.Center, FONTB, 5)
        pool[n] = t
        t.Visible = true
        local k = c.km / st.rng * r
        local x, y = cx + math.sin(math.rad(c.az)) * k, cy - math.cos(math.rad(c.az)) * k
        t.Position = UD2(0, x - 20, 0, y - 7)
        t.Text = (c.friend and "◠" or ((c.kind == "air") and "∧" or "◆")) .. string.format("%02d", (i * 7) % 100)
        t.TextColor3 = c.friend and RGB(110, 200, 255) or RGB(255, 120, 90)
        if c.locked then
          lockB.Visible = true
          lockB.Position = UD2(0, x - 11, 0, y - 11)
        end
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
    title.Text = string.format("TID  RNG %d  TRK %d", st.rng, n)
  end
end

P.ppi = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G = RGB(80, 230, 110)
  local cx, cy, r = W / 2, H / 2 + 6, math.min(W, H) * 0.42
  for i = 1, 4 do Ring(R, cx, cy, r * i / 4, 1, G, 2) end
  Ln(R, cx - r, cy, cx + r, cy, 1, G, 2)
  Ln(R, cx, cy - r, cx, cy + r, 1, G, 2)
  local _, sweep = Ln(R, cx, cy, cx, cy - r, 2, G, 3)
  local title = Tx(R, "", 4, 2, W - 8, 14, 11, G, nil, FONTB, 4)
  local pool = {}
  local rng = 12000   -- 12 公里
  return function(d)
    local t = os.clock() * 1.6
    sweep(cx, cy, cx + math.sin(t) * r, cy - math.cos(t) * r)
    local pos, fwd = d.pos, d.fwd
    local n = 0
    if pos and fwd then
      local yaw = math.atan2(-fwd.X, -fwd.Z)
      for _, e in ipairs(d.ents or {}) do
        if e.kind == "air" then
          local q = e.pos - pos
          local dist = Vector3.new(q.X, 0, q.Z).Magnitude / 2.8
          if dist < rng then
            local a = math.atan2(-q.X, -q.Z) - yaw
            local k = dist / rng * r
            n += 1
            local f = pool[n] or F(R, 0, 0, 7, 7, G, 0, 5)
            pool[n] = f
            f.Visible = true
            f.Position = UD2(0, cx - math.sin(a) * k - 3, 0, cy - math.cos(a) * k - 3)
            f.BackgroundColor3 = (e.team == d.team) and RGB(80, 160, 255) or RGB(255, 90, 70)
          end
        end
      end
    end
    for i = n + 1, #pool do pool[i].Visible = false end
    title.Text = zh and string.format("搜索雷达  12 公里  空中目标 %d", n) or string.format("SEARCH RADAR  12 KM  AIR TRACKS %d", n)
  end
end

-- 火控计算机（自行火炮、火箭炮、防空车的火控页）：射击诸元——方位、射角、距离、弹种、装药、剩余弹数
P.afcs = function(s, env, zh)
  local W, H = s.px.X, s.px.Y
  local R = s.root
  local G = RGB(90, 230, 120)
  Tx(R, zh and "火控计算机" or "FIRE CONTROL", 4, 2, W - 8, 14, 12, G, Enum.TextXAlignment.Center, FONTB, 3)
  local rows = {}
  for i = 1, 6 do rows[i] = Tx(R, "", 8, 18 + (i - 1) * (H - 24) / 6, W - 16, (H - 24) / 6, 12, G, nil, FONT, 3) end
  return function(d)
    local az = d.turretDeg or 0
    rows[1].Text = string.format(zh and "方位   %04d 密位" or "AZ     %04d MIL", math.floor((az % 360) / 360 * 6400))
    rows[2].Text = string.format(zh and "射角   %+.1f°" or "QE     %+.1f DEG", d.gunDeg or 0)
    rows[3].Text = string.format(zh and "距离   %d 米" or "RANGE  %d M", math.floor(d.range or 0))
    rows[4].Text = (zh and "弹种   " or "AMMO   ") .. tostring(d.ammoName or "--")
    rows[5].Text = string.format(zh and "剩余   %d" or "RDS    %d", d.ammo or 0)
    rows[6].Text = (d.ready == false) and (zh and "装填中…" or "LOADING…") or (zh and "可以射击" or "READY")
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
