-- 全游戏统一外观（用户 11-25：「整个游戏风格极其割裂……四不像」，定下来统一成我们自己的一套写实军事风格，不照搬别的游戏的样子）。
--   规范写在 docs/style.md；所有界面的颜色、字体、字号、面板从这里取，新界面也一样（不要再在模块里自己定一套白、灰、绿、红）。
--   原则：底子是黑白灰（深色半透明面板、白字），颜色只用来表示意思——绿 = 自己人 / 完好 / 可以，红 = 敌人 / 危险 / 坏了，
--   琥珀 = 注意 / 进行中 / 受伤 / 金币；车上、飞机上的瞄准和飞行符号统一一种亮绿（Theme.C.HUD）。不用蓝色（用户 11-21：蓝色全部改成绿色）。
local Theme = {}
local RGB = Color3.fromRGB

Theme.C = {
  -- 底色、面板
  BG = RGB(8, 10, 12),        -- 整屏的底（机库、科技树、结算页）
  PANEL = RGB(14, 17, 20),    -- 面板、卡片
  RAISE = RGB(32, 36, 40),    -- 次要按钮、悬停
  LINE = RGB(255, 255, 255),  -- 细线、描边（配 Theme.A.line / lineHi 的透明度）
  INK = RGB(0, 0, 0),         -- 字的描边
  -- 字
  TEXT = RGB(236, 238, 236),  -- 正文、数字
  MUTE = RGB(160, 166, 164),  -- 次要说明、标签
  FAINT = RGB(104, 110, 110), -- 不能点的、没解锁的
  -- 意思
  GOOD = RGB(110, 214, 124),  -- 自己人、完好、已拥有、能打穿
  BAD = RGB(236, 74, 60),     -- 敌人、危险、坏了、打不穿
  WARN = RGB(240, 182, 72),   -- 注意、受伤、进行中、金币
  NEUTRAL = RGB(200, 204, 204), -- 中立据点
  HUD = RGB(128, 255, 152),   -- 车上 / 飞机上的瞄准与飞行符号（亮绿：天空、沙地上都看得清）
}
Theme.C.FRIEND = Theme.C.GOOD
Theme.C.FOE = Theme.C.BAD

-- 透明度
Theme.A = {
  panel = 0.18,   -- 面板底
  bar = 0.35,     -- 屏幕边上的信息条（比面板淡，不挡战场）
  line = 0.82,    -- 普通细线
  lineHi = 0.45,  -- 选中、悬停的细线
  stroke = 0.45,  -- 战场上的字的描边
}

-- 字体（用户 11-25「字体不清晰」）：正文、强调、标题换成 Roblox 自己的 Builder Sans（小字号下比 Gotham 清楚，中文跟着用粗一档的字重），
--   数字和仪表 RobotoMono；卡片上的短标签、型号用窄体 RobotoCondensed（同类游戏的军事界面感）
Theme.F = {
  body = Enum.Font.BuilderSansMedium,
  bold = Enum.Font.BuilderSansBold,
  title = Enum.Font.BuilderSansExtraBold,
  mono = Enum.Font.RobotoMono,
  cond = Enum.Font.RobotoCondensed,
}

-- 字号（11-25 整体大一档：12 / 13 / 15 / 17 / 21 / 29 / 42）
Theme.S = { tiny = 12, small = 13, body = 15, sub = 17, title = 21, big = 29, huge = 42 }
-- 科技树等级的底色（用户 11-25「载具科技树不同等级的载具背景颜色要有区别」）：一级一个色，压暗、偏军用色，不用蓝；
--   科技树每一级的横条、车卡车图底板、机库阵容卡、详情大图都按它（Theme.rankGrad）
Theme.RANK = {
  Color3.fromRGB(86, 104, 80),    -- I   灰绿
  Color3.fromRGB(108, 106, 62),   -- II  橄榄
  Color3.fromRGB(124, 104, 70),   -- III 沙褐
  Color3.fromRGB(128, 86, 58),    -- IV  铜褐
  Color3.fromRGB(122, 64, 62),    -- V   砖红
  Color3.fromRGB(102, 70, 98),    -- VI  紫褐
  Color3.fromRGB(132, 112, 52),   -- VII 暗金
}
function Theme.rankColor(r) return Theme.RANK[math.clamp(math.floor(r or 1), 1, #Theme.RANK)] end
Theme.R = 2   -- 圆角（像素）：方正、硬朗

-- 自己这一边 / 对面：一律按看的人算（不按攻守方的固定颜色）
function Theme.side(side, mine)
  if side == nil or side == "" then return Theme.C.NEUTRAL end
  if mine == nil or mine == "" then
    local ok, pl = pcall(function() return game:GetService("Players").LocalPlayer end)
    mine = ok and pl and pl:GetAttribute("Side") or nil
  end
  return (side == mine) and Theme.C.FRIEND or Theme.C.FOE
end

-- 状态比例（1 完好 → 0 坏了）：绿 → 琥珀 → 红
function Theme.state(k)
  if k >= 0.66 then return Theme.C.GOOD end
  if k >= 0.33 then return Theme.C.WARN end
  return Theme.C.BAD
end

---------------------------------------------------------------- 小工具（新界面直接用；老界面只换颜色字体时用不到）
function Theme.stroke(o, strong, col)
  local s = o:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
  s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  s.Color = col or Theme.C.LINE
  s.Transparency = strong and Theme.A.lineHi or Theme.A.line
  s.Thickness = 1
  s.Parent = o
  return s
end

function Theme.corner(o, r)
  local c = o:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
  c.CornerRadius = UDim.new(0, r or Theme.R)
  c.Parent = o
  return c
end

-- 面板：深色半透明底 + 一圈细线
function Theme.panel(parent, size, pos, anchor)
  local f = Instance.new("Frame")
  f.Size, f.Position, f.AnchorPoint = size, pos or UDim2.new(), anchor or Vector2.new(0, 0)
  f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = Theme.C.PANEL, Theme.A.panel, 0
  Theme.corner(f)
  Theme.stroke(f)
  f.Parent = parent
  return f
end

-- 字：kind = "body" | "bold" | "title" | "mono"
function Theme.label(parent, text, size, kind, col)
  local l = Instance.new("TextLabel")
  l.BackgroundTransparency = 1
  l.Text = text
  l.Font = Theme.F[kind or "body"] or Theme.F.body
  l.TextSize = size or Theme.S.body
  l.TextColor3 = col or Theme.C.TEXT
  l.TextXAlignment = Enum.TextXAlignment.Left
  l.Size = UDim2.new(1, 0, 0, (size or Theme.S.body) + 4)
  l.Parent = parent
  return l
end

-- 按钮：primary（白底黑字，一屏最多一个：出击、开始）/ 默认（灰底白字）
function Theme.button(parent, text, size, pos, primary)
  local b = Instance.new("TextButton")
  b.AutoButtonColor = true
  b.Size, b.Position = size, pos or UDim2.new()
  b.BackgroundColor3 = primary and Theme.C.TEXT or Theme.C.RAISE
  b.BackgroundTransparency = primary and 0 or 0.1
  b.BorderSizePixel = 0
  b.Text = text
  b.Font = Theme.F.bold
  b.TextSize = Theme.S.body
  b.TextColor3 = primary and Theme.C.BG or Theme.C.TEXT
  Theme.corner(b)
  if not primary then Theme.stroke(b) end
  b.Parent = parent
  return b
end

-- 竖着的渐变（上 → 下）：面板、卡片的车图底板（用户 11-25「没有设计感」：纯色细线太平，加一点层次）
-- 车图底板按等级上色：上面是这一级的颜色（亮一点）、往下压到近黑
function Theme.rankGrad(o, r)
  local c = Theme.rankColor(r)
  return Theme.grad(o, c:Lerp(Color3.new(1, 1, 1), 0.12), c:Lerp(Color3.new(0, 0, 0), 0.82))
end
function Theme.grad(o, top, bottom, rot)
  local g = o:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
  g.Color = ColorSequence.new(top, bottom)
  g.Rotation = rot or 90
  g.Parent = o
  return g
end
-- 选中的发光描边（琥珀）：外面再套一圈淡的
function Theme.glow(o, col)
  local s = Theme.stroke(o, true, col or Theme.C.WARN)
  s.Thickness, s.Transparency = 2, 0
  return s
end

-- 选中 / 没选中（页签、分段按钮）：选中白底黑字，没选中灰底白字
function Theme.setSelected(b, on)
  b.BackgroundColor3 = on and Theme.C.TEXT or Theme.C.RAISE
  b.BackgroundTransparency = on and 0 or 0.1
  if b:IsA("TextButton") or b:IsA("TextLabel") then
    b.TextColor3 = on and Theme.C.BG or Theme.C.TEXT
  end
end

return Theme
