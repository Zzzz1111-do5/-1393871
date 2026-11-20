-- 开坦克时屏幕上画了什么（模拟器）：python3 tools/mock/run.py tools/mock/hudshot.lua out=<文件.json> [kind=tank|ifv|ship|inf] [hp=0.5] [erax=1,2,5]
--   kind=jet / heli：开飞机（空中出发，前方一架敌机、地上一辆敌车）[id=j20] [alt=700]——看开飞机的界面（AirHud，用户 11-19 照 MWT 截图改）
--     [lock=0.5]：锁定画到一半（菱形顺时针画了一半）；[outcone=1]：锁上以后把敌机挪到导弹离轴角外（菱形变黄）；[ir=1]：开热成像；
--     [roll=25]：带坡度；[clean=1]：截图前收起新手卡、作战简报
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

if kind == "jet" or kind == "heli" then
  local foeSide = mySide == "def" and "atk" or "def"
  local id = TEST_ARGS:match("id=(%w+)") or G.Config.Vehicles[mySide][kind][1]
  local p = me.Character.HumanoidRootPart.Position
  local alt = tonumber(TEST_ARGS:match("alt=(%d+)") or "") or ((kind == "jet") and 700 or 160)
  local x, z = p.X, p.Z
  local cf = CF(x, math.max(G.Map.ground(x, z), 0) + alt, z)   -- 朝 −Z
  local fe = G.spawnAircraft(foeSide, G.Config.Vehicles[foeSide].jet[1], cf * CF(90, 60, -1000), nil, nil)
  local VD = R.require(R.services.ReplicatedStorage:FindFirstChild("VehDefs"))
  local ft = G.Config.Vehicles[foeSide].tank[1]
  pcall(function() G.newVehicle(foeSide, ft, G.vehBaseAt(VD.get(ft), x - 160, z - 1500, V3(0, 0, 1))) end)
  local e = G.spawnAircraft(mySide, id, cf, nil, P)
  me.Character:PivotTo(cf * CF(4, 0, 0))
  T.act("enterVeh", e.id)
  R.run(0.2)
  local st = C.fly
  if st then   -- 刚放的飞机算停在地上（零速度、起落架放着）：改成巡航（八成军推速度、收起落架；直升机前飞）
    st.ground = false
    if kind == "jet" then
      st.spd = st.d.vMil * 0.8
      st.vel = st.cf.LookVector * st.spd
      st.thr, st.gearWant, st.gear = 85, 0, 0
    else
      st.rpm = 100
      st.hv = st.cf.LookVector * st.d.vMax * 0.5
      st.vel = st.hv
    end
  end
  R.run(2.5)
  check(C.fly ~= nil and C.fly.pilot, "坐进 " .. id .. "（离地 " .. alt .. " 格）")
  check(fe ~= nil, "前方放了一架敌机")
  local hpK = tonumber(TEST_ARGS:match("hp=([%d%.]+)") or "")
  if hpK and e and e.alive then
    G.damageEnt(e, e.maxHp * (1 - hpK), { team = foeSide, name = "test" })
    R.run(0.6)
  end
  local AD = R.require(R.services.ReplicatedStorage:FindFirstChild("AirDefs"))
  local st2 = C.fly
  if fe and fe.root and st2 then   -- 没人开的敌机停在原地、自己这架掉了一些高度：截图前把它重新摆到正前方 700 格、稍偏右上
    fe.root.CFrame = st2.cf * CF(70, 25, -700)
    R.run(0.3)
  end
  local w = st2 and AD.W[st2.wl[st2.wi]]
  check(st2 ~= nil and st2.lock ~= nil, "锁着前方的敌机：" .. tostring(st2 and st2.lock and st2.lock.em and st2.lock.em:GetAttribute("Model")))
  local function where(tag)
    if not (st2 and st2.lock) then return end
    local rel = st2.cf:PointToObjectSpace(st2.lock.pos)
    local ang = math.deg(math.acos(math.max(-1, math.min(1, st2.cf.LookVector:Dot((st2.lock.pos - st2.cf.Position).Unit)))))
    print(string.format("  %s：锁定目标在机身坐标 右 %.0f 上 %.0f 前 %.0f（偏 %.0f°），离开离轴角 %s", tag, rel.X, rel.Y, -rel.Z, ang, tostring(st2.lock.out)))
  end
  where("截图前")
  if fe and fe.model then
    print(string.format("  敌机实体：Cat=%s Team=%s Hp=%s/%s Kind=%s Root=%s Wreck=%s", tostring(fe.model:GetAttribute("Cat")), tostring(fe.model:GetAttribute("Team")),
      tostring(fe.model:GetAttribute("Hp")), tostring(fe.model:GetAttribute("MaxHp")), tostring(fe.model:GetAttribute("Kind")), tostring(fe.model:FindFirstChild("Root") ~= nil), tostring(fe.model:GetAttribute("Wreck"))))
  end
  if TEST_ARGS:find("outcone=1", 1, true) and fe and st2 and w then   -- 敌机挪到离轴角外（还在跟踪的范围里）
    local cone = w.cone or 30
    local a = math.rad(math.min(cone * 1.6, 80))
    local p0 = st2.cf.Position
    local dir = (st2.cf.LookVector * math.cos(a) + st2.cf.RightVector * math.sin(a))
    fe.root.CFrame = CF(p0 + dir * 900)
    R.run(0.25)
    where("挪开以后")
    check(st2.lock ~= nil and st2.lock.out == true, "敌机出了离轴角：锁还在、算在发射角度外")
  end
  local lockK = tonumber(TEST_ARGS:match("lock=([%d%.]+)") or "")
  if lockK and st2 and st2.lock and w then
    st2.lockT = lockK * (w.lockTime or 1)
    R.run(1 / 60)
  end
  local roll = tonumber(TEST_ARGS:match("roll=(%-?[%d%.]+)") or "")
  if roll and st2 then   -- 带一点坡度（看机头全息准心跟着机身滚转、有透视）
    st2.cf = st2.cf * R.CFrame.Angles(0, 0, math.rad(-roll))
    R.run(1 / 60)
  end
  if TEST_ARGS:find("ir=1", 1, true) and C.airThermal then
    C.airThermal(true)
    R.run(0.2)
  end
end

if kind ~= "inf" and kind ~= "jet" and kind ~= "heli" then
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
  -- hp=0.5：挨一下打到这个血量（看「被发现!」、车的图标按车况变黄 / 变红）
  local hpK = tonumber(TEST_ARGS:match("hp=([%d%.]+)") or "")
  if hpK and e and e.alive then
    G.damageEnt(e, e.maxHp * (1 - hpK), { team = foeSide, name = "test" })
    R.run(0.6)
  end
  -- erax=1,2,5：这几块爆反算炸掉了（看视角图上爆反的缺口）
  local ex = TEST_ARGS:match("erax=([%d,]+)")
  if ex and e and e.model then
    e.model:SetAttribute("EraX", ex)
    R.run(0.3)
  end
end

-- clean=1：截图前收起新手三步卡、开局的作战简报（只为了截图好看）
if TEST_ARGS:find("clean=1", 1, true) then
  for _, d in ipairs(me.PlayerGui:GetDescendants()) do
    if d.Name == "CoachCard" or d.Name == "OperationBrief" then d.Visible = false end
  end
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
T.summary()
