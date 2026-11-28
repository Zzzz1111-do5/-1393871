-- 全面大战场（客户端）——飞机的挂载表（战雷的「挂载」窗口）
--   用户 11-28（给了战雷截图）：「飞机选挂载我还是没找到位置 你给我做成这样」——一行一套挂载（对空 / 对地 / 自定义三组）、一列一个挂点
--   （左翼尖 → 右翼尖），右边清单和性能变化；点一行就换成它（即时存，同整备）；「创建 / 细调」打开整备的挂载页
--   11-28 晚（用户「改挂载界面没有设计感 我需要惊艳的效果」）：整屏重做成出击前的「简报台」——
--   · 上半屏：真 3D 的这架飞机（AirModels 拼的、挂着这一套弹；前下方仰看，翼下的弹都看得见），背后蓝图网格、一道横向柔光、四角取景框；
--     每个挂了东西的挂点一个琥珀小菱形，引线拉到两边的标签（型号 × 枚数）；左键拖着转飞机（转的时候标签先收起来，停了再出来）
--   · 左上「当前挂载」：一种弹一行（枚数、型号、类别）；右上「性能变化 · 比空挂」：数值 + 一根条（变差红、变好绿，换挂载时滚过去）
--   · 下半屏：预设表。表头画一架俯视的小飞机（机翼一条线、机身一块、每个挂点一个刻度和编号），和下面的格子一列一列对齐；
--     一行一套：名字（预设名 + 挂了什么）、每个挂点一格（弹的剪影 + 型号 × 枚数）。悬停一行，上面的 3D 和数字先换成那一套预览（琥珀「预览」）；
--     点一下换成它（即时存），选中的那一行琥珀细描边 + 贴底 2 像素琥珀线，换的那一下一道光扫过去
--   · 底部：「创建 / 细调（整备）」、提示、「完成」（这一屏唯一的主按钮）；Esc、右上 ✕ 关
--   打开：G.openLoadout(科技树键)——机库里飞机的「挂载」键、出击页左栏的「挂载表」
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local LoadoutWin = {}

function LoadoutWin.init(G)
  local TH = require(RS:WaitForChild("Theme"))
  local AD = require(RS:WaitForChild("AirDefs"))
  local TT = require(RS:WaitForChild("TechTree"))
  local FM = nil
  pcall(function() FM = require(RS:WaitForChild("FlightModel", 5)) end)
  local AM = nil
  pcall(function() AM = require(script.Parent:WaitForChild("AirModels", 5)) end)
  local me = Players.LocalPlayer
  local RGB, U2, V2, V3 = Color3.fromRGB, UDim2, Vector2.new, Vector3.new
  local CF = CFrame.new
  local function L(zh, en) return (G.lang == "en") and en or zh end
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local TEXT, MUTE, FAINT, GOOD, BAD, AMBER = TH.C.TEXT, TH.C.MUTE, TH.C.FAINT, TH.C.GOOD, TH.C.BAD, TH.C.WARN
  local WHITE, INK = RGB(255, 255, 255), RGB(0, 0, 0)
  local function hex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local function reduced()
    local ok, v = pcall(function() return GuiService.ReducedMotionEnabled end)
    return (ok and v == true) or (G.reducedMotion and G.reducedMotion()) or false
  end
  local function tw(o, props, t, ease, delay)
    if reduced() then for k, v in pairs(props) do pcall(function() o[k] = v end) end return nil end
    return TH.tween(o, props, t, ease, delay)
  end

  -- 画布：按 1280 × 720 排版，整块按屏幕缩放（UIScale）
  local W, H = 1280, 720
  local PAD = 40
  local HERO = { x = 300, y = 74, w = 680, h = 252 }   -- 3D 飞机那一块
  local TBL = { x = PAD, y = 378, w = W - 2 * PAD, h = 284 }
  local NAMEW, ROWH, GROUPH = 300, 48, 28

  local gui = Instance.new("ScreenGui")
  gui.Name = "LoadoutWin"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 22   -- 机库（12）、出击页（13）、观战（15）上面，设置（30）下面
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  G.loadoutGui = gui   -- 测试用

  local function frame(parent, size, pos, col, tr, name)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or U2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or TH.C.PANEL, tr or 0, 0
    if name then f.Name = name end
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, xa, name)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text, t.Size, t.Position = s or "", size, pos or U2.new()
    t.TextSize, t.TextColor3, t.Font = ts or TH.S.body, col or TEXT, font or TH.F.body
    t.TextXAlignment = xa or Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    if name then t.Name = name end
    t.Parent = parent
    return t
  end
  local function line(parent, x, y, w, h, tr, col, name)
    return frame(parent, U2.fromOffset(w, h), U2.fromOffset(x, y), col or WHITE, tr or TH.A.line, name)
  end
  local function stroke(o, col, tr, th)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Transparency, s.Thickness = col or WHITE, tr or TH.A.line, th or 1
    s.Parent = o
    return s
  end
  local function round(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0, TH.R)
    c.Parent = o
    return c
  end
  local function hgrad(o, seq, rot)   -- 透明度渐变（横向：0°）
    local g = Instance.new("UIGradient")
    g.Transparency = seq
    g.Rotation = rot or 0
    g.Parent = o
    return g
  end
  local function nseq(pts)
    local kp = {}
    for _, p in ipairs(pts) do kp[#kp + 1] = NumberSequenceKeypoint.new(p[1], p[2]) end
    return NumberSequence.new(kp)
  end
  -- 按钮：主按钮白底黑字（一屏一个）；次按钮透明底 + 1 像素细线，悬停线变亮
  local function btn(parent, s, size, pos, name, primary)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text, b.Size, b.Position = s, size, pos or U2.new()
    b.Font, b.TextSize = primary and TH.F.title or TH.F.bold, TH.S.body
    b.TextColor3 = primary and TH.C.BG or TEXT
    b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = primary and TEXT or TH.C.RAISE, primary and 0 or 1, 0
    if name then b.Name = name end
    b.Parent = parent
    round(b)
    if not primary then
      local st = stroke(b, WHITE, TH.A.line)
      b.MouseEnter:Connect(function() tw(st, { Transparency = TH.A.lineHi }, "hover", "hover") tw(b, { BackgroundTransparency = 0.6 }, "hover", "hover") end)
      b.MouseLeave:Connect(function() tw(st, { Transparency = TH.A.line }, "hover", "hover") tw(b, { BackgroundTransparency = 1 }, "hover", "hover") end)
    else
      b.MouseEnter:Connect(function() tw(b, { BackgroundColor3 = WHITE }, "hover", "hover") end)
      b.MouseLeave:Connect(function() tw(b, { BackgroundColor3 = TEXT }, "hover", "hover") end)
    end
    return b
  end

  ---------------------------------------------------------------- 底子：整屏压暗、上亮下暗

  local dim = frame(gui, U2.fromScale(1, 1), nil, TH.C.BG, 0, "Dim")
  dim.Active = true   -- 点在窗口外面不穿透到下面
  do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(RGB(30, 35, 40), RGB(6, 7, 9))
    g.Rotation = 90
    g.Parent = dim
  end
  -- 外面一层按屏幕大小缩放（UIScale），里面的窗口留给 G.uiPop 弹出来（它要往窗口上挂自己的 UIScale）
  local box = frame(gui, U2.fromOffset(W, H), U2.fromScale(0.5, 0.5), INK, 1, "Box")
  box.AnchorPoint = V2(0.5, 0.5)
  local fit = Instance.new("UIScale")
  fit.Parent = box
  local win = frame(box, U2.fromScale(1, 1), U2.fromScale(0.5, 0.5), INK, 1, "Win")
  win.AnchorPoint = V2(0.5, 0.5)

  -- 蓝图网格（上半屏，3D 飞机的背后）：40 像素一格，越往两边越淡；正中一横一竖稍微亮一点
  local grid = frame(win, U2.fromOffset(W, HERO.h + 12), U2.fromOffset(0, HERO.y - 6), INK, 1, "Grid")
  grid.ClipsDescendants = true
  for x = 0, W, 40 do
    local ln = line(grid, x, 0, 1, HERO.h + 12, 0.955)
    hgrad(ln, nseq({ { 0, 1 }, { 0.25, 0.3 }, { 0.75, 0.3 }, { 1, 1 } }), 90)
    if math.abs(x - (HERO.x + HERO.w / 2)) < 1 then ln.BackgroundTransparency = 0.9 end
  end
  for y = 6, HERO.h + 6, 40 do
    local ln = line(grid, 0, y, W, 1, 0.955)
    hgrad(ln, nseq({ { 0, 1 }, { 0.3, 0.2 }, { 0.7, 0.2 }, { 1, 1 } }))
  end
  -- 横向柔光（飞机后面垫一块：白、正中 0.9 → 两边透明）和一道地平线
  local halo = frame(win, U2.fromOffset(HERO.w + 260, 170), U2.fromOffset(HERO.x - 130, HERO.y + HERO.h / 2 - 85), WHITE, 0.88, "Halo")
  hgrad(halo, nseq({ { 0, 1 }, { 0.5, 0.55 }, { 1, 1 } }))
  local halo2 = frame(halo, U2.fromScale(1, 1), nil, WHITE, 0, "V")
  halo2.BackgroundTransparency = 1
  local horizon = line(win, HERO.x - 160, HERO.y + HERO.h - 46, HERO.w + 320, 1, 0.8, WHITE, "Horizon")
  hgrad(horizon, nseq({ { 0, 1 }, { 0.5, 0.35 }, { 1, 1 } }))
  -- 四角取景框
  local function corners(x, y, w, h, len, tr)
    for _, c in ipairs({ { 0, 0, 1, 1 }, { 1, 0, -1, 1 }, { 0, 1, 1, -1 }, { 1, 1, -1, -1 } }) do
      local cx, cy = x + c[1] * w, y + c[2] * h
      line(win, (c[3] > 0) and cx or (cx - len), (c[4] > 0) and cy or (cy - 1), len, 1, tr)
      line(win, (c[3] > 0) and cx or (cx - 1), (c[4] > 0) and cy or (cy - len), 1, len, tr)
    end
  end
  corners(HERO.x - 4, HERO.y + 2, HERO.w + 8, HERO.h - 4, 18, 0.55)

  ---------------------------------------------------------------- 上面一条：标题、型号、关

  frame(win, U2.fromOffset(3, 30), U2.fromOffset(PAD, 20), AMBER, 0, "Accent")
  local title = text(win, "", U2.fromOffset(820, 34), U2.fromOffset(PAD + 14, 16), TH.S.big, TEXT, TH.F.title, nil, "Title")
  title.RichText = true
  local sub = text(win, "", U2.fromOffset(820, 18), U2.fromOffset(PAD + 15, 48), TH.S.small, MUTE, TH.F.body, nil, "Sub")
  sub.RichText = true
  local close = btn(win, "✕", U2.fromOffset(36, 36), U2.fromOffset(W - PAD - 36, 18), "Close")
  close.TextSize = TH.S.sub
  local esc = text(win, "ESC", U2.fromOffset(34, 18), U2.fromOffset(W - PAD - 36 - 46, 27), TH.S.tiny, MUTE, TH.F.mono, Enum.TextXAlignment.Center, "Esc")
  stroke(esc, WHITE, 0.8)
  round(esc)
  local hair = line(win, PAD, 72, W - 2 * PAD, 1, 0.86, WHITE, "Hair")
  hgrad(hair, nseq({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }))
  line(win, PAD, 71, 120, 2, 0, AMBER, "HairAmber")

  ---------------------------------------------------------------- 3D 飞机

  local vp = Instance.new("ViewportFrame")
  vp.Name = "Hero"
  vp.Size, vp.Position = U2.fromOffset(HERO.w, HERO.h), U2.fromOffset(HERO.x, HERO.y)
  vp.BackgroundTransparency = 1
  vp.Ambient = RGB(150, 156, 166)   -- 镜头在前下方：机腹、翼下朝着镜头，环境光亮一点（同挂载编辑器），不然一片黑
  vp.LightColor = RGB(255, 246, 232)
  vp.LightDirection = V3(0.55, -0.35, 0.75)   -- 主光从左前上方打过来（照亮机身侧面、弹的头部）
  vp.Parent = win
  local world = Instance.new("WorldModel")
  world.Parent = vp
  local vcam = Instance.new("Camera")
  vcam.FieldOfView = 24
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local flash = frame(win, U2.fromOffset(HERO.w, HERO.h), U2.fromOffset(HERO.x, HERO.y), WHITE, 1, "Flash")
  hgrad(flash, nseq({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }))
  local callouts = frame(win, U2.fromOffset(W, H), nil, INK, 1, "Callouts")
  local drag = Instance.new("TextButton")   -- 左键拖着转飞机
  drag.Name = "HeroDrag"
  drag.Text, drag.AutoButtonColor = "", false
  drag.BackgroundTransparency = 1
  drag.Size, drag.Position = U2.fromOffset(HERO.w - 260, HERO.h - 20), U2.fromOffset(HERO.x + 130, HERO.y + 10)
  drag.Parent = win
  local previewTag = text(win, L("预览", "PREVIEW"), U2.fromOffset(70, 20), U2.fromOffset(HERO.x + HERO.w / 2 - 35, HERO.y + 6), TH.S.tiny, AMBER, TH.F.bold, Enum.TextXAlignment.Center, "PreviewTag")
  stroke(previewTag, AMBER, 0.4)
  round(previewTag)
  previewTag.Visible = false
  local dragHint = text(win, L("拖动旋转", "Drag to rotate"), U2.fromOffset(160, 16), U2.fromOffset(HERO.x + HERO.w - 172, HERO.y + 10), TH.S.tiny, FAINT, TH.F.body, Enum.TextXAlignment.Right, "DragHint")

  ---------------------------------------------------------------- 左上：当前挂载；右上：性能变化

  local info = frame(win, U2.fromOffset(240, 236), U2.fromOffset(PAD, 90), INK, 1, "Info")
  text(info, L("当前挂载", "LOADOUT"), U2.fromOffset(200, 16), U2.fromOffset(0, 0), TH.S.tiny, MUTE, TH.F.bold, nil, "Head")
  line(info, 0, 20, 240, 1, 0.82)
  local sideList = text(info, "", U2.fromOffset(240, 176), U2.fromOffset(0, 30), TH.S.body, TEXT, TH.F.body, nil, "Chosen")
  sideList.RichText = true
  sideList.TextYAlignment = Enum.TextYAlignment.Top
  sideList.TextWrapped = true
  sideList.TextTruncate = Enum.TextTruncate.None
  sideList.LineHeight = 1.25
  local gunLine = text(info, "", U2.fromOffset(240, 16), U2.fromOffset(0, 214), TH.S.tiny, FAINT, TH.F.body, nil, "Gun")

  local side = frame(win, U2.fromOffset(240, 236), U2.fromOffset(W - PAD - 240, 90), INK, 1, "Side")
  local perfT = text(side, L("性能变化 · 比空挂", "VS CLEAN"), U2.fromOffset(240, 16), U2.fromOffset(0, 0), TH.S.tiny, MUTE, TH.F.bold, nil, "PerfTitle")
  line(side, 0, 20, 240, 1, 0.82)
  local perfRows = frame(side, U2.fromOffset(240, 190), U2.fromOffset(0, 28), INK, 1, "Perf")
  local noPerf = text(perfRows, L("这一型没有飞行物理数据", "No flight data for this type"), U2.fromOffset(240, 18), U2.fromOffset(0, 0), TH.S.small, FAINT, TH.F.body, nil, "NoPerf")
  noPerf.Visible = false
  local note = text(side, L("按这一套挂载、满内油实时算", "Live, full internal fuel"), U2.fromOffset(240, 16), U2.fromOffset(0, 220), TH.S.tiny, FAINT, TH.F.body)
  local PERF = {
    { id = "w", label = L("外挂重量", "stores weight"), unit = L("千克", "kg"), worseUp = true, fmt = "%+.0f", scale = 3000 },
    { id = "d", label = L("阻力", "drag"), unit = "%", worseUp = true, fmt = "%+.0f", scale = 80 },
    { id = "v", label = L("最大速度", "top speed"), unit = "km/h", worseUp = false, fmt = "%+.0f", scale = 160 },
    { id = "c", label = L("爬升率", "climb rate"), unit = "m/s", worseUp = false, fmt = "%+.1f", scale = 60 },
    { id = "t", label = L("盘旋一圈", "turn time"), unit = L("秒", "s"), worseUp = true, fmt = "%+.1f", scale = 6 },
  }
  for i, m in ipairs(PERF) do
    local y = (i - 1) * 38
    local row = frame(perfRows, U2.fromOffset(240, 36), U2.fromOffset(0, y), INK, 1, "Row_" .. m.id)
    m.row = row
    m.name = text(row, m.label, U2.fromOffset(120, 18), U2.fromOffset(0, 0), TH.S.small, MUTE, TH.F.body, nil, "Label")
    m.abs = text(row, "", U2.fromOffset(110, 14), U2.fromOffset(0, 18), TH.S.tiny, FAINT, TH.F.mono, nil, "Abs")
    m.val = text(row, "", U2.fromOffset(130, 20), U2.fromOffset(110, -1), TH.S.body, TEXT, TH.F.mono, Enum.TextXAlignment.Right, "Perf_" .. m.label)
    line(row, 110, 24, 130, 2, 0.9, WHITE, "Track")
    m.bar = frame(row, U2.fromOffset(0, 2), U2.fromOffset(110, 24), MUTE, 0, "Bar")
    line(row, 110, 21, 1, 8, 0.6, WHITE, "Zero")
  end

  ---------------------------------------------------------------- 预设表：表头（俯视的小飞机，和格子一列一列对齐）、表、底部

  local plan = frame(win, U2.fromOffset(TBL.w, 40), U2.fromOffset(TBL.x, TBL.y - 44), INK, 1, "Plan")
  local tableF = Instance.new("ScrollingFrame")
  tableF.Name = "Table"
  tableF.Size, tableF.Position = U2.fromOffset(TBL.w, TBL.h), U2.fromOffset(TBL.x, TBL.y)
  tableF.BackgroundTransparency, tableF.BorderSizePixel = 1, 0
  tableF.ScrollBarThickness = 4
  tableF.ScrollBarImageColor3 = WHITE
  tableF.ScrollBarImageTransparency = 0.6
  tableF.ScrollingDirection = Enum.ScrollingDirection.Y
  tableF.CanvasSize = U2.new()
  tableF.Parent = win
  -- 表上下两头淡出（滚动时行从边上淡进来）
  local fadeTop = frame(win, U2.fromOffset(TBL.w, 10), U2.fromOffset(TBL.x, TBL.y), TH.C.BG, 0, "FadeTop")
  hgrad(fadeTop, nseq({ { 0, 0.2 }, { 1, 1 } }), 90)
  local fadeBot = frame(win, U2.fromOffset(TBL.w, 14), U2.fromOffset(TBL.x, TBL.y + TBL.h - 14), TH.C.BG, 0, "FadeBot")
  hgrad(fadeBot, nseq({ { 0, 1 }, { 1, 0.1 } }), 90)
  fadeTop.Active, fadeBot.Active = false, false

  line(win, PAD, H - 56, W - 2 * PAD, 1, 0.88, WHITE, "FootLine")
  local fine = btn(win, L("创建 / 细调（整备）", "Create / fine-tune"), U2.fromOffset(210, 36), U2.fromOffset(PAD, H - 46), "Fine")
  local hint = text(win, L("悬停一行先预览，点一下换成这一套（即时保存）", "Hover to preview, click to equip (saved right away)"), U2.fromOffset(520, 20), U2.fromOffset(PAD + 228, H - 38), TH.S.small, MUTE, TH.F.body, nil, "Hint")
  local done = btn(win, L("完成", "Done"), U2.fromOffset(150, 36), U2.fromOffset(W - PAD - 150, H - 46), "Done", true)

  ---------------------------------------------------------------- 数据

  local cur = nil   -- { it, a, D, cols = 挂点顺序（左翼尖 → 右翼尖）, team }
  local function shortName(wid)
    local s = T("aws." .. wid)
    if s == "aws." .. wid then s = T("aw." .. wid) end
    if s == "aw." .. wid then s = wid end
    return s
  end
  local function countOf(a, i, wid)
    local s = a.st and a.st[i]
    if not s or not wid then return 0 end
    return AD.count(s, wid)
  end
  -- 一套挂载的清单（型号 × 枚数，按出现的顺序）
  local function summary(a, load)
    local order, n = {}, {}
    for i, wid in ipairs(load or {}) do
      if wid then
        if not n[wid] then n[wid] = 0 table.insert(order, wid) end
        n[wid] += countOf(a, i, wid)
      end
    end
    local parts = {}
    for _, wid in ipairs(order) do table.insert(parts, shortName(wid) .. " ×" .. n[wid]) end
    return parts, order, n
  end
  local function isAirOnly(load)
    for _, wid in ipairs(load or {}) do
      local w = wid and AD.W[wid]
      if w and w.kind ~= "aam" and w.kind ~= "tank" then return false end
    end
    return true
  end
  local function same(a, b)
    for i = 1, math.max(#(a or {}), #(b or {})) do
      if (a[i] or false) ~= (b[i] or false) then return false end
    end
    return true
  end
  local CATN = {
    aam = { "空空导弹", "AAM" }, agm = { "空地导弹", "AGM" }, bomb = { "炸弹", "Bomb" }, gbomb = { "制导炸弹", "Guided bomb" }, rkt = { "火箭", "Rockets" },
    tank = { "副油箱", "Drop tank" }, gun = { "机炮吊舱", "Gun pod" }, sam = { "导弹", "Missile" }, arm = { "反辐射导弹", "Anti-radiation" },
  }
  local function catOf(w)
    if not w then return nil end
    if w.arm then return "arm" end
    if w.kind == "bomb" and w.guided then return "gbomb" end
    return w.kind
  end
  -- 性能（同整备：FlightModel.loadout + perf）：比空挂的差
  local perfCache = {}
  local function perfOf(load, fuel)
    if not (FM and FM.loadout and FM.perf and cur and cur.D) then return nil end
    local key = table.concat((function() local t = {} for i, w in ipairs(load) do t[i] = w or "" end return t end)(), ",") .. "|" .. tostring(fuel)
    if perfCache[key] then return perfCache[key] end
    local ok, Lo = pcall(FM.loadout, cur.a, load, fuel, { key = cur.it.key, AD = AD })
    if not ok or not Lo or not Lo.m then return nil end
    local ok2, p = pcall(FM.perf, cur.D, Lo.m, Lo.dCD0)
    if not ok2 or not p then return nil end
    local r = { Lo = Lo, p = p }
    perfCache[key] = r
    return r
  end

  ---------------------------------------------------------------- 弹的剪影（格子里、清单里）：几块小方块拼的，横着放、头朝右

  local function glyph(parent, kind, w, h, col, tr)
    local g = frame(parent, U2.fromOffset(w, h), nil, INK, 1, "Glyph")
    col, tr = col or TEXT, tr or 0.08
    local cy = h / 2
    local function bar(x, y, bw, bh, rr, c2, t2)
      local f = frame(g, U2.fromOffset(bw, bh), U2.fromOffset(x, y), c2 or col, t2 or tr)
      if rr then round(f, UDim.new(0, rr)) end
      return f
    end
    if kind == "aam" or kind == "sam" or kind == "agm" or kind == "arm" then
      local th = (kind == "aam" or kind == "sam") and 3 or 5
      local L0 = w * ((kind == "aam" or kind == "sam") and 0.9 or 0.82)
      local x0 = (w - L0) / 2
      bar(x0, cy - th / 2, L0, th, th / 2)                          -- 弹体
      bar(x0 + 1, cy - 5, 2, 10)                                   -- 尾翼
      bar(x0 + L0 * (kind == "agm" and 0.62 or 0.55), cy - 3.5, 2, 7)   -- 弹翼
      bar(x0 + L0 - 2, cy - th / 2 + 0.5, 3, th - 1, th / 2, WHITE, 0)  -- 导引头（亮一点）
    elseif kind == "bomb" or kind == "gbomb" then
      local L0, th = w * 0.56, 9
      local x0 = (w - L0) / 2 + 3
      bar(x0, cy - th / 2, L0, th, th / 2)
      bar(x0 - 6, cy - 5.5, 7, 11, 1, col, tr + 0.25)               -- 尾翼箱
      if kind == "gbomb" then bar(x0 + L0 - 6, cy - 6, 2, 12) end   -- 制导组件的鸭翼
    elseif kind == "rkt" then
      local L0, th = w * 0.5, 11
      local x0 = (w - L0) / 2
      bar(x0, cy - th / 2, L0, th, 2)
      bar(x0 + L0 - 3, cy - th / 2, 3, th, 1, WHITE, 0.35)          -- 发射管口
      for k = -1, 1 do bar(x0 + L0 - 2, cy + k * 3.2 - 1, 2, 2, 1, INK, 0.2) end
    elseif kind == "tank" then
      local L0, th = w * 0.78, 7
      local x0 = (w - L0) / 2
      bar(x0, cy - th / 2, L0, th, th / 2)
      bar(x0 + 2, cy - 5, 2, 10)
    else   -- 机炮吊舱
      local L0, th = w * 0.46, 6
      local x0 = (w - L0) / 2 - 4
      bar(x0, cy - th / 2, L0, th, 1)
      bar(x0 + L0, cy - 1, w * 0.22, 2)
    end
    return g
  end

  ---------------------------------------------------------------- 3D：建模型、取景、标签

  -- 取景：前方偏左 28°、低 15° 仰看（翼展在画面里横着铺开，翼下的弹都露出来；原来偏 38°，翼根几个挂点挤在机身边上）
  local AZ0, EL0 = math.rad(28), math.rad(15)
  local hero = { az = AZ0, el = EL0, M = nil, load = nil, dist = 60, target = V3() }
  -- 模型的外形点（每块看得见的零件八个角，建好模型时算一次）和包围盒中心：取景按真外形装下、对准中心
  local function shapeOf(M)
    local pts = {}
    local x0, y0, z0, x1, y1, z1 = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
    for _, p in ipairs(M.model:GetDescendants()) do
      if p:IsA("BasePart") and p.Transparency < 0.95 then
        local s = p.Size / 2
        for _, c in ipairs({ { 1, 1, 1 }, { 1, 1, -1 }, { 1, -1, 1 }, { 1, -1, -1 }, { -1, 1, 1 }, { -1, 1, -1 }, { -1, -1, 1 }, { -1, -1, -1 } }) do
          local w = p.CFrame * V3(s.X * c[1], s.Y * c[2], s.Z * c[3])
          pts[#pts + 1] = w
          x0, y0, z0 = math.min(x0, w.X), math.min(y0, w.Y), math.min(z0, w.Z)
          x1, y1, z1 = math.max(x1, w.X), math.max(y1, w.Y), math.max(z1, w.Z)
        end
      end
    end
    if #pts == 0 then return nil, nil end
    return pts, V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
  end
  -- 镜头：从 hero.az / hero.el 的方向看包围盒中心，距离按投影后正好装下（横着留一成二、竖着留两成的边）；keep = 转场里不改距离（不一推一拉）
  local function fitCam(keep)
    if not hero.M then return end
    local d = cur and cur.a or {}
    local dir = V3(-math.sin(hero.az) * math.cos(hero.el), -math.sin(hero.el), -math.cos(hero.az) * math.cos(hero.el))
    local look = -dir
    local rt = look:Cross(V3(0, 1, 0)).Unit
    local up = rt:Cross(look).Unit
    local tanV = math.tan(math.rad(vcam.FieldOfView / 2))
    local tanH = tanV * HERO.w / HERO.h
    local c0 = hero.target or hero.center or V3()
    if not keep then
      local pts = hero.pts
      if not pts then
        local L0, W0, H0 = (d.L or 40) / 2, (d.W or 30) / 2, (d.H or 10) / 2
        pts = { V3(0, 0, -L0), V3(0, 0, L0), V3(-W0, 0, L0 * 0.25), V3(W0, 0, L0 * 0.25), V3(0, H0, L0 * 0.8), V3(0, -H0, 0) }
      end
      local function needFor(c)
        local need = 1
        for _, p in ipairs(pts) do
          local q = p - c
          local x, y, z = q:Dot(rt), q:Dot(up), q:Dot(look)
          need = math.max(need, math.abs(x) / (tanH * 0.88) - z, math.abs(y) / (tanV * 0.8) - z)
        end
        return need
      end
      -- 立体包围盒的中心投到画面上不在正中（近大远小、机腹的弹偏下）：按投影后的框挪两次中心、再定距离
      c0 = hero.center or V3()
      local dist = needFor(c0)
      for _ = 1, 2 do
        local camPos = c0 + dir * dist
        local nx0, nx1, ny0, ny1 = 1e9, -1e9, 1e9, -1e9
        for _, p in ipairs(pts) do
          local q = p - camPos
          local depth = q:Dot(look)
          if depth > 0.1 then
            local nx, ny = q:Dot(rt) / (depth * tanH), q:Dot(up) / (depth * tanV)
            nx0, nx1, ny0, ny1 = math.min(nx0, nx), math.max(nx1, nx), math.min(ny0, ny), math.max(ny1, ny)
          end
        end
        if nx0 > nx1 then break end
        c0 = c0 + rt * ((nx0 + nx1) / 2 * dist * tanH) + up * ((ny0 + ny1) / 2 * dist * tanV)
        dist = needFor(c0)
      end
      hero.dist = dist
    end
    hero.target = c0
    vcam.CFrame = CFrame.lookAt(c0 + dir * hero.dist, c0)
  end
  -- 世界里一点在画布上的位置（3D 那一块按 HERO 的矩形算；镜头后面的返回 nil）
  local function project(p)
    local o = vcam.CFrame:PointToObjectSpace(p)
    if o.Z > -0.1 then return nil end
    local tanV = math.tan(math.rad(vcam.FieldOfView / 2))
    local tanH = tanV * HERO.w / HERO.h
    local nx, ny = o.X / (-o.Z * tanH), o.Y / (-o.Z * tanV)
    return HERO.x + (0.5 + nx / 2) * HERO.w, HERO.y + (0.5 - ny / 2) * HERO.h
  end
  local calloutTok = 0
  local function clearCallouts()
    for _, c in ipairs(callouts:GetChildren()) do c:Destroy() end
  end
  local function seg(parent, x1, y1, x2, y2, col, tr)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local f = frame(parent, U2.fromOffset(len, 1), U2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2), col, tr)
    f.AnchorPoint = V2(0.5, 0.5)
    f.Rotation = math.deg(math.atan2(dy, dx))
    return f
  end
  -- 挂点编号小牌：每枚弹（挂架下面那一截）一个琥珀小圈，往下一根细线拉到编号牌（和下面表头的挂点编号一样）；
  --   牌子挤在一起的往下错开。原来两边一列标签拉引线，翼根那几个挤在机身边上，线交叉成一团（11-28 晚截图）
  local function drawCallouts(load, animate)
    calloutTok += 1
    local tok = calloutTok
    clearCallouts()
    if not (cur and load) then return end
    local a = cur.a
    local pins = {}
    for si, wid in ipairs(load) do
      if wid and a.st[si] then
        local p = a.st[si].pos
        local list = hero.M and hero.M.stores and hero.M.stores[si]
        if list and #list > 0 then   -- 指着弹本身，不是挂点
          local s = V3()
          for _, it in ipairs(list) do s += it.p.Position end
          p = s / #list
        end
        local x, y = project(p)
        if x then table.insert(pins, { si = si, wid = wid, x = x, y = y }) end
      end
    end
    -- 离机身远的先摆（翼尖那几个最好摆），挤的往两边、上面错开，实在没地方才往下叠
    local cx0 = HERO.x + HERO.w / 2
    table.sort(pins, function(u, v) return math.abs(u.x - cx0) > math.abs(v.x - cx0) end)
    local TW0, TH0 = 24, 14
    local placed = {}
    local function free(tx, ty)
      if ty > HERO.y + HERO.h - 12 or ty < HERO.y + 10 then return false end
      for _, q in ipairs(placed) do
        if math.abs(q.x - tx) < TW0 + 4 and math.abs(q.y - ty) < TH0 + 4 then return false end
      end
      return true
    end
    for i, e in ipairs(pins) do
      local out = (e.x < cx0) and -1 or 1   -- 往机身外侧那边错
      local tx, ty = e.x, e.y + 22
      for _, c in ipairs({ { 0, 22 }, { out * 28, 20 }, { out * 30, -18 }, { 0, -22 }, { -out * 28, 20 }, { 0, 40 }, { out * 28, 40 }, { 0, 58 } }) do
        if free(e.x + c[1], e.y + c[2]) then tx, ty = e.x + c[1], e.y + c[2] break end
      end
      placed[#placed + 1] = { x = tx, y = ty }
      local g = frame(callouts, U2.fromOffset(W, H), nil, INK, 1, "C_" .. e.si)
      local ring = frame(g, U2.fromOffset(7, 7), U2.fromOffset(e.x, e.y), INK, 1, "Ring")
      ring.AnchorPoint = V2(0.5, 0.5)
      round(ring, UDim.new(0.5, 0))
      stroke(ring, AMBER, 0, 1)
      local dot = frame(g, U2.fromOffset(2, 2), U2.fromOffset(e.x, e.y), AMBER, 0)
      dot.AnchorPoint = V2(0.5, 0.5)
      seg(g, e.x, e.y + ((ty > e.y) and 4 or -4), tx, ty + ((ty > e.y) and -TH0 / 2 or TH0 / 2), AMBER, 0.5)
      local tag = text(g, string.format("%02d", e.si), U2.fromOffset(TW0, TH0), U2.fromOffset(tx - TW0 / 2, ty - TH0 / 2), 10, TEXT, TH.F.mono, Enum.TextXAlignment.Center, "Lab")
      tag.BackgroundColor3, tag.BackgroundTransparency = TH.C.BG, 0.25
      stroke(tag, AMBER, 0.35)
      if animate and not reduced() then   -- 一个接一个出来（往上浮 6 像素）
        g.Position = U2.fromOffset(0, 6)
        g.Visible = false
        task.delay(0.05 + TH.stagger(i), function()
          if tok ~= calloutTok or not g.Parent then return end
          g.Visible = true
          tw(g, { Position = U2.fromOffset(0, 0) }, "ui")
        end)
      end
    end
  end
  -- 打开那一下：飞机从侧面转到取景的角度（0.55 秒，两头慢），转完编号牌一个接一个出来；拖动、关窗打断
  local revealTok = 0
  local pendingReveal = false
  local function reveal()
    revealTok += 1
    local tok = revealTok
    local az1 = hero.az
    local az0 = az1 + 0.85
    local el1 = hero.el
    local el0 = el1 + math.rad(10)
    local tt = 0
    fitCam()   -- 按停下来的角度定好距离，转的路上不改
    hero.az, hero.el = az0, el0
    fitCam(true)
    callouts.Visible = false
    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
      if tok ~= revealTok or not gui.Enabled or not hero.M then
        conn:Disconnect()
        return
      end
      tt += dt or 1 / 60
      local k = math.clamp(tt / TH.T.cam, 0, 1)
      local e = TH.ease("cam", k)
      hero.az, hero.el = az0 + (az1 - az0) * e, el0 + (el1 - el0) * e
      fitCam(true)
      if k >= 1 then
        conn:Disconnect()
        callouts.Visible = true
        if hero.load then drawCallouts(hero.load, true) end
      end
    end)
  end
  local function setHero(load, animate)
    if not cur then return end
    hero.load = load
    if hero.M then pcall(function() hero.M.model:Destroy() end) hero.M = nil end
    hero.pts, hero.center = nil, nil
    if AM then
      local ok, M = pcall(AM.build, cur.a, cur.team, load)
      if ok and M then
        M.model.Parent = world
        local c = { gear = 0, bay = 1, bayS = 1, can = 0, fold = 0, thr = 0, rpm = 0, flap = 0 }
        pcall(AM.pose, M, CF(), c, 0, world)
        hero.M = M
        hero.pts, hero.center = shapeOf(M)
        hero.target = nil
      end
    end
    fitCam()
    if pendingReveal and hero.M and not reduced() then
      pendingReveal = false
      clearCallouts()
      hero.load = load
      reveal()
    else
      pendingReveal = false
      drawCallouts(load, animate)
    end
    if animate and not reduced() then
      flash.BackgroundTransparency = 0.86
      tw(flash, { BackgroundTransparency = 1 }, 0.35)
    end
  end

  ---------------------------------------------------------------- 清单、性能

  local function setChosen(load, isPreview)
    local _, order, n = summary(cur.a, load)
    local lines = {}
    for _, wid in ipairs(order) do
      local cat = CATN[catOf(AD.W[wid]) or ""]
      table.insert(lines, string.format('<font face="RobotoMono" color="%s">×%d</font>  %s  <font size="12" color="%s">%s</font>', hex(AMBER), n[wid], shortName(wid), hex(FAINT), cat and L(cat[1], cat[2]) or ""))
    end
    sideList.Text = (#lines > 0) and table.concat(lines, "\n") or string.format('<font color="%s">%s</font>', hex(MUTE), L("不挂（空挂）", "Clean (no stores)"))
    local gun = cur.a.gun and T("aw." .. cur.a.gun)
    gunLine.Text = (gun and gun ~= "aw." .. cur.a.gun) and (L("机炮  ", "Gun  ") .. gun) or ""
    previewTag.Visible = isPreview == true
  end
  local function setPerf(load, fuel, animate)
    local empty = {}
    for i = 1, #(cur.a.st or {}) do empty[i] = false end
    local P1, P0 = perfOf(load, fuel), perfOf(empty, fuel)
    noPerf.Visible = not (P1 and P0)
    for _, m in ipairs(PERF) do m.row.Visible = (P1 and P0) and true or false end
    if not (P1 and P0) then return end
    local cd0 = (cur.D and cur.D.CD0) or 0.02
    local t1 = (P1.p.str or 0) > 0 and (2 * math.pi / P1.p.str) or 0
    local t0 = (P0.p.str or 0) > 0 and (2 * math.pi / P0.p.str) or 0
    local vals = {
      w = { (P1.Lo.ext or 0) - (P0.Lo.ext or 0), P1.Lo.m and string.format(L("全重 %d 千克", "gross %d kg"), math.floor(P1.Lo.m + 0.5)) or "" },
      d = { ((P1.Lo.dCD0 or 0) - (P0.Lo.dCD0 or 0)) / cd0 * 100, "" },
      v = { ((P1.p.vAB or 0) - (P0.p.vAB or 0)) * 3.6, string.format("%d km/h", math.floor((P1.p.vAB or 0) * 3.6 + 0.5)) },
      c = { (P1.p.roc or 0) - (P0.p.roc or 0), string.format("%.0f m/s", P1.p.roc or 0) },
      t = { t1 - t0, string.format("%.1f %s", t1, L("秒", "s")) },
    }
    for _, m in ipairs(PERF) do
      local v, abs = vals[m.id][1], vals[m.id][2]
      local zero = math.abs(v) < 1e-6
      local up = v > 0
      local col = zero and MUTE or (((up and m.worseUp) or (not up and not m.worseUp)) and BAD or GOOD)
      m.val.Text = string.format(m.fmt, v) .. " " .. m.unit
      m.val.TextColor3 = col
      m.abs.Text = abs
      local k = math.clamp(math.abs(v) / m.scale, 0, 1)
      local want = U2.fromOffset(math.floor(130 * k + 0.5), 2)
      m.bar.BackgroundColor3 = col
      if animate then tw(m.bar, { Size = want }, "num") else m.bar.Size = want end
    end
  end
  local function setSide(load, fuel, animate, isPreview)
    setChosen(load, isPreview)
    setPerf(load, fuel, animate)
  end

  local refresh   -- 下面定义
  local applied = nil   -- 现在存着的那一套（悬停预览完回到它）
  local function apply(load, presetKey)
    if not cur then return end
    local _, _, f = G.treeAirLoad(cur.it)
    G.treeSaveLoad(cur.it.key, load, presetKey, f, true)
    refresh(true)
  end

  ---------------------------------------------------------------- 表

  local rows = {}
  local hoverTok = 0
  local function preview(load)
    hoverTok += 1
    local tok = hoverTok
    task.delay(0.1, function()
      if tok ~= hoverTok or not cur or not gui.Enabled then return end
      local _, _, f = G.treeAirLoad(cur.it)
      if load and applied and same(load, applied) then
        setHero(applied, false)
        setSide(applied, f, false, false)
      elseif load then
        setHero(load, true)
        setSide(load, f, false, true)
      end
    end)
  end
  local function unpreview()
    hoverTok += 1
    local tok = hoverTok
    task.delay(0.12, function()
      if tok ~= hoverTok or not cur or not gui.Enabled or not applied then return end
      if hero.load and same(hero.load, applied) and not previewTag.Visible then return end
      local _, _, f = G.treeAirLoad(cur.it)
      setHero(applied, false)
      setSide(applied, f, false, false)
    end)
  end
  local function buildPlan(cols, cw)
    for _, c in ipairs(plan:GetChildren()) do c:Destroy() end
    local a = cur.a
    text(plan, L("预设方案", "PRESETS"), U2.fromOffset(200, 14), U2.fromOffset(0, 12), TH.S.tiny, MUTE, TH.F.bold, nil, "Head")
    local n = #cols
    if n == 0 then return end
    local x0 = NAMEW + cw / 2
    local x1 = NAMEW + (n - 0.5) * cw
    local wy = 15
    -- 机翼：一条线从左翼尖到右翼尖（两头淡）；机身：挂点里离中线最近的那一两列下面一块圆头的条
    local wing = line(plan, x0 - cw * 0.35, wy, (x1 - x0) + cw * 0.7, 2, 0.45, WHITE, "Wing")
    hgrad(wing, nseq({ { 0, 0.8 }, { 0.15, 0 }, { 0.85, 0 }, { 1, 0.8 } }))
    local minX, cIdx = 1e9, {}
    for ci, si in ipairs(cols) do
      local px = math.abs(a.st[si].pos.X)
      if px < minX - 0.3 then minX, cIdx = px, { ci } elseif math.abs(px - minX) <= 0.3 then table.insert(cIdx, ci) end
    end
    local cx = 0
    for _, ci in ipairs(cIdx) do cx += NAMEW + (ci - 0.5) * cw end
    cx /= math.max(#cIdx, 1)
    local fus = frame(plan, U2.fromOffset(math.max(cw * 0.6, 26), 8), U2.fromOffset(cx, wy + 1), WHITE, 0.55, "Fuselage")
    fus.AnchorPoint = V2(0.5, 0.5)
    round(fus, UDim.new(0.5, 0))
    for ci, si in ipairs(cols) do
      local x = NAMEW + (ci - 0.5) * cw
      line(plan, x, wy + 3, 1, 6, 0.4, WHITE, "Tick_" .. ci)
      text(plan, string.format("%02d", si), U2.fromOffset(cw, 12), U2.fromOffset(x - cw / 2, wy + 11), 10, FAINT, TH.F.mono, Enum.TextXAlignment.Center, "Num_" .. ci)
    end
  end
  local function sweep(r)   -- 换成这一套的那一下：一道琥珀的光从左扫到右
    if reduced() then return end
    local s = frame(r, U2.new(0, 220, 1, 0), U2.fromOffset(-220, 0), AMBER, 0.55, "Sweep")
    hgrad(s, nseq({ { 0, 1 }, { 0.6, 0.55 }, { 1, 1 } }))
    s.ZIndex = 3
    local t = tw(s, { Position = U2.new(1, 0, 0, 0) }, 0.5)
    task.delay(0.55, function() if s.Parent then s:Destroy() end end)
    local _ = t
  end

  local function buildRows(animateSel)
    for _, c in ipairs(tableF:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    table.clear(rows)
    local a = cur.a
    local cols = cur.cols
    local nCols = #cols
    local avail = TBL.w - NAMEW - 12
    local cw = math.clamp(math.floor(avail / math.max(nCols, 1)), 40, 96)
    buildPlan(cols, cw)
    local y = 0
    local curL, curP = G.treeAirLoad(cur.it)
    applied = curL
    local function header(s, en)
      local h = text(tableF, "", U2.fromOffset(420, 20), U2.fromOffset(2, y + 3), TH.S.small, TEXT, TH.F.bold, nil, "Group")
      h.RichText = true
      h.Text = s .. string.format('   <font face="RobotoCondensed" size="11" color="%s">%s</font>', hex(FAINT), en)
      local ln = line(tableF, 0, y + 23, TBL.w - 12, 1, 0.86)
      hgrad(ln, nseq({ { 0, 0.3 }, { 1, 1 } }))
      y += GROUPH
      return h
    end
    local idx = 0
    local function row(title0, subT, load, rowName, onPick)
      idx += 1
      local r = Instance.new("TextButton")
      r.Name = rowName
      r.AutoButtonColor = false
      r.Text = ""
      r.ClipsDescendants = true
      r.Size, r.Position = U2.fromOffset(NAMEW + nCols * cw, ROWH - 4), U2.fromOffset(0, y)
      local on = load ~= nil and same(load, curL)
      r.BackgroundColor3 = on and RGB(36, 33, 27) or TH.C.PANEL
      r.BackgroundTransparency = on and 0.05 or 0.35
      r.BorderSizePixel = 0
      r.Parent = tableF
      round(r)
      if on then   -- 选中：琥珀细描边 + 贴底 2 像素琥珀线 + 名字那一块一道淡淡的琥珀光
        local st = stroke(r, AMBER, 0.1)
        st.Name = "Sel"
        frame(r, U2.new(1, 0, 0, 2), U2.new(0, 0, 1, -2), AMBER, 0, "PickLine")
        local warm = frame(r, U2.fromOffset(NAMEW, ROWH - 4), nil, AMBER, 0.88, "Warm")
        hgrad(warm, nseq({ { 0, 0.2 }, { 1, 1 } }))
      end
      local nm = text(r, title0, U2.fromOffset(NAMEW - 24, 20), U2.fromOffset(14, 3), TH.S.body, load and TEXT or FAINT, TH.F.bold, nil, "Name")
      local st2 = text(r, subT or "", U2.fromOffset(NAMEW - 24, 16), U2.fromOffset(14, 23), TH.S.tiny, on and MUTE or FAINT, TH.F.body, nil, "Sub")
      local _ = nm and st2
      for ci, si in ipairs(cols) do
        local x = NAMEW + (ci - 1) * cw
        local cell = frame(r, U2.fromOffset(cw - 4, ROWH - 12), U2.fromOffset(x + 2, 4), INK, on and 0.55 or 0.62, "Cell_" .. ci)
        round(cell)
        local wid = load and load[si]
        local w = wid and AD.W[wid]
        if w then
          stroke(cell, on and AMBER or WHITE, on and 0.6 or 0.88)
          local g = glyph(cell, catOf(w), cw - 14, 14, on and RGB(250, 236, 206) or TEXT, 0.08)
          g.Position = U2.fromOffset(5, 4)
          local n = countOf(a, si, wid)
          local lab = shortName(wid)
          if #lab > 9 then lab = string.sub(lab, 1, 9) end
          text(cell, lab .. ((n > 1) and (" ×" .. n) or ""), U2.new(1, -4, 0, 14), U2.new(0, 2, 1, -17), 11, on and TEXT or MUTE, TH.F.cond, Enum.TextXAlignment.Center, "Lab")
        else
          local d0 = frame(cell, U2.fromOffset(3, 3), U2.fromScale(0.5, 0.5), WHITE, 0.82, "Empty")
          d0.AnchorPoint = V2(0.5, 0.5)
          round(d0, UDim.new(0.5, 0))
        end
      end
      r.MouseEnter:Connect(function()
        if not on then tw(r, { BackgroundTransparency = 0.12, BackgroundColor3 = TH.C.RAISE }, "hover", "hover") end
        if load then preview(load) end
      end)
      r.MouseLeave:Connect(function()
        if not on then tw(r, { BackgroundTransparency = 0.35, BackgroundColor3 = TH.C.PANEL }, "hover", "hover") end
        unpreview()
      end)
      r.MouseButton1Click:Connect(onPick)
      rows[#rows + 1] = { r = r, load = load, on = on }
      if not reduced() then   -- 进场：一行一行从下面浮上来
        r.Position = U2.fromOffset(0, y + 10)
        tw(r, { Position = U2.fromOffset(0, y) }, "panel", "out", TH.stagger(idx))
      end
      if on and animateSel then sweep(r) end
      y += ROWH
      return r
    end
    -- 预设按用途分两组
    local airP, gndP = {}, {}
    for _, pr in ipairs(a.presets or {}) do
      local load = AD.presetLoad(a, pr.key)
      table.insert(isAirOnly(load) and airP or gndP, { pr = pr, load = load })
    end
    local function pname(e)
      local parts = summary(a, e.load)
      if #parts == 0 then return L("不挂", "Clean") end
      return table.concat(parts, "，")
    end
    local function ptitle(e)
      local k = e.pr and ("preset." .. e.pr.key)
      local s = k and T(k)
      if s and s ~= k then return s end
      return pname(e)
    end
    -- 自定义：整备里存的「我的方案」（tree.sets[键]["1"～"3"]）
    local t = G.treeState and G.treeState()
    local sets = t and t.sets and t.sets[cur.it.key] or {}
    local custom = {}
    for i = 1, 3 do
      local v = sets[tostring(i)]
      custom[i] = (type(v) == "table" and type(v.l) == "table") and AD.cleanLoad(a, v.l) or nil
    end
    -- 当前这一套不在下面任何一行（整备里一个挂点一个挂点改过）：最上面先放一行「当前（已改）」
    --   （先判断再排：原来排完再整体往下挪，行的进场补间还往原来的位置走，挪不下去）
    local found = false
    for _, e in ipairs(airP) do if same(e.load, curL) then found = true end end
    for _, e in ipairs(gndP) do if same(e.load, curL) then found = true end end
    for i = 1, 3 do if custom[i] and same(custom[i], curL) then found = true end end
    if not found then
      header(L("当前挂载（整备里改过）", "Current (customised)"), "CURRENT")
      row(pname({ load = curL }), L("整备里一个挂点一个挂点改的", "Edited per pylon in the workshop"), curL, "Current", function() end)
    end
    if #airP > 0 then
      header(L("对空中目标", "Air targets"), "AIR")
      for _, e in ipairs(airP) do row(ptitle(e), pname(e), e.load, "Preset_" .. e.pr.key, function() apply(e.load, e.pr.key) end) end
    end
    if #gndP > 0 then
      header(L("对地面目标", "Ground targets"), "GROUND")
      for _, e in ipairs(gndP) do row(ptitle(e), pname(e), e.load, "Preset_" .. e.pr.key, function() apply(e.load, e.pr.key) end) end
    end
    header(L("自定义武器", "Custom"), "CUSTOM")
    for i = 1, 3 do
      local load = custom[i]
      local nm = string.format(L("编组方案 #%d", "Custom #%d"), i) .. (load and "" or L("（空）", " (empty)"))
      local r = row(nm, load and pname({ load = load }) or L("还没存", "Not saved yet"), load, "Custom_" .. i, function()
        if load then
          apply(load, nil)
        elseif G.treeSaveSet then   -- 空的：把现在这一套存进来
          local l2, _, f2 = G.treeAirLoad(cur.it)
          G.treeSaveSet(cur.it.key, i, l2, f2)
          task.delay(0.2, function() if gui.Enabled then refresh() end end)
        end
      end)
      if not load then
        local sv = text(r, "+  " .. L("点一下：把现在这一套存成这个方案", "Click to save the current loadout here"), U2.fromOffset(nCols * cw, ROWH - 4), U2.fromOffset(NAMEW, 0), TH.S.small, FAINT, TH.F.body, Enum.TextXAlignment.Center, "SaveHere")
        sv.ZIndex = 2
      end
    end
    tableF.CanvasSize = U2.fromOffset(0, y + 8)
    local _, _, f = G.treeAirLoad(cur.it)
    setHero(curL, true)
    setSide(curL, f, animateSel == true, false)
    local _2 = curP
  end

  refresh = function(animateSel)
    if not cur then return end
    buildRows(animateSel)
  end

  local function fitScale()
    local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
    fit.Scale = math.clamp(math.min(vs.X / W, vs.Y / H), 0.5, 1.6)
  end

  ---------------------------------------------------------------- 拖着转飞机

  local dragging, lastX, lastY = false, 0, 0
  drag.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      dragging, lastX, lastY = true, io.Position.X, io.Position.Y
      revealTok += 1
      callouts.Visible = false
      dragHint.Visible = false
    end
  end)
  UIS.InputChanged:Connect(function(io)
    if not dragging then return end
    if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
      local dx, dy = io.Position.X - lastX, io.Position.Y - lastY
      lastX, lastY = io.Position.X, io.Position.Y
      hero.az -= dx * 0.009
      hero.el = math.clamp(hero.el + dy * 0.006, math.rad(-35), math.rad(40))
      fitCam(true)
    end
  end)
  UIS.InputEnded:Connect(function(io)
    if dragging and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
      dragging = false
      callouts.Visible = true
      if hero.load then drawCallouts(hero.load, true) end
    end
  end)

  ---------------------------------------------------------------- 开、关

  function G.openLoadout(key)
    local it = type(key) == "string" and TT.get(key)
    local a = it and AD.get(it.play)
    if not a or not a.st or #a.st == 0 then
      if G.toast then G.toast(L("这一型没有挂点", "No hardpoints on this aircraft"), "info") end
      return false
    end
    local D = nil
    if FM and a.kind == "jet" then D = FM.get(a.id, it.key) or (a.like and FM.get(a.like)) or nil end
    local cols = {}
    for i in ipairs(a.st) do cols[#cols + 1] = i end
    table.sort(cols, function(i, j)   -- 从左翼尖到右翼尖（同一个横坐标，前面的先）
      local pi, pj = a.st[i].pos, a.st[j].pos
      if math.abs(pi.X - pj.X) > 1e-3 then return pi.X < pj.X end
      return pi.Z < pj.Z
    end)
    cur = { it = it, a = a, D = D, cols = cols, team = me:GetAttribute("Side") or "atk" }
    table.clear(perfCache)
    hero.az, hero.el = AZ0, EL0
    local nm = (G.lang == "en") and it.en or it.name
    title.Text = string.format('<font color="%s">%s</font>  %s', hex(MUTE), L("挂载 - ", "Loadout - "), tostring(nm))
    local rk = it.rank and ({ "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ" })[it.rank] or ""
    local nSt = #a.st
    sub.Text = string.format('<font color="%s">%s</font>  ·  %s  ·  %s', hex(TH.rankColor(it.rank or 1):Lerp(WHITE, 0.35)), (rk ~= "" and (rk .. L(" 级", "")) or ""),
      (a.kind == "heli") and L("直升机", "Helicopter") or L("固定翼", "Fixed-wing"), string.format(L("%d 个挂点", "%d hardpoints"), nSt))
    fitScale()
    gui.Enabled = true
    dragHint.Visible = true
    pendingReveal = true
    refresh(false)
    if G.uiPop and not reduced() then G.uiPop(win, 0.97, true) end
    return true
  end
  function G.closeLoadout()
    gui.Enabled = false
    hoverTok += 1
    calloutTok += 1
    revealTok += 1
    callouts.Visible = true
    if hero.M then pcall(function() hero.M.model:Destroy() end) hero.M = nil end
    clearCallouts()
    cur = nil
    applied = nil
    if G.refreshLineup then pcall(G.refreshLineup) end   -- 机库里摆的飞机按新挂载
  end
  G.loadoutOpen = function() return gui.Enabled end
  close.MouseButton1Click:Connect(G.closeLoadout)
  done.MouseButton1Click:Connect(G.closeLoadout)
  fine.MouseButton1Click:Connect(function()
    local it = cur and cur.it
    G.closeLoadout()
    if it and G.openWorkshop then pcall(G.openWorkshop, it, "arms") end
  end)
  UIS.InputBegan:Connect(function(io, gp)
    if gui.Enabled and io.KeyCode == Enum.KeyCode.Escape then G.closeLoadout() end
  end)
  local cam = workspace.CurrentCamera
  if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fitScale() end end) end
  local _ = hint
  local _2 = perfT
  local _3 = note
  local _4 = halo2
end

return LoadoutWin
