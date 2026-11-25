-- Roblox全面大战场（客户端）——地图方格、标点、无线电（用户 11-25「全部都做」⑭，B 挑刺 13）
--   · 方格：大地图、小地图（同一张 MapUI 的图）上画 A～J（列）/ 1～10（行）的网格，每格左上角小字「C3」；G.gridRef(x, z) → "C3"
--   · I 标点：把准星对着的地方标给全队（服务器 WtMatch.lua 的 G.ACT.wtPing 转发）——地图上一个黄圈、三维里一个黄菱形写「C3 · 谁」，10 秒
--   · O 无线电：小菜单，按数字选一句（需要支援 / 跟我来 / 收到 / 不行 / 撤退 / 这里有敌人 / 进攻、守住最近的据点），全队左边一行字；
--     「需要支援」「这里有敌人」顺手标点。菜单开着时数字键不换弹（Drive.lua 问 G.radioOpen）
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local WtComms = {}

function WtComms.init(G)
  local Map = require(RS:WaitForChild("Map"))
  local me = Players.LocalPlayer
  local RGB, UD2, V2, V3 = Color3.fromRGB, UDim2.new, Vector2.new, Vector3.new
  local function T(k, ...) return G.T and G.T(k, ...) or k end
  local BOLD, MED = Enum.Font.GothamBold, Enum.Font.GothamMedium
  local TH = G.Theme   -- 统一外观（docs/style.md）
  local YEL, WHITE, DIM = TH.C.WARN, TH.C.TEXT, TH.C.MUTE
  local COLS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }

  ---------------------------------------------------------------- 方格
  local function gridRef(x, z)
    if not G.mapUV then return "?" end
    local u, v = G.mapUV(x, z)
    local c = math.clamp(math.floor(u * 10) + 1, 1, 10)
    local r = math.clamp(math.floor(v * 10) + 1, 1, 10)
    return COLS[c] .. r
  end
  G.gridRef = gridRef
  task.spawn(function()
    for _ = 1, 200 do
      if G.mapRoot then break end
      task.wait(0.1)
    end
    local root = G.mapRoot
    if not root then return end
    local layer = Instance.new("Frame")
    layer.Name = "WtGrid"
    layer.Size = UD2(1, 0, 1, 0)
    layer.BackgroundTransparency = 1
    layer.ZIndex = 3
    layer.Parent = root
    for i = 1, 9 do
      for _, vert in ipairs({ true, false }) do
        local l = Instance.new("Frame")
        l.BorderSizePixel = 0
        l.BackgroundColor3 = RGB(255, 255, 255)
        l.BackgroundTransparency = 0.82
        l.Size = vert and UD2(0, 1, 1, 0) or UD2(1, 0, 0, 1)
        l.Position = vert and UD2(i / 10, 0, 0, 0) or UD2(0, 0, i / 10, 0)
        l.ZIndex = 3
        l.Parent = layer
      end
    end
    for c = 1, 10 do
      for r = 1, 10 do
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UD2(0.1, -4, 0, 12)
        t.Position = UD2((c - 1) / 10, 3, (r - 1) / 10, 2)
        t.Text = COLS[c] .. r
        t.TextSize, t.Font = 10, MED
        t.TextColor3, t.TextTransparency = WHITE, 0.45
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.ZIndex = 3
        t.Parent = layer
      end
    end
  end)

  ---------------------------------------------------------------- 左边一列：无线电、标点的话（8 秒）
  local gui = Instance.new("ScreenGui")
  gui.Name = "WtComms"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 7
  gui.Parent = me:WaitForChild("PlayerGui")
  local lines = {}
  local box = Instance.new("Frame")
  box.Name = "RadioLog"
  box.BackgroundTransparency = 1
  box.Size = UDim2.fromOffset(420, 5 * 22)
  box.Position = UD2(0, 16, 0.42, 0)
  box.Parent = gui
  local rows = {}
  for i = 1, 5 do
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UD2(1, 0, 0, 20)
    l.Position = UD2(0, 0, 0, (i - 1) * 22)
    l.TextSize, l.Font = 15, BOLD
    l.TextColor3 = YEL
    l.TextStrokeTransparency = 0.4
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.RichText = true
    l.Visible = false
    l.Parent = box
    rows[i] = l
  end
  local function addLine(txt)
    table.insert(lines, 1, { txt = txt, t = os.clock() })
    while #lines > 5 do table.remove(lines) end
  end
  G.wtRadioLines = function() return lines end   -- 测试用

  ---------------------------------------------------------------- 标点：地图上的黄圈、三维里的黄菱形
  local pings = {}
  local fold = Instance.new("Folder")
  fold.Name = "WtPings"
  fold.Parent = workspace
  local function addPing(p, who, grid)
    local a = Instance.new("Part")
    a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.Transparency = true, false, false, false, 1
    a.Size = V3(0.2, 0.2, 0.2)
    a.CFrame = CFrame.new(p + V3(0, 8, 0))
    a.Parent = fold
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(140, 40)
    bb.AlwaysOnTop = true
    bb.Parent = a
    local d = Instance.new("TextLabel")
    d.BackgroundTransparency = 1
    d.Size = UD2(1, 0, 0, 20)
    d.Text = "◆"
    d.TextScaled = true
    d.TextColor3 = YEL
    d.Parent = bb
    local n = Instance.new("TextLabel")
    n.BackgroundTransparency = 1
    n.Size = UD2(1, 0, 0, 16)
    n.Position = UD2(0, 0, 0, 22)
    n.Text = grid .. " · " .. (who or "")
    n.TextSize, n.Font = 12, BOLD
    n.TextColor3 = YEL
    n.TextStrokeTransparency = 0.3
    n.Parent = bb
    local dot = nil
    if G.mapDot and G.mapRoot and G.mapUV then
      local u, v = G.mapUV(p.X, p.Z)
      local marks = G.mapRoot:FindFirstChild("Marks") or G.mapRoot
      local ok, dd = pcall(G.mapDot, marks, u, v, 12, YEL, "", 8)
      if ok then dot = dd end
    end
    table.insert(pings, { a = a, dot = dot, t = os.clock() })
    while #pings > 6 do
      local old = table.remove(pings, 1)
      if old.a then old.a:Destroy() end
      if old.dot then old.dot:Destroy() end
    end
  end

  ---------------------------------------------------------------- 无线电菜单（O）
  local MSG = { "need", "follow", "ok", "no", "retreat", "enemy", "attack", "defend" }
  local menu = Instance.new("Frame")
  menu.Name = "RadioMenu"
  menu.Size = UDim2.fromOffset(260, 24 + #MSG * 24)
  menu.Position = UD2(0, 16, 0.42, -24 - #MSG * 24 - 10)
  menu.BackgroundColor3, menu.BackgroundTransparency, menu.BorderSizePixel = RGB(10, 12, 14), 0.25, 0
  menu.Visible = false
  menu.Parent = gui
  do
    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UD2(1, -12, 0, 22)
    tl.Position = UD2(0, 8, 0, 2)
    tl.Text = T("wtr.menu")
    tl.TextSize, tl.Font, tl.TextColor3 = 13, BOLD, YEL
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Parent = menu
    for i, k in ipairs(MSG) do
      local l = Instance.new("TextLabel")
      l.BackgroundTransparency = 1
      l.Size = UD2(1, -12, 0, 22)
      l.Position = UD2(0, 8, 0, 2 + i * 24)
      l.Text = i .. "   " .. T("wtr." .. k, "…")
      l.TextSize, l.Font, l.TextColor3 = 14, MED, WHITE
      l.TextXAlignment = Enum.TextXAlignment.Left
      l.Parent = menu
    end
  end
  local menuT = 0
  G.radioOpen = function() return menu.Visible end

  -- 准星对着哪（开车：瞄准点；开飞机：镜头前方打到的地面；步行：鼠标指的地方）
  local function aimPoint()
    local st = G.drive
    if st and st.aimPt then return st.aimPt end
    local cam = workspace.CurrentCamera
    local o, d = cam.CFrame.Position, cam.CFrame.LookVector
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = { fold }
    if me.Character then table.insert(ex, me.Character) end
    rp.FilterDescendantsInstances = ex
    local res = workspace:Raycast(o, d * 30000, rp)
    return res and res.Position or (o + d * 3000)
  end
  local function myPos()
    local st = G.drive
    if st and st.root then return st.root.Position end
    local ch = me.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or workspace.CurrentCamera.CFrame.Position
  end
  local function nearestPoint(p)
    local best, bd = nil, math.huge
    for _, pt in ipairs(Map.POINTS or {}) do
      local d = (Vector2.new(pt.x, pt.z) - Vector2.new(p.X, p.Z)).Magnitude
      if d < bd then best, bd = pt, d end
    end
    return best and best.id or "?"
  end
  local function sendRadio(i)
    local k = MSG[i]
    if not k then return end
    local arg = nil
    local pos = nil
    if k == "need" then pos = myPos() arg = gridRef(pos.X, pos.Z)
    elseif k == "enemy" then pos = aimPoint() arg = gridRef(pos.X, pos.Z)
    elseif k == "attack" or k == "defend" then arg = nearestPoint(aimPoint()) end
    G.R.Act:FireServer("wtRadio", k, arg, pos)
  end

  UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.O then
      menu.Visible = not menu.Visible
      menuT = os.clock()
    elseif k == Enum.KeyCode.I then
      local p = aimPoint()
      G.R.Act:FireServer("wtPing", p)
    elseif menu.Visible then
      local nums = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8 }
      local i = nums[k.Name]
      if i then
        menu.Visible = false
        sendRadio(i)
      elseif k == Enum.KeyCode.Escape then
        menu.Visible = false
      end
    end
  end)

  ---------------------------------------------------------------- 服务器转发来的
  G.R.Drive.OnClientEvent:Connect(function(m)
    if type(m) ~= "table" then return end
    if m.op == "wtPing" and typeof(m.p) == "Vector3" then
      local grid = gridRef(m.p.X, m.p.Z)
      addPing(m.p, m.from, grid)
      addLine(T("wtr.pinged", m.from or "?", grid))
      if G.sfx then pcall(G.sfx, "uiClick") end
    elseif m.op == "wtRadio" and type(m.k) == "string" then
      addLine(T("wtr.line", m.from or "?", T("wtr." .. m.k, m.arg or "")))
      if typeof(m.p) == "Vector3" then addPing(m.p, m.from, gridRef(m.p.X, m.p.Z)) end
      if G.sfx then pcall(G.sfx, "uiClick") end
    end
  end)

  G.frameConn("WtComms", function()
    local t = os.clock()
    for i = #lines, 1, -1 do if t - lines[i].t > 8 then table.remove(lines, i) end end
    for i, r in ipairs(rows) do
      local L = lines[i]
      r.Visible = L ~= nil
      if L then
        r.Text = L.txt
        r.TextTransparency = math.clamp((t - L.t - 6.5) / 1.5, 0, 1)
      end
    end
    for i = #pings, 1, -1 do
      local P = pings[i]
      if t - P.t > 10 then
        if P.a then P.a:Destroy() end
        if P.dot then P.dot:Destroy() end
        table.remove(pings, i)
      end
    end
    if menu.Visible and t - menuT > 6 then menu.Visible = false end   -- 开着不选：六秒自己收起
  end)
end

return WtComms
