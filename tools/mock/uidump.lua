-- 把玩家屏幕上显示着的界面元素按 Roblox 的排版算出方框（1280×720，UDim2 + AnchorPoint + UIListLayout + UIScale 的近似），写成 JSON
--   tools/mock/hud_render.py 画成图。hudshot.lua、uishots.lua 共用：local dump = dofile(MOCK_DIR .. "/uidump.lua")；dump(T, me, out, quiet)
return function(T, me, out, quiet)
local R, V3, Enum = T.R, T.V3, T.Enum
local print = quiet and function() end or print
local VW, VH, INSET = 1280, 720, 36
local items, perGui = {}, {}
local function c3(c) return c and { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } or nil end
local function isGui(o) return R.base.IsA(o, "GuiObject") end
local function cut(a, x, y, w, h, r)   -- 裁剪框（ClipsDescendants、CanvasGroup）：和上一层的取交集
  local b = { x, y, x + w, y + h, r or 0 }
  if not a then return b end
  return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]), (r and r > 0) and r or a[5] }
end
-- 排版（同 Roblox）：每个元素在父元素「没缩放」的坐标里按 Size / Position / AnchorPoint 排，再乘上祖先的 UIScale；
--   元素自己的 UIScale 以它的锚点为中心放大它自己和子孙（ScreenGui 底下的 UIScale 当成每个顶层元素自己的）
--   walk(o, ax, ay, uw, uh, s)：o 的框左上角在屏幕的 (ax, ay)，没缩放的大小 uw × uh，o 里面的坐标乘 s 才是屏幕像素
local function walk(o, ax, ay, uw, uh, s, guiName, depth, clip, ga, rootU)
  ga = ga or 1
  -- 子元素：有 UIListLayout 的按顺序排
  local layout = o:FindFirstChildOfClass("UIListLayout")
  local kids = {}
  for _, c in ipairs(o._kids) do if isGui(c) and c._p.Visible ~= false then kids[#kids + 1] = c end end
  if layout and #kids > 0 then
    table.sort(kids, function(a, b)
      local la, lb = a.LayoutOrder or 0, b.LayoutOrder or 0
      if la ~= lb then return la < lb end
      return false
    end)
  end
  local cx, cy = 0, 0
  local horiz = layout and layout.FillDirection == Enum.FillDirection.Horizontal
  local pad = layout and layout.Padding or nil
  for _, c in ipairs(kids) do
    local sz, ps, ap = c.Size, c.Position, c.AnchorPoint
    local cuw = sz.XS * uw + sz.XO
    local cuh = sz.YS * uh + sz.YO
    local arc = c:FindFirstChildOfClass("UIAspectRatioConstraint")   -- 宽高比约束（默认 FitWithinMaxSize）：在原来的框里按比例缩
    if arc and (arc.AspectRatio or 0) > 0 then
      local ar = arc.AspectRatio
      local w2 = math.min(cuw, cuh * ar)
      cuw, cuh = w2, w2 / ar
    end
    local own = c:FindFirstChildOfClass("UIScale")
    local u = (own and own.Scale or 1) * (rootU or 1)
    local w, h = cuw * s * u, cuh * s * u
    local x, y
    if layout then
      x, y = ax + cx * s, ay + cy * s
      local padPx = pad and (pad.Scale * (horiz and uw or uh) + pad.Offset) or 0
      if horiz then cx = cx + cuw + padPx else cy = cy + cuh + padPx end
    else
      x = ax + (ps.XS * uw + ps.XO) * s - ap.X * w
      y = ay + (ps.YS * uh + ps.YO) * s - ap.Y * h
    end
    local sc = s * u
    local p = c._p
    local stroke = c:FindFirstChildOfClass("UIStroke")
    local corner = c:FindFirstChildOfClass("UICorner")
    local rec = { cls = c._cls, name = c._p.Name, gui = guiName, depth = depth, z = c.ZIndex or 1,
      x = x, y = y, w = w, h = h, rot = c.Rotation or 0,
      bg = c3(c.BackgroundColor3), bgT = c.BackgroundTransparency, }
    if corner then rec.corner = corner.CornerRadius.Scale * math.min(w, h) + corner.CornerRadius.Offset * sc end
    if stroke and stroke._p.Enabled ~= false then
      rec.st = c3(stroke.Color) rec.stT = stroke.Transparency rec.stW = stroke.Thickness * sc
      local sg = stroke:FindFirstChildOfClass("UIGradient")
      if sg then
        pcall(function()
          local kp = {}
          for _, k in ipairs(sg.Transparency.Keypoints) do kp[#kp + 1] = { k.Time, k.Value } end
          rec.stGrad = { rot = sg.Rotation or 0, kp = kp }
        end)
      end
    end
    if c._cls == "TextLabel" or c._cls == "TextButton" or c._cls == "TextBox" then
      rec.text, rec.tc, rec.tT, rec.ts = c.Text, c3(c.TextColor3), c.TextTransparency, (c.TextSize or 14) * sc
      rec.scaled = c.TextScaled
      rec.xa = tostring(c.TextXAlignment)
    end
    if c._cls == "ImageLabel" or c._cls == "ImageButton" then
      rec.img = c.Image rec.ic = c3(c.ImageColor3) rec.iT = c.ImageTransparency
      rec.icon = c:GetAttribute("Icon")   -- HudArt 装上的图标（HudIcons 里的名字）
      rec.pic = c:GetAttribute("PicName")   -- 写实车图（VehPics 里的名字；模拟器解不出 EditableImage，渲染时照游戏的解法还原）
      rec.fit = (c.ScaleType == Enum.ScaleType.Fit) or nil
    end
    rec.clip, rec.ga = clip, ga
    if c._cls == "ViewportFrame" then rec.vp = c._p.Name end
    local grad = c:FindFirstChildOfClass("UIGradient")
    if grad then
      pcall(function()
        local kp = {}
        for _, k in ipairs(grad.Transparency.Keypoints) do kp[#kp + 1] = { k.Time, k.Value } end
        local ck = {}   -- 颜色渐变（乘在底色上）：没开（Enabled = false）就不算
        if grad.Enabled ~= false then
          for _, k in ipairs(grad.Color.Keypoints) do ck[#ck + 1] = { k.Time, c3(k.Value) } end
        end
        rec.grad = { rot = grad.Rotation or 0, kp = kp, ck = (#ck > 0) and ck or nil }
      end)
    end
    items[#items + 1] = rec
    perGui[guiName] = (perGui[guiName] or 0) + 1
    local kidClip, kidGa = clip, ga
    if c._cls == "CanvasGroup" then
      kidGa = ga * (1 - (c.GroupTransparency or 0))
      kidClip = cut(clip, x, y, w, h, rec.corner)
    elseif c.ClipsDescendants then
      kidClip = cut(clip, x, y, w, h, nil)
    end
    if c._cls ~= "ViewportFrame" then walk(c, x, y, cuw, cuh, sc, guiName, depth + 1, kidClip, kidGa) end
  end
end
local pg = me:FindFirstChildOfClass("PlayerGui")
local guis = {}
for _, g in ipairs(pg._kids) do
  if g._cls == "ScreenGui" and g._p.Enabled ~= false then guis[#guis + 1] = g end
end
table.sort(guis, function(a, b) return (a.DisplayOrder or 0) < (b.DisplayOrder or 0) end)
for gi, g in ipairs(guis) do
  local top = g.IgnoreGuiInset and 0 or INSET
  local n0 = #items
  local gu = g:FindFirstChildOfClass("UIScale")
  walk(g, 0, top, VW, VH - top, 1, g._p.Name .. "#" .. gi, 0, nil, nil, gu and gu.Scale or nil)
  for i = n0 + 1, #items do items[i].order = (g.DisplayOrder or 0) * 1000 + gi end
end
print(string.format("显示着的界面元素 %d 个；按 ScreenGui：", #items))
local rows = {}
for k, v in pairs(perGui) do rows[#rows + 1] = { k = k, v = v } end
table.sort(rows, function(a, b) return a.v > b.v end)
for _, r in ipairs(rows) do print(string.format("  %4d  %s", r.v, r.k)) end
-- 每个 ScreenGui 下面显示着的第一层（看是哪些面板）
print("各 ScreenGui 显示着的第一层：")
for _, g in ipairs(guis) do
  local names = {}
  for _, c in ipairs(g._kids) do
    if isGui(c) and c._p.Visible ~= false then names[#names + 1] = c._p.Name end
  end
  print(string.format("  %s（DisplayOrder %s）：%s", g._p.Name, tostring(g.DisplayOrder), table.concat(names, "、")))
end
-- 屏幕上有字的（找旧界面的提示、按键说明）
print("有字的元素：")
for _, it in ipairs(items) do
  if it.text and it.text ~= "" and (it.tT or 0) < 0.95 and it.x < VW and it.y < VH and it.x + it.w > 0 and it.y + it.h > 0 then
    print(string.format("  [%s] %s (%.0f,%.0f %.0fx%.0f) %q", it.gui, it.name, it.x, it.y, it.w, it.h, it.text:sub(1, 60)))
  end
end
-- 机头的全息标记（AirHud：机头前方 3D 的一块面，不在 ScreenGui 里）：四个角投到屏幕上，hud_render.py 按透视把图贴上去
do
  local camO = R.services.Workspace.CurrentCamera
  local hp = camO and camO:FindFirstChild("NoseHolo")
  local sg = hp and hp:FindFirstChild("NoseHoloGui")
  local im = sg and sg:FindFirstChild("NoseHoloArt")
  if hp and sg and sg.Enabled and im then
    local cf, sz = hp.CFrame, hp.Size
    local q = {}
    for _, c in ipairs({ { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }) do   -- 背面（朝镜头）看过去：左上、右上、右下、左下
      local sp = camO:WorldToViewportPoint(cf * V3(c[1] * sz.X / 2, c[2] * sz.Y / 2, sz.Z / 2))
      q[#q + 1] = { sp.X, sp.Y }
    end
    table.insert(items, 1, { quad = q, icon = im:GetAttribute("Icon"), ic = c3(im.ImageColor3), iT = im.ImageTransparency, order = -100,
      x = q[1][1], y = q[1][2], w = 1, h = 1, gui = "NoseHolo", name = "NoseHolo" })
    print(string.format("机头全息标记：四个角 (%.0f,%.0f) (%.0f,%.0f) (%.0f,%.0f) (%.0f,%.0f)", q[1][1], q[1][2], q[2][1], q[2][2], q[3][1], q[3][2], q[4][1], q[4][2]))
  else
    print("机头全息标记：没显示")
  end
end
if out then
  local function enc(v)
    local t = type(v)
    if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "0" or string.format("%.2f", v) end
    if t == "string" then return '"' .. v:gsub('[%c"\\]', function(ch) return string.format("\\u%04x", ch:byte()) end) .. '"' end
    if t == "boolean" then return tostring(v) end
    if t == "table" then
      if #v > 0 or next(v) == nil then
        local o = {}
        for i, x in ipairs(v) do o[i] = enc(x) end
        return "[" .. table.concat(o, ",") .. "]"
      end
      local o = {}
      for k, x in pairs(v) do o[#o + 1] = enc(tostring(k)) .. ":" .. enc(x) end
      return "{" .. table.concat(o, ",") .. "}"
    end
    return "null"
  end
  local f = assert(io.open(out, "w"))
  f:write(enc(items))
  f:close()
  print("写到 " .. out)
end
return items
end
