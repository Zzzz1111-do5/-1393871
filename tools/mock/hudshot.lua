-- 开坦克时屏幕上画了什么（模拟器）：python3 tools/mock/run.py tools/mock/hudshot.lua out=<文件.json> [kind=tank|ifv|ship|inf]
--   用户：开坦克要是 MWT 那套驾驶界面（截图），不要叠着旧界面。坐进一辆车、前方放一辆敌车开一会，
--   把所有显示着的界面元素按 Roblox 的排版算出屏幕上的方框（1280×720，UDim2 + AnchorPoint + UIListLayout + UIScale 的近似），
--   写成 JSON；tools/mock/hud_render.py 画成图看。也按 ScreenGui 列出各有多少个显示着的元素（找没关掉的旧界面）
local T = dofile(MOCK_DIR .. "/common.lua")
local R, V3, CF, Enum = T.R, T.V3, T.CF, T.Enum
local check = T.check
local out = TEST_ARGS:match("out=(%S+)")
local kind = TEST_ARGS:match("kind=(%a+)") or "tank"
local mySide = TEST_ARGS:match("side=(%a+)") or "def"   -- atk：开 96 式那一边的车

local G = T.boot()
T.runUntil(function() return G.worldReady end, 120)
local me = T.join("P1", 7501, true)
T.runUntil(function() return G.round and (G.round.phase == "prep" or G.round.phase == "battle") end, 30)
local P = G.P[me]
P.team = mySide
me.Team = G.TEAM[mySide]
me.Neutral = false
me:SetAttribute("Side", mySide)
G.pushOne(P)
R.run(1)
local C = T.C
T.act("deploy", "rifle", mySide == "def" and "camp" or "fleet")
R.run(3)
check(P.alive, "守方在营地出生")
if not TEST_ARGS:find("prep", 1, true) then T.runUntil(function() return G.round.phase == "battle" end, 200, 1 / 10) end

if kind == "gunsmith" then
  -- 改枪界面：打开、点「瞄具」、鼠标停在全息瞄具的卡片上（预览）；镜头参数写进 <out>.cam.json（tools/weapons/gunrender.mjs 照它拍枪，贴进视口）
  R.as("client", function() C.openGunsmith(TEST_ARGS:match("gun=(%w+)") or "m4") end)
  for _ = 1, 40 do R.run(0.25) end
  local slot = TEST_ARGS:match("slot=(%w+)") or "optic"
  local hover = TEST_ARGS:match("hover=([%w_]+)") or "opt_holo"
  local gui = me.PlayerGui:FindFirstChild("Gunsmith")
  for _, d in ipairs(gui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == C.T("gm.slot." .. slot) and d.Parent and d.Parent.ClassName == "TextButton" then T.press(d.Parent) end
  end
  for _ = 1, 20 do R.run(0.1) end
  for _, d in ipairs(gui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == C.T("gm.item." .. hover) and d.Parent and d.Parent.ClassName == "TextButton" then
      R.as("client", function() d.Parent.MouseEnter:Fire() end)
    end
  end
  for _ = 1, 30 do R.run(1 / 30) end
  if out then
    local S, vcam = C.gunsmithDebug()
    local b = {}
    for k, v in pairs(S.cur) do b[k] = v end
    if S.hover and S.slot then b[S.slot] = S.hover end
    local c = { vcam.CFrame:GetComponents() }
    local f = io.open(out .. ".cam.json", "w")
    local parts = {}
    for k, v in pairs(b) do parts[#parts + 1] = string.format('"%s":"%s"', k, v) end
    f:write(string.format('{"gun":"%s","fov":%.3f,"cf":[%s],"build":{%s}}', S.id, vcam.FieldOfView, table.concat((function()
      local o = {}
      for i, v in ipairs(c) do o[i] = string.format("%.5f", v) end
      return o
    end)(), ","), table.concat(parts, ",")))
    f:close()
  end
elseif kind ~= "inf" then
  local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
  local list = G.Config.Vehicles[mySide][kind] or G.Config.Vehicles[mySide].tank
  local foeSide = mySide == "def" and "atk" or "def"
  local tid = list[1]
  local d = VD.get(tid)
  local hrp = me.Character.HumanoidRootPart
  local p = hrp.Position
  local x, z = p.X + 30, p.Z + 30
  if mySide == "atk" then   -- 攻方在舰队出生：找一块岸上的平地
    local pt = G.points and (G.points.A or G.points.C)
    local px, pz = pt and pt.pos and pt.pos.X or 0, pt and pt.pos and pt.pos.Z or 0
    for r = 120, 900, 40 do
      local found = false
      for a = 0, 330, 30 do
        local tx, tz = px + math.cos(math.rad(a)) * r, pz + math.sin(math.rad(a)) * r
        if G.Map.height(tx, tz) > 4 and G.Map.slope(tx, tz) < 0.12 and G.Map.height(tx, tz - 160) > 3 then x, z, found = tx, tz, true break end
      end
      if found then break end
    end
  end
  local e = G.newVehicle(mySide, tid, G.vehBaseAt(d, x, z, V3(0, 0, -1)))
  local ft = G.Config.Vehicles[foeSide].tank[1]
  G.newVehicle(foeSide, ft, G.vehBaseAt(VD.get(ft), x + 25, z - 160, V3(0, 0, 1)))
  R.run(0.5)
  me.Character:PivotTo(CF(x + 6, G.Map.ground(x + 6, z) + 3.5, z))
  R.run(0.3)
  T.act("enterVeh", e.id)
  R.run(1)
  check(C.drive ~= nil, "坐进 " .. tid)
  if C.drive then C.drive.camYaw = C.drive.yaw + math.pi end   -- 镜头朝车头看（模拟器里镜头偏航和车头差半圈；炮塔不用转过来）
  R.run(1)
  T.key(Enum.KeyCode.W, true)
  R.run(1.5)
  T.key(Enum.KeyCode.W, false)
  R.run(2.5)
end

-- 排版：算每个显示着的界面元素在屏幕上的方框
local VW, VH, INSET = 1280, 720, 36
local items, perGui = {}, {}
local function c3(c) return c and { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } or nil end
local function isGui(o) return R.base.IsA(o, "GuiObject") end
local function place(o, px, py, pw, ph, scale, guiName, z0, alpha)
  local p = o._p
  local sz = o.Size
  local ps = o.Position
  local ap = o.AnchorPoint
  local w = (sz.XS * pw + sz.XO) * scale
  local h = (sz.YS * ph + sz.YO) * scale
  local x = px + ps.XS * pw + ps.XO * scale - ap.X * w
  local y = py + ps.YS * ph + ps.YO * scale - ap.Y * h
  return x, y, w, h
end
local function cut(a, x, y, w, h, r)   -- 裁剪框（ClipsDescendants、CanvasGroup）：和上一层的取交集
  local b = { x, y, x + w, y + h, r or 0 }
  if not a then return b end
  return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]), (r and r > 0) and r or a[5] }
end
local function walk(o, px, py, pw, ph, scale, guiName, depth, clip, ga)
  ga = ga or 1
  -- 子元素：有 UIListLayout 的按顺序排
  local layout = o:FindFirstChildOfClass("UIListLayout")
  local kids = {}
  for _, c in ipairs(o._kids) do if isGui(c) and c._p.Visible ~= false then kids[#kids + 1] = c end end
  local us = o:FindFirstChildOfClass("UIScale")
  local sc = scale * (us and us.Scale or 1)
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
    local x, y, w, h = place(c, px, py, pw, ph, sc)
    if layout then
      x, y = px + cx, py + cy
      local padPx = pad and (pad.Scale * (horiz and pw or ph) + pad.Offset) or 0
      if horiz then cx = cx + w + padPx else cy = cy + h + padPx end
    end
    local p = c._p
    local stroke = c:FindFirstChildOfClass("UIStroke")
    local corner = c:FindFirstChildOfClass("UICorner")
    local rec = { cls = c._cls, name = c._p.Name, gui = guiName, depth = depth, z = c.ZIndex or 1,
      x = x, y = y, w = w, h = h, rot = c.Rotation or 0,
      bg = c3(c.BackgroundColor3), bgT = c.BackgroundTransparency, }
    if corner then rec.corner = corner.CornerRadius.Scale * math.min(w, h) + corner.CornerRadius.Offset * sc end
    if stroke and stroke._p.Enabled ~= false then rec.st = c3(stroke.Color) rec.stT = stroke.Transparency rec.stW = stroke.Thickness end
    if c._cls == "TextLabel" or c._cls == "TextButton" or c._cls == "TextBox" then
      rec.text, rec.tc, rec.tT, rec.ts = c.Text, c3(c.TextColor3), c.TextTransparency, (c.TextSize or 14) * sc
      rec.scaled = c.TextScaled
      rec.xa = tostring(c.TextXAlignment)
    end
    if c._cls == "ImageLabel" or c._cls == "ImageButton" then
      rec.img = c.Image rec.ic = c3(c.ImageColor3) rec.iT = c.ImageTransparency
      rec.icon = c:GetAttribute("Icon")   -- HudArt 装上的图标（HudIcons 里的名字）
    end
    rec.clip, rec.ga = clip, ga
    if c._cls == "ViewportFrame" then rec.vp = c._p.Name end
    local grad = c:FindFirstChildOfClass("UIGradient")
    if grad then
      pcall(function()
        local kp = {}
        for _, k in ipairs(grad.Transparency.Keypoints) do kp[#kp + 1] = { k.Time, k.Value } end
        rec.grad = { rot = grad.Rotation or 0, kp = kp }
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
    if c._cls ~= "ViewportFrame" then walk(c, x, y, w, h, sc, guiName, depth + 1, kidClip, kidGa) end
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
  walk(g, 0, top, VW, VH - top, 1, g._p.Name .. "#" .. gi, 0)
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
T.summary()
