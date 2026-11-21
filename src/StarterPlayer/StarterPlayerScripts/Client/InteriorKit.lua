-- Roblox全面大战场（客户端）——载具内饰的零件库（Interior.lua、InteriorDefs.lua 用）
--   用户 11-21：所有载具一比一还原内饰和里面所有功能性的东西（屏幕等），对标 Steel Beasts，要拿去拍电影
--   · 坐标一律用真实的米（1 米 = 2.8 格，和 VehDefs 一样）；挂在「组」上：根组 hull（车体，原点在炮塔座圈中心、座圈平面上，不随炮塔转）、
--     turret（同一点，随炮塔转）、gun（炮耳轴，随炮俯仰）；子组 = 父组 × 支点 × 动画（舱门滑开、炮闩下落、转盘转、弹丸被抬起……每帧改 anim）
--   · Interior 每帧算好各组的世界姿态，零件一次 BulkMoveTo；零件都不碰撞、不挡射线
--   · 屏幕：一块黑边框 + 一块发光的显示面（SurfaceGui，不受光照、自己发光，前面再挂一个很弱的 SurfaceLight 把车里照出一点屏幕的颜色）
--   · 乘员：R15 小人（服务器做的模板 ReplicatedStorage.BotRig，没有就用零件拼一个关节名字一样的），关节按反向运动学摆：
--     骨盆放在座位上，手握在操纵杆 / 方向把 / 炮弹上，脚踩在踏板 / 地板上，头朝着看的方向
local RS = game:GetService("ReplicatedStorage")

local K = {}
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local MAT = Enum.Material
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local S = 2.8   -- 1 米多少格
local PI = math.pi
K.S = S
local function rad(d) return math.rad(d) end
K.rad = rad

-- 米 → 格：位置乘 2.8，转角不变
local function toS(cf) return CF(cf.Position * S) * cf.Rotation end
K.toS = toS

-- 常用颜色（各车自己的漆色在 InteriorDefs 里）
K.C = {
  black = RGB(24, 25, 27), dark = RGB(44, 46, 49), gray = RGB(92, 95, 98), lgray = RGB(150, 153, 156), steel = RGB(118, 121, 124),
  gun = RGB(58, 60, 62), od = RGB(78, 84, 60), rubber = RGB(20, 20, 21), brass = RGB(176, 140, 72), copper = RGB(160, 96, 60),
  red = RGB(178, 38, 34), yellow = RGB(222, 184, 40), white = RGB(226, 226, 220), glass = RGB(30, 44, 52), screen = RGB(6, 9, 8),
  cable = RGB(30, 30, 32), cableG = RGB(70, 78, 56), green = RGB(60, 180, 90), amber = RGB(255, 170, 40), fabric = RGB(58, 56, 50),
}

local B = {}
B.__index = B

function K.new(model)
  local b = setmetatable({ model = model, parts = {}, groups = {}, gorder = {}, screens = {}, lights = {}, leds = {}, named = {},
    anims = {}, crew = {}, stations = {}, small = 0, softkeys = {} }, B)
  b:group("hull")
  b:group("turret")
  b:group("gun")
  return b
end

-- 组：parent 为 nil 的是根组（Interior 每帧直接给世界姿态）；子组的世界姿态 = 父组 × pivot × anim
function B:group(name, parent, pivot)
  if self.groups[name] then return self.groups[name] end
  local g = { name = name, parent = parent and self.groups[parent] or nil, pivot = pivot and toS(pivot) or CF(), anim = CF(), parts = {} }
  self.groups[name] = g
  table.insert(self.gorder, g)
  return g
end
-- 改一个子组的动画姿态（米）
function B:setAnim(name, cf)
  local g = self.groups[name]
  if g then g.anim = toS(cf) end
end

---------------------------------------------------------------- 零件

local SMALL = 0.05   -- 比这小的零件不投影（几百颗螺栓、开关都投影的话，车里几盏灯的阴影图很费）
function B:add(gname, cls, size, cf, color, mat, shape)
  local p = Instance.new(cls)
  if shape then p.Shape = shape end
  p.Size = size * S
  p.Color = color or K.C.gray
  p.Material = mat or MAT.SmoothPlastic
  p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  if math.max(size.X, size.Y, size.Z) < SMALL then p.CastShadow = false self.small += 1 end
  local off = toS(cf)
  p.CFrame = off
  p.Parent = self.model
  local g = self.groups[gname] or self.groups.hull
  table.insert(self.parts, { p, g, off })
  return p
end
function B:box(g, size, cf, col, mat) return self:add(g, "Part", size, cf, col, mat) end
function B:wedge(g, size, cf, col, mat) return self:add(g, "WedgePart", size, cf, col, mat) end
function B:cwedge(g, size, cf, col, mat) return self:add(g, "CornerWedgePart", size, cf, col, mat) end
-- 圆柱：轴沿 cf 的 X
function B:cyl(g, len, dia, cf, col, mat) return self:add(g, "Part", V(len, dia, dia), cf, col, mat, CYL) end
-- 竖着的圆柱（轴沿 Y）、前后的圆柱（轴沿 Z）
function B:cylY(g, len, dia, cf, col, mat) return self:cyl(g, len, dia, cf * ANG(0, 0, PI / 2), col, mat) end
function B:cylZ(g, len, dia, cf, col, mat) return self:cyl(g, len, dia, cf * ANG(0, PI / 2, 0), col, mat) end
function B:ball(g, dia, cf, col, mat) return self:add(g, "Part", V(dia, dia, dia), cf, col, mat, BALL) end
-- 从 a 到 b 的一根管子 / 杆子 / 电缆（米）
function B:tube(g, a, b, dia, col, mat)
  local d = b - a
  local L = d.Magnitude
  if L < 1e-3 then return nil end
  return self:cyl(g, L, dia, CFrame.lookAt((a + b) / 2, b) * ANG(0, PI / 2, 0), col, mat)
end
-- 一串点连成的电缆 / 液压管：拐弯处补一个球（不露出折角）
function B:cable(g, pts, dia, col, mat)
  for i = 1, #pts - 1 do
    self:tube(g, pts[i], pts[i + 1], dia, col or K.C.cable, mat or MAT.SmoothPlastic)
    if i > 1 then self:ball(g, dia, CF(pts[i]), col or K.C.cable, mat or MAT.SmoothPlastic) end
  end
end
-- 一束电缆：几根并排、颜色略有不同（车里到处是成束的线）
function B:harness(g, pts, n, dia, side)
  side = side or V(1, 0, 0)
  for i = 1, n do
    local o = side * ((i - (n + 1) / 2) * dia * 1.15)
    local q = {}
    for j, p in ipairs(pts) do q[j] = p + o end
    local c = (i % 3 == 0) and K.C.cableG or ((i % 3 == 1) and K.C.cable or K.C.dark)
    self:cable(g, q, dia, c)
  end
end

---------------------------------------------------------------- 字、屏幕、灯

-- 在零件某一面挂 SurfaceGui；ppm 每米多少像素
function K.gui(part, face, ppm, glow)
  local sg = Instance.new("SurfaceGui")
  sg.Face = face or Enum.NormalId.Front
  sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
  sg.PixelsPerStud = (ppm or 600) / S
  sg.LightInfluence = glow and 0 or 1
  if glow then pcall(function() sg.Brightness = glow end) end
  sg.ClipsDescendants = true
  sg.ResetOnSpawn = false
  sg.Parent = part
  return sg
end
-- 一块标牌 / 铭牌：贴在零件的一面上的字（米黄底黑字、黑底白字、黄底黑字的警告牌）
function B:placard(g, w, h, cf, text, opt)
  opt = opt or {}
  local p = self:box(g, V(w, h, 0.004), cf, opt.bg or RGB(214, 206, 170), MAT.SmoothPlastic)
  p.CastShadow = false
  local sg = K.gui(p, Enum.NormalId.Front, opt.ppm or 900)
  local l = Instance.new("TextLabel")
  l.Size = UDim2.fromScale(1, 1)
  l.BackgroundTransparency = 1
  l.Text = text
  l.TextColor3 = opt.fg or RGB(20, 20, 18)
  l.Font = opt.font or Enum.Font.GothamBold
  l.TextScaled = true
  l.TextWrapped = true
  l.Parent = sg
  return p
end
-- 屏幕：边框（黑色塑料 / 铝壳）+ 显示面；返回 { part, gui, w, h }，page 是 InteriorScreens 里的页面名
function B:screen(g, w, h, cf, page, opt)
  opt = opt or {}
  -- 触摸屏（F-35 的全景屏、歼-20 / 歼-35 的大屏，docs/cockpit_research.md）：没有边框上凸出来的键，菜单条就画在玻璃上，页面往里让出一条
  local touch = opt.touch == true and type(opt.keys) == "table"
  local bez = opt.bezel or (touch and 0.012) or ((type(opt.keys) == "table") and 0.036 or 0.02)
  local d = opt.depth or 0.05
  self:box(g, V(w + bez * 2, h + bez * 2, d), cf * CF(0, 0, d / 2 + 0.002), opt.frame or K.C.black, MAT.SmoothPlastic)
  local face = self:box(g, V(w, h, 0.004), cf, K.C.screen, MAT.Glass)
  face.CastShadow = false
  face.Reflectance = 0.04
  local sg = K.gui(face, Enum.NormalId.Front, opt.ppm or 1400, opt.glow or 1.6)
  local tabT = (touch and opt.keys.top and #opt.keys.top > 0) and (opt.touchH or 0.1) or 0      -- 上、下菜单条各占屏高几成
  local tabB = (touch and opt.keys.bottom and #opt.keys.bottom > 0) and (opt.touchH or 0.1) or 0
  local root = Instance.new("Frame")
  root.Name = "Page"
  root.Position = UDim2.fromScale(0, tabT)
  root.Size = UDim2.fromScale(1, 1 - tabT - tabB)
  root.BackgroundColor3 = RGB(0, 0, 0)
  root.BorderSizePixel = 0
  root.Parent = sg
  local s = { part = face, gui = sg, root = root, w = w, h = h, page = page, opt = opt, group = g, px = V(w, h * (1 - tabT - tabB), 0) * (opt.ppm or 1400) }
  if opt.light ~= false then   -- 屏幕把前面一小块照亮
    local L = Instance.new("SurfaceLight")
    L.Face = Enum.NormalId.Front
    L.Range = (opt.lightRange or 1.4) * S
    L.Brightness = opt.lightK or 0.35
    L.Angle = 80
    L.Shadows = false
    L.Color = opt.lightColor or RGB(140, 200, 160)
    L.Parent = face
    s.light = L
  end
  -- 按键：屏幕上下各一排（多功能显示器、指挥终端、驾驶员显示器都有），按键旁边边框上印着字；
  --   opt.keys = { top = { "MAP", … }, bottom = { … } }（真实的标签和功能见 InteriorScreens 的 KEYDESC），数字就是不带字的
  if touch then   -- 触摸屏：一格格薄片贴在玻璃前面（对准、按下同实体键：Interior 的 pickKey 按正面求交）
    for _, side in ipairs({ "top", "bottom" }) do
      local list = opt.keys[side] or {}
      local n = #list
      local th = h * ((side == "top") and tabT or tabB)
      for i, label in ipairs(list) do
        local x = w / 2 - (i - 0.5) * w / n
        local sy = (side == "top") and 1 or -1
        local key = self:box(g, V(w / n * 0.94, th * 0.84, 0.001), cf * CF(x, sy * (h / 2 - th / 2), -0.0026), RGB(16, 30, 26), MAT.SmoothPlastic)
        key.CastShadow = false
        local lg = K.gui(key, Enum.NormalId.Front, opt.ppm or 1400, 1.2)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.fromScale(1, 0.86)
        t.Position = UDim2.fromScale(0, 0.07)
        t.BackgroundTransparency = 1
        t.Text = label
        t.TextColor3 = RGB(190, 236, 214)
        t.Font = Enum.Font.GothamBold
        t.TextScaled = true
        t.Parent = lg
        local st = Instance.new("UIStroke")   -- 触摸格的细边框（玻璃上画的，不是实体键）
        st.Color, st.Thickness, st.Transparency = RGB(90, 160, 140), 1, 0.3
        local bg = Instance.new("Frame")
        bg.Size, bg.BackgroundTransparency, bg.BorderSizePixel = UDim2.fromScale(1, 1), 1, 0
        st.Parent = bg
        bg.Parent = lg
        table.insert(self.softkeys, { part = key, label = label, screen = s, side = side, idx = i, col = key.Color, touch = true })
      end
    end
  elseif type(opt.keys) == "table" then
    for _, side in ipairs({ "top", "bottom" }) do
      local list = opt.keys[side] or {}
      local n = #list
      for i, label in ipairs(list) do
        local x = w / 2 - (i - 0.5) * w / n   -- 屏幕的 −Z 对着人，人的右手边是局部 −X：第一个键在人看来最左边
        local kw = math.min(0.030, w / n * 0.72)
        local sy = (side == "top") and 1 or -1
        local key = self:box(g, V(kw, 0.011, 0.010), cf * CF(x, sy * (h / 2 + bez * 0.72), -0.005), RGB(62, 64, 66))
        key.CastShadow = false
        local lb = self:box(g, V(kw * 1.25, bez * 0.40, 0.001), cf * CF(x, sy * (h / 2 + bez * 0.28), -0.0012), opt.frame or K.C.black)
        lb.CastShadow = false
        local lg = K.gui(lb, Enum.NormalId.Front, 2600, 1)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.fromScale(1, 1)
        t.BackgroundTransparency = 1
        t.Text = label
        t.TextColor3 = RGB(226, 230, 222)
        t.Font = Enum.Font.GothamBold
        t.TextScaled = true
        t.Parent = lg
        table.insert(self.softkeys, { part = key, label = label, screen = s, side = side, idx = i, col = key.Color })
      end
    end
  elseif opt.keys then
    local n = opt.keys
    for i = 1, n do
      local x = -w / 2 + (i - 0.5) * w / n
      self:box(g, V(math.min(0.022, w / n * 0.6), 0.012, 0.012), cf * CF(x, -h / 2 - bez * 0.55, -0.004), RGB(70, 72, 74))
      self:box(g, V(math.min(0.022, w / n * 0.6), 0.012, 0.012), cf * CF(x, h / 2 + bez * 0.55, -0.004), RGB(70, 72, 74))
    end
  end
  table.insert(self.screens, s)
  return s
end
-- 灯：一个看不见的小零件挂 PointLight / SpotLight；role 给 Interior 分组控制（dome 车内照明、flash 炮口火光透进来、warn 告警红灯……）
function B:light(g, cf, role, color, range, bright, spotAngle, face)
  local p = self:box(g, V(0.02, 0.02, 0.02), cf, color, MAT.SmoothPlastic)
  p.Transparency = 1
  local L
  if spotAngle then
    L = Instance.new("SpotLight")
    L.Angle = spotAngle
    L.Face = face or Enum.NormalId.Bottom
  else
    L = Instance.new("PointLight")
  end
  L.Color = color
  L.Range = range * S
  L.Brightness = bright
  L.Shadows = true
  L.Parent = p
  table.insert(self.lights, { L = L, role = role, color = color, bright = bright, part = p })
  return L
end
-- 指示灯（霓虹，会发光）：role 由 Interior 按状态点亮 / 熄灭 / 闪
function B:led(g, cf, color, dia, role)
  local p = self:add(g, "Part", V(dia or 0.008, dia or 0.008, dia or 0.008), cf, color, MAT.Neon, BALL)
  p.CastShadow = false
  table.insert(self.leds, { p = p, role = role, on = color, off = color:Lerp(RGB(0, 0, 0), 0.82) })
  return p
end
function B:name(key, x) self.named[key] = x return x end

---------------------------------------------------------------- 常用件

-- 面板上的小件：cf 是面板表面上的一点，cf 的 −Z（LookVector）朝着看面板的人；东西往 −Z 凸出来，面板本体在 +Z 后面
-- 拨动开关（底座 + 拨杆，可带护盖）
function B:toggle(g, cf, guard)
  self:box(g, V(0.012, 0.012, 0.008), cf * CF(0, 0, -0.004), K.C.steel, MAT.Metal)
  self:tube(g, (cf * CF(0, 0, -0.006)).Position, (cf * CF(0, 0.008, -0.022)).Position, 0.004, K.C.lgray, MAT.Metal)
  if guard then self:box(g, V(0.018, 0.026, 0.004), cf * CF(0, 0.004, -0.02) * ANG(rad(60), 0, 0), K.C.red, MAT.SmoothPlastic) end
end
-- 旋钮（带指示线）
function B:knob(g, cf, dia, col)
  dia = dia or 0.022
  self:cylZ(g, 0.014, dia, cf * CF(0, 0, -0.007), col or K.C.black, MAT.SmoothPlastic)
  self:box(g, V(0.002, dia * 0.45, 0.002), cf * CF(0, dia * 0.22, -0.0145), K.C.white)
end
-- 按钮
function B:button(g, cf, col, w)
  w = w or 0.014
  self:box(g, V(w, w, 0.008), cf * CF(0, 0, -0.004), col or K.C.dark, MAT.SmoothPlastic)
end
-- 一块开关面板：底板 + 一格格的开关 / 旋钮 / 按钮 / 指示灯，标签条（rows × cols 格）；kinds 不给就按位置轮着放
function B:panel(g, w, h, cf, rows, cols, col, opt)
  opt = opt or {}
  local d = opt.depth or 0.04
  self:box(g, V(w, h, d), cf * CF(0, 0, d / 2), col or K.C.dark, MAT.SmoothPlastic)
  local kinds = opt.kinds or { "t", "k", "t", "b", "l", "t", "k", "b" }
  local n = 0
  for r = 1, rows do
    for c = 1, cols do
      n += 1
      local x = -w / 2 + (c - 0.5) * w / cols
      local y = h / 2 - (r - 0.5) * h / rows
      local k = kinds[(n - 1) % #kinds + 1]
      local q = cf * CF(x, y - h / rows * 0.12, 0)
      if k == "t" then self:toggle(g, q, opt.guard and (n % 5 == 0))
      elseif k == "k" then self:knob(g, q, math.min(w / cols, h / rows) * 0.42)
      elseif k == "b" then self:button(g, q, (n % 4 == 0) and K.C.red or K.C.black)
      elseif k == "l" then self:led(g, q * CF(0, 0, -0.004), (n % 3 == 0) and K.C.amber or K.C.green, 0.009, opt.ledRole)
      end
      if opt.labels ~= false then   -- 每格上面一条白色小字条（看不清写的什么，看着像）
        local lb = self:box(g, V(w / cols * 0.62, 0.006, 0.002), cf * CF(x, y + h / rows * 0.3, -0.001), RGB(200, 200, 190))
        lb.CastShadow = false
      end
    end
  end
end
-- 观察镜（潜望镜下半截）：钢壳 + 一块玻璃（玻璃是透的：外面的东西就从这里看得见）+ 上面的护额垫
function B:periscope(g, cf, w, h, d, opt)
  opt = opt or {}
  local col = opt.col or K.C.dark
  self:box(g, V(w + 0.03, 0.02, d + 0.02), cf * CF(0, h / 2 + 0.01, 0), col, MAT.Metal)
  self:box(g, V(0.015, h, d), cf * CF(-w / 2 - 0.0075, 0, 0), col, MAT.Metal)
  self:box(g, V(0.015, h, d), cf * CF(w / 2 + 0.0075, 0, 0), col, MAT.Metal)
  self:box(g, V(w + 0.03, 0.015, d + 0.02), cf * CF(0, -h / 2 - 0.0075, 0), col, MAT.Metal)
  local gl = self:box(g, V(w, h, 0.006), cf * CF(0, 0, -d / 2 + 0.003), RGB(110, 140, 150), MAT.Glass)
  gl.Transparency = 0.72
  gl.CastShadow = false
  if opt.pad ~= false then   -- 护额垫（黑橡胶）
    self:box(g, V(w + 0.02, 0.03, 0.03), cf * CF(0, h / 2 + 0.035, d / 2 - 0.01), K.C.rubber, MAT.Fabric)
  end
  return gl
end
-- 座椅：坐垫 + 靠背 + 钢架 + 调节手柄；cf 是坐垫上表面中心，−Z 朝前
function B:seat(g, cf, opt)
  opt = opt or {}
  local w, dp, bh = opt.w or 0.42, opt.d or 0.40, opt.back or 0.48
  local col = opt.col or K.C.fabric
  local fr = opt.frame or K.C.gray
  self:box(g, V(w, 0.07, dp), cf * CF(0, -0.035, 0), col, MAT.Fabric)
  self:box(g, V(w - 0.04, 0.03, dp - 0.04), cf * CF(0, -0.085, 0), fr, MAT.Metal)
  if bh > 0 then
    local rec = rad(opt.recline or 12)
    local bc = cf * CF(0, 0, dp / 2) * ANG(rec, 0, 0)
    self:box(g, V(w, bh, 0.07), bc * CF(0, bh / 2 + 0.02, 0.035), col, MAT.Fabric)
    self:box(g, V(w - 0.06, bh - 0.06, 0.02), bc * CF(0, bh / 2 + 0.02, 0.08), fr, MAT.Metal)
    if opt.head then self:box(g, V(w * 0.6, 0.16, 0.07), bc * CF(0, bh + 0.12, 0.035), col, MAT.Fabric) end
  end
  if opt.post then   -- 立柱（炮塔里的座椅多是一根立柱挂在炮塔篮上）
    local top = cf * CF(0, -0.1, 0)
    self:cylY(g, opt.post, 0.05, top * CF(0, -opt.post / 2, 0), fr, MAT.Metal)
    self:box(g, V(0.16, 0.012, 0.16), top * CF(0, -opt.post, 0), fr, MAT.Metal)
  end
  self:box(g, V(0.012, 0.012, 0.09), cf * CF(w / 2 + 0.006, -0.06, -dp / 2 + 0.06), K.C.black)   -- 调节手柄
end
-- 扶手 / 抓手（U 形钢管）
function B:grab(g, a, b, off, dia, col)
  dia = dia or 0.022
  col = col or K.C.lgray
  self:tube(g, a, a + off, dia, col, MAT.Metal)
  self:tube(g, a + off, b + off, dia, col, MAT.Metal)
  self:tube(g, b + off, b, dia, col, MAT.Metal)
end
-- 灭火瓶（红瓶 + 阀头 + 卡箍）
function B:extinguisher(g, cf, len, dia)
  len, dia = len or 0.42, dia or 0.13
  self:cylY(g, len, dia, cf, K.C.red, MAT.SmoothPlastic)
  self:ball(g, dia, cf * CF(0, len / 2, 0), K.C.red, MAT.SmoothPlastic)
  self:cylY(g, 0.06, 0.03, cf * CF(0, len / 2 + dia * 0.45, 0), K.C.steel, MAT.Metal)
  self:box(g, V(0.09, 0.012, 0.02), cf * CF(0.03, len / 2 + dia * 0.5, 0), K.C.black)
  for _, y in ipairs({ -len * 0.25, len * 0.25 }) do self:cylY(g, 0.02, dia + 0.01, cf * CF(0, y, 0), K.C.dark, MAT.Metal) end
end
-- 电台 / 电子盒（一个机箱 + 前面板上的旋钮、接头、指示灯、提手）
function B:radio(g, w, h, d, cf, col)
  col = col or RGB(70, 76, 58)
  self:box(g, V(w, h, d), cf * CF(0, 0, d / 2), col, MAT.SmoothPlastic)
  for i = 1, 3 do self:knob(g, cf * CF(-w / 2 + w * (i / 4), h * 0.18, 0), math.min(w, h) * 0.18, K.C.black) end
  for i = 1, 4 do self:cylZ(g, 0.02, 0.026, cf * CF(-w / 2 + w * (i / 5), -h * 0.25, -0.01), K.C.dark, MAT.Metal) end
  self:led(g, cf * CF(w * 0.4, h * 0.35, -0.004), K.C.green, 0.008, "radio")
  self:grab(g, (cf * CF(-w / 2 + 0.02, h / 2 - 0.02, 0)).Position, (cf * CF(-w / 2 + 0.02, -h / 2 + 0.02, 0)).Position, (cf.LookVector * 0.035), 0.012, K.C.black)
end

---------------------------------------------------------------- 乘员小人（R15 关节 + 反向运动学）

local JN = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
  "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local UPV = V(0, 1, 0)
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
K.clamp = clamp

local function quiet(p, anchored)
  p.Anchored = anchored == true
  p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
  p.Massless = true
end
local function mkPart(parent, size, color, mat, shape)
  local p = Instance.new("Part")
  if shape then p.Shape = shape end
  p.Size, p.Color = size, color
  p.Material = mat or MAT.SmoothPlastic
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
  quiet(p, false)
  p.Parent = parent
  return p
end
local function weld(p0, p1, c0)
  local w = Instance.new("Weld")
  w.Part0, w.Part1, w.C0 = p0, p1, c0
  w.Parent = p1
  return w
end
local function motor(name, p0, p1, c0, c1)
  local m = Instance.new("Motor6D")
  m.Name, m.Part0, m.Part1, m.C0, m.C1 = name, p0, p1, c0, c1 or CF()
  m.Parent = p1
  return m
end

-- 乘员的穿戴：tank_us 美军坦克兵（狼棕连体服、DH-132 车组头盔带耳罩和送话器）、tank_cn 解放军坦克兵（深绿连体服、黑色软坦克帽）、
--   pilot_us / pilot_cn 飞行员（飞行服、头盔护目镜、氧气面罩）、crew 普通车组（作训服、头盔）
local DRESS = {
  tank_us = { top = RGB(150, 132, 100), low = RGB(138, 120, 90), glove = RGB(96, 84, 64), boot = RGB(120, 96, 66), helm = RGB(158, 140, 104), kind = "cvc" },
  tank_cn = { top = RGB(58, 74, 52), low = RGB(50, 64, 46), glove = RGB(30, 30, 28), boot = RGB(26, 24, 22), helm = RGB(26, 26, 26), kind = "soft" },
  pilot_us = { top = RGB(112, 116, 90), low = RGB(106, 110, 86), glove = RGB(44, 40, 34), boot = RGB(30, 28, 26), helm = RGB(110, 112, 110), kind = "jet" },
  pilot_cn = { top = RGB(70, 82, 70), low = RGB(64, 76, 64), glove = RGB(30, 30, 28), boot = RGB(26, 24, 22), helm = RGB(232, 232, 228), kind = "jet" },
  heli_us = { top = RGB(112, 116, 90), low = RGB(106, 110, 86), glove = RGB(44, 40, 34), boot = RGB(30, 28, 26), helm = RGB(80, 84, 78), kind = "heli" },
  heli_cn = { top = RGB(70, 82, 70), low = RGB(64, 76, 64), glove = RGB(30, 30, 28), boot = RGB(26, 24, 22), helm = RGB(60, 70, 62), kind = "heli" },
  crew_us = { top = RGB(150, 132, 100), low = RGB(138, 120, 90), glove = RGB(40, 38, 34), boot = RGB(120, 96, 66), helm = RGB(146, 128, 96), kind = "ach" },
  crew_cn = { top = RGB(70, 86, 58), low = RGB(62, 76, 52), glove = RGB(30, 30, 28), boot = RGB(26, 24, 22), helm = RGB(80, 92, 64), kind = "ach" },
}
K.DRESS = DRESS
local SKIN = RGB(226, 186, 146)

-- 头上戴的（按 R15 头 1.2 格高算，k 缩放）
local function headgear(m, head, dress, k)
  local col = dress.helm
  local function P(size, cf, color, mat, shape, mesh)
    local p = mkPart(m, size * k, color or col, mat or MAT.SmoothPlastic, shape)
    if mesh then
      local sm = Instance.new("SpecialMesh")
      sm.MeshType = Enum.MeshType.Sphere
      sm.Parent = p
    end
    weld(head, p, CF(cf.Position * k) * cf.Rotation)
    p.Name = "Gear"
    return p
  end
  if dress.kind == "cvc" then   -- 美军 DH-132：圆头壳、两侧大耳罩、左边伸出来的送话器
    P(V(1.46, 0.95, 1.52), CF(0, 0.38, 0.06), col, MAT.SmoothPlastic, nil, true)
    for _, s in ipairs({ -1, 1 }) do P(V(0.24, 0.62, 0.62), CF(s * 0.7, -0.02, 0.06) * ANG(0, 0, PI / 2), col:Lerp(RGB(0, 0, 0), 0.15), MAT.SmoothPlastic, CYL) end
    P(V(0.06, 0.06, 0.5), CF(-0.62, -0.32, -0.28) * ANG(0, rad(28), 0), RGB(28, 28, 28), MAT.SmoothPlastic)
    P(V(0.13, 0.13, 0.13), CF(-0.42, -0.36, -0.55), RGB(28, 28, 28), MAT.SmoothPlastic, BALL)
    P(V(1.12, 0.16, 0.1), CF(0, 0.5, -0.66), RGB(40, 40, 38), MAT.SmoothPlastic)   -- 护目镜（推在头盔上）
  elseif dress.kind == "soft" then   -- 解放军坦克帽：黑色软帽、三道加厚棱、耳罩、喉部送话器的带子
    P(V(1.36, 0.9, 1.44), CF(0, 0.34, 0.04), col, MAT.Fabric, nil, true)
    for i = -1, 1 do P(V(0.16, 0.85, 1.36), CF(i * 0.34, 0.36, 0.04), col:Lerp(RGB(255, 255, 255), 0.04), MAT.Fabric, nil, true) end
    for _, s in ipairs({ -1, 1 }) do P(V(0.18, 0.5, 0.5), CF(s * 0.66, -0.06, 0.06) * ANG(0, 0, PI / 2), col, MAT.Fabric, CYL) end
    P(V(1.1, 0.08, 0.08), CF(0, -0.62, 0.05), RGB(20, 20, 20), MAT.Fabric)
  elseif dress.kind == "jet" then   -- 飞行头盔 + 护目镜 + 氧气面罩和软管
    P(V(1.5, 1.15, 1.6), CF(0, 0.3, 0.05), col, MAT.SmoothPlastic, nil, true)
    P(V(1.3, 0.42, 0.2), CF(0, 0.05, -0.72) * ANG(rad(8), 0, 0), RGB(20, 22, 26), MAT.Glass).Transparency = 0.25
    P(V(0.46, 0.42, 0.34), CF(0, -0.38, -0.62), RGB(54, 58, 56), MAT.SmoothPlastic)
    P(V(0.12, 0.12, 0.7), CF(0.2, -0.62, -0.3) * ANG(rad(-40), rad(20), 0), RGB(40, 44, 42), MAT.SmoothPlastic, nil)
  elseif dress.kind == "heli" then   -- 直升机飞行员头盔（带单目头盔显示器 / 夜视仪支架）
    P(V(1.5, 1.1, 1.58), CF(0, 0.3, 0.05), col, MAT.SmoothPlastic, nil, true)
    P(V(0.26, 0.2, 0.36), CF(0.36, 0.22, -0.74), RGB(30, 30, 32), MAT.Metal)
    P(V(0.14, 0.14, 0.14), CF(0.38, 0.04, -0.88), RGB(60, 180, 90), MAT.Neon, BALL)
  else   -- 普通头盔
    P(V(1.42, 0.86, 1.5), CF(0, 0.42, 0.04), col, MAT.Fabric, nil, true)
    P(V(1.46, 0.14, 1.54), CF(0, 0.08, 0.04), col:Lerp(RGB(0, 0, 0), 0.25), MAT.Fabric)
  end
end

-- 零件拼的小人（没有 R15 模板时）：关节名字、层级照 R15
local function partRig(dress)
  local m = Instance.new("Model")
  m.Name = "Crew"
  local function P(name, size, color)
    local p = mkPart(m, size, color)
    p.Name = name
    return p
  end
  local hrp = P("HumanoidRootPart", V(2, 2, 1), dress.top)
  hrp.Transparency, hrp.Anchored = 1, true
  local lt = P("LowerTorso", V(1.9, 0.45, 0.95), dress.low)
  local ut = P("UpperTorso", V(2, 1.6, 1), dress.top)
  local head = P("Head", V(1.2, 1.2, 1.2), SKIN)
  local hm = Instance.new("SpecialMesh")
  hm.MeshType = Enum.MeshType.Head
  hm.Scale = V(1, 1, 1)
  hm.Parent = head
  motor("Root", hrp, lt, CF(0, -0.8, 0), CF())
  motor("Waist", lt, ut, CF(0, 0.2, 0), CF(0, -0.8, 0))
  motor("Neck", ut, head, CF(0, 0.8, 0), CF(0, -0.55, 0))
  for _, s in ipairs({ -1, 1 }) do
    local side = (s < 0) and "Left" or "Right"
    local ua = P(side .. "UpperArm", V(0.95, 1.2, 0.95), dress.top)
    local la = P(side .. "LowerArm", V(0.9, 1.1, 0.9), dress.top)
    local hd = P(side .. "Hand", V(0.85, 0.32, 0.85), dress.glove)
    motor(side .. "Shoulder", ut, ua, CF(s * 1.5, 0.6, 0), CF(0, 0.4, 0))
    motor(side .. "Elbow", ua, la, CF(0, -0.55, 0), CF(0, 0.5, 0))
    motor(side .. "Wrist", la, hd, CF(0, -0.45, 0), CF(0, 0.1, 0))
    local ul = P(side .. "UpperLeg", V(0.95, 1.2, 0.95), dress.low)
    local ll = P(side .. "LowerLeg", V(0.9, 1.1, 0.9), dress.low)
    local ft = P(side .. "Foot", V(0.9, 0.3, 1.2), dress.boot)
    motor(side .. "Hip", lt, ul, CF(s * 0.5, -0.2, 0), CF(0, 0.5, 0))
    motor(side .. "Knee", ul, ll, CF(0, -0.45, 0), CF(0, 0.45, 0))
    motor(side .. "Ankle", ll, ft, CF(0, -0.4, 0), CF(0, 0.05, 0.15))
  end
  return m, hrp, head
end
-- 真人比例的小人（车里、座舱里都用它）：R15 的方块小人四肢有 0.34 米粗、胳膊腿太短，坐进座舱够不着杆和脚蹬、低头满眼是方块；
--   这个按 1.78 米的成年男子量的（肩宽 0.40、上臂 0.29、前臂 0.26、大腿 0.43、小腿 0.42 米），四肢、躯干是椭球（像人体模型），关节名字和层级照 R15
local function slimRig(dress)
  local m = Instance.new("Model")
  m.Name = "Crew"
  local function P(name, size, color, round)
    local p = mkPart(m, size * S, color)
    p.Name = name
    if round then
      local sm = Instance.new("SpecialMesh")
      sm.MeshType = Enum.MeshType.Sphere
      sm.Parent = p
    end
    return p
  end
  local function M(name, p0, p1, c0, c1) return motor(name, p0, p1, CF(c0 * S), CF((c1 or V()) * S)) end
  local hrp = P("HumanoidRootPart", V(0.5, 0.5, 0.3), dress.top)
  hrp.Transparency, hrp.Anchored = 1, true
  local lt = P("LowerTorso", V(0.34, 0.18, 0.22), dress.low, true)
  local ut = P("UpperTorso", V(0.40, 0.52, 0.25), dress.top, true)
  local head = P("Head", V(0.19, 0.23, 0.21), SKIN)
  local hm = Instance.new("SpecialMesh")
  hm.MeshType = Enum.MeshType.Head
  hm.Parent = head
  P("Neck", V(0.11, 0.10, 0.11), SKIN, true).Name = "NeckSkin"
  M("Root", hrp, lt, V(0, -0.05, 0))
  M("Waist", lt, ut, V(0, 0.07, 0), V(0, -0.24, 0))
  M("Neck", ut, head, V(0, 0.27, 0), V(0, -0.115, 0))
  local nk = m:FindFirstChild("NeckSkin")
  weld(ut, nk, CF(0, 0.25 * S, 0))
  for _, sd in ipairs({ -1, 1 }) do
    local side = (sd < 0) and "Left" or "Right"
    local ua = P(side .. "UpperArm", V(0.105, 0.32, 0.105), dress.top, true)
    local la = P(side .. "LowerArm", V(0.09, 0.28, 0.09), dress.top, true)
    local hd = P(side .. "Hand", V(0.085, 0.11, 0.045), dress.glove)
    M(side .. "Shoulder", ut, ua, V(sd * 0.19, 0.19, 0), V(0, 0.14, 0))
    M(side .. "Elbow", ua, la, V(0, -0.15, 0), V(0, 0.125, 0))
    M(side .. "Wrist", la, hd, V(0, -0.13, 0), V(0, 0.05, 0))
    local ul = P(side .. "UpperLeg", V(0.15, 0.47, 0.15), dress.low, true)
    local ll = P(side .. "LowerLeg", V(0.11, 0.45, 0.11), dress.low, true)
    local ft = P(side .. "Foot", V(0.10, 0.09, 0.27), dress.boot)
    M(side .. "Hip", lt, ul, V(sd * 0.095, -0.05, 0), V(0, 0.215, 0))
    M(side .. "Knee", ul, ll, V(0, -0.215, 0), V(0, 0.205, 0))
    M(side .. "Ankle", ll, ft, V(0, -0.21, 0), V(0, 0.035, 0.08))
  end
  return m, hrp, head
end
-- R15 模板克隆
local function rigFromTemplate(dress)
  local tpl = RS:FindFirstChild("BotRig")
  if not tpl then return nil end
  local m = tpl:Clone()
  m.Name = "Crew"
  local hrp = m:FindFirstChild("HumanoidRootPart")
  local head = m:FindFirstChild("Head")
  local hum = m:FindFirstChildOfClass("Humanoid")
  if not hrp or not head or not hum then m:Destroy() return nil end
  for _, p in ipairs(m:GetDescendants()) do
    if p:IsA("BasePart") then
      quiet(p, p == hrp)
      local n = p.Name
      if n == "Head" then p.Color = SKIN
      elseif string.find(n, "Hand") then p.Color = dress.glove
      elseif string.find(n, "Foot") then p.Color = dress.boot
      elseif string.find(n, "Leg") or n == "LowerTorso" then p.Color = dress.low
      elseif string.find(n, "Arm") or n == "UpperTorso" then p.Color = dress.top end
      p.CastShadow = true
    elseif p:IsA("BodyColors") or p:IsA("Accessory") or p:IsA("Shirt") or p:IsA("Pants") then
      p:Destroy()
    end
  end
  hrp.Transparency = 1
  hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
  hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
  pcall(function() hum.EvaluateStateMachine = false end)
  local an = hum:FindFirstChildOfClass("Animator")
  if an then an:Destroy() end
  return m, hrp, head
end

-- 两节肢体的反向运动学（同 Soldier.lua）：P0 是父零件（躯干）的世界姿态，末端关节放到 W，肘 / 膝往 pole 那边弯
local function ik(Lb, P0, W, pole, leg, endRot)
  local A, Bj, C = Lb.a, Lb.b, Lb.c
  local la, lb = Lb.la, Lb.lb
  local Sp = P0 * A.c0.Position
  local d = W - Sp
  local L = d.Magnitude
  local du = (L > 1e-4) and d / L or V(0, -1, 0)
  L = clamp(L, math.abs(la - lb) + 0.02, (la + lb) * 0.999)
  local ca = clamp((la * la + L * L - lb * lb) / (2 * la * L), -1, 1)
  local sa = math.sqrt(math.max(0, 1 - ca * ca))
  local pp = pole - du * pole:Dot(du)
  if pp.Magnitude < 1e-4 then pp = (math.abs(du.Y) < 0.9) and UPV:Cross(du) or V(1, 0, 0) end
  pp = pp.Unit
  local E = Sp + du * (la * ca) + pp * (la * sa)
  local Wc = Sp + du * L
  local hx = leg and du:Cross(pp) or pp:Cross(du)
  local y1 = (Sp - E).Unit
  local x1 = hx - y1 * hx:Dot(y1)
  x1 = (x1.Magnitude > 1e-4) and x1.Unit or V(1, 0, 0)
  local r1 = CFrame.fromMatrix(Vector3.zero, x1, y1, x1:Cross(y1))
  local y2 = (E - Wc).Unit
  local x2 = x1 - y2 * x1:Dot(y2)
  x2 = (x2.Magnitude > 1e-4) and x2.Unit or x1
  local r2 = CFrame.fromMatrix(Vector3.zero, x2, y2, x2:Cross(y2))
  local r3 = endRot or r2
  return CF(Sp - r1:VectorToWorldSpace(A.c1.Position)) * r1, CF(E - r2:VectorToWorldSpace(Bj.c1.Position)) * r2,
    CF(Wc - r3:VectorToWorldSpace(C.c1.Position)) * r3
end
local function setJ(Jx, P0, P1) Jx.m.C0 = P0:Inverse() * P1 * Jx.c1 end

-- 做一个乘员：返回 { model, hrp, J, set(pose) }；dress 见上面的 DRESS
function K.crew(dressKey)
  local dress = DRESS[dressKey] or DRESS.crew_us
  local m, hrp, head = slimRig(dress)   -- 真人比例（R15 模板 / 方块小人只在调试时用：rigFromTemplate、partRig）
  local J = {}
  for _, d in ipairs(m:GetDescendants()) do
    if d:IsA("Motor6D") then J[d.Name] = { m = d, c0 = d.C0, c1 = d.C1, c1i = d.C1:Inverse() } end
  end
  for _, n in ipairs(JN) do
    if not J[n] then m:Destroy() return nil end
  end
  local k = head.Size.Y / 1.2
  headgear(m, head, dress, k)
  local function limb(a, b, c)
    local A, Bj, C = J[a], J[b], J[c]
    return { a = A, b = Bj, c = C, la = (Bj.c0.Position - A.c1.Position).Magnitude, lb = (C.c0.Position - Bj.c1.Position).Magnitude }
  end
  local f = { model = m, hrp = hrp, head = head, J = J, dress = dress,
    LA = limb("LeftShoulder", "LeftElbow", "LeftWrist"), RA = limb("RightShoulder", "RightElbow", "RightWrist"),
    LL = limb("LeftHip", "LeftKnee", "LeftAnkle"), RL = limb("RightHip", "RightKnee", "RightAnkle") }
  -- 头和头上戴的（第一人称时藏起来，自己看得见自己的手和腿）
  f.headParts = { head }
  for _, p in ipairs(m:GetDescendants()) do
    if p:IsA("BasePart") and (p.Name == "Gear" or p.Name == "Head" or p.Name == "NeckSkin" or p:IsDescendantOf(head)) then table.insert(f.headParts, p) end
    if p:IsA("Decal") and p.Parent == head then table.insert(f.headParts, p) end
  end
  -- 摆姿势（世界坐标，格）：pelvis 骨盆（下躯干）的姿态；chest 上身相对骨盆的转角（CFrame）；look 头朝哪看（世界方向）；
  --   lh / rh 左右手掌心的位置，lf / rf 脚踝的位置；elbow / knee 往哪边弯（世界方向）
  function f.set(P)
    local hcf = P.pelvis * J.Root.c1 * J.Root.c0:Inverse()   -- 根零件放在骨盆对应的位置（关节 C0 保持原样）
    hrp.CFrame = hcf
    J.Root.m.C0 = J.Root.c0
    local lt = P.pelvis
    local ut = lt * J.Waist.c0 * (P.chest or CF()) * J.Waist.c1i
    setJ(J.Waist, lt, ut)
    if P.look and P.look.Magnitude > 1e-4 then
      -- 头：脖子关节点不动，脸朝 look（离上身正前方超过 75° 的拉回来，脖子不拧断）
      local jp = (ut * J.Neck.c0).Position
      local fwd = P.look.Unit
      local tf = ut.LookVector
      local a = math.acos(clamp(fwd:Dot(tf), -1, 1))
      if a > rad(75) then fwd = tf:Lerp(fwd, rad(75) / a).Unit end
      local R = CFrame.lookAt(Vector3.zero, fwd, ut.UpVector)
      local Hw = CF(jp - R:VectorToWorldSpace(J.Neck.c1.Position)) * R
      setJ(J.Neck, ut, Hw)
    else
      J.Neck.m.C0 = J.Neck.c0
    end
    local up = ut.UpVector
    local rt = ut.RightVector
    local function arm(Lb, W, side, pole)
      if not W then
        -- 没给手的位置：手臂自然垂下、略往前
        W = (ut * CF(side * 1.1 * k, -1.5 * k, -0.45 * k)).Position
      end
      local e = pole or (rt * side * 0.8 - up * 0.6 + ut.LookVector * 0.1)
      local a, b, c = ik(Lb, ut, W, e, false, nil)
      setJ(Lb.a, ut, a)
      setJ(Lb.b, a, b)
      setJ(Lb.c, b, c)
    end
    arm(f.LA, P.lh, -1, P.lelbow)
    arm(f.RA, P.rh, 1, P.relbow)
    local function leg(Lb, W, side, pole)
      if not W then W = (lt * CF(side * 0.5 * k, -2.2 * k, -1.2 * k)).Position end
      local e = pole or (lt.LookVector * 1 + rt * side * 0.15)
      local a, b, c = ik(Lb, lt, W, e, true, P.footRot)
      setJ(Lb.a, lt, a)
      setJ(Lb.b, a, b)
      setJ(Lb.c, b, c)
    end
    leg(f.LL, P.lf, -1, P.lknee)
    leg(f.RL, P.rf, 1, P.rknee)
  end
  f.torsoParts = {}
  for _, n in ipairs({ "UpperTorso", "LowerTorso" }) do
    local p = m:FindFirstChild(n)
    if p then table.insert(f.torsoParts, p) end
  end
  function f.torsoVisible(on)
    for _, p in ipairs(f.torsoParts) do p.LocalTransparencyModifier = on and 0 or 1 end
  end
  function f.headVisible(on)
    for _, p in ipairs(f.headParts) do
      if p:IsA("BasePart") then p.LocalTransparencyModifier = on and 0 or 1
      elseif p:IsA("Decal") then p.Transparency = on and 0 or 1 end
    end
  end
  return f
end

K.rigFromTemplate, K.partRig = rigFromTemplate, partRig   -- 调试用（R15 模板、方块小人）
return K
