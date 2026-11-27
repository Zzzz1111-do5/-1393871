-- Roblox全面大战场（客户端）——防空火控显示（用户 11-22：「高射炮加一个电子屏标记点位然后打」）
--   开防空车（Drive.lua：Cat = aa 的车、用炮的）、操作高炮工事（Gunner.lua：aaa）时每帧调 G.aaFcs(o)：
--   ① 射程里的每架敌机：方框四角（离得越近框越大）、底下写型号和距离；屏幕外的在屏幕边上画个箭头指过去
--   ② 指定目标（准星附近 25° 里最近的那架，锁定了就是锁定的那架）：框变琥珀色，算出提前量点（炮弹飞过去的时间里飞机飞到哪、
--      炮弹往下掉多少都算上），画一个圈、从飞机连一根线过去，写着弹丸飞行时间；准星压在圈上（2° 以内）圈变绿——这时开火就是按提前量打
--   ③ Q 雷达锁定 / 解锁：锁住以后炮塔自己跟着提前量点转（准星不用跟），框变红、写「锁定」；飞机被打下来、飞出射程自动解锁
--   ④ 左边一块小圆屏（搜索雷达）：车头朝上，一圈圈距离环、扫描线，敌机红点、锁定的那架加框，炮塔指向一根线
--   返回 { aimPt = 炮该指的点（锁定、或者准星压在圈上时；已经含弹道下坠，Drive 那边别再加）, locked, onTarget }
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local AaFcs = {}

function AaFcs.init(G)
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local V = Vector3.new
  local UD2 = UDim2.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local function L(cn, en) return (G.lang == "en") and en or cn end
  local AD = nil
  pcall(function() AD = require(RS:WaitForChild("AirDefs", 5)) end)

  local HOST, AMBER, LOCKC, GOOD, INK = RGB(255, 84, 70), RGB(255, 196, 60), RGB(255, 60, 60), RGB(110, 255, 140), RGB(230, 236, 232)
  local FONT, FONTB = Enum.Font.RobotoMono, Enum.Font.BuilderSansMedium

  local gui = Instance.new("ScreenGui")
  gui.Name = "AaFcs"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 4
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")

  local function frame(parent, size, pos, col, tr, anchor)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UD2()
    f.AnchorPoint = anchor or Vector2.new(0, 0)
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or INK, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function label(parent, size, pos, ts, col, anchor, font)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UD2()
    l.AnchorPoint = anchor or Vector2.new(0, 0)
    l.BackgroundTransparency = 1
    l.TextSize, l.TextColor3, l.Font = ts or 12, col or INK, font or FONT
    l.TextStrokeTransparency, l.TextStrokeColor3 = 0.5, RGB(0, 0, 0)
    l.Text = ""
    l.Parent = parent
    return l
  end
  local function round(f)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
    return f
  end
  local function stroke(f, col, th)
    local s = Instance.new("UIStroke")
    s.Color, s.Thickness = col, th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
    return s
  end

  ---------------------------------------------------------------- 目标框（四角）、屏幕边的箭头
  local boxes = {}
  local function box(i)
    local b = boxes[i]
    if b then return b end
    b = { f = frame(gui, UD2(0, 40, 0, 40), nil, INK, 1, Vector2.new(0.5, 0.5)), c = {} }
    for _, k in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
      table.insert(b.c, frame(b.f, UD2(0.3, 0, 0, 2), UD2(k[1], 0, k[2], 0), HOST, 0, Vector2.new(k[1], k[2])))
      table.insert(b.c, frame(b.f, UD2(0, 2, 0.3, 0), UD2(k[1], 0, k[2], 0), HOST, 0, Vector2.new(k[1], k[2])))
    end
    b.t = label(b.f, UD2(0, 160, 0, 14), UD2(0.5, 0, 1, 4), 12, HOST, Vector2.new(0.5, 0))
    b.tag = label(b.f, UD2(0, 80, 0, 14), UD2(0.5, 0, 0, -4), 12, LOCKC, Vector2.new(0.5, 1), FONTB)
    boxes[i] = b
    return b
  end
  local function boxColor(b, col)
    if b.col == col then return end
    b.col = col
    for _, f in ipairs(b.c) do f.BackgroundColor3 = col end
    b.t.TextColor3 = col
  end
  local arrows = {}
  local function arrow(i)
    local a = arrows[i]
    if a then return a end
    a = label(gui, UD2(0, 22, 0, 22), nil, 20, HOST, Vector2.new(0.5, 0.5), FONTB)
    a.Text = "▲"
    arrows[i] = a
    return a
  end

  ---------------------------------------------------------------- 提前量：圈、连线、飞行时间
  local lead = round(frame(gui, UD2(0, 20, 0, 20), nil, INK, 1, Vector2.new(0.5, 0.5)))
  local leadS = stroke(lead, AMBER, 2)
  local leadDot = round(frame(lead, UD2(0, 4, 0, 4), UD2(0.5, 0, 0.5, 0), AMBER, 0, Vector2.new(0.5, 0.5)))
  local leadLine = frame(gui, UD2(0, 10, 0, 1), nil, AMBER, 0.35, Vector2.new(0.5, 0.5))
  local leadT = label(gui, UD2(0, 120, 0, 14), nil, 12, AMBER, Vector2.new(0, 0.5))
  local status = label(gui, UD2(0, 420, 0, 16), UD2(0.5, 0, 0.5, 78), 13, INK, Vector2.new(0.5, 0), FONTB)
  status.Name = "AaStatus"

  ---------------------------------------------------------------- 搜索雷达小圆屏
  local PR = 74
  local ppi = round(frame(gui, UD2(0, PR * 2, 0, PR * 2), UD2(0, 22, 0.5, -PR), RGB(6, 16, 10), 0.25))
  ppi.Name = "AaRadar"
  stroke(ppi, RGB(80, 200, 110), 1.5)
  for i = 1, 2 do
    local r = PR * i / 3
    local c = round(frame(ppi, UD2(0, r * 2, 0, r * 2), UD2(0.5, 0, 0.5, 0), INK, 1, Vector2.new(0.5, 0.5)))
    stroke(c, RGB(60, 150, 80), 1)
  end
  frame(ppi, UD2(0, 1, 1, -8), UD2(0.5, 0, 0.5, 0), RGB(60, 150, 80), 0.4, Vector2.new(0.5, 0.5))
  frame(ppi, UD2(1, -8, 0, 1), UD2(0.5, 0, 0.5, 0), RGB(60, 150, 80), 0.4, Vector2.new(0.5, 0.5))
  local sweep = frame(ppi, UD2(0, 2, 0, PR - 4), UD2(0.5, 0, 0.5, 0), RGB(120, 255, 150), 0.25, Vector2.new(0.5, 1))
  local gunLine = frame(ppi, UD2(0, 2, 0, PR * 0.8), UD2(0.5, 0, 0.5, 0), AMBER, 0.1, Vector2.new(0.5, 1))
  round(frame(ppi, UD2(0, 6, 0, 6), UD2(0.5, 0, 0.5, 0), RGB(120, 200, 255), 0, Vector2.new(0.5, 0.5)))
  local ppiT = label(ppi, UD2(0, 220, 0, 14), UD2(0, 0, 1, 4), 11, RGB(120, 255, 150), nil)
  ppiT.TextXAlignment = Enum.TextXAlignment.Left
  local dots = {}
  local function dot(i)
    local d = dots[i]
    if d then return d end
    d = round(frame(ppi, UD2(0, 6, 0, 6), nil, HOST, 0, Vector2.new(0.5, 0.5)))
    dots[i] = d
    return d
  end
  local lockSq = frame(ppi, UD2(0, 12, 0, 12), nil, INK, 1, Vector2.new(0.5, 0.5))
  stroke(lockSq, LOCKC, 1.5)

  ---------------------------------------------------------------- 跟踪（每架飞机按位置差估速度）、锁定
  local track = {}
  local lockId, lastT, active = nil, 0, false
  local cur = nil   -- 这一帧的指定目标
  local function hostileAir(side)
    local list = {}
    local ents = workspace:FindFirstChild("Ents")
    if not ents then return list end
    local now = os.clock()
    for _, m in ipairs(ents:GetChildren()) do
      if m:GetAttribute("Kind") == "air" and m:GetAttribute("Team") ~= side and (m:GetAttribute("Hp") or 1) > 0 then
        local r = m:FindFirstChild("Root")
        if r then
          local id = m:GetAttribute("EntId") or m.Name
          local p = r.Position
          local tr = track[id]
          if not tr then
            tr = {}
            track[id] = tr
          end
          -- 速度：只在服务器真挪了它时按两次挪之间的时间算、按时间平滑（View.lua G.velTrack；原来每帧差分 × 0.3，锁定圈一跳一跳）
          if G.velTrack then G.velTrack(tr, p, now, 1500)
          else tr.p, tr.t, tr.v = p, now, tr.v or V() end
          tr.seen = now
          table.insert(list, { id = id, m = m, p = p, v = tr.v, model = m:GetAttribute("Model") })
        end
      end
    end
    for id, tr in pairs(track) do if now - (tr.seen or 0) > 2 then track[id] = nil end end
    return list
  end
  -- 炮弹从 o 以速度 s 打出去、重力 g（向下）：打中速度 v 的目标该瞄哪（含下坠的抬高），飞行时间
  local function intercept(o, p, v, s, g)
    local t = (p - o).Magnitude / s
    for _ = 1, 4 do t = ((p + v * t) - o).Magnitude / s end
    local hit = p + v * t
    return hit, hit + V(0, 0.5 * g * t * t, 0), t
  end
  local function typeName(model)
    local d = AD and AD.get and model and AD.get(model)
    local nm = model and T("veh." .. model) or nil
    if not nm or nm == "veh." .. tostring(model) then nm = (d and d.kind == "heli") and L("直升机", "HELO") or L("飞机", "AIR") end
    return nm
  end

  UIS.InputBegan:Connect(function(io, gp)
    if gp or io.KeyCode ~= Enum.KeyCode.Q then return end
    if not active or os.clock() - lastT > 0.3 then return end
    if lockId then
      lockId = nil
      if G.sfx then pcall(G.sfx, "uiClick") end
    elseif cur then
      lockId = cur.id
      if G.sfx then pcall(G.sfx, "uiClick") end
    else
      if G.toast then G.toast(L("没有可以锁定的目标（准星对准敌机附近）", "No target to lock (aim near an enemy aircraft)"), "info") end
    end
  end)

  function G.aaFcsHide()
    if gui.Enabled then gui.Enabled = false end
    active = false
    lockId = nil
    cur = nil
  end
  G.aaFcsState = function() return { lockId = lockId, target = cur, active = active } end   -- 测试用

  -- o = { origin（炮口 / 炮耳轴，世界坐标）, speed（弹速，格 / 秒）, g（弹道重力，格 / 秒²）, range（格）, look（准星方向）, side, hullYaw（车头方位，弧度）, gunYaw（炮指的方位，弧度） }
  function G.aaFcs(o)
    local cam = workspace.CurrentCamera
    if not cam then return {} end
    active, lastT = true, os.clock()
    gui.Enabled = true
    local vp = cam.ViewportSize
    local list = hostileAir(o.side)
    local look = o.look or cam.CFrame.LookVector
    -- 指定目标：锁定的那架；没锁就挑准星附近 25° 里离得最近的
    local best, bestK = nil, math.huge
    local locked = nil
    for _, t in ipairs(list) do
      local to = t.p - o.origin
      t.dist = to.Magnitude
      t.inRange = t.dist < o.range
      if t.id == lockId then locked = t end
      if t.inRange then
        local ang = math.deg(math.acos(math.clamp(to.Unit:Dot(look), -1, 1)))
        if ang < 25 then
          local k = ang * 30 + t.dist * 0.01
          if k < bestK then best, bestK = t, k end
        end
      end
    end
    if lockId and (not locked or not locked.inRange) then   -- 锁定的被打下来 / 飞出射程：解锁
      lockId = nil
      locked = nil
      if G.toast then G.toast(L("目标丢失，锁定解除", "Track lost — lock released"), "info") end
    end
    cur = locked or best
    local res = { locked = locked ~= nil }
    -- 方框、屏幕边箭头
    local nb, na = 0, 0
    for _, t in ipairs(list) do
      if t.dist < o.range * 1.6 then
        local sp, on = cam:WorldToViewportPoint(t.p)
        if on and sp.Z > 0 then
          nb += 1
          local b = box(nb)
          local px = math.clamp(2400 / math.max(sp.Z, 1) * (70 / cam.FieldOfView), 26, 70)
          b.f.Size = UD2(0, px, 0, px)
          b.f.Position = UD2(0, sp.X, 0, sp.Y)
          b.f.Visible = true
          local col = (t == locked) and LOCKC or ((t == cur) and AMBER or HOST)
          if not t.inRange then col = RGB(170, 120, 110) end
          boxColor(b, col)
          b.t.Text = string.format("%s  %.1f km", typeName(t.model), t.dist / 2.8 / 1000)
          b.tag.Text = (t == locked) and L("锁定", "LOCK") or ""
          b.tag.Visible = t == locked and (os.clock() % 0.6) < 0.42
        elseif t.inRange then
          na += 1
          local a = arrow(na)
          local q = cam.CFrame:PointToObjectSpace(t.p)
          local ang = math.atan2(q.X, q.Y)   -- 屏幕上往哪边（0 = 上）
          local cx, cy = vp.X / 2, vp.Y / 2
          local r = math.min(vp.X, vp.Y) * 0.42
          a.Position = UD2(0, cx + math.sin(ang) * r, 0, cy - math.cos(ang) * r)
          a.Rotation = math.deg(ang)
          a.TextColor3 = (t == locked) and LOCKC or HOST
          a.Visible = true
        end
      end
    end
    for i = nb + 1, #boxes do boxes[i].f.Visible = false end
    for i = na + 1, #arrows do arrows[i].Visible = false end
    -- 提前量
    lead.Visible, leadLine.Visible, leadT.Visible = false, false, false
    if cur and cur.inRange then
      local hit, aim, tof = intercept(o.origin, cur.p, cur.v, o.speed, o.g or 0)
      local sp, on = cam:WorldToViewportPoint(hit)
      local onT = false
      do
        local toA = (hit - o.origin).Unit
        local ang = math.deg(math.acos(math.clamp(toA:Dot(look), -1, 1)))
        onT = ang < 2
      end
      if on and sp.Z > 0 then
        lead.Visible = true
        lead.Position = UD2(0, sp.X, 0, sp.Y)
        local col = locked and LOCKC or (onT and GOOD or AMBER)
        leadS.Color, leadDot.BackgroundColor3 = col, col
        local tp, on2 = cam:WorldToViewportPoint(cur.p)
        if on2 and tp.Z > 0 then
          local dx, dy = sp.X - tp.X, sp.Y - tp.Y
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 14 then
            leadLine.Visible = true
            leadLine.Position = UD2(0, (sp.X + tp.X) / 2, 0, (sp.Y + tp.Y) / 2)
            leadLine.Size = UD2(0, len - 12, 0, 1)
            leadLine.Rotation = math.deg(math.atan2(dy, dx))
            leadLine.BackgroundColor3 = col
          end
        end
        leadT.Visible = true
        leadT.Position = UD2(0, sp.X + 14, 0, sp.Y)
        leadT.Text = string.format("%.1fs", tof)
        leadT.TextColor3 = col
      end
      res.target, res.tof = cur, tof
      res.onTarget = onT
      if locked or onT then res.aimPt = aim end
      if locked then
        status.Text = string.format(L("雷达锁定 %s · %.1f 公里 · 炮塔自动跟踪 · 左键开火 · Q 解锁", "RADAR LOCK %s · %.1f km · turret tracking · LMB fire · Q unlock"),
          typeName(cur.model), cur.dist / 2.8 / 1000)
        status.TextColor3 = LOCKC
      elseif onT then
        status.Text = L("准星压在提前量圈上：开火 · Q 雷达锁定", "On the lead circle: fire · Q radar lock")
        status.TextColor3 = GOOD
      else
        status.Text = L("准星对准提前量圈开火 · Q 雷达锁定", "Put the pipper on the lead circle · Q radar lock")
        status.TextColor3 = AMBER
      end
    else
      local n = 0
      for _, t in ipairs(list) do if t.inRange then n += 1 end end
      status.Text = (n > 0) and string.format(L("射程内敌机 %d 架 · 准星转过去", "%d hostile aircraft in range · swing toward them"), n) or L("搜索中：射程内没有敌机", "Searching: no aircraft in range")
      status.TextColor3 = INK
    end
    -- 搜索雷达小圆屏（车头朝上）
    local hy = o.hullYaw or 0
    local tnow = os.clock()
    sweep.Rotation = (tnow * 150) % 360
    gunLine.Rotation = -math.deg((o.gunYaw or hy) - hy)
    local nd = 0
    lockSq.Visible = false
    local R = o.range * 1.5
    for _, t in ipairs(list) do
      local q = t.p - o.origin
      local flat = V(q.X, 0, q.Z)
      local dist = flat.Magnitude
      if dist < R then
        nd += 1
        local d = dot(nd)
        local a = math.atan2(-q.X, -q.Z) - hy
        local k = dist / R * (PR - 6)
        local x, y = PR - math.sin(a) * k, PR - math.cos(a) * k
        d.Position = UD2(0, x, 0, y)
        d.BackgroundColor3 = (t == locked) and LOCKC or ((t == cur) and AMBER or HOST)
        d.Visible = true
        if t == locked then
          lockSq.Visible = true
          lockSq.Position = UD2(0, x, 0, y)
        end
      end
    end
    for i = nd + 1, #dots do dots[i].Visible = false end
    ppiT.Text = string.format(L("搜索雷达 %.1f 公里 · 目标 %d", "SEARCH %.1f km · TRK %d"), R / 2.8 / 1000, nd)
    return res
  end

  -- 下车、换车、死了（Drive / Gunner 不调了）：收起来、解锁
  G.frameConn("AaFcs", function()
    if active and os.clock() - lastT > 0.3 then G.aaFcsHide() end
  end)
end

return AaFcs
