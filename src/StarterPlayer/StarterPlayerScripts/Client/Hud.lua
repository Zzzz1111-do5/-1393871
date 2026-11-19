-- Roblox全面大战场（客户端）——战斗中的界面，照用户给的截图做，要比截图更精致、更简洁（用户：现在这个太卡通）：
--   顶部：四角括号框住比分——两头小字队名、队色大数字（手里的据点数）、细线，中间时间、下面小字模式；再下面 A～E 小菱形
--     （自己队的描边、对面的实心、正在被占的下面一道细进度线、争夺中描边闪）。部署界面也显示
--   世界里的据点：字母 + 距离（米），隔着东西也看得见
--   左下：方形小地图（跟着人走、北朝上），右上角镜头朝向读数；小地图右边是小队（同队真人按 UserId 每 5 人一队：阿尔法 / 布拉沃…；名字 + 细血条）
--   右下：武器名 + 射击方式，弹药「028/900」（前面补的 0 暗一点）
--   第一次出生：屏幕上方一块「目标与据点」说明（4 页，回车下一页、退格关掉）
--   UI.lua 原来的顶栏、血条、兵种字，Play.lua 原来的弹药字交给这里：挪进一个关着的 ScreenGui（照样刷新，只是不画）；小地图框挪到左下
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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
  local TEXT, MUTE, FAINT = RGB(232, 236, 238), RGB(160, 166, 170), RGB(110, 116, 120)
  local NUM = Enum.Font.Jura   -- 细的数字（弹药、距离、朝向）
  local M_PER = 2.8            -- 1 米多少格（同 AirDefs.M）
  local function T(k, ...) return G.T(k, ...) end
  local function teamColor(t) return Config.Teams[t or "atk"].color end
  local function other(t) return (t == "atk") and "def" or "atk" end
  local function hex(c) return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
  local function txt(parent, s, size, pos, ts, color, font, anchor, align, stroke)
    local l = ui.label(parent, s, size, pos, ts, color, font, anchor, align)
    l.TextWrapped = false
    l.TextStrokeTransparency = stroke or 0.75
    l.TextStrokeColor3 = Color3.new(0, 0, 0)
    return l
  end
  local function line(parent, size, pos, color, alpha, anchor) return ui.frame(parent, size, pos, color or WHITE, alpha or 0, anchor) end
  local mobile = G.mobile == true
  local reducedMotion = false
  pcall(function()
    local function syncMotion() reducedMotion = GuiService.ReducedMotionEnabled end
    syncMotion()
    GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(syncMotion)
  end)

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

  ---------------------------------------------------------------- 顶部比分

  local BW, BH = mobile and 470 or 600, mobile and 62 or 72
  local top = ui.frame(G.gui, UDim2.fromOffset(BW, BH), UDim2.new(0.5, 0, 0, mobile and 4 or 10), RGB(8, 17, 24), 0.3, V2(0.5, 0))
  top.Name = "ScoreBar"
  top.ZIndex = 12
  for _, a in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do   -- 四角括号
    line(top, UDim2.fromOffset(14, 1), UDim2.fromScale(a[1], a[2]), WHITE, 0.25, V2(a[1], a[2]))
    line(top, UDim2.fromOffset(1, 14), UDim2.fromScale(a[1], a[2]), WHITE, 0.25, V2(a[1], a[2]))
  end
  local sides = {}
  for _, sx in ipairs({ -1, 1 }) do
    local left = sx < 0
    local s = {}
    s.name = txt(top, "", UDim2.fromOffset(70, 14), UDim2.new(0.5, sx * (BW / 2 - 18), 0, 17), 10, MUTE, Enum.Font.GothamMedium, V2(left and 0 or 1, 0.5),
      left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right)
    s.name.TextTruncate = Enum.TextTruncate.AtEnd
    s.score = txt(top, "", UDim2.fromOffset(44, 26), UDim2.new(0.5, sx * (BW / 2 - (mobile and 84 or 96)), 0, 17), mobile and 20 or 24, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5))
    local lw = mobile and 70 or 120
    s.barBg = line(top, UDim2.fromOffset(lw, 1), UDim2.new(0.5, sx * (46 + lw / 2), 0, 17), WHITE, 0.82, V2(0.5, 0.5))
    s.bar = line(s.barBg, UDim2.new(0, 0, 0, 2), UDim2.fromScale(left and 1 or 0, 0.5), WHITE, 0, V2(left and 1 or 0, 0.5))   -- 从时间那头往外长
    sides[sx] = s
  end
  local timer = txt(top, "", UDim2.fromOffset(84, 24), UDim2.new(0.5, 0, 0, 16), mobile and 17 or 20, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5))
  local mode = txt(top, "", UDim2.fromOffset(170, 12), UDim2.new(0.5, 0, 0, 31), 9, MUTE, Enum.Font.GothamMedium, V2(0.5, 0.5))
  mode.TextTruncate = Enum.TextTruncate.AtEnd
  -- 比分条下面一行：现在该干什么（进攻 / 防守哪个据点，用户：玩法不够清晰）
  local goal = txt(top, "", UDim2.fromOffset(BW, 18), UDim2.new(0.5, 0, 1, mobile and 4 or 8), mobile and 12 or 14, TEXT, Enum.Font.GothamBold, V2(0.5, 0), nil, 0.5)
  goal.RichText = true
  goal.Size = UDim2.new(1, -8, 0, 18)
  goal.TextTruncate = Enum.TextTruncate.AtEnd
  -- A～E 小菱形
  local diamonds = {}
  for i, p in ipairs(Map.POINTS) do
    local cx = (i - (#Map.POINTS + 1) / 2) * (mobile and 30 or 34)
    local d = ui.frame(top, UDim2.fromOffset(13, 13), UDim2.new(0.5, cx, 0, BH - 20), WHITE, 1, V2(0.5, 0.5))
    d.Rotation = 45
    local st = ui.stroke(d, WHITE, 1, 0.15)
    local l = txt(top, p.id, UDim2.fromOffset(14, 14), UDim2.new(0.5, cx, 0, BH - 20), 8, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5), nil, 1)
    local pb = line(top, UDim2.fromOffset(18, 1), UDim2.new(0.5, cx, 0, BH - 8), WHITE, 0.82, V2(0.5, 0))
    local pf = line(pb, UDim2.fromScale(0, 1), nil, WHITE, 0)
    diamonds[p.id] = { d = d, st = st, l = l, pb = pb, pf = pf }
  end

  ---------------------------------------------------------------- 世界里的据点：字母 + 距离

  local pg = me:WaitForChild("PlayerGui")
  local marks = {}
  for _, p in ipairs(Map.POINTS) do
    local a = Instance.new("Part")
    a.Name = "Obj_" .. p.id
    a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.CastShadow = true, false, false, false, false
    a.Transparency = 1
    a.Size = Vector3.new(1, 1, 1)
    a.CFrame = CFrame.new(p.x, (p.y or 40) + 30, p.z)
    a.Parent = workspace.CurrentCamera   -- 只在自己这儿
    local bb = Instance.new("BillboardGui")
    bb.Name = "ObjMark_" .. p.id
    bb.Adornee = a
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Size = UDim2.fromOffset(80, 56)
    bb.ResetOnSpawn = false
    bb.Parent = pg
    local verb = txt(bb, "", UDim2.fromOffset(80, 13), UDim2.fromScale(0.5, 0), 10, TEXT, Enum.Font.GothamBold, V2(0.5, 0), nil, 0.5)   -- 进攻 / 防守
    local l = txt(bb, p.id, UDim2.fromOffset(40, 24), UDim2.new(0.5, 0, 0, 13), 20, WHITE, Enum.Font.GothamBold, V2(0.5, 0), nil, 0.55)
    local dist = txt(bb, "", UDim2.fromOffset(60, 14), UDim2.new(0.5, 0, 0, 37), 11, TEXT, NUM, V2(0.5, 0), nil, 0.55)
    marks[p.id] = { part = a, bb = bb, l = l, dist = dist, verb = verb, ok = p.y ~= nil, tries = 0, x = p.x, z = p.z }
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

  ---------------------------------------------------------------- 右上方形小地图（用户：右上角加个正方形小地图，不要那根绕圈转的扫描线；11-19：不要黑绿，改成正常的）
  --   方框（UI.lua 建的 CanvasGroup 裁边）里是正常颜色的地图（北朝上、跟着人走）：有 EditableImage 时是 MapPaint 画的卫星图
  --   （暗淡、拟真：水深、沙滩、草地、土路、岩石、山体阴影，身边每像素 6.25 格），没有就是 MapUI 的「mini」色块，
  --   淡淡的白网格、四角的取景框、白边；亮点：友军蓝、敌军红；步兵圆点、车和船方块、飞机菱形；敌人开枪的地方闪一个红圈
  --   哪些敌人上雷达见 Config.Radar（车船飞机在范围内就有；步兵要在视线里、开了枪或者被标记）
  --   手机：右边一列是开火、换枪、夜视、战术平板的按钮，小地图还放左上

  local RC = Config.Radar or { range = 520, ping = 3 }
  local LINE, LINE_DIM = RGB(244, 246, 248), RGB(214, 220, 226)   -- 框、网格、字：白（原来是雷达绿）
  local FRIEND, FOE = RGB(72, 168, 255), RGB(255, 64, 52)
  local MS = mobile and 122 or 216   -- 手机：左上，往下是开车的方向键，小一点免得压着
  local box = P.miniBox
  box.AnchorPoint = mobile and V2(0, 0) or V2(1, 0)
  box.Position = mobile and UDim2.new(0, 16, 0, 118) or UDim2.new(1, -18, 0, 18)
  box.Size = UDim2.fromOffset(MS, MS)
  box.BackgroundColor3 = RGB(22, 36, 50)   -- 地图外面也是深海的蓝
  box.BackgroundTransparency = 0.12
  do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = box
  end
  ui.stroke(box, LINE, 1.5, 0.35)
  local hudLayout = { radarRight = not mobile, radarX = mobile and 16 or 18, radarY = mobile and 118 or 18, radarSize = MS }
  G.hudLayout = hudLayout
  local scoreViewport, scoreRight, compactScore
  local function layoutScore(viewport)
    local edge = 12
    local right = hudLayout.radarRight and (hudLayout.radarX + hudLayout.radarSize + edge) or edge
    if mobile and viewport.Y < 360 and viewport.X > viewport.Y then right = G.infantryTouchWidth or 164 end
    if (scoreViewport == viewport.X and scoreRight == right) or viewport.X < 1 then return end
    scoreViewport, scoreRight = viewport.X, right
    local width = math.max(1, math.min(BW, viewport.X - edge - right))
    local center = math.max(edge + width / 2, math.min(viewport.X / 2, viewport.X - right - width / 2))
    compactScore = width < 440
    top.Size = UDim2.fromOffset(width, BH)
    top.Position = UDim2.fromOffset(center, mobile and 4 or 10)
    for _, sx in ipairs({ -1, 1 }) do
      local s = sides[sx]
      local scale = sx < 0 and 0 or 1
      if compactScore then
        s.name.Size = UDim2.fromOffset(math.clamp((width - 100) / 2 - 10, 0, 70), 14)
        s.name.Position = UDim2.new(scale, -sx * 10, 0, 11)
        s.score.Position = UDim2.new(scale, -sx * 32, 0, 31)
        s.barBg.Visible = false
      else
        s.name.Size = UDim2.fromOffset(70, 14)
        s.name.Position = UDim2.new(scale, -sx * 14, 0, 17)
        s.score.Position = UDim2.new(scale, -sx * 110, 0, 17)
        local railWidth = math.min(mobile and 70 or 120, width / 2 - 188)
        s.barBg.Size = UDim2.fromOffset(railWidth, 1)
        s.barBg.Position = UDim2.new(0.5, sx * (46 + railWidth / 2), 0, 17)
        s.barBg.Visible = true
      end
    end
    mode.Size = UDim2.fromOffset(math.max(1, math.min(170, width - 142)), 12)
    hudLayout.scoreBottom = top.Position.Y.Offset + BH + goal.Position.Y.Offset + goal.Size.Y.Offset
  end
  -- 坦克瞄准镜的目镜黑框（Drive，DisplayOrder 5）会盖住半个小地图：开镜时小地图挪到上面一层（像战雷，瞄准镜里也看得到小地图）
  local radarTop = Instance.new("ScreenGui")
  radarTop.Name = "RadarTop"
  radarTop.ResetOnSpawn = false
  radarTop.IgnoreGuiInset = true
  radarTop.DisplayOrder = 7
  radarTop.Parent = me:WaitForChild("PlayerGui")
  if P.feed and not mobile then P.feed.Position = UDim2.new(1, -16, 0, 18 + MS + 14) end
  -- 雷达范围跟着坐的东西变（用户：飞机的雷达有点近）：步兵 RC.range，地面载具 RC.veh，直升机 RC.heli，固定翼 RC.jet；换的时候慢慢缩放
  local curR = RC.range
  local function wantRange()
    local f = G.fly
    if f and f.d then return (f.d.kind == "jet") and (RC.jet or 9000) or (RC.heli or 4000) end
    if G.drive then return RC.veh or 900 end
    return RC.range
  end
  local MAPW = 6100 * ((G.Map and G.Map.K) or 1)   -- 整张地图（6100 × K 格见方，MapUI；地图放大了 K 倍）：画多大让半边正好是雷达范围
  -- 网格：横竖各三道淡线（四等分），中间两道稍亮；四个角上一对短线的取景框
  for i = 1, 3 do
    local k = i / 4
    local a = (i == 2) and 0.82 or 0.9
    local lv = line(box, UDim2.new(0, 1, 1, 0), UDim2.fromScale(k, 0.5), LINE, a, V2(0.5, 0.5))
    lv.ZIndex = 18
    local lh = line(box, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0.5, k), LINE, a, V2(0.5, 0.5))
    lh.ZIndex = 18
  end
  for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local ax = V2(c[1], c[2])
    local h = line(box, UDim2.fromOffset(12, 2), UDim2.new(c[1], c[1] == 0 and 4 or -4, c[2], c[2] == 0 and 4 or -4), LINE, 0.25, ax)
    local v = line(box, UDim2.fromOffset(2, 12), UDim2.new(c[1], c[1] == 0 and 4 or -4, c[2], c[2] == 0 and 4 or -4), LINE, 0.25, ax)
    h.ZIndex, v.ZIndex = 22, 22
  end
  local blipLayer = ui.frame(box, UDim2.fromScale(1, 1), nil, WHITE, 1)
  blipLayer.ZIndex = 20
  local arrow = txt(box, "▲", UDim2.fromOffset(14, 14), UDim2.fromScale(0.5, 0.5), 11, WHITE, Enum.Font.GothamBold, V2(0.5, 0.5), nil, 0.3)
  arrow.ZIndex = 22
  local north = txt(box, "N", UDim2.fromOffset(14, 14), UDim2.new(0.5, 0, 0, 4), 10, LINE, Enum.Font.GothamBold, V2(0.5, 0), nil, 0.5)
  north.ZIndex = 22
  local heading = txt(box, "", UDim2.fromOffset(44, 14), UDim2.new(0.5, 0, 1, -4), 11, LINE, NUM, V2(0.5, 1), nil, 0.4)
  heading.ZIndex = 22
  local rangeL = txt(box, math.floor(RC.range / M_PER + 0.5) .. "m", UDim2.fromOffset(52, 12), UDim2.new(1, -8, 1, -6), 9, LINE_DIM, NUM, V2(1, 1), Enum.TextXAlignment.Right, 0.6)
  rangeL.ZIndex = 22

  -- 亮点（对象池）：kind inf 圆点 / veh 方块 / air 菱形 / ping 红圈
  local pool, used = {}, 0
  local function blip()
    used += 1
    local b = pool[used]
    if not b then
      local f = Instance.new("Frame")
      f.AnchorPoint = V2(0.5, 0.5)
      f.BorderSizePixel = 0
      f.ZIndex = 21
      f.Parent = blipLayer
      local c = Instance.new("UICorner")
      c.Parent = f
      local st = Instance.new("UIStroke")
      st.Thickness = 1
      st.Parent = f
      b = { f = f, c = c, st = st }
      pool[used] = b
    end
    b.f.Visible = true
    return b
  end
  local function shape(b, kind, col, alpha)
    local f = b.f
    if kind == "ping" then
      f.Size = UDim2.fromOffset(12, 12)
      f.Rotation = 0
      b.c.CornerRadius = UDim.new(0.5, 0)
      f.BackgroundTransparency = 1
      b.st.Color, b.st.Transparency, b.st.Thickness = col, alpha, 1.5
      return
    end
    local sz = (kind == "inf") and 5 or 7
    f.Size = UDim2.fromOffset(sz, sz)
    f.Rotation = (kind == "air") and 45 or 0
    b.c.CornerRadius = (kind == "inf") and UDim.new(0.5, 0) or UDim.new(0, 1)
    f.BackgroundColor3, f.BackgroundTransparency = col, alpha
    b.st.Color, b.st.Transparency, b.st.Thickness = Color3.new(0, 0, 0), 0.4 + alpha * 0.6, 1
  end

  -- 雷达里的东西：真人（角色带 Team）、实体（workspace.Ents：机器人、车、飞机、船；工事、地雷不上雷达）
  local CAT = { inf = "inf", light = "veh", armor = "veh", ship = "veh", air = "air" }
  local contacts = {}      -- { pos, team, kind, model }
  local seenT = {}         -- 敌人 → 最近一次看见（视线里）的时刻
  local losT = {}          -- 敌人 → 下次查视线的时刻
  local pings = {}         -- 敌人开枪的地方：{ pos, t }
  local rayP = RaycastParams.new()
  rayP.FilterType = Enum.RaycastFilterType.Exclude
  local scanT, purgeT = 0, 5
  local function myEnt(m)
    local d = G.drive
    if d and d.em == m then return true end
    local uid = me.UserId
    return m:GetAttribute("Driver") == uid or m:GetAttribute("Pilot") == uid or m:GetAttribute("Gunner") == uid
  end
  local function scan(center, mine)
    table.clear(contacts)
    local R = curR * 1.04   -- 方框：横竖各在半边宽以内（角上比边上远）
    local function add(pos, team, kind, model)
      local dx, dz = pos.X - center.X, pos.Z - center.Z
      if math.abs(dx) <= R and math.abs(dz) <= R then table.insert(contacts, { pos = pos, team = team, kind = kind, model = model }) end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
      local ch = pl.Character
      local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
      local hum = ch and ch:FindFirstChildOfClass("Humanoid")
      if pl ~= me and hrp and hum and hum.Health > 0 then
        add(hrp.CFrame.Position, ch:GetAttribute("Team") or pl:GetAttribute("Side"), "inf", ch)
      end
    end
    local ents = workspace:FindFirstChild("Ents")
    for _, m in ipairs(ents and ents:GetChildren() or {}) do
      local kind = CAT[m:GetAttribute("Cat") or ""]
      local root = m.PrimaryPart or m:FindFirstChild("Root")
      if kind and root and not m:GetAttribute("Wreck") and (m:GetAttribute("Hp") or 1) > 0 and not myEnt(m) then
        add(root.CFrame.Position, m:GetAttribute("Team"), kind, m)
      end
    end
  end
  -- 敌人看不看得见：从镜头往它身上打一条线，先打到它自己（或者比它远的东西）就算看见
  local function visible(c, from)
    local to = c.pos + Vector3.new(0, 1.5, 0)
    local d = to - from
    local ex = { me.Character }
    if G.drive and G.drive.em then table.insert(ex, G.drive.em) end
    rayP.FilterDescendantsInstances = ex
    local hit = workspace:Raycast(from, d, rayP)
    return (not hit) or (c.model and hit.Instance:IsDescendantOf(c.model)) or (hit.Position - from).Magnitude > d.Magnitude - 3
  end
  -- 服务器发的开枪特效（Fx.lua）：敌人没消音的枪 → 雷达上开枪的地方闪一个红圈
  function G.radarShot(pos, team, quiet)
    if quiet or not pos or not team or team == me:GetAttribute("Side") then return end
    table.insert(pings, { pos = pos, t = os.clock() })
    if #pings > 40 then table.remove(pings, 1) end
  end
  G.radarContacts = function() return contacts end   -- 测试用
  G.radarShown = {}                                   -- 测试用：这一帧画出来的 { team, kind, enemy }

  ---------------------------------------------------------------- 小队（小地图右边）

  local squad = ui.frame(P.hud, UDim2.fromOffset(250, 150), UDim2.new(0, 22, 1, -18), RGB(0, 0, 0), 1, V2(0, 1))   -- 左下角（小地图搬到右上了）
  squad.Name = "Squad"
  squad.Visible = not mobile
  local sqHead = txt(squad, "", UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 0), 13, WHITE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left, 0.6)
  local rows = {}
  for i = 1, 5 do
    local y = 24 + (i - 1) * 25
    local mark = ui.frame(squad, UDim2.fromOffset(6, 6), UDim2.fromOffset(4, y + 7), teamColor("atk"), 0, V2(0.5, 0.5))
    mark.Rotation = 45
    local nm = txt(squad, "", UDim2.fromOffset(200, 16), UDim2.fromOffset(16, y), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left, 0.7)
    nm.TextTruncate = Enum.TextTruncate.AtEnd
    local hb = line(squad, UDim2.fromOffset(170, 1), UDim2.fromOffset(16, y + 18), WHITE, 0.82)
    local hf = line(hb, UDim2.new(1, 0, 0, 2), UDim2.fromScale(0, 0.5), WHITE, 0, V2(0, 0.5))
    local dead = txt(squad, "", UDim2.fromOffset(60, 16), UDim2.fromOffset(196, y), 11, RGB(230, 96, 84), Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left, 0.7)
    rows[i] = { mark = mark, nm = nm, hb = hb, hf = hf, dead = dead }
  end

  ---------------------------------------------------------------- 右下武器、弹药

  local wp = ui.frame(P.hud, UDim2.fromOffset(280, 64), mobile and UDim2.new(1, -260, 1, -62) or UDim2.new(1, -28, 1, -16), RGB(0, 0, 0), 1, V2(1, 1))   -- 手机：让开右下的开火按钮、下面的武器栏
  wp.Name = "Weapon"
  local wName = txt(wp, "", UDim2.new(1, 0, 0, 18), nil, 15, TEXT, NUM, nil, Enum.TextXAlignment.Right, 0.7)
  local wAmmo = txt(wp, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, 0), 36, WHITE, NUM, V2(0, 1), Enum.TextXAlignment.Right, 0.6)
  wAmmo.RichText = true

  ---------------------------------------------------------------- 目标说明（第一次出生时）

  local tipW = mobile and 330 or 500
  local tip = ui.frame(P.hud, UDim2.fromOffset(tipW, 168), UDim2.new(mobile and 0.42 or 0.5, 0, 0, BH + (mobile and 10 or 24)), RGB(8, 10, 12), 0.12, V2(0.5, 0))   -- 手机：让开右边的按钮
  tip.Name = "Tips"
  tip.Visible = false
  local tipTitle = txt(tip, "", UDim2.new(1, -120, 0, 20), UDim2.fromOffset(20, 16), 16, WHITE, Enum.Font.GothamBold, nil, Enum.TextXAlignment.Left, 1)
  local tipPage = txt(tip, "", UDim2.fromOffset(80, 16), UDim2.new(1, -20, 0, 18), 11, MUTE, Enum.Font.GothamMedium, V2(1, 0), Enum.TextXAlignment.Right, 1)
  local NT = 4
  local segs = {}
  for k = 1, NT do
    segs[k] = line(tip, UDim2.new(1 / NT, -3, 0, 2), UDim2.new((k - 1) / NT, 0, 0, 48), WHITE, 0.8)
  end
  local tipBody = ui.label(tip, "", UDim2.new(1, -40, 0, 54), UDim2.fromOffset(20, 60), 13, TEXT, Enum.Font.GothamMedium, nil, Enum.TextXAlignment.Left)
  tipBody.TextYAlignment = Enum.TextYAlignment.Top
  line(tip, UDim2.new(1, -40, 0, 1), UDim2.new(0, 20, 1, -46), WHITE, 0.88)
  local function keyChip(parent, x, anchorX)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(120, 26)
    b.Position = UDim2.new(anchorX, x, 1, -14)
    b.AnchorPoint = V2(anchorX, 1)
    b.BackgroundTransparency = 1
    b.Text = ""
    b.Parent = parent
    local k = ui.frame(b, UDim2.fromOffset(46, 20), UDim2.new(anchorX, 0, 0.5, 0), RGB(40, 44, 48), 0.2, V2(anchorX, 0.5))
    local kl = txt(k, "", UDim2.fromScale(1, 1), nil, 9, TEXT, Enum.Font.GothamBold, nil, nil, 1)
    local wl = txt(b, "", UDim2.fromOffset(66, 20), UDim2.new(anchorX, (anchorX == 0) and 54 or -54, 0.5, 0), 12, TEXT, Enum.Font.GothamMedium, V2(anchorX, 0.5),
      (anchorX == 0) and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, 1)
    return b, kl, wl
  end
  local closeB, closeK, closeW = keyChip(tip, 20, 0)
  local nextB, nextK, nextW = keyChip(tip, -20, 1)
  local tipI, tipDone = 1, false
  local function tipText(i)
    if i == 1 then return T("faction." .. ((G.S and G.S.team) or "atk") .. ".desc") end
    return T("hud.tip." .. i)
  end
  local function showTip()
    tipTitle.Text = T("hud.tip.title")
    tipPage.Text = T("hud.tip.page", tipI, NT)
    tipBody.Text = tipText(tipI)
    for k, s in ipairs(segs) do s.BackgroundTransparency = (k <= tipI) and 0 or 0.8 end
    closeK.Text, closeW.Text = T("hud.key.back"), T("hud.tip.close")
    nextK.Text, nextW.Text = T("hud.key.enter"), (tipI < NT) and T("hud.tip.next") or T("hud.tip.close")
  end
  local function closeTip()
    tipDone = true
    tip.Visible = false
  end
  local function nextTip()
    if tipI >= NT then closeTip() return end
    tipI += 1
    showTip()
  end
  closeB.Activated:Connect(closeTip)
  nextB.Activated:Connect(nextTip)
  UIS.InputBegan:Connect(function(io, gp)
    if gp or not tip.Visible then return end
    if io.KeyCode == Enum.KeyCode.Return then nextTip()
    elseif io.KeyCode == Enum.KeyCode.Backspace then closeTip() end
  end)
  local tipT0 = nil

  ---------------------------------------------------------------- 每帧

  local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%02d:%02d", s // 60, s % 60)
  end
  -- 028 / 900：前面补的 0 暗一点
  local function padNum(n, dim)
    local s = string.format("%03d", math.max(0, n))
    local lead = string.match(s, "^0*")
    if #lead == #s then lead = string.sub(s, 1, #s - 1) end
    local rest = string.sub(s, #lead + 1)
    return (#lead > 0 and ('<font color="' .. dim .. '">' .. lead .. "</font>") or "") .. rest
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
    local cam = workspace.CurrentCamera
    if cam then layoutScore(cam.ViewportSize) end
    local S = G.S
    local deployOn = G.menuOpen ~= nil and G.menuOpen() and not (G.hangarOpen and G.hangarOpen())
    -- 比分条：战斗中和部署界面都有；选阵营、结算、开服加载时不显示
    top.Visible = S ~= nil and S.picked ~= false and not G.factionOpen and S.phase ~= "end" and (S.progress or 1) >= 1 and (P.hud.Visible or deployOn)
    if not S or not top.Visible then
      for _, m in pairs(marks) do m.bb.Enabled = false end
      tip.Visible = false
      if not S then return end
    end
    local mine = S.team or "atk"
    local foe = other(mine)
    local pts = S.points or {}
    -- 比分：手里的据点数
    local held = { atk = 0, def = 0 }
    for _, s in ipairs(pts) do held[s.owner] = (held[s.owner] or 0) + 1 end
    local n = math.max(1, #pts)
    -- 分阶段突破：攻方那头是兵力（剩多少、细线按开局的比例），守方那头还是手里的据点数
    local tk = S.tickets
    for sx, t in pairs({ [-1] = mine, [1] = foe }) do
      local s = sides[sx]
      local c = teamColor(t)
      if t == "atk" and tk then
        s.name.Text = T("hud.atk") .. " · " .. T("hud.tickets")
        s.score.Text = tostring(tk)
        s.bar.Size = UDim2.new(math.clamp(tk / math.max(S.ticketsMax or tk, 1), 0, 1), 0, 0, 2)
        s.score.TextColor3 = tk <= 30 and RGB(255, 119, 105) or c:Lerp(WHITE, 0.15)
      else
        s.name.Text = T("hud." .. t)
        s.score.Text = tostring(held[t] or 0)
        s.bar.Size = UDim2.new((held[t] or 0) / n, 0, 0, 2)
        s.score.TextColor3 = c:Lerp(WHITE, 0.15)
      end
      s.bar.BackgroundColor3 = c
    end
    local stg = S.stageId and (T("hud.stage", S.stage or 1, S.stages or 3) .. " · " .. T("stage." .. S.stageId .. ".short")) or T("hud.mode")
    if S.phase == "prep" then
      timer.Text = fmtTime(S.left)
      mode.Text = compactScore and T("hud.prep") or (T("hud.prep") .. " · " .. stg)
    elseif S.ot then timer.Text = fmtTime(S.ot) mode.Text = T("hud.ot")
    else timer.Text = fmtTime(S.left) mode.Text = stg end
    -- 现在的目标：当前阶段开放的据点（侧翼另写）
    local main, flank = {}, {}
    for _, s in ipairs(pts) do
      if s.act and not s.locked then table.insert(s.flank and flank or main, compactScore and s.id or T("point." .. s.id)) end
    end
    local gtext = ""
    if #main > 0 then
      local col = hex(teamColor(mine):Lerp(WHITE, 0.25))
      gtext = '<font color="' .. col .. '">' .. T((mine == "atk") and "hud.goalAtk" or "hud.goalDef") .. "</font>  " .. table.concat(main, "  ·  ")
      if #flank > 0 then gtext ..= '   <font color="#9aa0a6">' .. T("hud.goalFlank", table.concat(flank, "  ·  ")) .. "</font>" end
    end
    goal.Text = gtext
    local t = os.clock()
    for _, s in ipairs(pts) do
      local d = diamonds[s.id]
      if d then
        local ours = s.owner == mine
        local idle = s.act == false and not s.locked   -- 还没轮到的阶段
        d.d.BackgroundColor3 = teamColor(s.owner)
        d.d.BackgroundTransparency = (ours or idle) and 1 or (s.locked and 0.45 or 0.05)
        local fight = (s.atk or 0) > 0 and (s.def or 0) > 0
        d.st.Transparency = fight and (reducedMotion and 0.12 or (0.4 + 0.3 * math.sin(t * 8))) or ((s.locked or idle) and 0.7 or 0.15)
        d.st.Color = ours and WHITE or teamColor(s.owner):Lerp(WHITE, 0.3)
        d.l.TextTransparency = (s.locked or idle) and 0.55 or 0
        local pr = (not s.locked and s.owner == "def") and (s.prog or 0) or 0
        d.pb.Visible = pr > 0
        d.pf.Size = UDim2.fromScale(pr, 1)
        d.pf.BackgroundColor3 = teamColor("atk")
      end
    end
    if not P.hud.Visible or not cam then return end
    -- 世界里的据点：没拿下的才标
    gT -= dt
    local cp = cam.CFrame.Position
    for _, s in ipairs(pts) do
      local m = marks[s.id]
      if m then
        if not m.ok and gT <= 0 and m.tries < 30 then
          m.tries += 1
          ground(m)
        end
        local on = not s.locked and s.act ~= false and not G.scopeOn   -- 只标当前阶段能占的
        m.bb.Enabled = on
        if on then
          m.l.TextColor3 = (s.owner == mine) and WHITE or teamColor(s.owner):Lerp(WHITE, 0.2)
          local dd = (Vector3.new(m.x, cp.Y, m.z) - cp).Magnitude
          m.dist.Text = math.floor(dd / M_PER + 0.5) .. "m"
          m.verb.Text = T((mine == "atk") and "hud.markAtk" or "hud.markDef") .. (s.flank and (" · " .. T("hud.flank")) or "")
          m.verb.TextColor3 = teamColor(mine):Lerp(WHITE, 0.35)
        end
      end
    end
    if gT <= 0 then gT = 2 end
    -- 雷达：跟着人走、北朝上
    local root = G.mapRoot
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.CFrame.Position or cp
    -- 视线从自己的眼睛（开车时从镜头）往外打：第三人称的镜头可能在墙外头
    local head = ch and ch:FindFirstChild("Head")
    local eye = (head and not G.drive) and head.CFrame.Position or cp
    curR += (wantRange() - curR) * math.min(1, dt * 3)
    rangeL.Text = (curR >= 2000 * M_PER) and string.format("%.1fkm", curR / M_PER / 1000) or (math.floor(curR / M_PER + 0.5) .. "m")
    local ZOOM = MAPW * (MS / 2) / curR
    if root and root.Parent == box and G.mapUV then
      if G.mapTheme then G.mapTheme("mini") end
      if G.mapFocus then G.mapFocus(pos.X, pos.Z, curR) end   -- 身边画细节块（MapUI 的卫星图）
      local u, v = G.mapUV(pos.X, pos.Z)
      root.AnchorPoint = V2(0, 0)
      root.Size = UDim2.fromOffset(ZOOM, ZOOM)
      root.Position = UDim2.new(0.5, -u * ZOOM, 0.5, -v * ZOOM)
      root.BackgroundTransparency = 0.1   -- 海稍微透一点（部署界面的大地图照旧不透明）
    elseif root and root.BackgroundTransparency ~= 0 then
      root.BackgroundTransparency = 0
      if G.mapTheme then G.mapTheme("map") end
    end
    local lv = cam.CFrame.LookVector
    local hdg = (math.deg(math.atan2(lv.X, -lv.Z)) + 360) % 360   -- 北 = −Z（地图上方）
    heading.Text = string.format("%03d°", math.floor(hdg + 0.5) % 360)
    arrow.Rotation = hdg
    local now = os.clock()
    do   -- 开着坦克瞄准镜（战况表、战术平板没开）：小地图在目镜黑框上面
      local dv = G.myVeh
      local over = dv ~= nil and dv == G.drive and dv.sight == true
        and not (G.tacOpen and G.tacOpen()) and not (G.boardShown and G.boardShown())
      local want = over and radarTop or P.hud
      if box.Parent ~= want then box.Parent = want end
    end
    -- 亮点：0.1 秒收一次雷达范围里的东西；敌方步兵每个 0.3 秒查一次视线
    scanT -= dt
    local mine = me:GetAttribute("Side")
    if scanT <= 0 then
      scanT = 0.1
      scan(pos, mine)
      purgeT -= 0.1
      if purgeT <= 0 then   -- 阵亡、消失了的模型不留在表里（长时间开着越积越多）
        purgeT = 5
        for mdl in pairs(seenT) do if not mdl.Parent then seenT[mdl] = nil end end
        for mdl in pairs(losT) do if not mdl.Parent then losT[mdl] = nil end end
      end
      for _, c in ipairs(contacts) do
        if c.team ~= mine and c.kind == "inf" and c.model and now >= (losT[c.model] or 0) then
          losT[c.model] = now + 0.3
          if visible(c, eye) then seenT[c.model] = now end
        end
      end
    end
    used = 0
    table.clear(G.radarShown)
    local px = (MS / 2) / curR
    local function place(b, wpos)
      b.f.Position = UDim2.new(0.5, (wpos.X - pos.X) * px, 0.5, (wpos.Z - pos.Z) * px)
    end
    local pulse = 0.08 + 0.14 * (0.5 + 0.5 * math.sin(now * 5))   -- 敌人的亮点轻轻地一明一暗（不靠扫描线也一眼看得到）
    for _, c in ipairs(contacts) do
      local enemy = c.team ~= mine
      local show = not enemy or RC.allEnemies or c.kind ~= "inf" or (c.model and now - (seenT[c.model] or -99) < 2)
      if show then
        local b = blip()
        shape(b, c.kind, enemy and FOE or FRIEND, enemy and pulse or 0.12)
        place(b, c.pos)
        table.insert(G.radarShown, { team = c.team, kind = c.kind, enemy = enemy })
      end
    end
    for i = #pings, 1, -1 do
      local p = pings[i]
      local age = now - p.t
      if age > RC.ping then
        table.remove(pings, i)
      else
        local dx, dz = p.pos.X - pos.X, p.pos.Z - pos.Z
        if math.abs(dx) <= curR and math.abs(dz) <= curR then
          local b = blip()
          shape(b, "ping", FOE, math.clamp(age / RC.ping, 0, 1) * 0.9)
          b.f.Size = UDim2.fromOffset(8 + age * 6, 8 + age * 6)
          place(b, p.pos)
          table.insert(G.radarShown, { team = "ping", kind = "ping", enemy = true })
        end
      end
    end
    for i = used + 1, #pool do pool[i].f.Visible = false end
    -- 小队（0.25 秒一次）
    sqT -= dt
    if sqT <= 0 and not mobile then
      sqT = 0.25
      local list, gi = squadOf(mine)
      sqHead.Text = T("hud.squad", T("hud.squad." .. math.clamp(gi, 1, 8))) .. "  " .. #list .. "/5"
      local tc = teamColor(mine)
      for i, r in ipairs(rows) do
        local pl = list[i]
        local vis = pl ~= nil
        r.mark.Visible, r.nm.Visible, r.hb.Visible, r.dead.Visible = vis, vis, vis, vis
        if pl then
          local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
          local k = hum and math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1) or 0
          local alive = hum ~= nil and hum.Health > 0
          r.nm.Text = string.upper(pl.DisplayName)
          r.nm.TextColor3 = (pl == me) and WHITE or TEXT
          r.nm.Font = (pl == me) and Enum.Font.GothamBold or Enum.Font.GothamMedium
          r.mark.BackgroundColor3 = tc
          r.hb.Visible = alive
          r.hf.Size = UDim2.new(k, 0, 0, 2)
          r.hf.BackgroundColor3 = (k > 0.35) and tc:Lerp(WHITE, 0.2) or RGB(235, 90, 70)
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
      if w.kind == "gun" then name = name .. "    [" .. T(w.auto and "hud.auto" or "hud.semi") .. "]" end
      wName.Text = name
      if w.kind == "heal" or w.kind == "repair" or w.kind == "spot" or w.kind == "breach" then
        wAmmo.Text = ""
      elseif a and a.r and a.r > 0 then
        wAmmo.Text = '<font size="18">' .. T("hud.reload") .. "</font>"
      elseif a then
        wAmmo.TextColor3 = ((a.n or 0) == 0) and RGB(235, 90, 70) or WHITE
        wAmmo.Text = padNum(a.n or 0, hex(FAINT)) .. '<font size="22" color="' .. hex(MUTE) .. '">/' .. (a.res and string.format("%03d", a.res) or "∞") .. "</font>"
      end
    end
    -- 目标说明：第一次出生后过一秒弹出来，一次进服只一次；开着战况表（Tab）时先让开
    local boardOn = G.boardShown ~= nil and G.boardShown()
    if not tipDone and S.alive and S.phase ~= "end" then
      tipT0 = tipT0 or t
      local want = t - tipT0 > 1 and not boardOn and not (G.operationHudVisible and G.operationHudVisible())
      if want and not tip.Visible then
        tip.Visible = true
        showTip()
      elseif not want and tip.Visible then
        tip.Visible = false
      end
    end
  end

  ---------------------------------------------------------------- 重新部署（H，服务器 Round.lua redeploy）：离当前目标多远（格），活着、开战了才算
  function G.objDist()
    local S = G.S
    local char = me.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (S and S.alive and S.phase == "battle" and hrp) then return nil end
    local best = nil
    for _, s in ipairs(S.points or {}) do
      if s.act ~= false and not s.locked then
        for _, p in ipairs(Map.POINTS) do
          if p.id == s.id then
            local pos = hrp.CFrame.Position
            local d = ((p.x - pos.X) ^ 2 + (p.z - pos.Z) ^ 2) ^ 0.5
            if not best or d < best then best = d end
          end
        end
      end
    end
    return best
  end
  UIS.InputBegan:Connect(function(io, gp)
    if gp or io.KeyCode ~= Enum.KeyCode.H then return end
    local S = G.S
    if S and S.alive and S.phase == "battle" then G.R.Act:FireServer("redeploy") end
  end)

  ---------------------------------------------------------------- 压制（Fx.lua 子弹擦身时调 G.suppress）：屏幕四边往里渐暗、微微模糊，两三秒退掉；越近、越密越重
  local vig = {}
  for _, e in ipairs({ { V2(0, 0), UDim2.new(1, 0, 0.32, 0), 90 }, { V2(0, 1), UDim2.new(1, 0, 0.32, 0), -90 },
    { V2(0, 0), UDim2.new(0.26, 0, 1, 0), 0 }, { V2(1, 0), UDim2.new(0.26, 0, 1, 0), 180 } }) do
    local f = ui.frame(G.gui, e[2], UDim2.fromScale(e[1].X, e[1].Y), RGB(0, 0, 0), 1, e[1])
    f.Name = "Suppress"
    f.ZIndex = 1
    f.BackgroundTransparency = 0
    local g = Instance.new("UIGradient")
    g.Rotation = e[3]
    g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
    g.Parent = f
    f.Visible = false
    table.insert(vig, f)
  end
  local blur = Instance.new("BlurEffect")
  blur.Name = "SuppressBlur"
  blur.Size = 0
  blur.Enabled = false
  blur.Parent = workspace.CurrentCamera
  local supp = 0
  function G.suppress(k) supp = math.min(1, supp + (k or 0.3)) end
  G.frameConn("HudFx", function(dt)
    if supp <= 0 and not vig[1].Visible then return end
    supp = math.max(0, supp - dt * 0.45)
    local on = supp > 0.01
    for _, f in ipairs(vig) do
      f.Visible = on
      if on then f.BackgroundTransparency = 1 - supp * 0.85 end
    end
    blur.Enabled = supp > 0.12
    blur.Size = supp * 7
  end)

  ---------------------------------------------------------------- 准星下面弹一行（击杀、占领）：一两秒淡出，新的把旧的往上顶（用户：感受不到激烈对抗）
  local pops = {}
  function G.pop(text, kind)
    local col = (kind == "kill") and RGB(255, 214, 120) or (kind == "ric") and RGB(255, 178, 64) or (kind == "ricIn") and RGB(200, 220, 255) or RGB(140, 230, 160)
    local l = txt(G.gui, text, UDim2.fromOffset(420, 22), UDim2.fromScale(0.5, 0.6), mobile and 15 or 17, col, Enum.Font.GothamBold, V2(0.5, 0.5), nil, 0.45)
    l.ZIndex = 25
    table.insert(pops, 1, l)
    for i, x in ipairs(pops) do
      if x.Parent then x.Position = UDim2.new(0.5, 0, 0.6, -(i - 1) * 24) end
    end
    while #pops > 3 do table.remove(pops):Destroy() end
    task.delay(1.4, function()
      if l.Parent then TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
      task.delay(0.65, function()
        local i = table.find(pops, l)
        if i then table.remove(pops, i) end
        l:Destroy()
      end)
    end)
  end
end

return Hud
