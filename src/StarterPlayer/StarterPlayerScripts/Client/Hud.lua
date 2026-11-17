-- Roblox全面大战场（客户端）——战斗中的界面（用户给了《坠落》的截图，照那个风格）：
--   顶部比分条：四角括号框住；左边自己队（队名、细比分线、手里的据点数），中间 ◀ 时间 ▶，右边对面；下面 A～E 菱形据点（颜色按谁占着，进度条、争夺中闪）
--   世界里的据点：菱形字母 + 距离（米），隔着东西也看得见
--   左下：方形小地图（跟着人走、北朝上），上面是镜头朝向的读数，中间白箭头是自己
--   左边：小队（同队真人按 UserId 排、每 5 人一队：阿尔法 / 布拉沃…；名字 + 血条，自己高亮）
--   右下：武器名 + 射击方式，弹药「028 / 900」细字体
--   UI.lua 原来的顶栏、血条、兵种字，Play.lua 原来的弹药字交给这里：挪进一个关着的 ScreenGui（它们照样刷新，只是不画）；小地图框挪到左下
local Players = game:GetService("Players")

local Hud = {}

function Hud.init(G)
  local Config, Map = G.Config, G.Map
  local ui, P = G.ui, G.hudParts
  if not (ui and P) then return end
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local V2 = Vector2.new
  local W = Config.Weapons
  local WHITE = Color3.new(1, 1, 1)
  local TEXT, MUTE = RGB(236, 240, 236), RGB(170, 178, 174)
  local NUM = Enum.Font.Jura   -- 细的数字（弹药、距离、朝向）
  local M_PER = 2.8            -- 1 米多少格（同 AirDefs.M）
  local function T(k, ...) return G.T(k, ...) end
  local function teamColor(t) return Config.Teams[t or "atk"].color end
  local function other(t) return (t == "atk") and "def" or "atk" end
  local function shadow(l, a)
    l.TextStrokeTransparency = a or 0.55
    l.TextStrokeColor3 = Color3.new(0, 0, 0)
    return l
  end
  local mobile = G.mobile == true

  -- 旧的顶栏、血条、兵种字、弹药字：收进一个关着的 ScreenGui
  local stash = Instance.new("ScreenGui")
  stash.Name = "HudStash"
  stash.Enabled = false
  stash.ResetOnSpawn = false
  stash.Parent = me:WaitForChild("PlayerGui")
  for _, k in ipairs({ "topBar", "counts", "hpBg", "roleText" }) do
    if P[k] then P[k].Parent = stash end
  end
  if G.ammoLabel then G.ammoLabel.Parent = stash end

  ---------------------------------------------------------------- 顶部比分条

  local BW = 700
  local top = ui.frame(P.hud, UDim2.fromOffset(BW, 44), UDim2.new(0.5, 0, 0, mobile and 6 or 12), RGB(0, 0, 0), 1, V2(0.5, 0))
  top.Name = "ScoreBar"
  for _, a in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do   -- 四角括号
    ui.frame(top, UDim2.fromOffset(16, 2), UDim2.fromScale(a[1], a[2]), WHITE, 0.3, V2(a[1], a[2]))
    ui.frame(top, UDim2.fromOffset(2, 12), UDim2.fromScale(a[1], a[2]), WHITE, 0.3, V2(a[1], a[2]))
  end
  -- 背后一层很淡的暗色，亮的天空、雪地上字也看得清
  local shade = ui.frame(top, UDim2.new(1, -8, 1, -8), UDim2.fromScale(0.5, 0.5), RGB(0, 0, 0), 0.72, V2(0.5, 0.5))
  local grad = Instance.new("UIGradient")
  grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.2), NumberSequenceKeypoint.new(0.82, 0.2), NumberSequenceKeypoint.new(1, 1) })
  grad.Parent = shade
  local sides = {}
  for _, sx in ipairs({ -1, 1 }) do
    local left = sx < 0
    local s = {}
    s.name = shadow(ui.label(top, "", UDim2.fromOffset(84, 20), UDim2.new(left and 0 or 1, left and 16 or -16, 0.5, 0), 15, TEXT, Enum.Font.GothamBold,
      V2(left and 0 or 1, 0.5), left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right))
    s.barBg = ui.frame(top, UDim2.fromOffset(150, 3), UDim2.new(0.5, sx * 183, 0.5, 0), WHITE, 0.8, V2(0.5, 0.5))
    s.bar = ui.frame(s.barBg, UDim2.fromScale(0, 1), UDim2.fromScale(left and 1 or 0, 0), WHITE, 0, V2(left and 1 or 0, 0))   -- 从比分那头往外长
    s.score = shadow(ui.label(top, "", UDim2.fromOffset(46, 30), UDim2.new(0.5, sx * 82, 0.5, 0), 26, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5)))
    s.arrow = shadow(ui.label(top, left and "◀" or "▶", UDim2.fromOffset(16, 16), UDim2.new(0.5, sx * 50, 0.5, 0), 12, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5)), 0.8)
    sides[sx] = s
  end
  local timer = shadow(ui.label(top, "", UDim2.fromOffset(84, 28), UDim2.fromScale(0.5, 0.5), 22, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5)))
  -- A～E 菱形
  local diamonds = {}
  local row = ui.frame(P.hud, UDim2.fromOffset(BW, 34), UDim2.new(0.5, 0, 0, (mobile and 6 or 12) + 50), RGB(0, 0, 0), 1, V2(0.5, 0))
  row.Name = "Objectives"
  for i, p in ipairs(Map.POINTS) do
    local holder = ui.frame(row, UDim2.fromOffset(30, 34), UDim2.new(0.5, (i - (#Map.POINTS + 1) / 2) * 44, 0, 0), RGB(0, 0, 0), 1, V2(0.5, 0))
    local d = ui.frame(holder, UDim2.fromOffset(19, 19), UDim2.new(0.5, 0, 0, 13), teamColor("def"), 0.12, V2(0.5, 0.5))
    d.Rotation = 45
    local st = ui.stroke(d, WHITE, 1.5, 0.25)
    local l = shadow(ui.label(holder, p.id, UDim2.fromOffset(30, 26), UDim2.fromScale(0.5, 0), 13, WHITE, Enum.Font.GothamBlack, V2(0.5, 0)), 0.7)
    local pb = ui.frame(holder, UDim2.fromOffset(24, 3), UDim2.new(0.5, 0, 1, -3), RGB(0, 0, 0), 0.5, V2(0.5, 0))
    local pf = ui.frame(pb, UDim2.fromScale(0, 1), nil, teamColor("atk"), 0)
    diamonds[p.id] = { holder = holder, d = d, st = st, l = l, pb = pb, pf = pf }
  end

  ---------------------------------------------------------------- 世界里的据点标记

  local pg = me:WaitForChild("PlayerGui")
  local marks = {}
  for _, p in ipairs(Map.POINTS) do
    local a = Instance.new("Part")
    a.Name = "Obj_" .. p.id
    a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.CastShadow = true, false, false, false, false
    a.Transparency = 1
    a.Size = Vector3.new(1, 1, 1)
    a.CFrame = CFrame.new(p.x, (p.y or 40) + 30, p.z)
    a.Parent = workspace.CurrentCamera   -- 只在自己这儿，别人看不见、不参与碰撞
    local bb = Instance.new("BillboardGui")
    bb.Name = "ObjMark_" .. p.id
    bb.Adornee = a
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Size = UDim2.fromOffset(64, 50)
    bb.ResetOnSpawn = false
    bb.Parent = pg
    local d = ui.frame(bb, UDim2.fromOffset(20, 20), UDim2.new(0.5, 0, 0, 14), teamColor("def"), 0.15, V2(0.5, 0.5))
    d.Rotation = 45
    ui.stroke(d, WHITE, 1.5, 0.2)
    shadow(ui.label(bb, p.id, UDim2.fromOffset(30, 28), UDim2.fromScale(0.5, 0), 14, WHITE, Enum.Font.GothamBlack, V2(0.5, 0)), 0.6)
    local dist = shadow(ui.label(bb, "", UDim2.fromOffset(64, 16), UDim2.new(0.5, 0, 0, 30), 13, WHITE, NUM, V2(0.5, 0)), 0.4)
    marks[p.id] = { part = a, bb = bb, d = d, dist = dist, y0 = p.y, ok = p.y ~= nil, tries = 0, x = p.x, z = p.z }
  end
  -- 据点高度：Map 里没写的照地面找（地形生成好以前找不到，过一会儿再试）
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Include
  local function ground(m)
    rp.FilterDescendantsInstances = { workspace.Terrain }
    local hit = workspace:Raycast(Vector3.new(m.x, 2000, m.z), Vector3.new(0, -4000, 0), rp)
    if hit then
      m.part.CFrame = CFrame.new(m.x, math.max(hit.Position.Y, 0) + 30, m.z)
      m.ok = true
    end
  end

  ---------------------------------------------------------------- 左下小地图

  local MS = mobile and 150 or 210
  local box = P.miniBox
  box.AnchorPoint = mobile and V2(0, 0) or V2(0, 1)
  box.Position = mobile and UDim2.new(0, 16, 0, 118) or UDim2.new(0, 16, 1, -16)   -- 手机：左下是摇杆，放到左上（让开战况表按钮）
  box.Size = UDim2.fromOffset(MS, MS)
  box.BackgroundColor3 = RGB(8, 12, 14)
  box.BackgroundTransparency = 0.35
  box.ClipsDescendants = true
  ui.stroke(box, WHITE, 1, 0.75)
  local ZOOM = 1200   -- 小地图里整张图画多大（像素）：框里看得到大约 1000 格
  local arrow = shadow(ui.label(box, "▲", UDim2.fromOffset(18, 18), UDim2.fromScale(0.5, 0.5), 15, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5)), 0.2)
  arrow.ZIndex = 20
  local north = shadow(ui.label(box, "N", UDim2.fromOffset(16, 16), UDim2.new(0.5, 0, 0, 2), 12, WHITE, Enum.Font.GothamBold, V2(0.5, 0)), 0.3)
  north.ZIndex = 20
  local heading = shadow(ui.label(P.hud, "", UDim2.fromOffset(60, 18), mobile and UDim2.new(0, 16 + MS / 2, 0, 118 + MS + 2) or UDim2.new(0, 16 + MS / 2, 1, -16 - MS - 4), 15, WHITE, NUM,
    mobile and V2(0.5, 0) or V2(0.5, 1)), 0.4)

  ---------------------------------------------------------------- 左边小队

  local squad = ui.frame(P.hud, UDim2.fromOffset(230, 140), UDim2.new(0, 16, 0.42, 0), RGB(0, 0, 0), 1, V2(0, 0))
  squad.Name = "Squad"
  squad.Visible = not mobile
  local sqHead = shadow(ui.label(squad, "", UDim2.new(1, 0, 0, 20), nil, 14, WHITE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left))
  local sqLine = ui.frame(squad, UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, 22), WHITE, 0.7)
  local rows = {}
  for i = 1, 5 do
    local r = ui.frame(squad, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 26 + (i - 1) * 23), RGB(0, 0, 0), 0.6)
    local mark = ui.frame(r, UDim2.new(0, 3, 1, 0), nil, teamColor("atk"), 0)
    local nm = shadow(ui.label(r, "", UDim2.new(1, -86, 1, 0), UDim2.fromOffset(10, 0), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left), 0.8)
    nm.TextTruncate = Enum.TextTruncate.AtEnd
    local hb = ui.frame(r, UDim2.fromOffset(64, 3), UDim2.new(1, -8, 0.5, 0), WHITE, 0.8, V2(1, 0.5))
    local hf = ui.frame(hb, UDim2.fromScale(1, 1), nil, WHITE, 0)
    local dead = shadow(ui.label(r, "", UDim2.fromOffset(64, 22), UDim2.new(1, -8, 0, 0), 12, RGB(230, 90, 80), Enum.Font.GothamBold, V2(1, 0), Enum.TextXAlignment.Right), 0.8)
    rows[i] = { f = r, mark = mark, nm = nm, hb = hb, hf = hf, dead = dead }
  end

  ---------------------------------------------------------------- 右下武器、弹药

  local wp = ui.frame(P.hud, UDim2.fromOffset(280, 66), mobile and UDim2.new(1, -260, 1, -30) or UDim2.new(1, -24, 1, -18), RGB(0, 0, 0), 1, V2(1, 1))   -- 手机：让开右下的开火按钮
  wp.Name = "Weapon"
  local wName = shadow(ui.label(wp, "", UDim2.new(1, 0, 0, 18), nil, 14, MUTE, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Right))
  local wMag = shadow(ui.label(wp, "", UDim2.fromOffset(120, 44), UDim2.new(1, -66, 1, 0), 40, WHITE, NUM, V2(1, 1), Enum.TextXAlignment.Right), 0.5)
  local wRes = shadow(ui.label(wp, "", UDim2.fromOffset(64, 26), UDim2.new(1, 0, 1, -6), 20, MUTE, NUM, V2(1, 1), Enum.TextXAlignment.Left), 0.6)
  local wLine = ui.frame(wp, UDim2.fromOffset(150, 1), UDim2.new(1, 0, 0, 21), WHITE, 0.6, V2(1, 0))

  ---------------------------------------------------------------- 每帧

  local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%02d:%02d", s // 60, s % 60)
  end
  local sqT, gT = 0, 0
  local function squadOf(team)
    local list = {}
    for _, pl in ipairs(Players:GetPlayers()) do
      if pl:GetAttribute("Side") == team then table.insert(list, pl) end
    end
    table.sort(list, function(a, b) return a.UserId < b.UserId end)
    local idx = table.find(list, me) or 1
    local g = (idx - 1) // 5
    local out = {}
    for i = g * 5 + 1, math.min(#list, g * 5 + 5) do table.insert(out, list[i]) end
    return out, g + 1
  end

  function G.stepHud(dt)
    local S = G.S
    if not S or not P.hud.Visible then
      for _, m in pairs(marks) do m.bb.Enabled = false end
      return
    end
    local mine = S.team or "atk"
    local foe = other(mine)
    local pts = S.points or {}
    -- 比分：手里的据点数
    local held = { atk = 0, def = 0 }
    for _, s in ipairs(pts) do held[s.owner] = (held[s.owner] or 0) + 1 end
    local n = math.max(1, #pts)
    for sx, t in pairs({ [-1] = mine, [1] = foe }) do
      local s = sides[sx]
      local c = teamColor(t)
      s.name.Text = T("hud." .. t)
      s.name.TextColor3 = c:Lerp(WHITE, 0.25)
      s.bar.BackgroundColor3 = c
      s.bar.Size = UDim2.fromScale((held[t] or 0) / n, 1)
      s.score.Text = tostring(held[t] or 0)
      s.arrow.TextColor3 = c
    end
    if S.phase == "prep" then timer.Text = T("hud.prep") .. " " .. math.max(0, S.left or 0)
    elseif S.ot then timer.Text = T("hud.ot") .. " " .. fmtTime(S.ot)
    else timer.Text = fmtTime(S.left) end
    local t = os.clock()
    for _, s in ipairs(pts) do
      local d = diamonds[s.id]
      if d then
        local c = teamColor(s.owner)
        d.d.BackgroundColor3 = c
        d.d.BackgroundTransparency = s.locked and 0.55 or 0.12
        local fight = (s.atk or 0) > 0 and (s.def or 0) > 0
        d.st.Transparency = fight and (0.1 + 0.5 * (0.5 + 0.5 * math.sin(t * 8))) or 0.25
        local pr = (not s.locked and s.owner == "def") and (s.prog or 0) or 0
        d.pb.Visible = pr > 0
        d.pf.Size = UDim2.fromScale(pr, 1)
        d.l.TextTransparency = s.locked and 0.4 or 0
      end
    end
    -- 世界里的据点：没拿下的才标；开着镜、开着车也标（AlwaysOnTop）
    gT -= dt
    local cam = workspace.CurrentCamera
    local cp = cam.CFrame.Position
    for _, s in ipairs(pts) do
      local m = marks[s.id]
      if m then
        if not m.ok and gT <= 0 and m.tries < 30 then
          m.tries += 1
          ground(m)
        end
        local on = not s.locked and not G.scopeOn
        m.bb.Enabled = on
        if on then
          m.d.BackgroundColor3 = teamColor(s.owner)
          local dd = (Vector3.new(m.x, cp.Y, m.z) - cp).Magnitude
          m.dist.Text = math.floor(dd / M_PER + 0.5) .. "m"
        end
      end
    end
    if gT <= 0 then gT = 2 end
    -- 小地图：跟着人走、北朝上
    local root = G.mapRoot
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if root and root.Parent == box and G.mapUV then
      local pos = hrp and hrp.Position or cp
      local u, v = G.mapUV(pos.X, pos.Z)
      root.AnchorPoint = V2(0, 0)
      root.Size = UDim2.fromOffset(ZOOM, ZOOM)
      root.Position = UDim2.new(0.5, -u * ZOOM, 0.5, -v * ZOOM)
      root.BackgroundTransparency = 0.3   -- 海半透明，看得见后面的战场（部署界面的大地图照旧不透明）
    elseif root and root.BackgroundTransparency ~= 0 then
      root.BackgroundTransparency = 0
    end
    local lv = cam.CFrame.LookVector
    local hdg = (math.deg(math.atan2(lv.X, -lv.Z)) + 360) % 360   -- 北 = −Z（地图上方）
    heading.Text = string.format("%03d", math.floor(hdg + 0.5) % 360)
    arrow.Rotation = hdg
    -- 小队（0.25 秒一次）
    sqT -= dt
    if sqT <= 0 and not mobile then
      sqT = 0.25
      local list, gi = squadOf(mine)
      sqHead.Text = T("hud.squad", T("hud.squad." .. math.clamp(gi, 1, 8))) .. "   " .. #list .. "/5"
      sqHead.TextColor3 = teamColor(mine):Lerp(WHITE, 0.35)
      sqLine.BackgroundColor3 = teamColor(mine)
      for i, r in ipairs(rows) do
        local pl = list[i]
        r.f.Visible = pl ~= nil
        if pl then
          local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
          local k = hum and math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1) or 0
          local alive = hum ~= nil and hum.Health > 0
          r.nm.Text = pl.DisplayName
          r.nm.TextColor3 = (pl == me) and WHITE or TEXT:Lerp(teamColor(mine), 0.25)
          r.nm.Font = (pl == me) and Enum.Font.GothamBold or Enum.Font.GothamMedium
          r.mark.BackgroundColor3 = teamColor(mine)
          r.mark.Visible = pl == me
          r.f.BackgroundTransparency = (pl == me) and 0.45 or 0.65
          r.hb.Visible = alive
          r.hf.Size = UDim2.fromScale(k, 1)
          r.hf.BackgroundColor3 = (k > 0.35) and WHITE or RGB(235, 90, 70)
          r.dead.Text = alive and "" or T("hud.dead")
        end
      end
    end
    -- 武器、弹药
    local id, a = nil, nil
    if G.weaponNow then id, a = G.weaponNow() end
    local w = id and W[id]
    wp.Visible = w ~= nil and not G.drive
    if w then
      local name = T("weapon." .. id)
      if w.kind == "gun" then name = name .. "  [" .. T(w.auto and "hud.auto" or "hud.semi") .. "]" end
      wName.Text = name
      if w.kind == "heal" or w.kind == "repair" or w.kind == "spot" or w.kind == "breach" then
        wMag.Text, wRes.Text = "", ""
      elseif a and a.r and a.r > 0 then
        wMag.Text, wRes.Text = "", ""
        wName.Text = name .. "  ·  " .. T("hud.reload")
      elseif a then
        wMag.Text = string.format("%03d", a.n or 0)
        wRes.Text = "/" .. (a.res and string.format("%03d", a.res) or "∞")
        wMag.TextColor3 = ((a.n or 0) == 0) and RGB(235, 90, 70) or WHITE
      end
    end
  end
end

return Hud
