-- 全面大战场（客户端）——整备（Workshop）共用的界面零件：面板、卡片、小块、分段键、勾选框、拖动条、对比行、引线标签、武器剪影、数字滚动
--   用户 11-27：「整个给载具配置武器的系统 做的很粗糙 我需要非常艺术经验的效果 参考战雷」——要的是同类写实军事游戏那种精致、克制、写实的质感，
--   用我们自己的界面美术（docs/style.md、Theme.lua）。卡片和战斗里的弹药栏（WtTank.lua）同一套画法：平涂深色半透明底 + 1 像素细线、圆角 2，
--   不要玻璃渐变、不抬起；选中 = 琥珀细描边 + 贴底 2 像素琥珀线；装着的那个 = 左边 2 像素白竖条（同弹药栏膛里那发）；图后面垫一块横向柔光。
--   白底只给页签和主按钮（一屏最多两块）；次级的选中（预设、内油……）用 Theme.setPicked。颜色只表意：琥珀 = 正在改 / 预览 / 改过，
--   绿 / 红只说「这次换上会变好 / 变差」，灰 = 锁住 / 空；不用蓝。中文小字一律用粗一档（K.text 自动换，docs/style.md 第 6 条）。
--   动效时长、缓动从 Theme.T / Theme.EASE 取（docs/style.md「动效」），每一处都能被打断：同一个东西再动一次，从它现在的样子接着走。
--   Workshop.lua（外壳）、WsArms.lua（挂载页）用；以后的弹药 / 改装 / 乘员 / 涂装页同一套
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TH = require(RS:WaitForChild("Theme"))

local K = { TH = TH }
local C, A, F, S = TH.C, TH.A, TH.F, TH.S
local UD2, V2 = UDim2.new, Vector2.new
local RIGHT = Enum.TextXAlignment.Right

---------------------------------------------------------------- 字：中文小字粗一档

-- Roboto 系（等宽、窄体）没有中文字形：13 号以下的中文退到引擎的后备字体，字重跟着 Regular / Medium 走，比 Bold 细一档（docs/style.md 第 6 条不许）——
--   K.text 建的字都按这一条：字号 ≤ 13、字里有中文、字体是窄体 / 正文的，换成 Bold；等宽的字里数字和中文混着（「巡航 18 分钟」）：开 RichText，
--   只把中文那几段包成 Builder Sans Bold，数字照旧等宽。之后改 Text 也照这条（盯着 Text 变）
local BOLD_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local function hasCJK(s)
  for _, cp in utf8.codes(s or "") do if cp >= 0x2E80 then return true end end
  return false
end
K.hasCJK = hasCJK
local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
-- 一段字里的中文包成 Builder Sans Bold（RichText 的写法）；别的字照原样（转义）
local function boldCJK(s)
  local out, run, inC = {}, {}, nil
  local function flush()
    if #run == 0 then return end
    local t = esc(table.concat(run))
    if inC then t = '<font family="' .. BOLD_FAMILY .. '" weight="bold">' .. t .. "</font>" end
    out[#out + 1] = t
    run = {}
  end
  for _, cp in utf8.codes(s) do
    local c = cp >= 0x2E80
    if c ~= inC then
      flush()
      inC = c
    end
    run[#run + 1] = utf8.char(cp)
  end
  flush()
  return table.concat(out)
end
K.boldCJK = boldCJK
local function hex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
K.hex = hex
-- 几段字拼一行（RichText；标签要开 RichText）：parts = { { 字, 颜色（可选）, 字号（可选） }, … }；字号 ≤ 13 的段里的中文自动包成粗体。
--   base：这个标签自己的字号（段没写字号时按它判断大小）
function K.rich(parts, base)
  local out = {}
  for _, p in ipairs(parts) do
    local s = p[1] or ""
    if s ~= "" then
      local sz = p[3] or base or S.small
      local body = esc(s)   -- 中文小字不再自动加粗（用户 11-27「我觉得字体可以细一点」）
      local at = {}
      if p[2] then at[#at + 1] = 'color="' .. hex(p[2]) .. '"' end
      if p[3] then at[#at + 1] = 'size="' .. tostring(p[3]) .. '"' end
      if #at > 0 then body = "<font " .. table.concat(at, " ") .. ">" .. body .. "</font>" end
      out[#out + 1] = body
    end
  end
  return table.concat(out)
end
local function fitFont(t)
  local s = t.Text
  if s:find("<font", 1, true) then return end   -- 自己拼好的 RichText（K.rich / 已经包过的）
  local kind = t:GetAttribute("FK") or "body"
  -- 中文小字不再自动换粗体（用户 11-27「我觉得字体可以细一点」：整体降一档，层级靠字号、颜色，不靠加粗）
  t.Font = F[kind] or F.body
end
K.fitFont = fitFont

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
-- 字：font 是 Theme.F 的键（body / bold / title / mono / cond）；一行、放不下截掉（…）；中文小字自动粗一档（见上）
function K.text(parent, str, ts, font, col, size, pos, align, anchor)
  local t = Instance.new("TextLabel")
  t.BackgroundTransparency = 1
  t.BorderSizePixel = 0
  t.TextSize = ts or S.body
  t.Font = F[font or "body"] or F.body
  t:SetAttribute("FK", font or "body")
  t.Text = str or ""
  t.TextColor3 = col or C.TEXT
  t.TextXAlignment = align or Enum.TextXAlignment.Left
  t.TextYAlignment = Enum.TextYAlignment.Center
  t.TextTruncate = Enum.TextTruncate.AtEnd
  t.Size = size or UD2(1, 0, 0, (ts or S.body) + 4)
  t.Position = pos or UD2(0, 0, 0, 0)
  t.AnchorPoint = anchor or V2(0, 0)
  fitFont(t)
  t:GetPropertyChangedSignal("Text"):Connect(function() fitFont(t) end)
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
-- 两点之间一根线（像素坐标，同一个父零件里）：转角度的细条（画尖角、勾这种小图形用；引线只走横竖，见 Tag:path）
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
function K.textW(s, ts, mono, heavy)
  local w = 0
  for _, cp in utf8.codes(tostring(s or "")) do
    if cp >= 0x2E80 then w += ts
    elseif cp == 32 then w += ts * 0.3
    else w += ts * (mono and 0.6 or (heavy and 0.66 or 0.54)) end
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
  a.Name = "Stroke"
  K.line(a, size * 0.68, size * 0.12, size * 0.28, size * 0.52, th or 1.5)
  local b = K.frame(box, nil, nil, col or C.TEXT, 0)
  b.Name = "Stroke"
  K.line(b, size * 0.28, size * 0.48, size * 0.68, size * 0.88, th or 1.5)
  return box
end
function K.tintChevron(box, col)
  for _, s in ipairs(box:GetChildren()) do if s:IsA("Frame") then s.BackgroundColor3 = col end end
end
-- 勾（「已保存」后面那个）：两笔细线，size 像素见方
function K.tick(parent, x, y, size, col, th)
  local box = K.frame(parent, UDim2.new(0, size, 0, size), UDim2.new(0, x, 0, y), nil, 1)
  box.Name = "Tick"
  K.line(K.frame(box, nil, nil, col or C.MUTE, 0), size * 0.08, size * 0.55, size * 0.38, size * 0.85, th or 1.5)
  K.line(K.frame(box, nil, nil, col or C.MUTE, 0), size * 0.34, size * 0.85, size * 0.94, size * 0.2, th or 1.5)
  return box
end
-- 加号（空着的「我的方案」）：一横一竖
function K.plus(parent, x, y, size, col)
  local box = K.frame(parent, UDim2.new(0, size, 0, size), UDim2.new(0, x, 0, y), nil, 1)
  box.Name = "Plus"
  K.frame(box, UD2(1, 0, 0, 1), UD2(0, 0, 0.5, 0), col or C.FAINT, 0, V2(0, 0.5))
  K.frame(box, UD2(0, 1, 1, 0), UD2(0.5, 0, 0, 0), col or C.FAINT, 0, V2(0.5, 0))
  return box
end
-- 键位框（同弹药栏左上那个：14 × 14、1 像素描边、等宽 12）：挂点卡的编号、空着的「我的方案」
function K.keyBox(parent, str, x, y, col, name)
  local w = math.max(14, math.floor(K.textW(str, S.tiny, true) + 6))
  local b = Instance.new("TextLabel")
  b.Name = name or "Key"
  b.BackgroundTransparency = 1
  b.BorderSizePixel = 0
  b.Text = str
  b.Font = F.mono
  b.TextSize = S.tiny
  b.TextColor3 = col or C.MUTE
  b.TextXAlignment = Enum.TextXAlignment.Center
  b.Size = UD2(0, w, 0, 14)
  b.Position = UD2(0, x, 0, y)
  b.Parent = parent
  local s = TH.stroke(b)
  s.Color, s.Transparency = col or C.MUTE, 0
  return b, w
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
-- 数字滚动（docs/style.md：数字变化 0.22 秒先快后慢）：从显示着的数滚到新的；fmt(数) → 字。只在点了装上、改内油的时候滚（悬停预览直接换：扫一列卡时右栏的数不一直转）
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

---------------------------------------------------------------- 面板、柔光、分节标题

-- 面板（整备的左栏、右栏）：深色底（整备 0.06：几乎不透，背后的机库横梁、地标线不压在字上），竖向一点点渐变（RAISE 渐到 BG），1 像素细线、圆角 2；
--   挡住后面的拖车（Active）
function K.panel(parent, size, pos, anchor, tr)
  local f = K.frame(parent, size, pos, Color3.new(1, 1, 1), tr or A.panel, anchor)
  f.Active = true
  TH.grad(f, C.RAISE, C.BG)
  TH.corner(f)
  TH.stroke(f)
  return f
end
-- 图后面一块横向柔光（同弹药栏 WtTank.lua：白、透明 0.92，横着 1 → 0 → 1 渐变；不描边、不圆角、不套框）：深色的弹体从暗底上分出来
function K.lightbox(parent, size, pos)
  local f = K.frame(parent, size, pos, Color3.new(1, 1, 1), 0.92)
  f.Name = "Plate"
  local g = Instance.new("UIGradient")
  g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
  g.Parent = f
  return f
end
K.plate = K.lightbox
-- 分节标题：13 号灰字（中文自动粗一档）+ 右边一道到头的细线（技术图纸那种）
function K.header(parent, str, y, w, x)
  x = x or 12
  local t = K.text(parent, str, S.small, "cond", C.MUTE, UD2(0, w, 0, 16), UD2(0, x, 0, y))
  t.Name = "Head"
  local tw = K.textW(str, S.small) + 8
  local ln = K.frame(parent, UD2(0, math.max(0, w - tw), 0, 1), UD2(0, x + tw, 0, y + 8), C.LINE, A.line)
  ln.Name = "HeadLine"
  return t, ln
end
-- 虚线框（「不挂」那张卡）：沿四边画 1 像素的短线；w × h 是框的像素大小
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

---------------------------------------------------------------- 卡片（同弹药栏的格子）

local Card = {}
Card.__index = Card
-- 卡片（挂点卡、武器卡、固定卡）：平涂深色半透明底（PANEL 0.35）+ 1 像素细线、圆角 2；悬停描边变亮（0.82 → 0.45），不抬起；
--   选中：1 像素琥珀描边 + 贴底 2 像素琥珀线；装着的（own）：左边 2 像素白竖条；dim：空着的（底更淡 0.6）
--   o：{ name, tr 底的透明度, still = true 不能点的（固定卡：悬停不变亮）, onEnter, onLeave, onClick }
function K.card(parent, size, pos, o)
  o = o or {}
  local b = Instance.new("TextButton")
  b.Name = o.name or "Card"
  b.Text = ""
  b.AutoButtonColor = false
  b.Size, b.Position = size, pos
  b.BackgroundColor3 = C.PANEL
  b.BackgroundTransparency = o.tr or 0.35
  b.BorderSizePixel = 0
  b.Parent = parent
  TH.corner(b)
  local st = TH.stroke(b)
  local sl = K.frame(b, UD2(1, 0, 0, 2), UD2(0, 0, 1, -2), C.WARN, 0)
  sl.Name = "SelLine"
  sl.Visible = false
  sl.ZIndex = 4
  local ob = K.frame(b, UD2(0, 2, 1, 0), nil, C.TEXT, 0)
  ob.Name = "OwnBar"
  ob.Visible = false
  ob.ZIndex = 4
  local cd = setmetatable({ f = b, st = st, selLine = sl, ownBar = ob, pos = pos, sel = false, hov = false, own = false, o = o, tr = o.tr or 0.35 }, Card)
  if not o.still then
    b.MouseEnter:Connect(function()
      cd:setHover(true)
      if o.onEnter then o.onEnter(cd) end
    end)
    b.MouseLeave:Connect(function()
      cd:setHover(false)
      if o.onLeave then o.onLeave(cd) end
    end)
  end
  if o.onClick then b.Activated:Connect(function() o.onClick(cd) end) end
  return cd
end
local function cardLook(cd)
  local st = cd.st
  if cd.sel then
    st.Color = C.WARN
    TH.tween(st, { Transparency = 0 }, "hover", "out")
  else
    st.Color = C.LINE
    TH.tween(st, { Transparency = cd.hov and A.lineHi or (cd.restT or A.line) }, "hover", "hover")
  end
  cd.selLine.Visible = cd.sel
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
function Card:setOwn(on)
  self.own = on == true
  self.ownBar.Visible = self.own
end
function Card:setDim(on) self.f.BackgroundTransparency = on and 0.6 or self.tr end
function Card:move(pos)
  self.pos = pos
  self.f.Position = pos
end

---------------------------------------------------------------- 小块（方案、预设）、分段键、勾选框

local Chip = {}
Chip.__index = Chip
-- 小块（预设、我的方案）：Theme.setPicked——选中 RAISE 底 + 白细线 + 底边 2 像素白线、字白；没选中透明底 + 细线、字灰（悬停字白、线亮）；
--   照这套改过：右边一个琥珀小字「已改」
function K.chip(parent, str, size, pos, o)
  o = o or {}
  local b = Instance.new("TextButton")
  b.Name = o.name or "Chip"
  b.Text = ""
  b.AutoButtonColor = false
  b.Size, b.Position = size, pos
  b.BorderSizePixel = 0
  b.Parent = parent
  TH.corner(b)
  local pad = (size.X.Offset > 0 and size.X.Offset < 80) and 6 or 8   -- 小块窄（手机一行三个）：字的边距收一点，「防空压制」放得下
  local t = K.text(b, str, S.small, "bold", C.MUTE, UD2(1, -2 * pad, 1, 0), UD2(0, pad, 0, 0))
  t.Name = "Label"
  local mod = K.text(b, "", S.tiny, "bold", C.WARN, UD2(0, 34, 1, 0), UD2(1, -7, 0, 0), RIGHT, V2(1, 0))
  mod.Name = "Mod"
  mod.Visible = false
  local ch = setmetatable({ f = b, t = t, mod = mod, on = false, hov = false, o = o }, Chip)
  TH.setPicked(b, false)
  b.MouseEnter:Connect(function() ch:hover(true) end)
  b.MouseLeave:Connect(function() ch:hover(false) end)
  if o.onClick then b.Activated:Connect(function() o.onClick(ch) end) end
  return ch
end
function Chip:hover(on)
  self.hov = on == true
  if self.on or self.off then return end
  local s = self.f:FindFirstChildOfClass("UIStroke")
  if s then TH.tween(s, { Transparency = self.hov and A.lineHi or (self.empty and 1 or A.line) }, "hover", "hover") end
  self.t.TextColor3 = self.hov and C.TEXT or C.MUTE
end
function Chip:set(on, modTxt)
  self.on = on == true
  TH.setPicked(self.f, self.on)
  if not self.on and self.hov then self.t.TextColor3 = C.TEXT end
  self.mod.Visible = modTxt ~= nil and modTxt ~= ""
  self.mod.Text = modTxt or ""
  local pad = self.t.Position.X.Offset
  self.t.Size = UD2(1, self.mod.Visible and -46 or -2 * pad, 1, 0)
end

-- 分段键（内油 25 / 50 / 75 / 100）：一排小块（间距 4），选中的 Theme.setPicked；opts = { { key, text, name } … }；o.onPick(键)
function K.seg(parent, opts, size, pos, o)
  o = o or {}
  local box = K.frame(parent, size, pos, nil, 1)
  box.Name = o.name or "Seg"
  local n = #opts
  local gap = o.gap or 4
  local sg = { f = box, btns = {}, cur = nil, on = true }
  for i, op in ipairs(opts) do
    local b = Instance.new("TextButton")
    b.Name = op.name or ("Seg_" .. tostring(op.key))
    b.AutoButtonColor = false
    b.Text = op.text or tostring(op.key)
    b.Font = F.bold
    b.TextSize = o.ts or S.small
    b.BorderSizePixel = 0
    b.Size = UD2(1 / n, -gap * (n - 1) / n, 1, 0)
    b.Position = UD2((i - 1) / n, (i - 1) * gap / n, 0, 0)
    b.Parent = box
    TH.corner(b)
    TH.setPicked(b, false)
    b.MouseEnter:Connect(function()
      if sg.cur ~= op.key and sg.on then
        b.TextColor3 = C.TEXT
        TH.tween(b:FindFirstChildOfClass("UIStroke"), { Transparency = A.lineHi }, "hover", "hover")
      end
    end)
    b.MouseLeave:Connect(function()
      if sg.cur ~= op.key and sg.on then
        b.TextColor3 = C.MUTE
        TH.tween(b:FindFirstChildOfClass("UIStroke"), { Transparency = A.line }, "hover", "hover")
      end
    end)
    b.Activated:Connect(function() if sg.on and o.onPick then o.onPick(op.key) end end)
    sg.btns[op.key] = b
  end
  function sg.set(k)
    sg.cur = k
    for key, b in pairs(sg.btns) do TH.setPicked(b, key == k) end
  end
  function sg.enable(on)
    sg.on = on == true
    for key, b in pairs(sg.btns) do
      b.Active = sg.on
      if not sg.on and key ~= sg.cur then b.TextColor3 = C.FAINT end
    end
  end
  return sg
end

-- 勾选框（左右对称）：14 × 14 的框（1 像素灰线；勾上了里面一块 8 × 8 白）+ 一行字（粗 12 灰，悬停白）；整行能点（o.h 高：手机 44）
--   o = { name, value, h, onToggle(新的值) }
function K.check(parent, str, pos, o)
  o = o or {}
  local h = o.h or 22
  local w = math.floor(14 + 8 + K.textW(str, S.tiny) + 6)
  local b = K.button(parent, UD2(0, w, 0, h), pos, o.name or "Check")
  b.AnchorPoint = o.anchor or V2(0, 0)
  local box = K.frame(b, UD2(0, 14, 0, 14), UD2(0, 0, 0.5, -7), C.PANEL, 0.35)
  box.Name = "Box"
  TH.corner(box, 2)
  local bs = TH.stroke(box)
  bs.Color, bs.Transparency = C.MUTE, 0
  local tk = K.frame(box, UD2(0, 8, 0, 8), UD2(0.5, 0, 0.5, 0), C.TEXT, 0, V2(0.5, 0.5))
  tk.Name = "On"
  local t = K.text(b, str, S.tiny, "bold", C.MUTE, UD2(1, -22, 1, 0), UD2(0, 22, 0, 0))
  t.Name = "Label"
  local ck = { f = b, on = false, w = w }
  function ck.set(on)
    ck.on = on == true
    tk.Visible = ck.on
    bs.Color = ck.on and C.TEXT or C.MUTE
  end
  b.MouseEnter:Connect(function() t.TextColor3 = C.TEXT end)
  b.MouseLeave:Connect(function() t.TextColor3 = C.MUTE end)
  b.Activated:Connect(function() if o.onToggle then o.onToggle(not ck.on) end end)
  ck.set(o.value)
  return ck
end

---------------------------------------------------------------- 拖动条（配弹：一种弹带几发；以后的弹药页用）

-- 轨道 4 高、填充 TEXT、滑块 10 × 16（悬停 / 拖着时琥珀描边）、每 tick 一道刻度；左右 26 × 26 的 − / +（透明底细线）；右边数目（等宽 17）；
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
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Size = UD2(0, 26, 0, 26)
    b.Position = UD2(0, x, 0, 0)
    b.Parent = box
    TH.corner(b)
    TH.stroke(b)
    b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.1 end)
    b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
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
  local num = K.text(box, "", S.sub, "mono", C.TEXT, UD2(0, 40, 1, 0), UD2(0, x0 + w + 6 + 26 + 6, 0, 0), RIGHT)
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

---------------------------------------------------------------- 对比行（右栏的性能：空挂 vs 现在；悬停时 现在 vs 换上）

-- 一行：左边名字（13 灰，中文粗一档）；右边三列——第一列（等宽 13 淡：平时「空挂」、悬停时「现在」）、→、第二列（等宽 15：平时「现在」白、
--   悬停时「换上」琥珀）、差（等宽 13）。平时差值灰（挂弹的代价，不是警告）；悬停预览时差 = 换上 − 现在，变好绿、变差红。
--   不画条（数都在 97%～100%，条长看不出区别；数字比条重要）；行底一道 1 像素细线。narrow（手机）：只写第二列和差
local Cmp = {}
Cmp.__index = Cmp
K.CMP_COLS = { base = -130, cur = -56 }   -- 第一列、第二列的右边（离行右边多远）：列名那一行照这个对齐
function K.compare(parent, y, w, label, x, narrow, rh)
  x = x or 12
  rh = rh or 26
  local row = K.frame(parent, UD2(0, w, 0, rh), UD2(0, x, 0, y), nil, 1)
  row.Name = "Cmp"
  local nm = K.text(row, label, S.small, "cond", C.MUTE, UD2(0, w - (narrow and 112 or 172), 1, -1), UD2(0, 0, 0, 0))
  nm.Name = "Name"
  local delta = K.text(row, "", S.small, "mono", C.MUTE, UD2(0, 46, 1, -1), UD2(1, 0, 0, 0), RIGHT, V2(1, 0))
  delta.Name = "Delta"
  local vb = K.text(row, "", S.body, "mono", C.TEXT, UD2(0, 66, 1, -1), UD2(1, narrow and -54 or K.CMP_COLS.cur, 0, 0), RIGHT, V2(1, 0))
  vb.Name = "Val"
  local va = K.text(row, "", S.small, "mono", C.FAINT, UD2(0, 56, 1, -1), UD2(1, K.CMP_COLS.base, 0, 0), RIGHT, V2(1, 0))
  va.Name = "Base"
  local arrow = K.text(row, "→", S.small, "mono", C.FAINT, UD2(0, 12, 1, -1), UD2(1, K.CMP_COLS.base + 6, 0, 0))
  arrow.Name = "Arrow"
  arrow.Visible, va.Visible = not narrow, not narrow
  local sep = K.frame(row, UD2(1, 0, 0, 1), UD2(0, 0, 1, -1), C.LINE, 0.92)
  sep.Name = "Sep"
  return setmetatable({ f = row, nm = nm, delta = delta, vb = vb, va = va, arrow = arrow, narrow = narrow,
    key = tostring(row) .. tostring(math.random()) }, Cmp)
end
-- base 空挂、cur 现在、pv 悬停预览（nil 不预览）；o = { fmt(数) → 字, dfmt(差) → 字, better = 1 越大越好 / −1 越小越好, eps, roll = true 数字滚动（点了装上、改内油） }
--   没变（空挂 = 现在、没在预览）：只写一个数（「极速 284」，不写「284 → 284」）
function Cmp:set(base, cur, pv, o)
  local fmt = o.fmt
  local dfmt = o.dfmt or function(v) return K.signed(v) end
  local eps = o.eps or 1e-6
  local better = o.better or 1
  local prev = pv ~= nil
  local from = prev and cur or base
  local to = prev and pv or cur
  local d = to - from
  local flat = (not prev) and math.abs(d) < eps
  self.va.Visible = not self.narrow and not flat
  self.arrow.Visible = not self.narrow and not flat
  self.va.Text = fmt(from)
  if prev or not o.roll then
    K.stop(self.key .. "v")
    self.vb.Text = fmt(to)
  else
    K.roll(self.vb, self.key .. "v", self.shown, to, fmt)
  end
  self.shown = to
  self.vb.TextColor3 = prev and C.WARN or C.TEXT
  self.delta.Text = (math.abs(d) < eps) and "" or dfmt(d)
  if prev and math.abs(d) >= eps and better ~= 0 then
    self.delta.TextColor3 = ((d * better) > 0) and C.GOOD or C.BAD
  else
    self.delta.TextColor3 = C.MUTE
  end
end
-- 只写一个数（没有对比的行）
function Cmp:plain(txt, col)
  self.va.Text, self.delta.Text = "", ""
  self.va.Visible, self.arrow.Visible = false, false
  K.stop(self.key .. "v")
  self.vb.Text = txt
  self.vb.TextColor3 = col or C.TEXT
end

---------------------------------------------------------------- 引线标签（3D 挂点：一个点、只走横竖的引线、一个 14 高的键位框「3」；选中的后面跟名字）

local Tag = {}
Tag.__index = Tag
-- clickable：手机上 false（标签太小，点底部的挂点卡）
function K.tag(layer, name, clickable)
  local dot = K.frame(layer, UD2(0, 6, 0, 6), nil, C.TEXT, 0, V2(0.5, 0.5))
  dot.Name = "Dot"
  round(dot)
  local ring = Instance.new("UIStroke")
  ring.Color, ring.Thickness, ring.Transparency = C.FAINT, 1, 1
  ring.Parent = dot
  local b = Instance.new("TextButton")
  b.Name = name or "Tag"
  b.AutoButtonColor = false
  b.Text = ""
  b.BackgroundColor3 = C.PANEL
  b.BackgroundTransparency = 0.35
  b.BorderSizePixel = 0
  b.Size = UD2(0, 20, 0, 14)
  b.Active = clickable ~= false
  b.Interactable = clickable ~= false
  b.Parent = layer
  TH.corner(b, 2)
  local st = TH.stroke(b)
  st.Transparency = A.lineHi
  local num = K.text(b, "", S.tiny, "mono", C.MUTE, UD2(0, 24, 1, 0), UD2(0, 5, 0, 0))
  num.Name = "Num"
  local nm = K.text(b, "", S.tiny, "bold", C.WARN, UD2(0, 90, 1, 0), UD2(0, 20, 0, 0))
  nm.Name = "Name"
  nm.Visible = false
  return setmetatable({ dot = dot, ring = ring, b = b, st = st, num = num, nm = nm, segs = {}, layer = layer, txt = nil, nameT = nil, w = 20 }, Tag)
end
function Tag:show(on)
  self.dot.Visible, self.b.Visible = on, on
  if not on then for _, f in ipairs(self.segs) do f.Visible = false end end
end
-- 一条只走横竖的折线（pts：{ { x, y }, … }，像素坐标取整）；dashed：机身另一边的（虚线：3 实 3 空）
function Tag:path(pts, col, tr, dashed)
  local k = 0
  local function seg(x, y, w, h)
    k += 1
    local f = self.segs[k]
    if not f then
      f = K.frame(self.layer, nil, nil, C.MUTE, 0)
      f.Name = "Leader"
      self.segs[k] = f
    end
    f.Visible = true
    f.Position = UD2(0, x, 0, y)
    f.Size = UD2(0, w, 0, h)
    f.BackgroundColor3 = col
    f.BackgroundTransparency = tr
  end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local x0, y0 = math.floor(math.min(a[1], b[1]) + 0.5), math.floor(math.min(a[2], b[2]) + 0.5)
    local x1, y1 = math.floor(math.max(a[1], b[1]) + 0.5), math.floor(math.max(a[2], b[2]) + 0.5)
    local horiz = (y1 - y0) < (x1 - x0)
    local len = horiz and (x1 - x0) or (y1 - y0)
    if len >= 1 then
      if dashed then
        local t = 0
        while t < len do
          local l = math.min(3, len - t)
          if horiz then seg(x0 + t, y0, l, 1) else seg(x0, y0 + t, 1, l) end
          t += 6
        end
      elseif horiz then
        seg(x0, y0, len + 1, 1)
      else
        seg(x0, y0, 1, len + 1)
      end
    end
  end
  for j = k + 1, #self.segs do self.segs[j].Visible = false end
end
-- 标签多宽（编号 + 选中时的名字）
function K.tagW(num, name)
  local w = math.floor(K.textW(num, S.tiny, true) + 10)
  if name and name ~= "" then w += math.floor(K.textW(name, S.tiny) + 6) end
  return math.max(16, w)
end
-- 摆：o = { dx, dy 挂点在画面上的位置；lx 标签中点、ly 标签上沿；jy 引线横着走的那一层；num 编号；name 名字（选中时才给）；
--   sel 选中（琥珀，永远不淡）、hov 鼠标挂着（白）、empty 空挂点（淡、空心点）、far 在机身另一边（虚线引线）、alpha 整体（镜头动着时淡掉）}
--   引线：从点竖着落到 jy、横着走到标签中点、再竖着落进标签（不出斜线）
function Tag:place(o)
  local a = math.clamp(o.alpha or 1, 0, 1)
  local tr = 1 - a
  local col = o.sel and C.WARN or (o.empty and C.FAINT or (o.hov and C.TEXT or C.MUTE))
  local dotC = o.sel and C.WARN or (o.empty and C.FAINT or C.TEXT)
  self.dot.Position = UD2(0, math.floor(o.dx + 0.5), 0, math.floor(o.dy + 0.5))
  self.dot.Size = o.sel and UD2(0, 7, 0, 7) or UD2(0, 6, 0, 6)
  self.dot.BackgroundColor3 = dotC
  self.dot.BackgroundTransparency = o.empty and 1 or tr
  self.ring.Color = dotC
  self.ring.Transparency = o.empty and (0.1 + 0.9 * tr) or 1
  local lcol = o.sel and C.WARN or (o.far and C.FAINT or C.MUTE)
  local ltr = o.sel and (0.15 + 0.85 * tr) or ((o.far and 0.2 or 0.45) + (o.far and 0.8 or 0.55) * tr)
  self:path({ { o.dx, o.dy + 4 }, { o.dx, o.jy }, { o.lx, o.jy }, { o.lx, o.ly } }, lcol, ltr, o.far)
  if self.txt ~= o.num or self.nameT ~= (o.name or "") then
    self.txt, self.nameT = o.num, o.name or ""
    self.num.Text = o.num
    self.nm.Text = self.nameT
    self.nm.Visible = self.nameT ~= ""
    local nw = math.floor(K.textW(o.num, S.tiny, true))
    self.num.Size = UD2(0, nw + 2, 1, 0)
    self.nm.Position = UD2(0, 5 + nw + 6, 0, 0)
    self.w = K.tagW(o.num, o.name)
  end
  self.b.Size = UD2(0, self.w, 0, 14)
  self.b.Position = UD2(0, math.floor(o.lx - self.w / 2 + 0.5), 0, math.floor(o.ly + 0.5))
  self.b.BackgroundTransparency = 0.35 + 0.65 * tr
  self.num.TextColor3 = col
  self.num.TextTransparency = tr
  self.nm.TextColor3 = C.WARN
  self.nm.TextTransparency = tr
  self.st.Color = o.sel and C.WARN or (o.hov and C.TEXT or C.LINE)
  self.st.Transparency = o.sel and tr or ((o.hov and 0.2 or A.lineHi) + (1 - (o.hov and 0.2 or A.lineHi)) * tr)
end
-- 只画一个点（全景时机身另一边的挂点：4 像素淡点，不写编号）
function Tag:dotOnly(dx, dy, alpha)
  self.b.Visible = false
  for _, f in ipairs(self.segs) do f.Visible = false end
  self.dot.Visible = true
  self.dot.Position = UD2(0, math.floor(dx + 0.5), 0, math.floor(dy + 0.5))
  self.dot.Size = UD2(0, 4, 0, 4)
  self.dot.BackgroundColor3 = C.FAINT
  self.dot.BackgroundTransparency = 1 - math.clamp(alpha or 1, 0, 1)
  self.ring.Transparency = 1
end

---------------------------------------------------------------- 武器剪影（这一轮先用单色剪影顶上，下一轮换 Blender 渲的图：tools/models/ammopics_blender.py 那条管线）
-- 照弹药栏（WtTank.lua）剪影的笔法：横放、弹头朝右、单色；尺寸按真弹的外形（AirDefs.W[...].shape：弹长 L、弹径 d，格），
--   弹头样式、尾翼 / 弹翼 / 鸭翼的位置和大小、炸弹尾翼套件、火箭巢、副油箱按 WeaponModels 的描述（同一枚弹在 3D 里、剪影里一个样子）。
--   不用圆角拼（圆滚滚的胶囊就是卡通）：雷达罩、炸弹头、副油箱两头、火箭巢整流罩都是 2～4 段递减的矩形（d → 0.78d → 0.5d……）拼出锥形 / 卵形。
--   一个挂点挂几枚只画一枚（几枚写在卡片右上角）；平时灰（MUTE）、选中和悬停的那张白（调用的地方给 col）。
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
K.libs = libs
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
  for _, F0 in ipairs({ ds.tail, ds.mid, ds.can }) do
    if F0 then s = math.max(s, F0.strake and F0.s * 0.4 or F0.s) end
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
-- 在 box（w × h 像素）里画 wid 的剪影：o = { px 比例尺, col 颜色（默认 MUTE）, tr 透明度（默认 0.1）, dx, dy }
function K.weaponArt(box, wid, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local _, ad = libs()
  local W0 = ad and ad.W[wid]
  if not W0 then return nil end
  local px = o.px or K.artScale({ wid }, w, h)
  local col = o.col or C.MUTE
  local tr0 = o.tr or 0.1
  local cut = C.BG
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local sh = W0.shape or { L = 5, d = 0.6 }
  local L, d = sh.L, sh.d
  local ds = descOf(wid, W0)
  local x0 = (w - L * px) / 2 + (o.dx or 0)
  local yc = h / 2 + (o.dy or 0)
  local function X(x) return x0 + x * px end
  local function Y(y) return yc - y * px end
  local function tr(t) return t or tr0 end
  -- 一块：x 从 a 到 b（格，从弹尾量起）、中心高 y、高 hh
  local function blk(a, b, y, hh, t, c2)
    local wp = math.max(1, (b - a) * px)
    local hp = math.max(1, hh * px)
    return K.frame(art, UD2(0, wp, 0, hp), UD2(0, X((a + b) / 2), 0, Y(y)), c2 or col, tr(t), V2(0.5, 0.5))
  end
  -- 一串递减的段（从 a 往 b 收细：steps = { { 占这一串的比例, 粗细（× d）}, … }）：锥形、卵形的头 / 尾
  local function taper(a, b, steps, t)
    local x = a
    for _, sp in ipairs(steps) do
      local x2 = x + (b - a) * sp[1]
      blk(math.min(x, x2), math.max(x, x2), 0, d * sp[2], t)
      x = x2
    end
  end
  local function ln(xa, ya, xb, yb, th, t)
    local f = K.frame(art, nil, nil, col, tr(t))
    K.line(f, X(xa), Y(ya), X(xb), Y(yb), math.max(1, th or 1))
    return f
  end
  -- 后掠的三角翼：后缘竖着在 xa、翼根贴着弹体表面 y0（从 xa 到前面的 xb）、翼尖在 (xa, y0 + 方向 × hh)
  local function fin(xa, xb, y0, hh, dir, t)
    local ch = math.abs(xb - xa)
    blk(xa, xa + math.max(ch * 0.2, 1 / px), y0 + dir * hh / 2, hh, t)
    blk(xa, xa + ch * 0.5, y0 + dir * hh / 4, hh / 2, t)
    ln(xb, y0, xa, y0 + dir * hh, math.max(1, math.min(ch, hh) * px * 0.3), t)
  end
  local function band(at, frac)   -- 弹体上的环带：暗一道
    local x = L - at * L
    local bw = math.max(frac * L, 1 / px)
    blk(x - bw / 2, x + bw / 2, 0, d * 0.98, 0.45, cut)
  end
  if ds.tank then   -- 副油箱：中段直筒，两头一段段收尖；两道焊缝；有的尾部小安定面
    blk(L * 0.24, L * 0.76, 0, d)
    taper(L * 0.76, L, { { 0.4, 0.8 }, { 0.35, 0.56 }, { 0.25, 0.28 } })
    taper(L * 0.24, 0, { { 0.42, 0.82 }, { 0.33, 0.58 }, { 0.25, 0.32 } })
    band(0.47, 0.006)
    band(0.27, 0.006)
    if ds.fins then
      fin(L * 0.04, L * 0.17, -d * 0.22, d * 0.34, -1, 0.2)
      fin(L * 0.04, L * 0.17, d * 0.22, d * 0.24, 1, 0.3)
    end
    return art
  end
  if ds.pod then   -- 火箭巢：粗圆筒、前后整流罩（两段收细）、前端发射管口那一面、一道环带、两排管子的影子
    blk(L * 0.12, L * 0.86, 0, d)
    taper(L * 0.86, L, { { 0.62, 0.86 }, { 0.38, 0.66 } })
    taper(L * 0.12, 0, { { 0.55, 0.86 }, { 0.45, 0.62 } })
    blk(L * 0.985, L, 0, d * 0.62, 0.3, cut)
    band(0.3, 0.035)
    for _, yy in ipairs({ -0.22, 0.22 }) do blk(L * 0.16, L * 0.84, yy * d, math.max(1 / px, d * 0.05), 0.72, cut) end
    return art
  end
  if W0.kind == "bomb" then
    local nose = ds.nose or "bomb"
    if nose == "laser" then   -- 激光制导炸弹：战斗部、细脖子上的导引头（两段）、四片鸭翼
      blk(L * 0.2, L * 0.7, 0, d)
      taper(L * 0.7, L * 0.82, { { 0.5, 0.9 }, { 0.5, 0.72 } })
      blk(L * 0.82, L * 0.92, 0, d * 0.5)
      taper(L * 0.92, L, { { 0.6, 0.56 }, { 0.4, 0.38 } })
      for _, dir in ipairs({ 1, -1 }) do fin(L * 0.83, L * 0.9, dir * d * 0.25, d * 0.34, dir, 0.18) end
    else   -- 普通炸弹 / 卫星制导：卵形头（一段段收细；制导的前面一个引信）
      blk(L * 0.22, L * 0.7, 0, d)
      taper(L * 0.7, L * 0.985, { { 0.34, 0.92 }, { 0.26, 0.78 }, { 0.22, 0.56 }, { 0.18, 0.32 } })
      if nose == "jdam" then blk(L * 0.97, L, 0, d * 0.2) end
    end
    for _, b in ipairs(ds.bands or {}) do band(b[1], b[2]) end
    local kit = ds.kit or "mk"
    if kit == "mk" then   -- 低阻尾锥 + 方尾翼
      blk(L * 0.1, L * 0.23, 0, d * 0.8)
      blk(L * 0.02, L * 0.11, 0, d * 0.52)
      for _, dir in ipairs({ 1, -1 }) do blk(L * 0.01, L * 0.18, dir * d * 0.42, d * 0.36, 0.25) end
    elseif kit == "jdam" or kit == "sdb" then   -- 卫星制导尾翼套件：尾段、四片长尾翼、弹体边条
      blk(L * 0.01, L * 0.25, 0, d * 0.86)
      blk(L * -0.005, L * 0.015, 0, d * 0.6)
      local fh = d * ((kit == "sdb") and 0.42 or 0.62) * 0.707
      for _, dir in ipairs({ 1, -1 }) do
        fin(L * 0.01, L * 0.17, dir * d * 0.43, fh, dir, 0.15)
        if kit == "jdam" then blk(L * 0.37, L * 0.67, dir * d * 0.52, math.max(d * 0.08, 1 / px), 0.3) end
      end
    elseif kit == "paveway" then   -- 激光制导炸弹的大尾翼
      blk(L * 0.0, L * 0.2, 0, d * 0.7)
      for _, dir in ipairs({ 1, -1 }) do blk(L * 0.0, L * 0.2, dir * d * 0.6, d * 0.58, 0.28) end
    end
    if ds.wing then   -- 折叠弹翼（雷石-6、小直径炸弹）：挂着时折在弹体上面
      local Wd = ds.wing
      local xc = L - Wd.at * L - Wd.span * 0.2
      blk(xc - Wd.span * 0.25, xc + Wd.span * 0.25, d * 0.58, math.max(0.1, 1 / px), 0.12)
    end
    return art
  end
  -- 导弹（空空 / 空地 / 地空）
  local nose = ds.nose or "radar"
  local noseL = (nose == "radar" or nose == "arm") and L * 0.16 or L * 0.09
  blk(L * 0.012, L - noseL, 0, d)
  blk(0, L * 0.02, 0, d * 0.66)   -- 尾喷口
  if nose == "radar" or nose == "arm" then   -- 雷达罩：细长的尖头（四段收细）
    taper(L - noseL, L, { { 0.34, 0.84 }, { 0.3, 0.62 }, { 0.22, 0.4 }, { 0.14, 0.18 } })
  elseif nose == "laser" then   -- 激光：细一点的导引头
    taper(L - noseL, L, { { 0.55, 0.84 }, { 0.45, 0.6 } })
  else   -- 红外 / 电视：短的玻璃罩（三段收圆）
    taper(L - noseL, L, { { 0.5, 0.82 }, { 0.32, 0.58 }, { 0.18, 0.3 } })
  end
  for _, b in ipairs(ds.bands or {}) do band(b[1], b[2]) end
  local function fins(Fd)
    if not Fd then return end
    local xc = L - Fd.at * L
    local ch = Fd.c * L
    local sp = Fd.s * d * 0.707   -- X 形的四片：侧面看上下各一片，展长 × cos 45°
    for _, dir in ipairs({ 1, -1 }) do
      if Fd.grid then   -- 栅格翼（R-77）：一个细框
        local f = blk(xc - ch / 2, xc + ch / 2, dir * (d / 2 + sp / 2), sp, 1)
        local s = Instance.new("UIStroke")
        s.Color, s.Thickness, s.Transparency = col, 1, tr(0.15)
        s.Parent = f
      elseif Fd.strake then   -- 长边条：贴着弹体的细长翼
        blk(xc - ch / 2, xc + ch / 2, dir * (d / 2 + sp * 0.2), sp * 0.4, 0.22)
      else
        fin(xc - ch / 2, xc + ch / 2, dir * d / 2, sp, dir, 0.15)
      end
    end
  end
  fins(ds.tail)
  fins(ds.mid)
  fins(ds.can)
  if ds.wing then   -- 巡航弹的折叠弹翼（KD-88、鹰击-83K）：挂着时折在弹体上面
    local Wd = ds.wing
    local xc = L - Wd.at * L - Wd.span * 0.2
    blk(xc - Wd.span * 0.25, xc + Wd.span * 0.25, d * 0.58, math.max(0.1, 1 / px), 0.12)
  end
  return art
end
-- 机炮（航炮固定卡）：机匣、一根或几根炮管、炮口、供弹槽；几管按型号
local GUN_BARRELS = { m61 = 3, gau8 = 3, gau22 = 3, m134 = 3, yakb = 3, m197 = 3, gsh23 = 2, gsh302 = 2 }
function K.gunArt(box, gid, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local col = o.col or C.MUTE
  local tr0 = o.tr or 0.1
  local n = GUN_BARRELS[gid or ""] or 1
  local cy = h / 2
  local x0, x1 = w * 0.1, w * 0.92
  K.frame(art, UD2(0, w * 0.32, 0, h * 0.34), UD2(0, x0, 0, cy - h * 0.17), col, tr0).Name = "Receiver"
  local gap = math.max(2, h * 0.09)
  for i = 1, n do
    local y = cy + (i - (n + 1) / 2) * gap
    K.frame(art, UD2(0, x1 - (x0 + w * 0.3), 0, math.max(1, h * 0.06)), UD2(0, x0 + w * 0.3, 0, y - math.max(1, h * 0.06) / 2), col, tr0).Name = "Barrel"
  end
  K.frame(art, UD2(0, w * 0.06, 0, math.max(2, h * 0.08 + (n - 1) * gap)), UD2(0, x1 - w * 0.06, 0, cy - math.max(2, h * 0.08 + (n - 1) * gap) / 2), col, tr0).Name = "Muzzle"
  local chute = K.frame(art, nil, nil, col, 0.4)
  K.line(chute, x0 + w * 0.06, cy + h * 0.17, x0 - w * 0.02, cy + h * 0.4, math.max(1, h * 0.08))
  return art
end
-- 干扰弹（固定卡）：一排四发药筒（方头）
function K.flareArt(box, w, h, o)
  o = o or {}
  for _, c in ipairs(box:GetChildren()) do if c.Name == "Art" then c:Destroy() end end
  local art = K.frame(box, UD2(1, 0, 1, 0), nil, nil, 1)
  art.Name = "Art"
  local col = o.col or C.MUTE
  local tr0 = o.tr or 0.1
  local cw, ch = math.max(4, w * 0.09), math.max(8, h * 0.56)
  for i = 0, 3 do
    local x = w * 0.5 + (i - 1.5) * (cw + math.max(2, w * 0.035)) - cw / 2
    K.frame(art, UD2(0, cw, 0, ch), UD2(0, x, 0, h / 2 - ch / 2 + 2), col, tr0).Name = "Case"
    K.frame(art, UD2(0, cw * 0.7, 0, math.max(2, cw * 0.4)), UD2(0, x + cw * 0.15, 0, h / 2 - ch / 2 + 2 - math.max(2, cw * 0.4)), col, tr0).Name = "Cap"
    K.frame(art, UD2(0, cw, 0, 1), UD2(0, x, 0, h / 2 + ch / 2 - 3), C.BG, 0.4).Name = "Rim"
  end
  return art
end

---------------------------------------------------------------- 武器的 3D 小视口（悬停资料卡：这枚弹真的 3D 模型——同 AirModels 挂在挂点上的那套零件，慢慢滚着转）

local View = {}
View.__index = View
-- 灯光照弹药栏的渲染图：环境光 90 灰、主光暖白、从左上前方照过来
function K.wpnView(parent, size, pos, name)
  local vp = Instance.new("ViewportFrame")
  vp.Name = name or "WsWpnView"
  vp.BackgroundTransparency = 1
  vp.BorderSizePixel = 0
  vp.Size, vp.Position = size, pos
  vp.Ambient = Color3.fromRGB(90, 90, 90)
  vp.LightColor = Color3.fromRGB(255, 250, 240)
  vp.LightDirection = Vector3.new(-1, -1, -0.5)
  vp.Parent = parent
  local cam = Instance.new("Camera")
  cam.FieldOfView = 18
  cam.Parent = vp
  vp.CurrentCamera = cam
  return setmetatable({ vp = vp, cam = cam, parts = nil, offs = nil, wid = nil, a = 0, L = 1 }, View)
end
-- 换一枚弹：拼零件（WeaponModels，和挂在飞机上的一样）、镜头按弹长退到正好放下（从侧前方偏上 6° 看，弹头朝右）
function View:set(wid)
  if wid == self.wid then return self.parts ~= nil end
  self.wid = wid
  if self.model then self.model:Destroy() end
  self.model, self.parts, self.offs = nil, nil, nil
  local wm, ad = libs()
  local w = wid and ad and ad.W[wid]
  if not (wm and w) then return false end
  local m = Instance.new("Model")
  m.Name = "Weapon"
  local ok, r = pcall(wm.make, m, w, CFrame.new(), false)
  if not ok or not r then
    m:Destroy()
    return false
  end
  m.Parent = self.vp
  self.model, self.parts, self.offs = m, r.parts, r.offs
  local sh = w.shape or { L = 5, d = 0.6 }
  self.L = sh.L
  local _, H = K.artExtent(wid)
  local vw = self.vp.Size.X.Offset > 0 and self.vp.Size.X.Offset or 276
  local vh = self.vp.Size.Y.Offset > 0 and self.vp.Size.Y.Offset or 72
  local tv = math.tan(math.rad(self.cam.FieldOfView) / 2)
  local th = tv * vw / vh
  local dist = math.max((sh.L * 0.56) / th, (H * 0.78) / tv) + sh.d
  -- 弹体沿 −Z（弹头朝前）：镜头在 +X 那边（画面往右 = 弹头），往弹头那边偏 20°、往上抬 6°
  local yaw, pitch = math.rad(20), math.rad(6)
  local eye = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), -math.sin(yaw) * math.cos(pitch)) * dist
  self.cam.CFrame = CFrame.lookAt(eye, Vector3.new(0, 0, 0))
  self.a = 0
  self:spin(0)
  return true
end
-- 绕弹轴慢慢滚（每秒 8°）：尾翼、弹翼转过来能看出是立体的；视口里只有十几个零件，每帧摆一下不费事
function View:spin(dt)
  if not self.parts then return end
  self.a = (self.a + math.rad(8) * (dt or 0)) % (2 * math.pi)
  local rot = CFrame.Angles(0, 0, self.a)
  for i, p in ipairs(self.parts) do
    if p.Parent then p.CFrame = rot * self.offs[i] end
  end
end
function View:clear()
  if self.model then self.model:Destroy() end
  self.model, self.parts, self.offs, self.wid = nil, nil, nil, nil
end

return K
