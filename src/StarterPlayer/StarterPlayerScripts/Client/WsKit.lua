-- 全面大战场（客户端）——整备（Workshop）共用的界面零件：面板、卡片、状态色条、小块、分段键、拖动条、对比条、引线标签、武器剪影、数字滚动
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——要的是同类写实军事游戏那种精致、克制、写实的质感，
--   用我们自己的界面美术（docs/style.md、Theme.lua）：深色半透明底 + 1 像素细线、圆角 2 像素；颜色只表意（绿 = 已装 / 变好、红 = 变差、
--   琥珀 = 选中 / 预览 / 进行中、灰 = 锁住），不用蓝；不要卡通感（圆滚滚的大按钮、高饱和色块、粗描边一律不用）。
--   动效时长、缓动从 Theme.T / Theme.EASE 取（docs/style.md「动效」），每一处都能被打断：同一个东西再动一次，从它现在的样子接着走。
--   Workshop.lua（外壳）、WsArms.lua（挂载页）用；以后的弹药 / 改装 / 乘员 / 涂装页同一套
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TH = require(RS:WaitForChild("Theme"))

local K = { TH = TH }
local C, A, F, S = TH.C, TH.A, TH.F, TH.S
local UD2, V2 = UDim2.new, Vector2.new

---------------------------------------------------------------- 基本零件

function K.frame(parent, size, pos, col, tr, anchor)
  local f = Instance.new("Frame")
  f.Size = size or UD2(1, 0, 1, 0)
  f.Position = pos or UD2(0, 0, 0, 0)
  f.AnchorPoint = anchor or V2(0, 0)
  f.BackgroundColor3 = col or C.PANEL
  f.BackgroundTransparency = tr or 0
  f.BorderSizePixel = 0
  f.Parent = parent
  return f
end
-- 字：font 是 Theme.F 的键（body / bold / title / mono / cond）；一行、放不下截掉
function K.text(parent, str, ts, font, col, size, pos, align, anchor)
  local t = Instance.new("TextLabel")
  t.BackgroundTransparency = 1
  t.BorderSizePixel = 0
  t.Text = str or ""
  t.TextSize = ts or S.body
  t.Font = F[font or "body"] or F.body
  t.TextColor3 = col or C.TEXT
  t.TextXAlignment = align or Enum.TextXAlignment.Left
  t.TextYAlignment = Enum.TextYAlignment.Center
  t.TextTruncate = Enum.TextTruncate.AtEnd
  t.Size = size or UD2(1, 0, 0, (ts or S.body) + 4)
  t.Position = pos or UD2(0, 0, 0, 0)
  t.AnchorPoint = anchor or V2(0, 0)
  t.Parent = parent
  return t
end
-- 透明的按钮（整块能点、自己不画东西）
function K.button(parent, size, pos, name)
  local b = Instance.new("TextButton")
  b.Name = name or "Button"
  b.Text = ""
  b.AutoButtonColor = false
  b.BackgroundTransparency = 1
  b.BorderSizePixel = 0
  b.Size = size or UD2(1, 0, 1, 0)
  b.Position = pos or UD2(0, 0, 0, 0)
  b.Parent = parent
  return b
end
local function round(f)
  local c = f:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
  c.CornerRadius = UDim.new(0.5, 0)
  c.Parent = f
  return f
end
K.round = round
-- 两点之间一根线（像素坐标，同一个父零件里）：转角度的细条
function K.line(f, x1, y1, x2, y2, th)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  f.AnchorPoint = V2(0.5, 0.5)
  f.Size = UD2(0, math.max(1, len), 0, th or 1)
  f.Position = UD2(0, (x1 + x2) / 2, 0, (y1 + y2) / 2)
  f.Rotation = (len > 0.01) and math.deg(math.atan2(dy, dx)) or 0
  return f
end
-- 字有多宽（估算：没有 TextService 也能排版；中日韩一个字一个字号宽，英文、数字半个多一点）
function K.textW(s, ts, mono)
  local w = 0
  for _, cp in utf8.codes(tostring(s or "")) do
    if cp >= 0x2E80 then w += ts
    elseif cp == 32 then w += ts * 0.3
    else w += ts * (mono and 0.6 or 0.54) end
  end
  return w
end
-- 1,840 这种写法（数字里的负号用 ASCII 的 -：U+2212 那个减号不是每种字体都有，缺字会画成方框）
function K.int(n)
  n = math.floor((n or 0) + 0.5)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return ((n < 0) and "-" or "") .. out
end
-- 带正负号的小数：+0.0042、-60（0 写 0）
function K.signed(v, dec)
  dec = dec or 0
  local mag = string.format("%." .. dec .. "f", math.abs(v))
  if dec == 0 then mag = K.int(math.abs(v)) end
  if math.abs(v) < 0.5 * 10 ^ (-dec) then return "0" end
  return ((v < 0) and "-" or "+") .. mag
end
-- 往左的尖角（「‹ 机库」的 ‹：画两笔细线，不靠字体里有没有这个字）；size 像素高
function K.chevron(parent, x, y, size, col, th)
  local box = K.frame(parent, UDim2.new(0, size, 0, size), UDim2.new(0, x, 0, y), nil, 1)
  box.Name = "Chevron"
  local a = K.frame(box, nil, nil, col or C.TEXT, 0)
  K.line(a, size * 0.68, size * 0.12, size * 0.28, size * 0.52, th or 1.5)
  local b = K.frame(box, nil, nil, col or C.TEXT, 0)
  K.line(b, size * 0.28, size * 0.48, size * 0.68, size * 0.88, th or 1.5)
  return box
end

---------------------------------------------------------------- 逐帧的小动画（自己插值的：数字滚动、3D 里的东西）——同一个键再来一次就从头接着走（打断）

local anims = {}
local animConn = nil
local function stepAnims(dt)
  local keys = {}
  for k in pairs(anims) do keys[#keys + 1] = k end
  for _, k in ipairs(keys) do
    local a = anims[k]
    if a then
      a.t += dt or 0.016
      local x = math.clamp(a.t / math.max(a.T, 1e-3), 0, 1)
      local ok = pcall(a.f, TH.ease(a.ease or "out", x), x)
      if (x >= 1 or not ok) and anims[k] == a then anims[k] = nil end
    end
  end
end
-- K.anim(键, 秒, 缓动键, f(缓动后的 0～1, 原始 0～1))：马上画第一帧
function K.anim(key, T, ease, f)
  local a = { t = 0, T = T or TH.T.ui, ease = ease, f = f }
  anims[key] = a
  if not animConn then animConn = RunService.RenderStepped:Connect(stepAnims) end
  pcall(f, 0, 0)
  if (T or 0) <= 0 then
    pcall(f, 1, 1)
    anims[key] = nil
  end
end
function K.stop(key) anims[key] = nil end
function K.animating(key) return anims[key] ~= nil end
-- 数字滚动（docs/style.md：数字、条长变化 0.22 秒先快后慢）：从显示着的数滚到新的；fmt(数) → 字
function K.roll(label, key, from, to, fmt)
  if type(to) ~= "number" then
    K.stop(key)
    label.Text = fmt(to)
    return
  end
  if type(from) ~= "number" or from ~= from or math.abs(from - to) < 1e-9 then
    K.stop(key)
    label.Text = fmt(to)
    return
  end
  K.anim(key, TH.T.num, "out", function(e) label.Text = fmt(from + (to - from) * e) end)
end

---------------------------------------------------------------- 面板、底板、分节标题

-- 面板（整备的左栏、右栏、底部条）：深色半透明底，竖向一点点渐变（RAISE 渐到 BG），1 像素细线、圆角 2；挡住后面的拖车（Active）
function K.panel(parent, size, pos, anchor)
  local f = K.frame(parent, size, pos, Color3.new(1, 1, 1), A.panel, anchor)
  f.Active = true
  TH.grad(f, C.RAISE, C.BG)
  TH.corner(f)
  TH.stroke(f)
  return f
end
-- 图的底板（武器图、炮弹图垫一块深色：RAISE 渐到 BG）
function K.plate(parent, size, pos)
  local f = K.frame(parent, size, pos, Color3.new(1, 1, 1), 0.15)
  f.Name = "Plate"
  TH.grad(f, C.RAISE:Lerp(C.BG, 0.25), C.BG)
  TH.corner(f)
  local s = TH.stroke(f)
  s.Transparency = 0.9
  return f
end
-- 分节标题：窄体 13 灰字 + 右边一道到头的细线（技术图纸那种）
function K.header(parent, str, y, w, x)
  x = x or 12
  local t = K.text(parent, str, S.small, "cond", C.MUTE, UD2(0, w, 0, 16), UD2(0, x, 0, y))
  t.Name = "Head"
  local tw = K.textW(str, S.small) + 8
  local ln = K.frame(parent, UD2(0, math.max(0, w - tw), 0, 1), UD2(0, x + tw, 0, y + 8), C.LINE, A.line)
  ln.Name = "HeadLine"
  return t, ln
end
-- 虚线框（「不挂」那张卡、空着的「我的方案」）：沿四边画 1 像素的短线；w × h 是框的像素大小
function K.dashed(parent, w, h, col, tr, dash, gap)
  local box = K.frame(parent, UD2(1, 0, 1, 0), nil, nil, 1)
  box.Name = "Dash"
  dash, gap = dash or 4, gap or 3
  local function run(len, f)
    local x = 0
    while x < len - 0.5 do
      local l = math.min(dash, len - x)
      f(x, l)
      x += dash + gap
    end
  end
  run(w, function(x, l)
    K.frame(box, UD2(0, l, 0, 1), UD2(0, x, 0, 0), col or C.LINE, tr or 0.55)
    K.frame(box, UD2(0, l, 0, 1), UD2(0, x, 1, -1), col or C.LINE, tr or 0.55)
  end)
  run(h, function(y, l)
    K.frame(box, UD2(0, 1, 0, l), UD2(0, 0, 0, y), col or C.LINE, tr or 0.55)
    K.frame(box, UD2(0, 1, 0, l), UD2(1, -1, 0, y), col or C.LINE, tr or 0.55)
  end)
  return box
end
-- 进场：一项盖一层面板色、淡开（列表一项项错开 Theme.stagger(i)，最多 8 项）；i 从 1 起
function K.reveal(f, i, dy)
  local cov = f:FindFirstChild("Reveal") or K.frame(f, UD2(1, 0, 1, 0), nil, C.PANEL, 0)
  cov.Name = "Reveal"
  cov.ZIndex = 20
  cov.BackgroundTransparency = 0
  TH.corner(cov)
  TH.tween(cov, { BackgroundTransparency = 1 }, "panel", "out", TH.stagger(i))
  if dy and dy ~= 0 then
    local p = f.Position
    f.Position = p + UD2(0, 0, 0, dy)
    TH.tween(f, { Position = p }, "panel", "out", TH.stagger(i))
  end
  return cov
end

---------------------------------------------------------------- 卡片、状态色条

-- 状态色条的颜色（卡片左边 3 像素）：own 已装 / 已拥有 GOOD、sel 选中 / 研究中 WARN、lock 锁住 FAINT、over 超限 BAD
K.STATE = { own = C.GOOD, sel = C.WARN, lock = C.FAINT, over = C.BAD }
local Card = {}
Card.__index = Card
-- 卡片：深色半透明底（PANEL）+ 1 像素细线、圆角 2；左边一道状态色条；悬停描边变亮、抬起 2 像素；选中琥珀描边（Theme.glow）
--   o：{ name, tr 底的透明度, onEnter, onLeave, onClick }
function K.card(parent, size, pos, o)
  o = o or {}
  local b = Instance.new("TextButton")
  b.Name = o.name or "Card"
  b.Text = ""
  b.AutoButtonColor = false
  b.Size, b.Position = size, pos
  b.BackgroundColor3 = C.PANEL
  b.BackgroundTransparency = o.tr or 0.12
  b.BorderSizePixel = 0
  b.Parent = parent
  TH.corner(b)
  local st = TH.stroke(b)
  local strip = K.frame(b, UD2(0, 3, 1, -8), UD2(0, 3, 0, 4), C.GOOD, 0)
  strip.Name = "Strip"
  strip.Visible = false
  strip.ZIndex = 3
  TH.corner(strip, 1)
  local cd = setmetatable({ f = b, st = st, strip = strip, pos = pos, sel = false, hov = false, o = o }, Card)
  b.MouseEnter:Connect(function()
    cd:setHover(true)
    if o.onEnter then o.onEnter(cd) end
  end)
  b.MouseLeave:Connect(function()
    cd:setHover(false)
    if o.onLeave then o.onLeave(cd) end
  end)
  if o.onClick then b.Activated:Connect(function() o.onClick(cd) end) end
  return cd
end
function Card:setState(k)
  local col = k and K.STATE[k]
  self.strip.Visible = col ~= nil
  if col then self.strip.BackgroundColor3 = col end
  self.state = k
end
local function cardLook(cd, T)
  local st = cd.st
  if cd.sel then
    st.Color = C.WARN
    st.Thickness = 2
    TH.tween(st, { Transparency = 0 }, T or "hover", "out")
  else
    st.Color = C.LINE
    st.Thickness = 1
    TH.tween(st, { Transparency = cd.hov and A.lineHi or A.line }, T or "hover", "hover")
  end
  local lift = (cd.hov or cd.sel) and -2 or 0
  TH.tween(cd.f, { Position = cd.pos + UD2(0, 0, 0, lift) }, "hover", "out")
end
function Card:setSel(on)
  if self.sel == (on == true) then return end
  self.sel = on == true
  cardLook(self)
end
function Card:setHover(on)
  if self.hov == (on == true) then return end
  self.hov = on == true
  cardLook(self)
end
function Card:move(pos)
  self.pos = pos
  local lift = (self.hov or self.sel) and -2 or 0
  self.f.Position = pos + UD2(0, 0, 0, lift)
end

---------------------------------------------------------------- 小块（方案、预设）、分段键

local Chip = {}
Chip.__index = Chip
-- 小块：灰底细线（30 高，手机 34）；选中白底黑字（同页签、分段键：docs/style.md 第 4 条）；
--   照这套改过：右边一个「已改」小标 + 底边一道 2 像素琥珀（注意 / 进行中）；dash：空着的（虚线框、淡字）
function K.chip(parent, str, size, pos, o)
  o = o or {}
  local b = Instance.new("TextButton")
  b.Name = o.name or "Chip"
  b.Text = ""
  b.AutoButtonColor = false
  b.Size, b.Position = size, pos
  b.BackgroundColor3 = C.RAISE
  b.BackgroundTransparency = 0.1
  b.BorderSizePixel = 0
  b.Parent = parent
  TH.corner(b)
  local st = TH.stroke(b)
  local t = K.text(b, str, S.small, "bold", C.TEXT, UD2(1, -16, 1, 0), UD2(0, 8, 0, 0))
  t.Name = "Label"
  local mod = K.text(b, "", S.tiny, "cond", C.BG, UD2(0, 30, 1, 0), UD2(1, -6, 0, 0), Enum.TextXAlignment.Right, V2(1, 0))
  mod.Name = "Mod"
  mod.Visible = false
  local bar = K.frame(b, UD2(1, -4, 0, 2), UD2(0, 2, 1, -2), C.WARN, 0)
  bar.Name = "ModBar"
  bar.Visible = false
  local ch = setmetatable({ f = b, t = t, st = st, mod = mod, bar = bar, on = false, o = o }, Chip)
  b.MouseEnter:Connect(function() if not ch.on then TH.tween(st, { Transparency = A.lineHi }, "hover", "hover") end end)
  b.MouseLeave:Connect(function() if not ch.on then TH.tween(st, { Transparency = A.line }, "hover", "hover") end end)
  if o.onClick then b.Activated:Connect(function() o.onClick(ch) end) end
  return ch
end
function Chip:set(on, modTxt)
  self.on = on == true
  local b = self.f
  b.BackgroundColor3 = on and C.TEXT or C.RAISE
  b.BackgroundTransparency = on and 0 or (self.dash and 0.6 or 0.1)
  self.t.TextColor3 = on and C.BG or (self.dash and C.FAINT or C.TEXT)
  self.st.Transparency = on and 1 or (self.dash and 1 or A.line)
  self.mod.Visible = on and modTxt ~= nil and modTxt ~= ""
  self.mod.Text = modTxt or ""
  self.bar.Visible = self.mod.Visible
  self.t.Size = UD2(1, self.mod.Visible and -44 or -16, 1, 0)
end
-- 空着的样子（虚线框、淡字）
function Chip:setDash(on, w, h)
  self.dash = on == true
  local d = self.f:FindFirstChild("Dash")
  if on and not d and w and h then K.dashed(self.f, w, h, C.LINE, 0.6) end
  if d then d.Visible = on end
  self:set(self.on, self.mod.Text ~= "" and self.mod.Text or nil)
end

-- 分段键（内油 25 / 50 / 75 / 100、开 / 关）：一条框里几段，段间 1 像素细线；选中那段白底黑字
--   opts = { { key = , text = , name = 按钮名 } … }；o.onPick(键)
function K.seg(parent, opts, size, pos, o)
  o = o or {}
  local box = K.frame(parent, size, pos, C.RAISE, 0.1)
  box.Name = o.name or "Seg"
  TH.corner(box)
  TH.stroke(box)
  local n = #opts
  local sg = { f = box, btns = {}, cur = nil }
  for i, op in ipairs(opts) do
    local b = Instance.new("TextButton")
    b.Name = op.name or ("Seg_" .. tostring(op.key))
    b.AutoButtonColor = false
    b.Text = op.text or tostring(op.key)
    b.Font = F.bold
    b.TextSize = o.ts or S.small
    b.TextColor3 = C.TEXT
    b.BackgroundColor3 = C.TEXT
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Size = UD2(1 / n, (i < n) and -1 or 0, 1, 0)
    b.Position = UD2((i - 1) / n, 0, 0, 0)
    b.Parent = box
    TH.corner(b)
    if i < n then K.frame(box, UD2(0, 1, 1, -8), UD2(i / n, -1, 0, 4), C.LINE, A.line).Name = "Div" end
    b.MouseEnter:Connect(function() if sg.cur ~= op.key then b.BackgroundTransparency = 0.92 end end)
    b.MouseLeave:Connect(function() if sg.cur ~= op.key then b.BackgroundTransparency = 1 end end)
    b.Activated:Connect(function() if o.onPick then o.onPick(op.key) end end)
    sg.btns[op.key] = b
  end
  function sg.set(k)
    sg.cur = k
    for key, b in pairs(sg.btns) do
      local on = key == k
      b.BackgroundTransparency = on and 0 or 1
      b.TextColor3 = on and C.BG or C.TEXT
    end
  end
  function sg.enable(on)
    for _, b in pairs(sg.btns) do
      b.Active = on
      if not on then b.TextColor3 = C.FAINT end
    end
  end
  return sg
end

---------------------------------------------------------------- 拖动条（配弹：一种弹带几发；以后的弹药页用）

-- 轨道 4 高、填充 TEXT、滑块 10 × 16（悬停 / 拖着时琥珀描边）、每 tick 一道刻度；左右 26 × 26 的 − / +；右边数目（等宽 17）；
--   lock：别的弹已经占掉的那一截（画 FAINT，拖不进去）；o = { w 轨道宽, min, max, step, tick, value, lock, onChange(数) }
function K.slider(parent, pos, o)
  local w = o.w or 172
  local box = K.frame(parent, UD2(0, w + 26 * 2 + 12 + 40, 0, 26), pos, nil, 1)
  box.Name = o.name or "Slider"
  local sl = { f = box, v = o.value or 0, min = o.min or 0, max = o.max or 10, step = o.step or 1, lock = o.lock or 0 }
  local function btn(x, s, name)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = s
    b.Font = F.bold
    b.TextSize = S.body
    b.TextColor3 = C.TEXT
    b.AutoButtonColor = false
    b.BackgroundColor3 = C.RAISE
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel = 0
    b.Size = UD2(0, 26, 0, 26)
    b.Position = UD2(0, x, 0, 0)
    b.Parent = box
    TH.corner(b)
    TH.stroke(b)
    return b
  end
  local minus = btn(0, "", "Minus")
  K.frame(minus, UD2(0, 10, 0, 2), UD2(0.5, 0, 0.5, 0), C.TEXT, 0, V2(0.5, 0.5)).Name = "Bar"   -- 减号画出来（U+2212 不是每种字体都有）
  local x0 = 26 + 6
  local track = K.frame(box, UD2(0, w, 0, 4), UD2(0, x0, 0.5, -2), C.LINE, 0.85)
  track.Name = "Track"
  local lockF = K.frame(track, UD2(0, 0, 1, 0), UD2(1, 0, 0, 0), C.FAINT, 0.2, V2(1, 0))
  lockF.Name = "Locked"
  local fill = K.frame(track, UD2(0, 0, 1, 0), nil, C.TEXT, 0)
  fill.Name = "Fill"
  local ticks = K.frame(box, UD2(0, w, 0, 4), UD2(0, x0, 0.5, 4), nil, 1)
  ticks.Name = "Ticks"
  local thumb = Instance.new("TextButton")
  thumb.Name = "Thumb"
  thumb.Text = ""
  thumb.AutoButtonColor = false
  thumb.BackgroundColor3 = C.TEXT
  thumb.BorderSizePixel = 0
  thumb.Size = UD2(0, 10, 0, 16)
  thumb.AnchorPoint = V2(0.5, 0.5)
  thumb.Parent = box
  TH.corner(thumb)
  local tst = TH.stroke(thumb, true, C.WARN)
  tst.Transparency = 1
  tst.Thickness = 1.5
  local plus = btn(x0 + w + 6, "+", "Plus")
  local num = K.text(box, "", S.sub, "mono", C.TEXT, UD2(0, 40, 1, 0), UD2(0, x0 + w + 6 + 26 + 6, 0, 0), Enum.TextXAlignment.Right)
  num.Name = "Count"
  local function draw()
    local span = math.max(1, sl.max - sl.min)
    local k = math.clamp((sl.v - sl.min) / span, 0, 1)
    fill.Size = UD2(k, 0, 1, 0)
    lockF.Size = UD2(math.clamp(sl.lock / span, 0, 1), 0, 1, 0)
    thumb.Position = UD2(0, x0 + k * w, 0.5, 0)
    num.Text = tostring(sl.v)
  end
  local function setTicks()
    ticks:ClearAllChildren()
    local tk = o.tick or 5
    local span = math.max(1, sl.max - sl.min)
    if tk > 0 and span / tk <= 40 then
      for v = sl.min, sl.max, tk do
        K.frame(ticks, UD2(0, 1, 0, 3), UD2((v - sl.min) / span, 0, 0, 0), C.LINE, 0.7).Name = "Tick"
      end
    end
  end
  function sl.set(v, quiet)
    local hi = sl.max - sl.lock
    v = math.clamp(math.floor((v or 0) / sl.step + 0.5) * sl.step, sl.min, math.max(sl.min, hi))
    local was = sl.v
    sl.v = v
    draw()
    if not quiet and v ~= was and o.onChange then o.onChange(v) end
  end
  function sl.get() return sl.v end
  function sl.setLock(n)
    sl.lock = math.max(0, n or 0)
    sl.set(sl.v, true)
  end
  function sl.range(lo, hi)
    sl.min, sl.max = lo, hi
    setTicks()
    sl.set(sl.v, true)
  end
  minus.Activated:Connect(function() sl.set(sl.v - sl.step) end)
  plus.Activated:Connect(function() sl.set(sl.v + sl.step) end)
  -- 拖：按住滑块或轨道，鼠标的横坐标换成数（按轨道在屏幕上的位置算）
  local drag = false
  local function fromX(px)
    local ok, a, sz = pcall(function() return track.AbsolutePosition, track.AbsoluteSize end)
    if not ok or not a or sz.X <= 0 then return end
    sl.set(sl.min + (px - a.X) / sz.X * (sl.max - sl.min))
  end
  thumb.MouseEnter:Connect(function() TH.tween(tst, { Transparency = 0 }, "hover", "hover") end)
  thumb.MouseLeave:Connect(function() if not drag then TH.tween(tst, { Transparency = 1 }, "hover", "hover") end end)
  thumb.MouseButton1Down:Connect(function() drag = true end)
  UIS.InputEnded:Connect(function(io)
    if drag and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
      drag = false
      TH.tween(tst, { Transparency = 1 }, "hover", "hover")
    end
  end)
  UIS.InputChanged:Connect(function(io)
    if drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then fromX(io.Position.X) end
  end)
  setTicks()
  draw()
  return sl
end

---------------------------------------------------------------- 对比条（右栏的性能：空挂 vs 这一套，悬停时预览）

-- 一行：左边名字（窄体 13 灰）；右边「空挂 → 当前」（等宽 13：空挂灰、当前白）+ 差值（变差红、变好绿）；
--   悬停预览时换成「当前 → 预览」（预览琥珀）+ 预览比当前的差值；底下一根 3 像素的细条：空挂淡灰、当前白、预览多出 / 少了的那一截琥珀。
--   刻度从 0 起（条长和数成比例，不夸大）；数字比条重要，条只是一眼看出变了多少
local Cmp = {}
Cmp.__index = Cmp
--   narrow（手机）：只写「当前 差值」，空挂只看底下的条
function K.compare(parent, y, w, label, x, narrow)
  x = x or 12
  local row = K.frame(parent, UD2(0, w, 0, 28), UD2(0, x, 0, y), nil, 1)
  row.Name = "Cmp"
  local nm = K.text(row, label, S.small, "cond", C.MUTE, UD2(0, w - (narrow and 104 or 158), 0, 16), UD2(0, 0, 0, 0))
  nm.Name = "Name"
  local delta = K.text(row, "", S.small, "mono", C.MUTE, UD2(0, 44, 0, 16), UD2(1, 0, 0, 0), Enum.TextXAlignment.Right, V2(1, 0))
  delta.Name = "Delta"
  local vb = K.text(row, "", S.small, "mono", C.TEXT, UD2(0, 54, 0, 16), UD2(1, -48, 0, 0), Enum.TextXAlignment.Right, V2(1, 0))
  vb.Name = "Val"
  local arrow = K.text(row, "→", S.small, "mono", C.FAINT, UD2(0, 14, 0, 16), UD2(1, -103, 0, 0), Enum.TextXAlignment.Center, V2(1, 0))
  arrow.Name = "Arrow"
  local va = K.text(row, "", S.small, "mono", C.MUTE, UD2(0, 50, 0, 16), UD2(1, -118, 0, 0), Enum.TextXAlignment.Right, V2(1, 0))
  va.Name = "Base"
  arrow.Visible, va.Visible = not narrow, not narrow
  local track = K.frame(row, UD2(1, 0, 0, 3), UD2(0, 0, 0, 20), C.LINE, 0.93)
  track.Name = "Track"
  local base = K.frame(track, UD2(0, 0, 1, 0), nil, C.FAINT, 0.35)
  base.Name = "BaseBar"
  local cur = K.frame(track, UD2(0, 0, 1, 0), nil, C.TEXT, 0.1)
  cur.Name = "CurBar"
  local prev = K.frame(track, UD2(0, 0, 1, 0), nil, C.WARN, 0)
  prev.Name = "PrevBar"
  prev.Visible = false
  return setmetatable({ f = row, nm = nm, delta = delta, vb = vb, va = va, arrow = arrow, base = base, cur = cur, prev = prev,
    key = tostring(row) .. tostring(math.random()) }, Cmp)
end
-- base 空挂、cur 当前、pv 悬停预览（nil 不预览）；o = { fmt(数) → 字, dfmt(差) → 字, better = 1 越大越好 / −1 越小越好 / 0 不分 }
function Cmp:set(base, cur, pv, o)
  local fmt = o.fmt
  local dfmt = o.dfmt or function(v) return K.signed(v) end
  local better = o.better or 1
  local function shade(d)
    if math.abs(d) < (o.eps or 1e-6) or better == 0 then return C.MUTE end
    return ((d * better) > 0) and C.GOOD or C.BAD
  end
  local from = (pv ~= nil) and cur or base
  local to = (pv ~= nil) and pv or cur
  self.va.Text = fmt(from)
  self.va.TextColor3 = (pv ~= nil) and C.TEXT or C.MUTE
  K.roll(self.vb, self.key .. "v", self.shown, to, fmt)
  self.shown = to
  self.vb.TextColor3 = (pv ~= nil) and C.WARN or C.TEXT
  local d = to - from
  self.delta.Text = (math.abs(d) < (o.eps or 1e-6)) and "" or dfmt(d)
  self.delta.TextColor3 = shade(d)
  local mx = math.max(base, cur, pv or 0, 1e-6)
  TH.tween(self.base, { Size = UD2(math.clamp(base / mx, 0, 1), 0, 1, 0) }, "num", "out")
  TH.tween(self.cur, { Size = UD2(math.clamp(cur / mx, 0, 1), 0, 1, 0) }, "num", "out")
  if pv ~= nil and math.abs(pv - cur) > 1e-9 then
    local a, b = math.min(pv, cur) / mx, math.max(pv, cur) / mx
    self.prev.Visible = true
    self.prev.Position = UD2(math.clamp(a, 0, 1), 0, 0, 0)
    TH.tween(self.prev, { Size = UD2(math.clamp(b - a, 0, 1), 0, 1, 0) }, "num", "out")
  else
    self.prev.Visible = false
  end
end
-- 只写一个数（没有对比的行：直升机的续航这种）
function Cmp:plain(txt, col)
  self.va.Text, self.arrow.Visible, self.delta.Text = "", false, ""
  K.stop(self.key .. "v")
  self.vb.Text = txt
  self.vb.TextColor3 = col or C.TEXT
  self.base.Size, self.cur.Size = UD2(0, 0, 1, 0), UD2(0, 0, 1, 0)
  self.prev.Visible = false
end

---------------------------------------------------------------- 引线标签（3D 挂点：6 像素的点、1 像素引线、22 高的小标签「3 · PL-15」）

local Tag = {}
Tag.__index = Tag
function K.tagW(txt) return math.max(20, math.floor(K.textW(txt, S.tiny) + 12)) end
function K.tag(layer, name)
  local dot = K.frame(layer, UD2(0, 6, 0, 6), nil, C.TEXT, 0, V2(0.5, 0.5))
  dot.Name = "Dot"
  round(dot)
  local ring = Instance.new("UIStroke")
  ring.Color, ring.Thickness, ring.Transparency = C.FAINT, 1, 1
  ring.Parent = dot
  local ln = K.frame(layer, nil, nil, C.MUTE, 0.45)
  ln.Name = "Leader"
  local b = Instance.new("TextButton")
  b.Name = name or "Tag"
  b.AutoButtonColor = false
  b.Text = ""
  b.BackgroundColor3 = C.PANEL
  b.BackgroundTransparency = 0.22
  b.BorderSizePixel = 0
  b.Size = UD2(0, 24, 0, 18)
  b.AnchorPoint = V2(0.5, 0)
  b.Parent = layer
  TH.corner(b)
  local st = TH.stroke(b)
  local t = K.text(b, "", S.tiny, "cond", C.TEXT, UD2(1, -8, 1, 0), UD2(0, 4, 0, 0), Enum.TextXAlignment.Center)
  t.Name = "Text"
  return setmetatable({ dot = dot, ring = ring, ln = ln, b = b, st = st, t = t, w = 24 }, Tag)
end
function Tag:show(on)
  self.dot.Visible, self.ln.Visible, self.b.Visible = on, on, on
end
-- 摆：dot (x, y) 是挂点在画面上的位置、lab (x, y) 是标签上沿中点；o = { text, empty, sel, hov, alpha（0～1，整体淡：远处那一侧的挂点）}
--   标签宽按字估（K.tagW）
function Tag:place(dx, dy, lx, ly, o)
  local a = o.alpha or 1
  local col = o.sel and C.WARN or ((o.empty and not o.hov) and C.FAINT or C.TEXT)
  local tr = 1 - a
  self.dot.Position = UD2(0, dx, 0, dy)
  self.dot.Size = o.sel and UD2(0, 8, 0, 8) or UD2(0, 6, 0, 6)
  self.dot.BackgroundColor3 = col
  self.dot.BackgroundTransparency = o.empty and 1 or tr
  self.ring.Transparency = o.empty and (0.1 + 0.9 * tr) or 1
  self.ring.Color = col
  K.line(self.ln, dx, dy + 4, lx, ly, 1)
  self.ln.BackgroundColor3 = o.sel and C.WARN or C.MUTE
  self.ln.BackgroundTransparency = o.sel and (0.1 + 0.9 * tr) or (0.5 + 0.5 * tr)
  if o.text ~= self.t.Text then
    self.t.Text = o.text
    self.w = K.tagW(o.text)
  end
  self.b.Size = UD2(0, self.w, 0, 18)
  self.b.Position = UD2(0, lx, 0, ly)
  self.b.BackgroundTransparency = 0.22 + 0.78 * tr
  self.t.TextColor3 = col
  self.t.TextTransparency = tr
  self.st.Color = o.sel and C.WARN or C.LINE
  self.st.Transparency = o.sel and (0.1 + 0.9 * tr) or ((o.hov and A.lineHi or A.line) + (1 - (o.hov and A.lineHi or A.line)) * tr)
end

---------------------------------------------------------------- 武器剪影（这一轮先用线条剪影顶上，下一轮换 Blender 渲的图）
-- 照弹药栏（WtTank.lua）剪影的笔法：横放、弹头朝右，单色；但尺寸按真弹的外形（AirDefs.W[...].shape：弹长 L、弹径 d，格），
--   弹头样式、尾翼 / 弹翼 / 鸭翼的位置和大小、炸弹尾翼套件、火箭巢、副油箱按 WeaponModels 的描述（同一枚弹在 3D 里、剪影里一个样子）——
--   一张一张不一样：霹雳-15 细长带边条、霹雳-10 短而大舵面、不死鸟又粗又长、激光制导炸弹前面一个导引头、联合直接攻击弹药一套灰尾翼……
--   px：每格多少像素——同一个挂点的几种弹、同一架飞机的挂点卡一个比例尺（长的就是长、粗的就是粗，像一张弹药识别图）
local WM, AD = nil, nil
local function libs()
  if not WM then
    local ok, m = pcall(function() return require(RS:WaitForChild("WeaponModels", 5)) end)
    WM = ok and m or false
  end
  if not AD then
    local ok, m = pcall(function() return require(RS:WaitForChild("AirDefs", 5)) end)
    AD = ok and m or false
  end
  return WM or nil, AD or nil
end
local function descOf(wid, w)
  local wm = libs()
  local d = wm and wm.D and wm.D[wid]
  if d then return d end
  if w and w.kind == "bomb" then return { nose = "bomb", kit = "mk" } end
  if w and w.kind == "tank" then return { tank = true } end
  if w and w.kind == "rkt" then return { pod = true } end
  return { nose = "radar", tail = { at = 0.92, c = 0.09, s = 2 } }
end
-- 剪影一共多长、多高（格：高算上上下的翼面）——给 K.artScale 定比例尺
function K.artExtent(wid)
  local _, ad = libs()
  local w = ad and ad.W[wid]
  if not w then return 6, 1 end
  local sh = w.shape or { L = 5, d = 0.6 }
  local L, d = sh.L, sh.d
  local ds = descOf(wid, w)
  if ds.tank or ds.pod then return L, d * 1.15 end
  if w.kind == "bomb" then return L, d * ((ds.kit == "paveway") and 2.3 or ((ds.kit == "jdam") and 1.7 or 1.35)) end
  local s = 0
  for _, F in ipairs({ ds.tail, ds.mid, ds.can }) do
    if F then s = math.max(s, F.strake and F.s * 0.4 or F.s) end
  end
  return L, d * (1 + 2 * 0.707 * s)
end
-- 这几种弹放进 w × h 的框（四周留 pad 像素）用多大的比例尺：最长 / 最高的那种正好放下
function K.artScale(wids, w, h, pad)
  pad = pad or 3
  local px = 1e9
  for _, wid in ipairs(wids) do
    if wid then
      local L, H = K.artExtent(wid)
      px = math.min(px, (w - 2 * pad) / math.max(L, 0.1), (h - 2 * pad) / math.max(H, 0.05))
    end
  end
  return (px < 1e8) and px or 4
end
-- 在 box（w × h 像素）里画 wid 的剪影：o = { px 比例尺, col 颜色, tr 透明度, n 一个挂点挂几枚（≥ 2 时后面错开画一枚淡的）, dx, dy }
function K.weaponArt(box, wid, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local _, ad = libs()
  local W0 = ad and ad.W[wid]
  if not W0 then return nil end
  local px = o.px or K.artScale({ wid }, w, h)
  local col = o.col or C.TEXT
  local tr0 = o.tr or 0.06
  local cut = C.BG
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local sh = W0.shape or { L = 5, d = 0.6 }
  local L, d = sh.L, sh.d
  local ds = descOf(wid, W0)
  local function draw(ox, oy, trK)
    local x0 = (w - L * px) / 2 + ox
    local yc = h / 2 + oy
    local function X(x) return x0 + x * px end
    local function Y(y) return yc - y * px end
    local function tr(t) return 1 - (1 - (t or tr0)) * trK end
    -- 一块：x 从 a 到 b（格，从弹尾量起）、中心高 y、高 hh；rr = true 两头圆
    local function blk(a, b, y, hh, rr, t, c2)
      local wp = math.max(1, (b - a) * px)
      local hp = math.max(1, hh * px)
      local f = K.frame(art, UD2(0, wp, 0, hp), UD2(0, X((a + b) / 2), 0, Y(y)), c2 or col, tr(t), V2(0.5, 0.5))
      if rr then round(f) end
      return f
    end
    local function ln(xa, ya, xb, yb, th, t)
      local f = K.frame(art, nil, nil, col, tr(t))
      K.line(f, X(xa), Y(ya), X(xb), Y(yb), math.max(1, th or 1))
      return f
    end
    -- 后掠的三角翼：后缘竖着在 xa、翼根贴着弹体表面 y0（从 xa 到前面的 xb）、翼尖在 (xa, y0 + 方向 × hh)
    local function fin(xa, xb, y0, hh, dir, t)
      local ch = math.abs(xb - xa)
      blk(xa, xa + math.max(ch * 0.2, 1 / px), y0 + dir * hh / 2, hh, nil, t)
      blk(xa, xa + ch * 0.5, y0 + dir * hh / 4, hh / 2, nil, t)
      ln(xb, y0, xa, y0 + dir * hh, math.max(1, math.min(ch, hh) * px * 0.3), t)
    end
    local function band(at, frac)   -- 弹体上的环带：暗一道
      local x = L - at * L
      local bw = math.max(frac * L, 1 / px)
      blk(x - bw / 2, x + bw / 2, 0, d * 0.98, nil, 0.45, cut)
    end
    if ds.tank then   -- 副油箱：两头收尖的流线长筒、两道焊缝；有的尾部小安定面
      blk(L * 0.3, L * 0.72, 0, d)
      blk(L * 0.5, L * 0.97, 0, d, true)
      blk(L * 0.86, L, 0, d * 0.46, true)
      blk(L * 0.1, L * 0.52, 0, d * 0.84, true)
      blk(L * 0.0, L * 0.24, 0, d * 0.42, true)
      band(0.47, 0.006)
      band(0.27, 0.006)
      if ds.fins then
        fin(L * 0.04, L * 0.17, -d * 0.22, d * 0.34, -1, 0.15)
        fin(L * 0.04, L * 0.17, d * 0.22, d * 0.24, 1, 0.3)
      end
      return
    end
    if ds.pod then   -- 火箭巢：粗圆筒、前后整流罩、前端发射管口那一面、一道环带、两排管子的影子
      blk(L * 0.11, L * 0.89, 0, d)
      blk(L * 0.72, L, 0, d, true)
      blk(L * 0.0, L * 0.26, 0, d * 0.96, true)
      blk(L * 0.975, L, 0, d * 0.8, nil, 0.25, cut)
      band(0.3, 0.035)
      for _, yy in ipairs({ -0.22, 0.22 }) do blk(L * 0.16, L * 0.84, yy * d, math.max(1 / px, d * 0.05), nil, 0.72, cut) end
      return
    end
    if W0.kind == "bomb" then
      local nose = ds.nose or "bomb"
      if nose == "laser" then   -- 激光制导炸弹：战斗部的圆头、细脖子上的导引头、四片鸭翼
        blk(L * 0.2, L * 0.74, 0, d)
        blk(L * 0.55, L * 0.86, 0, d * 0.9, true)
        blk(L * 0.8, L * 0.95, 0, d * 0.5)
        blk(L * 0.9, L, 0, d * 0.56, true)
        for _, dir in ipairs({ 1, -1 }) do fin(L * 0.83, L * 0.9, dir * d * 0.25, d * 0.34, dir, 0.15) end
      else   -- 普通炸弹 / 卫星制导：钝圆的卵形头（制导的前面一个引信）
        blk(L * 0.22, L * 0.72, 0, d)
        blk(L * 0.5, L * 0.93, 0, d, true)
        blk(L * 0.78, L * 0.985, 0, d * 0.58, true)
        if nose == "jdam" then blk(L * 0.97, L, 0, d * 0.22) end
      end
      for _, b in ipairs(ds.bands or {}) do band(b[1], b[2]) end
      local kit = ds.kit or "mk"
      if kit == "mk" then   -- 低阻尾锥 + 方尾翼
        blk(L * 0.1, L * 0.23, 0, d * 0.8)
        blk(L * 0.02, L * 0.11, 0, d * 0.52)
        for _, dir in ipairs({ 1, -1 }) do blk(L * 0.01, L * 0.18, dir * d * 0.42, d * 0.36, nil, 0.22) end
      elseif kit == "jdam" or kit == "sdb" then   -- 卫星制导尾翼套件：灰色尾段、四片长尾翼、弹体边条
        blk(L * 0.01, L * 0.25, 0, d * 0.86)
        blk(L * -0.005, L * 0.015, 0, d * 0.6)
        local fh = d * ((kit == "sdb") and 0.42 or 0.62) * 0.707
        for _, dir in ipairs({ 1, -1 }) do
          fin(L * 0.01, L * 0.17, dir * d * 0.43, fh, dir, 0.12)
          if kit == "jdam" then blk(L * 0.37, L * 0.67, dir * d * 0.52, math.max(d * 0.08, 1 / px), nil, 0.25) end
        end
      elseif kit == "paveway" then   -- 激光制导炸弹的大尾翼
        blk(L * 0.0, L * 0.2, 0, d * 0.7)
        for _, dir in ipairs({ 1, -1 }) do blk(L * 0.0, L * 0.2, dir * d * 0.6, d * 0.58, nil, 0.25) end
      end
      if ds.wing then   -- 折叠弹翼（雷石-6、小直径炸弹）：挂着时折在弹体上面
        local Wd = ds.wing
        local xc = L - Wd.at * L - Wd.span * 0.2
        blk(xc - Wd.span * 0.25, xc + Wd.span * 0.25, d * 0.58, math.max(0.1, 1 / px), nil, 0.1)
      end
      return
    end
    -- 导弹（空空 / 空地 / 地空）
    local nose = ds.nose or "radar"
    local noseL = (nose == "radar" or nose == "arm") and L * 0.16 or L * 0.09
    blk(L * 0.012, L - noseL, 0, d)
    blk(0, L * 0.02, 0, d * 0.66)   -- 尾喷口
    if nose == "radar" or nose == "arm" then   -- 雷达罩：细长的尖头
      blk(L - noseL - d * 0.5, L - noseL * 0.3, 0, d, true)
      blk(L - noseL * 0.72, L, 0, d * 0.46, true)
    elseif nose == "laser" then   -- 激光：细一点的导引头
      blk(L - noseL * 1.25, L - d * 0.3, 0, d * 0.84)
      blk(L - d * 0.9, L, 0, d * 0.84, true)
    else   -- 红外 / 电视：半球形的玻璃罩
      blk(L - noseL - d * 0.6, L, 0, d, true)
    end
    for _, b in ipairs(ds.bands or {}) do band(b[1], b[2]) end
    local function fins(Fd)
      if not Fd then return end
      local xc = L - Fd.at * L
      local ch = Fd.c * L
      local sp = Fd.s * d * 0.707   -- X 形的四片：侧面看上下各一片，展长 × cos 45°
      for _, dir in ipairs({ 1, -1 }) do
        if Fd.grid then   -- 栅格翼（R-77）：一个细框
          local f = blk(xc - ch / 2, xc + ch / 2, dir * (d / 2 + sp / 2), sp, nil, 1)
          local s = Instance.new("UIStroke")
          s.Color, s.Thickness, s.Transparency = col, 1, tr(0.15)
          s.Parent = f
        elseif Fd.strake then   -- 长边条：贴着弹体的细长翼
          blk(xc - ch / 2, xc + ch / 2, dir * (d / 2 + sp * 0.2), sp * 0.4, nil, 0.2)
        else
          fin(xc - ch / 2, xc + ch / 2, dir * d / 2, sp, dir, 0.12)
        end
      end
    end
    fins(ds.tail)
    fins(ds.mid)
    fins(ds.can)
    if ds.wing then   -- 巡航弹的折叠弹翼（KD-88、鹰击-83K）：挂着时折在弹体上面
      local Wd = ds.wing
      local xc = L - Wd.at * L - Wd.span * 0.2
      blk(xc - Wd.span * 0.25, xc + Wd.span * 0.25, d * 0.58, math.max(0.1, 1 / px), nil, 0.1)
    end
  end
  local n = o.n or 1
  if n >= 2 then draw(-math.max(3, L * px * 0.06), -math.max(3, d * px * 0.9), 0.4) end   -- 多联挂架：后面错开一枚淡的
  draw(o.dx or 0, o.dy or 0, 1)
  return art
end
-- 机炮（航炮固定卡）：机匣、一根或几根炮管、炮口、供弹槽；几管按型号
local GUN_BARRELS = { m61 = 3, gau8 = 3, gau22 = 3, m134 = 3, yakb = 3, m197 = 3, gsh23 = 2, gsh302 = 2 }
function K.gunArt(box, gid, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local col = o.col or C.TEXT
  local n = GUN_BARRELS[gid or ""] or 1
  local cy = h / 2
  local x0, x1 = w * 0.1, w * 0.92
  K.frame(art, UD2(0, w * 0.32, 0, h * 0.34), UD2(0, x0, 0, cy - h * 0.17), col, 0.06).Name = "Receiver"
  local gap = math.max(2, h * 0.09)
  for i = 1, n do
    local y = cy + (i - (n + 1) / 2) * gap
    K.frame(art, UD2(0, x1 - (x0 + w * 0.3), 0, math.max(1, h * 0.06)), UD2(0, x0 + w * 0.3, 0, y - math.max(1, h * 0.06) / 2), col, 0.06).Name = "Barrel"
  end
  K.frame(art, UD2(0, w * 0.06, 0, math.max(2, h * 0.08 + (n - 1) * gap)), UD2(0, x1 - w * 0.06, 0, cy - math.max(2, h * 0.08 + (n - 1) * gap) / 2), col, 0.06).Name = "Muzzle"
  local chute = K.frame(art, nil, nil, col, 0.35)
  K.line(chute, x0 + w * 0.06, cy + h * 0.17, x0 - w * 0.02, cy + h * 0.4, math.max(1, h * 0.08))
  return art
end
-- 干扰弹（固定卡）：一排四发药筒
function K.flareArt(box, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local col = o.col or C.TEXT
  local cw, ch = math.max(4, w * 0.1), math.max(8, h * 0.56)
  for i = 0, 3 do
    local x = w * 0.5 + (i - 1.5) * (cw + math.max(2, w * 0.035)) - cw / 2
    K.frame(art, UD2(0, cw, 0, ch), UD2(0, x, 0, h / 2 - ch / 2 + 2), col, 0.06).Name = "Case"
    round(K.frame(art, UD2(0, cw, 0, cw), UD2(0, x, 0, h / 2 - ch / 2 - cw / 2 + 2), col, 0.06)).Name = "Cap"
    K.frame(art, UD2(0, cw, 0, 1), UD2(0, x, 0, h / 2 + ch / 2 - 3), C.BG, 0.4).Name = "Rim"
  end
  return art
end

return K
