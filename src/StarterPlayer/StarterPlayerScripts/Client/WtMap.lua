-- 全面大战场（客户端）——M 键大地图页（用户 11-25：「交战给我改成这样的画面 按m放大地图」「按m打开地图是这样的」——
--   战雷那张图：左边一栏这一局的情况、出击阵容、任务目标；右边一张带网格坐标的大地图）
--   · 战斗中按 B 打开 / 关上（开坦克时 M 是烟幕弹——用户 11-25「烟幕改成m」；开喷气机 B 是机轮刹车、M 是鼠标瞄准，不开）；
--     观战、开直升机时 M 也能开；Esc 关；机库里不开
--   · 右边：MapUI 那张图（同小地图、部署界面是同一张，挂过来、关的时候挂回小地图），盖 10 × 10 的网格，行 A～J、列 1～10
--   · 左边：模式和阶段、剩余时间、我的 SP；目标据点（谁的、在不在争夺）；出击阵容出过的车（出了几次、备用还剩几次）
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local WtMap = {}

function WtMap.init(G)
  local TH = require(RS:WaitForChild("Theme"))
  local me = Players.LocalPlayer
  local RGB = Color3.fromRGB
  local function L(zh, en) return (G.lang == "en") and en or zh end
  local open = false

  local gui = Instance.new("ScreenGui")
  gui.Name = "WtMap"
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.DisplayOrder = 9
  gui.Enabled = false
  gui.Parent = me:WaitForChild("PlayerGui")
  local dim = Instance.new("Frame")
  dim.Size = UDim2.fromScale(1, 1)
  dim.BackgroundColor3, dim.BackgroundTransparency, dim.BorderSizePixel = RGB(6, 8, 10), 0.25, 0
  dim.Parent = gui
  local function frame(parent, size, pos, col, tr)
    local f = Instance.new("Frame")
    f.Size, f.Position = size, pos or UDim2.new()
    f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = col or TH.C.PANEL, tr or 0, 0
    f.Parent = parent
    return f
  end
  local function text(parent, s, size, pos, ts, col, font, xa)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text, t.Size, t.Position = s, size, pos or UDim2.new()
    t.TextSize, t.TextColor3, t.Font = ts or TH.S.body, col or TH.C.TEXT, font or TH.F.body
    t.TextXAlignment = xa or Enum.TextXAlignment.Left
    t.TextStrokeTransparency = 0.6
    t.Parent = parent
    return t
  end
  -- 左栏
  local LW = 320
  local left = frame(dim, UDim2.new(0, LW, 1, -120), UDim2.new(0, 28, 0, 60), TH.C.PANEL, 0.12)
  left.Name = "Side"
  TH.corner(left)
  TH.stroke(left)
  local title = text(left, L("战场地图", "BATTLE MAP"), UDim2.new(1, -24, 0, 30), UDim2.new(0, 12, 0, 8), TH.S.title, TH.C.TEXT, TH.F.title)
  title.Name = "Title"
  local info = text(left, "", UDim2.new(1, -24, 0, 60), UDim2.new(0, 12, 0, 42), TH.S.small, TH.C.MUTE, TH.F.bold)
  info.Name = "Info"
  info.TextYAlignment = Enum.TextYAlignment.Top
  info.TextWrapped = true
  local sec1 = text(left, L("目标", "OBJECTIVES"), UDim2.new(1, -24, 0, 20), UDim2.new(0, 12, 0, 108), TH.S.sub, TH.C.TEXT, TH.F.bold)
  local objList = frame(left, UDim2.new(1, -24, 0, 150), UDim2.new(0, 12, 0, 132), TH.C.BG, 1)
  objList.Name = "Objectives"
  local sec2 = text(left, L("出过的车", "SPAWNED"), UDim2.new(1, -24, 0, 20), UDim2.new(0, 12, 0, 292), TH.S.sub, TH.C.TEXT, TH.F.bold)
  local vehList = frame(left, UDim2.new(1, -24, 0, 200), UDim2.new(0, 12, 0, 316), TH.C.BG, 1)
  vehList.Name = "Spawned"
  local hint = text(dim, L("B / Esc 关闭", "B / Esc to close"), UDim2.new(0, 300, 0, 20), UDim2.new(0, 28, 1, -50), TH.S.small, TH.C.MUTE, TH.F.bold)
  hint.Name = "Hint"
  sec1.Name, sec2.Name = "SecObj", "SecVeh"
  -- 右边：大地图 + 网格
  local mapBox = frame(dim, UDim2.fromOffset(600, 600), UDim2.new(0, 28 + LW + 40, 0, 60), RGB(0, 0, 0), 0.2)
  mapBox.Name = "MapBox"
  TH.stroke(mapBox)
  local holder = frame(mapBox, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  holder.Name = "Holder"
  holder.ClipsDescendants = true
  local grid = frame(mapBox, UDim2.fromScale(1, 1), nil, RGB(0, 0, 0), 1)
  grid.Name = "Grid"
  grid.ZIndex = 20
  local ROWS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }
  for i = 1, 9 do
    local v = frame(grid, UDim2.new(0, 1, 1, 0), UDim2.fromScale(i / 10, 0), RGB(255, 255, 255), 0.82)
    v.ZIndex = 20
    local h = frame(grid, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, i / 10), RGB(255, 255, 255), 0.82)
    h.ZIndex = 20
  end
  for i = 1, 10 do   -- 行 A～J 写在左边、列 1～10 写在上边（战雷那样）
    local r = text(mapBox, ROWS[i], UDim2.new(0, 20, 0.1, 0), UDim2.new(0, -24, (i - 1) / 10, 0), TH.S.small, TH.C.TEXT, TH.F.bold, Enum.TextXAlignment.Center)
    r.Name = "Row_" .. ROWS[i]
    local c = text(mapBox, tostring(i), UDim2.new(0.1, 0, 0, 18), UDim2.new((i - 1) / 10, 0, 0, -20), TH.S.small, TH.C.TEXT, TH.F.bold, Enum.TextXAlignment.Center)
    c.Name = "Col_" .. i
  end
  -- 按屏幕大小摆：地图是正方形，左栏右边能放多大放多大
  local function layout()
    local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local s = math.max(200, math.min(vs.Y - 110, vs.X - (28 + LW + 40) - 28))
    mapBox.Size = UDim2.fromOffset(s, s)
  end
  -- 格子坐标（小地图、地图上的点说位置用）：世界坐标 → 「C7」
  function G.mapGridRef(x, z)
    if not G.mapUV then return "" end
    local u, v = G.mapUV(x, z)
    local col = math.clamp(math.floor(u * 10) + 1, 1, 10)
    local row = math.clamp(math.floor(v * 10) + 1, 1, 10)
    return ROWS[row] .. col
  end

  local function sideName(t)
    local mine = me:GetAttribute("Side")
    if t == nil or t == "none" or t == "" then return L("中立", "Neutral"), TH.C.MUTE end
    if t == mine then return L("我方", "Ours"), TH.C.FRIEND end
    return L("敌方", "Enemy"), TH.C.FOE
  end
  local function fill()
    local S = G.S or {}
    for _, c in ipairs(objList:GetChildren()) do c:Destroy() end
    for _, c in ipairs(vehList:GetChildren()) do c:Destroy() end
    local mode = workspace:GetAttribute("WtMode")
    local modeName = (mode == "sb" and L("全真", "Simulator")) or (mode == "rb" and L("历史", "Realistic")) or L("街机", "Arcade")
    local left = S.left and string.format("%d:%02d", math.floor(S.left / 60), math.floor(S.left % 60)) or "--:--"
    local w = S.wt
    info.Text = string.format(L("陆战 · %s · %s\n剩余 %s · 我的 SP %d", "Ground · %s · %s\n%s left · SP %d"), modeName,
      (S.phase == "prep") and L("准备阶段", "Preparation") or L("交战中", "Battle"), left, w and w.sp or 0)
    -- 目标据点
    local y = 0
    for _, p in ipairs(S.points or {}) do
      if y > 130 then break end
      local nm, col = sideName(p.owner)
      local row = frame(objList, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, y), TH.C.BG, 0.5)
      row.Name = "Point_" .. tostring(p.id)
      local badge = frame(row, UDim2.fromOffset(22, 22), UDim2.fromOffset(1, 1), col, 0.15)
      TH.corner(badge, 2)
      text(badge, tostring(p.id), UDim2.fromScale(1, 1), nil, TH.S.small, RGB(16, 18, 20), TH.F.title, Enum.TextXAlignment.Center)
      local st = nm
      if p.act and (p.prog or 0) > 0 and (p.prog or 0) < 1 then st = st .. L(" · 争夺中 ", " · contested ") .. math.floor((p.prog or 0) * 100) .. "%" end
      if p.locked then st = st .. L(" · 未开放", " · locked") end
      local where = ""
      local MP = G.Map and G.Map.POINTS
      if MP then
        for _, q in ipairs(MP) do if q.id == p.id and q.x then where = "  " .. G.mapGridRef(q.x, q.z) end end
      end
      text(row, st .. where, UDim2.new(1, -32, 1, 0), UDim2.fromOffset(30, 0), TH.S.small, col, TH.F.bold)
      y += 26
    end
    if y == 0 then text(objList, L("这张图没有据点", "No objectives"), UDim2.new(1, 0, 0, 20), nil, TH.S.small, TH.C.MUTE) end
    -- 出过的车（WtMatch 推的 S.wt：出了几次、备用还剩几次）
    y = 0
    for _, k in ipairs(w and w.order or {}) do
      if y > 180 then break end
      local n = (w.ln and w.ln[k]) or 0
      local left2 = math.max(0, 1 + (w.backup or 1) - n)
      local nm = (G.T and G.T("tree." .. k)) or k
      if nm == "tree." .. k then nm = (G.T and G.T("veh." .. k)) or k end
      local row = text(vehList, string.format(L("%s　出了 %d 次 · 还能出 %d 次", "%s  spawned %d · %d left"), nm, n, left2),
        UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, y), TH.S.small, (left2 > 0) and TH.C.TEXT or TH.C.MUTE, TH.F.bold)
      row.Name = "Veh_" .. k
      y += 24
    end
    if y == 0 then text(vehList, L("这一局还没出车", "Nothing spawned yet"), UDim2.new(1, 0, 0, 20), nil, TH.S.small, TH.C.MUTE) end
  end

  local function setOpen(on)
    if on == open then return end
    open = on
    gui.Enabled = on
    if on then
      layout()
      fill()
      if G.mapMount then G.mapMount(holder, UDim2.fromScale(1, 1)) end
    else
      local P = G.hudParts
      if G.mapMount and P then G.mapMount(P.miniClip or P.miniBox, UDim2.fromScale(1, 1)) end
    end
  end
  G.wtMapOpen = function() return open end
  G.wtMapToggle = function(on) if on == nil then on = not open end setOpen(on) end
  local function canOpen()
    if G.hangarActive and G.hangarActive() then return false end
    if G.settingsShown and G.settingsShown() then return false end
    local S = G.S
    return S ~= nil and (S.phase == "battle" or S.phase == "prep")
  end
  UIS.InputBegan:Connect(function(io, gp)
    if gp or UIS:GetFocusedTextBox() then return end
    local k = io.KeyCode
    if k == Enum.KeyCode.Escape and open then setOpen(false) return end
    local jet = G.fly ~= nil and G.fly.d and G.fly.d.kind == "jet"
    local ground = G.drive ~= nil
    if (k == Enum.KeyCode.B and not jet and not (G.interiorOn and G.interiorOn())) or (k == Enum.KeyCode.M and not jet and not ground) then
      if open then setOpen(false) elseif canOpen() then setOpen(true) end
    end
  end)
  -- 开着的时候每秒刷新一次左栏；机库开了 / 一局结束就关
  task.spawn(function()
    while true do
      task.wait(1)
      if open then
        if not canOpen() then setOpen(false) else fill() layout() end
      end
    end
  end)
end

return WtMap
